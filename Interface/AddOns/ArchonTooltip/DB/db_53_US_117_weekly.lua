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

local lookup = {'Warrior-Arms','Warrior-Fury','Druid-Restoration','Paladin-Protection','Monk-Windwalker','Priest-Holy','DemonHunter-Vengeance','Paladin-Holy','Paladin-Retribution','Hunter-BeastMastery','DeathKnight-Unholy','DemonHunter-Havoc','Druid-Guardian','Druid-Feral','Warlock-Demonology','Shaman-Elemental','Monk-Mistweaver','Priest-Shadow','Mage-Arcane','Unknown-Unknown','Priest-Discipline','Rogue-Subtlety','Shaman-Enhancement','Shaman-Restoration','Hunter-Marksmanship','Warlock-Destruction','Warlock-Affliction','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Mage-Frost','Druid-Balance','DeathKnight-Frost','DeathKnight-Blood','Monk-Brewmaster','DemonHunter-Devourer','Warrior-Protection','Mage-Fire','Hunter-Survival','Rogue-Assassination',}
local provider = {region='US',realm='Hakkar',name='US',type='weekly',zone=53,date='2026-10-20',data={Ac='Aceshaman:BAAANQADCgIIAgAAAA==.Acheros:BAAANQADCgMIAwAAAA==.Actionfigure:BAACNQAFFH8KAAIBAAQKyCCkFQB7AQABAAQKyCCkFQB7AQA1AAQKfyYAAwEACgrMHmA3AOYCAAEACgpoHmA3AOYCAAIAAwqVJAEKAOEAAAAA.',
Ad='Adielia:BAABNQAECn8hAAIDAAgKuxqLCACxAQADAAgKuxqLCACxAQAAAA==.Adurzin:BAAANQADCgIIAgAAAA==.',
Ae='Aeralina:BAAANQADCgUJBQAAAA==.Aeri:BAAANQADCgIIAwAAAA==.Aevalaana:BAAANQAECgYICQAAAA==.',
Ag='Agiermodinn:BAAANQADCgYICgAAAA==.',
Ah='Ahnho:BAAANQADCggICgAAAA==.',
Ai='Aidandrius:BAAANQADCgMIAwAAAA==.Aimeeleigh:BAAANQAECgEIAQABNQAECgcIHAAEAOUbAA==.Airflash:BAACNQAFFH8MAAIFAAUKEx4tCQBFAQAFAAUKEx4tCQBFAQA1AAQKfzkAAgUACAo/JasHAFQDAAUACAo/JasHAFQDAAAA.Aiøn:BAAANQADCgcIBwAAAA==.',
Ak='Akutagawa:BAABNQAECn8YAAIGAAkKXRd0SwBDAgAGAAkKXRd0SwBDAgABNQAFFAQICQAHABwYAA==.',
Al='Alexious:BAACNQAFFH8OAAIEAAUKhx8ZBACfAQAEAAUKhx8ZBACfAQA1AAQKfy8AAgQACgoCIk4HAC4DAAQACgoCIk4HAC4DAAAA.Aloonarn:BAAANQAECgUICwAAAA==.Alopix:BAAANQAECgcIEAAAAA==.Alulla:BAACNQAFFH8SAAMCAAUKqh7rAQD0AAABAAQKqh5tFwBnAQACAAMKwRjrAQD0AAA1AAQKfx8AAwIACgrpIK0KAB0CAAEACQr5HyJJAK4CAAIABwoTIq0KAB0CAAAA.Alunira:BAABNQAECn8tAAMIAAoKMBzgGAAVAwAIAAoKMBzgGAAVAwAJAAYKbhYTzQCBAQAAAA==.',
Am='Amberrfrost:BAAANQAECgQICgAAAA==.Amize:BAAANQADCgYIBgAAAA==.Ampz:BAAANQAECgIIAgAAAA==.',
An='Anabee:BAAANQADCggIDgAAAA==.Angelicshy:BAAANQADCgQIBAAAAA==.Angryhtr:BAABNQAECn8UAAIKAAcKGhkydgAjAgAKAAcKGhkydgAjAgAAAA==.Angrysh:BAAANQADCggIDAAAAA==.Angrywar:BAABNQAECn8bAAIBAAgKHxL9nADUAQABAAgKHxL9nADUAQAAAA==.Anharon:BAAANQADCgcICgAAAA==.Ansatz:BAAANQAECgIICAABNQAECgoKMQAKAAMaAA==.',
Ap='Apokalypto:BAAANQAECgQIBgAAAA==.',
Ar='Arbiterbinky:BAAANQADCgUIBQAAAA==.Ardå:BAAANQADCgEIAQAAAA==.Areina:BAAANQAECgEIAQAAAA==.Argangus:BAAANQADCgYIDwAAAA==.Arthan:BAAANQAECgMIBgAAAA==.Arthannix:BAAANQAECgEIAQAAAA==.',
As='Astanis:BAAANQAECgUICgAAAA==.Asteriia:BAAANQAECggIEwAAAA==.Astralyn:BAAANQAECgEIAQAAAA==.',
Au='Augito:BAAANQABCgIIAgAAAA==.',
Av='Averettara:BAAANQAECgIIBwABNQAECggIJQALAIcJAA==.',
Az='Azarazan:BAAANQADCgYIDgAAAA==.Azka:BAABNQAECn8jAAIJAAoKkx3uLwAKAwAJAAoKkx3uLwAKAwAAAA==.Azkadk:BAAANQADCgYIBgAAAA==.',
Ba='Babybilly:BAABNQAECn8cAAMEAAcK5RvBHQD7AQAEAAcK5RvBHQD7AQAJAAMKkAOgcAFtAAAAAA==.Baelmon:BAAANQAECgEIAQAAAA==.Baludis:BAAANQADCgcIEQAAAA==.Bamff:BAAANQAECgUIDQAAAA==.Bamfpally:BAAANQAECgEIAQAAAA==.Barreack:BAAANQADCgYICAAAAA==.Bast:BAACNQAFFH8JAAIHAAQKHBg8AgAuAQAHAAQKHBg8AgAuAQA1AAQKfy4AAwcACgoeIV0DADIDAAcACgoeIV0DADIDAAwABQpFE2pSAEoBAAAA.Basthara:BAABNQAECn8VAAMNAAoKvx+/BQA7AwANAAoKvx+/BQA7AwAOAAEKVAIbUwAGAAABNQAFFAQICQAHABwYAA==.',
Be='Beckianslip:BAAANQADCgUIBQAAAA==.Belphegor:BAAANQAECgYIBgABNQAECgkJHwAPACMKAA==.Benif:BAACNQAFFH8NAAIBAAYKVRy6DwC7AQABAAYKVRy6DwC7AQA1AAQKfygAAgEACgriI/8IAKwDAAEACgriI/8IAKwDAAAA.Benjaquel:BAAANQADCgQIBAAAAA==.Bertorod:BAABNQAECn8XAAIQAAgK+BYfWAAbAgAQAAgK+BYfWAAbAgAAAA==.Bewblover:BAAANQAECgEIAgAAAA==.',
Bi='Bigbitehotdo:BAABNQAECn8xAAMFAAoKMB6MDgD3AgAFAAoKMB6MDgD3AgARAAEK3wHaVAAgAAAAAA==.Bighoney:BAAANQAECgEIAQAAAA==.Bigtommybuns:BAAANQADCgUIBQAAAA==.Binkyfiasco:BAAANQAECgEIAQAAAA==.Binny:BAAANQADCgYIBgAAAA==.Birdiewordie:BAAANQAECgEIAQAAAA==.',
Bl='Bloodeie:BAAANQADCgQIBAAAAA==.Bloodstoned:BAAANQAECgUIDgAAAA==.Blueboy:BAABNQAECn8eAAISAAoKJgztAwDNAQASAAoKJgztAwDNAQAAAA==.',
Bo='Boffadz:BAAANQAECggIEgAAAA==.Bonewand:BAAANQAECgEIAgAAAA==.Bonewrath:BAAANQAECgEIAgAAAA==.Boogat:BAAANQAECgQIBQAAAA==.Bovillus:BAAANQADCgEIAQAAAA==.',
Br='Braugorlle:BAAANQAECgYIBgABNQAFFAUIDgAQAAEUAA==.Breadscrumb:BAAANQADCgUJBQAAAA==.Briandejay:BAAANQAECgIIAQAAAA==.Bridrystina:BAAANQADCgQIBAAAAA==.Brixlo:BAAANQAECgEIAQAAAA==.',
Bu='Buffmuffin:BAAANQAECgIIAgAAAA==.Burblbiblr:BAAANQAECgEIAQAAAA==.Bustrdugles:BAAANQADCgUIBQAAAA==.',
Bw='Bwazakki:BAAANQADCgMIAwAAAA==.Bwr:BAAANQADCgMIAwAAAA==.',
['Bü']='Bübbawrap:BAAANQAECgQIBQAAAA==.',
Ca='Cambrier:BAABNQAECn87AAMBAAoKmiB3BACdAgACAAgKoiAIBQDbAgABAAoK7x53BACdAgAAAA==.Cameraop:BAABNQAECn8XAAITAAcKKwj2EgFtAQATAAcKKwj2EgFtAQAAAA==.Candyapples:BAAANQADCgUIBQAAAA==.Capnsoap:BAAANQADCgYIBgABNQABCgEIAQAUAAAAAA==.Capnsöap:BAAANQAECgEIAQABNQABCgEIAQAUAAAAAA==.Capriestsun:BAAANQAECggICgAAAA==.Cardinal:BAAANQAECgEIAwAAAA==.Carynden:BAAANQAECgUIBQAAAA==.Castbo:BAAANQAECgcIEwABNQAFFAUIFAAVADwRAA==.',
Ce='Celilinia:BAAANQAECgIIAgAAAA==.Cellesstia:BAAANQADCgMIBQABNQAECgMIAwAUAAAAAA==.',
Ch='Chaiharder:BAAANQADCgYIBgAAAA==.Chalada:BAAANQADCgEIAQABNQAFFAcIBwAWAA4AAA==.Chalastorm:BAAANQAECggIAQABNQAFFAcIBwAWAA4AAA==.Charknight:BAAANQADCgUIBQAAAA==.Chatdodu:BAAANQADCgUIBQAAAA==.Chatnoir:BAAANQAECgUICwAAAA==.Chestock:BAAANQADCgYIBgAAAA==.Chuggz:BAAANQAECgQIBgAAAA==.',
Cl='Clonetastic:BAAANQADCggICAAAAA==.Clumsycarl:BAAANQADCgIIAgAAAA==.',
Cm='Cmx:BAAANQADCgUIBQAAAA==.',
Co='Codith:BAAANQAECgQIBQAAAA==.Coldlock:BAAANQADCgQIBAAAAA==.Colesiaw:BAAANQADCgQIBgAAAA==.Coraeze:BAAANQADCgEJAQAAAA==.',
Cr='Creek:BAAANQABCgYIBgABNQAECggIIwAMAHshAA==.Crnogorac:BAAANQAECggIAQAAAA==.Crotchgoblim:BAAANQADCgcIFAAAAA==.Cryodormu:BAAANQAECgMJAwAAAA==.',
Cu='Cubo:BAAANQAECgEIAwAAAA==.Cuddlesworth:BAABNQAECn8fAAIPAAkKIwoGJABeAQAPAAkKIwoGJABeAQAAAA==.',
Cw='Cwarr:BAAANQAECgIIAgABNQAFFAUICAAXAPAKAA==.',
Cy='Cyrcee:BAAANQADCgUIBQABNQAECgMIAwAUAAAAAA==.',
Da='Daddyluis:BAAANQADCggICgAAAA==.Dadstonks:BAAANQAECgEIAQAAAA==.Dagoujiao:BAABNQAECn8UAAMQAAoKTgp+SwCtAAAQAAgKOwp+SwCtAAAYAAcKGg3QXACgAAAAAA==.Dameiyo:BAAANQAECggIEgAAAA==.Dandanh:BAAANQADCgMIAwAAAA==.Dangright:BAABNQAECn8aAAIZAAgKXwVBPgBgAQAZAAgKXwVBPgBgAQAAAA==.Dankbo:BAACNQAFFH8UAAMVAAUKPBEfAgDVAAAGAAQKHhUiGAAyAQAVAAMK1ggfAgDVAAA1AAQKfzoAAxUACQooI7MCAOQCABUACAq6ILMCAOQCAAYACQqOHvYlANMCAAAA.Danorac:BAAANQAECgQIDgAAAA==.Darkcoffee:BAAANQAFFAEIAQAAAA==.Darkivie:BAAANQADCgYIBgABNQAECgkJHgAJAGMFAA==.',
De='Deadashe:BAAANQADCgEIAQAAAA==.Demonicsword:BAAANQADCgQIBAAAAA==.Despondent:BAAANQADCggIFgAAAA==.Devilcrybaby:BAAANQAECgIIAgAAAA==.Devildj:BAAANQAECgYIDQAAAA==.Dezadian:BAABNQAECn8aAAIJAAYKLQSIpgCUAAAJAAYKLQSIpgCUAAAAAA==.',
Dh='Dhampyra:BAABNQAECn8UAAMSAAgKOBOFJQADAgASAAgKOBOFJQADAgAGAAIK+BAg4wB/AAAAAA==.',
Di='Didicoralie:BAAANQADCgEJAQAAAA==.Dietmountdew:BAAANQADCgEJAQAAAA==.Dimitrios:BAAANQAECgcIDQAAAA==.Disolve:BAABNQAECn8gAAQPAAkKFBGueAD5AQAPAAkKog2ueAD5AQAaAAIK9hY7UgCIAAAbAAEKAABKJQBZAAAAAA==.Dixxonciderr:BAABNQAECn9BAAQcAAoKHh6PCQAKAwAcAAoKHh6PCQAKAwAdAAcKiw/FIABNAQAeAAIKWRX9HQByAAAAAA==.',
Dm='Dmoe:BAAANQAECgQIDgAAAA==.',
Do='Doji:BAAANQADCgEIAQAAAA==.',
Dq='Dqe:BAAANQAECgEIAwAAAA==.',
Dr='Drac:BAAANQADCgMIAwAAAA==.Dribby:BAAANQAECgIIAgAAAA==.',
Du='Duhästmich:BAAANQADCgYIBgABNQAECggIJQALAIcJAA==.Duplicate:BAACNQAFFH8PAAMTAAQKjBQXEQDWAAATAAQKjBQXEQDWAAAfAAIKGA8TCQCOAAA1AAQKfyUAAxMACgpbGDKdAEYCABMACgpbGDKdAEYCAB8AAQonG6BBAEEAAAAA.Dustdruid:BAACNQAFFH8FAAIgAAMKdxCdGgDNAAAgAAMKdxCdGgDNAAA1AAQKfykAAiAACQrGH28eANcCACAACQrGH28eANcCAAAA.Dustlock:BAAANQAECggIEQAAAA==.Dustmage:BAAANQADCggIEAAAAA==.',
Dw='Dwarr:BAAANQAECgYICAAAAA==.',
Dy='Dysnomia:BAAANQAECgIIAgAAAA==.',
['Dó']='Dóru:BAAANQADCgYIBwAAAA==.',
Ee='Eender:BAAANQAECgEIAQAAAA==.',
Eg='Eggrolls:BAABNQAECn88AAIBAAoKBhsAIwAsAwABAAoKBhsAIwAsAwAAAA==.',
El='Eldenmorden:BAAANQADCgYIBgAAAA==.Eleshmelly:BAAANQADCgcIFgAAAA==.Elfrafa:BAAANQADCgEIAQAAAA==.Ellayna:BAAANQADCgEIAQAAAA==.Ellcrys:BAABNQAECn8yAAIDAAoKBBaABAApAgADAAoKBBaABAApAgAAAA==.Elletta:BAAANQAECgEIAwAAAA==.Elrae:BAAANQAECgYIBgAAAA==.',
Ep='Epoptes:BAAANQAECgQIBQABNQAECgcIGgAEAJYLAA==.',
Eq='Eqo:BAABNQAECn8dAAMGAAkKERI8eQCvAQAGAAkKERI8eQCvAQASAAEKxQl3dAA9AAAAAA==.',
Er='Erisian:BAAANQAECgQIBQAAAA==.Erkêios:BAABNQAECn8XAAIhAAgKThB7QwC2AQAhAAgKThB7QwC2AQAAAA==.Ersande:BAAANQAECgMIAwAAAA==.Ertz:BAAANQADCggICQAAAA==.',
Es='Escherichia:BAAANQAECgEJAQAAAA==.Estheban:BAABNQAECn8gAAQdAAkKOR9zAwB7AQAdAAkKOR9zAwB7AQAeAAMKFRZxCwBZAAAcAAEKQAtiUAAtAAAAAA==.',
Ev='Evengelist:BAAANQAECgYIDQABNQAECgoKIAAIAB8MAA==.',
Fa='Face:BAAANQAECgUIBgAAAA==.Fairgrim:BAAANQAECgQIBQAAAA==.Falin:BAABNQAECn9CAAIJAAoKgBswQwDLAgAJAAoKgBswQwDLAgAAAA==.Faqueuedark:BAAANQAECggIEgABNQAFFAIIBQAHAPcNAA==.Faqueueeight:BAACNQAFFH8FAAMHAAIK9w0rAgBpAAAHAAIK9w0rAgBpAAAMAAEKvAOUIAAxAAA1AAQKf0UAAwcACgr0H1YCAK4BAAwACgq0HxoSAA4DAAcACgoWFlYCAK4BAAAA.Fatsloth:BAAANQAECgUICQAAAA==.Fatébringer:BAAANQADCgYIDAABNQAECgEIAQAUAAAAAA==.Faulted:BAAANQADCgUIBQAAAA==.',
Fe='Feironos:BAAANQAECgEIAQAAAA==.Felcookies:BAAANQAECgYIDQAAAA==.Ferrick:BAAANQAECgIIAgAAAA==.',
Fi='Fimtastic:BAABNQAECn8eAAIYAAgKCBTqfQCSAQAYAAgKCBTqfQCSAQAAAA==.Finasy:BAABNQAECn8iAAMiAAcKRiQ1GwDVAgAiAAcKRiQ1GwDVAgAhAAMKSQ00SwB/AAAAAA==.Finbezy:BAAANQAECgQIAwAAAA==.Finnicka:BAAANQAECgEIAQAAAA==.Firen:BAAANQADCgcIFAAAAA==.Fistymisty:BAABNQAECn8cAAIjAAkKix98BAAvAwAjAAkKix98BAAvAwAAAA==.Fizeecian:BAAANQADCggIDQAAAA==.',
Fl='Flaynpray:BAAANQADCgEIAQAAAA==.Fluffenstein:BAAANQAFFAMIBAAAAA==.',
Fo='Foxrawruwu:BAABNQAECn8WAAIPAAgKqRqZNgCxAgAPAAgKqRqZNgCxAgAAAA==.',
Fr='Frakk:BAAANQAECggIAQAAAA==.Freezegarr:BAABNQAECn8eAAITAAoKMh1fDwDuAQATAAoKMh1fDwDuAQAAAA==.Frostgrave:BAAANQADCgEIAQAAAA==.Frostya:BAAANQADCgYIBgAAAA==.',
Fu='Furearia:BAAANQABCgcICQAAAA==.Furrybowner:BAAANQAECggICAAAAA==.',
Ga='Galeriel:BAACNQAFFH8NAAIGAAMK6yL0FwA0AQAGAAMK6yL0FwA0AQA1AAQKfzcAAgYACgriJd4AAMoDAAYACgriJd4AAMoDAAAA.Gallethline:BAAANQAECgIIAwAAAA==.Ganjgotti:BAAANQADCgYICQAAAA==.Garault:BAAANQAECgYICgAAAA==.Gavered:BAAANQADCgMIBQAAAA==.',
Ge='Gekoni:BAAANQAECgUIBQAAAA==.Geonon:BAAANQADCggICAAAAA==.Geotracker:BAABNQAECn8XAAIKAAcKdQ9rnwDIAQAKAAcKdQ9rnwDIAQABNQADCggICAAUAAAAAA==.',
Gh='Ghorros:BAAANQADCgMIAwAAAA==.',
Gi='Gilgahmesh:BAAANQAECggIEAABNQAECgoKLAAIAFsdAA==.',
Gl='Glowpwr:BAAANQADCgcIBwAAAA==.',
Go='Goolgame:BAACNQAFFH8OAAMQAAUKARRiBQD8AAAQAAUKARRiBQD8AAAYAAMKXBXeFgDwAAA1AAQKfygAAxAACgp7Hso8AIICABAACAoEH8o8AIICABgABQq9G2SHAHgBAAAA.Goonthergg:BAAANQAECgEIAQAAAA==.Goothix:BAAANQADCgcJCAAAAA==.Gothmog:BAAANQADCgIIAgAAAA==.',
Gr='Grammarg:BAAANQADCgMIAwAAAA==.Grirr:BAAANQAECgIIBAAAAA==.Grothin:BAABNQAECn8mAAIYAAoKDhjiBgBfAgAYAAoKDhjiBgBfAgAAAA==.Gruldag:BAABNQAECn8xAAITAAoKUBsmXQDFAgATAAoKUBsmXQDFAgAAAA==.Grullander:BAABNQAECn8xAAIYAAgKyhPwGwB+AQAYAAgKyhPwGwB+AQAAAA==.',
Gu='Guiguiie:BAAANQADCggJEAAAAA==.',
Gw='Gwyndolynn:BAAANQADCgQIBAAAAA==.',
Ha='Hailey:BAEBNQAECn8WAAIGAAkKhRibKwC6AgAGAAkKhRibKwC6AgABNQAFFAUICgAIAEYMAA==.Halter:BAAANQAECgIIAgAAAA==.Hapló:BAAANQABCgEIAQAAAA==.Haratvy:BAAANQAECgEIAgAAAA==.Hazzurd:BAABNQAECn8aAAIKAAgKZRO8cwApAgAKAAgKZRO8cwApAgAAAA==.',
He='Header:BAACNQAFFH8aAAIZAAcKwhmiBQACAgAZAAcKwhmiBQACAgA1AAQKfyUAAxkACgqqGs8FAI8BABkACgqqGs8FAI8BAAoABQrhCjP9AAoBAAAA.Healsorz:BAAANQADCgcIBwAAAA==.Heersbeest:BAAANQAECgEIAwAAAA==.Helane:BAAANQAECgEIAgAAAA==.Herkharu:BAAANQADCgcIBwAAAA==.Hermionee:BAABNQAECn8tAAMTAAgKgBDsaQDpAAATAAcKwArsaQDpAAAfAAIK6RmWEACCAAAAAA==.Hetu:BAAANQABCgUIBAAAAA==.',
Hi='Hide:BAAANQAECgEIAQAAAA==.Himjongun:BAABNQAECn8fAAMMAAoKNBdeFABJAQAMAAkKNBdeFABJAQAkAAEKAADddQAiAAAAAA==.',
Ho='Holya:BAAANQADCgEIAQABNQAFFAcIBwAWAA4AAA==.Holycowe:BAAANQAECgQIBAAAAA==.Holykoi:BAABNQAECn8wAAIGAAkKcQ5LGQCqAQAGAAkKcQ5LGQCqAQAAAA==.',
Hr='Hroarr:BAABNQAECn8ZAAIiAAoKRSKTDgA7AwAiAAoKRSKTDgA7AwABNQAECgoKHgATADIdAA==.',
Hu='Humancarnage:BAAANQADCgYIBwAAAA==.Huuh:BAAANQADCgQIBwAAAA==.',
Hy='Hypaexia:BAAANQADCgIIAgAAAA==.',
['Hà']='Hàvoc:BAAANQADCggIDQAAAA==.',
['Hé']='Héboric:BAABNQAECn8fAAIIAAkKIR0XBgBuAgAIAAkKIR0XBgBuAgAAAA==.Hélbrecht:BAAANQAECgMIAwAAAA==.',
['Hÿ']='Hÿbrìd:BAAANQAECgYIEAAAAA==.',
Ia='Iamwho:BAAANQAECggICAAAAA==.Iatros:BAABNQAECn8aAAMEAAcKlgvTPQAHAQAEAAYKfw3TPQAHAQAJAAIKzgMWCgElAAAAAA==.',
Id='Idkno:BAAANQAECgEIAQAAAA==.',
Ik='Ikara:BAAANQADCggICAABNQAECgoKJAAbAKUPAA==.Ikodiwa:BAAANQADCgUIBQAAAA==.',
Il='Ilrion:BAAANQAECgEIAQAAAA==.',
Im='Imjustsaiyan:BAAANQADCgIIAgAAAA==.',
In='Indravax:BAABNQAECn8XAAIPAAkKQRSBFwCVAQAPAAkKQRSBFwCVAQAAAA==.',
Io='Iorin:BAAANQADCggIBwABNQAECgkJIAAMADoOAA==.',
It='Itwasntmebru:BAAANQADCgYIDgAAAA==.',
Iv='Ivantis:BAAANQADCgYIFwAAAA==.Ivie:BAAANQAECgMIAwAAAA==.',
Iw='Iwonabhornee:BAAANQADCgIIAgAAAA==.',
Ja='Jaholypriest:BAACNQAFFH8JAAIGAAMKsRQMDgDWAAAGAAMKsRQMDgDWAAA1AAQKfx4AAgYACgpmFYszADEBAAYACgpmFYszADEBAAAA.Janjor:BAAANQAECgIIAwAAAA==.Janjy:BAAANQADCgcIBwAAAA==.Jaypiea:BAABNQAECn8iAAMeAAkKTBUCCAAgAgAeAAgKTBUCCAAgAgAdAAgK8xC2FwDOAQAAAA==.',
Je='Jergall:BAAANQADCgUIBQAAAA==.Jettian:BAAANQAECgUIEAAAAA==.',
Ji='Jibz:BAAANQADCgEIAQAAAA==.',
Jj='Jjdruid:BAAANQAECgIIAgAAAA==.',
Jo='Johnathon:BAAANQAECgIIAQABNQAECgMIBAAUAAAAAA==.Jollygreene:BAAANQAECgEIBQAAAA==.Jonestu:BAAANQAECgEIAQAAAA==.',
Jp='Jpgigacat:BAAANQAECgYICAAAAA==.Jpgigademon:BAAANQAECgMIBAAAAA==.',
Ju='Justakatt:BAAANQAECgEIAQAAAA==.Justicasia:BAAANQADCgQIBAABNQADCgYIBgAUAAAAAA==.',
Ka='Kadinsky:BAAANQADCgUIBQAAAA==.Kalivan:BAAANQADCgYIBwAAAA==.Kankimasamu:BAAANQADCgIIAgAAAA==.Karametra:BAAANQAECgYIBgAAAA==.Karlldun:BAAANQAECgYICgAAAA==.Kasmir:BAABNQAECn8iAAMPAAgKhw+blwCsAQAPAAcK/xCblwCsAQAaAAEKLggUfQAwAAAAAA==.Kasnfriends:BAAANQADCgUIBQABNQAECggIIgAPAIcPAA==.',
Ke='Kevv:BAACNQAFFH8NAAIQAAUKJQNiGAD/AAAQAAUKJQNiGAD/AAA1AAQKfyQAAxAACgrvEnRSAC8CABAACgrvEnRSAC8CABcAAQoAAPI7ABkAAAAA.Keyniron:BAABNQAECn+OAAIJAAkKISVCAQBBAwAJAAkKISVCAQBBAwAAAA==.',
Kh='Khogent:BAAANQAECgEIAgAAAA==.Khonsu:BAAANQAECgQIBQAAAA==.Khrover:BAAANQADCgUIBQAAAA==.Khyle:BAAANQADCgYIBwAAAA==.',
Ki='Kijanajr:BAAANQADCgMIAgAAAA==.Killaarrow:BAABNQAECn8wAAIKAAkKHggvHwCbAQAKAAkKHggvHwCbAQAAAA==.Kindleos:BAAANQAECgEIAQAAAA==.',
Kk='Kkpriest:BAAANQADCgEIAQAAAA==.',
Kl='Klay:BAAANQAECgYIEQAAAA==.',
Km='Kmarte:BAEANQAECgYIEgABNQAECgQIBAAUAAAAAA==.Kmarti:BAEANQAECgQIBAAAAA==.Kmartt:BAEBNQAECn8cAAIJAAoK1hOjdgA/AgAJAAoK1hOjdgA/AgABNQAECgQIBAAUAAAAAA==.',
Ko='Kosmic:BAAANQADCgcICQABNQAECggIHwAiALwZAA==.Kosmicknight:BAABNQAECn8fAAMiAAgKvBk1NwAtAgAiAAgKvBk1NwAtAgAhAAEKAAA4twAoAAAAAA==.',
Kr='Kraggers:BAAANQAECgYIDQAAAA==.Kraggory:BAAANQAECgIIAgAAAA==.Kraggoryqt:BAAANQAECgMICgAAAA==.Kraggoryx:BAAANQAECgEIAQAAAA==.Kruncle:BAAANQAECgIIAgAAAA==.Kryesta:BAABNQAECn87AAIYAAoKgCCcBQCAAgAYAAoKgCCcBQCAAgAAAA==.',
Kw='Kwarr:BAACNQAFFH8IAAIXAAUK8AqjAwA8AQAXAAUK8AqjAwA8AQA1AAQKfzQAAhcACgqRIBsBAI8CABcACgqRIBsBAI8CAAAA.',
La='Laganddecay:BAAANQABCggIGQAAAA==.Lalii:BAAANQAECgEIAQAAAA==.Lallypop:BAAANQAECgEIAQAAAA==.Lammoth:BAAANQADCgYICwAAAA==.Lanemogsnick:BAAANQADCgQIBAAAAA==.Layonhandsy:BAAANQAECgQIBAABNQAFFAQICQAiABYhAA==.',
Le='Leasin:BAABNQAECn8kAAISAAkK6xywEwDKAgASAAkK6xywEwDKAgAAAA==.Lencreye:BAAANQADCgMIBAAAAA==.Lethendervis:BAAANQADCgYIDgAAAA==.',
Li='Lighthusk:BAAANQABCgQIBAAAAA==.Liliauna:BAABNQAECn8jAAIPAAcK+xr9aQAeAgAPAAcK+xr9aQAeAgAAAA==.Lilibejeane:BAAANQADCgcIDgABNQAECgYIEAAUAAAAAA==.Lillynelazar:BAABNQAECn8ZAAIKAAkKNQUwtwCVAQAKAAkKNQUwtwCVAQABNQAECgYICQAUAAAAAA==.Liloisback:BAABNQAECn8WAAIBAAkKmxBikwDsAQABAAkKmxBikwDsAQAAAA==.Lilsquirtboy:BAAANQADCgUIBQABNQAECgoKMQAFADAeAA==.Linasonna:BAAANQAECgIIBAABNQAFFAUIDgAQAAEUAA==.Linithara:BAABNQAECn8gAAMMAAkKOg4MNwD4AQAMAAkK1AwMNwD4AQAHAAgK5QmcFgBDAQAAAA==.Littlehoosie:BAAANQAECggICgAAAA==.',
Lo='Lockersz:BAAANQADCgEIAQABNQAFFAYIFAAhAIsXAA==.Loram:BAAANQAECgIIBAAAAA==.Lostbase:BAAANQAECgQIBAAAAA==.Lostgrip:BAAANQAECgUICAAAAA==.',
Lu='Lucthedk:BAABNQAECn8WAAMLAAkK/xAzTADkAQALAAkK/xAzTADkAQAhAAQKWwrPeADBAAAAAA==.Lukis:BAAANQAECgQIBwAAAA==.Lunarpriest:BAAANQAECgQIBQAAAA==.Lunitari:BAAANQAECgEIAgAAAA==.Lunkbeck:BAAANQAECgEIAgAAAA==.',
['Lø']='Lørd:BAABNQAECn8mAAMZAAoKXxp2IABLAgAZAAgKwhZ2IABLAgAKAAcKIBdMLgBmAQAAAA==.',
Ma='Madik:BAAANQADCgcJCAAAAA==.Magicmegan:BAAANQAECgEIAQABNQAECggIFgAPAKkaAA==.Maladin:BAAANQAECgIIBQAAAA==.Malkurim:BAAANQADCgEIAQAAAA==.Malvean:BAAANQADCgUIBwAAAA==.Manamommyy:BAAANQAECgEIAQAAAA==.Manasa:BAAANQAECgQICwAAAA==.Marceline:BAABNQAECn8cAAIKAAkKvBL7awA7AgAKAAkKvBL7awA7AgAAAA==.Marthahog:BAAANQAECgYIBgABNQAECgYIEQAUAAAAAA==.Marthog:BAAANQAECgYIEQAAAA==.Matresstains:BAAANQAECgUIDgAAAA==.',
Mc='Mcdermott:BAAANQAECgQIBwAAAA==.',
Me='Melanius:BAAANQAECgUIEAAAAA==.Melranis:BAAANQADCgcIDAAAAA==.',
Mi='Miluk:BAAANQAECgYICwAAAA==.Misconduct:BAAANQAECgUIDQABNQAECgYICgAUAAAAAA==.',
Mm='Mmins:BAAANQAECgYICgAAAA==.',
Mo='Montagne:BAAANQADCgQIBAAAAA==.Moomist:BAAANQAECgMIAwAAAA==.Moondarin:BAAANQABCgIIAgAAAA==.Moonfanna:BAAANQAECgQJBQAAAA==.Moonmx:BAAANQAECgYICQAAAA==.Moosesunaxe:BAAANQAECgEIAQAAAA==.Morriganth:BAAANQADCgEIAQAAAA==.',
Mu='Murdamoose:BAAANQADCgIIAgAAAA==.Mustysponge:BAAANQADCgUIBwAAAA==.',
My='Mysteryx:BAABNQAECn8lAAISAAoKYRSuGQCAAgASAAoKYRSuGQCAAgAAAA==.Mystrbeast:BAAANQADCgQIBAAAAA==.',
['Mó']='Móxie:BAAANQADCgIIAQAAAA==.',
Na='Nahtan:BAAANQADCgYIDAAAAA==.Nammu:BAAANQADCgEIAQAAAA==.Nandisa:BAAANQAECgEIAgAAAA==.Naniwa:BAAANQAECgMIBwAAAA==.Nawala:BAAANQAECgEIAQAAAA==.Nazendrov:BAEANQAECggICAABNQAECggICAAUAAAAAA==.Nazura:BAAANQADCgcIEQAAAA==.',
Ne='Nereza:BAAANQADCgYIDAAAAA==.Nershog:BAAANQAECgEIAQAAAA==.Nesquip:BAAANQADCgYJBgAAAA==.',
Ni='Nightforday:BAABNQAECn8zAAMLAAkKiSDHIwC0AgALAAkKiSDHIwC0AgAhAAIKUhVhjgB+AAAAAA==.Niko:BAAANQABCgUIBQAAAA==.Nishra:BAAANQADCggICAAAAA==.',
No='Noks:BAAANQAECgYIAgAAAA==.Noktas:BAAANQAECgMIBwABNQAECggICwAUAAAAAA==.Nominé:BAAANQADCgQIBgAAAA==.Nool:BAAANQADCgQIBwAAAA==.Norch:BAAANQAECgIJBgAAAA==.Notkory:BAAANQAECggICAAAAA==.Noux:BAAANQAECgUIBQAAAA==.',
Nu='Nube:BAAANQADCgUICAAAAA==.',
Ny='Nyababa:BAAANQAECgYICAABNQAFFAUIEgACAKoeAA==.',
Og='Ogora:BAAANQADCgQIBgAAAA==.',
Ok='Oki:BAAANQADCgMIBAAAAA==.Okktrål:BAAANQAECgYJDAAAAA==.Oktavius:BAABNQAECn8bAAIYAAoKYB2NAQBkAwAYAAoKYB2NAQBkAwAAAA==.',
On='Onlyvel:BAAANQAECgEIAgAAAA==.',
Op='Ophysia:BAAANQAECgIIAgAAAA==.',
Or='Ordaka:BAAANQADCgYIBgAAAA==.Orkcansas:BAAANQAECgEIAQAAAA==.Orruutah:BAAANQADCgYIBgAAAA==.',
Os='Oskaia:BAAANQAECgYICwAAAA==.Osla:BAAANQAECgYIBgAAAA==.',
Ox='Oxytoecin:BAAANQAECgYIBgAAAA==.',
Pa='Paapineau:BAAANQAECgUIDgAAAA==.Packes:BAABNQAECn8wAAIiAAkKQBmuEgBMAQAiAAkKQBmuEgBMAQAAAA==.Pakkohruun:BAABNQAECn8fAAIJAAoK+xbXbgBSAgAJAAoK+xbXbgBSAgAAAA==.Pallywack:BAABNQAECn8oAAIJAAgKOwwu0QB5AQAJAAgKOwwu0QB5AQAAAA==.Palussy:BAAANQADCgQIBAAAAA==.Parthima:BAABNQAECn8uAAMgAAgKTwm1GQAUAQAgAAgKTwm1GQAUAQADAAEKdwkyRgAoAAAAAA==.Partysnaxx:BAAANQABCgEIAQAAAA==.',
Pe='Peppercat:BAAANQAECgQICAAAAA==.Pertophos:BAAANQAECgUICQAAAA==.Pettigrew:BAAANQADCgIJAgAAAA==.',
Ph='Phantomclone:BAAANQAECgIIBQAAAA==.Phantomghoul:BAAANQAECgMIAwAAAA==.Philomena:BAAANQAECgEIAQAAAA==.',
Pi='Piggÿ:BAAANQAECgUICwAAAA==.Piko:BAAANQADCggIDgAAAA==.Piyo:BAAANQADCgcIBwABNQAECgkJMAAiAEAZAA==.',
Pl='Plankormast:BAAANQADCgEIAQAAAA==.',
Po='Poky:BAAANQAECgEIAgABNQAECgYICgAUAAAAAA==.Popena:BAAANQAECgMIBAAAAA==.Porkbuns:BAABNQAECn8eAAITAAoKlRJfPABEAQATAAoKlRJfPABEAQAAAA==.Potatogg:BAAANQAECgIIAwAAAA==.',
Pr='Praedor:BAAANQAECgEJAQAAAA==.Precious:BAAANQADCgEIAgAAAA==.Priestymon:BAABNQAECn8dAAIGAAoKlCBeCwBnAwAGAAoKlCBeCwBnAwABNQAFFAYIDQABAFUcAA==.Protdaddyy:BAAANQAECgEIAgAAAA==.',
Pw='Pwarr:BAACNQAFFH8JAAIlAAQKxwtEBADpAAAlAAQKxwtEBADpAAA1AAQKfyAAAyUACgq8HwYBAIICACUACgq8HwYBAIICAAEABwpnCxnSAE0BAAE1AAUUBQgIABcA8AoA.',
Qa='Qamar:BAAANQADCgQIBAAAAA==.',
Qu='Quackadeen:BAAANQAECgIJAgAAAA==.Quaesitor:BAAANQAECgEIAwAAAA==.',
Qw='Qwarr:BAAANQAECgUICgABNQAFFAUICAAXAPAKAA==.',
Ra='Raathya:BAAANQAECgcIDwAAAA==.Raeljin:BAABNQAECn8ZAAIQAAgKLxlaQQBwAgAQAAgKLxlaQQBwAgAAAA==.Raihua:BAAANQADCgYIBgAAAA==.Rangoz:BAAANQAECgUIDAAAAA==.Rar:BAABNQAECn8XAAIKAAoK+RvSDgD6AQAKAAoK+RvSDgD6AQAAAA==.Ratgamerlol:BAABNQAECn8mAAIKAAgKFiJIKgDwAgAKAAgKFiJIKgDwAgAAAA==.Ravnur:BAAANQADCggICAAAAA==.Rayennagrom:BAAANQAECgIIBAAAAA==.Rayo:BAAANQAECgEIAQAAAA==.',
Re='Reagent:BAAANQADCgMIAwAAAA==.Reckrunner:BAABNQAECn8cAAQPAAoK0A4/TgDpAAAPAAgKcg8/TgDpAAAbAAEKAABLLgA5AAAaAAEKZwoAegA0AAAAAA==.Redlocks:BAAANQAECgYICgAAAA==.Renault:BAAANQADCgMIAwAAAA==.Reneana:BAAANQAECgUIDQAAAA==.Restbo:BAABNQAECn8UAAIYAAkK/iJ0CwBlAwAYAAkK/iJ0CwBlAwABNQAFFAUIFAAVADwRAA==.',
Rh='Rhianonn:BAAANQAECgYIEAABNQAECgMIAwAUAAAAAA==.',
Ri='Riaslock:BAAANQAECgEJAQAAAA==.Richardluis:BAAANQAECgcIEAAAAA==.Rinehardtt:BAABNQAECn8sAAIIAAoKWx0OIwDgAgAIAAoKWx0OIwDgAgAAAA==.Riverstyxx:BAAANQADCgYIEQAAAA==.Rivër:BAAANQADCggIHwAAAA==.',
Ro='Robbell:BAABNQAECn8mAAIKAAoK2hk8CQAzAgAKAAoK2hk8CQAzAgAAAA==.Rococote:BAAANQAECgEIAQAAAA==.Roggehere:BAAANQAECgIIAgAAAA==.Rokyman:BAAANQAECgYIDgAAAA==.Roldazark:BAAANQAECgEIAQAAAA==.Roonsia:BAAANQADCgQIBQAAAA==.Rootsie:BAAANQADCgYJFwAAAA==.Roselynn:BAABNQAECn8ZAAIDAAgKbRasHwAuAgADAAgKbRasHwAuAgAAAA==.Rouby:BAAANQAECgEIBQAAAA==.Roughlight:BAAANQADCgMIAwAAAA==.',
Ru='Ruerl:BAABNQAECn8YAAIJAAgKTAqxzACCAQAJAAgKTAqxzACCAQAAAA==.Runentug:BAACNQAFFH8JAAIiAAQKFiHtDQB1AQAiAAQKFiHtDQB1AQA1AAQKfxsAAiIACQqSJAkNAEkDACIACQqSJAkNAEkDAAAA.Rustyspell:BAAANQADCgIIAgAAAA==.',
Ry='Ryumapriest:BAAANQAECgEIAQAAAA==.',
['Rî']='Rîft:BAAANQADCgEIAQAAAA==.',
Sa='Sanddora:BAAANQADCgIIAgAAAA==.Sanlordriel:BAAANQAECgMIAwAAAA==.Saramon:BAAANQADCggIKQAAAA==.Sassiberry:BAAANQADCgcIEQAAAA==.Sassitude:BAAANQADCgcIFQAAAA==.Satiiva:BAAANQADCggICAAAAA==.',
Sc='Scarlos:BAAANQABCgMIAwAAAA==.Screamdying:BAAANQABCgIIAgAAAA==.Scrembiblion:BAABNQAECn8hAAImAAgKix48AAAXAgAmAAgKix48AAAXAgAAAA==.',
Sd='Sdhoscillate:BAAANQADCgYIBgAAAA==.',
Se='Seins:BAAANQADCgYIBgAAAA==.Semillin:BAAANQAECgcICgAAAA==.Sensjei:BAAANQAECgQIDQAAAA==.Separatist:BAAANQADCgMJAwAAAA==.Serendibitty:BAAANQADCgMJAwAAAA==.',
Sg='Sgtbreezy:BAAANQADCgcIBwAAAA==.',
Sh='Shadey:BAAANQADCgIIAgAAAA==.Shambulance:BAAANQAECgcIDgAAAA==.Sharuerl:BAAANQADCgcIBwAAAA==.Shazi:BAEANQAECggICAAAAA==.Shiftroid:BAAANQADCgMIBgAAAA==.Shinyivie:BAABNQAECn8eAAIJAAkKYwX85ABRAQAJAAkKYwX85ABRAQAAAA==.Shiverchill:BAAANQABCgEJAQAAAA==.Shockrock:BAAANQAECgEIAQAAAA==.Shouzhe:BAAANQADCgUIBQAAAA==.Shroomjuice:BAAANQAECggIDwAAAA==.Shuthehealup:BAAANQAECgEIAgAAAA==.Shãdøwzzxz:BAAANQAECgUIDgAAAA==.',
Si='Sildenafil:BAAANQADCgIIAgAAAA==.Silessra:BAAANQADCggICAAAAA==.',
Sk='Skogr:BAAANQADCgIIAQABNQADCgUIBQAUAAAAAA==.Skädoosh:BAAANQAECgEIAQAAAA==.',
Sl='Slapshappy:BAAANQAECggIDAAAAA==.',
Sm='Smallhorn:BAAANQAECgEIAgAAAA==.Smokeyhaze:BAAANQAECgYIEAAAAA==.Smokin:BAABNQAECn8bAAIKAAcKogpVsgCfAQAKAAcKogpVsgCfAQAAAA==.Smolther:BAAANQADCgcIBwAAAA==.Smores:BAAANQADCgcJDQAAAA==.',
Sn='Sneech:BAAANQAECgEIAQAAAA==.Snowbvnni:BAAANQADCgQIBAAAAA==.',
So='Sofarkinghi:BAAANQAECgEIAQAAAA==.Sollamor:BAAANQAECgMIBAAAAA==.Solomonk:BAABNQAECn8gAAIjAAcKHg5vCgCyAAAjAAcKHg5vCgCyAAAAAA==.Solomus:BAABNQAECn8bAAMNAAYKkw6lMAAYAQANAAYKkw6lMAAYAQAgAAQKWwGjTgA6AAAAAA==.Sonal:BAABNQAECn8XAAQhAAcKtgocXQAzAQAhAAcKtQkcXQAzAQAiAAUK6QezjgDIAAALAAEKAAC9+AAfAAAAAA==.Soneca:BAAANQAECgEIAQAAAA==.Soter:BAAANQAECgcIBwAAAA==.',
Sq='Squeaph:BAAANQAECgUICAAAAA==.',
St='Stararia:BAAANQADCggICAAAAA==.Stelltrain:BAAANQAECgEIAQAAAA==.Stormiee:BAABNQAECn8lAAIYAAkKqxhSOAB+AgAYAAkKqxhSOAB+AgABNQAECgMIAwAUAAAAAA==.Stormroid:BAAANQAECgUICQAAAA==.Strangulate:BAAANQADCgQIAgAAAA==.Sttorm:BAAANQADCgUIBQAAAA==.Styles:BAABNQAECn8ZAAIJAAYK5wzpdgDaAAAJAAYK5wzpdgDaAAAAAA==.',
Su='Sugarontop:BAAANQADCgQIBAAAAA==.Sunmx:BAABNQAECn8rAAMBAAoKwRxzKQAVAwABAAoKtxxzKQAVAwACAAUKMh8LBAB8AQAAAA==.Superdark:BAAANQADCgIIAgAAAA==.',
Sw='Swurve:BAEANQAECgQIBwAAAA==.Swurves:BAAANQAECgIIAwABNQAECgYICAAUAAAAAA==.',
Sz='Szucs:BAAANQAECgEIAQAAAA==.',
['Sã']='Sãvãge:BAAANQADCgQIBAAAAA==.',
Ta='Tabiji:BAEANQAECggICAAAAA==.Tadpole:BAAANQADCggIDAAAAA==.Taedrum:BAAANQAECggIEAAAAA==.Taerror:BAAANQADCgIIAgAAAA==.Talegos:BAAANQAECgMJAwAAAA==.Talonfel:BAAANQADCgQIBAABNQAECgkJOQARACUjAA==.Taloning:BAAANQADCgYIBgABNQAECgkJOQARACUjAA==.Talonstryke:BAABNQAECn85AAIRAAkKJSO0AQCOAgARAAkKJSO0AQCOAgAAAA==.Tazrak:BAAANQAECgIIAgABNQAECgkJHwAPACMKAA==.',
Te='Teatoh:BAAANQADCgcIBwAAAA==.Tenseiga:BAAANQAECggIEQABNQAFFAQICQAHABwYAA==.Tevers:BAAANQAECgEIAgAAAA==.',
Th='Thaalion:BAAANQAECgEIAQAAAA==.Thalantier:BAAANQADCgMIBgAAAA==.Thardal:BAABNQAECn8kAAMbAAoKpQ9jAQCvAQAPAAkKiQyRfADvAQAbAAkKEhBjAQCvAQAAAA==.Thebigshot:BAAANQAECgMIBQAAAA==.Theenforcer:BAABNQAECn9FAAIJAAoKThD+hwAXAgAJAAoKThD+hwAXAgAAAA==.Thegreekbeas:BAAANQADCgUIBQAAAA==.Theguyfurry:BAAANQAECgEIAgAAAA==.Theonepanda:BAAANQAECgMIAwAAAA==.Thetzin:BAABNQAECn8eAAITAAYKJwM1pgCBAAATAAYKJwM1pgCBAAAAAA==.Theunite:BAAANQADCggICAAAAA==.Thickhobo:BAAANQADCgUICQAAAA==.Thidwick:BAABNQAECn8kAAINAAcKhiGWAgAnAgANAAcKhiGWAgAnAgAAAA==.Thingtwø:BAAANQAECgYICQAAAA==.Thistle:BAAANQADCgYIDAABNQAECgkJIAATADQMAA==.Thraggs:BAAANQADCgcICAAAAA==.Thunderfist:BAAANQADCggIBwAAAA==.',
Ti='Titanslay:BAAANQADCgEIAQAAAA==.Titø:BAAANQADCgYIDQABNQADCgcIBwAUAAAAAA==.',
Tm='Tmryuki:BAAANQAECggICwAAAA==.',
To='Tokadin:BAAANQAECgIIBAAAAA==.Tomorrow:BAAANQAECgYICgAAAA==.Topzee:BAAANQADCggIDQAAAA==.Totalljoe:BAAANQAECgQIBAABNQAECggIJQALAIcJAA==.Totoo:BAABNQAFFH8HAAIWAAcKDgB6FwAhAAAWAAcKDgB6FwAhAAAAAA==.Touchmablade:BAAANQAECgMIAwAAAA==.',
Tr='Traedarra:BAAANQADCgIIAgAAAA==.Tralis:BAEANQADCggIDgABNQAECggICAAUAAAAAA==.Tranarra:BAABNQAECn9CAAIPAAkK/hnyBgA8AgAPAAkK/hnyBgA8AgAAAA==.Traylo:BAABNQAECn8nAAIKAAkKmRJsFgDDAQAKAAkKmRJsFgDDAQAAAA==.',
Tv='Tvak:BAABNQAECn8WAAIJAAcKcxfjtAC1AQAJAAcKcxfjtAC1AQAAAA==.',
Tw='Twistedsham:BAAANQAECggIBgAAAA==.Twopump:BAABNQAECn8wAAIJAAgKKAnJWAATAQAJAAgKKAnJWAATAQAAAA==.',
['Tó']='Tónka:BAAANQADCgcJBwABNQAECgEIAQAUAAAAAA==.',
Ul='Ulhae:BAAANQABCgQIBAAAAA==.Ulinova:BAAANQAECgUICwAAAA==.',
Um='Umbressa:BAAANQADCgMIAwABNQAECgoKMQAKAAMaAA==.Umbryx:BAAANQADCgIIAgABNQAECgkJHwAPACMKAA==.',
Un='Unholly:BAAANQAECgIJBAAAAA==.',
Ur='Uroro:BAABNQAECn8oAAMYAAoK3iFNGAASAwAYAAoK3iFNGAASAwAQAAEKAADjQgEsAAABNQAFFAUIEgACAKoeAA==.',
Uu='Uu:BAAANQABCgIIAgAAAA==.',
Va='Vaiden:BAAANQABCgEIAQAAAA==.Vainqueur:BAABNQAECn8cAAIdAAkKZxm9AQDgAQAdAAkKZxm9AQDgAQAAAA==.Valienni:BAAANQAECgEIAQAAAA==.Vanderdemon:BAAANQADCgMIAwAAAA==.Vanderlight:BAAANQADCgUJCQAAAA==.Vandernum:BAAANQAECggIAwAAAA==.Vandersus:BAAANQADCggIBQAAAA==.Varm:BAAANQADCggICAAAAA==.',
Ve='Velakai:BAAANQABCgQIBAAAAA==.Vervaeda:BAAANQADCgQIBAAAAA==.Verymelon:BAAANQAECgQIBgABNQAFFAMIBgAQAFYOAA==.Vestele:BAAANQADCggIDwAAAA==.',
Vg='Vgx:BAABNQAECn8dAAIhAAgK3A2IUQBrAQAhAAgK3A2IUQBrAQAAAA==.',
Vi='Vielitre:BAAANQAECgIIAgAAAA==.Vigossfel:BAAANQADCgMIBwAAAA==.Viintage:BAABNQAECn8rAAITAAkKJRPtEgDPAQATAAkKJRPtEgDPAQAAAA==.Viridius:BAAANQAECgEIAQAAAA==.Vishouspayne:BAAANQAECgUIEgAAAA==.',
Vo='Voidshank:BAAANQAECgEIAgAAAA==.',
Vy='Vyolence:BAAANQAECgEIAgABNQAECgkJJAASAOscAA==.',
['Vä']='Väelün:BAABNQAECn8cAAMkAAgK2BA4OACCAQAkAAgK2BA4OACCAQAMAAEKawTsmwAnAAAAAA==.',
['Vÿ']='Vÿ:BAAANQAECgYIDAAAAA==.',
Wa='Wachoosh:BAAANQAECgEIBAAAAA==.Waidmanns:BAABNQAECn8xAAMKAAoKAxrAJwD5AgAKAAoKAxrAJwD5AgAnAAMKuwmkBwCJAAAAAA==.Walmartstaff:BAAANQADCgUIBQAAAA==.Warfable:BAAANQADCgIIAgAAAA==.',
Wg='Wgnmd:BAAANQAECgQIBQAAAA==.',
Wh='Wham:BAAANQAECgIIAgAAAA==.Whatsaggro:BAABNQAECn8lAAILAAgKhwk9aABwAQALAAgKhwk9aABwAQAAAA==.Whatshadow:BAAANQAECgQIBAAAAA==.Whatyamean:BAAANQAECgUIEAAAAA==.Whiteeyedemo:BAAANQADCgYIBgAAAA==.Whoami:BAAANQAECggIBQAAAA==.Whoangry:BAABNQAECn8YAAMoAAkKZBG6RQCwAQAoAAkKgQ+6RQCwAQAWAAIK8BGlMgCOAAAAAA==.Whomonk:BAAANQAECgIIBAAAAA==.',
Wi='Wickedchick:BAAANQADCggIGQAAAA==.Willowknight:BAAANQADCgYICgAAAA==.Wimdy:BAAANQAECgEIAQAAAA==.Winterknight:BAAANQADCgQIBgAAAA==.',
Wr='Wrenn:BAAANQAECgIIBQAAAA==.Wrongname:BAAANQAECgUICAAAAA==.',
Wu='Wumba:BAAANQAECgMIAwAAAA==.',
Xa='Xanthe:BAAANQADCggIBwAAAA==.',
Xf='Xfloki:BAAANQADCgQIBAAAAA==.',
Xi='Xiunlin:BAAANQAECgEIAQAAAA==.',
['Xß']='Xß:BAAANQADCgIJBAAAAA==.',
Ya='Yakpriest:BAAANQADCgcIDAAAAA==.Yawg:BAEANQADCgYIBgABNQAECgoKLQAKAP8dAA==.',
Yd='Ydgktt:BAAANQADCgEIAQAAAA==.',
Yn='Ynhük:BAAANQADCgMIAwAAAA==.',
Yo='Yogsothoth:BAEBNQAECn8tAAIKAAoK/x0LKQD0AgAKAAoK/x0LKQD0AgAAAA==.',
Yr='Yrdenal:BAAANQAECgEIAQAAAA==.',
Yu='Yugalipdeez:BAAANQAECgEIAwAAAA==.Yulian:BAAANQAECgUIDwAAAA==.',
Za='Zaartyn:BAABNQAECn8sAAIPAAoK4B+jEwA+AwAPAAoK4B+jEwA+AwAAAA==.Zaater:BAAANQAECgIIBQAAAA==.Zalin:BAAANQAECgEIAQABNQAECgoKJAAbAKUPAA==.Zanki:BAAANQAECgUIDAAAAA==.',
Ze='Zeebeth:BAABNQAECn8XAAIKAAgKkQ4wjQDwAQAKAAgKkQ4wjQDwAQAAAA==.Zefi:BAAANQAECgcIAgAAAA==.Zellek:BAAANQADCgYIBgAAAA==.Zenbu:BAAANQADCgIIAgAAAA==.Zeroasy:BAAANQADCgIIAgABNQAECgcIIgAiAEYkAA==.Zerokai:BAAANQAECgUIBgAAAA==.Zeztz:BAAANQAECgcIDAAAAA==.',
Zo='Zomlo:BAAANQAECgQIBQAAAA==.Zooli:BAAANQADCggICAAAAA==.Zorosenpai:BAAANQADCgcIEQABNQAECggIIgAhAJ8KAA==.',
Zu='Zuggernaught:BAAANQAECgUIBwAAAA==.',
['Át']='Átomic:BAAANQADCgUIAwAAAA==.',
['Ân']='Ânimosity:BAAANQADCgIIAgAAAA==.',
['Âr']='Ârtemis:BAAANQAECgQIBAABNQAFFAQICQAHABwYAA==.',
['År']='Åres:BAAANQAECgEIAQAAAA==.',
['Ís']='Ísvala:BAAANQADCgYIBgAAAA==.',
['ßu']='ßuzzibee:BAAANQAECgYICgAAAA==.',
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
