local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
--- the utf8 global is not available, so we polyfill utf8.offset so we can correctly find prefixes of utf8 strings
---@param str string
---@param index number
---@return number|nil
local function Utf8Offset(str, index)
	local len = #str

	if index <= 0 or index > len then
		return nil -- Out of bounds
	end

	-- Move forward to the nth character
	local count = 0
	for i = 1, len do
		local byte = string.byte(str, i)
		local isContinuationByte = byte >= 128 and byte < 192
		if not isContinuationByte then
			count = count + 1
			if count == index then
				return i
			end
		end
	end

	return nil -- If the nth character is not found
end

---@param table table<string, string> raw data table with character name prefixes as keys
---@param length number the number of complete characters to include in the prefix
---@return fun(characterName: string):string|nil getChunk function to retrieve a character chunk by prefix using a complete character name
local function getChunkLookup(table, length)
	return function(characterName)
		local startOfNextCharacter = Utf8Offset(characterName, length + 1)

		local prefix
		if startOfNextCharacter == nil then
			prefix = characterName
		else
			prefix = string.sub(characterName, 1, startOfNextCharacter - 1)
		end

		return table[prefix]
	end
end

local lookup = {'Priest-Holy','Priest-Shadow','Mage-Frost','Warlock-Destruction','Warrior-Fury','Paladin-Holy','Paladin-Retribution','Hunter-BeastMastery','DeathKnight-Unholy','Warrior-Arms','Warrior-Protection','Druid-Restoration','Druid-Balance','Unknown-Unknown','Hunter-Marksmanship','Shaman-Elemental','Shaman-Enhancement','Hunter-Survival','Evoker-Preservation','Evoker-Devastation','DemonHunter-Devourer','Monk-Brewmaster','DeathKnight-Blood','Druid-Guardian','DeathKnight-Frost','DemonHunter-Vengeance','Monk-Windwalker','Warlock-Affliction','Druid-Feral','Rogue-Subtlety','Rogue-Assassination','Paladin-Protection','DemonHunter-Havoc','Priest-Discipline','Warlock-Demonology',}
local provider = {region='US',realm='Farstriders',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Absolon:BAAALgAECgYJEgAAAA==.',
Ae='Aedelaide:BAAALgAECgEJAgAAAA==.Aelar:BAAALgADCgEJAQAAAA==.Aellynn:BAABLgAECn8zAAMBAAgJMAwiMABAAQABAAgJMAwiMABAAQACAAEJXgAqbAAXAAAAAA==.Aerir:BAACLgAFFH8dAAIDAAUJCBMXTgA+AQADAAUJCBMXTgA+AQAuAAQKfy4AAgMACQl0GdxbACYCAAMACQl0GdxbACYCAAAA.Aerithar:BAAALgADCgEJAQAAAA==.Aesirr:BAABLgAECn8TAAIEAAgJuQdSFQDxAAAEAAgJuQdSFQDxAAAAAA==.',
Ah='Ahmari:BAAALgADCgQJBwAAAA==.',
Ak='Akamini:BAAALgAECgYJBwAAAA==.',
Al='Alandris:BAABLgAECn8dAAIFAAgJJwV+VgDpAAAFAAgJJwV+VgDpAAAAAA==.Alerya:BAAALgAECgEJAQAAAA==.Alinie:BAACLgAFFH8GAAMGAAMJGCGYIgD+AAAGAAMJGCGYIgD+AAAHAAMJrBwjWwDkAAAuAAQKfxYAAgYACAkKJVgHAPcCAAYACAkKJVgHAPcCAAAA.Alleriya:BAABLgAECn8wAAIIAAgJCQw5YAB6AQAIAAgJCQw5YAB6AQAAAA==.Allison:BAAALgADCgMJAwAAAA==.Alltheheals:BAAALgAECggJDAAAAA==.Altruis:BAAALgADCgIJAgABLgAFFAQJBwAJAAwQAA==.',
Am='Amarawyn:BAABLgAECn8jAAIFAAcJ6BYBKgCoAQAFAAcJ6BYBKgCoAQAAAA==.Ambulance:BAAALgADCgEJAQAAAA==.Amoragan:BAABLgAECn8gAAQKAAkJHhq5HABrAQAFAAkJcBjaOADDAQAKAAcJnxa5HABrAQALAAEJdAq+TQA2AAAAAA==.Amoravin:BAAALgAECgcJBwAAAA==.Amyra:BAAALgAECgQJAwAAAA==.',
An='Andriela:BAABLgAECn8XAAMMAAkJEQ2mOwCcAQAMAAkJEQ2mOwCcAQANAAEJ8wEzngAZAAAAAA==.',
Ap='Apexy:BAABLgAECn8fAAIDAAYJzAWf3ADZAAADAAYJzAWf3ADZAAAAAA==.',
Ar='Arashikaze:BAAALgAECggJEAAAAA==.Ardy:BAAALgAECgEJAQABLgAFFAQJBwAJAAwQAA==.',
As='Asurion:BAAALgAECgEJAQAAAA==.',
Au='Augi:BAAALgADCgMJAwAAAA==.Augidget:BAABLgAECn8nAAICAAkJbhewEwArAgACAAkJbhewEwArAgAAAA==.',
Av='Avgo:BAAALgAECgMJAwABLgAECgYJDgAOAAAAAA==.Avilen:BAABLgAECn8nAAIIAAkJIguQTgCqAQAIAAkJIguQTgCqAQAAAA==.Aviris:BAAALgAECgcJEwABLgAECgkJHgAGABkeAA==.',
Ay='Ayuzi:BAAALgAECgYJBwAAAA==.',
Az='Azarri:BAAALgAECgcJBwAAAA==.',
Ba='Badsilk:BAAALgAECgYJEwAAAA==.Balinteen:BAABLgAECn8ZAAMIAAcJrQUukgAOAQAIAAcJrQUukgAOAQAPAAEJQAOxQgAbAAAAAA==.Barktwain:BAAALgAECgQJBAAAAA==.Bastael:BAABLgAECn8iAAIGAAkJtyMNBABSAwAGAAkJtyMNBABSAwAAAA==.Bayus:BAAALgADCgIJAgAAAA==.',
Be='Benchie:BAAALgAECgEJAQABLgAECgkJLwAQAOQaAA==.Bendyy:BAABLgAECn8jAAIDAAkJcRx5MABQAgADAAkJcRx5MABQAgAAAA==.',
Bh='Bharani:BAAALgADCgcJBwAAAA==.',
Bi='Biopaindr:BAABLgAECn8iAAINAAgJIhInJgCPAQANAAgJIhInJgCPAQAAAA==.Bitxi:BAABLgAECn8fAAIIAAYJXAh0mwD7AAAIAAYJXAh0mwD7AAAAAA==.',
Bl='Bloodtusk:BAAALgAECgYJBgAAAA==.',
Bo='Boldbane:BAAALgAECgYJCAAAAA==.Boozo:BAAALgAECgIJBAAAAA==.',
Br='Brocklee:BAABLgAECn8gAAIRAAkJahF+DQDLAQARAAkJahF+DQDLAQAAAA==.',
Bu='Bubbaman:BAABLgAECn8eAAMPAAYJLAaoHgCuAAAPAAYJLAaoHgCuAAAIAAEJlQJO2AArAAAAAA==.Burda:BAABLgAECn8rAAMSAAkJ6Re/DwAvAgASAAkJ6Re/DwAvAgAPAAEJZg8BOwAuAAAAAA==.',
By='Byzinteen:BAAALgAECgEJAQAAAA==.',
Ca='Caenae:BAABLgAECn8ZAAIIAAYJIwSfsQDPAAAIAAYJIwSfsQDPAAAAAA==.Cattlerage:BAAALgADCgUJBQABLgAFFAQJBwAJAAwQAA==.',
Ce='Celestial:BAAALgAECgEJAgAAAA==.Cephira:BAAALgAECgEJAQAAAA==.',
Ch='Chandris:BAAALgADCgIJAgAAAA==.Chrissy:BAAALgAECgYJBgAAAA==.',
Ci='Ciannie:BAAALgADCgQJCAAAAA==.',
Cl='Clamor:BAAALgAECgQJDgAAAA==.',
Co='Cogiaugi:BAAALgAECgEJAQAAAA==.Coletrain:BAAALgAECgYJEAAAAA==.Corri:BAABLgAECn8VAAMTAAUJXRypGgAmAQATAAQJ5BmpGgAmAQAUAAUJvRLDEADxAAAAAA==.Corriandis:BAAALgAECgQJBQAAAA==.',
Cr='Credon:BAABLgAECn8fAAIMAAYJPBRsRwBnAQAMAAYJPBRsRwBnAQAAAA==.Crixxe:BAAALgAECgQJBwAAAA==.',
Da='Davin:BAAALgAECgYJBwAAAA==.',
De='Dereda:BAAALgAECgEJAQAAAA==.',
Dh='Dhellia:BAAALgAECgYJCgAAAA==.',
Di='Dierlyn:BAABLgAECn8kAAIBAAcJZxQ/IgCjAQABAAcJZxQ/IgCjAQAAAA==.Dirtytaters:BAABLgAECn8fAAICAAYJyQXvTwDGAAACAAYJyQXvTwDGAAAAAA==.Divastating:BAAALgAECgQJCwABLgAECgUJGQAIAMECAA==.',
Do='Doko:BAAALgAECgIJAgAAAA==.Doró:BAABLgAECn8eAAIVAAgJehjKLwD8AQAVAAgJehjKLwD8AQABLgAECgkJLQAEAL4fAA==.',
Dt='Dtothed:BAAALgAECgQJCgAAAA==.',
Dw='Dwarfred:BAABLgAECn8hAAIQAAcJGh38GwD0AQAQAAcJGh38GwD0AQAAAA==.Dwimor:BAABLgAECn8cAAIIAAcJlg+NewA7AQAIAAcJlg+NewA7AQAAAA==.',
['Dô']='Dôro:BAAALgAECgYJBgABLgAECgkJLQAEAL4fAA==.',
Ea='Earadin:BAAALgAECgQJBAAAAA==.',
Ec='Ecthelorn:BAAALgADCgMJBAAAAA==.',
El='Elasong:BAAALgAECgcJEgAAAA==.Elletal:BAAALgADCgEJAQABLgAECgkJMgAWAD8TAA==.Elmö:BAAALgAECgYJCgAAAA==.Elrarebriel:BAAALgAECgMJAwAAAA==.',
Em='Emberstorm:BAAALgADCgQJBAAAAA==.',
Fa='Fairamir:BAAALgADCgQJBgAAAA==.Fayona:BAAALgADCgcJDgAAAA==.',
Fe='Felystra:BAAALgAECgIJBQAAAA==.',
Fi='Fizzbot:BAAALgAECgEJAgABLgAFFAUJHQAJAHcbAA==.Fizzlyn:BAACLgAFFH8dAAMJAAUJdxuPQABhAQAJAAQJbRuPQABhAQAXAAMJzxvoKACZAAAuAAQKfy4AAwkACQlxIhg3ABsCAAkACQlxIhg3ABsCABcAAwkfG0s9AJAAAAAA.',
Fl='Fluffsmcgee:BAAALgADCgkJDgAAAA==.',
Fr='Fredrick:BAAALgADCgcJCAAAAA==.Frieza:BAAALgAECgQJBgAAAA==.',
Fu='Furr:BAAALgAFFAEJAgABLgAFFAgJGgADAKkSAA==.',
Ga='Galdora:BAAALgADCgcJEQAAAA==.Galedriel:BAAALgAECgYJEAAAAA==.',
Gh='Ghosthunter:BAAALgADCgkJDwAAAA==.',
Gi='Giizmo:BAAALgAECgEJAQAAAA==.',
Gr='Gragdal:BAAALgADCggJCgAAAA==.Grandpa:BAAALgAECgEJAgABLgAECgYJIAAIAOUeAA==.Grewsöm:BAACLgAFFH8HAAMJAAQJDBBsowDCAAAJAAMJDBBsowDCAAAXAAEJAADSSQAAAAAuAAQKfyMAAwkACQnrIzwUAMYCAAkACQm5IzwUAMYCABcACAnOIKgJAG8CAAAA.Grotusque:BAABLgAECn8+AAIYAAkJRhf5CwARAgAYAAkJRhf5CwARAgAAAA==.',
Gu='Gullugren:BAAALgAECgkJCAAAAA==.Gutterdoxy:BAAALgADCgMJAwAAAA==.',
Ha='Hadiirn:BAABLgAECn8dAAIVAAYJ9RCiiAABAQAVAAYJ9RCiiAABAQAAAA==.Haiiro:BAABLgAECn8jAAIWAAkJyBd0EwAMAgAWAAkJyBd0EwAMAgAAAA==.Hardim:BAABLgAECn8cAAIIAAcJrAygcwBNAQAIAAcJrAygcwBNAQAAAA==.Hardwood:BAAALgAECgQJBwAAAA==.Hargen:BAAALgAECgMJAwAAAA==.Harknesse:BAABLgAECn8aAAIZAAYJ3A8hFgAZAQAZAAYJ3A8hFgAZAQAAAA==.Hatermage:BAAALgAECgYJDwAAAA==.Hazzrel:BAAALgAECgYJDQAAAA==.',
He='Heftychi:BAAALgAECgIJAgAAAA==.Heftydh:BAABLgAECn8vAAIaAAgJ2B+OBABlAgAaAAgJ2B+OBABlAgAAAA==.Hewhospins:BAABLgAECn8yAAMWAAkJPxMiGADeAQAWAAkJPxMiGADeAQAbAAEJbQqulwAuAAAAAA==.',
Ho='Hog:BAAALgAFFAEJAQABLgAFFAgJHwALAOgiAA==.Horizontal:BAAALgADCgcJBwABLgADCgcJBwAOAAAAAA==.',
Hr='Hranu:BAAALgAECgcJEgABLgAFFAMJDwAMABUXAA==.',
Hy='Hydraulicman:BAAALgAECgUJDwAAAA==.Hyzer:BAAALgAECgYJBgABLgAECggJEAAOAAAAAA==.',
Id='Idget:BAAALgADCgEJAQAAAA==.',
Ig='Igknight:BAAALgAECgEJAQAAAA==.',
Im='Image:BAAALgAECgYJCQABLgAFFAUJFgAHACocAA==.',
Ja='Jacksmite:BAAALgADCgEJAQAAAA==.Jasmirana:BAAALgAECggJEwAAAA==.',
Je='Jemano:BAAALgADCgEJAQAAAA==.',
Ji='Jirenr:BAABLgAECn8kAAIbAAcJ+QdbQgDnAAAbAAcJ+QdbQgDnAAAAAA==.',
Jo='Jolage:BAABLgAECn8fAAIDAAcJ5BF/hQBmAQADAAcJ5BF/hQBmAQAAAA==.Jolreal:BAACLgAFFH8NAAISAAMJ0Bx7GAD7AAASAAMJ0Bx7GAD7AAAuAAQKf0UAAxIACAmDI8wHAJ4CABIACAnPIMwHAJ4CAA8ABwlQIkUUAJICAAAA.',
Ju='Julez:BAABLgAECn8hAAIIAAYJ3xFaewA7AQAIAAYJ3xFaewA7AQAAAA==.Julezara:BAAALgAECgYJEAAAAA==.Julezdruid:BAAALgAECgIJAgAAAA==.Junkai:BAACLgAFFH8WAAIHAAUJKhzUKABTAQAHAAUJKhzUKABTAQAuAAQKfy4AAgcACAn+Iy0bAMYCAAcACAn+Iy0bAMYCAAAA.',
Ka='Kathanial:BAAALgADCgUJBgAAAA==.Katiagrimm:BAAALgADCgQJCAAAAA==.Kawi:BAAALgAECgMJAwABLgAECgkJIAARAGoRAA==.',
Ke='Keco:BAABLgAECn8ZAAIIAAUJwQK70wCOAAAIAAUJwQK70wCOAAAAAA==.Kelenar:BAAALgAECgMJAwAAAA==.Kennie:BAABLgAECn8kAAMEAAkJKQ0HDABwAQAEAAkJKQ0HDABwAQAcAAMJIAa1HACNAAAAAA==.',
Kl='Kladibo:BAAALgAECgEJAQABLgAECgYJBgAOAAAAAA==.Kladivo:BAAALgAECgYJBgAAAA==.',
Kn='Knorr:BAAALgAECgcJDAAAAA==.',
Ko='Korthaz:BAAALgADCgIJAgAAAA==.',
Ku='Kuwanlalenta:BAAALgADCgcJBQAAAA==.',
Kw='Kwansu:BAAALgAECgQJBAABLgAECgYJBgAOAAAAAA==.',
La='Lahlania:BAABLgAECn8WAAIdAAYJsR0xEACiAQAdAAYJsR0xEACiAQAAAA==.Laura:BAAALgAECgIJAgAAAA==.',
Le='Lexis:BAAALgADCgYJBgAAAA==.',
Li='Lilyda:BAAALgADCggJBgAAAA==.',
Lo='Lolann:BAAALgADCgUJCAAAAA==.',
Ly='Lyia:BAAALgADCgEJAQAAAA==.',
Ma='Machette:BAABLgAECn8aAAIHAAYJLxjIiQBRAQAHAAYJLxjIiQBRAQAAAA==.Mailaria:BAABLgAECn8oAAIaAAkJyw9lDACBAQAaAAkJyw9lDACBAQAAAA==.Maithe:BAAALgADCgcJBwAAAA==.Majesti:BAAALgADCggJBwAAAA==.Malakar:BAACLgAFFH8GAAIeAAMJbQrSJQDkAAAeAAMJbQrSJQDkAAAuAAQKfyMAAx4ABwm7GxQiAOgBAB4ABwlrFxQiAOgBAB8ABgmHGdALAGoBAAAA.Malvolio:BAAALgADCgMJAwAAAA==.Mantoecore:BAAALgADCgcJCAAAAA==.Marellaa:BAABLgAECn8UAAIBAAYJzAu+PADxAAABAAYJzAu+PADxAAAAAA==.Markers:BAAALgADCgIJAgAAAA==.',
Mc='Mcsplatapus:BAAALgAECgYJBQAAAA==.',
Me='Meingsolin:BAABLgAECn8vAAIbAAYJ5xaJKwBUAQAbAAYJ5xaJKwBUAQAAAA==.Meseeker:BAAALgAECgcJBwAAAA==.Mezagog:BAAALgADCgcJEAAAAA==.',
Mi='Midknight:BAAALgAECgUJBgAAAA==.Miggylosoh:BAAALgAECgMJCwAAAA==.Minizoomies:BAAALgAECgMJBgAAAA==.',
Mo='Momo:BAAALgADCgkJFgABLgAECgIJAgAOAAAAAA==.Moochi:BAAALgAECgEJAQAAAA==.',
My='Mygourdness:BAABLgAECn8VAAIMAAYJ+ATghwCeAAAMAAYJ+ATghwCeAAAAAA==.Myuk:BAABLgAECn8jAAISAAkJBB0qDQBPAgASAAkJBB0qDQBPAgAAAA==.',
Mz='Mzskywalker:BAAALgAECgUJBQAAAA==.',
Na='Naminay:BAABLgAECn8WAAIGAAgJfxmwFwBAAgAGAAgJfxmwFwBAAgAAAA==.Narbash:BAAALgAECgQJBAAAAA==.Nasrullah:BAAALgADCgkJDQAAAA==.Natalie:BAAALgAECgEJAQAAAA==.Natral:BAAALgAECgEJAQAAAA==.',
Ne='Nekia:BAAALgAECgEJAQAAAA==.Neroz:BAABLgAECn89AAIVAAkJJhzZFACSAgAVAAkJJhzZFACSAgAAAA==.Nerppie:BAABLgAECn84AAIGAAkJ1B/SBgAWAwAGAAkJ1B/SBgAWAwAAAA==.Nevershark:BAAALgAECgUJBQAAAA==.',
Ni='Nightfallz:BAAALgADCgUJBQAAAA==.Nina:BAABLgAECn8ZAAIHAAcJdRpRTwD0AQAHAAcJdRpRTwD0AQAAAA==.Nixah:BAAALgAECgUJDQAAAA==.',
Nk='Nkript:BAABLgAECn8qAAMIAAkJgRc0IQBWAgAIAAkJgRc0IQBWAgAPAAYJpgiJTwARAQAAAA==.',
No='Nortel:BAAALgAECgYJDgAAAA==.',
Oh='Ohgourdness:BAAALgADCgcJBwABLgAECgYJFQAMAPgEAA==.',
On='Onari:BAABLgAECn8mAAIBAAkJ6h24CQC/AgABAAkJ6h24CQC/AgAAAA==.',
Or='Orious:BAAALgADCgYJBgAAAA==.',
Pa='Paine:BAAALgAECgEJAQAAAA==.Pandagang:BAAALgADCgQJBQAAAA==.',
Pe='Peezee:BAABLgAECn8XAAMHAAgJ9w+7ggBeAQAHAAgJbw27ggBeAQAgAAYJSg1/JwDNAAAAAA==.Perce:BAABLgAECn82AAMGAAkJACAoBwARAwAGAAkJACAoBwARAwAHAAQJJxk1mAA4AQAAAA==.Peyotte:BAABLgAECn8VAAILAAgJgB9IDQAMAgALAAgJgB9IDQAMAgABLgAFFAQJBwAQAJQUAA==.',
Pf='Pfemme:BAABLgAECn8qAAIIAAkJDx7sGACEAgAIAAkJDx7sGACEAgAAAA==.',
Pp='Pp:BAAALgAECgQJBAAAAA==.',
Ps='Psych:BAAALgADCgYJBgAAAA==.',
Pu='Purian:BAAALgADCgcJDwAAAA==.',
Ra='Rainfall:BAAALgAECgIJAgAAAA==.Rami:BAAALgADCgYJBgAAAA==.',
Re='Repello:BAAALgAECgYJBwAAAA==.Reyaieleron:BAAALgAECgYJEAAAAA==.',
Ri='Ricky:BAAALgADCgEJAQAAAA==.Rivenaer:BAABLgAECn82AAMhAAkJxBC+FwC2AQAhAAkJxBC+FwC2AQAVAAEJiAJmKgEaAAAAAA==.',
Ru='Ruindsoul:BAAALgADCgcJCwAAAA==.Ruka:BAAALgADCgEJAQAAAA==.Runearne:BAAALgAECgIJAgAAAA==.Rustymark:BAACLgAFFH8LAAIIAAQJPQr9RQAQAQAIAAQJPQr9RQAQAQAuAAQKfx0AAggACQnBFGsnADYCAAgACQnBFGsnADYCAAAA.',
Sc='Scaletal:BAAALgAECgUJBQAAAA==.Schmetzy:BAAALgAECgYJCAAAAA==.Schmezzy:BAABLgAECn8cAAIJAAgJvB03RgDoAQAJAAgJvB03RgDoAQAAAA==.Scuti:BAAALgADCgcJBQAAAA==.',
Se='Sealalicious:BAABLgAECn8+AAIgAAkJrx3aBACfAgAgAAkJrx3aBACfAgAAAA==.Seenaa:BAAALgAECgMJAwAAAA==.Seân:BAAALgAECgEJAQAAAA==.',
Sh='Shallot:BAAALgADCgQJDwAAAA==.Shammywow:BAAALgAECgUJEgAAAA==.Sharkzilla:BAABLgAECn8XAAIIAAkJGx0wFwB/AgAIAAkJGx0wFwB/AgAAAA==.Shauray:BAAALgADCgYJCgAAAA==.Shine:BAABLgAECn8gAAMIAAYJ5R5WTQCuAQAIAAYJFh5WTQCuAQASAAUJ2xNpNQABAQAAAA==.Shrub:BAAALgADCgcJBwABLgAFFAkJGwAiACwhAA==.',
Si='Silksmilk:BAAALgADCgIJAgAAAA==.Siobhân:BAAALgAECgYJBgAAAA==.',
Sl='Sloppy:BAAALgAECgIJAgAAAA==.',
Sm='Smashchie:BAAALgAECgEJAQAAAA==.Smoo:BAAALgAECgUJBgAAAA==.Smythe:BAAALgADCgEJAQAAAA==.',
Sn='Snø:BAAALgAECgcJDwAAAA==.',
So='Sobol:BAAALgAFFAEJAgAAAA==.Soggyaugi:BAAALgAECgYJDQAAAA==.Solbinder:BAAALgADCgIJAgAAAA==.Soraa:BAEALgAECgUJDwABLgAECgkJHQADADIfAA==.Soulbleeder:BAAALgAECgQJBAAAAA==.',
St='Starlethia:BAAALgAECggJEwAAAA==.',
Su='Sumpnclaws:BAAALgAECgYJBgAAAA==.Sunshine:BAAALgAECgcJCwAAAA==.Sunwälker:BAAALgADCgQJBAAAAA==.',
Sy='Sybelin:BAAALgADCggJCQAAAA==.',
Ta='Tallchief:BAABLgAECn8aAAIIAAYJiBBkewA7AQAIAAYJiBBkewA7AQAAAA==.Talliah:BAAALgAECgQJBQAAAA==.Tamarynn:BAAALgADCgUJBQABLgAECggJMwABADAMAA==.Tankufrdying:BAAALgAECgUJCAAAAA==.Tarkuroth:BAAALgADCgQJBAAAAA==.Tavarien:BAAALgADCgEJAQAAAA==.Tayllana:BAAALgAECgEJAQAAAA==.',
Te='Tenjo:BAAALgAECgYJCgAAAA==.Terrier:BAAALgAECgEJAQAAAA==.',
Th='Thaerdran:BAABLgAECn8fAAIXAAcJqhevHgBUAQAXAAcJqhevHgBUAQAAAA==.',
Ti='Tierri:BAAALgAECgEJAgAAAA==.Tirriel:BAAALgADCgMJAwAAAA==.',
To='Toess:BAAALgAECgEJAQAAAA==.Tonati:BAAALgAECgMJAwAAAA==.Tonjuren:BAAALgAECgMJBwABLgAECgYJLwAbAOcWAA==.',
Tr='Travosaur:BAAALgAFFAEJAQAAAA==.Trublood:BAABLgAECn8aAAICAAYJ3QjwRwDlAAACAAYJ3QjwRwDlAAAAAA==.Truelder:BAAALgADCgIJAgAAAA==.',
Tw='Twister:BAAALgAECgQJDwAAAA==.',
Ty='Tyrra:BAAALgADCgMJAwAAAA==.',
Uk='Ukeenonme:BAAALgAECgIJAgAAAA==.',
Us='Usorloups:BAACLgAFFH8HAAIQAAQJlBSSLADTAAAQAAQJlBSSLADTAAAuAAQKfyAAAhAACQnCH4cOAHoCABAACQnCH4cOAHoCAAAA.',
Va='Vaelar:BAAALgAECgYJBgAAAA==.Valstad:BAAALgAECgYJDAAAAA==.',
Ve='Velonys:BAABLgAECn82AAQEAAkJayJ8AQDIAgAEAAgJmSN8AQDIAgAjAAYJdBaveQBBAQAcAAQJLCAAFQASAQAAAA==.Velus:BAAALgAECgQJBAAAAA==.',
Vi='Victory:BAAALgAECgEJAQAAAA==.Vintar:BAAALgADCgMJAwAAAA==.',
Vo='Volkhikos:BAAALgAECgQJBAAAAA==.',
Vy='Vyral:BAEALgAECgQJBgAAAA==.Vyu:BAAALgAECgkJBgAAAA==.',
Wa='Wanayu:BAABLgAECn8kAAIEAAkJTBkaBAA3AgAEAAkJTBkaBAA3AgAAAA==.Wanweasley:BAAALgAECgkJEQAAAA==.',
We='Weeab:BAAALgADCgEJAQAAAA==.Weezlee:BAAALgAECgQJBAAAAA==.Weh:BAABLgAECn8YAAIDAAkJryKXIwCIAgADAAkJryKXIwCIAgAAAA==.',
Wi='Wickedsham:BAAALgADCgIJAgAAAA==.Wintermourne:BAABLgAECn8eAAIZAAgJeQe7FQAdAQAZAAgJeQe7FQAdAQAAAA==.Wizagon:BAABLgAECn8XAAIUAAkJlBvGAwBBAgAUAAkJlBvGAwBBAgAAAA==.',
Wo='Woodsy:BAABLgAECn8lAAITAAkJAhzFBADOAgATAAkJAhzFBADOAgAAAA==.Wounded:BAAALgAECgEJAQAAAA==.Woundliquor:BAAALgAECgcJEQAAAA==.',
Wu='Wuinn:BAACLgAFFH8RAAMMAAQJlCAyGwBxAQAMAAQJlCAyGwBxAQANAAMJpQO0OAB7AAAuAAQKfzIAAwwACQn0Id4PALkCAAwACQn0Id4PALkCABgABwlSGGwUAKEBAAAA.',
Xe='Xemnas:BAABLgAECn86AAQJAAcJ/Q54kwA3AQAJAAcJgA14kwA3AQAZAAQJsA6DIgCnAAAXAAIJ7wF4WAAxAAAAAA==.',
Ya='Yawnday:BAAALgAECgMJAwABLgAECgcJCgAOAAAAAA==.Yawnight:BAAALgAECgcJCgAAAA==.',
Ys='Yserra:BAAALgAECgMJBAAAAA==.',
Za='Zaryala:BAAALgADCgkJKAAAAA==.',
Ze='Zenshift:BAAALgAECgMJCAAAAA==.',
Zy='Zynthia:BAABLgAECn8wAAIJAAkJ/SQIBQBQAwAJAAkJ/SQIBQBQAwAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
