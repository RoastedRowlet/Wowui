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

local lookup = {'Unknown-Unknown','Paladin-Retribution','DeathKnight-Blood','Priest-Discipline','Hunter-BeastMastery','Monk-Mistweaver','DeathKnight-Unholy','Evoker-Augmentation','Evoker-Devastation','Druid-Restoration','Druid-Guardian','Warrior-Arms','Warlock-Affliction','Hunter-Marksmanship','Shaman-Elemental','Shaman-Enhancement','Druid-Balance','Druid-Feral','DemonHunter-Devourer','DemonHunter-Havoc','Warrior-Protection','Warrior-Fury','Priest-Shadow','Rogue-Subtlety','Rogue-Assassination','Paladin-Holy','DemonHunter-Vengeance','Paladin-Protection','Mage-Frost','Warlock-Demonology','Warlock-Destruction','Priest-Holy','Shaman-Restoration','Monk-Windwalker','DeathKnight-Frost','Mage-Arcane','Monk-Brewmaster','Mage-Fire','Hunter-Survival','Rogue-Outlaw',}
local provider = {region='US',realm='Eonar',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abysseus:BAAANQADCgcIDwAAAA==.',
Ad='Admired:BAAANQAECgEIAwABNQAECgUIDAABAAAAAA==.',
Ae='Aerdrie:BAAANQABCgMIAwAAAA==.Aevelin:BAACNQAFFH8GAAICAAMKEAa1HQCrAAACAAMKEAa1HQCrAAA1AAQKfx4AAgIACgrDDxGeAOYBAAIACgrDDxGeAOYBAAAA.',
Aj='Ajagar:BAAANQAECgUICQABNQAECgoKIgADAK0JAA==.',
Al='Alamora:BAABNQAECn8XAAIEAAYK4xXzBgBuAQAEAAYK4xXzBgBuAQAAAA==.Alastair:BAAANQAECggIAgAAAA==.Alathena:BAAANQAECgMIAwAAAA==.Albrect:BAAANQADCgYIBgAAAA==.Alexandrya:BAABNQAECn86AAIFAAoK+A93cgDbAQAFAAoK+A93cgDbAQAAAA==.Alickdh:BAAANQADCgIIAgABNQAFFAEIAgABAAAAAA==.Almostpanda:BAAANQADCgUIBQABNQAECgoKHgAGAOQNAA==.Altery:BAAANQAECgEIAQAAAA==.',
Am='Ampharos:BAAANQABCgYIBgAAAA==.Amsahunter:BAAANQADCggICAABNQAECgkJGQAHAB8PAA==.Amsroeb:BAABNQAECn8ZAAMHAAkKHw/DMgBaAQAHAAcKGw/DMgBaAQADAAYKRQpsbACdAAAAAA==.',
An='Anelavenger:BAACNQAFFH8aAAIIAAcKWxhLBQB5AQAIAAcKWxhLBQB5AQA1AAQKf28AAwgACgr4I+gAAK4DAAgACgr4I+gAAK4DAAkABgppDEEjACwBAAAA.Anelblast:BAAANQAECgYIEQABNQAFFAcIGgAIAFsYAA==.Angerwina:BAAANQAECgUIDQAAAA==.Annain:BAAANQADCgYJCgAAAA==.',
Ar='Arathor:BAAANQADCggIEQAAAA==.Ardent:BAAANQAECgUICwAAAA==.Ardor:BAAANQADCgYICgABNQAECgUICwABAAAAAA==.Arent:BAABNQAECn89AAMKAAoKsBL0IAAiAgAKAAoKsBL0IAAiAgALAAcKTQscMwADAQAAAA==.Arkanna:BAAANQADCgYIBgAAAA==.Arkhea:BAAANQAECgQIBAAAAA==.Artemislives:BAAANQAECggICAAAAA==.',
As='Asharia:BAAANQAECgcIEAAAAA==.Ashla:BAAANQADCgIIAgAAAA==.Asilan:BAAANQABCgEIAQAAAA==.Assateague:BAABNQAECn8WAAIMAAUKPQNIBAFuAAAMAAUKPQNIBAFuAAAAAA==.Astelossa:BAAANQADCggIJwAAAA==.',
['Aë']='Aëro:BAAANQADCgYICQAAAA==.',
Ba='Bahnna:BAAANQADCgUICAAAAA==.Bananapistol:BAAANQABCgIIBAAAAA==.Barracksbuny:BAABNQAECn8UAAINAAoKcwmPDACXAQANAAoKcwmPDACXAQABNQAECgkKGgAFAOAWAA==.Barrathfrogy:BAAANQADCgUIDAAAAA==.',
Be='Bebheishel:BAAANQADCgQICwAAAA==.Beefcake:BAAANQADCgYIFQABNQAECgUICQABAAAAAA==.Bertello:BAAANQAECgQIBAAAAA==.Beserol:BAAANQAECgQICwAAAA==.',
Bi='Biest:BAAANQAECggICAAAAA==.Biggs:BAAANQADCggICQABNQAECggIBgABAAAAAA==.Billy:BAABNQAECn8dAAIGAAgKnxmVGAD0AQAGAAgKnxmVGAD0AQAAAA==.Bilywitchdoc:BAAANQAECgEIBQABNQAECgoKLwAOAEQcAA==.Bionicle:BAAANQADCgQIBAAAAA==.Biscuít:BAAANQAECggIDgAAAA==.',
Bk='Bk:BAAANQADCgcIDQABNQAECgoKMgAPAOMaAA==.',
Bl='Blasuoff:BAAANQADCgYIBgAAAA==.Blkmg:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Bloodeagle:BAAANQAECggIEAAAAA==.Bluechalk:BAAANQAFFAIIAgABNQAFFAkJHQAQAIsgAA==.',
Bo='Boomslap:BAAANQAECggICQAAAA==.Boredom:BAAANQADCggICAAAAA==.Borzoi:BAABNQAECn9hAAICAAoKDiaOAwB6AwACAAoKDiaOAwB6AwAAAA==.',
Br='Brawne:BAAANQADCgUIBQAAAA==.',
Bu='Buzzdkt:BAAANQAECgEIAgAAAA==.Buzzdruu:BAACNQAFFH8FAAQLAAMKbBEtBwB5AAALAAIKbBEtBwB5AAARAAEKAAA3KgAAAAASAAEKAAA5BgAAAAA1AAQKfykABBEACgqEHNAuAGgCABEACgqJF9AuAGgCABIABwqKF2AZAEgBAAsAAQqvIQNcAFwAAAAA.Buzzpal:BAAANQAECgUIBQAAAA==.',
['Bó']='Bóg:BAAANQADCgEIAQAAAA==.',
['Bø']='Bønës:BAAANQADCgQIBAAAAA==.',
Ca='Caaniss:BAAANQABCgQIBAAAAA==.Cadeana:BAAANQADCgQIBAAAAA==.Caduceus:BAAANQADCgUIBQAAAA==.Caesus:BAAANQADCgcICwAAAA==.Cagedancer:BAAANQAECgIIAgAAAA==.Callio:BAABNQAECn8/AAIFAAoKkQ6TYQADAgAFAAoKkQ6TYQADAgAAAA==.Canus:BAAANQAECggIEQAAAA==.Caprisunsipz:BAAANQAECggIDQAAAA==.Caritta:BAABNQAECn8UAAMTAAcK/hSpPgBVAQATAAYKSRCpPgBVAQAUAAMKqxaubADGAAAAAA==.Cathillex:BAABNQAECn8WAAMVAAkKSRRFFQBuAQAVAAkKSRRFFQBuAQAWAAEKVBHSMQA5AAAAAA==.Caycay:BAACNQAFFH8LAAIUAAYKbBbPCgB2AQAUAAYKbBbPCgB2AQA1AAQKf1MAAhQACgrBI4ECAM4DABQACgrBI4ECAM4DAAAA.',
Ce='Celestian:BAAANQAECggICQAAAA==.Cels:BAAANQAECgcIBwAAAA==.',
Ch='Chariso:BAAANQADCgEIAQAAAA==.Chillbros:BAABNQAECn8yAAMPAAoKBSaFGgAqAwAPAAoKBSaFGgAqAwAQAAgKexuiFQAOAgAAAA==.Chumleyson:BAAANQAECgQIBAAAAA==.Churd:BAACNQAFFH8JAAIXAAMKCwrHEQCEAAAXAAMKCwrHEQCEAAA1AAQKfy8AAhcACgpHFbwfAD0CABcACgpHFbwfAD0CAAAA.Chypnotic:BAABNQAECn8wAAIFAAkKIh4ARQCdAgAFAAkKIh4ARQCdAgAAAA==.Chypotle:BAAANQADCgYIBgAAAA==.Chypster:BAAANQADCgYIBgAAAA==.',
Ci='Ciceroe:BAABNQAECn8YAAMYAAkKpg71RQDnAQAYAAkKpg71RQDnAQAZAAUKygU1PACbAAAAAA==.',
Cl='Cleft:BAABNQAECn86AAMCAAoKeggdxQBKAQACAAoKeggdxQBKAQAaAAcK4wh2ogA/AQAAAA==.Clevelandk:BAAANQADCgQIBAAAAA==.Clowwnshoes:BAAANQAECgQICgAAAA==.',
Co='Coalystra:BAACNQAFFH8FAAITAAIKAg4+DQCJAAATAAIKAg4+DQCJAAA1AAQKf08AAxMACgoMIcgLAJYCABMACgoMIcgLAJYCABsAAQpvDcAxACkAAAAA.Cocopuffs:BAAANQAECgcIDAAAAA==.Colostrom:BAABNQAECn9KAAIcAAoKjSXpAgBFAwAcAAoKjSXpAgBFAwAAAA==.Coramage:BAABNQAECn8UAAIdAAkK+Qd0FgA1AQAdAAkK+Qd0FgA1AQAAAA==.Corliss:BAAANQAECgEIAQAAAA==.Corruptdata:BAABNQAECn84AAQeAAoKOhsCOgAqAgAeAAoKOhsCOgAqAgAfAAEKBBTCbwBAAAANAAEKjQhnMgAwAAABNQAFFAcIGgACAFcQAA==.',
Cp='Cpair:BAAANQADCggICAAAAA==.Cplusmc:BAAANQADCgUICAAAAA==.',
Cu='Cuddaloft:BAAANQADCgUIBQAAAA==.',
Cy='Cyori:BAAANQADCgIIAgAAAA==.',
Da='Darkbeast:BAABNQAECn8XAAIFAAoK3BcqkQDnAQAFAAoK3BcqkQDnAQAAAA==.Darthorc:BAAANQAECgUICQAAAA==.Daten:BAABNQAECn80AAICAAoKVQ1fqwDJAQACAAoKVQ1fqwDJAQAAAA==.Dazshauran:BAAANQADCgUICwAAAA==.',
De='Deadzexcs:BAAANQAECgMIBwAAAA==.Deathtaco:BAAANQADCgUIBQAAAA==.Decayed:BAABNQAECn8fAAIDAAoKIxMCLQCgAQADAAoKIxMCLQCgAQABNQAECgkKGgAFAOAWAA==.Deladoria:BAABNQAECn8hAAIgAAoKEQ2bawCaAQAgAAoKEQ2bawCaAQAAAA==.Depression:BAAANQADCgQIBAABNQAECgQIBQABAAAAAA==.Deragor:BAAANQADCgMIAwABNQAECgMIAwABAAAAAA==.Deus:BAAANQAECgQIBAAAAA==.',
Di='Diagonalli:BAABNQAECn8bAAIJAAkKDgkVEAA9AQAJAAkKDgkVEAA9AQAAAA==.Dirk:BAAANQAECgcIEAABNQAECgkJNAADAE4FAA==.Dirkdìggler:BAAANQADCgUIBwAAAA==.Dirti:BAAANQABCgQIAgAAAA==.Divirian:BAABNQAECn8cAAIPAAgKuRGXXgBrAQAPAAgKuRGXXgBrAQAAAA==.',
Dj='Djdaemon:BAAANQAECgQICAAAAA==.Djdrakshadow:BAAANQAECgEIBAAAAA==.Djdruidshadw:BAAANQAECgEIBAAAAA==.Djpaly:BAAANQAECgIIAwAAAA==.Djpriest:BAAANQAECgQICgAAAA==.Djshadow:BAAANQAECgQIBAAAAA==.Djshadowar:BAAANQAECgEIAwAAAA==.Djshadowhunt:BAAANQAECgMIBgAAAA==.Djshadowlock:BAAANQAECgUICQAAAA==.Djshadowlok:BAABNQAECn8UAAIeAAYK8AOO2QCfAAAeAAYK8AOO2QCfAAAAAA==.Djshadowrog:BAAANQAECgQICAAAAA==.Djshadruid:BAAANQAECgQIBwAAAA==.Djshamy:BAAANQAECgIIBgAAAA==.Djshaolin:BAAANQAECgQICAAAAA==.Djzhadow:BAAANQAECgQICAAAAA==.Djzhadruid:BAAANQAECgMIBwAAAA==.',
Dk='Dkshadow:BAAANQAECgUICgAAAA==.',
Do='Doofuss:BAAANQABCgIIAgAAAA==.',
Dr='Dragonchalk:BAAANQADCgYIBgABNQAFFAkJHQAQAIsgAA==.Drakhadir:BAAANQAECgUIBgAAAA==.Drakmon:BAAANQADCggIFQAAAA==.Draktând:BAABNQAECn84AAMYAAoKHBkjOAAbAgAYAAoKHBkjOAAbAgAZAAEK5gXjpQAwAAAAAA==.Dreve:BAAANQABCgIIBAAAAA==.Driftier:BAAANQAECgYICQAAAA==.Drogon:BAEANQAECggIDgABNQAFFAQIBgAhAGYiAA==.Drunkenpanda:BAABNQAECn8eAAMGAAoK5A3bHgCdAQAGAAoK5A3bHgCdAQAiAAEKAADhewAXAAAAAA==.',
Du='Duneshadow:BAAANQADCgUICQAAAA==.',
Ec='Echö:BAEBNQAECn9PAAIUAAoKTxi+GABQAgAUAAoKTxi+GABQAgAAAA==.',
Eg='Egamnilbog:BAAANQAECgQIBgAAAA==.',
Ei='Eirø:BAAANQAECgUICAABNQAFFAcIDgAOAE8UAA==.',
El='Elberon:BAAANQAECgIIBAABNQAECggIEQABAAAAAA==.Eljer:BAAANQADCgMIAwAAAA==.Ellspeth:BAAANQAECggIAgAAAA==.Elnax:BAAANQAECgEIAwAAAA==.Elöhim:BAAANQAECggIBgAAAA==.',
En='Enæmberclad:BAAANQAECgQIBQAAAA==.',
Ep='Epic:BAAANQADCgYICQAAAA==.',
Eq='Eqo:BAAANQAECgUIBQAAAA==.',
Er='Erebosa:BAAANQABCgQIBAAAAA==.Eriam:BAAANQAECgYICgABNQAECgoKRQARAKQTAA==.',
Fa='Fallden:BAAANQAECgMIAwABNQAECgoKJwAXAEoWAA==.Fatherchill:BAABNQAECn8dAAIcAAgKhRdSIQDZAQAcAAgKhRdSIQDZAQAAAA==.Fathermoses:BAABNQAECn8iAAIXAAoKcAdGJwBKAQAXAAoKcAdGJwBKAQAAAA==.',
Fi='Fitco:BAAANQAECgQIBQAAAA==.',
Fl='Flokii:BAAANQADCgEIAQAAAA==.Floppy:BAAANQADCgMIAwAAAA==.',
Fr='Frantecks:BAAANQAECgYIBgAAAA==.Freela:BAEANQAECgYICAABNQAECgkJLAAFAIUdAA==.Frost:BAAANQAECgIJAgABNQAFFAgIFgAjAJ8SAA==.Frostmon:BAABNQAECn9LAAIHAAoKpiD8CwC3AgAHAAoKpiD8CwC3AgAAAA==.Frostyaf:BAAANQADCgIIAgAAAA==.',
Fu='Furbee:BAAANQAECggIBgAAAA==.',
Ga='Galeandra:BAABNQAECn8ZAAIXAAoKXwWZKwApAQAXAAoKXwWZKwApAQAAAA==.Gambas:BAAANQAECgQIAwAAAA==.Garim:BAABNQAECn8iAAIQAAkKVg0lGgDBAQAQAAkKVg0lGgDBAQAAAA==.Gaztingo:BAABNQAECn8tAAMgAAoKhQ5fXADNAQAgAAoKhQ5fXADNAQAXAAIKcAK2dAA9AAAAAA==.',
Gh='Ghostbanri:BAAANQABCgcICAAAAA==.',
Gi='Gildor:BAAANQAECgEIAQAAAA==.Giox:BAAANQADCgMIAwAAAA==.Girthshock:BAAANQADCgcIBwABNQAECgcIEAABAAAAAA==.',
Gn='Gnar:BAAANQADCgcICAAAAA==.',
Go='Gobi:BAABNQAECn8nAAIkAAoKfRyiQgBFAgAkAAoKfRyiQgBFAgAAAA==.Gowtherpunch:BAACNQAFFH8FAAIlAAIKPAvhBwBxAAAlAAIKPAvhBwBxAAA1AAQKf1AAAiUACgowExUIANsBACUACgowExUIANsBAAAA.',
Gr='Gravewynd:BAAANQADCggIDwAAAA==.Grimsy:BAABNQAECn8nAAIMAAoKBRccQgA7AgAMAAoKBRccQgA7AgAAAA==.Grogg:BAAANQADCgUIBQAAAA==.Gruxxiron:BAAANQAECgQIBgABNQAECgoKLQADAKsSAA==.',
Gu='Guerriero:BAAANQAECgUIBgABNQAECgoKIgADAK0JAA==.Gulnn:BAABNQAECn8xAAQeAAoKHhu/QwAKAgAeAAkKVBu/QwAKAgAfAAIKYxaMHwBxAAANAAEKAAA4MAA1AAAAAA==.Gumby:BAAANQABCgQIBAAAAA==.',
Ha='Haelena:BAAANQAECgUICgAAAA==.Hage:BAAANQAECggIBAAAAA==.Harmossy:BAAANQAECgUIDgAAAA==.',
He='Heartsfang:BAAANQADCgMIBAAAAA==.Heriotza:BAABNQAECn8iAAMDAAoKrQnMRAAqAQADAAkKuAnMRAAqAQAHAAcKnAXwgQAWAQAAAA==.',
Ho='Hogmaine:BAAANQADCgUICQAAAA==.Holypaladin:BAABNQAECn8gAAIeAAcK+BkmhwDUAQAeAAcK+BkmhwDUAQAAAA==.',
Ib='Ibrakeforimp:BAAANQAECggIAQAAAA==.',
Ii='Iimit:BAABNQAECn8eAAIYAAkKGBZtSgDXAQAYAAkKGBZtSgDXAQABNQAECgoKLwAdAKYdAA==.',
Il='Illidead:BAACNQAFFH8eAAMkAAgKwCDFBQBnAgAkAAcKpiHFBQBnAgAdAAEKQRylDgBWAAA1AAQKf0MAAyQACgphJSYdAM0CACQACQpvJSYdAM0CAB0AAQr6JMo0AFkAAAAA.Illooj:BAACNQAFFH8PAAIgAAcKYiQ3DgCrAQAgAAcKYiQ3DgCrAQA1AAQKf1UAAyAACgqYJqAAAFUEACAACgqXJqAAAFUEAAQACArFJVwBAEQDAAAA.Ilwen:BAAANQAECgUIBAAAAA==.',
In='Indexes:BAABNQAECn8XAAMRAAYK7wtLVgDGAAARAAYK7wtLVgDGAAAKAAEKPggGggAgAAAAAA==.Inspiration:BAAANQADCgQICwAAAA==.',
Is='Ist:BAACNQAFFH8JAAIbAAIKowseBQBZAAAbAAIKowseBQBZAAA1AAQKfzMAAhsACgo6FcsNAOEBABsACgo6FcsNAOEBAAAA.',
It='Itchigo:BAAANQAECgUIBgAAAA==.Itskamertime:BAAANQAECgIIAQABNQAFFAIIBQARABYPAA==.',
Iv='Ivgorod:BAABNQAECn8ZAAIJAAkKZQXgEgAJAQAJAAkKZQXgEgAJAQAAAA==.',
Ja='Jabbadahut:BAAANQAECggIBgAAAA==.Jarhead:BAABNQAECn8fAAIfAAgK6wiwDAD1AAAfAAgK6wiwDAD1AAAAAA==.Jaxtoy:BAAANQADCgYIBgAAAA==.Jaybas:BAAANQABCgIIAgAAAA==.Jazienne:BAAANQAECgQIBwAAAA==.Jazilyne:BAAANQAECgEIAQABNQAECgQIBwABAAAAAA==.Jaziriel:BAAANQADCgYIBgAAAA==.',
Je='Jenka:BAAANQAECgMIAwAAAA==.',
Jo='Joleya:BAAANQADCgYICwAAAA==.',
Ju='Judihopps:BAAANQAECgIIAwAAAA==.Justcalmdown:BAAANQAECgYIDgABNQAECgIIAgABAAAAAA==.Justyra:BAAANQAECgQICAABNQAECgoKJgATAN4ZAA==.',
Ka='Kalder:BAAANQADCgIJAgABNQAECgYICQABAAAAAA==.Kalloo:BAAANQAECgYIBgABNQAFFAcIDwAgAGIkAA==.Kambative:BAACNQAFFH8FAAMRAAIKFg9WGwCRAAARAAIKFg9WGwCRAAAKAAIKkA6TEgB4AAA1AAQKf1EAAxEACgq4HmQNANACABEACgq4HmQNANACAAoABQqYFc9FAAEBAAAA.Kambustable:BAAANQADCggICwABNQAFFAIIBQARABYPAA==.Kammunion:BAAANQAECgcICQABNQAFFAIIBQARABYPAA==.Kamscendance:BAAANQADCggICgABNQAFFAIIBQARABYPAA==.Kanan:BAAANQADCggIFQAAAA==.Kandosii:BAAANQABCgIIAgAAAA==.Kantheal:BAABNQAECn8dAAMaAAkKJRcMTgDcAQAaAAkKJRcMTgDcAQAcAAEKAAAadQAoAAAAAA==.',
Ke='Keirmania:BAAANQADCgcIBwAAAA==.Kekkan:BAAANQAECgQIBAAAAA==.',
Ki='Kiagas:BAACNQAFFH8JAAIMAAQKrgfxIQCzAAAMAAQKrgfxIQCzAAA1AAQKfyUAAxYACgqNDz0YABwBAAwACgoGD6uZANwBABYABgq/CT0YABwBAAE1AAQKAggCAAEAAAAA.Kimbrawly:BAAANQADCgYIBgAAAA==.',
Kr='Kravex:BAABNQAECn9FAAIRAAoKpBMsIgDrAQARAAoKpBMsIgDrAQAAAA==.Kreynar:BAAANQAECgQJBAABNQAECgoKRQARAKQTAA==.Krrayt:BAAANQAECgQICwAAAA==.',
Ku='Kukoc:BAAANQAECgcIEgAAAA==.',
Ky='Kylana:BAAANQADCgYICwABNQAECgoKMgAKANESAA==.Kyriel:BAABNQAECn85AAIhAAoKlh2NIQCzAgAhAAoKlh2NIQCzAgAAAA==.',
['Ké']='Kélly:BAAANQAECggICAAAAA==.',
La='Laayna:BAABNQAECn8VAAIPAAcKFA9EqwA9AQAPAAcKFA9EqwA9AQAAAA==.Lanta:BAAANQAECggIEQAAAA==.Larayvia:BAACNQAFFH8GAAIFAAMKuAIWIACgAAAFAAMKuAIWIACgAAA1AAQKfykAAgUACgpoC6SQAOgBAAUACgpoC6SQAOgBAAAA.',
Le='Leesala:BAABNQAECn8/AAIhAAoKzBo5JQCcAgAhAAoKzBo5JQCcAgAAAA==.Leiman:BAAANQAECgQIDAAAAA==.Leymonte:BAAANQADCgMIAwAAAA==.',
Lg='Lg:BAABNQAECn8+AAMZAAkKWCLvCgAyAwAZAAkK1x7vCgAyAwAYAAgKeR57IQCFAgABNQAECgIIAgABAAAAAA==.',
Li='Lic:BAABNQAECn8oAAIFAAoKbhGrVAAiAgAFAAoKbhGrVAAiAgAAAA==.Lilbitty:BAAANQADCgEIAQAAAA==.Lilililil:BAABNQAECn8yAAMPAAoK4xqBJgBMAgAPAAoK4xqBJgBMAgAhAAIKkBFR2ABmAAAAAA==.Lillabet:BAAANQAECgQIDwAAAA==.Lilpoo:BAACNQAFFH8GAAIFAAMKUQxtFgDeAAAFAAMKUQxtFgDeAAA1AAQKfxwAAgUACQrxEXRSACgCAAUACQrxEXRSACgCAAAA.Limpydk:BAAANQADCgUIBQABNQAECgcIEAABAAAAAA==.Limpylock:BAAANQAECgYIDQABNQAECgcIEAABAAAAAA==.Limpypal:BAAANQAECgcIEAAAAA==.Lispeth:BAABNQAECn8qAAQTAAgKxwmIMgAFAQATAAgKxwmIMgAFAQAUAAEKAADZmwAnAAAbAAIKoAT2NwAfAAAAAA==.',
Lo='Lockém:BAAANQABCgYIBwAAAA==.Longtrang:BAAANQADCgMIAwAAAA==.Loriander:BAAANQADCgQIBAAAAA==.',
Lu='Luckyleaf:BAAANQAECgUIBAAAAA==.Lunaaris:BAAANQAECggIEQAAAA==.',
Ma='Macallan:BAAANQAECgQIBwAAAA==.Magifur:BAABNQAECn8cAAIkAAgKABITzADuAQAkAAgKABITzADuAQAAAA==.Magnakilro:BAABNQAECn8zAAIFAAgKwxWJfgAQAgAFAAgKwxWJfgAQAgAAAA==.Magnomar:BAAANQADCgcIDQAAAA==.Maisy:BAAANQADCgUIBwAAAA==.Malditto:BAAANQADCgIIAgAAAA==.Maleficus:BAABNQAECn8ZAAIfAAYKuwm1FgCnAAAfAAYKuwm1FgCnAAAAAA==.Mamoswine:BAAANQABCgcICgAAAA==.Mareki:BAAANQADCggIDQAAAA==.Markdfordeth:BAAANQADCgcIBwAAAA==.Mattyfu:BAAANQAECgYIDQAAAA==.Maxrogue:BAAANQADCgUIBQABNQAECgkJKAALALUNAA==.Mazikeen:BAABNQAECn8XAAIfAAgKoA88DQDrAAAfAAgKoA88DQDrAAAAAA==.',
Me='Meatsupreme:BAACNQAFFH8IAAICAAIKuQu9JwB9AAACAAIKuQu9JwB9AAA1AAQKfysAAgIACgrWE++kANcBAAIACgrWE++kANcBAAAA.Meepin:BAABNQAECn83AAQaAAoKTh7OOgB5AgAaAAkKlB3OOgB5AgACAAgKBRNsoQDeAQAcAAgKHArPMgDrAAAAAA==.Merdoc:BAAANQAECgUIBwAAAA==.Mesophistole:BAAANQADCgUIDQABNQAECgUIDwABAAAAAA==.Mesopunchy:BAAANQAECgUIDwAAAA==.Mesopyro:BAAANQADCgMIBgABNQAECgUIDwABAAAAAA==.',
Mi='Miamore:BAAANQADCggICAAAAA==.Microchyp:BAAANQADCgEIAQAAAA==.Mileenä:BAAANQAECggIBgAAAA==.Milemarker:BAABNQAECn8VAAIaAAgK2QZIiwB6AQAaAAgK2QZIiwB6AQAAAA==.Mindstorm:BAAANQADCggICAAAAA==.Misstwizted:BAABNQAECn8XAAMeAAcKfwTK1wAaAQAeAAcKfgTK1wAaAQANAAIK5AEZKwBBAAAAAA==.',
Mo='Mohinu:BAAANQAECgcIDwAAAA==.Mojodaemon:BAAANQADCgUIBQAAAA==.Molag:BAAANQAECgIIAgAAAA==.Moocowmoo:BAAANQADCggIDgABNQAECggIIAAeAPgZAA==.Moondevil:BAAANQADCgYIDQAAAA==.Morta:BAEBNQAECn8sAAIFAAkKhR2/TQAzAgAFAAkKhR2/TQAzAgAAAA==.Mortkavaliro:BAAANQADCgYIBgABNQAECgoKIgADAK0JAA==.',
Mu='Mugzy:BAAANQAECggIDwAAAA==.Muted:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.',
['Mö']='Mörph:BAAANQAECgMIAwABNQAECgkJHAAaAEobAA==.',
['Mø']='Møde:BAAANQADCggICwABNQAECgoKSwAkANMLAA==.',
Na='Nanérs:BAAANQAECgUIBgABNQAFFAYIEQARAGgcAA==.Narrodus:BAABNQAECn8YAAIbAAoK0x0PBQB9AgAbAAoK0x0PBQB9AgAAAA==.Nasht:BAAANQADCggICQAAAA==.Nasun:BAAANQADCgQIBAAAAA==.Nataku:BAABNQAECn8YAAIRAAcKswj7ZQA1AQARAAcKswj7ZQA1AQAAAA==.',
Ne='Neelix:BAAANQAECgEIAQAAAA==.Nezzick:BAABNQAECn89AAMPAAoKvxejOwCHAgAPAAoKvxejOwCHAgAhAAgK2AsplgBQAQAAAA==.',
Ni='Nicholasrage:BAAANQABCgQIBAAAAA==.Nidalap:BAAANQADCgEIAQAAAA==.Nightreaper:BAAANQADCggIQQAAAA==.Nightsinger:BAAANQAECgIIAQAAAA==.Nikkohan:BAAANQAECgQIBAAAAA==.Nimbus:BAACNQAFFH8bAAMPAAcKPBccAwB6AgAPAAcKPBccAwB6AgAhAAEKXgHEKwBGAAA1AAQKf9IAAg8ACgqlJvkAAPkDAA8ACgqlJvkAAPkDAAAA.Nixy:BAAANQAECggIDQAAAA==.',
No='Nomns:BAABNQAECn8sAAIFAAoK8SCmFQDyAgAFAAoK8SCmFQDyAgAAAA==.Normel:BAAANQAECgEIAQAAAA==.Noz:BAAANQAECgIIBAABNQAECggIGwACACwfAA==.',
Nr='Nrvous:BAAANQADCgIIAgAAAA==.',
Nu='Nuid:BAAANQAECggICQAAAA==.Numbers:BAABNQAECn8iAAITAAoKbhRVGQDlAQATAAoKbhRVGQDlAQAAAA==.',
Ny='Nytesage:BAACNQAFFH8SAAImAAcKmiMuAACsAQAmAAcKmiMuAACsAQA1AAQKfycAAiYACQqKJikAANoDACYACQqKJikAANoDAAAA.',
['Nä']='Näners:BAAANQAECgIIAQABNQAFFAYIEQARAGgcAA==.',
['Në']='Nëvërmind:BAABNQAECn89AAIcAAoKuh6MDQBUAgAcAAoKuh6MDQBUAgAAAA==.',
['Nì']='Nìghtcat:BAAANQAECgYIDAAAAA==.',
Or='Orgrom:BAAANQAECggICAAAAA==.',
Oz='Ozgar:BAABNQAECn8YAAMXAAcK4xUAJQBcAQAXAAcK4xUAJQBcAQAEAAEKkAgeLgApAAAAAA==.Ozo:BAAANQADCgIIAgAAAA==.',
Pa='Painavolian:BAABNQAECn9RAAIkAAoKGCCQMQAoAwAkAAoKGCCQMQAoAwAAAA==.Palcris:BAAANQADCgcIBwAAAA==.Paxren:BAAANQABCgIIAgAAAA==.',
Pe='Peeches:BAAANQAECgYIBQAAAA==.Pelonis:BAAANQADCgYICgAAAA==.Penthesilea:BAAANQAECgUICAAAAA==.',
Ph='Pheayre:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Phoenixdówn:BAABNQAECn82AAIhAAkKySJ+EwAcAwAhAAkKySJ+EwAcAwAAAA==.Phoosa:BAAANQADCgEIAQAAAA==.',
Pi='Pingpong:BAABNQAECn8zAAQiAAoKwhhuIAAqAgAiAAoKwhhuIAAqAgAlAAcKUw6IDwAsAQAGAAEKBQOtVAAgAAAAAA==.Pisspadpanda:BAABNQAECn85AAMeAAoKWhzLPgAaAgAeAAoK2RvLPgAaAgANAAQKWBXBEwAPAQAAAA==.',
Pl='Plungsnipes:BAAANQADCggIFAABNQAECggICQABAAAAAA==.',
Po='Poggies:BAACNQAFFH8PAAMmAAcKtCA5AACCAQAkAAYKfSBpFgDEAQAmAAQKvhs5AACCAQA1AAQKfxsAAyYACgpcJVABAMECACQACgpuJIQyACYDACYACAojI1ABAMECAAAA.Potatodh:BAAANQAECgEIAgAAAA==.Potatolock:BAABNQAECn8ZAAQeAAkKuRNYXwC3AQAeAAkK5xJYXwC3AQANAAQKRw00FAAIAQAfAAIKPhRsNQA8AAAAAA==.',
Pr='Praynes:BAACNQAFFH8FAAIgAAIKgQYILwBvAAAgAAIKgQYILwBvAAA1AAQKf00AAiAACgqVHOsuAIkCACAACgqVHOsuAIkCAAAA.',
Pu='Pupperputh:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Puppet:BAAANQADCgEIAQAAAA==.',
Py='Pylanora:BAAANQADCgMIAwAAAA==.',
Qu='Quinnx:BAAANQADCgYIBwAAAA==.',
Ra='Rach:BAABNQAECn85AAIFAAoKRxtpNgBwAgAFAAoKRxtpNgBwAgAAAA==.Rael:BAAANQADCgIJAgAAAA==.Ranoe:BAAANQAECgIIAwABNQAECgoKLwAdAKYdAA==.Rathalos:BAAANQABCgIIAgAAAA==.Raxity:BAABNQAECn8fAAIgAAoKBBpHKQCnAgAgAAoKBBpHKQCnAgAAAA==.Raxxity:BAAANQAECggICwAAAA==.Razji:BAABNQAECn8vAAMOAAoKRByAGgCBAgAOAAgKJSCAGgCBAgAFAAUK8xa68wAaAQAAAA==.',
Re='Redmg:BAAANQADCgUIDQABNQAECgMIAwABAAAAAA==.Renfro:BAAANQADCgMIAwAAAA==.',
Ri='Riete:BAABNQAECn8pAAINAAkKcRLECQDjAQANAAkKcRLECQDjAQAAAA==.Rinoa:BAABNQAECn9LAAIkAAoK0wtycwDJAQAkAAoK0wtycwDJAQAAAA==.',
Ro='Rochallie:BAAANQAECgUIDwAAAA==.Rockii:BAAANQADCgYIBgAAAA==.Rocknwolf:BAABNQAECn8fAAISAAoK7wczHgAWAQASAAoK7wczHgAWAQAAAA==.Rokd:BAABNQAECn8jAAIcAAkKHyHwCAAOAwAcAAkKHyHwCAAOAwAAAA==.Rosalee:BAEANQABCgIIAgABNQAECgcIEgABAAAAAA==.Roscoelock:BAABNQAECn8WAAMfAAcKfhZ1IABtAQAfAAUK4Rt1IABtAQAeAAUKEwzV9gDdAAAAAA==.Roxxann:BAAANQADCgYIBgAAAA==.',
Ru='Ruibaron:BAAANQAECgUIBgAAAA==.Rumur:BAAANQADCgYIBgABNQAECgoKLQAHAN4MAA==.',
['Rà']='Ràidèn:BAAANQADCgcIBwABNQAECgoKQQAhANkfAA==.',
['Rá']='Ráyne:BAAANQAECgEIAQAAAA==.',
Sa='Sadeel:BAABNQAECn9PAAMNAAoKaRWhBgAFAgANAAoKPBWhBgAFAgAeAAcKlAxtsgBrAQAAAA==.Sadewolf:BAABNQAECn8lAAMTAAoKKyD3FAC+AgATAAkK2SH3FAC+AgAUAAQKHxK9TgDrAAAAAA==.Salvadore:BAAANQADCggICAAAAA==.Samentoni:BAACNQAFFH8JAAIaAAMKuBIqHQCYAAAaAAMKuBIqHQCYAAA1AAQKfy8AAhoACgpAGrJAAGICABoACgpAGrJAAGICAAAA.Samgal:BAAANQAECgYIEQAAAA==.Sampsyn:BAAANQABCgYICgAAAA==.Sanctalux:BAAANQADCgQICQAAAA==.Sansura:BAAANQAECggICQABNQAECgoKWgAPAG0TAA==.Sasha:BAAANQAECgMICAAAAA==.Satyra:BAABNQAECn8mAAITAAoK3hmLGQDjAQATAAoK3hmLGQDjAQAAAA==.Saurphang:BAACNQAFFH8SAAMHAAUKrho3BgD8AAAHAAQKrho3BgD8AAADAAEKAABvPgAWAAA1AAQKfz0AAgcACgp/IVUPADwDAAcACgp/IVUPADwDAAAA.',
Sc='Scamanes:BAAANQAECgYIDAAAAA==.',
Se='Seluun:BAAANQAECgMIBAAAAA==.Semperfi:BAAANQABCgYICQAAAA==.Severis:BAAANQADCgEIAQAAAA==.',
Sh='Shadora:BAABNQAECn8ZAAIXAAkK8xHQFQAEAgAXAAkK8xHQFQAEAgAAAA==.Shadowwizard:BAABNQAECn9PAAIfAAoKZxDQBgBvAQAfAAoKZxDQBgBvAQAAAA==.Shadybrat:BAAANQAECgcICAABNQAECgoKOgAFAPgPAA==.Shaladin:BAAANQAECggIEAAAAA==.Shidan:BAABNQAECn9BAAIhAAoK2R83HAD9AgAhAAoK2R83HAD9AgAAAA==.Shmeepin:BAAANQAECgIIAgAAAA==.Shockaho:BAAANQAECgUIBwAAAA==.Shockchalk:BAACNQAFFH8dAAIQAAkKiyAyAADNAgAQAAkKiyAyAADNAgA1AAQKf1MAAhAACgrvJhYAAJwDABAACgrvJhYAAJwDAAAA.Shocknorris:BAAANQAECgIIBAABNQAECgQIBQABAAAAAA==.Shortcircuit:BAAANQADCgUIBQABNQAECgQIBQABAAAAAA==.Shrooclaw:BAAANQAECgIIAgAAAA==.Shulk:BAABNQAECn8UAAICAAgK9QsUvwCeAQACAAgK9QsUvwCeAQAAAA==.',
Si='Sibbiah:BAEANQAECgcIEgAAAQ==.Silanre:BAABNQAECn8pAAMkAAkKcg8ItwA3AQAkAAcKTREItwA3AQAdAAIKzgo3MABrAAAAAA==.',
Sk='Skaðï:BAACNQAFFH8OAAIOAAcKTxRsDQBnAQAOAAcKTxRsDQBnAQA1AAQKf2AABA4ACgpZI3UEAA4DAA4ACgpZI3UEAA4DAAUAAwrQAI9AAWEAACcAAQolDBEUADwAAAAA.',
Sl='Slizzard:BAAANQADCgIIAgABNQAFFAcIEQAHALoQAA==.',
Sm='Smalldrogø:BAAANQADCggICAAAAA==.',
Sp='Spadesrage:BAABNQAECn8eAAMaAAgKpB+CNgBCAgAaAAcK1B6CNgBCAgACAAEKkwi9qwEnAAAAAA==.Spadestree:BAAANQADCgYICgAAAA==.Spash:BAAANQADCggIEAAAAA==.Spicyycurryy:BAABNQAECn8jAAIMAAgKPBmcggAVAgAMAAgKPBmcggAVAgAAAA==.',
St='Staticshock:BAAANQADCgUICAABNQAECggICQABAAAAAA==.Stepdruid:BAAANQAECgEIAQAAAA==.Strahm:BAABNQAECn8oAAILAAkKtQ0cLgAgAQALAAkKtQ0cLgAgAQAAAA==.Strehm:BAAANQADCgYIDAABNQAECgkJKAALALUNAA==.Stryhm:BAAANQADCgQIBwABNQAECgkJKAALALUNAA==.',
Su='Sulfass:BAAANQABCgIIAgAAAA==.Supërman:BAAANQABCgcICQAAAA==.Surai:BAABNQAECn8cAAIhAAkK2yB2DwBIAwAhAAkK2yB2DwBIAwABNQAFFAYICAAYANALAA==.',
Sy='Sylryn:BAAANQADCgQIBAAAAA==.Sylvexa:BAAANQAECgQIBwAAAA==.Symple:BAAANQAECgEIAgABNQAECgQIBAABAAAAAA==.Syns:BAAANQAECgIIAgAAAA==.Synz:BAAANQAECgIIAgAAAA==.Syssare:BAABNQAECn8cAAIUAAgKrx0zMAAmAgAUAAgKrx0zMAAmAgAAAA==.',
Ta='Tacpally:BAAANQADCgYIFQAAAA==.Talamor:BAAANQADCgMJAwAAAA==.Talasam:BAAANQADCgQIBAAAAA==.Talisman:BAAANQADCggICAAAAA==.Tandsonnara:BAAANQAECggIAQAAAA==.Tastetickle:BAACNQAFFH8FAAIkAAIKsRJKNwCWAAAkAAIKsRJKNwCWAAA1AAQKf00AAiQACgrlHeooAJsCACQACgrlHeooAJsCAAAA.Tazdrin:BAACNQAFFH8FAAIoAAIK7QchAQB6AAAoAAIK7QchAQB6AAA1AAQKf1EAAigACgq0F9cBAFACACgACgq0F9cBAFACAAAA.Taze:BAABNQAECn8YAAQRAAgKrB5FHAAjAgARAAgKrB5FHAAjAgAKAAMK2By3VAC1AAALAAMKRg1AZgBGAAAAAA==.',
Te='Telidrus:BAACNQAFFH8GAAMdAAMK2REvCQCMAAAkAAMKlg9AOwDXAAAdAAIKxg8vCQCMAAA1AAQKfyQABB0ACQqpIC8MAPkBACQACAp6HdCaAEsCAB0ABwpBHi8MAPkBACYAAgroDlMJAHUAAAAA.Teneturadvys:BAAANQADCgQIBAABNQAECggIBwABAAAAAA==.Terrax:BAAANQADCgQIBAAAAA==.',
Th='Thepoacher:BAABNQAECn8aAAIFAAkK4Bb4NgBvAgAFAAkK4Bb4NgBvAgABNQAECgkKGgAFAOAWAA==.Thicc:BAAANQABCgQIBAAAAA==.Thicchunter:BAABNQAECn9MAAIOAAoKSiFCCwAkAwAOAAoKSiFCCwAkAwAAAA==.Thiccmage:BAABNQAECn8YAAIkAAgKXxFNfgCuAQAkAAgKXxFNfgCuAQAAAA==.Thiccwiggy:BAAANQADCgMIAwABNQAECgYIDQABAAAAAA==.Thuk:BAABNQAECn8WAAMVAAkKEhAdFwBXAQAVAAcKahMdFwBXAQAMAAgKYAgR2wA3AQAAAA==.Thukwarlock:BAAANQADCgEIAQAAAA==.Thunderbug:BAAANQADCggICAAAAA==.',
To='Topaze:BAABNQAECn8cAAMaAAkKShuzKADFAgAaAAkKShuzKADFAgAcAAEKAAAcdgAnAAAAAA==.Totemmonster:BAAANQABCgIIAgAAAA==.',
Tr='Trancendantx:BAAANQAECgEIAQAAAA==.Tripx:BAACNQAFFH8aAAMCAAcKVxCFDACCAQACAAYKRhCFDACCAQAcAAEKnRDADwBEAAA1AAQKfzgAAwIACgrDH94kAM0CAAIACgrDH94kAM0CABwAAQoAABd9AAAAAAAA.Tripxed:BAABNQAECn8/AAMRAAoKUBoYHwDSAgARAAoKUBoYHwDSAgASAAEKWgqVQAA5AAABNQAFFAcIGgACAFcQAA==.Trishan:BAAANQAECgQIBwAAAA==.Trolk:BAAANQADCgUIBwAAAA==.Tronklock:BAAANQADCgEIAQAAAA==.Tronko:BAABNQAECn8uAAMhAAoK/xiRHwDAAgAhAAoK/xiRHwDAAgAPAAEKNgOnQgEtAAAAAA==.Truthjustice:BAAANQADCggIEgAAAA==.',
Tu='Tullip:BAAANQAECgEIAgAAAA==.Turntsnaco:BAABNQAECn9IAAMYAAoK/BwnEgBhAgAYAAkKcx0nEgBhAgAZAAYKQBVOZQAeAQAAAA==.Turyon:BAAANQADCgEIAQAAAA==.',
Tw='Twiztedfaith:BAAANQADCgYIBgAAAA==.',
Tz='Tzifora:BAEANQAECgEIAQABNQAECgcIEgABAAAAAA==.',
Ul='Ulhume:BAAANQADCgEJAQABNQAECgoKRQARAKQTAA==.',
Un='Unafhaen:BAAANQADCgQIBAAAAA==.Unaverse:BAAANQAECgUICQAAAA==.',
Ur='Urp:BAAANQAECgUIDwAAAA==.',
Us='Usmc:BAAANQAECgYIBQAAAA==.Usmccpl:BAAANQADCgYICQAAAA==.',
Va='Valengarde:BAABNQAECn8aAAICAAoKVBdGjgAIAgACAAoKVBdGjgAIAgAAAA==.Valentin:BAAANQABCgIIAgAAAA==.Valhalia:BAAANQABCgIIAgAAAA==.Vanderneuker:BAAANQAECgQIBwABNQAFFAcIEQAHALoQAA==.Vanero:BAAANQAECgUIBgAAAA==.Vangoon:BAEBNQAECn81AAMZAAoKXSAsCQBHAwAZAAkKJSEsCQBHAwAYAAgKPxlzTQDMAQAAAA==.Vanmonk:BAAANQAECggIDAAAAA==.Vann:BAAANQADCgQIBwAAAA==.Vannix:BAABNQAECn9OAAIXAAoKySSuAgBaAwAXAAoKySSuAgBaAwAAAA==.',
Ve='Veldrys:BAAANQAECgUIBQABNQAECgoKRQARAKQTAA==.Velkanos:BAAANQADCgQIBAAAAA==.Velkhaz:BAAANQABCgYIBgAAAA==.Vereena:BAAANQAECgUIDgAAAA==.Vesstar:BAAANQABCggIFwAAAA==.',
Vi='Vigo:BAABNQAECn8cAAIFAAoKEBHMUAArAgAFAAoKEBHMUAArAgAAAA==.Violet:BAAANQADCgMIAwAAAA==.Virmethir:BAABNQAECn8dAAIJAAYKiBdIGwCVAQAJAAYKiBdIGwCVAQAAAA==.',
Vo='Voltaren:BAAANQAECgIJAgAAAA==.',
Wa='Waq:BAAANQADCgcIBwAAAA==.Wasabii:BAAANQAECgMIBAAAAA==.',
Wh='Whtmg:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.',
Wi='Winterbreeze:BAAANQADCgQICgAAAA==.Wiwi:BAACNQAFFH8RAAMHAAcKuhCDEQDyAAAHAAQKQhGDEQDyAAAjAAQK2xAJFQChAAA1AAQKf1kAAyMACgrZIzoSAL0CACMACQqMIzoSAL0CAAcACAqqG7ZMAOIBAAAA.',
Wo='Woopie:BAAANQAECgIIAQAAAA==.',
Wu='Wukøng:BAAANQABCgIIAgAAAA==.',
Xa='Xake:BAAANQAECgUICgAAAA==.Xares:BAABNQAECn8vAAMdAAoKph2gCABUAgAdAAoKph2gCABUAgAkAAYKiw0kIAFWAQAAAA==.',
Xe='Xenp:BAABNQAECn9DAAMcAAoKZRknDwA3AgAcAAoKZRknDwA3AgACAAUKmwoOOwHBAAAAAA==.',
Xi='Xiovemm:BAAANQADCgcIBQAAAA==.',
Xu='Xuri:BAABNQAECn8cAAIFAAkKLAxjkADoAQAFAAkKLAxjkADoAQAAAA==.',
Ya='Yalda:BAAANQADCgIIAgAAAA==.',
Yd='Ydriel:BAAANQADCgUIBwAAAA==.',
['Yö']='Yöurfired:BAAANQADCgQICAAAAA==.',
Za='Zake:BAABNQAECn9DAAIFAAoKMR2iKwDrAgAFAAoKMR2iKwDrAgAAAA==.Zalileina:BAAANQADCgMIAgAAAA==.Zantanna:BAAANQAECgMIAgAAAA==.Zappythile:BAABNQAECn80AAMhAAoKwyB5KADCAgAhAAoKwyB5KADCAgAPAAEKAACJQwEsAAAAAA==.',
Ze='Zealdavir:BAAANQABCgIIAgAAAA==.Zenà:BAAANQAECgEIAQAAAA==.',
Zi='Zigzagoon:BAAANQABCgYIBgAAAA==.',
Zo='Zoz:BAABNQAECn8gAAIdAAoKDQtTEgBpAQAdAAoKDQtTEgBpAQAAAA==.',
Zu='Zulfrik:BAABNQAECn8yAAMkAAoKkBWIdADGAQAkAAoKXROIdADGAQAdAAIKEh2DMwBsAAAAAA==.',
Zy='Zyzy:BAAANQAECgcICQABNQAFFAgIHwAXADoZAA==.',
['Äh']='Ählis:BAAANQAECgIIAwAAAA==.',
['ße']='ßeef:BAAANQAECggIEgAAAA==.',
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
