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
local provider = {region='US',realm='Uther',name='US',type='weekly',zone=53,date='2026-09-01',data={Ah='Aha:BAAANQADCgYIBgAAAA==.',
Ai='Aiax:BAAANQAECgIIAgAAAA==.',
Al='Aliancia:BAAANQADCggIDwAAAA==.',
Am='Amynle:BAAANQADCgUIBQAAAA==.',
An='Annora:BAAANQAECgIIAgAAAA==.Antonious:BAAANQADCggIDgAAAA==.',
Ap='Apollyon:BAAANQAECgIIAgAAAA==.',
Ar='Ari:BAAANQAECgEIAQAAAA==.Ariioch:BAAANQADCgQICAAAAA==.',
As='Assclapiuss:BAAANQAECgQIBQAAAA==.Asterchades:BAAANQAECgQIBQAAAA==.Asteriou:BAAANQADCgUIBgAAAA==.',
At='Attikus:BAAANQAECgEIAQAAAA==.Atuan:BAAANQADCgEIAQAAAA==.',
Au='Auralass:BAAANQADCgYICAAAAA==.Autauga:BAAANQADCggIDQAAAA==.',
Av='Avilla:BAAANQADCggIDQAAAA==.',
Ax='Axem:BAAANQAECgEIAQAAAA==.',
Az='Azulathan:BAAANQADCgQIBAAAAA==.',
Be='Bechett:BAAANQADCggIDwAAAA==.Beep:BAAANQADCggIDQAAAA==.Beerguy:BAAANQADCgMIAwAAAA==.Behemothe:BAAANQAECgQIBQAAAA==.Berníesandrs:BAAANQADCgYICgAAAA==.Beryllos:BAAANQADCgQIBAAAAA==.Bewzey:BAAANQADCggIDQAAAA==.',
Bl='Bloodmourne:BAAANQADCggIDQAAAA==.Bloodytoutii:BAAANQAECgEIAQAAAA==.',
Bo='Bortman:BAAANQAECgEIAQAAAA==.Bowowner:BAAANQADCgUIBQAAAA==.',
Bu='Buhbul:BAAANQADCgYIBgAAAA==.Buzzball:BAAANQADCgcIDQAAAA==.',
Bw='Bwicked:BAAANQAECgEIAQAAAA==.',
Ch='Chimpnzthat:BAAANQADCgYICAAAAA==.Chookicookie:BAAANQAECgQIBQAAAA==.Chrome:BAAANQAECgQIBQAAAA==.',
Ci='Cindyy:BAAANQAECgIIAgAAAA==.Cirí:BAAANQAECgEIAQAAAA==.',
Co='Coldbeans:BAAANQADCgUIBQAAAA==.Coresh:BAAANQAECgMIAwAAAA==.Cornpuff:BAAANQADCgQICAAAAA==.',
Cr='Crickets:BAAANQADCgYIDwAAAA==.',
Cu='Cupsandcakes:BAAANQADCgQIBgAAAA==.',
Da='Dark:BAAANQAECgQIBQAAAA==.Darkphyre:BAAANQADCgQICAAAAA==.',
De='Deadloc:BAAANQADCgUIBQAAAA==.Deadmandan:BAAANQAECgMIAwAAAA==.Deathtike:BAAANQAECgIIAgABNQAECgQIBQABAAAAAA==.Decius:BAAANQADCgQICAAAAA==.Deltairlines:BAAANQAECggIEAAAAA==.Demagorgin:BAAANQAECgEIAQAAAA==.Deqlyn:BAAANQAECgEIAQAAAA==.Desmus:BAAANQADCgYICAAAAA==.Deáthreaver:BAAANQAECgEIAQAAAA==.',
Di='Diddyy:BAAANQAECgIIAgAAAA==.',
Do='Domwarlock:BAAANQADCggIDQAAAA==.Dots:BAAANQADCgYICgAAAA==.',
Dr='Dronin:BAAANQADCgYICwAAAA==.Drpatan:BAAANQADCgcIBwAAAA==.Druni:BAAANQADCgQICAAAAA==.Drâkenhân:BAAANQADCgQICAAAAA==.',
Du='Dumpling:BAAANQADCgMIAwAAAA==.Durango:BAAANQADCgQIBQAAAA==.',
Ec='Echowalker:BAAANQADCgcIBwAAAA==.',
Ed='Edinburger:BAAANQADCgMIAwAAAA==.',
Em='Emokillaz:BAAANQADCgcIBwAAAA==.',
Ep='Epsilón:BAAANQADCgYICgAAAA==.',
Es='Esmerr:BAAANQADCggIDwAAAA==.',
Fa='Faxon:BAAANQADCggIDQAAAA==.',
Fe='Feronnia:BAAANQADCgQIBAAAAA==.',
Fi='Fibot:BAAANQAECgQIBQAAAA==.Fireboürne:BAAANQAECgIIAgAAAA==.Fireishot:BAAANQADCgUIBQAAAA==.',
Fl='Florasol:BAAANQADCgUICgAAAA==.',
Fr='Fraeyah:BAAANQADCgUIBgAAAA==.Friede:BAAANQAECgIIAgAAAA==.',
['Fè']='Fènrys:BAAANQADCgQIBAAAAA==.',
Ga='Galvanize:BAEANQAECgUIBgAAAA==.',
Gh='Ghomertin:BAAANQADCgMIAwAAAA==.',
Gi='Gipsydanger:BAAANQAECgQIBAAAAA==.',
Go='Gonnjass:BAAANQADCgYICgAAAA==.Gorlokk:BAEANQADCgEIAQAAAA==.',
Gr='Grakonys:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Greed:BAAANQAECgQIBAAAAA==.Grimmbot:BAAANQADCgQIBQAAAA==.Grunch:BAAANQADCgQIBAAAAA==.',
Gu='Guayusa:BAAANQAECgIIAgAAAA==.',
Ha='Harnix:BAAANQADCgQIBQAAAA==.Hawtbooty:BAAANQADCgcIDgAAAA==.',
He='Hellreines:BAAANQAECgMIBAAAAA==.Hemolythria:BAAANQADCgIIAgAAAA==.',
Hi='Hildi:BAAANQADCgYICAAAAA==.Him:BAAANQAECgIIAgAAAA==.',
Ho='Holy:BAAANQAECgMIAwAAAA==.Hotmess:BAAANQADCgUIBwAAAA==.',
Is='Ishura:BAAANQADCgYIBgAAAA==.',
Iv='Ivvy:BAAANQADCgcICwAAAA==.',
Iz='Izanami:BAAANQADCgUICAAAAA==.',
Ja='Jaffer:BAAANQAECgUIBwAAAA==.Janntro:BAAANQADCggIDgAAAA==.Jantro:BAAANQADCggIDQABNQADCggIDgABAAAAAA==.Janttro:BAAANQADCgYIBgABNQADCggIDgABAAAAAA==.',
Je='Jeebz:BAAANQAECgUIBQAAAA==.Jelmarr:BAAANQADCgQIBAAAAA==.Jerauld:BAAANQADCgYICAAAAA==.',
Ji='Jimmyhoffá:BAAANQADCgMIAwAAAA==.',
Jo='Johnnyzyns:BAAANQADCggIDgAAAA==.Joshc:BAAANQADCggIDgAAAA==.',
Ju='Judgédred:BAAANQADCgUIBQAAAA==.',
Ka='Kaaris:BAAANQADCgYIBgAAAA==.Kaiarie:BAAANQADCgYICAAAAA==.Kainraziel:BAAANQAECgEIAQAAAA==.Kairos:BAAANQAECgQIBQAAAA==.Kanofworms:BAAANQADCgYICgAAAA==.',
Ke='Kebin:BAAANQAECgIIAgAAAA==.',
Ki='Kibil:BAAANQADCggIDQAAAA==.',
Ko='Kortharion:BAAANQADCggICQAAAA==.Kos:BAAANQAECgYIBgAAAA==.',
Ku='Kujiera:BAAANQADCgcIDAAAAA==.Kurick:BAAANQADCgUIBQAAAA==.Kurrenter:BAAANQADCggIDQAAAA==.',
['Ká']='Kárgorr:BAAANQADCgQIBgAAAA==.',
['Kÿ']='Kÿtten:BAAANQAECgIIAgAAAA==.',
La='Laiyth:BAAANQAECgEIAQAAAA==.Larryfish:BAAANQADCggIDQAAAA==.Lavos:BAAANQAECgEIAQAAAA==.',
Li='Lisster:BAAANQADCggIDgAAAA==.Liyra:BAAANQADCgQIBAAAAA==.',
Lo='Loafe:BAAANQAECgIIAgAAAA==.Logout:BAAANQADCgQIBAAAAA==.',
Lu='Luthais:BAAANQADCgQICAAAAA==.Luxury:BAAANQADCgYICQAAAA==.',
Ly='Lykanthropos:BAAANQADCgQIBQAAAA==.',
Ma='Magmabeard:BAAANQADCggICwAAAA==.Maingauche:BAAANQAECgEIAQAAAA==.Mako:BAAANQAECgIIAgAAAA==.Malevian:BAAANQADCgYIDgAAAA==.Maples:BAAANQAECgMIAwAAAA==.Mariasha:BAAANQADCgQIBAAAAA==.Marichika:BAAANQADCgYIBgAAAA==.Mazz:BAAANQADCgYIBgAAAA==.',
Me='Megaterium:BAAANQADCggIDgAAAA==.Meláni:BAAANQADCgMIBAAAAA==.Menethil:BAAANQADCgYICwAAAA==.',
Mi='Milei:BAAANQADCgQICAAAAA==.Missmisery:BAAANQADCggIDQAAAA==.Mistaya:BAAANQADCgQIBAAAAA==.Mithdraug:BAAANQADCgQIBgAAAA==.',
Mo='Monache:BAAANQADCgQIBAAAAA==.Moocheala:BAAANQADCgMIAwAAAA==.Mortarîon:BAAANQADCgQIBQAAAA==.',
Ms='Msdktank:BAAANQADCgIIAgAAAA==.',
My='Mythrilblade:BAAANQADCgQIBAAAAA==.',
Ni='Nightparade:BAAANQADCgQICAAAAA==.Nishgrail:BAAANQAECgEIAgAAAA==.',
Nu='Nukusmaximus:BAAANQADCgQIBgAAAA==.',
Od='Odioz:BAAANQADCgMIAwAAAA==.',
On='Onex:BAAANQADCgQICAAAAA==.',
Or='Ori:BAAANQADCgQIBAAAAA==.',
Oz='Ozmo:BAAANQADCgQIBAAAAA==.',
Pa='Pawmasutra:BAAANQADCggIDgAAAA==.',
Pe='Pencil:BAAANQADCgcIDgAAAA==.Persefini:BAAANQADCgQICAAAAA==.Petrodrak:BAAANQADCgQIBQAAAA==.',
Ph='Pheylan:BAAANQADCgQICAAAAA==.',
Pl='Plugugly:BAAANQAECgEIAQAAAA==.',
Po='Polinemarois:BAAANQADCgUIAwAAAA==.Portal:BAAANQADCgIIAgABNQADCgYICQABAAAAAA==.Potatobear:BAAANQAECgIIAgAAAA==.',
Pr='Praytwothee:BAAANQAECgEIAQAAAA==.',
Qu='Quickbow:BAAANQADCgUIBQAAAA==.Quicktime:BAAANQAECgMIAwAAAA==.',
Ra='Ragedh:BAAANQAECgIIBAAAAA==.Ragequit:BAAANQAECgYIBAAAAA==.Ragnoir:BAAANQADCggIDgAAAA==.Rased:BAAANQADCggICAAAAA==.',
Ro='Roglof:BAAANQAECggIAgAAAA==.Rowlah:BAAANQADCgQIBAAAAA==.Rozy:BAAANQAECgYICAAAAA==.',
Ru='Ruiizu:BAAANQADCggIDgAAAA==.Rushuna:BAAANQAECgIIAwAAAA==.',
Sa='Saberjaw:BAAANQAECgIIAgAAAA==.Sairicck:BAAANQAECgEIAgAAAA==.Santamorte:BAAANQADCgMIAwAAAA==.Sarauco:BAAANQADCgQIBAAAAA==.Sarcasticus:BAAANQADCgQICAAAAA==.',
Se='Selenar:BAAANQADCggICAAAAA==.Selinora:BAAANQAECgEIAQAAAA==.Serhalatath:BAAANQADCgcIBwAAAA==.',
Sh='Shade:BAAANQADCgYICQAAAA==.Shadowsbane:BAAANQAECgIIAgAAAA==.Shaguar:BAAANQADCggIDgAAAA==.Shamwow:BAAANQAECgIIAgAAAA==.Shaolinsnake:BAAANQADCgQICAAAAA==.Shiftshow:BAAANQADCggICAAAAA==.Shinukagé:BAAANQADCgEIAQAAAA==.',
Si='Singe:BAAANQAECgIIAgAAAA==.',
Sk='Skeetsurfin:BAAANQABCgIIAgAAAA==.',
Sl='Sloppyjo:BAAANQAECgIIAgAAAA==.',
Sm='Smallblackdk:BAAANQADCgEIAQAAAA==.',
So='Solsti:BAAANQAECgIIAwAAAA==.Soulhunter:BAAANQAECgQIBQAAAA==.',
Sp='Spears:BAAANQADCgcIDAAAAA==.Spoondot:BAAANQADCgIIAgAAAA==.',
St='Stinjaga:BAAANQADCggIDgAAAA==.',
Su='Sunrae:BAAANQADCgYICAAAAA==.',
Sy='Sylinsor:BAAANQAECgIIAgAAAA==.Symor:BAAANQADCgQIBQAAAA==.Syxmoo:BAAANQADCgUICAAAAA==.',
Ta='Taproot:BAEANQADCgcIBwABNQAECgUIBgABAAAAAA==.Taryen:BAAANQADCggIDQABNQAECgIIBAABAAAAAA==.',
Te='Telaari:BAAANQADCgMIAwAAAA==.Teriyl:BAAANQADCgcIDQAAAA==.',
Th='Thalenia:BAAANQAECgIIAgAAAA==.Thalron:BAAANQADCgQICAAAAA==.',
Ti='Tikeidari:BAAANQAECgQIBQAAAA==.Tiltedtroll:BAAANQADCggIDAAAAA==.',
To='Tonofcron:BAAANQADCgUIBQAAAA==.Totemeri:BAAANQAECgEIAQAAAA==.',
Tr='Trappydk:BAAANQADCggIDwAAAA==.',
Un='Unagi:BAAANQADCgcIDQAAAA==.',
Va='Valezeal:BAAANQADCgIIAgAAAA==.Vazdun:BAAANQAECgEIAQAAAA==.',
Ve='Velari:BAAANQADCgQIBAAAAA==.Venan:BAAANQADCgYIBwAAAA==.Venefirous:BAAANQADCgUIBQAAAA==.Venenn:BAAANQADCgQIBAAAAA==.Venev:BAAANQADCgQIBwAAAA==.Ventana:BAAANQADCgcIDQAAAA==.Verdilac:BAAANQADCgQIBAABNQAECgQIBAABAAAAAA==.',
Vi='Vinceglortho:BAAANQADCgIIAgAAAA==.',
Vl='Vlad:BAAANQADCgIIAgAAAA==.',
Vy='Vyranox:BAAANQAECgIIAgAAAA==.',
Wa='Wanji:BAAANQADCggIDgAAAA==.',
Wi='Wintyr:BAAANQADCgQIBQAAAA==.',
Xa='Xaharst:BAAANQADCggICgAAAA==.Xaya:BAAANQAECgIIAgAAAA==.',
Xe='Xenophorge:BAAANQADCgMIAwAAAA==.',
Xo='Xovace:BAAANQADCgQICAAAAA==.',
Xt='Xtayse:BAAANQADCggIDQAAAA==.',
Yi='Yirya:BAAANQAECgIIAgAAAA==.',
Yo='Yoruechi:BAAANQAECgIIAgAAAA==.Youroverlord:BAAANQADCggICAAAAA==.',
['Yú']='Yúmyúm:BAAANQABCgIIAgAAAA==.',
Za='Zahel:BAAANQAECgQIBgAAAA==.Zavier:BAAANQADCggIDQAAAA==.',
Ze='Zeppola:BAAANQADCgYICgAAAA==.',
Zh='Zhee:BAAANQADCgQICAAAAA==.',
Zo='Zobi:BAAANQADCgQIBQAAAA==.Zomboo:BAAANQAECgUIBQAAAA==.',
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
