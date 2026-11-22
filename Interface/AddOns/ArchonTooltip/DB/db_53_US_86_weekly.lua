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

local lookup = {'Hunter-BeastMastery','Unknown-Unknown','Druid-Balance','Mage-Arcane','Rogue-Subtlety','Rogue-Assassination','Druid-Restoration','Priest-Holy','Priest-Discipline','Priest-Shadow','DeathKnight-Blood','DeathKnight-Unholy','Paladin-Retribution','Mage-Frost','Warlock-Demonology','Shaman-Restoration','Warrior-Protection','Druid-Guardian','Shaman-Elemental','Monk-Mistweaver','Monk-Windwalker','Warlock-Destruction','Warlock-Affliction','Warrior-Arms','Druid-Feral','DeathKnight-Frost','Paladin-Protection','Warrior-Fury','DemonHunter-Vengeance','DemonHunter-Havoc','Evoker-Devastation','Shaman-Enhancement','Paladin-Holy','DemonHunter-Devourer','Hunter-Marksmanship','Rogue-Outlaw','Monk-Brewmaster','Hunter-Survival','Mage-Fire','Evoker-Preservation','Evoker-Augmentation',}
local provider = {region='US',realm="Eldre'Thalas",name='US',type='weekly',zone=53,date='2026-11-17',data={Ad='Adesira:BAAANQAECgQIBQAAAA==.Adrastus:BAAANQAECgQIBAABNQAECgoKOAABAOEWAA==.Adurith:BAAANQABCgQIBAAAAA==.',
Ae='Aeslin:BAAANQADCgYJBgABNQAECgEIAQACAAAAAA==.',
Ah='Ahn:BAABNQAECn8aAAIDAAoKtQfLNQBhAQADAAoKtQfLNQBhAQAAAA==.Ahtila:BAAANQADCgUIBwAAAA==.Ahylin:BAAANQADCgcIDAAAAA==.',
Ai='Ainslie:BAAANQAECgYIEQAAAA==.',
Al='Alerana:BAAANQAECgYIDAAAAA==.Altria:BAAANQADCgUICQAAAA==.',
An='An:BAABNQAECn8YAAIEAAYKYRyh0wDfAQAEAAYKYRyh0wDfAQABNQAFFAEIBQAFAAAAAA==.Anarose:BAAANQAECgUIEQABNQAECggILQADAIwFAA==.Antityk:BAABNQAECn8jAAMFAAkKMwwAYwCDAQAFAAkKSQsAYwCDAQAGAAQK7gowdADgAAABNQAECgoKOAABAOEWAA==.',
Ar='Araedia:BAAANQAECgYIBgABNQAECgoKOwAHAA4WAA==.Aragorn:BAAANQADCgQIBQAAAA==.Arahant:BAAANQAECgIIAgAAAA==.Araxiel:BAECNQAFFH8HAAIIAAQKoB2HIQDeAAAIAAQKoB2HIQDeAAA1AAQKfy0ABAgACgp+I8EKAGwDAAgACgp+I8EKAGwDAAkABwq+FukLAH8BAAoAAQqAApCTABUAAAE1AAUUBAgHAAgAoB0A.Aretas:BAABNQAECn8rAAMLAAoKoRt8GQDiAgALAAoKoRt8GQDiAgAMAAEK4Q3c4gAxAAAAAA==.Armadian:BAAANQAECgQICAAAAA==.Arrianne:BAAANQADCgYIBgAAAA==.Arriella:BAAANQAECggIDAAAAA==.Arriånna:BAAANQADCgcIEwAAAA==.Artemist:BAABNQAECn8UAAINAAYKqg2y9QAyAQANAAYKqg2y9QAyAQAAAA==.',
As='Asifa:BAAANQAECgQIDgAAAA==.',
At='Atherion:BAABNQAECn8+AAIOAAoKxxOUCQAPAgAOAAoKxxOUCQAPAgAAAA==.Attackroot:BAAANQAECgUIBgABNQAECggIHQAPAI0LAA==.',
Au='Aurakk:BAAANQADCgYIEQABNQAECggIMQANAJ8TAA==.',
Av='Avelin:BAAANQADCgUIBQAAAA==.Avranarada:BAABNQAECn87AAMHAAoKDhYeIAAqAgAHAAoKDhYeIAAqAgADAAoKDhYOIAD+AQAAAA==.Avril:BAAANQAECgEIAQAAAA==.',
Az='Azhádi:BAAANQAECgEIAQAAAA==.Azkara:BAACNQAFFH8OAAIQAAYK/AwkEgA9AQAQAAYK/AwkEgA9AQA1AAQKfzYAAhAACgo3HkUdAM8CABAACgo3HkUdAM8CAAAA.Azung:BAABNQAECn8+AAINAAoK3iCwKwAZAwANAAoK3iCwKwAZAwAAAA==.',
Ba='Baatos:BAEANQAECggIAgABNQAECgkJHAAPAFQMAA==.Babaisyaga:BAACNQAFFH8WAAIBAAYK2xwSCQBdAQABAAYK2xwSCQBdAQA1AAQKf1YAAgEACgryJAwNAHYDAAEACgryJAwNAHYDAAAA.Baka:BAAANQAECgYICQAAAA==.Balinse:BAABNQAECn8fAAIRAAkKTRcMGQChAQARAAkKTRcMGQChAQABNQAECgoKIQAKAMsNAA==.Balystix:BAAANQADCggICAAAAA==.Barb:BAAANQAECgcIBwAAAA==.Barrelrollin:BAAANQAECgEIAgAAAA==.Basherdownn:BAAANQADCgQIBAAAAA==.',
Be='Beastfodays:BAACNQAFFH8JAAIBAAMKrhRiHQDIAAABAAMKrhRiHQDIAAA1AAQKfzUAAgEACgpxF8tDAKACAAEACgpxF8tDAKACAAAA.Bethlahammer:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.',
Bh='Bhassie:BAAANQAECgQIBAABNQAFFAYIEAASABoOAA==.',
Bi='Billcritin:BAAANQAECggIEAAAAA==.',
Bl='Blackleaf:BAAANQADCgcICgAAAA==.Blawyke:BAABNQAECn8ZAAMQAAoKoxE9PAAlAgAQAAoKoxE9PAAlAgATAAEKlgfOVwEhAAABNQAFFAIIBAACAAAAAA==.Bless:BAAANQADCggIDgABNQAECgYICgACAAAAAA==.Blizzcon:BAACNQAFFH8TAAIIAAUKexioDwCZAQAIAAUKexioDwCZAQA1AAQKf00AAggACgr2I2sJAHcDAAgACgr2I2sJAHcDAAAA.Bloodsurge:BAAANQADCgQJAwAAAA==.Blushies:BAABNQAECn83AAMTAAkK9x9sEADoAgATAAkK9x9sEADoAgAQAAMK8xC64wCiAAAAAA==.',
Bo='Boltzfodayz:BAAANQAECgIIAQAAAA==.Bonerslap:BAAANQAECgQIBQAAAA==.Boone:BAAANQADCgMIAwAAAA==.Borrgar:BAABNQAECn8xAAINAAgKnxOVsQBtAQANAAgKnxOVsQBtAQAAAA==.',
Br='Brackle:BAABNQAECn8eAAIBAAkKCxuQQgCjAgABAAkKCxuQQgCjAgAAAA==.Bracori:BAACNQAFFH8PAAIUAAYKewtjBQBEAQAUAAYKewtjBQBEAQA1AAQKf0cAAxQACgo+GwMIAOsCABQACgo+GwMIAOsCABUAAQoAAF9wAAAAAAAA.Brandywynne:BAABNQAECn8sAAIBAAoKsA+4ZQBJAgABAAoKsA+4ZQBJAgAAAA==.Bretcha:BAAANQADCgQIBAABNQAECgQIBgACAAAAAA==.Brick:BAABNQAECn8qAAIFAAoKcxeeDQCcAgAFAAoKcxeeDQCcAgAAAA==.Brightfame:BAABNQAECn89AAMWAAoK2BicBADDAQAWAAgKhBicBADDAQAXAAUKVBTpEQAsAQAAAA==.Bronny:BAABNQAECn8gAAIYAAkKSA3VuACOAQAYAAkKSA3VuACOAQAAAA==.Brônwyn:BAAANQADCgQIBAAAAA==.',
Bu='Buffshagwell:BAABNQAECn8pAAINAAkKhxdqWQCLAgANAAkKhxdqWQCLAgAAAA==.Bullrush:BAAANQADCgYICQAAAA==.Butterbllz:BAABNQAECn8pAAINAAoKhxs/XgB+AgANAAoKhxs/XgB+AgAAAA==.',
Ca='Caerhysa:BAAANQADCgQIBAAAAA==.Calypsio:BAAANQADCgQIBAABNQAECgMIAwACAAAAAA==.Camany:BAABNQAECn8oAAIBAAkKXRKMdwAgAgABAAkKXRKMdwAgAgAAAA==.Captinkrunch:BAAANQADCgEIAQAAAA==.Captinlock:BAAANQADCgEIAQABNQADCgEIAQACAAAAAA==.Captinmorí:BAAANQADCgEIAQAAAA==.Caretakerz:BAABNQAECn8tAAMSAAkKsB2yCwCuAgASAAkKsB2yCwCuAgAZAAEKjg3OTQAtAAAAAA==.Cartus:BAAANQAECgUICAABNQAECgcIFQASAAUJAA==.Cayin:BAABNQAECn8cAAILAAkKSiDsEwANAwALAAkKSiDsEwANAwABNQABCgYICwACAAAAAA==.',
Ch='Chanyeol:BAAANQAECggIEQAAAA==.Chemoshh:BAAANQADCggIBgABNQAECggIMQANAJ8TAA==.',
Cl='Clamshell:BAABNQAECn9CAAMaAAoKwiJ6CQAXAwAaAAoKwiJ6CQAXAwALAAUKwRi0YgBnAQAAAA==.Claudette:BAAANQAECgcICgAAAA==.Clayier:BAAANQADCgcIGQAAAA==.',
Cn='Cntendr:BAAANQADCgUICAAAAA==.',
Co='Codenike:BAABNQAECn84AAIVAAoKEBnNEABQAgAVAAoKEBnNEABQAgAAAA==.Coil:BAAANQADCggICgABNQAECgYICgACAAAAAA==.Copenzen:BAAANQAECgcIDgAAAA==.Corelheals:BAABNQAECn8ZAAIIAAgK0A67eQBtAQAIAAgK0A67eQBtAQAAAA==.Covertyqt:BAABNQAECn83AAIEAAoKQBziPwBNAgAEAAoKQBziPwBNAgAAAA==.',
Cp='Cptnhuman:BAABNQAECn9GAAIMAAoKcR0/EwBbAgAMAAoKcR0/EwBbAgAAAA==.',
Cr='Cromie:BAAANQADCggIFQAAAA==.Crosed:BAAANQADCgQIBAAAAA==.',
Cs='Cshunter:BAAANQADCgYIBwAAAA==.',
Cu='Cubcakes:BAAANQADCggIBQAAAA==.',
Cy='Cylcuria:BAAANQABCgIIAgAAAA==.',
['Cõ']='Cõrpses:BAEBNQAECn86AAILAAoK1h99DQDAAgALAAoK1h99DQDAAgABNQAECgoKJgASAGQkAA==.',
Da='Daboof:BAAANQAECgEIAQAAAA==.Daemandred:BAAANQADCgUIBQAAAA==.Daggere:BAAANQADCggIKAAAAA==.Danke:BAAANQAECgUIEAAAAA==.Dankz:BAABNQAECn8eAAINAAcKRwXVEgHNAAANAAcKRwXVEgHNAAAAAA==.Darkenmicky:BAAANQADCgcIEwAAAA==.Darkmickyz:BAABNQAECn8YAAIbAAcK1RDnNQA4AQAbAAcK1RDnNQA4AQAAAA==.Darthbobula:BAACNQAFFH8KAAINAAUKPQdcEgDxAAANAAUKPQdcEgDxAAA1AAQKfx0AAg0ACAqXEAbfAF0BAA0ACAqXEAbfAF0BAAAA.Dayloc:BAABNQAECn82AAIPAAoKnxBBSgD1AQAPAAoKnxBBSgD1AQAAAA==.',
De='Deataria:BAABNQAECn85AAIHAAoKCR0XCgAwAwAHAAoKCR0XCgAwAwAAAA==.Deathrho:BAAANQADCgUICwAAAA==.Deawin:BAAANQADCgQIBAABNQAECgEIAgACAAAAAA==.Delilia:BAEANQAECggICgABNQAECgkJHAAPAFQMAA==.Delryth:BAAANQADCgYIBQAAAA==.Demonikk:BAAANQAECgYIDgABNQAECgoKOAABAOEWAA==.Demontyk:BAAANQAECgYIEAABNQAECgoKOAABAOEWAA==.Desception:BAAANQADCgcICgAAAA==.Devourmax:BAABNQAECn8YAAIcAAoKNARyHwCyAAAcAAoKNARyHwCyAAAAAA==.',
Di='Diablõ:BAEBNQAECn8XAAMdAAkKuQ5VEQAzAQAeAAkKfQpxMQCNAQAdAAgKvA1VEQAzAQABNQAECgoKJgASAGQkAA==.Diadochi:BAAANQAECgQJBQAAAA==.Dieguerta:BAAANQADCgEJAQAAAA==.',
Dl='Dl:BAABNQAECn8zAAIKAAoK2Bm9GQCAAgAKAAoK2Bm9GQCAAgAAAA==.',
Dr='Drakkarr:BAAANQADCgYIBwAAAA==.Drazhoath:BAAANQAECgUIDQAAAA==.Drdrill:BAAANQADCgYIBgAAAA==.Drimbirt:BAAANQADCgcICgAAAA==.Drinkmormilk:BAAANQAECgQIBgAAAA==.Drogelf:BAAANQADCgcIGQAAAA==.Drogman:BAAANQADCgIIAgAAAA==.',
Du='Dumbledore:BAAANQADCgcIBwABNQAECgEIAQACAAAAAA==.',
['Dá']='Dáwnbringer:BAAANQADCgIIBAAAAA==.',
Eb='Ebullition:BAAANQAECggICgAAAA==.',
Ed='Edensfury:BAAANQAECgIIAgAAAA==.',
Ee='Eedani:BAAANQADCgUJCQAAAA==.',
Ei='Eigi:BAABNQAECn8iAAIBAAoKQxVfZQD6AQABAAoKQxVfZQD6AQAAAA==.',
El='Eldanon:BAABNQAECn9AAAIWAAoKhyMfAQCRAwAWAAoKhyMfAQCRAwAAAA==.Elementality:BAAANQADCgIIAgAAAA==.Eleyert:BAACNQAFFH8QAAITAAUKSiWxCQBDAQATAAUKSiWxCQBDAQA1AAQKfzkAAhMACgqOJtcAAI4DABMACgqOJtcAAI4DAAAA.Elistann:BAAANQAECgQIBAABNQAECggIMQANAJ8TAA==.Elwe:BAABNQAECn8jAAIIAAkKkxXMcgDEAQAIAAkKkxXMcgDEAQAAAA==.',
Em='Embaku:BAAANQADCggICAABNQAECgoKSQANALwVAA==.Emiri:BAAANQAECgQIBQAAAA==.Emrhakul:BAAANQABCggIFQAAAA==.',
En='Enkidu:BAABNQAECn8yAAIBAAgKZxQihwCqAQABAAgKZxQihwCqAQAAAA==.Enseth:BAABNQAECn87AAIfAAoK+goFDACaAQAfAAoK+goFDACaAQAAAA==.',
Er='Erakha:BAAANQAECgQIBgAAAA==.Erandria:BAAANQAECgMIAwABNQAECgQICAACAAAAAA==.',
Eu='Eulogy:BAAANQADCgYICAABNQAFFAUIEwAIAHsYAA==.',
Ez='Ezki:BAAANQADCggIFwABNQAECggIMQANAJ8TAA==.',
Fa='Fairious:BAABNQAECn9IAAIFAAoKWBnqKABeAgAFAAoKWBnqKABeAgAAAA==.',
Fe='Felcon:BAAANQADCgYICQAAAA==.Felenkeller:BAAANQAECgIIBgABNQAFFAcICwAMAJ0SAA==.Fenrirr:BAAANQADCggICAABNQAECggIMQANAJ8TAA==.Fet:BAABNQAECn8rAAMGAAoKSyCEDQDzAQAFAAgKDR6PEQBoAgAGAAkK5R2EDQDzAQAAAA==.',
Fh='Fhatbashtud:BAAANQAECgQICAAAAA==.',
Fl='Flashfiré:BAAANQAECgQIBAABNQAECgoKNQAgAI8eAA==.Flashies:BAAANQAECgQIBgABNQAECgkJNwATAPcfAA==.Flatline:BAABNQAECn8wAAIJAAoKvhxxAQAQAwAJAAoKvhxxAQAQAwAAAA==.Flinnt:BAAANQADCgUIBwABNQAECggIMQANAJ8TAA==.',
Fn='Fngusamungus:BAAANQAECgEIAQAAAA==.',
Fo='Folgore:BAAANQAECgQIDgAAAA==.Four:BAAANQAECgcIEAAAAA==.',
Fr='Fredwarlock:BAAANQAECgUIBwAAAA==.Frysky:BAABNQAECn8lAAMDAAoKLg1DLgCTAQADAAoKKwtDLgCTAQAZAAgKGw0YGAB4AQAAAA==.',
Fu='Furiousv:BAAANQADCgUIBQAAAA==.Futz:BAABNQAECn88AAIhAAoK1iIQHgD5AgAhAAoK1iIQHgD5AgAAAA==.',
['Fõ']='Fõrged:BAEANQAECggICAABNQAECgoKJgASAGQkAA==.',
Ga='Gahnzul:BAAANQADCgUICgAAAA==.Gajitbek:BAAANQADCgUICAAAAA==.Galah:BAABNQAECn8YAAIEAAcK4g498gCmAQAEAAcK4g498gCmAQAAAA==.Gardurst:BAABNQAECn8tAAITAAoKVhurKgA0AgATAAoKVhurKgA0AgAAAA==.',
Gn='Gnomicide:BAAANQAECgQIEAAAAA==.',
Go='Gonesh:BAAANQADCggIEAAAAA==.Gooberpea:BAAANQABCgYIEAAAAA==.Gordoe:BAAANQADCgUICgAAAA==.',
Gr='Graveborne:BAAANQADCggIEQAAAA==.Gravess:BAAANQADCgUICwAAAA==.Gravewin:BAAANQADCgQICgABNQAECgEIAgACAAAAAA==.Gravyexpress:BAABNQAECn9YAAMeAAoKBhw/FwDhAgAeAAoK6Bs/FwDhAgAiAAcKxhTCPQBbAQAAAA==.Grendelheim:BAAANQAECgEIAQAAAA==.Grogar:BAAANQADCgcIFQAAAA==.Groxxigar:BAAANQADCgUIBQAAAA==.',
Gu='Gula:BAAANQAECgYIEgABNQAECgoKJgAVAKwRAA==.',
Ha='Hadez:BAAANQADCgUIBQAAAA==.Hagrok:BAAANQAECgEIAQAAAA==.Hairybubble:BAAANQADCggICAAAAA==.Hakusei:BAAANQADCgMIAwAAAA==.Hantak:BAAANQADCgMIBgAAAA==.Harmsway:BAAANQADCgcIEQAAAA==.Hathaendron:BAAANQADCgYIBgAAAA==.',
He='Hephaestus:BAAANQAECgUICAAAAA==.',
Ho='Hocka:BAAANQADCgUIBgAAAA==.Holysmight:BAAANQAECgEIAQAAAA==.Holyumo:BAAANQADCgYIBgAAAA==.Holyyballs:BAAANQAECgcICwABNQAECgoKIwAOAPwPAA==.Howlymandel:BAAANQAECggICAABNQAECgkJGwABAA4IAA==.Hoytx:BAAANQADCgUIBQAAAA==.',
Hy='Hydraciel:BAAANQAECgYIDgAAAA==.',
['Hì']='Hìroko:BAABNQAECn8iAAMWAAgKYAbFOwDSAAAPAAgKbwWMsADzAAAWAAYKzwPFOwDSAAAAAA==.',
Ic='Icecreamkohn:BAAANQAECgQIBAABNQAECgoKIQAhAFwlAA==.Icedemon:BAABNQAECn8dAAMLAAgKphg1KAC9AQALAAgKphg1KAC9AQAaAAEKTwrZtQAzAAAAAA==.Iceliandra:BAAANQADCggIDgAAAA==.Iceveloric:BAAANQADCgYIAwAAAA==.Icupapi:BAAANQADCggILwAAAA==.Icynips:BAAANQABCgEIAQAAAA==.',
Ig='Ignitionfish:BAAANQAECgIIAwABNQAECgkJNwATAPcfAA==.',
Im='Im:BAAANQADCgEJAQABNQAFFAEIBQAFAAAAAA==.Imabigman:BAAANQADCgcICAAAAA==.Imaleaf:BAABNQAECn8aAAIDAAgKMQbsXQBZAQADAAgKMQbsXQBZAQAAAA==.Imperius:BAAANQAECgEIAQAAAA==.',
In='Insillico:BAAANQAECgEIAQABNQAECgoKOAABAOEWAA==.',
Ip='Iplaydead:BAABNQAECn84AAMBAAoK4RZnRgBFAgABAAoK4RZnRgBFAgAjAAEKAACnmgAmAAAAAA==.',
Ir='Iroh:BAABNQAECn8bAAIVAAkKcRkNIQAkAgAVAAkKcRkNIQAkAgAAAA==.',
Is='Ismokeprot:BAAANQADCgQIBAAAAA==.',
Ja='Jabelemachus:BAAANQAECgQIBAABNQAFFAYIBgAUAEQfAA==.Jacii:BAAANQAECggICwABNQAECgoKQgAaAMIiAA==.Jawnson:BAABNQAECn8VAAIFAAgKeg4KHAD1AQAFAAgKeg4KHAD1AQAAAA==.',
Je='Jelluz:BAAANQADCgYIBgAAAA==.Jenefer:BAACNQAFFH8PAAILAAYK8BkEDwAVAQALAAYK8BkEDwAVAQA1AAQKf0QAAwsACgohIT8LANwCAAsACgohIT8LANwCAAwAAgrsFBS4AH0AAAAA.Jeslartoma:BAAANQADCgEIAQABNQAECgMIBAACAAAAAA==.',
Ji='Jimjimmy:BAAANQADCgcIBwABNQAECgIIAgACAAAAAA==.',
Jo='Jondooz:BAAANQAECgcIBwAAAA==.Jonoisanerd:BAABNQAECn8UAAIiAAoKZQ9zGgDZAQAiAAoKZQ9zGgDZAQAAAA==.Joulecrafter:BAAANQAECgUIBQABNQAECgoKSQANALwVAA==.',
Jp='Jpegz:BAAANQADCgcIBgABNQAECgoKRwANAIIiAA==.',
Ka='Kailana:BAAANQAECgEIAgABNQAECgoKNQAgAI8eAA==.Kailback:BAAANQAECgYIEQABNQAECgoKNQAgAI8eAA==.Kait:BAABNQAECn8+AAMQAAoKHhpJHgDIAgAQAAoKHhpJHgDIAgATAAUKowy3mQDUAAAAAA==.Kalcifur:BAACNQAFFH8PAAMhAAUKGBSnEQAmAQAhAAUKGBSnEQAmAQAbAAEKGgz7EgA2AAA1AAQKf0gAAyEACgqKIpMFAMQDACEACgqKIpMFAMQDABsABgqNGXIiAFsBAAAA.Karin:BAAANQAECgIIAwABNQAECgcIFQASAAUJAA==.Karnelian:BAAANQAECggIEAABNQAFFAYIBgAUAEQfAA==.Karras:BAAANQADCgUIBQAAAA==.Kashisht:BAAANQAECgIIAgAAAA==.Kasstigate:BAABNQAECn8mAAIYAAoKERhNPQBMAgAYAAoKERhNPQBMAgABNQAFFAYIDwALAPAZAA==.Kastiel:BAABNQAECn8hAAIKAAoKyw3uLQC2AQAKAAoKyw3uLQC2AQAAAA==.Katstrider:BAABNQAECn9AAAIBAAoKcRfoZQD5AQABAAoKcRfoZQD5AQAAAA==.Kattarea:BAAANQADCgUJCAABNQAECgoKQAABAHEXAA==.Kavica:BAAANQAECggIDwABNQAECgoKPAAHAEshAA==.',
Ke='Keldean:BAABNQAECn8cAAIRAAkKhhyACgCZAgARAAkKhhyACgCZAgAAAA==.Keryka:BAACNQAFFH8QAAMaAAYK4SGgCABTAQAaAAYK4SGgCABTAQAMAAEKZRJXIQBHAAA1AAQKf0QAAxoACgq4IrUKAEQDABoACgqIILUKAEQDAAwACArMGy1FAAQCAAAA.',
Kh='Khere:BAAANQAECgQIBgAAAA==.',
Ki='Kirigiri:BAABNQAECn8bAAMHAAoKMBZhGgA6AgAHAAkKORVhGgA6AgASAAIK6RqpYwBLAAABNQAFFAUIDwAhABgUAA==.Kirøs:BAAANQAECgMIBQAAAA==.Kiterisa:BAABNQAECn9LAAIQAAoKqA6aQwAFAgAQAAoKqA6aQwAFAgAAAA==.',
Kk='Kkazz:BAAANQADCggICwABNQAECggIMQANAJ8TAA==.',
Ko='Kohn:BAABNQAECn8hAAIhAAoKXCU8AQAzBAAhAAoKXCU8AQAzBAAAAA==.Kona:BAEBNQAECn8mAAQSAAoKZCSuAgBNAwASAAoKZCSuAgBNAwAZAAcK9BpREQCyAQAHAAIKkQHHggAfAAAAAA==.Korbusty:BAAANQADCggIDgAAAA==.',
Ku='Kuattieb:BAAANQABCgIIAgAAAA==.',
La='Ladýfinger:BAABNQAECn84AAQhAAoKAhJ8YQD0AQAhAAkKWBN8YQD0AQAbAAgKEgvWJgA5AQANAAQKJghDWwGOAAABNQAFFAYIEAASABoOAA==.Laisidhiel:BAAANQAECgUICQAAAA==.Lateo:BAABNQAECn8oAAIFAAoKKQv7YACJAQAFAAoKKQv7YACJAQAAAA==.Lawz:BAABNQAECn8gAAMXAAkKzgXFEABAAQAXAAkKzgXFEABAAQAWAAIKOAAGegA0AAAAAA==.',
Le='Lelianna:BAAANQAECgEIAQAAAA==.Lemonruss:BAAANQADCggIEQAAAA==.Levibigguns:BAAANQADCggIEAABNQAECgkJMAAVAL0SAA==.Lexia:BAAANQAECgYICwAAAA==.',
Li='Libidine:BAAANQADCgQIBAABNQAECgoKJgAVAKwRAA==.Liemannin:BAAANQAECgEIAQAAAA==.Lilaa:BAAANQADCgcIBwAAAA==.Lilturtz:BAAANQAECgUIBgABNQAECgkJNwATAPcfAA==.Linnea:BAAANQADCgcIDQAAAA==.',
Ll='Llekra:BAAANQADCgEIAQAAAA==.',
Lo='Locksative:BAAANQADCggIJgAAAA==.Longhorn:BAABNQAECn80AAINAAkK7Q5QsgC6AQANAAkK7Q5QsgC6AQAAAA==.Lorekesh:BAAANQADCgEJAQABNQAECgcICgACAAAAAA==.Lorriena:BAAANQAECgEIAQABNQAECgIIAwACAAAAAA==.Lorrè:BAAANQADCgQIBAABNQAECgIIAwACAAAAAA==.Lortpegsalot:BAABNQAECn9HAAINAAoKgiKPJQDLAgANAAoKgiKPJQDLAgAAAA==.Lowy:BAAANQAECgUIAwAAAA==.',
Lu='Lucena:BAABNQAECn8zAAIIAAkK3yJ6DAB9AwAIAAkK3yJ6DAB9AwAAAA==.Lurg:BAAANQADCggICgABNQADCggIJgACAAAAAA==.Luxuria:BAABNQAECn8cAAQFAAkKDQwxTwDGAQAFAAkKDQwxTwDGAQAkAAQKgwYaCQB0AAAGAAEKrAcZaQAuAAABNQAECgoKJgAVAKwRAA==.',
Ly='Lyralana:BAAANQAECgQICAAAAA==.',
Ma='Maberu:BAACNQAFFH8HAAIUAAQK7gOoBwDWAAAUAAQK7gOoBwDWAAA1AAQKfycAAhQACgr1DmscAL0BABQACgr1DmscAL0BAAE1AAUUBQgPACEAGBQA.Madamholy:BAABNQAECn8YAAIIAAcKXR+hVwAbAgAIAAcKXR+hVwAbAgAAAA==.Madamkluck:BAAANQADCgUIBQAAAA==.Maglubiyet:BAABNQAECn8hAAIgAAcK1gtIIAAiAQAgAAcK1gtIIAAiAQAAAA==.Magnitood:BAABNQAECn8VAAMHAAcKBxTUMgCEAQAHAAcKBxTUMgCEAQADAAEKAAB+rgA5AAAAAA==.Malbjornion:BAABNQAECn8mAAMZAAgKnAy6JgDMAAAZAAcKzQ26JgDMAAASAAcKCQSBRwCgAAAAAA==.Malphox:BAAANQADCgQICAAAAA==.Manbearcat:BAABNQAECn8VAAISAAcKBQm/NgDwAAASAAcKBQm/NgDwAAAAAA==.Manhole:BAAANQAECgQIDAAAAA==.Markyb:BAAANQADCggIEQAAAA==.Masamura:BAACNQAFFH8SAAMEAAYK5hRHJADnAAAEAAUKExdHJADnAAAOAAIKfwchCgBxAAA1AAQKfz0AAwQACgqdHHpnAK8CAAQACgo/G3pnAK8CAA4AAgo0G+YrAJwAAAAA.Maureanna:BAAANQADCgUIDgABNQAECgQICAACAAAAAA==.',
Me='Mechahuntard:BAAANQADCgEIAQAAAA==.Medanii:BAEBNQAECn8fAAQJAAkKghFeDQBeAQAJAAYKVRJeDQBeAQAIAAUKUREcrAASAQAKAAQKTQenVwCsAAAAAA==.Melorm:BAAANQAECgQIDgAAAA==.Meno:BAAANQADCggICAAAAA==.',
Mi='Millizh:BAACNQAFFH8iAAMBAAkKHB+xAgDtAQABAAYKlx6xAgDtAQAjAAUKGR6cDwBDAQA1AAQKfygAAyMACgoJJhsGAG8DACMACQpXJhsGAG8DAAEABwq3IfWRAOUBAAAA.Mirasharu:BAAANQAECgEIAQAAAA==.Mireille:BAAANQADCgYIDQAAAA==.Mitsuri:BAABNQAECn8zAAINAAkKyg8ImQCbAQANAAkKyg8ImQCbAQAAAA==.Mitzuky:BAAANQADCgMIAwAAAA==.',
Mo='Mommamoon:BAAANQADCgQIBAABNQAECgoKIgANAM0ZAA==.Moonlïght:BAABNQAECn8iAAINAAoKzRn0YgAMAgANAAoKzRn0YgAMAgAAAA==.Morganlefay:BAABNQAECn8tAAIPAAoKdQLTyQC9AAAPAAoKdQLTyQC9AAAAAA==.Morlyn:BAABNQAECn8oAAIOAAkKFhdFDQDdAQAOAAkKFhdFDQDdAQAAAA==.Morregan:BAAANQAECgcICAAAAA==.Motion:BAAANQADCgcICgABNQAECgYICgACAAAAAA==.Mousereaper:BAABNQAECn8kAAIiAAoKtg/hLwDDAQAiAAoKtg/hLwDDAQAAAA==.',
My='Mydnight:BAAANQABCgIIAgAAAA==.Mystìc:BAABNQAECn81AAQgAAoKjx4lDwAhAgAgAAkK6h0lDwAhAgATAAYKOxzObADaAQAQAAEKaQr2IwEpAAAAAA==.Mystíc:BAAANQAECgYICAABNQAECgoKNQAgAI8eAA==.',
['Má']='Májorrobot:BAABNQAECn8wAAIYAAoKzyFrLgAEAwAYAAoKzyFrLgAEAwAAAA==.',
['Mé']='Ménopáwz:BAABNQAECn8YAAISAAkKoBSoFQDnAQASAAkKoBSoFQDnAQABNQAFFAcICwAMAJ0SAA==.',
Na='Namor:BAAANQAECgMIAwAAAA==.Nattisca:BAAANQAECgMIBAAAAA==.',
Ne='Nervanna:BAAANQAECgMIAwABNQAFFAEIAQACAAAAAA==.Nessà:BAABNQAECn8mAAMVAAoKrBE/FwD/AQAVAAoKrBE/FwD/AQAlAAEKKw+zJgA2AAAAAA==.Neveen:BAAANQAECgMIAwAAAA==.Neveenn:BAACNQAFFH8HAAIHAAMK8Qn3DgCyAAAHAAMK8Qn3DgCyAAA1AAQKf0YAAwcACgqWHQ8PAOQCAAcACgqWHQ8PAOQCABIAAwohBGZrADsAAAAA.',
Ni='Nirith:BAAANQADCgYIEwAAAA==.',
No='Nohatcat:BAAANQAECgQIBgABNQAECgkJNwATAPcfAA==.',
['Nâ']='Nâmii:BAAANQAECgMIAwAAAA==.',
['Nè']='Nèzukõ:BAABNQAECn8kAAIBAAkKQheHiwDzAQABAAkKQheHiwDzAQAAAA==.',
Ob='Obata:BAAANQAECgQIBQAAAA==.',
Oc='Octavius:BAAANQADCggJDQABNQAECgIIAgACAAAAAA==.',
Od='Odi:BAAANQADCgQIBAAAAA==.',
Oj='Ojore:BAEBNQAECn8jAAIaAAgKagxhUgBnAQAaAAgKagxhUgBnAQAAAA==.Ojoverde:BAACNQAFFH8PAAIPAAYKoAZYFQD7AAAPAAYKoAZYFQD7AAA1AAQKf0gAAg8ACgpBFLtLAPABAA8ACgpBFLtLAPABAAAA.',
On='Onizuka:BAAANQADCgEIAQABNQADCgcICQACAAAAAA==.Onside:BAAANQAECgcICgABNQAFFAUICgAVAAcVAA==.',
Op='Ophillã:BAABNQAECn8qAAQJAAoKNBpEBQDDAQAIAAgKmhm7LQCPAgAJAAgKbBdEBQDDAQAKAAYKnBOSQAArAQABNQAECgoKJgAVAKwRAA==.',
Or='Ordenn:BAAANQADCgQICAABNQAECgoKKwAGAEsgAA==.Orian:BAAANQADCgQIBwAAAA==.',
Oz='Ozz:BAABNQAECn8ZAAIVAAgKFw/aLgChAQAVAAgKFw/aLgChAQAAAA==.Ozzerker:BAAANQADCgEIAQAAAA==.Ozzullr:BAABNQAECn8XAAIBAAkKAht3MgDVAgABAAkKAht3MgDVAgAAAA==.',
Pa='Painbreak:BAAANQADCgEIAQABNQAECgkJLQASALAdAA==.Pajamas:BAAANQAECgEIAQABNQAECggIHQAPAI0LAA==.Pallanquin:BAAANQADCgYIDgAAAA==.Papichili:BAABNQAECn8VAAITAAUK8wr0oADFAAATAAUK8wr0oADFAAAAAA==.Pashnir:BAAANQADCgcICQAAAA==.',
Pe='Peachey:BAABNQAECn8kAAIQAAoKZhWYSQDsAQAQAAoKZhWYSQDsAQAAAA==.Peaker:BAAANQAECgQIAwAAAA==.Peakra:BAABNQAECn8nAAIIAAoKaxiUMACBAgAIAAoKaxiUMACBAgAAAA==.',
Ph='Phoênix:BAAANQADCgMIAwAAAA==.',
Pi='Pigas:BAABNQAECn8wAAIVAAkKvRJiKADdAQAVAAkKvRJiKADdAQAAAA==.',
Pr='Prestoresto:BAAANQADCgYIDwAAAA==.',
Ps='Psychosix:BAABNQAECn8dAAIEAAoKcR9mSwDrAgAEAAoKcR9mSwDrAgAAAA==.',
Qu='Quinberos:BAAANQAECgYICgAAAA==.',
Ra='Racey:BAAANQADCggICAAAAA==.Raiistlin:BAAANQADCgYIBwABNQAECggIMQANAJ8TAA==.Ramdel:BAAANQAECgUICwABNQAECgoKRQAmAFIbAA==.Ramstrider:BAABNQAECn9FAAMmAAoKUhv0AgCRAgAmAAoKUhv0AgCRAgABAAIKaQcTOAF2AAAAAA==.Ranah:BAAANQAECgYIBgABNQAECgcICAACAAAAAA==.Ranch:BAAANQADCgcICQAAAA==.Rapture:BAABNQAECn85AAIiAAoKjQ65HwCkAQAiAAoKjQ65HwCkAQAAAA==.Ravec:BAAANQADCgMIAwAAAA==.Rayziel:BAAANQADCggICAABNQAECgMIBQACAAAAAA==.',
Re='Rengell:BAABNQAECn8bAAIBAAkKDgjU1gAFAQABAAkKDgjU1gAFAQAAAA==.Reptiliano:BAAANQAECggIEQABNQAFFAUIBwAGAJwOAA==.',
Rh='Rheagall:BAABNQAECn88AAIgAAoKTiOPAwAUAwAgAAoKTiOPAwAUAwAAAA==.Rhodetta:BAABNQAECn8bAAIIAAoKAxS5OgB+AgAIAAoKAxS5OgB+AgABNQAFFAEIAQACAAAAAA==.',
Ri='Rizepriest:BAAANQADCgIIAgABNQAECgcIFAAYAEghAA==.Rizerage:BAABNQAECn8UAAIYAAcKSCENbABOAgAYAAcKSCENbABOAgAAAA==.',
Ro='Roaraxe:BAAANQADCgYIBgABNQAECgIIAgACAAAAAA==.Rowena:BAABNQAECn9HAAIDAAoK8xa5JADXAQADAAoK8xa5JADXAQAAAA==.Rowynna:BAAANQAECgMIAwABNQAECgYICgACAAAAAA==.Roxy:BAAANQADCgYIBgAAAA==.Roxymonk:BAAANQADCgYIBgAAAA==.Royalviaman:BAAANQADCgcICgAAAA==.',
Ry='Ryz:BAAANQADCggICAAAAA==.Ryztkmtchrch:BAACNQAFFH8FAAIIAAIKdhxbKACTAAAIAAIKdhxbKACTAAA1AAQKfzgABAgACgoKHWcyAJ4CAAgACgoKHWcyAJ4CAAkABwrDDe8MAGgBAAoABQqMDzNHAAIBAAAA.',
['Rå']='Råti:BAAANQAECgQIAwAAAA==.',
['Rø']='Rønis:BAAANQADCggICAAAAA==.',
Sa='Sacdk:BAAANQAECgQIBwAAAA==.Saetta:BAAANQAECgYIBgAAAA==.Safaria:BAAANQAECgQIBwABNQAECgYIGgAIAIsJAA==.Saloenus:BAAANQAECgYICgAAAA==.Satharis:BAAANQAECgUIBQABNQAECgoKOwAfAPoKAA==.Saucehoss:BAABNQAECn8mAAQXAAkKQx3sAwCrAgAXAAkKQx3sAwCrAgAWAAQKLQ8MPQDNAAAPAAMKkhTNBQHAAAAAAA==.Saucymac:BAACNQAFFH8JAAMKAAUKCQn+BwAXAQAKAAQKCQn+BwAXAQAIAAMKywHcKACgAAA1AAQKfyUAAwoACgrjHdMPAFwCAAoACQp0HdMPAFwCAAgACQrjB/q0APgAAAAA.',
Sc='Scofflaw:BAAANQADCgEIAQABNQAECgQIBAACAAAAAA==.Scootr:BAAANQAECggIDQAAAA==.Scubasteve:BAAANQADCgUICgAAAA==.',
Se='Sefi:BAABNQAECn81AAMNAAkKohNVnwCPAQANAAkK2xJVnwCPAQAbAAQKlQ3+TgCsAAAAAA==.Semirrhage:BAAANQADCgMIAwAAAA==.Serandipity:BAAANQAECgQIBAABNQAFFAYIDwALAPAZAA==.',
Sh='Shadowflame:BAABNQAECn8dAAIPAAgKjQs5mAAoAQAPAAgKjQs5mAAoAQAAAA==.Shallator:BAAANQAECgQIBAAAAA==.Shamanigans:BAAANQAECgcIDAABNQAECgcIFQAHAAcUAA==.Shammygoat:BAABNQAECn8nAAITAAgKERxzYgBfAQATAAgKERxzYgBfAQAAAA==.Shaqattack:BAACNQAFFH8KAAIVAAUKBxU5CgDSAAAVAAUKBxU5CgDSAAA1AAQKfzkAAhUACgoIIAgLALACABUACgoIIAgLALACAAAA.Shaqattaq:BAABNQAECn8nAAMFAAoKiRuTIQCEAgAFAAkK3BmTIQCEAgAGAAkK8heZIwBrAgABNQAFFAUICgAVAAcVAA==.Sharktide:BAABNQAECn8kAAIQAAoK0xbZXwDvAQAQAAoK0xbZXwDvAQAAAA==.Shawnella:BAABNQAECn83AAMVAAoKPh+vEABSAgAVAAkKnB6vEABSAgAUAAIKTQf1RABYAAAAAA==.Shawnellie:BAAANQAECgcIBgAAAA==.Shenlune:BAAANQAECgYIEQAAAA==.Sheutka:BAAANQAECgQIEAAAAA==.Shiggles:BAAANQAECgIIAQAAAA==.Shinaie:BAABNQAECn8ZAAIKAAgKxQp8OABhAQAKAAgKxQp8OABhAQAAAA==.Shocknrollz:BAAANQAECgQIDAAAAA==.Shogún:BAABNQAECn8qAAILAAkKlx0IFQBjAgALAAkKlx0IFQBjAgAAAA==.Shtylez:BAABNQAECn8cAAMRAAoKzAg3GgA3AQARAAgK3gk3GgA3AQAYAAYK+wPPBQHRAAABNQAECgoKOAABAOEWAA==.',
Si='Silntwolf:BAAANQABCgQIBAAAAA==.Silpion:BAABNQAECn8UAAInAAcKTgeWBQAiAQAnAAcKTgeWBQAiAQAAAA==.Silth:BAAANQADCggIKQAAAA==.Silvermist:BAAANQAECgQIBAAAAA==.Sinariel:BAABNQAECn87AAIUAAoK9BzmCADUAgAUAAoK9BzmCADUAgAAAA==.Sirdank:BAAANQAECgEIBQAAAA==.',
Sk='Skarlate:BAAANQADCgYIBgAAAA==.Skâld:BAEANQADCgYICwAAAA==.',
Sl='Sliko:BAABNQAECn9TAAINAAoKZRY5ZAAJAgANAAoKZRY5ZAAJAgAAAA==.',
Sm='Smmoke:BAABNQAECn9LAAIBAAoKSBjHRABJAgABAAoKSBjHRABJAgAAAA==.',
Sn='Sneekyone:BAAANQABCgUIBwAAAA==.Sneekypally:BAABNQAECn8nAAINAAYKDQTvIwHjAAANAAYKDQTvIwHjAAAAAA==.Snowballs:BAABNQAECn8jAAMOAAoK/A/kDQC4AQAOAAkKIxHkDQC4AQAEAAgK5wlECgF8AQAAAA==.',
So='Softhorn:BAAANQABCgUIBQAAAA==.Sorenreign:BAAANQAECgEIAQAAAA==.Sothh:BAAANQADCggIEAABNQAECggIMQANAJ8TAA==.Soull:BAABNQAECn9NAAIHAAoKTSU7AgD5AwAHAAoKTSU7AgD5AwAAAA==.Soulsmash:BAAANQAECgYIDgAAAA==.',
Sp='Spacebabe:BAAANQAECgQIBQABNQAECgcIGgAfAOQKAA==.Spacestepdad:BAABNQAECn8aAAQfAAcK5AqnHwBbAQAfAAcK5AqnHwBbAQAoAAYKlwpOMQAQAQApAAIKJgRPHwAnAAAAAA==.Sparkie:BAAANQAECgMIAwAAAA==.Spriggan:BAAANQAECgUIBQAAAA==.',
Sq='Squashfoot:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.',
St='Starface:BAACNQAFFH8QAAISAAYKGg6HAwDdAAASAAYKGg6HAwDdAAA1AAQKf0AAAxIACgqNHfwKAL8CABIACgqNHfwKAL8CABkABwpGFpITAJIBAAAA.Stargoose:BAAANQAECgUICAABNQAFFAYIEAASABoOAA==.Starphoenix:BAAANQADCggIFwAAAA==.Steelytree:BAAANQADCgcICgAAAA==.Stellaria:BAABNQAECn8XAAIhAAYKGBEkjQARAQAhAAYKGBEkjQARAQAAAA==.Steris:BAAANQADCggIIgABNQADCggIJgACAAAAAA==.Steverogers:BAABNQAECn8WAAMNAAcKAR1whQDBAQANAAcKAR1whQDBAQAbAAIK4APKgAAcAAABNQAFFAcICwAMAJ0SAA==.Stocktonrush:BAACNQAFFH8LAAQMAAcKnRJhDQA2AQAMAAUKwBRhDQA2AQAaAAQKMRB2EADOAAALAAEKAACCKgBMAAA1AAQKfzkABAwACgrxJEwQADQDAAwACQolJUwQADQDABoABgrgH+QpAA4CAAsAAwouJL9KABIBAAAA.Stonedhenge:BAAANQABCgQIBAAAAA==.Sturmx:BAABNQAECn9LAAIeAAoKixdoHQAiAgAeAAoKixdoHQAiAgAAAA==.',
Su='Subedei:BAABNQAECn89AAQaAAoKSiEoDAD5AgAaAAoK8yAoDAD5AgAMAAgKtRqcRQACAgALAAEK0Q7hyQA2AAAAAA==.Submison:BAAANQADCgYIBgABNQAECgoKIwAOAPwPAA==.Summerseve:BAAANQAECgMIAwAAAA==.Sunderhorn:BAAANQAECgQIDgAAAA==.Suriaa:BAABNQAECn9DAAMGAAoK6hh5DAAFAgAGAAoK6hh5DAAFAgAkAAQKugu8EwDBAAAAAA==.',
Sv='Svictis:BAABNQAECn8VAAIMAAgK2AgJQAAQAQAMAAgK2AgJQAAQAQAAAA==.Svictiss:BAAANQADCggIEQAAAA==.',
Sw='Swami:BAAANQAECgQIBAAAAA==.',
Ta='Talila:BAABNQAECn85AAISAAgKuR5DEgAUAgASAAgKuR5DEgAUAgAAAA==.Taniss:BAAANQADCggIFgABNQAECggIMQANAJ8TAA==.Taurdeth:BAABNQAECn8YAAQLAAgKGAx5YABwAQALAAgK5gt5YABwAQAMAAIKFQSsdQBTAAAaAAIKXgs8vAAqAAABNQAFFAEIAQACAAAAAA==.',
Te='Terrya:BAAANQAECgUIBQAAAA==.Teryail:BAAANQAECgEIAQAAAA==.',
Th='Thaqdaddy:BAAANQADCgYIBgABNQAECgoKKQALACwVAA==.Thaqknight:BAABNQAECn8pAAILAAoKLBXcMwA+AgALAAoKLBXcMwA+AgAAAA==.Therylnn:BAAANQAECgIIAQAAAA==.Thesthamenth:BAAANQADCgYIBgAAAA==.Thiccthaq:BAAANQAECgYICAABNQAECgoKKQALACwVAA==.Thily:BAAANQADCgIIAgAAAA==.Thorwallen:BAAANQADCggIFAABNQAECggIMQANAJ8TAA==.Thror:BAAANQAECgEIAQAAAA==.',
Ti='Tiac:BAAANQAECgEIAQAAAA==.Tiergyll:BAAANQABCgIIBgAAAA==.Tirithor:BAABNQAECn9JAAINAAoKvBWlawD4AQANAAoKvBWlawD4AQAAAA==.',
To='Tockell:BAAANQADCgQIBwAAAA==.Togala:BAAANQADCgYIDgABNQAECgQIBgACAAAAAA==.Toothless:BAAANQAECgEIAQAAAA==.Torbin:BAAANQAECgYIDgAAAA==.Touchmywave:BAAANQADCgcIDgABNQAFFAMICQABAK4UAA==.',
Tr='Trichinella:BAAANQAECggIDAABNQAECgoKKQALACwVAA==.Tryhunt:BAAANQAECgUIBAAAAA==.Tryjinks:BAABNQAECn8mAAMTAAoKHRAjaADoAQATAAkKQQ4jaADoAQAQAAcKCxHIjQBmAQAAAA==.',
Ts='Tsunameh:BAABNQAECn8dAAMIAAkKEBIeUAD5AQAIAAkKEBIeUAD5AQAKAAEKdAKBagAnAAABNQAECgoKOAABAOEWAA==.',
Tu='Tusky:BAAANQADCgYIBgAAAA==.',
Tw='Twohandtug:BAAANQADCggIGwAAAA==.',
Ty='Tykahndrius:BAABNQAECn8xAAMbAAoKWhgeHQACAgAbAAoKWhgeHQACAgANAAcKKBEo4gAaAQABNQAECgoKOAABAOEWAA==.Tylîus:BAABNQAECn8jAAQiAAoKtRS8JQAYAgAiAAgKZBa8JQAYAgAdAAUKBBg+HACwAAAeAAIK2QkZcwBhAAAAAA==.Tylïus:BAAANQAECgIIAQABNQAECgoKIwAiALUUAA==.Tyredelsia:BAAANQAECgQIBgAAAA==.',
['Tö']='Töph:BAAANQADCgYICgABNQAECgoKJgAVAKwRAA==.',
['Tú']='Túsk:BAAANQAECgEIAgAAAA==.',
['Tý']='Týlius:BAAANQAECgMIBAABNQAECgoKIwAiALUUAA==.Týlïus:BAAANQAECgcIBgABNQAECgoKIwAiALUUAA==.',
Uk='Ukika:BAAANQAECgEIAgABNQAECgQIBgACAAAAAA==.',
Us='Useriòs:BAAANQAECgQIBQAAAA==.',
Ut='Uthilon:BAABNQAECn9LAAIbAAoKZyKBBAAeAwAbAAoKZyKBBAAeAwAAAA==.',
Va='Valdare:BAABNQAECn8zAAIeAAgK6A67PwA7AQAeAAgK6A67PwA7AQAAAA==.Validorn:BAAANQAECgEIAQAAAA==.Vantris:BAAANQAECgEIAQABNQAECgYIFwAhABgRAA==.',
Ve='Vedillian:BAAANQAECgIIAQAAAA==.Velduar:BAAANQADCgQIBAAAAA==.',
Vi='Victorr:BAAANQAECgEIAQAAAA==.Vikkter:BAAANQAECggICAAAAA==.Viktorius:BAAANQADCggICwAAAA==.Vixious:BAAANQAECgUIBQAAAA==.Vizigoth:BAABNQAECn8xAAQXAAoKOw8RFAD1AAAPAAgK7w0spAAOAQAXAAYKURARFAD1AAAWAAEKURFWcgA9AAAAAA==.',
Vo='Vordell:BAAANQAECgQICQABNQAFFAEIAQACAAAAAA==.Voyana:BAABNQAECn8aAAIIAAYKiwmWogD2AAAIAAYKiwmWogD2AAAAAA==.Voz:BAAANQADCgUIBQAAAA==.',
Vy='Vydragon:BAACNQAFFH8NAAQoAAYK7wyVEQDLAAAoAAMKOAmVEQDLAAApAAQKZw1yCwCWAAAfAAEK0gfcDwBBAAA1AAQKfy0ABCgACgp4EdkaABgCACgACgp4EdkaABgCAB8ACAozGzwKAMoBACkABAroE/8VANEAAAE1AAUUBQgJAAQA0hIA.Vymage:BAACNQAFFH8JAAIEAAUK0hKLKQDRAAAEAAUK0hKLKQDRAAA1AAQKf0QAAwQACgptIcIdAMoCAAQACgpPIcIdAMoCACcACAorHNYBACkCAAAA.Vysneak:BAAANQADCgcIBwABNQAFFAUICQAEANISAA==.',
['Vá']='Válidüs:BAACNQAFFH8ZAAIIAAcKfAxEEACiAQAIAAcKfAxEEACiAQA1AAQKf1UAAggACgo+I+QJAJoDAAgACgo+I+QJAJoDAAAA.',
['Vã']='Vãsh:BAABNQAECn8gAAQUAAgK+geQHwAbAQAUAAgK+geQHwAbAQAVAAUKbQPqWQB/AAAlAAUK7gTsHwBmAAAAAA==.',
Wa='Wabbitseason:BAAANQADCgIIAgABNQAECgoKIwAOAPwPAA==.Wabìsuke:BAAANQADCggIFQAAAA==.Waterlogged:BAAANQAECgEIAQAAAA==.Waterloo:BAAANQADCgcIEQAAAA==.Waterproof:BAAANQABCgMIAwAAAA==.',
Wi='Wizpigas:BAAANQADCgcIDQABNQAECgkJMAAVAL0SAA==.',
['Wì']='Wìccka:BAAANQADCgUIBQAAAA==.',
Xi='Xi:BAAANQAECgMIAwAAAA==.Xifan:BAACNQAFFH8GAAIUAAYKRB96AwDGAQAUAAYKRB96AwDGAQA1AAQKfy0AAhQACgp7JdcAACkEABQACgp7JdcAACkEAAAA.',
Yd='Yd:BAAANQAECgQIBAABNQAFFAEIBQAFAAAAAA==.',
Yg='Yggdrasill:BAAANQABCgUICAAAAA==.',
Yi='Yingpi:BAAANQABCgIIAgAAAA==.',
Yo='Yodaa:BAAANQADCggICwABNQAECggIMQANAJ8TAA==.',
Ys='Ys:BAAANQAECgQIBAABNQAFFAEIBQAFAAAAAA==.',
Yt='Yt:BAAANQAECgQICgABNQAFFAEIBQAFAAAAAA==.',
Yw='Ywontudie:BAAANQAECgYIBgAAAA==.',
Yz='Yz:BAACNQAFFH8FAAIFAAEKAAAnEQBlAAAFAAEKAAAnEQBlAAA1AAQKfy4AAwUACQrQIwsCAJoDAAUACQrQIwsCAJoDAAYAAgpTGzqHAJUAAAAA.',
Za='Zashawa:BAAANQADCgYIEQAAAA==.',
Ze='Zenithgrey:BAABNQAECn8XAAMTAAkKMQ6ghwCRAQATAAcKug6ghwCRAQAQAAUKJQ8KqgAdAQAAAA==.',
Zl='Zluco:BAACNQAFFH8OAAIgAAUKjCFzAQB8AQAgAAUKjCFzAQB8AQA1AAQKf0kAAyAACgosJq0AAHYDACAACgosJq0AAHYDABAABgp5HAd+AJIBAAAA.',
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
