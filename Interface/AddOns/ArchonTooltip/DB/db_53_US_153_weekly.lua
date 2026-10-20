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

local lookup = {'DeathKnight-Unholy','DeathKnight-Blood','Mage-Frost','Hunter-BeastMastery','Unknown-Unknown','Paladin-Retribution','Paladin-Protection','Monk-Mistweaver','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Priest-Holy','Mage-Arcane','Druid-Restoration','Druid-Balance','Evoker-Devastation','Paladin-Holy','Priest-Shadow','DemonHunter-Devourer','Evoker-Preservation','DeathKnight-Frost','Hunter-Marksmanship','DemonHunter-Vengeance','Shaman-Elemental','Warrior-Arms','Warrior-Fury','Warrior-Protection','Rogue-Subtlety','Rogue-Assassination','Druid-Feral','Druid-Guardian','DemonHunter-Havoc','Monk-Windwalker','Shaman-Enhancement','Shaman-Restoration','Monk-Brewmaster','Rogue-Outlaw','Priest-Discipline','Mage-Fire','Hunter-Survival',}
local provider = {region='US',realm='Malygos',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Absofsteels:BAABNQAECn8aAAMBAAcKpxWlVAC/AQABAAcKpxWlVAC/AQACAAMKtQcDsABrAAAAAA==.',
Ac='Acaric:BAABNQAECn8aAAIDAAcKkAdpFwBAAQADAAcKkAdpFwBAAQAAAA==.',
Ad='Adøra:BAACNQAFFH8IAAIEAAMKmAhOCQDUAAAEAAMKmAhOCQDUAAA1AAQKf0MAAgQACgqVGmERAOYBAAQACgqVGmERAOYBAAAA.',
Ag='Agumon:BAABNQAECn8WAAICAAYKFBw5GAAoAQACAAYKFBw5GAAoAQAAAA==.',
Al='Alchemist:BAAANQADCgUICQAAAA==.Alistair:BAAANQADCgUIBQAAAA==.Alluriel:BAAANQAECgIIBAAAAA==.Alonas:BAAANQAECgYICAABNQAECggIEwAFAAAAAA==.Altharoth:BAABNQAECn8uAAMGAAkK9xr/XACBAgAGAAkK9xr/XACBAgAHAAEKzAypcQAuAAAAAA==.Altherion:BAAANQADCgUIBwAAAA==.',
Am='Amique:BAAANQABCgIIAgAAAA==.Amira:BAAANQADCgYIDwABNQAFFAUICgAIAMkZAA==.Amormage:BAAANQAECgQICwAAAA==.Amphitrite:BAAANQADCgUIBQAAAA==.',
An='Anabolicrage:BAAANQADCggICQAAAA==.Anteiku:BAAANQAECgIIBAAAAA==.Anteikudeath:BAAANQADCgEIAQAAAA==.',
Ap='Applemoose:BAABNQAECn8iAAQJAAoKFRyMcwAHAgAJAAgKRR2McwAHAgAKAAIKhBgNUQCMAAALAAEK8BVmKQBGAAAAAA==.',
Ar='Aragrar:BAAANQAECgQIBQAAAA==.Arauial:BAABNQAECn8fAAIMAAkK2R6sNACVAgAMAAkK2R6sNACVAgAAAA==.Arcanis:BAABNQAECn8tAAMNAAoKqhOLqAAxAgANAAoKdROLqAAxAgADAAIKBxftLwCBAAAAAA==.Aribella:BAACNQAFFH8GAAIEAAMKSQkJCQDZAAAEAAMKSQkJCQDZAAA1AAQKfx8AAgQACgrKEfVgAFUCAAQACgrKEfVgAFUCAAAA.Arizae:BAAANQAECgQICQAAAA==.Arizann:BAABNQAECn8UAAMOAAcKLhktJQD6AQAOAAcKLhktJQD6AQAPAAUKzRHcYwA+AQAAAA==.Arobotev:BAABNQAECn8tAAIQAAgKZxL+AgCPAQAQAAgKZxL+AgCPAQAAAA==.',
As='Astaren:BAAANQADCgcIEAAAAA==.Asuran:BAAANQAECggIDQAAAA==.',
At='Atiya:BAACNQAFFH8FAAIRAAMKbBCdCAD2AAARAAMKbBCdCAD2AAA1AAQKfyEAAhEACgocFK5OADACABEACgocFK5OADACAAAA.',
Az='Azaris:BAABNQAECn8gAAMSAAkK1xMIIwAaAgASAAkK1xMIIwAaAgAMAAEKowlQ9gBBAAAAAA==.',
Ba='Babykraze:BAABNQAECn8bAAIEAAcK1w3poQDCAQAEAAcK1w3poQDCAQAAAA==.Baelrog:BAAANQAECgUIEgAAAA==.Baiene:BAAANQAECggIEAAAAA==.Baiken:BAAANQAECgEIAQAAAA==.Baldheadelf:BAAANQADCgQIBAAAAA==.Bandalar:BAABNQAECn8lAAITAAgKYxdSIwAvAgATAAgKYxdSIwAvAgAAAA==.Banerino:BAAANQADCgIIAgAAAA==.Barkathemoon:BAAANQABCggICAABNQADCgcIFQAFAAAAAA==.Barnabust:BAAANQAECgUICgAAAA==.Bashems:BAAANQAECgEJAQAAAA==.Baston:BAAANQADCgIIAgAAAA==.Bastrd:BAAANQAECgMIAwAAAA==.',
Be='Bearypie:BAAANQAECggICAAAAA==.Beastums:BAABNQAECn8vAAIEAAgK5xbBFADNAQAEAAgK5xbBFADNAQAAAA==.',
Bi='Bigbôotyjudy:BAAANQADCgIIAgAAAA==.Bigchungus:BAAANQADCggICQAAAA==.Bingbong:BAAANQADCgEIAQAAAA==.',
Bl='Blacken:BAAANQADCgQIBgAAAA==.Bleak:BAAANQADCgQIBAAAAA==.Blindmonk:BAAANQAECggIAwAAAA==.Blite:BAAANQADCgUIDgAAAA==.Bloodmary:BAABNQAECn8fAAIGAAcKTAwzVgAYAQAGAAcKTAwzVgAYAQAAAA==.Bloodor:BAAANQAECgEIAQAAAA==.Bloöm:BAABNQAECn82AAIOAAoKAyAzBQBvAwAOAAoKAyAzBQBvAwAAAA==.',
Bm='Bmaazi:BAABNQAECn8lAAMUAAgKwxokAgAyAgAUAAgKwxokAgAyAgAQAAUKYgRMLADAAAAAAA==.',
Bo='Bonerina:BAAANQAECgQICQAAAA==.Boomadk:BAACNQAFFH8JAAIVAAQKwxIrBQDkAAAVAAQKwxIrBQDkAAA1AAQKfzwAAhUACgqsIT4EAC0CABUACgqsIT4EAC0CAAAA.',
Br='Bradburn:BAAANQADCgYIDAAAAA==.Bradkink:BAAANQAECgEIAQAAAA==.Brasserz:BAABNQAECn8ZAAMEAAgKFw+0uwCMAQAEAAgKFw+0uwCMAQAWAAEKAABJlAAsAAAAAA==.Breezybone:BAABNQAECn8lAAIDAAkK4xkcBADzAgADAAkK4xkcBADzAgAAAA==.Briaela:BAAANQADCgIIAgAAAA==.Brice:BAAANQADCgYICgAAAA==.Briochebun:BAABNQAECn8cAAIGAAkKRxUYeQA6AgAGAAkKRxUYeQA6AgAAAA==.',
Bw='Bwangifer:BAABNQAECn8uAAIXAAgKjxvDAQDdAQAXAAgKjxvDAQDdAQAAAA==.',
['Bë']='Bëcky:BAABNQAECn8mAAMGAAoKNSX8IQA8AwAGAAoKNSX8IQA8AwARAAYKYxL4kQBpAQAAAA==.',
Ca='Caloren:BAABNQAECn8cAAIEAAoK7R9WDQB0AwAEAAoK7R9WDQB0AwABNQAECgkJLAATAJsaAA==.Camerarius:BAAANQAECgEIAQAAAA==.Cannala:BAAANQADCgUIDgAAAA==.Cargae:BAAANQADCgUIDgAAAA==.Caso:BAAANQADCgMIBAABNQAECgUICwAFAAAAAA==.',
Ce='Cellysia:BAABNQAECn8lAAMMAAgKkwRCWwC9AAAMAAgKkwRCWwC9AAASAAIKFgPCdQA7AAAAAA==.Ceramyth:BAAANQADCgcIHAAAAA==.Ceres:BAABNQAECn8vAAIKAAgKAxVlAQCIAQAKAAgKAxVlAQCIAQAAAA==.Cesara:BAABNQAECn84AAISAAoK9hnyEQDfAgASAAoK9hnyEQDfAgAAAA==.',
Ch='Chal:BAABNQAECn8iAAIGAAcKxAl+6QBJAQAGAAcKxAl+6QBJAQAAAA==.Chaplin:BAAANQAECgMIBAABNQAECggIGwAYAIgMAA==.Chasterra:BAAANQADCgEIAQABNQAECgkJMgAOAM8bAA==.Chbribs:BAAANQAECgUIDAAAAA==.Chestypanda:BAAANQADCgQIBAAAAA==.Chiptewth:BAAANQABCgYICQAAAA==.Chiron:BAAANQADCgEIAQAAAA==.',
Co='Coldsteel:BAAANQADCggIKAAAAA==.Columbina:BAABNQAECn8dAAITAAgKVBSjKAD/AQATAAgKVBSjKAD/AQAAAA==.Cooperhowerd:BAAANQADCgUIDAAAAA==.Corky:BAAANQADCgEIAQABNQAECgcIFAAOAC4ZAA==.Corn:BAAANQADCgIIAgABNQAECgUICQAFAAAAAA==.',
Cp='Cptredbeardd:BAAANQADCgYIDgAAAA==.',
Cr='Crackmonger:BAACNQAFFH8FAAIZAAIKLxXkLACWAAAZAAIKLxXkLACWAAA1AAQKfyMAAhkACQquGh9ZAIACABkACQquGh9ZAIACAAAA.Crackundead:BAABNQAECn8xAAIVAAoKwRjnIQB+AgAVAAoKwRjnIQB+AgAAAA==.Crapdragon:BAAANQAECgQIBgAAAA==.',
Cy='Cyphr:BAABNQAECn8vAAIOAAgKtRstBQAQAgAOAAgKtRstBQAQAgAAAA==.Cyrinx:BAAANQAECgcIDgAAAA==.',
Da='Daen:BAAANQADCggICAAAAA==.Dagravytrain:BAAANQAECgUJBgAAAA==.Dain:BAAANQADCgYIBgAAAA==.Dalend:BAAANQAECggIEAAAAA==.Damerot:BAABNQAECn8fAAMaAAkKQhFwCwAMAgAaAAkKQhFwCwAMAgAbAAEK2gfYJAAtAAAAAA==.Dangerous:BAAANQAECgQICQAAAA==.Danpal:BAAANQADCggICQAAAA==.Dansharo:BAAANQADCgMIAwAAAA==.Darc:BAAANQAECgQIBAAAAA==.Darnnix:BAAANQAECgUICwAAAA==.Darthrevin:BAABNQAECn8eAAMcAAkKaQ1EJACmAQAcAAgKaAxEJACmAQAdAAYKMAhnYAAzAQAAAA==.Dawnsingers:BAAANQADCggIFgAAAA==.',
De='Deadbeard:BAABNQAECn89AAQVAAoKJSXhAgC4AwAVAAoKJSXhAgC4AwACAAYKJR2xSQDRAQABAAQKASTDeAA3AQAAAA==.Deathbash:BAAANQADCgEIAQAAAA==.Deathdream:BAAANQADCggIDgAAAA==.Deathrar:BAAANQADCgcICwAAAA==.Deathviix:BAAANQAECgEIAQAAAA==.Debased:BAABNQAECn8nAAIBAAgKGxVNCACsAQABAAgKGxVNCACsAQAAAA==.Demini:BAAANQADCgYIDQAAAA==.Demisê:BAABNQAECn88AAICAAoKqRSxFgAyAQACAAoKqRSxFgAyAQAAAA==.Demonn:BAAANQAECgYIDQAAAA==.Derbygirl:BAAANQADCgYIDQAAAA==.Desperation:BAAANQAECgcIEAAAAA==.Desso:BAAANQAECgYICgAAAA==.Detraz:BAAANQABCgEIAQAAAA==.Devilskin:BAAANQADCgUICgAAAA==.',
Di='Dillinger:BAAANQAECgQIBQAAAA==.Dingodgaf:BAABNQAECn8mAAIGAAcK4wbX8AA7AQAGAAcK4wbX8AA7AQAAAA==.',
Dj='Djinnjuicy:BAABNQAECn8dAAINAAcKpQivHAFcAQANAAcKpQivHAFcAQAAAA==.',
Do='Dodo:BAAANQAECgQICgAAAA==.Dorianmyth:BAABNQAECn8aAAIHAAgKRAecOAAnAQAHAAgKRAecOAAnAQAAAA==.',
Dr='Dragonshammy:BAAANQADCgMIAwABNQAECggIIwARAHcdAA==.Drazzi:BAAANQAECgEIAQAAAA==.Dreamclaw:BAABNQAECn8ZAAMeAAgKEw2oDgC8AAAeAAgK3QuoDgC8AAAfAAQKkwpgRQCeAAAAAA==.Drippindots:BAACNQAFFH8GAAMJAAMKIBstKgC1AAAJAAIKiR8tKgC1AAAKAAEKThIFCABXAAA1AAQKfzQAAwkACQp2I3oLAHEDAAkACQp2I3oLAHEDAAoAAQoeFuQSAEcAAAAA.Driztette:BAAANQAECgYICgAAAA==.Drnewport:BAAANQADCggIEwAAAA==.Drokash:BAAANQAECgYIBgAAAA==.Drystine:BAABNQAECn8ZAAIgAAYKThFMTABuAQAgAAYKThFMTABuAQAAAA==.',
Dy='Dyronebiggum:BAAANQADCggIDAAAAA==.',
['Dí']='Dín:BAAANQAECgYIDQAAAA==.',
Ec='Ectharienne:BAAANQABCgMIAwAAAA==.',
Ee='Eedeeweewee:BAAANQADCgUIDgAAAA==.',
Eg='Eggs:BAAANQADCgEIAQAAAA==.',
Ei='Eillaura:BAABNQAECn84AAIMAAoKVxnPFgC7AQAMAAoKVxnPFgC7AQAAAA==.',
El='Eleredra:BAAANQADCgYIBgABNQAECgkJIQASAJQRAA==.Elipsis:BAACNQAFFH8HAAIMAAMKcxnjDADtAAAMAAMKcxnjDADtAAA1AAQKfzMAAgwACgqiJFcHAIoDAAwACgqiJFcHAIoDAAAA.Elm:BAABNQAECn8aAAMPAAcKBBQiQQD0AQAPAAcKBBQiQQD0AQAOAAIK6gxuaABjAAAAAA==.Elybella:BAAANQADCgMIAwABNQAFFAMIBgAUAL0YAA==.Elycia:BAAANQAECgYIBwABNQAFFAMIBgAUAL0YAA==.Elyenora:BAACNQAFFH8GAAIUAAMKvRhkBgDdAAAUAAMKvRhkBgDdAAA1AAQKfyIAAhQACgrYFg8WAFUCABQACgrYFg8WAFUCAAAA.',
En='Enquea:BAAANQAECgQICQABNQAECgcIFAAOAC4ZAA==.Enricco:BAAANQADCggIGgAAAA==.',
Er='Eraeste:BAAANQABCgQIAwAAAA==.Ereko:BAABNQAECn8dAAIEAAcKuw1opQC7AQAEAAcKuw1opQC7AQAAAA==.Eriss:BAABNQAECn8eAAINAAgKNRFTuQARAgANAAgKNRFTuQARAgAAAA==.Erythorbic:BAABNQAECn8XAAMJAAcK3xg0uABdAQAJAAYKWBU0uABdAQAKAAIKDxxdSgCgAAAAAA==.',
Es='Estralage:BAAANQADCgUICwAAAA==.',
Ev='Evictor:BAAANQADCgIJAgABNQAECgcIEQAFAAAAAA==.',
Fa='Fanaticism:BAAANQAECgMIAwAAAA==.Fangs:BAAANQAECgIIAgABNQAECgkJGwAKAHkZAA==.Faranth:BAAANQAECgUIDwAAAA==.',
Fe='Feer:BAAANQADCgQICAAAAA==.Feldron:BAAANQAECggIEQAAAA==.',
Ff='Ffugher:BAAANQAECgUICQAAAA==.Ffugme:BAABNQAECn8lAAMHAAgKBAowOAAqAQAHAAgKrQkwOAAqAQAGAAYKVATEhgDCAAAAAA==.Ffugnutz:BAAANQADCgQIBAAAAA==.Ffugoff:BAAANQAECgYICwAAAA==.Ffugtard:BAABNQAECn8eAAIEAAcK2gtVXwDsAAAEAAcK2gtVXwDsAAAAAA==.Ffugyou:BAAANQADCggICwAAAA==.',
Fi='Finnian:BAABNQAECn8hAAIRAAgK6xCcJgBIAQARAAgK6xCcJgBIAQAAAA==.Fio:BAAANQAECgYICQAAAA==.Firiona:BAAANQAECgUICwABNQAECggIKgAcAI8eAA==.',
Fl='Flowers:BAABNQAECn8eAAITAAcKrR+FIABJAgATAAcKrR+FIABJAgAAAA==.Fläva:BAAANQADCgMIAwAAAA==.',
Fo='Foot:BAAANQADCgYICgAAAA==.Foxhound:BAABNQAECn8dAAIhAAcKAQ2ONgBhAQAhAAcKAQ2ONgBhAQAAAA==.',
Fr='Fracture:BAAANQADCggICAABNQAECgYIHwAiAAQJAA==.Fresca:BAAANQADCgEIAQAAAA==.Friendlyhoss:BAAANQADCgIIAgAAAA==.Frostypie:BAAANQADCggIEAAAAA==.',
Fu='Funkyfungi:BAAANQAECgEIAQAAAA==.Furyswarm:BAAANQAECggIBgAAAA==.',
['Fö']='Föx:BAAANQADCgYIBgAAAA==.',
Ga='Gaius:BAAANQAECgQICAAAAA==.Gawdcomplex:BAABNQAECn8bAAIRAAcKYQzHiwB5AQARAAcKYQzHiwB5AQAAAA==.',
Ge='Gernaj:BAAANQADCgcICwAAAA==.',
Gh='Ghostfrudge:BAAANQADCggICAAAAA==.Ghostfudge:BAABNQAECn8sAAMHAAkK1RqIBADCAQAHAAgKLh+IBADCAQARAAEKywDsqQAKAAAAAA==.',
Gi='Ginny:BAAANQAECgYIDgAAAA==.Ginsan:BAAANQADCgEIAQAAAA==.Ginthalos:BAAANQADCgYIDwAAAA==.',
Go='Golaru:BAAANQABCgIIAgAAAA==.',
Gr='Gramthyr:BAAANQADCgUIDgAAAA==.Grep:BAAANQADCgMIAwAAAA==.Greygor:BAAANQAECgYICwAAAA==.Grotok:BAAANQADCggIDgABNQAECggIIAAEABYUAA==.',
Gu='Gumer:BAAANQAECgcIEwAAAA==.Gurgatron:BAAANQAECgYIDAABNQAECgkJLgAbAEcjAA==.Guulen:BAAANQADCgIIAgAAAA==.',
['Gá']='Gárd:BAAANQADCggICAAAAA==.',
Ha='Halygos:BAAANQAECgQIBQAAAA==.Hariffug:BAAANQADCgcIBwAAAA==.Hasklaufien:BAAANQAECgcIEgAAAA==.',
He='Healinside:BAAANQAECgQIBQABNQAECggIIwARAHcdAA==.Hellvina:BAAANQADCggICAAAAA==.Hermie:BAAANQABCggICAAAAA==.',
Hi='Hinderberg:BAAANQAECgEIAQAAAA==.',
Ho='Holdor:BAAANQAECgUIEgAAAA==.Horde:BAAANQADCgIIAgAAAA==.',
Hu='Huntsum:BAABNQAECn8gAAMEAAgKFhRJfAAVAgAEAAcKvBVJfAAVAgAWAAYKhgwIGwC2AAAAAA==.',
Ia='Iahsotgievhu:BAAANQADCgcICAAAAA==.Iamspeed:BAAANQABCgEIAQAAAA==.',
Ic='Iceblocklulz:BAAANQADCgMIAwAAAA==.Icedsoul:BAAANQAECgUIEAAAAA==.Iceflame:BAAANQADCgYIBgABNQAECgcIHQAOAIsbAA==.',
Ig='Iggey:BAABNQAECn8cAAIZAAgKXw/OlwDhAQAZAAgKXw/OlwDhAQAAAA==.',
Ik='Ikkaku:BAAANQADCggIDQAAAA==.',
Il='Ilandras:BAABNQAECn8eAAITAAgKUhc9JAAlAgATAAgKUhc9JAAlAgAAAA==.Illadus:BAABNQAECn8VAAITAAYKag4xPwBRAQATAAYKag4xPwBRAQAAAA==.Illiviix:BAAANQADCgcIHgAAAA==.',
In='Indra:BAABNQAECn8oAAIGAAgKVB9mSwCzAgAGAAgKVB9mSwCzAgAAAA==.Intoxicated:BAAANQAECgMIBQAAAA==.',
Ir='Iranna:BAACNQAFFH8VAAMdAAUKWyNrAQAzAQAdAAQKriRrAQAzAQAcAAIKyyHaCwBjAAA1AAQKfyAAAx0ACgq3JB4NABwDAB0ACgq3JB4NABwDABwAAgrUF6A5AHAAAAAA.',
It='Itsredbelow:BAAANQAECgEIAwAAAA==.',
Iz='Izlaz:BAAANQADCggICAAAAA==.',
Ja='Jacrispy:BAAANQAECgIJAwAAAA==.Jaggedace:BAABNQAECn8dAAMVAAkKBwbURACUAAACAAYKvgR3igDWAAAVAAUKvQfURACUAAAAAA==.Janaki:BAABNQAECn8yAAMOAAkKzxu3AgCSAgAOAAkKzxu3AgCSAgAPAAYKiQhccAAJAQAAAA==.',
Je='Jellyfish:BAABNQAECn8VAAIGAAYKpxJrgwDHAAAGAAYKpxJrgwDHAAAAAA==.',
Ji='Jibbtotem:BAAANQADCgYIDQABNQAECgkJHQASAE8WAA==.Jivanos:BAAANQADCgUIBQAAAA==.',
Jo='Joexotick:BAAANQABCgMIBQAAAA==.Jonnyquestt:BAABNQAECn8nAAIGAAgKXA3qtQCyAQAGAAgKXA3qtQCyAQAAAA==.',
Ju='Junlock:BAAANQAECgYICgABNQAFFAYIFAATAMcbAA==.Junrush:BAACNQAFFH8UAAITAAYKxxszAQBiAQATAAYKxxszAQBiAQA1AAQKfyQAAxMACgp/HiIWALICABMACgp/HiIWALICABcAAQoAAMcvAD8AAAAA.Junshot:BAAANQAECgEIAQABNQAFFAYIFAATAMcbAA==.',
Ka='Kalietha:BAABNQAECn8UAAMKAAcKFQgcSACnAAAJAAcKKAWX0QAmAQAKAAMK3gwcSACnAAAAAA==.Karaizula:BAABNQAECn8hAAMjAAgKFwwDNAAUAQAjAAgKFwwDNAAUAQAYAAQKTwFGBgGBAAAAAA==.Kassandrah:BAAANQADCgUIBQAAAA==.Katsuko:BAABNQAECn8jAAICAAgK7RWYEQBVAQACAAgK7RWYEQBVAQAAAA==.Kattnirra:BAABNQAECn8bAAIEAAcKyAsdqgCxAQAEAAcKyAsdqgCxAQAAAA==.Katze:BAABNQAECn8iAAIEAAkKRhEzZABNAgAEAAkKRhEzZABNAgAAAA==.Kaylé:BAAANQAECgMIAwAAAA==.',
Ke='Keepper:BAAANQAECgMIBwAAAA==.Kenj:BAABNQAECn8pAAIMAAkK8CPuBgCOAwAMAAkK8CPuBgCOAwABNQAFFAUICwAOAMAXAA==.Kenjurr:BAABNQAECn8fAAMUAAkKTB/HBgA6AwAUAAkKTB/HBgA6AwAQAAIKOAtdNQBiAAABNQAFFAUICwAOAMAXAA==.Kenslynn:BAABNQAECn8iAAIMAAkKkBykKQDCAgAMAAkKkBykKQDCAgAAAA==.Ketheric:BAAANQADCgEIAQABNQAECgkJGwAKAHkZAA==.',
Ki='Kiannor:BAABNQAECn8gAAIhAAgKHQZjEgAaAQAhAAgKHQZjEgAaAQAAAA==.Killahaseo:BAABNQAECn8cAAIGAAgKzSH0SQC3AgAGAAgKzSH0SQC3AgAAAA==.Killmoedee:BAABNQAECn8qAAMHAAgKhyA5EACaAgAHAAgKhyA5EACaAgAGAAMKCQVU1ABZAAAAAA==.Kishibe:BAAANQAECgUIDQAAAA==.Kiss:BAAANQAECggIEwABNQAFFAgILgAjAGokAA==.Kitwryn:BAAANQADCgUIDgAAAA==.',
Kl='Klexios:BAAANQAECgQICQAAAA==.',
Ko='Koopa:BAAANQAECgYIEAAAAA==.',
Kr='Kraulhoof:BAAANQAECgEIAQABNQAECgQIBQAFAAAAAA==.Kronohs:BAAANQAECgIIAwAAAA==.Krymson:BAAANQADCgcIBwAAAA==.',
Ku='Kui:BAABNQAECn8qAAIkAAgKIhdIAwB6AQAkAAgKIhdIAwB6AQAAAA==.Kuneia:BAAANQADCgQIBAABNQAECgkJMgAOAM8bAA==.Kurakka:BAAANQADCgEIAQAAAA==.Kuyna:BAAANQADCgYIDgAAAA==.',
Ky='Kylohendrix:BAAANQAECgQIBAAAAA==.',
['Kö']='Köz:BAAANQADCgQIBAAAAA==.',
La='Laetri:BAAANQAECgQIBAAAAA==.Lailiia:BAABNQAECn8hAAIIAAcKFBJECABYAQAIAAcKFBJECABYAQAAAA==.Laindrin:BAAANQADCgcIDQAAAA==.Lavendarlace:BAAANQADCgYIDAAAAA==.Lawrence:BAAANQADCggICAAAAA==.Lazloo:BAABNQAECn8gAAIZAAgKQiRqJgAfAwAZAAgKQiRqJgAfAwAAAA==.Lazymidget:BAABNQAECn8YAAIWAAkKYgduOQCFAQAWAAkKYgduOQCFAQAAAA==.Lazytok:BAAANQAECgMIAwAAAA==.',
Le='Leftÿ:BAABNQAECn85AAIVAAoKmxwfEgD8AgAVAAoKmxwfEgD8AgAAAA==.Legindkiller:BAAANQADCgUIDgAAAA==.Lenie:BAAANQAECggIEgABNQAFFAYIEwACAGghAA==.Levoyon:BAAANQAECgYICQAAAA==.Lexibelle:BAABNQAECn8mAAIJAAgKGQz3LwA4AQAJAAgKGQz3LwA4AQAAAA==.',
Lf='Lfty:BAAANQADCggIDAABNQAECgoKOQAVAJscAA==.',
Li='Lightace:BAABNQAECn8jAAMGAAgKSQoogQDKAAAHAAYKAwwKPQAMAQAGAAgKzQYogQDKAAAAAA==.Lightbunny:BAAANQAECggIEQAAAA==.Lincia:BAAANQAECgQIBgAAAA==.Linkkil:BAAANQAECgUIBQAAAA==.Liv:BAAANQADCgMIAwABNQAECgkJGAAMAFAXAA==.',
Lo='Loastotem:BAAANQADCgIIAgAAAA==.Lobos:BAABNQAECn8tAAIJAAkKhA5OdQACAgAJAAkKhA5OdQACAgAAAA==.Lockrah:BAAANQADCgUIDAAAAA==.Lorvinion:BAAANQADCgYIBgAAAA==.Lostdraco:BAAANQAECgYIDgAAAA==.Lostdream:BAABNQAECn8qAAMgAAkKWwh6SACGAQAgAAkKWwh6SACGAQAXAAgKkwOCHgDaAAAAAA==.Loun:BAAANQAECgcIDgAAAA==.',
Lu='Luiss:BAABNQAECn8WAAIGAAQKcAmjOgHCAAAGAAQKcAmjOgHCAAAAAA==.Luminism:BAABNQAECn8YAAMRAAkKRxfSPgBpAgARAAkKRxfSPgBpAgAGAAEKAACCjgFGAAABNQAECgcICQAFAAAAAA==.Luvlycruelty:BAAANQAECgYIDQAAAA==.',
Ly='Lyn:BAEBNQAECn8qAAIkAAkKLCZmAADvAwAkAAkKLCZmAADvAwAAAA==.',
['Lê']='Lêônà:BAAANQABCggICAAAAA==.',
Ma='Maazi:BAAANQADCgYIBgAAAA==.Mackenziiee:BAABNQAECn8xAAIEAAoKbBcROwC5AgAEAAoKbBcROwC5AgAAAA==.Madglowup:BAABNQAECn8ZAAIlAAgK4hyABQCTAgAlAAgK4hyABQCTAgAAAA==.Magerick:BAAANQAECgUICwAAAA==.Magicwater:BAAANQADCggICwABNQAECgoKKAAGAHwiAA==.Magtaki:BAAANQADCgEJAQAAAA==.Mainline:BAAANQAECgQIBwAAAA==.Maizepriest:BAABNQAECn8dAAISAAgKzB6OHgBLAgASAAgKzB6OHgBLAgAAAA==.Maliaa:BAAANQADCgcIFQAAAA==.Malloryrose:BAAANQADCgcIBwAAAA==.Mandrison:BAAANQAECgcICgAAAA==.Masfima:BAAANQADCgIIAgAAAA==.Maxz:BAAANQADCggIHAAAAA==.',
Mc='Mcstàbby:BAAANQABCgMIAwAAAA==.',
Me='Meerkat:BAAANQAECgQIBAAAAA==.Mellowblink:BAABNQAECn8YAAINAAYKmBWJAAGNAQANAAYKmBWJAAGNAQABNQAECggIKgAcAI8eAA==.Mellowlink:BAABNQAECn8qAAMcAAgKjx76DQCXAgAcAAgKjx76DQCXAgAdAAEKURK6SQBBAAAAAA==.',
Mi='Migglet:BAAANQAECgMIAwAAAA==.Miirya:BAAANQADCgYIAwAAAA==.Mimi:BAACNQAFFH8gAAMEAAkKvyJPAgBYAgAWAAgK6x/vAgBuAgAEAAYK9CVPAgBYAgA1AAQKfzAAAxYACgpQJoEGAGgDABYACQpOJoEGAGgDAAQACApFJj8mAP4CAAAA.Miramage:BAAANQADCgcIBwABNQAECgkJHAAEABYaAA==.Miravus:BAAANQAECgUIDAABNQAECgkJHAAEABYaAA==.Misttie:BAABNQAECn8XAAIkAAkKZx0+AQAIAgAkAAkKZx0+AQAIAgABNQAFFAMIBwAMAHMZAA==.Mitcheoff:BAAANQAECgQICwAAAA==.',
Mo='Moisturizer:BAAANQAECgUICQAAAA==.Monkerick:BAAANQADCgQIBwAAAA==.Mowte:BAAANQADCgUIDgAAAA==.',
Mu='Murkoobi:BAAANQAECgEIAQAAAA==.',
My='Mystrial:BAAANQABCgYICgAAAA==.Mystáke:BAAANQAECgcIDgAAAA==.',
['Mó']='Mómo:BAAANQADCgMIAwAAAA==.Móus:BAAANQADCgIIAgABNQAECggIGgAjADYVAA==.',
Na='Narbus:BAABNQAECn8UAAIPAAUKBQ4acAAKAQAPAAUKBQ4acAAKAQAAAA==.Narcissus:BAAANQADCgUIDgAAAA==.Naromancer:BAABNQAECn8vAAINAAgKcB5DDwDuAQANAAgKcB5DDwDuAQAAAA==.Nathadon:BAABNQAECn8wAAISAAoKJCDYAADcAgASAAoKJCDYAADcAgAAAA==.Nautrium:BAAANQAECgMIBgAAAA==.',
Ne='Necrotis:BAAANQADCgUIDgAAAA==.Nekhraros:BAABNQAECn8bAAMKAAkKeRmPMAAGAQAJAAYKmRUwogCRAQAKAAMKox6PMAAGAQAAAA==.Neko:BAAANQAECggIEAAAAA==.Nergál:BAAANQADCgYIBQABNQADCggICAAFAAAAAA==.Nevelia:BAAANQADCgEIAQABNQAECgcIIQAIABQSAA==.Neytfury:BAAANQADCgUIBQAAAA==.Neyti:BAAANQADCgIIAgAAAA==.Neytvengy:BAAANQAECgMIAwAAAA==.Nezukô:BAAANQADCgUICQAAAA==.',
Ni='Nienna:BAAANQAECgMIBAABNQAECgcIFAAOAC4ZAA==.Nikkikynz:BAAANQABCgIIAgAAAA==.Nikkisan:BAAANQADCgYIGAAAAA==.Nixk:BAAANQAECgUIDQAAAA==.',
No='Noapte:BAAANQADCgYICQAAAA==.Noixi:BAABNQAECn8WAAMNAAcKSQhPPQEnAQANAAcKEgVPPQEnAQADAAMKHQtNFQBbAAAAAA==.Noras:BAAANQAECgcIEQAAAA==.Nordicslayer:BAAANQAECgEIAQAAAA==.Notagnoblin:BAECNQAFFH8VAAICAAUKYSJDCADcAQACAAUKYSJDCADcAQA1AAQKfywAAgIACgr4IvACAMMDAAIACgr4IvACAMMDAAAA.Notrick:BAAANQAECgQIBwAAAA==.',
Nu='Nuffsaid:BAAANQADCgUIBgAAAA==.',
Ny='Nyko:BAAANQADCgUIBgAAAA==.',
Oa='Oaklyn:BAAANQADCgUIBQAAAA==.',
Ob='Obsidious:BAAANQAECgYICQAAAA==.',
Og='Ogrelurd:BAABNQAECn85AAIZAAkKQhpaEQDNAQAZAAkKQhpaEQDNAQAAAA==.',
Op='Opalfox:BAAANQADCgEIAQAAAA==.Ophelia:BAABNQAECn8yAAQLAAkKsh1dCwC2AQALAAUKHR5dCwC2AQAJAAcKLBurOwAYAQAKAAIK6xKWVACBAAAAAA==.',
Or='Orakwa:BAABNQAECn8UAAMZAAgKbhKqjwD1AQAZAAgKbhKqjwD1AQAaAAQKshEfGwD1AAAAAA==.',
Os='Osteroth:BAAANQADCgcIBwAAAA==.',
Pa='Pachez:BAAANQAECgIIAgAAAA==.Paladont:BAAANQAECgUICwAAAA==.Pallinda:BAABNQAECn8jAAMRAAgKdx1YDQD1AQARAAgKdx1YDQD1AQAGAAYKoQ4s6wBFAQAAAA==.Palmogant:BAAANQAECgYIEQAAAA==.Panztide:BAAANQADCgcIBwABNQAECgkJHwAeAAMMAA==.Pappyoblues:BAAANQAECgEIAgAAAA==.Patt:BAAANQADCgUIBQAAAA==.',
Pe='Pendulumlaw:BAACNQAFFH8MAAIZAAUKbwggGgBGAQAZAAUKbwggGgBGAQA1AAQKfykAAhkACgp8Fz1nAFoCABkACgp8Fz1nAFoCAAAA.Pennypacker:BAAANQAECgQIBwABNQAECgcIFAAOAC4ZAA==.Pepe:BAAANQADCgEIAQAAAA==.',
Ph='Phinn:BAABNQAECn8kAAIPAAcKUghUJgDMAAAPAAcKUghUJgDMAAAAAA==.Phoel:BAAANQADCgUIDAAAAA==.Phoopanchu:BAAANQAECgYICwAAAA==.',
Pi='Pimikoh:BAAANQAECgQIBAAAAA==.Pinkbuns:BAAANQAECgYIDgAAAA==.',
Pn='Pneuma:BAAANQAECgUIDAAAAA==.',
Po='Pollonius:BAAANQADCgQIBAAAAA==.Poncho:BAAANQADCgIIAgAAAA==.Popsy:BAAANQAECgUIBQAAAA==.',
Pr='Prenton:BAABNQAECn8lAAIZAAcKxxxRIwB3AQAZAAcKxxxRIwB3AQAAAA==.Prepotente:BAAANQAECgMIBAABNQAECggIKgAcAI8eAA==.Prideflag:BAAANQADCggICAAAAA==.Priestin:BAAANQAECgEIAQAAAA==.Profundity:BAAANQAECgEIAQABNQAECgcIFAAOAC4ZAA==.',
Ps='Psyduck:BAABNQAFFH8FAAIZAAUKfAszFwBpAQAZAAUKfAszFwBpAQABNQAFFAkJIAAGACEfAA==.',
Pu='Punie:BAABNQAECn8kAAIYAAgKfRYzFQBzAQAYAAgKfRYzFQBzAQAAAA==.Puzzykat:BAAANQADCgYIBgAAAA==.',
['Pä']='Päg:BAAANQADCgEIAQABNQAECgoKOQAVAJscAA==.',
Qe='Qeini:BAABNQAECn8fAAImAAcKAgwvDgBMAQAmAAcKAgwvDgBMAQAAAA==.',
Ra='Radrin:BAAANQADCgcIEAAAAA==.Rafoff:BAAANQAECgUIBgAAAA==.Ragnarax:BAABNQAECn8XAAIZAAkKmx3vOQDeAgAZAAkKmx3vOQDeAgAAAA==.Rahll:BAAANQADCgIIAgAAAA==.Raikami:BAAANQAECgIIAgAAAA==.Rancoramble:BAAANQAECgUICwAAAA==.Randis:BAABNQAECn8lAAIBAAcKfQ1qJADVAAABAAcKfQ1qJADVAAAAAA==.Raysonna:BAAANQAECgYIEgAAAA==.',
Re='Rengår:BAAANQAECgUIBAAAAA==.Reticent:BAAANQAECgQIBgAAAA==.Reversewally:BAAANQAECgcIEAAAAA==.Rexhà:BAAANQAECgEIAQAAAA==.Rexiis:BAABNQAECn8YAAIJAAcKnRBpTwDmAAAJAAcKnRBpTwDmAAAAAA==.Reyth:BAAANQAECgQICwAAAA==.',
Rh='Rhuby:BAABNQAECn8iAAICAAcKHhfMGQAfAQACAAcKHhfMGQAfAQAAAA==.',
Ri='Rimos:BAAANQAECgQICAAAAA==.Riptîde:BAAANQADCggIEwAAAA==.Rivening:BAAANQAECgQIBgAAAA==.',
Rk='Rk:BAAANQADCgYICAAAAA==.',
Ro='Rochelle:BAAANQADCggIIQAAAA==.Roeyth:BAAANQADCggICAAAAA==.Rokki:BAABNQAECn8zAAINAAgKnwjd7ACxAQANAAgKnwjd7ACxAQAAAA==.Roostor:BAAANQADCggIEQAAAA==.Rosael:BAAANQADCgQJBAAAAA==.Roundhouse:BAABNQAECn8dAAIkAAcKMhzlDQAZAgAkAAcKMhzlDQAZAgAAAA==.',
Ru='Rubbmytotems:BAAANQAECgYICgAAAA==.Rubicôn:BAAANQABCgYICAABNQAFFAYIFwANAHUdAA==.Rubmyoysters:BAAANQADCgEIAQAAAA==.Ruleti:BAABNQAECn8mAAIEAAoKsRg1PwCtAgAEAAoKsRg1PwCtAgAAAA==.Rumí:BAAANQADCggJIgAAAA==.Rundeep:BAAANQABCgYICgAAAA==.Russell:BAAANQADCgUIDgAAAA==.',
Sa='Sabado:BAAANQAECgMIAwAAAA==.Safewerd:BAEANQAECgYIDQAAAA==.Saitama:BAAANQAECgYICQABNQAECgkJMgAZACoWAA==.Sangriel:BAABNQAECn8fAAICAAkKDg2rZwBUAQACAAkKDg2rZwBUAQAAAA==.Saraceleste:BAAANQAECgQIBAAAAA==.Sarafinmae:BAAANQAECgIIAgAAAA==.Sarahfi:BAAANQAECgIJAgABNQAECgUICQAFAAAAAA==.Saralanna:BAABNQAECn8nAAIJAAkK8QwfPwAQAQAJAAkK8QwfPwAQAQAAAA==.Sarasophie:BAAANQADCgcIGAAAAA==.Sarefina:BAAANQAECgQICQAAAA==.Sathenazarke:BAABNQAECn8UAAIQAAkK0B6zCADsAgAQAAkK0B6zCADsAgABNQAFFAUIFQAdAFsjAA==.',
Sc='Schism:BAAANQAECgMIBAAAAA==.Schmingus:BAAANQADCgIIAgAAAA==.Scoban:BAACNQAFFH8MAAIRAAUKbBvwCgCuAQARAAUKbBvwCgCuAQA1AAQKfxYAAhEACQqvGng2AIoCABEACQqvGng2AIoCAAAA.',
Se='Seaworld:BAAANQAECggIDgABNQAECggIKgAcAI8eAA==.Seraphnite:BAAANQADCgIIAgAAAA==.Seriousjakk:BAAANQADCgEIAQABNQADCgQIBwAFAAAAAA==.',
Sh='Shadeebear:BAAANQADCgEIAQAAAA==.Shadowtax:BAAANQADCgYIBgAAAA==.Shan:BAAANQAECgcIEwAAAA==.Shaohlin:BAAANQADCggIDgAAAA==.Shaqfu:BAAANQADCgUIDgAAAA==.Shavemybush:BAAANQADCgcJBwAAAA==.Shayy:BAABNQAECn8xAAImAAoKuRiHAAA5AgAmAAoKuRiHAAA5AgAAAA==.Sheve:BAAANQAECgQICAABNQAECgcIIAAjAPQfAA==.Shigure:BAABNQAECn8iAAMDAAoKPgqHFgBKAQANAAoKQwgW0wDgAQADAAcKOQqHFgBKAQAAAA==.Sholin:BAAANQAECgcIEAAAAA==.Shomea:BAAANQAECgQICQAAAA==.Shugz:BAAANQADCgUIDQAAAA==.Shumai:BAAANQAECgUIDAAAAA==.',
Si='Sigons:BAAANQABCgYICAAAAA==.Sikotick:BAAANQAECgUIEwAAAA==.Sikxrapture:BAAANQADCgYIBgAAAA==.Siliconista:BAACNQAFFH8IAAINAAMKORfkDAD0AAANAAMKORfkDAD0AAA1AAQKf0IAAw0ACgqHJLQCAOMCAA0ACgrVI7QCAOMCAAMABwrgJKkLAAUCAAAA.Simbelmyne:BAAANQAECgUIBQABNQAECgcIFAAOAC4ZAA==.',
Sk='Skitrit:BAAANQAECgEIAQABNQAECgoKJgAEALEYAA==.Skyjin:BAAANQADCgYJCQAAAA==.',
Sl='Slammurai:BAAANQADCgcICwAAAA==.Slippie:BAAANQADCgQIBAAAAA==.Slippinwater:BAABNQAECn8oAAIGAAoKfCKsHQBMAwAGAAoKfCKsHQBMAwAAAA==.Sllew:BAABNQAECn80AAMBAAoKexpOGQD1AgABAAkKax1OGQD1AgAVAAUKaA21KwDuAAAAAA==.Slyyce:BAAANQAECgcIDwAAAA==.',
Sm='Smoulder:BAAANQADCgIIBAAAAA==.',
Sn='Snigles:BAABNQAECn8ZAAIcAAkKKwZTKgBxAQAcAAkKKwZTKgBxAQAAAA==.Snowlily:BAAANQAECgQIBgABNQAECgkJIQASAJQRAA==.Snurp:BAAANQAECgUIDAABNQAECgoKIgAWAF4gAA==.',
So='Softnsquishy:BAAANQAECgEIAgAAAA==.Solmarrow:BAABNQAECn8YAAQDAAcKmggwGAA4AQADAAcKRggwGAA4AQANAAQKaAQchAG8AAAnAAEKFAbKDQA0AAAAAA==.',
Sp='Spanksbar:BAAANQADCggIFAAAAA==.Spartos:BAABNQAECn8iAAIZAAcKnxiYGgCbAQAZAAcKnxiYGgCbAQAAAA==.Speedy:BAABNQAECn8ZAAIEAAYKvwPShwCcAAAEAAYKvwPShwCcAAAAAA==.Speedyspeed:BAAANQADCgQIBQAAAA==.Spokes:BAAANQADCgYICQABNQAECggIAwAFAAAAAA==.Sposi:BAEBNQAECn8bAAICAAgKZCErGwDVAgACAAgKZCErGwDVAgAAAA==.Sprinkle:BAAANQAECggJCQABNQAECggIEQAFAAAAAA==.',
Sr='Srimrithyu:BAAANQADCgYIEwAAAA==.',
Ss='Sselionn:BAAANQAECgUIDgAAAA==.',
St='Stomps:BAABNQAECn8iAAIbAAgKyBeIBgBSAQAbAAgKyBeIBgBSAQAAAA==.Stonezef:BAABNQAECn8bAAINAAkKFwvf+ACbAQANAAkKFwvf+ACbAQAAAA==.',
Su='Suffocation:BAAANQADCgYIBwAAAA==.Sumbtch:BAAANQAECgUIDAAAAA==.Sungdihhwoo:BAAANQADCgQIBwAAAA==.Susann:BAABNQAECn8aAAIjAAgKNhVyaQDQAQAjAAgKNhVyaQDQAQAAAA==.',
Sy='Syravia:BAAANQAECgUIEQAAAA==.',
['Sò']='Sòlushan:BAAANQAECgEIAQABNQAECgoKIgAGAD4bAA==.',
Ta='Tahoa:BAAANQABCgQIBwAAAA==.Tameka:BAABNQAECn8wAAIEAAoKdBjFNQDKAgAEAAoKdBjFNQDKAgAAAA==.Tardis:BAAANQAECgcIBwABNQAECgoKJQAMAOcXAA==.Tatersdh:BAEANQAECgYIDAABNQAFFAUIFQACAGEiAA==.Tavinrayn:BAAANQAECgYIDAAAAA==.',
Te='Tekesh:BAAANQAECgYIDQAAAA==.Teksham:BAAANQADCgYIEgAAAA==.Telarin:BAABNQAECn8jAAMEAAgKDBVXJQCEAQAoAAcKdxPABwDtAQAEAAcKxRVXJQCEAQAAAA==.Tezrian:BAAANQADCgYJCgABNQAECggIKgAcAI8eAA==.',
Th='Thebigdawg:BAAANQADCggICQAAAA==.Theladyboy:BAABNQAECn8gAAMXAAgKxBTLAwBpAQAXAAgKxBTLAwBpAQAgAAMKtgrieQCRAAAAAA==.Thomss:BAABNQAECn8nAAIEAAgKrRO5awA7AgAEAAgKrRO5awA7AgAAAA==.Thraiene:BAAANQAECgUIDwABNQAECggIEAAFAAAAAA==.Throhk:BAAANQADCgcIFQAAAA==.Thrumgar:BAAANQAECgEIAgAAAA==.',
Ti='Tiamut:BAAANQABCgQIBAAAAA==.Tigerliley:BAAANQAECgQICAABNQAECgkJIQASAJQRAA==.Tinneas:BAAANQAECgEIAQAAAA==.',
To='Tomás:BAABNQAECn8bAAIYAAgKiAxVjACFAQAYAAgKiAxVjACFAQAAAA==.Topg:BAAANQADCgcIDAAAAA==.Torstai:BAABNQAECn8WAAILAAYKkgmwDwBTAQALAAYKkgmwDwBTAQAAAA==.Totemic:BAAANQADCggIEgAAAA==.Toyun:BAAANQADCgMIAwAAAA==.',
Tr='Trap:BAAANQADCgQIBAAAAA==.Trueshöt:BAABNQAECn8bAAMWAAcKahf0MADGAQAWAAcKUhP0MADGAQAoAAYK7xCZCQCXAQAAAA==.',
Ts='Tserendolgor:BAAANQAECgYIDAABNQAECggIKgAcAI8eAA==.',
Tu='Tukker:BAAANQADCgYIBgABNQAECgkJLgAbAEcjAA==.',
Ty='Tyedindis:BAAANQADCgEIAQAAAA==.Tyresious:BAABNQAECn8VAAIGAAcKNRlslwD1AQAGAAcKNRlslwD1AQAAAA==.',
Ut='Utherrex:BAAANQAECgEIAQABNQAECgcIGAAJAJ0QAA==.',
Va='Vahaghn:BAABNQAECn8zAAIZAAoKMx8AEwBwAwAZAAoKMx8AEwBwAwAAAA==.Valcerus:BAAANQAECgQICQAAAA==.Valedus:BAABNQAECn8nAAIGAAgKSiJJOQDrAgAGAAgKSiJJOQDrAgAAAA==.',
Ve='Veelete:BAAANQADCgcICwABNQAECggILAARADAjAA==.Vengeancedh:BAAANQAECgUICwAAAA==.Veroya:BAAANQAECgEIAQAAAA==.Vespra:BAAANQADCgYIBgAAAA==.Veylara:BAAANQADCgIIAgAAAA==.',
Vi='Viix:BAAANQADCgIIAgAAAA==.Vinno:BAAANQAECgEIAgAAAA==.Virr:BAAANQAECgUICQAAAA==.',
Vo='Volcker:BAABNQAECn8lAAIHAAcKwgiZGADHAAAHAAcKwgiZGADHAAAAAA==.Volthreal:BAAANQADCggICAABNQAECgkJLgAbAEcjAA==.Voltuk:BAABNQAECn8uAAMbAAkKRyNEAwBtAwAbAAgK9SVEAwBtAwAaAAMKiQrgJQCAAAAAAA==.',
Wa='Walrustusk:BAAANQAECgcIBwAAAA==.Wariius:BAAANQAECgIIAgAAAA==.Warwarb:BAAANQAECgYICAAAAA==.Wasabijack:BAAANQADCgcJCgAAAA==.Waterliliy:BAABNQAECn8hAAQSAAkKlBGWKADkAQASAAkKlBGWKADkAQAmAAIKPQuSIABdAAAMAAIKhAEz9wA/AAAAAA==.Wayhn:BAAANQADCgYIBgAAAA==.',
Wh='Whathehay:BAAANQADCgQIBAAAAA==.',
Wi='Wickedmon:BAAANQADCgMIAwAAAA==.Windfurypie:BAAANQADCggICQAAAA==.',
Wo='Wolfbish:BAAANQAECgUICAAAAA==.Wongidan:BAAANQAECgcIBwAAAA==.',
['Wý']='Wýler:BAAANQADCgIIAgABNQADCggICAAFAAAAAA==.',
Xa='Xacious:BAAANQAECgUIEAAAAA==.',
Xh='Xhuri:BAAANQADCgYIBgAAAA==.',
['Xë']='Xëna:BAABNQAECn8dAAMOAAcKixudJwDkAQAOAAcKixudJwDkAQAPAAIKSwSCpwBJAAAAAA==.',
Yo='Yorllik:BAAANQAECgUIDQAAAA==.',
Yt='Yt:BAAANQAECgQICgAAAA==.',
Yu='Yueguanghua:BAAANQADCgUIBQAAAA==.Yuzuha:BAAANQADCgIIAgAAAA==.',
Ze='Zeddicus:BAAANQAECgQIBAAAAA==.Zendragon:BAABNQAECn8kAAMHAAkKpCMJAQC3AgAHAAkKpCMJAQC3AgAGAAYK2wm9AQEdAQABNQAECgkJLgAbAEcjAA==.',
Zh='Zhorvan:BAAANQADCggIGQABNQAECggIGgAHAEQHAA==.',
Zi='Zilstar:BAAANQAECgUIBQAAAA==.',
Zu='Zuggondeez:BAAANQADCgMIAwABNQAECggIIAAEABYUAA==.Zuggsalot:BAAANQADCgcIBwAAAA==.',
['Âr']='Ârtëmïs:BAABNQAECn8WAAIEAAcKIQfj4AA/AQAEAAcKIQfj4AA/AQAAAA==.',
['Åp']='Åpollo:BAACNQAFFH8KAAIIAAUKyRkWBACjAQAIAAUKyRkWBACjAQA1AAQKfxgAAggACgqIG9wQAHECAAgACgqIG9wQAHECAAAA.',
['Òm']='Òmgitsbwòng:BAABNQAECn8bAAIWAAgKGgq0NACoAQAWAAgKGgq0NACoAQABNQAECgcIBwAFAAAAAA==.',
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
