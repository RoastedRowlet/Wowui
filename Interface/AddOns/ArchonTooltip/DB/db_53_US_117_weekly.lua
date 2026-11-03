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

local lookup = {'Warrior-Arms','Warrior-Fury','Druid-Restoration','Paladin-Protection','Monk-Windwalker','Priest-Holy','Priest-Shadow','DemonHunter-Vengeance','Paladin-Holy','Paladin-Retribution','Hunter-BeastMastery','Rogue-Subtlety','DemonHunter-Devourer','DemonHunter-Havoc','Druid-Guardian','Druid-Feral','Warlock-Demonology','Shaman-Elemental','Monk-Mistweaver','Unknown-Unknown','Mage-Arcane','Priest-Discipline','Shaman-Enhancement','Shaman-Restoration','Hunter-Marksmanship','Warlock-Destruction','Warlock-Affliction','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Mage-Frost','Druid-Balance','DeathKnight-Frost','DeathKnight-Blood','Monk-Brewmaster','DeathKnight-Unholy','Warrior-Protection','Rogue-Assassination','Mage-Fire','Hunter-Survival',}
local provider = {region='US',realm='Hakkar',name='US',type='weekly',zone=53,date='2026-11-03',data={Ac='Aceshaman:BAAANQADCgIIAgAAAA==.Acheros:BAAANQADCgMIAwAAAA==.Actionfigure:BAACNQAFFH8KAAIBAAQKyCCkFQB7AQABAAQKyCCkFQB7AQA1AAQKfzUAAwIACgqCJDUEAIACAAEACgonH2A3AOYCAAIACAptJDUEAIACAAAA.',
Ad='Adielia:BAABNQAECn8jAAIDAAgK4hvUHQBBAgADAAgK4hvUHQBBAgAAAA==.Adurzin:BAAANQADCgIIAgAAAA==.',
Ae='Aeralina:BAAANQADCgUJBQAAAA==.Aeri:BAAANQADCgIIAwAAAA==.Aevalaana:BAAANQAECgYICQAAAA==.',
Ag='Agiermodinn:BAAANQADCgYICgAAAA==.',
Ah='Ahnho:BAAANQADCggICgAAAA==.',
Ai='Aidandrius:BAAANQADCgMIAwAAAA==.Aimeeleigh:BAAANQAECgQIBQABNQAECggIJQAEAPwZAA==.Airflash:BAACNQAFFH8MAAIFAAUKEx4tCQBFAQAFAAUKEx4tCQBFAQA1AAQKfzkAAgUACAo/JasHAFQDAAUACAo/JasHAFQDAAAA.Aiøn:BAAANQADCgcIBwAAAA==.',
Ak='Akutagawa:BAABNQAECn8nAAMGAAkKoxo5HgC5AgAGAAkKoxo5HgC5AgAHAAEKAAD8ZgAAAAABNQAFFAUIDgAIAPMbAA==.',
Al='Alexandriia:BAAANQAECgEIAQAAAA==.Alexious:BAACNQAFFH8SAAIEAAUKrR8ZBACfAQAEAAUKrR8ZBACfAQA1AAQKfzQAAgQACgqFIk4HAC4DAAQACgqFIk4HAC4DAAAA.Aloonarn:BAAANQAECgYIEQAAAA==.Alopix:BAAANQAECgcIDQAAAA==.Alulla:BAACNQAFFH8SAAMCAAUKqh7rAQD0AAABAAQKqh5tFwBnAQACAAMKwRjrAQD0AAA1AAQKfyEAAwIACgopIa0KAB0CAAEACQo5ICJJAK4CAAIABwoTIq0KAB0CAAAA.Alunira:BAABNQAECn87AAMJAAoKnh/gGAAVAwAJAAoKnh/gGAAVAwAKAAYKbhYTzQCBAQAAAA==.',
Am='Amberrfrost:BAAANQAECgQICAAAAA==.Amize:BAAANQADCgYIBgAAAA==.Ampz:BAAANQAECgQIBAAAAA==.',
An='Anabee:BAAANQADCggIDgAAAA==.Angelicshy:BAAANQADCgQIBAAAAA==.Angryhtr:BAABNQAECn8UAAILAAcKGhkydgAjAgALAAcKGhkydgAjAgAAAA==.Angryshh:BAAANQAECggICgAAAA==.Angrywar:BAABNQAECn8bAAIBAAgKHxL9nADUAQABAAgKHxL9nADUAQAAAA==.Anharon:BAAANQADCgcICgAAAA==.Ansatz:BAAANQAECgEIBQABNQAECgoKNQALAAkcAA==.',
Ap='Apokalypto:BAAANQAECgUIBwAAAA==.',
Ar='Arbiterbinky:BAAANQADCgUIBQAAAA==.Ardå:BAAANQADCgEIAQAAAA==.Argangus:BAAANQADCgYIDwAAAA==.Arrowganz:BAAANQADCgYIBgAAAA==.Arthan:BAAANQAECgMIAwAAAA==.Arthannix:BAAANQADCgYICgAAAA==.',
As='Assine:BAAANQAECgEIAwABNQAFFAcIBwAMAA4AAA==.Astanis:BAAANQAECgcICgAAAA==.Asteriia:BAABNQAECn8aAAINAAkKfwgoNgCSAQANAAkKfwgoNgCSAQAAAA==.Astralyn:BAAANQAECgEIAQAAAA==.',
Au='Augito:BAAANQABCgIIAgAAAA==.',
Av='Averettara:BAAANQAECgIIBgABNQAECgkJFAAKACQQAA==.',
Az='Azarazan:BAAANQADCgYIDgAAAA==.Azka:BAABNQAECn8tAAIKAAoKDSDuIAC8AgAKAAoKDSDuIAC8AgAAAA==.Azkadk:BAAANQADCgYIBgAAAA==.',
Ba='Babybilly:BAABNQAECn8lAAMEAAgK/BnBHQD7AQAEAAgK/BnBHQD7AQAKAAMKkAOgcAFtAAAAAA==.Baelmon:BAAANQAECgIIAwAAAA==.Baludis:BAAANQADCgcIEQAAAA==.Bamff:BAAANQAECgUICQAAAA==.Bamfpally:BAAANQADCggICAAAAA==.Barreack:BAAANQADCgYICAAAAA==.Bast:BAACNQAFFH8OAAIIAAUK8xs8AgAuAQAIAAUK8xs8AgAuAQA1AAQKfz8AAwgACgpoJZcAAGEDAAgACgpoJZcAAGEDAA4ABQpFE2pSAEoBAAAA.Basthara:BAABNQAECn8wAAMPAAoKGSMkAwAsAwAPAAoKGSMkAwAsAwAQAAEKVAIbUwAGAAABNQAFFAUIDgAIAPMbAA==.',
Be='Beckianslip:BAAANQAECgEIAQAAAA==.Belphegor:BAAANQAECgYIBwABNQAECgoKLgARAIoKAA==.Benif:BAACNQAFFH8PAAIBAAcKQh26DwC7AQABAAcKQh26DwC7AQA1AAQKfzoAAgEACgrvJWMFAFwDAAEACgrvJWMFAFwDAAAA.Benjaquel:BAAANQADCgQIBAAAAA==.Bertorod:BAABNQAECn8YAAISAAkKqxUfWAAbAgASAAkKqxUfWAAbAgAAAA==.',
Bi='Bigbitehotdo:BAABNQAECn88AAMFAAoKZB+MDgD3AgAFAAoKZB+MDgD3AgATAAEK3wHaVAAgAAAAAA==.Bighoney:BAAANQAECgIIAgAAAA==.Bigtommybuns:BAAANQADCgUIBQAAAA==.Binkyfiasco:BAAANQADCggIDgAAAA==.Binny:BAAANQADCgYIBgAAAA==.Birdiewordie:BAAANQADCgQIBAAAAA==.',
Bl='Bloodeie:BAAANQADCgQIBAAAAA==.Bloodstoned:BAABNQAECn8VAAINAAcKBwabLQD0AAANAAcKBwabLQD0AAAAAA==.Blueboy:BAABNQAECn8eAAIHAAoKJgwvGACmAQAHAAoKJgwvGACmAQAAAA==.Bluechewman:BAAANQADCgQIBAAAAA==.',
Bo='Boffadz:BAAANQAECggIEQAAAA==.Bonewand:BAAANQAECgEIAQAAAA==.Bonewrath:BAAANQABCgIIAgAAAA==.Boogat:BAAANQAECgQICQAAAA==.Boomblessed:BAAANQAECgUIBQAAAA==.Bovillus:BAAANQAECgUICgAAAA==.Bowflex:BAAANQADCgQIBAAAAA==.',
Br='Braugorlle:BAAANQAECgYICQABNQAFFAUIEgASAI0dAA==.Breadscrumb:BAAANQADCgUJBQAAAA==.Briandejay:BAAANQAECgIIAwAAAA==.Bridrystina:BAAANQADCgQIBAAAAA==.Brixlo:BAAANQADCgEIAQABNQADCgcIBwAUAAAAAA==.',
Bu='Buffmuffin:BAAANQAECgIIAgAAAA==.Burblbiblr:BAAANQADCgQJBAAAAA==.Bustrdugles:BAAANQADCgUIBQAAAA==.',
Bw='Bwazakki:BAAANQADCgMIAwAAAA==.Bwr:BAAANQADCgMIAwAAAA==.',
['Bü']='Bübbawrap:BAAANQAECgQICgAAAA==.',
Ca='Cambrier:BAABNQAECn9IAAMBAAoKpSEnEwDzAgABAAoKHiEnEwDzAgACAAgKoiAIBQDbAgAAAA==.Cameraop:BAABNQAECn8XAAIVAAcKKwj2EgFtAQAVAAcKKwj2EgFtAQAAAA==.Candyapples:BAAANQADCgUIBQAAAA==.Canias:BAAANQADCgUIBAABNQAECggICgAUAAAAAA==.Capnsoap:BAAANQADCgYIBgABNQABCgEIAQAUAAAAAA==.Capnsöap:BAAANQAECgEIAQABNQABCgEIAQAUAAAAAA==.Capriestsun:BAAANQAECggICwAAAA==.Cardinal:BAAANQAECgIIAgAAAA==.Carynden:BAAANQAECgUIBQAAAA==.Castbo:BAAANQAECgcIEAABNQAFFAYIFQAWAB0RAA==.',
Ce='Celilinia:BAAANQAECgIIAgAAAA==.Cellesstia:BAAANQADCgMIBQABNQAECgYIDQAUAAAAAA==.',
Ch='Chaiharder:BAAANQAECgEIAQAAAA==.Chalada:BAAANQADCgEIAQABNQAFFAcIBwAMAA4AAA==.Chalastorm:BAAANQAECggIBQABNQAFFAcIBwAMAA4AAA==.Charknight:BAAANQADCgUIBQAAAA==.Chatdodu:BAAANQAECgEIAQAAAA==.Chatnoir:BAABNQAECn8XAAILAAgKCg9KeACDAQALAAgKCg9KeACDAQAAAA==.Chestock:BAAANQAECgYIBgAAAA==.Chuggz:BAAANQAECgQIBgAAAA==.',
Cl='Clonetastic:BAAANQADCggICAAAAA==.Clumsycarl:BAAANQADCgIIAgAAAA==.',
Cm='Cmx:BAAANQADCgUIBQAAAA==.',
Co='Codith:BAAANQAECgQIBQAAAA==.Coldlock:BAAANQADCgQIBAAAAA==.Colesiaw:BAAANQADCgQIBgAAAA==.Coraeze:BAAANQADCgEIAQAAAA==.',
Cp='Cptcrunch:BAAANQAECgQICQABNQAECgkJKwASAP4cAA==.',
Cr='Crais:BAAANQAECgYIBgAAAA==.Creek:BAAANQABCgYIBgABNQAECgoKLQAOAIQgAA==.Crnogorac:BAAANQAECggIAQAAAA==.Crotchgoblim:BAAANQADCgcIFAAAAA==.Cryodormu:BAAANQAECgMJAwAAAA==.',
Cu='Cubo:BAAANQAECgEIAQAAAA==.Cuddlesworth:BAABNQAECn8uAAIRAAoKigqbXACFAQARAAoKigqbXACFAQAAAA==.',
Cw='Cwarr:BAAANQAECgIIAgABNQAFFAYICQAXANIOAA==.',
Cy='Cyrcee:BAAANQADCgUIBQABNQAECgYIDQAUAAAAAA==.',
Da='Daddyluis:BAAANQADCggICgAAAA==.Dadstonks:BAAANQABCgYJCAAAAA==.Dagoujiao:BAABNQAECn8ZAAMSAAoKVgusTQBmAQASAAoKVgusTQBmAQAYAAcKGg0ErwASAQAAAA==.Dameiyo:BAAANQAECggIEwAAAA==.Dandanh:BAAANQADCgMIAwAAAA==.Dangright:BAABNQAECn8aAAIZAAgKXwVBPgBgAQAZAAgKXwVBPgBgAQAAAA==.Dankbo:BAACNQAFFH8VAAMWAAYKHREfAgDVAAAGAAUKMhQiGAAyAQAWAAMK1ggfAgDVAAA1AAQKfz0AAxYACgr/IrMCAOQCABYACAq6ILMCAOQCAAYACgrbHvYlANMCAAAA.Danorac:BAABNQAECn8hAAINAAoKdQxCGAC+AQANAAoKdQxCGAC+AQAAAA==.Darkcoffee:BAABNQAECn8dAAIEAAcKjhuPEADkAQAEAAcKjhuPEADkAQAAAA==.Darkivie:BAAANQADCgYIBgABNQAECgkJHgAKAGMFAA==.',
De='Deadashe:BAAANQADCgEIAQAAAA==.Demonicsword:BAAANQADCgQIBAAAAA==.Despondent:BAAANQADCggIFgAAAA==.Devilcrybaby:BAAANQAECgIIAgAAAA==.Devildj:BAAANQAECgcIEgAAAA==.Dezadian:BAABNQAECn8gAAIKAAcKogTGGwHxAAAKAAcKogTGGwHxAAAAAA==.',
Dh='Dhampyra:BAABNQAECn8YAAMHAAgKOBOFJQADAgAHAAgKOBOFJQADAgAGAAQKDRcqjwDyAAAAAA==.',
Di='Dietmountdew:BAAANQAECgQIBAAAAA==.Dimitrios:BAAANQAECgcICQAAAA==.Disolve:BAABNQAECn8gAAQRAAkKFBGueAD5AQARAAkKog2ueAD5AQAaAAIK9hY7UgCIAAAbAAEKAABKJQBZAAAAAA==.Dixxonciderr:BAACNQAFFH8IAAIcAAUKuAeKEgC4AAAcAAUKuAeKEgC4AAA1AAQKf0kABBwACgohHo8JAAoDABwACgohHo8JAAoDAB0ABwqLD8UgAE0BAB4AAgpZFf0dAHIAAAAA.',
Dm='Dmdedifudo:BAAANQADCgIIAgAAAA==.Dmoe:BAAANQAECgUICwAAAA==.',
Do='Docutratties:BAAANQAECgMIAwABNQAECgoKLgARAIoKAA==.Doji:BAAANQADCgEIAQAAAA==.Doublesixes:BAAANQAECgEIAQAAAA==.',
Dq='Dqe:BAAANQAECgEIAQAAAA==.',
Dr='Drac:BAAANQADCgMIAwAAAA==.Dragonara:BAAANQADCggICAAAAA==.Draskion:BAAANQADCgcIBwAAAA==.Dribby:BAAANQAECgQIBQABNQAECgYICwAUAAAAAA==.',
Du='Duhästmich:BAAANQADCgYIBgABNQAECgkJFAAKACQQAA==.Duplicate:BAACNQAFFH8PAAMfAAQKjBQTCQCOAAAVAAQKjBQ/IwDLAAAfAAIKGA8TCQCOAAA1AAQKfzAAAxUACgqHHUgxAF0CABUACgqHHUgxAF0CAB8AAQonG6BBAEEAAAAA.Dustdruid:BAACNQAFFH8FAAIgAAMKdxCdGgDNAAAgAAMKdxCdGgDNAAA1AAQKfzYAAiAACQpLIKsSAGECACAACQpLIKsSAGECAAAA.Dustlock:BAAANQAECggIEQAAAA==.Dustmage:BAAANQADCggIEAAAAA==.Dustsham:BAAANQAECgEIAwAAAA==.',
Dw='Dwarr:BAAANQAECgYICAAAAA==.',
Dy='Dysnomia:BAAANQAECgIIAgAAAA==.',
Dz='Dzoolock:BAAANQAECgEIAQAAAA==.',
['Dó']='Dóru:BAAANQADCgYIBwAAAA==.',
Ee='Eender:BAAANQAECgEIAQAAAA==.',
Eg='Eggrolls:BAABNQAECn9DAAIBAAoKNB4AIwAsAwABAAoKNB4AIwAsAwAAAA==.',
El='Eldenmorden:BAAANQADCgYIBgAAAA==.Eleshmelly:BAAANQADCgcIFgAAAA==.Elfrafa:BAAANQADCgQIBQAAAA==.Ellayna:BAAANQADCgEIAQAAAA==.Ellcrys:BAABNQAECn9EAAIDAAoK+xzVCQD3AgADAAoK+xzVCQD3AgAAAA==.Elletta:BAAANQAECgEIAQAAAA==.Elrae:BAAANQAECgYIBgAAAA==.',
Ep='Epoptes:BAAANQAECgQICQABNQAECgoKJwAEAJsMAA==.',
Eq='Eqo:BAABNQAECn8dAAMGAAkKERI8eQCvAQAGAAkKERI8eQCvAQAHAAEKxQl3dAA9AAAAAA==.',
Er='Erisian:BAAANQAECgUIBQAAAA==.Erkêios:BAABNQAECn8fAAIhAAkKFxSTMACqAQAhAAkKFxSTMACqAQAAAA==.Ersande:BAAANQAECgQIBwAAAA==.Ertz:BAAANQADCggICQAAAA==.',
Es='Escherichia:BAAANQAECgEJAQAAAA==.Estheban:BAABNQAECn8gAAQdAAkKOR/yDgBtAgAdAAkKOR/yDgBtAgAeAAMKFRbqFwBDAAAcAAEKQAtiUAAtAAAAAA==.',
Ev='Evengelist:BAABNQAECn8WAAMWAAkKIw9yEAAiAQAGAAgKlQtTWQCdAQAWAAUKdRFyEAAiAQAAAA==.',
Fa='Face:BAAANQAECgUIBwAAAA==.Fairgrim:BAAANQAECgQIBAAAAA==.Falin:BAABNQAECn9KAAIKAAoKqhswQwDLAgAKAAoKqhswQwDLAgAAAA==.Faqueuedark:BAABNQAECn8kAAIRAAoKyR9wDwDXAgARAAoKyR9wDwDXAgABNQAFFAMICwAIAMENAA==.Faqueueeight:BAACNQAFFH8LAAMIAAMKwQ24AgCWAAAIAAMKwQ24AgCWAAAOAAEKvAOUIAAxAAA1AAQKf08AAw4ACgpNIRoSAA4DAA4ACgq0HxoSAA4DAAgACgpvF8kIAKkBAAAA.Fatalyeeyee:BAAANQAECgIIAgABNQAECgoKfQARAC4SAA==.Fatsloth:BAAANQAECgYICAAAAA==.Fatébringer:BAAANQADCgYIDAABNQAECgEIAQAUAAAAAA==.Faulted:BAAANQADCgUIBQAAAA==.',
Fe='Feironos:BAAANQAECgEIAwAAAA==.Felcookies:BAAANQAECgYIEAAAAA==.Ferrick:BAAANQAECgIIAgAAAA==.',
Fi='Fiist:BAAANQAECggICAAAAA==.Fimtastic:BAABNQAECn8nAAIYAAkK2xM1UACfAQAYAAkK2xM1UACfAQAAAA==.Finasy:BAABNQAECn8yAAMiAAoKVCE1GwDVAgAiAAgKMiQ1GwDVAgAhAAgKtxQDNQCTAQAAAA==.Finbezy:BAAANQAECgQIAwAAAA==.Finnicka:BAAANQAECgEIAQAAAA==.Firen:BAAANQADCgcIFAAAAA==.Fireouch:BAAANQABCgIIAwAAAA==.Fistymisty:BAABNQAECn8cAAIjAAkKix98BAAvAwAjAAkKix98BAAvAwAAAA==.Fizeecian:BAAANQAECgQIBAAAAA==.',
Fl='Flaynpray:BAAANQADCgEIAQAAAA==.Fluffenstein:BAABNQAFFH8IAAIBAAQKmAIrHgCbAAABAAQKmAIrHgCbAAAAAA==.',
Fo='Foxrawruwu:BAABNQAECn8WAAIRAAgKqRqZNgCxAgARAAgKqRqZNgCxAgAAAA==.',
Fr='Frakk:BAAANQAECggIAQAAAA==.Freezegarr:BAACNQAFFH8KAAIVAAUK2Bl0GQD6AAAVAAUK2Bl0GQD6AAA1AAQKfzIAAhUACgq+IO0TAOYCABUACgq+IO0TAOYCAAAA.Frey:BAAANQAECgEIAQAAAA==.Frostgrave:BAAANQADCgEIAQAAAA==.Frostya:BAAANQADCgYIBgAAAA==.Frozzty:BAAANQAECgEIAQAAAA==.',
Fu='Fujibayashi:BAAANQAECgQICgAAAA==.Furearia:BAAANQABCgcICQAAAA==.Furrybowner:BAAANQAECggIDwAAAA==.',
Ga='Galeriel:BAACNQAFFH8UAAIGAAUKKB37DwBnAQAGAAUKKB37DwBnAQA1AAQKf0YAAgYACgoZJqcBACAEAAYACgoZJqcBACAEAAAA.Galileo:BAAANQAECgIIAgAAAA==.Gallethline:BAAANQAECgIIBQAAAA==.Ganjgotti:BAAANQADCgYICQAAAA==.Garault:BAAANQAECgYICgAAAA==.Gavered:BAAANQADCgMIBQAAAA==.',
Ge='Gekoni:BAAANQAECgYIEAAAAA==.Geonon:BAAANQADCggICAAAAA==.Geotracker:BAABNQAECn8eAAILAAgKpw73hwBfAQALAAgKpw73hwBfAQABNQADCggICAAUAAAAAA==.',
Gh='Ghorros:BAAANQADCgMIAwAAAA==.',
Gi='Gilgahmesh:BAABNQAECn8cAAIBAAoKmg/hagCHAQABAAoKmg/hagCHAQABNQAECgoKNgAJACUeAA==.',
Gl='Glowpwr:BAAANQADCgcIBwAAAA==.',
Go='Golruck:BAAANQAECggICgABNQAECgkJFQALAA4XAA==.Goolgame:BAACNQAFFH8SAAMSAAUKjR1lDACmAQASAAUKjR1lDACmAQAYAAMKXBXeFgDwAAA1AAQKfyoAAxIACgooIMo8AIICABIACApAIco8AIICABgABQq9G2SHAHgBAAAA.Goonthergg:BAAANQADCgYIBgAAAA==.Goothix:BAAANQADCgcJCAAAAA==.Gothmog:BAAANQADCgIIAgAAAA==.',
Gr='Grammarg:BAAANQADCgMIAwAAAA==.Grezzert:BAAANQADCgMIAwAAAA==.Grirr:BAAANQAECgIIBAAAAA==.Grothin:BAABNQAECn8zAAIYAAoKrxyXFADnAgAYAAoKrxyXFADnAgAAAA==.Gruldag:BAACNQAFFH8KAAIVAAQK7hM/IADdAAAVAAQK7hM/IADdAAA1AAQKfzgAAhUACgoxHCZdAMUCABUACgoxHCZdAMUCAAAA.Grullander:BAABNQAECn86AAIYAAoKkBOFQQDdAQAYAAoKkBOFQQDdAQAAAA==.Grullandyr:BAAANQAECgIIAgABNQAECgoKOgAYAJATAA==.',
Gu='Guiguiie:BAAANQADCggJEAAAAA==.',
Gw='Gwyndolynn:BAAANQADCgQIBQAAAA==.',
Ha='Haeheia:BAAANQADCgIIAgAAAA==.Haeldir:BAAANQADCgYIBQAAAA==.Hailey:BAEANQAECggIEwABNQAFFAcIDAAJAIoLAA==.Halter:BAAANQAECgIIAgAAAA==.Hapló:BAAANQABCgEIAQAAAA==.Haratvy:BAAANQAECgEIAQAAAA==.Hazzurd:BAABNQAECn8cAAILAAoKuBC8cwApAgALAAoKuBC8cwApAgAAAA==.',
He='Header:BAACNQAFFH8aAAIZAAcKwhmiBQACAgAZAAcKwhmiBQACAgA1AAQKfzAAAxkACgrlHgoMAFMCABkACgrlHgoMAFMCAAsABQrhCjP9AAoBAAAA.Healsorz:BAAANQADCgcIBwAAAA==.Heersbeest:BAAANQAECgEIAQAAAA==.Helane:BAAANQAECgEIAQAAAA==.Herkharu:BAAANQADCgcIBwAAAA==.Hermionee:BAABNQAECn81AAMVAAoKyhAElQBOAQAVAAkKygsElQBOAQAfAAMKUhbMHQC3AAAAAA==.Hetu:BAAANQABCgUIBAAAAA==.',
Hi='Hide:BAAANQAECgEIAQAAAA==.Himjongun:BAABNQAECn8mAAMOAAoKGhhzIwCyAQAOAAkKGhhzIwCyAQANAAEKAADddQAiAAAAAA==.',
Ho='Holya:BAAANQADCgEIAQABNQAFFAcIBwAMAA4AAA==.Holycowe:BAAANQAECggIDQAAAA==.Holykoi:BAABNQAECn9CAAIGAAoKcg70QwDwAQAGAAoKcg70QwDwAQAAAA==.',
Hr='Hroarr:BAABNQAECn8ZAAIiAAoKRSKTDgA7AwAiAAoKRSKTDgA7AwABNQAFFAUICgAVANgZAA==.',
Hu='Humancarnage:BAAANQADCgYIBwAAAA==.Huuh:BAAANQADCgUICgAAAA==.',
Hy='Hypaexia:BAAANQADCgIIAgAAAA==.',
['Hà']='Hàvoc:BAAANQADCggIDQAAAA==.',
['Hé']='Héboric:BAABNQAECn8tAAIJAAoKKh4+EQAJAwAJAAoKKh4+EQAJAwAAAA==.Hélbrecht:BAAANQAECgMIAwAAAA==.',
['Hÿ']='Hÿbrìd:BAAANQAECgYIDwAAAA==.',
Ia='Iamwho:BAAANQAECggICQAAAA==.Iatros:BAABNQAECn8nAAMEAAoKmwwRGQB2AQAEAAoKlgwRGQB2AQAKAAMKPQNOTwFLAAAAAA==.',
Id='Idkno:BAAANQAECgIIAgAAAA==.',
Ik='Ikara:BAAANQADCggICAABNQAECgoKJgAbAAwQAA==.Ikodiwa:BAAANQADCgUIBQAAAA==.',
Im='Imjustsaiyan:BAAANQADCgIIAgAAAA==.',
In='Indravax:BAABNQAECn8cAAIRAAkKQRSdeQD3AQARAAkKQRSdeQD3AQAAAA==.',
Io='Iorin:BAAANQADCggIBwABNQAFFAQIBgAOAJQBAA==.',
It='Itwasntmebru:BAAANQADCgYIFAAAAA==.',
Iv='Ivantis:BAAANQADCgYIFwAAAA==.Ivie:BAAANQAECgYIDQAAAA==.',
Iw='Iwonabhornee:BAAANQAECgEIAgAAAA==.',
Ja='Jaholypriest:BAACNQAFFH8KAAIGAAQKVBLeFQAaAQAGAAQKVBLeFQAaAQA1AAQKfyAAAgYACgpmFf5WAB4CAAYACgpmFf5WAB4CAAAA.Janjor:BAAANQAECgYICAAAAA==.Janjy:BAAANQADCgcIBwAAAA==.Jaypiea:BAABNQAECn8iAAMeAAkKTBUCCAAgAgAeAAgKTBUCCAAgAgAdAAgK8xC2FwDOAQAAAA==.',
Je='Jergall:BAAANQADCgUIBQAAAA==.Jettian:BAABNQAECn8XAAIkAAYKugx9QQDcAAAkAAYKugx9QQDcAAAAAA==.',
Ji='Jibz:BAAANQADCgEIAQAAAA==.',
Jj='Jjdruid:BAAANQAECgIIAgAAAA==.',
Jo='Johnathon:BAAANQAECgMIBAABNQAECgMIBAAUAAAAAA==.Jollygreene:BAAANQAECgEIAgAAAA==.Jonestu:BAAANQAECgQIBgAAAA==.Joyina:BAAANQADCgYIBgAAAA==.',
Jp='Jpgigacat:BAAANQAECgYICgAAAA==.Jpgigademon:BAAANQAECgMIBAAAAA==.Jpgigawolf:BAAANQAECggIDwAAAA==.',
Ju='Justakatt:BAAANQADCgIIAgAAAA==.Justicasia:BAAANQADCgQIBAABNQADCgYIBgAUAAAAAA==.',
Ka='Kadinsky:BAAANQADCgUIBQAAAA==.Kalivan:BAAANQADCgYIBwAAAA==.Kankimasamu:BAAANQADCgQIBAAAAA==.Karametra:BAAANQAECggIDwAAAA==.Karlldun:BAAANQAECgcIDwAAAA==.Kasmir:BAABNQAECn8iAAMRAAgKhw+blwCsAQARAAcK/xCblwCsAQAaAAEKLggUfQAwAAAAAA==.Kasnfriends:BAAANQADCgUIBQABNQAECggIIgARAIcPAA==.',
Ke='Kevv:BAACNQAFFH8PAAISAAYKIQMSEQDIAAASAAYKIQMSEQDIAAA1AAQKfzYAAxIACgphHNMXAIgCABIACgphHNMXAIgCABcAAQoAAPI7ABkAAAAA.Keyniron:BAABNQAECn/nAAIKAAkK4CV7AwBwAwAKAAkK4CV7AwBwAwAAAA==.',
Kh='Khogent:BAAANQADCgQIBAAAAA==.Khonsu:BAAANQAECgQIBAABNQAECggIDQAUAAAAAA==.Khrover:BAAANQADCgUIBQAAAA==.Khyle:BAAANQADCgYIBwAAAA==.',
Ki='Kijanajr:BAAANQADCgMIAgAAAA==.Killaarrow:BAABNQAECn9CAAILAAoKSAk9YgC6AQALAAoKSAk9YgC6AQAAAA==.Kiloton:BAAANQADCgQIBAAAAA==.Kindleos:BAAANQAECgEIAQAAAA==.',
Kk='Kkpriest:BAAANQADCgEIAQAAAA==.',
Kl='Klay:BAAANQAECgYIDQAAAA==.',
Km='Kmarte:BAEANQAECgYIEAABNQAECggIEAAUAAAAAA==.Kmarti:BAEANQAECggIEAAAAA==.Kmartt:BAEBNQAECn8mAAIKAAoKjhtxPABGAgAKAAoKjhtxPABGAgABNQAECggIEAAUAAAAAA==.',
Ko='Kosmic:BAAANQADCgcICQABNQAECgkJKQAiADsZAA==.Kosmicknight:BAABNQAECn8pAAMiAAkKOxk1NwAtAgAiAAkKOxk1NwAtAgAhAAEKAAA4twAoAAAAAA==.',
Kr='Kraggers:BAAANQAECgYIDQAAAA==.Kraggory:BAAANQAECgIIAgAAAA==.Kraggoryqt:BAAANQAECggIEgAAAA==.Kraggoryx:BAAANQAECgEIAQAAAA==.Krunclez:BAAANQAECggICgAAAA==.Kryesta:BAABNQAECn9IAAIYAAoKZiHIDwAWAwAYAAoKZiHIDwAWAwAAAA==.',
Kw='Kwarr:BAACNQAFFH8JAAIXAAYK0g6jAwA8AQAXAAYK0g6jAwA8AQA1AAQKf0MAAhcACgrOIjkDAG0DABcACgrOIjkDAG0DAAAA.',
La='Laganddecay:BAAANQABCggIGQAAAA==.Lalii:BAAANQAECgQIBAAAAA==.Lallatath:BAAANQADCgcIBwAAAA==.Lallypop:BAAANQAECgEIAQAAAA==.Lammoth:BAAANQAECgEIAwAAAA==.Lanemogsnick:BAAANQADCgQIBAAAAA==.Larissä:BAAANQAECgIIAgABNQAECgoKTAALANkWAA==.Layonhandsy:BAAANQAECgQIBAABNQAFFAQICQAiABYhAA==.',
Le='Leafu:BAAANQAECgMIAwABNQAECgoKLgAHAIQcAA==.Leasin:BAABNQAECn8uAAIHAAoKhBywEwDKAgAHAAoKhBywEwDKAgAAAA==.Lencreye:BAAANQADCgMIBAAAAA==.Lethendervis:BAAANQADCgYIDgAAAA==.',
Li='Lighthusk:BAAANQABCgQIBAAAAA==.Liliauna:BAABNQAECn8jAAIRAAcK+xr9aQAeAgARAAcK+xr9aQAeAgAAAA==.Lilibejeane:BAAANQADCgcIDgABNQAECgcIFQAOAOkRAA==.Lillynelazar:BAABNQAECn8cAAILAAoKBgUwtwCVAQALAAoKBgUwtwCVAQABNQAECgYICQAUAAAAAA==.Liloisback:BAABNQAECn8eAAIBAAoKUxbJaACNAQABAAoKUxbJaACNAQAAAA==.Lilsquirtboy:BAAANQADCgUIBQABNQAECgoKPAAFAGQfAA==.Linasonna:BAAANQAECgMIBwABNQAFFAUIEgASAI0dAA==.Linithara:BAACNQAFFH8GAAIOAAQKlAHSDwCWAAAOAAQKlAHSDwCWAAA1AAQKfyIAAw4ACgpXDQw3APgBAA4ACgodDAw3APgBAAgACArlCZwWAEMBAAAA.Littlehoosie:BAABNQAECn8VAAILAAkKDhcNUADuAQALAAkKDhcNUADuAQAAAA==.',
Lo='Lockersz:BAAANQADCgEIAQABNQAFFAcIFQAhAJ4TAA==.Lokedin:BAAANQAECgUIBQAAAA==.Loram:BAAANQAECgIIAQAAAA==.Lostbase:BAAANQAECgQIBAAAAA==.Lostgrip:BAAANQAECgYIEAAAAA==.',
Lu='Lucthedk:BAABNQAECn8WAAMkAAkK/xAzTADkAQAkAAkK/xAzTADkAQAhAAQKWwrPeADBAAAAAA==.Lukis:BAAANQAECgYICgAAAA==.Lunarpriest:BAAANQAECgQIBAAAAA==.Lunitari:BAAANQAECgEIAQAAAA==.Lunkbeck:BAAANQAECgEIAgAAAA==.Luxriel:BAAANQAECgEIAwAAAA==.',
Ly='Lyllith:BAAANQADCgIIAQABNQAECggIDQAUAAAAAA==.',
['Lø']='Lørd:BAABNQAECn8sAAMZAAoKxxx2IABLAgAZAAgKwhZ2IABLAgALAAcKVx7xZwCsAQAAAA==.',
Ma='Madik:BAAANQADCgcJCAAAAA==.Magicmegan:BAAANQAECgEIAQABNQAECggIFgARAKkaAA==.Mahoragax:BAAANQAECggIBQAAAA==.Malachí:BAAANQADCgUIBQABNQAECggIEgAUAAAAAA==.Maladin:BAAANQAECgIIAgAAAA==.Malkurim:BAAANQADCgEIAQAAAA==.Malvean:BAAANQADCgUICgAAAA==.Manasa:BAAANQAECgYIDwAAAA==.Marblack:BAAANQAECggICgAAAA==.Marceline:BAABNQAECn8qAAILAAoKWhaCOAA2AgALAAoKWhaCOAA2AgAAAA==.Marthahog:BAAANQAECgYIBgABNQAECgkJNQAlAOMVAA==.Marthog:BAABNQAECn81AAMlAAkK4xXICQD7AQAlAAkK4xXICQD7AQABAAMKNQaYGAEpAAAAAA==.Mashido:BAAANQADCgMIAwAAAA==.Matresstains:BAAANQAECgUICwAAAA==.',
Mc='Mcdermott:BAAANQAECgQIBgAAAA==.',
Me='Melanius:BAAANQAECgUIDQAAAA==.Melranis:BAAANQADCgcIDAAAAA==.',
Mi='Miluk:BAABNQAECn8VAAIVAAkKVw31kwBQAQAVAAkKVw31kwBQAQAAAA==.Misconduct:BAABNQAECn8cAAIOAAcKBhklNwAsAQAOAAcKBhklNwAsAQAAAA==.',
Mm='Mmins:BAAANQAECgYICgAAAA==.',
Mo='Montagne:BAAANQADCgQIBAAAAA==.Moomist:BAAANQAECgQIBgAAAA==.Moondarin:BAAANQABCgIIAgAAAA==.Moonfanna:BAAANQAECgQJBQAAAA==.Moonmx:BAAANQAECgYICgAAAA==.Moosesunaxe:BAAANQAECgEIAQAAAA==.Morriganth:BAAANQADCgEIAQAAAA==.',
Mu='Mujina:BAAANQAECgMIAwABNQAFFAUIEgACAKoeAA==.Murdamoose:BAAANQADCgIIAgAAAA==.Mustysponge:BAAANQADCgUIBwAAAA==.',
My='Mysteryx:BAABNQAECn8mAAIHAAoKYRSuGQCAAgAHAAoKYRSuGQCAAgAAAA==.Mystrbeast:BAAANQADCgQIBAAAAA==.',
['Mó']='Móxie:BAAANQADCgIIAQAAAA==.',
Na='Nahtan:BAAANQADCgYIDAAAAA==.Nammu:BAAANQADCgEIAQAAAA==.Nandisa:BAAANQADCgEIAQAAAA==.Naniwa:BAAANQAECgUICQAAAA==.Nawala:BAAANQAECgEIAQAAAA==.Nazaar:BAAANQADCgIIAgAAAA==.Nazendrov:BAEANQAECggICAABNQAECggICAAUAAAAAA==.Nazura:BAAANQADCgcIEQAAAA==.',
Ne='Nereza:BAAANQADCggIDAAAAA==.Nershog:BAAANQAECgEIAQAAAA==.Nesquip:BAAANQADCgYJBgAAAA==.Newil:BAAANQADCgYIBgAAAA==.',
Ni='Nightforday:BAABNQAECn8zAAMkAAkKiSDHIwC0AgAkAAkKiSDHIwC0AgAhAAIKUhVhjgB+AAAAAA==.Niko:BAAANQABCgUIBwAAAA==.Nishra:BAAANQADCggICAAAAA==.',
No='Noks:BAAANQAECggIBgAAAA==.Noktas:BAAANQAECgMIBQABNQAECggIBwAUAAAAAA==.Nokx:BAAANQAECggIBwAAAA==.Nominé:BAAANQADCgQIBgAAAA==.Nool:BAAANQADCgQIBwAAAA==.Norch:BAAANQAECgIJBAAAAA==.Notkory:BAAANQAECggICAAAAA==.Noux:BAAANQAECgUIBQAAAA==.',
Nu='Nube:BAAANQADCggIDAAAAA==.',
Ny='Nyababa:BAAANQAECgcIDAABNQAFFAUIEgACAKoeAA==.',
Oc='Octavia:BAAANQAECgIIAwAAAA==.',
Og='Ogora:BAAANQADCgQIBgAAAA==.',
Ok='Oki:BAAANQADCgMIBAAAAA==.Okktrål:BAAANQAECgYJCgAAAA==.Oktavius:BAABNQAECn8zAAIYAAoKpSEvBQCwAwAYAAoKpSEvBQCwAwAAAA==.',
Op='Ophysia:BAAANQAECgIIAgAAAA==.',
Or='Ordaka:BAAANQADCgYIBgAAAA==.Orkcansas:BAAANQAECgEIAQAAAA==.Orruutah:BAAANQADCgYIBgAAAA==.',
Os='Oskaia:BAAANQAECgYICwAAAA==.Osla:BAAANQAECgYIBQAAAA==.',
Ox='Oxytoecin:BAAANQAECgYIBgAAAA==.',
Pa='Paapineau:BAABNQAECn8XAAImAAkKQAeyHwAXAQAmAAkKQAeyHwAXAQAAAA==.Packel:BAAANQADCggICAABNQAECgoKOgAiADcZAA==.Packes:BAABNQAECn86AAIiAAoKNxm9FgAqAgAiAAoKNxm9FgAqAgAAAA==.Packs:BAAANQADCgYIBgABNQAECgoKOgAiADcZAA==.Pakkohruun:BAABNQAECn8gAAIKAAoKcxfXbgBSAgAKAAoKcxfXbgBSAgAAAA==.Pallywack:BAABNQAECn85AAIKAAoKZwzWkQBoAQAKAAoKZwzWkQBoAQAAAA==.Palussy:BAAANQADCgQIBAAAAA==.Parthima:BAABNQAECn88AAMgAAoKCQ55IQC8AQAgAAoKCQ55IQC8AQADAAEKdwnZcAAhAAAAAA==.Partysnaxx:BAAANQABCgEIAQAAAA==.',
Pe='Peppercat:BAAANQAECgQIBwAAAA==.Pertophos:BAAANQAECgUICQAAAA==.Pettigrew:BAAANQADCgIJAgAAAA==.',
Ph='Phantomclone:BAAANQAECgIIBQAAAA==.Phantomdh:BAAANQAECgEIAwAAAA==.Phantomghoul:BAAANQAECgUIBgAAAA==.Phated:BAAANQAECgEIAQAAAA==.Philomena:BAAANQADCgUICQAAAA==.',
Pi='Piggÿ:BAAANQAECgQIDgAAAA==.Piko:BAAANQADCggIDgAAAA==.Piyo:BAAANQADCgcIBwABNQAECgoKOgAiADcZAA==.',
Pl='Plankormast:BAAANQADCgEIAQAAAA==.',
Po='Poky:BAAANQAECgEIAQABNQAECgYICwAUAAAAAA==.Popena:BAAANQAECgMIBAAAAA==.Porkbuns:BAABNQAECn8oAAIVAAoKlhMrUAD4AQAVAAoKlhMrUAD4AQAAAA==.Potatogg:BAAANQAECgIIBgAAAA==.',
Pr='Praedor:BAAANQAECggICgAAAA==.Precious:BAAANQAECgEIAQAAAA==.Priestymon:BAABNQAECn8oAAIGAAoK3CFeCwBnAwAGAAoK3CFeCwBnAwABNQAFFAcIDwABAEIdAA==.Protdaddyy:BAAANQADCgUIBQAAAA==.',
Pw='Pwarr:BAACNQAFFH8JAAIlAAQKxwtEBADpAAAlAAQKxwtEBADpAAA1AAQKfyUAAyUACgoyITMEAL4CACUACgoyITMEAL4CAAEACAoPDxnSAE0BAAE1AAUUBggJABcA0g4A.',
Qa='Qamar:BAAANQADCgQIBAAAAA==.',
Qu='Quackadeen:BAAANQAECgIJAgAAAA==.Quaesitor:BAAANQAECgIIAwAAAA==.',
Qw='Qwarr:BAAANQAECgUICAABNQAFFAYICQAXANIOAA==.',
Ra='Raamey:BAAANQADCgIIAgAAAA==.Raathya:BAABNQAECn8bAAILAAkKyg/1hwD7AQALAAkKyg/1hwD7AQAAAA==.Raeljin:BAABNQAECn8ZAAISAAgKLxlaQQBwAgASAAgKLxlaQQBwAgAAAA==.Ragetastick:BAAANQAECggICQAAAA==.Raihua:BAAANQADCgYIBgAAAA==.Rampagarex:BAAANQADCgYIBgAAAA==.Rangoz:BAAANQAECgUIDwAAAA==.Rar:BAABNQAECn8kAAILAAoKCCB0GADCAgALAAoKCCB0GADCAgAAAA==.Ratgamerlol:BAACNQAFFH8FAAILAAIKbyCJFQC+AAALAAIKbyCJFQC+AAA1AAQKfzUAAgsACQrJJEgqAPACAAsACQrJJEgqAPACAAAA.Ravnur:BAAANQADCggICAAAAA==.Rayennagrom:BAAANQAECgIIBAAAAA==.',
Re='Reagent:BAAANQADCgMIAwAAAA==.Reckrunner:BAABNQAECn8qAAQRAAoKKBEcXQCDAQARAAgKHxIcXQCDAQAbAAIKNwdLLgA5AAAaAAEKZwrmMwAuAAAAAA==.Redlocks:BAAANQAECgYICwAAAA==.Renault:BAAANQADCgMIAwAAAA==.Reneana:BAAANQAECgUIDAAAAA==.Restbo:BAACNQAFFH8KAAIYAAUKkxyWBwCxAQAYAAUKkxyWBwCxAQA1AAQKfykAAhgACgqrI3QLAGUDABgACgqrI3QLAGUDAAE1AAUUBggVABYAHREA.',
Rg='Rgent:BAAANQADCgYIBgABNQADCgYIBwAUAAAAAA==.',
Rh='Rhianonn:BAAANQAECgYIEAABNQAECgYIDQAUAAAAAA==.',
Ri='Riaslock:BAAANQAECgEJAQAAAA==.Riaswar:BAAANQADCgEIAQAAAA==.Richardluis:BAABNQAECn8VAAISAAcKwwrPoABVAQASAAcKwwrPoABVAQAAAA==.Rinehardtt:BAABNQAECn82AAIJAAoKJR4OIwDgAgAJAAoKJR4OIwDgAgAAAA==.Riverstyxx:BAAANQADCgYIEQAAAA==.Rivër:BAAANQADCggIHwAAAA==.',
Ro='Robbell:BAABNQAECn8zAAILAAoKkRznIgCLAgALAAoKkRznIgCLAgAAAA==.Rococote:BAAANQAECggIEgAAAA==.Roggehere:BAAANQAECgIIAgAAAA==.Rokyman:BAAANQAECgcIEQAAAA==.Roldazark:BAAANQABCgEIAQAAAA==.Roonsia:BAAANQADCgQIBQAAAA==.Rootsie:BAAANQADCgYJFwAAAA==.Roselynn:BAABNQAECn8ZAAIDAAgKbRasHwAuAgADAAgKbRasHwAuAgAAAA==.Rouby:BAAANQAECgEIAgAAAA==.Roughlight:BAAANQADCgMIAwAAAA==.',
Ru='Ruerl:BAABNQAECn8YAAIKAAgKTAqxzACCAQAKAAgKTAqxzACCAQAAAA==.Runentug:BAACNQAFFH8JAAIiAAQKFiHtDQB1AQAiAAQKFiHtDQB1AQA1AAQKfxsAAiIACQqSJAkNAEkDACIACQqSJAkNAEkDAAAA.Rustyspell:BAAANQADCgIIAgAAAA==.',
Ry='Ryumapriest:BAAANQABCgEIAQAAAA==.',
['Rî']='Rîft:BAAANQADCgEIAQAAAA==.',
Sa='Sanddora:BAAANQADCgIIAgAAAA==.Sanlordriel:BAAANQAECgMIAwAAAA==.Saramon:BAAANQADCggIKQAAAA==.Sarios:BAAANQADCgQIAwAAAA==.Sassiberry:BAAANQADCgcIEQAAAA==.Sassitude:BAAANQADCgcIFQAAAA==.Satiiva:BAAANQADCggICAAAAA==.',
Sc='Scarlos:BAAANQABCgMIAwAAAA==.Screamdying:BAAANQABCgIIAgAAAA==.Scrembiblion:BAABNQAECn8rAAInAAkKkB0tAQDbAgAnAAkKkB0tAQDbAgAAAA==.',
Sd='Sdhoscillate:BAAANQADCgYIBgAAAA==.',
Se='Seins:BAAANQADCgYIBgAAAA==.Semillin:BAAANQAECgcIEQAAAA==.Senseitional:BAAANQAECgEIAQABNQAECggIMQAPADUiAA==.Sensjei:BAABNQAECn8UAAIFAAgKlQbGLgDuAAAFAAgKlQbGLgDuAAAAAA==.Sentarry:BAAANQAECgMIAwABNQAFFAUICgAVANgZAA==.Separatist:BAAANQADCgMJAwAAAA==.Serendibitty:BAAANQADCgMIAwABNQAECgUICQAUAAAAAA==.',
Sg='Sgtbreezy:BAAANQADCgcIBwAAAA==.',
Sh='Shadey:BAAANQADCgIIAgAAAA==.Shambulance:BAAANQAECgcIDQAAAA==.Sharuerl:BAAANQADCgcIBwAAAA==.Shawshaa:BAAANQADCgYIBgAAAA==.Shazi:BAEANQAECggICAAAAA==.Shiftroid:BAAANQADCgMIBgAAAA==.Shinyivie:BAABNQAECn8eAAIKAAkKYwX85ABRAQAKAAkKYwX85ABRAQAAAA==.Shiverchill:BAAANQABCgEJAQAAAA==.Shockrock:BAAANQADCgEIAQAAAA==.Shouzhe:BAAANQADCgUIBQAAAA==.Shroomjuice:BAAANQAECggIDwAAAA==.Shuthehealup:BAAANQAECgEIAgAAAA==.Shãdøwzzxz:BAAANQAECgUIDAAAAA==.',
Si='Sildenafil:BAAANQADCgIIAgAAAA==.Silessra:BAAANQADCggICAAAAA==.',
Sk='Skogr:BAAANQADCgIIAQABNQADCgUIBQAUAAAAAA==.Skädoosh:BAAANQAECgEIAQAAAA==.',
Sl='Slapshappy:BAAANQAECggICgAAAA==.',
Sm='Smallhorn:BAAANQAECgEIAgAAAA==.Smokeyhaze:BAAANQAECgYIDgAAAA==.Smokin:BAABNQAECn8oAAILAAkKMgqPiwBXAQALAAkKMgqPiwBXAQAAAA==.Smolther:BAAANQADCgcIBwAAAA==.Smores:BAAANQAECgEIAQAAAA==.',
Sn='Sneech:BAAANQAECgYIBwAAAA==.Snikrot:BAAANQADCgcIBwAAAA==.Snowbvnni:BAAANQADCgQIBAAAAA==.',
So='Sofarkinghi:BAAANQAECgEIAgAAAA==.Sollamor:BAAANQAECgMIBAAAAA==.Solomonk:BAABNQAECn8tAAIjAAgKAg6aEADnAAAjAAgKAg6aEADnAAAAAA==.Solomus:BAABNQAECn8rAAMPAAkKuQ3rIgAzAQAPAAkKuQ3rIgAzAQAgAAQKWwF5fQAyAAAAAA==.Sonal:BAABNQAECn8XAAQhAAcKtgocXQAzAQAhAAcKtQkcXQAzAQAiAAUK6QezjgDIAAAkAAEKAAC9+AAfAAAAAA==.Soneca:BAAANQAECgIIBQAAAA==.Soter:BAAANQAECggIEgAAAA==.',
Sp='Spitzonit:BAAANQAECgUIBQAAAA==.',
Sq='Squeaph:BAAANQAECgcIDwAAAA==.',
St='Stararia:BAAANQADCggIDwAAAA==.Stelltrain:BAAANQABCgIIBAAAAA==.Stoploss:BAAANQAECgEIAQAAAA==.Stormiee:BAABNQAECn8pAAIYAAkKqxhSOAB+AgAYAAkKqxhSOAB+AgABNQAECgYIDQAUAAAAAA==.Stormroid:BAAANQAECgUICQAAAA==.Sttorm:BAAANQADCgUIBQAAAA==.Styles:BAABNQAECn8nAAIKAAcK/AwgzQD/AAAKAAcK/AwgzQD/AAAAAA==.',
Su='Sugarontop:BAAANQADCgQIBAAAAA==.Sunmx:BAABNQAECn8zAAMBAAoKPR9zKQAVAwABAAoKtxxzKQAVAwACAAYKyiAcCQDIAQAAAA==.Superdark:BAAANQADCgIIAgAAAA==.Supersquidd:BAAANQADCgMIAwAAAA==.',
Sw='Swurve:BAEANQAECgQIBwAAAA==.Swurves:BAAANQAECgYIBwABNQAECgcIEgAUAAAAAA==.',
Sz='Szucs:BAAANQADCgMIAwAAAA==.',
['Sã']='Sãvãge:BAAANQADCgQIBAAAAA==.',
Ta='Tabiji:BAEANQAECggICAAAAA==.Tadpole:BAAANQADCggIHAAAAA==.Taedrum:BAABNQAECn8aAAIkAAgKEwiCNAAiAQAkAAgKEwiCNAAiAQAAAA==.Taerror:BAAANQADCgIIAgAAAA==.Talegos:BAAANQAECgMJAwAAAA==.Talonfel:BAAANQADCgQIBAABNQAECgkJOQATACUjAA==.Taloning:BAAANQADCgYIBgABNQAECgkJOQATACUjAA==.Talonstryke:BAABNQAECn85AAITAAkKJSOfAwB2AwATAAkKJSOfAwB2AwAAAA==.Tauraxs:BAAANQADCgEIAQAAAA==.Tazrak:BAAANQAECgUIBgABNQAECgoKLgARAIoKAA==.',
Te='Teatoh:BAAANQADCgcIBwAAAA==.Teenjus:BAAANQABCgMIAwABNQAECggIJQAEAPwZAA==.Tenseiga:BAABNQAECn8iAAMKAAoKVhnpOQBQAgAKAAkKVhnpOQBQAgAEAAoKJgrSLAB2AQABNQAFFAUIDgAIAPMbAA==.Testsubjectz:BAACNQAFFH8FAAIBAAUKyBtyEQD0AAABAAUKyBtyEQD0AAA1AAQKfxUAAgEACAqUJt4OABADAAEACAqUJt4OABADAAAA.Tevers:BAAANQAECgEIAgAAAA==.',
Th='Thaalion:BAAANQAECgIIAQAAAA==.Thalantier:BAAANQADCgMIBgAAAA==.Thardal:BAABNQAECn8mAAMbAAoKDBBeCwC1AQARAAoKMg2RfADvAQAbAAkKEhBeCwC1AQAAAA==.Thebigshot:BAAANQAECgMIBQAAAA==.Theenforcer:BAACNQAFFH8MAAIKAAUK5wXvFQC3AAAKAAUK5wXvFQC3AAA1AAQKf1wAAgoACgpJE29WAPMBAAoACgpJE29WAPMBAAAA.Thegreekbeas:BAAANQADCgUIBQAAAA==.Theguyfurry:BAAANQAECgEIAQAAAA==.Theonepanda:BAAANQAECgUICQAAAA==.Thetzin:BAABNQAECn8eAAIVAAYKJwNkYQHxAAAVAAYKJwNkYQHxAAAAAA==.Theunite:BAAANQADCggICAAAAA==.Thickhobo:BAAANQADCgUICQAAAA==.Thidwick:BAABNQAECn8xAAIPAAgKNSJ9CACRAgAPAAgKNSJ9CACRAgAAAA==.Thingtwø:BAABNQAECn8YAAIhAAoK9RxqEQCfAgAhAAoK9RxqEQCfAgAAAA==.Thistle:BAAANQADCgYIDAABNQAECgkJIQAVADQMAA==.Thraggs:BAAANQADCgcICAAAAA==.Thunderfist:BAAANQADCggIBwAAAA==.',
Ti='Titanslay:BAAANQADCgEIAQAAAA==.Titø:BAAANQADCgYIDQABNQADCgcIBwAUAAAAAA==.',
Tm='Tmryuki:BAAANQAECggICgAAAA==.',
To='Tokadin:BAAANQAECgIIAgAAAA==.Tomorrow:BAAANQAECgYICwAAAA==.Topzee:BAAANQAECgQIBAAAAA==.Totalljoe:BAABNQAECn8UAAIKAAkKJBDxfQCRAQAKAAkKJBDxfQCRAQAAAA==.Totoo:BAACNQAFFH8HAAIMAAcKDgB6FwAhAAAMAAcKDgB6FwAhAAA1AAQKfxMAAgwABwqbFfQqAGwBAAwABwqbFfQqAGwBAAAA.Touchmablade:BAAANQAECgUIBgAAAA==.',
Tr='Traedarra:BAAANQADCgIIAgAAAA==.Tralis:BAEANQADCggIDgABNQAECggICAAUAAAAAA==.Tranarra:BAABNQAECn9mAAIRAAoKrh6SEgDAAgARAAoKrh6SEgDAAgAAAA==.Traylo:BAABNQAECn8uAAILAAoKjxINRgALAgALAAoKjxINRgALAgAAAA==.',
Tv='Tvak:BAABNQAECn8ZAAIKAAcKcxfjtAC1AQAKAAcKcxfjtAC1AQAAAA==.',
Tw='Twistedsham:BAAANQAECggICQAAAA==.Twopump:BAABNQAECn83AAIKAAoKYwhrrwAxAQAKAAoKYwhrrwAxAQAAAA==.',
['Tó']='Tónka:BAAANQADCgcIBwAAAA==.',
Ul='Ulhae:BAAANQABCgQIBAAAAA==.Ulinova:BAAANQAECgcIDwAAAA==.',
Um='Umbressa:BAAANQADCgMIAwABNQAECgoKNQALAAkcAA==.Umbryx:BAAANQADCgIIAgABNQAECgoKLgARAIoKAA==.',
Un='Unholly:BAAANQAECgIJAwAAAA==.',
Ur='Uroro:BAACNQAFFH8IAAMYAAUKfhKnEQD+AAAYAAUKfhKnEQD+AAAXAAEK1QUpCQBEAAA1AAQKfzQAAxgACgo1Ik0YABIDABgACgo1Ik0YABIDABIAAQoAAONCASwAAAE1AAUUBQgSAAIAqh4A.',
Uu='Uu:BAAANQABCgIIAgAAAA==.',
Va='Vaiden:BAAANQABCgEIAQAAAA==.Vainqueur:BAABNQAECn8kAAIdAAkKwxpTBwD1AQAdAAkKwxpTBwD1AQAAAA==.Valienni:BAAANQAECgEIAQAAAA==.Vanderdemon:BAAANQADCgMIAwAAAA==.Vanderlight:BAAANQADCgUJCQAAAA==.Vandernum:BAAANQAECggICAAAAA==.Vandersus:BAAANQADCggIBQAAAA==.Varm:BAAANQADCggICAAAAA==.',
Ve='Velakai:BAAANQABCgQIBAAAAA==.Verlasky:BAAANQAECgQIBAABNQAECgoKOAAgAAgPAA==.Vervaeda:BAAANQADCgQIBAAAAA==.Verymelon:BAAANQAECgQIBgABNQAFFAMIBgASAFYOAA==.Vestele:BAAANQADCggIDwAAAA==.',
Vg='Vgx:BAABNQAECn8qAAIhAAkKnA40QQBWAQAhAAkKnA40QQBWAQAAAA==.',
Vi='Vielitre:BAAANQAECgMIAwAAAA==.Vigossfel:BAAANQADCgMIBwAAAA==.Viintage:BAABNQAECn80AAIVAAoKCBVDUAD4AQAVAAoKCBVDUAD4AQAAAA==.Vintige:BAAANQAECgEIAQABNQAECgoKNAAVAAgVAA==.Viridius:BAAANQADCgMIBQAAAA==.Vishouspayne:BAABNQAECn8XAAILAAYKFwaC4gCsAAALAAYKFwaC4gCsAAAAAA==.',
Vo='Voidshank:BAAANQAECgEIAgAAAA==.Vorath:BAAANQADCgQIBAAAAA==.',
Vy='Vyolence:BAAANQAECgQIBQABNQAECgoKLgAHAIQcAA==.',
['Vä']='Väelün:BAABNQAECn8lAAMNAAgKFBHqIwBFAQANAAgKFBHqIwBFAQAOAAEKawTsmwAnAAAAAA==.',
['Vÿ']='Vÿ:BAABNQAECn8YAAILAAYKfQh3xQDiAAALAAYKfQh3xQDiAAAAAA==.',
Wa='Wachoosh:BAAANQAECgUIBwAAAA==.Waidmanns:BAABNQAECn81AAMLAAoKCRzAJwD5AgALAAoKCRzAJwD5AgAoAAMKuwldDQB8AAAAAA==.Walmartstaff:BAAANQADCgUIBQAAAA==.Warfable:BAAANQADCgIIAgAAAA==.',
Wg='Wgnmd:BAAANQAECgQIBQAAAA==.',
Wh='Wham:BAAANQAECgIIAwAAAA==.Whatsaggro:BAABNQAECn8lAAIkAAgKhwk9aABwAQAkAAgKhwk9aABwAQABNQAECgkJFAAKACQQAA==.Whatyamean:BAABNQAECn8YAAMYAAgKQganjQDcAAAYAAgKQganjQDcAAASAAEKbgFg9AAdAAAAAA==.Whiteeyedemo:BAAANQADCgYIBgAAAA==.Whoami:BAAANQAECggIDAAAAA==.Whoangry:BAABNQAECn8iAAMMAAkKHhMdQgCtAQAmAAkKgQ+6RQCwAQAMAAgKCRAdQgCtAQAAAA==.Whomonk:BAAANQAECgIIBAAAAA==.',
Wi='Wickedchick:BAAANQAECgEIAQAAAA==.Willowknight:BAAANQADCgYICgAAAA==.Wimdy:BAAANQADCgMIAwAAAA==.Winterknight:BAAANQADCgUICwAAAA==.',
Wr='Wrenn:BAAANQAECgcICAAAAA==.Wrongname:BAAANQAECgYIBwAAAA==.',
Wu='Wumba:BAAANQAECgMIAwAAAA==.',
Xa='Xanthe:BAAANQADCggIBwAAAA==.',
Xf='Xfloki:BAAANQADCgQIBAAAAA==.',
['Xß']='Xß:BAAANQADCgIJBAAAAA==.',
Ya='Yakpriest:BAAANQADCgcIDAAAAA==.Yawg:BAEANQADCgYIBgABNQAECgoKPQALAOseAA==.',
Yd='Ydgktt:BAAANQADCgMIBAAAAA==.',
Yn='Ynhük:BAAANQADCgMIAwAAAA==.',
Yo='Yogsothoth:BAEBNQAECn89AAILAAoK6x7CHwCaAgALAAoK6x7CHwCaAgAAAA==.',
Yr='Yrdenal:BAAANQADCgcICQAAAA==.',
Yu='Yugalipdeez:BAAANQAECgEIAgAAAA==.Yulian:BAAANQAECgUIDwAAAA==.',
Za='Zaartyn:BAABNQAECn82AAIRAAoKGSKjEwA+AwARAAoKGSKjEwA+AwAAAA==.Zaater:BAAANQAECgcICgAAAA==.Zalin:BAAANQAECgEIAQABNQAECgoKJgAbAAwQAA==.Zanki:BAAANQAECgUICwAAAA==.',
Ze='Zeebeth:BAABNQAECn8YAAILAAkKfw8wjQDwAQALAAkKfw8wjQDwAQAAAA==.Zefi:BAAANQAECgcIAgAAAA==.Zellek:BAAANQADCgYIBgAAAA==.Zenbu:BAAANQADCgIIAgAAAA==.Zeroasy:BAAANQADCgIIAgABNQAECgoKMgAiAFQhAA==.Zerokai:BAAANQAECgQIBQAAAA==.Zeztz:BAAANQAECgcIDAAAAA==.',
Zo='Zomlo:BAAANQAECgQIBQAAAA==.Zooli:BAAANQADCggICAAAAA==.Zorosenpai:BAAANQADCgcIEQABNQAECggIIgAhAJ8KAA==.',
Zu='Zuggernaught:BAAANQAECgUIDAABNQAECggIDQAUAAAAAA==.',
Zy='Zynokyno:BAAANQADCgYIBgAAAA==.',
['Át']='Átomic:BAAANQADCgUIAwAAAA==.',
['Ân']='Ânimosity:BAAANQADCgIIAgAAAA==.',
['Âr']='Ârtemis:BAAANQAECgQIBAABNQAFFAUIDgAIAPMbAA==.',
['Ís']='Ísvala:BAAANQADCgYIBgAAAA==.',
['ßu']='ßuzzibee:BAAANQAECgYIDwABNQAECgcIHAAOAAYZAA==.',
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
