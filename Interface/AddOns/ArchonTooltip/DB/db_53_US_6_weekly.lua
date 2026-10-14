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

local lookup = {'Warlock-Demonology','Priest-Holy','Paladin-Protection','Druid-Restoration','Evoker-Devastation','Evoker-Preservation','Druid-Feral','DemonHunter-Vengeance','Mage-Arcane','Unknown-Unknown','Warrior-Arms','Monk-Brewmaster','Priest-Discipline','Hunter-BeastMastery','Hunter-Survival','Hunter-Marksmanship','Warrior-Protection','DeathKnight-Blood','DemonHunter-Devourer','Warrior-Fury','Mage-Frost','Mage-Fire','Evoker-Augmentation','Paladin-Holy','Paladin-Retribution','Shaman-Elemental','Monk-Windwalker','Monk-Mistweaver','Priest-Shadow','Shaman-Enhancement','Druid-Guardian','Warlock-Affliction','Warlock-Destruction','Shaman-Restoration','DemonHunter-Havoc','DeathKnight-Frost','DeathKnight-Unholy','Druid-Balance','Rogue-Outlaw',}
local provider = {region='US',realm='Alexstrasza',name='US',type='weekly',zone=53,date='2026-10-13',data={Ac='Acbabcaa:BAAANQAECgEIAQAAAA==.Aceon:BAAANQAECgIIBAAAAA==.Aceonarcher:BAAANQAECgQICAAAAA==.',
Ad='Adfectia:BAABNQAECn8YAAIBAAgKlApYnQCXAQABAAgKlApYnQCXAQAAAA==.',
Ae='Aelianna:BAAANQAECgYIDAAAAA==.Aeryana:BAABNQAECn8eAAICAAkKCyGTDQBVAwACAAkKCyGTDQBVAwAAAA==.Aeth:BAAANQAECgYIDAABNQAECggIGwADALcjAA==.Aethér:BAAANQAECgYIDgABNQAFFAYIDwAEAEsWAA==.',
Ag='Aggroout:BAAANQADCgYIBgABNQAECgkJKAADAHYgAA==.',
Ah='Ahsöka:BAAANQADCgIIAgAAAA==.',
Ai='Aimbel:BAAANQADCgQICQAAAA==.',
Al='Alexstrászá:BAAANQAECgcIEgAAAA==.Aloria:BAAANQADCgEIAQAAAA==.Alynas:BAAANQADCgUIBQAAAA==.Alysona:BAAANQADCgUIDQAAAA==.',
Am='Amaarii:BAAANQABCgQJCAAAAA==.Ambeia:BAAANQADCgQJBAAAAA==.Amewow:BAACNQAFFH8RAAIFAAUK1yWOAQAzAgAFAAUK1yWOAQAzAgA1AAQKfzQAAwUACQqVJJsCAIcDAAUACQqVJJsCAIcDAAYAAgpWA05JAFMAAAAA.Amoril:BAAANQAECgcIDgAAAA==.',
An='Anarchy:BAABNQAECn8ZAAIHAAgKpA9IEwDGAQAHAAgKpA9IEwDGAQAAAA==.Andraxi:BAAANQADCgYICwAAAA==.Angewomon:BAAANQADCgIIAgAAAA==.Annòy:BAABNQAECn86AAIIAAkKIh+ZAwAkAwAIAAkKIh+ZAwAkAwAAAA==.Anorakswrath:BAABNQAECn8cAAIJAAkKXQS5DAF0AQAJAAkKXQS5DAF0AQAAAA==.',
Ap='Apophys:BAAANQADCgcIGQAAAA==.Apoptosis:BAAANQABCgYICAAAAA==.',
Ar='Ariees:BAAANQADCgEIAQAAAA==.Ariella:BAAANQADCgQIBAAAAA==.Artfulrodent:BAAANQADCgQIBAAAAA==.Aruneza:BAABNQAECn8YAAMFAAgKdhEYHQB5AQAFAAcKjg0YHQB5AQAGAAYK9Al7LwAfAQAAAA==.',
As='Asherous:BAAANQADCgQICQABNQAECgUIDgAKAAAAAA==.Ashèr:BAAANQAECgUIDgAAAA==.Asunnaa:BAAANQADCgIIAwAAAA==.',
At='Atenchion:BAAANQAECgQIBAAAAA==.Atticuz:BAAANQADCgIIAgAAAA==.',
Au='Aura:BAAANQAECgUIDgAAAA==.Auralion:BAAANQADCgYIBwAAAA==.Autoignition:BAAANQAECgcIEwABNQAECggIEQAKAAAAAA==.',
Ba='Badcompanytt:BAAANQADCgUIAwAAAA==.Bahnkano:BAAANQAECgYIEQAAAA==.Bakeddh:BAAANQADCgYIDAAAAA==.Balwal:BAAANQAECgIIAgAAAA==.Banditz:BAAANQADCgcIDwAAAA==.Bashfury:BAAANQAECgEIAQAAAA==.',
Be='Beefcåkes:BAABNQAECn8YAAILAAYK9QNW9gDqAAALAAYK9QNW9gDqAAAAAA==.Beenah:BAAANQAECgUIDwAAAA==.Beyshunt:BAAANQADCgYICgAAAA==.',
Bl='Bloodrain:BAAANQAECggIBwAAAA==.Blàst:BAAANQAECgEIAQAAAA==.',
Bo='Boltcutter:BAAANQADCgEIAQAAAA==.Bombmagic:BAAANQADCgMIAwAAAA==.Bonesmccoy:BAAANQABCgQIBAAAAA==.Boomie:BAABNQAFFH8FAAIGAAUKqCSsBAAiAgAGAAUKqCSsBAAiAgAAAA==.Boopty:BAAANQAECgIIBAAAAA==.Booptydo:BAAANQADCggIHQAAAA==.Boris:BAAANQAECgIIAgAAAA==.Bowhawk:BAAANQAECgYICQAAAA==.',
Bp='Bpwhunter:BAAANQAECgQICgAAAA==.',
Br='Braiin:BAAANQAECgYICQABNQAFFAYIDwAEAEsWAA==.Brazyn:BAAANQADCggIIwAAAA==.Brevarda:BAAANQAECgYICgAAAA==.Brewcelee:BAABNQAECn8cAAIMAAcKeA0BFwBvAQAMAAcKeA0BFwBvAQAAAA==.',
Bu='Bubblzmgee:BAABNQAECn8qAAINAAgKMB5FAwDCAgANAAgKMB5FAwDCAgAAAA==.Buscemi:BAAANQADCggIDAAAAA==.Bustofez:BAAANQADCgYICwAAAA==.Buttèrs:BAAANQADCgEIAQAAAA==.',
['Bé']='Béach:BAAANQAECgMIAwAAAA==.',
Ca='Capone:BAAANQAECgQIBAAAAA==.Captiva:BAAANQAECgEIAQAAAA==.Caracalous:BAAANQAECgYIDAAAAA==.Carindria:BAAANQADCggIHQAAAA==.Carninn:BAAANQADCgUIBQAAAA==.Castermcfear:BAAANQABCgIIAgAAAA==.Cattiebrie:BAAANQAECgQICwAAAA==.Caylavana:BAABNQAECn8lAAMOAAgKBh4jSgCNAgAOAAgKBh4jSgCNAgAPAAIKaQNOEwA0AAAAAA==.',
Ce='Celaylria:BAABNQAECn8lAAIQAAgKvxU1HwBTAgAQAAgKvxU1HwBTAgAAAA==.Ceyine:BAAANQADCgEIAQAAAA==.',
Ch='Charmeleön:BAAANQADCgYIBgAAAA==.Chronicfury:BAAANQABCgIIAgAAAA==.',
Cl='Cloudedjayd:BAAANQADCgcIDgAAAA==.Cloudedmonk:BAAANQADCgUICQAAAA==.Clugorn:BAABNQAECn8dAAIRAAgK4Ax7GwB9AQARAAgK4Ax7GwB9AQAAAA==.Clydè:BAAANQAECgUIBQAAAA==.',
Co='Codyj:BAAANQADCggIDgAAAA==.Colossus:BAAANQADCggJCwAAAA==.Colourhunt:BAABNQAECn8YAAMQAAkKMxB8PABoAQAOAAcKZw4/nQDIAQAQAAcKCw58PABoAQAAAA==.Condewit:BAAANQADCgUIBQAAAA==.Conoresa:BAAANQADCgMIAwAAAA==.Copedk:BAABNQAECn8fAAISAAgKVx2MIgCfAgASAAgKVx2MIgCfAgAAAA==.Copestabb:BAAANQAECgEIAQABNQAECggIHwASAFcdAA==.Corrode:BAAANQAECgEIAQAAAA==.Cozymav:BAAANQADCgUIBQAAAA==.',
Cp='Cpt:BAAANQADCgEIAQAAAA==.',
Cr='Crinke:BAAANQABCgIIAgAAAA==.Crusadare:BAAANQAECgQIBAAAAA==.',
Cy='Cybeldin:BAABNQAECn8VAAMOAAgK3QUmuACPAQAOAAgK3QUmuACPAQAQAAQK8QLBbAB3AAAAAA==.Cyberdemonxd:BAAANQADCgYIDAABNQAECgcIDAAKAAAAAA==.Cyndyr:BAAANQADCgYIFgAAAA==.',
['Cë']='Cërßerus:BAAANQADCgYIBgAAAA==.',
Da='Daddysparey:BAAANQAECgYIEAAAAA==.Dalarrus:BAAANQAECgYICwABNQAECggIJQAOAAYeAA==.Dalishya:BAAANQADCgQIBAAAAA==.Darek:BAAANQAECgUIEQAAAA==.Darilyns:BAAANQADCgQIBQAAAA==.Darkbiffhunt:BAAANQADCgMIAwAAAA==.Darkrife:BAAANQADCgcIFQAAAA==.Darylinn:BAAANQADCgQJBgAAAA==.Daymann:BAAANQAECgQIBwAAAA==.',
De='Demonrife:BAAANQABCgYIBgABNQADCgcIFQAKAAAAAA==.Dependabull:BAAANQABCggICQABNQAECgQICQAKAAAAAA==.Dernis:BAAANQAECgIIAgABNQAECgkJKAALAEcfAA==.Derplock:BAAANQADCgcIEAAAAA==.Deshaman:BAAANQADCgMIAwABNQAFFAUIEAAOANsQAA==.Devilbeast:BAAANQAECgQIDQAAAA==.Dew:BAAANQABCgQIAwAAAA==.',
Dh='Dhargo:BAAANQAECgUICgABNQAECgQICQAKAAAAAA==.',
Di='Diablosauz:BAAANQADCgQIBAAAAA==.Diaous:BAAANQADCgcIEQAAAA==.Disasterina:BAAANQADCgcIBwABNQAECgkJKgATADkcAA==.Disgruntled:BAAANQAECgcIEQAAAA==.',
Do='Docbrown:BAAANQADCgEIAQAAAA==.Dontormentaa:BAABNQAECn8XAAMLAAkK4A8hdQAyAgALAAkKTw8hdQAyAgAUAAEK/BngLABNAAAAAA==.Dontormentaj:BAABNQAECn8iAAQVAAgKXxehFwA7AQAJAAgK1xb3lgBSAgAVAAQKHB2hFwA7AQAWAAMKmRRjBwDCAAABNQAECgkJFwALAOAPAA==.Doomzday:BAAANQADCgYIDQAAAA==.',
Dr='Dracthra:BAABNQAECn8YAAIXAAYK0w0DEgAQAQAXAAYK0w0DEgAQAQAAAA==.Dragonbrew:BAAANQADCggICAAAAA==.Dragonfang:BAAANQAECgYICwAAAA==.Drakk:BAAANQADCgUIBQABNQAECgEIAQAKAAAAAA==.Dreamhammer:BAAANQABCgcICwAAAA==.Dreamlesnite:BAAANQABCggIEQAAAA==.Dreidelman:BAAANQAECgIIAgAAAA==.Druvisept:BAAANQADCgcIBwAAAA==.',
Du='Dugdimadome:BAAANQAECgMIAwAAAA==.',
Dy='Dylora:BAAANQAECgcIEwAAAA==.',
Ea='Ealdoras:BAAANQADCggIDgAAAA==.',
Eg='Egg:BAABNQAECn8kAAMYAAkKXSJaCQB9AwAYAAkKXSJaCQB9AwAZAAEKqAzcvAEnAAABNQAFFAcIGgACAMETAA==.',
El='Elassha:BAAANQADCggICwAAAA==.Elatio:BAAANQAECgUIEwAAAA==.Elfairea:BAAANQADCgEIAQAAAA==.Elmortal:BAAANQAECgYIDAAAAA==.Elystaria:BAAANQAECgUIDwAAAA==.',
Em='Emokins:BAEBNQAECn8ZAAIaAAgK0iGRJgDnAgAaAAgK0iGRJgDnAgAAAA==.',
En='Enyos:BAAANQADCgcIDAAAAA==.',
Ep='Epicnakedman:BAAANQAECggICAABNQAECggIKwAYAGAZAA==.',
Er='Eronoljr:BAAANQADCgEIAQAAAA==.Erubus:BAABNQAECn8vAAQMAAkKviIHAwBqAwAMAAkKviIHAwBqAwAbAAQK/hVqPQAlAQAcAAEK6QgHTwApAAAAAA==.Erubuss:BAAANQAECgYICAAAAA==.Eryss:BAAANQAECgUIDwAAAA==.',
Ex='Excalibúr:BAAANQADCgcIBwAAAA==.',
Fa='Faithfulone:BAAANQAECgUIDwAAAA==.Farfidnoogan:BAAANQABCgQIBAAAAA==.Fatercul:BAAANQADCgEIAQAAAA==.',
Fd='Fdk:BAAANQAECgcIDAAAAA==.',
Fe='Fellariene:BAAANQADCggICwAAAA==.',
Fi='Fistenlick:BAAANQADCgMIAwABNQADCgYICwAKAAAAAA==.',
Fo='Forilla:BAAANQAECgQIBQAAAA==.Fortissimo:BAAANQADCgYICwAAAA==.',
Fr='Freim:BAAANQAECgcIBgAAAA==.',
['Fà']='Fàmous:BAAANQAECgYICQAAAA==.',
Ga='Galabris:BAABNQAECn8ZAAISAAgK/htWKQB1AgASAAgK/htWKQB1AgAAAA==.Gasilbench:BAAANQAECgEIAQAAAA==.Gazzik:BAAANQAECgMIAwAAAA==.',
Ge='Gera:BAAANQAECgEIAQAAAA==.',
Gh='Ghostboydk:BAAANQADCgYIBgABNQAECgUICwAKAAAAAA==.Ghoulmania:BAAANQAECggIAgAAAA==.',
Gi='Gimligrimes:BAAANQADCgYIBgAAAA==.Gington:BAAANQAECgQIBgAAAA==.Gitchusum:BAAANQAECgYIBgAAAA==.',
Gl='Glaivenez:BAAANQAECggIBgAAAA==.Gleenna:BAAANQAECgYIBwAAAA==.Glorify:BAAANQAECgEIAQABNQAECggIGwASAPMcAA==.',
Go='Goose:BAABNQAECn8mAAMCAAgKyiK1FQAiAwACAAgKyiK1FQAiAwANAAEK3BdFJABGAAAAAA==.Gormladin:BAAANQADCgYIFwAAAA==.Gormstorm:BAAANQAECgUIDQAAAA==.',
Gr='Greenbahamut:BAAANQADCgEIAQAAAA==.Grimsreaper:BAAANQADCgQIBAAAAA==.Grouchy:BAAANQADCgQIBgABNQAECgcIDAAKAAAAAA==.',
Gw='Gwynythe:BAAANQADCgEJAQAAAA==.',
Ha='Hadriac:BAAANQADCgQJBAAAAA==.Hailes:BAAANQABCgIIAQAAAA==.Halfang:BAAANQADCggIJwAAAA==.Hanta:BAAANQAFFAEIAQAAAA==.Haplò:BAAANQAECgEIAQAAAA==.Hastebuff:BAAANQAECgYICQAAAA==.',
He='Hentaime:BAAANQABCgMIAwAAAA==.',
Hi='Hitpoints:BAAANQADCgYIDAABNQAECgYIFwAdAA0NAA==.',
Ho='Holispirit:BAAANQABCgMIAwAAAA==.Holyfrog:BAAANQAECgUICgAAAA==.Holyhannah:BAAANQADCgcIBwAAAA==.Holyhope:BAABNQAECn8rAAIYAAgKYBkoPwBlAgAYAAgKYBkoPwBlAgAAAA==.Holylightz:BAAANQAECgMIAwAAAA==.Holymana:BAABNQAECn8dAAMZAAgKaxyPWwCBAgAZAAgKaxyPWwCBAgADAAIKvwdWZABLAAAAAA==.Holymilkers:BAAANQADCggIBQABNQAECggIJwAeABoMAA==.Honeybunns:BAAANQADCgUIBQAAAA==.Hosstx:BAAANQADCgEIAQAAAA==.Hotandready:BAABNQAECn8ZAAIfAAcKmQrVLAAsAQAfAAcKmQrVLAAsAQAAAA==.',
Hu='Huffingpaint:BAAANQADCgYIDgABNQAECgQIBQAKAAAAAA==.Hukhokhan:BAAANQADCggIDwAAAA==.Hutzil:BAABNQAECn8fAAQgAAkKvRUaCAAPAgABAAgK9hVaaQAdAgAgAAcK0RQaCAAPAgAhAAIKfQ9cVwB4AAAAAA==.Hutzilla:BAAANQABCgYICAAAAA==.',
Ia='Iakopa:BAABNQAECn8tAAMaAAkKsxwbKQDaAgAaAAgKeB4bKQDaAgAiAAUKNgefvQDqAAAAAA==.',
Il='Illidianna:BAABNQAECn8gAAMTAAgKqh5iGwB5AgATAAgKDx5iGwB5AgAjAAcKSxxeNgD4AQAAAA==.',
Im='Imfiredup:BAAANQAECggIBQAAAA==.Imitlol:BAABNQAECn8YAAIZAAcKbyRrXwB3AgAZAAcKbyRrXwB3AgAAAA==.',
In='Inception:BAAANQADCgYICwAAAA==.Ingress:BAAANQADCgYJBgAAAA==.',
Is='Ishu:BAAANQADCgIIAwAAAA==.',
It='Itchynyple:BAAANQADCgYIEgAAAA==.Ithowen:BAAANQABCgYIBgAAAA==.',
Ja='Jacques:BAAANQADCggIHAAAAA==.Jaetherion:BAABNQAECn8ZAAMZAAcKtSODTwCjAgAZAAcKtSODTwCjAgADAAEKEgnecAAtAAAAAA==.Jakes:BAAANQADCgYJDAAAAA==.Jayhawk:BAAANQAECgEIAgAAAA==.',
Ji='Jimothy:BAAANQADCgcIEwABNQAFFAYIDwAaAL0eAA==.Jinx:BAAANQAECgIIAgAAAA==.',
Jo='Johaliz:BAAANQADCgEIAQAAAA==.Johnnypopoff:BAAANQADCgYIBgAAAA==.Jojohunts:BAAANQAECgEIAQAAAA==.Jonesy:BAAANQADCgIIAgABNQAECggIPAAOAIQZAA==.',
Ju='Junyubych:BAAANQADCgYIGAABNQAECgUIDQAKAAAAAA==.',
['Jà']='Jàccuse:BAAANQADCgUIDAABNQAECgYIGAAXANMNAA==.Jàrnsaxa:BAAANQADCggIJgAAAA==.',
['Jò']='Jòhnnypopo:BAABNQAECn8eAAIZAAgK9xUTdwA7AgAZAAgK9xUTdwA7AgAAAA==.',
Ka='Kaeladra:BAAANQABCgQIBgABNQAECgEIAwAKAAAAAA==.Kagé:BAAANQADCgEIAQAAAA==.Kaisra:BAAANQAECgUICAAAAA==.Kasumeli:BAAANQAECgYIDAAAAA==.Kathelas:BAAANQADCgYIBgAAAA==.Kayd:BAAANQADCggIGwAAAA==.Kayhan:BAAANQADCgQICgAAAA==.Kaylaiis:BAAANQADCggICAAAAA==.Kayos:BAAANQADCgYJFgAAAA==.Kazoo:BAAANQADCgMIAwABNQAECgIIAgAKAAAAAA==.Kazurend:BAACNQAFFH8QAAMdAAYKWRpsBQDbAQAdAAUKbh9sBQDbAQACAAIKSgpYJQCiAAA1AAQKfyQAAx0ACQoFIm8MACADAB0ACQoFIm8MACADAAIAAgrwEuPaAI8AAAAA.',
Ke='Keish:BAAANQADCggICAAAAA==.Keleira:BAAANQADCgYIBgABNQAECgUICgAKAAAAAA==.Keyaielenst:BAAANQADCgYICwAAAA==.',
Kh='Khirina:BAABNQAECn8YAAMbAAgKKQx+NABsAQAbAAgKKQx+NABsAQAcAAMKwAjiPgB5AAAAAA==.Khristina:BAABNQAECn8YAAIYAAYKEh5+WgAGAgAYAAYKEh5+WgAGAgAAAA==.Khrogh:BAAANQAECgEIAwAAAA==.',
Ki='Kidiann:BAAANQAECgYICgAAAA==.Kippo:BAEANQAECgcICAAAAA==.Kirar:BAAANQADCgQIBAAAAA==.Kisarrah:BAAANQABCgMIAwAAAA==.',
Kn='Knarn:BAABNQAECn8eAAIOAAgKOyHpMwDNAgAOAAgKOyHpMwDNAgAAAA==.',
Ko='Koralie:BAACNQAFFH8UAAIOAAYKXR1gBAAQAgAOAAYKXR1gBAAQAgA1AAQKfyYAAg4ACQpvJToQAGIDAA4ACQpvJToQAGIDAAAA.Korheo:BAAANQADCgQIBwAAAA==.Korrum:BAAANQABCgIIAgAAAA==.',
Kr='Krillaxx:BAAANQAECgQIBAAAAA==.',
Kt='Ktullanux:BAAANQAECgIIAgABNQAECgkJKwAkAE0iAA==.',
Ky='Kyliekat:BAAANQAECgUIEgAAAA==.',
La='Lanceelot:BAAANQADCggIFAAAAA==.Lanel:BAAANQAECgUJCgAAAA==.Lathelous:BAABNQAECn8eAAIDAAgK4SEhDQDHAgADAAgK4SEhDQDHAgAAAA==.Laulten:BAAANQABCgQIBAAAAA==.',
Le='Leintheir:BAAANQAECgYICAAAAA==.',
Li='Lideina:BAAANQADCgUIBwAAAA==.Lieahi:BAAANQAECgIIAQAAAA==.Liebesleid:BAAANQADCgYICwABNQAECgQIBQAKAAAAAA==.Lightt:BAABNQAECn85AAICAAkK0RghKwC6AgACAAkK0RghKwC6AgAAAA==.Liightt:BAABNQAECn8jAAICAAgKfRY2RgBRAgACAAgKfRY2RgBRAgAAAA==.Lilcozz:BAAANQADCgYIFgAAAA==.Lilpyroblast:BAABNQAECn8aAAIJAAkKQhbfbACkAgAJAAkKQhbfbACkAgAAAA==.Liriope:BAAANQADCgYIDwAAAA==.Lizbethstar:BAAANQADCggIDAAAAA==.',
Ll='Llaerwyn:BAAANQADCgUJBwAAAA==.Llars:BAABNQAECn8eAAIiAAgKxxGgbADCAQAiAAgKxxGgbADCAQAAAA==.',
Lo='Loryanna:BAAANQADCgYIHgAAAA==.Louie:BAAANQAECgIIAgAAAA==.Lovehandless:BAAANQADCgIIAgAAAA==.',
Lu='Lumenne:BAAANQADCgUIBwAAAA==.Luxore:BAABNQAECn8cAAIDAAkKohBEHgD0AQADAAkKohBEHgD0AQABNQAECgkJLQAaALMcAA==.',
Ly='Lyandrea:BAAANQADCggIIwAAAA==.Lyfebane:BAAANQADCgUJBQAAAA==.Lynaomira:BAAANQADCgMIAwAAAA==.',
['Lõ']='Lõrs:BAAANQADCgMIBQAAAA==.',
['Lø']='Lørs:BAAANQAECgUIEAAAAA==.',
Ma='Main:BAABNQAECn8sAAIZAAkKcAtnqQDIAQAZAAkKcAtnqQDIAQAAAA==.Majrmiståke:BAACNQAFFH8OAAMVAAUKPgTPBQCxAAAJAAUK0AMMJgBOAQAVAAMKMQLPBQCxAAA1AAQKfyAAAxUACQqnHHAGAJgCABUACAqlGnAGAJgCAAkACQoGFd+LAGcCAAE1AAQKCQksABgAThQA.Malakir:BAAANQADCgYIDQAAAA==.Malaxxus:BAAANQADCgEIAQAAAA==.Malendorei:BAAANQAECgQICgAAAA==.Malicemech:BAAANQADCgcIIwAAAA==.Maliceone:BAAANQADCggIJAAAAA==.Malicepaly:BAAANQADCgcIEwAAAA==.Mallucavian:BAAANQAECgUIDAAAAA==.Mamadp:BAAANQAECgQIEAAAAA==.Manaholy:BAAANQADCggICwAAAA==.Manek:BAABNQAECn88AAIOAAgKhBlYUAB8AgAOAAgKhBlYUAB8AgAAAA==.Marraxa:BAAANQAECgYIDwAAAA==.Maräjade:BAAANQABCgYJBgAAAA==.Max:BAABNQAECn8aAAMBAAkK0hWhagAZAgABAAgKmBOhagAZAgAhAAMKlRM+QQC9AAAAAA==.',
Me='Melevil:BAAANQAECgcIDwAAAA==.Melinoe:BAAANQADCgIIAgAAAA==.Merlin:BAAANQAECgQIBAAAAA==.Merlise:BAAANQADCgcICgAAAA==.Metalgreymon:BAAANQADCgIIAgAAAA==.',
Mi='Milenad:BAAANQAECgYIDAAAAA==.Milho:BAAANQADCgYIBgABNQAFFAIICAAjAEYiAA==.Milkmeholy:BAAANQADCgcICQAAAA==.Minikey:BAAANQADCgMIAwAAAA==.Mishosuki:BAAANQAECgUIDQAAAA==.Misscleo:BAABNQAECn8eAAIJAAgK5g/d0ADiAQAJAAgK5g/d0ADiAQAAAA==.Mistalar:BAAANQAECgUIBgAAAA==.',
Mn='Mnesarte:BAAANQADCgUIBQAAAA==.',
Mo='Moltres:BAEANQAECggIBQAAAA==.Mongoro:BAAANQADCgEIAQAAAA==.Moonkist:BAAANQAECgUIDwAAAA==.Moose:BAABNQAECn8aAAMlAAkK1hwWGQD1AgAlAAkK1hwWGQD1AgASAAEKAACZwABDAAAAAA==.Mordrandian:BAAANQADCgYIFgAAAA==.Morroe:BAAANQADCgYIFwAAAA==.',
Mu='Muffintop:BAAANQADCgcICwAAAA==.',
Na='Nadless:BAAANQAECgMIAwAAAA==.Naeliria:BAAANQADCggICAAAAA==.Namuss:BAAANQADCgIIAwAAAA==.Navariis:BAAANQADCgQIDQAAAA==.',
Ne='Necropanzer:BAAANQAECggIEQAAAA==.Nelrehim:BAAANQAECgUIBgAAAA==.',
Ni='Niall:BAAANQAECgEIAQABNQAECggIJQAOAAYeAA==.Niandilan:BAAANQADCgYICgAAAA==.Niixxi:BAAANQADCgEIAQAAAA==.',
Nm='Nmbrs:BAAANQADCgYIDwABNQAECgcIDAAKAAAAAA==.',
No='Noirah:BAAANQADCgcIBwAAAA==.Noirheffer:BAABNQAECn8oAAMDAAkKdiB6EACVAgADAAkKdiB6EACVAgAZAAUK/xV55QBKAQAAAA==.Nokua:BAAANQAECgQIDQABNQAECgUIDQAKAAAAAA==.Noodles:BAABNQAECn8dAAImAAgKKwslUACZAQAmAAgKKwslUACZAQAAAA==.',
Nu='Nulannatoo:BAAANQAECgUIBwAAAA==.',
Ny='Nyank:BAAANQAECgMIAgABNQAECgcIDAAKAAAAAA==.Nyleaf:BAAANQADCgUIBwAAAA==.Nyogen:BAAANQAECggJBgAAAA==.Nyxaraa:BAAANQADCgYIEAAAAA==.',
Oc='Octomore:BAABNQAECn8eAAIJAAgK6hJcxAD6AQAJAAgK6hJcxAD6AQAAAA==.',
Od='Odysseus:BAABNQAECn8gAAIQAAkKvQ9RLADlAQAQAAkKvQ9RLADlAQAAAA==.',
Ol='Olgann:BAAANQAECgUIBgAAAA==.Olguita:BAAANQAECgUIDwAAAA==.',
Om='Omez:BAAANQAECgYICgABNQAECggICwAKAAAAAA==.Omgowned:BAAANQAECgIIAgABNQAECgcIGAABAMoVAA==.',
On='Onehothealer:BAAANQADCgYIBwAAAA==.',
Oo='Oorua:BAAANQADCggIGQAAAA==.',
Op='Opheliastar:BAABNQAECn8pAAIdAAkKIRbnHgBDAgAdAAkKIRbnHgBDAgAAAA==.',
Or='Ordovis:BAAANQAECgUIDAAAAA==.Orlucicia:BAAANQAECgIIAgAAAA==.Orobas:BAAANQAECggIAgAAAA==.',
Ow='Owltoidz:BAAANQABCgUIBAAAAA==.',
Pa='Pace:BAAANQABCgYICgAAAA==.Pad:BAAANQAECgUIDwAAAA==.Paladerp:BAAANQAECgYICQAAAA==.Palanym:BAABNQAECn8hAAIYAAgKqxV8VwAQAgAYAAgKqxV8VwAQAgAAAA==.Palidyne:BAAANQAECgEIAQAAAA==.Pallyown:BAAANQAECgcIDAAAAA==.Papamidnite:BAAANQADCgMIAwAAAA==.Papichulo:BAAANQADCgcIDQAAAA==.Parox:BAAANQADCgYIBwAAAA==.',
Ph='Phelement:BAABNQAECn8bAAIeAAkKUiG9AwBdAwAeAAkKUiG9AwBdAwAAAA==.Phett:BAABNQAECn8nAAMUAAgKvyJ5BADvAgAUAAcKPSR5BADvAgALAAMK1h0j9QDtAAAAAA==.Phonk:BAAANQAECgEIAQABNQAECgkJGwAeAFIhAA==.Phædrea:BAAANQADCggICAAAAA==.',
Pi='Picklës:BAAANQADCgUIBQABNQAECggIJgACAMoiAA==.Piffi:BAAANQAECgEIAQAAAA==.Pimmscup:BAAANQADCgYIFgAAAA==.',
Pr='Praedthy:BAAANQAFFAIIAgAAAA==.',
Qo='Qohelet:BAAANQAECgQIBQAAAA==.',
Ra='Raatus:BAAANQAECgIIAgABNQAECggIHAASACQiAA==.Raenya:BAAANQAECgIIAgAAAA==.Raikouu:BAAANQAECgYIEgAAAA==.Rainydaze:BAAANQAECgIIAgAAAA==.Ramani:BAAANQADCgEIAQAAAA==.Ramasses:BAAANQADCgYICgAAAA==.Ramcharger:BAAANQAECgEIAQABNQAECggIJQAOAAYeAA==.Ramoreo:BAAANQAECgUIDgABNQAECgcINAAjANoLAA==.Rashun:BAABNQAECn8cAAIbAAgKshmZIAAkAgAbAAgKshmZIAAkAgAAAA==.Raviolee:BAAANQAECgEIAQABNQAECgcIGAABAMoVAA==.',
Re='Reanatilax:BAAANQABCgMJBQABNQAECgYIGgACAKUeAA==.Regnier:BAAANQADCgYICgAAAA==.Relaeh:BAAANQADCgcJDQAAAA==.Resusitate:BAAANQADCgYJBgAAAA==.Rexxy:BAAANQADCgcICwAAAA==.',
Rh='Rhod:BAAANQADCgcICwABNQAECggIDgAKAAAAAA==.',
Ri='Rikashae:BAAANQADCgYJBgAAAA==.Rissa:BAAANQADCgEIAQAAAA==.Risuku:BAAANQADCgEIAQAAAA==.',
Ro='Roleon:BAAANQADCgYICwAAAA==.Rollforpi:BAAANQAECgEIAQABNQAFFAYIDwAEAEsWAA==.Ropebunnyana:BAAANQAECgIJAwABNQAECgkJHgACAAshAA==.',
Ru='Ruki:BAAANQAECgQIBQAAAA==.Rumshwizzle:BAAANQADCgQJBAAAAA==.',
Sa='Saltydk:BAABNQAECn8gAAIlAAkKhyBOJACuAgAlAAkKhyBOJACuAgAAAA==.Samiracy:BAAANQAECgcIEgAAAA==.Sannrin:BAAANQADCgMIAwAAAA==.Sataro:BAAANQABCggICgAAAA==.',
Sc='Scappe:BAABNQAECn8cAAISAAgKJCKCHADJAgASAAgKJCKCHADJAgAAAA==.Schniel:BAAANQAECgUICQAAAA==.',
Se='Seefoof:BAAANQADCgIIAgAAAA==.Seitaer:BAAANQADCgEJAQAAAA==.Senbatorii:BAABNQAECn8YAAQEAAYKOBzMPwAiAQAEAAQKYhjMPwAiAQAmAAUKXg5ddAD1AAAHAAIKTAqANQBlAAAAAA==.Sentrosi:BAAANQAECgEIAQAAAA==.Sethrow:BAABNQAECn8YAAMBAAcKyhWYngCUAQABAAYKRxWYngCUAQAhAAEK1RfwbQBCAAAAAA==.Severa:BAABNQAECn8YAAIZAAYKlRmjsAC4AQAZAAYKlRmjsAC4AQAAAA==.',
Sh='Shadoh:BAAANQAECgIIAgAAAA==.Shamazing:BAAANQADCgEIAQAAAA==.Shamwowsale:BAAANQADCgYIDAAAAA==.Shamwowza:BAABNQAECn8oAAIiAAkKBxDMWAADAgAiAAkKBxDMWAADAgAAAA==.Shantifa:BAAANQADCgYICwAAAA==.Shengari:BAAANQADCgIIAgABNQADCgQIBAAKAAAAAA==.Shoshanaa:BAAANQADCgYIEQAAAA==.Shotcallà:BAAANQADCgYIBwABNQADCggICAAKAAAAAA==.Shuna:BAAANQADCgYICQAAAA==.Shyly:BAAANQAECgIIAgAAAA==.',
Si='Siley:BAABNQAECn84AAIlAAkKfRA2TADhAQAlAAkKfRA2TADhAQAAAA==.',
Sn='Sneakysneak:BAABNQAECn8ZAAInAAgKvRQLBwBOAgAnAAgKvRQLBwBOAgAAAA==.Snüff:BAAANQADCgMIAwAAAA==.',
So='Somavan:BAAANQADCgMIAwABNQAECggIJQAOAAYeAA==.Somepriest:BAABNQAECn8aAAIdAAgKcB/9EwDDAgAdAAgKcB/9EwDDAgAAAA==.Sotteria:BAAANQABCgQIBAAAAA==.',
Sp='Spiarmf:BAAANQADCgMIAwAAAA==.Spicyness:BAAANQADCgIIAgAAAA==.Sprockett:BAAANQADCggICAAAAA==.Spycmchaggis:BAAANQAECgMIBAAAAA==.Spëcter:BAAANQAECgQIBwABNQAECggIHgAJAOoSAA==.',
Sq='Squishypoo:BAAANQAECgIIAgAAAA==.',
St='Staticpower:BAAANQAECggIAQAAAA==.Stiffkitten:BAAANQADCgEJAQAAAA==.Stoked:BAAANQADCgUIBQAAAA==.Sturba:BAAANQABCgIIAgAAAA==.',
Su='Sugrace:BAAANQADCgQIBAAAAA==.Sunaerosinda:BAAANQADCgYIBgAAAA==.Sunow:BAAANQADCgYIFwAAAA==.Superdemonzz:BAAANQAECgcIDAABNQAECgkJLAAYAE4UAA==.Superpallyz:BAABNQAECn8sAAQYAAkKThSKSgA8AgAYAAkKThSKSgA8AgAZAAEKAACymwE2AAADAAEKAACKewAgAAAAAA==.Superspidey:BAAANQADCgIIAgAAAA==.',
Sw='Swipeleft:BAABNQAECn8yAAImAAgK9BfCMQBSAgAmAAgK9BfCMQBSAgAAAA==.',
Sy='Sylora:BAAANQADCgIIAgAAAA==.',
Ta='Tabarnak:BAABNQAECn8hAAIeAAkKHR7NAwBcAwAeAAkKHR7NAwBcAwABNQAFFAIIBQAbAPUaAA==.Taiynn:BAAANQADCggIFwAAAA==.Tallon:BAAANQAFFAIIAwAAAA==.Tarogen:BAAANQAECgUIDAAAAA==.Taszherazade:BAAANQADCgEJAQAAAA==.',
Te='Teknique:BAAANQAECgIIAgAAAA==.Tendroni:BAABNQAECn8YAAIjAAkKoQ0xNgD5AQAjAAkKoQ0xNgD5AQAAAA==.Tervor:BAAANQAECgIIAgAAAA==.Tessadin:BAAANQADCgEJAQAAAA==.',
Th='Thanamoros:BAABNQAECn8mAAIIAAkK/hEYCwAeAgAIAAkK/hEYCwAeAgABNQAECgkJLQAaALMcAA==.Theredwake:BAAANQAECgYICgAAAA==.Theroach:BAAANQAECgIIAwAAAA==.Thgiewerom:BAAANQABCgYIBwAAAA==.Throfin:BAAANQAECgYIBgAAAA==.Thwaxi:BAAANQADCgQJCAAAAA==.',
Ti='Timeismoney:BAAANQADCggIHwAAAA==.Tinydeath:BAAANQAECgMIAwAAAA==.Tiognaska:BAAANQAECgQICAAAAA==.Tirdain:BAAANQADCgEIAQAAAA==.',
To='Toeren:BAACNQAFFH8QAAIOAAUK2xCMCwCSAQAOAAUK2xCMCwCSAQA1AAQKfzEAAg4ACQpBImYVAEUDAA4ACQpBImYVAEUDAAAA.Tokå:BAAANQADCgIIAgAAAA==.Torage:BAAANQAECgEJAQAAAA==.Tormentah:BAAANQADCgIIAgABNQAECgkJFwALAOAPAA==.Torosentado:BAAANQAECgQICAAAAA==.',
Tr='Trenity:BAAANQAECgMIBAAAAA==.Triplecanopy:BAAANQADCgUICwAAAA==.Trumu:BAAANQAECgEIAQAAAA==.Trïsh:BAAANQAECgIIAgABNQAECgcIKgADAC0RAA==.',
Ty='Tyinorin:BAAANQADCgYIFgAAAA==.',
['Tä']='Täryn:BAAANQADCgEIAQAAAA==.',
Ub='Ubee:BAAANQAECgYIEgAAAA==.',
Ud='Udderjustice:BAABNQAECn8gAAIDAAcKKA4lMQBTAQADAAcKKA4lMQBTAQAAAA==.',
Ug='Uglyelf:BAAANQAECgYIEAAAAA==.',
Ul='Ultimakitty:BAAANQAECgIIAgAAAA==.',
Un='Uncertainty:BAAANQADCgUIBQABNQAECgQIBQAKAAAAAA==.Unchanged:BAAANQAECgIIAgAAAA==.',
Va='Vaeldrin:BAAANQADCgUIBQAAAA==.Vanhellsings:BAAANQAECgEIAQAAAA==.Vantrix:BAABNQAECn85AAMmAAkK5xl8HQDcAgAmAAkK5xl8HQDcAgAEAAYKohCwNwBaAQABNQAECgkJLQAaALMcAA==.Varabo:BAAANQAECgUIBwAAAA==.Varolina:BAAANQADCggIJQAAAA==.',
Ve='Velmara:BAAANQABCgMIAwAAAA==.Velthala:BAAANQAECgcIEAAAAA==.Velyra:BAAANQAECgUICgAAAA==.',
Vi='Vitner:BAAANQADCgMIBAABNQAECgkJGAABAK0XAA==.Vivieneaux:BAAANQABCgUICAAAAA==.Vixsen:BAAANQABCgcIDQAAAA==.',
Vl='Vladdawngard:BAAANQAECggICAAAAA==.',
Vo='Voidcorpse:BAAANQADCgEIAQAAAA==.Voidmama:BAAANQADCgYIBgAAAA==.Voidryn:BAAANQABCgcIEQAAAA==.Voidshifter:BAAANQADCgUIBQAAAA==.Vosaleana:BAAANQAECgQICQAAAA==.',
Vr='Vraak:BAACNQAFFH8PAAIEAAYKSxYmBADpAQAEAAYKSxYmBADpAQA1AAQKfyIAAwQACQo3JAAGAGEDAAQACQo3JAAGAGEDACYAAgrrHPaFALYAAAAA.',
Vu='Vulcus:BAAANQAECgMIBAABNQAFFAYIDwAEAEsWAA==.',
Vy='Vyndarien:BAAANQABCgcICQAAAA==.',
Wa='Wa:BAAANQAECgUIDwAAAA==.Walimagus:BAAANQAECgIIAgAAAA==.Wayofthemist:BAAANQABCgIIAgAAAA==.',
Wc='Wcreator:BAAANQAECgIIAgAAAA==.',
Wh='Wheeljack:BAAANQAECgcIDQABNQAFFAEIAQAKAAAAAA==.',
Wi='Widowcancer:BAAANQADCgIJAgAAAA==.Will:BAACNQAFFH8GAAIZAAMKWR8fFAAPAQAZAAMKWR8fFAAPAQA1AAQKfysAAhkACQryJXYJAK8DABkACQryJXYJAK8DAAAA.',
Wo='Womdalie:BAAANQADCggIGAAAAA==.',
Wy='Wyckedpally:BAAANQAECgUIDQAAAA==.',
Xa='Xanthös:BAAANQAFFAIIAgABNQAFFAYIDwAEAEsWAA==.',
Xe='Xemnastrasza:BAABNQAECn8nAAMXAAkKJBVbCAAQAgAXAAgKHxNbCAAQAgAFAAgK4BUEFAALAgABNQAECgkJLQAaALMcAA==.Xenonne:BAAANQAECgMIBAABNQAFFAMIBQAYAMMOAA==.',
Xo='Xolither:BAABNQAECn8aAAICAAYKpR4fXgADAgACAAYKpR4fXgADAgAAAA==.',
Yo='Yorgo:BAAANQADCggICAAAAA==.Yourwifesbf:BAABNQAECn8kAAIRAAkKkxf3CwB1AgARAAkKkxf3CwB1AgAAAA==.Yourwivesbf:BAAANQADCggICQAAAA==.',
Yu='Yuura:BAAANQAECgMIBAAAAA==.',
Za='Zachdemon:BAABNQAECn8lAAIIAAcKjRVqDgDPAQAIAAcKjRVqDgDPAQAAAA==.Zazoo:BAAANQABCgEIAQAAAA==.',
Ze='Zenyátta:BAAANQAECgUIBwAAAA==.Zephymoo:BAABNQAECn84AAMHAAkKKhn1CwBnAgAHAAgKuBj1CwBnAgAmAAQKhhY4bgANAQAAAA==.Zeretha:BAAANQABCgIIAgAAAA==.Zershadowi:BAAANQAECgEIAQAAAA==.Zeyana:BAAANQAECgcIEgABNQAECgkJKwAOAAcfAA==.',
Zh='Zhengshi:BAAANQAECgcIEwAAAA==.',
Zi='Zinsatra:BAAANQADCgEIAQAAAA==.',
Zk='Zkarlyse:BAAANQAECgcIDQAAAA==.',
Zo='Zoose:BAABNQAECn8ZAAQLAAgKXRduiAADAgALAAgKXhRuiAADAgARAAQK6RlgKQDrAAAUAAEKhg7ZMgA0AAAAAA==.Zosahe:BAAANQAECgcIEwAAAA==.Zoser:BAAANQAECgYIEwAAAA==.',
Zs='Zsófia:BAAANQADCgcIBwAAAA==.',
Zu='Zuckuss:BAAANQADCgYIFgAAAA==.',
Zy='Zymri:BAAANQADCgUICQABNQAECgUIDwAKAAAAAA==.',
['Æl']='Ælthan:BAAANQAECgEIAQAAAA==.',
['Ér']='Érubus:BAAANQAECgMIBAAAAA==.',
['Ôr']='Ôrdra:BAAANQAECggICAAAAA==.',
['Öl']='Ölivê:BAABNQAECn8UAAISAAcKDQqIbwA0AQASAAcKDQqIbwA0AQAAAA==.',
['ßu']='ßugs:BAABNQAECn8ZAAIOAAcK6hrXhwD3AQAOAAcK6hrXhwD3AQAAAA==.',
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
