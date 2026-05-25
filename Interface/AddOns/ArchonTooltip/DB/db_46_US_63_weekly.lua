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

local lookup = {'Warlock-Affliction','Warlock-Demonology','Monk-Mistweaver','Mage-Frost','Monk-Windwalker','Monk-Brewmaster','Hunter-BeastMastery','Unknown-Unknown','Paladin-Retribution','Druid-Restoration','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Restoration','Shaman-Elemental','Priest-Holy','Priest-Shadow','Priest-Discipline','Paladin-Holy','Paladin-Protection','Warrior-Protection','Hunter-Survival','Warlock-Destruction','DemonHunter-Devourer','Shaman-Enhancement','DemonHunter-Havoc','DemonHunter-Vengeance','Warrior-Fury','Mage-Arcane','Warrior-Arms','Evoker-Augmentation','Evoker-Devastation','Hunter-Marksmanship','Druid-Balance','Rogue-Outlaw','Rogue-Subtlety','Mage-Fire','Rogue-Assassination','Evoker-Preservation','Druid-Feral','DeathKnight-Blood',}
local provider = {region='US',realm='Dawnbringer',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abdalhazred:BAACLgAFFH8SAAMBAAUJUiMXAQCJAQABAAUJUiMXAQCJAQACAAEJiR8emwBQAAAuAAQKfzQAAwEACQmYJFIAAGYDAAEACAm3JVIAAGYDAAIAAwnQHc+XAPcAAAAA.Abilus:BAAALgAECgQJDwAAAA==.Abolis:BAAALgAECgMJBQAAAA==.',
Ae='Aeldriel:BAAALgAECgMJAwAAAA==.Aeoyn:BAAALgAECgEJAQAAAA==.',
Ag='Aggar:BAAALgADCgkJCwABLgAECggJLQADANcWAA==.',
Ak='Akoa:BAAALgAECgEJAQAAAA==.',
Al='Alarak:BAABLgAECn8bAAIBAAgJcRVsCQCtAQABAAgJcRVsCQCtAQAAAA==.Alnara:BAAALgAECgEJAQAAAA==.Alvierearn:BAABLgAECn8WAAIEAAgJuxE4ewBlAQAEAAgJuxE4ewBlAQAAAA==.',
Am='Amoradis:BAAALgADCgUJEgAAAA==.',
An='Anaeir:BAAALgADCgYJBgAAAA==.Angriff:BAAALgADCgQJBQAAAA==.Anisette:BAABLgAECn8jAAMFAAcJOhpHGADGAQAFAAcJOhpHGADGAQAGAAQJDgqNXAB7AAAAAA==.Annuket:BAAALgAECgYJBgAAAA==.Anthria:BAAALgADCgkJGwAAAA==.',
Ap='Apexpredåtor:BAAALgADCgIJAgAAAA==.',
Aq='Aqurala:BAABLgAECn8eAAIHAAgJER1SJAAsAgAHAAgJER1SJAAsAgAAAA==.',
Ar='Aradem:BAAALgADCgcJBwABLgAFFAIJAgAIAAAAAA==.Aravenn:BAAALgAFFAIJAgAAAA==.Arcis:BAABLgAECn8kAAIJAAcJ0RL3dwBeAQAJAAcJ0RL3dwBeAQAAAA==.Arealis:BAAALgADCgcJDAAAAA==.Argatem:BAAALgAECgQJBAABLgAECggJKgAKAEYeAA==.Arkangel:BAABLgAECn8pAAMLAAkJXBujIgBZAgALAAkJXBujIgBZAgAMAAEJYQmZLgAnAAAAAA==.Arkharon:BAAALgADCgYJCQAAAA==.Arralyon:BAAALgADCgMJBgAAAA==.Artemesia:BAAALgAECgEJAQABLgAFFAUJKgANAM0fAA==.Arthäs:BAAALgAECgQJBAAAAA==.Aryrn:BAAALgADCgUJBQAAAA==.',
As='Asakua:BAAALgAECgMJBgAAAA==.Asiya:BAAALgAECgQJBQAAAA==.Assandra:BAAALgADCgUJBQAAAA==.',
At='Athul:BAAALgADCgUJCgAAAA==.',
Au='Aurlyn:BAAALgADCgcJDwAAAA==.',
Av='Avatartele:BAAALgAECgIJAwAAAA==.Avatartouka:BAABLgAECn8jAAMNAAgJ5yGVDADMAgANAAgJ5yGVDADMAgAOAAQJ9RM2WwCiAAAAAA==.Avianthel:BAAALgADCgMJAgAAAA==.Avraria:BAAALgAECggJDwAAAA==.Avyl:BAAALgAECgYJEAAAAA==.Avylastorica:BAAALgADCgYJBgABLgAECgYJEAAIAAAAAA==.',
Aw='Awsomninja:BAABLgAECn8kAAIGAAkJAiMGBADxAgAGAAkJAiMGBADxAgAAAA==.',
Ax='Axxain:BAAALgADCgkJGgAAAA==.',
Az='Azaralle:BAAALgADCgEJAQAAAA==.Azeazal:BAAALgAECgYJEAAAAA==.Azlifan:BAAALgADCgQJBAAAAA==.Azorthragal:BAAALgADCgYJBgAAAA==.',
Ba='Baddlandss:BAAALgAECgQJCAAAAA==.Bagador:BAAALgAECgYJCQAAAA==.Bastais:BAAALgAECgEJAQAAAA==.Batozai:BAAALgADCgEJAQAAAA==.Baumstack:BAAALgADCgUJBQAAAA==.',
Bd='Bdibz:BAAALgADCgcJDAAAAA==.',
Be='Beautifulluv:BAABLgAECn8jAAQPAAgJLCKNBwDSAgAPAAgJLCKNBwDSAgAQAAUJDQ4bRADTAAARAAEJkAzNUwA6AAAAAA==.Beelzabubba:BAAALgAECgkJAwAAAA==.Bekabeka:BAACLgAFFH8VAAISAAUJ1B1yCwC5AQASAAUJ1B1yCwC5AQAuAAQKf0cABBIACQk+JCEEADkDABIACQk+JCEEADkDAAkABQm5CMHbAL0AABMABQmOBhgvAH8AAAAA.Belfour:BAAALgAECgEJAgAAAA==.Bera:BAAALgAECgUJDwABLgAECgcJDgAIAAAAAA==.Beramage:BAAALgAECgEJAQAAAA==.',
Bi='Billybobjr:BAABLgAECn86AAINAAgJGyHzCQDtAgANAAgJGyHzCQDtAgAAAA==.Bippitybop:BAAALgAECgEJAQAAAA==.',
Bl='Blackbart:BAAALgADCgcJBwAAAA==.',
Bo='Boamere:BAABLgAECn8nAAIUAAgJ8xU0EwCRAQAUAAgJ8xU0EwCRAQAAAA==.Botemedel:BAAALgADCgEJAQAAAA==.',
Br='Braided:BAAALgAECgIJAwAAAA==.Brakkar:BAABLgAECn80AAIVAAgJDRTSFADjAQAVAAgJDRTSFADjAQAAAA==.Brandish:BAAALgADCgcJBwAAAA==.Breadstick:BAABLgAECn8xAAIKAAcJ/yRhCwDrAgAKAAcJ/yRhCwDrAgAAAA==.Brevik:BAAALgADCgMJAwAAAA==.Brutaal:BAAALgADCgcJCwAAAA==.Brynhild:BAAALgAFFAIJAwAAAA==.Brütaal:BAABLgAECn8dAAMNAAcJphcPKwDfAQANAAcJphcPKwDfAQAOAAEJAAAXkAAnAAAAAA==.',
Bu='Bubsydogo:BAAALgAECgcJEQAAAA==.Buddytheelf:BAABLgAECn8pAAMCAAgJKSQXGAB7AgACAAYJ7iMXGAB7AgAWAAIJiyUbJQBnAAAAAA==.Bumpyflea:BAAALgADCgUJBQAAAA==.',
Ca='Cairnsilvers:BAAALgADCgEJAQAAAA==.Camus:BAABLgAECn8ZAAIJAAgJ5Re2SwDFAQAJAAgJ5Re2SwDFAQAAAA==.Capped:BAAALgADCgMJAwAAAA==.Catgirl:BAAALgAECgYJCAAAAA==.',
Ce='Cebollin:BAAALgAECgUJCAAAAA==.Celaian:BAAALgAECgUJCgABLgAFFAEJAQAIAAAAAA==.Celamor:BAAALgAECgQJBwAAAA==.Celasmine:BAAALgADCgYJCAAAAA==.Celpanda:BAAALgAFFAEJAQAAAA==.',
Ch='Charlamayne:BAAALgADCgcJBwAAAA==.Charybdia:BAABLgAECn8iAAIXAAcJ5QaEkwDPAAAXAAcJ5QaEkwDPAAAAAA==.Chidõri:BAACLgAFFH8OAAIOAAQJ5x2+EQBQAQAOAAQJ5x2+EQBQAQAuAAQKfy4AAw4ACQmDI0kFAEMDAA4ACQmDI0kFAEMDABgAAgnPFuUlAHkAAAAA.Chopstix:BAAALgADCgcJBwAAAA==.Chudlock:BAAALgAECgYJEQAAAA==.Chunna:BAABLgAECn8oAAIFAAkJuB0oCgB8AgAFAAkJuB0oCgB8AgAAAA==.Chunni:BAABLgAECn8YAAIFAAgJEQcRQwDHAAAFAAgJEQcRQwDHAAAAAA==.',
Ci='Cilicia:BAAALgADCgUJBQAAAA==.',
Co='Codap:BAAALgADCgcJBwAAAA==.Coolerfrieza:BAAALgAECgUJCwAAAA==.',
Cp='Cpr:BAABLgAECn8XAAISAAcJiCGvDwCXAgASAAcJiCGvDwCXAgAAAA==.',
Cr='Crepic:BAAALgAECgQJBAAAAA==.Cruelkitty:BAABLgAECn8bAAMZAAgJAAW8NQCtAAAZAAYJoAa8NQCtAAAaAAgJGgHEGwCUAAAAAA==.',
Cu='Cudibandit:BAAALgADCgcJDwAAAA==.',
Cy='Cynaria:BAAALgAECgEJAgAAAA==.Cyralai:BAACLgAFFH8sAAIKAAgJQRdTAgC8AgAKAAgJQRdTAgC8AgAuAAQKfxkAAgoACQlQIfEQALACAAoACQlQIfEQALACAAAA.',
Da='Dabofdeath:BAAALgAECgIJAgAAAA==.Dalov:BAABLgAECn8gAAMSAAcJSSbxBwDvAgASAAcJSSbxBwDvAgAJAAIJbx0b9ACaAAAAAA==.Dankley:BAABLgAECn8VAAIbAAcJUgjTRAAJAQAbAAcJUgjTRAAJAQAAAA==.Darkestnyte:BAAALgAECggJDwAAAA==.Darkk:BAAALgAECgQJDAAAAA==.Darkomenz:BAAALgADCgYJBwAAAA==.Darkpalidin:BAAALgAECgYJBgABLgAECgcJIQAcAMUaAA==.Darkrhaenies:BAAALgADCgcJBwAAAA==.Darkwindx:BAAALgADCggJCQABLgAECgUJBwAIAAAAAA==.Datezero:BAAALgADCgQJBAAAAA==.',
De='Deadhealer:BAAALgADCgMJAwAAAA==.Deafknighte:BAAALgAECgMJAwAAAA==.Deathboi:BAABLgAECn8nAAILAAgJFBNcTAC7AQALAAgJFBNcTAC7AQAAAA==.Deathburgur:BAAALgAECggJEQAAAA==.Deathfromme:BAAALgAECgYJCgAAAA==.Deathstro:BAAALgAECgYJDgABLgAECgkJKQALAFwbAA==.Decayed:BAAALgAECgQJCgAAAA==.Dentridios:BAAALgADCgIJAgAAAA==.Deson:BAABLgAECn8hAAMSAAcJOxEQQgBwAQASAAcJOxEQQgBwAQAJAAUJiQi24QC0AAAAAA==.Deviantart:BAAALgAECgQJBAAAAA==.',
Di='Diana:BAABLgAECn8eAAIHAAgJrwwYUQCBAQAHAAgJrwwYUQCBAQAAAA==.Diietriich:BAABLgAECn8mAAIEAAcJHCQPLgBDAgAEAAcJHCQPLgBDAgAAAA==.Dilligaaf:BAAALgADCgMJAwAAAA==.',
Do='Docbeanz:BAAALgADCgMJAwAAAA==.Donkypunch:BAAALgADCgQJBAAAAA==.Dontjudgemê:BAAALgADCgIJAgAAAA==.Dopie:BAAALgADCgIJAgAAAA==.Dorcina:BAAALgAECgEJAQAAAA==.',
Dr='Dracthyr:BAAALgADCgUJDQAAAA==.Dragoondpain:BAAALgAECgQJCwAAAQ==.Draltina:BAABLgAECn8XAAMBAAgJPAmkDQBaAQABAAgJPAmkDQBaAQACAAEJywLtLwEhAAAAAA==.Drazira:BAAALgAECgYJCQABLgAECgYJEgAIAAAAAA==.Drunkbera:BAAALgAECgcJBwAAAA==.',
Du='Dunks:BAAALgAFFAEJAgAAAA==.',
Dy='Dylghoul:BAAALgADCgUJBQAAAA==.',
['Dí']='Dírac:BAABLgAFFH8FAAICAAMJMA1PXgDbAAACAAMJMA1PXgDbAAAAAA==.',
Ed='Edwillei:BAAALgAECgEJAQAAAA==.',
Ef='Efforex:BAAALgADCgQJBAAAAA==.',
El='Elactoplasm:BAAALgAECgMJAwAAAA==.Ellistrae:BAAALgADCgEJAQAAAA==.Ellysia:BAAALgADCgEJAQAAAA==.',
Em='Emmel:BAAALgADCggJCwAAAA==.',
Eq='Equeslucis:BAAALgAECgcJBwAAAA==.',
Er='Erodrana:BAAALgAECgYJEgAAAA==.Eromir:BAAALgAECgUJCgAAAA==.Eryi:BAABLgAECn8tAAIDAAgJ1xZCGQAPAgADAAgJ1xZCGQAPAgAAAA==.',
Et='Ethan:BAABLgAECn8eAAMdAAkJnRs/DQDsAQAdAAcJIRg/DQDsAQAbAAQJ6CK4RwD9AAAAAA==.',
Ev='Evonari:BAAALgADCgIJAgAAAA==.',
Ex='Exoticfrost:BAAALgADCgIJAgAAAA==.Expertnewb:BAAALgAECgIJAgABLgAECgcJIQAcAMUaAA==.',
['Eí']='Eísheth:BAAALgADCgUJBAAAAA==.',
Fa='Faegen:BAAALgAECgEJAgAAAA==.Falkønn:BAAALgAECgMJAwAAAA==.Fangytooth:BAABLgAECn8uAAIVAAkJeSS5AQAoAwAVAAkJeSS5AQAoAwAAAA==.Fashaun:BAAALgAECgIJAgAAAA==.Faze:BAAALgAECgYJEAAAAA==.',
Fe='Ferrus:BAACLgAFFH8YAAMXAAcJIx+rAwD9AQAXAAcJIx+rAwD9AQAZAAQJyBl3FACrAAAuAAQKfxsAAxkACQn1JdANAIYCABcACAkBJOwcAKQCABkABwncJNANAIYCAAAA.',
Ff='Ffleuderflam:BAAALgAECgYJBgAAAA==.',
Fr='Frose:BAAALgADCgEJAQAAAA==.Frostyblast:BAAALgADCgUJBgAAAA==.',
Fu='Fupacabra:BAAALgADCgEJAQAAAA==.Furiosity:BAAALgAECgMJBQAAAA==.Fuzzybear:BAAALgAECgcJCAABLgAECgkJLgAVAHkkAA==.Fuzzybeard:BAAALgAECgYJBgABLgAECgkJLgAVAHkkAA==.Fuzzywar:BAAALgAECgYJBgABLgAECgkJLgAVAHkkAA==.',
Ga='Gabomonk:BAABLgAFFH8FAAIGAAIJ1iQyLQDUAAAGAAIJ1iQyLQDUAAAAAA==.Gamalia:BAAALgADCgUJBQAAAA==.Garudekhan:BAAALgADCgUJBQAAAA==.',
Ge='Genreallee:BAABLgAECn8bAAIJAAcJ1hITcQBsAQAJAAcJ1hITcQBsAQAAAA==.Gernab:BAAALgADCgYJBgAAAA==.',
Gh='Ghost:BAABLgAECn8WAAIKAAYJ9xt+NgDOAQAKAAYJ9xt+NgDOAQAAAA==.',
Gi='Gianna:BAABLgAECn8XAAMSAAkJ7CPRAQCAAwASAAkJ7CPRAQCAAwAJAAIJCR5g8ACgAAAAAA==.Gizzar:BAAALgADCgYJCgAAAA==.',
Gl='Glau:BAAALgADCgcJBwABLgAECggJCAAIAAAAAA==.Glimpsed:BAAALgAECgcJDgAAAA==.Globgore:BAAALgADCgIJBAAAAA==.Gloçk:BAAALgAECgMJBwABLgAECgYJEQAIAAAAAA==.',
Go='Goofy:BAABLgAECn8fAAIJAAcJYCHDJACUAgAJAAcJYCHDJACUAgAAAA==.Goor:BAAALgAECgEJAQAAAA==.Gorrik:BAAALgADCgUJBQAAAA==.',
Gr='Graeae:BAAALgAECgUJBQAAAA==.Greyfeather:BAAALgADCgEJAgAAAA==.Grimeace:BAAALgADCgQJBAAAAA==.',
Gu='Gunduin:BAABLgAECn8eAAIHAAgJriB5IwAqAgAHAAgJriB5IwAqAgAAAA==.',
Gw='Gweb:BAAALgAECgIJAgAAAA==.',
Gy='Gyda:BAABLgAECn8cAAIRAAcJDiFtCwCNAgARAAcJDiFtCwCNAgAAAA==.Gyuyuki:BAABLgAECn84AAIOAAcJRxDCNAA4AQAOAAcJRxDCNAA4AQAAAA==.',
Ha='Hakuanah:BAAALgADCgEJAQAAAA==.Halvorak:BAAALgADCgcJCgAAAA==.Harryp:BAABLgAECn8yAAMeAAkJqRTJGADwAQAeAAkJ5RLJGADwAQAfAAkJ/BAqBwCrAQAAAA==.Hast:BAAALgAECgYJDwAAAA==.',
He='Hearthzilla:BAAALgAECgEJAQABLgAECgkJIAAOANgfAA==.Hellsbow:BAAALgAECgYJDgAAAA==.Hermin:BAAALgADCgQJBgAAAA==.',
Ho='Holyhellz:BAAALgADCgEJAQAAAA==.Honeyboo:BAAALgAECgEJAQABLgAECgkJOQAKAEQiAA==.Hots:BAAALgADCgcJBwAAAA==.Hotzz:BAAALgAECgEJAQAAAA==.',
Hr='Hraesvelgr:BAAALgADCggJBwAAAA==.',
Hu='Huntavious:BAABLgAECn80AAQVAAkJPB+eAwDmAgAVAAkJPB+eAwDmAgAHAAYJ4xrGXgBLAQAgAAEJyBPbigAwAAAAAA==.',
['Hë']='Hëllen:BAABLgAECn8YAAIJAAYJMiDaaQCrAQAJAAYJMiDaaQCrAQAAAA==.',
Ia='Iamshinigamy:BAAALgAECgIJAgABLgAECgcJFwAEAPMaAA==.',
Ii='Iichimaru:BAAALgAECgUJBQAAAA==.',
Il='Illidupe:BAAALgADCgMJAwAAAA==.',
In='Inaoh:BAAALgAECgQJBgAAAA==.',
Iv='Ivey:BAABLgAECn8qAAIKAAgJRh46EQCmAgAKAAgJRh46EQCmAgAAAA==.',
Iz='Izes:BAAALgAECgEJAQAAAA==.',
Ja='Jaagganug:BAAALgADCgMJAwAAAA==.Jacenne:BAABLgAECn8XAAIhAAUJmwMtXABwAAAhAAUJmwMtXABwAAAAAA==.Jairus:BAAALgAECgcJBwAAAA==.',
Jd='Jdirty:BAABLgAECn8UAAIiAAYJFwdKEQDDAAAiAAYJFwdKEQDDAAAAAA==.',
Je='Jellytime:BAAALgAECgEJAwAAAA==.',
Jo='Josephyn:BAAALgAECgMJAwABLgAFFAUJKgANAM0fAA==.',
Ju='Jugernaut:BAAALgAECgEJAQAAAA==.Jumpmann:BAAALgAECgMJAwAAAA==.Justdesserts:BAAALgAECgEJAQAAAA==.Justix:BAAALgADCggJEwAAAA==.',
Ka='Kadaffy:BAAALgAECgEJAgAAAA==.Kakusu:BAAALgAECgYJEQAAAA==.Kakuta:BAAALgAECgUJDAABLgAECggJEAAIAAAAAA==.Kakutá:BAAALgAECggJEAAAAA==.Kalru:BAAALgADCgQJCwAAAA==.Kargar:BAAALgAECgEJAgAAAA==.Katharsis:BAACLgAFFH8GAAIJAAMJJQr6UwDZAAAJAAMJJQr6UwDZAAAuAAQKfyEAAgkACQnPFoU1AAoCAAkACQnPFoU1AAoCAAAA.',
Ke='Keba:BAAALgADCggJDwABLgAFFAUJFQASANQdAA==.Keévs:BAAALgADCgQJBAAAAA==.',
Kh='Khalidisi:BAABLgAECn8uAAQTAAkJFR/pBACBAgATAAgJsR/pBACBAgASAAkJLRmSJwCnAQAJAAcJJAqYnAAcAQAAAA==.Khaliesi:BAAALgADCgIJAgAAAA==.Khalizar:BAABLgAFFH8FAAIbAAMJHwSKLQC2AAAbAAMJHwSKLQC2AAAAAA==.Kharazim:BAAALgADCgEJAQABLgAECgcJJQAXACwbAA==.Khenja:BAAALgAECgEJAQAAAA==.Khál:BAAALgADCgYJBgAAAA==.',
Ki='Killerelf:BAAALgAECgIJAgAAAA==.',
Kk='Kkiilleerr:BAAALgAECgYJDwAAAA==.',
Ko='Kobbaltcilar:BAAALgAECgUJBQAAAA==.Koraleena:BAAALgAECgQJBAAAAA==.Korbo:BAABLgAECn8mAAMOAAcJaB0GIwCgAQAOAAUJeR4GIwCgAQANAAQJZRUTaQDnAAAAAA==.Korbulo:BAAALgAECgcJEgAAAA==.Korlothel:BAABLgAECn8gAAITAAkJ2AbEHQD4AAATAAkJ2AbEHQD4AAABLgAFFAIJAgAIAAAAAA==.Korrith:BAAALgADCgIJAgAAAA==.',
Kr='Krumpus:BAABLgAECn8aAAIXAAgJrQ8xSQCIAQAXAAgJrQ8xSQCIAQAAAA==.',
Ku='Kungfuuy:BAABLgAECn8eAAIGAAgJsR8fDQBGAgAGAAgJsR8fDQBGAgAAAA==.Kurtevade:BAAALgAECgQJCwAAAA==.',
Kw='Kwetnepthl:BAAALgAECgEJAQAAAA==.',
Ky='Kynsong:BAAALgAECgYJEgAAAA==.',
['Kà']='Kàlbrews:BAABLgAECn9AAAIGAAkJvyYlAACMAwAGAAkJvyYlAACMAwAAAA==.Kàrmâ:BAAALgAECgUJBQAAAA==.',
La='Lainiee:BAAALgADCgEJAQAAAA==.Lavismad:BAEBLgAECn80AAQbAAkJDCWbAgAxAwAbAAkJ2CSbAgAxAwAUAAcJoSAaDAADAgAdAAEJRiV3MgBpAAAAAA==.Lavoc:BAEALgADCgcJBwABLgAECgkJNAAbAAwlAA==.Lavv:BAEALgAECgYJCAABLgAECgkJNAAbAAwlAA==.Lavz:BAEALgAECgYJBgABLgAECgkJNAAbAAwlAA==.',
Le='Legendary:BAAALgAECgYJDAAAAA==.Leshah:BAAALgAECgMJBQAAAA==.',
Li='Lichkingdied:BAAALgADCgUJBQAAAA==.Lightndpain:BAAALgAECgQJBgABLgAECgQJCwAIAAAAAA==.Lilypetal:BAAALgAECgQJBwAAAA==.Littlebucket:BAAALgADCgEJAQAAAA==.',
Lo='Lockdpain:BAAALgAECgYJGAABLgAECgQJCwAIAAAAAQ==.Logov:BAAALgAECgYJDwAAAA==.Loraine:BAAALgAECgEJAQAAAA==.Loìsbethe:BAAALgAECgQJBAAAAA==.',
Lu='Luciferra:BAAALgAECggJCwABLgAFFAUJKgANAM0fAA==.Lukey:BAAALgAECgMJAwAAAA==.Lunartemis:BAAALgAECgUJCAABLgAFFAQJBwAjAKQbAA==.Luu:BAAALgAECgIJAgAAAA==.',
['Lö']='Lörax:BAAALgADCgQJBQAAAA==.',
['Lû']='Lûnafreya:BAAALgAECggJEgAAAA==.',
Ma='Maelera:BAAALgADCgkJDAAAAA==.Maetromundo:BAAALgAECgEJAQAAAA==.Magentas:BAAALgADCgIJAgAAAA==.Magickul:BAAALgADCggJCAAAAA==.Mahlah:BAAALgAECgQJBAAAAA==.Malaboo:BAAALgAECgEJAQABLgAECgkJOQAKAEQiAA==.Malabooty:BAAALgAECgYJBgABLgAECgkJOQAKAEQiAA==.Maletsy:BAAALgAECgEJAQABLgAECggJHgAHAK4gAA==.Maliboo:BAABLgAECn85AAMKAAkJRCKOAwByAwAKAAkJRCKOAwByAwAhAAIJnwlCdgAzAAAAAA==.Maxamus:BAAALgAECgUJEgAAAA==.Maxigooner:BAAALgAECgYJCAABLgAFFAUJFgAJALAlAA==.',
Mc='Mcflurry:BAAALgAECgUJCwAAAA==.',
Me='Medarisa:BAAALgAECgYJCwAAAA==.Medavia:BAAALgADCgUJBQAAAA==.Mederia:BAAALgAECgUJBQAAAA==.Melisandr:BAAALgAECgMJBQAAAA==.Merkenier:BAABLgAECn8kAAIhAAgJyBGPIgCHAQAhAAgJyBGPIgCHAQAAAA==.Merkur:BAAALgADCgkJCQABLgAECggJJAAhAMgRAA==.',
Mi='Midnitehunt:BAAALgAECgQJBAAAAA==.Miragia:BAAALgAECgUJBwAAAA==.Missmayhem:BAAALgAECgUJCAAAAA==.Missmayhemm:BAAALgADCgQJBgAAAA==.',
Mo='Modifiedmix:BAABLgAECn8cAAIHAAcJKBR+VQB1AQAHAAcJKBR+VQB1AQAAAA==.Modsabadtank:BAAALgAECgUJCQABLgAECgcJHAAHACgUAA==.Mokomohama:BAAALgAECgcJBwAAAA==.Monatazumaa:BAAALgAECgEJAgAAAA==.Moonbloom:BAAALgAECgQJCAABLgAFFAUJKgANAM0fAA==.Mopeezie:BAAALgAECgEJAQAAAA==.Mordicant:BAAALgADCgEJAQABLgAECgYJCAAIAAAAAA==.Morella:BAABLgAECn81AAIWAAcJmQ4HGQCDAQAWAAcJmQ4HGQCDAQAAAA==.',
Mu='Mucduck:BAAALgADCgEJAQAAAA==.Mustakrakish:BAAALgAECgEJAQAAAA==.Mustaz:BAAALgAECgkJBQAAAA==.',
My='Mym:BAAALgADCgcJBAAAAA==.Mystics:BAAALgAECgUJBQAAAA==.Mythrunduil:BAAALgADCgEJAQAAAA==.',
['Mé']='Médb:BAABLgAECn8qAAMEAAcJxx0uOwARAgAEAAcJNx0uOwARAgAkAAMJFR0ZBwD2AAAAAA==.',
Na='Naste:BAAALgAECgUJBQAAAA==.Nathrold:BAAALgAECgIJBAABLgAECgYJEQAIAAAAAA==.',
Ne='Neptune:BAACLgAFFH8qAAINAAUJzR8WDQC2AQANAAUJzR8WDQC2AQAuAAQKfx8AAw0ACQnRHxgHAAIDAA0ACQnRHxgHAAIDAA4ABwkkDtE0AIQBAAAA.Nerfdks:BAAALgAECggJCgAAAA==.Nerfpaladins:BAABLgAECn8gAAMTAAcJpRJnHgDyAAAJAAYJthFzmgAfAQATAAcJJBFnHgDyAAAAAA==.Neruess:BAAALgADCgUJBQAAAA==.Nezzuko:BAAALgAECgcJBwAAAA==.',
Ni='Nightbird:BAABLgAECn8dAAMjAAcJvBc2JABFAQAjAAcJThc2JABFAQAlAAYJ8BWfDgAsAQABLgAECggJCAAIAAAAAA==.Ninediewatt:BAAALgAECgMJBAAAAA==.Nivella:BAAALgAECgYJCgAAAA==.Nixaana:BAAALgAECgEJAQAAAA==.Niçki:BAAALgADCgMJAwAAAA==.',
No='Notlockz:BAAALgADCgIJAgAAAA==.Novah:BAAALgADCgQJBQAAAA==.Noydb:BAAALgADCgYJBgABLgAECggJJwAUAPMVAA==.',
Nu='Nuah:BAAALgADCgYJDQAAAA==.',
Ny='Nyxsia:BAEALgAFFAEJAQABLgAFFAYJFgAbAMgdAA==.',
['Nè']='Nèo:BAAALgADCgcJBwAAAA==.',
Ob='Obayi:BAAALgAECgYJDgAAAA==.',
Og='Ogmadmonk:BAACLgAFFH8MAAIZAAMJnRKoEADkAAAZAAMJnRKoEADkAAAuAAQKfzEAAhkACQmUIRgGAK0CABkACQmUIRgGAK0CAAAA.',
Ok='Oktobra:BAAALgAECgYJEAAAAA==.',
On='Onetrickpony:BAAALgADCgYJCQAAAA==.Onos:BAAALgAECgIJAgAAAA==.Onosm:BAAALgAECgQJBAAAAA==.',
Or='Orangevoker:BAAALgAECgcJCwABLgAECgkJIAAOANgfAA==.Orioan:BAAALgAECgMJBAAAAA==.Orux:BAAALgAECgYJBgAAAA==.',
Os='Osenya:BAAALgAECgYJBgABLgAFFAIJAgAIAAAAAA==.Osun:BAAALgADCggJCwAAAA==.',
Ou='Ouroboro:BAAALgADCgUJBQAAAA==.',
Ow='Owlbat:BAAALgAECgEJAQAAAA==.',
Pa='Padremort:BAAALgADCgYJBgAAAA==.Palantyr:BAABLgAECn9XAAIOAAgJvRqZGgA+AgAOAAgJvRqZGgA+AgAAAA==.Paly:BAAALgAECgEJAQAAAA==.Para:BAAALgAECgQJBAAAAA==.Patrician:BAABLgAECn8mAAIiAAcJCRdiBwCjAQAiAAcJCRdiBwCjAQAAAA==.',
Pe='Peehat:BAAALgADCgcJCQAAAA==.Penutbutter:BAAALgAECgQJBAAAAA==.Pepegasus:BAAALgADCgcJBwAAAA==.',
Ph='Phobos:BAAALgADCgQJCAAAAA==.Phyloren:BAAALgADCgUJBgAAAA==.',
Pi='Pigsticker:BAAALgAECgQJBQAAAA==.Pixyfire:BAAALgAECgYJCgABLgAECgkJNAASAIsiAA==.',
Po='Poisonleaf:BAAALgAECgEJAQABLgAECgYJGAAJADIgAA==.Pokingharder:BAAALgAECggJEgABLgAFFAMJBwABAKUTAA==.',
Pu='Pulcherrimus:BAAALgAECgEJAwAAAA==.Purgeem:BAAALgADCgUJBQAAAA==.Pushpop:BAAALgAECgYJDwABLgAECggJVwAOAL0aAA==.',
Pw='Pwiest:BAAALgADCgcJEAAAAA==.',
Qu='Quetzalcoatl:BAABLgAECn8WAAImAAYJ9BxJEAChAQAmAAYJ9BxJEAChAQAAAA==.',
Ra='Raambox:BAAALgAECgQJBAAAAA==.Radak:BAAALgADCgYJDAAAAA==.Raddish:BAAALgAECgYJEAAAAA==.Rahjlynn:BAAALgADCgcJBwAAAA==.Rahken:BAAALgAECgcJBwAAAA==.Raiinn:BAAALgADCgUJBQAAAA==.Raylee:BAABLgAECn86AAMCAAkJniGDDwC5AgACAAgJsR+DDwC5AgAWAAcJfCEPCABEAgAAAA==.Razuki:BAABLgAECn80AAMSAAkJiyLDAwBGAwASAAkJiyLDAwBGAwAJAAcJ9hc2WwCcAQAAAA==.',
Re='Remyl:BAAALgADCggJCAAAAA==.',
Rf='Rfd:BAAALgADCgcJBwABLgAECggJEwAIAAAAAA==.',
Rh='Rhaenies:BAAALgAECgYJEAAAAA==.Rharr:BAAALgADCgkJDAAAAA==.Rhovanion:BAAALgAECgUJCQAAAA==.Rhuac:BAABLgAECn8jAAIKAAgJCRRbLgDJAQAKAAgJCRRbLgDJAQAAAA==.',
Ri='Risakah:BAAALgAECggJCAAAAA==.',
Ro='Rorschach:BAAALgAECgcJCgAAAA==.Rosefist:BAEALgADCgcJCAABLgAFFAUJDwARAM0SAA==.Rosemourne:BAEALgAECgIJAgABLgAFFAUJDwARAM0SAA==.Roseykat:BAABLgAECn8iAAIHAAYJrA2PfAAXAQAHAAYJrA2PfAAXAQAAAA==.Roshwyn:BAABLgAECn8UAAIHAAgJHgtPWQBqAQAHAAgJHgtPWQBqAQAAAA==.Rottedmeat:BAAALgAECgYJBgAAAA==.',
Ru='Ruckus:BAABLgAECn8nAAIJAAgJuRYPPwApAgAJAAgJuRYPPwApAgAAAA==.',
Sa='Saberwar:BAAALgAECgEJAQABLgAECgMJAwAIAAAAAA==.Saintfury:BAAALgAECgQJBQAAAA==.Saintsfear:BAABLgAECn8mAAIbAAcJyhFhMABlAQAbAAcJyhFhMABlAQAAAA==.Sanchito:BAAALgADCgMJAwAAAA==.Saphalia:BAAALgADCgMJAwAAAA==.Saradomin:BAAALgADCgUJBAAAAA==.Sareenastar:BAABLgAECn8uAAMPAAkJlCYtAADwAwAPAAkJlCYtAADwAwAQAAEJ3wm7cAAyAAAAAA==.Sasae:BAABLgAECn8XAAIGAAYJyhDHPADpAAAGAAYJyhDHPADpAAAAAA==.',
Sc='Scorias:BAAALgADCgQJAwAAAA==.',
Se='Selisztraza:BAAALgADCgEJAQAAAA==.Sephiróth:BAAALgADCgUJCAAAAA==.Sereni:BAAALgADCgQJBAAAAA==.Serenity:BAAALgAECgcJDAAAAA==.Serenitynow:BAAALgAECgEJAgAAAA==.Sewald:BAAALgAECgYJCQAAAA==.',
Sh='Shadowzbane:BAAALgAECgIJAgAAAA==.Shahasha:BAAALgADCgEJAQAAAA==.Shaidarharan:BAAALgADCgIJAgAAAA==.Shakeybop:BAAALgAECgQJBAAAAA==.Shalen:BAABLgAECn8lAAQeAAgJzhUPIQCuAQAeAAgJwBUPIQCuAQAfAAYJoQ2ZHQBCAQAmAAQJsw7mJwCBAAAAAA==.Sharker:BAAALgADCgYJBgAAAA==.Sharpie:BAAALgADCgcJCgAAAA==.Sheer:BAABLgAECn8UAAIGAAgJYB8pDABTAgAGAAgJYB8pDABTAgAAAA==.Sheraa:BAABLgAECn8fAAITAAcJOBNEFABaAQATAAcJOBNEFABaAQAAAA==.Shiftystrike:BAABLgAECn8WAAInAAcJPx/wCgAVAgAnAAcJPx/wCgAVAgAAAA==.Shifushield:BAAALgAECgcJCAAAAA==.Shireshannon:BAAALgAECgYJEQAAAA==.Shrunkador:BAACLgAFFH8MAAIOAAQJawrWHwD6AAAOAAQJawrWHwD6AAAuAAQKfysAAg4ACQmQHXgUABoCAA4ACQmQHXgUABoCAAAA.',
Si='Silk:BAAALgAECgYJDgAAAA==.Silmarkthree:BAABLgAECn80AAIEAAkJpBj+LgA/AgAEAAkJpBj+LgA/AgAAAA==.Sinbåd:BAAALgAECgcJCAAAAA==.Siodar:BAAALgADCgEJAQABLgADCgYJBgAIAAAAAA==.Sisterstar:BAAALgADCgMJAwAAAA==.',
Sl='Sleety:BAAALgAECgIJBQAAAA==.Slipknoth:BAACLgAFFH8ZAAMRAAcJdgs6EQClAQARAAYJ5gg6EQClAQAQAAYJtBoPCACdAQAuAAQKfyoABBAACQkpIWcYAN8BABAABwnDJGcYAN8BAA8ABwntF/kgANsBABEABAnOGY06APEAAAAA.',
Sn='Snekhain:BAAALgADCgMJAwAAAA==.Snuffaluffa:BAAALgAECgMJAwAAAA==.',
So='Somatra:BAAALgADCgkJCQAAAA==.Sorean:BAACLgAFFH8PAAIVAAQJ4hl6CgBYAQAVAAQJ4hl6CgBYAQAuAAQKfy8ABAcACQm+IFYhAD0CAAcABwlUG1YhAD0CABUABwlnHZ8UAOYBACAABwlQGv0vALUBAAAA.',
Sp='Specialmove:BAAALgAFFAEJAgAAAA==.Spookydookie:BAAALgADCgkJCgAAAA==.',
St='Staghealz:BAAALgAECgEJAQAAAA==.Stifs:BAABLgAECn8iAAITAAgJRBEEFwBlAQATAAgJRBEEFwBlAQAAAA==.Stilleena:BAAALgAECgYJBgAAAA==.Stinkinglily:BAAALgAECgEJAgAAAA==.Strunrage:BAEALgAECgUJBQABLgAECgkJPQAJAIskAA==.Stÿx:BAABLgAECn8ZAAIoAAYJ6gWBNQCTAAAoAAYJ6gWBNQCTAAABLgAECgcJDQAIAAAAAA==.',
Su='Sugarbomb:BAAALgADCgMJBAAAAA==.',
Sy='Sykotyk:BAAALgAECgkJDwAAAA==.Sylverfox:BAAALgAECgMJAwABLgAECggJEQAIAAAAAA==.Synchestra:BAAALgADCgcJCgAAAA==.',
Ta='Tadagain:BAABLgAECn8VAAMJAAUJ8RGAwgDhAAAJAAUJ8RGAwgDhAAASAAQJ2gV2dgChAAAAAA==.Tagrith:BAAALgADCgMJAwAAAA==.Tankybears:BAABLgAECn8sAAMhAAkJzhpVDQBcAgAhAAkJzhpVDQBcAgAKAAgJ6hsJSgBEAQAAAA==.Tarmalok:BAAALgAECgEJAQAAAA==.Tazera:BAAALgAECgUJCwAAAA==.',
Te='Telekinesis:BAABLgAECn8iAAIVAAgJvhAdGwCmAQAVAAgJvhAdGwCmAQAAAA==.Tenbinza:BAAALgAECgMJBQAAAA==.Teos:BAABLgAECn8vAAIYAAkJCBmQBgA+AgAYAAkJCBmQBgA+AgAAAA==.',
Th='Thainé:BAAALgAECgMJBgAAAA==.Thaldrassian:BAAALgADCgQJBAAAAA==.Tharris:BAAALgAECgEJAQAAAA==.Thehatred:BAAALgADCgYJBgAAAA==.Therondar:BAAALgADCgEJAQAAAA==.Thiyan:BAAALgADCgMJAwAAAA==.Thromar:BAABLgAECn8VAAIEAAcJiBWvgADPAQAEAAcJiBWvgADPAQAAAA==.Thunderlily:BAABLgAECn8hAAMcAAcJxRrpBgCgAQAEAAcJQxlyWQC0AQAcAAcJchfpBgCgAQAAAA==.Thünder:BAAALgADCgcJBwABLgAECgcJFgALAKQeAA==.',
Ti='Tinderbeef:BAAALgADCgcJCAAAAA==.Tinychaos:BAAALgAECgkJCQAAAA==.Tinyround:BAAALgAECgEJAQAAAA==.Tirra:BAAALgAECggJEQAAAA==.',
To='Toranth:BAABLgAECn81AAISAAkJiRXsFABAAgASAAkJiRXsFABAAgAAAA==.Torq:BAABLgAECn8XAAIEAAYJ/BmShwDCAQAEAAYJ/BmShwDCAQABLgAECgcJFwASAIghAA==.Torqumada:BAAALgAECgQJBQAAAA==.Toxian:BAABLgAECn8pAAIXAAcJ+RVXSwCCAQAXAAcJ+RVXSwCCAQAAAA==.Toxicelitist:BAABLgAECn8oAAMWAAgJcQ08DQA9AQAWAAgJcQ08DQA9AQACAAEJmgHMNwEbAAAAAA==.',
Tr='Treedemon:BAABLgAECn8qAAIXAAkJLCR9BwABAwAXAAkJLCR9BwABAwAAAA==.Treedin:BAAALgAECgMJAwAAAA==.Trollboi:BAAALgADCggJCAAAAA==.Trymw:BAAALgADCgIJAgAAAA==.Tryst:BAAALgADCgcJBwAAAA==.',
Ty='Tybearon:BAAALgADCgcJBwAAAA==.Tyreid:BAAALgADCgMJAwAAAA==.Tyrelitha:BAAALgADCgcJCAAAAA==.',
Ud='Udderchoad:BAAALgADCgEJAQAAAA==.',
Uh='Uhura:BAAALgADCgEJAQAAAA==.',
Ul='Ulfrir:BAACLgAFFH8HAAIHAAMJhhaVPgDwAAAHAAMJhhaVPgDwAAAuAAQKfyYAAwcACQk3IHALANUCAAcACQk3IHALANUCACAAAwkxCipvAIIAAAAA.Ultradukes:BAAALgAECgEJAQAAAA==.',
Un='Unatural:BAAALgAECgUJBQAAAA==.Unleashed:BAAALgAECgUJCgAAAA==.',
Va='Valarea:BAAALgADCgEJAQAAAA==.Valock:BAAALgAECgYJDgAAAA==.Valris:BAAALgAECgMJBAAAAA==.Vandham:BAAALgADCgEJAQAAAA==.Vannis:BAAALgADCgcJBgAAAA==.Vanshifty:BAABLgAECn87AAIKAAkJCSMXBABkAwAKAAkJCSMXBABkAwAAAA==.',
Ve='Veilf:BAAALgADCgYJDAAAAA==.Velf:BAAALgAECgIJAgAAAA==.Velrus:BAAALgAECgYJDAAAAA==.Venli:BAAALgAECgEJAQAAAA==.Venombite:BAAALgADCgMJAwAAAA==.Verez:BAAALgADCgcJBwAAAA==.',
Vi='Victorion:BAAALgAECggJCAAAAA==.Viktorax:BAAALgAECgYJCwAAAA==.Vincevega:BAAALgAECgQJBQAAAA==.Virtueozo:BAABLgAECn8aAAImAAgJEBfODwA+AgAmAAgJEBfODwA+AgAAAA==.',
Vo='Volam:BAAALgAECgQJBAAAAA==.',
Vy='Vyx:BAAALgAECgcJDQAAAA==.',
Wa='Waffle:BAAALgAECgYJDwAAAA==.Waldhorn:BAAALgAECgcJCwAAAA==.Wangwen:BAAALgADCgIJAgAAAA==.Wargue:BAABLgAECn8VAAIbAAYJjRugOADEAQAbAAYJjRugOADEAQAAAA==.',
We='Weebsz:BAAALgADCgQJBAAAAA==.Welindis:BAAALgAECgYJEAABLgAECggJKAAXADIRAA==.Wetkith:BAAALgADCgUJBQAAAA==.',
Wi='Windrider:BAAALgADCgIJAgAAAA==.Windwraith:BAAALgAECgIJAgAAAA==.Wizzard:BAAALgAECggJHAAAAQ==.',
Xa='Xaiyara:BAAALgADCgUJBQAAAA==.Xalina:BAAALgAECgEJAQAAAA==.Xandaka:BAAALgADCgQJBAAAAA==.',
Xe='Xephir:BAAALgAECggJCgAAAA==.',
Xi='Xidied:BAABLgAECn8wAAIGAAkJJiFTBADpAgAGAAkJJiFTBADpAgAAAA==.Xilon:BAAALgAECgYJBgABLgAFFAIJAgAIAAAAAA==.Xilra:BAABLgAECn8uAAMhAAkJmiJhCQCZAgAhAAkJmiJhCQCZAgAnAAEJmhGTPAA1AAABLgAFFAIJAgAIAAAAAA==.Xilrot:BAAALgAFFAIJAgAAAA==.Xilzen:BAAALgAECgUJEAABLgAFFAIJAgAIAAAAAA==.Xinia:BAAALgADCgEJAQAAAA==.',
Xz='Xzed:BAAALgADCgEJAQAAAA==.',
Ye='Yew:BAAALgADCgMJAwAAAA==.',
Yi='Yikers:BAACLgAFFH8RAAISAAQJZiCtEQBqAQASAAQJZiCtEQBqAQAuAAQKfyUAAhIACQm6IeYGAPwCABIACQm6IeYGAPwCAAAA.',
Yr='Yridai:BAAALgAECgYJCAAAAA==.',
Za='Zarsher:BAAALgADCgIJAgAAAA==.',
Zd='Zdk:BAAALgAECgEJAQABLgAECgcJHwAHALkZAA==.',
Ze='Zeldy:BAABLgAECn8mAAIHAAgJJxkkOwDIAQAHAAgJJxkkOwDIAQAAAA==.Zenestraza:BAAALgADCgcJCwABLgAECgcJJQAXACwbAA==.Zenthareal:BAABLgAECn8lAAIXAAcJLBvnMwDWAQAXAAcJLBvnMwDWAQAAAA==.Zenzz:BAAALgADCgEJAQAAAA==.Zeuc:BAAALgADCgMJAwAAAA==.Zeuus:BAAALgADCgMJBAAAAA==.',
Zh='Zhirldk:BAAALgAECgcJEQAAAA==.Zhulgarosh:BAAALgADCgUJBQAAAA==.',
Zi='Zillidan:BAAALgAECgEJAQABLgAECgcJHwAHALkZAA==.',
Zm='Zmaster:BAABLgAECn8fAAIHAAcJuRn1PwC3AQAHAAcJuRn1PwC3AQAAAA==.',
Zo='Zobeast:BAAALgADCgQJBAAAAA==.',
Zr='Zret:BAAALgAECgYJCgABLgAECgcJHwAHALkZAA==.',
Zw='Zwar:BAAALgAECgEJAQABLgAECgcJHwAHALkZAA==.',
Zy='Zynith:BAAALgAECgYJBgAAAA==.',
['Zö']='Zöey:BAAALgADCgQJBQAAAA==.',
['Åp']='Åpex:BAAALgAECggJBQAAAA==.',
['Çl']='Çloudz:BAAALgADCgMJAwAAAA==.',
['Ða']='Ðark:BAACLgAFFH8NAAIHAAMJyBFnGACmAAAHAAMJyBFnGACmAAAuAAQKfycAAgcACQm5HAQVAI8CAAcACQm5HAQVAI8CAAAA.',
['Ðr']='Ðr:BAABLgAECn8eAAMNAAkJ/Br1IgANAgANAAcJThr1IgANAgAOAAYJ7xcvLABoAQAAAA==.',
['ßl']='ßlack:BAAALgADCgEJAQAAAA==.',
['ßu']='ßudah:BAAALgAECgMJAwAAAA==.',
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
