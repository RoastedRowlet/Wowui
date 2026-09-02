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
local provider = {region='US',realm='Magtheridon',name='US',type='weekly',zone=53,date='2026-09-01',data={Ac='Acacia:BAAANQADCgcICwAAAA==.',
Ag='Agave:BAAANQAECgEIAQAAAA==.',
Ai='Aizun:BAAANQAECgYIBgAAAA==.',
Ak='Akulagos:BAAANQADCgIIAQAAAA==.',
Al='Alakavahm:BAAANQADCgEIAQAAAA==.Aldenfire:BAAANQADCgMIAwAAAA==.Alesce:BAAANQAECggIDgAAAA==.Alii:BAAANQADCgYICwAAAA==.',
Am='Amenadiel:BAAANQAECgIIAgAAAA==.Amythistle:BAAANQADCgUICgAAAA==.',
An='Andrü:BAAANQAECgIIAgAAAA==.',
Ar='Arnblass:BAAANQAECgEIAQAAAA==.',
As='Ascend:BAAANQADCgcIDAAAAA==.Ashtana:BAAANQAECgIIAgAAAA==.Ashtar:BAAANQAECgMIAwAAAA==.',
Av='Aviee:BAAANQAECgYICgAAAA==.',
Ax='Axidin:BAAANQADCgMIAwAAAA==.',
Az='Azushi:BAAANQADCggICAABNQAECggIDgABAAAAAA==.',
Ba='Babyfox:BAAANQADCgMIAwAAAA==.Babymage:BAAANQAECgYICgAAAA==.Badform:BAAANQADCgQICAAAAA==.Badkitteh:BAAANQADCgUIBwAAAA==.Baelstrom:BAAANQADCgIIAgABNQADCggICAABAAAAAA==.Baendron:BAAANQAECgIIAgAAAA==.Bakaris:BAAANQADCgUIBQAAAA==.Barbarik:BAAANQAECgMIAwABNQAECggIEAABAAAAAA==.Barberry:BAAANQADCgQIBAABNQAECgYICgABAAAAAA==.Baretwallace:BAAANQADCggICQABNQAECgUIBQABAAAAAA==.Bayesian:BAAANQABCgIIAgAAAA==.',
Be='Beefwildfire:BAAANQADCgEIAQAAAA==.Beercheer:BAAANQADCgUIBwAAAA==.Beertholomew:BAAANQADCggIDgAAAA==.Beestkyn:BAAANQADCgUIBQAAAA==.Behodakhtala:BAAANQADCgYICQAAAA==.Bellanzo:BAAANQADCggIDgAAAA==.',
Bi='Bigzee:BAEANQAECgYICgAAAA==.',
Bl='Blargin:BAAANQADCgIIAgAAAA==.Blorgin:BAAANQAECggIDgAAAA==.Bluntmàn:BAAANQADCgUIBQAAAA==.',
Bo='Boogieman:BAAANQADCgYIBgAAAA==.Boohwodoy:BAAANQADCgcIBwAAAA==.Bookers:BAAANQADCggICAAAAA==.Borgo:BAAANQADCgIIAgABNQAECgQIBwABAAAAAA==.Boulangerie:BAAANQAECggIDgAAAA==.Boulior:BAAANQAECgIIAwAAAA==.Bowvice:BAEANQADCgUIBQABNQAECgcICwABAAAAAA==.Boyd:BAAANQAECgcICAAAAA==.',
Br='Brewmungandr:BAAANQADCgcICwAAAA==.Bromayzo:BAAANQABCgIIAgAAAA==.',
Ca='Canadatrash:BAAANQAECgEIAQABNQAECgUIBQABAAAAAA==.Carraway:BAAANQAECgQIBQAAAA==.Cashewz:BAAANQADCgQIBAAAAA==.',
Ce='Ceasarsalad:BAAANQAECgcICwAAAA==.Ceazyweasley:BAAANQAECgEIAQAAAA==.Ceci:BAAANQABCgMIAwAAAA==.Celestriå:BAAANQADCgUICgAAAA==.Cetana:BAAANQAECgUIBQAAAA==.',
Ch='Chadlockb:BAAANQAECggICwAAAA==.Cheesee:BAAANQAECgMIBAAAAA==.Chiko:BAAANQADCggICAAAAA==.Chronite:BAAANQAECgQIBwAAAA==.Chucho:BAAANQADCgYIBgAAAA==.Chárgers:BAAANQADCgYICwAAAA==.',
Ci='Cindr:BAAANQAECggIDAAAAA==.Circumstance:BAAANQAECgUIBQAAAA==.',
Cl='Cleattus:BAAANQAECgEIAQAAAA==.',
Co='Colddblooded:BAAANQAECgIIAwAAAA==.Cololol:BAAANQAECggIDgAAAA==.Compcomp:BAAANQAECgMIBAAAAA==.Compi:BAAANQAECgEIAQABNQAECgMIBAABAAAAAA==.Cooper:BAAANQAECgIIAgAAAA==.Corlys:BAAANQAECgIIAgAAAA==.',
Cr='Crew:BAAANQAECggIDAAAAA==.Cronoz:BAAANQAECgMIAwAAAA==.',
Cu='Cucokai:BAAANQADCggICgAAAA==.Cuddlestomp:BAAANQAECggIDgAAAA==.',
['Cä']='Cämulos:BAAANQAECgEIAQAAAA==.',
['Cí']='Círí:BAEANQAECgIIAgAAAA==.',
Da='Dabbosh:BAAANQADCggIDgAAAA==.Damnhammer:BAAANQAECgQIBQAAAA==.Dandie:BAAANQADCgUIBQAAAA==.Darthjinwoo:BAAANQAECgMIAwAAAA==.Darthmerlin:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.Dasakko:BAAANQAECgMIAwABNQAECgYIBwABAAAAAA==.Dasmonko:BAAANQADCgQIBAABNQAECgYIBwABAAAAAA==.',
Db='Dbowzillaz:BAAANQAECgcIDAAAAA==.',
De='Deathskeeper:BAAANQADCgYICAAAAA==.Demithania:BAAANQADCgQIBAAAAA==.Demonhunterl:BAAANQAECgMIAwAAAA==.',
Dh='Dhsil:BAAANQADCggIDgAAAA==.',
Di='Diabòlic:BAAANQAECggIDAAAAA==.Dirtydiana:BAAANQAECgIIAgAAAA==.',
Dj='Djavol:BAAANQADCggICAAAAA==.',
Do='Doc:BAAANQADCgUICgAAAA==.Doguntarth:BAAANQAECggIDgAAAA==.',
Dr='Drankincup:BAAANQAECgcIEAAAAA==.Drstagger:BAEANQAECgQIBQAAAA==.',
Du='Dullahan:BAAANQADCgQIBAAAAA==.Durotann:BAAANQAECgEIAQAAAA==.Dusios:BAAANQADCgYIBgAAAA==.Duskflower:BAAANQAECgcIBwAAAA==.',
El='Elexandur:BAAANQAECgIIAgAAAA==.Elissa:BAAANQADCgYIBgAAAA==.Eliänna:BAAANQADCgIIAgAAAA==.Elleri:BAAANQAECgEIAQAAAA==.',
Ep='Epnokicks:BAAANQAECgcICAAAAA==.',
Er='Eroicel:BAAANQAECgcICwAAAA==.',
Ev='Evarielle:BAAANQADCgcIDAABNQAECgcICwABAAAAAA==.',
Fa='Fadedhalo:BAAANQADCggIDgAAAA==.Falaya:BAAANQAECgcICwAAAA==.Falst:BAAANQAECgIIAgAAAA==.',
Fe='Fennlar:BAAANQAECgIIAgAAAA==.',
Fl='Flawlessxi:BAAANQAECgMIAwAAAA==.Flyntflosy:BAAANQAECgYICAAAAA==.',
Fo='Fowl:BAAANQAECgQIBAAAAA==.',
Fr='Fragment:BAAANQABCgIIAwAAAA==.',
Fu='Fuehriån:BAAANQAECgcIBwAAAA==.Funstar:BAAANQADCgYIBgABNQAECgcIDAABAAAAAA==.Furyess:BAAANQAECgQIBAAAAA==.',
Ga='Gaelsi:BAAANQADCggIEAAAAA==.Galactic:BAAANQAECgUICAAAAA==.Galgore:BAAANQADCggIEAAAAA==.Garolok:BAAANQAECgIIAgAAAA==.Gascans:BAAANQAECgMIAwAAAA==.Gazelle:BAEANQAECgIIAgAAAA==.Gazerakhan:BAAANQADCgcIDgABNQAECgQIBwABAAAAAA==.Gazerielle:BAAANQAECgQIBwAAAA==.',
Gl='Glizzylizzy:BAAANQAECgYICgAAAA==.',
Go='Gothgrippers:BAAANQADCgcICwAAAA==.',
Gr='Gradeus:BAAANQAECggIDQAAAA==.Granddh:BAAANQAECgYICAAAAA==.Graydius:BAAANQADCgQIBAAAAA==.Greenmango:BAAANQADCgQIBAAAAA==.Grimeclipse:BAAANQADCgcIDgAAAA==.Grovehart:BAAANQADCgYIDAAAAA==.Grumpoo:BAAANQADCgYIBgAAAA==.',
Gu='Gutz:BAAANQADCgEIAQAAAA==.',
Ha='Halestorm:BAAANQADCgUIBgAAAA==.Hattori:BAAANQABCgMIBQAAAA==.Havefun:BAAANQAECgcIDAAAAA==.',
He='Hedonist:BAAANQADCggICAABNQAECggIEAABAAAAAA==.Hellsbringer:BAAANQADCggICQAAAA==.Heretik:BAAANQAECgEIAQAAAA==.Hevnoraak:BAAANQADCgYIBgAAAA==.',
Ho='Hold:BAAANQAECggICAAAAA==.Holycandi:BAAANQAECgEIAQAAAA==.Holydoyle:BAAANQAECgYIBgAAAA==.Holyho:BAAANQADCgYIBgAAAA==.Holyjuice:BAAANQAECgQIBAAAAA==.Hotpøcket:BAAANQAECgYICQAAAA==.',
Hu='Huntlzs:BAAANQAECgMIAwAAAA==.',
Hy='Hyperìen:BAEANQAECggIDgAAAA==.',
['Hø']='Hølý:BAAANQADCgIIAgAAAA==.',
Ic='Icedoggi:BAAANQAECgEIAQAAAA==.',
Im='Immortalmage:BAAANQADCgYIBgAAAA==.Imsopro:BAAANQABCgIIAgAAAA==.',
In='Indeed:BAAANQAECgYICgABNQAFFAEIAQABAAAAAA==.Inferna:BAAANQADCgUIBQAAAA==.Innerbeast:BAAANQAECgQIBAABNQAFFAMIAwABAAAAAA==.Intiq:BAAANQADCgIIAgAAAA==.',
Ir='Irbaboon:BAAANQAECgIIAgAAAA==.Irreletaur:BAAANQAECgcICwAAAA==.',
It='Itisovernow:BAAANQADCgQIBAABNQADCgUIBwABAAAAAA==.Itsovernow:BAAANQADCgUIBwAAAA==.',
Iz='Izimir:BAAANQADCgQIBAAAAA==.',
Ja='Jamloo:BAAANQADCggICQAAAA==.Jangokin:BAAANQAECgcICwAAAA==.Jayiasan:BAAANQAECgMIAwABNQAECggIDgABAAAAAA==.Jazz:BAAANQADCgQIBAAAAA==.',
Ji='Jimbaha:BAAANQADCgQIBAAAAA==.Jinks:BAAANQADCgUIBwAAAA==.',
['Jè']='Jèrmz:BAAANQADCgQIBAAAAA==.',
Ka='Kabang:BAAANQAECgQIBAAAAA==.Kachoo:BAAANQAECgcICAAAAA==.Kaige:BAAANQAECgEIAQAAAA==.Kalithor:BAAANQADCgYICgAAAA==.Kathoes:BAAANQAECgEIAQAAAA==.',
Ke='Kelennin:BAAANQADCgIIAgAAAA==.Kellwildfire:BAAANQAECgQIBQAAAA==.',
Kf='Kfish:BAAANQADCgYICwAAAA==.',
Kh='Khamael:BAAANQADCgcIBwAAAA==.Kheiron:BAAANQAECgYICgAAAA==.',
Ki='Kinu:BAAANQAECgQIBgAAAA==.Kitane:BAAANQADCggIDgAAAA==.',
Kl='Klarina:BAAANQAECgIIAgAAAA==.',
Kn='Knox:BAAANQADCgcIDQAAAA==.',
Ko='Kobieta:BAAANQADCggICAAAAA==.Koda:BAAANQADCgYICgAAAA==.Kosolapaya:BAAANQADCgIIAgAAAA==.',
Ku='Kurolion:BAAANQAECgQIBgAAAA==.Kurzon:BAAANQADCgEIAQAAAA==.',
Kw='Kwanrbless:BAAANQADCgIIAgAAAA==.',
Ky='Kyblade:BAAANQAECgIIAgAAAA==.',
['Kø']='Køs:BAAANQAECgIIAgAAAA==.',
La='Lampro:BAAANQADCgQIBAABNQAECgYICgABAAAAAA==.Lavajato:BAAANQADCgYIBgABNQAECgIIAwABAAAAAA==.',
Le='Leemius:BAAANQAECgIIAgAAAA==.Leosbryn:BAAANQAECgIIAgAAAA==.Leviträ:BAAANQADCgUIBQAAAA==.',
Li='Liable:BAAANQAECgEIAQAAAA==.Ligmadeebliz:BAAANQAECgQIBQAAAA==.Lilfister:BAAANQAECgEIAQABNQAFFAEIAQABAAAAAA==.Lilraz:BAAANQADCgYIBgAAAA==.Liltazzvert:BAAANQAECgMIAwAAAA==.Linksded:BAAANQADCgEIAQAAAA==.Listerfyne:BAAANQADCgQIAgAAAA==.Littlepain:BAAANQADCgEIAQAAAA==.',
Lu='Lucero:BAAANQADCggIDwAAAA==.',
Ly='Lyra:BAAANQADCgMIAwABNQADCgYICwABAAAAAA==.',
Ma='Mabey:BAAANQADCgYICgAAAA==.Maerron:BAAANQADCggICQAAAA==.Mageblprows:BAAANQADCgUICAAAAA==.Mangemonpain:BAAANQADCgYIBgABNQADCgYICgABAAAAAA==.Matikz:BAAANQAECgcICwAAAA==.Maximages:BAAANQADCggIDwAAAA==.Maximon:BAAANQAECgIIAgAAAA==.Maylla:BAAANQADCgcIBwAAAA==.',
Me='Meddle:BAAANQAECggICwAAAA==.Mehrunesd:BAAANQAECgUIBQAAAA==.Meowwmix:BAAANQABCgIIAgAAAA==.Merrydeath:BAAANQADCgMIBAAAAA==.Meyea:BAAANQAECggIDgAAAA==.',
Mi='Miller:BAAANQAECgUIBwAAAA==.Miru:BAAANQADCgUICgAAAA==.Mizdems:BAAANQAECgIIAgAAAA==.',
Mo='Moonfun:BAAANQADCgUIBQABNQAECgcIDAABAAAAAA==.Moufon:BAAANQADCgMIBQAAAA==.',
My='Myrodragon:BAAANQADCggIDgAAAA==.',
['Mé']='Mércy:BAAANQAECgMIBAAAAA==.',
Na='Navah:BAAANQAECgEIAQAAAA==.',
Ne='Neandratroll:BAAANQAECgEIAQAAAA==.Necrodis:BAAANQAECgEIAQABNQAECgMIBAABAAAAAA==.Nezemzy:BAAANQADCgUIBQABNQADCgcICwABAAAAAA==.',
Ni='Nightlevels:BAAANQAECgUIBgAAAA==.',
No='No:BAAANQADCgcIBwAAAA==.Nodens:BAAANQADCgQIBAAAAA==.Nogardd:BAAANQAECgIIAgAAAA==.Notpetya:BAAANQADCgUIBQAAAA==.Nottills:BAAANQADCgYIDAAAAA==.',
Nu='Nuulruk:BAAANQADCggICwAAAA==.',
Ny='Nylaehh:BAAANQAECgEIAQAAAA==.Nyxtro:BAAANQADCgYIBwAAAA==.',
Oi='Oilslick:BAAANQAECgIIAgAAAA==.',
On='Onornu:BAAANQAECggIDgAAAA==.',
Or='Orlidan:BAAANQAECgIIAgAAAA==.',
Ot='Oth:BAAANQAECgcIDAAAAA==.',
Ox='Oxylock:BAAANQAECggIDgAAAA==.',
Pa='Palgeron:BAAANQADCgIIAgAAAA==.Pathlon:BAAANQADCgcICQAAAA==.',
Pe='Peetypirate:BAAANQADCgEIAQAAAA==.Pekapow:BAAANQAECggIDgAAAA==.Peta:BAAANQADCgEIAQAAAA==.',
Ph='Phobius:BAAANQAECgYICgAAAA==.',
Pi='Pinkmango:BAAANQAECgYIBwAAAA==.Pireyne:BAAANQADCgYICgAAAA==.Pistachioz:BAAANQAECgIIAgAAAA==.',
Pl='Playfultouch:BAAANQADCgQIBQAAAA==.Plunkaplunk:BAAANQADCgUIBQAAAA==.',
Po='Polymorphine:BAAANQADCgUIBQAAAA==.Poonzer:BAEANQAECgcICwAAAA==.Porosity:BAAANQAECgMIAwAAAA==.',
Pr='Pretreckless:BAAANQADCgEIAQAAAA==.Proudclod:BAAANQADCgMIAwAAAA==.',
Qe='Qetesh:BAAANQADCgcIBwAAAA==.',
Ra='Ragnan:BAAANQADCgYICAAAAA==.Rain:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Ralinis:BAAANQADCgYIBgAAAA==.Ravicavasar:BAAANQADCgYICgAAAA==.Razfu:BAAANQAECgYICgAAAA==.Razul:BAAANQADCgQIBAAAAA==.',
Re='Redharvest:BAAANQAECgEIAQAAAA==.Relentless:BAAANQADCgYIDAAAAA==.Reznoop:BAEANQADCgcIBwABNQAECgcICwABAAAAAA==.',
Ri='Richardtwist:BAAANQADCgUICgAAAA==.',
Rk='Rkoo:BAAANQADCgYICgAAAA==.',
Ro='Roobee:BAAANQABCgEIAQABNQADCgYICgABAAAAAA==.Roxzor:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.Royok:BAAANQAECgMIAwAAAA==.',
Ru='Ruwey:BAAANQABCgIIAgAAAA==.',
Sa='Sakardi:BAAANQADCgQIBAAAAA==.Sawedoff:BAAANQAECgMIBAAAAA==.',
Sc='Scalybum:BAAANQADCgUIBQAAAA==.Scamall:BAAANQAECgEIAQAAAA==.Schizophreni:BAAANQAECgQIBAABNQAECggIDgABAAAAAA==.Scionoffury:BAAANQAECgQIBAAAAA==.Scotcolumbus:BAAANQAECgIIAgAAAA==.Scullcrusher:BAAANQABCgMIAwAAAA==.',
Se='Secsysalad:BAAANQADCgUIBQABNQAECgcICwABAAAAAA==.Seefoo:BAAANQADCgUIBgAAAA==.Sero:BAAANQADCgcIDAAAAA==.',
Sg='Sgsmagicman:BAAANQADCgYICwAAAA==.',
Sh='Shaamwow:BAAANQADCgcIDQAAAA==.Shade:BAAANQAECgYICgAAAA==.Shadoewolfe:BAAANQADCgUIBwAAAA==.Shageron:BAAANQAECggIDgAAAA==.Shallshock:BAAANQAECgMIBAAAAA==.Shandoe:BAAANQADCgQIBAAAAA==.Shankspec:BAAANQAECgYICAAAAA==.Shaolinshamy:BAAANQADCgYICAAAAA==.Shifterxmag:BAAANQAECgMIAwAAAA==.Shikaca:BAAANQADCgQIBQAAAA==.Shinseina:BAAANQAECgIIAgAAAA==.Shockinawe:BAAANQADCgMIAwAAAA==.Short:BAAANQADCgIIAgAAAA==.Shämash:BAAANQAECgEIAQAAAA==.Shöck:BAAANQADCgYICwAAAA==.',
Si='Siccness:BAAANQAECgIIAwAAAA==.Sieben:BAAANQAECgEIAQAAAA==.Siic:BAAANQADCgUIBQABNQAECgIIAwABAAAAAA==.Sindrex:BAAANQAECgYICgAAAA==.',
Sk='Skwerl:BAAANQADCgMIAwAAAA==.',
Sl='Slurmage:BAAANQAECgIIAgAAAA==.',
Sm='Smittywerben:BAAANQAECgIIAgAAAA==.Smokfun:BAAANQADCgMIAwABNQAECgcIDAABAAAAAA==.',
Sn='Snoozle:BAAANQAECgcIDQAAAA==.',
So='Sololeveling:BAAANQAECgIIAgAAAA==.Sootor:BAAANQADCgYIBgAAAA==.',
Sp='Spags:BAAANQADCgcICwABNQAECgEIAQABAAAAAA==.Sparklefarts:BAAANQADCgYIBgAAAA==.',
St='Starfun:BAAANQADCgYIBgABNQAECgcIDAABAAAAAA==.Steelheals:BAAANQADCgEIAQAAAA==.Stevensiegal:BAAANQADCgIIAgAAAA==.Stormbless:BAAANQAECgcIDAAAAA==.Stormfallz:BAAANQAECgMIBAAAAA==.',
Su='Superfrenzy:BAAANQADCgMIAwAAAA==.Supertotemz:BAAANQAECgEIAQAAAA==.Supervoid:BAAANQAECgIIAgABNQAECgUICAABAAAAAA==.',
Sw='Sweegie:BAAANQAECgEIAQAAAA==.Sweegz:BAAANQADCgYIBgAAAA==.',
Sy='Syds:BAAANQADCgcIDAAAAA==.Synapticzion:BAAANQADCgcICQAAAA==.',
['Sí']='Sílk:BAAANQADCgcIBwAAAA==.',
Ta='Taara:BAAANQAECgQIBwAAAA==.Takeshi:BAAANQABCgIIAgAAAA==.Takkana:BAAANQAECgUIBwAAAA==.Tatsuki:BAAANQABCgIIBAAAAA==.',
Te='Terk:BAAANQAECggIDgAAAA==.',
Th='Thalrymere:BAAANQAECgIIAgAAAA==.Thiccerlegs:BAAANQADCgIIAgAAAA==.',
Ti='Tidebeard:BAAANQAECgcICQAAAA==.Tikz:BAAANQAECgIIAgAAAA==.',
To='Tock:BAAANQAECgcIDAAAAA==.Tokenwarrior:BAAANQADCgYICAAAAA==.',
Tr='Tralina:BAAANQADCgMIAwABNQAECggIDgABAAAAAA==.Trapstâr:BAAANQAECgYIBgABNQAFFAIIAgABAAAAAA==.',
Ts='Tsarfun:BAAANQADCgQIBAABNQAECgcIDAABAAAAAA==.Tsireya:BAAANQADCgEIAQAAAA==.Tsunayoshii:BAAANQADCgEIAQAAAA==.',
Un='Undeadwaifu:BAAANQADCgEIAQAAAA==.Unkledeath:BAAANQADCgUIBQAAAA==.',
Va='Vaeryn:BAAANQADCgcIDAAAAA==.Valesyrin:BAAANQAECgIIAgAAAA==.Vansapanda:BAAANQADCggIEAAAAA==.Vaughn:BAAANQAECgcIDAAAAA==.',
Ve='Veggieboi:BAAANQADCgcIBwAAAA==.Vellast:BAAANQAECgIIAgAAAA==.',
Vi='Viande:BAAANQADCgQIBAAAAA==.Victory:BAAANQAECgEIAQAAAA==.Vigilo:BAAANQAECgUICQAAAA==.Vilhelmina:BAAANQAECgQIBgAAAA==.Viruzdk:BAAANQAECgQIBwAAAA==.',
Vl='Vlad:BAAANQAECgMIAwAAAA==.',
Wa='Wafi:BAAANQADCgYICgAAAA==.Wamp:BAAANQAECgYICgAAAA==.Warwonka:BAAANQAECgYICgAAAA==.Watchurbeard:BAAANQAECgIIAgAAAA==.',
We='Weenrgulpr:BAAANQADCgMIAwAAAA==.',
Wh='Whamass:BAAANQADCgUIBQAAAA==.',
Wi='Windowlicker:BAAANQAECgMIAwAAAA==.Winnydafoo:BAAANQADCgIIAgAAAA==.',
Wr='Wrapfire:BAAANQADCgcICwAAAA==.',
Ya='Yacob:BAAANQAECggIDgAAAA==.Yamarahj:BAAANQAECggIEAAAAA==.',
Yo='Yorikk:BAAANQAECgMIBAAAAA==.',
Yu='Yui:BAAANQABCgIIAgAAAA==.',
Za='Zankanotachi:BAAANQADCggICAAAAA==.Zarmaku:BAAANQADCgcICAAAAA==.Zauber:BAAANQAFFAEIAQAAAA==.Zazie:BAAANQAECgIIAgAAAA==.Zazu:BAAANQADCgEIAQAAAA==.',
Ze='Zepian:BAAANQAECgIIAgAAAA==.',
Zi='Zirraj:BAAANQAECggIDgAAAA==.',
['Èó']='Èówyn:BAAANQADCgUIBQAAAA==.',
['Év']='Évié:BAEANQADCggIEAABNQAECgIIAgABAAAAAA==.',
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
