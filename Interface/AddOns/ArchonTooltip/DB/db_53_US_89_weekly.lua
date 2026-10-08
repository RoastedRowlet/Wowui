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

local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Monk-Mistweaver','Evoker-Augmentation','Evoker-Devastation','Druid-Restoration','Hunter-Marksmanship','Shaman-Elemental','Shaman-Enhancement','Paladin-Retribution','Druid-Balance','DemonHunter-Devourer','DemonHunter-Havoc','Priest-Shadow','Paladin-Holy','Paladin-Protection','Rogue-Subtlety','Rogue-Assassination','Shaman-Restoration','Monk-Windwalker','DeathKnight-Frost','DeathKnight-Unholy','Priest-Holy','Monk-Brewmaster','DeathKnight-Blood','Warlock-Demonology','Mage-Arcane','Mage-Frost','Priest-Discipline','DemonHunter-Vengeance','Warrior-Arms','Warrior-Fury','Druid-Guardian','Mage-Fire','Warlock-Affliction','Warlock-Destruction','Rogue-Outlaw','Druid-Feral',}
local provider = {region='US',realm='Eonar',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abysseus:BAAANQADCgcIDwAAAA==.',
Ad='Admired:BAAANQADCgQIBQABNQAECgQIAwABAAAAAA==.',
Ae='Aerdrie:BAAANQABCgMIAwAAAA==.Aevelin:BAAANQAECggIDgAAAA==.',
Aj='Ajagar:BAAANQADCgcIIQABNQAECgcIEAABAAAAAA==.',
Al='Alamora:BAAANQAECgEIAQAAAA==.Alastair:BAAANQAECggIAgAAAA==.Alathena:BAAANQAECgMIAwAAAA==.Alexandrya:BAABNQAECoEgAAICAAgKbw6XawAPAgACAAgKbw6XawAPAgAAAA==.Alickdh:BAAANQADCgIIAgABNQAFFAEIAQABAAAAAA==.Almostpanda:BAAANQADCgUIBQABNQAECggIHAADAEEOAA==.Altery:BAAANQAECgEIAQAAAA==.',
Am='Ampharos:BAAANQABCgYIBgAAAA==.Amsahunter:BAAANQADCggICAABNQAECgQIBwABAAAAAA==.Amsroeb:BAAANQAECgQIBwAAAA==.',
An='Anelavenger:BAACNQAFFIEMAAIEAAUKAhVoAwCbAQAEAAUKAhVoAwCbAQA1AAQKgTcAAwQACQrYIgUBAJMDAAQACQrYIgUBAJMDAAUABgpiDHkgADIBAAAA.Anelblast:BAAANQAECgIIBQABNQAFFAUIDAAEAAIVAA==.Angerwina:BAAANQAECgIIAgAAAA==.Annain:BAAANQADCgYJCgAAAA==.',
Ar='Arathor:BAAANQADCggIEQAAAA==.Ardent:BAAANQAECgQICAAAAA==.Ardor:BAAANQADCgYICgABNQAECgQICAABAAAAAA==.Arent:BAABNQAECoEhAAIGAAgKWBNeIAD7AQAGAAgKWBNeIAD7AQAAAA==.Arkanna:BAAANQADCgYIBgAAAA==.',
As='Asharia:BAAANQAECgUICAAAAA==.Ashla:BAAANQADCgIIAgAAAA==.Assateague:BAAANQAECgEIAQAAAA==.Astelossa:BAAANQADCgcIEQAAAA==.',
['Aë']='Aëro:BAAANQADCgYICQAAAA==.',
Ba='Bananapistol:BAAANQABCgIIBAAAAA==.Barracksbuny:BAAANQAECgIIAwABNQAECgYICwABAAAAAA==.Barrathfrogy:BAAANQADCgQICQAAAA==.',
Be='Bebheishel:BAAANQADCgQICQAAAA==.Beefcake:BAAANQADCgYJFQABNQADCgcIDgABAAAAAA==.Bertello:BAAANQAECgQIBAAAAA==.Beserol:BAAANQADCgYICAAAAA==.',
Bi='Biest:BAAANQAECggIBgAAAA==.Biggs:BAAANQADCggICQABNQAECggIBgABAAAAAA==.Billy:BAAANQAECgcIDwAAAA==.Bilywitchdoc:BAAANQAECgEIAgABNQAECggIHQAHAMgfAA==.Bionicle:BAAANQADCgQIBAAAAA==.Biscuít:BAAANQAECgUICwAAAA==.',
Bk='Bk:BAAANQADCgcICwABNQAECggIGQAIAM8XAA==.',
Bl='Blasuoff:BAAANQADCgYIBgAAAA==.Bloodeagle:BAAANQADCggJCAAAAA==.Bloodyfate:BAAANQADCgYIBgAAAA==.Bluechalk:BAAANQAECgcIDAABNQAFFAcIFQAJAOAfAA==.',
Bo='Boomslap:BAAANQAECggICQAAAA==.Borzoi:BAABNQAECoExAAIKAAcK8SPfNQDVAgAKAAcK8SPfNQDVAgAAAA==.',
Br='Brawne:BAAANQADCgUIBQAAAA==.',
Bu='Buzzdruu:BAABNQAECoEWAAILAAcK/R46KQBqAgALAAcK/R46KQBqAgAAAA==.',
['Bø']='Bønës:BAAANQADCgQIBAAAAA==.',
Ca='Caaniss:BAAANQABCgQIBAAAAA==.Caduceus:BAAANQADCgUIBQAAAA==.Caesus:BAAANQADCgcICwAAAA==.Cagedancer:BAAANQADCgUICQAAAA==.Callio:BAABNQAECoEcAAICAAgKoQpxfQDkAQACAAgKoQpxfQDkAQAAAA==.Canus:BAAANQADCgMIAwAAAA==.Caritta:BAABNQAECoEUAAMMAAcKKxVfNgBqAQAMAAYKRxFfNgBqAQANAAMKqxY8XwDMAAAAAA==.Cathillex:BAAANQAECgQICQAAAA==.Caycay:BAACNQAFFIEKAAINAAUKCBTZBwCLAQANAAUKCBTZBwCLAQA1AAQKgTEAAg0ACQrpJNUDAKwDAA0ACQrpJNUDAKwDAAAA.',
Ce='Celestian:BAAANQAECggIBgAAAA==.',
Ch='Chillbros:BAABNQAECoEaAAMIAAkKjyP2HQD8AgAIAAgK8SP2HQD8AgAJAAgKwRs3EQA3AgAAAA==.Churd:BAABNQAECoEhAAIOAAkKlhGPHQAwAgAOAAkKlhGPHQAwAgAAAA==.Chypnotic:BAABNQAECoEdAAICAAkKQRUdTABiAgACAAkKQRUdTABiAgAAAA==.Chypotle:BAAANQADCgYJBgAAAA==.Chypster:BAAANQADCgYIBgAAAA==.',
Cl='Cleft:BAABNQAECoEYAAMPAAcK8wa0jwBFAQAPAAcK8wa0jwBFAQAKAAQK0gSXJAGoAAAAAA==.Clowwnshoes:BAAANQAECgQICgAAAA==.',
Co='Coalystra:BAABNQAECoEmAAIMAAgKkyHEDAAIAwAMAAgKkyHEDAAIAwAAAA==.Cocopuffs:BAAANQAECgUICwAAAA==.Colostrom:BAABNQAECoEmAAIQAAgKfCRUBQBEAwAQAAgKfCRUBQBEAwAAAA==.Coramage:BAAANQAECgIJAwAAAA==.Corliss:BAAANQAECgEIAQAAAA==.Cornholeo:BAAANQABCgIIBAAAAA==.Corruptdata:BAAANQAECgcIEwABNQAFFAUIDQAKALcOAA==.',
Cp='Cplusmc:BAAANQADCgMIAwAAAA==.',
Da='Darkbeast:BAAANQAECgYJDwAAAA==.Darthorc:BAAANQADCgcIDgAAAA==.Daten:BAABNQAECoEhAAIKAAgKDgz3ngCtAQAKAAgKDgz3ngCtAQAAAA==.Dazshauran:BAAANQADCgUICwAAAA==.',
De='Deadzexcs:BAAANQAECgIIBAAAAA==.Decayed:BAAANQAECgYICwAAAA==.Deladoria:BAAANQAECgYICgAAAA==.',
Di='Diagonalli:BAAANQAECgQICgAAAA==.Dirk:BAAANQADCgUIBQABNQAECgYIDwABAAAAAA==.Dirkdìggler:BAAANQADCgUIBwAAAA==.Divirian:BAAANQAECgIIAgAAAA==.',
Dj='Djdaemon:BAAANQADCgQIDgAAAA==.Djdrakshadow:BAAANQADCgUIDwAAAA==.Djdruidshadw:BAAANQADCgYIFgAAAA==.Djpaly:BAAANQADCgUIFQAAAA==.Djpriest:BAAANQADCgYIGwAAAA==.Djshadow:BAAANQADCgYIGQAAAA==.Djshadowar:BAAANQADCgYIHAAAAA==.Djshadowhunt:BAAANQADCgUIEwAAAA==.Djshadowlock:BAAANQADCgQIEQAAAA==.Djshadowlok:BAAANQADCgYIFwAAAA==.Djshadowrog:BAAANQAECgEIAQAAAA==.Djshadruid:BAAANQADCgYIDQAAAA==.Djshamy:BAAANQADCgYIFgAAAA==.Djshaolin:BAAANQADCgcIHQAAAA==.Djzhadow:BAAANQADCgQICwAAAA==.Djzhadruid:BAAANQADCgUICwAAAA==.',
Dk='Dkshadow:BAAANQADCgcIFwAAAA==.',
Do='Doofuss:BAAANQABCgIIAgAAAA==.',
Dr='Dragonchalk:BAAANQADCgYIBgABNQAFFAcIFQAJAOAfAA==.Drakhadir:BAAANQADCgUIBwAAAA==.Drakmon:BAAANQADCgUIBQAAAA==.Draktând:BAABNQAECoEZAAMRAAcKeReGFgAcAgARAAcKeReGFgAcAgASAAEK5gW/iwAxAAAAAA==.Dreve:BAAANQABCgIIBAAAAA==.Driftier:BAAANQADCggIDAAAAA==.Drogon:BAAANQAECgYIBwABNQAECgkJIwATAPIhAA==.Drunkenpanda:BAABNQAECoEcAAMDAAgKQQ7fGgCnAQADAAgKQQ7fGgCnAQAUAAEKLAEcbQAXAAAAAA==.',
Du='Duneshadow:BAAANQADCgUICQAAAA==.',
Ec='Echö:BAEBNQAECoEkAAINAAgK/gx3OAC6AQANAAgK/gx3OAC6AQAAAA==.',
Ei='Eirø:BAAANQAECgQIBAABNQAFFAUICgAHAGgRAA==.',
El='Elaine:BAAANQADCgUIBgAAAA==.Elberon:BAAANQAECgIIAgAAAA==.Elöhim:BAAANQAECggIBgAAAA==.',
Ep='Epic:BAAANQADCgYICQAAAA==.',
Eq='Eqo:BAAANQAECgUIBQAAAA==.',
Er='Erebosa:BAAANQABCgQIBAAAAA==.',
Fa='Fallden:BAAANQADCgUIBQABNQAECgcIHwAOAKobAA==.Fatherchill:BAABNQAECoEdAAIQAAgKvhfpGgDtAQAQAAgKvhfpGgDtAQAAAA==.Fathermoses:BAAANQADCgMIAwAAAA==.',
Fi='Fitco:BAAANQAECgQIBQAAAA==.',
Fl='Flokii:BAAANQADCgEIAQAAAA==.',
Fr='Frantecks:BAAANQAECgYIBgAAAA==.Freela:BAEANQADCgUIBQABNQAECgUIDAABAAAAAA==.Frost:BAAANQAECgIJAgABNQAFFAYIDgAVAK8SAA==.Frostmon:BAABNQAECoEqAAIWAAkKCCFAFgDxAgAWAAkKCCFAFgDxAgAAAA==.Frostyaf:BAAANQADCgIIAgAAAA==.',
Fu='Furbee:BAAANQAECggIBgAAAA==.',
Ga='Galeandra:BAAANQAECgMIBAAAAA==.Gambas:BAAANQADCgIIAgAAAA==.Garim:BAABNQAECoEaAAIJAAcKuBDiFQDfAQAJAAcKuBDiFQDfAQAAAA==.Gaztingo:BAABNQAECoEXAAMXAAgKnQuJawClAQAXAAgKnQuJawClAQAOAAIKcAKKZwA+AAAAAA==.',
Gh='Ghostbanri:BAAANQABCgcICAAAAA==.',
Gi='Gildor:BAAANQADCggIDQAAAA==.Giox:BAAANQADCgMIAwAAAA==.Girthshock:BAAANQADCgcIBwABNQAECgcIEAABAAAAAA==.',
Gn='Gnar:BAAANQADCgcICAAAAA==.',
Go='Gobi:BAAANQAECgYIDAAAAA==.Gowtherpunch:BAABNQAECoEnAAIYAAgKLA5jEgCfAQAYAAgKLA5jEgCfAQAAAA==.',
Gr='Gravewynd:BAAANQADCggIDwAAAA==.Grimsy:BAAANQAECgcIEgAAAA==.Gruxxiron:BAAANQAECgQIBgABNQAECggIHgAZANAVAA==.',
Gu='Gulnn:BAAANQAECgcIEgAAAA==.Gumby:BAAANQABCgQIBAAAAA==.',
Ha='Haelena:BAAANQADCgcIJwAAAA==.Hage:BAAANQADCggIAQAAAA==.Harmossy:BAAANQAECgUJDgAAAA==.',
He='Heartsfang:BAAANQADCgMIBAAAAA==.Heriotza:BAAANQAECgcIEAAAAA==.',
Ho='Hogmaine:BAAANQADCgQIBAAAAA==.Holypaladin:BAABNQAECoEgAAIaAAcKRBoFcADnAQAaAAcKRBoFcADnAQAAAA==.',
Hu='Hunttress:BAAANQADCgYIBgAAAA==.',
Ii='Iimit:BAAANQAECgUIDQABNQAECgcIEgABAAAAAA==.',
Il='Illidead:BAACNQAFFIETAAIbAAYKmh7EBgAxAgAbAAYKmh7EBgAxAgA1AAQKgScAAxsACQqMJT0kAEMDABsACAqfJT0kAEMDABwAAQr6JCE2AEwAAAAA.Illooj:BAACNQAFFIEIAAIXAAQKDh6lDgCAAQAXAAQKDh6lDgCAAQA1AAQKgSMAAx0ACQqZJgMBAE4DABcACAp6JWgLAFUDAB0ACAq+JQMBAE4DAAAA.',
In='Indexes:BAAANQAECgEIAQAAAA==.Inspiration:BAAANQADCgQICwAAAA==.',
Is='Ist:BAABNQAECoEgAAIeAAgKhxImDQC9AQAeAAgKhxImDQC9AQAAAA==.',
It='Itchigo:BAAANQAECgQIBAAAAA==.Itskamertime:BAAANQAECgEIAQABNQAECggIKgALAJIdAA==.',
Iv='Ivgorod:BAAANQAECgQICQAAAA==.',
Ja='Jabbadahut:BAAANQAECggIBgAAAA==.Jarhead:BAAANQAECgQICgAAAA==.Jaybas:BAAANQABCgIIAgAAAA==.Jazilyne:BAAANQADCgMIAwAAAA==.Jaziriel:BAAANQADCgYIBgAAAA==.',
Je='Jenka:BAAANQAECgMIAwAAAA==.',
Jo='Joleya:BAAANQADCgYICwAAAA==.',
Ju='Justcalmdown:BAAANQAECgUICAABNQAECgIIAgABAAAAAA==.Justyra:BAAANQAECgQICAABNQAECggIGwAMADMbAA==.',
Ka='Kalder:BAAANQADCgIJAgABNQAECgUICAABAAAAAA==.Kalloo:BAAANQAECgYIBgABNQAFFAQICAAXAA4eAA==.Kambative:BAABNQAECoEqAAMLAAgKkh22IgCbAgALAAgKkh22IgCbAgAGAAQKmxPmOwAKAQAAAA==.Kambustable:BAAANQADCggICwABNQAECggIKgALAJIdAA==.Kammunion:BAAANQAECgUIBQABNQAECggIKgALAJIdAA==.Kamphiyer:BAAANQADCgMIBAABNQAECggIKgALAJIdAA==.Kanan:BAAANQADCgcIDgAAAA==.Kandosii:BAAANQABCgIIAgAAAA==.Kantheal:BAAANQAECgQICgAAAA==.',
Ki='Kiagas:BAABNQAECoEWAAMfAAkKBA5RggDyAQAfAAkKxQxRggDyAQAgAAYKKwsNFQApAQABNQADCgIIAgABAAAAAA==.Kimbrawly:BAAANQADCgYIBgAAAA==.',
Kr='Kravex:BAABNQAECoEZAAILAAcKLhMCRAC2AQALAAcKLhMCRAC2AQAAAA==.Kreynar:BAAANQAECgQJBAABNQAECgcIGQALAC4TAA==.Krrayt:BAAANQAECgMIBAAAAA==.',
Ku='Kukoc:BAAANQAECgcIEgAAAA==.',
Ky='Kylana:BAAANQADCgYICwABNQAECgcIGQAGAIANAA==.Kyriel:BAABNQAECoEhAAITAAgKwBdxSAAVAgATAAgKwBdxSAAVAgAAAA==.',
['Ké']='Kélly:BAAANQAECggICAAAAA==.',
La='Laayna:BAAANQAECgIIBgAAAA==.Lanta:BAAANQAECgcIEAAAAA==.Larayvia:BAABNQAECoEbAAICAAkKnQdNfgDiAQACAAkKnQdNfgDiAQAAAA==.',
Le='Leesala:BAAANQAECgcIEwAAAA==.Leiman:BAAANQAECgMICQAAAA==.',
Lg='Lg:BAABNQAECoEdAAISAAkKKx75CgAZAwASAAkKKx75CgAZAwABNQAECgIIAgABAAAAAA==.',
Li='Lic:BAAANQAECgUICgAAAA==.Lilbitty:BAAANQADCgEIAQAAAA==.Lilililil:BAABNQAECoEZAAMIAAgKzxePRAA4AgAIAAgKzxePRAA4AgATAAEKqwxOBwEuAAAAAA==.Lillabet:BAAANQADCgQICgAAAA==.Limpydk:BAAANQADCgUIBQABNQAECgcIEAABAAAAAA==.Limpylock:BAAANQAECgYIDQABNQAECgcIEAABAAAAAA==.Limpypal:BAAANQAECgcIEAAAAA==.Lispeth:BAAANQAECgMIBAAAAA==.',
Lo='Longtrang:BAAANQADCgMIAwAAAA==.Loriander:BAAANQADCgQIBAAAAA==.',
Lu='Luckyleaf:BAAANQADCgYIDAAAAA==.Lunaaris:BAAANQAECgcIBwAAAA==.Lunastre:BAAANQABCgYICgAAAA==.',
Ma='Macallan:BAAANQADCgUICAAAAA==.Magifur:BAABNQAECoEcAAIbAAgKnxLBsQD9AQAbAAgKnxLBsQD9AQAAAA==.Magnakilro:BAAANQAECgYIEgAAAA==.Magnomar:BAAANQADCgcIDQAAAA==.Maisy:BAAANQADCgUIBwAAAA==.Maleficus:BAAANQADCggIJQAAAA==.Mamoswine:BAAANQABCgcICgAAAA==.Mareki:BAAANQADCggIDQAAAA==.Markdfordeth:BAAANQADCgcIBwAAAA==.Mattyfu:BAAANQAECgYIDQAAAA==.Maxrogue:BAAANQADCgUIBQABNQAECgcIGwAhAEkNAA==.Mazikeen:BAAANQAECgUIDAAAAA==.',
Me='Meatsupreme:BAABNQAECoEeAAIKAAgKFxRmhwDlAQAKAAgKFxRmhwDlAQAAAA==.Meepin:BAABNQAECoEhAAQPAAkKLh7XRQAwAgAPAAcKgR3XRQAwAgAKAAgK6BLIjgDTAQAQAAMKLwwNTgCCAAAAAA==.Merdoc:BAAANQADCgYJCAAAAA==.Mesophistole:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Mesopunchy:BAAANQAECgEIAQAAAA==.Mesopyro:BAAANQADCgMIBgABNQAECgEIAQABAAAAAA==.',
Mi='Microchyp:BAAANQADCgEIAQAAAA==.Milemarker:BAAANQAECgcIDAAAAA==.Misstwizted:BAAANQAECgYIEgAAAA==.',
Mo='Mohinu:BAAANQAECgUIBQAAAA==.Mojodaemon:BAAANQADCgUIBQAAAA==.Moocowmoo:BAAANQADCggIDgABNQAECggIIAAaAEQaAA==.Moondevil:BAAANQADCgQICAAAAA==.Morta:BAEANQAECgUIDAAAAA==.Mortkavaliro:BAAANQADCgYIBgABNQAECgcIEAABAAAAAA==.',
Mu='Mugzy:BAAANQAECggIAgAAAA==.Muted:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.',
['Mö']='Mörph:BAAANQAECgMIAwABNQAECgkJHAAPAEobAA==.',
Na='Nanérs:BAAANQAECgUIBgABNQAFFAUIDQALANwYAA==.Narrodus:BAAANQAECgMIBQAAAA==.Nasht:BAAANQADCggICQAAAA==.Nasun:BAAANQADCgQIBAAAAA==.Nataku:BAAANQAECgYIDwAAAA==.',
Ne='Neelix:BAAANQADCggIFgAAAA==.Neoth:BAAANQABCgQJBgAAAA==.Nezzick:BAABNQAECoEhAAMIAAgKUxp8OABtAgAIAAgKUxp8OABtAgATAAgKYAg3hABTAQAAAA==.',
Ni='Nicholasrage:BAAANQABCgQIBAAAAA==.Nidalap:BAAANQADCgEIAQAAAA==.Nightreaper:BAAANQADCggIKQAAAA==.Nightsinger:BAAANQABCgIIAgAAAA==.Nimbus:BAACNQAFFIEQAAIIAAcK4xc6AgB3AgAIAAcK4xc6AgB3AgA1AAQKgYEAAggACQpTJiIBAPEDAAgACQpTJiIBAPEDAAAA.',
No='Nomns:BAAANQADCgYIBgABNQAECgYIEwABAAAAAA==.Normel:BAAANQAECgEIAQAAAA==.Noz:BAAANQAECgIIBAABNQAECggIGwAKAJweAA==.',
Nr='Nrvous:BAAANQADCgIIAgAAAA==.',
Nu='Nuid:BAAANQAECggIAQAAAA==.Numbers:BAAANQAECgUICAAAAA==.',
Ny='Nytesage:BAACNQAFFIELAAIiAAQKaiAoAACnAQAiAAQKaiAoAACnAQA1AAQKgSQAAiIACQp5JhkAAOQDACIACQp5JhkAAOQDAAAA.',
['Nä']='Näners:BAAANQAECgIIAQABNQAFFAUIDQALANwYAA==.',
['Në']='Nëvërmind:BAABNQAECoEcAAIQAAgKHRxaEQBkAgAQAAgKHRxaEQBkAgAAAA==.',
['Nì']='Nìghtcat:BAAANQAECgMIAwAAAA==.',
Or='Orgrom:BAAANQAECggICAAAAA==.',
Oz='Ozgar:BAAANQAECgIIBgAAAA==.Ozo:BAAANQADCgIIAgAAAA==.',
Pa='Painavolian:BAABNQAECoEtAAIbAAkKKx8gMgAbAwAbAAkKKx8gMgAbAwAAAA==.Palcris:BAAANQADCgcIBwAAAA==.Paxren:BAAANQABCgIIAgAAAA==.',
Pe='Peeches:BAAANQAECgUIBQAAAA==.',
Ph='Pheayre:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Phoenixdówn:BAAANQAECgYIDgAAAA==.Phoosa:BAAANQADCgEIAQAAAA==.',
Pi='Pingpong:BAABNQAECoEeAAMUAAgKBBmKGgA/AgAUAAgKBBmKGgA/AgADAAEKBQOITAAgAAAAAA==.Pisspadpanda:BAABNQAECoElAAMaAAgKSBxLSQBZAgAaAAgKrhtLSQBZAgAjAAQKHhf/EAAUAQAAAA==.',
Pl='Plungsnipes:BAAANQADCgcIDgABNQAECggICQABAAAAAA==.',
Po='Poggies:BAACNQAFFIENAAMbAAUKnyCNDwDVAQAbAAUKXiCNDwDVAQAiAAMKohk4AAAlAQA1AAQKgRoAAyIACQpXJAsBAM8CABsACQqDI5YkAEIDACIACAr5IAsBAM8CAAAA.Potatodh:BAAANQAECgEIAgAAAA==.Potatolock:BAAANQAECgIIAgAAAA==.',
Pr='Praynes:BAABNQAECoEjAAIXAAgKQx3AMgB8AgAXAAgKQx3AMgB8AgAAAA==.',
Pu='Puppet:BAAANQADCgEIAQAAAA==.',
Py='Pylanora:BAAANQADCgMIAwAAAA==.',
Qu='Quinnx:BAAANQADCgMJAQAAAA==.',
Ra='Rach:BAABNQAECoEYAAICAAkK4xJYRgBzAgACAAkK4xJYRgBzAgAAAA==.Rael:BAAANQADCgIJAgAAAA==.Ranoe:BAAANQAECgIIAwABNQAECgcIEgABAAAAAA==.Rathalos:BAAANQABCgIIAgAAAA==.Raxity:BAAANQAECgUIDAAAAA==.Razji:BAABNQAECoEdAAMHAAgKyB93FwCGAgAHAAcKtSB3FwCGAgACAAQKfx2b1QAiAQAAAA==.',
Re='Redmg:BAAANQADCgUICAABNQAECgMIAwABAAAAAA==.',
Ri='Riete:BAAANQAECgYIEAAAAA==.',
Ro='Rochallie:BAAANQAECgIIAwAAAA==.Rockii:BAAANQADCgYIBgAAAA==.Rocknwolf:BAAANQAECgUIBgAAAA==.Rokd:BAABNQAECoEhAAIQAAgKqyFOCgDYAgAQAAgKqyFOCgDYAgAAAA==.Rosalee:BAEANQABCgIIAgABNQAECgMIBgABAAAAAA==.Roscoelock:BAABNQAECoEVAAMkAAYKUxiaHgBxAQAkAAUK0hqaHgBxAQAaAAQKzwqX2gDnAAAAAA==.Roxxann:BAAANQADCgYIBgAAAA==.',
Ru='Ruibaron:BAAANQADCgcIHgAAAA==.',
['Rà']='Ràidèn:BAAANQADCgcIBwABNQAECggIJgATAHwgAA==.',
['Rá']='Ráyne:BAAANQAECgEIAQAAAA==.',
Sa='Sadeel:BAABNQAECoEmAAIjAAgKsxQtBgAuAgAjAAgKsxQtBgAuAgAAAA==.Sadewolf:BAABNQAECoEZAAIMAAgK5SGYDwDlAgAMAAgK5SGYDwDlAgAAAA==.Salvadore:BAAANQADCggICAAAAA==.Samentoni:BAABNQAECoEiAAIPAAkK0hWSNQByAgAPAAkK0hWSNQByAgAAAA==.Samgal:BAAANQAECgQIBQAAAA==.Sampsyn:BAAANQABCgYICgAAAA==.Sasha:BAAANQAECgMIBwAAAA==.Satyra:BAABNQAECoEbAAIMAAgKMxt+GQBzAgAMAAgKMxt+GQBzAgAAAA==.Saurphang:BAACNQAFFIEHAAMWAAMKPhCuFACZAAAWAAIKshauFACZAAAZAAEKVgPjNQAaAAA1AAQKgSsAAhYACQq4IYgTAAYDABYACQq4IYgTAAYDAAAA.',
Sc='Scamanes:BAAANQAECgUIDAAAAA==.',
Se='Semperfi:BAAANQABCgYICQAAAA==.Severis:BAAANQADCgEIAQAAAA==.',
Sh='Shadora:BAAANQAECgUICAAAAA==.Shadowwizard:BAABNQAECoE5AAIkAAgKvAwgFQC8AQAkAAgKvAwgFQC8AQAAAA==.Shadybrat:BAAANQADCggIFwABNQAECggIIAACAG8OAA==.Shaladin:BAAANQAECgQICAAAAA==.Shidan:BAABNQAECoEmAAITAAgKfCB3IADJAgATAAgKfCB3IADJAgAAAA==.Shockaho:BAAANQAECgQIBwAAAA==.Shockchalk:BAACNQAFFIEVAAIJAAcK4B82AAC9AgAJAAcK4B82AAC9AgA1AAQKgS4AAgkACQrDJioAAAAEAAkACQrDJioAAAAEAAAA.Shocknorris:BAAANQAECgIIBAABNQAECgQIBQABAAAAAA==.Shrooclaw:BAAANQADCgIIAgAAAA==.Shulk:BAAANQAECgcIEwAAAA==.',
Si='Sibbiah:BAEANQAECgMIBgAAAQ==.Silanre:BAAANQAECgMIBQAAAA==.',
Sk='Skaðï:BAACNQAFFIEKAAIHAAUKaBEjCgB4AQAHAAUKaBEjCgB4AQA1AAQKgSsAAwcACQolG1EXAIcCAAcACQoZG1EXAIcCAAIAAgoiDW8gAWMAAAAA.',
Sl='Slizzard:BAAANQADCgIIAgABNQAFFAQICwAWAEgYAA==.',
Sp='Spadesrage:BAAANQAECgMICAAAAA==.Spash:BAAANQADCgQIBAAAAA==.Spicyycurryy:BAABNQAECoEcAAIfAAgK0BgLcAAiAgAfAAgK0BgLcAAiAgAAAA==.',
St='Staticshock:BAAANQADCgUICAABNQAECggICQABAAAAAA==.Strahm:BAABNQAECoEbAAIhAAcKSQ1GIQBIAQAhAAcKSQ1GIQBIAQAAAA==.Strehm:BAAANQADCgYIDAABNQAECgcIGwAhAEkNAA==.Stryhm:BAAANQADCgQIBwABNQAECgcIGwAhAEkNAA==.',
Su='Sulfass:BAAANQABCgIIAgAAAA==.Surai:BAABNQAECoEWAAITAAcKRyLhJgCpAgATAAcKRyLhJgCpAgABNQAFFAQIBgARAHoSAA==.',
Sy='Sylryn:BAAANQADCgQIBAAAAA==.Sylvexa:BAAANQADCggIDgAAAA==.Symple:BAAANQAECgEIAQAAAA==.Syns:BAAANQADCgcIDgAAAA==.Synz:BAAANQADCgcJEgAAAA==.Syssare:BAABNQAECoEUAAINAAcKxh3kJgA8AgANAAcKxh3kJgA8AgAAAA==.',
Ta='Tacpally:BAAANQADCgYIFQAAAA==.Talamor:BAAANQADCgMJAwAAAA==.Talasam:BAAANQADCgQIBAAAAA==.Tandsonnara:BAAANQAECggIAQAAAA==.Tastetickle:BAABNQAECoEnAAIbAAgK7hjNhQBaAgAbAAgK7hjNhQBaAgAAAA==.Tazdrin:BAABNQAECoEmAAIlAAgKnhIxCAAKAgAlAAgKnhIxCAAKAgAAAA==.',
Te='Telidrus:BAACNQAFFIEGAAMcAAMKJBD5BgCNAAAbAAMKog6kLwDcAAAcAAIKxg/5BgCNAAA1AAQKgSQABBwACQooIXcJAAoCABsACAowHuiBAGICABwABwrgHncJAAoCACIAAgroDhUIAHUAAAAA.Teneturadvys:BAAANQADCgQIBAABNQAECgYIBwABAAAAAA==.Terrax:BAAANQADCgQIBAAAAA==.',
Th='Thicc:BAAANQABCgQIBAAAAA==.Thicchunter:BAABNQAECoEjAAIHAAgKmSCuDgDnAgAHAAgKmSCuDgDnAgAAAA==.Thiccmage:BAAANQAECgYICQAAAA==.Thiccwiggy:BAAANQADCgMIAwABNQAECgYIDQABAAAAAA==.Thunderbug:BAAANQADCggICAAAAA==.',
To='Topaze:BAABNQAECoEcAAMPAAkKShuGIADWAgAPAAkKShuGIADWAgAQAAEKZQ/0aAAnAAAAAA==.Totemmonster:BAAANQABCgIIAgAAAA==.',
Tr='Trancendantx:BAAANQADCgcIBwAAAA==.Tripx:BAACNQAFFIENAAIKAAUKtw7bCQB/AQAKAAUKtw7bCQB/AQA1AAQKgSIAAgoACQoKG+ROAIACAAoACQoKG+ROAIACAAAA.Tripxed:BAABNQAECoEmAAMLAAgK5BhMLQBNAgALAAgK5BhMLQBNAgAmAAEKWgrXNAA6AAABNQAFFAUIDQAKALcOAA==.Trishan:BAAANQAECgQIBQAAAA==.Trolk:BAAANQADCgUIBwAAAA==.Tronko:BAAANQAECgUICwAAAA==.Truthjustice:BAAANQADCggJDwAAAA==.',
Tu='Turntsnaco:BAABNQAECoEtAAMRAAkK7xo1EABnAgARAAcKXx41EABnAgASAAYKaxHZXwDlAAAAAA==.Turyon:BAAANQADCgEIAQAAAA==.',
Tw='Twiztedfaith:BAAANQADCgYIBgAAAA==.',
Ul='Ulhume:BAAANQADCgEJAQABNQAECgcIGQALAC4TAA==.',
Un='Unafhaen:BAAANQADCgQIBAAAAA==.Unaverse:BAAANQADCgYIBgAAAA==.',
Ur='Urp:BAAANQAECgIIAwAAAA==.',
Us='Usmc:BAAANQADCgYIBgAAAA==.Usmccpl:BAAANQADCgYICQAAAA==.',
Va='Valengarde:BAAANQAECgcJDQAAAA==.Valentin:BAAANQABCgIIAgAAAA==.Valhalia:BAAANQABCgIIAgAAAA==.Vanderneuker:BAAANQAECgIIAwABNQAFFAQICwAWAEgYAA==.Vangoon:BAEBNQAECoEgAAISAAgKkiLsCgAaAwASAAgKkiLsCgAaAwAAAA==.Vanmonk:BAAANQAECgIIAQAAAA==.Vann:BAAANQADCgQIBwAAAA==.Vannix:BAABNQAECoEmAAIOAAgK2yO0CQAxAwAOAAgK2yO0CQAxAwAAAA==.',
Ve='Velkanos:BAAANQADCgQIBAAAAA==.Velkhaz:BAAANQABCgYIBgAAAA==.Vereena:BAAANQAECgUICwAAAA==.Vesstar:BAAANQABCggIFAAAAA==.',
Vi='Violet:BAAANQADCgMIAwAAAA==.Virmethir:BAAANQAECgQICwAAAA==.',
Vo='Voltaren:BAAANQAECgIJAgAAAA==.',
Wh='Whtmg:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.',
Wi='Winterbreeze:BAAANQADCgQIBAAAAA==.Wiwi:BAACNQAFFIELAAMWAAQKSBiFDgDyAAAWAAMKeRaFDgDyAAAVAAIKAhgtDwCeAAA1AAQKgTAAAxYACQoXHvdDAOQBABYACAp9GfdDAOQBABUABgpPHYI1AMYBAAAA.',
Wo='Woopie:BAAANQAECgEIAQAAAA==.',
Wu='Wukøng:BAAANQABCgIIAgAAAA==.',
Xa='Xake:BAAANQAECgUICgAAAA==.Xares:BAAANQAECgcIEgAAAA==.',
Xe='Xenp:BAABNQAECoEvAAMQAAkKPxa1EwBEAgAQAAkKPxa1EwBEAgAKAAQKFguoEwHHAAAAAA==.',
Xi='Xiovemm:BAAANQADCgcJBQAAAA==.',
Xu='Xuri:BAABNQAECoEXAAICAAgK8woieADwAQACAAgK8woieADwAQAAAA==.',
Yd='Ydriel:BAAANQADCgUIBwAAAA==.',
['Yö']='Yöurfired:BAAANQADCgQICAAAAA==.',
Za='Zake:BAABNQAECoEhAAICAAkK0xtFLADIAgACAAkK0xtFLADIAgAAAA==.Zalileina:BAAANQADCgMJAgAAAA==.Zantanna:BAAANQADCgYJEAAAAA==.Zappythile:BAAANQAECgYIDwAAAA==.Zayiro:BAAANQADCgYIDAAAAA==.',
Ze='Zealdavir:BAAANQABCgIIAgAAAA==.',
Zi='Zigzagoon:BAAANQABCgYIBgAAAA==.',
Zo='Zoz:BAAANQAECgEIAQAAAA==.',
Zu='Zulfrik:BAABNQAECoEbAAMbAAgKSRWQqAAQAgAbAAgKIRKQqAAQAgAcAAIKEh0OLQBuAAAAAA==.',
Zy='Zyzy:BAAANQAECgYICQABNQAFFAYIGgAOABUeAA==.',
['Äh']='Ählis:BAAANQAECgIIAgAAAA==.',
['ße']='ßeef:BAAANQAECgUICQAAAA==.',
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
