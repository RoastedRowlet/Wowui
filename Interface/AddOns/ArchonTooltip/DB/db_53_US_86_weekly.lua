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

local lookup = {'Unknown-Unknown','Rogue-Subtlety','Hunter-BeastMastery','Rogue-Assassination','Hunter-Marksmanship','DeathKnight-Unholy','Priest-Holy',}
local provider = {region='US',realm="Eldre'Thalas",name='US',type='weekly',zone=53,date='2026-09-08',data={Ad='Adesira:BAAANQADCgQIBgAAAA==.Adrastus:BAAANQADCgYIBwABNQAECgQICAABAAAAAA==.',
Ae='Aeslin:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Ah='Ahn:BAAANQABCgYIDgAAAA==.Ahylin:BAAANQADCgcIDAAAAA==.',
Ai='Ainslie:BAAANQADCgcIEQAAAA==.',
An='An:BAAANQAECgQIBAABNQAECgkJGAACAB4fAA==.Anarose:BAAANQADCggICAAAAA==.Antityk:BAAANQADCgYICwABNQAECgQICAABAAAAAA==.',
Ar='Aragorn:BAAANQADCgQIBQAAAA==.Aretas:BAAANQAECgQIBQAAAA==.Arrianne:BAAANQADCgYIBgAAAA==.Arriånna:BAAANQADCgYIBgAAAA==.',
As='Asifa:BAAANQADCgYICQAAAA==.',
At='Atherion:BAAANQAECgQIBgAAAA==.',
Av='Avranarada:BAAANQAECgIIAgAAAA==.Avril:BAAANQAECgEIAQAAAA==.',
Az='Azkara:BAAANQAECgcIDwAAAA==.Azung:BAAANQAECgUIBgAAAA==.',
Ba='Babaisyaga:BAABNQAECoEYAAIDAAkJxiEBBQBFAwADAAkJxiEBBQBFAwAAAA==.Baka:BAAANQAECgIIAwAAAA==.Balinse:BAAANQADCggIDgABNQAECgQIBAABAAAAAA==.Barb:BAAANQADCgUICwAAAA==.Barrelrollin:BAAANQADCgYIDwAAAA==.',
Be='Beastfodays:BAAANQAECgYIDgAAAA==.Bethlahammer:BAAANQADCgYIDQABNQADCggIDgABAAAAAA==.',
Bl='Blackleaf:BAAANQADCgMIAwAAAA==.Blawyke:BAAANQADCgYIBgAAAA==.Blizzcon:BAAANQAECgcIEAAAAA==.Bloodsurge:BAAANQADCgQIAwAAAA==.Blushies:BAAANQADCgQIBAABNQADCggIEgABAAAAAA==.',
Bo='Boltzfodayz:BAAANQAECgEIAQAAAA==.Boone:BAAANQADCgMIAwAAAA==.Borrgar:BAAANQADCggIDwAAAA==.',
Br='Brackle:BAAANQAECgEIAQAAAA==.Bracori:BAAANQAECgcIEAAAAA==.Brandywynne:BAAANQAECgMIAwAAAA==.Bretcha:BAAANQADCgQIBAAAAA==.Brick:BAAANQAECgMIBAAAAA==.Brightfame:BAAANQAECgQIBQAAAA==.Bronny:BAAANQADCggIFAAAAA==.',
Bu='Buffshagwell:BAAANQAECgUIBQAAAA==.Butterbllz:BAAANQAECgYICwAAAA==.',
Ca='Calypsio:BAAANQADCgQIBAABNQADCgcIDAABAAAAAA==.Camany:BAAANQAECgIIAgAAAA==.Caretakerz:BAAANQAECgEIAQAAAA==.Cartus:BAAANQADCgQIBAABNQADCgcIEwABAAAAAA==.Cayin:BAAANQAECgQIBAABNQABCgYICwABAAAAAA==.',
Cl='Clamshell:BAAANQAECgIIAgAAAA==.Claudette:BAAANQAECgMIAwAAAA==.Clayier:BAAANQADCgUIBQAAAA==.',
Co='Codenike:BAAANQAECgEIAQAAAA==.Covertyqt:BAAANQAECgIIAgAAAA==.',
Cp='Cptnhuman:BAAANQAECgIIAgAAAA==.',
Cr='Cromie:BAAANQADCggIDQAAAA==.Crosed:BAAANQADCgQIBAAAAA==.',
Cs='Cshunter:BAAANQADCgYIBwAAAA==.',
Cu='Cubcakes:BAAANQADCggIBQAAAA==.',
['Cõ']='Cõrpses:BAEANQAECgIIAgABNQADCgYIBgABAAAAAA==.',
Da='Daboof:BAAANQADCgMIBAAAAA==.Daggere:BAAANQADCgYIDQAAAA==.Danke:BAAANQADCgMIBAAAAA==.Dankz:BAAANQADCgYIDAAAAA==.Darkenmicky:BAAANQADCgcIEwAAAA==.Darkmickyz:BAAANQADCggIDAAAAA==.Darthbobula:BAAANQAECgMIAwAAAA==.Dayloc:BAAANQADCgcIDQAAAA==.',
De='Deataria:BAAANQAECgEIAQAAAA==.Deawin:BAAANQADCgQIBAABNQADCgYIDwABAAAAAA==.Delilia:BAEANQAECgEIAQABNQAECggICQABAAAAAA==.Delryth:BAAANQADCgYIBQAAAA==.Demonikk:BAAANQAECgIIAgABNQAECgQICAABAAAAAA==.Demontyk:BAAANQADCggICAABNQAECgQICAABAAAAAA==.Desception:BAAANQADCgMIAwAAAA==.',
Dl='Dl:BAAANQAECgMIBAAAAA==.',
Dr='Drazhoath:BAAANQAECgIIAgAAAA==.Drdrill:BAAANQADCgYIBgAAAA==.Drimbirt:BAAANQADCgMIAwAAAA==.Drinkmormilk:BAAANQADCgIIAgAAAA==.Drogelf:BAAANQADCgUIBwAAAA==.Drogman:BAAANQADCgIIAgAAAA==.',
Du='Dumbledore:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.',
['Dá']='Dáwnbringer:BAAANQADCgIIBAAAAA==.',
Eb='Ebullition:BAAANQADCggIFAAAAA==.',
Ee='Eedani:BAAANQADCgUIBwAAAA==.',
Ei='Eigi:BAAANQADCggIEwAAAA==.',
El='Eldanon:BAAANQAECgQICAAAAA==.Eleyert:BAAANQAECgMIAwAAAA==.Elistann:BAAANQABCgYICgABNQADCggIDwABAAAAAA==.Elwe:BAAANQADCggIDwAAAA==.',
En='Enkidu:BAAANQADCggIFAAAAA==.',
Er='Erakha:BAAANQADCgcIBwAAAA==.',
Eu='Eulogy:BAAANQADCgYICAABNQAECgcIEAABAAAAAA==.',
Ez='Ezerharden:BAAANQABCgEIAQAAAA==.',
Fa='Fairious:BAAANQAECgQIBgAAAA==.',
Fe='Felcon:BAAANQADCgQIBgAAAA==.Fet:BAABNQAECoEYAAMCAAkJtxzABQDcAgACAAgJXB/ABQDcAgAEAAEJjgcBMQA/AAAAAA==.',
Fh='Fhatbashtud:BAAANQADCgUIBQAAAA==.',
Fl='Flatline:BAAANQAECgEIAQAAAA==.Flinnt:BAAANQABCgYICgABNQADCggIDwABAAAAAA==.',
Fn='Fngusamungus:BAAANQAECgEIAQAAAA==.',
Fo='Four:BAAANQADCgcIFgAAAA==.',
Fr='Fredwarlock:BAAANQADCgQIBgAAAA==.Frysky:BAAANQADCggIDwAAAA==.',
Fu='Furiousv:BAAANQADCgUIBQAAAA==.Futz:BAAANQAECgQIDAAAAA==.',
Ga='Gahnzul:BAAANQADCgUIBQAAAA==.Gajitbek:BAAANQADCgMIAwAAAA==.',
Gn='Gnomicide:BAAANQADCgYICQAAAA==.',
Go='Gooberpea:BAAANQABCgYICAAAAA==.',
Gr='Graveborne:BAAANQADCgEIAQAAAA==.Gravess:BAAANQADCgUIBQAAAA==.Gravewin:BAAANQADCgQICgABNQADCgYIDwABAAAAAA==.Gravyexpress:BAAANQAECgQICAAAAA==.Grendelheim:BAAANQADCgIIAwAAAA==.Grogar:BAAANQADCgYIDAAAAA==.',
Ha='Hadez:BAAANQADCgUIBQAAAA==.Hagrok:BAAANQABCgQIBgAAAA==.Hantak:BAAANQADCgMIAwAAAA==.Harmsway:BAAANQADCgQIBAAAAA==.Hathaendron:BAAANQABCgIIAgAAAA==.',
Ho='Hocka:BAAANQADCgUIBgAAAA==.Holysmight:BAAANQADCgUIBQAAAA==.Holyyballs:BAAANQADCggIFQAAAA==.Howlymandel:BAAANQADCgQIBAABNQADCgQIBAABAAAAAA==.',
Hy='Hydraciel:BAAANQAECgYIDgAAAA==.',
['Hì']='Hìroko:BAAANQADCgYIDQAAAA==.',
Ic='Icedemon:BAAANQABCgQIBAAAAA==.Icupapi:BAAANQADCgEIAQAAAA==.Icynips:BAAANQABCgEIAQAAAA==.',
Im='Im:BAAANQADCgEIAQABNQAECgkJGAACAB4fAA==.Imabigman:BAAANQADCgcIBwAAAA==.Imaleaf:BAAANQAECgQIBAAAAA==.Imperius:BAAANQAECgEIAQAAAA==.',
Ip='Iplaydead:BAAANQAECgQICAAAAA==.',
Ir='Iroh:BAAANQADCgcIEQAAAA==.',
Is='Ismokeprot:BAAANQADCgMIAwAAAA==.',
Ja='Jawnson:BAAANQAECgIIAgAAAA==.',
Je='Jenefer:BAAANQAECgcIEAAAAA==.',
Jo='Jondooz:BAAANQAECgcIBwAAAA==.',
Ka='Kailback:BAAANQADCgUICQABNQAECgIIAwABAAAAAA==.Kalcifur:BAAANQAECgcIEAAAAA==.Karnelian:BAAANQADCgEIAQABNQAECgEIAgABAAAAAA==.Karras:BAAANQADCgUIBQAAAA==.Kashisht:BAAANQADCgYIBgAAAA==.Kasstigate:BAAANQAECgQIBQABNQAECgcIEAABAAAAAA==.Kastiel:BAAANQAECgQIBAAAAA==.Katstrider:BAAANQAECgMIBAAAAA==.Kattarea:BAAANQADCgUICAABNQAECgMIBAABAAAAAA==.Kavica:BAAANQADCgYICQABNQAECgEIAQABAAAAAA==.',
Ke='Keldean:BAAANQAECgEIAQAAAA==.Keryka:BAAANQAECggIDwAAAA==.',
Kh='Khere:BAAANQADCgUIBgAAAA==.',
Ki='Kiterisa:BAAANQAECgIIAgAAAA==.',
Ko='Kohn:BAAANQAECgIIAgAAAA==.Kona:BAEANQADCgYIBgAAAA==.',
Ku='Kuattieb:BAAANQABCgIIAgAAAA==.',
La='Ladýfinger:BAAANQAECgQIBQABNQAECgcIEAABAAAAAA==.Laisidhiel:BAAANQADCgYIFAAAAA==.Lateo:BAAANQAECgQIBwAAAA==.Lawz:BAAANQADCggIEwAAAA==.',
Le='Lelianna:BAAANQADCgMIBAAAAA==.Lexia:BAAANQADCgcIEAAAAA==.',
Li='Lilturtz:BAAANQADCgUIBQABNQADCggIEgABAAAAAA==.Linnea:BAAANQADCgcIDQAAAA==.',
Lo='Locksative:BAAANQADCggIDQAAAA==.Longhorn:BAAANQAECgEIAQAAAA==.Lorriena:BAAANQADCgUIBQABNQADCgYICAABAAAAAA==.Lortpegsalot:BAAANQAECgUICQAAAA==.Lowy:BAAANQAECgIIAgAAAA==.',
Lu='Lucena:BAAANQADCggIEwAAAA==.',
Ly='Lyralana:BAAANQADCgQIBwABNQADCgUIDgABAAAAAA==.',
Ma='Maberu:BAAANQAECgUIBwABNQAECgcIEAABAAAAAA==.Madamholy:BAAANQADCgcIDgAAAA==.Madamkluck:BAAANQADCgUIBQAAAA==.Maglubiyet:BAAANQADCgYIEQAAAA==.Magnitood:BAAANQADCggICQAAAA==.Malphox:BAAANQADCgQICAAAAA==.Manbearcat:BAAANQADCgcIEwAAAA==.Manhole:BAAANQAECgQICAAAAA==.Markyb:BAAANQADCgYIBgAAAA==.Masamura:BAAANQAECgcIDgAAAA==.Maureanna:BAAANQADCgUIDgAAAA==.',
Me='Medanii:BAEANQAECgQIBAAAAA==.Melorm:BAAANQADCgYICQAAAA==.',
Mi='Millizh:BAACNQAFFIEGAAMDAAUJrRg8AQANAQADAAMJIR48AQANAQAFAAMJvRJ6BAD3AAA1AAQKgRoAAwUACQmPJQ0BAL8DAAUACQlIJQ0BAL8DAAMABgnOIgofADUCAAAA.Mirasharu:BAAANQADCgMIBAAAAA==.Mireille:BAAANQADCgMIBAAAAA==.Mitsuri:BAAANQAECgEIAQAAAA==.Mitzuky:BAAANQADCgMIAwAAAA==.',
Mo='Moonlïght:BAAANQADCggIDwAAAA==.Morganlefay:BAAANQADCggIFQAAAA==.Morlyn:BAAANQADCggIFQAAAA==.Morregan:BAAANQADCggICAAAAA==.Mousereaper:BAAANQAECgMIBAAAAA==.',
My='Mydnight:BAAANQABCgIIAgAAAA==.Mystìc:BAAANQAECgIIAwAAAA==.Mystíc:BAAANQADCgcIEwABNQAECgIIAwABAAAAAA==.',
['Má']='Májorrobot:BAAANQAECgUIBQAAAA==.',
['Mé']='Ménopáwz:BAAANQADCgIIAgABNQAECgkJFwAGAJwjAA==.',
Na='Nattisca:BAAANQADCgQIBQAAAA==.',
Ne='Nessà:BAAANQAECgEIAQAAAA==.Neveenn:BAAANQAECgQIDAAAAA==.',
Ni='Nirith:BAAANQADCgQIBgAAAA==.',
No='Nohatcat:BAAANQADCggIEgAAAA==.',
['Nâ']='Nâmii:BAAANQADCgMIAwAAAA==.',
['Nè']='Nèzukõ:BAAANQADCggIDwAAAA==.',
Oc='Octavius:BAAANQADCgUICgABNQADCggIDgABAAAAAA==.',
Oj='Ojore:BAEANQADCggIFQAAAA==.Ojoverde:BAAANQAECgYIDgAAAA==.',
On='Onizuka:BAAANQADCgEIAQAAAA==.Onside:BAAANQAECgEIAQABNQAECgYICwABAAAAAA==.',
Op='Ophillã:BAAANQADCgYIDwABNQAECgEIAQABAAAAAA==.',
Or='Orian:BAAANQADCgQIBwAAAA==.',
Oz='Ozz:BAAANQAECgUICAAAAA==.Ozzerker:BAAANQADCgEIAQAAAA==.Ozzullr:BAAANQADCggICAAAAA==.',
Pa='Painbreak:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Pallanquin:BAAANQADCgQIBgAAAA==.Papichili:BAAANQADCgYIEQAAAA==.Pashnir:BAAANQADCgQIBQAAAA==.',
Pe='Peachey:BAAANQADCggIEwAAAA==.',
Pi='Pigas:BAAANQAECgIIAgAAAA==.',
Pr='Prestoresto:BAAANQADCgYIDwAAAA==.',
Ps='Psychosix:BAAANQADCgcIDwAAAA==.',
Qu='Quinberos:BAAANQADCggIDwABNQAECgMIAwABAAAAAA==.',
Ra='Racey:BAAANQADCggICAAAAA==.Ramdel:BAAANQADCgUICAABNQAECgMIBAABAAAAAA==.Ramstrider:BAAANQAECgMIBAAAAA==.Rapture:BAAANQAECgEIAQAAAA==.',
Re='Rengell:BAAANQADCgQIBAAAAA==.',
Rh='Rheagall:BAAANQAECgcIBgAAAA==.Rhodetta:BAAANQAECgIIAgAAAA==.',
Ri='Rizepriest:BAAANQADCgIIAgABNQADCgcIEQABAAAAAA==.Rizerage:BAAANQADCgcIEQAAAA==.',
Ro='Rowena:BAAANQAECgQICQAAAA==.Rowynna:BAAANQAECgMIAwAAAA==.Roxy:BAAANQADCgYIBgAAAA==.Roxymonk:BAAANQADCgYIBgAAAA==.Royalviaman:BAAANQADCgMIAwAAAA==.',
Ry='Ryztkmtchrch:BAAANQAECgYICgAAAA==.',
['Rå']='Råti:BAAANQADCgUIBQAAAA==.',
Sa='Sacdk:BAAANQAECgMIAwAAAA==.Safaria:BAAANQADCgYIBwABNQADCggIFQABAAAAAA==.Saloenus:BAAANQAECgYICgAAAA==.Saucehoss:BAAANQAECgcIEAAAAA==.Saucymac:BAAANQADCggIDwAAAA==.',
Sc='Scofflaw:BAAANQADCgEIAQAAAA==.',
Se='Sefi:BAAANQAECgEIAQAAAA==.',
Sh='Shadowflame:BAAANQADCggIFQAAAA==.Shammygoat:BAAANQADCggIDAAAAA==.Shaqattack:BAAANQAECgYICwAAAA==.Sharktide:BAAANQAECgMIBAAAAA==.Shawnella:BAAANQAECgIIAgAAAA==.Shenlune:BAAANQADCgYICwAAAA==.Sheutka:BAAANQADCgYICQAAAA==.Shiggles:BAAANQADCgYIDgAAAA==.Shinaie:BAAANQADCgcIDgAAAA==.Shocknrollz:BAAANQAECgEIAQAAAA==.Shogún:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Shtylez:BAAANQADCggIDgABNQAECgQICAABAAAAAA==.',
Si='Silpion:BAAANQADCgcIEwAAAA==.Silth:BAAANQADCgIIAgAAAA==.Sinariel:BAAANQAECgQIBAAAAA==.',
Sk='Skarlate:BAAANQADCgYIBgAAAA==.Skâld:BAEANQADCgYICwAAAA==.',
Sl='Sliko:BAAANQAECgQIBwAAAA==.',
Sm='Smmoke:BAAANQAECgIIAgAAAA==.',
Sn='Sneekypally:BAAANQAECgEIAgAAAA==.Snowballs:BAAANQABCgIIAgAAAA==.',
So='Soull:BAAANQAECgQIBwAAAA==.',
Sp='Sparkie:BAAANQADCgcIDAAAAA==.Spriggan:BAAANQADCgYICAAAAA==.',
Sq='Squashfoot:BAAANQADCggIDgAAAA==.',
St='Starface:BAAANQAECgcIEAAAAA==.Steelytree:BAAANQADCgMIAwAAAA==.Stellaria:BAAANQAECgQIBAAAAA==.Stocktonrush:BAABNQAECoEXAAIGAAkJnCOyAQC7AwAGAAkJnCOyAQC7AwAAAA==.Sturmx:BAAANQAECgIIAgAAAA==.',
Su='Subedei:BAAANQAECgEIAQAAAA==.Sunderhorn:BAAANQADCgYICQAAAA==.Suriaa:BAAANQAECgUIBwAAAA==.',
Sv='Svictis:BAAANQADCgcIEgAAAA==.',
Sw='Swami:BAAANQADCgMIAgAAAA==.',
Ta='Talila:BAAANQAECgIIAgAAAA==.',
Th='Thaqdaddy:BAAANQADCgYIBgABNQAECgQIBgABAAAAAA==.Thaqknight:BAAANQAECgQIBgAAAA==.Thesthamenth:BAAANQADCgYIBgAAAA==.Thily:BAAANQADCgIIAgAAAA==.Thorwallen:BAAANQABCgYIDAABNQADCggIDwABAAAAAA==.Thror:BAAANQAECgEIAQAAAA==.',
Ti='Tiergyll:BAAANQABCgIIBAAAAA==.Tirithor:BAAANQAECgQIBwAAAA==.',
To='Tockell:BAAANQADCgMIAwAAAA==.Togala:BAAANQADCgUIBwABNQADCgcIBwABAAAAAA==.Toothless:BAAANQAECgEIAQAAAA==.Torbin:BAAANQADCgcIDgAAAA==.Touchmywave:BAAANQADCgIIAgABNQAECgYIDgABAAAAAA==.',
Tr='Tryjinks:BAAANQAECgEIAQAAAA==.',
Ts='Tsunameh:BAAANQADCgQIBAABNQAECgQICAABAAAAAA==.',
Ty='Tykahndrius:BAAANQADCgcICwABNQAECgQICAABAAAAAA==.',
['Tú']='Túsk:BAAANQADCgYIBwAAAA==.',
['Tý']='Týlius:BAAANQAECgEIAQAAAA==.',
Uk='Ukika:BAAANQADCgUICgABNQADCgcIBwABAAAAAA==.',
Us='Useriòs:BAAANQADCgIIAgAAAA==.',
Ut='Uthilon:BAAANQAECgIIAgAAAA==.',
Va='Valdare:BAAANQADCggIFAAAAA==.Validorn:BAAANQADCgcIBwAAAA==.',
Ve='Velduar:BAAANQADCgQIBAAAAA==.',
Vi='Victorr:BAAANQADCgMIBAAAAA==.Viktorius:BAAANQADCgMIAwAAAA==.Vizigoth:BAAANQAECgIIAQAAAA==.',
Vo='Vordell:BAAANQAECgIIAgABNQAECgIIAgABAAAAAA==.Voyana:BAAANQADCggIFQAAAA==.',
Vy='Vydragon:BAAANQAECgEIAQABNQAECggIEAABAAAAAA==.Vymage:BAAANQAECggIEAAAAA==.',
['Vá']='Válidüs:BAABNQAECoEZAAIHAAkJix+hAgBpAwAHAAkJix+hAgBpAwAAAA==.',
['Vã']='Vãsh:BAAANQADCgYIBgAAAA==.',
Wa='Wabìsuke:BAAANQADCggIDwAAAA==.Waterlogged:BAAANQADCgIIAgAAAA==.Waterloo:BAAANQADCgIIAgAAAA==.',
['Wì']='Wìccka:BAAANQADCgUIBQAAAA==.',
Xi='Xi:BAAANQADCggICAAAAA==.Xifan:BAAANQAECgEIAgAAAA==.',
Yd='Yd:BAAANQAECgEIAQABNQAECgkJGAACAB4fAA==.',
Ys='Ys:BAAANQADCgQIBQABNQAECgkJGAACAB4fAA==.',
Yt='Yt:BAAANQAECgQICAABNQAECgkJGAACAB4fAA==.',
Yz='Yz:BAABNQAECoEYAAMCAAkJHh+LAgBNAwACAAkJGh+LAgBNAwAEAAIJUxtVJACfAAAAAA==.',
Za='Zashawa:BAAANQADCgQIBAAAAA==.',
Zl='Zluco:BAAANQAECgcIEQAAAA==.',
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
