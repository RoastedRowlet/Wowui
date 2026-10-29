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

local lookup = {'DeathKnight-Unholy','DeathKnight-Blood','Mage-Frost','Hunter-BeastMastery','Paladin-Retribution','Paladin-Protection','Monk-Mistweaver','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Priest-Holy','Mage-Arcane','Druid-Restoration','Druid-Balance','Evoker-Devastation','Evoker-Preservation','Paladin-Holy','Priest-Shadow','DemonHunter-Devourer','Unknown-Unknown','DeathKnight-Frost','Hunter-Marksmanship','DemonHunter-Vengeance','Shaman-Elemental','Warrior-Arms','Warrior-Protection','Warrior-Fury','Rogue-Subtlety','Rogue-Assassination','Druid-Feral','Druid-Guardian','DemonHunter-Havoc','Monk-Windwalker','Shaman-Enhancement','Shaman-Restoration','Rogue-Outlaw','Monk-Brewmaster','Priest-Discipline','Mage-Fire','Hunter-Survival',}
local provider = {region='US',realm='Malygos',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Absofsteels:BAABNQAECn8gAAMBAAcKyRVYJABTAQABAAcKyRVYJABTAQACAAMKtQcDsABrAAAAAA==.',
Ac='Acaric:BAABNQAECn8cAAIDAAgKVAdpFwBAAQADAAgKVAdpFwBAAQAAAA==.',
Ad='Adrielon:BAAANQADCggICAAAAA==.Adøra:BAACNQAFFH8IAAIEAAMKmAjiDwDOAAAEAAMKmAjiDwDOAAA1AAQKf0wAAgQACgqUG+AlAP8CAAQACgqUG+AlAP8CAAAA.',
Ag='Agumon:BAABNQAECn8ZAAICAAcKLRxKJwBfAQACAAcKLRxKJwBfAQAAAA==.',
Al='Alchemist:BAAANQADCgUICQAAAA==.Alistair:BAAANQADCgUIBQAAAA==.Alluriel:BAAANQAECgIIBAAAAA==.Alonas:BAAANQAECgYICAAAAA==.Altharoth:BAABNQAECn8uAAMFAAkK9xr/XACBAgAFAAkK9xr/XACBAgAGAAEKzAypcQAuAAAAAA==.Altherion:BAAANQAECgIIAQAAAA==.',
Am='Amique:BAAANQABCgIIAgAAAA==.Amira:BAAANQADCgYIDwABNQAFFAYICwAHAPIXAA==.Amorfox:BAAANQADCgcIBwAAAA==.Amormage:BAAANQAECgUIEAAAAA==.Amphitrite:BAAANQADCgUIBQAAAA==.',
An='Anabolicrage:BAAANQAECgIIAgAAAA==.Anteiku:BAAANQAECgIIBAAAAA==.Anteikudeath:BAAANQADCgEIAQAAAA==.',
Ap='Applemoose:BAABNQAECn8lAAQIAAoKSR2McwAHAgAIAAgK4B6McwAHAgAJAAIKhBgNUQCMAAAKAAEK8BVmKQBGAAAAAA==.',
Ar='Aragrar:BAAANQAECgQIBQAAAA==.Arauial:BAABNQAECn8jAAILAAkKMh+sNACVAgALAAkKMh+sNACVAgAAAA==.Arcanis:BAABNQAECn8xAAMMAAoKaxSLqAAxAgAMAAoKNxSLqAAxAgADAAIKBxftLwCBAAAAAA==.Aribella:BAACNQAFFH8HAAIEAAQKSQl7DwDTAAAEAAQKSQl7DwDTAAA1AAQKfyUAAgQACgrKEfVgAFUCAAQACgrKEfVgAFUCAAAA.Arizae:BAAANQAECgQIDAAAAA==.Arizann:BAABNQAECn8dAAMNAAkKKxUtJQD6AQANAAkKKxUtJQD6AQAOAAUKzRHcYwA+AQAAAA==.Arobotev:BAABNQAECn81AAMPAAgKZxLXCAByAQAPAAgKZxLXCAByAQAQAAEK7QHcMQAgAAAAAA==.',
As='Astaren:BAAANQADCgcIEAAAAA==.Astiria:BAAANQAECgIIAQAAAA==.Asuran:BAAANQAECggIEAAAAA==.',
At='Atiya:BAACNQAFFH8GAAIRAAQKiRRJCQBXAQARAAQKiRRJCQBXAQA1AAQKfyYAAhEACgpwFq5OADACABEACgpwFq5OADACAAAA.',
Az='Azaris:BAABNQAECn8hAAMSAAoK6RMIIwAaAgASAAkK1xMIIwAaAgALAAIK3wdQ9gBBAAAAAA==.',
Ba='Babykraze:BAABNQAECn8bAAIEAAcK1w3poQDCAQAEAAcK1w3poQDCAQAAAA==.Backshotz:BAAANQADCgMIAQAAAA==.Baelrog:BAABNQAECn8ZAAMRAAcKTwevcwDnAAARAAcKTwevcwDnAAAFAAUKVgQsPAHAAAAAAA==.Baiene:BAABNQAECn8UAAQJAAkKhBKgBQA0AQAJAAgKhBKgBQA0AQAIAAQKgAZ6DAGzAAAKAAIKUAtsIQBuAAAAAA==.Baiken:BAAANQAECgEIAQAAAA==.Baldheadelf:BAAANQADCgQIBAAAAA==.Bandalar:BAABNQAECn8lAAITAAgKYxdSIwAvAgATAAgKYxdSIwAvAgAAAA==.Banerino:BAAANQADCgIIAgAAAA==.Barkathemoon:BAAANQABCggICAABNQAECgIIAQAUAAAAAA==.Barnabust:BAAANQAECgcICwAAAA==.Bashems:BAAANQAECgEJAQAAAA==.Baston:BAAANQADCgIIAgAAAA==.Bastrd:BAAANQAECgYIBwAAAA==.',
Be='Bearypie:BAAANQAECggICAAAAA==.Beastums:BAABNQAECn83AAIEAAgK5xaXXgBaAgAEAAgK5xaXXgBaAgAAAA==.',
Bi='Bigbôotyjudy:BAAANQADCgIIAgAAAA==.Bigchungus:BAAANQADCggICQAAAA==.Bingbong:BAAANQADCgEIAQAAAA==.',
Bl='Blacken:BAAANQADCgQIBgAAAA==.Bleak:BAAANQADCgQIBAAAAA==.Blindmonk:BAAANQAECggIAwAAAA==.Blite:BAAANQADCgUIDgAAAA==.Bloodmary:BAABNQAECn8fAAIFAAcKTAzvqQADAQAFAAcKTAzvqQADAQAAAA==.Bloodor:BAAANQAECgEIAQAAAA==.Bloöm:BAABNQAECn84AAINAAoKDyEzBQBvAwANAAoKDyEzBQBvAwAAAA==.',
Bm='Bmaazi:BAABNQAECn8nAAMQAAgKwxpaCgD/AQAQAAgKwxpaCgD/AQAPAAUKYgRMLADAAAAAAA==.',
Bo='Bonerina:BAAANQAECgQICQAAAA==.Boomadk:BAACNQAFFH8JAAIVAAQKwxIDCQDgAAAVAAQKwxIDCQDgAAA1AAQKf0MAAhUACgrBI2wKAEcDABUACgrBI2wKAEcDAAAA.',
Br='Bradburn:BAAANQADCgYIDAAAAA==.Bradkink:BAAANQAECgEIAQAAAA==.Brasserz:BAABNQAECn8dAAMEAAgKvxC0uwCMAQAEAAgKvxC0uwCMAQAWAAEKAABJlAAsAAAAAA==.Breezybone:BAABNQAECn8rAAIDAAoKBxocBADzAgADAAoKBxocBADzAgAAAA==.Briaela:BAAANQADCgIIAgAAAA==.Brice:BAAANQADCgYICgAAAA==.Briochebun:BAABNQAECn8cAAIFAAkKRxUYeQA6AgAFAAkKRxUYeQA6AgAAAA==.',
Bw='Bwangifer:BAABNQAECn82AAIXAAgKBxwiBQDlAQAXAAgKBxwiBQDlAQAAAA==.',
['Bë']='Bëcky:BAABNQAECn8mAAMFAAoKNSX8IQA8AwAFAAoKNSX8IQA8AwARAAYKYxL4kQBpAQAAAA==.',
Ca='Caloren:BAABNQAECn8eAAIEAAoKSiBWDQB0AwAEAAoKSiBWDQB0AwABNQAECgkJMwATADkcAA==.Camerarius:BAAANQAECgEIAQAAAA==.Cannala:BAAANQADCgUIDgAAAA==.Cargae:BAAANQADCgUIDgAAAA==.Caso:BAAANQADCgMIBAABNQAECgUICwAUAAAAAA==.',
Ce='Cellysia:BAABNQAECn8nAAMLAAkKYwRrgwDRAAALAAkKYwRrgwDRAAASAAIKFgPCdQA7AAAAAA==.Ceres:BAABNQAECn83AAIJAAgKFxZLCgBSAgAJAAgKFxZLCgBSAgAAAA==.Cesara:BAABNQAECn8+AAISAAoKcRryEQDfAgASAAoKcRryEQDfAgAAAA==.',
Ch='Chal:BAABNQAECn8kAAIFAAcKxAl+6QBJAQAFAAcKxAl+6QBJAQAAAA==.Chaplin:BAAANQAECgMIBAABNQAECggIGwAYAIgMAA==.Chbribs:BAAANQAECgYIDwAAAA==.Chestypanda:BAAANQADCgQIBAAAAA==.Chiptewth:BAAANQABCgYICQAAAA==.Chiron:BAAANQADCgEIAQAAAA==.',
Co='Coldsteel:BAAANQADCggIKAAAAA==.Columbina:BAABNQAECn8fAAITAAoKGhOjKAD/AQATAAoKGhOjKAD/AQAAAA==.Cooperhowerd:BAAANQADCgUIDAAAAA==.Corky:BAAANQADCgEIAQABNQAECgkJHQANACsVAA==.Corn:BAAANQADCgIIAgABNQAECgcIEAAUAAAAAA==.',
Cp='Cptredbeardd:BAAANQADCgYIDgAAAA==.',
Cr='Crackmonger:BAACNQAFFH8FAAIZAAIKLxXkLACWAAAZAAIKLxXkLACWAAA1AAQKfyMAAhkACQquGh9ZAIACABkACQquGh9ZAIACAAAA.Crackundead:BAABNQAECn81AAIVAAoK0hjnIQB+AgAVAAoK0hjnIQB+AgAAAA==.Crapdragon:BAAANQAECgQIBgAAAA==.',
Cy='Cyphr:BAABNQAECn83AAINAAgK4h13DgBGAgANAAgK4h13DgBGAgAAAA==.Cyrinx:BAAANQAECgcIDwAAAA==.',
Da='Daen:BAAANQADCggICAAAAA==.Dagravytrain:BAAANQAECgUJBgAAAA==.Dain:BAAANQADCgYIBgAAAA==.Dalend:BAABNQAECn8YAAMZAAoKVht6dwAwAgAZAAoK9Bp6dwAwAgAaAAIKUhs0NACVAAAAAA==.Damerot:BAABNQAECn8oAAMbAAoKjRXrBAAdAgAbAAoKjRXrBAAdAgAaAAEK2gf7MwAsAAAAAA==.Dangerous:BAAANQAECgQICwAAAA==.Danpal:BAAANQADCggICQAAAA==.Dansharo:BAAANQADCgMIAwAAAA==.Darc:BAAANQAECgQIBAAAAA==.Darnnix:BAAANQAECgUICwAAAA==.Darthrevin:BAABNQAECn8gAAMcAAkKPA5EJACmAQAcAAkKOw1EJACmAQAdAAYKMAhnYAAzAQAAAA==.Dawnsingers:BAAANQADCggIFgAAAA==.',
De='Deadbeard:BAABNQAECn9MAAQVAAoKYSX1AQBdAwAVAAoKYSX1AQBdAwACAAYKJR2xSQDRAQABAAQKASTDeAA3AQAAAA==.Deathbash:BAAANQADCgEIAQAAAA==.Deathdream:BAAANQAECgIIAgAAAA==.Deathrar:BAAANQADCgcICwAAAA==.Deathviix:BAAANQAECgUIBgAAAA==.Debased:BAABNQAECn8nAAIBAAgKGxWGHACQAQABAAgKGxWGHACQAQAAAA==.Demini:BAAANQADCgYIDQAAAA==.Demisê:BAABNQAECn9DAAICAAoKIxjSGQDHAQACAAoKIxjSGQDHAQAAAA==.Demonn:BAAANQAECgcIEgAAAA==.Derbygirl:BAAANQADCgYIDQAAAA==.Desperation:BAAANQAECggIEwAAAA==.Desso:BAAANQAECgcIDAAAAA==.Detraz:BAAANQABCgEIAQAAAA==.Devilskin:BAAANQADCgUICgAAAA==.',
Di='Dillinger:BAAANQAECgQIBQAAAA==.Dingodgaf:BAABNQAECn8tAAIFAAcKKAjX8AA7AQAFAAcKKAjX8AA7AQAAAA==.',
Dj='Djinnjuicy:BAABNQAECn8dAAIMAAcKpQivHAFcAQAMAAcKpQivHAFcAQAAAA==.',
Do='Dodo:BAAANQAECgQICgAAAA==.Dorianmyth:BAABNQAECn8aAAIGAAgKRAecOAAnAQAGAAgKRAecOAAnAQAAAA==.',
Dr='Dragonshammy:BAAANQADCgMIAwABNQAECgkJKAARAIceAA==.Drazzi:BAAANQAECgEIAQAAAA==.Dreamclaw:BAABNQAECn8gAAMeAAoK7g3bDQBPAQAeAAoKBQ3bDQBPAQAfAAQKkwpgRQCeAAAAAA==.Drippindots:BAACNQAFFH8HAAMIAAQKIBstKgC1AAAIAAMKiR8tKgC1AAAJAAEKThIuDABQAAA1AAQKfzgAAwgACgrmIXoLAHEDAAgACgrmIXoLAHEDAAkAAQoeFuUlAEAAAAAA.Driztette:BAAANQAECgYICgAAAA==.Drnewport:BAAANQADCggIEwAAAA==.Drokash:BAAANQAECgYIBgAAAA==.Drystine:BAABNQAECn8bAAIgAAcKfg9MTABuAQAgAAcKfg9MTABuAQAAAA==.',
Dy='Dyronebiggum:BAAANQADCggIDAAAAA==.',
['Dí']='Dín:BAAANQAECgYIDQAAAA==.',
Ec='Ectharienne:BAAANQABCgMIAwAAAA==.',
Ee='Eedeeweewee:BAAANQADCgUIDgAAAA==.',
Eg='Eggs:BAAANQADCgEIAQAAAA==.',
Ei='Eillaura:BAABNQAECn8+AAILAAoK0hoBKAAuAgALAAoK0hoBKAAuAgAAAA==.',
El='Electroshokk:BAAANQAECgIIAgABNQAECgQIBQAUAAAAAA==.Eleredra:BAAANQADCgYIBgABNQAECgkJJAASAJQRAA==.Elipsis:BAACNQAFFH8IAAILAAQK6BqhDgBBAQALAAQK6BqhDgBBAQA1AAQKfzUAAgsACgqiJFcHAIoDAAsACgqiJFcHAIoDAAAA.Elm:BAABNQAECn8cAAMOAAgKAhMiQQD0AQAOAAgKAhMiQQD0AQANAAIK6gxuaABjAAAAAA==.Elybella:BAAANQADCgMIAwABNQAFFAQIBwAQAJIZAA==.Elycia:BAAANQAECgYIBwABNQAFFAQIBwAQAJIZAA==.Elyenora:BAACNQAFFH8HAAIQAAQKkhmTBwAsAQAQAAQKkhmTBwAsAQA1AAQKfygAAhAACgrxFw8WAFUCABAACgrxFw8WAFUCAAAA.',
En='Enquea:BAAANQAECgYICgABNQAECgkJHQANACsVAA==.Enricco:BAAANQADCggIGgAAAA==.',
Er='Eraeste:BAAANQABCgQIAwAAAA==.Ereko:BAABNQAECn8fAAIEAAcK9w1opQC7AQAEAAcK9w1opQC7AQAAAA==.Eriss:BAABNQAECn8hAAIMAAkKohBTuQARAgAMAAkKohBTuQARAgAAAA==.Erythorbic:BAABNQAECn8dAAMJAAcKcRkbEwCBAAAIAAYK/RdtdQAPAQAJAAMKeRgbEwCBAAAAAA==.',
Es='Estralage:BAAANQADCgUICwAAAA==.',
Ev='Evictor:BAAANQADCgIJAgABNQAECggIFQAhAP4SAA==.',
Fa='Fanaticism:BAAANQAECgMIAwAAAA==.Fangs:BAAANQAECgcIBQABNQAECgkJHQAJAMUZAA==.Faranth:BAABNQAECn8WAAIEAAYK6Bs4cwBPAQAEAAYK6Bs4cwBPAQAAAA==.Fatman:BAAANQAECgIIAgAAAA==.',
Fe='Feer:BAAANQADCgQICAAAAA==.Feldron:BAAANQAECggIEQAAAA==.',
Ff='Ffugher:BAAANQAECgUICQAAAA==.Ffugme:BAABNQAECn8pAAMGAAgKNgowOAAqAQAGAAgK3wkwOAAqAQAFAAYKTgV2ywDKAAAAAA==.Ffugnutz:BAAANQADCgQIBAAAAA==.Ffugoff:BAAANQAECgYIEQAAAA==.Ffugtard:BAABNQAECn8kAAIEAAgKvQ1igwArAQAEAAgKvQ1igwArAQAAAA==.Ffugyou:BAAANQADCggICwAAAA==.',
Fi='Finnian:BAABNQAECn8oAAIRAAgKXRGLNQDJAQARAAgKXRGLNQDJAQAAAA==.Fio:BAAANQAECgYICQAAAA==.Firiona:BAAANQAECgUIDgABNQAECgkJMQAcAHseAA==.',
Fl='Flowers:BAABNQAECn8kAAITAAcKrR+FIABJAgATAAcKrR+FIABJAgAAAA==.Fläva:BAAANQADCgMIAwAAAA==.',
Fo='Foot:BAAANQADCgYICgAAAA==.Foxhound:BAABNQAECn8jAAIhAAcKMw0+JAADAQAhAAcKMw0+JAADAQAAAA==.',
Fr='Fracture:BAAANQADCggICAABNQAECgcIJQAiAJAIAA==.Fresca:BAAANQADCgEIAQAAAA==.Friendlyhoss:BAAANQADCgIIAgAAAA==.Frostypie:BAAANQADCggIEAAAAA==.',
Fu='Funkyfungi:BAAANQAECgEIAQAAAA==.Furyswarm:BAAANQAECggIBgAAAA==.',
['Fö']='Föx:BAAANQADCgYIBgAAAA==.',
Ga='Gaius:BAAANQAECgQICAAAAA==.Gawdcomplex:BAABNQAECn8bAAIRAAcKYQzHiwB5AQARAAcKYQzHiwB5AQAAAA==.',
Ge='Gernaj:BAAANQADCgcICwAAAA==.',
Gh='Ghostfrudge:BAAANQADCggICAAAAA==.Ghostfudge:BAABNQAECn8wAAQGAAkK4RpkDgC1AgAGAAgKOx9kDgC1AgAFAAIKqwFxXgEaAAARAAEKywDh3QAJAAAAAA==.',
Gi='Ginny:BAABNQAECn8UAAIGAAcK4gmhOAAnAQAGAAcK4gmhOAAnAQAAAA==.Ginsan:BAAANQADCgEIAQAAAA==.Ginthalos:BAAANQADCgcIEAAAAA==.',
Go='Golaru:BAAANQABCgIIAgAAAA==.',
Gr='Gramthyr:BAAANQADCgUIDgAAAA==.Grep:BAAANQADCgMIAwAAAA==.Greygor:BAAANQAECgYICwAAAA==.Grotok:BAAANQADCggIDgABNQAECggIIQAEAEkUAA==.',
Gu='Gumer:BAABNQAECn8eAAMjAAkKmwzvmwBAAQAjAAkKmwzvmwBAAQAYAAUK0QIj7wC4AAAAAA==.Gurgatron:BAABNQAECn8VAAMdAAkKAg+IDQCnAQAdAAkKAg+IDQCnAQAkAAIK4QX4GABVAAABNQAECgoKNQAaAKslAA==.Guulen:BAAANQADCgIIAgAAAA==.',
['Gá']='Gárd:BAAANQAECgUIBQAAAA==.',
Ha='Halygos:BAAANQAECgQIBgAAAA==.Hariffug:BAAANQADCgcIBwAAAA==.Hasklaufien:BAAANQAECgcIEgAAAA==.',
He='Healinside:BAAANQAECgQIBQABNQAECgkJKAARAIceAA==.Hellvina:BAAANQADCggICAAAAA==.Hermie:BAAANQABCggICAAAAA==.',
Hi='Hinderberg:BAAANQAECgEIAQAAAA==.',
Ho='Holdor:BAABNQAECn8XAAMBAAYKqw0vMQACAQABAAYKqw0vMQACAQACAAQKdQM6aABjAAAAAA==.Horde:BAAANQADCgIIAgAAAA==.',
Hu='Huntsum:BAABNQAECn8hAAMEAAgKSRRJfAAVAgAEAAcKYBZJfAAVAgAWAAYKhgyzKwCxAAAAAA==.',
Ia='Iahsotgievhu:BAAANQADCgcICAAAAA==.Iamspeed:BAAANQABCgEIAQAAAA==.',
Ic='Iceblocklulz:BAAANQADCgMIAwAAAA==.Icedsoul:BAABNQAECn8UAAMDAAYKqwrMHwDrAAADAAUKqwrMHwDrAAAMAAMKrAGargFkAAAAAA==.Iceflame:BAAANQADCgYIBgABNQAECgcIIwANAMsbAA==.',
Ig='Iggey:BAABNQAECn8hAAIZAAoKgxHOlwDhAQAZAAoKgxHOlwDhAQAAAA==.',
Ik='Ikkaku:BAAANQADCggIDQAAAA==.',
Il='Ilandras:BAABNQAECn8eAAITAAgKUhc9JAAlAgATAAgKUhc9JAAlAgAAAA==.Illadus:BAABNQAECn8XAAITAAcK7gwxPwBRAQATAAcK7gwxPwBRAQAAAA==.Illiviix:BAAANQADCgcIHgAAAA==.',
In='Indra:BAABNQAECn8rAAIFAAkKqh1mSwCzAgAFAAkKqh1mSwCzAgAAAA==.Intoxicated:BAAANQAECgMICAAAAA==.',
Ir='Iranna:BAACNQAFFH8VAAMdAAUKWyMFAgApAQAdAAQKriQFAgApAQAcAAIKyyH3EABsAAA1AAQKfycAAx0ACgosJR4NABwDAB0ACgq3JB4NABwDABwABwpBJX4hABMCAAAA.',
It='Itsredbelow:BAAANQAECgIIBAAAAA==.',
Iz='Izlaz:BAAANQADCggICAAAAA==.',
Ja='Jacrispy:BAAANQAECgIJAwAAAA==.Jaggedace:BAABNQAECn8rAAQVAAoK4QYdMABlAQAVAAoKKQYdMABlAQACAAYKvgR3igDWAAABAAIKAgrrbQA0AAAAAA==.Janaki:BAABNQAECn9GAAMNAAoKvBtQBgAFAwANAAoKvBtQBgAFAwAOAAYKiQhccAAJAQAAAA==.',
Je='Jellyfish:BAABNQAECn8YAAIFAAcK7hKRmgAeAQAFAAcK7hKRmgAeAQAAAA==.',
Ji='Jibbtotem:BAAANQADCgYIDQABNQAECgkJHQASAE8WAA==.Jivanos:BAAANQADCgUIBQAAAA==.',
Jo='Joexotick:BAAANQABCgMIBgAAAA==.Jonnyquestt:BAABNQAECn8nAAIFAAgKXA3qtQCyAQAFAAgKXA3qtQCyAQAAAA==.',
Ju='Junlock:BAAANQAECgYICgABNQAFFAcIFgATAIsXAA==.Junrush:BAACNQAFFH8WAAITAAcKixdDAQCiAQATAAcKixdDAQCiAQA1AAQKfycAAxMACgp/HiIWALICABMACgp/HiIWALICABcAAQoAAMcvAD8AAAAA.Junshot:BAAANQAECgEIAQABNQAFFAcIFgATAIsXAA==.',
Ka='Kalea:BAAANQABCgIIBAAAAA==.Kalietha:BAABNQAECn8UAAMJAAcKFQgcSACnAAAIAAcKKAWX0QAmAQAJAAMK3gwcSACnAAAAAA==.Karaizula:BAABNQAECn8nAAMjAAgKJBBySAB0AQAjAAgKJBBySAB0AQAYAAQKTwFGBgGBAAAAAA==.Kasdeya:BAAANQADCgYIBgAAAA==.Kassandrah:BAAANQADCgUIBQAAAA==.Katsuko:BAABNQAECn8qAAICAAkKUhWxIQCFAQACAAkKUhWxIQCFAQAAAA==.Kattnirra:BAABNQAECn8cAAIEAAgKlQodqgCxAQAEAAgKlQodqgCxAQAAAA==.Katze:BAABNQAECn8mAAIEAAkKRhEzZABNAgAEAAkKRhEzZABNAgAAAA==.Kaylé:BAAANQAECgMIAwAAAA==.',
Ke='Keepper:BAAANQAECgMIBwAAAA==.Kenj:BAABNQAECn8wAAILAAoKdCPuBgCOAwALAAoKdCPuBgCOAwABNQAFFAYIDAANAAcZAA==.Kenjurr:BAABNQAECn8fAAMQAAkKTB/HBgA6AwAQAAkKTB/HBgA6AwAPAAIKOAtdNQBiAAABNQAFFAYIDAANAAcZAA==.Kenslynn:BAABNQAECn8kAAILAAkKkBykKQDCAgALAAkKkBykKQDCAgAAAA==.Ketheric:BAAANQADCgEIAQABNQAECgkJHQAJAMUZAA==.',
Ki='Kiannor:BAABNQAECn8oAAIhAAgKxwYtIgAUAQAhAAgKxwYtIgAUAQAAAA==.Killahaseo:BAABNQAECn8iAAIFAAoKyx/0SQC3AgAFAAoKyx/0SQC3AgAAAA==.Killmoedee:BAABNQAECn8wAAMGAAkKTh85EACaAgAGAAkKTh85EACaAgAFAAMKCQVcIgFTAAAAAA==.Kishibe:BAAANQAECgUIDQAAAA==.Kiss:BAAANQAECggIEwABNQAFFAgILgAjAGokAA==.Kitwryn:BAAANQADCgUIDgAAAA==.',
Kl='Klexios:BAAANQAECgQIDAAAAA==.',
Ko='Koopa:BAAANQAECgcIEAAAAA==.',
Kr='Kraulhoof:BAAANQAECgEIAQABNQAECgQIBQAUAAAAAA==.Kronohs:BAAANQAECgIIAwAAAA==.Krymson:BAAANQADCgcIBwAAAA==.',
Ku='Kui:BAABNQAECn8yAAIlAAgKdxpLBQDNAQAlAAgKdxpLBQDNAQAAAA==.Kuneia:BAAANQADCgQIBAABNQAECgoKRgANALwbAA==.Kurakka:BAAANQADCgEIAQAAAA==.Kuyna:BAAANQADCgYIDgAAAA==.',
Ky='Kylohendrix:BAAANQAECgQIBAAAAA==.',
['Kö']='Köz:BAAANQADCgQIBAAAAA==.',
La='Laetri:BAAANQAECgQIBAAAAA==.Lailiia:BAABNQAECn8hAAIHAAcKFBKYEgBOAQAHAAcKFBKYEgBOAQAAAA==.Laindrin:BAAANQADCgcIDQAAAA==.Lavendarlace:BAAANQADCgYIDAAAAA==.Lawrence:BAAANQADCggICAAAAA==.Lazloo:BAABNQAECn8wAAIZAAkKHSFqJgAfAwAZAAkKHSFqJgAfAwAAAA==.Lazymidget:BAABNQAECn8YAAIWAAkKYgduOQCFAQAWAAkKYgduOQCFAQAAAA==.Lazytok:BAAANQAECgMIAwAAAA==.',
Le='Leftÿ:BAABNQAECn9CAAIVAAoKsB0fEgD8AgAVAAoKsB0fEgD8AgAAAA==.Legindkiller:BAAANQADCgUIDgAAAA==.Lenie:BAABNQAECn8bAAQLAAkKLSHtCwAkAwALAAgK5iLtCwAkAwASAAIKigrmQwA9AAAmAAEKVwnvMgAbAAABNQAFFAYIEwACAGghAA==.Levoyon:BAABNQAECn8XAAIiAAgKVwVOFgAmAQAiAAgKVwVOFgAmAQAAAA==.Lexibelle:BAABNQAECn8uAAIIAAgKGQzXZwAwAQAIAAgKGQzXZwAwAQAAAA==.Lexsing:BAAANQABCgEIAgAAAA==.',
Lf='Lfty:BAAANQADCggIDAABNQAECgoKQgAVALAdAA==.',
Li='Lightace:BAABNQAECn8rAAMGAAkKzwsKPQAMAQAGAAYK9g4KPQAMAQAFAAkKZweRtgDsAAAAAA==.Lightbunny:BAAANQAECggIEQAAAA==.Lightlicious:BAAANQADCgQIBAAAAA==.Lincia:BAAANQAECgQIBgAAAA==.Linkkil:BAAANQAECgUICAAAAA==.Liv:BAAANQADCgMIAwABNQAECgkJGAALAFAXAA==.',
Lo='Loastotem:BAAANQADCgIIAgAAAA==.Lobos:BAABNQAECn8tAAIIAAkKhA5OdQACAgAIAAkKhA5OdQACAgAAAA==.Lockrah:BAAANQADCgUIDAAAAA==.Lorvinion:BAAANQAECgIIAgAAAA==.Lostdraco:BAAANQAECgYIDgAAAA==.Lostdream:BAABNQAECn8zAAMgAAoKjwkJLAA+AQAgAAoKjwkJLAA+AQAXAAgKPAWCHgDaAAAAAA==.Loun:BAABNQAECn8UAAIlAAcKuhv4CwBHAgAlAAcKuhv4CwBHAgAAAA==.',
Lu='Luiss:BAABNQAECn8cAAIFAAYKDAcg3ACxAAAFAAYKDAcg3ACxAAAAAA==.Luminism:BAABNQAECn8aAAMRAAkKVhjSPgBpAgARAAkKVhjSPgBpAgAFAAEKAACCjgFGAAABNQAECgYICgAUAAAAAA==.Luvlycruelty:BAAANQAECgYIDQAAAA==.',
Ly='Lycos:BAAANQABCgQIBAAAAA==.Lyn:BAEBNQAECn8vAAIlAAoKTSZmAADvAwAlAAoKTSZmAADvAwAAAA==.',
['Lê']='Lêônà:BAAANQABCggICAAAAA==.',
Ma='Maazi:BAAANQADCgYIBgAAAA==.Mackenziiee:BAABNQAECn83AAIEAAoKAhgROwC5AgAEAAoKAhgROwC5AgAAAA==.Madglowup:BAABNQAECn8cAAIkAAkK3xuABQCTAgAkAAkK3xuABQCTAgAAAA==.Magerick:BAAANQAECgYIDgAAAA==.Magicwater:BAAANQADCggICwABNQAECgoKLgAFANEjAA==.Magtaki:BAAANQADCgEJAQAAAA==.Mainline:BAAANQAECgQICgAAAA==.Maizepriest:BAABNQAECn8lAAISAAkKDR5RCwA0AgASAAkKDR5RCwA0AgAAAA==.Maliaa:BAAANQAECgIIAQAAAA==.Malloryrose:BAAANQADCgcIBwAAAA==.Mandrison:BAAANQAECggIEgAAAA==.Masfima:BAAANQADCgIIAgAAAA==.Maxz:BAAANQADCggIHAAAAA==.',
Mc='Mcstàbby:BAAANQABCgMIAwAAAA==.',
Me='Meerkat:BAAANQAECgYIBAAAAA==.Mellowblink:BAABNQAECn8YAAIMAAYKmBWJAAGNAQAMAAYKmBWJAAGNAQABNQAECgkJMQAcAHseAA==.Mellowlink:BAABNQAECn8xAAMcAAkKex76DQCXAgAcAAkKex76DQCXAgAdAAEKURIgVwA6AAAAAA==.',
Mi='Migglet:BAAANQAECgMIAwAAAA==.Miirya:BAAANQADCgYIAwAAAA==.Milkybar:BAAANQAECggICAAAAA==.Mimi:BAACNQAFFH8qAAMEAAoKpSRPAgBYAgAEAAYK9CVPAgBYAgAWAAkKBCN0AQAQAgA1AAQKfzEAAxYACgptJoEGAGgDABYACgoNJoEGAGgDAAQACApFJj8mAP4CAAAA.Miramage:BAAANQADCgcIBwABNQAECgoKIQAEAOgaAA==.Miravus:BAAANQAECgYIDwABNQAECgoKIQAEAOgaAA==.Mirlanda:BAAANQAECgIIAgAAAA==.Misttie:BAABNQAECn8gAAIlAAoKwxyQAgCIAgAlAAoKwxyQAgCIAgABNQAFFAQICAALAOgaAA==.Mitcheoff:BAAANQAECgUICwAAAA==.',
Mo='Moisturizer:BAAANQAECgUICwAAAA==.Moltenkam:BAAANQADCgEIAQAAAA==.Monkerick:BAAANQADCgQIBwAAAA==.Mowte:BAAANQADCgUIDgAAAA==.',
Mu='Murkoobi:BAAANQAECgEIAQAAAA==.',
My='Mystrial:BAAANQABCgYICwAAAA==.Mystáke:BAAANQAECgcIDgAAAA==.',
['Mó']='Mómo:BAAANQADCgMIAwAAAA==.Móus:BAAANQADCgIIAgABNQAECgkJIAAjAIoTAA==.',
Na='Narbus:BAABNQAECn8UAAIOAAUKBQ4acAAKAQAOAAUKBQ4acAAKAQAAAA==.Narcissus:BAAANQADCgUIDgAAAA==.Naromancer:BAABNQAECn82AAIMAAgKWiGrPAABAgAMAAgKWiGrPAABAgAAAA==.Nathadon:BAABNQAECn9EAAISAAoKJCBICQBKAwASAAoKJCBICQBKAwAAAA==.Nautrium:BAAANQAECgQIBwAAAA==.',
Ne='Necrotis:BAAANQADCgUIDgAAAA==.Nekhraros:BAABNQAECn8dAAMJAAkKxRmPMAAGAQAIAAYKHhYwogCRAQAJAAMKox6PMAAGAQAAAA==.Neko:BAAANQAECggIEAAAAA==.Nergál:BAAANQADCgYIBQABNQADCggICAAUAAAAAA==.Nevelia:BAAANQAECgcIBwABNQAECgcIIQAHABQSAA==.Neytfury:BAAANQADCgUIBQAAAA==.Neyti:BAAANQADCgIIAgAAAA==.Neytvengy:BAAANQAECgMIAwAAAA==.Nezukô:BAAANQADCgUICQAAAA==.',
Ni='Nienna:BAAANQAECgMIBAABNQAECgkJHQANACsVAA==.Nightwulf:BAAANQADCgIIAgAAAA==.Nikkikynz:BAAANQABCgIIAgAAAA==.Nikkisan:BAAANQADCgYIGAAAAA==.Nixk:BAAANQAECgUIDQAAAA==.',
No='Noapte:BAAANQADCgYICQAAAA==.Noixi:BAABNQAECn8bAAMDAAcKxgieHACLAAAMAAcKEgVPPQEnAQADAAQKfQqeHACLAAAAAA==.Noras:BAABNQAECn8VAAIhAAgK/hLyJgDqAQAhAAgK/hLyJgDqAQAAAA==.Nordicslayer:BAAANQAECgEIAQAAAA==.Notagnoblin:BAECNQAFFH8aAAICAAYKNSKaAwCQAQACAAYKNSKaAwCQAQA1AAQKfzUAAgIACgpwJroBAF4DAAIACgpwJroBAF4DAAAA.Notrick:BAAANQAECgQIBwAAAA==.',
Nu='Nuffsaid:BAAANQADCgUIBgAAAA==.',
Ny='Nyko:BAAANQADCgUIBgAAAA==.',
Oa='Oaklyn:BAAANQADCgUIBQAAAA==.',
Ob='Obolisq:BAAANQADCgIIAgAAAA==.Obsidious:BAAANQAECgYICQAAAA==.',
Og='Ogrelurd:BAABNQAECn9NAAMZAAoK+B34FAC+AgAZAAoK+B34FAC+AgAbAAEKAACwKgAAAAAAAA==.',
Op='Opalfox:BAAANQADCgEIAQAAAA==.Ophelia:BAABNQAECn82AAQKAAoKTB5dCwC2AQAKAAUKHR5dCwC2AQAIAAgKER25SwCBAQAJAAIK6xKWVACBAAAAAA==.',
Or='Orakwa:BAABNQAECn8VAAMZAAkKoBGqjwD1AQAZAAkKoBGqjwD1AQAbAAQKshEfGwD1AAAAAA==.',
Os='Osteroth:BAAANQADCggIDwAAAA==.',
Pa='Pachez:BAAANQAECgIIAgAAAA==.Paladont:BAAANQAECgUICwAAAA==.Pallinda:BAABNQAECn8oAAMRAAkKhx7NHwBHAgARAAkKhx7NHwBHAgAFAAYKoQ4s6wBFAQAAAA==.Palmogant:BAAANQAECgYIEQAAAA==.Panztide:BAAANQADCgcIBwABNQAECgkJIgAeABMNAA==.Pappyoblues:BAAANQAECgEIAgAAAA==.Patt:BAAANQADCgUIBQAAAA==.',
Pe='Pendulumlaw:BAACNQAFFH8PAAIZAAYKzAYgGgBGAQAZAAYKzAYgGgBGAQA1AAQKfywAAhkACgr0GD1nAFoCABkACgr0GD1nAFoCAAAA.Pennypacker:BAAANQAECgUICQABNQAECgkJHQANACsVAA==.Pepe:BAAANQADCgEIAQAAAA==.',
Ph='Phinn:BAABNQAECn8qAAIOAAcKkwmxOADlAAAOAAcKkwmxOADlAAAAAA==.Phoel:BAAANQADCgUIDAAAAA==.Phoopanchu:BAAANQAECgcIEgAAAA==.',
Pi='Pimikoh:BAAANQAECgQIBAAAAA==.Pinkbuns:BAABNQAECn8VAAIDAAcKoB2kCQA4AgADAAcKoB2kCQA4AgAAAA==.',
Pn='Pneuma:BAABNQAECn8WAAIXAAcK5htGCABzAQAXAAcK5htGCABzAQAAAA==.',
Po='Pollonius:BAAANQADCgQIBAAAAA==.Poncho:BAAANQADCgIIAgAAAA==.Popsy:BAAANQAECgUIBQAAAA==.',
Pr='Praxel:BAAANQAECgMIAwABNQAECgQICAAUAAAAAA==.Prenton:BAABNQAECn8rAAIZAAcKxxzTbgBGAgAZAAcKxxzTbgBGAgAAAA==.Prepotente:BAAANQAECgMIBAABNQAECgkJMQAcAHseAA==.Prideflag:BAAANQADCggICAAAAA==.Priestin:BAAANQAECgEIAQAAAA==.Profundity:BAAANQAECgEIAQABNQAECgkJHQANACsVAA==.',
Ps='Psyduck:BAABNQAFFH8FAAIZAAUKfAszFwBpAQAZAAUKfAszFwBpAQABNQAFFAoKKgAFANAgAA==.',
Pu='Punie:BAABNQAECn8mAAIYAAgKfRZQVgAhAgAYAAgKfRZQVgAhAgAAAA==.Punkte:BAAANQADCgQIBAAAAA==.Puzzykat:BAAANQADCgYIBgAAAA==.',
['Pä']='Päg:BAAANQADCgEIAQABNQAECgoKQgAVALAdAA==.',
Qe='Qeini:BAABNQAECn8lAAImAAcKbgwvDgBMAQAmAAcKbgwvDgBMAQAAAA==.',
Ra='Radrin:BAAANQADCgcIEAAAAA==.Rafoff:BAAANQAECgYICQAAAA==.Ragnarax:BAABNQAECn8gAAIZAAoKAh+lFgCyAgAZAAoKAh+lFgCyAgAAAA==.Rahll:BAAANQADCgIIAgAAAA==.Raikami:BAAANQAECgIIAgAAAA==.Rancoramble:BAAANQAECgUICwAAAA==.Randis:BAABNQAECn8rAAIBAAcK3g1yLgATAQABAAcK3g1yLgATAQAAAA==.Raysonna:BAAANQAECgYIEgAAAA==.',
Re='Rengår:BAAANQAECgUIBAAAAA==.Reticent:BAAANQAECgQIBgAAAA==.Reversewally:BAAANQAECgcIEAAAAA==.Rexhà:BAAANQAECgMIBQAAAA==.Rexiis:BAABNQAECn8aAAIIAAgKWg7efQD7AAAIAAgKWg7efQD7AAAAAA==.Reyth:BAAANQAECgQICwAAAA==.',
Rh='Rhuby:BAABNQAECn8oAAICAAcKHhdsTwC3AQACAAcKHhdsTwC3AQAAAA==.',
Ri='Rimos:BAAANQAECgUICgAAAA==.Riptîde:BAAANQAECgMIAwAAAA==.Rivening:BAAANQAECgQICAAAAA==.',
Rk='Rk:BAAANQADCgYICAAAAA==.',
Ro='Roeyth:BAAANQADCggICAAAAA==.Rokki:BAABNQAECn84AAIMAAkK+wjd7ACxAQAMAAkK+wjd7ACxAQAAAA==.Roostor:BAAANQADCggIEQAAAA==.Rosael:BAAANQADCgQJBAAAAA==.Roundhouse:BAABNQAECn8dAAIlAAcKMhzlDQAZAgAlAAcKMhzlDQAZAgAAAA==.',
Ru='Rubbmytotems:BAAANQAECgUIDgAAAA==.Rubicôn:BAAANQABCgYICAABNQAFFAcIHAAMAK0ZAA==.Rubmyoysters:BAAANQADCgEIAQAAAA==.Ruleti:BAABNQAECn8pAAIEAAoKsRg1PwCtAgAEAAoKsRg1PwCtAgAAAA==.Rumí:BAAANQADCggJIgAAAA==.Rundeep:BAAANQABCgYICgAAAA==.Russell:BAAANQADCgUIDgAAAA==.',
Sa='Sabado:BAAANQAECgMIAwAAAA==.Safewerd:BAEANQAECgYIEAAAAA==.Saitama:BAAANQAECgYICQABNQAECgkJMgAZACoWAA==.Sangriel:BAABNQAECn8jAAICAAkK7Q6rZwBUAQACAAkK7Q6rZwBUAQAAAA==.Saraceleste:BAAANQAECgQIBAAAAA==.Sarafinmae:BAAANQAECgIIAgAAAA==.Sarahfi:BAAANQAECgIJAgABNQAECgYIDwAUAAAAAA==.Saralanna:BAABNQAECn8vAAIIAAoKTw0rWwBSAQAIAAoKTw0rWwBSAQAAAA==.Sarasophie:BAAANQADCgcIGAAAAA==.Sarefina:BAAANQAECgQICQAAAA==.Sathenazarke:BAABNQAECn8VAAIPAAkK0B6zCADsAgAPAAkK0B6zCADsAgABNQAFFAUIFQAdAFsjAA==.',
Sc='Schism:BAAANQAECgMIBAAAAA==.Schmingus:BAAANQADCgIIAgAAAA==.Scoban:BAACNQAFFH8QAAIRAAYKuBmwBQCxAQARAAYKuBmwBQCxAQA1AAQKfxkAAhEACQraG3g2AIoCABEACQraG3g2AIoCAAAA.',
Se='Seaworld:BAABNQAECn8WAAQeAAcK8RXxFADlAAAeAAQKahnxFADlAAAOAAcKMRAsOQDjAAAfAAEKJhVfTgA5AAABNQAECgkJMQAcAHseAA==.Seraphine:BAAANQABCgIIAgAAAA==.Seraphnite:BAAANQADCgIIAgAAAA==.Seriousjakk:BAAANQADCgEIAQABNQADCgQIBwAUAAAAAA==.',
Sh='Shadeebear:BAAANQADCgEIAQAAAA==.Shadowtax:BAAANQADCgYIBgAAAA==.Shan:BAAANQAECgcIEwAAAA==.Shaohlin:BAAANQAECgEIAQAAAA==.Shaqfu:BAAANQADCgUIDgAAAA==.Shavemybush:BAAANQADCgcJBwAAAA==.Shayy:BAABNQAECn85AAImAAoKvRjnAwCeAgAmAAoKvRjnAwCeAgAAAA==.Sheve:BAAANQAECgQICAABNQAECgkJKgAjADAiAA==.Shigure:BAABNQAECn8jAAMDAAoKpwqHFgBKAQAMAAoKrAgW0wDgAQADAAcKOQqHFgBKAQAAAA==.Sholin:BAABNQAECn8ZAAIlAAkKWSCgCACfAgAlAAkKWSCgCACfAgAAAA==.Shomea:BAAANQAECgQICgAAAA==.Shugz:BAAANQADCgUIDQAAAA==.Shumai:BAAANQAECgYIDQAAAA==.',
Si='Sigons:BAAANQABCgYICQAAAA==.Sikotick:BAABNQAECn8cAAINAAgKqBZRLQCxAQANAAgKqBZRLQCxAQAAAA==.Sikxrapture:BAAANQADCgYIBgAAAA==.Siliconista:BAACNQAFFH8JAAIMAAQKORdEFwDrAAAMAAQKORdEFwDrAAA1AAQKf0UAAwwACgrbJEgVAH4DAAwACgooJEgVAH4DAAMABwrgJKkLAAUCAAAA.Simbelmyne:BAAANQAECgUIBgABNQAECgkJHQANACsVAA==.',
Sk='Skitrit:BAAANQAECgEIAQABNQAECgoKKQAEALEYAA==.Skyjin:BAAANQADCgYJCQAAAA==.',
Sl='Slammurai:BAAANQADCgcICwAAAA==.Slippie:BAAANQADCgQIBAAAAA==.Slippinwater:BAABNQAECn8uAAIFAAoK0SOsHQBMAwAFAAoK0SOsHQBMAwAAAA==.Sllew:BAABNQAECn9DAAMBAAoKhhtOGQD1AgABAAkKax1OGQD1AgAVAAoK2xAJGgD+AQAAAA==.Slyyce:BAAANQAECgcIDwAAAA==.',
Sm='Smoulder:BAAANQAECgIIAgAAAA==.',
Sn='Snigles:BAABNQAECn8dAAIcAAkKNAhTKgBxAQAcAAkKNAhTKgBxAQAAAA==.Snowlily:BAAANQAECgQIBgABNQAECgkJJAASAJQRAA==.Snurp:BAAANQAECgYIDAABNQAECgoKIwAWAIYgAA==.',
So='Softnsquishy:BAAANQAECgEIAgAAAA==.Solmarrow:BAABNQAECn8YAAQDAAcKmggwGAA4AQADAAcKRggwGAA4AQAMAAQKaAQchAG8AAAnAAEKFAbKDQA0AAAAAA==.',
Sp='Spagoni:BAAANQADCggICAAAAA==.Spanksbar:BAAANQADCggIFAAAAA==.Spartos:BAABNQAECn8pAAMZAAcKPBvuUACQAQAZAAcKPBvuUACQAQAaAAIKUA87JQBpAAAAAA==.Spazzlixx:BAAANQADCgMIAwAAAA==.Speedy:BAABNQAECn8dAAIEAAYKvwOG0ACRAAAEAAYKvwOG0ACRAAAAAA==.Speedyspeed:BAAANQADCgQIBQAAAA==.Spokes:BAAANQADCgYICQABNQAECggIAwAUAAAAAA==.Sposi:BAABNQAECn8dAAMCAAgKZCErGwDVAgACAAgKZCErGwDVAgAVAAIKzwwacABwAAAAAA==.Sprinkle:BAAANQAECggJCQABNQAECggIEQAUAAAAAA==.',
Sr='Srimrithyu:BAAANQADCgYIEwAAAA==.',
Ss='Sselionn:BAAANQAECgUIDgAAAA==.',
St='Stomps:BAABNQAECn8iAAIaAAgKyBccEAAnAgAaAAgKyBccEAAnAgAAAA==.Stonezef:BAABNQAECn8fAAIMAAkK8Qvf+ACbAQAMAAkK8Qvf+ACbAQAAAA==.',
Su='Suffocation:BAAANQADCgYIBwAAAA==.Sumasuka:BAAANQADCgcIBwAAAA==.Sumbtch:BAABNQAECn8ZAAIIAAcK8AKZswCKAAAIAAcK8AKZswCKAAAAAA==.Sungdihhwoo:BAAANQADCgQIBwAAAA==.Susann:BAABNQAECn8gAAIjAAkKihNyaQDQAQAjAAkKihNyaQDQAQAAAA==.',
Sy='Syravia:BAAANQAECgUIEQAAAA==.',
['Sò']='Sòlushan:BAAANQAECgEIAQABNQAECgoKJgAFAKEbAA==.',
Ta='Tahoa:BAAANQABCgQIBwAAAA==.Talarin:BAAANQAECgIIAgAAAA==.Talayro:BAAANQADCgIIAgAAAA==.Tameka:BAABNQAECn80AAIEAAoKuBnFNQDKAgAEAAoKuBnFNQDKAgAAAA==.Tardis:BAAANQAECgcIBwABNQAECgoKJgALAOcXAA==.Tatersdh:BAEANQAECgYIDAABNQAFFAYIGgACADUiAA==.Tavinrayn:BAAANQAECgYIDAAAAA==.',
Te='Tekesh:BAAANQAECgYIDQAAAA==.Teksham:BAAANQADCgYIEgAAAA==.Telarin:BAABNQAECn8qAAMEAAgKDBUBVAChAQAoAAcKdxPABwDtAQAEAAgKWxQBVAChAQAAAA==.Teremup:BAAANQAECgIIAQAAAA==.Tezrian:BAAANQADCgYJCgABNQAECgkJMQAcAHseAA==.',
Th='Thebigdawg:BAAANQADCggICQAAAA==.Theladyboy:BAABNQAECn8nAAMXAAgKqBZ+CABsAQAXAAgKqBZ+CABsAQAgAAMKtgrieQCRAAAAAA==.Thomss:BAABNQAECn8nAAIEAAgKrRO5awA7AgAEAAgKrRO5awA7AgAAAA==.Thraiene:BAAANQAECgUIDwABNQAECgkJFAAJAIQSAA==.Throhk:BAAANQADCgcIFQAAAA==.Thrumgar:BAAANQAECgEIAgAAAA==.',
Ti='Tiamut:BAAANQADCgQIBAAAAA==.Tigerliley:BAAANQAECgQICAABNQAECgkJJAASAJQRAA==.Tinneas:BAAANQAECgEIAQAAAA==.',
To='Tomás:BAABNQAECn8bAAIYAAgKiAxVjACFAQAYAAgKiAxVjACFAQAAAA==.Topg:BAAANQADCggIEwAAAA==.Torstai:BAABNQAECn8ZAAIKAAcKkwoYCQATAQAKAAcKkwoYCQATAQAAAA==.Totemic:BAAANQADCggIEgAAAA==.Toyun:BAAANQADCgMIAwAAAA==.',
Tr='Trap:BAAANQADCgQIBAAAAA==.Trueshöt:BAABNQAECn8hAAMWAAcKahf0MADGAQAWAAcKUhP0MADGAQAoAAYK7xCZCQCXAQAAAA==.',
Ts='Tserendolgor:BAAANQAECgYIDAABNQAECgkJMQAcAHseAA==.',
Tu='Tukker:BAAANQADCgYIBgABNQAECgoKNQAaAKslAA==.',
Ty='Tyedindis:BAAANQADCgEIAQAAAA==.Tyresious:BAABNQAECn8WAAIFAAgK+xdslwD1AQAFAAgK+xdslwD1AQAAAA==.',
Ut='Utherrex:BAAANQAECgIIAgABNQAECggIGgAIAFoOAA==.',
Va='Vahaghn:BAABNQAECn85AAIZAAoK3yIAEwBwAwAZAAoK3yIAEwBwAwAAAA==.Valcerus:BAAANQAECgQIDAAAAA==.Valedus:BAABNQAECn8tAAIFAAoK1SFJOQDrAgAFAAoK1SFJOQDrAgAAAA==.',
Ve='Veelete:BAAANQADCgcICwABNQAECggILAARADAjAA==.Vengeancedh:BAAANQAECgUIDwAAAA==.Veroya:BAAANQAECgEIAQAAAA==.Vespra:BAAANQADCgYIBgAAAA==.Veylara:BAAANQADCgIIAgAAAA==.',
Vi='Viix:BAAANQADCgIIAgAAAA==.Vinno:BAAANQAECgEIAgAAAA==.Virr:BAAANQAECgYIDwAAAA==.',
Vo='Volcker:BAABNQAECn8rAAIGAAcKwgikOQAhAQAGAAcKwgikOQAhAQAAAA==.Volthreal:BAAANQADCggICAABNQAECgoKNQAaAKslAA==.Voltuk:BAABNQAECn81AAQaAAoKqyVuAgDpAgAaAAoKqyVuAgDpAgAbAAMKiQrgJQCAAAAZAAEK2wmn8gA5AAAAAA==.',
Wa='Walrustusk:BAAANQAECgcIBwAAAA==.Wariius:BAAANQAECgIIAgAAAA==.Warwarb:BAAANQAECggICgAAAA==.Wasabijack:BAAANQADCgcJCgAAAA==.Waterliliy:BAABNQAECn8kAAQSAAkKlBGWKADkAQASAAkKlBGWKADkAQAmAAIKPQuSIABdAAALAAIKhAEz9wA/AAAAAA==.Wayhn:BAAANQADCgYIBgAAAA==.',
Wh='Whatcrap:BAAANQAECgEIAQAAAA==.Whathehay:BAAANQADCgQIBAAAAA==.',
Wi='Wickedmon:BAAANQADCgMIAwAAAA==.Windfurypie:BAAANQADCggICQAAAA==.',
Wo='Wolfbish:BAAANQAECgUICAAAAA==.Wongidan:BAAANQAECggICwAAAA==.',
['Wý']='Wýler:BAAANQADCgIIAgABNQADCggICAAUAAAAAA==.',
Xa='Xacious:BAAANQAECgcIEwAAAA==.',
Xh='Xhuri:BAAANQADCgYIBgAAAA==.',
['Xë']='Xëna:BAABNQAECn8jAAMNAAcKyxtSGACvAQANAAcKyxtSGACvAQAOAAIKSwSCpwBJAAAAAA==.',
Yo='Yorllik:BAAANQAECgUIDgAAAA==.',
Yt='Yt:BAABNQAECn8VAAITAAgKhQ+JHQBAAQATAAgKhQ+JHQBAAQAAAA==.',
Yu='Yueguanghua:BAAANQADCgUIBQAAAA==.Yuzuha:BAAANQADCgIIAgAAAA==.',
Ze='Zeddicus:BAAANQAECgQIBAAAAA==.Zendragon:BAABNQAECn8qAAMGAAkKpCMRBgCSAgAGAAkKpCMRBgCSAgAFAAcKDQq9AQEdAQABNQAECgoKNQAaAKslAA==.',
Zh='Zhorvan:BAAANQADCggIGQABNQAECggIGgAGAEQHAA==.',
Zi='Zilstar:BAAANQAECgUIBQAAAA==.',
Zo='Zoomy:BAAANQADCggICAAAAA==.',
Zu='Zuggondeez:BAAANQAECgUIBQABNQAECggIIQAEAEkUAA==.Zuggsalot:BAAANQAECgIIAQAAAA==.',
['Âr']='Ârtëmïs:BAABNQAECn8WAAIEAAcKIQfj4AA/AQAEAAcKIQfj4AA/AQAAAA==.',
['Åp']='Åpollo:BAACNQAFFH8LAAIHAAYK8hcWBACjAQAHAAYK8hcWBACjAQA1AAQKfxsAAgcACgqIG9wQAHECAAcACgqIG9wQAHECAAAA.',
['Òm']='Òmgitsbwòng:BAABNQAECn8bAAIWAAgKGgq0NACoAQAWAAgKGgq0NACoAQABNQAECggICwAUAAAAAA==.',
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
