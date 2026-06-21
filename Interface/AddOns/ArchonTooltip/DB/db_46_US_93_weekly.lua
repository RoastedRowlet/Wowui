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

local lookup = {'Hunter-BeastMastery','Priest-Holy','Priest-Shadow','Mage-Frost','Warlock-Destruction','Warrior-Fury','Paladin-Holy','Paladin-Retribution','Warrior-Arms','Warrior-Protection','Druid-Restoration','Druid-Balance','Shaman-Restoration','Unknown-Unknown','Hunter-Marksmanship','Shaman-Elemental','Shaman-Enhancement','Hunter-Survival','Evoker-Preservation','Evoker-Devastation','DemonHunter-Devourer','Paladin-Protection','Monk-Brewmaster','DeathKnight-Unholy','DeathKnight-Blood','Mage-Arcane','Druid-Guardian','DeathKnight-Frost','DemonHunter-Vengeance','Monk-Windwalker','Warlock-Affliction','Druid-Feral','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','DemonHunter-Havoc','Warlock-Demonology',}
local provider = {region='US',realm='Farstriders',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Absolon:BAABLgAECn8YAAIBAAgJWhyUNgADAgABAAgJWhyUNgADAgAAAA==.',
Ae='Aedelaide:BAAALgAECgEJAgAAAA==.Aelar:BAAALgADCgEJAQAAAA==.Aellynn:BAABLgAECn80AAMCAAgJMAxqMgBAAQACAAgJMAxqMgBAAQADAAEJXgAqbAAXAAAAAA==.Aerir:BAACLgAFFH8hAAIEAAUJCBN9WQArAQAEAAUJCBN9WQArAQAuAAQKfzAAAgQACQl0GdxbACYCAAQACQl0GdxbACYCAAAA.Aerithar:BAAALgADCgEJAQAAAA==.Aesirr:BAABLgAECn8VAAIFAAkJBwnsEQAqAQAFAAkJBwnsEQAqAQAAAA==.',
Ah='Ahmari:BAAALgADCgYJCgAAAA==.',
Al='Alandris:BAABLgAECn8lAAIGAAkJHgdOQQA/AQAGAAkJHgdOQQA/AQAAAA==.Alerya:BAAALgAECgEJAQAAAA==.Alinie:BAACLgAFFH8GAAMHAAMJGCHWJQDzAAAHAAMJGCHWJQDzAAAIAAMJrBynZgDhAAAuAAQKfxYAAgcACAkKJVgHAPcCAAcACAkKJVgHAPcCAAAA.Alleriya:BAABLgAECn83AAIBAAkJ6g1iAgBlAQABAAkJ6g1iAgBlAQAAAA==.Allison:BAAALgADCgMJAwAAAA==.Alltheheals:BAAALgAECggJDAAAAA==.Altruis:BAAALgADCgIJAgABLgAFFAUJFwAIAL4cAA==.',
Am='Amarawyn:BAABLgAECn8rAAIGAAgJsBZFAQA4AQAGAAgJsBZFAQA4AQAAAA==.Ambulance:BAAALgADCgEJAQAAAA==.Amoragan:BAABLgAECn8gAAQJAAkJHhq2HgBnAQAGAAkJcBjaOADDAQAJAAcJnxa2HgBnAQAKAAEJdAoAUgA2AAAAAA==.Amoravin:BAAALgAECgcJDQAAAA==.Amyra:BAAALgAECgQJBAAAAA==.',
An='Andriela:BAABLgAECn8XAAMLAAkJEQ0gPgCaAQALAAkJEQ0gPgCaAQAMAAEJ8wE8pwAZAAAAAA==.',
Ap='Apexy:BAABLgAECn8iAAIEAAcJVgYsxgAAAQAEAAcJVgYsxgAAAQAAAA==.',
Ar='Arashikaze:BAABLgAECn8WAAINAAgJyhnKJQAsAgANAAgJyhnKJQAsAgAAAA==.Ardy:BAAALgAECgEJAgABLgAFFAUJFwAIAL4cAA==.',
As='Asurion:BAAALgAECgEJAQAAAA==.',
Au='Augi:BAAALgADCgMJAwAAAA==.Augidget:BAABLgAECn8nAAIDAAkJbhehFQAfAgADAAkJbhehFQAfAgAAAA==.',
Av='Avgo:BAAALgAECgMJAwABLgAECgYJDgAOAAAAAA==.Avilen:BAABLgAECn8oAAIBAAkJ4Q03RADVAQABAAkJ4Q03RADVAQAAAA==.Aviris:BAABLgAECn8WAAMCAAgJABqBAQAKAQACAAgJABqBAQAKAQADAAEJIQp/jgAsAAABLgAECgkJHwAHAJUfAA==.',
Ay='Ayuzi:BAAALgAECgYJBwAAAA==.',
Az='Azarri:BAAALgAECgcJCAAAAA==.',
Ba='Badsilk:BAAALgAECgYJEwAAAA==.Balinteen:BAABLgAECn8ZAAMBAAcJrQXzmwAJAQABAAcJrQXzmwAJAQAPAAEJQANpRgAbAAAAAA==.Barktwain:BAAALgAECgQJBAAAAA==.Bastael:BAABLgAECn8iAAIHAAkJtyOSBABPAwAHAAkJtyOSBABPAwAAAA==.Bayus:BAAALgADCgIJAgAAAA==.',
Be='Benchie:BAAALgAECgEJAQABLgAECgkJNwAQACIbAA==.Bendyy:BAABLgAECn8jAAIEAAkJcRy/MwBKAgAEAAkJcRy/MwBKAgAAAA==.',
Bh='Bharani:BAAALgADCgcJBwAAAA==.',
Bi='Biopaindr:BAABLgAECn8pAAIMAAkJExENAQBHAQAMAAkJExENAQBHAQAAAA==.Bitxi:BAABLgAECn8iAAIBAAcJOQjPiwAnAQABAAcJOQjPiwAnAQAAAA==.',
Bl='Bloodtusk:BAAALgAECgYJCAAAAA==.',
Bo='Bob:BAAALgADCgcJBwAAAA==.Boldbane:BAAALgAECgYJCAAAAA==.Boozo:BAAALgAECgIJBAAAAA==.',
Br='Braic:BAAALgADCgEJAQAAAA==.Brax:BAAALgAECgQJAQAAAA==.Brocklee:BAABLgAECn8jAAIRAAkJExM5DgDMAQARAAkJExM5DgDMAQAAAA==.',
Bu='Bubbaman:BAABLgAECn8hAAMPAAcJsQVtHADLAAAPAAcJsQVtHADLAAABAAEJlQJO2AArAAAAAA==.Burda:BAABLgAECn8uAAMSAAkJTBkKEQAkAgASAAkJTBkKEQAkAgAPAAEJZg/2PQAuAAAAAA==.',
By='Byzinteen:BAAALgAECgIJAgAAAA==.',
Ca='Caenae:BAABLgAECn8eAAIBAAYJkwVItQDaAAABAAYJkwVItQDaAAAAAA==.Cattlerage:BAAALgADCgUJBQABLgAFFAUJFwAIAL4cAA==.',
Ce='Celestial:BAAALgAECgEJAgAAAA==.Cephira:BAAALgAECgEJAgAAAA==.',
Ch='Chandris:BAAALgADCgIJAgAAAA==.Chrissy:BAAALgAECgYJBgAAAA==.',
Ci='Ciannie:BAAALgADCgQJCAAAAA==.',
Cl='Clamor:BAAALgAECgQJDgAAAA==.',
Co='Cogiaugi:BAAALgAECgEJAQAAAA==.Coletrain:BAAALgAFFAEJAQAAAA==.Corri:BAABLgAECn8aAAMTAAUJXRxlGwAnAQATAAQJ5BllGwAnAQAUAAUJhxTWEAD9AAAAAA==.Corriandis:BAAALgAECgQJBQAAAA==.',
Cr='Credon:BAABLgAECn8iAAILAAcJThLuQgCFAQALAAcJThLuQgCFAQAAAA==.Crixxe:BAAALgAECgQJBwAAAA==.',
Da='Davin:BAAALgAECgYJBwAAAA==.',
De='Dereda:BAAALgAECgEJAQAAAA==.',
Dh='Dhellia:BAAALgAECgYJCgAAAA==.',
Di='Dierlyn:BAABLgAECn8vAAICAAgJXhLVIAC8AQACAAgJXhLVIAC8AQAAAA==.Dirtytaters:BAABLgAECn8iAAIDAAcJkAZHSQDqAAADAAcJkAZHSQDqAAAAAA==.Divastating:BAAALgAECgYJEAABLgAECgYJIQABAJ8DAA==.',
Do='Doko:BAAALgAECgIJAgAAAA==.Doró:BAABLgAECn8gAAIVAAkJDBptHABqAgAVAAkJDBptHABqAgAAAA==.',
Dt='Dtothed:BAAALgAECgQJCgAAAA==.',
Dw='Dwarfred:BAABLgAECn8rAAIQAAgJ3BvUFwAlAgAQAAgJ3BvUFwAlAgAAAA==.Dwimor:BAABLgAECn8cAAIBAAcJlg9vhAA2AQABAAcJlg9vhAA2AQAAAA==.',
['Dô']='Dôro:BAAALgAECgYJDQABLgAECgkJIAAVAAwaAA==.',
Ea='Earadin:BAAALgAECgQJBAAAAA==.',
Ec='Ecthelorn:BAAALgADCgMJBAAAAA==.',
El='Elasong:BAABLgAECn8UAAIWAAgJQQdTJgDjAAAWAAgJQQdTJgDjAAAAAA==.Elletal:BAAALgAECgEJAQABLgAECgkJMgAXAD8TAA==.Elmö:BAAALgAECgYJCgAAAA==.Elrarebriel:BAAALgAECgMJAwAAAA==.Elysius:BAAALgAECgEJAQAAAA==.',
Em='Emberstorm:BAAALgADCgQJBAAAAA==.',
Fa='Fairamir:BAAALgADCgQJBgAAAA==.Fayona:BAAALgADCgkJGwAAAA==.',
Fe='Felystra:BAAALgAECgIJBQAAAA==.',
Fi='Fizzbot:BAAALgAECgEJAgABLgAFFAUJIQAYAHcbAA==.Fizzlyn:BAACLgAFFH8hAAMYAAUJdxuoTABZAQAYAAQJbRuoTABZAQAZAAMJzxvkLQCPAAAuAAQKfzAAAxgACQlxIqU6ABYCABgACQlxIqU6ABYCABkAAwkfGz9AAI4AAAAA.',
Fl='Fluffsmcgee:BAAALgADCgkJDgAAAA==.',
Fr='Fredrick:BAAALgADCgcJCAAAAA==.Frieza:BAAALgAECgQJBgAAAA==.',
Fu='Furr:BAAALgAFFAEJAgABLgAFFAgJGwAEAEUTAA==.',
Ga='Galdora:BAAALgADCgcJEQAAAA==.Galedriel:BAABLgAECn8WAAIaAAYJ6QEvEwBUAAAaAAYJ6QEvEwBUAAAAAA==.',
Gh='Ghosthunter:BAAALgADCgkJDwAAAA==.',
Gi='Giizmo:BAAALgAECgEJAQAAAA==.',
Gr='Gragdal:BAAALgAECgMJAwAAAA==.Grandpa:BAAALgAECgEJAgABLgAECggJNAABAIsfAA==.Grewsöm:BAACLgAFFH8KAAMYAAQJTxrPlADjAAAYAAMJTxrPlADjAAAZAAIJwQ89CAAyAAAuAAQKfyMAAxgACQnrIzYWAMICABgACQm5IzYWAMICABkACAnOII8KAGgCAAEuAAUUBQkXAAgAvhwA.Grotusque:BAABLgAECn9DAAIbAAkJdBiUCwApAgAbAAkJdBiUCwApAgAAAA==.',
Gu='Guinness:BAAALgAECgQJBQAAAA==.Gullugren:BAAALgAECgkJCAAAAA==.Gutterdoxy:BAAALgADCgMJAwAAAA==.',
Ha='Hadiirn:BAABLgAECn8dAAIVAAYJ9RBQjwABAQAVAAYJ9RBQjwABAQAAAA==.Haiiro:BAABLgAECn8jAAIXAAkJyBeGFAAJAgAXAAkJyBeGFAAJAgAAAA==.Hardim:BAABLgAECn8nAAIBAAgJqQ2SAwAbAQABAAgJqQ2SAwAbAQAAAA==.Hardwood:BAAALgAECgQJCAAAAA==.Hargen:BAAALgAECgMJAwAAAA==.Harknesse:BAABLgAECn8dAAIcAAcJ/Q8TEwBJAQAcAAcJ/Q8TEwBJAQAAAA==.Hatermage:BAAALgAECgYJDwAAAA==.Haxxis:BAAALgAECgQJBQAAAA==.Hazzrel:BAAALgAECgYJDQAAAA==.',
He='Heftychi:BAAALgAECgIJAgAAAA==.Heftydh:BAABLgAECn82AAIdAAkJ0xw4AADdAQAdAAkJ0xw4AADdAQAAAA==.Hewhospins:BAABLgAECn8yAAMXAAkJPxMsGQDdAQAXAAkJPxMsGQDdAQAeAAEJbQrXpgAqAAAAAA==.Hextor:BAAALgAECgQJBAAAAA==.',
Ho='Hog:BAAALgAFFAEJAQABLgAFFAgJHwAKAOgiAA==.Horizontal:BAAALgADCgcJBwABLgADCgcJBwAOAAAAAA==.',
Hr='Hranu:BAABLgAECn8bAAILAAcJRxX+AAB0AQALAAcJRxX+AAB0AQABLgAFFAMJDwALABUXAA==.',
Hu='Husker:BAAALgAECgMJAwAAAA==.',
Hy='Hydraulicman:BAABLgAECn8WAAILAAUJKCHHMgDUAQALAAUJKCHHMgDUAQAAAA==.Hyzer:BAAALgAECgYJBgABLgAECggJEAAOAAAAAA==.',
Id='Idget:BAAALgAECgMJAwAAAA==.',
Ig='Igknight:BAAALgAECgEJAQAAAA==.',
Im='Image:BAAALgAECgYJCQABLgAFFAUJGgAIAF8cAA==.',
Ja='Jacksmite:BAAALgADCgEJAQAAAA==.Jasmirana:BAABLgAECn8UAAMCAAkJ5goELwBWAQACAAkJ5goELwBWAQADAAEJOAJemwAaAAAAAA==.',
Je='Jemano:BAAALgADCgEJAQAAAA==.Jenal:BAAALgAECgUJBQAAAA==.',
Ji='Jirenr:BAABLgAECn8rAAIeAAgJPQgsAQD4AAAeAAgJPQgsAQD4AAAAAA==.',
Jo='Jolage:BAABLgAECn8hAAIEAAcJZhW0BgCuAAAEAAcJZhW0BgCuAAAAAA==.Jolreal:BAACLgAFFH8OAAISAAQJzxogDwBLAQASAAQJzxogDwBLAQAuAAQKf04AAxIACAmDI48IAJUCABIACAnGIY8IAJUCAA8ABwlQIkUUAJICAAAA.',
Ju='Julez:BAABLgAECn8jAAIBAAgJmhBOhAA2AQABAAgJmhBOhAA2AQAAAA==.Julezara:BAAALgAECgYJEgAAAA==.Julezdruid:BAAALgAECgIJAgAAAA==.Junkai:BAACLgAFFH8aAAIIAAUJXxzQMABQAQAIAAUJXxzQMABQAQAuAAQKfzUAAggACAlQJK8aAKQCAAgACAlQJK8aAKQCAAAA.',
Ka='Kargak:BAAALgAECgYJBgAAAA==.Kathanial:BAAALgADCgUJBgAAAA==.Katiagrimm:BAAALgADCgYJCgAAAA==.Kawi:BAAALgAECgMJAwABLgAECgkJIwARABMTAA==.',
Ke='Keco:BAABLgAECn8hAAIBAAYJnwN4CgBmAAABAAYJnwN4CgBmAAAAAA==.Kelenar:BAAALgAECgMJAwAAAA==.Kennie:BAABLgAECn8lAAMFAAkJLg0yDQBrAQAFAAkJLg0yDQBrAQAfAAMJIAa1HACNAAAAAA==.',
Kl='Kladibo:BAAALgAECgEJAQABLgAECgYJCgAOAAAAAA==.Kladivo:BAAALgAECgYJBgABLgAECgYJCgAOAAAAAA==.',
Kn='Knorr:BAAALgAECgcJDAAAAA==.',
Ko='Korthaz:BAAALgADCgIJAgAAAA==.',
Ku='Kuwanlalenta:BAAALgAECgIJAgAAAA==.',
Kw='Kwansu:BAAALgAECgYJCgAAAA==.',
La='Lahlania:BAABLgAECn8WAAIgAAYJsR2MEQChAQAgAAYJsR2MEQChAQAAAA==.Laura:BAAALgAECgMJBQAAAA==.',
Le='Lexis:BAAALgADCgcJDQAAAA==.',
Li='Lilyda:BAAALgADCggJBgAAAA==.',
Lo='Lolann:BAAALgADCgUJCAAAAA==.',
Ly='Lyia:BAAALgADCgEJAQAAAA==.',
Ma='Machette:BAACLgAFFH8GAAIIAAMJ0QsEdgDIAAAIAAMJ0QsEdgDIAAAuAAQKfxoAAggABgkvGLmRAE8BAAgABgkvGLmRAE8BAAAA.Mailaria:BAABLgAECn8oAAIdAAkJyw8rDQCBAQAdAAkJyw8rDQCBAQAAAA==.Maithe:BAAALgADCgcJBwAAAA==.Majesti:BAAALgADCggJBwAAAA==.Malakar:BAACLgAFFH8GAAIhAAMJbQqeKQDgAAAhAAMJbQqeKQDgAAAuAAQKfyMAAyEABwm7GxQiAOgBACEABwlrFxQiAOgBACIABgmHGdALAGoBAAAA.Malvolio:BAAALgADCgMJAwAAAA==.Mantoecore:BAAALgADCgcJCAAAAA==.Marellaa:BAABLgAECn8ZAAICAAYJJww8PwDyAAACAAYJJww8PwDyAAAAAA==.Markers:BAAALgADCgIJAgAAAA==.Marottie:BAAALgADCgkJFgAAAA==.',
Mc='Mcsplatapus:BAAALgAECgcJCgAAAA==.',
Me='Meingsolin:BAABLgAECn8wAAIeAAcJwhYULgBTAQAeAAcJwhYULgBTAQAAAA==.Meseeker:BAAALgAECgcJBwAAAA==.Mezagog:BAAALgADCgcJEAAAAA==.',
Mi='Midknight:BAAALgAECgUJBgAAAA==.Miggylosoh:BAAALgAECgMJDgAAAA==.Minizoomies:BAAALgAECgMJBgAAAA==.Misthashira:BAAALgAFFAEJAQAAAA==.Miyeon:BAAALgADCgMJAwAAAA==.',
Mo='Momo:BAAALgADCgkJFgABLgAECgIJAwAOAAAAAA==.Moochi:BAAALgAECgEJAQAAAA==.',
My='Mygourdness:BAABLgAECn8VAAILAAYJ+AT4iwCeAAALAAYJ+AT4iwCeAAAAAA==.Myuk:BAABLgAECn8jAAISAAkJBB0+DgBFAgASAAkJBB0+DgBFAgAAAA==.',
Mz='Mzskywalker:BAAALgAECgYJDAAAAA==.',
Na='Naminay:BAABLgAECn8WAAIHAAgJfxkfGQA9AgAHAAgJfxkfGQA9AgAAAA==.Narbash:BAAALgAECgQJBAAAAA==.Nasrullah:BAAALgADCgkJDQAAAA==.Natalie:BAAALgAECgEJAQAAAA==.Natral:BAAALgAECgEJAQAAAA==.Navì:BAAALgADCgkJDgAAAA==.',
Ne='Nekia:BAAALgAECgIJAgAAAA==.Neroz:BAABLgAECn8+AAIVAAkJJhwsFgCSAgAVAAkJJhwsFgCSAgAAAA==.Nerppie:BAACLgAFFH8IAAIHAAMJWCGFHwAhAQAHAAMJWCGFHwAhAQAuAAQKfzgAAgcACQnUH4sHABMDAAcACQnUH4sHABMDAAAA.Nevershark:BAAALgAECgUJBQAAAA==.',
Ni='Nightfallz:BAAALgADCgUJBQAAAA==.Nina:BAABLgAECn8ZAAIIAAcJdRpRTwD0AQAIAAcJdRpRTwD0AQAAAA==.Nixah:BAAALgAECgUJDQAAAA==.',
Nk='Nkript:BAABLgAECn8yAAMBAAkJ3RkKHwBsAgABAAkJ3RkKHwBsAgAPAAYJpgiJTwARAQAAAA==.',
No='Nortel:BAAALgAECgYJDgAAAA==.',
Oh='Ohgourdness:BAAALgADCgcJBwABLgAECgYJFQALAPgEAA==.',
On='Onari:BAABLgAECn8rAAMCAAkJ6h05CgDEAgACAAkJ6h05CgDEAgAjAAMJOA86WgCXAAAAAA==.',
Or='Orious:BAAALgADCgYJBgAAAA==.',
Pa='Paine:BAAALgAECgEJAQAAAA==.Pandagang:BAAALgADCgQJBQAAAA==.',
Pe='Peezee:BAABLgAECn8XAAMIAAgJ9w8pjABZAQAIAAgJbw0pjABZAQAWAAYJSg2GKQDMAAAAAA==.Perce:BAABLgAECn8+AAMHAAkJACBGAABAAgAHAAkJACBGAABAAgAIAAQJJBnNoAA2AQAAAA==.Peyotte:BAABLgAECn8VAAIKAAgJgB9dDgAGAgAKAAgJgB9dDgAGAgABLgAFFAQJBwAQAJQUAA==.',
Pf='Pfemme:BAABLgAECn8qAAIBAAkJDx5KHAB7AgABAAkJDx5KHAB7AgAAAA==.',
Pp='Pp:BAAALgAECgQJBAAAAA==.',
Ps='Psych:BAAALgADCgYJBgAAAA==.',
Pu='Purian:BAAALgADCgcJDwAAAA==.',
Ra='Rainfall:BAAALgAECgMJAwAAAA==.Rami:BAAALgADCgYJBgAAAA==.',
Re='Repello:BAAALgAECgYJBwAAAA==.Reyaieleron:BAAALgAECgYJEAAAAA==.',
Ri='Ricky:BAAALgADCgEJAQAAAA==.Rivenaer:BAABLgAECn82AAMkAAkJxBCeGQC0AQAkAAkJxBCeGQC0AQAVAAEJiAKlOwEaAAAAAA==.',
Ru='Ruindsoul:BAAALgADCgcJCwAAAA==.Ruka:BAAALgADCgEJAQAAAA==.Runearne:BAAALgAECgIJAgAAAA==.Rus:BAAALgAECgcJCgABLgAECgkJIwARABMTAA==.Rustymark:BAACLgAFFH8TAAIBAAQJwRDXAwA2AQABAAQJwRDXAwA2AQAuAAQKfyMAAgEACQljF/0gAGICAAEACQljF/0gAGICAAAA.',
Sa='Sandlucky:BAAALgAECgEJAQAAAA==.',
Sc='Scaletal:BAAALgAECgUJBQAAAA==.Schmetzy:BAAALgAECgYJCAAAAA==.Schmezzy:BAABLgAECn8cAAIYAAgJvB2bSQDlAQAYAAgJvB2bSQDlAQAAAA==.Scuti:BAAALgAECgQJBQAAAA==.',
Se='Sealalicious:BAABLgAECn8+AAIWAAkJrx1WBQCcAgAWAAkJrx1WBQCcAgAAAA==.Seenaa:BAAALgAECgQJBAAAAA==.Seân:BAAALgAECgEJAQABLgAECggJEQAOAAAAAA==.',
Sh='Shallot:BAAALgADCgYJEgAAAA==.Shammywow:BAABLgAECn8VAAMNAAUJRx56MwC2AQANAAUJRx56MwC2AQAQAAMJlxf4WQDWAAAAAA==.Sharkzilla:BAABLgAECn8YAAIBAAkJKx0wFwB/AgABAAkJKx0wFwB/AgAAAA==.Shauray:BAAALgADCgYJCgAAAA==.Shine:BAABLgAECn80AAMBAAgJix+GKAA9AgABAAgJix+GKAA9AgASAAUJ2RYeAQDxAAAAAA==.Shrub:BAAALgADCgcJBwABLgAFFAkJIAAjACwhAA==.',
Si='Silksmilk:BAAALgADCgIJAgAAAA==.Siobhân:BAAALgAECgYJDAAAAA==.',
Sl='Sloppy:BAAALgAECgYJDgAAAA==.',
Sm='Smashchie:BAAALgAECgEJAQAAAA==.Smoo:BAAALgAECgUJBgAAAA==.Smythe:BAAALgADCgEJAQAAAA==.',
Sn='Snø:BAAALgAECgcJDwAAAA==.',
So='Sobol:BAAALgAFFAEJAgAAAA==.Soggyaugi:BAAALgAECgYJDQAAAA==.Solbinder:BAAALgADCgIJAgAAAA==.Soraa:BAEALgAECgUJDwABLgAECgkJIAAEADIfAA==.Soulbleeder:BAAALgAECgQJBAAAAA==.',
St='Starlethia:BAAALgAECggJEwAAAA==.Steelclad:BAAALgAECgUJBgABLgAECgkJPgAVACYcAA==.',
Su='Sumpnclaws:BAAALgAECgYJBgAAAA==.Sunshine:BAAALgAECgcJDAAAAA==.Sunwälker:BAAALgADCgQJBAAAAA==.',
Sy='Sybelin:BAAALgAECgQJBQAAAA==.',
Ta='Tallchief:BAABLgAECn8gAAIBAAYJkxL+fgBBAQABAAYJkxL+fgBBAQAAAA==.Talliah:BAAALgAECgQJBQAAAA==.Tamarynn:BAAALgADCgUJBQABLgAECggJNAACADAMAA==.Tankufrdying:BAAALgAECgYJDQAAAA==.Tarkuroth:BAAALgADCgQJBAAAAA==.Tavarien:BAAALgADCgEJAQAAAA==.Tayllana:BAAALgAECgEJAQAAAA==.',
Te='Tenjo:BAAALgAECgYJEAAAAA==.Terrier:BAAALgAECgEJAQAAAA==.',
Th='Thaerdran:BAABLgAECn8nAAIZAAkJFRucDABDAgAZAAkJFRucDABDAgAAAA==.',
Ti='Tierri:BAAALgAECgEJAwAAAA==.Tirriel:BAAALgADCgMJAwAAAA==.',
To='Toess:BAAALgAECgEJAQAAAA==.Tonati:BAAALgAECgMJAwAAAA==.Tonjuren:BAAALgAECgMJBwABLgAECgcJMAAeAMIWAA==.',
Tr='Travosaur:BAAALgAFFAEJAQAAAA==.Trublood:BAABLgAECn8dAAIDAAcJ0gidQgAFAQADAAcJ0gidQgAFAQAAAA==.Truelder:BAAALgADCgQJBAAAAA==.',
Tw='Twister:BAAALgAECgQJDwAAAA==.',
Ty='Tyrra:BAAALgADCgMJAwAAAA==.',
Uk='Ukeenonme:BAAALgAECgYJBwAAAA==.',
Us='Usorloups:BAACLgAFFH8HAAIQAAQJlBSXMQDLAAAQAAQJlBSXMQDLAAAuAAQKfyAAAhAACQnCH8APAHcCABAACQnCH8APAHcCAAAA.',
Va='Vaelar:BAAALgAECgYJBgAAAA==.Valstad:BAAALgAECgYJEgAAAA==.',
Ve='Velonys:BAABLgAECn85AAQFAAkJYCOvAQDCAgAFAAgJ5COvAQDCAgAlAAYJZBcAgAA5AQAfAAQJLCDyFgAQAQAAAA==.Velus:BAAALgAECgQJBAAAAA==.',
Vi='Victory:BAAALgAECgEJAQAAAA==.Vintar:BAAALgADCgMJAwAAAA==.',
Vo='Volkhikos:BAAALgAECgcJCAAAAA==.',
Vy='Vyral:BAAALgAECgQJBgAAAA==.Vyu:BAAALgAECgkJDQAAAA==.',
Wa='Wanayu:BAABLgAECn8kAAIFAAkJTBmcBAAyAgAFAAkJTBmcBAAyAgAAAA==.Wanweasley:BAABLgAECn8VAAINAAgJih+KEgC5AgANAAgJih+KEgC5AgAAAA==.',
We='Weeab:BAAALgADCgEJAQAAAA==.Weezlee:BAAALgAECgQJBAAAAA==.Weh:BAABLgAECn8YAAIEAAkJryImJgCDAgAEAAkJryImJgCDAgAAAA==.',
Wi='Wickedsham:BAAALgADCgIJAgAAAA==.Willic:BAAALgAECggJCAAAAA==.Wintermourne:BAABLgAECn8fAAIcAAkJfAcNEwBJAQAcAAkJfAcNEwBJAQAAAA==.Wizagon:BAABLgAECn8XAAIUAAkJlBsZBAA/AgAUAAkJlBsZBAA/AgAAAA==.',
Wo='Woodlet:BAAALgAECgMJAwAAAA==.Woodsy:BAABLgAECn8mAAITAAkJAhwNBQDMAgATAAkJAhwNBQDMAgAAAA==.Wounded:BAAALgAECgEJAgAAAA==.Woundliquor:BAAALgAECgcJEQAAAA==.',
Xe='Xemnas:BAABLgAECn8/AAQYAAcJGQ+7nQAvAQAYAAcJgA27nQAvAQAcAAQJ6g7+AQBfAAAZAAIJ7wF1XgAuAAAAAA==.',
Ya='Yawnday:BAAALgAECgMJAwABLgAECggJEQAOAAAAAA==.Yawnight:BAAALgAECggJEQAAAA==.',
Ys='Yserra:BAAALgAECgMJBAAAAA==.',
Za='Zaryala:BAAALgADCgkJKAAAAA==.',
Ze='Zenshift:BAAALgAECgMJCAAAAA==.',
Zy='Zynthia:BAACLgAFFH8GAAIYAAIJTyTHpQDOAAAYAAIJTyTHpQDOAAAuAAQKfzAAAhgACQn9JN8FAEoDABgACQn9JN8FAEoDAAAA.',
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
