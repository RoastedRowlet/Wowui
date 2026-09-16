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

local lookup = {'Druid-Restoration','Paladin-Protection','Evoker-Devastation','Evoker-Preservation','Unknown-Unknown','Paladin-Holy','Paladin-Retribution','Priest-Holy','Druid-Balance','Priest-Shadow','Hunter-BeastMastery','DemonHunter-Vengeance','DeathKnight-Unholy','Monk-Windwalker',}
local provider = {region='US',realm='Alexstrasza',name='US',type='weekly',zone=53,date='2026-09-15',data={Ac='Acbabcaa:BAAANQADCgEIAQAAAA==.Aceon:BAAANQAECgEIAQAAAA==.Aceonarcher:BAAANQAECgQIBQAAAA==.',
Ad='Adfectia:BAAANQAECgQIBQAAAA==.',
Ae='Aelianna:BAAANQADCgcIEQAAAA==.Aeryana:BAAANQADCgYIBgAAAA==.Aeth:BAAANQAECgYICwAAAA==.Aethér:BAAANQAECgQICAABNQAECgkJGQABAGwjAA==.',
Ag='Aggroout:BAAANQADCgYIBgABNQAECgkJGwACABIWAA==.',
Ah='Ahsöka:BAAANQADCgIIAgAAAA==.',
Ai='Aimbel:BAAANQADCgMIBQAAAA==.',
Al='Alexstrászá:BAAANQAECgMIBQAAAA==.Alynas:BAAANQADCgUIBQAAAA==.Alysona:BAAANQADCgQICAAAAA==.',
Am='Amaarii:BAAANQABCgMIBwAAAA==.Amewow:BAABNQAECoEeAAMDAAkJMyEbAgBzAwADAAkJMyEbAgBzAwAEAAIJVgPTLQBdAAAAAA==.',
An='Anarchy:BAAANQAECgIIAgAAAA==.Andraxi:BAAANQADCgYICwAAAA==.Angewomon:BAAANQADCgIIAgAAAA==.Anorakswrath:BAAANQAECgIIAgAAAA==.',
Ap='Apophys:BAAANQADCgYIDAAAAA==.Apoptosis:BAAANQABCgYICAAAAA==.',
Ar='Ariees:BAAANQADCgEIAQAAAA==.Aruneza:BAAANQAECgQIBQAAAA==.',
As='Ashèr:BAAANQAECgEIAQAAAA==.Asunnaa:BAAANQADCgIIAwAAAA==.',
At='Atenchion:BAAANQAECgQIBAAAAA==.Atticuz:BAAANQADCgIIAgAAAA==.',
Au='Aura:BAAANQAECgQIBAAAAA==.Auralion:BAAANQADCgEIAQAAAA==.Autoignition:BAAANQAECgUIDAAAAA==.',
Ba='Bahnkano:BAAANQAECgQIBgAAAA==.Bakeddh:BAAANQADCgYIDAAAAA==.Banditz:BAAANQADCgcICwAAAA==.Bashfury:BAAANQAECgEIAQAAAA==.',
Be='Beefcåkes:BAAANQAECgMIBAAAAA==.Beenah:BAAANQAECgIIAgAAAA==.',
Bl='Bloodrain:BAAANQAECggIBwAAAA==.Blàst:BAAANQAECgEIAQAAAA==.',
Bo='Bombmagic:BAAANQADCgMIAwAAAA==.Boomie:BAAANQAECggIBQAAAA==.Boopty:BAAANQAECgEIAQAAAA==.Booptydo:BAAANQADCgcICQAAAA==.Boris:BAAANQAECgIIAgAAAA==.Bowhawk:BAAANQAECgEIAQAAAA==.',
Bp='Bpwhunter:BAAANQAECgQICgAAAA==.',
Br='Braiin:BAAANQADCgcIBwABNQAECgkJGQABAGwjAA==.Brazyn:BAAANQADCggIEwAAAA==.Brevarda:BAAANQAECgEIAwAAAA==.',
Bu='Bubblzmgee:BAAANQAECgQIDQAAAA==.Buscemi:BAAANQADCggIDAAAAA==.Bustofez:BAAANQADCgYICwAAAA==.Buttèrs:BAAANQADCgEIAQAAAA==.',
['Bé']='Béach:BAAANQADCgIIAgAAAA==.',
Ca='Caracalous:BAAANQAECgUIBQAAAA==.Carindria:BAAANQADCgYIBgAAAA==.Carninn:BAAANQADCgUIBQAAAA==.Castermcfear:BAAANQABCgIIAgAAAA==.Cattiebrie:BAAANQAECgEIBAAAAA==.Caylavana:BAAANQAECgcIDQAAAA==.',
Ce='Celaylria:BAAANQAECgUICQAAAA==.',
Ch='Charmeleön:BAAANQADCgYIBgAAAA==.Chronicfury:BAAANQABCgIIAgAAAA==.',
Cl='Cloudedjayd:BAAANQADCgcIDgAAAA==.Cloudedmonk:BAAANQADCgQIBAAAAA==.Clugorn:BAAANQAECgQICAAAAA==.Clydè:BAAANQADCgYIDgAAAA==.',
Co='Codyj:BAAANQADCgMIAwAAAA==.Colossus:BAAANQADCgUIBQAAAA==.Colourhunt:BAAANQAECgQICAAAAA==.Condewit:BAAANQADCgUIBQAAAA==.Conoresa:BAAANQADCgMIAwAAAA==.Copedk:BAAANQAECgQIBQAAAA==.Corrode:BAAANQAECgEIAQAAAA==.Cozymav:BAAANQADCgUIBQAAAA==.',
Cp='Cpt:BAAANQADCgEIAQAAAA==.',
Cr='Crinke:BAAANQABCgIIAgAAAA==.',
Cy='Cybeldin:BAAANQAECgQIBAAAAA==.Cyberdemonxd:BAAANQADCgYICAABNQAECgEIAQAFAAAAAA==.Cyndyr:BAAANQADCgUIEAAAAA==.',
['Cë']='Cërßerus:BAAANQADCgYIBgAAAA==.',
Da='Daddysparey:BAAANQADCgYIEQAAAA==.Darek:BAAANQAECgIIAgAAAA==.Darilyns:BAAANQADCgQIBQAAAA==.Darkbiffhunt:BAAANQADCgMIAwAAAA==.Darkrife:BAAANQADCgYIDAAAAA==.Darylinn:BAAANQADCgQIBAAAAA==.Daymann:BAAANQADCgIIAgAAAA==.',
De='Demonrife:BAAANQABCgYIBgABNQADCgYIDAAFAAAAAA==.Dernis:BAAANQAECgIIAgABNQAECgYICQAFAAAAAA==.Derplock:BAAANQADCgYIBgAAAA==.Deshaman:BAAANQADCgMIAwABNQAECggIEQAFAAAAAA==.Devilbeast:BAAANQAECgQIBwAAAA==.Dew:BAAANQABCgQIAwAAAA==.',
Dh='Dhargo:BAAANQAECgMIAwAAAA==.',
Di='Diablosauz:BAAANQADCgQIBAAAAA==.Disgruntled:BAAANQAECgYICgAAAA==.',
Do='Dontormentaa:BAAANQAECgIIAgABNQAECgUICwAFAAAAAA==.Dontormentaj:BAAANQAECgUICwAAAA==.Doomzday:BAAANQADCgYIDQAAAA==.',
Dr='Dracthra:BAAANQAECgMIBAAAAA==.Drakk:BAAANQADCgUIBQABNQAECgEIAQAFAAAAAA==.Dreamlesnite:BAAANQABCgUIBgAAAA==.Dreidelman:BAAANQAECgEIAQAAAA==.',
Du='Dugdimadome:BAAANQAECgEIAQAAAA==.',
Dy='Dylora:BAAANQAECgMIBAAAAA==.',
Ea='Ealdoras:BAAANQADCggIDgAAAA==.',
Eg='Egg:BAABNQAECoEZAAMGAAkJzh6hBQBjAwAGAAkJzh6hBQBjAwAHAAEJuAyP8QAwAAABNQAFFAYIDAAIAN8QAA==.',
El='Elassha:BAAANQADCggICwAAAA==.Elatio:BAAANQAECgQICAAAAA==.Elfairea:BAAANQADCgEIAQAAAA==.Elmortal:BAAANQAECgMIAwAAAA==.Elystaria:BAAANQAECgIIAgAAAA==.',
Em='Emokins:BAEANQAECgQIBQAAAA==.',
En='Enyos:BAAANQABCgEIAQAAAA==.',
Ep='Epicnakedman:BAAANQAECggICAAAAA==.',
Er='Erubus:BAAANQAECgcIEwAAAA==.Eryss:BAAANQAECgIIAgAAAA==.',
Ex='Excalibúr:BAAANQADCgcIBwAAAA==.',
Ey='Eyeofstorm:BAAANQADCggIBwAAAA==.',
Fa='Faithfulone:BAAANQAECgIIAgAAAA==.Fatercul:BAAANQADCgEIAQAAAA==.',
Fd='Fdk:BAAANQAECgcIAgAAAA==.',
Fe='Fellariene:BAAANQADCgUIBQAAAA==.',
Fo='Forilla:BAAANQAECgQIBQAAAA==.Fortissimo:BAAANQADCgUIBwAAAA==.',
['Fà']='Fàmous:BAAANQAECgEIAgAAAA==.',
Ga='Galabris:BAAANQAECgQIBAAAAA==.Gasilbench:BAAANQAECgEIAQAAAA==.',
Gh='Ghostboydk:BAAANQADCgYIBgABNQAECgQICAAFAAAAAA==.',
Gi='Gimligrimes:BAAANQADCgYIBgAAAA==.Gington:BAAANQADCgUIDAAAAA==.Gitchusum:BAAANQADCgMIAwAAAA==.',
Gl='Glaivenez:BAAANQAECgEIAgAAAA==.Gleenna:BAAANQADCgUIBQAAAA==.',
Go='Goose:BAAANQAECgUIBwAAAA==.Gormladin:BAAANQADCgQIBwAAAA==.Gormstorm:BAAANQAECgIIAgAAAA==.',
Gr='Greenbahamut:BAAANQADCgEIAQAAAA==.Grouchy:BAAANQADCgQIBgABNQAECgcIAgAFAAAAAA==.',
Ha='Halfang:BAAANQADCggIEgAAAA==.Hanta:BAAANQAECgYICgAAAA==.',
Hi='Hitpoints:BAAANQADCgYIDAABNQAECgMIAwAFAAAAAA==.',
Ho='Holyfrog:BAAANQAECgMIAwAAAA==.Holyhope:BAAANQAECgMIBAABNQAECggICAAFAAAAAA==.Holylightz:BAAANQAECgMIAwAAAA==.Holymana:BAAANQAECgQICAAAAA==.Honeybunns:BAAANQADCgUIBQAAAA==.Hosstx:BAAANQADCgEIAQAAAA==.Hotandready:BAAANQABCgQIBAAAAA==.',
Hu='Huffingpaint:BAAANQADCgUICAABNQADCgYIEgAFAAAAAA==.Hukhokhan:BAAANQADCggIDwAAAA==.Hutzil:BAAANQAECgQICAAAAA==.Hutzilla:BAAANQABCgYICAAAAA==.',
Ia='Iakopa:BAAANQAECggIEwABNQAECgkJGwAJAKMQAA==.',
Il='Illidianna:BAAANQAECgQIBQAAAA==.',
Im='Imfiredup:BAAANQAECggIBQAAAA==.Imitlol:BAAANQAECgcIDQAAAA==.',
It='Itchynyple:BAAANQADCgYIDAAAAA==.Ithowen:BAAANQABCgYIBgAAAA==.',
Ja='Jacques:BAAANQADCgYICgAAAA==.Jaetherion:BAAANQAECgEIAQAAAA==.Jakes:BAAANQADCgYIBgAAAA==.Jayhawk:BAAANQAECgEIAQAAAA==.',
Ji='Jimothy:BAAANQADCgcIEwABNQAECgQIBAAFAAAAAA==.Jinx:BAAANQADCgYIEwAAAA==.',
Jo='Johaliz:BAAANQADCgEIAQAAAA==.Johnnypopoff:BAAANQADCgYIBgAAAA==.Jojohunts:BAAANQAECgEIAQAAAA==.Jonesy:BAAANQADCgIIAgABNQAECgcIEwAFAAAAAA==.',
Ju='Junyubych:BAAANQADCgQIBAABNQADCgcIFwAFAAAAAA==.',
['Jà']='Jàccuse:BAAANQADCgQICAABNQAECgMIBAAFAAAAAA==.Jàrnsaxa:BAAANQADCgYIFgAAAA==.',
['Jò']='Jòhnnypopo:BAAANQAECgQIBQAAAA==.',
Ka='Kaisra:BAAANQAECgIIAgAAAA==.Kasumeli:BAAANQAECgYICwAAAA==.Kathelas:BAAANQADCgYIBgAAAA==.Kayhan:BAAANQADCgMIBgAAAA==.Kaylaiis:BAAANQADCggICAAAAA==.Kayos:BAAANQADCgUIEAAAAA==.Kazurend:BAABNQAECoEaAAMKAAkJMSB+BQBQAwAKAAkJMSB+BQBQAwAIAAEJhRfoggBQAAAAAA==.',
Ke='Keyaielenst:BAAANQADCgUIBQAAAA==.',
Kh='Khirina:BAAANQAECgQIBAAAAA==.Khristina:BAAANQAECgMIBAAAAA==.Khrogh:BAAANQADCgYIDAAAAA==.',
Ki='Kippo:BAEANQAECgcICAAAAA==.Kisarrah:BAAANQABCgMIAwAAAA==.',
Kn='Knarn:BAAANQAECgQIBQAAAA==.',
Ko='Koralie:BAABNQAECoEaAAILAAkJkCS5AwCXAwALAAkJkCS5AwCXAwAAAA==.Korrum:BAAANQABCgIIAgAAAA==.',
Kr='Krillaxx:BAAANQAECgQIBAAAAA==.',
Kt='Ktullanux:BAAANQAECgIIAgAAAA==.',
Ky='Kyliekat:BAAANQAECgMIBAAAAA==.',
La='Lanceelot:BAAANQADCgYIBgAAAA==.Lanel:BAAANQAECgMIBQAAAA==.Lathelous:BAAANQAECgQIBQAAAA==.',
Le='Leintheir:BAAANQADCgIIAgAAAA==.',
Li='Lideina:BAAANQADCgMIAwAAAA==.Lieahi:BAAANQAECgIIAQAAAA==.Liebesleid:BAAANQADCgYIBgABNQADCgYIEgAFAAAAAA==.Lightt:BAABNQAECoEXAAIIAAgJ+QufOwCjAQAIAAgJ+QufOwCjAQAAAA==.Liightt:BAAANQAECgQIBwAAAA==.Lilcozz:BAAANQADCgUIEAAAAA==.Lilpyroblast:BAAANQAECgUICgAAAA==.Liriope:BAAANQADCgYICwAAAA==.Lizbethstar:BAAANQADCggIDAAAAA==.',
Ll='Llaerwyn:BAAANQADCgUIBQAAAA==.Llars:BAAANQAECgQIBQAAAA==.',
Lo='Loryanna:BAAANQADCgYIDgAAAA==.Louie:BAAANQADCggIEQAAAA==.Lovehandless:BAAANQADCgIIAgAAAA==.',
Lu='Lumenne:BAAANQADCgIIAgAAAA==.Luxore:BAAANQAECgUIBgABNQAECgkJGwAJAKMQAA==.',
Ly='Lyandrea:BAAANQADCggIDQAAAA==.Lyfebane:BAAANQADCgUIBQAAAA==.Lynaomira:BAAANQADCgMIAwAAAA==.',
['Lõ']='Lõrs:BAAANQADCgMIBQAAAA==.',
['Lø']='Lørs:BAAANQAECgMIBAAAAA==.',
Ma='Main:BAAANQAECgYIDQAAAA==.Majrmiståke:BAAANQADCggICAABNQAECgkJHAAGAL8PAA==.Malaxxus:BAAANQADCgEIAQAAAA==.Malendorei:BAAANQADCgcIFAAAAA==.Malicemech:BAAANQADCgcIFwAAAA==.Maliceone:BAAANQADCggIFQAAAA==.Malicepaly:BAAANQADCgUIBgAAAA==.Mallucavian:BAAANQAECgIIAgAAAA==.Mamadp:BAAANQAECgIIAgAAAA==.Manek:BAAANQAECgcIEwAAAA==.Marraxa:BAAANQAECgIIAgAAAA==.Maräjade:BAAANQABCgYIBgAAAA==.Max:BAAANQAECgUIBQAAAA==.',
Me='Melevil:BAAANQADCggICAAAAA==.Melinoe:BAAANQADCgIIAgAAAA==.Merlise:BAAANQADCgcICgAAAA==.Metalgreymon:BAAANQADCgIIAgAAAA==.',
Mi='Milenad:BAAANQAECgUIBwAAAA==.Mishosuki:BAAANQAECgEIAQAAAA==.Misscleo:BAAANQAECgQIBQAAAA==.',
Mn='Mnesarte:BAAANQADCgUIBQAAAA==.',
Mo='Mobmagnet:BAABNQAECoEhAAIMAAkJeRiqAgCTAgAMAAkJeRiqAgCTAgAAAA==.Moltres:BAEANQAECggIBQAAAA==.Moonkist:BAAANQAECgIIAgAAAA==.Moose:BAAANQAECgUICQAAAA==.Mordrandian:BAAANQADCgUIEAAAAA==.Morroe:BAAANQADCgYIDAAAAA==.',
Mu='Muffintop:BAAANQADCgQIBAAAAA==.',
Na='Nadless:BAAANQADCgYIDAAAAA==.Naeliria:BAAANQADCggICAAAAA==.Namuss:BAAANQADCgEIAQAAAA==.Navariis:BAAANQADCgQIDQAAAA==.',
Ne='Nelrehim:BAAANQAECgEIAQAAAA==.',
Ni='Niall:BAAANQAECgEIAQABNQAECgcIDQAFAAAAAA==.Niandilan:BAAANQADCgYICgAAAA==.Niixxi:BAAANQADCgEIAQAAAA==.',
Nm='Nmbrs:BAAANQADCgQIBgABNQAECgcIAgAFAAAAAA==.',
No='Noirah:BAAANQADCgcIBwAAAA==.Noirheffer:BAABNQAECoEbAAMCAAkJEhbjCQBQAgACAAkJEhbjCQBQAgAHAAEJJQFiBQEZAAAAAA==.Nokua:BAAANQADCgcIEQABNQADCgcIFwAFAAAAAA==.Noodles:BAAANQADCgQIBQAAAA==.',
Nu='Nulannatoo:BAAANQAECgEIAQAAAA==.',
Ny='Nyank:BAAANQADCggICwABNQAECgEIAQAFAAAAAA==.Nyleaf:BAAANQADCgUIBwAAAA==.Nyxaraa:BAAANQADCgYIEAAAAA==.',
Oc='Octomore:BAAANQAECgQIBQAAAA==.',
Od='Odysseus:BAAANQAECgYIEAAAAA==.',
Ol='Olguita:BAAANQAECgQIBAAAAA==.',
Om='Omgowned:BAAANQAECgIIAgABNQAECgQIBQAFAAAAAA==.',
On='Onehothealer:BAAANQADCgYIBwAAAA==.',
Oo='Oorua:BAAANQADCgYIBgAAAA==.',
Op='Opheliastar:BAAANQAECgYIEQAAAA==.',
Or='Ordovis:BAAANQAECgQIBAAAAA==.Orlucicia:BAAANQADCgQIBAAAAA==.',
Pa='Pace:BAAANQABCgYICgAAAA==.Pad:BAAANQAECgIIAgAAAA==.Paladerp:BAAANQADCggIGwAAAA==.Palanym:BAAANQAECgQIBAAAAA==.Palidyne:BAAANQAECgEIAQAAAA==.Pallyown:BAAANQADCggICAAAAA==.Papichulo:BAAANQADCgcIDQAAAA==.Parox:BAAANQABCgMIAwAAAA==.',
Ph='Phelement:BAAANQAECgQIBwAAAA==.Phett:BAAANQAECgQICAAAAA==.',
Pi='Picklës:BAAANQADCgUIBQABNQAECgUIBwAFAAAAAA==.Pimmscup:BAAANQADCgYIDAAAAA==.',
Pr='Praedthy:BAAANQAECgEIAQAAAA==.',
Qo='Qohelet:BAAANQAECgQIBQAAAA==.',
Ra='Raenya:BAAANQAECgEIAQAAAA==.Raikouu:BAAANQABCgEIAQAAAA==.Rainydaze:BAAANQADCgYICgAAAA==.Ramasses:BAAANQADCgYICgAAAA==.Ramcharger:BAAANQAECgEIAQABNQAECgcIDQAFAAAAAA==.Ramoreo:BAAANQAECgQIBAABNQADCggIHQAFAAAAAA==.Rashun:BAAANQAECgQIBAAAAA==.Raviolee:BAAANQADCgYIEAABNQAECgQIBQAFAAAAAA==.',
Re='Reanatilax:BAAANQABCgMIBQABNQAECgMIBAAFAAAAAA==.Relaeh:BAAANQADCgUIBQAAAA==.Rexxy:BAAANQADCgcICwAAAA==.',
Rh='Rhod:BAAANQADCgcICwABNQAECgIIAwAFAAAAAA==.',
Ri='Rikashae:BAAANQADCgYIBgAAAA==.Rissa:BAAANQADCgEIAQAAAA==.Risuku:BAAANQADCgEIAQAAAA==.',
Ro='Ropebunnyana:BAAANQAECgIIAwABNQADCgYIBgAFAAAAAA==.',
Ru='Ruki:BAAANQADCgYIEgAAAA==.',
Sa='Saltydk:BAAANQAECgcIEgAAAA==.Samiracy:BAAANQAECgQIBQAAAA==.Sataro:BAAANQABCgYIBAAAAA==.',
Sc='Scappe:BAAANQAECgYIEAAAAA==.',
Se='Senbatorii:BAAANQAECgMIBAAAAA==.Sethrow:BAAANQAECgQIBQAAAA==.Severa:BAAANQAECgMIBgAAAA==.',
Sh='Shadoh:BAAANQADCggIDgAAAA==.Shamazing:BAAANQADCgEIAQAAAA==.Shamwowza:BAAANQAECgIIAwAAAA==.Shantifa:BAAANQADCgYICwAAAA==.Shengari:BAAANQADCgIIAgABNQADCgQIBAAFAAAAAA==.Shoshanaa:BAAANQADCgIIAgAAAA==.Shotcallà:BAAANQADCgYIBwABNQADCggICAAFAAAAAA==.Shuna:BAAANQADCgYICQAAAA==.Shyly:BAAANQAECgIIAgAAAA==.',
Si='Siley:BAABNQAECoEYAAINAAcJ/weePAB0AQANAAcJ/weePAB0AQAAAA==.',
Sn='Sneakysneak:BAAANQAECgQIBgAAAA==.Snüff:BAAANQADCgMIAwAAAA==.',
So='Somepriest:BAAANQAECgQIBQAAAA==.',
Sp='Spiarmf:BAAANQADCgMIAwAAAA==.Sprockett:BAAANQADCggICAAAAA==.Spycmchaggis:BAAANQADCgcIEgAAAA==.',
St='Sturba:BAAANQABCgIIAgAAAA==.',
Su='Sugrace:BAAANQADCgQIBAAAAA==.Sunow:BAAANQADCgQIBwAAAA==.Superdemonzz:BAAANQAECgEIAQABNQAECgkJHAAGAL8PAA==.Superpallyz:BAABNQAECoEcAAQGAAkJvw+kJgA7AgAGAAkJvw+kJgA7AgAHAAEJUhLy3QA9AAACAAEJPgJkQgAmAAAAAA==.Superspidey:BAAANQADCgIIAgAAAA==.',
Sw='Swipeleft:BAAANQAECgYIDwAAAA==.',
Sy='Sylora:BAAANQADCgIIAgAAAA==.Sylveslem:BAAANQABCgIIAgAAAA==.',
Ta='Tabarnak:BAAANQAECgUIBQABNQAECgkJGwAOADcfAA==.Tarogen:BAAANQAECgEIAQAAAA==.',
Te='Teknique:BAAANQAECgIIAgAAAA==.Tendroni:BAAANQAECgUIBQAAAA==.Tervor:BAAANQADCgYICwAAAA==.',
Th='Thanamoros:BAAANQAECgcICwABNQAECgkJGwAJAKMQAA==.Theroach:BAAANQAECgIIAgAAAA==.Thgiewerom:BAAANQABCgYIBwAAAA==.',
Ti='Timeismoney:BAAANQABCgMIAwAAAA==.Tiognaska:BAAANQADCggIEAAAAA==.',
Tl='Tlcbm:BAAANQAECgcICwAAAA==.',
To='Toeren:BAAANQAECggIEQAAAA==.Tokå:BAAANQADCgIIAgAAAA==.Torage:BAAANQAECgEIAQAAAA==.Tormentah:BAAANQADCgIIAgABNQAECgUICwAFAAAAAA==.',
Tr='Trenity:BAAANQAECgMIBAAAAA==.Triplecanopy:BAAANQADCgUICwAAAA==.',
Ty='Tyinorin:BAAANQADCgUIEAAAAA==.',
['Tä']='Täryn:BAAANQADCgEIAQAAAA==.',
Ub='Ubee:BAAANQAECgEIAQAAAA==.',
Ug='Uglyelf:BAAANQAECgEIAQAAAA==.',
Ul='Ultimakitty:BAAANQADCggIDAAAAA==.',
Un='Uncertainty:BAAANQADCgUIBQABNQADCgYIEgAFAAAAAA==.Unchanged:BAAANQAECgIIAgAAAA==.',
Va='Vaeldrin:BAAANQADCgUIBQAAAA==.Vantrix:BAABNQAECoEbAAMJAAkJoxBfGwBrAgAJAAkJoxBfGwBrAgABAAQJ1AesKQDTAAAAAA==.Varabo:BAAANQAECgEIAQAAAA==.Varolina:BAAANQADCgcIDgAAAA==.',
Ve='Velmara:BAAANQABCgMIAwAAAA==.Velthala:BAAANQAECgMIAwAAAA==.Velyra:BAAANQAECgEIAQAAAA==.',
Vi='Vitner:BAAANQADCgIIAgABNQAECggICAAFAAAAAA==.Vivieneaux:BAAANQABCgMIBAAAAA==.',
Vo='Vosaleana:BAAANQADCgQIDQAAAA==.',
Vr='Vraak:BAABNQAECoEZAAMBAAkJbCORAQCIAwABAAkJbCORAQCIAwAJAAEJVBwjagBEAAAAAA==.',
Vu='Vulcus:BAAANQABCgYIBgABNQAECgkJGQABAGwjAA==.',
Vy='Vyndarien:BAAANQABCgcICQAAAA==.',
Wa='Wa:BAAANQAECgIIAgAAAA==.Wayofthemist:BAAANQABCgIIAgAAAA==.',
Wc='Wcreator:BAAANQAECgIIAgAAAA==.',
Wi='Will:BAABNQAECoEbAAIHAAkJzCI0BwCGAwAHAAkJzCI0BwCGAwAAAA==.',
Wo='Womdalie:BAAANQADCgYIDwAAAA==.',
Wy='Wyckedpally:BAAANQADCgcIFwAAAA==.',
Xa='Xanthös:BAAANQAECgIIAgABNQAECgkJGQABAGwjAA==.',
Xe='Xemnastrasza:BAABNQAECoEPAAIDAAgJ5gpZEQCuAQADAAgJ5gpZEQCuAQABNQAECgkJGwAJAKMQAA==.Xenonne:BAAANQAECgMIBAABNQAECgcIEgAFAAAAAA==.',
Xo='Xolither:BAAANQAECgMIBAAAAA==.',
Yo='Yourwivesbf:BAAANQADCggICQAAAA==.',
Yu='Yuura:BAAANQAECgMIAwAAAA==.',
Za='Zachdemon:BAAANQAECgUICwAAAA==.Zazoo:BAAANQABCgEIAQAAAA==.',
Ze='Zenyátta:BAAANQAECgEIAQAAAA==.Zephymoo:BAAANQAECgcIEwAAAA==.Zeretha:BAAANQABCgIIAgAAAA==.Zershadowi:BAAANQADCgYIBgAAAA==.Zeyana:BAAANQAECgUICAABNQAECgcIEgAFAAAAAA==.',
Zh='Zhengshi:BAAANQAECgMIBAAAAA==.',
Zi='Zinsatra:BAAANQADCgEIAQAAAA==.',
Zk='Zkarlyse:BAAANQAECgQIBgAAAA==.',
Zo='Zoose:BAAANQAECgQIBQAAAA==.Zoser:BAAANQADCggIGQAAAA==.',
Zs='Zsófia:BAAANQABCgMIAwAAAA==.',
Zu='Zuckuss:BAAANQADCgUIEAAAAA==.',
Zy='Zymri:BAAANQADCgQIBAABNQAECgIIAgAFAAAAAA==.',
['Æl']='Ælthan:BAAANQAECgEIAQAAAA==.',
['Ér']='Érubus:BAAANQAECgIIAgAAAA==.',
['Öl']='Ölivê:BAAANQADCggIFQAAAA==.',
['ßu']='ßugs:BAAANQAECgEIAQAAAA==.',
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
