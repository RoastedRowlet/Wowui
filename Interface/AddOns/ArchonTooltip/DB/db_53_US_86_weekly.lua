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

local lookup = {'Hunter-BeastMastery','Unknown-Unknown','Rogue-Subtlety','DeathKnight-Blood','DeathKnight-Unholy','Shaman-Restoration','Paladin-Retribution','Priest-Holy','Monk-Mistweaver','Warlock-Destruction','Warlock-Affliction','Priest-Shadow','Rogue-Assassination','Paladin-Holy','DemonHunter-Havoc','Druid-Balance','Hunter-Marksmanship','Paladin-Protection','DeathKnight-Frost','Druid-Guardian','Mage-Arcane','Priest-Discipline','DemonHunter-Devourer','Druid-Restoration','Warlock-Demonology','Monk-Windwalker','Hunter-Survival','Shaman-Enhancement','Rogue-Outlaw','Evoker-Preservation','Mage-Fire',}
local provider = {region='US',realm="Eldre'Thalas",name='US',type='weekly',zone=53,date='2026-09-29',data={Ad='Adesira:BAAANQADCggIDwAAAA==.Adrastus:BAAANQADCggIDAABNQAECggIGAABABoSAA==.',
Ae='Aeslin:BAAANQADCgYJBgABNQAECgEIAQACAAAAAA==.',
Ah='Ahn:BAAANQADCgUJBQAAAA==.Ahylin:BAAANQADCgcIDAAAAA==.',
Ai='Ainslie:BAAANQAECgQIBAAAAA==.',
Al='Alerana:BAAANQADCggIGAAAAA==.Altria:BAAANQADCgQIBAAAAA==.',
An='An:BAAANQAECgQIDwABNQAECgkJJwADAKYjAA==.Anarose:BAAANQAECgUIBwAAAA==.Antityk:BAAANQAECgIIAgABNQAECggIGAABABoSAA==.',
Ar='Aragorn:BAAANQADCgQIBQAAAA==.Arahant:BAAANQAECgIIAgAAAA==.Aretas:BAABNQAECoEZAAMEAAcK2B+2GwCeAgAEAAcK2B+2GwCeAgAFAAEK4Q2isAAxAAAAAA==.Armadian:BAAANQAECgQICAAAAA==.Arrianne:BAAANQADCgYIBgAAAA==.Arriånna:BAAANQADCgcIDQAAAA==.Artemist:BAAANQAECggICwAAAA==.',
As='Asifa:BAAANQADCggIFgAAAA==.',
At='Atherion:BAAANQAECgQJCwAAAA==.',
Au='Aurakk:BAAANQADCgYIDAABNQAECgQICQACAAAAAA==.',
Av='Avelin:BAAANQADCgUIBQAAAA==.Avranarada:BAAANQAECgcIEgAAAA==.Avril:BAAANQAECgEIAQAAAA==.',
Az='Azkara:BAABNQAECoEhAAIGAAkK6Rm7IQCqAgAGAAkK6Rm7IQCqAgAAAA==.Azung:BAABNQAECoEYAAIHAAgKph4gMQDGAgAHAAgKph4gMQDGAgAAAA==.',
Ba='Babaisyaga:BAACNQAFFIEIAAIBAAMK5BpYDAALAQABAAMK5BpYDAALAQA1AAQKgS8AAgEACQpjI7YMAFYDAAEACQpjI7YMAFYDAAAA.Baka:BAAANQAECgUJCAAAAA==.Balinse:BAAANQAECgUIDAABNQAECgYIEAACAAAAAA==.Balystix:BAAANQADCggICAAAAA==.Barb:BAAANQAECgEIAQAAAA==.Barrelrollin:BAAANQADCgYIDwAAAA==.',
Be='Beastfodays:BAABNQAECoEoAAIBAAkKmhhPLACqAgABAAkKmhhPLACqAgAAAA==.Bethlahammer:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.',
Bi='Billcritin:BAAANQAECgYICwAAAA==.',
Bl='Blackleaf:BAAANQADCgQIBwAAAA==.Blawyke:BAAANQADCgYIBgABNQAFFAIIAgACAAAAAA==.Bless:BAAANQADCgYJBgAAAA==.Blizzcon:BAABNQAECoEvAAIIAAkKWCPCBQB/AwAIAAkKWCPCBQB/AwAAAA==.Bloodsurge:BAAANQADCgQJAwAAAA==.Blushies:BAAANQAECgUIDAAAAA==.',
Bo='Boltzfodayz:BAAANQAECgEIAQAAAA==.Bonerslap:BAAANQADCgEJAQAAAA==.Boone:BAAANQADCgMIAwAAAA==.Borrgar:BAAANQAECgQICQAAAA==.',
Br='Brackle:BAAANQAECgYIDAAAAA==.Bracori:BAABNQAECoElAAIJAAkKVA9JEgAGAgAJAAkKVA9JEgAGAgAAAA==.Brandywynne:BAABNQAECoEWAAIBAAgK5gv8ZAD1AQABAAgK5gv8ZAD1AQAAAA==.Bretcha:BAAANQADCgQIBAABNQAECgQIBQACAAAAAA==.Brick:BAABNQAECoEXAAIDAAgKcxfcDgBsAgADAAgKcxfcDgBsAgAAAA==.Brightfame:BAABNQAECoEbAAMKAAgKWxYSFQC5AQAKAAYK1xYSFQC5AQALAAQKGxYNDgAnAQAAAA==.Bronny:BAAANQAECgUICQAAAA==.Brônwyn:BAAANQADCgQIBAAAAA==.',
Bu='Buffshagwell:BAABNQAECoEaAAIHAAcKyB1AUwBKAgAHAAcKyB1AUwBKAgAAAA==.Butterbllz:BAABNQAECoEfAAIHAAkKYBynNAC4AgAHAAkKYBynNAC4AgAAAA==.',
Ca='Calypsio:BAAANQADCgQIBAABNQADCggIHgACAAAAAA==.Camany:BAAANQAECgYIEQAAAA==.Captinkrunch:BAAANQADCgEJAQAAAA==.Caretakerz:BAAANQAECgYIDwAAAA==.Cartus:BAAANQADCgUICAABNQAECgQIBwACAAAAAA==.Cayin:BAABNQAECoEaAAIEAAgKaCCXEwDlAgAEAAgKaCCXEwDlAgABNQABCgYICwACAAAAAA==.',
Ch='Chemoshh:BAAANQADCggIBgABNQAECgQICQACAAAAAA==.',
Cl='Clamshell:BAAANQAECgcIEgAAAA==.Claudette:BAAANQAECgYICQAAAA==.Clayier:BAAANQADCgYIDAAAAA==.',
Cn='Cntendr:BAAANQADCgUIBQAAAA==.',
Co='Codenike:BAAANQAECgQICwAAAA==.Copenzen:BAAANQAECgIIAgAAAA==.Corelheals:BAAANQADCgcICgAAAA==.Covertyqt:BAAANQAECgcIEgAAAA==.Coyote:BAAANQABCgUIBgAAAA==.',
Cp='Cptnhuman:BAAANQAECgcIEgAAAA==.',
Cr='Cromie:BAAANQADCggIFQAAAA==.Crosed:BAAANQADCgQIBAAAAA==.',
Cs='Cshunter:BAAANQADCgYIBwAAAA==.',
Cu='Cubcakes:BAAANQADCggIBQAAAA==.',
['Cõ']='Cõrpses:BAEANQAECgYIDQABNQAECgUIBgACAAAAAA==.',
Da='Daboof:BAAANQADCgYIEwAAAA==.Daemandred:BAAANQADCgIIAgAAAA==.Daggere:BAAANQADCgYJGQAAAA==.Danke:BAAANQADCgYIFAAAAA==.Dankz:BAAANQAECgEIAQAAAA==.Darkenmicky:BAAANQADCgcIEwAAAA==.Darkmickyz:BAAANQAECgQIBwAAAA==.Darthbobula:BAAANQAFFAEIAQAAAA==.Dayloc:BAAANQADCgcIDQAAAA==.',
De='Deataria:BAAANQAECgUIEAAAAA==.Deawin:BAAANQADCgQIBAABNQADCgYIDwACAAAAAA==.Delilia:BAEANQAECggIBQABNQAECggIEAACAAAAAA==.Delryth:BAAANQADCgYIBQAAAA==.Demonikk:BAAANQAECgUICgABNQAECggIGAABABoSAA==.Demontyk:BAAANQAECgIIAgABNQAECggIGAABABoSAA==.Desception:BAAANQADCgQIBwAAAA==.',
Di='Diadochi:BAAANQAECgQJBQAAAA==.Dieguerta:BAAANQADCgEJAQAAAA==.',
Dl='Dl:BAABNQAECoEaAAIMAAgKkhm9FwBTAgAMAAgKkhm9FwBTAgAAAA==.',
Dr='Drakkarr:BAAANQADCgYIBwAAAA==.Drazhoath:BAAANQAECgUIDQAAAA==.Drdrill:BAAANQADCgYIBgAAAA==.Drimbirt:BAAANQADCgQIBwAAAA==.Drinkmormilk:BAAANQADCgQIBwAAAA==.Drogelf:BAAANQADCgYIDQAAAA==.Drogman:BAAANQADCgIIAgAAAA==.',
Du='Dumbledore:BAAANQADCgcIBwABNQAECgEIAQACAAAAAA==.',
['Dá']='Dáwnbringer:BAAANQADCgIIBAAAAA==.',
Eb='Ebullition:BAAANQAECgEIAQAAAA==.',
Ed='Edensfury:BAAANQAECgIIAgAAAA==.',
Ee='Eedani:BAAANQADCgUJCQAAAA==.',
Ei='Eigi:BAAANQAECgcIDwAAAA==.',
El='Eldanon:BAABNQAECoEeAAIKAAgKhyJRAgArAwAKAAgKhyJRAgArAwAAAA==.Elementality:BAAANQADCgIIAgAAAA==.Eleyert:BAAANQAECgcIEwAAAA==.Elistann:BAAANQADCggIEQABNQAECgQICQACAAAAAA==.Elwe:BAAANQAECgUIDAAAAA==.',
Em='Embaku:BAAANQADCggICAABNQAECggIHwAHAHYTAA==.Emrhakul:BAAANQABCggIEAAAAA==.',
En='Enkidu:BAAANQAECgQICQAAAA==.Enseth:BAAANQAECgQICgAAAA==.',
Er='Erakha:BAAANQAECgQIBQAAAA==.Erandria:BAAANQADCgUJBQABNQADCgUIDgACAAAAAA==.',
Eu='Eulogy:BAAANQADCgYICAABNQAECgkJLwAIAFgjAA==.',
Ez='Ezerharden:BAAANQABCgEJAQAAAA==.Ezki:BAAANQADCgYICAABNQAECgQICQACAAAAAA==.',
Fa='Fairious:BAAANQAECgYIEwAAAA==.',
Fe='Felcon:BAAANQADCgYJCAAAAA==.Felenkeller:BAAANQAECgIIAgABNQAECgkJIwAFAD0lAA==.Fenrirr:BAAANQADCggICAABNQAECgQICQACAAAAAA==.Fet:BAABNQAECoEdAAMDAAkK4R78DACKAgADAAgKXB/8DACKAgANAAQKRR53OwBfAQAAAA==.',
Fh='Fhatbashtud:BAAANQADCgcJEQAAAA==.',
Fl='Flatline:BAAANQAECgYIDgAAAA==.Flinnt:BAAANQADCgEIAQABNQAECgQICQACAAAAAA==.',
Fn='Fngusamungus:BAAANQAECgEIAQAAAA==.',
Fo='Folgore:BAAANQADCgUIBQAAAA==.Four:BAAANQAECgMJBQAAAA==.',
Fr='Fredwarlock:BAAANQAECgEIAQAAAA==.Frysky:BAAANQAECgUIBgAAAA==.',
Fu='Furiousv:BAAANQADCgUIBQAAAA==.Futz:BAABNQAECoEcAAIOAAYKqiFuOgA8AgAOAAYKqiFuOgA8AgAAAA==.',
Ga='Gahnzul:BAAANQADCgUIBQAAAA==.Gajitbek:BAAANQADCgMIAwAAAA==.Galah:BAAANQAECgYIDAAAAA==.',
Gn='Gnomicide:BAAANQADCggIHAAAAA==.',
Go='Gonesh:BAAANQADCgcICgAAAA==.Gooberpea:BAAANQABCgYIDgAAAA==.Gordoe:BAAANQADCgUIBQAAAA==.',
Gr='Graveborne:BAAANQADCgcIDgAAAA==.Gravess:BAAANQADCgUIBQAAAA==.Gravewin:BAAANQADCgQICgABNQADCgYIDwACAAAAAA==.Gravyexpress:BAABNQAECoE2AAIPAAgK4h5yFQCzAgAPAAgK4h5yFQCzAgAAAA==.Grendelheim:BAAANQADCgYIEQAAAA==.Grogar:BAAANQADCgYIDQAAAA==.',
Gu='Gula:BAAANQADCgcIEQABNQAECgIIBAACAAAAAA==.',
Ha='Hadez:BAAANQADCgUIBQAAAA==.Hagrok:BAAANQABCgQIBgAAAA==.Hantak:BAAANQADCgMIBgAAAA==.Harmsway:BAAANQADCgcJEQAAAA==.Hathaendron:BAAANQABCgMJAwAAAA==.',
He='Hephaestus:BAAANQAECgQIBAAAAA==.',
Ho='Hocka:BAAANQADCgUIBgAAAA==.Holysmight:BAAANQAECgEIAQAAAA==.Holyumo:BAAANQADCgYIBgAAAA==.Holyyballs:BAAANQAECgMIBAABNQAECgUICAACAAAAAA==.Howlymandel:BAAANQAECgIIAgABNQAECgcIGAAQAE8LAA==.Hoytx:BAAANQADCgUIBQAAAA==.',
Hy='Hydraciel:BAAANQAECgYIDgAAAA==.',
['Hì']='Hìroko:BAAANQADCggIIAAAAA==.',
Ic='Icedemon:BAAANQADCgYIBgAAAA==.Icupapi:BAAANQADCggIGAAAAA==.Icynips:BAAANQABCgEIAQAAAA==.',
Im='Im:BAAANQADCgEJAQABNQAECgkJJwADAKYjAA==.Imabigman:BAAANQADCgcICAAAAA==.Imaleaf:BAABNQAECoEaAAIQAAgKFgd/SgBrAQAQAAgKFgd/SgBrAQAAAA==.Imperius:BAAANQAECgEIAQAAAA==.',
Ip='Iplaydead:BAABNQAECoEYAAMBAAgKGhIjVQAhAgABAAgKGhIjVQAhAgARAAEKigO1dwAmAAAAAA==.',
Ir='Iroh:BAAANQAECgQICQAAAA==.',
Is='Ismokeprot:BAAANQADCgMIAwAAAA==.',
Ja='Jawnson:BAAANQAECgcIEgAAAA==.',
Je='Jelluz:BAAANQADCgUIBQAAAA==.Jenefer:BAABNQAECoEjAAMEAAgKWx2YJgBRAgAEAAgKQR2YJgBRAgAFAAIK7BTAjACHAAAAAA==.Jeslartoma:BAAANQADCgEIAQABNQADCgYIDAACAAAAAA==.',
Ji='Jimjimmy:BAAANQADCgcIBwABNQAECgIIAgACAAAAAA==.',
Jo='Jondooz:BAAANQAECgcIBwAAAA==.',
Ka='Kailback:BAAANQAECgEIAgABNQAECgcIEAACAAAAAA==.Kait:BAAANQAECgcIEAAAAA==.Kalcifur:BAABNQAECoEfAAMOAAkKMhjHJwCUAgAOAAkKMhjHJwCUAgASAAEKHhaAVAA7AAAAAA==.Karin:BAAANQADCgUIBQABNQAECgQIBwACAAAAAA==.Karnelian:BAAANQAECgMIAwABNQAFFAEIAQACAAAAAA==.Karras:BAAANQADCgUIBQAAAA==.Kashisht:BAAANQADCgYJEQAAAA==.Kasstigate:BAAANQAECgUICgABNQAECggIIwAEAFsdAA==.Kastiel:BAAANQAECgYIEAAAAA==.Katstrider:BAABNQAECoEZAAIBAAcKtxR2ZQDzAQABAAcKtxR2ZQDzAQAAAA==.Kattarea:BAAANQADCgUJCAABNQAECgcIGQABALcUAA==.Kavica:BAAANQADCggIFAABNQAECgQICwACAAAAAA==.',
Ke='Keldean:BAAANQAECgYIDQAAAA==.Keryka:BAABNQAECoEhAAMTAAkKpSBJFgCUAgATAAcKKCFJFgCUAgAFAAgKoh2jKgA2AgAAAA==.',
Kh='Khere:BAAANQADCgUIBwAAAA==.',
Ki='Kiterisa:BAAANQAECgcIEgAAAA==.',
Kk='Kkazz:BAAANQADCggICwABNQAECgQICQACAAAAAA==.',
Ko='Kohn:BAAANQAECgUIBwAAAA==.Kona:BAEANQAECgUIBgAAAA==.Korbusty:BAAANQADCggIDgAAAA==.',
Ku='Kuattieb:BAAANQABCgIIAgAAAA==.',
La='Ladýfinger:BAAANQAECgYIEQABNQAECgkJJQAUAF0cAA==.Laisidhiel:BAAANQADCggILAAAAA==.Lateo:BAAANQAECgYJEQAAAA==.Lawz:BAAANQAECgUIBwAAAA==.',
Le='Lelianna:BAAANQADCgYIEwAAAA==.Lemonruss:BAAANQADCggIEAAAAA==.Lexia:BAAANQAECgIIAwAAAA==.',
Li='Libidine:BAAANQADCgQIBAABNQAECgIIBAACAAAAAA==.Liemannin:BAAANQAECgEIAQAAAA==.Lightninghah:BAAANQABCgIIAgAAAA==.Lilturtz:BAAANQADCgUIBQABNQAECgUIDAACAAAAAA==.Linnea:BAAANQADCgcIDQAAAA==.',
Lo='Locksative:BAAANQADCggIHQAAAA==.Longhorn:BAAANQAECgYIDgAAAA==.Lorekesh:BAAANQADCgEJAQABNQAECgYICQACAAAAAA==.Lorriena:BAAANQADCgUIBQABNQADCgYICAACAAAAAA==.Lortpegsalot:BAABNQAECoEjAAIHAAgK9CB5MQDFAgAHAAgK9CB5MQDFAgAAAA==.Lowy:BAAANQAECgIIAgAAAA==.',
Lu='Lucena:BAAANQAECgQICAAAAA==.Lurg:BAAANQADCgQJBAABNQADCggIHQACAAAAAA==.',
Ly='Lyralana:BAAANQADCgQIBwABNQADCgUIDgACAAAAAA==.',
Ma='Maberu:BAABNQAECoEWAAIJAAgKAgi8HABfAQAJAAgKAgi8HABfAQABNQAECgkJHwAOADIYAA==.Madamholy:BAAANQAECgQIBwAAAA==.Madamkluck:BAAANQADCgUIBQAAAA==.Maglubiyet:BAAANQAECgEIAQAAAA==.Magnitood:BAAANQAECgIIAgAAAA==.Malbjornion:BAAANQAECgMIBAAAAA==.Malphox:BAAANQADCgQICAAAAA==.Manbearcat:BAAANQAECgQIBwAAAA==.Manhole:BAAANQAECgQIDAAAAA==.Markyb:BAAANQADCgYICQAAAA==.Masamura:BAACNQAFFIEFAAIVAAIKxg4QMwCfAAAVAAIKxg4QMwCfAAA1AAQKgSoAAhUACQrXGltAAOMCABUACQrXGltAAOMCAAAA.Maureanna:BAAANQADCgUIDgAAAA==.',
Me='Mechahuntard:BAAANQADCgEIAQAAAA==.Medanii:BAEBNQAECoEaAAQWAAgKwg5UCgBzAQAWAAYKVRJUCgBzAQAIAAQKOAXUnQDHAAAMAAQKFwrHRAC4AAAAAA==.Melorm:BAAANQAECgEIAQAAAA==.',
Mi='Millizh:BAACNQAFFIEUAAMBAAcK1B+nAgD2AQABAAUK4iCnAgD2AQARAAQKfRx9CQBcAQA1AAQKgSIAAxEACQpuJvwCAJsDABEACQo+JvwCAJsDAAEABgrOIothAP4BAAAA.Mirasharu:BAAANQADCgYIDwAAAA==.Mireille:BAAANQADCgYIDQAAAA==.Mitsuri:BAAANQAECgUICgAAAA==.Mitzuky:BAAANQADCgMIAwAAAA==.',
Mo='Moonlïght:BAAANQAECgcIDgAAAA==.Morganlefay:BAAANQAECgIIAwAAAA==.Morlyn:BAAANQAECgUICAAAAA==.Morregan:BAAANQAECgEIAQAAAA==.Mousereaper:BAABNQAECoEWAAIXAAcKqxAiKgCzAQAXAAcKqxAiKgCzAQAAAA==.',
My='Mydnight:BAAANQABCgIIAgAAAA==.Mystìc:BAAANQAECgcIEAAAAA==.Mystíc:BAAANQADCggIJAABNQAECgcIEAACAAAAAA==.',
['Má']='Májorrobot:BAAANQAECggIEQAAAA==.',
['Mé']='Ménopáwz:BAAANQAECgIIAgABNQAECgkJIwAFAD0lAA==.',
Na='Namor:BAAANQADCggICwAAAA==.Nattisca:BAAANQADCgYIDAAAAA==.',
Ne='Nessà:BAAANQAECgIIBAAAAA==.Neveenn:BAABNQAECoEkAAIYAAgKThiVFABcAgAYAAgKThiVFABcAgAAAA==.',
Ni='Nirith:BAAANQADCgYIDQAAAA==.',
No='Nohatcat:BAAANQADCggIEgABNQAECgUIDAACAAAAAA==.',
['Nâ']='Nâmii:BAAANQADCgUICAAAAA==.',
['Nè']='Nèzukõ:BAAANQAECgQICwAAAA==.',
Ob='Obata:BAAANQAECgEIAQAAAA==.',
Oc='Octavius:BAAANQADCggJDQABNQAECgIIAgACAAAAAA==.',
Oj='Ojore:BAEANQAECgUICwAAAA==.Ojoverde:BAABNQAECoEjAAIZAAkKHBH5TQAjAgAZAAkKHBH5TQAjAgAAAA==.',
On='Onizuka:BAAANQADCgEIAQABNQADCgcICQACAAAAAA==.Onside:BAAANQAECgYICgABNQAECgkJGgAaAAAdAA==.',
Op='Ophillã:BAAANQAECgEIAgABNQAECgIIBAACAAAAAA==.',
Or='Ordenn:BAAANQADCgQIBAABNQAECgkJHQADAOEeAA==.Orian:BAAANQADCgQIBwAAAA==.',
Oz='Ozz:BAABNQAECoEZAAIaAAgK2w/LIQC+AQAaAAgK2w/LIQC+AQAAAA==.Ozzerker:BAAANQADCgEIAQAAAA==.Ozzullr:BAAANQAECgcIDQAAAA==.',
Pa='Painbreak:BAAANQADCgEIAQABNQAECgYIDwACAAAAAA==.Pajamas:BAAANQAECgEJAQABNQAECgUICgACAAAAAA==.Pallanquin:BAAANQADCgYJCQAAAA==.Papichili:BAAANQAECgEIAQAAAA==.Pashnir:BAAANQADCgUIBgAAAA==.',
Pe='Peachey:BAAANQAECgUICAAAAA==.Peaker:BAAANQAECgMIAwAAAA==.Peakra:BAAANQAECgUIBQAAAA==.',
Pi='Pigas:BAABNQAECoEXAAIaAAcKChGIJACgAQAaAAcKChGIJACgAQAAAA==.',
Pr='Prestoresto:BAAANQADCgYIDwAAAA==.',
Ps='Psychosix:BAAANQAECgcJCwAAAA==.',
Qu='Quinberos:BAAANQAECgIIAwABNQAECgMIAwACAAAAAA==.',
Ra='Racey:BAAANQADCggICAAAAA==.Ramdel:BAAANQAECgIIAgABNQAECgcIGQAbAEQdAA==.Ramstrider:BAABNQAECoEZAAIbAAcKRB1wBABRAgAbAAcKRB1wBABRAgAAAA==.Ranch:BAAANQADCgcICQAAAA==.Rapture:BAAANQAECgYIDAAAAA==.Ravec:BAAANQABCgQJBQAAAA==.',
Re='Rengell:BAAANQAECgQICQABNQAECgcIGAAQAE8LAA==.',
Rh='Rheagall:BAABNQAECoEXAAIcAAkK+xeiCAC/AgAcAAkK+xeiCAC/AgAAAA==.Rhodetta:BAAANQAECggIDwAAAA==.',
Ri='Rizepriest:BAAANQADCgIIAgABNQAECgQIBwACAAAAAA==.Rizerage:BAAANQAECgQIBwAAAA==.',
Ro='Roaraxe:BAAANQADCgYIBgABNQAECgIIAgACAAAAAA==.Rowena:BAABNQAECoEqAAIQAAgKlRAGNgDuAQAQAAgKlRAGNgDuAQAAAA==.Rowynna:BAAANQAECgMIAwAAAA==.Roxy:BAAANQADCgYIBgAAAA==.Roxymonk:BAAANQADCgYIBgAAAA==.Royalviaman:BAAANQADCgQIBwAAAA==.',
Ry='Ryz:BAAANQADCggICAAAAA==.Ryztkmtchrch:BAABNQAECoElAAQWAAgK5RvcCQB+AQAIAAgK5Rs7OgA5AgAWAAcKww3cCQB+AQAMAAUKJg+rNwATAQAAAA==.',
['Rå']='Råti:BAAANQADCgUIBQAAAA==.',
Sa='Sacdk:BAAANQAECgQIBwAAAA==.Safaria:BAAANQAECgEIAQABNQAECgQJBwACAAAAAA==.Saloenus:BAAANQAECgYICgAAAA==.Sarlyssa:BAAANQABCgYICgAAAA==.Saucehoss:BAABNQAECoEgAAQLAAkKlRxOAgDNAgALAAkKlRxOAgDNAgAZAAMKag7y2wCnAAAKAAMK5Q3bQwCgAAAAAA==.Saucymac:BAAANQAECgYIBQAAAA==.',
Sc='Scofflaw:BAAANQADCgEIAQABNQAECgQIBAACAAAAAA==.Scubasteve:BAAANQADCgUIBQAAAA==.',
Se='Sefi:BAAANQAECgUIDgAAAA==.Semirrhage:BAAANQADCgMIAwAAAA==.',
Sh='Shadowflame:BAAANQAECgUICgAAAA==.Shammygoat:BAAANQAECgUIDQAAAA==.Shaqattack:BAABNQAECoEaAAIaAAkKAB0MDgDHAgAaAAkKAB0MDgDHAgAAAA==.Shaqattaq:BAAANQAECgQIBAABNQAECgkJGgAaAAAdAA==.Sharktide:BAABNQAECoEXAAIGAAcKwBrRQwAFAgAGAAcKwBrRQwAFAgAAAA==.Shawnella:BAAANQAECgcIEgAAAA==.Shenlune:BAAANQAECgQIBwAAAA==.Sheutka:BAAANQADCggIHAAAAA==.Shiggles:BAAANQADCgYIGgAAAA==.Shinaie:BAAANQAECgQIBwAAAA==.Shocknrollz:BAAANQAECgQIDAAAAA==.Shogún:BAAANQAECgUIDQABNQAECggIEAACAAAAAA==.Shtylez:BAAANQADCggIIQABNQAECggIGAABABoSAA==.',
Si='Silntwolf:BAAANQABCgQIBAAAAA==.Silpion:BAAANQAECgQIBQAAAA==.Silth:BAAANQADCggIEAAAAA==.Sinariel:BAAANQAECgcIEQAAAA==.Sirdank:BAAANQAECgEIAQAAAA==.',
Sk='Skarlate:BAAANQADCgYIBgAAAA==.Skâld:BAEANQADCgYICwAAAA==.',
Sl='Sliko:BAABNQAECoEfAAIHAAgK0hJEbwD0AQAHAAgK0hJEbwD0AQAAAA==.',
Sm='Smmoke:BAAANQAECgcIEgAAAA==.',
Sn='Sneekypally:BAAANQAECgQIBwAAAA==.Snowballs:BAAANQAECgUICAAAAA==.',
So='Softhorn:BAAANQABCgUIBQAAAA==.Soull:BAABNQAECoEfAAIYAAgKliQoBABnAwAYAAgKliQoBABnAwAAAA==.Soulsmash:BAAANQADCggICQAAAA==.',
Sp='Spacestepdad:BAAANQAECgQIBwAAAA==.Sparkie:BAAANQADCggIHgAAAA==.Spriggan:BAAANQAECgUIBQAAAA==.',
Sq='Squashfoot:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.',
St='Starface:BAABNQAECoElAAIUAAkKXRzVBQDdAgAUAAkKXRzVBQDdAgAAAA==.Stargoose:BAAANQAECgMIAwABNQAECgkJJQAUAF0cAA==.Steelytree:BAAANQADCgQIBwAAAA==.Stellaria:BAAANQAECgQICAAAAA==.Steris:BAAANQADCggIDAABNQADCggIHQACAAAAAA==.Steverogers:BAAANQAECgMIBwABNQAECgkJIwAFAD0lAA==.Stocktonrush:BAABNQAECoEjAAMFAAkKPSWcBwBnAwAFAAkKOyWcBwBnAwAEAAEKnyN1lwBkAAAAAA==.Stonedhenge:BAAANQABCgQIBAAAAA==.Sturmx:BAAANQAECgcIEgAAAA==.',
Su='Subedei:BAAANQAECgcIEwAAAA==.Summerseve:BAAANQAECgMIAwAAAA==.Sunderhorn:BAAANQADCggIHAAAAA==.Suriaa:BAABNQAECoEfAAMNAAgKUxIXIAAlAgANAAgKUxIXIAAlAgAdAAQKFAnvEADPAAAAAA==.',
Sv='Svictis:BAAANQAECgMIAwAAAA==.Svictiss:BAAANQADCgUIBQAAAA==.',
Sw='Swami:BAAANQAECgQIBAAAAA==.',
Ta='Talila:BAAANQAECgQICQAAAA==.Taniss:BAAANQADCggIDgABNQAECgQICQACAAAAAA==.Taurdeth:BAAANQAECgYIBgABNQAECggIDwACAAAAAA==.',
Te='Terrya:BAAANQAECgUIBQAAAA==.Teryail:BAAANQADCgUIBQAAAA==.',
Th='Thaqdaddy:BAAANQADCgYIBgABNQAECggIGAAEAD8RAA==.Thaqknight:BAABNQAECoEYAAIEAAgKPxFHQwCrAQAEAAgKPxFHQwCrAQAAAA==.Therylnn:BAAANQABCgUJBQAAAA==.Thesthamenth:BAAANQADCgYIBgAAAA==.Thily:BAAANQADCgIIAgAAAA==.Thorwallen:BAAANQADCggIDQABNQAECgQICQACAAAAAA==.Thror:BAAANQAECgEIAQAAAA==.',
Ti='Tiac:BAAANQAECgEIAQAAAA==.Tiergyll:BAAANQABCgIIBAAAAA==.Tirithor:BAABNQAECoEfAAIHAAgKdhM+awAAAgAHAAgKdhM+awAAAgAAAA==.',
To='Tockell:BAAANQADCgQIBwAAAA==.Togala:BAAANQADCgUIBwABNQAECgQIBQACAAAAAA==.Toothless:BAAANQAECgEIAQAAAA==.Torbin:BAAANQAECgEIAgAAAA==.Touchmywave:BAAANQADCgcIDgABNQAECgkJKAABAJoYAA==.',
Tr='Tryjinks:BAAANQAECgYICAAAAA==.',
Ts='Tsunameh:BAAANQADCgcIFgABNQAECggIGAABABoSAA==.',
Tu='Tusky:BAAANQADCgYIBgAAAA==.',
Ty='Tykahndrius:BAAANQAECgcIDQABNQAECggIGAABABoSAA==.Tylîus:BAAANQAECgcICAAAAA==.Tyredelsia:BAAANQABCggIFAAAAA==.',
['Tö']='Töph:BAAANQADCgYIBgABNQAECgIIBAACAAAAAA==.',
['Tú']='Túsk:BAAANQADCgYIBwAAAA==.',
['Tý']='Týlius:BAAANQAECgMIBAABNQAECgcICAACAAAAAA==.',
Uk='Ukika:BAAANQAECgEIAQABNQAECgQIBQACAAAAAA==.',
Us='Useriòs:BAAANQADCgIIAwAAAA==.',
Ut='Uthilon:BAAANQAECgcIEgAAAA==.',
Va='Valdare:BAAANQAECgQICQAAAA==.Validorn:BAAANQADCggIEgAAAA==.',
Ve='Vedillian:BAAANQAECgEJAQAAAA==.Velduar:BAAANQADCgQJBAAAAA==.',
Vi='Victorr:BAAANQADCgUIDAAAAA==.Viktorius:BAAANQADCgQIBAAAAA==.Vixious:BAAANQADCgUIAwAAAA==.Vizigoth:BAAANQAECgUIDgAAAA==.',
Vo='Vordell:BAAANQAECgMIBQABNQAECggIDwACAAAAAA==.Voyana:BAAANQAECgQJBwAAAA==.Voz:BAAANQADCgUIBQAAAA==.',
Vy='Vydragon:BAABNQAFFIEFAAIeAAMKDgkkDADmAAAeAAMKDgkkDADmAAABNQAECgkJJQAVADIfAA==.Vymage:BAABNQAECoElAAMVAAkKMh8bOgD1AgAVAAkKMh8bOgD1AgAfAAMK8BSFBQDWAAAAAA==.',
['Vá']='Válidüs:BAACNQAFFIEKAAIIAAQKcwhlDwA3AQAIAAQKcwhlDwA3AQA1AAQKgSsAAggACQqJIo0KAEsDAAgACQqJIo0KAEsDAAAA.',
['Vã']='Vãsh:BAAANQADCggIHAAAAA==.',
Wa='Wabìsuke:BAAANQADCggIFQAAAA==.Waterlogged:BAAANQADCgQJCgAAAA==.Waterloo:BAAANQADCgYICQAAAA==.',
Wi='Wizpigas:BAAANQADCgcIDQABNQAECgcIFwAaAAoRAA==.',
['Wì']='Wìccka:BAAANQADCgUIBQAAAA==.',
Xi='Xi:BAAANQAECgMIAwAAAA==.Xifan:BAAANQAFFAEIAQAAAA==.',
Yd='Yd:BAAANQAECgQIBAABNQAECgkJJwADAKYjAA==.',
Yg='Yggdrasill:BAAANQABCgUICAAAAA==.',
Yi='Yingpi:BAAANQABCgIIAgAAAA==.',
Yo='Yodaa:BAAANQADCggICQABNQAECgQICQACAAAAAA==.',
Ys='Ys:BAAANQAECgQIBAABNQAECgkJJwADAKYjAA==.',
Yt='Yt:BAAANQAECgQICgABNQAECgkJJwADAKYjAA==.',
Yw='Ywontudie:BAAANQADCgIIAgAAAA==.',
Yz='Yz:BAABNQAECoEnAAMDAAkKpiNxAgCAAwADAAkKpiNxAgCAAwANAAIKUxvQYQCKAAAAAA==.',
Za='Zashawa:BAAANQADCgYICwAAAA==.',
Ze='Zenithgrey:BAAANQAECgcIEwAAAA==.',
Zl='Zluco:BAABNQAECoEnAAMcAAkKER9+BQATAwAcAAkKER9+BQATAwAGAAYKeRx5WwCoAQAAAA==.',
Zo='Zoomy:BAAANQADCgQIBAAAAA==.',
Zy='Zypherion:BAAANQADCgQIBgAAAA==.',
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
