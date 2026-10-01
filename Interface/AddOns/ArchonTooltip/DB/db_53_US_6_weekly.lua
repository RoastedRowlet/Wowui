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

local lookup = {'Unknown-Unknown','Druid-Restoration','Paladin-Protection','Evoker-Devastation','Evoker-Preservation','Priest-Discipline','Hunter-BeastMastery','Hunter-Marksmanship','Warrior-Fury','DemonHunter-Devourer','Mage-Arcane','Mage-Frost','Mage-Fire','Paladin-Holy','Paladin-Retribution','Priest-Holy','Monk-Brewmaster','Monk-Windwalker','Shaman-Elemental','Shaman-Restoration','Druid-Balance','Priest-Shadow','DeathKnight-Blood','DemonHunter-Havoc','DemonHunter-Vengeance','Warrior-Arms','DeathKnight-Unholy','Rogue-Outlaw','Druid-Feral',}
local provider = {region='US',realm='Alexstrasza',name='US',type='weekly',zone=53,date='2026-09-29',data={Ac='Acbabcaa:BAAANQADCgEIAQAAAA==.Aceon:BAAANQAECgIIBAAAAA==.Aceonarcher:BAAANQAECgQICAAAAA==.',
Ad='Adfectia:BAAANQAECgUICgAAAA==.',
Ae='Aelianna:BAAANQAECgQIBAAAAA==.Aeryana:BAAANQAECgcIDgAAAA==.Aeth:BAAANQAECgYIDAABNQAECgcIDAABAAAAAA==.Aethér:BAAANQAECgQICwABNQAECgkJIQACAGwjAA==.',
Ag='Aggroout:BAAANQADCgYIBgABNQAECgkJIAADAEgcAA==.',
Ah='Ahsöka:BAAANQADCgIIAgAAAA==.',
Ai='Aimbel:BAAANQADCgQICQAAAA==.',
Al='Alexstrászá:BAAANQAECgUICwAAAA==.Alynas:BAAANQADCgUIBQAAAA==.Alysona:BAAANQADCgUIDQAAAA==.',
Am='Amaarii:BAAANQABCgQJCAAAAA==.Ambeia:BAAANQADCgQJBAAAAA==.Amewow:BAACNQAFFIEHAAIEAAQK8CLiAgCkAQAEAAQK8CLiAgCkAQA1AAQKgS0AAwQACQraI6YBAJgDAAQACQraI6YBAJgDAAUAAgpWA2U9AFgAAAAA.Amoril:BAAANQAECgYIBwAAAA==.',
An='Anarchy:BAAANQAECgUICgAAAA==.Andraxi:BAAANQADCgYICwAAAA==.Angewomon:BAAANQADCgIIAgAAAA==.Anorakswrath:BAAANQAECgcIDwAAAA==.',
Ap='Apophys:BAAANQADCgYJEgAAAA==.Apoptosis:BAAANQABCgYICAAAAA==.',
Ar='Ariees:BAAANQADCgEIAQAAAA==.Artfulrodent:BAAANQADCgQIBAAAAA==.Aruneza:BAAANQAECgYIEAAAAA==.',
As='Asherous:BAAANQADCgQIBgABNQAECgQIBgABAAAAAA==.Ashèr:BAAANQAECgQIBgAAAA==.Asunnaa:BAAANQADCgIIAwAAAA==.',
At='Atenchion:BAAANQAECgQIBAAAAA==.Atticuz:BAAANQADCgIIAgAAAA==.',
Au='Aura:BAAANQAECgUIDgAAAA==.Auralion:BAAANQADCgYIBwAAAA==.Autoignition:BAAANQAECgcIEwAAAA==.',
Ba='Bahnkano:BAAANQAECgUICwAAAA==.Bakeddh:BAAANQADCgYJDAAAAA==.Banditz:BAAANQADCgcJDwAAAA==.Bashfury:BAAANQAECgEIAQAAAA==.',
Be='Beefcåkes:BAAANQAECgUIDQAAAA==.Beenah:BAAANQAECgMIBwAAAA==.Beyshunt:BAAANQADCgYICgAAAA==.',
Bl='Bloodrain:BAAANQAECggIBwAAAA==.Blàst:BAAANQAECgEIAQAAAA==.',
Bo='Boltcutter:BAAANQADCgEJAQAAAA==.Bombmagic:BAAANQADCgMIAwAAAA==.Bonesmccoy:BAAANQABCgQIBAAAAA==.Boomie:BAAANQAECggIBwAAAA==.Boopty:BAAANQAECgIIAwAAAA==.Booptydo:BAAANQADCggIFgAAAA==.Boris:BAAANQAECgIIAgAAAA==.Bowhawk:BAAANQAECgMIBwAAAA==.',
Bp='Bpwhunter:BAAANQAECgQICgAAAA==.',
Br='Braiin:BAAANQAECgQIBQABNQAECgkJIQACAGwjAA==.Brazyn:BAAANQADCggIIwAAAA==.Brevarda:BAAANQAECgYICgAAAA==.Brewcelee:BAAANQAECgYIEAAAAA==.',
Bu='Bubblzmgee:BAABNQAECoEdAAIGAAcKtR9nAwCKAgAGAAcKtR9nAwCKAgAAAA==.Buscemi:BAAANQADCggIDAAAAA==.Bustofez:BAAANQADCgYICwAAAA==.Buttèrs:BAAANQADCgEIAQAAAA==.',
['Bé']='Béach:BAAANQADCgQIBQAAAA==.',
Ca='Capone:BAAANQADCgcIBwAAAA==.Caracalous:BAAANQAECgYICwAAAA==.Carindria:BAAANQADCggIFwAAAA==.Carninn:BAAANQADCgUIBQAAAA==.Castermcfear:BAAANQABCgIIAgAAAA==.Cattiebrie:BAAANQAECgIIBgAAAA==.Caylavana:BAABNQAECoEcAAIHAAgK/xmeLwCdAgAHAAgK/xmeLwCdAgAAAA==.',
Ce='Celaylria:BAAANQAECgYIEQAAAA==.',
Ch='Charmeleön:BAAANQADCgYIBgAAAA==.Chronicfury:BAAANQABCgIIAgAAAA==.',
Cl='Cloudedjayd:BAAANQADCgcIDgAAAA==.Cloudedmonk:BAAANQADCgUICQAAAA==.Clugorn:BAAANQAECgYIEwAAAA==.Clydè:BAAANQADCgYIEQAAAA==.',
Co='Codyj:BAAANQADCggICQAAAA==.Colossus:BAAANQADCggJCwAAAA==.Colourhunt:BAABNQAECoEWAAMIAAgKLw3sLgB8AQAHAAYKNQs0iwCRAQAIAAcKeAzsLgB8AQAAAA==.Condewit:BAAANQADCgUIBQAAAA==.Conoresa:BAAANQADCgMIAwAAAA==.Copedk:BAAANQAECgUIDwAAAA==.Corrode:BAAANQAECgEIAQAAAA==.Cozymav:BAAANQADCgUIBQAAAA==.',
Cp='Cpt:BAAANQADCgEIAQAAAA==.',
Cr='Crinke:BAAANQABCgIIAgAAAA==.Crusadare:BAAANQAECgQIBAAAAA==.',
Cy='Cybeldin:BAAANQAECgUIDQAAAA==.Cyberdemonxd:BAAANQADCgYICAABNQAECgIIAgABAAAAAA==.Cyndyr:BAAANQADCgYIFgAAAA==.',
['Cë']='Cërßerus:BAAANQADCgYIBgAAAA==.',
Da='Daddysparey:BAAANQAECgQIBQAAAA==.Dalarrus:BAAANQAECgMIBAABNQAECggIHAAHAP8ZAA==.Dalishya:BAAANQADCgQIBAAAAA==.Darek:BAAANQAECgQICQAAAA==.Darilyns:BAAANQADCgQJBQAAAA==.Darkbiffhunt:BAAANQADCgMIAwAAAA==.Darkrife:BAAANQADCgYJDgAAAA==.Darylinn:BAAANQADCgQJBgAAAA==.Daymann:BAAANQAECgIIAwAAAA==.',
De='Demonrife:BAAANQABCgYIBgABNQADCgYJDgABAAAAAA==.Dernis:BAAANQAECgIIAgABNQAECggIGQAJAG0ZAA==.Derplock:BAAANQADCgcIEAAAAA==.Deshaman:BAAANQADCgMIAwABNQAFFAQIBgAHAK4SAA==.Devilbeast:BAAANQAECgQIDQAAAA==.Dew:BAAANQABCgQIAwAAAA==.',
Dh='Dhargo:BAAANQAECgUICgABNQAECgQIBQABAAAAAA==.',
Di='Diablosauz:BAAANQADCgQIBAAAAA==.Diaous:BAAANQADCgUICgAAAA==.Disasterina:BAAANQADCgcIBwABNQAECggIHAAKAGkdAA==.Disgruntled:BAAANQAECgcIEQAAAA==.',
Do='Docbrown:BAAANQADCgEIAQAAAA==.Dontormentaa:BAAANQAECgMIBQABNQAECggIHQALADgZAA==.Dontormentaj:BAABNQAECoEdAAQLAAgKOBmsbAByAgALAAgKOBmsbAByAgAMAAIKlRHqJQB6AAANAAEKVRZ9CABNAAAAAA==.Doomzday:BAAANQADCgYIDQAAAA==.',
Dr='Dracthra:BAAANQAECgUIDQAAAA==.Drakk:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Dreamhammer:BAAANQABCgUIBQAAAA==.Dreamlesnite:BAAANQABCggIEQAAAA==.Dreidelman:BAAANQAECgIIAgAAAA==.',
Du='Dugdimadome:BAAANQAECgMIAwAAAA==.',
Dy='Dylora:BAAANQAECgYIDAAAAA==.',
Ea='Ealdoras:BAAANQADCggIDgAAAA==.',
Eg='Egg:BAABNQAECoEaAAMOAAkK2x7UCwBKAwAOAAkK2x7UCwBKAwAPAAEKqAwGZAEnAAABNQAFFAYIFwAQAMEUAA==.',
El='Elassha:BAAANQADCggICwAAAA==.Elatio:BAAANQAECgQIDgAAAA==.Elfairea:BAAANQADCgEIAQAAAA==.Elmortal:BAAANQAECgQJBgAAAA==.Elystaria:BAAANQAECgMIBwAAAA==.',
Em='Emokins:BAEANQAECgYIEAAAAA==.',
En='Enyos:BAAANQABCgEIAQAAAA==.',
Ep='Epicnakedman:BAAANQAECggICAABNQAECggIJwAOAPUWAA==.',
Er='Erubus:BAABNQAECoElAAMRAAkKHiJ0AgBgAwARAAkKHiJ0AgBgAwASAAIK/hXwRACGAAAAAA==.Erubuss:BAAANQADCgcIBwAAAA==.Eryss:BAAANQAECgMIBwAAAA==.',
Ex='Excalibúr:BAAANQADCgcIBwAAAA==.',
Fa='Faithfulone:BAAANQAECgMIBwAAAA==.Farfidnoogan:BAAANQABCgQIBAAAAA==.Fatercul:BAAANQADCgEIAQAAAA==.',
Fd='Fdk:BAAANQAECgcIBwAAAA==.',
Fe='Fellariene:BAAANQADCgUIBQAAAA==.',
Fo='Forilla:BAAANQAECgQIBQAAAA==.Fortissimo:BAAANQADCgYICgAAAA==.',
['Fà']='Fàmous:BAAANQAECgYICQAAAA==.',
Ga='Galabris:BAAANQAECgYIDwAAAA==.Gasilbench:BAAANQAECgEIAQAAAA==.Gazzik:BAAANQADCggICAAAAA==.',
Gh='Ghostboydk:BAAANQADCgYIBgABNQAECgUICAABAAAAAA==.',
Gi='Gimligrimes:BAAANQADCgYIBgAAAA==.Gington:BAAANQADCgYJEgAAAA==.Gitchusum:BAAANQAECgYIBgAAAA==.',
Gl='Glaivenez:BAAANQAECggIBgAAAA==.Gleenna:BAAANQAECgYIBgAAAA==.Glorify:BAAANQADCggIDwABNQAECgUIDAABAAAAAA==.',
Go='Goose:BAAANQAECgYIEgAAAA==.Gormladin:BAAANQADCgUIEQAAAA==.Gormstorm:BAAANQAECgMIBQAAAA==.',
Gr='Greenbahamut:BAAANQADCgEIAQAAAA==.Grimsreaper:BAAANQADCgQIBAAAAA==.Grouchy:BAAANQADCgQIBgABNQAECgcIBwABAAAAAA==.',
Gw='Gwynythe:BAAANQADCgEJAQAAAA==.',
Ha='Hadriac:BAAANQADCgQJBAAAAA==.Hailes:BAAANQABCgIIAQAAAA==.Halfang:BAAANQADCggIHgAAAA==.Hanta:BAAANQAECgcIDwAAAA==.',
He='Hentaime:BAAANQABCgMIAwAAAA==.',
Hi='Hitpoints:BAAANQADCgYIDAABNQAECgUIDAABAAAAAA==.',
Ho='Holispirit:BAAANQABCgMIAwAAAA==.Holyfrog:BAAANQAECgQIBQAAAA==.Holyhope:BAABNQAECoEnAAIOAAgK9RZxNwBKAgAOAAgK9RZxNwBKAgAAAA==.Holylightz:BAAANQAECgMIAwAAAA==.Holymana:BAAANQAECgUIDQAAAA==.Honeybunns:BAAANQADCgUIBQAAAA==.Hosstx:BAAANQADCgEIAQAAAA==.Hotandready:BAAANQAECgYIDgAAAA==.',
Hu='Huffingpaint:BAAANQADCgYIDgABNQADCggIGQABAAAAAA==.Hukhokhan:BAAANQADCggIDwAAAA==.Hutzil:BAAANQAECgYJDgAAAA==.Hutzilla:BAAANQABCgYICAAAAA==.',
Ia='Iakopa:BAABNQAECoEjAAMTAAkKDBoILwB/AgATAAgKChsILwB/AgAUAAUKNgcFlwD2AAABNQAECgkJKgAVACIXAA==.',
Il='Illidianna:BAAANQAECgYIEAAAAA==.',
Im='Imfiredup:BAAANQAECggIBQAAAA==.Imitlol:BAABNQAECoEXAAIPAAcKsSNhNwCtAgAPAAcKsSNhNwCtAgAAAA==.',
In='Inception:BAAANQADCgYICAAAAA==.Ingress:BAAANQADCgYJBgAAAA==.',
It='Itchynyple:BAAANQADCgYJDgAAAA==.Ithowen:BAAANQABCgYIBgAAAA==.',
Ja='Jacques:BAAANQADCggIHAAAAA==.Jaetherion:BAAANQAECgUICgAAAA==.Jakes:BAAANQADCgYJDAAAAA==.Jayhawk:BAAANQAECgEIAgAAAA==.',
Ji='Jimothy:BAAANQADCgcIEwABNQAFFAUICAATACIaAA==.Jinx:BAAANQADCggIGwAAAA==.',
Jo='Johaliz:BAAANQADCgEIAQAAAA==.Johnnypopoff:BAAANQADCgYIBgAAAA==.Jojohunts:BAAANQAECgEIAQAAAA==.Jonesy:BAAANQADCgIIAgABNQAECggIJAAHAAYWAA==.',
Ju='Junyubych:BAAANQADCgYIDwABNQAECgQIBQABAAAAAA==.',
['Jà']='Jàccuse:BAAANQADCgUIDAABNQAECgUIDQABAAAAAA==.Jàrnsaxa:BAAANQADCggIJgAAAA==.',
['Jò']='Jòhnnypopo:BAAANQAECgUIDwAAAA==.',
Ka='Kaeladra:BAAANQABCgQIBgABNQAECgEIAgABAAAAAA==.Kagé:BAAANQADCgEIAQAAAA==.Kaisra:BAAANQAECgMJAwAAAA==.Kasumeli:BAAANQAECgYIDAAAAA==.Kathelas:BAAANQADCgYIBgAAAA==.Kayd:BAAANQADCggIEAAAAA==.Kayhan:BAAANQADCgQICgAAAA==.Kaylaiis:BAAANQADCggICAAAAA==.Kayos:BAAANQADCgYJFgAAAA==.Kazurend:BAACNQAFFIEIAAMWAAUK5xxFAwDZAQAWAAUK5xxFAwDZAQAQAAEKMgcMJgBNAAA1AAQKgSAAAxYACQoNIagIADIDABYACQoNIagIADIDABAAAQpIF8e+AFAAAAAA.',
Ke='Keyaielenst:BAAANQADCgYICwAAAA==.',
Kh='Khirina:BAAANQAECgYICgAAAA==.Khristina:BAAANQAECgUIDQAAAA==.Khrogh:BAAANQAECgEIAgAAAA==.',
Ki='Kidiann:BAAANQAECgQIBAAAAA==.Kippo:BAEANQAECgcICAAAAA==.Kisarrah:BAAANQABCgMIAwAAAA==.',
Kn='Knarn:BAAANQAECgYIEAAAAA==.',
Ko='Koralie:BAACNQAFFIENAAIHAAUKCRUIBQCrAQAHAAUKCRUIBQCrAQA1AAQKgSAAAgcACQqkJKIJAHEDAAcACQqkJKIJAHEDAAAA.Korheo:BAAANQADCgQIBAAAAA==.Korrum:BAAANQABCgIIAgAAAA==.',
Kr='Krillaxx:BAAANQAECgQIBAAAAA==.',
Kt='Ktullanux:BAAANQAECgIIAgABNQAECgkJHQAXABkgAA==.',
Ky='Kyliekat:BAAANQAECgUIDQAAAA==.',
La='Lanceelot:BAAANQADCggIFAAAAA==.Lanel:BAAANQAECgUJCgAAAA==.Lathelous:BAAANQAECgYIEAAAAA==.Laulten:BAAANQABCgQIBAAAAA==.',
Le='Leintheir:BAAANQAECgUIBQAAAA==.',
Li='Lideina:BAAANQADCgUIBQAAAA==.Lieahi:BAAANQAECgIIAQAAAA==.Liebesleid:BAAANQADCgYICwABNQADCggIGQABAAAAAA==.Lightt:BAABNQAECoEnAAIQAAkKoBYsJACiAgAQAAkKoBYsJACiAgAAAA==.Liightt:BAAANQAECgUIEgAAAA==.Lilcozz:BAAANQADCgYIFgAAAA==.Lilpyroblast:BAAANQAECgUICgAAAA==.Liriope:BAAANQADCgYICwAAAA==.Lizbethstar:BAAANQADCggIDAAAAA==.',
Ll='Llaerwyn:BAAANQADCgUJBwAAAA==.Llars:BAAANQAECgYIEAAAAA==.',
Lo='Loryanna:BAAANQADCgYIGAAAAA==.Louie:BAAANQADCggIFQAAAA==.Lovehandless:BAAANQADCgIIAgAAAA==.',
Lu='Lumenne:BAAANQADCgIIAgAAAA==.Luxore:BAAANQAECggIDwABNQAECgkJKgAVACIXAA==.',
Ly='Lyandrea:BAAANQADCggIHAAAAA==.Lyfebane:BAAANQADCgUJBQAAAA==.Lynaomira:BAAANQADCgMIAwAAAA==.',
['Lõ']='Lõrs:BAAANQADCgMIBQAAAA==.',
['Lø']='Lørs:BAAANQAECgUIDQAAAA==.',
Ma='Main:BAABNQAECoEfAAIPAAgKAQfOogBsAQAPAAgKAQfOogBsAQAAAA==.Majrmiståke:BAAANQAFFAQIBAABNQAECgkJJAAOAJcSAA==.Malakir:BAAANQADCgUIBwAAAA==.Malaxxus:BAAANQADCgEIAQAAAA==.Malendorei:BAAANQAECgIIAgAAAA==.Malicemech:BAAANQADCgcIHAAAAA==.Maliceone:BAAANQADCggIJAAAAA==.Malicepaly:BAAANQADCgcIEwAAAA==.Mallucavian:BAAANQAECgMIBQAAAA==.Mamadp:BAAANQAECgMICAAAAA==.Manaholy:BAAANQADCggICAAAAA==.Manek:BAABNQAECoEkAAIHAAgKBhZMSQBFAgAHAAgKBhZMSQBFAgAAAA==.Marraxa:BAAANQAECgQICQAAAA==.Maräjade:BAAANQABCgYJBgAAAA==.Max:BAAANQAECgcIEQAAAA==.',
Me='Melevil:BAAANQAECgUIBwAAAA==.Melinoe:BAAANQADCgIIAgAAAA==.Merlin:BAAANQADCgcIBwAAAA==.Merlise:BAAANQADCgcICgAAAA==.Metalgreymon:BAAANQADCgIIAgAAAA==.',
Mi='Milenad:BAAANQAECgYIDAAAAA==.Milho:BAAANQADCgYIBgABNQAFFAIIBwAYAHkgAA==.Milkmeholy:BAAANQADCgcIBwAAAA==.Minikey:BAAANQADCgMIAwAAAA==.Mishosuki:BAAANQAECgUIBgAAAA==.Misscleo:BAAANQAECgYIEAAAAA==.',
Mn='Mnesarte:BAAANQADCgUIBQAAAA==.',
Mo='Mobmagnet:BAABNQAECoEvAAIZAAkKdxq6AwDRAgAZAAkKdxq6AwDRAgAAAA==.Moltres:BAEANQAECggIBQAAAA==.Mongoro:BAAANQABCgIIAgAAAA==.Moonkist:BAAANQAECgMIBwAAAA==.Moose:BAAANQAECgcIEAAAAA==.Mordrandian:BAAANQADCgYIFgAAAA==.Morroe:BAAANQADCgYIEQAAAA==.',
Mu='Muffintop:BAAANQADCgQIBAAAAA==.',
Na='Nadless:BAAANQADCgYIDAAAAA==.Naeliria:BAAANQADCggICAAAAA==.Namuss:BAAANQADCgIIAwAAAA==.Navariis:BAAANQADCgQIDQAAAA==.',
Ne='Necropanzer:BAAANQAECgcIBwABNQAECgcIEwABAAAAAA==.Nelrehim:BAAANQAECgUIBgAAAA==.',
Ni='Niall:BAAANQAECgEIAQABNQAECggIHAAHAP8ZAA==.Niandilan:BAAANQADCgYICgAAAA==.Niixxi:BAAANQADCgEIAQAAAA==.',
Nm='Nmbrs:BAAANQADCgQIDAABNQAECgcIBwABAAAAAA==.',
No='Noirah:BAAANQADCgcIBwAAAA==.Noirheffer:BAABNQAECoEgAAMDAAkKSBzACwCcAgADAAkKSBzACwCcAgAPAAEKJQHscwEYAAAAAA==.Nokua:BAAANQAECgQIBQAAAA==.Noodles:BAAANQAECgYIDwAAAA==.',
Nu='Nulannatoo:BAAANQAECgIIAgAAAA==.',
Ny='Nyank:BAAANQAECgIIAgAAAA==.Nyleaf:BAAANQADCgUIBwAAAA==.Nyogen:BAAANQAECggJBgAAAA==.Nyxaraa:BAAANQADCgYIEAAAAA==.',
Oc='Octomore:BAAANQAECgYIEAAAAA==.',
Od='Odysseus:BAABNQAECoEVAAIIAAcKkg6CLACSAQAIAAcKkg6CLACSAQAAAA==.',
Ol='Olgann:BAAANQAECgIIAgAAAA==.Olguita:BAAANQAECgQJCAAAAA==.',
Om='Omez:BAAANQAECgQIBgABNQAECgYIBgABAAAAAA==.Omgowned:BAAANQAECgIIAgABNQAECgYIEAABAAAAAA==.',
On='Onehothealer:BAAANQADCgYIBwAAAA==.',
Oo='Oorua:BAAANQADCggIEgAAAA==.',
Op='Opheliastar:BAABNQAECoEhAAIWAAgK1xejGQA5AgAWAAgK1xejGQA5AgAAAA==.',
Or='Ordovis:BAAANQAECgUIDAAAAA==.Orlucicia:BAAANQADCgcICgAAAA==.Orobas:BAAANQAECggIAgAAAA==.',
Ow='Owltoidz:BAAANQABCgUIAwAAAA==.',
Pa='Pace:BAAANQABCgYICgAAAA==.Pad:BAAANQAECgMIBwAAAA==.Paladerp:BAAANQAECgEIAQAAAA==.Palanym:BAABNQAECoEUAAIOAAcKixPeVgDMAQAOAAcKixPeVgDMAQAAAA==.Palidyne:BAAANQAECgEIAQAAAA==.Pallyown:BAAANQAECgUIBgAAAA==.Papichulo:BAAANQADCgcIDQAAAA==.Parox:BAAANQADCgEIAQAAAA==.',
Ph='Phelement:BAAANQAECgUIDAAAAA==.Phett:BAABNQAECoEaAAMJAAgKdx/LBACQAgAJAAcKECDLBACQAgAaAAMKeRPI3gC/AAAAAA==.Phædrea:BAAANQADCggICAAAAA==.',
Pi='Picklës:BAAANQADCgUIBQABNQAECgYIEgABAAAAAA==.Pimmscup:BAAANQADCgYJEgAAAA==.',
Pr='Praedthy:BAAANQAECgYIDAAAAA==.',
Qo='Qohelet:BAAANQAECgQIBQAAAA==.',
Ra='Raenya:BAAANQAECgIIAgAAAA==.Raikouu:BAAANQAECgYICAAAAA==.Rainydaze:BAAANQADCgYIEAAAAA==.Ramasses:BAAANQADCgYICgAAAA==.Ramcharger:BAAANQAECgEIAQABNQAECggIHAAHAP8ZAA==.Ramoreo:BAAANQAECgQIBAABNQAECgUIFAAYAMsIAA==.Rashun:BAAANQAECgYIDwAAAA==.Raviolee:BAAANQAECgEIAQABNQAECgYIEAABAAAAAA==.',
Re='Reanatilax:BAAANQABCgMJBQABNQAECgUIDQABAAAAAA==.Regnier:BAAANQADCgYIBgAAAA==.Relaeh:BAAANQADCgcJDQAAAA==.Resusitate:BAAANQADCgYJBgAAAA==.Rexxy:BAAANQADCgcICwAAAA==.',
Rh='Rhod:BAAANQADCgcICwABNQAECgMJAwABAAAAAA==.',
Ri='Rikashae:BAAANQADCgYJBgAAAA==.Rissa:BAAANQADCgEIAQAAAA==.Risuku:BAAANQADCgEIAQAAAA==.',
Ro='Roleon:BAAANQADCgYJBwAAAA==.Rollforpi:BAAANQAECgEIAQABNQAECgkJIQACAGwjAA==.Ropebunnyana:BAAANQAECgIJAwABNQAECgcIDgABAAAAAA==.',
Ru='Ruki:BAAANQADCggIGQAAAA==.Rumshwizzle:BAAANQADCgQJBAAAAA==.',
Sa='Saltydk:BAABNQAECoEgAAIbAAkK+CBVEQD7AgAbAAkK+CBVEQD7AgAAAA==.Samiracy:BAAANQAECgYIEAAAAA==.Sataro:BAAANQABCggICgAAAA==.',
Sc='Scappe:BAAANQAECgcIEwAAAA==.',
Se='Seitaer:BAAANQADCgEJAQAAAA==.Senbatorii:BAAANQAECgUIDQAAAA==.Sentrosi:BAAANQAECgEIAQAAAA==.Sethrow:BAAANQAECgYIEAAAAA==.Severa:BAAANQAECgUICwAAAA==.',
Sh='Shadoh:BAAANQAECgIIAgAAAA==.Shamazing:BAAANQADCgEIAQAAAA==.Shamwowsale:BAAANQADCgYIBgAAAA==.Shamwowza:BAAANQAECgcIEwAAAA==.Shantifa:BAAANQADCgYICwAAAA==.Shengari:BAAANQADCgIIAgABNQADCgQIBAABAAAAAA==.Shieldbot:BAAANQADCggIAgAAAA==.Shoshanaa:BAAANQADCgUICwAAAA==.Shotcallà:BAAANQADCgYIBwABNQADCggICAABAAAAAA==.Shuna:BAAANQADCgYICQAAAA==.Shyly:BAAANQAECgIIAgAAAA==.',
Si='Siley:BAABNQAECoEtAAIbAAgKGw/6QQCuAQAbAAgKGw/6QQCuAQAAAA==.',
Sn='Sneakysneak:BAABNQAECoEVAAIcAAgKLxGyBwAGAgAcAAgKLxGyBwAGAgAAAA==.Snüff:BAAANQADCgMIAwAAAA==.',
So='Somavan:BAAANQADCgMIAwABNQAECggIHAAHAP8ZAA==.Somepriest:BAAANQAECgYIEAAAAA==.Sotteria:BAAANQABCgQIBAAAAA==.',
Sp='Spiarmf:BAAANQADCgMIAwAAAA==.Sprockett:BAAANQADCggICAAAAA==.Spycmchaggis:BAAANQAECgEJAQAAAA==.',
St='Stiffkitten:BAAANQADCgEJAQAAAA==.Sturba:BAAANQABCgIIAgAAAA==.',
Su='Sugrace:BAAANQADCgQIBAAAAA==.Sunaerosinda:BAAANQADCgYIBgAAAA==.Sunow:BAAANQADCgUIEQAAAA==.Superdemonzz:BAAANQAECgEIAQABNQAECgkJJAAOAJcSAA==.Superpallyz:BAABNQAECoEkAAQOAAkKlxIiOQBCAgAOAAkKlxIiOQBCAgAPAAEKNRIPSAE2AAADAAEKPgLoYQAhAAAAAA==.Superspidey:BAAANQADCgIIAgAAAA==.',
Sw='Swipeleft:BAABNQAECoEjAAIVAAgKohT0LgAiAgAVAAgKohT0LgAiAgAAAA==.',
Sy='Sylora:BAAANQADCgIIAgAAAA==.',
Ta='Tabarnak:BAAANQAECggIEQABNQAECgkJKQASAN4jAA==.Taiynn:BAAANQADCggIEAAAAA==.Tarogen:BAAANQAECgIIBQAAAA==.Taszherazade:BAAANQADCgEJAQAAAA==.',
Te='Teknique:BAAANQAECgIIAgAAAA==.Tendroni:BAAANQAECgcIEAAAAA==.Tervor:BAAANQADCgYIFgAAAA==.Tessadin:BAAANQADCgEJAQAAAA==.',
Th='Thanamoros:BAAANQAECggIEwABNQAECgkJKgAVACIXAA==.Theredwake:BAAANQAECgYICgAAAA==.Theroach:BAAANQAECgIIAwAAAA==.Thgiewerom:BAAANQABCgYIBwAAAA==.Thwaxi:BAAANQADCgQJCAAAAA==.',
Ti='Timeismoney:BAAANQADCggIDwAAAA==.Tiognaska:BAAANQAECgQICAAAAA==.Tirdain:BAAANQADCgEIAQAAAA==.',
Tl='Tlcbm:BAAANQAECgcIEwAAAA==.',
To='Toeren:BAACNQAFFIEGAAIHAAQKrhL6CABRAQAHAAQKrhL6CABRAQA1AAQKgScAAgcACQoyIVkRADUDAAcACQoyIVkRADUDAAAA.Tokå:BAAANQADCgIIAgAAAA==.Torage:BAAANQAECgEJAQAAAA==.Tormentah:BAAANQADCgIIAgABNQAECggIHQALADgZAA==.Torosentado:BAAANQAECgQIBAAAAA==.',
Tr='Trenity:BAAANQAECgMIBAAAAA==.Triplecanopy:BAAANQADCgUICwAAAA==.Trïsh:BAAANQADCgEIAQABNQAECgUIGQADALQRAA==.',
Ty='Tyinorin:BAAANQADCgYIFgAAAA==.',
['Tä']='Täryn:BAAANQADCgEIAQAAAA==.',
Ub='Ubee:BAAANQAECgUIBwAAAA==.',
Ud='Udderjustice:BAAANQAECgYIEQAAAA==.',
Ug='Uglyelf:BAAANQAECgQJBQAAAA==.',
Ul='Ultimakitty:BAAANQADCggIDAAAAA==.',
Un='Uncertainty:BAAANQADCgUIBQABNQADCggIGQABAAAAAA==.Unchanged:BAAANQAECgIIAgAAAA==.',
Va='Vaeldrin:BAAANQADCgUIBQAAAA==.Vantrix:BAABNQAECoEqAAMVAAkKIheFHAC0AgAVAAkKIheFHAC0AgACAAQK1AdYPwDCAAAAAA==.Varabo:BAAANQAECgMIAwAAAA==.Varolina:BAAANQADCggIHgAAAA==.',
Ve='Velmara:BAAANQABCgMIAwAAAA==.Velthala:BAAANQAECgYICQAAAA==.Velyra:BAAANQAECgIIAwAAAA==.',
Vi='Vitner:BAAANQADCgIIAgABNQAFFAEIAQABAAAAAA==.Vivieneaux:BAAANQABCgMIBAAAAA==.Vixsen:BAAANQABCgcICwAAAA==.',
Vl='Vladdawngard:BAAANQAECggICAAAAA==.',
Vo='Voidmama:BAAANQADCgYIBgAAAA==.Voidryn:BAAANQABCgcIEQAAAA==.Vosaleana:BAAANQAECgQIBwAAAA==.',
Vr='Vraak:BAABNQAECoEhAAMCAAkKbCOcBABdAwACAAkKbCOcBABdAwAVAAIK6SALbgC+AAAAAA==.',
Vu='Vulcus:BAAANQAECgEIAQABNQAECgkJIQACAGwjAA==.',
Vy='Vyndarien:BAAANQABCgcICQAAAA==.',
Wa='Wa:BAAANQAECgMIBwAAAA==.Walimagus:BAAANQADCggICAAAAA==.Wayofthemist:BAAANQABCgIIAgAAAA==.',
Wc='Wcreator:BAAANQAECgIIAgAAAA==.',
Wh='Wheeljack:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.',
Wi='Widowcancer:BAAANQADCgIJAgAAAA==.Will:BAABNQAECoEmAAIPAAkKpCW1BADHAwAPAAkKpCW1BADHAwABNQAECgkJIwALABclAA==.',
Wo='Womdalie:BAAANQADCggIGAAAAA==.',
Wy='Wyckedpally:BAAANQAECgQIBAABNQAECgQIBQABAAAAAA==.',
Xa='Xanthös:BAAANQAFFAIIAgABNQAECgkJIQACAGwjAA==.',
Xe='Xemnastrasza:BAABNQAECoEWAAIEAAgK6BW9DwAiAgAEAAgK6BW9DwAiAgABNQAECgkJKgAVACIXAA==.Xenonne:BAAANQAECgMIBAABNQAECgkJIwAOAOgbAA==.',
Xo='Xolither:BAAANQAECgUIDQAAAA==.',
Yo='Yorgo:BAAANQADCggICAAAAA==.Yourwivesbf:BAAANQADCggICQAAAA==.',
Yu='Yuura:BAAANQAECgMIBAAAAA==.',
Za='Zachdemon:BAABNQAECoEXAAIZAAYKpA4WEQA6AQAZAAYKpA4WEQA6AQAAAA==.Zazoo:BAAANQABCgEIAQAAAA==.',
Ze='Zenyátta:BAAANQAECgMIBQAAAA==.Zephymoo:BAABNQAECoEoAAMdAAkK8BbGCQA5AgAdAAgKrBXGCQA5AgAVAAQKpRRIXwD+AAAAAA==.Zeretha:BAAANQABCgIIAgAAAA==.Zershadowi:BAAANQAECgEIAQAAAA==.Zeyana:BAAANQAECgUICgABNQAECggIIQAHADQaAA==.',
Zh='Zhengshi:BAAANQAECgYIDAAAAA==.',
Zi='Zinsatra:BAAANQADCgEIAQAAAA==.',
Zk='Zkarlyse:BAAANQAECgcIDQAAAA==.',
Zo='Zoose:BAAANQAECgYIEAAAAA==.Zosahe:BAAANQAECgYIBgAAAA==.Zoser:BAAANQAECgUICQAAAA==.',
Zs='Zsófia:BAAANQADCgcIBwAAAA==.',
Zu='Zuckuss:BAAANQADCgYIFgAAAA==.',
Zy='Zymri:BAAANQADCgUICQABNQAECgMIBwABAAAAAA==.',
['Æl']='Ælthan:BAAANQAECgEIAQAAAA==.',
['Ér']='Érubus:BAAANQAECgIIAgAAAA==.',
['Öl']='Ölivê:BAAANQAECgYICwAAAA==.',
['ßu']='ßugs:BAAANQAECgQIBQAAAA==.',
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
