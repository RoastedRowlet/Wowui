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

local lookup = {'Unknown-Unknown','Priest-Holy','Paladin-Retribution','Paladin-Holy','Druid-Guardian','Mage-Frost','Mage-Arcane','Monk-Windwalker','Shaman-Enhancement','DemonHunter-Devourer','Shaman-Restoration','Shaman-Elemental','Druid-Restoration','Druid-Balance','DeathKnight-Blood','Warlock-Demonology','Warlock-Destruction','DemonHunter-Vengeance','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Paladin-Protection','Priest-Discipline','DeathKnight-Frost','Rogue-Assassination','DemonHunter-Havoc','Priest-Shadow','Monk-Mistweaver','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Unholy',}
local provider = {region='US',realm='Uther',name='US',type='weekly',zone=53,date='2026-09-29',data={Ae='Aelithsong:BAEANQAECgIJAgABNQADCgcICwABAAAAAA==.',
Ah='Aha:BAAANQADCgYICAAAAA==.',
Ai='Aiax:BAAANQAECgcIEwAAAA==.',
Al='Alderok:BAAANQADCgcICAABNQAECgUIBQABAAAAAA==.Aliancia:BAAANQAECgUIDgAAAA==.Aloriel:BAAANQAECgEIAQAAAA==.Alydin:BAAANQAECgQJBAAAAA==.',
Am='Amynle:BAAANQADCgcIDQAAAA==.',
An='Anerius:BAAANQABCgMIAwAAAA==.Annora:BAABNQAECoEeAAICAAgKCSAaHQDIAgACAAgKCSAaHQDIAgAAAA==.Antherina:BAAANQADCgEIAQAAAA==.Antonious:BAAANQAECgEIAQAAAA==.',
Ap='Apollyon:BAABNQAECoEeAAMDAAgKQiKTPwCNAgADAAcKuCGTPwCNAgAEAAIKZQ510AB/AAAAAA==.',
Ar='Ari:BAAANQAECgUIEQAAAA==.Ariioch:BAAANQAECgEIAQAAAA==.',
As='Asiago:BAAANQAECgEIAQAAAA==.Assclapiuss:BAABNQAECoEgAAMDAAgK0iNvIAASAwADAAgK0iNvIAASAwAEAAQKlwxurgDRAAAAAA==.Asterchades:BAABNQAECoEiAAIFAAgKOxN8EADUAQAFAAgKOxN8EADUAQAAAA==.Asteriou:BAAANQAECgIIAwAAAA==.',
At='Attikus:BAABNQAECoEdAAIGAAgKBgZ/DwBoAQAGAAgKBgZ/DwBoAQAAAA==.Atuan:BAAANQAECgEIAQAAAA==.',
Au='Auralass:BAAANQAECgIIAgAAAA==.Autauga:BAAANQAECgQIBAAAAA==.',
Av='Avatard:BAAANQAECgQIBAABNQAECggIGgAHAJIPAA==.Avilla:BAAANQAECgUIDAAAAA==.',
Ax='Axem:BAAANQAECgcJEQAAAA==.',
Az='Azulathan:BAAANQAECgQICAAAAA==.',
Ba='Bangpewpew:BAAANQADCgQJBAAAAA==.',
Be='Bechett:BAABNQAECoEXAAIIAAgKxBKhHgDjAQAIAAgKxBKhHgDjAQAAAA==.Beep:BAAANQAECgIIAgAAAA==.Beerguy:BAAANQADCgcICgAAAA==.Behemothe:BAABNQAECoEkAAIJAAgKPhc6DABwAgAJAAgKPhc6DABwAgAAAA==.Berníesandrs:BAAANQAECgQIBQAAAA==.Beryllos:BAAANQADCggIFwAAAA==.Bewzey:BAAANQAECgUIDAAAAA==.',
Bi='Bittiesxo:BAAANQABCgcICwAAAA==.',
Bl='Bledana:BAAANQADCgQIBAAAAA==.Bloodmourne:BAAANQAECgYIDwAAAA==.Bloodytoutii:BAAANQAECgMIBgAAAA==.',
Bo='Bortman:BAABNQAECoEYAAIKAAgK6CGhCwAJAwAKAAgK6CGhCwAJAwAAAA==.Bowowner:BAAANQAECgYIBgAAAA==.',
Bu='Buhbul:BAAANQAECgUIDQAAAA==.Buzzball:BAAANQAECgUICwAAAA==.',
Bw='Bwicked:BAABNQAECoEbAAMGAAgKEBHhDQCHAQAGAAcKihLhDQCHAQAHAAgKmAbq2gCAAQAAAA==.',
Ca='Caroline:BAAANQADCgQJBAAAAA==.Catdamage:BAAANQAECgQIBAABNQAECgUIBQABAAAAAA==.',
Ce='Celonge:BAAANQAECgQIBAABNQAECggIIAAEAL0WAA==.Ceremony:BAEANQADCgUJBQABNQAECggIHwAHAGkSAA==.',
Ch='Chamelean:BAAANQADCgUIBQABNQAECgUIDAABAAAAAA==.Chimpnzthat:BAAANQAECgIIAwAAAA==.Chookicookie:BAABNQAECoEdAAMLAAgKHCPAFAD6AgALAAgKHCPAFAD6AgAMAAcK/xS/UADlAQAAAA==.Chrome:BAABNQAECoEiAAMNAAgKpxmtFQBPAgANAAgKpxmtFQBPAgAOAAcKWRvnKwA6AgAAAA==.',
Ci='Cindyy:BAAANQAECgcIDwAAAA==.Cini:BAAANQADCgEIAQAAAA==.Cirí:BAABNQAECoEZAAIPAAcKiCCZHACXAgAPAAcKiCCZHACXAgAAAA==.',
Co='Coldbeans:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Coresh:BAABNQAECoEfAAIJAAgK5hmCCwCBAgAJAAgK5hmCCwCBAgAAAA==.Cornpuff:BAAANQADCggIEAAAAA==.',
Cr='Crickets:BAAANQAECgMIBgAAAA==.Crucifixx:BAAANQADCgcIDQAAAA==.',
Cu='Cupsandcakes:BAAANQAECgUIBwAAAA==.',
Da='Dacarry:BAAANQAECgQIBAAAAA==.Dadbody:BAAANQAECgQICAABNQAECggIIAADANIjAA==.Damessiah:BAAANQADCggICAAAAA==.Dark:BAABNQAECoEgAAIQAAgKByKSFQAHAwAQAAgKByKSFQAHAwAAAA==.Darkphyre:BAAANQAECgEJAQAAAA==.',
De='Deadloc:BAAANQADCggIEwAAAA==.Deadmandan:BAABNQAECoEjAAMQAAkKBiTRAwCgAwAQAAkKBiTRAwCgAwARAAEK+h3sYABKAAAAAA==.Deathtike:BAABNQAECoEbAAIPAAcK+h48IwBnAgAPAAcK+h48IwBnAgABNQAECggIIgASANYgAA==.Decius:BAAANQAECgEJAQAAAA==.Deltairlines:BAACNQAFFIEHAAMTAAQKgxlGAwBOAQATAAQKgxlGAwBOAQAUAAEKXgAbFQAkAAA1AAQKgR4ABBMACQqTIYYCAAcDABMACQqTIYYCAAcDABQACQo2EbYVACcCABUAAQqBDW0yADkAAAAA.Deltayaya:BAAANQAECggICgABNQAFFAQIBwATAIMZAA==.Demagorgin:BAAANQAECgYICwAAAA==.Deqlyn:BAABNQAECoEYAAIDAAgKNBolVgBAAgADAAgKNBolVgBAAgAAAA==.Desmus:BAAANQAECgIIAwAAAA==.Devilmaycry:BAAANQADCggIDAAAAA==.Deáthreaver:BAABNQAECoEbAAIWAAgKsBnuEQAzAgAWAAgKsBnuEQAzAgAAAA==.',
Di='Diddyy:BAAANQAECgMIBQABNQAECgQIBAABAAAAAA==.',
Do='Domwarlock:BAABNQAECoEXAAIQAAcKvxzMPgBXAgAQAAcKvxzMPgBXAgAAAA==.Dots:BAAANQAECgQIBAAAAA==.Doublehungus:BAAANQABCgQIBAAAAA==.',
Dr='Dronin:BAAANQAECgYIEgAAAA==.Drpatan:BAAANQAECgMIBAAAAA==.Druni:BAAANQAECgEJAQAAAA==.Drâkenhân:BAAANQAECgEIAQAAAA==.',
Du='Dumpling:BAAANQADCgQIBAAAAA==.Durango:BAAANQADCgcIFwAAAA==.',
Ea='Eamon:BAAANQADCggICQAAAA==.',
Ec='Echowalker:BAAANQAECgIIAgAAAA==.',
Ed='Edinburger:BAAANQADCgUICAAAAA==.',
Eh='Ehdawg:BAAANQAECgMIBAAAAA==.',
Ei='Eirya:BAAANQADCgEIAQAAAA==.',
El='Elguezo:BAAANQADCgEIAQAAAA==.',
Em='Emokillaz:BAAANQADCgcIBwAAAA==.',
Ep='Epictaxes:BAAANQAECgQIBAAAAA==.Epsilón:BAEANQADCgcICwAAAA==.',
Es='Esmerr:BAAANQADCggIHwAAAA==.',
Fa='Faxon:BAAANQAECgUIDQAAAA==.',
Fe='Feronnia:BAAANQADCggIFwAAAA==.',
Fi='Fibot:BAABNQAECoEiAAIJAAgKoxUmDAByAgAJAAgKoxUmDAByAgAAAA==.Fireboürne:BAAANQAECgIIAgAAAA==.Fireishot:BAAANQAECgMIBQAAAA==.',
Fl='Florasol:BAAANQAECgIIAgAAAA==.',
Fr='Fraeyah:BAAANQADCgUIBgAAAA==.Friede:BAAANQAECgQICgAAAA==.',
['Fè']='Fènrys:BAAANQADCgYICgAAAA==.',
Ga='Galvanize:BAEBNQAECoEfAAIHAAgKaRKflgAPAgAHAAgKaRKflgAPAgAAAA==.Gastbubble:BAAANQAECgQIBAAAAA==.',
Ge='Geewetsya:BAAANQAECgIIBAAAAA==.Gengarr:BAAANQADCgMIAwABNQAECgYIDgABAAAAAA==.',
Gh='Ghomertin:BAAANQAECgIIAgAAAA==.',
Gi='Gipsydanger:BAABNQAECoEjAAMCAAkKgR9zCQBVAwACAAkKgR9zCQBVAwAXAAIKKw1wGQBmAAAAAA==.',
Gl='Gladiatrix:BAAANQADCgYIBgAAAA==.Glofor:BAAANQADCgUIBQABNQAECggICwABAAAAAA==.',
Go='Gonnjass:BAAANQADCgYJEgAAAA==.Gorlokk:BAEANQADCgYIBwAAAA==.',
Gr='Grakonys:BAABNQAECoEYAAIVAAgKQAfNGAB+AQAVAAgKQAfNGAB+AQAAAA==.Greed:BAAANQAECgUJCQAAAA==.Grimmbot:BAAANQAECgQICAAAAA==.Grunch:BAAANQADCgQIBAAAAA==.Grunnck:BAAANQADCggIGgAAAA==.',
Gu='Guayusa:BAAANQAECgIIAgAAAA==.',
Gy='Gypsydanger:BAAANQADCgYIBgAAAA==.',
Ha='Habb:BAAANQADCggIEAAAAA==.Harnix:BAAANQAECgEIAQAAAA==.Hawtbooty:BAABNQAECoEYAAICAAgKGR84GQDhAgACAAgKGR84GQDhAgAAAA==.Hazuul:BAAANQABCgQIBAABNQAECgUICwABAAAAAA==.',
He='Hellreines:BAABNQAECoEfAAIYAAgKFCEfDwDhAgAYAAgKFCEfDwDhAgAAAA==.Hemolythria:BAAANQADCgIIAgAAAA==.',
Hi='Hildi:BAAANQAECgIIAwAAAA==.Him:BAAANQAECgUJDwAAAA==.Himothy:BAAANQADCgMIAwAAAA==.',
Ho='Holy:BAABNQAECoEbAAICAAcKNSVMFwDsAgACAAcKNSVMFwDsAgAAAA==.Holyscales:BAAANQAECgQIBQAAAA==.Hotmess:BAAANQADCgUIBwAAAA==.Hottopic:BAAANQABCgQIBAAAAA==.',
Hu='Hurcules:BAAANQABCgEIAQAAAA==.',
Ic='Icespirit:BAAANQABCgEIAQAAAA==.',
Ir='Irintha:BAAANQABCgMIAwAAAA==.',
Is='Ishura:BAAANQAECgIIAwAAAA==.',
It='Itslevi:BAAANQAECgMIAwAAAA==.',
Iv='Ivvy:BAAANQAECgUIBgAAAA==.',
Iz='Izanami:BAAANQADCgcIDwAAAA==.',
Ja='Jaffer:BAABNQAECoEVAAIZAAkKGwmlKADhAQAZAAkKGwmlKADhAQAAAA==.Janntro:BAABNQAECoEYAAMaAAcK/xlzKQAAAgAaAAcK/xlzKQAAAgASAAEKOBz+IQBMAAAAAA==.Jantra:BAAANQADCgQIBAABNQAECgcIGAAaAP8ZAA==.Jantro:BAAANQAECgUICwABNQAECgcIGAAaAP8ZAA==.Janttro:BAAANQAECgUICgABNQAECgcIGAAaAP8ZAA==.',
Je='Jebby:BAAANQAECgcIEwAAAA==.Jeebz:BAAANQAECgUICAABNQAECgcIEwABAAAAAA==.Jelmarr:BAAANQADCggIFwAAAA==.Jerauld:BAAANQAECgIIAwAAAA==.',
Ji='Jimmyhoffá:BAAANQAECgEIAQAAAA==.',
Jo='Johnnyzyns:BAAANQAECggIDwAAAA==.Joshc:BAAANQAECgYIDwAAAA==.',
Ju='Judgédred:BAAANQADCgYIBgAAAA==.',
['Já']='Ják:BAAANQAECgYIDwAAAA==.',
Ka='Kaaris:BAAANQAECgUICgAAAA==.Kaiarie:BAAANQAECgIIAwAAAA==.Kainraziel:BAAANQAECgUIDAAAAA==.Kairos:BAABNQAECoEeAAIHAAgKaA4UqwDhAQAHAAgKaA4UqwDhAQAAAA==.Kanofworms:BAAANQAECgQICAAAAA==.Karkea:BAAANQAECgcIEAAAAA==.',
Ke='Kebin:BAAANQAECgYIEQAAAA==.',
Ki='Kibil:BAAANQAECgUIDAAAAA==.',
Ko='Koga:BAAANQADCgIIAgAAAA==.Korax:BAAANQADCgUIBAAAAA==.Kortharion:BAAANQAECgYIDwAAAA==.Kos:BAACNQAFFIEGAAIbAAQKxSIPBQCYAQAbAAQKxSIPBQCYAQA1AAQKgRsAAhsACQpKJSEEAIADABsACQpKJSEEAIADAAAA.',
Kr='Krule:BAAANQADCgYIBgABNQAECgcIGAAaAP8ZAA==.',
Ku='Kujiera:BAAANQAECgcIEAAAAA==.Kurick:BAAANQAECgUICAAAAA==.Kurrenter:BAAANQAECgUIDAAAAA==.',
['Ká']='Kárgorr:BAAANQADCgQIBgAAAA==.',
['Kÿ']='Kÿtten:BAABNQAECoEcAAIWAAgKCw/yIQB3AQAWAAgKCw/yIQB3AQAAAA==.',
La='Laiyth:BAAANQAECgcIEgAAAA==.Larryfish:BAAANQAECgUIDAAAAA==.Lavos:BAABNQAECoEaAAIRAAgKCwmAFwCjAQARAAgKCwmAFwCjAQAAAA==.',
Le='Levitikus:BAAANQAECgEIAQAAAA==.',
Li='Lisster:BAAANQAECggIDwAAAA==.Liyra:BAAANQAECgUIDwAAAA==.',
Lo='Loafe:BAABNQAECoEZAAIDAAcKmBS+fADOAQADAAcKmBS+fADOAQAAAA==.Loennicus:BAAANQADCgQIBAAAAA==.Logout:BAAANQADCgQIBAAAAA==.',
Lu='Lurts:BAAANQAECgEIAQAAAA==.Luthais:BAAANQAECgEJAQAAAA==.Luxury:BAAANQAECgYIDwAAAA==.',
Ly='Lykanthropos:BAAANQADCggIGAAAAA==.',
Ma='Magmabeard:BAAANQADCggICwAAAA==.Maingauche:BAAANQAECgcIEgAAAA==.Mako:BAABNQAECoEbAAIUAAgKPx6rCwDFAgAUAAgKPx6rCwDFAgAAAA==.Malevian:BAAANQADCgYIIQAAAA==.Malfuridan:BAAANQADCgMIAwAAAA==.Malocki:BAAANQADCgcIBwAAAA==.Maples:BAABNQAECoEhAAIcAAgKfAuzGgB6AQAcAAgKfAuzGgB6AQAAAA==.Mariasha:BAAANQADCgQIBAAAAA==.Marichika:BAAANQAECgMIAwAAAA==.Mazz:BAAANQAECgUIEAAAAA==.',
Me='Megaterium:BAAANQAECgQIBwAAAA==.Meláni:BAAANQAECgEIAQAAAA==.Menethil:BAAANQAECgIIBAAAAA==.',
Mi='Milei:BAAANQAECgEIAQAAAA==.Missmisery:BAAANQAECgUICwAAAA==.Mistaya:BAAANQAECgQIDQAAAA==.Mithdraug:BAAANQAECgEJAQAAAA==.',
Mo='Modrem:BAAANQADCgYICQAAAA==.Monache:BAAANQAECgQICQAAAA==.Mongalf:BAAANQADCgYIBgAAAA==.Moocheala:BAAANQADCgMIAwAAAA==.Mortarîon:BAAANQAECgIIAQAAAA==.',
Ms='Msdktank:BAAANQADCgIIAgAAAA==.',
My='Mystiqwolf:BAAANQAECgQJBAAAAA==.Mythrilblade:BAAANQADCgQJCAAAAA==.Myzeel:BAAANQABCgMIAwAAAA==.',
Na='Naavilus:BAAANQADCggICAABNQAFFAUICgAVADcZAA==.',
Ni='Nightparade:BAAANQAECgEJAQAAAA==.Nishgrail:BAABNQAECoEdAAIFAAgK3CF3BAASAwAFAAgK3CF3BAASAwAAAA==.',
No='Nohkal:BAAANQADCgYIEQAAAA==.',
Nu='Nukusmaximus:BAAANQAECgIIAwAAAA==.',
Ny='Nyxiie:BAAANQADCgMIAwAAAA==.Nyxofflimits:BAAANQABCgMIAwAAAA==.',
Od='Odioz:BAAANQAECgcIEAAAAA==.',
On='Onex:BAAANQAECgEJAQAAAA==.',
Or='Ori:BAAANQAECgIIAwAAAA==.',
Oz='Ozmo:BAAANQADCgQIBAAAAA==.',
Pa='Palidinas:BAAANQADCggIFAAAAA==.Pawmasutra:BAAANQAECgUIDgAAAA==.',
Pe='Pencil:BAAANQAECgEIBgAAAA==.Persefini:BAAANQAECgEJAQAAAA==.Petrodaear:BAAANQADCgEJAQABNQADCggIGwABAAAAAA==.Petrodrak:BAAANQADCggIGwAAAA==.',
Ph='Pheylan:BAAANQAECgEJAQAAAA==.Philidox:BAAANQADCgYIBgABNQAECgYIDwABAAAAAA==.Phløw:BAAANQADCgQIBwAAAA==.',
Pl='Plugadin:BAAANQADCgUIBQAAAA==.Plugugly:BAAANQAECgUIDQAAAA==.',
Po='Polinemarois:BAAANQADCgUIAwAAAA==.Portal:BAAANQADCgIIAgABNQAECgUICwABAAAAAA==.Potatobear:BAABNQAECoEcAAMdAAgK2yR5DwBCAwAdAAgK2yR5DwBCAwAeAAMKDAy7SgCsAAAAAA==.',
Pr='Praytwothee:BAAANQAECgcIEgAAAA==.',
Qu='Quickbow:BAAANQADCgUIBQAAAA==.Quicktime:BAABNQAECoEeAAMaAAgKNw9wLADnAQAaAAgKNw9wLADnAQAKAAYK4wexOQAoAQAAAA==.',
Ra='Ragedh:BAAANQAECgcIEwAAAA==.Ragequit:BAAANQAECgYICQAAAA==.Ragnoir:BAAANQAECgYIDwAAAA==.Rased:BAAANQAECgQIBQAAAA==.Ravensblood:BAAANQADCgEIAQAAAA==.Rawdøg:BAAANQAECgMIAwAAAA==.',
Re='Reddfire:BAAANQAECgUIBgAAAA==.Reeses:BAEANQADCgQIBAABNQADCgYIBwABAAAAAA==.',
Ro='Robnsparkles:BAAANQABCgUICAAAAA==.Roglof:BAAANQAECggICwAAAA==.Rowlah:BAAANQAECgIIAwAAAA==.Rozy:BAABNQAECoEkAAMEAAkK4RUGMABrAgAEAAkK4RUGMABrAgADAAcKCRGHjgCeAQAAAA==.',
Ru='Ruiizu:BAAANQAECgYIDwAAAA==.Rushuna:BAABNQAECoEYAAIXAAgKPBFTBgDxAQAXAAgKPBFTBgDxAQAAAA==.',
Sa='Saberjaw:BAABNQAECoEUAAIdAAcKoBKxbADfAQAdAAcKoBKxbADfAQAAAA==.Sairicck:BAABNQAECoEWAAIdAAcKJxa5ZQDyAQAdAAcKJxa5ZQDyAQAAAA==.Santamorte:BAAANQADCgMIAwAAAA==.Sarauco:BAAANQADCgQIBAAAAA==.Sarcasticus:BAAANQAECgEJAQAAAA==.',
Se='Selenar:BAAANQADCggICAAAAA==.Selinora:BAAANQAECgcIDAAAAA==.Serhalatath:BAAANQAECgMIBAAAAA==.',
Sh='Shade:BAAANQAECgUICwAAAA==.Shadowsbane:BAABNQAECoEVAAMEAAYKwBNCfABRAQAEAAUKbRVCfABRAQADAAIKyATdKgFbAAAAAA==.Shaguar:BAAANQAECgYIDwAAAA==.Shamhawk:BAAANQADCgMIAwABNQAECgcICwABAAAAAA==.Shamwow:BAAANQAECggIEAAAAA==.Shaolinsnake:BAAANQAECgEJAQAAAA==.Shemonkk:BAAANQADCgUIBwAAAA==.Shiftshow:BAAANQAECgMIAwAAAA==.Shinukagé:BAAANQAECgQIBQAAAA==.Shizzite:BAAANQADCggICAAAAA==.',
Si='Silverscream:BAAANQADCgYJBgAAAA==.Singe:BAABNQAECoEaAAIHAAgKkg8YnwD8AQAHAAgKkg8YnwD8AQAAAA==.',
Sk='Skeetsurfin:BAAANQABCgIIAgAAAA==.',
Sl='Sloppyjo:BAAANQAECgYIEQAAAA==.',
Sm='Smallblackdk:BAAANQAECgIIAgAAAA==.',
So='Solai:BAAANQADCgcIBwAAAA==.Solenne:BAAANQADCgcJBwABNQAECggIIAAEAL0WAA==.Solsti:BAABNQAECoEgAAIEAAgKvRbENwBIAgAEAAgKvRbENwBIAgAAAA==.Soulhunter:BAABNQAECoEZAAMPAAgKbxtzJABfAgAPAAgKjRhzJABfAgAfAAIKiSJEeADKAAAAAA==.',
Sp='Spears:BAAANQAECgQIBQAAAA==.Spoondot:BAAANQAECgUIBQAAAA==.',
St='Stainpngolin:BAAANQADCgYIBgAAAA==.Stephe:BAAANQABCgYIBgAAAA==.Stillhorn:BAAANQADCgQIBAAAAA==.Stinjaga:BAAANQAECgYIDwAAAA==.Strglsngls:BAAANQADCgIIAgAAAA==.Strikerv:BAAANQAECgQIBQABNQAECgkJFQAZABsJAA==.',
Su='Sunrae:BAAANQAECgIIAwAAAA==.',
Sw='Swifty:BAAANQAECgIIAgAAAA==.',
Sy='Sylinsor:BAAANQAECgIIAgAAAA==.Symor:BAAANQADCgcIEwAAAA==.Syxmoo:BAAANQAECgEIAgAAAA==.',
Ta='Taproot:BAEANQADCgcJDgABNQAECggIHwAHAGkSAA==.Taryen:BAAANQAECgUIDAABNQAECgcIEwABAAAAAA==.',
Te='Tedo:BAAANQADCgIIAgABNQAECggIGwAEAF0aAA==.Telaari:BAAANQAECgMIAwAAAA==.Teriyl:BAAANQAECgYIEQAAAA==.',
Th='Thalenia:BAABNQAECoEbAAIdAAgKWAteZgDxAQAdAAgKWAteZgDxAQAAAA==.Thallenia:BAAANQADCgYIBgAAAA==.Thalron:BAAANQAECgEIAQAAAA==.Thargrim:BAAANQADCgIIAgAAAA==.Thelandra:BAAANQADCgMJAwAAAA==.',
Ti='Tikeidari:BAABNQAECoEiAAISAAgK1iDoAgD/AgASAAgK1iDoAgD/AgAAAA==.Tiltedtroll:BAAANQAECgYIDgAAAA==.',
To='Tonofcron:BAAANQADCgUIEAAAAA==.Totemeri:BAABNQAECoEcAAMLAAgKLhGPWACzAQALAAgKLhGPWACzAQAMAAYKAA/QegBcAQAAAA==.',
Tr='Trappydk:BAAANQAECgcIDgAAAA==.',
Tu='Turbotastic:BAAANQADCgQIBAAAAA==.',
Ug='Uglyplug:BAAANQADCgIIAgAAAA==.',
Un='Unagi:BAAANQAECgUICQAAAA==.',
Va='Vaks:BAAANQAECgEIAQAAAA==.Valezeal:BAAANQAECgIIAwAAAA==.Vazdun:BAAANQAECgUIDwAAAA==.',
Ve='Vehlahi:BAAANQABCgIIAgAAAA==.Velari:BAAANQADCgQIBAAAAA==.Vemazan:BAAANQABCgYJBgAAAA==.Venan:BAAANQAECgIIAwAAAA==.Venefirous:BAAANQADCgUIBgAAAA==.Venenn:BAAANQAECgIIAgAAAA==.Venev:BAAANQAECgIIBAAAAA==.Ventana:BAAANQAECgQJCAAAAA==.Verdilac:BAAANQAECgcIBwAAAA==.',
Vi='Vinceglortho:BAAANQADCgcIFAAAAA==.',
Vl='Vlad:BAAANQADCgIIAgAAAA==.',
Vy='Vyranox:BAABNQAECoEZAAIYAAcK8hB3MwCkAQAYAAcK8hB3MwCkAQAAAA==.',
Wa='Wanji:BAAANQAECgYIDwAAAA==.',
Wh='Whiteookami:BAAANQADCgMIAwABNQAECgUIDwABAAAAAA==.',
Wi='Widginatrix:BAAANQADCgYIBgAAAA==.Wildthangz:BAAANQAECgEIAQAAAA==.Wintyr:BAAANQADCgcIEwAAAA==.',
Xa='Xaharst:BAAANQAECgUIDgAAAA==.Xaya:BAABNQAECoEXAAIQAAcKhQ9HdACqAQAQAAcKhQ9HdACqAQAAAA==.',
Xe='Xenophorge:BAAANQADCggIHgAAAA==.',
Xi='Xiurong:BAAANQADCggIEwAAAA==.',
Xo='Xovace:BAAANQAECgEJAQAAAA==.',
Xt='Xtayse:BAAANQAECgUICwAAAA==.',
Yi='Yirya:BAABNQAECoEZAAMNAAcKoAukMAAtAQANAAcKoAukMAAtAQAOAAEK2gGYmwAkAAAAAA==.',
Yo='Yoruechi:BAABNQAECoEZAAIFAAcKoiKqBgDBAgAFAAcKoiKqBgDBAgAAAA==.Youroverlord:BAAANQADCggJCAAAAA==.',
['Yú']='Yúmyúm:BAAANQABCgcICgAAAA==.',
Za='Zahel:BAABNQAECoEhAAIDAAgK7SHgLQDUAgADAAgK7SHgLQDUAgAAAA==.Zavier:BAAANQAECgUIBQAAAA==.',
Ze='Zebajin:BAAANQAECgUJBQAAAA==.Zefiryn:BAAANQABCgIIAgAAAA==.Zeppola:BAAANQAECgMIBAAAAA==.',
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
