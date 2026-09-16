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

local lookup = {'Unknown-Unknown','Priest-Shadow','Priest-Holy','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Restoration','Shaman-Restoration',}
local provider = {region='US',realm='Durotan',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aakai:BAAANQAECgUICwAAAA==.Aarmorr:BAAANQAECgQIBgAAAA==.',
Ad='Adinna:BAAANQADCgYIBgAAAA==.Adiro:BAAANQADCgQIBAAAAA==.Adsdad:BAAANQADCgQICAAAAA==.',
Ai='Aimeeiove:BAAANQAECgMIAwAAAA==.',
Al='Alcarza:BAAANQADCgcIBwAAAA==.Alchon:BAAANQAECgUICgAAAA==.Alicalsastre:BAAANQAECgcICAAAAA==.Alista:BAAANQABCgIIAgAAAA==.Allykat:BAAANQAECgQIBwAAAA==.Alunathsong:BAAANQADCggICAAAAA==.',
Am='Amaith:BAAANQAECgQICgAAAA==.Amantillado:BAAANQAECgEIAwABNQAECgMIBAABAAAAAA==.Amata:BAAANQADCgMIAwAAAA==.Amelianne:BAAANQADCgQIBAAAAA==.Ammastary:BAAANQADCgYIBwAAAA==.',
An='Andrea:BAAANQAECgQIBQAAAA==.Angelec:BAAANQADCgYIDAAAAA==.Anthria:BAAANQADCgQIBAAAAA==.',
Aq='Aqules:BAAANQADCgIIAgAAAA==.',
Ar='Archonsfury:BAAANQADCgcIBwAAAA==.Ardagg:BAAANQABCgYICQAAAA==.Arilyn:BAAANQADCgQIBAAAAA==.Arin:BAAANQAECgQIBAAAAA==.',
As='Ashentris:BAAANQADCgYICQAAAA==.Asnew:BAAANQAECgUIDQAAAA==.Asura:BAAANQAECgEIAQAAAA==.',
At='Athelstan:BAAANQAECgIIAwAAAA==.',
Au='Aumaril:BAAANQADCggICAAAAA==.Auralynn:BAAANQADCggIFQAAAA==.Auroriana:BAAANQADCgQIBQAAAA==.',
Av='Averus:BAAANQAECgQIBgAAAA==.',
Az='Azariel:BAAANQAECgUICQAAAA==.Azuriah:BAAANQAECgQIBgAAAA==.',
Ba='Baane:BAAANQADCgMIAwABNQADCgcICQABAAAAAA==.Babnik:BAEANQAECgEIAQAAAA==.',
Be='Bealzibub:BAAANQABCgIIAgAAAA==.Bedhead:BAAANQAECgQIBgAAAA==.Belovis:BAAANQAECgcIEwAAAA==.Betsea:BAAANQADCgcIBwABNQAECgQICwABAAAAAA==.',
Bi='Bidock:BAAANQAECgQIBAAAAA==.Bidoof:BAAANQAECgMIBAAAAA==.Bitemarks:BAAANQADCgYIDAAAAA==.Bix:BAAANQAECgQIBgAAAA==.',
Bl='Blackcoat:BAAANQADCgUIBQAAAA==.Blokmor:BAAANQAECgQICQAAAA==.',
Bo='Boggrog:BAAANQADCgcIFgAAAA==.Boneybob:BAAANQABCgQIBgAAAA==.Boras:BAAANQAECgIIAgAAAA==.Bosshog:BAAANQAECgEIAQAAAA==.',
Br='Breadfriend:BAAANQADCggICAAAAA==.Brightnshiny:BAAANQABCgIIAgAAAA==.Broseidon:BAAANQADCgYIBgAAAA==.Broxxer:BAAANQADCgYIBgAAAA==.',
Bu='Buffsalot:BAAANQADCgcIGwAAAA==.Burningblunt:BAAANQADCgMIBQAAAA==.',
Ca='Calav:BAAANQADCgYIAwAAAA==.Castle:BAAANQADCgcIFgAAAA==.Catsinhats:BAAANQADCggICgABNQAECgYIDQABAAAAAA==.Catzinhatz:BAAANQADCgUIBQABNQAECgYIDQABAAAAAA==.',
Ce='Cecelya:BAAANQAECgQIBgAAAA==.',
Ch='Cherlia:BAAANQADCgcIBwABNQAECgYICgABAAAAAA==.Chivactdl:BAAANQADCgYICgABNQAECgQIBwABAAAAAA==.Chosenn:BAAANQAECgQIBQAAAA==.Chotek:BAAANQADCgcIDwAAAA==.Chunknoriss:BAAANQADCgcIEgABNQAECgQIBwABAAAAAA==.',
Ci='Cilarnen:BAAANQADCgcIEwAAAA==.',
Cl='Clure:BAAANQAECgUICgABNQAECgUICwABAAAAAA==.Clurethyr:BAAANQAECgUICwAAAA==.',
Co='Conchobhar:BAAANQADCgcIDgAAAA==.Coppertan:BAAANQADCgYIEAAAAA==.Cornaddict:BAABNQAECoEbAAMCAAkJTxo0DQCjAgACAAgJBhs0DQCjAgADAAcJnRIwNADNAQAAAA==.Corrosion:BAAANQAECgQIBQAAAA==.',
Cr='Cromshade:BAAANQABCgYIBgAAAA==.Cromsteel:BAAANQABCgQIBgAAAA==.Crono:BAAANQADCgYICQAAAA==.Crunchynuget:BAAANQAECgMIBAABNQAECgcIEQABAAAAAA==.',
Ct='Cthuwu:BAAANQADCgYIDwABNQAECgcIDwABAAAAAA==.',
Cv='Cvhamster:BAAANQADCgcIBwAAAA==.',
Cy='Cybeast:BAAANQAECgUICAAAAA==.Cynortas:BAAANQADCgUIBQAAAA==.',
Da='Daciana:BAAANQAECgIIAgAAAA==.Darkhazel:BAAANQADCgcIDAAAAA==.Darkkromdor:BAAANQAECgUICgAAAA==.Darloct:BAAANQADCgEIAgAAAA==.',
De='Deadelff:BAAANQAECgUICQAAAA==.Deathcat:BAAANQAECgYIDQAAAA==.Deathkiss:BAAANQAECgEIAQAAAA==.Deathrixx:BAAANQADCggICAAAAA==.Deathshadowx:BAAANQADCgMIAwAAAA==.Decayy:BAAANQAECgIIAgAAAA==.Dedbull:BAAANQADCggIHQAAAA==.Demodius:BAAANQADCggICAAAAA==.Demourdenite:BAAANQADCgYIEQAAAA==.Des:BAAANQABCgIIAgAAAA==.',
Di='Discharged:BAAANQADCgYICAABNQAECgMIBAABAAAAAA==.',
Dk='Dkpheonix:BAAANQAECgQIBAAAAA==.',
Do='Dolemite:BAAANQAECgEIAgAAAA==.Donalbain:BAAANQAECgYIEQAAAA==.Donninban:BAAANQAECgEIAQAAAA==.Doodoobutter:BAAANQAECgIIAgABNQAECgUICQABAAAAAA==.',
Dr='Draganpriest:BAAANQADCgcIDQAAAA==.Dremar:BAAANQADCgcIHwAAAA==.',
Du='Duarcán:BAAANQADCgEIAQAAAA==.',
Eb='Ebolla:BAAANQADCgcIBwAAAA==.',
Ec='Eclipsy:BAAANQADCgIIAgAAAA==.',
Eg='Eggroll:BAAANQADCgQIBAAAAA==.',
El='Elexander:BAAANQAECgEIAQAAAA==.Elifar:BAAANQADCggIFwAAAA==.Eluneatic:BAAANQADCgQIBAAAAA==.Elyssaris:BAAANQAECgUIBwAAAA==.Elzulkin:BAAANQADCgQIBAAAAA==.',
Em='Emmils:BAAANQAECgQICAAAAA==.Emìly:BAAANQAECgQIBQAAAA==.',
En='Entaria:BAAANQADCgYIDAAAAA==.',
Ep='Ephria:BAAANQAECgUICwAAAA==.Episkey:BAAANQAECgIIAgAAAA==.',
Er='Eroward:BAAANQAECgYIEQAAAA==.',
Es='Esmay:BAAANQADCggIHgAAAA==.',
Et='Ethren:BAAANQAECgQIBgAAAA==.',
Eu='Eudoxos:BAAANQADCgcIDgAAAA==.Euroecka:BAAANQADCgYIBgAAAA==.',
Ev='Evelynstar:BAAANQADCgEIAQAAAA==.',
Ez='Ezikarridge:BAAANQADCggIDgAAAA==.',
Fa='Falcone:BAAANQAECgEIAQAAAA==.',
Fe='Felbolter:BAAANQAECgUIDAAAAA==.Fetide:BAAANQADCgIIAgAAAA==.',
Fi='Fiddlefaddle:BAAANQABCgMIAwAAAA==.Filgulfin:BAAANQAECgUICwAAAA==.Firebringer:BAAANQADCggICAAAAA==.',
Fl='Flamehunter:BAAANQAECgEIAQAAAA==.Flo:BAAANQAECgUICwAAAA==.Floki:BAAANQAECgIIAwAAAA==.Flowing:BAAANQAECgUICAAAAA==.',
Fo='Foods:BAAANQAECgUICwAAAA==.',
Fr='Fripouille:BAAANQADCgMIBgAAAA==.',
['Fæ']='Fæ:BAAANQADCgcIBwAAAA==.',
Ga='Gaboo:BAAANQAECgIIAwAAAA==.',
Gh='Ghostinhale:BAAANQADCgQIBAAAAA==.',
Gi='Gilorion:BAAANQAECgQIBAAAAA==.',
Gl='Gler:BAAANQADCgQIBAAAAA==.',
Gn='Gnibat:BAAANQADCgMIAwAAAA==.',
Go='Goburina:BAAANQAECgcIEAAAAA==.',
['Gí']='Gímlí:BAAANQAECgQIBwABNQAECgQICAABAAAAAA==.',
Ha='Haidyn:BAAANQADCgIIAgAAAA==.Halcyndraag:BAAANQAECgQIBgAAAA==.Handofcope:BAAANQAECgYICAAAAA==.Hartu:BAAANQAECgQICAAAAA==.',
He='Hemic:BAAANQAECgYICgAAAA==.Hemogobblin:BAAANQADCgQIBAAAAA==.Herbalmist:BAAANQADCgMIAwAAAA==.',
Hi='Hircine:BAAANQADCggIDAAAAA==.',
Ho='Holysea:BAAANQAECgIIAgABNQAECgQICwABAAAAAA==.Honk:BAAANQADCgYIBgAAAA==.',
Im='Imwithfloki:BAAANQAECgIIAwAAAA==.',
Ir='Ironmark:BAAANQADCgMIAwAAAA==.Irys:BAAANQADCgYIBgAAAA==.',
Is='Isam:BAAANQAECgUIBQAAAA==.Isamidor:BAABNQAECoEeAAIEAAkJQyPsBACBAwAEAAkJQyPsBACBAwAAAA==.Ismokeu:BAAANQAECgYIDAAAAA==.Istran:BAAANQADCgIIAgAAAA==.',
Iv='Ivrys:BAAANQADCggICAAAAA==.',
Ja='Jackoneal:BAAANQADCgYICAAAAA==.Jalidelo:BAAANQAECgUICgAAAA==.Jalyyn:BAAANQADCgEIAQAAAA==.',
Ji='Jingild:BAAANQADCgYIBgAAAA==.',
Jo='Joeyfoxone:BAAANQADCgQIBAAAAA==.Johan:BAAANQAECgUICwAAAA==.Jokersfists:BAAANQADCgYIEAAAAA==.Jokersmage:BAAANQADCgQIBAAAAA==.Joraflheim:BAAANQABCgIIAgAAAA==.Joranbragi:BAAANQADCgcIEgAAAA==.Jordanjr:BAAANQAECgYIDgAAAA==.Josunlee:BAAANQADCggIDwAAAA==.Jotoonice:BAAANQAECgUIDAAAAA==.',
Jt='Jtoothaordan:BAABNQAECoEbAAMFAAkJpRTjEwBKAgAFAAkJGxLjEwBKAgAEAAIJWx4OpQClAAAAAA==.',
Ju='Juicyfruit:BAAANQABCgYICAAAAA==.Jules:BAAANQADCgcIBwAAAA==.',
Ka='Kaana:BAAANQAECgQIBgAAAA==.Kallista:BAAANQADCgYIDwAAAA==.Karvel:BAAANQAECgUIBwAAAA==.Kaychow:BAAANQAECgQICAABNQAECgYIBgABAAAAAA==.',
Ke='Kelonaar:BAAANQAECgcIEQAAAA==.',
Kh='Kharys:BAAANQADCgUICgAAAA==.',
Ki='Killermoomoo:BAAANQADCgMIAwAAAA==.',
Kl='Kloverr:BAAANQAECgUICgAAAA==.',
Ko='Kombatkarl:BAAANQADCgMIAwAAAA==.',
Kr='Kretaios:BAAANQADCgEIAQAAAA==.Kronixrage:BAAANQAECgMIBQAAAA==.Krooler:BAAANQAECgEIAQAAAA==.',
La='Lanval:BAAANQAECgQICAAAAA==.',
Le='Leaky:BAAANQADCgQIBQAAAA==.Leetah:BAAANQAECgYIDAAAAA==.Leftblank:BAAANQADCgMIAwAAAA==.',
Li='Lich:BAAANQADCgYIBgAAAA==.Lighthugger:BAAANQAECgUICQAAAA==.Lilyoptra:BAAANQADCgYIEgABNQADCgcIEwABAAAAAA==.Lishalzin:BAAANQAECgEIAQAAAA==.Liszt:BAAANQADCgMIAwAAAA==.Livana:BAAANQADCggIEAABNQAECgQIBAABAAAAAA==.',
Lo='Loriane:BAAANQADCgYIBwABNQADCgUIBQABAAAAAA==.Lorianth:BAAANQAECgYICgAAAA==.Lotharbacco:BAAANQADCggICAAAAA==.Lovegood:BAAANQADCgUIBQAAAA==.',
Ly='Lychi:BAAANQADCgMIAwAAAA==.Lylora:BAABNQAECoEYAAIGAAgJ3CTaAgBVAwAGAAgJ3CTaAgBVAwAAAA==.',
['Lê']='Lêmonaide:BAAANQAECgQICQAAAA==.',
Ma='Madclaws:BAAANQAECgUICwAAAA==.Madman:BAAANQADCgcIFgAAAA==.Magekaestey:BAAANQADCggIDwABNQAECgUICAABAAAAAA==.Malala:BAAANQADCgMICQABNQAECgYIDwABAAAAAA==.Malyndra:BAAANQADCggICwAAAA==.Marshy:BAAANQADCgUICgAAAA==.Marvolt:BAAANQAECgUICgAAAA==.',
Me='Mesmash:BAAANQADCggIHgAAAA==.Metadk:BAAANQAECgMIBAAAAA==.Metamasters:BAAANQADCgYIBgABNQAECgMIBAABAAAAAA==.',
Mi='Mialtaa:BAAANQADCgYICgAAAA==.Midgiit:BAAANQADCgYICwABNQAECgYICwABAAAAAA==.Miniborg:BAAANQADCggIFwABNQAECgcIEQABAAAAAA==.Misfire:BAAANQADCgEIAQAAAA==.Mistycrusade:BAAANQADCgQIBAAAAA==.Mizzen:BAAANQAECgQICAABNQAECggIGwACAP4UAA==.',
Mo='Moejojojo:BAAANQAECgIIAwAAAA==.Moofasaha:BAAANQAECgIIBQAAAA==.Morog:BAAANQAECgQIBwAAAA==.Morragan:BAAANQADCgYIEAAAAA==.',
Mu='Mulvan:BAAANQAECgIIAwAAAA==.',
['Mâ']='Mârshy:BAAANQADCgEIAQABNQADCgUICgABAAAAAA==.',
['Mã']='Mãrshy:BAAANQADCgIIAgABNQADCgUICgABAAAAAA==.',
Na='Nabû:BAAANQADCgQIBAAAAA==.Naler:BAAANQAECgUICAAAAA==.Nanarus:BAAANQAECgYIDwAAAA==.Nashalie:BAAANQAECgUICQAAAA==.',
Ne='Nedyav:BAAANQADCgIIAgAAAA==.Nefele:BAAANQAECgIIAgAAAA==.Nexbasia:BAAANQAECgUICgAAAA==.',
Ni='Nickyboy:BAAANQAECgIIAQAAAA==.Nightevel:BAAANQADCgYIBgAAAA==.Nihimetal:BAAANQADCgcIDQAAAA==.',
No='Noctum:BAAANQAECgEIAQAAAA==.Nomad:BAAANQADCgYIEAAAAA==.',
Oc='Octt:BAAANQAECgYICgAAAA==.',
Ol='Oldcannabis:BAAANQADCgYICgAAAA==.',
Om='Ominis:BAAANQADCgMIAwAAAA==.',
Oo='Oomaw:BAAANQADCgQIAgAAAA==.',
Or='Ornimus:BAAANQADCgcIGQAAAA==.Ortian:BAAANQAECgEIAQAAAA==.',
Os='Osrs:BAABNQAECoEZAAICAAkJ6SH/BABbAwACAAkJ6SH/BABbAwAAAA==.',
Oz='Ozo:BAAANQAECgMIBAAAAA==.',
Pa='Paiva:BAAANQADCgMIAwAAAA==.Palandor:BAAANQADCgYIBgAAAA==.Pallyscorned:BAAANQAECgUICgAAAA==.Pamgetem:BAAANQAECgQIBQABNQAECgYICgABAAAAAA==.Pampas:BAAANQAECgEIAQAAAA==.Panduh:BAAANQAECgYIEQAAAA==.',
Ph='Phenixy:BAAANQADCgMIAwAAAA==.Phoebell:BAAANQADCgcIEwAAAA==.Phoinix:BAAANQADCgEIAQAAAA==.',
Pi='Pinkducky:BAAANQADCgIIAgAAAA==.',
Po='Ponyo:BAAANQAECgQIBwAAAA==.Poppyseed:BAAANQADCgQIBQAAAA==.',
Pv='Pve:BAAANQADCgIIAgAAAA==.',
Qu='Quiewt:BAAANQAECgQIBwAAAA==.',
Ra='Raddra:BAAANQADCgUIBQAAAA==.Raddrap:BAAANQADCgIIAgAAAA==.Radra:BAAANQAECgIIBwAAAA==.Raeku:BAAANQAECgUICgAAAA==.Raharuto:BAAANQADCggICAAAAA==.Raja:BAAANQAECgIIAgAAAA==.Rav:BAAANQADCgIIAgAAAA==.Razzlor:BAAANQADCgQIBAAAAA==.',
Re='Recoill:BAAANQAECgQIBAAAAA==.Reducto:BAAANQADCgUIBQAAAA==.Retribution:BAAANQAECgQIBwAAAA==.',
Ro='Robomurph:BAAANQADCgQIBAAAAA==.Rolas:BAAANQADCggIHAAAAA==.Ronfax:BAABNQAECoEZAAIHAAkJch71CQAeAwAHAAkJch71CQAeAwAAAA==.Roony:BAAANQADCgIIAQAAAA==.Rooss:BAAANQAECgEIAQAAAA==.Rowdyredneck:BAAANQADCgYIBwABNQAECgMIBAABAAAAAA==.',
Ru='Rul:BAAANQADCgIIAgABNQAECgYIEQABAAAAAA==.',
Ry='Ryllae:BAAANQADCgEIAQABNQAECgYICgABAAAAAA==.Ryuu:BAAANQADCgUIBQAAAA==.Ryuusythe:BAAANQADCgEIAQAAAA==.',
['Rì']='Rììdìì:BAAANQAECgQICAAAAA==.',
['Rï']='Rïchardgear:BAAANQADCggIDAABNQAECgQICAABAAAAAA==.',
Sa='Saint:BAAANQAECgEIAQAAAA==.Salopard:BAAANQADCgQIBAAAAA==.Sarinae:BAAANQAECgMIAwAAAA==.Sarmuc:BAAANQAECgQICQAAAA==.Saryda:BAAANQAECgQIBAAAAA==.Sauda:BAAANQADCgQIBQAAAA==.',
Sc='Schuybusta:BAAANQAECgEIAQAAAA==.Scubagal:BAAANQADCgcIEgAAAA==.',
Se='Sensu:BAAANQADCgcICQAAAA==.Seä:BAAANQAECgQICwAAAA==.',
Sh='Shacktown:BAAANQABCgYICAAAAA==.Shapzan:BAAANQADCgcIFQAAAA==.Sharks:BAAANQAECgEIAgAAAA==.Shivant:BAAANQAECgQIBwAAAA==.',
Si='Silendreas:BAAANQADCgUIBQAAAA==.',
Sl='Sloth:BAAANQAECgQIBQAAAA==.',
Sm='Smalltwngirl:BAAANQAECgIIAgABNQAECgkJGQAHAHIeAA==.',
So='Solaspirus:BAAANQAECgEIAQAAAA==.Solinius:BAAANQADCgYIEAAAAA==.Songbreeze:BAAANQAECgYICwAAAA==.Sonofagun:BAAANQADCgcIDgAAAA==.',
Sp='Spectors:BAAANQAECgQICAAAAA==.',
St='Stabon:BAAANQAECgIIBAAAAA==.Strykah:BAAANQADCgQIBAAAAA==.',
Su='Sugarmarks:BAAANQAECgIIAgAAAA==.',
Sw='Sweetstorm:BAAANQADCggIHAAAAA==.',
Sy='Sydburns:BAAANQABCgYICAAAAA==.',
Ta='Tarixx:BAAANQAECgYICAAAAA==.Tazanoth:BAAANQAECgYIDQAAAA==.',
Te='Tekeelà:BAAANQAECgcIDwAAAA==.',
Th='Theenna:BAAANQADCgEIAQAAAA==.Thianna:BAAANQAECgIIAgAAAA==.Thobu:BAAANQADCgcICQAAAA==.Thornscale:BAAANQAECgUICgAAAA==.',
Ti='Tigolcrittys:BAAANQADCggICQABNQAECgQICAABAAAAAA==.',
To='Tokkem:BAAANQADCgEIAQAAAA==.Tomzombe:BAAANQADCgIIAwAAAA==.Tonguepunch:BAAANQAECgEIAQAAAA==.Tovê:BAAANQADCgEIAQAAAA==.',
Tr='Traveler:BAAANQADCgEIAQAAAA==.Trenko:BAAANQADCgMIAwAAAA==.Troloq:BAAANQAECgUICgAAAA==.',
Tu='Turger:BAAANQADCgUIBQABNQAECgIIBQABAAAAAA==.',
Va='Vahlorraa:BAAANQADCgMIAwAAAA==.Vaimei:BAAANQAECgYICQAAAA==.Vallyna:BAAANQADCgYIBgAAAA==.Vapor:BAAANQAECgEIAQAAAA==.Varaine:BAAANQADCgYICwABNQAECgEIAQABAAAAAA==.',
Ve='Veebs:BAAANQAECgQIBAAAAA==.Vento:BAAANQADCggIDgAAAA==.Verité:BAAANQAECgQIBAAAAA==.',
Vi='Virauca:BAAANQAECgQICAAAAA==.Vizon:BAAANQADCgYIEAAAAA==.',
Vo='Voices:BAAANQAECgIIAgAAAA==.Voltrix:BAAANQADCgMIBAAAAA==.',
Vy='Vynesta:BAAANQAECgYICgAAAA==.',
Wa='Wanagi:BAAANQADCgYIDQAAAA==.Wankz:BAAANQAECgIIAwAAAA==.Warkaestey:BAAANQAECgUICAAAAA==.Warriorguyes:BAAANQAECgEIAgAAAA==.',
Wh='Whomper:BAAANQADCggIDwAAAA==.',
Wi='Widowx:BAAANQAECgEIAQAAAA==.Windshrieker:BAAANQADCgYIBgAAAA==.Wintervalor:BAAANQAECgQIBAAAAA==.',
Wo='Womphunt:BAAANQADCgQIBAABNQAECgQIBAABAAAAAA==.',
Wu='Wulyn:BAAANQADCgcIFgAAAA==.',
Wy='Wylla:BAAANQAECgQIBwAAAA==.',
Xa='Xalethra:BAAANQAECgQIBQAAAA==.',
Xe='Xenophobias:BAAANQADCgQIBQAAAA==.',
Xs='Xsuns:BAAANQAECgQIBgAAAA==.',
Yv='Yve:BAAANQAECgEIAgAAAA==.',
Za='Zalajin:BAAANQADCgUIBwAAAA==.Zarathiel:BAAANQAECgYICgAAAA==.',
Ze='Zeddicus:BAAANQAECgEIAQAAAA==.',
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
