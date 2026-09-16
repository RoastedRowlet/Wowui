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

local lookup = {'Unknown-Unknown','Rogue-Subtlety','Shaman-Restoration','Hunter-BeastMastery','Druid-Feral','Priest-Holy','Monk-Mistweaver','Rogue-Assassination','DemonHunter-Havoc','DeathKnight-Blood','Paladin-Holy','Druid-Guardian','Mage-Arcane','Hunter-Marksmanship','DeathKnight-Unholy','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Shaman-Enhancement',}
local provider = {region='US',realm="Eldre'Thalas",name='US',type='weekly',zone=53,date='2026-09-15',data={Ad='Adesira:BAAANQADCgQIBgAAAA==.Adrastus:BAAANQADCgYIBwABNQAECgYIDgABAAAAAA==.',
Ae='Aeslin:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Ah='Ahn:BAAANQABCgYIDgAAAA==.Ahylin:BAAANQADCgcIDAAAAA==.',
Ai='Ainslie:BAAANQAECgEIAQAAAA==.',
Al='Alerana:BAAANQADCggICAAAAA==.Altria:BAAANQADCgQIBAAAAA==.',
An='An:BAAANQAECgQICAABNQAECgkJIQACANciAA==.Anarose:BAAANQAECgIIAgAAAA==.Antityk:BAAANQADCggIEwABNQAECgYIDgABAAAAAA==.',
Ar='Aragorn:BAAANQADCgQIBQAAAA==.Aretas:BAAANQAECgUICgAAAA==.Arrianne:BAAANQADCgYIBgAAAA==.Arriånna:BAAANQADCgYIBgAAAA==.Artemist:BAAANQAECggIBgAAAA==.',
As='Asifa:BAAANQADCgcIEAAAAA==.',
At='Atherion:BAAANQAECgQICgAAAA==.',
Av='Avranarada:BAAANQAECgUIBwAAAA==.Avril:BAAANQAECgEIAQAAAA==.',
Az='Azkara:BAABNQAECoEZAAIDAAgJ9BcUJgA0AgADAAgJ9BcUJgA0AgAAAA==.Azung:BAAANQAECgUIBgAAAA==.',
Ba='Babaisyaga:BAABNQAECoEhAAIEAAkJiyIpBwBfAwAEAAkJiyIpBwBfAwAAAA==.Baka:BAAANQAECgIIAwAAAA==.Balinse:BAAANQAECgQIBAABNQAECgQIBwABAAAAAA==.Barb:BAAANQADCgYIEQAAAA==.Barrelrollin:BAAANQADCgYIDwAAAA==.',
Be='Beastfodays:BAABNQAECoEYAAIEAAgJwhEJLABNAgAEAAgJwhEJLABNAgAAAA==.Bethlahammer:BAAANQADCgYIDQABNQADCggIFQABAAAAAA==.',
Bi='Billcritin:BAAANQAECgUIBQAAAA==.',
Bl='Blackleaf:BAAANQADCgQIBwAAAA==.Blawyke:BAAANQADCgYIBgABNQAECgkJGgAFAFAaAA==.Blizzcon:BAABNQAECoEeAAIGAAkJpiCiAwBvAwAGAAkJpiCiAwBvAwAAAA==.Bloodsurge:BAAANQADCgQIAwAAAA==.Blushies:BAAANQAECgMIBAAAAA==.',
Bo='Boltzfodayz:BAAANQAECgEIAQAAAA==.Boone:BAAANQADCgMIAwAAAA==.Borrgar:BAAANQAECgEIAQAAAA==.',
Br='Brackle:BAAANQAECgIIAwAAAA==.Bracori:BAABNQAECoEbAAIHAAgJ6gwJEADAAQAHAAgJ6gwJEADAAQAAAA==.Brandywynne:BAAANQAECgYICQAAAA==.Bretcha:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.Brick:BAAANQAECgYICgAAAA==.Brightfame:BAAANQAECgUICgAAAA==.Bronny:BAAANQAECgMIAwAAAA==.',
Bu='Buffshagwell:BAAANQAECgUIDAAAAA==.Butterbllz:BAAANQAECgcIEgAAAA==.',
Ca='Calypsio:BAAANQADCgQIBAABNQADCggIEgABAAAAAA==.Camany:BAAANQAECgQIBgAAAA==.Captinkrunch:BAAANQADCgEIAQAAAA==.Caretakerz:BAAANQAECgMIBAAAAA==.Cartus:BAAANQADCgUICAABNQAECgEIAQABAAAAAA==.Cayin:BAAANQAECgUICQABNQABCgYICwABAAAAAA==.',
Cl='Clamshell:BAAANQAECgUIBwAAAA==.Claudette:BAAANQAECgMIAwAAAA==.Clayier:BAAANQADCgYICwAAAA==.',
Co='Codenike:BAAANQAECgIIAwAAAA==.Covertyqt:BAAANQAECgUIBwAAAA==.',
Cp='Cptnhuman:BAAANQAECgUIBwAAAA==.',
Cr='Cromie:BAAANQADCggIFQAAAA==.Crosed:BAAANQADCgQIBAAAAA==.',
Cs='Cshunter:BAAANQADCgYIBwAAAA==.',
Cu='Cubcakes:BAAANQADCggIBQAAAA==.',
['Cõ']='Cõrpses:BAEANQAECgUIBwABNQADCgYIBgABAAAAAA==.',
Da='Daboof:BAAANQADCgQICAAAAA==.Daggere:BAAANQADCgYIEwAAAA==.Danke:BAAANQADCgYICgAAAA==.Dankz:BAAANQADCgYIEAAAAA==.Darkenmicky:BAAANQADCgcIEwAAAA==.Darkmickyz:BAAANQAECgEIAQAAAA==.Darthbobula:BAAANQAECgMIAwAAAA==.Dayloc:BAAANQADCgcIDQAAAA==.',
De='Deataria:BAAANQAECgIIBAAAAA==.Deawin:BAAANQADCgQIBAABNQADCgYIDwABAAAAAA==.Delilia:BAEANQAECggICQABNQAECggIDAABAAAAAA==.Delryth:BAAANQADCgYIBQAAAA==.Demonikk:BAAANQAECgIIAgABNQAECgYIDgABAAAAAA==.Demontyk:BAAANQADCggIEAABNQAECgYIDgABAAAAAA==.Desception:BAAANQADCgQIBwAAAA==.',
Di='Diadochi:BAAANQAECgQIBAAAAA==.',
Dl='Dl:BAAANQAECgYICgAAAA==.',
Dr='Drakkarr:BAAANQADCgIIAgAAAA==.Drazhoath:BAAANQAECgQIBAAAAA==.Drdrill:BAAANQADCgYIBgAAAA==.Drimbirt:BAAANQADCgQIBwAAAA==.Drinkmormilk:BAAANQADCgMIAwAAAA==.Drogelf:BAAANQADCgYIDQAAAA==.Drogman:BAAANQADCgIIAgAAAA==.',
Du='Dumbledore:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.',
['Dá']='Dáwnbringer:BAAANQADCgIIBAAAAA==.',
Eb='Ebullition:BAAANQAECgEIAQAAAA==.',
Ed='Edensfury:BAAANQADCggIFQAAAA==.',
Ee='Eedani:BAAANQADCgUIBwAAAA==.',
Ei='Eigi:BAAANQAECgUIBQAAAA==.',
El='Eldanon:BAAANQAECgQIDQAAAA==.Eleyert:BAAANQAECgUICAAAAA==.Elistann:BAAANQADCggICQABNQAECgEIAQABAAAAAA==.Elwe:BAAANQAECgQIBAAAAA==.',
Em='Embaku:BAAANQADCggICAABNQAECgYIDQABAAAAAA==.',
En='Enkidu:BAAANQAECgEIAQAAAA==.Enseth:BAAANQAECgMIAwAAAA==.',
Er='Erakha:BAAANQAECgIIAgAAAA==.Erandria:BAAANQADCgUIBQABNQADCgUIDgABAAAAAA==.',
Eu='Eulogy:BAAANQADCgYICAABNQAECgkJHgAGAKYgAA==.',
Ez='Ezerharden:BAAANQABCgEIAQAAAA==.Ezki:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Fa='Fairious:BAAANQAECgQICgAAAA==.',
Fe='Felcon:BAAANQADCgYICAAAAA==.Fet:BAABNQAECoEYAAMCAAkJtxyECAC5AgACAAgJXB+ECAC5AgAIAAEJjgeQSAA+AAAAAA==.',
Fh='Fhatbashtud:BAAANQADCgYICwAAAA==.',
Fl='Flatline:BAAANQAECgMIBAAAAA==.Flinnt:BAAANQABCggIEQABNQAECgEIAQABAAAAAA==.',
Fn='Fngusamungus:BAAANQAECgEIAQAAAA==.',
Fo='Four:BAAANQAECgIIAgAAAA==.',
Fr='Fredwarlock:BAAANQADCgQIBgAAAA==.Frysky:BAAANQAECgIIAgAAAA==.',
Fu='Furiousv:BAAANQADCgUIBQAAAA==.Futz:BAAANQAECgQIDwAAAA==.',
Ga='Gahnzul:BAAANQADCgUIBQAAAA==.Gajitbek:BAAANQADCgMIAwAAAA==.Galah:BAAANQAECgIIAgAAAA==.',
Gn='Gnomicide:BAAANQADCgcIEAAAAA==.',
Go='Gooberpea:BAAANQABCgYICgAAAA==.',
Gr='Graveborne:BAAANQADCgYIBwAAAA==.Gravess:BAAANQADCgUIBQAAAA==.Gravewin:BAAANQADCgQICgABNQADCgYIDwABAAAAAA==.Gravyexpress:BAABNQAECoEWAAIJAAcJBBxKFABNAgAJAAcJBBxKFABNAgAAAA==.Grendelheim:BAAANQADCgQIBgAAAA==.Grogar:BAAANQADCgYIDQAAAA==.',
Gu='Gula:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
Ha='Hadez:BAAANQADCgUIBQAAAA==.Hagrok:BAAANQABCgQIBgAAAA==.Hantak:BAAANQADCgMIBgAAAA==.Harmsway:BAAANQADCgcICwAAAA==.Hathaendron:BAAANQABCgIIAgAAAA==.',
He='Hephaestus:BAAANQADCgIIAgAAAA==.',
Ho='Hocka:BAAANQADCgUIBgAAAA==.Holysmight:BAAANQAECgEIAQAAAA==.Holyumo:BAAANQADCgYIBgAAAA==.Holyyballs:BAAANQAECgIIAgAAAA==.Howlymandel:BAAANQADCgQIBAABNQAECgUICgABAAAAAA==.',
Hy='Hydraciel:BAAANQAECgYIDgAAAA==.',
['Hì']='Hìroko:BAAANQADCgcIFAAAAA==.',
Ic='Icedemon:BAAANQABCgQIBAAAAA==.Icupapi:BAAANQADCgUIBQAAAA==.Icynips:BAAANQABCgEIAQAAAA==.',
Im='Im:BAAANQADCgEIAQABNQAECgkJIQACANciAA==.Imabigman:BAAANQADCgcICAAAAA==.Imaleaf:BAAANQAECgUICQAAAA==.Imperius:BAAANQAECgEIAQAAAA==.',
Ip='Iplaydead:BAAANQAECgYIDgAAAA==.',
Ir='Iroh:BAAANQAECgMIAwAAAA==.',
Is='Ismokeprot:BAAANQADCgMIAwAAAA==.',
Ja='Jawnson:BAAANQAECgUIBwAAAA==.',
Je='Jenefer:BAABNQAECoEbAAIKAAgJTBvRGQBWAgAKAAgJTBvRGQBWAgAAAA==.',
Jo='Jondooz:BAAANQAECgcIBwAAAA==.',
Ka='Kailback:BAAANQAECgEIAQABNQAECgIIBAABAAAAAA==.Kait:BAAANQAECgUIBQAAAA==.Kalcifur:BAABNQAECoEYAAILAAgJ3xVaKgAmAgALAAgJ3xVaKgAmAgAAAA==.Karnelian:BAAANQADCgEIAQABNQAECgIIAwABAAAAAA==.Karras:BAAANQADCgUIBQAAAA==.Kashisht:BAAANQADCgYICwAAAA==.Kasstigate:BAAANQAECgUICgABNQAECggIGwAKAEwbAA==.Kastiel:BAAANQAECgQIBwAAAA==.Katstrider:BAAANQAECgUICQAAAA==.Kattarea:BAAANQADCgUICAABNQAECgUICQABAAAAAA==.Kavica:BAAANQADCgYICwABNQAECgQIBQABAAAAAA==.',
Ke='Keldean:BAAANQAECgMIBAAAAA==.Keryka:BAAANQAECggIEwAAAA==.',
Kh='Khere:BAAANQADCgUIBgAAAA==.',
Ki='Kiterisa:BAAANQAECgUIBwAAAA==.',
Ko='Kohn:BAAANQAECgUIBwAAAA==.Kona:BAEANQADCgYIBgAAAA==.',
Ku='Kuattieb:BAAANQABCgIIAgAAAA==.',
La='Ladýfinger:BAAANQAECgQIBQABNQAECggIGwAMADoaAA==.Laisidhiel:BAAANQADCgcIHAAAAA==.Lateo:BAAANQAECgYIDQAAAA==.Lawz:BAAANQAECgIIAgAAAA==.',
Le='Lelianna:BAAANQADCgQICAAAAA==.Lexia:BAAANQAECgEIAQAAAA==.',
Li='Lilturtz:BAAANQADCgUIBQABNQAECgMIBAABAAAAAA==.Linnea:BAAANQADCgcIDQAAAA==.',
Lo='Locksative:BAAANQADCggIEQAAAA==.Longhorn:BAAANQAECgMIAwAAAA==.Lorriena:BAAANQADCgUIBQABNQADCgYICAABAAAAAA==.Lortpegsalot:BAAANQAECgcIEAAAAA==.Lowy:BAAANQAECgIIAgAAAA==.',
Lu='Lucena:BAAANQADCggIGQAAAA==.',
Ly='Lyralana:BAAANQADCgQIBwABNQADCgUIDgABAAAAAA==.',
Ma='Maberu:BAAANQAECgUIBwABNQAECggIGAALAN8VAA==.Madamholy:BAAANQAECgEIAQAAAA==.Madamkluck:BAAANQADCgUIBQAAAA==.Maglubiyet:BAAANQADCgYIFwAAAA==.Magnitood:BAAANQADCggICgAAAA==.Malphox:BAAANQADCgQICAAAAA==.Manbearcat:BAAANQAECgEIAQAAAA==.Manhole:BAAANQAECgQIDAAAAA==.Markyb:BAAANQADCgYIBgAAAA==.Masamura:BAABNQAECoEYAAINAAkJ8xN4SAB1AgANAAkJ8xN4SAB1AgAAAA==.Maureanna:BAAANQADCgUIDgAAAA==.',
Me='Mechahuntard:BAAANQADCgEIAQAAAA==.Medanii:BAEANQAECgUICQAAAA==.Melorm:BAAANQADCgYIDQAAAA==.',
Mi='Millizh:BAACNQAFFIEMAAMEAAYJihu+AQCDAQAEAAQJpR2+AQCDAQAOAAMJqxhtBwD5AAA1AAQKgR0AAw4ACQn+JQoCAKQDAA4ACQm3JQoCAKQDAAQABgnOIpI0ACcCAAAA.Mirasharu:BAAANQADCgQICAAAAA==.Mireille:BAAANQADCgQICAAAAA==.Mitsuri:BAAANQAECgQIBQAAAA==.Mitzuky:BAAANQADCgMIAwAAAA==.',
Mo='Moonlïght:BAAANQAECgUIBQAAAA==.Morganlefay:BAAANQADCggIHQAAAA==.Morlyn:BAAANQADCggIFQAAAA==.Morregan:BAAANQAECgEIAQAAAA==.Mousereaper:BAAANQAECgUICQAAAA==.',
My='Mydnight:BAAANQABCgIIAgAAAA==.Mystìc:BAAANQAECgIIBAAAAA==.Mystíc:BAAANQADCggIGwABNQAECgIIBAABAAAAAA==.',
['Má']='Májorrobot:BAAANQAECgcICQAAAA==.',
['Mé']='Ménopáwz:BAAANQAECgEIAQABNQAECgkJHQAPAAMkAA==.',
Na='Namor:BAAANQADCgcIBwAAAA==.Nattisca:BAAANQADCgYIBwAAAA==.',
Ne='Nessà:BAAANQAECgEIAQAAAA==.Neveenn:BAAANQAECgYIEgAAAA==.',
Ni='Nirith:BAAANQADCgYICAAAAA==.',
No='Nohatcat:BAAANQADCggIEgABNQAECgMIBAABAAAAAA==.',
['Nâ']='Nâmii:BAAANQADCgMIAwAAAA==.',
['Nè']='Nèzukõ:BAAANQAECgQIBAAAAA==.',
Oc='Octavius:BAAANQADCgUICgABNQADCggIFQABAAAAAA==.',
Oj='Ojore:BAEANQAECgIIAgAAAA==.Ojoverde:BAABNQAECoEZAAIQAAgJHxG5OADuAQAQAAgJHxG5OADuAQAAAA==.',
On='Onizuka:BAAANQADCgEIAQABNQADCgcICQABAAAAAA==.Onside:BAAANQAECgQIBQABNQAECgcIEAABAAAAAA==.',
Op='Ophillã:BAAANQADCgYIFAABNQAECgEIAQABAAAAAA==.',
Or='Ordenn:BAAANQADCgQIBAABNQAECgkJGAACALccAA==.Orian:BAAANQADCgQIBwAAAA==.',
Oz='Ozz:BAAANQAECgYIDgAAAA==.Ozzerker:BAAANQADCgEIAQAAAA==.Ozzullr:BAAANQAECgMIAwAAAA==.',
Pa='Painbreak:BAAANQADCgEIAQABNQAECgMIBAABAAAAAA==.Pallanquin:BAAANQADCgQIBgAAAA==.Papichili:BAAANQADCgcIGAAAAA==.Pashnir:BAAANQADCgQIBQAAAA==.',
Pe='Peachey:BAAANQAECgIIAgAAAA==.Peaker:BAAANQAECgMIAwAAAA==.',
Pi='Pigas:BAAANQAECgQICgAAAA==.',
Pr='Prestoresto:BAAANQADCgYIDwAAAA==.',
Ps='Psychosix:BAAANQAECgUIBQAAAA==.',
Qu='Quinberos:BAAANQAECgIIAgABNQAECgMIAwABAAAAAA==.',
Ra='Racey:BAAANQADCggICAAAAA==.Ramdel:BAAANQADCgcIDwABNQAECgUICQABAAAAAA==.Ramstrider:BAAANQAECgUICQAAAA==.Ranch:BAAANQADCgcICQAAAA==.Rapture:BAAANQAECgQIBQAAAA==.',
Re='Rengell:BAAANQAECgMIAwABNQAECgUICgABAAAAAA==.',
Rh='Rheagall:BAAANQAECgcIBgAAAA==.Rhodetta:BAAANQAECgUIBwAAAA==.',
Ri='Rizepriest:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Rizerage:BAAANQAECgEIAQAAAA==.',
Ro='Rowena:BAAANQAECgQIDwAAAA==.Rowynna:BAAANQAECgMIAwAAAA==.Roxy:BAAANQADCgYIBgAAAA==.Roxymonk:BAAANQADCgYIBgAAAA==.Royalviaman:BAAANQADCgQIBwAAAA==.',
Ry='Ryz:BAAANQADCggICAAAAA==.Ryztkmtchrch:BAAANQAECgcIEQAAAA==.',
['Rå']='Råti:BAAANQADCgUIBQAAAA==.',
Sa='Sacdk:BAAANQAECgQIBwAAAA==.Safaria:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Saloenus:BAAANQAECgYICgAAAA==.Sarlyssa:BAAANQABCgYICgAAAA==.Saucehoss:BAABNQAECoEbAAQRAAgJFh50AQC+AgARAAgJFh50AQC+AgASAAMJ5Q3mNwCpAAAQAAIJlgzZogCDAAAAAA==.Saucymac:BAAANQAECgYIBQAAAA==.',
Sc='Scofflaw:BAAANQADCgEIAQABNQADCggICgABAAAAAA==.',
Se='Sefi:BAAANQAECgMIBAAAAA==.Semirrhage:BAAANQADCgMIAwAAAA==.',
Sh='Shadowflame:BAAANQAECgIIAgAAAA==.Shammygoat:BAAANQAECgQIBAAAAA==.Shaqattack:BAAANQAECgcIEAAAAA==.Sharktide:BAAANQAECgUICQAAAA==.Shawnella:BAAANQAECgUIBwAAAA==.Shenlune:BAAANQADCgcIFAAAAA==.Sheutka:BAAANQADCgcIEAAAAA==.Shiggles:BAAANQADCgYIFAAAAA==.Shinaie:BAAANQAECgEIAQAAAA==.Shocknrollz:BAAANQAECgQIBgAAAA==.Shogún:BAAANQAECgUIBQABNQAECgYIBgABAAAAAA==.Shtylez:BAAANQADCggIFgABNQAECgYIDgABAAAAAA==.',
Si='Silntwolf:BAAANQABCgQIBAAAAA==.Silpion:BAAANQAECgEIAQAAAA==.Silth:BAAANQADCgYICAAAAA==.Sinariel:BAAANQAECgQICAAAAA==.Sirdank:BAAANQADCgUIBQAAAA==.',
Sk='Skarlate:BAAANQADCgYIBgAAAA==.Skâld:BAEANQADCgYICwAAAA==.',
Sl='Sliko:BAAANQAECgYIDQAAAA==.',
Sm='Smmoke:BAAANQAECgUIBwAAAA==.',
Sn='Sneekypally:BAAANQAECgMIBQAAAA==.Snowballs:BAAANQAECgIIAgAAAA==.',
So='Soull:BAAANQAECgYIDQAAAA==.Soulsmash:BAAANQADCgYIBgAAAA==.',
Sp='Spacestepdad:BAAANQAECgEIAQAAAA==.Sparkie:BAAANQADCggIEgAAAA==.Spriggan:BAAANQADCgcIDwAAAA==.',
Sq='Squashfoot:BAAANQADCggIEQABNQADCggIFQABAAAAAA==.',
St='Starface:BAABNQAECoEbAAIMAAgJOhoABQBzAgAMAAgJOhoABQBzAgAAAA==.Steelytree:BAAANQADCgQIBwAAAA==.Stellaria:BAAANQAECgQIBAAAAA==.Steverogers:BAAANQAECgMIAwABNQAECgkJHQAPAAMkAA==.Stocktonrush:BAABNQAECoEdAAIPAAkJAySaAgC2AwAPAAkJAySaAgC2AwAAAA==.Sturmx:BAAANQAECgUIBwAAAA==.',
Su='Subedei:BAAANQAECgcICAAAAA==.Summerseve:BAAANQAECgMIAwAAAA==.Sunderhorn:BAAANQADCgcIEAAAAA==.Suriaa:BAAANQAECgYIDQAAAA==.',
Sv='Svictis:BAAANQADCgcIGQAAAA==.',
Sw='Swami:BAAANQADCggICgAAAA==.',
Ta='Talila:BAAANQAECgIIAwAAAA==.Taniss:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Taurdeth:BAAANQADCgYIBgABNQAECgUIBwABAAAAAA==.',
Th='Thaqdaddy:BAAANQADCgYIBgABNQAECgYIDAABAAAAAA==.Thaqknight:BAAANQAECgYIDAAAAA==.Therylnn:BAAANQABCgUIBQAAAA==.Thesthamenth:BAAANQADCgYIBgAAAA==.Thily:BAAANQADCgIIAgAAAA==.Thorwallen:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Thror:BAAANQAECgEIAQAAAA==.',
Ti='Tiac:BAAANQAECgEIAQAAAA==.Tiergyll:BAAANQABCgIIBAAAAA==.Tirithor:BAAANQAECgYIDQAAAA==.',
To='Tockell:BAAANQADCgQIBwAAAA==.Togala:BAAANQADCgUIBwABNQAECgIIAgABAAAAAA==.Toothless:BAAANQAECgEIAQAAAA==.Torbin:BAAANQAECgEIAQAAAA==.Touchmywave:BAAANQADCgUICAABNQAECggIGAAEAMIRAA==.',
Tr='Tryjinks:BAAANQAECgEIAgAAAA==.',
Ts='Tsunameh:BAAANQADCgQICQABNQAECgYIDgABAAAAAA==.',
Tu='Tusky:BAAANQADCgYIBgAAAA==.',
Ty='Tykahndrius:BAAANQAECgQIBAABNQAECgYIDgABAAAAAA==.Tyredelsia:BAAANQABCgcIEAAAAA==.',
['Tú']='Túsk:BAAANQADCgYIBwAAAA==.',
['Tý']='Týlius:BAAANQAECgMIBAAAAA==.',
Uk='Ukika:BAAANQADCgUICgABNQAECgIIAgABAAAAAA==.',
Us='Useriòs:BAAANQADCgIIAgAAAA==.',
Ut='Uthilon:BAAANQAECgUIBwAAAA==.',
Va='Valdare:BAAANQAECgEIAQAAAA==.Validorn:BAAANQADCgcIDgAAAA==.',
Ve='Vedillian:BAAANQAECgEIAQAAAA==.Velduar:BAAANQADCgQIBAAAAA==.',
Vi='Victorr:BAAANQADCgMIBAAAAA==.Viktorius:BAAANQADCgQIBAAAAA==.Vizigoth:BAAANQAECgQIBQAAAA==.',
Vo='Vordell:BAAANQAECgIIAgABNQAECgUIBwABAAAAAA==.Voyana:BAAANQAECgMIAwAAAA==.Voz:BAAANQADCgUIBQAAAA==.',
Vy='Vydragon:BAAANQAECgMIBAABNQAECgkJGwANAB4bAA==.Vymage:BAABNQAECoEbAAINAAkJHhuXLQDaAgANAAkJHhuXLQDaAgAAAA==.Vyrubur:BAAANQADCgQIBAABNQAECgkJGwANAB4bAA==.',
['Vá']='Válidüs:BAABNQAECoEgAAIGAAkJ5h/8BwAoAwAGAAkJ5h/8BwAoAwAAAA==.',
['Vã']='Vãsh:BAAANQADCgcIDQAAAA==.',
Wa='Wabìsuke:BAAANQADCggIFQAAAA==.Waterlogged:BAAANQADCgQIBgAAAA==.Waterloo:BAAANQADCgIIAgAAAA==.',
['Wì']='Wìccka:BAAANQADCgUIBQAAAA==.',
Xi='Xi:BAAANQAECgMIAwAAAA==.Xifan:BAAANQAECgIIAwAAAA==.',
Yd='Yd:BAAANQAECgEIAQABNQAECgkJIQACANciAA==.',
Yg='Yggdrasill:BAAANQABCgMIBQAAAA==.',
Yi='Yingpi:BAAANQABCgIIAgAAAA==.',
Ys='Ys:BAAANQADCgcICwABNQAECgkJIQACANciAA==.',
Yt='Yt:BAAANQAECgQICgABNQAECgkJIQACANciAA==.',
Yw='Ywontudie:BAAANQADCgIIAgAAAA==.',
Yz='Yz:BAABNQAECoEhAAMCAAkJ1yKXAQCWAwACAAkJ1yKXAQCWAwAIAAIJUxtbOQCYAAAAAA==.',
Za='Zashawa:BAAANQADCgYIBgAAAA==.',
Ze='Zenithgrey:BAAANQAECgYIBgAAAA==.',
Zl='Zluco:BAABNQAECoEdAAMTAAkJYhzIAwALAwATAAkJYhzIAwALAwADAAYJvRmqSQCCAQAAAA==.',
Zo='Zoomy:BAAANQADCgIIAgAAAA==.',
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
