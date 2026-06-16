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

local lookup = {'Hunter-BeastMastery','Priest-Holy','Priest-Shadow','Mage-Frost','Warlock-Destruction','Warrior-Fury','Paladin-Holy','Paladin-Retribution','Warrior-Arms','Warrior-Protection','Druid-Restoration','Druid-Balance','Shaman-Restoration','Unknown-Unknown','Hunter-Marksmanship','Shaman-Elemental','Shaman-Enhancement','Hunter-Survival','Evoker-Preservation','Evoker-Devastation','DemonHunter-Devourer','Monk-Brewmaster','DeathKnight-Unholy','DeathKnight-Blood','Mage-Arcane','Druid-Guardian','DeathKnight-Frost','DemonHunter-Vengeance','Monk-Windwalker','Warlock-Affliction','Druid-Feral','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Paladin-Protection','DemonHunter-Havoc','Warlock-Demonology',}
local provider = {region='US',realm='Farstriders',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Absolon:BAABLgAECn8VAAIBAAgJkxoeNQAEAgABAAgJkxoeNQAEAgAAAA==.',
Ae='Aedelaide:BAAALgAECgEJAgAAAA==.Aelar:BAAALgADCgEJAQAAAA==.Aellynn:BAABLgAECn8zAAMCAAgJMAyxMQBAAQACAAgJMAyxMQBAAQADAAEJXgAqbAAXAAAAAA==.Aerir:BAACLgAFFH8hAAIEAAUJCBNDVgA7AQAEAAUJCBNDVgA7AQAuAAQKfzAAAgQACQl0GdxbACYCAAQACQl0GdxbACYCAAAA.Aerithar:BAAALgADCgEJAQAAAA==.Aesirr:BAABLgAECn8VAAIFAAkJBwl7EQAqAQAFAAkJBwl7EQAqAQAAAA==.',
Ah='Ahmari:BAAALgADCgYJCgAAAA==.',
Al='Alandris:BAABLgAECn8kAAIGAAkJ0wZ9QABCAQAGAAkJ0wZ9QABCAQAAAA==.Alerya:BAAALgAECgEJAQAAAA==.Alinie:BAACLgAFFH8GAAMHAAMJGCHdJADzAAAHAAMJGCHdJADzAAAIAAMJrBwDYwDiAAAuAAQKfxYAAgcACAkKJVgHAPcCAAcACAkKJVgHAPcCAAAA.Alleriya:BAABLgAECn8wAAIBAAgJCQwYZgBzAQABAAgJCQwYZgBzAQAAAA==.Allison:BAAALgADCgMJAwAAAA==.Alltheheals:BAAALgAECggJDAAAAA==.Altruis:BAAALgADCgIJAgABLgAFFAUJFwAIAL4cAA==.',
Am='Amarawyn:BAABLgAECn8mAAIGAAgJWxZFIQDmAQAGAAgJWxZFIQDmAQAAAA==.Ambulance:BAAALgADCgEJAQAAAA==.Amoragan:BAABLgAECn8gAAQJAAkJHhokHgBoAQAGAAkJcBjaOADDAQAJAAcJnxYkHgBoAQAKAAEJdAqYUAA2AAAAAA==.Amoravin:BAAALgAECgcJDQAAAA==.Amyra:BAAALgAECgQJAwAAAA==.',
An='Andriela:BAABLgAECn8XAAMLAAkJEQ1YPQCbAQALAAkJEQ1YPQCbAQAMAAEJ8wFGpAAZAAAAAA==.',
Ap='Apexy:BAABLgAECn8hAAIEAAcJVgbYwwAAAQAEAAcJVgbYwwAAAQAAAA==.',
Ar='Arashikaze:BAABLgAECn8WAAINAAgJyhkRJQAsAgANAAgJyhkRJQAsAgAAAA==.Ardy:BAAALgAECgEJAQABLgAFFAUJFwAIAL4cAA==.',
As='Asurion:BAAALgAECgEJAQAAAA==.',
Au='Augi:BAAALgADCgMJAwAAAA==.Augidget:BAABLgAECn8nAAIDAAkJbhfmFAAmAgADAAkJbhfmFAAmAgAAAA==.',
Av='Avgo:BAAALgAECgMJAwABLgAECgYJDgAOAAAAAA==.Avilen:BAABLgAECn8oAAIBAAkJ4Q2zQgDWAQABAAkJ4Q2zQgDWAQAAAA==.Aviris:BAAALgAECgcJEwABLgAECgkJHwAHAJUfAA==.',
Ay='Ayuzi:BAAALgAECgYJBwAAAA==.',
Az='Azarri:BAAALgAECgcJCAAAAA==.',
Ba='Badsilk:BAAALgAECgYJEwAAAA==.Balinteen:BAABLgAECn8ZAAMBAAcJrQUEmQAJAQABAAcJrQUEmQAJAQAPAAEJQANJRQAbAAAAAA==.Barktwain:BAAALgAECgQJBAAAAA==.Bastael:BAABLgAECn8iAAIHAAkJtyNqBABQAwAHAAkJtyNqBABQAwAAAA==.Bayus:BAAALgADCgIJAgAAAA==.',
Be='Benchie:BAAALgAECgEJAQABLgAECgkJMwAQAEUaAA==.Bendyy:BAABLgAECn8jAAIEAAkJcRzbMgBLAgAEAAkJcRzbMgBLAgAAAA==.',
Bh='Bharani:BAAALgADCgcJBwAAAA==.',
Bi='Biopaindr:BAABLgAECn8iAAIMAAgJIhLKJwCOAQAMAAgJIhLKJwCOAQAAAA==.Bitxi:BAABLgAECn8hAAIBAAcJ/AfOigAkAQABAAcJ/AfOigAkAQAAAA==.',
Bl='Bloodtusk:BAAALgAECgYJBwAAAA==.',
Bo='Bob:BAAALgADCgcJBwAAAA==.Boldbane:BAAALgAECgYJCAAAAA==.Boozo:BAAALgAECgIJBAAAAA==.',
Br='Braic:BAAALgADCgEJAQAAAA==.Brax:BAAALgAECgQJAQAAAA==.Brocklee:BAABLgAECn8hAAIRAAkJQRLoDQDOAQARAAkJQRLoDQDOAQAAAA==.',
Bu='Bubbaman:BAABLgAECn8gAAMPAAcJsQX8GwDLAAAPAAcJsQX8GwDLAAABAAEJlQJO2AArAAAAAA==.Burda:BAABLgAECn8rAAMSAAkJ6RehEAApAgASAAkJ6RehEAApAgAPAAEJZg8SPQAuAAAAAA==.',
By='Byzinteen:BAAALgAECgEJAQAAAA==.',
Ca='Caenae:BAABLgAECn8eAAIBAAYJkwXJsQDaAAABAAYJkwXJsQDaAAAAAA==.Cattlerage:BAAALgADCgUJBQABLgAFFAUJFwAIAL4cAA==.',
Ce='Celestial:BAAALgAECgEJAgAAAA==.Cephira:BAAALgAECgEJAgAAAA==.',
Ch='Chandris:BAAALgADCgIJAgAAAA==.Chrissy:BAAALgAECgYJBgAAAA==.',
Ci='Ciannie:BAAALgADCgQJCAAAAA==.',
Cl='Clamor:BAAALgAECgQJDgAAAA==.',
Co='Cogiaugi:BAAALgAECgEJAQAAAA==.Coletrain:BAAALgAFFAEJAQAAAA==.Corri:BAABLgAECn8aAAMTAAUJXRweGwAnAQATAAQJ5BkeGwAnAQAUAAUJhxSPEAD9AAAAAA==.Corriandis:BAAALgAECgQJBQAAAA==.',
Cr='Credon:BAABLgAECn8hAAILAAcJThJmQgCFAQALAAcJThJmQgCFAQAAAA==.Crixxe:BAAALgAECgQJBwAAAA==.',
Da='Davin:BAAALgAECgYJBwAAAA==.',
De='Dereda:BAAALgAECgEJAQAAAA==.',
Dh='Dhellia:BAAALgAECgYJCgAAAA==.',
Di='Dierlyn:BAABLgAECn8qAAICAAgJXhJKIAC8AQACAAgJXhJKIAC8AQAAAA==.Dirtytaters:BAABLgAECn8hAAIDAAcJkAYHSADsAAADAAcJkAYHSADsAAAAAA==.Divastating:BAAALgAECgQJDgABLgAECgYJHgABAJsDAA==.',
Do='Doko:BAAALgAECgIJAgAAAA==.Doró:BAABLgAECn8gAAIVAAkJDBoCHABpAgAVAAkJDBoCHABpAgAAAA==.',
Dt='Dtothed:BAAALgAECgQJCgAAAA==.',
Dw='Dwarfred:BAABLgAECn8nAAIQAAgJVxt4FwAmAgAQAAgJVxt4FwAmAgAAAA==.Dwimor:BAABLgAECn8cAAIBAAcJlg/mgQA2AQABAAcJlg/mgQA2AQAAAA==.',
['Dô']='Dôro:BAAALgAECgYJCQABLgAECgkJIAAVAAwaAA==.',
Ea='Earadin:BAAALgAECgQJBAAAAA==.',
Ec='Ecthelorn:BAAALgADCgMJBAAAAA==.',
El='Elasong:BAAALgAECggJEwAAAA==.Elletal:BAAALgAECgEJAQABLgAECgkJMgAWAD8TAA==.Elmö:BAAALgAECgYJCgAAAA==.Elrarebriel:BAAALgAECgMJAwAAAA==.Elysius:BAAALgAECgEJAQAAAA==.',
Em='Emberstorm:BAAALgADCgQJBAAAAA==.',
Fa='Fairamir:BAAALgADCgQJBgAAAA==.Fayona:BAAALgADCgcJFQAAAA==.',
Fe='Felystra:BAAALgAECgIJBQAAAA==.',
Fi='Fizzbot:BAAALgAECgEJAgABLgAFFAUJIQAXAHcbAA==.Fizzlyn:BAACLgAFFH8hAAMXAAUJdxs2SQBbAQAXAAQJbRs2SQBbAQAYAAMJzxvHLACRAAAuAAQKfzAAAxcACQlxIrA5ABcCABcACQlxIrA5ABcCABgAAwkfG1k/AI8AAAAA.',
Fl='Fluffsmcgee:BAAALgADCgkJDgAAAA==.',
Fr='Fredrick:BAAALgADCgcJCAAAAA==.Frieza:BAAALgAECgQJBgAAAA==.',
Fu='Furr:BAAALgAFFAEJAgABLgAFFAQJCgACALcSAA==.',
Ga='Galdora:BAAALgADCgcJEQAAAA==.Galedriel:BAABLgAECn8VAAIZAAYJ6QGMEgBUAAAZAAYJ6QGMEgBUAAAAAA==.',
Gh='Ghosthunter:BAAALgADCgkJDwAAAA==.',
Gi='Giizmo:BAAALgAECgEJAQAAAA==.',
Gr='Gragdal:BAAALgAECgMJAwAAAA==.Grandpa:BAAALgAECgEJAgABLgAECggJLAABAAwdAA==.Grewsöm:BAACLgAFFH8JAAMXAAQJTxr9jwDnAAAXAAMJTxr9jwDnAAAYAAEJAAB6TwAAAAAuAAQKfyMAAxcACQnrI7kVAMMCABcACQm5I7kVAMMCABgACAnOIFQKAGsCAAEuAAUUBQkXAAgAvhwA.Grotusque:BAABLgAECn9DAAIaAAkJdBhfCwApAgAaAAkJdBhfCwApAgAAAA==.',
Gu='Guinness:BAAALgAECgQJBQAAAA==.Gullugren:BAAALgAECgkJCAAAAA==.Gutterdoxy:BAAALgADCgMJAwAAAA==.',
Ha='Hadiirn:BAABLgAECn8dAAIVAAYJ9RBGjQABAQAVAAYJ9RBGjQABAQAAAA==.Haiiro:BAABLgAECn8jAAIWAAkJyBc+FAAKAgAWAAkJyBc+FAAKAgAAAA==.Hardim:BAABLgAECn8iAAIBAAgJFgzWZQB0AQABAAgJFgzWZQB0AQAAAA==.Hardwood:BAAALgAECgQJCAAAAA==.Hargen:BAAALgAECgMJAwAAAA==.Harknesse:BAABLgAECn8cAAIbAAcJ4A4cEwBFAQAbAAcJ4A4cEwBFAQAAAA==.Hatermage:BAAALgAECgYJDwAAAA==.Haxxis:BAAALgAECgEJAQAAAA==.Hazzrel:BAAALgAECgYJDQAAAA==.',
He='Heftychi:BAAALgAECgIJAgAAAA==.Heftydh:BAABLgAECn8vAAIcAAgJ2B/WBABkAgAcAAgJ2B/WBABkAgAAAA==.Hewhospins:BAABLgAECn8yAAMWAAkJPxPrGADdAQAWAAkJPxPrGADdAQAdAAEJbQrMowAqAAAAAA==.Hextor:BAAALgAECgQJBAAAAA==.',
Ho='Hog:BAAALgAFFAEJAQABLgAFFAgJHwAKAOgiAA==.Horizontal:BAAALgADCgcJBwABLgADCgcJBwAOAAAAAA==.',
Hr='Hranu:BAABLgAECn8WAAILAAcJ0xHpPwCQAQALAAcJ0xHpPwCQAQABLgAFFAMJDwALABUXAA==.',
Hu='Husker:BAAALgAECgMJAwAAAA==.',
Hy='Hydraulicman:BAAALgAECgUJEwAAAA==.Hyzer:BAAALgAECgYJBgABLgAECggJEAAOAAAAAA==.',
Id='Idget:BAAALgADCgEJAQAAAA==.',
Ig='Igknight:BAAALgAECgEJAQAAAA==.',
Im='Image:BAAALgAECgYJCQABLgAFFAUJGgAIAF8cAA==.',
Ja='Jacksmite:BAAALgADCgEJAQAAAA==.Jasmirana:BAABLgAECn8UAAMCAAkJ5gpALgBWAQACAAkJ5gpALgBWAQADAAEJOAJgmAAaAAAAAA==.',
Je='Jemano:BAAALgADCgEJAQAAAA==.Jenal:BAAALgAECgUJBQAAAA==.',
Ji='Jirenr:BAABLgAECn8kAAIdAAcJ+QcERQDnAAAdAAcJ+QcERQDnAAAAAA==.',
Jo='Jolage:BAABLgAECn8fAAIEAAcJ5BESiwBeAQAEAAcJ5BESiwBeAQAAAA==.Jolreal:BAACLgAFFH8OAAISAAQJzxqBDgBMAQASAAQJzxqBDgBMAQAuAAQKf0kAAxIACAmDI3EIAJcCABIACAnPIHEIAJcCAA8ABwlQIkUUAJICAAAA.',
Ju='Julez:BAABLgAECn8hAAIBAAYJ3xGrgQA2AQABAAYJ3xGrgQA2AQAAAA==.Julezara:BAAALgAECgYJEQAAAA==.Julezdruid:BAAALgAECgIJAgAAAA==.Junkai:BAACLgAFFH8aAAIIAAUJXxzuLQBRAQAIAAUJXxzuLQBRAQAuAAQKfzAAAggACAn+Iy0bAMYCAAgACAn+Iy0bAMYCAAAA.',
Ka='Kathanial:BAAALgADCgUJBgAAAA==.Katiagrimm:BAAALgADCgYJCgAAAA==.Kawi:BAAALgAECgMJAwABLgAECgkJIQARAEESAA==.',
Ke='Keco:BAABLgAECn8eAAIBAAYJmwOLvwDBAAABAAYJmwOLvwDBAAAAAA==.Kelenar:BAAALgAECgMJAwAAAA==.Kennie:BAABLgAECn8lAAMFAAkJLg3mDABsAQAFAAkJLg3mDABsAQAeAAMJIAa1HACNAAAAAA==.',
Kl='Kladibo:BAAALgAECgEJAQABLgAECgYJCgAOAAAAAA==.Kladivo:BAAALgAECgYJBgABLgAECgYJCgAOAAAAAA==.',
Kn='Knorr:BAAALgAECgcJDAAAAA==.',
Ko='Korthaz:BAAALgADCgIJAgAAAA==.',
Ku='Kuwanlalenta:BAAALgAECgIJAgAAAA==.',
Kw='Kwansu:BAAALgAECgYJCgAAAA==.',
La='Lahlania:BAABLgAECn8WAAIfAAYJsR0hEQChAQAfAAYJsR0hEQChAQAAAA==.Laura:BAAALgAECgMJBQAAAA==.',
Le='Lexis:BAAALgADCgcJDQAAAA==.',
Li='Lilyda:BAAALgADCggJBgAAAA==.',
Lo='Lolann:BAAALgADCgUJCAAAAA==.',
Ly='Lyia:BAAALgADCgEJAQAAAA==.',
Ma='Machette:BAACLgAFFH8GAAIIAAMJ0QsycgDJAAAIAAMJ0QsycgDJAAAuAAQKfxoAAggABgkvGOmPAE8BAAgABgkvGOmPAE8BAAAA.Mailaria:BAABLgAECn8oAAIcAAkJyw/2DACBAQAcAAkJyw/2DACBAQAAAA==.Maithe:BAAALgADCgcJBwAAAA==.Majesti:BAAALgADCggJBwAAAA==.Malakar:BAACLgAFFH8GAAIgAAMJbQonKADhAAAgAAMJbQonKADhAAAuAAQKfyMAAyAABwm7GxQiAOgBACAABwlrFxQiAOgBACEABgmHGdALAGoBAAAA.Malvolio:BAAALgADCgMJAwAAAA==.Mantoecore:BAAALgADCgcJCAAAAA==.Marellaa:BAABLgAECn8ZAAICAAYJJwxcPgDyAAACAAYJJwxcPgDyAAAAAA==.Markers:BAAALgADCgIJAgAAAA==.Marottie:BAAALgADCgcJBwAAAA==.',
Mc='Mcsplatapus:BAAALgAECgcJCgAAAA==.',
Me='Meingsolin:BAABLgAECn8vAAIdAAYJ5xZSLQBTAQAdAAYJ5xZSLQBTAQAAAA==.Meseeker:BAAALgAECgcJBwAAAA==.Mezagog:BAAALgADCgcJEAAAAA==.',
Mi='Midknight:BAAALgAECgUJBgAAAA==.Miggylosoh:BAAALgAECgMJCwAAAA==.Minizoomies:BAAALgAECgMJBgAAAA==.Miyeon:BAAALgADCgMJAwAAAA==.',
Mo='Momo:BAAALgADCgkJFgABLgAECgIJAgAOAAAAAA==.Moochi:BAAALgAECgEJAQAAAA==.',
My='Mygourdness:BAABLgAECn8VAAILAAYJ+ATKigCeAAALAAYJ+ATKigCeAAAAAA==.Myuk:BAABLgAECn8jAAISAAkJBB3LDQBLAgASAAkJBB3LDQBLAgAAAA==.',
Mz='Mzskywalker:BAAALgAECgYJDAAAAA==.',
Na='Naminay:BAABLgAECn8WAAIHAAgJfxnJGAA+AgAHAAgJfxnJGAA+AgAAAA==.Narbash:BAAALgAECgQJBAAAAA==.Nasrullah:BAAALgADCgkJDQAAAA==.Natalie:BAAALgAECgEJAQAAAA==.Natral:BAAALgAECgEJAQAAAA==.Navì:BAAALgADCgkJCQAAAA==.',
Ne='Nekia:BAAALgAECgEJAQAAAA==.Neroz:BAABLgAECn8+AAIVAAkJJhzPFQCSAgAVAAkJJhzPFQCSAgAAAA==.Nerppie:BAACLgAFFH8GAAIHAAMJyCBSHwAcAQAHAAMJyCBSHwAcAQAuAAQKfzgAAgcACQnUH18HABQDAAcACQnUH18HABQDAAAA.Nevershark:BAAALgAECgUJBQAAAA==.',
Ni='Nightfallz:BAAALgADCgUJBQAAAA==.Nina:BAABLgAECn8ZAAIIAAcJdRpRTwD0AQAIAAcJdRpRTwD0AQAAAA==.Nixah:BAAALgAECgUJDQAAAA==.',
Nk='Nkript:BAABLgAECn8uAAMBAAkJthkmHgBtAgABAAkJthkmHgBtAgAPAAYJpgiJTwARAQAAAA==.',
No='Nortel:BAAALgAECgYJDgAAAA==.',
Oh='Ohgourdness:BAAALgADCgcJBwABLgAECgYJFQALAPgEAA==.',
On='Onari:BAABLgAECn8rAAMCAAkJ6h3/CQDFAgACAAkJ6h3/CQDFAgAiAAMJOA+0WACYAAAAAA==.',
Or='Orious:BAAALgADCgYJBgAAAA==.',
Pa='Paine:BAAALgAECgEJAQAAAA==.Pandagang:BAAALgADCgQJBQAAAA==.',
Pe='Peezee:BAABLgAECn8XAAMIAAgJ9w+4iABcAQAIAAgJbw24iABcAQAjAAYJSg3vKADMAAAAAA==.Perce:BAABLgAECn82AAMHAAkJACC6BwAOAwAHAAkJACC6BwAOAwAIAAQJJBnIngA3AQAAAA==.Peyotte:BAABLgAECn8VAAIKAAgJgB8NDgAHAgAKAAgJgB8NDgAHAgABLgAFFAQJBwAQAJQUAA==.',
Pf='Pfemme:BAABLgAECn8qAAIBAAkJDx5LGwB8AgABAAkJDx5LGwB8AgAAAA==.',
Pp='Pp:BAAALgAECgQJBAAAAA==.',
Ps='Psych:BAAALgADCgYJBgAAAA==.',
Pu='Purian:BAAALgADCgcJDwAAAA==.',
Ra='Rainfall:BAAALgAECgMJAwAAAA==.Rami:BAAALgADCgYJBgAAAA==.',
Re='Repello:BAAALgAECgYJBwAAAA==.Reyaieleron:BAAALgAECgYJEAAAAA==.',
Ri='Ricky:BAAALgADCgEJAQAAAA==.Rivenaer:BAABLgAECn82AAMkAAkJxBAPGQC1AQAkAAkJxBAPGQC1AQAVAAEJiAI2NgEaAAAAAA==.',
Ru='Ruindsoul:BAAALgADCgcJCwAAAA==.Ruka:BAAALgADCgEJAQAAAA==.Runearne:BAAALgAECgIJAgAAAA==.Rus:BAAALgAECgUJBQABLgAECgkJIQARAEESAA==.Rustymark:BAACLgAFFH8PAAIBAAQJSA1oRAAeAQABAAQJSA1oRAAeAQAuAAQKfyEAAgEACQlbF24gAGECAAEACQlbF24gAGECAAAA.',
Sc='Scaletal:BAAALgAECgUJBQAAAA==.Schmetzy:BAAALgAECgYJCAAAAA==.Schmezzy:BAABLgAECn8cAAIXAAgJvB27SADmAQAXAAgJvB27SADmAQAAAA==.Scuti:BAAALgAECgQJBQAAAA==.',
Se='Sealalicious:BAABLgAECn8+AAIjAAkJrx0zBQCdAgAjAAkJrx0zBQCdAgAAAA==.Seenaa:BAAALgAECgQJBAAAAA==.Seân:BAAALgAECgEJAQAAAA==.',
Sh='Shallot:BAAALgADCgYJEgAAAA==.Shammywow:BAAALgAECgUJEgAAAA==.Sharkzilla:BAABLgAECn8YAAIBAAkJKx0wFwB/AgABAAkJKx0wFwB/AgAAAA==.Shauray:BAAALgADCgYJCgAAAA==.Shine:BAABLgAECn8sAAMBAAgJDB1nJwA+AgABAAgJeBxnJwA+AgASAAUJXBSVMwASAQAAAA==.Shrub:BAAALgADCgcJBwABLgAFFAkJGwAiACwhAA==.',
Si='Silksmilk:BAAALgADCgIJAgAAAA==.Siobhân:BAAALgAECgYJDAAAAA==.',
Sl='Sloppy:BAAALgAECgYJCAAAAA==.',
Sm='Smashchie:BAAALgAECgEJAQAAAA==.Smoo:BAAALgAECgUJBgAAAA==.Smythe:BAAALgADCgEJAQAAAA==.',
Sn='Snø:BAAALgAECgcJDwAAAA==.',
So='Sobol:BAAALgAFFAEJAgAAAA==.Soggyaugi:BAAALgAECgYJDQAAAA==.Solbinder:BAAALgADCgIJAgAAAA==.Soraa:BAEALgAECgUJDwABLgAECgkJHgAEADIfAA==.Soulbleeder:BAAALgAECgQJBAAAAA==.',
St='Starlethia:BAAALgAECggJEwAAAA==.',
Su='Sumpnclaws:BAAALgAECgYJBgAAAA==.Sunshine:BAAALgAECgcJDAAAAA==.Sunwälker:BAAALgADCgQJBAAAAA==.',
Sy='Sybelin:BAAALgAECgMJAwAAAA==.',
Ta='Tallchief:BAABLgAECn8fAAIBAAYJTxFZfABBAQABAAYJTxFZfABBAQAAAA==.Talliah:BAAALgAECgQJBQAAAA==.Tamarynn:BAAALgADCgUJBQABLgAECggJMwACADAMAA==.Tankufrdying:BAAALgAECgUJCAAAAA==.Tarkuroth:BAAALgADCgQJBAAAAA==.Tavarien:BAAALgADCgEJAQAAAA==.Tayllana:BAAALgAECgEJAQAAAA==.',
Te='Tenjo:BAAALgAECgYJEAAAAA==.Terrier:BAAALgAECgEJAQAAAA==.',
Th='Thaerdran:BAABLgAECn8mAAIYAAkJFRtYDABFAgAYAAkJFRtYDABFAgAAAA==.',
Ti='Tierri:BAAALgAECgEJAgAAAA==.Tirriel:BAAALgADCgMJAwAAAA==.',
To='Toess:BAAALgAECgEJAQAAAA==.Tonati:BAAALgAECgMJAwAAAA==.Tonjuren:BAAALgAECgMJBwABLgAECgYJLwAdAOcWAA==.',
Tr='Travosaur:BAAALgAFFAEJAQAAAA==.Trublood:BAABLgAECn8cAAIDAAcJPAgRQwAAAQADAAcJPAgRQwAAAQAAAA==.Truelder:BAAALgADCgQJBAAAAA==.',
Tw='Twister:BAAALgAECgQJDwAAAA==.',
Ty='Tyrra:BAAALgADCgMJAwAAAA==.',
Uk='Ukeenonme:BAAALgAECgIJAgAAAA==.',
Us='Usorloups:BAACLgAFFH8HAAIQAAQJlBTJLwDMAAAQAAQJlBTJLwDMAAAuAAQKfyAAAhAACQnCH3EPAHgCABAACQnCH3EPAHgCAAAA.',
Va='Vaelar:BAAALgAECgYJBgAAAA==.Valstad:BAAALgAECgYJEgAAAA==.',
Ve='Velonys:BAABLgAECn82AAQFAAkJayKgAQDEAgAFAAgJmSOgAQDEAgAlAAYJdBZTfgA8AQAeAAQJLCBxFgAQAQAAAA==.Velus:BAAALgAECgQJBAAAAA==.',
Vi='Victory:BAAALgAECgEJAQAAAA==.Vintar:BAAALgADCgMJAwAAAA==.',
Vo='Volkhikos:BAAALgAECgcJCAAAAA==.',
Vy='Vyral:BAAALgAECgQJBgAAAA==.Vyu:BAAALgAECgkJCgAAAA==.',
Wa='Wanayu:BAABLgAECn8kAAIFAAkJTBlrBAAzAgAFAAkJTBlrBAAzAgAAAA==.Wanweasley:BAAALgAECgkJEgAAAA==.',
We='Weeab:BAAALgADCgEJAQAAAA==.Weezlee:BAAALgAECgQJBAAAAA==.Weh:BAABLgAECn8YAAIEAAkJryJ6JQCDAgAEAAkJryJ6JQCDAgAAAA==.',
Wi='Wickedsham:BAAALgADCgIJAgAAAA==.Willic:BAAALgAECgcJBwAAAA==.Wintermourne:BAABLgAECn8fAAIbAAkJfAdNEgBPAQAbAAkJfAdNEgBPAQAAAA==.Wizagon:BAABLgAECn8XAAIUAAkJlBsHBAA/AgAUAAkJlBsHBAA/AgAAAA==.',
Wo='Woodsy:BAABLgAECn8lAAITAAkJAhz6BADLAgATAAkJAhz6BADLAgAAAA==.Wounded:BAAALgAECgEJAgAAAA==.Woundliquor:BAAALgAECgcJEQAAAA==.',
Wu='Wuinn:BAACLgAFFH8RAAMLAAQJlCARHQBoAQALAAQJlCARHQBoAQAMAAMJpQOuPAB6AAAuAAQKfzMAAwsACQn0Id4PALkCAAsACQn0Id4PALkCABoABwlSGMIVAKABAAAA.',
Xe='Xemnas:BAABLgAECn87AAQXAAcJ/Q4emgAzAQAXAAcJgA0emgAzAQAbAAQJsA7mJACkAAAYAAIJ7wFGXAAwAAAAAA==.',
Ya='Yawnday:BAAALgAECgMJAwABLgAECggJEQAOAAAAAA==.Yawnight:BAAALgAECggJEQAAAA==.',
Ys='Yserra:BAAALgAECgMJBAAAAA==.',
Za='Zaryala:BAAALgADCgkJKAAAAA==.',
Ze='Zenshift:BAAALgAECgMJCAAAAA==.',
Zy='Zynthia:BAACLgAFFH8GAAIXAAIJTyQLogDRAAAXAAIJTyQLogDRAAAuAAQKfzAAAhcACQn9JJcFAEwDABcACQn9JJcFAEwDAAAA.',
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
