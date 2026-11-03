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

local lookup = {'Unknown-Unknown','Paladin-Retribution','DeathKnight-Unholy','Hunter-BeastMastery','Monk-Mistweaver','DeathKnight-Blood','Evoker-Augmentation','Evoker-Devastation','Druid-Restoration','Druid-Guardian','Hunter-Marksmanship','Shaman-Elemental','Shaman-Enhancement','Druid-Balance','Druid-Feral','DemonHunter-Devourer','DemonHunter-Havoc','Warrior-Protection','Warrior-Fury','Priest-Shadow','Paladin-Holy','DemonHunter-Vengeance','Paladin-Protection','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Priest-Holy','Rogue-Subtlety','Rogue-Assassination','Shaman-Restoration','Monk-Windwalker','DeathKnight-Frost','Mage-Arcane','Monk-Brewmaster','Warrior-Arms','Mage-Frost','Priest-Discipline','Mage-Fire','Hunter-Survival','Rogue-Outlaw',}
local provider = {region='US',realm='Eonar',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abysseus:BAAANQADCgcIEAAAAA==.',
Ad='Admired:BAAANQAECgEIAwABNQAECgUIDAABAAAAAA==.',
Ae='Aerdrie:BAAANQADCgEIAQAAAA==.Aevelin:BAABNQAECn8bAAICAAoKmw8RngDmAQACAAoKmw8RngDmAQAAAA==.',
Aj='Ajagar:BAAANQAECgIIBAABNQAECgoKFQADAGcHAA==.',
Al='Alamora:BAAANQAECgUIDwAAAA==.Alastair:BAAANQAECggIAgAAAA==.Alathena:BAAANQAECgMIAwAAAA==.Albrect:BAAANQADCgYIBgAAAA==.Alexandrya:BAABNQAECn82AAIEAAoKrg6vXwDCAQAEAAoKrg6vXwDCAQAAAA==.Alickdh:BAAANQADCgIIAwABNQAFFAEIAgABAAAAAA==.Almostpanda:BAAANQADCgUIBQABNQAECgoKHgAFAOQNAA==.Altery:BAAANQAECgEIAQAAAA==.',
Am='Ampharos:BAAANQADCgEIAQAAAA==.Amsahunter:BAAANQADCggICAABNQAECggIGAADAB8OAA==.Amsroeb:BAABNQAECn8YAAMDAAgKHw49NQAeAQADAAYK5Q09NQAeAQAGAAYKRQr0XgCjAAAAAA==.',
An='Anelavenger:BAACNQAFFH8ZAAIHAAYKexeDBAA0AQAHAAYKexeDBAA0AQA1AAQKf2cAAwcACgq2I+gAAK4DAAcACgq2I+gAAK4DAAgABgppDEEjACwBAAAA.Anelblast:BAAANQAECgYIEQABNQAFFAYIGQAHAHsXAA==.Angerwina:BAAANQAECgMICAAAAA==.Annain:BAAANQADCgYJCgAAAA==.',
Ar='Arathor:BAAANQADCggIEQAAAA==.Ardent:BAAANQAECgUICwAAAA==.Ardor:BAAANQADCgYIDAABNQAECgUICwABAAAAAA==.Arent:BAABNQAECn85AAMJAAoKIxH0IAAiAgAJAAoKIxH0IAAiAgAKAAcKTQs1KQAIAQAAAA==.Arkanna:BAAANQADCgYIBgAAAA==.Arkhea:BAAANQAECgQIBAAAAA==.Artemislives:BAAANQAECggICAAAAA==.',
As='Asharia:BAAANQAECgcIEAAAAA==.Ashla:BAAANQADCgIIAgAAAA==.Asilan:BAAANQABCgEIAQAAAA==.Assateague:BAAANQAECgUIDwAAAA==.Astelossa:BAAANQADCggIJwAAAA==.',
['Aë']='Aëro:BAAANQADCgYICwAAAA==.',
Ba='Bahnna:BAAANQADCgUICAAAAA==.Bananapistol:BAAANQADCgEIAQAAAA==.Barracksbuny:BAAANQAECgYIDQABNQAECgkJFgAGAKATAA==.Barrathfrogy:BAAANQADCgUIDQAAAA==.',
Be='Bebheishel:BAAANQADCgQIDAAAAA==.Beefcake:BAAANQADCgYIFgABNQAECgIIBAABAAAAAA==.Bertello:BAAANQAECgQIBAAAAA==.Beserol:BAAANQAECgQICwAAAA==.',
Bi='Biest:BAAANQAECggICAAAAA==.Biggs:BAAANQADCggICQABNQAECggIBgABAAAAAA==.Billy:BAABNQAECn8dAAIFAAgKnxmVGAD0AQAFAAgKnxmVGAD0AQAAAA==.Bilywitchdoc:BAAANQAECgEIBQABNQAECgoKKwALABIcAA==.Bionicle:BAAANQADCgQIBAAAAA==.Biscuít:BAAANQAECggIDgAAAA==.',
Bk='Bk:BAAANQADCgcIDQABNQAECgoKMgAMAOMaAA==.',
Bl='Blasuoff:BAAANQADCgYIBgAAAA==.Blkmg:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Bloodeagle:BAAANQAECggICAAAAA==.Bluechalk:BAAANQAECgcIEAABNQAFFAgIHAANAK8gAA==.',
Bo='Boomslap:BAAANQAECggICQAAAA==.Boredom:BAAANQADCggICAAAAA==.Borzoi:BAABNQAECn9OAAICAAkKCiWxCwAyAwACAAkKCiWxCwAyAwAAAA==.',
Br='Brawne:BAAANQADCgUIBQAAAA==.',
Bu='Buzzdkt:BAAANQAECgEIAQAAAA==.Buzzdruu:BAABNQAECn8mAAQOAAoKhBzQLgBoAgAOAAoKiRfQLgBoAgAPAAYK6RWMGQD4AAAKAAEKryERTgBdAAAAAA==.',
['Bó']='Bóg:BAAANQADCgEIAQAAAA==.',
['Bø']='Bønës:BAAANQADCgQIBAAAAA==.',
Ca='Caaniss:BAAANQADCgEIAQAAAA==.Cadeana:BAAANQADCgQIBAAAAA==.Caduceus:BAAANQADCgUIBgAAAA==.Caesus:BAAANQADCgcIDgAAAA==.Cagedancer:BAAANQAECgIIAgAAAA==.Callio:BAABNQAECn82AAIEAAoKVwyHXADKAQAEAAoKVwyHXADKAQAAAA==.Canus:BAAANQAECggIDAAAAA==.Caprisunsipz:BAAANQAECggIDAAAAA==.Caritta:BAABNQAECn8UAAMQAAcK/hSpPgBVAQAQAAYKSRCpPgBVAQARAAMKqxaubADGAAAAAA==.Cathillex:BAABNQAECn8VAAMSAAgKnhWEEwBHAQASAAgKnhWEEwBHAQATAAEKVBHSMQA5AAAAAA==.Caycay:BAACNQAFFH8LAAIRAAYKbBbPCgB2AQARAAYKbBbPCgB2AQA1AAQKf04AAhEACgp/I4ECAM4DABEACgp/I4ECAM4DAAAA.',
Ce='Celestian:BAAANQAECggICQAAAA==.Cels:BAAANQAECgcIBwAAAA==.',
Ch='Chillbros:BAABNQAECn8qAAMMAAoKtCWFGgAqAwAMAAoKtCWFGgAqAwANAAgKexuiFQAOAgAAAA==.Chumleyson:BAAANQAECgQIBAAAAA==.Churd:BAACNQAFFH8HAAIUAAIKbA9HFQB2AAAUAAIKbA9HFQB2AAA1AAQKfywAAhQACgpHFbwfAD0CABQACgpHFbwfAD0CAAAA.Chypnotic:BAABNQAECn8vAAIEAAkK9BkARQCdAgAEAAkK9BkARQCdAgAAAA==.Chypotle:BAAANQADCgYIBgAAAA==.Chypster:BAAANQADCgYIBgAAAA==.',
Ci='Ciceroe:BAAANQAECggIDwAAAA==.',
Cl='Cleft:BAABNQAECn85AAMCAAoKeggQpQBDAQACAAoKeggQpQBDAQAVAAcK4wh2ogA/AQAAAA==.Clevelandk:BAAANQADCgQIBAAAAA==.Clowwnshoes:BAAANQAECgQICgAAAA==.',
Co='Coalystra:BAABNQAECn9BAAMQAAoKDCESCgCUAgAQAAoKDCESCgCUAgAWAAEKbw2zKwArAAAAAA==.Cocopuffs:BAAANQAECgcIDAAAAA==.Colostrom:BAABNQAECn9BAAIXAAoK6yTeAwAYAwAXAAoK6yTeAwAYAwAAAA==.Coramage:BAAANQAECgcIEAAAAA==.Corliss:BAAANQAECgEIAQAAAA==.Corruptdata:BAABNQAECn80AAQYAAoKjxm/MwASAgAYAAoKjxm/MwASAgAZAAEKBBTCbwBAAAAaAAEKjQhnMgAwAAABNQAFFAYIGAACADMRAA==.',
Cp='Cpair:BAAANQADCggICAAAAA==.Cplusmc:BAAANQADCgUICQAAAA==.',
Cu='Cuddaloft:BAAANQADCgUIBQAAAA==.',
Da='Darkbeast:BAABNQAECn8XAAIEAAoK3BcqkQDnAQAEAAoK3BcqkQDnAQAAAA==.Darthorc:BAAANQAECgIIBAAAAA==.Daten:BAABNQAECn80AAICAAoKVQ3skgBmAQACAAoKVQ3skgBmAQAAAA==.Dazshauran:BAAANQADCgUICwAAAA==.',
De='Deadzexcs:BAAANQAECgQIBwAAAA==.Deathpizza:BAAANQADCgEIAQAAAA==.Deathtaco:BAAANQADCgUIBQAAAA==.Decayed:BAABNQAECn8WAAIGAAkKoBNLTADFAQAGAAkKoBNLTADFAQAAAA==.Deladoria:BAABNQAECn8YAAIbAAkKKAyFaQBkAQAbAAkKKAyFaQBkAQAAAA==.Depression:BAAANQADCgQIBAABNQAECgQIBQABAAAAAA==.Deragor:BAAANQADCgMIAwABNQAECgMIAwABAAAAAA==.Deus:BAAANQAECgIIAgAAAA==.',
Di='Diagonalli:BAABNQAECn8aAAIIAAgKMgluDwAUAQAIAAgKMgluDwAUAQAAAA==.Dirk:BAAANQAECgcIDgAAAA==.Dirkdìggler:BAAANQADCgUICQAAAA==.Dirti:BAAANQADCgEIAQAAAA==.Divirian:BAABNQAECn8VAAIMAAgKMg89XgAwAQAMAAgKMg89XgAwAQAAAA==.',
Dj='Djdaemon:BAAANQAECgUIBQAAAA==.Djdrakshadow:BAAANQAECgEIAgAAAA==.Djdruidshadw:BAAANQAECgIIAgAAAA==.Djpaly:BAAANQAECgEIAQAAAA==.Djpriest:BAAANQAECgUIBQAAAA==.Djshadow:BAAANQAECgEIAQAAAA==.Djshadowar:BAAANQAECgEIAgAAAA==.Djshadowhunt:BAAANQAECgMIBAAAAA==.Djshadowlock:BAAANQAECgQIBAAAAA==.Djshadowlok:BAAANQAECgYIBwAAAA==.Djshadowrog:BAAANQAECgIIAwAAAA==.Djshadruid:BAAANQAECgIIAwAAAA==.Djshamy:BAAANQAECgIIBAAAAA==.Djshaolin:BAAANQAECgUIBAAAAA==.Djzhadow:BAAANQAECgQIBQAAAA==.Djzhadruid:BAAANQAECgIIAwAAAA==.',
Dk='Dkshadow:BAAANQAECgQICQAAAA==.',
Do='Doofuss:BAAANQADCgEIAgAAAA==.',
Dr='Dragonchalk:BAAANQADCgYIBgABNQAFFAgIHAANAK8gAA==.Drakhadir:BAAANQAECgcIBgAAAA==.Drakmon:BAAANQADCggIFQAAAA==.Draktând:BAABNQAECn8wAAMcAAoKbhVMFwAkAgAcAAoKbhVMFwAkAgAdAAEK5gXjpQAwAAAAAA==.Dreve:BAAANQABCgIIBAAAAA==.Driftier:BAAANQAECgYICAAAAA==.Drogon:BAEANQAECggIDgABNQAFFAMIBQAeAFsjAA==.Drunkenpanda:BAABNQAECn8eAAMFAAoK5A3bHgCdAQAFAAoK5A3bHgCdAQAfAAEKAADhewAXAAAAAA==.',
Du='Duneshadow:BAAANQADCgUICQAAAA==.',
Ec='Echö:BAEBNQAECn9BAAIRAAoKyBaoFwAkAgARAAoKyBaoFwAkAgAAAA==.',
Eg='Egamnilbog:BAAANQAECgQIBgAAAA==.',
Ei='Eirø:BAAANQAECgUICAABNQAFFAYIDAALAH4XAA==.',
El='Elberon:BAAANQAECgIIBAABNQAECgYICwABAAAAAA==.Eljer:BAAANQADCgMIAwAAAA==.Ellspeth:BAAANQAECggIAgAAAA==.Elnax:BAAANQAECgEIAQAAAA==.Elöhim:BAAANQAECggIBgAAAA==.',
En='Enæmberclad:BAAANQAECgQIBQAAAA==.',
Ep='Epic:BAAANQADCgYICQAAAA==.',
Eq='Eqo:BAAANQAECgUIBQAAAA==.',
Er='Erebosa:BAAANQADCgEIAQAAAA==.',
Fa='Fallden:BAAANQAECgMIAwABNQAECgoKJwAUAEoWAA==.Fatherchill:BAABNQAECn8dAAIXAAgKhRdSIQDZAQAXAAgKhRdSIQDZAQAAAA==.Fathermoses:BAAANQAECggIDwAAAA==.',
Fi='Fitco:BAAANQAECgQIBQAAAA==.',
Fl='Flokii:BAAANQADCgEIAQAAAA==.',
Fr='Frantecks:BAAANQAECgYIBgAAAA==.Frost:BAAANQAECgIJAgABNQAFFAcIFQAgAPMUAA==.Frostmon:BAABNQAECn9DAAIDAAoKpiCYCwCaAgADAAoKpiCYCwCaAgAAAA==.Frostyaf:BAAANQADCgIIAgAAAA==.',
Fu='Furbee:BAAANQAECggIBgAAAA==.',
Ga='Galeandra:BAABNQAECn8ZAAIUAAoKXwXNIwAqAQAUAAoKXwXNIwAqAQAAAA==.Gambas:BAAANQAECgQIAwAAAA==.Garim:BAABNQAECn8hAAINAAgKbw4lGgDBAQANAAgKbw4lGgDBAQAAAA==.Gaztingo:BAABNQAECn8tAAMbAAoKhQ7ARwDgAQAbAAoKhQ7ARwDgAQAUAAIKcAK2dAA9AAAAAA==.',
Gh='Ghostbanri:BAAANQADCgEIAQAAAA==.',
Gi='Gildor:BAAANQAECgEIAQAAAA==.Giox:BAAANQADCgMIAwAAAA==.Girthshock:BAAANQADCgcIBwABNQAECgcIEAABAAAAAA==.',
Gn='Gnar:BAAANQADCgcICAAAAA==.',
Go='Gobi:BAABNQAECn8nAAIhAAoKfRzrNABQAgAhAAoKfRzrNABQAgAAAA==.Gowtherpunch:BAABNQAECn9CAAIiAAoK2w98CACbAQAiAAoK2w98CACbAQAAAA==.',
Gr='Gravewynd:BAAANQADCggIEAAAAA==.Grimsy:BAABNQAECn8nAAIjAAoKBRf3MwBHAgAjAAoKBRf3MwBHAgAAAA==.Grogg:BAAANQADCgUIBQAAAA==.Gruxxiron:BAAANQAECgQIBgABNQAECgoKLQAGAKsSAA==.',
Gu='Guerriero:BAAANQAECgUIBQABNQAECgoKFQADAGcHAA==.Gulnn:BAABNQAECn8tAAQYAAkKQxlVfwDoAQAYAAgKNBlVfwDoAQAZAAIKYxa+GgBxAAAaAAEKAAA4MAA1AAAAAA==.Gumby:BAAANQADCgEIAQAAAA==.',
Ha='Haelena:BAAANQAECgIIBAAAAA==.Hage:BAAANQADCggIAQAAAA==.Harmossy:BAAANQAECgUJDgAAAA==.',
He='Heartsfang:BAAANQADCgMIBAAAAA==.Heriotza:BAABNQAECn8VAAMDAAoKZwfwgQAWAQADAAcKnAXwgQAWAQAGAAQKQQh4egBcAAAAAA==.',
Ho='Hogmaine:BAAANQADCgUICgAAAA==.Holypaladin:BAABNQAECn8gAAIYAAcK+BkmhwDUAQAYAAcK+BkmhwDUAQAAAA==.',
Ib='Ibrakeforimp:BAAANQAECggIAQAAAA==.',
Ii='Iimit:BAABNQAECn8eAAIcAAkKGBYGOgDRAQAcAAkKGBYGOgDRAQABNQAECgoKLwAkAKYdAA==.',
Il='Illidead:BAACNQAFFH8dAAMhAAcKTiLFBQBnAgAhAAYK0iPFBQBnAgAkAAEKQRyaCgBfAAA1AAQKfzYAAyEACgonJVkqADwDACEACQotJVkqADwDACQAAQr6JGguAFIAAAAA.Illooj:BAACNQAFFH8OAAIbAAYKKyU3DgCrAQAbAAYKKyU3DgCrAQA1AAQKf0EAAxsACgpdJt4BABgEABsACgpWJt4BABgEACUACArFJVwBAEQDAAAA.Ilwen:BAAANQAECgUIBAAAAA==.',
In='Indexes:BAAANQAECgUIDwAAAA==.Inspiration:BAAANQADCgQIDAAAAA==.',
Ir='Ironballs:BAAANQADCgEIAQAAAA==.',
Is='Ist:BAACNQAFFH8HAAIWAAIKOwtJBABXAAAWAAIKOwtJBABXAAA1AAQKfy8AAhYACgp6FMsNAOEBABYACgp6FMsNAOEBAAAA.',
It='Itchigo:BAAANQAECgUIBgAAAA==.Itskamertime:BAAANQAECgIIAQABNQAECgoKQwAOADAdAA==.',
Iv='Ivgorod:BAABNQAECn8YAAIIAAgKKwX0EQDnAAAIAAgKKwX0EQDnAAAAAA==.',
Ja='Jabbadahut:BAAANQAECggIBgAAAA==.Jarhead:BAABNQAECn8bAAIZAAgKjAg4CgD0AAAZAAgKjAg4CgD0AAAAAA==.Jaxtoy:BAAANQADCgYIBgAAAA==.Jaybas:BAAANQADCgEIAQAAAA==.Jazilyne:BAAANQAECgEIAQAAAA==.Jaziriel:BAAANQADCgYIBgAAAA==.',
Je='Jenka:BAAANQAECgMIAwAAAA==.',
Jo='Joleya:BAAANQADCgYICwAAAA==.',
Ju='Judihopps:BAAANQAECgIIAwAAAA==.Justcalmdown:BAAANQAECgYIDgABNQAECgIIAgABAAAAAA==.Justyra:BAAANQAECgQICAABNQAECggIIgAQAIwcAA==.',
Ka='Kalder:BAAANQADCgIJAgABNQAECgYICQABAAAAAA==.Kalloo:BAAANQAECgYIBgABNQAFFAYIDgAbACslAA==.Kambative:BAABNQAECn9DAAMOAAoKMB1YEgBmAgAOAAoKMB1YEgBmAgAJAAUKmBXPRQABAQAAAA==.Kambustable:BAAANQADCggICwABNQAECgoKQwAOADAdAA==.Kammunion:BAAANQAECgcICQABNQAECgoKQwAOADAdAA==.Kamphiyer:BAAANQADCgMIBQABNQAECgoKQwAOADAdAA==.Kamscendance:BAAANQADCggICgABNQAECgoKQwAOADAdAA==.Kanan:BAAANQADCggIFgAAAA==.Kandosii:BAAANQADCgEIAQAAAA==.Kantheal:BAABNQAECn8cAAMVAAgKOhfATgCmAQAVAAgKOhfATgCmAQAXAAEKAAAadQAoAAAAAA==.',
Ke='Keirmania:BAAANQADCgcIBwAAAA==.Kekkan:BAAANQADCgEIAQABNQAECgEIAgABAAAAAA==.',
Ki='Kiagas:BAACNQAFFH8GAAIjAAQKCQMbIQCKAAAjAAQKCQMbIQCKAAA1AAQKfyQAAxMACgqDDj0YABwBACMACgr8DauZANwBABMABgq/CT0YABwBAAE1AAQKAggCAAEAAAAA.Kimbrawly:BAAANQADCgYIBgAAAA==.',
Kr='Kravex:BAABNQAECn81AAIOAAoK+BIbHQDnAQAOAAoK+BIbHQDnAQAAAA==.Kreynar:BAAANQAECgQJBAABNQAECgoKNQAOAPgSAA==.Krrayt:BAAANQAECgQICwAAAA==.',
Ku='Kukoc:BAAANQAECgcIEgAAAA==.',
Ky='Kylana:BAAANQADCgYICwABNQAECgkJLgAJAJATAA==.Kyriel:BAABNQAECn8zAAIeAAoKlh1AGQDAAgAeAAoKlh1AGQDAAgAAAA==.',
['Ké']='Kélly:BAAANQAECggICAAAAA==.',
La='Laayna:BAABNQAECn8VAAIMAAcKFA9EqwA9AQAMAAcKFA9EqwA9AQAAAA==.Lanta:BAAANQAECggIEQAAAA==.Larayvia:BAABNQAECn8kAAIEAAoKJwmkkADoAQAEAAoKJwmkkADoAQAAAA==.',
Le='Leesala:BAABNQAECn8xAAIeAAoKhBgGLQA/AgAeAAoKhBgGLQA/AgAAAA==.Leiman:BAAANQAECgQIDAAAAA==.Leymonte:BAAANQADCgMIAwAAAA==.',
Lg='Lg:BAABNQAECn82AAMdAAkKrCDvCgAyAwAdAAkK1x7vCgAyAwAcAAgKKBnLJQA6AgABNQAECgIIAgABAAAAAA==.',
Li='Lic:BAABNQAECn8hAAIEAAcK7g6QqwAXAQAEAAcK7g6QqwAXAQAAAA==.Lilbitty:BAAANQADCgEIAQAAAA==.Lilililil:BAABNQAECn8yAAMMAAoK4xqFHQBYAgAMAAoK4xqFHQBYAgAeAAIKkBGkwABqAAAAAA==.Lillabet:BAAANQAECgQICgAAAA==.Lilpoo:BAAANQAFFAIIAgAAAA==.Limpydk:BAAANQADCgUIBQABNQAECgcIEAABAAAAAA==.Limpylock:BAAANQAECgYIDQABNQAECgcIEAABAAAAAA==.Limpypal:BAAANQAECgcIEAAAAA==.Lispeth:BAABNQAECn8fAAQQAAgKxwg6QgA9AQAQAAgKxwg6QgA9AQARAAEKAADZmwAnAAAWAAIKoAT2NwAfAAAAAA==.',
Lo='Lockém:BAAANQABCgYIBwAAAA==.Longtrang:BAAANQADCgMIBAAAAA==.Loriander:BAAANQADCgQIBAAAAA==.',
Lu='Luckyleaf:BAAANQAECgUIBAAAAA==.Lunaaris:BAAANQAECggIDwAAAA==.',
Ma='Macallan:BAAANQAECgUIBwAAAA==.Magifur:BAABNQAECn8cAAIhAAgKABITzADuAQAhAAgKABITzADuAQAAAA==.Magnakilro:BAABNQAECn8xAAIEAAgKVRWJfgAQAgAEAAgKVRWJfgAQAgAAAA==.Magnomar:BAAANQADCgcIDgAAAA==.Maisy:BAAANQADCgUIBwAAAA==.Malditto:BAAANQADCgIIAgAAAA==.Maleficus:BAAANQAECgYIDwAAAA==.Mamoswine:BAAANQADCgEIAgAAAA==.Mareki:BAAANQADCggIDQAAAA==.Markdfordeth:BAAANQADCgcIBwAAAA==.Mattyfu:BAAANQAECgYIDQAAAA==.Maxrogue:BAAANQADCgUIBQABNQAECggIJwAKALINAA==.Mazikeen:BAAANQAECgcIEQAAAA==.',
Me='Meatsupreme:BAACNQAFFH8GAAICAAEKTgxZLAA5AAACAAEKTgxZLAA5AAA1AAQKfygAAgIACgrQEu+kANcBAAIACgrQEu+kANcBAAAA.Meepin:BAABNQAECn81AAQVAAoKTh7OOgB5AgAVAAkKlB3OOgB5AgACAAgKBRNsoQDeAQAXAAgKHApsKQD0AAAAAA==.Merdoc:BAAANQAECgUIBwAAAA==.Mesophistole:BAAANQADCgUIDQABNQAECgUIDwABAAAAAA==.Mesopunchy:BAAANQAECgUIDwAAAA==.Mesopyro:BAAANQADCgMIBgABNQAECgUIDwABAAAAAA==.',
Mi='Miamore:BAAANQADCggICAAAAA==.Microchyp:BAAANQADCgEIAQAAAA==.Mileenä:BAAANQAECggIAgAAAA==.Milemarker:BAABNQAECn8VAAIVAAgK2QZIiwB6AQAVAAgK2QZIiwB6AQAAAA==.Mindstorm:BAAANQADCggICAAAAA==.Misstwizted:BAABNQAECn8XAAMYAAcKfwTK1wAaAQAYAAcKfgTK1wAaAQAaAAIK5AEZKwBBAAAAAA==.',
Mo='Mohinu:BAAANQAECgcIDwAAAA==.Mojodaemon:BAAANQADCgUIBgAAAA==.Molag:BAAANQAECgIIAgAAAA==.Moocowmoo:BAAANQADCggIDgABNQAECggIIAAYAPgZAA==.Moondevil:BAAANQADCgYIDQAAAA==.Mordryn:BAAANQADCgEIAQAAAA==.Morta:BAEBNQAECn8kAAIEAAkKfR1SRAAQAgAEAAkKfR1SRAAQAgAAAA==.Mortkavaliro:BAAANQADCgYIBgABNQAECgoKFQADAGcHAA==.',
Mu='Mugzy:BAAANQAECggIDwAAAA==.Muted:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.',
My='Mygrane:BAAANQADCgEIAQAAAA==.',
['Mö']='Mörph:BAAANQAECgMIAwABNQAECgkJHAAVAEobAA==.',
Na='Nanérs:BAAANQAECgUIBgABNQAFFAYIEQAOAGgcAA==.Narrodus:BAABNQAECn8WAAIWAAoKvB3cAwCEAgAWAAoKvB3cAwCEAgAAAA==.Nasht:BAAANQADCggICgAAAA==.Nasun:BAAANQADCgQIBQAAAA==.Nataku:BAABNQAECn8YAAIOAAcKswj7ZQA1AQAOAAcKswj7ZQA1AQAAAA==.',
Ne='Nedeen:BAAANQADCgEIAgAAAA==.Neelix:BAAANQAECgEIAQAAAA==.Nezzick:BAABNQAECn85AAMMAAoKbxejOwCHAgAMAAoKbxejOwCHAgAeAAgK2AsplgBQAQAAAA==.',
Ni='Nicholasrage:BAAANQABCgQIBAAAAA==.Nidalap:BAAANQADCgEIAQAAAA==.Nightreaper:BAAANQADCggIQgAAAA==.Nightsinger:BAAANQAECgIIAQAAAA==.Nikkohan:BAAANQAECgQIBAAAAA==.Nimbus:BAACNQAFFH8bAAMMAAcKPBccAwB6AgAMAAcKPBccAwB6AgAeAAEKXgHEKwBGAAA1AAQKf9IAAgwACgqlJvkAAPkDAAwACgqlJvkAAPkDAAAA.Nixy:BAAANQAECgcIBwAAAA==.',
No='Nomns:BAABNQAECn8bAAIEAAkKAB85LQBfAgAEAAkKAB85LQBfAgAAAA==.Normel:BAAANQAECgEIAQAAAA==.Noz:BAAANQAECgIIBAABNQAECggIGwACACwfAA==.',
Nr='Nrvous:BAAANQADCgIIAgAAAA==.',
Nu='Nuid:BAAANQAECggICQAAAA==.Numbers:BAABNQAECn8WAAIQAAoKLQ8MIQBgAQAQAAoKLQ8MIQBgAQAAAA==.',
Ny='Nytesage:BAACNQAFFH8RAAImAAYKnCQuAACsAQAmAAYKnCQuAACsAQA1AAQKfycAAiYACQqKJikAANoDACYACQqKJikAANoDAAAA.',
['Nä']='Näners:BAAANQAECgIIAQABNQAFFAYIEQAOAGgcAA==.',
['Në']='Nëvërmind:BAABNQAECn85AAIXAAoKDh3QDAAsAgAXAAoKDh3QDAAsAgAAAA==.',
['Nì']='Nìghtcat:BAAANQAECgYIDAAAAA==.',
Oa='Oakrot:BAAANQADCgEIAQAAAA==.',
Or='Orgrom:BAAANQAECggICAAAAA==.',
Oz='Ozgar:BAABNQAECn8XAAMUAAYK5hX1JgAQAQAUAAYK5hX1JgAQAQAlAAEKkAgeLgApAAAAAA==.Ozo:BAAANQADCgIIAwAAAA==.',
Pa='Painavolian:BAABNQAECn9NAAIhAAoKhR+QMQAoAwAhAAoKhR+QMQAoAwAAAA==.Palcris:BAAANQADCgcIBwAAAA==.Paxren:BAAANQADCgEIAQAAAA==.',
Pe='Peeches:BAAANQAECgYIBQAAAA==.Pelonis:BAAANQADCgYICgAAAA==.Penthesilea:BAAANQAECgQIAwAAAA==.',
Ph='Pheayre:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Phoenixdówn:BAABNQAECn8oAAIeAAgKxiGyHACmAgAeAAgKxiGyHACmAgAAAA==.Phoosa:BAAANQADCgEIAQAAAA==.',
Pi='Pingpong:BAABNQAECn8yAAQfAAkKehpuIAAqAgAfAAkKehpuIAAqAgAiAAcKUw69DAAvAQAFAAEKBQOtVAAgAAAAAA==.Pisspadpanda:BAABNQAECn8zAAMYAAoKIRtAWwBFAgAYAAoKiBpAWwBFAgAaAAQKWBXBEwAPAQAAAA==.',
Pl='Plungsnipes:BAAANQADCggIFAABNQAECggICQABAAAAAA==.',
Po='Poggies:BAACNQAFFH8PAAMmAAcKtCA5AACCAQAhAAYKfSBpFgDEAQAmAAQKvhs5AACCAQA1AAQKfxsAAyYACgpcJVABAMECACEACgpuJIQyACYDACYACAojI1ABAMECAAAA.Potatodh:BAAANQAECgEIAgAAAA==.Potatolock:BAABNQAECn8XAAQYAAgK5RU1VACeAQAYAAgK7xQ1VACeAQAaAAQKRw00FAAIAQAZAAIKPhT0LgA8AAAAAA==.Poundtown:BAAANQADCgEIAQAAAA==.',
Pr='Praynes:BAABNQAECn8/AAIbAAoKKxxNKgBsAgAbAAoKKxxNKgBsAgAAAA==.',
Pu='Pupperputh:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Puppet:BAAANQADCgEIAQAAAA==.',
Py='Pylanora:BAAANQADCgMIAwAAAA==.',
Qu='Quinnx:BAAANQADCgYIBwAAAA==.',
Ra='Rach:BAABNQAECn80AAIEAAoKXRrQKQBsAgAEAAoKXRrQKQBsAgAAAA==.Rael:BAAANQADCgIJAgAAAA==.Ranoe:BAAANQAECgIIAwABNQAECgoKLwAkAKYdAA==.Rathalos:BAAANQABCgIIAgAAAA==.Raxity:BAABNQAECn8fAAIbAAoKBBolHQDBAgAbAAoKBBolHQDBAgAAAA==.Raxxity:BAAANQAECggICwAAAA==.Razji:BAABNQAECn8rAAMLAAoKEhyAGgCBAgALAAgK+R+AGgCBAgAEAAUK0Ba68wAaAQAAAA==.',
Re='Redmg:BAAANQADCgUIDQABNQAECgMIAwABAAAAAA==.',
Ri='Riete:BAABNQAECn8nAAIaAAgKkhHECQDjAQAaAAgKkhHECQDjAQAAAA==.Rinoa:BAABNQAECn8xAAIhAAcKoAtejwBZAQAhAAcKoAtejwBZAQAAAA==.',
Ro='Rochallie:BAAANQAECgMIDAAAAA==.Rockii:BAAANQADCgYIBgAAAA==.Rocknwolf:BAABNQAECn8fAAIPAAoK7we5FgAaAQAPAAoK7we5FgAaAQAAAA==.Rokd:BAABNQAECn8jAAIXAAkKHyHwCAAOAwAXAAkKHyHwCAAOAwAAAA==.Rosalee:BAEANQADCgEIAQABNQAECgcIEgABAAAAAA==.Roscoelock:BAABNQAECn8WAAMZAAcKfhZ1IABtAQAZAAUK4Rt1IABtAQAYAAUKEwzV9gDdAAAAAA==.Roxxann:BAAANQADCgYIBgAAAA==.',
Ru='Ruibaron:BAAANQAECgEIAQAAAA==.Rumur:BAAANQADCgYIBgABNQAECgcIIwADAD4PAA==.',
['Rà']='Ràidèn:BAAANQADCgcIBwABNQAECgoKPQAeALYdAA==.',
['Rá']='Ráyne:BAAANQAECgEIAQAAAA==.',
Sa='Sadeel:BAABNQAECn9BAAMaAAoKVRXxBAACAgAaAAoKJxXxBAACAgAYAAcKlAxtsgBrAQAAAA==.Sadewolf:BAABNQAECn8jAAMQAAoKDSD3FAC+AgAQAAkKuCH3FAC+AgARAAQKHxLAQwDmAAAAAA==.Salvadore:BAAANQADCggICAAAAA==.Samentoni:BAACNQAFFH8HAAIVAAIKzRATIwCAAAAVAAIKzRATIwCAAAA1AAQKfywAAhUACgo3GLJAAGICABUACgo3GLJAAGICAAAA.Samgal:BAAANQAECgYIEAAAAA==.Sampsyn:BAAANQADCgEIAgAAAA==.Sanctalux:BAAANQADCgQICQAAAA==.Sansura:BAAANQAECggICQAAAA==.Sasha:BAAANQAECgMICAAAAA==.Satyra:BAABNQAECn8iAAIQAAgKjBzjHwBPAgAQAAgKjBzjHwBPAgAAAA==.Saurphang:BAACNQAFFH8SAAMDAAUKrhpoBAAKAQADAAQKrhpoBAAKAQAGAAEKAABvPgAWAAA1AAQKfz0AAgMACgp/IVUPADwDAAMACgp/IVUPADwDAAAA.',
Sc='Scamanes:BAAANQAECgYIDAAAAA==.',
Se='Semperfi:BAAANQADCgEIAQAAAA==.Severis:BAAANQADCgEIAQAAAA==.',
Sh='Shadora:BAAANQAECgcIDgAAAA==.Shadowwizard:BAABNQAECn9HAAIZAAoKNg5MBgBLAQAZAAoKNg5MBgBLAQAAAA==.Shadybrat:BAAANQAECgcICAABNQAECgoKNgAEAK4OAA==.Shaladin:BAAANQAECggIEAAAAA==.Shidan:BAABNQAECn89AAIeAAoKth18FgDXAgAeAAoKth18FgDXAgAAAA==.Shmeepin:BAAANQAECgIIAgAAAA==.Shockaho:BAAANQAECgUIBwAAAA==.Shockchalk:BAACNQAFFH8cAAINAAgKryAyAADNAgANAAgKryAyAADNAgA1AAQKf0AAAg0ACgrvJn4AAN8DAA0ACgrvJn4AAN8DAAAA.Shocknorris:BAAANQAECgIIBAABNQAECgQIBQABAAAAAA==.Shrooclaw:BAAANQAECgIIAgAAAA==.Shulk:BAABNQAECn8UAAICAAgK9QsUvwCeAQACAAgK9QsUvwCeAQAAAA==.',
Si='Sibbiah:BAEANQAECgcIEgAAAQ==.Silanre:BAABNQAECn8eAAIhAAYKrRTEtwAMAQAhAAYKrRTEtwAMAQAAAA==.',
Sk='Skaðï:BAACNQAFFH8MAAILAAYKfhdsDQBnAQALAAYKfhdsDQBnAQA1AAQKf1IABAsACgqHIlAEAP8CAAsACgqHIlAEAP8CAAQAAwrQAI9AAWEAACcAAQolDFoQAEAAAAAA.',
Sl='Slizzard:BAAANQADCgIIAgABNQAFFAYIDwADAKYSAA==.',
Sm='Smalldrogø:BAAANQADCggICAAAAA==.',
Sp='Spadesrage:BAAANQAECgUIEgAAAA==.Spadestree:BAAANQADCgYICgAAAA==.Spash:BAAANQADCggIEAAAAA==.Spicyycurryy:BAABNQAECn8jAAIjAAgKPBmcggAVAgAjAAgKPBmcggAVAgAAAA==.Splashback:BAAANQADCgEIAQAAAA==.',
St='Staggerlee:BAAANQADCgEIAQAAAA==.Staticshock:BAAANQADCgUICAABNQAECggICQABAAAAAA==.Strahm:BAABNQAECn8nAAIKAAgKsg0fKwD6AAAKAAgKsg0fKwD6AAAAAA==.Strehm:BAAANQADCgYIDAABNQAECggIJwAKALINAA==.Stryhm:BAAANQADCgQIBwABNQAECggIJwAKALINAA==.',
Su='Sulfass:BAAANQABCgIIAgAAAA==.Supërman:BAAANQABCgcICQAAAA==.Surai:BAABNQAECn8bAAIeAAkK2yB2DwBIAwAeAAkK2yB2DwBIAwABNQAFFAQIBgAcAMoMAA==.',
Sy='Sylryn:BAAANQADCgQIBAAAAA==.Sylvery:BAAANQADCgEIAQAAAA==.Sylvexa:BAAANQAECgUIBwAAAA==.Symple:BAAANQAECgEIAgAAAA==.Syns:BAAANQAECgIIAgAAAA==.Synz:BAAANQAECgIIAgAAAA==.Syssare:BAABNQAECn8cAAIRAAgKrx2AJwCSAQARAAgKrx2AJwCSAQAAAA==.',
Ta='Tacpally:BAAANQADCgYIFwAAAA==.Talamor:BAAANQADCgMJAwAAAA==.Talasam:BAAANQADCgQIBAAAAA==.Talisman:BAAANQADCggICAAAAA==.Tandsonnara:BAAANQAECggIAQAAAA==.Tastetickle:BAABNQAECn9EAAIhAAoK+BpJNQBOAgAhAAoK+BpJNQBOAgAAAA==.Tazdrin:BAABNQAECn9DAAIoAAoK/BXPAQAkAgAoAAoK/BXPAQAkAgAAAA==.Taze:BAABNQAECn8XAAQOAAgKrB4BFwArAgAOAAgKrB4BFwArAgAJAAMK2By3VAC1AAAKAAMKRg1oVgBJAAAAAA==.',
Te='Telidrus:BAACNQAFFH8GAAMkAAMK2REvCQCMAAAhAAMKlg9AOwDXAAAkAAIKxg8vCQCMAAA1AAQKfyQABCQACQqpIC8MAPkBACEACAp6HdCaAEsCACQABwpBHi8MAPkBACYAAgroDlMJAHUAAAAA.Teneturadvys:BAAANQADCgQIBgABNQAECggIBwABAAAAAA==.Terrax:BAAANQADCgQIBgAAAA==.',
Th='Thepoacher:BAAANQAECgUIBwABNQAECgkJFgAGAKATAA==.Thicc:BAAANQADCgEIAQAAAA==.Thicchunter:BAABNQAECn8+AAILAAoK1CBCCwAkAwALAAoK1CBCCwAkAwAAAA==.Thiccmage:BAABNQAECn8YAAIhAAgKXxEhawCtAQAhAAgKXxEhawCtAQAAAA==.Thiccwiggy:BAAANQADCgMIAwABNQAECgYIDQABAAAAAA==.Thuk:BAABNQAECn8VAAMSAAkKEhDBEQBgAQASAAcKahPBEQBgAQAjAAgKYAgR2wA3AQAAAA==.Thukwarlock:BAAANQADCgEIAQAAAA==.Thunderbug:BAAANQADCggICAAAAA==.',
To='Topaze:BAABNQAECn8cAAMVAAkKShuzKADFAgAVAAkKShuzKADFAgAXAAEKAAAcdgAnAAAAAA==.Totemmonster:BAAANQABCgIIAgAAAA==.',
Tr='Trancendantx:BAAANQAECgEIAQAAAA==.Tripx:BAACNQAFFH8YAAMCAAYKMxGFDACCAQACAAUKZBGFDACCAQAXAAEKnRDsDABHAAA1AAQKfzIAAwIACgrsHhYoAJkCAAIACgrsHhYoAJkCABcAAQoAADJtAAAAAAAA.Tripxed:BAABNQAECn88AAMOAAoKbRkYHwDSAgAOAAoKbRkYHwDSAgAPAAEKWgqVQAA5AAABNQAFFAYIGAACADMRAA==.Trishan:BAAANQAECgQIBwAAAA==.Trolk:BAAANQADCgUIBwAAAA==.Tronklock:BAAANQADCgEIAQAAAA==.Tronko:BAABNQAECn8jAAMeAAoK6RTdJQBnAgAeAAoK6RTdJQBnAgAMAAEKNgOnQgEtAAAAAA==.Truthjustice:BAAANQADCggIEwAAAA==.',
Tu='Tullip:BAAANQAECgEIAgAAAA==.Turntsnaco:BAABNQAECn9IAAMcAAoK/ByzJgA0AgAcAAkKcx2zJgA0AgAdAAYKQBVOZQAeAQAAAA==.Turyon:BAAANQADCgEIAQAAAA==.',
Tw='Twiztedfaith:BAAANQADCgYIBwAAAA==.',
Tz='Tzifora:BAEANQAECgEIAQABNQAECgcIEgABAAAAAA==.',
Ul='Ulhume:BAAANQADCgEJAQABNQAECgoKNQAOAPgSAA==.',
Un='Unafhaen:BAAANQADCgQIBAAAAA==.Unaverse:BAAANQAECgUICQAAAA==.',
Ur='Urp:BAAANQAECgMIDAAAAA==.',
Us='Usmc:BAAANQAECgYIBQAAAA==.Usmccpl:BAAANQADCgYICQAAAA==.',
Va='Valengarde:BAABNQAECn8ZAAICAAoKVBdGjgAIAgACAAoKVBdGjgAIAgAAAA==.Valentin:BAAANQADCgEIAQAAAA==.Valhalia:BAAANQADCgEIAQAAAA==.Vanderneuker:BAAANQAECgQIBwABNQAFFAYIDwADAKYSAA==.Vanero:BAAANQAECgcIBQAAAA==.Vangoon:BAEBNQAECn8zAAMdAAoKXSAsCQBHAwAdAAkKJSEsCQBHAwAcAAgKohhyPADGAQAAAA==.Vanmonk:BAAANQAECggIDAAAAA==.Vann:BAAANQADCgQICAAAAA==.Vannix:BAABNQAECn9AAAIUAAoKfSIfCADDAgAUAAoKfSIfCADDAgAAAA==.',
Ve='Veldrys:BAAANQAECgUIBQABNQAECgoKNQAOAPgSAA==.Velkanos:BAAANQADCgQIBQAAAA==.Velkhaz:BAAANQADCgEIAQAAAA==.Vereena:BAAANQAECgUIDgAAAA==.Vesstar:BAAANQADCgEIAQAAAA==.',
Vi='Vigo:BAAANQAECggICQAAAA==.Violet:BAAANQADCgMIAwAAAA==.Virmethir:BAABNQAECn8dAAIIAAYKiBdIGwCVAQAIAAYKiBdIGwCVAQAAAA==.',
Vo='Voltaren:BAAANQAECgIJAgAAAA==.',
Wa='Waq:BAAANQADCgcIBwAAAA==.',
Wh='Whtmg:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.',
Wi='Winterbreeze:BAAANQADCgQICgAAAA==.Wiwi:BAACNQAFFH8PAAMDAAYKphKDEQDyAAADAAMKfBmDEQDyAAAgAAQK2xAmEACjAAA1AAQKf1MAAyAACgrZI/wMANACACAACQqMI/wMANACAAMACApfG7ZMAOIBAAAA.',
Wo='Woopie:BAAANQAECgIIAQAAAA==.',
Wu='Wukøng:BAAANQADCgEIAQAAAA==.',
Xa='Xake:BAAANQAECgUICgAAAA==.Xares:BAABNQAECn8vAAMkAAoKph0VBgAzAgAkAAoKph0VBgAzAgAhAAYKiw0kIAFWAQAAAA==.',
Xe='Xenp:BAABNQAECn87AAMXAAoKBRifFwA9AgAXAAoKBRifFwA9AgACAAUKrAkOOwHBAAAAAA==.',
Xi='Xiovemm:BAAANQADCgcJBQAAAA==.',
Xu='Xuri:BAABNQAECn8cAAIEAAkKLAxjkADoAQAEAAkKLAxjkADoAQAAAA==.',
Ya='Yalda:BAAANQADCgIIAgAAAA==.',
Yd='Ydriel:BAAANQADCgUIBwAAAA==.',
['Yö']='Yöurfired:BAAANQADCgQICQAAAA==.',
Za='Zake:BAABNQAECn9DAAIEAAoKMR3bJQB9AgAEAAoKMR3bJQB9AgAAAA==.Zalileina:BAAANQADCgMIAwAAAA==.Zantanna:BAAANQAECgMIAgAAAA==.Zappythile:BAABNQAECn8uAAMeAAoKwyB5KADCAgAeAAoKwyB5KADCAgAMAAEKAACJQwEsAAAAAA==.',
Ze='Zealdavir:BAAANQABCgIIAgAAAA==.Zenà:BAAANQAECgEIAQAAAA==.',
Zi='Zigzagoon:BAAANQADCgEIAQAAAA==.',
Zo='Zoz:BAABNQAECn8YAAIkAAoKwgn9DgBXAQAkAAoKwgn9DgBXAQAAAA==.',
Zu='Zulfrik:BAABNQAECn8yAAMhAAoKkBXTYADKAQAhAAoKXRPTYADKAQAkAAIKEh2DMwBsAAAAAA==.',
Zy='Zyzy:BAAANQAECgYICQABNQAFFAcIHQAUAP8bAA==.',
['Äh']='Ählis:BAAANQAECgIIAwAAAA==.',
['ße']='ßeef:BAAANQAECggIEQAAAA==.',
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
