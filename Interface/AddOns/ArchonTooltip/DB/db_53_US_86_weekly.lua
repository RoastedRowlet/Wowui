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

local lookup = {'Unknown-Unknown','Rogue-Subtlety','Shaman-Restoration','Hunter-BeastMastery','Druid-Feral','Priest-Holy','Monk-Mistweaver','Paladin-Retribution','Warlock-Destruction','Rogue-Assassination','DemonHunter-Havoc','DeathKnight-Blood','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Druid-Guardian','Mage-Arcane','Hunter-Marksmanship','Druid-Restoration','Warlock-Demonology','Monk-Windwalker','Druid-Balance','Priest-Shadow','Warlock-Affliction','Mage-Fire','Shaman-Enhancement',}
local provider = {region='US',realm="Eldre'Thalas",name='US',type='weekly',zone=53,date='2026-09-22',data={Ad='Adesira:BAAANQADCggJCwAAAA==.Adrastus:BAAANQADCggJDAABNQAECgcICwABAAAAAA==.',
Ae='Aeslin:BAAANQADCgYJBgABNQAECgEIAQABAAAAAA==.',
Ah='Ahn:BAAANQADCgUJBQAAAA==.Ahylin:BAAANQADCgcIDAAAAA==.',
Ai='Ainslie:BAAANQAECgEJAQAAAA==.',
Al='Alerana:BAAANQADCggJEAAAAA==.Altria:BAAANQADCgQIBAAAAA==.',
An='An:BAAANQAECgQICwABNQAECgkJJAACANciAA==.Anarose:BAAANQAECgIIAgAAAA==.Antityk:BAAANQAECgIIAgABNQAECgcICwABAAAAAA==.',
Ar='Aragorn:BAAANQADCgQIBQAAAA==.Aretas:BAAANQAECgYJEAAAAA==.Armadian:BAAANQAECgMIAwAAAA==.Arrianne:BAAANQADCgYIBgAAAA==.Arriånna:BAAANQADCgYIBgAAAA==.Artemist:BAAANQAECggICAAAAA==.',
As='Asifa:BAAANQADCgcJEQAAAA==.',
At='Atherion:BAAANQAECgQJCwAAAA==.',
Av='Avranarada:BAAANQAECgYIDQAAAA==.Avril:BAAANQAECgEIAQAAAA==.',
Az='Azkara:BAABNQAECoEgAAIDAAkK6RlDGADHAgADAAkK6RlDGADHAgAAAA==.Azung:BAAANQAECgcIDQAAAA==.',
Ba='Babaisyaga:BAACNQAFFIEGAAIEAAMK0hofCAANAQAEAAMK0hofCAANAQA1AAQKgSkAAgQACQqYIoMKAFYDAAQACQqYIoMKAFYDAAAA.Baka:BAAANQAECgUJCAAAAA==.Balinse:BAAANQAECgQJBwABNQAECgYJDAABAAAAAA==.Barb:BAAANQAECgEIAQAAAA==.Barrelrollin:BAAANQADCgYIDwAAAA==.',
Be='Beastfodays:BAABNQAECoEhAAIEAAgKnxnBKQCNAgAEAAgKnxnBKQCNAgAAAA==.Bethlahammer:BAAANQADCgYIDQABNQAECgEIAQABAAAAAA==.',
Bi='Billcritin:BAAANQAECgYICwAAAA==.',
Bl='Blackleaf:BAAANQADCgQIBwAAAA==.Blawyke:BAAANQADCgYIBgABNQAECgkJHQAFAE0cAA==.Bless:BAAANQADCgYJBgAAAA==.Blizzcon:BAABNQAECoEmAAIGAAkK6yHNBQBrAwAGAAkK6yHNBQBrAwAAAA==.Bloodsurge:BAAANQADCgQJAwAAAA==.Blushies:BAAANQAECgMIBwAAAA==.',
Bo='Boltzfodayz:BAAANQAECgEIAQAAAA==.Bonerslap:BAAANQADCgEJAQAAAA==.Boone:BAAANQADCgMIAwAAAA==.Borrgar:BAAANQAECgQIBQAAAA==.',
Br='Brackle:BAAANQAECgQIBgAAAA==.Bracori:BAABNQAECoEiAAIHAAkK8g1aDwAMAgAHAAkK8g1aDwAMAgAAAA==.Brandywynne:BAAANQAECgYIDwAAAA==.Bretcha:BAAANQADCgQIBAABNQAECgMIBAABAAAAAA==.Brick:BAAANQAECgcJEAAAAA==.Brightfame:BAAANQAECgYIEAAAAA==.Bronny:BAAANQAECgMJBAAAAA==.',
Bu='Buffshagwell:BAAANQAECgUIEQAAAA==.Butterbllz:BAABNQAECoEcAAIIAAgKPB33MACTAgAIAAgKPB33MACTAgAAAA==.',
Ca='Calypsio:BAAANQADCgQIBAABNQADCggJGQABAAAAAA==.Camany:BAAANQAECgYICQAAAA==.Captinkrunch:BAAANQADCgEJAQAAAA==.Caretakerz:BAAANQAECgUICQAAAA==.Cartus:BAAANQADCgUICAABNQAECgMJBAABAAAAAA==.Cayin:BAAANQAECgYJDwABNQABCgYICwABAAAAAA==.',
Cl='Clamshell:BAAANQAECgYIDQAAAA==.Claudette:BAAANQAECgUJCAAAAA==.Clayier:BAAANQADCgYIDAAAAA==.',
Cn='Cntendr:BAAANQADCgUJBQAAAA==.',
Co='Codenike:BAAANQAECgQJBwAAAA==.Corelheals:BAAANQADCgMIBQAAAA==.Covertyqt:BAAANQAECgYIDQAAAA==.',
Cp='Cptnhuman:BAAANQAECgYIDQAAAA==.',
Cr='Cromie:BAAANQADCggIFQAAAA==.Crosed:BAAANQADCgQIBAAAAA==.',
Cs='Cshunter:BAAANQADCgYIBwAAAA==.',
Cu='Cubcakes:BAAANQADCggIBQAAAA==.',
['Cõ']='Cõrpses:BAEANQAECgYIDQABNQAECgEJAQABAAAAAA==.',
Da='Daboof:BAAANQADCgUIDQAAAA==.Daemandred:BAAANQADCgEJAQAAAA==.Daggere:BAAANQADCgYJGQAAAA==.Danke:BAAANQADCgYJDgAAAA==.Dankz:BAAANQADCgYJFgAAAA==.Darkenmicky:BAAANQADCgcIEwAAAA==.Darkmickyz:BAAANQAECgMJBAAAAA==.Darthbobula:BAAANQAECgUJCAAAAA==.Dayloc:BAAANQADCgcIDQAAAA==.',
De='Deataria:BAAANQAECgQJCwAAAA==.Deawin:BAAANQADCgQIBAABNQADCgYIDwABAAAAAA==.Delilia:BAEANQAECggIBQABNQAECggIEAABAAAAAA==.Delryth:BAAANQADCgYIBQAAAA==.Demonikk:BAAANQAECgQIBgABNQAECgcICwABAAAAAA==.Demontyk:BAAANQAECgIIAgABNQAECgcICwABAAAAAA==.Desception:BAAANQADCgQIBwAAAA==.',
Di='Diadochi:BAAANQAECgQJBQAAAA==.Dieguerta:BAAANQADCgEJAQAAAA==.',
Dl='Dl:BAAANQAECgcJEQAAAA==.',
Dr='Drakkarr:BAAANQADCgIJAgAAAA==.Drazhoath:BAAANQAECgQICAAAAA==.Drdrill:BAAANQADCgYIBgAAAA==.Drimbirt:BAAANQADCgQIBwAAAA==.Drinkmormilk:BAAANQADCgMJBAAAAA==.Drogelf:BAAANQADCgYIDQAAAA==.Drogman:BAAANQADCgIIAgAAAA==.',
Du='Dumbledore:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.',
['Dá']='Dáwnbringer:BAAANQADCgIIBAAAAA==.',
Eb='Ebullition:BAAANQAECgEIAQAAAA==.',
Ed='Edensfury:BAAANQAECgEIAQAAAA==.',
Ee='Eedani:BAAANQADCgUJCQAAAA==.',
Ei='Eigi:BAAANQAECgYICwAAAA==.',
El='Eldanon:BAABNQAECoEXAAIJAAgKrR1wAwDnAgAJAAgKrR1wAwDnAgAAAA==.Elementality:BAAANQADCgIIAgAAAA==.Eleyert:BAAANQAECgYIDgAAAA==.Elistann:BAAANQADCggICQABNQAECgQIBQABAAAAAA==.Elwe:BAAANQAECgQJBwAAAA==.',
Em='Embaku:BAAANQADCggICAABNQAECggIFwAIAAoSAA==.Emrhakul:BAAANQABCgcJCgAAAA==.',
En='Enkidu:BAAANQAECgQJBQAAAA==.Enseth:BAAANQAECgQJBwAAAA==.',
Er='Erakha:BAAANQAECgMIBAAAAA==.Erandria:BAAANQADCgUJBQABNQADCgUIDgABAAAAAA==.',
Eu='Eulogy:BAAANQADCgYICAABNQAECgkJJgAGAOshAA==.',
Ez='Ezerharden:BAAANQABCgEJAQAAAA==.Ezki:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.',
Fa='Fairious:BAAANQAECgQJDQAAAA==.',
Fe='Felcon:BAAANQADCgYJCAAAAA==.Fet:BAABNQAECoEZAAMCAAkKXx3OCgCeAgACAAgKXB/OCgCeAgAKAAEKcQ2ZXABAAAAAAA==.',
Fh='Fhatbashtud:BAAANQADCgcJEQAAAA==.',
Fl='Flatline:BAAANQAECgQICAAAAA==.Flinnt:BAAANQABCggIEwABNQAECgQIBQABAAAAAA==.',
Fn='Fngusamungus:BAAANQAECgEIAQAAAA==.',
Fo='Four:BAAANQAECgMJBQAAAA==.',
Fr='Fredwarlock:BAAANQADCgcIDAAAAA==.Frysky:BAAANQAECgIIAgAAAA==.',
Fu='Furiousv:BAAANQADCgUIBQAAAA==.Futz:BAAANQAECgQJEwAAAA==.',
Ga='Gahnzul:BAAANQADCgUIBQAAAA==.Gajitbek:BAAANQADCgMIAwAAAA==.Galah:BAAANQAECgQJBgAAAA==.',
Gn='Gnomicide:BAAANQADCgcJFwAAAA==.',
Go='Gooberpea:BAAANQABCgYICgAAAA==.',
Gr='Graveborne:BAAANQADCgYIBwAAAA==.Gravess:BAAANQADCgUIBQAAAA==.Gravewin:BAAANQADCgQICgABNQADCgYIDwABAAAAAA==.Gravyexpress:BAABNQAECoEmAAILAAgK3xtpFACWAgALAAgK3xtpFACWAgAAAA==.Grendelheim:BAAANQADCgUICwAAAA==.Grogar:BAAANQADCgYIDQAAAA==.',
Gu='Gula:BAAANQADCgcJEQABNQAECgEJAgABAAAAAA==.',
Ha='Hadez:BAAANQADCgUIBQAAAA==.Hagrok:BAAANQABCgQJBgAAAA==.Hantak:BAAANQADCgMIBgAAAA==.Harmsway:BAAANQADCgcJEQAAAA==.Hathaendron:BAAANQABCgMJAwAAAA==.',
He='Hephaestus:BAAANQADCgYJCAAAAA==.',
Ho='Hocka:BAAANQADCgUIBgAAAA==.Holysmight:BAAANQAECgEIAQAAAA==.Holyumo:BAAANQADCgYIBgAAAA==.Holyyballs:BAAANQAECgIIAgAAAA==.Howlymandel:BAAANQADCgQIBAABNQAECgYJEAABAAAAAA==.',
Hy='Hydraciel:BAAANQAECgYIDgAAAA==.',
['Hì']='Hìroko:BAAANQADCggJHAAAAA==.',
Ic='Icedemon:BAAANQABCgQIBAAAAA==.Icupapi:BAAANQADCggIFQAAAA==.Icynips:BAAANQABCgEIAQAAAA==.',
Im='Im:BAAANQADCgEJAQABNQAECgkJJAACANciAA==.Imabigman:BAAANQADCgcICAAAAA==.Imaleaf:BAAANQAECgYIDwAAAA==.Imperius:BAAANQAECgEIAQAAAA==.',
Ip='Iplaydead:BAAANQAECgYIEQABNQAECgcICwABAAAAAA==.',
Ir='Iroh:BAAANQAECgQIBQAAAA==.',
Is='Ismokeprot:BAAANQADCgMIAwAAAA==.',
Ja='Jawnson:BAAANQAECgYIDQAAAA==.',
Je='Jenefer:BAABNQAECoEhAAIMAAgKQR2zHQBoAgAMAAgKQR2zHQBoAgAAAA==.',
Ji='Jimjimmy:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.',
Jo='Jondooz:BAAANQAECgcIBwAAAA==.',
Ka='Kailback:BAAANQAECgEIAQABNQAECgUICQABAAAAAA==.Kait:BAAANQAECgYICwAAAA==.Kalcifur:BAABNQAECoEcAAINAAkKMhg4HwCeAgANAAkKMhg4HwCeAgAAAA==.Karnelian:BAAANQADCgUJBgABNQAECgcJCgABAAAAAA==.Karras:BAAANQADCgUIBQAAAA==.Kashisht:BAAANQADCgYJEQAAAA==.Kasstigate:BAAANQAECgUICgABNQAECggJIQAMAEEdAA==.Kastiel:BAAANQAECgYJDAAAAA==.Katstrider:BAAANQAECgYIDwAAAA==.Kattarea:BAAANQADCgUJCAABNQAECgYIDwABAAAAAA==.Kavica:BAAANQADCggIFAABNQAECgQICAABAAAAAA==.',
Ke='Keldean:BAAANQAECgQJBwAAAA==.Keryka:BAABNQAECoEbAAMOAAgKoh0VHACGAgAOAAgKoh0VHACGAgAPAAUKoR/rJQDFAQAAAA==.',
Kh='Khere:BAAANQADCgUIBgAAAA==.',
Ki='Kiterisa:BAAANQAECgYIDQAAAA==.',
Ko='Kohn:BAAANQAECgUIBwAAAA==.Kona:BAEANQAECgEJAQAAAA==.Korbusty:BAAANQADCggJCAAAAA==.',
Ku='Kuattieb:BAAANQABCgIIAgAAAA==.',
La='Ladýfinger:BAAANQAECgYICwABNQAECgkJIgAQAMsaAA==.Laisidhiel:BAAANQADCggJJAAAAA==.Lateo:BAAANQAECgYJEQAAAA==.Lawz:BAAANQAECgIIAgAAAA==.',
Le='Lelianna:BAAANQADCgUIDQAAAA==.Lemonruss:BAAANQADCggICAAAAA==.Lexia:BAAANQAECgIIAwAAAA==.',
Li='Liemannin:BAAANQAECgEIAQAAAA==.Lightninghah:BAAANQABCgIIAgAAAA==.Lilturtz:BAAANQADCgUIBQABNQAECgMIBwABAAAAAA==.Linnea:BAAANQADCgcIDQAAAA==.',
Lo='Locksative:BAAANQADCggJGQAAAA==.Longhorn:BAAANQAECgUICAAAAA==.Lorekesh:BAAANQADCgEJAQABNQAECgUJCAABAAAAAA==.Lorriena:BAAANQADCgUIBQABNQADCgYICAABAAAAAA==.Lortpegsalot:BAABNQAECoEbAAIIAAgK9CC7JADSAgAIAAgK9CC7JADSAgAAAA==.Lowy:BAAANQAECgIIAgAAAA==.',
Lu='Lucena:BAAANQAECgQJBAAAAA==.Lurg:BAAANQADCgQJBAABNQADCggJGQABAAAAAA==.',
Ly='Lyralana:BAAANQADCgQIBwABNQADCgUIDgABAAAAAA==.',
Ma='Maberu:BAAANQAECgYIDQABNQAECgkJHAANADIYAA==.Madamholy:BAAANQAECgMJBAAAAA==.Madamkluck:BAAANQADCgUIBQAAAA==.Maglubiyet:BAAANQADCggJHwAAAA==.Magnitood:BAAANQAECgEIAQAAAA==.Malbjornion:BAAANQAECgEJAQAAAA==.Malphox:BAAANQADCgQICAAAAA==.Manbearcat:BAAANQAECgMJBAAAAA==.Manhole:BAAANQAECgQIDAAAAA==.Markyb:BAAANQADCgYIBgAAAA==.Masamura:BAABNQAECoEiAAIRAAkKihaSTQCiAgARAAkKihaSTQCiAgAAAA==.Maureanna:BAAANQADCgUIDgAAAA==.',
Me='Mechahuntard:BAAANQADCgEIAQAAAA==.Medanii:BAEANQAECgYJDwAAAA==.Melorm:BAAANQADCgcIEQAAAA==.',
Mi='Millizh:BAACNQAFFIETAAMEAAcKeR4FAQATAgAEAAUK4iAFAQATAgASAAQKHRo6BwBcAQA1AAQKgSAAAxIACQpRJvYBALEDABIACQofJvYBALEDAAQABgrOIs9LAA8CAAAA.Mirasharu:BAAANQADCgUICQAAAA==.Mireille:BAAANQADCgUIDAAAAA==.Mitsuri:BAAANQAECgUJCgAAAA==.Mitzuky:BAAANQADCgMIAwAAAA==.',
Mo='Moonlïght:BAAANQAECgYICQAAAA==.Morganlefay:BAAANQAECgEJAQAAAA==.Morlyn:BAAANQAECgMJAwAAAA==.Morregan:BAAANQAECgEIAQAAAA==.Mousereaper:BAAANQAECgYJDwAAAA==.',
My='Mydnight:BAAANQABCgIIAgAAAA==.Mystìc:BAAANQAECgUICQAAAA==.Mystíc:BAAANQADCggIIgABNQAECgUICQABAAAAAA==.',
['Má']='Májorrobot:BAAANQAECgcICwAAAA==.',
['Mé']='Ménopáwz:BAAANQAECgIJAgABNQAECgkJIAAOAD0lAA==.',
Na='Namor:BAAANQADCgcIBwAAAA==.Nattisca:BAAANQADCgYIBwAAAA==.',
Ne='Nessà:BAAANQAECgEJAgAAAA==.Neveenn:BAABNQAECoEdAAITAAcKxBYNGQDkAQATAAcKxBYNGQDkAQAAAA==.',
Ni='Nirith:BAAANQADCgYJCAAAAA==.',
No='Nohatcat:BAAANQADCggIEgABNQAECgMIBwABAAAAAA==.',
['Nâ']='Nâmii:BAAANQADCgMIAwAAAA==.',
['Nè']='Nèzukõ:BAAANQAECgQJBwAAAA==.',
Oc='Octavius:BAAANQADCggJDQABNQAECgEIAQABAAAAAA==.',
Oj='Ojore:BAEANQAECgQJBgAAAA==.Ojoverde:BAABNQAECoEfAAIUAAgKSRJ2SAD8AQAUAAgKSRJ2SAD8AQAAAA==.',
On='Onizuka:BAAANQADCgEIAQABNQADCgcICQABAAAAAA==.Onside:BAAANQAECgYICgABNQAECgkJFwAVALQbAA==.',
Op='Ophillã:BAAANQAECgEJAQABNQAECgEJAgABAAAAAA==.',
Or='Ordenn:BAAANQADCgQIBAABNQAECgkJGQACAF8dAA==.Orian:BAAANQADCgQIBwAAAA==.',
Oz='Ozz:BAABNQAECoEZAAIVAAgK2w9wGgDcAQAVAAgK2w9wGgDcAQAAAA==.Ozzerker:BAAANQADCgEIAQAAAA==.Ozzullr:BAAANQAECgQJBwAAAA==.',
Pa='Painbreak:BAAANQADCgEIAQABNQAECgUICQABAAAAAA==.Pajamas:BAAANQAECgEJAQABNQAECgMIBQABAAAAAA==.Pallanquin:BAAANQADCgYJCQAAAA==.Papichili:BAAANQADCggJIAAAAA==.Pashnir:BAAANQADCgQIBQAAAA==.',
Pe='Peachey:BAAANQAECgIIAwAAAA==.Peaker:BAAANQAECgMIAwAAAA==.Peakra:BAAANQADCgEIAQAAAA==.',
Pi='Pigas:BAAANQAECgYIEAAAAA==.',
Pr='Prestoresto:BAAANQADCgYIDwAAAA==.',
Ps='Psychosix:BAAANQAECgcJCwAAAA==.',
Qu='Quinberos:BAAANQAECgIIAwABNQAECgMIAwABAAAAAA==.',
Ra='Racey:BAAANQADCggICAAAAA==.Ramdel:BAAANQADCggIFwABNQAECgYIDwABAAAAAA==.Ramstrider:BAAANQAECgYIDwAAAA==.Ranch:BAAANQADCgcICQAAAA==.Rapture:BAAANQAECgUJBgAAAA==.Ravec:BAAANQABCgQJBQAAAA==.',
Re='Rengell:BAAANQAECgQJBgABNQAECgYJEAABAAAAAA==.',
Rh='Rheagall:BAAANQAECgYJDgAAAA==.Rhodetta:BAAANQAECgcIDgAAAA==.',
Ri='Rizepriest:BAAANQADCgIIAgABNQAECgMJBAABAAAAAA==.Rizerage:BAAANQAECgMJBAAAAA==.',
Ro='Roaraxe:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Rowena:BAABNQAECoEaAAIWAAcKoQ/1OQCgAQAWAAcKoQ/1OQCgAQAAAA==.Rowynna:BAAANQAECgMIAwAAAA==.Roxy:BAAANQADCgYIBgAAAA==.Roxymonk:BAAANQADCgYIBgAAAA==.Royalviaman:BAAANQADCgQJBwAAAA==.',
Ry='Ryz:BAAANQADCggICAAAAA==.Ryztkmtchrch:BAABNQAECoEdAAMGAAgK5RvyKwBMAgAGAAgK5RvyKwBMAgAXAAUKJg8VLwAjAQAAAA==.',
['Rå']='Råti:BAAANQADCgUIBQAAAA==.',
Sa='Sacdk:BAAANQAECgQIBwAAAA==.Safaria:BAAANQAECgEIAQABNQAECgQJBwABAAAAAA==.Saloenus:BAAANQAECgYICgAAAA==.Sarlyssa:BAAANQABCgYJCgAAAA==.Saucehoss:BAABNQAECoEeAAQYAAgKkx4pAgCxAgAYAAgKkx4pAgCxAgAUAAMKag4wuQCwAAAJAAMK5Q1jPgCkAAAAAA==.Saucymac:BAAANQAECgYIBQAAAA==.',
Sc='Scofflaw:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.',
Se='Sefi:BAAANQAECgUJCQAAAA==.Semirrhage:BAAANQADCgMIAwAAAA==.',
Sh='Shadowflame:BAAANQAECgMIBQAAAA==.Shammygoat:BAAANQAECgQICAAAAA==.Shaqattack:BAABNQAECoEXAAIVAAkKtBueCgDcAgAVAAkKtBueCgDcAgAAAA==.Sharktide:BAAANQAECgYIDwAAAA==.Shawnella:BAAANQAECgYIDQAAAA==.Shenlune:BAAANQAECgQJBAAAAA==.Sheutka:BAAANQADCgcJFwAAAA==.Shiggles:BAAANQADCgYIGgAAAA==.Shinaie:BAAANQAECgMJBAAAAA==.Shocknrollz:BAAANQAECgQJCgAAAA==.Shogún:BAAANQAECgUICQABNQAECgcJDQABAAAAAA==.Shtylez:BAAANQADCggIGQABNQAECgcICwABAAAAAA==.',
Si='Silntwolf:BAAANQABCgQIBAAAAA==.Silpion:BAAANQAECgIJAgAAAA==.Silth:BAAANQADCggJCgAAAA==.Sinariel:BAAANQAECgUIDQAAAA==.Sirdank:BAAANQADCgUJCQAAAA==.',
Sk='Skarlate:BAAANQADCgYIBgAAAA==.Skâld:BAEANQADCgYICwAAAA==.',
Sl='Sliko:BAABNQAECoEXAAIIAAgK7hFLWQD1AQAIAAgK7hFLWQD1AQAAAA==.',
Sm='Smmoke:BAAANQAECgYIDQAAAA==.',
Sn='Sneekypally:BAAANQAECgMJBQAAAA==.Snowballs:BAAANQAECgMJBQAAAA==.',
So='Soull:BAABNQAECoEXAAITAAgKvx2NCQDWAgATAAgKvx2NCQDWAgAAAA==.Soulsmash:BAAANQADCgYIBgAAAA==.',
Sp='Spacestepdad:BAAANQAECgMJBAAAAA==.Sparkie:BAAANQADCggJGQAAAA==.Spriggan:BAAANQADCgcIDwAAAA==.',
Sq='Squashfoot:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.',
St='Starface:BAABNQAECoEiAAIQAAkKyxoNBQC9AgAQAAkKyxoNBQC9AgAAAA==.Stargoose:BAAANQAECgMIAwABNQAECgkJIgAQAMsaAA==.Steelytree:BAAANQADCgQIBwAAAA==.Stellaria:BAAANQAECgQIBAAAAA==.Steris:BAAANQADCggJCAABNQADCggJGQABAAAAAA==.Steverogers:BAAANQAECgMIBQABNQAECgkJIAAOAD0lAA==.Stocktonrush:BAABNQAECoEgAAMOAAkKPSUeBACkAwAOAAkKAyQeBACkAwAMAAEKnyPvhABlAAAAAA==.Sturmx:BAAANQAECgYIDQAAAA==.',
Su='Subedei:BAAANQAECgcIDgAAAA==.Summerseve:BAAANQAECgMIAwAAAA==.Sunderhorn:BAAANQADCgcJFwAAAA==.Suriaa:BAAANQAECgYJEwAAAA==.',
Sv='Svictis:BAAANQADCggJIQAAAA==.',
Sw='Swami:BAAANQAECgIIAgAAAA==.',
Ta='Talila:BAAANQAECgMJBgAAAA==.Taniss:BAAANQADCgYJBgABNQAECgQIBQABAAAAAA==.Taurdeth:BAAANQADCgYIBgABNQAECgcIDgABAAAAAA==.',
Th='Thaqdaddy:BAAANQADCgYIBgABNQAECgcJDwABAAAAAA==.Thaqknight:BAAANQAECgcJDwAAAA==.Therylnn:BAAANQABCgUJBQAAAA==.Thesthamenth:BAAANQADCgYIBgAAAA==.Thily:BAAANQADCgIIAgAAAA==.Thorwallen:BAAANQADCgQIBAABNQAECgQIBQABAAAAAA==.Thror:BAAANQAECgEIAQAAAA==.',
Ti='Tiac:BAAANQAECgEIAQAAAA==.Tiergyll:BAAANQABCgIIBAAAAA==.Tirithor:BAABNQAECoEXAAIIAAgKChJ3VwD7AQAIAAgKChJ3VwD7AQAAAA==.',
To='Tockell:BAAANQADCgQIBwAAAA==.Togala:BAAANQADCgUIBwABNQAECgMIBAABAAAAAA==.Toothless:BAAANQAECgEIAQAAAA==.Torbin:BAAANQAECgEIAgAAAA==.Touchmywave:BAAANQADCgcIDQABNQAECggIIQAEAJ8ZAA==.',
Tr='Tryjinks:BAAANQAECgEIAgAAAA==.',
Ts='Tsunameh:BAAANQADCgYIDwABNQAECgcICwABAAAAAA==.',
Tu='Tusky:BAAANQADCgYIBgAAAA==.',
Ty='Tykahndrius:BAAANQAECgcICwAAAA==.Tylîus:BAAANQAECgEJAQABNQAECgMIBAABAAAAAA==.Tyredelsia:BAAANQABCggIFAAAAA==.',
['Tú']='Túsk:BAAANQADCgYIBwAAAA==.',
['Tý']='Týlius:BAAANQAECgMIBAAAAA==.',
Uk='Ukika:BAAANQADCgUICgABNQAECgMIBAABAAAAAA==.',
Us='Useriòs:BAAANQADCgIJAwAAAA==.',
Ut='Uthilon:BAAANQAECgYIDQAAAA==.',
Va='Valdare:BAAANQAECgQJBQAAAA==.Validorn:BAAANQADCggJDwAAAA==.',
Ve='Vedillian:BAAANQAECgEJAQAAAA==.Velduar:BAAANQADCgQJBAAAAA==.',
Vi='Victorr:BAAANQADCgUJCAAAAA==.Viktorius:BAAANQADCgQIBAAAAA==.Vixious:BAAANQADCgUIAwAAAA==.Vizigoth:BAAANQAECgQJCQAAAA==.',
Vo='Vordell:BAAANQAECgIJAgABNQAECgcIDgABAAAAAA==.Voyana:BAAANQAECgQJBwAAAA==.Voz:BAAANQADCgUIBQAAAA==.',
Vy='Vydragon:BAAANQAFFAIIAgABNQAECgkJIQARAEgcAA==.Vymage:BAABNQAECoEhAAMRAAkKSBwOOwDbAgARAAkK8xsOOwDbAgAZAAMK8BScBADhAAAAAA==.',
['Vá']='Válidüs:BAACNQAFFIEGAAIGAAMK3wfZDgDqAAAGAAMK3wfZDgDqAAA1AAQKgSYAAgYACQoSIU4JAD8DAAYACQoSIU4JAD8DAAAA.',
['Vã']='Vãsh:BAAANQADCggJFQAAAA==.',
Wa='Wabìsuke:BAAANQADCggIFQAAAA==.Waterlogged:BAAANQADCgQJCgAAAA==.Waterloo:BAAANQADCgMIAwAAAA==.',
Wi='Wizpigas:BAAANQADCgYIBgABNQAECgYIEAABAAAAAA==.',
['Wì']='Wìccka:BAAANQADCgUIBQAAAA==.',
Xi='Xi:BAAANQAECgMIAwAAAA==.Xifan:BAAANQAECgcJCgAAAA==.',
Yd='Yd:BAAANQAECgQIBAABNQAECgkJJAACANciAA==.',
Yg='Yggdrasill:BAAANQABCgUICAAAAA==.',
Yi='Yingpi:BAAANQABCgIIAgAAAA==.',
Ys='Ys:BAAANQAECgQIBAABNQAECgkJJAACANciAA==.',
Yt='Yt:BAAANQAECgQICgABNQAECgkJJAACANciAA==.',
Yw='Ywontudie:BAAANQADCgIJAgAAAA==.',
Yz='Yz:BAABNQAECoEkAAMCAAkK1yIoAgCFAwACAAkK1yIoAgCFAwAKAAIKUxvxTQCPAAAAAA==.',
Za='Zashawa:BAAANQADCgYJBgAAAA==.',
Ze='Zenithgrey:BAAANQAECgYJDAAAAA==.',
Zl='Zluco:BAABNQAECoEkAAMaAAkKtx42BAAhAwAaAAkKtx42BAAhAwADAAYKeRyDTAC2AQAAAA==.',
Zo='Zoomy:BAAANQADCgQIBAAAAA==.',
Zy='Zypherion:BAAANQADCgQJBAAAAA==.',
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
