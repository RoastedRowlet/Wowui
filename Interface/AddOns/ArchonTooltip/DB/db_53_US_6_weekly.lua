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

local lookup = {'Priest-Holy','Unknown-Unknown','Druid-Restoration','Paladin-Protection','Evoker-Devastation','Evoker-Preservation','Monk-Brewmaster','Priest-Discipline','Hunter-BeastMastery','Hunter-Marksmanship','Warrior-Protection','DeathKnight-Blood','DemonHunter-Devourer','Mage-Frost','Mage-Arcane','Mage-Fire','Paladin-Holy','Paladin-Retribution','Shaman-Elemental','Monk-Windwalker','Shaman-Restoration','DemonHunter-Havoc','Priest-Shadow','DeathKnight-Frost','Warlock-Demonology','Warlock-Destruction','DemonHunter-Vengeance','DeathKnight-Unholy','Druid-Balance','Warrior-Fury','Warrior-Arms','Rogue-Outlaw','Shaman-Enhancement','Evoker-Augmentation','Druid-Feral',}
local provider = {region='US',realm='Alexstrasza',name='US',type='weekly',zone=53,date='2026-10-06',data={Ac='Acbabcaa:BAAANQADCgEIAQAAAA==.Aceon:BAAANQAECgIIBAAAAA==.Aceonarcher:BAAANQAECgQICAAAAA==.',
Ad='Adfectia:BAAANQAECgYIEAAAAA==.',
Ae='Aelianna:BAAANQAECgUIBgAAAA==.Aeryana:BAABNQAECoEWAAIBAAgK5h88IQDOAgABAAgK5h88IQDOAgAAAA==.Aeth:BAAANQAECgYIDAABNQAECgcIEwACAAAAAA==.Aethér:BAAANQAECgQICwABNQAFFAUICgADANgYAA==.',
Ag='Aggroout:BAAANQADCgYIBgABNQAECgkJKAAEAO4eAA==.',
Ah='Ahsöka:BAAANQADCgIIAgAAAA==.',
Ai='Aimbel:BAAANQADCgQICQAAAA==.',
Al='Alexstrászá:BAAANQAECgYIEQAAAA==.Aloria:BAAANQADCgEIAQAAAA==.Alynas:BAAANQADCgUIBQAAAA==.Alysona:BAAANQADCgUIDQAAAA==.',
Am='Amaarii:BAAANQABCgQJCAAAAA==.Ambeia:BAAANQADCgQJBAAAAA==.Amewow:BAACNQAFFIEMAAIFAAUKTSVmAQAoAgAFAAUKTSVmAQAoAgA1AAQKgTEAAwUACQraI0sCAIgDAAUACQraI0sCAIgDAAYAAgpWA5hDAFcAAAAA.Amoril:BAAANQAECgcIDgAAAA==.',
An='Anarchy:BAAANQAECgYIEAAAAA==.Andraxi:BAAANQADCgYICwAAAA==.Angewomon:BAAANQADCgIIAgAAAA==.Anorakswrath:BAAANQAECgcIEQAAAA==.',
Ap='Apophys:BAAANQADCgYIFgAAAA==.Apoptosis:BAAANQABCgYICAAAAA==.',
Ar='Ariees:BAAANQADCgEIAQAAAA==.Artfulrodent:BAAANQADCgQIBAAAAA==.Aruneza:BAABNQAECoEWAAMFAAcKPw2lGgCCAQAFAAcKPw2lGgCCAQAGAAUKPwv1LwD4AAAAAA==.',
As='Asherous:BAAANQADCgQICQABNQAECgQICQACAAAAAA==.Ashèr:BAAANQAECgQICQAAAA==.Asunnaa:BAAANQADCgIIAwAAAA==.',
At='Atenchion:BAAANQAECgQIBAAAAA==.Atticuz:BAAANQADCgIIAgAAAA==.',
Au='Aura:BAAANQAECgUIDgABNQAECgYICwACAAAAAA==.Auralion:BAAANQADCgYIBwAAAA==.Autoignition:BAAANQAECgcIEwAAAA==.',
Ba='Badcompanytt:BAAANQADCgUIAwAAAA==.Bahnkano:BAAANQAECgUICwAAAA==.Bakeddh:BAAANQADCgYJDAAAAA==.Balwal:BAAANQAECgIIAgAAAA==.Banditz:BAAANQADCgcJDwAAAA==.Bashfury:BAAANQAECgEIAQAAAA==.',
Be='Beefcåkes:BAAANQAECgUIEgAAAA==.Beenah:BAAANQAECgMICgAAAA==.Beyshunt:BAAANQADCgYICgAAAA==.',
Bl='Bloodrain:BAAANQAECggIBwAAAA==.Blàst:BAAANQAECgEIAQAAAA==.',
Bo='Boltcutter:BAAANQADCgEJAQAAAA==.Bombmagic:BAAANQADCgMIAwAAAA==.Bonesmccoy:BAAANQABCgQIBAAAAA==.Boomie:BAAANQAECggIBwAAAA==.Boopty:BAAANQAECgIIAwAAAA==.Booptydo:BAAANQADCggIHQAAAA==.Boris:BAAANQAECgIIAgAAAA==.Bowhawk:BAAANQAECgUICQAAAA==.',
Bp='Bpwhunter:BAAANQAECgQICgAAAA==.',
Br='Braiin:BAAANQAECgUIBgABNQAFFAUICgADANgYAA==.Brazyn:BAAANQADCggIIwAAAA==.Brevarda:BAAANQAECgYICgAAAA==.Brewcelee:BAABNQAECoEVAAIHAAYK/gkbGgAdAQAHAAYK/gkbGgAdAQAAAA==.',
Bu='Bubblzmgee:BAABNQAECoEjAAIIAAcKtR/8AwCDAgAIAAcKtR/8AwCDAgAAAA==.Buscemi:BAAANQADCggIDAAAAA==.Bustofez:BAAANQADCgYICwAAAA==.Buttèrs:BAAANQADCgEIAQAAAA==.',
['Bé']='Béach:BAAANQADCgQIBwAAAA==.',
Ca='Capone:BAAANQADCgcICQAAAA==.Captiva:BAAANQAECgEIAQAAAA==.Caracalous:BAAANQAECgYIDAAAAA==.Carindria:BAAANQADCggIFwAAAA==.Carninn:BAAANQADCgUIBQAAAA==.Castermcfear:BAAANQABCgIIAgAAAA==.Cattiebrie:BAAANQAECgMICAAAAA==.Caylavana:BAABNQAECoEjAAIJAAgKTBxPNwCiAgAJAAgKTBxPNwCiAgAAAA==.',
Ce='Celaylria:BAABNQAECoEdAAIKAAgK0hYaHgBEAgAKAAgK0hYaHgBEAgAAAA==.',
Ch='Charmeleön:BAAANQADCgYIBgAAAA==.Chronicfury:BAAANQABCgIIAgAAAA==.',
Cl='Cloudedjayd:BAAANQADCgcIDgAAAA==.Cloudedmonk:BAAANQADCgUICQAAAA==.Clugorn:BAABNQAECoEaAAILAAcKpQ2nGwBTAQALAAcKpQ2nGwBTAQAAAA==.Clydè:BAAANQADCggIFgAAAA==.',
Co='Codyj:BAAANQADCggIDgAAAA==.Colossus:BAAANQADCggJCwAAAA==.Colourhunt:BAABNQAECoEXAAMKAAgK1g3/NQByAQAJAAYKFAxXpACKAQAKAAcKeAz/NQByAQAAAA==.Condewit:BAAANQADCgUIBQAAAA==.Conoresa:BAAANQADCgMIAwAAAA==.Copedk:BAABNQAECoEYAAIMAAcK2R4IKQBeAgAMAAcK2R4IKQBeAgAAAA==.Copestabb:BAAANQAECgEIAQABNQAECgcIGAAMANkeAA==.Corrode:BAAANQAECgEIAQAAAA==.Cozymav:BAAANQADCgUIBQAAAA==.',
Cp='Cpt:BAAANQADCgEIAQAAAA==.',
Cr='Crinke:BAAANQABCgIIAgAAAA==.Crusadare:BAAANQAECgQIBAAAAA==.',
Cy='Cybeldin:BAAANQAECgYIEwAAAA==.Cyberdemonxd:BAAANQADCgYICAABNQAECgcICAACAAAAAA==.Cyndyr:BAAANQADCgYIFgAAAA==.',
['Cë']='Cërßerus:BAAANQADCgYIBgAAAA==.',
Da='Daddysparey:BAAANQAECgUICgAAAA==.Dalarrus:BAAANQAECgYICwABNQAECggIIwAJAEwcAA==.Dalishya:BAAANQADCgQIBAAAAA==.Darek:BAAANQAECgQIDQAAAA==.Darilyns:BAAANQADCgQIBQAAAA==.Darkbiffhunt:BAAANQADCgMIAwAAAA==.Darkrife:BAAANQADCgYIEgAAAA==.Darylinn:BAAANQADCgQJBgAAAA==.Daymann:BAAANQAECgQIBwAAAA==.',
De='Demonrife:BAAANQABCgYIBgABNQADCgYIEgACAAAAAA==.Dependabull:BAAANQABCggICQABNQAECgQICQACAAAAAA==.Dernis:BAAANQAECgIIAgAAAA==.Derplock:BAAANQADCgcIEAAAAA==.Deshaman:BAAANQADCgMIAwABNQAFFAUICwAJAK4RAA==.Devilbeast:BAAANQAECgQIDQAAAA==.Dew:BAAANQABCgQIAwAAAA==.',
Dh='Dhargo:BAAANQAECgUICgABNQAECgQICQACAAAAAA==.',
Di='Diablosauz:BAAANQADCgQIBAAAAA==.Diaous:BAAANQADCgUICgAAAA==.Disasterina:BAAANQADCgcIBwABNQAECgkJJAANAFUbAA==.Disgruntled:BAAANQAECgcIEQAAAA==.',
Do='Docbrown:BAAANQADCgEIAQAAAA==.Dontormentaa:BAAANQAECgYIDAABNQAECggIIgAOAJ4ZAA==.Dontormentaj:BAABNQAECoEiAAQOAAgKnhn0EwBDAQAPAAgKOBlMggBhAgAOAAQKnhz0EwBDAQAQAAMKPRV8BgDFAAAAAA==.Doomzday:BAAANQADCgYIDQAAAA==.',
Dr='Dracthra:BAAANQAECgUIEgAAAA==.Dragonbrew:BAAANQADCggICAAAAA==.Drakk:BAAANQADCgUIBQABNQAECgEIAQACAAAAAA==.Dreamhammer:BAAANQABCgYICAAAAA==.Dreamlesnite:BAAANQABCggIEQAAAA==.Dreidelman:BAAANQAECgIIAgAAAA==.Druvisept:BAAANQADCgcIBwAAAA==.',
Du='Dugdimadome:BAAANQAECgMIAwAAAA==.',
Dy='Dylora:BAAANQAECgYIEgAAAA==.',
Ea='Ealdoras:BAAANQADCggIDgAAAA==.',
Eg='Egg:BAABNQAECoEeAAMRAAkKYx/cCwBbAwARAAkKYx/cCwBbAwASAAEKqAyKjwEnAAABNQAFFAYIGAABAMEUAA==.',
El='Elassha:BAAANQADCggICwAAAA==.Elatio:BAAANQAECgQIDgAAAA==.Elfairea:BAAANQADCgEIAQAAAA==.Elmortal:BAAANQAECgQIBgAAAA==.Elystaria:BAAANQAECgMICgAAAA==.',
Em='Emokins:BAEBNQAECoEXAAITAAcKpiE/LwCbAgATAAcKpiE/LwCbAgAAAA==.',
En='Enyos:BAAANQADCgQIBQAAAA==.',
Ep='Epicnakedman:BAAANQAECggICAABNQAECggIKwARAGAZAA==.',
Er='Eronoljr:BAAANQADCgEIAQAAAA==.Erubus:BAABNQAECoEqAAMHAAkKbCLMAgBjAwAHAAkKbCLMAgBjAwAUAAMKaRjUQQDSAAAAAA==.Erubuss:BAAANQAECgQIBAAAAA==.Eryss:BAAANQAECgMICgAAAA==.',
Ex='Excalibúr:BAAANQADCgcIBwAAAA==.',
Fa='Faithfulone:BAAANQAECgMICgAAAA==.Farfidnoogan:BAAANQABCgQIBAAAAA==.Fatercul:BAAANQADCgEIAQAAAA==.',
Fd='Fdk:BAAANQAECgcIBwAAAA==.',
Fe='Fellariene:BAAANQADCggICwAAAA==.',
Fo='Forilla:BAAANQAECgQIBQAAAA==.Fortissimo:BAAANQADCgYICwAAAA==.',
['Fà']='Fàmous:BAAANQAECgYICQAAAA==.',
Ga='Galabris:BAABNQAECoEXAAIMAAcKgRzMLQBCAgAMAAcKgRzMLQBCAgAAAA==.Gasilbench:BAAANQAECgEIAQAAAA==.Gazzik:BAAANQADCggIEAAAAA==.',
Gh='Ghostboydk:BAAANQADCgYIBgABNQAECgQICAACAAAAAA==.Ghoulmania:BAAANQAECggIAgAAAA==.',
Gi='Gimligrimes:BAAANQADCgYIBgAAAA==.Gington:BAAANQAECgQIBAAAAA==.Gitchusum:BAAANQAECgYIBgAAAA==.',
Gl='Glaivenez:BAAANQAECggIBgAAAA==.Gleenna:BAAANQAECgYIBwAAAA==.Glorify:BAAANQADCggIDwABNQAECgcIEwACAAAAAA==.',
Go='Goose:BAABNQAECoEdAAMBAAcKgCObIADRAgABAAcKgCObIADRAgAIAAEK3Be9IABIAAAAAA==.Gormladin:BAAANQADCgUIEQAAAA==.Gormstorm:BAAANQAECgMICAAAAA==.',
Gr='Greenbahamut:BAAANQADCgEIAQAAAA==.Grimsreaper:BAAANQADCgQIBAAAAA==.Grouchy:BAAANQADCgQIBgABNQAECgcIBwACAAAAAA==.',
Gw='Gwynythe:BAAANQADCgEJAQAAAA==.',
Ha='Hadriac:BAAANQADCgQJBAAAAA==.Hailes:BAAANQABCgIIAQAAAA==.Halfang:BAAANQADCggIIAAAAA==.Hanta:BAAANQAFFAEIAQAAAA==.Haplò:BAAANQAECgEIAQAAAA==.',
He='Hentaime:BAAANQABCgMIAwAAAA==.',
Hi='Hitpoints:BAAANQADCgYIDAABNQAECgUIEQACAAAAAA==.',
Ho='Holispirit:BAAANQABCgMIAwAAAA==.Holyfrog:BAAANQAECgUICgAAAA==.Holyhope:BAABNQAECoErAAIRAAgKYBl8NQBzAgARAAgKYBl8NQBzAgAAAA==.Holylightz:BAAANQAECgMIAwAAAA==.Holymana:BAABNQAECoEYAAMSAAgKbRvYUwBxAgASAAgKbRvYUwBxAgAEAAIKSA0fWQBOAAAAAA==.Honeybunns:BAAANQADCgUIBQAAAA==.Hosstx:BAAANQADCgEIAQAAAA==.Hotandready:BAAANQAECgYIEwAAAA==.',
Hu='Huffingpaint:BAAANQADCgYIDgABNQAECgIIAgACAAAAAA==.Hukhokhan:BAAANQADCggIDwAAAA==.Hutzil:BAAANQAECgYIEQAAAA==.Hutzilla:BAAANQABCgYICAAAAA==.',
Ia='Iakopa:BAABNQAECoEnAAMTAAkKlhzWLACmAgATAAgK5R3WLACmAgAVAAUKNgdyrQDnAAAAAA==.',
Il='Illidianna:BAABNQAECoEZAAMWAAcK/RgJLgAHAgAWAAcK/RgJLgAHAgANAAUKvQuQQgAHAQAAAA==.',
Im='Imfiredup:BAAANQAECggIBQAAAA==.Imitlol:BAABNQAECoEYAAISAAcKsSNfSQCSAgASAAcKsSNfSQCSAgAAAA==.',
In='Inception:BAAANQADCgYICgAAAA==.Ingress:BAAANQADCgYJBgAAAA==.',
Is='Ishu:BAAANQADCgIIAwAAAA==.',
It='Itchynyple:BAAANQADCgYIEgAAAA==.Ithowen:BAAANQABCgYIBgAAAA==.',
Ja='Jacques:BAAANQADCggIHAAAAA==.Jaetherion:BAAANQAECgUIDwAAAA==.Jakes:BAAANQADCgYJDAAAAA==.Jayhawk:BAAANQAECgEIAgAAAA==.',
Ji='Jimothy:BAAANQADCgcIEwABNQAFFAUICwATACcaAA==.Jinx:BAAANQAECgIIAgAAAA==.',
Jo='Johaliz:BAAANQADCgEIAQAAAA==.Johnnypopoff:BAAANQADCgYIBgAAAA==.Jojohunts:BAAANQAECgEIAQAAAA==.Jonesy:BAAANQADCgIIAgABNQAECggILgAJALcXAA==.',
Ju='Junyubych:BAAANQADCgYIFQABNQAECgQICQACAAAAAA==.',
['Jà']='Jàccuse:BAAANQADCgUIDAABNQAECgUIEgACAAAAAA==.Jàrnsaxa:BAAANQADCggIJgAAAA==.',
['Jò']='Jòhnnypopo:BAABNQAECoEYAAISAAcKIRqdegAGAgASAAcKIRqdegAGAgAAAA==.',
Ka='Kaeladra:BAAANQABCgQIBgABNQAECgEIAwACAAAAAA==.Kagé:BAAANQADCgEIAQAAAA==.Kaisra:BAAANQAECgUICAAAAA==.Kasumeli:BAAANQAECgYIDAAAAA==.Kathelas:BAAANQADCgYIBgAAAA==.Kayd:BAAANQADCggIGAAAAA==.Kayhan:BAAANQADCgQICgAAAA==.Kaylaiis:BAAANQADCggICAAAAA==.Kayos:BAAANQADCgYJFgAAAA==.Kazurend:BAACNQAFFIEMAAMXAAUK7yAxBADgAQAXAAUK7yAxBADgAQABAAEKMgemKwBNAAA1AAQKgSMAAxcACQqnIb0JADADABcACQqnIb0JADADAAEAAQpIF2bXAFAAAAAA.',
Ke='Keyaielenst:BAAANQADCgYICwAAAA==.',
Kh='Khirina:BAAANQAECgYIEAAAAA==.Khristina:BAAANQAECgUIEgAAAA==.Khrogh:BAAANQAECgEIAwAAAA==.',
Ki='Kidiann:BAAANQAECgUICAAAAA==.Kippo:BAEANQAECgcICAAAAA==.Kirar:BAAANQADCgQIBAAAAA==.Kisarrah:BAAANQABCgMIAwAAAA==.',
Kn='Knarn:BAABNQAECoEXAAIJAAcKRR9nQwB8AgAJAAcKRR9nQwB8AgAAAA==.',
Ko='Koralie:BAACNQAFFIERAAIJAAUKWBdlBwCuAQAJAAUKWBdlBwCuAQA1AAQKgSMAAgkACQrXJH8MAGkDAAkACQrXJH8MAGkDAAAA.Korheo:BAAANQADCgQIBAAAAA==.Korrum:BAAANQABCgIIAgAAAA==.',
Kr='Krillaxx:BAAANQAECgQIBAAAAA==.',
Kt='Ktullanux:BAAANQAECgIIAgABNQAECgkJJQAYAOIiAA==.',
Ky='Kyliekat:BAAANQAECgUIDQAAAA==.',
La='Lanceelot:BAAANQADCggIFAAAAA==.Lanel:BAAANQAECgUJCgAAAA==.Lathelous:BAABNQAECoEXAAIEAAcKDyHdDgCKAgAEAAcKDyHdDgCKAgAAAA==.Laulten:BAAANQABCgQIBAAAAA==.',
Le='Leintheir:BAAANQAECgUIBQAAAA==.',
Li='Lideina:BAAANQADCgUIBwAAAA==.Lieahi:BAAANQAECgIIAQAAAA==.Liebesleid:BAAANQADCgYICwABNQAECgIIAgACAAAAAA==.Lightt:BAABNQAECoEvAAIBAAkKyxfmJgCxAgABAAkKyxfmJgCxAgAAAA==.Liightt:BAABNQAECoEdAAIBAAgK8BQzRAA2AgABAAgK8BQzRAA2AgAAAA==.Lilcozz:BAAANQADCgYIFgAAAA==.Lilpyroblast:BAAANQAECgYIEAAAAA==.Liriope:BAAANQADCgYIDwAAAA==.Lizbethstar:BAAANQADCggIDAAAAA==.',
Ll='Llaerwyn:BAAANQADCgUJBwAAAA==.Llars:BAABNQAECoEXAAIVAAcKUBJVbgCRAQAVAAcKUBJVbgCRAQAAAA==.',
Lo='Loryanna:BAAANQADCgYIGAAAAA==.Louie:BAAANQAECgEIAQAAAA==.Lovehandless:BAAANQADCgIIAgAAAA==.',
Lu='Lumenne:BAAANQADCgUIBwAAAA==.Luxore:BAABNQAECoEXAAIEAAkKFBFPGwDpAQAEAAkKFBFPGwDpAQABNQAECgkJJwATAJYcAA==.',
Ly='Lyandrea:BAAANQADCggIIwAAAA==.Lyfebane:BAAANQADCgUJBQAAAA==.Lynaomira:BAAANQADCgMIAwAAAA==.',
['Lõ']='Lõrs:BAAANQADCgMIBQAAAA==.',
['Lø']='Lørs:BAAANQAECgUIDQAAAA==.',
Ma='Main:BAABNQAECoEnAAISAAgKyAnVqQCTAQASAAgKyAnVqQCTAQAAAA==.Majrmiståke:BAACNQAFFIEJAAMPAAUKogXuHQBXAQAPAAUKogXuHQBXAQAOAAIKCAHODQBNAAA1AAQKgRwAAw4ACQp2HIcFAI8CAA4ACArOGocFAI8CAA8ACQpfFFZ8AG4CAAE1AAQKCQklABEAlxIA.Malakir:BAAANQADCgYIDQAAAA==.Malaxxus:BAAANQADCgEIAQAAAA==.Malendorei:BAAANQAECgQIBgAAAA==.Malicemech:BAAANQADCgcIHAAAAA==.Maliceone:BAAANQADCggIJAAAAA==.Malicepaly:BAAANQADCgcIEwAAAA==.Mallucavian:BAAANQAECgMIBwAAAA==.Mamadp:BAAANQAECgQIDAAAAA==.Manaholy:BAAANQADCggICwAAAA==.Manek:BAABNQAECoEuAAIJAAgKtxcfTwBaAgAJAAgKtxcfTwBaAgAAAA==.Marraxa:BAAANQAECgUIDgAAAA==.Maräjade:BAAANQABCgYJBgAAAA==.Max:BAABNQAECoEaAAMZAAkKwhYUVgAyAgAZAAgKNBUUVgAyAgAaAAMKlRNbPQDBAAAAAA==.',
Me='Melevil:BAAANQAECgcIDgAAAA==.Melinoe:BAAANQADCgIIAgAAAA==.Merlin:BAAANQAECgQIBAAAAA==.Merlise:BAAANQADCgcICgAAAA==.Metalgreymon:BAAANQADCgIIAgAAAA==.',
Mi='Milenad:BAAANQAECgYIDAAAAA==.Milho:BAAANQADCgYIBgABNQAFFAIICAAWAEYiAA==.Milkmeholy:BAAANQADCgcICQAAAA==.Minikey:BAAANQADCgMIAwAAAA==.Mishosuki:BAAANQAECgUICgAAAA==.Misscleo:BAABNQAECoEbAAIPAAcKLg/d2ACvAQAPAAcKLg/d2ACvAQAAAA==.Mistalar:BAAANQAECgEIAQAAAA==.',
Mn='Mnesarte:BAAANQADCgUIBQAAAA==.',
Mo='Mobmagnet:BAABNQAECoEzAAIbAAkK9h3LAwD1AgAbAAkK9h3LAwD1AgAAAA==.Moltres:BAEANQAECggIBQAAAA==.Mongoro:BAAANQADCgEIAQAAAA==.Moonkist:BAAANQAECgMICgAAAA==.Moose:BAABNQAECoEZAAMcAAgKmh9OHgC4AgAcAAgKmh9OHgC4AgAMAAEKKx2fsgBFAAAAAA==.Mordrandian:BAAANQADCgYIFgAAAA==.Morroe:BAAANQADCgYIEQAAAA==.',
Mu='Muffintop:BAAANQADCgQICAAAAA==.',
Na='Nadless:BAAANQADCgYIEgAAAA==.Naeliria:BAAANQADCggICAAAAA==.Namuss:BAAANQADCgIIAwAAAA==.Navariis:BAAANQADCgQIDQAAAA==.',
Ne='Necropanzer:BAAANQAECgcIDgABNQAECgcIEwACAAAAAA==.Nelrehim:BAAANQAECgUIBgAAAA==.',
Ni='Niall:BAAANQAECgEIAQABNQAECggIIwAJAEwcAA==.Niandilan:BAAANQADCgYICgAAAA==.Niixxi:BAAANQADCgEIAQAAAA==.',
Nm='Nmbrs:BAAANQADCgQIDAABNQAECgcIBwACAAAAAA==.',
No='Noirah:BAAANQADCgcIBwAAAA==.Noirheffer:BAABNQAECoEoAAMEAAkK7h7MDACsAgAEAAkKMh7MDACsAgASAAUKwRa0xABZAQAAAA==.Nokua:BAAANQAECgQICQAAAA==.Noodles:BAABNQAECoEXAAIdAAcKEQteUgBmAQAdAAcKEQteUgBmAQAAAA==.',
Nu='Nulannatoo:BAAANQAECgIIAgAAAA==.',
Ny='Nyank:BAAANQAECgIIAgABNQAECgcICAACAAAAAA==.Nyleaf:BAAANQADCgUIBwAAAA==.Nyogen:BAAANQAECggJBgAAAA==.Nyxaraa:BAAANQADCgYIEAAAAA==.',
Oc='Octomore:BAABNQAECoEXAAIPAAcKwBCIzgDEAQAPAAcKwBCIzgDEAQAAAA==.',
Od='Odysseus:BAABNQAECoEcAAIKAAcK1w9DMQCZAQAKAAcK1w9DMQCZAQAAAA==.',
Ol='Olgann:BAAANQAECgIIAgAAAA==.Olguita:BAAANQAECgQIDAAAAA==.',
Om='Omez:BAAANQAECgQIBgABNQAECggIHgAEACEhAA==.Omgowned:BAAANQAECgIIAgABNQAECgcIFwAZAPIVAA==.',
On='Onehothealer:BAAANQADCgYIBwAAAA==.',
Oo='Oorua:BAAANQADCggIGQAAAA==.',
Op='Opheliastar:BAABNQAECoEiAAIXAAgK4RdqHgAmAgAXAAgK4RdqHgAmAgAAAA==.',
Or='Ordovis:BAAANQAECgUIDAAAAA==.Orlucicia:BAAANQADCgcICgAAAA==.Orobas:BAAANQAECggIAgAAAA==.',
Ow='Owltoidz:BAAANQABCgUIBAAAAA==.',
Pa='Pace:BAAANQABCgYICgAAAA==.Pad:BAAANQAECgMICgAAAA==.Paladerp:BAAANQAECgIIAwAAAA==.Palanym:BAABNQAECoEcAAIRAAgKuhRvTQAUAgARAAgKuhRvTQAUAgAAAA==.Palidyne:BAAANQAECgEIAQAAAA==.Pallyown:BAAANQAECgcICgAAAA==.Papamidnite:BAAANQADCgMIAwAAAA==.Papichulo:BAAANQADCgcIDQAAAA==.Parox:BAAANQADCgYIBwAAAA==.',
Ph='Phelement:BAAANQAECgcIEwAAAA==.Phett:BAABNQAECoEhAAMeAAgKQSPKAwDrAgAeAAcKZCTKAwDrAgAfAAMKeRMx9gDBAAAAAA==.Phonk:BAAANQADCgQIAwABNQAECgcIEwACAAAAAA==.Phædrea:BAAANQADCggICAAAAA==.',
Pi='Picklës:BAAANQADCgUIBQABNQAECgcIHQABAIAjAA==.Piffi:BAAANQAECgEIAQAAAA==.Pimmscup:BAAANQADCgYIFgAAAA==.',
Pr='Praedthy:BAAANQAECgYIDQAAAA==.',
Qo='Qohelet:BAAANQAECgQIBQAAAA==.',
Ra='Raatus:BAAANQAECgIIAgABNQAECggIGgAMAG8hAA==.Raenya:BAAANQAECgIIAgAAAA==.Raikouu:BAAANQAECgYIDgAAAA==.Rainydaze:BAAANQAECgIIAgAAAA==.Ramani:BAAANQADCgEIAQAAAA==.Ramasses:BAAANQADCgYICgAAAA==.Ramcharger:BAAANQAECgEIAQABNQAECggIIwAJAEwcAA==.Ramoreo:BAAANQAECgUIDgABNQAECgcIIAAWABYJAA==.Rashun:BAABNQAECoEVAAIUAAcKuBYMJADXAQAUAAcKuBYMJADXAQAAAA==.Raviolee:BAAANQAECgEIAQABNQAECgcIFwAZAPIVAA==.',
Re='Reanatilax:BAAANQABCgMJBQABNQAECgUIEgACAAAAAA==.Regnier:BAAANQADCgYICgAAAA==.Relaeh:BAAANQADCgcJDQAAAA==.Resusitate:BAAANQADCgYJBgAAAA==.Rexxy:BAAANQADCgcICwAAAA==.',
Rh='Rhod:BAAANQADCgcICwABNQAECgYICQACAAAAAA==.',
Ri='Rikashae:BAAANQADCgYJBgAAAA==.Rissa:BAAANQADCgEIAQAAAA==.Risuku:BAAANQADCgEIAQAAAA==.',
Ro='Roleon:BAAANQADCgYICwAAAA==.Rollforpi:BAAANQAECgEIAQABNQAFFAUICgADANgYAA==.Ropebunnyana:BAAANQAECgIJAwABNQAECggIFgABAOYfAA==.',
Ru='Ruki:BAAANQAECgIIAgAAAA==.Rumshwizzle:BAAANQADCgQJBAAAAA==.',
Sa='Saltydk:BAABNQAECoEgAAIcAAkK8iDSHQC7AgAcAAkK8iDSHQC7AgAAAA==.Samiracy:BAAANQAECgYIEQAAAA==.Sataro:BAAANQABCggICgAAAA==.',
Sc='Scappe:BAABNQAECoEaAAIMAAgKbyGsFwDaAgAMAAgKbyGsFwDaAgAAAA==.',
Se='Seefoof:BAAANQADCgIIAgAAAA==.Seitaer:BAAANQADCgEJAQAAAA==.Senbatorii:BAAANQAECgUIEgAAAA==.Sentrosi:BAAANQAECgEIAQAAAA==.Sethrow:BAABNQAECoEXAAMZAAcK8hWYhwClAQAZAAYKohWYhwClAQAaAAEK1RdYaABEAAAAAA==.Severa:BAAANQAECgUIEAAAAA==.',
Sh='Shadoh:BAAANQAECgIIAgAAAA==.Shamazing:BAAANQADCgEIAQAAAA==.Shamwowsale:BAAANQADCgYIDAAAAA==.Shamwowza:BAABNQAECoEgAAIVAAgKdxBaXADLAQAVAAgKdxBaXADLAQAAAA==.Shantifa:BAAANQADCgYICwAAAA==.Shengari:BAAANQADCgIIAgABNQADCgQIBAACAAAAAA==.Shoshanaa:BAAANQADCgUICwAAAA==.Shotcallà:BAAANQADCgYIBwABNQADCggICAACAAAAAA==.Shuna:BAAANQADCgYICQAAAA==.Shyly:BAAANQAECgIIAgAAAA==.',
Si='Siley:BAABNQAECoEtAAIcAAgKGg/5UQCiAQAcAAgKGg/5UQCiAQAAAA==.',
Sn='Sneakysneak:BAABNQAECoEZAAIgAAgKixUmBgBfAgAgAAgKixUmBgBfAgAAAA==.Snüff:BAAANQADCgMIAwAAAA==.',
So='Somavan:BAAANQADCgMIAwABNQAECggIIwAJAEwcAA==.Somepriest:BAAANQAECgYIEgAAAA==.Sotteria:BAAANQABCgQIBAAAAA==.',
Sp='Spiarmf:BAAANQADCgMIAwAAAA==.Sprockett:BAAANQADCggICAAAAA==.Spycmchaggis:BAAANQAECgMIBAAAAA==.Spëcter:BAAANQAECgMIAwABNQAECgcIFwAPAMAQAA==.',
St='Stiffkitten:BAAANQADCgEJAQAAAA==.Sturba:BAAANQABCgIIAgAAAA==.',
Su='Sugrace:BAAANQADCgQIBAAAAA==.Sunaerosinda:BAAANQADCgYIBgAAAA==.Sunow:BAAANQADCgUIEQAAAA==.Superdemonzz:BAAANQAECgUIBgABNQAECgkJJQARAJcSAA==.Superpallyz:BAABNQAECoElAAQRAAkKlxJERAA2AgARAAkKlxJERAA2AgASAAEKNRIXcQE2AAAEAAEKPgJSbgAhAAAAAA==.Superspidey:BAAANQADCgIIAgAAAA==.',
Sw='Swipeleft:BAABNQAECoEqAAIdAAgKLBYoMgAsAgAdAAgKLBYoMgAsAgAAAA==.',
Sy='Sylora:BAAANQADCgIIAgAAAA==.',
Ta='Tabarnak:BAABNQAECoEaAAIhAAkKaRsQBwACAwAhAAkKaRsQBwACAwABNQAECgkJMQAUACYkAA==.Taiynn:BAAANQADCggIFwAAAA==.Tallon:BAAANQAFFAEIAQAAAA==.Tarogen:BAAANQAECgMIBwAAAA==.Taszherazade:BAAANQADCgEJAQAAAA==.',
Te='Teknique:BAAANQAECgIIAgAAAA==.Tendroni:BAAANQAECgcIEgAAAA==.Tervor:BAAANQAECgEIAQAAAA==.Tessadin:BAAANQADCgEJAQAAAA==.',
Th='Thanamoros:BAABNQAECoEeAAIbAAkKhg0+DQC7AQAbAAkKhg0+DQC7AQABNQAECgkJJwATAJYcAA==.Theredwake:BAAANQAECgYICgAAAA==.Theroach:BAAANQAECgIIAwAAAA==.Thgiewerom:BAAANQABCgYIBwAAAA==.Throfin:BAAANQAECgYIBgAAAA==.Thwaxi:BAAANQADCgQJCAAAAA==.',
Ti='Timeismoney:BAAANQADCggIFwAAAA==.Tiognaska:BAAANQAECgQICAAAAA==.Tirdain:BAAANQADCgEIAQAAAA==.',
Tl='Tlcbm:BAABNQAECoEeAAILAAkKFxfSCgBnAgALAAkKFxfSCgBnAgAAAA==.',
To='Toeren:BAACNQAFFIELAAIJAAUKrhFICACdAQAJAAUKrhFICACdAQA1AAQKgS4AAgkACQq0IVgPAFUDAAkACQq0IVgPAFUDAAAA.Tokå:BAAANQADCgIIAgAAAA==.Torage:BAAANQAECgEJAQAAAA==.Tormentah:BAAANQADCgIIAgABNQAECggIIgAOAJ4ZAA==.Torosentado:BAAANQAECgQICAAAAA==.',
Tr='Trenity:BAAANQAECgMIBAAAAA==.Triplecanopy:BAAANQADCgUICwAAAA==.Trollie:BAAANQADCgEIAQAAAA==.Trumu:BAAANQAECgEIAQAAAA==.Trïsh:BAAANQADCgQIBAABNQAECgYIHQAEAEARAA==.',
Ty='Tyinorin:BAAANQADCgYIFgAAAA==.',
['Tä']='Täryn:BAAANQADCgEIAQAAAA==.',
Ub='Ubee:BAAANQAECgUIDAAAAA==.',
Ud='Udderjustice:BAABNQAECoEaAAIEAAcKAw/lKgBaAQAEAAcKAw/lKgBaAQAAAA==.',
Ug='Uglyelf:BAAANQAECgUICgAAAA==.',
Ul='Ultimakitty:BAAANQADCggIDAAAAA==.',
Un='Uncertainty:BAAANQADCgUIBQABNQAECgIIAgACAAAAAA==.Unchanged:BAAANQAECgIIAgAAAA==.',
Va='Vaeldrin:BAAANQADCgUIBQAAAA==.Vanhellsings:BAAANQAECgEIAQAAAA==.Vantrix:BAABNQAECoEzAAMdAAkKQhmsHgC5AgAdAAkKQhmsHgC5AgADAAYKohARMABlAQABNQAECgkJJwATAJYcAA==.Varabo:BAAANQAECgUIBQAAAA==.Varolina:BAAANQADCggIJQAAAA==.',
Ve='Velmara:BAAANQABCgMIAwAAAA==.Velthala:BAAANQAECgYIDwAAAA==.Velyra:BAAANQAECgMIBQAAAA==.',
Vi='Vitner:BAAANQADCgMIBAABNQAECgkJFwAZAKQWAA==.Vivieneaux:BAAANQABCgUICAAAAA==.Vixsen:BAAANQABCgcIDQAAAA==.',
Vl='Vladdawngard:BAAANQAECggICAAAAA==.',
Vo='Voidcorpse:BAAANQADCgEIAQAAAA==.Voidmama:BAAANQADCgYIBgAAAA==.Voidryn:BAAANQABCgcIEQAAAA==.Voidshifter:BAAANQADCgUIBQAAAA==.Vosaleana:BAAANQAECgQICQAAAA==.',
Vr='Vraak:BAACNQAFFIEKAAIDAAUK2BjZBACvAQADAAUK2BjZBACvAQA1AAQKgSIAAwMACQo3JJEEAGwDAAMACQo3JJEEAGwDAB0AAgrpIFB6ALkAAAAA.',
Vu='Vulcus:BAAANQAECgIIAwABNQAFFAUICgADANgYAA==.',
Vy='Vyndarien:BAAANQABCgcICQAAAA==.',
Wa='Wa:BAAANQAECgMICgAAAA==.Walimagus:BAAANQADCggICAAAAA==.Wayofthemist:BAAANQABCgIIAgAAAA==.',
Wc='Wcreator:BAAANQAECgIIAgAAAA==.',
Wh='Wheeljack:BAAANQAECgUIBgAAAA==.',
Wi='Widowcancer:BAAANQADCgIJAgAAAA==.Will:BAACNQAFFIEFAAISAAIKZR/cFgC7AAASAAIKZR/cFgC7AAA1AAQKgSgAAhIACQqkJSEIALEDABIACQqkJSEIALEDAAAA.',
Wo='Womdalie:BAAANQADCggIGAAAAA==.',
Wy='Wyckedpally:BAAANQAECgQICAABNQAECgQICQACAAAAAA==.',
Xa='Xanthös:BAAANQAFFAIIAgABNQAFFAUICgADANgYAA==.',
Xe='Xemnastrasza:BAABNQAECoEYAAMFAAgKlBYUEgASAgAFAAgK6BUUEgASAgAiAAIKJBSpGQB5AAABNQAECgkJJwATAJYcAA==.Xenonne:BAAANQAECgMIBAABNQAECgkJKgARAFccAA==.',
Xo='Xolither:BAAANQAECgUIEgAAAA==.',
Yo='Yorgo:BAAANQADCggICAAAAA==.Yourwivesbf:BAAANQADCggICQAAAA==.',
Yu='Yuura:BAAANQAECgMIBAAAAA==.',
Za='Zachdemon:BAABNQAECoEeAAIbAAcKJhIuDwCSAQAbAAcKJhIuDwCSAQAAAA==.Zazoo:BAAANQABCgEIAQAAAA==.',
Ze='Zenyátta:BAAANQAECgMIBQAAAA==.Zephymoo:BAABNQAECoEwAAMjAAkKhxfICwA4AgAjAAgKyxXICwA4AgAdAAQKuhXQaAD9AAAAAA==.Zeretha:BAAANQABCgIIAgAAAA==.Zershadowi:BAAANQAECgEIAQAAAA==.Zeyana:BAAANQAECgYIEAABNQAECgkJKAAJAI4aAA==.',
Zh='Zhengshi:BAAANQAECgYIEgAAAA==.',
Zi='Zinsatra:BAAANQADCgEIAQAAAA==.',
Zk='Zkarlyse:BAAANQAECgcIDQAAAA==.',
Zo='Zoose:BAABNQAECoEXAAQfAAcKzxY8jQDUAQAfAAcKPhQ8jQDUAQALAAQKORZYJADzAAAeAAEKhg4jLQA2AAAAAA==.Zosahe:BAAANQAECgYIDAAAAA==.Zoser:BAAANQAECgUIDgAAAA==.',
Zs='Zsófia:BAAANQADCgcIBwAAAA==.',
Zu='Zuckuss:BAAANQADCgYIFgAAAA==.',
Zy='Zymri:BAAANQADCgUICQABNQAECgMICgACAAAAAA==.',
['Æl']='Ælthan:BAAANQAECgEIAQAAAA==.',
['Ér']='Érubus:BAAANQAECgIIAgAAAA==.',
['Öl']='Ölivê:BAAANQAECgcIDQAAAA==.',
['ßu']='ßugs:BAAANQAECgYIDwAAAA==.',
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
