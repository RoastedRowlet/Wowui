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
local provider = {region='US',realm='Dawnbringer',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abdalhazred:BAACLgAFFH8bAAMBAAUJUiMHAgCEAQABAAUJUiMHAgCEAQACAAEJiR+8sABQAAAuAAQKfzgAAwEACQmYJFIAAGYDAAEACAm3JVIAAGYDAAIAAwnQHa6mAO4AAAAA.Abilus:BAABLgAECn8UAAIDAAQJvxaKIQD7AAADAAQJvxaKIQD7AAAAAA==.Abolis:BAAALgAECgMJBgAAAA==.',
Ae='Aeldriel:BAAALgAECgMJAwAAAA==.Aeoyn:BAAALgAECgEJAQAAAA==.',
Ag='Aggar:BAAALgADCgkJEwABLgAECgkJQAAEAPIXAA==.',
Ak='Akoa:BAAALgAECgEJAQAAAA==.',
Al='Alarak:BAABLgAECn8bAAIBAAgJcRVsCQCtAQABAAgJcRVsCQCtAQAAAA==.Alerion:BAAALgAECgEJAQAAAA==.Alnara:BAAALgAECgEJAgAAAA==.Alvierearn:BAABLgAECn8WAAIFAAgJuxF9igBcAQAFAAgJuxF9igBcAQAAAA==.',
Am='Amoradis:BAAALgADCgUJEgAAAA==.',
An='Anaeir:BAAALgADCgYJBgAAAA==.Angriff:BAAALgADCgQJBQAAAA==.Anisette:BAABLgAECn8mAAMGAAgJdRnjFQD8AQAGAAgJdRnjFQD8AQAHAAQJDgrQZAB5AAAAAA==.Annuket:BAAALgAECgYJBgAAAA==.Anthria:BAAALgADCgkJGwAAAA==.',
Ap='Apexpredåtor:BAAALgADCgIJAgAAAA==.',
Aq='Aqurala:BAABLgAECn8jAAIIAAkJXRwTHwBhAgAIAAkJXRwTHwBhAgAAAA==.',
Ar='Aradem:BAAALgADCgcJBwABLgAFFAMJAwAJAAAAAA==.Aravenn:BAAALgAFFAMJAwAAAA==.Arcis:BAABLgAECn8kAAIKAAcJ0RI9iwBPAQAKAAcJ0RI9iwBPAQAAAA==.Ardeniro:BAAALgAECgIJBAAAAA==.Arealis:BAAALgADCgcJDAAAAA==.Argatem:BAAALgAECgQJBAABLgAECggJKgALAEYeAA==.Arkangel:BAACLgAFFH8IAAIMAAQJIQ0NgAD0AAAMAAQJIQ0NgAD0AAAuAAQKfyoAAwwACQk7HF8jAHACAAwACQk7HF8jAHACAA0AAQlhCUE3AC4AAAAA.Arke:BAAALgAECgMJAwAAAA==.Arkharon:BAAALgADCgYJCQAAAA==.Arralyon:BAAALgADCgMJBgAAAA==.Artemesia:BAAALgAECgYJBwABLgAFFAYJLQAOAKgfAA==.Arthäs:BAAALgAECgQJBAAAAA==.Aryrn:BAAALgADCgUJBQAAAA==.',
As='Asakua:BAAALgAECgMJBgAAAA==.Asiya:BAAALgAECgQJBQAAAA==.Assandra:BAAALgADCgUJBQAAAA==.Astræa:BAAALgAECgYJBgAAAA==.',
At='Athul:BAAALgADCgUJCgAAAA==.',
Au='Aurlyn:BAAALgADCgcJDwAAAA==.',
Av='Avatartele:BAAALgAECgIJAwAAAA==.Avatartouka:BAABLgAECn8jAAMOAAgJ5yEdEADEAgAOAAgJ5yEdEADEAgAPAAQJ9ROUZwCgAAAAAA==.Avianthel:BAAALgADCgMJAgAAAA==.Avraria:BAABLgAECn8aAAIQAAkJphWNDwAdAgAQAAkJphWNDwAdAgAAAA==.Avyl:BAABLgAECn8bAAQBAAYJ+xEKFAAdAQABAAYJ1hAKFAAdAQARAAQJNhHaGgDEAAACAAIJpgZvHwExAAAAAA==.Avylastorica:BAAALgADCgYJBgABLgAECgYJGwABAPsRAA==.',
Aw='Awsomninja:BAABLgAECn8kAAIHAAkJAiMiBQDpAgAHAAkJAiMiBQDpAgAAAA==.',
Ax='Axxain:BAAALgADCgkJGgAAAA==.',
Az='Azaralle:BAAALgADCgEJAQAAAA==.Azeazal:BAAALgAECgcJEgAAAA==.Azlifan:BAAALgADCgQJBAAAAA==.Azorthragal:BAAALgADCgYJBgABLgAECgMJAwAJAAAAAA==.',
Ba='Baddlandss:BAAALgAECgQJCAAAAA==.Bagador:BAAALgAECgYJCQAAAA==.Bastais:BAAALgAECgEJAQAAAA==.Batozai:BAAALgADCgEJAQAAAA==.Baumstack:BAAALgADCgUJBQAAAA==.',
Bd='Bdibz:BAAALgADCgcJDAAAAA==.',
Be='Beautifulluv:BAABLgAECn8sAAQSAAkJSyKMBAAwAwASAAkJSyKMBAAwAwATAAYJzA3hQAAEAQAUAAEJkAzNUwA6AAAAAA==.Beelzabubba:BAAALgAECgkJAwAAAA==.Bekabeka:BAACLgAFFH8cAAIVAAUJSiIMDADkAQAVAAUJSiIMDADkAQAuAAQKf00ABBUACQk+JMMEAEEDABUACQk+JMMEAEEDAAoABQm5CPb3ALMAAAMABQmOBmQ1AH4AAAAA.Belfour:BAAALgAECgEJAgAAAA==.Bera:BAAALgAECgUJDwABLgAECgkJAgAJAAAAAA==.Beramage:BAAALgAECgEJAQAAAA==.',
Bi='Billybobjr:BAACLgAFFH8FAAIOAAIJDSKRRADEAAAOAAIJDSKRRADEAAAuAAQKf0YAAw4ACAkEIyILAPoCAA4ACAkEIyILAPoCAA8AAQkhEMabADEAAAAA.Bippitybop:BAAALgAECgEJAQAAAA==.',
Bl='Blackbart:BAAALgADCgcJCgAAAA==.',
Bo='Boamere:BAABLgAECn83AAIWAAkJrBs4BwCFAgAWAAkJrBs4BwCFAgAAAA==.Botemedel:BAAALgADCgEJAQAAAA==.',
Br='Braided:BAAALgAECgIJAwAAAA==.Brakkar:BAABLgAECn9HAAIXAAkJUhYLDQBQAgAXAAkJUhYLDQBQAgAAAA==.Brandish:BAAALgADCgcJBwAAAA==.Breadstick:BAABLgAECn80AAILAAgJyiQiBgBOAwALAAgJyiQiBgBOAwAAAA==.Brevik:BAAALgADCgMJAwAAAA==.Brutaal:BAAALgADCgcJCwAAAA==.Brynhild:BAAALgAFFAIJAwAAAA==.Brütaal:BAABLgAECn8hAAMOAAcJpheHMgDbAQAOAAcJpheHMgDbAQAPAAQJ7wZ8eABxAAAAAA==.',
Bu='Bubsydogo:BAABLgAECn8aAAIPAAkJPRTuGwD1AQAPAAkJPRTuGwD1AQAAAA==.Buddytheelf:BAABLgAECn8sAAMCAAkJrCNjDgDTAgACAAcJZyNjDgDTAgARAAIJiyUzKgBlAAAAAA==.Bumpyflea:BAAALgADCgUJBQAAAA==.',
Ca='Cairnsilvers:BAAALgADCgEJAQAAAA==.Camus:BAABLgAECn8aAAIKAAgJHBrGSQDeAQAKAAgJHBrGSQDeAQAAAA==.Capped:BAAALgADCgMJAwAAAA==.Catgirl:BAAALgAECgYJCAAAAA==.',
Ce='Cebollin:BAAALgAECgUJCAAAAA==.Celaian:BAAALgAECgUJCgABLgAFFAEJAQAJAAAAAA==.Celamor:BAAALgAECgQJBwAAAA==.Celasmine:BAAALgADCgYJCAAAAA==.Celpanda:BAAALgAFFAEJAQAAAA==.',
Ch='Chamoan:BAAALgAECgMJAwAAAA==.Charlamayne:BAAALgADCgcJBwAAAA==.Charybdia:BAABLgAECn8kAAIYAAgJbgatlQDoAAAYAAgJbgatlQDoAAAAAA==.Chidõri:BAACLgAFFH8XAAIPAAUJzB+aFQBYAQAPAAUJzB+aFQBYAQAuAAQKfy4AAw8ACQmDI0kFAEMDAA8ACQmDI0kFAEMDABkAAgnPFuUlAHkAAAAA.Chimerå:BAAALgADCgEJAQAAAA==.Chopstix:BAAALgADCgcJBwAAAA==.Chudlock:BAAALgAECgYJEgAAAA==.Chunna:BAABLgAECn8tAAIGAAkJnR/fCQCbAgAGAAkJnR/fCQCbAgAAAA==.Chunni:BAABLgAECn8hAAIGAAkJHArAKwBSAQAGAAkJHArAKwBSAQAAAA==.',
Ci='Cilicia:BAAALgADCgUJBQAAAA==.',
Co='Codap:BAAALgADCgcJBwAAAA==.Coolerfrieza:BAAALgAECgUJCwAAAA==.',
Cp='Cpr:BAABLgAECn8XAAIVAAcJiCGvDwCXAgAVAAcJiCGvDwCXAgAAAA==.',
Cr='Crayonman:BAAALgAECgMJAwABLgAFFAQJBwAXANghAA==.Crepic:BAAALgAECgQJBAAAAA==.Cruelkitty:BAABLgAECn8gAAMQAAgJIAXgPgCoAAAQAAYJzgbgPgCoAAAaAAgJMgHlHwCOAAAAAA==.',
Cu='Cudibandit:BAAALgADCgcJDwAAAA==.',
Cy='Cynaria:BAAALgAECgEJAwABLgAFFAIJBQALADobAA==.Cyralai:BAACLgAFFH80AAILAAgJQRflBACqAgALAAgJQRflBACqAgAuAAQKfxkAAgsACQlQIfEQALACAAsACQlQIfEQALACAAAA.',
Da='Dabofdeath:BAAALgAECgIJAgAAAA==.Dalov:BAABLgAECn8gAAMVAAcJSSbxBwDvAgAVAAcJSSbxBwDvAgAKAAIJbx0DEAGWAAAAAA==.Dankley:BAABLgAECn8WAAIbAAgJYQd3SAAaAQAbAAgJYQd3SAAaAQAAAA==.Darkestnyte:BAAALgAECggJDwAAAA==.Darkk:BAAALgAECgQJDAAAAA==.Darkpalidin:BAAALgAECgYJBgABLgAECggJKAAFAD4bAA==.Darkrhaenies:BAAALgADCgcJBwAAAA==.Darkwindx:BAAALgADCggJCQABLgAECgUJDQAJAAAAAA==.Datezero:BAAALgADCgQJBAAAAA==.',
Dd='Ddream:BAAALgADCgQJBAAAAA==.',
De='Deadhealer:BAAALgADCgMJBQAAAA==.Deafknighte:BAAALgAECgMJAwAAAA==.Deathboi:BAABLgAECn8xAAIMAAkJwxuDGQClAgAMAAkJwxuDGQClAgAAAA==.Deathburgur:BAABLgAECn8YAAMMAAkJqg83bwB+AQAMAAgJehA3bwB+AQANAAcJpQvsEgA6AQAAAA==.Deathfromme:BAAALgAECgYJCgAAAA==.Deathstro:BAAALgAECgYJDgABLgAFFAQJCAAMACENAA==.Decayed:BAAALgAECgUJDgAAAA==.Demonicuss:BAAALgAECgEJAQAAAA==.Demontress:BAAALgADCgQJBAAAAA==.Dentridios:BAAALgADCgIJAgAAAA==.Deson:BAABLgAECn8lAAMVAAgJxxCGOgBTAQAVAAgJxxCGOgBTAQAKAAUJiQjU/QCsAAAAAA==.Deviantart:BAAALgAECgQJBAAAAA==.',
Di='Diana:BAABLgAECn8kAAIIAAkJqA00RADJAQAIAAkJqA00RADJAQAAAA==.Diietriich:BAABLgAECn8yAAIFAAgJSCKNHQCkAgAFAAgJSCKNHQCkAgAAAA==.Dilligaaf:BAAALgADCgMJAwAAAA==.',
Do='Docbeanz:BAAALgADCgMJAwAAAA==.Donkypunch:BAAALgADCgQJBAAAAA==.Dontjudgemê:BAAALgADCgIJAgAAAA==.Doodlekhal:BAAALgADCgMJAwAAAA==.Dopie:BAAALgADCgIJAgAAAA==.Dorcina:BAAALgAECgIJAgAAAA==.',
Dr='Dracthyr:BAAALgADCgUJDQAAAA==.Dragonwarrio:BAAALgADCggJCAAAAA==.Dragoondpain:BAAALgAECgQJCwAAAQ==.Draltina:BAABLgAECn8XAAMBAAgJPAmkDQBaAQABAAgJPAmkDQBaAQACAAEJywLtLwEhAAAAAA==.Drazira:BAABLgAECn8YAAIYAAgJ9wRMlwDlAAAYAAgJ9wRMlwDlAAAAAA==.Drugonwerier:BAAALgADCgEJAgAAAA==.Drunkbera:BAAALgAECgcJBwAAAA==.Druzzlek:BAAALgAECgEJAQAAAA==.',
Du='Dubalpally:BAAALgADCggJCAAAAA==.Dunks:BAABLgAFFH8FAAICAAMJJwMJhQCoAAACAAMJJwMJhQCoAAAAAA==.',
Dy='Dylghoul:BAAALgADCgUJBQAAAA==.',
['Dí']='Dírac:BAABLgAFFH8GAAICAAMJTw3bcwDMAAACAAMJTw3bcwDMAAAAAA==.',
Ec='Eclipsekitty:BAAALgAECgUJBQABLgAFFAQJCQAVAOIQAA==.',
Ed='Edwillei:BAAALgAECgUJCAAAAA==.',
Ef='Efforex:BAAALgADCgQJBAAAAA==.',
Ei='Einhar:BAAALgAECgEJAQAAAA==.',
El='Elactoplasm:BAAALgAECgMJAwAAAA==.Elderslapaho:BAAALgADCgUJBgAAAA==.Ellistrae:BAAALgAECgYJCQAAAA==.Ellysia:BAAALgADCgEJAQAAAA==.',
Em='Emmel:BAAALgADCggJCwAAAA==.',
Eq='Equeslucis:BAAALgAECgcJBwAAAA==.',
Er='Erodrana:BAAALgAECgYJEgABLgAECggJGAAYAPcEAA==.Eromir:BAAALgAECgUJCgAAAA==.Eryi:BAABLgAECn9AAAIEAAkJ8hddEwBwAgAEAAkJ8hddEwBwAgAAAA==.',
Et='Ethan:BAABLgAECn8eAAMcAAkJnRvhEADZAQAcAAcJIRjhEADZAQAbAAQJ6CIdUgD4AAAAAA==.',
Ev='Evonari:BAAALgADCgIJAgAAAA==.',
Ex='Exoticfrost:BAAALgADCgIJAgAAAA==.Expertnewb:BAAALgAECgIJAgABLgAECggJKAAFAD4bAA==.',
['Eí']='Eísheth:BAAALgADCgUJBAAAAA==.',
Fa='Faegen:BAAALgAECgEJAgAAAA==.Falkønn:BAAALgAECgMJAwAAAA==.Fangytooth:BAACLgAFFH8HAAIXAAQJ2CFzBgCSAQAXAAQJ2CFzBgCSAQAuAAQKfy4AAhcACQl5JJACABgDABcACQl5JJACABgDAAAA.Fashaun:BAAALgAECgIJAgAAAA==.Faze:BAABLgAECn8aAAIFAAYJyx+nXgC9AQAFAAYJyx+nXgC9AQAAAA==.',
Fe='Fellamayyne:BAAALgADCgEJAQAAAA==.Ferrus:BAACLgAFFH8hAAMYAAgJBiKgBwB0AgAYAAgJBiKgBwB0AgAQAAQJsxyyFwDIAAAuAAQKfx4AAxAACQn1JdANAIYCABgACQlWJOwcAKQCABAABwncJNANAIYCAAAA.',
Ff='Ffleuderflam:BAAALgAECgYJBgAAAA==.',
Fl='Floors:BAAALgAECgEJAQAAAA==.',
Fr='Frose:BAAALgADCgEJAQAAAA==.Frostyblast:BAAALgADCgUJBgAAAA==.',
Fu='Fupacabra:BAAALgADCgEJAQAAAA==.Furiiosa:BAAALgAECgUJBQAAAA==.Furiosity:BAAALgAECgMJBQAAAA==.Fuzzybear:BAAALgAECgcJCAABLgAFFAQJBwAXANghAA==.Fuzzybeard:BAAALgAECgYJBgABLgAFFAQJBwAXANghAA==.Fuzzyspells:BAAALgAECgEJAQABLgAFFAQJBwAXANghAA==.Fuzzywar:BAAALgAECgYJBwABLgAFFAQJBwAXANghAA==.',
['Fõ']='Fõrtress:BAAALgAECgMJBAAAAA==.',
Ga='Gabomonk:BAABLgAFFH8FAAIHAAIJ1iSqMwDMAAAHAAIJ1iSqMwDMAAAAAA==.Gamalia:BAAALgADCgUJBQAAAA==.Garudekhan:BAAALgADCgUJBQAAAA==.',
Ge='Genreallee:BAABLgAECn8dAAIKAAcJ1hIphABbAQAKAAcJ1hIphABbAQAAAA==.Gernab:BAAALgADCgYJBgAAAA==.',
Gh='Ghost:BAABLgAECn8WAAILAAYJ9xt+NgDOAQALAAYJ9xt+NgDOAQAAAA==.',
Gi='Gianna:BAABLgAECn8XAAMVAAkJ7COWAgB3AwAVAAkJ7COWAgB3AwAKAAIJCR6JCwGcAAAAAA==.Gizzar:BAAALgADCgYJCgAAAA==.',
Gl='Glau:BAAALgAECgQJBAABLgAECggJCQAJAAAAAA==.Glimpsed:BAAALgAECgcJDgABLgAECgkJAgAJAAAAAA==.Globgore:BAAALgADCgIJBAAAAA==.Gloçk:BAAALgAECgMJCAABLgAECgYJEQAJAAAAAA==.',
Go='Goofy:BAABLgAECn8fAAIKAAcJYCHDJACUAgAKAAcJYCHDJACUAgAAAA==.Goor:BAAALgAECgEJAQAAAA==.Gorrik:BAAALgADCgUJBQAAAA==.',
Gr='Graeae:BAAALgAECgcJCAAAAA==.Greyfeather:BAAALgADCgEJAgAAAA==.Grimeace:BAAALgADCgQJBAAAAA==.',
Gu='Gunduin:BAACLgAFFH8FAAIIAAIJ/hakbwCfAAAIAAIJ/hakbwCfAAAuAAQKfx4AAggACAmuIBQeAFECAAgACAmuIBQeAFECAAAA.',
Gw='Gweb:BAAALgAECgIJAgAAAA==.',
Gy='Gyda:BAABLgAECn8nAAIUAAcJ9CGRCwCpAgAUAAcJ9CGRCwCpAgAAAA==.Gyuyuki:BAABLgAECn9AAAIPAAkJdhN9HQDoAQAPAAkJdhN9HQDoAQAAAA==.',
Ha='Hakuanah:BAAALgADCgEJAQAAAA==.Halvorak:BAAALgADCgcJCgAAAA==.Harryp:BAACLgAFFH8HAAIdAAQJ6ApBNgDgAAAdAAQJ6ApBNgDgAAAuAAQKfzYAAx4ACQm5GIYGANkBAB0ACQnlElocAOwBAB4ACQlDFYYGANkBAAAA.Hast:BAAALgAECgYJEwAAAA==.',
He='Hearthzilla:BAAALgAECgEJAQABLgAECgkJIQAPANgfAA==.Heidie:BAAALgAECgUJBgAAAA==.Hellsbow:BAAALgAECgYJDgAAAA==.Hermin:BAAALgADCgQJCAAAAA==.',
Ho='Holyhellz:BAAALgADCgEJAQAAAA==.Honeyboo:BAAALgAECgUJBQABLgAFFAQJCQALADMNAA==.Hots:BAAALgADCgcJBwAAAA==.Hotzz:BAAALgAECgEJAQAAAA==.',
Hr='Hraesvelgr:BAAALgADCggJBwAAAA==.',
Hu='Huntavious:BAACLgAFFH8IAAIXAAQJGxTKDwA5AQAXAAQJGxTKDwA5AQAuAAQKfzQABBcACQk8H+IEANgCABcACQk8H+IEANgCAAgABgnjGsZeAEsBAB8AAQnIE9uKADAAAAAA.',
['Hë']='Hëllen:BAABLgAECn8YAAIKAAYJMiDaaQCrAQAKAAYJMiDaaQCrAQAAAA==.',
['Hú']='Húñtrèss:BAAALgAECgMJAwAAAA==.',
Ia='Iamshinigamy:BAAALgAECgIJAgABLgAECgcJFwAFAPMaAA==.',
Ii='Iichimaru:BAAALgAECgUJBQAAAA==.',
Il='Illidupe:BAAALgADCgMJAwAAAA==.',
In='Inaoh:BAAALgAECgQJBwAAAA==.Insaniac:BAAALgAECgQJBAAAAA==.',
Ir='Ironboss:BAAALgAECgUJBQAAAA==.',
Iv='Ivey:BAABLgAECn8qAAILAAgJRh7REwCkAgALAAgJRh7REwCkAgAAAA==.',
Iz='Izes:BAAALgAECgEJAgAAAA==.',
Ja='Jaagganug:BAAALgADCgMJAwAAAA==.Jacenne:BAABLgAECn8bAAIgAAcJlAN5WwCXAAAgAAcJlAN5WwCXAAAAAA==.Jairus:BAAALgAECgcJBwAAAA==.',
Jd='Jdirty:BAABLgAECn8YAAIhAAYJhAnMEQDgAAAhAAYJhAnMEQDgAAAAAA==.',
Je='Jellytime:BAAALgAECgMJBQAAAA==.',
Jo='Josephyn:BAAALgAECgcJCgABLgAFFAYJLQAOAKgfAA==.',
Ju='Jugernaut:BAAALgAECgEJAQAAAA==.Jumpmann:BAAALgAECgMJAwAAAA==.Justdesserts:BAAALgAECgEJAQAAAA==.Justix:BAAALgADCggJEwAAAA==.',
Ka='Kadaffy:BAAALgAECgIJAwAAAA==.Kakusu:BAAALgAECgYJEQAAAA==.Kakuta:BAAALgAECgUJDwABLgAECgkJGgAPAA4dAA==.Kakutá:BAABLgAECn8aAAIPAAkJDh1/CwCfAgAPAAkJDh1/CwCfAgAAAA==.Kalru:BAAALgAECgIJAgAAAA==.Kargar:BAAALgAECgEJAgAAAA==.Katharsis:BAACLgAFFH8NAAIKAAQJ8g1xSwAIAQAKAAQJ8g1xSwAIAQAuAAQKfyEAAgoACQnPFihBAPgBAAoACQnPFihBAPgBAAAA.',
Ke='Keba:BAAALgAECgEJAQABLgAFFAUJHAAVAEoiAA==.Keit:BAAALgADCgYJBgABLgAFFAQJBgAQALkeAA==.Keévs:BAAALgADCgQJBAAAAA==.',
Kh='Khalidisi:BAABLgAECn8uAAQDAAkJFR8oBgB5AgADAAgJsR8oBgB5AgAVAAkJLRnMLACiAQAKAAcJJAr/tAAMAQAAAA==.Khaliesi:BAAALgADCgIJAgAAAA==.Khalizar:BAABLgAFFH8MAAIbAAQJPgh5JwAEAQAbAAQJPgh5JwAEAQAAAA==.Kharazim:BAAALgADCgEJAQABLgAECgkJKgAYAOIaAA==.Khenja:BAAALgAECgEJAQAAAA==.Khál:BAAALgADCgYJBgAAAA==.',
Ki='Killerelf:BAAALgAECgcJEAAAAA==.Kittie:BAAALgADCggJCAAAAA==.',
Kk='Kkiilleerr:BAAALgAECgYJDwAAAA==.',
Ko='Kobbaltcilar:BAAALgAECgUJBgAAAA==.Koraleena:BAAALgAECgQJBAAAAA==.Korbo:BAABLgAECn8pAAMPAAgJ/RyKKACbAQAPAAUJeR6KKACbAQAOAAUJOhZtXwAuAQAAAA==.Korbulo:BAABLgAECn8UAAIFAAkJmwlncACTAQAFAAkJmwlncACTAQAAAA==.Korlothel:BAABLgAECn8kAAIDAAkJvAdGHwANAQADAAkJvAdGHwANAQABLgAFFAMJAwAJAAAAAA==.Korrith:BAAALgADCgIJAgAAAA==.',
Kr='Krumpus:BAABLgAECn8hAAIYAAkJmRJUNQDlAQAYAAkJmRJUNQDlAQAAAA==.',
Ku='Kungfuuy:BAABLgAECn8lAAIHAAkJPCFJBAD8AgAHAAkJPCFJBAD8AgAAAA==.Kurtevade:BAAALgAECgQJDAAAAA==.',
Kw='Kwetnepthl:BAAALgAECgEJAgAAAA==.',
Ky='Kynsong:BAABLgAECn8WAAISAAkJ4w7sIQCmAQASAAkJ4w7sIQCmAQAAAA==.',
['Kà']='Kàlbrews:BAABLgAECn9AAAIHAAkJvyZAAACJAwAHAAkJvyZAAACJAwAAAA==.Kàrmâ:BAAALgAECgUJBQAAAA==.',
['Kî']='Kîrah:BAAALgAFFAIJAgAAAA==.',
La='Lagk:BAAALgADCgkJHgAAAA==.Lainiee:BAAALgADCgEJAQAAAA==.Lavismad:BAECLgAFFH8JAAIbAAQJuiBsDACOAQAbAAQJuiBsDACOAQAuAAQKfzQABBsACQkMJewDACIDABsACQnYJOwDACIDABYABwmhIH4OAPQBABwAAQlGJXcyAGkAAAAA.Lavoc:BAEALgADCgcJBwABLgAFFAQJCQAbALogAA==.Lavv:BAEALgAECgYJCAABLgAFFAQJCQAbALogAA==.Lavz:BAEALgAECgYJBgABLgAFFAQJCQAbALogAA==.',
Le='Legendary:BAAALgAECgYJDQAAAA==.Leshah:BAAALgAECgYJCwAAAA==.',
Li='Lichkingdied:BAAALgADCgUJBQAAAA==.Lightndpain:BAAALgAECgQJBgABLgAECgQJCwAJAAAAAA==.Lildh:BAAALgAECgUJCQAAAA==.Lilypetal:BAAALgAECgQJBwAAAA==.Lionaest:BAAALgAECgEJAQAAAA==.Littlebucket:BAAALgADCgEJAQAAAA==.',
Lo='Lockdpain:BAAALgAECgYJGAABLgAECgQJCwAJAAAAAQ==.Logov:BAAALgAECgYJDwAAAA==.Loraine:BAAALgAECgEJAQAAAA==.Loìsbethe:BAAALgAECgYJCgAAAA==.',
Lu='Luciferra:BAAALgAFFAMJAwABLgAFFAYJLQAOAKgfAA==.Lukey:BAAALgAECgMJAwAAAA==.Lunartemis:BAAALgAECgUJCAABLgAFFAQJDgAiACchAA==.Luu:BAAALgAECgMJBwAAAA==.',
Ly='Lyza:BAAALgADCgYJCQAAAA==.',
['Lö']='Lörax:BAAALgADCgQJBQAAAA==.',
['Lû']='Lûnafreya:BAAALgAECggJEgAAAA==.',
Ma='Maelera:BAAALgADCgkJDAAAAA==.Maetromundo:BAAALgAECgEJAQAAAA==.Magentas:BAAALgADCgIJAgAAAA==.Magickul:BAAALgADCggJCAAAAA==.Mahlah:BAAALgAECgQJBAAAAA==.Malaboo:BAAALgAECgEJAQABLgAFFAQJCQALADMNAA==.Malabooty:BAAALgAECgYJBwABLgAFFAQJCQALADMNAA==.Maletsy:BAAALgAECgEJAQABLgAFFAIJBQAIAP4WAA==.Maliboo:BAACLgAFFH8JAAILAAQJMw0ZMQDmAAALAAQJMw0ZMQDmAAAuAAQKfzkAAwsACQlEIkcEAHEDAAsACQlEIkcEAHEDACAAAgmfCWSGADIAAAAA.Maxamus:BAABLgAECn8aAAQcAAYJwiG8EQDOAQAcAAYJwiG8EQDOAQAWAAUJzBi6JgDuAAAbAAEJgxdojQBHAAAAAA==.Maxigooner:BAAALgAFFAEJAgABLgAFFAUJIAAKACMmAA==.',
Mc='Mcflurry:BAAALgAECgUJCwAAAA==.',
Me='Medarisa:BAAALgAECgcJDQAAAA==.Medavia:BAAALgADCgUJBQAAAA==.Mederia:BAAALgAECgUJBQAAAA==.Medívh:BAAALgADCgEJAQAAAA==.Melisandr:BAAALgAECgMJBQAAAA==.Merkenier:BAABLgAECn8rAAIgAAgJ7RKrIQCuAQAgAAgJ7RKrIQCuAQAAAA==.Merkshamalot:BAAALgADCgcJBwABLgAECggJKwAgAO0SAA==.Merkur:BAAALgAECgYJDQABLgAECggJKwAgAO0SAA==.Merkurry:BAAALgADCgYJBgABLgAECggJKwAgAO0SAA==.',
Mi='Midnitehunt:BAAALgAECgQJBAAAAA==.Miragia:BAAALgAECgUJDQAAAA==.Missmayhem:BAAALgAECgUJCAAAAA==.Missmayhemm:BAAALgADCgQJBgAAAA==.',
Mo='Modifiedmix:BAABLgAECn8pAAIIAAgJfxldMQAMAgAIAAgJfxldMQAMAgAAAA==.Modsabadtank:BAAALgAECgYJCwABLgAECggJKQAIAH8ZAA==.Mokomohama:BAAALgAECgcJBwAAAA==.Monatazumaa:BAAALgAECgEJAgAAAA==.Moofasah:BAAALgAECgkJAgAAAA==.Moonbloom:BAAALgAFFAEJAQABLgAFFAYJLQAOAKgfAA==.Mopeezie:BAAALgAECgEJAQAAAA==.Mordicant:BAAALgADCgEJAQAAAA==.Morella:BAABLgAECn81AAIRAAcJmQ4HGQCDAQARAAcJmQ4HGQCDAQAAAA==.',
Mu='Mucduck:BAAALgADCgEJAQAAAA==.Mustakrakish:BAAALgAECgEJAQAAAA==.Mustaz:BAAALgAECgkJBQAAAA==.',
My='Mym:BAAALgADCgcJBAAAAA==.Mystics:BAAALgAECgUJBQAAAA==.Mythrunduil:BAAALgADCgEJAQAAAA==.',
['Må']='Mågi:BAAALgAECgcJBwAAAA==.',
['Mé']='Médb:BAABLgAECn8tAAMFAAgJnB03LQBeAgAFAAgJIR03LQBeAgAjAAMJFR2+CADoAAAAAA==.',
Na='Naste:BAAALgAECgUJBQAAAA==.Nathrold:BAAALgAECgIJBAABLgAECgYJEQAJAAAAAA==.',
Ne='Neptune:BAACLgAFFH8tAAIOAAYJqB+aCwD1AQAOAAYJqB+aCwD1AQAuAAQKfyEAAw4ACQlRIhgHAAIDAA4ACQlRIhgHAAIDAA8ABwkkDtE0AIQBAAAA.Nerfdks:BAAALgAECgkJDQAAAA==.Nerfpaladins:BAABLgAECn8kAAQDAAcJpRL1IgDvAAAKAAYJthG5sAASAQADAAcJJBH1IgDvAAAVAAMJzAQYcgBiAAAAAA==.Neruess:BAAALgADCgUJBQAAAA==.Nezzuko:BAAALgAECgcJBwAAAA==.',
Ni='Nightbird:BAABLgAECn8dAAMiAAcJvBdUKQA9AQAiAAcJThdUKQA9AQAkAAYJ8BWfDgAsAQABLgAECggJCQAJAAAAAA==.Ninediewatt:BAAALgAECgQJCAAAAA==.Nivella:BAAALgAECgYJCgAAAA==.Nixaana:BAAALgAECgQJBQAAAA==.Niçki:BAAALgADCgMJAwAAAA==.',
No='Notlockz:BAAALgADCgIJAgAAAA==.Novah:BAAALgADCgQJBQAAAA==.Noydb:BAAALgAECgEJAQABLgAECgkJNwAWAKwbAA==.',
Nu='Nuah:BAAALgADCgYJDQAAAA==.',
Ny='Nyxsia:BAEALgAFFAEJAQABLgAFFAcJHwAbAJAdAA==.',
['Nè']='Nèo:BAAALgADCgcJBwAAAA==.',
Ob='Obayi:BAABLgAECn80AAIIAAcJ5A8FawBfAQAIAAcJ5A8FawBfAQAAAA==.',
Og='Ogmadmonk:BAACLgAFFH8MAAIQAAMJnRJMFwDLAAAQAAMJnRJMFwDLAAAuAAQKfzEAAhAACQmUIRoIAJ8CABAACQmUIRoIAJ8CAAAA.',
Ok='Oktobra:BAABLgAECn8bAAIKAAYJIwOxDwGXAAAKAAYJIwOxDwGXAAAAAA==.',
On='Onetrickpony:BAAALgAECgIJAgAAAA==.Onos:BAAALgAECgIJAgAAAA==.Onosm:BAAALgAECgQJBAAAAA==.',
Or='Orangevoker:BAAALgAECgcJCwABLgAECgkJIQAPANgfAA==.Orioan:BAAALgAECgUJCQAAAA==.Orux:BAAALgAECgYJBgAAAA==.',
Os='Osenya:BAAALgAECgYJBgABLgAFFAQJCQAMAGMfAA==.Osun:BAAALgADCggJCwAAAA==.',
Ou='Ouroboro:BAAALgADCgUJBQAAAA==.',
Ow='Owlbat:BAAALgAECgEJAQAAAA==.',
Pa='Padremort:BAAALgADCgYJBgAAAA==.Palantyr:BAABLgAECn9fAAIPAAgJvRqZGgA+AgAPAAgJvRqZGgA+AgAAAA==.Paly:BAAALgAECgEJAQAAAA==.Para:BAAALgAECgQJBAAAAA==.Patrician:BAABLgAECn8pAAIhAAgJdBZzBgDfAQAhAAgJdBZzBgDfAQAAAA==.',
Pe='Peehat:BAAALgADCgcJCQAAAA==.Penutbutter:BAAALgAECgQJBwAAAA==.Pepegasus:BAAALgADCgcJBwAAAA==.',
Ph='Phobos:BAAALgADCgQJCAAAAA==.Phyloren:BAAALgADCgUJBgAAAA==.',
Pi='Pigsticker:BAAALgAECgQJBQAAAA==.Pixyfire:BAAALgAECgYJCgABLgAFFAQJCQAVAOIQAA==.',
Po='Poisonleaf:BAAALgAECgUJBgABLgAECgYJGAAKADIgAA==.Pokingharder:BAABLgAECn8aAAIkAAkJhhQ3BQAhAgAkAAkJhhQ3BQAhAgABLgAFFAMJCgABAA0WAA==.',
Pu='Pulcherrimus:BAAALgAECgEJAwAAAA==.Purgeem:BAAALgADCgUJBQAAAA==.Pushpop:BAAALgAECgYJDwABLgAECggJXwAPAL0aAA==.',
Pw='Pwiest:BAAALgADCgcJEAAAAA==.',
Qu='Quetzalcoatl:BAABLgAECn8bAAIlAAkJsRmyBwByAgAlAAkJsRmyBwByAgAAAA==.',
Ra='Raambox:BAAALgAECgQJBAAAAA==.Radak:BAAALgAECgEJAQAAAA==.Raddish:BAABLgAECn8bAAISAAYJ+RBwPADzAAASAAYJ+RBwPADzAAAAAA==.Rahjlynn:BAAALgADCgcJCAAAAA==.Rahken:BAAALgAECgcJBwAAAA==.Raiinn:BAAALgADCgUJBQAAAA==.Raylee:BAACLgAFFH8JAAMBAAQJBRxHAwBZAQABAAQJQhVHAwBZAQARAAIJ4xsoEACoAAAuAAQKfz4ABAIACQmeISkTAK4CAAIACAmxHykTAK4CABEABwl8IQ8IAEQCAAEAAwk2GscXAPEAAAAA.Razuki:BAACLgAFFH8JAAIVAAQJ4hCHIwD4AAAVAAQJ4hCHIwD4AAAuAAQKfzQAAxUACQmLIu8EAD0DABUACQmLIu8EAD0DAAoABwn2F8hrAIwBAAAA.',
Re='Remyl:BAAALgADCggJCAAAAA==.Reynia:BAAALgAECgEJAQAAAA==.',
Rf='Rfd:BAAALgADCgcJBwAAAA==.',
Rh='Rhaenies:BAAALgAECgYJEAAAAA==.Rharr:BAAALgADCgkJDAAAAA==.Rhovanion:BAAALgAECgUJCQAAAA==.Rhuac:BAABLgAECn8pAAILAAkJeRPFKAADAgALAAkJeRPFKAADAgAAAA==.',
Ri='Risakah:BAAALgAECggJCQAAAA==.',
Ro='Rorschach:BAAALgAECgcJCgAAAA==.Rosefist:BAEALgADCgcJCAABLgAFFAYJEAAUAKcSAA==.Rosemourne:BAEALgAECgIJAgABLgAFFAYJEAAUAKcSAA==.Roseykat:BAABLgAECn8lAAIIAAcJBww8ewA7AQAIAAcJBww8ewA7AQAAAA==.Roshwyn:BAABLgAECn8UAAIIAAgJHguZaABlAQAIAAgJHguZaABlAQAAAA==.Rottedmeat:BAAALgAECgcJCgAAAA==.',
Ru='Rubmytotems:BAAALgAECgYJBgAAAA==.Ruckus:BAABLgAECn8nAAIKAAgJuRYPPwApAgAKAAgJuRYPPwApAgAAAA==.',
Sa='Saberwar:BAAALgAECgEJAQABLgAECgMJAwAJAAAAAA==.Saintfury:BAAALgAECgQJBQAAAA==.Saintsfear:BAABLgAECn8oAAIbAAgJTBCPLQCUAQAbAAgJTBCPLQCUAQAAAA==.Sanchito:BAAALgADCgMJAwAAAA==.Saphalia:BAAALgADCgMJAwAAAA==.Saradomin:BAAALgADCgUJBAAAAA==.Sareenastar:BAACLgAFFH8JAAISAAQJoyCYCwB4AQASAAQJoyCYCwB4AQAuAAQKfy4AAxIACQmUJk8AAOIDABIACQmUJk8AAOIDABMAAQnfCZuCAC8AAAAA.Sasae:BAABLgAECn8YAAIHAAcJtg69NgAaAQAHAAcJtg69NgAaAQAAAA==.',
Sc='Scorias:BAAALgADCgQJAwAAAA==.',
Se='Selisztraza:BAAALgADCgEJAQAAAA==.Sephiróth:BAAALgADCgUJCAAAAA==.Sereni:BAAALgADCgQJBAAAAA==.Serenity:BAAALgAECgcJEgAAAA==.Serenitynow:BAAALgAECgEJAgAAAA==.Sewald:BAAALgAECgcJDwAAAA==.',
Sh='Shadowzbane:BAAALgAECgIJAgAAAA==.Shahasha:BAAALgADCgEJAQAAAA==.Shaidarharan:BAAALgADCgIJAgAAAA==.Shakeybop:BAAALgAECgQJBAAAAA==.Shalen:BAABLgAECn8oAAQdAAkJCBS+HQDhAQAdAAkJ/BO+HQDhAQAeAAYJoQ2ZHQBCAQAlAAQJsw6VKwCBAAAAAA==.Sharker:BAAALgADCgYJBgAAAA==.Sharkyb:BAAALgAECgEJAQABLgAECgkJNwAMAKsiAA==.Sharpie:BAAALgADCgcJCgAAAA==.Sheer:BAABLgAECn8UAAIHAAgJYB8SDgBNAgAHAAgJYB8SDgBNAgAAAA==.Sheraa:BAABLgAECn8iAAIDAAgJrxFLFAB9AQADAAgJrxFLFAB9AQAAAA==.Shiftystrike:BAABLgAECn8WAAImAAcJPx/wCgAVAgAmAAcJPx/wCgAVAgAAAA==.Shifushield:BAAALgAECgcJCAAAAA==.Shireshannon:BAABLgAECn8VAAIIAAYJegkrmAACAQAIAAYJegkrmAACAQAAAA==.Shrike:BAAALgAECgEJAQABLgAFFAcJGgATALAaAA==.Shrunkador:BAACLgAFFH8QAAIPAAQJMg35JQD2AAAPAAQJMg35JQD2AAAuAAQKfzMAAg8ACQm6HV4PAHACAA8ACQm6HV4PAHACAAAA.',
Si='Silk:BAAALgAECgYJDgAAAA==.Silmarkthree:BAACLgAFFH8JAAIFAAQJnBOdUgA3AQAFAAQJnBOdUgA3AQAuAAQKfzQAAgUACQmkGP02ADYCAAUACQmkGP02ADYCAAAA.Sinbåd:BAAALgAECgcJCAAAAA==.Siodar:BAAALgADCgEJAQABLgAECgMJAwAJAAAAAA==.Sisterstar:BAAALgADCgMJAwAAAA==.',
Sl='Sleety:BAAALgAECgIJBQAAAA==.Slipknoth:BAACLgAFFH8iAAMTAAgJzxpEBAApAgATAAcJeh1EBAApAgAUAAYJ3g2yFACyAQAuAAQKfywABBMACQnlInMQAFACABMACAkHJXMQAFACABIABwntF/kgANsBABQABAnOGWFCAPAAAAAA.',
Sn='Snekhain:BAAALgADCgMJAwAAAA==.Snuffaluffa:BAAALgAECgMJAwAAAA==.',
So='Somatra:BAAALgADCgkJCQAAAA==.Sorean:BAACLgAFFH8RAAIXAAUJxxsaCwBfAQAXAAUJxxsaCwBfAQAuAAQKfy8ABAgACQm+IFYhAD0CAAgABwlUG1YhAD0CABcABwlnHXEYANkBAB8ABwlQGv0vALUBAAAA.',
Sp='Specialmove:BAAALgAFFAEJAgAAAA==.Spookydookie:BAAALgADCgkJCgAAAA==.',
St='Staghealz:BAAALgAECgIJAgAAAA==.Stifs:BAABLgAECn8kAAIDAAgJzhEEFwBlAQADAAgJzhEEFwBlAQAAAA==.Stilleena:BAAALgAECgYJBgAAAA==.Stinkinglily:BAAALgAECgEJAgAAAA==.Strunrage:BAEALgAECgcJDAABLgAECgkJPgAKAIskAA==.Stÿx:BAABLgAECn8ZAAInAAYJ6gUtPQCQAAAnAAYJ6gUtPQCQAAABLgAECggJEAAJAAAAAA==.',
Su='Sugarbomb:BAAALgADCgYJCgAAAA==.',
Sy='Sykotyk:BAAALgAECgkJDwAAAA==.Sylverfox:BAAALgAECgMJAwABLgAECgkJHgAVABkeAA==.Synchestra:BAAALgADCgcJCgAAAA==.',
Ta='Tadagain:BAABLgAECn8gAAMKAAYJlhK1ogAnAQAKAAYJlhK1ogAnAQAVAAQJ2gV2dgChAAAAAA==.Tagrith:BAAALgADCgMJAwAAAA==.Tankybears:BAACLgAFFH8FAAILAAIJOhtBQQCnAAALAAIJOhtBQQCnAAAuAAQKfywAAyAACQnOGhAQAFQCACAACQnOGhAQAFQCAAsACAnqG6lQAEIBAAAA.Tarmalok:BAAALgAECgEJAQAAAA==.Tazera:BAAALgAECgUJCwAAAA==.',
Te='Telekinesis:BAABLgAECn8iAAIXAAgJvhDEHgCiAQAXAAgJvhDEHgCiAQAAAA==.Tenara:BAABLgAFFH8GAAIOAAQJORRONQD1AAAOAAQJORRONQD1AAABLgAFFAIJBQALADobAA==.Tenbinza:BAAALgAECgQJBgAAAA==.Teos:BAACLgAFFH8FAAIZAAMJSQmFDgC9AAAZAAMJSQmFDgC9AAAuAAQKfzQAAhkACQlnGcwHAD8CABkACQlnGcwHAD8CAAAA.',
Th='Thainé:BAAALgAECgMJBgAAAA==.Thaldrassian:BAAALgADCgQJBAAAAA==.Tharris:BAAALgAECgYJCAAAAA==.Thehatred:BAAALgADCgYJBgAAAA==.Therondar:BAAALgADCgEJAQAAAA==.Thiyan:BAAALgADCgMJAwAAAA==.Tholin:BAAALgAECgcJCgAAAA==.Thromar:BAABLgAECn8VAAIFAAcJiBWvgADPAQAFAAcJiBWvgADPAQAAAA==.Thunderlily:BAABLgAECn8oAAMFAAgJPhsxNABBAgAFAAgJeRoxNABBAgAoAAcJchfpBgCgAQAAAA==.Thünder:BAAALgADCgcJBwABLgAECgcJFgAMAKQeAA==.',
Ti='Tinderbeef:BAAALgADCgcJCAAAAA==.Tinychaos:BAAALgAECgkJCQAAAA==.Tinyround:BAAALgAECgEJAQAAAA==.Tirra:BAABLgAECn8eAAMVAAkJGR62EQB8AgAVAAkJGR62EQB8AgAKAAIJJgZXVAFPAAAAAA==.',
To='Torama:BAAALgADCgIJAgAAAA==.Toranth:BAABLgAECn81AAIVAAkJiRVvGAA5AgAVAAkJiRVvGAA5AgAAAA==.Torq:BAABLgAECn8XAAIFAAYJ/BmShwDCAQAFAAYJ/BmShwDCAQABLgAECgcJFwAVAIghAA==.Torqumada:BAAALgAECgkJBgAAAA==.Toxian:BAABLgAECn8tAAIYAAgJzxWfPwC+AQAYAAgJzxWfPwC+AQAAAA==.Toxicelitist:BAABLgAECn8rAAMRAAkJ4w7bCgCEAQARAAkJ4w7bCgCEAQACAAEJmgErVgEaAAAAAA==.',
Tr='Treedemon:BAACLgAFFH8JAAIYAAQJExnGLwBNAQAYAAQJExnGLwBNAQAuAAQKfyoAAhgACQksJJcJAPcCABgACQksJJcJAPcCAAAA.Treedin:BAAALgAECgMJAwAAAA==.Trollboi:BAAALgADCggJCAAAAA==.Tryden:BAAALgADCggJCAABLgAECgkJNwAWAKwbAA==.Trymw:BAAALgADCgIJAgAAAA==.Tryst:BAAALgADCgcJBwAAAA==.',
Ty='Tybearon:BAAALgAECgEJAQAAAA==.Tyinthus:BAAALgAECgcJBwABLgAECgcJBwAJAAAAAA==.Tyreid:BAAALgAECgcJBwAAAA==.Tyrelitha:BAAALgAECgMJBgAAAA==.',
Ud='Udderchoad:BAAALgADCgEJAQAAAA==.',
Uh='Uhura:BAAALgAECgEJAQAAAA==.',
Ul='Ulfrir:BAACLgAFFH8OAAIIAAQJ2RsXJwBYAQAIAAQJ2RsXJwBYAQAuAAQKfyYAAwgACQk3IMoPAMkCAAgACQk3IMoPAMkCAB8AAwkxCipvAIIAAAAA.Ultradukes:BAAALgAECgMJBAAAAA==.',
Un='Unatural:BAAALgAECgUJBQAAAA==.Unleashed:BAAALgAECgUJCgAAAA==.',
Va='Valarea:BAAALgADCgEJAQAAAA==.Valock:BAAALgAECgcJEAAAAA==.Vandham:BAAALgADCgEJAQAAAA==.Vannis:BAAALgADCggJDgAAAA==.Vanshifty:BAACLgAFFH8IAAILAAMJ+BdIMwDcAAALAAMJ+BdIMwDcAAAuAAQKf0QAAgsACQk0I8YEAGYDAAsACQk0I8YEAGYDAAAA.',
Ve='Veilf:BAAALgADCgYJDAAAAA==.Velf:BAAALgAECgIJAgAAAA==.Velrus:BAAALgAECgYJDAAAAA==.Venli:BAAALgAECgMJAwAAAA==.Venombite:BAAALgADCgMJAwAAAA==.Verez:BAAALgADCgcJBwAAAA==.',
Vi='Victorion:BAAALgAECggJCQAAAA==.Viktorax:BAAALgAECgYJCwAAAA==.Vincevega:BAAALgAECgkJDgAAAA==.Virtueozo:BAABLgAECn8aAAIlAAgJEBfODwA+AgAlAAgJEBfODwA+AgAAAA==.',
Vo='Volam:BAAALgAECgQJBAAAAA==.',
Vy='Vyx:BAAALgAECggJEAAAAA==.',
Wa='Waffle:BAABLgAECn8YAAIIAAYJihU2eQBAAQAIAAYJihU2eQBAAQABLgAECggJGgAIAFEOAA==.Waldhorn:BAAALgAECgcJCwAAAA==.Wangji:BAAALgAECgQJBAAAAA==.Wangwen:BAAALgADCgIJAgAAAA==.Wargue:BAABLgAECn8VAAIbAAYJjRugOADEAQAbAAYJjRugOADEAQAAAA==.',
We='Weeaboos:BAAALgADCgIJAgABLgADCgQJBAAJAAAAAA==.Weebsz:BAAALgADCgQJBAAAAA==.Welindis:BAABLgAECn8XAAIKAAcJVQd2vgD+AAAKAAcJVQd2vgD+AAABLgAECgkJMAAYAPgQAA==.Wetkith:BAAALgADCgUJBQAAAA==.',
Wi='Windrider:BAAALgADCgIJAgAAAA==.Windwraith:BAAALgAECgIJAgAAAA==.Wizzard:BAAALgAECggJHAAAAQ==.',
Xa='Xaiyara:BAAALgADCgUJBQAAAA==.Xalina:BAAALgAECgEJAQAAAA==.Xandaka:BAAALgADCgQJBAAAAA==.',
Xe='Xephir:BAAALgAECggJCgAAAA==.',
Xi='Xidied:BAACLgAFFH8HAAIHAAQJ3CDEEQCAAQAHAAQJ3CDEEQCAAQAuAAQKfzAAAgcACQkmIXkFAOICAAcACQkmIXkFAOICAAAA.Xilon:BAAALgAECgYJCgABLgAFFAQJCQAMAGMfAA==.Xilra:BAABLgAECn8uAAMgAAkJmiJiCwCUAgAgAAkJmiJiCwCUAgAmAAEJmhE3SwAzAAABLgAFFAQJCQAMAGMfAA==.Xilrot:BAABLgAFFH8JAAIMAAQJYx9GPABsAQAMAAQJYx9GPABsAQAAAA==.Xilzen:BAAALgAECgUJEQABLgAFFAQJCQAMAGMfAA==.Xinia:BAAALgAECgMJAwAAAA==.',
Xz='Xzed:BAAALgADCgEJAQAAAA==.',
Ye='Yew:BAAALgADCgMJAwAAAA==.',
Yi='Yikers:BAACLgAFFH8RAAIVAAQJZiCwFwBYAQAVAAQJZiCwFwBYAQAuAAQKfyUAAhUACQm6IacIAPcCABUACQm6IacIAPcCAAAA.',
Yr='Yridai:BAAALgAECgYJCAAAAA==.',
Za='Zani:BAAALgADCgYJBwAAAA==.Zarsher:BAAALgADCgIJAgAAAA==.',
Zd='Zdk:BAAALgAECgEJAQABLgAECgkJJAAIAHMbAA==.',
Ze='Zeldy:BAABLgAECn8vAAIIAAkJJxcWLgAZAgAIAAkJJxcWLgAZAgAAAA==.Zenestraza:BAAALgADCgcJCwABLgAECgkJKgAYAOIaAA==.Zenthareal:BAABLgAECn8qAAIYAAkJ4hrZFgCEAgAYAAkJ4hrZFgCEAgAAAA==.Zenzi:BAAALgADCgMJAwAAAA==.Zenzz:BAAALgADCgEJAQAAAA==.Zeuc:BAAALgADCgMJAwAAAA==.Zeuus:BAAALgADCgMJBAAAAA==.',
Zh='Zhirldk:BAAALgAECgcJEQAAAA==.Zhulgarosh:BAAALgADCgUJBQAAAA==.',
Zi='Zillidan:BAAALgAECgEJAwABLgAECgkJJAAIAHMbAA==.',
Zm='Zmaster:BAABLgAECn8kAAIIAAkJcxvVGwBzAgAIAAkJcxvVGwBzAgAAAA==.',
Zo='Zobeast:BAAALgADCgQJBAAAAA==.',
Zr='Zret:BAAALgAECgYJCgABLgAECgkJJAAIAHMbAA==.',
Zw='Zwar:BAAALgAECgEJAQABLgAECgkJJAAIAHMbAA==.',
Zy='Zynith:BAAALgAECgYJBgAAAA==.',
['Zö']='Zöey:BAAALgADCgQJBQAAAA==.',
['Åp']='Åpex:BAAALgAECggJBgAAAA==.',
['Çl']='Çloudz:BAAALgADCgMJAwAAAA==.',
['Ða']='Ðark:BAACLgAFFH8QAAIIAAMJDhJnGACmAAAIAAMJDhJnGACmAAAuAAQKfycAAggACQm5HAQVAI8CAAgACQm5HAQVAI8CAAAA.',
['Ðr']='Ðr:BAABLgAECn8eAAMOAAkJ/Br1IgANAgAOAAcJThr1IgANAgAPAAYJ7xeFMgBkAQAAAA==.',
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
