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

local lookup = {'Warlock-Affliction','Warlock-Demonology','Paladin-Protection','Monk-Mistweaver','Mage-Frost','Monk-Windwalker','Monk-Brewmaster','Hunter-BeastMastery','Unknown-Unknown','Paladin-Retribution','Druid-Restoration','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Restoration','Shaman-Elemental','DemonHunter-Havoc','Warlock-Destruction','Priest-Holy','Priest-Shadow','Priest-Discipline','Paladin-Holy','Warrior-Protection','Hunter-Survival','DemonHunter-Devourer','Shaman-Enhancement','DemonHunter-Vengeance','Warrior-Fury','Warrior-Arms','Evoker-Augmentation','Evoker-Devastation','Hunter-Marksmanship','Druid-Balance','Rogue-Outlaw','Rogue-Subtlety','Mage-Fire','Rogue-Assassination','Evoker-Preservation','Druid-Feral','DeathKnight-Blood','Mage-Arcane',}
local provider = {region='US',realm='Dawnbringer',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abdalhazred:BAACLgAFFH8bAAMBAAUJUiOKAgB6AQABAAUJUiOKAgB6AQACAAEJiR/uuQBMAAAuAAQKfzgAAwEACQmYJFIAAGYDAAEACAm3JVIAAGYDAAIAAwnQHT6qAO4AAAAA.Abilus:BAABLgAECn8UAAIDAAQJvxbeIgD6AAADAAQJvxbeIgD6AAAAAA==.Abolis:BAAALgAECgMJBgAAAA==.',
Ae='Aeldriel:BAAALgAECgMJAwAAAA==.Aeoyn:BAAALgAECgEJAQAAAA==.',
Ag='Aggar:BAAALgADCgkJEwABLgAECgkJSAAEADMaAA==.',
Ak='Akoa:BAAALgAECgEJAQAAAA==.',
Al='Alarak:BAABLgAECn8bAAIBAAgJcRVsCQCtAQABAAgJcRVsCQCtAQAAAA==.Alerion:BAAALgAECgEJAQAAAA==.Alnara:BAAALgAECgEJAgAAAA==.Aloxys:BAAALgADCgcJCQAAAA==.Alvierearn:BAABLgAECn8WAAIFAAgJuxH7jwBUAQAFAAgJuxH7jwBUAQAAAA==.',
Am='Amoradis:BAAALgADCgUJEgAAAA==.',
An='Anaeir:BAAALgADCgYJBgAAAA==.Angriff:BAAALgADCgQJBQAAAA==.Anisette:BAABLgAECn8pAAMGAAkJnRfUEQAyAgAGAAkJnRfUEQAyAgAHAAQJDgqkZwB2AAAAAA==.Annuket:BAAALgAECgYJBgAAAA==.Anthria:BAAALgADCgkJGwAAAA==.',
Ap='Apexpredåtor:BAAALgADCgIJAgAAAA==.',
Aq='Aqurala:BAABLgAECn8jAAIIAAkJXRx2IQBbAgAIAAkJXRx2IQBbAgAAAA==.',
Ar='Aradem:BAAALgADCgcJBwABLgAFFAMJAwAJAAAAAA==.Aravenn:BAAALgAFFAMJAwAAAA==.Arcis:BAABLgAECn8kAAIKAAcJ0RJxkABOAQAKAAcJ0RJxkABOAQAAAA==.Ardeniro:BAAALgAECgIJBAAAAA==.Arealis:BAAALgADCgcJDAAAAA==.Argatem:BAAALgAECgQJBAABLgAECggJKgALAEYeAA==.Arkangel:BAACLgAFFH8IAAIMAAQJIQ2EiwDvAAAMAAQJIQ2EiwDvAAAuAAQKfyoAAwwACQk7HLAlAGsCAAwACQk7HLAlAGsCAA0AAQlhCT47AC0AAAAA.Arke:BAAALgAECgMJAwAAAA==.Arkharon:BAAALgADCgYJCQAAAA==.Arralyon:BAAALgADCgMJBgAAAA==.Artemesia:BAAALgAECgYJBwABLgAFFAYJLQAOAKgfAA==.Arthäs:BAAALgAECgQJBAAAAA==.Aryrn:BAAALgADCgUJBQAAAA==.',
As='Asakua:BAAALgAECgMJBgAAAA==.Asiya:BAAALgAECgQJBQAAAA==.Assandra:BAAALgADCgUJBQAAAA==.Astræa:BAAALgAECgYJBgAAAA==.',
At='Athul:BAAALgADCgUJCgAAAA==.',
Au='Aurlyn:BAAALgADCgcJDwAAAA==.',
Av='Avatartele:BAAALgAECgIJAwAAAA==.Avatartouka:BAABLgAECn8jAAMOAAgJ5yEmEQDCAgAOAAgJ5yEmEQDCAgAPAAQJ9RMebACgAAAAAA==.Avianthel:BAAALgADCgMJAgAAAA==.Avraria:BAABLgAECn8aAAIQAAkJphWvEAAbAgAQAAkJphWvEAAbAgAAAA==.Avyl:BAABLgAECn8bAAQBAAYJ+xFaFQAcAQABAAYJ1hBaFQAcAQARAAQJNhFSHADBAAACAAIJpgZvHwExAAAAAA==.Avylastorica:BAAALgADCgYJBgABLgAECgYJGwABAPsRAA==.',
Aw='Awsomninja:BAABLgAECn8kAAIHAAkJAiN0BQDmAgAHAAkJAiN0BQDmAgAAAA==.',
Ax='Axxain:BAAALgADCgkJGgAAAA==.',
Az='Azaralle:BAAALgADCgEJAQAAAA==.Azeazal:BAAALgAECgcJEwAAAA==.Azlifan:BAAALgADCgQJBAAAAA==.Azorthragal:BAAALgADCgYJBgABLgAECgUJBwAJAAAAAA==.',
Ba='Baddlandss:BAAALgAECgQJCAAAAA==.Bagador:BAAALgAECgYJCQAAAA==.Bastais:BAAALgAECgEJAQAAAA==.Batozai:BAAALgADCgEJAQAAAA==.Baumstack:BAAALgADCgUJBQAAAA==.',
Bd='Bdibz:BAAALgADCgcJDAAAAA==.',
Be='Beautifulluv:BAABLgAECn8sAAQSAAkJSyLrBAAtAwASAAkJSyLrBAAtAwATAAYJzA0fRAD8AAAUAAEJkAzNUwA6AAAAAA==.Beelzabubba:BAAALgAECgkJAwAAAA==.Beewaregobs:BAAALgAECgIJAgAAAA==.Bekabeka:BAACLgAFFH8cAAIVAAUJSiIXDQDaAQAVAAUJSiIXDQDaAQAuAAQKf00ABBUACQk+JDMFAD4DABUACQk+JDMFAD4DAAoABQm5CJIAAbMAAAMABQmOBnI3AH4AAAAA.Belfour:BAAALgAECgEJAgAAAA==.Bera:BAAALgAECgUJDwABLgAECgkJAgAJAAAAAA==.Beramage:BAAALgAECgEJAQAAAA==.',
Bi='Billybobjr:BAACLgAFFH8HAAIOAAMJgCKVLAAoAQAOAAMJgCKVLAAoAQAuAAQKf0kAAw4ACQnrIaQGAEMDAA4ACQnrIaQGAEMDAA8AAQkhEDSjADEAAAAA.Bippitybop:BAAALgAECgEJAQAAAA==.',
Bl='Blackbart:BAAALgADCgcJCgAAAA==.',
Bo='Boamere:BAABLgAECn8/AAIWAAkJoxzXBgCYAgAWAAkJoxzXBgCYAgAAAA==.Botemedel:BAAALgADCgEJAQAAAA==.',
Br='Braided:BAAALgAECgIJAwAAAA==.Brakkar:BAABLgAECn9IAAIXAAkJUhaxDQBMAgAXAAkJUhaxDQBMAgAAAA==.Brandish:BAAALgADCgcJBwAAAA==.Breadstick:BAABLgAECn83AAILAAkJmyUTAQDQAwALAAkJmyUTAQDQAwAAAA==.Brevik:BAAALgADCgMJAwAAAA==.Brutaal:BAAALgADCgcJCwAAAA==.Brynhild:BAAALgAFFAIJAwAAAA==.Brütaal:BAABLgAECn8hAAMOAAcJphfLNADaAQAOAAcJphfLNADaAQAPAAQJ7wbGfQBxAAAAAA==.',
Bu='Bubsydogo:BAABLgAECn8aAAIPAAkJPRRiHQDzAQAPAAkJPRRiHQDzAQAAAA==.Buddytheelf:BAABLgAECn8yAAMCAAkJFSS/BABCAwACAAkJuCO/BABCAwARAAIJiyX5KwBkAAAAAA==.Bumpyflea:BAAALgADCgUJBQAAAA==.',
Ca='Cairnsilvers:BAAALgADCgEJAQAAAA==.Camus:BAABLgAECn8aAAIKAAgJHBpzTQDdAQAKAAgJHBpzTQDdAQAAAA==.Capped:BAAALgADCgMJAwAAAA==.Catgirl:BAAALgAECgYJCAAAAA==.',
Ce='Cebollin:BAAALgAECgUJCAAAAA==.Celaian:BAAALgAECgUJCgABLgAFFAEJAQAJAAAAAA==.Celamor:BAAALgAECgQJBwAAAA==.Celasmine:BAAALgADCgYJCAAAAA==.Celpanda:BAAALgAFFAEJAQAAAA==.',
Ch='Chamoan:BAAALgAECgMJAwAAAA==.Charlamayne:BAAALgADCgcJBwAAAA==.Charybdia:BAABLgAECn8nAAIYAAkJngeLbwBAAQAYAAkJngeLbwBAAQAAAA==.Chidõri:BAACLgAFFH8XAAIPAAUJzB+sGABNAQAPAAUJzB+sGABNAQAuAAQKfy4AAw8ACQmDI0kFAEMDAA8ACQmDI0kFAEMDABkAAgnPFuUlAHkAAAAA.Chimerå:BAAALgADCgEJAQAAAA==.Chopstix:BAAALgADCgcJDgAAAA==.Chudlock:BAAALgAECgYJEgAAAA==.Chunni:BAABLgAECn8hAAIGAAkJHAoSLgBPAQAGAAkJHAoSLgBPAQAAAA==.',
Ci='Cilicia:BAAALgADCgUJBQAAAA==.',
Co='Codap:BAAALgADCgcJBwAAAA==.Coffees:BAAALgAECgEJAgAAAA==.Coolerfrieza:BAAALgAECgUJCwAAAA==.',
Cp='Cpr:BAABLgAECn8XAAIVAAcJiCGvDwCXAgAVAAcJiCGvDwCXAgAAAA==.',
Cr='Crayonman:BAAALgAECgMJAwABLgAFFAQJBwAXANghAA==.Crepic:BAAALgAECgQJBAAAAA==.Cruelkitty:BAABLgAECn8gAAMQAAgJIAVTQgCoAAAQAAYJzgZTQgCoAAAaAAgJMgFZIQCOAAAAAA==.',
Cu='Cubanwarlock:BAAALgAECgIJAgAAAA==.Cudibandit:BAAALgADCgcJDwAAAA==.Cullodena:BAAALgAECgEJAQAAAA==.',
Cy='Cynaria:BAAALgAECgEJAwABLgAFFAIJBgALADobAA==.Cyralai:BAACLgAFFH82AAILAAgJQRcyBgCcAgALAAgJQRcyBgCcAgAuAAQKfxkAAgsACQlQIfEQALACAAsACQlQIfEQALACAAAA.',
Da='Dabofdeath:BAAALgAECgIJAgAAAA==.Dalov:BAABLgAECn8gAAMVAAcJSSbxBwDvAgAVAAcJSSbxBwDvAgAKAAIJbx0qGgGWAAAAAA==.Dankley:BAABLgAECn8WAAIbAAgJYQdLSwAYAQAbAAgJYQdLSwAYAQAAAA==.Darkestnyte:BAAALgAECggJDwAAAA==.Darkk:BAAALgAECgQJDQAAAA==.Darkpalidin:BAAALgAECgYJBgABLgAECggJKAAFAD4bAA==.Darkrhaenies:BAAALgADCgcJBwAAAA==.Darkwindx:BAAALgADCggJCQABLgAECgYJEgAJAAAAAA==.Datezero:BAAALgADCgQJBAAAAA==.',
Dd='Ddream:BAAALgADCgQJBAAAAA==.',
De='Deadhealer:BAAALgADCgMJBQAAAA==.Deafknighte:BAAALgAECgMJAwAAAA==.Deathboi:BAABLgAECn8xAAIMAAkJwxtwGwCgAgAMAAkJwxtwGwCgAgAAAA==.Deathburgur:BAABLgAECn8gAAMMAAkJfxVGNwAfAgAMAAkJfxVGNwAfAgANAAcJpQt0FAA1AQAAAA==.Deathfromme:BAAALgAECgYJCgAAAA==.Deathstro:BAAALgAECgYJDgABLgAFFAQJCAAMACENAA==.Decayed:BAAALgAECgUJDgAAAA==.Demonicuss:BAAALgAECgEJAQAAAA==.Demontress:BAAALgADCgQJBAAAAA==.Dentridios:BAAALgADCgIJAgAAAA==.Deson:BAABLgAECn8mAAMVAAkJCRJvLQCmAQAVAAkJCRJvLQCmAQAKAAUJiQjGBgGsAAAAAA==.Deviantart:BAAALgAECgQJBAAAAA==.',
Di='Diana:BAABLgAECn8kAAIIAAkJqA0hSQDBAQAIAAkJqA0hSQDBAQAAAA==.Diietriich:BAABLgAECn8zAAIFAAkJriLWDAAQAwAFAAkJriLWDAAQAwAAAA==.Dilligaaf:BAAALgADCgMJAwAAAA==.',
Do='Docbeanz:BAAALgADCgMJAwAAAA==.Donkypunch:BAAALgADCgQJBAAAAA==.Dontjudgemê:BAAALgADCgIJAgAAAA==.Doodlekhal:BAAALgADCgMJAwAAAA==.Dopie:BAAALgADCgIJAgAAAA==.Dorcina:BAAALgAECgIJAgAAAA==.',
Dr='Dracthyr:BAAALgADCgUJDQAAAA==.Dragonwarrio:BAAALgAECgEJAQAAAA==.Dragoondpain:BAAALgAECgQJCwAAAQ==.Drakai:BAAALgAECgEJAgAAAA==.Draltina:BAABLgAECn8XAAMBAAgJPAmkDQBaAQABAAgJPAmkDQBaAQACAAEJywLtLwEhAAAAAA==.Drazira:BAABLgAECn8gAAIYAAkJsgSWkwD1AAAYAAkJsgSWkwD1AAAAAA==.Drugonwerier:BAAALgADCgEJAgAAAA==.Drunkbera:BAAALgAECgcJBwAAAA==.Druzzlek:BAAALgAECgEJAQAAAA==.',
Du='Dubalpally:BAAALgADCggJCAAAAA==.Dunks:BAABLgAFFH8FAAICAAMJJwM+jACmAAACAAMJJwM+jACmAAAAAA==.Duskfu:BAABLgAECn8tAAIGAAkJnR+HCgCYAgAGAAkJnR+HCgCYAgAAAA==.',
Dy='Dylghoul:BAAALgADCgUJBQAAAA==.',
['Dí']='Dírac:BAABLgAFFH8GAAICAAMJTw2QegDJAAACAAMJTw2QegDJAAABLgAFFAQJCQAOAGkcAA==.',
Ec='Eclipsekitty:BAAALgAECgUJBgABLgAFFAQJCQAVAOIQAA==.',
Ed='Edwillei:BAAALgAECgUJCAAAAA==.',
Ef='Efforex:BAAALgADCgQJBAAAAA==.',
Ei='Einhar:BAAALgAECgEJAQAAAA==.',
El='Elactoplasm:BAAALgAECgMJAwAAAA==.Elderslapaho:BAAALgADCgUJBgAAAA==.Ellistrae:BAAALgAECgYJCQAAAA==.Ellysia:BAAALgADCgEJAQAAAA==.',
Em='Emmel:BAAALgADCggJCwAAAA==.',
Eq='Equeslucis:BAAALgAECgcJBwAAAA==.',
Er='Erodrana:BAAALgAECgYJEgABLgAECgkJIAAYALIEAA==.Eromir:BAAALgAECgUJCgAAAA==.Eryi:BAABLgAECn9IAAIEAAkJMxpvDwCnAgAEAAkJMxpvDwCnAgAAAA==.',
Et='Ethan:BAABLgAECn8eAAMcAAkJnRuIEQDZAQAcAAcJIRiIEQDZAQAbAAQJ6CIpVQD2AAAAAA==.',
Ev='Evonari:BAAALgADCgIJAgAAAA==.',
Ex='Exoticfrost:BAAALgADCgIJAgAAAA==.Expertnewb:BAAALgAECgIJAgABLgAECggJKAAFAD4bAA==.',
['Eí']='Eísheth:BAAALgADCgUJBAAAAA==.',
Fa='Faegen:BAAALgAECgEJAgAAAA==.Falkønn:BAAALgAECgMJAwAAAA==.Fangytooth:BAACLgAFFH8HAAIXAAQJ2CHOBwCOAQAXAAQJ2CHOBwCOAQAuAAQKfy4AAhcACQl5JNsCABMDABcACQl5JNsCABMDAAAA.Fashaun:BAAALgAECgIJAgAAAA==.Faze:BAABLgAECn8aAAIFAAYJyx8eYQC6AQAFAAYJyx8eYQC6AQAAAA==.',
Fe='Fellamayyne:BAAALgADCgEJAQAAAA==.Ferrus:BAACLgAFFH8kAAMYAAgJPiLLCQBvAgAYAAgJPiLLCQBvAgAQAAQJsxzdGgDDAAAuAAQKfx4AAxAACQn1JdANAIYCABgACQlWJOwcAKQCABAABwncJNANAIYCAAAA.',
Ff='Ffleuderflam:BAAALgAECgYJBgAAAA==.',
Fl='Floors:BAAALgAECgEJAQAAAA==.',
Fr='Frose:BAAALgADCgEJAQAAAA==.Frostyblast:BAAALgADCgUJBgAAAA==.',
Fu='Fupacabra:BAAALgADCgEJAQAAAA==.Furiiosa:BAAALgAECgUJBQAAAA==.Furiosity:BAAALgAECgMJBQAAAA==.Fuzzybear:BAAALgAECgcJCAABLgAFFAQJBwAXANghAA==.Fuzzybeard:BAAALgAECgYJBgABLgAFFAQJBwAXANghAA==.Fuzzyspells:BAAALgAECgEJAQABLgAFFAQJBwAXANghAA==.Fuzzywar:BAAALgAECgYJBwABLgAFFAQJBwAXANghAA==.',
['Fõ']='Fõrtress:BAAALgAECgMJBAAAAA==.',
Ga='Gabomonk:BAABLgAFFH8FAAIHAAIJ1iQTNgDKAAAHAAIJ1iQTNgDKAAAAAA==.Galvandra:BAABLgAECn8dAAMVAAkJGiQPAgCPAwAVAAkJGiQPAgCPAwAKAAIJCR6UFQGbAAAAAA==.Gamalia:BAAALgADCgUJBQAAAA==.Garudekhan:BAAALgADCgUJBQAAAA==.',
Ge='Genreallee:BAABLgAECn8dAAIKAAcJ1hKAigBZAQAKAAcJ1hKAigBZAQAAAA==.Gernab:BAAALgADCgYJBgAAAA==.',
Gh='Ghost:BAABLgAECn8WAAILAAYJ9xt+NgDOAQALAAYJ9xt+NgDOAQAAAA==.',
Gi='Gizzar:BAAALgADCgYJCgAAAA==.',
Gl='Glau:BAAALgAECgQJBAABLgAECggJCQAJAAAAAA==.Glimpsed:BAAALgAECgcJDgABLgAECgkJAgAJAAAAAA==.Globgore:BAAALgADCgIJBAAAAA==.Gloçk:BAAALgAECgMJCAABLgAECgYJEQAJAAAAAA==.',
Go='Goofy:BAABLgAECn8fAAIKAAcJYCHDJACUAgAKAAcJYCHDJACUAgAAAA==.Goor:BAAALgAECgEJAQAAAA==.Gorrik:BAAALgADCgUJBQAAAA==.',
Gr='Graeae:BAAALgAECgcJCAAAAA==.Greyfeather:BAAALgADCgEJAgAAAA==.Grimeace:BAAALgADCgQJBAAAAA==.',
Gu='Gunduin:BAACLgAFFH8FAAIIAAIJ/hbveQCaAAAIAAIJ/hbveQCaAAAuAAQKfx4AAggACAmuIBQeAFECAAgACAmuIBQeAFECAAAA.',
Gw='Gweb:BAAALgAECgIJAgAAAA==.',
Gy='Gyda:BAABLgAECn8nAAIUAAcJ9CEwDACpAgAUAAcJ9CEwDACpAgAAAA==.Gyuyuki:BAABLgAECn9HAAIPAAkJ4hb2FQA0AgAPAAkJ4hb2FQA0AgAAAA==.',
Ha='Hakuanah:BAAALgADCgEJAQAAAA==.Halvorak:BAAALgADCgcJCgAAAA==.Harryp:BAACLgAFFH8KAAIdAAQJ7gxFOQDeAAAdAAQJ7gxFOQDeAAAuAAQKfzYAAx4ACQm5GN8GANcBAB0ACQnlElkdAOsBAB4ACQlDFd8GANcBAAAA.Hast:BAAALgAECgYJEwAAAA==.',
He='Hearthzilla:BAAALgAECgEJAQABLgAECgkJIQAPANgfAA==.Heidie:BAAALgAECgUJCgAAAA==.Hellsbow:BAAALgAECgYJDgAAAA==.Hermin:BAAALgADCgQJCAAAAA==.',
Ho='Holyhellz:BAAALgADCgEJAQAAAA==.Honeyboo:BAAALgAECgUJBQABLgAFFAQJCQALADMNAA==.Hots:BAAALgADCgcJBwAAAA==.Hotzz:BAAALgAECgEJAQAAAA==.',
Hr='Hraesvelgr:BAAALgADCggJBwAAAA==.',
Hu='Huntavious:BAACLgAFFH8IAAIXAAQJGxScEQA3AQAXAAQJGxScEQA3AQAuAAQKfzQABBcACQk8HzcFANQCABcACQk8HzcFANQCAAgABgnjGsZeAEsBAB8AAQnIE9uKADAAAAAA.',
['Hë']='Hëllen:BAABLgAECn8YAAIKAAYJMiDaaQCrAQAKAAYJMiDaaQCrAQAAAA==.',
['Hú']='Húñtrèss:BAAALgAECgUJBwAAAA==.',
Ia='Iamshinigamy:BAAALgAECgIJAgABLgAECgcJFwAFAPMaAA==.',
Ii='Iichimaru:BAAALgAECgUJBQAAAA==.',
Il='Illidupe:BAAALgADCgMJAwAAAA==.',
In='Inaoh:BAAALgAECgQJBwAAAA==.Insaniac:BAAALgAECgQJBAAAAA==.',
Ir='Ironboss:BAAALgAECgYJCQAAAA==.',
Iv='Ivey:BAABLgAECn8qAAILAAgJRh6TFACjAgALAAgJRh6TFACjAgAAAA==.',
Iz='Izes:BAAALgAECgEJAgAAAA==.',
Ja='Jaagganug:BAAALgAECgcJBwAAAA==.Jacenne:BAABLgAECn8bAAIgAAcJlAP1XgCXAAAgAAcJlAP1XgCXAAAAAA==.Jairus:BAAALgAECgcJBwAAAA==.',
Jd='Jdirty:BAABLgAECn8YAAIhAAYJhAl9EgDgAAAhAAYJhAl9EgDgAAAAAA==.',
Je='Jellytime:BAAALgAECgMJBQAAAA==.',
Jo='Josephyn:BAAALgAECgcJCgABLgAFFAYJLQAOAKgfAA==.',
Ju='Jugernaut:BAAALgAECgEJAQAAAA==.Jumpmann:BAAALgAECgMJAwAAAA==.Justdesserts:BAAALgAECgEJAQAAAA==.Justix:BAAALgADCggJEwAAAA==.',
Ka='Kadaffy:BAAALgAECgIJAwAAAA==.Kakota:BAAALgADCgQJBAABLgAECgkJGgAPAA4dAA==.Kakusu:BAAALgAECgYJEQAAAA==.Kakuta:BAAALgAECgUJDwABLgAECgkJGgAPAA4dAA==.Kakutá:BAABLgAECn8aAAIPAAkJDh1IDACdAgAPAAkJDh1IDACdAgAAAA==.Kalru:BAAALgAECgIJAgAAAA==.Kargar:BAAALgAECgEJAgAAAA==.Karliah:BAAALgAECgIJAgAAAA==.Katharsis:BAACLgAFFH8RAAIKAAQJlw90SAAXAQAKAAQJlw90SAAXAQAuAAQKfyEAAgoACQnPFoJEAPYBAAoACQnPFoJEAPYBAAAA.',
Ke='Keba:BAAALgAECgEJAQABLgAFFAUJHAAVAEoiAA==.Keit:BAAALgADCgYJBgABLgAFFAQJCQAQAPkeAA==.',
Kh='Khalidisi:BAACLgAFFH8FAAQDAAMJyxyJBwD/AAADAAMJyxyJBwD/AAAKAAEJEAuovQA7AAAVAAEJoxUfRwA6AAAuAAQKfzAABAMACQnsH6AGAHcCAAMACAmxH6AGAHcCABUACQktGVouAKEBAAoACQnIDYdmAKABAAAA.Khaliesi:BAAALgADCgIJAgAAAA==.Khalizar:BAABLgAFFH8MAAIbAAQJPgiHKgAEAQAbAAQJPgiHKgAEAQAAAA==.Kharazim:BAAALgADCgEJAQABLgAECgkJMAAYALkbAA==.Khenja:BAAALgAECgEJAQAAAA==.Khál:BAAALgADCgYJBgAAAA==.',
Ki='Killerelf:BAABLgAECn8YAAIKAAgJiwfDqwAjAQAKAAgJiwfDqwAjAQAAAA==.Kittie:BAAALgADCggJCAAAAA==.',
Kk='Kkiilleerr:BAAALgAECgYJDwAAAA==.',
Ko='Kobbaltcilar:BAAALgAECgUJBgAAAA==.Koraleena:BAAALgAECgQJBAAAAA==.Korbo:BAABLgAECn8sAAMOAAkJMBtQNQDYAQAOAAcJKBhQNQDYAQAPAAUJeR5vKgCaAQAAAA==.Korbulo:BAABLgAECn8UAAIFAAkJmwnbdQCKAQAFAAkJmwnbdQCKAQAAAA==.Korlothel:BAABLgAECn8kAAIDAAkJvAeTIAAMAQADAAkJvAeTIAAMAQABLgAFFAMJAwAJAAAAAA==.Korrith:BAAALgADCgIJAgAAAA==.',
Kr='Krumpus:BAABLgAECn8iAAIYAAkJRRRbLwAGAgAYAAkJRRRbLwAGAgAAAA==.Kryma:BAAALgAECgcJBwAAAA==.',
Ku='Kungfuuy:BAABLgAECn8lAAIHAAkJPCGMBAD5AgAHAAkJPCGMBAD5AgAAAA==.Kurtevade:BAAALgAECgQJDAAAAA==.',
Kw='Kwetnepthl:BAAALgAECgEJAgAAAA==.',
Ky='Kynsong:BAABLgAECn8gAAISAAkJ5xNFFgAcAgASAAkJ5xNFFgAcAgAAAA==.',
['Kà']='Kàlbrews:BAABLgAECn9AAAIHAAkJvyZLAACHAwAHAAkJvyZLAACHAwAAAA==.Kàrmâ:BAAALgAECgUJBQAAAA==.',
['Kî']='Kîrah:BAAALgAFFAIJAgAAAA==.',
La='Lagk:BAAALgADCgkJJQAAAA==.Lainiee:BAAALgADCgEJAQAAAA==.Lavismad:BAECLgAFFH8JAAIbAAQJuiDPDgCJAQAbAAQJuiDPDgCJAQAuAAQKfzQABBsACQkMJWgEAB0DABsACQnYJGgEAB0DABYABwmhIEwPAPABABwAAQlGJXcyAGkAAAAA.Lavoc:BAEALgADCgcJBwABLgAFFAQJCQAbALogAA==.Lavv:BAEALgAECgYJCAABLgAFFAQJCQAbALogAA==.Lavz:BAEALgAECgYJBgABLgAFFAQJCQAbALogAA==.',
Le='Legendary:BAAALgAECgYJDQAAAA==.Leshah:BAAALgAECgYJCwAAAA==.',
Li='Lichkingdied:BAAALgADCgUJBQAAAA==.Lightndpain:BAAALgAECgQJBgABLgAECgQJCwAJAAAAAA==.Lildh:BAAALgAECgUJCQAAAA==.Lilypetal:BAAALgAECgQJBwAAAA==.Lionaest:BAAALgAECgMJAwAAAA==.Littlebucket:BAAALgADCgEJAQAAAA==.',
Lo='Lockdpain:BAAALgAECgYJGAABLgAECgQJCwAJAAAAAQ==.Logov:BAAALgAECgYJDwAAAA==.Loraine:BAAALgAECgEJAQAAAA==.Loìsbethe:BAAALgAECgYJCgAAAA==.',
Lu='Luciferra:BAABLgAFFH8IAAISAAUJ9A7yEQA3AQASAAUJ9A7yEQA3AQABLgAFFAYJLQAOAKgfAA==.Lukey:BAAALgAECgMJAwAAAA==.Lunartemis:BAAALgAECgUJCAABLgAFFAUJDwAiACchAA==.Luu:BAAALgAECgMJBwAAAA==.',
Ly='Lyza:BAAALgADCgYJCQAAAA==.',
['Lö']='Lörax:BAAALgADCgQJBQAAAA==.',
['Lû']='Lûnafreya:BAAALgAECggJEgAAAA==.',
Ma='Maelera:BAAALgADCgkJDAAAAA==.Maetromundo:BAAALgAECgEJAQAAAA==.Maevan:BAAALgADCgEJAQAAAA==.Magentas:BAAALgADCgIJAgAAAA==.Magickul:BAAALgADCggJCAAAAA==.Mahlah:BAAALgAECgQJBAAAAA==.Malaboo:BAAALgAECgEJAQABLgAFFAQJCQALADMNAA==.Malabooty:BAAALgAECgYJBwABLgAFFAQJCQALADMNAA==.Maletsy:BAAALgAECgEJAQABLgAFFAIJBQAIAP4WAA==.Maliboo:BAACLgAFFH8JAAILAAQJMw3YNQDQAAALAAQJMw3YNQDQAAAuAAQKfzkAAwsACQlEIpcEAHADAAsACQlEIpcEAHADACAAAgmfCXqLADIAAAAA.Maxamus:BAABLgAECn8aAAQcAAYJwiGUEgDMAQAcAAYJwiGUEgDMAQAWAAUJzBhrKADsAAAbAAEJgxc5kwBHAAAAAA==.Maxigooner:BAABLgAFFH8FAAIYAAMJKRaVXADSAAAYAAMJKRaVXADSAAABLgAFFAUJIgAKAFwmAA==.',
Mc='Mcflurry:BAAALgAECgUJCwAAAA==.',
Me='Medarisa:BAAALgAECgcJDQAAAA==.Medavia:BAAALgADCgUJBQAAAA==.Mederia:BAAALgAECgUJBQAAAA==.Medívh:BAAALgADCgEJAQAAAA==.Melisandr:BAAALgAECgMJBQAAAA==.Merkenier:BAABLgAECn8wAAIgAAgJ2RNvIQC5AQAgAAgJ2RNvIQC5AQAAAA==.Merkshamalot:BAAALgAECgEJAQABLgAECggJMAAgANkTAA==.Merkur:BAAALgAECgYJEwABLgAECggJMAAgANkTAA==.Merkurry:BAAALgAECgEJAQABLgAECggJMAAgANkTAA==.',
Mi='Midnitehunt:BAAALgAECgQJBAAAAA==.Miragia:BAAALgAECgYJEgAAAA==.Missmayhem:BAAALgAECgUJCAAAAA==.Missmayhemm:BAAALgADCgQJBgAAAA==.',
Mo='Modifiedmix:BAABLgAECn8sAAIIAAgJfxm5KgAuAgAIAAgJfxm5KgAuAgAAAA==.Modsabadtank:BAAALgAECgYJCwABLgAECggJLAAIAH8ZAA==.Mokomohama:BAAALgAECgcJBwAAAA==.Monatazumaa:BAAALgAECgEJAgAAAA==.Moonbloom:BAAALgAFFAEJAQABLgAFFAYJLQAOAKgfAA==.Mopeezie:BAAALgAECgEJAQAAAA==.Mordicant:BAAALgADCgEJAQABLgAECgYJDQAJAAAAAA==.Morella:BAABLgAECn81AAIRAAcJmQ4HGQCDAQARAAcJmQ4HGQCDAQAAAA==.',
Mu='Mucduck:BAAALgADCgEJAQAAAA==.Mustakrakish:BAAALgAECgEJAQAAAA==.Mustaz:BAAALgAECgkJBQAAAA==.',
My='Mym:BAAALgADCgcJBAAAAA==.Mystics:BAAALgAECgUJBgAAAA==.Mythrunduil:BAAALgADCgEJAQAAAA==.',
['Må']='Mågi:BAAALgAECgcJBwAAAA==.',
['Mé']='Médb:BAABLgAECn8wAAMFAAkJdx4lGADGAgAFAAkJDB4lGADGAgAjAAMJFR1iCQDmAAAAAA==.',
Na='Naste:BAAALgAECgUJBQAAAA==.Nathrold:BAAALgAECgIJBAABLgAECgYJEQAJAAAAAA==.',
Ne='Necrobon:BAAALgAECgUJBQAAAA==.Necrognome:BAAALgAECgIJAgAAAA==.Neptune:BAACLgAFFH8tAAIOAAYJqB94DgDuAQAOAAYJqB94DgDuAQAuAAQKfyEAAw4ACQlRIhgHAAIDAA4ACQlRIhgHAAIDAA8ABwkkDtE0AIQBAAAA.Nerfdks:BAAALgAECgkJEgAAAA==.Nerfpaladins:BAABLgAECn8kAAQDAAcJpRJBJADvAAAKAAYJthGRtwASAQADAAcJJBFBJADvAAAVAAMJzARQdQBhAAAAAA==.Nerfpriests:BAAALgAECgQJBQAAAA==.Neruess:BAAALgADCgUJBQAAAA==.Nezzuko:BAAALgAECgcJBwAAAA==.',
Ni='Nightbird:BAABLgAECn8dAAMiAAcJvBcHKwA8AQAiAAcJThcHKwA8AQAkAAYJ8BWfDgAsAQABLgAECggJCQAJAAAAAA==.Ninediewatt:BAAALgAECgQJCAAAAA==.Nivella:BAAALgAECgYJCgAAAA==.Nixaana:BAAALgAECgUJBgAAAA==.Niçki:BAAALgADCgMJAwAAAA==.',
No='Notlockz:BAAALgADCgIJAgAAAA==.Novah:BAAALgADCgQJBQAAAA==.Noydb:BAAALgAECgEJAQABLgAECgkJPwAWAKMcAA==.',
Nu='Nuah:BAAALgADCgYJDQAAAA==.',
Ny='Nyxsia:BAEALgAFFAEJAQABLgAFFAcJIgAbAJAdAA==.',
['Nå']='Nåmi:BAAALgAECgYJBgAAAA==.',
['Nè']='Nèo:BAAALgADCgcJBwAAAA==.',
Ob='Obayi:BAABLgAECn85AAIIAAcJThD4cABZAQAIAAcJThD4cABZAQAAAA==.Obsaedia:BAAALgAECgcJBwABLgAECggJHAAJAAAAAQ==.',
Od='Odinsgrace:BAAALgAECgEJAQAAAA==.',
Og='Ogmadmonk:BAACLgAFFH8MAAIQAAMJnRLYGQDLAAAQAAMJnRLYGQDLAAAuAAQKfzEAAhAACQmUIdEIAJsCABAACQmUIdEIAJsCAAAA.',
Ok='Oktobra:BAABLgAECn8bAAIKAAYJIwM/GQGXAAAKAAYJIwM/GQGXAAAAAA==.',
On='Onetrickpony:BAAALgAECgIJAgAAAA==.Onos:BAAALgAECgIJAgAAAA==.Onosm:BAAALgAECgQJBAAAAA==.',
Or='Orangevoker:BAAALgAECgcJCwABLgAECgkJIQAPANgfAA==.Ordin:BAAALgAECgEJAQAAAA==.Orioan:BAAALgAECgUJCQAAAA==.Orux:BAAALgAECgYJBgAAAA==.',
Os='Osenya:BAAALgAECgYJBgABLgAFFAQJCQAMAGMfAA==.Osun:BAAALgAECgQJBAAAAA==.',
Ou='Ouroboro:BAAALgADCgUJBQAAAA==.',
Ow='Owlbat:BAAALgAECgEJAQAAAA==.',
Pa='Padremort:BAAALgADCgYJBgAAAA==.Palantyr:BAABLgAECn9fAAIPAAgJvRqZGgA+AgAPAAgJvRqZGgA+AgAAAA==.Paly:BAAALgAECgEJAQAAAA==.Para:BAAALgAECgQJBAAAAA==.Patrician:BAABLgAECn8sAAIhAAkJdhdgBAA8AgAhAAkJdhdgBAA8AgAAAA==.',
Pe='Penutbutter:BAAALgAECgQJBwAAAA==.Pepegasus:BAAALgADCgcJBwAAAA==.',
Ph='Phobos:BAAALgADCgQJCAAAAA==.Phyloren:BAAALgADCgUJBgAAAA==.',
Pi='Pigsticker:BAAALgAECgQJBQAAAA==.Pixyfire:BAAALgAECgYJCgABLgAFFAQJCQAVAOIQAA==.',
Po='Poisonleaf:BAAALgAECgUJBgABLgAECgYJGAAKADIgAA==.Pokingharder:BAABLgAECn8iAAIkAAkJHBbJBAA9AgAkAAkJHBbJBAA9AgABLgAFFAMJCgABAA0WAA==.',
Pu='Pulcherrimus:BAAALgAECgEJAwAAAA==.Purgeem:BAAALgADCgUJBQAAAA==.Pushpop:BAAALgAECgYJDwABLgAECggJXwAPAL0aAA==.',
Pw='Pwiest:BAAALgADCgcJEAAAAA==.',
Qu='Quetzalcoatl:BAABLgAECn8cAAIlAAkJsRmUBwB5AgAlAAkJsRmUBwB5AgAAAA==.',
Ra='Raambox:BAAALgAECgQJBAAAAA==.Radak:BAAALgAECgEJAQAAAA==.Raddish:BAABLgAECn8bAAISAAYJ+RCGPgDxAAASAAYJ+RCGPgDxAAAAAA==.Rahjlynn:BAAALgADCgcJCAAAAA==.Rahken:BAAALgAECgcJBwAAAA==.Raiinn:BAAALgADCgUJBQAAAA==.Raylee:BAACLgAFFH8JAAMBAAQJBRzQAwBPAQABAAQJQhXQAwBPAQARAAIJ4xtzEQCnAAAuAAQKfz4ABAIACQmeIUMUAKoCAAIACAmxH0MUAKoCABEABwl8IQ8IAEQCAAEAAwk2Gl8ZAPAAAAAA.Razuki:BAACLgAFFH8JAAIVAAQJ4hCvJgDmAAAVAAQJ4hCvJgDmAAAuAAQKfzQAAxUACQmLIlwFADsDABUACQmLIlwFADsDAAoABwn2F81wAIoBAAAA.',
Re='Remyl:BAAALgADCggJCAAAAA==.Reynia:BAAALgAECgEJAQAAAA==.',
Rf='Rfd:BAAALgADCgcJBwABLgAECggJGQAPAMUSAA==.',
Rh='Rhaenies:BAAALgAECgYJEAAAAA==.Rharr:BAAALgADCgkJDAAAAA==.Rhovanion:BAAALgAECgUJCQAAAA==.Rhuac:BAABLgAECn8pAAILAAkJeRPeKQADAgALAAkJeRPeKQADAgAAAA==.',
Ri='Risakah:BAAALgAECggJCQAAAA==.',
Ro='Rorschach:BAAALgAECgcJCgAAAA==.Rosefist:BAEALgADCgcJCAABLgAFFAcJEQAUAAMRAA==.Rosemourne:BAEALgAECgIJAgABLgAFFAcJEQAUAAMRAA==.Roseykat:BAABLgAECn8oAAIIAAkJkAosWwCPAQAIAAkJkAosWwCPAQAAAA==.Roshwyn:BAABLgAECn8UAAIIAAgJHgvCbgBfAQAIAAgJHgvCbgBfAQAAAA==.Rottedmeat:BAAALgAECgcJCgAAAA==.',
Ru='Rubmytotems:BAAALgAECgYJBgAAAA==.Ruckus:BAABLgAECn8nAAIKAAgJuRYPPwApAgAKAAgJuRYPPwApAgAAAA==.',
Sa='Saberwar:BAAALgAECgEJAQABLgAECgMJAwAJAAAAAA==.Saintfury:BAAALgAECgQJBQAAAA==.Saintsfear:BAABLgAECn8qAAIbAAkJWQ+NJQDKAQAbAAkJWQ+NJQDKAQAAAA==.Samest:BAAALgADCgkJCQAAAA==.Sanchito:BAAALgADCgMJAwAAAA==.Saphalia:BAAALgADCgMJAwAAAA==.Saradomin:BAAALgADCgUJBAAAAA==.Sareenastar:BAACLgAFFH8JAAISAAQJoyAiDQByAQASAAQJoyAiDQByAQAuAAQKfy4AAxIACQmUJnAAAOADABIACQmUJnAAAOADABMAAQnfCe6HAC8AAAAA.Sasae:BAABLgAECn8eAAIHAAcJVxXoHwClAQAHAAcJVxXoHwClAQAAAA==.',
Sc='Scorias:BAAALgADCgQJAwAAAA==.',
Se='Selisztraza:BAAALgADCgEJAQAAAA==.Sephiróth:BAAALgADCgUJCAAAAA==.Sereni:BAAALgADCgQJBAAAAA==.Serenity:BAAALgAECgcJEgAAAA==.Serenitynow:BAAALgAECgEJAgAAAA==.Sewald:BAAALgAECgcJDwAAAA==.',
Sh='Shadowzbane:BAAALgAECgIJAgAAAA==.Shahasha:BAAALgADCgEJAQAAAA==.Shaidarharan:BAAALgADCgIJAgAAAA==.Shakeybop:BAAALgAECgQJBAAAAA==.Shalen:BAABLgAECn8sAAQdAAkJCBQqHwDdAQAdAAkJ/BMqHwDdAQAeAAYJoQ2ZHQBCAQAlAAYJ7g1mGwAjAQAAAA==.Sharker:BAAALgADCgYJBgAAAA==.Sharkyb:BAAALgAECgEJAgABLgAECgkJNwAMAKsiAA==.Sharpie:BAAALgADCgcJCgAAAA==.Sheer:BAABLgAECn8aAAMHAAgJYB/GDgBLAgAHAAgJYB/GDgBLAgAEAAYJkyFuGgA/AgAAAA==.Sheraa:BAABLgAECn8lAAIDAAkJeBI7EAC9AQADAAkJeBI7EAC9AQAAAA==.Shiftystrike:BAABLgAECn8WAAImAAcJPx/wCgAVAgAmAAcJPx/wCgAVAgAAAA==.Shifushield:BAAALgAECgcJCAAAAA==.Shireshannon:BAABLgAECn8VAAIIAAYJegmhnwD8AAAIAAYJegmhnwD8AAAAAA==.Shrike:BAAALgAECgIJAwABLgAFFAcJGgATALAaAA==.Shrunkador:BAACLgAFFH8RAAIPAAQJMg3dKQDoAAAPAAQJMg3dKQDoAAAuAAQKfzMAAg8ACQm6HUgQAG4CAA8ACQm6HUgQAG4CAAAA.',
Si='Silk:BAAALgAECgYJDgAAAA==.Silmarkthree:BAACLgAFFH8JAAIFAAQJnBMjWQA2AQAFAAQJnBMjWQA2AQAuAAQKfzQAAgUACQmkGCE5ADECAAUACQmkGCE5ADECAAAA.Sinbåd:BAAALgAECgcJCAAAAA==.Siodar:BAAALgADCgEJAQABLgAECgUJBwAJAAAAAA==.Sisterstar:BAAALgADCgMJAwAAAA==.',
Sl='Sleety:BAAALgAECgIJBQAAAA==.Slipknoth:BAACLgAFFH8iAAMTAAgJzxpsBQAeAgATAAcJeh1sBQAeAgAUAAYJ3g1TFwCuAQAuAAQKfywABBMACQnlIjIRAE0CABMACAkHJTIRAE0CABIABwntF/kgANsBABQABAnOGUJFAPAAAAAA.',
Sn='Snekhain:BAAALgADCgMJAwAAAA==.Snuffaluffa:BAAALgAECgMJAwAAAA==.',
So='Somatra:BAAALgADCgkJCQAAAA==.Sorean:BAACLgAFFH8WAAIXAAUJNx5ACgByAQAXAAUJNx5ACgByAQAuAAQKfy8ABAgACQm+IFYhAD0CAAgABwlUG1YhAD0CABcABwlnHWQZANQBAB8ABwlQGv0vALUBAAAA.',
Sp='Specialmove:BAAALgAFFAEJAgAAAA==.Spookydookie:BAAALgADCgkJCgAAAA==.',
St='Staghealz:BAAALgAECgIJAgAAAA==.Stifs:BAABLgAECn8oAAIDAAgJGxbOFQB0AQADAAgJGxbOFQB0AQAAAA==.Stilleena:BAAALgAECgYJBgAAAA==.Stinkinglily:BAAALgAECgEJAgAAAA==.Strunrage:BAAALgAECgcJDAABLgAECgkJQgAKAI4kAA==.Stÿx:BAABLgAECn8ZAAInAAYJ6gWRPwCOAAAnAAYJ6gWRPwCOAAABLgAECgkJEwAJAAAAAA==.',
Su='Sugarbomb:BAAALgADCgYJCgAAAA==.',
Sy='Sykotyk:BAAALgAECgkJDwAAAA==.Sylverfox:BAAALgAECgMJAwABLgAECgkJHwAVAJUfAA==.Synchestra:BAAALgADCgcJCgAAAA==.',
Ta='Tadagain:BAABLgAECn8gAAMKAAYJlhIcqQAnAQAKAAYJlhIcqQAnAQAVAAQJ2gV2dgChAAAAAA==.Tagrith:BAAALgADCgMJAwAAAA==.Tankybears:BAACLgAFFH8GAAILAAIJOhscQwChAAALAAIJOhscQwChAAAuAAQKfywAAyAACQnOGugQAFICACAACQnOGugQAFICAAsACAnqGzJTAEABAAAA.Tarmalok:BAAALgAECgEJAQAAAA==.Tazera:BAAALgAECgUJCwAAAA==.',
Te='Telekinesis:BAABLgAECn8iAAIXAAgJvhAjIACbAQAXAAgJvhAjIACbAQAAAA==.Tenara:BAABLgAFFH8GAAIOAAQJORQrOgDyAAAOAAQJORQrOgDyAAABLgAFFAIJBgALADobAA==.Tenbinza:BAAALgAECgUJBwAAAA==.Teos:BAACLgAFFH8FAAIZAAMJSQmIEAC3AAAZAAMJSQmIEAC3AAAuAAQKfzgAAhkACQmwGc4HAEgCABkACQmwGc4HAEgCAAAA.',
Th='Thadude:BAAALgAECgcJBwABLgAFFAQJDQAnAMoUAA==.Thainé:BAAALgAECgMJBgAAAA==.Thaldrassian:BAAALgADCgQJBAAAAA==.Tharris:BAAALgAECgYJCwAAAA==.Thehatred:BAAALgADCgYJBgAAAA==.Therondar:BAAALgADCgEJAQAAAA==.Thiyan:BAAALgADCgMJAwAAAA==.Tholin:BAAALgAECggJDgAAAA==.Thromar:BAABLgAECn8VAAIFAAcJiBWvgADPAQAFAAcJiBWvgADPAQAAAA==.Thunderlily:BAABLgAECn8oAAMFAAgJPhtuNgA8AgAFAAgJeRpuNgA8AgAoAAcJchfpBgCgAQAAAA==.Thünder:BAAALgADCgcJBwABLgAECgcJFgAMAKQeAA==.',
Ti='Tinderbeef:BAAALgADCgcJCAAAAA==.Tinychaos:BAAALgAECgkJCQAAAA==.Tinyround:BAAALgAECgEJAQAAAA==.Tirra:BAABLgAECn8fAAMVAAkJlR/tDgClAgAVAAkJlR/tDgClAgAKAAIJJgYHYwFNAAAAAA==.',
To='Topeka:BAAALgAECgQJBAABLgAECgkJJAAIAKgNAA==.Torama:BAAALgADCgIJAgAAAA==.Toranth:BAABLgAECn81AAIVAAkJiRWOGQA4AgAVAAkJiRWOGQA4AgAAAA==.Torq:BAABLgAECn8XAAIFAAYJ/BmShwDCAQAFAAYJ/BmShwDCAQABLgAECgcJFwAVAIghAA==.Torqumada:BAAALgAECgkJBgAAAA==.Toxian:BAABLgAECn8tAAIYAAgJzxUSQgC/AQAYAAgJzxUSQgC/AQAAAA==.Toxicelitist:BAABLgAECn8rAAMRAAkJ4w68CwB/AQARAAkJ4w68CwB/AQACAAEJmgG+YAEaAAAAAA==.',
Tr='Treedemon:BAACLgAFFH8JAAIYAAQJExkWNgBEAQAYAAQJExkWNgBEAQAuAAQKfyoAAhgACQksJEUKAPYCABgACQksJEUKAPYCAAAA.Treedin:BAAALgAECgMJAwAAAA==.Trollboi:BAAALgADCggJCAAAAA==.Trymw:BAAALgADCgIJAgAAAA==.Tryst:BAAALgADCgcJBwAAAA==.',
Ty='Tybearon:BAAALgAECgEJAQAAAA==.Tyinthus:BAAALgAECgcJBwABLgAECgcJBwAJAAAAAA==.Tyreid:BAAALgAECgcJBwAAAA==.Tyrelitha:BAAALgAECgQJCgAAAA==.',
Ud='Udderchoad:BAAALgADCgEJAQAAAA==.',
Uh='Uhura:BAAALgAECgEJAQAAAA==.',
Ul='Ulfrir:BAACLgAFFH8SAAIIAAQJ2RvyKwBTAQAIAAQJ2RvyKwBTAQAuAAQKfyYAAwgACQk3IDgRAMQCAAgACQk3IDgRAMQCAB8AAwkxCipvAIIAAAAA.Ultradukes:BAAALgAECgMJBAAAAA==.',
Un='Unatural:BAAALgAECgUJBQAAAA==.Unleashed:BAAALgAECgUJCgAAAA==.',
Va='Valarea:BAAALgADCgEJAQAAAA==.Valock:BAAALgAECgkJEwAAAA==.Vandham:BAAALgADCgEJAQAAAA==.Vannis:BAAALgAECgcJBwAAAA==.Vanshifty:BAACLgAFFH8OAAILAAMJCxlFMwDbAAALAAMJCxlFMwDbAAAuAAQKf0QAAgsACQk0IxwFAGQDAAsACQk0IxwFAGQDAAAA.',
Ve='Veilf:BAAALgADCgYJDAAAAA==.Velf:BAAALgAECgIJAgAAAA==.Velrus:BAAALgAECgYJDAAAAA==.Venli:BAAALgAECgMJAwAAAA==.Venombite:BAAALgADCgMJAwAAAA==.Verez:BAAALgAECgEJAgAAAA==.',
Vi='Victorion:BAAALgAECggJCQAAAA==.Viktorax:BAAALgAECgYJDgAAAA==.Vincevega:BAAALgAECgkJDgAAAA==.Virtueozo:BAABLgAECn8aAAIlAAgJEBfODwA+AgAlAAgJEBfODwA+AgAAAA==.',
Vo='Volam:BAAALgAECgQJBAAAAA==.',
Vy='Vyx:BAAALgAECgkJEwAAAA==.',
Wa='Waffle:BAABLgAECn8YAAIIAAYJihV5fwA7AQAIAAYJihV5fwA7AQABLgAECggJGgAIAFEOAA==.Waldhorn:BAAALgAECgcJCwAAAA==.Wangji:BAAALgAECgQJBAAAAA==.Wangwen:BAAALgADCgIJAgAAAA==.Wargue:BAABLgAECn8VAAIbAAYJjRugOADEAQAbAAYJjRugOADEAQAAAA==.',
We='Weeaboos:BAAALgADCgIJAgABLgADCgQJBAAJAAAAAA==.Weebsz:BAAALgADCgQJBAAAAA==.Welindis:BAABLgAECn8YAAIKAAcJOwgswQAEAQAKAAcJOwgswQAEAQABLgAECgkJMAAYAPgQAA==.Wetkith:BAAALgADCgUJBQAAAA==.',
Wi='Windrider:BAAALgADCgIJAgAAAA==.Windwraith:BAAALgAECgIJAgAAAA==.Wizzard:BAAALgAECggJHAAAAQ==.',
Xa='Xaiyara:BAAALgADCgUJBQAAAA==.Xalina:BAAALgAECgEJAQAAAA==.Xandaka:BAAALgADCgQJBAAAAA==.',
Xe='Xephir:BAAALgAECggJCgAAAA==.',
Xi='Xidied:BAACLgAFFH8HAAIHAAQJ3CAtFAB6AQAHAAQJ3CAtFAB6AQAuAAQKfzAAAgcACQkmIcoFAN8CAAcACQkmIcoFAN8CAAAA.Xilon:BAAALgAECgcJDwABLgAFFAQJCQAMAGMfAA==.Xilra:BAABLgAECn8vAAMgAAkJmiJaCwCcAgAgAAkJmiJaCwCcAgAmAAEJmhFqUAAzAAABLgAFFAQJCQAMAGMfAA==.Xilrot:BAABLgAFFH8JAAIMAAQJYx/oRQBiAQAMAAQJYx/oRQBiAQAAAA==.Xilzen:BAAALgAECgUJEQABLgAFFAQJCQAMAGMfAA==.Xinia:BAAALgAECgMJAwAAAA==.',
Xz='Xzed:BAAALgADCgEJAQAAAA==.',
Ye='Yew:BAAALgADCgMJAwAAAA==.',
Yi='Yikers:BAACLgAFFH8RAAIVAAQJZiBOGQBQAQAVAAQJZiBOGQBQAQAuAAQKfyUAAhUACQm6IToJAPUCABUACQm6IToJAPUCAAAA.',
Yr='Yridai:BAAALgAECgYJCAAAAA==.',
Za='Zani:BAAALgADCgYJBwAAAA==.Zarsher:BAAALgADCgIJAgAAAA==.',
Zd='Zdk:BAAALgAECgEJAQABLgAECgkJKgAIAJQdAA==.',
Ze='Zeldy:BAABLgAECn8vAAIIAAkJJxeYMQASAgAIAAkJJxeYMQASAgAAAA==.Zenestraza:BAAALgADCgcJCwABLgAECgkJMAAYALkbAA==.Zennitsu:BAAALgAECgkJCAAAAA==.Zenthareal:BAABLgAECn8wAAIYAAkJuRu5FACaAgAYAAkJuRu5FACaAgAAAA==.Zenzi:BAAALgADCgUJCAAAAA==.Zenzz:BAAALgADCgEJAgAAAA==.Zeuc:BAAALgADCgMJAwAAAA==.Zeuus:BAAALgADCgMJBAAAAA==.',
Zh='Zhirldk:BAAALgAECgcJEQAAAA==.Zhulgarosh:BAAALgADCgUJBQAAAA==.',
Zi='Zillidan:BAAALgAECgEJAwABLgAECgkJKgAIAJQdAA==.',
Zm='Zmaster:BAABLgAECn8qAAIIAAkJlB2KFACqAgAIAAkJlB2KFACqAgAAAA==.',
Zo='Zobeast:BAAALgADCgQJBAAAAA==.',
Zr='Zret:BAAALgAECgYJCgABLgAECgkJKgAIAJQdAA==.',
Zw='Zwar:BAAALgAECgEJAQABLgAECgkJKgAIAJQdAA==.',
Zy='Zynith:BAAALgAECgYJBgAAAA==.',
['Zö']='Zöey:BAAALgADCgQJBQAAAA==.',
['Åp']='Åpex:BAAALgAECggJBgAAAA==.',
['Çl']='Çloudz:BAAALgADCgMJAwAAAA==.',
['Ða']='Ðark:BAACLgAFFH8RAAIIAAMJDhJnGACmAAAIAAMJDhJnGACmAAAuAAQKfycAAggACQm5HAQVAI8CAAgACQm5HAQVAI8CAAAA.',
['Ðr']='Ðr:BAABLgAECn8eAAMOAAkJ/Br1IgANAgAOAAcJThr1IgANAgAPAAYJ7xfXNABkAQAAAA==.',
['ßl']='ßlack:BAAALgADCgEJAQAAAA==.',
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
