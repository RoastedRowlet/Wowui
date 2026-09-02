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
local provider = {region='US',realm="Eldre'Thalas",name='US',type='weekly',zone=53,date='2026-09-01',data={Ad='Adesira:BAAANQADCgQIBgAAAA==.',
Ae='Aeslin:BAAANQADCgYIBgABNQADCgYIBgABAAAAAA==.',
Ah='Ahn:BAAANQABCgQICAAAAA==.Ahylin:BAAANQADCgcIDAAAAA==.',
Ai='Ainslie:BAAANQADCgcICgAAAA==.',
An='An:BAAANQADCggICAABNQAECggIDQABAAAAAA==.Antityk:BAAANQADCgUIBQABNQAECgMIAwABAAAAAA==.',
Ar='Aretas:BAAANQAECgEIAQAAAA==.Arriånna:BAAANQADCgYIBgAAAA==.',
As='Asifa:BAAANQADCgQIBAAAAA==.',
At='Atherion:BAAANQAECgIIAgAAAA==.',
Av='Avranarada:BAAANQADCgcIDQAAAA==.Avril:BAAANQAECgEIAQAAAA==.',
Az='Azkara:BAAANQAECgUICAAAAA==.Azung:BAAANQAECgEIAQAAAA==.',
Ba='Babaisyaga:BAAANQAECggIDQAAAA==.Baka:BAAANQAECgEIAQAAAA==.Balinse:BAAANQADCgcIDQAAAA==.Barb:BAAANQADCgUIBgAAAA==.Barrelrollin:BAAANQADCgUICQAAAA==.',
Be='Beastfodays:BAAANQAECgQIBAAAAA==.Bethlahammer:BAAANQADCgYICAABNQADCgYIDAABAAAAAA==.',
Bl='Blawyke:BAAANQADCgYIBgABNQAECgYICgABAAAAAA==.Blizzcon:BAAANQAECgcICAAAAA==.Bloodsurge:BAAANQADCgQIAwAAAA==.',
Bo='Boltzfodayz:BAAANQAECgEIAQAAAA==.Boone:BAAANQADCgMIAwAAAA==.Borrgar:BAAANQADCgcIBwAAAA==.',
Br='Brackle:BAAANQADCggIDgAAAA==.Bracori:BAAANQAECgYICQAAAA==.Brandywynne:BAAANQADCgYIBgAAAA==.Bretcha:BAAANQADCgQIBAAAAA==.Brick:BAAANQAECgEIAQAAAA==.Brightfame:BAAANQAECgEIAQAAAA==.Bronny:BAAANQADCgYIDAAAAA==.',
Bu='Buffshagwell:BAAANQAECgQIBAAAAA==.Butterbllz:BAAANQAECgQIBQAAAA==.',
Ca='Calypsio:BAAANQADCgQIBAABNQADCgUIBQABAAAAAA==.Camany:BAAANQADCgcIDAAAAA==.Caretakerz:BAAANQADCgcIDAAAAA==.Cayin:BAAANQADCggIDgABNQABCgIIBQABAAAAAA==.',
Cl='Clamshell:BAAANQADCgcIDQAAAA==.Claudette:BAAANQADCgIIAgAAAA==.',
Co='Codenike:BAAANQADCgYICQAAAA==.Covertyqt:BAAANQADCgcIDQAAAA==.',
Cp='Cptnhuman:BAAANQADCgYIBgAAAA==.',
Cr='Cromie:BAAANQADCggIDQAAAA==.Crosed:BAAANQADCgQIBAAAAA==.',
Cs='Cshunter:BAAANQADCgYIBgAAAA==.',
Cu='Cubcakes:BAAANQADCggIBQAAAA==.',
['Cõ']='Cõrpses:BAEANQADCgcIDQAAAA==.',
Da='Daboof:BAAANQADCgMIBAAAAA==.Daggere:BAAANQADCgYIBgAAAA==.Danke:BAAANQADCgMIAwAAAA==.Dankz:BAAANQADCgYICgAAAA==.Darkenmicky:BAAANQADCgcIDAAAAA==.Darkmickyz:BAAANQADCgQIBAAAAA==.Darthbobula:BAAANQAECgMIAwAAAA==.Dayloc:BAAANQADCgcIDQAAAA==.',
De='Deataria:BAAANQAECgEIAQAAAA==.Deawin:BAAANQADCgQIBAABNQADCgUICQABAAAAAA==.Delilia:BAEANQAECgEIAQAAAA==.Delryth:BAAANQADCgQIBAAAAA==.Demonikk:BAAANQADCgcICgABNQAECgMIAwABAAAAAA==.',
Dl='Dl:BAAANQAECgEIAQAAAA==.',
Dr='Drinkmormilk:BAAANQADCgEIAQAAAA==.Drogelf:BAAANQADCgEIAQAAAA==.Drogman:BAAANQADCgIIAgAAAA==.',
['Dá']='Dáwnbringer:BAAANQADCgIIBAAAAA==.',
Eb='Ebullition:BAAANQADCgcIDAAAAA==.',
Ed='Edensfury:BAAANQADCgYIDAAAAA==.',
Ee='Eedani:BAAANQADCgIIAgAAAA==.',
Ei='Eigi:BAAANQADCggIDwAAAA==.',
El='Eldanon:BAAANQAECgQIBAAAAA==.Eleyert:BAAANQAECgEIAQAAAA==.Elistann:BAAANQABCgQIBgABNQADCgcIBwABAAAAAA==.Elwe:BAAANQADCgYICgAAAA==.',
En='Enkidu:BAAANQADCgcIDAAAAA==.Enseth:BAAANQADCgcICwAAAA==.',
Er='Erakha:BAAANQADCgcIBwAAAA==.',
Eu='Eulogy:BAAANQADCgYICAABNQAECgcICAABAAAAAA==.',
Ez='Ezerharden:BAAANQABCgEIAQAAAA==.',
Fa='Fairious:BAAANQAECgIIAgAAAA==.',
Fe='Felcon:BAAANQADCgIIAgAAAA==.Fet:BAAANQAECgcIDQAAAA==.',
Fl='Flatline:BAAANQADCgYICwAAAA==.',
Fn='Fngusamungus:BAAANQAECgEIAQAAAA==.',
Fo='Four:BAAANQADCgcIDAAAAA==.',
Fr='Fredwarlock:BAAANQADCgQIBgAAAA==.Frysky:BAAANQADCggICwAAAA==.',
Fu='Futz:BAAANQAECgQICAAAAA==.',
Gn='Gnomicide:BAAANQADCgQIBAAAAA==.',
Gr='Graveborne:BAAANQADCgEIAQAAAA==.Gravess:BAAANQADCgYIBQAAAA==.Gravewin:BAAANQADCgQICgABNQADCgUICQABAAAAAA==.Gravyexpress:BAAANQAECgQIBAAAAA==.Grendelheim:BAAANQADCgIIAwAAAA==.Grogar:BAAANQADCgYICAAAAA==.',
Ha='Hadez:BAAANQADCgUIBQAAAA==.Hagrok:BAAANQABCgQIBgAAAA==.Harmsway:BAAANQADCgQIBAAAAA==.',
Ho='Hocka:BAAANQADCgUIBgAAAA==.Holyyballs:BAAANQADCgcIDQAAAA==.',
Hy='Hydraciel:BAAANQAECgUICAAAAA==.',
['Hì']='Hìroko:BAAANQADCgUIBwAAAA==.',
Im='Im:BAAANQADCgEIAQABNQAECggIDQABAAAAAA==.Imaleaf:BAAANQADCgMIAwAAAA==.Imperius:BAAANQADCgYIBgAAAA==.',
Ip='Iplaydead:BAAANQAECgMIAwAAAA==.',
Ir='Iroh:BAAANQADCgYICgAAAA==.',
Ja='Jawnson:BAAANQADCgcIDQAAAA==.',
Je='Jenefer:BAAANQAECgYICQAAAA==.',
Jo='Jondooz:BAAANQAECgEIAQAAAA==.',
Ka='Kailback:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.Kalcifur:BAAANQAECgYICQAAAA==.Karnelian:BAAANQADCgEIAQABNQAECgEIAgABAAAAAA==.Kasstigate:BAAANQAECgEIAQABNQAECgYICQABAAAAAA==.Kastiel:BAAANQADCgUICQABNQADCgcIDQABAAAAAA==.Katstrider:BAAANQAECgEIAQAAAA==.Kattarea:BAAANQADCgUICAABNQAECgEIAQABAAAAAA==.Kavica:BAAANQADCgYIBgABNQADCgYIBwABAAAAAA==.',
Ke='Keldean:BAAANQADCggIDgAAAA==.Keryka:BAAANQAECggICQAAAA==.',
Kh='Khere:BAAANQADCgQIBQAAAA==.',
Ki='Kiterisa:BAAANQADCgcIDQAAAA==.',
Ku='Kuattieb:BAAANQABCgIIAgAAAA==.',
La='Ladýfinger:BAAANQAECgEIAQABNQAECgYICQABAAAAAA==.Laisidhiel:BAAANQADCgUIDgAAAA==.Lateo:BAAANQAECgMIAwAAAA==.Lawz:BAAANQADCgYICwAAAA==.',
Le='Lelianna:BAAANQADCgMIBAAAAA==.Lexia:BAAANQADCgcICgAAAA==.',
Li='Linnea:BAAANQADCgYIBgAAAA==.',
Lo='Locksative:BAAANQADCgUIBQAAAA==.Longhorn:BAAANQADCgcIDQAAAA==.Lorriena:BAAANQADCgUIBQABNQADCgYICAABAAAAAA==.Lortpegsalot:BAAANQAECgQIBAAAAA==.Lowy:BAAANQADCgUICAAAAA==.',
Lu='Lucena:BAAANQADCgYICwAAAA==.',
Ly='Lyralana:BAAANQADCgMIAwABNQADCgUICQABAAAAAA==.',
Ma='Maberu:BAAANQAECgIIAgABNQAECgYICQABAAAAAA==.Madamholy:BAAANQADCgcIBwAAAA==.Madamkluck:BAAANQADCgUIBQAAAA==.Maglubiyet:BAAANQADCgYICwAAAA==.Magnitood:BAAANQADCgcICAAAAA==.Malphox:BAAANQADCgQICAAAAA==.Manbearcat:BAAANQADCgcIDAAAAA==.Manhole:BAAANQAECgQIBAAAAA==.Markyb:BAAANQADCgYIBgAAAA==.Masamura:BAAANQAECgYIBwAAAA==.Maureanna:BAAANQADCgUICQAAAA==.',
Me='Medanii:BAEANQADCggIDgAAAA==.Melorm:BAAANQADCgMIAwAAAA==.',
Mi='Millizh:BAAANQAFFAEIAQAAAA==.Mirasharu:BAAANQADCgEIAQAAAA==.Mireille:BAAANQADCgMIBAAAAA==.Mitsuri:BAAANQADCgcIDQAAAA==.',
Mo='Moonlïght:BAAANQADCggIDAAAAA==.Morganlefay:BAAANQADCgYIDQAAAA==.Morlyn:BAAANQADCgcIDQAAAA==.Mousereaper:BAAANQAECgEIAQAAAA==.',
My='Mystìc:BAAANQAECgIIAgAAAA==.Mystíc:BAAANQADCgcIDQABNQAECgIIAgABAAAAAA==.',
['Má']='Májorrobot:BAAANQADCgcICgAAAA==.',
Na='Nattisca:BAAANQADCgEIAQAAAA==.',
Ne='Nessà:BAAANQADCgcIDAAAAA==.Neveenn:BAAANQAECgQIBAAAAA==.',
Ni='Nirith:BAAANQADCgIIAgAAAA==.',
No='Nohatcat:BAAANQADCgYICgAAAA==.',
['Nâ']='Nâmii:BAAANQADCgMIAwAAAA==.',
['Nè']='Nèzukõ:BAAANQADCgcIDQAAAA==.',
Oc='Octavius:BAAANQADCgQIBQABNQADCgYIDAABAAAAAA==.',
Oj='Ojore:BAEANQADCgcIDQAAAA==.Ojoverde:BAAANQAECgUICAAAAA==.',
On='Onizuka:BAAANQADCgEIAQABNQADCgYICAABAAAAAA==.Onside:BAAANQAECgEIAQABNQAECgUIBQABAAAAAA==.',
Op='Ophillã:BAAANQADCgUICQABNQADCgcIDAABAAAAAA==.',
Or='Orian:BAAANQADCgQIBwAAAA==.',
Ov='Overflare:BAAANQADCgMIAwAAAA==.',
Oz='Ozz:BAAANQAECgIIAwAAAA==.Ozzerker:BAAANQADCgEIAQAAAA==.',
Pa='Painbreak:BAAANQADCgEIAQABNQADCgcIDAABAAAAAA==.Pallanquin:BAAANQADCgQIBgAAAA==.Papichili:BAAANQADCgYICwAAAA==.Pashnir:BAAANQADCgQIBQAAAA==.',
Pe='Peachey:BAAANQADCgYICwAAAA==.',
Pi='Pigas:BAAANQADCgcICwAAAA==.',
Pr='Prestoresto:BAAANQADCgUICQAAAA==.',
Ps='Psychosix:BAAANQADCgcIDQAAAA==.',
Qu='Quinberos:BAAANQADCgUIBQABNQAECgMIAwABAAAAAA==.',
Ra='Racey:BAAANQADCggICAAAAA==.Ramdel:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.Ramstrider:BAAANQAECgEIAQAAAA==.Ranch:BAAANQADCgYICAAAAA==.Rapture:BAAANQADCgEIAQAAAA==.',
Re='Rengell:BAAANQADCgEIAQAAAA==.',
Ri='Rizerage:BAAANQADCgcIDAAAAA==.',
Ro='Rowena:BAAANQAECgEIAQAAAA==.Rowynna:BAAANQAECgMIAwAAAA==.Roxymonk:BAAANQADCgYIBgAAAA==.',
Ry='Ryztkmtchrch:BAAANQAECgQIBAAAAA==.',
['Rå']='Råti:BAAANQADCgUIBQAAAA==.',
Sa='Sacdk:BAAANQADCgUIBQAAAA==.Safaria:BAAANQADCgYIBwABNQADCgcIDQABAAAAAA==.Saloenus:BAAANQAECgQIBAAAAA==.Saucehoss:BAAANQAECgYICQAAAA==.Saucymac:BAAANQADCggIDwAAAA==.',
Sc='Scofflaw:BAAANQADCgEIAQAAAA==.',
Se='Sefi:BAAANQADCggIDgAAAA==.',
Sh='Shadowflame:BAAANQADCgcIDQAAAA==.Shammygoat:BAAANQADCgcIBwAAAA==.Shaqattack:BAAANQAECgUIBQAAAA==.Sharktide:BAAANQAECgEIAQAAAA==.Shawnella:BAAANQADCgcIDQAAAA==.Shenlune:BAAANQADCgYICwAAAA==.Sheutka:BAAANQADCgQIBAAAAA==.Shiggles:BAAANQADCgUICAAAAA==.Shinaie:BAAANQADCgcIBwAAAA==.Shocknrollz:BAAANQADCgcICgAAAA==.Shtylez:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.',
Si='Silpion:BAAANQADCgcIDAAAAA==.Silth:BAAANQADCgEIAQAAAA==.Sinariel:BAAANQADCggIDgAAAA==.',
Sk='Skarlate:BAAANQADCgYIBgAAAA==.Skâld:BAEANQADCgYIBgAAAA==.',
Sl='Sliko:BAAANQAECgMIAwAAAA==.',
Sm='Smmoke:BAAANQADCgcIDQAAAA==.',
Sn='Sneekypally:BAAANQAECgEIAQAAAA==.',
So='Soull:BAAANQAECgMIAwAAAA==.',
Sp='Sparkie:BAAANQADCgUIBQAAAA==.Spriggan:BAAANQADCgYICAAAAA==.',
Sq='Squashfoot:BAAANQADCgUIBgABNQADCgYIDAABAAAAAA==.',
St='Starface:BAAANQAECgYICQAAAA==.Stellaria:BAAANQADCgYICwAAAA==.Stocktonrush:BAAANQAECggIDAAAAA==.Sturmx:BAAANQADCgcIDQAAAA==.',
Su='Subedei:BAAANQADCgUICAAAAA==.Sunderhorn:BAAANQADCgQIBAAAAA==.Suriaa:BAAANQAECgIIAgAAAA==.',
Sv='Svictis:BAAANQADCgYICwAAAA==.',
Sw='Swami:BAAANQADCgMIAgAAAA==.',
Ta='Tabby:BAAANQADCgcIDgAAAA==.Talila:BAAANQAECgEIAQAAAA==.',
Th='Thaqdaddy:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Thaqknight:BAAANQAECgMIAwAAAA==.Thily:BAAANQADCgIIAgAAAA==.Thror:BAAANQADCggICAAAAA==.',
Ti='Tiergyll:BAAANQABCgIIBAAAAA==.Tirithor:BAAANQAECgMIAwAAAA==.',
To='Togala:BAAANQADCgQIBgABNQADCgcIBwABAAAAAA==.Toothless:BAAANQADCgEIAQAAAA==.Torbin:BAAANQADCgUIBwAAAA==.',
Tr='Tryjinks:BAAANQADCggIDgAAAA==.',
Ty='Tykahndrius:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.',
['Tú']='Túsk:BAAANQADCgUIBAAAAA==.',
['Tý']='Týlius:BAAANQADCggIDgAAAA==.',
Uk='Ukika:BAAANQADCgUIBgABNQADCgcIBwABAAAAAA==.',
Us='Useriòs:BAAANQADCgIIAgAAAA==.',
Ut='Uthilon:BAAANQADCgYIBgAAAA==.',
Va='Valdare:BAAANQADCgcIDAAAAA==.',
Ve='Vedillian:BAAANQADCgYICAAAAA==.',
Vi='Victorr:BAAANQADCgIIAgAAAA==.Vizigoth:BAAANQADCgcIDAAAAA==.',
Vo='Vordell:BAAANQADCggIEAAAAA==.Voyana:BAAANQADCgcIDQAAAA==.',
Vy='Vydragon:BAAANQAECgEIAQABNQAECgUICAABAAAAAA==.Vymage:BAAANQAECgUICAAAAA==.',
['Vá']='Válidüs:BAAANQAECgcIDgAAAA==.',
Wa='Wabìsuke:BAAANQADCggIDwAAAA==.Waterlogged:BAAANQADCgIIAgAAAA==.Waterloo:BAAANQADCgIIAgAAAA==.',
['Wì']='Wìccka:BAAANQADCgUIBQAAAA==.',
Xi='Xifan:BAAANQAECgEIAgAAAA==.',
Yd='Yd:BAAANQAECgEIAQABNQAECggIDQABAAAAAA==.',
Ys='Ys:BAAANQADCgQIBAABNQAECggIDQABAAAAAA==.',
Yt='Yt:BAAANQAECgQICAABNQAECggIDQABAAAAAA==.',
Yz='Yz:BAAANQAECggIDQAAAA==.',
Zl='Zluco:BAAANQAECgYICgAAAA==.',
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
