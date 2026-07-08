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

local lookup = {'Druid-Guardian','Shaman-Elemental','Shaman-Restoration','DemonHunter-Devourer','DeathKnight-Unholy','Rogue-Subtlety','Unknown-Unknown','Paladin-Protection','Evoker-Preservation','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Survival','Mage-Frost','Priest-Holy','Mage-Arcane','Warrior-Fury','Evoker-Augmentation','Priest-Shadow','Warlock-Demonology','Evoker-Devastation','Druid-Balance','Monk-Mistweaver','Monk-Windwalker','Druid-Restoration','Monk-Brewmaster','Warlock-Affliction','Shaman-Enhancement','Paladin-Retribution','Warrior-Arms','Hunter-Marksmanship','Warrior-Protection','Rogue-Assassination','Warlock-Destruction','Paladin-Holy','DemonHunter-Havoc','Priest-Discipline','Rogue-Outlaw','DemonHunter-Vengeance','DeathKnight-Frost','Druid-Feral',}
local provider = {region='US',realm='KulTiras',name='US',type='weekly',zone=46,date='2026-07-05',data={Aa='Aaissis:BAAALgAECgQJBAABLgAECgkJKwABABQaAA==.Aarix:BAABLgAECn8UAAICAAkJQRESKQCnAQACAAkJQRESKQCnAQAAAA==.',
Ae='Aedrelyn:BAAALgAECgcJDQAAAA==.Aegia:BAABLgAECn8ZAAMDAAcJrxCdVgBcAQADAAcJrxCdVgBcAQACAAMJTQGHgABFAAAAAA==.Aendillan:BAABLgAECn8TAAIEAAYJQxzHWwCOAQAEAAYJQxzHWwCOAQAAAA==.Aewrynn:BAAALgAECgIJAgAAAA==.',
Af='Affonasei:BAABLgAECn84AAIFAAkJTAzcXACxAQAFAAkJTAzcXACxAQAAAA==.',
Ai='Aicaramba:BAAALgAECgYJCgAAAA==.Aileen:BAAALgAFFAIJAgAAAA==.',
Ak='Akashi:BAAALgAFFAIJAwABLgAFFAUJFgAGAM4cAA==.',
Al='Alacrodie:BAAALgAECgMJBQAAAA==.Alladorn:BAAALgADCgEJAQAAAA==.Allarii:BAAALgAECgUJBQABLgAECgUJBQAHAAAAAA==.Allynoon:BAAALgADCgMJAwAAAA==.Alurynath:BAAALgADCgcJCQABLgAECgkJLwAIAIMeAA==.',
An='Anahla:BAAALgAECgUJBQABLgAECgkJOQAJAIIYAA==.Ancbow:BAAALgADCgUJBQAAAA==.Angrydisc:BAAALgADCgUJBQAAAA==.Angrytotems:BAAALgAECgYJBwAAAA==.Angyll:BAAALgADCgUJAQAAAA==.Annaborshen:BAAALgADCgcJCgAAAA==.Antoccino:BAABLgAECn8sAAIKAAkJ9yH1AwD6AgAKAAkJ9yH1AwD6AgAAAA==.',
Ar='Aragorno:BAABLgAECn8sAAMLAAkJrBdVJwBCAgALAAkJrBdVJwBCAgAMAAQJRAZgQgC6AAAAAA==.Araziel:BAAALgAECgMJBAAAAA==.Arcturen:BAABLgAECn85AAILAAkJYBzLAgBVAgALAAkJYBzLAgBVAgAAAA==.Arenthal:BAAALgAECgUJCgABLgAFFAQJCAANAEgUAA==.Arill:BAAALgADCgYJBgAAAA==.Arkulas:BAAALgAECgYJBwAAAA==.Artemisha:BAAALgADCgEJAQABLgAECgMJAwAHAAAAAA==.Arturaan:BAAALgAECgEJAQAAAA==.',
As='Ashalana:BAAALgAECgcJEAAAAA==.Asheby:BAAALgAECgIJAgABLgAECgkJOwAOAD8cAA==.Ashiera:BAABLgAECn8yAAMNAAkJ+gNSqgAqAQANAAkJ+gNSqgAqAQAPAAEJ7AHwIgATAAAAAA==.',
At='Atomic:BAABLgAECn8YAAIQAAkJ5QUcBwABAQAQAAkJ5QUcBwABAQAAAA==.',
Au='Aurorée:BAAALgAECgEJAQAAAA==.Ausuna:BAAALgAECgYJBwAAAA==.',
Av='Avelai:BAAALgADCgkJEgAAAA==.',
Aw='Awhiteboy:BAAALgAECgcJDgABLgAECgkJLQAGAJ8fAA==.',
Az='Azeral:BAAALgADCgYJBgAAAA==.Azylstrid:BAAALgAECgQJBAAAAA==.',
Ba='Babyshred:BAAALgAECgYJCAAAAA==.Badonka:BAAALgAECgQJBAABLgAECgkJSAARAG8eAA==.Bahaana:BAAALgAECgUJBgAAAA==.Balentine:BAACLgAFFH8HAAIOAAMJKxKnCwCnAAAOAAMJKxKnCwCnAAAuAAQKfx0AAw4ACAkxE+o6AAsBAA4ABwkCE+o6AAsBABIABQnHA/tHAMEAAAAA.Bananasloth:BAAALgAECgcJEQABLgAFFAkJUAATADwkAA==.Banjali:BAAALgADCgMJAwAAAA==.Banostraza:BAABLgAECn9IAAMRAAkJbx6/CQC8AgARAAkJyB2/CQC8AgAUAAEJ2RQxIgBFAAAAAA==.Baspir:BAABLgAECn8pAAIVAAkJNxbAJAClAQAVAAkJNxbAJAClAQAAAA==.',
Be='Beeboop:BAAALgAECgEJAQAAAA==.Belly:BAAALgAECgIJAgABLgAECgkJLQAGAJ8fAA==.Belrae:BAACLgAFFH8IAAIEAAIJ0QamiABxAAAEAAIJ0QamiABxAAAuAAQKfzYAAgQACQlSF78lADcCAAQACQlSF78lADcCAAAA.Belrinthe:BAAALgAFFAIJBAAAAA==.Berenzen:BAAALgAECgEJAQAAAA==.Bethaliz:BAAALgAECgIJAgAAAA==.Bezieck:BAABLgAECn89AAISAAgJmBXwHgDOAQASAAgJmBXwHgDOAQAAAA==.',
Bi='Bigdawg:BAAALgAECggJEAAAAA==.Bigdeborah:BAAALgAECgUJBQAAAA==.Bigfolks:BAAALgADCgEJAQAAAA==.Bigollock:BAAALgAECgEJBAAAAA==.Billyhikz:BAABLgAECn8oAAINAAkJ8w3oYAC+AQANAAkJ8w3oYAC+AQAAAA==.Birdbrain:BAAALgAFFAIJAwAAAA==.Biru:BAAALgAFFAIJAgABLgAFFAQJCQAOAM8QAA==.',
Bl='Bloodarrow:BAAALgAECgYJEwAAAA==.',
Bo='Bobino:BAAALgADCgEJAQAAAA==.Bockchi:BAABLgAECn8YAAMWAAYJ5RcHOgCJAQAWAAYJ5RcHOgCJAQAXAAEJaRX3lAA7AAAAAA==.Bonegavel:BAAALgAECgUJBwAAAA==.Bookhuntress:BAABLgAECn8jAAQYAAcJ3RtAJgAfAgAYAAcJ3RtAJgAfAgAVAAYJ5xcsNABIAQABAAEJnAwahAAcAAAAAA==.Bordrann:BAAALgAECgIJAwAAAA==.Bosyoh:BAAALgAECgIJAgAAAA==.',
Br='Branaxe:BAAALgAECggJDwABLgAECgkJCAAHAAAAAA==.Brandisheer:BAAALgAECgYJCAAAAA==.Branpaw:BAAALgAECgEJAgABLgAECgkJCAAHAAAAAA==.Branthor:BAAALgADCgIJAgAAAA==.Brewdeez:BAACLgAFFH8JAAIXAAUJbAm3HwDaAAAXAAUJbAm3HwDaAAAuAAQKfzQAAhkACQktH7UIAKcCABkACQktH7UIAKcCAAAA.Brewzer:BAACLgAFFH8SAAIWAAQJuAvBNwDJAAAWAAQJuAvBNwDJAAAuAAQKfyUAAxYACAmEExs3AJcBABYACAmEExs3AJcBABcABQmtDBBYAK8AAAAA.Brick:BAAALgAECgUJBQAAAA==.Brint:BAABLgAECn8fAAMTAAgJNg+GawBlAQATAAgJMw+GawBlAQAaAAEJshNcOQBCAAAAAA==.Brok:BAABLgAECn8UAAIbAAgJPxqRCQAjAgAbAAgJPxqRCQAjAgAAAA==.Brokenhorn:BAAALgADCgYJGAAAAA==.Bronad:BAACLgAFFH8vAAINAAYJTCTuIQD2AQANAAYJTCTuIQD2AQAuAAQKfyIAAg0ACAkXJdEjAOMCAA0ACAkXJdEjAOMCAAAA.Bronst:BAAALgAECgEJAwABLgAECgkJMQACAOYYAA==.Broomhandle:BAABLgAECn8vAAIcAAkJySRZBgA+AwAcAAkJySRZBgA+AwAAAA==.',
Bu='Bubbletea:BAAALgAECgYJDAAAAA==.Bumbushka:BAACLgAFFH8eAAIQAAYJZh/JCgC2AQAQAAYJZh/JCgC2AQAuAAQKfxkAAxAABwl/IyskADUCABAABwl/IyskADUCAB0AAgnfGNcrAJUAAAEuAAUUBgkeABAAZh8A.Burinn:BAAALgAECgcJCgABLgAECgkJSAAOAFkPAA==.',
Ca='Caeus:BAABLgAECn8xAAIFAAkJnyRSBwA7AwAFAAkJnyRSBwA7AwAAAA==.Cam:BAABLgAECn8xAAINAAkJlCXtCwAZAwANAAkJlCXtCwAZAwAAAA==.Capriestson:BAAALgADCgkJCQABLgAECgYJDwAHAAAAAA==.Cardo:BAAALgADCgUJBQABLgAFFAgJFwAeAGgZAA==.Care:BAABLgAECn8ZAAINAAkJjAwciADBAQANAAkJjAwciADBAQAAAA==.Carolinabele:BAAALgAECgcJBQAAAA==.Carrowend:BAAALgAECgMJAwAAAA==.Cauud:BAABLgAECn8dAAIfAAYJ8RP4IwARAQAfAAYJ8RP4IwARAQAAAA==.',
Cb='Cbd:BAAALgADCgcJCAAAAA==.',
Ch='Chacruna:BAAALgAECgQJBAAAAA==.Charmed:BAAALgAECgUJBgAAAA==.Cheesús:BAAALgAECggJDAAAAA==.Chelan:BAABLgAECn9IAAMOAAkJWQ//IgCrAQAOAAkJWQ//IgCrAQASAAkJjgW7OgAoAQAAAA==.Chiji:BAAALgAECgYJBQAAAA==.Chilljaeden:BAAALgAECgUJDQAAAA==.Chizuko:BAAALgADCgMJAwAAAA==.Chuntspeed:BAAALgADCgYJEQAAAA==.Chuye:BAAALgAFFAEJAQABLgAFFAQJCQAOAM8QAA==.',
Ci='Cigs:BAAALgAECgYJBgABLgAFFAkJKQANAM4iAA==.Cindyloowhoo:BAAALgADCgMJAwAAAA==.Cinnabunz:BAABLgAECn8hAAITAAgJLQzzDgCwAAATAAgJLQzzDgCwAAAAAA==.Citorcen:BAAALgAECgEJAQAAAA==.',
Cl='Clambulance:BAAALgAECgcJBwABLgAFFAMJCQATAEMFAA==.Cleaväge:BAAALgADCgYJBgAAAA==.Cleurisse:BAABLgAFFH8VAAIKAAUJ5heSGAAjAQAKAAUJ5heSGAAjAQAAAA==.Cloudlol:BAAALgAECgQJBgAAAA==.Clueless:BAAALgADCgMJAwAAAA==.',
Cn='Cnova:BAAALgAECgUJDgABLgAECgkJOwAcAHsgAA==.',
Co='Codythedead:BAABLgAFFH8GAAIFAAIJ7RQd3ACHAAAFAAIJ7RQd3ACHAAAAAA==.Compadre:BAABLgAECn8XAAQXAAgJPh7NHQDrAQAXAAcJ0RrNHQDrAQAZAAQJUiAiRAAyAQAWAAYJWxE4RADMAAAAAA==.Contekst:BAABLgAECn8iAAMYAAgJQA8XWQAtAQAYAAgJQA8XWQAtAQAVAAcJxAaoVwCzAAAAAA==.Coolsbeans:BAAALgAECgYJCwAAAA==.Coraf:BAACLgAFFH8sAAIDAAgJCSDXAwCWAgADAAgJCSDXAwCWAgAuAAQKfzgAAgMACQkAJMABAHQDAAMACQkAJMABAHQDAAAA.',
Cr='Crankzilla:BAAALgADCggJFgAAAA==.Cravix:BAAALgADCgYJBgAAAA==.Cruoris:BAABLgAECn8bAAIgAAcJww2MDwArAQAgAAcJww2MDwArAQAAAA==.',
Cu='Cunfuzed:BAAALgAECgEJAQAAAA==.Cuvier:BAABLgAECn8hAAIgAAcJMQVrEwDxAAAgAAcJMQVrEwDxAAAAAA==.',
Da='Daddle:BAABLgAECn8gAAQTAAkJayNrDwDRAgATAAkJ5iFrDwDRAgAaAAYJWSIkCgC+AQAhAAEJAADTVAAAAAAAAA==.Daemonxblack:BAAALgAECgEJAQAAAA==.Daeth:BAAALgAECgMJBQAAAA==.Daeththane:BAAALgAECgEJAQAAAA==.Dahaxors:BAABLgAECn8lAAIFAAkJGxvOLwBAAgAFAAkJGxvOLwBAAgAAAA==.Dalareas:BAAALgAECgMJAwAAAA==.Danak:BAAALgAECgIJBAAAAA==.Dannika:BAAALgAECgYJBwAAAA==.Dantelous:BAAALgAECgEJAgAAAA==.Darthwader:BAAALgAECgUJCAAAAA==.Dascrazy:BAABLgAECn8mAAMGAAgJNgwMJQBtAQAGAAgJ4AsMJQBtAQAgAAUJNAe/FwC4AAAAAA==.Daynaa:BAAALgAECgYJCwABLgAECggJGgAiADYTAA==.',
De='Deadlyfrosty:BAABLgAECn8ZAAIFAAYJWQMXEAGYAAAFAAYJWQMXEAGYAAAAAA==.Deathsfather:BAAALgADCgYJBgABLgAECgcJEwAHAAAAAA==.Debixie:BAACLgAFFH8SAAIgAAQJyB3eAgB8AQAgAAQJyB3eAgB8AQAuAAQKfyUAAiAACQlLI04BACUDACAACQlLI04BACUDAAAA.Dejection:BAAALgAECgEJAQAAAA==.Delron:BAAALgADCgEJAQAAAA==.Demisi:BAAALgAECgcJEwAAAA==.Demoness:BAABLgAECn8iAAMEAAkJQSK0FQCWAgAEAAgJZCK0FQCWAgAjAAEJTCFiVwBgAAAAAA==.Demsynth:BAAALgAECgQJBAABLgAECgkJJgAPAOYgAA==.Derangedsp:BAAALgADCgkJCQABLgAFFAkJUAATADwkAA==.Destorr:BAAALgADCgQJBAAAAA==.Dextero:BAAALgADCgMJAwAAAA==.',
Di='Diasundra:BAABLgAECn8sAAILAAkJ5h9NDgDKAgALAAkJ5h9NDgDKAgAAAA==.Digiornos:BAABLgAECn8jAAITAAkJqhRCPQDnAQATAAkJqhRCPQDnAQAAAA==.',
Dj='Djyinn:BAAALgADCgcJCgAAAA==.',
Do='Doorknob:BAAALgAECgYJCQAAAA==.Dottingyou:BAACLgAFFH8mAAMTAAgJXRQmJwCrAQATAAcJ3RYmJwCrAQAhAAEJXQWVIwBOAAAuAAQKfzUAAxMACQnvHw4QAMwCABMACQnvHw4QAMwCACEAAwlMHzYsAA4BAAAA.',
Dr='Draenei:BAAALgAECgEJAQAAAA==.Draeziq:BAAALgAECgEJAgABLgAECggJGgAiADYTAA==.Dragonpo:BAAALgAECgEJAQAAAA==.Drakkonde:BAABLgAECn8bAAITAAYJUhafegBEAQATAAYJUhafegBEAQAAAA==.Dravin:BAAALgADCgYJBgAAAA==.Drazarth:BAAALgAECgUJDQAAAA==.Dreamon:BAAALgAFFAEJAwAAAA==.Droplet:BAAALgAECgQJBAABLgAFFAIJBQAWAAEfAA==.Drransom:BAAALgAECgEJAgAAAA==.Dryan:BAAALgAECgYJEwAAAA==.Dryon:BAABLgAECn82AAIfAAkJPB9TBQDEAgAfAAkJPB9TBQDEAgAAAA==.',
Du='Duergan:BAAALgADCgEJAQAAAA==.Duo:BAABLgAECn8xAAILAAkJXBNgRwDMAQALAAkJXBNgRwDMAQAAAA==.Duragon:BAABLgAECn8yAAQRAAkJ7RbBGAARAgARAAkJ7RbBGAARAgAUAAgJPwUoFgCyAAAJAAYJPwdHJwCxAAAAAA==.',
['Dí']='Díznutz:BAABLgAECn8OAAIEAAYJ6RBJeAA+AQAEAAYJ6RBJeAA+AQABLgAFFAMJBQALAFsaAA==.',
El='Eldumir:BAAALgADCgIJBAABLgAECgkJLwAIAIMeAA==.Elyleath:BAAALgAECgYJBgAAAA==.',
Em='Emilia:BAABLgAECn8pAAMOAAkJHAwhBQAiAQAOAAkJHAwhBQAiAQAkAAEJtwaRGAAnAAAAAA==.Empanada:BAAALgADCgEJAQAAAA==.',
En='Endressa:BAABLgAECn8yAAMkAAkJPw8rGwD2AQAkAAkJPw8rGwD2AQASAAIJTw8jFABFAAAAAA==.English:BAABLgAECn8zAAINAAkJdBu8NwA5AgANAAkJdBu8NwA5AgAAAA==.',
Er='Erelios:BAABLgAECn8vAAIIAAkJgx5iBQCbAgAIAAkJgx5iBQCbAgAAAA==.Erubus:BAAALgADCgUJCAAAAA==.',
Es='Eski:BAAALgAECgEJAwAAAA==.',
Eu='Eureka:BAEALgAECgMJCAABLgAECgkJMQAiACYmAA==.',
Ev='Everlight:BAAALgAECgQJBQABLgAECgkJJgABAM0TAA==.Evileyes:BAAALgADCgMJAgAAAA==.',
Ey='Eyezoffury:BAAALgAECgIJAgAAAA==.',
Ez='Ezrì:BAAALgAECgMJBQAAAA==.',
Fa='Faddeyshnek:BAABLgAECn8oAAILAAkJSxZTOwDyAQALAAkJSxZTOwDyAQAAAA==.Fastbeefball:BAAALgADCggJDAAAAA==.Fatgirljuice:BAAALgADCgMJAwABLgAFFAkJLQARANsbAA==.',
Fe='Feliseda:BAAALgADCgkJCwAAAA==.Felorianis:BAAALgADCgEJAQABLgAECgkJOgAEAKkeAA==.Felysambre:BAAALgAECgkJEgAAAA==.',
Fi='Filibertos:BAABLgAFFH8FAAIEAAUJehftEwAwAQAEAAUJehftEwAwAQABLgAFFAkJKQANAM4iAA==.Fish:BAACLgAFFH82AAISAAgJ4iaDAAApAwASAAgJ4iaDAAApAwAuAAQKfzcAAhIACAmOJlYCAIwDABIACAmOJlYCAIwDAAEuAAUUCQlPABIApiYA.',
Fl='Flight:BAACLgAFFH8WAAMGAAUJzhy5GABMAQAGAAUJzhy5GABMAQAlAAIJ9BX9CwCkAAAuAAQKfx0AAwYACAkRHHcUAG8CAAYACAljG3cUAG8CACAAAQkBDiweADwAAAAA.Fluxyouup:BAABLgAECn8gAAMDAAkJmghnVwBZAQADAAkJmghnVwBZAQACAAYJCQXWaACsAAAAAA==.Fløki:BAAALgAECgIJAgAAAA==.',
Fo='Follow:BAAALgAECgQJBQAAAA==.Forsynth:BAABLgAECn8mAAMPAAkJ5iDWAADgAgAPAAkJ5iDWAADgAgANAAEJAABIdQEwAAAAAA==.',
Fr='Frrostitute:BAAALgADCgEJAQAAAA==.',
Ge='Gewitt:BAABLgAECn8tAAMDAAkJgh4cFgCZAgADAAkJgh4cFgCZAgACAAgJ2hnYKADNAQAAAA==.',
Gg='Ggiven:BAABLgAECn8XAAIEAAcJjRJCYQBmAQAEAAcJjRJCYQBmAQAAAA==.',
Gl='Glinda:BAAALgAECgIJBAAAAA==.',
Gn='Gnow:BAAALgADCgEJAQAAAA==.',
Go='Gonjah:BAAALgAECgcJBwAAAA==.',
Gr='Grabomage:BAACLgAFFH8tAAINAAgJyR1BBgBZAgANAAgJyR1BBgBZAgAuAAQKf1oAAg0ACQkmJlIDAMoDAA0ACQkmJlIDAMoDAAAA.Grag:BAAALgADCgMJBQAAAA==.Grapekoolaid:BAAALgAECgYJDwAAAA==.Grapesloth:BAAALgAECgQJBAABLgAFFAkJUAATADwkAA==.Grazienne:BAAALgAECgIJBAAAAA==.Greavos:BAAALgAECgEJAgABLgAECgkJPQANAI0hAA==.Gretchen:BAAALgADCgUJBQAAAA==.Grif:BAAALgADCgMJAwAAAA==.Grilm:BAABLgAECn8tAAIBAAkJhx/oBQCnAgABAAkJhx/oBQCnAgAAAA==.Grimbaine:BAABLgAECn84AAIcAAkJCCMjCAAqAwAcAAkJCCMjCAAqAwAAAA==.Grimbane:BAAALgAECgMJBAAAAA==.Grimgar:BAAALgAECgEJAQAAAA==.Grimmshady:BAAALgAECgMJBQAAAA==.Grizzlegrimm:BAAALgAECgEJAgAAAA==.Groot:BAAALgAECgkJAQAAAA==.Gryphin:BAAALgADCgcJBwAAAA==.',
Gu='Gulmok:BAAALgADCgUJDQAAAA==.Gumbles:BAACLgAFFH8JAAIOAAQJzxA7DACeAAAOAAQJzxA7DACeAAAuAAQKfygABA4ACQlUHWgRAFcCAA4ACQlUHWgRAFcCACQAAglJB3tuAE4AABIAAQnUA5dnACoAAAAA.Gurney:BAABLgAECn8qAAMiAAkJ/hauHQAWAgAiAAkJ/hauHQAWAgAIAAEJggQxWQAdAAAAAA==.Guzfu:BAABLgAECn8UAAIXAAcJgg1jSgDYAAAXAAcJgg1jSgDYAAAAAA==.Guzprimal:BAAALgAECgEJAQABLgAECgcJFAAXAIINAA==.',
Gw='Gwenory:BAAALgAECgEJAQAAAA==.',
Gy='Gying:BAABLgAECn9EAAMZAAkJhR3KAABGAgAZAAkJhR3KAABGAgAXAAUJcg8FQAAZAQAAAA==.',
Ha='Hanjabs:BAAALgAECgYJDgAAAA==.Hanmine:BAAALgAECgYJDQAAAA==.Hannie:BAAALgAECgIJBAAAAA==.Happyelf:BAAALgAECgYJDgAAAA==.Hartephinar:BAAALgAECgEJAQAAAA==.Hatike:BAAALgAECgEJAQAAAA==.',
He='Headhúnter:BAACLgAFFH8FAAILAAMJWxouWgDxAAALAAMJWxouWgDxAAAuAAQKfxgAAgsACQlYH0ARAMcCAAsACQlYH0ARAMcCAAAA.Heatseeka:BAABLgAECn8YAAIDAAgJFw5AWQBSAQADAAgJFw5AWQBSAQAAAA==.Hexxiz:BAAALgAECggJDQABLgAECgkJPQAYAB4kAA==.',
Hi='Hiphopinator:BAABLgAECn8vAAMQAAkJLyWHBgD2AgAQAAkJCSOHBgD2AgAfAAcJHCWGDwDwAQAAAA==.',
Ho='Holydeath:BAAALgAECgEJAQAAAA==.Holyshock:BAABLgAECn8UAAIiAAcJrRcIMACaAQAiAAcJrRcIMACaAQAAAA==.Holyterror:BAAALgAECgIJBAAAAA==.Honeysweety:BAAALgADCgMJAwAAAA==.',
Hy='Hydril:BAAALgADCgEJAQAAAA==.',
['Hø']='Hødør:BAAALgAECgQJCwAAAA==.',
Ia='Iamcro:BAAALgAECgUJBgAAAA==.Ianthe:BAABLgAECn83AAIPAAkJ8AvTAABJAQAPAAkJ8AvTAABJAQAAAA==.',
Ib='Iboga:BAAALgAECgUJBwAAAA==.Ibrahimovic:BAABLgAECn80AAQhAAcJryPdCwCBAQAhAAUJHCTdCwCBAQAaAAYJURlGDwBoAQATAAQJjB1qfABAAQAAAA==.',
Ig='Ignitecro:BAAALgADCgUJBQAAAA==.Igram:BAAALgAECgQJBAAAAA==.',
Ih='Iheal:BAAALgADCgcJCgAAAA==.',
Il='Illidoonger:BAAALgAECgYJDwAAAA==.',
Im='Imauggin:BAAALgADCgYJBgAAAA==.Imbobbymom:BAAALgAECgEJAgABLgAFFAkJLQARANsbAA==.Imhim:BAAALgAECgEJAQAAAA==.',
In='Inafume:BAAALgAECgcJDQAAAA==.Infoxicated:BAAALgAECgUJCgABLgAECgYJCAAHAAAAAA==.Inoxia:BAAALgAECgQJBgAAAA==.Intrépidice:BAAALgAECgQJBwAAAA==.',
Io='Iowastyle:BAABLgAECn84AAMOAAkJHSC7BQAdAwAOAAkJHSC7BQAdAwAkAAMJlgx+QwCZAAAAAA==.',
It='Ithruyn:BAAALgADCgQJBAAAAA==.',
Ix='Ixtabay:BAACLgAFFH8dAAMaAAYJLRcTAQBSAQAaAAUJfhwTAQBSAQATAAIJvgdPyABCAAAuAAQKfzoABBoACQn0Ia8EAE8CABoACQmXIa8EAE8CABMABgnBGmYHADIBACEAAgm6EoBTAHQAAAAA.',
Ja='Jakobey:BAAALgAECgQJBQAAAA==.Jamurra:BAAALgAECgUJEAABLgAECggJGgAiADYTAA==.Jaylinn:BAABLgAECn8uAAILAAkJ4Q3TVAClAQALAAkJ4Q3TVAClAQAAAA==.Jazzmend:BAAALgADCgEJAQAAAA==.',
Je='Jeanne:BAAALgAECgYJBwAAAA==.Jezebel:BAAALgAECgUJBQABLgAECgkJOQAJAIIYAA==.',
Ji='Jimsonweed:BAAALgAECgYJEAAAAA==.',
Jo='Jocko:BAAALgADCgYJBgAAAA==.Josie:BAABLgAECn8pAAIkAAkJFiRcBABPAwAkAAkJFiRcBABPAwAAAA==.',
Ju='Judgekoopa:BAABLgAECn8qAAIiAAkJcx0rCwDaAgAiAAkJcx0rCwDaAgAAAA==.',
Ka='Kaadore:BAAALgAECgYJBwAAAA==.Kaeiria:BAAALgAECgUJCgAAAA==.Kael:BAAALgAECgEJAQAAAA==.Kalaanri:BAABLgAECn8xAAMCAAkJLxQyKACsAQACAAkJLxQyKACsAQADAAYJig6haQAfAQAAAA==.Kaleberry:BAABLgAECn8gAAMVAAkJBA6GJgCZAQAVAAgJBA6GJgCZAQAYAAcJEgmlhgDJAAAAAA==.Kalthyra:BAAALgAECgMJAwABLgAECgkJLwAIAIMeAA==.Kalyandra:BAABLgAECn8mAAIXAAcJdxBENAAyAQAXAAcJdxBENAAyAQAAAA==.Kalógeros:BAAALgADCgMJAwAAAA==.Kanhang:BAAALgADCgcJDAAAAA==.Kanra:BAABLgAECn8XAAQBAAYJ6RydFwCUAQABAAYJ6RydFwCUAQAYAAYJLgwzaQD5AAAVAAEJvBKCiQA4AAABLgAECgkJNgAIAH8iAA==.Karkevon:BAAALgAECgYJDgAAAA==.Karlach:BAABLgAECn8eAAIQAAkJAh0bFwA1AgAQAAkJAh0bFwA1AgAAAA==.Karlachs:BAAALgADCgYJBwAAAA==.Karrla:BAABLgAECn8rAAIEAAkJMRqnGQB7AgAEAAkJMRqnGQB7AgAAAA==.Karumie:BAABLgAECn8nAAIDAAkJZhyXHwBTAgADAAkJZhyXHwBTAgAAAA==.Kashyyk:BAAALgAECgMJAwABLgAECgkJQAATAJkaAA==.Kateera:BAAALgAECgUJCwAAAA==.',
Ke='Keden:BAAALgAECgMJBAAAAA==.Keelivan:BAAALgAECgMJAwAAAA==.Kelivann:BAAALgADCgUJBQAAAA==.Keljaden:BAABLgAECn8YAAIdAAkJwiA3AwACAwAdAAkJwiA3AwACAwABLgAECgkJLAAEAEEiAA==.Kels:BAABLgAECn8sAAIEAAkJQSL5DADdAgAEAAkJQSL5DADdAgAAAA==.',
Kh='Kheyra:BAABLgAECn8mAAIBAAkJzROLEgDJAQABAAkJzROLEgDJAQAAAA==.',
Ki='Kiaona:BAAALgADCgMJAwAAAA==.Kidashia:BAAALgAECgQJBAAAAA==.Kiwisloth:BAAALgAFFAEJAQABLgAFFAkJUAATADwkAA==.',
Ko='Koggs:BAAALgAFFAIJAgAAAA==.Kohnor:BAAALgAECgMJBQAAAA==.Kopi:BAAALgAECgMJBAABLgAECgkJLAAKAPchAA==.Kopiccino:BAAALgAECgEJAQABLgAECgkJLAAKAPchAA==.Korlatt:BAABLgAECn86AAQEAAkJqR7kEgCsAgAEAAkJQh3kEgCsAgAmAAMJDRxHFwDqAAAjAAMJOhZfVwBgAAAAAA==.Kowalabear:BAABLgAECn8rAAMnAAkJtCExAQD+AgAnAAkJtCExAQD+AgAKAAQJPwqaTQBbAAAAAA==.',
Kr='Kryptrix:BAAALgAECgQJBAAAAA==.Krìmzar:BAAALgADCggJCgABLgAECgYJFAANADgXAA==.',
Kt='Kthanid:BAABLgAECn8XAAIkAAYJdRTaMgBOAQAkAAYJdRTaMgBOAQAAAA==.',
Ku='Kurston:BAABLgAECn9DAAIYAAkJMRtoEwCwAgAYAAkJMRtoEwCwAgAAAA==.',
Ky='Kymakazie:BAABLgAECn8ZAAILAAkJrAP4mAAOAQALAAkJrAP4mAAOAQAAAA==.',
['Kã']='Kãtniss:BAAALgAECgEJAQAAAA==.',
La='Laih:BAABLgAECn8jAAIgAAkJgA+uCAC+AQAgAAkJgA+uCAC+AQAAAA==.Lasturus:BAAALgAECgUJBQABLgAFFAgJJQAWAGkZAA==.Lathelinis:BAAALgAECgcJCgAAAA==.Lauraenital:BAAALgAECgQJBAAAAA==.Layssara:BAAALgADCgMJAwAAAA==.',
Le='Leafbloom:BAAALgAECgEJAQABLgAECggJFgAZAHsYAA==.Letmeout:BAAALgAECgEJAQAAAA==.Lexx:BAAALgAECgIJAgAAAA==.Leyote:BAABLgAECn8/AAIDAAkJDBOiLAAGAgADAAkJDBOiLAAGAgAAAA==.',
Lh='Lhai:BAAALgAECgEJAQABLgAECgkJIwAgAIAPAA==.',
Li='Liady:BAAALgADCgcJDQAAAA==.Lightshop:BAAALgADCgIJAQAAAA==.Liirah:BAAALgAECgEJAQAAAA==.Linora:BAAALgAECgIJAQAAAA==.Listriesa:BAAALgADCgEJAQAAAA==.',
Lo='Lolabunny:BAABLgAECn8UAAMXAAYJZBofNABRAQAXAAUJkxYfNABRAQAZAAQJ+xkLRgAqAQABLgAECggJGAAKAOIiAA==.Lorianne:BAAALgAECgMJBAAAAA==.Lousseur:BAAALgADCgEJAgAAAA==.Lowdangle:BAABLgAECn8tAAIEAAkJtheTJQA3AgAEAAkJtheTJQA3AgAAAA==.',
Lu='Lulz:BAAALgAECgkJEwAAAA==.Lumini:BAABLgAECn8eAAMSAAkJ3AbqNABEAQASAAkJ3AbqNABEAQAOAAMJfwPyagA9AAAAAA==.Luminias:BAAALgAECgUJDQAAAA==.Luthein:BAAALgAECgcJEwAAAA==.Luxroy:BAAALgAECgYJEQAAAA==.',
Ly='Lygma:BAABLgAECn8jAAIcAAkJ/g6UZACmAQAcAAkJ/g6UZACmAQAAAA==.Lynniebee:BAABLgAECn8pAAIPAAkJjAwmBQCPAQAPAAkJjAwmBQCPAQAAAA==.',
Ma='Madalyn:BAAALgAECgcJEwAAAA==.Maexna:BAAALgAECgEJAQAAAA==.Magdelyne:BAAALgAECgkJDAAAAA==.Magicpie:BAAALgAECgcJBwABLgAECgkJPwAmANIkAA==.Magni:BAAALgAECgQJBQAAAA==.Makklehaney:BAABLgAECn8hAAMbAAkJTg5EEQCfAQAbAAkJTg5EEQCfAQACAAEJ7QFmlQAgAAAAAA==.Mallaah:BAAALgADCgYJCgAAAA==.Malthorin:BAAALgADCgMJAwAAAA==.Maneke:BAAALgADCgkJCQABLgAECgkJLwADAJcVAA==.Marovingian:BAABLgAECn8uAAIiAAkJ4yFYAwBsAwAiAAkJ4yFYAwBsAwAAAA==.Matthad:BAABLgAECn8vAAIDAAkJlxWIJwAiAgADAAkJlxWIJwAiAgAAAA==.Mazìkene:BAACLgAFFH8bAAMaAAUJQQ5nCQDjAAATAAQJ0gfraADzAAAaAAQJzxFnCQDjAAAuAAQKfygAAxoACQlEGZ0JAMkBABoABwnrGJ0JAMkBABMACQk2FgdSAKYBAAAA.',
Mc='Mccone:BAABLgAECn8ZAAILAAYJnQmtrwDlAAALAAYJnQmtrwDlAAAAAA==.Mcsluts:BAABLgAECn8jAAMcAAYJDhBuwgAFAQAcAAYJkw5uwgAFAQAIAAEJaBDqUwApAAAAAA==.Mcwild:BAAALgADCgUJCAAAAA==.',
Me='Megadumb:BAAALgAECgQJBAABLgAFFAkJLQARANsbAA==.Melmirict:BAACLgAFFH8TAAIGAAUJWBJgIAAiAQAGAAUJWBJgIAAiAQAuAAQKfyUAAwYACQlQGd0TAAQCAAYACQlQGd0TAAQCACAAAwmAGpQSANkAAAAA.Meng:BAAALgADCgYJBgAAAA==.Merciala:BAABLgAECn9DAAIBAAkJdRLfFwCSAQABAAkJdRLfFwCSAQAAAA==.',
Mi='Milyva:BAAALgADCgMJAwAAAA==.Milyyanna:BAAALgAECgMJBQAAAA==.Minaby:BAAALgAECgYJEAABLgAECgkJLwAcAMkkAA==.Missmurder:BAAALgAFFAEJAgAAAA==.Mitochondria:BAAALgADCgQJBAAAAA==.',
Mo='Moddoxx:BAABLgAECn9AAAQTAAkJmRruKgAuAgATAAgJSxzuKgAuAgAaAAIJkg6GPAA5AAAhAAIJuw4KPwAyAAAAAA==.Mohawk:BAABLgAECn8WAAIYAAkJjxL0AgC5AQAYAAkJjxL0AgC5AQAAAA==.Mohaxors:BAAALgADCgcJDwAAAA==.Moko:BAAALgAECgEJAgAAAA==.Mokopal:BAAALgADCgMJAwAAAA==.Mokøtrollz:BAABLgAECn8jAAMLAAkJrh9zOAD8AQAMAAgJmBnLEgASAgALAAgJIB5zOAD8AQAAAA==.Molen:BAAALgAECgYJCwAAAA==.Mommyjuice:BAAALgAFFAEJAQABLgAFFAkJLQARANsbAA==.Mommysbush:BAACLgAFFH8tAAMRAAkJ2xu2BQCrAgARAAkJ2xu2BQCrAgAUAAEJygr9CQBTAAAuAAQKfyoAAxEACQmjJfcBAGIDABEACQmjJfcBAGIDABQABgmRI78PAN8BAAEuAAUUCQktABEA2xsA.Monkeeh:BAAALgADCgUJCQAAAA==.Monkle:BAABLgAECn9QAAIXAAkJ/CTOAQBYAwAXAAkJ/CTOAQBYAwAAAA==.Monkoku:BAAALgAECgQJBAABLgAFFAUJDgAGAHcbAA==.Moonsii:BAABLgAECn8aAAIYAAkJ9Q1zPQCdAQAYAAkJ9Q1zPQCdAQAAAA==.Mooroth:BAABLgAECn9CAAIfAAkJPSBaBADhAgAfAAkJPSBaBADhAgABLgAFFAIJAgAHAAAAAA==.Morekk:BAAALgAECgEJAQAAAA==.Morozko:BAABLgAECn8eAAInAAgJShqLCAAEAgAnAAgJShqLCAAEAgAAAA==.',
Mu='Muddler:BAABLgAECn9CAAIhAAkJlAOlHADCAAAhAAkJlAOlHADCAAAAAA==.Muscuees:BAAALgADCgEJAQAAAA==.Mush:BAAALgAECgQJBAAAAA==.',
['Mà']='Màggles:BAAALgAECgQJBAAAAA==.',
Na='Nadd:BAABLgAECn8sAAILAAkJ/QqhDAAuAQALAAkJ/QqhDAAuAQAAAA==.Naledi:BAABLgAECn8cAAIVAAgJ5Q+/MwBKAQAVAAgJ5Q+/MwBKAQAAAA==.Nancy:BAAALgAECgQJBAAAAA==.Naomas:BAABLgAECn89AAMNAAkJjSGbEgDqAgANAAkJ9SCbEgDqAgAPAAIJ2R6aDAC1AAAAAA==.Narella:BAABLgAECn8tAAINAAgJjRQpZQCzAQANAAgJjRQpZQCzAQAAAA==.',
Ne='Needlepax:BAAALgAECgEJAgAAAA==.Negotiable:BAAALgAECgYJEAAAAA==.Negrido:BAABLgAECn8zAAQTAAkJ+yU2DwDTAgATAAgJwSI2DwDTAgAhAAMJNiWJJAA3AQAaAAEJvx9qMQBaAAAAAA==.Nei:BAABLgAECn9IAAIcAAgJjBuhBADeAQAcAAgJjBuhBADeAQAAAA==.Nemeton:BAAALgAECgIJAgAAAA==.Newt:BAAALgADCgUJBQAAAA==.Nezzarector:BAAALgAECgUJCwAAAA==.',
Ni='Nikem:BAABLgAECn82AAMVAAkJ6BnjEABWAgAVAAkJ6BnjEABWAgABAAEJ0wKQOwAPAAAAAA==.Nimseti:BAAALgAFFAEJAQAAAA==.',
No='Noelle:BAAALgAECgQJCQAAAA==.Nor:BAAALgAECgUJCgAAAA==.Noraelyn:BAABLgAECn8zAAMiAAkJ7xtHDQC9AgAiAAkJ7xtHDQC9AgAcAAQJewSqUAFeAAAAAA==.Norelei:BAAALgAECgUJBwABLgAECgkJJgABAM0TAA==.Noriyuki:BAABLgAECn8uAAIXAAcJDgKihgBMAAAXAAcJDgKihgBMAAAAAA==.Northside:BAAALgADCgQJBAABLgAFFAkJKQANAM4iAA==.Notkorlatt:BAAALgADCgIJAgAAAA==.',
Nu='Nugatory:BAACLgAFFH8IAAQMAAQJFhW0FgAbAQAMAAQJFhW0FgAbAQALAAEJFwaBqgBDAAAeAAEJwAH2PAAqAAAuAAQKfxcAAwwACAlSI1cKAHkCAAwACAlSI1cKAHkCAB4AAwnADI9pAJgAAAEuAAUUBgkJABIADwoA.Nuudles:BAAALgAECgEJAQAAAA==.',
Ny='Nyxahlia:BAAALgAECgYJEQAAAA==.',
Oa='Oakenia:BAAALgAECgEJAQABLgAECgkJOgAYAO8QAA==.',
Og='Ogkagìsttv:BAAALgAECgYJBwAAAA==.',
Ol='Olrong:BAABLgAECn9BAAIjAAkJlxOVFgDTAQAjAAkJlxOVFgDTAQAAAA==.Oluja:BAAALgAECgYJDwAAAA==.',
Om='Omegâ:BAABLgAFFH8HAAIEAAMJBATJLACMAAAEAAMJBATJLACMAAAAAA==.',
On='Onlypaws:BAAALgAECgYJEgAAAA==.Onuris:BAAALgAECgEJAQAAAA==.',
Op='Opaalite:BAAALgAECgMJAwAAAA==.Opacuslupus:BAAALgAECggJEAAAAA==.Ophel:BAAALgADCgYJBgABLgAECgkJOQAJAIIYAA==.Oppcookies:BAAALgAECgYJDwABLgAECgkJIwALALkYAA==.Oppressin:BAAALgAECgEJAQABLgAECgkJIwALALkYAA==.Oppshot:BAABLgAECn8jAAMLAAkJuRiaKgAzAgALAAkJuRiaKgAzAgAeAAEJUAnlPgAsAAAAAA==.',
Or='Orin:BAAALgAECgEJAQAAAA==.',
Os='Oshìe:BAACLgAFFH8FAAIiAAMJFxE+MwCjAAAiAAMJFxE+MwCjAAAuAAQKfykAAiIACQnbIVAMALgCACIACQnbIVAMALgCAAAA.',
Ov='Overdoom:BAABLgAECn82AAMFAAkJYx7KKgBVAgAFAAkJYx7KKgBVAgAKAAUJHAb3QwB/AAAAAA==.',
Pa='Packapipe:BAAALgADCggJEgAAAA==.Paladinjohn:BAACLgAFFH8pAAIcAAgJJSGMCgAwAgAcAAgJJSGMCgAwAgAuAAQKfysAAhwACQkbJWMBANEDABwACQkbJWMBANEDAAAA.Palykat:BAABLgAECn81AAIcAAkJBAmYCgA+AQAcAAkJBAmYCgA+AQAAAA==.Paradox:BAAALgAECgEJAQAAAA==.',
Pe='Pelagos:BAAALgAECggJCgAAAA==.Pennywisé:BAABLgAECn8rAAIFAAkJUyBAGwCjAgAFAAkJUyBAGwCjAgAAAA==.Percentguy:BAAALgAECgMJAwAAAA==.Pessimal:BAAALgADCgEJAQABLgAECgkJIgAFAEMfAA==.',
Ph='Phillygg:BAAALgAECgQJBAAAAA==.Phoeniix:BAABLgAECn8mAAMBAAkJiBeLEwC9AQABAAkJ4haLEwC9AQAVAAQJvRe1UgDcAAAAAA==.',
Pl='Plaguegying:BAABLgAECn8eAAMFAAkJnA+CZgCaAQAFAAgJ8w+CZgCaAQAKAAEJOQ3gWQA6AAABLgAECgkJRAAZAIUdAA==.Ploofee:BAAALgAECgkJEQAAAA==.',
Po='Porker:BAAALgADCgEJAQAAAA==.',
Pr='Prog:BAAALgAECgEJAQAAAA==.Progresz:BAABLgAECn8WAAINAAkJwRBLYAC/AQANAAkJwRBLYAC/AQAAAA==.',
Ps='Psichosa:BAAALgAECggJDgAAAA==.Psychosis:BAAALgADCgQJAwAAAA==.',
Py='Pykel:BAABLgAECn8nAAIVAAkJ2QmpOQAsAQAVAAkJ2QmpOQAsAQAAAA==.Pyrexea:BAAALgADCgYJBgAAAA==.Pyrivia:BAAALgAECgEJAgABLgAECgUJCgAHAAAAAA==.',
Qa='Qaren:BAABLgAECn8XAAIcAAYJFgirCgGrAAAcAAYJFgirCgGrAAAAAA==.',
Qi='Qikeyy:BAAALgAECgEJAQAAAA==.',
Qu='Quadraxis:BAAALgADCgcJCQAAAA==.',
Ra='Raethe:BAAALgAECgQJBAAAAA==.Raishun:BAAALgAECgMJAwAAAA==.Raizo:BAAALgADCgEJAQAAAA==.Rajak:BAAALgADCgEJAQAAAA==.Rake:BAABLgAECn80AAQoAAkJVSCbBgB8AgAoAAkJFB+bBgB8AgABAAEJQh1IYABPAAAVAAIJ6wcegABIAAAAAA==.Raminthórn:BAAALgADCgIJAgAAAA==.Rannï:BAACLgAFFH8GAAINAAMJyAp7jQC+AAANAAMJyAp7jQC+AAAuAAQKfxUAAg0ACAkiFPxeAMMBAA0ACAkiFPxeAMMBAAEuAAUUBgkdABoALRcA.Raskreia:BAAALgAFFAMJAwABLgAFFAYJHQANAOIiAA==.Ratabi:BAAALgADCgIJAgAAAA==.Ravana:BAAALgADCggJCAAAAA==.Ravna:BAABLgAECn8YAAMCAAgJ+A88BQApAQACAAgJ+A88BQApAQADAAQJCgYnpACFAAABLgAECgkJOwAVADYcAA==.Rawk:BAAALgAECgYJBgAAAA==.Rawrski:BAAALgADCgEJAgABLgAECgkJNgADAH0OAA==.',
Re='Reavert:BAAALgADCgYJBgAAAA==.Reeven:BAAALgAECgkJNgAAAQ==.Reshii:BAAALgAECgEJAQABLgAECgkJQAATAJkaAA==.Ressurectjin:BAAALgAECgUJDgAAAA==.Rexmortis:BAAALgAECgkJAgAAAA==.',
Rh='Rhaistlin:BAAALgADCgMJAwAAAA==.Rhcpmage:BAACLgAFFH8NAAINAAQJUSL0RwBUAQANAAQJUSL0RwBUAQAuAAQKfxwAAg0ACQmKIVsWANMCAA0ACQmKIVsWANMCAAAA.Rhetegast:BAABLgAECn8oAAIIAAkJrRPHDwDIAQAIAAkJrRPHDwDIAQAAAA==.Rhymaek:BAAALgAECgYJCQABLgAECggJGgAiADYTAA==.Rhyss:BAAALgAECgQJBAAAAA==.',
Ri='Rike:BAEBLgAECn9AAAMcAAkJ+iJjHwCLAgAcAAkJ5SFjHwCLAgAIAAYJlB4DEQC0AQAAAA==.Rinde:BAAALgADCgkJCQAAAA==.Riobla:BAAALgAECgQJBwAAAA==.',
Ro='Roflbackpack:BAAALgAECgkJBwAAAA==.Roflbalanced:BAAALgAECgQJCAAAAA==.Roflgotnerfd:BAAALgADCgMJAwABLgAECgkJBwAHAAAAAA==.Roflhazotime:BAABLgAECn8nAAIEAAkJVyOWCQD/AgAEAAkJVyOWCQD/AgAAAA==.Roland:BAABLgAECn80AAMYAAkJyhOgMADfAQAYAAkJyhOgMADfAQAVAAYJVgx5TQDWAAAAAA==.Rolandin:BAABLgAECn9AAAIiAAkJ1RfYEgB6AgAiAAkJ1RfYEgB6AgAAAA==.Rollaen:BAAALgADCgYJDAAAAA==.Rollan:BAAALgAECgUJDAAAAA==.Rook:BAABLgAFFH8JAAIGAAQJfxRoGwA+AQAGAAQJfxRoGwA+AQABLgAFFAgJLAADAAkgAA==.Roscjou:BAABLgAECn8YAAICAAcJsQT3YADCAAACAAcJsQT3YADCAAAAAA==.Ross:BAAALgAECgYJDwAAAA==.',
Ru='Rubisco:BAAALgAECgYJCwAAAA==.Ruh:BAAALgAECgMJBgABLgAECgkJQAATAJkaAA==.',
Ry='Rylagosa:BAABLgAECn85AAMJAAkJghiJDwDTAQAJAAcJNxiJDwDTAQARAAkJZRIEJgCwAQAAAA==.Rynehardt:BAAALgADCgcJBwAAAA==.Ryuji:BAAALgAECgEJAQAAAA==.Ryzesmidge:BAABLgAECn8XAAINAAkJGRHYWQDQAQANAAkJGRHYWQDQAQAAAA==.',
['Rê']='Rêdrum:BAABLgAFFH8IAAIFAAMJ3guYSQCRAAAFAAMJ3guYSQCRAAABLgAFFAUJGwAaAEEOAA==.',
Sa='Sabithia:BAAALgAECgEJAQAAAA==.Sahathiel:BAAALgAFFAIJAwAAAA==.Salandria:BAAALgAECgYJEAAAAA==.Salandriath:BAAALgAECgYJCwAAAA==.Sange:BAAALgAECgcJDQAAAA==.Sarionian:BAABLgAECn86AAIYAAkJ7xDmMgDTAQAYAAkJ7xDmMgDTAQAAAA==.Sarvin:BAAALgADCgcJBwABLgAECgkJKwADAEscAA==.Sarvinblue:BAABLgAECn8rAAMDAAkJSxxAFgCYAgADAAkJSxxAFgCYAgACAAMJLQ8SagCbAAAAAA==.Satrathen:BAAALgADCgYJBgAAAA==.Saucestash:BAAALgAECgIJAgAAAA==.Sauronic:BAAALgAECgYJCgAAAA==.',
Sc='Scopolamine:BAAALgADCgEJAQAAAA==.',
Se='Searchlights:BAAALgAECgYJCwAAAA==.Seshu:BAAALgAECgEJAQAAAA==.Sevrin:BAAALgADCgEJAQAAAA==.',
Sh='Shambúlance:BAAALgAECgMJAwAAAA==.Shanaynay:BAAALgAECgQJBAAAAA==.Shanir:BAAALgADCgMJAwAAAA==.Shanksie:BAABLgAECn8bAAIgAAcJkAaDEwDwAAAgAAcJkAaDEwDwAAAAAA==.Shazlulu:BAABLgAECn8pAAIDAAkJ1RgaBADEAQADAAkJ1RgaBADEAQAAAA==.Shedoa:BAAALgAECgYJBgAAAA==.Shiftywelt:BAAALgADCggJDAAAAA==.Shinmothee:BAABLgAECn8iAAIPAAkJkApWBgBeAQAPAAkJkApWBgBeAQAAAA==.Shinsura:BAAALgADCgcJEAAAAA==.Shtamman:BAAALgADCgUJBQAAAA==.',
Si='Silvantis:BAAALgADCgEJAQAAAA==.Siobhán:BAABLgAECn8tAAIGAAkJnx8LDwA7AgAGAAkJnx8LDwA7AgAAAA==.',
Sk='Skandle:BAAALgADCgMJAwAAAA==.',
Sl='Sleepypanda:BAABLgAECn8jAAIiAAkJtxnWFQBdAgAiAAkJtxnWFQBdAgAAAA==.Sloe:BAABLgAECn87AAMOAAkJPxyFDQCOAgAOAAkJPxyFDQCOAgASAAEJrAXjlAAlAAAAAA==.',
Sm='Smokalot:BAAALgADCgEJAQAAAA==.',
Sn='Sneakez:BAAALgAFFAEJAQAAAA==.',
So='Somebody:BAAALgAECgQJBQAAAA==.Soulitude:BAAALgAECgEJAQAAAA==.Southerngal:BAAALgADCgQJBQAAAA==.',
Sp='Speedbeefbal:BAAALgADCgQJBAAAAA==.Speedkweef:BAABLgAFFH8FAAISAAMJTQIpEQCIAAASAAMJTQIpEQCIAAAAAA==.Speedmeat:BAABLgAECn8gAAMDAAkJ8gi1ZAAtAQADAAgJxAi1ZAAtAQACAAIJmAO/nQA+AAAAAA==.Spinny:BAAALgAECgYJBgAAAA==.Sporkulous:BAACLgAFFH8GAAILAAMJbAcrNQCVAAALAAMJbAcrNQCVAAAuAAQKfy8AAwsACAl/E1BKAMIBAAsACAl/E1BKAMIBAB4AAQkXARRIABAAAAAA.',
Sq='Squal:BAABLgAECn87AAMcAAkJeyCuEADhAgAcAAkJeyCuEADhAgAIAAUJ/BhSGwA9AQAAAA==.Squiggle:BAABLgAECn89AAIIAAkJjSJMAgASAwAIAAkJjSJMAgASAwAAAA==.',
St='Stalkêr:BAAALgADCgIJAgAAAA==.Steevii:BAAALgADCgEJAQAAAA==.Stewie:BAAALgAECgEJAQAAAA==.Stewy:BAAALgAECgYJCAAAAA==.Stickybunz:BAABLgAECn8ZAAIQAAgJURUDJgDIAQAQAAgJURUDJgDIAQABLgAFFAQJDwASAHAFAA==.Striker:BAEALgAECgQJDwABLgAECgkJQAAcAPoiAA==.Strombone:BAAALgADCgEJAgABLgAECgIJEAAHAAAAAA==.Stunseed:BAABLgAECn8rAAIBAAkJ1hhFCwAuAgABAAkJ1hhFCwAuAgAAAA==.',
Su='Sumo:BAAALgAECgEJAQAAAA==.Sungjinwu:BAAALgAECgUJBQAAAA==.Sunnmage:BAAALgAECgcJCAAAAA==.Sunshíne:BAABLgAECn8qAAMIAAkJPxGjAQCqAQAIAAkJPxGjAQCqAQAcAAgJQQfKsAAeAQAAAA==.Surf:BAABLgAECn8XAAIEAAcJWRxlNAD1AQAEAAcJWRxlNAD1AQABLgAFFAEJAgAHAAAAAA==.',
Sw='Sweetbunz:BAACLgAFFH8PAAMSAAQJcAW1JQDLAAASAAQJcAW1JQDLAAAOAAQJAAnwHQDJAAAuAAQKfzoAAxIACQnHFpYXAAsCABIACQnHFpYXAAsCAA4ACAlYDjMxAEgBAAAA.Swegin:BAAALgAECgIJAgABLgAECgIJBAAHAAAAAA==.',
Sx='Sxes:BAAALgAECgYJDAAAAA==.',
Sy='Synaminaphyn:BAAALgAECgEJAQAAAA==.Syver:BAABLgAECn8pAAMFAAkJ2BkHRwDtAQAFAAgJGxsHRwDtAQAKAAEJCRG+WAA9AAAAAA==.',
['Sì']='Sìrfuzywuzy:BAAALgAECgYJDwAAAA==.',
['Sí']='Sírlancealot:BAAALgADCgYJBgABLgAECgYJDwAHAAAAAA==.',
Ta='Taisty:BAAALgADCgQJBAAAAA==.Takers:BAAALgAECgYJCgAAAA==.Tanagra:BAAALgAECgEJAQABLgAECgkJQAATAJkaAA==.Taniss:BAABLgAECn8pAAIlAAkJlQioCwBcAQAlAAkJlQioCwBcAQAAAA==.Tanner:BAABLgAECn8dAAMeAAgJDgnESgAnAQAeAAgJwQfESgAnAQALAAIJoBF5ogCHAAAAAA==.Tarnaby:BAAALgAECgEJAQAAAA==.',
Te='Teboe:BAAALgAECgYJBwAAAA==.Tedman:BAABLgAECn8vAAMCAAkJjRlTEwBTAgACAAkJjRlTEwBTAgADAAMJmgdWjwBaAAAAAA==.Tekki:BAAALgADCgEJAQAAAA==.Temel:BAABLgAECn82AAMDAAkJfQ5DTgB4AQADAAgJtwxDTgB4AQACAAkJUw07NABqAQAAAA==.Tenelum:BAAALgAECgQJCgABLgAECgkJNgADAH0OAA==.Testoecles:BAAALgAECgMJBQABLgAECgYJBwAHAAAAAA==.',
Th='Thadrack:BAABLgAECn85AAINAAkJuQm2fQB8AQANAAkJuQm2fQB8AQAAAA==.Thaine:BAAALgADCgEJAQABLgAECgcJDQAHAAAAAA==.Thalonstin:BAAALgAECgQJCQAAAA==.Thanee:BAABLgAFFH8IAAIOAAUJFRM8FAAjAQAOAAUJFRM8FAAjAQABLgAECgcJDQAHAAAAAA==.Thanevoker:BAAALgAECgcJDQAAAA==.Theodrid:BAACLgAFFH8TAAIcAAgJKRHlJQBxAQAcAAgJKRHlJQBxAQAuAAQKfyMAAhwACQmhHjAkAJcCABwACQmhHjAkAJcCAAAA.Thoreum:BAAALgAECgEJAgAAAA==.Thraxia:BAABLgAECn8XAAITAAgJWAUGlgAsAQATAAgJWAUGlgAsAQAAAA==.Thrombin:BAAALgAECgMJAwAAAA==.',
Ti='Tigertigress:BAAALgAECgQJBAAAAA==.Tinkíe:BAABLgAECn8iAAQXAAkJ9Ry3GQDjAQAXAAgJ0By3GQDjAQAZAAQJQRmWTgAJAQAWAAUJ2QxNaQDbAAAAAA==.Tirzahdozier:BAABLgAECn8aAAMiAAgJNhNUJADiAQAiAAgJNhNUJADiAQAcAAEJXwJ90AEYAAAAAA==.Tiwohnne:BAAALgAECgYJCgAAAA==.',
Tl='Tla:BAAALgAECgIJBAAAAA==.',
To='Tooey:BAAALgAECgEJAQAAAA==.',
Tr='Treat:BAABLgAECn9DAAISAAkJfySLAgBAAwASAAkJfySLAgBAAwAAAA==.Tremblement:BAAALgADCgMJAwAAAA==.Trickortreat:BAAALgADCgMJAwAAAA==.Trippyshock:BAABLgAFFH8QAAICAAQJlxwtGwBBAQACAAQJlxwtGwBBAQABLgAFFAkJUAATADwkAA==.Tristitia:BAABLgAECn8vAAMFAAkJ+BYgMQA6AgAFAAkJ+BYgMQA6AgAKAAIJGAYxWQA8AAAAAA==.Trolidan:BAAALgAECgEJAQAAAA==.',
Ts='Tsaorkrad:BAAALgAECgEJAQAAAA==.',
Tu='Tubbs:BAABLgAECn8ZAAIFAAkJAxw4LQBLAgAFAAkJAxw4LQBLAgAAAA==.Turkeltin:BAAALgAECgYJEAABLgAFFAQJCgANAF0ZAA==.',
Tw='Twiggle:BAAALgAECgQJBAABLgAECggJGgAiADYTAA==.',
Ty='Tyche:BAABLgAECn8ZAAMDAAYJcw1pZgAoAQADAAYJcw1pZgAoAQACAAEJ2gHYwwAYAAAAAA==.Tyrdrin:BAAALgAECgEJAQAAAA==.Tyrinara:BAAALgADCgYJBgAAAA==.Tysbich:BAAALgAECgQJCAABLgAECgkJLgAiAOMhAA==.',
Ui='Uiewedaoez:BAABLgAECn80AAIYAAkJWST7AgCZAwAYAAkJWST7AgCZAwAAAA==.',
Um='Umakkel:BAAALgAECgYJDgAAAA==.Umiko:BAAALgADCgUJBQAAAA==.',
Ur='Urd:BAABLgAECn8hAAIFAAkJ9BAmWgC4AQAFAAkJ9BAmWgC4AQAAAA==.',
Va='Vaelrelyn:BAABLgAECn8UAAMhAAYJJhD1HgBZAQAhAAYJJhD1HgBZAQATAAIJ4gHuLwEhAAAAAA==.Vains:BAACLgAFFH8SAAIcAAUJkRzxOQA4AQAcAAUJkRzxOQA4AQAuAAQKfyIAAhwACQkzIc4mAGgCABwACQkzIc4mAGgCAAAA.Valoras:BAAALgADCgEJAQAAAA==.Valrith:BAABLgAECn8YAAIcAAcJIwc2zwD0AAAcAAcJIwc2zwD0AAAAAA==.Vardis:BAABLgAECn8uAAINAAkJMh+SKgBwAgANAAkJMh+SKgBwAgAAAA==.',
Ve='Velinami:BAAALgAECgIJAwAAAA==.Venato:BAAALgADCgEJBAABLgAECgkJNgADAH0OAA==.Vendettuh:BAAALgADCgEJAQAAAA==.Verazene:BAABLgAFFH8HAAIaAAMJmhvpBwD8AAAaAAMJmhvpBwD8AAAAAA==.Verenthirl:BAAALgAECgUJBAAAAA==.Veronica:BAABLgAECn88AAINAAkJ/h6GFQDYAgANAAkJ/h6GFQDYAgAAAA==.Verren:BAABLgAECn8rAAIBAAkJFBrYCQBMAgABAAkJFBrYCQBMAgAAAA==.Versutia:BAAALgAECgIJAgAAAA==.',
Vi='Virse:BAAALgAECgUJCQAAAA==.Virtigo:BAAALgADCgQJCAAAAA==.Vixie:BAAALgAECgcJBwAAAA==.',
Vy='Vye:BAAALgAECgEJAQAAAA==.Vyerith:BAABLgAECn8kAAITAAkJjhzwKAA4AgATAAkJjhzwKAA4AgAAAA==.',
Wa='Warsynth:BAAALgAECgEJAQABLgAECgkJJgAPAOYgAA==.',
We='Weltamus:BAABLgAECn8rAAMKAAkJABhJHAB4AQAFAAgJyg83dQB5AQAKAAQJ9yBJHAB4AQAAAA==.Weltasaur:BAABLgAECn8dAAIBAAYJBhixHgBYAQABAAYJBhixHgBYAQAAAA==.Weltazar:BAABLgAECn82AAICAAkJrxcsJADFAQACAAkJrxcsJADFAQAAAA==.Westside:BAACLgAFFH8pAAMNAAkJziKuBwDBAgANAAkJziKuBwDBAgAPAAEJqAndBwA5AAAuAAQKfyMAAg0ACQnVJmcBAIsDAA0ACQnVJmcBAIsDAAAA.',
Wi='Wickedfluff:BAAALgADCgYJBgAAAA==.Wickët:BAAALgAECgQJCAABLgAECgkJIAATAGsjAA==.Wildtiger:BAABLgAECn8zAAIoAAkJ5hgeCABQAgAoAAkJ5hgeCABQAgAAAA==.',
Wo='Wolfslied:BAAALgAECgYJCAAAAA==.',
Wr='Wrecken:BAAALgADCgUJBQAAAA==.',
Wu='Wulfenhide:BAABLgAECn8zAAQgAAkJ8B5qAgC1AgAgAAkJ8B5qAgC1AgAGAAMJoAfkUACkAAAlAAEJeAVgDwArAAAAAA==.',
Wy='Wyzsky:BAAALgAECgEJBAABLgAECgkJNgADAH0OAA==.',
Xa='Xal:BAAALgADCgEJAQABLgAECgMJBQAHAAAAAA==.Xalreth:BAABLgAECn8hAAIEAAkJPg6YXAByAQAEAAkJPg6YXAByAQAAAA==.Xaviana:BAAALgAECgkJKgAAAQ==.',
Xc='Xcedrin:BAABLgAECn8fAAMSAAkJOQgiOwAmAQASAAgJOAciOwAmAQAOAAMJXwWBcQBhAAAAAA==.',
Xi='Xiangzhu:BAAALgAECgEJAQABLgAECgkJLwAIAIMeAA==.',
Ya='Yastinfect:BAABLgAECn8eAAIEAAkJ0BgPLwBAAgAEAAkJ0BgPLwBAAgAAAA==.Yastypoo:BAAALgAECgEJAQAAAA==.',
Yu='Yurika:BAEBLgAECn8xAAIiAAkJJibZBwAOAwAiAAkJJibZBwAOAwAAAA==.Yushi:BAABLgAECn8tAAIGAAkJlx/zCgB1AgAGAAkJlx/zCgB1AgAAAA==.',
Yv='Yväinne:BAAALgAECgIJAgAAAA==.',
Za='Zareen:BAAALgADCgkJCQAAAA==.Zaru:BAAALgADCgcJEwAAAA==.Zayfall:BAAALgAECgYJEwAAAA==.',
Ze='Zelenor:BAABLgAECn8nAAQFAAkJfxTJNgAkAgAFAAkJfxTJNgAkAgAnAAYJKQV3KQCIAAAKAAQJYQOLSwBhAAAAAA==.Zenweaver:BAACLgAFFH8RAAIZAAMJVSS1HgA2AQAZAAMJVSS1HgA2AQAuAAQKfx8AAhkACQlqIlUEAEcDABkACQlqIlUEAEcDAAAA.',
Zi='Ziur:BAAALgADCgEJAQAAAA==.',
Zo='Zonde:BAAALgAECgEJAQAAAA==.',
Zu='Zud:BAABLgAECn8hAAIFAAkJRiGtEwDSAgAFAAkJRiGtEwDSAgAAAA==.',
['Zö']='Zödd:BAAALgAECgEJAQAAAA==.',
['Öå']='Öåken:BAAALgAECgEJAQABLgAECgkJOgAYAO8QAA==.',
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
