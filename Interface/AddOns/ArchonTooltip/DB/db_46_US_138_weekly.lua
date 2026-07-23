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

local lookup = {'Druid-Guardian','Shaman-Elemental','Shaman-Restoration','Paladin-Protection','DemonHunter-Devourer','DeathKnight-Unholy','Rogue-Subtlety','Unknown-Unknown','Evoker-Preservation','Mage-Frost','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Survival','Priest-Holy','Mage-Arcane','Warrior-Fury','Evoker-Augmentation','Priest-Shadow','Warlock-Demonology','Evoker-Devastation','Druid-Balance','Monk-Brewmaster','Monk-Mistweaver','Monk-Windwalker','Druid-Restoration','Warlock-Affliction','Shaman-Enhancement','Paladin-Retribution','Warrior-Arms','Hunter-Marksmanship','Warrior-Protection','Rogue-Assassination','Warlock-Destruction','Paladin-Holy','DemonHunter-Havoc','Priest-Discipline','DemonHunter-Vengeance','Rogue-Outlaw','DeathKnight-Frost','Druid-Feral',}
local provider = {region='US',realm='KulTiras',name='US',type='weekly',zone=46,date='2026-07-19',data={Aa='Aaissis:BAAALgAECgQJBAABLgAECgkJKwABABQaAA==.Aarix:BAABLgAECn8UAAICAAkJQRESKQCnAQACAAkJQRESKQCnAQAAAA==.',
Ae='Aedrelyn:BAAALgAECgcJDQAAAA==.Aegia:BAABLgAECn8ZAAMDAAcJrxCdVgBcAQADAAcJrxCdVgBcAQACAAMJTQGHgABFAAAAAA==.Aegrim:BAAALgAECgEJAQABLgAECgkJLwAEAIMeAA==.Aendillan:BAABLgAECn8UAAIFAAcJVhrHWwCOAQAFAAcJVhrHWwCOAQAAAA==.Aewrynn:BAAALgAECgIJAgAAAA==.',
Af='Affonasei:BAABLgAECn86AAIGAAkJvA/cXACxAQAGAAkJvA/cXACxAQAAAA==.',
Ai='Aicaramba:BAAALgAECgYJCgAAAA==.Aileen:BAAALgAFFAIJAgAAAA==.',
Ak='Akashi:BAAALgAFFAIJAwABLgAFFAUJFgAHAM4cAA==.',
Al='Alacrodie:BAAALgAECgQJCAAAAA==.Alladorn:BAAALgADCgEJAQAAAA==.Allarii:BAAALgAECgUJBQABLgAECgUJBQAIAAAAAA==.Allynoon:BAAALgADCgMJAwAAAA==.Alurynath:BAAALgAECgEJAQABLgAECgkJLwAEAIMeAA==.',
An='Anahla:BAAALgAECgUJBQABLgAECgkJOQAJAIIYAA==.Ancbow:BAAALgADCgUJBQAAAA==.Angrydisc:BAAALgADCgUJBQABLgAECgkJPAAKAEgKAA==.Angrytotems:BAAALgAECgYJBwABLgAECgkJPAAKAEgKAA==.Angyll:BAAALgADCgUJAQAAAA==.Annaborshen:BAAALgADCgcJCgAAAA==.Antoccino:BAABLgAECn8sAAILAAkJ9yH1AwD6AgALAAkJ9yH1AwD6AgAAAA==.',
Ar='Aragorno:BAABLgAECn8sAAMMAAkJrBdVJwBCAgAMAAkJrBdVJwBCAgANAAQJRAZgQgC6AAAAAA==.Araziel:BAAALgAECgMJBAAAAA==.Arcturen:BAABLgAECn85AAIMAAkJYBxeBABSAgAMAAkJYBxeBABSAgAAAA==.Arenthal:BAAALgAECgUJCgABLgAFFAQJCAAKAEgUAA==.Arill:BAAALgADCgYJBgAAAA==.Arkulas:BAAALgAECgYJBwAAAA==.Artemisha:BAAALgADCgEJAQABLgAECgMJAwAIAAAAAA==.Arturaan:BAAALgAECgEJAQAAAA==.',
As='Ashalana:BAAALgAECgcJEAAAAA==.Asheby:BAAALgAECgIJAwABLgAECgkJOwAOAD8cAA==.Ashiera:BAABLgAECn8yAAMKAAkJ+gNSqgAqAQAKAAkJ+gNSqgAqAQAPAAEJ7AHwIgATAAAAAA==.',
At='Atomic:BAABLgAECn8aAAIQAAkJrQcdCQAPAQAQAAkJrQcdCQAPAQAAAA==.',
Au='Aurorée:BAAALgAECgEJAQAAAA==.Ausuna:BAAALgAECgYJBwAAAA==.',
Av='Avelai:BAAALgADCgkJEgAAAA==.',
Aw='Awhiteboy:BAAALgAECgcJDgABLgAECgkJLQAHAJ8fAA==.',
Az='Azeral:BAAALgADCgYJBgAAAA==.Azylstrid:BAAALgAECgQJBAAAAA==.',
Ba='Babyshred:BAAALgAECgYJCAAAAA==.Badonka:BAAALgAECgQJBAABLgAECgkJSAARAG8eAA==.Bahaana:BAAALgAECgUJBgAAAA==.Balentine:BAACLgAFFH8HAAIOAAMJKxKXDwCgAAAOAAMJKxKXDwCgAAAuAAQKfx0AAw4ACAkxE+o6AAsBAA4ABwkCE+o6AAsBABIABQnHA/tHAMEAAAAA.Bananasloth:BAAALgAECgcJEQABLgAFFAkJVwATAEYkAA==.Banjali:BAAALgADCgMJAwAAAA==.Banostraza:BAABLgAECn9IAAMRAAkJbx6/CQC8AgARAAkJyB2/CQC8AgAUAAEJ2RQxIgBFAAAAAA==.Baspir:BAABLgAECn8pAAIVAAkJNxbAJAClAQAVAAkJNxbAJAClAQAAAA==.',
Be='Beeboop:BAAALgAECgUJCAAAAA==.Belly:BAAALgAECgIJAgABLgAECgkJLQAHAJ8fAA==.Belrae:BAACLgAFFH8IAAIFAAIJ0QamiABxAAAFAAIJ0QamiABxAAAuAAQKfzYAAgUACQlSF78lADcCAAUACQlSF78lADcCAAAA.Belrinthe:BAABLgAFFH8GAAIWAAMJ3xaIDgDSAAAWAAMJ3xaIDgDSAAAAAA==.Berenzen:BAAALgAECgEJAgAAAA==.Bethaliz:BAAALgAECgIJAgAAAA==.Bezieck:BAABLgAECn9CAAISAAgJjRYEBQByAQASAAgJjRYEBQByAQAAAA==.',
Bi='Bigdawg:BAAALgAECggJEAAAAA==.Bigdeborah:BAAALgAECgUJBQAAAA==.Bigfolks:BAAALgAECgIJAgAAAA==.Bigollock:BAAALgAECgEJBAAAAA==.Billyhikz:BAABLgAECn8oAAIKAAkJ8w3oYAC+AQAKAAkJ8w3oYAC+AQAAAA==.Birdbrain:BAAALgAFFAIJAwAAAA==.Biru:BAAALgAFFAIJAgABLgAFFAQJCQAOAM8QAA==.',
Bl='Bloodarrow:BAABLgAECn8VAAIMAAYJgBg5eQBNAQAMAAYJgBg5eQBNAQAAAA==.',
Bo='Bobino:BAAALgADCgEJAQAAAA==.Bockchi:BAABLgAECn8YAAMXAAYJ5RcHOgCJAQAXAAYJ5RcHOgCJAQAYAAEJaRX3lAA7AAAAAA==.Bonegavel:BAAALgAECgUJBwAAAA==.Bookhuntress:BAABLgAECn8jAAQZAAcJ3RtAJgAfAgAZAAcJ3RtAJgAfAgAVAAYJ5xcsNABIAQABAAEJnAwahAAcAAAAAA==.Bordrann:BAAALgAECgMJBAAAAA==.Bosyoh:BAAALgAECgIJAgAAAA==.',
Br='Branaxe:BAAALgAECgkJEgAAAA==.Brandisheer:BAAALgAECgYJCAAAAA==.Branpaw:BAAALgAECgIJAwABLgAECgkJEgAIAAAAAA==.Branthor:BAAALgADCgIJAgAAAA==.Brewdeez:BAACLgAFFH8JAAIYAAUJbAm3HwDaAAAYAAUJbAm3HwDaAAAuAAQKfzQAAhYACQktH7UIAKcCABYACQktH7UIAKcCAAAA.Brewzer:BAACLgAFFH8SAAIXAAQJuAvBNwDJAAAXAAQJuAvBNwDJAAAuAAQKfyUAAxcACAmEExs3AJcBABcACAmEExs3AJcBABgABQmtDBBYAK8AAAAA.Brick:BAAALgAECgYJCgAAAA==.Brint:BAABLgAECn8fAAMTAAgJNg+GawBlAQATAAgJMw+GawBlAQAaAAEJshNcOQBCAAAAAA==.Brok:BAABLgAECn8UAAIbAAgJPxqRCQAjAgAbAAgJPxqRCQAjAgAAAA==.Brokenhorn:BAAALgADCgYJGAAAAA==.Bronad:BAACLgAFFH86AAIKAAYJhiUuCwAtAgAKAAYJhiUuCwAtAgAuAAQKfyIAAgoACAkXJdEjAOMCAAoACAkXJdEjAOMCAAAA.Bronst:BAAALgAECgEJAwABLgAECgkJMQACAOYYAA==.Broomhandle:BAABLgAECn85AAIcAAkJJSVZBgA+AwAcAAkJJSVZBgA+AwAAAA==.',
Bu='Bubbletea:BAAALgAECgYJDAAAAA==.Bumbushka:BAACLgAFFH8eAAIQAAYJZh/JCgC2AQAQAAYJZh/JCgC2AQAuAAQKfxkAAxAABwl/IyskADUCABAABwl/IyskADUCAB0AAgnfGNcrAJUAAAEuAAUUBgkeABAAZh8A.Burinn:BAAALgAECgcJCgABLgAECgkJSAAOAFkPAA==.',
Ca='Caeus:BAABLgAECn8xAAIGAAkJnyRSBwA7AwAGAAkJnyRSBwA7AwAAAA==.Cam:BAABLgAECn8xAAIKAAkJlCXtCwAZAwAKAAkJlCXtCwAZAwAAAA==.Capriestson:BAAALgADCgkJCQABLgAECgYJEgAIAAAAAA==.Cardo:BAAALgADCgUJBQABLgAFFAgJFwAeAGgZAA==.Care:BAABLgAECn8ZAAIKAAkJjAwciADBAQAKAAkJjAwciADBAQAAAA==.Carolinabele:BAAALgAECgcJBQAAAA==.Carrowend:BAAALgAECgMJAwAAAA==.Cauud:BAABLgAECn8gAAIfAAYJ8RP4IwARAQAfAAYJ8RP4IwARAQAAAA==.',
Cb='Cbd:BAAALgADCgcJCAAAAA==.',
Ch='Chacruna:BAAALgAECgQJBAAAAA==.Charmed:BAAALgAECgUJBgAAAA==.Cheesús:BAAALgAECggJDAAAAA==.Chelan:BAABLgAECn9IAAMOAAkJWQ//IgCrAQAOAAkJWQ//IgCrAQASAAkJjgW7OgAoAQAAAA==.Chiji:BAAALgAECgYJBQAAAA==.Chilljaeden:BAAALgAECgUJDQAAAA==.Chizuko:BAAALgADCgMJAwAAAA==.Chuntspeed:BAAALgADCgYJHQAAAA==.Chuye:BAAALgAFFAEJAQABLgAFFAQJCQAOAM8QAA==.',
Ci='Cigs:BAAALgAECgYJBgABLgAFFAkJMgAKAHskAA==.Cindyloowhoo:BAAALgADCgMJAwAAAA==.Cinnabunz:BAABLgAECn8hAAITAAgJLQzqFACnAAATAAgJLQzqFACnAAAAAA==.Citorcen:BAAALgAECgEJAQAAAA==.',
Cl='Clambulance:BAAALgAFFAMJAwAAAA==.Cleaväge:BAAALgADCgYJBgAAAA==.Cleurisse:BAABLgAFFH8YAAILAAUJ5heSGAAjAQALAAUJ5heSGAAjAQAAAA==.Cloudlol:BAAALgAECgQJBgAAAA==.Clueless:BAAALgADCgMJAwAAAA==.',
Cn='Cnova:BAAALgAECgUJDgABLgAECgkJOwAcAHsgAA==.',
Co='Codythedead:BAABLgAFFH8GAAIGAAIJ7RQd3ACHAAAGAAIJ7RQd3ACHAAAAAA==.Compadre:BAABLgAECn8XAAQYAAgJPh7NHQDrAQAYAAcJ0RrNHQDrAQAWAAQJUiAiRAAyAQAXAAYJWxE4RADMAAAAAA==.Contekst:BAABLgAECn8iAAMZAAgJQA8XWQAtAQAZAAgJQA8XWQAtAQAVAAcJxAaoVwCzAAAAAA==.Coolsbeans:BAAALgAECgYJCwAAAA==.Coraf:BAACLgAFFH8sAAIDAAgJCSDXAwCWAgADAAgJCSDXAwCWAgAuAAQKfzgAAgMACQkAJMABAHQDAAMACQkAJMABAHQDAAAA.',
Cr='Crankzilla:BAAALgADCggJFgAAAA==.Cravix:BAAALgADCgYJBgAAAA==.Cruoris:BAABLgAECn8bAAIgAAcJww2MDwArAQAgAAcJww2MDwArAQAAAA==.',
Cu='Cunfuzed:BAAALgAECgEJAQAAAA==.Cuvier:BAABLgAECn8hAAIgAAcJMQVrEwDxAAAgAAcJMQVrEwDxAAAAAA==.',
Da='Daddle:BAABLgAECn8gAAQTAAkJayNrDwDRAgATAAkJ5iFrDwDRAgAaAAYJWSIkCgC+AQAhAAEJAADTVAAAAAAAAA==.Daemonxblack:BAAALgAECgEJAQAAAA==.Daeth:BAAALgAECgMJBQAAAA==.Daeththane:BAAALgAECgEJAQAAAA==.Dahaxors:BAABLgAECn8lAAIGAAkJGxvOLwBAAgAGAAkJGxvOLwBAAgAAAA==.Dalareas:BAAALgAECgMJAwAAAA==.Danak:BAAALgAECgIJBgAAAA==.Dannika:BAAALgAECgYJBwAAAA==.Dantelous:BAAALgAECgEJAgAAAA==.Darthwader:BAAALgAECgUJCAAAAA==.Dascrazy:BAABLgAECn8nAAMHAAgJ7QwMJQBtAQAHAAgJ7QwMJQBtAQAgAAUJNAe/FwC4AAAAAA==.Daynaa:BAAALgAECgYJDAABLgAFFAIJCAAiAOAYAA==.',
De='Deadlyfrosty:BAABLgAECn8cAAIGAAYJ3gMXEAGYAAAGAAYJ3gMXEAGYAAAAAA==.Deathsfather:BAAALgADCgYJBgABLgAECgcJEwAIAAAAAA==.Debixie:BAACLgAFFH8TAAIgAAQJyB3eAgB8AQAgAAQJyB3eAgB8AQAuAAQKfyUAAiAACQlLI04BACUDACAACQlLI04BACUDAAAA.Dejection:BAAALgAECgEJAQAAAA==.Delron:BAAALgADCgEJAQAAAA==.Demisi:BAAALgAECgcJEwAAAA==.Demoness:BAABLgAECn8iAAMFAAkJQSK0FQCWAgAFAAgJZCK0FQCWAgAjAAEJTCFiVwBgAAAAAA==.Demsynth:BAAALgAECgQJBAABLgAECgkJJgAPAOYgAA==.Derangedsp:BAAALgADCgkJCQABLgAFFAkJVwATAEYkAA==.Destorr:BAAALgADCgQJBAAAAA==.Dextero:BAAALgADCgMJAwAAAA==.',
Di='Diasundra:BAABLgAECn8sAAIMAAkJ5h9NDgDKAgAMAAkJ5h9NDgDKAgAAAA==.Digiornos:BAABLgAECn8jAAITAAkJqhRCPQDnAQATAAkJqhRCPQDnAQAAAA==.',
Dj='Djyinn:BAAALgADCgcJCgAAAA==.',
Do='Doorknob:BAAALgAECgYJCQAAAA==.Dottingyou:BAACLgAFFH8mAAMTAAgJXRQmJwCrAQATAAcJ3RYmJwCrAQAhAAEJXQWVIwBOAAAuAAQKfzUAAxMACQnvHw4QAMwCABMACQnvHw4QAMwCACEAAwlMHzYsAA4BAAAA.',
Dr='Draenei:BAAALgAECgEJAQAAAA==.Draeziq:BAAALgAECgQJBgABLgAFFAIJCAAiAOAYAA==.Dragonpo:BAAALgAECgEJAQAAAA==.Dragonshide:BAAALgAECgEJAQAAAA==.Drakkonde:BAABLgAECn8bAAITAAYJUhafegBEAQATAAYJUhafegBEAQAAAA==.Dravin:BAAALgADCgYJBgAAAA==.Drazarth:BAAALgAECgUJDQAAAA==.Dreamon:BAAALgAFFAEJAwAAAA==.Droplet:BAAALgAECgQJBAABLgAFFAIJBQAXAAEfAA==.Drransom:BAAALgAECgEJAgAAAA==.Dryan:BAAALgAECgYJEwAAAA==.Dryon:BAABLgAECn82AAIfAAkJPB9TBQDEAgAfAAkJPB9TBQDEAgAAAA==.',
Du='Duergan:BAAALgADCgEJAQAAAA==.Duo:BAABLgAECn8xAAIMAAkJXBNgRwDMAQAMAAkJXBNgRwDMAQAAAA==.Duragon:BAABLgAECn8yAAQRAAkJ7RbBGAARAgARAAkJ7RbBGAARAgAUAAgJPwUoFgCyAAAJAAYJPwdHJwCxAAAAAA==.',
['Dí']='Díznutz:BAABLgAECn8OAAIFAAYJ6RBJeAA+AQAFAAYJ6RBJeAA+AQABLgAFFAMJBQAMAFsaAA==.',
El='Eldumir:BAAALgADCgIJBAABLgAECgkJLwAEAIMeAA==.Elyleath:BAAALgAECgYJBgAAAA==.',
Em='Emilia:BAABLgAECn8vAAMOAAkJHAwABwArAQAOAAkJHAwABwArAQAkAAMJoQeSEgB2AAAAAA==.Empanada:BAAALgADCgEJAQAAAA==.',
En='Endressa:BAABLgAECn8yAAMkAAkJPw8rGwD2AQAkAAkJPw8rGwD2AQASAAIJTw9lbwBlAAAAAA==.English:BAABLgAECn8zAAIKAAkJdBu8NwA5AgAKAAkJdBu8NwA5AgAAAA==.',
Er='Erelios:BAABLgAECn8vAAIEAAkJgx5iBQCbAgAEAAkJgx5iBQCbAgAAAA==.Erubus:BAAALgADCgUJCAAAAA==.',
Es='Eski:BAAALgAECgEJAwAAAA==.',
Eu='Eureka:BAEALgAECgMJCAABLgAECgkJMQAiACYmAA==.',
Ev='Everlight:BAAALgAECgQJBQABLgAECgkJJgABAM0TAA==.Evileyes:BAAALgADCgMJAgAAAA==.',
Ey='Eyezoffury:BAAALgAECgIJAgABLgAECgkJPAAKAEgKAA==.',
Ez='Ezrì:BAAALgAECgMJBwAAAA==.',
Fa='Faddeyshnek:BAABLgAECn8oAAIMAAkJSxZTOwDyAQAMAAkJSxZTOwDyAQAAAA==.Fastbeefball:BAAALgAECgQJBAAAAA==.Fatgirljuice:BAAALgADCgMJAwABLgAFFAkJOwARAEEfAA==.',
Fe='Feliseda:BAAALgADCgkJCwAAAA==.Felorianis:BAAALgADCgEJAQABLgAECgkJOgAFAKkeAA==.Felysambre:BAABLgAECn8WAAMFAAkJWgz0CwAWAQAFAAgJSAz0CwAWAQAlAAEJ1gyFCgA1AAAAAA==.',
Fi='Filibertos:BAABLgAFFH8HAAIFAAUJ2xx3FgBJAQAFAAUJ2xx3FgBJAQABLgAFFAkJMgAKAHskAA==.Firvessa:BAAALgAECgEJAQAAAA==.Fish:BAACLgAFFH87AAISAAgJ4iaDAAApAwASAAgJ4iaDAAApAwAuAAQKfzcAAhIACAmOJlYCAIwDABIACAmOJlYCAIwDAAEuAAUUCQlhABIA7SYA.',
Fl='Flight:BAACLgAFFH8WAAMHAAUJzhy5GABMAQAHAAUJzhy5GABMAQAmAAIJ9BX9CwCkAAAuAAQKfx0AAwcACAkRHHcUAG8CAAcACAljG3cUAG8CACAAAQkBDiweADwAAAAA.Fluxyouup:BAABLgAECn8gAAMDAAkJmghnVwBZAQADAAkJmghnVwBZAQACAAYJCQXWaACsAAAAAA==.Fløki:BAAALgAECgIJAgAAAA==.',
Fo='Follow:BAAALgAECgQJBQAAAA==.Forsynth:BAABLgAECn8mAAMPAAkJ5iDWAADgAgAPAAkJ5iDWAADgAgAKAAEJAABIdQEwAAAAAA==.Foxymeatbal:BAAALgADCgYJBgAAAA==.',
Fr='Frankdux:BAAALgADCgEJAQAAAA==.Frrostitute:BAAALgADCgEJAQAAAA==.',
Ge='Gewitt:BAABLgAECn8tAAMDAAkJgh4cFgCZAgADAAkJgh4cFgCZAgACAAgJ2hnYKADNAQAAAA==.',
Gg='Ggiven:BAABLgAECn8XAAIFAAcJjRJCYQBmAQAFAAcJjRJCYQBmAQAAAA==.',
Gl='Glinda:BAAALgAECgQJBwAAAA==.',
Gn='Gnow:BAAALgADCgEJAQAAAA==.',
Go='Gonjah:BAAALgAECgcJDQAAAA==.',
Gr='Grabomage:BAACLgAFFH8vAAIKAAgJyR1lCgA7AgAKAAgJyR1lCgA7AgAuAAQKf1oAAgoACQkmJlIDAMoDAAoACQkmJlIDAMoDAAAA.Grabovoker:BAAALgAFFAMJAwABLgAFFAgJLwAKAMkdAA==.Grag:BAAALgADCgMJBQAAAA==.Grapekoolaid:BAAALgAECgYJDwAAAA==.Grapesloth:BAAALgAECgQJBAABLgAFFAkJVwATAEYkAA==.Grazienne:BAAALgAECgQJBwAAAA==.Greavos:BAAALgAECgEJAgABLgAECgkJPQAKAI0hAA==.Gretchen:BAAALgADCgUJBQAAAA==.Grif:BAAALgADCgMJAwAAAA==.Grilm:BAABLgAECn8tAAIBAAkJhx/oBQCnAgABAAkJhx/oBQCnAgAAAA==.Grimbaine:BAABLgAECn84AAIcAAkJCCMjCAAqAwAcAAkJCCMjCAAqAwAAAA==.Grimbane:BAAALgAECgMJBAAAAA==.Grimgar:BAAALgAECgEJAgAAAA==.Grimmshady:BAAALgAECgQJBgAAAA==.Grizzlegrimm:BAAALgAECgEJAgAAAA==.Groot:BAAALgAECgkJAQAAAA==.Gryphin:BAAALgADCgcJBwAAAA==.',
Gu='Gulmok:BAAALgADCgUJDQAAAA==.Gumbles:BAACLgAFFH8JAAIOAAQJzxA6EwBwAAAOAAQJzxA6EwBwAAAuAAQKfygABA4ACQlUHWgRAFcCAA4ACQlUHWgRAFcCACQAAglJB3tuAE4AABIAAQnUA5dnACoAAAAA.Gurney:BAABLgAECn8qAAMiAAkJ/hauHQAWAgAiAAkJ/hauHQAWAgAEAAEJggQxWQAdAAAAAA==.Guzfu:BAABLgAECn8UAAIYAAcJgg1jSgDYAAAYAAcJgg1jSgDYAAAAAA==.Guzprimal:BAAALgAECgEJAQABLgAECgcJFAAYAIINAA==.',
Gw='Gwenory:BAAALgAECgEJAQAAAA==.',
Gy='Gying:BAABLgAECn9EAAMWAAkJhR1uCACsAgAWAAkJhR1uCACsAgAYAAUJcg8FQAAZAQAAAA==.',
Ha='Hanjabs:BAAALgAECgYJDgAAAA==.Hanmine:BAAALgAECgYJDQAAAA==.Hannie:BAAALgAECgQJBwAAAA==.Happyelf:BAAALgAECgYJDgAAAA==.Hartephinar:BAAALgAECgEJAQAAAA==.Hatike:BAAALgAECgEJAQAAAA==.',
He='Headhúnter:BAACLgAFFH8FAAIMAAMJWxouWgDxAAAMAAMJWxouWgDxAAAuAAQKfxgAAgwACQlYH0ARAMcCAAwACQlYH0ARAMcCAAAA.Heatseeka:BAABLgAECn8YAAIDAAgJFw5AWQBSAQADAAgJFw5AWQBSAQAAAA==.Hexxiz:BAAALgAECggJDQABLgAECgkJPQAZAB4kAA==.Hezanji:BAAALgAECgUJBQAAAA==.',
Hi='Hiphopinator:BAABLgAECn8vAAMQAAkJLyWHBgD2AgAQAAkJCSOHBgD2AgAfAAcJHCWGDwDwAQAAAA==.',
Ho='Holydeath:BAAALgAECgEJAQAAAA==.Holyshock:BAABLgAECn8UAAIiAAcJrRcIMACaAQAiAAcJrRcIMACaAQAAAA==.Holyterror:BAAALgAECgQJBwAAAA==.Honeysweety:BAAALgADCgMJAwAAAA==.',
Hy='Hydril:BAAALgADCgEJAQAAAA==.',
['Hø']='Hødør:BAAALgAECgQJCwAAAA==.',
Ia='Iamcro:BAAALgAECgUJBgAAAA==.Ianthe:BAABLgAECn83AAIPAAkJ8AtvAQBNAQAPAAkJ8AtvAQBNAQAAAA==.',
Ib='Iboga:BAAALgAECgUJBwAAAA==.Ibrahimovic:BAABLgAECn80AAQhAAcJryPdCwCBAQAhAAUJHCTdCwCBAQAaAAYJURlGDwBoAQATAAQJjB1qfABAAQAAAA==.',
Ig='Ignitecro:BAAALgADCgUJBQAAAA==.Igram:BAAALgAECgQJBAAAAA==.',
Ih='Iheal:BAAALgADCgcJCgAAAA==.',
Il='Illidoonger:BAAALgAECgYJDwAAAA==.',
Im='Imauggin:BAAALgADCgYJBgAAAA==.Imbobbymom:BAAALgAECgEJAgABLgAFFAkJOwARAEEfAA==.Imhim:BAAALgAECgEJAQAAAA==.',
In='Inafume:BAAALgAECgcJDQAAAA==.Infoxicated:BAAALgAECgUJCgABLgAECgYJCAAIAAAAAA==.Inoxia:BAAALgAECgQJBgAAAA==.Intrépidice:BAAALgAECgQJBwAAAA==.',
Io='Iowastyle:BAABLgAECn84AAMOAAkJHSC7BQAdAwAOAAkJHSC7BQAdAwAkAAMJlgx+QwCZAAAAAA==.',
It='Ithruyn:BAAALgAECgQJBQAAAA==.',
Ix='Ixtabay:BAACLgAFFH8dAAMaAAYJLRcMAgBAAQAaAAUJfhwMAgBAAQATAAIJvgdPyABCAAAuAAQKfzoABBoACQn0Ia8EAE8CABoACQmXIa8EAE8CABMABgnBGg5CANYBACEAAgm6EoBTAHQAAAAA.',
Ja='Jakobey:BAAALgAECgQJBQAAAA==.Jamurra:BAABLgAECn8aAAIDAAcJohX1BwCLAQADAAcJohX1BwCLAQABLgAFFAIJCAAiAOAYAA==.Jaylinn:BAABLgAECn8uAAIMAAkJ4Q3TVAClAQAMAAkJ4Q3TVAClAQAAAA==.Jazzmend:BAAALgADCgEJAQAAAA==.',
Je='Jeanne:BAAALgAECgYJBwAAAA==.Jessika:BAACLgAFFH87AAMRAAkJQR9nAgDXAgARAAkJQR9nAgDXAgAUAAEJygr9CQBTAAAuAAQKfyoAAxEACQmjJfcBAGIDABEACQmjJfcBAGIDABQABgmRI78PAN8BAAEuAAUUCQk7ABEAQR8A.Jezebel:BAAALgAECgUJBQABLgAECgkJOQAJAIIYAA==.',
Ji='Jimsonweed:BAAALgAFFAEJAQAAAA==.',
Jo='Jocko:BAAALgADCgYJBgAAAA==.Josie:BAABLgAECn8pAAIkAAkJFiRcBABPAwAkAAkJFiRcBABPAwAAAA==.',
Ju='Judgekoopa:BAABLgAECn8qAAIiAAkJcx0rCwDaAgAiAAkJcx0rCwDaAgAAAA==.',
Ka='Kaadore:BAAALgAECgYJBwAAAA==.Kaeiria:BAAALgAECgUJCgAAAA==.Kael:BAAALgAECgEJAQAAAA==.Kalaanri:BAABLgAECn8xAAMCAAkJLxQyKACsAQACAAkJLxQyKACsAQADAAYJig6haQAfAQAAAA==.Kaleberry:BAABLgAECn8gAAMVAAkJBA6GJgCZAQAVAAgJBA6GJgCZAQAZAAcJEgmlhgDJAAAAAA==.Kalthyra:BAAALgAECgMJAwABLgAECgkJLwAEAIMeAA==.Kalyandra:BAABLgAECn8mAAIYAAcJdxBENAAyAQAYAAcJdxBENAAyAQAAAA==.Kalógeros:BAAALgADCgMJAwAAAA==.Kanhang:BAAALgADCgcJDAAAAA==.Kanra:BAABLgAECn8XAAQBAAYJ6RydFwCUAQABAAYJ6RydFwCUAQAZAAYJLgwzaQD5AAAVAAEJvBKCiQA4AAABLgAECgkJOgAEAH8iAA==.Karkevon:BAAALgAECgYJDgAAAA==.Karlach:BAABLgAECn8eAAIQAAkJAh0bFwA1AgAQAAkJAh0bFwA1AgAAAA==.Karlachs:BAAALgADCgYJBwAAAA==.Karrla:BAABLgAECn8wAAIFAAkJhxqnGQB7AgAFAAkJhxqnGQB7AgAAAA==.Karumie:BAABLgAECn8nAAIDAAkJZhyXHwBTAgADAAkJZhyXHwBTAgAAAA==.Kashyyk:BAAALgAECgMJAwABLgAECgkJQAATAJkaAA==.Kateera:BAAALgAECgUJCwAAAA==.',
Ke='Keden:BAAALgAECgQJBgAAAA==.Keelivan:BAAALgAECgMJAwAAAA==.Kelivann:BAAALgADCgUJBQAAAA==.Keljaden:BAABLgAECn8YAAIdAAkJwiA3AwACAwAdAAkJwiA3AwACAwABLgAECgkJLAAFAEEiAA==.Kels:BAABLgAECn8sAAIFAAkJQSL5DADdAgAFAAkJQSL5DADdAgAAAA==.',
Kh='Kheyra:BAABLgAECn8mAAIBAAkJzROLEgDJAQABAAkJzROLEgDJAQAAAA==.',
Ki='Kiaona:BAAALgADCgMJAwAAAA==.Kidashia:BAAALgAECgQJBAAAAA==.Kiwisloth:BAAALgAFFAEJAQABLgAFFAkJVwATAEYkAA==.',
Ko='Koggs:BAAALgAFFAIJAgAAAA==.Kohnor:BAAALgAECgQJCAAAAA==.Kopi:BAAALgAECgMJBAABLgAECgkJLAALAPchAA==.Kopiccino:BAAALgAECgEJAQABLgAECgkJLAALAPchAA==.Korlatt:BAABLgAECn86AAQFAAkJqR7kEgCsAgAFAAkJQh3kEgCsAgAlAAMJDRxHFwDqAAAjAAMJOhZfVwBgAAAAAA==.Kowalabear:BAABLgAECn8rAAMnAAkJtCExAQD+AgAnAAkJtCExAQD+AgALAAQJPwqaTQBbAAAAAA==.',
Kr='Kryptrix:BAAALgAECgQJBAAAAA==.Krìmzar:BAAALgADCggJCgABLgAECgYJFAAKADgXAA==.',
Kt='Kthanid:BAABLgAECn8aAAIkAAYJpBjaMgBOAQAkAAYJpBjaMgBOAQAAAA==.',
Ku='Kurston:BAABLgAECn9DAAIZAAkJMRtoEwCwAgAZAAkJMRtoEwCwAgAAAA==.',
Ky='Kymakazie:BAABLgAECn8ZAAIMAAkJrAP4mAAOAQAMAAkJrAP4mAAOAQAAAA==.Kymmuul:BAAALgAECgMJAwAAAA==.',
['Kã']='Kãtniss:BAAALgAECgIJAgAAAA==.',
['Kÿ']='Kÿndrà:BAAALgAECgQJBgAAAA==.',
La='Labella:BAAALgAECgIJAgAAAA==.Laih:BAABLgAECn8jAAIgAAkJgA+uCAC+AQAgAAkJgA+uCAC+AQAAAA==.Lasturus:BAAALgAECgUJBQABLgAFFAgJJQAXAGkZAA==.Lathelinis:BAAALgAECgcJCgAAAA==.Lauraenital:BAAALgAECgQJBAAAAA==.Layssara:BAAALgADCgMJAwAAAA==.',
Le='Leafbloom:BAAALgAECgEJAQABLgAECggJFgAWAHsYAA==.Letmeout:BAAALgAECgEJAQAAAA==.Lexx:BAAALgAECgIJAgAAAA==.Leyote:BAABLgAECn8/AAIDAAkJDBOiLAAGAgADAAkJDBOiLAAGAgAAAA==.',
Lh='Lhai:BAAALgAECgEJAQABLgAECgkJIwAgAIAPAA==.',
Li='Liady:BAAALgADCgcJDQAAAA==.Lightshop:BAAALgADCgIJAQAAAA==.Liirah:BAAALgAECgEJAQAAAA==.Linora:BAAALgAECgIJAQAAAA==.Listriesa:BAAALgADCgEJAQAAAA==.',
Lo='Lolabunny:BAABLgAECn8UAAMYAAYJZBofNABRAQAYAAUJkxYfNABRAQAWAAQJ+xkLRgAqAQABLgAECggJGAALAOIiAA==.Lorianne:BAAALgAECgcJCQAAAA==.Lousseur:BAAALgADCgEJAgAAAA==.Lowdangle:BAABLgAECn8tAAIFAAkJtheTJQA3AgAFAAkJtheTJQA3AgAAAA==.',
Lu='Lulz:BAAALgAECgkJEwAAAA==.Lumini:BAABLgAECn8eAAMSAAkJ3AbqNABEAQASAAkJ3AbqNABEAQAOAAMJfwPyagA9AAAAAA==.Luminias:BAAALgAECgUJDQAAAA==.Luthein:BAAALgAECgcJEwAAAA==.Luxroy:BAAALgAECgYJEQAAAA==.',
Ly='Lygma:BAABLgAECn8jAAIcAAkJ/g6UZACmAQAcAAkJ/g6UZACmAQAAAA==.Lynniebee:BAABLgAECn8pAAIPAAkJjAwmBQCPAQAPAAkJjAwmBQCPAQAAAA==.',
Ma='Madalyn:BAAALgAECgcJEwAAAA==.Maexna:BAAALgAECgEJAQAAAA==.Magicpie:BAAALgAECgcJBwABLgAECgkJPwAlANIkAA==.Magni:BAAALgAECgQJBQAAAA==.Makklehaney:BAABLgAECn8hAAMbAAkJTg5EEQCfAQAbAAkJTg5EEQCfAQACAAEJ7QFmlQAgAAAAAA==.Mallaah:BAAALgADCgYJCgAAAA==.Malthorin:BAAALgADCgMJAwAAAA==.Maneke:BAAALgADCgkJCQABLgAECgkJLwADAJcVAA==.Marovingian:BAABLgAECn8uAAIiAAkJ4yFYAwBsAwAiAAkJ4yFYAwBsAwAAAA==.Matthad:BAABLgAECn8vAAIDAAkJlxWIJwAiAgADAAkJlxWIJwAiAgAAAA==.Mazìkene:BAACLgAFFH8bAAMaAAUJQQ5nCQDjAAATAAQJ0gfraADzAAAaAAQJzxFnCQDjAAAuAAQKfygAAxoACQlEGZ0JAMkBABoABwnrGJ0JAMkBABMACQk2FgdSAKYBAAAA.',
Mc='Mccone:BAABLgAECn8ZAAIMAAYJnQmtrwDlAAAMAAYJnQmtrwDlAAAAAA==.Mcnastie:BAAALgAECgEJAQAAAA==.Mcsluts:BAABLgAECn8lAAMcAAYJDhCAJwCOAAAcAAYJkw6AJwCOAAAEAAEJaBDqUwApAAAAAA==.',
Me='Megadumb:BAAALgAECgQJBAABLgAFFAkJOwARAEEfAA==.Melmirict:BAACLgAFFH8TAAIHAAUJWBJgIAAiAQAHAAUJWBJgIAAiAQAuAAQKfyUAAwcACQlQGd0TAAQCAAcACQlQGd0TAAQCACAAAwmAGpQSANkAAAAA.Meng:BAAALgADCgYJBgAAAA==.Merciala:BAABLgAECn9DAAIBAAkJdRLfFwCSAQABAAkJdRLfFwCSAQAAAA==.',
Mi='Milyva:BAAALgADCgMJAwAAAA==.Milyyanna:BAAALgAECgMJBQAAAA==.Minaby:BAAALgAECgYJEAABLgAECgkJOQAcACUlAA==.Missmurder:BAAALgAFFAEJAgAAAA==.Mitochondria:BAAALgADCgQJBAAAAA==.',
Mo='Moddoxx:BAABLgAECn9AAAQTAAkJmRruKgAuAgATAAgJSxzuKgAuAgAaAAIJkg6GPAA5AAAhAAIJuw4KPwAyAAAAAA==.Mohawk:BAABLgAECn8YAAIZAAkJIBNIAwD0AQAZAAkJIBNIAwD0AQAAAA==.Mohaxors:BAAALgADCgcJDwAAAA==.Moko:BAAALgAECgEJAgAAAA==.Mokopal:BAAALgADCgMJAwAAAA==.Mokøtrollz:BAABLgAECn8jAAMMAAkJrh9zOAD8AQANAAgJmBnLEgASAgAMAAgJIB5zOAD8AQAAAA==.Molen:BAAALgAECgYJCwAAAA==.Mommyjuice:BAAALgAFFAEJAQABLgAFFAkJOwARAEEfAA==.Monkeeh:BAAALgADCgUJCQAAAA==.Monkle:BAABLgAECn9YAAIYAAkJ/CTOAQBYAwAYAAkJ/CTOAQBYAwAAAA==.Monkoku:BAAALgAECgQJBAABLgAFFAYJEwAHAKgXAA==.Moonsii:BAABLgAECn8aAAIZAAkJ9Q1zPQCdAQAZAAkJ9Q1zPQCdAQAAAA==.Mooroth:BAABLgAECn9CAAIfAAkJPSBaBADhAgAfAAkJPSBaBADhAgABLgAFFAIJAgAIAAAAAA==.Morekk:BAAALgAECgEJAQAAAA==.Morozko:BAABLgAECn8eAAInAAgJShqLCAAEAgAnAAgJShqLCAAEAgAAAA==.',
Mu='Muddler:BAABLgAECn9CAAIhAAkJlAOlHADCAAAhAAkJlAOlHADCAAAAAA==.Muscuees:BAAALgADCgEJAQAAAA==.Mush:BAAALgAECgQJBAAAAA==.',
['Mà']='Màggles:BAAALgAECgQJBAAAAA==.',
Na='Nadd:BAABLgAECn8wAAIMAAkJBgymEQAxAQAMAAkJBgymEQAxAQAAAA==.Naledi:BAABLgAECn8cAAIVAAgJ5Q+/MwBKAQAVAAgJ5Q+/MwBKAQAAAA==.Nancy:BAAALgAECgQJBAAAAA==.Naomas:BAABLgAECn89AAMKAAkJjSGbEgDqAgAKAAkJ9SCbEgDqAgAPAAIJ2R6aDAC1AAAAAA==.Narella:BAABLgAECn8tAAIKAAgJjRQpZQCzAQAKAAgJjRQpZQCzAQAAAA==.',
Ne='Needlepax:BAAALgAECgEJAgAAAA==.Negotiable:BAAALgAECgYJEAAAAA==.Negrido:BAABLgAECn8zAAQTAAkJ+yU2DwDTAgATAAgJwSI2DwDTAgAhAAMJNiWJJAA3AQAaAAEJvx9qMQBaAAAAAA==.Nei:BAABLgAECn9LAAIcAAgJ2xvEBgDiAQAcAAgJ2xvEBgDiAQAAAA==.Nemeton:BAAALgAECgIJAgAAAA==.Newt:BAAALgADCgUJBQAAAA==.Nezzarector:BAAALgAECgUJCwAAAA==.',
Ni='Nikem:BAABLgAECn87AAMVAAkJbxrjEABWAgAVAAkJbxrjEABWAgABAAEJ0wKQOwAPAAAAAA==.Nimseti:BAAALgAFFAIJAwAAAA==.',
No='Noelle:BAAALgAECgQJCQAAAA==.Nor:BAAALgAECgUJCgAAAA==.Noraelyn:BAABLgAECn8zAAMiAAkJ7xtHDQC9AgAiAAkJ7xtHDQC9AgAcAAQJewSqUAFeAAAAAA==.Norelei:BAAALgAECgUJBwABLgAECgkJJgABAM0TAA==.Noriyuki:BAABLgAECn8uAAIYAAcJDgKihgBMAAAYAAcJDgKihgBMAAAAAA==.Northside:BAAALgADCgQJBAABLgAFFAkJMgAKAHskAA==.Notkorlatt:BAAALgADCgIJAgAAAA==.',
Nu='Nugatory:BAACLgAFFH8KAAQNAAYJhBO0FgAbAQANAAYJhBO0FgAbAQAMAAEJFwaBqgBDAAAeAAEJwAH2PAAqAAAuAAQKfxcAAw0ACAlSI1cKAHkCAA0ACAlSI1cKAHkCAB4AAwnADI9pAJgAAAEuAAUUBgkJABIADwoA.Nuudles:BAAALgAECgEJAQAAAA==.',
Ny='Nyxahlia:BAAALgAECgYJEQAAAA==.',
Oa='Oakenia:BAAALgAECgEJAQABLgAECgkJOgAZAO8QAA==.',
Og='Ogkagìsttv:BAAALgAECgYJBwAAAA==.',
Ol='Olderon:BAAALgAECgIJAgAAAA==.Olrong:BAABLgAECn9BAAIjAAkJlxOVFgDTAQAjAAkJlxOVFgDTAQAAAA==.Oluja:BAAALgAECgYJDwAAAA==.',
Om='Omegâ:BAABLgAFFH8HAAIFAAMJBASVNgCDAAAFAAMJBASVNgCDAAAAAA==.',
On='Onlypaws:BAAALgAECgYJEgAAAA==.Onuris:BAAALgAECgEJAQAAAA==.',
Op='Opaalite:BAAALgAECgMJAwAAAA==.Opacuslupus:BAAALgAECggJEAAAAA==.Ophel:BAAALgADCgYJBgABLgAECgkJOQAJAIIYAA==.Oppcookies:BAAALgAECgYJDwABLgAECgkJIwAMALkYAA==.Oppressin:BAAALgAECgEJAQABLgAECgkJIwAMALkYAA==.Oppshot:BAABLgAECn8jAAMMAAkJuRiaKgAzAgAMAAkJuRiaKgAzAgAeAAEJUAnlPgAsAAAAAA==.',
Or='Orin:BAAALgAECgEJAQAAAA==.',
Os='Oshìe:BAACLgAFFH8FAAIiAAMJFxE+MwCjAAAiAAMJFxE+MwCjAAAuAAQKfykAAiIACQnbIVAMALgCACIACQnbIVAMALgCAAAA.',
Ov='Overdoom:BAABLgAECn82AAMGAAkJYx7KKgBVAgAGAAkJYx7KKgBVAgALAAUJHAb3QwB/AAAAAA==.Ovscur:BAAALgAFFAEJAgAAAA==.',
Pa='Packapipe:BAAALgADCggJEgAAAA==.Paladinjohn:BAACLgAFFH8pAAIcAAgJJSGMCgAwAgAcAAgJJSGMCgAwAgAuAAQKfysAAhwACQkbJWMBANEDABwACQkbJWMBANEDAAAA.Palykat:BAABLgAECn81AAIcAAkJBAkZEAAzAQAcAAkJBAkZEAAzAQAAAA==.Paradox:BAAALgAECgEJAQAAAA==.',
Pe='Pelagos:BAAALgAECggJCgAAAA==.Pennywisé:BAABLgAECn8rAAIGAAkJUyBAGwCjAgAGAAkJUyBAGwCjAgAAAA==.Percentguy:BAAALgAECgMJAwAAAA==.Pessimal:BAAALgADCgEJAQABLgAECgkJIgAGAEMfAA==.',
Ph='Phillygg:BAAALgAECgQJBAAAAA==.Phoeniix:BAABLgAECn8mAAMBAAkJiBeLEwC9AQABAAkJ4haLEwC9AQAVAAQJvRe1UgDcAAAAAA==.',
Pl='Plaguegying:BAABLgAECn8eAAMGAAkJnA+CZgCaAQAGAAgJ8w+CZgCaAQALAAEJOQ3gWQA6AAABLgAECgkJRAAWAIUdAA==.Ploofee:BAAALgAECgkJEgAAAA==.',
Po='Porker:BAAALgADCgEJAQAAAA==.',
Pr='Prog:BAAALgAECgEJAQAAAA==.Progresz:BAABLgAECn8WAAIKAAkJwRBLYAC/AQAKAAkJwRBLYAC/AQAAAA==.',
Ps='Psichosa:BAAALgAECggJDgAAAA==.Psychosis:BAAALgADCgQJAwAAAA==.',
Py='Pykel:BAABLgAECn8uAAIVAAkJgw34BwAKAQAVAAkJgw34BwAKAQAAAA==.Pyrexea:BAAALgADCgYJBgAAAA==.Pyrivia:BAAALgAECgEJAgABLgAECgUJCgAIAAAAAA==.',
Qa='Qaren:BAABLgAECn8aAAIcAAYJrgmrCgGrAAAcAAYJrgmrCgGrAAAAAA==.',
Qi='Qikeyy:BAAALgAECgEJAQAAAA==.',
Qu='Quadraxis:BAAALgADCgcJCQAAAA==.Questionable:BAAALgADCgUJBQAAAA==.',
Ra='Racerx:BAAALgAFFAIJAgAAAA==.Raethe:BAAALgAECgQJBAAAAA==.Raishun:BAAALgAECgMJAwAAAA==.Raizo:BAAALgADCgEJAQAAAA==.Rajak:BAAALgADCgEJAQAAAA==.Rake:BAABLgAECn80AAQoAAkJVSCbBgB8AgAoAAkJFB+bBgB8AgABAAEJQh1IYABPAAAVAAIJ6wcegABIAAAAAA==.Raminthórn:BAAALgADCgIJAgAAAA==.Rannï:BAACLgAFFH8GAAIKAAMJyAp7jQC+AAAKAAMJyAp7jQC+AAAuAAQKfxUAAgoACAkiFPxeAMMBAAoACAkiFPxeAMMBAAEuAAUUBgkdABoALRcA.Raskreia:BAABLgAFFH8GAAIGAAMJRyNXJAA1AQAGAAMJRyNXJAA1AQABLgAFFAYJHQAKAOIiAA==.Ratabi:BAAALgADCgIJAgAAAA==.Ravana:BAAALgADCggJCAAAAA==.Ravna:BAABLgAECn8dAAMCAAgJfRUGBACjAQACAAgJfRUGBACjAQADAAQJCgYnpACFAAABLgAECgkJOwAVADYcAA==.Rawk:BAAALgAECgYJCwAAAA==.Rawrski:BAAALgADCgEJAgABLgAECgkJNgADAH0OAA==.',
Re='Reavert:BAAALgADCgYJBgAAAA==.Reeven:BAAALgAECgkJNgAAAQ==.Reshii:BAAALgAECgEJAQABLgAECgkJQAATAJkaAA==.Ressurectjin:BAAALgAECgUJDgAAAA==.Rexmortis:BAAALgAECgkJAgAAAA==.',
Rh='Rhaistlin:BAAALgADCgMJAwAAAA==.Rhcpmage:BAACLgAFFH8NAAIKAAQJUSL0RwBUAQAKAAQJUSL0RwBUAQAuAAQKfxwAAgoACQmKIVsWANMCAAoACQmKIVsWANMCAAAA.Rhetegast:BAABLgAECn8oAAIEAAkJrRPHDwDIAQAEAAkJrRPHDwDIAQAAAA==.Rhymaek:BAAALgAECgYJCQABLgAFFAIJCAAiAOAYAA==.Rhyss:BAAALgAECgQJBAAAAA==.',
Ri='Rike:BAABLgAECn9AAAMcAAkJ+iJjHwCLAgAcAAkJ5SFjHwCLAgAEAAYJlB4DEQC0AQAAAA==.Rinde:BAAALgADCgkJCQAAAA==.Riobla:BAAALgAECgQJBwABLgAECgkJPAAKAEgKAA==.',
Ro='Roflbackpack:BAAALgAECgkJBwAAAA==.Roflbalanced:BAAALgAECgQJCAAAAA==.Roflgotnerfd:BAAALgADCgMJAwABLgAECgkJBwAIAAAAAA==.Roflhazotime:BAABLgAECn8nAAIFAAkJVyOWCQD/AgAFAAkJVyOWCQD/AgAAAA==.Roland:BAABLgAECn81AAMZAAkJyhOgMADfAQAZAAkJyhOgMADfAQAVAAYJAQ15TQDWAAAAAA==.Rolandin:BAABLgAECn9AAAIiAAkJ1RfYEgB6AgAiAAkJ1RfYEgB6AgAAAA==.Rollaen:BAAALgADCgYJDAAAAA==.Rollan:BAAALgAECgUJDAAAAA==.Rook:BAABLgAFFH8JAAIHAAQJfxRoGwA+AQAHAAQJfxRoGwA+AQABLgAFFAgJLAADAAkgAA==.Roscjou:BAABLgAECn8YAAICAAcJsQT3YADCAAACAAcJsQT3YADCAAAAAA==.Ross:BAAALgAECgYJDwAAAA==.',
Ru='Rubisco:BAAALgAECgYJCwAAAA==.Ruh:BAAALgAECgMJBgABLgAECgkJQAATAJkaAA==.Rukraga:BAAALgAECgIJAgAAAA==.',
Ry='Rylagosa:BAABLgAECn85AAMJAAkJghiJDwDTAQAJAAcJNxiJDwDTAQARAAkJZRIEJgCwAQAAAA==.Rynehardt:BAAALgADCgcJBwAAAA==.Ryuji:BAAALgAECgEJAQAAAA==.Ryzesmidge:BAABLgAECn8XAAIKAAkJGRHYWQDQAQAKAAkJGRHYWQDQAQAAAA==.',
['Rê']='Rêdrum:BAABLgAFFH8IAAIGAAMJ3guFXQCNAAAGAAMJ3guFXQCNAAABLgAFFAUJGwAaAEEOAA==.',
Sa='Sabithia:BAAALgAECgEJAQAAAA==.Sahathiel:BAAALgAFFAIJAwAAAA==.Salandria:BAAALgAECgYJEAAAAA==.Salandriath:BAAALgAECgYJCwAAAA==.Sange:BAAALgAECgcJDQAAAA==.Sarionian:BAABLgAECn86AAIZAAkJ7xDmMgDTAQAZAAkJ7xDmMgDTAQAAAA==.Sarvin:BAAALgADCgcJBwABLgAECgkJKwADAEscAA==.Sarvinblue:BAABLgAECn8rAAMDAAkJSxxAFgCYAgADAAkJSxxAFgCYAgACAAMJLQ8SagCbAAAAAA==.Satrathen:BAAALgADCgYJBgAAAA==.Saucestash:BAAALgAECgIJAgAAAA==.Sauronic:BAAALgAECgYJCgAAAA==.',
Sc='Scopolamine:BAAALgADCgEJAQAAAA==.',
Se='Searchlights:BAAALgAECgYJEQAAAA==.Seshu:BAAALgAECgEJAQAAAA==.Sevrin:BAAALgADCgEJAQAAAA==.',
Sh='Shaeko:BAAALgADCgYJBgAAAA==.Shambúlance:BAAALgAECgMJAwAAAA==.Shanaynay:BAAALgAECgQJBAAAAA==.Shanir:BAAALgADCgMJAwAAAA==.Shanksie:BAABLgAECn8bAAIgAAcJkAaDEwDwAAAgAAcJkAaDEwDwAAAAAA==.Shazlulu:BAABLgAECn8pAAIDAAkJ1RgHBgDJAQADAAkJ1RgHBgDJAQAAAA==.Shedoa:BAAALgAECgYJBgAAAA==.Shiftywelt:BAAALgADCggJDAAAAA==.Shinmothee:BAABLgAECn8iAAIPAAkJkApWBgBeAQAPAAkJkApWBgBeAQAAAA==.Shinsura:BAAALgADCgcJEAAAAA==.Shtamman:BAAALgADCgUJBQAAAA==.',
Si='Silvantis:BAAALgADCgEJAQAAAA==.Siobhán:BAABLgAECn8tAAIHAAkJnx8LDwA7AgAHAAkJnx8LDwA7AgAAAA==.',
Sk='Skandle:BAAALgADCgMJAwAAAA==.',
Sl='Sleepypanda:BAABLgAECn8jAAIiAAkJtxnWFQBdAgAiAAkJtxnWFQBdAgAAAA==.Sloe:BAABLgAECn87AAMOAAkJPxyFDQCOAgAOAAkJPxyFDQCOAgASAAEJrAXjlAAlAAAAAA==.',
Sm='Smokalot:BAAALgADCgEJAQAAAA==.',
Sn='Sneakez:BAAALgAFFAEJAQAAAA==.',
So='Somebody:BAAALgAECgQJBQAAAA==.Soulitude:BAAALgAECgEJAQAAAA==.Southerngal:BAAALgADCgQJBQAAAA==.',
Sp='Speedbeefbal:BAAALgAECgUJBQAAAA==.Speedkweef:BAABLgAFFH8HAAISAAMJWwK1FgCAAAASAAMJWwK1FgCAAAAAAA==.Speedmeat:BAABLgAECn8pAAMDAAkJ8gi1ZAAtAQADAAgJxAi1ZAAtAQACAAgJMQvdCgDdAAAAAA==.Spinny:BAAALgAECgYJBgAAAA==.Sporkulous:BAACLgAFFH8IAAIMAAMJbAfyQgCPAAAMAAMJbAfyQgCPAAAuAAQKfy8AAwwACAl/E1BKAMIBAAwACAl/E1BKAMIBAB4AAQkXARRIABAAAAAA.',
Sq='Squal:BAABLgAECn87AAMcAAkJeyCuEADhAgAcAAkJeyCuEADhAgAEAAUJ/BhSGwA9AQAAAA==.Squiggle:BAABLgAECn89AAIEAAkJjSJMAgASAwAEAAkJjSJMAgASAwAAAA==.',
St='Stalkêr:BAAALgADCgIJAgAAAA==.Steevii:BAAALgADCgEJAQAAAA==.Stewie:BAAALgAECgEJAgAAAA==.Stewy:BAAALgAECgYJCAAAAA==.Stickybunz:BAABLgAECn8ZAAIQAAgJURUDJgDIAQAQAAgJURUDJgDIAQABLgAFFAQJDwASAHAFAA==.Striker:BAAALgAECgQJDwABLgAECgkJQAAcAPoiAA==.Strombone:BAAALgADCgEJAgABLgAECgIJEAAIAAAAAA==.Stunseed:BAABLgAECn8rAAIBAAkJ1hhFCwAuAgABAAkJ1hhFCwAuAgAAAA==.',
Su='Sumo:BAAALgAECgEJAQAAAA==.Sungjinwu:BAAALgAECgUJBQAAAA==.Sunnmage:BAAALgAECgcJCAAAAA==.Sunshíne:BAABLgAECn8vAAMEAAkJkhFmAgCtAQAEAAkJkhFmAgCtAQAcAAgJQQfKsAAeAQAAAA==.Surf:BAABLgAECn8XAAIFAAcJWRxlNAD1AQAFAAcJWRxlNAD1AQABLgAFFAEJAwAIAAAAAA==.',
Sw='Sweetbunz:BAACLgAFFH8PAAMSAAQJcAW1JQDLAAASAAQJcAW1JQDLAAAOAAQJAAnwHQDJAAAuAAQKfzoAAxIACQnHFpYXAAsCABIACQnHFpYXAAsCAA4ACAlYDjMxAEgBAAAA.Swegin:BAAALgAECgIJAgABLgAECgQJBwAIAAAAAA==.',
Sx='Sxes:BAAALgAECgYJDAAAAA==.',
Sy='Synaminaphyn:BAAALgAECgEJAQAAAA==.Syver:BAABLgAECn8pAAMGAAkJ2BkHRwDtAQAGAAgJGxsHRwDtAQALAAEJCRG+WAA9AAAAAA==.',
['Sì']='Sìrcândymân:BAAALgAECgEJAQABLgAECgYJEgAIAAAAAA==.Sìrfuzywuzy:BAAALgAECgYJEgAAAA==.',
['Sí']='Sírlancealot:BAAALgAECgEJAQABLgAECgYJEgAIAAAAAA==.',
Ta='Taisty:BAAALgADCgQJBAAAAA==.Takers:BAAALgAECgYJCgAAAA==.Tanagra:BAAALgAECgEJAQABLgAECgkJQAATAJkaAA==.Taniss:BAABLgAECn8pAAImAAkJlQioCwBcAQAmAAkJlQioCwBcAQAAAA==.Tanner:BAABLgAECn8dAAMeAAgJDgnESgAnAQAeAAgJwQfESgAnAQAMAAIJoBF5ogCHAAAAAA==.Tarnaby:BAAALgAECgEJAgAAAA==.',
Te='Teboe:BAAALgAECgYJBwAAAA==.Tedman:BAABLgAECn8vAAMCAAkJjRlTEwBTAgACAAkJjRlTEwBTAgADAAMJmgdWjwBaAAAAAA==.Tekki:BAAALgADCgEJAQAAAA==.Temel:BAABLgAECn82AAMDAAkJfQ5DTgB4AQADAAgJtwxDTgB4AQACAAkJUw07NABqAQAAAA==.Tenelum:BAAALgAECgQJDQABLgAECgkJNgADAH0OAA==.Testoecles:BAAALgAECgMJBQABLgAECgYJBwAIAAAAAA==.',
Th='Thadrack:BAABLgAECn88AAIKAAkJSAq2fQB8AQAKAAkJSAq2fQB8AQAAAA==.Thaine:BAAALgADCgEJAQABLgAECgcJDQAIAAAAAA==.Thalonstin:BAAALgAECgQJCgAAAA==.Thanee:BAABLgAFFH8IAAIOAAUJFRM8FAAjAQAOAAUJFRM8FAAjAQABLgAECgcJDQAIAAAAAA==.Thanevoker:BAAALgAECgcJDQAAAA==.Theodrid:BAACLgAFFH8TAAIcAAgJKRHlJQBxAQAcAAgJKRHlJQBxAQAuAAQKfyMAAhwACQmhHjAkAJcCABwACQmhHjAkAJcCAAAA.Thoreum:BAAALgAECgEJAgAAAA==.Thraxia:BAABLgAECn8XAAITAAgJWAUGlgAsAQATAAgJWAUGlgAsAQAAAA==.Thrombin:BAAALgAECgMJAwAAAA==.',
Ti='Tigertigress:BAAALgAECgQJBAAAAA==.Tinkíe:BAABLgAECn8iAAQYAAkJ9Ry3GQDjAQAYAAgJ0By3GQDjAQAWAAQJQRmWTgAJAQAXAAUJ2QxNaQDbAAAAAA==.Tirzahdozier:BAACLgAFFH8IAAIiAAIJ4BiFFwCJAAAiAAIJ4BiFFwCJAAAuAAQKfx4AAyIACQkCFDIFAGYBACIACQkCFDIFAGYBABwAAQlfAn3QARgAAAAA.Tiwohnne:BAAALgAECgYJDQAAAA==.',
Tl='Tla:BAAALgAECgQJBwAAAA==.',
To='Tooey:BAAALgAECgEJAQAAAA==.',
Tr='Treat:BAABLgAECn9DAAISAAkJfySLAgBAAwASAAkJfySLAgBAAwAAAA==.Tremblement:BAAALgADCgMJAwAAAA==.Trickortreat:BAAALgADCgMJAwAAAA==.Trippyshock:BAABLgAFFH8RAAICAAQJKh0tGwBBAQACAAQJKh0tGwBBAQABLgAFFAkJVwATAEYkAA==.Tristitia:BAABLgAECn8vAAMGAAkJ+BYgMQA6AgAGAAkJ+BYgMQA6AgALAAIJGAYxWQA8AAAAAA==.Trolidan:BAAALgAECgEJAQAAAA==.',
Ts='Tsaorkrad:BAAALgAECgEJAQAAAA==.',
Tu='Tubbs:BAABLgAECn8ZAAIGAAkJAxw4LQBLAgAGAAkJAxw4LQBLAgAAAA==.Turkeltin:BAAALgAECgYJEAABLgAFFAQJCgAKAF0ZAA==.',
Tw='Twiggle:BAAALgAECgQJBAABLgAFFAIJCAAiAOAYAA==.',
Ty='Tyche:BAABLgAECn8cAAMDAAYJXhBpZgAoAQADAAYJXhBpZgAoAQACAAEJ2gHYwwAYAAAAAA==.Tyrdrin:BAAALgAECgEJAQAAAA==.Tyrinara:BAAALgADCgYJBgAAAA==.Tysbich:BAAALgAECgQJCAABLgAECgkJLgAiAOMhAA==.',
Ui='Uiewedaoez:BAABLgAECn80AAIZAAkJWST7AgCZAwAZAAkJWST7AgCZAwAAAA==.',
Um='Umakkel:BAAALgAECgYJDgAAAA==.Umiko:BAAALgADCgUJBQAAAA==.',
Ur='Urd:BAABLgAECn8hAAIGAAkJ9BAmWgC4AQAGAAkJ9BAmWgC4AQAAAA==.',
Va='Vaelrelyn:BAABLgAECn8UAAMhAAYJJhD1HgBZAQAhAAYJJhD1HgBZAQATAAIJ4gHuLwEhAAAAAA==.Vains:BAACLgAFFH8SAAIcAAUJkRzxOQA4AQAcAAUJkRzxOQA4AQAuAAQKfyMAAhwACQkzIc4mAGgCABwACQkzIc4mAGgCAAAA.Valoras:BAAALgADCgEJAQAAAA==.Valrith:BAABLgAECn8YAAIcAAcJIwc2zwD0AAAcAAcJIwc2zwD0AAAAAA==.Vardis:BAABLgAECn8uAAIKAAkJMh+SKgBwAgAKAAkJMh+SKgBwAgAAAA==.',
Ve='Velinami:BAAALgAECgIJAwAAAA==.Venato:BAAALgADCgEJBAABLgAECgkJNgADAH0OAA==.Vendettuh:BAAALgADCgEJAQAAAA==.Verazene:BAABLgAFFH8IAAIaAAMJrx3pBwD8AAAaAAMJrx3pBwD8AAAAAA==.Verenthirl:BAAALgAECgUJBAAAAA==.Veronica:BAABLgAECn88AAIKAAkJ/h6GFQDYAgAKAAkJ/h6GFQDYAgAAAA==.Verren:BAABLgAECn8rAAIBAAkJFBrYCQBMAgABAAkJFBrYCQBMAgAAAA==.Versutia:BAAALgAECgIJAgAAAA==.',
Vi='Virse:BAAALgAECgUJCQAAAA==.Virtigo:BAAALgADCgQJCAAAAA==.Vixie:BAAALgAECgcJBwAAAA==.',
Vy='Vye:BAAALgAECgEJAQAAAA==.Vyerith:BAABLgAECn8kAAITAAkJjhzwKAA4AgATAAkJjhzwKAA4AgAAAA==.',
Wa='Warsynth:BAAALgAECgEJAQABLgAECgkJJgAPAOYgAA==.',
We='Weltamus:BAABLgAECn8rAAMLAAkJABhJHAB4AQAGAAgJyg83dQB5AQALAAQJ9yBJHAB4AQAAAA==.Weltasaur:BAABLgAECn8fAAIBAAYJBhixHgBYAQABAAYJBhixHgBYAQAAAA==.Weltazar:BAABLgAECn82AAICAAkJrxcsJADFAQACAAkJrxcsJADFAQAAAA==.Westside:BAACLgAFFH8yAAMKAAkJeyRGAgAIAwAKAAkJeyRGAgAIAwAPAAEJqAndBwA5AAAuAAQKfyMAAgoACQnVJmcBAIsDAAoACQnVJmcBAIsDAAAA.',
Wi='Wickedfluff:BAAALgADCgYJBgAAAA==.Wickët:BAAALgAECgQJCAABLgAECgkJIAATAGsjAA==.Wildtiger:BAABLgAECn8zAAIoAAkJ5hgeCABQAgAoAAkJ5hgeCABQAgAAAA==.',
Wo='Wolfslied:BAAALgAECgYJCAAAAA==.',
Wr='Wrecken:BAAALgADCgUJBQAAAA==.',
Wu='Wulfenhide:BAABLgAECn8zAAQgAAkJ8B5qAgC1AgAgAAkJ8B5qAgC1AgAHAAMJoAfkUACkAAAmAAEJeAVgDwArAAAAAA==.',
Wy='Wyzsky:BAAALgAECgEJBQABLgAECgkJNgADAH0OAA==.',
Xa='Xal:BAAALgADCgEJAQABLgAECgMJBQAIAAAAAA==.Xalreth:BAABLgAECn8hAAIFAAkJPg6YXAByAQAFAAkJPg6YXAByAQAAAA==.Xaviana:BAAALgAECgkJKgAAAQ==.',
Xc='Xcedrin:BAABLgAECn8fAAMSAAkJOQgiOwAmAQASAAgJOAciOwAmAQAOAAMJXwWBcQBhAAAAAA==.',
Xi='Xiangzhu:BAAALgAECgEJAQABLgAECgkJLwAEAIMeAA==.',
Ya='Yastinfect:BAABLgAECn8eAAIFAAkJ0BgPLwBAAgAFAAkJ0BgPLwBAAgAAAA==.Yastypoo:BAAALgAECgEJAQAAAA==.',
Yu='Yurika:BAEBLgAECn8xAAIiAAkJJibZBwAOAwAiAAkJJibZBwAOAwAAAA==.Yushi:BAABLgAECn8tAAIHAAkJlx/zCgB1AgAHAAkJlx/zCgB1AgAAAA==.',
Yv='Yväinne:BAAALgAECgIJAgAAAA==.',
Za='Zaketh:BAAALgADCgQJBAAAAA==.Zareen:BAAALgADCgkJCQAAAA==.Zaru:BAAALgADCgcJEwAAAA==.Zayfall:BAAALgAECgYJEwAAAA==.',
Ze='Zelenor:BAABLgAECn8nAAQGAAkJfxTJNgAkAgAGAAkJfxTJNgAkAgAnAAYJKQV3KQCIAAALAAQJYQOLSwBhAAAAAA==.Zenweaver:BAACLgAFFH8RAAIWAAMJVSS1HgA2AQAWAAMJVSS1HgA2AQAuAAQKfx8AAhYACQlqIlUEAEcDABYACQlqIlUEAEcDAAAA.',
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
