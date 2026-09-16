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

local lookup = {'Unknown-Unknown','Evoker-Augmentation','Evoker-Preservation','Rogue-Assassination','Priest-Shadow','Paladin-Holy','Druid-Balance',}
local provider = {region='US',realm='Uther',name='US',type='weekly',zone=53,date='2026-09-15',data={Ae='Aelithsong:BAAANQADCggICQABNQADCgcICwABAAAAAA==.',
Ah='Aha:BAAANQADCgYICAAAAA==.',
Ai='Aiax:BAAANQAECgUIDAAAAA==.',
Al='Alderok:BAAANQADCgcIBwABNQAECgQIBAABAAAAAA==.Aliancia:BAAANQAECgQIBQAAAA==.Alydin:BAAANQAECgQIBAAAAA==.',
Am='Amynle:BAAANQADCgcIDQAAAA==.',
An='Anerius:BAAANQABCgMIAwAAAA==.Annora:BAAANQAECgYIDAAAAA==.Antonious:BAAANQAECgEIAQAAAA==.',
Ap='Apollyon:BAAANQAECgYIDgAAAA==.',
Ar='Ari:BAAANQAECgQICAAAAA==.Ariioch:BAAANQAECgEIAQAAAA==.',
As='Assclapiuss:BAAANQAECgYIEAAAAA==.Asterchades:BAAANQAECgYIEAAAAA==.Asteriou:BAAANQADCgUIBgAAAA==.',
At='Attikus:BAAANQAECgUICwAAAA==.Atuan:BAAANQAECgEIAQAAAA==.',
Au='Auralass:BAAANQADCgcIFgAAAA==.Autauga:BAAANQAECgMIAwAAAA==.',
Av='Avilla:BAAANQAECgQIBwAAAA==.',
Ax='Axem:BAAANQAECgUICgAAAA==.',
Az='Azulathan:BAAANQAECgEIAQAAAA==.',
Be='Bechett:BAAANQAECgMIBgAAAA==.Beep:BAAANQAECgIIAgAAAA==.Beerguy:BAAANQADCgMIAwAAAA==.Behemothe:BAAANQAECgYIEAAAAA==.Berníesandrs:BAAANQAECgEIAQAAAA==.Beryllos:BAAANQADCgUICwAAAA==.Bewzey:BAAANQAECgQIBwAAAA==.',
Bi='Bittiesxo:BAAANQABCgcICwAAAA==.',
Bl='Bledana:BAAANQADCgQIBAAAAA==.Bloodmourne:BAAANQAECgQIBAAAAA==.Bloodytoutii:BAAANQAECgEIAgAAAA==.',
Bo='Bortman:BAAANQAECgYIBwAAAA==.Bowowner:BAAANQAECgQIBAAAAA==.',
Bu='Buhbul:BAAANQAECgQIBQAAAA==.Buzzball:BAAANQAECgIIAgAAAA==.',
Bw='Bwicked:BAAANQAECgQICQAAAA==.',
Ca='Caroline:BAAANQADCgQIBAAAAA==.',
Ce='Celonge:BAAANQADCggIEAABNQAECgYIDwABAAAAAA==.',
Ch='Chamelean:BAAANQADCgUIBQABNQAECgMIBwABAAAAAA==.Chimpnzthat:BAAANQADCgcIFgAAAA==.Chookicookie:BAAANQAECgYICwAAAA==.Chrome:BAAANQAECgYIEAAAAA==.',
Ci='Cindyy:BAAANQAECgIIAgAAAA==.Cini:BAAANQADCgEIAQAAAA==.Cirí:BAAANQAECgUICgAAAA==.',
Co='Coldbeans:BAAANQAECgEIAQAAAA==.Coresh:BAAANQAECgYIDgAAAA==.Cornpuff:BAAANQADCggIEAAAAA==.',
Cr='Crickets:BAAANQAECgMIBAAAAA==.Crucifixx:BAAANQADCgQIBAAAAA==.',
Cu='Cupsandcakes:BAAANQAECgIIAgAAAA==.',
Da='Dacarry:BAAANQAECgQIBAAAAA==.Dadbody:BAAANQADCgUIBQABNQAECgYIEAABAAAAAA==.Dark:BAAANQAECgYIEAAAAA==.Darkphyre:BAAANQAECgEIAQAAAA==.',
De='Deadloc:BAAANQADCggIEwAAAA==.Deadmandan:BAAANQAECgYIDgAAAA==.Deathtike:BAAANQAECgUICwABNQAECgYIEAABAAAAAA==.Decius:BAAANQAECgEIAQAAAA==.Deltairlines:BAABNQAECoEZAAMCAAkJcSGJAQAiAwACAAkJcSGJAQAiAwADAAkJNhGdDgA7AgAAAA==.Demagorgin:BAAANQAECgIIAwAAAA==.Deqlyn:BAAANQAECgYICQAAAA==.Desmus:BAAANQADCgcIFAAAAA==.Devilmaycry:BAAANQADCgUIBQAAAA==.Deáthreaver:BAAANQAECgUICgAAAA==.',
Di='Diddyy:BAAANQAECgMIBAABNQAECgQIBAABAAAAAA==.',
Do='Domwarlock:BAAANQAECgcICgAAAA==.Dots:BAAANQAECgQIBAAAAA==.Doublehungus:BAAANQABCgMIAwAAAA==.',
Dr='Dronin:BAAANQAECgQIBwAAAA==.Drpatan:BAAANQADCggIFgAAAA==.Druni:BAAANQAECgEIAQAAAA==.Drâkenhân:BAAANQAECgEIAQAAAA==.',
Du='Dumpling:BAAANQADCgMIAwAAAA==.Durango:BAAANQADCgUIDAAAAA==.',
Ec='Echowalker:BAAANQADCggIFQAAAA==.',
Ed='Edinburger:BAAANQADCgMIAwAAAA==.',
Ei='Eirya:BAAANQABCgEIAQAAAA==.',
Em='Emokillaz:BAAANQADCgcIBwAAAA==.',
Ep='Epsilón:BAAANQADCgcICwAAAA==.',
Es='Esmerr:BAAANQADCggIHwAAAA==.',
Fa='Faxon:BAAANQAECgQIBwAAAA==.',
Fe='Feronnia:BAAANQADCgUICwAAAA==.',
Fi='Fibot:BAAANQAECgYIEAAAAA==.Fireboürne:BAAANQAECgIIAgAAAA==.Fireishot:BAAANQAECgMIAwAAAA==.',
Fl='Florasol:BAAANQADCgYIEgAAAA==.',
Fr='Fraeyah:BAAANQADCgUIBgAAAA==.Friede:BAAANQAECgQIBgAAAA==.',
['Fè']='Fènrys:BAAANQADCgYICgAAAA==.',
Ga='Galvanize:BAEANQAECgcIEwAAAA==.',
Ge='Geewetsya:BAAANQAECgEIAQAAAA==.Gengarr:BAAANQADCgMIAwABNQAECgQIBAABAAAAAA==.',
Gh='Ghomertin:BAAANQADCgYIDgAAAA==.',
Gi='Gipsydanger:BAAANQAECgcIEAAAAA==.',
Gl='Gladiatrix:BAAANQADCgYIBgAAAA==.Glofor:BAAANQADCgUIBQABNQAECggICAABAAAAAA==.',
Go='Gonnjass:BAAANQADCgYIEAAAAA==.Gorlokk:BAEANQADCgEIAQABNQADCgQIBAABAAAAAA==.',
Gr='Grakonys:BAAANQAECgYIDAAAAA==.Greed:BAAANQAECgUICQAAAA==.Grimmbot:BAAANQAECgQIBAAAAA==.Grunch:BAAANQADCgQIBAAAAA==.Grunnck:BAAANQADCgYICwAAAA==.',
Gu='Guayusa:BAAANQAECgIIAgAAAA==.',
Ha='Harnix:BAAANQADCgYICwAAAA==.Hawtbooty:BAAANQAECgUIBwAAAA==.Hazuul:BAAANQABCgQIBAABNQAECgIIAgABAAAAAA==.',
He='Hellreines:BAAANQAECgcIDAAAAA==.Hemolythria:BAAANQADCgIIAgAAAA==.',
Hi='Hildi:BAAANQADCgcIFQAAAA==.Him:BAAANQAECgUICwAAAA==.',
Ho='Holy:BAAANQAECgUIDAAAAA==.Hotmess:BAAANQADCgUIBwAAAA==.Hottopic:BAAANQABCgQIBAAAAA==.',
Hu='Hurcules:BAAANQABCgEIAQAAAA==.',
Ic='Icespirit:BAAANQABCgEIAQAAAA==.',
Il='Illidaris:BAAANQADCgYIBgAAAA==.',
Ir='Irintha:BAAANQABCgMIAwAAAA==.',
Is='Ishura:BAAANQADCgcIDQAAAA==.',
It='Itslevi:BAAANQAECgMIAwAAAA==.',
Iv='Ivvy:BAAANQAECgIIAgAAAA==.',
Iz='Izanami:BAAANQADCgcIDwAAAA==.',
Ja='Jaffer:BAABNQAECoEQAAIEAAcJSQUhIQBlAQAEAAcJSQUhIQBlAQAAAA==.Janntro:BAAANQAECgUICgAAAA==.Jantra:BAAANQADCgQIBAABNQAECgUICgABAAAAAA==.Jantro:BAAANQAECgQIBgABNQAECgUICgABAAAAAA==.Janttro:BAAANQAECgMIAwABNQAECgUICgABAAAAAA==.',
Je='Jebby:BAAANQAECgYIBgAAAA==.Jeebz:BAAANQAECgUICAABNQAECgYIBgABAAAAAA==.Jelmarr:BAAANQADCgUICwAAAA==.Jerauld:BAAANQADCgcIFgAAAA==.',
Ji='Jimmyhoffá:BAAANQAECgEIAQAAAA==.',
Jo='Johnnyzyns:BAAANQAECggIBAAAAA==.Joshc:BAAANQAECgQIBAAAAA==.',
Ju='Judgédred:BAAANQADCgYIBgAAAA==.',
['Já']='Ják:BAAANQAECgQIBAAAAA==.',
Ka='Kaaris:BAAANQAECgMIBQAAAA==.Kaiarie:BAAANQADCgcIFQAAAA==.Kainraziel:BAAANQAECgMIBwAAAA==.Kairos:BAAANQAECgYIEAAAAA==.Kanofworms:BAAANQAECgEIAQAAAA==.Karkea:BAAANQAECgQIBAAAAA==.',
Ke='Kebin:BAAANQAECgQIBgAAAA==.',
Ki='Kibil:BAAANQAECgQIBwAAAA==.',
Ko='Korax:BAAANQADCgUIBAAAAA==.Kortharion:BAAANQAECgQIBAAAAA==.Kos:BAABNQAECoEXAAIFAAkJQCVvAQC+AwAFAAkJQCVvAQC+AwAAAA==.',
Kr='Krule:BAAANQADCgYIBgABNQAECgUICgABAAAAAA==.',
Ku='Kujiera:BAAANQAECgIIAgAAAA==.Kurick:BAAANQAECgEIAQAAAA==.Kurrenter:BAAANQAECgQIBwAAAA==.',
['Ká']='Kárgorr:BAAANQADCgQIBgAAAA==.',
['Kÿ']='Kÿtten:BAAANQAECgYIDQAAAA==.',
La='Laiyth:BAAANQAECgUICAAAAA==.Larryfish:BAAANQAECgQIBwAAAA==.Lavos:BAAANQAECgYICwAAAA==.',
Le='Levitikus:BAAANQAECgEIAQAAAA==.',
Li='Lisster:BAAANQAECgYIBAAAAA==.Liyra:BAAANQAECgUIBQAAAA==.',
Lo='Loafe:BAAANQAECgYICwAAAA==.Logout:BAAANQADCgQIBAAAAA==.',
Lu='Luthais:BAAANQAECgEIAQAAAA==.Luxury:BAAANQAECgQIBAAAAA==.',
Ly='Lykanthropos:BAAANQADCgUIDAAAAA==.',
Ma='Magmabeard:BAAANQADCggICwAAAA==.Maingauche:BAAANQAECgUICgAAAA==.Mako:BAAANQAECgcIDAAAAA==.Malevian:BAAANQADCgYIFgAAAA==.Malfuridan:BAAANQADCgMIAwAAAA==.Malocki:BAAANQABCgEIAQAAAA==.Maples:BAAANQAECgYIDgAAAA==.Mariasha:BAAANQADCgQIBAAAAA==.Marichika:BAAANQADCggICAAAAA==.Mazz:BAAANQAECgQICAAAAA==.',
Me='Megaterium:BAAANQAECgIIAwAAAA==.Meláni:BAAANQADCgYIDwAAAA==.Menethil:BAAANQAECgEIAQAAAA==.',
Mi='Milei:BAAANQAECgEIAQAAAA==.Missmisery:BAAANQAECgQIBgAAAA==.Mistaya:BAAANQAECgMIAwAAAA==.Mithdraug:BAAANQAECgEIAQAAAA==.',
Mo='Modrem:BAAANQADCgMIAwAAAA==.Monache:BAAANQAECgQIBQAAAA==.Mongalf:BAAANQABCgQICAAAAA==.Moocheala:BAAANQADCgMIAwAAAA==.Mortarîon:BAAANQADCgQIBQAAAA==.',
Ms='Msdktank:BAAANQADCgIIAgAAAA==.',
My='Mystiqwolf:BAAANQADCgIIAgAAAA==.Mythrilblade:BAAANQADCgQICAAAAA==.Myzeel:BAAANQABCgMIAwAAAA==.',
Ni='Nightparade:BAAANQAECgEIAQAAAA==.Nishgrail:BAAANQAECgYIDAAAAA==.',
No='Nohkal:BAAANQADCgcIBgAAAA==.',
Nu='Nukusmaximus:BAAANQADCgcIFAAAAA==.',
Ny='Nyxiie:BAAANQABCgYICQAAAA==.',
Od='Odioz:BAAANQAECgYIBwAAAA==.',
Ok='Oktharun:BAAANQADCggICAAAAA==.',
On='Onex:BAAANQAECgEIAQAAAA==.',
Or='Ori:BAAANQADCggICwAAAA==.',
Oz='Ozmo:BAAANQADCgQIBAAAAA==.',
Pa='Pawmasutra:BAAANQAECgIIBAAAAA==.',
Pe='Pencil:BAAANQAECgEIBAAAAA==.Persefini:BAAANQAECgEIAQAAAA==.Petrodrak:BAAANQADCgcIDwAAAA==.',
Ph='Pheylan:BAAANQAECgEIAQAAAA==.Phløw:BAAANQADCgQIBAAAAA==.',
Pl='Plugadin:BAAANQADCgUIBQAAAA==.Plugugly:BAAANQAECgQICAAAAA==.',
Po='Polinemarois:BAAANQADCgUIAwAAAA==.Portal:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Potatobear:BAAANQAECgYIDAAAAA==.',
Pr='Praytwothee:BAAANQAECgUICAAAAA==.',
Qu='Quickbow:BAAANQADCgUIBQAAAA==.Quicktime:BAAANQAECgUIDAAAAA==.',
Ra='Ragedh:BAAANQAECgQICwAAAA==.Ragequit:BAAANQAECgYIBAAAAA==.Ragnoir:BAAANQAECgQIBAAAAA==.Rased:BAAANQAECgEIAQAAAA==.Ravensblood:BAAANQADCgEIAQAAAA==.Rawdøg:BAAANQAECgEIAQAAAA==.',
Re='Reddfire:BAAANQADCggICAAAAA==.Reeses:BAEANQADCgQIBAAAAA==.',
Ro='Roglof:BAAANQAECggICAAAAA==.Rowlah:BAAANQADCgUICQAAAA==.Rozy:BAABNQAECoEZAAIGAAgJbxZnJgA8AgAGAAgJbxZnJgA8AgAAAA==.',
Ru='Ruiizu:BAAANQAECgQIBAAAAA==.Rushuna:BAAANQAECgYICQAAAA==.',
Sa='Saberjaw:BAAANQAECgYICAAAAA==.Sairicck:BAAANQAECgUICgAAAA==.Santamorte:BAAANQADCgMIAwAAAA==.Sarauco:BAAANQADCgQIBAAAAA==.Sarcasticus:BAAANQAECgEIAQAAAA==.',
Se='Selenar:BAAANQADCggICAAAAA==.Selinora:BAAANQAECgEIAwAAAA==.Serhalatath:BAAANQAECgEIAQAAAA==.',
Sh='Shade:BAAANQAECgIIAgAAAA==.Shadowsbane:BAAANQAECgQICgAAAA==.Shaguar:BAAANQAECgQIBAAAAA==.Shamhawk:BAAANQADCgMIAwABNQAECgQIBAABAAAAAA==.Shamwow:BAAANQAECgYICwAAAA==.Shaolinsnake:BAAANQAECgEIAQAAAA==.Shemonkk:BAAANQADCgUIBwAAAA==.Shiftshow:BAAANQAECgIIAgAAAA==.Shinukagé:BAAANQAECgIIAgAAAA==.Shizzite:BAAANQADCggICAAAAA==.',
Si='Singe:BAAANQAECgYICwAAAA==.',
Sk='Skeetsurfin:BAAANQABCgIIAgAAAA==.',
Sl='Sloppyjo:BAAANQAECgQIBgAAAA==.',
Sm='Smallblackdk:BAAANQADCgEIAQAAAA==.',
So='Solenne:BAAANQADCgcIBwABNQAECgYIDwABAAAAAA==.Solsti:BAAANQAECgYIDwAAAA==.Soulhunter:BAAANQAECgcIDwAAAA==.',
Sp='Spears:BAAANQAECgEIAQAAAA==.Spoondot:BAAANQAECgMIAwAAAA==.',
St='Stillhorn:BAAANQADCgUIBAAAAA==.Stinjaga:BAAANQAECgQIBAAAAA==.Strglsngls:BAAANQADCgIIAgAAAA==.',
Su='Sunrae:BAAANQADCgcIFgAAAA==.',
Sy='Sylinsor:BAAANQAECgIIAgAAAA==.Symor:BAAANQADCgUIDAAAAA==.Syxmoo:BAAANQAECgEIAgAAAA==.',
Ta='Taproot:BAEANQADCgcIDgABNQAECgcIEwABAAAAAA==.Taryen:BAAANQAECgQIBwABNQAECgQICwABAAAAAA==.',
Te='Telaari:BAAANQAECgMIAwAAAA==.Teriyl:BAAANQAECgMIBgAAAA==.',
Th='Thalenia:BAAANQAECgYICwAAAA==.Thalron:BAAANQAECgEIAQAAAA==.Thargrim:BAAANQADCgIIAgAAAA==.',
Ti='Tikeidari:BAAANQAECgYIEAAAAA==.Tiltedtroll:BAAANQAECgQIBAAAAA==.',
To='Tonofcron:BAAANQADCgUIDQAAAA==.Totemeri:BAAANQAECgYICwAAAA==.',
Tr='Trappydk:BAAANQAECgUIBwAAAA==.',
Ug='Uglyplug:BAAANQADCgIIAgAAAA==.',
Un='Unagi:BAAANQAECgIIAgAAAA==.',
Va='Valezeal:BAAANQADCgcICwAAAA==.Vazdun:BAAANQAECgQIBgAAAA==.',
Ve='Velari:BAAANQADCgQIBAAAAA==.Vemazan:BAAANQABCgIIAgAAAA==.Venan:BAAANQADCgYIBwAAAA==.Venefirous:BAAANQADCgUIBgAAAA==.Venenn:BAAANQADCgUICgAAAA==.Venev:BAAANQADCggIDgAAAA==.Ventana:BAAANQAECgQIBAAAAA==.Verdilac:BAAANQADCgQIBAABNQAECggIHwAHAM8XAA==.',
Vi='Vinceglortho:BAAANQADCgUICQAAAA==.',
Vl='Vlad:BAAANQADCgIIAgAAAA==.',
Vy='Vyranox:BAAANQAECgYICwAAAA==.',
Wa='Wanji:BAAANQAECgQIBAAAAA==.',
Wi='Widginatrix:BAAANQADCgYIBgAAAA==.Wildthangz:BAAANQAECgEIAQAAAA==.Wintyr:BAAANQADCgUIDAAAAA==.',
Xa='Xaharst:BAAANQAECgIIBAAAAA==.Xaya:BAAANQAECgQIBgAAAA==.',
Xe='Xenophorge:BAAANQADCgcIEAAAAA==.',
Xi='Xiurong:BAAANQADCgcICwAAAA==.',
Xo='Xovace:BAAANQAECgEIAQAAAA==.',
Xt='Xtayse:BAAANQAECgMIBgAAAA==.',
Yi='Yirya:BAAANQAECgQIDAAAAA==.',
Yo='Yoruechi:BAAANQAECgYICwAAAA==.Youroverlord:BAAANQADCggICAAAAA==.',
['Yú']='Yúmyúm:BAAANQABCgcICgAAAA==.',
Za='Zahel:BAAANQAECgYIEAAAAA==.Zavier:BAAANQAECgQIBAAAAA==.',
Ze='Zebajin:BAAANQAECgQIBAAAAA==.Zeppola:BAAANQADCgcIFwAAAA==.',
Zh='Zhee:BAAANQAECgEIAQAAAA==.',
Zo='Zobi:BAAANQADCgUIDAAAAA==.Zomboo:BAAANQAECgcIDQAAAA==.',
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
