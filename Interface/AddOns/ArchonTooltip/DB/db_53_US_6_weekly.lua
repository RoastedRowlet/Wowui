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

local lookup = {'Unknown-Unknown',}
local provider = {region='US',realm='Alexstrasza',name='US',type='weekly',zone=53,date='2026-09-01',data={Ac='Acbabcaa:BAAANQADCgEIAQAAAA==.Aceon:BAAANQAECgEIAQAAAA==.',
Ad='Adfectia:BAAANQADCgcIDAAAAA==.',
Ae='Aelianna:BAAANQADCgUIBgAAAA==.Aeth:BAAANQAECgEIAQAAAA==.Aethér:BAAANQADCgcIBwABNQAECgcIDAABAAAAAA==.',
Ag='Aggroout:BAAANQADCgYIBgABNQAECgUIBgABAAAAAA==.',
Ah='Ahsöka:BAAANQADCgIIAgAAAA==.',
Al='Alexstrászá:BAAANQAECgIIAgAAAA==.Alynas:BAAANQADCgUIBQAAAA==.Alysona:BAAANQADCgMIAwAAAA==.',
Am='Amewow:BAAANQAECgYICgAAAA==.',
An='Anarchy:BAAANQADCgcIDgAAAA==.Andraxi:BAAANQADCgUIBQAAAA==.Anorakswrath:BAAANQADCgYIBwAAAA==.',
Ap='Apophys:BAAANQADCgUIAQAAAA==.',
Ar='Ariees:BAAANQADCgEIAQAAAA==.Aruneza:BAAANQADCgcIDQAAAA==.',
As='Ashèr:BAAANQADCgcIDQAAAA==.Asunnaa:BAAANQADCgEIAQAAAA==.',
Au='Autoignition:BAAANQAECgIIAgAAAA==.',
Ba='Bahnkano:BAAANQADCgcIDAAAAA==.Bakeddh:BAAANQADCgYIBwAAAA==.',
Be='Beefcåkes:BAAANQADCgcIDwAAAA==.Beenah:BAAANQADCgUICgAAAA==.',
Bl='Blàst:BAAANQADCggICAAAAA==.',
Bo='Boomie:BAAANQAECggIBQAAAA==.Boopty:BAAANQAECgEIAQAAAA==.Booptydo:BAAANQADCgIIAgAAAA==.Boris:BAAANQADCgQIBAAAAA==.Bowhawk:BAAANQADCgYICgAAAA==.',
Bp='Bpwhunter:BAAANQAECgIIAgAAAA==.',
Br='Braiin:BAAANQADCgcIBwABNQAECgcIDAABAAAAAA==.Brazyn:BAAANQADCgYICwAAAA==.Brevarda:BAAANQAECgEIAQAAAA==.',
Bu='Bubblzmgee:BAAANQAECgQIBAAAAA==.Buscemi:BAAANQABCgMIAwAAAA==.',
['Bé']='Béach:BAAANQADCgIIAgAAAA==.',
Ca='Caracalous:BAAANQADCggIDAAAAA==.Carninn:BAAANQADCgUIBQAAAA==.Castermcfear:BAAANQABCgIIAgAAAA==.Cattiebrie:BAAANQAECgEIAgAAAA==.Caylavana:BAAANQADCggIFAAAAA==.',
Ce='Celaylria:BAAANQADCggIDgAAAA==.',
Ch='Chantille:BAAANQADCgYICAAAAA==.Charmeleön:BAAANQADCgYIBgAAAA==.',
Cl='Cloudedjayd:BAAANQADCgMIBQAAAA==.Clugorn:BAAANQAECgEIAQAAAA==.',
Co='Colourhunt:BAAANQADCggIEAAAAA==.Condewit:BAAANQADCgUIAQAAAA==.Conoresa:BAAANQADCgMIAwAAAA==.Copedk:BAAANQADCgYICgAAAA==.Corrode:BAAANQADCgYICAAAAA==.Cozymav:BAAANQADCgUIBQAAAA==.',
Cp='Cpt:BAAANQADCgEIAQAAAA==.',
Cy='Cybeldin:BAAANQADCgcIBwAAAA==.Cyberdemonxd:BAAANQADCgQIBQABNQADCgYICgABAAAAAA==.Cyndyr:BAAANQADCgQIBgAAAA==.',
Da='Daddysparey:BAAANQADCgYICwAAAA==.Darek:BAAANQADCgUIBQAAAA==.Darkbiffhunt:BAAANQADCgMIAwAAAA==.Darkrife:BAAANQADCgUIAQAAAA==.',
De='Dernis:BAAANQAECgIIAgAAAA==.Deshaman:BAAANQADCgMIAwABNQAECgUIBwABAAAAAA==.Devilbeast:BAAANQADCgUIBQAAAA==.',
Di='Disgruntled:BAAANQADCggIEAAAAA==.',
Do='Dontormentaa:BAAANQAECgIIAgAAAA==.Dontormentaj:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.',
Dr='Dracthra:BAAANQADCgcIDQAAAA==.Drakk:BAAANQADCgUIBQABNQAECgUIBwABAAAAAA==.Dreamlesnite:BAAANQABCgEIAQAAAA==.Dreidelman:BAAANQAECgEIAQAAAA==.',
Du='Dugdimadome:BAAANQADCgUIBQAAAA==.',
Dy='Dylora:BAAANQADCgcIDQAAAA==.',
Eg='Egg:BAAANQAFFAIIAgABNQAECggIDgABAAAAAA==.',
El='Elassha:BAAANQABCgQIBAAAAA==.Elatio:BAAANQAECgEIAQAAAA==.Elfairea:BAAANQADCgEIAQAAAA==.Elmortal:BAAANQADCggICAAAAA==.Elystaria:BAAANQADCgUIBwAAAA==.',
Em='Emokins:BAEANQADCgcIDQAAAA==.',
Er='Erubus:BAAANQAECgQIBgAAAA==.Eryss:BAAANQADCgUICgAAAA==.',
Fa='Faithfulone:BAAANQADCgUIBQAAAA==.Fatercul:BAAANQADCgEIAQAAAA==.',
Fd='Fdk:BAAANQADCgUIBwAAAA==.',
Fe='Fellariene:BAAANQADCgUIBQAAAA==.',
Fo='Fortissimo:BAAANQADCgIIAgAAAA==.',
['Fà']='Fàmous:BAAANQADCgcIDAAAAA==.',
Ga='Galabris:BAAANQADCgYIDAAAAA==.Gasilbench:BAAANQADCgQIBAAAAA==.',
Gh='Ghostboydk:BAAANQADCgYIBgABNQADCggICAABAAAAAA==.',
Gi='Gimligrimes:BAAANQADCgYIBgAAAA==.Gington:BAAANQADCgMIAwAAAA==.Gitchusum:BAAANQADCgMIAwAAAA==.',
Gl='Gleenna:BAAANQADCgQIAwAAAA==.',
Go='Goose:BAAANQADCgYIBgAAAA==.Gormladin:BAAANQADCgMIAwAAAA==.Gormstorm:BAAANQADCgUIBwAAAA==.',
Gr='Greenbahamut:BAAANQABCgQIBAAAAA==.Grouchy:BAAANQADCgMIAwABNQADCgUIBwABAAAAAA==.',
Ha='Halfang:BAAANQADCgQIBAAAAA==.',
Hi='Hitpoints:BAAANQADCgQIBgABNQADCgYIDQABAAAAAA==.',
Ho='Holyhope:BAAANQAECgIIAgAAAA==.Holymana:BAAANQAECgIIAgAAAA==.',
Ht='Htet:BAAANQAECgQIBAAAAA==.',
Hu='Huffingpaint:BAAANQADCgMIAwABNQADCgQIBgABAAAAAA==.Hutzil:BAAANQAECgMIBAAAAA==.',
Ia='Iakopa:BAAANQAECgUIBgABNQAECgYICgABAAAAAA==.',
Il='Illidianna:BAAANQADCgcIDAAAAA==.',
Im='Imfiredup:BAAANQAECggIBQAAAA==.',
It='Itchynyple:BAAANQADCgUIAQAAAA==.',
Ja='Jaetherion:BAAANQADCgcICgAAAA==.',
Ji='Jimothy:BAAANQADCgcIDQABNQADCggICAABAAAAAA==.Jinx:BAAANQADCgUIBwAAAA==.',
Jo='Johaliz:BAAANQADCgEIAQAAAA==.Johnnypopoff:BAAANQADCgYIBgAAAA==.Jonesy:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.',
['Jà']='Jàccuse:BAAANQADCgIIAgABNQADCgcIDQABAAAAAA==.Jàrnsaxa:BAAANQADCgYIDgAAAA==.',
['Jò']='Jòhnnypopo:BAAANQADCgcIDAAAAA==.',
Ka='Kasumeli:BAAANQAECgYIAgAAAA==.Kathelas:BAAANQADCgYIBgAAAA==.Kayos:BAAANQADCgQIBgAAAA==.Kazurend:BAAANQAECgcIDAAAAA==.',
Ke='Keyaielenst:BAAANQADCgUIBQAAAA==.',
Kh='Khirina:BAAANQADCgcIDAAAAA==.Khristina:BAAANQADCgcIDQAAAA==.Khrogh:BAAANQADCgUIBQAAAA==.',
Ki='Kippo:BAEANQAECgEIAQABNQAECgYICgABAAAAAA==.',
Kn='Knarn:BAAANQADCgcIDAAAAA==.',
Ko='Koralie:BAAANQAECgcIDQAAAA==.Korrum:BAAANQABCgMIAgAAAA==.',
Ky='Kyliekat:BAAANQADCgYIDQAAAA==.',
La='Lanel:BAAANQAECgIIAgAAAA==.Lathelous:BAAANQADCgcIDAAAAA==.',
Le='Leintheir:BAAANQADCgIIAgAAAA==.',
Li='Lightt:BAAANQAECgUIBwAAAA==.Liightt:BAAANQADCggIDgAAAA==.Lilcozz:BAAANQADCgQIBgAAAA==.Lilpyroblast:BAAANQAECgEIAQAAAA==.Lizbethstar:BAAANQADCgQIBAAAAA==.',
Ll='Llars:BAAANQADCgcIDAAAAA==.',
Lo='Loryanna:BAAANQADCgYIBgAAAA==.Louie:BAAANQADCgYIBwAAAA==.Lovehandless:BAAANQADCgIIAgAAAA==.',
Ly='Lyandrea:BAAANQADCgUIBQAAAA==.',
['Lõ']='Lõrs:BAAANQADCgIIAgAAAA==.',
['Lø']='Lørs:BAAANQADCgcIDgAAAA==.',
Ma='Main:BAAANQAECgIIAgAAAA==.Malaxxus:BAAANQADCgEIAQAAAA==.Malendorei:BAAANQADCgYIBgAAAA==.Malicemech:BAAANQADCgYICwAAAA==.Maliceone:BAAANQADCgYICQAAAA==.Malicepaly:BAAANQADCgEIAQAAAA==.Mallucavian:BAAANQADCgMIAwAAAA==.Mamadp:BAAANQADCgQICQAAAA==.Manek:BAAANQAECgQIBAAAAA==.Marraxa:BAAANQADCgQIBwAAAA==.Max:BAAANQADCgYIBwAAAA==.',
Me='Melinoe:BAAANQADCgIIAgAAAA==.Merlise:BAAANQADCgcICgAAAA==.',
Mi='Milenad:BAAANQADCggIDgAAAA==.Mishosuki:BAAANQADCgYIBgAAAA==.Misscleo:BAAANQADCgcICwAAAA==.',
Mn='Mnesarte:BAAANQADCgUIBQAAAA==.',
Mo='Mobmagnet:BAAANQAECggIDwAAAA==.Moltres:BAEANQAECggIBQAAAA==.Moonkist:BAAANQADCgMIAwABNQADCgUIBwABAAAAAA==.Moose:BAAANQAECgQIBAAAAA==.Mordrandian:BAAANQADCgQIBgAAAA==.Morroe:BAAANQADCgYICAAAAA==.',
Na='Nadless:BAAANQADCgYIDAAAAA==.Naki:BAAANQADCgUICQAAAA==.Navariis:BAAANQADCgQIBwAAAA==.',
Ne='Nelrehim:BAAANQADCgQIBAAAAA==.',
Ni='Niandilan:BAAANQADCgUIAQAAAA==.Niixxi:BAAANQADCgEIAQAAAA==.',
Nm='Nmbrs:BAAANQADCgEIAQABNQADCgUIBwABAAAAAA==.',
No='Noirheffer:BAAANQAECgUIBgAAAA==.Nokua:BAAANQADCgUICQABNQADCgYICgABAAAAAA==.',
Ny='Nyank:BAAANQADCgUIBQABNQADCgYICgABAAAAAA==.Nyleaf:BAAANQADCgUIBwAAAA==.',
Oc='Octomore:BAAANQADCgcIDAAAAA==.',
Od='Odysseus:BAAANQAECgQIBAAAAA==.',
Ol='Olguita:BAAANQADCgIIAgAAAA==.',
Om='Omgowned:BAAANQADCgYIDAABNQADCgcIDQABAAAAAA==.',
On='Onehothealer:BAAANQADCgYIBgAAAA==.',
Op='Opheliastar:BAAANQAECgQIBQAAAA==.',
Or='Ordovis:BAAANQAECgQIBAAAAA==.',
Pa='Pad:BAAANQADCgUIBQAAAA==.Paladerp:BAAANQADCgYICwAAAA==.Palanym:BAAANQADCggIDgAAAA==.Palidyne:BAAANQADCgYICwAAAA==.Papichulo:BAAANQADCgcIDQAAAA==.',
Ph='Phelement:BAAANQAECgIIAgAAAA==.Phett:BAAANQADCggICgAAAA==.',
Pi='Picklës:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.Pimmscup:BAAANQADCgUIAQAAAA==.',
Qo='Qohelet:BAAANQADCggIDgAAAA==.',
Ra='Raenya:BAAANQADCgUICwAAAA==.Rainydaze:BAAANQADCgQIBAAAAA==.Ramasses:BAAANQADCgYICgAAAA==.Ramcharger:BAAANQADCgEIAQABNQADCggIFAABAAAAAA==.Ramoreo:BAAANQAECgQIBAABNQADCgYIBgABAAAAAA==.Rashun:BAAANQADCgcIDAAAAA==.Raviolee:BAAANQADCgUIBQAAAA==.',
Re='Rexxy:BAAANQADCgMIBAAAAA==.',
Rh='Rhod:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.',
Ro='Ropebunnyana:BAAANQAECgIIAwAAAA==.',
Ru='Ruki:BAAANQADCgQIBgAAAA==.',
Sa='Saltydk:BAAANQAECgQIBQAAAA==.Samiracy:BAAANQADCgcIDQAAAA==.',
Sc='Scappe:BAAANQAECgQIBAAAAA==.',
Se='Senbatorii:BAAANQADCgcIDwAAAA==.Sethrow:BAAANQADCgcIDQAAAA==.Severa:BAAANQADCgcIDgAAAA==.',
Sh='Shadoh:BAAANQADCgYIBgAAAA==.Shamazing:BAAANQADCgEIAQAAAA==.Shamwowza:BAAANQADCgcIEQAAAA==.Shoshanaa:BAAANQADCgIIAgAAAA==.Shyly:BAAANQADCggIFAAAAA==.',
Si='Siley:BAAANQAECgMIBgAAAA==.',
So='Somepriest:BAAANQADCgcIDAAAAA==.',
Sp='Spiarmf:BAAANQADCgMIAwAAAA==.Spycmchaggis:BAAANQADCgYICwAAAA==.',
St='Sturba:BAAANQABCgIIAgAAAA==.',
Su='Superdemonzz:BAAANQADCgQIBQABNQAECgYIDAABAAAAAA==.Superpallyz:BAAANQAECgYIDAAAAA==.',
Sw='Swipeleft:BAAANQAECgQIBAAAAA==.',
Ta='Tarogen:BAAANQADCgQIBAAAAA==.',
Te='Tervor:BAAANQADCgIIBQAAAA==.',
Th='Thundermace:BAAANQADCggICAAAAA==.',
Ti='Tiognaska:BAAANQADCgEIAQAAAA==.',
Tl='Tlcbm:BAAANQADCggIDwAAAA==.',
To='Toeren:BAAANQAECgUIBwAAAA==.Tokå:BAAANQADCgIIAgAAAA==.Tormentah:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.',
Tr='Trenity:BAAANQADCgcIDQAAAA==.Triplecanopy:BAAANQADCgQIBgAAAA==.',
Ty='Tyinorin:BAAANQADCgQIBgAAAA==.',
['Tä']='Täryn:BAAANQADCgEIAQAAAA==.',
Ub='Ubee:BAAANQADCgcICgAAAA==.',
Ug='Uglyelf:BAAANQADCgcICgAAAA==.',
Un='Unchanged:BAAANQAECgIIAgAAAA==.',
Va='Vaeldrin:BAAANQADCgUIBQAAAA==.Vantrix:BAAANQAECgYICgAAAA==.Varabo:BAAANQADCgYIBgAAAA==.Varolina:BAAANQADCgIIAgAAAA==.',
Ve='Velthala:BAAANQADCgcIDAAAAA==.Velyra:BAAANQADCgUIBwAAAA==.',
Vo='Vosaleana:BAAANQADCgQICQAAAA==.',
Vr='Vraak:BAAANQAECgcIDAAAAA==.',
Wa='Wa:BAAANQADCgYIDAAAAA==.Wayofthemist:BAAANQABCgIIAgAAAA==.',
Wc='Wcreator:BAAANQAECgIIAgAAAA==.',
Wi='Will:BAAANQAECgUICAAAAA==.',
Wo='Womdalie:BAAANQADCgQICQAAAA==.',
Wy='Wyckedpally:BAAANQADCgYICgAAAA==.',
Xa='Xanthös:BAAANQAECgEIAQABNQAECgcIDAABAAAAAA==.',
Xe='Xemnastrasza:BAAANQADCgMIAwABNQAECgYICgABAAAAAA==.Xenonne:BAAANQAECgMIBAABNQAECgQIBAABAAAAAA==.',
Xo='Xolither:BAAANQADCgcIEAAAAA==.',
Yo='Yourwivesbf:BAAANQADCgcIBwAAAA==.',
Za='Zachdemon:BAAANQAECgIIAgAAAA==.Zazoo:BAAANQABCgEIAQAAAA==.',
Ze='Zenyátta:BAAANQADCgYICwAAAA==.Zephymoo:BAAANQAECgQIBgAAAA==.Zeretha:BAAANQABCgIIAgAAAA==.Zeyana:BAAANQAECgMIAwABNQAECgYICQABAAAAAA==.',
Zh='Zhengshi:BAAANQADCgcIDQAAAA==.',
Zi='Zinsatra:BAAANQADCgEIAQAAAA==.',
Zk='Zkarlyse:BAAANQAECgEIAQAAAA==.',
Zo='Zoose:BAAANQADCgcIDQAAAA==.Zoser:BAAANQADCgcICgAAAA==.',
Zu='Zuckuss:BAAANQADCgQIBgAAAA==.',
['Æl']='Ælthan:BAAANQADCggIAQAAAA==.',
['Öl']='Ölivê:BAAANQADCgUIBQAAAA==.',
['ßu']='ßugs:BAAANQADCggIDgAAAA==.',
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
