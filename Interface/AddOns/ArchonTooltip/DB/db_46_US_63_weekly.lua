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

local lookup = {'Warlock-Affliction','Warlock-Demonology','Paladin-Protection','Monk-Mistweaver','Mage-Frost','Monk-Windwalker','Monk-Brewmaster','Hunter-BeastMastery','Paladin-Retribution','Druid-Restoration','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Restoration','Shaman-Elemental','DemonHunter-Havoc','Warlock-Destruction','Unknown-Unknown','Priest-Holy','Priest-Shadow','Priest-Discipline','Paladin-Holy','Warrior-Protection','Hunter-Survival','DemonHunter-Devourer','Shaman-Enhancement','DemonHunter-Vengeance','Warrior-Fury','Warrior-Arms','Evoker-Augmentation','Evoker-Devastation','Druid-Balance','Hunter-Marksmanship','Rogue-Outlaw','Rogue-Subtlety','Mage-Fire','DeathKnight-Blood','Rogue-Assassination','Evoker-Preservation','Druid-Feral','Mage-Arcane',}
local provider = {region='US',realm='Dawnbringer',name='US',type='weekly',zone=46,date='2026-06-27',data={Ab='Abdalhazred:BAACLgAFFH8cAAMBAAYJvSG/AgB3AQABAAYJvSG/AgB3AQACAAEJiR/pvQBMAAAuAAQKfzgAAwEACQmYJFIAAGYDAAEACAm3JVIAAGYDAAIAAwnQHSWsAOsAAAAA.Abillus:BAAALgAECgEJAwAAAA==.Abilus:BAABLgAECn8VAAIDAAQJsRdfIwD6AAADAAQJsRdfIwD6AAAAAA==.Abolis:BAAALgAECgMJBwAAAA==.',
Ae='Aeldriel:BAAALgAECgMJAwAAAA==.Aeoyn:BAAALgAECgEJAQAAAA==.',
Ag='Aggar:BAAALgADCgkJGwABLgAECgkJUgAEAL4aAA==.',
Ak='Akoa:BAAALgAECgEJAQAAAA==.',
Al='Alarak:BAABLgAECn8bAAIBAAgJcRVsCQCtAQABAAgJcRVsCQCtAQAAAA==.Alerion:BAAALgAECgEJAQAAAA==.Alnara:BAAALgAECgEJAgAAAA==.Aloxys:BAAALgADCgcJCQAAAA==.Alvierearn:BAABLgAECn8WAAIFAAgJuxE8kgBTAQAFAAgJuxE8kgBTAQAAAA==.',
Am='Amoradis:BAAALgADCgUJFAAAAA==.',
An='Anaeir:BAAALgADCgYJBgAAAA==.Anarran:BAAALgAECgEJAQAAAA==.Angriff:BAAALgADCgQJBQAAAA==.Anisette:BAABLgAECn8pAAMGAAkJnRcdEgAxAgAGAAkJnRcdEgAxAgAHAAQJDgqzaAB2AAAAAA==.Annuket:BAAALgAECgYJBgAAAA==.Anthria:BAAALgADCgkJGwAAAA==.',
Ap='Apexpredåtor:BAAALgADCgIJAgAAAA==.',
Aq='Aqurala:BAABLgAECn8jAAIIAAkJXRxcIgBbAgAIAAkJXRxcIgBbAgAAAA==.',
Ar='Aradem:BAAALgADCgcJBwABLgAFFAMJBgAIAJ0GAA==.Aravenn:BAABLgAFFH8GAAIIAAMJnQZmHADFAAAIAAMJnQZmHADFAAAAAA==.Arbitir:BAAALgADCgEJAQAAAA==.Arcis:BAABLgAECn8kAAIJAAcJ0RKKkwBMAQAJAAcJ0RKKkwBMAQAAAA==.Ardeniro:BAAALgAECgIJBwAAAA==.Arealis:BAAALgADCgcJDAAAAA==.Argatem:BAAALgAECgQJBAABLgAECggJKgAKAEYeAA==.Arkangel:BAACLgAFFH8IAAILAAQJIQ2gjwDsAAALAAQJIQ2gjwDsAAAuAAQKfyoAAwsACQk7HEAmAGsCAAsACQk7HEAmAGsCAAwAAQlhCbU8AC0AAAAA.Arke:BAAALgAECgMJAwAAAA==.Arkharon:BAAALgADCgYJCQAAAA==.Arralyon:BAAALgADCgMJBgAAAA==.Artemesia:BAAALgAFFAQJBAABLgAFFAcJLgANAO4eAA==.Arthäs:BAAALgAECgQJBAAAAA==.Aryrn:BAAALgADCgUJBQAAAA==.',
As='Asakua:BAAALgAECgMJBgAAAA==.Asiya:BAAALgAECgQJBQAAAA==.Assandra:BAAALgADCgUJBQAAAA==.Astræa:BAAALgAECgYJBgAAAA==.',
At='Athul:BAAALgADCgUJCgAAAA==.',
Au='Aurlyn:BAAALgAECgMJAwAAAA==.',
Av='Avatartele:BAAALgAECgIJAwAAAA==.Avatartouka:BAABLgAECn8jAAMNAAgJ5yGbEQDBAgANAAgJ5yGbEQDBAgAOAAQJ9RPVbQCgAAAAAA==.Avianthel:BAAALgADCgMJAgAAAA==.Avraria:BAABLgAECn8aAAIPAAkJphUJEQAZAgAPAAkJphUJEQAZAgAAAA==.Avyl:BAABLgAECn8bAAQBAAYJ+xHZFQAcAQABAAYJ1hDZFQAcAQAQAAQJNhHYHADBAAACAAIJpgZvHwExAAAAAA==.Avylastorica:BAAALgADCgYJBgABLgAECgYJGwABAPsRAA==.',
Aw='Awsomninja:BAABLgAECn8mAAIHAAkJAiOcBQDmAgAHAAkJAiOcBQDmAgAAAA==.',
Ax='Axxain:BAAALgADCgkJGgAAAA==.',
Az='Azaralle:BAAALgADCgEJAQAAAA==.Azeazal:BAAALgAECgcJEwAAAA==.Azlifan:BAAALgADCgQJBAAAAA==.Azorthragal:BAAALgADCgYJBgABLgAECgUJBwARAAAAAA==.',
Ba='Baddlandss:BAAALgAECgQJCAAAAA==.Bagador:BAAALgAFFAEJAQAAAA==.Bastais:BAAALgAECgEJAQAAAA==.Batozai:BAAALgADCgEJAQAAAA==.Baumstack:BAAALgADCgUJBQAAAA==.',
Bd='Bdibz:BAAALgADCgcJDAAAAA==.',
Be='Beautifulluv:BAABLgAECn8sAAQSAAkJSyIJBQAtAwASAAkJSyIJBQAtAwATAAYJzA15RQD5AAAUAAEJkAzNUwA6AAAAAA==.Beelzabubba:BAAALgAECgkJAwAAAA==.Beewaregobs:BAAALgAECgIJAgAAAA==.Bekabeka:BAACLgAFFH8dAAIVAAYJox0ADgDYAQAVAAYJox0ADgDYAQAuAAQKf00ABBUACQk+JFYFAD0DABUACQk+JFYFAD0DAAkABQm5CAQGAbEAAAMABQmOBj84AH4AAAAA.Belfour:BAAALgAECgEJAgAAAA==.Bera:BAAALgAECgUJDwABLgAECgkJCwARAAAAAA==.Beramage:BAAALgAECgEJAQAAAA==.',
Bi='Billybobjr:BAACLgAFFH8KAAMNAAMJgCK6LgAnAQANAAMJgCK6LgAnAQAOAAEJDQVBIQA2AAAuAAQKf0kAAw0ACQnrIdMGAEMDAA0ACQnrIdMGAEMDAA4AAQkhEKimADEAAAAA.Bippitybop:BAAALgAECgEJAQAAAA==.',
Bl='Blackbart:BAAALgADCgcJCgAAAA==.',
Bo='Boamere:BAABLgAECn8/AAIWAAkJoxz+BgCXAgAWAAkJoxz+BgCXAgAAAA==.Botemedel:BAAALgADCgEJAQAAAA==.',
Br='Braided:BAAALgAECgIJAwAAAA==.Brakkar:BAABLgAECn9TAAIXAAkJbRp9AAByAgAXAAkJbRp9AAByAgAAAA==.Brandish:BAAALgADCgcJBwAAAA==.Breadstick:BAABLgAECn83AAIKAAkJmyUnAQDPAwAKAAkJmyUnAQDPAwAAAA==.Brevik:BAAALgADCgMJAwAAAA==.Brutaal:BAAALgADCgcJCwAAAA==.Brynhild:BAAALgAFFAIJAwAAAA==.Brütaal:BAABLgAECn8iAAMNAAgJthe/NQDaAQANAAcJphe/NQDaAQAOAAUJGgafdQCMAAAAAA==.',
Bu='Bubsydogo:BAABLgAECn8bAAIOAAkJPRTrHQDyAQAOAAkJPRTrHQDyAQAAAA==.Buddytheelf:BAABLgAECn8yAAMCAAkJFST1BABAAwACAAkJuCP1BABAAwAQAAIJiyXbLABkAAAAAA==.Bumpyflea:BAAALgADCgUJBQAAAA==.',
Ca='Cairnsilvers:BAAALgADCgEJAQAAAA==.Camus:BAABLgAECn8aAAIJAAgJHBqrTwDZAQAJAAgJHBqrTwDZAQAAAA==.Capped:BAAALgADCgMJAwAAAA==.Catgirl:BAAALgAECgYJCAAAAA==.',
Ce='Cebollin:BAAALgAECgUJCAAAAA==.Celaian:BAAALgAECgUJCgABLgAFFAEJAQARAAAAAA==.Celamor:BAAALgAECgQJBwAAAA==.Celasmine:BAAALgADCgYJCAAAAA==.Celpanda:BAAALgAFFAEJAQAAAA==.',
Ch='Chamoan:BAAALgAECgMJAwAAAA==.Charlamayne:BAAALgADCgcJBwAAAA==.Charybdia:BAABLgAECn8nAAIYAAkJngc/cQBAAQAYAAkJngc/cQBAAQAAAA==.Chidõri:BAACLgAFFH8YAAIOAAYJhBonGgBKAQAOAAYJhBonGgBKAQAuAAQKfy4AAw4ACQmDI0kFAEMDAA4ACQmDI0kFAEMDABkAAgnPFuUlAHkAAAAA.Chimerå:BAAALgADCgEJAQAAAA==.Chopstix:BAAALgADCgcJDgAAAA==.Chudlock:BAAALgAECgYJEgAAAA==.Chunni:BAABLgAECn8hAAIGAAkJHAobLwBNAQAGAAkJHAobLwBNAQAAAA==.',
Ci='Cilicia:BAAALgADCgUJBQAAAA==.',
Co='Codap:BAAALgADCgcJBwAAAA==.Coffees:BAAALgAECgEJAgAAAA==.Coolbeard:BAAALgAFFAEJAQAAAA==.Coolerfrieza:BAAALgAECgYJDAAAAA==.',
Cp='Cpr:BAABLgAECn8XAAIVAAcJiCGvDwCXAgAVAAcJiCGvDwCXAgAAAA==.',
Cr='Crayonman:BAAALgAECgMJAwABLgAFFAQJCgAXAEoiAA==.Crepic:BAAALgAECgQJBAAAAA==.Cruelkitty:BAABLgAECn8gAAMPAAgJIAUJRACmAAAPAAYJzgYJRACmAAAaAAgJMgHwIQCOAAAAAA==.',
Cu='Cubanwarlock:BAAALgAECgIJAgAAAA==.Cudibandit:BAAALgADCgcJDwAAAA==.Cullodena:BAAALgAECgEJAQAAAA==.',
Cy='Cynaria:BAAALgAECgEJAwABLgAFFAIJBgAKADobAA==.Cyralai:BAACLgAFFH82AAIKAAgJQRfNBgCZAgAKAAgJQRfNBgCZAgAuAAQKfxkAAgoACQlQIfEQALACAAoACQlQIfEQALACAAAA.',
['Cä']='Cäelus:BAAALgADCgUJBQABLgAFFAcJFgAJAJsTAA==.',
Da='Dabofdeath:BAAALgAECgIJAgAAAA==.Dalov:BAABLgAECn8gAAMVAAcJSSbxBwDvAgAVAAcJSSbxBwDvAgAJAAIJbx3CHgGVAAAAAA==.Dankley:BAABLgAECn8WAAIbAAgJYQcGTQATAQAbAAgJYQcGTQATAQAAAA==.Darkestnyte:BAAALgAECggJDwAAAA==.Darkk:BAAALgAECgQJDQAAAA==.Darkpalidin:BAAALgAECgYJBgABLgAECgkJKgAFAFgbAA==.Darkrhaenies:BAAALgADCgcJBwAAAA==.Darkwindx:BAAALgADCggJCQABLgAECgYJEgARAAAAAA==.Datezero:BAAALgADCgQJBAAAAA==.',
Dd='Ddream:BAAALgADCgQJBAAAAA==.',
De='Deadhealer:BAAALgADCgMJBQAAAA==.Deafknighte:BAAALgAECgMJAwAAAA==.Deathboi:BAABLgAECn8xAAILAAkJwxsWHACfAgALAAkJwxsWHACfAgAAAA==.Deathburgur:BAABLgAECn8gAAMLAAkJfxX+NwAfAgALAAkJfxX+NwAfAgAMAAcJpQt/FQAuAQAAAA==.Deathfromme:BAAALgAECgYJCgAAAA==.Deathstro:BAAALgAECgYJDgABLgAFFAQJCAALACENAA==.Decayed:BAAALgAECgUJDgAAAA==.Demonicuss:BAAALgAECgEJAQAAAA==.Demontress:BAAALgADCgQJBAAAAA==.Dentridios:BAAALgADCgIJAgAAAA==.Deson:BAABLgAECn8mAAMVAAkJCRICLgCmAQAVAAkJCRICLgCmAQAJAAUJiQi+DAGpAAAAAA==.Deviantart:BAAALgAECgQJBAAAAA==.',
Di='Diana:BAABLgAECn8kAAIIAAkJqA2qSgDBAQAIAAkJqA2qSgDBAQAAAA==.Diietriich:BAABLgAECn8zAAIFAAkJriJCDQAPAwAFAAkJriJCDQAPAwAAAA==.Dilligaaf:BAAALgADCgMJAwAAAA==.',
Do='Docbeanz:BAAALgADCgMJAwAAAA==.Donkypunch:BAAALgADCgQJBAAAAA==.Dontjudgemê:BAAALgADCgIJAgAAAA==.Doodlekhal:BAAALgADCgMJAwAAAA==.Dopie:BAAALgADCgIJAgAAAA==.Dorcina:BAAALgAECgIJAgAAAA==.',
Dr='Dracthyr:BAAALgADCgUJDQAAAA==.Dragonwarrio:BAAALgAECgEJAQAAAA==.Dragoondpain:BAAALgAECgQJCwAAAQ==.Drakai:BAAALgAECgEJAgAAAA==.Draltina:BAABLgAECn8XAAMBAAgJPAmkDQBaAQABAAgJPAmkDQBaAQACAAEJywLtLwEhAAAAAA==.Drazira:BAABLgAECn8hAAIYAAkJsgTWlQD1AAAYAAkJsgTWlQD1AAAAAA==.Drugonwerier:BAAALgADCgEJAgAAAA==.Drunkbera:BAAALgAECgcJDQAAAA==.Druzzlek:BAAALgAECgEJAQAAAA==.',
Du='Dubalpally:BAAALgADCggJDQAAAA==.Dunks:BAABLgAFFH8FAAICAAMJJwM9jwCmAAACAAMJJwM9jwCmAAAAAA==.Duskfu:BAABLgAECn8uAAIGAAkJnR/DCgCXAgAGAAkJnR/DCgCXAgAAAA==.',
Dy='Dylghoul:BAAALgADCgUJBQAAAA==.',
['Dí']='Dírac:BAABLgAFFH8GAAICAAMJTw2lfQDJAAACAAMJTw2lfQDJAAABLgAFFAQJCQANAGkcAA==.',
Ec='Eclipsekitty:BAAALgAECgUJBgABLgAFFAQJDAAVALETAA==.',
Ed='Edwillei:BAAALgAECgUJCAAAAA==.',
Ef='Efforex:BAAALgADCgQJBAAAAA==.',
Ei='Einhar:BAAALgAECgEJAgAAAA==.',
El='Elactoplasm:BAAALgAECgMJAwAAAA==.Elderslapaho:BAAALgADCgUJBgAAAA==.Ellistrae:BAAALgAECgYJCQAAAA==.Ellysia:BAAALgADCgEJAQAAAA==.',
Em='Emmel:BAAALgADCggJCwAAAA==.',
Ep='Epicknee:BAAALgAECgEJAQAAAA==.',
Eq='Equeslucis:BAAALgAECgcJBwAAAA==.',
Er='Erodrana:BAAALgAECgYJEgABLgAECgkJIQAYALIEAA==.Eromir:BAAALgAECgUJCgAAAA==.Eryi:BAABLgAECn9SAAIEAAkJvhrHDwCoAgAEAAkJvhrHDwCoAgAAAA==.',
Et='Ethan:BAABLgAECn8eAAMcAAkJnRvdEQDZAQAcAAcJIRjdEQDZAQAbAAQJ6CICVgD1AAAAAA==.',
Ev='Evonari:BAAALgADCgIJAgAAAA==.',
Ex='Exoticfrost:BAAALgADCgIJAgAAAA==.Expertnewb:BAAALgAECgIJAgABLgAECgkJKgAFAFgbAA==.',
['Eí']='Eísheth:BAAALgADCgUJBAAAAA==.',
Fa='Faegen:BAAALgAECgEJAgAAAA==.Falkønn:BAAALgAECgMJAwAAAA==.Fallumn:BAAALgAECgEJAQAAAA==.Fangytooth:BAACLgAFFH8KAAIXAAQJSiJFCACMAQAXAAQJSiJFCACMAQAuAAQKfy4AAhcACQl5JPoCABADABcACQl5JPoCABADAAAA.Fashaun:BAAALgAECgIJAgAAAA==.Faze:BAABLgAECn8aAAIFAAYJyx+LYgC5AQAFAAYJyx+LYgC5AQAAAA==.',
Fe='Fellamayne:BAAALgAECgEJAgAAAA==.Fellamayyne:BAAALgADCgEJAQAAAA==.Ferrus:BAACLgAFFH8kAAMYAAgJPiKrAwD9AQAYAAgJPiKrAwD9AQAPAAQJsxxiHADAAAAuAAQKfx8AAw8ACQn1JdANAIYCABgACQlgJOwcAKQCAA8ABwncJNANAIYCAAAA.',
Ff='Ffleuderflam:BAAALgAECgYJBgAAAA==.',
Fl='Floors:BAAALgAECgEJAQAAAA==.',
Fr='Frose:BAAALgADCgEJAQAAAA==.Frostyblast:BAAALgADCgUJBgAAAA==.',
Fu='Fupacabra:BAAALgADCgEJAQAAAA==.Furiiosa:BAAALgAECgUJBQAAAA==.Furiosity:BAAALgAECgMJBQAAAA==.Fuzzybear:BAAALgAECgcJCAABLgAFFAQJCgAXAEoiAA==.Fuzzybeard:BAAALgAECgYJBgABLgAFFAQJCgAXAEoiAA==.Fuzzyspells:BAAALgAECgEJAQABLgAFFAQJCgAXAEoiAA==.Fuzzywar:BAAALgAECgYJBwABLgAFFAQJCgAXAEoiAA==.',
['Fõ']='Fõrtress:BAAALgAECgMJBAAAAA==.',
Ga='Gabomonk:BAABLgAFFH8FAAIHAAIJ1iRMNwDJAAAHAAIJ1iRMNwDJAAAAAA==.Galaxybell:BAAALgAECgEJAgAAAA==.Galvandra:BAABLgAECn8rAAMVAAkJGiQpAgCNAwAVAAkJGiQpAgCNAwAJAAgJESNDAQDIAgAAAA==.Gamalia:BAAALgADCgUJBQAAAA==.Garudekhan:BAAALgADCgUJBQAAAA==.',
Ge='Genreallee:BAABLgAECn8dAAIJAAcJ1hIPjgBVAQAJAAcJ1hIPjgBVAQAAAA==.Gernab:BAAALgADCgYJBgAAAA==.',
Gh='Ghost:BAABLgAECn8WAAIKAAYJ9xt+NgDOAQAKAAYJ9xt+NgDOAQAAAA==.',
Gi='Gizzar:BAAALgADCgYJCgAAAA==.',
Gl='Glau:BAAALgAECgQJBAABLgAECggJCQARAAAAAA==.Glimpsed:BAAALgAECgcJDgABLgAECgkJCwARAAAAAA==.Globgore:BAAALgADCgIJBAAAAA==.Gloçk:BAAALgAECgMJCAABLgAECgYJEQARAAAAAA==.',
Go='Goofy:BAABLgAECn8fAAIJAAcJYCHDJACUAgAJAAcJYCHDJACUAgAAAA==.Goor:BAAALgAECgEJAQAAAA==.Gorrik:BAAALgADCgUJBQAAAA==.',
Gr='Graeae:BAAALgAECgkJDwAAAA==.Greyfeather:BAAALgADCgEJAgAAAA==.Grimeace:BAAALgADCgQJBAAAAA==.',
Gu='Gunduin:BAACLgAFFH8FAAIIAAIJ/hYPfwCaAAAIAAIJ/hYPfwCaAAAuAAQKfx4AAggACAmuIBQeAFECAAgACAmuIBQeAFECAAAA.',
Gw='Gweb:BAAALgAECgIJAgAAAA==.',
Gy='Gyda:BAABLgAECn8vAAIUAAkJux/qBwD5AgAUAAkJux/qBwD5AgAAAA==.Gyuyuki:BAABLgAECn9RAAIOAAkJQhikFQA6AgAOAAkJQhikFQA6AgAAAA==.',
Ha='Hakuanah:BAAALgADCgEJAQAAAA==.Halvorak:BAAALgADCgcJCgAAAA==.Harryp:BAACLgAFFH8KAAIdAAQJ7gxqOwDZAAAdAAQJ7gxqOwDZAAAuAAQKfzYAAx4ACQm5GP0GANcBAB0ACQnlEp0dAOoBAB4ACQlDFf0GANcBAAAA.Hast:BAABLgAECn8XAAIfAAYJFBBsQgADAQAfAAYJFBBsQgADAQAAAA==.',
He='Hearthzilla:BAAALgAECgEJAQABLgAECgkJIgAOAN4fAA==.Hechicero:BAAALgAECgEJAQAAAA==.Heidie:BAAALgAECgUJCgAAAA==.Hellsbow:BAAALgAECgYJDgAAAA==.Hermin:BAAALgADCgQJCAAAAA==.',
Ho='Holyhellz:BAAALgADCgEJAQAAAA==.Honeyboo:BAAALgAECgUJBQABLgAFFAQJDAAKAKMSAA==.Hots:BAAALgADCgcJBwAAAA==.Hotzz:BAAALgAECgEJAQAAAA==.',
Hr='Hraesvelgr:BAAALgADCggJBwAAAA==.',
Hu='Huntavious:BAACLgAFFH8LAAIXAAQJtxaHBQDqAAAXAAQJtxaHBQDqAAAuAAQKfzUABBcACQk8H2cFANECABcACQk8H2cFANECAAgABgnjGsZeAEsBACAAAQnIE9uKADAAAAAA.',
['Hë']='Hëllen:BAABLgAECn8aAAIJAAYJMiDDDgDFAAAJAAYJMiDDDgDFAAAAAA==.',
['Hú']='Húñtrèss:BAAALgAECgUJBwAAAA==.',
Ia='Iamshinigamy:BAAALgAECgIJAgABLgAECgcJFwAFAPMaAA==.',
Ic='Icdatprince:BAAALgAFFAMJAwAAAA==.',
Ii='Iichimaru:BAAALgAECgUJBQAAAA==.',
Il='Illidupe:BAAALgADCgMJAwAAAA==.',
Im='Imakittycat:BAAALgAECggJCAAAAA==.',
In='Inaoh:BAAALgAECgQJBwAAAA==.Insaniac:BAAALgAECgQJBAAAAA==.',
Ir='Ironboss:BAABLgAECn8bAAIJAAcJOxB+BwA5AQAJAAcJOxB+BwA5AQAAAA==.',
Iv='Ivey:BAABLgAECn8qAAIKAAgJRh7fFACjAgAKAAgJRh7fFACjAgAAAA==.',
Iz='Izes:BAAALgAECgEJAwAAAA==.',
Ja='Jaagganug:BAAALgAECgcJBwAAAA==.Jacenne:BAABLgAECn8eAAIfAAcJ8Qn9BgCgAAAfAAcJ8Qn9BgCgAAAAAA==.Jairus:BAAALgAECgcJBwAAAA==.',
Jd='Jdirty:BAABLgAECn8YAAIhAAYJhAnjEgDcAAAhAAYJhAnjEgDcAAAAAA==.',
Je='Jellytime:BAAALgAECgMJBQAAAA==.',
Jo='Josephyn:BAAALgAFFAEJAQABLgAFFAcJLgANAO4eAA==.',
Ju='Jugernaut:BAAALgAECgEJAQAAAA==.Jumpmann:BAAALgAECgMJAwAAAA==.Justdesserts:BAAALgAECgEJAQAAAA==.Justix:BAAALgADCggJEwAAAA==.',
Ka='Kadaffy:BAAALgAECgQJBQAAAA==.Kakota:BAAALgADCgQJBAABLgAECgkJGgAOAA4dAA==.Kakusu:BAAALgAECgYJEQAAAA==.Kakuta:BAABLgAECn8VAAIVAAYJjhYGAgCdAQAVAAYJjhYGAgCdAQABLgAECgkJGgAOAA4dAA==.Kakutá:BAABLgAECn8aAAIOAAkJDh2MDACcAgAOAAkJDh2MDACcAgAAAA==.Kalru:BAAALgAECgIJAgAAAA==.Kargar:BAAALgAECgEJAgAAAA==.Karliah:BAAALgAECgIJAgAAAA==.Katharsis:BAACLgAFFH8VAAIJAAQJ9xHdEgDvAAAJAAQJ9xHdEgDvAAAuAAQKfyEAAgkACQnPFoZGAPMBAAkACQnPFoZGAPMBAAAA.',
Ke='Keba:BAAALgAECgEJAQABLgAFFAYJHQAVAKMdAA==.Keit:BAAALgADCgYJBgABLgAFFAQJCgAPAPkeAA==.',
Kh='Khalidisi:BAACLgAFFH8FAAQDAAMJyxzMBwD9AAADAAMJyxzMBwD9AAAJAAEJEAsLxAA7AAAVAAEJoxWtSAA5AAAuAAQKfzAABAMACQnsH8gGAHYCAAMACAmxH8gGAHYCABUACQktGTgvAJ4BAAkACQnIDRJpAJ0BAAAA.Khaliesi:BAAALgADCgIJAgAAAA==.Khalizar:BAABLgAFFH8NAAIbAAQJLAnsKwAEAQAbAAQJLAnsKwAEAQAAAA==.Kharazim:BAAALgADCgEJAQABLgAECgkJOgAYAKkeAA==.Khenja:BAAALgAECgEJAQAAAA==.Khál:BAAALgADCgYJBgAAAA==.',
Ki='Killerelf:BAABLgAECn8YAAIJAAgJiwedrwAgAQAJAAgJiwedrwAgAQAAAA==.Kittie:BAAALgADCggJCAAAAA==.',
Kk='Kkiilleerr:BAAALgAECgYJDwAAAA==.',
Ko='Kobbaltcilar:BAAALgAECgUJBgAAAA==.Koraleena:BAAALgAECgQJBAAAAA==.Korbo:BAABLgAECn8sAAMNAAkJMBtSNgDXAQANAAcJKBhSNgDXAQAOAAUJeR4tKwCaAQAAAA==.Korbulo:BAABLgAECn8UAAIFAAkJmwmfdwCKAQAFAAkJmwmfdwCKAQAAAA==.Korlothel:BAABLgAECn8kAAIDAAkJvAcEIQAMAQADAAkJvAcEIQAMAQABLgAFFAMJBgAIAJ0GAA==.Korrith:BAAALgADCgIJAgAAAA==.',
Kr='Kreeper:BAAALgADCgEJAQAAAA==.Krumpus:BAABLgAECn8jAAIYAAkJ5xTyLwAHAgAYAAkJ5xTyLwAHAgAAAA==.Kryma:BAAALgAECgcJBwAAAA==.',
Ku='Kungfuuy:BAABLgAECn8rAAIHAAkJ1SGzBAD5AgAHAAkJ1SGzBAD5AgAAAA==.Kurtevade:BAAALgAECgQJDAAAAA==.',
Kw='Kwetnepthl:BAAALgAECgEJAgAAAA==.',
Ky='Kynsong:BAABLgAECn8pAAISAAkJTxWfFgAbAgASAAkJTxWfFgAbAgAAAA==.',
['Kà']='Kàlbrews:BAABLgAECn9AAAIHAAkJvyZOAACHAwAHAAkJvyZOAACHAwAAAA==.Kàrmâ:BAAALgAECgUJBQAAAA==.',
['Kî']='Kîrah:BAAALgAFFAIJAgAAAA==.',
La='Lagk:BAAALgAECgYJEQAAAA==.Lainiee:BAAALgADCgEJAQAAAA==.Lavismad:BAECLgAFFH8LAAIbAAQJuiDLDwCHAQAbAAQJuiDLDwCHAQAuAAQKfzQABBsACQkMJZgEABsDABsACQnYJJgEABsDABYABwmhIJQPAO8BABwAAQlGJXcyAGkAAAAA.Lavoc:BAEALgADCgcJBwABLgAFFAQJCwAbALogAA==.Lavv:BAEALgAECgYJCAABLgAFFAQJCwAbALogAA==.Lavz:BAEALgAECgYJBgABLgAFFAQJCwAbALogAA==.',
Le='Legendary:BAAALgAECgYJDQAAAA==.Leshah:BAAALgAECgYJCwAAAA==.',
Li='Lichkingdied:BAAALgADCgUJBQAAAA==.Lightndpain:BAAALgAECgQJBgABLgAECgQJCwARAAAAAA==.Lildh:BAAALgAECgYJEQAAAA==.Lilypetal:BAAALgAECgQJBwAAAA==.Lionaest:BAAALgAECgYJEAAAAA==.Littlebucket:BAAALgADCgEJAQAAAA==.',
Lo='Lockdpain:BAAALgAECgYJGAABLgAECgQJCwARAAAAAQ==.Logov:BAAALgAECgYJDwAAAA==.Loraine:BAAALgAECgEJAQAAAA==.Loìsbethe:BAAALgAECgYJCgAAAA==.',
Lu='Luciferra:BAABLgAFFH8LAAISAAUJEhKkEgA1AQASAAUJEhKkEgA1AQABLgAFFAcJLgANAO4eAA==.Lukey:BAAALgAECgMJAwAAAA==.Lunartemis:BAAALgAECgUJCAABLgAFFAUJEAAiACchAA==.Luu:BAAALgAECgQJCAAAAA==.',
Ly='Lyza:BAAALgADCgYJCQAAAA==.',
['Lö']='Lörax:BAAALgADCgQJBQAAAA==.',
['Lû']='Lûnafreya:BAAALgAECggJEgAAAA==.',
Ma='Maelera:BAAALgADCgkJDAAAAA==.Maetromundo:BAAALgAECgEJAQAAAA==.Maevan:BAAALgADCgEJAQAAAA==.Magentas:BAAALgADCgIJAgAAAA==.Magickul:BAAALgADCggJCAAAAA==.Mahlah:BAAALgAECgQJBAAAAA==.Malaboo:BAAALgAECgEJAQABLgAFFAQJDAAKAKMSAA==.Malabooty:BAAALgAECgYJBwABLgAFFAQJDAAKAKMSAA==.Malakaii:BAAALgAECgEJAQAAAA==.Maletsy:BAAALgAECgEJAQABLgAFFAIJBQAIAP4WAA==.Maliboo:BAACLgAFFH8MAAIKAAQJoxLNDACxAAAKAAQJoxLNDACxAAAuAAQKfzkAAwoACQlEIsAEAG8DAAoACQlEIsAEAG8DAB8AAgmfCQ2OADIAAAAA.Maxamus:BAABLgAECn8dAAQcAAYJaCKTAQA5AQAcAAYJaCKTAQA5AQAWAAUJzBgOKQDsAAAbAAEJgxeYlQBHAAAAAA==.Maxigooner:BAABLgAFFH8FAAIYAAMJKRYYXwDSAAAYAAMJKRYYXwDSAAABLgAFFAUJIgAJAFwmAA==.Maxpower:BAAALgAECgEJAQAAAA==.',
Mc='Mcflurry:BAAALgAECgUJCwAAAA==.',
Me='Medarisa:BAAALgAECgcJDQAAAA==.Medavia:BAAALgADCgUJBQAAAA==.Mederia:BAAALgAECgUJBQAAAA==.Medívh:BAAALgADCgEJAQAAAA==.Melisandr:BAAALgAECgMJBQAAAA==.Merkenier:BAABLgAECn85AAIfAAgJWRUSIQDAAQAfAAgJWRUSIQDAAQAAAA==.Merkshamalot:BAAALgAECgEJAQABLgAECggJOQAfAFkVAA==.Merkur:BAABLgAECn8aAAMJAAYJwAnz2wDjAAAJAAYJwAnz2wDjAAAVAAEJigHboQAbAAABLgAECggJOQAfAFkVAA==.Merkurry:BAAALgAECgEJAQABLgAECggJOQAfAFkVAA==.',
Mi='Midnitehunt:BAAALgAECgQJBAAAAA==.Miragia:BAAALgAECgYJEgAAAA==.Missmayhem:BAAALgAECgUJCAAAAA==.Missmayhemm:BAAALgADCgQJBgAAAA==.',
Mo='Modifiedmix:BAABLgAECn8sAAIIAAgJfxnxKwAtAgAIAAgJfxnxKwAtAgAAAA==.Modsabadtank:BAAALgAECgYJCwABLgAECggJLAAIAH8ZAA==.Mokomohama:BAAALgAECgcJBwAAAA==.Monatazumaa:BAAALgAECgEJAgAAAA==.Moonbloom:BAAALgAFFAEJAQABLgAFFAcJLgANAO4eAA==.Mopeezie:BAAALgAECgEJAQAAAA==.Mordicant:BAAALgADCgEJAQABLgAECgYJDQARAAAAAA==.Morella:BAABLgAECn81AAIQAAcJmQ4HGQCDAQAQAAcJmQ4HGQCDAQAAAA==.',
Mu='Mucduck:BAAALgADCgEJAQAAAA==.Mustakrakish:BAAALgAECgEJAQAAAA==.Mustaz:BAAALgAECgkJBQAAAA==.',
My='Mym:BAAALgADCgcJBAAAAA==.Mystics:BAAALgAECgUJBgAAAA==.Mythrunduil:BAAALgADCgEJAQAAAA==.',
['Må']='Mågi:BAAALgAFFAIJAgAAAA==.',
['Mé']='Médb:BAABLgAECn8wAAMFAAkJdx7dGADEAgAFAAkJDB7dGADEAgAjAAMJFR2jCQDmAAAAAA==.',
Na='Naia:BAAALgAECgEJAQAAAA==.Naste:BAAALgAECgUJBQAAAA==.Nathrold:BAAALgAECgIJBAABLgAECgYJEQARAAAAAA==.',
Ne='Necrobon:BAAALgAECgYJCAAAAA==.Necrognome:BAAALgAECgMJBAAAAA==.Neptune:BAACLgAFFH8uAAINAAcJ7h7zDwDsAQANAAcJ7h7zDwDsAQAuAAQKfyEAAw0ACQlRIhgHAAIDAA0ACQlRIhgHAAIDAA4ABwkkDtE0AIQBAAAA.Nerfdks:BAABLgAECn8XAAIkAAkJYhYyFADRAQAkAAkJYhYyFADRAQAAAA==.Nerfpaladins:BAABLgAECn8lAAQJAAcJpRKPnAA9AQAJAAcJTBGPnAA9AQADAAcJJBHJJADvAAAVAAMJzAQ7dwBgAAAAAA==.Nerfpriests:BAAALgAFFAIJAgAAAA==.Neruess:BAAALgADCgUJBQAAAA==.Nezzuko:BAAALgAECgcJBwAAAA==.',
Ni='Nightbird:BAABLgAECn8dAAMiAAcJvBepKwA8AQAiAAcJThepKwA8AQAlAAYJ8BWfDgAsAQABLgAECggJCQARAAAAAA==.Ninediewatt:BAAALgAECgQJCAAAAA==.Nivella:BAAALgAECgYJCgAAAA==.Nixaana:BAAALgAECgUJBgAAAA==.Niçki:BAAALgADCgMJAwAAAA==.',
No='Notlockz:BAAALgADCgIJAgAAAA==.Novah:BAAALgADCgQJBQAAAA==.Noydb:BAAALgAECgYJBwABLgAECgkJPwAWAKMcAA==.',
Nu='Nuah:BAAALgADCgYJDQAAAA==.',
Ny='Nyxsia:BAEALgAFFAEJAQABLgAFFAcJIgAbAJAdAA==.',
['Nå']='Nåmi:BAAALgAECgYJBgAAAA==.',
['Nè']='Nèo:BAAALgADCgcJBwAAAA==.',
Ob='Obayi:BAABLgAECn9EAAIIAAcJ/hCrCAA0AQAIAAcJ/hCrCAA0AQAAAA==.Obsaedia:BAAALgAECgcJBwABLgAECggJHAARAAAAAQ==.',
Oc='Oculo:BAAALgADCgMJAwAAAA==.',
Od='Odinsgrace:BAAALgAECgEJAQAAAA==.',
Og='Ogmadmonk:BAACLgAFFH8MAAIPAAMJnRLOGgDLAAAPAAMJnRLOGgDLAAAuAAQKfzEAAg8ACQmUIQsJAJoCAA8ACQmUIQsJAJoCAAAA.',
Ok='Oktobra:BAABLgAECn8eAAIJAAYJMANjHgGVAAAJAAYJMANjHgGVAAAAAA==.',
On='Onetrickpony:BAAALgAECgIJAgAAAA==.Onos:BAAALgAECgIJAgAAAA==.Onosm:BAAALgAECgQJBAAAAA==.',
Or='Orangevoker:BAAALgAECgcJCwABLgAECgkJIgAOAN4fAA==.Ordin:BAAALgAECgEJAQAAAA==.Orioan:BAAALgAECgUJCQAAAA==.Orux:BAAALgAECgYJBgAAAA==.',
Os='Osenya:BAAALgAECgYJBgABLgAFFAQJDAALAHcfAA==.Osun:BAAALgAECgQJBQAAAA==.',
Ou='Ouroboro:BAAALgADCgUJBQAAAA==.',
Ow='Owlbat:BAAALgAECgEJAQAAAA==.',
Pa='Padremort:BAAALgADCgYJBgAAAA==.Palantyr:BAABLgAECn9fAAIOAAgJvRqZGgA+AgAOAAgJvRqZGgA+AgAAAA==.Paly:BAAALgAECgEJAQAAAA==.Para:BAAALgAECgcJCQAAAA==.Patrician:BAABLgAECn8sAAIhAAkJdhdpBAA9AgAhAAkJdhdpBAA9AgAAAA==.',
Pe='Penutbutter:BAAALgAECgQJCAAAAA==.Pepegasus:BAAALgADCgcJBwAAAA==.',
Ph='Phobos:BAAALgADCgQJCAAAAA==.Phyloren:BAAALgADCgUJBgAAAA==.',
Pi='Picklemorty:BAAALgAFFAEJAQABLgAFFAEJAQARAAAAAA==.Pigsticker:BAAALgAECgQJBQAAAA==.Pixyfire:BAAALgAECgYJCgABLgAFFAQJDAAVALETAA==.',
Po='Poisonleaf:BAAALgAECgUJBgABLgAECgYJGgAJADIgAA==.Pokingharder:BAABLgAECn8kAAIlAAkJRRbUBAA9AgAlAAkJRRbUBAA9AgABLgAFFAMJEAABAKAYAA==.',
Pu='Pulcherrimus:BAAALgAECgEJAwAAAA==.Purgeem:BAAALgADCgUJBQAAAA==.Pushpop:BAAALgAECgYJDwABLgAECggJXwAOAL0aAA==.',
Pw='Pwiest:BAAALgADCgcJEAAAAA==.',
Qu='Quetzalcoatl:BAABLgAECn8jAAMmAAkJMhxzAAAAAgAmAAkJMhxzAAAAAgAdAAEJ9gXODgAqAAAAAA==.',
Ra='Raambox:BAAALgAECgQJBAAAAA==.Radak:BAAALgAECgEJAQAAAA==.Raddish:BAABLgAECn8eAAISAAYJtBJLBgCoAAASAAYJtBJLBgCoAAAAAA==.Raedl:BAAALgAECgUJBgAAAA==.Ragriefy:BAAALgAECgEJAQAAAA==.Rahjlynn:BAAALgAECgEJAQAAAA==.Rahken:BAAALgAECgcJBwAAAA==.Raiinn:BAAALgADCgUJBQAAAA==.Raylee:BAACLgAFFH8MAAQBAAQJVyATBABNAQABAAQJQhUTBABNAQACAAIJoxvFHQCzAAAQAAIJ4xtwEgCkAAAuAAQKfz4ABAIACQmeIcEUAKkCAAIACAmxH8EUAKkCABAABwl8IQ8IAEQCAAEAAwk2GvQZAPAAAAAA.Razuki:BAACLgAFFH8MAAMVAAQJsROeJwDmAAAVAAQJsROeJwDmAAAJAAIJjBQ+IAChAAAuAAQKfzQAAxUACQmLIoQFADoDABUACQmLIoQFADoDAAkABwn2F1hzAIcBAAAA.',
Re='Remyl:BAAALgADCggJCAAAAA==.Reynia:BAAALgAECgEJAQAAAA==.',
Rf='Rfd:BAAALgADCgcJBwABLgAECggJGQAOAMUSAA==.',
Rh='Rhaenies:BAAALgAECgYJEAAAAA==.Rharr:BAAALgADCgkJDAAAAA==.Rhovanion:BAAALgAECggJCQAAAA==.Rhuac:BAABLgAECn8qAAIKAAkJlhPKKQAGAgAKAAkJlhPKKQAGAgAAAA==.',
Ri='Rigymorty:BAAALgAECgMJBAAAAA==.Risakah:BAAALgAECggJCgAAAA==.',
Ro='Rorschach:BAAALgAECggJCwAAAA==.Rosefist:BAEALgADCgcJCAABLgAFFAcJEQAUAAMRAA==.Rosemourne:BAEALgAECgIJAgABLgAFFAcJEQAUAAMRAA==.Roseykat:BAABLgAECn8oAAIIAAkJkAoAXQCPAQAIAAkJkAoAXQCPAQAAAA==.Roshwyn:BAABLgAECn8VAAIIAAkJlwrhcABfAQAIAAkJlwrhcABfAQAAAA==.Rottedmeat:BAAALgAECgcJCgAAAA==.',
Ru='Rubmytotems:BAAALgAECgYJBgAAAA==.Ruckus:BAABLgAECn8nAAIJAAgJuRYPPwApAgAJAAgJuRYPPwApAgAAAA==.',
Sa='Saberwar:BAAALgAECgEJAQABLgAECgMJAwARAAAAAA==.Saintfury:BAAALgAECgQJBQAAAA==.Saintsfear:BAABLgAECn8qAAIbAAkJWQ+MJgDEAQAbAAkJWQ+MJgDEAQAAAA==.Samest:BAAALgAECgEJAQAAAA==.Sanchito:BAAALgADCgMJAwAAAA==.Saphalia:BAAALgADCgMJAwAAAA==.Saradomin:BAAALgADCgUJBAAAAA==.Sareenastar:BAACLgAFFH8MAAISAAQJIyIZBAAeAQASAAQJIyIZBAAeAQAuAAQKfy4AAxIACQmUJncAAN8DABIACQmUJncAAN8DABMAAQnfCWqKAC8AAAAA.Sasae:BAABLgAECn8hAAIHAAgJmhNKIAClAQAHAAgJmhNKIAClAQAAAA==.',
Sc='Scorias:BAAALgADCgQJAwAAAA==.',
Se='Selisztraza:BAAALgADCgEJAQAAAA==.Sephiróth:BAAALgADCgUJCAAAAA==.Sereni:BAAALgADCgQJBAAAAA==.Serenity:BAAALgAECgcJEwAAAA==.Serenitynow:BAAALgAECgEJAwAAAA==.Sewald:BAAALgAECgcJDwAAAA==.',
Sh='Shadowzbane:BAAALgAECgIJAgAAAA==.Shahasha:BAAALgADCgEJAQAAAA==.Shaidarharan:BAAALgADCgIJAgAAAA==.Shakeybop:BAAALgAECgQJBAAAAA==.Shalen:BAABLgAECn8vAAQdAAkJRBV6HwDcAQAdAAkJOBV6HwDcAQAeAAYJoQ2ZHQBCAQAmAAYJ7g2vGwAjAQAAAA==.Sharker:BAAALgADCgYJBgAAAA==.Sharkyb:BAAALgAECgEJAgABLgAECgkJNwALAKsiAA==.Sharpie:BAAALgADCgcJCgAAAA==.Sheer:BAABLgAECn8aAAMHAAgJYB8FDwBKAgAHAAgJYB8FDwBKAgAEAAYJkyEqGwA/AgAAAA==.Sheraa:BAABLgAECn8lAAIDAAkJeBJ9EAC9AQADAAkJeBJ9EAC9AQAAAA==.Shiftystrike:BAABLgAECn8WAAInAAcJPx/wCgAVAgAnAAcJPx/wCgAVAgAAAA==.Shifushield:BAAALgAECgcJCAAAAA==.Shireshannon:BAABLgAECn8VAAIIAAYJegmvogD8AAAIAAYJegmvogD8AAAAAA==.Shrike:BAAALgAECgIJBQABLgAFFAgJIQATAGQaAA==.Shrunkador:BAACLgAFFH8RAAIOAAQJMg1qKwDoAAAOAAQJMg1qKwDoAAAuAAQKfzMAAg4ACQm6HY8QAG4CAA4ACQm6HY8QAG4CAAAA.',
Si='Silicå:BAAALgAECgMJAwAAAA==.Silk:BAAALgAECgYJDgAAAA==.Silmarkthree:BAACLgAFFH8MAAIFAAQJeRXVHwDYAAAFAAQJeRXVHwDYAAAuAAQKfzQAAgUACQmkGCc6ADACAAUACQmkGCc6ADACAAAA.Sinbåd:BAAALgAECgcJDAAAAA==.Siodar:BAAALgADCgEJAQABLgAECgUJBwARAAAAAA==.Sisterstar:BAAALgADCgMJAwAAAA==.',
Sl='Sleety:BAAALgAECgIJBQAAAA==.Slipknoth:BAACLgAFFH8jAAMTAAgJzxoNBgAbAgATAAcJeh0NBgAbAgAUAAYJ3g1pGACqAQAuAAQKfywABBMACQnlInsRAEsCABMACAkHJXsRAEsCABIABwntF/kgANsBABQABAnOGQtGAO8AAAAA.',
Sn='Snekhain:BAAALgADCgMJAwAAAA==.Snuffaluffa:BAAALgAECgMJAwAAAA==.',
So='Somatra:BAAALgADCgkJCQAAAA==.Sorean:BAACLgAFFH8WAAIXAAUJNx7aCgBwAQAXAAUJNx7aCgBwAQAuAAQKfy8ABAgACQm+IFYhAD0CAAgABwlUG1YhAD0CABcABwlnHfkZAM8BACAABwlQGv0vALUBAAAA.',
Sp='Specialmove:BAAALgAFFAEJAgAAAA==.Spookydookie:BAAALgADCgkJCgAAAA==.',
St='Staghealz:BAAALgAECgIJBAAAAA==.Starkey:BAAALgAECgMJAwAAAA==.Stifs:BAABLgAECn8oAAIDAAgJGxYZFgB0AQADAAgJGxYZFgB0AQAAAA==.Stilleena:BAAALgAECgYJBgAAAA==.Stinkinglily:BAAALgAECgEJAgAAAA==.Strunrage:BAEALgAECgcJDAABLgAFFAIJBQAJAIEmAA==.Stÿx:BAABLgAECn8ZAAIkAAYJ6gXNQACMAAAkAAYJ6gXNQACMAAABLgAECgkJEwARAAAAAA==.',
Su='Sugarbomb:BAAALgADCgYJCgAAAA==.',
Sy='Sykotyk:BAAALgAECgkJDwAAAA==.Sylverfox:BAAALgAECgMJBAABLgAECgkJHwAVAJUfAA==.Synchestra:BAAALgADCgcJCgAAAA==.',
Ta='Tadagain:BAABLgAECn8jAAMJAAYJlhLvrAAjAQAJAAYJlhLvrAAjAQAVAAQJ2gV2dgChAAAAAA==.Tagrith:BAAALgADCgMJAwAAAA==.Tankybears:BAACLgAFFH8GAAIKAAIJOhvBRAChAAAKAAIJOhvBRAChAAAuAAQKfywAAx8ACQnOGmgRAE8CAB8ACQnOGmgRAE8CAAoACAnqGwZUAEABAAAA.Tarmalok:BAAALgAECgEJAQAAAA==.Tazera:BAAALgAECgUJCwAAAA==.',
Te='Telekinesis:BAABLgAECn8iAAIXAAgJvhCoIACXAQAXAAgJvhCoIACXAQAAAA==.Tenara:BAABLgAFFH8IAAINAAQJGRvHEQC/AAANAAQJGRvHEQC/AAABLgAFFAIJBgAKADobAA==.Tenbinza:BAAALgAECgUJBwAAAA==.Teos:BAACLgAFFH8FAAIZAAMJSQlcEQCyAAAZAAMJSQlcEQCyAAAuAAQKfzgAAhkACQmwGQMIAEcCABkACQmwGQMIAEcCAAAA.',
Th='Thadude:BAAALgAECgcJBwABLgAFFAQJEAAkADQWAA==.Thainé:BAAALgAECgMJBgAAAA==.Thaldrassian:BAAALgADCgQJBAAAAA==.Tharris:BAAALgAECgYJCwAAAA==.Thehatred:BAAALgADCgYJBgAAAA==.Therondar:BAAALgADCgEJAQAAAA==.Thirdleggedg:BAAALgAECgIJAgAAAA==.Thiyan:BAAALgADCgMJAwAAAA==.Tholin:BAAALgAECggJDwAAAA==.Thromar:BAABLgAECn8VAAIFAAcJiBWvgADPAQAFAAcJiBWvgADPAQAAAA==.Thunderlily:BAABLgAECn8qAAMFAAkJWBs9NwA8AgAFAAkJCxs9NwA8AgAoAAcJchfpBgCgAQAAAA==.Thünder:BAAALgADCgcJBwABLgAECgcJFgALAKQeAA==.',
Ti='Tinderbeef:BAAALgADCgcJCAAAAA==.Tinychaos:BAAALgAECgkJCQAAAA==.Tinyround:BAAALgAECgEJAQAAAA==.Tinytotem:BAAALgADCgQJBAAAAA==.Tirra:BAABLgAECn8fAAMVAAkJlR9NDwCiAgAVAAkJlR9NDwCiAgAJAAIJJgbXaAFNAAAAAA==.',
To='Topeka:BAAALgAECgQJBAABLgAECgkJJAAIAKgNAA==.Torama:BAAALgADCgIJAgAAAA==.Toranth:BAABLgAECn81AAIVAAkJiRXlGQA3AgAVAAkJiRXlGQA3AgAAAA==.Torq:BAABLgAECn8XAAIFAAYJ/BmShwDCAQAFAAYJ/BmShwDCAQABLgAECgcJFwAVAIghAA==.Torqumada:BAAALgAECgkJBgAAAA==.Torvik:BAAALgAECgEJAQAAAA==.Toxian:BAABLgAECn8uAAIYAAgJVBbpQgC/AQAYAAgJVBbpQgC/AQAAAA==.Toxicelitist:BAABLgAECn8rAAMQAAkJ4w4KDAB+AQAQAAkJ4w4KDAB+AQACAAEJmgF2ZQEaAAAAAA==.',
Tr='Treedemon:BAACLgAFFH8MAAIYAAQJwhm6OABCAQAYAAQJwhm6OABCAQAuAAQKfyoAAhgACQksJH8KAPYCABgACQksJH8KAPYCAAAA.Treedin:BAAALgAECgMJAwAAAA==.Trollboi:BAAALgADCggJCAAAAA==.Trymw:BAAALgADCgIJAgAAAA==.Tryst:BAAALgADCgcJBwAAAA==.',
Ty='Tybearon:BAAALgAECgQJBAAAAA==.Tyinthus:BAAALgAECgcJBwABLgAECgcJBwARAAAAAA==.Tyreid:BAAALgAECgcJBwAAAA==.Tyrelitha:BAAALgAECgQJEQAAAA==.',
Ud='Udderchoad:BAAALgADCgEJAQAAAA==.',
Uh='Uhura:BAAALgAECgEJAQAAAA==.',
Ul='Ulfrir:BAACLgAFFH8UAAIIAAQJ2RtELwBRAQAIAAQJ2RtELwBRAQAuAAQKfyYAAwgACQk3INIRAMMCAAgACQk3INIRAMMCACAAAwkxCipvAIIAAAAA.Ultradukes:BAAALgAECgMJBAAAAA==.',
Un='Unatural:BAAALgAECgUJBQAAAA==.Unleashed:BAAALgAECgUJCgAAAA==.',
Va='Valarea:BAAALgADCgEJAQAAAA==.Valock:BAABLgAECn8VAAMQAAkJNAUIHwCyAAAQAAcJHAUIHwCyAAACAAQJYgS6GQA2AAAAAA==.Vandham:BAAALgADCgEJAQAAAA==.Vannis:BAAALgAECgcJBwAAAA==.Vanshifty:BAACLgAFFH8UAAIKAAMJWBnVCQDeAAAKAAMJWBnVCQDeAAAuAAQKf0QAAgoACQk0I0sFAGQDAAoACQk0I0sFAGQDAAAA.',
Ve='Veilf:BAAALgADCgYJDAAAAA==.Velf:BAAALgAECgIJAgAAAA==.Velrus:BAAALgAECgYJDAAAAA==.Venli:BAAALgAECgMJAwAAAA==.Venombite:BAAALgADCgMJAwAAAA==.Venomlord:BAAALgADCgQJBAAAAA==.Verez:BAAALgAECgEJAgAAAA==.',
Vi='Victorion:BAAALgAECggJCQAAAA==.Viktorax:BAAALgAECgYJDgAAAA==.Vincevega:BAAALgAECgkJDgAAAA==.Virtueozo:BAABLgAECn8aAAImAAgJEBfODwA+AgAmAAgJEBfODwA+AgAAAA==.',
Vo='Volam:BAAALgAECgQJBAAAAA==.',
Vy='Vyx:BAAALgAECgkJEwAAAA==.',
Wa='Waffle:BAABLgAECn8ZAAIIAAYJihUrggA6AQAIAAYJihUrggA6AQABLgAECggJGgAIAFEOAA==.Waldhorn:BAAALgAECgcJCwABLgAECgkJMwAFAK4iAA==.Wangji:BAAALgAECgQJBAAAAA==.Wangwen:BAAALgADCgIJAgAAAA==.Wargue:BAABLgAECn8VAAIbAAYJjRugOADEAQAbAAYJjRugOADEAQAAAA==.',
We='Weeaboos:BAAALgADCgIJAgABLgADCgQJBAARAAAAAA==.Weebsz:BAAALgADCgQJBAAAAA==.Welindis:BAABLgAECn8ZAAIJAAcJ5wr4xAABAQAJAAcJ5wr4xAABAQABLgAECgkJMAAYAPgQAA==.Wetkith:BAAALgADCgUJBQAAAA==.',
Wi='Windrider:BAAALgADCgIJAgAAAA==.Windwraith:BAAALgAECgIJAgAAAA==.Wizzard:BAAALgAECggJHAAAAQ==.',
Xa='Xaiyara:BAAALgADCgUJBQAAAA==.Xalina:BAAALgAECgEJAQAAAA==.Xandaka:BAAALgADCgQJBAAAAA==.',
Xe='Xephir:BAAALgAECggJCwAAAA==.',
Xi='Xidied:BAACLgAFFH8LAAMHAAQJSSFMFQB3AQAHAAQJSSFMFQB3AQAGAAEJNwbBEgA3AAAuAAQKfzAAAgcACQkmIfYFAN4CAAcACQkmIfYFAN4CAAAA.Xilon:BAAALgAECgcJDwABLgAFFAQJDAALAHcfAA==.Xilra:BAABLgAECn8vAAMfAAkJmiJ7CwCcAgAfAAkJmiJ7CwCcAgAnAAEJmhHqUgAzAAABLgAFFAQJDAALAHcfAA==.Xilrot:BAABLgAFFH8MAAILAAQJdx/CGQAHAQALAAQJdx/CGQAHAQAAAA==.Xilzen:BAAALgAECgUJEQABLgAFFAQJDAALAHcfAA==.Xinia:BAAALgAECgMJAwAAAA==.',
Xz='Xzed:BAAALgADCgEJAQAAAA==.',
Ye='Yew:BAAALgADCgMJAwAAAA==.',
Yi='Yikers:BAACLgAFFH8RAAIVAAQJZiAwGgBPAQAVAAQJZiAwGgBPAQAuAAQKfyUAAhUACQm6IXIJAPQCABUACQm6IXIJAPQCAAAA.',
Yr='Yridai:BAAALgAECgYJCAAAAA==.',
Za='Zani:BAAALgADCgYJBwAAAA==.Zarsher:BAAALgADCgIJAgAAAA==.',
Zd='Zdk:BAAALgAECgEJAQABLgAECgkJMAAIAP0fAA==.',
Ze='Zeldy:BAABLgAECn8vAAIIAAkJJxfTMgARAgAIAAkJJxfTMgARAgAAAA==.Zenestraza:BAAALgADCgcJCwABLgAECgkJOgAYAKkeAA==.Zennitsu:BAAALgAFFAEJAQAAAA==.Zenthareal:BAABLgAECn86AAMYAAkJqR4aAgC4AQAYAAkJPx4aAgC4AQAaAAQJQxdCAQApAQAAAA==.Zenzi:BAAALgADCgcJDwAAAA==.Zenzz:BAAALgADCgYJCAAAAA==.Zeuc:BAAALgADCgMJAwAAAA==.Zeuus:BAAALgADCgMJBAAAAA==.',
Zh='Zhirldk:BAAALgAECgcJEQAAAA==.Zhulgarosh:BAAALgADCgUJBQAAAA==.',
Zi='Zillidan:BAAALgAECgEJAwABLgAECgkJMAAIAP0fAA==.',
Zm='Zmaster:BAABLgAECn8wAAIIAAkJ/R9HFQCpAgAIAAkJ/R9HFQCpAgAAAA==.',
Zo='Zobeast:BAAALgADCgQJBAAAAA==.',
Zr='Zret:BAAALgAECgcJDwABLgAECgkJMAAIAP0fAA==.',
Zw='Zwar:BAAALgAECgEJAQABLgAECgkJMAAIAP0fAA==.',
Zy='Zynith:BAAALgAECgYJBgAAAA==.',
['Zö']='Zöey:BAAALgADCgQJBQAAAA==.',
['Åp']='Åpex:BAAALgAECggJBgAAAA==.',
['Çl']='Çloudz:BAAALgADCgMJAwAAAA==.',
['Ða']='Ðark:BAACLgAFFH8WAAIIAAMJFB/jTQAQAQAIAAMJFB/jTQAQAQAuAAQKfycAAggACQm5HAQVAI8CAAgACQm5HAQVAI8CAAAA.',
['Ðr']='Ðr:BAABLgAECn8eAAMNAAkJ/Br1IgANAgANAAcJThr1IgANAgAOAAYJ7xfONQBjAQAAAA==.',
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
