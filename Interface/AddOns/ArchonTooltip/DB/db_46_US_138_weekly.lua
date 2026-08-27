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

local lookup = {'Druid-Guardian','Shaman-Elemental','Shaman-Restoration','Paladin-Protection','DemonHunter-Devourer','DeathKnight-Unholy','Rogue-Subtlety','Unknown-Unknown','Evoker-Preservation','Mage-Frost','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Survival','Priest-Holy','Mage-Arcane','Warrior-Fury','Evoker-Augmentation','Priest-Shadow','Warlock-Demonology','Evoker-Devastation','Druid-Balance','Monk-Brewmaster','Monk-Mistweaver','Monk-Windwalker','Druid-Restoration','Warlock-Affliction','Shaman-Enhancement','Paladin-Retribution','Warrior-Arms','Warrior-Protection','Rogue-Assassination','Warlock-Destruction','Paladin-Holy','DemonHunter-Havoc','Priest-Discipline','DemonHunter-Vengeance','Rogue-Outlaw','DeathKnight-Frost','Hunter-Marksmanship','Druid-Feral',}
local provider = {region='US',realm='KulTiras',name='US',type='weekly',zone=46,date='2026-08-25',data={Aa='Aaissis:BAAALgAECgQJBAABLgAECgkJKwABABQaAA==.Aarix:BAABLgAECn8UAAICAAkJQRESKQCnAQACAAkJQRESKQCnAQAAAA==.',
Ae='Aedrelyn:BAAALgAECgcJDQAAAA==.Aegia:BAABLgAECn8ZAAMDAAcJrxCdVgBcAQADAAcJrxCdVgBcAQACAAMJTQGHgABFAAAAAA==.Aegrim:BAAALgAECgEJAQABLgAECgkJLwAEAIMeAA==.Aendillan:BAABLgAECn8WAAIFAAkJuRpmFgDSAAAFAAkJuRpmFgDSAAAAAA==.Aewrynn:BAAALgAECgIJAgAAAA==.',
Af='Affonasei:BAABLgAECn86AAIGAAkJvA/cXACxAQAGAAkJvA/cXACxAQAAAA==.',
Ai='Aicaramba:BAAALgAECgYJCgAAAA==.Aileen:BAAALgAFFAIJAgAAAA==.',
Ak='Akashi:BAAALgAFFAIJAwABLgAFFAUJFgAHAM4cAA==.',
Al='Alacrodie:BAAALgAECgQJDAAAAA==.Alladorn:BAAALgADCgEJAQAAAA==.Allarii:BAAALgAECgUJBQABLgAECgUJBQAIAAAAAA==.Allynoon:BAAALgADCgMJAwAAAA==.Alurynath:BAAALgAECgEJAQABLgAECgkJLwAEAIMeAA==.',
An='Anahla:BAAALgAECgUJBQABLgAECgkJOQAJAIIYAA==.Ancbow:BAAALgADCgUJBQAAAA==.Angrydisc:BAAALgADCgUJBQABLgAECgkJPAAKAEgKAA==.Angrytotems:BAAALgAECgYJEQABLgAECgkJPAAKAEgKAA==.Angyll:BAAALgADCgUJAQAAAA==.Annaborshen:BAAALgADCgcJCgAAAA==.Antoccino:BAABLgAECn8sAAILAAkJ9yH1AwD6AgALAAkJ9yH1AwD6AgAAAA==.',
Ar='Aragorno:BAABLgAECn8sAAMMAAkJrBdVJwBCAgAMAAkJrBdVJwBCAgANAAQJRAZgQgC6AAAAAA==.Araziel:BAAALgAECgMJBAAAAA==.Arcturen:BAABLgAECn85AAIMAAkJYBxIBgBAAgAMAAkJYBxIBgBAAgAAAA==.Arenthal:BAAALgAFFAEJAQABLgAFFAQJCAAKAEgUAA==.Arill:BAAALgADCgYJBgAAAA==.Arkulas:BAAALgAECgYJBwAAAA==.Artemisha:BAAALgADCgEJAQABLgAFFAEJAQAIAAAAAA==.Arturaan:BAAALgAECgEJAQAAAA==.',
As='Ashalana:BAAALgAECgcJEAAAAA==.Asheby:BAAALgAECgIJAwABLgAECgkJOwAOAD8cAA==.Ashiera:BAABLgAECn8yAAMKAAkJ+gNSqgAqAQAKAAkJ+gNSqgAqAQAPAAEJ7AHwIgATAAAAAA==.',
At='Atomic:BAABLgAECn8iAAIQAAkJqwzCCABIAQAQAAkJqwzCCABIAQAAAA==.',
Au='Aurorée:BAAALgAECgEJAQAAAA==.Ausuna:BAAALgAECgYJBwAAAA==.',
Av='Avelai:BAAALgADCgkJEgAAAA==.',
Aw='Awhiteboy:BAAALgAECgcJDgABLgAECgkJLQAHAJ8fAA==.',
Az='Azeral:BAAALgADCgYJBgAAAA==.Azylstrid:BAAALgAECgQJBAAAAA==.',
Ba='Babyshred:BAAALgAECgYJCAAAAA==.Badonka:BAAALgAECgQJBAABLgAECgkJSAARAG8eAA==.Bahaana:BAAALgAECgUJBgAAAA==.Balentine:BAACLgAFFH8HAAIOAAMJKxLqEQCYAAAOAAMJKxLqEQCYAAAuAAQKfx0AAw4ACAkxE+o6AAsBAA4ABwkCE+o6AAsBABIABQnHA/tHAMEAAAAA.Bananasloth:BAAALgAECgcJEQABLgAFFAkJXwATAFklAA==.Banjali:BAAALgADCgMJAwAAAA==.Banostraza:BAABLgAECn9IAAMRAAkJbx6/CQC8AgARAAkJyB2/CQC8AgAUAAEJ2RQxIgBFAAAAAA==.Baspir:BAABLgAECn8pAAIVAAkJNxbAJAClAQAVAAkJNxbAJAClAQAAAA==.',
Be='Beeboop:BAAALgAECgYJEQAAAA==.Belly:BAAALgAECgIJAgABLgAECgkJLQAHAJ8fAA==.Belrae:BAACLgAFFH8NAAIFAAMJnQ9JMAC2AAAFAAMJnQ9JMAC2AAAuAAQKfzYAAgUACQlSF78lADcCAAUACQlSF78lADcCAAAA.Belrinthe:BAABLgAFFH8GAAIWAAMJ3xbsEADMAAAWAAMJ3xbsEADMAAAAAA==.Berenzen:BAAALgAECgEJAgAAAA==.Bethaliz:BAAALgAECgIJAgAAAA==.Bezieck:BAABLgAECn9CAAISAAgJjRYtBwBoAQASAAgJjRYtBwBoAQAAAA==.',
Bi='Bigdawg:BAAALgAECggJEAAAAA==.Bigdeborah:BAAALgAECgUJBQAAAA==.Bigfolks:BAAALgAECgIJAwAAAA==.Bigollock:BAAALgAECgEJBAAAAA==.Billyhikz:BAABLgAECn8oAAIKAAkJ8w3oYAC+AQAKAAkJ8w3oYAC+AQAAAA==.Birdbrain:BAAALgAFFAIJAwAAAA==.Biru:BAAALgAFFAIJAgABLgAFFAQJCQAOAM8QAA==.',
Bl='Bloodarrow:BAABLgAECn8VAAIMAAYJgBj5JADIAAAMAAYJgBj5JADIAAAAAA==.',
Bo='Bobino:BAAALgADCgEJAQAAAA==.Bockchi:BAABLgAECn8YAAMXAAYJ5RcHOgCJAQAXAAYJ5RcHOgCJAQAYAAEJaRX3lAA7AAAAAA==.Bonegavel:BAAALgAECgUJBwAAAA==.Bookhuntress:BAABLgAECn8jAAQZAAcJ3RtAJgAfAgAZAAcJ3RtAJgAfAgAVAAYJ5xcsNABIAQABAAEJnAwahAAcAAAAAA==.Bordrann:BAAALgAECgQJBwAAAA==.Bosyoh:BAAALgAECgIJAgAAAA==.',
Br='Branaxe:BAAALgAECgkJEgAAAA==.Brandisheer:BAAALgAECgYJCAAAAA==.Branex:BAAALgAECgQJBAAAAA==.Branpaw:BAAALgAECgIJAwABLgAECgkJEgAIAAAAAA==.Branthor:BAAALgADCgIJAgAAAA==.Brewdeez:BAACLgAFFH8JAAIYAAUJbAm3HwDaAAAYAAUJbAm3HwDaAAAuAAQKfzQAAhYACQktH7UIAKcCABYACQktH7UIAKcCAAAA.Brewzen:BAAALgAECgEJAQAAAA==.Brewzer:BAACLgAFFH8SAAIXAAQJuAvBNwDJAAAXAAQJuAvBNwDJAAAuAAQKfykAAxcACQkVFRs3AJcBABcACQkVFRs3AJcBABgABQmtDBBYAK8AAAAA.Brick:BAAALgAECgYJCgAAAA==.Brint:BAABLgAECn8fAAMTAAgJNg+GawBlAQATAAgJMw+GawBlAQAaAAEJshNcOQBCAAAAAA==.Brok:BAABLgAECn8UAAIbAAgJPxqRCQAjAgAbAAgJPxqRCQAjAgAAAA==.Brokenhorn:BAAALgADCgYJGAAAAA==.Bronad:BAACLgAFFH87AAIKAAYJhiWjDgAgAgAKAAYJhiWjDgAgAgAuAAQKfyIAAgoACAkXJdEjAOMCAAoACAkXJdEjAOMCAAEuAAUUCAk1AAoAkB8A.Bronst:BAAALgAECgEJAwABLgAECgkJMQACAOYYAA==.Broomhandle:BAABLgAECn9DAAIcAAkJJiVZBgA+AwAcAAkJJiVZBgA+AwAAAA==.',
Bu='Bubbletea:BAAALgAECgYJDAAAAA==.Bumbushka:BAACLgAFFH8eAAIQAAYJZh/JCgC2AQAQAAYJZh/JCgC2AQAuAAQKfxkAAxAABwl/IyskADUCABAABwl/IyskADUCAB0AAgnfGNcrAJUAAAAA.Burinn:BAAALgAECgcJCgABLgAECgkJSAAOAFkPAA==.',
Ca='Caeus:BAABLgAECn8xAAIGAAkJnyRSBwA7AwAGAAkJnyRSBwA7AwAAAA==.Cam:BAABLgAECn8xAAIKAAkJlCXtCwAZAwAKAAkJlCXtCwAZAwAAAA==.Capriestson:BAAALgADCgkJCQABLgAECgYJFgABAFYQAA==.Cardo:BAAALgADCgUJBQABLgAFFAkJHQAMAOwZAA==.Care:BAABLgAECn8ZAAIKAAkJjAwciADBAQAKAAkJjAwciADBAQAAAA==.Carolinabele:BAAALgAECgcJBgAAAA==.Carrowend:BAAALgAECgMJAwAAAA==.Cauud:BAABLgAECn8gAAIeAAYJ8RP4IwARAQAeAAYJ8RP4IwARAQAAAA==.',
Cb='Cbd:BAAALgADCgcJCAAAAA==.',
Ch='Chacruna:BAAALgAECgUJCQAAAA==.Charmed:BAAALgAECgUJBgAAAA==.Cheesús:BAAALgAECggJDAAAAA==.Chelan:BAABLgAECn9IAAMOAAkJWQ//IgCrAQAOAAkJWQ//IgCrAQASAAkJjgW7OgAoAQAAAA==.Chiji:BAAALgAECgYJBQAAAA==.Chilljaeden:BAAALgAECgUJDQAAAA==.Chizuko:BAAALgADCgMJAwAAAA==.Chuntspeed:BAAALgAECgQJBAAAAA==.Chuye:BAAALgAFFAEJAQABLgAFFAQJCQAOAM8QAA==.',
Ci='Cigs:BAAALgAECgYJBgABLgAFFAkJOgAKAPskAA==.Cindylouwho:BAAALgADCgMJAwAAAA==.Cinnabunz:BAABLgAECn8hAAITAAgJLQxvGgClAAATAAgJLQxvGgClAAAAAA==.Citorcen:BAAALgAECgEJBAAAAA==.',
Cl='Clambulance:BAAALgAFFAQJBAAAAA==.Cleaväge:BAAALgADCgYJBgAAAA==.Cleurisse:BAABLgAFFH8ZAAILAAUJ5heSGAAjAQALAAUJ5heSGAAjAQAAAA==.Cloudlol:BAAALgAECgQJBgAAAA==.Clueless:BAAALgADCgMJAwAAAA==.',
Cn='Cnova:BAAALgAECgUJDgABLgAECgkJPgAcADUhAA==.',
Co='Codythedead:BAABLgAFFH8GAAIGAAIJ7RQd3ACHAAAGAAIJ7RQd3ACHAAAAAA==.Compadre:BAABLgAECn8YAAQYAAkJax7NHQDrAQAYAAcJ0RrNHQDrAQAWAAQJUiAiRAAyAQAXAAcJ4BA4RADMAAAAAA==.Contekst:BAABLgAECn8iAAMZAAgJQA8XWQAtAQAZAAgJQA8XWQAtAQAVAAcJxAaoVwCzAAAAAA==.Coolsbeans:BAAALgAECgYJCwAAAA==.Coraf:BAACLgAFFH8sAAIDAAgJCSDXAwCWAgADAAgJCSDXAwCWAgAuAAQKfzgAAgMACQkAJMABAHQDAAMACQkAJMABAHQDAAAA.',
Cr='Crankzilla:BAAALgADCggJFgAAAA==.Cravix:BAAALgADCgYJBgAAAA==.Cruoris:BAABLgAECn8bAAIfAAcJww2MDwArAQAfAAcJww2MDwArAQAAAA==.',
Cu='Cunfuzed:BAAALgAECgEJAQAAAA==.Cuvier:BAABLgAECn8hAAIfAAcJMQVrEwDxAAAfAAcJMQVrEwDxAAAAAA==.',
Da='Daddle:BAABLgAECn8gAAQTAAkJayNrDwDRAgATAAkJ5iFrDwDRAgAaAAYJWSIkCgC+AQAgAAEJAADTVAAAAAAAAA==.Daemonxblack:BAAALgAECgEJAQAAAA==.Daeth:BAAALgAECgMJBQAAAA==.Daeththane:BAAALgAECgEJAQAAAA==.Dahaxors:BAABLgAECn8lAAIGAAkJGxvOLwBAAgAGAAkJGxvOLwBAAgAAAA==.Dalareas:BAAALgAECgMJAwAAAA==.Danak:BAAALgAECgIJCAAAAA==.Dannika:BAAALgAECgYJBwAAAA==.Dantelous:BAAALgAECgEJAgAAAA==.Darthwader:BAAALgAECgUJCAAAAA==.Dascrazy:BAABLgAECn8nAAMHAAgJ7QwMJQBtAQAHAAgJ7QwMJQBtAQAfAAUJNAe/FwC4AAAAAA==.Daynaa:BAAALgAECgYJEQABLgAFFAIJCAAhAOAYAA==.',
De='Deadlyfrosty:BAABLgAECn8cAAIGAAYJ3gMXEAGYAAAGAAYJ3gMXEAGYAAAAAA==.Deathsfather:BAAALgADCgYJBgABLgAECgcJEwAIAAAAAA==.Debixie:BAACLgAFFH8TAAIfAAQJyB3eAgB8AQAfAAQJyB3eAgB8AQAuAAQKfyUAAh8ACQlLI04BACUDAB8ACQlLI04BACUDAAAA.Dejection:BAAALgAECgEJAQAAAA==.Delron:BAAALgADCgEJAQAAAA==.Demisi:BAAALgAECgcJEwAAAA==.Demoness:BAABLgAECn8iAAMFAAkJQSK0FQCWAgAFAAgJZCK0FQCWAgAiAAEJTCFiVwBgAAAAAA==.Demsynth:BAAALgAECgQJBAABLgAECgkJJgAPAOYgAA==.Derangedsp:BAAALgAFFAIJAgABLgAFFAkJXwATAFklAA==.Destorr:BAAALgADCgQJBAAAAA==.Dextero:BAAALgADCgMJAwAAAA==.',
Di='Diasundra:BAABLgAECn8sAAIMAAkJ5h9NDgDKAgAMAAkJ5h9NDgDKAgAAAA==.Digiornos:BAABLgAECn8jAAITAAkJqhRCPQDnAQATAAkJqhRCPQDnAQAAAA==.Divinatjin:BAAALgAECgUJDgAAAA==.',
Dj='Djyinn:BAAALgADCgcJCgAAAA==.',
Do='Doorknob:BAAALgAECgYJCQAAAA==.Dottingyou:BAACLgAFFH8mAAMTAAgJXRQmJwCrAQATAAcJ3RYmJwCrAQAgAAEJXQWVIwBOAAAuAAQKfzUAAxMACQnvHw4QAMwCABMACQnvHw4QAMwCACAAAwlMHzYsAA4BAAAA.',
Dr='Draenei:BAAALgAECgEJAQAAAA==.Draeziq:BAAALgAECgQJBgABLgAFFAIJCAAhAOAYAA==.Dragonpo:BAAALgAECgEJAQAAAA==.Dragonshide:BAAALgAECgEJAgAAAA==.Drakkonde:BAABLgAECn8bAAITAAYJUhafegBEAQATAAYJUhafegBEAQAAAA==.Dravin:BAAALgADCgYJBgAAAA==.Drazarth:BAAALgAECgUJDQAAAA==.Dreamon:BAAALgAFFAEJAwAAAA==.Droplet:BAAALgAECgQJBAABLgAFFAIJBQAXAAEfAA==.Drransom:BAAALgAECgEJAgAAAA==.Dryan:BAAALgAECgYJEwAAAA==.Dryon:BAABLgAECn82AAIeAAkJPB9TBQDEAgAeAAkJPB9TBQDEAgAAAA==.',
Du='Duergan:BAAALgADCgEJAQAAAA==.Duo:BAABLgAECn8xAAIMAAkJXBNgRwDMAQAMAAkJXBNgRwDMAQAAAA==.Duragon:BAABLgAECn8yAAQRAAkJ7RbBGAARAgARAAkJ7RbBGAARAgAUAAgJPwUoFgCyAAAJAAYJPwdHJwCxAAAAAA==.',
['Dí']='Díznutz:BAABLgAECn8OAAIFAAYJ6RBJeAA+AQAFAAYJ6RBJeAA+AQABLgAFFAMJBQAMAFsaAA==.',
El='Eldumir:BAAALgADCgIJBAABLgAECgkJLwAEAIMeAA==.Elyleath:BAAALgAECgYJBgAAAA==.',
Em='Emilia:BAABLgAECn8vAAMOAAkJHAyUCQAbAQAOAAkJHAyUCQAbAQAjAAMJoQcvGAB1AAAAAA==.Empanada:BAAALgADCgEJAQAAAA==.',
En='Endressa:BAABLgAECn8yAAMjAAkJPw8rGwD2AQAjAAkJPw8rGwD2AQASAAIJTw9lbwBlAAAAAA==.English:BAABLgAECn8zAAIKAAkJdBu8NwA5AgAKAAkJdBu8NwA5AgAAAA==.',
Er='Erelios:BAABLgAECn8vAAIEAAkJgx5iBQCbAgAEAAkJgx5iBQCbAgAAAA==.Erubus:BAAALgADCgUJCAAAAA==.',
Es='Eski:BAAALgAECgEJAwAAAA==.',
Eu='Eureka:BAEALgAECgMJCAABLgAECgkJMQAhACYmAA==.',
Ev='Everlight:BAAALgAECgQJBQABLgAECgkJJgABAM0TAA==.Evileyes:BAAALgADCgMJAgAAAA==.Evilfoids:BAAALgAECgEJAQAAAA==.',
Ey='Eyezoffury:BAAALgAECgIJAgABLgAECgkJPAAKAEgKAA==.',
Ez='Ezrì:BAAALgAECgMJCQAAAA==.',
Fa='Faddeyshnek:BAABLgAECn8oAAIMAAkJSxZTOwDyAQAMAAkJSxZTOwDyAQAAAA==.Fastbeefball:BAAALgAECgQJBAAAAA==.Fatgirljuice:BAAALgADCgMJAwABLgAFFAkJRgARABYgAA==.',
Fe='Feliseda:BAAALgADCgkJCwAAAA==.Felorianis:BAAALgADCgEJAQABLgAECgkJOgAFAKkeAA==.Felysambre:BAABLgAECn8WAAMFAAkJWgx2EAAKAQAFAAgJSAx2EAAKAQAkAAEJ1gybDQA1AAAAAA==.',
Fi='Filibertos:BAABLgAFFH8HAAIFAAUJ2xxgGwA7AQAFAAUJ2xxgGwA7AQABLgAFFAkJOgAKAPskAA==.Firvessa:BAAALgAFFAEJAgAAAA==.Fish:BAACLgAFFH9GAAISAAkJ8CYMAACbAwASAAkJ8CYMAACbAwAuAAQKfzcAAhIACAmOJlYCAIwDABIACAmOJlYCAIwDAAAA.',
Fl='Flight:BAACLgAFFH8WAAMHAAUJzhy5GABMAQAHAAUJzhy5GABMAQAlAAIJ9BX9CwCkAAAuAAQKfx4AAwcACQm2G3cUAG8CAAcACQkeG3cUAG8CAB8AAQkBDiweADwAAAAA.Fluxyouup:BAABLgAECn8gAAMDAAkJmghnVwBZAQADAAkJmghnVwBZAQACAAYJCQXWaACsAAAAAA==.Fløki:BAAALgAECgIJAgAAAA==.',
Fo='Follow:BAAALgAECgQJBQAAAA==.Forsynth:BAABLgAECn8mAAMPAAkJ5iDWAADgAgAPAAkJ5iDWAADgAgAKAAEJAABIdQEwAAAAAA==.Foxymeatbal:BAAALgAECgMJAwAAAA==.',
Fr='Frankdux:BAAALgADCgEJAQAAAA==.Frrostitute:BAAALgADCgEJAQAAAA==.',
Ge='Gewitt:BAABLgAECn8tAAMDAAkJgh4cFgCZAgADAAkJgh4cFgCZAgACAAgJ2hnYKADNAQAAAA==.',
Gg='Ggiven:BAABLgAECn8XAAIFAAcJjRJCYQBmAQAFAAcJjRJCYQBmAQAAAA==.',
Gl='Glinda:BAAALgAECgQJCwAAAA==.',
Gn='Gnow:BAAALgADCgEJAQAAAA==.',
Go='Gonjah:BAAALgAECgcJEAAAAA==.',
Gr='Grabomage:BAACLgAFFH81AAIKAAgJkB+3CgBiAgAKAAgJkB+3CgBiAgAuAAQKf3UAAgoACQnsJg8AAKgDAAoACQnsJg8AAKgDAAAA.Grabovoker:BAABLgAFFH8IAAIRAAQJlxJyGgDVAAARAAQJlxJyGgDVAAABLgAFFAgJNQAKAJAfAA==.Grag:BAAALgADCgMJBQAAAA==.Grapekoolaid:BAAALgAECgYJDwAAAA==.Grapesloth:BAAALgAECgQJBAABLgAFFAkJXwATAFklAA==.Grazienne:BAAALgAECgQJCQAAAA==.Greavos:BAAALgAECgEJAgABLgAECgkJPQAKAI0hAA==.Gretchen:BAAALgADCgUJBQAAAA==.Grif:BAAALgADCgMJAwAAAA==.Grilm:BAABLgAECn8tAAIBAAkJhx/oBQCnAgABAAkJhx/oBQCnAgAAAA==.Grimbaine:BAABLgAECn84AAIcAAkJCCMjCAAqAwAcAAkJCCMjCAAqAwAAAA==.Grimbane:BAAALgAECgMJBAAAAA==.Grimgar:BAAALgAECgEJAgAAAA==.Grimmshady:BAAALgAECgQJBgAAAA==.Grizzlegrimm:BAAALgAECgEJAgAAAA==.Groot:BAAALgAECgkJAQAAAA==.Gryphin:BAAALgADCgcJBwAAAA==.',
Gu='Gulmok:BAAALgADCgUJDQAAAA==.Gumbles:BAACLgAFFH8JAAIOAAQJzxBnFgBpAAAOAAQJzxBnFgBpAAAuAAQKfygABA4ACQlUHWgRAFcCAA4ACQlUHWgRAFcCACMAAglJB3tuAE4AABIAAQnUA5dnACoAAAAA.Gurney:BAABLgAECn8qAAMhAAkJ/hauHQAWAgAhAAkJ/hauHQAWAgAEAAEJggQxWQAdAAAAAA==.Guzfu:BAABLgAECn8UAAIYAAcJgg1jSgDYAAAYAAcJgg1jSgDYAAAAAA==.Guzprimal:BAAALgAECgEJAQABLgAECgcJFAAYAIINAA==.',
Gw='Gwenory:BAAALgAECgEJAQAAAA==.',
Gy='Gying:BAABLgAECn9EAAMWAAkJhR1uCACsAgAWAAkJhR1uCACsAgAYAAUJcg8FQAAZAQAAAA==.',
Ha='Hanekawa:BAAALgAECgkJCQABLgAFFAcJHgAKADIfAA==.Hanjabs:BAAALgAECgYJDgAAAA==.Hanmine:BAAALgAECgYJDQAAAA==.Hannie:BAAALgAECgQJCgAAAA==.Happyelf:BAAALgAECgYJDgAAAA==.Hartephinar:BAAALgAECgEJAQAAAA==.Hatike:BAAALgAECgEJAQAAAA==.',
He='Headhúnter:BAACLgAFFH8FAAIMAAMJWxouWgDxAAAMAAMJWxouWgDxAAAuAAQKfxgAAgwACQlYH0ARAMcCAAwACQlYH0ARAMcCAAAA.Heatseeka:BAABLgAECn8YAAIDAAgJFw5AWQBSAQADAAgJFw5AWQBSAQAAAA==.Hexxiz:BAAALgAECggJDQABLgAECgkJPQAZAB4kAA==.Hezanji:BAAALgAFFAEJAQAAAA==.',
Hi='Hiphopinator:BAABLgAECn8vAAMQAAkJLyWHBgD2AgAQAAkJCSOHBgD2AgAeAAcJHCWGDwDwAQAAAA==.',
Ho='Holydeath:BAAALgAECgEJAQAAAA==.Holyshock:BAABLgAECn8UAAIhAAcJrRcIMACaAQAhAAcJrRcIMACaAQAAAA==.Holyterror:BAAALgAECgQJDAAAAA==.Honeysweety:BAAALgAECgIJAgAAAA==.',
Hy='Hydril:BAAALgADCgEJAQAAAA==.',
['Hö']='Hööters:BAABLgAFFH8IAAIcAAUJqwyebgDTAAAcAAUJqwyebgDTAAAAAA==.',
['Hø']='Hødør:BAAALgAECgQJCwAAAA==.',
Ia='Iamcro:BAAALgAECgUJBgAAAA==.Ianthe:BAABLgAECn83AAIPAAkJ8At1AgBeAQAPAAkJ8At1AgBeAQAAAA==.',
Ib='Iboga:BAAALgAECgUJCgAAAA==.Ibrahimovic:BAABLgAECn80AAQgAAcJryPdCwCBAQAgAAUJHCTdCwCBAQAaAAYJURlGDwBoAQATAAQJjB1qfABAAQAAAA==.',
Ig='Ignitecro:BAAALgADCgUJBQAAAA==.Igram:BAAALgAECgQJBAAAAA==.',
Ih='Iheal:BAAALgADCgcJCgAAAA==.',
Il='Illidoonger:BAAALgAECgYJDwAAAA==.',
Im='Imauggin:BAAALgADCgYJBgAAAA==.Imbobbymom:BAAALgAECgEJAgABLgAFFAkJRgARABYgAA==.Imhim:BAAALgAECgEJAQAAAA==.',
In='Inafume:BAAALgAECgcJDQAAAA==.Infoxicated:BAAALgAECgUJCgABLgAECgYJCAAIAAAAAA==.Inoxia:BAAALgAECgUJCQAAAA==.Intrépidice:BAAALgAECgQJBwAAAA==.',
Io='Iowastyle:BAABLgAECn84AAMOAAkJHSC7BQAdAwAOAAkJHSC7BQAdAwAjAAMJlgx+QwCZAAAAAA==.',
It='Ithruyn:BAAALgAECgQJBQAAAA==.',
Ix='Ixtabay:BAACLgAFFH8dAAMaAAYJLRfIAgA3AQAaAAUJfhzIAgA3AQATAAIJvge4aQA4AAAuAAQKfzoABBoACQn0Ia8EAE8CABoACQmXIa8EAE8CABMABgnBGg5CANYBACAAAgm6EoBTAHQAAAAA.',
Ja='Jakobey:BAAALgAECgQJCAAAAA==.Jamurra:BAABLgAECn8qAAMDAAkJTxkWAwCVAgADAAkJTxkWAwCVAgACAAEJeg0ULwApAAABLgAFFAIJCAAhAOAYAA==.Jaylinn:BAABLgAECn8uAAIMAAkJ4Q3TVAClAQAMAAkJ4Q3TVAClAQAAAA==.Jazzmend:BAAALgADCgEJAQAAAA==.',
Je='Jeanne:BAAALgAECgYJBwAAAA==.Jessika:BAACLgAFFH9GAAMRAAkJFiBPAgDmAgARAAkJFiBPAgDmAgAUAAIJhgyWBgBWAAAuAAQKfyoAAxEACQmjJfcBAGIDABEACQmjJfcBAGIDABQABgmRI78PAN8BAAEuAAUUCQlGABEAFiAA.Jezebel:BAAALgAECgUJBQABLgAECgkJOQAJAIIYAA==.',
Ji='Jimsonweed:BAAALgAFFAEJAQAAAA==.',
Jo='Jocko:BAAALgADCgYJBgAAAA==.Josie:BAABLgAECn8pAAIjAAkJFiRcBABPAwAjAAkJFiRcBABPAwAAAA==.',
Ju='Judgekoopa:BAABLgAECn8qAAIhAAkJcx0rCwDaAgAhAAkJcx0rCwDaAgAAAA==.',
Ka='Kaadore:BAAALgAECgYJBwAAAA==.Kaeiria:BAAALgAECgUJCgAAAA==.Kael:BAAALgAECgEJAQAAAA==.Kalaanri:BAABLgAECn8xAAMCAAkJLxQyKACsAQACAAkJLxQyKACsAQADAAYJig6haQAfAQAAAA==.Kaleberry:BAABLgAECn8gAAMVAAkJBA6GJgCZAQAVAAgJBA6GJgCZAQAZAAcJEgmlhgDJAAAAAA==.Kalthyra:BAAALgAECgMJAwABLgAECgkJLwAEAIMeAA==.Kalyandra:BAABLgAECn8nAAIYAAgJcRFENAAyAQAYAAgJcRFENAAyAQAAAA==.Kalógeros:BAAALgADCgMJAwAAAA==.Kanhang:BAAALgADCgcJDAAAAA==.Kanra:BAABLgAECn8XAAQBAAYJ6RydFwCUAQABAAYJ6RydFwCUAQAZAAYJLgwzaQD5AAAVAAEJvBKCiQA4AAABLgAECgkJOgAEAH8iAA==.Karkevon:BAAALgAECgYJDgAAAA==.Karlach:BAABLgAECn8eAAIQAAkJAh0bFwA1AgAQAAkJAh0bFwA1AgAAAA==.Karlachs:BAAALgADCgYJBwAAAA==.Karrla:BAABLgAECn8wAAIFAAkJhxqnGQB7AgAFAAkJhxqnGQB7AgAAAA==.Karumie:BAABLgAECn8nAAIDAAkJZhyXHwBTAgADAAkJZhyXHwBTAgAAAA==.Kashyyk:BAAALgAECgMJAwABLgAECgkJQAATAJkaAA==.Kateera:BAAALgAECgUJCwAAAA==.',
Ke='Keden:BAAALgAECgQJCwAAAA==.Keelivan:BAAALgAECgMJAwAAAA==.Kelivann:BAAALgADCgUJBQAAAA==.Keljaden:BAABLgAECn8YAAIdAAkJwiA3AwACAwAdAAkJwiA3AwACAwABLgAECgkJLAAFAEEiAA==.Kels:BAABLgAECn8sAAIFAAkJQSL5DADdAgAFAAkJQSL5DADdAgAAAA==.',
Kh='Kheyra:BAABLgAECn8mAAIBAAkJzROLEgDJAQABAAkJzROLEgDJAQAAAA==.',
Ki='Kiaona:BAAALgADCgMJAwAAAA==.Kidashia:BAAALgAECgQJBAAAAA==.Kiwisloth:BAAALgAFFAEJAQABLgAFFAkJXwATAFklAA==.',
Ko='Koggs:BAAALgAFFAIJAgAAAA==.Kohnor:BAAALgAECgQJCgAAAA==.Kopi:BAAALgAECgMJBAABLgAECgkJLAALAPchAA==.Kopiccino:BAAALgAECgEJAQABLgAECgkJLAALAPchAA==.Korlatt:BAABLgAECn86AAQFAAkJqR7kEgCsAgAFAAkJQh3kEgCsAgAkAAMJDRxHFwDqAAAiAAMJOhZfVwBgAAAAAA==.Kowalabear:BAABLgAECn8rAAMmAAkJtCExAQD+AgAmAAkJtCExAQD+AgALAAQJPwqaTQBbAAAAAA==.',
Kr='Kryptrix:BAAALgAECgQJBAAAAA==.Krìmzar:BAAALgADCggJCgABLgAECgYJFAAKADgXAA==.',
Kt='Kthanid:BAABLgAECn8aAAIjAAYJohj9DQD6AAAjAAYJohj9DQD6AAAAAA==.',
Ku='Kurston:BAABLgAECn9DAAIZAAkJMRtoEwCwAgAZAAkJMRtoEwCwAgAAAA==.',
Ky='Kymakazie:BAABLgAECn8ZAAIMAAkJrAP4mAAOAQAMAAkJrAP4mAAOAQAAAA==.Kymmuul:BAAALgAECgMJAwAAAA==.',
['Kã']='Kãtniss:BAAALgAECgMJBAAAAA==.',
['Kÿ']='Kÿndrà:BAAALgAECgQJBgAAAA==.',
La='Labella:BAAALgAECgcJEQAAAA==.Lacia:BAAALgAECgQJBAABLgAECgkJPAAKAEgKAA==.Laih:BAABLgAECn8jAAIfAAkJgA+uCAC+AQAfAAkJgA+uCAC+AQAAAA==.Lasturus:BAAALgAECgUJBQABLgAFFAkJKQAXAEwZAA==.Lathelinis:BAAALgAECgcJCgAAAA==.Lauraenital:BAAALgAECgQJBAAAAA==.Layssara:BAAALgADCgMJAwAAAA==.',
Le='Leafbloom:BAAALgAECgEJAQABLgAECggJFgAWAHsYAA==.Letmeout:BAAALgAECgEJAQAAAA==.Lexx:BAAALgAECgIJAgAAAA==.Leyote:BAABLgAECn8/AAIDAAkJDBOiLAAGAgADAAkJDBOiLAAGAgAAAA==.',
Lh='Lhai:BAAALgAECgEJAQABLgAECgkJIwAfAIAPAA==.',
Li='Liady:BAAALgADCgcJDQAAAA==.Lightshop:BAAALgADCgIJAQAAAA==.Liirah:BAAALgAECgQJBQAAAA==.Linora:BAAALgAECgIJAQAAAA==.Listriesa:BAAALgADCgEJAQAAAA==.Livingdead:BAAALgAECgUJBQAAAA==.',
Lo='Lolabunny:BAABLgAECn8UAAMYAAYJZBofNABRAQAYAAUJkxYfNABRAQAWAAQJ+xkLRgAqAQABLgAECggJGAALAOIiAA==.Lorianne:BAAALgAECgcJCQAAAA==.Lousseur:BAAALgADCgEJAgAAAA==.Lowdangle:BAABLgAECn8tAAIFAAkJtheTJQA3AgAFAAkJtheTJQA3AgAAAA==.',
Lu='Lulz:BAAALgAECgkJEwAAAA==.Lumini:BAABLgAECn8eAAMSAAkJ3AbqNABEAQASAAkJ3AbqNABEAQAOAAMJfwPyagA9AAAAAA==.Luminias:BAAALgAECgUJDQAAAA==.Luthein:BAAALgAECgcJEwAAAA==.Luxroy:BAAALgAECgYJEQAAAA==.',
Ly='Lygma:BAABLgAECn8jAAIcAAkJ/g6UZACmAQAcAAkJ/g6UZACmAQAAAA==.Lynniebee:BAABLgAECn8pAAIPAAkJjAwmBQCPAQAPAAkJjAwmBQCPAQAAAA==.',
Ma='Madalyn:BAAALgAECgcJEwAAAA==.Maexna:BAAALgAECgEJAQAAAA==.Magicpie:BAAALgAECgcJBwABLgAECgkJPwAkANIkAA==.Magni:BAAALgAECgQJBQAAAA==.Makklehaney:BAABLgAECn8hAAMbAAkJTg5EEQCfAQAbAAkJTg5EEQCfAQACAAEJ7QFmlQAgAAAAAA==.Mallaah:BAAALgADCgYJCgAAAA==.Malthorin:BAAALgADCgMJAwAAAA==.Maneke:BAAALgADCgkJCQABLgAECgkJLwADAJcVAA==.Marovingian:BAABLgAECn8uAAIhAAkJ4yFYAwBsAwAhAAkJ4yFYAwBsAwAAAA==.Matthad:BAABLgAECn8vAAIDAAkJlxWIJwAiAgADAAkJlxWIJwAiAgAAAA==.Mazìkene:BAACLgAFFH8bAAMaAAUJQQ5nCQDjAAATAAQJ0gfraADzAAAaAAQJzxFnCQDjAAAuAAQKfzIAAxoACQlDH2YAANsCABoACQnDHmYAANsCABMACQk2FgdSAKYBAAAA.',
Mc='Mccone:BAABLgAECn8ZAAIMAAYJnQmtrwDlAAAMAAYJnQmtrwDlAAAAAA==.Mcnastie:BAAALgAECgUJEgAAAA==.Mcsluts:BAABLgAECn8oAAMcAAYJIhHzLQCfAAAcAAYJpw/zLQCfAAAEAAEJaBDqUwApAAAAAA==.',
Me='Megadumb:BAAALgAECgQJBAABLgAFFAkJRgARABYgAA==.Melmirict:BAACLgAFFH8TAAIHAAUJWBJgIAAiAQAHAAUJWBJgIAAiAQAuAAQKfy0AAwcACQkTG90TAAQCAAcACQkTG90TAAQCAB8AAwmAGpQSANkAAAAA.Meneldor:BAAALgAECggJCgAAAA==.Meng:BAAALgADCgYJBgAAAA==.Merciala:BAABLgAECn9DAAIBAAkJdRLfFwCSAQABAAkJdRLfFwCSAQAAAA==.',
Mi='Milyva:BAAALgADCgMJAwAAAA==.Milyyanna:BAAALgAECgQJBgAAAA==.Minaby:BAAALgAECgYJEAABLgAECgkJQwAcACYlAA==.Missmurder:BAAALgAFFAEJAgAAAA==.Mitochondria:BAAALgADCgQJBAAAAA==.',
Mo='Moddoxx:BAABLgAECn9AAAQTAAkJmRruKgAuAgATAAgJSxzuKgAuAgAaAAIJkg6GPAA5AAAgAAIJuw4KPwAyAAAAAA==.Mohawk:BAABLgAECn8YAAIZAAkJIBMvBAD0AQAZAAkJIBMvBAD0AQAAAA==.Mohaxors:BAAALgADCgcJDwAAAA==.Moko:BAAALgAECgEJAgAAAA==.Mokopal:BAAALgADCgMJAwAAAA==.Mokøtrollz:BAABLgAECn8jAAMMAAkJrh9zOAD8AQANAAgJmBnLEgASAgAMAAgJIB5zOAD8AQAAAA==.Molen:BAAALgAECgYJCwAAAA==.Mommyjuice:BAAALgAFFAEJAQABLgAFFAkJRgARABYgAA==.Monkeeh:BAAALgAECgUJBQAAAA==.Monkle:BAABLgAECn9YAAIYAAkJ/CTOAQBYAwAYAAkJ/CTOAQBYAwAAAA==.Monkoku:BAAALgAECgQJBAABLgAFFAYJEwAHAKgXAA==.Moonsii:BAABLgAECn8aAAIZAAkJ9Q1zPQCdAQAZAAkJ9Q1zPQCdAQAAAA==.Mooroth:BAABLgAECn9CAAIeAAkJPSBaBADhAgAeAAkJPSBaBADhAgABLgAFFAIJAgAIAAAAAA==.Morekk:BAAALgAECgEJAQAAAA==.Morozko:BAABLgAECn8eAAImAAgJShqLCAAEAgAmAAgJShqLCAAEAgAAAA==.',
Mu='Muddler:BAABLgAECn9CAAIgAAkJlAOlHADCAAAgAAkJlAOlHADCAAAAAA==.Muscuees:BAAALgADCgEJAQAAAA==.Mush:BAAALgAECgQJBAAAAA==.',
['Mà']='Màggles:BAAALgAECgQJBAAAAA==.',
Na='Nadd:BAABLgAECn84AAIMAAkJKw6pDgCIAQAMAAkJKw6pDgCIAQAAAA==.Naledi:BAABLgAECn8cAAIVAAgJ5Q+/MwBKAQAVAAgJ5Q+/MwBKAQAAAA==.Nancy:BAAALgAECgQJBAAAAA==.Naomas:BAABLgAECn89AAMKAAkJjSGbEgDqAgAKAAkJ9SCbEgDqAgAPAAIJ2R6aDAC1AAAAAA==.Naralyn:BAAALgAECgcJBwAAAA==.Narella:BAABLgAECn8tAAIKAAgJjRQpZQCzAQAKAAgJjRQpZQCzAQAAAA==.Narmaru:BAAALgAECgMJAwAAAA==.',
Ne='Needlepax:BAAALgAECgEJAgAAAA==.Negotiable:BAAALgAECgYJEAAAAA==.Negrido:BAABLgAECn8zAAQTAAkJ+yU2DwDTAgATAAgJwSI2DwDTAgAgAAMJNiWJJAA3AQAaAAEJvx9qMQBaAAAAAA==.Nei:BAABLgAECn9SAAIcAAgJtB9QBgA8AgAcAAgJtB9QBgA8AgAAAA==.Newt:BAAALgADCgUJBQAAAA==.Nezzarector:BAAALgAECgUJCwAAAA==.',
Ni='Nikem:BAABLgAECn87AAMVAAkJbxrjEABWAgAVAAkJbxrjEABWAgABAAEJ0wKQOwAPAAAAAA==.Nimseti:BAAALgAFFAMJBAAAAA==.',
No='Noelle:BAAALgAECgQJCQAAAA==.Nor:BAAALgAECgUJCgAAAA==.Noraelyn:BAABLgAECn8zAAMhAAkJ7xtHDQC9AgAhAAkJ7xtHDQC9AgAcAAQJewSqUAFeAAAAAA==.Norelei:BAAALgAECgUJBwABLgAECgkJJgABAM0TAA==.Noriyuki:BAABLgAECn8uAAIYAAcJDgKihgBMAAAYAAcJDgKihgBMAAAAAA==.Northside:BAAALgADCgQJBAABLgAFFAkJOgAKAPskAA==.Notkorlatt:BAAALgADCgIJAgAAAA==.',
Nu='Nugatory:BAACLgAFFH8RAAQNAAkJ+hDAAgC0AQANAAkJ+hDAAgC0AQAMAAEJFwaBqgBDAAAnAAEJwAH2PAAqAAAuAAQKfxcAAw0ACAlSI1cKAHkCAA0ACAlSI1cKAHkCACcAAwnADI9pAJgAAAEuAAUUBwkQABIAVRQA.Nuudles:BAAALgAECgEJAQAAAA==.',
Ny='Nyxahlia:BAAALgAECgYJEQAAAA==.',
Oa='Oakenia:BAAALgAECgEJAQABLgAECgkJOgAZAO8QAA==.',
Og='Ogkagìsttv:BAAALgAECgYJBwAAAA==.',
Ol='Olderon:BAAALgAECgIJAgAAAA==.Olrong:BAABLgAECn9BAAIiAAkJlxOVFgDTAQAiAAkJlxOVFgDTAQAAAA==.Oluja:BAAALgAECgYJDwAAAA==.',
Om='Omegâ:BAABLgAFFH8HAAIFAAMJBAS4PQB8AAAFAAMJBAS4PQB8AAAAAA==.',
On='Onlypaws:BAAALgAECgYJEgAAAA==.Onuris:BAAALgAECgEJAQAAAA==.',
Op='Opaalite:BAAALgAECgMJAwAAAA==.Opacuslupus:BAAALgAECggJEAAAAA==.Ophel:BAAALgADCgYJBgABLgAECgkJOQAJAIIYAA==.Oppcookies:BAAALgAECgYJDwABLgAECgkJIwAMALkYAA==.Oppressin:BAAALgAECgEJAQABLgAECgkJIwAMALkYAA==.Oppshot:BAABLgAECn8jAAMMAAkJuRiaKgAzAgAMAAkJuRiaKgAzAgAnAAEJUAnlPgAsAAAAAA==.',
Or='Orin:BAAALgAECgEJAQAAAA==.',
Os='Oshìe:BAACLgAFFH8FAAIhAAMJFxE+MwCjAAAhAAMJFxE+MwCjAAAuAAQKfykAAiEACQnbIVAMALgCACEACQnbIVAMALgCAAAA.',
Ov='Overdoom:BAABLgAECn82AAMGAAkJYx7KKgBVAgAGAAkJYx7KKgBVAgALAAUJHAb3QwB/AAAAAA==.Ovscur:BAAALgAFFAEJAgAAAA==.',
Pa='Packapipe:BAAALgADCggJEgAAAA==.Paladinjohn:BAACLgAFFH8pAAIcAAgJJSGMCgAwAgAcAAgJJSGMCgAwAgAuAAQKfysAAhwACQkbJWMBANEDABwACQkbJWMBANEDAAAA.Palykat:BAABLgAECn81AAIcAAkJBAnGFwAfAQAcAAkJBAnGFwAfAQAAAA==.',
Pe='Pennywisé:BAABLgAECn8rAAIGAAkJUyBAGwCjAgAGAAkJUyBAGwCjAgAAAA==.Percentguy:BAAALgAECgMJAwAAAA==.Pessimal:BAAALgADCgEJAQABLgAECgkJIgAGAEMfAA==.',
Ph='Phillygg:BAAALgAECgQJBAAAAA==.Phoeniix:BAABLgAECn8mAAMBAAkJiBeLEwC9AQABAAkJ4haLEwC9AQAVAAQJvRe1UgDcAAAAAA==.',
Pl='Plaguegying:BAABLgAECn8eAAMGAAkJnA+CZgCaAQAGAAgJ8w+CZgCaAQALAAEJOQ3gWQA6AAABLgAECgkJRAAWAIUdAA==.Ploofee:BAAALgAECgkJEgAAAA==.',
Po='Porker:BAAALgADCgEJAQAAAA==.',
Pr='Prog:BAAALgAECgEJAQAAAA==.Progresz:BAABLgAECn8WAAIKAAkJwRBLYAC/AQAKAAkJwRBLYAC/AQAAAA==.',
Ps='Psichosa:BAAALgAECggJDgAAAA==.Psychosis:BAAALgADCgQJAwAAAA==.',
Pu='Purebread:BAAALgADCgQJBAAAAA==.',
Py='Pykel:BAABLgAECn8uAAIVAAkJgw0DDAD9AAAVAAkJgw0DDAD9AAAAAA==.Pyrexea:BAAALgADCgYJBgAAAA==.Pyrivia:BAAALgAECgEJAgABLgAECgUJCgAIAAAAAA==.',
Qa='Qaren:BAABLgAECn8aAAIcAAYJrgn4PwBkAAAcAAYJrgn4PwBkAAAAAA==.',
Qi='Qikeyy:BAAALgAECgEJAQAAAA==.',
Qu='Quadraxis:BAAALgADCgcJCQAAAA==.Questionable:BAAALgADCgUJBQAAAA==.',
Ra='Racerx:BAAALgAFFAMJAgAAAA==.Raethe:BAAALgAECgQJBAAAAA==.Raishun:BAAALgAECgMJAwAAAA==.Raizo:BAAALgADCgEJAQAAAA==.Rajak:BAAALgADCgEJAQAAAA==.Rake:BAABLgAECn80AAQoAAkJVSCbBgB8AgAoAAkJFB+bBgB8AgABAAEJQh1IYABPAAAVAAIJ6wcegABIAAAAAA==.Raminthórn:BAAALgADCgIJAgAAAA==.Rannï:BAACLgAFFH8GAAIKAAMJyAp7jQC+AAAKAAMJyAp7jQC+AAAuAAQKfxUAAgoACAkiFPxeAMMBAAoACAkiFPxeAMMBAAEuAAUUBgkdABoALRcA.Raskreia:BAABLgAFFH8GAAIGAAMJRyNIKgAqAQAGAAMJRyNIKgAqAQABLgAFFAcJHgAKADIfAA==.Ratabi:BAAALgADCgIJAgAAAA==.Ravana:BAAALgADCggJCAAAAA==.Ravna:BAABLgAECn8iAAMCAAgJlxY7BQC1AQACAAgJlxY7BQC1AQADAAUJqwp1LgBSAAABLgAECgkJOwAVADYcAA==.Rawk:BAAALgAECgYJEQAAAA==.Rawrski:BAAALgADCgEJAgABLgAECgkJNgADAH0OAA==.',
Re='Reavert:BAAALgADCgYJBgAAAA==.Reeven:BAAALgAECgkJNgAAAQ==.Reshii:BAAALgAECgEJAQABLgAECgkJQAATAJkaAA==.Rexmortis:BAAALgAECgkJAgAAAA==.',
Rh='Rhaistlin:BAAALgADCgMJAwAAAA==.Rhcpmage:BAACLgAFFH8NAAIKAAQJUSL0RwBUAQAKAAQJUSL0RwBUAQAuAAQKfxwAAgoACQmKIVsWANMCAAoACQmKIVsWANMCAAEuAAUUCAk1AAoAkB8A.Rhetegast:BAABLgAECn8oAAIEAAkJrRPHDwDIAQAEAAkJrRPHDwDIAQAAAA==.Rhymaek:BAAALgAECgYJCQABLgAFFAIJCAAhAOAYAA==.Rhyss:BAAALgAECgQJBAAAAA==.',
Ri='Rike:BAABLgAECn9AAAMcAAkJ+iJjHwCLAgAcAAkJ5SFjHwCLAgAEAAYJlB4DEQC0AQAAAA==.Rinde:BAAALgADCgkJCQAAAA==.Riobla:BAAALgAECgQJBwABLgAECgkJPAAKAEgKAA==.',
Ro='Roflbackpack:BAAALgAECgkJBwAAAA==.Roflbalanced:BAAALgAECgQJCAAAAA==.Roflgotnerfd:BAAALgADCgMJAwABLgAECgkJBwAIAAAAAA==.Roflhazotime:BAABLgAECn8nAAIFAAkJVyOWCQD/AgAFAAkJVyOWCQD/AgAAAA==.Roland:BAABLgAECn81AAMZAAkJyhOgMADfAQAZAAkJyhOgMADfAQAVAAYJAQ15TQDWAAAAAA==.Rolandin:BAABLgAECn9AAAIhAAkJ1RfYEgB6AgAhAAkJ1RfYEgB6AgAAAA==.Rollaen:BAAALgADCgYJDAAAAA==.Rollan:BAAALgAECgUJDAAAAA==.Rook:BAABLgAFFH8JAAIHAAQJfxRoGwA+AQAHAAQJfxRoGwA+AQABLgAFFAgJLAADAAkgAA==.Roscjou:BAABLgAECn8YAAICAAcJsQT3YADCAAACAAcJsQT3YADCAAAAAA==.Ross:BAAALgAECgYJDwAAAA==.',
Ru='Rubisco:BAAALgAECgYJCwAAAA==.Ruh:BAAALgAECgMJBgABLgAECgkJQAATAJkaAA==.Rukraga:BAAALgAFFAEJAQAAAA==.',
Ry='Rylagosa:BAABLgAECn85AAMJAAkJghiJDwDTAQAJAAcJNxiJDwDTAQARAAkJZRIEJgCwAQAAAA==.Rynehardt:BAAALgADCgcJBwAAAA==.Ryuji:BAAALgAECgEJAQAAAA==.Ryzesmidge:BAABLgAECn8XAAIKAAkJGRHYWQDQAQAKAAkJGRHYWQDQAQAAAA==.',
['Rê']='Rêdrum:BAABLgAFFH8IAAIGAAMJ3gslqwDIAAAGAAMJ3gslqwDIAAABLgAFFAUJGwAaAEEOAA==.',
Sa='Sabithia:BAAALgAECgEJAQAAAA==.Sahathiel:BAAALgAFFAIJAwAAAA==.Salandria:BAAALgAECgYJEAAAAA==.Salandriath:BAAALgAECgYJCwAAAA==.Sange:BAAALgAECgcJDQAAAA==.Sarionian:BAABLgAECn86AAIZAAkJ7xDmMgDTAQAZAAkJ7xDmMgDTAQAAAA==.Sarvin:BAAALgADCgcJBwABLgAECgkJKwADAEscAA==.Sarvinblue:BAABLgAECn8rAAMDAAkJSxxAFgCYAgADAAkJSxxAFgCYAgACAAMJLQ8SagCbAAAAAA==.Satrathen:BAAALgADCgYJBgAAAA==.Saucestash:BAAALgAECgIJAgAAAA==.Sauronic:BAAALgAECgYJCgAAAA==.',
Sc='Scopolamine:BAAALgAECgYJBQAAAA==.',
Se='Searchlights:BAAALgAECgYJEQAAAA==.Seshu:BAAALgAECgEJAQAAAA==.Sevrin:BAAALgADCgEJAQAAAA==.',
Sh='Shaeko:BAAALgAECgUJCgAAAA==.Shambúlance:BAAALgAECgMJAwAAAA==.Shanaynay:BAAALgAECgQJBAAAAA==.Shanir:BAAALgAFFAEJAQAAAA==.Shanksie:BAABLgAECn8bAAIfAAcJkAaDEwDwAAAfAAcJkAaDEwDwAAAAAA==.Shazlulu:BAABLgAECn8pAAIDAAkJ1RgaCADKAQADAAkJ1RgaCADKAQAAAA==.Shedoa:BAAALgAECgYJBgAAAA==.Shiftywelt:BAAALgADCggJDAAAAA==.Shilajit:BAAALgAECgUJCwAAAA==.Shinmothee:BAABLgAECn8iAAIPAAkJkApWBgBeAQAPAAkJkApWBgBeAQAAAA==.Shinsura:BAAALgADCgcJEAAAAA==.Shtamman:BAAALgADCgUJBQAAAA==.',
Si='Silvantis:BAAALgADCgEJAQAAAA==.Siobhán:BAABLgAECn8tAAIHAAkJnx8LDwA7AgAHAAkJnx8LDwA7AgAAAA==.',
Sk='Skandle:BAAALgADCgMJAwAAAA==.',
Sl='Sleepypanda:BAABLgAECn8jAAIhAAkJtxnWFQBdAgAhAAkJtxnWFQBdAgAAAA==.Sloe:BAABLgAECn87AAMOAAkJPxyFDQCOAgAOAAkJPxyFDQCOAgASAAEJrAXjlAAlAAAAAA==.',
Sm='Smokalot:BAAALgADCgEJAQAAAA==.Smokehunter:BAAALgAECgYJCwAAAA==.',
Sn='Sneakez:BAAALgAFFAEJAQABLgAFFAYJEwAHAKgXAA==.',
So='Somebody:BAAALgAECgQJBQAAAA==.Soulitude:BAAALgAECgEJAQAAAA==.Southerngal:BAAALgADCgQJBQAAAA==.',
Sp='Speedbeefbal:BAAALgAECgYJDQAAAA==.Speeddwrfbal:BAAALgAECgYJBgAAAA==.Speedkweef:BAABLgAFFH8HAAISAAMJWwK0GwB3AAASAAMJWwK0GwB3AAAAAA==.Speedmeat:BAABLgAECn8sAAMDAAkJ8gi1ZAAtAQADAAgJxAi1ZAAtAQACAAgJ8wvYDQDrAAAAAA==.Spinny:BAAALgAECgYJBgAAAA==.Sporkulous:BAACLgAFFH8IAAIMAAMJbAd4TQCKAAAMAAMJbAd4TQCKAAAuAAQKfy8AAwwACAl/E1BKAMIBAAwACAl/E1BKAMIBACcAAQkXARRIABAAAAAA.',
Sq='Squal:BAABLgAECn8+AAMcAAkJNSGuEADhAgAcAAkJeyCuEADhAgAEAAcJWBp4BQA+AQAAAA==.Squiggle:BAABLgAECn89AAIEAAkJjSJMAgASAwAEAAkJjSJMAgASAwAAAA==.',
St='Stalkêr:BAAALgADCgIJAgAAAA==.Steevii:BAAALgAECgQJBAAAAA==.Stewie:BAAALgAECgEJAgAAAA==.Stewy:BAAALgAECgYJCAAAAA==.Stickybunz:BAABLgAECn8ZAAIQAAgJURUDJgDIAQAQAAgJURUDJgDIAQABLgAFFAQJDwASAHAFAA==.Striker:BAAALgAECgQJDwABLgAECgkJQAAcAPoiAA==.Strombone:BAAALgADCgEJAgABLgAECgcJEAAIAAAAAA==.Stunseed:BAABLgAECn8rAAIBAAkJ1hhFCwAuAgABAAkJ1hhFCwAuAgAAAA==.',
Su='Sumo:BAAALgAECgEJAQAAAA==.Sungjinwu:BAAALgAECgUJBQAAAA==.Sunnmage:BAAALgAECgcJCAAAAA==.Sunshíne:BAABLgAECn8vAAMEAAkJkhF+AwCeAQAEAAkJkhF+AwCeAQAcAAgJQQfKsAAeAQAAAA==.Surf:BAABLgAECn8XAAIFAAcJWRxlNAD1AQAFAAcJWRxlNAD1AQABLgAFFAEJAwAIAAAAAA==.',
Sw='Sweetandsour:BAAALgADCgYJBgAAAA==.Sweetbunz:BAACLgAFFH8PAAMSAAQJcAW1JQDLAAASAAQJcAW1JQDLAAAOAAQJAAnwHQDJAAAuAAQKfzoAAxIACQnHFpYXAAsCABIACQnHFpYXAAsCAA4ACAlYDjMxAEgBAAAA.Swegin:BAAALgAECgIJAgABLgAECgQJCwAIAAAAAA==.',
Sx='Sxes:BAAALgAECgYJDAAAAA==.',
Sy='Synaminaphyn:BAAALgAECgEJAQAAAA==.Syver:BAABLgAECn8pAAMGAAkJ2BkHRwDtAQAGAAgJGxsHRwDtAQALAAEJCRG+WAA9AAAAAA==.',
['Sì']='Sìrcândymân:BAAALgAECgQJBAABLgAECgYJFgABAFYQAA==.Sìrfuzywuzy:BAABLgAECn8WAAMBAAUJVhCXDwCOAAAoAAQJTw2dKADLAAABAAUJ6wqXDwCOAAAAAA==.',
['Sí']='Sírlancealot:BAAALgAECgEJAgABLgAECgYJFgABAFYQAA==.',
Ta='Taisty:BAAALgADCgQJBAAAAA==.Takers:BAAALgAECgYJCgAAAA==.Tanagra:BAAALgAECgEJAQABLgAECgkJQAATAJkaAA==.Taniss:BAABLgAECn8pAAIlAAkJlQioCwBcAQAlAAkJlQioCwBcAQAAAA==.Tanner:BAABLgAECn8dAAMnAAgJDgnESgAnAQAnAAgJwQfESgAnAQAMAAIJoBF5ogCHAAAAAA==.Tarnaby:BAAALgAFFAIJAgAAAA==.',
Te='Teatim:BAAALgADCgUJBQAAAA==.Teboe:BAAALgAECgYJBwAAAA==.Tedman:BAABLgAECn8vAAMCAAkJjRlTEwBTAgACAAkJjRlTEwBTAgADAAMJmgdWjwBaAAAAAA==.Tekki:BAAALgADCgEJAQAAAA==.Temel:BAABLgAECn82AAMDAAkJfQ5DTgB4AQADAAgJtwxDTgB4AQACAAkJUw07NABqAQAAAA==.Tenelum:BAAALgAECgQJEgABLgAECgkJNgADAH0OAA==.Testoecles:BAAALgAECgMJBQABLgAECgYJBwAIAAAAAA==.',
Th='Thadrack:BAABLgAECn88AAIKAAkJSAq2fQB8AQAKAAkJSAq2fQB8AQAAAA==.Thaine:BAAALgADCgEJAQABLgAECgcJDQAIAAAAAA==.Thalonstin:BAAALgAECgQJCgAAAA==.Thanee:BAACLgAFFH8IAAIOAAUJFRM8FAAjAQAOAAUJFRM8FAAjAQAuAAQKfyYAAw4ACQmAI18AAJMDAA4ACQmAI18AAJMDACMABglREoIjAHcBAAEuAAQKBwkNAAgAAAAA.Thanevoker:BAAALgAECgcJDQAAAA==.Theodrid:BAACLgAFFH8TAAIcAAgJKRHlJQBxAQAcAAgJKRHlJQBxAQAuAAQKfyMAAhwACQmhHjAkAJcCABwACQmhHjAkAJcCAAAA.Thoreum:BAAALgAECgEJAgAAAA==.Thraxia:BAABLgAECn8XAAITAAgJWAUGlgAsAQATAAgJWAUGlgAsAQAAAA==.Thrombin:BAAALgAECgMJAwAAAA==.',
Ti='Tigertigress:BAAALgAECgQJBAAAAA==.Tinkíe:BAABLgAECn8iAAQYAAkJ9Ry3GQDjAQAYAAgJ0By3GQDjAQAWAAQJQRmWTgAJAQAXAAUJ2QxNaQDbAAAAAA==.Tirzahdozier:BAACLgAFFH8IAAIhAAIJ4BiJGgCFAAAhAAIJ4BiJGgCFAAAuAAQKfx4AAyEACQkCFF0HAGsBACEACQkCFF0HAGsBABwAAQlfAn3QARgAAAAA.Tiwohnne:BAAALgAECgYJDQAAAA==.',
Tl='Tla:BAAALgAECgQJCgAAAA==.',
To='Tooey:BAAALgAECgEJAQAAAA==.',
Tr='Treat:BAABLgAECn9DAAISAAkJfySLAgBAAwASAAkJfySLAgBAAwAAAA==.Tremblement:BAAALgADCgMJAwAAAA==.Trickortreat:BAAALgADCgMJAwAAAA==.Trippyshock:BAABLgAFFH8SAAICAAUJSBotGwBBAQACAAUJSBotGwBBAQABLgAFFAkJXwATAFklAA==.Tristitia:BAABLgAECn8vAAMGAAkJ+BYgMQA6AgAGAAkJ+BYgMQA6AgALAAIJGAYxWQA8AAAAAA==.Trolidan:BAAALgAECgEJAQAAAA==.',
Ts='Tsaorkrad:BAAALgAECgEJAQAAAA==.',
Tu='Tuathwa:BAAALgAECgEJAQABLgAFFAIJCAAhAOAYAA==.Tubbs:BAABLgAECn8ZAAIGAAkJAxw4LQBLAgAGAAkJAxw4LQBLAgAAAA==.Turkeltin:BAAALgAECgYJEAABLgAFFAQJCgAKAF0ZAA==.',
Tw='Twiggle:BAAALgAECgQJBAABLgAFFAIJCAAhAOAYAA==.',
Ty='Tyberogh:BAAALgAECgEJAQAAAA==.Tyche:BAABLgAECn8cAAMDAAYJXhDEHACqAAADAAYJXhDEHACqAAACAAEJ2gHYwwAYAAAAAA==.Tylius:BAAALgAECgcJBwAAAA==.Tyrdrin:BAAALgAECgEJAQAAAA==.Tyrinara:BAAALgADCgYJBgAAAA==.Tysbich:BAAALgAECgQJCAABLgAECgkJLgAhAOMhAA==.',
Ui='Uiewedaoez:BAABLgAECn80AAIZAAkJWST7AgCZAwAZAAkJWST7AgCZAwAAAA==.',
Um='Umakkel:BAAALgAECgYJDgAAAA==.Umiko:BAAALgADCgUJBQAAAA==.',
Ur='Urd:BAABLgAECn8hAAIGAAkJ9BAmWgC4AQAGAAkJ9BAmWgC4AQAAAA==.',
Va='Vaelrelyn:BAABLgAECn8UAAMgAAYJJhD1HgBZAQAgAAYJJhD1HgBZAQATAAIJ4gHuLwEhAAAAAA==.Vains:BAACLgAFFH8SAAIcAAUJkRzxOQA4AQAcAAUJkRzxOQA4AQAuAAQKfy0AAhwACQkzIX8FAFwCABwACQkzIX8FAFwCAAAA.Valoras:BAAALgADCgEJAQAAAA==.Valrith:BAABLgAECn8YAAIcAAcJIwc2zwD0AAAcAAcJIwc2zwD0AAAAAA==.Vardis:BAABLgAECn8uAAIKAAkJMh+SKgBwAgAKAAkJMh+SKgBwAgAAAA==.',
Ve='Velinami:BAAALgAECgIJAwAAAA==.Venato:BAAALgADCgEJBAABLgAECgkJNgADAH0OAA==.Vendettuh:BAAALgADCgEJAQAAAA==.Verazene:BAABLgAFFH8IAAIaAAMJrx3pBwD8AAAaAAMJrx3pBwD8AAAAAA==.Verenthirl:BAAALgAECgUJBAAAAA==.Veronica:BAABLgAECn88AAIKAAkJ/h6GFQDYAgAKAAkJ/h6GFQDYAgAAAA==.Verren:BAABLgAECn8rAAIBAAkJFBrYCQBMAgABAAkJFBrYCQBMAgAAAA==.Versutia:BAAALgAECgIJAgAAAA==.',
Vi='Violenta:BAAALgAECgUJBQAAAA==.Virse:BAAALgAECgUJCQAAAA==.Virtigo:BAAALgADCgQJCAAAAA==.Vixie:BAAALgAECgcJBwAAAA==.',
Vy='Vye:BAAALgAECgEJAQAAAA==.Vyerith:BAABLgAECn8kAAITAAkJjhzwKAA4AgATAAkJjhzwKAA4AgAAAA==.Vyrridyl:BAAALgAECgEJAQAAAA==.',
Wa='Warsynth:BAAALgAECgEJAQABLgAECgkJJgAPAOYgAA==.',
We='Weltamus:BAABLgAECn8rAAMLAAkJABhJHAB4AQAGAAgJyg83dQB5AQALAAQJ9yBJHAB4AQAAAA==.Weltasaur:BAABLgAECn8fAAIBAAYJBhixHgBYAQABAAYJBhixHgBYAQAAAA==.Weltazar:BAABLgAECn82AAICAAkJrxcsJADFAQACAAkJrxcsJADFAQAAAA==.Weltt:BAAALgAECgEJAQAAAA==.Westside:BAACLgAFFH86AAMKAAkJ+yQWAgArAwAKAAkJxyQWAgArAwAPAAcJUh5nAAAFAgAuAAQKfyMAAgoACQnVJmcBAIsDAAoACQnVJmcBAIsDAAAA.',
Wi='Wickedfluff:BAAALgADCgYJBgAAAA==.Wickët:BAAALgAECgQJCAABLgAECgkJIAATAGsjAA==.Wildtiger:BAABLgAECn8zAAIoAAkJ5hgeCABQAgAoAAkJ5hgeCABQAgAAAA==.',
Wo='Wolfslied:BAAALgAECgYJCAAAAA==.',
Wr='Wrecken:BAAALgADCgUJBQAAAA==.',
Wu='Wulfenhide:BAABLgAECn8zAAQfAAkJ8B5qAgC1AgAfAAkJ8B5qAgC1AgAHAAMJoAfkUACkAAAlAAEJeAVgDwArAAAAAA==.',
Wy='Wyzsky:BAAALgAECgEJBQABLgAECgkJNgADAH0OAA==.',
Xa='Xal:BAAALgADCgEJAQABLgAECgMJBQAIAAAAAA==.Xalreth:BAABLgAECn8hAAIFAAkJPg6YXAByAQAFAAkJPg6YXAByAQAAAA==.Xaviana:BAAALgAECgkJKgAAAQ==.',
Xc='Xcedrin:BAABLgAECn8fAAMSAAkJOQgiOwAmAQASAAgJOAciOwAmAQAOAAMJXwWBcQBhAAAAAA==.',
Xi='Xiangzhu:BAAALgAECgEJAQABLgAECgkJLwAEAIMeAA==.',
Ya='Yastinfect:BAABLgAECn8eAAIFAAkJ0BgPLwBAAgAFAAkJ0BgPLwBAAgAAAA==.Yastypoo:BAAALgAECgEJAQAAAA==.',
Yu='Yurika:BAEBLgAECn8xAAIhAAkJJibZBwAOAwAhAAkJJibZBwAOAwAAAA==.Yushi:BAABLgAECn8tAAIHAAkJlx/zCgB1AgAHAAkJlx/zCgB1AgAAAA==.',
Yv='Yväinne:BAAALgAECgIJAgAAAA==.',
Za='Zaketh:BAAALgADCgQJBAAAAA==.Zareen:BAAALgADCgkJCQAAAA==.Zaru:BAAALgADCgcJGQAAAA==.Zayfall:BAAALgAECgYJEwAAAA==.',
Ze='Zelenor:BAABLgAECn8nAAQGAAkJfxTJNgAkAgAGAAkJfxTJNgAkAgAmAAYJKQV3KQCIAAALAAQJYQOLSwBhAAAAAA==.Zenweaver:BAACLgAFFH8RAAIWAAMJVSS1HgA2AQAWAAMJVSS1HgA2AQAuAAQKfx8AAhYACQlqIlUEAEcDABYACQlqIlUEAEcDAAAA.',
Zi='Ziur:BAAALgADCgEJAQAAAA==.',
Zo='Zonde:BAAALgAECgEJAQAAAA==.',
Zu='Zud:BAABLgAECn8hAAIGAAkJRiGtEwDSAgAGAAkJRiGtEwDSAgAAAA==.',
['Zö']='Zödd:BAAALgAECgEJAQAAAA==.',
['Öå']='Öåken:BAAALgAECgEJAQABLgAECgkJOgAZAO8QAA==.',
['Øt']='Øtherside:BAAALgAECgEJAQAAAA==.',
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
