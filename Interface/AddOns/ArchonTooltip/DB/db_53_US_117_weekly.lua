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

local lookup = {'Warrior-Arms','Warrior-Fury','Druid-Restoration','Paladin-Protection','Monk-Windwalker','Priest-Holy','DemonHunter-Vengeance','Paladin-Holy','Paladin-Retribution','Hunter-BeastMastery','Rogue-Subtlety','DeathKnight-Unholy','DemonHunter-Havoc','Druid-Guardian','Druid-Feral','Warlock-Demonology','Shaman-Elemental','Monk-Mistweaver','Priest-Shadow','Mage-Arcane','Unknown-Unknown','Priest-Discipline','Shaman-Enhancement','Shaman-Restoration','Hunter-Marksmanship','DemonHunter-Devourer','Warlock-Destruction','Warlock-Affliction','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Mage-Frost','Druid-Balance','DeathKnight-Frost','DeathKnight-Blood','Monk-Brewmaster','Warrior-Protection','Rogue-Assassination','Mage-Fire','Hunter-Survival',}
local provider = {region='US',realm='Hakkar',name='US',type='weekly',zone=53,date='2026-10-27',data={Ac='Aceshaman:BAAANQADCgIIAgAAAA==.Acheros:BAAANQADCgMIAwAAAA==.Actionfigure:BAACNQAFFH8KAAIBAAQKyCCkFQB7AQABAAQKyCCkFQB7AQA1AAQKfzAAAwIACgqCJMwCAI8CAAEACgonH2A3AOYCAAIACAptJMwCAI8CAAAA.',
Ad='Adielia:BAABNQAECn8jAAIDAAgK4hvHEwDsAQADAAgK4hvHEwDsAQAAAA==.Adurzin:BAAANQADCgIIAgAAAA==.',
Ae='Aeralina:BAAANQADCgUJBQAAAA==.Aeri:BAAANQADCgIIAwAAAA==.Aevalaana:BAAANQAECgYICQAAAA==.',
Ag='Agiermodinn:BAAANQADCgYICgAAAA==.',
Ah='Ahnho:BAAANQADCggICgAAAA==.',
Ai='Aidandrius:BAAANQADCgMIAwAAAA==.Aimeeleigh:BAAANQAECgQIBgABNQAECggIHgAEAPwZAA==.Airflash:BAACNQAFFH8MAAIFAAUKEx4tCQBFAQAFAAUKEx4tCQBFAQA1AAQKfzkAAgUACAo/JasHAFQDAAUACAo/JasHAFQDAAAA.Aiøn:BAAANQADCgcIBwAAAA==.',
Ak='Akutagawa:BAABNQAECn8dAAIGAAkKuBgVKgAgAgAGAAkKuBgVKgAgAgABNQAFFAUIDQAHAPMbAA==.',
Al='Alexandriia:BAAANQAECgEIAQAAAA==.Alexious:BAACNQAFFH8SAAIEAAUKrR8CAwABAQAEAAUKrR8CAwABAQA1AAQKfzMAAgQACgqFIk4HAC4DAAQACgqFIk4HAC4DAAAA.Aloonarn:BAAANQAECgYIEgAAAA==.Alopix:BAAANQAECgcIEAAAAA==.Alulla:BAACNQAFFH8SAAMCAAUKqh7rAQD0AAABAAQKqh5tFwBnAQACAAMKwRjrAQD0AAA1AAQKfx8AAwIACgrpIK0KAB0CAAEACQr5HyJJAK4CAAIABwoTIq0KAB0CAAAA.Alunira:BAABNQAECn82AAMIAAoKYR/gGAAVAwAIAAoKYR/gGAAVAwAJAAYKbhYTzQCBAQAAAA==.',
Am='Amberrfrost:BAAANQAECgQICgAAAA==.Amize:BAAANQADCgYIBgAAAA==.Ampz:BAAANQAECgQIAgAAAA==.',
An='Anabee:BAAANQADCggIDgAAAA==.Angelicshy:BAAANQADCgQIBAAAAA==.Angryhtr:BAABNQAECn8UAAIKAAcKGhkydgAjAgAKAAcKGhkydgAjAgAAAA==.Angryshh:BAAANQAECgMIAwAAAA==.Angrywar:BAABNQAECn8bAAIBAAgKHxL9nADUAQABAAgKHxL9nADUAQAAAA==.Anharon:BAAANQADCgcICgAAAA==.Ansatz:BAAANQAECgEICgABNQAECgoKNAAKAAMaAA==.',
Ap='Apokalypto:BAAANQAECgQICAAAAA==.',
Ar='Arbiterbinky:BAAANQADCgUIBQAAAA==.Ardå:BAAANQADCgEIAQAAAA==.Areina:BAAANQAECgEIAQAAAA==.Argangus:BAAANQADCgYIDwAAAA==.Arrowganz:BAAANQADCgYIBgAAAA==.Arthan:BAAANQAECgMIBgAAAA==.Arthannix:BAAANQAECgEIAQAAAA==.',
As='Assine:BAAANQAECgEIAQABNQAFFAcIBwALAA4AAA==.Astanis:BAAANQAECgUICgAAAA==.Asteriia:BAAANQAECgcIEwAAAA==.Astralyn:BAAANQAECgEIAQAAAA==.',
Au='Augito:BAAANQABCgIIAgAAAA==.',
Av='Averettara:BAAANQAECgIIBwABNQAECggIJQAMAIcJAA==.',
Az='Azarazan:BAAANQADCgYIDgAAAA==.Azka:BAABNQAECn8kAAIJAAoKkx3uLwAKAwAJAAoKkx3uLwAKAwAAAA==.Azkadk:BAAANQADCgYIBgAAAA==.',
Ba='Babybilly:BAABNQAECn8eAAMEAAgK/BnBHQD7AQAEAAgK/BnBHQD7AQAJAAMKkAOgcAFtAAAAAA==.Baelmon:BAAANQAECgIIBAAAAA==.Baludis:BAAANQADCgcIEQAAAA==.Bamff:BAAANQAECgUIDQAAAA==.Bamfpally:BAAANQAECgEIAQAAAA==.Barreack:BAAANQADCgYICAAAAA==.Bast:BAACNQAFFH8NAAIHAAUK8xtQAQDeAAAHAAUK8xtQAQDeAAA1AAQKfzgAAwcACgoQJZYAAE0DAAcACgoQJZYAAE0DAA0ABQpFE2pSAEoBAAAA.Basthara:BAABNQAECn8lAAMOAAoKciFiAwD+AgAOAAoKciFiAwD+AgAPAAEKVAIbUwAGAAABNQAFFAUIDQAHAPMbAA==.',
Be='Beckianslip:BAAANQADCgUIBQAAAA==.Belphegor:BAAANQAECgYICAABNQAECgoKJQAQAOMJAA==.Benif:BAACNQAFFH8NAAIBAAYKVRy6DwC7AQABAAYKVRy6DwC7AQA1AAQKfzMAAgEACgoXJf8IAKwDAAEACgoXJf8IAKwDAAAA.Benjaquel:BAAANQADCgQIBAAAAA==.Bertorod:BAABNQAECn8YAAIRAAkKqxUfWAAbAgARAAkKqxUfWAAbAgAAAA==.Bewblover:BAAANQAECgEIAgAAAA==.',
Bi='Bigbitehotdo:BAABNQAECn86AAMFAAoKZB+MDgD3AgAFAAoKZB+MDgD3AgASAAEK3wHaVAAgAAAAAA==.Bighoney:BAAANQAECgIIAgAAAA==.Bigtommybuns:BAAANQADCgUIBQAAAA==.Binkyfiasco:BAAANQAECgEIAQAAAA==.Binny:BAAANQADCgYIBgAAAA==.Birdiewordie:BAAANQAECgEIAQAAAA==.',
Bl='Bloodeie:BAAANQADCgQIBAAAAA==.Bloodstoned:BAAANQAECgUIDwAAAA==.Blueboy:BAABNQAECn8eAAITAAoKJgz0EQCrAQATAAoKJgz0EQCrAQAAAA==.',
Bo='Boffadz:BAAANQAECggIEwAAAA==.Bonewand:BAAANQAECgEIAgAAAA==.Bonewrath:BAAANQAECgEIAgAAAA==.Boogat:BAAANQAECgQIBQAAAA==.Bovillus:BAAANQAECgQIBQAAAA==.',
Br='Braugorlle:BAAANQAECgYICAABNQAFFAUIEgARAI0dAA==.Breadscrumb:BAAANQADCgUJBQAAAA==.Briandejay:BAAANQAECgIIBAAAAA==.Bridrystina:BAAANQADCgQIBAAAAA==.Brixlo:BAAANQAECgEIAQAAAA==.',
Bu='Buffmuffin:BAAANQAECgIIAgAAAA==.Burblbiblr:BAAANQAECgEIAQAAAA==.Bustrdugles:BAAANQADCgUIBQAAAA==.',
Bw='Bwazakki:BAAANQADCgMIAwAAAA==.Bwr:BAAANQADCgMIAwAAAA==.',
['Bü']='Bübbawrap:BAAANQAECgQICAAAAA==.',
Ca='Cambrier:BAABNQAECn9EAAMBAAoKpSGpDwDoAgABAAoKXSCpDwDoAgACAAgKoiAIBQDbAgAAAA==.Cameraop:BAABNQAECn8XAAIUAAcKKwj2EgFtAQAUAAcKKwj2EgFtAQAAAA==.Candyapples:BAAANQADCgUIBQAAAA==.Capnsoap:BAAANQADCgYIBgABNQABCgEIAQAVAAAAAA==.Capnsöap:BAAANQAECgIIAgABNQABCgEIAQAVAAAAAA==.Capriestsun:BAAANQAECggICwAAAA==.Cardinal:BAAANQAECgEIAwAAAA==.Carynden:BAAANQAECgUIBQAAAA==.Castbo:BAAANQAECgcIEwABNQAFFAUIFAAWADwRAA==.',
Ce='Celilinia:BAAANQAECgIIAgAAAA==.Cellesstia:BAAANQADCgMIBQABNQAECgQIBgAVAAAAAA==.',
Ch='Chaiharder:BAAANQAECgEIAQAAAA==.Chalada:BAAANQADCgEIAQABNQAFFAcIBwALAA4AAA==.Chalastorm:BAAANQAECggIAQABNQAFFAcIBwALAA4AAA==.Charknight:BAAANQADCgUIBQAAAA==.Chatdodu:BAAANQADCgUIBQAAAA==.Chatnoir:BAAANQAECgYIEAAAAA==.Chestock:BAAANQADCgYIBgAAAA==.Chuggz:BAAANQAECgQIBgAAAA==.',
Cl='Clonetastic:BAAANQADCggICAAAAA==.Clumsycarl:BAAANQADCgIIAgAAAA==.',
Cm='Cmx:BAAANQADCgUIBQAAAA==.',
Co='Codith:BAAANQAECgQIBQAAAA==.Coldlock:BAAANQADCgQIBAAAAA==.Colesiaw:BAAANQADCgQIBgAAAA==.Coraeze:BAAANQADCgEIAQAAAA==.',
Cp='Cptcrunch:BAAANQAECgIIBAABNQAECgkJKAARANQbAA==.',
Cr='Crais:BAAANQAECgYIBgAAAA==.Creek:BAAANQABCgYIBgABNQAECgoKKQANAFYfAA==.Crnogorac:BAAANQAECggIAQAAAA==.Crotchgoblim:BAAANQADCgcIFAAAAA==.Cryodormu:BAAANQAECgMJAwAAAA==.',
Cu='Cubo:BAAANQAECgEIAwAAAA==.Cuddlesworth:BAABNQAECn8lAAIQAAoK4wlgSQCIAQAQAAoK4wlgSQCIAQAAAA==.',
Cw='Cwarr:BAAANQAECgIIAgABNQAFFAYICQAXANIOAA==.',
Cy='Cyrcee:BAAANQADCgUIBQABNQAECgQIBgAVAAAAAA==.',
Da='Daddyluis:BAAANQADCggICgAAAA==.Dadstonks:BAAANQAECgEIAQAAAA==.Dagoujiao:BAABNQAECn8ZAAMRAAoKVgtIOQBwAQARAAoKVgtIOQBwAQAYAAcKGg0ErwASAQAAAA==.Dameiyo:BAAANQAECggIEwAAAA==.Dandanh:BAAANQADCgMIAwAAAA==.Dangright:BAABNQAECn8aAAIZAAgKXwVBPgBgAQAZAAgKXwVBPgBgAQAAAA==.Dankbo:BAACNQAFFH8UAAMWAAUKPBEfAgDVAAAGAAQKHhUiGAAyAQAWAAMK1ggfAgDVAAA1AAQKfzsAAxYACQooI7MCAOQCABYACAq6ILMCAOQCAAYACQqOHvYlANMCAAAA.Danorac:BAABNQAECn8XAAIaAAkKzgmzGgBbAQAaAAkKzgmzGgBbAQAAAA==.Darkcoffee:BAABNQAECn8WAAIEAAYKGhd6FgBQAQAEAAYKGhd6FgBQAQAAAA==.Darkivie:BAAANQADCgYIBgABNQAECgkJHgAJAGMFAA==.',
De='Deadashe:BAAANQADCgEIAQAAAA==.Demonicsword:BAAANQADCgQIBAAAAA==.Despondent:BAAANQADCggIFgAAAA==.Devilcrybaby:BAAANQAECgIIAgAAAA==.Devildj:BAAANQAECgcIDwAAAA==.Dezadian:BAABNQAECn8gAAIJAAcKogQZ0gC/AAAJAAcKogQZ0gC/AAAAAA==.',
Dh='Dhampyra:BAABNQAECn8YAAMTAAgKOBOFJQADAgATAAgKOBOFJQADAgAGAAQKDReXcwD8AAAAAA==.',
Di='Dietmountdew:BAAANQADCgEJAQAAAA==.Dimitrios:BAAANQAECgcIDgAAAA==.Disolve:BAABNQAECn8gAAQQAAkKFBGueAD5AQAQAAkKog2ueAD5AQAbAAIK9hY7UgCIAAAcAAEKAABKJQBZAAAAAA==.Dixxonciderr:BAACNQAFFH8IAAIdAAUKuAeKEgC4AAAdAAUKuAeKEgC4AAA1AAQKf0kABB0ACgohHo8JAAoDAB0ACgohHo8JAAoDAB4ABwqLD8UgAE0BAB8AAgpZFf0dAHIAAAAA.',
Dm='Dmoe:BAAANQAECgUIEAAAAA==.',
Do='Docutratties:BAAANQAECgIIAgABNQAECgoKJQAQAOMJAA==.Doji:BAAANQADCgEIAQAAAA==.Doublesixes:BAAANQAECgEIAQAAAA==.',
Dq='Dqe:BAAANQAECgEIAwAAAA==.',
Dr='Drac:BAAANQADCgMIAwAAAA==.Dragonara:BAAANQADCggICAAAAA==.Draskion:BAAANQADCgUIBQAAAA==.Dribby:BAAANQAECgQIBQAAAA==.',
Du='Duhästmich:BAAANQADCgYIBgABNQAECggIJQAMAIcJAA==.Duplicate:BAACNQAFFH8PAAMUAAQKjBS6GwDRAAAUAAQKjBS6GwDRAAAgAAIKGA8TCQCOAAA1AAQKfy4AAxQACgqHHVshAHQCABQACgqHHVshAHQCACAAAQonG6BBAEEAAAAA.Dustdruid:BAACNQAFFH8FAAIhAAMKdxCdGgDNAAAhAAMKdxCdGgDNAAA1AAQKfzEAAiEACQpLIKARAC8CACEACQpLIKARAC8CAAAA.Dustlock:BAAANQAECggIEgAAAA==.Dustmage:BAAANQADCggIEAAAAA==.Dustsham:BAAANQAECgEIAwAAAA==.',
Dw='Dwarr:BAAANQAECgYICAAAAA==.',
Dy='Dysnomia:BAAANQAECgIIAgAAAA==.',
Dz='Dzoolock:BAAANQAECgEIAQAAAA==.',
['Dó']='Dóru:BAAANQADCgYIBwAAAA==.',
Ee='Eender:BAAANQAECgEIAQAAAA==.',
Eg='Eggrolls:BAABNQAECn9CAAIBAAoKLBsAIwAsAwABAAoKLBsAIwAsAwAAAA==.',
El='Eldenmorden:BAAANQADCgYIBgAAAA==.Eleshmelly:BAAANQADCgcIFgAAAA==.Elfrafa:BAAANQADCgEIAQAAAA==.Ellayna:BAAANQADCgEIAQAAAA==.Ellcrys:BAABNQAECn87AAIDAAoK1Rn6CgCLAgADAAoK1Rn6CgCLAgAAAA==.Elletta:BAAANQAECgEIAwAAAA==.Elrae:BAAANQAECgYIBgAAAA==.',
Ep='Epoptes:BAAANQAECgQIBgABNQAECgcIHQAEAJYLAA==.',
Eq='Eqo:BAABNQAECn8dAAMGAAkKERI8eQCvAQAGAAkKERI8eQCvAQATAAEKxQl3dAA9AAAAAA==.',
Er='Erisian:BAAANQAECgQIBgAAAA==.Erkêios:BAABNQAECn8dAAIiAAkKnxP1IwCvAQAiAAkKnxP1IwCvAQAAAA==.Ersande:BAAANQAECgMIAwAAAA==.Ertz:BAAANQADCggICQAAAA==.',
Es='Escherichia:BAAANQAECgEJAQAAAA==.Estheban:BAABNQAECn8gAAQeAAkKOR/yDgBtAgAeAAkKOR/yDgBtAgAfAAMKFRa0EwBFAAAdAAEKQAtiUAAtAAAAAA==.',
Ev='Evengelist:BAAANQAECgcIEwABNQAECgoKIQAIAPYNAA==.',
Fa='Face:BAAANQAECgUIBwAAAA==.Fairgrim:BAAANQAECgQIBQAAAA==.Falin:BAABNQAECn9KAAIJAAoKqhswQwDLAgAJAAoKqhswQwDLAgAAAA==.Faqueuedark:BAABNQAECn8bAAIQAAoKshlaPgCYAgAQAAoKshlaPgCYAgABNQAFFAMICAAHAGIMAA==.Faqueueeight:BAACNQAFFH8IAAMHAAMKYgwxAgCeAAAHAAMKYgwxAgCeAAANAAEKvAOUIAAxAAA1AAQKf0kAAw0ACgr0HxoSAA4DAA0ACgq0HxoSAA4DAAcACgoWFj0HAI8BAAAA.Fatsloth:BAAANQAECgUICQAAAA==.Fatébringer:BAAANQADCgYIDAABNQAECgEIAQAVAAAAAA==.Faulted:BAAANQADCgUIBQAAAA==.',
Fe='Feironos:BAAANQAECgEIAwAAAA==.Felcookies:BAAANQAECgYIDQAAAA==.Ferrick:BAAANQAECgIIAgAAAA==.',
Fi='Fimtastic:BAABNQAECn8mAAIYAAgKDBWPSQBvAQAYAAgKDBWPSQBvAQAAAA==.Finasy:BAABNQAECn8oAAMjAAgKWSE1GwDVAgAjAAcKRiQ1GwDVAgAiAAYKExIwOgAxAQAAAA==.Finbezy:BAAANQAECgQIAwAAAA==.Finnicka:BAAANQAECgEIAQAAAA==.Firen:BAAANQADCgcIFAAAAA==.Fireouch:BAAANQABCgIIAwAAAA==.Fistymisty:BAABNQAECn8cAAIkAAkKix98BAAvAwAkAAkKix98BAAvAwAAAA==.Fizeecian:BAAANQAECgQIBAAAAA==.',
Fl='Flaynpray:BAAANQADCgEIAQAAAA==.Fluffenstein:BAAANQAFFAMIBAAAAA==.',
Fo='Foxrawruwu:BAABNQAECn8WAAIQAAgKqRqZNgCxAgAQAAgKqRqZNgCxAgAAAA==.',
Fr='Frakk:BAAANQAECggIAQAAAA==.Freezegarr:BAACNQAFFH8IAAIUAAUKbBiEEwD9AAAUAAUKbBiEEwD9AAA1AAQKfygAAhQACgpFIKkOAOQCABQACgpFIKkOAOQCAAAA.Frostgrave:BAAANQADCgEIAQAAAA==.Frostya:BAAANQADCgYIBgAAAA==.',
Fu='Fujibayashi:BAAANQAECgQICQAAAA==.Furearia:BAAANQABCgcICQAAAA==.Furrybowner:BAAANQAECggIDwAAAA==.',
Ga='Galeriel:BAACNQAFFH8RAAIGAAUK9hwDDABrAQAGAAUK9hwDDABrAQA1AAQKf0IAAgYACgoZJtIAAC4EAAYACgoZJtIAAC4EAAAA.Gallethline:BAAANQAECgIIBQAAAA==.Ganjgotti:BAAANQADCgYICQAAAA==.Garault:BAAANQAECgYICwAAAA==.Gavered:BAAANQADCgMIBQAAAA==.',
Ge='Gekoni:BAAANQAECgUICgAAAA==.Geonon:BAAANQADCggICAAAAA==.Geotracker:BAABNQAECn8dAAIKAAcKHxAsegBAAQAKAAcKHxAsegBAAQABNQADCggICAAVAAAAAA==.',
Gh='Ghorros:BAAANQADCgMIAwAAAA==.',
Gi='Gilgahmesh:BAABNQAECn8VAAIBAAkKLAmo3AAyAQABAAkKLAmo3AAyAQABNQAECgoKMgAIAFsdAA==.',
Gl='Glowpwr:BAAANQADCgcIBwAAAA==.',
Go='Golruck:BAAANQAECgMIAwABNQAECggIEgAVAAAAAA==.Goolgame:BAACNQAFFH8SAAMRAAUKjR3UBwAGAQARAAUKjR3UBwAGAQAYAAMKXBXeFgDwAAA1AAQKfykAAxEACgooIMo8AIICABEACApAIco8AIICABgABQq9G2SHAHgBAAAA.Goonthergg:BAAANQAECgEIAQAAAA==.Goothix:BAAANQADCgcJCAAAAA==.Gothmog:BAAANQADCgIIAgAAAA==.',
Gr='Grammarg:BAAANQADCgMIAwAAAA==.Grezzert:BAAANQADCgMIAwAAAA==.Grirr:BAAANQAECgIIBAAAAA==.Grothin:BAABNQAECn8uAAIYAAoK6Rp1EgC5AgAYAAoK6Rp1EgC5AgAAAA==.Gruldag:BAACNQAFFH8GAAIUAAMK7hO/GADkAAAUAAMK7hO/GADkAAA1AAQKfzUAAhQACgoxHCZdAMUCABQACgoxHCZdAMUCAAAA.Grullander:BAABNQAECn81AAIYAAoKWxIzMgDYAQAYAAoKWxIzMgDYAQAAAA==.Grullandyr:BAAANQAECgIIAgABNQAECgoKNQAYAFsSAA==.',
Gu='Guiguiie:BAAANQADCggJEAAAAA==.',
Gw='Gwyndolynn:BAAANQADCgQIBQAAAA==.',
Ha='Haeldir:BAAANQADCgYIBQAAAA==.Hailey:BAEBNQAECn8WAAIGAAkKhRibKwC6AgAGAAkKhRibKwC6AgABNQAFFAYICwAIAC4LAA==.Halter:BAAANQAECgIIAgAAAA==.Hapló:BAAANQABCgEIAQAAAA==.Haratvy:BAAANQAECgEIAgAAAA==.Hazzurd:BAABNQAECn8aAAIKAAgKZRO8cwApAgAKAAgKZRO8cwApAgAAAA==.',
He='Header:BAACNQAFFH8aAAIZAAcKwhmiBQACAgAZAAcKwhmiBQACAgA1AAQKfy4AAxkACgpGHccIAGECABkACgpGHccIAGECAAoABQrhCjP9AAoBAAAA.Healsorz:BAAANQADCgcIBwAAAA==.Heersbeest:BAAANQAECgEIBAAAAA==.Helane:BAAANQAECgEIAgAAAA==.Herkharu:BAAANQADCgcIBwAAAA==.Hermionee:BAABNQAECn8xAAMgAAoKyhBSFwC4AAAUAAgKUQxqkQAhAQAgAAMKUhZSFwC4AAAAAA==.Hetu:BAAANQABCgUIBAAAAA==.',
Hi='Hide:BAAANQAECgEIAQAAAA==.Himjongun:BAABNQAECn8hAAMNAAoKNBcdIwB8AQANAAkKNBcdIwB8AQAaAAEKAADddQAiAAAAAA==.',
Ho='Holya:BAAANQADCgEIAQABNQAFFAcIBwALAA4AAA==.Holycowe:BAAANQAECgUICwAAAA==.Holykoi:BAABNQAECn85AAIGAAoKwg1UMwDvAQAGAAoKwg1UMwDvAQAAAA==.',
Hr='Hroarr:BAABNQAECn8ZAAIjAAoKRSKTDgA7AwAjAAoKRSKTDgA7AwABNQAFFAUICAAUAGwYAA==.',
Hu='Humancarnage:BAAANQADCgYIBwAAAA==.Huuh:BAAANQADCgQIBwAAAA==.',
Hy='Hypaexia:BAAANQADCgIIAgAAAA==.',
['Hà']='Hàvoc:BAAANQADCggIDQAAAA==.',
['Hé']='Héboric:BAABNQAECn8mAAIIAAkK4R7EEADLAgAIAAkK4R7EEADLAgAAAA==.Hélbrecht:BAAANQAECgMIAwAAAA==.',
['Hÿ']='Hÿbrìd:BAAANQAECgYIEAAAAA==.',
Ia='Iamwho:BAAANQAECggICQAAAA==.Iatros:BAABNQAECn8dAAMEAAcKlgvTPQAHAQAEAAYKfw3TPQAHAQAJAAMKPQMvKAFLAAAAAA==.',
Id='Idkno:BAAANQAECgIIAgAAAA==.',
Ik='Ikara:BAAANQADCggICAABNQAECgoKJQAcAAwQAA==.Ikodiwa:BAAANQADCgUIBQAAAA==.',
Il='Ilrion:BAAANQAECgEIAQAAAA==.',
Im='Imjustsaiyan:BAAANQADCgIIAgAAAA==.',
In='Indravax:BAABNQAECn8bAAIQAAkKQRRITwB2AQAQAAkKQRRITwB2AQAAAA==.',
Io='Iorin:BAAANQADCggIBwABNQAECgkJIAANADoOAA==.',
It='Itwasntmebru:BAAANQADCgYIFAAAAA==.',
Iv='Ivantis:BAAANQADCgYIFwAAAA==.Ivie:BAAANQAECgQIBgAAAA==.',
Iw='Iwonabhornee:BAAANQADCgIIAgAAAA==.',
Ja='Jaholypriest:BAACNQAFFH8KAAIGAAQKVBIAEQAdAQAGAAQKVBIAEQAdAQA1AAQKfx8AAgYACgpmFf5WAB4CAAYACgpmFf5WAB4CAAAA.Janjor:BAAANQAECgYICQAAAA==.Janjy:BAAANQADCgcIBwAAAA==.Jaypiea:BAABNQAECn8iAAMfAAkKTBUCCAAgAgAfAAgKTBUCCAAgAgAeAAgK8xC2FwDOAQAAAA==.',
Je='Jergall:BAAANQADCgUIBQAAAA==.Jettian:BAAANQAECgYIEgAAAA==.',
Ji='Jibz:BAAANQADCgEIAQAAAA==.',
Jj='Jjdruid:BAAANQAECgIIAgAAAA==.',
Jo='Johnathon:BAAANQAECgIIAgABNQAECgMIBAAVAAAAAA==.Jollygreene:BAAANQAECgEIBQAAAA==.Jonestu:BAAANQAECgQIBQAAAA==.',
Jp='Jpgigacat:BAAANQAECgYICgAAAA==.Jpgigademon:BAAANQAECgMIBAAAAA==.Jpgigawolf:BAAANQAECgUIBgAAAA==.',
Ju='Justakatt:BAAANQAECgEIAQAAAA==.Justicasia:BAAANQADCgQIBAABNQADCgYIBgAVAAAAAA==.',
Ka='Kadinsky:BAAANQADCgUIBQAAAA==.Kalivan:BAAANQADCgYIBwAAAA==.Kankimasamu:BAAANQADCgIIAgAAAA==.Karametra:BAAANQAECgcICgAAAA==.Karlldun:BAAANQAECgYIDgAAAA==.Kasmir:BAABNQAECn8iAAMQAAgKhw+blwCsAQAQAAcK/xCblwCsAQAbAAEKLggUfQAwAAAAAA==.Kasnfriends:BAAANQADCgUIBQABNQAECggIIgAQAIcPAA==.',
Ke='Kevv:BAACNQAFFH8PAAIRAAYKIQNdDQDIAAARAAYKIQNdDQDIAAA1AAQKfy0AAxEACgplGO4cABQCABEACgplGO4cABQCABcAAQoAAPI7ABkAAAAA.Keyniron:BAABNQAECn/EAAIJAAkKZiXxAgBwAwAJAAkKZiXxAgBwAwAAAA==.',
Kh='Khogent:BAAANQAECgEIAgAAAA==.Khonsu:BAAANQAECgQIBQABNQAECgUICwAVAAAAAA==.Khrover:BAAANQADCgUIBQAAAA==.Khyle:BAAANQADCgYIBwAAAA==.',
Ki='Kijanajr:BAAANQADCgMIAgAAAA==.Killaarrow:BAABNQAECn85AAIKAAkKSQn3VQCbAQAKAAkKSQn3VQCbAQAAAA==.Kindleos:BAAANQAECgEIAQAAAA==.',
Kk='Kkpriest:BAAANQADCgEIAQAAAA==.',
Kl='Klay:BAAANQAECgYIEQAAAA==.',
Km='Kmarte:BAEANQAECgYIEgABNQAECgcIDAAVAAAAAA==.Kmarti:BAEANQAECgcIDAAAAA==.Kmartt:BAEBNQAECn8lAAIJAAoKjht4JwBkAgAJAAoKjht4JwBkAgABNQAECgcIDAAVAAAAAA==.',
Ko='Kosmic:BAAANQADCgcICQABNQAECggIJAAjALwZAA==.Kosmicknight:BAABNQAECn8kAAMjAAgKvBk1NwAtAgAjAAgKvBk1NwAtAgAiAAEKAAA4twAoAAAAAA==.',
Kr='Kraggers:BAAANQAECgYIDQAAAA==.Kraggory:BAAANQAECgIIAgAAAA==.Kraggoryqt:BAAANQAECgMIDwAAAA==.Kraggoryx:BAAANQAECgEIAQAAAA==.Krunclez:BAAANQAECgIIAgAAAA==.Kryesta:BAABNQAECn9EAAIYAAoKZiGWCQApAwAYAAoKZiGWCQApAwAAAA==.',
Kw='Kwarr:BAACNQAFFH8JAAIXAAYK0g6jAwA8AQAXAAYK0g6jAwA8AQA1AAQKfz4AAhcACgp9IjkDAG0DABcACgp9IjkDAG0DAAAA.',
La='Laganddecay:BAAANQABCggIGQAAAA==.Lalii:BAAANQAECgQIBQAAAA==.Lallypop:BAAANQAECgEIAgAAAA==.Lammoth:BAAANQAECgEIAgAAAA==.Lanemogsnick:BAAANQADCgQIBAAAAA==.Layonhandsy:BAAANQAECgQIBAABNQAFFAQICQAjABYhAA==.',
Le='Leafu:BAAANQAECgMIAwABNQAECgoKKwATAIQcAA==.Leasin:BAABNQAECn8rAAITAAoKhBywEwDKAgATAAoKhBywEwDKAgAAAA==.Lencreye:BAAANQADCgMIBAAAAA==.Lethendervis:BAAANQADCgYIDgAAAA==.',
Li='Lighthusk:BAAANQABCgQIBAAAAA==.Liliauna:BAABNQAECn8jAAIQAAcK+xr9aQAeAgAQAAcK+xr9aQAeAgAAAA==.Lilibejeane:BAAANQADCgcIDgABNQAECgYIEQAVAAAAAA==.Lillynelazar:BAABNQAECn8cAAIKAAoKBgUwtwCVAQAKAAoKBgUwtwCVAQABNQAECgYICQAVAAAAAA==.Liloisback:BAABNQAECn8aAAIBAAoKzBMEYQBgAQABAAoKzBMEYQBgAQAAAA==.Lilsquirtboy:BAAANQADCgUIBQABNQAECgoKOgAFAGQfAA==.Linasonna:BAAANQAECgMIBQABNQAFFAUIEgARAI0dAA==.Linithara:BAABNQAECn8gAAMNAAkKOg4MNwD4AQANAAkK1AwMNwD4AQAHAAgK5QmcFgBDAQAAAA==.Littlehoosie:BAAANQAECggIEgAAAA==.',
Lo='Lockersz:BAAANQADCgEIAQABNQAFFAcIFQAiAJ4TAA==.Loram:BAAANQAECgIIBAAAAA==.Lostbase:BAAANQAECgQIBAAAAA==.Lostgrip:BAAANQAECgYIDgAAAA==.',
Lu='Lucthedk:BAABNQAECn8WAAMMAAkK/xAzTADkAQAMAAkK/xAzTADkAQAiAAQKWwrPeADBAAAAAA==.Lukis:BAAANQAECgMICAAAAA==.Lunarpriest:BAAANQAECgQIBQAAAA==.Lunitari:BAAANQAECgEIAgAAAA==.Lunkbeck:BAAANQAECgEIAgAAAA==.Luxriel:BAAANQAECgEIAgAAAA==.',
['Lø']='Lørd:BAABNQAECn8qAAMZAAoKxxp2IABLAgAZAAgKwhZ2IABLAgAKAAcKrRuucwBOAQAAAA==.',
Ma='Madik:BAAANQADCgcJCAAAAA==.Magicmegan:BAAANQAECgEIAQABNQAECggIFgAQAKkaAA==.Mahoragax:BAAANQAECggIAQAAAA==.Maladin:BAAANQAECgIIBQAAAA==.Malkurim:BAAANQADCgEIAQAAAA==.Malvean:BAAANQADCgUICgAAAA==.Manamommyy:BAAANQAECgEIAQAAAA==.Manasa:BAAANQAECgYIEQAAAA==.Marblack:BAAANQAECgQIBAAAAA==.Marceline:BAABNQAECn8mAAIKAAoKgBWKJwBEAgAKAAoKgBWKJwBEAgAAAA==.Marthahog:BAAANQAECgYIBgABNQAECgkJJgAlAH8VAA==.Marthog:BAABNQAECn8mAAMlAAkKfxVkBgATAgAlAAkKfxVkBgATAgABAAEKYAM4YQElAAAAAA==.Mashido:BAAANQADCgMIAwAAAA==.Matresstains:BAAANQAECgUIDgAAAA==.',
Mc='Mcdermott:BAAANQAECgQIBwAAAA==.',
Me='Melanius:BAAANQAECgUIEAAAAA==.Melranis:BAAANQADCgcIDAAAAA==.',
Mi='Miluk:BAAANQAECgYIEgAAAA==.Misconduct:BAAANQAECgcIEwAAAA==.',
Mm='Mmins:BAAANQAECgYICgAAAA==.',
Mo='Montagne:BAAANQADCgQIBAAAAA==.Moomist:BAAANQAECgQIBgAAAA==.Moondarin:BAAANQABCgIIAgAAAA==.Moonfanna:BAAANQAECgQJBQAAAA==.Moonmx:BAAANQAECgYICQAAAA==.Moosesunaxe:BAAANQAECgEIAQAAAA==.Morriganth:BAAANQADCgEIAQAAAA==.',
Mu='Mujina:BAAANQAECgMIAwABNQAFFAUIEgACAKoeAA==.Murdamoose:BAAANQADCgIIAgAAAA==.Mustysponge:BAAANQADCgUIBwAAAA==.',
My='Mysteryx:BAABNQAECn8mAAITAAoKYRSuGQCAAgATAAoKYRSuGQCAAgAAAA==.Mystrbeast:BAAANQADCgQIBAAAAA==.',
['Mó']='Móxie:BAAANQADCgIIAQAAAA==.',
Na='Nahtan:BAAANQADCgYIDAAAAA==.Nammu:BAAANQADCgEIAQAAAA==.Nandisa:BAAANQAECgEIAgAAAA==.Naniwa:BAAANQAECgUICgAAAA==.Nawala:BAAANQAECgEIAQAAAA==.Nazendrov:BAEANQAECggICAABNQAECggICAAVAAAAAA==.Nazura:BAAANQADCgcIEQAAAA==.',
Ne='Nereza:BAAANQADCgYIDAAAAA==.Nershog:BAAANQAECgEIAQAAAA==.Nesquip:BAAANQADCgYJBgAAAA==.Newil:BAAANQADCgYIBgAAAA==.',
Ni='Nightforday:BAABNQAECn8zAAMMAAkKiSDHIwC0AgAMAAkKiSDHIwC0AgAiAAIKUhVhjgB+AAAAAA==.Niko:BAAANQABCgUIBwAAAA==.Nishra:BAAANQADCggICAAAAA==.',
No='Noks:BAAANQAECggIBAAAAA==.Noktas:BAAANQAECgMIBwABNQAECggIEgAVAAAAAA==.Nominé:BAAANQADCgQIBgAAAA==.Nool:BAAANQADCgQIBwAAAA==.Norch:BAAANQAECgIJBgAAAA==.Notkory:BAAANQAECggICAAAAA==.Noux:BAAANQAECgUIBQAAAA==.',
Nu='Nube:BAAANQADCggIDAAAAA==.',
Ny='Nyababa:BAAANQAECgcICwABNQAFFAUIEgACAKoeAA==.',
Oc='Octavia:BAAANQAECgIIAwAAAA==.',
Og='Ogora:BAAANQADCgQIBgAAAA==.',
Ok='Oki:BAAANQADCgMIBAAAAA==.Okktrål:BAAANQAECgYJDAAAAA==.Oktavius:BAABNQAECn8sAAIYAAoK+yDLAwCoAwAYAAoK+yDLAwCoAwAAAA==.',
On='Onlyvel:BAAANQAECgEIAgAAAA==.',
Op='Ophysia:BAAANQAECgIIAgAAAA==.',
Or='Ordaka:BAAANQADCgYIBgAAAA==.Orkcansas:BAAANQAECgEIAQAAAA==.Orruutah:BAAANQADCgYIBgAAAA==.',
Os='Oskaia:BAAANQAECgYICwAAAA==.Osla:BAAANQAECgYIBgAAAA==.',
Ox='Oxytoecin:BAAANQAECgYIBgAAAA==.',
Pa='Paapineau:BAABNQAECn8VAAImAAgKFwfzIAD9AAAmAAgKFwfzIAD9AAAAAA==.Packes:BAABNQAECn8zAAIjAAoKNBhVKQB4AgAjAAoKNBhVKQB4AgAAAA==.Pakkohruun:BAABNQAECn8gAAIJAAoKcxfXbgBSAgAJAAoKcxfXbgBSAgAAAA==.Pallywack:BAABNQAECn8yAAIJAAkKrAsu0QB5AQAJAAkKrAsu0QB5AQAAAA==.Palussy:BAAANQADCgQIBAAAAA==.Parthima:BAABNQAECn8yAAMhAAgKqQkJMAAUAQAhAAgKqQkJMAAUAQADAAEKdwk/YQAhAAAAAA==.Partysnaxx:BAAANQABCgEIAQAAAA==.',
Pe='Peppercat:BAAANQAECgQICAAAAA==.Pertophos:BAAANQAECgUICQAAAA==.Pettigrew:BAAANQADCgIJAgAAAA==.',
Ph='Phantomclone:BAAANQAECgIIBQAAAA==.Phantomdh:BAAANQAECgEIAgAAAA==.Phantomghoul:BAAANQAECgUIBQAAAA==.Phated:BAAANQAECgEIAQAAAA==.Philomena:BAAANQAECgEIAQAAAA==.',
Pi='Piggÿ:BAAANQAECgQIDQAAAA==.Piko:BAAANQADCggIDgAAAA==.Piyo:BAAANQADCgcIBwABNQAECgoKMwAjADQYAA==.',
Pl='Plankormast:BAAANQADCgEIAQAAAA==.',
Po='Poky:BAAANQAECgEIAgABNQAECgYICwAVAAAAAA==.Popena:BAAANQAECgMIBAAAAA==.Porkbuns:BAABNQAECn8oAAIUAAoKlhN5OgAJAgAUAAoKlhN5OgAJAgAAAA==.Potatogg:BAAANQAECgIIBQAAAA==.',
Pr='Praedor:BAAANQAECgYIBgAAAA==.Precious:BAAANQAECgEIAQAAAA==.Priestymon:BAABNQAECn8mAAIGAAoK3CFeCwBnAwAGAAoK3CFeCwBnAwABNQAFFAYIDQABAFUcAA==.Protdaddyy:BAAANQAECgEIAgAAAA==.',
Pw='Pwarr:BAACNQAFFH8JAAIlAAQKxwtEBADpAAAlAAQKxwtEBADpAAA1AAQKfyIAAyUACgq8H9YEAFUCACUACgq8H9YEAFUCAAEACAoPDxnSAE0BAAE1AAUUBggJABcA0g4A.',
Qa='Qamar:BAAANQADCgQIBAAAAA==.',
Qu='Quackadeen:BAAANQAECgIJAgAAAA==.Quaesitor:BAAANQAECgEIBAAAAA==.',
Qw='Qwarr:BAAANQAECgUICgABNQAFFAYICQAXANIOAA==.',
Ra='Raamey:BAAANQADCgIIAgAAAA==.Raathya:BAABNQAECn8WAAIKAAkK0A5MYQB7AQAKAAkK0A5MYQB7AQAAAA==.Raeljin:BAABNQAECn8ZAAIRAAgKLxlaQQBwAgARAAgKLxlaQQBwAgAAAA==.Ragetastick:BAAANQAECggIAQAAAA==.Raihua:BAAANQADCgYIBgAAAA==.Rampagarex:BAAANQADCgYIBgAAAA==.Rangoz:BAAANQAECgUIEAAAAA==.Rar:BAABNQAECn8gAAIKAAoKjB7HEgC6AgAKAAoKjB7HEgC6AgAAAA==.Ratgamerlol:BAACNQAFFH8FAAIKAAIKbyCNEADFAAAKAAIKbyCNEADFAAA1AAQKfyoAAgoACAoPJEgqAPACAAoACAoPJEgqAPACAAAA.Ravnur:BAAANQADCggICAAAAA==.Rayennagrom:BAAANQAECgEIBQAAAA==.Rayo:BAAANQAECgEIAQAAAA==.',
Re='Reagent:BAAANQADCgMIAwAAAA==.Reckrunner:BAABNQAECn8lAAQQAAoKbhALRwCQAQAQAAgKShELRwCQAQAcAAIKNwdLLgA5AAAbAAEKZwoEKwAvAAAAAA==.Redlocks:BAAANQAECgYICgAAAA==.Renault:BAAANQADCgMIAwAAAA==.Reneana:BAAANQAECgUIDQAAAA==.Restbo:BAACNQAFFH8FAAIYAAUKyAy+CQBQAQAYAAUKyAy+CQBQAQA1AAQKfx8AAhgACgpwIXQLAGUDABgACgpwIXQLAGUDAAE1AAUUBQgUABYAPBEA.',
Rh='Rhianonn:BAAANQAECgYIEAABNQAECgQIBgAVAAAAAA==.',
Ri='Riaslock:BAAANQAECgEJAQAAAA==.Riaswar:BAAANQADCgEIAQAAAA==.Richardluis:BAABNQAECn8VAAIRAAcKwwrPoABVAQARAAcKwwrPoABVAQAAAA==.Rinehardtt:BAABNQAECn8yAAIIAAoKWx0OIwDgAgAIAAoKWx0OIwDgAgAAAA==.Riverstyxx:BAAANQADCgYIEQAAAA==.Rivër:BAAANQADCggIHwAAAA==.',
Ro='Robbell:BAABNQAECn8wAAIKAAoKiBsBGwCEAgAKAAoKiBsBGwCEAgAAAA==.Rococote:BAAANQAECggICgAAAA==.Roggehere:BAAANQAECgIIAgAAAA==.Rokyman:BAAANQAECgcIEAAAAA==.Roldazark:BAAANQAECgEIAQAAAA==.Roonsia:BAAANQADCgQIBQAAAA==.Rootsie:BAAANQADCgYJFwAAAA==.Roselynn:BAABNQAECn8ZAAIDAAgKbRasHwAuAgADAAgKbRasHwAuAgAAAA==.Rouby:BAAANQAECgEIBQAAAA==.Roughlight:BAAANQADCgMIAwAAAA==.',
Ru='Ruerl:BAABNQAECn8YAAIJAAgKTAqxzACCAQAJAAgKTAqxzACCAQAAAA==.Runentug:BAACNQAFFH8JAAIjAAQKFiHtDQB1AQAjAAQKFiHtDQB1AQA1AAQKfxsAAiMACQqSJAkNAEkDACMACQqSJAkNAEkDAAAA.Rustyspell:BAAANQADCgIIAgAAAA==.',
Ry='Ryumapriest:BAAANQAECgEIAQAAAA==.',
['Rî']='Rîft:BAAANQADCgEIAQAAAA==.',
Sa='Sanddora:BAAANQADCgIIAgAAAA==.Sanlordriel:BAAANQAECgMIAwAAAA==.Saramon:BAAANQADCggIKQAAAA==.Sassiberry:BAAANQADCgcIEQAAAA==.Sassitude:BAAANQADCgcIFQAAAA==.Satiiva:BAAANQADCggICAAAAA==.',
Sc='Scarlos:BAAANQABCgMIAwAAAA==.Screamdying:BAAANQABCgIIAgAAAA==.Scrembiblion:BAABNQAECn8kAAInAAgKLh8tAQDbAgAnAAgKLh8tAQDbAgAAAA==.',
Sd='Sdhoscillate:BAAANQADCgYIBgAAAA==.',
Se='Seins:BAAANQADCgYIBgAAAA==.Semillin:BAAANQAECgcIEgAAAA==.Senseitional:BAAANQAECgEIAQABNQAECgcIKwAOAHwiAA==.Sensjei:BAAANQAECgQIDQAAAA==.Separatist:BAAANQADCgMJAwAAAA==.Serendibitty:BAAANQADCgMJAwAAAA==.',
Sg='Sgtbreezy:BAAANQADCgcIBwAAAA==.',
Sh='Shadey:BAAANQADCgIIAgAAAA==.Shambulance:BAAANQAECgcIDgAAAA==.Sharuerl:BAAANQADCgcIBwAAAA==.Shazi:BAEANQAECggICAAAAA==.Shiftroid:BAAANQADCgMIBgAAAA==.Shinyivie:BAABNQAECn8eAAIJAAkKYwX85ABRAQAJAAkKYwX85ABRAQAAAA==.Shiverchill:BAAANQABCgEJAQAAAA==.Shockrock:BAAANQAECgEIAQAAAA==.Shouzhe:BAAANQADCgUIBQAAAA==.Shroomjuice:BAAANQAECggIDwAAAA==.Shuthehealup:BAAANQAECgEIAwAAAA==.Shãdøwzzxz:BAAANQAECgUIDgAAAA==.',
Si='Sildenafil:BAAANQADCgIIAgAAAA==.Silessra:BAAANQADCggICAAAAA==.',
Sk='Skogr:BAAANQADCgIIAQABNQADCgUIBQAVAAAAAA==.Skädoosh:BAAANQAECgEIAQAAAA==.',
Sl='Slapshappy:BAAANQAECggIDAAAAA==.',
Sm='Smallhorn:BAAANQAECgEIAgAAAA==.Smokeyhaze:BAAANQAECgYIEAAAAA==.Smokin:BAABNQAECn8hAAIKAAgK9gpVsgCfAQAKAAgK9gpVsgCfAQAAAA==.Smolther:BAAANQADCgcIBwAAAA==.Smores:BAAANQADCgcJDQAAAA==.',
Sn='Sneech:BAAANQAECgMIBQAAAA==.Snowbvnni:BAAANQADCgQIBAAAAA==.',
So='Sofarkinghi:BAAANQAECgEIAwAAAA==.Sollamor:BAAANQAECgMIBAAAAA==.Solomonk:BAABNQAECn8pAAIkAAgKowwnDgDcAAAkAAgKowwnDgDcAAAAAA==.Solomus:BAABNQAECn8jAAMOAAgKiwxFIgD3AAAOAAgKiwxFIgD3AAAhAAQKWwH3awA3AAAAAA==.Sonal:BAABNQAECn8XAAQiAAcKtgocXQAzAQAiAAcKtQkcXQAzAQAjAAUK6QezjgDIAAAMAAEKAAC9+AAfAAAAAA==.Soneca:BAAANQAECgMIBAAAAA==.Soter:BAAANQAECgcICwAAAA==.',
Sq='Squeaph:BAAANQAECgcIDgAAAA==.',
St='Stararia:BAAANQADCggIDwAAAA==.Stelltrain:BAAANQAECgEIAQAAAA==.Stoploss:BAAANQAECgEIAQAAAA==.Stormiee:BAABNQAECn8pAAIYAAkKqxhSOAB+AgAYAAkKqxhSOAB+AgABNQAECgQIBgAVAAAAAA==.Stormroid:BAAANQAECgUICQAAAA==.Strangulate:BAAANQAECgMIBAAAAA==.Sttorm:BAAANQADCgUIBQAAAA==.Styles:BAABNQAECn8hAAIJAAYK5wxV+QAsAQAJAAYK5wxV+QAsAQAAAA==.',
Su='Sugarontop:BAAANQADCgQIBAAAAA==.Sunmx:BAABNQAECn8xAAMBAAoKWR5zKQAVAwABAAoKtxxzKQAVAwACAAYKXh/qBgDCAQAAAA==.Superdark:BAAANQADCgIIAgAAAA==.',
Sw='Swurve:BAEANQAECgQIBwAAAA==.Swurves:BAAANQAECgIIAwABNQAECgUIBQAVAAAAAA==.',
Sz='Szucs:BAAANQAECgEIAQAAAA==.',
['Sã']='Sãvãge:BAAANQADCgQIBAAAAA==.',
Ta='Tabiji:BAEANQAECggICAAAAA==.Tadpole:BAAANQADCggIFAAAAA==.Taedrum:BAABNQAECn8XAAIMAAgKEwgfLAAhAQAMAAgKEwgfLAAhAQAAAA==.Taerror:BAAANQADCgIIAgAAAA==.Talegos:BAAANQAECgMJAwAAAA==.Talonfel:BAAANQADCgQIBAABNQAECgkJOQASACUjAA==.Taloning:BAAANQADCgYIBgABNQAECgkJOQASACUjAA==.Talonstryke:BAABNQAECn85AAISAAkKJSOfAwB2AwASAAkKJSOfAwB2AwAAAA==.Tauraxs:BAAANQADCgEIAQAAAA==.Tazrak:BAAANQAECgMIBgABNQAECgoKJQAQAOMJAA==.',
Te='Teatoh:BAAANQADCgcIBwAAAA==.Tenseiga:BAABNQAECn8aAAMJAAoKCxS/RwDhAQAJAAgKxRS/RwDhAQAEAAoKJgrSLAB2AQABNQAFFAUIDQAHAPMbAA==.Testsubjectz:BAABNQAFFH8FAAIBAAUKyBujDAD+AAABAAUKyBujDAD+AAAAAA==.Tevers:BAAANQAECgEIAgAAAA==.',
Th='Thaalion:BAAANQAECgEIAQAAAA==.Thalantier:BAAANQADCgMIBgAAAA==.Thardal:BAABNQAECn8lAAMcAAoKDBD1BACaAQAQAAoKMg2RfADvAQAcAAkKEhD1BACaAQAAAA==.Thebigshot:BAAANQAECgMIBQAAAA==.Theenforcer:BAACNQAFFH8KAAIJAAUK7wLEEwCgAAAJAAUK7wLEEwCgAAA1AAQKf0wAAgkACgpGEf6HABcCAAkACgpGEf6HABcCAAAA.Thegreekbeas:BAAANQADCgUIBQAAAA==.Theguyfurry:BAAANQAECgEIAgAAAA==.Theonepanda:BAAANQAECgUICQAAAA==.Thetzin:BAABNQAECn8eAAIUAAYKJwNkYQHxAAAUAAYKJwNkYQHxAAAAAA==.Theunite:BAAANQADCggICAAAAA==.Thickhobo:BAAANQADCgUICQAAAA==.Thidwick:BAABNQAECn8rAAIOAAcKfCIdCQA9AgAOAAcKfCIdCQA9AgAAAA==.Thingtwø:BAAANQAECgYIEAAAAA==.Thistle:BAAANQADCgYIDAABNQAECgkJIQAUADQMAA==.Thraggs:BAAANQADCgcICAAAAA==.Thunderfist:BAAANQADCggIBwAAAA==.',
Ti='Titanslay:BAAANQADCgEIAQAAAA==.Titø:BAAANQADCgYIDQABNQADCgcIBwAVAAAAAA==.',
Tm='Tmryuki:BAAANQAECggICwAAAA==.',
To='Tokadin:BAAANQAECgIIBAAAAA==.Tomorrow:BAAANQAECgYICwAAAA==.Topzee:BAAANQAECgQIBAAAAA==.Totalljoe:BAAANQAECgQICwABNQAECggIJQAMAIcJAA==.Totoo:BAABNQAFFH8HAAILAAcKDgB6FwAhAAALAAcKDgB6FwAhAAAAAA==.Touchmablade:BAAANQAECgUIBgAAAA==.',
Tr='Traedarra:BAAANQADCgIIAgAAAA==.Tralis:BAEANQADCggIDgABNQAECggICAAVAAAAAA==.Tranarra:BAABNQAECn9UAAIQAAoK2hruFACDAgAQAAoK2hruFACDAgAAAA==.Traylo:BAABNQAECn8sAAIKAAkKcRMKPADxAQAKAAkKcRMKPADxAQAAAA==.',
Tv='Tvak:BAABNQAECn8WAAIJAAcKcxfjtAC1AQAJAAcKcxfjtAC1AQAAAA==.',
Tw='Twistedsham:BAAANQAECggIBgAAAA==.Twopump:BAABNQAECn80AAIJAAoKYQjUiAA/AQAJAAoKYQjUiAA/AQAAAA==.',
['Tó']='Tónka:BAAANQADCgcJBwABNQAECgEIAQAVAAAAAA==.',
Ul='Ulhae:BAAANQABCgQIBAAAAA==.Ulinova:BAAANQAECgcIDQAAAA==.',
Um='Umbressa:BAAANQADCgMIAwABNQAECgoKNAAKAAMaAA==.Umbryx:BAAANQADCgIIAgABNQAECgoKJQAQAOMJAA==.',
Un='Unholly:BAAANQAECgIJBAAAAA==.',
Ur='Uroro:BAACNQAFFH8HAAMYAAQK4BWNFwDnAAAYAAQK4BWNFwDnAAAXAAEK1QUpCQBEAAA1AAQKfzMAAxgACgoYIk0YABIDABgACgoYIk0YABIDABEAAQoAAONCASwAAAE1AAUUBQgSAAIAqh4A.',
Uu='Uu:BAAANQABCgIIAgAAAA==.',
Va='Vaiden:BAAANQABCgEIAQAAAA==.Vainqueur:BAABNQAECn8gAAIeAAkKwxp8BQD7AQAeAAkKwxp8BQD7AQAAAA==.Valienni:BAAANQAECgEIAQAAAA==.Vanderdemon:BAAANQADCgMIAwAAAA==.Vanderlight:BAAANQADCgUJCQAAAA==.Vandernum:BAAANQAECggIAwAAAA==.Vandersus:BAAANQADCggIBQAAAA==.Varm:BAAANQADCggICAAAAA==.',
Ve='Velakai:BAAANQABCgQIBAAAAA==.Vervaeda:BAAANQADCgQIBAAAAA==.Verymelon:BAAANQAECgQIBgABNQAFFAMIBgARAFYOAA==.Vestele:BAAANQADCggIDwAAAA==.',
Vg='Vgx:BAABNQAECn8lAAIiAAkK4gyIUQBrAQAiAAkK4gyIUQBrAQAAAA==.',
Vi='Vielitre:BAAANQAECgMIAwAAAA==.Vigossfel:BAAANQADCgMIBwAAAA==.Viintage:BAABNQAECn80AAIUAAoKCBVGOgAKAgAUAAoKCBVGOgAKAgAAAA==.Vintige:BAAANQAECgEIAQABNQAECgoKNAAUAAgVAA==.Viridius:BAAANQAECgEIAQAAAA==.Vishouspayne:BAAANQAECgUIEgAAAA==.',
Vo='Voidshank:BAAANQAECgEIAgAAAA==.',
Vy='Vyolence:BAAANQAECgYIBgABNQAECgoKKwATAIQcAA==.',
['Vä']='Väelün:BAABNQAECn8jAAMaAAgKFBG5GwBQAQAaAAgKFBG5GwBQAQANAAEKawTsmwAnAAAAAA==.',
['Vÿ']='Vÿ:BAAANQAECgUIEgAAAA==.',
Wa='Wachoosh:BAAANQAECgQIBwAAAA==.Waidmanns:BAABNQAECn80AAMKAAoKAxrAJwD5AgAKAAoKAxrAJwD5AgAoAAMKuwnsCgB+AAAAAA==.Walmartstaff:BAAANQADCgUIBQAAAA==.Warfable:BAAANQADCgIIAgAAAA==.',
Wg='Wgnmd:BAAANQAECgQIBQAAAA==.',
Wh='Wham:BAAANQAECgIIAwAAAA==.Whatsaggro:BAABNQAECn8lAAIMAAgKhwk9aABwAQAMAAgKhwk9aABwAQAAAA==.Whatyamean:BAABNQAECn8WAAIYAAcKtwb6gwC6AAAYAAcKtwb6gwC6AAAAAA==.Whiteeyedemo:BAAANQADCgYIBgAAAA==.Whoami:BAAANQAECggIBQAAAA==.Whoangry:BAABNQAECn8cAAMmAAkKHhO6RQCwAQAmAAkKgQ+6RQCwAQALAAUKMRI3SAA+AQAAAA==.Whomonk:BAAANQAECgIIBAAAAA==.',
Wi='Wickedchick:BAAANQADCggIHgAAAA==.Willowknight:BAAANQADCgYICgAAAA==.Wimdy:BAAANQAECgEIAQAAAA==.Winterknight:BAAANQADCgUICwAAAA==.',
Wr='Wrenn:BAAANQAECgcICwAAAA==.Wrongname:BAAANQAECgYICAAAAA==.',
Wu='Wumba:BAAANQAECgMIAwAAAA==.',
Xa='Xanthe:BAAANQADCggIBwAAAA==.',
Xf='Xfloki:BAAANQADCgQIBAAAAA==.',
Xi='Xiunlin:BAAANQAECgEIAQAAAA==.',
['Xß']='Xß:BAAANQADCgIJBAAAAA==.',
Ya='Yakpriest:BAAANQADCgcIDAAAAA==.Yawg:BAEANQADCgYIBgABNQAECgoKNAAKAP8dAA==.',
Yd='Ydgktt:BAAANQADCgMIBAAAAA==.',
Yn='Ynhük:BAAANQADCgMIAwAAAA==.',
Yo='Yogsothoth:BAEBNQAECn80AAIKAAoK/x0LKQD0AgAKAAoK/x0LKQD0AgAAAA==.',
Yr='Yrdenal:BAAANQAECgEIAQAAAA==.',
Yu='Yugalipdeez:BAAANQAECgEIAwAAAA==.Yulian:BAAANQAECgUIDwAAAA==.',
Za='Zaartyn:BAABNQAECn80AAIQAAoKGSKjEwA+AwAQAAoKGSKjEwA+AwAAAA==.Zaater:BAAANQAECgIIBQAAAA==.Zalin:BAAANQAECgEIAQABNQAECgoKJQAcAAwQAA==.Zanki:BAAANQAECgUIDAAAAA==.',
Ze='Zeebeth:BAABNQAECn8YAAIKAAkKfw8wjQDwAQAKAAkKfw8wjQDwAQAAAA==.Zefi:BAAANQAECgcIAgAAAA==.Zellek:BAAANQADCgYIBgAAAA==.Zenbu:BAAANQADCgIIAgAAAA==.Zeroasy:BAAANQADCgIIAgABNQAECggIKAAjAFkhAA==.Zerokai:BAAANQAECgQIBwAAAA==.Zeztz:BAAANQAECgcIDAAAAA==.',
Zo='Zomlo:BAAANQAECgQIBQAAAA==.Zooli:BAAANQADCggICAAAAA==.Zorosenpai:BAAANQADCgcIEQABNQAECggIIgAiAJ8KAA==.',
Zu='Zuggernaught:BAAANQAECgUIBwABNQAECgUICwAVAAAAAA==.',
['Át']='Átomic:BAAANQADCgUIAwAAAA==.',
['Ân']='Ânimosity:BAAANQADCgIIAgAAAA==.',
['Âr']='Ârtemis:BAAANQAECgQIBAABNQAFFAUIDQAHAPMbAA==.',
['År']='Åres:BAAANQAECgEIAQAAAA==.',
['Ís']='Ísvala:BAAANQADCgYIBgAAAA==.',
['ßu']='ßuzzibee:BAAANQAECgYICwABNQAECgcIEwAVAAAAAA==.',
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
