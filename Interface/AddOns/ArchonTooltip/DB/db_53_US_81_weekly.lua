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

local lookup = {'Rogue-Outlaw','Hunter-BeastMastery','Unknown-Unknown','DeathKnight-Blood','Paladin-Retribution','Paladin-Protection','Paladin-Holy','Shaman-Restoration','DeathKnight-Unholy','Evoker-Preservation','Priest-Holy','Priest-Shadow','Druid-Feral','Druid-Guardian','DemonHunter-Havoc','DeathKnight-Frost','Monk-Brewmaster','Shaman-Elemental','Warrior-Protection','Priest-Discipline','Evoker-Augmentation','Evoker-Devastation','Warrior-Arms','Warrior-Fury','Warlock-Demonology','Hunter-Marksmanship','Mage-Frost','Mage-Arcane','Druid-Restoration','Druid-Balance','Warlock-Destruction','Monk-Windwalker','Hunter-Survival','Shaman-Enhancement','DemonHunter-Devourer',}
local provider = {region='US',realm='Durotan',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aakai:BAABNQAECoEcAAIBAAgKYhZsBgA9AgABAAgKYhZsBgA9AgAAAA==.Aarmorr:BAAANQAECgUIDwAAAA==.',
Ac='Acinianis:BAAANQADCgUIBQAAAA==.',
Ad='Adinna:BAAANQADCgYIBgAAAA==.Adiro:BAAANQADCgQIBAAAAA==.Adsdad:BAAANQAECgIIAgAAAA==.',
Ae='Aedelas:BAAANQADCggICAAAAA==.',
Ai='Aimeeiove:BAAANQAECgMIAwAAAA==.',
Ak='Akarag:BAAANQADCgcIBwAAAA==.',
Al='Alcarza:BAAANQADCgcIBwAAAA==.Alchon:BAABNQAECoEaAAICAAgKBxrPNACKAgACAAgKBxrPNACKAgAAAA==.Alicalsastre:BAAANQAECgcJDwAAAA==.Alista:BAAANQABCgIIAgAAAA==.Allykat:BAAANQAECggICgAAAA==.Alunathsong:BAAANQAECgEIAQAAAA==.Alvagíngras:BAAANQAECgIIAgAAAA==.',
Am='Amaith:BAAANQAECgQJCgAAAA==.Amantillado:BAAANQAECgEIAwABNQAECgUIDgADAAAAAA==.Amata:BAAANQAECgEIAQAAAA==.Amblance:BAAANQADCggICAAAAA==.Amelianne:BAAANQADCgQIBwAAAA==.Ammastary:BAAANQAECgEIAQAAAA==.',
An='Andrea:BAAANQAECgUIDwAAAA==.Angelec:BAAANQADCgYIDAAAAA==.Anthria:BAAANQADCgQIBAAAAA==.Anysra:BAAANQADCgYJBgAAAA==.',
Ap='Apöllo:BAAANQAECgUICQAAAA==.',
Aq='Aqules:BAAANQADCgMJAwAAAA==.',
Ar='Arcapeligo:BAAANQADCgcIBwAAAA==.Archonsfury:BAAANQADCgcIBwAAAA==.Ardagg:BAAANQABCgYICQAAAA==.Arilyn:BAAANQADCgQJBAAAAA==.Arin:BAAANQAECgcIEAAAAA==.',
As='Ashentris:BAAANQADCgcIFAAAAA==.Asnew:BAABNQAECoEVAAIEAAcKAAh/XgAwAQAEAAcKAAh/XgAwAQAAAA==.Asura:BAAANQAECgQIBQAAAA==.',
At='Athelstan:BAAANQAECgUIDAAAAA==.',
Au='Aumaril:BAAANQADCggICAAAAA==.Auralynn:BAAANQAECgUICgAAAA==.Auroriana:BAAANQADCgQIBQAAAA==.',
Av='Averus:BAAANQAECgUIEAAAAA==.',
Az='Azariel:BAABNQAECoEZAAMFAAgKJBE1bwD0AQAFAAgKJBE1bwD0AQAGAAEKbBDrWgAqAAAAAA==.Azatre:BAAANQADCgIIAgAAAA==.Azuriah:BAAANQAECgUIDwAAAA==.',
Ba='Baane:BAAANQAECgEIAQABNQAECgMIAwADAAAAAA==.Babnik:BAEANQAECgQIBQAAAA==.',
Be='Bealzibub:BAAANQABCgIIAgAAAA==.Bedhead:BAAANQAECgUIEAAAAA==.Belovis:BAABNQAECoEgAAIFAAkKeCKaEgBdAwAFAAkKeCKaEgBdAwAAAA==.Betsea:BAAANQADCgcIBwABNQAECgcIHwAHAHIRAA==.',
Bi='Bidock:BAAANQAECgQJBAAAAA==.Bidoof:BAAANQAECgYICQAAAA==.Bigocritties:BAAANQABCgMIAgAAAA==.Bitemarks:BAAANQADCggJFQAAAA==.Bix:BAAANQAECgUJCwAAAA==.',
Bl='Blackcoat:BAAANQADCgUIBQAAAA==.Blokmor:BAAANQAECgQIDgAAAA==.',
Bo='Boggrog:BAAANQAECgMIAwAAAA==.Bonepicklucy:BAAANQADCgUIBQAAAA==.Boneybob:BAAANQABCgQJCAAAAA==.Boras:BAAANQAECgMIBAAAAA==.Bosshog:BAAANQAECgQJBQAAAA==.',
Br='Brabanzio:BAAANQAECgUICQABNQAECggIGgAIAAUXAA==.Breadfriend:BAAANQADCggICAAAAA==.Brightnshiny:BAAANQABCgIIAgAAAA==.Broseidon:BAAANQAECgEIAQAAAA==.Broxxer:BAAANQADCgYIBgAAAA==.Brycke:BAAANQADCggIDwAAAA==.',
Bu='Buffsalot:BAAANQAECgIIAgAAAA==.Burningblunt:BAAANQADCgYICwAAAA==.Buttons:BAAANQADCgcJBwAAAA==.',
Ca='Calav:BAAANQADCgYJBwAAAA==.Castle:BAAANQAECgMIAwAAAA==.Catsinhats:BAAANQADCggICgABNQAECggIHgAJALoYAA==.Catzinhatz:BAAANQADCgUIBQABNQAECggIHgAJALoYAA==.',
Ce='Cecelya:BAAANQAECgcIEgAAAA==.',
Ch='Cherlia:BAAANQADCgcIDgABNQAECgYIEwADAAAAAA==.Chivactdl:BAAANQADCgYJCgABNQAECgYIEgADAAAAAA==.Chosenn:BAAANQAECgUICgAAAA==.Chotek:BAAANQAECgMIAwAAAA==.Chunknoriss:BAAANQAECgEIAgABNQAECgYIEgADAAAAAA==.',
Ci='Cilarnen:BAAANQAECgEIAgAAAA==.',
Cl='Clure:BAABNQAECoEaAAIHAAgKKx4tHQDQAgAHAAgKKx4tHQDQAgAAAA==.Clurethyr:BAABNQAECoEbAAIKAAcKshwLFQAwAgAKAAcKshwLFQAwAgABNQAECggIGgAHACseAA==.',
Co='Conchobhar:BAAANQAECgIIAwAAAA==.Coppertan:BAAANQADCgYIFgAAAA==.Cornaddict:BAACNQAFFIEIAAILAAUKNAv6CgCPAQALAAUKNAv6CgCPAQA1AAQKgSUAAwsACQo2FiExAGECAAsACApHGCExAGECAAwACAoGG6QXAFQCAAAA.Corrosion:BAAANQAECgcIEQAAAA==.',
Cr='Crommash:BAAANQAECggICQAAAA==.Cromshade:BAAANQABCgYIBgAAAA==.Cromsteel:BAAANQABCgQIBgAAAA==.Crono:BAAANQADCgYICQAAAA==.Crunchynuget:BAAANQAECgQICwABNQAECgkJIQAFAM4bAA==.',
Ct='Cthuwu:BAAANQAECgEIAQABNQAECgkJJAACAP8eAA==.',
Cv='Cvhamster:BAAANQADCgcIBwAAAA==.',
Cy='Cy:BAAANQADCggJCAAAAA==.Cybeast:BAABNQAECoEWAAMNAAgKlBnDBwB9AgANAAgKlBnDBwB9AgAOAAMKghRnKwCuAAAAAA==.Cynortas:BAAANQADCgUIBQAAAA==.',
Da='Daciana:BAAANQAECgUICwAAAA==.Dados:BAAANQAECgUIBQAAAA==.Dahleigh:BAAANQADCgYIBAAAAA==.Dakanar:BAAANQADCggICAAAAA==.Darkessence:BAAANQADCgEIAQAAAA==.Darkhazel:BAAANQAECgIIAwAAAA==.Darkkromdor:BAABNQAECoEXAAIFAAcKcR1TVABHAgAFAAcKcR1TVABHAgAAAA==.Darloct:BAAANQADCgEIAgAAAA==.',
De='Deadelff:BAABNQAECoEWAAIPAAcKrBQ6LwDRAQAPAAcKrBQ6LwDRAQAAAA==.Deathcat:BAABNQAECoEeAAMJAAgKuhgSMgAIAgAJAAgKuhgSMgAIAgAQAAYKfQolRQAuAQAAAA==.Deathkiss:BAAANQAECgMJBAAAAA==.Deathrixx:BAAANQADCggICAAAAA==.Deathshadowx:BAAANQAECgEIAQAAAA==.Decayy:BAAANQAECgcIEAABNQAECgYIDgADAAAAAA==.Dedbull:BAAANQADCggJIQAAAA==.Demodius:BAAANQADCggICAAAAA==.Demourdenite:BAAANQADCgYJFQAAAA==.Des:BAAANQABCgIIAgAAAA==.',
Di='Discharged:BAAANQADCgYICAABNQAECgUIDgADAAAAAA==.',
Dk='Dkpheonix:BAAANQAECgQJCAAAAA==.',
Do='Dolemite:BAAANQAECgQICgAAAA==.Donalbain:BAABNQAECoEaAAIIAAgKBRexQwAFAgAIAAgKBRexQwAFAgAAAA==.Donninban:BAAANQAECgMIBQAAAA==.Doodoobutter:BAAANQAECgIIAgABNQAECggIGgARAMoYAA==.',
Dr='Draganpriest:BAAANQADCgcJDQAAAA==.Dremar:BAAANQADCggIJQAAAA==.',
Du='Duarcán:BAAANQADCgEIAQAAAA==.',
Eb='Ebolla:BAAANQADCgcIBwAAAA==.',
Ec='Eclipsy:BAAANQADCgIIAgAAAA==.',
Eg='Eggroll:BAAANQADCgQIBAAAAA==.',
El='Elexander:BAAANQAECgEIAQAAAA==.Elifar:BAAANQADCggIFwAAAA==.Eluneatic:BAAANQADCgQIBAAAAA==.Elyssaris:BAABNQAECoEXAAIEAAgKuxOBMAAPAgAEAAgKuxOBMAAPAgAAAA==.Elzulkin:BAAANQADCgQIBAAAAA==.',
Em='Emmils:BAAANQAECgYIEQAAAA==.Emìly:BAAANQAECgUIDgAAAA==.',
En='Entaria:BAAANQAECgEIAQAAAA==.',
Ep='Ephria:BAABNQAECoEdAAMIAAgKtiRjCgBNAwAIAAgKtiRjCgBNAwASAAEKUwa9DQEpAAAAAA==.Episkey:BAAANQAECgMIBQAAAA==.',
Er='Eroward:BAABNQAECoEsAAITAAcK8RehDwDRAQATAAcK8RehDwDRAQAAAA==.',
Es='Esmay:BAAANQAECgUICAAAAA==.',
Et='Ethren:BAAANQAECgUIEAAAAA==.',
Eu='Eudoxos:BAAANQAECgEJAQAAAA==.Euroecka:BAAANQADCgYIBQAAAA==.',
Ev='Evelynstar:BAAANQADCgMJAwAAAA==.',
Ez='Ezikarridge:BAAANQADCggIDgAAAA==.',
Fa='Falcone:BAAANQAECgEIAQAAAA==.',
Fe='Felbolter:BAAANQAECgUJEQAAAA==.Fetide:BAAANQADCgIIAgAAAA==.',
Fi='Fiddlefaddle:BAAANQABCgMIAwAAAA==.Filgulfin:BAAANQAECgYJEQAAAA==.Finkate:BAAANQADCggICAAAAA==.Firebringer:BAAANQAECgEIAQAAAA==.Fistmegently:BAAANQADCgYIBgAAAA==.',
Fl='Flamehunter:BAAANQAECgEIAQAAAA==.Flo:BAABNQAECoEdAAMMAAgKhA7PIwDCAQAMAAgKhA7PIwDCAQAUAAYKrgutDAA3AQAAAA==.Floki:BAAANQAECgUIDAAAAA==.Flowing:BAABNQAECoEYAAQVAAcKqBANCwBaAQAVAAYKTBINCwBaAQAKAAYKIwe8KQASAQAWAAQK2wSAKACfAAAAAA==.',
Fo='Foods:BAABNQAECoEdAAQXAAgKSQosmwB3AQAXAAgKjwYsmwB3AQATAAUK7wnOIQDWAAAYAAEKnA8MJABGAAAAAA==.',
Fr='Fripouille:BAAANQADCgMIBgAAAA==.',
['Fæ']='Fæ:BAAANQADCgcIBwAAAA==.',
Ga='Gaboo:BAAANQAECgUIDAAAAA==.',
Gh='Ghostinhale:BAAANQADCgQIBAAAAA==.',
Gi='Gilorion:BAAANQAECgYIDgAAAA==.',
Gl='Gler:BAAANQADCgQJBQAAAA==.',
Gn='Gnibat:BAAANQAECgEIAQAAAA==.',
Go='Goburina:BAABNQAECoEcAAIIAAkKWRHLRAABAgAIAAkKWRHLRAABAgAAAA==.Goldhawk:BAAANQABCgIIAgAAAA==.',
Gu='Gulpron:BAAANQABCgMJBAAAAA==.',
['Gí']='Gímlí:BAABNQAECoEVAAICAAgKwRjIQABgAgACAAgKwRjIQABgAgAAAA==.',
Ha='Haidyn:BAAANQADCgMJAwAAAA==.Halcyndraag:BAAANQAECgUIEAAAAA==.Handofcope:BAAANQAECgYIDwAAAA==.Hartu:BAABNQAECoEaAAITAAgK0RSJDQAAAgATAAgK0RSJDQAAAgAAAA==.',
He='Hemic:BAAANQAECgcIEgAAAA==.Hemogobblin:BAAANQADCgQIBAAAAA==.Herbalmist:BAAANQAECgEIAQAAAA==.',
Hi='Hircine:BAAANQADCggIDAAAAA==.',
Ho='Holysea:BAAANQAECgIIAgABNQAECgcIHwAHAHIRAA==.Honk:BAAANQADCggIEQAAAA==.',
Im='Imwithfloki:BAAANQAECgUIDAAAAA==.',
Ir='Ironmark:BAAANQADCgYICQAAAA==.Irys:BAAANQADCgYIDAAAAA==.',
Is='Isam:BAAANQAECgUIBQAAAA==.Isamidor:BAABNQAECoEmAAICAAkKwCWfAwC5AwACAAkKwCWfAwC5AwAAAA==.Ismokeu:BAAANQAECgcIEwAAAA==.Istran:BAAANQADCgYJCQAAAA==.',
Iv='Ivrys:BAAANQAECgYICgAAAA==.',
Iw='Iwillbethere:BAAANQABCgQIBAAAAA==.',
Ja='Jackoneal:BAAANQAECgUIBQAAAA==.Jalidelo:BAABNQAECoEaAAILAAgKHRXZPgAlAgALAAgKHRXZPgAlAgAAAA==.Jalidemon:BAAANQADCggJCAAAAA==.Jalyyn:BAAANQADCgEIAQAAAA==.',
Ji='Jingild:BAAANQADCgYIBgAAAA==.',
Jo='Joeyfoxone:BAAANQADCgQIBAAAAA==.Johan:BAABNQAECoEaAAIZAAgK0hvaNQB3AgAZAAgK0hvaNQB3AgAAAA==.Jokersfists:BAAANQADCgcIGAABNQAECgQIBQADAAAAAA==.Jokersmage:BAAANQAECgQIBQAAAA==.Joraflheim:BAAANQABCgIJAgAAAA==.Joranbragi:BAAANQAECgEIAgAAAA==.Jordanjr:BAABNQAECoEdAAMCAAgKmhbnYQD9AQACAAcKDBbnYQD9AQAaAAYKtg3RNABIAQAAAA==.Josunlee:BAAANQADCggIDwAAAA==.Jotoonice:BAABNQAECoEVAAMbAAcKag38FgAAAQAcAAYK/wU4FAEZAQAbAAQKgxH8FgAAAQAAAA==.',
Jt='Jtoothaordan:BAABNQAECoEkAAMaAAkKHhW3HAA0AgAaAAkK1BK3HAA0AgACAAIKWx6+8ACVAAAAAA==.',
Ju='Juicyfruit:BAAANQABCgYICAAAAA==.Jules:BAAANQADCgcIBwAAAA==.',
Ka='Kaana:BAAANQAECgUIEAAAAA==.Kallista:BAAANQADCgYIDwAAAA==.Karvel:BAABNQAECoEWAAIEAAgK3xqzIQBxAgAEAAgK3xqzIQBxAgAAAA==.Kaychow:BAAANQAECgQICAABNQAECgcIDwADAAAAAA==.Kaydullz:BAAANQAECgIIAgAAAA==.',
Ke='Kelonaar:BAABNQAECoEfAAMSAAkKFh4GGwD6AgASAAkKFh4GGwD6AgAIAAIKsR1GtgCqAAAAAA==.',
Kh='Kharys:BAAANQADCgYIFAAAAA==.',
Ki='Killermoomoo:BAAANQAECgEIAQAAAA==.',
Kl='Kloverr:BAAANQAECgYIEAAAAA==.',
Ko='Kombatkarl:BAAANQADCgMIAwAAAA==.',
Kr='Kretaios:BAAANQADCgEIAQAAAA==.Kromir:BAAANQADCggICAAAAA==.Kronixrage:BAAANQAECgMIBQAAAA==.Krooler:BAAANQAECgMJBAAAAA==.Krum:BAAANQAECgYIEQAAAA==.',
La='Lanval:BAABNQAECoEaAAIFAAgKHxemVgA/AgAFAAgKHxemVgA/AgAAAA==.Latinlover:BAAANQAECgIIAgAAAA==.Laurian:BAAANQABCgMIAwAAAA==.',
Le='Leaky:BAAANQADCgQIBQAAAA==.Leetah:BAABNQAECoEfAAIOAAgKlBqECQBsAgAOAAgKlBqECQBsAgAAAA==.Leftblank:BAAANQAECgEIAQAAAA==.',
Li='Lich:BAAANQADCgYIBgAAAA==.Lighthugger:BAABNQAECoEbAAIFAAgKxxcvWgA0AgAFAAgKxxcvWgA0AgAAAA==.Lilyoptra:BAAANQAECgEIAgABNQAECgEIAgADAAAAAA==.Liqmycrits:BAAANQADCggICAAAAA==.Lishalzin:BAAANQAECgEIAQABNQAECgQIBgADAAAAAA==.Liszt:BAAANQADCgMIAwAAAA==.Livana:BAAANQADCggIEAABNQAECgYIDwADAAAAAA==.',
Lo='Lockpockets:BAAANQADCgUIBwAAAA==.Loriane:BAAANQADCgYIBwABNQADCgUJCQADAAAAAA==.Lorianth:BAABNQAECoEbAAIaAAgKCRDtIwDpAQAaAAgKCRDtIwDpAQAAAA==.Lotharbacco:BAAANQADCggICAAAAA==.Lovegood:BAAANQADCgUIBQAAAA==.',
Lu='Lucifér:BAAANQABCgQIBQAAAA==.',
Ly='Lychi:BAAANQAECgEIAQAAAA==.Lylora:BAABNQAECoEpAAIdAAkKLiVXAQC4AwAdAAkKLiVXAQC4AwAAAA==.',
['Lê']='Lêmonaide:BAAANQAECgYIDwAAAA==.',
Ma='Madclaws:BAABNQAECoEdAAMOAAgKxRroEQC+AQAeAAgKURfWKgBCAgAOAAYKQhvoEQC+AQAAAA==.Madman:BAAANQAECgIIBAAAAA==.Magekaestey:BAAANQADCggIDwABNQAECggIFwAXAD8LAA==.Malala:BAAANQADCgMICQABNQAECggIIQALAIcUAA==.Malyndra:BAAANQAECgUICAAAAA==.Marshy:BAAANQAFFAEIAQAAAA==.Marvolt:BAABNQAECoEXAAIZAAgKIgg6ewCVAQAZAAgKIgg6ewCVAQAAAA==.',
Me='Mesmash:BAAANQAECgQJBAAAAA==.Metadk:BAAANQAECgUIDgAAAA==.Metamasters:BAAANQADCgYIDAABNQAECgUIDgADAAAAAA==.',
Mi='Mialtaa:BAAANQAECgEIAQAAAA==.Micah:BAAANQAECgIJAgAAAA==.Midgiit:BAAANQADCgYICwABNQAECgYIFwALANUPAA==.Miniborg:BAAANQADCggIFwABNQAECgkJIQAFAM4bAA==.Minidude:BAAANQADCgEIAQAAAA==.Misfire:BAAANQADCgEIAQAAAA==.Mistycrusade:BAAANQAECgIIAgAAAA==.Mizzen:BAAANQAECgUIDAABNQAECgkJJwAMACsaAA==.',
Mo='Moejojojo:BAAANQAECgUIDAAAAA==.Moofasaha:BAAANQAECgUIDgAAAA==.Morog:BAAANQAECgcIDwAAAA==.Morragan:BAAANQADCggIGAAAAA==.',
Mu='Mulvan:BAAANQAECgUIDAAAAA==.',
['Mâ']='Mârshy:BAAANQADCgEIAQABNQAFFAEIAQADAAAAAA==.',
['Mã']='Mãrshy:BAAANQAECgYIBgABNQAFFAEIAQADAAAAAA==.',
['Mä']='Märshy:BAAANQAECgIIAgABNQAFFAEIAQADAAAAAA==.',
Na='Nabû:BAAANQADCgQIBAAAAA==.Naler:BAAANQAECgUICAAAAA==.Nanarus:BAABNQAECoEhAAILAAgKhxSlRwD/AQALAAgKhxSlRwD/AQAAAA==.Nashalie:BAABNQAECoEZAAMZAAcKbR2VRgA8AgAZAAcKbR2VRgA8AgAfAAIKNRLfTQB/AAAAAA==.',
Ne='Nedyav:BAAANQADCgIIAgAAAA==.Nefele:BAAANQAECgUICgAAAA==.Nexbasia:BAAANQAECgYIEAAAAA==.',
Ni='Nickyboy:BAAANQAECgIIAQAAAA==.Nightevel:BAAANQADCgYICQAAAA==.Nihimetal:BAAANQADCgcIEwAAAA==.',
No='Noctum:BAAANQAECgIIAgAAAA==.Nomad:BAAANQADCggIGAAAAA==.Norinisa:BAAANQABCgcIBwAAAA==.',
Oc='Octt:BAAANQAECgYICgAAAA==.',
Ol='Oldcannabis:BAAANQADCgYIEAAAAA==.',
Om='Ominis:BAAANQADCgQJBAAAAA==.',
Oo='Oomaw:BAAANQADCgYJCAAAAA==.',
Or='Ornimus:BAAANQAECgIIAwAAAA==.Ortian:BAAANQAECgEIAQAAAA==.',
Os='Osrs:BAABNQAECoEcAAIMAAkK5CJTCgAYAwAMAAkK5CJTCgAYAwAAAA==.',
Oz='Ozo:BAAANQAECgQICQAAAA==.',
Pa='Paiva:BAAANQAECgEIAQAAAA==.Palandor:BAAANQADCgYIBgAAAA==.Pallyscorned:BAABNQAECoEaAAIGAAgKpxfSEgAlAgAGAAgKpxfSEgAlAgAAAA==.Pamgetem:BAAANQAECgQIBQABNQAECgcICwADAAAAAA==.Pampas:BAAANQAECgEIAQAAAA==.Panduh:BAABNQAECoEjAAMgAAgKaSG3DQDMAgAgAAgKRiC3DQDMAgARAAcKWh/RCgAkAgAAAA==.',
Ph='Phenixy:BAAANQAECgEIAQAAAA==.Phoebell:BAAANQAECgEIAQAAAA==.Phoinix:BAAANQADCgYIBwAAAA==.',
Pi='Pinkducky:BAAANQADCgYIDQAAAA==.',
Pl='Plen:BAAANQAECgIIAgABNQAECgYIFwALANUPAA==.',
Po='Ponyo:BAABNQAECoEYAAILAAgKER2+JACfAgALAAgKER2+JACfAgAAAA==.Poppyseed:BAAANQADCgQIBQAAAA==.Poquads:BAAANQADCggICAAAAA==.',
Pv='Pve:BAAANQADCgIIAgAAAA==.',
Qu='Quiewt:BAAANQAECgcIEwAAAA==.',
Ra='Raddra:BAAANQADCgUICgAAAA==.Raddrah:BAAANQABCgUICAAAAA==.Raddrap:BAAANQADCgUIBgAAAA==.Radra:BAAANQAECgMICgAAAA==.Raeku:BAABNQAECoEaAAIhAAgKvB4XAgD8AgAhAAgKvB4XAgD8AgAAAA==.Raharuto:BAAANQADCggICAAAAA==.Raja:BAAANQAECgMJBQAAAA==.Rav:BAAANQADCgIIAgAAAA==.Razzlor:BAAANQADCgQIBAAAAA==.',
Re='Recoill:BAAANQAECgYIDwAAAA==.Redhaven:BAAANQAECggIBwAAAA==.Reducto:BAAANQADCgYICwAAAA==.Retribution:BAAANQAECgYIEgAAAA==.',
Ro='Robomurph:BAAANQADCgQIBAAAAA==.Rolas:BAAANQAECgEIAQAAAA==.Ronfax:BAACNQAFFIEHAAIIAAMKMBpvDQAGAQAIAAMKMBpvDQAGAQA1AAQKgSQAAggACQp9IeEKAEgDAAgACQp9IeEKAEgDAAAA.Roony:BAAANQADCgIIAQAAAA==.Rooss:BAAANQAECgQIBQAAAA==.Rowdyredneck:BAAANQADCgYIBwABNQAECgUIDgADAAAAAA==.',
Ru='Rul:BAAANQADCgIIAgABNQAECggIIwAgAGkhAA==.',
Ry='Ryllae:BAAANQADCgIIAgABNQAECgYIEwADAAAAAA==.Ryuu:BAAANQAECgEIAQAAAA==.Ryuusythe:BAAANQADCggICQAAAA==.',
['Rì']='Rììdìì:BAAANQAECgYIEAABNQAECggIFQACAMEYAA==.',
['Rï']='Rïchardgear:BAAANQADCggIDAABNQAECggIFQACAMEYAA==.',
Sa='Saint:BAAANQAECgQJBQAAAA==.Salopard:BAAANQADCgQIBAAAAA==.Sarinae:BAAANQAECgUIDAAAAA==.Sarmuc:BAABNQAECoEfAAIiAAkKJBJxDQBXAgAiAAkKJBJxDQBXAgAAAA==.Saryda:BAAANQAECgQICQAAAA==.Sauda:BAAANQADCgcIDAAAAA==.',
Sc='Schuybusta:BAAANQAECgEIAQAAAA==.Scubagal:BAAANQAECgEJAQAAAA==.',
Se='Secundinius:BAAANQADCgMIAwAAAA==.Sensu:BAAANQAECgMIAwAAAA==.Serrest:BAAANQAECgUIBQAAAA==.Seä:BAABNQAECoEfAAIHAAcKchG+YACoAQAHAAcKchG+YACoAQAAAA==.',
Sh='Shacktown:BAAANQABCgYICQAAAA==.Shadowdoh:BAAANQADCgYICgABNQAECgUICAADAAAAAA==.Shapzan:BAAANQAECgMIAwAAAA==.Sharks:BAAANQAECgQJBgAAAA==.Shivant:BAAANQAECgYIEgAAAA==.',
Si='Silendreas:BAAANQADCgUIBQAAAA==.',
Sl='Sloth:BAAANQAECgYIEAAAAA==.',
Sm='Smalltwngirl:BAAANQAECgUICAABNQAFFAMIBwAIADAaAA==.',
So='Solaspirus:BAAANQAECgEJAQAAAA==.Solinius:BAAANQADCggIGAAAAA==.Songbreeze:BAABNQAECoEXAAMLAAYK1Q9pcQBbAQALAAYK1Q9pcQBbAQAMAAUK1wWBPgDhAAAAAA==.Sonofagun:BAAANQAECgIIAwAAAA==.',
Sp='Spectors:BAAANQAECgYIEQAAAA==.Spideygirl:BAAANQADCgQIBAAAAA==.',
St='Stabon:BAAANQAECgIJBgAAAA==.Strykah:BAAANQADCgQIBAAAAA==.',
Su='Sugarmarks:BAAANQAECgIJAgAAAA==.',
Sw='Sweetstorm:BAAANQAECgUICgAAAA==.',
Sy='Sydburns:BAAANQABCgYICAAAAA==.Sydley:BAAANQABCgIIAgAAAA==.',
Ta='Taotao:BAAANQADCgYIBgAAAA==.Tarixx:BAAANQAECgYICAAAAA==.Tazanoth:BAABNQAECoEbAAMCAAcKpx7kPgBmAgACAAcKpx7kPgBmAgAaAAUKSwsEPwDyAAAAAA==.',
Te='Tekeela:BAAANQADCggICAABNQAECgkJJAACAP8eAA==.Tekeelà:BAABNQAECoEkAAICAAkK/x6cFgATAwACAAkK/x6cFgATAwAAAA==.',
Th='Thalion:BAAANQADCgcIBwAAAA==.Theenna:BAAANQADCgEIAQAAAA==.Thianna:BAAANQAECgUIDAAAAA==.Thobu:BAAANQAECgEIAQAAAA==.Thornscale:BAAANQAECgcIEQAAAA==.',
Ti='Tigolcrittys:BAAANQADCggJCQABNQAECggIFQACAMEYAA==.',
To='Tokkem:BAAANQADCgEIAQAAAA==.Tomzombe:BAAANQADCgYICgAAAA==.Tonguepunch:BAAANQAECgUIBgAAAA==.Tovê:BAAANQADCgEIAQAAAA==.',
Tr='Traumajazz:BAAANQABCgIIAgAAAA==.Traveler:BAAANQADCgEIAQAAAA==.Trenko:BAAANQADCgMIAwAAAA==.Troloq:BAAANQAECgcIEwAAAA==.',
Tu='Turger:BAAANQADCgUIBgABNQAECgUIDgADAAAAAA==.',
Va='Vaeluptuous:BAAANQAECgQIBQAAAA==.Vahlorraa:BAAANQADCgMJAwAAAA==.Vaimei:BAAANQAECgcIEgAAAA==.Vallyna:BAAANQADCgYIBgAAAA==.Vapor:BAAANQAECgUIBgAAAA==.Varaine:BAAANQADCgYICwABNQAECgQIBgADAAAAAA==.',
Ve='Veebs:BAAANQAECgUJBQAAAA==.Vento:BAAANQADCggIDgAAAA==.Verité:BAAANQAECgYIDwAAAA==.',
Vi='Virauca:BAABNQAECoEaAAIjAAgKzwtGJgDVAQAjAAgKzwtGJgDVAQAAAA==.Vizon:BAAANQADCgYIFgAAAA==.',
Vo='Voices:BAAANQAECgYIEwAAAA==.Voltrix:BAAANQADCggIEwAAAA==.',
Vy='Vynesta:BAAANQAECgYIEwAAAA==.',
Wa='Wanagi:BAAANQAECgEIAQAAAA==.Wankz:BAAANQAECgUIDAAAAA==.Warkaestey:BAABNQAECoEXAAIXAAgKPwtDgwC9AQAXAAgKPwtDgwC9AQAAAA==.Warriorguyes:BAAANQAECgUIBwAAAA==.',
Wh='Whomper:BAAANQADCggIDwAAAA==.',
Wi='Widowx:BAAANQAECgEIAgAAAA==.Windshrieker:BAAANQADCgYIBgAAAA==.Wintervalor:BAAANQAECgUIDgAAAA==.',
Wo='Womphunt:BAAANQAECgQIBwABNQAECgYIDgADAAAAAA==.',
Wu='Wulyn:BAAANQAECgMIAwAAAA==.',
Wy='Wylla:BAAANQAECgQIDAAAAA==.',
Xa='Xalethra:BAAANQAECgQIBQAAAA==.',
Xe='Xenophobias:BAAANQADCgYIEAAAAA==.',
Xs='Xsuns:BAAANQAECgUIEAAAAA==.',
Yv='Yve:BAAANQAECgMIBQAAAA==.',
Za='Zabberz:BAAANQADCgQJBAAAAA==.Zaharian:BAAANQADCgYJBgAAAA==.Zalajin:BAAANQAECgIIAgAAAA==.Zarathiel:BAAANQAECgcIEQAAAA==.',
Ze='Zeddicus:BAAANQAECgQJBQAAAA==.',
Zo='Zoriadon:BAAANQADCgcIDAAAAA==.',
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
