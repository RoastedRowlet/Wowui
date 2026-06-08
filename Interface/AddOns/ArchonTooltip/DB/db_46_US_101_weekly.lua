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

local lookup = {'Priest-Discipline','Warrior-Protection','Hunter-BeastMastery','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Havoc','DemonHunter-Devourer','Shaman-Restoration','Monk-Mistweaver','Unknown-Unknown','Evoker-Preservation','Rogue-Assassination','Warlock-Affliction','Monk-Windwalker','Paladin-Retribution','Mage-Frost','DeathKnight-Unholy','Druid-Restoration','Priest-Shadow','Priest-Holy','Paladin-Holy','Shaman-Elemental','Druid-Balance','Monk-Brewmaster','Paladin-Protection','DeathKnight-Blood','Warlock-Demonology','Hunter-Survival','DemonHunter-Vengeance','Druid-Guardian','Druid-Feral','Hunter-Marksmanship','Warlock-Destruction','DeathKnight-Frost','Shaman-Enhancement','Warrior-Fury','Mage-Arcane',}
local provider = {region='US',realm='Galakrond',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aaravos:BAAALgAECgEJAQABLgAECggJNgABAEAhAA==.',
Ae='Aegisthal:BAACLgAFFH8KAAICAAQJ6RnlDgAtAQACAAQJ6RnlDgAtAQAuAAQKfxsAAgIACQldIG4FALYCAAIACQldIG4FALYCAAAA.Aequitasx:BAAALgAECgcJCQAAAA==.Aeristella:BAAALgAECgEJAQAAAA==.',
Ah='Ahrus:BAAALgADCgMJBgABLgAECggJLgADADIMAA==.',
Ak='Akåshå:BAAALgADCgMJAwAAAA==.',
Al='Alanerazza:BAAALgADCgcJDQAAAA==.Althenzdormu:BAABLgAECn8pAAMEAAgJBw5iCgBsAQAEAAgJmA1iCgBsAQAFAAcJiArNRwAAAQAAAA==.Altruist:BAABLgAECn8fAAMGAAgJ3RsyDgAxAgAGAAgJ3RsyDgAxAgAHAAIJnAQT/ABAAAABLgAECggJNgACAL0ZAA==.',
Am='Amaethon:BAAALgAECggJEwAAAA==.',
An='Ancaera:BAAALgADCgcJBwAAAA==.Andalikus:BAABLgAECn8/AAIIAAkJER+gDADpAgAIAAkJER+gDADpAgAAAA==.Andorra:BAAALgADCggJBwAAAA==.Andïea:BAAALgADCgEJAQAAAA==.Anrien:BAABLgAECn82AAIBAAgJQCGQBwD2AgABAAgJQCGQBwD2AgAAAA==.',
Ar='Arathor:BAAALgAECgYJCgAAAA==.Ari:BAABLgAECn8WAAIJAAgJTAgWOwD6AAAJAAgJTAgWOwD6AAAAAA==.Ariany:BAAALgADCgcJBwAAAA==.Ariyia:BAAALgAECgYJEgAAAA==.Arms:BAAALgAECgEJAQABLgAECgQJCwAKAAAAAA==.Around:BAAALgAECgEJAQAAAA==.',
As='Asgorath:BAAALgADCgQJBAAAAA==.Asharal:BAABLgAECn8uAAQEAAgJ9xXaBgDMAQAEAAgJ9xXaBgDMAQALAAQJpxQLHwD1AAAFAAEJsQO0kwAkAAAAAA==.Ashlayah:BAAALgAECgYJBwAAAA==.',
Au='Aunyx:BAABLgAECn82AAIMAAgJABFNCQCgAQAMAAgJABFNCQCgAQAAAA==.',
Az='Azbogah:BAAALgAECgUJDQAAAA==.',
Ba='Babyjack:BAAALgADCgcJCAABLgAECgYJFAANAGkVAA==.Baloth:BAAALgADCgYJBgABLgAECggJMAAOAEkbAA==.Balthenor:BAACLgAFFH8GAAIPAAIJqxMpIgCoAAAPAAIJqxMpIgCoAAAuAAQKfx4AAg8ACAn+IZMRAAQDAA8ACAn+IZMRAAQDAAAA.',
Be='Beej:BAABLgAECn8qAAIJAAkJyRpnDQC1AgAJAAkJyRpnDQC1AgAAAA==.Belenjan:BAAALgAECgYJCwAAAA==.Belestius:BAAALgADCgYJCwABLgADCgkJGAAKAAAAAA==.Berse:BAABLgAECn8YAAIDAAYJRB94bgBYAQADAAYJRB94bgBYAQAAAA==.',
Bi='Bilko:BAAALgADCgcJCAAAAA==.Birdymage:BAABLgAECn8VAAIQAAUJHBT7wQABAQAQAAUJHBT7wQABAQAAAA==.',
Bl='Blightbeard:BAABLgAECn8VAAIRAAgJLAi+jABDAQARAAgJLAi+jABDAQAAAA==.Blîss:BAAALgAECgYJCAAAAA==.',
Bo='Bolong:BAAALgAECgMJAwABLgAFFAcJIAARAHkUAA==.Bonebroth:BAAALgAECgMJAwAAAA==.Bonehealer:BAAALgAECgQJBAAAAA==.',
Br='Brut:BAABLgAECn8gAAIHAAkJNx61RACtAQAHAAkJNx61RACtAQAAAA==.',
Bu='Bustus:BAABLgAECn8rAAISAAgJJw02SwBYAQASAAgJJw02SwBYAQAAAA==.',
Ca='Carmasutra:BAAALgADCggJCAAAAA==.Caroll:BAABLgAECn8YAAQBAAcJoxUZJgCSAQABAAYJ1BUZJgCSAQATAAcJaRAhMQBQAQAUAAMJexQyRQDFAAAAAA==.Carsomavra:BAAALgAECgEJAQAAAA==.Cathercy:BAABLgAECn8gAAIPAAYJNg+KswAOAQAPAAYJNg+KswAOAQAAAA==.',
Ch='Cheese:BAAALgAECgEJAQAAAA==.Chenzhen:BAABLgAECn8ZAAIQAAYJAA1QuQAPAQAQAAYJAA1QuQAPAQAAAA==.Chilly:BAABLgAECn8VAAMPAAYJSgwjqwAsAQAPAAYJSgwjqwAsAQAVAAEJrwEjnAAYAAABLgAFFAUJEAAJAIYSAA==.Chunt:BAAALgAECgQJBQAAAA==.',
Co='Compliance:BAABLgAECn82AAICAAgJvRklDgD7AQACAAgJvRklDgD7AQAAAA==.Corannis:BAABLgAECn8qAAIWAAgJURZFIwC+AQAWAAgJURZFIwC+AQAAAA==.Cowabunga:BAAALgADCgkJCQABLgAFFAMJBwAXAGYIAA==.',
Cr='Cranberries:BAABLgAECn8bAAMUAAcJyxcyJQCMAQAUAAYJpxgyJQCMAQABAAcJNRDuLABjAQAAAA==.Crockett:BAAALgADCggJCAABLgAECgUJEAAKAAAAAA==.',
Cu='Cuauhtzin:BAAALgAECgkJCQAAAA==.Cupcáke:BAAALgAECgIJAgAAAA==.Curtis:BAAALgAECgYJDQABLgAECgkJMQAYAEEfAA==.',
Da='Daberserker:BAAALgADCgUJBQAAAA==.Dalmas:BAAALgAECgMJCAAAAA==.Dalra:BAAALgADCgUJBQABLgAECgkJOwAGAGYVAA==.Dantez:BAABLgAECn8UAAMXAAgJFh8LDQB8AgAXAAgJFh8LDQB8AgASAAYJ3A5RXAAYAQAAAA==.Darkgenie:BAAALgADCgEJAgAAAA==.Darlight:BAAALgAECggJCAAAAA==.Darlàrk:BAABLgAECn8qAAIHAAkJAhv+HQBWAgAHAAkJAhv+HQBWAgAAAA==.Dawnmane:BAAALgAECggJCAAAAA==.',
De='Delderach:BAABLgAECn8gAAIZAAYJmRI6HgAWAQAZAAYJmRI6HgAWAQAAAA==.Delosine:BAAALgADCgUJCgAAAA==.Demise:BAAALgADCgMJAwAAAA==.Denîn:BAABLgAECn82AAIRAAkJHRyLIQB6AgARAAkJHRyLIQB6AgAAAA==.',
Di='Dirkette:BAABLgAECn8pAAIBAAkJMwTqMwA6AQABAAkJMwTqMwA6AQAAAA==.Dirknelf:BAAALgADCgEJAQABLgAECgkJKQABADMEAA==.Dirksavoid:BAAALgAECgUJBQABLgAECgkJKQABADMEAA==.Dixonmayas:BAAALgAECgYJDAAAAA==.',
Do='Dokai:BAABLgAECn8wAAIOAAgJSRsfEwAaAgAOAAgJSRsfEwAaAgAAAA==.',
Dr='Dracmiz:BAAALgAECgQJBQAAAA==.Dragenous:BAAALgAECgMJBAAAAA==.Dragmartigan:BAAALgAECgQJCQABLgAECgYJEgAKAAAAAA==.Dragndeznuts:BAAALgAECgcJBwABLgAECgkJOQAaAHcWAA==.Dragoran:BAAALgAECgUJBQAAAA==.Drathan:BAAALgAECgMJAgAAAA==.Drewella:BAAALgADCgkJCQAAAA==.',
El='Elaenei:BAAALgADCgkJLAAAAA==.Eliance:BAABLgAECn8gAAIMAAYJpwQvFgC/AAAMAAYJpwQvFgC/AAAAAA==.Elienn:BAAALgAECgIJAgAAAA==.Elsewhere:BAABLgAECn8dAAMFAAkJMQ/LJQCpAQAFAAkJMQ/LJQCpAQALAAEJwQiFPgAkAAAAAA==.',
Em='Emberly:BAAALgAECgYJBgAAAA==.Emmily:BAAALgADCgYJDAAAAA==.',
En='Enuia:BAAALgADCgUJBQAAAA==.',
Er='Eririn:BAAALgAECgEJAgAAAA==.Errius:BAABLgAECn8qAAIaAAkJmhaaEwDMAQAaAAkJmhaaEwDMAQAAAA==.',
Eu='Eunja:BAEALgAECgYJDAAAAQ==.',
Ev='Evangelica:BAAALgAECgMJAwAAAA==.',
Fa='Fatherbetter:BAAALgAECgYJCAABLgAECgkJJQAHAHMhAA==.',
Fe='Feeltheburn:BAAALgAFFAIJAgABLgAFFAUJDAARAHQGAA==.Feloras:BAAALgAECgYJEAAAAA==.',
Fl='Flamemane:BAAALgADCgIJAgAAAA==.',
Fo='Foxina:BAAALgADCgcJCgAAAA==.',
Fu='Fusaa:BAABLgAECn9DAAIbAAkJpRd4IgBSAgAbAAkJpRd4IgBSAgAAAA==.',
Ga='Gahzoo:BAAALgADCgQJAQAAAA==.Gallindo:BAAALgADCgYJBgABLgAECgcJFQAcAM4TAA==.Gangry:BAAALgAECgQJCQAAAA==.',
Ge='Gelst:BAAALgAECgEJAQAAAA==.Gerbzarrion:BAABLgAECn8eAAIQAAYJBArcxAD9AAAQAAYJBArcxAD9AAAAAA==.Gerudo:BAAALgAECgQJBAAAAA==.Getherdone:BAAALgAECgYJBgAAAA==.',
Gi='Gilgador:BAABLgAECn87AAIGAAkJZhWREQACAgAGAAkJZhWREQACAgAAAA==.',
Gl='Glyslam:BAAALgAFFAIJAgAAAA==.',
Go='Gord:BAAALgADCgYJBgAAAA==.',
Gr='Gravewalker:BAAALgAECgYJCgAAAA==.Gream:BAAALgADCgcJCgAAAA==.Greepster:BAAALgAECgYJEwAAAA==.Gripreaper:BAAALgAFFAIJAwAAAA==.',
Ha='Haggrum:BAAALgADCgIJAgAAAA==.Haley:BAAALgAECgEJAQABLgAECgQJCwAKAAAAAA==.Hawknnin:BAABLgAECn8dAAIVAAYJNSS7EwBnAgAVAAYJNSS7EwBnAgAAAA==.',
He='Hechicera:BAAALgAECgkJEgAAAA==.Hectorjbm:BAAALgADCgMJBAAAAA==.Here:BAAALgAECgEJAwAAAA==.',
Hu='Hunterpulled:BAABLgAFFH8GAAIDAAIJ3A/xcgCaAAADAAIJ3A/xcgCaAAAAAA==.Huntrod:BAAALgADCgEJBgAAAA==.Huroona:BAAALgAECgMJAwAAAA==.Huskiè:BAAALgADCgYJDAAAAA==.',
Hy='Hyasinth:BAAALgADCgQJBAABLgAECgkJGwAUAMsXAA==.',
Ip='Ipwnallnoobs:BAABLgAECn8dAAIRAAkJ1Q3nUwDBAQARAAkJ1Q3nUwDBAQAAAA==.',
Ir='Irisila:BAAALgAECgQJBAABLgAECgcJFQAcAM4TAA==.Ironfists:BAAALgADCgMJAwAAAA==.',
Ja='Jagel:BAAALgADCgQJBAAAAA==.Jahkwellynn:BAAALgADCgEJAQAAAA==.Jairian:BAAALgADCgkJCQAAAA==.Jakoti:BAAALgADCgUJCQAAAA==.Jaxsi:BAAALgAECgQJCwAAAA==.Jaypharyn:BAABLgAECn8sAAISAAgJCBzvFgCGAgASAAgJCBzvFgCGAgAAAA==.',
Jo='Johalea:BAAALgAECgMJAwAAAA==.',
['Jå']='Jåsper:BAABLgAECn8WAAIPAAcJrhxiSwDaAQAPAAcJrhxiSwDaAQAAAA==.',
Ka='Kabbek:BAAALgADCgYJBgAAAA==.Kaileena:BAABLgAECn8xAAIdAAkJ0hfKBgAQAgAdAAkJ0hfKBgAQAgAAAA==.Kaimare:BAAALgADCgUJCgAAAA==.Kandistars:BAABLgAECn8oAAIXAAkJoBEmHwDBAQAXAAkJoBEmHwDBAQAAAA==.Kasia:BAABLgAECn8kAAIIAAgJnhu+JAAkAgAIAAgJnhu+JAAkAgAAAA==.Kazahana:BAAALgADCgkJCQAAAA==.',
Ke='Keeffer:BAAALgADCgEJAQAAAA==.',
Kh='Kharnas:BAAALgADCgYJCQAAAA==.',
Ki='Kierrings:BAABLgAECn8bAAIRAAgJiBYlWwCuAQARAAgJiBYlWwCuAQAAAA==.Kirarah:BAABLgAECn8xAAIDAAgJECRMDgDVAgADAAgJECRMDgDVAgAAAA==.Kirarose:BAACLgAFFH8TAAMTAAUJrBsvEQBLAQATAAUJrBsvEQBLAQAUAAIJ2gGVMABDAAAuAAQKfxwAAxMACQmmIj4QAFICABMACQmmIj4QAFICABQAAwmECWxoAIsAAAAA.Kitcarson:BAAALgADCgUJCAAAAA==.',
Kl='Klauss:BAABLgAECn82AAIJAAkJRA+bKwC7AQAJAAkJRA+bKwC7AQAAAA==.Klax:BAAALgAECgYJCgAAAA==.',
Ko='Kordjin:BAAALgAECgUJCgAAAA==.',
Kr='Krornik:BAAALgAECggJEwAAAA==.Krunch:BAAALgADCgkJGAABLgAECgYJCgAKAAAAAA==.',
Ky='Kylia:BAABLgAECn8iAAINAAgJRhsWBQAtAgANAAgJRhsWBQAtAgAAAA==.',
['Kí']='Kíhanna:BAABLgAECn8rAAIDAAkJOyF1DgDUAgADAAkJOyF1DgDUAgAAAA==.',
La='Larissa:BAAALgAECgYJDAAAAA==.',
Le='Leangra:BAAALgADCgUJCQAAAA==.Legenddairy:BAACLgAFFH8HAAIXAAMJZgglMgCiAAAXAAMJZgglMgCiAAAuAAQKfz0AAx4ACQn1GKkJADsCAB4ACQn1GKkJADsCABcACQlGEPEvAIgBAAAA.',
Li='Lizardath:BAACLgAFFH8JAAMcAAMJIAVvKACFAAAcAAMJJQFvKACFAAADAAIJhwfqfwCEAAAuAAQKfyQAAwMACQmKCbR0AEoBAAMACAkjCrR0AEoBABwAAgnOBpVNAG4AAAAA.',
Lj='Ljósálfr:BAABLgAECn88AAICAAkJuCPSAgAMAwACAAkJuCPSAgAMAwAAAA==.',
Lo='Lochramae:BAABLgAECn85AAIaAAkJdxYKFgCuAQAaAAkJdxYKFgCuAQAAAA==.Logarius:BAAALgADCgQJBAAAAA==.Loupe:BAAALgADCgYJCwAAAA==.',
Lu='Lumanoughty:BAAALgADCgkJHQAAAA==.Lunargaze:BAABLgAECn8lAAIHAAgJcyE8FQCQAgAHAAgJcyE8FQCQAgAAAA==.',
Ly='Lyssena:BAAALgAECgUJBQABLgAFFAEJAQAKAAAAAA==.',
Ma='Macha:BAAALgADCgEJAQAAAA==.Madmartigan:BAAALgADCggJDgABLgAECgYJEgAKAAAAAA==.Magjistar:BAAALgADCgMJAwAAAA==.Mahangi:BAAALgADCgkJEAAAAA==.Mamimisan:BAABLgAECn8uAAIIAAkJHR+pCwD0AgAIAAkJHR+pCwD0AgAAAA==.Marmalade:BAAALgADCgkJCQAAAA==.',
Me='Meatball:BAAALgADCgYJBgAAAA==.Mecaris:BAAALgAECgYJBgABLgAFFAIJBgAPAKsTAA==.Medios:BAAALgAECgkJDwAAAA==.Mehumah:BAAALgADCgkJEQAAAA==.Mel:BAAALgADCgUJBQAAAA==.Melusine:BAAALgADCgcJBwAAAA==.Metalicfox:BAAALgAECgUJDAAAAA==.',
Mi='Mistazee:BAAALgAECgQJBAAAAA==.Mitsumi:BAAALgAECgUJDQAAAA==.Miz:BAABLgAECn8WAAMeAAcJoRiRFACfAQAeAAcJoRiRFACfAQASAAMJ7Ab2qwBWAAAAAA==.Mizkat:BAABLgAECn8mAAQeAAkJhxrICABRAgAeAAkJhxrICABRAgAfAAEJSw5ZSgA1AAASAAIJHA2bzwAvAAAAAA==.',
Mo='Mojomoe:BAAALgADCggJCQAAAA==.Morket:BAAALgADCgMJAwAAAA==.Mormra:BAABLgAECn8uAAMDAAgJMgyUZABuAQADAAgJMgyUZABuAQAgAAEJ1QG/QgAbAAAAAA==.',
Mu='Mushroom:BAAALgADCgYJCQAAAA==.Mustard:BAEBLgAECn8sAAQcAAgJlSVXBgCfAgAcAAcJ4iRXBgCfAgADAAYJliS1OwDlAQAgAAIJ/SOsHQC1AAAAAA==.',
['Më']='Mërcy:BAAALgAECgMJAwAAAA==.',
Na='Naklus:BAAALgAECgYJDQAAAA==.Nathan:BAAALgADCgcJBwAAAA==.',
Ne='Neilia:BAABLgAECn8gAAIIAAkJSBQVIABCAgAIAAkJSBQVIABCAgABLgAECgkJOwAGAGYVAA==.Nekra:BAAALgAECgEJAQAAAA==.Nezot:BAAALgAECgEJAQAAAA==.',
Ni='Nitehawk:BAAALgADCgEJAQAAAA==.Nixilia:BAAALgADCgUJBQAAAA==.',
Nl='Nlani:BAAALgAECgcJDAAAAA==.',
Nu='Nuncadragon:BAAALgAECgEJAQAAAA==.Nuvi:BAAALgAECgkJEAAAAA==.',
Ol='Olivia:BAAALgAFFAQJBAABLgAFFAgJGgAHACshAA==.',
Or='Orees:BAAALgAECgEJAQAAAA==.Orihime:BAAALgAECgEJAQAAAA==.',
Ox='Oxygentank:BAABLgAECn8aAAIfAAYJWxofEgCHAQAfAAYJWxofEgCHAQAAAA==.',
Pa='Parne:BAAALgADCggJDQAAAA==.',
Ph='Phatbutfun:BAAALgADCgMJAwAAAA==.Phóenix:BAAALgAECgIJAwAAAA==.',
Pi='Pips:BAAALgADCgcJBwAAAA==.',
Pl='Platura:BAABLgAECn8rAAIVAAgJ+RlFGQAwAgAVAAgJ+RlFGQAwAgAAAA==.Plection:BAAALgADCgEJAQAAAA==.',
Ra='Raezune:BAAALgADCgMJBgAAAA==.Rajia:BAABLgAECn82AAIhAAgJChJaCwB8AQAhAAgJChJaCwB8AQAAAA==.Ralaan:BAAALgADCgUJBQABLgAECggJLgADADIMAA==.Ranron:BAAALgAECgQJBgAAAA==.Rassaphore:BAABLgAECn8hAAIOAAgJfiE5CQClAgAOAAgJfiE5CQClAgAAAA==.Raziik:BAAALgADCgYJBgAAAA==.Raínbow:BAAALgAECgEJAQAAAA==.',
Re='Reapin:BAABLgAECn8kAAIiAAgJwxWeCwCvAQAiAAgJwxWeCwCvAQAAAA==.',
Ri='Rilorren:BAAALgADCgcJCgABLgAECgkJIAAHADceAA==.Rionach:BAABLgAECn82AAIeAAgJ2QhOMADVAAAeAAgJ2QhOMADVAAAAAA==.Ritsara:BAABLgAECn8UAAIZAAcJyQ07JADlAAAZAAcJyQ07JADlAAAAAA==.Riven:BAAALgAECgIJAgABLgAECgYJCgAKAAAAAA==.Rivon:BAABLgAECn8jAAMVAAkJgxgMHwD/AQAVAAgJWBcMHwD/AQAPAAEJagsHagE+AAAAAA==.Rivonsshield:BAAALgADCgYJBgAAAA==.',
Ro='Ro:BAAALgADCgYJBgAAAA==.Rothu:BAAALgAECgYJDAABLgAFFAMJCAAHAMwWAA==.Rowena:BAAALgADCgYJBgAAAA==.',
Ru='Ruka:BAAALgAECgEJAQAAAA==.',
Sa='Salenias:BAAALgADCgkJDAAAAA==.Sannicor:BAAALgADCgMJBAAAAA==.Saonji:BAAALgADCgcJDgAAAA==.',
Sc='Scoop:BAAALgAECgYJDAAAAA==.',
Se='Seanan:BAABLgAECn8cAAIjAAkJnx9KAgD0AgAjAAkJnx9KAgD0AgABLgAECgkJKQAPAHgdAA==.Seanx:BAABLgAECn8pAAMPAAkJeB2QHwCAAgAPAAkJeB2QHwCAAgAZAAYJhhJAIgD1AAAAAA==.',
Sh='Shenlong:BAABLgAFFH8IAAIRAAIJrhkrxwCOAAARAAIJrhkrxwCOAAAAAA==.Shigurexx:BAABLgAECn8+AAMDAAkJUSCkCwDtAgADAAkJUSCkCwDtAgAgAAYJ8xoZDgBvAQAAAA==.Shoe:BAABLgAECn8/AAMEAAkJBhw4AwBhAgAEAAkJBhw4AwBhAgAFAAcJyxAtJgCmAQAAAA==.Shootup:BAAALgAECgIJAgAAAA==.',
Si='Sigmandis:BAABLgAECn8UAAIPAAcJ8gMl6gDEAAAPAAcJ8gMl6gDEAAAAAA==.Siph:BAAALgAECgYJEQAAAA==.',
Sk='Sklook:BAAALgAECgEJAQAAAA==.Skolam:BAAALgADCgYJDAAAAA==.',
So='Soitgoes:BAAALgAECgYJBgAAAA==.Somassen:BAAALgAECgMJAwAAAA==.Sorrengail:BAAALgAECgIJAgAAAA==.Soulforge:BAAALgAECgMJAwAAAA==.',
Sq='Squanchy:BAAALgADCgcJBAAAAA==.',
St='Stalestorn:BAAALgADCgIJAgAAAA==.',
Su='Sunquell:BAAALgAECgMJAwAAAA==.Surii:BAAALgAECgUJDgAAAA==.Surtrr:BAAALgAFFAQJBAAAAA==.',
Sw='Sweeneytodd:BAAALgAECgEJAgAAAA==.',
Sy='Symmastus:BAAALgAECgMJBQAAAA==.',
Ta='Taliadrin:BAAALgAECgMJAwAAAA==.Tamarins:BAABLgAECn8kAAICAAgJlxbrEwCkAQACAAgJlxbrEwCkAQAAAA==.Taryeth:BAAALgAECgEJAQAAAA==.',
Te='Terkarakk:BAACLgAFFH8JAAIeAAQJiBC9EQDdAAAeAAQJiBC9EQDdAAAuAAQKfxwAAh4ACQmwHw8FALICAB4ACQmwHw8FALICAAAA.',
Th='There:BAAALgAECgcJDQAAAA==.Thetamoon:BAAALgADCgUJBQAAAA==.Thireaux:BAAALgAECgQJBQAAAA==.Thorybos:BAABLgAECn8UAAIQAAYJNSBhVADZAQAQAAYJNSBhVADZAQAAAA==.',
To='Toom:BAABLgAECn8gAAIDAAYJTQ3diAAgAQADAAYJTQ3diAAgAQAAAA==.',
Tr='Traylinna:BAAALgADCgQJBAAAAA==.Tritas:BAAALgAECgIJAgABLgAECgkJOwAGAGYVAA==.Trophyhubby:BAABLgAECn8qAAMTAAkJIAcFMQBQAQATAAkJIAcFMQBQAQAUAAcJ5QxZOAALAQAAAA==.',
Tu='Tuknark:BAAALgAECgEJAQAAAA==.Tuktuvak:BAAALgAECgUJCgABLgAECgkJPAACALgjAA==.Tuladrin:BAAALgADCgQJBAAAAA==.',
Ty='Tyeren:BAAALgAECgcJEgAAAA==.Tyeriel:BAACLgAFFH8gAAMRAAcJeRQMHQDeAQARAAYJeRQMHQDeAQAaAAEJAAB0UAAAAAAuAAQKfx8AAxEACQnZHtkiALQCABEACAn/HtkiALQCABoAAwkMGqkwANIAAAAA.Tyrîel:BAAALgADCgcJBwABLgAFFAcJIAARAHkUAA==.',
Us='Usato:BAAALgAECgYJEgAAAA==.',
Va='Valat:BAAALgADCgkJFAAAAA==.Valkyriefall:BAAALgAECgMJBQAAAA==.Valkyriewing:BAABLgAECn8aAAIPAAYJUgp4ywDsAAAPAAYJUgp4ywDsAAAAAA==.Valvet:BAAALgADCgkJLgAAAA==.Vardanis:BAAALgADCggJDwAAAA==.',
Vi='Vikril:BAACLgAFFH8MAAIRAAUJdAaRegD/AAARAAUJdAaRegD/AAAuAAQKfxcAAxEACQlHE/d5AGcBABEACAmdCfd5AGcBABoABQm7G04iADYBAAAA.Vincenzo:BAAALgAECgEJAgAAAA==.Vixer:BAAALgAECgQJBgAAAA==.',
Vl='Vleesroos:BAAALgAECgUJCQAAAA==.',
Vo='Vog:BAAALgADCgYJBgAAAA==.Voidquèèn:BAAALgADCgEJAQAAAA==.Volkanoth:BAABLgAECn8VAAIHAAcJHiTjJQBvAgAHAAcJHiTjJQBvAgAAAA==.Volora:BAAALgAECgEJAgABLgAECgIJAwAKAAAAAA==.',
Vu='Vue:BAAALgADCgcJBwABLgAECgYJCgAKAAAAAA==.',
Vy='Vylus:BAAALgAECgQJBwAAAA==.',
['Vá']='Vásh:BAAALgADCgkJEQAAAA==.',
We='Webjibaro:BAAALgAECgQJCgAAAA==.Weeblewobble:BAAALgAECgEJAQAAAA==.',
Wi='Wikidblade:BAAALgAECgQJCQAAAA==.William:BAABLgAECn8mAAIDAAkJBiJ4BwAaAwADAAkJBiJ4BwAaAwAAAA==.Windee:BAABLgAECn8ZAAIOAAYJqg2pQQDrAAAOAAYJqg2pQQDrAAAAAA==.',
Wr='Wrast:BAABLgAECn8lAAMgAAgJnglUGgDRAAADAAYJNwwglAAKAQAgAAcJkwZUGgDRAAAAAA==.Wravyn:BAAALgAECgUJCQAAAA==.',
Xy='Xyara:BAACLgAFFH8JAAMNAAQJuw6fDACmAAAbAAMJgAj8eQDBAAANAAIJuhWfDACmAAAuAAQKfyYABA0ACQk0HSMEAFMCAA0ACQk0HSMEAFMCABsABgmmEjdtAFwBACEAAwmgE2Y7AMYAAAAA.Xylaara:BAAALgAECgYJCwAAAA==.',
Ya='Yarine:BAAALgAECgIJAwAAAA==.',
Yo='Yoghurt:BAABLgAECn9DAAIkAAkJICGbBQD/AgAkAAkJICGbBQD/AgAAAA==.',
Za='Zabimaru:BAAALgADCgYJCgAAAA==.Zaisum:BAAALgADCgYJBgAAAA==.Zalidus:BAACLgAFFH8QAAIjAAQJXA2jCQATAQAjAAQJXA2jCQATAQAuAAQKfxgAAiMACQnKHPoFAHMCACMACQnKHPoFAHMCAAAA.Zatika:BAABLgAECn85AAMQAAkJuhlJNABAAgAQAAkJxRZJNABAAgAlAAcJ1xjcBACPAQAAAA==.',
Ze='Zehnia:BAAALgADCgYJBgAAAA==.',
Zi='Zibzab:BAABLgAECn8gAAIXAAYJ3Qh5TQDIAAAXAAYJ3Qh5TQDIAAAAAA==.',
Zm='Zmija:BAAALgAECgIJAgAAAA==.',
Zo='Zoeya:BAAALgADCgkJCQAAAA==.',
['Él']='Élsa:BAAALgADCgUJBAAAAA==.',
['ßr']='ßristle:BAAALgADCgEJAQAAAA==.',
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
