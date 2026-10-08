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

local lookup = {'Hunter-BeastMastery','Unknown-Unknown','Rogue-Subtlety','DeathKnight-Blood','DeathKnight-Unholy','Druid-Restoration','Druid-Balance','Shaman-Restoration','Paladin-Retribution','Priest-Holy','Monk-Mistweaver','Warlock-Destruction','Warlock-Affliction','Druid-Guardian','DeathKnight-Frost','Mage-Arcane','Priest-Shadow','Shaman-Elemental','Rogue-Assassination','Paladin-Holy','DemonHunter-Havoc','Hunter-Marksmanship','Paladin-Protection','Mage-Frost','Priest-Discipline','DemonHunter-Devourer','Shaman-Enhancement','Warrior-Arms','Warlock-Demonology','Monk-Windwalker','Hunter-Survival','Rogue-Outlaw','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Mage-Fire',}
local provider = {region='US',realm="Eldre'Thalas",name='US',type='weekly',zone=53,date='2026-10-06',data={Ad='Adesira:BAAANQADCggIFwAAAA==.Adrastus:BAAANQAECgMIAwABNQAECggIHgABAPcTAA==.',
Ae='Aeslin:BAAANQADCgYJBgABNQAECgEIAQACAAAAAA==.',
Ah='Ahn:BAAANQADCggIDQAAAA==.Ahylin:BAAANQADCgcIDAAAAA==.',
Ai='Ainslie:BAAANQAECgQICAAAAA==.',
Al='Alerana:BAAANQADCggIGAAAAA==.Altria:BAAANQADCgQIBAAAAA==.',
An='An:BAAANQAECgQIEwABNQAECgkJLgADAEskAA==.Anarose:BAAANQAECgUIDAAAAA==.Antityk:BAAANQAECgQIBgABNQAECggIHgABAPcTAA==.',
Ar='Aragorn:BAAANQADCgQIBQAAAA==.Arahant:BAAANQAECgIIAgAAAA==.Aretas:BAABNQAECoEdAAMEAAgK+h8dFAD1AgAEAAgK+h8dFAD1AgAFAAEK4Q2EzgAxAAAAAA==.Armadian:BAAANQAECgQICAAAAA==.Arrianne:BAAANQADCgYIBgAAAA==.Arriånna:BAAANQADCgcIEwAAAA==.Artemist:BAAANQAECggIDwAAAA==.',
As='Asifa:BAAANQADCggIGQAAAA==.',
At='Atherion:BAAANQAECgYIEQAAAA==.Attackroot:BAAANQAECgEIAQABNQAECgUIDwACAAAAAA==.',
Au='Aurakk:BAAANQADCgYIDAABNQAECgQIDQACAAAAAA==.',
Av='Avelin:BAAANQADCgUIBQAAAA==.Avranarada:BAABNQAECoEaAAMGAAgKkhfgGgA3AgAGAAgKkhfgGgA3AgAHAAYKVxiPSwCMAQAAAA==.Avril:BAAANQAECgEIAQAAAA==.',
Az='Azkara:BAABNQAECoEkAAIIAAkKVx43HADhAgAIAAkKVx43HADhAgAAAA==.Azung:BAABNQAECoEbAAIJAAgKsB9lOQDHAgAJAAgKsB9lOQDHAgAAAA==.',
Ba='Babaisyaga:BAACNQAFFIELAAIBAAMK5BqdEQAHAQABAAMK5BqdEQAHAQA1AAQKgTIAAgEACQqUI1QQAE4DAAEACQqUI1QQAE4DAAAA.Baka:BAAANQAECgUJCAAAAA==.Balinse:BAAANQAECgYIEgAAAA==.Balystix:BAAANQADCggICAAAAA==.Barb:BAAANQAECgEIAQAAAA==.Barrelrollin:BAAANQADCgYIDwAAAA==.',
Be='Beastfodays:BAABNQAECoEsAAIBAAkKsBjCNgCkAgABAAkKsBjCNgCkAgAAAA==.Bethlahammer:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.',
Bi='Billcritin:BAAANQAECgYICwAAAA==.',
Bl='Blackleaf:BAAANQADCgQIBwAAAA==.Blawyke:BAAANQAECgIIAgABNQAFFAIIAgACAAAAAA==.Bless:BAAANQADCgYJBgAAAA==.Blizzcon:BAACNQAFFIEJAAIKAAUKNBD3DACXAQAKAAUKNBD3DACXAQA1AAQKgTEAAgoACQqEI2sGAIQDAAoACQqEI2sGAIQDAAAA.Bloodsurge:BAAANQADCgQJAwAAAA==.Blushies:BAAANQAECgUIEQAAAA==.',
Bo='Boltzfodayz:BAAANQAECgEIAQAAAA==.Bonerslap:BAAANQADCgEJAQAAAA==.Boone:BAAANQADCgMIAwAAAA==.Borrgar:BAAANQAECgQIDQAAAA==.',
Br='Brackle:BAAANQAECgcIEwAAAA==.Bracori:BAABNQAECoEoAAILAAkKdBEXFAAOAgALAAkKdBEXFAAOAgAAAA==.Brandywynne:BAABNQAECoEYAAIBAAgKtwzbcgD9AQABAAgKtwzbcgD9AQAAAA==.Bretcha:BAAANQADCgQIBAABNQAECgQIBgACAAAAAA==.Brick:BAABNQAECoEdAAIDAAgKNRhhEABlAgADAAgKNRhhEABlAgAAAA==.Brightfame:BAABNQAECoEiAAMMAAgKjxaoFgCvAQAMAAYK9BaoFgCvAQANAAQKWBajEAAZAQAAAA==.Bronny:BAAANQAECgYIDwAAAA==.Brônwyn:BAAANQADCgQIBAAAAA==.',
Bu='Buffshagwell:BAABNQAECoEgAAIJAAcKUx6CVgBpAgAJAAcKUx6CVgBpAgAAAA==.Bullrush:BAAANQADCgUIBQAAAA==.Butterbllz:BAABNQAECoEiAAIJAAkKYByXSACVAgAJAAkKYByXSACVAgAAAA==.',
Ca='Calypsio:BAAANQADCgQIBAABNQADCggIHgACAAAAAA==.Camany:BAABNQAECoEXAAIBAAYKURIqlQCrAQABAAYKURIqlQCrAQAAAA==.Captinkrunch:BAAANQADCgEJAQAAAA==.Caretakerz:BAABNQAECoEYAAIOAAgKix2QCQCjAgAOAAgKix2QCQCjAgAAAA==.Cartus:BAAANQAECgUIBQABNQAECgUIDAACAAAAAA==.Cayin:BAABNQAECoEbAAIEAAgKaCCTGADSAgAEAAgKaCCTGADSAgABNQABCgYICwACAAAAAA==.',
Ch='Chanta:BAAANQABCgYIBwAAAA==.Chanyeol:BAAANQAECgEIAQAAAA==.Chemoshh:BAAANQADCggIBgABNQAECgQIDQACAAAAAA==.',
Cl='Clamshell:BAABNQAECoEaAAMPAAgKlyCxFgCyAgAPAAgKASCxFgCyAgAEAAUK1hlLVwB0AQAAAA==.Claudette:BAAANQAECgcICgAAAA==.Clayier:BAAANQADCgYIDAAAAA==.',
Cn='Cntendr:BAAANQADCgUICAAAAA==.',
Co='Codenike:BAAANQAECgUIDwAAAA==.Copenzen:BAAANQAECgQIBAAAAA==.Corelheals:BAAANQAECgMIAwAAAA==.Covertyqt:BAABNQAECoEaAAIQAAgKkRzobACPAgAQAAgKkRzobACPAgAAAA==.Coyote:BAAANQABCgUIBgAAAA==.',
Cp='Cptnhuman:BAABNQAECoEaAAIFAAgKyR4VJgCEAgAFAAgKyR4VJgCEAgAAAA==.',
Cr='Cromie:BAAANQADCggIFQAAAA==.Crosed:BAAANQADCgQIBAAAAA==.',
Cs='Cshunter:BAAANQADCgYIBwAAAA==.',
Cu='Cubcakes:BAAANQADCggIBQAAAA==.',
['Cõ']='Cõrpses:BAEANQAECgYIDQABNQAECgUIBgACAAAAAA==.',
Da='Daboof:BAAANQADCgYIGAAAAA==.Daemandred:BAAANQADCgMIAwAAAA==.Daggere:BAAANQADCgcIIAAAAA==.Danke:BAAANQADCgYIGQAAAA==.Dankz:BAAANQAECgEIAQAAAA==.Darkenmicky:BAAANQADCgcIEwAAAA==.Darkmickyz:BAAANQAECgUIDAAAAA==.Darthbobula:BAAANQAFFAIIAwAAAA==.Dayloc:BAAANQAECgQIBAAAAA==.',
De='Deataria:BAABNQAECoEbAAIGAAYKMx3QIAD2AQAGAAYKMx3QIAD2AQAAAA==.Deawin:BAAANQADCgQIBAABNQADCgYIDwACAAAAAA==.Delilia:BAEANQAECggIBQABNQAECggIEAACAAAAAA==.Delryth:BAAANQADCgYIBQAAAA==.Demonikk:BAAANQAECgUICwABNQAECggIHgABAPcTAA==.Demontyk:BAAANQAECgQIBgABNQAECggIHgABAPcTAA==.Desception:BAAANQADCgQIBwAAAA==.',
Di='Diadochi:BAAANQAECgQJBQAAAA==.Dieguerta:BAAANQADCgEJAQAAAA==.',
Dl='Dl:BAABNQAECoEhAAIRAAgKkhkSHABCAgARAAgKkhkSHABCAgAAAA==.',
Dr='Drakkarr:BAAANQADCgYIBwAAAA==.Drazhoath:BAAANQAECgUIDQAAAA==.Drdrill:BAAANQADCgYIBgAAAA==.Drimbirt:BAAANQADCgQIBwAAAA==.Drinkmormilk:BAAANQADCgQICAAAAA==.Drogelf:BAAANQADCgYIDQAAAA==.Drogman:BAAANQADCgIIAgAAAA==.',
Du='Dumbledore:BAAANQADCgcIBwABNQAECgEIAQACAAAAAA==.',
['Dá']='Dáwnbringer:BAAANQADCgIIBAAAAA==.',
Eb='Ebullition:BAAANQAECgUIBgAAAA==.',
Ed='Edensfury:BAAANQAECgIIAgAAAA==.',
Ee='Eedani:BAAANQADCgUJCQAAAA==.',
Ei='Eigi:BAAANQAECgcIEQAAAA==.',
El='Eldanon:BAABNQAECoEkAAIMAAgKkSMoAgA+AwAMAAgKkSMoAgA+AwAAAA==.Elementality:BAAANQADCgIIAgAAAA==.Eleyert:BAABNQAECoEeAAISAAkK2COBCQCQAwASAAkK2COBCQCQAwAAAA==.Elistann:BAAANQADCggIEQABNQAECgQIDQACAAAAAA==.Elwe:BAAANQAECgUIEAAAAA==.',
Em='Embaku:BAAANQADCggICAABNQAECggIHwAJAHYTAA==.Emrhakul:BAAANQABCggIEAAAAA==.',
En='Enkidu:BAAANQAECgQIDQAAAA==.Enseth:BAAANQAECgQIDgAAAA==.',
Er='Erakha:BAAANQAECgQIBgAAAA==.Erandria:BAAANQADCgUJBQABNQADCgUIDgACAAAAAA==.',
Eu='Eulogy:BAAANQADCgYICAABNQAFFAUICQAKADQQAA==.',
Ez='Ezerharden:BAAANQABCgEJAQAAAA==.Ezki:BAAANQADCgcIDwABNQAECgQIDQACAAAAAA==.',
Fa='Fairious:BAABNQAECoEdAAIDAAcK9xbUFwAOAgADAAcK9xbUFwAOAgAAAA==.',
Fe='Felcon:BAAANQADCgYICQAAAA==.Felenkeller:BAAANQAECgIIAgABNQAECgkJJgAFAD0lAA==.Fenrirr:BAAANQADCggICAABNQAECgQIDQACAAAAAA==.Fet:BAABNQAECoEeAAMDAAkKlB/gDgB7AgADAAgKXB/gDgB7AgATAAQK2B89RwBgAQAAAA==.',
Fh='Fhatbashtud:BAAANQADCgcIGAAAAA==.',
Fl='Flatline:BAAANQAECgYIDgAAAA==.Flinnt:BAAANQADCgEIAQABNQAECgQIDQACAAAAAA==.',
Fn='Fngusamungus:BAAANQAECgEIAQAAAA==.',
Fo='Folgore:BAAANQADCgUICgAAAA==.Four:BAAANQAECgYIDAAAAA==.',
Fr='Fredwarlock:BAAANQAECgIIAgAAAA==.Frysky:BAAANQAECgUIBgAAAA==.',
Fu='Furiousv:BAAANQADCgUIBQAAAA==.Futz:BAABNQAECoEiAAIUAAYK1yEPQQBCAgAUAAYK1yEPQQBCAgAAAA==.',
Ga='Gahnzul:BAAANQADCgUIBQAAAA==.Gajitbek:BAAANQADCgMIAwAAAA==.Galah:BAAANQAECgYIEAAAAA==.Gardurst:BAAANQAECgUIBQAAAA==.',
Gn='Gnomicide:BAAANQADCggIHwAAAA==.',
Go='Gonesh:BAAANQADCggIEAAAAA==.Gooberpea:BAAANQABCgYIEAAAAA==.Gordoe:BAAANQADCgUICgAAAA==.',
Gr='Graveborne:BAAANQADCgcIDgAAAA==.Gravess:BAAANQADCgUIBQAAAA==.Gravewin:BAAANQADCgQICgABNQADCgYIDwACAAAAAA==.Gravyexpress:BAABNQAECoE9AAIVAAgKQR8HGwCdAgAVAAgKQR8HGwCdAgAAAA==.Grendelheim:BAAANQADCgYIFgAAAA==.Grogar:BAAANQADCgYIDgAAAA==.',
Gu='Gula:BAAANQAECgEIAQABNQAECgIIBAACAAAAAA==.',
Ha='Hadez:BAAANQADCgUIBQAAAA==.Hagrok:BAAANQABCgYICAAAAA==.Hantak:BAAANQADCgMIBgAAAA==.Harmsway:BAAANQADCgcJEQAAAA==.Hathaendron:BAAANQABCgMJAwAAAA==.',
He='Hephaestus:BAAANQAECgQIBAAAAA==.',
Ho='Hocka:BAAANQADCgUIBgAAAA==.Holysmight:BAAANQAECgEIAQAAAA==.Holyumo:BAAANQADCgYIBgAAAA==.Holyyballs:BAAANQAECgUIBgABNQAECgUIDAACAAAAAA==.Howlymandel:BAAANQAECgQIBQABNQAECggIIAAHADwLAA==.Hoytx:BAAANQADCgUIBQAAAA==.',
Hy='Hydraciel:BAAANQAECgYIDgAAAA==.',
['Hì']='Hìroko:BAAANQAECgIIAgAAAA==.',
Ic='Icedemon:BAAANQADCgYICgAAAA==.Icupapi:BAAANQADCggIIAAAAA==.Icynips:BAAANQABCgEIAQAAAA==.',
Im='Im:BAAANQADCgEJAQABNQAECgkJLgADAEskAA==.Imabigman:BAAANQADCgcICAAAAA==.Imaleaf:BAABNQAECoEaAAIHAAgKFgcYVABeAQAHAAgKFgcYVABeAQAAAA==.Imperius:BAAANQAECgEIAQAAAA==.',
In='Insillico:BAAANQADCggICAABNQAECggIHgABAPcTAA==.',
Ip='Iplaydead:BAABNQAECoEeAAMBAAgK9xPjXAA1AgABAAgK9xPjXAA1AgAWAAEKigPDhwAmAAAAAA==.',
Ir='Iroh:BAAANQAECgQIDQAAAA==.',
Is='Ismokeprot:BAAANQADCgMIAwAAAA==.',
Ja='Jacii:BAAANQAECggIBwABNQAECggIGgAPAJcgAA==.Jawnson:BAAANQAECgcIEgAAAA==.',
Je='Jelluz:BAAANQADCgUIBQAAAA==.Jenefer:BAABNQAECoEmAAMEAAkKNxzjJAB5AgAEAAkKIBzjJAB5AgAFAAIK7BRGqAB9AAAAAA==.Jeslartoma:BAAANQADCgEIAQABNQADCgYIDAACAAAAAA==.',
Ji='Jimjimmy:BAAANQADCgcIBwABNQAECgIIAgACAAAAAA==.',
Jo='Jondooz:BAAANQAECgcIBwAAAA==.',
Ka='Kailana:BAAANQAECgEIAQABNQAECggIGQASAC4cAA==.Kailback:BAAANQAECgUIBwABNQAECggIGQASAC4cAA==.Kait:BAABNQAECoEYAAIIAAgKNBKBYAC+AQAIAAgKNBKBYAC+AQAAAA==.Kalcifur:BAABNQAECoEiAAMUAAkKkBq3IwDFAgAUAAkKkBq3IwDFAgAXAAEKHhbPYQA1AAAAAA==.Karin:BAAANQAECgEIAQABNQAECgUIDAACAAAAAA==.Karnelian:BAAANQAECgUIBwABNQAFFAEIAQACAAAAAA==.Karras:BAAANQADCgUIBQAAAA==.Kashisht:BAAANQAECgIIAgAAAA==.Kasstigate:BAAANQAECgYIEAABNQAECgkJJgAEADccAA==.Kastiel:BAAANQAECgYIEAABNQAECgYIEgACAAAAAA==.Katstrider:BAABNQAECoEeAAIBAAgK2BPbXQAyAgABAAgK2BPbXQAyAgAAAA==.Kattarea:BAAANQADCgUJCAABNQAECggIHgABANgTAA==.Kavica:BAAANQAECgYIBgABNQAECgQICwACAAAAAA==.',
Ke='Keldean:BAAANQAECgYIEgAAAA==.Keryka:BAABNQAECoEiAAMPAAkK1yBCGgCSAgAPAAcKjiFCGgCSAgAFAAgKoh3HOwAMAgAAAA==.',
Kh='Khere:BAAANQADCgUICgAAAA==.',
Ki='Kirøs:BAAANQAECgMIAgAAAA==.Kiterisa:BAABNQAECoEaAAIIAAgKQgcViABIAQAIAAgKQgcViABIAQAAAA==.',
Kk='Kkazz:BAAANQADCggICwABNQAECgQIDQACAAAAAA==.',
Ko='Kohn:BAAANQAECgUIBwAAAA==.Kona:BAEANQAECgUIBgAAAA==.Korbusty:BAAANQADCggIDgAAAA==.',
Ku='Kuattieb:BAAANQABCgIIAgAAAA==.',
La='Ladýfinger:BAABNQAECoEbAAMUAAgKVQ9JXQDdAQAUAAgKVQ9JXQDdAQAJAAMKYAi7MQGQAAABNQAECgkJKAAOAF0cAA==.Laisidhiel:BAAANQADCggILAAAAA==.Lateo:BAAANQAECgYJEQAAAA==.Lawz:BAAANQAECgYIDQAAAA==.',
Le='Lelianna:BAAANQADCgYIGAAAAA==.Lemonruss:BAAANQADCggIEQAAAA==.Lexia:BAAANQAECgQIBwAAAA==.',
Li='Libidine:BAAANQADCgQIBAABNQAECgIIBAACAAAAAA==.Liemannin:BAAANQAECgEIAQAAAA==.Lightninghah:BAAANQABCgIIAgAAAA==.Lilturtz:BAAANQADCgUIBQABNQAECgUIEQACAAAAAA==.Linnea:BAAANQADCgcIDQAAAA==.',
Lo='Locksative:BAAANQADCggIHQAAAA==.Longhorn:BAAANQAECgcIEwAAAA==.Lorekesh:BAAANQADCgEJAQABNQAECgcICgACAAAAAA==.Lorriena:BAAANQADCgUIBQAAAA==.Lortpegsalot:BAABNQAECoEnAAIJAAkKlR+9LgDvAgAJAAkKlR+9LgDvAgAAAA==.Lowy:BAAANQAECgIIAgAAAA==.',
Lu='Lucena:BAAANQAECgQIDAAAAA==.Lurg:BAAANQADCgQIBAABNQADCggIHQACAAAAAA==.',
Ly='Lyralana:BAAANQADCgQIBwABNQADCgUIDgACAAAAAA==.',
Ma='Maberu:BAABNQAECoEYAAILAAgKzgoAHQCJAQALAAgKzgoAHQCJAQABNQAECgkJIgAUAJAaAA==.Madamholy:BAAANQAECgUIDAAAAA==.Madamkluck:BAAANQADCgUIBQAAAA==.Maglubiyet:BAAANQAECgEIAQAAAA==.Magnitood:BAAANQAECgQICAAAAA==.Malbjornion:BAAANQAECgMIBQAAAA==.Malphox:BAAANQADCgQICAAAAA==.Manbearcat:BAAANQAECgUIDAAAAA==.Manhole:BAAANQAECgQIDAAAAA==.Markyb:BAAANQADCgYICQAAAA==.Masamura:BAACNQAFFIEIAAMYAAMKBBJ9BwB4AAAQAAIK1xP5OQCiAAAYAAIKfwd9BwB4AAA1AAQKgS4AAxAACQpHG3JQANACABAACQrXGnJQANACABgAAgqoFuIlAJ8AAAAA.Maureanna:BAAANQADCgUIDgAAAA==.',
Me='Mechahuntard:BAAANQADCgEIAQAAAA==.Medanii:BAEBNQAECoEbAAQZAAgKcRDRCwBqAQAZAAYKVRLRCwBqAQAKAAQKlggvsADNAAARAAQKFwoQTgCyAAAAAA==.Melorm:BAAANQAECgQIBQAAAA==.',
Mi='Millizh:BAACNQAFFIEVAAMBAAcK1B/gBADlAQABAAUK4iDgBADlAQAWAAQKfRwqDABRAQA1AAQKgSIAAxYACQpuJl8EAIYDABYACQo+Jl8EAIYDAAEABgrOIhR4APABAAAA.Mirasharu:BAAANQADCgYIFAAAAA==.Mireille:BAAANQADCgYIDQAAAA==.Mitsuri:BAAANQAECggIDwAAAA==.Mitzuky:BAAANQADCgMIAwAAAA==.',
Mo='Mommamoon:BAAANQADCgQIBAABNQAECgcIEAACAAAAAA==.Moonlïght:BAAANQAECgcIEAAAAA==.Morganlefay:BAAANQAECgUICAAAAA==.Morlyn:BAAANQAECgYIDgAAAA==.Morregan:BAAANQAECgUIBgAAAA==.Mousereaper:BAABNQAECoEYAAIaAAgKRA9xKADhAQAaAAgKRA9xKADhAQAAAA==.',
My='Mydnight:BAAANQABCgIIAgAAAA==.Mystìc:BAABNQAECoEZAAQSAAgKLhwCWQDqAQAbAAcKDBn4EQApAgASAAYKXRwCWQDqAQAIAAEKaQqhCgEpAAAAAA==.Mystíc:BAAANQAECgUIBQABNQAECggIGQASAC4cAA==.',
['Má']='Májorrobot:BAABNQAECoEYAAIcAAkK/BqGNwDPAgAcAAkK/BqGNwDPAgAAAA==.',
['Mé']='Ménopáwz:BAAANQAECgIIAwABNQAECgkJJgAFAD0lAA==.',
Na='Namor:BAAANQADCggIEwAAAA==.Nattisca:BAAANQADCgYIDAAAAA==.',
Ne='Nessà:BAAANQAECgIIBAAAAA==.Neveenn:BAABNQAECoErAAIGAAgKjBtQEwCSAgAGAAgKjBtQEwCSAgAAAA==.',
Ni='Nirith:BAAANQADCgYIEwAAAA==.Nivmizet:BAAANQABCgcICgAAAA==.',
No='Nohatcat:BAAANQADCggIEgABNQAECgUIEQACAAAAAA==.',
['Nâ']='Nâmii:BAAANQAECgMIAwAAAA==.',
['Nè']='Nèzukõ:BAAANQAECgYIEQAAAA==.',
Ob='Obata:BAAANQAECgEIAQAAAA==.',
Oc='Octavius:BAAANQADCggJDQABNQAECgIIAgACAAAAAA==.',
Od='Odi:BAAANQADCgQIBAAAAA==.',
Oj='Ojore:BAEANQAECgUIEAAAAA==.Ojoverde:BAABNQAECoEmAAIdAAkKihHBXAAfAgAdAAkKihHBXAAfAgAAAA==.',
On='Onizuka:BAAANQADCgEIAQABNQADCgcICQACAAAAAA==.Onside:BAAANQAECgYICgABNQAECgkJHQAeAJkdAA==.',
Op='Ophillã:BAAANQAECgEIBQABNQAECgIIBAACAAAAAA==.',
Or='Ordenn:BAAANQADCgQICAABNQAECgkJHgADAJQfAA==.Orian:BAAANQADCgQIBwAAAA==.',
Oz='Ozz:BAABNQAECoEZAAIeAAgK2w/fJwCvAQAeAAgK2w/fJwCvAQAAAA==.Ozzerker:BAAANQADCgEIAQAAAA==.Ozzullr:BAAANQAECgcIDgAAAA==.',
Pa='Painbreak:BAAANQADCgEIAQABNQAECggIGAAOAIsdAA==.Pajamas:BAAANQAECgEJAQABNQAECgUIDwACAAAAAA==.Pallanquin:BAAANQADCgYIDAAAAA==.Papichili:BAAANQAECgIIAwAAAA==.Pashnir:BAAANQADCgcICQAAAA==.',
Pe='Peachey:BAAANQAECgYIDgAAAA==.Peaker:BAAANQAECgMIAwAAAA==.Peakra:BAAANQAECgcIDAAAAA==.',
Ph='Phoênix:BAAANQADCgMIAwAAAA==.',
Pi='Pigas:BAABNQAECoEeAAIeAAgKhBOhIQDwAQAeAAgKhBOhIQDwAQAAAA==.',
Pr='Prestoresto:BAAANQADCgYIDwAAAA==.',
Ps='Psychosix:BAAANQAECgcICwAAAA==.',
Qu='Quinberos:BAAANQAECgQIBwAAAA==.',
Ra='Racey:BAAANQADCggICAAAAA==.Raiistlin:BAAANQADCgYIBgABNQAECgQIDQACAAAAAA==.Ramdel:BAAANQAECgIIAgABNQAECggIHgAfAGIcAA==.Ramstrider:BAABNQAECoEeAAMfAAgKYhz7AwCSAgAfAAgKYhz7AwCSAgABAAEK9gdSOgE4AAAAAA==.Ranch:BAAANQADCgcICQAAAA==.Rapture:BAAANQAECgcIEwAAAA==.Ravec:BAAANQABCgQJBQAAAA==.',
Re='Rengell:BAAANQAECgQICQABNQAECggIIAAHADwLAA==.Reptiliano:BAAANQAECggIAwAAAA==.',
Rh='Rheagall:BAABNQAECoEaAAIbAAkKRhngCQDDAgAbAAkKRhngCQDDAgAAAA==.Rhodetta:BAABNQAECoEWAAIKAAkK/xVTLwCKAgAKAAkK/xVTLwCKAgAAAA==.',
Ri='Rizepriest:BAAANQADCgIIAgABNQAECgUICAACAAAAAA==.Rizerage:BAAANQAECgUICAAAAA==.',
Ro='Roaraxe:BAAANQADCgYIBgABNQAECgIIAgACAAAAAA==.Rowena:BAABNQAECoEzAAIHAAgKaRaKMQAwAgAHAAgKaRaKMQAwAgAAAA==.Rowynna:BAAANQAECgMIAwABNQAECgQIBwACAAAAAA==.Roxy:BAAANQADCgYIBgAAAA==.Roxymonk:BAAANQADCgYIBgAAAA==.Royalviaman:BAAANQADCgQIBwAAAA==.',
Ry='Ryz:BAAANQADCggICAAAAA==.Ryztkmtchrch:BAABNQAECoEoAAQKAAkKhhtAJwCwAgAKAAkKhhtAJwCwAgAZAAcKww1CCwB3AQARAAUKJg95PwAJAQAAAA==.',
['Rå']='Råti:BAAANQADCgUIBQAAAA==.',
Sa='Sacdk:BAAANQAECgQIBwAAAA==.Safaria:BAAANQAECgQIBAABNQAECgUICwACAAAAAA==.Saloenus:BAAANQAECgYICgAAAA==.Sarlyssa:BAAANQABCgYICgAAAA==.Saucehoss:BAABNQAECoEjAAQNAAkKlRwQAwC5AgANAAkKlRwQAwC5AgAdAAMKkhQ86wDEAAAMAAMK5Q0TSACdAAAAAA==.Saucymac:BAAANQAECgYIBQAAAA==.',
Sc='Scofflaw:BAAANQADCgEIAQABNQAECgQIBAACAAAAAA==.Scubasteve:BAAANQADCgUICgAAAA==.',
Se='Sefi:BAABNQAECoEXAAMJAAcKmRNvuwBtAQAJAAYKRRNvuwBtAQAXAAQKjg3lRAC0AAAAAA==.Semirrhage:BAAANQADCgMIAwAAAA==.',
Sh='Shadowflame:BAAANQAECgUIDwAAAA==.Shammygoat:BAAANQAECgUIEQAAAA==.Shaqattack:BAABNQAECoEdAAIeAAkKmR0hEADHAgAeAAkKmR0hEADHAgAAAA==.Shaqattaq:BAAANQAECgcICQABNQAECgkJHQAeAJkdAA==.Sharktide:BAABNQAECoEYAAIIAAcKwBq8TwD5AQAIAAcKwBq8TwD5AQAAAA==.Shawnella:BAABNQAECoEaAAMeAAgK/xi2IAD6AQAeAAcKeBe2IAD6AQALAAIKTQfkPQBZAAAAAA==.Shenlune:BAAANQAECgYIDQAAAA==.Sheutka:BAAANQADCggIHwAAAA==.Shiggles:BAAANQAECgEIAQAAAA==.Shinaie:BAAANQAECgUIDAAAAA==.Shocknrollz:BAAANQAECgQIDAAAAA==.Shogún:BAABNQAECoEWAAIEAAcKPB8AJQB4AgAEAAcKPB8AJQB4AgABNQAECggIEQACAAAAAA==.Shtylez:BAAANQAECgIIAgABNQAECggIHgABAPcTAA==.',
Si='Silntwolf:BAAANQABCgQIBAAAAA==.Silpion:BAAANQAECgUICAAAAA==.Silth:BAAANQADCggIFAAAAA==.Sinariel:BAABNQAECoEbAAILAAgKhBW4EQA3AgALAAgKhBW4EQA3AgAAAA==.Sirdank:BAAANQAECgEIAgAAAA==.',
Sk='Skarlate:BAAANQADCgYIBgAAAA==.Skâld:BAEANQADCgYICwAAAA==.',
Sl='Sliko:BAABNQAECoElAAIJAAgKdRMRggDzAQAJAAgKdRMRggDzAQAAAA==.',
Sm='Smmoke:BAABNQAECoEaAAIBAAgKuxe2TQBeAgABAAgKuxe2TQBeAgAAAA==.',
Sn='Sneekypally:BAAANQAECgQICAAAAA==.Snowballs:BAAANQAECgUIDAAAAA==.',
So='Softhorn:BAAANQABCgUIBQAAAA==.Sorenreign:BAAANQADCgYIBgAAAA==.Sothh:BAAANQADCggICAABNQAECgQIDQACAAAAAA==.Soull:BAABNQAECoEoAAIGAAkK7yFxAgCcAwAGAAkK7yFxAgCcAwAAAA==.Soulsmash:BAAANQADCggIDAAAAA==.',
Sp='Spacebabe:BAAANQADCgEIAQABNQAECgUIDAACAAAAAA==.Spacestepdad:BAAANQAECgUIDAAAAA==.Sparkie:BAAANQADCggIHgAAAA==.Spriggan:BAAANQAECgUIBQAAAA==.',
Sq='Squashfoot:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.',
St='Starface:BAABNQAECoEoAAIOAAkKXRzqBwDOAgAOAAkKXRzqBwDOAgAAAA==.Stargoose:BAAANQAECgUICAABNQAECgkJKAAOAF0cAA==.Steelytree:BAAANQADCgQIBwAAAA==.Stellaria:BAAANQAECgQIDAAAAA==.Steris:BAAANQADCggIFAABNQADCggIHQACAAAAAA==.Steverogers:BAAANQAECgMICAABNQAECgkJJgAFAD0lAA==.Stocktonrush:BAABNQAECoEmAAMFAAkKPSXRDQA1AwAFAAkKOyXRDQA1AwAEAAEKnyOypQBiAAAAAA==.Stonedhenge:BAAANQABCgQIBAAAAA==.Sturmx:BAABNQAECoEaAAIVAAgK1xYUKwAeAgAVAAgK1xYUKwAeAgAAAA==.',
Su='Subedei:BAABNQAECoEcAAQFAAkKYxojPAAKAgAFAAgKGhojPAAKAgAPAAYKORT0PwCEAQAEAAEK0Q5vuAA4AAAAAA==.Summerseve:BAAANQAECgMIAwAAAA==.Sunderhorn:BAAANQADCggIHwAAAA==.Suriaa:BAABNQAECoEoAAMTAAkK8hOSHwBaAgATAAkK8hOSHwBaAgAgAAQKFAlbEgDIAAAAAA==.',
Sv='Svictis:BAAANQAECgUICAAAAA==.Svictiss:BAAANQADCgUICQAAAA==.',
Sw='Swami:BAAANQAECgQIBAAAAA==.',
Ta='Talila:BAAANQAECgQIDQAAAA==.Taniss:BAAANQADCggIDgABNQAECgQIDQACAAAAAA==.Taurdeth:BAAANQAECgYICQABNQAECgkJFgAKAP8VAA==.',
Te='Terrya:BAAANQAECgUIBQAAAA==.Teryail:BAAANQADCgUIBQAAAA==.',
Th='Thaqdaddy:BAAANQADCgYIBgABNQAECgkJGgAEAKwRAA==.Thaqknight:BAABNQAECoEaAAIEAAkKrBHxPwDfAQAEAAkKrBHxPwDfAQAAAA==.Therylnn:BAAANQADCggICAAAAA==.Thesthamenth:BAAANQADCgYIBgAAAA==.Thily:BAAANQADCgIIAgAAAA==.Thorwallen:BAAANQADCggIFAABNQAECgQIDQACAAAAAA==.Thror:BAAANQAECgEIAQAAAA==.',
Ti='Tiac:BAAANQAECgEIAQAAAA==.Tiergyll:BAAANQABCgIIBAAAAA==.Tirithor:BAABNQAECoEfAAIJAAgKdhMihADtAQAJAAgKdhMihADtAQAAAA==.',
To='Tockell:BAAANQADCgQIBwAAAA==.Togala:BAAANQADCgUIBwABNQAECgQIBgACAAAAAA==.Toothless:BAAANQAECgEIAQAAAA==.Torbin:BAAANQAECgUIBwAAAA==.Touchmywave:BAAANQADCgcIDgABNQAECgkJLAABALAYAA==.',
Tr='Tryjinks:BAAANQAECgcIDwAAAA==.',
Ts='Tsunameh:BAAANQAECgQIBAABNQAECggIHgABAPcTAA==.',
Tu='Tusky:BAAANQADCgYIBgAAAA==.',
Tw='Twohandtug:BAAANQADCgcICwAAAA==.',
Ty='Tykahndrius:BAABNQAECoEWAAMXAAgK/BU7HQDVAQAXAAcKhBc7HQDVAQAJAAMKngrwJgGkAAABNQAECggIHgABAPcTAA==.Tylîus:BAAANQAECgcIDwAAAA==.Tyredelsia:BAAANQABCggIFAAAAA==.',
['Tö']='Töph:BAAANQADCgYIBgABNQAECgIIBAACAAAAAA==.',
['Tú']='Túsk:BAAANQADCgYIBwAAAA==.',
['Tý']='Týlius:BAAANQAECgMIBAABNQAECgcIDwACAAAAAA==.',
Uk='Ukika:BAAANQAECgEIAgABNQAECgQIBgACAAAAAA==.',
Us='Useriòs:BAAANQADCgIIAwAAAA==.',
Ut='Uthilon:BAABNQAECoEaAAIXAAgKnB8XDQCoAgAXAAgKnB8XDQCoAgAAAA==.',
Va='Valdare:BAAANQAECgQIDQAAAA==.Validorn:BAAANQAECgEIAQAAAA==.',
Ve='Vedillian:BAAANQAECgEJAQAAAA==.Velduar:BAAANQADCgQIBAAAAA==.',
Vi='Victorr:BAAANQAECgEIAQAAAA==.Viktorius:BAAANQADCgQIBAAAAA==.Vixious:BAAANQADCgUIAwAAAA==.Vizigoth:BAABNQAECoEZAAQdAAcKIA6+pgBWAQAdAAYK8g2+pgBWAQANAAEK7QvUKwA1AAAMAAEKJgrPcwA0AAAAAA==.',
Vo='Vordell:BAAANQAECgQICQABNQAECgkJFgAKAP8VAA==.Voyana:BAAANQAECgUICwAAAA==.Voz:BAAANQADCgUIBQAAAA==.',
Vy='Vydragon:BAACNQAFFIEIAAIhAAMKOAnNDgDXAAAhAAMKOAnNDgDXAAA1AAQKgRkABCEACQpEDVAaAAMCACEACQpEDVAaAAMCACIABQoLElkfAEMBACMAAwozFB8TANIAAAE1AAQKCQkpABAAMh8A.Vymage:BAABNQAECoEpAAMQAAkKMh+jSADiAgAQAAkKMh+jSADiAgAkAAMK8BRrBgDJAAAAAA==.',
['Vá']='Válidüs:BAACNQAFFIEPAAIKAAUKWwvkDgB8AQAKAAUKWwvkDgB8AQA1AAQKgS0AAgoACQqJIs4OADoDAAoACQqJIs4OADoDAAAA.',
['Vã']='Vãsh:BAAANQAECgIIAgAAAA==.',
Wa='Wabbitseason:BAAANQADCgIIAgABNQAECgUIDAACAAAAAA==.Wabìsuke:BAAANQADCggIFQAAAA==.Waterlogged:BAAANQADCgQJCgAAAA==.Waterloo:BAAANQADCgYIDgAAAA==.',
Wi='Wizpigas:BAAANQADCgcIDQABNQAECggIHgAeAIQTAA==.',
['Wì']='Wìccka:BAAANQADCgUIBQAAAA==.',
Xi='Xi:BAAANQAECgMIAwAAAA==.Xifan:BAAANQAFFAEIAQAAAA==.',
Yd='Yd:BAAANQAECgQIBAABNQAECgkJLgADAEskAA==.',
Yg='Yggdrasill:BAAANQABCgUICAAAAA==.',
Yi='Yingpi:BAAANQABCgIIAgAAAA==.',
Yo='Yodaa:BAAANQADCggICwABNQAECgQIDQACAAAAAA==.',
Ys='Ys:BAAANQAECgQIBAABNQAECgkJLgADAEskAA==.',
Yt='Yt:BAAANQAECgQICgABNQAECgkJLgADAEskAA==.',
Yw='Ywontudie:BAAANQADCgQIBgAAAA==.',
Yz='Yz:BAABNQAECoEuAAMDAAkKSySdAQCqAwADAAkKSySdAQCqAwATAAIKUxtdcACaAAAAAA==.',
Za='Zashawa:BAAANQADCgYIEQAAAA==.',
Ze='Zenithgrey:BAAANQAECgcIEwAAAA==.',
Zl='Zluco:BAABNQAECoEqAAMbAAkKHB+HBgAOAwAbAAkKHB+HBgAOAwAIAAYKeRwAawCcAQAAAA==.',
Zo='Zoomy:BAAANQADCgQIBAAAAA==.',
Zy='Zypherion:BAAANQADCgYIDAAAAA==.',
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
