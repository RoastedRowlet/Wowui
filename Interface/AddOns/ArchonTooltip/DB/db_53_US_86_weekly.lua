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

local lookup = {'Hunter-BeastMastery','Unknown-Unknown','Mage-Arcane','Rogue-Subtlety','DeathKnight-Blood','DeathKnight-Unholy','Paladin-Retribution','Mage-Frost','Warlock-Demonology','Druid-Restoration','Druid-Balance','Shaman-Restoration','Warrior-Protection','Priest-Shadow','Priest-Holy','Shaman-Elemental','Monk-Mistweaver','Warlock-Destruction','Warlock-Affliction','Warrior-Arms','Druid-Guardian','Druid-Feral','DeathKnight-Frost','Monk-Windwalker','Paladin-Protection','Evoker-Devastation','Priest-Discipline','Rogue-Assassination','Paladin-Holy','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Marksmanship','Shaman-Enhancement','Hunter-Survival','Evoker-Preservation','Evoker-Augmentation','Rogue-Outlaw','DemonHunter-Vengeance','Mage-Fire',}
local provider = {region='US',realm="Eldre'Thalas",name='US',type='weekly',zone=53,date='2026-10-20',data={Ad='Adesira:BAAANQAECgQIBQAAAA==.Adrastus:BAAANQAECgMIAwABNQAECgoKKQABAN8UAA==.',
Ae='Aeslin:BAAANQADCgYJBgABNQAECgEIAQACAAAAAA==.',
Ah='Ahn:BAAANQADCggIEAAAAA==.Ahylin:BAAANQADCgcIDAAAAA==.',
Ai='Ainslie:BAAANQAECgQICwAAAA==.',
Al='Alerana:BAAANQADCggIGAAAAA==.Altria:BAAANQADCgUICQAAAA==.',
An='An:BAABNQAECn8YAAIDAAYKYRyh0wDfAQADAAYKYRyh0wDfAQABNQAFFAEIBQAEAAAAAA==.Anarose:BAAANQAECgUIEQAAAA==.Antityk:BAAANQAECgQIDAABNQAECgoKKQABAN8UAA==.',
Ar='Aragorn:BAAANQADCgQIBQAAAA==.Arahant:BAAANQAECgIIAgAAAA==.Aretas:BAABNQAECn8dAAMFAAgK5B58GQDiAgAFAAgK5B58GQDiAgAGAAEK4Q3c4gAxAAAAAA==.Armadian:BAAANQAECgQICAAAAA==.Arrianne:BAAANQADCgYIBgAAAA==.Arriånna:BAAANQADCgcIEwAAAA==.Artemist:BAABNQAECn8UAAIHAAYKqg2y9QAyAQAHAAYKqg2y9QAyAQAAAA==.',
As='Asifa:BAAANQAECgEIAgAAAA==.',
At='Atherion:BAABNQAECn8hAAIIAAgKEhEiCwATAgAIAAgKEhEiCwATAgAAAA==.Attackroot:BAAANQAECgUIBgABNQAECgYIGAAJANoMAA==.',
Au='Aurakk:BAAANQADCgYIEQABNQAECgYIHAAHAGATAA==.',
Av='Avelin:BAAANQADCgUIBQAAAA==.Avranarada:BAABNQAECn8lAAMKAAkKcRYeIAAqAgAKAAkKcRYeIAAqAgALAAcKuBhUQgDtAQAAAA==.Avril:BAAANQAECgEIAQAAAA==.',
Az='Azhádi:BAAANQABCgIIAgAAAA==.Azkara:BAACNQAFFH8KAAIMAAQK2A/ECgDSAAAMAAQK2A/ECgDSAAA1AAQKfysAAgwACgpQHGojANkCAAwACgpQHGojANkCAAAA.Azung:BAABNQAECn8pAAIHAAoKiRywKwAZAwAHAAoKiRywKwAZAwAAAA==.',
Ba='Babaisyaga:BAACNQAFFH8QAAIBAAQKXiI0BAAaAQABAAQKXiI0BAAaAQA1AAQKfzsAAgEACgqyIgwNAHYDAAEACgqyIgwNAHYDAAAA.Baka:BAAANQAECgYICQAAAA==.Balinse:BAABNQAECn8YAAINAAgKoBMMGQChAQANAAgKoBMMGQChAQABNQAECgoKGQAOAHoLAA==.Balystix:BAAANQADCggICAAAAA==.Barb:BAAANQAECgEIAQAAAA==.Barrelrollin:BAAANQADCgYIDwAAAA==.Basherdownn:BAAANQADCgQIBAAAAA==.',
Be='Beastfodays:BAACNQAFFH8JAAIBAAMKrhQPDgCcAAABAAMKrhQPDgCcAAA1AAQKfzIAAgEACQpxGctDAKACAAEACQpxGctDAKACAAAA.Bethlahammer:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.',
Bi='Billcritin:BAAANQAECgcIDQAAAA==.',
Bl='Blackleaf:BAAANQADCgcICgAAAA==.Blawyke:BAAANQAECgUIBwABNQAFFAIIBAACAAAAAA==.Bless:BAAANQADCggIDgAAAA==.Blizzcon:BAACNQAFFH8RAAIPAAUKexgqCABPAQAPAAUKexgqCABPAQA1AAQKfzsAAg8ACgqUI2sJAHcDAA8ACgqUI2sJAHcDAAAA.Bloodsurge:BAAANQADCgQJAwAAAA==.Blushies:BAABNQAECn8cAAMQAAYKrR//DQCiAQAQAAYKrR//DQCiAQAMAAMK8xC64wCiAAAAAA==.',
Bo='Boltzfodayz:BAAANQAECgEIAQAAAA==.Bonerslap:BAAANQAECgEIAQAAAA==.Boone:BAAANQADCgMIAwAAAA==.Borrgar:BAABNQAECn8cAAIHAAYKYBOjegDUAAAHAAYKYBOjegDUAAAAAA==.',
Br='Brackle:BAABNQAECn8dAAIBAAkKtRqQQgCjAgABAAkKtRqQQgCjAgAAAA==.Bracori:BAACNQAFFH8JAAIRAAQKZg04AwDKAAARAAQKZg04AwDKAAA1AAQKfy4AAhEACgpBE98XAAACABEACgpBE98XAAACAAAA.Brandywynne:BAABNQAECn8kAAIBAAoKsA/3MQBbAQABAAoKsA/3MQBbAQAAAA==.Bretcha:BAAANQADCgQIBAABNQAECgYIBgACAAAAAA==.Brick:BAABNQAECn8lAAIEAAoKVBaeDQCcAgAEAAoKVBaeDQCcAgAAAA==.Brightfame:BAABNQAECn8rAAMSAAgKxRVXGACqAQASAAYK0xRXGACqAQATAAQKlBfpEQAsAQAAAA==.Bronny:BAABNQAECn8ZAAIUAAgKMQ3VuACOAQAUAAgKMQ3VuACOAQAAAA==.Brônwyn:BAAANQADCgQIBAAAAA==.',
Bu='Buffshagwell:BAABNQAECn8lAAIHAAgKsxhqWQCLAgAHAAgKsxhqWQCLAgAAAA==.Bullrush:BAAANQADCgUIBQAAAA==.Butterbllz:BAABNQAECn8pAAIHAAoKhxs/XgB+AgAHAAoKhxs/XgB+AgAAAA==.',
Ca='Calypsio:BAAANQADCgQIBAABNQAECgMIAwACAAAAAA==.Camany:BAABNQAECn8fAAIBAAgKExGMdwAgAgABAAgKExGMdwAgAgAAAA==.Captinkrunch:BAAANQADCgEJAQAAAA==.Captinlock:BAAANQADCgEIAQABNQADCgEJAQACAAAAAA==.Captinmorí:BAAANQADCgEIAQAAAA==.Caretakerz:BAABNQAECn8hAAMVAAkKqRuyCwCuAgAVAAgKAx6yCwCuAgAWAAEKjg2zIAAyAAAAAA==.Cartus:BAAANQAECgUICAABNQAECgYIFAAVAAUJAA==.Cayin:BAABNQAECn8cAAIFAAkKSiDsEwANAwAFAAkKSiDsEwANAwABNQABCgYICwACAAAAAA==.',
Ch='Chanyeol:BAAANQAECgUICAAAAA==.Chemoshh:BAAANQADCggIBgABNQAECgYIHAAHAGATAA==.',
Cl='Clamshell:BAABNQAECn8lAAMXAAkKhSCSBAAiAgAXAAkKhSCSBAAiAgAFAAUKwRi0YgBnAQAAAA==.Claudette:BAAANQAECgcICgAAAA==.Clayier:BAAANQADCgcIEwAAAA==.',
Cn='Cntendr:BAAANQADCgUICAAAAA==.',
Co='Codenike:BAABNQAECn8eAAIYAAcKFhplEgAaAQAYAAcKFhplEgAaAQAAAA==.Coil:BAAANQADCggICgABNQADCggIDgACAAAAAA==.Copenzen:BAAANQAECgQIBgAAAA==.Corelheals:BAAANQAECgUICgAAAA==.Covertyqt:BAABNQAECn8lAAIDAAkKLx0rDgD4AQADAAkKLx0rDgD4AQAAAA==.Coyote:BAAANQABCgUIBgAAAA==.',
Cp='Cptnhuman:BAABNQAECn8lAAIGAAkKfB2qDQByAQAGAAkKfB2qDQByAQAAAA==.',
Cr='Cromie:BAAANQADCggIFQAAAA==.Crosed:BAAANQADCgQIBAAAAA==.',
Cs='Cshunter:BAAANQADCgYIBwAAAA==.',
Cu='Cubcakes:BAAANQADCggIBQAAAA==.',
Cy='Cylcuria:BAAANQABCgIIAgAAAA==.',
['Cõ']='Cõrpses:BAEBNQAECn8aAAIFAAkKjR9rAwA8AgAFAAkKjR9rAwA8AgABNQAECggIEgACAAAAAA==.',
Da='Daboof:BAAANQADCgYIGgAAAA==.Daemandred:BAAANQADCgMIAwAAAA==.Daggere:BAAANQADCggIKAAAAA==.Danke:BAAANQADCgcIJQAAAA==.Dankz:BAAANQAECgEIAgAAAA==.Darkenmicky:BAAANQADCgcIEwAAAA==.Darkmickyz:BAABNQAECn8XAAIZAAYK1xHnNQA4AQAZAAYK1xHnNQA4AQAAAA==.Darthbobula:BAACNQAFFH8JAAIHAAQKKQdcCgDCAAAHAAQKKQdcCgDCAAA1AAQKfxcAAgcACArFDG9tAOsAAAcACArFDG9tAOsAAAAA.Dayloc:BAAANQAECgcIDwAAAA==.',
De='Deataria:BAABNQAECn8pAAIKAAkKdxkwAwByAgAKAAkKdxkwAwByAgAAAA==.Deathrho:BAAANQADCgMIAwAAAA==.Deawin:BAAANQADCgQIBAABNQADCgYIDwACAAAAAA==.Delilia:BAEANQAECggIBQABNQAECgkJFgAJALcKAA==.Delryth:BAAANQADCgYIBQAAAA==.Demonikk:BAAANQAECgUICwABNQAECgoKKQABAN8UAA==.Demontyk:BAAANQAECgUICwABNQAECgoKKQABAN8UAA==.Desception:BAAANQADCgcICgAAAA==.',
Di='Diablõ:BAEANQAECggICAABNQAECggIEgACAAAAAA==.Diadochi:BAAANQAECgQJBQAAAA==.Dieguerta:BAAANQADCgEJAQAAAA==.',
Dl='Dl:BAABNQAECn8pAAIOAAoKOBm9GQCAAgAOAAoKOBm9GQCAAgAAAA==.',
Dr='Drakkarr:BAAANQADCgYIBwAAAA==.Drazhoath:BAAANQAECgUIDQAAAA==.Drdrill:BAAANQADCgYIBgAAAA==.Drimbirt:BAAANQADCgcICgAAAA==.Drinkmormilk:BAAANQAECgIIAgAAAA==.Drogelf:BAAANQADCgYIEgAAAA==.Drogman:BAAANQADCgIIAgAAAA==.',
Du='Dumbledore:BAAANQADCgcIBwABNQAECgEIAQACAAAAAA==.',
['Dá']='Dáwnbringer:BAAANQADCgIIBAAAAA==.',
Eb='Ebullition:BAAANQAECgcICAAAAA==.',
Ed='Edensfury:BAAANQAECgIIAgAAAA==.',
Ee='Eedani:BAAANQADCgUJCQAAAA==.',
Ei='Eigi:BAABNQAECn8aAAIBAAkKLBU8bwAzAgABAAkKLBU8bwAzAgAAAA==.',
El='Eldanon:BAABNQAECn8vAAISAAkKfCEfAQCRAwASAAkKfCEfAQCRAwAAAA==.Elementality:BAAANQADCgIIAgAAAA==.Eleyert:BAACNQAFFH8KAAIQAAUK4x0pDACpAQAQAAUK4x0pDACpAQA1AAQKfyYAAhAACgpUI6YMAIIDABAACgpUI6YMAIIDAAAA.Elistann:BAAANQAECgQIBAABNQAECgYIHAAHAGATAA==.Elwe:BAABNQAECn8cAAIPAAgKtRTMcgDEAQAPAAgKtRTMcgDEAQAAAA==.',
Em='Embaku:BAAANQADCggICAABNQAECgoKMgAHANgTAA==.Emiri:BAAANQAECgQIBQAAAA==.Emrhakul:BAAANQABCggIFQAAAA==.',
En='Enkidu:BAABNQAECn8aAAIBAAUKaBRcdwC+AAABAAUKaBRcdwC+AAAAAA==.Enseth:BAABNQAECn8fAAIaAAcKvgnVCQDMAAAaAAcKvgnVCQDMAAAAAA==.',
Er='Erakha:BAAANQAECgYIBgAAAA==.Erandria:BAAANQADCgcICQABNQAECgUIBAACAAAAAA==.',
Eu='Eulogy:BAAANQADCgYICAABNQAFFAUIEQAPAHsYAA==.',
Ex='Exileosis:BAEBNQAECn8bAAQPAAkK6SPBCgBsAwAPAAkK6SPBCgBsAwAbAAYKHRjpCwB/AQAOAAEKgAKQkwAVAAABNQAECgkKGwAPAOkjAA==.',
Ez='Ezerharden:BAAANQABCgEJAQAAAA==.Ezki:BAAANQADCggIFwABNQAECgYIHAAHAGATAA==.',
Fa='Fairious:BAABNQAECn8sAAIEAAkKahggBAANAgAEAAkKahggBAANAgAAAA==.',
Fe='Felcon:BAAANQADCgYICQAAAA==.Felenkeller:BAAANQAECgIIBQABNQAFFAUICQAGAIkVAA==.Fenrirr:BAAANQADCggICAABNQAECgYIHAAHAGATAA==.Fet:BAABNQAECn8kAAMcAAoKSyCHEQA4AQAEAAgKDR6PEQBoAgAcAAcK/R+HEQA4AQAAAA==.',
Fh='Fhatbashtud:BAAANQAECgIIAwAAAA==.',
Fl='Flashies:BAAANQAECgIIAgABNQAECgYIHAAQAK0fAA==.Flatline:BAABNQAECn8dAAIbAAcKFxrQAQBhAQAbAAcKFxrQAQBhAQAAAA==.Flinnt:BAAANQADCgMIBAABNQAECgYIHAAHAGATAA==.',
Fn='Fngusamungus:BAAANQAECgEIAQAAAA==.',
Fo='Folgore:BAAANQAECgIIAgAAAA==.Four:BAAANQAECgYIEAAAAA==.',
Fr='Fredwarlock:BAAANQAECgUIBwAAAA==.Frysky:BAAANQAECgYIDAAAAA==.',
Fu='Furiousv:BAAANQADCgUIBQAAAA==.Futz:BAABNQAECn8pAAIdAAgKXCAQHgD5AgAdAAgKXCAQHgD5AgAAAA==.',
Ga='Gahnzul:BAAANQADCgUICgAAAA==.Gajitbek:BAAANQADCgUIBQAAAA==.Galah:BAABNQAECn8WAAIDAAcKSg498gCmAQADAAcKSg498gCmAQAAAA==.Gardurst:BAABNQAECn8nAAIQAAoK8BnABAAwAgAQAAoK8BnABAAwAgAAAA==.',
Gn='Gnomicide:BAAANQAECgIIBAAAAA==.',
Go='Gonesh:BAAANQADCggIEAAAAA==.Gooberpea:BAAANQABCgYIEAAAAA==.Gordoe:BAAANQADCgUICgAAAA==.',
Gr='Graveborne:BAAANQADCggIEQAAAA==.Gravess:BAAANQADCgUICwAAAA==.Gravewin:BAAANQADCgQICgABNQADCgYIDwACAAAAAA==.Gravyexpress:BAABNQAECn9XAAMeAAoKBhw/FwDhAgAeAAoK6Bs/FwDhAgAfAAcKxhTCPQBbAQAAAA==.Grendelheim:BAAANQADCgYIHAAAAA==.Grogar:BAAANQADCgcIEQAAAA==.',
Gu='Gula:BAAANQAECgQIBQABNQAECgQIDAACAAAAAA==.',
Ha='Hadez:BAAANQADCgUIBQAAAA==.Hantak:BAAANQADCgMIBgAAAA==.Harmsway:BAAANQADCgcJEQAAAA==.Hathaendron:BAAANQADCgYIBgAAAA==.',
He='Hephaestus:BAAANQAECgQICAAAAA==.',
Ho='Hocka:BAAANQADCgUIBgAAAA==.Holysmight:BAAANQAECgEIAQAAAA==.Holyumo:BAAANQADCgYIBgAAAA==.Holyyballs:BAAANQAECgUIBgABNQAECgkJGQAIALwKAA==.Howlymandel:BAAANQAECgQIBQABNQAECggIEQACAAAAAA==.Hoytx:BAAANQADCgUIBQAAAA==.',
Hy='Hydraciel:BAAANQAECgYIDgAAAA==.',
['Hì']='Hìroko:BAAANQAECgUIDAAAAA==.',
Ic='Icedemon:BAAANQAECgQICAAAAA==.Iceliandra:BAAANQADCgYIBgAAAA==.Icupapi:BAAANQADCggILwAAAA==.Icynips:BAAANQABCgEIAQAAAA==.',
Im='Im:BAAANQADCgEJAQABNQAFFAEIBQAEAAAAAA==.Imabigman:BAAANQADCgcICAAAAA==.Imaleaf:BAABNQAECn8aAAILAAgKMQbsXQBZAQALAAgKMQbsXQBZAQAAAA==.Imperius:BAAANQAECgEIAQAAAA==.',
In='Insillico:BAAANQAECgEIAQABNQAECgoKKQABAN8UAA==.',
Ip='Iplaydead:BAABNQAECn8pAAMBAAoK3xT9TwB/AgABAAoK3xT9TwB/AgAgAAEKAACnmgAmAAAAAA==.',
Ir='Iroh:BAABNQAECn8WAAIYAAcKuxwNIQAkAgAYAAcKuxwNIQAkAgAAAA==.',
Is='Ismokeprot:BAAANQADCgQIBAAAAA==.',
Ja='Jacii:BAAANQAECggICQABNQAECgkJJQAXAIUgAA==.Jawnson:BAABNQAECn8VAAIEAAgKeg4KHAD1AQAEAAgKeg4KHAD1AQAAAA==.',
Je='Jelluz:BAAANQADCgYIBgAAAA==.Jenefer:BAACNQAFFH8JAAIFAAQKpxrQBgDnAAAFAAQKpxrQBgDnAAA1AAQKfy0AAwUACgrHGm8pAHcCAAUACgqtGm8pAHcCAAYAAgrsFBS4AH0AAAAA.Jeslartoma:BAAANQADCgEIAQABNQADCgYIEAACAAAAAA==.',
Ji='Jimjimmy:BAAANQADCgcIBwABNQAECgIIAgACAAAAAA==.',
Jo='Jondooz:BAAANQAECgcIBwAAAA==.',
Jp='Jpegz:BAAANQADCgcIBgABNQAECgoKNgAHAI0hAA==.',
Ka='Kailana:BAAANQAECgEIAgABNQAECgoKKAAhANAZAA==.Kailback:BAAANQAECgYIDQABNQAECgoKKAAhANAZAA==.Kait:BAABNQAECn8jAAIMAAkKfBWNEADUAQAMAAkKfBWNEADUAQAAAA==.Kalcifur:BAACNQAFFH8KAAMdAAQKdhTGCADwAAAdAAQKdhTGCADwAAAZAAEKGgz7EgA2AAA1AAQKfy0AAx0ACgpJHEQoAMcCAB0ACgpJHEQoAMcCABkAAwqRGm0qAF8AAAAA.Karin:BAAANQAECgIIAwABNQAECgYIFAAVAAUJAA==.Karnelian:BAAANQAECgYICwABNQAECgoKGQARAH0UAA==.Karras:BAAANQADCgUIBQAAAA==.Kashisht:BAAANQAECgIIAgAAAA==.Kasstigate:BAABNQAECn8bAAIUAAgKGheEdQA1AgAUAAgKGheEdQA1AgABNQAFFAQICQAFAKcaAA==.Kastiel:BAABNQAECn8ZAAIOAAoKegvuLQC2AQAOAAoKegvuLQC2AQAAAA==.Katstrider:BAABNQAECn8iAAIBAAgKbhaXcwApAgABAAgKbhaXcwApAgAAAA==.Kattarea:BAAANQADCgUJCAABNQAECggIIgABAG4WAA==.Kavica:BAAANQAECgYIBgABNQAECgoKGwAKABQdAA==.',
Ke='Keldean:BAABNQAECn8YAAINAAgKQh2ACgCZAgANAAgKQh2ACgCZAgAAAA==.Keryka:BAACNQAFFH8KAAMXAAQKuBwHBAD+AAAXAAQKuBwHBAD+AAAGAAEKZRJXIQBHAAA1AAQKfy4AAxcACgqlHrUKAEQDABcACQoTILUKAEQDAAYACArMGy1FAAQCAAAA.',
Kh='Khere:BAAANQAECgIIAgAAAA==.',
Ki='Kirigiri:BAAANQAECgEIAQABNQAFFAQICgAdAHYUAA==.Kirøs:BAAANQAECgMIBAAAAA==.Kiterisa:BAABNQAECn8lAAIMAAkKEAd8OgD9AAAMAAkKEAd8OgD9AAAAAA==.',
Kk='Kkazz:BAAANQADCggICwABNQAECgYIHAAHAGATAA==.',
Ko='Kohn:BAAANQAECgUIBwAAAA==.Kona:BAEANQAECggIEgAAAA==.Korbusty:BAAANQADCggIDgAAAA==.',
Ku='Kuattieb:BAAANQABCgIIAgAAAA==.',
La='Ladýfinger:BAABNQAECn8nAAQdAAkKbxN8YQD0AQAdAAgKkBR8YQD0AQAHAAMKxQdDWwGOAAAZAAMKmgRHIQCNAAABNQAFFAQICgAVAI0OAA==.Laisidhiel:BAAANQAECgMIAwAAAA==.Lateo:BAABNQAECn8WAAIEAAkKVwu4JwCIAQAEAAkKVwu4JwCIAQAAAA==.Lawz:BAABNQAECn8ZAAMTAAgKXATFEABAAQATAAgKXATFEABAAQASAAIKOAAGegA0AAAAAA==.',
Le='Lelianna:BAAANQADCgYIHgAAAA==.Lemonruss:BAAANQADCggIEQAAAA==.Lexia:BAAANQAECgYICwAAAA==.',
Li='Libidine:BAAANQADCgQIBAABNQAECgQIDAACAAAAAA==.Liemannin:BAAANQAECgEIAQAAAA==.Lightninghah:BAAANQABCgIIAgAAAA==.Lilaa:BAAANQADCgcIBwAAAA==.Lilturtz:BAAANQAECgQIBgABNQAECgYIHAAQAK0fAA==.Linnea:BAAANQADCgcIDQAAAA==.',
Lo='Locksative:BAAANQADCggIJgAAAA==.Longhorn:BAABNQAECn8jAAIHAAgKVw9QsgC6AQAHAAgKVw9QsgC6AQAAAA==.Lorekesh:BAAANQADCgEJAQABNQAECgcICgACAAAAAA==.Lorriena:BAAANQADCggIDQABNQAECgIIAwACAAAAAA==.Lortpegsalot:BAABNQAECn82AAIHAAoKjSGZAgD8AgAHAAoKjSGZAgD8AgAAAA==.Lowy:BAAANQAECgMIAwAAAA==.',
Lu='Lucena:BAABNQAECn8aAAIPAAYKUSTcBgCBAgAPAAYKUSTcBgCBAgAAAA==.Lurg:BAAANQADCgYICAABNQADCggIJgACAAAAAA==.Luxuria:BAAANQADCggICAABNQAECgQIDAACAAAAAA==.',
Ly='Lyralana:BAAANQAECgUIBAAAAA==.',
Ma='Maberu:BAABNQAECn8dAAIRAAoKDQxrHAC9AQARAAoKDQxrHAC9AQABNQAFFAQICgAdAHYUAA==.Madamholy:BAABNQAECn8XAAIPAAYKjx8dGwCfAQAPAAYKjx8dGwCfAQAAAA==.Madamkluck:BAAANQADCgUIBQAAAA==.Maglubiyet:BAAANQAECgQIBwAAAA==.Magnitood:BAAANQAECgYIEwAAAA==.Malbjornion:BAAANQAECgMIBgAAAA==.Malphox:BAAANQADCgQICAAAAA==.Manbearcat:BAABNQAECn8UAAIVAAYKBQm/NgDwAAAVAAYKBQm/NgDwAAAAAA==.Manhole:BAAANQAECgQIDAAAAA==.Markyb:BAAANQADCggIEQAAAA==.Masamura:BAACNQAFFH8PAAMDAAUKFxdaFgCpAAADAAQKcxtaFgCpAAAIAAIKfwchCgBxAAA1AAQKfzIAAwMACgqXGXpnAK8CAAMACgoZGXpnAK8CAAgAAgqoFuYrAJwAAAAA.Maureanna:BAAANQADCgUIDgABNQAECgUIBAACAAAAAA==.',
Me='Mechahuntard:BAAANQADCgEIAQAAAA==.Medanii:BAEBNQAECn8dAAQbAAkKDBBeDQBeAQAbAAYKVRJeDQBeAQAPAAUKcQkcrAASAQAOAAQKTQenVwCsAAAAAA==.Melorm:BAAANQAECgQICQAAAA==.',
Mi='Millizh:BAACNQAFFH8YAAMBAAgKoh6tBwDUAQABAAUKLiCtBwDUAQAgAAUKqhucDwBDAQA1AAQKfycAAyAACgrEJBsGAG8DACAACQpXJhsGAG8DAAEABwqvH/WRAOUBAAAA.Mirasharu:BAAANQADCgYIGgAAAA==.Mireille:BAAANQADCgYIDQAAAA==.Mitsuri:BAABNQAECn8dAAIHAAcK+A6XyACKAQAHAAcK+A6XyACKAQAAAA==.Mitzuky:BAAANQADCgMIAwAAAA==.',
Mo='Mommamoon:BAAANQADCgQIBAABNQAECgkJGQAHAHEXAA==.Moonlïght:BAABNQAECn8ZAAIHAAkKcReDdgBAAgAHAAkKcReDdgBAAgAAAA==.Morganlefay:BAAANQAECgYIEQAAAA==.Morlyn:BAABNQAECn8dAAIIAAgKpxRFDQDdAQAIAAgKpxRFDQDdAQAAAA==.Morregan:BAAANQAECgcICAAAAA==.Motion:BAAANQADCgcICQABNQADCggIDgACAAAAAA==.Mousereaper:BAABNQAECn8YAAIfAAgKzA3hLwDDAQAfAAgKzA3hLwDDAQAAAA==.',
My='Mydnight:BAAANQABCgIIAgAAAA==.Mystìc:BAABNQAECn8oAAQhAAoK0BnxBQCbAQAQAAYKOxzObADaAQAhAAkKxhjxBQCbAQAMAAEKaQr2IwEpAAAAAA==.Mystíc:BAAANQAECgYICAABNQAECgoKKAAhANAZAA==.',
['Má']='Májorrobot:BAABNQAECn8gAAIUAAkKYiBrLgAEAwAUAAkKYiBrLgAEAwAAAA==.',
['Mé']='Ménopáwz:BAAANQAECggIDQABNQAFFAUICQAGAIkVAA==.',
Na='Nattisca:BAAANQADCgYIEAAAAA==.',
Ne='Nefhainea:BAAANQADCgEIAQABNQAECgYIBgACAAAAAA==.Nervanna:BAAANQAECgIIAgABNQAECgoKGwAPAAMUAA==.Nessà:BAAANQAECgQIDAAAAA==.Neveenn:BAABNQAECn82AAIKAAoKBxwPDwDkAgAKAAoKBxwPDwDkAgAAAA==.',
Ni='Nirith:BAAANQADCgYIEwAAAA==.',
No='Nohatcat:BAAANQAECgQIBgABNQAECgYIHAAQAK0fAA==.',
['Nâ']='Nâmii:BAAANQAECgMIAwAAAA==.',
['Nè']='Nèzukõ:BAABNQAECn8dAAIBAAgK5xSHiwDzAQABAAgK5xSHiwDzAQAAAA==.',
Ob='Obata:BAAANQAECgEIAQAAAA==.',
Oc='Octavius:BAAANQADCggJDQABNQAECgIIAgACAAAAAA==.',
Od='Odi:BAAANQADCgQIBAAAAA==.',
Oj='Ojore:BAEBNQAECn8fAAIXAAcKsgw4LwDfAAAXAAcKsgw4LwDfAAAAAA==.Ojoverde:BAACNQAFFH8JAAIJAAQKXgRPCwC+AAAJAAQKXgRPCwC+AAA1AAQKfy0AAgkACgrcD5luABMCAAkACgrcD5luABMCAAAA.',
On='Onizuka:BAAANQADCgEIAQABNQADCgcICQACAAAAAA==.Onside:BAAANQAECgYICgABNQAFFAQIBwAYAL8TAA==.',
Op='Ophillã:BAAANQAECgUIDAABNQAECgQIDAACAAAAAA==.',
Or='Ordenn:BAAANQADCgQICAABNQAECgoKJAAcAEsgAA==.Orian:BAAANQADCgQIBwAAAA==.',
Oz='Ozz:BAABNQAECn8ZAAIYAAgKFw/aLgChAQAYAAgKFw/aLgChAQAAAA==.Ozzerker:BAAANQADCgEIAQAAAA==.Ozzullr:BAABNQAECn8XAAIBAAkKAht3MgDVAgABAAkKAht3MgDVAgAAAA==.',
Pa='Painbreak:BAAANQADCgEIAQABNQAECgkJIQAVAKkbAA==.Pajamas:BAAANQAECgEJAQABNQAECgYIGAAJANoMAA==.Pallanquin:BAAANQADCgYIDgAAAA==.Papichili:BAAANQAECgQIBwAAAA==.Pashnir:BAAANQADCgcICQAAAA==.',
Pe='Peachey:BAABNQAECn8cAAIMAAgK9A0pigBwAQAMAAgK9A0pigBwAQAAAA==.Peaker:BAAANQAECgMIAwAAAA==.Peakra:BAAANQAECggIEwAAAA==.',
Ph='Phoênix:BAAANQADCgMIAwAAAA==.',
Pi='Pigas:BAABNQAECn8gAAIYAAgKTxRiKADdAQAYAAgKTxRiKADdAQAAAA==.',
Pr='Prestoresto:BAAANQADCgYIDwAAAA==.',
Ps='Psychosix:BAABNQAECn8WAAIDAAoKjxtmSwDrAgADAAoKjxtmSwDrAgAAAA==.',
Qu='Quinberos:BAAANQAECgUICgAAAA==.',
Ra='Racey:BAAANQADCggICAAAAA==.Raiistlin:BAAANQADCgYIBwABNQAECgYIHAAHAGATAA==.Ramdel:BAAANQAECgIIAgABNQAECgkJLwAiAPoXAA==.Ramstrider:BAABNQAECn8vAAMiAAkK+hexBACRAgAiAAkK+hexBACRAgABAAIKaQcTOAF2AAAAAA==.Ranch:BAAANQADCgcICQAAAA==.Rapture:BAABNQAECn8mAAIfAAkKbA1IDABWAQAfAAkKbA1IDABWAQAAAA==.Ravec:BAAANQADCgMIAwAAAA==.Rayziel:BAAANQADCggICAABNQAECgMIBQACAAAAAA==.',
Re='Rengell:BAAANQAECggIEQAAAA==.Reptiliano:BAAANQAECggICwABNQAFFAMIBQAcAJwOAA==.',
Rh='Rheagall:BAABNQAECn8mAAIhAAoKox/fBgAUAwAhAAoKox/fBgAUAwAAAA==.Rhodetta:BAABNQAECn8bAAIPAAoKAxS5OgB+AgAPAAoKAxS5OgB+AgAAAA==.',
Ri='Rizepriest:BAAANQADCgIIAgABNQAECgYIEwACAAAAAA==.Rizerage:BAAANQAECgYIEwAAAA==.',
Ro='Roaraxe:BAAANQADCgYIBgABNQAECgIIAgACAAAAAA==.Rowena:BAABNQAECn82AAILAAkKjhSROQAjAgALAAkKjhSROQAjAgAAAA==.Rowynna:BAAANQAECgMIAwABNQAECgUICgACAAAAAA==.Roxy:BAAANQADCgYIBgAAAA==.Roxymonk:BAAANQADCgYIBgAAAA==.Royalviaman:BAAANQADCgcICgAAAA==.',
Ry='Ryz:BAAANQADCggICAAAAA==.Ryztkmtchrch:BAACNQAFFH8FAAIPAAIKdhz1EACtAAAPAAIKdhz1EACtAAA1AAQKfy8ABA8ACgqXG2cyAJ4CAA8ACgqXG2cyAJ4CABsABwrDDe8MAGgBAA4ABQqMDzNHAAIBAAAA.',
['Rå']='Råti:BAAANQADCgUIBQAAAA==.',
Sa='Sacdk:BAAANQAECgQIBwAAAA==.Safaria:BAAANQAECgQIBAABNQAECgUIDQACAAAAAA==.Saloenus:BAAANQAECgYICgAAAA==.Saucehoss:BAABNQAECn8mAAQTAAkKQx3sAwCrAgATAAkKQx3sAwCrAgASAAQKLQ8MPQDNAAAJAAMKkhTNBQHAAAAAAA==.Saucymac:BAAANQAFFAMIAwAAAA==.',
Sc='Scofflaw:BAAANQADCgEIAQABNQAECgQIBAACAAAAAA==.Scubasteve:BAAANQADCgUICgAAAA==.',
Se='Sefi:BAABNQAECn8nAAMHAAgKCxHoTwAlAQAHAAgKIxDoTwAlAQAZAAQKlQ3+TgCsAAAAAA==.Semirrhage:BAAANQADCgMIAwAAAA==.',
Sh='Shadowflame:BAABNQAECn8YAAIJAAYK2gx4VADaAAAJAAYK2gx4VADaAAAAAA==.Shamanigans:BAAANQAECgEIAQABNQAECgYIEwACAAAAAA==.Shammygoat:BAABNQAECn8cAAIQAAYKGhpJfwCnAQAQAAYKGhpJfwCnAQAAAA==.Shaqattack:BAACNQAFFH8HAAIYAAQKvxPqAwDiAAAYAAQKvxPqAwDiAAA1AAQKfyQAAhgACgoWHBATAMICABgACgoWHBATAMICAAAA.Shaqattaq:BAAANQAECggIEQABNQAFFAQIBwAYAL8TAA==.Sharktide:BAABNQAECn8YAAIMAAcKwBrZXwDvAQAMAAcKwBrZXwDvAQAAAA==.Shawnella:BAABNQAECn8lAAMYAAkK/RlsCACHAQAYAAgKYBhsCACHAQARAAIKTQf1RABYAAAAAA==.Shenlune:BAAANQAECgYIEQAAAA==.Sheutka:BAAANQAECgIIBAAAAA==.Shiggles:BAAANQAECgEIAQAAAA==.Shinaie:BAABNQAECn8YAAIOAAcKYAt8OABhAQAOAAcKYAt8OABhAQAAAA==.Shocknrollz:BAAANQAECgQIDAAAAA==.Shogún:BAABNQAECn8ZAAIFAAgKbR2+IQCnAgAFAAgKbR2+IQCnAgAAAA==.Shtylez:BAAANQAECgQIBwABNQAECgoKKQABAN8UAA==.',
Si='Silntwolf:BAAANQABCgQIBAAAAA==.Silpion:BAAANQAECgYIEwAAAA==.Silth:BAAANQADCggIIQAAAA==.Sinariel:BAABNQAECn8oAAIRAAoKyRy2DAC4AgARAAoKyRy2DAC4AgAAAA==.Sirdank:BAAANQAECgEIAwAAAA==.',
Sk='Skarlate:BAAANQADCgYIBgAAAA==.Skâld:BAEANQADCgYICwAAAA==.',
Sl='Sliko:BAABNQAECn83AAIHAAoKZhXXDwD9AQAHAAoKZhXXDwD9AQAAAA==.',
Sm='Smmoke:BAABNQAECn8lAAIBAAkKaRZlFgDDAQABAAkKaRZlFgDDAQAAAA==.',
Sn='Sneekypally:BAABNQAECn8XAAIHAAYKsgPvIwHjAAAHAAYKsgPvIwHjAAAAAA==.Snowballs:BAABNQAECn8ZAAMIAAkKvAr3EAB9AAADAAgKnwlECgF8AQAIAAIKGA33EAB9AAAAAA==.',
So='Softhorn:BAAANQABCgUIBQAAAA==.Sorenreign:BAAANQADCgYICgAAAA==.Sothh:BAAANQADCggIEAABNQAECgYIHAAHAGATAA==.Soull:BAABNQAECn86AAIKAAoKlyRKAAD6AwAKAAoKlyRKAAD6AwAAAA==.Soulsmash:BAAANQAECgEIAQAAAA==.',
Sp='Spacebabe:BAAANQADCgcICwABNQAECgcIGgAaAOQKAA==.Spacestepdad:BAABNQAECn8aAAQaAAcK5AqnHwBbAQAaAAcK5AqnHwBbAQAjAAYKlwpOMQAQAQAkAAIKJgQ9DwAqAAAAAA==.Sparkie:BAAANQAECgMIAwAAAA==.Spriggan:BAAANQAECgUIBQAAAA==.',
Sq='Squashfoot:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.',
St='Starface:BAACNQAFFH8KAAIVAAQKjQ5YAgCvAAAVAAQKjQ5YAgCvAAA1AAQKfywAAhUACgo6GPwKAL8CABUACgo6GPwKAL8CAAAA.Stargoose:BAAANQAECgUICAABNQAFFAQICgAVAI0OAA==.Starphoenix:BAAANQADCggIDgAAAA==.Steelytree:BAAANQADCgcICgAAAA==.Stellaria:BAABNQAECn8WAAIdAAYKERFTKQA9AQAdAAYKERFTKQA9AQAAAA==.Steris:BAAANQADCggIHQABNQADCggIJgACAAAAAA==.Steverogers:BAAANQAECgQIDAABNQAFFAUICQAGAIkVAA==.Stocktonrush:BAACNQAFFH8JAAQGAAUKiRVhDQA2AQAGAAQKsxJhDQA2AQAXAAMKgRcZCACgAAAFAAEKAACCKgBMAAA1AAQKfy0ABAYACgqvJEwQADQDAAYACQolJUwQADQDABcAAQpjIU5UAGUAAAUAAQqfIwO0AGEAAAAA.Stonedhenge:BAAANQABCgQIBAAAAA==.Sturmx:BAABNQAECn8lAAIeAAkKMBQZDACRAQAeAAkKMBQZDACRAQAAAA==.',
Su='Subedei:BAABNQAECn8oAAQXAAoKphzLHAA1AQAGAAgKtRqcRQACAgAXAAgK3BzLHAA1AQAFAAEK0Q7hyQA2AAAAAA==.Summerseve:BAAANQAECgMIAwAAAA==.Sunderhorn:BAAANQAECgIIBAAAAA==.Suriaa:BAABNQAECn86AAMcAAoKphe1AgA0AgAcAAoKphe1AgA0AgAlAAQKugu8EwDBAAAAAA==.',
Sv='Svictis:BAAANQAECgYIDAAAAA==.Svictiss:BAAANQADCggIEQAAAA==.',
Sw='Swami:BAAANQAECgQIBAAAAA==.',
Ta='Talila:BAABNQAECn8bAAIVAAUKyx36HwCdAQAVAAUKyx36HwCdAQAAAA==.Taniss:BAAANQADCggIFgABNQAECgYIHAAHAGATAA==.Taurdeth:BAABNQAECn8XAAQFAAgKGAx5YABwAQAFAAgK5gt5YABwAQAGAAIKFQQ3QgBcAAAXAAIKXgsZbAAvAAABNQAECgoKGwAPAAMUAA==.',
Te='Terrya:BAAANQAECgUIBQAAAA==.Teryail:BAAANQADCgUIBQAAAA==.',
Th='Thaqdaddy:BAAANQADCgYIBgABNQAECgoKJQAFACwVAA==.Thaqknight:BAABNQAECn8lAAIFAAoKLBXcMwA+AgAFAAoKLBXcMwA+AgAAAA==.Therylnn:BAAANQAECgEIAQAAAA==.Thesthamenth:BAAANQADCgYIBgAAAA==.Thiccthaq:BAAANQAECgMIAwABNQAECgoKJQAFACwVAA==.Thily:BAAANQADCgIIAgAAAA==.Thorwallen:BAAANQADCggIFAABNQAECgYIHAAHAGATAA==.Thror:BAAANQAECgEIAQAAAA==.',
Ti='Tiac:BAAANQAECgEIAQAAAA==.Tiergyll:BAAANQABCgIIBgAAAA==.Tirithor:BAABNQAECn8yAAIHAAoK2BNJFgDNAQAHAAoK2BNJFgDNAQAAAA==.',
To='Tockell:BAAANQADCgQIBwAAAA==.Togala:BAAANQADCgYIDgABNQAECgYIBgACAAAAAA==.Toothless:BAAANQAECgEIAQAAAA==.Torbin:BAAANQAECgUIDQAAAA==.Touchmywave:BAAANQADCgcIDgABNQAFFAMICQABAK4UAA==.',
Tr='Tryjinks:BAABNQAECn8iAAMQAAkK+Q0jaADoAQAQAAkK+Q0jaADoAQAMAAYKnBLIjQBmAQAAAA==.',
Ts='Tsunameh:BAAANQAECgcIDAABNQAECgoKKQABAN8UAA==.',
Tu='Tusky:BAAANQADCgYIBgAAAA==.',
Tw='Twohandtug:BAAANQADCggIGwAAAA==.',
Ty='Tykahndrius:BAABNQAECn8lAAMZAAoKgxYeHQACAgAZAAgKoBgeHQACAgAHAAcKJBEGRgA5AQABNQAECgoKKQABAN8UAA==.Tylîus:BAABNQAECn8hAAQmAAkK8hUPCQDZAAAfAAgKZBa8JQAYAgAmAAUKBBgPCQDZAAAeAAEKqgeQUQA0AAAAAA==.Tylïus:BAAANQAECgEIAQABNQAECgkJIQAmAPIVAA==.Tyredelsia:BAAANQABCggIFAAAAA==.',
['Tö']='Töph:BAAANQADCgYICgABNQAECgQIDAACAAAAAA==.',
['Tú']='Túsk:BAAANQAECgEIAgAAAA==.',
['Tý']='Týlius:BAAANQAECgMIBAABNQAECgkJIQAmAPIVAA==.',
Uk='Ukika:BAAANQAECgEIAgABNQAECgYIBgACAAAAAA==.',
Us='Useriòs:BAAANQADCgIIAwAAAA==.',
Ut='Uthilon:BAABNQAECn8lAAIZAAkKyR6FAgAdAgAZAAkKyR6FAgAdAgAAAA==.',
Va='Valdare:BAABNQAECn8bAAIeAAUKmg1yWwAWAQAeAAUKmg1yWwAWAQAAAA==.Validorn:BAAANQAECgEIAQAAAA==.',
Ve='Vedillian:BAAANQAECgEJAQAAAA==.Velduar:BAAANQADCgQIBAAAAA==.',
Vi='Victorr:BAAANQAECgEIAQAAAA==.Vikkter:BAAANQAECggICAAAAA==.Viktorius:BAAANQADCgQIBAAAAA==.Vixious:BAAANQAECgQIBAAAAA==.Vizigoth:BAABNQAECn8gAAQJAAcKaw14vgBPAQAJAAYKaAt4vgBPAQASAAEKURFWcgA9AAATAAIK7QtCMAA1AAAAAA==.',
Vo='Vordell:BAAANQAECgQICQABNQAECgoKGwAPAAMUAA==.Voyana:BAAANQAECgUIDQAAAA==.Voz:BAAANQADCgUIBQAAAA==.',
Vy='Vydragon:BAACNQAFFH8MAAQjAAUKXwyVEQDLAAAjAAMKOAmVEQDLAAAkAAMKExACBQBaAAAaAAEK0gfcDwBBAAA1AAQKfyQABCMACgoyENkaABgCACMACgoyENkaABgCABoABwrzGC4XANgBACQABApJEP8VANEAAAE1AAUUAwgHAAMArBIA.Vymage:BAACNQAFFH8HAAIDAAMKrBJxHACKAAADAAMKrBJxHACKAAA1AAQKfzAAAwMACgqEHPYmAHsBAAMACgqEHPYmAHsBACcAAwrwFGUHAMYAAAAA.',
['Vá']='Válidüs:BAACNQAFFH8YAAIPAAYKEw7rBgBuAQAPAAYKEw7rBgBuAQA1AAQKfzcAAg8ACgrXIlkMAGADAA8ACgrXIlkMAGADAAAA.',
['Vã']='Vãsh:BAAANQAECgYIDAAAAA==.',
Wa='Wabbitseason:BAAANQADCgIIAgABNQAECgkJGQAIALwKAA==.Wabìsuke:BAAANQADCggIFQAAAA==.Waterlogged:BAAANQADCgQIEAAAAA==.Waterloo:BAAANQADCgYIDgAAAA==.',
Wi='Wizpigas:BAAANQADCgcIDQABNQAECggIIAAYAE8UAA==.',
['Wì']='Wìccka:BAAANQADCgUIBQAAAA==.',
Xi='Xi:BAAANQAECgMIAwAAAA==.Xifan:BAABNQAECn8ZAAIRAAoKfRRmEwBGAgARAAoKfRRmEwBGAgAAAA==.',
Yd='Yd:BAAANQAECgQIBAABNQAFFAEIBQAEAAAAAA==.',
Yg='Yggdrasill:BAAANQABCgUICAAAAA==.',
Yi='Yingpi:BAAANQABCgIIAgAAAA==.',
Yo='Yodaa:BAAANQADCggICwABNQAECgYIHAAHAGATAA==.',
Ys='Ys:BAAANQAECgQIBAABNQAFFAEIBQAEAAAAAA==.',
Yt='Yt:BAAANQAECgQICgABNQAFFAEIBQAEAAAAAA==.',
Yw='Ywontudie:BAAANQAECgEIAQAAAA==.',
Yz='Yz:BAACNQAFFH8FAAIEAAEKAAAnEQBlAAAEAAEKAAAnEQBlAAA1AAQKfy4AAwQACQrQIwsCAJoDAAQACQrQIwsCAJoDABwAAgpTGzqHAJUAAAAA.',
Za='Zashawa:BAAANQADCgYIEQAAAA==.',
Ze='Zenithgrey:BAABNQAECn8XAAMQAAkKMQ6ghwCRAQAQAAcKug6ghwCRAQAMAAUKJQ8KqgAdAQAAAA==.',
Zl='Zluco:BAACNQAFFH8JAAIhAAMKfx3fAAAfAQAhAAMKfx3fAAAfAQA1AAQKfzIAAyEACgowIMUDANkBACEACgowIMUDANkBAAwABgp5HAd+AJIBAAAA.',
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
