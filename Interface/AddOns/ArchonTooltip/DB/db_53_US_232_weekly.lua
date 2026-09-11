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

local lookup = {'Unknown-Unknown','Evoker-Augmentation','Evoker-Preservation',}
local provider = {region='US',realm='Uther',name='US',type='weekly',zone=53,date='2026-09-08',data={Ah='Aha:BAAANQADCgYICAAAAA==.',
Ai='Aiax:BAAANQAECgUIBwAAAA==.',
Al='Alderok:BAAANQADCgcIBwABNQAECgMIAwABAAAAAA==.Aliancia:BAAANQAECgEIAQAAAA==.Alydin:BAAANQAECgQIBAAAAA==.',
Am='Amynle:BAAANQADCgYICwAAAA==.',
An='Annora:BAAANQAECgQIBgAAAA==.Antonious:BAAANQAECgEIAQAAAA==.',
Ap='Apollyon:BAAANQAECgQICAAAAA==.',
Ar='Ari:BAAANQAECgMIBAAAAA==.Ariioch:BAAANQADCggIEAAAAA==.',
As='Assclapiuss:BAAANQAECgUICgAAAA==.Asterchades:BAAANQAECgUICgAAAA==.Asteriou:BAAANQADCgUIBgAAAA==.',
At='Attikus:BAAANQAECgUIBgAAAA==.Atuan:BAAANQADCggICQAAAA==.',
Au='Auralass:BAAANQADCgcIDwAAAA==.Autauga:BAAANQAECgMIAwAAAA==.',
Av='Avilla:BAAANQAECgMIAwAAAA==.',
Ax='Axem:BAAANQAECgQIBQAAAA==.',
Az='Azulathan:BAAANQADCgQIBAAAAA==.',
Be='Bechett:BAAANQAECgMIAwAAAA==.Beep:BAAANQAECgEIAQAAAA==.Beerguy:BAAANQADCgMIAwAAAA==.Behemothe:BAAANQAECgUICgAAAA==.Berníesandrs:BAAANQADCggIDwAAAA==.Beryllos:BAAANQADCgUICQAAAA==.Bewzey:BAAANQAECgMIAwAAAA==.',
Bl='Bloodmourne:BAAANQADCggIDQAAAA==.Bloodytoutii:BAAANQAECgEIAgAAAA==.',
Bo='Bortman:BAAANQAECgEIAQAAAA==.Bowowner:BAAANQADCgUIBQAAAA==.',
Bu='Buhbul:BAAANQADCgYIDAAAAA==.Buzzball:BAAANQADCgcIDgAAAA==.',
Bw='Bwicked:BAAANQAECgQIBQAAAA==.',
Ca='Caroline:BAAANQADCgQIBAAAAA==.',
Ce='Celonge:BAAANQADCggICAABNQAECgQIBwABAAAAAA==.',
Ch='Chimpnzthat:BAAANQADCgcIDwAAAA==.Chookicookie:BAAANQAECgUICgAAAA==.Chrome:BAAANQAECgUICgAAAA==.',
Ci='Cindyy:BAAANQAECgIIAgAAAA==.Cirí:BAAANQAECgQIBQAAAA==.',
Co='Coldbeans:BAAANQAECgEIAQAAAA==.Coresh:BAAANQAECgUICAAAAA==.Cornpuff:BAAANQADCggIEAAAAA==.',
Cr='Crickets:BAAANQAECgIIAgAAAA==.',
Cu='Cupsandcakes:BAAANQADCggIDgAAAA==.',
Da='Dadbody:BAAANQADCgUIBQABNQAECgUICgABAAAAAA==.Dark:BAAANQAECgUICgAAAA==.Darkphyre:BAAANQADCggIEAAAAA==.',
De='Deadloc:BAAANQADCgYICwAAAA==.Deadmandan:BAAANQAECgUICAAAAA==.Deathtike:BAAANQAECgQIBgABNQAECgUICgABAAAAAA==.Decius:BAAANQADCggIEAAAAA==.Deltairlines:BAABNQAECoEYAAMCAAkJcSHpAABCAwACAAkJcSHpAABCAwADAAkJNhEjCgBTAgAAAA==.Demagorgin:BAAANQAECgEIAQAAAA==.Deqlyn:BAAANQAECgMIAwAAAA==.Desmus:BAAANQADCgcIDgAAAA==.Devilmaycry:BAAANQADCgUIBQAAAA==.Deáthreaver:BAAANQAECgQIBQAAAA==.',
Di='Diddyy:BAAANQAECgIIAgAAAA==.',
Do='Domwarlock:BAAANQAECgMIAwAAAA==.Dots:BAAANQADCgYIDwAAAA==.',
Dr='Dronin:BAAANQAECgMIAwAAAA==.Drpatan:BAAANQADCgcICwAAAA==.Druni:BAAANQADCggIEAAAAA==.Drâkenhân:BAAANQADCggIEAAAAA==.',
Du='Dumpling:BAAANQADCgMIAwAAAA==.Durango:BAAANQADCgUICgAAAA==.',
Ec='Echowalker:BAAANQADCggIDgAAAA==.',
Ed='Edinburger:BAAANQADCgMIAwAAAA==.',
Em='Emokillaz:BAAANQADCgcIBwAAAA==.',
Ep='Epsilón:BAAANQADCgcICwAAAA==.',
Es='Esmerr:BAAANQADCggIHgAAAA==.',
Fa='Faxon:BAAANQAECgMIAwAAAA==.',
Fe='Feronnia:BAAANQADCgUICQAAAA==.',
Fi='Fibot:BAAANQAECgUICgAAAA==.Fireboürne:BAAANQAECgIIAgAAAA==.Fireishot:BAAANQADCgUICQAAAA==.',
Fl='Florasol:BAAANQADCgYIEAAAAA==.',
Fr='Fraeyah:BAAANQADCgUIBgAAAA==.Friede:BAAANQAECgMIBAAAAA==.',
['Fè']='Fènrys:BAAANQADCgQIBAAAAA==.',
Ga='Galvanize:BAEANQAECgYIDAAAAA==.',
Ge='Geewetsya:BAAANQADCgUIBQAAAA==.Gengarr:BAAANQADCgMIAwABNQADCgUIBQABAAAAAA==.',
Gh='Ghomertin:BAAANQADCgYICQAAAA==.',
Gi='Gipsydanger:BAAANQAECgUICQAAAA==.',
Gl='Gladiatrix:BAAANQADCgYIBgAAAA==.',
Go='Gonnjass:BAAANQADCgYICgAAAA==.Gorlokk:BAEANQADCgEIAQABNQADCgQIBAABAAAAAA==.',
Gr='Grakonys:BAAANQAECgUIBgAAAA==.Greed:BAAANQAECgQICAAAAA==.Grimmbot:BAAANQAECgQIBAAAAA==.Grunch:BAAANQADCgQIBAAAAA==.Grunnck:BAAANQADCgUIBQAAAA==.',
Gu='Guayusa:BAAANQAECgIIAgAAAA==.',
Ha='Harnix:BAAANQADCgYICwAAAA==.Hawtbooty:BAAANQAECgIIAgAAAA==.',
He='Hellreines:BAAANQAECgMIBAAAAA==.Hemolythria:BAAANQADCgIIAgAAAA==.',
Hi='Hildi:BAAANQADCgcIDwAAAA==.Him:BAAANQAECgQIBgAAAA==.',
Ho='Holy:BAAANQAECgQIBwAAAA==.Hotmess:BAAANQADCgUIBwAAAA==.',
Hu='Hurcules:BAAANQABCgEIAQAAAA==.',
Ic='Icespirit:BAAANQABCgEIAQAAAA==.',
Il='Illidaris:BAAANQADCgYIBgAAAA==.',
Is='Ishura:BAAANQADCgcIDQAAAA==.',
Iv='Ivvy:BAAANQAECgIIAgAAAA==.',
Iz='Izanami:BAAANQADCgcIDwAAAA==.',
Ja='Jaffer:BAAANQAECgYIDQAAAA==.Janntro:BAAANQAECgIIAgABNQAECgIIAgABAAAAAA==.Jantra:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.Jantro:BAAANQAECgIIAgAAAA==.Janttro:BAAANQADCggIDQABNQAECgIIAgABAAAAAA==.',
Je='Jebby:BAAANQADCgYIBwABNQAECgUICAABAAAAAA==.Jeebz:BAAANQAECgUICAAAAA==.Jelmarr:BAAANQADCgUICQAAAA==.Jerauld:BAAANQADCgcIDwAAAA==.',
Ji='Jimmyhoffá:BAAANQAECgEIAQAAAA==.',
Jo='Johnnyzyns:BAAANQADCggIDgAAAA==.Joshc:BAAANQADCggIDgAAAA==.',
Ju='Judgédred:BAAANQADCgYIBgAAAA==.',
['Já']='Ják:BAAANQADCgUIBQAAAA==.',
Ka='Kaaris:BAAANQAECgIIAgAAAA==.Kaiarie:BAAANQADCgYIDgAAAA==.Kainraziel:BAAANQAECgMIBAAAAA==.Kairos:BAAANQAECgUICgAAAA==.Kanofworms:BAAANQADCggIEgAAAA==.Karkea:BAAANQABCgIIAgAAAA==.',
Ke='Kebin:BAAANQAECgIIAgAAAA==.',
Ki='Kibil:BAAANQAECgMIAwAAAA==.',
Ko='Korax:BAAANQADCgUIBAAAAA==.Kortharion:BAAANQADCggICQAAAA==.Kos:BAAANQAECgcIDQAAAA==.',
Kr='Krule:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.',
Ku='Kujiera:BAAANQAECgIIAgAAAA==.Kurick:BAAANQAECgEIAQAAAA==.Kurrenter:BAAANQAECgMIAwAAAA==.',
['Ká']='Kárgorr:BAAANQADCgQIBgAAAA==.',
['Kÿ']='Kÿtten:BAAANQAECgQIBwAAAA==.',
La='Laiyth:BAAANQAECgIIAwAAAA==.Larryfish:BAAANQAECgMIAwAAAA==.Lavos:BAAANQAECgQIBQAAAA==.',
Li='Lisster:BAAANQADCggIDgAAAA==.Liyra:BAAANQADCgcICwAAAA==.',
Lo='Loafe:BAAANQAECgMIBQAAAA==.Logout:BAAANQADCgQIBAAAAA==.',
Lu='Luthais:BAAANQADCggIEAAAAA==.Luxury:BAAANQAECgEIAQAAAA==.',
Ly='Lykanthropos:BAAANQADCgUICgAAAA==.',
Ma='Magmabeard:BAAANQADCggICwAAAA==.Maingauche:BAAANQAECgQIBQAAAA==.Mako:BAAANQAECgMIBQAAAA==.Malevian:BAAANQADCgYIFgAAAA==.Malfuridan:BAAANQADCgMIAwAAAA==.Maples:BAAANQAECgUICAAAAA==.Mariasha:BAAANQADCgQIBAAAAA==.Marichika:BAAANQADCggICAAAAA==.Mazz:BAAANQAECgQIBAAAAA==.',
Me='Megaterium:BAAANQAECgEIAQAAAA==.Meláni:BAAANQADCgUICQAAAA==.Menethil:BAAANQADCggIEwAAAA==.',
Mi='Milei:BAAANQADCgYIDgAAAA==.Missmisery:BAAANQAECgIIAgAAAA==.Mistaya:BAAANQADCggIDAAAAA==.Mithdraug:BAAANQADCgYIDAAAAA==.',
Mo='Modrem:BAAANQABCgYICwAAAA==.Monache:BAAANQAECgEIAQAAAA==.Mongalf:BAAANQABCgQICAAAAA==.Moocheala:BAAANQADCgMIAwAAAA==.Mortarîon:BAAANQADCgQIBQAAAA==.',
Ms='Msdktank:BAAANQADCgIIAgAAAA==.',
My='Mystiqwolf:BAAANQADCgIIAgAAAA==.Mythrilblade:BAAANQADCgQICAAAAA==.',
Ni='Nightparade:BAAANQADCggIEAAAAA==.Nishgrail:BAAANQAECgQIBgAAAA==.',
Nu='Nukusmaximus:BAAANQADCgcIDQAAAA==.',
Ny='Nyxiie:BAAANQABCgYIBwAAAA==.',
Od='Odioz:BAAANQAECgEIAQAAAA==.',
On='Onex:BAAANQADCggIEAAAAA==.',
Or='Ori:BAAANQADCgUIBQAAAA==.',
Oz='Ozmo:BAAANQADCgQIBAAAAA==.',
Pa='Pawmasutra:BAAANQAECgIIAgAAAA==.',
Pe='Pencil:BAAANQAECgEIAgAAAA==.Persefini:BAAANQADCggIEAAAAA==.Petrodrak:BAAANQADCgUICgAAAA==.',
Ph='Pheylan:BAAANQADCggIEAAAAA==.',
Pl='Plugadin:BAAANQADCgUIBQAAAA==.Plugugly:BAAANQAECgMIBAAAAA==.',
Po='Polinemarois:BAAANQADCgUIAwAAAA==.Portal:BAAANQADCgIIAgABNQADCgcIEAABAAAAAA==.Potatobear:BAAANQAECgQIBgAAAA==.',
Pr='Praytwothee:BAAANQAECgIIAwAAAA==.',
Qu='Quickbow:BAAANQADCgUIBQAAAA==.Quicktime:BAAANQAECgQIBwAAAA==.',
Ra='Ragedh:BAAANQAECgIIBQABNQAECgMIAwABAAAAAA==.Ragequit:BAAANQAECgYIBAAAAA==.Ragnoir:BAAANQADCggIDgAAAA==.Rased:BAAANQAECgEIAQAAAA==.',
Re='Reeses:BAEANQADCgQIBAAAAA==.',
Ro='Roglof:BAAANQAECggICAAAAA==.Rowlah:BAAANQADCgQIBAAAAA==.Rozy:BAAANQAECgcIDwAAAA==.',
Ru='Ruiizu:BAAANQADCggIDgAAAA==.Rushuna:BAAANQAECgIIAwAAAA==.',
Sa='Saberjaw:BAAANQAECgIIAgAAAA==.Sairicck:BAAANQAECgUIBgAAAA==.Santamorte:BAAANQADCgMIAwAAAA==.Sarauco:BAAANQADCgQIBAAAAA==.Sarcasticus:BAAANQADCggIEAAAAA==.',
Se='Selenar:BAAANQADCggICAAAAA==.Selinora:BAAANQAECgEIAgAAAA==.Serhalatath:BAAANQADCggIDwAAAA==.',
Sh='Shade:BAAANQADCgcIEAAAAA==.Shadowsbane:BAAANQAECgQIBgAAAA==.Shaguar:BAAANQADCggIDgAAAA==.Shamwow:BAAANQAECgMIBQAAAA==.Shaolinsnake:BAAANQADCggIEAAAAA==.Shemonkk:BAAANQADCgUIBQAAAA==.Shiftshow:BAAANQAECgIIAgAAAA==.Shinukagé:BAAANQAECgIIAgAAAA==.',
Si='Singe:BAAANQAECgMIBQAAAA==.',
Sk='Skeetsurfin:BAAANQABCgIIAgAAAA==.',
Sl='Sloppyjo:BAAANQAECgIIAgAAAA==.',
Sm='Smallblackdk:BAAANQADCgEIAQAAAA==.',
So='Solenne:BAAANQADCgcIBwABNQAECgQIBwABAAAAAA==.Solsti:BAAANQAECgQIBwAAAA==.Soulhunter:BAAANQAECgcIDAAAAA==.',
Sp='Spears:BAAANQADCggIFAAAAA==.Spoondot:BAAANQAECgMIAwAAAA==.',
St='Stillhorn:BAAANQADCgQIBAAAAA==.Stinjaga:BAAANQADCggIDgAAAA==.Strglsngls:BAAANQADCgIIAgAAAA==.',
Su='Sunrae:BAAANQADCgcIDwAAAA==.',
Sy='Sylinsor:BAAANQAECgIIAgAAAA==.Symor:BAAANQADCgUICgAAAA==.Syxmoo:BAAANQAECgEIAQAAAA==.',
Ta='Taproot:BAEANQADCgcIBwABNQAECgYIDAABAAAAAA==.Taryen:BAAANQAECgMIAwAAAA==.',
Te='Telaari:BAAANQAECgMIAwAAAA==.Teriyl:BAAANQAECgMIAwAAAA==.',
Th='Thalenia:BAAANQAECgMIBQAAAA==.Thalron:BAAANQADCgYICgAAAA==.Thargrim:BAAANQABCgIIAgAAAA==.',
Ti='Tikeidari:BAAANQAECgUICgAAAA==.Tiltedtroll:BAAANQADCggIDAAAAA==.',
To='Tonofcron:BAAANQADCgUICAAAAA==.Totemeri:BAAANQAECgQIBQAAAA==.',
Tr='Trappydk:BAAANQAECgIIAgAAAA==.',
Ug='Uglyplug:BAAANQADCgIIAgAAAA==.',
Un='Unagi:BAAANQADCggIFQAAAA==.',
Va='Valezeal:BAAANQADCgcICQAAAA==.Vazdun:BAAANQAECgEIAgAAAA==.',
Ve='Velari:BAAANQADCgQIBAAAAA==.Venan:BAAANQADCgYIBwAAAA==.Venefirous:BAAANQADCgUIBgAAAA==.Venenn:BAAANQADCgUIBgAAAA==.Venev:BAAANQADCgUICAAAAA==.Ventana:BAAANQADCgcIDQAAAA==.Verdilac:BAAANQADCgQIBAABNQAECgUIDgABAAAAAA==.',
Vi='Vinceglortho:BAAANQADCgUIBwAAAA==.',
Vl='Vlad:BAAANQADCgIIAgAAAA==.',
Vy='Vyranox:BAAANQAECgMIBQAAAA==.',
Wa='Wanji:BAAANQADCggIDgAAAA==.',
Wi='Wildthangz:BAAANQADCgEIAQAAAA==.Wintyr:BAAANQADCgUICgAAAA==.',
Xa='Xaharst:BAAANQAECgIIAgAAAA==.Xaya:BAAANQAECgMIBQAAAA==.',
Xe='Xenophorge:BAAANQADCgcICgAAAA==.',
Xi='Xiurong:BAAANQADCgUIBQAAAA==.',
Xo='Xovace:BAAANQADCggIDQAAAA==.',
Xt='Xtayse:BAAANQAECgMIAwAAAA==.',
Yi='Yirya:BAAANQAECgQIBgAAAA==.',
Yo='Yoruechi:BAAANQAECgMIBQAAAA==.Youroverlord:BAAANQADCggICAAAAA==.',
['Yú']='Yúmyúm:BAAANQABCgMIAwAAAA==.',
Za='Zahel:BAAANQAECgQICgAAAA==.Zavier:BAAANQAECgMIAwAAAA==.',
Ze='Zebajin:BAAANQADCggICAAAAA==.Zeppola:BAAANQADCgcIEQAAAA==.',
Zh='Zhee:BAAANQADCggIEAAAAA==.',
Zo='Zobi:BAAANQADCgUICgAAAA==.Zomboo:BAAANQAECgYIDAAAAA==.',
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
