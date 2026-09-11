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

local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Priest-Shadow',}
local provider = {region='US',realm='Durotan',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aakai:BAAANQAECgUIBwAAAA==.Aarmorr:BAAANQAECgIIAgAAAA==.',
Ad='Adinna:BAAANQADCgYIBgAAAA==.',
Ai='Aimeeiove:BAAANQADCgcIDQAAAA==.',
Al='Alcarza:BAAANQABCgQIAgAAAA==.Alchon:BAAANQAECgMIBQAAAA==.Alicalsastre:BAAANQAECgEIAQAAAA==.Alista:BAAANQABCgIIAgAAAA==.Allykat:BAAANQAECgQIBAAAAA==.Alunathsong:BAAANQADCggICAAAAA==.',
Am='Amaith:BAAANQAECgQIBgAAAA==.Amantillado:BAAANQAECgEIAwAAAA==.Amata:BAAANQABCgQIBAAAAA==.Amelianne:BAAANQABCgQIBgAAAA==.Ammastary:BAAANQADCgMIAwAAAA==.',
An='Andrea:BAAANQAECgEIAQAAAA==.Angelec:BAAANQADCgYIDAAAAA==.Anthria:BAAANQADCgQIBAAAAA==.',
Ar='Archonsfury:BAAANQADCgcIBwAAAA==.Arin:BAAANQAECgQIBAAAAA==.',
As='Ashentris:BAAANQADCgYICQAAAA==.Asnew:BAAANQAECgUICAAAAA==.Asura:BAAANQADCggIFAAAAA==.',
At='Athelstan:BAAANQAECgEIAQAAAA==.',
Au='Auralynn:BAAANQADCggIFQAAAA==.Auroriana:BAAANQADCgQIBQAAAA==.',
Av='Averus:BAAANQAECgIIAgAAAA==.',
Az='Azariel:BAAANQAECgIIBAAAAA==.Azuriah:BAAANQAECgIIAgAAAA==.',
Ba='Baane:BAAANQABCgYICAABNQADCgQIBAABAAAAAA==.',
Be='Bealzibub:BAAANQABCgIIAgAAAA==.Bedhead:BAAANQAECgIIAgAAAA==.Belovis:BAAANQAECgYIDAAAAA==.Betsea:BAAANQADCgcIBwABNQAECgIIAwABAAAAAA==.',
Bi='Bidock:BAAANQAECgQIBAAAAA==.Bidoof:BAAANQADCgYIEgAAAA==.Bitemarks:BAAANQADCgYICgAAAA==.Bix:BAAANQAECgIIAgAAAA==.',
Bl='Blackcoat:BAAANQADCgUIBQAAAA==.',
Bo='Boggrog:BAAANQADCgYIDwAAAA==.Boneybob:BAAANQABCgIIAgAAAA==.Boras:BAAANQAECgIIAgAAAA==.',
Br='Breadfriend:BAAANQADCggICAAAAA==.Brightnshiny:BAAANQABCgIIAgAAAA==.Broxxer:BAAANQADCgYIBgAAAA==.',
Bu='Buffsalot:BAAANQADCgYIFAAAAA==.Burningblunt:BAAANQADCgEIAQAAAA==.',
Ca='Castle:BAAANQADCgYIDwAAAA==.Catsinhats:BAAANQADCgMIAgABNQAECgQIBwABAAAAAA==.Catzinhatz:BAAANQADCgUIBQABNQAECgQIBwABAAAAAA==.',
Ce='Cecelya:BAAANQAECgQIBAAAAA==.',
Ch='Chivactdl:BAAANQADCgUICAABNQAECgMIAwABAAAAAA==.Chosenn:BAAANQAECgQIBAAAAA==.Chotek:BAAANQADCgYICgAAAA==.Chunknoriss:BAAANQADCgcIDAABNQAECgMIAwABAAAAAA==.',
Ci='Cilarnen:BAAANQADCgYIDAABNQADCgYIDAABAAAAAA==.',
Cl='Clure:BAAANQAECgMIBQABNQAECgQIBgABAAAAAA==.Clurethyr:BAAANQAECgQIBgAAAA==.',
Co='Conchobhar:BAAANQADCgcIBwAAAA==.Coppertan:BAAANQADCgUICgAAAA==.Corrosion:BAAANQAECgEIAQAAAA==.',
Cr='Cromshade:BAAANQABCgYIBgAAAA==.Cromsteel:BAAANQABCgQIBAAAAA==.Crono:BAAANQADCgYICQAAAA==.Crunchynuget:BAAANQAECgEIAQABNQAECgYIDAABAAAAAA==.',
Ct='Cthuwu:BAAANQADCgQICQABNQAECgUIBgABAAAAAA==.',
Cy='Cybeast:BAAANQAECgMIAwAAAA==.Cynortas:BAAANQADCgUIBQAAAA==.',
Da='Daciana:BAAANQADCggIFQAAAA==.Darkhazel:BAAANQADCgUIBQAAAA==.Darkkromdor:BAAANQAECgQIBQAAAA==.Darloct:BAAANQADCgEIAgAAAA==.',
De='Deadelff:BAAANQAECgQIBAAAAA==.Deathcat:BAAANQAECgQIBwAAAA==.Deathkiss:BAAANQADCgYIBwAAAA==.Deathrixx:BAAANQADCggICAAAAA==.Dedbull:BAAANQADCgcIHAAAAA==.Demodius:BAAANQADCgcIBwAAAA==.Demourdenite:BAAANQADCgYIEQAAAA==.Des:BAAANQABCgIIAgAAAA==.',
Dk='Dkpheonix:BAAANQADCggIFgAAAA==.',
Do='Dolemite:BAAANQAECgEIAQAAAA==.Donalbain:BAAANQAECgYICwAAAA==.Donninban:BAAANQADCgcIDwAAAA==.Doodoobutter:BAAANQAECgIIAgABNQAECgQIBAABAAAAAA==.',
Dr='Draganpriest:BAAANQADCgcIDQAAAA==.Dremar:BAAANQADCgYIEwAAAA==.',
Du='Duarcán:BAAANQADCgEIAQAAAA==.',
Ec='Eclipsy:BAAANQADCgIIAgAAAA==.',
Eg='Eggroll:BAAANQADCgQIBAAAAA==.',
El='Elexander:BAAANQAECgEIAQAAAA==.Elifar:BAAANQADCgUIDgAAAA==.Elyssaris:BAAANQAECgUIBwAAAA==.',
Em='Emmils:BAAANQAECgQIBAAAAA==.Emìly:BAAANQAECgMIAgAAAA==.',
En='Entaria:BAAANQADCgQIBgAAAA==.',
Ep='Ephria:BAAANQAECgUIBwAAAA==.Episkey:BAAANQADCgcIFQAAAA==.',
Er='Eroward:BAAANQAECgMIBwAAAA==.',
Es='Esmay:BAAANQADCggIFgAAAA==.',
Et='Ethren:BAAANQAECgIIAgAAAA==.',
Eu='Eudoxos:BAAANQADCgcIBwAAAA==.',
Ez='Ezikarridge:BAAANQADCggIDgAAAA==.',
Fa='Falcone:BAAANQAECgEIAQAAAA==.Fatherhotdog:BAAANQAECggIEgAAAA==.',
Fe='Felbolter:BAAANQAECgQIBwAAAA==.Fetide:BAAANQADCgIIAgAAAA==.',
Fi='Fiddlefaddle:BAAANQABCgMIAwAAAA==.Filgulfin:BAAANQAECgUIBwAAAA==.Firebringer:BAAANQADCggICAAAAA==.',
Fl='Flamehunter:BAAANQAECgEIAQAAAA==.Flo:BAAANQAECgUIBwAAAA==.Floki:BAAANQAECgEIAQAAAA==.Flowing:BAAANQAECgMIAwAAAA==.',
Fo='Foods:BAAANQAECgQIBgAAAA==.',
Fr='Fripouille:BAAANQADCgMIAwAAAA==.',
['Fæ']='Fæ:BAAANQADCgcIBwAAAA==.',
Ga='Gaboo:BAAANQAECgEIAQAAAA==.',
Gh='Ghostinhale:BAAANQADCgQIBAAAAA==.',
Gi='Gilorion:BAAANQADCggICAAAAA==.',
Gl='Gler:BAAANQADCgQIBAAAAA==.',
Gn='Gnibat:BAAANQABCgUICQAAAA==.',
Go='Goburina:BAAANQAECgcIDQAAAA==.',
['Gí']='Gímlí:BAAANQAECgQIBQAAAA==.',
Ha='Halcyndraag:BAAANQAECgIIAgAAAA==.Handofcope:BAAANQAECgIIAgAAAA==.Hartu:BAAANQAECgIIBAAAAA==.',
He='Healtardo:BAAANQAECgIIAgAAAA==.Hemic:BAAANQAECgMIBAAAAA==.Hemogobblin:BAAANQADCgQIBAAAAA==.Herbalmist:BAAANQABCgQIBQAAAA==.',
Hi='Hircine:BAAANQADCgYICQAAAA==.',
Im='Imwithfloki:BAAANQAECgEIAQAAAA==.',
Ir='Ironmark:BAAANQABCgIIAgAAAA==.',
Is='Isam:BAAANQAECgQIBAAAAA==.Isamidor:BAABNQAECoEZAAICAAkJrR/hBABGAwACAAkJrR/hBABGAwAAAA==.Ismokeu:BAAANQAECgQIBgAAAA==.',
Iv='Ivrys:BAAANQABCgIIAwAAAA==.',
Ja='Jackoneal:BAAANQADCgYICAAAAA==.Jalidelo:BAAANQAECgMIBQAAAA==.Jalyyn:BAAANQADCgEIAQAAAA==.',
Ji='Jingild:BAAANQADCgYIBgAAAA==.',
Jo='Joeyfoxone:BAAANQADCgQIBAAAAA==.Johan:BAAANQAECgUIBwAAAA==.Jokersfists:BAAANQADCgYIDAAAAA==.Joranbragi:BAAANQADCgcICwAAAA==.Jordanjr:BAAANQAECgUICAAAAA==.Josunlee:BAAANQADCgcIBwAAAA==.Jotoonice:BAAANQAECgQIBwAAAA==.',
Jt='Jtoothaordan:BAAANQAECgcIEQAAAA==.',
Ju='Jules:BAAANQADCgcIBwAAAA==.',
Ka='Kaana:BAAANQAECgIIAgAAAA==.Kallista:BAAANQADCgYIDwAAAA==.Karvel:BAAANQAECgIIAgAAAA==.Kaychow:BAAANQAECgUICAAAAA==.',
Ke='Kelonaar:BAAANQAECgYICgAAAA==.',
Kh='Kharys:BAAANQADCgQICQAAAA==.',
Kl='Kloverr:BAAANQAECgQIBgAAAA==.',
Ko='Kombatkarl:BAAANQADCgMIAwAAAA==.',
Kr='Kronixrage:BAAANQAECgIIAgAAAA==.Krooler:BAAANQAECgEIAQAAAA==.',
La='Lanval:BAAANQAECgIIBAAAAA==.',
Le='Leaky:BAAANQADCgQIBQAAAA==.Leetah:BAAANQAECgQIBgAAAA==.Leftblank:BAAANQABCgYIBgAAAA==.',
Li='Lich:BAAANQADCgYIBgAAAA==.Lighthugger:BAAANQAECgQIBAAAAA==.Lilyoptra:BAAANQADCgYIDAAAAA==.Lishalzin:BAAANQADCgcIBwAAAA==.Liszt:BAAANQADCgMIAwAAAA==.Livana:BAAANQADCggIEAABNQADCggIEQABAAAAAA==.',
Lo='Loriane:BAAANQADCgYIBwABNQAECgQIBQABAAAAAA==.Lorianth:BAAANQAECgQIBAAAAA==.Lovegood:BAAANQADCgUIBQAAAA==.',
Ly='Lychi:BAAANQABCgYICAAAAA==.Lylora:BAAANQAECgYIDwAAAA==.',
['Lê']='Lêmonaide:BAAANQAECgQIBQAAAA==.',
Ma='Madclaws:BAAANQAECgUIBwAAAA==.Madman:BAAANQADCgcIEAAAAA==.Magekaestey:BAAANQADCggIDwABNQAECgMIAwABAAAAAA==.Malala:BAAANQADCgMIBgABNQAECgUICQABAAAAAA==.Malyndra:BAAANQADCggICwAAAA==.Marshy:BAAANQADCgUICgAAAA==.Marvolt:BAAANQAECgMIBQAAAA==.',
Me='Metadk:BAAANQAECgEIAQABNQAECgEIAwABAAAAAA==.Metamasters:BAAANQADCgYIBgABNQAECgEIAwABAAAAAA==.',
Mi='Mialtaa:BAAANQADCgQIBAAAAA==.Midgiit:BAAANQADCgYICwABNQAECgQIBQABAAAAAA==.Miniborg:BAAANQADCgYIDwABNQAECgYIDAABAAAAAA==.Misfire:BAAANQABCgYICwAAAA==.Mizzen:BAAANQAECgQIBAABNQAECgcIEAABAAAAAA==.',
Mo='Moejojojo:BAAANQAECgEIAQAAAA==.Moofasaha:BAAANQAECgIIAwAAAA==.Morog:BAAANQAECgQIBwAAAA==.Morragan:BAAANQADCgUICgAAAA==.',
Mu='Mulvan:BAAANQAECgEIAQAAAA==.',
['Mâ']='Mârshy:BAAANQADCgEIAQABNQADCgUICgABAAAAAA==.',
Na='Naler:BAAANQAECgUICAAAAA==.Nanarus:BAAANQAECgUICQAAAA==.Nashalie:BAAANQAECgQIBAAAAA==.',
Ne='Nedyav:BAAANQADCgIIAgAAAA==.Nefele:BAAANQADCggIFQAAAA==.Nexbasia:BAAANQAECgQIBQAAAA==.',
Ni='Nickyboy:BAAANQAECgIIAQAAAA==.Nightevel:BAAANQADCgYIBgAAAA==.Nihimetal:BAAANQADCgcICgAAAA==.',
No='Noctum:BAAANQADCgYICgAAAA==.Nomad:BAAANQADCgUICgAAAA==.',
Oc='Octt:BAAANQAECgYICgAAAA==.',
Ol='Oldcannabis:BAAANQADCgYICgAAAA==.',
Om='Ominis:BAAANQADCgIIAgAAAA==.',
Oo='Oomaw:BAAANQADCgQIAQAAAA==.',
Or='Ornimus:BAAANQADCgYIDwAAAA==.Ortian:BAAANQAECgEIAQAAAA==.',
Os='Osrs:BAABNQAECoEWAAIDAAkJjB9AAwBnAwADAAkJjB9AAwBnAwAAAA==.',
Oz='Ozo:BAAANQAECgEIAQAAAA==.',
Pa='Palandor:BAAANQADCgYIBgAAAA==.Pallyscorned:BAAANQAECgMIBQAAAA==.Pamgetem:BAAANQAECgQIBQAAAA==.Pampas:BAAANQAECgEIAQAAAA==.Panduh:BAAANQAECgYICwAAAA==.',
Ph='Phoebell:BAAANQADCgYIDAAAAA==.Phoinix:BAAANQADCgEIAQAAAA==.',
Pi='Pinkducky:BAAANQADCgEIAQAAAA==.',
Po='Ponyo:BAAANQAECgQIAwAAAA==.Poppyseed:BAAANQADCgQIBQAAAA==.',
Pv='Pve:BAAANQADCgIIAgAAAA==.',
Qu='Quiewt:BAAANQAECgMIAwAAAA==.',
Ra='Raddra:BAAANQADCgUIBQAAAA==.Raddrap:BAAANQADCgIIAgAAAA==.Radra:BAAANQAECgIIBAAAAA==.Raeku:BAAANQAECgMIBQAAAA==.Raharuto:BAAANQADCggICAAAAA==.Raja:BAAANQADCgQIBAAAAA==.Rav:BAAANQADCgIIAgAAAA==.',
Re='Retribution:BAAANQAECgMIAwAAAA==.',
Ro='Ronfax:BAAANQAECggIDgAAAA==.Roony:BAAANQADCgIIAQAAAA==.Rooss:BAAANQADCgcIDwAAAA==.Rowdyredneck:BAAANQADCgYIBwABNQAECgEIAwABAAAAAA==.',
Ru='Rul:BAAANQADCgIIAgABNQAECgYICwABAAAAAA==.',
Ry='Ryllae:BAAANQADCgEIAQABNQAECgQIBAABAAAAAA==.Ryuusythe:BAAANQADCgEIAQAAAA==.',
['Rì']='Rììdìì:BAAANQAECgQIBAABNQAECgQIBQABAAAAAA==.',
['Rï']='Rïchardgear:BAAANQADCggICAABNQAECgQIBQABAAAAAA==.',
Sa='Salopard:BAAANQADCgQIBAAAAA==.Sarinae:BAAANQADCggIEwAAAA==.Sarmuc:BAAANQAECgMIAwAAAA==.Sauda:BAAANQADCgEIAQAAAA==.',
Sc='Schuybusta:BAAANQADCgcIBwAAAA==.Scubagal:BAAANQADCgUICwAAAA==.',
Se='Sensu:BAAANQADCgQIBAAAAA==.Seä:BAAANQAECgIIAwAAAA==.',
Sh='Shacktown:BAAANQABCgIIAgAAAA==.Shapzan:BAAANQADCgUIDgAAAA==.Shivant:BAAANQAECgMIAwAAAA==.',
Si='Silendreas:BAAANQADCgUIBQAAAA==.',
Sl='Sloth:BAAANQAECgEIAQAAAA==.',
Sm='Smalltwngirl:BAAANQAECgIIAgABNQAECggIDgABAAAAAA==.',
So='Solaspirus:BAAANQABCgUIBQAAAA==.Solinius:BAAANQADCgUICgAAAA==.Songbreeze:BAAANQAECgQIBQAAAA==.Sonofagun:BAAANQADCgcIBwAAAA==.',
Sp='Spectors:BAAANQAECgQIBAAAAA==.',
St='Stabon:BAAANQAECgIIAgAAAA==.Strykah:BAAANQADCgQIBAAAAA==.',
Su='Sugarmarks:BAAANQAECgIIAgAAAA==.',
Sw='Sweetstorm:BAAANQADCggIFAAAAA==.',
Sy='Sydburns:BAAANQABCgQIBAAAAA==.',
Ta='Tarixx:BAAANQAECgYICAAAAA==.Tazanoth:BAAANQAECgQIBwAAAA==.',
Te='Tekeelà:BAAANQAECgUIBgAAAA==.',
Th='Theenna:BAAANQADCgEIAQAAAA==.Thianna:BAAANQADCggIFQAAAA==.Thobu:BAAANQADCgIIAgAAAA==.Thornscale:BAAANQAECgMIBQAAAA==.',
Ti='Tigolcrittys:BAAANQADCggICAABNQAECgQIBQABAAAAAA==.',
To='Tokkem:BAAANQADCgEIAQAAAA==.Tomzombe:BAAANQADCgEIAQAAAA==.Tonguepunch:BAAANQAECgEIAQAAAA==.Tovê:BAAANQADCgEIAQAAAA==.',
Tr='Troloq:BAAANQAECgMIBQAAAA==.',
Tu='Turger:BAAANQADCgUIBQABNQAECgIIAwABAAAAAA==.',
Va='Vahlorraa:BAAANQADCgMIAwAAAA==.Vaimei:BAAANQAECgIIAwAAAA==.Vallyna:BAAANQADCgYIBgAAAA==.Vapor:BAAANQAECgEIAQAAAA==.Varaine:BAAANQADCgYICwABNQADCgcIBwABAAAAAA==.',
Ve='Veebs:BAAANQADCggICwAAAA==.Vento:BAAANQADCggIDgAAAA==.Verité:BAAANQADCggIEQAAAA==.',
Vi='Virauca:BAAANQAECgMIBAAAAA==.Vizon:BAAANQADCgUICgAAAA==.',
Vo='Voltrix:BAAANQADCgMIBAAAAA==.',
Vy='Vynesta:BAAANQAECgQIBAAAAA==.',
Wa='Wanagi:BAAANQADCgYICAAAAA==.Wankz:BAAANQAECgEIAQAAAA==.Warkaestey:BAAANQAECgMIAwAAAA==.Warriorguyes:BAAANQAECgEIAQAAAA==.',
Wh='Whomper:BAAANQADCgcIDQAAAA==.',
Wi='Widowx:BAAANQAECgEIAQAAAA==.Windshrieker:BAAANQADCgYIBgAAAA==.',
Wu='Wulyn:BAAANQADCgYIDwAAAA==.',
Wy='Wylla:BAAANQAECgMIAwAAAA==.',
Xa='Xalethra:BAAANQAECgQIBQAAAA==.',
Xe='Xenophobias:BAAANQADCgMIBAAAAA==.',
Xs='Xsuns:BAAANQAECgIIAgAAAA==.',
Yv='Yve:BAAANQAECgEIAQAAAA==.',
Za='Zalajin:BAAANQADCgEIAgAAAA==.Zarathiel:BAAANQAECgQIBAAAAA==.',
Ze='Zeddicus:BAAANQADCggIFgAAAA==.',
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
