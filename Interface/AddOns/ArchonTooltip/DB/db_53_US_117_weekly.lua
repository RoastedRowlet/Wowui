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

local lookup = {'Warrior-Arms','Warrior-Fury','Druid-Restoration','Paladin-Protection','Monk-Windwalker','Priest-Holy','Priest-Shadow','DemonHunter-Vengeance','Unknown-Unknown','Paladin-Holy','Paladin-Retribution','Hunter-BeastMastery','Rogue-Subtlety','DemonHunter-Devourer','DemonHunter-Havoc','Druid-Guardian','Druid-Feral','Warlock-Demonology','Shaman-Elemental','Monk-Mistweaver','Mage-Arcane','Priest-Discipline','Shaman-Enhancement','Shaman-Restoration','Hunter-Marksmanship','Warlock-Destruction','Warlock-Affliction','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Mage-Frost','Druid-Balance','DeathKnight-Frost','DeathKnight-Blood','Monk-Brewmaster','DeathKnight-Unholy','Warrior-Protection','Rogue-Assassination','Mage-Fire','Rogue-Outlaw','Hunter-Survival',}
local provider = {region='US',realm='Hakkar',name='US',type='weekly',zone=53,date='2026-11-17',data={Ac='Aceshaman:BAAANQADCgIIAgAAAA==.Acheros:BAAANQADCgMIAwAAAA==.Actionfigure:BAACNQAFFH8KAAIBAAQKyCCkFQB7AQABAAQKyCCkFQB7AQA1AAQKfzUAAwIACgqCJM8FAHMCAAEACgonH2A3AOYCAAIACAptJM8FAHMCAAAA.',
Ad='Adielia:BAABNQAECn8oAAIDAAoKOBt9FgBqAgADAAoKOBt9FgBqAgAAAA==.Adurzin:BAAANQADCgIIAgAAAA==.',
Ae='Aeralina:BAAANQADCgUJBQAAAA==.Aeri:BAAANQADCgIIAwAAAA==.Aevalaana:BAAANQAECgYICQAAAA==.',
Ag='Agiermodinn:BAAANQADCgYICgAAAA==.',
Ah='Ahnho:BAAANQADCggICgAAAA==.',
Ai='Aidandrius:BAAANQADCgMIAwAAAA==.Aimeeleigh:BAAANQAECgUICAABNQAECgoKNAAEAPAZAA==.Airflash:BAACNQAFFH8MAAIFAAUKEx4tCQBFAQAFAAUKEx4tCQBFAQA1AAQKfzkAAgUACAo/JasHAFQDAAUACAo/JasHAFQDAAAA.Aiøn:BAAANQADCgcIBwAAAA==.',
Ak='Akutagawa:BAABNQAECn8rAAMGAAkKoxr9KQCjAgAGAAkKoxr9KQCjAgAHAAEKAAC2dwAAAAABNQAFFAUIDwAIAPMbAA==.',
Al='Alexious:BAACNQAFFH8VAAIEAAYKASBXAwBRAQAEAAYKASBXAwBRAQA1AAQKfzUAAgQACgqFIk4HAC4DAAQACgqFIk4HAC4DAAAA.Aloonarn:BAAANQAECgYIDQABNQAECgcIDwAJAAAAAA==.Alopix:BAAANQAECggIDgAAAA==.Alulla:BAACNQAFFH8SAAMCAAUKqh7rAQD0AAABAAQKqh5tFwBnAQACAAMKwRjrAQD0AAA1AAQKfyIAAwIACgrzIa0KAB0CAAEACQoDISJJAK4CAAIABwoTIq0KAB0CAAAA.Alunira:BAABNQAECn87AAMKAAoKnh/gGAAVAwAKAAoKnh/gGAAVAwALAAYKbhYTzQCBAQAAAA==.',
Am='Amberrfrost:BAAANQAECgQICAAAAA==.Amize:BAAANQADCgYIBgAAAA==.Ampz:BAAANQAECgQIBgAAAA==.',
An='Anabee:BAAANQADCggIDgAAAA==.Angelicshy:BAAANQADCgQIBAAAAA==.Angryhtr:BAABNQAECn8UAAIMAAcKGhkydgAjAgAMAAcKGhkydgAjAgAAAA==.Angryshh:BAAANQAECggIDQAAAA==.Angrywar:BAABNQAECn8bAAIBAAgKHxL9nADUAQABAAgKHxL9nADUAQAAAA==.Anharon:BAAANQADCgcICgAAAA==.Ansatz:BAAANQAECgEIAwABNQAECgoKNgAMAAkcAA==.',
Ap='Apokalypto:BAAANQAECgUIBAAAAA==.',
Ar='Arbiterbinky:BAAANQADCgUIBQAAAA==.Ardå:BAAANQADCgEIAQAAAA==.Argangus:BAAANQADCgYIDwAAAA==.Aridon:BAAANQAECgEIAQAAAA==.Arrowganz:BAAANQADCgYIBgAAAA==.Arthan:BAAANQAECgMIAwAAAA==.Arthannix:BAAANQADCgYICgAAAA==.',
As='Assine:BAAANQAECgEIAgABNQAFFAcIBwANAA4AAA==.Astanis:BAAANQAECgcICgAAAA==.Asteriia:BAABNQAECn8kAAIOAAoKAQrKJwBbAQAOAAoKAQrKJwBbAQAAAA==.Astralyn:BAAANQAECgEIAQAAAA==.',
Au='Augito:BAAANQABCgIIAgAAAA==.',
Av='Averettara:BAAANQAECgIIBgABNQAECgkJGAALAC8TAA==.',
Az='Azarazan:BAAANQADCgYIDgAAAA==.Azka:BAABNQAECn8tAAILAAoKDSDuLwAKAwALAAoKDSDuLwAKAwAAAA==.Azkadk:BAAANQADCgYIBgAAAA==.',
Ba='Babybilly:BAABNQAECn80AAMEAAoK8Bk+EQAXAgAEAAoK8Bk+EQAXAgALAAMKkAOgcAFtAAAAAA==.Baelmon:BAAANQAECgQIBQAAAA==.Baludis:BAAANQADCgcIEQAAAA==.Bamff:BAAANQAECgUICQAAAA==.Bamfpally:BAAANQADCggICAAAAA==.Barreack:BAAANQADCgYICAAAAA==.Bast:BAACNQAFFH8PAAIIAAUK8xs8AgAuAQAIAAUK8xs8AgAuAQA1AAQKfz8AAwgACgpoJecAAFkDAAgACgpoJecAAFkDAA8ABQpFE2pSAEoBAAAA.Basthara:BAABNQAECn81AAMQAAoKGSM2BAAlAwAQAAoKGSM2BAAlAwARAAEKVAIbUwAGAAABNQAFFAUIDwAIAPMbAA==.',
Be='Beckianslip:BAAANQADCgUIBQAAAA==.Belphegor:BAAANQAECgYIBQABNQAECgoKNAASAIoKAA==.Benif:BAACNQAFFH8PAAIBAAcKQh26DwC7AQABAAcKQh26DwC7AQA1AAQKfzsAAgEACgrvJf8IAKwDAAEACgrvJf8IAKwDAAAA.Benjaquel:BAAANQADCgQIBAAAAA==.Bertorod:BAABNQAECn8YAAITAAkKqxUfWAAbAgATAAkKqxUfWAAbAgAAAA==.',
Bi='Bigbitehotdo:BAABNQAECn88AAMFAAoKZB+MDgD3AgAFAAoKZB+MDgD3AgAUAAEK3wHaVAAgAAAAAA==.Bighoney:BAAANQAECgIIAQAAAA==.Bigtommybuns:BAAANQADCgUIBQAAAA==.Binkyfiasco:BAAANQADCggIDgAAAA==.Binny:BAAANQADCgYIBgAAAA==.Birdiewordie:BAAANQADCgQIBAAAAA==.',
Bl='Bloodeie:BAAANQADCgQIBAAAAA==.Bloodstoned:BAABNQAECn8XAAIOAAcKxgbRMwD7AAAOAAcKxgbRMwD7AAAAAA==.Blueboy:BAABNQAECn8eAAIHAAoKJgyIHQClAQAHAAoKJgyIHQClAQAAAA==.Bluechewman:BAAANQADCgQIBAAAAA==.',
Bo='Boffadz:BAAANQAECggIEAAAAA==.Bonewand:BAAANQAECgEIAQAAAA==.Bonewrath:BAAANQABCgIIAgAAAA==.Boogat:BAAANQAECgUIEgAAAA==.Boomblessed:BAAANQAECgUIBQAAAA==.Boomkin:BAAANQAECgIIAQAAAA==.Bovillus:BAAANQAECgYIDgAAAA==.Bowflex:BAAANQADCgQIBAAAAA==.',
Br='Braugorlle:BAAANQAECgcICQABNQAFFAUIFAATAI0dAA==.Breadscrumb:BAAANQADCgUJBQAAAA==.Bridrystina:BAAANQADCgQIBAAAAA==.Brixlo:BAAANQADCgEIAQABNQADCgcIBwAJAAAAAA==.Brokenfinger:BAAANQADCgIIAgAAAA==.',
Bu='Buffmuffin:BAAANQAECgIIAgAAAA==.Burblbiblr:BAAANQADCgQJBAAAAA==.Bustrdugles:BAAANQADCgUIBQAAAA==.',
Bw='Bwazakki:BAAANQADCgMIAwAAAA==.Bwr:BAAANQADCgMIAwAAAA==.',
['Bü']='Bübbawrap:BAAANQAECgQICAAAAA==.',
Ca='Cambrier:BAACNQAFFH8HAAIBAAIKJQ+EKgCEAAABAAIKJQ+EKgCEAAA1AAQKf1AAAwEACgpqIrQSAAkDAAEACgr0IbQSAAkDAAIACAqiIAgFANsCAAAA.Cameraop:BAABNQAECn8XAAIVAAcKKwj2EgFtAQAVAAcKKwj2EgFtAQAAAA==.Candyapples:BAAANQAECgEIAQAAAA==.Canias:BAAANQADCgQIBAABNQAECggIEAAJAAAAAA==.Capnsoap:BAAANQADCgYIBgABNQABCgEIAQAJAAAAAA==.Capriestsun:BAAANQAECggICgAAAA==.Cardinal:BAAANQAECgIIAQAAAA==.Carynden:BAAANQAECgUIBQAAAA==.Castbo:BAAANQAECgcIEAABNQAFFAYIFQAWAB0RAA==.',
Ce='Celilinia:BAAANQAECgIIAgAAAA==.Cellesstia:BAAANQADCgMIBQABNQAECgkJHgADAIkYAA==.',
Ch='Chalada:BAAANQADCgEIAQABNQAFFAcIBwANAA4AAA==.Chalastorm:BAAANQAECggIBQABNQAFFAcIBwANAA4AAA==.Charknight:BAAANQADCgUIBQAAAA==.Chatdodu:BAAANQAECgIIAgAAAA==.Chatnoir:BAABNQAECn8YAAIMAAkK7A4GegDIAQAMAAkK7A4GegDIAQAAAA==.Chestock:BAAANQAECgYIBgAAAA==.Chuggz:BAAANQAECgQIBgAAAA==.',
Cl='Clonetastic:BAAANQADCggICAAAAA==.Clumsycarl:BAAANQADCgIIAgAAAA==.',
Cm='Cmx:BAAANQADCgUIBQAAAA==.',
Co='Codith:BAAANQAECgQIBQAAAA==.Coldlock:BAAANQADCgQIBAAAAA==.Coraeze:BAAANQADCgEIAQAAAA==.',
Cp='Cptcrunch:BAABNQAECn8YAAMLAAgK+Q5UuQBfAQALAAcKCA9UuQBfAQAEAAQKvwrIRwCGAAABNQAECgkJLwATAP4cAA==.',
Cr='Crais:BAAANQAECgYIBgAAAA==.Creek:BAAANQABCgYIBgABNQAECgoKMAAPAIQgAA==.Critneyfears:BAAANQAECgIIAQABNQAECgIIAgAJAAAAAA==.Crnogorac:BAAANQAECggIAQAAAA==.Crotchgoblim:BAAANQAECgUIBQAAAA==.Crothic:BAAANQAECgIIAgAAAA==.Cryodormu:BAAANQAECgMJAwAAAA==.',
Cu='Cubo:BAAANQAECgEIAQAAAA==.Cuddlesworth:BAABNQAECn80AAISAAoKigqccACIAQASAAoKigqccACIAQAAAA==.',
Cw='Cwarr:BAAANQAECgIIAgABNQAFFAYICQAXANIOAA==.',
Cy='Cyrcee:BAAANQADCgUIBQABNQAECgkJHgADAIkYAA==.',
Da='Daddyluis:BAAANQADCggICwAAAA==.Dadstonks:BAAANQABCgYICAAAAA==.Dagoujiao:BAABNQAECn8ZAAMTAAoKVgtSYABmAQATAAoKVgtSYABmAQAYAAcKGg0ErwASAQAAAA==.Dameiyo:BAAANQAECggIEgAAAA==.Dandanh:BAAANQADCgMIAwAAAA==.Dangright:BAABNQAECn8aAAIZAAgKXwVBPgBgAQAZAAgKXwVBPgBgAQAAAA==.Dankbo:BAACNQAFFH8VAAMWAAYKHREfAgDVAAAGAAUKMhQiGAAyAQAWAAMK1ggfAgDVAAA1AAQKfz0AAxYACgr/IrMCAOQCABYACAq6ILMCAOQCAAYACgrbHvYlANMCAAAA.Danorac:BAABNQAECn8nAAIOAAoKGQ0dHQC9AQAOAAoKGQ0dHQC9AQAAAA==.Darkcoffee:BAABNQAECn8qAAIEAAcKDh5hEgAGAgAEAAcKDh5hEgAGAgAAAA==.Darkivie:BAAANQADCgYIBgABNQAECgkJHgALAGMFAA==.Datgoodtree:BAAANQADCgIIAgAAAA==.',
De='Deadashe:BAAANQADCgEIAQAAAA==.Demonicsword:BAAANQADCgQIBAAAAA==.Despondent:BAAANQADCggIFgAAAA==.Devilcrybaby:BAAANQAECgIIAgAAAA==.Devildj:BAAANQAECggIEwAAAA==.Dezadian:BAABNQAECn8iAAILAAgKJwVlAwHkAAALAAgKJwVlAwHkAAAAAA==.',
Dh='Dhampyra:BAABNQAECn8YAAMHAAgKOBOFJQADAgAHAAgKOBOFJQADAgAGAAQKDRfhpwDnAAAAAA==.',
Di='Dietmountdew:BAAANQAECgQIBAAAAA==.Dimitrios:BAAANQAECgcICQAAAA==.Disolve:BAABNQAECn8gAAQSAAkKFBGueAD5AQASAAkKog2ueAD5AQAaAAIK9hY7UgCIAAAbAAEKAABKJQBZAAAAAA==.Dixxonciderr:BAACNQAFFH8IAAIcAAUKuAeKEgC4AAAcAAUKuAeKEgC4AAA1AAQKf0kABBwACgohHo8JAAoDABwACgohHo8JAAoDAB0ABwqLD8UgAE0BAB4AAgpZFf0dAHIAAAAA.',
Dm='Dmdedifudo:BAAANQADCgQIBQAAAA==.Dmoe:BAAANQAECgYICwAAAA==.',
Do='Docutratties:BAAANQAECgMIAgABNQAECgoKNAASAIoKAA==.Doji:BAAANQADCgEIAQAAAA==.Doublesixes:BAAANQADCggIEwAAAA==.',
Dq='Dqe:BAAANQAECgEIAQAAAA==.',
Dr='Drac:BAAANQADCgMIAwAAAA==.Dragonara:BAAANQADCggICAAAAA==.Draskion:BAAANQADCgcIBwAAAA==.Dribby:BAAANQAECgQIBAABNQAECggIDQAJAAAAAA==.',
Du='Duhästmich:BAAANQADCgYIBgABNQAECgkJGAALAC8TAA==.Duplicate:BAACNQAFFH8PAAMfAAQKjBQTCQCOAAAVAAQKjBTELQC8AAAfAAIKGA8TCQCOAAA1AAQKfzAAAxUACgqHHcU9AFQCABUACgqHHcU9AFQCAB8AAQonG6BBAEEAAAAA.Dustdruid:BAACNQAFFH8FAAIgAAMKdxCdGgDNAAAgAAMKdxCdGgDNAAA1AAQKfzYAAiAACQpLIDAXAFgCACAACQpLIDAXAFgCAAAA.Dustlock:BAAANQAECggIEAAAAA==.Dustmage:BAAANQADCggIEAAAAA==.Dustsham:BAAANQAECgEIAQAAAA==.',
Dw='Dwarr:BAAANQAECgYICAAAAA==.',
Dy='Dysnomia:BAAANQAECgIIAgAAAA==.',
Dz='Dzoolock:BAAANQAECgEIAQAAAA==.',
['Dó']='Dóru:BAAANQADCgYIBwAAAA==.',
Ee='Eender:BAAANQAECgEIAQAAAA==.',
Eg='Eggrolls:BAABNQAECn9EAAIBAAoKNB4AIwAsAwABAAoKNB4AIwAsAwAAAA==.',
El='Eldenmorden:BAAANQADCgYIBwAAAA==.Eleshmelly:BAAANQADCgcIFgAAAA==.Elfrafa:BAAANQADCgUIBgAAAA==.Ellayna:BAAANQADCgEIAQAAAA==.Ellcrys:BAABNQAECn9LAAIDAAoKMB3jDAD7AgADAAoKMB3jDAD7AgAAAA==.Elletta:BAAANQAECgIIAQAAAA==.Elrae:BAAANQAECgYIBgAAAA==.',
Ep='Epoptes:BAAANQAECgYIDAABNQAECgoKMgAEAJsMAA==.',
Eq='Eqo:BAABNQAECn8dAAMGAAkKERI8eQCvAQAGAAkKERI8eQCvAQAHAAEKxQl3dAA9AAAAAA==.',
Er='Erisian:BAAANQAECgUIBQAAAA==.Erkêios:BAABNQAECn8hAAIhAAkKtBWTNQDNAQAhAAkKtBWTNQDNAQAAAA==.Ersande:BAAANQAECgQIBgAAAA==.Ertz:BAAANQADCggICQAAAA==.',
Es='Escherichia:BAAANQAECgEJAQAAAA==.Estheban:BAABNQAECn8nAAQdAAoK+x3TBQBaAgAdAAoK+x3TBQBaAgAeAAMKFRa/GwBDAAAcAAEKQAtiUAAtAAAAAA==.',
Ev='Evengelist:BAABNQAECn8eAAMWAAoK1RByEAAiAQAGAAkK9w1ZVQDmAQAWAAUKdRFyEAAiAQAAAA==.',
Ex='Exolar:BAAANQADCggIDwAAAA==.',
Fa='Face:BAAANQAECgcIDAAAAA==.Fairgrim:BAAANQAECgQIBAAAAA==.Falin:BAACNQAFFH8FAAILAAIKLgnEJgCBAAALAAIKLgnEJgCBAAA1AAQKf1EAAgsACgqqGzBDAMsCAAsACgqqGzBDAMsCAAAA.Faqueuedark:BAABNQAECn8kAAISAAoKyR/yFgDEAgASAAoKyR/yFgDEAgABNQAFFAQIDAAIAMENAA==.Faqueueeight:BAACNQAFFH8MAAMIAAQKwQ2CAwCUAAAIAAQKwQ2CAwCUAAAPAAEKvAOUIAAxAAA1AAQKf1UAAwgACgpoISwGAEgCAA8ACgq0HxoSAA4DAAgACgp1GiwGAEgCAAAA.Fatalyeeyee:BAAANQAECggIEQABNQAFFAQICAASADIFAA==.Fatsloth:BAAANQAECgYICAAAAA==.Fatébringer:BAAANQADCgYIDAABNQAECgEIAQAJAAAAAA==.Faulted:BAAANQADCgUIBQAAAA==.',
Fe='Feironos:BAAANQADCggICAAAAA==.Felcookies:BAAANQAECgYIEAAAAA==.Ferrick:BAAANQAECgIIAgAAAA==.',
Fi='Fiist:BAAANQAECggICAAAAA==.Fimtastic:BAABNQAECn8oAAIYAAkK8RNSZACJAQAYAAkK8RNSZACJAQAAAA==.Finasy:BAABNQAECn83AAMiAAoK8iM1GwDVAgAiAAoK8iM1GwDVAgAhAAgKtxRgRACIAQAAAA==.Finbezy:BAAANQAECgQIAwAAAA==.Finnicka:BAAANQAECgEIAQAAAA==.Firen:BAAANQADCgcIFAAAAA==.Fireouch:BAAANQABCgIIAwAAAA==.Fistymisty:BAABNQAECn8cAAIjAAkKix98BAAvAwAjAAkKix98BAAvAwAAAA==.Fizeecian:BAAANQAECgQIBQAAAA==.',
Fl='Flaynpray:BAAANQADCgEIAQAAAA==.Fluffenstein:BAABNQAFFH8IAAIBAAQKmALSJgCXAAABAAQKmALSJgCXAAAAAA==.',
Fo='Foxrawruwu:BAABNQAECn8WAAISAAgKqRqZNgCxAgASAAgKqRqZNgCxAgAAAA==.',
Fr='Frakk:BAAANQAECggIAQAAAA==.Freezegarr:BAACNQAFFH8QAAIVAAcKCBgQDgCeAQAVAAcKCBgQDgCeAQA1AAQKfzYAAhUACgrpIKAWAO0CABUACgrpIKAWAO0CAAAA.Frey:BAAANQADCgIIAgAAAA==.Frostgrave:BAAANQADCgEIAQAAAA==.Frostya:BAAANQADCgYIBgAAAA==.Frozzty:BAAANQAECgIIAgAAAA==.',
Fu='Fujibayashi:BAAANQAECgcIEgAAAA==.Furearia:BAAANQABCgcICQAAAA==.Furrybowner:BAAANQAECggIDwAAAA==.',
Ga='Galeriel:BAACNQAFFH8WAAIGAAYKGB7bDgC6AQAGAAYKGB7bDgC6AQA1AAQKf08AAgYACgoZJj8CACEEAAYACgoZJj8CACEEAAAA.Galileo:BAAANQAECgIIAgAAAA==.Gallethline:BAAANQAECgIIBwAAAA==.Ganjgotti:BAAANQADCgYICQAAAA==.Garault:BAAANQAECggIEAAAAA==.Gavered:BAAANQADCgMIBQAAAA==.',
Ge='Gekoni:BAABNQAECn8cAAIEAAkKRwf4KwAXAQAEAAkKRwf4KwAXAQAAAA==.Geonon:BAAANQADCggICAAAAA==.Geotracker:BAABNQAECn8fAAIMAAkKyg6IigCiAQAMAAkKyg6IigCiAQABNQADCggICAAJAAAAAA==.',
Gh='Ghorros:BAAANQADCgMIAwAAAA==.',
Gi='Gilgahmesh:BAABNQAECn8fAAIBAAoK7BB4eACbAQABAAoK7BB4eACbAQABNQAECgoKQAAKAFQgAA==.',
Gl='Glowpwr:BAAANQADCgcIBwAAAA==.',
Go='Golruck:BAAANQAECggICgABNQAECgkJFQAMAA4XAA==.Goolgame:BAACNQAFFH8UAAMTAAUKjR1lDACmAQATAAUKjR1lDACmAQAYAAMKfhveFgDwAAA1AAQKfywAAxMACgooIMo8AIICABMACApAIco8AIICABgABQq9G2SHAHgBAAAA.Goonthergg:BAAANQADCgYIBgAAAA==.Goothix:BAAANQADCgcJCAAAAA==.Gothmog:BAAANQADCgIIAgAAAA==.',
Gr='Grammarg:BAAANQADCgMIAwAAAA==.Grezzert:BAAANQADCgMIAwAAAA==.Grirr:BAAANQAECgIIBAAAAA==.Grothin:BAACNQAFFH8KAAIYAAQKQBEKFQAUAQAYAAQKQBEKFQAUAQA1AAQKfzcAAhgACgqvHJcdAM0CABgACgqvHJcdAM0CAAAA.Gruldag:BAACNQAFFH8KAAIVAAQK7hN3KgDOAAAVAAQK7hN3KgDOAAA1AAQKfzkAAhUACgrXHCZdAMUCABUACgrXHCZdAMUCAAAA.Grullander:BAABNQAECn87AAIYAAoKkBNDVQC+AQAYAAoKkBNDVQC+AQAAAA==.',
Gu='Guiguiie:BAAANQADCggJEAAAAA==.',
Gw='Gwyndolynn:BAAANQADCgQIBQAAAA==.',
Ha='Hadalyon:BAAANQADCgYICgAAAA==.Haeheia:BAAANQADCgIIAgAAAA==.Haeldir:BAAANQADCgYIBQAAAA==.Hailey:BAEANQAECggIEwABNQAFFAcIDAAKAIoLAA==.Halter:BAAANQAECgIIAgAAAA==.Hapló:BAAANQABCgEIAQAAAA==.Haratvy:BAAANQAECgEIAQAAAA==.Hazzurd:BAABNQAECn8cAAIMAAoKuBC8cwApAgAMAAoKuBC8cwApAgAAAA==.',
He='Header:BAACNQAFFH8bAAIZAAgK8xqiBQACAgAZAAgK8xqiBQACAgA1AAQKfzAAAxkACgrlHmIPAEYCABkACgrlHmIPAEYCAAwABQrhCjP9AAoBAAAA.Healsorz:BAAANQADCgcIBwAAAA==.Heersbeest:BAAANQABCggIDgAAAA==.Helane:BAAANQADCgUIBQAAAA==.Herkharu:BAAANQADCgcIBwAAAA==.Hermionee:BAABNQAECn85AAMVAAoK8hH3ogBeAQAVAAkKWA33ogBeAQAfAAMKUhZUJQCyAAAAAA==.Hetu:BAAANQABCgUIBAAAAA==.',
Hi='Hide:BAAANQAECgEIAQAAAA==.Himjongun:BAABNQAECn8mAAMPAAoKGhgzLACwAQAPAAkKGhgzLACwAQAOAAEKAADddQAiAAAAAA==.',
Ho='Hollieheifer:BAAANQADCgEIAQAAAA==.Holya:BAAANQADCgEIAQABNQAFFAcIBwANAA4AAA==.Holycowe:BAAANQAECgcIDQAAAA==.Holykoi:BAABNQAECn9QAAIGAAoKthLkPQBDAgAGAAoKthLkPQBDAgAAAA==.',
Hr='Hroarr:BAABNQAECn8ZAAIiAAoKRSKTDgA7AwAiAAoKRSKTDgA7AwABNQAFFAcIEAAVAAgYAA==.',
Hu='Humancarnage:BAAANQADCgYIBwAAAA==.Huuh:BAAANQAECgMIAwAAAA==.',
Hy='Hypaexia:BAAANQADCgIIAgAAAA==.',
['Hà']='Hàvoc:BAAANQADCggIDQAAAA==.',
['Hé']='Héboric:BAABNQAECn8vAAIKAAoKLR9kFAAXAwAKAAoKLR9kFAAXAwAAAA==.Hélbrecht:BAAANQAECgMIAwAAAA==.',
['Hÿ']='Hÿbrìd:BAAANQAECgYIDwAAAA==.',
Ia='Iamwho:BAAANQAECggICAAAAA==.Iatros:BAABNQAECn8yAAMEAAoKmwzSHwBwAQAEAAoKlgzSHwBwAQALAAcKMgWWHgG8AAAAAA==.',
Id='Idkno:BAAANQAECgIIAQAAAA==.',
Ik='Ikara:BAAANQADCggICAABNQAECgoKJgAbAAwQAA==.Ikodiwa:BAAANQADCgUIBQAAAA==.',
Il='Ilrion:BAAANQABCgIIAgAAAA==.',
Im='Imjustsaiyan:BAAANQADCgIIAgAAAA==.',
In='Indravax:BAABNQAECn8cAAISAAkKQRSdeQD3AQASAAkKQRSdeQD3AQAAAA==.',
Io='Iorin:BAAANQADCgcIBwABNQAFFAQIDAAPAEYCAA==.',
It='Itwasntmebru:BAAANQADCgYIFAAAAA==.',
Iv='Ivantis:BAAANQADCgYIFwAAAA==.Ivie:BAABNQAECn8eAAIDAAkKiRgMFACLAgADAAkKiRgMFACLAgAAAA==.',
Iw='Iwonabhornee:BAAANQAECgEIAQAAAA==.',
Ja='Jaholypriest:BAACNQAFFH8KAAIGAAQKVBLUHAAMAQAGAAQKVBLUHAAMAQA1AAQKfyAAAgYACgpmFf5WAB4CAAYACgpmFf5WAB4CAAAA.Janjor:BAAANQAECgYICAAAAA==.Janjy:BAAANQADCgcIBwAAAA==.Jaypiea:BAABNQAECn8iAAMeAAkKTBUCCAAgAgAeAAgKTBUCCAAgAgAdAAgK8xC2FwDOAQAAAA==.',
Je='Jergall:BAAANQADCgUIBQAAAA==.Jettian:BAABNQAECn8ZAAIkAAgKJAxeNwA+AQAkAAgKJAxeNwA+AQAAAA==.',
Ji='Jibz:BAAANQADCgEIAQAAAA==.',
Jj='Jjdruid:BAAANQAECgIIAgAAAA==.',
Jo='Johnathon:BAAANQAECgMIAwABNQAECgMIBAAJAAAAAA==.Jollygreene:BAAANQAECgEIAgAAAA==.Jonestu:BAAANQAECgQIBgAAAA==.Joyina:BAAANQADCgYIBgAAAA==.',
Jp='Jpgigacat:BAAANQAECgYICAAAAA==.Jpgigademon:BAAANQAECgMIBAAAAA==.Jpgigawolf:BAAANQAECggIEQAAAA==.',
Ju='Justakatt:BAAANQADCgIIAgAAAA==.Justicasia:BAAANQADCgQIBAABNQADCgYIBgAJAAAAAA==.',
Ka='Kadinsky:BAAANQADCgUIBQAAAA==.Kalivan:BAAANQADCgYIBwAAAA==.Kankimasamu:BAAANQADCgQIBAAAAA==.Karametra:BAABNQAECn8bAAITAAgKuRVaPwDXAQATAAgKuRVaPwDXAQAAAA==.Karlldun:BAAANQAECgcIDQAAAA==.Kasmir:BAABNQAECn8tAAMSAAkK8g61bQCQAQASAAkK8g61bQCQAQAaAAEKLggUfQAwAAAAAA==.Kasnfriends:BAAANQADCgUIBQABNQAECgkJLQASAPIOAA==.',
Ke='Kevv:BAACNQAFFH8PAAITAAYKIQOwFQDBAAATAAYKIQOwFQDBAAA1AAQKfzsAAxMACgqNHXAXAK8CABMACgqNHXAXAK8CABcAAQoAAPI7ABkAAAAA.Keyniron:BAABNQAECn/rAAILAAkK4CXIBQBpAwALAAkK4CXIBQBpAwAAAA==.',
Kh='Khogent:BAAANQADCgQIBAAAAA==.Khonsu:BAAANQAECgQIBAABNQAECgcIDQAJAAAAAA==.Khrover:BAAANQADCgUIBQAAAA==.Khyle:BAAANQADCgYIBwAAAA==.',
Ki='Kijanajr:BAAANQADCgMIAgAAAA==.Killaarrow:BAABNQAECn9EAAIMAAoKSAkafQDBAQAMAAoKSAkafQDBAQAAAA==.Kiloton:BAAANQAECgUIBwAAAA==.Kindleos:BAAANQAECgEIAQAAAA==.',
Kk='Kkpriest:BAAANQADCgEIAQAAAA==.',
Kl='Klay:BAAANQAECgYIDQAAAA==.',
Km='Kmarte:BAEANQAECgYIEAABNQAFFAMIAwAJAAAAAA==.Kmarti:BAEANQAFFAMIAwAAAA==.Kmartt:BAEBNQAECn8nAAILAAoKjhs1UgA2AgALAAoKjhs1UgA2AgABNQAFFAMIAwAJAAAAAA==.',
Ko='Kosmic:BAAANQADCgcICQABNQAECgoKOAAiAGcZAA==.Kosmicknight:BAABNQAECn84AAQiAAoKZxnSFQBcAgAiAAoKZxnSFQBcAgAkAAIKZgmdiAA1AAAhAAEKAAA4twAoAAAAAA==.',
Kr='Kraggers:BAAANQAECgYIDQAAAA==.Kraggory:BAAANQAECgIIAgAAAA==.Kraggoryqt:BAABNQAECn8aAAILAAcK7RuAcgDqAQALAAcK7RuAcgDqAQAAAA==.Kraggoryx:BAAANQAECgEIAQAAAA==.Krunclez:BAAANQAECggIEAAAAA==.Kryesta:BAACNQAFFH8FAAIYAAQK/hKfFQAMAQAYAAQK/hKfFQAMAQA1AAQKf00AAhgACgpmIYsYABEDABgACgpmIYsYABEDAAAA.',
Kw='Kwarr:BAACNQAFFH8JAAIXAAYK0g6jAwA8AQAXAAYK0g6jAwA8AQA1AAQKf0MAAhcACgrOIjkDAG0DABcACgrOIjkDAG0DAAAA.',
La='Laganddecay:BAAANQABCggIGQAAAA==.Lalii:BAAANQAECgQIBwAAAA==.Lallatath:BAAANQADCgcIBwAAAA==.Lammoth:BAAANQADCgYICwAAAA==.Lanemogsnick:BAAANQADCgQIBAAAAA==.Larissä:BAAANQAECgIIAgABNQAECgoKUQAMANkWAA==.Layonhandsy:BAAANQAECgQIBAABNQAFFAQICQAiABYhAA==.',
Le='Leafu:BAAANQAECgMIAwABNQAECgoKMgAHAIQcAA==.Leasin:BAABNQAECn8yAAIHAAoKhBywEwDKAgAHAAoKhBywEwDKAgAAAA==.Lencreye:BAAANQADCgMIBAAAAA==.Lethendervis:BAAANQADCgYIDgAAAA==.',
Li='Lighthusk:BAAANQABCgQIBAAAAA==.Liliauna:BAABNQAECn8jAAISAAcK+xr9aQAeAgASAAcK+xr9aQAeAgAAAA==.Lilibejeane:BAAANQADCgcIDgABNQAECgcIFwAPABcSAA==.Lillynelazar:BAABNQAECn8cAAIMAAoKBgUwtwCVAQAMAAoKBgUwtwCVAQABNQAECgYICQAJAAAAAA==.Liloisback:BAABNQAECn8gAAIBAAoKUxZikwDsAQABAAoKUxZikwDsAQAAAA==.Lilsquirtboy:BAAANQADCgUIBQABNQAECgoKPAAFAGQfAA==.Linasonna:BAAANQAFFAEIAQABNQAFFAUIFAATAI0dAA==.Linbächle:BAAANQAECgIIAgAAAA==.Linithara:BAACNQAFFH8MAAIPAAQKRgIsFACZAAAPAAQKRgIsFACZAAA1AAQKfyYAAw8ACgqRDQw3APgBAA8ACgpXDAw3APgBAAgACArlCZwWAEMBAAAA.Lionabtglad:BAAANQAECggICgABNQAECgkJHQAGABESAA==.Littlehoosie:BAABNQAECn8VAAIMAAkKDhe1agDtAQAMAAkKDhe1agDtAQAAAA==.',
Lo='Lockersz:BAAANQADCgEIAQABNQAFFAgIFwAhAGsSAA==.Lokedin:BAAANQAECgUIBQAAAA==.Loram:BAAANQAECgEIAQAAAA==.Lostbase:BAAANQAECgQIBAAAAA==.Lostgrip:BAAANQAECgYIEQAAAA==.',
Lu='Lucthedk:BAABNQAECn8WAAMkAAkK/xAzTADkAQAkAAkK/xAzTADkAQAhAAQKWwrPeADBAAAAAA==.Lukis:BAAANQAECgYICQAAAA==.Lunarpriest:BAAANQAECgQIBAAAAA==.Lunitari:BAAANQAECgEIAQAAAA==.Lunkbeck:BAAANQAECgEIAgAAAA==.Luxriel:BAAANQADCggIDAAAAA==.',
Ly='Lyllith:BAAANQADCgIIAQABNQAECgcIDQAJAAAAAA==.',
['Lø']='Lørd:BAABNQAECn8uAAMZAAoKNB12IABLAgAZAAgK9hl2IABLAgAMAAcKVx7SgwCyAQAAAA==.',
Ma='Madik:BAAANQADCgcJCAAAAA==.Magicmegan:BAAANQAECgEIAQABNQAECggIFgASAKkaAA==.Mahoragax:BAAANQAECggIBgAAAA==.Malachí:BAAANQADCgUIBQABNQAECggIHgAiAGUNAA==.Maladin:BAAANQAECgQIBgAAAA==.Malkurim:BAAANQADCgEIAQAAAA==.Malvean:BAAANQADCgUICgAAAA==.Manasa:BAAANQAECgYIDwAAAA==.Marblack:BAABNQAECn8aAAIBAAkK7AaWjwBiAQABAAkK7AaWjwBiAQAAAA==.Marceline:BAABNQAECn8uAAIMAAoKihb0SgA6AgAMAAoKihb0SgA6AgAAAA==.Marpal:BAAANQAECgMIAwAAAA==.Marthahog:BAAANQAECgYIBgABNQAECgkJOQAlAMgWAA==.Marthog:BAABNQAECn85AAMlAAkKyBboCgAbAgAlAAkKyBboCgAbAgABAAQKTQfiDgFdAAAAAA==.Mashido:BAAANQADCgMIAwAAAA==.Matresstains:BAAANQAECgUICwAAAA==.',
Mc='Mcdermott:BAAANQAECgQIBgAAAA==.',
Me='Melanius:BAAANQAECgUIDQAAAA==.Melranis:BAAANQADCgcIDAAAAA==.',
Mi='Miluk:BAABNQAECn8VAAIVAAkKVw3aqgBOAQAVAAkKVw3aqgBOAQAAAA==.Misconduct:BAABNQAECn8xAAIPAAoKohqbEwCGAgAPAAoKohqbEwCGAgAAAA==.',
Mm='Mmins:BAAANQAECgYICgAAAA==.',
Mo='Montagne:BAAANQADCgQIBAAAAA==.Moomist:BAAANQAECgQIBgAAAA==.Moondarin:BAAANQABCgIIAgAAAA==.Moonfanna:BAAANQAECgQJBQAAAA==.Moonmx:BAAANQAECgYICgAAAA==.Mordakz:BAAANQADCgIIAgABNQAECggIEAAJAAAAAA==.Morriganth:BAAANQADCgEIAQAAAA==.',
Mu='Mujina:BAAANQAECgMIAwABNQAFFAUIEgACAKoeAA==.Murdamoose:BAAANQADCgIIAgAAAA==.Mustysponge:BAAANQADCgUIBwAAAA==.',
My='Mysteryx:BAABNQAECn8mAAIHAAoKYRSuGQCAAgAHAAoKYRSuGQCAAgAAAA==.Mystrbeast:BAAANQADCgQIBAAAAA==.',
['Mó']='Móxie:BAAANQADCgIIAQAAAA==.',
Na='Nahtan:BAAANQADCgYIDAAAAA==.Nammu:BAAANQADCgEIAQAAAA==.Nandisa:BAAANQADCgEIAQAAAA==.Naniwa:BAAANQAECgUICQAAAA==.Nawala:BAAANQAECgEIAQAAAA==.Nazaar:BAAANQADCgIIAgAAAA==.Nazendrov:BAEANQAECggICAABNQAECggICAAJAAAAAA==.Nazura:BAAANQADCgcIEQAAAA==.',
Ne='Nereza:BAAANQADCggIDgAAAA==.Nershog:BAAANQAECgEIAQAAAA==.Nesquip:BAAANQADCgYJBgAAAA==.Newil:BAAANQADCgYIBgAAAA==.',
Ni='Nightforday:BAABNQAECn8zAAMkAAkKiSDHIwC0AgAkAAkKiSDHIwC0AgAhAAIKUhVhjgB+AAAAAA==.Niko:BAAANQABCgUIBwAAAA==.Nishra:BAAANQADCggICAAAAA==.',
No='Nokn:BAAANQAECggIAQAAAA==.Noks:BAAANQAECggICAAAAA==.Noktas:BAAANQAECgYIBwABNQAECgcIBgAJAAAAAA==.Noktus:BAAANQADCgIIAwABNQAECgcIBgAJAAAAAA==.Nokx:BAAANQAECgcIBgAAAA==.Nominé:BAAANQADCgQIBgAAAA==.Nool:BAAANQADCgQIBwAAAA==.Norch:BAAANQAECgIIBAAAAA==.Notkory:BAAANQAECggICAAAAA==.Noux:BAAANQAECgUIBQAAAA==.',
Nu='Nube:BAAANQADCggIDAAAAA==.',
Ny='Nyababa:BAAANQAECgcICgABNQAFFAUIEgACAKoeAA==.',
Oc='Octavia:BAAANQAECgIIAgAAAA==.',
Og='Ogora:BAAANQADCgQIBgAAAA==.',
Ok='Oki:BAAANQADCgMIBAAAAA==.Okktrål:BAAANQAECgYJCgAAAA==.Oktavius:BAACNQAFFH8HAAIYAAMK+BIbGgDYAAAYAAMK+BIbGgDYAAA1AAQKf0wAAxgACgobIy8EAN4DABgACgobIy8EAN4DABMAAQpmC+EHAS0AAAAA.',
Op='Ophysia:BAAANQAECgIIAgAAAA==.',
Or='Ordaka:BAAANQADCgYIBgAAAA==.Orkcansas:BAAANQAECgEIAQAAAA==.Orruutah:BAAANQADCgYIBgAAAA==.',
Os='Oskaia:BAAANQAECgYICwAAAA==.Osla:BAAANQAECgYIBQAAAA==.',
Ox='Oxytoecin:BAAANQAECgYIBgAAAA==.',
Pa='Paapineau:BAABNQAECn8YAAImAAkKRweEIwARAQAmAAkKRweEIwARAQAAAA==.Packel:BAAANQADCggICAABNQAECgoKSwAiAEgbAA==.Packes:BAABNQAECn9LAAIiAAoKSBsvEgCFAgAiAAoKSBsvEgCFAgAAAA==.Packs:BAAANQADCgYIBgABNQAECgoKSwAiAEgbAA==.Pakkohruun:BAABNQAECn8gAAILAAoKcxfXbgBSAgALAAoKcxfXbgBSAgAAAA==.Pallyative:BAAANQADCgIIAgAAAA==.Pallywack:BAABNQAECn9GAAILAAoKSg2biQC5AQALAAoKSg2biQC5AQAAAA==.Palussy:BAAANQADCgQIBAAAAA==.Parthima:BAABNQAECn9EAAMgAAoKHw/iJgDGAQAgAAoKHw/iJgDGAQADAAEKdwlcgQAhAAAAAA==.Partysnaxx:BAAANQABCgEIAQAAAA==.',
Pe='Peppercat:BAAANQAECgQIBwAAAA==.Pertophos:BAAANQAECgUICQAAAA==.Pettigrew:BAAANQADCgIJAgAAAA==.',
Ph='Phantomclone:BAAANQAECgIIBQAAAA==.Phantomdh:BAAANQAECgEIAQAAAA==.Phantomghoul:BAAANQAECgUIBAAAAA==.Philomena:BAAANQADCgUICQAAAA==.',
Pi='Piggÿ:BAABNQAECn8eAAIQAAYKaxDAPQDJAAAQAAYKaxDAPQDJAAAAAA==.Piko:BAAANQADCggIDgAAAA==.Piyo:BAAANQADCgcIBwABNQAECgoKSwAiAEgbAA==.',
Pl='Plankormast:BAAANQADCgEIAQAAAA==.',
Po='Poky:BAAANQAECgEIAQABNQAECgYICgAJAAAAAA==.Popena:BAAANQAECgMIBAAAAA==.Porkbuns:BAABNQAECn8pAAIVAAoKlhNOYQD0AQAVAAoKlhNOYQD0AQAAAA==.Potatogg:BAAANQAECgIIBAAAAA==.',
Pr='Praedor:BAAANQAECggIDAAAAA==.Priestymon:BAABNQAECn8oAAIGAAoK3CFeCwBnAwAGAAoK3CFeCwBnAwABNQAFFAcIDwABAEIdAA==.Protdaddyy:BAAANQADCgUIBQAAAA==.',
Pw='Pwarr:BAACNQAFFH8JAAIlAAQKxwtEBADpAAAlAAQKxwtEBADpAAA1AAQKfyUAAyUACgoyIfYFAKsCACUACgoyIfYFAKsCAAEACAoPDxnSAE0BAAE1AAUUBggJABcA0g4A.',
Qa='Qamar:BAAANQADCgQIBAAAAA==.',
Qu='Quackadeen:BAAANQAECgIJAgAAAA==.Quaesitor:BAAANQADCgYIDwAAAA==.',
Qw='Qwarr:BAAANQAECgUICAABNQAFFAYICQAXANIOAA==.',
Ra='Raamey:BAAANQADCgIIAgAAAA==.Raathya:BAABNQAECn8uAAIMAAoKLRQjRQBIAgAMAAoKLRQjRQBIAgAAAA==.Raeljin:BAABNQAECn8ZAAITAAgKLxlaQQBwAgATAAgKLxlaQQBwAgAAAA==.Ragetastick:BAAANQAECggICQAAAA==.Raihua:BAAANQADCgYIBgAAAA==.Rampagarex:BAAANQADCgYIBgAAAA==.Rangoz:BAAANQAECgUIDQAAAA==.Rar:BAABNQAECn8oAAIMAAoKtiD8HQDJAgAMAAoKtiD8HQDJAgAAAA==.Ratgamerlol:BAACNQAFFH8FAAIMAAIKbyAxHAC0AAAMAAIKbyAxHAC0AAA1AAQKfzwAAgwACQoRJUgqAPACAAwACQoRJUgqAPACAAAA.Ravnur:BAAANQADCggICAAAAA==.Rayennagrom:BAAANQAECgIIAgAAAA==.Rayo:BAAANQAECgIIAgAAAA==.',
Re='Reagent:BAAANQADCgMIAwAAAA==.Reckrunner:BAABNQAECn9bAAQSAAoK2xa7XgC5AQASAAgKGha7XgC5AQAbAAQKiBhdFQDjAAAaAAEKoRTBMABGAAAAAA==.Redlocks:BAAANQAECggIDAAAAA==.Renault:BAAANQADCgMIAwAAAA==.Reneana:BAAANQAECgUIDAAAAA==.Restbo:BAACNQAFFH8LAAIYAAYKsxlCCAD7AQAYAAYKsxlCCAD7AQA1AAQKfy0AAhgACgrdJHQLAGUDABgACgrdJHQLAGUDAAE1AAUUBggVABYAHREA.',
Rg='Rgent:BAAANQADCgYIBgABNQADCgYIBwAJAAAAAA==.',
Rh='Rhianonn:BAAANQAECgYIEgABNQAECgkJHgADAIkYAA==.',
Ri='Riaslock:BAAANQAECgEJAQAAAA==.Riaswar:BAAANQADCgEIAQAAAA==.Richardluis:BAABNQAECn8WAAITAAcKwwrPoABVAQATAAcKwwrPoABVAQAAAA==.Rinehardtt:BAABNQAECn9AAAIKAAoKVCCsGADyAgAKAAoKVCCsGADyAgAAAA==.Ripheals:BAAANQAECggIDAAAAA==.Riverstyxx:BAAANQADCgYIEQAAAA==.Rivër:BAAANQADCggIJAAAAA==.',
Ro='Robbell:BAABNQAECn82AAIMAAoK3BzgLACOAgAMAAoK3BzgLACOAgAAAA==.Rococote:BAAANQAECggIEgAAAA==.Roggehere:BAAANQAECgIIAgAAAA==.Rokyman:BAAANQAECgYIEAAAAA==.Roldazark:BAAANQABCgEIAQAAAA==.Roonsia:BAAANQADCgQIBQAAAA==.Rootsie:BAAANQADCgYJFwAAAA==.Roselynn:BAABNQAECn8ZAAIDAAgKbRasHwAuAgADAAgKbRasHwAuAgAAAA==.Rouby:BAAANQAECgEIAgAAAA==.Roughlight:BAAANQADCgMIAwAAAA==.',
Ru='Ruerl:BAABNQAECn8YAAILAAgKTAqxzACCAQALAAgKTAqxzACCAQAAAA==.Runentug:BAACNQAFFH8JAAIiAAQKFiHtDQB1AQAiAAQKFiHtDQB1AQA1AAQKfxsAAiIACQqSJAkNAEkDACIACQqSJAkNAEkDAAAA.Rustyspell:BAAANQADCgIIAgAAAA==.',
Ry='Ryumapriest:BAAANQABCgEIAQAAAA==.',
['Rî']='Rîft:BAAANQADCgEIAQAAAA==.',
Sa='Sadako:BAAANQAECgEIAQABNQAFFAUIEgACAKoeAA==.Sanddora:BAAANQADCgIIAgAAAA==.Sanlordriel:BAAANQAECgMIAwAAAA==.Saramon:BAAANQADCggIKQAAAA==.Sarios:BAAANQADCgQIAwAAAA==.Sassiberry:BAAANQADCgcIEQAAAA==.Sassitude:BAAANQADCgcIFQAAAA==.Satiiva:BAAANQADCggICAAAAA==.',
Sc='Scarlos:BAAANQABCgMIAwAAAA==.Screamdying:BAAANQABCgIIAgAAAA==.Scrembiblion:BAABNQAECn81AAInAAoKfh0tAQCKAgAnAAoKfh0tAQCKAgAAAA==.',
Sd='Sdhoscillate:BAAANQADCgYIBgAAAA==.',
Se='Seins:BAAANQADCgYIBgAAAA==.Semillin:BAAANQAECgcIEAAAAA==.Senseitional:BAAANQAECgEIAQABNQAECgoKQwAQAJciAA==.Sensjei:BAABNQAECn8UAAIFAAgKlQamNgDtAAAFAAgKlQamNgDtAAAAAA==.Sentarry:BAAANQAECgMIAwABNQAFFAcIEAAVAAgYAA==.Separatist:BAAANQADCgMIAwAAAA==.Serendibitty:BAAANQADCgMIAwABNQAECgYIEgAJAAAAAA==.',
Sg='Sgtbreezy:BAAANQADCgcIBwAAAA==.Sgtpanda:BAAANQADCgEIAQAAAA==.',
Sh='Shadey:BAAANQADCgIIAgAAAA==.Shambulance:BAAANQAECgcIDQAAAA==.Sharuerl:BAAANQADCgcIBwAAAA==.Shawshaa:BAAANQAECgUIBQAAAA==.Shazi:BAEANQAECggICAAAAA==.Shiftroid:BAAANQADCgMIBgAAAA==.Shinyivie:BAABNQAECn8eAAILAAkKYwX85ABRAQALAAkKYwX85ABRAQAAAA==.Shiverchill:BAAANQABCgEJAQAAAA==.Shockrock:BAAANQADCgEIAQAAAA==.Shouzhe:BAAANQADCgUIBQAAAA==.Shroomjuice:BAAANQAECggIDwAAAA==.Shãdøwzzxz:BAAANQAECgUIDAAAAA==.Shådwözzxz:BAAANQADCgUIBQAAAA==.',
Si='Sildenafil:BAAANQADCgIIAgAAAA==.Silessra:BAAANQADCggICAAAAA==.',
Sk='Skiffyy:BAAANQAECgEIAQAAAA==.Skogr:BAAANQADCgIIAQABNQADCgUIBQAJAAAAAA==.Skädoosh:BAAANQAECgEIAQAAAA==.',
Sl='Slapshappy:BAAANQAECggICQAAAA==.',
Sm='Smallhorn:BAAANQAECgEIAgAAAA==.Smokeyhaze:BAAANQAECgYIDgAAAA==.Smokin:BAABNQAECn8vAAIMAAoKQAq6kwCOAQAMAAoKQAq6kwCOAQAAAA==.Smolther:BAAANQADCgcIBwAAAA==.Smores:BAAANQAECgEIAQAAAA==.',
Sn='Sneech:BAAANQAECgUIDQAAAA==.Snikrot:BAAANQADCgcIBwAAAA==.Snowbvnni:BAAANQADCgQIBAAAAA==.',
So='Sofarkinghi:BAAANQAECgEIAgAAAA==.Sollamor:BAAANQAECgMIAwAAAA==.Solomonk:BAABNQAECn9GAAIjAAkKhg7yDABeAQAjAAkKhg7yDABeAQAAAA==.Solomus:BAABNQAECn87AAMQAAoKLQ9KIgBwAQAQAAoKLQ9KIgBwAQAgAAQKWwEFjAAyAAAAAA==.Sonal:BAABNQAECn8XAAQhAAcKtgocXQAzAQAhAAcKtQkcXQAzAQAiAAUK6QezjgDIAAAkAAEKAAC9+AAfAAAAAA==.Soneca:BAAANQAECgMIAwAAAA==.Soter:BAABNQAECn8eAAMiAAgKZQ2WOQBcAQAiAAgKZQ2WOQBcAQAkAAQKrwXCaQBtAAAAAA==.',
Sp='Spitzonit:BAAANQAECgUIBAAAAA==.',
Sq='Squeaph:BAABNQAECn8XAAIPAAkKZQxgLwCbAQAPAAkKZQxgLwCbAQAAAA==.',
St='Stararia:BAAANQADCggIDwAAAA==.Stelltrain:BAAANQABCgIIBAAAAA==.Stormiee:BAABNQAECn8pAAIYAAkKqxhSOAB+AgAYAAkKqxhSOAB+AgABNQAECgkJHgADAIkYAA==.Stormroid:BAAANQAECgUICQAAAA==.Sttorm:BAAANQADCgUIBQAAAA==.Styles:BAABNQAECn8wAAILAAgKCgyJ0AA3AQALAAgKCgyJ0AA3AQAAAA==.',
Su='Sudowoodont:BAAANQAECgYICwAAAA==.Sugarontop:BAAANQADCgQIBAAAAA==.Sunmx:BAABNQAECn81AAMBAAoKPh9zKQAVAwABAAoKYB5zKQAVAwACAAYKyiCwDAC6AQAAAA==.Superdark:BAAANQADCgIIAgAAAA==.Supersquidd:BAAANQADCgMIAwAAAA==.Suskebears:BAAANQAECgMIAwAAAA==.',
Sw='Swurve:BAEANQAECgcIDgAAAA==.Swurves:BAAANQAECggICgAAAA==.',
Sz='Szucs:BAAANQADCgMIAwAAAA==.',
['Sã']='Sãvãge:BAAANQADCgQIBAAAAA==.',
Ta='Tabiji:BAEANQAECggICAAAAA==.Tadpole:BAAANQAECggIDwAAAA==.Taedrum:BAABNQAECn8aAAIkAAgKEwgxPQAeAQAkAAgKEwgxPQAeAQAAAA==.Taerror:BAAANQADCgIIAgAAAA==.Talegos:BAAANQAECgMJAwAAAA==.Talonfel:BAAANQADCgQIBAABNQAECgkJOQAUACUjAA==.Taloning:BAAANQADCgYIBgABNQAECgkJOQAUACUjAA==.Talonstryke:BAABNQAECn85AAIUAAkKJSOfAwB2AwAUAAkKJSOfAwB2AwAAAA==.Tauraxs:BAAANQADCgEIAQAAAA==.Tazrak:BAAANQAECgUIBAABNQAECgoKNAASAIoKAA==.',
Te='Teatoh:BAAANQADCgcIBwAAAA==.Teenjus:BAAANQABCgMIAwABNQAECgoKNAAEAPAZAA==.Tenseiga:BAABNQAECn8lAAMLAAoKhxplRABdAgALAAkKhxplRABdAgAEAAoK7QvSLAB2AQABNQAFFAUIDwAIAPMbAA==.Testsubjectz:BAACNQAFFH8FAAIBAAUKyBtrGADrAAABAAUKyBtrGADrAAA1AAQKfxwAAgEACQpTJiECAIQDAAEACQpTJiECAIQDAAAA.Tevers:BAAANQAECgEIAgAAAA==.',
Th='Thalantier:BAAANQADCgMIBgAAAA==.Thardal:BAABNQAECn8mAAMbAAoKDBBeCwC1AQASAAoKMg2RfADvAQAbAAkKEhBeCwC1AQAAAA==.Thebigshot:BAAANQAECgMIBQAAAA==.Theenforcer:BAACNQAFFH8SAAILAAUK7QtnGQDGAAALAAUK7QtnGQDGAAA1AAQKf2kAAgsACgqAE71nAAECAAsACgqAE71nAAECAAAA.Thegreekbeas:BAAANQADCgUIBQAAAA==.Theguyfurry:BAAANQAECgEIAQAAAA==.Theonepanda:BAAANQAECgUICAAAAA==.Thetzin:BAABNQAECn8eAAIVAAYKJwNkYQHxAAAVAAYKJwNkYQHxAAAAAA==.Theunite:BAAANQADCggICAAAAA==.Thickhobo:BAAANQADCgUICQAAAA==.Thidwick:BAABNQAECn9DAAIQAAoKlyJTBAAiAwAQAAoKlyJTBAAiAwAAAA==.Thingtwø:BAABNQAECn8aAAIhAAoKFB2JFwCPAgAhAAoKFB2JFwCPAgAAAA==.Thistle:BAAANQADCgYIDAABNQAECgkJIQAVADQMAA==.Thraggs:BAAANQADCgcICAAAAA==.Thunderfist:BAAANQADCggIBwAAAA==.',
Ti='Tirtraz:BAAANQADCgQIBAAAAA==.Titanslay:BAAANQADCgEIAQAAAA==.Titø:BAAANQADCgYIDQABNQADCgcIBwAJAAAAAA==.',
Tm='Tmryuki:BAAANQAECggICgAAAA==.',
To='Tokadin:BAAANQAECgIIAgAAAA==.Tomorrow:BAAANQAECgYICgAAAA==.Topzee:BAAANQAECgQIBQAAAA==.Totalljoe:BAABNQAECn8YAAILAAkKLxOPhgC/AQALAAkKLxOPhgC/AQAAAA==.Totoo:BAABNQAFFH8HAAINAAcKDgB6FwAhAAANAAcKDgB6FwAhAAAAAA==.Touchmablade:BAAANQAECgUIBQAAAA==.',
Tr='Traedarra:BAAANQADCgIIAgAAAA==.Tralis:BAEANQADCggIDgABNQAECggICAAJAAAAAA==.Tranarra:BAABNQAECn95AAISAAoKrh7NGAC6AgASAAoKrh7NGAC6AgAAAA==.Traylo:BAABNQAECn8uAAIMAAoKjxJ9XAAPAgAMAAoKjxJ9XAAPAgAAAA==.',
Tv='Tvak:BAABNQAECn8ZAAILAAcKcxfjtAC1AQALAAcKcxfjtAC1AQAAAA==.',
Tw='Twistedsham:BAAANQAECggICQAAAA==.Twopump:BAABNQAECn83AAILAAoKYwjMzACCAQALAAoKYwjMzACCAQAAAA==.',
['Tó']='Tónka:BAAANQADCgcIBwAAAA==.',
Ul='Ulhae:BAAANQABCgQIBAAAAA==.Ulinova:BAABNQAECn8bAAIoAAkK4BE9AwDBAQAoAAkK4BE9AwDBAQAAAA==.',
Um='Umbressa:BAAANQADCgMIAwABNQAECgoKNgAMAAkcAA==.Umbryx:BAAANQADCgIIAgABNQAECgoKNAASAIoKAA==.',
Un='Unholly:BAAANQAECgIJAwAAAA==.',
Ur='Uroro:BAACNQAFFH8IAAMYAAUKfhKNFwDnAAAYAAUKfhKNFwDnAAAXAAEK1QUpCQBEAAA1AAQKfzkAAxgACgo1Ik0YABIDABgACgo1Ik0YABIDABMAAQoAAONCASwAAAE1AAUUBQgSAAIAqh4A.',
Uu='Uu:BAAANQABCgIIAgAAAA==.',
Va='Vaiden:BAAANQABCgEIAQAAAA==.Vainqueur:BAABNQAECn84AAIdAAoK0RwcBACjAgAdAAoK0RwcBACjAgAAAA==.Valienni:BAAANQAECgEIAQAAAA==.Vanderdemon:BAAANQADCgMIAwAAAA==.Vanderlight:BAAANQADCgUJCQAAAA==.Vandernum:BAAANQAECggICAAAAA==.Vandersus:BAAANQADCggIBQAAAA==.Varm:BAAANQADCggICAAAAA==.',
Ve='Velakai:BAAANQABCgQIBAAAAA==.Verlasky:BAABNQAECn8UAAIMAAoKnQ+dVwAcAgAMAAoKnQ+dVwAcAgABNQAECgoKOAAgAAgPAA==.Vervaeda:BAAANQADCgQIBAAAAA==.Verymelon:BAAANQAECgQIBgABNQAFFAQIBwATAFYOAA==.Vestele:BAAANQADCggIDwAAAA==.',
Vg='Vgx:BAABNQAECn86AAIhAAoKCA94PwCeAQAhAAoKCA94PwCeAQAAAA==.',
Vi='Vielitre:BAAANQAECgMIAwAAAA==.Vigossfel:BAAANQADCgMIBwAAAA==.Viintage:BAABNQAECn80AAIVAAoKCBW9YAD1AQAVAAoKCBW9YAD1AQAAAA==.Vishouspayne:BAABNQAECn8XAAIMAAYKFwYPBAGqAAAMAAYKFwYPBAGqAAAAAA==.',
Vo='Voidshank:BAAANQAECgEIAgAAAA==.Vorath:BAAANQADCgQIBAAAAA==.',
Vy='Vyolence:BAAANQAECgQIBAABNQAECgoKMgAHAIQcAA==.',
['Vä']='Väelün:BAABNQAECn8mAAMOAAgKFBFNKwA9AQAOAAgKFBFNKwA9AQAPAAEKawTsmwAnAAAAAA==.',
['Vÿ']='Vÿ:BAABNQAECn8lAAIMAAgK0wiWrQBXAQAMAAgK0wiWrQBXAQAAAA==.',
Wa='Wachoosh:BAAANQAECgYIDAAAAA==.Waidmanns:BAABNQAECn82AAMMAAoKCRzAJwD5AgAMAAoKCRzAJwD5AgApAAMKuwk7EAB3AAAAAA==.Wakenbakejs:BAAANQAECgEIAQAAAA==.Wakinbakin:BAAANQAECgQIBQAAAA==.Walmartstaff:BAAANQADCgUIBQAAAA==.Warfable:BAAANQADCgIIAgAAAA==.',
Wg='Wgnmd:BAAANQAECgQIBQAAAA==.',
Wh='Wham:BAAANQAECgIIAwAAAA==.Whatsaggro:BAABNQAECn8lAAIkAAgKhwk9aABwAQAkAAgKhwk9aABwAQABNQAECgkJGAALAC8TAA==.Whatyamean:BAABNQAECn8jAAMYAAoKvxCXVQC9AQAYAAkKSg6XVQC9AQATAAMKZwN84gBTAAAAAA==.Whiteeyedemo:BAAANQADCgYIBgAAAA==.Whoangry:BAABNQAECn8mAAMNAAkKLhMzUwC4AQANAAgKGhAzUwC4AQAmAAkKgQ+6RQCwAQAAAA==.Whomonk:BAAANQAECgIIBAAAAA==.',
Wi='Willowknight:BAAANQADCgYICgAAAA==.Wimdy:BAAANQADCgMIAwAAAA==.Winterknight:BAAANQADCgUICwAAAA==.',
Wr='Wrenn:BAAANQAECgcICAAAAA==.Wrongname:BAAANQAECgUIBwAAAA==.',
Wu='Wumba:BAAANQAECgMIAwAAAA==.',
Xa='Xanthe:BAAANQADCggIBwAAAA==.',
Xf='Xfloki:BAAANQADCgQIBAAAAA==.',
['Xß']='Xß:BAAANQADCgIJBAAAAA==.',
Ya='Yakpriest:BAAANQADCgcIDAAAAA==.Yawg:BAEANQADCgYIBgABNQAECgoKQQAMAPsfAA==.',
Yd='Ydgktt:BAAANQADCgMIBAAAAA==.',
Yl='Ylladaern:BAAANQADCgEIAQAAAA==.',
Yn='Ynhük:BAAANQADCgMIAwAAAA==.',
Yo='Yogsothoth:BAEBNQAECn9BAAIMAAoK+x/eIgC0AgAMAAoK+x/eIgC0AgAAAA==.Yosha:BAAANQABCgYICAAAAA==.',
Yr='Yrdenal:BAAANQADCgcICQAAAA==.',
Yu='Yugalipdeez:BAAANQAECgEIAgAAAA==.Yulian:BAABNQAECn8VAAISAAYKrwwZrwD2AAASAAYKrwwZrwD2AAAAAA==.',
Za='Zaartyn:BAABNQAECn88AAISAAoKWyOjEwA+AwASAAoKWyOjEwA+AwAAAA==.Zaater:BAAANQAECggICQAAAA==.Zalin:BAAANQAECgEIAQABNQAECgoKJgAbAAwQAA==.Zanki:BAAANQAECgUICwAAAA==.',
Ze='Zeebeth:BAABNQAECn8YAAIMAAkKfw8wjQDwAQAMAAkKfw8wjQDwAQAAAA==.Zefi:BAAANQAECgcIAgAAAA==.Zellek:BAAANQADCgYIBgAAAA==.Zenbu:BAAANQADCgIIAgAAAA==.Zeroasy:BAAANQADCgIIAgABNQAECgoKNwAiAPIjAA==.Zerokai:BAAANQAECggIDwAAAA==.Zeztz:BAAANQAECgcIDAAAAA==.',
Zo='Zomlo:BAAANQAECgQIBgAAAA==.Zooli:BAAANQADCggICAAAAA==.Zorosenpai:BAAANQADCgcIEQABNQAECggIIgAhAJ8KAA==.',
Zu='Zuggernaught:BAAANQAECgUIDAABNQAECgcIDQAJAAAAAA==.',
Zy='Zynokyno:BAAANQADCgYIBgAAAA==.',
['Át']='Átomic:BAAANQADCgUIAwAAAA==.',
['Ân']='Ânimosity:BAAANQADCgIIAgAAAA==.',
['Âr']='Ârtemis:BAAANQAECgQIBAABNQAFFAUIDwAIAPMbAA==.',
['Ís']='Ísvala:BAAANQADCgYIBgAAAA==.',
['ßu']='ßuzzibee:BAABNQAECn8fAAILAAoKNhT8bAD2AQALAAoKNhT8bAD2AQABNQAECgoKMQAPAKIaAA==.',
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
