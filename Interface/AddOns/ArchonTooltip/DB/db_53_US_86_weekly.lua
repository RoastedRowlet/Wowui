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

local lookup = {'Hunter-BeastMastery','Unknown-Unknown','Mage-Arcane','Rogue-Subtlety','DeathKnight-Blood','DeathKnight-Unholy','Paladin-Retribution','Mage-Frost','Druid-Restoration','Druid-Balance','Shaman-Restoration','Priest-Holy','Shaman-Elemental','Monk-Mistweaver','Warlock-Destruction','Warlock-Affliction','Warrior-Arms','Druid-Guardian','DeathKnight-Frost','Monk-Windwalker','Priest-Shadow','Evoker-Devastation','Priest-Discipline','Rogue-Assassination','Paladin-Holy','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Marksmanship','Shaman-Enhancement','Paladin-Protection','Warlock-Demonology','Hunter-Survival','Rogue-Outlaw','DemonHunter-Vengeance','Evoker-Preservation','Evoker-Augmentation','Mage-Fire',}
local provider = {region='US',realm="Eldre'Thalas",name='US',type='weekly',zone=53,date='2026-10-13',data={Ad='Adesira:BAAANQAECgQIBAAAAA==.Adrastus:BAAANQAECgMIAwABNQAECgkJJQABAAYVAA==.',
Ae='Aeslin:BAAANQADCgYJBgABNQAECgEIAQACAAAAAA==.',
Ah='Ahn:BAAANQADCggIEAAAAA==.Ahylin:BAAANQADCgcIDAAAAA==.',
Ai='Ainslie:BAAANQAECgQICwAAAA==.',
Al='Alerana:BAAANQADCggIGAAAAA==.Altria:BAAANQADCgUICQAAAA==.',
An='An:BAABNQAECn8YAAIDAAYKYRyD0QDhAQADAAYKYRyD0QDhAQABNQAFFAEIBQAEAAAAAA==.Anarose:BAAANQAECgUIEQAAAA==.Antityk:BAAANQAECgQICgABNQAECgkJJQABAAYVAA==.',
Ar='Aragorn:BAAANQADCgQIBQAAAA==.Arahant:BAAANQAECgIIAgAAAA==.Aretas:BAABNQAECn8dAAMFAAgK5B4eGQDiAgAFAAgK5B4eGQDiAgAGAAEK4Q1T4AAxAAAAAA==.Armadian:BAAANQAECgQICAAAAA==.Arrianne:BAAANQADCgYIBgAAAA==.Arriånna:BAAANQADCgcIEwAAAA==.Artemist:BAABNQAECn8UAAIHAAYKqg0r8gAyAQAHAAYKqg0r8gAyAQAAAA==.',
As='Asifa:BAAANQAECgEIAQAAAA==.',
At='Atherion:BAABNQAECn8dAAIIAAgKEhH0CgATAgAIAAgKEhH0CgATAgAAAA==.Attackroot:BAAANQAECgUIBgABNQAECgUIEAACAAAAAA==.',
Au='Aurakk:BAAANQADCgYIEQABNQAECgQIEQACAAAAAA==.',
Av='Avelin:BAAANQADCgUIBQAAAA==.Avranarada:BAABNQAECn8eAAMJAAgKkhfBHwApAgAJAAgKkhfBHwApAgAKAAcKuBi0QQDuAQAAAA==.Avril:BAAANQAECgEIAQAAAA==.',
Az='Azkara:BAACNQAFFH8HAAILAAMKSw6oGQDJAAALAAMKSw6oGQDJAAA1AAQKfycAAgsACQpXHv0iANkCAAsACQpXHv0iANkCAAAA.Azung:BAABNQAECn8lAAIHAAkKzx6/KgAaAwAHAAkKzx6/KgAaAwAAAA==.',
Ba='Babaisyaga:BAACNQAFFH8NAAIBAAMK6CCnFQAKAQABAAMK6CCnFQAKAQA1AAQKfzcAAgEACQpnI9AMAHcDAAEACQpnI9AMAHcDAAAA.Baka:BAAANQAECgYICQAAAA==.Balinse:BAAANQAECgYIEgABNQAECgcIEQACAAAAAA==.Balystix:BAAANQADCggICAAAAA==.Barb:BAAANQAECgEIAQAAAA==.Barrelrollin:BAAANQADCgYIDwAAAA==.',
Be='Beastfodays:BAACNQAFFH8GAAIBAAMKrhS2HADIAAABAAMKrhS2HADIAAA1AAQKfy8AAgEACQoJGIhCAKECAAEACQoJGIhCAKECAAAA.Bethlahammer:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.',
Bi='Billcritin:BAAANQAECgcIDQAAAA==.',
Bl='Blackleaf:BAAANQADCgQIBwAAAA==.Blawyke:BAAANQAECgUIBwABNQAFFAIIAgACAAAAAA==.Bless:BAAANQADCgYJBgABNQADCgYIBgACAAAAAA==.Blizzcon:BAACNQAFFH8NAAIMAAUKKxQzDwCaAQAMAAUKKxQzDwCaAQA1AAQKfzcAAgwACQqEIy0JAHgDAAwACQqEIy0JAHgDAAAA.Bloodsurge:BAAANQADCgQJAwAAAA==.Blushies:BAABNQAECn8WAAMNAAUKEB+JfACqAQANAAUKEB+JfACqAQALAAMK8xAf4QCjAAAAAA==.',
Bo='Boltzfodayz:BAAANQAECgEIAQAAAA==.Bonerslap:BAAANQADCgEIAQAAAA==.Boone:BAAANQADCgMIAwAAAA==.Borrgar:BAAANQAECgQIEQAAAA==.',
Br='Brackle:BAABNQAECn8aAAIBAAgKXh1XQQClAgABAAgKXh1XQQClAgAAAA==.Bracori:BAACNQAFFH8GAAIOAAMKkgoOCADMAAAOAAMKkgoOCADMAAA1AAQKfyoAAg4ACQp0EZsXAAACAA4ACQp0EZsXAAACAAAA.Brandywynne:BAABNQAECn8eAAIBAAkK8A9TZABKAgABAAkK8A9TZABKAgAAAA==.Bretcha:BAAANQADCgQIBAABNQAECgQIBgACAAAAAA==.Brick:BAABNQAECn8hAAIEAAkK7xZ1DQCdAgAEAAkK7xZ1DQCdAgAAAA==.Brightfame:BAABNQAECn8pAAMPAAgKxRUyGACqAQAPAAYK0xQyGACqAQAQAAQKlBeyEQAsAQAAAA==.Bronny:BAABNQAECn8XAAIRAAcKaQ67tgCOAQARAAcKaQ67tgCOAQAAAA==.Brônwyn:BAAANQADCgQIBAAAAA==.',
Bu='Buffshagwell:BAABNQAECn8lAAIHAAgKsxi4VwCMAgAHAAgKsxi4VwCMAgAAAA==.Bullrush:BAAANQADCgUIBQAAAA==.Butterbllz:BAABNQAECn8lAAIHAAkKCBx0XAB/AgAHAAkKCBx0XAB/AgAAAA==.',
Ca='Calypsio:BAAANQADCgQIBAABNQAECgMIAwACAAAAAA==.Camany:BAABNQAECn8fAAIBAAgKExHHdQAhAgABAAgKExHHdQAhAgAAAA==.Captinkrunch:BAAANQADCgEJAQAAAA==.Caretakerz:BAABNQAECn8fAAISAAgKAx6JCwCuAgASAAgKAx6JCwCuAgAAAA==.Cartus:BAAANQAECgUICAABNQAECgYIEgACAAAAAA==.Cayin:BAABNQAECn8cAAIFAAkKSiCQEwANAwAFAAkKSiCQEwANAwABNQABCgYICwACAAAAAA==.',
Ch='Chanta:BAAANQABCgYIBwAAAA==.Chanyeol:BAAANQAECgIIAwAAAA==.Chemoshh:BAAANQADCggIBgABNQAECgQIEQACAAAAAA==.',
Cl='Clamshell:BAABNQAECn8eAAMTAAgKyCELGwCvAgATAAgKyCELGwCvAgAFAAUKwRjiYQBnAQAAAA==.Claudette:BAAANQAECgcICgAAAA==.Clayier:BAAANQADCgYIDAAAAA==.',
Cn='Cntendr:BAAANQADCgUICAAAAA==.',
Co='Codenike:BAABNQAECn8ZAAIUAAcKFhobJAAAAgAUAAcKFhobJAAAAgAAAA==.Copenzen:BAAANQAECgQIBgAAAA==.Corelheals:BAAANQAECgQIBwAAAA==.Covertyqt:BAABNQAECn8eAAIDAAgKRxxxdQCTAgADAAgKRxxxdQCTAgAAAA==.Coyote:BAAANQABCgUIBgAAAA==.',
Cp='Cptnhuman:BAABNQAECn8eAAIGAAgK2h/hJgCeAgAGAAgK2h/hJgCeAgAAAA==.',
Cr='Cromie:BAAANQADCggIFQAAAA==.Crosed:BAAANQADCgQIBAAAAA==.',
Cs='Cshunter:BAAANQADCgYIBwAAAA==.',
Cu='Cubcakes:BAAANQADCggIBQAAAA==.',
['Cõ']='Cõrpses:BAEANQAECgYIEQABNQAECgUICgACAAAAAA==.',
Da='Daboof:BAAANQADCgYIGgAAAA==.Daemandred:BAAANQADCgMIAwAAAA==.Daggere:BAAANQADCggIKAAAAA==.Danke:BAAANQADCgYIHgAAAA==.Dankz:BAAANQAECgEIAgAAAA==.Darkenmicky:BAAANQADCgcIEwAAAA==.Darkmickyz:BAAANQAECgYIEgAAAA==.Darthbobula:BAABNQAFFH8GAAIHAAMKBgfMHgCnAAAHAAMKBgfMHgCnAAAAAA==.Dayloc:BAAANQAECgUICAAAAA==.',
De='Deataria:BAABNQAECn8eAAIJAAYKOx0RJgDuAQAJAAYKOx0RJgDuAQAAAA==.Deawin:BAAANQADCgQIBAABNQADCgYIDwACAAAAAA==.Delilia:BAEANQAECggIBQABNQAECggIEAACAAAAAA==.Delryth:BAAANQADCgYIBQAAAA==.Demonikk:BAAANQAECgUICwABNQAECgkJJQABAAYVAA==.Demontyk:BAAANQAECgQIBgABNQAECgkJJQABAAYVAA==.Desception:BAAANQADCgQIBwAAAA==.',
Di='Diadochi:BAAANQAECgQJBQAAAA==.Dieguerta:BAAANQADCgEJAQAAAA==.',
Dl='Dl:BAABNQAECn8lAAIVAAkKIxp4GQCAAgAVAAkKIxp4GQCAAgAAAA==.',
Dr='Drakkarr:BAAANQADCgYIBwAAAA==.Drazhoath:BAAANQAECgUIDQAAAA==.Drdrill:BAAANQADCgYIBgAAAA==.Drimbirt:BAAANQADCgQIBwAAAA==.Drinkmormilk:BAAANQAECgIIAgAAAA==.Drogelf:BAAANQADCgYIEgAAAA==.Drogman:BAAANQADCgIIAgAAAA==.',
Du='Dumbledore:BAAANQADCgcIBwABNQAECgEIAQACAAAAAA==.',
['Dá']='Dáwnbringer:BAAANQADCgIIBAAAAA==.',
Eb='Ebullition:BAAANQAECgYIBwAAAA==.',
Ed='Edensfury:BAAANQAECgIIAgAAAA==.',
Ee='Eedani:BAAANQADCgUJCQAAAA==.',
Ei='Eigi:BAABNQAECn8XAAIBAAgKchawbQA0AgABAAgKchawbQA0AgAAAA==.',
El='Eldanon:BAABNQAECn8sAAIPAAkKfCEgAQCQAwAPAAkKfCEgAQCQAwAAAA==.Elementality:BAAANQADCgIIAgAAAA==.Eleyert:BAACNQAFFH8IAAINAAUKNRriCwCpAQANAAUKNRriCwCpAQA1AAQKfyEAAg0ACQo2I28MAIIDAA0ACQo2I28MAIIDAAAA.Elistann:BAAANQADCggIEQABNQAECgQIEQACAAAAAA==.Elwe:BAABNQAECn8aAAIMAAcKChVrcQDEAQAMAAcKChVrcQDEAQAAAA==.',
Em='Embaku:BAAANQADCggICAABNQAECgkJKAAHALEVAA==.Emiri:BAAANQAECgQIBAAAAA==.Emrhakul:BAAANQABCggIFQAAAA==.',
En='Enkidu:BAAANQAECgQIEQAAAA==.Enseth:BAABNQAECn8ZAAIWAAcKQglOHQB3AQAWAAcKQglOHQB3AQAAAA==.',
Er='Erakha:BAAANQAECgQIBgAAAA==.Erandria:BAAANQADCgUICQABNQAECgQIBAACAAAAAA==.',
Eu='Eulogy:BAAANQADCgYICAABNQAFFAUIDQAMACsUAA==.',
Ex='Exileosis:BAEBNQAECn8YAAQMAAkK1CGECgBsAwAMAAkK1CGECgBsAwAXAAYKHRjZCwB+AQAVAAEKgAKnkQAVAAABNQAECgkKGAAMANQhAA==.',
Ez='Ezerharden:BAAANQABCgEJAQAAAA==.Ezki:BAAANQADCggIFwABNQAECgQIEQACAAAAAA==.',
Fa='Fairious:BAABNQAECn8kAAIEAAgKUhfaEwBJAgAEAAgKUhfaEwBJAgAAAA==.',
Fe='Felcon:BAAANQADCgYICQAAAA==.Felenkeller:BAAANQAECgIIBAABNQAFFAUIBgAGALMSAA==.Fenrirr:BAAANQADCggICAABNQAECgQIEQACAAAAAA==.Fet:BAABNQAECn8gAAMEAAkK5B9ZEQBpAgAEAAgKDR5ZEQBpAgAYAAUKyx7ERgClAQAAAA==.',
Fh='Fhatbashtud:BAAANQAECgEIAQAAAA==.',
Fl='Flatline:BAABNQAECn8YAAIXAAcK5hfRBwDxAQAXAAcK5hfRBwDxAQAAAA==.Flinnt:BAAANQADCgMIBAABNQAECgQIEQACAAAAAA==.',
Fn='Fngusamungus:BAAANQAECgEIAQAAAA==.',
Fo='Folgore:BAAANQAECgEIAQAAAA==.Four:BAAANQAECgYIEAAAAA==.',
Fr='Fredwarlock:BAAANQAECgUIBwAAAA==.Frysky:BAAANQAECgYIDAAAAA==.',
Fu='Furiousv:BAAANQADCgUIBQAAAA==.Futz:BAABNQAECn8pAAIZAAgKXCCrHQD6AgAZAAgKXCCrHQD6AgAAAA==.',
Ga='Gahnzul:BAAANQADCgUICgAAAA==.Gajitbek:BAAANQADCgMIAwAAAA==.Galah:BAAANQAECgYIEAAAAA==.Gardurst:BAABNQAECn8XAAINAAkK6BbmQQBrAgANAAkK6BbmQQBrAgAAAA==.',
Gn='Gnomicide:BAAANQAECgIIAgAAAA==.',
Go='Gonesh:BAAANQADCggIEAAAAA==.Gooberpea:BAAANQABCgYIEAAAAA==.Gordoe:BAAANQADCgUICgAAAA==.',
Gr='Graveborne:BAAANQADCgcIDgAAAA==.Gravess:BAAANQADCgUIBQAAAA==.Gravewin:BAAANQADCgQICgABNQADCgYIDwACAAAAAA==.Gravyexpress:BAABNQAECn9OAAMaAAkKch3SFgDiAgAaAAkKUB3SFgDiAgAbAAUKmhX9PABbAQAAAA==.Grendelheim:BAAANQADCgYIGAAAAA==.Grogar:BAAANQADCgcIEAAAAA==.',
Gu='Gula:BAAANQAECgEIAQABNQAECgQICAACAAAAAA==.',
Ha='Hadez:BAAANQADCgUIBQAAAA==.Hagrok:BAAANQABCgYICAAAAA==.Hantak:BAAANQADCgMIBgAAAA==.Harmsway:BAAANQADCgcJEQAAAA==.Hathaendron:BAAANQABCgMJAwAAAA==.',
He='Hephaestus:BAAANQAECgQICAAAAA==.',
Ho='Hocka:BAAANQADCgUIBgAAAA==.Holysmight:BAAANQAECgEIAQAAAA==.Holyumo:BAAANQADCgYIBgAAAA==.Holyyballs:BAAANQAECgUIBgABNQAECgYIEgACAAAAAA==.Howlymandel:BAAANQAECgQIBQABNQAECgQICQACAAAAAA==.Hoytx:BAAANQADCgUIBQAAAA==.',
Hy='Hydraciel:BAAANQAECgYIDgAAAA==.',
['Hì']='Hìroko:BAAANQAECgUIBwAAAA==.',
Ic='Icedemon:BAAANQAECgQIBAAAAA==.Icupapi:BAAANQADCggIKwAAAA==.Icynips:BAAANQABCgEIAQAAAA==.',
Im='Im:BAAANQADCgEJAQABNQAFFAEIBQAEAAAAAA==.Imabigman:BAAANQADCgcICAAAAA==.Imaleaf:BAABNQAECn8aAAIKAAgKMQYHXQBZAQAKAAgKMQYHXQBZAQAAAA==.Imperius:BAAANQAECgEIAQAAAA==.',
In='Insillico:BAAANQAECgEIAQABNQAECgkJJQABAAYVAA==.',
Ip='Iplaydead:BAABNQAECn8lAAMBAAkKBhW7TgCAAgABAAkKBhW7TgCAAgAcAAEKAAB0mAAmAAAAAA==.',
Ir='Iroh:BAAANQAECgYIEwAAAA==.',
Is='Ismokeprot:BAAANQADCgMIAwAAAA==.',
Ja='Jacii:BAAANQAECggIBwABNQAECggIHgATAMghAA==.Jawnson:BAAANQAECgcIEgAAAA==.',
Je='Jelluz:BAAANQADCgUIBQAAAA==.Jenefer:BAACNQAFFH8GAAIFAAMKyxeBGQDNAAAFAAMKyxeBGQDNAAA1AAQKfykAAwUACQppHAUpAHcCAAUACQpLHAUpAHcCAAYAAgrsFDy2AH0AAAAA.Jeslartoma:BAAANQADCgEIAQABNQADCgYIDAACAAAAAA==.',
Ji='Jimjimmy:BAAANQADCgcIBwABNQAECgIIAgACAAAAAA==.',
Jo='Jondooz:BAAANQAECgcIBwAAAA==.',
Ka='Kailana:BAAANQAECgEIAgABNQAECgkJIAAdAFMaAA==.Kailback:BAAANQAECgYICQABNQAECgkJIAAdAFMaAA==.Kait:BAABNQAECn8cAAILAAgK1hI+bADDAQALAAgK1hI+bADDAQAAAA==.Kalcifur:BAACNQAFFH8HAAMZAAMK/hckFgD4AAAZAAMK/hckFgD4AAAeAAEKGgykEgA2AAA1AAQKfycAAxkACQr+GtsnAMcCABkACQr+GtsnAMcCAB4AAQoeFmxuADEAAAAA.Karin:BAAANQAECgIIAwABNQAECgYIEgACAAAAAA==.Karnelian:BAAANQAECgYICgABNQAFFAEIAQACAAAAAA==.Karras:BAAANQADCgUIBQAAAA==.Kashisht:BAAANQAECgIIAgAAAA==.Kasstigate:BAABNQAECn8ZAAIRAAgKKRXxcwA1AgARAAgKKRXxcwA1AgABNQAFFAMIBgAFAMsXAA==.Kastiel:BAAANQAECgcIEQAAAA==.Katstrider:BAABNQAECn8eAAIBAAgKTxTzcQAqAgABAAgKTxTzcQAqAgAAAA==.Kattarea:BAAANQADCgUJCAABNQAECggIHgABAE8UAA==.Kavica:BAAANQAECgYIBgABNQAECgUIDQACAAAAAA==.',
Ke='Keldean:BAAANQAECgcIEwAAAA==.Keryka:BAACNQAFFH8HAAMTAAMKUCDeDAAIAQATAAMKUCDeDAAIAQAGAAEKZRL4IABHAAA1AAQKfykAAxMACQrUIWwKAEUDABMACArnI2wKAEUDAAYACArMG3FEAAQCAAAA.',
Kh='Khere:BAAANQADCgUICgAAAA==.',
Ki='Kirøs:BAAANQAECgMIAwAAAA==.Kiterisa:BAABNQAECn8eAAILAAgKXwdHmABGAQALAAgKXwdHmABGAQAAAA==.',
Kk='Kkazz:BAAANQADCggICwABNQAECgQIEQACAAAAAA==.',
Ko='Kohn:BAAANQAECgUIBwAAAA==.Kona:BAEANQAECgUICgAAAA==.Korbusty:BAAANQADCggIDgAAAA==.',
Ku='Kuattieb:BAAANQABCgIIAgAAAA==.',
La='Ladýfinger:BAABNQAECn8iAAMZAAgKmBORYAD0AQAZAAgKmBORYAD0AQAHAAMKxQcuVgGOAAABNQAFFAMIBwASAPARAA==.Laisidhiel:BAAANQAECgMIAwAAAA==.Lateo:BAAANQAECgYJEQAAAA==.Lawz:BAAANQAECgYIEwAAAA==.',
Le='Lelianna:BAAANQADCgYIGgAAAA==.Lemonruss:BAAANQADCggIEQAAAA==.Lexia:BAAANQAECgUICAAAAA==.',
Li='Libidine:BAAANQADCgQIBAABNQAECgQICAACAAAAAA==.Liemannin:BAAANQAECgEIAQAAAA==.Lightninghah:BAAANQABCgIIAgAAAA==.Lilaa:BAAANQADCgcIBwAAAA==.Lilturtz:BAAANQAECgQIBAABNQAECgUIFgANABAfAA==.Linnea:BAAANQADCgcIDQAAAA==.',
Lo='Locksative:BAAANQADCggIHgAAAA==.Longhorn:BAABNQAECn8eAAIHAAgKVw/CrwC6AQAHAAgKVw/CrwC6AQAAAA==.Lorekesh:BAAANQADCgEJAQABNQAECgcICgACAAAAAA==.Lorriena:BAAANQADCgUIBQABNQAECgEIAQACAAAAAA==.Lortpegsalot:BAABNQAECn8tAAIHAAkK4R7mPQDZAgAHAAkK4R7mPQDZAgAAAA==.Lowy:BAAANQAECgIIAgAAAA==.',
Lu='Lucena:BAAANQAECgQIEAAAAA==.Lurg:BAAANQADCgYICAABNQADCggIHgACAAAAAA==.Luxuria:BAAANQADCggICAABNQAECgQICAACAAAAAA==.',
Ly='Lyralana:BAAANQAECgQIBAAAAA==.',
Ma='Maberu:BAABNQAECn8aAAIOAAkKoQscHAC9AQAOAAkKoQscHAC9AQABNQAFFAMIBwAZAP4XAA==.Madamholy:BAAANQAECgYIEgAAAA==.Madamkluck:BAAANQADCgUIBQAAAA==.Maglubiyet:BAAANQAECgMIBAAAAA==.Magnitood:BAAANQAECgYIDgAAAA==.Malbjornion:BAAANQAECgMIBgAAAA==.Malphox:BAAANQADCgQICAAAAA==.Manbearcat:BAAANQAECgYIEgAAAA==.Manhole:BAAANQAECgQIDAAAAA==.Markyb:BAAANQADCggIEQAAAA==.Masamura:BAACNQAFFH8LAAMIAAQKAxPjCQBxAAADAAMKVRVINgDnAAAIAAIKfwfjCQBxAAA1AAQKfzAAAwMACQp3Gg9lALQCAAMACQrnGQ9lALQCAAgAAgqoFmArAJwAAAAA.Maureanna:BAAANQADCgUIDgABNQAECgQIBAACAAAAAA==.',
Me='Mechahuntard:BAAANQADCgEIAQAAAA==.Medanii:BAEBNQAECn8cAAQXAAkKDBBQDQBeAQAXAAYKVRJQDQBeAQAMAAUKcQkxqgASAQAVAAQKTQeiVgCsAAAAAA==.Melorm:BAAANQAECgQIBwAAAA==.',
Mi='Millizh:BAACNQAFFH8WAAMBAAcKgh5kBwDUAQABAAUKLiBkBwDUAQAcAAQKeBpKDwBDAQA1AAQKfyIAAxwACQpaJvcFAHADABwACQpXJvcFAHADAAEABgowIYyPAOYBAAAA.Mirasharu:BAAANQADCgYIFgAAAA==.Mireille:BAAANQADCgYIDQAAAA==.Mitsuri:BAABNQAECn8aAAIHAAcKjw5vxQCLAQAHAAcKjw5vxQCLAQAAAA==.Mitzuky:BAAANQADCgMIAwAAAA==.',
Mo='Mommamoon:BAAANQADCgQIBAABNQAECggIFQAHAG8YAA==.Moonlïght:BAABNQAECn8VAAIHAAgKbxhwdABBAgAHAAgKbxhwdABBAgAAAA==.Morganlefay:BAAANQAECgYIDgAAAA==.Morlyn:BAABNQAECn8XAAIIAAcKERUdDQDeAQAIAAcKERUdDQDeAQAAAA==.Morregan:BAAANQAECgYIBwAAAA==.Motion:BAAANQADCgYIBgAAAA==.Mousereaper:BAABNQAECn8YAAIbAAgKzA1ZLwDDAQAbAAgKzA1ZLwDDAQAAAA==.',
My='Mydnight:BAAANQABCgIIAgAAAA==.Mystìc:BAABNQAECn8gAAQdAAkKUxqFDwBuAgAdAAgK6xiFDwBuAgANAAYKOxxXawDaAQALAAEKaQq4IAEpAAAAAA==.Mystíc:BAAANQAECgYICAABNQAECgkJIAAdAFMaAA==.',
['Má']='Májorrobot:BAABNQAECn8cAAIRAAkKnx+RLQAEAwARAAkKnx+RLQAEAwAAAA==.',
['Mé']='Ménopáwz:BAAANQAECgUIBgABNQAFFAUIBgAGALMSAA==.',
Na='Namor:BAAANQADCggIGgAAAA==.Nattisca:BAAANQADCgYIDAAAAA==.',
Ne='Nessà:BAAANQAECgQICAAAAA==.Neveenn:BAABNQAECn8zAAIJAAkKyBvVDgDkAgAJAAkKyBvVDgDkAgAAAA==.',
Ni='Nirith:BAAANQADCgYIEwAAAA==.Nivmizet:BAAANQABCggIDQAAAA==.',
No='Nohatcat:BAAANQAECgQIBAABNQAECgUIFgANABAfAA==.',
['Nâ']='Nâmii:BAAANQAECgMIAwAAAA==.',
['Nè']='Nèzukõ:BAABNQAECn8bAAIBAAcKnxdWiQD0AQABAAcKnxdWiQD0AQAAAA==.',
Ob='Obata:BAAANQAECgEIAQAAAA==.',
Oc='Octavius:BAAANQADCggJDQABNQAECgIIAgACAAAAAA==.',
Od='Odi:BAAANQADCgQIBAAAAA==.',
Oj='Ojore:BAEBNQAECn8aAAITAAcKsgzbUABnAQATAAcKsgzbUABnAQAAAA==.Ojoverde:BAACNQAFFH8GAAIfAAMKXAIHLQCjAAAfAAMKXAIHLQCjAAA1AAQKfykAAh8ACQpBEPtsABMCAB8ACQpBEPtsABMCAAAA.',
On='Onizuka:BAAANQADCgEIAQABNQADCgcICQACAAAAAA==.Onside:BAAANQAECgYICgABNQAECgkJIAAUALMdAA==.',
Op='Ophillã:BAAANQAECgQICQABNQAECgQICAACAAAAAA==.',
Or='Ordenn:BAAANQADCgQICAABNQAECgkJIAAEAOQfAA==.Orian:BAAANQADCgQIBwAAAA==.',
Oz='Ozz:BAABNQAECn8ZAAIUAAgKFw9TLgChAQAUAAgKFw9TLgChAQAAAA==.Ozzerker:BAAANQADCgEIAQAAAA==.Ozzullr:BAABNQAECn8XAAIBAAkKAhuNMQDWAgABAAkKAhuNMQDWAgAAAA==.',
Pa='Painbreak:BAAANQADCgEIAQABNQAECggIHwASAAMeAA==.Pajamas:BAAANQAECgEJAQABNQAECgUIEAACAAAAAA==.Pallanquin:BAAANQADCgYIDgAAAA==.Papichili:BAAANQAECgQIBgAAAA==.Pashnir:BAAANQADCgcICQAAAA==.',
Pe='Peachey:BAABNQAECn8aAAILAAcKcQ+yiABwAQALAAcKcQ+yiABwAQAAAA==.Peaker:BAAANQAECgMIAwAAAA==.Peakra:BAAANQAECggIDwAAAA==.',
Ph='Phoênix:BAAANQADCgMIAwAAAA==.',
Pi='Pigas:BAABNQAECn8gAAIUAAgKTxTlJwDdAQAUAAgKTxTlJwDdAQAAAA==.',
Pr='Prestoresto:BAAANQADCgYIDwAAAA==.',
Ps='Psychosix:BAAANQAECggIDwAAAA==.',
Qu='Quinberos:BAAANQAECgQIBwAAAA==.',
Ra='Racey:BAAANQADCggICAAAAA==.Raiistlin:BAAANQADCgYIBwABNQAECgQIEQACAAAAAA==.Ramdel:BAAANQAECgIIAgABNQAECggIIwAgAGAbAA==.Ramstrider:BAABNQAECn8jAAMgAAgKYBuoBACSAgAgAAgKYBuoBACSAgABAAIKaQcUNAF2AAAAAA==.Ranch:BAAANQADCgcICQAAAA==.Rapture:BAABNQAECn8fAAIbAAgKGw62LQDQAQAbAAgKGw62LQDQAQAAAA==.Ravec:BAAANQADCgMIAwAAAA==.',
Re='Rengell:BAAANQAECgQICQAAAA==.Reptiliano:BAAANQAECggIBwABNQAECgkJIgAYAGsdAA==.',
Rh='Rheagall:BAABNQAECn8gAAIdAAkKRxzFBgAWAwAdAAkKRxzFBgAWAwAAAA==.Rhodetta:BAABNQAECn8aAAIMAAkK/xXZOQB+AgAMAAkK/xXZOQB+AgAAAA==.',
Ri='Rizepriest:BAAANQADCgIIAgABNQAECgYIDgACAAAAAA==.Rizerage:BAAANQAECgYIDgAAAA==.',
Ro='Roaraxe:BAAANQADCgYIBgABNQAECgIIAgACAAAAAA==.Rowena:BAABNQAECn8zAAIKAAgKfxbsOAAkAgAKAAgKfxbsOAAkAgAAAA==.Rowynna:BAAANQAECgMIAwABNQAECgQIBwACAAAAAA==.Roxy:BAAANQADCgYIBgAAAA==.Roxymonk:BAAANQADCgYIBgAAAA==.Royalviaman:BAAANQADCgQIBwAAAA==.',
Ry='Ryz:BAAANQADCggICAAAAA==.Ryztkmtchrch:BAABNQAECn8rAAQMAAkKjxugMQCfAgAMAAkKjxugMQCfAgAXAAcKww3cDABoAQAVAAUKjA91RgACAQAAAA==.',
['Rå']='Råti:BAAANQADCgUIBQAAAA==.',
Sa='Sacdk:BAAANQAECgQIBwAAAA==.Safaria:BAAANQAECgQIBAABNQAECgUICwACAAAAAA==.Saloenus:BAAANQAECgYICgAAAA==.Sarlyssa:BAAANQABCgYICgAAAA==.Saucehoss:BAABNQAECn8mAAQQAAkKQx3gAwCsAgAQAAkKQx3gAwCsAgAPAAQKLQ/APADNAAAfAAMKkhSdAgHAAAAAAA==.Saucymac:BAAANQAECgYIBQAAAA==.',
Sc='Scofflaw:BAAANQADCgEIAQABNQAECgQIBAACAAAAAA==.Scubasteve:BAAANQADCgUICgAAAA==.',
Se='Sefi:BAABNQAECn8fAAMHAAgKCxGNqADJAQAHAAgKfw6NqADJAQAeAAQKlQ0MTgCsAAAAAA==.Semirrhage:BAAANQADCgMIAwAAAA==.',
Sh='Shadowflame:BAAANQAECgUIEAAAAA==.Shammygoat:BAAANQAECgUIEwAAAA==.Shaqattack:BAABNQAECn8gAAIUAAkKsx3NEgDBAgAUAAkKsx3NEgDBAgAAAA==.Shaqattaq:BAAANQAECggIDwABNQAECgkJIAAUALMdAA==.Sharktide:BAABNQAECn8YAAILAAcKwBq0XgDvAQALAAcKwBq0XgDvAQAAAA==.Shawnella:BAABNQAECn8eAAMUAAgKERq2IAAjAgAUAAcKJBi2IAAjAgAOAAIKTQf3QwBYAAAAAA==.Shenlune:BAAANQAECgYIEQAAAA==.Sheutka:BAAANQAECgIIAgAAAA==.Shiggles:BAAANQAECgEIAQAAAA==.Shinaie:BAAANQAECgYIEgAAAA==.Shocknrollz:BAAANQAECgQIDAAAAA==.Shogún:BAABNQAECn8ZAAIFAAgKbR1dIQCnAgAFAAgKbR1dIQCnAgAAAA==.Shtylez:BAAANQAECgQIBwABNQAECgkJJQABAAYVAA==.',
Si='Silntwolf:BAAANQABCgQIBAAAAA==.Silpion:BAAANQAECgYIDgAAAA==.Silth:BAAANQADCggIGgAAAA==.Sinariel:BAABNQAECn8kAAIOAAgKFh57DAC5AgAOAAgKFh57DAC5AgAAAA==.Sirdank:BAAANQAECgEIAwAAAA==.',
Sk='Skarlate:BAAANQADCgYIBgAAAA==.Skâld:BAEANQADCgYICwAAAA==.',
Sl='Sliko:BAABNQAECn8tAAIHAAkKLBbNbQBRAgAHAAkKLBbNbQBRAgAAAA==.',
Sm='Smmoke:BAABNQAECn8eAAIBAAgK6hYsWABoAgABAAgK6hYsWABoAgAAAA==.',
Sn='Sneekypally:BAAANQAECgUIDQAAAA==.Snowballs:BAAANQAECgYIEgAAAA==.',
So='Softhorn:BAAANQABCgUIBQAAAA==.Sorenreign:BAAANQADCgYICgAAAA==.Sothh:BAAANQADCggIEAABNQAECgQIEQACAAAAAA==.Soull:BAABNQAECn8wAAIJAAkK0yI/AgCqAwAJAAkK0yI/AgCqAwAAAA==.Soulsmash:BAAANQADCggIDAAAAA==.',
Sp='Spacebabe:BAAANQADCgYIBwABNQAECgYIEgACAAAAAA==.Spacestepdad:BAAANQAECgYIEgAAAA==.Sparkie:BAAANQAECgMIAwAAAA==.Spriggan:BAAANQAECgUIBQAAAA==.',
Sq='Squashfoot:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.',
St='Starface:BAACNQAFFH8HAAISAAMK8BGNBQC3AAASAAMK8BGNBQC3AAA1AAQKfysAAhIACQoXG90KAL4CABIACQoXG90KAL4CAAAA.Stargoose:BAAANQAECgUICAABNQAFFAMIBwASAPARAA==.Starphoenix:BAAANQADCgYIBgAAAA==.Steelytree:BAAANQADCgQIBwAAAA==.Stellaria:BAAANQAECgQIEAAAAA==.Steris:BAAANQADCggIGwABNQADCggIHgACAAAAAA==.Steverogers:BAAANQAECgMICQABNQAFFAUIBgAGALMSAA==.Stocktonrush:BAACNQAFFH8GAAQGAAUKsxIqDQA2AQAGAAQKsxIqDQA2AQAFAAEKAADmKQBMAAATAAEKBws1HwA+AAA1AAQKfykAAwYACQonJScQADUDAAYACQolJScQADUDAAUAAQqfI36yAGEAAAAA.Stonedhenge:BAAANQABCgQIBAAAAA==.Sturmx:BAABNQAECn8eAAIaAAgKJxbbLwAkAgAaAAgKJxbbLwAkAgAAAA==.',
Su='Subedei:BAABNQAECn8kAAQTAAkKPhy2MQAWAgATAAcKXBm2MQAWAgAGAAgKtRrZRAACAgAFAAEK0Q79xwA2AAAAAA==.Summerseve:BAAANQAECgMIAwAAAA==.Sunderhorn:BAAANQAECgIIAgAAAA==.Suriaa:BAABNQAECn8wAAMYAAkKlBVZJABhAgAYAAkKlBVZJABhAgAhAAQKuguVEwDBAAAAAA==.',
Sv='Svictis:BAAANQAECgUICAAAAA==.Svictiss:BAAANQADCggIEQAAAA==.',
Sw='Swami:BAAANQAECgQIBAAAAA==.',
Ta='Talila:BAAANQAECgQIEQAAAA==.Taniss:BAAANQADCggIFgABNQAECgQIEQACAAAAAA==.Taurdeth:BAAANQAECgcIEQABNQAECgkJGgAMAP8VAA==.',
Te='Terrya:BAAANQAECgUIBQAAAA==.Teryail:BAAANQADCgUIBQAAAA==.',
Th='Thaqdaddy:BAAANQADCgYIBgABNQAECgkJIwAFANUVAA==.Thaqknight:BAABNQAECn8jAAIFAAkK1RVRMwA+AgAFAAkK1RVRMwA+AgAAAA==.Therylnn:BAAANQADCggICAAAAA==.Thesthamenth:BAAANQADCgYIBgAAAA==.Thiccthaq:BAAANQAECgMIAwABNQAECgkJIwAFANUVAA==.Thily:BAAANQADCgIIAgAAAA==.Thorwallen:BAAANQADCggIFAABNQAECgQIEQACAAAAAA==.Thror:BAAANQAECgEIAQAAAA==.',
Ti='Tiac:BAAANQAECgEIAQAAAA==.Tiergyll:BAAANQABCgIIBAAAAA==.Tirithor:BAABNQAECn8oAAIHAAkKsRUTdABCAgAHAAkKsRUTdABCAgAAAA==.',
To='Tockell:BAAANQADCgQIBwAAAA==.Togala:BAAANQADCgUICwABNQAECgQIBgACAAAAAA==.Toothless:BAAANQAECgEIAQAAAA==.Torbin:BAAANQAECgUIDAAAAA==.Touchmywave:BAAANQADCgcIDgABNQAFFAMIBgABAK4UAA==.',
Tr='Tryjinks:BAABNQAECn8aAAMNAAgK3w7TZgDoAQANAAgK3w7TZgDoAQALAAYKlBJRjABnAQAAAA==.',
Ts='Tsunameh:BAAANQAECgUICQABNQAECgkJJQABAAYVAA==.',
Tu='Tusky:BAAANQADCgYIBgAAAA==.',
Tw='Twohandtug:BAAANQADCggIFwAAAA==.',
Ty='Tykahndrius:BAABNQAECn8dAAMeAAgK/Bm3HAAEAgAeAAcK4Bu3HAAEAgAHAAMKXwzxRgGnAAABNQAECgkJJQABAAYVAA==.Tylîus:BAABNQAECn8ZAAMbAAgKZBZRJQAYAgAbAAgKZBZRJQAYAgAiAAEKAADXLwA7AAAAAA==.Tylïus:BAAANQAECgEIAQABNQAECggIGQAbAGQWAA==.Tyredelsia:BAAANQABCggIFAAAAA==.',
['Tö']='Töph:BAAANQADCgYICgABNQAECgQICAACAAAAAA==.',
['Tú']='Túsk:BAAANQAECgEIAgAAAA==.',
['Tý']='Týlius:BAAANQAECgMIBAABNQAECggIGQAbAGQWAA==.',
Uk='Ukika:BAAANQAECgEIAgABNQAECgQIBgACAAAAAA==.',
Us='Useriòs:BAAANQADCgIIAwAAAA==.',
Ut='Uthilon:BAABNQAECn8eAAIeAAgK8R3zDwCcAgAeAAgK8R3zDwCcAgAAAA==.',
Va='Valdare:BAAANQAECgQIEQAAAA==.Validorn:BAAANQAECgEIAQAAAA==.',
Ve='Vedillian:BAAANQAECgEJAQAAAA==.Velduar:BAAANQADCgQIBAAAAA==.',
Vi='Victorr:BAAANQAECgEIAQAAAA==.Vikkter:BAAANQAECggICAAAAA==.Viktorius:BAAANQADCgQIBAAAAA==.Vixious:BAAANQAECgQIBAAAAA==.Vizigoth:BAABNQAECn8fAAQfAAcKaw09vABPAQAfAAYKaAs9vABPAQAPAAEKURHAcQA9AAAQAAEK7QvNLwA1AAAAAA==.',
Vo='Vordell:BAAANQAECgQICQABNQAECgkJGgAMAP8VAA==.Voyana:BAAANQAECgUICwAAAA==.Voz:BAAANQADCgUIBQAAAA==.',
Vy='Vydragon:BAACNQAFFH8KAAQjAAMKOAlFEQDLAAAjAAMKOAlFEQDLAAAkAAEKiw+SCwBPAAAWAAEK0gd4DwBEAAA1AAQKfx4ABCMACQooD58aABkCACMACQooD58aABkCABYABgonGgUXANgBACQAAwpJEMoVANEAAAE1AAUUAwgFAAMArBIA.Vymage:BAACNQAFFH8FAAIDAAMKrBLEOgDTAAADAAMKrBLEOgDTAAA1AAQKfysAAwMACQrOHrdQAN8CAAMACQrOHrdQAN8CACUAAwrwFE0HAMYAAAAA.',
['Vá']='Válidüs:BAACNQAFFH8TAAIMAAUKKw5CEgB3AQAMAAUKKw5CEgB3AQA1AAQKfzIAAgwACQojIxEMAGADAAwACQojIxEMAGADAAAA.',
['Vã']='Vãsh:BAAANQAECgUIBwAAAA==.',
Wa='Wabbitseason:BAAANQADCgIIAgABNQAECgYIEgACAAAAAA==.Wabìsuke:BAAANQADCggIFQAAAA==.Waterlogged:BAAANQADCgQIDAAAAA==.Waterloo:BAAANQADCgYIDgAAAA==.',
Wi='Wizpigas:BAAANQADCgcIDQABNQAECggIIAAUAE8UAA==.',
['Wì']='Wìccka:BAAANQADCgUIBQAAAA==.',
Xi='Xi:BAAANQAECgMIAwAAAA==.Xifan:BAAANQAFFAEIAQAAAA==.',
Yd='Yd:BAAANQAECgQIBAABNQAFFAEIBQAEAAAAAA==.',
Yg='Yggdrasill:BAAANQABCgUICAAAAA==.',
Yi='Yingpi:BAAANQABCgIIAgAAAA==.',
Yo='Yodaa:BAAANQADCggICwABNQAECgQIEQACAAAAAA==.',
Ys='Ys:BAAANQAECgQIBAABNQAFFAEIBQAEAAAAAA==.',
Yt='Yt:BAAANQAECgQICgABNQAFFAEIBQAEAAAAAA==.',
Yw='Ywontudie:BAAANQADCgUICwAAAA==.',
Yz='Yz:BAACNQAFFH8FAAIEAAEKAADaEABlAAAEAAEKAADaEABlAAA1AAQKfy4AAwQACQrQIwUCAJoDAAQACQrQIwUCAJoDABgAAgpTG2qEAJUAAAAA.',
Za='Zashawa:BAAANQADCgYIEQAAAA==.',
Ze='Zenithgrey:BAABNQAECn8XAAMNAAkKMQ7jhQCSAQANAAcKug7jhQCSAQALAAUKJQ9JqAAdAQAAAA==.',
Zl='Zluco:BAACNQAFFH8GAAIdAAIKLCMeBQDHAAAdAAIKLCMeBQDHAAA1AAQKfy0AAx0ACQqfIC4IAPUCAB0ACQqfIC4IAPUCAAsABgp5HKF8AJIBAAAA.',
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
