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

local lookup = {'Warlock-Affliction','Warlock-Demonology','Monk-Mistweaver','Mage-Frost','Monk-Windwalker','Monk-Brewmaster','Hunter-BeastMastery','Paladin-Protection','Paladin-Retribution','Druid-Restoration','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Restoration','Shaman-Elemental','Unknown-Unknown','Priest-Holy','Priest-Shadow','Priest-Discipline','Paladin-Holy','Warrior-Protection','Hunter-Survival','Warlock-Destruction','DemonHunter-Devourer','Shaman-Enhancement','Warrior-Fury','Warrior-Arms','Mage-Arcane','DemonHunter-Havoc','Rogue-Subtlety','Evoker-Augmentation','Evoker-Devastation','Hunter-Marksmanship','Druid-Balance','Mage-Fire','Rogue-Assassination','Rogue-Outlaw','Evoker-Preservation','Druid-Feral','DeathKnight-Blood',}
local provider = {region='US',realm='Dawnbringer',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abdalhazred:BAACLgAFFH8QAAMBAAQJECOwAACLAQABAAQJECOwAACLAQACAAEJiR+hhQBVAAAuAAQKfzQAAwEACQmXJFIAAGYDAAEACAm3JVIAAGYDAAIAAwnQHSmAAPwAAAAA.Abilus:BAAALgAECgQJDwAAAA==.Abolis:BAAALgAECgMJAwAAAA==.',
Ae='Aeldriel:BAAALgAECgMJAwAAAA==.Aeoyn:BAAALgAECgEJAQAAAA==.',
Ag='Aggar:BAAALgADCgkJCwABLgAECggJJQADALYWAA==.',
Ak='Akoa:BAAALgAECgEJAQAAAA==.',
Al='Alarak:BAABLgAECn8bAAIBAAgJcRVsCQCtAQABAAgJcRVsCQCtAQAAAA==.Alvierearn:BAABLgAECn8WAAIEAAgJuBFlbABjAQAEAAgJuBFlbABjAQAAAA==.',
Am='Amoradis:BAAALgADCgUJDgAAAA==.',
An='Anaeir:BAAALgADCgYJBgAAAA==.Angriff:BAAALgADCgQJBQAAAA==.Anisette:BAABLgAECn8cAAMFAAcJpBdZGQCWAQAFAAcJpBdZGQCWAQAGAAQJDgprUwB7AAAAAA==.Anthria:BAAALgADCgkJGwAAAA==.',
Aq='Aqurala:BAABLgAECn8eAAIHAAgJER1JJAABAgAHAAgJER1JJAABAgAAAA==.',
Ar='Aradem:BAAALgADCgcJBwABLgAECgkJIAAIANgGAA==.Aravenn:BAAALgADCgYJBgABLgAECgkJIAAIANgGAA==.Arcis:BAABLgAECn8kAAIJAAcJ0RKnZABbAQAJAAcJ0RKnZABbAQAAAA==.Arealis:BAAALgADCgcJDAAAAA==.Argatem:BAAALgAECgQJBAABLgAECggJJgAKAEYeAA==.Arkangel:BAABLgAECn8pAAMLAAkJXBveGQBoAgALAAkJXBveGQBoAgAMAAEJYQmHIgAwAAAAAA==.Arkharon:BAAALgADCgYJCQAAAA==.Arralyon:BAAALgADCgMJBgAAAA==.Artemesia:BAAALgAECgEJAQABLgAFFAUJIAANANIcAA==.Arthäs:BAAALgAECgQJBAAAAA==.Aryrn:BAAALgADCgUJBQAAAA==.',
As='Asakua:BAAALgAECgMJBgAAAA==.Asiya:BAAALgAECgQJBQAAAA==.Assandra:BAAALgADCgUJBQAAAA==.',
At='Athul:BAAALgADCgUJCgAAAA==.',
Au='Aurlyn:BAAALgADCgcJDwAAAA==.',
Av='Avatartele:BAAALgAECgIJAwAAAA==.Avatartouka:BAABLgAECn8iAAMNAAgJ6CEcCQDWAgANAAgJ6CEcCQDWAgAOAAQJ9ROcTQCoAAAAAA==.Avianthel:BAAALgADCgMJAgAAAA==.Avraria:BAAALgAECggJCAAAAA==.Avyl:BAAALgAECgYJEAAAAA==.Avylastorica:BAAALgADCgYJBgABLgAECgYJEAAPAAAAAA==.',
Aw='Awsomninja:BAABLgAECn8jAAIGAAgJ4iIwBwCPAgAGAAgJ4iIwBwCPAgAAAA==.',
Ax='Axxain:BAAALgADCgkJGgAAAA==.',
Az='Azaralle:BAAALgADCgEJAQAAAA==.Azeazal:BAAALgAECgYJEAAAAA==.Azlifan:BAAALgADCgQJBAAAAA==.Azorthragal:BAAALgADCgYJBgAAAA==.',
Ba='Baddlandss:BAAALgAECgQJCAAAAA==.Bagador:BAAALgAECgQJBAAAAA==.Bastais:BAAALgAECgEJAQAAAA==.Batozai:BAAALgADCgEJAQAAAA==.Baumstack:BAAALgADCgUJBQAAAA==.',
Bd='Bdibz:BAAALgADCgcJDAAAAA==.',
Be='Beautifulluv:BAABLgAECn8iAAQQAAgJLCLSBQDcAgAQAAgJLCLSBQDcAgARAAUJDQ72OQDWAAASAAEJkAzNUwA6AAAAAA==.Beelzabubba:BAAALgAECgkJAwAAAA==.Bekabeka:BAACLgAFFH8QAAITAAQJkR3DDwBkAQATAAQJkR3DDwBkAQAuAAQKf0IABBMACQk+JMMCAEgDABMACQk+JMMCAEgDAAkABAnTCavTAJkAAAgAAgkJAh5CABkAAAAA.Bera:BAAALgAECgUJDwABLgAECgcJCQAPAAAAAA==.Beramage:BAAALgAECgEJAQAAAA==.',
Bi='Billybobjr:BAABLgAECn85AAINAAgJGyEyBwD0AgANAAgJGyEyBwD0AgAAAA==.Bippitybop:BAAALgAECgEJAQAAAA==.',
Bl='Blackbart:BAAALgADCgcJBwAAAA==.',
Bo='Boamere:BAABLgAECn8lAAIUAAgJiRVZEgBzAQAUAAgJiRVZEgBzAQAAAA==.Botemedel:BAAALgADCgEJAQAAAA==.',
Br='Braided:BAAALgAECgIJAwAAAA==.Brakkar:BAABLgAECn8sAAIVAAgJSBNSEwDFAQAVAAgJSBNSEwDFAQAAAA==.Brandish:BAAALgADCgcJBwAAAA==.Breadstick:BAABLgAECn8qAAIKAAcJsiSJCQDlAgAKAAcJsiSJCQDlAgAAAA==.Brevik:BAAALgADCgMJAwAAAA==.Brutaal:BAAALgADCgcJCwAAAA==.Brynhild:BAAALgAFFAIJAwAAAA==.Brütaal:BAABLgAECn8cAAMNAAcJpRfqIgDlAQANAAcJpRfqIgDlAQAOAAEJAAAXkAAnAAAAAA==.',
Bu='Bubsydogo:BAAALgAECgYJCwAAAA==.Buddytheelf:BAABLgAECn8jAAMCAAcJiCSwJgAFAgACAAUJVCSwJgAFAgAWAAIJiyU5IABpAAAAAA==.Bumpyflea:BAAALgADCgUJBQAAAA==.',
Ca='Cairnsilvers:BAAALgADCgEJAQAAAA==.Camus:BAABLgAECn8WAAIJAAYJQRnUaABSAQAJAAYJQRnUaABSAQAAAA==.Capped:BAAALgADCgMJAwAAAA==.Catgirl:BAAALgAECgUJBgAAAA==.',
Ce='Cebollin:BAAALgAECgUJCAAAAA==.Celaian:BAAALgAECgUJCgABLgAECggJEwAPAAAAAA==.Celamor:BAAALgAECgQJBwAAAA==.Celasmine:BAAALgADCgYJCAAAAA==.Celpanda:BAAALgAECggJEwAAAA==.',
Ch='Charlamayne:BAAALgADCgcJBwAAAA==.Charybdia:BAABLgAECn8bAAIXAAcJjgb2gwDDAAAXAAcJjgb2gwDDAAAAAA==.Chidõri:BAACLgAFFH8OAAIOAAQJ5x11DABfAQAOAAQJ5x11DABfAQAuAAQKfy4AAw4ACQmDI0kFAEMDAA4ACQmDI0kFAEMDABgAAgnPFuUlAHkAAAAA.Chudlock:BAAALgAECgYJEQAAAA==.Chunna:BAABLgAECn8mAAIFAAkJth2RBwCLAgAFAAkJth2RBwCLAgAAAA==.Chunni:BAABLgAECn8XAAIFAAgJEQcwOADQAAAFAAgJEQcwOADQAAAAAA==.',
Co='Codap:BAAALgADCgcJBwAAAA==.Coolerfrieza:BAAALgAECgMJBAAAAA==.',
Cp='Cpr:BAABLgAECn8XAAITAAcJiCGvDwCXAgATAAcJiCGvDwCXAgAAAA==.',
Cr='Crepic:BAAALgAECgQJBAAAAA==.Cruelkitty:BAAALgAECgYJEwAAAA==.',
Cu='Cudibandit:BAAALgADCgcJDwAAAA==.',
Cy='Cynaria:BAAALgAECgEJAgAAAA==.Cyralai:BAACLgAFFH8mAAIKAAcJIxaPBAA0AgAKAAcJIxaPBAA0AgAuAAQKfxkAAgoACQlQIfEQALACAAoACQlQIfEQALACAAAA.',
Da='Dabofdeath:BAAALgAECgIJAgAAAA==.Dalov:BAABLgAECn8bAAMTAAcJSSbxBwDvAgATAAcJSSbxBwDvAgAJAAIJbx1OzwCgAAAAAA==.Dankley:BAABLgAECn8UAAIZAAcJUQjqOgAJAQAZAAcJUQjqOgAJAQAAAA==.Darkestnyte:BAAALgAECgYJBgAAAA==.Darkk:BAAALgAECgQJDAAAAA==.Darkomenz:BAAALgADCgUJBQAAAA==.Darkrhaenies:BAAALgADCgcJBwAAAA==.Darkwindx:BAAALgADCggJCQABLgAECgUJBwAPAAAAAA==.Datezero:BAAALgADCgQJBAAAAA==.',
De='Deadhealer:BAAALgADCgMJAwAAAA==.Deafknighte:BAAALgAECgMJAwAAAA==.Deathboi:BAABLgAECn8fAAILAAcJSQ/sawBDAQALAAcJSQ/sawBDAQAAAA==.Deathburgur:BAAALgAECggJEQAAAA==.Deathfromme:BAAALgAECgYJCgAAAA==.Deathstro:BAAALgAECgYJDgABLgAECgkJKQALAFwbAA==.Decayed:BAAALgAECgQJCgAAAA==.Dentridios:BAAALgADCgIJAgAAAA==.Deson:BAABLgAECn8eAAMTAAcJjxAQQgBwAQATAAcJjxAQQgBwAQAJAAUJiQgEvwC5AAAAAA==.Deviantart:BAAALgAECgEJAQAAAA==.',
Di='Diana:BAABLgAECn8XAAIHAAcJlgy8VgBEAQAHAAcJlgy8VgBEAQAAAA==.Diietriich:BAABLgAECn8gAAIEAAYJ5CQpRABrAgAEAAYJ5CQpRABrAgAAAA==.Dilligaaf:BAAALgADCgMJAwAAAA==.',
Do='Docbeanz:BAAALgADCgMJAwAAAA==.Donkypunch:BAAALgADCgQJBAAAAA==.Dontjudgemê:BAAALgADCgIJAgAAAA==.Dopie:BAAALgADCgIJAgAAAA==.Dorcina:BAAALgAECgEJAQAAAA==.',
Dr='Dracthyr:BAAALgADCgUJDQAAAA==.Dragoondpain:BAAALgAECgQJCAAAAQ==.Draltina:BAABLgAECn8XAAMBAAgJOwmkDQBaAQABAAgJOwmkDQBaAQACAAEJywLtLwEhAAAAAA==.Drazira:BAAALgAECgYJCQABLgAECgYJEgAPAAAAAA==.Drunkbera:BAAALgAECgcJBwAAAA==.',
Du='Dunks:BAAALgAECggJDgAAAA==.',
Dy='Dylghoul:BAAALgADCgUJBQAAAA==.',
['Dí']='Dírac:BAAALgAFFAMJAwAAAA==.',
Ed='Edwillei:BAAALgADCgMJAwAAAA==.',
Ef='Efforex:BAAALgADCgQJBAAAAA==.',
El='Elactoplasm:BAAALgAECgMJAwAAAA==.Ellistrae:BAAALgADCgEJAQAAAA==.Ellysia:BAAALgADCgEJAQAAAA==.',
Em='Emmel:BAAALgADCggJCwAAAA==.',
Eq='Equeslucis:BAAALgAECgcJBwAAAA==.',
Er='Erodrana:BAAALgAECgYJEgAAAA==.Eromir:BAAALgAECgUJCgAAAA==.Eryi:BAABLgAECn8lAAIDAAgJthbNFwDlAQADAAgJthbNFwDlAQAAAA==.',
Et='Ethan:BAABLgAECn8eAAMaAAkJnRuQCgDrAQAaAAcJIRiQCgDrAQAZAAQJ6CJ6OwAHAQAAAA==.',
Ev='Evonari:BAAALgADCgIJAgAAAA==.',
Ex='Exoticfrost:BAAALgADCgIJAgAAAA==.Expertnewb:BAAALgAECgIJAgABLgAECgcJIAAbALkaAA==.',
['Eí']='Eísheth:BAAALgADCgUJBAAAAA==.',
Fa='Faegen:BAAALgAECgEJAQAAAA==.Falkønn:BAAALgAECgMJAwAAAA==.Fangytooth:BAABLgAECn8uAAIVAAkJeiQDAQA6AwAVAAkJeiQDAQA6AwAAAA==.Fashaun:BAAALgAECgIJAgAAAA==.Faze:BAAALgAECgYJEAAAAA==.',
Fe='Ferrus:BAACLgAFFH8YAAMXAAcJIx+rAwD9AQAXAAcJIx+rAwD9AQAcAAQJyBl5EACwAAAuAAQKfxsAAxwACQn1JdANAIYCABcACAkBJOwcAKQCABwABwncJNANAIYCAAAA.',
Ff='Ffleuderflam:BAAALgAECgYJBgAAAA==.',
Fr='Frose:BAAALgADCgEJAQAAAA==.Frostyblast:BAAALgADCgUJBgAAAA==.',
Fu='Fupacabra:BAAALgADCgEJAQAAAA==.Furiosity:BAAALgAECgIJAwAAAA==.Fuzzybear:BAAALgAECgcJCAABLgAECgkJLgAVAHokAA==.Fuzzywar:BAAALgAECgYJBgABLgAECgkJLgAVAHokAA==.',
Ga='Gabomonk:BAABLgAFFH8FAAIGAAIJ1iQiJwDXAAAGAAIJ1iQiJwDXAAAAAA==.Gamalia:BAAALgADCgUJBQAAAA==.Garudekhan:BAAALgADCgUJBQAAAA==.',
Ge='Genreallee:BAAALgAECgYJEwAAAA==.Gernab:BAAALgADCgYJBgAAAA==.',
Gh='Ghost:BAABLgAECn8VAAIKAAYJ9xt+NgDOAQAKAAYJ9xt+NgDOAQAAAA==.',
Gi='Gianna:BAABLgAECn8VAAMTAAkJ7CMpAQCJAwATAAkJ7CMpAQCJAwAJAAIJCR7+ywClAAAAAA==.Gizzar:BAAALgADCgYJCgAAAA==.',
Gl='Glau:BAAALgADCgcJBwABLgAECgcJHQAdALwXAA==.Glimpsed:BAAALgAECgcJCQAAAA==.Globgore:BAAALgADCgIJBAAAAA==.Gloçk:BAAALgAECgMJBwABLgAECgYJEQAPAAAAAA==.',
Go='Goofy:BAABLgAECn8fAAIJAAcJYCHDJACUAgAJAAcJYCHDJACUAgAAAA==.Gorrik:BAAALgADCgUJBQAAAA==.',
Gr='Graeae:BAAALgADCggJCAAAAA==.Greyfeather:BAAALgADCgEJAgAAAA==.Grimeace:BAAALgADCgQJBAAAAA==.',
Gu='Gunduin:BAABLgAECn8eAAIHAAgJrSBBGQBCAgAHAAgJrSBBGQBCAgAAAA==.',
Gw='Gweb:BAAALgAECgIJAgAAAA==.',
Gy='Gyda:BAABLgAECn8ZAAISAAcJ7iAjCQCPAgASAAcJ7iAjCQCPAgAAAA==.Gyuyuki:BAABLgAECn8sAAIOAAcJ8w3KMgAXAQAOAAcJ8w3KMgAXAQAAAA==.',
Ha='Hakuanah:BAAALgADCgEJAQAAAA==.Halvorak:BAAALgADCgcJCgAAAA==.Harryp:BAABLgAECn8vAAMeAAkJLhTOFADpAQAeAAkJ5BLOFADpAQAfAAcJ2hBUCgAzAQAAAA==.Hast:BAAALgAECgMJBgAAAA==.',
He='Hearthzilla:BAAALgAECgEJAQABLgAECgkJHwAOANkfAA==.Hellsbow:BAAALgAECgYJDgAAAA==.Hermin:BAAALgADCgQJBgAAAA==.',
Ho='Holyhellz:BAAALgADCgEJAQAAAA==.Honeyboo:BAAALgAECgEJAQABLgAECgkJOQAKAEMiAA==.Hots:BAAALgADCgcJBwAAAA==.Hotzz:BAAALgAECgEJAQAAAA==.',
Hr='Hraesvelgr:BAAALgADCggJBwAAAA==.',
Hu='Huntavious:BAABLgAECn8nAAQVAAkJwR75AgDeAgAVAAkJwR75AgDeAgAHAAUJGhvGXgBLAQAgAAEJyBPbigAwAAAAAA==.',
['Hë']='Hëllen:BAABLgAECn8WAAIJAAYJqh/aaQCrAQAJAAYJqh/aaQCrAQAAAA==.',
Ia='Iamshinigamy:BAAALgAECgIJAgABLgAECgcJFwAEAPMaAA==.',
Ii='Iichimaru:BAAALgAECgUJBQAAAA==.',
Il='Illidupe:BAAALgADCgMJAwAAAA==.',
In='Inaoh:BAAALgAECgIJAgAAAA==.',
Iv='Ivey:BAABLgAECn8mAAIKAAgJRh4HDgCoAgAKAAgJRh4HDgCoAgAAAA==.',
Iz='Izes:BAAALgADCgEJAQAAAA==.',
Ja='Jaagganug:BAAALgADCgMJAwAAAA==.Jacenne:BAAALgAECgUJEgAAAA==.Jairus:BAAALgAECgcJBwAAAA==.',
Jd='Jdirty:BAAALgAECgUJDwAAAA==.',
Je='Jellytime:BAAALgAECgEJAwAAAA==.',
Jo='Josephyn:BAAALgAECgMJAwABLgAFFAUJIAANANIcAA==.',
Ju='Jugernaut:BAAALgAECgEJAQAAAA==.Jumpmann:BAAALgAECgMJAwAAAA==.Justdesserts:BAAALgAECgEJAQAAAA==.Justix:BAAALgADCggJEwAAAA==.',
Ka='Kadaffy:BAAALgAECgEJAQAAAA==.Kakusu:BAAALgAECgYJEQAAAA==.Kakuta:BAAALgAECgUJCAABLgAECggJEAAPAAAAAA==.Kakutá:BAAALgAECggJEAAAAA==.Kalru:BAAALgADCgQJCwAAAA==.Kargar:BAAALgAECgEJAQAAAA==.Katharsis:BAABLgAECn8fAAIJAAkJ4BQKPwDBAQAJAAkJ4BQKPwDBAQAAAA==.',
Ke='Keba:BAAALgADCggJDwABLgAFFAQJEAATAJEdAA==.Keévs:BAAALgADCgQJBAAAAA==.',
Kh='Khalidisi:BAABLgAECn8mAAQTAAkJLRmXIACzAQATAAkJLRmXIACzAQAJAAcJJAoWhwAWAQAIAAEJIx5PMgBQAAAAAA==.Khalizar:BAAALgAFFAIJAgAAAA==.Kharazim:BAAALgADCgEJAQABLgAECgcJIAAXAHsYAA==.Khenja:BAAALgAECgEJAQAAAA==.Khál:BAAALgADCgYJBgAAAA==.',
Ki='Killerelf:BAAALgAECgIJAgAAAA==.',
Kk='Kkiilleerr:BAAALgAECgQJBAAAAA==.',
Ko='Kobbaltcilar:BAAALgAECgQJBAAAAA==.Koraleena:BAAALgAECgQJBAAAAA==.Korbo:BAABLgAECn8fAAMOAAcJBx2wHgCXAQAOAAUJBh6wHgCXAQANAAMJOxqIYgDIAAAAAA==.Korbulo:BAAALgAECgYJDQAAAA==.Korlothel:BAABLgAECn8gAAIIAAkJ2AbFGQD2AAAIAAkJ2AbFGQD2AAAAAA==.',
Kr='Krumpus:BAAALgAECgcJEwAAAA==.',
Ku='Kungfuuy:BAABLgAECn8bAAIGAAYJyh8bGgCXAQAGAAYJyh8bGgCXAQAAAA==.Kurtevade:BAAALgAECgEJAgAAAA==.',
Kw='Kwetnepthl:BAAALgAECgEJAQAAAA==.',
Ky='Kynsong:BAAALgAECgUJDQAAAA==.',
['Kà']='Kàlbrews:BAABLgAECn8+AAIGAAkJvyYdAACNAwAGAAkJvyYdAACNAwAAAA==.',
La='Lainiee:BAAALgADCgEJAQAAAA==.Lavismad:BAEBLgAECn80AAQZAAkJDCVqAQBEAwAZAAkJ2CRqAQBEAwAUAAcJniCWCQARAgAaAAEJRiV3MgBpAAAAAA==.Lavoc:BAEALgADCgcJBwABLgAECgkJNAAZAAwlAA==.Lavv:BAEALgAECgYJCAABLgAECgkJNAAZAAwlAA==.',
Le='Legendary:BAAALgAECgYJCwAAAA==.Leshah:BAAALgAECgIJAgAAAA==.',
Li='Lichkingdied:BAAALgADCgUJBQAAAA==.Lightndpain:BAAALgAECgQJBQAAAA==.Lilypetal:BAAALgAECgQJBwAAAA==.Littlebucket:BAAALgADCgEJAQAAAA==.',
Lo='Lockdpain:BAAALgAECgYJGAABLgAECgQJCAAPAAAAAQ==.Logov:BAAALgAECgYJDwAAAA==.Loraine:BAAALgAECgEJAQAAAA==.Loìsbethe:BAAALgAECgQJBAAAAA==.',
Lu='Luciferra:BAAALgAECggJCwABLgAFFAUJIAANANIcAA==.Lukey:BAAALgAECgMJAwAAAA==.Lunartemis:BAAALgAECgUJCAABLgAFFAMJAwAPAAAAAA==.',
['Lö']='Lörax:BAAALgADCgQJBQAAAA==.',
['Lû']='Lûnafreya:BAAALgAECggJEgAAAA==.',
Ma='Maelera:BAAALgADCgkJDAAAAA==.Maetromundo:BAAALgAECgEJAQAAAA==.Magentas:BAAALgADCgIJAgAAAA==.Magickul:BAAALgADCggJCAAAAA==.Mahlah:BAAALgAECgQJBAAAAA==.Malaboo:BAAALgAECgEJAQABLgAECgkJOQAKAEMiAA==.Maletsy:BAAALgAECgEJAQABLgAECggJHgAHAK0gAA==.Maliboo:BAABLgAECn85AAMKAAkJQyLNAgBzAwAKAAkJQyLNAgBzAwAhAAIJnwnPZwAzAAAAAA==.Maxamus:BAAALgAECgUJEgAAAA==.',
Mc='Mcflurry:BAAALgAECgQJCAAAAA==.',
Me='Medarisa:BAAALgAECgYJCwAAAA==.Medavia:BAAALgADCgUJBQAAAA==.Melisandr:BAAALgAECgMJBQAAAA==.Merkenier:BAABLgAECn8eAAIhAAgJDQvkLwAEAQAhAAgJDQvkLwAEAQAAAA==.Merkur:BAAALgADCgkJCQABLgAECggJHgAhAA0LAA==.',
Mi='Midnitehunt:BAAALgAECgQJBAAAAA==.Miragia:BAAALgAECgUJBwAAAA==.Missmayhem:BAAALgAECgUJCAAAAA==.Missmayhemm:BAAALgADCgQJBgAAAA==.',
Mo='Modifiedmix:BAABLgAECn8YAAIHAAcJKhNURwByAQAHAAcJKhNURwByAQAAAA==.Modsabadtank:BAAALgAECgUJBwABLgAECgcJGAAHACoTAA==.Mokomohama:BAAALgAECgcJBwAAAA==.Monatazumaa:BAAALgAECgEJAgAAAA==.Moonbloom:BAAALgAECgQJCAABLgAFFAUJIAANANIcAA==.Mopeezie:BAAALgAECgEJAQAAAA==.Mordicant:BAAALgADCgEJAQABLgAECgYJCAAPAAAAAA==.Morella:BAABLgAECn81AAIWAAcJmQ4HGQCDAQAWAAcJmQ4HGQCDAQAAAA==.',
Mu='Mucduck:BAAALgADCgEJAQAAAA==.Mustakrakish:BAAALgAECgEJAQAAAA==.Mustaz:BAAALgAECgkJBQAAAA==.',
My='Mym:BAAALgADCgcJBAAAAA==.Mystics:BAAALgAECgQJBAAAAA==.Mythrunduil:BAAALgADCgEJAQAAAA==.',
['Mé']='Médb:BAABLgAECn8jAAMEAAcJ8xsrSADAAQAEAAcJdhorSADAAQAiAAMJFR34BQD8AAAAAA==.',
Na='Nathrold:BAAALgAECgIJBAABLgAECgYJEQAPAAAAAA==.',
Ne='Neptune:BAACLgAFFH8gAAINAAUJ0hw5CQC3AQANAAUJ0hw5CQC3AQAuAAQKfx4AAw0ACQnRHxgHAAIDAA0ACQnRHxgHAAIDAA4ABwkkDtE0AIQBAAAA.Nerfdks:BAAALgAECgcJCAAAAA==.Nerfpaladins:BAABLgAECn8fAAMIAAcJpRK/GQD2AAAJAAYJthG5fQAnAQAIAAcJJBG/GQD2AAAAAA==.Neruess:BAAALgADCgUJBQAAAA==.Nezzuko:BAAALgAECgcJBwAAAA==.',
Ni='Nightbird:BAABLgAECn8dAAMdAAcJvBdkHABWAQAdAAcJThdkHABWAQAjAAYJ8BWfDgAsAQAAAA==.Ninediewatt:BAAALgAECgEJAQAAAA==.Nivella:BAAALgAECgYJCgAAAA==.Nixaana:BAAALgADCgYJBgAAAA==.Niçki:BAAALgADCgMJAwAAAA==.',
No='Notlockz:BAAALgADCgIJAgAAAA==.Novah:BAAALgADCgQJBQAAAA==.Noydb:BAAALgADCgYJBgABLgAECggJJQAUAIkVAA==.',
Nu='Nuah:BAAALgADCgYJDQAAAA==.',
Ny='Nyxsia:BAEALgAFFAEJAQABLgAFFAYJEQAZAIoYAA==.',
['Nè']='Nèo:BAAALgADCgcJBwAAAA==.',
Ob='Obayi:BAAALgAECgUJBwAAAA==.',
Og='Ogmadmonk:BAACLgAFFH8JAAIcAAMJBxEEDQDuAAAcAAMJBxEEDQDuAAAuAAQKfy8AAhwACQmVIT4EAL8CABwACQmVIT4EAL8CAAAA.',
Ok='Oktobra:BAAALgAECgYJEAAAAA==.',
On='Onetrickpony:BAAALgADCgYJCQAAAA==.Onos:BAAALgAECgIJAgAAAA==.Onosm:BAAALgAECgQJBAAAAA==.',
Or='Orioan:BAAALgAECgMJBAAAAA==.Orux:BAAALgAECgYJBgAAAA==.',
Os='Osenya:BAAALgAECgYJBgABLgAECgkJLgAhAJoiAA==.Osun:BAAALgADCggJCwAAAA==.',
Ou='Ouroboro:BAAALgADCgUJBQAAAA==.',
Ow='Owlbat:BAAALgAECgEJAQAAAA==.',
Pa='Padremort:BAAALgADCgYJBgAAAA==.Palantyr:BAABLgAECn9VAAIOAAgJtxqZGgA+AgAOAAgJtxqZGgA+AgAAAA==.Paly:BAAALgAECgEJAQAAAA==.Para:BAAALgAECgQJBAAAAA==.Patrician:BAABLgAECn8fAAIkAAcJgBLuBwBmAQAkAAcJgBLuBwBmAQAAAA==.',
Pe='Peehat:BAAALgADCgcJCQAAAA==.Penutbutter:BAAALgAECgEJAQAAAA==.Pepegasus:BAAALgADCgcJBwAAAA==.',
Ph='Phobos:BAAALgADCgQJCAAAAA==.Phyloren:BAAALgADCgUJBgAAAA==.',
Pi='Pigsticker:BAAALgAECgQJBQAAAA==.Pixyfire:BAAALgAECgQJBAABLgAECgkJNAATAIwiAA==.',
Po='Pokingharder:BAAALgAECggJCgAAAA==.',
Pu='Pulcherrimus:BAAALgAECgEJAgAAAA==.Purgeem:BAAALgADCgUJBQAAAA==.Pushpop:BAAALgAECgYJCQABLgAECggJVQAOALcaAA==.',
Pw='Pwiest:BAAALgADCgcJEAAAAA==.',
Qu='Quetzalcoatl:BAABLgAECn8WAAIlAAYJ9BzmDQClAQAlAAYJ9BzmDQClAQAAAA==.',
Ra='Raambox:BAAALgAECgQJBAAAAA==.Radak:BAAALgADCgYJDAAAAA==.Raddish:BAAALgAECgYJEAAAAA==.Rahjlynn:BAAALgADCgcJBwAAAA==.Rahken:BAAALgAECgcJBwAAAA==.Raiinn:BAAALgADCgUJBQAAAA==.Raylee:BAABLgAECn86AAMCAAkJniH/CgDHAgACAAgJrx//CgDHAgAWAAcJfCEPCABEAgAAAA==.Razuki:BAABLgAECn80AAMTAAkJjCJzAgBUAwATAAkJjCJzAgBUAwAJAAcJ9hc8RgCrAQAAAA==.',
Rf='Rfd:BAAALgADCgcJBwABLgAECgcJEQAPAAAAAA==.',
Rh='Rhaenies:BAAALgAECgYJEAAAAA==.Rharr:BAAALgADCgkJDAAAAA==.Rhovanion:BAAALgAECgUJCQAAAA==.Rhuac:BAABLgAECn8hAAIKAAgJCRRPKADIAQAKAAgJCRRPKADIAQAAAA==.',
Ri='Risakah:BAAALgAECggJCAAAAA==.',
Ro='Rorschach:BAAALgAECgYJCAAAAA==.Rosefist:BAEALgADCgcJCAABLgAFFAUJDwASAM0SAA==.Rosemourne:BAEALgAECgIJAgABLgAFFAUJDwASAM0SAA==.Roseykat:BAABLgAECn8bAAIHAAYJtwyYbAALAQAHAAYJtwyYbAALAQAAAA==.Roshwyn:BAABLgAECn8UAAIHAAgJHgsHSQBtAQAHAAgJHgsHSQBtAQAAAA==.',
Ru='Ruckus:BAABLgAECn8nAAIJAAgJuRYPPwApAgAJAAgJuRYPPwApAgAAAA==.',
Sa='Saberwar:BAAALgAECgEJAQABLgAECgMJAwAPAAAAAA==.Saintfury:BAAALgAECgQJBQAAAA==.Saintsfear:BAABLgAECn8fAAIZAAcJ4w++LgBFAQAZAAcJ4w++LgBFAQAAAA==.Sanchito:BAAALgADCgMJAwAAAA==.Saphalia:BAAALgADCgMJAwAAAA==.Saradomin:BAAALgADCgUJBAAAAA==.Sareenastar:BAABLgAECn8uAAMQAAkJlCYdAAD2AwAQAAkJlCYdAAD2AwARAAEJ3wkOYwAyAAAAAA==.Sasae:BAABLgAECn8XAAIGAAYJyhB1NQDsAAAGAAYJyhB1NQDsAAAAAA==.',
Sc='Scorias:BAAALgADCgQJAwAAAA==.',
Se='Selisztraza:BAAALgADCgEJAQAAAA==.Sephiróth:BAAALgADCgUJCAAAAA==.Sereni:BAAALgADCgQJBAAAAA==.Serenity:BAAALgAECgYJCAAAAA==.Serenitynow:BAAALgAECgEJAgAAAA==.Sewald:BAAALgAECgIJBAAAAA==.',
Sh='Shadowzbane:BAAALgAECgIJAgAAAA==.Shahasha:BAAALgADCgEJAQAAAA==.Shakeybop:BAAALgAECgQJBAAAAA==.Shalen:BAABLgAECn8hAAQeAAgJWBWJHQCaAQAeAAgJShWJHQCaAQAfAAYJoQ2ZHQBCAQAlAAQJsg7GIwCBAAAAAA==.Sharker:BAAALgADCgYJBgAAAA==.Sharpie:BAAALgADCgcJCgAAAA==.Sheer:BAAALgAECgcJEgAAAA==.Sheraa:BAABLgAECn8YAAIIAAcJNxPzEABbAQAIAAcJNxPzEABbAQAAAA==.Shiftystrike:BAABLgAECn8WAAImAAcJPx/wCgAVAgAmAAcJPx/wCgAVAgAAAA==.Shifushield:BAAALgAECgcJBgAAAA==.Shireshannon:BAAALgAECgYJDAAAAA==.Shrunkador:BAACLgAFFH8IAAIOAAMJUAyFIgDFAAAOAAMJUAyFIgDFAAAuAAQKfygAAg4ACQmLHYoPACgCAA4ACQmLHYoPACgCAAAA.',
Si='Silk:BAAALgAECgYJDgAAAA==.Silmarkthree:BAABLgAECn80AAIEAAkJpRhmJQBGAgAEAAkJpRhmJQBGAgAAAA==.Sinbåd:BAAALgAECgcJBwAAAA==.Sisterstar:BAAALgADCgMJAwAAAA==.',
Sl='Sleety:BAAALgAECgIJBQAAAA==.Slipknoth:BAACLgAFFH8YAAMRAAYJtBpIBQCtAQARAAYJtBpIBQCtAQASAAUJWwmuEgBZAQAuAAQKfygABBAACQnOGfkgANsBABAABwntF/kgANsBABEABwm1JLIUANcBABIABAnOGU8xAPQAAAAA.',
Sn='Snekhain:BAAALgADCgMJAwAAAA==.Snuffaluffa:BAAALgAECgMJAwAAAA==.',
So='Somatra:BAAALgADCgkJCQAAAA==.Sorean:BAACLgAFFH8MAAIVAAQJ2haTCABcAQAVAAQJ2haTCABcAQAuAAQKfy8ABAcACQm+IFYhAD0CAAcABwlUG1YhAD0CABUABwlnHYgPAPMBACAABwlQGv0vALUBAAAA.',
Sp='Specialmove:BAAALgAFFAEJAgAAAA==.Spookydookie:BAAALgADCgkJCgAAAA==.',
St='Staghealz:BAAALgADCgYJBgAAAA==.Stifs:BAABLgAECn8iAAIIAAgJRBEEFwBlAQAIAAgJRBEEFwBlAQAAAA==.Stinkinglily:BAAALgAECgEJAgAAAA==.Strunrage:BAEALgAECgUJBQABLgAECggJNwAJANglAA==.Stÿx:BAABLgAECn8ZAAInAAYJ6gXqLQCaAAAnAAYJ6gXqLQCaAAAAAA==.',
Su='Sugarbomb:BAAALgADCgMJBAAAAA==.',
Sy='Sykotyk:BAAALgAECgkJDwAAAA==.Sylverfox:BAAALgAECgMJAwABLgAECggJDQAPAAAAAA==.Synchestra:BAAALgADCgcJCgAAAA==.',
Ta='Tadagain:BAABLgAECn8VAAMJAAUJ8RFbowDlAAAJAAUJ8RFbowDlAAATAAQJ2gV2dgChAAAAAA==.Tagrith:BAAALgADCgMJAwAAAA==.Tankybears:BAABLgAECn8sAAMhAAkJzxpjCgBjAgAhAAkJzxpjCgBjAgAKAAgJ6hvvQABFAQAAAA==.Tarmalok:BAAALgAECgEJAQAAAA==.Tazera:BAAALgAECgUJCwAAAA==.',
Te='Telekinesis:BAABLgAECn8iAAIVAAgJvxAsFgCoAQAVAAgJvxAsFgCoAQAAAA==.Tenbinza:BAAALgAECgMJBAAAAA==.Teos:BAABLgAECn8vAAIYAAkJBxmLBABWAgAYAAkJBxmLBABWAgAAAA==.',
Th='Thainé:BAAALgAECgMJBgAAAA==.Thaldrassian:BAAALgADCgQJBAAAAA==.Thehatred:BAAALgADCgYJBgAAAA==.Therondar:BAAALgADCgEJAQAAAA==.Thiyan:BAAALgADCgMJAwAAAA==.Thromar:BAABLgAECn8VAAIEAAcJiBWvgADPAQAEAAcJiBWvgADPAQAAAA==.Thunderlily:BAABLgAECn8gAAMbAAcJuRrpBgCgAQAEAAcJRBnXSQC7AQAbAAcJZhfpBgCgAQAAAA==.Thünder:BAAALgADCgcJBwABLgAECgcJFgALAKQeAA==.',
Ti='Tinderbeef:BAAALgADCgcJCAAAAA==.Tinychaos:BAAALgAECgkJCQAAAA==.Tinyround:BAAALgAECgEJAQAAAA==.Tirra:BAAALgAECggJDQAAAA==.',
To='Toranth:BAABLgAECn8tAAITAAgJRhZbFgALAgATAAgJRhZbFgALAgAAAA==.Torq:BAABLgAECn8XAAIEAAYJ/BmShwDCAQAEAAYJ/BmShwDCAQABLgAECgcJFwATAIghAA==.Torqumada:BAAALgAECgQJBQAAAA==.Toxian:BAABLgAECn8jAAIXAAcJyxS8QgBxAQAXAAcJyxS8QgBxAQAAAA==.Toxicelitist:BAABLgAECn8oAAMWAAgJcQ1oCwA6AQAWAAgJcQ1oCwA6AQACAAEJmgEMGQEbAAAAAA==.',
Tr='Treedemon:BAABLgAECn8qAAIXAAkJLCRoBQAFAwAXAAkJLCRoBQAFAwAAAA==.Treedin:BAAALgAECgMJAwAAAA==.Trymw:BAAALgADCgIJAgAAAA==.',
Tu='Tutimon:BAAALgADCgUJBQAAAA==.',
Ty='Tybearon:BAAALgADCgcJBwAAAA==.Tyreid:BAAALgADCgMJAwAAAA==.Tyrelitha:BAAALgADCgcJCAAAAA==.',
Ud='Udderchoad:BAAALgADCgEJAQAAAA==.',
Uh='Uhura:BAAALgADCgEJAQAAAA==.',
Ul='Ulfrir:BAABLgAECn8lAAMHAAkJLR4pCgDFAgAHAAkJLR4pCgDFAgAgAAMJMQoqbwCCAAAAAA==.Ultradukes:BAAALgADCgcJGQAAAA==.',
Un='Unatural:BAAALgAECgUJBQAAAA==.Unleashed:BAAALgAECgUJCgAAAA==.',
Va='Valarea:BAAALgADCgEJAQAAAA==.Valock:BAAALgAECgYJDAAAAA==.Valris:BAAALgAECgMJBAAAAA==.Vandham:BAAALgADCgEJAQAAAA==.Vannis:BAAALgADCgYJBgAAAA==.Vanshifty:BAABLgAECn81AAIKAAkJ/CJDAwBkAwAKAAkJ/CJDAwBkAwAAAA==.',
Ve='Veilf:BAAALgADCgYJDAAAAA==.Velf:BAAALgAECgIJAgAAAA==.Velrus:BAAALgAECgYJDAAAAA==.Venli:BAAALgAECgEJAQAAAA==.Venombite:BAAALgADCgMJAwAAAA==.',
Vi='Viktorax:BAAALgAECgYJCwAAAA==.Vincevega:BAAALgAECgMJAwAAAA==.Virtueozo:BAABLgAECn8aAAIlAAgJEBfODwA+AgAlAAgJEBfODwA+AgAAAA==.',
Vo='Volam:BAAALgAECgQJBAAAAA==.',
Vy='Vyx:BAAALgAECgYJBgABLgAECgYJGQAnAOoFAA==.',
Wa='Waffle:BAAALgAECgUJDgABLgAECggJGgAHAFEOAA==.Waldhorn:BAAALgAECgYJBgAAAA==.Wangwen:BAAALgADCgIJAgAAAA==.Wargue:BAABLgAECn8VAAIZAAYJjRvLKgBbAQAZAAYJjRvLKgBbAQAAAA==.',
We='Weebsz:BAAALgADCgQJBAAAAA==.Welindis:BAAALgAECgYJEAABLgAECggJKAAXACwRAA==.Wetkith:BAAALgADCgUJBQAAAA==.',
Wi='Windrider:BAAALgADCgIJAgAAAA==.Windwraith:BAAALgAECgIJAgAAAA==.Wizzard:BAAALgAECggJHAAAAQ==.',
Xa='Xaiyara:BAAALgADCgUJBQAAAA==.Xandaka:BAAALgADCgQJBAAAAA==.',
Xe='Xephir:BAAALgAECggJCgAAAA==.',
Xi='Xidied:BAABLgAECn8wAAIGAAkJJSE8AwDyAgAGAAkJJSE8AwDyAgAAAA==.Xilon:BAAALgADCgcJBwABLgAECgkJLgAhAJoiAA==.Xilra:BAABLgAECn8uAAMhAAkJmiLoBgCiAgAhAAkJmiLoBgCiAgAmAAEJmhEEMgA1AAAAAA==.Xilrot:BAAALgAECgcJDAABLgAECgkJLgAhAJoiAA==.Xilzen:BAAALgAECgUJEAABLgAECgkJLgAhAJoiAA==.Xinia:BAAALgADCgEJAQAAAA==.',
Xz='Xzed:BAAALgADCgEJAQAAAA==.',
Ye='Yew:BAAALgADCgMJAwAAAA==.',
Yi='Yikers:BAACLgAFFH8KAAITAAMJoR6bGwD5AAATAAMJoR6bGwD5AAAuAAQKfyUAAhMACQm6IRIFAAUDABMACQm6IRIFAAUDAAAA.',
Yr='Yridai:BAAALgAECgYJCAAAAA==.',
Za='Zarsher:BAAALgADCgIJAgAAAA==.',
Zd='Zdk:BAAALgAECgEJAQABLgAECgcJGgAHAIAZAA==.',
Ze='Zeldy:BAABLgAECn8lAAIHAAgJHBmpLgDQAQAHAAgJHBmpLgDQAQAAAA==.Zenestraza:BAAALgADCgQJBAABLgAECgcJIAAXAHsYAA==.Zenthareal:BAABLgAECn8gAAIXAAcJexiWOgCQAQAXAAcJexiWOgCQAQAAAA==.Zeuc:BAAALgADCgMJAwAAAA==.Zeuus:BAAALgADCgMJBAAAAA==.',
Zh='Zhirldk:BAAALgAECgcJEQAAAA==.Zhulgarosh:BAAALgADCgUJBQAAAA==.',
Zi='Zillidan:BAAALgAECgEJAQABLgAECgcJGgAHAIAZAA==.',
Zm='Zmaster:BAABLgAECn8aAAIHAAcJgBmmNwCrAQAHAAcJgBmmNwCrAQAAAA==.',
Zo='Zobeast:BAAALgADCgQJBAAAAA==.',
Zr='Zret:BAAALgAECgYJCgABLgAECgcJGgAHAIAZAA==.',
Zw='Zwar:BAAALgAECgEJAQABLgAECgcJGgAHAIAZAA==.',
Zy='Zynith:BAAALgAECgYJBgAAAA==.',
['Zö']='Zöey:BAAALgADCgQJBQAAAA==.',
['Çl']='Çloudz:BAAALgADCgMJAwAAAA==.',
['Ða']='Ðark:BAACLgAFFH8NAAIHAAMJyBHxNADuAAAHAAMJyBHxNADuAAAuAAQKfycAAgcACQm5HAQVAI8CAAcACQm5HAQVAI8CAAAA.',
['Ðr']='Ðr:BAABLgAECn8eAAMNAAkJ/Br1IgANAgANAAcJThr1IgANAgAOAAYJ7xeDIwB1AQAAAA==.',
['ßl']='ßlack:BAAALgADCgEJAQAAAA==.',
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
