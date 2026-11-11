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

local lookup = {'Hunter-BeastMastery','Unknown-Unknown','Mage-Arcane','Rogue-Subtlety','Druid-Balance','Rogue-Assassination','Priest-Holy','Priest-Discipline','Priest-Shadow','DeathKnight-Blood','DeathKnight-Unholy','Paladin-Retribution','Mage-Frost','Warlock-Demonology','Druid-Restoration','Shaman-Restoration','Warrior-Protection','Druid-Guardian','Shaman-Elemental','Monk-Mistweaver','Monk-Windwalker','Warlock-Destruction','Warlock-Affliction','Warrior-Arms','Druid-Feral','DeathKnight-Frost','Paladin-Protection','Warrior-Fury','DemonHunter-Vengeance','DemonHunter-Havoc','Evoker-Devastation','Shaman-Enhancement','Paladin-Holy','DemonHunter-Devourer','Hunter-Marksmanship','Monk-Brewmaster','Hunter-Survival','Mage-Fire','Evoker-Preservation','Evoker-Augmentation','Rogue-Outlaw',}
local provider = {region='US',realm="Eldre'Thalas",name='US',type='weekly',zone=53,date='2026-11-10',data={Ad='Adesira:BAAANQAECgQIBQAAAA==.Adrastus:BAAANQAECgQICAABNQAECgoKOAABAOEWAA==.Adurith:BAAANQAECgEIAQAAAA==.',
Ae='Aeslin:BAAANQADCgYJBgABNQAECgEIAwACAAAAAA==.',
Ah='Ahn:BAAANQAECggIEAAAAA==.Ahtila:BAAANQADCgUIBwAAAA==.Ahylin:BAAANQADCgcIDAAAAA==.',
Ai='Ainslie:BAAANQAECgYIEwAAAA==.',
Al='Alerana:BAAANQAECgYIDAAAAA==.Altria:BAAANQADCgUICQAAAA==.',
An='An:BAABNQAECn8YAAIDAAYKYRyh0wDfAQADAAYKYRyh0wDfAQABNQAFFAEIBQAEAAAAAA==.Anarose:BAAANQAECgUIEQABNQAECggIJwAFAPIEAA==.Antityk:BAABNQAECn8jAAMEAAkKMwzlWQCDAQAEAAkKSQvlWQCDAQAGAAQK7gowdADgAAABNQAECgoKOAABAOEWAA==.',
Ar='Aragorn:BAAANQADCgQIBQAAAA==.Arahant:BAAANQAECgIIAgAAAA==.Araxiel:BAECNQAFFH8HAAIHAAQKoB34HQDiAAAHAAQKoB34HQDiAAA1AAQKfy0ABAcACgp+I8EKAGwDAAcACgp+I8EKAGwDAAgABwq+FukLAH8BAAkAAQqAApCTABUAAAE1AAUUBAgHAAcAoB0A.Aretas:BAABNQAECn8oAAMKAAkKzhx8GQDiAgAKAAkKzhx8GQDiAgALAAEK4Q3c4gAxAAAAAA==.Armadian:BAAANQAECgQICAAAAA==.Arrianne:BAAANQADCgYIBgAAAA==.Arriella:BAAANQAECgUICgAAAA==.Arriånna:BAAANQADCgcIEwAAAA==.Artemist:BAABNQAECn8UAAIMAAYKqg2y9QAyAQAMAAYKqg2y9QAyAQAAAA==.',
As='Asifa:BAAANQAECgQICgAAAA==.',
At='Atherion:BAABNQAECn81AAINAAoK4xEiCwATAgANAAoK4xEiCwATAgAAAA==.Attackroot:BAAANQAECgUIBgABNQAECgcIHAAOAFkMAA==.',
Au='Aurakk:BAAANQADCgYIEQABNQAECggIKwAMADYTAA==.',
Av='Avelin:BAAANQADCgUIBQAAAA==.Aveticus:BAAANQAECgEIAQAAAA==.Avranarada:BAABNQAECn83AAMPAAoKDhYeIAAqAgAPAAoKDhYeIAAqAgAFAAkKCBZhJgC2AQAAAA==.Avril:BAAANQAECgEIAwAAAA==.',
Az='Azhádi:BAAANQAECgEIAQAAAA==.Azkara:BAACNQAFFH8NAAIQAAUKpQ3IFAD7AAAQAAUKpQ3IFAD7AAA1AAQKfzUAAhAACgreHQMaANMCABAACgreHQMaANMCAAAA.Azung:BAABNQAECn8+AAIMAAoK3iCwKwAZAwAMAAoK3iCwKwAZAwAAAA==.',
Ba='Baatos:BAEANQAECggIAgABNQAECgkJHAAOAFQMAA==.Babaisyaga:BAACNQAFFH8VAAIBAAUKXiK9DQALAQABAAUKXiK9DQALAQA1AAQKf1UAAgEACgpxJAwNAHYDAAEACgpxJAwNAHYDAAAA.Baka:BAAANQAECgYICQAAAA==.Balinse:BAABNQAECn8fAAIRAAkKTRcMGQChAQARAAkKTRcMGQChAQABNQAECgoKHwAJAMsNAA==.Balystix:BAAANQADCggICAAAAA==.Barb:BAAANQAECgcICgAAAA==.Barrelrollin:BAAANQAECgEIAQAAAA==.Basherdownn:BAAANQADCgQIBAAAAA==.',
Be='Beastfodays:BAACNQAFFH8JAAIBAAMKrhRiHQDIAAABAAMKrhRiHQDIAAA1AAQKfzUAAgEACgpxF8tDAKACAAEACgpxF8tDAKACAAAA.Bethlahammer:BAAANQAECgEIAQABNQAECgIIAwACAAAAAA==.',
Bh='Bhassie:BAAANQAECgQIBAABNQAFFAUIDwASAO8OAA==.',
Bi='Billcritin:BAAANQAECggIEAAAAA==.',
Bl='Blackleaf:BAAANQADCgcICgAAAA==.Blawyke:BAABNQAECn8ZAAMQAAoKoxE2NgAsAgAQAAoKoxE2NgAsAgATAAEKlgfOVwEhAAABNQAFFAIIBAACAAAAAA==.Bless:BAAANQADCggIDgABNQAECgYICgACAAAAAA==.Blizzcon:BAACNQAFFH8TAAIHAAUKexioDwCZAQAHAAUKexioDwCZAQA1AAQKf00AAgcACgr2I2sJAHcDAAcACgr2I2sJAHcDAAAA.Bloodsurge:BAAANQADCgQJAwAAAA==.Blushies:BAABNQAECn8xAAMTAAgKKh8iHgBwAgATAAgKKh8iHgBwAgAQAAMK8xC64wCiAAAAAA==.',
Bo='Boltzfodayz:BAAANQAECgEIAgAAAA==.Bonerslap:BAAANQAECgQIBQAAAA==.Boone:BAAANQADCgMIAwAAAA==.Borrgar:BAABNQAECn8rAAIMAAgKNhMvrgBdAQAMAAgKNhMvrgBdAQAAAA==.',
Br='Brackle:BAABNQAECn8eAAIBAAkKCxuQQgCjAgABAAkKCxuQQgCjAgAAAA==.Bracori:BAACNQAFFH8OAAIUAAUKSgwNBgAEAQAUAAUKSgwNBgAEAQA1AAQKf0cAAxQACgo+G0MHAPECABQACgo+G0MHAPECABUAAQoAAOJqAAAAAAAA.Brandywynne:BAABNQAECn8sAAIBAAoKsA+4ZQBJAgABAAoKsA+4ZQBJAgAAAA==.Bretcha:BAAANQADCgQIBAABNQAECgQIBwACAAAAAA==.Brick:BAABNQAECn8qAAIEAAoKcxeeDQCcAgAEAAoKcxeeDQCcAgAAAA==.Brightfame:BAABNQAECn87AAMWAAoKdRe+BACpAQAWAAgK7xa+BACpAQAXAAUKVBTpEQAsAQAAAA==.Bronny:BAABNQAECn8gAAIYAAkKSA3VuACOAQAYAAkKSA3VuACOAQAAAA==.Brônwyn:BAAANQADCgQIBAAAAA==.',
Bu='Buffshagwell:BAABNQAECn8pAAIMAAkKhxdqWQCLAgAMAAkKhxdqWQCLAgAAAA==.Bullrush:BAAANQADCgYICAAAAA==.Butterbllz:BAABNQAECn8pAAIMAAoKhxs/XgB+AgAMAAoKhxs/XgB+AgAAAA==.',
Ca='Caerhysa:BAAANQADCgQIBAAAAA==.Calypsio:BAAANQADCgQIBAABNQAECgMIAwACAAAAAA==.Camany:BAABNQAECn8iAAIBAAkKZhGMdwAgAgABAAkKZhGMdwAgAgAAAA==.Captinkrunch:BAAANQADCgEIAQAAAA==.Captinlock:BAAANQADCgEIAQABNQADCgEIAQACAAAAAA==.Captinmorí:BAAANQADCgEIAQAAAA==.Caretakerz:BAABNQAECn8tAAMSAAkKsB2yCwCuAgASAAkKsB2yCwCuAgAZAAEKjg30RwAtAAAAAA==.Cartus:BAAANQAECgUICQABNQAECgcIFQASAAUJAA==.Cayin:BAABNQAECn8cAAIKAAkKSiDsEwANAwAKAAkKSiDsEwANAwABNQABCgYICwACAAAAAA==.',
Ch='Chanta:BAAANQAECgEIAQAAAA==.Chanyeol:BAAANQAECggIEgAAAA==.Chemoshh:BAAANQADCggIBgABNQAECggIKwAMADYTAA==.',
Cl='Clamshell:BAABNQAECn9AAAMaAAoKnSLkCAAWAwAaAAoKnSLkCAAWAwAKAAUKwRi0YgBnAQAAAA==.Claudette:BAAANQAECgcIDQAAAA==.Clayier:BAAANQADCgcIGQAAAA==.',
Cn='Cntendr:BAAANQADCgUICAAAAA==.',
Co='Codenike:BAABNQAECn82AAIVAAoKyRcJEQA6AgAVAAoKyRcJEQA6AgAAAA==.Coil:BAAANQADCggICgABNQAECgYICgACAAAAAA==.Copenzen:BAAANQAECgcIDgAAAA==.Corelheals:BAAANQAECgUIEgAAAA==.Covertyqt:BAABNQAECn83AAIDAAoKQBwAOgBTAgADAAoKQBwAOgBTAgAAAA==.Coyote:BAAANQAECgIIAQAAAA==.',
Cp='Cptnhuman:BAABNQAECn88AAILAAoKPh2tEgBTAgALAAoKPh2tEgBTAgAAAA==.',
Cr='Cromie:BAAANQADCggIFQAAAA==.Crosed:BAAANQADCgQIBAAAAA==.',
Cs='Cshunter:BAAANQADCgYIBwAAAA==.',
Cu='Cubcakes:BAAANQAECgEIAgAAAA==.',
Cy='Cylcuria:BAAANQABCgIIAgAAAA==.',
['Cõ']='Cõrpses:BAEBNQAECn8wAAIKAAoKkB9PDwCgAgAKAAoKkB9PDwCgAgABNQAECgoKJgASAGQkAA==.',
Da='Daboof:BAAANQADCggIKgAAAA==.Daemandred:BAAANQADCgUIBQAAAA==.Daggere:BAAANQADCggIKAAAAA==.Danke:BAAANQAECgYIDQAAAA==.Dankz:BAABNQAECn8ZAAIMAAcKIwUNBQHMAAAMAAcKIwUNBQHMAAAAAA==.Darkenmicky:BAAANQADCgcIEwAAAA==.Darkmickyz:BAABNQAECn8YAAIbAAcK1RDnNQA4AQAbAAcK1RDnNQA4AQAAAA==.Darthbobula:BAACNQAFFH8JAAIMAAQKKQd6GgCuAAAMAAQKKQd6GgCuAAA1AAQKfxwAAgwACAqXEP3PACIBAAwACAqXEP3PACIBAAAA.Dayloc:BAABNQAECn8sAAIOAAoKXQ2ZUQDMAQAOAAoKXQ2ZUQDMAQAAAA==.',
De='Deataria:BAABNQAECn8yAAIPAAoKYhrOCgAKAwAPAAoKYhrOCgAKAwAAAA==.Deathrho:BAAANQADCgUICwAAAA==.Deawin:BAAANQADCgQIBAABNQAECgEIAQACAAAAAA==.Delilia:BAEANQAECggICwABNQAECgkJHAAOAFQMAA==.Delryth:BAAANQADCgYIBQAAAA==.Demonikk:BAAANQAECgYIDgABNQAECgoKOAABAOEWAA==.Demontyk:BAAANQAECgYIEAABNQAECgoKOAABAOEWAA==.Desception:BAAANQADCgcICgAAAA==.Devourmax:BAABNQAECn8YAAIcAAoKNARdHAC1AAAcAAoKNARdHAC1AAAAAA==.',
Di='Diablõ:BAEBNQAECn8XAAMdAAkKuQ7IDwA0AQAeAAkKfQphLQCQAQAdAAgKvA3IDwA0AQABNQAECgoKJgASAGQkAA==.Diadochi:BAAANQAECgQJBgAAAA==.Dieguerta:BAAANQADCgEJAQAAAA==.',
Dl='Dl:BAABNQAECn8zAAIJAAoK2Bm9GQCAAgAJAAoK2Bm9GQCAAgAAAA==.',
Dr='Drakkarr:BAAANQADCgYIBwAAAA==.Drazhoath:BAAANQAECgUIDwAAAA==.Drdrill:BAAANQADCgYIBgAAAA==.Drimbirt:BAAANQADCgcICgAAAA==.Drinkmormilk:BAAANQAECgQIBgAAAA==.Drogelf:BAAANQADCgcIGQAAAA==.Drogman:BAAANQADCgIIAgAAAA==.',
Du='Dumbledore:BAAANQAECgEIAQABNQAECgEIAwACAAAAAA==.',
['Dá']='Dáwnbringer:BAAANQADCgIIBAAAAA==.',
Eb='Ebullition:BAAANQAECggICgAAAA==.',
Ed='Edensfury:BAAANQAECgIIAwAAAA==.',
Ee='Eedani:BAAANQADCgUJCQAAAA==.',
Ei='Eigi:BAABNQAECn8iAAIBAAoKQxV4WgD9AQABAAoKQxV4WgD9AQAAAA==.',
El='Eldanon:BAABNQAECn9AAAIWAAoKhyMfAQCRAwAWAAoKhyMfAQCRAwAAAA==.Elementality:BAAANQADCgIIAgAAAA==.Eleyert:BAACNQAFFH8QAAITAAUKSiUHCABGAQATAAUKSiUHCABGAQA1AAQKfzkAAhMACgqOJrQAAJADABMACgqOJrQAAJADAAAA.Elistann:BAAANQAECgQIBAABNQAECggIKwAMADYTAA==.Elwe:BAABNQAECn8jAAIHAAkKkxXMcgDEAQAHAAkKkxXMcgDEAQAAAA==.',
Em='Embaku:BAAANQADCggICAABNQAECgoKSQAMALwVAA==.Emiri:BAAANQAECgQIBQAAAA==.Emrhakul:BAAANQABCggIFQAAAA==.',
En='Enkidu:BAABNQAECn8sAAIBAAgKbxNXhQCSAQABAAgKbxNXhQCSAQAAAA==.Enseth:BAABNQAECn83AAIfAAoKugqWCwCQAQAfAAoKugqWCwCQAQAAAA==.',
Er='Erakha:BAAANQAECgQIBwAAAA==.Erandria:BAAANQADCggIEQABNQAECgQICwACAAAAAA==.',
Eu='Eulogy:BAAANQADCgYICAABNQAFFAUIEwAHAHsYAA==.',
Ez='Ezki:BAAANQADCggIFwABNQAECggIKwAMADYTAA==.',
Fa='Fairious:BAABNQAECn8/AAIEAAoKzxitLAA5AgAEAAoKzxitLAA5AgAAAA==.',
Fe='Felcon:BAAANQADCgYICQAAAA==.Felenkeller:BAAANQAECgIIBgABNQAFFAYICgALAOAWAA==.Fenrirr:BAAANQADCggICAABNQAECggIKwAMADYTAA==.Fet:BAABNQAECn8rAAMGAAoKSyB7DAD3AQAEAAgKDR6PEQBoAgAGAAkK5R17DAD3AQAAAA==.',
Fh='Fhatbashtud:BAAANQAECgMIBwAAAA==.',
Fl='Flashfiré:BAAANQAECgQIBAABNQAECgoKNQAgAI8eAA==.Flashies:BAAANQAECgQIBgABNQAECggIMQATACofAA==.Flatline:BAABNQAECn8oAAIIAAkKbRuPAgCFAgAIAAkKbRuPAgCFAgAAAA==.Flinnt:BAAANQADCgUIBwABNQAECggIKwAMADYTAA==.',
Fn='Fngusamungus:BAAANQAECgEIAQAAAA==.',
Fo='Folgore:BAAANQAECgQIDAAAAA==.Four:BAAANQAECgcIEgAAAA==.',
Fr='Fredwarlock:BAAANQAECgUIBwAAAA==.Frysky:BAABNQAECn8fAAMZAAkKEg0YGAB4AQAZAAgKGw0YGAB4AQAFAAkKeQmmOAA7AQAAAA==.',
Fu='Furiousv:BAAANQADCgUIBQAAAA==.Futz:BAABNQAECn88AAIhAAoK1iIQHgD5AgAhAAoK1iIQHgD5AgAAAA==.',
['Fõ']='Fõrged:BAEANQAECggICAABNQAECgoKJgASAGQkAA==.',
Ga='Gahnzul:BAAANQADCgUICgAAAA==.Gajitbek:BAAANQADCgUICAAAAA==.Galah:BAABNQAECn8YAAIDAAcK4g498gCmAQADAAcK4g498gCmAQAAAA==.Gardurst:BAABNQAECn8tAAITAAoKVhtCJgA6AgATAAoKVhtCJgA6AgAAAA==.',
Gn='Gnomicide:BAAANQAECgQIDAAAAA==.',
Go='Gonesh:BAAANQADCggIEAAAAA==.Gooberpea:BAAANQABCgYIEAAAAA==.Gordoe:BAAANQADCgUICgAAAA==.',
Gr='Graveborne:BAAANQADCggIEQAAAA==.Gravess:BAAANQADCgUICwAAAA==.Gravewin:BAAANQADCgQICgABNQAECgEIAQACAAAAAA==.Gravyexpress:BAABNQAECn9YAAMeAAoKBhw/FwDhAgAeAAoK6Bs/FwDhAgAiAAcKxhTCPQBbAQAAAA==.Grendelheim:BAAANQADCggILAAAAA==.Grogar:BAAANQADCgcIFQAAAA==.Groxxigar:BAAANQADCgUIBQAAAA==.',
Gu='Gula:BAAANQAECgUICwABNQAECgoKJQAVAFgQAA==.',
Ha='Hadez:BAAANQADCgUIBQAAAA==.Hagrok:BAAANQAECgEIAwAAAA==.Hairybubble:BAAANQADCggICAAAAA==.Hakusei:BAAANQADCgMIAwAAAA==.Hantak:BAAANQADCgMIBgAAAA==.Harmsway:BAAANQADCgcIEQAAAA==.Hathaendron:BAAANQADCgYIBgAAAA==.',
He='Hephaestus:BAAANQAECgUICwAAAA==.',
Ho='Hocka:BAAANQADCgUIBgAAAA==.Holysmight:BAAANQAECgEIAQAAAA==.Holyumo:BAAANQADCgYIBgAAAA==.Holyyballs:BAAANQAECgcICwABNQAECgoKIwANAPwPAA==.Howlymandel:BAAANQAECggICQABNQAECgkJGwABAA4IAA==.Hoytx:BAAANQADCgUIBQAAAA==.',
Hy='Hydraciel:BAAANQAECgYIDwAAAA==.',
['Hì']='Hìroko:BAABNQAECn8hAAMWAAcKtAbFOwDSAAAOAAcKkwXNtQDTAAAWAAYKzwPFOwDSAAAAAA==.',
Ic='Icedemon:BAABNQAECn8bAAMKAAgKwheNJwCzAQAKAAgKwheNJwCzAQAaAAEKTwr3qgA2AAAAAA==.Iceliandra:BAAANQADCggIDgAAAA==.Iceveloric:BAAANQADCgYIAwAAAA==.Icupapi:BAAANQADCggILwAAAA==.Icynips:BAAANQABCgEIAQAAAA==.',
Ig='Ignitionfish:BAAANQAECgIIAwABNQAECggIMQATACofAA==.',
Im='Im:BAAANQADCgEJAQABNQAFFAEIBQAEAAAAAA==.Imabigman:BAAANQADCgcICAAAAA==.Imaleaf:BAABNQAECn8aAAIFAAgKMQbsXQBZAQAFAAgKMQbsXQBZAQAAAA==.Imperius:BAAANQAECgEIAwAAAA==.',
In='Insillico:BAAANQAECgEIAQABNQAECgoKOAABAOEWAA==.',
Ip='Iplaydead:BAABNQAECn84AAMBAAoK4RaePgBHAgABAAoK4RaePgBHAgAjAAEKAACnmgAmAAAAAA==.',
Ir='Iroh:BAABNQAECn8bAAIVAAkKcRkNIQAkAgAVAAkKcRkNIQAkAgAAAA==.',
Is='Ismokeprot:BAAANQADCgQIBAAAAA==.',
Ja='Jabelemachus:BAAANQAECgEIAQABNQAFFAYIBgAUAEQfAA==.Jacii:BAAANQAECggIDAABNQAECgoKQAAaAJ0iAA==.Jawnson:BAABNQAECn8VAAIEAAgKeg4KHAD1AQAEAAgKeg4KHAD1AQAAAA==.',
Je='Jelluz:BAAANQADCgYIBgAAAA==.Jenefer:BAACNQAFFH8OAAIKAAUKhx3vEQDRAAAKAAUKhx3vEQDRAAA1AAQKf0MAAwoACgohIVsKAOICAAoACgohIVsKAOICAAsAAgrsFBS4AH0AAAAA.Jeslartoma:BAAANQADCgEIAQABNQAECgMIBAACAAAAAA==.',
Ji='Jimjimmy:BAAANQADCgcIBwABNQAECgIIAwACAAAAAA==.',
Jo='Jondooz:BAAANQAECgcICQAAAA==.Jonoisanerd:BAAANQAECggICAAAAA==.Joulecrafter:BAAANQAECgUIBQABNQAECgoKSQAMALwVAA==.',
Jp='Jpegz:BAAANQADCgcIBgABNQAECgoKRwAMAIIiAA==.',
Ka='Kailana:BAAANQAECgEIBAABNQAECgoKNQAgAI8eAA==.Kailback:BAAANQAECgYIEQABNQAECgoKNQAgAI8eAA==.Kait:BAABNQAECn8+AAMQAAoKHhpuGgDPAgAQAAoKHhpuGgDPAgATAAUKowzijwDUAAAAAA==.Kalcifur:BAACNQAFFH8PAAMhAAUKGBS1DwAtAQAhAAUKGBS1DwAtAQAbAAEKGgz7EgA2AAA1AAQKf0cAAyEACgqKItoEAMkDACEACgqKItoEAMkDABsABgqNGR4fAGABAAAA.Karin:BAAANQAECgIIBAABNQAECgcIFQASAAUJAA==.Karnelian:BAAANQAECgYIDAABNQAFFAYIBgAUAEQfAA==.Karras:BAAANQADCgUIBQAAAA==.Kashisht:BAAANQAECgIIAwAAAA==.Kasstigate:BAABNQAECn8lAAIYAAoKERg1OABRAgAYAAoKERg1OABRAgABNQAFFAUIDgAKAIcdAA==.Kastiel:BAABNQAECn8fAAIJAAoKyw3uLQC2AQAJAAoKyw3uLQC2AQAAAA==.Katstrider:BAABNQAECn89AAIBAAoKcReqWwD6AQABAAoKcReqWwD6AQAAAA==.Kattarea:BAAANQADCgUJCAABNQAECgoKPQABAHEXAA==.Kavica:BAAANQAECgcIEAABNQAECgoKOAAPAEshAA==.',
Ke='Keldean:BAABNQAECn8cAAIRAAkKhhyACgCZAgARAAkKhhyACgCZAgAAAA==.Keryka:BAACNQAFFH8PAAMaAAUKliJzCwD5AAAaAAUKliJzCwD5AAALAAEKZRJXIQBHAAA1AAQKf0MAAxoACgrnILUKAEQDABoACgq3HrUKAEQDAAsACArMGy1FAAQCAAAA.',
Kh='Khere:BAAANQAECgQIBQAAAA==.',
Ki='Kirigiri:BAAANQAECggIDwABNQAFFAUIDwAhABgUAA==.Kirøs:BAAANQAECgMIBgAAAA==.Kiterisa:BAABNQAECn9BAAIQAAoKVAyNSQDVAQAQAAoKVAyNSQDVAQAAAA==.',
Kk='Kkazz:BAAANQADCggICwABNQAECggIKwAMADYTAA==.',
Ko='Kohn:BAABNQAECn8cAAIhAAoKkiSbAQAiBAAhAAoKkiSbAQAiBAAAAA==.Kona:BAEBNQAECn8mAAQSAAoKZCRyAgBQAwASAAoKZCRyAgBQAwAZAAcK9BobDwC2AQAPAAIKkQEyfAAfAAAAAA==.Korbusty:BAAANQADCggIDgAAAA==.',
Ku='Kuattieb:BAAANQABCgIIAgAAAA==.',
La='Ladýfinger:BAABNQAECn84AAQhAAoKAhJ8YQD0AQAhAAkKWBN8YQD0AQAbAAgKEgv/IwA5AQAMAAQKJghDWwGOAAABNQAFFAUIDwASAO8OAA==.Laisidhiel:BAAANQAECgUICQAAAA==.Lateo:BAABNQAECn8oAAIEAAoKKQsWWACJAQAEAAoKKQsWWACJAQAAAA==.Lawz:BAABNQAECn8gAAMXAAkKzgXFEABAAQAXAAkKzgXFEABAAQAWAAIKOAAGegA0AAAAAA==.',
Le='Lelianna:BAAANQADCggIMwAAAA==.Lemonruss:BAAANQADCggIEQAAAA==.Levibigguns:BAAANQADCggIEAABNQAECggILwAVAFUUAA==.Lexia:BAAANQAECgYICwAAAA==.',
Li='Libidine:BAAANQADCgQIBAABNQAECgoKJQAVAFgQAA==.Liemannin:BAAANQAECgEIAQAAAA==.Lilaa:BAAANQADCgcIBwAAAA==.Lilturtz:BAAANQAECgUIBgABNQAECggIMQATACofAA==.Linnea:BAAANQADCgcIDQAAAA==.',
Lo='Locksative:BAAANQADCggIJgAAAA==.Longhorn:BAABNQAECn80AAIMAAkK7Q5XpABvAQAMAAkK7Q5XpABvAQAAAA==.Lorekesh:BAAANQADCgEJAQABNQAECgcIDQACAAAAAA==.Lorriena:BAAANQAECgEIAQABNQAECgIIAwACAAAAAA==.Lorrè:BAAANQADCgQIBAABNQAECgIIAwACAAAAAA==.Lortpegsalot:BAABNQAECn9HAAIMAAoKgiJlIADWAgAMAAoKgiJlIADWAgAAAA==.Lowy:BAAANQAECgUIAwAAAA==.',
Lu='Lucena:BAABNQAECn8tAAIHAAkKySIzDABxAwAHAAkKySIzDABxAwAAAA==.Lurg:BAAANQADCggICgABNQADCggIJgACAAAAAA==.Luxuria:BAAANQAECggIEwABNQAECgoKJQAVAFgQAA==.',
Ly='Lyralana:BAAANQAECgQICwAAAA==.',
Ma='Maberu:BAACNQAFFH8HAAIUAAQK7gO4BgDdAAAUAAQK7gO4BgDdAAA1AAQKfyYAAhQACgrWDWscAL0BABQACgrWDWscAL0BAAE1AAUUBQgPACEAGBQA.Madamholy:BAABNQAECn8YAAIHAAcKXR+hVwAbAgAHAAcKXR+hVwAbAgAAAA==.Madamkluck:BAAANQADCgUIBQAAAA==.Maglubiyet:BAABNQAECn8aAAIgAAYKJww8IwDkAAAgAAYKJww8IwDkAAAAAA==.Magnitood:BAABNQAECn8VAAMPAAcKBxTUMgCEAQAPAAcKBxTUMgCEAQAFAAEKAAB+rgA5AAAAAA==.Malbjornion:BAABNQAECn8fAAMSAAgKOAliQgCiAAASAAcKCQRiQgCiAAAZAAYKNgtVLwB/AAAAAA==.Malphox:BAAANQADCgQICAAAAA==.Manbearcat:BAABNQAECn8VAAISAAcKBQm/NgDwAAASAAcKBQm/NgDwAAAAAA==.Manhole:BAAANQAECgQIDQAAAA==.Markyb:BAAANQADCggIEQAAAA==.Masamura:BAACNQAFFH8SAAMDAAYK5hS0IADsAAADAAUKExe0IADsAAANAAIKfwchCgBxAAA1AAQKfz0AAwMACgqdHHpnAK8CAAMACgo/G3pnAK8CAA0AAgo0G+YrAJwAAAAA.Maureanna:BAAANQADCgUIDgABNQAECgQICwACAAAAAA==.',
Me='Mechahuntard:BAAANQADCgEIAQAAAA==.Medanii:BAEBNQAECn8fAAQIAAkKghFeDQBeAQAIAAYKVRJeDQBeAQAHAAUKUREcrAASAQAJAAQKTQenVwCsAAAAAA==.Melorm:BAAANQAECgQIDgAAAA==.Meno:BAAANQADCggICAAAAA==.',
Mi='Millizh:BAACNQAFFH8aAAMBAAkKhhytBwDUAQABAAYK6hytBwDUAQAjAAUKqhucDwBDAQA1AAQKfygAAyMACgoJJhsGAG8DACMACQpXJhsGAG8DAAEABwq3IfWRAOUBAAAA.Mirasharu:BAAANQADCggIKwAAAA==.Mireille:BAAANQADCgYIDQAAAA==.Mitsuri:BAABNQAECn8qAAIMAAgKxA9DrABgAQAMAAgKxA9DrABgAQAAAA==.Mitzuky:BAAANQADCgMIAwAAAA==.',
Mo='Mommamoon:BAAANQADCgQIBAABNQAECgoKIQAMAM0ZAA==.Moonlïght:BAABNQAECn8hAAIMAAoKzRmmWAAUAgAMAAoKzRmmWAAUAgAAAA==.Morganlefay:BAABNQAECn8nAAIOAAkKdwITxgCyAAAOAAkKdwITxgCyAAAAAA==.Morlyn:BAABNQAECn8oAAINAAkKFhdFDQDdAQANAAkKFhdFDQDdAQAAAA==.Morregan:BAAANQAECgcICAAAAA==.Motion:BAAANQADCgcICgABNQAECgYICgACAAAAAA==.Mousereaper:BAABNQAECn8kAAIiAAoKtg/hLwDDAQAiAAoKtg/hLwDDAQAAAA==.',
My='Mydnight:BAAANQABCgIIAgAAAA==.Mystìc:BAABNQAECn81AAQgAAoKjx60DQAlAgAgAAkK6h20DQAlAgATAAYKOxzObADaAQAQAAEKaQr2IwEpAAAAAA==.Mystíc:BAAANQAECgYICAABNQAECgoKNQAgAI8eAA==.',
['Má']='Májorrobot:BAABNQAECn8wAAIYAAoKzyFrLgAEAwAYAAoKzyFrLgAEAwAAAA==.',
['Mé']='Ménopáwz:BAABNQAECn8YAAISAAkKoBTDEwDoAQASAAkKoBTDEwDoAQABNQAFFAYICgALAOAWAA==.',
Na='Namor:BAAANQAECgIIBAAAAA==.Nattisca:BAAANQAECgMIBAAAAA==.',
Ne='Nervanna:BAAANQAECgMIAwABNQAFFAEIAQACAAAAAA==.Nessà:BAABNQAECn8lAAMVAAoKWBD8FgDqAQAVAAoKWBD8FgDqAQAkAAEKKw+YJAA2AAAAAA==.Neveen:BAAANQAECgMIAwAAAA==.Neveenn:BAABNQAECn9CAAMPAAoKJR0PDwDkAgAPAAoKJR0PDwDkAgASAAMKIQScZQA7AAAAAA==.',
Ni='Niccala:BAAANQAECgEIAQAAAQ==.Nirith:BAAANQADCgYIEwAAAA==.Nivmizet:BAAANQAECgEIAQAAAA==.',
No='Nohatcat:BAAANQAECgQIBgABNQAECggIMQATACofAA==.',
['Nâ']='Nâmii:BAAANQAECgMIBAAAAA==.',
['Nè']='Nèzukõ:BAABNQAECn8kAAIBAAkKQheHiwDzAQABAAkKQheHiwDzAQAAAA==.',
Ob='Obata:BAAANQAECgQIBQAAAA==.',
Oc='Octavius:BAAANQADCggJDQABNQAECgIIAwACAAAAAA==.',
Od='Odi:BAAANQADCgQIBAAAAA==.',
Oj='Ojore:BAEBNQAECn8jAAIaAAgKagxhUgBnAQAaAAgKagxhUgBnAQAAAA==.Ojoverde:BAACNQAFFH8OAAIOAAUKrge1GgDCAAAOAAUKrge1GgDCAAA1AAQKf0cAAg4ACgpBFMxEAPQBAA4ACgpBFMxEAPQBAAAA.',
On='Onizuka:BAAANQADCgEIAQABNQAECgEIAQACAAAAAA==.Onside:BAAANQAECgcICwABNQAFFAUICgAVAAcVAA==.',
Op='Ophillã:BAABNQAECn8hAAMIAAkKsBbNBADKAQAIAAgKbBfNBADKAQAJAAYKnBOSQAArAQABNQAECgoKJQAVAFgQAA==.',
Or='Ordenn:BAAANQADCgQICAABNQAECgoKKwAGAEsgAA==.Orian:BAAANQADCgQIBwAAAA==.Oromë:BAAANQAECgEIAQAAAA==.',
Ov='Overflare:BAAANQAECgEIAQAAAA==.',
Oz='Ozz:BAABNQAECn8ZAAIVAAgKFw/aLgChAQAVAAgKFw/aLgChAQAAAA==.Ozzerker:BAAANQADCgEIAQAAAA==.Ozzullr:BAABNQAECn8XAAIBAAkKAht3MgDVAgABAAkKAht3MgDVAgAAAA==.',
Pa='Painbreak:BAAANQADCgEIAQABNQAECgkJLQASALAdAA==.Pajamas:BAAANQAECgEIAQABNQAECgcIHAAOAFkMAA==.Pallanquin:BAAANQAECgEIAQAAAA==.Papichili:BAABNQAECn8VAAITAAUK8wr6lgDFAAATAAUK8wr6lgDFAAAAAA==.Pashnir:BAAANQAECgEIAQAAAA==.',
Pe='Peachey:BAABNQAECn8kAAIQAAoKZhU3QwDwAQAQAAoKZhU3QwDwAQAAAA==.Peaker:BAAANQAECgQIBAAAAA==.Peakra:BAABNQAECn8nAAIHAAoKaxi2KwCGAgAHAAoKaxi2KwCGAgAAAA==.',
Ph='Phoênix:BAAANQADCgMIAwAAAA==.',
Pi='Pigas:BAABNQAECn8vAAIVAAgKVRRiKADdAQAVAAgKVRRiKADdAQAAAA==.',
Pr='Prestoresto:BAAANQADCgYIDwAAAA==.',
Ps='Psychosix:BAABNQAECn8dAAIDAAoKcR9mSwDrAgADAAoKcR9mSwDrAgAAAA==.',
Qu='Quinberos:BAAANQAECgYICwAAAA==.',
Ra='Racey:BAAANQADCggICAAAAA==.Raiistlin:BAAANQADCgYIBwABNQAECggIKwAMADYTAA==.Ramdel:BAAANQAECgUICwABNQAECgoKQQAlAN0aAA==.Ramstrider:BAABNQAECn9BAAMlAAoK3RoJAwB0AgAlAAoK3RoJAwB0AgABAAIKaQcTOAF2AAAAAA==.Ranah:BAAANQAECgYIBgABNQAECgcICAACAAAAAA==.Ranch:BAAANQAECgEIAQAAAA==.Rapture:BAABNQAECn84AAIiAAoKjQ4fHQCoAQAiAAoKjQ4fHQCoAQAAAA==.Ravec:BAAANQAECgEIAQAAAA==.Rayziel:BAAANQADCggICAABNQAECgMIBQACAAAAAA==.',
Re='Rengell:BAABNQAECn8bAAIBAAkKDgjJyAAGAQABAAkKDgjJyAAGAQAAAA==.Reptiliano:BAAANQAECggIEgABNQAFFAUIBwAGAJwOAA==.',
Rh='Rheagall:BAABNQAECn88AAIgAAoKTiMPAwAbAwAgAAoKTiMPAwAbAwAAAA==.Rhodetta:BAABNQAECn8bAAIHAAoKAxS5OgB+AgAHAAoKAxS5OgB+AgABNQAFFAEIAQACAAAAAA==.',
Ri='Rizepriest:BAAANQADCgIIAgABNQAECgcIFAAYAEghAA==.Rizerage:BAABNQAECn8UAAIYAAcKSCENbABOAgAYAAcKSCENbABOAgAAAA==.',
Ro='Roaraxe:BAAANQADCgYIBgABNQAECgIIAwACAAAAAA==.Rowena:BAABNQAECn9HAAIFAAoK8xYCIgDYAQAFAAoK8xYCIgDYAQAAAA==.Rowynna:BAAANQAECgMIAwABNQAECgYICwACAAAAAA==.Roxy:BAAANQAECgEIAQAAAA==.Roxymonk:BAAANQADCgYIBgAAAA==.Royalviaman:BAAANQADCgcICgAAAA==.',
Ry='Ryz:BAAANQADCggICAAAAA==.Ryztkmtchrch:BAACNQAFFH8FAAIHAAIKdhyCJQCgAAAHAAIKdhyCJQCgAAA1AAQKfzgABAcACgoKHWcyAJ4CAAcACgoKHWcyAJ4CAAgABwrDDe8MAGgBAAkABQqMDzNHAAIBAAAA.',
['Rå']='Råti:BAAANQAECgQIAwAAAA==.',
['Rø']='Rønis:BAAANQADCggICAAAAA==.',
Sa='Sacdk:BAAANQAECgQICQAAAA==.Safaria:BAAANQAECgQIBwABNQAECgYIGgAHAIsJAA==.Saloenus:BAAANQAECgYIDQAAAA==.Sarlyssa:BAAANQAECgEIAQAAAA==.Saucehoss:BAABNQAECn8mAAQXAAkKQx3sAwCrAgAXAAkKQx3sAwCrAgAWAAQKLQ8MPQDNAAAOAAMKkhTNBQHAAAAAAA==.Saucymac:BAACNQAFFH8IAAMJAAQKbAicCwDHAAAJAAMKbAicCwDHAAAHAAMKywEpJQCjAAA1AAQKfyQAAwkACgrjHaQOAFwCAAkACQp0HaQOAFwCAAcACQqWB/q0APgAAAAA.',
Sc='Scofflaw:BAAANQADCgEIAQABNQAECgQIBgACAAAAAA==.Scootr:BAAANQAECggIDQAAAA==.Scubasteve:BAAANQADCgUICgAAAA==.',
Se='Sefi:BAABNQAECn8yAAMMAAkKohOykQCUAQAMAAkK2xKykQCUAQAbAAQKlQ3+TgCsAAAAAA==.Semirrhage:BAAANQADCgMIAwAAAA==.Serandipity:BAAANQAECgQIBAABNQAFFAUIDgAKAIcdAA==.',
Sh='Shadowflame:BAABNQAECn8cAAIOAAcKWQy3oQD/AAAOAAcKWQy3oQD/AAAAAA==.Shallator:BAAANQAECgQIBAAAAA==.Shamanigans:BAAANQAECgUICwABNQAECgcIFQAPAAcUAA==.Shammygoat:BAABNQAECn8mAAITAAgKERzxWQBhAQATAAgKERzxWQBhAQAAAA==.Shaqattack:BAACNQAFFH8KAAIVAAUKBxUKCQDXAAAVAAUKBxUKCQDXAAA1AAQKfzkAAhUACgoIIDoKALMCABUACgoIIDoKALMCAAAA.Shaqattaq:BAABNQAECn8lAAMEAAoKIRvwHwB/AgAEAAkKdBnwHwB/AgAGAAkK8heZIwBrAgABNQAFFAUICgAVAAcVAA==.Sharktide:BAABNQAECn8kAAIQAAoK0xbZXwDvAQAQAAoK0xbZXwDvAQAAAA==.Shawnella:BAABNQAECn83AAMVAAoKPh8/DwBUAgAVAAkKnB4/DwBUAgAUAAIKTQf1RABYAAAAAA==.Shenlune:BAABNQAECn8VAAMUAAcKbQs6JgBHAQAUAAcKbQs6JgBHAQAkAAUKChivGwArAQAAAA==.Sheutka:BAAANQAECgQIDAAAAA==.Shiggles:BAAANQAECgIIAgAAAA==.Shinaie:BAABNQAECn8ZAAIJAAgKxQp8OABhAQAJAAgKxQp8OABhAQAAAA==.Shocknrollz:BAAANQAECgQIDQAAAA==.Shogún:BAABNQAECn8qAAIKAAkKlx1qEwBqAgAKAAkKlx1qEwBqAgAAAA==.Shran:BAAANQAECgEIAwAAAA==.Shtylez:BAAANQAECggIEwABNQAECgoKOAABAOEWAA==.',
Si='Silntwolf:BAAANQABCgQIBAAAAA==.Silpion:BAABNQAECn8UAAImAAcKTgeWBQAiAQAmAAcKTgeWBQAiAQAAAA==.Silth:BAAANQADCggIKQAAAA==.Sinariel:BAABNQAECn87AAIUAAoK9BwZCADYAgAUAAoK9BwZCADYAgAAAA==.Sirdank:BAAANQAECgIIBAAAAA==.',
Sk='Skarlate:BAAANQADCgYIBgAAAA==.Skâld:BAEANQADCgYICwAAAA==.',
Sl='Sliko:BAABNQAECn9TAAIMAAoKZRYtWgAQAgAMAAoKZRYtWgAQAgAAAA==.',
Sm='Smmoke:BAABNQAECn9BAAIBAAoK9RfHQgA7AgABAAoK9RfHQgA7AgAAAA==.',
Sn='Sneekyone:BAAANQABCgUIBwAAAA==.Sneekypally:BAABNQAECn8nAAIMAAYKDQTvIwHjAAAMAAYKDQTvIwHjAAAAAA==.Snowballs:BAABNQAECn8jAAMNAAoK/A87DAC6AQANAAkKIxE7DAC6AQADAAgK5wlECgF8AQAAAA==.',
So='Softhorn:BAAANQABCgUIBQAAAA==.Sorenreign:BAAANQAECgEIAQAAAA==.Sothh:BAAANQADCggIEAABNQAECggIKwAMADYTAA==.Soull:BAABNQAECn9NAAIPAAoKTSXYAQD9AwAPAAoKTSXYAQD9AwAAAA==.Soulsmash:BAAANQAECggICwAAAA==.',
Sp='Spacebabe:BAAANQAECgQIBQABNQAECgcIGgAfAOQKAA==.Spacestepdad:BAABNQAECn8aAAQfAAcK5AqnHwBbAQAfAAcK5AqnHwBbAQAnAAYKlwpOMQAQAQAoAAIKJgSnHQAnAAAAAA==.Sparkie:BAAANQAECgMIAwAAAA==.Spriggan:BAAANQAECgUIBgAAAA==.',
Sq='Squashfoot:BAAANQAECgEIAgABNQAECgIIAwACAAAAAA==.',
St='Starface:BAACNQAFFH8PAAISAAUK7w43BQCjAAASAAUK7w43BQCjAAA1AAQKfz8AAxIACgqNHfwKAL8CABIACgqNHfwKAL8CABkABwpGFhYRAJUBAAAA.Stargoose:BAAANQAECgUICQABNQAFFAUIDwASAO8OAA==.Starphoenix:BAAANQADCggIFwAAAA==.Steelytree:BAAANQADCgcICgAAAA==.Stellaria:BAABNQAECn8WAAIhAAYKGBGihwANAQAhAAYKGBGihwANAQAAAA==.Steris:BAAANQADCggIIgABNQADCggIJgACAAAAAA==.Steverogers:BAABNQAECn8WAAMMAAcKAR1weADJAQAMAAcKAR1weADJAQAbAAIK4APKgAAcAAABNQAFFAYICgALAOAWAA==.Stocktonrush:BAACNQAFFH8KAAQLAAYK4BZhDQA2AQALAAUKwBRhDQA2AQAaAAMKgRc9FACPAAAKAAEKAACCKgBMAAA1AAQKfzkABAsACgrxJEwQADQDAAsACQolJUwQADQDABoABgrgH5ElABQCAAoAAwouJPhGABQBAAAA.Stonedhenge:BAAANQAECgEIAQAAAA==.Sturmx:BAABNQAECn9BAAIeAAoK6xaoHAAUAgAeAAoK6xaoHAAUAgAAAA==.',
Su='Subedei:BAABNQAECn85AAQaAAoKUiAlDgDZAgAaAAoK/B8lDgDZAgALAAgKtRqcRQACAgAKAAEK0Q7hyQA2AAAAAA==.Submison:BAAANQADCgYIBgABNQAECgoKIwANAPwPAA==.Summerseve:BAAANQAECgMIBAAAAA==.Sunderhorn:BAAANQAECgQICgAAAA==.Suriaa:BAABNQAECn9DAAMGAAoK6hh+CwAJAgAGAAoK6hh+CwAJAgApAAQKugu8EwDBAAAAAA==.',
Sv='Svictis:BAABNQAECn8VAAILAAgK2AiLPAARAQALAAgK2AiLPAARAQAAAA==.Svictiss:BAAANQADCggIEQAAAA==.',
Sw='Swami:BAAANQAECgQIBgAAAA==.',
Ta='Talila:BAABNQAECn8zAAISAAgKZh1bEgD9AQASAAgKZh1bEgD9AQAAAA==.Taniss:BAAANQADCggIFgABNQAECggIKwAMADYTAA==.Taurdeth:BAABNQAECn8YAAQKAAgKGAx5YABwAQAKAAgK5gt5YABwAQALAAIKFQR9cABUAAAaAAIKXgvesgAqAAABNQAFFAEIAQACAAAAAA==.',
Te='Terrya:BAAANQAECgUIBQAAAA==.Teryail:BAAANQADCgYIBgAAAA==.',
Th='Thaqdaddy:BAAANQADCgYIBgABNQAECgoKKQAKACwVAA==.Thaqknight:BAABNQAECn8pAAIKAAoKLBXcMwA+AgAKAAoKLBXcMwA+AgAAAA==.Therylnn:BAAANQAECgIIAwAAAA==.Thesthamenth:BAAANQADCgYIBgAAAA==.Thiccthaq:BAAANQAECgYICAABNQAECgoKKQAKACwVAA==.Thily:BAAANQADCgIIAgAAAA==.Thorwallen:BAAANQADCggIFAABNQAECggIKwAMADYTAA==.Thror:BAAANQAECgEIAQAAAA==.',
Ti='Tiac:BAAANQAECgEIAQAAAA==.Tiergyll:BAAANQABCgIIBgAAAA==.Tirithor:BAABNQAECn9JAAIMAAoKvBVNYQD/AQAMAAoKvBVNYQD/AQAAAA==.',
To='Tockell:BAAANQADCgQIBwAAAA==.Togala:BAAANQADCgYIDgABNQAECgQIBwACAAAAAA==.Toothless:BAAANQAECgEIAgAAAA==.Torbin:BAAANQAECgYIDwAAAA==.Touchmywave:BAAANQAECgEIAQABNQAFFAMICQABAK4UAA==.',
Tr='Trichinella:BAAANQAECggIDAABNQAECgoKKQAKACwVAA==.Tryhunt:BAAANQAECgUIBAAAAA==.Tryjinks:BAABNQAECn8mAAMTAAoKHRAjaADoAQATAAkKQQ4jaADoAQAQAAcKCxHIjQBmAQAAAA==.Trypriest:BAAANQAECgEIAQAAAA==.',
Ts='Tsunameh:BAABNQAECn8cAAMHAAkKEBL1RgAGAgAHAAkKEBL1RgAGAgAJAAEKdAJgZAAnAAABNQAECgoKOAABAOEWAA==.',
Tu='Tusky:BAAANQADCgYIBgAAAA==.',
Tw='Twohandtug:BAAANQADCggIGwAAAA==.',
Ty='Tykahndrius:BAABNQAECn8wAAMbAAoKWhgeHQACAgAbAAoKWhgeHQACAgAMAAcKKBGU0wAcAQABNQAECgoKOAABAOEWAA==.Tylîus:BAABNQAECn8jAAQiAAoKtRS8JQAYAgAiAAgKZBa8JQAYAgAdAAUKBBjiGQCyAAAeAAIK2QlIbQBhAAAAAA==.Tylïus:BAAANQAECgIIAgABNQAECgoKIwAiALUUAA==.Tyredelsia:BAAANQAECgQIBgAAAA==.',
['Tö']='Töph:BAAANQADCgYICgABNQAECgoKJQAVAFgQAA==.',
['Tú']='Túsk:BAAANQAECgEIAgAAAA==.',
['Tý']='Týlius:BAAANQAECgMIBQABNQAECgoKIwAiALUUAA==.Týlïus:BAAANQAECgcIBgABNQAECgoKIwAiALUUAA==.',
Uk='Ukika:BAAANQAECgEICAABNQAECgQIBwACAAAAAA==.',
Us='Useriòs:BAAANQAECgEIAQAAAA==.',
Ut='Uthilon:BAABNQAECn9BAAIbAAoKsyEyBQAEAwAbAAoKsyEyBQAEAwAAAA==.',
Va='Valdare:BAABNQAECn8tAAIeAAgKqgpuQwANAQAeAAgKqgpuQwANAQAAAA==.Validorn:BAAANQAECgEIAQAAAA==.',
Ve='Vedillian:BAAANQAECgIIAgAAAA==.Velduar:BAAANQADCgQIBAAAAA==.',
Vi='Victorr:BAAANQAECgEIAwAAAA==.Vikkter:BAAANQAECggICAAAAA==.Viktorius:BAAANQADCggICwAAAA==.Vixious:BAAANQAECgQIBAAAAA==.Vizigoth:BAABNQAECn8vAAQXAAkKKhAjEgD4AAAOAAcK+w54vgBPAQAXAAYKURAjEgD4AAAWAAEKURFWcgA9AAAAAA==.',
Vo='Vordell:BAAANQAECgQICgABNQAFFAEIAQACAAAAAA==.Voyana:BAABNQAECn8aAAIHAAYKiwm6lwD8AAAHAAYKiwm6lwD8AAAAAA==.Voz:BAAANQADCgUIBQAAAA==.',
Vy='Vydragon:BAACNQAFFH8NAAQnAAYK7wyVEQDLAAAnAAMKOAmVEQDLAAAoAAQKZw3/CQCXAAAfAAEK0gfcDwBBAAA1AAQKfywABCcACgp4EdkaABgCACcACgp4EdkaABgCAB8ACAozG48JAMoBACgABAroE/8VANEAAAE1AAUUBAgIAAMArBIA.Vymage:BAACNQAFFH8IAAIDAAQKrBL4OwDTAAADAAQKrBL4OwDTAAA1AAQKf0QAAwMACgptIYUaANECAAMACgpPIYUaANECACYACAorHKEBAC0CAAAA.Vyrubur:BAAANQAECgEIAQABNQAFFAQICAADAKwSAA==.Vysneak:BAAANQADCgcIBwABNQAFFAQICAADAKwSAA==.',
['Vá']='Válidüs:BAACNQAFFH8ZAAIHAAcKfAy1DQCtAQAHAAcKfAy1DQCtAQA1AAQKf1EAAgcACgoUIx8KAIoDAAcACgoUIx8KAIoDAAAA.',
['Vã']='Vãsh:BAABNQAECn8fAAQUAAcKHAiOIAD7AAAUAAcKHAiOIAD7AAAVAAUKbQPqWQB/AAAkAAUK7gQRHgBmAAAAAA==.',
Wa='Wabbitseason:BAAANQADCgIIAgABNQAECgoKIwANAPwPAA==.Wabìsuke:BAAANQADCggIFQAAAA==.Waterlogged:BAAANQADCgUIFQAAAA==.Waterloo:BAAANQADCgcIEQAAAA==.Waterproof:BAAANQABCgMIAwAAAA==.',
Wi='Wizpigas:BAAANQADCgcIDQABNQAECggILwAVAFUUAA==.',
['Wì']='Wìccka:BAAANQADCgUIBQAAAA==.',
Xi='Xi:BAAANQAECgMIBAAAAA==.Xifan:BAACNQAFFH8GAAIUAAYKRB/dAgDSAQAUAAYKRB/dAgDSAQA1AAQKfy0AAhQACgp7JbAAAC8EABQACgp7JbAAAC8EAAAA.',
Yd='Yd:BAAANQAECgQIBgABNQAFFAEIBQAEAAAAAA==.',
Yg='Yggdrasill:BAAANQABCgUICAAAAA==.',
Yi='Yingpi:BAAANQABCgIIAgAAAA==.',
Yo='Yodaa:BAAANQADCggICwABNQAECggIKwAMADYTAA==.',
Ys='Ys:BAAANQAECgQIBAABNQAFFAEIBQAEAAAAAA==.',
Yt='Yt:BAAANQAECgQICwABNQAFFAEIBQAEAAAAAA==.',
Yw='Ywontudie:BAAANQAECgYICAAAAA==.',
Yz='Yz:BAACNQAFFH8FAAIEAAEKAAAnEQBlAAAEAAEKAAAnEQBlAAA1AAQKfy4AAwQACQrQIwsCAJoDAAQACQrQIwsCAJoDAAYAAgpTGzqHAJUAAAAA.',
Za='Zashawa:BAAANQADCgYIEQAAAA==.',
Ze='Zenithgrey:BAABNQAECn8XAAMTAAkKMQ6ghwCRAQATAAcKug6ghwCRAQAQAAUKJQ8KqgAdAQAAAA==.',
Zl='Zluco:BAACNQAFFH8NAAIgAAQKciMBAgAmAQAgAAQKciMBAgAmAQA1AAQKf0gAAyAACgoYJtcAAG0DACAACgoYJtcAAG0DABAABgp5HAd+AJIBAAAA.',
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
