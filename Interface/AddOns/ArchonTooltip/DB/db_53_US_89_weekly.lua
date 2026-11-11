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

local lookup = {'Unknown-Unknown','Paladin-Retribution','DeathKnight-Blood','Priest-Discipline','Hunter-BeastMastery','Monk-Mistweaver','DeathKnight-Unholy','Evoker-Augmentation','Evoker-Devastation','Druid-Restoration','Druid-Guardian','Warrior-Arms','Hunter-Marksmanship','Shaman-Elemental','Shaman-Enhancement','Druid-Balance','Druid-Feral','DemonHunter-Devourer','DemonHunter-Havoc','Warrior-Protection','Warrior-Fury','Priest-Shadow','Rogue-Subtlety','Rogue-Assassination','Paladin-Holy','DemonHunter-Vengeance','Paladin-Protection','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Priest-Holy','Shaman-Restoration','Monk-Windwalker','DeathKnight-Frost','Mage-Arcane','Monk-Brewmaster','Mage-Frost','Mage-Fire','Hunter-Survival','Rogue-Outlaw',}
local provider = {region='US',realm='Eonar',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abysseus:BAAANQADCgcIDwAAAA==.',
Ad='Admired:BAAANQAECgEIAwABNQAECgUIDAABAAAAAA==.',
Ae='Aerdrie:BAAANQABCgMIAwAAAA==.Aevelin:BAACNQAFFH8GAAICAAMKEAZqGgCuAAACAAMKEAZqGgCuAAA1AAQKfxwAAgIACgrDDxGeAOYBAAIACgrDDxGeAOYBAAAA.',
Aj='Ajagar:BAAANQAECgQIBgABNQAECgoKHAADANAIAA==.',
Al='Alamora:BAABNQAECn8VAAIEAAUK6ROcCAAbAQAEAAUK6ROcCAAbAQAAAA==.Alastair:BAAANQAECggIAgAAAA==.Alathena:BAAANQAECgMIBAAAAA==.Albrect:BAAANQADCgYIBgAAAA==.Alexandrya:BAABNQAECn86AAIFAAoK+A93ZwDcAQAFAAoK+A93ZwDcAQAAAA==.Alickdh:BAAANQADCgIIAgABNQAFFAEIAgABAAAAAA==.Almostpanda:BAAANQADCgUIBQABNQAECgoKHgAGAOQNAA==.Altery:BAAANQAECgEIAQAAAA==.',
Am='Ampharos:BAAANQABCgYIBgAAAA==.Amsahunter:BAAANQADCggICAABNQAECggIGAAHAB8OAA==.Amsroeb:BAABNQAECn8YAAMHAAgKHw68OgAaAQAHAAYK5Q28OgAaAQADAAYKRQqCZgCjAAAAAA==.',
An='Anelavenger:BAACNQAFFH8ZAAIIAAYKexeUBACLAQAIAAYKexeUBACLAQA1AAQKf28AAwgACgr4I+gAAK4DAAgACgr4I+gAAK4DAAkABgppDEEjACwBAAAA.Anelblast:BAAANQAECgYIEgABNQAFFAYIGQAIAHsXAA==.Angerwina:BAAANQAECgQIDAAAAA==.Annain:BAAANQAECgEIAQAAAA==.',
Ar='Arathor:BAAANQAECgEIAQAAAA==.Ardent:BAAANQAECgUIDgAAAA==.Ardor:BAAANQADCgYICgABNQAECgUIDgABAAAAAA==.Arent:BAABNQAECn89AAMKAAoKsBL0IAAiAgAKAAoKsBL0IAAiAgALAAcKTQvuLgAFAQAAAA==.Arkanna:BAAANQADCgYIBgAAAA==.Arkhea:BAAANQAECgQIBAAAAA==.Artemislives:BAAANQAECggIDAAAAA==.',
As='Asharia:BAAANQAECgcIEAAAAA==.Ashla:BAAANQADCgIIAgAAAA==.Asilan:BAAANQABCgEIAQAAAA==.Assateague:BAABNQAECn8WAAIMAAUKPQMx+gBuAAAMAAUKPQMx+gBuAAAAAA==.Astelossa:BAAANQADCggIJwAAAA==.',
['Aë']='Aëro:BAAANQAECgEIAgAAAA==.',
Ba='Bahnna:BAAANQADCgUICAAAAA==.Bananapistol:BAAANQABCgIIBAAAAA==.Barracksbuny:BAAANQAECggIEAABNQAECgkJHQADABMUAA==.Barrathfrogy:BAAANQADCgUIDAAAAA==.',
Be='Bebheishel:BAAANQADCgQICwAAAA==.Beefcake:BAAANQADCgYIFQABNQAECgQIBgABAAAAAA==.Bertello:BAAANQAECgQIBAAAAA==.Beserol:BAAANQAECgQICwAAAA==.',
Bi='Biest:BAAANQAECggICAAAAA==.Biggs:BAAANQADCggICQABNQAECggIBgABAAAAAA==.Billy:BAABNQAECn8dAAIGAAgKnxmVGAD0AQAGAAgKnxmVGAD0AQAAAA==.Bilywitchdoc:BAAANQAECgEIBwABNQAECgoKLwANAEQcAA==.Bionicle:BAAANQADCgQIBAAAAA==.Biscuít:BAAANQAECggIEgAAAA==.',
Bk='Bk:BAAANQADCgcIDQABNQAECgoKMgAOAOMaAA==.',
Bl='Blasuoff:BAAANQADCgYIBgAAAA==.Blkmg:BAAANQADCgYIBgABNQAECgMIBAABAAAAAA==.Bloodeagle:BAAANQAECggIEAAAAA==.Bloodyfate:BAAANQAECgEIAQAAAA==.Bluechalk:BAAANQAFFAIIAgABNQAFFAgIHAAPAK8gAA==.',
Bo='Boomslap:BAAANQAECggICgAAAA==.Boredom:BAAANQADCggICAAAAA==.Borzoi:BAABNQAECn9YAAICAAoKTyWFBgBhAwACAAoKTyWFBgBhAwAAAA==.',
Br='Brawne:BAAANQADCgUIBQAAAA==.Brig:BAAANQAECgEIAgAAAA==.',
Bu='Buzzdkt:BAAANQAECgEIAQAAAA==.Buzzdruu:BAABNQAECn8oAAQQAAoKhBzQLgBoAgAQAAoKiRfQLgBoAgARAAcKihduFgBMAQALAAEKryGpVgBcAAAAAA==.Buzzpal:BAAANQAECgUIBQAAAA==.',
['Bó']='Bóg:BAAANQADCgEIAQAAAA==.',
['Bø']='Bønës:BAAANQADCgQIBAAAAA==.',
Ca='Caaniss:BAAANQABCgQIBAAAAA==.Cadeana:BAAANQADCgQIBAAAAA==.Caduceus:BAAANQAECgEIAQAAAA==.Caesus:BAAANQAECgEIAQAAAA==.Cagedancer:BAAANQAECgIIAgAAAA==.Callio:BAABNQAECn8/AAIFAAoKkQ4EVwAFAgAFAAoKkQ4EVwAFAgAAAA==.Canus:BAAANQAECggIDwAAAA==.Caprisunsipz:BAAANQAECggIDQAAAA==.Caritta:BAABNQAECn8UAAMSAAcK/hSpPgBVAQASAAYKSRCpPgBVAQATAAMKqxaubADGAAAAAA==.Cathillex:BAABNQAECn8VAAMUAAgKnhUrFwA+AQAUAAgKnhUrFwA+AQAVAAEKVBHSMQA5AAAAAA==.Caycay:BAACNQAFFH8LAAITAAYKbBbPCgB2AQATAAYKbBbPCgB2AQA1AAQKf1MAAhMACgrBI4ECAM4DABMACgrBI4ECAM4DAAAA.',
Ce='Celestian:BAAANQAECggICQAAAA==.Cels:BAAANQAECgcIBwAAAA==.',
Ch='Chariso:BAAANQADCgEIAQAAAA==.Chillbros:BAABNQAECn8wAAMOAAoK1SWFGgAqAwAOAAoK1SWFGgAqAwAPAAgKexuiFQAOAgAAAA==.Chumleyson:BAAANQAECgQIBAAAAA==.Churd:BAACNQAFFH8JAAIWAAMKCwoWEACEAAAWAAMKCwoWEACEAAA1AAQKfy8AAhYACgpHFbwfAD0CABYACgpHFbwfAD0CAAAA.Chypnotic:BAABNQAECn8wAAIFAAkKIh4ARQCdAgAFAAkKIh4ARQCdAgAAAA==.Chypotle:BAAANQADCgYIBgAAAA==.Chypster:BAAANQADCgYIBgAAAA==.',
Ci='Ciceroe:BAABNQAECn8YAAMXAAkKpg48PwDoAQAXAAkKpg48PwDoAQAYAAUKygUtOgCdAAAAAA==.',
Cl='Cleft:BAABNQAECn85AAMCAAoKegg7tgBOAQACAAoKegg7tgBOAQAZAAcK4wh2ogA/AQAAAA==.Clevelandk:BAAANQADCgQIBAAAAA==.Clowwnshoes:BAAANQAECgQICgAAAA==.',
Co='Coalystra:BAABNQAECn9KAAMSAAoKDCGwCgCbAgASAAoKDCGwCgCbAgAaAAEKbw3CLgApAAAAAA==.Cocopuffs:BAAANQAECgcIEwAAAA==.Colostrom:BAABNQAECn9KAAIbAAoKjSWeAgBIAwAbAAoKjSWeAgBIAwAAAA==.Coramage:BAAANQAECgcIEwAAAA==.Corliss:BAAANQAECgEIAQAAAA==.Cornholeo:BAAANQAECgEIAgAAAA==.Corruptdata:BAABNQAECn84AAQcAAoKOhuzMwAyAgAcAAoKOhuzMwAyAgAdAAEKBBTCbwBAAAAeAAEKjQhnMgAwAAABNQAFFAcIGgACAFcQAA==.',
Cp='Cpair:BAAANQADCggICAAAAA==.Cplusmc:BAAANQADCgUICAAAAA==.',
Cu='Cuddaloft:BAAANQADCgUIBQAAAA==.',
Cy='Cyori:BAAANQADCgIIAgAAAA==.',
Da='Darkbeast:BAABNQAECn8XAAIFAAoK3BcqkQDnAQAFAAoK3BcqkQDnAQAAAA==.Darthorc:BAAANQAECgQIBgAAAA==.Daten:BAABNQAECn80AAICAAoKVQ1fqwDJAQACAAoKVQ1fqwDJAQAAAA==.Dazlian:BAAANQAECgEIAQAAAA==.Dazshauran:BAAANQADCgUICwAAAA==.',
De='Deadzexcs:BAAANQAECgQICAAAAA==.Deathtaco:BAAANQADCgUIBQAAAA==.Decayed:BAABNQAECn8dAAIDAAkKExSWMAB9AQADAAkKExSWMAB9AQAAAA==.Deladoria:BAABNQAECn8bAAIfAAoKEQ0wZQCYAQAfAAoKEQ0wZQCYAQAAAA==.Depression:BAAANQADCgQIBAABNQAECgQIBQABAAAAAA==.Deragor:BAAANQADCgMIAwABNQAECgMIBAABAAAAAA==.Deus:BAAANQAECgQIBAAAAA==.',
Di='Diagonalli:BAABNQAECn8aAAIJAAgKMgkpEQASAQAJAAgKMgkpEQASAQAAAA==.Dirk:BAAANQAECgcIEAABNQAECgkJLgADADgFAA==.Dirkdìggler:BAAANQADCgUIBwAAAA==.Dirti:BAAANQABCgIIAgAAAA==.Divirian:BAABNQAECn8cAAIOAAgKuRHPVQBvAQAOAAgKuRHPVQBvAQAAAA==.',
Dj='Djdaemon:BAAANQAECgQIBgAAAA==.Djdrakshadow:BAAANQAECgEIAwAAAA==.Djdruidshadw:BAAANQAECgIIBAAAAA==.Djpaly:BAAANQAECgMIBAAAAA==.Djpriest:BAAANQAECgQICgAAAA==.Djshadow:BAAANQAECgMIAwAAAA==.Djshadowar:BAAANQAECgIIBQAAAA==.Djshadowhunt:BAAANQAECgQIBwAAAA==.Djshadowlock:BAAANQAECgQIBQAAAA==.Djshadowlok:BAAANQAECgUICwAAAA==.Djshadowrog:BAAANQAECgEIBAAAAA==.Djshadruid:BAAANQAECgIIBAAAAA==.Djshamy:BAAANQAECgIIBQAAAA==.Djshaolin:BAAANQAECgQICQAAAA==.Djzhadow:BAAANQAECgQIBwAAAA==.Djzhadruid:BAAANQAECgEIBAAAAA==.',
Dk='Dkshadow:BAAANQAECgUICwAAAA==.',
Do='Doofuss:BAAANQAECgEIAgAAAA==.',
Dr='Dragonchalk:BAAANQADCgYIBgABNQAFFAgIHAAPAK8gAA==.Drakhadir:BAAANQAECgUIBwAAAA==.Drakmon:BAAANQADCggIFQAAAA==.Draktând:BAABNQAECn8zAAMXAAoKuxekOQD/AQAXAAoKuxekOQD/AQAYAAEK5gXjpQAwAAAAAA==.Dreve:BAAANQAECgEIAQAAAA==.Driftier:BAAANQAECgYICQAAAA==.Drogon:BAEANQAECggIEgABNQAFFAQIBgAgAGYiAA==.Drunkenpanda:BAABNQAECn8eAAMGAAoK5A3bHgCdAQAGAAoK5A3bHgCdAQAhAAEKAADhewAXAAAAAA==.',
Du='Duneshadow:BAAANQADCgUICQAAAA==.',
Ec='Echö:BAEBNQAECn9KAAITAAoKDReNGQAzAgATAAoKDReNGQAzAgAAAA==.',
Eg='Egamnilbog:BAAANQAECgQIBgAAAA==.',
Ei='Eirø:BAAANQAECgUICAABNQAFFAYIDAANAH4XAA==.',
El='Elaine:BAAANQAECgEIAQAAAA==.Elberon:BAAANQAECgIIBAABNQAECgcIDQABAAAAAA==.Eljer:BAAANQADCgMIAwAAAA==.Ellspeth:BAAANQAECggIAgAAAA==.Elnax:BAAANQAECgEIAwAAAA==.Elöhim:BAAANQAECggIBwAAAA==.',
En='Enæmberclad:BAAANQAECgQIBQAAAA==.',
Ep='Epic:BAAANQADCgYICQAAAA==.',
Eq='Eqo:BAAANQAECgUIBQAAAA==.',
Er='Erebosa:BAAANQAECgEIAwAAAA==.Eriam:BAAANQAECgYIBgABNQAECgoKOgAQAI0TAA==.',
Fa='Fallden:BAAANQAECgMIAwABNQAECgoKJwAWAEoWAA==.Fatherchill:BAABNQAECn8dAAIbAAgKhRdSIQDZAQAbAAgKhRdSIQDZAQAAAA==.Fathermoses:BAABNQAECn8ZAAIWAAoKZQZMJwAyAQAWAAoKZQZMJwAyAQAAAA==.',
Fi='Finnoc:BAAANQAECgEIAgAAAA==.Fitco:BAAANQAECgQIBgAAAA==.',
Fl='Flokii:BAAANQADCgEIAQAAAA==.',
Fr='Frantecks:BAAANQAECgYIBgAAAA==.Freela:BAEANQAECgYICAABNQAECgkJKgAFAIUdAA==.Frost:BAAANQAECgIJAgABNQAFFAcIFQAiAPMUAA==.Frostmon:BAABNQAECn9LAAIHAAoKpiDOCgC9AgAHAAoKpiDOCgC9AgAAAA==.Frostyaf:BAAANQADCgIIAgAAAA==.',
Fu='Furbee:BAAANQAECggIBgAAAA==.',
Ga='Galeandra:BAABNQAECn8ZAAIWAAoKXwV1KAApAQAWAAoKXwV1KAApAQAAAA==.Gambas:BAAANQAECgQIAwAAAA==.Garim:BAABNQAECn8iAAIPAAkKVg0lGgDBAQAPAAkKVg0lGgDBAQAAAA==.Gaztingo:BAABNQAECn8tAAMfAAoKhQ4ZVgDNAQAfAAoKhQ4ZVgDNAQAWAAIKcAK2dAA9AAAAAA==.',
Gh='Ghostbanri:BAAANQABCgcICAAAAA==.',
Gi='Gildor:BAAANQAECgEIAQAAAA==.Giox:BAAANQADCgMIAwAAAA==.Girthshock:BAAANQADCgcIBwABNQAECgcIEgABAAAAAA==.',
Gn='Gnar:BAAANQADCgcICAAAAA==.',
Go='Gobi:BAABNQAECn8nAAIjAAoKfRyCPQBIAgAjAAoKfRyCPQBIAgAAAA==.Gowtherpunch:BAABNQAECn9LAAIkAAoKMBNxBwDbAQAkAAoKMBNxBwDbAQAAAA==.',
Gr='Gravewynd:BAAANQADCggIDwAAAA==.Grimsy:BAABNQAECn8nAAIMAAoKBRekPABAAgAMAAoKBRekPABAAgAAAA==.Grogg:BAAANQADCgUIBQAAAA==.Gruxxiron:BAAANQAECgQICQABNQAECgoKLQADAKsSAA==.',
Gu='Guerriero:BAAANQAECgUIBgABNQAECgoKHAADANAIAA==.Gulnn:BAABNQAECn8xAAQcAAoKHhvRPQAMAgAcAAkKVBvRPQAMAgAdAAIKYxalHQBxAAAeAAEKAAA4MAA1AAAAAA==.Gumby:BAAANQABCgQIBAAAAA==.',
Ha='Haelena:BAAANQAECgQIBwAAAA==.Hage:BAAANQAECggIBAAAAA==.Harmossy:BAAANQAECgUJEQAAAA==.',
He='Heartsfang:BAAANQADCgMIBAAAAA==.Heriotza:BAABNQAECn8cAAMDAAoK0AiUSwAAAQAHAAcKnAXwgQAWAQADAAkKuwiUSwAAAQAAAA==.',
Ho='Hogmaine:BAAANQADCgUICQAAAA==.Holypaladin:BAABNQAECn8gAAIcAAcK+BkmhwDUAQAcAAcK+BkmhwDUAQAAAA==.',
Hu='Hunttress:BAAANQAECgEIAQAAAA==.',
Ib='Ibrakeforimp:BAAANQAECggIAQAAAA==.',
Ii='Iimit:BAABNQAECn8eAAIXAAkKGBY/QwDYAQAXAAkKGBY/QwDYAQABNQAECgoKLwAlAKYdAA==.',
Il='Illidead:BAACNQAFFH8dAAMjAAcKTiLFBQBnAgAjAAYK0iPFBQBnAgAlAAEKQRwVDQBWAAA1AAQKf0MAAyMACgphJUMaANICACMACQpvJUMaANICACUAAQr6JO4wAFoAAAAA.Illooj:BAACNQAFFH8OAAIfAAYKKyU3DgCrAQAfAAYKKyU3DgCrAQA1AAQKf1IAAx8ACgpwJpEAAE8EAB8ACgpqJpEAAE8EAAQACArFJVwBAEQDAAAA.Ilwen:BAAANQAECgUIBAAAAA==.',
In='Indexes:BAABNQAECn8VAAMQAAUKXwtCYQCOAAAQAAUKXwtCYQCOAAAKAAEKPghxewAgAAAAAA==.Inspiration:BAAANQAECgEIAQAAAA==.',
Is='Ist:BAACNQAFFH8JAAIaAAIKowvCBABZAAAaAAIKowvCBABZAAA1AAQKfzMAAhoACgo6FcsNAOEBABoACgo6FcsNAOEBAAAA.',
It='Itchigo:BAAANQAECgUIBgAAAA==.Itskamertime:BAAANQAECgIIAgABNQAECgoKTAAQACYeAA==.',
Iv='Ivgorod:BAABNQAECn8YAAIJAAgKKwXNEwDlAAAJAAgKKwXNEwDlAAAAAA==.',
Ja='Jabbadahut:BAAANQAECggIBgAAAA==.Jarhead:BAABNQAECn8fAAIdAAgK6whjCwD4AAAdAAgK6whjCwD4AAAAAA==.Jaxtoy:BAAANQADCgYIBgAAAA==.Jaybas:BAAANQABCgIIAgAAAA==.Jazienne:BAAANQAECgMIAwAAAA==.Jazilyne:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Jaziriel:BAAANQADCgYIBgAAAA==.',
Je='Jenka:BAAANQAECgMIAwAAAA==.',
Jo='Joleya:BAAANQADCgYICwAAAA==.',
Ju='Judihopps:BAAANQAECgIIAwAAAA==.Justcalmdown:BAAANQAECgYIEgABNQAECgIIAwABAAAAAA==.Justyra:BAAANQAECgQICgABNQAECgoKJgASAN4ZAA==.',
Ka='Kalder:BAAANQADCgIJAgABNQAECgYICQABAAAAAA==.Kalloo:BAAANQAECgYIBgABNQAFFAYIDgAfACslAA==.Kambative:BAABNQAECn9MAAMQAAoKJh4oDgC6AgAQAAoKJh4oDgC6AgAKAAUKmBXPRQABAQAAAA==.Kambustable:BAAANQADCggICwABNQAECgoKTAAQACYeAA==.Kammunion:BAAANQAECgcICgABNQAECgoKTAAQACYeAA==.Kamphiyer:BAAANQADCgMIBAABNQAECgoKTAAQACYeAA==.Kamscendance:BAAANQADCggICgABNQAECgoKTAAQACYeAA==.Kanan:BAAANQADCggIFQAAAA==.Kandosii:BAAANQABCgIIAgAAAA==.Kantheal:BAABNQAECn8cAAMZAAgKOhfdWACgAQAZAAgKOhfdWACgAQAbAAEKAAAadQAoAAAAAA==.',
Ke='Keirmania:BAAANQADCgcIBwAAAA==.',
Ki='Kiagas:BAACNQAFFH8JAAIMAAQKrgchHwCzAAAMAAQKrgchHwCzAAA1AAQKfyUAAxUACgqNDz0YABwBAAwACgoGD6uZANwBABUABgq/CT0YABwBAAE1AAQKAggCAAEAAAAA.Kimbrawly:BAAANQADCgYIBgAAAA==.',
Kr='Kravex:BAABNQAECn86AAIQAAoKjRMsIADoAQAQAAoKjRMsIADoAQAAAA==.Kreynar:BAAANQAECgQJBAABNQAECgoKOgAQAI0TAA==.Krrayt:BAAANQAECgQIDQAAAA==.',
Ku='Kukoc:BAAANQAECgcIEgAAAA==.',
Ky='Kylana:BAAANQADCgYICwAAAA==.Kyriel:BAABNQAECn84AAIgAAoKlh2JHQC5AgAgAAoKlh2JHQC5AgAAAA==.',
['Ké']='Kélly:BAAANQAECggICAAAAA==.',
La='Laayna:BAABNQAECn8VAAIOAAcKFA9EqwA9AQAOAAcKFA9EqwA9AQAAAA==.Lanta:BAAANQAECggIEQAAAA==.Larayvia:BAACNQAFFH8GAAIFAAMKuALKHACjAAAFAAMKuALKHACjAAA1AAQKfyUAAgUACgqACaSQAOgBAAUACgqACaSQAOgBAAAA.',
Le='Leesala:BAABNQAECn86AAIgAAoKXBqVKABzAgAgAAoKXBqVKABzAgAAAA==.Leiman:BAAANQAECgQIDgAAAA==.Leymonte:BAAANQADCgMIAwAAAA==.',
Lg='Lg:BAABNQAECn8+AAMYAAkKWCLvCgAyAwAYAAkK1x7vCgAyAwAXAAgKeR6GHgCHAgABNQAECgIIAwABAAAAAA==.',
Li='Lic:BAABNQAECn8oAAIFAAoKbhEkSwAlAgAFAAoKbhEkSwAlAgAAAA==.Lilbitty:BAAANQADCgEIAQAAAA==.Lilililil:BAABNQAECn8yAAMOAAoK4xq9IgBRAgAOAAoK4xq9IgBRAgAgAAIKkBGUzgBoAAAAAA==.Lillabet:BAAANQAECgQIDgAAAA==.Lilpoo:BAACNQAFFH8FAAIFAAMKBAlKFQDYAAAFAAMKBAlKFQDYAAA1AAQKfxUAAgUACQo7CUN8AKcBAAUACQo7CUN8AKcBAAAA.Limpydk:BAAANQADCgUIBQABNQAECgcIEgABAAAAAA==.Limpylock:BAAANQAECgYIEAABNQAECgcIEgABAAAAAA==.Limpypal:BAAANQAECgcIEgAAAA==.Lispeth:BAABNQAECn8lAAQSAAgKYwk6QgA9AQASAAgKYwk6QgA9AQATAAEKAADZmwAnAAAaAAIKoAT2NwAfAAAAAA==.',
Lo='Lockém:BAAANQABCgYIBwAAAA==.Longtrang:BAAANQADCgMIAwAAAA==.Loriander:BAAANQADCgQIBAAAAA==.',
Lu='Luckyleaf:BAAANQAECgUIBAAAAA==.Lunaaris:BAAANQAECggIDwAAAA==.Lunastre:BAAANQAECgEIAgAAAA==.',
Ma='Macallan:BAAANQAECgQIBwAAAA==.Magifur:BAABNQAECn8cAAIjAAgKABITzADuAQAjAAgKABITzADuAQAAAA==.Magnakilro:BAABNQAECn8zAAIFAAgKwxWJfgAQAgAFAAgKwxWJfgAQAgAAAA==.Magnomar:BAAANQADCgcIDQAAAA==.Maisy:BAAANQADCgUIBwAAAA==.Malditto:BAAANQADCgIIAgAAAA==.Maleficus:BAABNQAECn8VAAIdAAYKuwlTFQCmAAAdAAYKuwlTFQCmAAAAAA==.Mamoswine:BAAANQAECgEIAwAAAA==.Mareki:BAAANQADCggIDQAAAA==.Markdfordeth:BAAANQADCgcIBwAAAA==.Mattyfu:BAAANQAECgYIDwAAAA==.Maxrogue:BAAANQADCgUIBQABNQAECgkJKAALALUNAA==.Mazikeen:BAABNQAECn8UAAIdAAcKChAqHwB1AQAdAAcKChAqHwB1AQAAAA==.',
Me='Meatsupreme:BAACNQAFFH8IAAICAAIKuQsNJAB/AAACAAIKuQsNJAB/AAA1AAQKfysAAgIACgrWE++kANcBAAIACgrWE++kANcBAAAA.Meepin:BAABNQAECn82AAQZAAoKTh7OOgB5AgAZAAkKlB3OOgB5AgACAAgKBRNsoQDeAQAbAAgKHAp7LwDrAAAAAA==.Merdoc:BAAANQAECgUICAAAAA==.Mesophistole:BAAANQADCgUIDQABNQAECgUIEQABAAAAAA==.Mesopunchy:BAAANQAECgUIEQAAAA==.Mesopyro:BAAANQADCgMIBgABNQAECgUIEQABAAAAAA==.',
Mi='Miamore:BAAANQADCggICAAAAA==.Microchyp:BAAANQADCgEIAQAAAA==.Mileenä:BAAANQAECggIBgAAAA==.Milemarker:BAABNQAECn8VAAIZAAgK2QZIiwB6AQAZAAgK2QZIiwB6AQAAAA==.Mindstorm:BAAANQADCggICAAAAA==.Misstwizted:BAABNQAECn8XAAMcAAcKfwTK1wAaAQAcAAcKfgTK1wAaAQAeAAIK5AEZKwBBAAAAAA==.',
Mo='Mohinu:BAAANQAECgcIDwAAAA==.Mojodaemon:BAAANQADCgUIBQAAAA==.Molag:BAAANQAECgIIAgAAAA==.Moocowmoo:BAAANQADCggIDgABNQAECggIIAAcAPgZAA==.Mooli:BAAANQAECgEIAQAAAA==.Moondevil:BAAANQADCgYIDQAAAA==.Morta:BAEBNQAECn8qAAIFAAkKhR2jQgA8AgAFAAkKhR2jQgA8AgAAAA==.Mortkavaliro:BAAANQADCgYIBgABNQAECgoKHAADANAIAA==.',
Mu='Mugzy:BAAANQAECggIDwAAAA==.Muted:BAAANQADCgIIAgABNQAECgIIAwABAAAAAA==.',
['Mö']='Mörph:BAAANQAECgMIAwABNQAECgkJHAAZAEobAA==.',
['Mø']='Møde:BAAANQADCgQIBAABNQAECgoKRQAjADQLAA==.',
Na='Nanérs:BAAANQAECgUIBgABNQAFFAYIEQAQAGgcAA==.Narrodus:BAABNQAECn8XAAIaAAoKvB2fBAB9AgAaAAoKvB2fBAB9AgAAAA==.Nasht:BAAANQAECgEIAgAAAA==.Nasun:BAAANQADCgQIBAAAAA==.Nataku:BAABNQAECn8YAAIQAAcKswj7ZQA1AQAQAAcKswj7ZQA1AQAAAA==.',
Ne='Neelix:BAAANQAECgEIAQAAAA==.Neoth:BAAANQAECgEIAQAAAA==.Nerdofprey:BAAANQAECggIAQAAAA==.Nezzick:BAABNQAECn89AAMOAAoKvxejOwCHAgAOAAoKvxejOwCHAgAgAAgK2AsplgBQAQAAAA==.',
Ni='Nicholasrage:BAAANQAECgEIAQAAAA==.Nidalap:BAAANQADCgEIAQAAAA==.Nightreaper:BAAANQADCggIQQAAAA==.Nightsinger:BAAANQAECgIIAgAAAA==.Nikkohan:BAAANQAECgQIBAAAAA==.Nimbus:BAACNQAFFH8bAAMOAAcKPBccAwB6AgAOAAcKPBccAwB6AgAgAAEKXgHEKwBGAAA1AAQKf9IAAg4ACgqlJvkAAPkDAA4ACgqlJvkAAPkDAAAA.Nixy:BAAANQAECggIDQAAAA==.',
No='Nomns:BAABNQAECn8kAAIFAAoK1x8PGwDKAgAFAAoK1x8PGwDKAgAAAA==.Normel:BAAANQAECgEIAQAAAA==.Noz:BAAANQAECgIIBAABNQAECggIGwACACwfAA==.',
Nr='Nrvous:BAAANQADCgIIAgAAAA==.',
Nu='Nuid:BAAANQAECggICQAAAA==.Numbers:BAABNQAECn8bAAISAAoKixBYIwBtAQASAAoKixBYIwBtAQAAAA==.',
Ny='Nytesage:BAACNQAFFH8SAAImAAcKmiMuAACsAQAmAAcKmiMuAACsAQA1AAQKfycAAiYACQqKJikAANoDACYACQqKJikAANoDAAAA.',
['Nä']='Näners:BAAANQAECgIIAQABNQAFFAYIEQAQAGgcAA==.',
['Në']='Nëvërmind:BAABNQAECn89AAIbAAoKuh5IDABYAgAbAAoKuh5IDABYAgAAAA==.',
['Nì']='Nìghtcat:BAAANQAECgYIEgAAAA==.',
Or='Orgrom:BAAANQAECggICAAAAA==.',
Os='Osiva:BAAANQAECgEIAQAAAA==.',
Oz='Ozgar:BAABNQAECn8XAAMWAAYK5hXeKwAPAQAWAAYK5hXeKwAPAQAEAAEKkAgeLgApAAAAAA==.Ozo:BAAANQADCgIIAgAAAA==.',
Pa='Painavolian:BAABNQAECn9QAAIjAAoKhR+QMQAoAwAjAAoKhR+QMQAoAwAAAA==.Palcris:BAAANQADCgcIBwAAAA==.Paxren:BAAANQABCgIIAgAAAA==.',
Pe='Peeches:BAAANQAECgYIBgAAAA==.Pelonis:BAAANQADCgYICgAAAA==.Penthesilea:BAAANQAECgQIBQAAAA==.',
Ph='Pheayre:BAAANQADCgYIBgABNQAECgMIBAABAAAAAA==.Phoenixdówn:BAABNQAECn8uAAIgAAgKxiEiIgCaAgAgAAgKxiEiIgCaAgAAAA==.Phoosa:BAAANQADCgEIAQAAAA==.',
Pi='Pingpong:BAABNQAECn8zAAQhAAoKwhhuIAAqAgAhAAoKwhhuIAAqAgAkAAcKUw5sDgAtAQAGAAEKBQOtVAAgAAAAAA==.Pisspadpanda:BAABNQAECn85AAMcAAoKWhxaNwAjAgAcAAoK2RtaNwAjAgAeAAQKWBXBEwAPAQAAAA==.',
Pl='Plungsnipes:BAAANQADCggIFAABNQAECggICgABAAAAAA==.',
Po='Poggies:BAACNQAFFH8PAAMmAAcKtCA5AACCAQAjAAYKfSBpFgDEAQAmAAQKvhs5AACCAQA1AAQKfxsAAyYACgpcJVABAMECACMACgpuJIQyACYDACYACAojI1ABAMECAAAA.Potatodh:BAAANQAECgEIBQAAAA==.Potatolock:BAABNQAECn8ZAAQcAAkKuRP0VgC7AQAcAAkK5xL0VgC7AQAeAAQKRw00FAAIAQAdAAIKPhTQMgA8AAAAAA==.',
Pr='Praynes:BAABNQAECn9IAAIfAAoKlRx8KQCSAgAfAAoKlRx8KQCSAgAAAA==.',
Pu='Pupperputh:BAAANQADCgIIAgABNQAECgIIAwABAAAAAA==.Puppet:BAAANQAECgEIAQAAAA==.',
Py='Pylanora:BAAANQADCgMIAwAAAA==.',
Qu='Quinnx:BAAANQADCgYIBwAAAA==.',
Ra='Rach:BAABNQAECn85AAIFAAoKRxtfLwB3AgAFAAoKRxtfLwB3AgAAAA==.Rael:BAAANQADCgIJAgAAAA==.Ranoe:BAAANQAECgIIAwABNQAECgoKLwAlAKYdAA==.Rathalos:BAAANQAECgEIAQAAAA==.Raxity:BAABNQAECn8fAAIfAAoKBBrpJACsAgAfAAoKBBrpJACsAgAAAA==.Raxxity:BAAANQAECggICwAAAA==.Razji:BAABNQAECn8vAAMNAAoKRByAGgCBAgANAAgKJSCAGgCBAgAFAAUK8xa68wAaAQAAAA==.',
Re='Redmg:BAAANQADCgUIDQABNQAECgMIBAABAAAAAA==.Renfro:BAAANQAECgEIAwAAAA==.',
Ri='Riete:BAABNQAECn8oAAIeAAkKaRHECQDjAQAeAAkKaRHECQDjAQAAAA==.Rinoa:BAABNQAECn9FAAIjAAoKNAsqcQC7AQAjAAoKNAsqcQC7AQAAAA==.',
Ro='Rochallie:BAAANQAECgQIDgAAAA==.Rockii:BAAANQADCgYIBgAAAA==.Rocknwolf:BAABNQAECn8fAAIRAAoK7wf9GgAXAQARAAoK7wf9GgAXAQAAAA==.Rokd:BAABNQAECn8jAAIbAAkKHyHwCAAOAwAbAAkKHyHwCAAOAwAAAA==.Rosalee:BAEANQABCgIIAgABNQAECgcIFAABAAAAAA==.Roscoelock:BAABNQAECn8WAAMdAAcKfhZ1IABtAQAdAAUK4Rt1IABtAQAcAAUKEwzV9gDdAAAAAA==.Roxxann:BAAANQADCgYIBgAAAA==.',
Ru='Ruibaron:BAAANQAECgQIBQAAAA==.Rumur:BAAANQADCgYIBgABNQAECggIKQAHAA4OAA==.',
['Rà']='Ràidèn:BAAANQADCgcIBwABNQAECgoKQQAgANkfAA==.',
['Rá']='Ráyne:BAAANQAECgEIAQAAAA==.',
Sa='Sadeel:BAABNQAECn9KAAMeAAoKVRXzBQAGAgAeAAoKJxXzBQAGAgAcAAcKlAxtsgBrAQAAAA==.Sadewolf:BAABNQAECn8lAAMSAAoKKyD3FAC+AgASAAkK2SH3FAC+AgATAAQKHxL/SQDqAAAAAA==.Salvadore:BAAANQADCggICAAAAA==.Samentoni:BAACNQAFFH8JAAIZAAMKuBJgGgCbAAAZAAMKuBJgGgCbAAA1AAQKfy8AAhkACgpAGrJAAGICABkACgpAGrJAAGICAAAA.Samgal:BAAANQAECgYIEQAAAA==.Sampsyn:BAAANQABCgYICgAAAA==.Sanctalux:BAAANQADCgQICQAAAA==.Sansura:BAAANQAECggICQABNQAECgoKUgAOAG0TAA==.Sasha:BAAANQAECgMICAAAAA==.Satyra:BAABNQAECn8mAAISAAoK3hltFwDpAQASAAoK3hltFwDpAQAAAA==.Saurphang:BAACNQAFFH8SAAMHAAUKrhpnBQACAQAHAAQKrhpnBQACAQADAAEKAABvPgAWAAA1AAQKfz0AAgcACgp/IVUPADwDAAcACgp/IVUPADwDAAAA.',
Sc='Scamanes:BAAANQAECgYIDQAAAA==.',
Se='Seluun:BAAANQAECgEIAQAAAA==.Semperfi:BAAANQABCgYICQAAAA==.Severis:BAAANQADCgEIAQAAAA==.',
Sh='Shadora:BAABNQAECn8ZAAIWAAkK8xEwFAAFAgAWAAkK8xEwFAAFAgAAAA==.Shadowwizard:BAABNQAECn9PAAIdAAoKZxAPBgBvAQAdAAoKZxAPBgBvAQAAAA==.Shadybrat:BAAANQAECgcICgABNQAECgoKOgAFAPgPAA==.Shaladin:BAAANQAECggIEAAAAA==.Shidan:BAABNQAECn9BAAIgAAoK2R/yFQDzAgAgAAoK2R/yFQDzAgAAAA==.Shmeepin:BAAANQAECgIIAgAAAA==.Shockaho:BAAANQAECgUICQAAAA==.Shockchalk:BAACNQAFFH8cAAIPAAgKryAyAADNAgAPAAgKryAyAADNAgA1AAQKf0oAAg8ACgrvJmsAAIQDAA8ACgrvJmsAAIQDAAAA.Shocknorris:BAAANQAECgIIBQABNQAECgQIBgABAAAAAA==.Shqaukers:BAAANQAECgEIAQAAAA==.Shrooclaw:BAAANQAECgIIAgAAAA==.Shulk:BAABNQAECn8UAAICAAgK9QsUvwCeAQACAAgK9QsUvwCeAQAAAA==.',
Si='Sibbiah:BAEANQAECgcIFAAAAQ==.Silanre:BAABNQAECn8lAAMjAAcKOBLRyQADAQAjAAYKrRTRyQADAQAlAAEKYwi3PgArAAAAAA==.',
Sk='Skaðï:BAACNQAFFH8MAAINAAYKfhdsDQBnAQANAAYKfhdsDQBnAQA1AAQKf2AABA0ACgpZI+YDABQDAA0ACgpZI+YDABQDAAUAAwrQAI9AAWEAACcAAQolDHoSADwAAAAA.',
Sl='Slizzard:BAAANQADCgIIAgABNQAFFAYIDwAHAKYSAA==.',
Sm='Smalldrogø:BAAANQADCggICAAAAA==.',
Sp='Spadesrage:BAABNQAECn8XAAIZAAYKcx9cQwD0AQAZAAYKcx9cQwD0AQAAAA==.Spadesrot:BAAANQAECgEIAQAAAA==.Spadestree:BAAANQADCgYICgAAAA==.Spash:BAAANQADCggIEAAAAA==.Spicyycurryy:BAABNQAECn8jAAIMAAgKPBmcggAVAgAMAAgKPBmcggAVAgAAAA==.',
St='Staticshock:BAAANQADCgUICAABNQAECggICgABAAAAAA==.Stepdruid:BAAANQAECgEIAQAAAA==.Strahm:BAABNQAECn8oAAILAAkKtQ04KgAjAQALAAkKtQ04KgAjAQAAAA==.Strehm:BAAANQADCgYIDAABNQAECgkJKAALALUNAA==.Stryhm:BAAANQADCgQIBwABNQAECgkJKAALALUNAA==.',
Su='Sulfass:BAAANQAECgEIAQAAAA==.Supërman:BAAANQABCgcICQAAAA==.Surai:BAABNQAECn8cAAIgAAkK2yB2DwBIAwAgAAkK2yB2DwBIAwABNQAFFAYICAAXANALAA==.',
Sy='Sylryn:BAAANQADCgQIBAAAAA==.Sylvexa:BAAANQAECgQIBwAAAA==.Symple:BAAANQAECgEIAgAAAA==.Syns:BAAANQAECgIIAgAAAA==.Synz:BAAANQAECgIIAgAAAA==.Syssare:BAABNQAECn8cAAITAAgKrx0zMAAmAgATAAgKrx0zMAAmAgAAAA==.',
Ta='Tacpally:BAAANQAECgEIAQAAAA==.Talamor:BAAANQADCgMJAwAAAA==.Talasam:BAAANQADCgQIBAAAAA==.Talisman:BAAANQADCggICAAAAA==.Tandsonnara:BAAANQAECggIAQAAAA==.Tastetickle:BAABNQAECn9NAAIjAAoK5R1yJACiAgAjAAoK5R1yJACiAgAAAA==.Tazdrin:BAABNQAECn9MAAIoAAoKNxfLAQBHAgAoAAoKNxfLAQBHAgAAAA==.Taze:BAABNQAECn8XAAQQAAgKrB41GgAlAgAQAAgKrB41GgAlAgAKAAMK2By3VAC1AAALAAMKRg3SXwBHAAAAAA==.',
Te='Telidrus:BAACNQAFFH8GAAMlAAMK2REvCQCMAAAjAAMKlg9AOwDXAAAlAAIKxg8vCQCMAAA1AAQKfyQABCUACQqpIC8MAPkBACMACAp6HdCaAEsCACUABwpBHi8MAPkBACYAAgroDlMJAHUAAAAA.Teneturadvys:BAAANQADCgQIBAABNQAECggICQABAAAAAA==.Terrax:BAAANQAECgEIAQAAAA==.',
Th='Thepoacher:BAAANQAECggIDwABNQAECgkJHQADABMUAA==.Thicc:BAAANQABCgQIBAAAAA==.Thicchunter:BAABNQAECn9HAAINAAoK6SBCCwAkAwANAAoK6SBCCwAkAwAAAA==.Thiccmage:BAABNQAECn8YAAIjAAgKXxFIdgCuAQAjAAgKXxFIdgCuAQAAAA==.Thiccwiggy:BAAANQADCgMIAwABNQAECgYIDwABAAAAAA==.Thuk:BAABNQAECn8WAAMUAAkKEhDhFABYAQAUAAcKahPhFABYAQAMAAgKYAgR2wA3AQAAAA==.Thukwarlock:BAAANQADCgEIAQAAAA==.Thunderbug:BAAANQADCggICAAAAA==.',
To='Topaze:BAABNQAECn8cAAMZAAkKShuzKADFAgAZAAkKShuzKADFAgAbAAEKAAAcdgAnAAAAAA==.Totemmonster:BAAANQAECgEIAQAAAA==.',
Tr='Trancendantx:BAAANQAECgEIAQAAAA==.Tripx:BAACNQAFFH8aAAMCAAcKVxCFDACCAQACAAYKRhCFDACCAQAbAAEKnRBsDgBHAAA1AAQKfzgAAwIACgrDH04gANcCAAIACgrDH04gANcCABsAAQoAALB2AAAAAAAA.Tripxed:BAABNQAECn8/AAMQAAoKUBoYHwDSAgAQAAoKUBoYHwDSAgARAAEKWgqVQAA5AAABNQAFFAcIGgACAFcQAA==.Trishan:BAAANQAECgQIBwAAAA==.Trolk:BAAANQADCgUIBwAAAA==.Tronklock:BAAANQADCgEIAQAAAA==.Tronko:BAABNQAECn8pAAMgAAoKTxjpHAC9AgAgAAoKTxjpHAC9AgAOAAEKNgOnQgEtAAAAAA==.Truthjustice:BAAANQADCggIEgAAAA==.',
Tu='Tullip:BAAANQAECgEIAgAAAA==.Turntsnaco:BAABNQAECn9IAAMXAAoK/Bw8LQA2AgAXAAkKcx08LQA2AgAYAAYKQBVOZQAeAQAAAA==.Turyon:BAAANQADCgEIAQAAAA==.',
Tw='Twiztedfaith:BAAANQADCgYIBgAAAA==.',
Tz='Tzifora:BAEANQAECgEIAQABNQAECgcIFAABAAAAAA==.',
Ul='Ulhume:BAAANQADCgEJAQABNQAECgoKOgAQAI0TAA==.',
Un='Unafhaen:BAAANQADCgQIBAAAAA==.Unaverse:BAAANQAECgUICgAAAA==.',
Ur='Urp:BAAANQAECgQIDgAAAA==.',
Us='Usmc:BAAANQAECgYIBQAAAA==.Usmccpl:BAAANQADCgYICQAAAA==.',
Va='Valengarde:BAABNQAECn8aAAICAAoKVBdGjgAIAgACAAoKVBdGjgAIAgAAAA==.Valentin:BAAANQABCgIIAgAAAA==.Valhalia:BAAANQABCgIIAgAAAA==.Vanderneuker:BAAANQAECgQIBwABNQAFFAYIDwAHAKYSAA==.Vanero:BAAANQAECgUIBgAAAA==.Vangoon:BAEBNQAECn81AAMYAAoKXSAsCQBHAwAYAAkKJSEsCQBHAwAXAAgKPxmaRQDPAQAAAA==.Vanmonk:BAAANQAECggIDAAAAA==.Vann:BAAANQADCgQIBwAAAA==.Vannix:BAABNQAECn9JAAIWAAoKDiQnAwBKAwAWAAoKDiQnAwBKAwAAAA==.',
Ve='Veldrys:BAAANQAECgUIBQABNQAECgoKOgAQAI0TAA==.Velkanos:BAAANQADCgQIBAAAAA==.Velkhaz:BAAANQABCgYIBgAAAA==.Vereena:BAAANQAECgUIDwAAAA==.Vesstar:BAAANQABCggIFwAAAA==.',
Vi='Vigo:BAAANQAECggIDwAAAA==.Violet:BAAANQADCgMIAwAAAA==.Virmethir:BAABNQAECn8dAAIJAAYKiBdIGwCVAQAJAAYKiBdIGwCVAQAAAA==.',
Vo='Voltaren:BAAANQAECgIJAgAAAA==.',
Wa='Waq:BAAANQADCgcIBwAAAA==.Wasabii:BAAANQAECgMIBAAAAA==.',
Wh='Whtmg:BAAANQADCgIIAgABNQAECgMIBAABAAAAAA==.',
Wi='Winterbreeze:BAAANQADCgQICgAAAA==.Wiwi:BAACNQAFFH8PAAMHAAYKphKDEQDyAAAHAAMKfBmDEQDyAAAiAAQK2xDqEgChAAA1AAQKf1kAAyIACgrZIxIQAMUCACIACQqMIxIQAMUCAAcACAqqG7ZMAOIBAAAA.',
Wo='Woopie:BAAANQAECgIIAgAAAA==.',
Wu='Wukøng:BAAANQABCgIIAgAAAA==.',
Xa='Xake:BAAANQAECgUIDQAAAA==.Xares:BAABNQAECn8vAAMlAAoKph2gCABUAgAlAAoKph2gCABUAgAjAAYKiw0kIAFWAQAAAA==.',
Xe='Xenp:BAABNQAECn9CAAMbAAoKZRmxDQA9AgAbAAoKZRmxDQA9AgACAAUKmwoOOwHBAAAAAA==.',
Xi='Xiovemm:BAAANQADCgcJBQAAAA==.',
Xu='Xuri:BAABNQAECn8cAAIFAAkKLAxjkADoAQAFAAkKLAxjkADoAQAAAA==.',
Ya='Yalda:BAAANQADCgIIAgAAAA==.',
Yd='Ydriel:BAAANQADCgUIBwAAAA==.',
['Yö']='Yöurfired:BAAANQAECgEIBAAAAA==.',
Za='Zake:BAABNQAECn9DAAIFAAoKMR2iKwDrAgAFAAoKMR2iKwDrAgAAAA==.Zalileina:BAAANQADCgMIAgAAAA==.Zantanna:BAAANQAECgMIBQAAAA==.Zappythile:BAABNQAECn8yAAMgAAoKwyB5KADCAgAgAAoKwyB5KADCAgAOAAEKAACJQwEsAAAAAA==.',
Ze='Zealdavir:BAAANQAECgEIAgAAAA==.Zenà:BAAANQAECgEIAQAAAA==.',
Zi='Zigzagoon:BAAANQABCgYIBgAAAA==.',
Zo='Zoz:BAABNQAECn8eAAIlAAoKDQtIEABrAQAlAAoKDQtIEABrAQAAAA==.',
Zu='Zulfrik:BAABNQAECn8yAAMjAAoKkBWVbADHAQAjAAoKXROVbADHAQAlAAIKEh2DMwBsAAAAAA==.',
Zy='Zyzy:BAAANQAECgcICwABNQAFFAcIHQAWAP8bAA==.',
['Äh']='Ählis:BAAANQAECgIIBgAAAA==.',
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
