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

local lookup = {'Shaman-Elemental','Shaman-Restoration','DemonHunter-Devourer','DeathKnight-Unholy','Rogue-Subtlety','Unknown-Unknown','Paladin-Protection','Evoker-Preservation','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Survival','Mage-Frost','Priest-Holy','Mage-Arcane','Warrior-Fury','Evoker-Augmentation','Priest-Shadow','Warlock-Demonology','Evoker-Devastation','Druid-Balance','Monk-Mistweaver','Monk-Windwalker','Druid-Restoration','Druid-Guardian','Monk-Brewmaster','Warlock-Affliction','Shaman-Enhancement','Paladin-Retribution','Warrior-Arms','Hunter-Marksmanship','Warrior-Protection','Rogue-Assassination','Warlock-Destruction','Paladin-Holy','DemonHunter-Havoc','Priest-Discipline','Rogue-Outlaw','DemonHunter-Vengeance','DeathKnight-Frost','Druid-Feral',}
local provider = {region='US',realm='KulTiras',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aarix:BAABLgAECn8UAAIBAAkJQRESKQCnAQABAAkJQRESKQCnAQAAAA==.',
Ae='Aedrelyn:BAAALgAECgcJDQAAAA==.Aegia:BAABLgAECn8ZAAMCAAcJrxCXVgBcAQACAAcJrxCXVgBcAQABAAMJTQGHgABFAAAAAA==.Aendillan:BAABLgAECn8TAAIDAAYJQxzHWwCOAQADAAYJQxzHWwCOAQAAAA==.Aewrynn:BAAALgAECgIJAgAAAA==.',
Af='Affonasei:BAABLgAECn82AAIEAAkJ4gvbXACxAQAEAAkJ4gvbXACxAQAAAA==.',
Ai='Aicaramba:BAAALgAECgYJCQAAAA==.Aileen:BAAALgAFFAEJAQAAAA==.',
Ak='Akashi:BAAALgAFFAIJAwABLgAFFAUJFgAFAM4cAA==.',
Al='Alacrodie:BAAALgAECgMJBAAAAA==.Alladorn:BAAALgADCgEJAQAAAA==.Allarii:BAAALgAECgUJBQABLgAECgUJBQAGAAAAAA==.Allynoon:BAAALgADCgMJAwAAAA==.Alurynath:BAAALgADCgcJBwABLgAECgkJLgAHAIMeAA==.',
An='Anahla:BAAALgAECgUJBQABLgAECgkJOQAIAIIYAA==.Ancbow:BAAALgADCgUJBQAAAA==.Angrytotems:BAAALgAECgYJBgAAAA==.Angyll:BAAALgADCgUJAQAAAA==.Annaborshen:BAAALgADCgcJCgAAAA==.Antoccino:BAABLgAECn8sAAIJAAkJ9yH3AwD6AgAJAAkJ9yH3AwD6AgAAAA==.',
Ar='Aragorno:BAABLgAECn8sAAMKAAkJrBdWJwBCAgAKAAkJrBdWJwBCAgALAAQJRAZfQgC6AAAAAA==.Araziel:BAAALgAECgMJBAAAAA==.Arcturen:BAABLgAECn84AAIKAAkJHhvbAAAiAgAKAAkJHhvbAAAiAgAAAA==.Arenthal:BAAALgAECgUJCgABLgAFFAQJBwAMAEgUAA==.Arkulas:BAAALgAECgYJBwAAAA==.Artemisha:BAAALgADCgEJAQABLgAECgMJAwAGAAAAAA==.Arturaan:BAAALgADCgcJCgAAAA==.',
As='Ashalana:BAAALgAECgcJEAAAAA==.Asheby:BAAALgAECgEJAQABLgAECgkJOgANABMcAA==.Ashiera:BAABLgAECn8yAAMMAAkJ+gNNqgAqAQAMAAkJ+gNNqgAqAQAOAAEJ7AHwIgATAAAAAA==.',
At='Atomic:BAABLgAECn8XAAIPAAkJ1gU3AgDXAAAPAAkJ1gU3AgDXAAAAAA==.',
Au='Aurorée:BAAALgAECgEJAQAAAA==.Ausuna:BAAALgAECgYJBwAAAA==.',
Av='Avelai:BAAALgADCgkJCQAAAA==.',
Aw='Awhiteboy:BAAALgAECgcJDgABLgAECgkJLQAFAJ8fAA==.',
Az='Azeral:BAAALgADCgYJBgAAAA==.Azylstrid:BAAALgAECgQJBAAAAA==.',
Ba='Babyshred:BAAALgAECgYJCAAAAA==.Badonka:BAAALgAECgQJBAABLgAECgkJSAAQAG8eAA==.Bahaana:BAAALgAECgUJBQAAAA==.Balentine:BAABLgAECn8dAAMNAAgJMRPlOgALAQANAAcJAhPlOgALAQARAAUJxwP7RwDBAAAAAA==.Bananasloth:BAAALgAECgcJEQABLgAFFAkJTgASAFskAA==.Banjali:BAAALgADCgMJAwAAAA==.Banostraza:BAABLgAECn9IAAMQAAkJbx6/CQC8AgAQAAkJyB2/CQC8AgATAAEJ2RQxIgBFAAAAAA==.Baspir:BAABLgAECn8pAAIUAAkJNxa8JAClAQAUAAkJNxa8JAClAQAAAA==.',
Be='Beeboop:BAAALgAECgEJAQAAAA==.Belly:BAAALgAECgIJAgABLgAECgkJLQAFAJ8fAA==.Belrae:BAACLgAFFH8IAAIDAAIJ0QasiABxAAADAAIJ0QasiABxAAAuAAQKfzUAAgMACQl0FsElADcCAAMACQl0FsElADcCAAAA.Belrinthe:BAAALgAFFAIJAgAAAA==.Bezieck:BAABLgAECn84AAIRAAgJPxXvHgDOAQARAAgJPxXvHgDOAQAAAA==.',
Bi='Bigdawg:BAAALgAECggJEAAAAA==.Bigdeborah:BAAALgAECgUJBQAAAA==.Bigollock:BAAALgAECgEJBAAAAA==.Billyhikz:BAABLgAECn8oAAIMAAkJ8w3oYAC+AQAMAAkJ8w3oYAC+AQAAAA==.Birdbrain:BAAALgAFFAIJAgAAAA==.Biru:BAAALgAECgIJBQABLgAFFAQJBgANAMQLAA==.',
Bl='Bloodarrow:BAAALgAECgYJEQAAAA==.',
Bo='Bobino:BAAALgADCgEJAQAAAA==.Bockchi:BAABLgAECn8YAAMVAAYJ5RcEOgCJAQAVAAYJ5RcEOgCJAQAWAAEJaRX5lAA7AAAAAA==.Bonegavel:BAAALgAECgUJBwAAAA==.Bookhuntress:BAABLgAECn8jAAQXAAcJ3RtAJgAfAgAXAAcJ3RtAJgAfAgAUAAYJ5xcqNABIAQAYAAEJnAwYhAAcAAAAAA==.Bordrann:BAAALgAECgIJAwAAAA==.Bosyoh:BAAALgAECgIJAgAAAA==.',
Br='Branaxe:BAAALgAECggJDgABLgAECgkJCAAGAAAAAA==.Brandisheer:BAAALgAECgYJCAAAAA==.Branpaw:BAAALgAECgEJAQABLgAECgkJCAAGAAAAAA==.Branthor:BAAALgADCgIJAgAAAA==.Brewdeez:BAACLgAFFH8JAAIWAAUJbAm1HwDaAAAWAAUJbAm1HwDaAAAuAAQKfzQAAhkACQktH7QIAKcCABkACQktH7QIAKcCAAAA.Brewzer:BAACLgAFFH8SAAIVAAQJuAu/NwDJAAAVAAQJuAu/NwDJAAAuAAQKfyUAAxUACAmEExg3AJcBABUACAmEExg3AJcBABYABQmtDA9YAK8AAAAA.Brick:BAAALgAECgUJBQAAAA==.Brint:BAABLgAECn8fAAMSAAgJNg+FawBlAQASAAgJMw+FawBlAQAaAAEJshNcOQBCAAAAAA==.Brok:BAABLgAECn8TAAIbAAgJPxqRCQAjAgAbAAgJPxqRCQAjAgAAAA==.Brokenhorn:BAAALgADCgYJGAAAAA==.Bronad:BAACLgAFFH8vAAIMAAYJTCQJIgD2AQAMAAYJTCQJIgD2AQAuAAQKfyIAAgwACAkXJdEjAOMCAAwACAkXJdEjAOMCAAAA.Bronst:BAAALgAECgEJAwABLgAECgkJMQABAOYYAA==.Broomhandle:BAABLgAECn8mAAIcAAkJqiRYBgA+AwAcAAkJqiRYBgA+AwAAAA==.',
Bu='Bubbletea:BAAALgAECgYJDAAAAA==.Bumbushka:BAACLgAFFH8eAAIPAAYJZh/SCgC2AQAPAAYJZh/SCgC2AQAuAAQKfxkAAw8ABwl/IyskADUCAA8ABwl/IyskADUCAB0AAgnfGNcrAJUAAAEuAAUUBgkeAA8AZh8A.Burinn:BAAALgAECgcJCgABLgAECgkJSAANAFkPAA==.',
Ca='Caeus:BAABLgAECn8wAAIEAAkJnyRSBwA7AwAEAAkJnyRSBwA7AwAAAA==.Cam:BAABLgAECn8xAAIMAAkJlCXwCwAZAwAMAAkJlCXwCwAZAwAAAA==.Capriestson:BAAALgADCgkJCQABLgAECgYJDwAGAAAAAA==.Cardo:BAAALgADCgUJBQABLgAFFAgJFwAeAGgZAA==.Care:BAABLgAECn8ZAAIMAAkJjAwciADBAQAMAAkJjAwciADBAQAAAA==.Carolinabele:BAAALgAECgcJBAAAAA==.Carrowend:BAAALgADCgcJBwAAAA==.Cauud:BAABLgAECn8bAAIfAAYJuxL4IwARAQAfAAYJuxL4IwARAQAAAA==.',
Cb='Cbd:BAAALgADCgcJCAAAAA==.',
Ch='Chacruna:BAAALgAECgQJBAAAAA==.Charmed:BAAALgAECgUJBgAAAA==.Cheesús:BAAALgAECggJDAAAAA==.Chelan:BAABLgAECn9IAAMNAAkJWQ/9IgCrAQANAAkJWQ/9IgCrAQARAAkJjgW2OgAoAQAAAA==.Chiji:BAAALgAECgYJBQAAAA==.Chilljaeden:BAAALgAECgUJDQAAAA==.Chizuko:BAAALgADCgMJAwAAAA==.Chuntspeed:BAAALgADCgYJDAAAAA==.Chuye:BAAALgAECgEJAQABLgAFFAQJBgANAMQLAA==.',
Ci='Cigs:BAAALgAECgYJBgABLgAFFAgJJQAMAAMjAA==.Cindyloowhoo:BAAALgADCgMJAwAAAA==.Cinnabunz:BAABLgAECn8gAAISAAcJjApBBQB4AAASAAcJjApBBQB4AAAAAA==.',
Cl='Cleaväge:BAAALgADCgYJBgAAAA==.Cleurisse:BAABLgAFFH8RAAIJAAUJaBeZGAAiAQAJAAUJaBeZGAAiAQAAAA==.Cloudlol:BAAALgAECgQJBgAAAA==.Clueless:BAAALgADCgMJAwAAAA==.',
Cn='Cnova:BAAALgAECgUJDgABLgAECgkJNQAcAAggAA==.',
Co='Codythedead:BAABLgAFFH8GAAIEAAIJ7RQh3ACHAAAEAAIJ7RQh3ACHAAAAAA==.Compadre:BAABLgAECn8XAAQWAAgJPh7NHQDrAQAWAAcJ0RrNHQDrAQAZAAQJUiAiRAAyAQAVAAYJWxE4RADMAAAAAA==.Contekst:BAABLgAECn8hAAMXAAcJ5w8aWQAtAQAXAAcJ5w8aWQAtAQAUAAcJxAajVwCzAAAAAA==.Coolsbeans:BAAALgAECgYJCwAAAA==.Coraf:BAACLgAFFH8rAAICAAcJvSLYAwCWAgACAAcJvSLYAwCWAgAuAAQKfzgAAgIACQkAJMABAHQDAAIACQkAJMABAHQDAAAA.',
Cr='Crankzilla:BAAALgADCggJFgAAAA==.Cravix:BAAALgADCgYJBgAAAA==.Cruoris:BAABLgAECn8bAAIgAAcJww2LDwArAQAgAAcJww2LDwArAQAAAA==.',
Cu='Cunfuzed:BAAALgAECgEJAQAAAA==.Cuvier:BAABLgAECn8hAAIgAAcJMQVsEwDxAAAgAAcJMQVsEwDxAAAAAA==.',
Da='Daddle:BAABLgAECn8gAAQSAAkJayNrDwDRAgASAAkJ5iFrDwDRAgAaAAYJWSIjCgC+AQAhAAEJAADWVAAAAAAAAA==.Daemonxblack:BAAALgAECgEJAQAAAA==.Daeth:BAAALgAECgMJBQAAAA==.Daeththane:BAAALgAECgEJAQAAAA==.Dahaxors:BAABLgAECn8lAAIEAAkJGxvNLwBAAgAEAAkJGxvNLwBAAgAAAA==.Dalareas:BAAALgAECgMJAwAAAA==.Danak:BAAALgAECgIJAwAAAA==.Dannika:BAAALgAECgYJBwAAAA==.Dantelous:BAAALgAECgEJAgAAAA==.Darthwader:BAAALgAECgUJCAAAAA==.Dascrazy:BAABLgAECn8lAAMFAAgJvQsOJQBtAQAFAAgJZgsOJQBtAQAgAAUJNAe9FwC4AAAAAA==.Daynaa:BAAALgAECgQJBQABLgAECggJFwAiACETAA==.',
De='Deadlyfrosty:BAABLgAECn8XAAIEAAYJAAMNEAGYAAAEAAYJAAMNEAGYAAAAAA==.Deathsfather:BAAALgADCgYJBgABLgAECgYJEwAGAAAAAA==.Debixie:BAACLgAFFH8SAAIgAAQJyB3eAgB8AQAgAAQJyB3eAgB8AQAuAAQKfyUAAiAACQlLI04BACUDACAACQlLI04BACUDAAAA.Dejection:BAAALgAECgEJAQAAAA==.Delron:BAAALgADCgEJAQAAAA==.Demisi:BAAALgAECgcJEwAAAA==.Demoness:BAABLgAECn8iAAMDAAkJQSK2FQCWAgADAAgJZCK2FQCWAgAjAAEJTCFeVwBgAAAAAA==.Demsynth:BAAALgAECgQJBAABLgAECgkJJgAOAOYgAA==.Derangedsp:BAAALgADCgkJCQABLgAFFAkJTgASAFskAA==.Destorr:BAAALgADCgQJBAAAAA==.Dextero:BAAALgADCgMJAwAAAA==.',
Di='Diasundra:BAABLgAECn8sAAIKAAkJ5h9NDgDKAgAKAAkJ5h9NDgDKAgAAAA==.Digiornos:BAABLgAECn8jAAISAAkJqhQ/PQDnAQASAAkJqhQ/PQDnAQAAAA==.',
Dj='Djyinn:BAAALgADCgcJCgAAAA==.',
Do='Doorknob:BAAALgAECgYJCQAAAA==.Dottingyou:BAACLgAFFH8lAAMSAAcJrBZUJwCrAQASAAYJIhpUJwCrAQAhAAEJXQWcIwBOAAAuAAQKfzUAAxIACQnvHw4QAMwCABIACQnvHw4QAMwCACEAAwlMHzYsAA4BAAAA.',
Dr='Draenei:BAAALgAECgEJAQAAAA==.Draeziq:BAAALgAECgEJAgABLgAECggJFwAiACETAA==.Dragonpo:BAAALgAECgEJAQAAAA==.Drakkonde:BAABLgAECn8bAAISAAYJUhadegBEAQASAAYJUhadegBEAQAAAA==.Dravin:BAAALgADCgYJBgAAAA==.Drazarth:BAAALgAECgUJDQAAAA==.Dreamon:BAAALgAFFAEJAQAAAA==.Drransom:BAAALgAECgEJAQAAAA==.Dryan:BAAALgAECgYJEQAAAA==.Dryon:BAABLgAECn82AAIfAAkJPB9VBQDEAgAfAAkJPB9VBQDEAgAAAA==.',
Du='Duergan:BAAALgADCgEJAQAAAA==.Duo:BAABLgAECn8xAAIKAAkJXBNfRwDMAQAKAAkJXBNfRwDMAQAAAA==.Duragon:BAABLgAECn8yAAQQAAkJ7RbCGAARAgAQAAkJ7RbCGAARAgATAAgJPwUpFgCyAAAIAAYJPwdHJwCxAAAAAA==.',
['Dí']='Díznutz:BAABLgAECn8OAAIDAAYJ6RBJeAA+AQADAAYJ6RBJeAA+AQABLgAFFAMJBQAKAFsaAA==.',
El='Eldumir:BAAALgADCgIJBAABLgAECgkJLgAHAIMeAA==.Elyleath:BAAALgAECgYJBgAAAA==.',
Em='Emilia:BAABLgAECn8jAAINAAkJxQu6AQDvAAANAAkJxQu6AQDvAAAAAA==.Empanada:BAAALgADCgEJAQAAAA==.',
En='Endressa:BAABLgAECn8yAAMkAAkJPw8qGwD2AQAkAAkJPw8qGwD2AQARAAIJXQ9zBQBMAAAAAA==.English:BAABLgAECn8zAAIMAAkJdBu+NwA5AgAMAAkJdBu+NwA5AgAAAA==.',
Er='Erelios:BAABLgAECn8uAAIHAAkJgx5iBQCbAgAHAAkJgx5iBQCbAgAAAA==.Erubus:BAAALgADCgUJCAAAAA==.',
Es='Eski:BAAALgAECgEJAgAAAA==.',
Eu='Eureka:BAEALgAECgMJBwABLgAECgkJMQAiACYmAA==.',
Ev='Evangelina:BAACLgAFFH8mAAMQAAgJvB7CBQCpAgAQAAgJvB7CBQCpAgATAAEJygr9CQBTAAAuAAQKfygAAxAACQmjJfcBAGIDABAACQmjJfcBAGIDABMABgmRI78PAN8BAAAA.Everlight:BAAALgAECgQJBQABLgAECgkJJgAYAM0TAA==.Evileyes:BAAALgADCgMJAgAAAA==.',
Ey='Eyezoffury:BAAALgAECgIJAgAAAA==.',
Ez='Ezrì:BAAALgAECgMJBAAAAA==.',
Fa='Faddeyshnek:BAABLgAECn8oAAIKAAkJSxZVOwDyAQAKAAkJSxZVOwDyAQAAAA==.Fastbeefball:BAAALgADCggJDAAAAA==.Fatgirljuice:BAAALgADCgMJAwABLgAFFAgJJgAQALweAA==.',
Fe='Feliseda:BAAALgADCgkJCwAAAA==.Felysambre:BAAALgAECgYJDAAAAA==.',
Fi='Filibertos:BAAALgAECgQJBAABLgAFFAgJJQAMAAMjAA==.Fish:BAACLgAFFH8rAAIRAAgJ4iaDAAApAwARAAgJ4iaDAAApAwAuAAQKfzcAAhEACAmOJlYCAIwDABEACAmOJlYCAIwDAAEuAAUUCQlAABEA8iUA.',
Fl='Flight:BAACLgAFFH8WAAMFAAUJzhy9GABMAQAFAAUJzhy9GABMAQAlAAIJ9BX+CwCkAAAuAAQKfx0AAwUACAkRHHcUAG8CAAUACAljG3cUAG8CACAAAQkBDiweADwAAAAA.Fluxyouup:BAABLgAECn8gAAMCAAkJmghhVwBZAQACAAkJmghhVwBZAQABAAYJCQXUaACsAAAAAA==.Fløki:BAAALgAECgIJAgAAAA==.',
Fo='Follow:BAAALgAECgQJBQAAAA==.Forsynth:BAABLgAECn8mAAMOAAkJ5iDWAADgAgAOAAkJ5iDWAADgAgAMAAEJAABIdQEwAAAAAA==.',
Fr='Frrostitute:BAAALgADCgEJAQAAAA==.',
Ge='Gewitt:BAABLgAECn8tAAMCAAkJgh4cFgCZAgACAAkJgh4cFgCZAgABAAgJ2hnYKADNAQAAAA==.',
Gg='Ggiven:BAABLgAECn8XAAIDAAcJjRJDYQBmAQADAAcJjRJDYQBmAQAAAA==.',
Gl='Glinda:BAAALgAECgIJAwAAAA==.',
Gn='Gnow:BAAALgADCgEJAQAAAA==.',
Gr='Grabomage:BAACLgAFFH8lAAIMAAcJJh7zFABJAgAMAAcJJh7zFABJAgAuAAQKf1kAAgwACQkmJlIDAMoDAAwACQkmJlIDAMoDAAAA.Grag:BAAALgADCgMJBQAAAA==.Grapekoolaid:BAAALgAECgYJDwAAAA==.Grapesloth:BAAALgAECgQJBAABLgAFFAkJTgASAFskAA==.Grazienne:BAAALgAECgIJAwAAAA==.Gretchen:BAAALgADCgUJBQAAAA==.Grif:BAAALgADCgMJAwAAAA==.Grilm:BAABLgAECn8tAAIYAAkJhx/nBQCnAgAYAAkJhx/nBQCnAgAAAA==.Grimbaine:BAABLgAECn83AAIcAAkJCCMkCAAqAwAcAAkJCCMkCAAqAwAAAA==.Grimbane:BAAALgAECgMJBAAAAA==.Grimmshady:BAAALgAECgMJBAAAAA==.Grizzlegrimm:BAAALgAECgEJAgAAAA==.Groot:BAAALgAECgkJAQAAAA==.Gryphin:BAAALgADCgcJBwAAAA==.',
Gu='Gulmok:BAAALgADCgUJDQAAAA==.Gumbles:BAACLgAFFH8GAAINAAQJxAu4AgCHAAANAAQJxAu4AgCHAAAuAAQKfycABA0ACAkcHWgRAFcCAA0ACAkcHWgRAFcCACQAAglJB3luAE4AABEAAQnUA5dnACoAAAAA.Gurney:BAABLgAECn8qAAMiAAkJ/hawHQAWAgAiAAkJ/hawHQAWAgAHAAEJggQxWQAdAAAAAA==.Guzfu:BAABLgAECn8UAAIWAAcJgg1iSgDYAAAWAAcJgg1iSgDYAAAAAA==.',
Gw='Gwenory:BAAALgAECgEJAQAAAA==.',
Gy='Gying:BAABLgAECn9DAAMZAAkJohxCAAAeAgAZAAkJohxCAAAeAgAWAAUJcg8FQAAZAQAAAA==.',
Ha='Hanjabs:BAAALgAECgYJDgAAAA==.Hanmine:BAAALgAECgYJDQAAAA==.Hannie:BAAALgAECgIJAwAAAA==.Happyelf:BAAALgAECgYJDgAAAA==.Hartephinar:BAAALgAECgEJAQAAAA==.Hatike:BAAALgAECgEJAQAAAA==.',
He='Headhúnter:BAACLgAFFH8FAAIKAAMJWxouWgDxAAAKAAMJWxouWgDxAAAuAAQKfxcAAgoACQkgH0MRAMcCAAoACQkgH0MRAMcCAAAA.Heatseeka:BAABLgAECn8YAAICAAgJFw48WQBSAQACAAgJFw48WQBSAQAAAA==.Hexxiz:BAAALgAECggJDAABLgAECgkJOwAXAB4kAA==.',
Hi='Hiphopinator:BAABLgAECn8vAAMPAAkJLiWGBgD2AgAPAAkJCSOGBgD2AgAfAAcJGyWIDwDwAQAAAA==.',
Ho='Holydeath:BAAALgAECgEJAQAAAA==.Holyshock:BAAALgAECgcJEwAAAA==.Holyterror:BAAALgAECgIJAwAAAA==.Honeysweety:BAAALgADCgMJAwAAAA==.',
Hy='Hydril:BAAALgADCgEJAQAAAA==.',
['Hø']='Hødør:BAAALgAECgQJCwAAAA==.',
Ia='Iamcro:BAAALgAECgUJBgAAAA==.Ianthe:BAABLgAECn82AAIOAAkJDgs1AAA3AQAOAAkJDgs1AAA3AQAAAA==.',
Ib='Iboga:BAAALgAECgUJBwAAAA==.Ibrahimovic:BAABLgAECn80AAQhAAcJryPdCwCBAQAhAAUJHCTdCwCBAQAaAAYJURlGDwBoAQASAAQJjB1nfABAAQAAAA==.',
Ig='Ignitecro:BAAALgADCgUJBQAAAA==.Igram:BAAALgADCggJCQAAAA==.',
Ih='Iheal:BAAALgADCgcJCgAAAA==.',
Il='Illidoonger:BAAALgAECgYJDwAAAA==.',
Im='Imauggin:BAAALgADCgYJBgAAAA==.Imbobbymom:BAAALgAECgEJAgABLgAFFAgJJgAQALweAA==.Imhim:BAAALgAECgEJAQAAAA==.',
In='Inafume:BAAALgAECgYJDAAAAA==.Infoxicated:BAAALgAECgUJCgABLgAECgYJCAAGAAAAAA==.Inoxia:BAAALgAECgQJBgAAAA==.Intrépidice:BAAALgAECgQJBwAAAA==.',
Io='Iowastyle:BAABLgAECn84AAMNAAkJHSC8BQAdAwANAAkJHSC8BQAdAwAkAAMJlgx+QwCZAAAAAA==.',
It='Ithruyn:BAAALgADCgQJBAAAAA==.',
Ix='Ixtabay:BAACLgAFFH8XAAMaAAUJfhwwAABeAQAaAAUJfhwwAABeAQASAAEJlA1ZyABCAAAuAAQKfzcABBoACQmmIa8EAE8CABoACQmXIa8EAE8CABIABgnGGQ1CANYBACEAAgm6EoBTAHQAAAAA.',
Ja='Jakobey:BAAALgAECgQJBQAAAA==.Jamurra:BAAALgAECgQJDgABLgAECggJFwAiACETAA==.Jaylinn:BAABLgAECn8uAAIKAAkJ4Q3UVAClAQAKAAkJ4Q3UVAClAQAAAA==.Jazzmend:BAAALgADCgEJAQAAAA==.',
Je='Jeanne:BAAALgAECgYJBwAAAA==.',
Ji='Jimsonweed:BAAALgAECgUJDAAAAA==.',
Jo='Jocko:BAAALgADCgYJBgAAAA==.Josie:BAABLgAECn8pAAIkAAkJFiRcBABPAwAkAAkJFiRcBABPAwAAAA==.',
Ju='Judgekoopa:BAABLgAECn8qAAIiAAkJcx0rCwDaAgAiAAkJcx0rCwDaAgAAAA==.',
Ka='Kaadore:BAAALgAECgYJBwAAAA==.Kaeiria:BAAALgAECgUJCgAAAA==.Kalaanri:BAABLgAECn8wAAMBAAkJohMzKACsAQABAAgJzRQzKACsAQACAAYJig6daQAfAQAAAA==.Kaleberry:BAABLgAECn8gAAMUAAkJBA6CJgCZAQAUAAgJBA6CJgCZAQAXAAcJEgmlhgDJAAAAAA==.Kalthyra:BAAALgAECgMJAwABLgAECgkJLgAHAIMeAA==.Kalyandra:BAABLgAECn8mAAIWAAcJdxBDNAAyAQAWAAcJdxBDNAAyAQAAAA==.Kalógeros:BAAALgADCgMJAwAAAA==.Kanhang:BAAALgADCgcJDAAAAA==.Kanra:BAABLgAECn8XAAQYAAYJ6RydFwCUAQAYAAYJ6RydFwCUAQAXAAYJLgw4aQD5AAAUAAEJvBJ+iQA4AAABLgAECgkJMAAHAF0iAA==.Karkevon:BAAALgAECgYJDgAAAA==.Karlach:BAABLgAECn8eAAIPAAkJAh0aFwA1AgAPAAkJAh0aFwA1AgAAAA==.Karlachs:BAAALgADCgYJBwAAAA==.Karrla:BAABLgAECn8oAAIDAAkJLhqpGQB7AgADAAkJLhqpGQB7AgAAAA==.Karumie:BAABLgAECn8nAAICAAkJZhyWHwBTAgACAAkJZhyWHwBTAgAAAA==.Kashyyk:BAAALgAECgMJAwABLgAECgkJPgASAJkaAA==.Kateera:BAAALgAECgUJCwAAAA==.',
Ke='Keden:BAAALgAECgMJBAAAAA==.Keelivan:BAAALgAECgMJAwAAAA==.Kelivann:BAAALgADCgUJBQAAAA==.Keljaden:BAABLgAECn8XAAIdAAkJjiA4AwACAwAdAAkJjiA4AwACAwABLgAECgkJLAADAEEiAA==.Kels:BAABLgAECn8sAAIDAAkJQSL6DADdAgADAAkJQSL6DADdAgAAAA==.',
Kh='Kheyra:BAABLgAECn8mAAIYAAkJzROLEgDJAQAYAAkJzROLEgDJAQAAAA==.',
Ki='Kiaona:BAAALgADCgMJAwAAAA==.Kidashia:BAAALgAECgQJBAAAAA==.Kiwisloth:BAAALgAFFAEJAQABLgAFFAkJTgASAFskAA==.',
Ko='Koggs:BAAALgAFFAIJAgAAAA==.Kohnor:BAAALgAECgMJBAAAAA==.Kopi:BAAALgAECgMJAwABLgAECgkJLAAJAPchAA==.Korlatt:BAABLgAECn86AAQDAAkJqR7mEgCsAgADAAkJQh3mEgCsAgAmAAMJDRxJFwDqAAAjAAMJOhZdVwBgAAAAAA==.Kowalabear:BAABLgAECn8rAAMnAAkJtCExAQD+AgAnAAkJtCExAQD+AgAJAAQJPwqaTQBbAAAAAA==.',
Kr='Kryptrix:BAAALgAECgQJBAAAAA==.Krìmzar:BAAALgADCggJCgABLgAECgYJFAAMADgXAA==.',
Kt='Kthanid:BAABLgAECn8VAAIkAAYJog/ZMgBOAQAkAAYJog/ZMgBOAQAAAA==.',
Ku='Kurston:BAABLgAECn9DAAIXAAkJMRtpEwCwAgAXAAkJMRtpEwCwAgAAAA==.',
Ky='Kymakazie:BAABLgAECn8YAAIKAAkJjQP5mAAOAQAKAAkJjQP5mAAOAQAAAA==.',
['Kã']='Kãtniss:BAAALgAECgEJAQAAAA==.',
La='Laih:BAABLgAECn8iAAIgAAkJgA+tCAC+AQAgAAkJgA+tCAC+AQAAAA==.Lasturus:BAAALgAECgUJBQABLgAFFAgJJQAVAGkZAA==.Lathelinis:BAAALgAECgcJCAAAAA==.Lauraenital:BAAALgAECgQJBAAAAA==.Layssara:BAAALgADCgMJAwAAAA==.',
Le='Leafbloom:BAAALgAECgEJAQABLgAECggJFgAZAHsYAA==.Letmeout:BAAALgAECgEJAQAAAA==.Lexx:BAAALgAECgIJAgAAAA==.Leyote:BAABLgAECn8+AAICAAkJDBOfLAAGAgACAAkJDBOfLAAGAgAAAA==.',
Li='Liady:BAAALgADCgcJBwAAAA==.Lightshop:BAAALgADCgIJAQAAAA==.Liirah:BAAALgAECgEJAQAAAA==.Linora:BAAALgAECgIJAQAAAA==.Listriesa:BAAALgADCgEJAQAAAA==.',
Lo='Lolabunny:BAABLgAECn8UAAMWAAYJZBofNABRAQAWAAUJkxYfNABRAQAZAAQJ+xkLRgAqAQABLgAECggJGAAJAOIiAA==.Lorianne:BAAALgAECgMJBAAAAA==.Lousseur:BAAALgADCgEJAgAAAA==.Lowdangle:BAABLgAECn8tAAIDAAkJtheXJQA3AgADAAkJtheXJQA3AgAAAA==.',
Lu='Lulz:BAAALgAECgkJEwAAAA==.Lumini:BAABLgAECn8eAAMRAAkJ3AblNABEAQARAAkJ3AblNABEAQANAAMJfwPvagA9AAAAAA==.Luminias:BAAALgAECgUJDQAAAA==.Luthein:BAAALgAECgYJDwAAAA==.Luxroy:BAAALgAECgYJEQAAAA==.',
Ly='Lygma:BAABLgAECn8iAAIcAAkJoQ6WZACmAQAcAAkJoQ6WZACmAQAAAA==.Lynniebee:BAABLgAECn8pAAIOAAkJjAwmBQCPAQAOAAkJjAwmBQCPAQAAAA==.',
Ma='Madalyn:BAAALgAECgcJEwAAAA==.Maexna:BAAALgAECgEJAQAAAA==.Magdelyne:BAAALgAECgkJDAAAAA==.Magicpie:BAAALgAECgcJBwABLgAECgkJPgAmANIkAA==.Magni:BAAALgAECgQJBQAAAA==.Makklehaney:BAABLgAECn8eAAMbAAkJTg5FEQCfAQAbAAkJTg5FEQCfAQABAAEJ7QFmlQAgAAAAAA==.Mallaah:BAAALgADCgYJCgAAAA==.Malthorin:BAAALgADCgMJAwAAAA==.Maneke:BAAALgADCgkJCQABLgAECgkJLgACAIUUAA==.Marovingian:BAABLgAECn8tAAIiAAkJ4yFZAwBsAwAiAAkJ4yFZAwBsAwAAAA==.Matthad:BAABLgAECn8uAAICAAkJhRSGJwAiAgACAAkJhRSGJwAiAgAAAA==.Mazìkene:BAACLgAFFH8ZAAMaAAUJWQ1nCQDjAAASAAQJ0gcDaQDzAAAaAAQJ2g9nCQDjAAAuAAQKfygAAxoACQlEGZwJAMkBABoABwnrGJwJAMkBABIACQk2FgZSAKYBAAAA.',
Mc='Mccone:BAABLgAECn8XAAIKAAYJYwmnrwDlAAAKAAYJYwmnrwDlAAAAAA==.Mcsluts:BAABLgAECn8jAAMcAAYJDhCQCQBtAAAcAAYJkw6QCQBtAAAHAAEJaBDqUwApAAAAAA==.',
Me='Megadumb:BAAALgAECgQJBAABLgAFFAgJJgAQALweAA==.Melmirict:BAACLgAFFH8SAAIFAAUJWBJnIAAiAQAFAAUJWBJnIAAiAQAuAAQKfyUAAwUACQlQGdwTAAQCAAUACQlQGdwTAAQCACAAAwmAGpQSANkAAAAA.Meng:BAAALgADCgYJBgAAAA==.Merciala:BAABLgAECn9DAAIYAAkJdRLfFwCSAQAYAAkJdRLfFwCSAQAAAA==.',
Mi='Milyva:BAAALgADCgMJAwAAAA==.Milyyanna:BAAALgAECgMJBQAAAA==.Minaby:BAAALgAECgYJEAABLgAECgkJJgAcAKokAA==.Missmurder:BAAALgAFFAEJAQAAAA==.Mitochondria:BAAALgADCgQJBAAAAA==.',
Mo='Moddoxx:BAABLgAECn8+AAQSAAkJmRruKgAuAgASAAgJSxzuKgAuAgAaAAIJkg6HPAA5AAAhAAIJuw4KPwAyAAAAAA==.Mohawk:BAAALgAECgcJDgAAAA==.Mohaxors:BAAALgADCgcJDwAAAA==.Moko:BAAALgAECgEJAgAAAA==.Mokopal:BAAALgADCgMJAwAAAA==.Mokøtrollz:BAABLgAECn8jAAMKAAkJrh92OAD8AQALAAgJmBnNEgASAgAKAAgJIB52OAD8AQAAAA==.Molen:BAAALgAECgUJBwAAAA==.Mommyjuice:BAAALgAECgYJBgABLgAFFAgJJgAQALweAA==.Monkeeh:BAAALgADCgUJCQAAAA==.Monkle:BAABLgAECn9QAAIWAAkJ/CTOAQBYAwAWAAkJ/CTOAQBYAwAAAA==.Monkoku:BAAALgAECgQJBAABLgAFFAUJDgAFAHcbAA==.Moonsii:BAABLgAECn8aAAIXAAkJ9Q13PQCdAQAXAAkJ9Q13PQCdAQAAAA==.Mooroth:BAABLgAECn9CAAIfAAkJPSBbBADhAgAfAAkJPSBbBADhAgABLgAFFAIJAgAGAAAAAA==.Morekk:BAAALgADCgYJBgAAAA==.Morozko:BAABLgAECn8eAAInAAgJShqLCAAEAgAnAAgJShqLCAAEAgAAAA==.',
Mu='Muddler:BAABLgAECn9CAAIhAAkJlAOjHADCAAAhAAkJlAOjHADCAAAAAA==.Muscuees:BAAALgADCgEJAQAAAA==.Mush:BAAALgAECgQJBAAAAA==.',
['Mà']='Màggles:BAAALgADCggJCQAAAA==.',
Na='Nadd:BAABLgAECn8hAAIKAAgJOAo3gwA4AQAKAAgJOAo3gwA4AQAAAA==.Naledi:BAABLgAECn8cAAIUAAgJ5Q+8MwBKAQAUAAgJ5Q+8MwBKAQAAAA==.Nancy:BAAALgAECgQJBAAAAA==.Naomas:BAABLgAECn89AAMMAAkJjSGfEgDqAgAMAAkJ9SCfEgDqAgAOAAIJ2R6aDAC1AAAAAA==.Narella:BAABLgAECn8tAAIMAAgJjRQoZQCzAQAMAAgJjRQoZQCzAQAAAA==.',
Ne='Needlepax:BAAALgAECgEJAQAAAA==.Negotiable:BAAALgAECgUJDQAAAA==.Negrido:BAABLgAECn8zAAQSAAkJ+yU2DwDTAgASAAgJwSI2DwDTAgAhAAMJNiWJJAA3AQAaAAEJvx9qMQBaAAAAAA==.Nei:BAABLgAECn89AAIcAAgJPBsFAgBpAQAcAAgJPBsFAgBpAQAAAA==.Newt:BAAALgADCgUJBQAAAA==.Nezzarector:BAAALgAECgUJCwAAAA==.',
Ni='Nikem:BAABLgAECn82AAMUAAkJ6BniEABWAgAUAAkJ6BniEABWAgAYAAEJ0wKQOwAPAAAAAA==.',
No='Noelle:BAAALgAECgQJCQAAAA==.Nor:BAAALgAECgUJCgAAAA==.Noraelyn:BAABLgAECn8zAAMiAAkJ7xtHDQC9AgAiAAkJ7xtHDQC9AgAcAAQJewSiUAFeAAAAAA==.Norelei:BAAALgAECgUJBwABLgAECgkJJgAYAM0TAA==.Noriyuki:BAABLgAECn8uAAIWAAcJDgKjhgBMAAAWAAcJDgKjhgBMAAAAAA==.Northside:BAAALgADCgQJBAABLgAFFAgJJQAMAAMjAA==.Notkorlatt:BAAALgADCgIJAgAAAA==.',
Nu='Nugatory:BAACLgAFFH8IAAQLAAQJFhW1FgAbAQALAAQJFhW1FgAbAQAKAAEJFwaBqgBDAAAeAAEJwAH9PAAqAAAuAAQKfxcAAwsACAlSI1gKAHkCAAsACAlSI1gKAHkCAB4AAwnADI9pAJgAAAEuAAUUBgkJABEADwoA.Nuudles:BAAALgAECgEJAQAAAA==.',
Ny='Nyxahlia:BAAALgAECgYJEQAAAA==.',
Oa='Oakenia:BAAALgADCgQJBAABLgAECgkJOgAXAO8QAA==.',
Og='Ogkagìsttv:BAAALgAECgYJBwAAAA==.',
Ol='Olrong:BAABLgAECn8/AAIjAAkJMBOVFgDTAQAjAAkJMBOVFgDTAQAAAA==.Oluja:BAAALgAECgYJDwAAAA==.',
Om='Omegâ:BAAALgAFFAEJAQAAAA==.',
On='Onlypaws:BAAALgAECgYJEgAAAA==.Onuris:BAAALgAECgEJAQAAAA==.',
Op='Opaalite:BAAALgAECgMJAwAAAA==.Opacuslupus:BAAALgAECggJEAAAAA==.Ophel:BAAALgADCgYJBgABLgAECgkJOQAIAIIYAA==.Oppcookies:BAAALgAECgYJDwABLgAECgkJIAAKAHQXAA==.Oppressin:BAAALgADCggJDAABLgAECgkJIAAKAHQXAA==.Oppshot:BAABLgAECn8gAAMKAAkJdBebKgAzAgAKAAkJdBebKgAzAgAeAAEJUAnnPgAsAAAAAA==.',
Or='Orin:BAAALgAECgEJAQAAAA==.',
Os='Oshìe:BAACLgAFFH8FAAIiAAMJFxE8MwCjAAAiAAMJFxE8MwCjAAAuAAQKfykAAiIACQnbIVAMALgCACIACQnbIVAMALgCAAAA.',
Ov='Overdoom:BAABLgAECn82AAMEAAkJYx7JKgBVAgAEAAkJYx7JKgBVAgAJAAUJHAb1QwB/AAAAAA==.Ovscur:BAAALgAECgMJCAAAAA==.',
Pa='Packapipe:BAAALgADCggJEgAAAA==.Paladinjohn:BAACLgAFFH8oAAIcAAcJhSGVCgAwAgAcAAcJhSGVCgAwAgAuAAQKfysAAhwACQkbJWMBANEDABwACQkbJWMBANEDAAAA.Palykat:BAABLgAECn80AAIcAAkJ5QjnAgAjAQAcAAkJ5QjnAgAjAQAAAA==.Paradox:BAAALgAECgEJAQAAAA==.',
Pe='Pelagos:BAAALgAECggJCgAAAA==.Pennywisé:BAABLgAECn8rAAIEAAkJUyBAGwCjAgAEAAkJUyBAGwCjAgAAAA==.Pessimal:BAAALgADCgEJAQABLgAECgkJIgAEAEMfAA==.',
Ph='Phillygg:BAAALgAECgQJBAAAAA==.Phoeniix:BAABLgAECn8mAAMYAAkJiBeKEwC9AQAYAAkJ4haKEwC9AQAUAAQJvRe1UgDcAAAAAA==.',
Pl='Plaguegying:BAABLgAECn8eAAMEAAkJnA+CZgCaAQAEAAgJ8w+CZgCaAQAJAAEJOQ3iWQA6AAABLgAECgkJQwAZAKIcAA==.Ploofee:BAAALgAECggJEAAAAA==.',
Po='Porker:BAAALgADCgEJAQAAAA==.',
Pr='Prog:BAAALgAECgEJAQAAAA==.Progresz:BAABLgAECn8WAAIMAAkJwRBMYAC/AQAMAAkJwRBMYAC/AQAAAA==.',
Ps='Psichosa:BAAALgAECggJDgAAAA==.Psychosis:BAAALgADCgQJAwAAAA==.',
Py='Pykel:BAABLgAECn8nAAIUAAkJ2QmlOQAsAQAUAAkJ2QmlOQAsAQAAAA==.Pyrexea:BAAALgADCgYJBgAAAA==.Pyrivia:BAAALgAECgEJAgABLgAECgUJCgAGAAAAAA==.',
Qa='Qaren:BAABLgAECn8VAAIcAAYJ9QWnCgGrAAAcAAYJ9QWnCgGrAAAAAA==.',
Qi='Qikeyy:BAAALgAECgEJAQAAAA==.',
Qu='Quadraxis:BAAALgADCgcJCQAAAA==.',
Ra='Raethe:BAAALgAECgQJBAAAAA==.Raishun:BAAALgAECgMJAwAAAA==.Raizo:BAAALgADCgEJAQAAAA==.Rajak:BAAALgADCgEJAQAAAA==.Rake:BAABLgAECn80AAQoAAkJVSCZBgB8AgAoAAkJFB+ZBgB8AgAYAAEJQh1EYABPAAAUAAIJ6wcdgABIAAAAAA==.Raminthórn:BAAALgADCgIJAgAAAA==.Rannï:BAACLgAFFH8GAAIMAAMJyAqWjQC+AAAMAAMJyAqWjQC+AAAuAAQKfxUAAgwACAkiFPxeAMMBAAwACAkiFPxeAMMBAAEuAAUUBQkXABoAfhwA.Ratabi:BAAALgADCgIJAgAAAA==.Ravana:BAAALgADCggJCAAAAA==.Ravna:BAAALgAECggJEQABLgAECgkJOgAUAN0aAA==.Rawrski:BAAALgADCgEJAgABLgAECgkJNgACAH0OAA==.',
Re='Reavert:BAAALgADCgYJBgAAAA==.Reeven:BAAALgAECgkJNgAAAQ==.Ressurectjin:BAAALgAECgUJDgAAAA==.Rexmortis:BAAALgAECgkJAgAAAA==.',
Rh='Rhaistlin:BAAALgADCgMJAwAAAA==.Rhcpmage:BAACLgAFFH8NAAIMAAQJUSIRSABUAQAMAAQJUSIRSABUAQAuAAQKfxwAAgwACQmKIV4WANMCAAwACQmKIV4WANMCAAAA.Rhetegast:BAABLgAECn8oAAIHAAkJrRPHDwDIAQAHAAkJrRPHDwDIAQAAAA==.Rhymaek:BAAALgAECgEJAwABLgAECggJFwAiACETAA==.Rhyss:BAAALgAECgQJBAAAAA==.',
Ri='Rike:BAEBLgAECn8/AAMcAAkJ+iJhHwCLAgAcAAkJ5SFhHwCLAgAHAAYJlB4DEQC0AQAAAA==.',
Ro='Roflbackpack:BAAALgAECgkJBwAAAA==.Roflbalanced:BAAALgAECgQJCAAAAA==.Roflgotnerfd:BAAALgADCgMJAwABLgAECgkJBwAGAAAAAA==.Roflhazotime:BAABLgAECn8nAAIDAAkJVyOZCQD/AgADAAkJVyOZCQD/AgAAAA==.Roland:BAABLgAECn8yAAMXAAkJvBOhMADfAQAXAAkJvBOhMADfAQAUAAYJQQtzTQDWAAAAAA==.Rolandin:BAABLgAECn8/AAIiAAkJ1RfZEgB6AgAiAAkJ1RfZEgB6AgAAAA==.Rollaen:BAAALgADCgYJDAAAAA==.Rollan:BAAALgAECgQJCwAAAA==.Rook:BAABLgAFFH8JAAIFAAQJfxRtGwA+AQAFAAQJfxRtGwA+AQABLgAFFAcJKwACAL0iAA==.Roscjou:BAABLgAECn8YAAIBAAcJsQT1YADCAAABAAcJsQT1YADCAAAAAA==.Ross:BAAALgAECgYJDwAAAA==.',
Ru='Rubisco:BAAALgAECgYJCwAAAA==.Ruh:BAAALgAECgMJBgABLgAECgkJPgASAJkaAA==.',
Ry='Rylagosa:BAABLgAECn85AAMIAAkJghiKDwDTAQAIAAcJNxiKDwDTAQAQAAkJZRICJgCwAQAAAA==.Rynehardt:BAAALgADCgcJBwAAAA==.Ryzesmidge:BAABLgAECn8XAAIMAAkJGRHZWQDQAQAMAAkJGRHZWQDQAQAAAA==.',
['Rê']='Rêdrum:BAABLgAFFH8GAAIEAAMJrgssqwDIAAAEAAMJrgssqwDIAAABLgAFFAUJGQAaAFkNAA==.',
Sa='Sabithia:BAAALgAECgEJAQAAAA==.Sahathiel:BAAALgAFFAEJAQAAAA==.Salandria:BAAALgAECgYJEAAAAA==.Salandriath:BAAALgAECgYJCwAAAA==.Sange:BAAALgAECgcJDQAAAA==.Sarionian:BAABLgAECn86AAIXAAkJ7xDoMgDTAQAXAAkJ7xDoMgDTAQAAAA==.Sarvin:BAAALgADCgcJBwABLgAECgkJKwACAEscAA==.Sarvinblue:BAABLgAECn8rAAMCAAkJSxxAFgCYAgACAAkJSxxAFgCYAgABAAMJLQ8SagCbAAAAAA==.Saucestash:BAAALgAECgIJAgAAAA==.Sauronic:BAAALgAECgYJCgAAAA==.',
Se='Searchlights:BAAALgAECgYJCwAAAA==.Seshu:BAAALgAECgEJAQAAAA==.Sevrin:BAAALgADCgEJAQAAAA==.',
Sh='Shambúlance:BAAALgAECgIJAgAAAA==.Shanaynay:BAAALgAECgQJBAAAAA==.Shanir:BAAALgADCgMJAwAAAA==.Shanksie:BAABLgAECn8bAAIgAAcJkAaDEwDwAAAgAAcJkAaDEwDwAAAAAA==.Shazlulu:BAABLgAECn8oAAICAAgJmRkCAQCvAQACAAgJmRkCAQCvAQAAAA==.Shedoa:BAAALgAECgYJBgAAAA==.Shiftywelt:BAAALgADCggJDAAAAA==.Shinmothee:BAABLgAECn8iAAIOAAkJkApWBgBeAQAOAAkJkApWBgBeAQAAAA==.Shinsura:BAAALgADCgcJEAAAAA==.Shtamman:BAAALgADCgUJBQAAAA==.',
Si='Silvantis:BAAALgADCgEJAQAAAA==.Siobhán:BAABLgAECn8tAAIFAAkJnx8IDwA7AgAFAAkJnx8IDwA7AgAAAA==.',
Sk='Skandle:BAAALgADCgMJAwAAAA==.',
Sl='Sleepypanda:BAABLgAECn8jAAIiAAkJtxnXFQBdAgAiAAkJtxnXFQBdAgAAAA==.Sloe:BAABLgAECn86AAMNAAkJExyEDQCOAgANAAkJExyEDQCOAgARAAEJrAXclAAlAAAAAA==.',
Sm='Smokalot:BAAALgADCgEJAQAAAA==.',
Sn='Sneakez:BAAALgAFFAEJAQAAAA==.',
So='Somebody:BAAALgAECgQJBQAAAA==.Soulitude:BAAALgAECgEJAQAAAA==.Southerngal:BAAALgADCgQJBQAAAA==.',
Sp='Speedbeefbal:BAAALgADCgQJBAAAAA==.Speedkweef:BAAALgAECggJDgAAAA==.Speedmeat:BAABLgAECn8gAAMCAAkJ8givZAAtAQACAAgJxAivZAAtAQABAAIJmAO/nQA+AAAAAA==.Spinny:BAAALgAECgYJBgAAAA==.Sporkulous:BAABLgAECn8vAAMKAAgJfxNOSgDCAQAKAAgJfxNOSgDCAQAeAAEJFwEWSAAQAAAAAA==.',
Sq='Squal:BAABLgAECn81AAMcAAkJCCCtEADhAgAcAAkJCCCtEADhAgAHAAUJ/BhSGwA9AQAAAA==.Squiggle:BAABLgAECn89AAIHAAkJjSJMAgASAwAHAAkJjSJMAgASAwAAAA==.',
St='Stalkêr:BAAALgADCgIJAgAAAA==.Stewy:BAAALgAECgYJCAAAAA==.Stickybunz:BAABLgAECn8ZAAIPAAgJURUCJgDIAQAPAAgJURUCJgDIAQABLgAFFAQJDwARAHAFAA==.Striker:BAEALgAECgQJDwABLgAECgkJPwAcAPoiAA==.Strombone:BAAALgADCgEJAgABLgAECgIJEAAGAAAAAA==.Stunseed:BAABLgAECn8rAAIYAAkJ1hhFCwAuAgAYAAkJ1hhFCwAuAgAAAA==.',
Su='Sumo:BAAALgAECgEJAQAAAA==.Sungjinwu:BAAALgAECgUJBQAAAA==.Sunnmage:BAAALgAECgcJCAAAAA==.Sunshíne:BAABLgAECn8hAAMHAAkJPQxJHAA0AQAHAAgJ7wxJHAA0AQAcAAgJQQfLsAAeAQAAAA==.Surf:BAABLgAECn8XAAIDAAcJWRxmNAD1AQADAAcJWRxmNAD1AQAAAA==.',
Sw='Sweetbunz:BAACLgAFFH8PAAMRAAQJcAW0JQDLAAARAAQJcAW0JQDLAAANAAQJAAnwHQDJAAAuAAQKfzoAAxEACQnHFpYXAAsCABEACQnHFpYXAAsCAA0ACAlYDjAxAEgBAAAA.Swegin:BAAALgAECgIJAgABLgAECgIJAwAGAAAAAA==.',
Sx='Sxes:BAAALgAECgYJBgAAAA==.',
Sy='Synaminaphyn:BAAALgAECgEJAQAAAA==.Syver:BAABLgAECn8pAAMEAAkJ2BkBRwDtAQAEAAgJGxsBRwDtAQAJAAEJCRHAWAA9AAAAAA==.',
['Sì']='Sìrfuzywuzy:BAAALgAECgYJDwAAAA==.',
['Sí']='Sírlancealot:BAAALgADCgYJBgABLgAECgYJDwAGAAAAAA==.',
Ta='Taisty:BAAALgADCgQJBAAAAA==.Takers:BAAALgAECgYJCQAAAA==.Tanagra:BAAALgAECgEJAQABLgAECgkJPgASAJkaAA==.Taniss:BAABLgAECn8pAAIlAAkJlQioCwBcAQAlAAkJlQioCwBcAQAAAA==.Tanner:BAABLgAECn8dAAMeAAgJDgnESgAnAQAeAAgJwQfESgAnAQAKAAIJoBF5ogCHAAAAAA==.Tarnaby:BAAALgAECgEJAQAAAA==.',
Te='Teboe:BAAALgAECgYJBwAAAA==.Tedman:BAABLgAECn8vAAMBAAkJjRlUEwBTAgABAAkJjRlUEwBTAgACAAMJmgdWjwBaAAAAAA==.Temel:BAABLgAECn82AAMCAAkJfQ4/TgB4AQACAAgJtww/TgB4AQABAAkJUw05NABqAQAAAA==.Tenelum:BAAALgAECgQJCAABLgAECgkJNgACAH0OAA==.Testoecles:BAAALgAECgMJBQABLgAECgYJBwAGAAAAAA==.',
Th='Thadrack:BAABLgAECn83AAIMAAkJlAi4fQB8AQAMAAkJlAi4fQB8AQAAAA==.Thaine:BAAALgADCgEJAQABLgAECgcJDQAGAAAAAA==.Thalonstin:BAAALgAECgQJCAAAAA==.Thanee:BAABLgAFFH8HAAINAAUJ4A87FAAjAQANAAUJ4A87FAAjAQABLgAECgcJDQAGAAAAAA==.Thanevoker:BAAALgAECgcJDQAAAA==.Theodrid:BAACLgAFFH8SAAIcAAcJiRL4JQBxAQAcAAcJiRL4JQBxAQAuAAQKfyMAAhwACQmhHjAkAJcCABwACQmhHjAkAJcCAAAA.Thoreum:BAAALgAECgEJAgAAAA==.Thraxia:BAABLgAECn8XAAISAAgJWAUGlgAsAQASAAgJWAUGlgAsAQAAAA==.Thrombin:BAAALgAECgMJAwAAAA==.',
Ti='Tigertigress:BAAALgAECgQJBAAAAA==.Tinkíe:BAABLgAECn8iAAQWAAkJ9Ry2GQDjAQAWAAgJ0By2GQDjAQAZAAQJQRmWTgAJAQAVAAUJ2QxIaQDbAAAAAA==.Tirzahdozier:BAABLgAECn8XAAMiAAgJIRNTJADiAQAiAAgJIRNTJADiAQAcAAEJXwJ60AEYAAAAAA==.Tiwohnne:BAAALgAECgYJCgAAAA==.',
Tl='Tla:BAAALgAECgIJAwAAAA==.',
To='Tooey:BAAALgAECgEJAQAAAA==.',
Tr='Treat:BAABLgAECn9DAAIRAAkJfySNAgBAAwARAAkJfySNAgBAAwAAAA==.Tremblement:BAAALgADCgMJAwAAAA==.Trippyshock:BAABLgAFFH8QAAIBAAQJlxwvGwBBAQABAAQJlxwvGwBBAQABLgAFFAkJTgASAFskAA==.Tristitia:BAABLgAECn8vAAMEAAkJ+BYgMQA6AgAEAAkJ+BYgMQA6AgAJAAIJGAYyWQA8AAAAAA==.Trolidan:BAAALgAECgEJAQAAAA==.',
Tu='Tubbs:BAABLgAECn8ZAAIEAAkJAxw3LQBLAgAEAAkJAxw3LQBLAgAAAA==.Turkeltin:BAAALgAECgYJEAABLgAFFAQJCgAMAF0ZAA==.',
Tw='Twiggle:BAAALgAECgQJBAABLgAECggJFwAiACETAA==.',
Ty='Tyche:BAABLgAECn8XAAMCAAYJcw1jZgAoAQACAAYJcw1jZgAoAQABAAEJ2gHWwwAYAAAAAA==.Tyrdrin:BAAALgAECgEJAQAAAA==.Tysbich:BAAALgAECgQJBAABLgAECgkJLQAiAOMhAA==.',
Ui='Uiewedaoez:BAABLgAECn80AAIXAAkJWST7AgCZAwAXAAkJWST7AgCZAwAAAA==.',
Um='Umakkel:BAAALgAECgYJDgAAAA==.Umiko:BAAALgADCgUJBQAAAA==.',
Ur='Urd:BAABLgAECn8hAAIEAAkJ9BAkWgC4AQAEAAkJ9BAkWgC4AQAAAA==.',
Va='Vaelrelyn:BAABLgAECn8UAAMhAAYJJhD1HgBZAQAhAAYJJhD1HgBZAQASAAIJ4gHuLwEhAAAAAA==.Vaelrieth:BAABLgAECn8YAAIcAAcJIwc1zwD0AAAcAAcJIwc1zwD0AAAAAA==.Vains:BAACLgAFFH8RAAIcAAUJkRwBOgA4AQAcAAUJkRwBOgA4AQAuAAQKfyIAAhwACQkzIc4mAGgCABwACQkzIc4mAGgCAAAA.Valoras:BAAALgADCgEJAQAAAA==.Vardis:BAABLgAECn8uAAIMAAkJMh+VKgBwAgAMAAkJMh+VKgBwAgAAAA==.',
Ve='Velinami:BAAALgAECgIJAwAAAA==.Venato:BAAALgADCgEJBAABLgAECgkJNgACAH0OAA==.Vendettuh:BAAALgADCgEJAQAAAA==.Verazene:BAABLgAFFH8GAAIaAAMJmhvpBwD8AAAaAAMJmhvpBwD8AAAAAA==.Verenthirl:BAAALgAECgUJBAAAAA==.Veronica:BAABLgAECn87AAIMAAkJ/h6KFQDYAgAMAAkJ/h6KFQDYAgAAAA==.Verren:BAABLgAECn8rAAIYAAkJFBrYCQBMAgAYAAkJFBrYCQBMAgAAAA==.Versutia:BAAALgAECgIJAgAAAA==.',
Vi='Virse:BAAALgAECgUJCQAAAA==.Virtigo:BAAALgADCgQJCAAAAA==.Vixie:BAAALgAECgcJBwAAAA==.',
Vy='Vye:BAAALgAECgEJAQAAAA==.Vyerith:BAABLgAECn8kAAISAAkJjhzvKAA4AgASAAkJjhzvKAA4AgAAAA==.',
We='Weltamus:BAABLgAECn8pAAMJAAkJABhHHAB4AQAEAAgJyg80dQB5AQAJAAQJ9yBHHAB4AQAAAA==.Weltasaur:BAABLgAECn8bAAIYAAYJBhixHgBYAQAYAAYJBhixHgBYAQAAAA==.Weltazar:BAABLgAECn82AAIBAAkJrxcuJADFAQABAAkJrxcuJADFAQAAAA==.Westside:BAACLgAFFH8lAAMMAAgJAyOzBwDBAgAMAAgJAyOzBwDBAgAOAAEJqAngBwA5AAAuAAQKfyMAAgwACQnVJmYBAIsDAAwACQnVJmYBAIsDAAAA.',
Wi='Wickedfluff:BAAALgADCgYJBgAAAA==.Wickët:BAAALgAECgQJBwABLgAECgkJIAASAGsjAA==.Wildtiger:BAABLgAECn8zAAIoAAkJ5hgdCABQAgAoAAkJ5hgdCABQAgAAAA==.',
Wo='Wolfslied:BAAALgAECgYJCAAAAA==.',
Wr='Wrecken:BAAALgADCgUJBQAAAA==.',
Wu='Wulfenhide:BAABLgAECn8zAAQgAAkJ8B5qAgC1AgAgAAkJ8B5qAgC1AgAFAAMJoAfkUACkAAAlAAEJeAVgDwArAAAAAA==.',
Wy='Wyzsky:BAAALgAECgEJAwABLgAECgkJNgACAH0OAA==.',
Xa='Xal:BAAALgADCgEJAQABLgAECgMJBQAGAAAAAA==.Xalreth:BAABLgAECn8gAAIDAAkJPg6ZXAByAQADAAkJPg6ZXAByAQAAAA==.Xaviana:BAAALgAECgkJKgAAAQ==.',
Xc='Xcedrin:BAABLgAECn8fAAMRAAkJOQgeOwAmAQARAAgJOAceOwAmAQANAAMJXwWBcQBhAAAAAA==.',
Ya='Yastinfect:BAABLgAECn8eAAIDAAkJ0BgPLwBAAgADAAkJ0BgPLwBAAgAAAA==.Yastypoo:BAAALgAECgEJAQAAAA==.',
Yu='Yurika:BAEBLgAECn8xAAIiAAkJJibaBwAOAwAiAAkJJibaBwAOAwAAAA==.Yushi:BAABLgAECn8tAAIFAAkJlx/xCgB1AgAFAAkJlx/xCgB1AgAAAA==.',
Yv='Yväinne:BAAALgAECgIJAgAAAA==.',
Za='Zareen:BAAALgADCgkJCQAAAA==.Zaru:BAAALgADCgcJEgAAAA==.Zayfall:BAAALgAECgYJEwAAAA==.',
Ze='Zelenor:BAABLgAECn8nAAQEAAkJfxTHNgAkAgAEAAkJfxTHNgAkAgAnAAYJKQV4KQCIAAAJAAQJYQOLSwBhAAAAAA==.Zenweaver:BAACLgAFFH8RAAIZAAMJVSS9HgA2AQAZAAMJVSS9HgA2AQAuAAQKfx8AAhkACQlqIlUEAEcDABkACQlqIlUEAEcDAAAA.',
Zi='Ziur:BAAALgADCgEJAQAAAA==.',
Zo='Zonde:BAAALgAECgEJAQAAAA==.',
Zu='Zud:BAABLgAECn8hAAIEAAkJRiGrEwDSAgAEAAkJRiGrEwDSAgAAAA==.',
['Zö']='Zödd:BAAALgAECgEJAQAAAA==.',
['Öå']='Öåken:BAAALgAECgEJAQABLgAECgkJOgAXAO8QAA==.',
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
