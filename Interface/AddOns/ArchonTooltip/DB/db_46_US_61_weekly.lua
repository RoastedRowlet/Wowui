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

local lookup = {'DeathKnight-Frost','Unknown-Unknown','Hunter-BeastMastery','Hunter-Survival','Warrior-Arms','Warrior-Fury','Warlock-Demonology','Druid-Balance','Shaman-Elemental','Paladin-Retribution','Warlock-Destruction','Priest-Discipline','Shaman-Enhancement','DeathKnight-Unholy','DeathKnight-Blood','Shaman-Restoration','Warrior-Protection','Monk-Windwalker','Evoker-Augmentation','Evoker-Devastation','Mage-Frost','DemonHunter-Havoc','Rogue-Subtlety','Warlock-Affliction','Priest-Shadow','Druid-Feral','DemonHunter-Devourer','Monk-Mistweaver','Priest-Holy','Druid-Guardian','Rogue-Assassination','Hunter-Marksmanship','Paladin-Holy','Druid-Restoration','Paladin-Protection','Monk-Brewmaster',}
local provider = {region='US',realm='Darrowmere',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abaddonmoon:BAABLgAECn8oAAIBAAgJvQYbFwDtAAABAAgJvQYbFwDtAAAAAA==.Absentia:BAAALgAECgEJAQABLgAECgEJAgACAAAAAA==.',
Ad='Addvar:BAAALgADCgEJAQAAAA==.Adelost:BAAALgAECgQJBQAAAA==.',
Ah='Ahalina:BAAALgAECgYJBwAAAA==.Ahnari:BAACLgAFFH8FAAIDAAMJdgJ5DwDMAAADAAMJdgJ5DwDMAAAuAAQKfxUAAwMACAlAEVg9ALkBAAMACAlAEVg9ALkBAAQABAm8AoQmAIsAAAAA.',
Ai='Ailinaa:BAACLgAFFH8iAAMFAAYJmh1MBQDLAQAFAAYJvhxMBQDLAQAGAAUJBRx6BQCbAQAuAAQKfyAAAwYACQkkH8kVAJ8CAAYACAkpH8kVAJ8CAAUABAnjF9MpAA4BAAAA.',
Ak='Akalifato:BAACLgAFFH8HAAIHAAMJyx5rVAAJAQAHAAMJyx5rVAAJAQAuAAQKfxgAAgcABwkBGxo4AO0BAAcABwkBGxo4AO0BAAEuAAUUCAkeAAgAAh0A.Akroma:BAAALgAECgIJBAAAAA==.',
Al='Alariya:BAAALgAECgUJBQAAAA==.Alerat:BAAALgAECgQJBAABLgAECgkJIgAJAGkJAA==.Alistin:BAABLgAECn8WAAIEAAgJ9BI/GgC9AQAEAAgJ9BI/GgC9AQAAAA==.Alistïn:BAAALgAECgEJAgAAAA==.Alone:BAAALgADCgQJAwAAAA==.Alstir:BAAALgAECgEJAQAAAA==.',
Am='Amaryllis:BAAALgAECgEJAQAAAA==.Ambivalent:BAAALgAECgQJBgAAAA==.',
Ar='Aradin:BAAALgAECgIJAgAAAA==.Archanfel:BAABLgAECn82AAIEAAgJYBCiHACpAQAEAAgJYBCiHACpAQAAAA==.Argasha:BAAALgADCgUJBQAAAA==.',
As='Asriel:BAAALgAECgcJDQAAAA==.',
At='Atraxa:BAAALgAECgYJDQAAAA==.',
Aw='Awsomweorc:BAAALgADCgEJAQAAAA==.',
Ay='Ayonna:BAABLgAECn8YAAIKAAYJCgZE3wDAAAAKAAYJCgZE3wDAAAAAAA==.',
Az='Azar:BAAALgADCgUJBQABLgAECgEJAQACAAAAAA==.',
Ba='Bandie:BAAALgAECgYJEQAAAA==.Barksalot:BAAALgAECgcJBwAAAA==.Barrakum:BAAALgAECgUJDgAAAA==.Bayn:BAAALgADCgQJCQAAAA==.',
Be='Beeftruck:BAACLgAFFH8KAAMGAAMJ8hSOLADeAAAGAAMJAxSOLADeAAAFAAIJtwjnLABxAAAuAAQKfy8AAwUACQlBIcAEALICAAUACQlzH8AEALICAAYABwn7HkcqAJkBAAAA.Belletrixx:BAABLgAECn8UAAMHAAYJOAyBtwDMAAAHAAYJgguBtwDMAAALAAMJhQVpNQA8AAAAAA==.Bellonä:BAAALgAECgEJAQAAAA==.Berried:BAACLgAFFH8GAAIMAAIJFhLAMgCGAAAMAAIJFhLAMgCGAAAuAAQKf0kAAgwACQlwIF0EADcDAAwACQlwIF0EADcDAAAA.',
Bi='Biigmâc:BAABLgAECn8WAAIJAAcJ6QUdSwAbAQAJAAcJ6QUdSwAbAQAAAA==.Biminem:BAABLgAECn8dAAINAAgJbxVpDQC+AQANAAgJbxVpDQC+AQAAAA==.',
Bl='Black:BAAALgAECgYJDAAAAA==.Blackwidow:BAAALgAECgMJAwAAAA==.Bloodshöt:BAABLgAECn8eAAMOAAgJdhv9MgAfAgAOAAgJdhv9MgAfAgAPAAEJXgc4XgAYAAABLgAECgkJJgAGAB8YAA==.',
Bo='Bodak:BAABLgAECn8bAAIQAAYJ5hnRNwCjAQAQAAYJ5hnRNwCjAQAAAA==.Boricua:BAAALgAECgEJAgAAAA==.',
Br='Brakun:BAAALgADCgIJAgAAAA==.Brolly:BAAALgAECgkJAgAAAA==.Broris:BAAALgAECgMJAwABLgAECgYJDAACAAAAAA==.Brucewii:BAAALgAECgQJBAAAAA==.Brunn:BAAALgAECgYJDAAAAA==.',
Ca='Calamari:BAAALgADCgQJBAAAAA==.Calistarius:BAACLgAFFH8JAAIRAAMJJBF2GQCyAAARAAMJJBF2GQCyAAAuAAQKfxwAAhEACQkCEmgTAJ8BABEACQkCEmgTAJ8BAAAA.Caliste:BAAALgADCgIJAgABLgAFFAUJEwANAOkeAA==.Calityy:BAAALgADCgYJBgABLgAFFAgJFwAEABchAA==.Camine:BAABLgAECn8yAAIOAAkJ/BwtKABNAgAOAAkJ/BwtKABNAgAAAA==.Candrabeckya:BAAALgADCgUJBQAAAA==.Carise:BAAALgAECgQJBAAAAA==.Castalasaras:BAAALgAECgYJDgAAAA==.Castorsilver:BAAALgAECgEJAQAAAA==.',
Ce='Certified:BAAALgAECgUJBQAAAA==.',
Ch='Charkoal:BAAALgAECgUJBQAAAA==.Chickeny:BAAALgADCgEJAQAAAA==.Choppstik:BAABLgAECn8VAAISAAYJpQWtUQCrAAASAAYJpQWtUQCrAAAAAA==.',
Co='Cocstrong:BAAALgADCgYJBQAAAA==.Coldslayerck:BAAALgAECgUJBQAAAA==.Constäntine:BAAALgAECggJDQAAAA==.Coriolis:BAABLgAECn86AAMTAAgJAxwYEgA4AgATAAgJAxwYEgA4AgAUAAMJggrxMACPAAAAAA==.',
Cr='Crowléy:BAAALgAECgYJEQAAAA==.',
Cu='Cuddlyowl:BAABLgAECn8XAAIVAAcJwQ4DqwCFAQAVAAcJwQ4DqwCFAQAAAA==.',
Da='Dagnamagus:BAAALgAECgYJCgAAAA==.Daire:BAAALgADCgYJBgAAAA==.Daliann:BAAALgAECgYJDAAAAA==.Damnation:BAAALgAECgYJCwAAAA==.Dangerduck:BAABLgAECn8YAAMUAAYJvxTvDwD6AAAUAAQJpxTvDwD6AAATAAYJgg9fSQDiAAAAAA==.Darktruth:BAAALgADCgMJAwAAAA==.Dartes:BAABLgAECn8WAAIDAAgJaxFmTwCbAQADAAgJaxFmTwCbAQAAAA==.Dashe:BAAALgAECgcJAQAAAA==.',
De='Deathcokie:BAAALgAECgYJDgAAAA==.Deatho:BAABLgAECn86AAMRAAgJ7ibbAQAqAwARAAgJ7ibbAQAqAwAGAAEJCSNznQBKAAAAAA==.Deathstoned:BAAALgADCgQJBQAAAA==.Deimos:BAAALgAECgEJAgAAAA==.',
Di='Diamondshard:BAAALgAECgMJCAAAAA==.Discofreezer:BAAALgAECgEJAQAAAA==.',
Dr='Draegov:BAAALgADCgYJBgAAAA==.Draeth:BAAALgADCgcJDQAAAA==.Dreadful:BAAALgAECgYJDgAAAA==.Dreylan:BAAALgADCgcJBwAAAA==.Dreyra:BAAALgADCgcJBwABLgAFFAMJBQAEAOwUAA==.Drosof:BAAALgADCgYJFQAAAA==.Drow:BAAALgAECgEJAQAAAA==.',
Du='Dukalioth:BAABLgAECn8iAAIWAAcJ0BAiIwA7AQAWAAcJ0BAiIwA7AQAAAA==.',
['Dê']='Dêcay:BAACLgAFFH8VAAQOAAYJNCBEPABZAQAOAAUJaSJEPABZAQABAAIJIBpMEgDBAAAPAAEJAAD1RgAAAAAuAAQKfzQAAw4ACQl7IhMYAOsCAA4ACAkCIhMYAOsCAAEABwnHIagEAFECAAAA.',
['Dö']='Döctorfate:BAABLgAECn8cAAIXAAgJqwubHwB+AQAXAAgJqwubHwB+AQAAAA==.',
Ed='Ediela:BAAALgAECgQJBAAAAA==.',
Ef='Effinsoldier:BAABLgAECn8eAAIKAAYJAxXfiwA+AQAKAAYJAxXfiwA+AQAAAA==.',
Eg='Egfuyun:BAAALgAECgQJBwAAAA==.',
Ek='Ekko:BAAALgADCgIJAgAAAA==.',
El='Ellyy:BAAALgAFFAEJAQAAAA==.Elvira:BAAALgAECgQJBgAAAA==.',
En='Endlessagony:BAACLgAFFH8FAAIOAAMJsxDwggDcAAAOAAMJsxDwggDcAAAuAAQKfycAAg4ACQmoHjAgAMECAA4ACQmoHjAgAMECAAAA.Endlessice:BAAALgAECgYJCgAAAA==.Ennyo:BAAALgAECgcJCgAAAA==.Enyo:BAABLgAECn8tAAQHAAcJvSB6KQAnAgAHAAcJvSB6KQAnAgAYAAEJAAA1JwBVAAALAAIJeAZ9XgBTAAAAAA==.',
Er='Erathas:BAABLgAECn8ZAAIKAAkJsRHBYQC/AQAKAAkJsRHBYQC/AQAAAA==.',
Fa='Falandril:BAABLgAECn8PAAIZAAgJZhJJGgDXAQAZAAgJZhJJGgDXAQAAAA==.Fasriel:BAAALgAECgIJAgAAAA==.',
Fe='Feata:BAAALgAECgEJAQABLgAECgYJDAACAAAAAA==.Felston:BAAALgADCgUJBQAAAA==.',
Fi='Fiyero:BAABLgAECn8uAAMGAAkJ8A6PJgCwAQAGAAkJ8A6PJgCwAQAFAAcJwgQqJQDEAAAAAA==.',
Fl='Flagcrazed:BAAALgADCgUJBQAAAA==.Fleabath:BAABLgAECn8UAAIaAAYJ6AimJAC/AAAaAAYJ6AimJAC/AAABLgAECggJIAADAKUKAA==.Fluffypyro:BAAALgADCgYJBgAAAA==.',
Fo='Forëplây:BAAALgAECgYJCgAAAA==.Foughum:BAAALgADCgUJBQABLgAECgYJDAACAAAAAA==.',
Fr='Friedcheekin:BAAALgADCgUJBQAAAA==.',
Fu='Fury:BAAALgADCgEJAQAAAA==.',
Ga='Galdames:BAAALgADCgQJBAAAAA==.',
Ge='Gedien:BAAALgAECggJEAAAAA==.Gerftrazkal:BAAALgAECgUJBQAAAA==.',
Gi='Gilforty:BAABLgAECn8YAAILAAcJ0RZUCgCAAQALAAcJ0RZUCgCAAQAAAA==.',
Gl='Glep:BAAALgAECgIJAgABLgAECgkJJgAbAEUdAA==.Gloriosa:BAABLgAECn9JAAIcAAkJlRDiJgDCAQAcAAkJlRDiJgDCAQAAAA==.',
Go='Gorl:BAAALgAECgEJAQAAAA==.',
Gr='Grootforce:BAAALgADCgMJAwAAAA==.',
Gv='Gvendalyn:BAABLgAECn8vAAIDAAkJYyXnAgBXAwADAAkJYyXnAgBXAwAAAA==.',
Gw='Gweyn:BAAALgADCgUJCAAAAA==.',
Gy='Gyatsò:BAABLgAECn8jAAISAAkJAxgzEQAlAgASAAkJAxgzEQAlAgAAAA==.',
['Gø']='Gød:BAAALgADCgUJBQAAAA==.',
Ha='Harshdh:BAAALgAECgYJBgABLgAFFAMJBgAOAFMJAA==.Harshdk:BAACLgAFFH8GAAIOAAMJUwljkQDJAAAOAAMJUwljkQDJAAAuAAQKfycAAw4ACQnjG0gYAKECAA4ACQnjG0gYAKECAA8ABAmgAdpJAE8AAAAA.',
He='Helel:BAACLgAFFH8JAAIOAAMJfxlGdgDxAAAOAAMJfxlGdgDxAAAuAAQKf0MAAw4ACQntIvoGADADAA4ACQntIvoGADADAA8ABgnlETsrAOYAAAAA.',
Ho='Hops:BAAALgAECgIJBQAAAA==.',
Il='Illibanger:BAAALgAECgcJCAABLgAFFAMJCgAGAPIUAA==.Illifiend:BAAALgAECgYJCQABLgAECgkJLgAGAPAOAA==.',
Im='Impetuous:BAAALgADCgYJDwABLgAECggJIAADAKUKAA==.',
Ip='Ipokeu:BAAALgADCgQJBAAAAA==.',
Ja='Jabmoney:BAAALgAFFAEJAgAAAA==.Jaffy:BAAALgADCgYJDgAAAA==.Jamninja:BAABLgAECn8pAAIVAAkJsxunJwBmAgAVAAkJsxunJwBmAgAAAA==.Jamxd:BAAALgAECgcJBwABLgAECgkJKQAVALMbAA==.Jardalanin:BAAALgADCgEJAQAAAA==.Jaroshe:BAAALgADCgUJBQAAAA==.',
Je='Jellyfish:BAABLgAECn8eAAMMAAkJqxL+GQDfAQAMAAkJYQ7+GQDfAQAdAAgJRgzBKQBkAQAAAA==.Jessamyn:BAAALgAECgYJCwAAAA==.',
Jh='Jhoira:BAAALgAECgYJDwAAAA==.',
Jo='Jokko:BAAALgADCgEJAgAAAA==.Jordyy:BAABLgAECn8oAAQYAAkJTiJyBgD0AQAHAAgJfSCeIQCQAgAYAAYJpiRyBgD0AQALAAIJERNKVABxAAAAAA==.',
Ka='Kaifren:BAACLgAFFH8LAAIVAAQJbxAGUwAsAQAVAAQJbxAGUwAsAQAuAAQKfx0AAhUACQmvFMFGAPABABUACQmvFMFGAPABAAAA.Kalifa:BAACLgAFFH8eAAIIAAgJAh1jAgB9AgAIAAgJAh1jAgB9AgAuAAQKfzQAAwgACAn1I7cIAAoDAAgACAn1I7cIAAoDAB4AAgmIFc1aADwAAAAA.Kalinethe:BAAALgAECgEJAgAAAA==.Karatay:BAAALgADCgQJBQAAAA==.Karrod:BAAALgAECggJEwAAAA==.Katyce:BAAALgADCgcJDQAAAA==.',
Ke='Keilani:BAAALgAECgQJBQAAAA==.',
Ki='Killeerrkap:BAAALgAECgQJBgAAAA==.Killrmiller:BAAALgADCgMJAwAAAA==.Kirajdh:BAABLgAECn8mAAIbAAkJRR2YFQCDAgAbAAkJRR2YFQCDAgAAAA==.Kittenmitten:BAAALgADCgQJBAAAAA==.Kiwaj:BAAALgAECgUJBQABLgAECgkJJgAbAEUdAA==.',
Ko='Komayetu:BAAALgAECgQJCQAAAA==.',
Kr='Kraas:BAAALgAECgEJAQAAAA==.Krateis:BAABLgAECn8oAAIfAAcJ+QS9EgDlAAAfAAcJ+QS9EgDlAAAAAA==.Kraéthlas:BAAALgADCgYJCgAAAA==.',
Kw='Kwonhee:BAAALgADCgMJAwAAAA==.',
La='Lanadelrey:BAAALgAECgYJAQAAAA==.Laurenth:BAAALgADCgkJFQAAAA==.Lazyace:BAAALgAECgYJCQAAAA==.',
Le='Lebenspender:BAABLgAECn8qAAMQAAgJ1R9iIQAtAgAQAAYJWiJiIQAtAgAJAAgJ6A4KMQBgAQAAAA==.Lextalonis:BAAALgAECgYJCAABLgAECggJEAACAAAAAA==.',
Li='Linkstery:BAABLgAECn82AAMHAAkJmRsfIgBMAgAHAAkJTxsfIgBMAgALAAMJfRWwNADkAAAAAA==.',
Lo='Losvanknight:BAABLgAECn8UAAIgAAcJkAmbFQD2AAAgAAcJkAmbFQD2AAAAAA==.',
Lt='Lt:BAAALgADCgEJAQAAAA==.',
Ly='Lyathon:BAAALgADCgMJAwAAAA==.',
Ma='Macfluffy:BAAALgAECggJDwAAAA==.Mactacolover:BAAALgAECgMJAwAAAA==.Madbomber:BAAALgAECgcJDwAAAA==.Maeze:BAABLgAECn8gAAIDAAgJpQqNYgBoAQADAAgJpQqNYgBoAQAAAA==.Magepawk:BAAALgAECgMJAwAAAA==.Magew:BAAALgADCgQJBAAAAA==.Malandru:BAACLgAFFH8JAAIhAAUJbhGoFgBTAQAhAAUJbhGoFgBTAQAuAAQKfysAAwoACQnlIqESAL8CAAoACAn0JKESAL8CACEACQlUDGQ6AJABAAAA.Mawwowow:BAABLgAECn8xAAIbAAgJOhnKKgAIAgAbAAgJOhnKKgAIAgAAAA==.Maximillius:BAAALgAECgYJBwABLgAECggJJAAOAHgbAA==.Mayjoraid:BAAALgAECgEJAgAAAA==.',
Me='Meekah:BAACLgAFFH8PAAIMAAQJ4RFNHwAdAQAMAAQJ4RFNHwAdAQAuAAQKf04AAgwACQluILQDAEwDAAwACQluILQDAEwDAAAA.Melbrosha:BAAALgAECgUJDAAAAA==.Melodine:BAAALgADCgEJAQAAAA==.Melyndia:BAAALgAECgUJBQABLgAECggJIQAiAP4fAA==.Meriks:BAAALgAECgQJDAABLgAECgUJDQACAAAAAA==.Metaliorch:BAAALgADCgcJCAAAAA==.',
Mi='Mickmonkey:BAAALgAFFAIJAgABLgAECgMJAwACAAAAAA==.Mickspooky:BAACLgAFFH8XAAMOAAUJlhW4WgAlAQAOAAQJlhW4WgAlAQAPAAEJAADjRgAAAAAuAAQKfywAAw4ACAmZH0opAJUCAA4ACAmZH0opAJUCAA8AAwkwFyMyALsAAAEuAAQKAwkDAAIAAAAA.Mickstormy:BAAALgAECgMJAwAAAA==.Mierin:BAAALgAECgQJBwAAAA==.Milfy:BAAALgADCgQJBAABLgAECgEJAQACAAAAAA==.Mintie:BAABLgAECn8zAAIeAAgJHxiHDgDaAQAeAAgJHxiHDgDaAQAAAA==.',
Mo='Moozylla:BAAALgAECggJCgAAAA==.Morrïgan:BAAALgAFFAEJAQAAAA==.Mossiah:BAAALgAECgEJAQAAAA==.',
Mu='Muriggy:BAAALgADCgIJAgAAAA==.',
My='Mylarna:BAABLgAECn8iAAIJAAkJaQmcNQBIAQAJAAkJaQmcNQBIAQAAAA==.Mynx:BAABLgAECn8WAAIgAAgJPx/WAwByAgAgAAgJPx/WAwByAgAAAA==.',
['Må']='Mårsh:BAAALgAECgEJAQAAAA==.',
['Mî']='Mîstweaver:BAAALgAECgYJBwAAAA==.',
Na='Nadira:BAAALgADCgYJBgABLgADCgkJEAACAAAAAA==.Nahkti:BAAALgADCgcJBwAAAA==.Nazarick:BAAALgAECgYJCAAAAA==.',
Ne='Neona:BAAALgAECgQJBAAAAA==.Neriv:BAABLgAECn8XAAILAAgJhw7XDQBFAQALAAgJhw7XDQBFAQAAAA==.Nexaladin:BAAALgAECgEJAQAAAA==.',
Ni='Nicor:BAAALgADCgQJBAAAAA==.Nimbus:BAAALgAECgMJBAABLgAFFAgJHgATAPIbAA==.Nixii:BAABLgAECn8zAAIIAAgJsRZJGQDpAQAIAAgJsRZJGQDpAQAAAA==.',
No='Nocticula:BAABLgAECn86AAIdAAkJXAlFKgBgAQAdAAkJXAlFKgBgAQAAAA==.',
Ny='Nyet:BAACLgAFFH8YAAMGAAUJ+hMhDgAkAQAGAAUJ+hMhDgAkAQAFAAEJYgaKNgA+AAAuAAQKfxwAAgYACQm/G1wcAGoCAAYACQm/G1wcAGoCAAAA.Nythraxia:BAAALgAECgMJAwAAAA==.Nyxiria:BAAALgADCgcJGgAAAA==.',
['Nò']='Nòir:BAAALgAECgcJCAAAAA==.',
['Nø']='Nø:BAAALgADCgMJAwAAAA==.',
Oh='Ohnarr:BAAALgAECgMJAwAAAA==.',
Ok='Oktoberfist:BAAALgAECgcJBwABLgAECggJAwACAAAAAA==.',
Or='Orine:BAABLgAECn8XAAIOAAgJbQcfkQBeAQAOAAgJbQcfkQBeAQAAAA==.Orioz:BAACLgAFFH8TAAINAAUJ6R6xBQBFAQANAAUJ6R6xBQBFAQAuAAQKfyQAAg0ACAk0IvEDAOgCAA0ACAk0IvEDAOgCAAAA.',
Os='Osiras:BAAALgAECggJEAAAAA==.',
Ot='Othela:BAAALgADCgEJAQAAAA==.',
Ow='Owun:BAAALgADCgEJAQAAAA==.',
Oz='Oz:BAAALgADCgkJCgAAAA==.',
Pa='Pandapal:BAAALgAECgEJAgAAAA==.Pathbrin:BAAALgADCgEJAQAAAA==.Pauliee:BAAALgAECgYJCgAAAA==.Pawkah:BAAALgAECgEJAgAAAA==.Paytowintaxi:BAAALgADCgEJAQAAAA==.',
Pe='Peyton:BAAALgADCggJEQAAAA==.',
Pr='Protection:BAAALgADCgUJBgAAAA==.',
Ps='Psychoman:BAAALgADCgMJAwABLgAFFAUJEwAIAMAfAA==.Psychomurda:BAABLgAECn8dAAMKAAYJpAusxADkAAAKAAYJpAusxADkAAAjAAMJ/gc1OABkAAABLgAFFAQJDwAMAOERAA==.',
Pu='Puthealshere:BAAALgAFFAEJAQAAAA==.',
['Pü']='Pü:BAAALgADCgkJEAAAAA==.',
Ra='Raign:BAAALgAECgEJAgAAAA==.Randomfelfox:BAAALgAECgUJBQAAAA==.Ratpack:BAAALgAECggJAwAAAA==.',
Re='Renfri:BAAALgADCgYJDgAAAA==.',
Ro='Robel:BAAALgAECgUJBgAAAA==.Ronaldbruce:BAAALgAECgQJBQAAAA==.Roupert:BAAALgAECgEJAwAAAA==.Rovox:BAAALgAECgkJDQABLgAECgkJJgAbAEUdAA==.',
Sa='Sadness:BAAALgAFFAEJAQAAAA==.Sao:BAAALgAECgIJAgAAAA==.Sardrian:BAABLgAECn8ZAAIDAAcJrAazjAAMAQADAAcJrAazjAAMAQAAAA==.',
Se='Seimie:BAABLgAECn8nAAILAAkJeQtUDABbAQALAAkJeQtUDABbAQAAAA==.Selithvia:BAABLgAECn8YAAIZAAgJWxHpIwCKAQAZAAgJWxHpIwCKAQAAAA==.Senethotsare:BAAALgAECgYJCgAAAA==.Sethen:BAAALgADCgEJAQAAAA==.',
Sh='Shaboudi:BAAALgAECgQJBQAAAA==.Shamalicious:BAAALgADCgEJAQAAAA==.Shammwow:BAAALgAECgMJBgAAAA==.Shaofikx:BAABLgAECn80AAIkAAkJng1MIQCMAQAkAAkJng1MIQCMAQAAAA==.Shenknarok:BAABLgAECn8vAAIaAAYJnR6cDQC5AQAaAAYJnR6cDQC5AQAAAA==.Sherryl:BAABLgAECn83AAIiAAgJlBGCNAC2AQAiAAgJlBGCNAC2AQAAAA==.Shmooples:BAAALgAECgEJAQAAAA==.Shunei:BAAALgADCgQJBAAAAA==.',
Si='Siema:BAAALgAECgMJAwAAAA==.Sigurd:BAAALgADCggJBwAAAA==.',
Sk='Skdragon:BAAALgADCgMJAQAAAA==.Skyari:BAABLgAECn8mAAMGAAgJMCSwBwDTAgAGAAgJLCSwBwDTAgAFAAEJviK7UgBlAAAAAA==.Skyarii:BAAALgAECgUJCQABLgAECggJJgAGADAkAA==.',
So='Songweaver:BAAALgAECgEJAgAAAA==.Soulminion:BAABLgAECn8fAAMOAAYJ6wKZ+ACWAAAOAAYJuAKZ+ACWAAAPAAEJ5gIQYAAVAAAAAA==.',
Sp='Spiritshard:BAAALgAECgMJAwAAAA==.Splashmountn:BAEALgAECgYJEAAAAA==.',
St='Sthane:BAAALgADCgEJAQAAAA==.Sthise:BAAALgAECgMJAwAAAA==.',
Su='Subtlety:BAABLgAECn8aAAIXAAkJ+yLfAwDzAgAXAAkJ+yLfAwDzAgAAAA==.Sulfurya:BAAALgAECgYJCgAAAA==.',
Sy='Sykoman:BAACLgAFFH8TAAMIAAUJwB8/EQBlAQAIAAUJwB8/EQBlAQAiAAEJ5QC8bQApAAAuAAQKfygAAggACAlwI30LAN8CAAgACAlwI30LAN8CAAAA.',
['Sì']='Sìleñtclãw:BAAALgAECgcJDgAAAA==.',
Ta='Talarina:BAAALgADCgYJBgAAAA==.Taylen:BAAALgADCgcJBwAAAA==.',
Te='Terumi:BAAALgAECgUJCgAAAA==.Teverion:BAAALgADCgcJCwAAAA==.',
Th='Thesios:BAAALgAECgIJAgAAAA==.Thickthighs:BAAALgAECgEJAQAAAA==.Thiizz:BAAALgAECgYJCwAAAA==.Thizz:BAABLgAECn8fAAIGAAYJPiD/KQASAgAGAAYJPiD/KQASAgABLgAFFAEJAgACAAAAAA==.',
Ti='Tic:BAABLgAFFH8FAAIHAAMJVwO3egCxAAAHAAMJVwO3egCxAAAAAA==.Tinksy:BAAALgADCgEJAQABLgAECgEJAQACAAAAAA==.Tionder:BAAALgAECgMJCwAAAA==.',
To='Toeto:BAAALgADCgYJBgAAAA==.Toetoeto:BAAALgAECgMJAwAAAA==.Toetoetoete:BAAALgADCgYJBgAAAA==.Tooe:BAAALgAECgMJAwAAAA==.Torquei:BAAALgAECgYJCAAAAA==.Toxious:BAAALgAECgQJBAAAAA==.',
Tp='Tpaman:BAAALgAECgYJBgAAAA==.Tpdruid:BAAALgAECgMJAwAAAA==.',
Ts='Tsjuda:BAAALgADCgEJAQAAAA==.Tsjudii:BAAALgADCgYJBgAAAA==.Tsjudilla:BAAALgADCgEJAQAAAA==.',
Tu='Tujefe:BAAALgAECgcJCwAAAA==.',
Ty='Tyllibust:BAAALgAECgEJAQAAAA==.',
Ug='Ugzlug:BAAALgADCgEJAQAAAA==.',
Un='Unholydk:BAABLgAFFH8FAAMKAAMJkA16XADWAAAKAAMJkA16XADWAAAhAAIJngA7PQBNAAABLgAFFAUJCAAiAEkOAA==.',
Va='Vacuus:BAABLgAECn8mAAIYAAkJSwpdCgCZAQAYAAkJSwpdCgCZAQAAAA==.Vahldire:BAAALgAECgUJEAAAAA==.Valeri:BAAALgADCggJCwAAAA==.Varkon:BAAALgAECgYJBgAAAA==.Varn:BAAALgADCggJCAAAAA==.Varthion:BAAALgAECgYJBgAAAA==.',
Ve='Velastrasza:BAAALgADCgcJBwAAAA==.Velkethria:BAAALgAECgYJEwAAAA==.Velnyxia:BAAALgAECgQJBQAAAA==.Velovañ:BAAALgADCgEJAQAAAA==.Velthyria:BAAALgADCgkJCQAAAA==.Vestara:BAAALgAECggJCAAAAA==.Veylara:BAABLgAECn8oAAIHAAcJ7gZQmAACAQAHAAcJ7gZQmAACAQAAAA==.',
Vi='Viryda:BAAALgAECgQJBAABLgAECggJLgAeAKMJAA==.',
Wa='Waeder:BAAALgADCgQJBAAAAA==.Wartimebeast:BAAALgAECgUJEAAAAA==.',
We='Welp:BAAALgAECgEJAgAAAA==.',
Wh='Wherebear:BAAALgAECgEJAQAAAA==.',
Wi='Windwalker:BAAALgAECgcJCAAAAA==.Wisteria:BAABLgAECn88AAMLAAgJYxhiCwALAgALAAgJYxhiCwALAgAYAAEJwwEzOAAaAAABLgAECgEJAgACAAAAAA==.',
Wo='Wompalot:BAAALgADCgQJBAAAAA==.Womplock:BAAALgAECgQJCQAAAA==.',
Wr='Wrâth:BAACLgAFFH8HAAIVAAMJOAX9fQDBAAAVAAMJOAX9fQDBAAAuAAQKfzQAAhUACQlwFDc9AA8CABUACQlwFDc9AA8CAAAA.',
Wy='Wydwen:BAAALgAECgEJAQAAAA==.',
Xa='Xael:BAAALgAECgIJAgAAAA==.',
Xe='Xenro:BAAALgADCgcJBgAAAA==.',
Xi='Xirus:BAAALgADCgQJAQAAAA==.',
Xu='Xulfred:BAAALgADCgIJAgAAAA==.',
Ya='Yavana:BAAALgADCgEJAQAAAA==.',
Yo='Yoshiscookie:BAAALgADCgMJAwAAAA==.',
Zi='Zigzogg:BAAALgADCgEJAQAAAA==.Zilida:BAAALgADCgEJAQAAAA==.Ziwee:BAABLgAECn8aAAIkAAgJvBqBFQBeAgAkAAgJvBqBFQBeAgABLgAECggJGgAkALwaAA==.',
Zo='Zolvyr:BAAALgADCgMJAwAAAA==.Zorana:BAAALgADCgEJAQAAAA==.',
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
