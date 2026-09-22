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

local lookup = {'Unknown-Unknown','Paladin-Protection','Evoker-Devastation','Evoker-Preservation','Hunter-BeastMastery','Paladin-Holy','Paladin-Retribution','Priest-Holy','Monk-Brewmaster','Monk-Windwalker','Shaman-Elemental','Shaman-Restoration','Druid-Balance','Priest-Shadow','DemonHunter-Havoc','DemonHunter-Vengeance','Hunter-Marksmanship','DeathKnight-Unholy','Druid-Restoration','Mage-Arcane','Druid-Feral',}
local provider = {region='US',realm='Alexstrasza',name='US',type='weekly',zone=53,date='2026-09-22',data={Ac='Acbabcaa:BAAANQADCgEJAQAAAA==.Aceon:BAAANQAECgIJBAAAAA==.Aceonarcher:BAAANQAECgQIBQAAAA==.',
Ad='Adfectia:BAAANQAECgUICgAAAA==.',
Ae='Aelianna:BAAANQAECgQIBAAAAA==.Aeryana:BAAANQAECgcJBwAAAA==.Aeth:BAAANQAECgYJCwAAAA==.Aethér:BAAANQAECgQJCwABNQAFFAIIAgABAAAAAA==.',
Ag='Aggroout:BAAANQADCgYIBgABNQAECgkJHQACAEoYAA==.',
Ah='Ahsöka:BAAANQADCgIIAgAAAA==.',
Ai='Aimbel:BAAANQADCgQICQAAAA==.',
Al='Alexstrászá:BAAANQAECgUICQAAAA==.Alynas:BAAANQADCgUIBQAAAA==.Alysona:BAAANQADCgQICAAAAA==.',
Am='Amaarii:BAAANQABCgQJCAAAAA==.Ambeia:BAAANQADCgQJBAAAAA==.Amewow:BAABNQAECoEkAAMDAAkKSSOOAQCbAwADAAkKSSOOAQCbAwAEAAIKVgOfNQBaAAAAAA==.Amoril:BAAANQAECgEJAQAAAA==.',
An='Anarchy:BAAANQAECgUJBwAAAA==.Andraxi:BAAANQADCgYICwAAAA==.Angewomon:BAAANQADCgIIAgAAAA==.Anorakswrath:BAAANQAECgYJCAAAAA==.',
Ap='Apophys:BAAANQADCgYJEgAAAA==.Apoptosis:BAAANQABCgYICQAAAA==.',
Ar='Ariees:BAAANQADCgEIAQAAAA==.Aruneza:BAAANQAECgUJCgAAAA==.',
As='Asherous:BAAANQADCgMJAwABNQAECgIJAgABAAAAAA==.Ashèr:BAAANQAECgIJAgAAAA==.Asunnaa:BAAANQADCgIIAwAAAA==.',
At='Atenchion:BAAANQAECgQIBAAAAA==.Atticuz:BAAANQADCgIIAgAAAA==.',
Au='Aura:BAAANQAECgUJCQAAAA==.Auralion:BAAANQADCgYIBwAAAA==.Autoignition:BAAANQAECgcJEwAAAA==.',
Ba='Bahnkano:BAAANQAECgQICgAAAA==.Bakeddh:BAAANQADCgYJDAAAAA==.Banditz:BAAANQADCgcJDwAAAA==.Bashfury:BAAANQAECgEIAQAAAA==.',
Be='Beefcåkes:BAAANQAECgQJCAAAAA==.Beenah:BAAANQAECgIIBAAAAA==.Beyshunt:BAAANQADCgQIBAAAAA==.',
Bl='Blackøut:BAAANQABCgEIAQAAAA==.Bloodrain:BAAANQAECggIBwAAAA==.Blàst:BAAANQAECgEIAQAAAA==.',
Bo='Boltcutter:BAAANQADCgEJAQAAAA==.Bombmagic:BAAANQADCgMIAwAAAA==.Bonesmccoy:BAAANQABCgEIAQAAAA==.Boomie:BAAANQAECggIBQAAAA==.Boopty:BAAANQAECgEIAQAAAA==.Booptydo:BAAANQADCgcJDgAAAA==.Boris:BAAANQAECgIIAgAAAA==.Bowhawk:BAAANQAECgMIBAAAAA==.',
Bp='Bpwhunter:BAAANQAECgQICgAAAA==.',
Br='Braiin:BAAANQAECgQJBAABNQAFFAIIAgABAAAAAA==.Brazyn:BAAANQADCggIGwAAAA==.Brevarda:BAAANQAECgEIBAAAAA==.Brewcelee:BAAANQAECgUIBgAAAA==.',
Bu='Bubblzmgee:BAAANQAECgUJEgAAAA==.Buscemi:BAAANQADCggIDAAAAA==.Bustofez:BAAANQADCgYICwAAAA==.Buttèrs:BAAANQADCgEIAQAAAA==.',
['Bé']='Béach:BAAANQADCgQIBAAAAA==.',
Ca='Caracalous:BAAANQAECgUJBQAAAA==.Carindria:BAAANQADCggJDgAAAA==.Carninn:BAAANQADCgUIBQAAAA==.Castermcfear:BAAANQABCgIIAwAAAA==.Cattiebrie:BAAANQAECgIIBgAAAA==.Caylavana:BAABNQAECoEXAAIFAAgKtRY0LACDAgAFAAgKtRY0LACDAgAAAA==.',
Ce='Celaylria:BAAANQAECgUICwAAAA==.',
Ch='Charmeleön:BAAANQADCgYIBgAAAA==.Chronicfury:BAAANQABCgIIAwAAAA==.',
Cl='Cloudedjayd:BAAANQADCgcIDgAAAA==.Cloudedmonk:BAAANQADCgUICQAAAA==.Clugorn:BAAANQAECgUJDQAAAA==.Clydè:BAAANQADCgYIDgAAAA==.',
Co='Codyj:BAAANQADCgMIAwAAAA==.Colossus:BAAANQADCggJCwAAAA==.Colourhunt:BAAANQAECgYJDgAAAA==.Condewit:BAAANQADCgUIBQAAAA==.Conoresa:BAAANQADCgMIAwAAAA==.Copedk:BAAANQAECgUJCgAAAA==.Corrode:BAAANQAECgEIAQAAAA==.Cozymav:BAAANQADCgUIBQAAAA==.',
Cp='Cpt:BAAANQADCgEIAQAAAA==.',
Cr='Crinke:BAAANQABCgIIAgAAAA==.',
Cy='Cybeldin:BAAANQAECgQJCAAAAA==.Cyberdemonxd:BAAANQADCgYICAABNQAECgIIAgABAAAAAA==.Cyndyr:BAAANQADCgYIFgAAAA==.',
['Cë']='Cërßerus:BAAANQADCgYIBgAAAA==.',
Da='Daddysparey:BAAANQAECgEIAQAAAA==.Dalarrus:BAAANQAECgIIAwABNQAECggIFwAFALUWAA==.Dalishya:BAAANQADCgQIBAAAAA==.Darek:BAAANQAECgQJBgAAAA==.Darilyns:BAAANQADCgQJBQAAAA==.Darkbiffhunt:BAAANQADCgMIAwAAAA==.Darkrife:BAAANQADCgYJDgAAAA==.Darylinn:BAAANQADCgQJBgAAAA==.Daymann:BAAANQAECgEIAQAAAA==.',
De='Demonrife:BAAANQABCgYIBgABNQADCgYJDgABAAAAAA==.Dernis:BAAANQAECgIIAgABNQAECgcIEAABAAAAAA==.Derplock:BAAANQADCgYIDAAAAA==.Deshaman:BAAANQADCgMIAwABNQAECgkJHgAFAJ4eAA==.Devilbeast:BAAANQAECgQICwAAAA==.Dew:BAAANQABCgQIAwAAAA==.',
Dh='Dhargo:BAAANQAECgUICAABNQAECgEJAQABAAAAAA==.',
Di='Diablosauz:BAAANQADCgQIBAAAAA==.Diaous:BAAANQADCgQIBAAAAA==.Disgruntled:BAAANQAECgYJEAAAAA==.',
Do='Docbrown:BAAANQADCgEIAQAAAA==.Dontormentaa:BAAANQAECgIIAgABNQAECgYJEgABAAAAAA==.Dontormentaj:BAAANQAECgYJEgAAAA==.Doomzday:BAAANQADCgYIDQAAAA==.',
Dr='Dracthra:BAAANQAECgQJCAAAAA==.Drakk:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Dreamlesnite:BAAANQABCggIDwAAAA==.Dreidelman:BAAANQAECgEIAQAAAA==.',
Du='Dugdimadome:BAAANQAECgEIAQAAAA==.',
Dy='Dylora:BAAANQAECgQJBgAAAA==.',
Ea='Ealdoras:BAAANQADCggIDgAAAA==.',
Eg='Egg:BAABNQAECoEZAAMGAAkKzh4ACQBRAwAGAAkKzh4ACQBRAwAHAAEKqAy7KQEvAAABNQAFFAYIEQAIAMEUAA==.',
El='Elassha:BAAANQADCggICwAAAA==.Elatio:BAAANQAECgQICgAAAA==.Elfairea:BAAANQADCgEIAQAAAA==.Elmortal:BAAANQAECgQJBgAAAA==.Elystaria:BAAANQAECgIIBAAAAA==.',
Em='Emmâ:BAAANQABCgEIAgAAAA==.Emokins:BAEANQAECgUJCgAAAA==.',
En='Enyos:BAAANQABCgEJAQAAAA==.',
Ep='Epicnakedman:BAAANQAECggICAAAAA==.',
Er='Erubus:BAABNQAECoEdAAMJAAgKOCNfAwAYAwAJAAgKOCNfAwAYAwAKAAEK4RPlQwBAAAAAAA==.Erubuss:BAAANQADCgYIBgAAAA==.Eryss:BAAANQAECgIIBAAAAA==.',
Ex='Excalibúr:BAAANQADCgcIBwAAAA==.Existance:BAAANQABCgEIAwAAAA==.',
Ey='Eyeofstorm:BAAANQADCggIBwAAAA==.',
Fa='Faithfulone:BAAANQAECgIIBAAAAA==.Falcone:BAAANQABCgEIAgABNQAECgEIAQABAAAAAA==.Farfidnoogan:BAAANQABCgQIBAAAAA==.Fatercul:BAAANQADCgEIAQAAAA==.',
Fd='Fdk:BAAANQAECgcIBAAAAA==.',
Fe='Fellariene:BAAANQADCgUIBQAAAA==.',
Fo='Forilla:BAAANQAECgQIBQAAAA==.Fortissimo:BAAANQADCgUIBwAAAA==.',
['Fà']='Fàmous:BAAANQAECgQIBgAAAA==.',
Ga='Galabris:BAAANQAECgUJCQAAAA==.Gasilbench:BAAANQAECgEIAQAAAA==.',
Gh='Ghostboydk:BAAANQADCgYIBgABNQAECgUIBgABAAAAAA==.Ghoulmania:BAAANQAECggIBgAAAA==.',
Gi='Gimligrimes:BAAANQADCgYIBgAAAA==.Gington:BAAANQADCgYJEgAAAA==.Gitchusum:BAAANQAECgYIBgAAAA==.',
Gl='Glaivenez:BAAANQAECgUJBgAAAA==.Gleenna:BAAANQADCgUJBQAAAA==.Glorify:BAAANQADCggICAABNQAECgQIBwABAAAAAA==.',
Go='Goose:BAAANQAECgUIDAAAAA==.Gormladin:BAAANQADCgUIDAAAAA==.Gormstorm:BAAANQAECgIIAgAAAA==.',
Gr='Greenbahamut:BAAANQADCgEIAQAAAA==.Grouchy:BAAANQADCgQIBgABNQAECgcIBAABAAAAAA==.',
Gw='Gwynythe:BAAANQADCgEJAQAAAA==.',
Ha='Hadriac:BAAANQADCgQJBAAAAA==.Halfang:BAAANQADCggIGQAAAA==.Hanta:BAAANQAECgYJCgAAAA==.',
Hi='Hildegarde:BAAANQABCgEIAQABNQADCgcIFgABAAAAAA==.Hitpoints:BAAANQADCgYIDAABNQAECgQJBwABAAAAAA==.',
Ho='Holyfrog:BAAANQAECgQIBQAAAA==.Holyhope:BAAANQAECgYIEAABNQAECggICAABAAAAAA==.Holylightz:BAAANQAECgMIAwAAAA==.Holymana:BAAANQAECgQICAAAAA==.Honeybunns:BAAANQADCgUIBQAAAA==.Hosstx:BAAANQADCgEIAQAAAA==.Hotandready:BAAANQAECgUICAAAAA==.',
Hu='Huffingpaint:BAAANQADCgYIDgABNQADCgcIFgABAAAAAA==.Hukhokhan:BAAANQADCggIDwAAAA==.Hutzil:BAAANQAECgYJDgAAAA==.Hutzilla:BAAANQABCgYICAAAAA==.',
Ia='Iakopa:BAABNQAECoEcAAMLAAkK4BrbMABEAgALAAcK0hrbMABEAgAMAAUKNgdyfgAKAQABNQAECgkJJAANAHMWAA==.',
Il='Illidianna:BAAANQAECgUICgAAAA==.',
Im='Imfiredup:BAAANQAECggIBQAAAA==.Imitlol:BAABNQAECoEVAAIHAAcKfSN2JwDDAgAHAAcKfSN2JwDDAgAAAA==.',
In='Inception:BAAANQADCgQIBAAAAA==.Ingress:BAAANQADCgYJBgAAAA==.',
It='Itchynyple:BAAANQADCgYJDgAAAA==.Ithowen:BAAANQABCgYIBwAAAA==.',
Ja='Jacques:BAAANQADCggIEAAAAA==.Jaetherion:BAAANQAECgQJBQAAAA==.Jakes:BAAANQADCgYJDAAAAA==.Jayhawk:BAAANQAECgEIAQAAAA==.',
Ji='Jimothy:BAAANQADCgcIEwABNQAECgkJHQALANojAA==.Jinx:BAAANQADCggIGwAAAA==.',
Jo='Johaliz:BAAANQADCgEIAQAAAA==.Johnnypopoff:BAAANQADCgYIBgAAAA==.Jojohunts:BAAANQAECgEIAQAAAA==.Jonesy:BAAANQADCgIIAgABNQAECggIHAAFAN0TAA==.',
Ju='Junyubych:BAAANQADCgYICgABNQAECgEJAQABAAAAAA==.',
['Jà']='Jàccuse:BAAANQADCgUIDAABNQAECgQJCAABAAAAAA==.Jàrnsaxa:BAAANQADCggIHgAAAA==.',
['Jò']='Jòhnnypopo:BAAANQAECgUJCgAAAA==.',
Ka='Kagé:BAAANQADCgEIAQAAAA==.Kaisra:BAAANQAECgMJAwAAAA==.Kasumeli:BAAANQAECgYIDAAAAA==.Kathelas:BAAANQADCgYIBgAAAA==.Kayd:BAAANQADCgYIBgAAAA==.Kayhan:BAAANQADCgQICgAAAA==.Kaylaiis:BAAANQADCggICAAAAA==.Kayos:BAAANQADCgYJFgAAAA==.Kazurend:BAABNQAECoEdAAMOAAkK4h+RBwA3AwAOAAkK4h+RBwA3AwAIAAEKSBcrogBQAAAAAA==.',
Ke='Keyaielenst:BAAANQADCgUIBQAAAA==.',
Kh='Khirina:BAAANQAECgYIBwAAAA==.Khristina:BAAANQAECgQJCAAAAA==.Khrogh:BAAANQAECgEJAQAAAA==.',
Ki='Kippo:BAEANQAECgcICAAAAA==.Kisarrah:BAAANQABCgMIBAAAAA==.',
Kn='Knarn:BAAANQAECgUICgAAAA==.',
Ko='Koralie:BAACNQAFFIEJAAIFAAUKKRSaAgC5AQAFAAUKKRSaAgC5AQA1AAQKgR0AAgUACQqkJO4FAIoDAAUACQqkJO4FAIoDAAAA.Korrum:BAAANQABCgIIBAAAAA==.',
Kr='Krillaxx:BAAANQAECgQIBAAAAA==.',
Kt='Ktullanux:BAAANQAECgIIAgAAAA==.',
Ky='Kyliekat:BAAANQAECgQJCAAAAA==.',
La='Lanceelot:BAAANQADCgYJDAAAAA==.Lanel:BAAANQAECgUJCgAAAA==.Lathelous:BAAANQAECgUICgAAAA==.Laulten:BAAANQABCgQIBQAAAA==.',
Le='Leintheir:BAAANQAECgUIBQAAAA==.',
Li='Lideina:BAAANQADCgMIAwAAAA==.Lieahi:BAAANQAECgIIAQAAAA==.Liebesleid:BAAANQADCgYIBgABNQADCgcIFgABAAAAAA==.Lightt:BAABNQAECoEdAAIIAAgKKA+oPgDuAQAIAAgKKA+oPgDuAQAAAA==.Liightt:BAAANQAECgQICwAAAA==.Lilcozz:BAAANQADCgYIFgAAAA==.Lilpyroblast:BAAANQAECgUICgAAAA==.Liriope:BAAANQADCgYICwAAAA==.Lizbethstar:BAAANQADCggIDAAAAA==.',
Ll='Llaerwyn:BAAANQADCgUJBwAAAA==.Llars:BAAANQAECgUICgAAAA==.',
Lo='Loryanna:BAAANQADCgYIEwAAAA==.Louie:BAAANQADCggIEQAAAA==.Lovehandless:BAAANQADCgIIAgAAAA==.',
Lu='Lumenne:BAAANQADCgIIAgAAAA==.Luxore:BAAANQAECgcIDAABNQAECgkJJAANAHMWAA==.',
Ly='Lyandrea:BAAANQADCggIFQAAAA==.Lyfebane:BAAANQADCgUJBQAAAA==.Lynaomira:BAAANQADCgMIAwAAAA==.',
['Lõ']='Lõrs:BAAANQADCgMIBQAAAA==.',
['Lø']='Lørs:BAAANQAECgQJCAAAAA==.',
Ma='Main:BAAANQAECgYJEwAAAA==.Majrmiståke:BAAANQAECgcICQABNQAECgkJJAAGAJcSAA==.Malakir:BAAANQADCgUJBQAAAA==.Malaxxus:BAAANQADCgEIAQAAAA==.Malendorei:BAAANQADCggJHAAAAA==.Malicemech:BAAANQADCgcIHAAAAA==.Maliceone:BAAANQADCggJHAAAAA==.Malicepaly:BAAANQADCgYIDAAAAA==.Mallucavian:BAAANQAECgIIBAAAAA==.Mamadp:BAAANQAECgMIBQAAAA==.Manaholy:BAAANQADCggICAAAAA==.Manek:BAABNQAECoEcAAIFAAgK3ROoOwBHAgAFAAgK3ROoOwBHAgAAAA==.Marraxa:BAAANQAECgMIBQAAAA==.Maräjade:BAAANQABCgYJBwAAAA==.Max:BAAANQAECgYJCwAAAA==.',
Me='Melevil:BAAANQAECgIJAgAAAA==.Melinoe:BAAANQADCgIIAgAAAA==.Merlise:BAAANQADCgcICgAAAA==.Metalgreymon:BAAANQADCgIIAgAAAA==.',
Mi='Milenad:BAAANQAECgUIBwAAAA==.Milho:BAAANQADCgYIBgABNQAFFAIIBQAPAJUfAA==.Mishosuki:BAAANQAECgEJAQAAAA==.Misscleo:BAAANQAECgUICgAAAA==.',
Mn='Mnesarte:BAAANQADCgUIBQAAAA==.',
Mo='Mobmagnet:BAABNQAECoEpAAIQAAkKeRgCBACNAgAQAAkKeRgCBACNAgAAAA==.Moltres:BAEANQAECggIBQAAAA==.Moonkist:BAAANQAECgIIBAAAAA==.Moose:BAAANQAECgcIDwAAAA==.Mordrandian:BAAANQADCgYIFgAAAA==.Morroe:BAAANQADCgYIEQAAAA==.',
Mu='Muffintop:BAAANQADCgQIBAAAAA==.',
Na='Nadless:BAAANQADCgYIDAAAAA==.Naeliria:BAAANQADCggICAAAAA==.Namuss:BAAANQADCgEIAQAAAA==.Navariis:BAAANQADCgQJDQAAAA==.',
Ne='Necropanzer:BAAANQADCgcIBwAAAA==.Nelrehim:BAAANQAECgIIAgAAAA==.',
Ni='Niall:BAAANQAECgEJAQABNQAECggIFwAFALUWAA==.Niandilan:BAAANQADCgYICgAAAA==.Niixxi:BAAANQADCgEIAQAAAA==.',
Nm='Nmbrs:BAAANQADCgQICAABNQAECgcIBAABAAAAAA==.',
No='Noirah:BAAANQADCgcIBwAAAA==.Noirheffer:BAABNQAECoEdAAMCAAkKShiNDABaAgACAAkKShiNDABaAgAHAAEKJQExQAEZAAAAAA==.Nokua:BAAANQAECgEJAQAAAA==.Noodles:BAAANQAECgQICQAAAA==.',
Nu='Nulannatoo:BAAANQAECgEIAQAAAA==.',
Ny='Nyank:BAAANQAECgIIAgAAAA==.Nyleaf:BAAANQADCgUIBwAAAA==.Nyogen:BAAANQAECggJBgAAAA==.Nyxaraa:BAAANQADCgYIEAAAAA==.',
Oc='Octomore:BAAANQAECgUICgAAAA==.',
Od='Odysseus:BAABNQAECoEVAAIRAAcKkg4TJQCoAQARAAcKkg4TJQCoAQAAAA==.',
Ol='Olguita:BAAANQAECgQJCAAAAA==.',
Om='Omez:BAAANQAECgIJAgABNQAECgYJEwABAAAAAA==.Omgowned:BAAANQAECgIIAgABNQAECgUJCgABAAAAAA==.',
On='Onehothealer:BAAANQADCgYIBwAAAA==.',
Oo='Oorua:BAAANQADCgYJCgAAAA==.',
Op='Opheliastar:BAABNQAECoEZAAIOAAcKNBZJGwD6AQAOAAcKNBZJGwD6AQAAAA==.',
Or='Ordovis:BAAANQAECgQJCAAAAA==.Orlucicia:BAAANQADCgQIBAAAAA==.',
Pa='Pace:BAAANQABCgYICgAAAA==.Pad:BAAANQAECgIIBAAAAA==.Paladerp:BAAANQADCggJIwAAAA==.Palanym:BAAANQAECgUJCQAAAA==.Palidyne:BAAANQAECgEIAQAAAA==.Pallyown:BAAANQAECgUIBQAAAA==.Papichulo:BAAANQADCgcIDQAAAA==.Parox:BAAANQABCgMIAwAAAA==.',
Ph='Phelement:BAAANQAECgQIBwAAAA==.Phett:BAAANQAECgYIDgAAAA==.',
Pi='Picklës:BAAANQADCgUIBQABNQAECgUIDAABAAAAAA==.Pimmscup:BAAANQADCgYJEgAAAA==.',
Pr='Praedthy:BAAANQAECgUIBgAAAA==.',
Qo='Qohelet:BAAANQAECgQIBQAAAA==.',
Ra='Raenya:BAAANQAECgEIAQAAAA==.Raikouu:BAAANQAECgIJAgAAAA==.Rainydaze:BAAANQADCgYICgAAAA==.Ramasses:BAAANQADCgYICgAAAA==.Ramcharger:BAAANQAECgEJAQABNQAECggIFwAFALUWAA==.Ramoreo:BAAANQAECgQIBAABNQAECgUICgABAAAAAA==.Rashun:BAAANQAECgUICQAAAA==.Raviolee:BAAANQAECgEIAQABNQAECgUJCgABAAAAAA==.',
Re='Reanatilax:BAAANQABCgMJBgABNQAECgQJCAABAAAAAA==.Regnier:BAAANQADCgYJBgAAAA==.Relaeh:BAAANQADCgcJDQAAAA==.Resusitate:BAAANQADCgYJBgAAAA==.Rexxy:BAAANQADCgcICwAAAA==.',
Rh='Rhod:BAAANQADCgcICwABNQAECgMJAwABAAAAAA==.',
Ri='Rikashae:BAAANQADCgYJBgAAAA==.Rissa:BAAANQADCgEIAQAAAA==.Risuku:BAAANQADCgEIAQAAAA==.',
Ro='Roleon:BAAANQADCgYJBwAAAA==.Ropebunnyana:BAAANQAECgIJAwABNQAECgcJBwABAAAAAA==.',
Ru='Ruki:BAAANQADCgcIFgAAAA==.Rumshwizzle:BAAANQADCgQJBAAAAA==.',
Sa='Saltydk:BAABNQAECoEaAAISAAkKKCA1DAAoAwASAAkKKCA1DAAoAwAAAA==.Samiracy:BAAANQAECgUJCgAAAA==.Sataro:BAAANQABCggICwAAAA==.',
Sc='Scappe:BAAANQAECgcIEQAAAA==.',
Se='Seitaer:BAAANQADCgEJAQAAAA==.Senbatorii:BAAANQAECgQJCAAAAA==.Sentrosi:BAAANQAECgEIAQAAAA==.Sethrow:BAAANQAECgUJCgAAAA==.Severa:BAAANQAECgQJCgAAAA==.',
Sh='Shadoh:BAAANQAECgIIAgAAAA==.Shamazing:BAAANQADCgEIAQAAAA==.Shamwowza:BAAANQAECgUJCQAAAA==.Shantifa:BAAANQADCgYICwAAAA==.Shengari:BAAANQADCgIIAgABNQADCgQIBAABAAAAAA==.Shoshanaa:BAAANQADCgUIBwAAAA==.Shotcallà:BAAANQADCgYIBwABNQADCggICAABAAAAAA==.Shuna:BAAANQADCgYICQAAAA==.Shyly:BAAANQAECgIIAgAAAA==.',
Si='Siley:BAABNQAECoEjAAISAAgKKA0nMQDoAQASAAgKKA0nMQDoAQAAAA==.',
Sn='Sneakysneak:BAAANQAECggIDwAAAA==.Snüff:BAAANQADCgMIAwAAAA==.',
So='Somepriest:BAAANQAECgUICgAAAA==.Sotteria:BAAANQABCgEIAgAAAA==.',
Sp='Spiarmf:BAAANQADCgMIAwAAAA==.Sprockett:BAAANQADCggICAAAAA==.Spycmchaggis:BAAANQAECgEJAQAAAA==.',
St='Stiffkitten:BAAANQADCgEJAQAAAA==.Sturba:BAAANQABCgIIAgAAAA==.',
Su='Sugrace:BAAANQADCgQIBAAAAA==.Sunow:BAAANQADCgUIDAAAAA==.Superdemonzz:BAAANQAECgEIAQABNQAECgkJJAAGAJcSAA==.Superpallyz:BAABNQAECoEkAAQGAAkKlxLBLABQAgAGAAkKlxLBLABQAgAHAAEKNRJ7EwE9AAACAAEKPgKFUgAkAAAAAA==.Superspidey:BAAANQADCgIIAgAAAA==.',
Sw='Swipeleft:BAABNQAECoEbAAINAAgKAxFILgD1AQANAAgKAxFILgD1AQAAAA==.',
Sy='Sylora:BAAANQADCgIIAgAAAA==.Sylveslem:BAAANQABCgIIAgAAAA==.',
Ta='Tabarnak:BAAANQAECggJDgAAAA==.Taiynn:BAAANQADCggICAAAAA==.Talianna:BAAANQABCgEIAQAAAA==.Tarogen:BAAANQAECgIIAwAAAA==.Taszherazade:BAAANQADCgEJAQAAAA==.',
Te='Teknique:BAAANQAECgIIAgAAAA==.Tendroni:BAAANQAECgYJCQAAAA==.Tervor:BAAANQADCgYIEAAAAA==.Tessadin:BAAANQADCgEJAQAAAA==.',
Th='Thanamoros:BAAANQAECggJDAABNQAECgkJJAANAHMWAA==.Theredwake:BAAANQAECgYJBgAAAA==.Theroach:BAAANQAECgIJAgAAAA==.Thgiewerom:BAAANQABCgYIBwAAAA==.Thwaxi:BAAANQADCgQJCAAAAA==.',
Ti='Timeismoney:BAAANQADCggICAAAAA==.Tiognaska:BAAANQAECgQIBQAAAA==.Tirdain:BAAANQADCgEJAQAAAA==.',
Tl='Tlcbm:BAAANQAECgcIDQAAAA==.',
To='Toeren:BAABNQAECoEeAAIFAAkKnh4YEgATAwAFAAkKnh4YEgATAwAAAA==.Tokå:BAAANQADCgIIAgAAAA==.Torage:BAAANQAECgEJAQAAAA==.Tormentah:BAAANQADCgIIAgABNQAECgYJEgABAAAAAA==.Torosentado:BAAANQADCgcIBwAAAA==.',
Tr='Trenity:BAAANQAECgMIBAAAAA==.Triplecanopy:BAAANQADCgUICwAAAA==.',
Ty='Tyinorin:BAAANQADCgYIFgAAAA==.',
['Tä']='Täryn:BAAANQADCgEIAQAAAA==.',
Ub='Ubee:BAAANQAECgEIAgAAAA==.',
Ud='Udderjustice:BAAANQAECgUICQAAAA==.',
Ug='Uglyelf:BAAANQAECgQJBQAAAA==.',
Ul='Ultimakitty:BAAANQADCggIDAAAAA==.',
Un='Uncertainty:BAAANQADCgUIBQABNQADCgcIFgABAAAAAA==.Unchanged:BAAANQAECgIIAgAAAA==.',
Va='Vaeldrin:BAAANQADCgUIBQAAAA==.Vantrix:BAABNQAECoEkAAMNAAkKcxafFwC9AgANAAkKcxafFwC9AgATAAQK1Ae/NADJAAAAAA==.Varabo:BAAANQAECgEJAQAAAA==.Varolina:BAAANQADCggJFgAAAA==.',
Ve='Velmara:BAAANQABCgMIAwAAAA==.Velthala:BAAANQAECgMIAwAAAA==.Velyra:BAAANQAECgIIAwAAAA==.',
Vi='Vitner:BAAANQADCgIJAgABNQAECggIDwABAAAAAA==.Vivieneaux:BAAANQABCgMIBQAAAA==.',
Vl='Vladdawngard:BAAANQAECggICAAAAA==.',
Vo='Voidryn:BAAANQABCgcIEQAAAA==.Vosaleana:BAAANQAECgEIAQAAAA==.',
Vr='Vraak:BAABNQAECoEdAAMTAAkKbCMGAwBwAwATAAkKbCMGAwBwAwANAAIKaBxuaACbAAABNQAFFAIIAgABAAAAAA==.',
Vu='Vulcus:BAAANQABCgYIBgABNQAFFAIIAgABAAAAAA==.',
Vy='Vyndarien:BAAANQABCgcICgAAAA==.',
Wa='Wa:BAAANQAECgIIBAAAAA==.Wayofthemist:BAAANQABCgIIAgAAAA==.',
Wc='Wcreator:BAAANQAECgIIAgAAAA==.',
Wi='Widowcancer:BAAANQADCgIJAgAAAA==.Will:BAABNQAECoEjAAIHAAkKViUDAwDWAwAHAAkKViUDAwDWAwABNQAECgkJGwAUAOgkAA==.',
Wo='Womdalie:BAAANQADCgYJEwAAAA==.',
Wy='Wyckedpally:BAAANQADCggJGAABNQAECgEJAQABAAAAAA==.',
Xa='Xanthös:BAAANQAFFAIIAgAAAA==.',
Xe='Xemnastrasza:BAABNQAECoEWAAIDAAgK6BXiDABFAgADAAgK6BXiDABFAgABNQAECgkJJAANAHMWAA==.Xenonne:BAAANQAECgMIBAABNQAECggIHAAGAHkaAA==.',
Xo='Xolither:BAAANQAECgQJCAAAAA==.',
Yo='Yorgo:BAAANQADCggICAAAAA==.Yourwivesbf:BAAANQADCggICQAAAA==.',
Yu='Yuura:BAAANQAECgMIBAAAAA==.',
Za='Zachdemon:BAAANQAECgYJEQAAAA==.Zazoo:BAAANQABCgEIAQAAAA==.',
Ze='Zenyátta:BAAANQAECgEJAgAAAA==.Zephymoo:BAABNQAECoEfAAMVAAgKbxTJCQD0AQAVAAcKUBTJCQD0AQANAAQKshEbVgD3AAAAAA==.Zeretha:BAAANQABCgIIAgAAAA==.Zershadowi:BAAANQADCgcIDQAAAA==.Zeyana:BAAANQAECgUJCAABNQAECggJGgAFADQaAA==.',
Zh='Zhengshi:BAAANQAECgQJBgAAAA==.',
Zi='Zinsatra:BAAANQADCgEIAQAAAA==.',
Zk='Zkarlyse:BAAANQAECgcIDQAAAA==.',
Zo='Zoose:BAAANQAECgUJCgAAAA==.Zoser:BAAANQAECgQJBAAAAA==.',
Zs='Zsófia:BAAANQADCgcIBwAAAA==.',
Zu='Zuckuss:BAAANQADCgYIFgAAAA==.',
Zy='Zymri:BAAANQADCgUICQABNQAECgIIBAABAAAAAA==.',
['Æl']='Ælthan:BAAANQAECgEIAQAAAA==.',
['Ér']='Érubus:BAAANQAECgIIAgAAAA==.',
['Öl']='Ölivê:BAAANQAECgUJBQAAAA==.',
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
