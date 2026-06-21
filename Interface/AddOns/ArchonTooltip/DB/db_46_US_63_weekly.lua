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

local lookup = {'Warlock-Affliction','Warlock-Demonology','Paladin-Protection','Monk-Mistweaver','Mage-Frost','Monk-Windwalker','Monk-Brewmaster','Hunter-BeastMastery','Unknown-Unknown','Paladin-Retribution','Druid-Restoration','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Restoration','Shaman-Elemental','DemonHunter-Havoc','Warlock-Destruction','Priest-Holy','Priest-Shadow','Priest-Discipline','Paladin-Holy','Warrior-Protection','Hunter-Survival','DemonHunter-Devourer','Shaman-Enhancement','DemonHunter-Vengeance','Warrior-Fury','Warrior-Arms','Evoker-Augmentation','Evoker-Devastation','Druid-Balance','Hunter-Marksmanship','Rogue-Outlaw','Rogue-Subtlety','Mage-Fire','DeathKnight-Blood','Rogue-Assassination','Evoker-Preservation','Druid-Feral','Mage-Arcane',}
local provider = {region='US',realm='Dawnbringer',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abdalhazred:BAACLgAFFH8cAAMBAAYJvSG/AgB3AQABAAYJvSG/AgB3AQACAAEJiR/xvQBMAAAuAAQKfzgAAwEACQmYJFIAAGYDAAEACAm3JVIAAGYDAAIAAwnQHSWsAOsAAAAA.Abillus:BAAALgAECgEJAwAAAA==.Abilus:BAABLgAECn8VAAIDAAQJsRdfIwD6AAADAAQJsRdfIwD6AAAAAA==.Abolis:BAAALgAECgMJBgAAAA==.',
Ae='Aeldriel:BAAALgAECgMJAwAAAA==.Aeoyn:BAAALgAECgEJAQAAAA==.',
Ag='Aggar:BAAALgADCgkJGwABLgAECgkJTAAEAL4aAA==.',
Ak='Akoa:BAAALgAECgEJAQAAAA==.',
Al='Alarak:BAABLgAECn8bAAIBAAgJcRVsCQCtAQABAAgJcRVsCQCtAQAAAA==.Alerion:BAAALgAECgEJAQAAAA==.Alnara:BAAALgAECgEJAgAAAA==.Aloxys:BAAALgADCgcJCQAAAA==.Alvierearn:BAABLgAECn8WAAIFAAgJuxE6kgBTAQAFAAgJuxE6kgBTAQAAAA==.',
Am='Amoradis:BAAALgADCgUJEgAAAA==.',
An='Anaeir:BAAALgADCgYJBgAAAA==.Angriff:BAAALgADCgQJBQAAAA==.Anisette:BAABLgAECn8pAAMGAAkJnRcdEgAxAgAGAAkJnRcdEgAxAgAHAAQJDgqzaAB2AAAAAA==.Annuket:BAAALgAECgYJBgAAAA==.Anthria:BAAALgADCgkJGwAAAA==.',
Ap='Apexpredåtor:BAAALgADCgIJAgAAAA==.',
Aq='Aqurala:BAABLgAECn8jAAIIAAkJXRxdIgBbAgAIAAkJXRxdIgBbAgAAAA==.',
Ar='Aradem:BAAALgADCgcJBwABLgAFFAMJAwAJAAAAAA==.Aravenn:BAAALgAFFAMJAwAAAA==.Arcis:BAABLgAECn8kAAIKAAcJ0RKKkwBMAQAKAAcJ0RKKkwBMAQAAAA==.Ardeniro:BAAALgAECgIJBwAAAA==.Arealis:BAAALgADCgcJDAAAAA==.Argatem:BAAALgAECgQJBAABLgAECggJKgALAEYeAA==.Arkangel:BAACLgAFFH8IAAIMAAQJIQ2njwDsAAAMAAQJIQ2njwDsAAAuAAQKfyoAAwwACQk7HEAmAGsCAAwACQk7HEAmAGsCAA0AAQlhCbU8AC0AAAAA.Arke:BAAALgAECgMJAwAAAA==.Arkharon:BAAALgADCgYJCQAAAA==.Arralyon:BAAALgADCgMJBgAAAA==.Artemesia:BAAALgAECgYJBwABLgAFFAcJLgAOAO4eAA==.Arthäs:BAAALgAECgQJBAAAAA==.Aryrn:BAAALgADCgUJBQAAAA==.',
As='Asakua:BAAALgAECgMJBgAAAA==.Asiya:BAAALgAECgQJBQAAAA==.Assandra:BAAALgADCgUJBQAAAA==.Astræa:BAAALgAECgYJBgAAAA==.',
At='Athul:BAAALgADCgUJCgAAAA==.',
Au='Aurlyn:BAAALgAECgMJAwAAAA==.',
Av='Avatartele:BAAALgAECgIJAwAAAA==.Avatartouka:BAABLgAECn8jAAMOAAgJ5yGaEQDBAgAOAAgJ5yGaEQDBAgAPAAQJ9RPUbQCgAAAAAA==.Avianthel:BAAALgADCgMJAgAAAA==.Avraria:BAABLgAECn8aAAIQAAkJphULEQAZAgAQAAkJphULEQAZAgAAAA==.Avyl:BAABLgAECn8bAAQBAAYJ+xHaFQAcAQABAAYJ1hDaFQAcAQARAAQJNhHVHADBAAACAAIJpgZvHwExAAAAAA==.Avylastorica:BAAALgADCgYJBgABLgAECgYJGwABAPsRAA==.',
Aw='Awsomninja:BAABLgAECn8lAAIHAAkJAiOcBQDmAgAHAAkJAiOcBQDmAgAAAA==.',
Ax='Axxain:BAAALgADCgkJGgAAAA==.',
Az='Azaralle:BAAALgADCgEJAQAAAA==.Azeazal:BAAALgAECgcJEwAAAA==.Azlifan:BAAALgADCgQJBAAAAA==.Azorthragal:BAAALgADCgYJBgABLgAECgUJBwAJAAAAAA==.',
Ba='Baddlandss:BAAALgAECgQJCAAAAA==.Bagador:BAAALgAFFAEJAQAAAA==.Bastais:BAAALgAECgEJAQAAAA==.Batozai:BAAALgADCgEJAQAAAA==.Baumstack:BAAALgADCgUJBQAAAA==.',
Bd='Bdibz:BAAALgADCgcJDAAAAA==.',
Be='Beautifulluv:BAABLgAECn8sAAQSAAkJSyIKBQAtAwASAAkJSyIKBQAtAwATAAYJzA1zRQD5AAAUAAEJkAzNUwA6AAAAAA==.Beelzabubba:BAAALgAECgkJAwAAAA==.Beewaregobs:BAAALgAECgIJAgAAAA==.Bekabeka:BAACLgAFFH8dAAIVAAYJox0NDgDYAQAVAAYJox0NDgDYAQAuAAQKf00ABBUACQk+JFcFAD0DABUACQk+JFcFAD0DAAoABQm5CAEGAbEAAAMABQmOBj04AH4AAAAA.Belfour:BAAALgAECgEJAgAAAA==.Bera:BAAALgAECgUJDwABLgAECgkJCwAJAAAAAA==.Beramage:BAAALgAECgEJAQAAAA==.',
Bi='Billybobjr:BAACLgAFFH8IAAMOAAMJgCK0LgAnAQAOAAMJgCK0LgAnAQAPAAEJDQUWDAA2AAAuAAQKf0kAAw4ACQnrIdUGAEMDAA4ACQnrIdUGAEMDAA8AAQkhEKOmADEAAAAA.Bippitybop:BAAALgAECgEJAQAAAA==.',
Bl='Blackbart:BAAALgADCgcJCgAAAA==.',
Bo='Boamere:BAABLgAECn8/AAIWAAkJoxwABwCXAgAWAAkJoxwABwCXAgAAAA==.Botemedel:BAAALgADCgEJAQAAAA==.',
Br='Braided:BAAALgAECgIJAwAAAA==.Brakkar:BAABLgAECn9MAAIXAAkJqhfYDQBKAgAXAAkJqhfYDQBKAgAAAA==.Brandish:BAAALgADCgcJBwAAAA==.Breadstick:BAABLgAECn83AAILAAkJmyUnAQDPAwALAAkJmyUnAQDPAwAAAA==.Brevik:BAAALgADCgMJAwAAAA==.Brutaal:BAAALgADCgcJCwAAAA==.Brynhild:BAAALgAFFAIJAwAAAA==.Brütaal:BAABLgAECn8iAAMOAAgJthe6NQDaAQAOAAcJphe6NQDaAQAPAAUJGgaddQCMAAAAAA==.',
Bu='Bubsydogo:BAABLgAECn8bAAIPAAkJPRTtHQDyAQAPAAkJPRTtHQDyAQAAAA==.Buddytheelf:BAABLgAECn8yAAMCAAkJFST1BABAAwACAAkJuCP1BABAAwARAAIJiyXbLABkAAAAAA==.Bumpyflea:BAAALgADCgUJBQAAAA==.',
Ca='Cairnsilvers:BAAALgADCgEJAQAAAA==.Camus:BAABLgAECn8aAAIKAAgJHBqvTwDZAQAKAAgJHBqvTwDZAQAAAA==.Capped:BAAALgADCgMJAwAAAA==.Catgirl:BAAALgAECgYJCAAAAA==.',
Ce='Cebollin:BAAALgAECgUJCAAAAA==.Celaian:BAAALgAECgUJCgABLgAFFAEJAQAJAAAAAA==.Celamor:BAAALgAECgQJBwAAAA==.Celasmine:BAAALgADCgYJCAAAAA==.Celpanda:BAAALgAFFAEJAQAAAA==.',
Ch='Chamoan:BAAALgAECgMJAwAAAA==.Charlamayne:BAAALgADCgcJBwAAAA==.Charybdia:BAABLgAECn8nAAIYAAkJngdAcQBAAQAYAAkJngdAcQBAAQAAAA==.Chidõri:BAACLgAFFH8YAAIPAAYJhBopGgBKAQAPAAYJhBopGgBKAQAuAAQKfy4AAw8ACQmDI0kFAEMDAA8ACQmDI0kFAEMDABkAAgnPFuUlAHkAAAAA.Chimerå:BAAALgADCgEJAQAAAA==.Chopstix:BAAALgADCgcJDgAAAA==.Chudlock:BAAALgAECgYJEgAAAA==.Chunni:BAABLgAECn8hAAIGAAkJHAoaLwBNAQAGAAkJHAoaLwBNAQAAAA==.',
Ci='Cilicia:BAAALgADCgUJBQAAAA==.',
Co='Codap:BAAALgADCgcJBwAAAA==.Coffees:BAAALgAECgEJAgAAAA==.Coolerfrieza:BAAALgAECgUJCwAAAA==.',
Cp='Cpr:BAABLgAECn8XAAIVAAcJiCGvDwCXAgAVAAcJiCGvDwCXAgAAAA==.',
Cr='Crayonman:BAAALgAECgMJAwABLgAFFAQJBwAXANghAA==.Crepic:BAAALgAECgQJBAAAAA==.Cruelkitty:BAABLgAECn8gAAMQAAgJIAUHRACmAAAQAAYJzgYHRACmAAAaAAgJMgHvIQCOAAAAAA==.',
Cu='Cubanwarlock:BAAALgAECgIJAgAAAA==.Cudibandit:BAAALgADCgcJDwAAAA==.Cullodena:BAAALgAECgEJAQAAAA==.',
Cy='Cynaria:BAAALgAECgEJAwABLgAFFAIJBgALADobAA==.Cyralai:BAACLgAFFH82AAILAAgJQRfSBgCZAgALAAgJQRfSBgCZAgAuAAQKfxkAAgsACQlQIfEQALACAAsACQlQIfEQALACAAAA.',
Da='Dabofdeath:BAAALgAECgIJAgAAAA==.Dalov:BAABLgAECn8gAAMVAAcJSSbxBwDvAgAVAAcJSSbxBwDvAgAKAAIJbx29HgGVAAAAAA==.Dankley:BAABLgAECn8WAAIbAAgJYQcETQATAQAbAAgJYQcETQATAQAAAA==.Darkestnyte:BAAALgAECggJDwAAAA==.Darkk:BAAALgAECgQJDQAAAA==.Darkpalidin:BAAALgAECgYJBgABLgAECgkJKgAFAFgbAA==.Darkrhaenies:BAAALgADCgcJBwAAAA==.Darkwindx:BAAALgADCggJCQABLgAECgYJEgAJAAAAAA==.Datezero:BAAALgADCgQJBAAAAA==.',
Dd='Ddream:BAAALgADCgQJBAAAAA==.',
De='Deadhealer:BAAALgADCgMJBQAAAA==.Deafknighte:BAAALgAECgMJAwAAAA==.Deathboi:BAABLgAECn8xAAIMAAkJwxsWHACfAgAMAAkJwxsWHACfAgAAAA==.Deathburgur:BAABLgAECn8gAAMMAAkJfxX8NwAfAgAMAAkJfxX8NwAfAgANAAcJpQt/FQAuAQAAAA==.Deathfromme:BAAALgAECgYJCgAAAA==.Deathstro:BAAALgAECgYJDgABLgAFFAQJCAAMACENAA==.Decayed:BAAALgAECgUJDgAAAA==.Demonicuss:BAAALgAECgEJAQAAAA==.Demontress:BAAALgADCgQJBAAAAA==.Dentridios:BAAALgADCgIJAgAAAA==.Deson:BAABLgAECn8mAAMVAAkJCRIALgCmAQAVAAkJCRIALgCmAQAKAAUJiQi4DAGpAAAAAA==.Deviantart:BAAALgAECgQJBAAAAA==.',
Di='Diana:BAABLgAECn8kAAIIAAkJqA2rSgDBAQAIAAkJqA2rSgDBAQAAAA==.Diietriich:BAABLgAECn8zAAIFAAkJriJGDQAPAwAFAAkJriJGDQAPAwAAAA==.Dilligaaf:BAAALgADCgMJAwAAAA==.',
Do='Docbeanz:BAAALgADCgMJAwAAAA==.Donkypunch:BAAALgADCgQJBAAAAA==.Dontjudgemê:BAAALgADCgIJAgAAAA==.Doodlekhal:BAAALgADCgMJAwAAAA==.Dopie:BAAALgADCgIJAgAAAA==.Dorcina:BAAALgAECgIJAgAAAA==.',
Dr='Dracthyr:BAAALgADCgUJDQAAAA==.Dragonwarrio:BAAALgAECgEJAQAAAA==.Dragoondpain:BAAALgAECgQJCwAAAQ==.Drakai:BAAALgAECgEJAgAAAA==.Draltina:BAABLgAECn8XAAMBAAgJPAmkDQBaAQABAAgJPAmkDQBaAQACAAEJywLtLwEhAAAAAA==.Drazira:BAABLgAECn8hAAIYAAkJsgTUlQD1AAAYAAkJsgTUlQD1AAAAAA==.Drugonwerier:BAAALgADCgEJAgAAAA==.Drunkbera:BAAALgAECgcJDQAAAA==.Druzzlek:BAAALgAECgEJAQAAAA==.',
Du='Dubalpally:BAAALgADCggJDQAAAA==.Dunks:BAABLgAFFH8FAAICAAMJJwNRjwCmAAACAAMJJwNRjwCmAAAAAA==.Duskfu:BAABLgAECn8uAAIGAAkJnR/CCgCXAgAGAAkJnR/CCgCXAgAAAA==.',
Dy='Dylghoul:BAAALgADCgUJBQAAAA==.',
['Dí']='Dírac:BAABLgAFFH8GAAICAAMJTw3CfQDJAAACAAMJTw3CfQDJAAABLgAFFAQJCQAOAGkcAA==.',
Ec='Eclipsekitty:BAAALgAECgUJBgABLgAFFAQJCQAVAOIQAA==.',
Ed='Edwillei:BAAALgAECgUJCAAAAA==.',
Ef='Efforex:BAAALgADCgQJBAAAAA==.',
Ei='Einhar:BAAALgAECgEJAgAAAA==.',
El='Elactoplasm:BAAALgAECgMJAwAAAA==.Elderslapaho:BAAALgADCgUJBgAAAA==.Ellistrae:BAAALgAECgYJCQAAAA==.Ellysia:BAAALgADCgEJAQAAAA==.',
Em='Emmel:BAAALgADCggJCwAAAA==.',
Ep='Epicknee:BAAALgAECgEJAQAAAA==.',
Eq='Equeslucis:BAAALgAECgcJBwAAAA==.',
Er='Erodrana:BAAALgAECgYJEgABLgAECgkJIQAYALIEAA==.Eromir:BAAALgAECgUJCgAAAA==.Eryi:BAABLgAECn9MAAIEAAkJvhrKDwCoAgAEAAkJvhrKDwCoAgAAAA==.',
Et='Ethan:BAABLgAECn8eAAMcAAkJnRvcEQDZAQAcAAcJIRjcEQDZAQAbAAQJ6CL8VQD1AAAAAA==.',
Ev='Evonari:BAAALgADCgIJAgAAAA==.',
Ex='Exoticfrost:BAAALgADCgIJAgAAAA==.Expertnewb:BAAALgAECgIJAgABLgAECgkJKgAFAFgbAA==.',
['Eí']='Eísheth:BAAALgADCgUJBAAAAA==.',
Fa='Faegen:BAAALgAECgEJAgAAAA==.Falkønn:BAAALgAECgMJAwAAAA==.Fallumn:BAAALgAECgEJAQAAAA==.Fangytooth:BAACLgAFFH8HAAIXAAQJ2CFDCACMAQAXAAQJ2CFDCACMAQAuAAQKfy4AAhcACQl5JPsCABADABcACQl5JPsCABADAAAA.Fashaun:BAAALgAECgIJAgAAAA==.Faze:BAABLgAECn8aAAIFAAYJyx+LYgC5AQAFAAYJyx+LYgC5AQAAAA==.',
Fe='Fellamayne:BAAALgAECgEJAQAAAA==.Fellamayyne:BAAALgADCgEJAQAAAA==.Ferrus:BAACLgAFFH8kAAMYAAgJPiKrAwD9AQAYAAgJPiKrAwD9AQAQAAQJsxxfHADAAAAuAAQKfx4AAxAACQn1JdANAIYCABgACQlWJOwcAKQCABAABwncJNANAIYCAAAA.',
Ff='Ffleuderflam:BAAALgAECgYJBgAAAA==.',
Fl='Floors:BAAALgAECgEJAQAAAA==.',
Fr='Frose:BAAALgADCgEJAQAAAA==.Frostyblast:BAAALgADCgUJBgAAAA==.',
Fu='Fupacabra:BAAALgADCgEJAQAAAA==.Furiiosa:BAAALgAECgUJBQAAAA==.Furiosity:BAAALgAECgMJBQAAAA==.Fuzzybear:BAAALgAECgcJCAABLgAFFAQJBwAXANghAA==.Fuzzybeard:BAAALgAECgYJBgABLgAFFAQJBwAXANghAA==.Fuzzyspells:BAAALgAECgEJAQABLgAFFAQJBwAXANghAA==.Fuzzywar:BAAALgAECgYJBwABLgAFFAQJBwAXANghAA==.',
['Fõ']='Fõrtress:BAAALgAECgMJBAAAAA==.',
Ga='Gabomonk:BAABLgAFFH8FAAIHAAIJ1iRcNwDJAAAHAAIJ1iRcNwDJAAAAAA==.Galvandra:BAABLgAECn8lAAMVAAkJGiQqAgCNAwAVAAkJGiQqAgCNAwAKAAgJbx7BAAA7AgAAAA==.Gamalia:BAAALgADCgUJBQAAAA==.Garudekhan:BAAALgADCgUJBQAAAA==.',
Ge='Genreallee:BAABLgAECn8dAAIKAAcJ1hIPjgBVAQAKAAcJ1hIPjgBVAQAAAA==.Gernab:BAAALgADCgYJBgAAAA==.',
Gh='Ghost:BAABLgAECn8WAAILAAYJ9xt+NgDOAQALAAYJ9xt+NgDOAQAAAA==.',
Gi='Gizzar:BAAALgADCgYJCgAAAA==.',
Gl='Glau:BAAALgAECgQJBAABLgAECggJCQAJAAAAAA==.Glimpsed:BAAALgAECgcJDgABLgAECgkJCwAJAAAAAA==.Globgore:BAAALgADCgIJBAAAAA==.Gloçk:BAAALgAECgMJCAABLgAECgYJEQAJAAAAAA==.',
Go='Goofy:BAABLgAECn8fAAIKAAcJYCHDJACUAgAKAAcJYCHDJACUAgAAAA==.Goor:BAAALgAECgEJAQAAAA==.Gorrik:BAAALgADCgUJBQAAAA==.',
Gr='Graeae:BAAALgAECgcJDAAAAA==.Greyfeather:BAAALgADCgEJAgAAAA==.Grimeace:BAAALgADCgQJBAAAAA==.',
Gu='Gunduin:BAACLgAFFH8FAAIIAAIJ/hYPfwCaAAAIAAIJ/hYPfwCaAAAuAAQKfx4AAggACAmuIBQeAFECAAgACAmuIBQeAFECAAAA.',
Gw='Gweb:BAAALgAECgIJAgAAAA==.',
Gy='Gyda:BAABLgAECn8oAAIUAAgJRiHrBwD5AgAUAAgJRiHrBwD5AgAAAA==.Gyuyuki:BAABLgAECn9QAAIPAAkJahelFQA6AgAPAAkJahelFQA6AgAAAA==.',
Ha='Hakuanah:BAAALgADCgEJAQAAAA==.Halvorak:BAAALgADCgcJCgAAAA==.Harryp:BAACLgAFFH8KAAIdAAQJ7gxqOwDZAAAdAAQJ7gxqOwDZAAAuAAQKfzYAAx4ACQm5GP0GANcBAB0ACQnlEp4dAOoBAB4ACQlDFf0GANcBAAAA.Hast:BAABLgAECn8XAAIfAAYJFBBoQgADAQAfAAYJFBBoQgADAQAAAA==.',
He='Hearthzilla:BAAALgAECgEJAQABLgAECgkJIQAPANgfAA==.Heidie:BAAALgAECgUJCgAAAA==.Hellsbow:BAAALgAECgYJDgAAAA==.Hermin:BAAALgADCgQJCAAAAA==.',
Ho='Holyhellz:BAAALgADCgEJAQAAAA==.Honeyboo:BAAALgAECgUJBQABLgAFFAQJCQALADMNAA==.Hots:BAAALgADCgcJBwAAAA==.Hotzz:BAAALgAECgEJAQAAAA==.',
Hr='Hraesvelgr:BAAALgADCggJBwAAAA==.',
Hu='Huntavious:BAACLgAFFH8IAAIXAAQJGxRNEgA2AQAXAAQJGxRNEgA2AQAuAAQKfzQABBcACQk8H2gFANECABcACQk8H2gFANECAAgABgnjGsZeAEsBACAAAQnIE9uKADAAAAAA.',
['Hë']='Hëllen:BAABLgAECn8aAAIKAAYJMiBoBQDGAAAKAAYJMiBoBQDGAAAAAA==.',
['Hú']='Húñtrèss:BAAALgAECgUJBwAAAA==.',
Ia='Iamshinigamy:BAAALgAECgIJAgABLgAECgcJFwAFAPMaAA==.',
Ii='Iichimaru:BAAALgAECgUJBQAAAA==.',
Il='Illidupe:BAAALgADCgMJAwAAAA==.',
Im='Imakittycat:BAAALgAECggJCAAAAA==.',
In='Inaoh:BAAALgAECgQJBwAAAA==.Insaniac:BAAALgAECgQJBAAAAA==.',
Ir='Ironboss:BAAALgAECgYJEAAAAA==.',
Iv='Ivey:BAABLgAECn8qAAILAAgJRh7fFACjAgALAAgJRh7fFACjAgAAAA==.',
Iz='Izes:BAAALgAECgEJAwAAAA==.',
Ja='Jaagganug:BAAALgAECgcJBwAAAA==.Jacenne:BAABLgAECn8bAAIfAAcJlAOLYACXAAAfAAcJlAOLYACXAAAAAA==.Jairus:BAAALgAECgcJBwAAAA==.',
Jd='Jdirty:BAABLgAECn8YAAIhAAYJhAnjEgDcAAAhAAYJhAnjEgDcAAAAAA==.',
Je='Jellytime:BAAALgAECgMJBQAAAA==.',
Jo='Josephyn:BAAALgAECgcJCgABLgAFFAcJLgAOAO4eAA==.',
Ju='Jugernaut:BAAALgAECgEJAQAAAA==.Jumpmann:BAAALgAECgMJAwAAAA==.Justdesserts:BAAALgAECgEJAQAAAA==.Justix:BAAALgADCggJEwAAAA==.',
Ka='Kadaffy:BAAALgAECgQJBQAAAA==.Kakota:BAAALgADCgQJBAABLgAECgkJGgAPAA4dAA==.Kakusu:BAAALgAECgYJEQAAAA==.Kakuta:BAAALgAECgUJDwABLgAECgkJGgAPAA4dAA==.Kakutá:BAABLgAECn8aAAIPAAkJDh2MDACcAgAPAAkJDh2MDACcAgAAAA==.Kalru:BAAALgAECgIJAgAAAA==.Kargar:BAAALgAECgEJAgAAAA==.Karliah:BAAALgAECgIJAgAAAA==.Katharsis:BAACLgAFFH8VAAIKAAQJ9xECBQD6AAAKAAQJ9xECBQD6AAAuAAQKfyEAAgoACQnPFohGAPMBAAoACQnPFohGAPMBAAAA.',
Ke='Keba:BAAALgAECgEJAQABLgAFFAYJHQAVAKMdAA==.Keit:BAAALgADCgYJBgABLgAFFAQJCgAQAPkeAA==.',
Kh='Khalidisi:BAACLgAFFH8FAAQDAAMJyxzMBwD9AAADAAMJyxzMBwD9AAAKAAEJEAsTxAA7AAAVAAEJoxWzSAA5AAAuAAQKfzAABAMACQnsH8gGAHYCAAMACAmxH8gGAHYCABUACQktGTYvAJ4BAAoACQnIDRRpAJ0BAAAA.Khaliesi:BAAALgADCgIJAgAAAA==.Khalizar:BAABLgAFFH8NAAIbAAQJLAnuKwAEAQAbAAQJLAnuKwAEAQAAAA==.Kharazim:BAAALgADCgEJAQABLgAECgkJNwAYANwcAA==.Khenja:BAAALgAECgEJAQAAAA==.Khál:BAAALgADCgYJBgAAAA==.',
Ki='Killerelf:BAABLgAECn8YAAIKAAgJiwecrwAgAQAKAAgJiwecrwAgAQAAAA==.Kittie:BAAALgADCggJCAAAAA==.',
Kk='Kkiilleerr:BAAALgAECgYJDwAAAA==.',
Ko='Kobbaltcilar:BAAALgAECgUJBgAAAA==.Koraleena:BAAALgAECgQJBAAAAA==.Korbo:BAABLgAECn8sAAMOAAkJMBtQNgDXAQAOAAcJKBhQNgDXAQAPAAUJeR4rKwCaAQAAAA==.Korbulo:BAABLgAECn8UAAIFAAkJmwmedwCKAQAFAAkJmwmedwCKAQAAAA==.Korlothel:BAABLgAECn8kAAIDAAkJvAcDIQAMAQADAAkJvAcDIQAMAQABLgAFFAMJAwAJAAAAAA==.Korrith:BAAALgADCgIJAgAAAA==.',
Kr='Krumpus:BAABLgAECn8iAAIYAAkJRRT1LwAHAgAYAAkJRRT1LwAHAgAAAA==.Kryma:BAAALgAECgcJBwAAAA==.',
Ku='Kungfuuy:BAABLgAECn8lAAIHAAkJPCGzBAD5AgAHAAkJPCGzBAD5AgAAAA==.Kurtevade:BAAALgAECgQJDAAAAA==.',
Kw='Kwetnepthl:BAAALgAECgEJAgAAAA==.',
Ky='Kynsong:BAABLgAECn8nAAISAAkJJhWeFgAbAgASAAkJJhWeFgAbAgAAAA==.',
['Kà']='Kàlbrews:BAABLgAECn9AAAIHAAkJvyZOAACHAwAHAAkJvyZOAACHAwAAAA==.Kàrmâ:BAAALgAECgUJBQAAAA==.',
['Kî']='Kîrah:BAAALgAFFAIJAgAAAA==.',
La='Lagk:BAAALgAECgQJBQAAAA==.Lainiee:BAAALgADCgEJAQAAAA==.Lavismad:BAECLgAFFH8JAAIbAAQJuiDZDwCHAQAbAAQJuiDZDwCHAQAuAAQKfzQABBsACQkMJZcEABsDABsACQnYJJcEABsDABYABwmhIJYPAO8BABwAAQlGJXcyAGkAAAAA.Lavoc:BAEALgADCgcJBwABLgAFFAQJCQAbALogAA==.Lavv:BAEALgAECgYJCAABLgAFFAQJCQAbALogAA==.Lavz:BAEALgAECgYJBgABLgAFFAQJCQAbALogAA==.',
Le='Legendary:BAAALgAECgYJDQAAAA==.Leshah:BAAALgAECgYJCwAAAA==.',
Li='Lichkingdied:BAAALgADCgUJBQAAAA==.Lightndpain:BAAALgAECgQJBgABLgAECgQJCwAJAAAAAA==.Lildh:BAAALgAECgUJCQAAAA==.Lilypetal:BAAALgAECgQJBwAAAA==.Lionaest:BAAALgAECgYJBwAAAA==.Littlebucket:BAAALgADCgEJAQAAAA==.',
Lo='Lockdpain:BAAALgAECgYJGAABLgAECgQJCwAJAAAAAQ==.Logov:BAAALgAECgYJDwAAAA==.Loraine:BAAALgAECgEJAQAAAA==.Loìsbethe:BAAALgAECgYJCgAAAA==.',
Lu='Luciferra:BAABLgAFFH8IAAISAAUJ9A6kEgA1AQASAAUJ9A6kEgA1AQABLgAFFAcJLgAOAO4eAA==.Lukey:BAAALgAECgMJAwAAAA==.Lunartemis:BAAALgAECgUJCAABLgAFFAUJEAAiACchAA==.Luu:BAAALgAECgQJCAAAAA==.',
Ly='Lyza:BAAALgADCgYJCQAAAA==.',
['Lö']='Lörax:BAAALgADCgQJBQAAAA==.',
['Lû']='Lûnafreya:BAAALgAECggJEgAAAA==.',
Ma='Maelera:BAAALgADCgkJDAAAAA==.Maetromundo:BAAALgAECgEJAQAAAA==.Maevan:BAAALgADCgEJAQAAAA==.Magentas:BAAALgADCgIJAgAAAA==.Magickul:BAAALgADCggJCAAAAA==.Mahlah:BAAALgAECgQJBAAAAA==.Malaboo:BAAALgAECgEJAQABLgAFFAQJCQALADMNAA==.Malabooty:BAAALgAECgYJBwABLgAFFAQJCQALADMNAA==.Maletsy:BAAALgAECgEJAQABLgAFFAIJBQAIAP4WAA==.Maliboo:BAACLgAFFH8JAAILAAQJMw09NwDQAAALAAQJMw09NwDQAAAuAAQKfzkAAwsACQlEIsAEAG8DAAsACQlEIsAEAG8DAB8AAgmfCQuOADIAAAAA.Maxamus:BAABLgAECn8aAAQcAAYJwiH2EgDLAQAcAAYJwiH2EgDLAQAWAAUJzBgNKQDsAAAbAAEJgxeSlQBHAAAAAA==.Maxigooner:BAABLgAFFH8FAAIYAAMJKRYmXwDSAAAYAAMJKRYmXwDSAAABLgAFFAUJIgAKAFwmAA==.Maxpower:BAAALgAECgEJAQAAAA==.',
Mc='Mcflurry:BAAALgAECgUJCwAAAA==.',
Me='Medarisa:BAAALgAECgcJDQAAAA==.Medavia:BAAALgADCgUJBQAAAA==.Mederia:BAAALgAECgUJBQAAAA==.Medívh:BAAALgADCgEJAQAAAA==.Melisandr:BAAALgAECgMJBQAAAA==.Merkenier:BAABLgAECn84AAIfAAgJPBQNIQDAAQAfAAgJPBQNIQDAAQAAAA==.Merkshamalot:BAAALgAECgEJAQABLgAECggJOAAfADwUAA==.Merkur:BAABLgAECn8aAAMKAAYJwAnx2wDjAAAKAAYJwAnx2wDjAAAVAAEJigHeoQAbAAABLgAECggJOAAfADwUAA==.Merkurry:BAAALgAECgEJAQABLgAECggJOAAfADwUAA==.',
Mi='Midnitehunt:BAAALgAECgQJBAAAAA==.Miragia:BAAALgAECgYJEgAAAA==.Missmayhem:BAAALgAECgUJCAAAAA==.Missmayhemm:BAAALgADCgQJBgAAAA==.',
Mo='Modifiedmix:BAABLgAECn8sAAIIAAgJfxnxKwAtAgAIAAgJfxnxKwAtAgAAAA==.Modsabadtank:BAAALgAECgYJCwABLgAECggJLAAIAH8ZAA==.Mokomohama:BAAALgAECgcJBwAAAA==.Monatazumaa:BAAALgAECgEJAgAAAA==.Moonbloom:BAAALgAFFAEJAQABLgAFFAcJLgAOAO4eAA==.Mopeezie:BAAALgAECgEJAQAAAA==.Mordicant:BAAALgADCgEJAQABLgAECgYJDQAJAAAAAA==.Morella:BAABLgAECn81AAIRAAcJmQ4HGQCDAQARAAcJmQ4HGQCDAQAAAA==.',
Mu='Mucduck:BAAALgADCgEJAQAAAA==.Mustakrakish:BAAALgAECgEJAQAAAA==.Mustaz:BAAALgAECgkJBQAAAA==.',
My='Mym:BAAALgADCgcJBAAAAA==.Mystics:BAAALgAECgUJBgAAAA==.Mythrunduil:BAAALgADCgEJAQAAAA==.',
['Må']='Mågi:BAAALgAECgcJBwAAAA==.',
['Mé']='Médb:BAABLgAECn8wAAMFAAkJdx7fGADEAgAFAAkJDB7fGADEAgAjAAMJFR2hCQDmAAAAAA==.',
Na='Naste:BAAALgAECgUJBQAAAA==.Nathrold:BAAALgAECgIJBAABLgAECgYJEQAJAAAAAA==.',
Ne='Necrobon:BAAALgAECgYJCAAAAA==.Necrognome:BAAALgAECgIJAgAAAA==.Neptune:BAACLgAFFH8uAAIOAAcJ7h7vDwDsAQAOAAcJ7h7vDwDsAQAuAAQKfyEAAw4ACQlRIhgHAAIDAA4ACQlRIhgHAAIDAA8ABwkkDtE0AIQBAAAA.Nerfdks:BAABLgAECn8UAAIkAAkJJhQyFADRAQAkAAkJJhQyFADRAQAAAA==.Nerfpaladins:BAABLgAECn8lAAQKAAcJpRKRnAA9AQAKAAcJTBGRnAA9AQADAAcJJBHIJADvAAAVAAMJzAQ+dwBgAAAAAA==.Nerfpriests:BAAALgAFFAIJAgAAAA==.Neruess:BAAALgADCgUJBQAAAA==.Nezzuko:BAAALgAECgcJBwAAAA==.',
Ni='Nightbird:BAABLgAECn8dAAMiAAcJvBeoKwA8AQAiAAcJTheoKwA8AQAlAAYJ8BWfDgAsAQABLgAECggJCQAJAAAAAA==.Ninediewatt:BAAALgAECgQJCAAAAA==.Nivella:BAAALgAECgYJCgAAAA==.Nixaana:BAAALgAECgUJBgAAAA==.Niçki:BAAALgADCgMJAwAAAA==.',
No='Notlockz:BAAALgADCgIJAgAAAA==.Novah:BAAALgADCgQJBQAAAA==.Noydb:BAAALgAECgEJAQABLgAECgkJPwAWAKMcAA==.',
Nu='Nuah:BAAALgADCgYJDQAAAA==.',
Ny='Nyxsia:BAEALgAFFAEJAQABLgAFFAcJIgAbAJAdAA==.',
['Nå']='Nåmi:BAAALgAECgYJBgAAAA==.',
['Nè']='Nèo:BAAALgADCgcJBwAAAA==.',
Ob='Obayi:BAABLgAECn9EAAIIAAcJ/hAdAwA2AQAIAAcJ/hAdAwA2AQAAAA==.Obsaedia:BAAALgAECgcJBwABLgAECggJHAAJAAAAAQ==.',
Oc='Oculo:BAAALgADCgMJAwAAAA==.',
Od='Odinsgrace:BAAALgAECgEJAQAAAA==.',
Og='Ogmadmonk:BAACLgAFFH8MAAIQAAMJnRLLGgDLAAAQAAMJnRLLGgDLAAAuAAQKfzEAAhAACQmUIQsJAJoCABAACQmUIQsJAJoCAAAA.',
Ok='Oktobra:BAABLgAECn8bAAIKAAYJIwNcHgGVAAAKAAYJIwNcHgGVAAAAAA==.',
On='Onetrickpony:BAAALgAECgIJAgAAAA==.Onos:BAAALgAECgIJAgAAAA==.Onosm:BAAALgAECgQJBAAAAA==.',
Or='Orangevoker:BAAALgAECgcJCwABLgAECgkJIQAPANgfAA==.Ordin:BAAALgAECgEJAQAAAA==.Orioan:BAAALgAECgUJCQAAAA==.Orux:BAAALgAECgYJBgAAAA==.',
Os='Osenya:BAAALgAECgYJBgABLgAFFAQJCQAMAGMfAA==.Osun:BAAALgAECgQJBAAAAA==.',
Ou='Ouroboro:BAAALgADCgUJBQAAAA==.',
Ow='Owlbat:BAAALgAECgEJAQAAAA==.',
Pa='Padremort:BAAALgADCgYJBgAAAA==.Palantyr:BAABLgAECn9fAAIPAAgJvRqZGgA+AgAPAAgJvRqZGgA+AgAAAA==.Paly:BAAALgAECgEJAQAAAA==.Para:BAAALgAECgUJBwAAAA==.Patrician:BAABLgAECn8sAAIhAAkJdhdpBAA9AgAhAAkJdhdpBAA9AgAAAA==.',
Pe='Penutbutter:BAAALgAECgQJBwAAAA==.Pepegasus:BAAALgADCgcJBwAAAA==.',
Ph='Phobos:BAAALgADCgQJCAAAAA==.Phyloren:BAAALgADCgUJBgAAAA==.',
Pi='Picklemorty:BAAALgAECgYJCwABLgAFFAEJAQAJAAAAAA==.Pigsticker:BAAALgAECgQJBQAAAA==.Pixyfire:BAAALgAECgYJCgABLgAFFAQJCQAVAOIQAA==.',
Po='Poisonleaf:BAAALgAECgUJBgABLgAECgYJGgAKADIgAA==.Pokingharder:BAABLgAECn8iAAIlAAkJHBbUBAA9AgAlAAkJHBbUBAA9AgABLgAFFAMJDQABAKAYAA==.',
Pu='Pulcherrimus:BAAALgAECgEJAwAAAA==.Purgeem:BAAALgADCgUJBQAAAA==.Pushpop:BAAALgAECgYJDwABLgAECggJXwAPAL0aAA==.',
Pw='Pwiest:BAAALgADCgcJEAAAAA==.',
Qu='Quetzalcoatl:BAABLgAECn8eAAImAAkJ9hq0BwB6AgAmAAkJ9hq0BwB6AgAAAA==.',
Ra='Raambox:BAAALgAECgQJBAAAAA==.Radak:BAAALgAECgEJAQAAAA==.Raddish:BAABLgAECn8bAAISAAYJ+RBnPwDxAAASAAYJ+RBnPwDxAAAAAA==.Raedl:BAAALgADCgQJBAAAAA==.Rahjlynn:BAAALgAECgEJAQAAAA==.Rahken:BAAALgAECgcJBwAAAA==.Raiinn:BAAALgADCgUJBQAAAA==.Raylee:BAACLgAFFH8JAAMBAAQJBRwTBABNAQABAAQJQhUTBABNAQARAAIJ4xt3EgCkAAAuAAQKfz4ABAIACQmeIcAUAKkCAAIACAmxH8AUAKkCABEABwl8IQ8IAEQCAAEAAwk2GvUZAPAAAAAA.Razuki:BAACLgAFFH8JAAIVAAQJ4hChJwDmAAAVAAQJ4hChJwDmAAAuAAQKfzQAAxUACQmLIoUFADoDABUACQmLIoUFADoDAAoABwn2F1xzAIcBAAAA.',
Re='Remyl:BAAALgADCggJCAAAAA==.Reynia:BAAALgAECgEJAQAAAA==.',
Rf='Rfd:BAAALgADCgcJBwABLgAECggJGQAPAMUSAA==.',
Rh='Rhaenies:BAAALgAECgYJEAAAAA==.Rharr:BAAALgADCgkJDAAAAA==.Rhovanion:BAAALgAECggJCQAAAA==.Rhuac:BAABLgAECn8qAAILAAkJlhPMKQAGAgALAAkJlhPMKQAGAgAAAA==.',
Ri='Rigymorty:BAAALgAECgMJAwAAAA==.Risakah:BAAALgAECggJCQAAAA==.',
Ro='Rorschach:BAAALgAECgcJCgAAAA==.Rosefist:BAEALgADCgcJCAABLgAFFAcJEQAUAAMRAA==.Rosemourne:BAEALgAECgIJAgABLgAFFAcJEQAUAAMRAA==.Roseykat:BAABLgAECn8oAAIIAAkJkAoEXQCPAQAIAAkJkAoEXQCPAQAAAA==.Roshwyn:BAABLgAECn8VAAIIAAkJlwrmcABfAQAIAAkJlwrmcABfAQAAAA==.Rottedmeat:BAAALgAECgcJCgAAAA==.',
Ru='Rubmytotems:BAAALgAECgYJBgAAAA==.Ruckus:BAABLgAECn8nAAIKAAgJuRYPPwApAgAKAAgJuRYPPwApAgAAAA==.',
Sa='Saberwar:BAAALgAECgEJAQABLgAECgMJAwAJAAAAAA==.Saintfury:BAAALgAECgQJBQAAAA==.Saintsfear:BAABLgAECn8qAAIbAAkJWQ+MJgDEAQAbAAkJWQ+MJgDEAQAAAA==.Samest:BAAALgAECgEJAQAAAA==.Sanchito:BAAALgADCgMJAwAAAA==.Saphalia:BAAALgADCgMJAwAAAA==.Saradomin:BAAALgADCgUJBAAAAA==.Sareenastar:BAACLgAFFH8JAAISAAQJoyC+DQBwAQASAAQJoyC+DQBwAQAuAAQKfy4AAxIACQmUJngAAN8DABIACQmUJngAAN8DABMAAQnfCWOKAC8AAAAA.Sasae:BAABLgAECn8hAAIHAAgJmhNIIAClAQAHAAgJmhNIIAClAQAAAA==.',
Sc='Scorias:BAAALgADCgQJAwAAAA==.',
Se='Selisztraza:BAAALgADCgEJAQAAAA==.Sephiróth:BAAALgADCgUJCAAAAA==.Sereni:BAAALgADCgQJBAAAAA==.Serenity:BAAALgAECgcJEwAAAA==.Serenitynow:BAAALgAECgEJAwAAAA==.Sewald:BAAALgAECgcJDwAAAA==.',
Sh='Shadowzbane:BAAALgAECgIJAgAAAA==.Shahasha:BAAALgADCgEJAQAAAA==.Shaidarharan:BAAALgADCgIJAgAAAA==.Shakeybop:BAAALgAECgQJBAAAAA==.Shalen:BAABLgAECn8vAAQdAAkJRBV7HwDcAQAdAAkJOBV7HwDcAQAeAAYJoQ2ZHQBCAQAmAAYJ7g2uGwAjAQAAAA==.Sharker:BAAALgADCgYJBgAAAA==.Sharkyb:BAAALgAECgEJAgABLgAECgkJNwAMAKsiAA==.Sharpie:BAAALgADCgcJCgAAAA==.Sheer:BAABLgAECn8aAAMHAAgJYB8EDwBKAgAHAAgJYB8EDwBKAgAEAAYJkyErGwA/AgAAAA==.Sheraa:BAABLgAECn8lAAIDAAkJeBJ9EAC9AQADAAkJeBJ9EAC9AQAAAA==.Shiftystrike:BAABLgAECn8WAAInAAcJPx/wCgAVAgAnAAcJPx/wCgAVAgAAAA==.Shifushield:BAAALgAECgcJCAAAAA==.Shireshannon:BAABLgAECn8VAAIIAAYJegmrogD8AAAIAAYJegmrogD8AAAAAA==.Shrike:BAAALgAECgIJBQABLgAFFAcJGgATALAaAA==.Shrunkador:BAACLgAFFH8RAAIPAAQJMg1oKwDoAAAPAAQJMg1oKwDoAAAuAAQKfzMAAg8ACQm6HZAQAG4CAA8ACQm6HZAQAG4CAAAA.',
Si='Silicå:BAAALgAECgMJAwAAAA==.Silk:BAAALgAECgYJDgAAAA==.Silmarkthree:BAACLgAFFH8JAAIFAAQJnBPfWwAnAQAFAAQJnBPfWwAnAQAuAAQKfzQAAgUACQmkGCk6ADACAAUACQmkGCk6ADACAAAA.Sinbåd:BAAALgAECgcJCAAAAA==.Siodar:BAAALgADCgEJAQABLgAECgUJBwAJAAAAAA==.Sisterstar:BAAALgADCgMJAwAAAA==.',
Sl='Sleety:BAAALgAECgIJBQAAAA==.Slipknoth:BAACLgAFFH8iAAMTAAgJzxoNBgAbAgATAAcJeh0NBgAbAgAUAAYJ3g16GACqAQAuAAQKfywABBMACQnlInoRAEsCABMACAkHJXoRAEsCABIABwntF/kgANsBABQABAnOGQtGAO8AAAAA.',
Sn='Snekhain:BAAALgADCgMJAwAAAA==.Snuffaluffa:BAAALgAECgMJAwAAAA==.',
So='Somatra:BAAALgADCgkJCQAAAA==.Sorean:BAACLgAFFH8WAAIXAAUJNx7YCgBwAQAXAAUJNx7YCgBwAQAuAAQKfy8ABAgACQm+IFYhAD0CAAgABwlUG1YhAD0CABcABwlnHfsZAM8BACAABwlQGv0vALUBAAAA.',
Sp='Specialmove:BAAALgAFFAEJAgAAAA==.Spookydookie:BAAALgADCgkJCgAAAA==.',
St='Staghealz:BAAALgAECgIJAwAAAA==.Stifs:BAABLgAECn8oAAIDAAgJGxYZFgB0AQADAAgJGxYZFgB0AQAAAA==.Stilleena:BAAALgAECgYJBgAAAA==.Stinkinglily:BAAALgAECgEJAgAAAA==.Strunrage:BAEALgAECgcJDAABLgAECgkJQgAKAI4kAA==.Stÿx:BAABLgAECn8ZAAIkAAYJ6gXLQACMAAAkAAYJ6gXLQACMAAABLgAECgkJEwAJAAAAAA==.',
Su='Sugarbomb:BAAALgADCgYJCgAAAA==.',
Sy='Sykotyk:BAAALgAECgkJDwAAAA==.Sylverfox:BAAALgAECgMJAwABLgAECgkJHwAVAJUfAA==.Synchestra:BAAALgADCgcJCgAAAA==.',
Ta='Tadagain:BAABLgAECn8gAAMKAAYJlhLwrAAjAQAKAAYJlhLwrAAjAQAVAAQJ2gV2dgChAAAAAA==.Tagrith:BAAALgADCgMJAwAAAA==.Tankybears:BAACLgAFFH8GAAILAAIJOhvIRAChAAALAAIJOhvIRAChAAAuAAQKfywAAx8ACQnOGmcRAE8CAB8ACQnOGmcRAE8CAAsACAnqGwpUAEABAAAA.Tarmalok:BAAALgAECgEJAQAAAA==.Tazera:BAAALgAECgUJCwAAAA==.',
Te='Telekinesis:BAABLgAECn8iAAIXAAgJvhCnIACXAQAXAAgJvhCnIACXAQAAAA==.Tenara:BAABLgAFFH8GAAIOAAQJORQwPADyAAAOAAQJORQwPADyAAABLgAFFAIJBgALADobAA==.Tenbinza:BAAALgAECgUJBwAAAA==.Teos:BAACLgAFFH8FAAIZAAMJSQleEQCyAAAZAAMJSQleEQCyAAAuAAQKfzgAAhkACQmwGQMIAEcCABkACQmwGQMIAEcCAAAA.',
Th='Thadude:BAAALgAECgcJBwABLgAFFAQJDQAkAMoUAA==.Thainé:BAAALgAECgMJBgAAAA==.Thaldrassian:BAAALgADCgQJBAAAAA==.Tharris:BAAALgAECgYJCwAAAA==.Thehatred:BAAALgADCgYJBgAAAA==.Therondar:BAAALgADCgEJAQAAAA==.Thirdleggedg:BAAALgAECgEJAQAAAA==.Thiyan:BAAALgADCgMJAwAAAA==.Tholin:BAAALgAECggJDwAAAA==.Thromar:BAABLgAECn8VAAIFAAcJiBWvgADPAQAFAAcJiBWvgADPAQAAAA==.Thunderlily:BAABLgAECn8qAAMFAAkJWBs/NwA8AgAFAAkJCxs/NwA8AgAoAAcJchfpBgCgAQAAAA==.Thünder:BAAALgADCgcJBwABLgAECgcJFgAMAKQeAA==.',
Ti='Tinderbeef:BAAALgADCgcJCAAAAA==.Tinychaos:BAAALgAECgkJCQAAAA==.Tinyround:BAAALgAECgEJAQAAAA==.Tinytotem:BAAALgADCgQJBAAAAA==.Tirra:BAABLgAECn8fAAMVAAkJlR9ODwCiAgAVAAkJlR9ODwCiAgAKAAIJJgbTaAFNAAAAAA==.',
To='Topeka:BAAALgAECgQJBAABLgAECgkJJAAIAKgNAA==.Torama:BAAALgADCgIJAgAAAA==.Toranth:BAABLgAECn81AAIVAAkJiRXmGQA3AgAVAAkJiRXmGQA3AgAAAA==.Torq:BAABLgAECn8XAAIFAAYJ/BmShwDCAQAFAAYJ/BmShwDCAQABLgAECgcJFwAVAIghAA==.Torqumada:BAAALgAECgkJBgAAAA==.Toxian:BAABLgAECn8tAAIYAAgJzxXnQgC/AQAYAAgJzxXnQgC/AQAAAA==.Toxicelitist:BAABLgAECn8rAAMRAAkJ4w4KDAB+AQARAAkJ4w4KDAB+AQACAAEJmgF2ZQEaAAAAAA==.',
Tr='Treedemon:BAACLgAFFH8JAAIYAAQJExnFOABCAQAYAAQJExnFOABCAQAuAAQKfyoAAhgACQksJIIKAPYCABgACQksJIIKAPYCAAAA.Treedin:BAAALgAECgMJAwAAAA==.Trollboi:BAAALgADCggJCAAAAA==.Trymw:BAAALgADCgIJAgAAAA==.Tryst:BAAALgADCgcJBwAAAA==.',
Ty='Tybearon:BAAALgAECgMJAwAAAA==.Tyinthus:BAAALgAECgcJBwABLgAECgcJBwAJAAAAAA==.Tyreid:BAAALgAECgcJBwAAAA==.Tyrelitha:BAAALgAECgQJDQAAAA==.',
Ud='Udderchoad:BAAALgADCgEJAQAAAA==.',
Uh='Uhura:BAAALgAECgEJAQAAAA==.',
Ul='Ulfrir:BAACLgAFFH8SAAIIAAQJ2RtILwBRAQAIAAQJ2RtILwBRAQAuAAQKfyYAAwgACQk3INURAMMCAAgACQk3INURAMMCACAAAwkxCipvAIIAAAAA.Ultradukes:BAAALgAECgMJBAAAAA==.',
Un='Unatural:BAAALgAECgUJBQAAAA==.Unleashed:BAAALgAECgUJCgAAAA==.',
Va='Valarea:BAAALgADCgEJAQAAAA==.Valock:BAAALgAECgkJEwAAAA==.Vandham:BAAALgADCgEJAQAAAA==.Vannis:BAAALgAECgcJBwAAAA==.Vanshifty:BAACLgAFFH8RAAILAAMJWBmMAwDCAAALAAMJWBmMAwDCAAAuAAQKf0QAAgsACQk0I0sFAGQDAAsACQk0I0sFAGQDAAAA.',
Ve='Veilf:BAAALgADCgYJDAAAAA==.Velf:BAAALgAECgIJAgAAAA==.Velrus:BAAALgAECgYJDAAAAA==.Venli:BAAALgAECgMJAwAAAA==.Venombite:BAAALgADCgMJAwAAAA==.Venomlord:BAAALgADCgQJBAAAAA==.Verez:BAAALgAECgEJAgAAAA==.',
Vi='Victorion:BAAALgAECggJCQAAAA==.Viktorax:BAAALgAECgYJDgAAAA==.Vincevega:BAAALgAECgkJDgAAAA==.Virtueozo:BAABLgAECn8aAAImAAgJEBfODwA+AgAmAAgJEBfODwA+AgAAAA==.',
Vo='Volam:BAAALgAECgQJBAAAAA==.',
Vy='Vyx:BAAALgAECgkJEwAAAA==.',
Wa='Waffle:BAABLgAECn8YAAIIAAYJihUrggA6AQAIAAYJihUrggA6AQABLgAECggJGgAIAFEOAA==.Waldhorn:BAAALgAECgcJCwAAAA==.Wangji:BAAALgAECgQJBAAAAA==.Wangwen:BAAALgADCgIJAgAAAA==.Wargue:BAABLgAECn8VAAIbAAYJjRugOADEAQAbAAYJjRugOADEAQAAAA==.',
We='Weeaboos:BAAALgADCgIJAgABLgADCgQJBAAJAAAAAA==.Weebsz:BAAALgADCgQJBAAAAA==.Welindis:BAABLgAECn8ZAAIKAAcJ5wr0xAABAQAKAAcJ5wr0xAABAQABLgAECgkJMAAYAPgQAA==.Wetkith:BAAALgADCgUJBQAAAA==.',
Wi='Windrider:BAAALgADCgIJAgAAAA==.Windwraith:BAAALgAECgIJAgAAAA==.Wizzard:BAAALgAECggJHAAAAQ==.',
Xa='Xaiyara:BAAALgADCgUJBQAAAA==.Xalina:BAAALgAECgEJAQAAAA==.Xandaka:BAAALgADCgQJBAAAAA==.',
Xe='Xephir:BAAALgAECggJCwAAAA==.',
Xi='Xidied:BAACLgAFFH8HAAIHAAQJ3CBbFQB3AQAHAAQJ3CBbFQB3AQAuAAQKfzAAAgcACQkmIfYFAN4CAAcACQkmIfYFAN4CAAAA.Xilon:BAAALgAECgcJDwABLgAFFAQJCQAMAGMfAA==.Xilra:BAABLgAECn8vAAMfAAkJmiJ6CwCcAgAfAAkJmiJ6CwCcAgAnAAEJmhHoUgAzAAABLgAFFAQJCQAMAGMfAA==.Xilrot:BAABLgAFFH8JAAIMAAQJYx8QSgBeAQAMAAQJYx8QSgBeAQAAAA==.Xilzen:BAAALgAECgUJEQABLgAFFAQJCQAMAGMfAA==.Xinia:BAAALgAECgMJAwAAAA==.',
Xz='Xzed:BAAALgADCgEJAQAAAA==.',
Ye='Yew:BAAALgADCgMJAwAAAA==.',
Yi='Yikers:BAACLgAFFH8RAAIVAAQJZiA2GgBPAQAVAAQJZiA2GgBPAQAuAAQKfyUAAhUACQm6IXMJAPQCABUACQm6IXMJAPQCAAAA.',
Yr='Yridai:BAAALgAECgYJCAAAAA==.',
Za='Zani:BAAALgADCgYJBwAAAA==.Zarsher:BAAALgADCgIJAgAAAA==.',
Zd='Zdk:BAAALgAECgEJAQABLgAECgkJLQAIAA0fAA==.',
Ze='Zeldy:BAABLgAECn8vAAIIAAkJJxfVMgARAgAIAAkJJxfVMgARAgAAAA==.Zenestraza:BAAALgADCgcJCwABLgAECgkJNwAYANwcAA==.Zennitsu:BAAALgAECgkJCAAAAA==.Zenthareal:BAABLgAECn83AAMYAAkJ3BwaFQCaAgAYAAkJchwaFQCaAgAaAAQJQxeGAAAjAQAAAA==.Zenzi:BAAALgADCgUJCAAAAA==.Zenzz:BAAALgADCgQJBAAAAA==.Zeuc:BAAALgADCgMJAwAAAA==.Zeuus:BAAALgADCgMJBAAAAA==.',
Zh='Zhirldk:BAAALgAECgcJEQAAAA==.Zhulgarosh:BAAALgADCgUJBQAAAA==.',
Zi='Zillidan:BAAALgAECgEJAwABLgAECgkJLQAIAA0fAA==.',
Zm='Zmaster:BAABLgAECn8tAAIIAAkJDR9JFQCpAgAIAAkJDR9JFQCpAgAAAA==.',
Zo='Zobeast:BAAALgADCgQJBAAAAA==.',
Zr='Zret:BAAALgAECgcJDQABLgAECgkJLQAIAA0fAA==.',
Zw='Zwar:BAAALgAECgEJAQABLgAECgkJLQAIAA0fAA==.',
Zy='Zynith:BAAALgAECgYJBgAAAA==.',
['Zö']='Zöey:BAAALgADCgQJBQAAAA==.',
['Åp']='Åpex:BAAALgAECggJBgAAAA==.',
['Çl']='Çloudz:BAAALgADCgMJAwAAAA==.',
['Ða']='Ðark:BAACLgAFFH8WAAIIAAMJFB94CgCgAAAIAAMJFB94CgCgAAAuAAQKfycAAggACQm5HAQVAI8CAAgACQm5HAQVAI8CAAAA.',
['Ðr']='Ðr:BAABLgAECn8eAAMOAAkJ/Br1IgANAgAOAAcJThr1IgANAgAPAAYJ7xfNNQBjAQAAAA==.',
['ßl']='ßlack:BAAALgADCgEJAQAAAA==.ßlood:BAAALgADCgUJBQAAAA==.',
['ßu']='ßudah:BAAALgAECgMJBgAAAA==.',
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
