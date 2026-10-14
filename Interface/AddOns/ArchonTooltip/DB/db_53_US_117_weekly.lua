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

local lookup = {'Warrior-Arms','Warrior-Fury','Druid-Restoration','Paladin-Protection','Monk-Windwalker','Priest-Holy','DemonHunter-Vengeance','Paladin-Holy','Paladin-Retribution','Hunter-BeastMastery','DeathKnight-Unholy','DemonHunter-Havoc','Unknown-Unknown','Shaman-Elemental','Monk-Mistweaver','Mage-Arcane','Priest-Discipline','Rogue-Subtlety','Warrior-Protection','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Mage-Frost','Druid-Balance','Priest-Shadow','Shaman-Restoration','DeathKnight-Blood','Monk-Brewmaster','DemonHunter-Devourer','Shaman-Enhancement','DeathKnight-Frost','Mage-Fire','Druid-Guardian','Hunter-Survival','Rogue-Assassination',}
local provider = {region='US',realm='Hakkar',name='US',type='weekly',zone=53,date='2026-10-13',data={Ac='Aceshaman:BAAANQADCgIIAgAAAA==.Acheros:BAAANQADCgMIAwAAAA==.Actionfigure:BAACNQAFFH8JAAIBAAQKyCD8FAB8AQABAAQKyCD8FAB8AQA1AAQKfyIAAwEACQocIlA2AOYCAAEACQocIlA2AOYCAAIAAQoAACcvAEEAAAAA.',
Ad='Adielia:BAABNQAECn8bAAIDAAgK0hh9HQBBAgADAAgK0hh9HQBBAgAAAA==.Adurzin:BAAANQADCgIIAgAAAA==.',
Ae='Aeralina:BAAANQADCgUJBQAAAA==.Aeri:BAAANQADCgIIAwAAAA==.Aevalaana:BAAANQAECgYICQAAAA==.',
Ag='Agiermodinn:BAAANQADCgYICgAAAA==.',
Ah='Ahnho:BAAANQADCggICgAAAA==.',
Ai='Aidandrius:BAAANQADCgMIAwAAAA==.Aimeeleigh:BAAANQADCggIJQABNQAECgcIFwAEAHgbAA==.Airflash:BAACNQAFFH8JAAIFAAQKEx7xCABFAQAFAAQKEx7xCABFAQA1AAQKfzcAAgUACAo/JX8HAFQDAAUACAo/JX8HAFQDAAAA.Aiøn:BAAANQADCgcIBwAAAA==.',
Ak='Akutagawa:BAABNQAECn8VAAIGAAkK/hJLSgBDAgAGAAkK/hJLSgBDAgABNQAFFAQICAAHABwYAA==.',
Al='Alexious:BAACNQAFFH8LAAIEAAUKhx/6AwCgAQAEAAUKhx/6AwCgAQA1AAQKfysAAgQACQqPIjEHAC8DAAQACQqPIjEHAC8DAAAA.Aloonarn:BAAANQAECgQICAAAAA==.Alopix:BAAANQAECgYIDAAAAA==.Alulla:BAACNQAFFH8RAAMCAAUKqh7oAQD0AAABAAQKqh7JFgBnAQACAAMKwRjoAQD0AAA1AAQKfx0AAwIACQrNIZMKABwCAAEACAq6IAhIAK4CAAIABwoTIpMKABwCAAAA.Alunira:BAABNQAECn8pAAMIAAkKoh2eGAAVAwAIAAkKoh2eGAAVAwAJAAYKbhbjyQCCAQAAAA==.',
Am='Amberrfrost:BAAANQAECgQICAAAAA==.Amize:BAAANQADCgYIBgAAAA==.Ampz:BAAANQAECgIIAgAAAA==.',
An='Anabee:BAAANQADCggIDgAAAA==.Angelicshy:BAAANQADCgQIBAAAAA==.Angryhtr:BAABNQAECn8UAAIKAAcKGhl7dAAkAgAKAAcKGhl7dAAkAgAAAA==.Angrysh:BAAANQADCgQIBAAAAA==.Angrywar:BAABNQAECn8bAAIBAAgKHxIemwDUAQABAAgKHxIemwDUAQAAAA==.Anharon:BAAANQADCgYICQAAAA==.Ansatz:BAAANQAECgEIAwABNQAECgkJKgAKAJkaAA==.',
Ap='Apokalypto:BAAANQAECgQIBAAAAA==.',
Ar='Arbiterbinky:BAAANQADCgUIBQAAAA==.Ardå:BAAANQADCgEIAQAAAA==.Argangus:BAAANQADCgYIDwAAAA==.Arthan:BAAANQAECgMIAwAAAA==.Arthannix:BAAANQADCgYICgAAAA==.',
As='Astanis:BAAANQAECgUICAAAAA==.Asteriia:BAAANQAECgcIEAAAAA==.Astralyn:BAAANQAECgEIAQAAAA==.',
Av='Averettara:BAAANQAECgIIBgABNQAECggIIwALAIcJAA==.',
Az='Azarazan:BAAANQADCgYIDgAAAA==.Azka:BAABNQAECn8hAAIJAAkKWh8HLwAKAwAJAAkKWh8HLwAKAwAAAA==.Azkadk:BAAANQADCgYIBgAAAA==.',
Ba='Babybilly:BAABNQAECn8XAAMEAAcKeBtgHQD8AQAEAAcKeBtgHQD8AQAJAAMKkAM6awFtAAAAAA==.Baelmon:BAAANQADCgcIGQAAAA==.Baludis:BAAANQADCgcIEQAAAA==.Bamff:BAAANQAECgUICQAAAA==.Bamfpally:BAAANQADCggICAAAAA==.Barreack:BAAANQADCgYICAAAAA==.Bast:BAACNQAFFH8IAAIHAAQKHBgtAgAtAQAHAAQKHBgtAgAtAQA1AAQKfyoAAwcACQqtIE8DADIDAAcACQqtIE8DADIDAAwABQpFE3RRAEoBAAAA.Basthara:BAAANQAECggIEgABNQAFFAQICAAHABwYAA==.',
Be='Beckianslip:BAAANQADCgUIBQAAAA==.Belphegor:BAAANQAECgEIAQABNQAECgUIEgANAAAAAA==.Benif:BAACNQAFFH8MAAIBAAUKLh0+DwC8AQABAAUKLh0+DwC8AQA1AAQKfyUAAgEACQqcJbsIAK0DAAEACQqcJbsIAK0DAAAA.Benjaquel:BAAANQADCgQIBAAAAA==.Bertorod:BAABNQAECn8XAAIOAAgK+BboVgAcAgAOAAgK+BboVgAcAgAAAA==.Bewblover:BAAANQADCggIFwAAAA==.',
Bi='Bigbitehotdo:BAABNQAECn8sAAMFAAkK5R5aDgD4AgAFAAkK5R5aDgD4AgAPAAEK3wGrUwAgAAAAAA==.Bighoney:BAAANQAECgEIAQAAAA==.Bigtommybuns:BAAANQADCgUIBQAAAA==.Binkyfiasco:BAAANQADCggIDgAAAA==.Binny:BAAANQADCgYIBgAAAA==.Birdiewordie:BAAANQADCgQIBAAAAA==.',
Bl='Bloodeie:BAAANQADCgQIBAAAAA==.Bloodstoned:BAAANQAECgUICwAAAA==.Blueboy:BAAANQAECgcIEwAAAA==.',
Bo='Boffadz:BAAANQAECggICAAAAA==.Bonewand:BAAANQAECgEIAQAAAA==.Bonewrath:BAAANQABCgIIAgAAAA==.Boogat:BAAANQAECgMIAwAAAA==.',
Br='Braugorlle:BAAANQAECgYIBgABNQAFFAUICwAOALoQAA==.Breadscrumb:BAAANQADCgUJBQAAAA==.Briandejay:BAAANQABCgIIBAAAAA==.Bridrystina:BAAANQADCgQIBAAAAA==.Brixlo:BAAANQADCgEIAQABNQADCgcJBwANAAAAAA==.',
Bu='Buffmuffin:BAAANQAECgIIAgAAAA==.Burblbiblr:BAAANQADCgQJBAAAAA==.Bustrdugles:BAAANQADCgUIBQAAAA==.',
Bw='Bwazakki:BAAANQADCgMIAwAAAA==.Bwr:BAAANQADCgMIAwAAAA==.',
['Bü']='Bübbawrap:BAAANQAECgIIAwAAAA==.',
Ca='Cambrier:BAABNQAECn8yAAMCAAkK5yD1BADcAgABAAkKuh4AKAAYAwACAAgKoiD1BADcAgAAAA==.Cameraop:BAABNQAECn8XAAIQAAcKKwhVEAFuAQAQAAcKKwhVEAFuAQAAAA==.Capnsoap:BAAANQADCgYIBgABNQABCgEIAQANAAAAAA==.Capriestsun:BAAANQAECgYICAAAAA==.Cardinal:BAAANQAECgEIAQAAAA==.Carynden:BAAANQADCgUIBQAAAA==.Castbo:BAAANQAECgcIEAABNQAFFAUIFAARADwRAA==.',
Ce='Celilinia:BAAANQAECgIIAgAAAA==.Cellesstia:BAAANQADCgMIBQABNQAECgMIAwANAAAAAA==.',
Ch='Chalada:BAAANQADCgEIAQABNQAFFAcIBwASAA4AAA==.Chalastorm:BAAANQAECggIAQABNQAFFAcIBwASAA4AAA==.Charknight:BAAANQADCgUIBQAAAA==.Chatdodu:BAAANQADCgUIBQAAAA==.Chatnoir:BAAANQAECgYICQAAAA==.Chestock:BAAANQADCgYIBgAAAA==.Chuggz:BAAANQAECgQIBgAAAA==.',
Cl='Clonetastic:BAAANQADCggICAAAAA==.Clumsycarl:BAAANQADCgIIAgAAAA==.',
Cm='Cmx:BAAANQADCgUIBQAAAA==.',
Co='Codith:BAAANQAECgEIAQAAAA==.Coldlock:BAAANQADCgQIBAAAAA==.Colesiaw:BAAANQADCgQIBgAAAA==.Coraeze:BAAANQADCgEJAQAAAA==.',
Cr='Creek:BAAANQABCgYIBgABNQAECggIIQAMAHshAA==.Crnogorac:BAAANQAECggIAQAAAA==.Crotchgoblim:BAAANQADCgcIEQAAAA==.Cryodormu:BAAANQAECgMJAwAAAA==.',
Cu='Cubo:BAAANQAECgEIAQAAAA==.Cuddlesworth:BAAANQAECgUIEgAAAA==.',
Cw='Cwarr:BAAANQAECgIIAgABNQAFFAQICQATAMcLAA==.',
Cy='Cyrcee:BAAANQADCgUIBQABNQAECgMIAwANAAAAAA==.',
Da='Daddyluis:BAAANQADCggICgAAAA==.Dadstonks:BAAANQABCgYJCAAAAA==.Dagoujiao:BAAANQAFFAEIAQAAAA==.Dameiyo:BAAANQAECggIDgAAAA==.Dandanh:BAAANQADCgMIAwAAAA==.Dangright:BAABNQAECn8aAAIUAAgKXwWKPQBgAQAUAAgKXwWKPQBgAQAAAA==.Dankbo:BAACNQAFFH8UAAMRAAUKPBEYAgDVAAAGAAQKHhWIFwAyAQARAAMK1ggYAgDVAAA1AAQKfzoAAxEACQooI60CAOMCABEACAq6IK0CAOMCAAYACQqOHlQlANMCAAAA.Danorac:BAAANQAECgQIBAAAAA==.Darkcoffee:BAAANQAFFAEIAQAAAA==.Darkivie:BAAANQADCgYIBgABNQAECgkJHgAJAGMFAA==.',
De='Deadashe:BAAANQADCgEIAQAAAA==.Demonicsword:BAAANQADCgQIBAAAAA==.Despondent:BAAANQADCgcIFQAAAA==.Devilcrybaby:BAAANQAECgIIAgAAAA==.Devildj:BAAANQAECgYIDQAAAA==.Dezadian:BAAANQAECgUIEAAAAA==.',
Dh='Dhampyra:BAAANQAECgcIEgAAAA==.',
Di='Didicoralie:BAAANQADCgEJAQAAAA==.Dietmountdew:BAAANQADCgEJAQAAAA==.Dimitrios:BAAANQAECgUIBwAAAA==.Disolve:BAABNQAECn8gAAQVAAkKFBG1dgD6AQAVAAkKog21dgD6AQAWAAIK9ha/UQCIAAAXAAEKAADnJABZAAAAAA==.Dixxonciderr:BAABNQAECn88AAQYAAkKCh5nCQALAwAYAAkKCh5nCQALAwAZAAYKiw+HIABNAQAaAAIKWRWeHQByAAAAAA==.',
Dm='Dmoe:BAAANQAECgQICQAAAA==.',
Do='Doji:BAAANQADCgEIAQAAAA==.',
Dq='Dqe:BAAANQAECgEIAQAAAA==.',
Dr='Drac:BAAANQADCgMIAwAAAA==.Dribby:BAAANQAECgIIAgAAAA==.',
Du='Duhästmich:BAAANQADCgYIBgABNQAECggIIwALAIcJAA==.Duplicate:BAACNQAFFH8MAAMbAAQK3hHbCACOAAAQAAMKWRlwNADuAAAbAAIKGA/bCACOAAA1AAQKfyIAAxAACQphGE6aAEsCABAACQphGE6aAEsCABsAAQonG7NAAEEAAAAA.Dustdruid:BAACNQAFFH8FAAIcAAMKdxApGgDNAAAcAAMKdxApGgDNAAA1AAQKfycAAhwACAq1IBceANcCABwACAq1IBceANcCAAAA.Dustlock:BAAANQAECgcIDQAAAA==.Dustmage:BAAANQADCggIEAAAAA==.',
Dw='Dwarr:BAAANQAECgYICAAAAA==.',
['Dó']='Dóru:BAAANQADCgYIBwAAAA==.',
Ee='Eender:BAAANQAECgEIAQAAAA==.',
Eg='Eggrolls:BAABNQAECn82AAIBAAkKjh5VIgAtAwABAAkKjh5VIgAtAwAAAA==.',
El='Eldenmorden:BAAANQADCgYIBgAAAA==.Eleshmelly:BAAANQADCgcIFgAAAA==.Ellayna:BAAANQADCgEIAQAAAA==.Ellcrys:BAABNQAECn8pAAIDAAgKyhamIAAgAgADAAgKyhamIAAgAgAAAA==.Elletta:BAAANQAECgEIAQAAAA==.Elrae:BAAANQAECgUIBQAAAA==.',
Ep='Epoptes:BAAANQAECgEIAQABNQAECgYIFgAEAH8NAA==.',
Eq='Eqo:BAABNQAECn8dAAMGAAkKERLmdwCvAQAGAAkKERLmdwCvAQAdAAEKxQnycgA9AAAAAA==.',
Er='Erisian:BAAANQAECgQIBAAAAA==.Erkêios:BAAANQAECggIDwAAAA==.Ersande:BAAANQAECgMIAwAAAA==.Ertz:BAAANQADCggICQAAAA==.',
Es='Escherichia:BAAANQAECgEJAQAAAA==.Estheban:BAABNQAECn8aAAQZAAcKxBzVDgBtAgAZAAcKxBzVDgBtAgAaAAEKXw5zIwA2AAAYAAEKQAtwTwAtAAAAAA==.',
Ev='Evengelist:BAAANQAECgQIBwABNQAECgYICQANAAAAAA==.',
Fa='Face:BAAANQAECgEIAQAAAA==.Fairgrim:BAAANQAECgQIBAAAAA==.Falin:BAABNQAECn8+AAIJAAkKWBzGQQDMAgAJAAkKWBzGQQDMAgAAAA==.Faqueuedark:BAAANQAECggIEAABNQAECgkJOgAMAOMhAA==.Faqueueeight:BAABNQAECn86AAMMAAkK4yGwEQAOAwAMAAkK4yGwEQAOAwAHAAkKahZtCgAwAgAAAA==.Fatsloth:BAAANQAECgUICAAAAA==.Fatébringer:BAAANQADCgYIDAABNQAECgEIAQANAAAAAA==.Faulted:BAAANQADCgUIBQAAAA==.',
Fe='Feironos:BAAANQADCgEIAQAAAA==.Felcookies:BAAANQAECgYIDAAAAA==.Ferrick:BAAANQAECgIIAgAAAA==.',
Fi='Fimtastic:BAABNQAECn8dAAIeAAcKSBR/fACSAQAeAAcKSBR/fACSAQAAAA==.Finasy:BAABNQAECn8dAAIfAAcKRiTfGgDVAgAfAAcKRiTfGgDVAgAAAA==.Finnicka:BAAANQAECgEIAQAAAA==.Firen:BAAANQADCgYIDQAAAA==.Fistymisty:BAABNQAECn8cAAIgAAkKix9sBAAwAwAgAAkKix9sBAAwAwAAAA==.Fizeecian:BAAANQADCgUIBQAAAA==.',
Fl='Flaynpray:BAAANQADCgEIAQAAAA==.Fluffenstein:BAAANQAFFAEIAQAAAA==.',
Fo='Foxrawruwu:BAABNQAECn8WAAIVAAgKqRpbNQCyAgAVAAgKqRpbNQCyAgAAAA==.',
Fr='Frakk:BAAANQAECggIAQAAAA==.Freezegarr:BAAANQAECggIEwABNQAECgkJFwAfAPciAA==.Frostgrave:BAAANQADCgEIAQAAAA==.Frostya:BAAANQADCgEIAQAAAA==.',
Fu='Furearia:BAAANQABCgcICQAAAA==.Furrybowner:BAAANQAECggIBQAAAA==.',
Ga='Galeriel:BAACNQAFFH8LAAIGAAMK1iJWFwA0AQAGAAMK1iJWFwA0AQA1AAQKfy4AAgYACQoYJQcKAHEDAAYACQoYJQcKAHEDAAAA.Gallethline:BAAANQAECgIIAgAAAA==.Ganjgotti:BAAANQADCgYICQAAAA==.Garault:BAAANQAECgYICAAAAA==.Gavered:BAAANQADCgMJBQAAAA==.',
Ge='Gekoni:BAAANQADCgYIBgAAAA==.Geonon:BAAANQADCggICAAAAA==.Geotracker:BAABNQAECn8XAAIKAAcKdQ8inQDIAQAKAAcKdQ8inQDIAQABNQADCggICAANAAAAAA==.',
Gh='Ghorros:BAAANQADCgMIAwAAAA==.',
Gi='Gilgahmesh:BAAANQAECgcIDAABNQAECgkJKAAIANQbAA==.',
Gl='Glowpwr:BAAANQADCgcIBwAAAA==.',
Go='Goolgame:BAACNQAFFH8LAAMOAAUKuhAhDACmAQAOAAUKuhAhDACmAQAeAAMKXBVNFgDwAAA1AAQKfycAAw4ACQpMIO47AIMCAA4ABwqrIe47AIMCAB4ABQq9G/uFAHgBAAAA.Goonthergg:BAAANQADCgYIBgAAAA==.Goothix:BAAANQADCgcJCAAAAA==.Gothmog:BAAANQADCgIIAgAAAA==.',
Gr='Grammarg:BAAANQADCgMIAwAAAA==.Grirr:BAAANQAECgIIBAAAAA==.Grothin:BAABNQAECn8cAAIeAAgKChfkTwAiAgAeAAgKChfkTwAiAgAAAA==.Gruldag:BAABNQAECn8tAAIQAAkKVBu4WwDIAgAQAAkKVBu4WwDIAgAAAA==.Grullander:BAABNQAECn8pAAIeAAgKyhMLZwDUAQAeAAgKyhMLZwDUAQAAAA==.',
Gu='Guiguiie:BAAANQADCggJEAAAAA==.',
Gw='Gwyndolynn:BAAANQADCgQIBAAAAA==.',
Ha='Hailey:BAEANQAECggIEwABNQAFFAUICgAIAEYMAA==.Halter:BAAANQAECgIIAgAAAA==.Hapló:BAAANQABCgEIAQAAAA==.Haratvy:BAAANQAECgEIAQAAAA==.Hazzurd:BAABNQAECn8aAAIKAAgKZRMZcgAqAgAKAAgKZRMZcgAqAgAAAA==.',
He='Header:BAACNQAFFH8ZAAIUAAYKShx1BQACAgAUAAYKShx1BQACAgA1AAQKfx8AAxQACQqJG6ciADUCABQACQqJG6ciADUCAAoABQrhCtf5AAsBAAAA.Healsorz:BAAANQADCgcIBwAAAA==.Heersbeest:BAAANQABCggICwAAAA==.Helane:BAAANQADCgUIBQAAAA==.Herkharu:BAAANQADCgcIBwAAAA==.Hermionee:BAABNQAECn8lAAMQAAgKAxC7/wCLAQAQAAcKwAq7/wCLAQAbAAIKbxhcLgCHAAAAAA==.Hetu:BAAANQABCgUIBAAAAA==.',
Hi='Hide:BAAANQAECgEIAQAAAA==.Himjongun:BAABNQAECn8YAAMMAAcKhhlcRACcAQAMAAYKhhlcRACcAQAhAAEKAAD6cwAiAAAAAA==.',
Ho='Holya:BAAANQADCgEIAQABNQAFFAcIBwASAA4AAA==.Holykoi:BAABNQAECn8oAAIGAAgKZQ2edgCzAQAGAAgKZQ2edgCzAQAAAA==.',
Hr='Hroarr:BAABNQAECn8XAAIfAAkK9yJPDgA7AwAfAAkK9yJPDgA7AwAAAA==.',
Hu='Humancarnage:BAAANQADCgYIBwAAAA==.Huuh:BAAANQADCgQIBwAAAA==.',
Hy='Hypaexia:BAAANQADCgIIAgAAAA==.',
['Hà']='Hàvoc:BAAANQADCggIDQAAAA==.',
['Hé']='Héboric:BAABNQAECn8YAAIIAAgKghhMQgBZAgAIAAgKghhMQgBZAgAAAA==.Hélbrecht:BAAANQAECgMIAwAAAA==.',
['Hÿ']='Hÿbrìd:BAAANQAECgYIDwAAAA==.',
Ia='Iamwho:BAAANQAECggICAAAAA==.Iatros:BAABNQAECn8WAAMEAAYKfw0LPQAHAQAEAAYKfw0LPQAHAQAJAAEKqwNCxAEiAAAAAA==.',
Id='Idkno:BAAANQADCggIGQAAAA==.',
Ik='Ikara:BAAANQADCggICAABNQAECgkJHAAXAIIOAA==.Ikodiwa:BAAANQADCgUIBQAAAA==.',
Im='Imjustsaiyan:BAAANQADCgIIAgAAAA==.',
In='Indravax:BAAANQAECgYIDAAAAA==.',
Io='Iorin:BAAANQADCgcIBwABNQAECgkJIAAMADoOAA==.',
It='Itwasntmebru:BAAANQADCgYIDgAAAA==.',
Iv='Ivantis:BAAANQADCgYIFwAAAA==.Ivie:BAAANQAECgMIAwAAAA==.',
Iw='Iwonabhornee:BAAANQADCgIIAgAAAA==.',
Ja='Jaholypriest:BAACNQAFFH8GAAIGAAMKQxRXHQDxAAAGAAMKQxRXHQDxAAA1AAQKfxoAAgYACQqbEvJVAB4CAAYACQqbEvJVAB4CAAAA.Janjor:BAAANQAECgIIAgAAAA==.Janjy:BAAANQADCgcIBwAAAA==.Jaypiea:BAABNQAECn8iAAMaAAkKTBXyBwAgAgAaAAgKTBXyBwAgAgAZAAgK8xCOFwDOAQAAAA==.',
Je='Jergall:BAAANQADCgUIBQAAAA==.Jettian:BAAANQAECgQICQAAAA==.',
Ji='Jibz:BAAANQADCgEIAQAAAA==.',
Jj='Jjdruid:BAAANQAECgIIAgAAAA==.',
Jo='Jollygreene:BAAANQAECgEIAgAAAA==.Jonestu:BAAANQAECgEIAQAAAA==.',
Jp='Jpgigacat:BAAANQAECgUIBQAAAA==.Jpgigademon:BAAANQAECgMIBAAAAA==.',
Ju='Justakatt:BAAANQADCgIIAgAAAA==.Justicasia:BAAANQADCgQIBAABNQADCgYIBgANAAAAAA==.',
Ka='Kadinsky:BAAANQADCgUIBQAAAA==.Kalivan:BAAANQADCgYIBwAAAA==.Kankimasamu:BAAANQADCgIIAgAAAA==.Karametra:BAAANQAECgYIBgAAAA==.Karlldun:BAAANQAECgYIBgAAAA==.Kasmir:BAABNQAECn8hAAMVAAgKhw9zlQCsAQAVAAcK/xBzlQCsAQAWAAEKLghsfAAwAAAAAA==.Kasnfriends:BAAANQADCgUIBQABNQAECggIIQAVAIcPAA==.',
Ke='Kevv:BAACNQAFFH8JAAIOAAQKyALYFwD/AAAOAAQKyALYFwD/AAA1AAQKfyAAAw4ACQohFIxRAC8CAA4ACQohFIxRAC8CACIAAQoAAEY7ABkAAAAA.Keyniron:BAABNQAECn91AAIJAAgKzyRgGABhAwAJAAgKzyRgGABhAwAAAA==.',
Kh='Khogent:BAAANQADCgQIBAAAAA==.Khonsu:BAAANQAECgQIBAAAAA==.Khrover:BAAANQADCgUIBQAAAA==.Khyle:BAAANQADCgYIBwAAAA==.',
Ki='Kijanajr:BAAANQADCgMIAgAAAA==.Killaarrow:BAABNQAECn8oAAIKAAgKyAe3kQDiAQAKAAgKyAe3kQDiAQAAAA==.Kindleos:BAAANQADCgQJBAAAAA==.',
Kk='Kkpriest:BAAANQADCgEIAQAAAA==.',
Kl='Klay:BAAANQAECgYIDQAAAA==.',
Km='Kmarte:BAEANQAECgUIEAABNQAECgkJGAAJADcVAA==.Kmartt:BAEBNQAECn8YAAIJAAkKNxWKdABAAgAJAAkKNxWKdABAAgAAAA==.',
Ko='Kosmic:BAAANQADCgcICQABNQAECggIGQAfALwZAA==.Kosmicknight:BAABNQAECn8ZAAMfAAgKvBmPNgAtAgAfAAgKvBmPNgAtAgAjAAEKAACcswAoAAAAAA==.',
Kr='Kraggers:BAAANQAECgUIDQAAAA==.Kraggory:BAAANQAECgIIAgAAAA==.Kraggoryqt:BAAANQAECgMIBwAAAA==.Kraggoryx:BAAANQAECgEIAQAAAA==.Kruncle:BAAANQADCgYIBgAAAA==.Kryesta:BAABNQAECn8yAAIeAAkKkyAYGAARAwAeAAkKkyAYGAARAwAAAA==.',
Kw='Kwarr:BAACNQAFFH8HAAIiAAQKzwuYAwBAAQAiAAQKzwuYAwBAAQA1AAQKfysAAiIACQowIyQDAG4DACIACQowIyQDAG4DAAE1AAUUBAgJABMAxwsA.',
La='Laganddecay:BAAANQABCggIGQAAAA==.Lalii:BAAANQADCggIJAAAAA==.Lallypop:BAAANQADCggICAAAAA==.Lammoth:BAAANQADCgYICwAAAA==.Lanemogsnick:BAAANQADCgQIBAAAAA==.Layonhandsy:BAAANQAECgQIBAABNQAFFAQICQAfABYhAA==.',
Le='Leasin:BAABNQAECn8hAAIdAAgKBR9tEwDKAgAdAAgKBR9tEwDKAgAAAA==.Lencreye:BAAANQADCgMIBAAAAA==.Lethendervis:BAAANQADCgYICQAAAA==.',
Li='Lighthusk:BAAANQABCgQIBAAAAA==.Liliauna:BAABNQAECn8jAAIVAAcK+xpHaAAfAgAVAAcK+xpHaAAfAgAAAA==.Lilibejeane:BAAANQADCgcICQABNQAECgQICwANAAAAAA==.Lillynelazar:BAABNQAECn8XAAIKAAkKNQWwtACWAQAKAAkKNQWwtACWAQABNQAECgYICQANAAAAAA==.Liloisback:BAAANQAECgcIEQAAAA==.Lilsquirtboy:BAAANQADCgUIBQABNQAECgkJLAAFAOUeAA==.Linasonna:BAAANQAECgIIBAABNQAFFAUICwAOALoQAA==.Linithara:BAABNQAECn8gAAMMAAkKOg5YNgD4AQAMAAkK1AxYNgD4AQAHAAgK5QlYFgBDAQAAAA==.Littlehoosie:BAAANQAECggIBAAAAA==.',
Lo='Lockersz:BAAANQADCgEIAQABNQAFFAYIFAAjAIsXAA==.Loram:BAAANQAECgEIAQAAAA==.Lostbase:BAAANQAECgQIBAAAAA==.Lostgrip:BAAANQAECgQIBgAAAA==.',
Lu='Lucthedk:BAABNQAECn8WAAMLAAkK/xCNSwDkAQALAAkK/xCNSwDkAQAjAAQKXAqpsAArAAAAAA==.Lukis:BAAANQAECgIIAgAAAA==.Lunarpriest:BAAANQAECgQIBAAAAA==.Lunitari:BAAANQAECgEIAQAAAA==.Lunkbeck:BAAANQAECgEIAgAAAA==.Luxriel:BAAANQADCggIDAAAAA==.',
['Lø']='Lørd:BAABNQAECn8fAAMUAAkK1RgpNQCgAQAUAAgKIhYpNQCgAQAKAAUK+RR51wBMAQAAAA==.',
Ma='Madik:BAAANQADCgcJCAAAAA==.Magicmegan:BAAANQAECgEIAQABNQAECggIFgAVAKkaAA==.Maladin:BAAANQAECgIIAgAAAA==.Malkurim:BAAANQADCgEIAQAAAA==.Malvean:BAAANQADCgUIBwAAAA==.Manasa:BAAANQAECgQIBgAAAA==.Marceline:BAABNQAECn8ZAAIKAAgKMBOkagA7AgAKAAgKMBOkagA7AgAAAA==.Marthog:BAAANQAECgEIAQAAAA==.Matresstains:BAAANQAECgUICwAAAA==.',
Mc='Mcdermott:BAAANQAECgQIBgAAAA==.',
Me='Melanius:BAAANQAECgUIDQAAAA==.Melranis:BAAANQADCgcIDAAAAA==.',
Mi='Miluk:BAAANQAECgUIBgAAAA==.Misconduct:BAAANQAECgUIDQABNQAECgYICgANAAAAAA==.',
Mm='Mmins:BAAANQAECgYICgAAAA==.',
Mo='Montagne:BAAANQADCgQIBAAAAA==.Moomist:BAAANQAECgMIAwAAAA==.Moonfanna:BAAANQAECgQJBQAAAA==.Moonmx:BAAANQAECgYICQAAAA==.Morriganth:BAAANQADCgEIAQAAAA==.',
Mu='Murdamoose:BAAANQADCgIIAgAAAA==.Mustysponge:BAAANQADCgUIBwAAAA==.',
My='Mysteryx:BAABNQAECn8jAAIdAAkK9BVqGQCBAgAdAAkK9BVqGQCBAgAAAA==.Mystrbeast:BAAANQADCgQIBAAAAA==.',
['Mó']='Móxie:BAAANQADCgIIAQAAAA==.',
Na='Nahtan:BAAANQADCgYIDAAAAA==.Nammu:BAAANQADCgEIAQAAAA==.Nandisa:BAAANQADCgEIAQAAAA==.Naniwa:BAAANQAECgMIBgAAAA==.Nawala:BAAANQAECgEIAQAAAA==.Nazendrov:BAEANQAECggICAABNQAECggICAANAAAAAA==.Nazura:BAAANQADCgcIEQAAAA==.',
Ne='Nereza:BAAANQADCgYIDAAAAA==.Nershog:BAAANQAECgEIAQAAAA==.Nesquip:BAAANQADCgYJBgAAAA==.',
Ni='Nightforday:BAABNQAECn8zAAMLAAkKiSBxIwCzAgALAAkKiSBxIwCzAgAjAAIKUhVkiwB+AAAAAA==.Niko:BAAANQABCgUIBQAAAA==.Nishra:BAAANQADCggICAAAAA==.',
No='Noktas:BAAANQAECgIIAgABNQAECgYICAANAAAAAA==.Nominé:BAAANQADCgQIBgAAAA==.Nool:BAAANQADCgQIBwAAAA==.Norch:BAAANQAECgIJBAAAAA==.Notkory:BAAANQAECggICAAAAA==.Noux:BAAANQADCgcIDAABNQAECgEIAQANAAAAAA==.',
Nu='Nube:BAAANQADCgUICAAAAA==.',
Ny='Nyababa:BAAANQAECgUIBwABNQAFFAUIEQACAKoeAA==.',
Og='Ogora:BAAANQADCgQIBgAAAA==.',
Ok='Oki:BAAANQADCgMIBAAAAA==.Okktrål:BAAANQAECgYJCgAAAA==.Oktavius:BAAANQAECgcIDQAAAA==.',
Op='Ophysia:BAAANQAECgIIAgAAAA==.',
Or='Ordaka:BAAANQADCgYIBgAAAA==.Orkcansas:BAAANQAECgEIAQAAAA==.Orruutah:BAAANQADCgYIBgAAAA==.',
Os='Oskaia:BAAANQAECgYICwAAAA==.Osla:BAAANQAECgUIBQAAAA==.',
Ox='Oxytoecin:BAAANQAECgYIBgAAAA==.',
Pa='Paapineau:BAAANQAECgUICwAAAA==.Packes:BAABNQAECn8qAAIfAAkKQBnPKAB4AgAfAAkKQBnPKAB4AgAAAA==.Pakkohruun:BAABNQAECn8cAAIJAAkKQxgybQBSAgAJAAkKQxgybQBSAgAAAA==.Pallywack:BAABNQAECn8hAAIJAAcKNQ0hzgB5AQAJAAcKNQ0hzgB5AQAAAA==.Palussy:BAAANQADCgQIBAAAAA==.Parthima:BAABNQAECn8lAAIcAAgKVAeRVACDAQAcAAgKVAeRVACDAQAAAA==.Partysnaxx:BAAANQABCgEIAQAAAA==.',
Pe='Peppercat:BAAANQAECgQIBwAAAA==.Pertophos:BAAANQAECgUICQAAAA==.Pettigrew:BAAANQADCgIJAgAAAA==.',
Ph='Phantomclone:BAAANQAECgIIBQAAAA==.Philomena:BAAANQADCgUICQAAAA==.',
Pi='Piggÿ:BAAANQAECgMIBQAAAA==.Piko:BAAANQADCggIDgAAAA==.Piyo:BAAANQADCgcIBwABNQAECgkJKgAfAEAZAA==.',
Pl='Plankormast:BAAANQADCgEIAQAAAA==.',
Po='Poky:BAAANQAECgEIAQABNQAECgQIBgANAAAAAA==.Popena:BAAANQAECgMIBAAAAA==.Porkbuns:BAABNQAECn8YAAIQAAgKyBFvtgAVAgAQAAgKyBFvtgAVAgAAAA==.Potatogg:BAAANQAECgIIAwAAAA==.',
Pr='Praedor:BAAANQAECgEJAQAAAA==.Precious:BAAANQADCgEIAgAAAA==.Priestymon:BAABNQAECn8cAAIGAAkKIiEbCwBoAwAGAAkKIiEbCwBoAwABNQAFFAUIDAABAC4dAA==.Protdaddyy:BAAANQADCgUIBQAAAA==.',
Pw='Pwarr:BAACNQAFFH8JAAITAAQKxwstBADpAAATAAQKxwstBADpAAA1AAQKfxcAAxMACQqOFugRAAQCABMABwpkGegRAAQCAAEABwpnC8HPAE0BAAAA.',
Qa='Qamar:BAAANQADCgQIBAAAAA==.',
Qu='Quackadeen:BAAANQAECgIJAgAAAA==.Quaesitor:BAAANQADCgYIDwAAAA==.',
Qw='Qwarr:BAAANQAECgUICAABNQAFFAQICQATAMcLAA==.',
Ra='Raathya:BAAANQAECgcICgAAAA==.Raeljin:BAABNQAECn8ZAAIOAAgKLxl2QABxAgAOAAgKLxl2QABxAgAAAA==.Raihua:BAAANQADCgYIBgAAAA==.Rangoz:BAAANQAECgUICQAAAA==.Rar:BAAANQAECgcIDgAAAA==.Ratgamerlol:BAABNQAECn8iAAIKAAcKzyQyMwDQAgAKAAcKzyQyMwDQAgAAAA==.Ravnur:BAAANQADCggICAAAAA==.Rayennagrom:BAAANQAECgEIAQAAAA==.',
Re='Reagent:BAAANQADCgMIAwAAAA==.Reckrunner:BAAANQAECggIEgAAAA==.Redlocks:BAAANQAECgUICgAAAA==.Renault:BAAANQADCgMIAwAAAA==.Reneana:BAAANQAECgUIDAAAAA==.Restbo:BAAANQAECggIEAABNQAFFAUIFAARADwRAA==.',
Rh='Rhianonn:BAAANQAECgUICgABNQAECgMIAwANAAAAAA==.',
Ri='Riaslock:BAAANQAECgEJAQAAAA==.Richardluis:BAAANQAECgYIDAAAAA==.Rinehardtt:BAABNQAECn8oAAIIAAkK1Bt2IgDhAgAIAAkK1Bt2IgDhAgAAAA==.Riverstyxx:BAAANQADCgUICwAAAA==.Rivër:BAAANQADCggIHwAAAA==.',
Ro='Robbell:BAABNQAECn8eAAIKAAkKsBYSRQCbAgAKAAkKsBYSRQCbAgAAAA==.Rokyman:BAAANQAECgYIDgAAAA==.Roldazark:BAAANQABCgEIAQAAAA==.Roonsia:BAAANQADCgQIBQAAAA==.Rootsie:BAAANQADCgYJFwAAAA==.Roselynn:BAABNQAECn8ZAAIDAAgKbRZIHwAuAgADAAgKbRZIHwAuAgAAAA==.Rouby:BAAANQAECgEIAgAAAA==.Roughlight:BAAANQADCgMIAwAAAA==.',
Ru='Ruerl:BAABNQAECn8YAAIJAAgKTAqcyQCCAQAJAAgKTAqcyQCCAQAAAA==.Runentug:BAACNQAFFH8JAAIfAAQKFiGZDQB1AQAfAAQKFiGZDQB1AQA1AAQKfxsAAh8ACQqSJNMMAEkDAB8ACQqSJNMMAEkDAAAA.Rustyspell:BAAANQADCgIIAgAAAA==.',
Ry='Ryumapriest:BAAANQABCgEIAQAAAA==.',
['Rî']='Rîft:BAAANQADCgEIAQAAAA==.',
Sa='Sanlordriel:BAAANQAECgMIAwAAAA==.Saramon:BAAANQADCggIKQAAAA==.Sassiberry:BAAANQADCgcIEQAAAA==.Sassitude:BAAANQADCgcIFQAAAA==.Satiiva:BAAANQADCggICAAAAA==.',
Sc='Scarlos:BAAANQABCgMIAwAAAA==.Screamdying:BAAANQABCgIIAgAAAA==.Scrembiblion:BAABNQAECn8aAAIkAAgKiB0oAQDbAgAkAAgKiB0oAQDbAgAAAA==.',
Sd='Sdhoscillate:BAAANQADCgYIBgAAAA==.',
Se='Seins:BAAANQADCgYIBgAAAA==.Semillin:BAAANQAECgQIBAAAAA==.Sensjei:BAAANQAECgQIDAAAAA==.Separatist:BAAANQADCgMJAwAAAA==.Serendibitty:BAAANQADCgMJAwAAAA==.',
Sg='Sgtbreezy:BAAANQADCgcIBwAAAA==.',
Sh='Shadey:BAAANQADCgIIAgAAAA==.Shambulance:BAAANQAECgUICAAAAA==.Sharuerl:BAAANQADCgcIBwAAAA==.Shazi:BAEANQAECggICAAAAA==.Shiftroid:BAAANQADCgMIBgAAAA==.Shinyivie:BAABNQAECn8eAAIJAAkKYwWY4QBRAQAJAAkKYwWY4QBRAQAAAA==.Shiverchill:BAAANQABCgEJAQAAAA==.Shockrock:BAAANQADCgEIAQAAAA==.Shouzhe:BAAANQADCgUIBQAAAA==.Shroomjuice:BAAANQAECggIDwAAAA==.Shãdøwzzxz:BAAANQAECgUIDAAAAA==.',
Si='Sildenafil:BAAANQADCgIIAgAAAA==.Silessra:BAAANQADCggICAAAAA==.',
Sk='Skogr:BAAANQADCgIIAQABNQADCgUIBQANAAAAAA==.Skädoosh:BAAANQAECgEIAQAAAA==.',
Sl='Slapshappy:BAAANQAECggICQAAAA==.',
Sm='Smallhorn:BAAANQAECgEIAQAAAA==.Smokeyhaze:BAAANQAECgYIDgAAAA==.Smokin:BAABNQAECn8bAAIKAAcKogq3rwCgAQAKAAcKogq3rwCgAQAAAA==.Smolther:BAAANQADCgcIBwAAAA==.Smores:BAAANQADCgcJDQAAAA==.',
Sn='Sneech:BAAANQADCgYIBwAAAA==.Snowbvnni:BAAANQADCgQIBAAAAA==.',
So='Sofarkinghi:BAAANQADCgQIBAAAAA==.Sollamor:BAAANQAECgMIAwAAAA==.Solomonk:BAAANQAECgUIEgAAAA==.Solomus:BAAANQAECgUIEAAAAA==.Sonal:BAAANQAECgYIEwAAAA==.Soter:BAAANQAECgcIBwAAAA==.',
Sq='Squeaph:BAAANQAECgQIBAAAAA==.',
St='Stelltrain:BAAANQABCgIIAwAAAA==.Stormiee:BAABNQAECn8lAAIeAAkKqxijNwB+AgAeAAkKqxijNwB+AgABNQAECgMIAwANAAAAAA==.Stormroid:BAAANQAECgUICQAAAA==.Sttorm:BAAANQADCgUIBQAAAA==.Styles:BAAANQAECgUIEAAAAA==.',
Su='Sugarontop:BAAANQADCgQIBAAAAA==.Sunmx:BAABNQAECn8lAAIBAAkKlx6yKAAVAwABAAkKlx6yKAAVAwAAAA==.Superdark:BAAANQADCgIIAgAAAA==.',
Sw='Swurve:BAEANQAECgQIBwAAAA==.Swurves:BAAANQAECgIIAwABNQAECgYICAANAAAAAA==.',
Sz='Szucs:BAAANQADCgMIAwAAAA==.',
['Sã']='Sãvãge:BAAANQADCgQIBAAAAA==.',
Ta='Tabiji:BAEANQAECggICAAAAA==.Tadpole:BAAANQADCgYIBgAAAA==.Taedrum:BAAANQAECgUICgAAAA==.Taerror:BAAANQADCgIIAgAAAA==.Talegos:BAAANQAECgMJAwAAAA==.Talonfel:BAAANQADCgQIBAABNQAECgkJMgAPAI4iAA==.Taloning:BAAANQADCgYIBgABNQAECgkJMgAPAI4iAA==.Talonstryke:BAABNQAECn8yAAIPAAkKjiKSAwB3AwAPAAkKjiKSAwB3AwAAAA==.',
Te='Teatoh:BAAANQADCgcIBwAAAA==.Tenseiga:BAAANQAECggIDwABNQAFFAQICAAHABwYAA==.Tevers:BAAANQAECgEIAQAAAA==.',
Th='Thaalion:BAAANQADCggICAAAAA==.Thalantier:BAAANQADCgMIBgAAAA==.Thardal:BAABNQAECn8cAAMXAAkKgg5ICwC2AQAVAAkKiQzCegDvAQAXAAgKkQpICwC2AQAAAA==.Thebigshot:BAAANQAECgMIBQAAAA==.Theenforcer:BAABNQAECn8/AAIJAAkK4hHFhQAXAgAJAAkK4hHFhQAXAgAAAA==.Thegreekbeas:BAAANQADCgUIBQAAAA==.Theguyfurry:BAAANQAECgEIAQAAAA==.Thetzin:BAABNQAECn8ZAAIQAAYKJwNbXgHxAAAQAAYKJwNbXgHxAAAAAA==.Theunite:BAAANQADCggICAAAAA==.Thickhobo:BAAANQADCgUICQAAAA==.Thidwick:BAABNQAECn8dAAIlAAcKhiG/DACYAgAlAAcKhiG/DACYAgAAAA==.Thingtwø:BAAANQAECgYIBQAAAA==.Thistle:BAAANQADCgcIDAABNQAECgkJIAAQADQMAA==.Thraggs:BAAANQADCgcICAAAAA==.Thunderfist:BAAANQADCggIBwAAAA==.',
Ti='Titanslay:BAAANQADCgEIAQAAAA==.Titø:BAAANQADCgYIDQABNQADCgcIBwANAAAAAA==.',
Tm='Tmryuki:BAAANQAECggICQAAAA==.',
To='Tokadin:BAAANQAECgIIAgAAAA==.Tomorrow:BAAANQAECgQIBgAAAA==.Topzee:BAAANQADCgUIBQAAAA==.Totoo:BAABNQAFFH8HAAISAAcKDgApFwAhAAASAAcKDgApFwAhAAAAAA==.',
Tr='Traedarra:BAAANQADCgEIAQAAAA==.Tralis:BAEANQADCggIDgABNQAECggICAANAAAAAA==.Tranarra:BAABNQAECn80AAIVAAcKrxphZgAkAgAVAAcKrxphZgAkAgAAAA==.Traylo:BAABNQAECn8gAAIKAAgKQhO5cQArAgAKAAgKQhO5cQArAgAAAA==.',
Tv='Tvak:BAABNQAECn8VAAIJAAYKYBvQsQC2AQAJAAYKYBvQsQC2AQAAAA==.',
Tw='Twistedsham:BAAANQAECggIBgAAAA==.Twopump:BAABNQAECn8oAAIJAAgKEgm6yQCCAQAJAAgKEgm6yQCCAQAAAA==.',
['Tó']='Tónka:BAAANQADCgcJBwAAAA==.',
Ul='Ulhae:BAAANQABCgQIBAAAAA==.Ulinova:BAAANQAECgQIBgAAAA==.',
Um='Umbressa:BAAANQADCgMIAwABNQAECgkJKgAKAJkaAA==.Umbryx:BAAANQADCgIIAgABNQAECgUIEgANAAAAAA==.',
Un='Unholly:BAAANQAECgIJAwAAAA==.',
Ur='Uroro:BAABNQAECn8kAAMeAAkK+SDkFwASAwAeAAkK+SDkFwASAwAOAAEKAABtPgEsAAABNQAFFAUIEQACAKoeAA==.',
Uu='Uu:BAAANQABCgIIAgAAAA==.',
Va='Vainqueur:BAAANQAECgcIEwAAAA==.Valienni:BAAANQAECgEIAQAAAA==.Vanderdemon:BAAANQADCgMIAwAAAA==.Vanderlight:BAAANQADCgUJCQAAAA==.Vandernum:BAAANQAECggIAwAAAA==.Vandersus:BAAANQADCggIBQAAAA==.Varm:BAAANQADCggICAAAAA==.',
Ve='Velakai:BAAANQABCgQIBAAAAA==.Vervaeda:BAAANQADCgQIBAAAAA==.Verymelon:BAAANQAECgQIBgABNQAECgkJOQAOAJ4hAA==.Vestele:BAAANQADCggIDwAAAA==.',
Vg='Vgx:BAABNQAECn8bAAIjAAcKIw8DUABrAQAjAAcKIw8DUABrAQAAAA==.',
Vi='Vielitre:BAAANQADCgUIBwAAAA==.Vigossfel:BAAANQADCgMIBwAAAA==.Viintage:BAABNQAECn8jAAIQAAcKkxYltgAVAgAQAAcKkxYltgAVAgAAAA==.Viridius:BAAANQADCgMIBQAAAA==.Vishouspayne:BAAANQAECgQICwAAAA==.',
Vo='Voidshank:BAAANQAECgEIAgAAAA==.',
Vy='Vyolence:BAAANQAECgEIAQABNQAECggIIQAdAAUfAA==.',
['Vä']='Väelün:BAABNQAECn8ZAAMhAAYKuBSBNwCDAQAhAAYKuBSBNwCDAQAMAAEKawSpmQAnAAABNQAECgkJIQAeAB4SAA==.',
['Vÿ']='Vÿ:BAAANQAECgUIBQAAAA==.',
Wa='Wachoosh:BAAANQAECgEIAgAAAA==.Waidmanns:BAABNQAECn8qAAMKAAkKmRriJgD6AgAKAAkKmRriJgD6AgAmAAEKAACwFAAmAAAAAA==.Walmartstaff:BAAANQADCgUIBQAAAA==.Warfable:BAAANQADCgIIAgAAAA==.',
Wg='Wgnmd:BAAANQAECgQIBQAAAA==.',
Wh='Wham:BAAANQADCgUIBwAAAA==.Whatsaggro:BAABNQAECn8jAAILAAgKhwk0ZwBwAQALAAgKhwk0ZwBwAQAAAA==.Whatshadow:BAAANQAECgQIBAAAAA==.Whatyamean:BAAANQAECgQIDwAAAA==.Whoami:BAAANQAECggIBAAAAA==.Whoangry:BAABNQAECn8UAAInAAcKPg+CRACwAQAnAAcKPg+CRACwAQAAAA==.Whomonk:BAAANQAECgIIBAAAAA==.',
Wi='Wickedchick:BAAANQADCggIGQAAAA==.Willowknight:BAAANQADCgYICgAAAA==.Winterknight:BAAANQADCgQIBgAAAA==.',
Wr='Wrenn:BAAANQAECgIIAgAAAA==.Wrongname:BAAANQAECgMIBgAAAA==.',
Wu='Wumba:BAAANQAECgMIAwAAAA==.',
Xa='Xanthe:BAAANQADCggIBwAAAA==.',
Xf='Xfloki:BAAANQADCgQIBAAAAA==.',
['Xß']='Xß:BAAANQADCgIJBAAAAA==.',
Ya='Yakpriest:BAAANQADCgcIDAAAAA==.',
Yd='Ydgktt:BAAANQADCgEIAQAAAA==.',
Yn='Ynhük:BAAANQADCgMIAwAAAA==.',
Yo='Yogsothoth:BAEBNQAECn8pAAIKAAkKxRwuKAD2AgAKAAkKxRwuKAD2AgAAAA==.',
Yr='Yrdenal:BAAANQADCgcICQAAAA==.',
Yu='Yugalipdeez:BAAANQAECgEIAgAAAA==.Yulian:BAAANQAECgQICgAAAA==.',
Za='Zaartyn:BAABNQAECn8mAAIVAAkKvR8uEwA/AwAVAAkKvR8uEwA/AwAAAA==.Zaater:BAAANQAECgIIAQAAAA==.Zalin:BAAANQAECgEIAQABNQAECgkJHAAXAIIOAA==.Zanki:BAAANQAECgUICgAAAA==.',
Ze='Zeebeth:BAABNQAECn8XAAIKAAgKkQ46iwDwAQAKAAgKkQ46iwDwAQAAAA==.Zefi:BAAANQAECgcIAgAAAA==.Zellek:BAAANQADCgYIBgAAAA==.Zenbu:BAAANQADCgIIAgAAAA==.Zeroasy:BAAANQADCgIIAgABNQAECgcIHQAfAEYkAA==.Zerokai:BAAANQAECgUIBAAAAA==.Zeztz:BAAANQAECgcIDAAAAA==.',
Zo='Zomlo:BAAANQAECgEIAQAAAA==.Zooli:BAAANQADCggICAAAAA==.Zorosenpai:BAAANQADCgcIEQABNQAECggIIgAjAJ8KAA==.',
Zu='Zuggernaught:BAAANQAECgUIBQAAAA==.',
['Át']='Átomic:BAAANQADCgUIAwAAAA==.',
['Ân']='Ânimosity:BAAANQADCgIIAgAAAA==.',
['Âr']='Ârtemis:BAAANQAECgQIBAABNQAFFAQICAAHABwYAA==.',
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
