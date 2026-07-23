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

local lookup = {'Unknown-Unknown','Warlock-Demonology','Warlock-Affliction','Paladin-Retribution','Shaman-Restoration','Shaman-Elemental','Druid-Feral','Mage-Arcane','Mage-Frost','Mage-Fire','Druid-Guardian','DeathKnight-Blood','Priest-Holy','Warlock-Destruction','Shaman-Enhancement','Warrior-Protection','Warrior-Fury','DeathKnight-Unholy','Hunter-Survival','Paladin-Protection','Hunter-BeastMastery','Rogue-Outlaw','Druid-Restoration','Druid-Balance','Hunter-Marksmanship','Rogue-Assassination','Paladin-Holy','DemonHunter-Vengeance','DemonHunter-Devourer','Priest-Discipline','Monk-Windwalker','Monk-Mistweaver','DemonHunter-Havoc','Warrior-Arms','Rogue-Subtlety','Priest-Shadow','Evoker-Augmentation','DeathKnight-Frost','Monk-Brewmaster','Evoker-Preservation','Evoker-Devastation',}
local provider = {region='US',realm='EchoIsles',name='US',type='weekly',zone=46,date='2026-07-19',data={Aa='Aaelless:BAAALgAECgMJBAAAAA==.Aardz:BAAALgAECgYJCQAAAA==.',
Ab='Abeblinkin:BAAALgADCgkJDgAAAA==.Abrakadavar:BAAALgAECgQJBQAAAA==.Abraxís:BAAALgAECgMJAwABLgAECgMJAwABAAAAAA==.Abräxis:BAAALgADCgkJCQABLgAECgMJAwABAAAAAA==.',
Ac='Acindis:BAAALgAFFAIJAgAAAA==.Ackspez:BAAALgADCgYJBgAAAA==.',
Ae='Aeless:BAABLgAECn8oAAMCAAkJRCKECwDyAgACAAkJRCKECwDyAgADAAEJAABgEgAAAAAAAA==.Aelless:BAAALgAECgYJCAAAAA==.Aenest:BAAALgADCggJCAAAAA==.',
Ai='Aiko:BAAALgADCgEJAQAAAA==.Aithinne:BAABLgAECn8YAAIEAAYJ/wmJIwCiAAAEAAYJ/wmJIwCiAAAAAA==.',
Ak='Akanah:BAAALgADCgcJBwAAAA==.',
Al='Alch:BAAALgAECgUJAQAAAA==.Alfira:BAAALgAECgYJEwAAAA==.Alghul:BAAALgAECgMJBAABLgAECgYJEwABAAAAAA==.',
Am='Amoredis:BAAALgADCgYJDQAAAA==.Amorlorin:BAAALgADCggJEwAAAA==.',
An='Anklbiterkat:BAAALgADCgQJBAAAAA==.Anume:BAAALgADCgkJFQAAAA==.',
Ar='Aragan:BAABLgAECn8bAAMFAAgJLBbfBQDOAQAFAAcJXRbfBQDOAQAGAAYJnw5eDwCgAAAAAA==.Aravis:BAABLgAECn8sAAIHAAgJ6w+oGQBBAQAHAAgJ6w+oGQBBAQAAAA==.Arese:BAABLgAECn8fAAQIAAYJTiZ/AwA0AgAIAAUJTiZ/AwA0AgAJAAMJlyTzEgHYAAAKAAEJAABTDABpAAAAAA==.Argopol:BAABLgAECn8iAAILAAgJhyFUBgCbAgALAAgJhyFUBgCbAgABLgAECgkJLwAMAEMeAA==.Aron:BAAALgADCgMJAgAAAA==.',
As='Ashandra:BAAALgADCgkJDwAAAA==.Ashlyssra:BAABLgAECn8fAAINAAkJYh0xCQDWAgANAAkJYh0xCQDWAgAAAA==.Asphonix:BAAALgADCgEJAQAAAA==.',
Aw='Awsomesause:BAAALgAECgQJBgAAAA==.',
Az='Azuri:BAAALgAFFAMJAwAAAA==.Azzif:BAABLgAECn8kAAIOAAcJdwXtJwB4AAAOAAcJdwXtJwB4AAAAAA==.Azzraell:BAAALgADCgEJAQAAAA==.',
Ba='Babaorumm:BAAALgAECgQJBAAAAA==.Babasha:BAACLgAFFH8JAAIPAAQJ6Qv7CwACAQAPAAQJ6Qv7CwACAQAuAAQKfxsAAw8ABgmSH0sQAK0BAA8ABgmSH0sQAK0BAAUABgnADcJPAEUBAAAA.Babybluz:BAABLgAECn8wAAIJAAgJChBfDgBIAQAJAAgJChBfDgBIAQAAAA==.Baconloaf:BAAALgAECgUJCQAAAA==.Baifeng:BAAALgADCgkJFgAAAA==.Baldilocks:BAAALgADCgQJDAAAAA==.Barlas:BAAALgAECgEJAQAAAA==.Bat:BAAALgADCgEJAQAAAA==.Baunshee:BAAALgAECgcJBwABLgAFFAIJBQAGABEDAA==.',
Be='Beauriley:BAABLgAECn8xAAMQAAkJHBWsEwC0AQAQAAkJHBWsEwC0AQARAAEJnA7vnwA1AAAAAA==.Behomethan:BAABLgAECn8mAAMFAAkJZBtJKgDlAQAFAAgJOBpJKgDlAQAGAAgJABTTMgBxAQAAAA==.Berians:BAAALgAECgEJAgAAAA==.Beyonsláy:BAAALgAECgYJEQAAAA==.',
Bh='Bhipbookie:BAAALgAECgEJBAAAAA==.',
Bi='Billbetaray:BAAALgADCgMJAwAAAA==.',
Bl='Bluerift:BAAALgADCgEJAQAAAA==.Blux:BAAALgAECgEJAQAAAA==.',
Bo='Bobbyb:BAABLgAECn8XAAISAAcJyxkUVwDAAQASAAcJyxkUVwDAAQAAAA==.Bolton:BAAALgADCgMJAwAAAA==.Bombchele:BAAALgAECgYJBgABLgAECgkJGQASAPMaAA==.Boneulngtime:BAAALgADCgUJCgAAAA==.Boon:BAAALgAECgIJAgAAAA==.Bowlofwrong:BAAALgAECgYJBwAAAA==.',
Br='Bratticusrex:BAABLgAECn8nAAIRAAgJDwt7QQA/AQARAAgJDwt7QQA/AQAAAA==.Brazier:BAAALgAECgQJBAAAAA==.Bresowar:BAAALgAECggJEAAAAA==.Brieseis:BAAALgADCgUJBQABLgAECggJCAABAAAAAA==.Brynthe:BAAALgADCgEJAQAAAA==.',
Bu='Bunnylicious:BAABLgAECn9nAAIFAAkJGyatAADZAwAFAAkJGyatAADZAwAAAA==.Bunnymedic:BAABLgAECn8WAAINAAYJIh1LHgDSAQANAAYJIh1LHgDSAQABLgAECgkJZwAFABsmAA==.',
Ca='Caebrylla:BAABLgAECn88AAITAAkJgg8yFQD6AQATAAkJgg8yFQD6AQAAAA==.Calistie:BAAALgAECgIJAgAAAA==.Calver:BAAALgADCgcJCwAAAA==.Camigatu:BAAALgADCgQJBAAAAA==.Camil:BAABLgAECn8cAAIUAAkJiwtbHQAqAQAUAAkJiwtbHQAqAQABLgAFFAQJFgAVAIgJAA==.Cang:BAAALgAECgIJAgAAAA==.Capulin:BAABLgAECn8lAAIRAAkJsBYQHgD+AQARAAkJsBYQHgD+AQAAAA==.Catdurid:BAAALgADCgYJBgAAAA==.Cayleta:BAAALgADCgUJBQAAAA==.',
Ce='Cecilbrown:BAAALgADCgcJBgAAAA==.Cecimorte:BAABLgAECn86AAIMAAkJ4BmbDQAwAgAMAAkJ4BmbDQAwAgAAAA==.Cephalopod:BAABLgAECn8UAAIWAAgJ1RXEAwD5AQAWAAgJ1RXEAwD5AQAAAA==.',
Ch='Chargeasap:BAAALgAECgMJAwAAAA==.Charttopper:BAAALgAECgYJCQABLgAECgkJFQAUAGUUAA==.Chibby:BAAALgADCgMJAwAAAA==.Chimichanga:BAAALgAECgcJDAABLgAECgkJFQAUAGUUAA==.Chonker:BAABLgAECn84AAMXAAkJdSB/BwBAAwAXAAkJdSB/BwBAAwAYAAcJVwzlOwAiAQAAAA==.Chorelock:BAAALgADCgEJAQABLgAECgkJFQAUAGUUAA==.Chronormu:BAAALgAECgMJAwAAAA==.Chuckforrest:BAAALgAECgQJBAAAAA==.Chultis:BAABLgAECn8bAAQHAAgJuhQrEwCLAQAHAAgJuhQrEwCLAQAYAAEJ2wH5jgAeAAAXAAEJAgLF6QAbAAAAAA==.',
Ci='Cihato:BAABLgAECn83AAILAAkJIxtQCQBVAgALAAkJIxtQCQBVAgAAAA==.',
Cl='Claxious:BAABLgAECn8iAAIZAAkJlRmeBgAoAgAZAAkJlRmeBgAoAgAAAA==.Claye:BAACLgAFFH8TAAIFAAQJcRTyOAD/AAAFAAQJcRTyOAD/AAAuAAQKfysAAgUACQnPHJURAMECAAUACQnPHJURAMECAAAA.Clubbinseals:BAAALgAECgMJBAAAAA==.',
Co='Coldshoulder:BAABLgAECn86AAMJAAkJfx8wGwC4AgAJAAkJfx8wGwC4AgAKAAQJaxOMCwC3AAAAAA==.Corelas:BAABLgAECn87AAIJAAkJfhFmCACwAQAJAAkJfhFmCACwAQAAAA==.Corfellyn:BAAALgAECggJBAAAAA==.Couchdad:BAAALgAECgYJEwAAAA==.',
Cr='Crazymadman:BAABLgAECn8qAAIaAAYJWQqmAgDdAAAaAAYJWQqmAgDdAAAAAA==.Crescentbane:BAAALgAECgEJAQAAAA==.Crushingblow:BAAALgAECgkJAwAAAA==.',
Cy='Cyon:BAAALgADCgEJAQAAAA==.',
Da='Daalaria:BAAALgADCgEJAQAAAA==.Darkle:BAAALgAECgEJAQAAAA==.Darkone:BAAALgAECgEJAQAAAA==.Daul:BAAALgADCgEJAQAAAA==.Dawnson:BAABLgAECn8oAAIbAAkJbCB+BQA7AwAbAAkJbCB+BQA7AwAAAA==.',
De='Deadzexcs:BAABLgAECn8cAAIaAAcJtw79AQAZAQAaAAcJtw79AQAZAQAAAA==.Deathsnear:BAAALgAECgEJAQAAAA==.Demogless:BAABLgAECn9IAAMcAAgJyg+KAwDtAAAdAAgJjgsRcgA+AQAcAAYJLRCKAwDtAAAAAA==.Desyrel:BAAALgAECgYJBgABLgAECgkJIgAVAEoMAA==.Devyn:BAAALgADCgUJBQAAAA==.',
Dh='Dharknight:BAAALgAECgEJAQAAAA==.',
Di='Didimissfire:BAEBLgAECn87AAIVAAkJlxShOAD7AQAVAAkJlxShOAD7AQAAAA==.Distal:BAAALgAECgcJBwAAAA==.',
Do='Donaghy:BAAALgAECgEJAQAAAA==.Dooms:BAAALgADCgcJBwAAAA==.',
Dp='Dpsmaster:BAABLgAECn8hAAIYAAcJPgiOEAB3AAAYAAcJPgiOEAB3AAAAAA==.',
Dr='Dranalis:BAAALgAECggJEAAAAA==.Drdrake:BAAALgADCgcJFAAAAA==.Dredlok:BAABLgAECn8WAAIOAAYJ3gTgCAByAAAOAAYJ3gTgCAByAAAAAA==.Drufiyo:BAAALgAECgUJBQABLgAECgkJMAAdALUUAA==.',
Du='Dumonster:BAABLgAECn8gAAIRAAYJWgeQEQCaAAARAAYJWgeQEQCaAAAAAA==.',
['Dø']='Døll:BAAALgADCgYJBgAAAA==.',
Ea='Eamishal:BAAALgADCgEJAQAAAA==.',
Ei='Eightace:BAAALgAECgQJBgAAAA==.Eirenne:BAAALgAECgYJBwAAAA==.',
Ek='Ekaru:BAAALgADCgEJAQAAAA==.',
El='Eledell:BAAALgAECgUJCAAAAA==.Elethryia:BAAALgAECgcJDQAAAA==.Elev:BAAALgAECgYJDwAAAA==.Elindril:BAAALgAECgYJEwAAAA==.',
En='Enoth:BAAALgAECggJEQAAAA==.',
Eo='Eowynn:BAACLgAFFH8GAAIFAAMJfBo7SgDHAAAFAAMJfBo7SgDHAAAuAAQKfygAAgUACQnuH9MIACQDAAUACQnuH9MIACQDAAAA.',
Er='Erewhon:BAAALgADCgkJCQAAAA==.',
Es='Estella:BAABLgAECn8hAAIJAAYJ7g3rxgD/AAAJAAYJ7g3rxgD/AAAAAA==.',
Ev='Eventhorizon:BAAALgAECgkJBgAAAA==.Evielli:BAAALgADCgUJBQAAAA==.',
Fa='Faeriefire:BAAALgADCggJDQAAAA==.Fanna:BAAALgADCgMJAwAAAA==.Fatbox:BAABLgAECn8lAAIRAAkJjyDgKgCrAQARAAkJjyDgKgCrAQAAAA==.Faythh:BAABLgAECn8xAAMNAAkJfiHEBwDyAgANAAkJfiHEBwDyAgAeAAEJVhsNbwBMAAAAAA==.',
Fe='Fearblade:BAABLgAECn8VAAIdAAUJnA6erQDLAAAdAAUJnA6erQDLAAAAAA==.Fedoran:BAABLgAECn8iAAQHAAkJRB+nCABTAgAHAAcJyyGnCABTAgAXAAcJbREERACAAQAYAAYJnBxYTgDwAAAAAA==.Felasap:BAAALgAECgcJCAAAAA==.Fenastic:BAABLgAECn8nAAMCAAkJIgcKegBFAQACAAkJqAYKegBFAQADAAMJEAYsHACRAAAAAA==.Fenrisúlfur:BAAALgAECgUJDQAAAA==.Feyrah:BAAALgAECggJCwABLgAFFAMJBgAFAHwaAA==.',
Fi='Filthy:BAAALgAECgkJCQAAAA==.Finwë:BAAALgAECgMJAwAAAA==.Fiobhe:BAABLgAECn85AAIbAAkJFBmSFwBNAgAbAAkJFBmSFwBNAgAAAA==.Fixeruper:BAABLgAECn8cAAINAAgJswEOTQCuAAANAAgJswEOTQCuAAAAAA==.',
Fl='Flaggedname:BAAALgADCgMJAwABLgAECgkJFQAUAGUUAA==.Flubberduck:BAAALgAECgMJBAAAAA==.Fluffybeer:BAABLgAECn8gAAISAAgJrh1wPAAPAgASAAgJrh1wPAAPAgAAAA==.',
Fo='Fonz:BAAALgAECgYJBgABLgAECgcJGwAbAHYQAA==.Footdig:BAABLgAECn89AAIXAAkJjSMoBAB8AwAXAAkJjSMoBAB8AwAAAA==.',
Fr='Frøstbìtê:BAAALgADCgUJBQAAAA==.',
Fu='Fuquan:BAAALgAECgYJCgAAAA==.',
Fw='Fwd:BAAALgADCgIJAgAAAA==.',
Ga='Gadzook:BAAALgADCggJFQAAAA==.Garthok:BAAALgADCggJCAAAAA==.Gatolun:BAAALgADCgUJBQAAAA==.',
Gi='Giline:BAAALgAECgEJAQAAAA==.Gimp:BAAALgADCgEJAQAAAA==.Ginja:BAAALgADCgIJAgAAAA==.',
Gl='Glenlizzo:BAAALgADCgYJDQABLgAECggJHgALAJ0aAA==.Glenroyce:BAABLgAECn8eAAILAAgJnRr+AgCmAQALAAgJnRr+AgCmAQAAAA==.Gless:BAABLgAECn80AAIQAAgJIhAKAwB3AQAQAAgJIhAKAwB3AQAAAA==.',
Go='Goodfine:BAAALgADCgcJDwAAAA==.Goss:BAAALgAECgMJAwAAAA==.Goteem:BAAALgADCggJDAAAAA==.',
Gr='Grandcross:BAAALgADCgMJAwAAAA==.Grapedrink:BAABLgAECn8WAAIbAAYJKhpeAwDEAQAbAAYJKhpeAwDEAQABLgAECgkJJQARAI8gAA==.Griimtotem:BAAALgAECgQJBAAAAA==.Groen:BAAALgAECgIJAgABLgAECgkJMQAQABwVAA==.',
Gu='Gueret:BAAALgAECgEJAQAAAA==.Gungnir:BAABLgAECn8dAAMfAAgJnRjtFwD0AQAfAAgJnRjtFwD0AQAgAAYJggfQewCrAAAAAA==.Gush:BAAALgADCgQJBAAAAA==.Guttertrash:BAAALgAECgIJAgAAAA==.',
Gw='Gwendelspear:BAAALgADCgQJBAABLgAECggJEAABAAAAAA==.',
Ha='Hae:BAAALgADCgEJAQAAAA==.Haenus:BAAALgAECgYJDAAAAA==.Haill:BAAALgAECggJEAAAAA==.Hamhock:BAABLgAECn9KAAIhAAgJhCFVAQCmAgAhAAgJhCFVAQCmAgABLgAECgkJJQARAI8gAA==.Hardtobepro:BAAALgAECgcJBwAAAA==.Harleydk:BAAALgADCgUJBQAAAA==.Hawks:BAAALgADCggJCQAAAA==.',
He='Heartsong:BAAALgAECgcJBgAAAA==.Hevn:BAAALgAECgQJBAABLgAECgkJIgAVAEoMAA==.',
Ho='Holycrusader:BAABLgAECn8YAAIEAAgJWBJIXQDLAQAEAAgJWBJIXQDLAQAAAA==.Hoop:BAAALgAECgMJBQAAAA==.Hornito:BAAALgAECgYJCAAAAA==.',
Ic='Icerug:BAAALgAECgYJBwABLgAFFAQJCgAXANQUAA==.',
Ih='Ihatepallys:BAAALgAECgUJDAAAAA==.',
Ii='Iikeomgikr:BAAALgADCgEJAQAAAA==.',
Il='Ildefonso:BAAALgAECgEJAQABLgAECgcJGwAbAHYQAA==.Ilduca:BAAALgADCgYJBwAAAA==.Ilidank:BAABLgAECn8nAAIdAAkJOB98AQCwAgAdAAkJOB98AQCwAgAAAA==.Ilya:BAAALgAECgUJCwABLgAECggJKQAEAHcbAA==.',
Im='Impotence:BAAALgADCgMJAwAAAA==.',
In='Indigo:BAABLgAECn+MAAMFAAkJYiI8AQARAwAFAAkJYiI8AQARAwAGAAcJfRtTAwDSAQAAAA==.Innax:BAAALgADCgEJAQAAAA==.Innron:BAABLgAECn8xAAMhAAkJSxHyGQCwAQAhAAkJSxHyGQCwAQAcAAIJWwMzMgA7AAAAAA==.',
Ir='Irisblue:BAAALgADCgkJDwAAAA==.',
Iy='Iyahli:BAAALgAECgUJDwAAAA==.',
Ja='Jaedia:BAAALgADCgYJCQAAAA==.Jaque:BAAALgADCgEJAQAAAA==.Jarclian:BAACLgAFFH8PAAIJAAQJ9Rf1ZQAXAQAJAAQJ9Rf1ZQAXAQAuAAQKf0AAAgkACQnRIrcRAPACAAkACQnRIrcRAPACAAAA.Jaymonk:BAAALgAECgkJDgAAAA==.Jazmon:BAAALgAECgIJAgAAAA==.',
Je='Jezzea:BAAALgADCgkJEgAAAA==.',
Ji='Jimlaheys:BAAALgAECgYJDgAAAA==.Jinjix:BAAALgAECgEJAwAAAA==.Jitt:BAABLgAECn8XAAIdAAYJYxv9TwCVAQAdAAYJYxv9TwCVAQAAAA==.',
Jo='Jolike:BAAALgADCgUJBwAAAA==.Joséphine:BAAALgADCgkJGwAAAA==.',
['Jâ']='Jâten:BAABLgAECn8WAAIfAAkJxBlCDgBjAgAfAAkJxBlCDgBjAgABLgAFFAcJEgAdAGMdAA==.Jâtens:BAACLgAFFH8SAAMdAAcJYx3TCgDnAQAdAAcJYx3TCgDnAQAcAAEJAgRCFQAlAAAuAAQKfyIAAh0ACAlxH2AdAGQCAB0ACAlxH2AdAGQCAAAA.',
Ka='Kaelía:BAAALgAECggJEwAAAA==.Kair:BAACLgAFFH8LAAIfAAMJLwfrLQCRAAAfAAMJLwfrLQCRAAAuAAQKfykAAh8ACQnUCsMwAEQBAB8ACQnUCsMwAEQBAAAA.Kairring:BAABLgAECn8jAAIVAAkJ4BSVMAAZAgAVAAkJ4BSVMAAZAgAAAA==.Kame:BAAALgAECgUJBQAAAA==.Kamehameha:BAABLgAECn8YAAIZAAkJlRX/CQDTAQAZAAkJlRX/CQDTAQAAAA==.Kami:BAABLgAECn80AAIfAAkJ1xOrHADJAQAfAAkJ1xOrHADJAQAAAA==.Kapslock:BAAALgAECgYJBwAAAA==.Karii:BAAALgADCgEJAQAAAA==.Karma:BAAALgADCgcJHAAAAA==.Katsicle:BAABLgAECn8wAAIJAAgJiwdzFwDxAAAJAAgJiwdzFwDxAAAAAA==.Kattastrophy:BAABLgAECn8dAAMCAAgJ0AflEQDDAAAOAAgJ+gU7GwDLAAACAAcJ7QflEQDDAAAAAA==.Katteya:BAAALgAECgcJEAAAAA==.Kattia:BAABLgAECn8rAAIVAAkJkA6RTwC0AQAVAAkJkA6RTwC0AQAAAA==.Kazmoru:BAAALgAECgEJAQAAAA==.',
Kh='Khalico:BAAALgADCgEJAQAAAA==.Khat:BAAALgAECgUJCgAAAA==.Khellendros:BAAALgADCgUJBQABLgAECgYJCgABAAAAAA==.Khir:BAAALgAECgQJBwAAAA==.',
Ki='Killinkair:BAAALgAECgYJBgAAAA==.Kinomihime:BAABLgAECn83AAIJAAkJ3w+iYQC8AQAJAAkJ3w+iYQC8AQAAAA==.Kirajoy:BAABLgAECn91AAIOAAkJgQxeAwAlAQAOAAkJgQxeAwAlAQAAAA==.Kirel:BAAALgADCgEJAQAAAA==.Kithri:BAAALgADCgEJAQAAAA==.Kitkatt:BAAALgAECgMJAwAAAA==.Kiymeria:BAAALgAECgYJBgAAAA==.',
Kn='Knyghtt:BAABLgAECn8jAAIRAAgJDw+nNQByAQARAAgJDw+nNQByAQAAAA==.',
Ko='Kogwyn:BAAALgAECggJEQAAAA==.Kogy:BAAALgADCgcJBgABLgAECggJEQABAAAAAA==.',
Kr='Krakor:BAAALgADCgYJBgAAAA==.Kraviz:BAAALgAECgYJDgAAAA==.Krombopolous:BAAALgADCgkJKgABLgAECgkJPwAVAJoVAA==.Krystle:BAABLgAECn8wAAIVAAkJHhc7LwAgAgAVAAkJHhc7LwAgAgAAAA==.',
Ky='Kydormu:BAAALgADCgEJAQAAAA==.',
['Kä']='Käyfex:BAAALgAECgQJBAAAAA==.',
La='Lazarus:BAAALgAECgkJCQAAAA==.',
Le='Leannan:BAAALgAECgUJCAAAAA==.Leftyloose:BAAALgADCgkJBAAAAA==.Lexdysic:BAAALgAECgEJAQAAAA==.',
Li='Lilfonz:BAABLgAECn8bAAMbAAcJdhA7PgBMAQAbAAcJdhA7PgBMAQAEAAYJ/RgVnQBEAQAAAA==.Livik:BAABLgAECn8cAAIWAAkJ2BxqAwBoAgAWAAkJ2BxqAwBoAgAAAA==.',
Lo='Lockofdeath:BAAALgADCgYJBwAAAA==.Lockywolf:BAAALgAECgUJBgAAAA==.Logarth:BAAALgAECgYJDAABLgAECgcJGQAFALMVAA==.Longbrew:BAAALgADCgEJAQAAAA==.Loppsang:BAABLgAECn8XAAMXAAgJwBEMTQBbAQAXAAcJkREMTQBbAQAYAAEJBQ1tHQAqAAAAAA==.Lopseng:BAAALgAECgMJAwAAAA==.Lorcan:BAABLgAECn82AAIiAAkJdhsuCwA1AgAiAAkJdhsuCwA1AgAAAA==.',
Lr='Lroye:BAACLgAFFH8WAAIjAAUJMRliCwA5AQAjAAUJMRliCwA5AQAuAAQKfxkAAiMABwnqHrcYANQBACMABwnqHrcYANQBAAAA.',
Ls='Lsdarko:BAAALgAECgEJAwAAAA==.',
Lu='Luckyleet:BAAALgADCgQJCwAAAA==.Lucyfer:BAABLgAECn8bAAIGAAkJNwzzBQBVAQAGAAkJNwzzBQBVAQABLgAECgkJIgAVAEoMAA==.Lucyferr:BAABLgAECn8eAAIJAAgJVggNIQCvAAAJAAgJVggNIQCvAAABLgAECgkJIgAVAEoMAA==.Ludacritts:BAAALgAECgQJBAAAAA==.Ludicrispeed:BAAALgADCgkJFQAAAA==.Luliak:BAACLgAFFH8WAAITAAcJQSOLAgCWAQATAAcJQSOLAgCWAQAuAAQKfyAAAhMACQnRInYEAOYCABMACQnRInYEAOYCAAAA.Lunabren:BAABLgAECn8eAAMXAAgJ2A4uCAAPAQAXAAcJYA0uCAAPAQAYAAcJwwcJSwDgAAAAAA==.Lunamina:BAABLgAECn8fAAIVAAYJcBkVEwAjAQAVAAYJcBkVEwAjAQAAAA==.',
Ly='Lynvala:BAAALgADCgQJBQAAAA==.Lysdexíc:BAABLgAECn8aAAIdAAkJzhP4QQDCAQAdAAkJzhP4QQDCAQAAAA==.',
['Lì']='Lìllith:BAABLgAECn8sAAMNAAkJLB3wDQCHAgANAAkJLB3wDQCHAgAkAAQJIwrgTgCXAAABLgAFFAIJDgAEAP0dAA==.',
Ma='Mactheknife:BAAALgADCgIJAgAAAA==.Majakdastudr:BAAALgAECgIJAgAAAA==.Majika:BAAALgADCgYJBQAAAA==.Mariophra:BAABLgAECn86AAIFAAkJ1xq6FQCdAgAFAAkJ1xq6FQCdAgAAAA==.Marvelious:BAAALgAFFAEJAQAAAA==.Mattlen:BAAALgADCgYJCAAAAA==.Maximumswag:BAAALgADCgkJLQABLgAECgkJPwAVAJoVAA==.Maxmugruith:BAAALgADCgQJBwAAAA==.Maxtheb:BAAALgADCgYJDAAAAA==.Mayfair:BAAALgAECgYJBwAAAA==.',
Mc='Mcnastyqt:BAAALgAECgQJBAAAAA==.',
Me='Meatshiéld:BAAALgAECgYJCgAAAA==.',
Mi='Midopamos:BAAALgADCgEJAQAAAA==.Mikki:BAAALgAECgcJDwAAAA==.Milber:BAAALgAECgMJBQAAAA==.Missconduct:BAAALgADCgYJBgAAAA==.Misstorgo:BAABLgAECn8kAAIQAAkJoh6VAQAYAgAQAAkJoh6VAQAYAgAAAA==.',
Mo='Monfro:BAABLgAECn8UAAIVAAkJ2h4dDwBNAQAVAAkJ2h4dDwBNAQAAAA==.Moodswings:BAAALgAECgYJBgAAAA==.Moogatoo:BAAALgAECgYJCAABLgAECgcJFwASAMsZAA==.Moonbane:BAABLgAECn8sAAIOAAgJUCDOAwBQAgAOAAgJUCDOAwBQAgAAAA==.Moonfanda:BAAALgADCgIJAgAAAA==.Moonmist:BAAALgADCgEJAQABLgAECggJEAABAAAAAA==.Moor:BAAALgAECgYJDAAAAA==.Mordecai:BAAALgAECgUJBQAAAA==.',
Mu='Mumferd:BAAALgADCgQJBAAAAA==.',
My='Myaquean:BAAALgADCgkJFAAAAA==.Mystogan:BAAALgAECgcJEgAAAA==.Myth:BAAALgAECggJDAAAAA==.Mythelea:BAAALgAECgQJBAAAAA==.',
Na='Nakeefa:BAABLgAECn8nAAMCAAkJdBRxMwALAgACAAkJdBRxMwALAgAOAAEJAAA9cgAzAAAAAA==.Natah:BAAALgADCgcJBwAAAA==.Natsuu:BAABLgAECn82AAMVAAkJPBtnBwDgAQAVAAgJsxxnBwDgAQATAAUJuQ6+NAAMAQAAAA==.Naturewolf:BAABLgAECn8eAAIHAAgJXRbsFAB2AQAHAAgJXRbsFAB2AQAAAA==.',
Ne='Nefertiti:BAAALgAECgcJCQAAAA==.Nekona:BAABLgAECn8VAAQCAAgJTwuEiQBGAQACAAgJTwuEiQBGAQAOAAIJCgmuWwBcAAADAAEJlwWVNAAzAAAAAA==.Neron:BAACLgAFFH8OAAIEAAIJ/R2cOwCXAAAEAAIJ/R2cOwCXAAAuAAQKf0QAAgQACQlYIBccAJwCAAQACQlYIBccAJwCAAAA.Nethertusk:BAABLgAECn8uAAMCAAkJTBmlMwAKAgACAAkJTBmlMwAKAgAOAAIJYQP2WQBhAAAAAA==.',
Nh='Nhancecntrl:BAACLgAFFH8IAAIPAAMJ8QvhCAC1AAAPAAMJ8QvhCAC1AAAuAAQKfykAAg8ACQnRGkUFAJECAA8ACQnRGkUFAJECAAEuAAUUBAkKACUAYRAA.',
Ni='Niany:BAAALgAECgYJDwAAAA==.Nightbréaker:BAAALgADCgcJFQAAAA==.Nilospite:BAACLgAFFH8FAAIQAAUJTw9hCgDwAAAQAAUJTw9hCgDwAAAuAAQKfzIAAhAACAlwHpMJAFoCABAACAlwHpMJAFoCAAEuAAUUBwkeAAwAghUA.Nimposter:BAABLgAECn8rAAISAAkJNRfIOAAcAgASAAkJNRfIOAAcAgAAAA==.',
Nj='Njoror:BAAALgADCgQJBAAAAA==.',
No='Noodle:BAAALgADCgEJAQAAAA==.Norky:BAAALgAECgUJBQABLgAFFAQJEwAFAHEUAA==.Nottapally:BAAALgAECgcJEgABLgAECgkJFQAUAGUUAA==.',
Nu='Nuckìnfuts:BAAALgADCgUJBQAAAA==.Nullea:BAAALgAECgYJCAAAAA==.',
Ny='Nyxthos:BAAALgADCggJCAAAAA==.',
Ob='Obizi:BAAALgAECgEJAQAAAA==.',
Oc='Ocatarineta:BAAALgADCgIJAgAAAA==.',
Od='Odine:BAAALgAECgEJAgAAAA==.Odito:BAABLgAECn8VAAIYAAYJpRdwMABbAQAYAAYJpRdwMABbAQAAAA==.',
Om='Omegalich:BAAALgAECgEJAQAAAA==.',
Oo='Oopslol:BAAALgAECgYJDAAAAA==.',
Os='Osdavalmarro:BAAALgADCgYJGQAAAA==.',
Ot='Othaerion:BAABLgAECn8YAAIbAAkJbw+sKgC6AQAbAAkJbw+sKgC6AQAAAA==.',
Ou='Outerlimits:BAABLgAECn8uAAImAAgJMRjRCwC7AQAmAAgJMRjRCwC7AQAAAA==.',
Pa='Paindore:BAAALgAECgQJBwAAAA==.Pamboo:BAABLgAECn8xAAIbAAkJzg/KJQDaAQAbAAkJzg/KJQDaAQAAAA==.Papalegba:BAAALgAECgEJAQAAAA==.Parolee:BAAALgAECgkJAQAAAA==.',
Pe='Pearle:BAABLgAECn8vAAIMAAkJQx4aDABLAgAMAAkJQx4aDABLAgAAAA==.',
Ph='Phyg:BAAALgAECgQJBQABLgAECgUJBwABAAAAAA==.',
Po='Pokimane:BAAALgADCggJDwAAAA==.Polyasap:BAAALgADCgQJBAAAAA==.',
Pr='Priestiô:BAAALgAECgEJAgAAAA==.Pringo:BAAALgAFFAIJAgAAAA==.Proximal:BAAALgAECgcJBwAAAA==.',
Pu='Pukka:BAAALgADCgcJEQABLgAECgkJJAANADUaAA==.Punk:BAAALgAFFAEJAQAAAA==.',
Qa='Qahnaarin:BAAALgAFFAEJAQAAAA==.',
Ra='Rajax:BAABLgAECn8WAAIRAAkJKhFEIADuAQARAAkJKhFEIADuAQAAAA==.Ralphthedh:BAAALgAECgkJDwAAAA==.Ramindizzle:BAABLgAECn86AAIZAAkJcBYUCQDnAQAZAAkJcBYUCQDnAQAAAA==.Rangewolf:BAAALgADCgcJDgAAAA==.Rapidito:BAAALgAECgEJAQAAAA==.',
Re='Refreshing:BAAALgAECgUJCQAAAA==.Rejuvasap:BAABLgAECn8aAAQYAAgJMBpWKQC1AQAYAAgJMBpWKQC1AQAXAAUJ6R35OwCkAQAHAAMJqheuNQCHAAAAAA==.Rekki:BAAALgAECggJCQABLgAECgkJIgAVAEoMAA==.Reliri:BAAALgADCgMJAwAAAA==.Remlin:BAAALgADCgcJCAAAAA==.Retastic:BAAALgAECgcJBwAAAA==.Retsall:BAAALgADCgUJBQAAAA==.Reâper:BAAALgAECgYJCgAAAA==.',
Ri='Rikal:BAAALgADCgYJEAAAAA==.',
Ro='Rook:BAABLgAECn82AAIZAAkJ8A1kDgB4AQAZAAkJ8A1kDgB4AQAAAA==.Roye:BAACLgAFFH8cAAIEAAgJIxa6FQAvAQAEAAgJIxa6FQAvAQAuAAQKfx4AAgQACQl1HbYaAMkCAAQACQl1HbYaAMkCAAAA.',
Ru='Ruffiyo:BAABLgAECn8wAAMdAAkJtRSyPwDKAQAdAAkJrxOyPwDKAQAhAAgJ3Q+LLQBfAQAAAA==.Rugrahfreaky:BAACLgAFFH8KAAIXAAQJ1BRELQAAAQAXAAQJ1BRELQAAAQAuAAQKfzkAAhcACQl6IVMFAGMDABcACQl6IVMFAGMDAAAA.Rugrahh:BAABLgAECn8pAAMZAAkJux5MDwDGAgAZAAkJux5MDwDGAgATAAMJaQ+QQwC0AAABLgAFFAQJCgAXANQUAA==.Rugrahx:BAABLgAFFH8FAAIcAAMJ4Rl8BwDhAAAcAAMJ4Rl8BwDhAAABLgAFFAQJCgAXANQUAA==.Rugzco:BAABLgAFFH8LAAIgAAYJzQ43EQBMAQAgAAYJzQ43EQBMAQAAAA==.Ruthen:BAAALgAECgYJDgAAAA==.Ruìn:BAAALgAECgcJCQAAAA==.',
Sa='Sabermore:BAABLgAECn8dAAIEAAgJdxgNSADuAQAEAAgJdxgNSADuAQAAAA==.Sabina:BAABLgAECn83AAIGAAkJgAuhOQBQAQAGAAkJgAuhOQBQAQAAAA==.Sadako:BAAALgAECgYJCAABLgAECgkJIgAVAEoMAA==.Sadness:BAABLgAECn8bAAMfAAgJ0RqdAQArAgAfAAgJ0RqdAQArAgAnAAYJmAojSgDUAAAAAA==.Sadorick:BAAALgADCgkJLwAAAA==.Safira:BAAALgAECgQJBgABLgAFFAIJDgAEAP0dAA==.Sageguy:BAABLgAECn8dAAIJAAYJ9gXVJQCTAAAJAAYJ9gXVJQCTAAAAAA==.Sakurarose:BAAALgAECgEJAQAAAA==.Samerle:BAAALgADCgEJAQAAAA==.Sango:BAABLgAECn9DAAMhAAkJcBlXDgBAAgAhAAkJcBlXDgBAAgAdAAQJ2gKPwQB8AAAAAA==.Sarenity:BAAALgADCgkJFQAAAA==.Saucewalker:BAABLgAFFH8VAAISAAUJkBsvRwBlAQASAAUJkBsvRwBlAQAAAA==.Savagelykill:BAABLgAECn8eAAIMAAYJvwrINgC7AAAMAAYJvwrINgC7AAAAAA==.',
Sc='Scotch:BAABLgAECn9GAAMEAAkJOB17LgBHAgAEAAkJwBt7LgBHAgAUAAYJBSA7AwBuAQAAAA==.Scotchnwater:BAABLgAECn8lAAMoAAgJSxEUAgB1AQAoAAgJSxEUAgB1AQApAAMJIwcQGwB0AAAAAA==.Scrubyheals:BAAALgADCgQJBwABLgAECgkJFQAUAGUUAA==.',
Se='Sendio:BAAALgAECgQJBAAAAA==.Senji:BAAALgADCgQJBAAAAA==.',
Sg='Sgtpayne:BAAALgADCgIJAgAAAA==.',
Sh='Shadowcrwlr:BAAALgAECgQJCgAAAA==.Shadowlock:BAAALgAECggJEwAAAA==.Shadowmane:BAAALgADCgQJBAAAAA==.Shaeixia:BAAALgADCggJCgAAAA==.Shamangroo:BAAALgAECgEJAQABLgAECgYJGAAQAEYXAA==.Shamanio:BAAALgAECgkJCwAAAA==.Shamichangas:BAAALgAECgEJAQAAAA==.Shammying:BAAALgAECgUJCwAAAA==.Shamsham:BAAALgADCgIJAgAAAA==.Sharaaz:BAAALgAECgMJBgAAAA==.Shivalry:BAAALgADCgkJCwAAAA==.Shmiggy:BAAALgAECgQJCgAAAA==.',
Si='Silverytwo:BAAALgAECgYJCQAAAA==.Silverywine:BAAALgADCgkJCQAAAA==.Silverywolfe:BAAALgAECgYJDgAAAA==.Simony:BAABLgAECn8qAAIEAAkJoQjHEQAhAQAEAAkJoQjHEQAhAQABLgAECgkJIgAVAEoMAA==.Sinton:BAAALgAECgEJAQAAAA==.',
Sk='Skorpyoh:BAAALgADCgYJBgAAAA==.Skovak:BAABLgAECn8VAAIUAAkJkA70FQB2AQAUAAkJkA70FQB2AQAAAA==.Skoveth:BAAALgAECgQJBAAAAA==.Skybright:BAAALgAECggJCwAAAA==.',
So='Soggy:BAAALgAECgcJBwAAAA==.Sorayae:BAABLgAECn8kAAINAAkJNRr1EwA/AgANAAkJNRr1EwA/AgAAAA==.',
Sp='Specialk:BAAALgAECgYJEgAAAA==.Spinnykat:BAAALgAECgMJBgAAAA==.Splooshh:BAAALgAECgkJDAABLgAECgkJMAAdALUUAA==.',
St='Starmist:BAAALgADCgMJAwAAAA==.Stinkfoot:BAAALgAECgUJCAAAAA==.Stoo:BAAALgADCgkJHAAAAA==.Stormkissed:BAABLgAECn8fAAMFAAkJIQwNUAByAQAFAAkJIQwNUAByAQAGAAEJQALlwQAcAAAAAA==.Stormweaver:BAAALgAECgUJBQAAAA==.Strongheart:BAAALgAECgMJAgABLgAECgcJGQAFALMVAA==.',
Su='Sunil:BAABLgAECn9TAAINAAkJxx7kBQAZAwANAAkJxx7kBQAZAwAAAA==.Suviqhabo:BAAALgAECggJDwAAAA==.',
Sv='Svala:BAAALgADCgYJBgAAAA==.',
Sy='Syclic:BAAALgAECgUJBQABLgAECgkJMwAQABAmAA==.Syclone:BAABLgAECn8zAAIQAAkJECbHAABoAwAQAAkJECbHAABoAwAAAA==.Syladen:BAAALgAECgYJEgAAAA==.Syleste:BAAALgAECgQJBAABLgAECgkJMwAQABAmAA==.Syvi:BAAALgAECgYJCQABLgAECggJEQABAAAAAA==.',
Ta='Taetheron:BAAALgAECgUJBQAAAA==.Tahwe:BAAALgADCgUJBQAAAA==.Tattianna:BAAALgAECgYJEwAAAA==.Tavendar:BAAALgAECgkJEgABLgAFFAQJEwAFAHEUAA==.Tavil:BAAALgADCgMJAwAAAA==.Taírn:BAAALgAECgYJEAAAAA==.',
Te='Techie:BAABLgAECn8gAAMgAAkJTRKfJAD9AQAgAAkJTRKfJAD9AQAnAAUJpASfYgC4AAAAAA==.Teeser:BAABLgAECn8WAAIEAAYJAwNFPABUAAAEAAYJAwNFPABUAAAAAA==.Tehkatza:BAAALgAECgYJBgAAAA==.Terradactyl:BAAALgADCgMJAwAAAA==.',
Th='Thesis:BAAALgADCgkJCQAAAA==.Thunderslate:BAABLgAECn8VAAIUAAkJZRQcEwCYAQAUAAkJZRQcEwCYAQAAAA==.Thôrin:BAAALgAECgUJBQAAAA==.',
Ti='Tigerlillee:BAAALgADCgcJDQAAAA==.Tigreth:BAABLgAECn82AAMEAAkJ1hTbUQDTAQAEAAkJ1hTbUQDTAQAUAAIJlhSvNgBoAAAAAA==.Timotheus:BAAALgAECgUJDAAAAA==.Tinkerballa:BAAALgAECgYJCQAAAA==.',
To='Tonï:BAAALgADCggJCAAAAA==.Totemzasap:BAAALgAECgEJAgAAAA==.',
Tr='Tragik:BAABLgAECn8mAAIPAAkJQA5uEACsAQAPAAkJQA5uEACsAQAAAA==.',
Tt='Ttrouble:BAAALgADCgUJBQAAAA==.',
Tu='Tuugadark:BAABLgAECn81AAICAAkJRx22JABMAgACAAkJRx22JABMAgAAAA==.Tuugashox:BAAALgAECgUJBQAAAA==.',
Ul='Ulyaoth:BAABLgAECn86AAICAAgJwQspcQBYAQACAAgJwQspcQBYAQAAAA==.',
Un='Unc:BAAALgAECgEJAQAAAA==.Unnerfable:BAAALgAECgYJCAAAAA==.',
Uw='Uwa:BAAALgADCgMJAwAAAA==.',
Uy='Uy:BAAALgAECgYJDwAAAA==.',
Va='Valakha:BAAALgAECgQJDwAAAA==.Valkyrie:BAAALgAECgQJBgAAAA==.',
Ve='Vedros:BAAALgADCgkJDgAAAA==.Vermouth:BAABLgAECn8ZAAINAAgJIxBBBQBrAQANAAgJIxBBBQBrAQAAAA==.Vespertilia:BAAALgAECgIJAgAAAA==.',
Vi='Viktoros:BAAALgAECgIJAgAAAA==.Violetra:BAAALgADCgMJAwAAAA==.',
Vo='Vorcan:BAAALgADCgYJBgAAAA==.Vorukh:BAABLgAECn8fAAQHAAkJohHCDgDIAQAHAAkJohHCDgDIAQAXAAMJ9gxKmACBAAALAAEJyw/1gAAhAAAAAA==.',
Vr='Vrave:BAAALgADCgQJBQAAAA==.',
Vy='Vyhlet:BAAALgAECggJEgABLgAECgkJjAAFAGIiAA==.',
Wa='Warlockgroo:BAAALgADCgQJBAABLgAECgYJGAAQAEYXAA==.Warriorgroo:BAABLgAECn8YAAIQAAYJRhdZJgD/AAAQAAYJRhdZJgD/AAAAAA==.',
We='Wendish:BAAALgAECgEJCgAAAA==.Wertyda:BAABLgAECn8aAAIbAAkJzhT4JgDSAQAbAAkJzhT4JgDSAQAAAA==.Wetnwild:BAAALgAECgUJBQAAAA==.',
Wh='Whácker:BAABLgAECn8UAAMiAAgJOwpYEgB8AQAiAAgJOwpYEgB8AQAQAAMJrAguOQCBAAABLgAECgYJEAABAAAAAA==.',
Wi='Wickdlovly:BAAALgADCgEJAQABLgAECggJEAABAAAAAA==.Wickedslicks:BAABLgAECn8+AAIYAAkJqiA9CADQAgAYAAkJqiA9CADQAgAAAA==.Wildthangg:BAAALgAECgIJAgAAAA==.',
Wo='Wooddchipper:BAAALgADCgYJBgAAAA==.',
Wr='Wreckshop:BAABLgAECn8ZAAISAAkJ8xrzSQDkAQASAAkJ8xrzSQDkAQAAAA==.',
Wt='Wtfoxtrot:BAAALgADCgkJDAAAAA==.',
Xe='Xenøcide:BAAALgAECgcJEwAAAA==.',
Xi='Xiatus:BAAALgAECgUJBQABLgAECgkJKgASAOYhAA==.',
Xx='Xxlockz:BAABLgAECn8lAAMCAAkJWREwZwBvAQACAAgJ8A4wZwBvAQAOAAMJGRFLIQCkAAAAAA==.Xxpallyz:BAAALgAECggJCwABLgAECgkJJQACAFkRAA==.',
Yi='Yinger:BAAALgADCgcJEAAAAA==.Yinglang:BAAALgADCgEJAQAAAA==.Yingling:BAABLgAECn8rAAISAAkJ6RmPQQD+AQASAAkJ6RmPQQD+AQAAAA==.',
Yo='Yohh:BAABLgAECn8sAAIFAAkJTBowAgCcAgAFAAkJTBowAgCcAgAAAA==.Yorshka:BAAALgAECgMJAwABLgAECgkJKgASAOYhAA==.',
Yu='Yukara:BAAALgAECgEJAQAAAA==.Yulay:BAAALgADCgkJBwAAAA==.Yuriko:BAABLgAECn83AAIgAAkJ1hONIwAEAgAgAAkJ1hONIwAEAgAAAA==.',
Za='Zadory:BAAALgAECgEJAgAAAA==.Zaidan:BAABLgAECn8UAAIhAAYJDAfzSwCHAAAhAAYJDAfzSwCHAAAAAA==.Zanpaktu:BAAALgAECgYJEwAAAA==.Zaraha:BAAALgADCgEJAQAAAA==.Zata:BAAALgAECgUJBwAAAA==.',
Ze='Zendous:BAAALgAECgcJBwAAAA==.Zeref:BAAALgAECgYJEgAAAA==.Zeur:BAAALgAECgEJAQAAAA==.Zevgrip:BAAALgAECgQJBQAAAA==.',
Zh='Zhia:BAAALgAECgQJBQAAAA==.',
Zi='Zippitydooda:BAAALgAECgEJAQABLgAECggJEAABAAAAAA==.',
Zo='Zodiacc:BAABLgAECn84AAILAAkJQxzvBgCJAgALAAkJQxzvBgCJAgAAAA==.Zornen:BAAALgAECggJDQAAAA==.Zornhealer:BAAALgAECgUJBgABLgAECgYJEwABAAAAAA==.',
Zy='Zyxxyz:BAAALgADCgkJCQABLgAECgkJMAAdALUUAA==.',
['Zö']='Zölä:BAAALgAECgMJAwAAAA==.',
['Ât']='Âtomic:BAAALgADCgYJAgABLgAECgYJEAABAAAAAA==.',
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
