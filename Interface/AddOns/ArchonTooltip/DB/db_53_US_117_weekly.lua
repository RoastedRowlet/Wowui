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

local lookup = {'Warrior-Arms','Warrior-Fury','Druid-Restoration','Paladin-Protection','Monk-Windwalker','Priest-Holy','Priest-Shadow','DemonHunter-Vengeance','Paladin-Holy','Paladin-Retribution','Hunter-BeastMastery','Rogue-Subtlety','DemonHunter-Devourer','DemonHunter-Havoc','Druid-Guardian','Druid-Feral','Warlock-Demonology','Shaman-Elemental','Monk-Mistweaver','Unknown-Unknown','Mage-Arcane','Priest-Discipline','Shaman-Enhancement','Shaman-Restoration','Hunter-Marksmanship','Warlock-Destruction','Warlock-Affliction','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Mage-Frost','Druid-Balance','DeathKnight-Frost','DeathKnight-Blood','Monk-Brewmaster','DeathKnight-Unholy','Warrior-Protection','Rogue-Assassination','Mage-Fire','Rogue-Outlaw','Hunter-Survival',}
local provider = {region='US',realm='Hakkar',name='US',type='weekly',zone=53,date='2026-11-10',data={Ac='Aceshaman:BAAANQADCgIIAgAAAA==.Acheros:BAAANQADCgMIAwAAAA==.Actionfigure:BAACNQAFFH8KAAIBAAQKyCCkFQB7AQABAAQKyCCkFQB7AQA1AAQKfzUAAwIACgqCJCMFAHgCAAEACgonH2A3AOYCAAIACAptJCMFAHgCAAAA.',
Ad='Adielia:BAABNQAECn8kAAIDAAkKwhprGwARAgADAAkKwhprGwARAgAAAA==.Adurzin:BAAANQADCgIIAgAAAA==.',
Ae='Aeralina:BAAANQADCgUJBQAAAA==.Aeri:BAAANQADCgIIAwAAAA==.Aevalaana:BAAANQAECgYICQAAAA==.',
Ag='Agiermodinn:BAAANQADCgYICgAAAA==.',
Ah='Ahnho:BAAANQADCggICgAAAA==.',
Ai='Aidandrius:BAAANQADCgMIAwAAAA==.Aimeeleigh:BAAANQAECgQIBAABNQAECgoKKwAEAC8ZAA==.Airflash:BAACNQAFFH8MAAIFAAUKEx4tCQBFAQAFAAUKEx4tCQBFAQA1AAQKfzkAAgUACAo/JasHAFQDAAUACAo/JasHAFQDAAAA.Aiøn:BAAANQADCgcIBwAAAA==.',
Ak='Akutagawa:BAABNQAECn8rAAMGAAkKoxoHJQCsAgAGAAkKoxoHJQCsAgAHAAEKAADRcAAAAAABNQAFFAUIDwAIAPMbAA==.',
Al='Alexious:BAACNQAFFH8TAAIEAAYKASC8AgBXAQAEAAYKASC8AgBXAQA1AAQKfzUAAgQACgqFIk4HAC4DAAQACgqFIk4HAC4DAAAA.Aloonarn:BAAANQAECgYIDQAAAA==.Alopix:BAAANQAECggIDQAAAA==.Alulla:BAACNQAFFH8SAAMCAAUKqh7rAQD0AAABAAQKqh5tFwBnAQACAAMKwRjrAQD0AAA1AAQKfyIAAwIACgrzIa0KAB0CAAEACQoDISJJAK4CAAIABwoTIq0KAB0CAAAA.Alunira:BAABNQAECn87AAMJAAoKnh/gGAAVAwAJAAoKnh/gGAAVAwAKAAYKbhYTzQCBAQAAAA==.',
Am='Amberrfrost:BAAANQAECgQICAAAAA==.Amize:BAAANQADCgYIBgAAAA==.Ampz:BAAANQAECgQIBAAAAA==.',
An='Anabee:BAAANQADCggIDgAAAA==.Angelicshy:BAAANQADCgQIBAAAAA==.Angryhtr:BAABNQAECn8UAAILAAcKGhkydgAjAgALAAcKGhkydgAjAgAAAA==.Angryshh:BAAANQAECggICwAAAA==.Angrywar:BAABNQAECn8bAAIBAAgKHxL9nADUAQABAAgKHxL9nADUAQAAAA==.Anharon:BAAANQADCgcICgAAAA==.Ansatz:BAAANQAECgEIAwABNQAECgoKNgALAAkcAA==.',
Ap='Apokalypto:BAAANQAECgQIBAAAAA==.',
Ar='Arbiterbinky:BAAANQADCgUIBQAAAA==.Ardå:BAAANQADCgEIAQAAAA==.Argangus:BAAANQADCgYIDwAAAA==.Aridon:BAAANQAECgEIAQAAAA==.Arrowganz:BAAANQADCgYIBgAAAA==.Arthan:BAAANQAECgMIAwAAAA==.Arthannix:BAAANQADCgYICgAAAA==.',
As='Assine:BAAANQAECgEIAgABNQAFFAcIBwAMAA4AAA==.Astanis:BAAANQAECgcICgAAAA==.Asteriia:BAABNQAECn8eAAINAAoKfQlTJwBIAQANAAoKfQlTJwBIAQAAAA==.Astralyn:BAAANQAECgEIAQAAAA==.',
Au='Augito:BAAANQABCgIIAgAAAA==.',
Av='Averettara:BAAANQAECgIIBgABNQAECgkJFgAKAFESAA==.',
Az='Azarazan:BAAANQADCgYIDgAAAA==.Azka:BAABNQAECn8tAAIKAAoKDSAQKQCxAgAKAAoKDSAQKQCxAgAAAA==.Azkadk:BAAANQADCgYIBgAAAA==.',
Ba='Babybilly:BAABNQAECn8rAAMEAAoKLxkIEgD0AQAEAAoKLxkIEgD0AQAKAAMKkAOgcAFtAAAAAA==.Baelmon:BAAANQAECgQIBQAAAA==.Baludis:BAAANQADCgcIEQAAAA==.Bamff:BAAANQAECgUICQAAAA==.Bamfpally:BAAANQADCggICAAAAA==.Barreack:BAAANQADCgYICAAAAA==.Bast:BAACNQAFFH8PAAIIAAUK8xs8AgAuAQAIAAUK8xs8AgAuAQA1AAQKfz8AAwgACgpoJc4AAFoDAAgACgpoJc4AAFoDAA4ABQpFE2pSAEoBAAAA.Basthara:BAABNQAECn81AAMPAAoKGSPMAwAnAwAPAAoKGSPMAwAnAwAQAAEKVAIbUwAGAAABNQAFFAUIDwAIAPMbAA==.',
Be='Beckianslip:BAAANQADCgUIBQAAAA==.Belphegor:BAAANQAECgYIBQABNQAECgoKMAARAIoKAA==.Benif:BAACNQAFFH8PAAIBAAcKQh26DwC7AQABAAcKQh26DwC7AQA1AAQKfzsAAgEACgrvJf8GAFMDAAEACgrvJf8GAFMDAAAA.Benjaquel:BAAANQADCgQIBAAAAA==.Bertorod:BAABNQAECn8YAAISAAkKqxUfWAAbAgASAAkKqxUfWAAbAgAAAA==.',
Bi='Bigbitehotdo:BAABNQAECn88AAMFAAoKZB+MDgD3AgAFAAoKZB+MDgD3AgATAAEK3wHaVAAgAAAAAA==.Bighoney:BAAANQAECgIIAQAAAA==.Bigtommybuns:BAAANQADCgUIBQAAAA==.Binkyfiasco:BAAANQADCggIDgAAAA==.Binny:BAAANQADCgYIBgAAAA==.Birdiewordie:BAAANQADCgQIBAAAAA==.',
Bl='Bloodeie:BAAANQADCgQIBAAAAA==.Bloodstoned:BAABNQAECn8XAAINAAcKxgagMAD+AAANAAcKxgagMAD+AAAAAA==.Blueboy:BAABNQAECn8eAAIHAAoKJgxkGwClAQAHAAoKJgxkGwClAQAAAA==.Bluechewman:BAAANQADCgQIBAAAAA==.',
Bo='Boffadz:BAAANQAECggIEAAAAA==.Bonewand:BAAANQAECgEIAQAAAA==.Bonewrath:BAAANQABCgIIAgAAAA==.Boogat:BAAANQAECgUIDgAAAA==.Boomblessed:BAAANQAECgUIBQAAAA==.Boomkin:BAAANQAECgIIAQAAAA==.Bovillus:BAAANQAECgYICwAAAA==.Bowflex:BAAANQADCgQIBAAAAA==.',
Br='Braugorlle:BAAANQAECgcICAABNQAFFAUIEgASAI0dAA==.Breadscrumb:BAAANQADCgUJBQAAAA==.Bridrystina:BAAANQADCgQIBAAAAA==.Brixlo:BAAANQADCgEIAQABNQADCgcIBwAUAAAAAA==.Brokenfinger:BAAANQADCgIIAgAAAA==.',
Bu='Buffmuffin:BAAANQAECgIIAgAAAA==.Burblbiblr:BAAANQADCgQJBAAAAA==.Bustrdugles:BAAANQADCgUIBQAAAA==.',
Bw='Bwazakki:BAAANQADCgMIAwAAAA==.Bwr:BAAANQADCgMIAwAAAA==.',
['Bü']='Bübbawrap:BAAANQAECgQICAAAAA==.',
Ca='Cambrier:BAACNQAFFH8FAAIBAAIKVQ4YJwCBAAABAAIKVQ4YJwCBAAA1AAQKf0wAAwEACgrOIRwUAPoCAAEACgpGIRwUAPoCAAIACAqiIAgFANsCAAAA.Cameraop:BAABNQAECn8XAAIVAAcKKwj2EgFtAQAVAAcKKwj2EgFtAQAAAA==.Candyapples:BAAANQAECgEIAQAAAA==.Canias:BAAANQADCgQIBAABNQAECggICwAUAAAAAA==.Capnsoap:BAAANQADCgYIBgABNQABCgEIAQAUAAAAAA==.Capriestsun:BAAANQAECggICgAAAA==.Cardinal:BAAANQAECgIIAQAAAA==.Carynden:BAAANQAECgUIBQAAAA==.Castbo:BAAANQAECgcIEAABNQAFFAYIFQAWAB0RAA==.',
Ce='Celilinia:BAAANQAECgIIAgAAAA==.Cellesstia:BAAANQADCgMIBQABNQAECggIEwAUAAAAAA==.',
Ch='Chalada:BAAANQADCgEIAQABNQAFFAcIBwAMAA4AAA==.Chalastorm:BAAANQAECggIBQABNQAFFAcIBwAMAA4AAA==.Charknight:BAAANQADCgUIBQAAAA==.Chatdodu:BAAANQAECgEIAQAAAA==.Chatnoir:BAABNQAECn8YAAILAAkK7A4dbgDKAQALAAkK7A4dbgDKAQAAAA==.Chestock:BAAANQAECgYIBgAAAA==.Chuggz:BAAANQAECgQIBgAAAA==.',
Cl='Clonetastic:BAAANQADCggICAAAAA==.Clumsycarl:BAAANQADCgIIAgAAAA==.',
Cm='Cmx:BAAANQADCgUIBQAAAA==.',
Co='Codith:BAAANQAECgQIBQAAAA==.Coldlock:BAAANQADCgQIBAAAAA==.Colesiaw:BAAANQADCgQIBgAAAA==.Coraeze:BAAANQADCgEIAQAAAA==.',
Cp='Cptcrunch:BAABNQAECn8WAAMKAAcKSw54zAAoAQAKAAYKOg54zAAoAQAEAAQKvwoiQwCHAAABNQAECgkJLwASAP4cAA==.',
Cr='Crais:BAAANQAECgYIBgAAAA==.Creek:BAAANQABCgYIBgABNQAECgoKMAAOAIQgAA==.Critneyfears:BAAANQAECgIIAQABNQAECgIIAgAUAAAAAA==.Crnogorac:BAAANQAECggIAQAAAA==.Crotchgoblim:BAAANQAECgUIBQAAAA==.Cryodormu:BAAANQAECgMJAwAAAA==.',
Cu='Cubo:BAAANQAECgEIAQAAAA==.Cuddlesworth:BAABNQAECn8wAAIRAAoKigroZwCLAQARAAoKigroZwCLAQAAAA==.',
Cw='Cwarr:BAAANQAECgIIAgABNQAFFAYICQAXANIOAA==.',
Cy='Cyrcee:BAAANQADCgUIBQABNQAECggIEwAUAAAAAA==.',
Da='Daddyluis:BAAANQADCggICwAAAA==.Dadstonks:BAAANQABCgYJCAAAAA==.Dagoujiao:BAABNQAECn8ZAAMSAAoKVguMWABmAQASAAoKVguMWABmAQAYAAcKGg0ErwASAQAAAA==.Dameiyo:BAAANQAECggIEgAAAA==.Dandanh:BAAANQADCgMIAwAAAA==.Dangright:BAABNQAECn8aAAIZAAgKXwVBPgBgAQAZAAgKXwVBPgBgAQAAAA==.Dankbo:BAACNQAFFH8VAAMWAAYKHREfAgDVAAAGAAUKMhQiGAAyAQAWAAMK1ggfAgDVAAA1AAQKfz0AAxYACgr/IrMCAOQCABYACAq6ILMCAOQCAAYACgrbHvYlANMCAAAA.Danorac:BAABNQAECn8nAAINAAoKGQ3LGgDCAQANAAoKGQ3LGgDCAQAAAA==.Darkcoffee:BAABNQAECn8kAAIEAAcKvRs+EwDgAQAEAAcKvRs+EwDgAQAAAA==.Darkivie:BAAANQADCgYIBgABNQAECgkJHgAKAGMFAA==.Datgoodtree:BAAANQADCgIIAgAAAA==.',
De='Deadashe:BAAANQADCgEIAQAAAA==.Demonicsword:BAAANQADCgQIBAAAAA==.Despondent:BAAANQADCggIFgAAAA==.Devilcrybaby:BAAANQAECgIIAgAAAA==.Devildj:BAAANQAECggIEwAAAA==.Dezadian:BAABNQAECn8iAAIKAAgKJwXY8wDnAAAKAAgKJwXY8wDnAAAAAA==.',
Dh='Dhampyra:BAABNQAECn8YAAMHAAgKOBOFJQADAgAHAAgKOBOFJQADAgAGAAQKDRd0nQDsAAAAAA==.',
Di='Dietmountdew:BAAANQAECgQIBAAAAA==.Dimitrios:BAAANQAECgcICQAAAA==.Disolve:BAABNQAECn8gAAQRAAkKFBGueAD5AQARAAkKog2ueAD5AQAaAAIK9hY7UgCIAAAbAAEKAABKJQBZAAAAAA==.Dixxonciderr:BAACNQAFFH8IAAIcAAUKuAeKEgC4AAAcAAUKuAeKEgC4AAA1AAQKf0kABBwACgohHo8JAAoDABwACgohHo8JAAoDAB0ABwqLD8UgAE0BAB4AAgpZFf0dAHIAAAAA.',
Dm='Dmdedifudo:BAAANQADCgQIBQAAAA==.Dmoe:BAAANQAECgYICwAAAA==.',
Do='Docutratties:BAAANQAECgMIAgABNQAECgoKMAARAIoKAA==.Doji:BAAANQADCgEIAQAAAA==.Doublesixes:BAAANQADCggIEwAAAA==.',
Dq='Dqe:BAAANQAECgEIAQAAAA==.',
Dr='Drac:BAAANQADCgMIAwAAAA==.Dragonara:BAAANQADCggICAAAAA==.Draskion:BAAANQADCgcIBwAAAA==.Dribby:BAAANQAECgQIBAABNQAECggIDQAUAAAAAA==.',
Du='Duhästmich:BAAANQADCgYIBgABNQAECgkJFgAKAFESAA==.Duplicate:BAACNQAFFH8PAAMfAAQKjBQTCQCOAAAVAAQKjBSxKADFAAAfAAIKGA8TCQCOAAA1AAQKfzAAAxUACgqHHeE4AFcCABUACgqHHeE4AFcCAB8AAQonG6BBAEEAAAAA.Dustdruid:BAACNQAFFH8FAAIgAAMKdxCdGgDNAAAgAAMKdxCdGgDNAAA1AAQKfzYAAiAACQpLIH4VAFoCACAACQpLIH4VAFoCAAAA.Dustlock:BAAANQAECggIEAAAAA==.Dustmage:BAAANQADCggIEAAAAA==.Dustsham:BAAANQAECgEIAQAAAA==.',
Dw='Dwarr:BAAANQAECgYICAAAAA==.',
Dy='Dysnomia:BAAANQAECgIIAgAAAA==.',
Dz='Dzoolock:BAAANQAECgEIAQAAAA==.',
['Dó']='Dóru:BAAANQADCgYIBwAAAA==.',
Ee='Eender:BAAANQAECgEIAQAAAA==.',
Eg='Eggrolls:BAABNQAECn9EAAIBAAoKNB4AIwAsAwABAAoKNB4AIwAsAwAAAA==.',
El='Eldenmorden:BAAANQADCgYIBwAAAA==.Eleshmelly:BAAANQADCgcIFgAAAA==.Elfrafa:BAAANQADCgUIBgAAAA==.Ellayna:BAAANQADCgEIAQAAAA==.Ellcrys:BAABNQAECn9LAAIDAAoKMB13CwD+AgADAAoKMB13CwD+AgAAAA==.Elletta:BAAANQAECgIIAQAAAA==.Elrae:BAAANQAECgYIBgAAAA==.',
Ep='Epoptes:BAAANQAECgUICAABNQAECgoKLAAEAJsMAA==.',
Eq='Eqo:BAABNQAECn8dAAMGAAkKERI8eQCvAQAGAAkKERI8eQCvAQAHAAEKxQl3dAA9AAAAAA==.',
Er='Erisian:BAAANQAECgUIBQAAAA==.Erkêios:BAABNQAECn8gAAIhAAkK3hTENgCwAQAhAAkK3hTENgCwAQAAAA==.Ersande:BAAANQAECgQIBgAAAA==.Ertz:BAAANQADCggICQAAAA==.',
Es='Escherichia:BAAANQAECgEJAQAAAA==.Estheban:BAABNQAECn8gAAQdAAkKOR/yDgBtAgAdAAkKOR/yDgBtAgAeAAMKFRYiGgBCAAAcAAEKQAtiUAAtAAAAAA==.',
Ev='Evengelist:BAABNQAECn8eAAMGAAoK1RBhTADxAQAGAAkK9w1hTADxAQAWAAUKdRFyEAAiAQAAAA==.',
Fa='Face:BAAANQAECgcIDAAAAA==.Fairgrim:BAAANQAECgQIBAAAAA==.Falin:BAABNQAECn9NAAIKAAoKqhswQwDLAgAKAAoKqhswQwDLAgAAAA==.Faqueuedark:BAABNQAECn8kAAIRAAoKyR/JEwDMAgARAAoKyR/JEwDMAgABNQAFFAQIDAAIAMENAA==.Faqueueeight:BAACNQAFFH8MAAMIAAQKwQ0jAwCVAAAIAAQKwQ0jAwCVAAAOAAEKvAOUIAAxAAA1AAQKf1UAAwgACgpoIaUFAEkCAA4ACgq0HxoSAA4DAAgACgp1GqUFAEkCAAAA.Fatalyeeyee:BAAANQAECgcICAABNQAFFAMIBQARAKADAA==.Fatsloth:BAAANQAECgYICAAAAA==.Fatébringer:BAAANQADCgYIDAABNQAECgEIAQAUAAAAAA==.Faulted:BAAANQADCgUIBQAAAA==.',
Fe='Feironos:BAAANQADCggICAAAAA==.Felcookies:BAAANQAECgYIEAAAAA==.Ferrick:BAAANQAECgIIAgAAAA==.',
Fi='Fiist:BAAANQAECggICAAAAA==.Fimtastic:BAABNQAECn8nAAIYAAkK2xOPXQCJAQAYAAkK2xOPXQCJAQAAAA==.Finasy:BAABNQAECn83AAMiAAoK8iM1GwDVAgAiAAoK8iM1GwDVAgAhAAgKtxTjPQCOAQAAAA==.Finbezy:BAAANQAECgQIAwAAAA==.Finnicka:BAAANQAECgEIAQAAAA==.Firen:BAAANQADCgcIFAAAAA==.Fireouch:BAAANQABCgIIAwAAAA==.Fistymisty:BAABNQAECn8cAAIjAAkKix98BAAvAwAjAAkKix98BAAvAwAAAA==.Fizeecian:BAAANQAECgQIBQAAAA==.',
Fl='Flaynpray:BAAANQADCgEIAQAAAA==.Fluffenstein:BAABNQAFFH8IAAIBAAQKmAIbIwCXAAABAAQKmAIbIwCXAAAAAA==.',
Fo='Foxrawruwu:BAABNQAECn8WAAIRAAgKqRqZNgCxAgARAAgKqRqZNgCxAgAAAA==.',
Fr='Frakk:BAAANQAECggIAQAAAA==.Freezegarr:BAACNQAFFH8PAAIVAAYKcRleEQBQAQAVAAYKcRleEQBQAQA1AAQKfzYAAhUACgrpIOcTAPMCABUACgrpIOcTAPMCAAAA.Frey:BAAANQADCgIIAgAAAA==.Frostgrave:BAAANQADCgEIAQAAAA==.Frostya:BAAANQADCgYIBgAAAA==.Frozzty:BAAANQAECgIIAgAAAA==.',
Fu='Fujibayashi:BAAANQAECgQIDAAAAA==.Furearia:BAAANQABCgcICQAAAA==.Furrybowner:BAAANQAECggIDwAAAA==.',
Ga='Galeriel:BAACNQAFFH8WAAIGAAYKGB5kDADFAQAGAAYKGB5kDADFAQA1AAQKf0sAAgYACgoZJj8CABMEAAYACgoZJj8CABMEAAAA.Galileo:BAAANQAECgIIAgAAAA==.Gallethline:BAAANQAECgIIBQAAAA==.Ganjgotti:BAAANQADCgYICQAAAA==.Garault:BAAANQAECggICAAAAA==.Gavered:BAAANQADCgMIBQAAAA==.',
Ge='Gekoni:BAABNQAECn8WAAIEAAgKQAfrLwDpAAAEAAgKQAfrLwDpAAAAAA==.Geonon:BAAANQADCggICAAAAA==.Geotracker:BAABNQAECn8fAAILAAkKyg5qfQClAQALAAkKyg5qfQClAQABNQADCggICAAUAAAAAA==.',
Gh='Ghorros:BAAANQADCgMIAwAAAA==.',
Gi='Gilgahmesh:BAABNQAECn8eAAIBAAoK7BAYbwCfAQABAAoK7BAYbwCfAQABNQAECgoKPAAJAEUfAA==.',
Gl='Glowpwr:BAAANQADCgcIBwAAAA==.',
Go='Golruck:BAAANQAECggICgABNQAECgkJFQALAA4XAA==.Goolgame:BAACNQAFFH8SAAMSAAUKjR1lDACmAQASAAUKjR1lDACmAQAYAAMKXBXeFgDwAAA1AAQKfywAAxIACgooIMo8AIICABIACApAIco8AIICABgABQq9G2SHAHgBAAAA.Goonthergg:BAAANQADCgYIBgAAAA==.Goothix:BAAANQADCgcJCAAAAA==.Gothmog:BAAANQADCgIIAgAAAA==.',
Gr='Grammarg:BAAANQADCgMIAwAAAA==.Grezzert:BAAANQADCgMIAwAAAA==.Grirr:BAAANQAECgIIBAAAAA==.Grothin:BAACNQAFFH8GAAIYAAIKnhWlIACHAAAYAAIKnhWlIACHAAA1AAQKfzcAAhgACgqvHC4aANICABgACgqvHC4aANICAAAA.Gruldag:BAACNQAFFH8KAAIVAAQK7hOmJQDXAAAVAAQK7hOmJQDXAAA1AAQKfzkAAhUACgrXHCZdAMUCABUACgrXHCZdAMUCAAAA.Grullander:BAABNQAECn87AAIYAAoKkBO5TgDAAQAYAAoKkBO5TgDAAQAAAA==.',
Gu='Guiguiie:BAAANQADCggJEAAAAA==.',
Gw='Gwyndolynn:BAAANQADCgQIBQAAAA==.',
Ha='Haeheia:BAAANQADCgIIAgAAAA==.Haeldir:BAAANQADCgYIBQAAAA==.Hailey:BAEANQAECggIEwABNQAFFAcIDAAJAIoLAA==.Halter:BAAANQAECgIIAgAAAA==.Hapló:BAAANQABCgEIAQAAAA==.Haratvy:BAAANQAECgEIAQAAAA==.Hazzurd:BAABNQAECn8cAAILAAoKuBC8cwApAgALAAoKuBC8cwApAgAAAA==.',
He='Header:BAACNQAFFH8bAAIZAAgK8xqiBQACAgAZAAgK8xqiBQACAgA1AAQKfzAAAxkACgrlHjYOAEsCABkACgrlHjYOAEsCAAsABQrhCjP9AAoBAAAA.Healsorz:BAAANQADCgcIBwAAAA==.Heersbeest:BAAANQABCggIDgAAAA==.Helane:BAAANQADCgUIBQAAAA==.Herkharu:BAAANQADCgcIBwAAAA==.Hermionee:BAABNQAECn85AAMVAAoK8hF8mQBfAQAVAAkKWA18mQBfAQAfAAMKUhYtIgC1AAAAAA==.Hetu:BAAANQABCgUIBAAAAA==.',
Hi='Hide:BAAANQAECgEIAQAAAA==.Himjongun:BAABNQAECn8mAAMOAAoKGhjVKACwAQAOAAkKGhjVKACwAQANAAEKAADddQAiAAAAAA==.',
Ho='Holya:BAAANQADCgEIAQABNQAFFAcIBwAMAA4AAA==.Holycowe:BAAANQAECgcIDQAAAA==.Holykoi:BAABNQAECn9MAAIGAAoKYRJ9NwBKAgAGAAoKYRJ9NwBKAgAAAA==.',
Hr='Hroarr:BAABNQAECn8ZAAIiAAoKRSKTDgA7AwAiAAoKRSKTDgA7AwABNQAFFAYIDwAVAHEZAA==.',
Hu='Humancarnage:BAAANQADCgYIBwAAAA==.Huuh:BAAANQADCgUICgAAAA==.',
Hy='Hypaexia:BAAANQADCgIIAgAAAA==.',
['Hà']='Hàvoc:BAAANQADCggIDQAAAA==.',
['Hé']='Héboric:BAABNQAECn8vAAIJAAoKLR/ZEQAfAwAJAAoKLR/ZEQAfAwAAAA==.Hélbrecht:BAAANQAECgMIAwAAAA==.',
['Hÿ']='Hÿbrìd:BAAANQAECgYIDwAAAA==.',
Ia='Iamwho:BAAANQAECggICAAAAA==.Iatros:BAABNQAECn8sAAMEAAoKmwwaHQBxAQAEAAoKlgwaHQBxAQAKAAQKPQOwawFJAAAAAA==.',
Id='Idkno:BAAANQAECgIIAQAAAA==.',
Ik='Ikara:BAAANQADCggICAABNQAECgoKJgAbAAwQAA==.Ikodiwa:BAAANQADCgUIBQAAAA==.',
Im='Imjustsaiyan:BAAANQADCgIIAgAAAA==.',
In='Indravax:BAABNQAECn8cAAIRAAkKQRSdeQD3AQARAAkKQRSdeQD3AQAAAA==.',
Io='Iorin:BAAANQADCggIBwABNQAFFAQICQAOAK0BAA==.',
It='Itwasntmebru:BAAANQADCgYIFAAAAA==.',
Iv='Ivantis:BAAANQADCgYIFwAAAA==.Ivie:BAAANQAECggIEwAAAA==.',
Iw='Iwonabhornee:BAAANQAECgEIAQAAAA==.',
Ja='Jaholypriest:BAACNQAFFH8KAAIGAAQKVBJpGQAUAQAGAAQKVBJpGQAUAQA1AAQKfyAAAgYACgpmFf5WAB4CAAYACgpmFf5WAB4CAAAA.Janjor:BAAANQAECgYICAAAAA==.Janjy:BAAANQADCgcIBwAAAA==.Jaypiea:BAABNQAECn8iAAMeAAkKTBUCCAAgAgAeAAgKTBUCCAAgAgAdAAgK8xC2FwDOAQAAAA==.',
Je='Jergall:BAAANQADCgUIBQAAAA==.Jettian:BAABNQAECn8YAAIkAAcKrwuPPgAHAQAkAAcKrwuPPgAHAQAAAA==.',
Ji='Jibz:BAAANQADCgEIAQAAAA==.',
Jj='Jjdruid:BAAANQAECgIIAgAAAA==.',
Jo='Johnathon:BAAANQAECgMIAwABNQAECgMIBAAUAAAAAA==.Jollygreene:BAAANQAECgEIAgAAAA==.Jonestu:BAAANQAECgQIBgAAAA==.Joyina:BAAANQADCgYIBgAAAA==.',
Jp='Jpgigacat:BAAANQAECgYICAAAAA==.Jpgigademon:BAAANQAECgMIBAAAAA==.Jpgigawolf:BAAANQAECggIDQAAAA==.',
Ju='Justakatt:BAAANQADCgIIAgAAAA==.Justicasia:BAAANQADCgQIBAABNQADCgYIBgAUAAAAAA==.',
Ka='Kadinsky:BAAANQADCgUIBQAAAA==.Kalivan:BAAANQADCgYIBwAAAA==.Kankimasamu:BAAANQADCgQIBAAAAA==.Karametra:BAABNQAECn8XAAISAAgK/RR+PADMAQASAAgK/RR+PADMAQAAAA==.Karlldun:BAAANQAECgcIDQAAAA==.Kasmir:BAABNQAECn8nAAMRAAkK0g6blwCsAQARAAkK0g6blwCsAQAaAAEKLggUfQAwAAAAAA==.Kasnfriends:BAAANQADCgUIBQABNQAECgkJJwARANIOAA==.',
Ke='Kevv:BAACNQAFFH8PAAISAAYKIQN0EwDEAAASAAYKIQN0EwDEAAA1AAQKfzsAAxIACgqNHV4VALQCABIACgqNHV4VALQCABcAAQoAAPI7ABkAAAAA.Keyniron:BAABNQAECn/rAAIKAAkK4CWKBABwAwAKAAkK4CWKBABwAwAAAA==.',
Kh='Khogent:BAAANQADCgQIBAAAAA==.Khonsu:BAAANQAECgQIBAABNQAECgcIDQAUAAAAAA==.Khrover:BAAANQADCgUIBQAAAA==.Khyle:BAAANQADCgYIBwAAAA==.',
Ki='Kijanajr:BAAANQADCgMIAgAAAA==.Killaarrow:BAABNQAECn9EAAILAAoKSAkBcQDCAQALAAoKSAkBcQDCAQAAAA==.Kiloton:BAAANQAECgIIAgAAAA==.Kindleos:BAAANQAECgEIAQAAAA==.',
Kk='Kkpriest:BAAANQADCgEIAQAAAA==.',
Kl='Klay:BAAANQAECgYIDQAAAA==.',
Km='Kmarte:BAEANQAECgYIEAABNQAECggIDwAUAAAAAA==.Kmarti:BAEANQAECggIDwAAAA==.Kmartt:BAEBNQAECn8nAAIKAAoKjhsPSQA/AgAKAAoKjhsPSQA/AgABNQAECggIDwAUAAAAAA==.',
Ko='Kosmic:BAAANQADCgcICQABNQAECgoKMgAiAIYYAA==.Kosmicknight:BAABNQAECn8yAAMiAAoKhhhbFwA9AgAiAAoKhhhbFwA9AgAhAAEKAAA4twAoAAAAAA==.',
Kr='Kraggers:BAAANQAECgYIDQAAAA==.Kraggory:BAAANQAECgIIAgAAAA==.Kraggoryqt:BAABNQAECn8UAAIKAAQKIxz/uwBEAQAKAAQKIxz/uwBEAQAAAA==.Kraggoryx:BAAANQAECgEIAQAAAA==.Krunclez:BAAANQAECggICwAAAA==.Kryesta:BAABNQAECn9MAAIYAAoKZiGyEwAIAwAYAAoKZiGyEwAIAwAAAA==.',
Kw='Kwarr:BAACNQAFFH8JAAIXAAYK0g6jAwA8AQAXAAYK0g6jAwA8AQA1AAQKf0MAAhcACgrOIjkDAG0DABcACgrOIjkDAG0DAAAA.',
La='Laganddecay:BAAANQABCggIGQAAAA==.Lalii:BAAANQAECgQIBwAAAA==.Lallatath:BAAANQADCgcIBwAAAA==.Lammoth:BAAANQADCgYICwAAAA==.Lanemogsnick:BAAANQADCgQIBAAAAA==.Larissä:BAAANQAECgIIAgABNQAECgoKUQALANkWAA==.Layonhandsy:BAAANQAECgQIBAABNQAFFAQICQAiABYhAA==.',
Le='Leafu:BAAANQAECgMIAwABNQAECgoKMgAHAIQcAA==.Leasin:BAABNQAECn8yAAIHAAoKhBywEwDKAgAHAAoKhBywEwDKAgAAAA==.Lencreye:BAAANQADCgMIBAAAAA==.Lethendervis:BAAANQADCgYIDgAAAA==.',
Li='Lighthusk:BAAANQABCgQIBAAAAA==.Liliauna:BAABNQAECn8jAAIRAAcK+xr9aQAeAgARAAcK+xr9aQAeAgAAAA==.Lilibejeane:BAAANQADCgcIDgABNQAECgcIFgAOAOkRAA==.Lillynelazar:BAABNQAECn8cAAILAAoKBgUwtwCVAQALAAoKBgUwtwCVAQABNQAECgYICQAUAAAAAA==.Liloisback:BAABNQAECn8fAAIBAAoKUxZ7eQCDAQABAAoKUxZ7eQCDAQAAAA==.Lilsquirtboy:BAAANQADCgUIBQABNQAECgoKPAAFAGQfAA==.Linasonna:BAAANQAFFAEIAQABNQAFFAUIEgASAI0dAA==.Linbächle:BAAANQAECgIIAgAAAA==.Linithara:BAACNQAFFH8JAAIOAAQKrQGoEgCRAAAOAAQKrQGoEgCRAAA1AAQKfyMAAw4ACgpXDQw3APgBAA4ACgodDAw3APgBAAgACArlCZwWAEMBAAAA.Lionabtglad:BAAANQAECgIIAgAAAA==.Littlehoosie:BAABNQAECn8VAAILAAkKDhd6XwDwAQALAAkKDhd6XwDwAQAAAA==.',
Lo='Lockersz:BAAANQADCgEIAQABNQAFFAcIFQAhAJ4TAA==.Lokedin:BAAANQAECgUIBQAAAA==.Loram:BAAANQAECgEIAQAAAA==.Lostbase:BAAANQAECgQIBAAAAA==.Lostgrip:BAAANQAECgcIEAAAAA==.',
Lu='Lucthedk:BAABNQAECn8WAAMkAAkK/xAzTADkAQAkAAkK/xAzTADkAQAhAAQKWwrPeADBAAAAAA==.Lukis:BAAANQAECgYICQAAAA==.Lunarpriest:BAAANQAECgQIBAAAAA==.Lunitari:BAAANQAECgEIAQAAAA==.Lunkbeck:BAAANQAECgEIAgAAAA==.Luxriel:BAAANQADCggIDAAAAA==.',
Ly='Lyllith:BAAANQADCgIIAQABNQAECgcIDQAUAAAAAA==.',
['Lø']='Lørd:BAABNQAECn8uAAMZAAoKNB12IABLAgAZAAgK9hl2IABLAgALAAcKVx7RdgC0AQAAAA==.',
Ma='Madik:BAAANQADCgcJCAAAAA==.Magicmegan:BAAANQAECgEIAQABNQAECggIFgARAKkaAA==.Mahoragax:BAAANQAECggIBgAAAA==.Malachí:BAAANQADCgUIBQABNQAECggIGgAiAF0NAA==.Maladin:BAAANQAECgQIBgAAAA==.Malkurim:BAAANQADCgEIAQAAAA==.Malvean:BAAANQADCgUICgAAAA==.Manasa:BAAANQAECgYIDwAAAA==.Marblack:BAAANQAECggIDQAAAA==.Marceline:BAABNQAECn8uAAILAAoKihaNQgA8AgALAAoKihaNQgA8AgAAAA==.Marthahog:BAAANQAECgYIBgABNQAECgkJOQAlAMgWAA==.Marthog:BAABNQAECn85AAMlAAkKyBazCQAhAgAlAAkKyBazCQAhAgABAAQKTQdYBAFdAAAAAA==.Mashido:BAAANQADCgMIAwAAAA==.Matresstains:BAAANQAECgUICwAAAA==.',
Mc='Mcdermott:BAAANQAECgQIBgAAAA==.',
Me='Melanius:BAAANQAECgUIDQAAAA==.Melranis:BAAANQADCgcIDAAAAA==.',
Mi='Miluk:BAABNQAECn8VAAIVAAkKVw1ZoQBPAQAVAAkKVw1ZoQBPAQAAAA==.Misconduct:BAABNQAECn8nAAIOAAoKMhqTEgCAAgAOAAoKMhqTEgCAAgAAAA==.',
Mm='Mmins:BAAANQAECgYICgAAAA==.',
Mo='Montagne:BAAANQADCgQIBAAAAA==.Moomist:BAAANQAECgQIBgAAAA==.Moondarin:BAAANQABCgIIAgAAAA==.Moonfanna:BAAANQAECgQJBQAAAA==.Moonmx:BAAANQAECgYICgAAAA==.Morriganth:BAAANQADCgEIAQAAAA==.',
Mu='Mujina:BAAANQAECgMIAwABNQAFFAUIEgACAKoeAA==.Murdamoose:BAAANQADCgIIAgAAAA==.Mustysponge:BAAANQADCgUIBwAAAA==.',
My='Mysteryx:BAABNQAECn8mAAIHAAoKYRSuGQCAAgAHAAoKYRSuGQCAAgAAAA==.Mystrbeast:BAAANQADCgQIBAAAAA==.',
['Mó']='Móxie:BAAANQADCgIIAQAAAA==.',
Na='Nahtan:BAAANQADCgYIDAAAAA==.Nammu:BAAANQADCgEIAQAAAA==.Nandisa:BAAANQADCgEIAQAAAA==.Naniwa:BAAANQAECgUICQAAAA==.Nawala:BAAANQAECgEIAQAAAA==.Nazaar:BAAANQADCgIIAgAAAA==.Nazendrov:BAEANQAECggICAABNQAECggICAAUAAAAAA==.Nazura:BAAANQADCgcIEQAAAA==.',
Ne='Nereza:BAAANQADCggIDgAAAA==.Nershog:BAAANQAECgEIAQAAAA==.Nesquip:BAAANQADCgYJBgAAAA==.Newil:BAAANQADCgYIBgAAAA==.',
Ni='Nightforday:BAABNQAECn8zAAMkAAkKiSDHIwC0AgAkAAkKiSDHIwC0AgAhAAIKUhVhjgB+AAAAAA==.Niko:BAAANQABCgUIBwAAAA==.Nishra:BAAANQADCggICAAAAA==.',
No='Noks:BAAANQAECggIBwAAAA==.Noktas:BAAANQAECgYIBwABNQAECgcIBgAUAAAAAA==.Nokx:BAAANQAECgcIBgAAAA==.Nominé:BAAANQADCgQIBgAAAA==.Nool:BAAANQADCgQIBwAAAA==.Norch:BAAANQAECgIJBAAAAA==.Notkory:BAAANQAECggICAAAAA==.Noux:BAAANQAECgUIBQAAAA==.',
Nu='Nube:BAAANQADCggIDAAAAA==.',
Ny='Nyababa:BAAANQAECgYICgABNQAFFAUIEgACAKoeAA==.',
Oc='Octavia:BAAANQAECgIIAgAAAA==.',
Og='Ogora:BAAANQADCgQIBgAAAA==.',
Ok='Oki:BAAANQADCgMIBAAAAA==.Okktrål:BAAANQAECgYJCgAAAA==.Oktavius:BAACNQAFFH8FAAIYAAMK+BJiFwDZAAAYAAMK+BJiFwDZAAA1AAQKf0YAAhgACgobI4EDAOMDABgACgobI4EDAOMDAAAA.',
Op='Ophysia:BAAANQAECgIIAgAAAA==.',
Or='Ordaka:BAAANQADCgYIBgAAAA==.Orkcansas:BAAANQAECgEIAQAAAA==.Orruutah:BAAANQADCgYIBgAAAA==.',
Os='Oskaia:BAAANQAECgYICwAAAA==.Osla:BAAANQAECgYIBQAAAA==.',
Ox='Oxytoecin:BAAANQAECgYIBgAAAA==.',
Pa='Paapineau:BAABNQAECn8XAAImAAkKQAcGIgAUAQAmAAkKQAcGIgAUAQAAAA==.Packel:BAAANQADCggICAABNQAECgoKQwAiAK8ZAA==.Packes:BAABNQAECn9DAAIiAAoKrxkHFQBXAgAiAAoKrxkHFQBXAgAAAA==.Packs:BAAANQADCgYIBgABNQAECgoKQwAiAK8ZAA==.Pakkohruun:BAABNQAECn8gAAIKAAoKcxfXbgBSAgAKAAoKcxfXbgBSAgAAAA==.Pallyative:BAAANQADCgIIAgAAAA==.Pallywack:BAABNQAECn9AAAIKAAoKZwyjhQCsAQAKAAoKZwyjhQCsAQAAAA==.Palussy:BAAANQADCgQIBAAAAA==.Parthima:BAABNQAECn9AAAMgAAoKWw5nJQC9AQAgAAoKWw5nJQC9AQADAAEKdwnSegAhAAAAAA==.Partysnaxx:BAAANQABCgEIAQAAAA==.',
Pe='Peppercat:BAAANQAECgQIBwAAAA==.Pertophos:BAAANQAECgUICQAAAA==.Pettigrew:BAAANQADCgIJAgAAAA==.',
Ph='Phantomclone:BAAANQAECgIIBQAAAA==.Phantomdh:BAAANQAECgEIAQAAAA==.Phantomghoul:BAAANQAECgUIBAAAAA==.Philomena:BAAANQADCgUICQAAAA==.',
Pi='Piggÿ:BAABNQAECn8YAAIPAAYKFQ/gPgCxAAAPAAYKFQ/gPgCxAAAAAA==.Piko:BAAANQADCggIDgAAAA==.Piyo:BAAANQADCgcIBwABNQAECgoKQwAiAK8ZAA==.',
Pl='Plankormast:BAAANQADCgEIAQAAAA==.',
Po='Poky:BAAANQAECgEIAQABNQAECgYICgAUAAAAAA==.Popena:BAAANQAECgMIBAAAAA==.Porkbuns:BAABNQAECn8oAAIVAAoKlhO1WgD1AQAVAAoKlhO1WgD1AQAAAA==.Potatogg:BAAANQAECgIIBAAAAA==.',
Pr='Praedor:BAAANQAECggIDAAAAA==.Priestymon:BAABNQAECn8oAAIGAAoK3CFeCwBnAwAGAAoK3CFeCwBnAwABNQAFFAcIDwABAEIdAA==.Protdaddyy:BAAANQADCgUIBQAAAA==.',
Pw='Pwarr:BAACNQAFFH8JAAIlAAQKxwtEBADpAAAlAAQKxwtEBADpAAA1AAQKfyUAAyUACgoyIVAFALECACUACgoyIVAFALECAAEACAoPDxnSAE0BAAE1AAUUBggJABcA0g4A.',
Qa='Qamar:BAAANQADCgQIBAAAAA==.',
Qu='Quackadeen:BAAANQAECgIJAgAAAA==.Quaesitor:BAAANQADCgYIDwAAAA==.',
Qw='Qwarr:BAAANQAECgUICAABNQAFFAYICQAXANIOAA==.',
Ra='Raamey:BAAANQADCgIIAgAAAA==.Raathya:BAABNQAECn8lAAILAAoKBROHSAAsAgALAAoKBROHSAAsAgAAAA==.Raeljin:BAABNQAECn8ZAAISAAgKLxlaQQBwAgASAAgKLxlaQQBwAgAAAA==.Ragetastick:BAAANQAECggICQAAAA==.Raihua:BAAANQADCgYIBgAAAA==.Rampagarex:BAAANQADCgYIBgAAAA==.Rangoz:BAAANQAECgUIDQAAAA==.Rar:BAABNQAECn8oAAILAAoKtiCCGQDSAgALAAoKtiCCGQDSAgAAAA==.Ratgamerlol:BAACNQAFFH8FAAILAAIKbyDyGAC5AAALAAIKbyDyGAC5AAA1AAQKfzgAAgsACQoOJUgqAPACAAsACQoOJUgqAPACAAAA.Ravnur:BAAANQADCggICAAAAA==.Rayennagrom:BAAANQAECgIIAgAAAA==.',
Re='Reagent:BAAANQADCgMIAwAAAA==.Reckrunner:BAABNQAECn9IAAQRAAoKVhSbXQCoAQARAAgK0hSbXQCoAQAbAAMKKBBJHACAAAAaAAEKMw8+MgA9AAAAAA==.Redlocks:BAAANQAECggIDAAAAA==.Renault:BAAANQADCgMIAwAAAA==.Reneana:BAAANQAECgUIDAAAAA==.Restbo:BAACNQAFFH8LAAIYAAYKsxmVBgD+AQAYAAYKsxmVBgD+AQA1AAQKfywAAhgACgrHJHQLAGUDABgACgrHJHQLAGUDAAE1AAUUBggVABYAHREA.',
Rg='Rgent:BAAANQADCgYIBgABNQADCgYIBwAUAAAAAA==.',
Rh='Rhianonn:BAAANQAECgYIEgABNQAECggIEwAUAAAAAA==.',
Ri='Riaslock:BAAANQAECgEJAQAAAA==.Riaswar:BAAANQADCgEIAQAAAA==.Richardluis:BAABNQAECn8VAAISAAcKwwrPoABVAQASAAcKwwrPoABVAQAAAA==.Rinehardtt:BAABNQAECn88AAIJAAoKRR8OIwDgAgAJAAoKRR8OIwDgAgAAAA==.Riverstyxx:BAAANQADCgYIEQAAAA==.Rivër:BAAANQADCggIJAAAAA==.',
Ro='Robbell:BAABNQAECn82AAILAAoK3BxLJwCUAgALAAoK3BxLJwCUAgAAAA==.Rococote:BAAANQAECggIEQAAAA==.Roggehere:BAAANQAECgIIAgAAAA==.Rokyman:BAAANQAECgYIEAAAAA==.Roldazark:BAAANQABCgEIAQAAAA==.Roonsia:BAAANQADCgQIBQAAAA==.Rootsie:BAAANQADCgYJFwAAAA==.Roselynn:BAABNQAECn8ZAAIDAAgKbRasHwAuAgADAAgKbRasHwAuAgAAAA==.Rouby:BAAANQAECgEIAgAAAA==.Roughlight:BAAANQADCgMIAwAAAA==.',
Ru='Ruerl:BAABNQAECn8YAAIKAAgKTAqxzACCAQAKAAgKTAqxzACCAQAAAA==.Runentug:BAACNQAFFH8JAAIiAAQKFiHtDQB1AQAiAAQKFiHtDQB1AQA1AAQKfxsAAiIACQqSJAkNAEkDACIACQqSJAkNAEkDAAAA.Rustyspell:BAAANQADCgIIAgAAAA==.',
Ry='Ryumapriest:BAAANQABCgEIAQAAAA==.',
['Rî']='Rîft:BAAANQADCgEIAQAAAA==.',
Sa='Sanddora:BAAANQADCgIIAgAAAA==.Sanlordriel:BAAANQAECgMIAwAAAA==.Saramon:BAAANQADCggIKQAAAA==.Sarios:BAAANQADCgQIAwAAAA==.Sassiberry:BAAANQADCgcIEQAAAA==.Sassitude:BAAANQADCgcIFQAAAA==.Satiiva:BAAANQADCggICAAAAA==.',
Sc='Scarlos:BAAANQABCgMIAwAAAA==.Screamdying:BAAANQABCgIIAgAAAA==.Scrembiblion:BAABNQAECn8vAAInAAoKdh0tAQDbAgAnAAoKdh0tAQDbAgAAAA==.',
Sd='Sdhoscillate:BAAANQADCgYIBgAAAA==.',
Se='Seins:BAAANQADCgYIBgAAAA==.Semillin:BAAANQAECgcIEAAAAA==.Senseitional:BAAANQAECgEIAQABNQAECgoKOwAPAGgiAA==.Sensjei:BAABNQAECn8UAAIFAAgKlQZOMwDtAAAFAAgKlQZOMwDtAAAAAA==.Sentarry:BAAANQAECgMIAwABNQAFFAYIDwAVAHEZAA==.Separatist:BAAANQADCgMIAwAAAA==.Serendibitty:BAAANQADCgMIAwABNQAECgUICAAUAAAAAA==.',
Sg='Sgtbreezy:BAAANQADCgcIBwAAAA==.',
Sh='Shadey:BAAANQADCgIIAgAAAA==.Shambulance:BAAANQAECgcIDQAAAA==.Sharuerl:BAAANQADCgcIBwAAAA==.Shawshaa:BAAANQAECgUIBQAAAA==.Shazi:BAEANQAECggICAAAAA==.Shiftroid:BAAANQADCgMIBgAAAA==.Shinyivie:BAABNQAECn8eAAIKAAkKYwX85ABRAQAKAAkKYwX85ABRAQAAAA==.Shiverchill:BAAANQABCgEJAQAAAA==.Shockrock:BAAANQADCgEIAQAAAA==.Shouzhe:BAAANQADCgUIBQAAAA==.Shroomjuice:BAAANQAECggIDwAAAA==.Shãdøwzzxz:BAAANQAECgUIDAAAAA==.',
Si='Sildenafil:BAAANQADCgIIAgAAAA==.Silessra:BAAANQADCggICAAAAA==.',
Sk='Skogr:BAAANQADCgIIAQABNQADCgUIBQAUAAAAAA==.Skädoosh:BAAANQAECgEIAQAAAA==.',
Sl='Slapshappy:BAAANQAECggICQAAAA==.',
Sm='Smallhorn:BAAANQAECgEIAgAAAA==.Smokeyhaze:BAAANQAECgYIDgAAAA==.Smokin:BAABNQAECn8rAAILAAkKMgpnoABWAQALAAkKMgpnoABWAQAAAA==.Smolther:BAAANQADCgcIBwAAAA==.Smores:BAAANQAECgEIAQAAAA==.',
Sn='Sneech:BAAANQAECgUICQAAAA==.Snikrot:BAAANQADCgcIBwAAAA==.Snowbvnni:BAAANQADCgQIBAAAAA==.',
So='Sofarkinghi:BAAANQAECgEIAgAAAA==.Sollamor:BAAANQAECgMIAwAAAA==.Solomonk:BAABNQAECn86AAIjAAkKHg5yDABUAQAjAAkKHg5yDABUAQAAAA==.Solomus:BAABNQAECn80AAMPAAoKKw9iHwBwAQAPAAoKKw9iHwBwAQAgAAQKWwHfhQAyAAAAAA==.Sonal:BAABNQAECn8XAAQhAAcKtgocXQAzAQAhAAcKtQkcXQAzAQAiAAUK6QezjgDIAAAkAAEKAAC9+AAfAAAAAA==.Soneca:BAAANQAECgMIAwAAAA==.Soter:BAABNQAECn8aAAMiAAgKXQ05NwBaAQAiAAgKXQ05NwBaAQAkAAMKtwRacwBNAAAAAA==.',
Sp='Spitzonit:BAAANQAECgUIBAAAAA==.',
Sq='Squeaph:BAABNQAECn8WAAIOAAkKLgztKwCaAQAOAAkKLgztKwCaAQAAAA==.',
St='Stararia:BAAANQADCggIDwAAAA==.Stelltrain:BAAANQABCgIIBAAAAA==.Stormiee:BAABNQAECn8pAAIYAAkKqxhSOAB+AgAYAAkKqxhSOAB+AgABNQAECggIEwAUAAAAAA==.Stormroid:BAAANQAECgUICQAAAA==.Sttorm:BAAANQADCgUIBQAAAA==.Styles:BAABNQAECn8rAAIKAAgKCgznwwA2AQAKAAgKCgznwwA2AQAAAA==.',
Su='Sudowoodont:BAAANQAECgUIBQAAAA==.Sugarontop:BAAANQADCgQIBAAAAA==.Sunmx:BAABNQAECn81AAMBAAoKPh9zKQAVAwABAAoKYB5zKQAVAwACAAYKyiBACwC/AQAAAA==.Superdark:BAAANQADCgIIAgAAAA==.Supersquidd:BAAANQADCgMIAwAAAA==.',
Sw='Swurve:BAEANQAECgQIBwAAAA==.Swurves:BAAANQAECgcIBwABNQAECggICAAUAAAAAA==.',
Sz='Szucs:BAAANQADCgMIAwAAAA==.',
['Sã']='Sãvãge:BAAANQADCgQIBAAAAA==.',
Ta='Tabiji:BAEANQAECggICAAAAA==.Tadpole:BAAANQAECgUIBwAAAA==.Taedrum:BAABNQAECn8aAAIkAAgKEwjXOQAfAQAkAAgKEwjXOQAfAQAAAA==.Taerror:BAAANQADCgIIAgAAAA==.Talegos:BAAANQAECgMJAwAAAA==.Talonfel:BAAANQADCgQIBAABNQAECgkJOQATACUjAA==.Taloning:BAAANQADCgYIBgABNQAECgkJOQATACUjAA==.Talonstryke:BAABNQAECn85AAITAAkKJSOfAwB2AwATAAkKJSOfAwB2AwAAAA==.Tauraxs:BAAANQADCgEIAQAAAA==.Tazrak:BAAANQAECgUIBAABNQAECgoKMAARAIoKAA==.',
Te='Teatoh:BAAANQADCgcIBwAAAA==.Teenjus:BAAANQABCgMIAwABNQAECgoKKwAEAC8ZAA==.Tenseiga:BAABNQAECn8lAAMKAAoKhxqgPABmAgAKAAkKhxqgPABmAgAEAAoK7QvSLAB2AQABNQAFFAUIDwAIAPMbAA==.Testsubjectz:BAACNQAFFH8FAAIBAAUKyBtIFQDuAAABAAUKyBtIFQDuAAA1AAQKfxYAAgEACQpTJgwDAHcDAAEACQpTJgwDAHcDAAAA.Tevers:BAAANQAECgEIAgAAAA==.',
Th='Thalantier:BAAANQADCgMIBgAAAA==.Thardal:BAABNQAECn8mAAMbAAoKDBBeCwC1AQARAAoKMg2RfADvAQAbAAkKEhBeCwC1AQAAAA==.Thebigshot:BAAANQAECgMIBQAAAA==.Theenforcer:BAACNQAFFH8OAAIKAAUK7QtuFgDKAAAKAAUK7QtuFgDKAAA1AAQKf2IAAgoACgqAE8JeAAUCAAoACgqAE8JeAAUCAAAA.Thegreekbeas:BAAANQADCgUIBQAAAA==.Theguyfurry:BAAANQAECgEIAQAAAA==.Theonepanda:BAAANQAECgUICAAAAA==.Thetzin:BAABNQAECn8eAAIVAAYKJwNkYQHxAAAVAAYKJwNkYQHxAAAAAA==.Theunite:BAAANQADCggICAAAAA==.Thickhobo:BAAANQADCgUICQAAAA==.Thidwick:BAABNQAECn87AAIPAAoKaCLPBAAKAwAPAAoKaCLPBAAKAwAAAA==.Thingtwø:BAABNQAECn8ZAAIhAAoKFB1DFQCVAgAhAAoKFB1DFQCVAgAAAA==.Thistle:BAAANQADCgYIDAABNQAECgkJIQAVADQMAA==.Thraggs:BAAANQADCgcICAAAAA==.Thunderfist:BAAANQADCggIBwAAAA==.',
Ti='Titanslay:BAAANQADCgEIAQAAAA==.Titø:BAAANQADCgYIDQABNQADCgcIBwAUAAAAAA==.',
Tm='Tmryuki:BAAANQAECggICgAAAA==.',
To='Tokadin:BAAANQAECgIIAgAAAA==.Tomorrow:BAAANQAECgYICgAAAA==.Topzee:BAAANQAECgQIBQAAAA==.Totalljoe:BAABNQAECn8WAAIKAAkKURKxgQC0AQAKAAkKURKxgQC0AQAAAA==.Totoo:BAABNQAFFH8HAAIMAAcKDgB6FwAhAAAMAAcKDgB6FwAhAAAAAA==.Touchmablade:BAAANQAECgUIBQAAAA==.',
Tr='Traedarra:BAAANQADCgIIAgAAAA==.Tralis:BAEANQADCggIDgABNQAECggICAAUAAAAAA==.Tranarra:BAABNQAECn9wAAIRAAoKrh4UFgC9AgARAAoKrh4UFgC9AgAAAA==.Traylo:BAABNQAECn8uAAILAAoKjxJOUgASAgALAAoKjxJOUgASAgAAAA==.',
Tv='Tvak:BAABNQAECn8ZAAIKAAcKcxfjtAC1AQAKAAcKcxfjtAC1AQAAAA==.',
Tw='Twistedsham:BAAANQAECggICQAAAA==.Twopump:BAABNQAECn83AAIKAAoKYwhWvwA+AQAKAAoKYwhWvwA+AQAAAA==.',
['Tó']='Tónka:BAAANQADCgcIBwAAAA==.',
Ul='Ulhae:BAAANQABCgQIBAAAAA==.Ulinova:BAABNQAECn8VAAIoAAcKrg8QBQApAQAoAAcKrg8QBQApAQAAAA==.',
Um='Umbressa:BAAANQADCgMIAwABNQAECgoKNgALAAkcAA==.Umbryx:BAAANQADCgIIAgABNQAECgoKMAARAIoKAA==.',
Un='Unholly:BAAANQAECgIJAwAAAA==.',
Ur='Uroro:BAACNQAFFH8IAAMYAAUKfhJmFQD0AAAYAAUKfhJmFQD0AAAXAAEK1QUpCQBEAAA1AAQKfzYAAxgACgo1Ik0YABIDABgACgo1Ik0YABIDABIAAQoAAONCASwAAAE1AAUUBQgSAAIAqh4A.',
Uu='Uu:BAAANQABCgIIAgAAAA==.',
Va='Vaiden:BAAANQABCgEIAQAAAA==.Vainqueur:BAABNQAECn8vAAIdAAoK6xt4BACAAgAdAAoK6xt4BACAAgAAAA==.Valienni:BAAANQAECgEIAQAAAA==.Vanderdemon:BAAANQADCgMIAwAAAA==.Vanderlight:BAAANQADCgUJCQAAAA==.Vandernum:BAAANQAECggICAAAAA==.Vandersus:BAAANQADCggIBQAAAA==.Varm:BAAANQADCggICAAAAA==.',
Ve='Velakai:BAAANQABCgQIBAAAAA==.Verlasky:BAAANQAECggICQABNQAECgoKOAAgAAgPAA==.Vervaeda:BAAANQADCgQIBAAAAA==.Verymelon:BAAANQAECgQIBgABNQAFFAQIBwASAFYOAA==.Vestele:BAAANQADCggIDwAAAA==.',
Vg='Vgx:BAABNQAECn8xAAIhAAkKJRBJRABxAQAhAAkKJRBJRABxAQAAAA==.',
Vi='Vielitre:BAAANQAECgMIAwAAAA==.Vigossfel:BAAANQADCgMIBwAAAA==.Viintage:BAABNQAECn80AAIVAAoKCBUuWgD2AQAVAAoKCBUuWgD2AQAAAA==.Vishouspayne:BAABNQAECn8XAAILAAYKFwaO9gCqAAALAAYKFwaO9gCqAAAAAA==.',
Vo='Voidshank:BAAANQAECgEIAgAAAA==.Vorath:BAAANQADCgQIBAAAAA==.',
Vy='Vyolence:BAAANQAECgQIBAABNQAECgoKMgAHAIQcAA==.',
['Vä']='Väelün:BAABNQAECn8mAAMNAAgKFBE5KABAAQANAAgKFBE5KABAAQAOAAEKawTsmwAnAAAAAA==.',
['Vÿ']='Vÿ:BAABNQAECn8dAAILAAcKRwglvAAfAQALAAcKRwglvAAfAQAAAA==.',
Wa='Wachoosh:BAAANQAECgUIBwAAAA==.Waidmanns:BAABNQAECn82AAMLAAoKCRzAJwD5AgALAAoKCRzAJwD5AgApAAMKuwkNDwB3AAAAAA==.Wakinbakin:BAAANQAECgQIBAAAAA==.Walmartstaff:BAAANQADCgUIBQAAAA==.Warfable:BAAANQADCgIIAgAAAA==.',
Wg='Wgnmd:BAAANQAECgQIBQAAAA==.',
Wh='Wham:BAAANQAECgIIAwAAAA==.Whatsaggro:BAABNQAECn8lAAIkAAgKhwk9aABwAQAkAAgKhwk9aABwAQABNQAECgkJFgAKAFESAA==.Whatyamean:BAABNQAECn8bAAMYAAkK7AXtjwDyAAAYAAkK7AXtjwDyAAASAAIKpwEB8wA1AAAAAA==.Whiteeyedemo:BAAANQADCgYIBgAAAA==.Whoangry:BAABNQAECn8kAAMMAAkKLhN9SwC4AQAMAAgKGhB9SwC4AQAmAAkKgQ+6RQCwAQAAAA==.Whomonk:BAAANQAECgIIBAAAAA==.',
Wi='Willowknight:BAAANQADCgYICgAAAA==.Wimdy:BAAANQADCgMIAwAAAA==.Winterknight:BAAANQADCgUICwAAAA==.',
Wr='Wrenn:BAAANQAECgcICAAAAA==.Wrongname:BAAANQAECgUIBwAAAA==.',
Wu='Wumba:BAAANQAECgMIAwAAAA==.',
Xa='Xanthe:BAAANQADCggIBwAAAA==.',
Xf='Xfloki:BAAANQADCgQIBAAAAA==.',
['Xß']='Xß:BAAANQADCgIJBAAAAA==.',
Ya='Yakpriest:BAAANQADCgcIDAAAAA==.Yawg:BAEANQADCgYIBgABNQAECgoKQQALAPsfAA==.',
Yd='Ydgktt:BAAANQADCgMIBAAAAA==.',
Yn='Ynhük:BAAANQADCgMIAwAAAA==.',
Yo='Yogsothoth:BAEBNQAECn9BAAILAAoK+x+1HgC5AgALAAoK+x+1HgC5AgAAAA==.',
Yr='Yrdenal:BAAANQADCgcICQAAAA==.',
Yu='Yugalipdeez:BAAANQAECgEIAgAAAA==.Yulian:BAABNQAECn8VAAIRAAYKrwzcpQD2AAARAAYKrwzcpQD2AAAAAA==.',
Za='Zaartyn:BAABNQAECn86AAIRAAoKTiKjEwA+AwARAAoKTiKjEwA+AwAAAA==.Zaater:BAAANQAECggICQAAAA==.Zalin:BAAANQAECgEIAQABNQAECgoKJgAbAAwQAA==.Zanki:BAAANQAECgUICwAAAA==.',
Ze='Zeebeth:BAABNQAECn8YAAILAAkKfw8wjQDwAQALAAkKfw8wjQDwAQAAAA==.Zefi:BAAANQAECgcIAgAAAA==.Zellek:BAAANQADCgYIBgAAAA==.Zenbu:BAAANQADCgIIAgAAAA==.Zeroasy:BAAANQADCgIIAgABNQAECgoKNwAiAPIjAA==.Zerokai:BAAANQAECggICgAAAA==.Zeztz:BAAANQAECgcIDAAAAA==.',
Zo='Zomlo:BAAANQAECgQIBQAAAA==.Zooli:BAAANQADCggICAAAAA==.Zorosenpai:BAAANQADCgcIEQABNQAECggIIgAhAJ8KAA==.',
Zu='Zuggernaught:BAAANQAECgUIDAABNQAECgcIDQAUAAAAAA==.',
Zy='Zynokyno:BAAANQADCgYIBgAAAA==.',
['Át']='Átomic:BAAANQADCgUIAwAAAA==.',
['Ân']='Ânimosity:BAAANQADCgIIAgAAAA==.',
['Âr']='Ârtemis:BAAANQAECgQIBAABNQAFFAUIDwAIAPMbAA==.',
['Ís']='Ísvala:BAAANQADCgYIBgAAAA==.',
['ßu']='ßuzzibee:BAABNQAECn8WAAIKAAkKlRTwxwCMAQAKAAkKlRTwxwCMAQABNQAECgoKJwAOADIaAA==.',
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
