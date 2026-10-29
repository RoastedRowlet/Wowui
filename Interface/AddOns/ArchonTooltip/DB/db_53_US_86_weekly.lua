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

local lookup = {'Hunter-BeastMastery','Unknown-Unknown','Mage-Arcane','Rogue-Subtlety','DeathKnight-Blood','DeathKnight-Unholy','Paladin-Retribution','Mage-Frost','Warlock-Demonology','Druid-Restoration','Druid-Balance','Shaman-Restoration','Warrior-Protection','Priest-Shadow','Priest-Holy','Shaman-Elemental','Monk-Mistweaver','Warlock-Destruction','Warlock-Affliction','Warrior-Arms','Druid-Guardian','Druid-Feral','DeathKnight-Frost','Monk-Windwalker','Paladin-Protection','Evoker-Devastation','Priest-Discipline','Rogue-Assassination','Paladin-Holy','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Marksmanship','Shaman-Enhancement','Hunter-Survival','Evoker-Preservation','Monk-Brewmaster','Evoker-Augmentation','Rogue-Outlaw','DemonHunter-Vengeance','Mage-Fire',}
local provider = {region='US',realm="Eldre'Thalas",name='US',type='weekly',zone=53,date='2026-10-27',data={Ad='Adesira:BAAANQAECgQIBQAAAA==.Adrastus:BAAANQAECgMIBwABNQAECgoKLwABAOQVAA==.Adurith:BAAANQAECgEIAQAAAA==.',
Ae='Aeslin:BAAANQADCgYJBgABNQAECgEIAwACAAAAAA==.',
Ah='Ahn:BAAANQAECgEIAwAAAA==.Ahtila:BAAANQADCgMIAgAAAA==.Ahylin:BAAANQADCgcIDAAAAA==.',
Ai='Ainslie:BAAANQAECgQIDgAAAA==.',
Al='Alerana:BAAANQAECgYIBwAAAA==.Altria:BAAANQADCgUICQAAAA==.',
An='An:BAABNQAECn8YAAIDAAYKYRyh0wDfAQADAAYKYRyh0wDfAQABNQAFFAEIBQAEAAAAAA==.Anarose:BAAANQAECgUIEQAAAA==.Antityk:BAAANQAECgcIEwABNQAECgoKLwABAOQVAA==.',
Ar='Aragorn:BAAANQADCgQIBQAAAA==.Arahant:BAAANQAECgIIAgAAAA==.Aretas:BAABNQAECn8iAAMFAAkKixt8GQDiAgAFAAkKixt8GQDiAgAGAAEK4Q3c4gAxAAAAAA==.Armadian:BAAANQAECgQICAAAAA==.Arrianne:BAAANQADCgYIBgAAAA==.Arriånna:BAAANQADCgcIEwAAAA==.Artemist:BAABNQAECn8UAAIHAAYKqg2y9QAyAQAHAAYKqg2y9QAyAQAAAA==.',
As='Asifa:BAAANQAECgIIAwAAAA==.',
At='Atherion:BAABNQAECn8pAAIIAAkKkRAiCwATAgAIAAkKkRAiCwATAgAAAA==.Attackroot:BAAANQAECgUIBgABNQAECgcIGgAJAFkMAA==.',
Au='Aurakk:BAAANQADCgYIEQABNQAECgYIIgAHAGATAA==.',
Av='Avelin:BAAANQADCgUIBQAAAA==.Aveticus:BAAANQAECgEIAQAAAA==.Avranarada:BAABNQAECn8tAAMKAAoKDhYeIAAqAgAKAAoKDhYeIAAqAgALAAcK+BhUQgDtAQAAAA==.Avril:BAAANQAECgEIAwAAAA==.',
Az='Azhádi:BAAANQAECgIIBAAAAA==.Azkara:BAACNQAFFH8LAAIMAAUKpQ3iDQAEAQAMAAUKpQ3iDQAEAQA1AAQKfysAAgwACgpQHGojANkCAAwACgpQHGojANkCAAAA.Azung:BAABNQAECn86AAIHAAoKeCB0GwCoAgAHAAoKeCB0GwCoAgAAAA==.',
Ba='Babaisyaga:BAACNQAFFH8RAAIBAAUKXiKuCAAPAQABAAUKXiKuCAAPAQA1AAQKf0YAAgEACgoXJPQJAAUDAAEACgoXJPQJAAUDAAAA.Baka:BAAANQAECgYICQAAAA==.Balinse:BAABNQAECn8aAAINAAgKhxQMGQChAQANAAgKhxQMGQChAQABNQAECgoKGwAOAB0MAA==.Balystix:BAAANQADCggICAAAAA==.Barb:BAAANQAECgEIBAAAAA==.Barrelrollin:BAAANQADCgYIDwAAAA==.Basherdownn:BAAANQADCgQIBAAAAA==.',
Be='Beastfodays:BAACNQAFFH8JAAIBAAMKrhRiHQDIAAABAAMKrhRiHQDIAAA1AAQKfzIAAgEACQpxGctDAKACAAEACQpxGctDAKACAAAA.Bethlahammer:BAAANQAECgEIAQABNQAECgIIAwACAAAAAA==.',
Bi='Billcritin:BAAANQAECggIDgAAAA==.',
Bl='Blackleaf:BAAANQADCgcICgAAAA==.Blawyke:BAAANQAECgUIBwABNQAFFAIIBAACAAAAAA==.Bless:BAAANQADCggIDgABNQAECgYICgACAAAAAA==.Blizzcon:BAACNQAFFH8RAAIPAAUKexioDwCZAQAPAAUKexioDwCZAQA1AAQKf0UAAg8ACgr2I2sJAHcDAA8ACgr2I2sJAHcDAAAA.Bloodsurge:BAAANQADCgQJAwAAAA==.Blushies:BAABNQAECn8jAAMQAAcKXh4eHgALAgAQAAcKXh4eHgALAgAMAAMK8xC64wCiAAAAAA==.',
Bo='Boltzfodayz:BAAANQAECgEIAgAAAA==.Bonerslap:BAAANQAECgIIAwAAAA==.Boone:BAAANQADCgMIAwAAAA==.Borrgar:BAABNQAECn8iAAIHAAYKYBPE1AByAQAHAAYKYBPE1AByAQAAAA==.',
Br='Brackle:BAABNQAECn8eAAIBAAkKCxuQQgCjAgABAAkKCxuQQgCjAgAAAA==.Bracori:BAACNQAFFH8KAAIRAAUKiwsQBAAHAQARAAUKiwsQBAAHAQA1AAQKfzkAAhEACgoPGXcGAJYCABEACgoPGXcGAJYCAAAA.Brandywynne:BAABNQAECn8pAAIBAAoKsA+4ZQBJAgABAAoKsA+4ZQBJAgAAAA==.Bretcha:BAAANQADCgQIBAABNQAECgQICQACAAAAAA==.Brick:BAABNQAECn8mAAIEAAoKVBaeDQCcAgAEAAoKVBaeDQCcAgAAAA==.Brightfame:BAABNQAECn8tAAMSAAkKVxVXGACqAQASAAcKexRXGACqAQATAAQKlBfpEQAsAQAAAA==.Bronny:BAABNQAECn8bAAIUAAgK7A3VuACOAQAUAAgK7A3VuACOAQAAAA==.Brônwyn:BAAANQADCgQIBAAAAA==.',
Bu='Buffshagwell:BAABNQAECn8lAAIHAAgKsxhqWQCLAgAHAAgKsxhqWQCLAgAAAA==.Bullrush:BAAANQADCgUIBQAAAA==.Butterbllz:BAABNQAECn8pAAIHAAoKhxs/XgB+AgAHAAoKhxs/XgB+AgAAAA==.',
Ca='Calypsio:BAAANQADCgQIBAABNQAECgMIAwACAAAAAA==.Camany:BAABNQAECn8fAAIBAAgKExGMdwAgAgABAAgKExGMdwAgAgAAAA==.Captinkrunch:BAAANQADCgEJAQAAAA==.Captinlock:BAAANQADCgEIAQABNQADCgEJAQACAAAAAA==.Captinmorí:BAAANQADCgEIAQAAAA==.Caretakerz:BAABNQAECn8kAAMVAAkKWxyyCwCuAgAVAAkKWxyyCwCuAgAWAAEKjg2jMQAwAAAAAA==.Cartus:BAAANQAECgUICQABNQAECgYIFAAVAAUJAA==.Cayin:BAABNQAECn8cAAIFAAkKSiDsEwANAwAFAAkKSiDsEwANAwABNQABCgYICwACAAAAAA==.',
Ch='Chanta:BAAANQAECgEIAQAAAA==.Chanyeol:BAAANQAECgYICwAAAA==.Chemoshh:BAAANQADCggIBgABNQAECgYIIgAHAGATAA==.',
Cl='Clamshell:BAABNQAECn8sAAMXAAoKKCBPEABnAgAXAAoKKCBPEABnAgAFAAUKwRi0YgBnAQAAAA==.Claudette:BAAANQAECgcIDQAAAA==.Clayier:BAAANQADCgcIEwAAAA==.',
Cn='Cntendr:BAAANQADCgUICAAAAA==.',
Co='Codenike:BAABNQAECn8iAAIYAAgKXhmSJAAAAgAYAAgKXhmSJAAAAgAAAA==.Coil:BAAANQADCggICgABNQAECgYICgACAAAAAA==.Copenzen:BAAANQAECgQIBgAAAA==.Corelheals:BAAANQAECgUIEQAAAA==.Covertyqt:BAABNQAECn8tAAIDAAoKQBwAMgApAgADAAoKQBwAMgApAgAAAA==.Coyote:BAAANQAECgEIAQAAAA==.',
Cp='Cptnhuman:BAABNQAECn8oAAIGAAkKEh5LJwCeAgAGAAkKEh5LJwCeAgAAAA==.',
Cr='Cromie:BAAANQADCggIFQAAAA==.Crosed:BAAANQADCgQIBAAAAA==.',
Cs='Cshunter:BAAANQADCgYIBwAAAA==.',
Cu='Cubcakes:BAAANQAECgEIAgAAAA==.',
Cy='Cylcuria:BAAANQAECgEIAgAAAA==.',
['Cõ']='Cõrpses:BAEBNQAECn8gAAIFAAoKgh7sDwBHAgAFAAoKgh7sDwBHAgABNQAECgoKHAAWAH0cAA==.',
Da='Daboof:BAAANQADCgYIIAAAAA==.Daemandred:BAAANQADCgQIBAAAAA==.Daggere:BAAANQADCggIKAAAAA==.Danke:BAAANQAECgUIBwAAAA==.Dankz:BAAANQAECgQICAAAAA==.Darkenmicky:BAAANQADCgcIEwAAAA==.Darkmickyz:BAABNQAECn8XAAIZAAYK1xHnNQA4AQAZAAYK1xHnNQA4AQAAAA==.Darthbobula:BAACNQAFFH8JAAIHAAQKKQdkEQC3AAAHAAQKKQdkEQC3AAA1AAQKfxcAAgcACArFDAbfAF0BAAcACArFDAbfAF0BAAAA.Dayloc:BAABNQAECn8YAAIJAAkKOQ2fRgCSAQAJAAkKOQ2fRgCSAQAAAA==.',
De='Deataria:BAABNQAECn8pAAIKAAkKdxk6DgBLAgAKAAkKdxk6DgBLAgAAAA==.Deathrho:BAAANQADCgMIAwAAAA==.Deawin:BAAANQADCgQIBAABNQADCgYIDwACAAAAAA==.Delilia:BAEANQAECggIDAABNQAECgkJGAAJALcKAA==.Delryth:BAAANQADCgYIBQAAAA==.Demonikk:BAAANQAECgUICwABNQAECgoKLwABAOQVAA==.Demontyk:BAAANQAECgYIDAABNQAECgoKLwABAOQVAA==.Desception:BAAANQADCgcICgAAAA==.Devourmax:BAAANQAECggICgAAAA==.',
Di='Diablõ:BAEANQAECggICwABNQAECgoKHAAWAH0cAA==.Diadochi:BAAANQAECgQJBgAAAA==.Dieguerta:BAAANQADCgEJAQAAAA==.',
Dl='Dl:BAABNQAECn8uAAIOAAoKOBm9GQCAAgAOAAoKOBm9GQCAAgAAAA==.',
Dr='Drakkarr:BAAANQADCgYIBwAAAA==.Drazhoath:BAAANQAECgUIDwAAAA==.Drdrill:BAAANQADCgYIBgAAAA==.Drimbirt:BAAANQADCgcICgAAAA==.Drinkmormilk:BAAANQAECgIIAwAAAA==.Drogelf:BAAANQADCgcIGQAAAA==.Drogman:BAAANQADCgIIAgAAAA==.',
Du='Dumbledore:BAAANQAECgEIAQABNQAECgEIAwACAAAAAA==.',
['Dá']='Dáwnbringer:BAAANQADCgIIBAAAAA==.',
Eb='Ebullition:BAAANQAECgcICAAAAA==.',
Ed='Edensfury:BAAANQAECgIIAwAAAA==.',
Ee='Eedani:BAAANQADCgUJCQAAAA==.',
Ei='Eigi:BAABNQAECn8hAAIBAAkK7hWwRgDLAQABAAkK7hWwRgDLAQAAAA==.',
El='Eldanon:BAABNQAECn82AAISAAkKRiMfAQCRAwASAAkKRiMfAQCRAwAAAA==.Elementality:BAAANQADCgIIAgAAAA==.Eleyert:BAACNQAFFH8MAAIQAAUKYiHEBQAuAQAQAAUKYiHEBQAuAQA1AAQKfyoAAhAACgpeJaYMAIIDABAACgpeJaYMAIIDAAAA.Elistann:BAAANQAECgQIBQABNQAECgYIIgAHAGATAA==.Elwe:BAABNQAECn8eAAIPAAgKJhXMcgDEAQAPAAgKJhXMcgDEAQAAAA==.',
Em='Embaku:BAAANQADCggICAABNQAECgoKNQAHAPsTAA==.Emiri:BAAANQAECgQIBQAAAA==.Emrhakul:BAAANQABCggIFQAAAA==.',
En='Enkidu:BAABNQAECn8gAAIBAAYKChAE1wBSAQABAAYKChAE1wBSAQAAAA==.Enseth:BAABNQAECn8mAAIaAAkKxQiNDAAVAQAaAAkKxQiNDAAVAQAAAA==.',
Er='Erakha:BAAANQAECgQICQAAAA==.Erandria:BAAANQADCgcICQABNQAECgUIBwACAAAAAA==.',
Eu='Eulogy:BAAANQADCgYICAABNQAFFAUIEQAPAHsYAA==.',
Ex='Exileosis:BAEBNQAECn8iAAQPAAoKfiPBCgBsAwAPAAoKfiPBCgBsAwAbAAYKHRjpCwB/AQAOAAEKgAKQkwAVAAAAAA==.',
Ez='Ezki:BAAANQADCggIFwABNQAECgYIIgAHAGATAA==.',
Fa='Fairious:BAABNQAECn8zAAIEAAkKDBmpJgDxAQAEAAkKDBmpJgDxAQAAAA==.',
Fe='Felcon:BAAANQADCgYICQAAAA==.Felenkeller:BAAANQAECgMIBwABNQAFFAUICQAGAIkVAA==.Fenrirr:BAAANQADCggICAABNQAECgYIIgAHAGATAA==.Fet:BAABNQAECn8rAAMcAAoKSyChBwAeAgAEAAgKDR6PEQBoAgAcAAkK5R2hBwAeAgAAAA==.',
Fh='Fhatbashtud:BAAANQAECgIIBQAAAA==.',
Fl='Flashies:BAAANQAECgIIAwABNQAECgcIIwAQAF4eAA==.Flatline:BAABNQAECn8fAAIbAAcKFxowAwC4AQAbAAcKFxowAwC4AQAAAA==.Flinnt:BAAANQADCgUIBwABNQAECgYIIgAHAGATAA==.',
Fn='Fngusamungus:BAAANQAECgEIAQAAAA==.',
Fo='Folgore:BAAANQAECgUICQAAAA==.Four:BAAANQAECgcIEgAAAA==.',
Fr='Fredwarlock:BAAANQAECgUIBwAAAA==.Frysky:BAABNQAECn8WAAMWAAkKFAwYGAB4AQAWAAgKGw0YGAB4AQALAAcK8gVhNgDyAAAAAA==.',
Fu='Furiousv:BAAANQADCgUIBQAAAA==.Futz:BAABNQAECn8vAAIdAAkKECMQHgD5AgAdAAkKECMQHgD5AgAAAA==.',
Ga='Gahnzul:BAAANQADCgUICgAAAA==.Gajitbek:BAAANQADCgUIBwAAAA==.Galah:BAABNQAECn8YAAIDAAcK4g498gCmAQADAAcK4g498gCmAQAAAA==.Gardurst:BAABNQAECn8sAAIQAAoK8Bl/FwBFAgAQAAoK8Bl/FwBFAgAAAA==.',
Gn='Gnomicide:BAAANQAECgIIBQAAAA==.',
Go='Gonesh:BAAANQADCggIEAAAAA==.Gooberpea:BAAANQABCgYIEAAAAA==.Gordoe:BAAANQADCgUICgAAAA==.',
Gr='Graveborne:BAAANQADCggIEQAAAA==.Gravess:BAAANQADCgUICwAAAA==.Gravewin:BAAANQADCgQICgABNQADCgYIDwACAAAAAA==.Gravyexpress:BAABNQAECn9YAAMeAAoKBhw/FwDhAgAeAAoK6Bs/FwDhAgAfAAcKxhTCPQBbAQAAAA==.Grendelheim:BAAANQADCgYIIgAAAA==.Grogar:BAAANQADCgcIEwAAAA==.Groxxigar:BAAANQADCgUIBQAAAA==.',
Gu='Gula:BAAANQAECgQIBQABNQAECgcIFgAYAIQQAA==.',
Ha='Hadez:BAAANQADCgUIBQAAAA==.Hagrok:BAAANQAECgEIAwAAAA==.Hantak:BAAANQADCgMIBgAAAA==.Harmsway:BAAANQADCgcJEQAAAA==.Hathaendron:BAAANQADCgYIBgAAAA==.',
He='Hephaestus:BAAANQAECgUICwAAAA==.',
Ho='Hocka:BAAANQADCgUIBgAAAA==.Holysmight:BAAANQAECgEIAQAAAA==.Holyumo:BAAANQADCgYIBgAAAA==.Holyyballs:BAAANQAECgYICAABNQAECgkJGwADAPkKAA==.Howlymandel:BAAANQAECgUIBgABNQAECggIEwACAAAAAA==.Hoytx:BAAANQADCgUIBQAAAA==.',
Hy='Hydraciel:BAAANQAECgYIDwAAAA==.',
['Hì']='Hìroko:BAAANQAECgUIEwAAAA==.',
Ic='Icedemon:BAAANQAECgUIDQAAAA==.Iceliandra:BAAANQADCgYIBgAAAA==.Iceveloric:BAAANQADCgUIAwAAAA==.Icupapi:BAAANQADCggILwAAAA==.Icynips:BAAANQABCgEIAQAAAA==.',
Im='Im:BAAANQADCgEJAQABNQAFFAEIBQAEAAAAAA==.Imabigman:BAAANQADCgcICAAAAA==.Imaleaf:BAABNQAECn8aAAILAAgKMQbsXQBZAQALAAgKMQbsXQBZAQAAAA==.Imperius:BAAANQAECgEIAwAAAA==.',
In='Insillico:BAAANQAECgEIAQABNQAECgoKLwABAOQVAA==.',
Ip='Iplaydead:BAABNQAECn8vAAMBAAoK5BX9TwB/AgABAAoK5BX9TwB/AgAgAAEKAACnmgAmAAAAAA==.',
Ir='Iroh:BAABNQAECn8YAAIYAAgKYRoNIQAkAgAYAAgKYRoNIQAkAgAAAA==.',
Is='Ismokeprot:BAAANQADCgQIBAAAAA==.',
Ja='Jacii:BAAANQAECggIDAABNQAECgoKLAAXACggAA==.Jawnson:BAABNQAECn8VAAIEAAgKeg4KHAD1AQAEAAgKeg4KHAD1AQAAAA==.',
Je='Jelluz:BAAANQADCgYIBgAAAA==.Jenefer:BAACNQAFFH8KAAIFAAUKpxqbCwDXAAAFAAUKpxqbCwDXAAA1AAQKfzgAAwUACgqCHtMKAJwCAAUACgqCHtMKAJwCAAYAAgrsFBS4AH0AAAAA.Jeslartoma:BAAANQADCgEIAQABNQADCggIGAACAAAAAA==.',
Ji='Jimjimmy:BAAANQADCgcIBwABNQAECgIIAwACAAAAAA==.',
Jo='Jondooz:BAAANQAECgcICQAAAA==.Joulecrafter:BAAANQAECgUIBQABNQAECgoKNQAHAPsTAA==.',
Jp='Jpegz:BAAANQADCgcIBgABNQAECgoKPQAHAIIiAA==.',
Ka='Kailana:BAAANQAECgEIBAABNQAECgoKLAAhALsbAA==.Kailback:BAAANQAECgYIDwABNQAECgoKLAAhALsbAA==.Kait:BAABNQAECn8rAAIMAAoKixZdIQA7AgAMAAoKixZdIQA7AgAAAA==.Kalcifur:BAACNQAFFH8LAAMdAAUK4ROXCgA6AQAdAAUK4ROXCgA6AQAZAAEKGgz7EgA2AAA1AAQKfzgAAx0ACgrKIHMEAJUDAB0ACgrKIHMEAJUDABkAAwqRGrtAAFIAAAAA.Karin:BAAANQAECgIIBAABNQAECgYIFAAVAAUJAA==.Karnelian:BAAANQAECggIDgABNQAECgoKGwARACAWAA==.Karras:BAAANQADCgUIBQAAAA==.Kashisht:BAAANQAECgIIAwAAAA==.Kasstigate:BAABNQAECn8cAAIUAAgKGheEdQA1AgAUAAgKGheEdQA1AgABNQAFFAUICgAFAKcaAA==.Kastiel:BAABNQAECn8bAAIOAAoKHQzuLQC2AQAOAAoKHQzuLQC2AQAAAA==.Katstrider:BAABNQAECn8tAAIBAAoKEBaWOgD2AQABAAoKEBaWOgD2AQAAAA==.Kattarea:BAAANQADCgUJCAABNQAECgoKLQABABAWAA==.Kavica:BAAANQAECgcICwABNQAECgoKJAAKAKQfAA==.',
Ke='Keldean:BAABNQAECn8ZAAINAAgK5h2ACgCZAgANAAgK5h2ACgCZAgAAAA==.Keryka:BAACNQAFFH8LAAMXAAUKuBypBwDzAAAXAAUKuBypBwDzAAAGAAEKZRJXIQBHAAA1AAQKfzYAAxcACgpLILUKAEQDABcACQr1IbUKAEQDAAYACArMGy1FAAQCAAAA.',
Kh='Khere:BAAANQAECgQIBQAAAA==.',
Ki='Kirigiri:BAAANQAECgcICAABNQAFFAUICwAdAOETAA==.Kirøs:BAAANQAECgQIBwAAAA==.Kiterisa:BAABNQAECn8tAAIMAAoK5QYeWgAyAQAMAAoK5QYeWgAyAQAAAA==.',
Kk='Kkazz:BAAANQADCggICwABNQAECgYIIgAHAGATAA==.',
Ko='Kohn:BAAANQAECgYICAAAAA==.Kona:BAEBNQAECn8cAAQWAAoKfRzbBwDXAQAVAAgK9CBVEgA+AgAWAAcK9BrbBwDXAQAKAAIKkQEDYQAhAAAAAA==.Korbusty:BAAANQADCggIDgAAAA==.',
Ku='Kuattieb:BAAANQABCgIIAgAAAA==.',
La='Ladýfinger:BAABNQAECn8uAAQdAAkKbxN8YQD0AQAdAAgKkBR8YQD0AQAHAAMKxQdDWwGOAAAZAAMKiQftMgCHAAABNQAFFAUICwAVAI0OAA==.Laisidhiel:BAAANQAECgMIBgAAAA==.Lateo:BAABNQAECn8eAAIEAAoKKQt6QABeAQAEAAoKKQt6QABeAQAAAA==.Lawz:BAABNQAECn8cAAMTAAkKPQTFEABAAQATAAkKPQTFEABAAQASAAIKOAAGegA0AAAAAA==.',
Le='Lelianna:BAAANQADCgYIJAAAAA==.Lemonruss:BAAANQADCggIEQAAAA==.Levibigguns:BAAANQADCggICAABNQAECggIJAAYAE8UAA==.Lexia:BAAANQAECgYICwAAAA==.',
Li='Libidine:BAAANQADCgQIBAABNQAECgcIFgAYAIQQAA==.Liemannin:BAAANQAECgEIAQAAAA==.Lightninghah:BAAANQABCgIIAgAAAA==.Lilaa:BAAANQADCgcIBwAAAA==.Lilturtz:BAAANQAECgUICAABNQAECgcIIwAQAF4eAA==.Linnea:BAAANQADCgcIDQAAAA==.',
Lo='Locksative:BAAANQADCggIJgAAAA==.Longhorn:BAABNQAECn8rAAIHAAkK4Q5ohwBCAQAHAAkK4Q5ohwBCAQAAAA==.Lorekesh:BAAANQADCgEJAQABNQAECgcIDQACAAAAAA==.Lorriena:BAAANQAECgEIAgABNQAECgIIAwACAAAAAA==.Lortpegsalot:BAABNQAECn89AAIHAAoKgiITFgDLAgAHAAoKgiITFgDLAgAAAA==.Lowy:BAAANQAECgUIBQAAAA==.',
Lu='Lucena:BAABNQAECn8hAAIPAAcKuSQ2EQDiAgAPAAcKuSQ2EQDiAgAAAA==.Lurg:BAAANQADCggICgABNQADCggIJgACAAAAAA==.Luxuria:BAAANQAECgQIBAABNQAECgcIFgAYAIQQAA==.',
Ly='Lyralana:BAAANQAECgUIBwAAAA==.',
Ma='Maberu:BAACNQAFFH8GAAIRAAMKJwRyBQCnAAARAAMKJwRyBQCnAAA1AAQKfyAAAhEACgqyDWscAL0BABEACgqyDWscAL0BAAE1AAUUBQgLAB0A4RMA.Madamholy:BAABNQAECn8XAAIPAAYKjx+hVwAbAgAPAAYKjx+hVwAbAgAAAA==.Madamkluck:BAAANQADCgUIBQAAAA==.Maglubiyet:BAAANQAECgUIDgAAAA==.Magnitood:BAABNQAECn8UAAMKAAYKVxbUMgCEAQAKAAYKVxbUMgCEAQALAAEKAAB+rgA5AAAAAA==.Malbjornion:BAAANQAECgUIEAAAAA==.Malphox:BAAANQADCgQICAAAAA==.Manbearcat:BAABNQAECn8UAAIVAAYKBQm/NgDwAAAVAAYKBQm/NgDwAAAAAA==.Manhole:BAAANQAECgQIDQAAAA==.Markyb:BAAANQADCggIEQAAAA==.Masamura:BAACNQAFFH8SAAMDAAYK5hS9EwD8AAADAAUKExe9EwD8AAAIAAIKfwchCgBxAAA1AAQKfzoAAwMACgoFG4c9AP4BAAMACgqnGYc9AP4BAAgAAgo0G+YrAJwAAAAA.Maureanna:BAAANQADCgUIDgABNQAECgUIBwACAAAAAA==.',
Me='Mechahuntard:BAAANQADCgEIAQAAAA==.Medanii:BAEBNQAECn8dAAQbAAkKDBBeDQBeAQAbAAYKVRJeDQBeAQAPAAUKcQkcrAASAQAOAAQKTQenVwCsAAAAAA==.Melorm:BAAANQAECgQIDgAAAA==.',
Mi='Millizh:BAACNQAFFH8YAAMBAAgKoh6tBwDUAQABAAUKLiCtBwDUAQAgAAUKqhucDwBDAQA1AAQKfycAAyAACgrEJBsGAG8DACAACQpXJhsGAG8DAAEABwqvH/WRAOUBAAAA.Mirasharu:BAAANQADCgYIIAAAAA==.Mireille:BAAANQADCgYIDQAAAA==.Mitsuri:BAABNQAECn8kAAIHAAgKRg6uhgBDAQAHAAgKRg6uhgBDAQAAAA==.Mitzuky:BAAANQADCgMIAwAAAA==.',
Mo='Mommamoon:BAAANQADCgQIBAABNQAECgkJIAAHAIAZAA==.Moonlïght:BAABNQAECn8gAAIHAAkKgBmXRwDhAQAHAAkKgBmXRwDhAQAAAA==.Morganlefay:BAABNQAECn8YAAIJAAcK2gFsygBiAAAJAAcK2gFsygBiAAAAAA==.Morlyn:BAABNQAECn8jAAIIAAgKlhZFDQDdAQAIAAgKlhZFDQDdAQAAAA==.Morregan:BAAANQAECgcICAAAAA==.Motion:BAAANQADCgcICQABNQAECgYICgACAAAAAA==.Mousereaper:BAABNQAECn8eAAIfAAoKcg0AHgA7AQAfAAoKcg0AHgA7AQAAAA==.',
My='Mydnight:BAAANQABCgIIAgAAAA==.Mystìc:BAABNQAECn8sAAQhAAoKuxvADwBtAgAhAAkK2RrADwBtAgAQAAYKOxzObADaAQAMAAEKaQr2IwEpAAAAAA==.Mystíc:BAAANQAECgYICAABNQAECgoKLAAhALsbAA==.',
['Má']='Májorrobot:BAABNQAECn8nAAIUAAoKzCFrLgAEAwAUAAoKzCFrLgAEAwAAAA==.',
['Mé']='Ménopáwz:BAABNQAECn8XAAIVAAkKoBSmDADqAQAVAAkKoBSmDADqAQABNQAFFAUICQAGAIkVAA==.',
Na='Namor:BAAANQAECgEIAQAAAA==.Nattisca:BAAANQADCggIGAAAAA==.',
Ne='Nefhainea:BAAANQAECgIIAwABNQAECgQICQACAAAAAA==.Nervanna:BAAANQAECgIIAwABNQAECgoKGwAPAAMUAA==.Nessà:BAABNQAECn8WAAIYAAcKhBBKIQAbAQAYAAcKhBBKIQAbAQAAAA==.Neveenn:BAABNQAECn84AAIKAAoKJR0PDwDkAgAKAAoKJR0PDwDkAgAAAA==.',
Ni='Niccala:BAAANQAECgEIAQAAAQ==.Nirith:BAAANQADCgYIEwAAAA==.Nivmizet:BAAANQAECgEIAQAAAA==.',
No='Nohatcat:BAAANQAECgQIBwABNQAECgcIIwAQAF4eAA==.',
['Nâ']='Nâmii:BAAANQAECgMIBAAAAA==.',
['Nè']='Nèzukõ:BAABNQAECn8fAAIBAAgKDxeHiwDzAQABAAgKDxeHiwDzAQAAAA==.',
Ob='Obata:BAAANQAECgQIBQAAAA==.',
Oc='Octavius:BAAANQADCggJDQABNQAECgIIAwACAAAAAA==.',
Od='Odi:BAAANQADCgQIBAAAAA==.',
Oj='Ojore:BAEBNQAECn8hAAIXAAgKagxhUgBnAQAXAAgKagxhUgBnAQAAAA==.Ojoverde:BAACNQAFFH8KAAIJAAUKXgQuEwC0AAAJAAUKXgQuEwC0AAA1AAQKfzgAAgkACgpqE4Q0ANgBAAkACgpqE4Q0ANgBAAAA.',
On='Onizuka:BAAANQADCgEIAQABNQAECgEIAQACAAAAAA==.Onside:BAAANQAECgcICwABNQAFFAUICAAYAL8TAA==.',
Op='Ophillã:BAABNQAECn8WAAMOAAYKnBOSQAArAQAOAAYKnBOSQAArAQAbAAUKORxyBwDcAAABNQAECgcIFgAYAIQQAA==.',
Or='Ordenn:BAAANQADCgQICAABNQAECgoKKwAcAEsgAA==.Orian:BAAANQADCgQIBwAAAA==.Oromë:BAAANQAECgEIAQAAAA==.',
Ov='Overflare:BAAANQAECgEIAQAAAA==.',
Oz='Ozz:BAABNQAECn8ZAAIYAAgKFw/aLgChAQAYAAgKFw/aLgChAQAAAA==.Ozzerker:BAAANQADCgEIAQAAAA==.Ozzullr:BAABNQAECn8XAAIBAAkKAht3MgDVAgABAAkKAht3MgDVAgAAAA==.',
Pa='Painbreak:BAAANQADCgEIAQABNQAECgkJJAAVAFscAA==.Pajamas:BAAANQAECgEIAQABNQAECgcIGgAJAFkMAA==.Pallanquin:BAAANQAECgEIAQAAAA==.Papichili:BAAANQAECgUIDAAAAA==.Pashnir:BAAANQAECgEIAQAAAA==.',
Pe='Peachey:BAABNQAECn8fAAIMAAkKYw4pigBwAQAMAAkKYw4pigBwAQAAAA==.Peaker:BAAANQAECgQIBAAAAA==.Peakra:BAABNQAECn8fAAIPAAoKxRZ4HQB0AgAPAAoKxRZ4HQB0AgAAAA==.',
Ph='Phoênix:BAAANQADCgMIAwAAAA==.',
Pi='Pigas:BAABNQAECn8kAAIYAAgKTxRiKADdAQAYAAgKTxRiKADdAQAAAA==.',
Pr='Prestoresto:BAAANQADCgYIDwAAAA==.',
Ps='Psychosix:BAABNQAECn8ZAAIDAAoK9xtmSwDrAgADAAoK9xtmSwDrAgAAAA==.',
Qu='Quinberos:BAAANQAECgUIDAAAAA==.',
Ra='Racey:BAAANQADCggICAAAAA==.Raiistlin:BAAANQADCgYIBwABNQAECgYIIgAHAGATAA==.Ramdel:BAAANQAECgMIAwABNQAECgoKOgAiAIkZAA==.Ramstrider:BAABNQAECn86AAMiAAoKiRnYAgAlAgAiAAoKiRnYAgAlAgABAAIKaQcTOAF2AAAAAA==.Ranah:BAAANQAECgQIBAABNQAECgcICAACAAAAAA==.Ranch:BAAANQAECgEIAQAAAA==.Rapture:BAABNQAECn8vAAIfAAoKxg2sEwCyAQAfAAoKxg2sEwCyAQAAAA==.Ravec:BAAANQAECgEIAQAAAA==.Rayziel:BAAANQADCggICAABNQAECgMIBQACAAAAAA==.',
Re='Rengell:BAAANQAECggIEwAAAA==.Reptiliano:BAABNQAECn8VAAIjAAkKPxIXCwDqAQAjAAkKPxIXCwDqAQABNQAFFAQIBgAcAJwOAA==.',
Rh='Rheagall:BAABNQAECn8rAAIhAAoKox/fBgAUAwAhAAoKox/fBgAUAwAAAA==.Rhodetta:BAABNQAECn8bAAIPAAoKAxS5OgB+AgAPAAoKAxS5OgB+AgAAAA==.',
Ri='Rizepriest:BAAANQADCgIIAgABNQAECgYIEwACAAAAAA==.Rizerage:BAAANQAECgYIEwAAAA==.',
Ro='Roaraxe:BAAANQADCgYIBgABNQAECgIIAwACAAAAAA==.Rowena:BAABNQAECn86AAILAAkKeBWROQAjAgALAAkKeBWROQAjAgAAAA==.Rowynna:BAAANQAECgMIAwABNQAECgUIDAACAAAAAA==.Roxy:BAAANQAECgEIAQAAAA==.Roxymonk:BAAANQADCgYIBgAAAA==.Royalviaman:BAAANQADCgcICgAAAA==.',
Ry='Ryz:BAAANQADCggICAAAAA==.Ryztkmtchrch:BAACNQAFFH8FAAIPAAIKdhxFGgCpAAAPAAIKdhxFGgCpAAA1AAQKfzMABA8ACgrmG2cyAJ4CAA8ACgrmG2cyAJ4CABsABwrDDe8MAGgBAA4ABQqMDzNHAAIBAAAA.',
['Rå']='Råti:BAAANQAECgQIBAAAAA==.',
Sa='Sacdk:BAAANQAECgQICQAAAA==.Safaria:BAAANQAECgQIBwABNQAECgUIEAACAAAAAA==.Saloenus:BAAANQAECgYIDQAAAA==.Sarlyssa:BAAANQAECgEIAQAAAA==.Saucehoss:BAABNQAECn8mAAQTAAkKQx3sAwCrAgATAAkKQx3sAwCrAgASAAQKLQ8MPQDNAAAJAAMKkhTNBQHAAAAAAA==.Saucymac:BAABNQAECn8VAAMOAAoKfRwPEADOAQAOAAgKTBoPEADOAQAPAAgKeQb6tAD4AAAAAA==.',
Sc='Scofflaw:BAAANQADCgEIAQABNQAECgQIBgACAAAAAA==.Scootr:BAAANQAECgQIBAAAAA==.Scubasteve:BAAANQADCgUICgAAAA==.',
Se='Sefi:BAABNQAECn8uAAMHAAgKeBJFfgBUAQAHAAgKkBFFfgBUAQAZAAQKlQ3+TgCsAAAAAA==.Semirrhage:BAAANQADCgMIAwAAAA==.',
Sh='Shadowflame:BAABNQAECn8aAAIJAAcKWQzteAAGAQAJAAcKWQzteAAGAQAAAA==.Shallator:BAAANQADCgYIBgAAAA==.Shamanigans:BAAANQAECgMIBwABNQAECgYIFAAKAFcWAA==.Shammygoat:BAABNQAECn8eAAIQAAcKDxlJfwCnAQAQAAcKDxlJfwCnAQAAAA==.Shaqattack:BAACNQAFFH8IAAIYAAUKvxNvBgDXAAAYAAUKvxNvBgDXAAA1AAQKfy8AAhgACgqxHtYHAJkCABgACgqxHtYHAJkCAAAA.Shaqattaq:BAABNQAECn8ZAAMcAAoKnhmZIwBrAgAcAAkK8heZIwBrAgAEAAYKKxXyQgBUAQABNQAFFAUICAAYAL8TAA==.Sharktide:BAABNQAECn8eAAIMAAoKuhbZXwDvAQAMAAoKuhbZXwDvAQAAAA==.Shawnella:BAABNQAECn8tAAMYAAoKoxz/DAAhAgAYAAkKohv/DAAhAgARAAIKTQf1RABYAAAAAA==.Shenlune:BAABNQAECn8VAAMRAAcKbQs6JgBHAQARAAcKbQs6JgBHAQAkAAUKChivGwArAQAAAA==.Sheutka:BAAANQAECgIIBQAAAA==.Shiggles:BAAANQAECgIIAgAAAA==.Shinaie:BAABNQAECn8YAAIOAAcKYAt8OABhAQAOAAcKYAt8OABhAQAAAA==.Shocknrollz:BAAANQAECgQIDQAAAA==.Shogún:BAABNQAECn8hAAIFAAkKchy/FAACAgAFAAkKchy/FAACAgAAAA==.Shran:BAAANQAECgEIAwAAAA==.Shtylez:BAAANQAECgUICwABNQAECgoKLwABAOQVAA==.',
Si='Silntwolf:BAAANQABCgQIBAAAAA==.Silpion:BAAANQAECgYIEwAAAA==.Silth:BAAANQADCggIKQAAAA==.Sinariel:BAABNQAECn8zAAIRAAoK9BycBADyAgARAAoK9BycBADyAgAAAA==.Sirdank:BAAANQAECgIIBQAAAA==.',
Sk='Skarlate:BAAANQADCgYIBgAAAA==.Skâld:BAEANQADCgYICwAAAA==.',
Sl='Sliko:BAABNQAECn8/AAIHAAoKTRaAQAD5AQAHAAoKTRaAQAD5AQAAAA==.',
Sm='Smmoke:BAABNQAECn8tAAIBAAoK7xfzNwAAAgABAAoK7xfzNwAAAgAAAA==.',
Sn='Sneekypally:BAABNQAECn8dAAIHAAYK4gPvIwHjAAAHAAYK4gPvIwHjAAAAAA==.Snowballs:BAABNQAECn8bAAMDAAkK+QpECgF8AQADAAgK5wlECgF8AQAIAAIKGA3MHgB2AAAAAA==.',
So='Softhorn:BAAANQABCgUIBQAAAA==.Sorenreign:BAAANQADCgYICgAAAA==.Sothh:BAAANQADCggIEAABNQAECgYIIgAHAGATAA==.Soull:BAABNQAECn8/AAIKAAoK1SRaAQDhAwAKAAoK1SRaAQDhAwAAAA==.Soulsmash:BAAANQAECgUIBgAAAA==.',
Sp='Spacebabe:BAAANQAECgMIAwABNQAECgcIGgAaAOQKAA==.Spacestepdad:BAABNQAECn8aAAQaAAcK5AqnHwBbAQAaAAcK5AqnHwBbAQAjAAYKlwpOMQAQAQAlAAIKJgSQFgAqAAAAAA==.Sparkie:BAAANQAECgMIAwAAAA==.Spriggan:BAAANQAECgUIBgAAAA==.',
Sq='Squashfoot:BAAANQAECgEIAgABNQAECgIIAwACAAAAAA==.',
St='Starface:BAACNQAFFH8LAAIVAAUKjQ7EAwCkAAAVAAUKjQ7EAwCkAAA1AAQKfzUAAhUACgoNHfwKAL8CABUACgoNHfwKAL8CAAAA.Stargoose:BAAANQAECgUICQABNQAFFAUICwAVAI0OAA==.Starphoenix:BAAANQADCggIFwAAAA==.Steelytree:BAAANQADCgcICgAAAA==.Stellaria:BAABNQAECn8WAAIdAAYKGBEWXgAnAQAdAAYKGBEWXgAnAQAAAA==.Steris:BAAANQADCggIHwABNQADCggIJgACAAAAAA==.Steverogers:BAAANQAECgYIEwABNQAFFAUICQAGAIkVAA==.Stocktonrush:BAACNQAFFH8JAAQGAAUKiRVhDQA2AQAGAAQKsxJhDQA2AQAXAAMKgRcuDQCZAAAFAAEKAACCKgBMAAA1AAQKfzMABAYACgrxJEwQADQDAAYACQolJUwQADQDAAUAAwouJC0zAB0BABcAAwrjH7BBABEBAAAA.Stonedhenge:BAAANQAECgEIAQAAAA==.Sturmx:BAABNQAECn8tAAIeAAoKbRMSGwDEAQAeAAoKbRMSGwDEAQAAAA==.',
Su='Subedei:BAABNQAECn8vAAQXAAoK4xxeEQBaAgAXAAgKPx1eEQBaAgAGAAgKtRqcRQACAgAFAAEK0Q7hyQA2AAAAAA==.Summerseve:BAAANQAECgMIBAAAAA==.Sunderhorn:BAAANQAECgIIBQAAAA==.Suriaa:BAABNQAECn89AAMcAAoKIBhwBwAlAgAcAAoKIBhwBwAlAgAmAAQKugu8EwDBAAAAAA==.',
Sv='Svictis:BAAANQAECgUIDgAAAA==.Svictiss:BAAANQADCggIEQAAAA==.',
Sw='Swami:BAAANQAECgQIBgAAAA==.',
Ta='Talila:BAABNQAECn8hAAIVAAYK/Bz6HwCdAQAVAAYK/Bz6HwCdAQAAAA==.Taniss:BAAANQADCggIFgABNQAECgYIIgAHAGATAA==.Taurdeth:BAABNQAECn8YAAQFAAgKGAx5YABwAQAFAAgK5gt5YABwAQAGAAIKFQSJWwBYAAAXAAIKXgt6jwArAAABNQAECgoKGwAPAAMUAA==.',
Te='Terrya:BAAANQAECgUIBQAAAA==.Teryail:BAAANQAECgEIAgAAAA==.',
Th='Thaqdaddy:BAAANQADCgYIBgABNQAECgoKJwAFACwVAA==.Thaqknight:BAABNQAECn8nAAIFAAoKLBXcMwA+AgAFAAoKLBXcMwA+AgAAAA==.Therylnn:BAAANQAECgIIBAAAAA==.Thesthamenth:BAAANQADCgYIBgAAAA==.Thiccthaq:BAAANQAECgYICQABNQAECgoKJwAFACwVAA==.Thily:BAAANQADCgIIAgAAAA==.Thorwallen:BAAANQADCggIFAABNQAECgYIIgAHAGATAA==.Thror:BAAANQAECgEIAQAAAA==.',
Ti='Tiac:BAAANQAECgEIAQAAAA==.Tiergyll:BAAANQABCgIIBgAAAA==.Tirithor:BAABNQAECn81AAIHAAoK+xNiVAC5AQAHAAoK+xNiVAC5AQAAAA==.',
To='Tockell:BAAANQADCgQIBwAAAA==.Togala:BAAANQADCgYIDgABNQAECgQICQACAAAAAA==.Toothless:BAAANQAECgEIAgAAAA==.Torbin:BAAANQAECgUIDgAAAA==.Touchmywave:BAAANQAECgEIAQABNQAFFAMICQABAK4UAA==.',
Tr='Tryhunt:BAAANQAECgUIBQAAAA==.Tryjinks:BAABNQAECn8mAAMQAAoKHRAjaADoAQAQAAkKQQ4jaADoAQAMAAcKCxHIjQBmAQAAAA==.Trypriest:BAAANQAECgEIAQAAAA==.',
Ts='Tsunameh:BAAANQAECgcIEgABNQAECgoKLwABAOQVAA==.',
Tu='Tusky:BAAANQADCgYIBgAAAA==.',
Tw='Twohandtug:BAAANQADCggIGwAAAA==.',
Ty='Tykahndrius:BAABNQAECn8oAAMZAAoKJxceHQACAgAZAAkKGRgeHQACAgAHAAcKJBHslwAjAQABNQAECgoKLwABAOQVAA==.Tylîus:BAABNQAECn8jAAQfAAoKtRS8JQAYAgAfAAgKZBa8JQAYAgAnAAUKBBjCEQC9AAAeAAIK2Ql2VwBqAAAAAA==.Tylïus:BAAANQAECgIIAwABNQAECgoKIwAfALUUAA==.Tyredelsia:BAAANQAECgQIBwAAAA==.',
['Tö']='Töph:BAAANQADCgYICgABNQAECgcIFgAYAIQQAA==.',
['Tú']='Túsk:BAAANQAECgEIAgAAAA==.',
['Tý']='Týlius:BAAANQAECgMIBQABNQAECgoKIwAfALUUAA==.Týlïus:BAAANQAECgcIBwABNQAECgoKIwAfALUUAA==.',
Uk='Ukika:BAAANQAECgIICAABNQAECgQICQACAAAAAA==.',
Us='Useriòs:BAAANQAECgEIAQAAAA==.',
Ut='Uthilon:BAABNQAECn8tAAIZAAoKwh9eBgCJAgAZAAoKwh9eBgCJAgAAAA==.',
Va='Valdare:BAABNQAECn8hAAIeAAYKegpyWwAWAQAeAAYKegpyWwAWAQAAAA==.Validorn:BAAANQAECgEIAQAAAA==.',
Ve='Vedillian:BAAANQAECgEJAgAAAA==.Velduar:BAAANQADCgQIBAAAAA==.',
Vi='Victorr:BAAANQAECgEIAwAAAA==.Vikkter:BAAANQAECggICAAAAA==.Viktorius:BAAANQADCgcICgAAAA==.Vixious:BAAANQAECgQIBAAAAA==.Vizigoth:BAABNQAECn8nAAQTAAgK7hCQCwDYAAAJAAYKcg54vgBPAQATAAUKQRKQCwDYAAASAAEKURFWcgA9AAAAAA==.',
Vo='Vordell:BAAANQAECgQICgABNQAECgoKGwAPAAMUAA==.Voyana:BAAANQAECgUIEAAAAA==.Voz:BAAANQADCgUIBQAAAA==.',
Vy='Vydragon:BAACNQAFFH8MAAQjAAUKXwyVEQDLAAAjAAMKOAmVEQDLAAAlAAMKExCFCABRAAAaAAEK0gfcDwBBAAA1AAQKfygABCMACgoyENkaABgCACMACgoyENkaABgCABoACAoAGIcJAF8BACUABAroE/8VANEAAAE1AAUUBAgIAAMArBIA.Vymage:BAACNQAFFH8IAAIDAAQKrBL4OwDTAAADAAQKrBL4OwDTAAA1AAQKfzkAAwMACgpEHq0RAM4CAAMACgpEHq0RAM4CACgAAwrwFGUHAMYAAAAA.Vyrubur:BAAANQAECgEIAQABNQAFFAQICAADAKwSAA==.',
['Vá']='Válidüs:BAACNQAFFH8YAAIPAAYKEw4NDABqAQAPAAYKEw4NDABqAQA1AAQKf0EAAg8ACgrdImEGAH8DAA8ACgrdImEGAH8DAAAA.',
['Vã']='Vãsh:BAABNQAECn8WAAMRAAcK4wdNFwAHAQARAAcK4wdNFwAHAQAYAAUKbQPqWQB/AAAAAA==.',
Wa='Wabbitseason:BAAANQADCgIIAgABNQAECgkJGwADAPkKAA==.Wabìsuke:BAAANQADCggIFQAAAA==.Waterlogged:BAAANQADCgQIEAAAAA==.Waterloo:BAAANQADCgYIEAAAAA==.',
Wi='Wizpigas:BAAANQADCgcIDQABNQAECggIJAAYAE8UAA==.',
['Wì']='Wìccka:BAAANQADCgUIBQAAAA==.',
Xi='Xi:BAAANQAECgMIBAAAAA==.Xifan:BAABNQAECn8bAAIRAAoKIBZmEwBGAgARAAoKIBZmEwBGAgAAAA==.',
Yd='Yd:BAAANQAECgQIBgABNQAFFAEIBQAEAAAAAA==.',
Yg='Yggdrasill:BAAANQABCgUICAAAAA==.',
Yi='Yingpi:BAAANQABCgIIAgAAAA==.',
Yo='Yodaa:BAAANQADCggICwABNQAECgYIIgAHAGATAA==.',
Ys='Ys:BAAANQAECgQIBAABNQAFFAEIBQAEAAAAAA==.',
Yt='Yt:BAAANQAECgQICwABNQAFFAEIBQAEAAAAAA==.',
Yw='Ywontudie:BAAANQAECgYICgAAAA==.',
Yz='Yz:BAACNQAFFH8FAAIEAAEKAAAnEQBlAAAEAAEKAAAnEQBlAAA1AAQKfy4AAwQACQrQIwsCAJoDAAQACQrQIwsCAJoDABwAAgpTGzqHAJUAAAAA.',
Za='Zashawa:BAAANQADCgYIEQAAAA==.',
Ze='Zenithgrey:BAABNQAECn8XAAMQAAkKMQ6ghwCRAQAQAAcKug6ghwCRAQAMAAUKJQ8KqgAdAQAAAA==.',
Zl='Zluco:BAACNQAFFH8JAAIhAAMKfx2rAQAEAQAhAAMKfx2rAQAEAQA1AAQKfz0AAyEACgqiJd8AAFADACEACgqiJd8AAFADAAwABgp5HAd+AJIBAAAA.',
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
