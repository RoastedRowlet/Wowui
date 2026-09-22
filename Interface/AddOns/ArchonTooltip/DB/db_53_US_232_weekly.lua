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

local lookup = {'Unknown-Unknown','Paladin-Retribution','Paladin-Holy','Druid-Guardian','Shaman-Enhancement','Mage-Arcane','Druid-Balance','Druid-Restoration','Warlock-Demonology','Warlock-Destruction','DemonHunter-Vengeance','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Priest-Holy','Priest-Discipline','Rogue-Assassination','Priest-Shadow','Paladin-Protection','Monk-Mistweaver',}
local provider = {region='US',realm='Uther',name='US',type='weekly',zone=53,date='2026-09-22',data={Ae='Aelithsong:BAAANQAECgIJAgABNQADCgcICwABAAAAAA==.',
Ah='Aha:BAAANQADCgYICAAAAA==.',
Ai='Aiax:BAAANQAECgUIDAAAAA==.',
Al='Alderok:BAAANQADCgcIBwABNQAECgUIBQABAAAAAA==.Aliancia:BAAANQAECgQICQAAAA==.Alydin:BAAANQAECgQJBAAAAA==.',
Am='Amynle:BAAANQADCgcIDQAAAA==.',
An='Anerius:BAAANQABCgMIAwAAAA==.Annora:BAAANQAECgcJEwAAAA==.Antonious:BAAANQAECgEJAQAAAA==.',
Ap='Apollyon:BAAANQAECgcIEwAAAA==.',
Ar='Ari:BAAANQAECgQIDAAAAA==.Ariioch:BAAANQAECgEIAQAAAA==.',
As='Assclapiuss:BAABNQAECoEYAAMCAAgK0iMvFgApAwACAAgK0iMvFgApAwADAAQKlwxMlQDcAAAAAA==.Asterchades:BAABNQAECoEaAAIEAAgK7xKYDADSAQAEAAgK7xKYDADSAQAAAA==.Asteriou:BAAANQAECgIIAwAAAA==.',
At='Attikus:BAAANQAECgcJEgAAAA==.Atuan:BAAANQAECgEJAQAAAA==.',
Au='Auralass:BAAANQADCgcIHQAAAA==.Autauga:BAAANQAECgQIBAAAAA==.',
Av='Avatard:BAAANQAECgMIAwABNQAECgcJEgABAAAAAA==.Avilla:BAAANQAECgUIDAAAAA==.',
Ax='Axem:BAAANQAECgcJEQAAAA==.',
Az='Azulathan:BAAANQAECgMJBAAAAA==.',
Ba='Bangpewpew:BAAANQADCgQJBAAAAA==.',
Be='Bechett:BAAANQAECgcIDQAAAA==.Beep:BAAANQAECgIIAgAAAA==.Beerguy:BAAANQADCgMIAwAAAA==.Behemothe:BAABNQAECoEaAAIFAAgKiBU6CgByAgAFAAgKiBU6CgByAgAAAA==.Berníesandrs:BAAANQAECgQJBQAAAA==.Beryllos:BAAANQADCgYJEQAAAA==.Bewzey:BAAANQAECgUIDAAAAA==.',
Bi='Bittiesxo:BAAANQABCgcICwAAAA==.',
Bl='Bledana:BAAANQADCgQIBAAAAA==.Bloodmourne:BAAANQAECgUJCQAAAA==.Bloodytoutii:BAAANQAECgIJAwAAAA==.',
Bo='Bortman:BAAANQAECgcJDgAAAA==.Bowowner:BAAANQAECgUJBQAAAA==.',
Bu='Buhbul:BAAANQAECgQJCAAAAA==.Buzzball:BAAANQAECgQIBgAAAA==.',
Bw='Bwicked:BAAANQAECgYJDwAAAA==.',
Ca='Caroline:BAAANQADCgQJBAAAAA==.',
Ce='Celonge:BAAANQAECgQIBAABNQAECggJGQADABMTAA==.Ceremony:BAEANQADCgUJBQABNQAECggIHwAGAGkSAA==.',
Ch='Chamelean:BAAANQADCgUIBQABNQAECgUIDAABAAAAAA==.Chimpnzthat:BAAANQAECgEIAQAAAA==.Chookicookie:BAAANQAECgcIEwAAAA==.Chrome:BAABNQAECoEaAAMHAAgKMBu/JQA7AgAHAAcKmxq/JQA7AgAIAAcKLBltFgAJAgAAAA==.',
Ci='Cindyy:BAAANQAECgcICAAAAA==.Cini:BAAANQADCgEIAQAAAA==.Cirí:BAAANQAECgYIEAAAAA==.',
Co='Coldbeans:BAAANQAECgEIAQAAAA==.Coresh:BAABNQAECoEYAAIFAAgKhxnbCACXAgAFAAgKhxnbCACXAgAAAA==.Cornpuff:BAAANQADCggIEAAAAA==.',
Cr='Crickets:BAAANQAECgMIBAAAAA==.Crucifixx:BAAANQADCgYICgAAAA==.',
Cu='Cupsandcakes:BAAANQAECgIIAgAAAA==.',
Da='Dacarry:BAAANQAECgQIBAAAAA==.Dadbody:BAAANQAECgQJBAABNQAECggIGAACANIjAA==.Dark:BAABNQAECoEZAAIJAAgKGSEAEwD4AgAJAAgKGSEAEwD4AgAAAA==.Darkphyre:BAAANQAECgEJAQAAAA==.',
De='Deadloc:BAAANQADCggIEwAAAA==.Deadmandan:BAABNQAECoEaAAMJAAkK0SKkBAB/AwAJAAkK0SKkBAB/AwAKAAEK+h0LWQBOAAAAAA==.Deathtike:BAAANQAECgYIEQABNQAECggIGgALAFwdAA==.Decius:BAAANQAECgEJAQAAAA==.Deltairlines:BAACNQAFFIEHAAMMAAQKgxkQAgBiAQAMAAQKgxkQAgBiAQANAAEKXgD6EAAoAAA1AAQKgR4ABAwACQqTIdkBACkDAAwACQqTIdkBACkDAA0ACQo2EW0SAC4CAA4AAQqBDY4sAD4AAAAA.Deltayaya:BAAANQAECggICAABNQAFFAQIBwAMAIMZAA==.Demagorgin:BAAANQAECgQIBgAAAA==.Deqlyn:BAAANQAECgcJEAAAAA==.Desmus:BAAANQAECgEIAQAAAA==.Devilmaycry:BAAANQADCgUIBQAAAA==.Deáthreaver:BAAANQAECgYIEAAAAA==.',
Di='Diddyy:BAAANQAECgMJBAABNQAECgQIBAABAAAAAA==.',
Do='Domwarlock:BAAANQAECgcIEAAAAA==.Dots:BAAANQAECgQIBAAAAA==.Doublehungus:BAAANQABCgQIBAAAAA==.',
Dr='Dronin:BAAANQAECgUJDAAAAA==.Drpatan:BAAANQAECgMIAwAAAA==.Druni:BAAANQAECgEJAQAAAA==.Drâkenhân:BAAANQAECgEIAQAAAA==.',
Du='Dumpling:BAAANQADCgMIAwAAAA==.Durango:BAAANQADCgYJEgAAAA==.',
Ec='Echowalker:BAAANQADCggJHAAAAA==.',
Ed='Edinburger:BAAANQADCgUICAAAAA==.',
Eh='Ehdawg:BAAANQAECgEJAQAAAA==.',
Ei='Eirya:BAAANQADCgEIAQAAAA==.',
Em='Emokillaz:BAAANQADCgcIBwAAAA==.',
Ep='Epsilón:BAAANQADCgcICwAAAA==.',
Es='Esmerr:BAAANQADCggIHwAAAA==.',
Fa='Faxon:BAAANQAECgUIDAAAAA==.',
Fe='Feronnia:BAAANQADCgYJEQAAAA==.',
Fi='Fibot:BAABNQAECoEaAAIFAAgKiBDCDAA0AgAFAAgKiBDCDAA0AgAAAA==.Fireboürne:BAAANQAECgIIAgAAAA==.Fireishot:BAAANQAECgMIBQAAAA==.',
Fl='Florasol:BAAANQADCgYIEgAAAA==.',
Fr='Fraeyah:BAAANQADCgUIBgAAAA==.Friede:BAAANQAECgQICAAAAA==.',
['Fè']='Fènrys:BAAANQADCgYICgAAAA==.',
Ga='Galvanize:BAEBNQAECoEfAAIGAAgKaRKcegAlAgAGAAgKaRKcegAlAgAAAA==.Gastbubble:BAAANQADCgQIBAAAAA==.',
Ge='Geewetsya:BAAANQAECgEJAgAAAA==.Gengarr:BAAANQADCgMIAwABNQAECgYICAABAAAAAA==.',
Gh='Ghomertin:BAAANQADCgcJFQAAAA==.',
Gi='Gipsydanger:BAABNQAECoEaAAMPAAgKqyHNDQARAwAPAAgKqyHNDQARAwAQAAIKKw2pFQBmAAAAAA==.',
Gl='Gladiatrix:BAAANQADCgYIBgAAAA==.Glofor:BAAANQADCgUIBQABNQAECggICQABAAAAAA==.',
Go='Gonnjass:BAAANQADCgYJEgAAAA==.Gorlokk:BAEANQADCgEIAQABNQADCgQIBAABAAAAAA==.',
Gr='Grakonys:BAAANQAECgcJDgAAAA==.Greed:BAAANQAECgUJCQAAAA==.Grimmbot:BAAANQAECgQICAAAAA==.Grunch:BAAANQADCgQIBAAAAA==.Grunnck:BAAANQADCggJEwAAAA==.',
Gu='Guayusa:BAAANQAECgIIAgAAAA==.',
Ha='Habb:BAAANQADCggICAAAAA==.Harnix:BAAANQADCgcIEgAAAA==.Hawtbooty:BAAANQAECgcJDgAAAA==.Hazuul:BAAANQABCgQIBAABNQAECgQIBgABAAAAAA==.',
He='Hellreines:BAAANQAECgcIEwAAAA==.Hemolythria:BAAANQADCgIIAgAAAA==.',
Hi='Hildi:BAAANQAECgEIAQAAAA==.Him:BAAANQAECgUJDwAAAA==.',
Ho='Holy:BAAANQAECgYIEgAAAA==.Hotmess:BAAANQADCgUIBwAAAA==.Hottopic:BAAANQABCgQJBAAAAA==.',
Hu='Hurcules:BAAANQABCgEIAQAAAA==.',
Ic='Icespirit:BAAANQABCgEIAQAAAA==.',
Il='Illidaris:BAAANQADCgYIBgAAAA==.',
Ir='Irintha:BAAANQABCgMIAwAAAA==.',
Is='Ishura:BAAANQAECgEIAQAAAA==.',
It='Itslevi:BAAANQAECgMIAwAAAA==.',
Iv='Ivvy:BAAANQAECgQIBQAAAA==.',
Iz='Izanami:BAAANQADCgcIDwAAAA==.',
Ja='Jaffer:BAABNQAECoESAAIRAAgKzAagKACSAQARAAgKzAagKACSAQAAAA==.Janntro:BAAANQAECgUICwAAAA==.Jantra:BAAANQADCgQIBAABNQAECgUICwABAAAAAA==.Jantro:BAAANQAECgUICwABNQAECgUICwABAAAAAA==.Janttro:BAAANQAECgUICAABNQAECgUICwABAAAAAA==.',
Je='Jebby:BAAANQAECgYIDAAAAA==.Jeebz:BAAANQAECgUICAABNQAECgYIDAABAAAAAA==.Jelmarr:BAAANQADCgYIEQAAAA==.Jerauld:BAAANQAECgEIAQAAAA==.',
Ji='Jimmyhoffá:BAAANQAECgEIAQAAAA==.',
Jo='Johnnyzyns:BAAANQAECggJCQAAAA==.Joshc:BAAANQAECgUICQAAAA==.',
Ju='Judgédred:BAAANQADCgYIBgAAAA==.',
['Já']='Ják:BAAANQAECgUJCQAAAA==.',
Ka='Kaaris:BAAANQAECgUICgAAAA==.Kaiarie:BAAANQAECgEIAQAAAA==.Kainraziel:BAAANQAECgUIDAAAAA==.Kairos:BAABNQAECoEaAAIGAAgKaA65iwD6AQAGAAgKaA65iwD6AQAAAA==.Kanofworms:BAAANQAECgMJBAAAAA==.Karkea:BAAANQAECgQICQAAAA==.',
Ke='Kebin:BAAANQAECgUICwAAAA==.',
Ki='Kibil:BAAANQAECgUIDAAAAA==.',
Ko='Koga:BAAANQABCgQJBAAAAA==.Korax:BAAANQADCgUIBAAAAA==.Kortharion:BAAANQAECgUJCQAAAA==.Kos:BAABNQAECoEZAAISAAkKQCVuAgCnAwASAAkKQCVuAgCnAwAAAA==.',
Kr='Krule:BAAANQADCgYIBgABNQAECgUICwABAAAAAA==.',
Ku='Kujiera:BAAANQAECgcJCQAAAA==.Kurick:BAAANQAECgMIAwAAAA==.Kurrenter:BAAANQAECgUIDAAAAA==.',
['Ká']='Kárgorr:BAAANQADCgQIBgAAAA==.',
['Kÿ']='Kÿtten:BAABNQAECoEVAAITAAgKYA6FGgCMAQATAAgKYA6FGgCMAQAAAA==.',
La='Laiyth:BAAANQAECgYJCwAAAA==.Larryfish:BAAANQAECgUIDAAAAA==.Lavos:BAAANQAECgcJEQAAAA==.',
Le='Levitikus:BAAANQAECgEIAQAAAA==.',
Li='Lisster:BAAANQAECgcJCQAAAA==.Liyra:BAAANQAECgUICgAAAA==.',
Lo='Loafe:BAAANQAECgcJEgAAAA==.Loennicus:BAAANQADCgQIBAAAAA==.Logout:BAAANQADCgQIBAAAAA==.',
Lu='Lurts:BAAANQADCgEIAQAAAA==.Luthais:BAAANQAECgEJAQAAAA==.Luxury:BAAANQAECgUICgAAAA==.',
Ly='Lykanthropos:BAAANQADCgYJEgAAAA==.',
Ma='Magmabeard:BAAANQADCggICwAAAA==.Maingauche:BAAANQAECgYJCwAAAA==.Mako:BAAANQAECgcIEgAAAA==.Malevian:BAAANQADCgYIGwAAAA==.Malfuridan:BAAANQADCgMIAwAAAA==.Malocki:BAAANQABCgMJAwAAAA==.Maples:BAABNQAECoEZAAIUAAgKiQk1FwB+AQAUAAgKiQk1FwB+AQAAAA==.Mariasha:BAAANQADCgQIBAAAAA==.Marichika:BAAANQADCggICAAAAA==.Mazz:BAAANQAECgQJCwAAAA==.',
Me='Megaterium:BAAANQAECgIJAwAAAA==.Meláni:BAAANQADCggIEQAAAA==.Menethil:BAAANQAECgEIAgAAAA==.',
Mi='Milei:BAAANQAECgEIAQAAAA==.Missmisery:BAAANQAECgUICwAAAA==.Mistaya:BAAANQAECgQICgAAAA==.Mithdraug:BAAANQAECgEJAQAAAA==.',
Mo='Modrem:BAAANQADCgUJCAAAAA==.Monache:BAAANQAECgQJBQAAAA==.Mongalf:BAAANQABCgYJCgAAAA==.Moocheala:BAAANQADCgMIAwAAAA==.Mortarîon:BAAANQADCgQIBQAAAA==.',
Ms='Msdktank:BAAANQADCgIIAgAAAA==.',
My='Mystiqwolf:BAAANQAECgQJBAAAAA==.Mythrilblade:BAAANQADCgQJCAAAAA==.Myzeel:BAAANQABCgMIAwAAAA==.',
Ni='Nightparade:BAAANQAECgEJAQAAAA==.Nishgrail:BAAANQAECgcJEwAAAA==.',
No='Nohkal:BAAANQADCgYIDAAAAA==.',
Nu='Nukusmaximus:BAAANQAECgEIAQAAAA==.',
Ny='Nyxiie:BAAANQADCgMIAwAAAA==.',
Od='Odioz:BAAANQAECgYICwAAAA==.',
On='Onex:BAAANQAECgEJAQAAAA==.',
Or='Ori:BAAANQAECgEJAQAAAA==.',
Oz='Ozmo:BAAANQADCgQIBAAAAA==.',
Pa='Palidinas:BAAANQADCgcIDAAAAA==.Pawmasutra:BAAANQAECgUICQAAAA==.',
Pe='Pencil:BAAANQAECgEJBgAAAA==.Persefini:BAAANQAECgEJAQAAAA==.Petrodaear:BAAANQADCgEJAQABNQADCggJFQABAAAAAA==.Petrodrak:BAAANQADCggJFQAAAA==.',
Ph='Pheylan:BAAANQAECgEJAQAAAA==.Philidox:BAAANQADCgYIBgABNQAECgUJCQABAAAAAA==.Phløw:BAAANQADCgQIBAAAAA==.',
Pl='Plugadin:BAAANQADCgUIBQAAAA==.Plugugly:BAAANQAECgUIDQAAAA==.',
Po='Polinemarois:BAAANQADCgUIAwAAAA==.Portal:BAAANQADCgIIAgABNQAECgQIBgABAAAAAA==.Potatobear:BAAANQAECgcJEwAAAA==.',
Pr='Praytwothee:BAAANQAECgYJCwAAAA==.',
Qu='Quickbow:BAAANQADCgUIBQAAAA==.Quicktime:BAAANQAECgYJEgAAAA==.',
Ra='Ragedh:BAAANQAECgcIEgAAAA==.Ragequit:BAAANQAECgYICQAAAA==.Ragnoir:BAAANQAECgUJCQAAAA==.Rased:BAAANQAECgEJAQAAAA==.Ravensblood:BAAANQADCgEIAQAAAA==.Rawdøg:BAAANQAECgEIAQAAAA==.',
Re='Reddfire:BAAANQAECgEIAQAAAA==.Reeses:BAEANQADCgQIBAAAAA==.',
Ro='Roglof:BAAANQAECggICQAAAA==.Rowlah:BAAANQAECgEIAQAAAA==.Rozy:BAABNQAECoEhAAMDAAkK4RUlJgB0AgADAAkK4RUlJgB0AgACAAYKVBEohwBrAQAAAA==.',
Ru='Ruiizu:BAAANQAECgUJCQAAAA==.Rushuna:BAAANQAECgYJDgAAAA==.',
Sa='Saberjaw:BAAANQAECgcJDwAAAA==.Sairicck:BAAANQAECgUJDwAAAA==.Santamorte:BAAANQADCgMIAwAAAA==.Sarauco:BAAANQADCgQIBAAAAA==.Sarcasticus:BAAANQAECgEJAQAAAA==.',
Se='Selenar:BAAANQADCggICAAAAA==.Selinora:BAAANQAECgYJCgAAAA==.Serhalatath:BAAANQAECgEJAQAAAA==.',
Sh='Shade:BAAANQAECgQIBgAAAA==.Shadowsbane:BAAANQAECgUIDwAAAA==.Shaguar:BAAANQAECgUJCQAAAA==.Shamhawk:BAAANQADCgMIAwABNQAECgcJCwABAAAAAA==.Shamwow:BAAANQAECgcIEAAAAA==.Shaolinsnake:BAAANQAECgEJAQAAAA==.Shemonkk:BAAANQADCgUIBwAAAA==.Shiftshow:BAAANQAECgMIAwAAAA==.Shinukagé:BAAANQAECgMIAwAAAA==.Shizzite:BAAANQADCggJCAAAAA==.',
Si='Silverscream:BAAANQADCgYJBgAAAA==.Singe:BAAANQAECgcJEgAAAA==.',
Sk='Skeetsurfin:BAAANQABCgIIAgAAAA==.',
Sl='Sloppyjo:BAAANQAECgUICwAAAA==.',
Sm='Smallblackdk:BAAANQADCgEIAQAAAA==.',
So='Solenne:BAAANQADCgcJBwABNQAECggJGQADABMTAA==.Solsti:BAABNQAECoEZAAIDAAgKExP3NwAZAgADAAgKExP3NwAZAgAAAA==.Soulhunter:BAAANQAECgcIEwAAAA==.',
Sp='Spears:BAAANQAECgEIAQAAAA==.Spoondot:BAAANQAECgMIAwAAAA==.',
St='Stillhorn:BAAANQADCgQJBAAAAA==.Stinjaga:BAAANQAECgUJCQAAAA==.Strglsngls:BAAANQADCgIIAgAAAA==.Strikerv:BAAANQADCgIJAgABNQAECggIEgARAMwGAA==.',
Su='Sunrae:BAAANQAECgEIAQAAAA==.',
Sy='Sylinsor:BAAANQAECgIIAgAAAA==.Symor:BAAANQADCgYJEgAAAA==.Syxmoo:BAAANQAECgEIAgAAAA==.',
Ta='Taproot:BAEANQADCgcJDgABNQAECggIHwAGAGkSAA==.Taryen:BAAANQAECgUIDAABNQAECgcIEgABAAAAAA==.',
Te='Telaari:BAAANQAECgMIAwAAAA==.Teriyl:BAAANQAECgMICQAAAA==.',
Th='Thalenia:BAAANQAECgcJEgAAAA==.Thalron:BAAANQAECgEIAQAAAA==.Thargrim:BAAANQADCgIIAgAAAA==.Thelandra:BAAANQADCgMJAwAAAA==.',
Ti='Tikeidari:BAABNQAECoEaAAILAAgKXB2JAwCsAgALAAgKXB2JAwCsAgAAAA==.Tiltedtroll:BAAANQAECgQICAAAAA==.',
To='Tonofcron:BAAANQADCgUJEAAAAA==.Totemeri:BAAANQAECgcJEgAAAA==.',
Tr='Trappydk:BAAANQAECgUIBwAAAA==.',
Tu='Turbotastic:BAAANQADCgQIBAAAAA==.',
Ug='Uglyplug:BAAANQADCgIIAgAAAA==.',
Un='Unagi:BAAANQAECgIIBAAAAA==.',
Va='Valezeal:BAAANQAECgEIAQAAAA==.Vazdun:BAAANQAECgUICwAAAA==.',
Ve='Vehlahi:BAAANQABCgIIAgAAAA==.Velari:BAAANQADCgQIBAAAAA==.Vemazan:BAAANQABCgYJBgAAAA==.Venan:BAAANQAECgEIAQAAAA==.Venefirous:BAAANQADCgUIBgAAAA==.Venenn:BAAANQAECgEIAQAAAA==.Venev:BAAANQAECgEIAgAAAA==.Ventana:BAAANQAECgQJCAAAAA==.Verdilac:BAAANQADCgQIBAABNQAECggJLwAHAHcZAA==.',
Vi='Vinceglortho:BAAANQADCgYJDwAAAA==.',
Vl='Vlad:BAAANQADCgIIAgAAAA==.',
Vy='Vyranox:BAAANQAECgcJEgAAAA==.',
Wa='Wanji:BAAANQAECgUJCQAAAA==.',
Wi='Widginatrix:BAAANQADCgYIBgAAAA==.Wildthangz:BAAANQAECgEIAQAAAA==.Wintyr:BAAANQADCgYJEgAAAA==.',
Xa='Xaharst:BAAANQAECgUICQAAAA==.Xaya:BAAANQAECgYIDwAAAA==.',
Xe='Xenophorge:BAAANQADCgcIHAAAAA==.',
Xi='Xiurong:BAAANQADCggIEwAAAA==.',
Xo='Xovace:BAAANQAECgEJAQAAAA==.',
Xt='Xtayse:BAAANQAECgUICwAAAA==.',
Yi='Yirya:BAAANQAECgQJDAAAAA==.',
Yo='Yoruechi:BAAANQAECgcIEgAAAA==.Youroverlord:BAAANQADCggJCAAAAA==.',
['Yú']='Yúmyúm:BAAANQABCgcICgAAAA==.',
Za='Zahel:BAABNQAECoEaAAICAAgKziG1HwDtAgACAAgKziG1HwDtAgAAAA==.Zavier:BAAANQAECgUIBQAAAA==.',
Ze='Zebajin:BAAANQAECgUJBQAAAA==.Zefiryn:BAAANQABCgIIAgAAAA==.Zeppola:BAAANQAECgEJAQAAAA==.',
Zh='Zhee:BAAANQAECgEIAQAAAA==.',
Zo='Zobi:BAAANQADCgYJEgAAAA==.Zomboo:BAAANQAECgcJDQAAAA==.',
Zy='Zyde:BAAANQADCgIJAgAAAA==.',
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
