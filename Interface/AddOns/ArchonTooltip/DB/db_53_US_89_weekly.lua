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

local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Monk-Mistweaver','Evoker-Augmentation','Evoker-Devastation','Druid-Restoration','Hunter-Marksmanship','Shaman-Elemental','Shaman-Enhancement','Paladin-Retribution','Druid-Balance','DemonHunter-Devourer','DemonHunter-Havoc','Priest-Shadow','Paladin-Holy','Paladin-Protection','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','DeathKnight-Blood','Rogue-Subtlety','Rogue-Assassination','Shaman-Restoration','Monk-Windwalker','DeathKnight-Frost','DeathKnight-Unholy','Priest-Holy','Monk-Brewmaster','Warrior-Arms','Mage-Arcane','Mage-Frost','Priest-Discipline','DemonHunter-Vengeance','Warrior-Fury','Druid-Guardian','Mage-Fire','Rogue-Outlaw','Druid-Feral',}
local provider = {region='US',realm='Eonar',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abysseus:BAAANQADCgcIDwAAAA==.',
Ad='Admired:BAAANQAECgEIAQABNQAECgQIBgABAAAAAA==.',
Ae='Aerdrie:BAAANQABCgMIAwAAAA==.Aevelin:BAAANQAFFAEIAQAAAA==.',
Aj='Ajagar:BAAANQADCgcIKAABNQAECgcIEAABAAAAAA==.',
Al='Alamora:BAAANQAECgIIAwAAAA==.Alastair:BAAANQAECggIAgAAAA==.Alathena:BAAANQAECgMIAwAAAA==.Alexandrya:BAABNQAECn8mAAICAAgK7AtRgQAGAgACAAgK7AtRgQAGAgAAAA==.Alickdh:BAAANQADCgIIAgABNQAFFAEIAQABAAAAAA==.Almostpanda:BAAANQADCgUIBQABNQAECggIHAADAEEOAA==.Altery:BAAANQAECgEIAQAAAA==.',
Am='Ampharos:BAAANQABCgYIBgAAAA==.Amsahunter:BAAANQADCggICAABNQAECgQIBwABAAAAAA==.Amsroeb:BAAANQAECgQIBwAAAA==.',
An='Anelavenger:BAACNQAFFH8QAAIEAAUKHxd1BACLAQAEAAUKHxd1BACLAQA1AAQKf0AAAwQACQqZI+UAAK4DAAQACQqZI+UAAK4DAAUABgppDAMjACwBAAAA.Anelblast:BAAANQAECgUIDAABNQAFFAUIEAAEAB8XAA==.Angerwina:BAAANQAECgIIAgAAAA==.Annain:BAAANQADCgYJCgAAAA==.',
Ar='Arathor:BAAANQADCggIEQAAAA==.Ardent:BAAANQAECgQICAAAAA==.Ardor:BAAANQADCgYICgABNQAECgQICAABAAAAAA==.Arent:BAABNQAECn8jAAIGAAkKGxKdIAAhAgAGAAkKGxKdIAAhAgAAAA==.Arkanna:BAAANQADCgYIBgAAAA==.Artemislives:BAAANQAECggICAAAAA==.',
As='Asharia:BAAANQAECgUICAAAAA==.Ashla:BAAANQADCgIIAgAAAA==.Assateague:BAAANQAECgIIAwAAAA==.Astelossa:BAAANQADCgcIHAAAAA==.',
['Aë']='Aëro:BAAANQADCgYICQAAAA==.',
Ba='Bahnna:BAAANQADCgUIBQAAAA==.Bananapistol:BAAANQABCgIIBAAAAA==.Barracksbuny:BAAANQAECgYICQABNQAECgYIEAABAAAAAA==.Barrathfrogy:BAAANQADCgUIDAAAAA==.',
Be='Bebheishel:BAAANQADCgQICwAAAA==.Beefcake:BAAANQADCgYJFQABNQADCgcIDgABAAAAAA==.Bertello:BAAANQAECgQIBAAAAA==.Beserol:BAAANQADCgYICAAAAA==.',
Bi='Biest:BAAANQAECggIAQAAAA==.Biggs:BAAANQADCggICQABNQAECggIBgABAAAAAA==.Billy:BAAANQAECgcIEAAAAA==.Bilywitchdoc:BAAANQAECgEIAwABNQAECggIHwAHAIQgAA==.Bionicle:BAAANQADCgQIBAAAAA==.Biscuít:BAAANQAECgUICwAAAA==.',
Bk='Bk:BAAANQADCgcIDQABNQAECgkJGwAIAGwYAA==.',
Bl='Blasuoff:BAAANQADCgYIBgAAAA==.Bloodeagle:BAAANQADCggJCAAAAA==.Bloodyfate:BAAANQADCgYIBgAAAA==.Bluechalk:BAAANQAECgcIDQABNQAFFAcIGgAJAEgjAA==.',
Bo='Boomslap:BAAANQAECggICQAAAA==.Borzoi:BAABNQAECn84AAIKAAcKbSRlOgDlAgAKAAcKbSRlOgDlAgAAAA==.',
Br='Brawne:BAAANQADCgUIBQAAAA==.',
Bu='Buzzdruu:BAABNQAECn8YAAILAAgK4RpULgBpAgALAAgK4RpULgBpAgAAAA==.',
['Bó']='Bóg:BAAANQADCgEIAQAAAA==.',
['Bø']='Bønës:BAAANQADCgQIBAAAAA==.',
Ca='Caaniss:BAAANQABCgQIBAAAAA==.Caduceus:BAAANQADCgUIBQAAAA==.Caesus:BAAANQADCgcICwAAAA==.Cagedancer:BAAANQADCgUICQAAAA==.Callio:BAABNQAECn8jAAICAAgKuwq0iAD2AQACAAgKuwq0iAD2AQAAAA==.Canus:BAAANQAECgEIAQAAAA==.Caritta:BAABNQAECn8UAAMMAAcK/hTrPQBVAQAMAAYKSRDrPQBVAQANAAMKqxZNawDGAAAAAA==.Cathillex:BAAANQAECgQICQAAAA==.Caycay:BAACNQAFFH8KAAINAAUKaxmCCgB3AQANAAUKaxmCCgB3AQA1AAQKfzkAAg0ACQrWJHICAM4DAA0ACQrWJHICAM4DAAAA.',
Ce='Celestian:BAAANQAECggIBwAAAA==.',
Ch='Chillbros:BAABNQAECn8dAAMIAAkKtyQkGgAqAwAIAAgKaiUkGgAqAwAJAAgKextmFQAOAgAAAA==.Churd:BAACNQAFFH8FAAIOAAIKigrlFAB2AAAOAAIKigrlFAB2AAA1AAQKfyQAAg4ACQqnEmofAD0CAA4ACQqnEmofAD0CAAAA.Chypnotic:BAABNQAECn8kAAICAAkK3BfWQwCeAgACAAkK3BfWQwCeAgAAAA==.Chypotle:BAAANQADCgYJBgAAAA==.Chypster:BAAANQADCgYIBgAAAA==.',
Ci='Ciceroe:BAAANQAECgEIAQAAAA==.',
Cl='Cleft:BAABNQAECn8fAAMKAAcKIgcT6gBBAQAKAAcKIgcT6gBBAQAPAAcK8wYBoQA/AQAAAA==.Clowwnshoes:BAAANQAECgQICgAAAA==.',
Co='Coalystra:BAABNQAECn8rAAIMAAgK2iBMEQDhAgAMAAgK2iBMEQDhAgAAAA==.Cocopuffs:BAAANQAECgUICwAAAA==.Colostrom:BAABNQAECn8tAAIQAAgKDyXuBQBMAwAQAAgKDyXuBQBMAwAAAA==.Coramage:BAAANQAECgIJAwAAAA==.Corliss:BAAANQAECgEIAQAAAA==.Cornholeo:BAAANQABCgIIBAAAAA==.Corruptdata:BAABNQAECn8eAAQRAAgK5xJmXwA2AgARAAgK5xJmXwA2AgASAAEKBBQvbwBAAAATAAEKjQjwMQAwAAABNQAFFAUIEgAKAGQRAA==.',
Cp='Cpair:BAAANQADCggICAAAAA==.Cplusmc:BAAANQADCgMIAwAAAA==.',
Da='Darkbeast:BAAANQAECgYJDwAAAA==.Darthorc:BAAANQADCgcIDgAAAA==.Daten:BAABNQAECn8kAAIKAAkKDQzqqADJAQAKAAkKDQzqqADJAQAAAA==.Dazshauran:BAAANQADCgUICwAAAA==.',
De='Deadzexcs:BAAANQAECgMIBwAAAA==.Decayed:BAAANQAECgYIEAAAAA==.Deladoria:BAAANQAECgYICgAAAA==.',
Di='Diagonalli:BAAANQAECgQICgAAAA==.Dirk:BAAANQAECgIIBAABNQAECgYIFQAUAJMCAA==.Dirkdìggler:BAAANQADCgUIBwAAAA==.Divirian:BAAANQAECgMIAwAAAA==.',
Dj='Djdaemon:BAAANQADCggIFgAAAA==.Djdrakshadow:BAAANQADCgUIEQAAAA==.Djdruidshadw:BAAANQADCgYIGwAAAA==.Djpaly:BAAANQADCgUIFwAAAA==.Djpriest:BAAANQADCgYIIQAAAA==.Djshadow:BAAANQADCgYIHwAAAA==.Djshadowar:BAAANQADCgYIHgAAAA==.Djshadowhunt:BAAANQADCgUIGAAAAA==.Djshadowlock:BAAANQADCgQIFQAAAA==.Djshadowlok:BAAANQADCgYIHAAAAA==.Djshadowrog:BAAANQAECgEIAQAAAA==.Djshadruid:BAAANQADCgYIEwAAAA==.Djshamy:BAAANQADCgYIFgAAAA==.Djshaolin:BAAANQAECgEIAQAAAA==.Djzhadow:BAAANQADCgUIEAAAAA==.Djzhadruid:BAAANQADCgYIEQAAAA==.',
Dk='Dkshadow:BAAANQADCgcIHAAAAA==.',
Do='Doofuss:BAAANQABCgIIAgAAAA==.',
Dr='Dragonchalk:BAAANQADCgYIBgABNQAFFAcIGgAJAEgjAA==.Drakhadir:BAAANQADCggIDQAAAA==.Drakmon:BAAANQADCggIDAAAAA==.Draktând:BAABNQAECn8fAAMVAAcK5BgKFwAlAgAVAAcK5BgKFwAlAgAWAAEK5gUfogAwAAAAAA==.Dreve:BAAANQABCgIIBAAAAA==.Driftier:BAAANQAECgEIAQAAAA==.Drogon:BAAANQAECgYIDQABNQAECgkJJQAXAL4iAA==.Drunkenpanda:BAABNQAECn8cAAMDAAgKQQ6LHgCdAQADAAgKQQ6LHgCdAQAYAAEKAAC/eQAXAAAAAA==.',
Du='Duneshadow:BAAANQADCgUICQAAAA==.',
Ec='Echö:BAEBNQAECn8rAAINAAgKKBHTOADnAQANAAgKKBHTOADnAQAAAA==.',
Ei='Eirø:BAAANQAECgUICAABNQAFFAUICgAHACQWAA==.',
El='Elaine:BAAANQADCgUIBgAAAA==.Elberon:BAAANQAECgIIAgAAAA==.Elnax:BAAANQADCgYIBgAAAA==.Elöhim:BAAANQAECggIBgAAAA==.',
Ep='Epic:BAAANQADCgYICQAAAA==.',
Eq='Eqo:BAAANQAECgUIBQAAAA==.',
Er='Erebosa:BAAANQABCgQIBAAAAA==.',
Fa='Fallden:BAAANQAECgMIAwABNQAECgkJIgAOAIsXAA==.Fatherchill:BAABNQAECn8dAAIQAAgKhRffIADaAQAQAAgKhRffIADaAQAAAA==.Fathermoses:BAAANQAECgUIBQAAAA==.',
Fi='Fitco:BAAANQAECgQIBQAAAA==.',
Fl='Flokii:BAAANQADCgEIAQAAAA==.',
Fr='Frantecks:BAAANQAECgYIBgAAAA==.Freela:BAEANQADCgUIBQABNQAECgYIEgABAAAAAA==.Frost:BAAANQAECgIJAgABNQAFFAYIEAAZANUSAA==.Frostmon:BAABNQAECn8sAAIaAAkK9yAdGgDuAgAaAAkK9yAdGgDuAgAAAA==.Frostyaf:BAAANQADCgIIAgAAAA==.',
Fu='Furbee:BAAANQAECggIBgAAAA==.',
Ga='Galeandra:BAAANQAECgUICQAAAA==.Gallo:BAAANQADCgYIBgAAAA==.Gambas:BAAANQADCgIIAgAAAA==.Garim:BAABNQAECn8bAAIJAAcK1Q7WGQDBAQAJAAcK1Q7WGQDBAQAAAA==.Gaztingo:BAABNQAECn8fAAMbAAgKqQwaeQCrAQAbAAgKqQwaeQCrAQAOAAIKcAI0cwA9AAAAAA==.',
Gh='Ghostbanri:BAAANQABCgcICAAAAA==.',
Gi='Gildor:BAAANQAECgEIAQAAAA==.Giox:BAAANQADCgMIAwAAAA==.Girthshock:BAAANQADCgcIBwABNQAECgcIEAABAAAAAA==.',
Gn='Gnar:BAAANQADCgcICAAAAA==.',
Go='Gobi:BAAANQAECgcIEgAAAA==.Gowtherpunch:BAABNQAECn8uAAIcAAgKLw89FACcAQAcAAgKLw89FACcAQAAAA==.',
Gr='Gravewynd:BAAANQADCggIDwAAAA==.Grimsy:BAABNQAECn8WAAIdAAgKgBVOhAANAgAdAAgKgBVOhAANAgAAAA==.Grogg:BAAANQADCgQIBAAAAA==.Gruxxiron:BAAANQAECgQIBgABNQAECgkJIQAUAF8TAA==.',
Gu='Gulnn:BAABNQAECn8YAAQRAAkKLxaQfQDoAQARAAcKARiQfQDoAQASAAIKoBFIWQBzAAATAAEKAADCLwA1AAAAAA==.Gumby:BAAANQABCgQIBAAAAA==.',
Ha='Haelena:BAAANQADCgcIKQAAAA==.Hage:BAAANQADCggIAQAAAA==.Harmossy:BAAANQAECgUJDgAAAA==.',
He='Heartsfang:BAAANQADCgMIBAAAAA==.Heriotza:BAAANQAECgcIEAAAAA==.',
Ho='Hogmaine:BAAANQADCgUICQAAAA==.Holypaladin:BAABNQAECn8gAAIRAAcK+BkmhQDVAQARAAcK+BkmhQDVAQAAAA==.',
Hu='Hunttress:BAAANQADCgYIBgAAAA==.',
Ib='Ibrakeforimp:BAAANQAECggIAQAAAA==.',
Ii='Iimit:BAAANQAECgUIDQABNQAECgcIEgABAAAAAA==.',
Il='Illidead:BAACNQAFFH8YAAIeAAYK0iNgBQBnAgAeAAYK0iNgBQBnAgA1AAQKfykAAx4ACQqJJbwpAD0DAB4ACAqhJbwpAD0DAB8AAQr6JOM8AEoAAAAA.Illooj:BAACNQAFFH8MAAIbAAQKhyTMDQCrAQAbAAQKhyTMDQCrAQA1AAQKfyYAAyAACQqZJlkBAEQDABsACAp6JdAOAE0DACAACAq+JVkBAEQDAAAA.',
In='Indexes:BAAANQAECgIIAwAAAA==.Inspiration:BAAANQADCgQICwAAAA==.',
Is='Ist:BAABNQAECn8jAAIhAAkKQxKgDQDhAQAhAAkKQxKgDQDhAQAAAA==.',
It='Itchigo:BAAANQAECgQIBAAAAA==.Itskamertime:BAAANQAECgEIAQABNQAECggIMQALAEwdAA==.',
Iv='Ivgorod:BAAANQAECgQICQAAAA==.',
Ja='Jabbadahut:BAAANQAECggIBgAAAA==.Jarhead:BAAANQAECgQIDAAAAA==.Jaxtoy:BAAANQADCgYIBgAAAA==.Jaybas:BAAANQABCgIIAgAAAA==.Jazilyne:BAAANQADCgMIAwAAAA==.Jaziriel:BAAANQADCgYIBgAAAA==.',
Je='Jenka:BAAANQAECgMIAwAAAA==.',
Jo='Joleya:BAAANQADCgYICwAAAA==.',
Ju='Judihopps:BAAANQAECgIIAwAAAA==.Justcalmdown:BAAANQAECgYIDgABNQAECgIIAgABAAAAAA==.Justyra:BAAANQAECgQICAABNQAECggIGwAMAE8cAA==.',
Ka='Kalder:BAAANQADCgIJAgABNQAECgUICAABAAAAAA==.Kalloo:BAAANQAECgYIBgABNQAFFAQIDAAbAIckAA==.Kambative:BAABNQAECn8xAAMLAAgKTB3/IwCtAgALAAgKTB3/IwCtAgAGAAQKmxPzRAABAQAAAA==.Kambustable:BAAANQADCggICwABNQAECggIMQALAEwdAA==.Kammunion:BAAANQAECgUIBQABNQAECggIMQALAEwdAA==.Kamphiyer:BAAANQADCgMIBAABNQAECggIMQALAEwdAA==.Kamscendance:BAAANQADCgcIBwABNQAECggIMQALAEwdAA==.Kanan:BAAANQADCggIFQAAAA==.Kandosii:BAAANQABCgIIAgAAAA==.Kantheal:BAAANQAECgQICgAAAA==.',
Ke='Keirmania:BAAANQADCgMIAwAAAA==.',
Ki='Kiagas:BAABNQAECn8YAAMiAAkK/QwNGAAcAQAdAAkKYgz9lwDcAQAiAAYKvwkNGAAcAQABNQADCgIIAgABAAAAAA==.Kimbrawly:BAAANQADCgYIBgAAAA==.',
Kr='Kravex:BAABNQAECn8fAAILAAcKvBD1SgC1AQALAAcKvBD1SgC1AQAAAA==.Kreynar:BAAANQAECgQJBAABNQAECgcIHwALALwQAA==.Krrayt:BAAANQAECgMIBgAAAA==.',
Ku='Kukoc:BAAANQAECgcIEgAAAA==.',
Ky='Kylana:BAAANQADCgYICwABNQAECggIGwAGAIENAA==.Kyriel:BAABNQAECn8hAAIXAAgKwBeCVwAHAgAXAAgKwBeCVwAHAgAAAA==.',
['Ké']='Kélly:BAAANQAECggICAAAAA==.',
La='Laayna:BAAANQAECgQICgAAAA==.Lanta:BAAANQAECgcIEAAAAA==.Larayvia:BAABNQAECn8eAAICAAkK1AefjgDoAQACAAkK1AefjgDoAQAAAA==.',
Le='Leesala:BAABNQAECn8eAAIXAAgK+hh8UwAVAgAXAAgK+hh8UwAVAgAAAA==.Leiman:BAAANQAECgQIDAAAAA==.Leymonte:BAAANQADCgMIAwAAAA==.',
Lg='Lg:BAABNQAECn8kAAIWAAkK1x6wCgAzAwAWAAkK1x6wCgAzAwABNQAECgIIAgABAAAAAA==.',
Li='Lic:BAAANQAECgUIEAAAAA==.Lilbitty:BAAANQADCgEIAQAAAA==.Lilililil:BAABNQAECn8bAAMIAAkKbBhtPwB1AgAIAAkKbBhtPwB1AgAXAAEKqwxeHQEuAAAAAA==.Lillabet:BAAANQADCgQICgAAAA==.Limpydk:BAAANQADCgUIBQABNQAECgcIEAABAAAAAA==.Limpylock:BAAANQAECgYIDQABNQAECgcIEAABAAAAAA==.Limpypal:BAAANQAECgcIEAAAAA==.Lispeth:BAAANQAECggICgAAAA==.',
Lo='Longtrang:BAAANQADCgMIAwAAAA==.Loriander:BAAANQADCgQIBAAAAA==.',
Lu='Luckyleaf:BAAANQADCggIFAAAAA==.Lunaaris:BAAANQAECgcIBwAAAA==.Lunastre:BAAANQABCgYICgAAAA==.',
Ma='Macallan:BAAANQADCgUICAAAAA==.Magifur:BAABNQAECn8cAAIeAAgKABI9ygDvAQAeAAgKABI9ygDvAQAAAA==.Magnakilro:BAABNQAECn8eAAICAAcKLRVwfAARAgACAAcKLRVwfAARAgAAAA==.Magnomar:BAAANQADCgcIDQAAAA==.Maisy:BAAANQADCgUIBwAAAA==.Malditto:BAAANQADCgIIAgAAAA==.Maleficus:BAAANQAECgQIBAAAAA==.Mamoswine:BAAANQABCgcICgAAAA==.Mareki:BAAANQADCggIDQAAAA==.Markdfordeth:BAAANQADCgcIBwAAAA==.Mattyfu:BAAANQAECgYIDQAAAA==.Maxrogue:BAAANQADCgUIBQABNQAECgcIHAAjAKIMAA==.Mazikeen:BAAANQAECgUIDAAAAA==.',
Me='Meatsupreme:BAABNQAECn8gAAIKAAgK3BShogDXAQAKAAgK3BShogDXAQAAAA==.Meepin:BAABNQAECn8oAAQPAAkK9x0xOgB5AgAPAAgKGx0xOgB5AgAKAAgKBRMInwDfAQAQAAMKLwxlWAB4AAAAAA==.Merdoc:BAAANQAECgMIAwAAAA==.Mesophistole:BAAANQADCgQICAABNQAECgIIAwABAAAAAA==.Mesopunchy:BAAANQAECgIIAwAAAA==.Mesopyro:BAAANQADCgMIBgABNQAECgIIAwABAAAAAA==.',
Mi='Miamore:BAAANQADCggICAAAAA==.Microchyp:BAAANQADCgEIAQAAAA==.Milemarker:BAAANQAECggIEwAAAA==.Mindstorm:BAAANQADCgYIBgAAAA==.Misstwizted:BAAANQAECgYIEgAAAA==.',
Mo='Mohinu:BAAANQAECgUIBQAAAA==.Mojodaemon:BAAANQADCgUIBQAAAA==.Moocowmoo:BAAANQADCggIDgABNQAECggIIAARAPgZAA==.Moondevil:BAAANQADCgUICwAAAA==.Morta:BAEANQAECgYIEgAAAA==.Mortkavaliro:BAAANQADCgYIBgABNQAECgcIEAABAAAAAA==.',
Mu='Mugzy:BAAANQAECggIAgAAAA==.Muted:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.',
['Mö']='Mörph:BAAANQAECgMIAwABNQAECgkJHAAPAEobAA==.',
Na='Nanérs:BAAANQAECgUIBgABNQAFFAYIEQALAGgcAA==.Narrodus:BAAANQAECgMIBQAAAA==.Nasht:BAAANQADCggICQAAAA==.Nasun:BAAANQADCgQIBAAAAA==.Nataku:BAAANQAECgYIDwAAAA==.',
Ne='Neelix:BAAANQAECgEIAQAAAA==.Neoth:BAAANQABCgQJBgAAAA==.Nezzick:BAABNQAECn8jAAMIAAkKcxnZOgCHAgAIAAkKcxnZOgCHAgAXAAgKYAillABQAQAAAA==.',
Ni='Nicholasrage:BAAANQABCgQIBAAAAA==.Nidalap:BAAANQADCgEIAQAAAA==.Nightreaper:BAAANQADCggIMAAAAA==.Nightsinger:BAAANQABCgIIAgAAAA==.Nimbus:BAACNQAFFH8UAAMIAAcKNBfrAgB+AgAIAAcKNBfrAgB+AgAXAAEKXgH0KgBGAAA1AAQKf5MAAggACQqKJvMAAPoDAAgACQqKJvMAAPoDAAAA.',
No='Nomns:BAAANQAECgUIBQABNQAECgcIHgAjAI0kAA==.Normel:BAAANQAECgEIAQAAAA==.Noz:BAAANQAECgIIBAABNQAECggIGwAKACwfAA==.',
Nr='Nrvous:BAAANQADCgIIAgAAAA==.',
Nu='Nuid:BAAANQAECggIAQAAAA==.Numbers:BAAANQAECgYICgAAAA==.',
Ny='Nytesage:BAACNQAFFH8PAAIkAAQKfyUtAACrAQAkAAQKfyUtAACrAQA1AAQKfycAAiQACQqKJigAANoDACQACQqKJigAANoDAAAA.',
['Nä']='Näners:BAAANQAECgIIAQABNQAFFAYIEQALAGgcAA==.',
['Në']='Nëvërmind:BAABNQAECn8kAAIQAAgKbx7TDwCdAgAQAAgKbx7TDwCdAgAAAA==.',
['Nì']='Nìghtcat:BAAANQAECgQIBwAAAA==.',
Or='Orgrom:BAAANQAECggICAAAAA==.',
Oz='Ozgar:BAAANQAECgIIBwAAAA==.Ozo:BAAANQADCgIIAgAAAA==.',
Pa='Painavolian:BAABNQAECn8zAAIeAAkKSR+2MAAqAwAeAAkKSR+2MAAqAwAAAA==.Palcris:BAAANQADCgcIBwAAAA==.Paxren:BAAANQABCgIIAgAAAA==.',
Pe='Peeches:BAAANQAECgUIBQAAAA==.Pelonis:BAAANQADCgQIBAAAAA==.',
Ph='Pheayre:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Phoenixdówn:BAABNQAECn8ZAAIXAAcKySEtLwCjAgAXAAcKySEtLwCjAgAAAA==.Phoosa:BAAANQADCgEIAQAAAA==.',
Pi='Pingpong:BAABNQAECn8eAAMYAAgK4RsOIAAqAgAYAAgK4RsOIAAqAgADAAEKBQN9UwAgAAAAAA==.Pisspadpanda:BAABNQAECn8nAAMRAAgKQRybWQBGAgARAAgKdRubWQBGAgATAAQKWBWMEwAPAQAAAA==.',
Pl='Plungsnipes:BAAANQADCgcIDgABNQAECggICQABAAAAAA==.',
Po='Poggies:BAACNQAFFH8OAAMkAAYKlSI4AACCAQAeAAUK7SLBFQDDAQAkAAQKvhs4AACCAQA1AAQKfxoAAyQACQqdJUoBAMICAB4ACQqOJKwxACgDACQACAojI0oBAMICAAAA.Potatodh:BAAANQAECgEIAgAAAA==.Potatolock:BAAANQAECgUIBQAAAA==.',
Pr='Praynes:BAABNQAECn8qAAIbAAgKQx0DPgBvAgAbAAgKQx0DPgBvAgAAAA==.',
Pu='Puppet:BAAANQADCgEIAQAAAA==.',
Py='Pylanora:BAAANQADCgMIAwAAAA==.',
Qu='Quinnx:BAAANQADCgMJAQAAAA==.',
Ra='Rach:BAABNQAECn8cAAICAAkKMxTMbAA2AgACAAkKMxTMbAA2AgAAAA==.Rael:BAAANQADCgIJAgAAAA==.Ranoe:BAAANQAECgIIAwABNQAECgcIEgABAAAAAA==.Rathalos:BAAANQABCgIIAgAAAA==.Raxity:BAAANQAECgcIEAAAAA==.Razji:BAABNQAECn8fAAMHAAgKhCAZGgCCAgAHAAcK9iEZGgCCAgACAAQK8htV8AAbAQAAAA==.',
Re='Redmg:BAAANQADCgUIDQABNQAECgMIAwABAAAAAA==.',
Ri='Riete:BAABNQAECn8XAAITAAcKtxCyCQDjAQATAAcKtxCyCQDjAQAAAA==.Rinoa:BAAANQADCggICwAAAA==.',
Ro='Rochallie:BAAANQAECgIIBAAAAA==.Rockii:BAAANQADCgYIBgAAAA==.Rocknwolf:BAAANQAECgUIBgAAAA==.Rokd:BAABNQAECn8jAAIQAAkKHyHTCAAPAwAQAAkKHyHTCAAPAwAAAA==.Rosalee:BAEANQABCgIIAgABNQAECgMICQABAAAAAA==.Roscoelock:BAABNQAECn8VAAMSAAYKrRg+IABtAQASAAUK4Rs+IABtAQARAAQKPgz08wDdAAAAAA==.Roxxann:BAAANQADCgYIBgAAAA==.',
Ru='Ruibaron:BAAANQADCggIJgAAAA==.Rumur:BAAANQADCgYIBgABNQAECgYICQABAAAAAA==.',
['Rà']='Ràidèn:BAAANQADCgcIBwABNQAECgkJKAAXAHMeAA==.',
['Rá']='Ráyne:BAAANQAECgEIAQAAAA==.',
Sa='Sadeel:BAABNQAECn8tAAMTAAgKiRV2BwAjAgATAAgKiRV2BwAjAgARAAcKqwoOsABrAQAAAA==.Sadewolf:BAABNQAECn8bAAMMAAgKTyOuFAC+AgAMAAgKTyOuFAC+AgANAAEKcx/mhABcAAAAAA==.Salvadore:BAAANQADCggICAAAAA==.Samentoni:BAACNQAFFH8FAAIPAAIKiQiCIgCAAAAPAAIKiQiCIgCAAAA1AAQKfyQAAg8ACQrSFeA/AGMCAA8ACQrSFeA/AGMCAAAA.Samgal:BAAANQAECgQIBQAAAA==.Sampsyn:BAAANQABCgYICgAAAA==.Sanctalux:BAAANQADCgMIBQAAAA==.Sasha:BAAANQAECgMICAAAAA==.Satyra:BAABNQAECn8bAAIMAAgKTxyJHwBPAgAMAAgKTxyJHwBPAgAAAA==.Saurphang:BAACNQAFFH8HAAMaAAMKshbgFwCZAAAaAAIKshbgFwCZAAAUAAEKAACUPQAWAAA1AAQKfzAAAhoACQqqITQPADwDABoACQqqITQPADwDAAAA.',
Sc='Scamanes:BAAANQAECgUIDAAAAA==.',
Se='Semperfi:BAAANQABCgYICQAAAA==.Severis:BAAANQADCgEIAQAAAA==.',
Sh='Shadora:BAAANQAECgUICAAAAA==.Shadowwizard:BAABNQAECn88AAISAAgKvg4YEgDjAQASAAgKvg4YEgDjAQAAAA==.Shadybrat:BAAANQADCggIFwABNQAECggIJgACAOwLAA==.Shaladin:BAAANQAECggIEAAAAA==.Shidan:BAABNQAECn8oAAIXAAkKcx7AGwD+AgAXAAkKcx7AGwD+AgAAAA==.Shmeepin:BAAANQAECgIIAgAAAA==.Shockaho:BAAANQAECgQIBwAAAA==.Shockchalk:BAACNQAFFH8aAAIJAAcKSCMxAADQAgAJAAcKSCMxAADQAgA1AAQKfzEAAgkACQq7JnsAAOEDAAkACQq7JnsAAOEDAAAA.Shocknorris:BAAANQAECgIIBAABNQAECgQIBQABAAAAAA==.Shrooclaw:BAAANQADCgIIAgAAAA==.Shulk:BAAANQAECgcIEwAAAA==.',
Si='Sibbiah:BAEANQAECgMICQAAAQ==.Silanre:BAAANQAECgQICQAAAA==.',
Sk='Skaðï:BAACNQAFFH8KAAIHAAUKJBYYDQBnAQAHAAUKJBYYDQBnAQA1AAQKfy4AAwcACQqZHDsZAIoCAAcACQqZHDsZAIoCAAIAAgrQAFM8AWEAAAAA.',
Sl='Slizzard:BAAANQADCgIIAgABNQAFFAQICwAaAJkbAA==.',
Sm='Smalldrogø:BAAANQADCggICAAAAA==.',
Sp='Spadesrage:BAAANQAECgUIDQAAAA==.Spadestree:BAAANQADCgQIBAAAAA==.Spash:BAAANQADCggICwAAAA==.Spicyycurryy:BAABNQAECn8dAAIdAAgKPBkwgQAVAgAdAAgKPBkwgQAVAgAAAA==.',
St='Staticshock:BAAANQADCgUICAABNQAECggICQABAAAAAA==.Strahm:BAABNQAECn8cAAIjAAcKogw3KQBIAQAjAAcKogw3KQBIAQAAAA==.Strehm:BAAANQADCgYIDAABNQAECgcIHAAjAKIMAA==.Stryhm:BAAANQADCgQIBwABNQAECgcIHAAjAKIMAA==.',
Su='Sulfass:BAAANQABCgIIAgAAAA==.Surai:BAABNQAECn8ZAAIXAAkK2yAuDwBIAwAXAAkK2yAuDwBIAwABNQAFFAQIBgAVAMoMAA==.',
Sy='Sylryn:BAAANQADCgQIBAAAAA==.Sylvexa:BAAANQADCggIEwAAAA==.Symple:BAAANQAECgEIAgAAAA==.Syns:BAAANQADCgcIEwAAAA==.Synz:BAAANQADCgcIEgAAAA==.Syssare:BAABNQAECn8UAAINAAcKrx2CLwAmAgANAAcKrx2CLwAmAgAAAA==.',
Ta='Tacpally:BAAANQADCgYIFQAAAA==.Talamor:BAAANQADCgMJAwAAAA==.Talasam:BAAANQADCgQIBAAAAA==.Tandsonnara:BAAANQAECggIAQAAAA==.Tastetickle:BAABNQAECn8vAAIeAAkKYBieYwC3AgAeAAkKYBieYwC3AgAAAA==.Tazdrin:BAABNQAECn8tAAIlAAgKcRYXCAAiAgAlAAgKcRYXCAAiAgAAAA==.',
Te='Telidrus:BAACNQAFFH8GAAMfAAMK2RH4CACMAAAeAAMKlg8DOgDXAAAfAAIKxg/4CACMAAA1AAQKfyQABB8ACQqpIAgMAPkBAB4ACAp6HQ2YAFACAB8ABwpBHggMAPkBACQAAgroDjAJAHUAAAAA.Teneturadvys:BAAANQADCgQIBAABNQAECgYIBwABAAAAAA==.Terrax:BAAANQADCgQIBAAAAA==.',
Th='Thepoacher:BAAANQAECgQIBAABNQAECgYIEAABAAAAAA==.Thicc:BAAANQABCgQIBAAAAA==.Thicchunter:BAABNQAECn8qAAIHAAkKVx4NCwAlAwAHAAkKVx4NCwAlAwAAAA==.Thiccmage:BAAANQAECgYICQAAAA==.Thiccwiggy:BAAANQADCgMIAwABNQAECgYIDQABAAAAAA==.Thuk:BAAANQAECgcIBwAAAA==.Thunderbug:BAAANQADCggICAAAAA==.',
To='Topaze:BAABNQAECn8cAAMPAAkKShsKKADGAgAPAAkKShsKKADGAgAQAAEKAAC/dAAnAAAAAA==.Totemmonster:BAAANQABCgIIAgAAAA==.',
Tr='Trancendantx:BAAANQADCgcIBwAAAA==.Tripx:BAACNQAFFH8SAAIKAAUKZBE3DACCAQAKAAUKZBE3DACCAQA1AAQKfyUAAgoACQo2G31YAIoCAAoACQo2G31YAIoCAAAA.Tripxed:BAABNQAECn8wAAMLAAkKYhm7HgDSAgALAAkKYhm7HgDSAgAmAAEKWgr0PgA5AAABNQAFFAUIEgAKAGQRAA==.Trishan:BAAANQAECgQIBwAAAA==.Trolk:BAAANQADCgUIBwAAAA==.Tronko:BAAANQAECgYIDQAAAA==.Truthjustice:BAAANQADCggIDwAAAA==.',
Tu='Turntsnaco:BAABNQAECn81AAMVAAkKthjwEQBiAgAVAAcKoxzwEQBiAgAWAAYKzxG7YwAdAQAAAA==.Turyon:BAAANQADCgEIAQAAAA==.',
Tw='Twiztedfaith:BAAANQADCgYIBgAAAA==.',
Ul='Ulhume:BAAANQADCgEJAQABNQAECgcIHwALALwQAA==.',
Un='Unafhaen:BAAANQADCgQIBAAAAA==.Unaverse:BAAANQAECgUIBQAAAA==.',
Ur='Urp:BAAANQAECgIIBAAAAA==.',
Us='Usmc:BAAANQADCgYIBgAAAA==.Usmccpl:BAAANQADCgYICQAAAA==.',
Va='Valengarde:BAAANQAFFAEIAQAAAA==.Valentin:BAAANQABCgIIAgAAAA==.Valhalia:BAAANQABCgIIAgAAAA==.Vanderneuker:BAAANQAECgQIBwABNQAFFAQICwAaAJkbAA==.Vangoon:BAEBNQAECn8iAAIWAAkKbCAECQBGAwAWAAkKbCAECQBGAwAAAA==.Vanmonk:BAAANQAECgIIAQAAAA==.Vann:BAAANQADCgQIBwAAAA==.Vannix:BAABNQAECn8tAAIOAAgKwSNPCwAuAwAOAAgKwSNPCwAuAwAAAA==.',
Ve='Velkanos:BAAANQADCgQIBAAAAA==.Velkhaz:BAAANQABCgYIBgAAAA==.Vereena:BAAANQAECgUIDgAAAA==.Vesstar:BAAANQABCggIFgAAAA==.',
Vi='Violet:BAAANQADCgMIAwAAAA==.Virmethir:BAAANQAECgUIEAAAAA==.',
Vo='Voltaren:BAAANQAECgIJAgAAAA==.',
Wh='Whtmg:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.',
Wi='Winterbreeze:BAAANQADCgQICAAAAA==.Wiwi:BAACNQAFFH8LAAMaAAQKmRtJEQDyAAAaAAMKfBlJEQDyAAAZAAIKAhjMFACTAAA1AAQKfzMAAxoACQo2H/5LAOIBABoACArtGv5LAOIBABkABgqIHedCALIBAAAA.',
Wo='Woopie:BAAANQAECgEIAQAAAA==.',
Wu='Wukøng:BAAANQABCgIIAgAAAA==.',
Xa='Xake:BAAANQAECgUICgAAAA==.Xares:BAAANQAECgcIEgAAAA==.',
Xe='Xenp:BAABNQAECn8yAAMQAAkK/xZJFwA+AgAQAAkK/xZJFwA+AgAKAAQKfwqTNgHBAAAAAA==.',
Xi='Xiovemm:BAAANQADCgcJBQAAAA==.',
Xu='Xuri:BAABNQAECn8XAAICAAgKEg01jgDpAQACAAgKEg01jgDpAQAAAA==.',
Yd='Ydriel:BAAANQADCgUIBwAAAA==.',
['Yö']='Yöurfired:BAAANQADCgQICAAAAA==.',
Za='Zake:BAABNQAECn8qAAICAAkK+hqnKgDtAgACAAkK+hqnKgDtAgAAAA==.Zalileina:BAAANQADCgMJAgAAAA==.Zantanna:BAAANQADCgYJEAAAAA==.Zappythile:BAABNQAECn8bAAMXAAgKlx/sJwDCAgAXAAgKlx/sJwDCAgAIAAEKAAAOPwEsAAAAAA==.Zayiro:BAAANQADCgYIDAAAAA==.',
Ze='Zealdavir:BAAANQABCgIIAgAAAA==.',
Zi='Zigzagoon:BAAANQABCgYIBgAAAA==.',
Zo='Zoz:BAAANQAECgIIAwAAAA==.',
Zu='Zulfrik:BAABNQAECn8dAAMeAAkKtRXUpgAzAgAeAAkKGhLUpgAzAgAfAAIKEh3tMgBsAAAAAA==.',
Zy='Zyzy:BAAANQAECgYICQABNQAFFAYIGwAOAJsfAA==.',
['Äh']='Ählis:BAAANQAECgIIAwAAAA==.',
['ße']='ßeef:BAAANQAECgUICwAAAA==.',
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
