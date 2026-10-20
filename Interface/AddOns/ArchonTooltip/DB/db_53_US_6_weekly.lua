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

local lookup = {'Warlock-Demonology','Priest-Holy','Paladin-Protection','Druid-Restoration','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Druid-Feral','DemonHunter-Vengeance','Mage-Arcane','Unknown-Unknown','Hunter-BeastMastery','Mage-Fire','Mage-Frost','Warrior-Arms','Monk-Brewmaster','Priest-Discipline','Hunter-Survival','Hunter-Marksmanship','Warrior-Protection','DeathKnight-Blood','DemonHunter-Devourer','Warrior-Fury','Paladin-Holy','Paladin-Retribution','Shaman-Elemental','Monk-Windwalker','Monk-Mistweaver','Priest-Shadow','Shaman-Enhancement','Druid-Guardian','Warlock-Affliction','Warlock-Destruction','Shaman-Restoration','DemonHunter-Havoc','DeathKnight-Frost','Rogue-Assassination','Rogue-Outlaw','Rogue-Subtlety','DeathKnight-Unholy','Druid-Balance',}
local provider = {region='US',realm='Alexstrasza',name='US',type='weekly',zone=53,date='2026-10-20',data={Ac='Acbabcaa:BAAANQAECgEIAQAAAA==.Aceon:BAAANQAECgIIBAAAAA==.Aceonarcher:BAAANQAECgQICAAAAA==.',
Ad='Adfectia:BAABNQAECn8fAAIBAAkK7AlHKgBJAQABAAkK7AlHKgBJAQAAAA==.',
Ae='Aelianna:BAAANQAECgYIDAAAAA==.Aeryana:BAABNQAECn8mAAICAAoKHSIKBgCXAgACAAoKHSIKBgCXAgAAAA==.Aeth:BAAANQAECgYIDAABNQAECggIHQADALcjAA==.Aethér:BAAANQAECgYIDwABNQAFFAYIDwAEAEsWAA==.',
Ag='Aggroout:BAAANQADCgYIBgABNQAECgoKKQADAJUfAA==.',
Ah='Ahsöka:BAAANQADCgIIAgAAAA==.',
Ai='Aimbel:BAAANQADCgQICQAAAA==.',
Al='Alberoo:BAAANQABCgQIBAAAAA==.Alexstrászá:BAABNQAECn8YAAMFAAkKMwjmDgBUAQAFAAgKyQjmDgBUAQAGAAMKzwJ3NwBTAAAAAA==.Aloria:BAAANQADCgEIAQAAAA==.Alynas:BAAANQADCgUIBQAAAA==.Alysona:BAAANQADCgUIDQAAAA==.',
Am='Amaarii:BAAANQABCgQJCAAAAA==.Ambeia:BAAANQAECgIIAgAAAA==.Amewow:BAACNQAFFH8WAAIGAAYKtCM5AACgAQAGAAYKtCM5AACgAQA1AAQKfzoAAwYACgppI7MCAIYDAAYACgppI7MCAIYDAAcABgogDToMAAEBAAAA.Amoril:BAAANQAECggIEAAAAA==.Amìko:BAAANQADCggICAAAAA==.',
An='Anarchy:BAABNQAECn8hAAIIAAgKpA/bBQBcAQAIAAgKpA/bBQBcAQAAAA==.Andraxi:BAAANQADCgYICwAAAA==.Andrewchau:BAAANQAECgIIAgAAAA==.Angewomon:BAAANQADCgIIAgAAAA==.Annòy:BAABNQAECn9AAAIJAAoKFB+oAwAkAwAJAAoKFB+oAwAkAwAAAA==.Anorakswrath:BAABNQAECn8cAAIKAAkKXQQQEAFyAQAKAAkKXQQQEAFyAQAAAA==.',
Ap='Apophys:BAAANQADCggIHwAAAA==.',
Ar='Ariees:BAAANQADCgEIAQAAAA==.Ariella:BAAANQADCgQIBAAAAA==.Artfulrodent:BAAANQADCgQIBAAAAA==.Aruneza:BAABNQAECn8YAAMGAAgKdhFQHQB5AQAGAAcKjg1QHQB5AQAHAAYK9AnYLwAfAQAAAA==.',
As='Asherous:BAAANQADCgQICQABNQAECgYIEAALAAAAAA==.Ashèr:BAAANQAECgYIEAAAAA==.Asunnaa:BAAANQADCgIIAwAAAA==.',
At='Atenchion:BAAANQAECgQIBAAAAA==.Atsivacof:BAAANQABCgYICAAAAA==.Atticuz:BAAANQADCgIIAgAAAA==.',
Au='Aura:BAAANQAECgYIEQABNQAECgkJFwAMAPMSAA==.Auralion:BAAANQADCgYIBwAAAA==.Autoignition:BAABNQAECn8XAAQNAAkKthwwBAB1AQAKAAcKmh9XwgAAAgANAAUKDxswBAB1AQAOAAMKlxnnIwDOAAAAAA==.',
Ba='Badcompanytt:BAAANQADCgUIAwAAAA==.Bahnkano:BAAANQAECgcIEgAAAA==.Bakeddh:BAAANQADCgYIDAAAAA==.Balwal:BAAANQAECgIIAgAAAA==.Banditz:BAAANQADCgcIDwAAAA==.Bashfury:BAAANQAECgEIAQAAAA==.',
Be='Beefcåkes:BAABNQAECn8YAAIPAAYK9QMf+QDqAAAPAAYK9QMf+QDqAAAAAA==.Beenah:BAAANQAECgUIEQAAAA==.Beyshunt:BAAANQADCgYICgAAAA==.',
Bl='Bloodrain:BAAANQAECggIBwAAAA==.Blàst:BAAANQAECgMIBAAAAA==.',
Bo='Boltcutter:BAAANQADCgEIAQAAAA==.Bombmagic:BAAANQADCgMIAwAAAA==.Bonesmccoy:BAAANQABCgYIBgAAAA==.Boomie:BAABNQAFFH8FAAIHAAUKqCTcBAAiAgAHAAUKqCTcBAAiAgABNQAFFAgIBAALAAAAAA==.Boopty:BAAANQAECgMIBAAAAA==.Booptydo:BAAANQADCggIHQAAAA==.Boris:BAAANQAECgIIAgAAAA==.Bowhawk:BAAANQAECgYIDQAAAA==.',
Bp='Bpwhunter:BAAANQAECgQICgAAAA==.',
Br='Braiin:BAAANQAECgYICQABNQAFFAYIDwAEAEsWAA==.Brazyn:BAAANQADCggIIwAAAA==.Brevarda:BAAANQAECgYIDQAAAA==.Brewcelee:BAABNQAECn8hAAIQAAcKeA08FwBuAQAQAAcKeA08FwBuAQAAAA==.',
Bu='Bubblzmgee:BAABNQAECn8yAAIRAAkK3h3ZAADtAQARAAkK3h3ZAADtAQAAAA==.Buscemi:BAAANQADCggIDAAAAA==.Bustofez:BAAANQADCggIDgAAAA==.Buttèrs:BAAANQADCgEIAQAAAA==.',
['Bé']='Béach:BAAANQAECgMIAwAAAA==.',
Ca='Capone:BAAANQAECgcICwAAAA==.Captiva:BAAANQAECgEIAQAAAA==.Caracalous:BAAANQAECgYIDAAAAA==.Carindria:BAAANQADCggIJQAAAA==.Carninn:BAAANQADCgcIBwAAAA==.Castermcfear:BAAANQABCgIIAgAAAA==.Cattiebrie:BAAANQAECgUIDAAAAA==.Caylavana:BAABNQAECn8oAAMMAAkKOByWSwCLAgAMAAgK1h6WSwCLAgASAAMKkwiTBwCNAAAAAA==.',
Ce='Celaylria:BAABNQAECn8sAAITAAgKvxXBCwAzAQATAAgKvxXBCwAzAQAAAA==.Ceyine:BAAANQAECgEIAQAAAA==.',
Ch='Charmeleön:BAAANQADCgYIBgAAAA==.Chronicfury:BAAANQABCgIIAgAAAA==.',
Cl='Cloudedjayd:BAAANQADCgcIDgAAAA==.Cloudedmonk:BAAANQADCgUICQAAAA==.Clugorn:BAABNQAECn8jAAIUAAgK4Ay+IABIAQAUAAgK4Ay+IABIAQAAAA==.Clydè:BAAANQAECgcICQAAAA==.',
Co='Codyj:BAAANQADCggIDgAAAA==.Colossus:BAAANQADCggJCwAAAA==.Colourhunt:BAABNQAECn8YAAMTAAkKMxAwPQBoAQAMAAcKZw6MnwDHAQATAAcKCw4wPQBoAQAAAA==.Condewit:BAAANQADCgUIBQAAAA==.Conoresa:BAAANQADCgMIAwAAAA==.Copedk:BAABNQAECn8mAAIVAAgKVx2mCACuAQAVAAgKVx2mCACuAQAAAA==.Copestabb:BAAANQAECgMIAwABNQAECggIJgAVAFcdAA==.Corrode:BAAANQAECgEIAQAAAA==.Cozymav:BAAANQADCgUIBQAAAA==.',
Cp='Cpt:BAAANQADCgEIAQAAAA==.',
Cr='Crimie:BAAANQADCggICAAAAA==.Crinke:BAAANQABCgIIAgAAAA==.Crusadare:BAAANQAECgQIBAAAAA==.',
Cy='Cybeldin:BAABNQAECn8VAAMMAAgK3QWnugCOAQAMAAgK3QWnugCOAQATAAQK8QIzbgB3AAAAAA==.Cyberdemonxd:BAAANQADCgYIDAABNQAECggIDgALAAAAAA==.Cyndyr:BAAANQAECgEIAQAAAA==.',
['Cë']='Cërßerus:BAAANQADCgYIBgAAAA==.',
Da='Daddysparey:BAABNQAECn8ZAAIWAAcKlhF/MQC1AQAWAAcKlhF/MQC1AQAAAA==.Dalarrus:BAAANQAECgYIDQABNQAECgkJKAAMADgcAA==.Dalishya:BAAANQADCgQIBAAAAA==.Darek:BAAANQAECgUIEQAAAA==.Darilyns:BAAANQADCgQIBQAAAA==.Darkbiffhunt:BAAANQADCgMIAwAAAA==.Darkrife:BAAANQADCgcIGAAAAA==.Darylinn:BAAANQADCgQJBgAAAA==.Daymann:BAAANQAECgYICgAAAA==.',
De='Demonrife:BAAANQABCgYIBgABNQADCgcIGAALAAAAAA==.Dependabull:BAAANQADCgYIBgABNQAECgQICQALAAAAAA==.Dernis:BAAANQAECgIIAgABNQAECgoKLAAPAAAdAA==.Derplock:BAAANQADCgcIEAAAAA==.Deshaman:BAAANQADCgMIAwABNQAFFAUIFAAMAHwVAA==.Devilbeast:BAAANQAECgQIDQAAAA==.Dew:BAAANQABCgQIAwAAAA==.',
Dh='Dhargo:BAAANQAECgYIDgABNQAECgQICQALAAAAAA==.',
Di='Diablosauz:BAAANQADCgQIBAAAAA==.Diaous:BAAANQADCgcIEQAAAA==.Disasterina:BAAANQADCgcIBwABNQAECgoKMQAWALYdAA==.Disgruntled:BAAANQAECgcIEQAAAA==.',
Do='Docbrown:BAAANQADCgEIAQAAAA==.Dontormentaa:BAABNQAECn8dAAMPAAoKyw9tdgAzAgAPAAoKTQ9tdgAzAgAXAAEK/Bl9LQBNAAAAAA==.Dontormentaj:BAABNQAECn8iAAQOAAgKXxfiFwA7AQAKAAgK1xYpmABQAgAOAAQKHB3iFwA7AQANAAMKmRR7BwDCAAABNQAECgoKHQAPAMsPAA==.Doomzday:BAAANQADCgYIDQAAAA==.',
Dr='Dracthra:BAABNQAECn8ZAAIFAAcK1A01EgAQAQAFAAcK1A01EgAQAQAAAA==.Dragonbrew:BAAANQADCggICAAAAA==.Dragonfang:BAAANQAECgcIDgABNQAECgkJFwANALYcAA==.Drakk:BAAANQADCgUIBQABNQAECgEIAQALAAAAAA==.Dreamhammer:BAAANQABCgcIDwAAAA==.Dreamlesnite:BAAANQABCggIFAAAAA==.Dreidelman:BAAANQAECgQIBAAAAA==.Druvisept:BAAANQADCgcIBwAAAA==.',
Du='Dugdimadome:BAAANQAECgMIAwAAAA==.Dunthur:BAAANQAECgIIBAAAAA==.',
Dy='Dylora:BAAANQAECggIEwAAAA==.',
Ea='Ealdoras:BAAANQADCggIDgAAAA==.',
Eg='Egg:BAABNQAECn8qAAMYAAoKtyGJCQB8AwAYAAoKtyGJCQB8AwAZAAEKqAw/wwEnAAABNQAFFAcIHAACAPUWAA==.',
El='Elassha:BAAANQADCggICwAAAA==.Elatio:BAABNQAECn8aAAIKAAgKAhivXQACAQAKAAgKAhivXQACAQAAAA==.Elfairea:BAAANQADCgEIAQAAAA==.Elmortal:BAAANQAECgYIDAAAAA==.Elystaria:BAAANQAECgUIEwAAAA==.',
Em='Emokins:BAEBNQAECn8ZAAIaAAgK0iEyJwDmAgAaAAgK0iEyJwDmAgAAAA==.',
En='Enyos:BAAANQADCgcIDwAAAA==.',
Ep='Epicnakedman:BAAANQAECggICAABNQAECgoKMwAYAHIWAA==.',
Er='Eronoljr:BAAANQADCgEIAQAAAA==.Erubus:BAABNQAECn81AAQQAAoKfiEPAwBpAwAQAAoKfiEPAwBpAwAbAAQKyBYsPgAlAQAcAAIKagl5IgA4AAAAAA==.Erubuss:BAAANQAECgYICwAAAA==.Eryss:BAAANQAECgUIEwAAAA==.',
Ex='Excalibúr:BAAANQADCgcIBwAAAA==.',
Fa='Faithfulone:BAAANQAECgUIEwAAAA==.Farfidnoogan:BAAANQABCgQIBAAAAA==.Fateforged:BAAANQABCgIIAgABNQAECgIIBAALAAAAAA==.Fatercul:BAAANQADCgEIAQAAAA==.',
Fd='Fdk:BAAANQAECgcIEAAAAA==.',
Fe='Fellariene:BAAANQADCggICwAAAA==.',
Fi='Fistenlick:BAAANQADCgMIAwABNQADCggIDgALAAAAAA==.',
Fo='Forilla:BAAANQAECgQIBQAAAA==.Fortissimo:BAAANQADCgYICwAAAA==.',
Fr='Freim:BAAANQAFFAEIAQAAAA==.',
['Fà']='Fàmous:BAAANQAECgcICQAAAA==.',
Ga='Galabris:BAABNQAECn8ZAAIVAAgK/hvrKQB1AgAVAAgK/hvrKQB1AgAAAA==.Gasilbench:BAAANQAECgEIAQAAAA==.Gazzik:BAAANQAECgMIAwAAAA==.',
Ge='Gera:BAAANQAECgEIAQAAAA==.',
Gh='Ghostboydk:BAAANQADCgYIBgABNQAECggICgALAAAAAA==.Ghoulmania:BAAANQAECggIAwAAAA==.',
Gi='Gimligrimes:BAAANQADCgYIBgAAAA==.Gington:BAAANQAECgUICgAAAA==.Gitchusum:BAAANQAECgYIBgAAAA==.',
Gl='Glaivenez:BAAANQAECggIBgAAAA==.Gleenna:BAAANQAECgcIEQAAAA==.Glorify:BAAANQAECgIIAwABNQAECgkJHAAVAGobAA==.',
Go='Goose:BAABNQAECn8pAAMCAAkK0iEaFgAhAwACAAkK0iEaFgAhAwARAAEK3BevJABGAAAAAA==.Gormladin:BAAANQADCgYIFwAAAA==.Gormstorm:BAAANQAECgUIEQAAAA==.',
Gr='Greenbahamut:BAAANQADCgEIAQAAAA==.Grimsreaper:BAAANQADCgQIBAAAAA==.Grouchy:BAAANQADCgQIBgABNQAECgcIEAALAAAAAA==.',
Gw='Gwynythe:BAAANQADCgEIAQAAAA==.',
Ha='Hadriac:BAAANQAECgIIAgAAAA==.Hailes:BAAANQABCgIIAQAAAA==.Halfang:BAAANQADCggILgAAAA==.Hanta:BAABNQAECn8YAAIMAAoKCQ7EbQA3AgAMAAoKCQ7EbQA3AgAAAA==.Haplò:BAAANQAECgEIAgAAAA==.Hastebuff:BAAANQAECgYICwAAAA==.',
He='Hentaime:BAAANQABCgMIAwAAAA==.',
Hi='Hildegarde:BAAANQADCggICAABNQAECgMIBQALAAAAAA==.Hitpoints:BAAANQADCgYIDAABNQAECgcIGAAdAMIMAA==.',
Ho='Holispirit:BAAANQABCgMIAwAAAA==.Holyfrog:BAAANQAECgUICgAAAA==.Holyhannah:BAAANQADCgcIBwAAAA==.Holyhope:BAABNQAECn8zAAIYAAoKchbIPwBlAgAYAAoKchbIPwBlAgAAAA==.Holylightz:BAAANQAECgYICgAAAA==.Holymana:BAABNQAECn8lAAMZAAoKdh3FCABVAgAZAAoKdh3FCABVAgADAAIKvweXZQBLAAAAAA==.Holymilkers:BAAANQADCggIDQABNQAECgkJKwAeAMAKAA==.Honeybunns:BAAANQADCgUIBQAAAA==.Hosstx:BAAANQADCgEIAQAAAA==.Hotandready:BAABNQAECn8gAAIfAAcKqQpAGwCxAAAfAAcKqQpAGwCxAAAAAA==.',
Hu='Huffingpaint:BAAANQADCgYIDgABNQAECgMIBQALAAAAAA==.Hukhokhan:BAAANQADCggIDwAAAA==.Hutzil:BAABNQAECn8kAAQgAAoKmhcwCAAPAgABAAkKDxgJawAcAgAgAAcK0RQwCAAPAgAhAAIKfQ/LVwB4AAAAAA==.Hutzilla:BAAANQABCgYICAAAAA==.',
Ia='Iakopa:BAABNQAECn8xAAMaAAoKrxu2KQDaAgAaAAkKDR22KQDaAgAiAAUKNgeyvwDqAAAAAA==.',
Il='Illidianna:BAABNQAECn8nAAMWAAkKlRvYBADLAQAjAAcKSxwmNwD3AQAWAAkKEBvYBADLAQAAAA==.',
Im='Imfiredup:BAAANQAECggIBQAAAA==.Imitlol:BAABNQAECn8YAAIZAAcKbyRPYQB2AgAZAAcKbyRPYQB2AgAAAA==.',
In='Inception:BAAANQAECgEIAQAAAA==.Ingress:BAAANQADCgYJBgAAAA==.',
Is='Ishu:BAAANQADCgIIAwAAAA==.',
It='Itchynyple:BAAANQADCggIGAAAAA==.Ithowen:BAAANQABCgYIBgAAAA==.',
Ja='Jacques:BAAANQAECgQIBAAAAA==.Jaetherion:BAABNQAECn8fAAMZAAcKtSPaFwDEAQAZAAcKtSPaFwDEAQADAAEKEgkkcgAtAAAAAA==.Jakes:BAAANQADCgYJDAAAAA==.Jayhawk:BAAANQAECgEIAwAAAA==.',
Ji='Jimothy:BAAANQADCgcIEwABNQAFFAcIEAAaAJEdAA==.Jinx:BAAANQAECgIIAgAAAA==.',
Jo='Johaliz:BAAANQADCgEIAQAAAA==.Johnnypopoff:BAAANQADCgYIBgAAAA==.Jojohunts:BAAANQAECgEIAQAAAA==.Jonesy:BAAANQADCggICgABNQAECgkJRAAMAIcXAA==.',
Ju='Junyubych:BAAANQADCgYIHgABNQAECgUIEgALAAAAAA==.',
['Jà']='Jàccuse:BAAANQADCgUIDAABNQAECgcIGQAFANQNAA==.Jàrnsaxa:BAAANQADCggIJgAAAA==.',
['Jò']='Jòhnnypopo:BAABNQAECn8lAAIZAAgKIhiqLgB0AQAZAAgKIhiqLgB0AQAAAA==.',
Ka='Kaeladra:BAAANQABCgQIBgABNQAECgEIAwALAAAAAA==.Kagé:BAAANQADCgEIAQAAAA==.Kaisra:BAAANQAECgUICAAAAA==.Kalida:BAAANQADCgUIBQAAAA==.Kasumeli:BAAANQAECgYIDAAAAA==.Kathelas:BAAANQADCgYIBgAAAA==.Kayd:BAAANQADCggIHQAAAA==.Kayhan:BAAANQADCgQICgAAAA==.Kaylaiis:BAAANQADCggICAAAAA==.Kaylastrasza:BAAANQADCgQIBAAAAA==.Kayos:BAAANQAECgEIAQAAAA==.Kazoo:BAAANQADCgMIAwABNQAECgIIAgALAAAAAA==.Kazurend:BAACNQAFFH8RAAMdAAcKDBudBQDaAQAdAAYKCB+dBQDaAQACAAIKSgoaJgCiAAA1AAQKfyYAAx0ACgoeIqAMACADAB0ACgoeIqAMACADAAIAAgrwEufdAI8AAAAA.',
Ke='Keish:BAAANQADCggICAAAAA==.Keleira:BAAANQAECgQIBAABNQAECgUICgALAAAAAA==.Keyaielenst:BAAANQADCgYICwAAAA==.',
Kh='Khirina:BAABNQAECn8YAAMbAAgKKQwUNQBsAQAbAAgKKQwUNQBsAQAcAAMKwAjCPwB5AAAAAA==.Khristina:BAABNQAECn8ZAAIYAAcKEBxxWwAGAgAYAAcKEBxxWwAGAgAAAA==.Khrogh:BAAANQAECgEIAwAAAA==.',
Ki='Kidiann:BAAANQAECgYIDQAAAA==.Kippo:BAEANQAECgcICAAAAA==.Kirar:BAAANQAECgIIAgAAAA==.Kisarrah:BAAANQABCgMIAwAAAA==.',
Kn='Knarn:BAABNQAECn8lAAIMAAkKiiAOCQA1AgAMAAkKiiAOCQA1AgAAAA==.Knazugardarg:BAAANQAECgIIAgAAAA==.',
Ko='Kohde:BAABNQAECn8VAAMTAAgKlhQ3MwC0AQATAAgKwBI3MwC0AQAMAAYKWRI+1QBWAQABNQAFFAkJJwATAH8iAA==.Koralie:BAACNQAFFH8WAAIMAAYK/h2SBAAQAgAMAAYK/h2SBAAQAgA1AAQKfykAAgwACgoGJL4QAGADAAwACgoGJL4QAGADAAAA.Korrum:BAAANQABCgIIAgAAAA==.',
Kr='Krillaxx:BAAANQAECgQIBAAAAA==.',
Kt='Ktullanux:BAAANQAECgIIAgABNQAECgoKMQAkALYiAA==.',
Ky='Kyliekat:BAAANQAECgYIEwAAAA==.',
['Kå']='Kåiri:BAAANQAECgEIAQAAAA==.',
La='Lanceelot:BAAANQAECgQIBAAAAA==.Lanel:BAAANQAECgUJCgAAAA==.Lathelous:BAABNQAECn8eAAIDAAgK4SFIDQDHAgADAAgK4SFIDQDHAgAAAA==.Laulten:BAAANQABCgQIBAAAAA==.',
Le='Leintheir:BAAANQAECgYIEAAAAA==.',
Li='Lideina:BAAANQADCgUIBwAAAA==.Lieahi:BAAANQAECgIIAQAAAA==.Liebesleid:BAAANQADCgYICwABNQAECgMIBQALAAAAAA==.Lightt:BAABNQAECn9CAAICAAoKwBgrCgBBAgACAAoKwBgrCgBBAgAAAA==.Liightt:BAABNQAECn8qAAICAAgKjhveCABYAgACAAgKjhveCABYAgAAAA==.Lilcozz:BAAANQAECgEIAQAAAA==.Lilpyroblast:BAABNQAECn8eAAIKAAoKuBZibwCfAgAKAAoKuBZibwCfAgAAAA==.Liriope:BAAANQADCggIEgAAAA==.Lizbethstar:BAAANQADCggIDAAAAA==.',
Ll='Llaerwyn:BAAANQADCgUJBwAAAA==.Llars:BAABNQAECn8lAAIiAAkKiRIDJABVAQAiAAkKiRIDJABVAQAAAA==.',
Lo='Loryanna:BAAANQADCgYIHgAAAA==.Louie:BAAANQAECgUIBwAAAA==.Lovehandless:BAAANQADCgIIAgAAAA==.',
Lu='Lumenne:BAAANQADCgUIBwAAAA==.Luxore:BAABNQAECn8gAAIDAAoKVw+sHgDzAQADAAoKVw+sHgDzAQABNQAECgoKMQAaAK8bAA==.',
Ly='Lyandrea:BAAANQADCggIIwAAAA==.Lyfebane:BAAANQADCgUJBQAAAA==.Lynaomira:BAAANQADCgMIAwAAAA==.',
['Lõ']='Lõrs:BAAANQADCgMIBQAAAA==.',
['Lø']='Lørs:BAAANQAECgYIEQAAAA==.',
Ma='Main:BAABNQAECn8vAAIZAAoKWQvnqwDIAQAZAAoKWQvnqwDIAQAAAA==.Majrmiståke:BAACNQAFFH8SAAMOAAUKrw/3BQCxAAAKAAUKcgwIJwBPAQAOAAMKAQX3BQCxAAA1AAQKfyIAAw4ACgqDG4cGAJgCAA4ACAqlGocGAJgCAAoACgrWFEmOAGMCAAE1AAQKCgouABgAthQA.Malakir:BAAANQADCgYIEwAAAA==.Malaxxus:BAAANQADCgEIAQAAAA==.Malendorei:BAAANQAECgQIDgAAAA==.Malicemech:BAAANQADCgcIIwAAAA==.Maliceone:BAAANQADCggIJAAAAA==.Malicepaly:BAAANQADCgcIEwAAAA==.Mallucavian:BAAANQAECgUIEAAAAA==.Mamadp:BAABNQAECn8VAAIkAAUK+AdcdQDMAAAkAAUK+AdcdQDMAAAAAA==.Manaholy:BAAANQADCggIDQAAAA==.Manek:BAABNQAECn9EAAIMAAkKhxczJwB9AQAMAAkKhxczJwB9AQAAAA==.Marraxa:BAABNQAECn8UAAQlAAcKDQW1XgA7AQAlAAcKDQW1XgA7AQAmAAQKYgPLFACmAAAnAAMKBQJ2SAB2AAAAAA==.Maräjade:BAAANQABCgYJBgAAAA==.Max:BAABNQAECn8aAAMBAAkK0hVpbAAZAgABAAgKmBNpbAAZAgAhAAMKlROVQQC9AAAAAA==.',
Me='Melevil:BAAANQAECgcIDwAAAA==.Melinoe:BAAANQADCgIIAgAAAA==.Merlin:BAAANQAECgQIBgAAAA==.Merlise:BAAANQADCgcICgAAAA==.Metalgreymon:BAAANQADCgIIAgAAAA==.',
Mi='Milenad:BAAANQAECgYIDAAAAA==.Milho:BAAANQADCgYIBgABNQAFFAIICAAjAEYiAA==.Milkmeholy:BAAANQADCgcICQAAAA==.Mishosuki:BAAANQAECgUIDwAAAA==.Misscleo:BAABNQAECn8hAAIKAAgK5g/M0gDhAQAKAAgK5g/M0gDhAQAAAA==.Mistalar:BAAANQAECgUIBgAAAA==.',
Mn='Mnesarte:BAAANQADCgUIBQAAAA==.',
Mo='Moltres:BAEANQAECggIBQAAAA==.Mongoro:BAAANQADCgEIAQAAAA==.Moonkist:BAAANQAECgUIEwAAAA==.Moose:BAABNQAECn8bAAMoAAkKbB1LGQD1AgAoAAkKbB1LGQD1AgAVAAEKAABcwgBDAAAAAA==.Mordrandian:BAAANQAECgEIAQAAAA==.',
Mu='Muffindk:BAAANQAECgQIBAAAAA==.Muffintop:BAAANQADCggIEQAAAA==.',
['Mó']='Mórningstar:BAAANQADCgIIBAAAAA==.',
Na='Nadless:BAAANQAECgMIAwAAAA==.Naeliria:BAAANQADCggICAAAAA==.Namuss:BAAANQADCgIIAwAAAA==.Narokatha:BAAANQAECgIIAgAAAA==.',
Ne='Necropanzer:BAAANQAECggIEwABNQAECgkJFwANALYcAA==.Nelrehim:BAAANQAECgUICgAAAA==.',
Ni='Niall:BAAANQAECgEIAQABNQAECgkJKAAMADgcAA==.Niandilan:BAAANQADCgYICgAAAA==.Niixxi:BAAANQADCgEIAQAAAA==.',
Nm='Nmbrs:BAAANQADCgYIDwABNQAECgcIEAALAAAAAA==.',
No='Noirah:BAAANQADCgcIBwAAAA==.Noirheffer:BAABNQAECn8pAAMDAAoKlR+oEACUAgADAAoKlR+oEACUAgAZAAUK/xU36QBJAQAAAA==.Nokua:BAAANQAECgUIEgAAAA==.Noodles:BAABNQAECn8hAAIpAAoKrgnuUACZAQApAAoKrgnuUACZAQAAAA==.',
Nu='Nulannatoo:BAAANQAECgYICAAAAA==.',
Ny='Nyank:BAAANQAECgMIAgABNQAECggIDgALAAAAAA==.Nyleaf:BAAANQADCgUIBwAAAA==.Nyogen:BAAANQAECggJBgAAAA==.Nyxaraa:BAAANQADCgYIEAAAAA==.',
Oc='Octomore:BAABNQAECn8lAAIKAAkK1REbHwCUAQAKAAkK1REbHwCUAQAAAA==.',
Od='Odysseus:BAABNQAECn8gAAITAAkKvQ+3LADlAQATAAkKvQ+3LADlAQAAAA==.',
Ol='Olgann:BAAANQAECgUIBgAAAA==.Olguita:BAAANQAECgYIEgAAAA==.',
Om='Omez:BAAANQAECgYICgABNQAFFAQIBAALAAAAAA==.Omgowned:BAAANQAECgIIAgABNQAECgcIGAABAMoVAA==.',
On='Onehothealer:BAAANQADCgYIBwAAAA==.',
Oo='Oorua:BAAANQADCggIGQAAAA==.',
Op='Opheliastar:BAABNQAECn8tAAIdAAoKZxU4HwBDAgAdAAoKZxU4HwBDAgAAAA==.',
Or='Ordovis:BAAANQAECgUIDAAAAA==.Orlucicia:BAAANQAECgIIAgAAAA==.Orobas:BAAANQAECggIAgAAAA==.',
Ow='Owltoidz:BAAANQABCgYIBwAAAA==.',
Pa='Pace:BAAANQABCgYICgAAAA==.Pad:BAAANQAECgUIEwAAAA==.Paladerp:BAAANQAECgcIEAAAAA==.Palanym:BAABNQAECn8lAAIYAAgK6BWbWAAPAgAYAAgK6BWbWAAPAgAAAA==.Palidyne:BAAANQAECgUIBgAAAA==.Pallyown:BAAANQAECgcIEAAAAA==.Papamidnite:BAAANQADCgMIAwAAAA==.Papichulo:BAAANQADCgcIDQAAAA==.Parox:BAAANQADCgYICAAAAA==.',
Pe='Peluij:BAAANQAECgQIBAAAAA==.',
Ph='Phelement:BAABNQAECn8eAAIeAAoKSSLmAwBbAwAeAAoKSSLmAwBbAwAAAA==.Pheta:BAAANQADCggICAAAAA==.Phett:BAABNQAECn8rAAMXAAoKVSCKBADwAgAXAAgKJSOKBADwAgAPAAYKMBgfWgDlAAAAAA==.Phonk:BAAANQAECgEIAQABNQAECgoKHgAeAEkiAA==.Phædrea:BAAANQADCggICAAAAA==.',
Pi='Picklës:BAAANQADCgUIBQABNQAECgkJKQACANIhAA==.Piffi:BAAANQAECgEIAgAAAA==.Pimmscup:BAAANQADCggIHAAAAA==.',
Po='Porgoon:BAAANQAECgEIAQAAAA==.',
Pr='Praedthy:BAAANQAFFAIIAgAAAA==.',
Qo='Qohelet:BAAANQAECgQIBQAAAA==.',
Ra='Raatus:BAAANQAECgIIAgABNQAECgkJHQAVAEIiAA==.Raenya:BAAANQAECgIIAgAAAA==.Raikouu:BAABNQAECn8ZAAIBAAcKXwhwVwDTAAABAAcKXwhwVwDTAAAAAA==.Rainydaze:BAAANQAECgMIBQAAAA==.Ramani:BAAANQADCgEIAQAAAA==.Ramasses:BAAANQADCgYICgAAAA==.Ramcharger:BAAANQAECgEIAQABNQAECgkJKAAMADgcAA==.Ramoreo:BAAANQAECgUIDgABNQAECggIQgAjAGwKAA==.Rashun:BAABNQAECn8jAAMQAAkKQRfGBAA/AQAbAAgKshkPIQAkAgAQAAcKiQvGBAA/AQAAAA==.Raviolee:BAAANQAECgEIAQABNQAECgcIGAABAMoVAA==.Rayvin:BAAANQADCggIBwAAAA==.',
Re='Reanatilax:BAAANQABCgMJBQABNQAECgcIGwACALQdAA==.Regnier:BAAANQADCggIEAAAAA==.Relaeh:BAAANQADCgcJDQAAAA==.Resusitate:BAAANQADCgYJBgAAAA==.Rev:BAAANQAECgQIBAAAAA==.Rexxy:BAAANQADCgcICwAAAA==.',
Rh='Rhod:BAAANQADCgcICwABNQAECggIEQALAAAAAA==.',
Ri='Rikashae:BAAANQADCgYJBgAAAA==.Rissa:BAAANQADCgEIAQAAAA==.Risuku:BAAANQADCgEIAQAAAA==.',
Ro='Roleon:BAAANQADCggIDgAAAA==.Rollforpi:BAAANQAECgIIAgABNQAFFAYIDwAEAEsWAA==.Ropebunnyana:BAAANQAECgIJAwABNQAECgoKJgACAB0iAA==.',
Ru='Ruki:BAAANQAECgMIBQAAAA==.Rumshwizzle:BAAANQADCgQJBAAAAA==.',
Sa='Saltydk:BAABNQAECn8gAAIoAAkKhyClJACuAgAoAAkKhyClJACuAgAAAA==.Samiracy:BAABNQAECn8UAAIhAAgKNBhKDAAyAgAhAAgKNBhKDAAyAgAAAA==.Sannrin:BAAANQADCgMIAwAAAA==.Sataro:BAAANQABCggIDAAAAA==.',
Sc='Scappe:BAABNQAECn8dAAIVAAkKQiLlHADJAgAVAAkKQiLlHADJAgAAAA==.Schniel:BAAANQAECgYIDgAAAA==.',
Se='Seefoof:BAAANQADCgIIAgAAAA==.Seitaer:BAAANQADCgEJAQAAAA==.Senbatorii:BAABNQAECn8ZAAQEAAcKuRqNQAAiAQAEAAUKDheNQAAiAQApAAUKXg6EdQD1AAAIAAIKTArCNgBlAAAAAA==.Sentrosi:BAAANQAECgEIAQAAAA==.Sethrow:BAABNQAECn8YAAMBAAcKyhXxoACUAQABAAYKRxXxoACUAQAhAAEK1ReEbgBCAAAAAA==.Severa:BAABNQAECn8dAAIZAAoKehM1TAAsAQAZAAoKehM1TAAsAQAAAA==.',
Sh='Shadoh:BAAANQAECgIIAgAAAA==.Shamazing:BAAANQADCgEIAQAAAA==.Shamwowsale:BAAANQADCgYIDAAAAA==.Shamwowza:BAABNQAECn8vAAIiAAoK6A92JQBOAQAiAAoK6A92JQBOAQAAAA==.Shantifa:BAAANQADCggIDgAAAA==.Shengari:BAAANQADCgIIAgABNQADCgQIBAALAAAAAA==.Shoshanaa:BAAANQADCgYIEQAAAA==.Shotcallà:BAAANQADCgYIBwABNQADCggICAALAAAAAA==.Shuna:BAAANQADCgYICQAAAA==.Shyly:BAAANQAECgIIAgAAAA==.',
Si='Siley:BAABNQAECn8/AAIoAAoKDQ/aEgBGAQAoAAoKDQ/aEgBGAQAAAA==.',
Sn='Sneakysneak:BAABNQAECn8ZAAImAAgKvRQUBwBOAgAmAAgKvRQUBwBOAgAAAA==.Snüff:BAAANQADCgMIAwAAAA==.',
So='Somavan:BAAANQADCgMIAwABNQAECgkJKAAMADgcAA==.Somepriest:BAABNQAECn8iAAIdAAkKeyAbAQCxAgAdAAkKeyAbAQCxAgAAAA==.Sotteria:BAAANQABCgQIBAAAAA==.',
Sp='Spiarmf:BAAANQADCgMIAwAAAA==.Spicyness:BAAANQADCgIIAgAAAA==.Sprockett:BAAANQADCggICAAAAA==.Spycmchaggis:BAAANQAECgMIBAAAAA==.Spëcter:BAAANQAECgUICwABNQAECgkJJQAKANURAA==.',
Sq='Squishypoo:BAAANQAECgUIBwAAAA==.',
St='Staticpower:BAAANQAECggIAQAAAA==.Stiffkitten:BAAANQADCgEJAQAAAA==.Stoked:BAAANQADCgUIBQAAAA==.Sturba:BAAANQABCgIIAgAAAA==.',
Su='Sugrace:BAAANQADCgQIBAAAAA==.Sunaerosinda:BAAANQADCgYIBgAAAA==.Sunow:BAAANQADCgYIFwAAAA==.Superdemonzz:BAAANQAECggIDwABNQAECgoKLgAYALYUAA==.Superpallyz:BAABNQAECn8uAAQYAAoKthQZSwA8AgAYAAoKthQZSwA8AgAZAAEKAADMoQE2AAADAAEKAADrfAAgAAAAAA==.Superspidey:BAAANQADCgIIAgAAAA==.',
Sw='Swipeleft:BAABNQAECn82AAIpAAkKhBZQMgBRAgApAAkKhBZQMgBRAgAAAA==.',
Sy='Sylora:BAAANQADCgIIAgAAAA==.',
Ta='Tabarnak:BAABNQAECn8oAAIeAAoKURvsAwBaAwAeAAoKURvsAwBaAwABNQAFFAIIBwAbANMeAA==.Taiynn:BAAANQADCggIFwAAAA==.Tallon:BAACNQAFFH8HAAIfAAQKdBavAQDTAAAfAAQKdBavAQDTAAA1AAQKfxUAAh8ACQpdH/sJANICAB8ACQpdH/sJANICAAAA.Tarogen:BAAANQAECgUIDgAAAA==.Taszherazade:BAAANQADCgEJAQAAAA==.',
Te='Teknique:BAAANQAECgIIAgAAAA==.Tempestclaw:BAAANQADCgUIBQAAAA==.Tendroni:BAABNQAECn8aAAIjAAkKoQ3nNgD5AQAjAAkKoQ3nNgD5AQAAAA==.Tervor:BAAANQAECgIIAgAAAA==.Tessadin:BAAANQADCgEJAQAAAA==.',
Th='Thanamoros:BAABNQAECn8tAAIJAAoKdhE4CwAeAgAJAAoKdhE4CwAeAgABNQAECgoKMQAaAK8bAA==.Theredwake:BAAANQAECgYICgAAAA==.Theroach:BAAANQAECgIIAwAAAA==.Thgiewerom:BAAANQABCgYIBwAAAA==.Throfin:BAAANQAECgYIBgAAAA==.Thwaxi:BAAANQADCgQICAAAAA==.',
Ti='Timeismoney:BAAANQADCggIJwAAAA==.Tinydeath:BAAANQAECgMIBwAAAA==.Tiognaska:BAAANQAECgQICAAAAA==.Tirdain:BAAANQADCgEIAQAAAA==.',
To='Toeren:BAACNQAFFH8UAAIMAAUKfBXhCwCSAQAMAAUKfBXhCwCSAQA1AAQKfzIAAgwACgquIuQVAEQDAAwACgquIuQVAEQDAAAA.Tokå:BAAANQADCgIIAgAAAA==.Torage:BAAANQAECgEJAQAAAA==.Tormentah:BAAANQADCgIIAgABNQAECgoKHQAPAMsPAA==.Torosentado:BAAANQAECgQICAAAAA==.',
Tr='Tregan:BAAANQAECgIIAgAAAA==.Trenity:BAAANQAECgMIBAAAAA==.Triplecanopy:BAAANQAECgEIAQAAAA==.Trumu:BAAANQAECgEIAQAAAA==.Trïsh:BAAANQAECgIIAgABNQAECgUIDgALAAAAAA==.',
Ty='Tyinorin:BAAANQAECgEIAQAAAA==.',
['Tä']='Täryn:BAAANQADCgEIAQAAAA==.',
Ub='Ubee:BAABNQAECn8cAAIWAAcK/A4BEgAiAQAWAAcK/A4BEgAiAQAAAA==.',
Ud='Udderjustice:BAABNQAECn8lAAIDAAcKKA7IMQBSAQADAAcKKA7IMQBSAQAAAA==.',
Ug='Uglyelf:BAABNQAECn8aAAIMAAcK3QjQVgACAQAMAAcK3QjQVgACAQAAAA==.',
Ul='Ultimakitty:BAAANQAECgMIAgAAAA==.',
Un='Uncertainty:BAAANQADCgUIBQABNQAECgMIBQALAAAAAA==.Unchanged:BAAANQAECgIIAgAAAA==.',
Va='Vaeldrin:BAAANQADCgUIBQAAAA==.Vanhellsings:BAAANQAECgEIAQAAAA==.Vantrix:BAABNQAECn8+AAMpAAoK2RjMHQDbAgApAAoK2RjMHQDbAgAEAAYKohBWOABbAQABNQAECgoKMQAaAK8bAA==.Varabo:BAAANQAECgUIBwAAAA==.Varolina:BAAANQADCggIJQAAAA==.',
Ve='Velmara:BAAANQABCgMIAwAAAA==.Velthala:BAABNQAECn8YAAIPAAkKPxiFEgDEAQAPAAkKPxiFEgDEAQAAAA==.Velyra:BAAANQAECgUICgAAAA==.',
Vi='Vitner:BAAANQADCgMIBAABNQAECgkJGAABAK0XAA==.Vivieneaux:BAAANQABCgUICAAAAA==.Vixsen:BAAANQABCgcIDQAAAA==.',
Vl='Vladdawngard:BAAANQAECggICAAAAA==.',
Vo='Voidcorpse:BAAANQADCgEIAQAAAA==.Voidmama:BAAANQADCgYIBgAAAA==.Voidryn:BAAANQABCgcIEQAAAA==.Voidshifter:BAAANQADCgUIBQAAAA==.Vosaleana:BAAANQAECgUIDAAAAA==.',
Vr='Vraak:BAACNQAFFH8PAAIEAAYKSxZRBADpAQAEAAYKSxZRBADpAQA1AAQKfyQAAwQACgqoIx8GAGEDAAQACgqoIx8GAGEDACkAAgrrHGeHALUAAAAA.',
Vu='Vulcus:BAAANQAECgMIBQABNQAFFAYIDwAEAEsWAA==.',
Vy='Vyndarien:BAAANQABCgcICgAAAA==.',
Wa='Wa:BAAANQAECgUIDwAAAA==.Walimagus:BAAANQAECgIIAgAAAA==.Wayofthemist:BAAANQABCgIIAgAAAA==.',
Wc='Wcreator:BAAANQAECgIIAgAAAA==.',
Wh='Wheeljack:BAAANQAECgcIEQABNQAFFAEIAQALAAAAAA==.',
Wi='Widowcancer:BAAANQADCgIJAgAAAA==.Will:BAACNQAFFH8KAAIZAAQKEiGVAwAqAQAZAAQKEiGVAwAqAQA1AAQKfy4AAhkACgplI9EJAK4DABkACgplI9EJAK4DAAAA.',
Wo='Womdalie:BAAANQADCggIGwAAAA==.',
Wy='Wyckedpally:BAAANQAECgUIEQABNQAECgUIEgALAAAAAA==.',
Xa='Xanthös:BAAANQAFFAIIAgABNQAFFAYIDwAEAEsWAA==.',
Xe='Xemnastrasza:BAABNQAECn8rAAMFAAoKLBRsCAAQAgAFAAkKaBJsCAAQAgAGAAgK4BU0FAALAgABNQAECgoKMQAaAK8bAA==.Xenonne:BAAANQAECgMIBAABNQAFFAQIBgAYAI4MAA==.',
Xo='Xolither:BAABNQAECn8bAAICAAcKtB1lXwADAgACAAcKtB1lXwADAgAAAA==.',
Yo='Yorgo:BAAANQADCggICAAAAA==.Yourwifesbf:BAABNQAECn8qAAIUAAoK5xUgDAB1AgAUAAoK5xUgDAB1AgAAAA==.Yourwivesbf:BAAANQADCggICQAAAA==.',
Yu='Yuura:BAAANQAECgMIBAAAAA==.',
Za='Zachdemon:BAABNQAECn8oAAIJAAgKhBSZDgDPAQAJAAgKhBSZDgDPAQAAAA==.Zarulu:BAAANQAECgIIAgABNQAECgoKMQAaAK8bAA==.Zazoo:BAAANQABCgEIAQAAAA==.',
Ze='Zeeblax:BAAANQADCggICAAAAA==.Zenyátta:BAAANQAECgUIDAAAAA==.Zephymoo:BAABNQAECn9BAAMIAAoKPhodAgDgAQAIAAkKAxodAgDgAQApAAQKhhZObwANAQAAAA==.Zeretha:BAAANQABCgIIAgAAAA==.Zershadowi:BAAANQAECgEIAQAAAA==.Zertfelgard:BAAANQABCgcICgAAAA==.Zeyana:BAABNQAECn8YAAMJAAkKBREdBgAiAQAJAAkKBREdBgAiAQAjAAYKtQQeaADYAAABNQAECgoKLQAMAMgcAA==.',
Zh='Zhengshi:BAABNQAECn8VAAIQAAgKsAnZFwBlAQAQAAgKsAnZFwBlAQAAAA==.',
Zi='Zinsatra:BAAANQADCgEIAQAAAA==.',
Zk='Zkarlyse:BAAANQAECgcIDQAAAA==.',
Zo='Zoose:BAABNQAECn8ZAAQPAAgKXRcaigADAgAPAAgKXhQaigADAgAUAAQK6RnrKQDrAAAXAAEKhg6SMwA0AAAAAA==.Zosahe:BAABNQAECn8bAAMbAAgKTw2LCQB4AQAbAAcKTw2LCQB4AQAcAAcK3AcxKwAVAQAAAA==.Zoser:BAABNQAECn8cAAIbAAcK4iTOEQDQAgAbAAcK4iTOEQDQAgAAAA==.',
Zs='Zsófia:BAAANQADCgcIBwAAAA==.',
Zu='Zuckuss:BAAANQAECgEIAQAAAA==.',
Zy='Zymri:BAAANQADCgUICQABNQAECgUIEQALAAAAAA==.',
['Æl']='Ælthan:BAAANQAECgEIAQAAAA==.',
['Ér']='Érubus:BAAANQAECgMIBgAAAA==.',
['Ôr']='Ôrdra:BAAANQAECggICAAAAA==.',
['Öl']='Ölivê:BAABNQAECn8WAAIVAAcKDQpvcAA0AQAVAAcKDQpvcAA0AQAAAA==.',
['ßu']='ßugs:BAABNQAECn8fAAIMAAcK6hqVQAA1AQAMAAcK6hqVQAA1AQAAAA==.',
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
