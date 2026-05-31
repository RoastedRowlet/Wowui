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

local lookup = {'Warlock-Affliction','Warlock-Demonology','Monk-Mistweaver','Mage-Frost','Monk-Windwalker','Monk-Brewmaster','Hunter-BeastMastery','Unknown-Unknown','Paladin-Retribution','Druid-Restoration','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Restoration','Shaman-Elemental','Warlock-Destruction','Priest-Holy','Priest-Shadow','Priest-Discipline','Paladin-Holy','Paladin-Protection','Warrior-Protection','Hunter-Survival','DemonHunter-Devourer','Shaman-Enhancement','DemonHunter-Vengeance','DemonHunter-Havoc','Warrior-Fury','Warrior-Arms','Evoker-Augmentation','Evoker-Devastation','Hunter-Marksmanship','Druid-Balance','Rogue-Outlaw','Rogue-Subtlety','Mage-Fire','Rogue-Assassination','Evoker-Preservation','Druid-Feral','DeathKnight-Blood','Mage-Arcane',}
local provider = {region='US',realm='Dawnbringer',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abdalhazred:BAACLgAFFH8XAAMBAAUJUiOKAQCLAQABAAUJUiOKAQCLAQACAAEJiR8GqABQAAAuAAQKfzQAAwEACQmYJFIAAGYDAAEACAm3JVIAAGYDAAIAAwnQHYehAPIAAAAA.Abilus:BAAALgAECgQJEAAAAA==.Abolis:BAAALgAECgMJBgAAAA==.',
Ae='Aeldriel:BAAALgAECgMJAwAAAA==.Aeoyn:BAAALgAECgEJAQAAAA==.',
Ag='Aggar:BAAALgADCgkJEwABLgAECgkJNwADAJEWAA==.',
Ak='Akoa:BAAALgAECgEJAQAAAA==.',
Al='Alarak:BAABLgAECn8bAAIBAAgJcRVsCQCtAQABAAgJcRVsCQCtAQAAAA==.Alerion:BAAALgAECgEJAQAAAA==.Alnara:BAAALgAECgEJAgAAAA==.Alvierearn:BAABLgAECn8WAAIEAAgJuxECigBIAQAEAAgJuxECigBIAQAAAA==.',
Am='Amoradis:BAAALgADCgUJEgAAAA==.',
An='Anaeir:BAAALgADCgYJBgAAAA==.Angriff:BAAALgADCgQJBQAAAA==.Anisette:BAABLgAECn8lAAMFAAgJdRlmFAACAgAFAAgJdRlmFAACAgAGAAQJDgp7YQB5AAAAAA==.Annuket:BAAALgAECgYJBgAAAA==.Anthria:BAAALgADCgkJGwAAAA==.',
Ap='Apexpredåtor:BAAALgADCgIJAgAAAA==.',
Aq='Aqurala:BAABLgAECn8jAAIHAAkJXRweHABnAgAHAAkJXRweHABnAgAAAA==.',
Ar='Aradem:BAAALgADCgcJBwABLgAFFAMJAwAIAAAAAA==.Aravenn:BAAALgAFFAMJAwAAAA==.Arcis:BAABLgAECn8kAAIJAAcJ0RLxgQBQAQAJAAcJ0RLxgQBQAQAAAA==.Ardeniro:BAAALgAECgEJAQAAAA==.Arealis:BAAALgADCgcJDAAAAA==.Argatem:BAAALgAECgQJBAABLgAECggJKgAKAEYeAA==.Arkangel:BAABLgAECn8qAAMLAAkJOxzdIAByAgALAAkJOxzdIAByAgAMAAEJYQnTNAAnAAAAAA==.Arke:BAAALgAECgMJAwAAAA==.Arkharon:BAAALgADCgYJCQAAAA==.Arralyon:BAAALgADCgMJBgAAAA==.Artemesia:BAAALgAECgEJAQABLgAFFAYJLAANAKgfAA==.Arthäs:BAAALgAECgQJBAAAAA==.Aryrn:BAAALgADCgUJBQAAAA==.',
As='Asakua:BAAALgAECgMJBgAAAA==.Asiya:BAAALgAECgQJBQAAAA==.Assandra:BAAALgADCgUJBQAAAA==.Astræa:BAAALgAECgEJAQAAAA==.',
At='Athul:BAAALgADCgUJCgAAAA==.',
Au='Aurlyn:BAAALgADCgcJDwAAAA==.',
Av='Avatartele:BAAALgAECgIJAwAAAA==.Avatartouka:BAABLgAECn8jAAMNAAgJ5yGPDgDHAgANAAgJ5yGPDgDHAgAOAAQJ9RNDYgCiAAAAAA==.Avianthel:BAAALgADCgMJAgAAAA==.Avraria:BAAALgAECgkJEgAAAA==.Avyl:BAABLgAECn8VAAQPAAYJ3RElGQDGAAABAAYJuBCQFAAEAQAPAAQJNhElGQDGAAACAAEJ9wdvHwExAAAAAA==.Avylastorica:BAAALgADCgYJBgABLgAECgYJFQAPAN0RAA==.',
Aw='Awsomninja:BAABLgAECn8kAAIGAAkJAiO7BADsAgAGAAkJAiO7BADsAgAAAA==.',
Ax='Axxain:BAAALgADCgkJGgAAAA==.',
Az='Azaralle:BAAALgADCgEJAQAAAA==.Azeazal:BAAALgAECgcJEgAAAA==.Azlifan:BAAALgADCgQJBAAAAA==.Azorthragal:BAAALgADCgYJBgABLgAECgIJAgAIAAAAAA==.',
Ba='Baddlandss:BAAALgAECgQJCAAAAA==.Bagador:BAAALgAECgYJCQAAAA==.Bastais:BAAALgAECgEJAQAAAA==.Batozai:BAAALgADCgEJAQAAAA==.Baumstack:BAAALgADCgUJBQAAAA==.',
Bd='Bdibz:BAAALgADCgcJDAAAAA==.',
Be='Beautifulluv:BAABLgAECn8sAAQQAAkJSyIEBAA4AwAQAAkJSyIEBAA4AwARAAYJzA1uPQD3AAASAAEJkAzNUwA6AAAAAA==.Beelzabubba:BAAALgAECgkJAwAAAA==.Bekabeka:BAACLgAFFH8aAAITAAUJRSJbCgDsAQATAAUJRSJbCgDsAQAuAAQKf0cABBMACQk+JNgEADQDABMACQk+JNgEADQDAAkABQm5CObxAKkAABQABQmOBskyAH4AAAAA.Belfour:BAAALgAECgEJAgAAAA==.Bera:BAAALgAECgUJDwABLgAECgkJAgAIAAAAAA==.Beramage:BAAALgAECgEJAQAAAA==.',
Bi='Billybobjr:BAABLgAECn8+AAINAAgJGyGFCwDqAgANAAgJGyGFCwDqAgAAAA==.Bippitybop:BAAALgAECgEJAQAAAA==.',
Bl='Blackbart:BAAALgADCgcJCgAAAA==.',
Bo='Boamere:BAABLgAECn8uAAIVAAgJCRrsDAAFAgAVAAgJCRrsDAAFAgAAAA==.Botemedel:BAAALgADCgEJAQAAAA==.',
Br='Braided:BAAALgAECgIJAwAAAA==.Brakkar:BAABLgAECn8+AAIWAAkJ7BKfDwAnAgAWAAkJ7BKfDwAnAgAAAA==.Brandish:BAAALgADCgcJBwAAAA==.Breadstick:BAABLgAECn8zAAIKAAgJqyTkBQBNAwAKAAgJqyTkBQBNAwAAAA==.Brevik:BAAALgADCgMJAwAAAA==.Brutaal:BAAALgADCgcJCwAAAA==.Brynhild:BAAALgAFFAIJAwAAAA==.Brütaal:BAABLgAECn8hAAMNAAcJphePLwDcAQANAAcJphePLwDcAQAOAAQJ7warcgBxAAAAAA==.',
Bu='Bubsydogo:BAAALgAECgcJEQAAAA==.Buddytheelf:BAABLgAECn8qAAMCAAkJhCPYDQDSAgACAAcJOSPYDQDSAgAPAAIJiyXGJwBmAAAAAA==.Bumpyflea:BAAALgADCgUJBQAAAA==.',
Ca='Cairnsilvers:BAAALgADCgEJAQAAAA==.Camus:BAABLgAECn8aAAIJAAgJHBroRADfAQAJAAgJHBroRADfAQAAAA==.Capped:BAAALgADCgMJAwAAAA==.Catgirl:BAAALgAECgYJCAAAAA==.',
Ce='Cebollin:BAAALgAECgUJCAAAAA==.Celaian:BAAALgAECgUJCgABLgAFFAEJAQAIAAAAAA==.Celamor:BAAALgAECgQJBwAAAA==.Celasmine:BAAALgADCgYJCAAAAA==.Celpanda:BAAALgAFFAEJAQAAAA==.',
Ch='Chamoan:BAAALgAECgMJAwAAAA==.Charlamayne:BAAALgADCgcJBwAAAA==.Charybdia:BAABLgAECn8jAAIXAAgJbAZfkQDfAAAXAAgJbAZfkQDfAAAAAA==.Chidõri:BAACLgAFFH8TAAIOAAUJzB+ZEQBkAQAOAAUJzB+ZEQBkAQAuAAQKfy4AAw4ACQmDI0kFAEMDAA4ACQmDI0kFAEMDABgAAgnPFuUlAHkAAAAA.Chimerå:BAAALgADCgEJAQAAAA==.Chopstix:BAAALgADCgcJBwAAAA==.Chudlock:BAAALgAECgYJEgAAAA==.Chunna:BAABLgAECn8sAAIFAAkJnR8JCQCgAgAFAAkJnR8JCQCgAgAAAA==.Chunni:BAABLgAECn8hAAIFAAkJHApSKABcAQAFAAkJHApSKABcAQAAAA==.',
Ci='Cilicia:BAAALgADCgUJBQAAAA==.',
Co='Codap:BAAALgADCgcJBwAAAA==.Coolerfrieza:BAAALgAECgUJCwAAAA==.',
Cp='Cpr:BAABLgAECn8XAAITAAcJiCGvDwCXAgATAAcJiCGvDwCXAgAAAA==.',
Cr='Crayonman:BAAALgAECgMJAwABLgAECgkJLgAWAHkkAA==.Crepic:BAAALgAECgQJBAAAAA==.Cruelkitty:BAABLgAECn8gAAMZAAgJIAXHHQCTAAAaAAYJzgbEOgCqAAAZAAgJMgHHHQCTAAAAAA==.',
Cu='Cudibandit:BAAALgADCgcJDwAAAA==.',
Cy='Cynaria:BAAALgAECgEJAgABLgAFFAIJBQAKADobAA==.Cyralai:BAACLgAFFH8uAAIKAAgJQReDAwCzAgAKAAgJQReDAwCzAgAuAAQKfxkAAgoACQlQIfEQALACAAoACQlQIfEQALACAAAA.',
Da='Dabofdeath:BAAALgAECgIJAgAAAA==.Dalov:BAABLgAECn8gAAMTAAcJSSbxBwDvAgATAAcJSSbxBwDvAgAJAAIJbx15/wCYAAAAAA==.Dankley:BAABLgAECn8WAAIbAAgJYQfTRAAaAQAbAAgJYQfTRAAaAQAAAA==.Darkestnyte:BAAALgAECggJDwAAAA==.Darkk:BAAALgAECgQJDAAAAA==.Darkpalidin:BAAALgAECgYJBgABLgAECggJKAAEAD4bAA==.Darkrhaenies:BAAALgADCgcJBwAAAA==.Darkwindx:BAAALgADCggJCQABLgAECgUJBwAIAAAAAA==.Datezero:BAAALgADCgQJBAAAAA==.',
Dd='Ddream:BAAALgADCgQJBAAAAA==.',
De='Deadhealer:BAAALgADCgMJBQAAAA==.Deafknighte:BAAALgAECgMJAwAAAA==.Deathboi:BAABLgAECn8pAAILAAgJRhdpOQAGAgALAAgJRhdpOQAGAgAAAA==.Deathburgur:BAABLgAECn8YAAMLAAkJqg/+aQB+AQALAAgJehD+aQB+AQAMAAcJpQsGEQAzAQAAAA==.Deathfromme:BAAALgAECgYJCgAAAA==.Deathstro:BAAALgAECgYJDgABLgAECgkJKgALADscAA==.Decayed:BAAALgAECgUJDgAAAA==.Demonicuss:BAAALgAECgEJAQAAAA==.Demontress:BAAALgADCgQJBAAAAA==.Dentridios:BAAALgADCgIJAgAAAA==.Deson:BAABLgAECn8kAAMTAAgJrRBeOABTAQATAAgJrRBeOABTAQAJAAUJiQhf9wCiAAAAAA==.Deviantart:BAAALgAECgQJBAAAAA==.',
Di='Diana:BAABLgAECn8jAAIHAAgJjQ5WUgCTAQAHAAgJjQ5WUgCTAQAAAA==.Diietriich:BAABLgAECn8tAAIEAAgJRSJpHQCWAgAEAAgJRSJpHQCWAgAAAA==.Dilligaaf:BAAALgADCgMJAwAAAA==.',
Do='Docbeanz:BAAALgADCgMJAwAAAA==.Donkypunch:BAAALgADCgQJBAAAAA==.Dontjudgemê:BAAALgADCgIJAgAAAA==.Dopie:BAAALgADCgIJAgAAAA==.Dorcina:BAAALgAECgIJAgAAAA==.',
Dr='Dracthyr:BAAALgADCgUJDQAAAA==.Dragoondpain:BAAALgAECgQJCwAAAQ==.Draltina:BAABLgAECn8XAAMBAAgJPAmkDQBaAQABAAgJPAmkDQBaAQACAAEJywLtLwEhAAAAAA==.Drazira:BAAALgAECgcJEAAAAA==.Drugonwerier:BAAALgADCgEJAgAAAA==.Drunkbera:BAAALgAECgcJBwAAAA==.Druzzlek:BAAALgAECgEJAQAAAA==.',
Du='Dunks:BAABLgAFFH8FAAICAAMJJwMAewCwAAACAAMJJwMAewCwAAAAAA==.',
Dy='Dylghoul:BAAALgADCgUJBQAAAA==.',
['Dí']='Dírac:BAABLgAFFH8FAAICAAMJMA1UagDWAAACAAMJMA1UagDWAAAAAA==.',
Ec='Eclipsekitty:BAAALgAECgQJBAABLgAFFAMJBQATAOgPAA==.',
Ed='Edwillei:BAAALgAECgUJCAAAAA==.',
Ef='Efforex:BAAALgADCgQJBAAAAA==.',
El='Elactoplasm:BAAALgAECgMJAwAAAA==.Elderslapaho:BAAALgADCgMJAwAAAA==.Ellistrae:BAAALgAECgUJBQAAAA==.Ellysia:BAAALgADCgEJAQAAAA==.',
Em='Emmel:BAAALgADCggJCwAAAA==.',
Eq='Equeslucis:BAAALgAECgcJBwAAAA==.',
Er='Erodrana:BAAALgAECgYJEgABLgAECgcJEAAIAAAAAA==.Eromir:BAAALgAECgUJCgAAAA==.Eryi:BAABLgAECn83AAIDAAkJkRbTEwBcAgADAAkJkRbTEwBcAgAAAA==.',
Et='Ethan:BAABLgAECn8eAAMcAAkJnRuODwDdAQAcAAcJIRiODwDdAQAbAAQJ6CKaTQD5AAAAAA==.',
Ev='Evonari:BAAALgADCgIJAgAAAA==.',
Ex='Exoticfrost:BAAALgADCgIJAgAAAA==.Expertnewb:BAAALgAECgIJAgABLgAECggJKAAEAD4bAA==.',
['Eí']='Eísheth:BAAALgADCgUJBAAAAA==.',
Fa='Faegen:BAAALgAECgEJAgAAAA==.Falkønn:BAAALgAECgMJAwAAAA==.Fangytooth:BAABLgAECn8uAAIWAAkJeSQxAgAeAwAWAAkJeSQxAgAeAwAAAA==.Fashaun:BAAALgAECgIJAgAAAA==.Faze:BAABLgAECn8UAAIEAAYJ0B0YcwB5AQAEAAYJ0B0YcwB5AQAAAA==.',
Fe='Fellamayyne:BAAALgADCgEJAQAAAA==.Ferrus:BAACLgAFFH8aAAMXAAgJXh+rAwD9AQAXAAgJXh+rAwD9AQAaAAQJyBmKGACdAAAuAAQKfx4AAxoACQn1JdANAIYCABcACQlWJOwcAKQCABoABwncJNANAIYCAAAA.',
Ff='Ffleuderflam:BAAALgAECgYJBgAAAA==.',
Fr='Frose:BAAALgADCgEJAQAAAA==.Frostyblast:BAAALgADCgUJBgAAAA==.',
Fu='Fupacabra:BAAALgADCgEJAQAAAA==.Furiosity:BAAALgAECgMJBQAAAA==.Fuzzybear:BAAALgAECgcJCAABLgAECgkJLgAWAHkkAA==.Fuzzybeard:BAAALgAECgYJBgABLgAECgkJLgAWAHkkAA==.Fuzzywar:BAAALgAECgYJBgABLgAECgkJLgAWAHkkAA==.',
Ga='Gabomonk:BAABLgAFFH8FAAIGAAIJ1iSpMADPAAAGAAIJ1iSpMADPAAAAAA==.Gamalia:BAAALgADCgUJBQAAAA==.Garudekhan:BAAALgADCgUJBQAAAA==.',
Ge='Genreallee:BAABLgAECn8dAAIJAAcJ1hKDfABaAQAJAAcJ1hKDfABaAQAAAA==.Gernab:BAAALgADCgYJBgAAAA==.',
Gh='Ghost:BAABLgAECn8WAAIKAAYJ9xt+NgDOAQAKAAYJ9xt+NgDOAQAAAA==.',
Gi='Gianna:BAABLgAECn8XAAMTAAkJ7CNBAgB7AwATAAkJ7CNBAgB7AwAJAAIJCR4O+wCdAAAAAA==.Gizzar:BAAALgADCgYJCgAAAA==.',
Gl='Glau:BAAALgAECgQJBAABLgAECggJCAAIAAAAAA==.Glimpsed:BAAALgAECgcJDgABLgAECgkJAgAIAAAAAA==.Globgore:BAAALgADCgIJBAAAAA==.Gloçk:BAAALgAECgMJCAABLgAECgYJEQAIAAAAAA==.',
Go='Goofy:BAABLgAECn8fAAIJAAcJYCHDJACUAgAJAAcJYCHDJACUAgAAAA==.Goor:BAAALgAECgEJAQAAAA==.Gorrik:BAAALgADCgUJBQAAAA==.',
Gr='Graeae:BAAALgAECgcJBwAAAA==.Greyfeather:BAAALgADCgEJAgAAAA==.Grimeace:BAAALgADCgQJBAAAAA==.',
Gu='Gunduin:BAABLgAECn8eAAIHAAgJriAUHgBRAgAHAAgJriAUHgBRAgAAAA==.',
Gw='Gweb:BAAALgAECgIJAgAAAA==.',
Gy='Gyda:BAABLgAECn8hAAISAAcJcCELDACQAgASAAcJcCELDACQAgAAAA==.Gyuyuki:BAABLgAECn87AAIOAAgJxxFkKgCGAQAOAAgJxxFkKgCGAQAAAA==.',
Ha='Hakuanah:BAAALgADCgEJAQAAAA==.Halvorak:BAAALgADCgcJCgAAAA==.Harryp:BAABLgAECn8yAAMdAAkJqRTWGgDmAQAdAAkJ5RLWGgDmAQAeAAkJ/BAjCACfAQAAAA==.Hast:BAAALgAECgYJEgAAAA==.',
He='Hearthzilla:BAAALgAECgEJAQABLgAECgkJIQAOANgfAA==.Heidie:BAAALgAECgUJBQAAAA==.Hellsbow:BAAALgAECgYJDgAAAA==.Hermin:BAAALgADCgQJCAAAAA==.',
Ho='Holyhellz:BAAALgADCgEJAQAAAA==.Honeyboo:BAAALgAECgUJBQABLgAFFAMJBQAKAK8LAA==.Hots:BAAALgADCgcJBwAAAA==.Hotzz:BAAALgAECgEJAQAAAA==.',
Hr='Hraesvelgr:BAAALgADCggJBwAAAA==.',
Hu='Huntavious:BAACLgAFFH8IAAIWAAQJGxS0DQBLAQAWAAQJGxS0DQBLAQAuAAQKfzQABBYACQk8H1gEAN4CABYACQk8H1gEAN4CAAcABgnjGsZeAEsBAB8AAQnIE9uKADAAAAAA.',
['Hë']='Hëllen:BAABLgAECn8YAAIJAAYJMiDaaQCrAQAJAAYJMiDaaQCrAQAAAA==.',
['Hú']='Húñtrèss:BAAALgAECgIJAgAAAA==.',
Ia='Iamshinigamy:BAAALgAECgIJAgABLgAECgcJFwAEAPMaAA==.',
Ii='Iichimaru:BAAALgAECgUJBQAAAA==.',
Il='Illidupe:BAAALgADCgMJAwAAAA==.',
In='Inaoh:BAAALgAECgQJBgAAAA==.',
Iv='Ivey:BAABLgAECn8qAAIKAAgJRh6zEgClAgAKAAgJRh6zEgClAgAAAA==.',
Iz='Izes:BAAALgAECgEJAQAAAA==.',
Ja='Jaagganug:BAAALgADCgMJAwAAAA==.Jacenne:BAABLgAECn8ZAAIgAAYJ1QOzWQCPAAAgAAYJ1QOzWQCPAAAAAA==.Jairus:BAAALgAECgcJBwAAAA==.',
Jd='Jdirty:BAABLgAECn8YAAIhAAYJhAnaEADhAAAhAAYJhAnaEADhAAAAAA==.',
Je='Jellytime:BAAALgAECgMJBQAAAA==.',
Jo='Josephyn:BAAALgAECgMJAwABLgAFFAYJLAANAKgfAA==.',
Ju='Jugernaut:BAAALgAECgEJAQAAAA==.Jumpmann:BAAALgAECgMJAwAAAA==.Justdesserts:BAAALgAECgEJAQAAAA==.Justix:BAAALgADCggJEwAAAA==.',
Ka='Kadaffy:BAAALgAECgEJAgAAAA==.Kakusu:BAAALgAECgYJEQAAAA==.Kakuta:BAAALgAECgUJDwABLgAECgkJGQAOAA4dAA==.Kakutá:BAABLgAECn8ZAAIOAAkJDh12CgCkAgAOAAkJDh12CgCkAgAAAA==.Kalru:BAAALgADCgQJDAAAAA==.Kargar:BAAALgAECgEJAgAAAA==.Katharsis:BAACLgAFFH8JAAIJAAMJwQuyXgDRAAAJAAMJwQuyXgDRAAAuAAQKfyEAAgkACQnPFs08APkBAAkACQnPFs08APkBAAAA.',
Ke='Keba:BAAALgADCggJDwABLgAFFAUJGgATAEUiAA==.Keit:BAAALgADCgYJBgABLgAECggJIQAaALYhAA==.Keévs:BAAALgADCgQJBAAAAA==.',
Kh='Khalidisi:BAABLgAECn8uAAQUAAkJFR+fBQB9AgAUAAgJsR+fBQB9AgATAAkJLRmIKgClAQAJAAcJJArXrgAFAQAAAA==.Khaliesi:BAAALgADCgIJAgAAAA==.Khalizar:BAABLgAFFH8IAAIbAAQJGQeyJAAEAQAbAAQJGQeyJAAEAQAAAA==.Kharazim:BAAALgADCgEJAQABLgAECggJKAAXAJEbAA==.Khenja:BAAALgAECgEJAQAAAA==.Khál:BAAALgADCgYJBgAAAA==.',
Ki='Killerelf:BAAALgAECgcJCQAAAA==.Kittie:BAAALgADCggJCAAAAA==.',
Kk='Kkiilleerr:BAAALgAECgYJDwAAAA==.',
Ko='Kobbaltcilar:BAAALgAECgUJBgAAAA==.Koraleena:BAAALgAECgQJBAAAAA==.Korbo:BAABLgAECn8oAAMOAAgJ/RyHJgCdAQAOAAUJeR6HJgCdAQANAAUJOhZpWgAvAQAAAA==.Korbulo:BAAALgAFFAIJAgAAAA==.Korlothel:BAABLgAECn8kAAIUAAkJvAeCHQAPAQAUAAkJvAeCHQAPAQABLgAFFAMJAwAIAAAAAA==.Korrith:BAAALgADCgIJAgAAAA==.',
Kr='Krumpus:BAABLgAECn8aAAIXAAgJrQ/xTwB+AQAXAAgJrQ/xTwB+AQAAAA==.',
Ku='Kungfuuy:BAABLgAECn8fAAIGAAgJsR9KDgBCAgAGAAgJsR9KDgBCAgAAAA==.Kurtevade:BAAALgAECgQJDAAAAA==.',
Kw='Kwetnepthl:BAAALgAECgEJAgAAAA==.',
Ky='Kynsong:BAABLgAECn8UAAIQAAcJXhBSKgBgAQAQAAcJXhBSKgBgAQAAAA==.',
['Kà']='Kàlbrews:BAABLgAECn9AAAIGAAkJvyY0AACKAwAGAAkJvyY0AACKAwAAAA==.Kàrmâ:BAAALgAECgUJBQAAAA==.',
La='Lagk:BAAALgADCgkJCQAAAA==.Lainiee:BAAALgADCgEJAQAAAA==.Lavismad:BAECLgAFFH8FAAIbAAMJmRu1HgAiAQAbAAMJmRu1HgAiAQAuAAQKfzQABBsACQkMJU0DACcDABsACQnYJE0DACcDABUABwmhII4NAPoBABwAAQlGJXcyAGkAAAAA.Lavoc:BAEALgADCgcJBwABLgAFFAMJBQAbAJkbAA==.Lavv:BAEALgAECgYJCAABLgAFFAMJBQAbAJkbAA==.Lavz:BAEALgAECgYJBgABLgAFFAMJBQAbAJkbAA==.',
Le='Legendary:BAAALgAECgYJDQAAAA==.Leshah:BAAALgAECgQJBgAAAA==.',
Li='Lichkingdied:BAAALgADCgUJBQAAAA==.Lightndpain:BAAALgAECgQJBgABLgAECgQJCwAIAAAAAA==.Lilypetal:BAAALgAECgQJBwAAAA==.Lionaest:BAAALgADCgIJAgAAAA==.Littlebucket:BAAALgADCgEJAQAAAA==.',
Lo='Lockdpain:BAAALgAECgYJGAABLgAECgQJCwAIAAAAAQ==.Logov:BAAALgAECgYJDwAAAA==.Loraine:BAAALgAECgEJAQAAAA==.Loìsbethe:BAAALgAECgQJBAAAAA==.',
Lu='Luciferra:BAAALgAECggJDAABLgAFFAYJLAANAKgfAA==.Lukey:BAAALgAECgMJAwAAAA==.Lunartemis:BAAALgAECgUJCAABLgAFFAQJCwAiAK8eAA==.Luu:BAAALgAECgMJBQAAAA==.',
['Lö']='Lörax:BAAALgADCgQJBQAAAA==.',
['Lû']='Lûnafreya:BAAALgAECggJEgAAAA==.',
Ma='Maelera:BAAALgADCgkJDAAAAA==.Maetromundo:BAAALgAECgEJAQAAAA==.Magentas:BAAALgADCgIJAgAAAA==.Magickul:BAAALgADCggJCAAAAA==.Mahlah:BAAALgAECgQJBAAAAA==.Malaboo:BAAALgAECgEJAQABLgAFFAMJBQAKAK8LAA==.Malabooty:BAAALgAECgYJBgABLgAFFAMJBQAKAK8LAA==.Maletsy:BAAALgAECgEJAQABLgAECggJHgAHAK4gAA==.Maliboo:BAACLgAFFH8FAAIKAAMJrwv+PACtAAAKAAMJrwv+PACtAAAuAAQKfzkAAwoACQlEIgIEAHIDAAoACQlEIgIEAHIDACAAAgmfCXV/ADMAAAAA.Maxamus:BAABLgAECn8UAAMcAAUJfSD/EgBzAQAcAAUJfSD/EgBzAQAVAAUJzBh6JAD0AAAAAA==.Maxigooner:BAAALgAECgYJCQABLgAFFAUJGwAJALAlAA==.',
Mc='Mcflurry:BAAALgAECgUJCwAAAA==.',
Me='Medarisa:BAAALgAECgYJCwAAAA==.Medavia:BAAALgADCgUJBQAAAA==.Mederia:BAAALgAECgUJBQAAAA==.Medívh:BAAALgADCgEJAQAAAA==.Melisandr:BAAALgAECgMJBQAAAA==.Merkenier:BAABLgAECn8lAAIgAAgJyBGeJQCGAQAgAAgJyBGeJQCGAQAAAA==.Merkur:BAAALgAECgYJBgABLgAECggJJQAgAMgRAA==.',
Mi='Midnitehunt:BAAALgAECgQJBAAAAA==.Miragia:BAAALgAECgUJBwAAAA==.Missmayhem:BAAALgAECgUJCAAAAA==.Missmayhemm:BAAALgADCgQJBgAAAA==.',
Mo='Modifiedmix:BAABLgAECn8kAAIHAAgJixfMLAATAgAHAAgJixfMLAATAgAAAA==.Modsabadtank:BAAALgAECgYJCwABLgAECggJJAAHAIsXAA==.Mokomohama:BAAALgAECgcJBwAAAA==.Monatazumaa:BAAALgAECgEJAgAAAA==.Moonbloom:BAAALgAFFAEJAQABLgAFFAYJLAANAKgfAA==.Mopeezie:BAAALgAECgEJAQAAAA==.Mordicant:BAAALgADCgEJAQABLgAECgYJCAAIAAAAAA==.Morella:BAABLgAECn81AAIPAAcJmQ4HGQCDAQAPAAcJmQ4HGQCDAQAAAA==.',
Mu='Mucduck:BAAALgADCgEJAQAAAA==.Mustakrakish:BAAALgAECgEJAQAAAA==.Mustaz:BAAALgAECgkJBQAAAA==.',
My='Mym:BAAALgADCgcJBAAAAA==.Mystics:BAAALgAECgUJBQAAAA==.Mythrunduil:BAAALgADCgEJAQAAAA==.',
['Må']='Mågi:BAAALgAECgcJBwAAAA==.',
['Mé']='Médb:BAABLgAECn8sAAMEAAgJuxwsLgBKAgAEAAgJQBwsLgBKAgAjAAMJFR3zBwDuAAAAAA==.',
Na='Naste:BAAALgAECgUJBQAAAA==.Nathrold:BAAALgAECgIJBAABLgAECgYJEQAIAAAAAA==.',
Ne='Neptune:BAACLgAFFH8sAAINAAYJqB96CAAHAgANAAYJqB96CAAHAgAuAAQKfyEAAw0ACQlRIhgHAAIDAA0ACQlRIhgHAAIDAA4ABwkkDtE0AIQBAAAA.Nerfdks:BAAALgAECggJCwAAAA==.Nerfpaladins:BAABLgAECn8kAAQUAAcJpRIkIQDwAAAJAAYJthE/rAAJAQAUAAcJJBEkIQDwAAATAAMJzATrbQBiAAAAAA==.Neruess:BAAALgADCgUJBQAAAA==.Nezzuko:BAAALgAECgcJBwAAAA==.',
Ni='Nightbird:BAABLgAECn8dAAMkAAcJvBefDgAsAQAiAAcJThdCJwBAAQAkAAYJ8BWfDgAsAQABLgAECggJCAAIAAAAAA==.Ninediewatt:BAAALgAECgMJBAAAAA==.Nivella:BAAALgAECgYJCgAAAA==.Nixaana:BAAALgAECgQJBQAAAA==.Niçki:BAAALgADCgMJAwAAAA==.',
No='Notlockz:BAAALgADCgIJAgAAAA==.Novah:BAAALgADCgQJBQAAAA==.Noydb:BAAALgADCgYJBgABLgAECggJLgAVAAkaAA==.',
Nu='Nuah:BAAALgADCgYJDQAAAA==.',
Ny='Nyxsia:BAEALgAFFAEJAQABLgAFFAcJHAAbAJAdAA==.',
['Nè']='Nèo:BAAALgADCgcJBwAAAA==.',
Ob='Obayi:BAABLgAECn8qAAIHAAcJwwuYbwBJAQAHAAcJwwuYbwBJAQAAAA==.',
Og='Ogmadmonk:BAACLgAFFH8MAAIaAAMJnRLJEwDVAAAaAAMJnRLJEwDVAAAuAAQKfzEAAhoACQmUISIHAKUCABoACQmUISIHAKUCAAAA.',
Ok='Oktobra:BAABLgAECn8VAAIJAAYJAQONCwGIAAAJAAYJAQONCwGIAAAAAA==.',
On='Onetrickpony:BAAALgADCgYJCQAAAA==.Onos:BAAALgAECgIJAgAAAA==.Onosm:BAAALgAECgQJBAAAAA==.',
Or='Orangevoker:BAAALgAECgcJCwABLgAECgkJIQAOANgfAA==.Orioan:BAAALgAECgUJCQAAAA==.Orux:BAAALgAECgYJBgAAAA==.',
Os='Osenya:BAAALgAECgYJBgABLgAFFAMJBQALAJofAA==.Osun:BAAALgADCggJCwAAAA==.',
Ou='Ouroboro:BAAALgADCgUJBQAAAA==.',
Ow='Owlbat:BAAALgAECgEJAQAAAA==.',
Pa='Padremort:BAAALgADCgYJBgAAAA==.Palantyr:BAABLgAECn9fAAIOAAgJvRqZGgA+AgAOAAgJvRqZGgA+AgAAAA==.Paly:BAAALgAECgEJAQAAAA==.Para:BAAALgAECgQJBAAAAA==.Patrician:BAABLgAECn8oAAIhAAgJdBYeBgDhAQAhAAgJdBYeBgDhAQAAAA==.',
Pe='Peehat:BAAALgADCgcJCQAAAA==.Penutbutter:BAAALgAECgQJBwAAAA==.Pepegasus:BAAALgADCgcJBwAAAA==.',
Ph='Phobos:BAAALgADCgQJCAAAAA==.Phyloren:BAAALgADCgUJBgAAAA==.',
Pi='Pigsticker:BAAALgAECgQJBQAAAA==.Pixyfire:BAAALgAECgYJCgABLgAFFAMJBQATAOgPAA==.',
Po='Poisonleaf:BAAALgAECgUJBgABLgAECgYJGAAJADIgAA==.Pokingharder:BAABLgAECn8aAAIkAAkJhhTjBAAkAgAkAAkJhhTjBAAkAgABLgAFFAMJCgABAA0WAA==.',
Pu='Pulcherrimus:BAAALgAECgEJAwAAAA==.Purgeem:BAAALgADCgUJBQAAAA==.Pushpop:BAAALgAECgYJDwABLgAECggJXwAOAL0aAA==.',
Pw='Pwiest:BAAALgADCgcJEAAAAA==.',
Qu='Quetzalcoatl:BAABLgAECn8ZAAIlAAgJkBnRCgAdAgAlAAgJkBnRCgAdAgAAAA==.',
Ra='Raambox:BAAALgAECgQJBAAAAA==.Radak:BAAALgAECgEJAQAAAA==.Raddish:BAABLgAECn8VAAIQAAYJhhD5OgD0AAAQAAYJhhD5OgD0AAAAAA==.Rahjlynn:BAAALgADCgcJBwAAAA==.Rahken:BAAALgAECgcJBwAAAA==.Raiinn:BAAALgADCgUJBQAAAA==.Raylee:BAACLgAFFH8FAAMBAAMJSRslBgD7AAABAAMJ1BElBgD7AAAPAAIJ4xs/DgCqAAAuAAQKfz4ABAIACQmeIaQRALICAAIACAmxH6QRALICAA8ABwl8IQ8IAEQCAAEAAwk2GvQVAPIAAAAA.Razuki:BAACLgAFFH8FAAITAAMJ6A8kKwC5AAATAAMJ6A8kKwC5AAAuAAQKfzQAAxMACQmLInIEAEEDABMACQmLInIEAEEDAAkABwn2F4VnAIYBAAAA.',
Re='Remyl:BAAALgADCggJCAAAAA==.Reynia:BAAALgAECgEJAQAAAA==.',
Rf='Rfd:BAAALgADCgcJBwABLgAECggJEwAIAAAAAA==.',
Rh='Rhaenies:BAAALgAECgYJEAAAAA==.Rharr:BAAALgADCgkJDAAAAA==.Rhovanion:BAAALgAECgUJCQAAAA==.Rhuac:BAABLgAECn8lAAIKAAkJeRM8JwACAgAKAAkJeRM8JwACAgAAAA==.',
Ri='Risakah:BAAALgAECggJCQAAAA==.',
Ro='Rorschach:BAAALgAECgcJCgAAAA==.Rosefist:BAEALgADCgcJCAABLgAFFAYJEAASAKcSAA==.Rosemourne:BAEALgAECgIJAgABLgAFFAYJEAASAKcSAA==.Roseykat:BAABLgAECn8kAAIHAAcJBwy2cwBAAQAHAAcJBwy2cwBAAQAAAA==.Roshwyn:BAABLgAECn8UAAIHAAgJHgvQYQBqAQAHAAgJHgvQYQBqAQAAAA==.Rottedmeat:BAAALgAECgYJCgAAAA==.',
Ru='Rubmytotems:BAAALgAECgQJBAAAAA==.Ruckus:BAABLgAECn8nAAIJAAgJuRYPPwApAgAJAAgJuRYPPwApAgAAAA==.',
Sa='Saberwar:BAAALgAECgEJAQABLgAECgMJAwAIAAAAAA==.Saintfury:BAAALgAECgQJBQAAAA==.Saintsfear:BAABLgAECn8oAAIbAAgJTBArKwCUAQAbAAgJTBArKwCUAQAAAA==.Sanchito:BAAALgADCgMJAwAAAA==.Saphalia:BAAALgADCgMJAwAAAA==.Saradomin:BAAALgADCgUJBAAAAA==.Sareenastar:BAACLgAFFH8FAAIQAAMJayIbEAArAQAQAAMJayIbEAArAQAuAAQKfy4AAxAACQmUJjsAAOkDABAACQmUJjsAAOkDABEAAQnfCf55ADAAAAAA.Sasae:BAABLgAECn8XAAIGAAYJyhCeQADnAAAGAAYJyhCeQADnAAAAAA==.',
Sc='Scorias:BAAALgADCgQJAwAAAA==.',
Se='Selisztraza:BAAALgADCgEJAQAAAA==.Sephiróth:BAAALgADCgUJCAAAAA==.Sereni:BAAALgADCgQJBAAAAA==.Serenity:BAAALgAECgcJDAAAAA==.Serenitynow:BAAALgAECgEJAgAAAA==.Sewald:BAAALgAECgcJCwAAAA==.',
Sh='Shadowzbane:BAAALgAECgIJAgAAAA==.Shahasha:BAAALgADCgEJAQAAAA==.Shaidarharan:BAAALgADCgIJAgAAAA==.Shakeybop:BAAALgAECgQJBAAAAA==.Shalen:BAABLgAECn8oAAQdAAkJCBQwHADcAQAdAAkJ/BMwHADcAQAeAAYJoQ2ZHQBCAQAlAAQJsw4PKgCBAAAAAA==.Sharker:BAAALgADCgYJBgAAAA==.Sharpie:BAAALgADCgcJCgAAAA==.Sheer:BAABLgAECn8UAAIGAAgJYB89DQBPAgAGAAgJYB89DQBPAgAAAA==.Sheraa:BAABLgAECn8hAAIUAAgJrxHoEgCBAQAUAAgJrxHoEgCBAQAAAA==.Shiftystrike:BAABLgAECn8WAAImAAcJPx/wCgAVAgAmAAcJPx/wCgAVAgAAAA==.Shifushield:BAAALgAECgcJCAAAAA==.Shireshannon:BAABLgAECn8VAAIHAAYJeglZjwAGAQAHAAYJeglZjwAGAQAAAA==.Shrunkador:BAACLgAFFH8QAAIOAAQJMg35IQD7AAAOAAQJMg35IQD7AAAuAAQKfysAAg4ACQmQHbEWABcCAA4ACQmQHbEWABcCAAAA.',
Si='Silk:BAAALgAECgYJDgAAAA==.Silmarkthree:BAACLgAFFH8FAAIEAAMJlQ83cADhAAAEAAMJlQ83cADhAAAuAAQKfzQAAgQACQmkGEszADMCAAQACQmkGEszADMCAAAA.Sinbåd:BAAALgAECgcJCAAAAA==.Siodar:BAAALgADCgEJAQABLgAECgIJAgAIAAAAAA==.Sisterstar:BAAALgADCgMJAwAAAA==.',
Sl='Sleety:BAAALgAECgIJBQAAAA==.Slipknoth:BAACLgAFFH8cAAMSAAcJuQ/SEQC9AQASAAYJ3g3SEQC9AQARAAYJtBq3CgCKAQAuAAQKfyoABBEACQkpIbwZANsBABEABwnDJLwZANsBABAABwntF/kgANsBABIABAnOGd89AOsAAAAA.',
Sn='Snekhain:BAAALgADCgMJAwAAAA==.Snuffaluffa:BAAALgAECgMJAwAAAA==.',
So='Somatra:BAAALgADCgkJCQAAAA==.Sorean:BAACLgAFFH8RAAIWAAUJxxvsCQBnAQAWAAUJxxvsCQBnAQAuAAQKfy8ABAcACQm+IFYhAD0CAAcABwlUG1YhAD0CABYABwlnHQEXAN0BAB8ABwlQGv0vALUBAAAA.',
Sp='Specialmove:BAAALgAFFAEJAgAAAA==.Spookydookie:BAAALgADCgkJCgAAAA==.',
St='Staghealz:BAAALgAECgIJAgAAAA==.Starfallin:BAAALgAECgkJAgAAAA==.Stifs:BAABLgAECn8iAAIUAAgJRBEEFwBlAQAUAAgJRBEEFwBlAQAAAA==.Stilleena:BAAALgAECgYJBgAAAA==.Stinkinglily:BAAALgAECgEJAgAAAA==.Strunrage:BAEALgAECgcJDAABLgAECgkJPQAJAIskAA==.Stÿx:BAABLgAECn8ZAAInAAYJ6gX6OQCSAAAnAAYJ6gX6OQCSAAABLgAECggJDwAIAAAAAA==.',
Su='Sugarbomb:BAAALgADCgMJBAAAAA==.',
Sy='Sykotyk:BAAALgAECgkJDwAAAA==.Sylverfox:BAAALgAECgMJAwABLgAECgkJFQATACscAA==.Synchestra:BAAALgADCgcJCgAAAA==.',
Ta='Tadagain:BAABLgAECn8aAAMJAAUJ1hJgxgDiAAAJAAUJ1hJgxgDiAAATAAQJ2gV2dgChAAAAAA==.Tagrith:BAAALgADCgMJAwAAAA==.Tankybears:BAACLgAFFH8FAAIKAAIJOhv6PACtAAAKAAIJOhv6PACtAAAuAAQKfywAAyAACQnOGtMOAFkCACAACQnOGtMOAFkCAAoACAnqG0pOAEMBAAAA.Tarmalok:BAAALgAECgEJAQAAAA==.Tazera:BAAALgAECgUJCwAAAA==.',
Te='Telekinesis:BAABLgAECn8iAAIWAAgJvhBdHQCjAQAWAAgJvhBdHQCjAQAAAA==.Tenara:BAAALgAFFAIJAgABLgAFFAIJBQAKADobAA==.Tenbinza:BAAALgAECgMJBQAAAA==.Teos:BAABLgAECn8wAAIYAAkJCBl2BwA6AgAYAAkJCBl2BwA6AgAAAA==.',
Th='Thainé:BAAALgAECgMJBgAAAA==.Thaldrassian:BAAALgADCgQJBAAAAA==.Tharris:BAAALgAECgYJCAAAAA==.Thehatred:BAAALgADCgYJBgAAAA==.Therondar:BAAALgADCgEJAQAAAA==.Thiyan:BAAALgADCgMJAwAAAA==.Tholin:BAAALgAECgcJCgAAAA==.Thromar:BAABLgAECn8VAAIEAAcJiBWvgADPAQAEAAcJiBWvgADPAQAAAA==.Thunderlily:BAABLgAECn8oAAMEAAgJPhsNMQA9AgAEAAgJeRoNMQA9AgAoAAcJchfpBgCgAQAAAA==.Thünder:BAAALgADCgcJBwABLgAECgcJFgALAKQeAA==.',
Ti='Tinderbeef:BAAALgADCgcJCAAAAA==.Tinychaos:BAAALgAECgkJCQAAAA==.Tinyround:BAAALgAECgEJAQAAAA==.Tirra:BAABLgAECn8VAAMTAAkJKxwMFwA6AgATAAkJKxwMFwA6AgAJAAIJJgZsQwFPAAAAAA==.',
To='Torama:BAAALgADCgIJAgAAAA==.Toranth:BAABLgAECn81AAITAAkJiRXtFgA8AgATAAkJiRXtFgA8AgAAAA==.Torq:BAABLgAECn8XAAIEAAYJ/BmShwDCAQAEAAYJ/BmShwDCAQABLgAECgcJFwATAIghAA==.Torqumada:BAAALgAECgkJBgAAAA==.Toxian:BAABLgAECn8qAAIXAAgJCxX5PwCyAQAXAAgJCxX5PwCyAQAAAA==.Toxicelitist:BAABLgAECn8qAAMPAAgJRg6rDQBHAQAPAAgJRg6rDQBHAQACAAEJmgGOSQEbAAAAAA==.',
Tr='Treedemon:BAACLgAFFH8FAAIXAAMJLRsbSQDyAAAXAAMJLRsbSQDyAAAuAAQKfyoAAhcACQksJKMIAPgCABcACQksJKMIAPgCAAAA.Treedin:BAAALgAECgMJAwAAAA==.Trollboi:BAAALgADCggJCAAAAA==.Tryden:BAAALgADCggJCAABLgAECggJLgAVAAkaAA==.Trymw:BAAALgADCgIJAgAAAA==.Tryst:BAAALgADCgcJBwAAAA==.',
Ty='Tybearon:BAAALgADCgcJBwAAAA==.Tyinthus:BAAALgAECgcJBwABLgAECgcJBwAIAAAAAA==.Tyreid:BAAALgAECgcJBwAAAA==.Tyrelitha:BAAALgAECgMJAwAAAA==.',
Ud='Udderchoad:BAAALgADCgEJAQAAAA==.',
Uh='Uhura:BAAALgADCgEJAQAAAA==.',
Ul='Ulfrir:BAACLgAFFH8LAAIHAAQJ2Rs5HwBeAQAHAAQJ2Rs5HwBeAQAuAAQKfyYAAwcACQk3IP0NAM4CAAcACQk3IP0NAM4CAB8AAwkxCipvAIIAAAAA.Ultradukes:BAAALgAECgMJBAAAAA==.',
Un='Unatural:BAAALgAECgUJBQAAAA==.Unleashed:BAAALgAECgUJCgAAAA==.',
Va='Valarea:BAAALgADCgEJAQAAAA==.Valock:BAAALgAECgcJDwAAAA==.Valris:BAAALgAECgMJBAAAAA==.Vandham:BAAALgADCgEJAQAAAA==.Vannis:BAAALgADCggJDgAAAA==.Vanshifty:BAACLgAFFH8FAAIKAAIJrxuIPwClAAAKAAIJrxuIPwClAAAuAAQKf0QAAgoACQk0I3EEAGcDAAoACQk0I3EEAGcDAAAA.',
Ve='Veilf:BAAALgADCgYJDAAAAA==.Velf:BAAALgAECgIJAgAAAA==.Velrus:BAAALgAECgYJDAAAAA==.Venli:BAAALgAECgEJAQAAAA==.Venombite:BAAALgADCgMJAwAAAA==.Verez:BAAALgADCgcJBwAAAA==.',
Vi='Victorion:BAAALgAECggJCAAAAA==.Viktorax:BAAALgAECgYJCwAAAA==.Vincevega:BAAALgAECgkJDgAAAA==.Virtueozo:BAABLgAECn8aAAIlAAgJEBfODwA+AgAlAAgJEBfODwA+AgAAAA==.',
Vo='Volam:BAAALgAECgQJBAAAAA==.',
Vy='Vyx:BAAALgAECggJDwAAAA==.',
Wa='Waffle:BAAALgAECgYJEwABLgAECggJGgAHAFEOAA==.Waldhorn:BAAALgAECgcJCwAAAA==.Wangwen:BAAALgADCgIJAgAAAA==.Wargue:BAABLgAECn8VAAIbAAYJjRugOADEAQAbAAYJjRugOADEAQAAAA==.',
We='Weeaboos:BAAALgADCgIJAgABLgADCgQJBAAIAAAAAA==.Weebsz:BAAALgADCgQJBAAAAA==.Welindis:BAAALgAECgYJEAABLgAECgkJLgAXAI8QAA==.Wetkith:BAAALgADCgUJBQAAAA==.',
Wi='Windrider:BAAALgADCgIJAgAAAA==.Windwraith:BAAALgAECgIJAgAAAA==.Wizzard:BAAALgAECggJHAAAAQ==.',
Xa='Xaiyara:BAAALgADCgUJBQAAAA==.Xalina:BAAALgAECgEJAQAAAA==.Xandaka:BAAALgADCgQJBAAAAA==.',
Xe='Xephir:BAAALgAECggJCgAAAA==.',
Xi='Xidied:BAABLgAECn8wAAIGAAkJJiEOBQDkAgAGAAkJJiEOBQDkAgAAAA==.Xilon:BAAALgAECgYJBgABLgAFFAMJBQALAJofAA==.Xilra:BAABLgAECn8uAAMgAAkJmiKHCgCWAgAgAAkJmiKHCgCWAgAmAAEJmhFpRAAzAAABLgAFFAMJBQALAJofAA==.Xilrot:BAABLgAFFH8FAAILAAMJmh/uZgARAQALAAMJmh/uZgARAQAAAA==.Xilzen:BAAALgAECgUJEAABLgAFFAMJBQALAJofAA==.Xinia:BAAALgAECgMJAwAAAA==.',
Xz='Xzed:BAAALgADCgEJAQAAAA==.',
Ye='Yew:BAAALgADCgMJAwAAAA==.',
Yi='Yikers:BAACLgAFFH8RAAITAAQJZiBFFQBhAQATAAQJZiBFFQBhAQAuAAQKfyUAAhMACQm6IfIHAPkCABMACQm6IfIHAPkCAAAA.',
Yr='Yridai:BAAALgAECgYJCAAAAA==.',
Za='Zani:BAAALgADCgYJBwAAAA==.Zarsher:BAAALgADCgIJAgAAAA==.',
Zd='Zdk:BAAALgAECgEJAQABLgAECggJIgAHAAMbAA==.',
Ze='Zeldy:BAABLgAECn8vAAIHAAkJJxfQKQAgAgAHAAkJJxfQKQAgAgAAAA==.Zenestraza:BAAALgADCgcJCwABLgAECggJKAAXAJEbAA==.Zenthareal:BAABLgAECn8oAAIXAAgJkRtSIwAtAgAXAAgJkRtSIwAtAgAAAA==.Zenzi:BAAALgADCgMJAwAAAA==.Zenzz:BAAALgADCgEJAQAAAA==.Zeuc:BAAALgADCgMJAwAAAA==.Zeuus:BAAALgADCgMJBAAAAA==.',
Zh='Zhirldk:BAAALgAECgcJEQAAAA==.Zhulgarosh:BAAALgADCgUJBQAAAA==.',
Zi='Zillidan:BAAALgAECgEJAwABLgAECggJIgAHAAMbAA==.',
Zm='Zmaster:BAABLgAECn8iAAIHAAgJAxt1KgAdAgAHAAgJAxt1KgAdAgAAAA==.',
Zo='Zobeast:BAAALgADCgQJBAAAAA==.',
Zr='Zret:BAAALgAECgYJCgABLgAECggJIgAHAAMbAA==.',
Zw='Zwar:BAAALgAECgEJAQABLgAECggJIgAHAAMbAA==.',
Zy='Zynith:BAAALgAECgYJBgAAAA==.',
['Zö']='Zöey:BAAALgADCgQJBQAAAA==.',
['Åp']='Åpex:BAAALgAECggJBgAAAA==.',
['Çl']='Çloudz:BAAALgADCgMJAwAAAA==.',
['Ða']='Ðark:BAACLgAFFH8PAAIHAAMJ0BFnGACmAAAHAAMJ0BFnGACmAAAuAAQKfycAAgcACQm5HAQVAI8CAAcACQm5HAQVAI8CAAAA.',
['Ðr']='Ðr:BAABLgAECn8eAAMNAAkJ/Br1IgANAgANAAcJThr1IgANAgAOAAYJ7xcVMABmAQAAAA==.',
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
