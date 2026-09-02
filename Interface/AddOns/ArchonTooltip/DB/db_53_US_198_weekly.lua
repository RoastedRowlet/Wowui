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
local provider = {region='US',realm='Skullcrusher',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Abzdh:BAAANQABCgQIBAABNQAECgMIAwABAAAAAA==.Abzmage:BAAANQAECgMIAwAAAA==.',
Ac='Acoreüs:BAEANQADCgcIBwAAAA==.',
Ae='Aed:BAAANQABCgEIAQAAAA==.Aeiay:BAAANQADCgYICgAAAA==.',
Ai='Aibh:BAAANQADCgIIAgAAAA==.',
Al='Alastorias:BAAANQADCgYIBgAAAA==.Alexandrap:BAAANQADCgUIBQAAAA==.Allmighto:BAEANQAFFAEIAQAAAA==.Alyssaxoo:BAAANQAECgQIBQAAAA==.',
An='Androstraz:BAAANQADCggICAAAAA==.Anjkh:BAAANQADCgYIBgAAAA==.Anniesthesia:BAAANQADCgYICwAAAA==.Anoobyss:BAAANQAECgQIBgAAAA==.Anorexorcist:BAAANQABCgEIAQABNQAECgIIAgABAAAAAA==.Anorxxorcist:BAAANQAECgIIAgAAAA==.Anthraxx:BAAANQADCggIDwAAAA==.',
Ar='Arda:BAAANQADCgcICQAAAA==.Arune:BAAANQADCgcICwAAAA==.',
As='Aspyrx:BAAANQAECgEIAQAAAA==.Astelan:BAEANQADCggICwAAAA==.Astärea:BAAANQADCgcIBwAAAA==.',
Ay='Ayeola:BAAANQADCgEIAQAAAA==.',
Az='Aztëk:BAAANQAECgIIAgAAAA==.',
Ba='Bachaterah:BAAANQADCgEIAQAAAA==.Baeldaeg:BAAANQADCgEIAQAAAA==.Bauce:BAAANQADCgQIBAAAAA==.Baxterevo:BAAANQADCggIDQAAAA==.Baybx:BAAANQABCgEIAQAAAA==.',
Be='Bella:BAAANQADCgYIDAAAAA==.',
Bi='Bianchi:BAAANQABCgIIAgAAAA==.Billygoatgrf:BAAANQADCggIDgAAAA==.',
Bl='Blackvomit:BAAANQADCgMIAwAAAA==.Blakkbeard:BAAANQAECgcICwAAAA==.Blazefort:BAAANQAECgQIBwAAAA==.Blitzeye:BAAANQAECgMIAwAAAA==.',
Bo='Bonix:BAAANQADCgIIBAAAAA==.Boozeftw:BAAANQADCgUIBQAAAA==.Bowjobdamage:BAAANQADCgMIAwAAAA==.',
Br='Braincell:BAAANQAECgMIAwABNQADCgEIAQABAAAAAA==.Breemonic:BAAANQAECgMIAwAAAA==.Brewdie:BAAANQABCgMIAwAAAA==.Bruce:BAAANQAECgYICAAAAA==.',
Bu='Bubblekush:BAAANQAECgIIAgAAAA==.Bubbleøseven:BAAANQADCgQIBAAAAA==.Butturz:BAAANQADCgYICwAAAA==.',
Ca='Cailleach:BAAANQAECgEIAQAAAA==.',
Ce='Celeryman:BAAANQADCgYICwAAAA==.Centuro:BAAANQAECgEIAQAAAA==.',
Ch='Chobi:BAAANQAECgYICgAAAA==.',
Ci='Cinnamen:BAAANQADCgUIBQAAAA==.',
Cl='Clearstoned:BAAANQADCgUIBQABNQAECgUIBgABAAAAAA==.',
Co='Coaa:BAAANQAECgEIAQAAAA==.Colossus:BAAANQAECgIIAgAAAA==.Contrap:BAAANQAECgIIAgAAAA==.Coolbreeze:BAAANQADCggIDgAAAA==.Corpsgrinder:BAAANQAECgIIAgAAAA==.Cowbroni:BAAANQAECgEIAQAAAA==.',
Cr='Crashöut:BAAANQADCgEIAQAAAA==.',
Cu='Curtland:BAAANQADCgYICwAAAA==.',
Cz='Cz:BAAANQADCgQIBAAAAA==.Czera:BAAANQADCgMIAwAAAA==.',
Da='Dahialkahina:BAAANQADCgEIAQAAAA==.Darkmeadow:BAAANQADCgYIDAAAAA==.Dastard:BAAANQAECgIIAwAAAA==.',
De='Deadplank:BAAANQADCgYIBwAAAA==.Deathlyfrost:BAAANQADCgEIAQAAAA==.Deftonia:BAAANQAECgEIAQAAAA==.Degenerate:BAAANQADCgMIAwAAAA==.Demonbläde:BAAANQADCgcIBwAAAA==.Devondric:BAAANQAECgEIAQAAAA==.Devotion:BAAANQADCgUIBQABNQAECgYICgABAAAAAA==.Devotional:BAAANQAECgYICgAAAA==.',
Di='Dimepiece:BAAANQADCgUIBwAAAA==.Dithi:BAAANQADCgQIBAAAAA==.Divinaputits:BAAANQADCgEIAQAAAA==.',
Do='Dommiemommie:BAAANQAECgIIAgAAAA==.Doozpal:BAAANQAECgUIBwAAAA==.Dorinspins:BAEANQADCgIIAgAAAA==.',
Dr='Drakonman:BAAANQAECgEIAQAAAA==.Draynen:BAAANQAECgYIBgABNQAECgcIDQABAAAAAA==.Drbanner:BAAANQADCgUIBQAAAA==.Drezd:BAAANQAECgQIBAAAAA==.',
Du='Duck:BAAANQADCgQIBAABNQADCgYICwABAAAAAA==.Dulcïnea:BAAANQADCggIBQAAAA==.Dumpymilk:BAAANQADCgUIBQABNQADCgEIAQABAAAAAA==.',
Ea='Eao:BAAANQAECgIIAgAAAA==.',
Ed='Edrana:BAAANQADCgYIBgABNQADCgYIBgABAAAAAA==.',
Eh='Ehvyn:BAAANQADCgIIAgAAAA==.',
El='Elitistjerk:BAAANQADCgEIAQAAAA==.Ellisis:BAAANQADCggIDQAAAA==.',
Em='Emriq:BAAANQAECgEIAQAAAA==.',
En='Enmai:BAAANQAECgEIAQAAAA==.',
Ep='Epiphany:BAAANQADCgYICAAAAA==.',
Eu='Eulogy:BAAANQAECgIIAgAAAA==.',
Ev='Evangelise:BAAANQADCgEIAQAAAA==.',
Ex='Exxitus:BAAANQAECgIIAgAAAA==.',
Fa='Faith:BAAANQAECgMIAwAAAA==.Fatblackcow:BAAANQADCgEIAQAAAA==.',
Fe='Felachio:BAAANQAECgEIAQAAAA==.',
Fj='Fjörgyn:BAAANQAECggIDAAAAA==.',
Fo='Fork:BAAANQADCggIDgAAAA==.Fozziedaburr:BAAANQAECgEIAQAAAA==.',
Fr='Frasierkrane:BAAANQADCgQIBwAAAA==.',
Ga='Galie:BAAANQAECgIIAgAAAA==.Garrahoth:BAAANQADCggICwAAAA==.',
Ge='Gekk:BAAANQAECgEIAQAAAA==.',
Gi='Giaus:BAAANQAECgIIAgAAAA==.Girby:BAAANQADCgcIBwAAAA==.',
Gl='Glaaive:BAAANQADCgEIAQAAAA==.',
Go='Gobzilla:BAAANQADCggIDgAAAA==.Gonn:BAAANQADCgUIBQAAAA==.Goub:BAAANQAECgIIAgAAAA==.',
Gr='Grapefantuh:BAAANQADCgcIBwAAAA==.Grimrieber:BAAANQAECgIIAgAAAA==.Gromn:BAAANQAECgUICQAAAA==.',
Ha='Hashed:BAAANQADCgUIBQAAAA==.Hashi:BAAANQADCgIIAgAAAA==.Haysevoker:BAAANQAECgcICwAAAA==.',
He='Henn:BAAANQADCgYIBgAAAA==.',
Ho='Holycopter:BAAANQADCgYICwAAAA==.Holymojo:BAAANQAECgMIAwAAAA==.Hoodler:BAEANQAECgcIDAAAAA==.Hoodlery:BAEANQAECgUIBQABNQAECgcIDAABAAAAAA==.Hoofjob:BAAANQAECgcIDAAAAA==.',
Hu='Huskydots:BAAANQAECgQIBgAAAA==.',
['Hé']='Hércules:BAAANQADCgIIAgAAAA==.',
Ib='Iblastpants:BAAANQADCgIIAgAAAA==.',
Id='Idd:BAAANQADCgMIBgAAAA==.',
Ig='Iggyy:BAAANQAECgEIAQAAAA==.',
In='Inflammo:BAAANQABCgEIAQAAAA==.',
Ir='Irila:BAAANQADCgQIBgAAAA==.',
It='Ithrein:BAAANQADCgYIBgAAAA==.',
Ja='Jakè:BAAANQAECgIIAgAAAA==.Jangutu:BAAANQAECgQIBAAAAA==.Jasono:BAAANQADCgQIBAAAAA==.Jaspy:BAAANQAECgIIAgAAAA==.',
Je='Jeffdennis:BAAANQAECgIIAgAAAA==.',
Ji='Jimmybuffler:BAAANQADCgQIBAAAAA==.',
Jo='Jonra:BAAANQADCgIIAgAAAA==.Josefbugman:BAAANQAECgIIAgAAAA==.',
Ju='Juju:BAAANQADCggIFAAAAA==.Juktal:BAAANQADCgcICwAAAA==.Justyn:BAAANQADCggIDgAAAA==.',
Ka='Kainz:BAAANQADCgcIBwAAAA==.Kaoscontrol:BAAANQADCgQIBAAAAA==.Kazaju:BAAANQAECgQIAwAAAA==.',
Ki='Kialorstus:BAAANQADCgYIBgAAAA==.Kirbo:BAAANQADCgEIAQAAAA==.Kitagawa:BAAANQADCggIDAAAAA==.',
Ko='Kolakua:BAAANQADCgQIBAAAAA==.Korianth:BAAANQADCggIDwAAAA==.Korlon:BAAANQADCgYIBgAAAA==.Kouw:BAAANQAECgIIAgAAAA==.',
Kr='Kradyn:BAAANQADCgYICAAAAA==.Kragfoerend:BAAANQADCgYIFwAAAA==.Krankenstein:BAAANQAECgEIAQAAAA==.Kriix:BAAANQAECgIIAgAAAA==.Krusnik:BAAANQADCgMIAwAAAA==.',
Ku='Kuhtta:BAAANQADCgcICAAAAA==.Kumdobeast:BAAANQAECgIIAgAAAA==.Kuothe:BAAANQADCggIDAAAAA==.',
Ky='Kyotpal:BAAANQADCgIIAgAAAA==.',
La='Lazyriver:BAAANQADCgcICwABNQADCgUICwABAAAAAA==.',
Le='Legoland:BAAANQADCggIDgAAAA==.Lesnichii:BAAANQADCggIDgAAAA==.Lewakex:BAAANQAECgIIAgAAAA==.Leyninade:BAAANQADCgMIAwAAAA==.',
Li='Lightbrngr:BAAANQAECgMIAwAAAA==.Liilpeep:BAAANQAECgEIAQAAAA==.Lilbertha:BAAANQAECgIIAgAAAA==.Lilchigirl:BAAANQADCgYIBgAAAA==.Lildipster:BAAANQADCgQIBAABNQADCgEIAQABAAAAAA==.Limitlessone:BAAANQADCgYIBgAAAA==.Liptonaysti:BAAANQADCgUIBwAAAA==.Lissandine:BAAANQAECgMIAwAAAA==.',
Lo='Lotharn:BAAANQADCgMIAQAAAA==.Lowdy:BAAANQAECgIIAwAAAA==.',
Lu='Luulk:BAAANQADCgIIAgAAAA==.',
['Lì']='Lìllith:BAAANQAECgEIAQAAAA==.',
Ma='Magemagerson:BAAANQAECgMIAwAAAA==.Magnuss:BAAANQAECgIIAgAAAA==.Mahini:BAAANQADCgYIBgAAAA==.Malleus:BAAANQADCggIDgAAAA==.Mammutos:BAAANQADCgcIDQAAAA==.Manion:BAAANQAECgIIAgAAAA==.Manipepper:BAAANQADCgcICgAAAA==.Manippiez:BAAANQADCgYICwAAAA==.Manipulation:BAAANQADCgEIAQAAAA==.Mannarchy:BAAANQADCgQIBAAAAA==.Maplemaga:BAAANQADCgUIBgAAAA==.Masochista:BAAANQAECgcICgAAAA==.Mastavas:BAAANQAECgEIAQAAAA==.Mastric:BAEANQAECgIIAgAAAA==.',
Mc='Mccaffrey:BAAANQAECgEIAQAAAA==.',
Me='Meetch:BAAANQAECgMIAwAAAA==.Megdar:BAAANQADCggIDwAAAA==.Melledreu:BAAANQAECgQICgAAAA==.Merix:BAAANQAECgMIBAAAAA==.Mestea:BAAANQADCggIDgAAAA==.Mewing:BAAANQADCgYIBgABNQAECgQICAABAAAAAA==.',
Mi='Miraclemill:BAAANQADCgYICgAAAA==.Mirra:BAAANQADCgYIDAAAAA==.',
Mo='Mojobtw:BAAANQADCgcIBwAAAA==.Mortamur:BAAANQAECgIIAgAAAA==.Mortelinnos:BAAANQAECgIIAgAAAA==.',
My='Mysticguru:BAAANQAECgMIAwAAAA==.Mythrax:BAAANQAECgMIAwAAAA==.',
Na='Naisu:BAAANQADCgEIAQAAAA==.Naradrae:BAAANQADCgUIBQAAAA==.Narodaran:BAAANQADCgcIBwAAAA==.Naughtyrawr:BAAANQADCgYICwAAAA==.',
Ne='Nevets:BAAANQAECgIIAwAAAA==.Nevrs:BAAANQADCggICAAAAA==.Newworld:BAAANQADCgMIAwAAAA==.',
Ni='Nimit:BAAANQADCggIDgAAAA==.',
No='Notzee:BAAANQABCgIIAgAAAA==.Novic:BAAANQAECgIIAgAAAA==.',
Nu='Nualia:BAAANQAECgMIAwAAAA==.',
['Né']='Némésis:BAAANQADCgUIBwAAAA==.',
Oj='Ojaks:BAAANQADCgYIBgAAAA==.',
Or='Orbian:BAAANQADCgcIBwAAAA==.Orobus:BAAANQADCgMIAwAAAA==.',
Os='Oscassey:BAAANQAECgEIAQAAAA==.',
Ox='Oxley:BAAANQAECgEIAQAAAA==.',
Pa='Paladingus:BAAANQAECgEIAQAAAA==.Pandidin:BAAANQAECgIIAgAAAA==.Pauldrons:BAAANQAECgQICgAAAA==.',
Pe='Peenar:BAAANQADCgUIBQAAAA==.Pejorative:BAAANQADCgYIBgAAAA==.',
Ph='Pharlock:BAAANQADCgcIDQAAAA==.',
Pl='Plankie:BAAANQADCgUICAAAAA==.',
Po='Pooterdiddle:BAAANQADCggIDgAAAA==.',
Pr='Prohealin:BAAANQAECgIIAgAAAA==.',
Pt='Ptiteagacee:BAAANQADCgYIBgAAAA==.',
Pu='Pufdaddy:BAAANQADCggICQAAAA==.Puffymuffinz:BAAANQADCgcIDAAAAA==.Puffymüffins:BAAANQADCgIIAgABNQADCgcIDAABAAAAAA==.Pumpkinq:BAAANQAECgcICAAAAA==.',
Py='Pyre:BAAANQABCgIIAgAAAA==.',
['Pì']='Pìkachu:BAAANQAECgIIAgAAAA==.',
Ra='Rasmus:BAAANQAECgIIAgAAAA==.Raykwan:BAAANQADCgUIBQAAAA==.Rayquaza:BAAANQAECgIIAgAAAA==.Razzmatazz:BAAANQAECgEIAQAAAA==.',
Re='Reddeyes:BAAANQADCgcIDQAAAA==.Rescue:BAAANQAECgIIAgAAAA==.Reva:BAEANQADCgEIAQABNQADCggICwABAAAAAA==.',
Ro='Roasted:BAAANQAECgMIAwAAAA==.Rockma:BAAANQAECggIAQAAAA==.Rollandburn:BAAANQAECgMICAAAAA==.Roxymigurdia:BAAANQAECgMIAwAAAA==.',
Ru='Rufföaddy:BAAANQAECgIIAgAAAA==.Runeesa:BAAANQADCgcIDQAAAA==.',
Ry='Rylena:BAAANQAECgEIAQAAAA==.Ryuke:BAAANQADCggICAAAAA==.',
['Râ']='Râmên:BAAANQADCgEIAQAAAA==.',
Sa='Sagikos:BAEANQADCggIDwAAAA==.Sardras:BAAANQAECgIIAgAAAA==.Sark:BAAANQAECgYIBwAAAA==.Sathor:BAAANQAECgUIBwAAAA==.Saucyjenkins:BAAANQADCgQIBAAAAA==.',
Sc='Scranton:BAAANQADCgQIBgAAAA==.',
Se='Semprefi:BAAANQABCgIIAgAAAA==.',
Sh='Shaani:BAAANQADCgMIAwAAAA==.Shadowfoot:BAAANQADCgUIBQAAAA==.Shadowhut:BAAANQADCgQIBAAAAA==.Shalanot:BAEANQAECgUICQABNQADCggIDwABAAAAAA==.Shamerific:BAAANQABCgQIBAAAAA==.Shammooz:BAAANQAECgQICgAAAA==.Shinier:BAAANQAECgMIBQAAAA==.Shockwoods:BAAANQADCgEIAQAAAA==.',
Si='Silversmage:BAAANQADCgQIBAAAAA==.',
Sl='Slappywappy:BAAANQAECgMIAwAAAA==.',
Sm='Smorcin:BAAANQAECgEIAQAAAA==.',
So='Softdeath:BAAANQADCgYIBgAAAA==.',
Sp='Spellnchill:BAAANQADCgYICQAAAA==.Spintor:BAAANQADCggIDgAAAA==.',
Sq='Squidseye:BAAANQADCgQIBAAAAA==.',
St='Steelwaves:BAAANQADCgQIBQAAAA==.Stricker:BAAANQADCggIDwAAAA==.',
Su='Surious:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Sw='Sweettooth:BAAANQADCgMIAwAAAA==.',
Sy='Symmas:BAAANQADCggIAQAAAA==.Syphian:BAAANQADCgQIBAAAAA==.',
Ta='Taishigi:BAAANQADCggIDQAAAA==.Tapewyrm:BAAANQAECgEIAQAAAA==.',
Te='Tecknique:BAAANQAECgMIAwAAAA==.Teedge:BAAANQAECgYICgAAAA==.',
Th='Thanos:BAAANQADCgMIAwAAAA==.Thatwhitekid:BAAANQADCggICQAAAA==.Thorodron:BAAANQADCgEIAQAAAA==.Thundera:BAAANQAECgQIBQAAAA==.',
Ti='Timberdoc:BAAANQADCgYIDAAAAA==.Tindril:BAAANQAECgIIAgAAAA==.',
To='Tolan:BAAANQAECgMIBAAAAA==.Totemtartt:BAAANQAECgMIBAAAAA==.Toxicai:BAAANQADCgcIDQAAAA==.',
Tr='Treyman:BAAANQADCggIEAAAAA==.Tribune:BAAANQAECgYICAABNQAECgYICgABAAAAAA==.Trinitree:BAAANQADCgcIDAAAAA==.Trinkler:BAAANQADCgYIDgAAAA==.',
Tu='Tunka:BAAANQADCgQIBAAAAA==.',
Tw='Twist:BAAANQADCggIDgAAAA==.',
Ty='Tychondris:BAAANQAECgIIAgAAAA==.',
Ul='Ulsoga:BAAANQADCgcIDQAAAA==.',
Un='Unbórn:BAAANQADCgQIBAAAAA==.Undeadbeast:BAAANQADCgUIBQAAAA==.',
Ut='Utica:BAAANQADCgQIBgAAAA==.',
Va='Vaiko:BAAANQADCgMIAwAAAA==.Vaspara:BAAANQADCgMIAwAAAA==.',
Ve='Vergalis:BAAANQADCgYIDAAAAA==.',
Vi='Vileknight:BAAANQAECgEIAQAAAA==.Visz:BAAANQADCgQIBAAAAA==.',
Vo='Voidlìlíth:BAAANQAECgMIAwAAAA==.Voidwak:BAAANQADCgYICgAAAA==.Vorronni:BAAANQAECgEIAQAAAA==.',
Wa='Wardo:BAAANQAECgcIDAAAAA==.',
We='Wellen:BAAANQADCgUICQAAAA==.Werewolf:BAAANQADCgcIDAAAAA==.',
Wh='Whitepikmin:BAAANQADCgQIBAAAAA==.',
Wi='Wilmer:BAAANQAECgIIAgAAAA==.Wily:BAAANQADCggIDgAAAA==.Wiseguy:BAAANQADCgQIBAAAAA==.',
Wo='Wookieweener:BAAANQAECgQIBAABNQAECgcICAABAAAAAA==.',
Wr='Wravc:BAAANQAECgIIAgAAAQ==.',
Xo='Xoroth:BAAANQAECgUIBQAAAA==.',
Ya='Yargonz:BAAANQADCggICAAAAA==.Yargzdk:BAAANQAECgcIDAAAAA==.',
Ye='Yeyol:BAAANQADCggICQAAAA==.',
Yo='Yolius:BAAANQADCgUIBwAAAA==.Yoogi:BAAANQADCgQIBAABNQADCggICwABAAAAAA==.',
Yu='Yungnetero:BAAANQAECgQIBwAAAA==.Yunikon:BAAANQADCgcIEQABNQADCgEIAQABAAAAAA==.',
Za='Zavorotnuk:BAAANQADCgEIAQAAAA==.',
Ze='Zelluss:BAAANQAECgQIBAAAAA==.',
Zh='Zhaphiria:BAAANQADCggICQABNQAECgcIDQABAAAAAA==.',
Zo='Zoomies:BAAANQADCgYIBgAAAA==.',
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
