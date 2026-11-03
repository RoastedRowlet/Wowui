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

local lookup = {'Hunter-BeastMastery','Unknown-Unknown','Mage-Arcane','Rogue-Subtlety','Druid-Balance','Rogue-Assassination','DeathKnight-Blood','DeathKnight-Unholy','Paladin-Retribution','Mage-Frost','Warlock-Demonology','Druid-Restoration','Shaman-Restoration','Warrior-Protection','Priest-Shadow','Druid-Guardian','Priest-Holy','Shaman-Elemental','Monk-Mistweaver','Monk-Windwalker','Warlock-Destruction','Warlock-Affliction','Warrior-Arms','Druid-Feral','DeathKnight-Frost','Paladin-Protection','Warrior-Fury','Evoker-Devastation','Shaman-Enhancement','Priest-Discipline','Paladin-Holy','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Marksmanship','Monk-Brewmaster','Hunter-Survival','Mage-Fire','Evoker-Preservation','Evoker-Augmentation','Rogue-Outlaw','DemonHunter-Vengeance',}
local provider = {region='US',realm="Eldre'Thalas",name='US',type='weekly',zone=53,date='2026-11-03',data={Ad='Adesira:BAAANQAECgQIBQAAAA==.Adrastus:BAAANQAECgQIBAABNQAECgoKNwABAOEWAA==.Adurith:BAAANQABCgQIBAAAAA==.',
Ae='Aeslin:BAAANQADCgYJBgABNQAECgEIAQACAAAAAA==.',
Ah='Ahn:BAAANQAECgYIBgAAAA==.Ahtila:BAAANQADCgUIBwAAAA==.Ahylin:BAAANQADCgcIDQAAAA==.',
Ai='Ainslie:BAAANQAECgYIEAAAAA==.',
Al='Alerana:BAAANQAECgYIDAAAAA==.Alliane:BAAANQADCgEIAQAAAA==.Altria:BAAANQADCgUICQAAAA==.',
An='An:BAABNQAECn8YAAIDAAYKYRyh0wDfAQADAAYKYRyh0wDfAQABNQAFFAEIBQAEAAAAAA==.Anarose:BAAANQAECgUIEQABNQAECgcIIQAFANQDAA==.Antityk:BAABNQAECn8bAAMEAAgKIAvgUQBtAQAEAAgKNgrgUQBtAQAGAAQK7gowdADgAAABNQAECgoKNwABAOEWAA==.',
Ar='Aragorn:BAAANQADCgQIBQAAAA==.Arahant:BAAANQAECgIIAgAAAA==.Aretas:BAABNQAECn8oAAMHAAkKzhx8GQDiAgAHAAkKzhx8GQDiAgAIAAEK4Q3c4gAxAAAAAA==.Armadian:BAAANQAECgQICAAAAA==.Arrianne:BAAANQADCgYIBgAAAA==.Arriella:BAAANQAECgUIBQAAAA==.Arriånna:BAAANQADCgcIEwAAAA==.Artemist:BAABNQAECn8UAAIJAAYKqg2y9QAyAQAJAAYKqg2y9QAyAQAAAA==.',
As='Asifa:BAAANQAECgMIBgAAAA==.',
At='Atherion:BAABNQAECn8sAAIKAAkK6hEiCwATAgAKAAkK6hEiCwATAgAAAA==.Attackroot:BAAANQAECgUIBgABNQAECgcIGgALAFkMAA==.',
Au='Aurakk:BAAANQADCgYIEQABNQAECgcIKAAJALcTAA==.',
Av='Avelin:BAAANQADCgUIBgAAAA==.Avranarada:BAABNQAECn83AAMMAAoKDhYeIAAqAgAMAAoKDhYeIAAqAgAFAAkKCBbmIQC4AQAAAA==.Avril:BAAANQAECgEIAQAAAA==.',
Az='Azkara:BAACNQAFFH8NAAINAAUKpQ35EQD7AAANAAUKpQ35EQD7AAA1AAQKfzUAAg0ACgreHTkVAOICAA0ACgreHTkVAOICAAAA.Azung:BAABNQAECn8+AAIJAAoK3iC8JACpAgAJAAoK3iC8JACpAgAAAA==.',
Ba='Baatos:BAEANQAECggIAgABNQAECgkJGAALALcKAA==.Babaisyaga:BAACNQAFFH8VAAIBAAUKXiIKCwASAQABAAUKXiIKCwASAQA1AAQKf1AAAgEACgpqJEYKACQDAAEACgpqJEYKACQDAAAA.Baka:BAAANQAECgYICQAAAA==.Balinse:BAABNQAECn8cAAIOAAgK2hUMGQChAQAOAAgK2hUMGQChAQABNQAECgoKHQAPAMsNAA==.Balystix:BAAANQADCggICAAAAA==.Barb:BAAANQAECgcIBwAAAA==.Barrelrollin:BAAANQAECgEIAQAAAA==.Basherdownn:BAAANQADCgQIBAAAAA==.',
Be='Beastfodays:BAACNQAFFH8JAAIBAAMKrhRiHQDIAAABAAMKrhRiHQDIAAA1AAQKfzIAAgEACQpxGctDAKACAAEACQpxGctDAKACAAAA.Becia:BAAANQADCgEIAQABNQAECgQICAACAAAAAA==.Bethlahammer:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.',
Bh='Bhassie:BAAANQADCgcIBwABNQAFFAUIDwAQAO8OAA==.',
Bi='Bigbeans:BAAANQADCgEIAQAAAA==.Billcritin:BAAANQAECggIEAAAAA==.',
Bl='Blackleaf:BAAANQADCgcICgAAAA==.Blawyke:BAAANQAECggIDwABNQAFFAIIBAACAAAAAA==.Bless:BAAANQADCggIDgABNQAECgYICgACAAAAAA==.Blizzcon:BAACNQAFFH8TAAIRAAUKexioDwCZAQARAAUKexioDwCZAQA1AAQKf0UAAhEACgr2I2sJAHcDABEACgr2I2sJAHcDAAAA.Bloodsurge:BAAANQADCgQJAwAAAA==.Blushies:BAABNQAECn8rAAMSAAgKGh8bGwBrAgASAAgKGh8bGwBrAgANAAMK8xC64wCiAAAAAA==.',
Bo='Boltzfodayz:BAAANQAECgEIAQAAAA==.Bonerslap:BAAANQAECgQIBQAAAA==.Boone:BAAANQADCgMIAwAAAA==.Borrgar:BAABNQAECn8oAAIJAAcKtxPE1AByAQAJAAcKtxPE1AByAQAAAA==.',
Br='Brackle:BAABNQAECn8eAAIBAAkKCxuQQgCjAgABAAkKCxuQQgCjAgAAAA==.Bracori:BAACNQAFFH8OAAITAAUKSgwxBQAEAQATAAUKSgwxBQAEAQA1AAQKf0IAAxMACgqIGRwJAIsCABMACgqIGRwJAIsCABQAAQoAAP1iAAAAAAAA.Brandywynne:BAABNQAECn8sAAIBAAoKsA+4ZQBJAgABAAoKsA+4ZQBJAgAAAA==.Bretcha:BAAANQADCgQIBQABNQAECgQIBgACAAAAAA==.Brick:BAABNQAECn8qAAIEAAoKcxeeDQCcAgAEAAoKcxeeDQCcAgAAAA==.Brightfame:BAABNQAECn80AAMVAAoKCBZgBwAxAQAVAAgKZRVgBwAxAQAWAAUKHhTpEQAsAQAAAA==.Bronny:BAABNQAECn8dAAIXAAgK7A3VuACOAQAXAAgK7A3VuACOAQAAAA==.Brônwyn:BAAANQADCgQIBQAAAA==.',
Bu='Buffshagwell:BAABNQAECn8pAAIJAAkKhxdqWQCLAgAJAAkKhxdqWQCLAgAAAA==.Bullrush:BAAANQADCgYICAAAAA==.Butterbllz:BAABNQAECn8pAAIJAAoKhxs/XgB+AgAJAAoKhxs/XgB+AgAAAA==.',
Ca='Caerhysa:BAAANQADCgQIBAAAAA==.Calypsio:BAAANQADCgQIBAABNQAECgMIAwACAAAAAA==.Camany:BAABNQAECn8fAAIBAAgKExGMdwAgAgABAAgKExGMdwAgAgAAAA==.Captinkrunch:BAAANQADCgEIAQAAAA==.Captinlock:BAAANQADCgEIAQABNQADCgEIAQACAAAAAA==.Captinmorí:BAAANQADCgEIAQAAAA==.Caretakerz:BAABNQAECn8tAAMQAAkKsB2yCwCuAgAQAAkKsB2yCwCuAgAYAAEKjg07PwAtAAAAAA==.Cartus:BAAANQAECgUICAABNQAECgcIFQAQAAUJAA==.Cayin:BAABNQAECn8cAAIHAAkKSiDsEwANAwAHAAkKSiDsEwANAwABNQABCgYICwACAAAAAA==.',
Ce='Cedre:BAAANQADCgEIAQAAAA==.Celestine:BAAANQADCgEIAQAAAA==.',
Ch='Chanyeol:BAAANQAECggIEQAAAA==.Chemoshh:BAAANQADCggIBgABNQAECgcIKAAJALcTAA==.',
Cl='Clamshell:BAABNQAECn82AAMZAAoKKCJwCQD+AgAZAAoKKCJwCQD+AgAHAAUKwRi0YgBnAQAAAA==.Claudette:BAAANQAECgcICgAAAA==.Clayier:BAAANQADCgcIGQAAAA==.',
Cn='Cntendr:BAAANQADCgUICQAAAA==.',
Co='Codenike:BAABNQAECn8qAAIUAAgKXhkEHACOAQAUAAgKXhkEHACOAQAAAA==.Coil:BAAANQADCggICgABNQAECgYICgACAAAAAA==.Copenzen:BAAANQAECgcIDAAAAA==.Corelheals:BAAANQAECgUIDgAAAA==.Covertyqt:BAABNQAECn8tAAIDAAoKQBxuRwARAgADAAoKQBxuRwARAgAAAA==.',
Cp='Cptnhuman:BAABNQAECn8yAAIIAAoKPh1HEABVAgAIAAoKPh1HEABVAgAAAA==.',
Cr='Cromie:BAAANQADCggIFwAAAA==.Crosed:BAAANQADCgQIBAAAAA==.',
Cs='Cshunter:BAAANQADCgYIBwAAAA==.',
Cu='Cubcakes:BAAANQADCggIBgAAAA==.',
Cy='Cylcuria:BAAANQABCgIIAgAAAA==.',
['Cõ']='Cõrpses:BAEBNQAECn8mAAIHAAoKIx/yFABAAgAHAAoKIx/yFABAAgABNQAECgoKHgAQAPMhAA==.',
Da='Daboof:BAAANQADCggIJAAAAA==.Daemandred:BAAANQADCgUIBgAAAA==.Daggere:BAAANQADCggIKQAAAA==.Danilo:BAAANQADCgEIAQAAAA==.Danke:BAAANQAECgYICQAAAA==.Dankz:BAAANQAECgUICQAAAA==.Darkenmicky:BAAANQADCgcIEwAAAA==.Darkmickyz:BAABNQAECn8YAAIaAAcK1RDnNQA4AQAaAAcK1RDnNQA4AQAAAA==.Darthbobula:BAACNQAFFH8JAAIJAAQKKQetFgCwAAAJAAQKKQetFgCwAAA1AAQKfxcAAgkACArFDAbfAF0BAAkACArFDAbfAF0BAAAA.Dayloc:BAABNQAECn8iAAILAAoKsAvKWwCHAQALAAoKsAvKWwCHAQAAAA==.',
De='Deataria:BAABNQAECn8pAAIMAAkKdxnTFAA1AgAMAAkKdxnTFAA1AgAAAA==.Deathrho:BAAANQADCgUICwAAAA==.Deawin:BAAANQADCgQIBAABNQAECgEIAQACAAAAAA==.Delilia:BAEANQAECggICgABNQAECgkJGAALALcKAA==.Delort:BAAANQADCgEIAQAAAA==.Delryth:BAAANQADCgYIBQAAAA==.Demonikk:BAAANQAECgYIDgABNQAECgoKNwABAOEWAA==.Demontyk:BAAANQAECgYIEAABNQAECgoKNwABAOEWAA==.Desception:BAAANQADCgcICgAAAA==.Devourmax:BAABNQAECn8UAAIbAAoKNASRGAC3AAAbAAoKNASRGAC3AAAAAA==.',
Di='Diablõ:BAEANQAECggIDgABNQAECgoKHgAQAPMhAA==.Diadochi:BAAANQAECgQJBQAAAA==.Dieguerta:BAAANQADCgEJAQAAAA==.',
Dl='Dl:BAABNQAECn8yAAIPAAoK2Bm9GQCAAgAPAAoK2Bm9GQCAAgAAAA==.',
Dr='Drakkarr:BAAANQADCgYIBwAAAA==.Drazhoath:BAAANQAECgUIDQAAAA==.Drdrill:BAAANQADCgYIBgAAAA==.Drimbirt:BAAANQADCgcICgAAAA==.Drinkmormilk:BAAANQAECgMIBAAAAA==.Drogelf:BAAANQADCgcIGQAAAA==.Drogman:BAAANQADCgIIAgAAAA==.',
Du='Dumbledore:BAAANQADCgcICAABNQAECgEIAQACAAAAAA==.',
['Dá']='Dáwnbringer:BAAANQADCgIIBAAAAA==.',
Eb='Ebullition:BAAANQAECgcICAAAAA==.',
Ed='Edensfury:BAAANQAECgIIAgAAAA==.',
Ee='Eedani:BAAANQADCgUJCgAAAA==.',
Ei='Eigi:BAABNQAECn8iAAIBAAoKQxU9TgDzAQABAAoKQxU9TgDzAQAAAA==.',
El='Eldanon:BAABNQAECn9AAAIVAAoKhyMfAQCRAwAVAAoKhyMfAQCRAwAAAA==.Elementality:BAAANQADCgIIAgAAAA==.Eleyert:BAACNQAFFH8QAAISAAUKSiWQBgBKAQASAAUKSiWQBgBKAQA1AAQKfzEAAhIACgpRJs0BAHkDABIACgpRJs0BAHkDAAAA.Elistann:BAAANQAECgQIBAABNQAECgcIKAAJALcTAA==.Elwe:BAABNQAECn8gAAIRAAgKJhXMcgDEAQARAAgKJhXMcgDEAQAAAA==.',
Em='Embaku:BAAANQADCggICQABNQAECgoKPwAJAGgUAA==.Emiri:BAAANQAECgQIBQAAAA==.Emrhakul:BAAANQADCgEIAQAAAA==.',
En='Enkidu:BAABNQAECn8mAAIBAAcKFxG+nwAuAQABAAcKFxG+nwAuAQAAAA==.Enseth:BAABNQAECn8vAAIcAAkKfgq1CwBpAQAcAAkKfgq1CwBpAQAAAA==.',
Er='Erakha:BAAANQAECgQIBgAAAA==.Erandria:BAAANQADCgcIDAABNQAECgQICAACAAAAAA==.',
Eu='Eulogy:BAAANQADCgYICQABNQAFFAUIEwARAHsYAA==.',
Ez='Ezki:BAAANQADCggIFwABNQAECgcIKAAJALcTAA==.',
Fa='Fairious:BAABNQAECn82AAIEAAkKDBkKFABIAgAEAAkKDBkKFABIAgAAAA==.Faror:BAAANQADCgEIAQAAAA==.',
Fe='Felcon:BAAANQADCgYICQAAAA==.Felenkeller:BAAANQAECgIIBgABNQAFFAYICgAIAOAWAA==.Fenrirr:BAAANQADCggICAABNQAECgcIKAAJALcTAA==.Fet:BAABNQAECn8rAAMGAAoKSyDoCgD+AQAEAAgKDR6PEQBoAgAGAAkK5R3oCgD+AQAAAA==.',
Fh='Fhatbashtud:BAAANQAECgMIBwAAAA==.',
Fl='Flashfiré:BAAANQAECgQIAwABNQAECgoKNAAdAOIcAA==.Flashies:BAAANQAECgQIBgABNQAECggIKwASABofAA==.Flatline:BAABNQAECn8fAAIeAAcKFxrkBwDxAQAeAAcKFxrkBwDxAQAAAA==.Flinnt:BAAANQADCgUICAABNQAECgcIKAAJALcTAA==.',
Fn='Fngusamungus:BAAANQAECgEIAQAAAA==.',
Fo='Folgore:BAAANQAECgUIBwAAAA==.Four:BAAANQAECgcIEAAAAA==.',
Fr='Fredwarlock:BAAANQAECgUIBwAAAA==.Frysky:BAABNQAECn8aAAMYAAkKFAwYGAB4AQAYAAgKGw0YGAB4AQAFAAkKWAY4OgATAQAAAA==.',
Fu='Furiousv:BAAANQADCgUIBQAAAA==.Futz:BAABNQAECn82AAIfAAoK1iIQHgD5AgAfAAoK1iIQHgD5AgAAAA==.',
Ga='Gahnzul:BAAANQADCgUICgAAAA==.Gajitbek:BAAANQADCgUICAAAAA==.Galah:BAABNQAECn8YAAIDAAcK4g498gCmAQADAAcK4g498gCmAQAAAA==.Gardurst:BAABNQAECn8tAAISAAoKVhswIABDAgASAAoKVhswIABDAgAAAA==.',
Gn='Gnomicide:BAAANQAECgMICAAAAA==.',
Go='Gonesh:BAAANQADCggIEAAAAA==.Gooberpea:BAAANQADCgEIAQAAAA==.Gordoe:BAAANQADCgUICgAAAA==.',
Gr='Graveborne:BAAANQADCggIEQAAAA==.Gravess:BAAANQADCgUIDQAAAA==.Gravewin:BAAANQADCgQICgABNQAECgEIAQACAAAAAA==.Gravyexpress:BAABNQAECn9YAAMgAAoKBhw/FwDhAgAgAAoK6Bs/FwDhAgAhAAcKxhTCPQBbAQAAAA==.Grendelheim:BAAANQADCggIJgAAAA==.Grogar:BAAANQADCgcIFQAAAA==.Groxxigar:BAAANQADCgUIBQAAAA==.',
Gu='Gula:BAAANQAECgUICwABNQAECgcIHAAUABgRAA==.',
Ha='Hadez:BAAANQADCgUIBQAAAA==.Hairybubble:BAAANQADCggICAAAAA==.Hantak:BAAANQADCgMIBgAAAA==.Harmsway:BAAANQADCgcJEQAAAA==.Hathaendron:BAAANQADCgYIBwAAAA==.',
He='Hephaestus:BAAANQAECgUICAAAAA==.',
Ho='Hocka:BAAANQADCgUIBwAAAA==.Holysmight:BAAANQAECgEIAQAAAA==.Holyumo:BAAANQADCgYIBgAAAA==.Holyyballs:BAAANQAECgcICQABNQAECgkJGwADAPkKAA==.Howlymandel:BAAANQAECggICAABNQAECgkJGwABAA4IAA==.Hoytx:BAAANQADCgUIBQAAAA==.',
Hy='Hydraciel:BAAANQAECgYIDgAAAA==.',
['Hì']='Hìroko:BAABNQAECn8aAAMVAAcKKAbFOwDSAAAVAAYKzwPFOwDSAAALAAcKBwXiqwDIAAAAAA==.',
Ic='Icedemon:BAABNQAECn8UAAMHAAcKJxg2JQCnAQAHAAcKJxg2JQCnAQAZAAEKTwrxnQA1AAAAAA==.Iceliandra:BAAANQADCggIDgAAAA==.Iceveloric:BAAANQADCgYIAwAAAA==.Icupapi:BAAANQADCggILwAAAA==.Icynips:BAAANQADCgEIAQAAAA==.',
Ig='Ignitionfish:BAAANQAECgIIAgABNQAECggIKwASABofAA==.',
Im='Im:BAAANQADCgEJAQABNQAFFAEIBQAEAAAAAA==.Imabigman:BAAANQADCgcICQAAAA==.Imaleaf:BAABNQAECn8aAAIFAAgKMQbsXQBZAQAFAAgKMQbsXQBZAQAAAA==.Imperius:BAAANQAECgEIAQAAAA==.',
In='Insillico:BAAANQAECgEIAQABNQAECgoKNwABAOEWAA==.',
Ip='Iplaydead:BAABNQAECn83AAMBAAoK4RbANABDAgABAAoK4RbANABDAgAiAAEKAACnmgAmAAAAAA==.',
Ir='Iroh:BAABNQAECn8aAAIUAAgKvBoNIQAkAgAUAAgKvBoNIQAkAgAAAA==.',
Is='Ismokeprot:BAAANQADCgQIBAAAAA==.',
Ja='Jacii:BAAANQAECggICwABNQAECgoKNgAZACgiAA==.Jarinduva:BAAANQADCgEIAgAAAA==.Jarofeyes:BAAANQADCgEIAQAAAA==.Jawnson:BAABNQAECn8VAAIEAAgKeg4KHAD1AQAEAAgKeg4KHAD1AQAAAA==.',
Je='Jelluz:BAAANQADCgYIBwAAAA==.Jenefer:BAACNQAFFH8OAAIHAAUKhx2TDgDaAAAHAAUKhx2TDgDaAAA1AAQKf0IAAwcACgoXILUKAM4CAAcACgoXILUKAM4CAAgAAgrsFBS4AH0AAAAA.Jeslartoma:BAAANQADCgEIAQABNQAECgMIAwACAAAAAA==.',
Ji='Jimjimmy:BAAANQADCgcIBwABNQAECgIIAgACAAAAAA==.',
Jo='Jondooz:BAAANQAECgcIBwAAAA==.Jonoisanerd:BAAANQADCgEIAQAAAA==.Joulecrafter:BAAANQAECgUIBQABNQAECgoKPwAJAGgUAA==.',
Jp='Jpegz:BAAANQADCgcIBgABNQAECgoKRgAJAIIiAA==.',
Ka='Kailana:BAAANQAECgEIAgABNQAECgoKNAAdAOIcAA==.Kailback:BAAANQAECgcIEAABNQAECgoKNAAdAOIcAA==.Kait:BAABNQAECn81AAMNAAoKHhp5FQDgAgANAAoKHhp5FQDgAgASAAQKKQwdnQCZAAAAAA==.Kalcifur:BAACNQAFFH8PAAMfAAUKGBSRDQAwAQAfAAUKGBSRDQAwAQAaAAEKGgz7EgA2AAA1AAQKf0IAAx8ACgqKIosDANYDAB8ACgqKIosDANYDABoAAwqRGsBNAE8AAAAA.Kalidorn:BAAANQADCgEIAQAAAA==.Kallevald:BAAANQADCgEIAQAAAA==.Karin:BAAANQAECgIIAwABNQAECgcIFQAQAAUJAA==.Karnelian:BAAANQAECgYICwABNQAECgoKJAATAGUjAA==.Karras:BAAANQADCgUIBQAAAA==.Kashisht:BAAANQAECgIIAgAAAA==.Kasstigate:BAABNQAECn8lAAIXAAoKERinMABWAgAXAAoKERinMABWAgABNQAFFAUIDgAHAIcdAA==.Kastiel:BAABNQAECn8dAAIPAAoKyw3uLQC2AQAPAAoKyw3uLQC2AQAAAA==.Katstrider:BAABNQAECn83AAIBAAoK+hb6UgDmAQABAAoK+hb6UgDmAQAAAA==.Kattarea:BAAANQADCgUJCQABNQAECgoKNwABAPoWAA==.Kavica:BAAANQAECggIDQABNQAECgoKMAAMAEshAA==.',
Ke='Keldean:BAABNQAECn8aAAIOAAgK5h2ACgCZAgAOAAgK5h2ACgCZAgAAAA==.Keryka:BAACNQAFFH8PAAMZAAUKliIWCQABAQAZAAUKliIWCQABAQAIAAEKZRJXIQBHAAA1AAQKf0AAAxkACgrnILUKAEQDABkACgq3HrUKAEQDAAgACArMGy1FAAQCAAAA.',
Kh='Khere:BAAANQAECgQIBQAAAA==.',
Ki='Kirigiri:BAAANQAECggIDwABNQAFFAUIDwAfABgUAA==.Kirøs:BAAANQAECgQIBQAAAA==.Kiterisa:BAABNQAECn83AAINAAoKIgwvQQDfAQANAAoKIgwvQQDfAQAAAA==.',
Kk='Kkazz:BAAANQADCggICwABNQAECgcIKAAJALcTAA==.',
Ko='Kohn:BAAANQAECggIDwAAAA==.Kona:BAEBNQAECn8eAAQQAAoK8yHuDQAfAgAQAAoK8yHuDQAfAgAYAAcK9BoqDAC9AQAMAAIKkQEWcgAfAAAAAA==.Korbusty:BAAANQADCggIDwAAAA==.',
Ku='Kuattieb:BAAANQADCgEIAQAAAA==.',
La='Ladýfinger:BAABNQAECn84AAQfAAoKAhJ8YQD0AQAfAAkKWBN8YQD0AQAaAAgKEguVHgBEAQAJAAQKJghDWwGOAAABNQAFFAUIDwAQAO8OAA==.Laisidhiel:BAAANQAECgUICQAAAA==.Lateo:BAABNQAECn8oAAIEAAoKKQuoTACBAQAEAAoKKQuoTACBAQAAAA==.Lawz:BAABNQAECn8gAAMWAAkKzgXFEABAAQAWAAkKzgXFEABAAQAVAAIKOAAGegA0AAAAAA==.',
Le='Lelianna:BAAANQADCggILgAAAA==.Lemonruss:BAAANQADCggIEQAAAA==.Levibigguns:BAAANQADCggICwABNQAECggIKwAUAFUUAA==.Lexia:BAAANQAECgYICwAAAA==.',
Li='Liandria:BAAANQADCgEIAgABNQAECgcICgACAAAAAA==.Libidine:BAAANQADCgQIBAABNQAECgcIHAAUABgRAA==.Liemannin:BAAANQAECgEIAQAAAA==.Lightninghah:BAAANQADCgEIAQABNQADCgEIAQACAAAAAA==.Lilaa:BAAANQADCgcICAAAAA==.Lilturtz:BAAANQAECgUIBgABNQAECggIKwASABofAA==.Linnea:BAAANQADCgcIDQAAAA==.',
Lo='Locksative:BAAANQADCggIKAAAAA==.Longhorn:BAABNQAECn80AAIJAAkK7Q6klQBgAQAJAAkK7Q6klQBgAQAAAA==.Lore:BAAANQADCgEIAQABNQAECgQIBAACAAAAAA==.Lorekesh:BAAANQADCgEJAgABNQAECgcICgACAAAAAA==.Lorriena:BAAANQAECgEIAQABNQAECgIIAwACAAAAAA==.Lorrè:BAAANQADCgQIBAABNQAECgIIAwACAAAAAA==.Lortpegsalot:BAABNQAECn9GAAIJAAoKgiJoGgDdAgAJAAoKgiJoGgDdAgAAAA==.Lowy:BAAANQAECgUIAwAAAA==.',
Lu='Lucena:BAABNQAECn8nAAIRAAgKTyN6EQAjAwARAAgKTyN6EQAjAwAAAA==.Lurg:BAAANQADCggICgABNQADCggIKAACAAAAAA==.Luxuria:BAAANQAECgYICgABNQAECgcIHAAUABgRAA==.',
Ly='Lyralana:BAAANQAECgQICAAAAA==.',
Ma='Maberu:BAACNQAFFH8HAAITAAQK7gOxBQDdAAATAAQK7gOxBQDdAAA1AAQKfyMAAhMACgqyDWscAL0BABMACgqyDWscAL0BAAE1AAUUBQgPAB8AGBQA.Madamholy:BAABNQAECn8YAAIRAAcKXR9aTQDKAQARAAcKXR9aTQDKAQAAAA==.Madamkluck:BAAANQADCgUIBQAAAA==.Maglubiyet:BAABNQAECn8UAAIdAAYKJwyEIADeAAAdAAYKJwyEIADeAAAAAA==.Magnitood:BAABNQAECn8UAAMMAAYKVxbUMgCEAQAMAAYKVxbUMgCEAQAFAAEKAAB+rgA5AAAAAA==.Malbjornion:BAAANQAECgYIDQAAAA==.Malphox:BAAANQADCgQICAAAAA==.Manbearcat:BAABNQAECn8VAAIQAAcKBQm/NgDwAAAQAAcKBQm/NgDwAAAAAA==.Manhole:BAAANQAECgQIDAAAAA==.Markyb:BAAANQADCggIEgAAAA==.Masamura:BAACNQAFFH8SAAMDAAYK5hQKHADvAAADAAUKExcKHADvAAAKAAIKfwchCgBxAAA1AAQKfzwAAwMACgqdHHpnAK8CAAMACgo/G3pnAK8CAAoAAgo0G+YrAJwAAAAA.Maureanna:BAAANQADCgUIEQABNQAECgQICAACAAAAAA==.',
Me='Mechahuntard:BAAANQADCgEIAQAAAA==.Medanii:BAEBNQAECn8fAAQeAAkKghFeDQBeAQAeAAYKVRJeDQBeAQARAAUKUREcrAASAQAPAAQKTQenVwCsAAAAAA==.Melorm:BAAANQAECgQIDgAAAA==.',
Mi='Millizh:BAACNQAFFH8YAAMBAAgKoh6tBwDUAQABAAUKLiCtBwDUAQAiAAUKqhucDwBDAQA1AAQKfycAAyIACgrEJBsGAG8DACIACQpXJhsGAG8DAAEABwqvH/WRAOUBAAAA.Mirasharu:BAAANQADCggIKAAAAA==.Mireille:BAAANQADCgYIDgAAAA==.Mitsuri:BAABNQAECn8qAAIJAAgKxA+PnABTAQAJAAgKxA+PnABTAQAAAA==.Mitzuky:BAAANQADCgMIAwAAAA==.',
Mo='Mommamoon:BAAANQADCgQIBAABNQAECgoKIQAJAM0ZAA==.Moonlïght:BAABNQAECn8hAAIJAAoKzRl1SgAWAgAJAAoKzRl1SgAWAgAAAA==.Morganlefay:BAABNQAECn8gAAILAAkKKwJAwwCbAAALAAkKKwJAwwCbAAAAAA==.Morlyn:BAABNQAECn8lAAIKAAgKlhZFDQDdAQAKAAgKlhZFDQDdAQAAAA==.Morregan:BAAANQAECgcICAAAAA==.Motion:BAAANQADCgcICQABNQAECgYICgACAAAAAA==.Mousereaper:BAABNQAECn8kAAIhAAoKtg/7IQBYAQAhAAoKtg/7IQBYAQAAAA==.',
My='Mydnight:BAAANQADCgEIAQAAAA==.Mystìc:BAABNQAECn80AAQdAAoK4hynDAAXAgAdAAkKPhynDAAXAgASAAYKOxzObADaAQANAAEKaQr2IwEpAAAAAA==.Mystíc:BAAANQAECgYICAABNQAECgoKNAAdAOIcAA==.',
['Má']='Májorrobot:BAABNQAECn8tAAIXAAoKzyEIIwCXAgAXAAoKzyEIIwCXAgAAAA==.',
['Mé']='Ménopáwz:BAABNQAECn8YAAIQAAkKoBQbEQDoAQAQAAkKoBQbEQDoAQABNQAFFAYICgAIAOAWAA==.',
Na='Namor:BAAANQAECgIIAQAAAA==.Nattisca:BAAANQAECgMIAwAAAA==.',
Ne='Nemein:BAAANQADCgEIAQAAAA==.Nervanna:BAAANQAECgMIAwABNQAFFAEIAQACAAAAAA==.Nessà:BAABNQAECn8cAAMUAAcKGBEHJwAoAQAUAAcKhBAHJwAoAQAjAAEKKw+sIQA2AAAAAA==.Neveen:BAAANQAECgMIAwAAAA==.Neveenn:BAABNQAECn9AAAMMAAoKJR0PDwDkAgAMAAoKJR0PDwDkAgAQAAMKIQQJXAA8AAAAAA==.',
Ni='Nirith:BAAANQADCgYIEwAAAA==.Niteskye:BAAANQADCgEIAQAAAA==.',
No='Nohatcat:BAAANQAECgQIBgABNQAECggIKwASABofAA==.Notoom:BAAANQADCgEIAQAAAA==.',
['Nâ']='Nâmii:BAAANQAECgMIAwAAAA==.',
['Nè']='Nèzukõ:BAABNQAECn8hAAIBAAgKYxiHiwDzAQABAAgKYxiHiwDzAQAAAA==.',
Ob='Obata:BAAANQAECgQIBQAAAA==.',
Oc='Octavius:BAAANQADCggJDQABNQAECgIIAgACAAAAAA==.',
Od='Odi:BAAANQADCgQIBAAAAA==.',
Oj='Ojore:BAEBNQAECn8hAAIZAAgKagxhUgBnAQAZAAgKagxhUgBnAQAAAA==.Ojoverde:BAACNQAFFH8OAAILAAUKrgcqFgDIAAALAAUKrgcqFgDIAAA1AAQKf0IAAgsACgpBFCA8APEBAAsACgpBFCA8APEBAAAA.',
Ol='Olórin:BAAANQADCgEIAQAAAA==.',
On='Onizuka:BAAANQADCgEIAQABNQADCgcICQACAAAAAA==.Onside:BAAANQAECgcICgABNQAFFAUICgAUAAcVAA==.',
Op='Ophillã:BAABNQAECn8aAAMPAAYKnBOSQAArAQAPAAYKnBOSQAArAQAeAAUKVR3zCADvAAABNQAECgcIHAAUABgRAA==.',
Or='Ordenn:BAAANQADCgQICAABNQAECgoKKwAGAEsgAA==.Orian:BAAANQADCgQIBwAAAA==.',
Oz='Ozz:BAABNQAECn8ZAAIUAAgKFw/aLgChAQAUAAgKFw/aLgChAQAAAA==.Ozzerker:BAAANQADCgEIAQAAAA==.Ozzullr:BAABNQAECn8XAAIBAAkKAht3MgDVAgABAAkKAht3MgDVAgAAAA==.',
Pa='Painbreak:BAAANQADCgEIAgABNQAECgkJLQAQALAdAA==.Pajamas:BAAANQAECgEIAQABNQAECgcIGgALAFkMAA==.Pallanquin:BAAANQADCgYIDgAAAA==.Papichili:BAAANQAECgUIEAAAAA==.Pashnir:BAAANQADCgcICgAAAA==.',
Pe='Peachey:BAABNQAECn8jAAINAAkKWxaQRgDGAQANAAkKWxaQRgDGAQAAAA==.Peaker:BAAANQAECgQIAwAAAA==.Peakra:BAABNQAECn8iAAIRAAoKxRY/LABhAgARAAoKxRY/LABhAgAAAA==.Petre:BAAANQADCgEIAQAAAA==.',
Ph='Phoênix:BAAANQADCgMIAwAAAA==.',
Pi='Pigas:BAABNQAECn8rAAIUAAgKVRRiKADdAQAUAAgKVRRiKADdAQAAAA==.',
Pr='Prestoresto:BAAANQADCgYIDwAAAA==.',
Ps='Psychosix:BAABNQAECn8dAAIDAAoKcR9mSwDrAgADAAoKcR9mSwDrAgAAAA==.',
Qu='Quinberos:BAAANQAECgUICgAAAA==.',
Ra='Racey:BAAANQADCggICQAAAA==.Raiistlin:BAAANQADCgYIBwABNQAECgcIKAAJALcTAA==.Ramdel:BAAANQAECgQIBgABNQAECgoKQQAkAN0aAA==.Ramstrider:BAABNQAECn9BAAMkAAoK3RqHAgCDAgAkAAoK3RqHAgCDAgABAAIKaQcTOAF2AAAAAA==.Ranah:BAAANQAECgQIBAABNQAECgcICAACAAAAAA==.Ranch:BAAANQADCgcICQAAAA==.Rapture:BAABNQAECn84AAIhAAoKjQ6IGQCuAQAhAAoKjQ6IGQCuAQAAAA==.Ravec:BAAANQADCgMIAwAAAA==.Rayziel:BAAANQADCggICAABNQAECgMIBQACAAAAAA==.',
Re='Reign:BAAANQADCgEIAQABNQAECgQIBAACAAAAAA==.Rengell:BAABNQAECn8bAAIBAAkKDgjPuQD6AAABAAkKDgjPuQD6AAAAAA==.Reptiliano:BAAANQAECggIEQABNQAFFAUIBwAGAJwOAA==.',
Rh='Rheagall:BAABNQAECn81AAIdAAoKxx/fBgAUAwAdAAoKxx/fBgAUAwAAAA==.Rhodetta:BAABNQAECn8bAAIRAAoKAxS5OgB+AgARAAoKAxS5OgB+AgABNQAFFAEIAQACAAAAAA==.',
Ri='Rizepriest:BAAANQADCgIIAgABNQAECgcIFAAXAEghAA==.Rizerage:BAABNQAECn8UAAIXAAcKSCENbABOAgAXAAcKSCENbABOAgAAAA==.',
Ro='Roaraxe:BAAANQADCgYIBgABNQAECgIIAgACAAAAAA==.Rowena:BAABNQAECn9BAAIFAAoKpxXiIgCvAQAFAAoKpxXiIgCvAQAAAA==.Rowynna:BAAANQAECgMIAwABNQAECgUICgACAAAAAA==.Roxy:BAAANQADCgYIBgAAAA==.Roxymonk:BAAANQADCgYIBgAAAA==.Royalviaman:BAAANQADCgcICgAAAA==.',
Ry='Ryz:BAAANQADCggICAAAAA==.Ryztkmtchrch:BAACNQAFFH8FAAIRAAIKdhzOIACmAAARAAIKdhzOIACmAAA1AAQKfzcABBEACgoKHWcyAJ4CABEACgoKHWcyAJ4CAB4ABwrDDe8MAGgBAA8ABQqMDzNHAAIBAAAA.',
['Rå']='Råti:BAAANQAECgQIAwAAAA==.',
Sa='Sacdk:BAAANQAECgQIBwAAAA==.Safaria:BAAANQAECgQIBwABNQAECgUIFAARAGgJAA==.Saloenus:BAAANQAECgYICgAAAA==.Sarnoxia:BAAANQADCgEIAQAAAA==.Saucehoss:BAABNQAECn8mAAQWAAkKQx3sAwCrAgAWAAkKQx3sAwCrAgAVAAQKLQ8MPQDNAAALAAMKkhTNBQHAAAAAAA==.Saucymac:BAACNQAFFH8IAAMPAAQKbAgKCgDMAAAPAAMKbAgKCgDMAAARAAMKywG+IACnAAA1AAQKfx8AAw8ACgpeH1wRAA0CAA8ACArXHVwRAA0CABEACQpaBvq0APgAAAAA.',
Sc='Scofflaw:BAAANQADCgEIAQABNQAECgQIBAACAAAAAA==.Scootr:BAAANQAECgcICQAAAA==.Scubasteve:BAAANQADCgUICgAAAA==.',
Se='Sefi:BAABNQAECn8wAAMJAAgKCRMyqwDJAQAJAAgKIRIyqwDJAQAaAAQKlQ3+TgCsAAAAAA==.Seleneluna:BAAANQADCgEIAQAAAA==.Semirrhage:BAAANQADCgMIAwAAAA==.',
Sh='Shadowflame:BAABNQAECn8aAAILAAcKWQxrlgD2AAALAAcKWQxrlgD2AAAAAA==.Shallator:BAAANQAECgQIBAAAAA==.Shamanigans:BAAANQAECgMIBwABNQAECgYIFAAMAFcWAA==.Shammygoat:BAABNQAECn8gAAISAAcK8RpJfwCnAQASAAcK8RpJfwCnAQAAAA==.Shaqattack:BAACNQAFFH8KAAIUAAUKBxW9BwDYAAAUAAUKBxW9BwDYAAA1AAQKfzkAAhQACgoIIN0IALkCABQACgoIIN0IALkCAAAA.Shaqattaq:BAABNQAECn8iAAMEAAoK8hroHgBmAgAGAAkK8heZIwBrAgAEAAkKnxjoHgBmAgABNQAFFAUICgAUAAcVAA==.Sharktide:BAABNQAECn8kAAINAAoK0xbZXwDvAQANAAoK0xbZXwDvAQAAAA==.Shawnella:BAABNQAECn8yAAMUAAoK4x7kDQBQAgAUAAkKMx7kDQBQAgATAAIKTQf1RABYAAAAAA==.Shenlune:BAAANQAECgYIEQAAAA==.Sheutka:BAAANQAECgMICAAAAA==.Shiggles:BAAANQAECgIIAQAAAA==.Shinaie:BAABNQAECn8ZAAIPAAgKxQp8OABhAQAPAAgKxQp8OABhAQAAAA==.Shocknrollz:BAAANQAECgQIDAAAAA==.Shogún:BAABNQAECn8qAAIHAAkKlx3/EAByAgAHAAkKlx3/EAByAgAAAA==.Shran:BAAANQADCgEIAQAAAA==.Shtylez:BAAANQAECgcIEAABNQAECgoKNwABAOEWAA==.',
Si='Silntwolf:BAAANQADCgEIAgAAAA==.Silpion:BAABNQAECn8UAAIlAAcKTgeWBQAiAQAlAAcKTgeWBQAiAQAAAA==.Silth:BAAANQADCggIKQAAAA==.Sinariel:BAABNQAECn83AAITAAoK9BztBgDeAgATAAoK9BztBgDeAgAAAA==.Sirdank:BAAANQAECgIIBAAAAA==.',
Sk='Skarlate:BAAANQADCgYIBgAAAA==.Skâld:BAEANQADCgYICwAAAA==.',
Sl='Sliko:BAABNQAECn9JAAIJAAoKTRaFWgDoAQAJAAoKTRaFWgDoAQAAAA==.',
Sm='Smmoke:BAABNQAECn83AAIBAAoK9RcBRQAOAgABAAoK9RcBRQAOAgAAAA==.',
Sn='Sneekyone:BAAANQABCgUIBwAAAA==.Sneekypally:BAABNQAECn8hAAIJAAYK4gPvIwHjAAAJAAYK4gPvIwHjAAAAAA==.Snowballs:BAABNQAECn8bAAMDAAkK+QpECgF8AQADAAgK5wlECgF8AQAKAAIKGA0DJwByAAAAAA==.',
So='Softhorn:BAAANQADCgEIAQAAAA==.Sorenreign:BAAANQAECgEIAQAAAA==.Sothh:BAAANQADCggIEAABNQAECgcIKAAJALcTAA==.Soull:BAABNQAECn9JAAIMAAoK7CSmAQD2AwAMAAoK7CSmAQD2AwAAAA==.Soulsmash:BAAANQAECgYIBwAAAA==.',
Sp='Spacebabe:BAAANQAECgQIBQABNQAECgcIGgAcAOQKAA==.Spacestepdad:BAABNQAECn8aAAQcAAcK5AqnHwBbAQAcAAcK5AqnHwBbAQAmAAYKlwpOMQAQAQAnAAIKJgQzGwAoAAAAAA==.Sparkie:BAAANQAECgMIAwAAAA==.Spriggan:BAAANQAECgUIBQAAAA==.',
Sq='Squashfoot:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.',
St='Starface:BAACNQAFFH8PAAIQAAUK7w6iBACkAAAQAAUK7w6iBACkAAA1AAQKfz4AAxAACgqNHfwKAL8CABAACgqNHfwKAL8CABgABwpGFs0NAJ4BAAAA.Stargoose:BAAANQAECgUICAABNQAFFAUIDwAQAO8OAA==.Starphoenix:BAAANQADCggIFwAAAA==.Steelytree:BAAANQADCgcICgAAAA==.Stellaria:BAABNQAECn8WAAIfAAYKGBFxdwAeAQAfAAYKGBFxdwAeAQAAAA==.Steris:BAAANQADCggIIwABNQADCggIKAACAAAAAA==.Steverogers:BAABNQAECn8VAAMJAAcKAR13YgDRAQAJAAcKAR13YgDRAQAaAAIK4APKgAAcAAABNQAFFAYICgAIAOAWAA==.Stocktonrush:BAACNQAFFH8KAAQIAAYK4BZhDQA2AQAIAAUKwBRhDQA2AQAZAAMKgRc3EQCUAAAHAAEKAACCKgBMAAA1AAQKfzgABAgACgrxJEwQADQDAAgACQolJUwQADQDABkABgrgH+seAB8CAAcAAwouJAZAABYBAAAA.Stonedhenge:BAAANQABCgQIBAAAAA==.Sturmx:BAABNQAECn83AAIgAAoKyBZDGQASAgAgAAoKyBZDGQASAgAAAA==.',
Su='Subedei:BAABNQAECn84AAQZAAoKUiAnCwDnAgAZAAoK/B8nCwDnAgAIAAgKtRqcRQACAgAHAAEK0Q7hyQA2AAAAAA==.Submison:BAAANQADCgYIBgABNQAECgkJGwADAPkKAA==.Summerseve:BAAANQAECgMIAwAAAA==.Sunderhorn:BAAANQAECgMIBgAAAA==.Suriaa:BAABNQAECn9AAAMGAAoKpxhCCgAKAgAGAAoKpxhCCgAKAgAoAAQKugu8EwDBAAAAAA==.',
Sv='Svictis:BAAANQAECgYIEgAAAA==.Svictiss:BAAANQADCggIEQAAAA==.',
Sw='Swami:BAAANQAECgQIBAAAAA==.',
Ta='Talila:BAABNQAECn8nAAIQAAcKeht4GgB4AQAQAAcKeht4GgB4AQAAAA==.Taniss:BAAANQADCggIFgABNQAECgcIKAAJALcTAA==.Taurdeth:BAABNQAECn8YAAQHAAgKGAx5YABwAQAHAAgK5gt5YABwAQAIAAIKFQT7aABVAAAZAAIKXguvpAArAAABNQAFFAEIAQACAAAAAA==.',
Te='Terrya:BAAANQAECgUIBQAAAA==.Teryail:BAAANQADCgYIBgAAAA==.',
Th='Thaqdaddy:BAAANQADCgYIBgABNQAECgoKKAAHACwVAA==.Thaqknight:BAABNQAECn8oAAIHAAoKLBXcMwA+AgAHAAoKLBXcMwA+AgAAAA==.Therylnn:BAAANQAECgIIAQAAAA==.Thesthamenth:BAAANQADCgYIBgAAAA==.Thiccthaq:BAAANQAECgYICAABNQAECgoKKAAHACwVAA==.Thily:BAAANQADCgIIAgAAAA==.Thorwallen:BAAANQADCggIFQABNQAECgcIKAAJALcTAA==.Thror:BAAANQAECgEIAQAAAA==.',
Ti='Tiac:BAAANQAECgEIAQAAAA==.Tiergyll:BAAANQADCgEIAQAAAA==.Tirithor:BAABNQAECn8/AAIJAAoKaBQqdgBBAgAJAAoKaBQqdgBBAgAAAA==.',
To='Tockell:BAAANQADCgQIBwAAAA==.Togala:BAAANQADCgYIDgABNQAECgQIBgACAAAAAA==.Toothless:BAAANQAECgEIAQAAAA==.Torbin:BAAANQAECgYIDgAAAA==.Touchmywave:BAAANQADCgcIDwABNQAFFAMICQABAK4UAA==.',
Tr='Trichinella:BAAANQAECggICAABNQAECgoKKAAHACwVAA==.Tryhunt:BAAANQAECgUIBAAAAA==.Tryjinks:BAABNQAECn8mAAMSAAoKHRAjaADoAQASAAkKQQ4jaADoAQANAAcKCxHIjQBmAQAAAA==.',
Ts='Tsunameh:BAABNQAECn8aAAMRAAkKEBIxPAARAgARAAkKEBIxPAARAgAPAAEKdAKdWwAnAAABNQAECgoKNwABAOEWAA==.',
Tu='Tusky:BAAANQADCgYIBgAAAA==.',
Tw='Twohandtug:BAAANQADCggIHQAAAA==.',
Ty='Tykahndrius:BAABNQAECn8sAAMaAAoKBBgeHQACAgAaAAkKkxkeHQACAgAJAAcKKBGuuAAhAQABNQAECgoKNwABAOEWAA==.Tylîus:BAABNQAECn8jAAQhAAoKtRS8JQAYAgAhAAgKZBa8JQAYAgApAAUKBBg8FwC0AAAgAAIK2QmfZABhAAAAAA==.Tylïus:BAAANQAECgIIAQABNQAECgoKIwAhALUUAA==.Tyredelsia:BAAANQAECgQIBgAAAA==.',
['Tö']='Töph:BAAANQADCgYICgABNQAECgcIHAAUABgRAA==.',
['Tú']='Túsk:BAAANQAECgEIAgAAAA==.',
['Tý']='Týlius:BAAANQAECgMIBAABNQAECgoKIwAhALUUAA==.Týlïus:BAAANQAECgcIBgABNQAECgoKIwAhALUUAA==.',
Uk='Ukika:BAAANQAECgIIAgABNQAECgQIBgACAAAAAA==.',
Un='Unspokenword:BAAANQADCgEIAQAAAA==.',
Us='Useriòs:BAAANQAECgEIAQAAAA==.',
Ut='Uthilon:BAABNQAECn83AAIaAAoK4CB1BQDoAgAaAAoK4CB1BQDoAgAAAA==.',
Va='Valdare:BAABNQAECn8nAAIgAAcKpQnlRwDSAAAgAAcKpQnlRwDSAAAAAA==.Validorn:BAAANQAECgEIAQAAAA==.Varinathon:BAAANQADCgEIAQAAAA==.',
Ve='Vedillian:BAAANQAECgEJAQAAAA==.Velduar:BAAANQADCgQIBAAAAA==.',
Vi='Victorr:BAAANQAECgEIAQAAAA==.Vikkter:BAAANQAECggICAAAAA==.Viktorius:BAAANQADCggICwAAAA==.Vite:BAAANQADCgEIAQAAAA==.Vixious:BAAANQAECgQIBAAAAA==.Vizigoth:BAABNQAECn8uAAQWAAkKvA8jDwD4AAALAAYKcg54vgBPAQAWAAYKURAjDwD4AAAVAAEKURFWcgA9AAAAAA==.',
Vo='Vordell:BAAANQAECgQICQABNQAFFAEIAQACAAAAAA==.Voyana:BAABNQAECn8UAAIRAAUKaAmgoADHAAARAAUKaAmgoADHAAAAAA==.Voz:BAAANQADCgUIBQAAAA==.',
Vy='Vydragon:BAACNQAFFH8NAAQmAAYK7wyVEQDLAAAmAAMKOAmVEQDLAAAnAAQKZw1CCACjAAAcAAEK0gfcDwBBAAA1AAQKfykABCYACgp4EdkaABgCACYACgp4EdkaABgCABwACAoAGGcMAFkBACcABAroE/8VANEAAAE1AAUUBAgIAAMArBIA.Vymage:BAACNQAFFH8IAAIDAAQKrBL4OwDTAAADAAQKrBL4OwDTAAA1AAQKf0MAAwMACgqrHjMdALMCAAMACgqNHjMdALMCACUACAorHEgBAD8CAAAA.Vysneak:BAAANQADCgcIBwABNQAFFAQICAADAKwSAA==.',
['Vá']='Válidüs:BAACNQAFFH8ZAAIRAAcKfAzYCgC2AQARAAcKfAzYCgC2AQA1AAQKf0sAAhEACgrdIscJAHsDABEACgrdIscJAHsDAAAA.',
['Vã']='Vãsh:BAABNQAECn8dAAQTAAcKHAggHQAEAQATAAcKHAggHQAEAQAUAAUKbQPqWQB/AAAjAAMK2AXFHwBHAAAAAA==.',
Wa='Wabbitseason:BAAANQADCgIIAgABNQAECgkJGwADAPkKAA==.Wabìsuke:BAAANQADCggIFwAAAA==.Waterlogged:BAAANQADCgUIFgAAAA==.Waterloo:BAAANQADCgYIEgAAAA==.',
Wi='Wizpigas:BAAANQADCgcIDQABNQAECggIKwAUAFUUAA==.',
['Wì']='Wìccka:BAAANQADCgUIBgAAAA==.',
Xi='Xi:BAAANQAECgMIAwAAAA==.Xifan:BAABNQAECn8kAAITAAoKZSPRAQDQAwATAAoKZSPRAQDQAwAAAA==.',
Yd='Yd:BAAANQAECgQIBAABNQAFFAEIBQAEAAAAAA==.',
Yg='Yggdrasill:BAAANQADCgEIAQAAAA==.',
Yi='Yingpi:BAAANQADCgEIAQAAAA==.',
Yo='Yodaa:BAAANQADCggIDAABNQAECgcIKAAJALcTAA==.',
Ys='Ys:BAAANQAECgQIBAABNQAFFAEIBQAEAAAAAA==.',
Yt='Yt:BAAANQAECgQICgABNQAFFAEIBQAEAAAAAA==.',
Yw='Ywontudie:BAAANQAECgYIBgAAAA==.',
Yz='Yz:BAACNQAFFH8FAAIEAAEKAAAnEQBlAAAEAAEKAAAnEQBlAAA1AAQKfy4AAwQACQrQIwsCAJoDAAQACQrQIwsCAJoDAAYAAgpTGzqHAJUAAAAA.',
Za='Zailormoon:BAAANQADCgEIAQAAAA==.Zashawa:BAAANQADCgYIEQAAAA==.',
Ze='Zenithgrey:BAABNQAECn8XAAMSAAkKMQ6ghwCRAQASAAcKug6ghwCRAQANAAUKJQ8KqgAdAQAAAA==.',
Zl='Zluco:BAACNQAFFH8NAAIdAAQKciOqAQAqAQAdAAQKciOqAQAqAQA1AAQKf0cAAx0ACgoYJpQAAHQDAB0ACgoYJpQAAHQDAA0ABgp5HAd+AJIBAAAA.',
Zo='Zoomy:BAAANQADCgQIBAAAAA==.',
Zy='Zypherion:BAAANQADCgYIDgAAAA==.',
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
