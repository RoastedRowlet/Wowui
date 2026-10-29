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

local lookup = {'Unknown-Unknown','Paladin-Retribution','Hunter-BeastMastery','Monk-Mistweaver','DeathKnight-Unholy','DeathKnight-Blood','Evoker-Augmentation','Evoker-Devastation','Druid-Restoration','Druid-Guardian','Hunter-Marksmanship','Shaman-Elemental','Shaman-Enhancement','Druid-Balance','Druid-Feral','DemonHunter-Devourer','DemonHunter-Havoc','Warrior-Protection','Warrior-Fury','Priest-Shadow','Paladin-Holy','Paladin-Protection','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Rogue-Subtlety','Rogue-Assassination','Evoker-Preservation','Shaman-Restoration','Monk-Windwalker','DeathKnight-Frost','Priest-Holy','Mage-Arcane','Monk-Brewmaster','Warrior-Arms','Mage-Frost','Priest-Discipline','DemonHunter-Vengeance','Mage-Fire','Hunter-Survival','Rogue-Outlaw',}
local provider = {region='US',realm='Eonar',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abysseus:BAAANQADCgcIDwAAAA==.',
Ad='Admired:BAAANQAECgEIBQABNQAECgQIDAABAAAAAA==.',
Ae='Aerdrie:BAAANQABCgMIAwAAAA==.Aevelin:BAABNQAECn8YAAICAAoKfw8RngDmAQACAAoKfw8RngDmAQAAAA==.',
Aj='Ajagar:BAAANQAECgIIBAABNQAECgcIEwABAAAAAA==.',
Al='Alamora:BAAANQAECgQIDQAAAA==.Alastair:BAAANQAECggIAgAAAA==.Alathena:BAAANQAECgMIBAAAAA==.Albrect:BAAANQADCgYIBgAAAA==.Alexandrya:BAABNQAECn8wAAIDAAoK8Q3RRwDHAQADAAoK8Q3RRwDHAQAAAA==.Alickdh:BAAANQADCgIIAgABNQAFFAEIAgABAAAAAA==.Almostpanda:BAAANQADCgUIBQABNQAECgoKHgAEAOQNAA==.Altery:BAAANQAECgEIAQAAAA==.',
Am='Ampharos:BAAANQABCgYIBgAAAA==.Amsahunter:BAAANQADCggICAABNQAECgcIFwAFAEUOAA==.Amsroeb:BAABNQAECn8XAAMFAAcKRQ4ONQDtAAAFAAUKBw4ONQDtAAAGAAYKRQptTwCpAAAAAA==.',
An='Anelavenger:BAACNQAFFH8ZAAIHAAYKexf0AgA6AQAHAAYKexf0AgA6AQA1AAQKf1oAAwcACgq2I+gAAK4DAAcACgq2I+gAAK4DAAgABgppDEEjACwBAAAA.Anelblast:BAAANQAECgYIEgABNQAFFAYIGQAHAHsXAA==.Angerwina:BAAANQAECgMICAAAAA==.Annain:BAAANQAECgEIAQAAAA==.',
Ar='Arathor:BAAANQAECgEIAQAAAA==.Ardent:BAAANQAECgUIDgAAAA==.Ardor:BAAANQADCgYICgABNQAECgUIDgABAAAAAA==.Arent:BAABNQAECn8wAAMJAAkKGxL0IAAiAgAJAAkKGxL0IAAiAgAKAAcKdggXIwDxAAAAAA==.Arkanna:BAAANQADCgYIBgAAAA==.Artemislives:BAAANQAECggIDgAAAA==.',
As='Asharia:BAAANQAECgYIDQAAAA==.Ashla:BAAANQADCgIIAgAAAA==.Asilan:BAAANQAECgEIAQAAAA==.Assateague:BAAANQAECgQIDgAAAA==.Astelossa:BAAANQADCggIJwAAAA==.',
['Aë']='Aëro:BAAANQAECgEIAgAAAA==.',
Ba='Bahnna:BAAANQADCgUICAAAAA==.Bananapistol:BAAANQABCgIIBAAAAA==.Barracksbuny:BAAANQAECgYIDwABNQAECgkJFAAGAKATAA==.Barrathfrogy:BAAANQADCgUIDAAAAA==.',
Be='Bebheishel:BAAANQADCgQICwAAAA==.Beefcake:BAAANQADCgYIFQABNQAECgIIBAABAAAAAA==.Bertello:BAAANQAECgQIBAAAAA==.Beserol:BAAANQAECgUICgAAAA==.',
Bi='Biest:BAAANQAECggICQAAAA==.Biggs:BAAANQADCggICQABNQAECggIBgABAAAAAA==.Billy:BAABNQAECn8bAAIEAAgKmBmVGAD0AQAEAAgKmBmVGAD0AQAAAA==.Bilywitchdoc:BAAANQAECgIIBgABNQAECggIIwALAIQgAA==.Bionicle:BAAANQADCgQIBAAAAA==.Biscuít:BAAANQAECggIEwAAAA==.',
Bk='Bk:BAAANQADCgcIDQABNQAECgoKKQAMAIUaAA==.',
Bl='Blasuoff:BAAANQADCgYIBgAAAA==.Blkmg:BAAANQADCgYIBgABNQAECgMIBAABAAAAAA==.Bloodeagle:BAAANQAECggICgAAAA==.Bloodyfate:BAAANQAECgEIAQAAAA==.Bluechalk:BAAANQAECgcIEgABNQAFFAgIHAANAK8gAA==.',
Bo='Boomslap:BAAANQAECggICwAAAA==.Boredom:BAAANQADCggICAAAAA==.Borzoi:BAABNQAECn9FAAICAAkKGSTdKABeAgACAAkKGSTdKABeAgAAAA==.',
Br='Brawne:BAAANQADCgUIBQAAAA==.Brig:BAAANQAECgEIAgAAAA==.',
Bu='Buzzdkt:BAAANQAECgEIAQAAAA==.Buzzdruu:BAABNQAECn8hAAQOAAoKCBrQLgBoAgAOAAkK8BjQLgBoAgAPAAMKaRuBHACcAAAKAAEKryEHQABgAAAAAA==.',
['Bó']='Bóg:BAAANQADCgEIAQAAAA==.',
['Bø']='Bønës:BAAANQADCgQIBAAAAA==.',
Ca='Caaniss:BAAANQABCgQIBAAAAA==.Cadeana:BAAANQADCgMIAwAAAA==.Caduceus:BAAANQAECgEIAQAAAA==.Caesus:BAAANQAECgEIAQAAAA==.Cagedancer:BAAANQADCgUICQAAAA==.Callio:BAABNQAECn8uAAIDAAkKwgw3TgCyAQADAAkKwgw3TgCyAQAAAA==.Canus:BAAANQAECggICwAAAA==.Caprisunsipz:BAAANQAECggICQAAAA==.Caritta:BAABNQAECn8UAAMQAAcK/hSpPgBVAQAQAAYKSRCpPgBVAQARAAMKqxaubADGAAAAAA==.Cathillex:BAABNQAECn8UAAMSAAcKjRaXEQAhAQASAAcKjRaXEQAhAQATAAEKVBHSMQA5AAAAAA==.Caycay:BAACNQAFFH8KAAIRAAUKaxnPCgB2AQARAAUKaxnPCgB2AQA1AAQKf0QAAhEACgp/I4ECAM4DABEACgp/I4ECAM4DAAAA.',
Ce='Celestian:BAAANQAECggICQAAAA==.Cels:BAAANQAECgcICAAAAA==.',
Ch='Chillbros:BAABNQAECn8iAAMMAAoKwCSFGgAqAwAMAAkKWiWFGgAqAwANAAgKexuiFQAOAgAAAA==.Churd:BAACNQAFFH8GAAIUAAIK8QtHFQB2AAAUAAIK8QtHFQB2AAA1AAQKfygAAhQACgpfFLwfAD0CABQACgpfFLwfAD0CAAAA.Chypnotic:BAABNQAECn8tAAIDAAkKXxkARQCdAgADAAkKXxkARQCdAgAAAA==.Chypotle:BAAANQADCgYJBgAAAA==.Chypster:BAAANQADCgYIBgAAAA==.',
Ci='Ciceroe:BAAANQAECggIDAAAAA==.',
Cl='Cleft:BAABNQAECn8vAAMVAAkKKA12ogA/AQAVAAcK4wh2ogA/AQACAAkKEQgAlgAmAQAAAA==.Clevelandk:BAAANQADCgQIBAAAAA==.Clowwnshoes:BAAANQAECgQICgAAAA==.',
Co='Coalystra:BAABNQAECn83AAIQAAoK+h8ABwCgAgAQAAoK+h8ABwCgAgAAAA==.Cocopuffs:BAAANQAECgYIEwAAAA==.Colostrom:BAABNQAECn85AAIWAAoKXyTkAwDpAgAWAAoKXyTkAwDpAgAAAA==.Coramage:BAAANQAECgcIEgAAAA==.Corliss:BAAANQAECgEIAQAAAA==.Cornholeo:BAAANQAECgEIAwAAAA==.Corruptdata:BAABNQAECn8tAAQXAAoKxBcgKwAFAgAXAAoKxBcgKwAFAgAYAAEKBBTCbwBAAAAZAAEKjQhnMgAwAAABNQAFFAYIGAACADMRAA==.',
Cp='Cpair:BAAANQADCggICAAAAA==.Cplusmc:BAAANQADCgUICAAAAA==.',
Cu='Cuddaloft:BAAANQADCgUIBQAAAA==.',
Da='Darkbeast:BAABNQAECn8XAAIDAAoK3BcqkQDnAQADAAoK3BcqkQDnAQAAAA==.Darkpallo:BAAANQAECgEIAQABNQAECgoKFwADANwXAA==.Darthorc:BAAANQAECgIIBAAAAA==.Daten:BAABNQAECn8yAAICAAoKFQ0dbwB2AQACAAoKFQ0dbwB2AQAAAA==.Daydreemer:BAAANQAECgMIAQAAAA==.Dazlian:BAAANQAECgEIAQAAAA==.Dazshauran:BAAANQADCgUICwAAAA==.',
De='Deadzexcs:BAAANQAECgQICAAAAA==.Decayed:BAABNQAECn8UAAIGAAkKoBNLTADFAQAGAAkKoBNLTADFAQAAAA==.Deladoria:BAAANQAECgYIDAAAAA==.Deragor:BAAANQADCgMIAwABNQAECgMIBAABAAAAAA==.Deus:BAAANQAECgIIAgAAAA==.',
Di='Diagonalli:BAABNQAECn8ZAAIIAAcK6AljDgDxAAAIAAcK6AljDgDxAAAAAA==.Dirk:BAAANQAECgYICgABNQAECggIJQAGAOcEAA==.Dirkdìggler:BAAANQADCgUIBwAAAA==.Divirian:BAAANQAECgcIDwAAAA==.',
Dj='Djdaemon:BAAANQAECgQIBQAAAA==.Djdrakshadow:BAAANQAECgIIAgAAAA==.Djdruidshadw:BAAANQAECgEIBAAAAA==.Djpaly:BAAANQAECgEIAgAAAA==.Djpriest:BAAANQAECgQIBQAAAA==.Djshadow:BAAANQAECgEIAQAAAA==.Djshadowar:BAAANQAECgIIBAAAAA==.Djshadowhunt:BAAANQAECgIIBQAAAA==.Djshadowlock:BAAANQAECgEIAgAAAA==.Djshadowlok:BAAANQAECgIIBQAAAA==.Djshadowrog:BAAANQAECgEIAwAAAA==.Djshadruid:BAAANQAECgIIAwAAAA==.Djshamy:BAAANQAECgIIAwAAAA==.Djshaolin:BAAANQAECgQIBQAAAA==.Djzhadow:BAAANQAECgQIBwAAAA==.Djzhadruid:BAAANQAECgIIBQAAAA==.',
Dk='Dkshadow:BAAANQAECgUICAAAAA==.',
Do='Doofuss:BAAANQAECgEIAwAAAA==.',
Dr='Dragonchalk:BAAANQADCgYIBgABNQAFFAgIHAANAK8gAA==.Drakhadir:BAAANQAECgUIBQAAAA==.Drakmon:BAAANQADCggIFQAAAA==.Draktând:BAABNQAECn8tAAMaAAoKHhV1KwDRAQAaAAoKHhV1KwDRAQAbAAEK5gXjpQAwAAAAAA==.Dreve:BAAANQAECgEIAQAAAA==.Driftier:BAAANQAECgQIBAAAAA==.Drogon:BAEBNQAECn8UAAMcAAkKsA7QJgCDAQAcAAkKsA7QJgCDAQAIAAEKAAByQQAoAAABNQAFFAMIBQAdAFsjAA==.Drunkenpanda:BAABNQAECn8eAAMEAAoK5A3bHgCdAQAEAAoK5A3bHgCdAQAeAAEKAADhewAXAAAAAA==.',
Du='Duneshadow:BAAANQADCgUICQAAAA==.',
Ec='Echö:BAEBNQAECn81AAIRAAkKsBFVIwB6AQARAAkKsBFVIwB6AQAAAA==.',
Eg='Egamnilbog:BAAANQAECgIIAgAAAA==.',
Ei='Eirø:BAAANQAECgUICAABNQAFFAYIDAALAH4XAA==.',
El='Elaine:BAAANQAECgEIAQAAAA==.Elberon:BAAANQAECgIIBAABNQAECgYIDAABAAAAAA==.Eljer:BAAANQADCgMIAwAAAA==.Elnax:BAAANQAECgEIAQAAAA==.Elöhim:BAAANQAECggIBwAAAA==.',
En='Enæmberclad:BAAANQAECgQIBAAAAA==.',
Ep='Epic:BAAANQADCgYICQAAAA==.',
Eq='Eqo:BAAANQAECgUIBQAAAA==.',
Er='Erebosa:BAAANQAECgEIAwAAAA==.',
Fa='Fallden:BAAANQAECgMIAwABNQAECgoKJwAUAEoWAA==.Fatherchill:BAABNQAECn8dAAIWAAgKhRdSIQDZAQAWAAgKhRdSIQDZAQAAAA==.Fathermoses:BAAANQAECgYICwAAAA==.',
Fi='Finnoc:BAAANQAECgEIAgAAAA==.Fitco:BAAANQAECgQIBgAAAA==.',
Fl='Flokii:BAAANQADCgEIAQAAAA==.',
Fr='Frantecks:BAAANQAECgYIBgAAAA==.Freela:BAEANQAECgEIBAABNQAECggIHQADAHwdAA==.Frost:BAAANQAECgIJAgABNQAFFAcIFQAfAPMUAA==.Frostmon:BAABNQAECn86AAIFAAoKkCBfGgDuAgAFAAoKkCBfGgDuAgAAAA==.Frostyaf:BAAANQADCgIIAgAAAA==.',
Fu='Furbee:BAAANQAECggIBgAAAA==.',
Ga='Galeandra:BAABNQAECn8ZAAIUAAoKXwWyGwAvAQAUAAoKXwWyGwAvAQAAAA==.Gallo:BAAANQAECgEIAQAAAA==.Gambas:BAAANQAECgQIBAAAAA==.Garim:BAABNQAECn8fAAINAAgKbw4lGgDBAQANAAgKbw4lGgDBAQAAAA==.Gaztingo:BAABNQAECn8jAAMgAAkKYA1segCrAQAgAAkKYA1segCrAQAUAAIKcAK2dAA9AAAAAA==.',
Gh='Ghostbanri:BAAANQABCgcICAAAAA==.',
Gi='Gildor:BAAANQAECgEIAQAAAA==.Giox:BAAANQADCgMIAwAAAA==.Girthshock:BAAANQADCgcIBwABNQAECgcIEgABAAAAAA==.',
Gn='Gnar:BAAANQADCgcICAAAAA==.',
Go='Gobi:BAABNQAECn8jAAIhAAoKnxqrLgA3AgAhAAoKnxqrLgA3AgAAAA==.Gowtherpunch:BAABNQAECn86AAIiAAoKLQ+eBgCdAQAiAAoKLQ+eBgCdAQAAAA==.',
Gr='Gravewynd:BAAANQADCggIDwAAAA==.Grimsy:BAABNQAECn8lAAIjAAoKKRaKKQA6AgAjAAoKKRaKKQA6AgAAAA==.Grogg:BAAANQADCgQIBAAAAA==.Gruxxiron:BAAANQAECgQICQABNQAECgoKKQAGACsSAA==.',
Gu='Gulnn:BAABNQAECn8mAAQXAAkKQxlVfwDoAQAXAAcKahpVfwDoAQAYAAIKYxaPFQBxAAAZAAEKAAA4MAA1AAAAAA==.Gumby:BAAANQABCgQIBAAAAA==.',
Ha='Haelena:BAAANQAECgIIBAAAAA==.Hage:BAAANQADCggIAQAAAA==.Harmossy:BAAANQAECgUJEQAAAA==.',
He='Heartsfang:BAAANQADCgMIBAAAAA==.Heriotza:BAAANQAECgcIEwAAAA==.',
Ho='Hogmaine:BAAANQAECgEIAQAAAA==.Holypaladin:BAABNQAECn8gAAIXAAcK+BkmhwDUAQAXAAcK+BkmhwDUAQAAAA==.',
Hu='Hunttress:BAAANQAECgEIAQAAAA==.',
Ib='Ibrakeforimp:BAAANQAECggIAQAAAA==.',
Ii='Iimit:BAABNQAECn8XAAIaAAgKMxaXQABeAQAaAAgKMxaXQABeAQABNQAECgoKJAAkAG8dAA==.',
Il='Illidead:BAACNQAFFH8dAAMhAAcKTiLFBQBnAgAhAAYK0iPFBQBnAgAkAAEKQRzcBwBfAAA1AAQKfzIAAyEACgonJVkqADwDACEACQotJVkqADwDACQAAQr6JKslAFIAAAAA.Illooj:BAACNQAFFH8NAAIgAAUK7yQ3DgCrAQAgAAUK7yQ3DgCrAQA1AAQKfzgAAyAACgpdJjwEAKsDACAACgoxIzwEAKsDACUACArFJVwBAEQDAAAA.',
In='Indexes:BAAANQAECgQIDQAAAA==.Inspiration:BAAANQAECgEIAQAAAA==.',
Ir='Ironballs:BAAANQAECgEIAQAAAA==.',
Is='Ist:BAACNQAFFH8FAAImAAIKagl+AwBcAAAmAAIKagl+AwBcAAA1AAQKfysAAiYACgpYE8sNAOEBACYACgpYE8sNAOEBAAAA.',
It='Itchigo:BAAANQAECgQIBQAAAA==.Itskamertime:BAAANQAECgIIAgABNQAECgoKOwAOABUbAA==.',
Iv='Ivgorod:BAABNQAECn8XAAIIAAcKWQWkEADHAAAIAAcKWQWkEADHAAAAAA==.',
Ja='Jabbadahut:BAAANQAECggIBgAAAA==.Jarhead:BAABNQAECn8WAAIYAAgKVgc/CADqAAAYAAgKVgc/CADqAAAAAA==.Jaxtoy:BAAANQADCgYIBgAAAA==.Jaybas:BAAANQABCgIIAgAAAA==.Jazilyne:BAAANQADCgYIAwAAAA==.Jaziriel:BAAANQADCgYIBgAAAA==.',
Je='Jenka:BAAANQAECgMIAwAAAA==.',
Jo='Joleya:BAAANQADCgYICwAAAA==.',
Ju='Judihopps:BAAANQAECgIIAwAAAA==.Justcalmdown:BAAANQAECgYIEgABNQAECgIIAwABAAAAAA==.Justyra:BAAANQAECgQICgABNQAECggIIgAQAIwcAA==.',
Ka='Kalder:BAAANQADCgIJAgABNQAECgUICAABAAAAAA==.Kalloo:BAAANQAECgYIBgABNQAFFAUIDQAgAO8kAA==.Kambative:BAABNQAECn87AAMOAAoKFRsUEQA3AgAOAAoKFRsUEQA3AgAJAAUKmBXPRQABAQAAAA==.Kambustable:BAAANQADCggICwABNQAECgoKOwAOABUbAA==.Kammunion:BAAANQAECgYIBgABNQAECgoKOwAOABUbAA==.Kamphiyer:BAAANQADCgMIBAABNQAECgoKOwAOABUbAA==.Kamscendance:BAAANQAECgEIAQABNQAECgoKOwAOABUbAA==.Kanan:BAAANQADCggIFQAAAA==.Kandosii:BAAANQABCgIIAgAAAA==.Kantheal:BAABNQAECn8bAAMVAAcKJhkTRACFAQAVAAcKJhkTRACFAQAWAAEKAAAadQAoAAAAAA==.',
Ke='Keirmania:BAAANQADCgcIBwAAAA==.',
Ki='Kiagas:BAABNQAECn8fAAMTAAoKSA49GAAcAQAjAAoKwQ2rmQDcAQATAAYKvwk9GAAcAQABNQADCgIIAgABAAAAAA==.Kimbrawly:BAAANQADCgYIBgAAAA==.',
Kr='Kravex:BAABNQAECn8tAAIOAAkKMBKLHgCUAQAOAAkKMBKLHgCUAQAAAA==.Kreynar:BAAANQAECgQJBAABNQAECgkJLQAOADASAA==.Krrayt:BAAANQAECgYIDwAAAA==.',
Ku='Kukoc:BAAANQAECgcIEgAAAA==.',
Ky='Kylana:BAAANQADCgYICwABNQAECgkJLAAJAJATAA==.Kyriel:BAABNQAECn8vAAIdAAoKKx0fEgC9AgAdAAoKKx0fEgC9AgAAAA==.',
['Ké']='Kélly:BAAANQAECggICAAAAA==.',
La='Laayna:BAABNQAECn8VAAIMAAcKFA/SaADUAAAMAAcKFA/SaADUAAAAAA==.Lanta:BAAANQAECggIEQAAAA==.Larayvia:BAABNQAECn8kAAIDAAoKJwmkkADoAQADAAoKJwmkkADoAQAAAA==.',
Le='Leesala:BAABNQAECn8qAAIdAAoKthcGLgDtAQAdAAoKthcGLgDtAQAAAA==.Leiman:BAAANQAECgQIDgAAAA==.Leymonte:BAAANQADCgMIAwAAAA==.',
Lg='Lg:BAABNQAECn8vAAMbAAkKFiDvCgAyAwAbAAkK1x7vCgAyAwAaAAgK1hCoMACxAQABNQAECgIIAwABAAAAAA==.',
Li='Lic:BAABNQAECn8eAAIDAAcK7g7hkQAOAQADAAcK7g7hkQAOAQAAAA==.Lilbitty:BAAANQADCgEIAQAAAA==.Lilililil:BAABNQAECn8pAAMMAAoKhRrwFgBLAgAMAAoKhRrwFgBLAgAdAAEK1RCMyAA0AAAAAA==.Lillabet:BAAANQAECgUICQAAAA==.Lilpoo:BAAANQAECggICQAAAA==.Limpydk:BAAANQADCgUIBQABNQAECgcIEgABAAAAAA==.Limpylock:BAAANQAECgYIEAABNQAECgcIEgABAAAAAA==.Limpypal:BAAANQAECgcIEgAAAA==.Lispeth:BAABNQAECn8ZAAQQAAcKaAk6QgA9AQAQAAcKaAk6QgA9AQARAAEKAADZmwAnAAAmAAIKoAT2NwAfAAAAAA==.',
Lo='Lockém:BAAANQABCgYIBwAAAA==.Longtrang:BAAANQADCgMIAwAAAA==.Loriander:BAAANQADCgQIBAAAAA==.',
Lu='Luckyleaf:BAAANQAECgUIBQAAAA==.Lunaaris:BAAANQAECggIDgAAAA==.Lunastre:BAAANQAECgEIAgAAAA==.',
Ma='Macallan:BAAANQAECgQIBgAAAA==.Magifur:BAABNQAECn8cAAIhAAgKABITzADuAQAhAAgKABITzADuAQAAAA==.Magnakilro:BAABNQAECn8qAAIDAAcKehWJfgAQAgADAAcKehWJfgAQAgAAAA==.Magnomar:BAAANQADCgcIDQAAAA==.Maisy:BAAANQADCgUIBwAAAA==.Malditto:BAAANQADCgIIAgAAAA==.Maleficus:BAAANQAECgUICwAAAA==.Mamoswine:BAAANQAECgEIAwAAAA==.Mareki:BAAANQADCggIDQAAAA==.Markdfordeth:BAAANQADCgcIBwAAAA==.Mattyfu:BAAANQAECgYIDwAAAA==.Maxrogue:BAAANQADCgUIBQABNQAECggIJQAKAOkMAA==.Mazikeen:BAAANQAECgcIDwAAAA==.',
Me='Meatsupreme:BAACNQAFFH8FAAICAAEKTgzdJAA7AAACAAEKTgzdJAA7AAA1AAQKfyQAAgIACgq9Eu+kANcBAAIACgq9Eu+kANcBAAAA.Meepin:BAABNQAECn8zAAQVAAoKTh7OOgB5AgAVAAkKlB3OOgB5AgACAAgKBRNsoQDeAQAWAAgKHAqCIAD4AAAAAA==.Merdoc:BAAANQAECgUICAAAAA==.Mesophistole:BAAANQADCgUIDQABNQAECgQIDQABAAAAAA==.Mesopunchy:BAAANQAECgQIDQAAAA==.Mesopyro:BAAANQADCgMIBgABNQAECgQIDQABAAAAAA==.',
Mi='Miamore:BAAANQADCggICAAAAA==.Microchyp:BAAANQADCgEIAQAAAA==.Milemarker:BAABNQAECn8VAAIVAAgK2QZIiwB6AQAVAAgK2QZIiwB6AQAAAA==.Mindstorm:BAAANQADCggICAAAAA==.Misstwizted:BAABNQAECn8XAAMXAAcKfwTK1wAaAQAXAAcKfgTK1wAaAQAZAAIK5AEZKwBBAAAAAA==.',
Mo='Mohinu:BAAANQAECgcIDQAAAA==.Mojodaemon:BAAANQADCgUIBQAAAA==.Molag:BAAANQAECgMIAwAAAA==.Moocowmoo:BAAANQADCggIDgABNQAECggIIAAXAPgZAA==.Mooli:BAAANQAECgEIAQAAAA==.Moondevil:BAAANQADCgYIDQAAAA==.Morta:BAEBNQAECn8dAAIDAAgKfB1AXQBeAgADAAgKfB1AXQBeAgAAAA==.Mortkavaliro:BAAANQADCgYIBgABNQAECgcIEwABAAAAAA==.',
Mu='Mugzy:BAAANQAECggIBwAAAA==.Muted:BAAANQADCgIIAgABNQAECgIIAwABAAAAAA==.',
['Mö']='Mörph:BAAANQAECgMIAwABNQAECgkJHAAVAEobAA==.',
Na='Nanérs:BAAANQAECgUIBgABNQAFFAYIEQAOAGgcAA==.Narrodus:BAAANQAECgYIEwAAAA==.Nasht:BAAANQAECgEIAgAAAA==.Nasun:BAAANQADCgQIBAAAAA==.Nataku:BAABNQAECn8YAAIOAAcKswj7ZQA1AQAOAAcKswj7ZQA1AQAAAA==.',
Ne='Neelix:BAAANQAECgEIAQAAAA==.Neoth:BAAANQAECgEIAQAAAA==.Nerdofprey:BAAANQAECggIAQAAAA==.Nezzick:BAABNQAECn8wAAMMAAkKcxmjOwCHAgAMAAkKcxmjOwCHAgAdAAgK2wgplgBQAQAAAA==.',
Ni='Nicholasrage:BAAANQAECgEIAQAAAA==.Nidalap:BAAANQADCgEIAQAAAA==.Nightreaper:BAAANQADCggIOgAAAA==.Nightsinger:BAAANQAECgEIAQAAAA==.Nikkohan:BAAANQADCgMIAwAAAA==.Nimbus:BAACNQAFFH8bAAMMAAcKPBccAwB6AgAMAAcKPBccAwB6AgAdAAEKXgHEKwBGAAA1AAQKf8EAAgwACgqIJvkAAPkDAAwACgqIJvkAAPkDAAAA.',
No='Nomns:BAABNQAECn8VAAIDAAgK/B+8LgAlAgADAAgK/B+8LgAlAgABNQAECggIJQAKAEskAA==.Normel:BAAANQAECgEIAQAAAA==.Noz:BAAANQAECgIIBAABNQAECggIGwACACwfAA==.',
Nr='Nrvous:BAAANQADCgIIAgAAAA==.',
Nu='Nuid:BAAANQAECggIAgAAAA==.Numbers:BAAANQAECggIEwAAAA==.',
Ny='Nytesage:BAACNQAFFH8QAAInAAUKfyUuAACsAQAnAAUKfyUuAACsAQA1AAQKfycAAicACQqKJikAANoDACcACQqKJikAANoDAAAA.',
['Nä']='Näners:BAAANQAECgIIAQABNQAFFAYIEQAOAGgcAA==.',
['Në']='Nëvërmind:BAABNQAECn80AAIWAAkKRR0KEACdAgAWAAkKRR0KEACdAgAAAA==.',
['Nì']='Nìghtcat:BAAANQAECgQIDQAAAA==.',
Or='Orgrom:BAAANQAECggICAAAAA==.',
Os='Osiva:BAAANQAECgEIAQAAAA==.',
Oz='Ozgar:BAAANQAECgUIEQAAAA==.Ozo:BAAANQADCgIIAgAAAA==.',
Pa='Painavolian:BAABNQAECn9BAAIhAAoKKh6QMQAoAwAhAAoKKh6QMQAoAwAAAA==.Palcris:BAAANQADCgcIBwAAAA==.Paxren:BAAANQAECgEIAgAAAA==.',
Pe='Peeches:BAAANQAECgYIBgAAAA==.Pelonis:BAAANQADCgUICQAAAA==.Penthesilea:BAAANQAECgEIAgAAAA==.',
Ph='Pheayre:BAAANQADCgYIBgABNQAECgMIBAABAAAAAA==.Phoenixdówn:BAABNQAECn8hAAIdAAcKvCK5HwBHAgAdAAcKvCK5HwBHAgAAAA==.Phoosa:BAAANQADCgEIAQAAAA==.',
Pi='Pingpong:BAABNQAECn8qAAQeAAgK4RtuIAAqAgAeAAgK4RtuIAAqAgAiAAcKOw4pCQBJAQAEAAEKBQOtVAAgAAAAAA==.Pisspadpanda:BAABNQAECn8zAAMXAAoKIRvROQDCAQAXAAoKiBrROQDCAQAZAAQKWBXBEwAPAQAAAA==.',
Pl='Plungsnipes:BAAANQADCggIFAABNQAECggICwABAAAAAA==.',
Po='Poggies:BAACNQAFFH8PAAMnAAcKtCA5AACCAQAhAAYKfSBpFgDEAQAnAAQKvhs5AACCAQA1AAQKfxsAAycACgpcJVABAMECACEACgpuJIQyACYDACcACAojI1ABAMECAAAA.Potatodh:BAAANQAECgEIBQAAAA==.Potatolock:BAABNQAECn8WAAQXAAgKPhPuTAB9AQAXAAgKSRLuTAB9AQAZAAQKRw00FAAIAQAYAAIKPhSCJgA+AAAAAA==.Powerglide:BAAANQAECgEIAQAAAA==.',
Pr='Praynes:BAABNQAECn83AAIgAAoKBxt6LAATAgAgAAoKBxt6LAATAgAAAA==.',
Pu='Pupperputh:BAAANQADCgIIAgABNQAECgIIAwABAAAAAA==.Puppet:BAAANQAECgEIAQAAAA==.',
Py='Pylanora:BAAANQADCgMIAwAAAA==.',
Qu='Quinnx:BAAANQADCgMJAQAAAA==.',
Ra='Rach:BAABNQAECn8qAAIDAAoK0BhJHgByAgADAAoK0BhJHgByAgAAAA==.Rael:BAAANQADCgIJAgAAAA==.Ranoe:BAAANQAECgIIAwABNQAECgoKJAAkAG8dAA==.Rathalos:BAAANQAECgEIAQAAAA==.Raxity:BAABNQAECn8ZAAIgAAkKYRkXUgAtAgAgAAkKYRkXUgAtAgAAAA==.Raxxity:BAAANQAECggICgAAAA==.Razji:BAABNQAECn8jAAMLAAgKhCCAGgCBAgALAAcK9iGAGgCBAgADAAQK8hu68wAaAQAAAA==.',
Re='Redmg:BAAANQADCgUIDQABNQAECgMIBAABAAAAAA==.Renfro:BAAANQAECgEIBQAAAA==.',
Ri='Riete:BAABNQAECn8nAAIZAAgKkhFzBQCFAQAZAAgKkhFzBQCFAQAAAA==.Rinoa:BAABNQAECn8aAAIhAAUKtwnOuADWAAAhAAUKtwnOuADWAAAAAA==.',
Ro='Rochallie:BAAANQAECgMICgAAAA==.Rockii:BAAANQADCgYIBgAAAA==.Rocknwolf:BAABNQAECn8YAAIPAAkKNQa/FQDcAAAPAAkKNQa/FQDcAAAAAA==.Rokd:BAABNQAECn8jAAIWAAkKHyHwCAAOAwAWAAkKHyHwCAAOAwAAAA==.Rosalee:BAEANQABCgIIAgABNQAECgcIEQABAAAAAA==.Roscoelock:BAABNQAECn8WAAMYAAcKfhZ1IABtAQAYAAUK4Rt1IABtAQAXAAUKEwzV9gDdAAAAAA==.Roxxann:BAAANQADCgYIBgAAAA==.',
Ru='Ruibaron:BAAANQAECgEIAQAAAA==.Rumur:BAAANQADCgYIBgABNQAECgcIGwAFANUOAA==.',
['Rà']='Ràidèn:BAAANQADCgcIBwABNQAECgkJNAAdAFYfAA==.',
['Rá']='Ráyne:BAAANQAECgEIAQAAAA==.',
Sa='Sadeel:BAABNQAECn85AAMZAAoKOxW6AgAWAgAZAAoKmRS6AgAWAgAXAAcKlAxtsgBrAQAAAA==.Sadewolf:BAABNQAECn8fAAMQAAoKtx33FAC+AgAQAAgKTyP3FAC+AgARAAQKHxLgNgD6AAAAAA==.Salvadore:BAAANQADCggICAAAAA==.Samentoni:BAACNQAFFH8GAAIVAAIKzRATIwCAAAAVAAIKzRATIwCAAAA1AAQKfygAAhUACgrTFrJAAGICABUACgrTFrJAAGICAAAA.Samgal:BAAANQAECgYIEQAAAA==.Sampsyn:BAAANQABCgYICgAAAA==.Sanctalux:BAAANQADCgQIBgAAAA==.Sansura:BAAANQAECggICQABNQAECgoKQQAMALwSAA==.Sasha:BAAANQAECgMICAAAAA==.Satyra:BAABNQAECn8iAAIQAAgKjBzjHwBPAgAQAAgKjBzjHwBPAgAAAA==.Saurphang:BAACNQAFFH8OAAMFAAUK5BH/BwCdAAAFAAQK5BH/BwCdAAAGAAEKAABvPgAWAAA1AAQKfzgAAgUACgoUIVUPADwDAAUACgoUIVUPADwDAAAA.',
Sc='Scamanes:BAAANQAECgYIDgAAAA==.',
Se='Semperfi:BAAANQABCgYICQAAAA==.Severis:BAAANQADCgEIAQAAAA==.',
Sh='Shadora:BAAANQAECgYIDAAAAA==.Shadowwizard:BAABNQAECn9AAAIYAAkKdQ4+EgDjAQAYAAkKdQ4+EgDjAQAAAA==.Shadybrat:BAAANQAECgcICAABNQAECgoKMAADAPENAA==.Shaladin:BAAANQAECggIEAAAAA==.Shidan:BAABNQAECn80AAIdAAkKVh83HAD9AgAdAAkKVh83HAD9AgAAAA==.Shmeepin:BAAANQAECgIIAgAAAA==.Shockaho:BAAANQAECgUICQAAAA==.Shockchalk:BAACNQAFFH8cAAINAAgKryAyAADNAgANAAgKryAyAADNAgA1AAQKfzwAAg0ACgrWJlAAAHMDAA0ACgrWJlAAAHMDAAAA.Shocknorris:BAAANQAECgIIBQABNQAECgQIBgABAAAAAA==.Shqaukers:BAAANQAECgEIAQAAAA==.Shrooclaw:BAAANQADCgIIAgAAAA==.Shulk:BAABNQAECn8UAAICAAgK9QsUvwCeAQACAAgK9QsUvwCeAQAAAA==.',
Si='Sibbiah:BAEANQAECgcIEQAAAQ==.Silanre:BAABNQAECn8YAAIhAAYKghTfnQAKAQAhAAYKghTfnQAKAQAAAA==.',
Sk='Skaðï:BAACNQAFFH8MAAILAAYKfhdsDQBnAQALAAYKfhdsDQBnAQA1AAQKf0gABAsACgpgIIMHAIICAAsACgpgIIMHAIICAAMAAwrQAI9AAWEAACgAAQolDFUNAEEAAAAA.',
Sl='Slizzard:BAAANQADCgIIAgABNQAFFAYIDwAFAKYSAA==.',
Sm='Smalldrogø:BAAANQADCggICAAAAA==.',
Sp='Spadesrage:BAABNQAECn8WAAIVAAYKrBwJNwDCAQAVAAYKrBwJNwDCAQAAAA==.Spadesrot:BAAANQAECgEIAQAAAA==.Spadestree:BAAANQADCgYICgAAAA==.Spash:BAAANQADCggIEAAAAA==.Spicyycurryy:BAABNQAECn8jAAIjAAgKPBmcggAVAgAjAAgKPBmcggAVAgAAAA==.',
St='Staticshock:BAAANQADCgUICAABNQAECggICwABAAAAAA==.Strahm:BAABNQAECn8lAAIKAAgK6QzvIAABAQAKAAgK6QzvIAABAQAAAA==.Strehm:BAAANQADCgYIDAABNQAECggIJQAKAOkMAA==.Stryhm:BAAANQADCgQIBwABNQAECggIJQAKAOkMAA==.',
Su='Sulfass:BAAANQAECgEIAQAAAA==.Supërman:BAAANQAECgEIAgAAAA==.Surai:BAABNQAECn8bAAIdAAkK2yB2DwBIAwAdAAkK2yB2DwBIAwABNQAFFAQIBgAaAMoMAA==.',
Sy='Sylryn:BAAANQADCgQIBAAAAA==.Sylvexa:BAAANQAECgUICAAAAA==.Symple:BAAANQAECgEIAgAAAA==.Syns:BAAANQAECgIIAgAAAA==.Synz:BAAANQAECgIIAgAAAA==.Syssare:BAABNQAECn8cAAIRAAgKrx3sHQCoAQARAAgKrx3sHQCoAQAAAA==.',
Ta='Tacpally:BAAANQAECgEIAQAAAA==.Talamor:BAAANQADCgMJAwAAAA==.Talasam:BAAANQADCgQIBAAAAA==.Tandsonnara:BAAANQAECggIAgAAAA==.Tastetickle:BAABNQAECn88AAIhAAoKehqVMAAvAgAhAAoKehqVMAAvAgAAAA==.Tazdrin:BAABNQAECn85AAIpAAoK6xSRAQAPAgApAAoK6xSRAQAPAgAAAA==.Taze:BAAANQAECgUIEQAAAA==.',
Te='Telidrus:BAACNQAFFH8GAAMkAAMK2REvCQCMAAAhAAMKlg9AOwDXAAAkAAIKxg8vCQCMAAA1AAQKfyQABCQACQqpIC8MAPkBACEACAp6HdCaAEsCACQABwpBHi8MAPkBACcAAgroDlMJAHUAAAAA.Teneturadvys:BAAANQADCgQIBAABNQAECggICQABAAAAAA==.Terrax:BAAANQAECgEIAQAAAA==.',
Th='Thepoacher:BAAANQAECgQIBAABNQAECgkJFAAGAKATAA==.Thicc:BAAANQABCgQIBAAAAA==.Thicchunter:BAABNQAECn83AAILAAoK1CBCCwAkAwALAAoK1CBCCwAkAwAAAA==.Thiccmage:BAABNQAECn8YAAIhAAgKXxE4UAC9AQAhAAgKXxE4UAC9AQAAAA==.Thiccwiggy:BAAANQADCgMIAwABNQAECgYIDwABAAAAAA==.Thuk:BAAANQAECgcIEgAAAA==.Thukwarlock:BAAANQADCgEIAQAAAA==.Thunderbug:BAAANQADCggICAAAAA==.',
To='Topaze:BAABNQAECn8cAAMVAAkKShuzKADFAgAVAAkKShuzKADFAgAWAAEKAAAcdgAnAAAAAA==.Totemmonster:BAAANQAECgEIAQAAAA==.',
Tr='Trancendantx:BAAANQADCgcIBwAAAA==.Tripx:BAACNQAFFH8YAAMCAAYKMxGFDACCAQACAAUKZBGFDACCAQAWAAEKnRCTCgBKAAA1AAQKfzAAAgIACgptHhUbAKoCAAIACgptHhUbAKoCAAAA.Tripxed:BAABNQAECn88AAMOAAoKbRkYHwDSAgAOAAoKbRkYHwDSAgAPAAEKWgqVQAA5AAABNQAFFAYIGAACADMRAA==.Trishan:BAAANQAECgQIBwAAAA==.Trolk:BAAANQADCgUIBwAAAA==.Tronklock:BAAANQADCgEIAQAAAA==.Tronko:BAABNQAECn8cAAMdAAoKTxNsHwBJAgAdAAoKTxNsHwBJAgAMAAEKNgOnQgEtAAAAAA==.Truthjustice:BAAANQAECgEIAQAAAA==.',
Tu='Tullip:BAAANQAECgEIAgAAAA==.Turntsnaco:BAABNQAECn9EAAMaAAoK/BwvHQAzAgAaAAkKcx0vHQAzAgAbAAYKQBVOZQAeAQAAAA==.Turyon:BAAANQADCgEIAQAAAA==.',
Tw='Twiztedfaith:BAAANQADCgYIBgAAAA==.',
Ul='Ulhume:BAAANQADCgEJAQABNQAECgkJLQAOADASAA==.',
Un='Unafhaen:BAAANQADCgQIBAAAAA==.Unaverse:BAAANQAECgUIBwAAAA==.',
Ur='Urp:BAAANQAECgMICgAAAA==.',
Us='Usmc:BAAANQAECgYIBgAAAA==.Usmccpl:BAAANQADCgYICQAAAA==.',
Va='Valengarde:BAABNQAECn8VAAICAAoKqxZGjgAIAgACAAoKqxZGjgAIAgAAAA==.Valentin:BAAANQABCgIIAgAAAA==.Valhalia:BAAANQABCgIIAgAAAA==.Vanderneuker:BAAANQAECgQIBwABNQAFFAYIDwAFAKYSAA==.Vanero:BAAANQAECgIIAgAAAA==.Vangoon:BAEBNQAECn8pAAMbAAoKXSAsCQBHAwAbAAkKJSEsCQBHAwAaAAUKEhZmYwDQAAAAAA==.Vanmonk:BAAANQAECggICwAAAA==.Vann:BAAANQADCgQIBwAAAA==.Vannix:BAABNQAECn84AAIUAAoKxyEUBgC6AgAUAAoKxyEUBgC6AgAAAA==.',
Ve='Velkanos:BAAANQADCgQIBAAAAA==.Velkhaz:BAAANQABCgYIBgAAAA==.Vereena:BAAANQAECgUIDwAAAA==.Vesstar:BAAANQABCggIFgAAAA==.',
Vi='Vigo:BAAANQAECgIIAwAAAA==.Violet:BAAANQADCgMIAwAAAA==.Virmethir:BAABNQAECn8ZAAIIAAYKiBdIGwCVAQAIAAYKiBdIGwCVAQAAAA==.',
Vo='Voltaren:BAAANQAECgIJAgAAAA==.',
Wh='Whtmg:BAAANQADCgIIAgABNQAECgMIBAABAAAAAA==.',
Wi='Winterbreeze:BAAANQADCgQICgAAAA==.Wiwi:BAACNQAFFH8PAAMFAAYKphKDEQDyAAAFAAMKfBmDEQDyAAAfAAQK2xB6DAClAAA1AAQKf0oAAx8ACgrsH5MSAEsCAB8ACQoTH5MSAEsCAAUACAoQG7ZMAOIBAAAA.',
Wo='Woopie:BAAANQAECgIIAwAAAA==.',
Wu='Wukøng:BAAANQABCgIIAgAAAA==.',
Xa='Xake:BAAANQAECgUIDQAAAA==.Xares:BAABNQAECn8kAAMkAAoKbx1VBAAtAgAkAAoKbx1VBAAtAgAhAAYKiw0kIAFWAQAAAA==.',
Xe='Xenp:BAABNQAECn85AAMWAAoKlxafFwA9AgAWAAoKlxafFwA9AgACAAUKjwkOOwHBAAAAAA==.',
Xi='Xiovemm:BAAANQADCgcJBQAAAA==.',
Xu='Xuri:BAABNQAECn8cAAIDAAkKLAxjkADoAQADAAkKLAxjkADoAQAAAA==.',
Ya='Yalda:BAAANQADCgIIAgAAAA==.',
Yd='Ydriel:BAAANQADCgUIBwAAAA==.',
['Yö']='Yöurfired:BAAANQAECgEIBAAAAA==.',
Za='Zake:BAABNQAECn89AAIDAAoK8RxpFwCaAgADAAoK8RxpFwCaAgAAAA==.Zalileina:BAAANQADCgMIAgAAAA==.Zantanna:BAAANQAECgMIBQAAAA==.Zappythile:BAABNQAECn8lAAMdAAgKNiB5KADCAgAdAAgKNiB5KADCAgAMAAEKAACJQwEsAAAAAA==.Zayiro:BAAANQADCgYIDAAAAA==.',
Ze='Zealdavir:BAAANQAECgEIAgAAAA==.Zenà:BAAANQAECgEIAQAAAA==.',
Zi='Zigzagoon:BAAANQABCgYIBgAAAA==.',
Zo='Zoz:BAAANQAECggIEAAAAA==.',
Zu='Zulfrik:BAABNQAECn8qAAMhAAkKhxaDZgB8AQAhAAkKBBSDZgB8AQAkAAIKEh2DMwBsAAAAAA==.',
Zy='Zyzy:BAAANQAECgYIDAABNQAFFAcIHQAUAP8bAA==.',
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
