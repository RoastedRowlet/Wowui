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

local lookup = {'Unknown-Unknown','DeathKnight-Blood','Paladin-Retribution','Paladin-Holy','Shaman-Restoration','DeathKnight-Unholy','Priest-Shadow','Priest-Holy','Hunter-BeastMastery','Warrior-Protection','Hunter-Marksmanship','Shaman-Elemental','Druid-Restoration','Monk-Windwalker','Monk-Brewmaster','Shaman-Enhancement',}
local provider = {region='US',realm='Durotan',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aakai:BAAANQAECgYIEQAAAA==.Aarmorr:BAAANQAECgQJCgAAAA==.',
Ac='Acinianis:BAAANQADCgUJBQAAAA==.',
Ad='Adinna:BAAANQADCgYIBgAAAA==.Adiro:BAAANQADCgQIBAAAAA==.Adsdad:BAAANQADCgQICAAAAA==.',
Ai='Aimeeiove:BAAANQAECgMIAwAAAA==.',
Ak='Akarag:BAAANQADCgEJAQABNQADCgcIDgABAAAAAA==.',
Al='Alcarza:BAAANQADCgcIBwAAAA==.Alchon:BAAANQAECgYJEAAAAA==.Alicalsastre:BAAANQAECgcJDwAAAA==.Alista:BAAANQABCgIIAgAAAA==.Allykat:BAAANQAECgQICAAAAA==.Alunathsong:BAAANQADCggICQAAAA==.',
Am='Amaith:BAAANQAECgQJCgAAAA==.Amantillado:BAAANQAECgEIAwABNQAECgUJCQABAAAAAA==.Amata:BAAANQADCgMJAwAAAA==.Amelianne:BAAANQADCgQIBAAAAA==.Ammastary:BAAANQADCgYIBwAAAA==.',
An='Andrea:BAAANQAECgUJCgAAAA==.Angelec:BAAANQADCgYIDAAAAA==.Anthria:BAAANQADCgQIBAAAAA==.Anysra:BAAANQADCgYJBgAAAA==.',
Ap='Apöllo:BAAANQAECgUIBQAAAA==.',
Aq='Aqules:BAAANQADCgMJAwAAAA==.',
Ar='Archonsfury:BAAANQADCgcIBwAAAA==.Ardagg:BAAANQABCgYICQAAAA==.Arilyn:BAAANQADCgQJBAAAAA==.Arin:BAAANQAECgQJCAAAAA==.',
As='Ashentris:BAAANQADCgcJEAAAAA==.Asnew:BAABNQAECoEUAAICAAcK9ge7UAA5AQACAAcK9ge7UAA5AQAAAA==.Asura:BAAANQAECgMIAwAAAA==.',
At='Athelstan:BAAANQAECgQIBwAAAA==.',
Au='Aumaril:BAAANQADCggICAAAAA==.Auralynn:BAAANQAECgUJBQAAAA==.Auroriana:BAAANQADCgQIBQAAAA==.',
Av='Averus:BAAANQAECgUJCwAAAA==.',
Az='Azariel:BAAANQAECgYJDwAAAA==.Azuriah:BAAANQAECgUJCgAAAA==.',
Ba='Baane:BAAANQADCgMIAwABNQADCgcJDQABAAAAAA==.Babnik:BAEANQAECgEIAQAAAA==.',
Be='Bealzibub:BAAANQABCgIIAgAAAA==.Bedhead:BAAANQAECgUJCwAAAA==.Belovis:BAABNQAECoEdAAIDAAkK9SDeDwBWAwADAAkK9SDeDwBWAwAAAA==.Betsea:BAAANQADCgcIBwABNQAECgYJFwAEAPIRAA==.',
Bi='Bidock:BAAANQAECgQJBAAAAA==.Bidoof:BAAANQAECgUIBwAAAA==.Bitemarks:BAAANQADCggJFQAAAA==.Bix:BAAANQAECgUJCwAAAA==.',
Bl='Blackcoat:BAAANQADCgUIBQAAAA==.Blokmor:BAAANQAECgQIDQAAAA==.',
Bo='Boggrog:BAAANQADCggJHQAAAA==.Boneybob:BAAANQABCgQJCAAAAA==.Boras:BAAANQAECgIJAgAAAA==.Bosshog:BAAANQAECgQJBQAAAA==.',
Br='Brabanzio:BAAANQAECgUJBQABNQAECgcJGQAFAK0XAA==.Breadfriend:BAAANQADCggICAAAAA==.Brightnshiny:BAAANQABCgIIAgAAAA==.Broseidon:BAAANQADCggJDgAAAA==.Broxxer:BAAANQADCgYIBgAAAA==.Brycke:BAAANQADCgcJBwAAAA==.',
Bu='Buffsalot:BAAANQADCggJHgAAAA==.Burningblunt:BAAANQADCgYICwAAAA==.Buttons:BAAANQADCgcJBwAAAA==.',
Ca='Calav:BAAANQADCgYJBwAAAA==.Castle:BAAANQADCggJHQAAAA==.Catsinhats:BAAANQADCggICgABNQAECggJFwAGAFoXAA==.Catzinhatz:BAAANQADCgUIBQABNQAECggJFwAGAFoXAA==.',
Ce='Cecelya:BAAANQAECgYIDAAAAA==.',
Ch='Cherlia:BAAANQADCgcIDgABNQAECgYJEAABAAAAAA==.Chivactdl:BAAANQADCgYJCgABNQAECgUJDAABAAAAAA==.Chosenn:BAAANQAECgUICgAAAA==.Chotek:BAAANQADCgcIDwAAAA==.Chunknoriss:BAAANQAECgEIAQABNQAECgUJDAABAAAAAA==.',
Ci='Cilarnen:BAAANQAECgEJAQABNQAECgEJAQABAAAAAA==.',
Cl='Clure:BAAANQAECgYJEAABNQAECgYJEQABAAAAAA==.Clurethyr:BAAANQAECgYJEQAAAA==.',
Co='Conchobhar:BAAANQAECgEIAQAAAA==.Coppertan:BAAANQADCgYIEAAAAA==.Cornaddict:BAABNQAECoEjAAMHAAkKPBqjEQCGAgAHAAgKBhujEQCGAgAIAAgKnReQJQBtAgAAAA==.Corrosion:BAAANQAECgUJCgAAAA==.',
Cr='Crommash:BAAANQAECggJCAAAAA==.Cromshade:BAAANQABCgYIBgAAAA==.Cromsteel:BAAANQABCgQIBgAAAA==.Crono:BAAANQADCgYICQAAAA==.Crunchynuget:BAAANQAECgQICAABNQAECgkJGwADALkaAA==.',
Ct='Cthuwu:BAAANQADCgcJEAABNQAECggJGwAJAP0fAA==.',
Cv='Cvhamster:BAAANQADCgcIBwAAAA==.',
Cy='Cy:BAAANQADCggJCAAAAA==.Cybeast:BAAANQAECgYJDgAAAA==.Cynortas:BAAANQADCgUIBQAAAA==.',
Da='Daciana:BAAANQAECgUJBwAAAA==.Darkhazel:BAAANQAECgEJAQAAAA==.Darkkromdor:BAAANQAECgYJEAAAAA==.Darloct:BAAANQADCgEIAgAAAA==.',
De='Deadelff:BAAANQAECgYJDwAAAA==.Deathcat:BAABNQAECoEXAAIGAAgKWhecIwBIAgAGAAgKWhecIwBIAgAAAA==.Deathkiss:BAAANQAECgMJBAAAAA==.Deathrixx:BAAANQADCggICAAAAA==.Deathshadowx:BAAANQADCgMIAwAAAA==.Decayy:BAAANQAECgcJCgAAAA==.Dedbull:BAAANQADCggJIQAAAA==.Demodius:BAAANQADCggICAAAAA==.Demourdenite:BAAANQADCgYJFQAAAA==.Des:BAAANQABCgIIAgAAAA==.',
Di='Discharged:BAAANQADCgYICAABNQAECgUJCQABAAAAAA==.',
Dk='Dkpheonix:BAAANQAECgQJCAAAAA==.',
Do='Dolemite:BAAANQAECgQJBgAAAA==.Donalbain:BAABNQAECoEZAAIFAAcKrRfFQgDiAQAFAAcKrRfFQgDiAQAAAA==.Donninban:BAAANQAECgIIAwAAAA==.Doodoobutter:BAAANQAECgIIAgABNQAECgYJDwABAAAAAA==.',
Dr='Draganpriest:BAAANQADCgcJDQAAAA==.Dremar:BAAANQADCggJIAAAAA==.',
Du='Duarcán:BAAANQADCgEIAQAAAA==.',
Eb='Ebolla:BAAANQADCgcIBwAAAA==.',
Ec='Eclipsy:BAAANQADCgIIAgAAAA==.',
Eg='Eggroll:BAAANQADCgQIBAAAAA==.',
El='Elexander:BAAANQAECgEIAQAAAA==.Elifar:BAAANQADCggIFwAAAA==.Eluneatic:BAAANQADCgQIBAAAAA==.Elyssaris:BAAANQAECgYIDQAAAA==.Elzulkin:BAAANQADCgQIBAAAAA==.',
Em='Emmils:BAAANQAECgYJDgAAAA==.Emìly:BAAANQAECgUJCQAAAA==.',
En='Entaria:BAAANQADCggJFAAAAA==.',
Ep='Ephria:BAAANQAECgYIEQAAAA==.Episkey:BAAANQAECgMIBQAAAA==.',
Er='Eroward:BAABNQAECoEgAAIKAAcK3hSeDQDBAQAKAAcK3hSeDQDBAQAAAA==.',
Es='Esmay:BAAANQAECgUJBQAAAA==.',
Et='Ethren:BAAANQAECgUJCwAAAA==.',
Eu='Eudoxos:BAAANQAECgEJAQAAAA==.Euroecka:BAAANQADCgYIBgAAAA==.',
Ev='Evelynstar:BAAANQADCgMJAwAAAA==.',
Ez='Ezikarridge:BAAANQADCggIDgAAAA==.',
Fa='Falcone:BAAANQAECgEIAQAAAA==.',
Fe='Felbolter:BAAANQAECgUJEQAAAA==.Fetide:BAAANQADCgIIAgAAAA==.',
Fi='Fiddlefaddle:BAAANQABCgMIAwAAAA==.Filgulfin:BAAANQAECgYJEQAAAA==.Firebringer:BAAANQADCggICAAAAA==.Fistmegently:BAAANQADCgYIBgAAAA==.',
Fl='Flamehunter:BAAANQAECgEIAQAAAA==.Flo:BAAANQAECgYIEQAAAA==.Floki:BAAANQAECgQIBwAAAA==.Flowing:BAAANQAECgYJDgAAAA==.',
Fo='Foods:BAAANQAECgYJEQAAAA==.',
Fr='Fripouille:BAAANQADCgMIBgAAAA==.',
['Fæ']='Fæ:BAAANQADCgcIBwAAAA==.',
Ga='Gaboo:BAAANQAECgQIBwAAAA==.',
Gh='Ghostinhale:BAAANQADCgQIBAAAAA==.',
Gi='Gilorion:BAAANQAECgUJCQAAAA==.',
Gl='Gler:BAAANQADCgQJBQAAAA==.',
Gn='Gnibat:BAAANQADCgMIAwAAAA==.',
Go='Goburina:BAABNQAECoEVAAIFAAkK0BB/OAAQAgAFAAkK0BB/OAAQAgAAAA==.',
Gu='Gulpron:BAAANQABCgMJBAAAAA==.',
['Gí']='Gímlí:BAAANQAECgYJDQABNQAECgYJDgABAAAAAA==.',
Ha='Haidyn:BAAANQADCgMJAwAAAA==.Halcyndraag:BAAANQAECgUJCwAAAA==.Handofcope:BAAANQAECgYICwAAAA==.Hartu:BAAANQAECgYIDgAAAA==.',
He='Hemic:BAAANQAECgYJDAAAAA==.Hemogobblin:BAAANQADCgQIBAAAAA==.Herbalmist:BAAANQADCgMIAwAAAA==.',
Hi='Hircine:BAAANQADCggIDAAAAA==.',
Ho='Holysea:BAAANQAECgIJAgABNQAECgYJFwAEAPIRAA==.Honk:BAAANQADCggJDQAAAA==.',
Im='Imwithfloki:BAAANQAECgQIBwAAAA==.',
Ir='Ironmark:BAAANQADCgMJAwAAAA==.Irys:BAAANQADCgYIBgAAAA==.',
Is='Isam:BAAANQAECgUIBQAAAA==.Isamidor:BAABNQAECoEkAAIJAAkKcSWrAgC+AwAJAAkKcSWrAgC+AwAAAA==.Ismokeu:BAAANQAECgYJEgAAAA==.Istran:BAAANQADCgYJCQAAAA==.',
Iv='Ivrys:BAAANQAECgQIBAAAAA==.',
Iw='Iwillbethere:BAAANQABCgQIBAAAAA==.',
Ja='Jackoneal:BAAANQADCgYICAAAAA==.Jalidelo:BAAANQAECgYJEAAAAA==.Jalidemon:BAAANQADCggJCAAAAA==.Jalyyn:BAAANQADCgEJAQAAAA==.',
Ji='Jingild:BAAANQADCgYIBgAAAA==.',
Jo='Joeyfoxone:BAAANQADCgQIBAAAAA==.Johan:BAAANQAECgYJEQAAAA==.Jokersfists:BAAANQADCgYIEAAAAA==.Jokersmage:BAAANQAECgMIAwAAAA==.Joraflheim:BAAANQABCgIJAgAAAA==.Joranbragi:BAAANQAECgEJAQAAAA==.Jordanjr:BAABNQAECoEWAAMJAAcKCBU0XgDTAQAJAAYKhxY0XgDTAQALAAYKTwtRLgBHAQAAAA==.Josunlee:BAAANQADCggIDwAAAA==.Jotoonice:BAAANQAECgUIDQAAAA==.',
Jt='Jtoothaordan:BAABNQAECoEhAAMLAAkKHhVAGABAAgALAAkKrhJAGABAAgAJAAIKWx7hzACdAAAAAA==.',
Ju='Juicyfruit:BAAANQABCgYICAAAAA==.Jules:BAAANQADCgcIBwAAAA==.',
Ka='Kaana:BAAANQAECgUJCwAAAA==.Kallista:BAAANQADCgYIDwAAAA==.Karvel:BAAANQAECgYJDQAAAA==.Kaychow:BAAANQAECgQICAABNQAECgcICgABAAAAAA==.Kaydullz:BAAANQADCgYIBgAAAA==.',
Ke='Kelonaar:BAABNQAECoEcAAMMAAkKUR+DHADJAgAMAAgKzR6DHADJAgAFAAIKsR3SngCvAAAAAA==.',
Kh='Kharys:BAAANQADCgUJDwAAAA==.',
Ki='Killermoomoo:BAAANQADCgMIAwAAAA==.',
Kl='Kloverr:BAAANQAECgUICgAAAA==.',
Ko='Kombatkarl:BAAANQADCgMIAwAAAA==.',
Kr='Kretaios:BAAANQADCgEIAQAAAA==.Kronixrage:BAAANQAECgMIBQAAAA==.Krooler:BAAANQAECgMJBAAAAA==.Krum:BAAANQAECgUIBQAAAA==.',
La='Lanval:BAAANQAECgYIDgAAAA==.Latinlover:BAAANQAECgIIAgAAAA==.Laurian:BAAANQABCgMJAwAAAA==.',
Le='Leaky:BAAANQADCgQIBQAAAA==.Leetah:BAAANQAECgYIEgAAAA==.Leftblank:BAAANQADCgMIAwAAAA==.',
Li='Lich:BAAANQADCgYIBgAAAA==.Lighthugger:BAAANQAECgYJDwAAAA==.Lilyoptra:BAAANQAECgEJAQAAAA==.Lishalzin:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Liszt:BAAANQADCgMIAwAAAA==.Livana:BAAANQADCggIEAABNQAECgUICQABAAAAAA==.',
Lo='Loriane:BAAANQADCgYIBwABNQADCgUJCQABAAAAAA==.Lorianth:BAAANQAECgYIEAAAAA==.Lotharbacco:BAAANQADCggICAAAAA==.Lovegood:BAAANQADCgUIBQAAAA==.',
Ly='Lychi:BAAANQADCgMIAwAAAA==.Lylora:BAABNQAECoEhAAINAAkKLiWyAADJAwANAAkKLiWyAADJAwAAAA==.',
['Lê']='Lêmonaide:BAAANQAECgUJDgAAAA==.',
Ma='Madclaws:BAAANQAECgYIEQAAAA==.Madman:BAAANQAECgIJAgAAAA==.Magekaestey:BAAANQADCggIDwABNQAECgYJDgABAAAAAA==.Malala:BAAANQADCgMICQABNQAECgcJGAAIAJUVAA==.Malyndra:BAAANQAECgMIAwAAAA==.Marshy:BAAANQAFFAEJAQAAAA==.Marvolt:BAAANQAECgUJDgAAAA==.',
Me='Mesmash:BAAANQAECgQJBAAAAA==.Metadk:BAAANQAECgUJCQAAAA==.Metamasters:BAAANQADCgYIBgABNQAECgUJCQABAAAAAA==.',
Mi='Mialtaa:BAAANQADCggIEgAAAA==.Micah:BAAANQAECgIJAgAAAA==.Midgiit:BAAANQADCgYICwABNQAECgYJEQABAAAAAA==.Miniborg:BAAANQADCggIFwABNQAECgkJGwADALkaAA==.Misfire:BAAANQADCgEIAQAAAA==.Mistycrusade:BAAANQAECgIIAgAAAA==.Mizzen:BAAANQAECgUIDAABNQAECgkJJAAHAAcYAA==.',
Mo='Moejojojo:BAAANQAECgQIBwAAAA==.Moofasaha:BAAANQAECgQICQAAAA==.Morog:BAAANQAECgYJDAAAAA==.Morragan:BAAANQADCggJEgAAAA==.',
Mu='Mulvan:BAAANQAECgQIBwAAAA==.',
['Mâ']='Mârshy:BAAANQADCgEIAQABNQAFFAEJAQABAAAAAA==.',
['Mã']='Mãrshy:BAAANQAECgQJBAABNQAFFAEJAQABAAAAAA==.',
Na='Nabû:BAAANQADCgQIBAAAAA==.Naler:BAAANQAECgUICAAAAA==.Nanarus:BAABNQAECoEYAAIIAAcKlRWtSAC9AQAIAAcKlRWtSAC9AQAAAA==.Nashalie:BAAANQAECgYJDwAAAA==.',
Ne='Nedyav:BAAANQADCgIIAgAAAA==.Nefele:BAAANQAECgUJBwAAAA==.Nexbasia:BAAANQAECgUICgAAAA==.',
Ni='Nickyboy:BAAANQAECgIIAQAAAA==.Nightevel:BAAANQADCgYIBgAAAA==.Nihimetal:BAAANQADCgcIDQAAAA==.',
No='Noctum:BAAANQAECgIIAgAAAA==.Nomad:BAAANQADCggJEgAAAA==.Norinisa:BAAANQABCgcIBwAAAA==.',
Oc='Octt:BAAANQAECgYICgAAAA==.',
Ol='Oldcannabis:BAAANQADCgYJEAAAAA==.',
Om='Ominis:BAAANQADCgQJBAAAAA==.',
Oo='Oomaw:BAAANQADCgYJCAAAAA==.',
Or='Ornimus:BAAANQADCggJIAAAAA==.Ortian:BAAANQAECgEIAQAAAA==.',
Os='Osrs:BAABNQAECoEcAAIHAAkK5CJeBgBRAwAHAAkK5CJeBgBRAwAAAA==.',
Oz='Ozo:BAAANQAECgQICAAAAA==.',
Pa='Paiva:BAAANQADCgMIAwAAAA==.Palandor:BAAANQADCgYIBgAAAA==.Pallyscorned:BAAANQAECgYJEAAAAA==.Pamgetem:BAAANQAECgQIBQABNQAECgYICgABAAAAAA==.Pampas:BAAANQAECgEIAQAAAA==.Panduh:BAABNQAECoEbAAMOAAgK4h6HDwCCAgAOAAgKPhyHDwCCAgAPAAcKWh+BCAA6AgAAAA==.',
Ph='Phenixy:BAAANQADCgMIAwAAAA==.Phoebell:BAAANQAECgEJAQAAAA==.Phoinix:BAAANQADCgYJBwAAAA==.',
Pi='Pinkducky:BAAANQADCgYJCAAAAA==.',
Po='Ponyo:BAAANQAECgYJDQAAAA==.Poppyseed:BAAANQADCgQIBQAAAA==.',
Pv='Pve:BAAANQADCgIIAgAAAA==.',
Qu='Quiewt:BAAANQAECgYJDAAAAA==.',
Ra='Raddra:BAAANQADCgUJCAAAAA==.Raddrap:BAAANQADCgUIBgAAAA==.Radra:BAAANQAECgIIBwAAAA==.Raeku:BAAANQAECgYIEAAAAA==.Raharuto:BAAANQADCggICAAAAA==.Raja:BAAANQAECgMJBQAAAA==.Rav:BAAANQADCgIIAgAAAA==.Razzlor:BAAANQADCgQIBAAAAA==.',
Re='Recoill:BAAANQAECgUJCQAAAA==.Redhaven:BAAANQAECggJBwAAAA==.Reducto:BAAANQADCgYICwAAAA==.Retribution:BAAANQAECgUJDAAAAA==.',
Ro='Robomurph:BAAANQADCgQIBAAAAA==.Rolas:BAAANQAECgEIAQAAAA==.Ronfax:BAABNQAECoEgAAIFAAkKsiBeCQBHAwAFAAkKsiBeCQBHAwAAAA==.Roony:BAAANQADCgIIAQAAAA==.Rooss:BAAANQAECgEIAQAAAA==.Rowdyredneck:BAAANQADCgYIBwABNQAECgUJCQABAAAAAA==.',
Ru='Rul:BAAANQADCgIIAgABNQAECggIGwAOAOIeAA==.',
Ry='Ryllae:BAAANQADCgEIAQABNQAECgYJEAABAAAAAA==.Ryuu:BAAANQADCgcJDAAAAA==.Ryuusythe:BAAANQADCgEIAQAAAA==.',
['Rì']='Rììdìì:BAAANQAECgYJDgAAAA==.',
['Rï']='Rïchardgear:BAAANQADCggIDAABNQAECgYJDgABAAAAAA==.',
Sa='Saint:BAAANQAECgQJBQAAAA==.Salopard:BAAANQADCgQIBAAAAA==.Sarinae:BAAANQAECgQJBwAAAA==.Sarmuc:BAABNQAECoEXAAIQAAgKXRCODAA5AgAQAAgKXRCODAA5AgAAAA==.Saryda:BAAANQAECgQJCAAAAA==.Sauda:BAAANQADCgUJCQAAAA==.',
Sc='Schuybusta:BAAANQAECgEJAQAAAA==.Scubagal:BAAANQAECgEJAQAAAA==.',
Se='Secundinius:BAAANQADCgMJAwAAAA==.Sensu:BAAANQADCgcJDQAAAA==.Seä:BAABNQAECoEXAAIEAAYK8hGtYwBqAQAEAAYK8hGtYwBqAQAAAA==.',
Sh='Shacktown:BAAANQABCgYJCAAAAA==.Shadowdoh:BAAANQADCgYJBgABNQAECgMIAwABAAAAAA==.Shapzan:BAAANQADCggJHAAAAA==.Sharks:BAAANQAECgQJBgAAAA==.Shivant:BAAANQAECgUJDAAAAA==.',
Si='Silendreas:BAAANQADCgUIBQAAAA==.',
Sl='Sloth:BAAANQAECgUJCgAAAA==.',
Sm='Smalltwngirl:BAAANQAECgQIBgABNQAECgkJIAAFALIgAA==.',
So='Solaspirus:BAAANQAECgEJAQAAAA==.Solinius:BAAANQADCggJEgAAAA==.Songbreeze:BAAANQAECgYJEQAAAA==.Sonofagun:BAAANQAECgEJAQAAAA==.',
Sp='Spectors:BAAANQAECgYJDgAAAA==.',
St='Stabon:BAAANQAECgIJBgAAAA==.Strykah:BAAANQADCgQIBAAAAA==.',
Su='Sugarmarks:BAAANQAECgIJAgAAAA==.',
Sw='Sweetstorm:BAAANQAECgUJBQAAAA==.',
Sy='Sydburns:BAAANQABCgYICAAAAA==.',
Ta='Tarixx:BAAANQAECgYICAAAAA==.Tazanoth:BAAANQAECgYJEgAAAA==.',
Te='Tekeela:BAAANQADCgUIBQABNQAECggJGwAJAP0fAA==.Tekeelà:BAABNQAECoEbAAIJAAgK/R+5GQDgAgAJAAgK/R+5GQDgAgAAAA==.',
Th='Thalion:BAAANQADCgUJBQAAAA==.Theenna:BAAANQADCgEIAQAAAA==.Thianna:BAAANQAECgUJBwAAAA==.Thobu:BAAANQAECgEJAQAAAA==.Thornscale:BAAANQAECgYJEAAAAA==.',
Ti='Tigolcrittys:BAAANQADCggJCQABNQAECgYJDgABAAAAAA==.',
To='Tokkem:BAAANQADCgEIAQAAAA==.Tomzombe:BAAANQADCgYJCgAAAA==.Tonguepunch:BAAANQAECgEIAQAAAA==.Tovê:BAAANQADCgEIAQAAAA==.',
Tr='Traumajazz:BAAANQABCgIIAgAAAA==.Traveler:BAAANQADCgEIAQAAAA==.Trenko:BAAANQADCgMIAwAAAA==.Troloq:BAAANQAECgYJEAAAAA==.',
Tu='Turger:BAAANQADCgUIBQABNQAECgQICQABAAAAAA==.',
Va='Vaeluptuous:BAAANQAECgEJAQAAAA==.Vahlorraa:BAAANQADCgMJAwAAAA==.Vaimei:BAAANQAECgYJDAAAAA==.Vallyna:BAAANQADCgYIBgAAAA==.Vapor:BAAANQAECgUIBgAAAA==.Varaine:BAAANQADCgYICwABNQAECgIIAgABAAAAAA==.',
Ve='Veebs:BAAANQAECgUJBQAAAA==.Vento:BAAANQADCggIDgAAAA==.Verité:BAAANQAECgUICQAAAA==.',
Vi='Virauca:BAAANQAECgYIDgAAAA==.Vizon:BAAANQADCgYIEAAAAA==.',
Vo='Voices:BAAANQAECgUIBwAAAA==.Voltrix:BAAANQADCgcICwAAAA==.',
Vy='Vynesta:BAAANQAECgYJEAAAAA==.',
Wa='Wanagi:BAAANQADCggJDwAAAA==.Wankz:BAAANQAECgQIBwAAAA==.Warkaestey:BAAANQAECgYJDgAAAA==.Warriorguyes:BAAANQAECgEIAgAAAA==.',
Wh='Whomper:BAAANQADCggIDwAAAA==.',
Wi='Widowx:BAAANQAECgEIAgAAAA==.Windshrieker:BAAANQADCgYIBgAAAA==.Wintervalor:BAAANQAECgUJCQAAAA==.',
Wo='Womphunt:BAAANQAECgQIBAABNQAECgYJCgABAAAAAA==.',
Wu='Wulyn:BAAANQADCggJHQAAAA==.',
Wy='Wylla:BAAANQAECgQICwAAAA==.',
Xa='Xalethra:BAAANQAECgQIBQAAAA==.',
Xe='Xenophobias:BAAANQADCgYJCwAAAA==.',
Xs='Xsuns:BAAANQAECgUJCwAAAA==.',
Yv='Yve:BAAANQAECgEIAgAAAA==.',
Za='Zabberz:BAAANQADCgQJBAAAAA==.Zaharian:BAAANQADCgYJBgAAAA==.Zalajin:BAAANQADCgUIBwAAAA==.Zarathiel:BAAANQAECgYICgAAAA==.',
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
