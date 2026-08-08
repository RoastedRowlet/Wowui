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

local lookup = {'Unknown-Unknown','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Paladin-Retribution','Shaman-Restoration','Shaman-Elemental','Druid-Feral','Mage-Arcane','Mage-Fire','Mage-Frost','Druid-Guardian','DeathKnight-Blood','Priest-Holy','Shaman-Enhancement','Warrior-Protection','Warrior-Fury','DeathKnight-Unholy','Hunter-Survival','Paladin-Protection','Hunter-BeastMastery','Rogue-Outlaw','Druid-Restoration','Druid-Balance','Hunter-Marksmanship','Rogue-Assassination','Paladin-Holy','DemonHunter-Vengeance','DemonHunter-Devourer','Priest-Discipline','DemonHunter-Havoc','Monk-Windwalker','Monk-Mistweaver','Warrior-Arms','Rogue-Subtlety','Priest-Shadow','Evoker-Augmentation','DeathKnight-Frost','Monk-Brewmaster','Evoker-Preservation','Evoker-Devastation',}
local provider = {region='US',realm='EchoIsles',name='US',type='weekly',zone=46,date='2026-08-04',data={Aa='Aaelless:BAAALgAECgMJBAAAAA==.Aardz:BAAALgAECgYJCQAAAA==.',
Ab='Abeblinkin:BAAALgADCgkJDgAAAA==.Abrakadavar:BAAALgAECgQJBQAAAA==.Abraxís:BAAALgAECgMJAwABLgAECgMJAwABAAAAAA==.Abräxis:BAAALgADCgkJCQABLgAECgMJAwABAAAAAA==.',
Ac='Acindis:BAAALgAFFAIJAwAAAA==.Ackspez:BAAALgADCgYJBgAAAA==.',
Ae='Aeless:BAABLgAECn8sAAQCAAkJRCKECwDyAgACAAkJRCKECwDyAgADAAIJoxrbCACgAAAEAAEJAAA3FgAAAAAAAA==.Aelless:BAAALgAECgYJCAAAAA==.Aenest:BAAALgADCggJCAAAAA==.',
Ah='Ahzure:BAAALgAECgYJBgAAAA==.',
Ai='Aiko:BAAALgADCgEJAQAAAA==.Aithinne:BAABLgAECn8lAAIFAAcJVRKYEQBKAQAFAAcJVRKYEQBKAQAAAA==.',
Ak='Akanah:BAAALgADCgcJBwAAAA==.',
Al='Alch:BAAALgAECgUJAwAAAA==.Alfira:BAAALgAECgYJEwAAAA==.Alghul:BAAALgAECgMJBAABLgAECgYJEwABAAAAAA==.',
Am='Amoredis:BAAALgADCgYJDQAAAA==.Amorlorin:BAAALgADCggJEwAAAA==.',
An='Anklbiterkat:BAAALgADCgQJBAAAAA==.Anume:BAAALgADCgkJFQAAAA==.',
Ar='Aragan:BAABLgAECn8kAAMGAAgJfxZZBQARAgAGAAgJfxZZBQARAgAHAAYJaQ/fEgCkAAAAAA==.Aravis:BAABLgAECn8sAAIIAAgJ6w+oGQBBAQAIAAgJ6w+oGQBBAQAAAA==.Arboreh:BAAALgAECgEJAQAAAA==.Arese:BAABLgAECn8hAAQJAAYJTiZ/AwA0AgAJAAUJTiZ/AwA0AgAKAAEJAABTDABpAAALAAMJlyTrOwBcAAAAAA==.Argopol:BAABLgAECn8iAAIMAAgJhyFUBgCbAgAMAAgJhyFUBgCbAgABLgAECgkJLwANAEMeAA==.Aron:BAAALgADCgMJAgAAAA==.',
As='Ashandra:BAAALgADCgkJDwAAAA==.Ashlyssra:BAABLgAECn8fAAIOAAkJYh0xCQDWAgAOAAkJYh0xCQDWAgAAAA==.Asphonix:BAAALgADCgEJAQAAAA==.',
Au='Auglade:BAAALgADCgYJBgAAAA==.',
Aw='Awsomesause:BAAALgAECgQJBgAAAA==.',
Az='Azuri:BAAALgAFFAMJAwAAAA==.Azzif:BAABLgAECn8kAAIDAAcJdwXtJwB4AAADAAcJdwXtJwB4AAAAAA==.Azzraell:BAAALgADCgEJAQAAAA==.',
Ba='Babaorumm:BAAALgAECgQJBAAAAA==.Babasha:BAACLgAFFH8JAAIPAAQJ6Qv7CwACAQAPAAQJ6Qv7CwACAQAuAAQKfxsAAw8ABgmSH0sQAK0BAA8ABgmSH0sQAK0BAAYABgnADcJPAEUBAAAA.Babybluz:BAABLgAECn8wAAILAAgJChDuEQBFAQALAAgJChDuEQBFAQAAAA==.Baconloaf:BAAALgAECgUJCQAAAA==.Baifeng:BAAALgADCgkJFgAAAA==.Baldilocks:BAAALgADCgQJDAAAAA==.Barlas:BAAALgAECgEJAQAAAA==.Bat:BAAALgADCgEJAQAAAA==.Baunshee:BAAALgAFFAIJBAAAAA==.',
Be='Beauriley:BAABLgAECn8xAAMQAAkJHBWsEwC0AQAQAAkJHBWsEwC0AQARAAEJnA7vnwA1AAAAAA==.Behomethan:BAABLgAECn8mAAMGAAkJZBtJKgDlAQAGAAgJOBpJKgDlAQAHAAgJABTTMgBxAQAAAA==.Berians:BAAALgAECgEJAgAAAA==.Beyonsláy:BAAALgAECgYJEQAAAA==.',
Bh='Bhipbookie:BAAALgAECgEJBAAAAA==.',
Bi='Billbetaray:BAAALgADCgMJAwAAAA==.',
Bl='Bluerift:BAAALgADCgEJAQAAAA==.Blux:BAAALgAECgEJAQAAAA==.',
Bo='Bobbyb:BAABLgAECn8XAAISAAcJyxkUVwDAAQASAAcJyxkUVwDAAQAAAA==.Bolton:BAAALgADCgMJAwAAAA==.Bombchele:BAAALgAECgYJCgABLgAECgkJGQASAPMaAA==.Boneulngtime:BAAALgADCgUJCgAAAA==.Boon:BAAALgAECgIJAgAAAA==.Bowlofwrong:BAAALgAECgYJBwAAAA==.',
Br='Bratticusrex:BAABLgAECn8nAAIRAAgJDwt7QQA/AQARAAgJDwt7QQA/AQAAAA==.Brazier:BAAALgAECgQJBAAAAA==.Bresowar:BAAALgAECgkJEQAAAA==.Brieseis:BAAALgADCgUJBQABLgAECggJCAABAAAAAA==.Bruhmoment:BAAALgAECgQJBAAAAA==.Brynthe:BAAALgADCgcJBwAAAA==.',
Bu='Bunnyhopp:BAAALgAECggJDgABLgAECgkJaQAGABsmAA==.Bunnylicious:BAABLgAECn9pAAIGAAkJGyatAADZAwAGAAkJGyatAADZAwAAAA==.Bunnymedic:BAABLgAECn8WAAIOAAYJIh1LHgDSAQAOAAYJIh1LHgDSAQABLgAECgkJaQAGABsmAA==.',
Ca='Caebrylla:BAABLgAECn88AAITAAkJgg8yFQD6AQATAAkJgg8yFQD6AQAAAA==.Calistie:BAAALgAECgIJAgAAAA==.Calver:BAAALgADCgcJCwAAAA==.Camigatu:BAAALgADCgQJBAAAAA==.Camil:BAABLgAECn8cAAIUAAkJiwtbHQAqAQAUAAkJiwtbHQAqAQABLgAFFAQJGgAVADAKAA==.Cang:BAAALgAECgIJAgAAAA==.Capulin:BAABLgAECn8lAAIRAAkJsBYQHgD+AQARAAkJsBYQHgD+AQAAAA==.Catalina:BAAALgAECgQJBAABLgAECgkJLwAGALMiAA==.Catdurid:BAAALgADCgYJBgAAAA==.Cayleta:BAAALgADCgYJBgAAAA==.',
Ce='Cecilbrown:BAAALgADCgcJBgAAAA==.Cecimorte:BAABLgAECn86AAINAAkJ4BmbDQAwAgANAAkJ4BmbDQAwAgAAAA==.Cephalopod:BAABLgAECn8UAAIWAAgJ1RXEAwD5AQAWAAgJ1RXEAwD5AQAAAA==.',
Ch='Chargeasap:BAAALgAECgMJAwAAAA==.Charttopper:BAAALgAECgYJCQABLgAECgkJFQAUAGUUAA==.Chibby:BAAALgADCgMJAwAAAA==.Chimichanga:BAAALgAECgcJDQABLgAECgkJFQAUAGUUAA==.Chinacloset:BAAALgAECgEJAQAAAA==.Chonker:BAABLgAECn84AAMXAAkJdSB/BwBAAwAXAAkJdSB/BwBAAwAYAAcJVwzlOwAiAQAAAA==.Chorelock:BAAALgADCgEJAQABLgAECgkJFQAUAGUUAA==.Chronormu:BAAALgAECgMJAwAAAA==.Chuckforrest:BAAALgAECgQJBAAAAA==.Chultis:BAABLgAECn8bAAQIAAgJuhQrEwCLAQAIAAgJuhQrEwCLAQAYAAEJ2wH5jgAeAAAXAAEJAgLF6QAbAAAAAA==.',
Ci='Cihato:BAABLgAECn83AAIMAAkJIxtQCQBVAgAMAAkJIxtQCQBVAgAAAA==.',
Cl='Claxious:BAABLgAECn8iAAIZAAkJlRmeBgAoAgAZAAkJlRmeBgAoAgAAAA==.Claye:BAACLgAFFH8TAAIGAAQJcRTyOAD/AAAGAAQJcRTyOAD/AAAuAAQKfysAAgYACQnPHJURAMECAAYACQnPHJURAMECAAAA.Clubbinseals:BAAALgAECgMJBAAAAA==.',
Co='Coldshoulder:BAABLgAECn86AAMLAAkJfx8wGwC4AgALAAkJfx8wGwC4AgAKAAQJaxOMCwC3AAAAAA==.Corelas:BAABLgAECn89AAILAAkJfhHTCgCpAQALAAkJfhHTCgCpAQAAAA==.Corfellyn:BAAALgAECggJBAAAAA==.Couchdad:BAAALgAECgYJEwAAAA==.',
Cr='Crazymadman:BAABLgAECn8qAAIaAAYJWQphAwDVAAAaAAYJWQphAwDVAAAAAA==.Creatineman:BAAALgAECgEJAQAAAA==.Crescentbane:BAAALgAECgEJAQAAAA==.Crushingblow:BAAALgAECgkJAwAAAA==.',
Cy='Cyon:BAAALgADCgEJAQAAAA==.',
Da='Daalaria:BAAALgADCgEJAQAAAA==.Dafang:BAAALgAECgEJAgAAAA==.Darkle:BAAALgAECgEJAQAAAA==.Darkone:BAAALgAECgEJAwAAAA==.Daul:BAAALgADCgEJAQAAAA==.Dawnson:BAABLgAECn8oAAIbAAkJbCB+BQA7AwAbAAkJbCB+BQA7AwAAAA==.',
De='Deadzexcs:BAABLgAECn8fAAIaAAcJiw9tAgAXAQAaAAcJiw9tAgAXAQAAAA==.Deathsnear:BAAALgAECgEJAQAAAA==.Demogless:BAABLgAECn9OAAMcAAgJyg8OBAADAQAdAAgJjgsRcgA+AQAcAAYJ5RAOBAADAQAAAA==.Desyrel:BAAALgAECgYJBgABLgAECgkJIgAVAEoMAA==.Devyn:BAAALgADCgUJBQAAAA==.',
Dh='Dharknight:BAAALgAECgEJAQABLgAECgMJBgABAAAAAA==.',
Di='Didimissfire:BAEBLgAECn87AAIVAAkJlxShOAD7AQAVAAkJlxShOAD7AQAAAA==.Distal:BAAALgAECgcJBwAAAA==.',
Do='Donaghy:BAAALgAECgEJAQAAAA==.Dooms:BAAALgADCgcJBwAAAA==.',
Dp='Dpsmaster:BAABLgAECn8hAAIYAAcJPgjKUgDDAAAYAAcJPgjKUgDDAAAAAA==.',
Dr='Draeven:BAAALgAECgEJAQAAAA==.Dranalis:BAAALgAECgkJEgAAAA==.Drdrake:BAAALgADCgcJFAAAAA==.Dredlok:BAABLgAECn8WAAIDAAYJ3gQdCwBwAAADAAYJ3gQdCwBwAAAAAA==.Drufiyo:BAAALgAECgUJBQABLgAECgkJMAAdALUUAA==.',
Du='Dumonster:BAABLgAECn8gAAIRAAYJWgdbFQCXAAARAAYJWgdbFQCXAAAAAA==.',
['Dø']='Døll:BAAALgADCgYJBgAAAA==.',
Ea='Eamishal:BAAALgADCgEJAQAAAA==.',
Ei='Eightace:BAAALgAECgQJBgAAAA==.Eirenne:BAAALgAECgYJBwAAAA==.',
Ek='Ekaru:BAAALgADCgEJAQAAAA==.',
El='Eledell:BAAALgAECgUJCAAAAA==.Elethryia:BAAALgAECgcJDQAAAA==.Elev:BAAALgAECgYJDwAAAA==.Elindril:BAAALgAECgYJEwAAAA==.',
En='Enoth:BAAALgAECggJEQAAAA==.',
Eo='Eowynn:BAACLgAFFH8GAAIGAAMJfBo7SgDHAAAGAAMJfBo7SgDHAAAuAAQKfygAAgYACQnuH9MIACQDAAYACQnuH9MIACQDAAAA.',
Er='Erewhon:BAAALgADCgkJCQAAAA==.',
Es='Estella:BAABLgAECn8hAAILAAYJ7g3rxgD/AAALAAYJ7g3rxgD/AAAAAA==.',
Ev='Eventhorizon:BAAALgAECgkJBgAAAA==.Evielli:BAAALgADCgUJBQAAAA==.',
Fa='Faeriefire:BAAALgADCggJDQAAAA==.Fanna:BAAALgADCgMJAwAAAA==.Fatbox:BAABLgAECn8lAAIRAAkJjyDgKgCrAQARAAkJjyDgKgCrAQAAAA==.Faythh:BAABLgAECn8xAAMOAAkJfiHEBwDyAgAOAAkJfiHEBwDyAgAeAAEJVhsNbwBMAAAAAA==.',
Fe='Fearblade:BAABLgAECn8VAAIdAAUJnA6erQDLAAAdAAUJnA6erQDLAAAAAA==.Fearkin:BAAALgAECgcJBwAAAA==.Fedoran:BAABLgAECn8pAAUMAAkJRB9iAwCuAQAIAAcJyyGnCABTAgAMAAcJABliAwCuAQAXAAcJbREERACAAQAYAAYJnBxYTgDwAAAAAA==.Felasap:BAAALgAECgcJCAAAAA==.Fenastic:BAABLgAECn8nAAMCAAkJIgcKegBFAQACAAkJqAYKegBFAQAEAAMJEAYsHACRAAAAAA==.Fenrisúlfur:BAAALgAECgUJDQAAAA==.Fermy:BAAALgADCgEJAQAAAA==.Feyrah:BAABLgAECn8UAAIfAAkJzByvAQCeAgAfAAkJzByvAQCeAgABLgAFFAMJBgAGAHwaAA==.',
Fi='Filthy:BAAALgAECgkJCQAAAA==.Finwë:BAAALgAECgMJAwAAAA==.Fiobhe:BAABLgAECn87AAIbAAkJFBmSFwBNAgAbAAkJFBmSFwBNAgAAAA==.Fixeruper:BAABLgAECn8cAAIOAAgJswEOTQCuAAAOAAgJswEOTQCuAAAAAA==.',
Fl='Flaggedname:BAAALgADCgMJAwABLgAECgkJFQAUAGUUAA==.Flubberduck:BAAALgAECgMJBAAAAA==.Fluffybeer:BAABLgAECn8gAAISAAgJrh1wPAAPAgASAAgJrh1wPAAPAgAAAA==.',
Fo='Fonz:BAAALgAECgYJBgABLgAECgcJGwAbAHYQAA==.Footdig:BAABLgAECn89AAIXAAkJjSMoBAB8AwAXAAkJjSMoBAB8AwAAAA==.',
Fr='Frøstbìtê:BAAALgADCgUJBQAAAA==.',
Fu='Fuquan:BAAALgAECgYJCgAAAA==.',
Fw='Fwd:BAAALgADCgIJAgAAAA==.',
Ga='Gadzook:BAAALgADCggJFQAAAA==.Garthok:BAAALgADCggJCAAAAA==.Gatolun:BAAALgADCgUJBQAAAA==.',
Gi='Giline:BAAALgAECgEJAQAAAA==.Gimp:BAAALgADCgEJAQAAAA==.Ginja:BAAALgADCgIJAgAAAA==.',
Gl='Glenlizzo:BAAALgADCgYJDQABLgAECggJHgAMAJ0aAA==.Glenroyce:BAABLgAECn8eAAIMAAgJnRrCAwCeAQAMAAgJnRrCAwCeAQAAAA==.Gless:BAABLgAECn9EAAIQAAgJCBQJAwCuAQAQAAgJCBQJAwCuAQAAAA==.',
Go='Goodfine:BAAALgADCgcJDwAAAA==.Goss:BAAALgAECgMJAwAAAA==.Goteem:BAAALgADCggJDAAAAA==.',
Gr='Grandcross:BAAALgADCgMJAwAAAA==.Grapedrink:BAABLgAECn8WAAIbAAYJKhpeBADGAQAbAAYJKhpeBADGAQABLgAECgkJJQARAI8gAA==.Griimtotem:BAAALgAECgQJBAAAAA==.Groen:BAAALgAECgIJAgABLgAECgkJMQAQABwVAA==.',
Gu='Gueret:BAAALgAECgEJAQAAAA==.Gungnir:BAABLgAECn8dAAMgAAgJnRjtFwD0AQAgAAgJnRjtFwD0AQAhAAYJggfQewCrAAAAAA==.Gush:BAAALgADCgQJBAAAAA==.Guttertrash:BAAALgAECgIJAgAAAA==.',
Gw='Gwendelspear:BAAALgADCgQJBAABLgAECgkJEQABAAAAAA==.',
Ha='Hae:BAAALgADCgEJAQAAAA==.Haenus:BAAALgAECgYJEAAAAA==.Haill:BAAALgAECgkJEQAAAA==.Hamhock:BAABLgAECn9ZAAIfAAgJMiKTAQC1AgAfAAgJMiKTAQC1AgABLgAECgkJJQARAI8gAA==.Hammered:BAAALgAECgQJAQABLgAECggJHgAMAJ0aAA==.Hanis:BAAALgADCgIJAgAAAA==.Hardtobepro:BAAALgAECgcJBwAAAA==.Harleydk:BAAALgADCgUJBQAAAA==.Hawks:BAAALgADCggJCQAAAA==.',
He='Heartsong:BAAALgAECgcJBgAAAA==.Hellìos:BAAALgAECgEJAQABLgAECggJFAARACgXAA==.Hevn:BAAALgAECgQJBAABLgAECgkJIgAVAEoMAA==.',
Ho='Holycrusader:BAABLgAECn8YAAIFAAgJWBJIXQDLAQAFAAgJWBJIXQDLAQAAAA==.Hoop:BAAALgAECgMJBQAAAA==.Hornito:BAAALgAECgYJCAAAAA==.',
Ic='Icerug:BAAALgAECgYJBwABLgAFFAQJCgAXANQUAA==.',
Ih='Ihatepallys:BAAALgAECgUJDAAAAA==.',
Ii='Iikeomgikr:BAAALgADCgEJAQAAAA==.',
Il='Ildefonso:BAAALgAECgEJAQABLgAECgcJGwAbAHYQAA==.Ilduca:BAAALgADCgYJBwAAAA==.Ilidank:BAABLgAECn8nAAIdAAkJOB/iAQCoAgAdAAkJOB/iAQCoAgAAAA==.Ilya:BAAALgAECgUJCwABLgAECggJKQAFAHcbAA==.',
Im='Impotence:BAAALgADCgMJAwAAAA==.',
In='Indigo:BAABLgAECn+cAAMGAAkJ5CI/AQA2AwAGAAkJ5CI/AQA2AwAHAAcJ6RzfAwDqAQAAAA==.Innax:BAAALgADCgEJAQAAAA==.Innron:BAABLgAECn8xAAMfAAkJSxHyGQCwAQAfAAkJSxHyGQCwAQAcAAIJWwMzMgA7AAAAAA==.',
Ir='Irisblue:BAAALgADCgkJDwAAAA==.',
Iy='Iyahli:BAAALgAECgUJDwAAAA==.',
Ja='Jaedia:BAAALgAECgQJBgAAAA==.Jaque:BAAALgADCgEJAQAAAA==.Jarclian:BAACLgAFFH8PAAILAAQJ9Rf1ZQAXAQALAAQJ9Rf1ZQAXAQAuAAQKf0AAAgsACQnRIrcRAPACAAsACQnRIrcRAPACAAAA.Jaymonk:BAAALgAECgkJDgAAAA==.Jazmon:BAAALgAECgIJAgAAAA==.',
Je='Jezzea:BAAALgADCgkJEgAAAA==.',
Ji='Jimlaheys:BAAALgAECgYJDgAAAA==.Jinjix:BAAALgAECgEJAwAAAA==.Jitt:BAABLgAECn8XAAIdAAYJYxv9TwCVAQAdAAYJYxv9TwCVAQAAAA==.',
Jo='Jolike:BAAALgAECgMJAwAAAA==.Joséphine:BAAALgADCgkJGwAAAA==.',
['Jâ']='Jâten:BAABLgAECn8WAAIgAAkJxBlCDgBjAgAgAAkJxBlCDgBjAgABLgAFFAcJEgAdAGMdAA==.Jâtens:BAACLgAFFH8SAAMdAAcJYx27DQDWAQAdAAcJYx27DQDWAQAcAAEJAgRCFQAlAAAuAAQKfyIAAh0ACAlxH2AdAGQCAB0ACAlxH2AdAGQCAAAA.',
Ka='Kaelía:BAABLgAECn8VAAMdAAgJtw1tEwDkAAAdAAgJOQxtEwDkAAAcAAMJVgfjCABlAAAAAA==.Kair:BAACLgAFFH8LAAIgAAMJLwfrLQCRAAAgAAMJLwfrLQCRAAAuAAQKfykAAiAACQnUCsMwAEQBACAACQnUCsMwAEQBAAAA.Kairring:BAABLgAECn8jAAIVAAkJ4BSVMAAZAgAVAAkJ4BSVMAAZAgAAAA==.Kame:BAAALgAECgUJBQAAAA==.Kamehameha:BAABLgAECn8YAAIZAAkJlRX/CQDTAQAZAAkJlRX/CQDTAQAAAA==.Kami:BAABLgAECn80AAIgAAkJ1xOrHADJAQAgAAkJ1xOrHADJAQAAAA==.Kapslock:BAAALgAECgYJBwAAAA==.Karii:BAAALgADCgEJAQAAAA==.Karma:BAAALgADCgcJHAAAAA==.Katsicle:BAABLgAECn84AAILAAgJvwqmFAAtAQALAAgJvwqmFAAtAQAAAA==.Kattastrophy:BAABLgAECn8eAAMCAAgJ0AdqEgDbAAACAAgJOgdqEgDbAAADAAgJ+gU7GwDLAAAAAA==.Katteya:BAAALgAECgcJEAAAAA==.Kattia:BAABLgAECn8sAAIVAAkJkA6RTwC0AQAVAAkJkA6RTwC0AQAAAA==.Kazmoru:BAAALgAECgEJAQAAAA==.',
Kh='Khalico:BAAALgADCgEJAQAAAA==.Khat:BAAALgAECgUJCgAAAA==.Khellendros:BAAALgADCgUJBQABLgAECgYJCgABAAAAAA==.Khir:BAAALgAECgQJBwAAAA==.',
Ki='Killinkair:BAAALgAECgYJBgAAAA==.Kimosabi:BAAALgAECgIJAgABLgAECgcJFwASAMsZAA==.Kinomihime:BAABLgAECn83AAILAAkJ3w+iYQC8AQALAAkJ3w+iYQC8AQAAAA==.Kirajoy:BAABLgAECn99AAIDAAkJ2QwSBAAvAQADAAkJ2QwSBAAvAQAAAA==.Kirel:BAAALgADCgEJAQAAAA==.Kithri:BAAALgADCgEJAQAAAA==.Kitkatt:BAAALgAECgYJCQAAAA==.Kiymeria:BAAALgAECgYJBgAAAA==.',
Kn='Knyghtt:BAABLgAECn8jAAIRAAgJDw+nNQByAQARAAgJDw+nNQByAQAAAA==.',
Ko='Kogwyn:BAAALgAECggJEQAAAA==.Kogy:BAAALgADCgcJBgABLgAECggJEQABAAAAAA==.',
Kr='Krakor:BAAALgADCgYJBgAAAA==.Kraviz:BAAALgAECgYJDgAAAA==.Krombopolous:BAAALgAECgUJBQABLgAECgkJPwAVAJoVAA==.Krystle:BAABLgAECn8wAAIVAAkJHhc7LwAgAgAVAAkJHhc7LwAgAgAAAA==.',
Ky='Kydormu:BAAALgADCgEJAQAAAA==.',
['Kä']='Käyfex:BAAALgAECgQJBAAAAA==.',
La='Lanfeer:BAAALgADCgEJAQAAAA==.Lazarus:BAAALgAECgkJCQAAAA==.',
Le='Leannan:BAAALgAECgUJCAAAAA==.Leftyloose:BAAALgADCgkJBAAAAA==.',
Li='Lilfonz:BAABLgAECn8bAAMbAAcJdhA7PgBMAQAbAAcJdhA7PgBMAQAFAAYJ/RgVnQBEAQAAAA==.Littlejohn:BAAALgAECgIJAgAAAA==.Livik:BAABLgAECn8cAAIWAAkJ2BxqAwBoAgAWAAkJ2BxqAwBoAgAAAA==.',
Lo='Lockofdeath:BAAALgADCgYJBwAAAA==.Lockywolf:BAAALgAECgUJBgAAAA==.Logarth:BAAALgAECgYJDAABLgAECggJGgAGAHIUAA==.Longbrew:BAAALgADCgEJAQAAAA==.Loppandload:BAAALgAECgMJAwAAAA==.Loppsang:BAABLgAECn8YAAMXAAkJJBElCwD1AAAXAAgJ6BAlCwD1AAAYAAEJBQ28JQAqAAAAAA==.Lopseng:BAAALgAECgMJAwAAAA==.Lorcan:BAABLgAECn82AAIiAAkJdhsuCwA1AgAiAAkJdhsuCwA1AgAAAA==.',
Lr='Lroye:BAACLgAFFH8WAAIjAAUJMRlVDQAxAQAjAAUJMRlVDQAxAQAuAAQKfxkAAiMABwnqHrcYANQBACMABwnqHrcYANQBAAAA.',
Lu='Luckyleet:BAAALgADCgQJCwAAAA==.Lucyfer:BAABLgAECn8bAAIHAAkJNwyJBwBWAQAHAAkJNwyJBwBWAQABLgAECgkJIgAVAEoMAA==.Lucyferr:BAABLgAECn8eAAILAAgJVgjXKACqAAALAAgJVgjXKACqAAABLgAECgkJIgAVAEoMAA==.Ludacritts:BAAALgAECgQJBAAAAA==.Ludicrispeed:BAAALgADCgkJFQAAAA==.Luliak:BAACLgAFFH8WAAITAAcJQSM5BQC8AQATAAcJQSM5BQC8AQAuAAQKfyAAAhMACQnRInYEAOYCABMACQnRInYEAOYCAAAA.Lunabren:BAABLgAECn8eAAMXAAgJ2A7RCQARAQAXAAcJYA3RCQARAQAYAAcJwwcJSwDgAAAAAA==.Lunamina:BAABLgAECn8sAAIVAAcJ8BqJCQDVAQAVAAcJ8BqJCQDVAQAAAA==.',
Ly='Lynvala:BAAALgADCgQJBQAAAA==.Lysdexíc:BAABLgAECn8aAAIdAAkJzhP4QQDCAQAdAAkJzhP4QQDCAQAAAA==.Lysdéxic:BAAALgAECgEJAQAAAA==.',
['Lì']='Lìllith:BAABLgAECn8sAAMOAAkJLB3wDQCHAgAOAAkJLB3wDQCHAgAkAAQJIwrgTgCXAAABLgAFFAIJDgAFAP0dAA==.',
Ma='Mactheknife:BAAALgADCgIJAgAAAA==.Majakdastudr:BAAALgAECgIJAgAAAA==.Majika:BAAALgADCgYJBQAAAA==.Mariophra:BAABLgAECn86AAIGAAkJ1xq6FQCdAgAGAAkJ1xq6FQCdAgAAAA==.Marvelious:BAAALgAFFAEJAQAAAA==.Mattlen:BAAALgADCgYJCAAAAA==.Maxdemon:BAAALgAECgUJBQAAAA==.Maximumswag:BAAALgADCgkJLQABLgAECgkJPwAVAJoVAA==.Maxmugruith:BAAALgADCgQJBwAAAA==.Maxtheb:BAAALgADCgYJDAAAAA==.Mayfair:BAAALgAECgYJBwAAAA==.',
Mc='Mcnastyqt:BAAALgAECgQJBAAAAA==.',
Me='Meatshiéld:BAAALgAECgYJCgAAAA==.',
Mi='Midopamos:BAAALgADCgEJAQAAAA==.Mikki:BAAALgAECgcJDwAAAA==.Milber:BAAALgAECgUJCQAAAA==.Missconduct:BAAALgADCgYJBgAAAA==.Misstorgo:BAABLgAECn8kAAIQAAkJoh4YAgAPAgAQAAkJoh4YAgAPAgAAAA==.',
Mo='Mohegian:BAAALgADCgEJAQAAAA==.Monfro:BAABLgAECn8UAAIVAAkJ2h46PQDsAQAVAAkJ2h46PQDsAQAAAA==.Moodswings:BAAALgAECgYJBgAAAA==.Moogatoo:BAAALgAECgYJCAABLgAECgcJFwASAMsZAA==.Moonbane:BAABLgAECn8sAAIDAAgJUCDOAwBQAgADAAgJUCDOAwBQAgAAAA==.Moonfanda:BAAALgADCgIJAgAAAA==.Moonmist:BAAALgADCgEJAQABLgAECgkJEQABAAAAAA==.Moor:BAAALgAECgYJDAAAAA==.Mordecai:BAAALgAECgUJBQAAAA==.',
Mu='Mumferd:BAAALgADCgQJBAAAAA==.',
My='Myaquean:BAAALgADCgkJFAAAAA==.Mystogan:BAABLgAECn8VAAISAAgJ2A9/HgC/AAASAAgJ2A9/HgC/AAAAAA==.Myth:BAAALgAECggJDAAAAA==.Mythelea:BAAALgAECgQJBAAAAA==.',
Na='Nakeefa:BAABLgAECn8nAAMCAAkJdBRxMwALAgACAAkJdBRxMwALAgADAAEJAAA9cgAzAAAAAA==.Natah:BAAALgADCgcJBwAAAA==.Natsuu:BAABLgAECn88AAMVAAkJPBuMCQDVAQAVAAgJsxyMCQDVAQATAAUJuQ6+NAAMAQAAAA==.Naturewolf:BAABLgAECn8eAAIIAAgJXRbsFAB2AQAIAAgJXRbsFAB2AQAAAA==.',
Ne='Nefertiti:BAAALgAECgcJCQAAAA==.Nekona:BAABLgAECn8VAAQCAAgJTwuEiQBGAQACAAgJTwuEiQBGAQADAAIJCgmuWwBcAAAEAAEJlwWVNAAzAAAAAA==.Neron:BAACLgAFFH8OAAIFAAIJ/R1XQwCVAAAFAAIJ/R1XQwCVAAAuAAQKf0QAAgUACQlYIBccAJwCAAUACQlYIBccAJwCAAAA.Nethertusk:BAABLgAECn8uAAMCAAkJTBmlMwAKAgACAAkJTBmlMwAKAgADAAIJYQP2WQBhAAAAAA==.',
Nh='Nhancecntrl:BAACLgAFFH8IAAIPAAMJ8QuICgCvAAAPAAMJ8QuICgCvAAAuAAQKfykAAg8ACQnRGkUFAJECAA8ACQnRGkUFAJECAAEuAAUUBAkNACUAKhIA.',
Ni='Niany:BAAALgAECgYJEgAAAA==.Nightbréaker:BAAALgAECgYJBgAAAA==.Nilospite:BAACLgAFFH8FAAIQAAUJTw93DADmAAAQAAUJTw93DADmAAAuAAQKfzIAAhAACAlwHpMJAFoCABAACAlwHpMJAFoCAAEuAAUUBwkeAA0AghUA.Nimposter:BAABLgAECn8rAAISAAkJNRfIOAAcAgASAAkJNRfIOAAcAgAAAA==.',
Nj='Njoror:BAAALgADCgQJBAAAAA==.',
No='Noodle:BAAALgADCgEJAQAAAA==.Norky:BAAALgAECgUJBQABLgAFFAQJEwAGAHEUAA==.Nottapally:BAAALgAECgcJEgABLgAECgkJFQAUAGUUAA==.',
Nu='Nullea:BAAALgAECgYJCAAAAA==.',
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
Pe='Pearle:BAABLgAECn8vAAINAAkJQx4aDABLAgANAAkJQx4aDABLAgAAAA==.',
Ph='Phyg:BAAALgAECgQJBQABLgAECgUJBwABAAAAAA==.',
Pi='Picts:BAAALgADCgMJAwAAAA==.',
Po='Pokimane:BAAALgADCggJDwAAAA==.Polyasap:BAAALgADCgQJBAAAAA==.',
Pr='Priestiô:BAAALgAECgEJAgAAAA==.Pringo:BAAALgAFFAIJAgAAAA==.Proximal:BAAALgAECgcJBwAAAA==.',
Pu='Pukka:BAAALgADCgcJEQABLgAECgkJJAAOADUaAA==.Punk:BAAALgAFFAEJAQAAAA==.',
Qa='Qahnaarin:BAAALgAFFAEJAQAAAA==.',
Ra='Rajax:BAABLgAECn8WAAIRAAkJKhFEIADuAQARAAkJKhFEIADuAQAAAA==.Ralphthedh:BAAALgAECgkJDwAAAA==.Ramindizzle:BAABLgAECn86AAIZAAkJcBYUCQDnAQAZAAkJcBYUCQDnAQAAAA==.Rangewolf:BAAALgADCgcJDgAAAA==.Rapidito:BAAALgAECgEJAQAAAA==.',
Re='Refreshing:BAAALgAECgUJCQAAAA==.Rejuvasap:BAABLgAECn8aAAQYAAgJMBpWKQC1AQAYAAgJMBpWKQC1AQAXAAUJ6R35OwCkAQAIAAMJqheuNQCHAAAAAA==.Rekki:BAAALgAECggJCQABLgAECgkJIgAVAEoMAA==.Reliri:BAAALgADCgMJAwAAAA==.Remlin:BAAALgADCgcJCAAAAA==.Retastic:BAAALgAECggJCQAAAA==.Retsall:BAAALgADCgUJBQAAAA==.Reâper:BAAALgAECgYJCgAAAA==.',
Ri='Rikal:BAAALgADCgYJEAAAAA==.Ripntearn:BAAALgAECgMJAwAAAA==.',
Ro='Rook:BAABLgAECn82AAIZAAkJ8A1kDgB4AQAZAAkJ8A1kDgB4AQAAAA==.Roye:BAACLgAFFH8cAAIFAAgJIxaKJgBvAQAFAAgJIxaKJgBvAQAuAAQKfx4AAgUACQl1HbYaAMkCAAUACQl1HbYaAMkCAAAA.',
Ru='Ruffiyo:BAABLgAECn8wAAMdAAkJtRSyPwDKAQAdAAkJrxOyPwDKAQAfAAgJ3Q+LLQBfAQAAAA==.Rugrahfreaky:BAACLgAFFH8KAAIXAAQJ1BRELQAAAQAXAAQJ1BRELQAAAQAuAAQKfzkAAhcACQl6IVMFAGMDABcACQl6IVMFAGMDAAAA.Rugrahh:BAABLgAECn8pAAMZAAkJux5MDwDGAgAZAAkJux5MDwDGAgATAAMJaQ+QQwC0AAABLgAFFAQJCgAXANQUAA==.Rugrahx:BAABLgAFFH8FAAIcAAMJ4Rl8BwDhAAAcAAMJ4Rl8BwDhAAABLgAFFAQJCgAXANQUAA==.Rugzco:BAABLgAFFH8MAAIhAAYJzQ7UEwBGAQAhAAYJzQ7UEwBGAQAAAA==.Ruthen:BAAALgAECgYJDgAAAA==.Ruìn:BAAALgAECgcJCQAAAA==.',
Sa='Sabermore:BAABLgAECn8dAAIFAAgJdxgNSADuAQAFAAgJdxgNSADuAQAAAA==.Sabina:BAABLgAECn83AAIHAAkJgAuhOQBQAQAHAAkJgAuhOQBQAQAAAA==.Sadako:BAAALgAECgYJCAABLgAECgkJIgAVAEoMAA==.Sadness:BAABLgAECn8bAAMgAAgJ0RoGAgAlAgAgAAgJ0RoGAgAlAgAnAAYJmAojSgDUAAAAAA==.Sadorick:BAAALgADCgkJLwAAAA==.Safira:BAAALgAECgQJBgABLgAFFAIJDgAFAP0dAA==.Sageguy:BAABLgAECn8dAAILAAYJ9gUbLgCQAAALAAYJ9gUbLgCQAAAAAA==.Sakurarose:BAAALgAECgQJBQAAAA==.Samerle:BAAALgADCgEJAQAAAA==.Sango:BAABLgAECn9DAAMfAAkJcBlXDgBAAgAfAAkJcBlXDgBAAgAdAAQJ2gKPwQB8AAAAAA==.Sarenity:BAAALgADCgkJFQAAAA==.Saucewalker:BAABLgAFFH8aAAISAAYJqxfHIwBIAQASAAYJqxfHIwBIAQAAAA==.Savagelykill:BAABLgAECn8eAAINAAYJvwrINgC7AAANAAYJvwrINgC7AAAAAA==.',
Sc='Scotch:BAABLgAECn9GAAMFAAkJOR17LgBHAgAFAAkJwBt7LgBHAgAUAAYJBSAwBABpAQAAAA==.Scotchnwater:BAABLgAECn8oAAMoAAgJRBPYAQC+AQAoAAgJRBPYAQC+AQApAAMJIwcQGwB0AAAAAA==.Scrubyheals:BAAALgADCgQJBwABLgAECgkJFQAUAGUUAA==.',
Se='Sendio:BAAALgAECgQJBAAAAA==.Senji:BAAALgADCgQJBAAAAA==.',
Sg='Sgtpayne:BAAALgADCgIJAgAAAA==.',
Sh='Shadornia:BAAALgAECgEJAQAAAA==.Shadowcrwlr:BAAALgAECgQJCgAAAA==.Shadowlock:BAAALgAECggJEwAAAA==.Shadowmane:BAAALgADCgQJBAAAAA==.Shaeixia:BAAALgADCggJCgAAAA==.Shamangroo:BAAALgAECgEJAQABLgAECggJGwAQAEoVAA==.Shamanio:BAABLgAECn8UAAIGAAkJaxwkAgDMAgAGAAkJaxwkAgDMAgAAAA==.Shamichangas:BAAALgAECgEJAQAAAA==.Shammying:BAAALgAECgUJCwAAAA==.Shamsham:BAAALgADCgIJAgAAAA==.Sharaaz:BAAALgAECgMJBgAAAA==.Shivalry:BAAALgADCgkJCwAAAA==.Shmiggy:BAAALgAECgQJCgAAAA==.',
Si='Silverytwo:BAAALgAECgYJCQAAAA==.Silverywine:BAAALgADCgkJCQAAAA==.Silverywolfe:BAABLgAECn8bAAIDAAcJ8xGvAwBAAQADAAcJ8xGvAwBAAQAAAA==.Simony:BAABLgAECn8qAAIFAAkJoQgyGAANAQAFAAkJoQgyGAANAQABLgAECgkJIgAVAEoMAA==.Sinton:BAAALgAECgEJAQAAAA==.',
Sk='Skorpyoh:BAAALgADCgYJBgAAAA==.Skovak:BAABLgAECn8VAAIUAAkJkA70FQB2AQAUAAkJkA70FQB2AQAAAA==.Skoveth:BAAALgAECgQJBAAAAA==.Skybright:BAAALgAECggJCwAAAA==.',
So='Soggy:BAAALgAECgcJBwAAAA==.Sorayae:BAABLgAECn8kAAIOAAkJNRr1EwA/AgAOAAkJNRr1EwA/AgAAAA==.',
Sp='Specialk:BAABLgAECn8ZAAIFAAcJ4xU8DQCEAQAFAAcJ4xU8DQCEAQAAAA==.Spinnykat:BAAALgAECgMJBgAAAA==.Splooshh:BAAALgAECgkJDAABLgAECgkJMAAdALUUAA==.',
St='Starmist:BAAALgADCgMJAwAAAA==.Steeler:BAAALgAECgEJAQABLgAECgkJEQABAAAAAA==.Stinkfoot:BAAALgAECgUJCAAAAA==.Stoo:BAAALgADCgkJHAAAAA==.Stormkissed:BAABLgAECn8fAAMGAAkJIQwNUAByAQAGAAkJIQwNUAByAQAHAAEJQALlwQAcAAAAAA==.Stormweaver:BAAALgAECgUJBQAAAA==.Strongheart:BAAALgAECgMJBQABLgAECggJGgAGAHIUAA==.',
Su='Sugarush:BAAALgAECgEJAQABLgAECgkJEQABAAAAAA==.Sunil:BAABLgAECn9iAAIOAAkJxx7kBQAZAwAOAAkJxx7kBQAZAwAAAA==.Suviqhabo:BAAALgAECggJDwAAAA==.',
Sv='Svala:BAAALgADCgYJBgAAAA==.',
Sy='Syclic:BAAALgAECgUJBQABLgAECgkJMwAQABAmAA==.Syclone:BAABLgAECn8zAAIQAAkJECbHAABoAwAQAAkJECbHAABoAwAAAA==.Syladen:BAAALgAECgYJEgAAAA==.Syleste:BAAALgAECgQJBAABLgAECgkJMwAQABAmAA==.Syvi:BAAALgAECgYJCQABLgAECggJEQABAAAAAA==.',
Ta='Taetheron:BAAALgAECgUJBQAAAA==.Tahwe:BAAALgADCgUJBQAAAA==.Tattianna:BAABLgAECn8WAAIbAAgJHxtlKQDCAQAbAAgJHxtlKQDCAQAAAA==.Tavendar:BAAALgAECgkJEgABLgAFFAQJEwAGAHEUAA==.Tavil:BAAALgADCgMJAwAAAA==.Taírn:BAAALgAECgYJEAAAAA==.',
Te='Techie:BAABLgAECn8gAAMhAAkJTRKfJAD9AQAhAAkJTRKfJAD9AQAnAAUJpASfYgC4AAAAAA==.Teeser:BAABLgAECn8WAAIFAAYJAwO5LQGDAAAFAAYJAwO5LQGDAAAAAA==.Tehkatza:BAAALgAECgYJDAAAAA==.Terradactyl:BAAALgADCgMJAwAAAA==.',
Th='Theeyedoctor:BAAALgAECgQJBAABLgAECgkJFQAUAGUUAA==.Thesis:BAAALgADCgkJCQAAAA==.Thunderslate:BAABLgAECn8VAAIUAAkJZRQcEwCYAQAUAAkJZRQcEwCYAQAAAA==.Thôrin:BAAALgAECgUJBQAAAA==.',
Ti='Tigerlillee:BAAALgADCgcJDQAAAA==.Tigreth:BAABLgAECn82AAMFAAkJ1hTbUQDTAQAFAAkJ1hTbUQDTAQAUAAIJlhSvNgBoAAAAAA==.Timotheus:BAAALgAECgUJDAAAAA==.Tinkerballa:BAAALgAECgYJCgAAAA==.',
To='Tonï:BAAALgADCggJCAAAAA==.Totemzasap:BAAALgAECgEJAgAAAA==.',
Tr='Tragik:BAABLgAECn8mAAIPAAkJQA5uEACsAQAPAAkJQA5uEACsAQAAAA==.',
Tt='Ttrouble:BAAALgADCgUJBQAAAA==.',
Tu='Tuugadark:BAABLgAECn81AAICAAkJRx22JABMAgACAAkJRx22JABMAgAAAA==.Tuugashox:BAAALgAECgUJBQAAAA==.',
Tz='Tzulari:BAAALgAECgMJBgAAAA==.',
Ul='Ulyaoth:BAABLgAECn8/AAMCAAkJzw/dDwD9AAACAAkJ5Q3dDwD9AAADAAEJ7xvHDgBQAAAAAA==.',
Un='Unc:BAAALgAECgEJAQAAAA==.Unnerfable:BAAALgAECgYJCAAAAA==.',
Uw='Uwa:BAAALgADCgMJAwAAAA==.',
Uy='Uy:BAAALgAECgYJDwAAAA==.',
Va='Valakha:BAAALgAECgQJDwAAAA==.Valkyrie:BAAALgAECgQJBgAAAA==.',
Ve='Vedros:BAAALgADCgkJDgAAAA==.Vermouth:BAABLgAECn8eAAMOAAgJhxKSBAC6AQAOAAgJhxKSBAC6AQAkAAEJ6gmDKgAlAAAAAA==.Vespertilia:BAAALgAECgIJAgAAAA==.',
Vi='Viktoros:BAAALgAECgIJAgAAAA==.Violetra:BAAALgADCgMJAwAAAA==.',
Vo='Vorcan:BAAALgADCgYJBgAAAA==.Vorukh:BAABLgAECn8fAAQIAAkJohHCDgDIAQAIAAkJohHCDgDIAQAXAAMJ9gxKmACBAAAMAAEJyw/1gAAhAAAAAA==.',
Vr='Vrave:BAAALgADCgQJBQAAAA==.',
Vy='Vyhlet:BAAALgAECggJEgABLgAECgkJnAAGAOQiAA==.',
Wa='Warlockgroo:BAAALgADCgQJBAABLgAECggJGwAQAEoVAA==.Warriorgroo:BAABLgAECn8bAAIQAAgJShWmBgD2AAAQAAgJShWmBgD2AAAAAA==.',
We='Wendish:BAAALgAECgEJCgAAAA==.Wertyda:BAABLgAECn8aAAIbAAkJzhT4JgDSAQAbAAkJzhT4JgDSAQAAAA==.Wetnwild:BAAALgAECgUJBQAAAA==.',
Wh='Whácker:BAABLgAECn8UAAMiAAgJOwpYEgB8AQAiAAgJOwpYEgB8AQAQAAMJrAguOQCBAAABLgAECgYJEAABAAAAAA==.',
Wi='Wickdlovly:BAAALgADCgEJAQABLgAECgkJEQABAAAAAA==.Wickedslicks:BAABLgAECn9EAAIYAAkJMCI9CADQAgAYAAkJMCI9CADQAgAAAA==.Wildthangg:BAAALgAECgIJAgAAAA==.',
Wo='Wooddchipper:BAAALgADCgYJBgAAAA==.',
Wr='Wreckshop:BAABLgAECn8ZAAISAAkJ8xrzSQDkAQASAAkJ8xrzSQDkAQAAAA==.',
Wt='Wtfoxtrot:BAAALgADCgkJDAAAAA==.',
Xe='Xenøcide:BAAALgAECgcJEwAAAA==.',
Xi='Xiatus:BAAALgAECgUJBQABLgAECgkJKgASAOYhAA==.',
Xx='Xxlockz:BAABLgAECn8lAAMCAAkJWREwZwBvAQACAAgJ8A4wZwBvAQADAAMJGRFLIQCkAAAAAA==.Xxpallyz:BAAALgAECggJCwABLgAECgkJJQACAFkRAA==.',
Yi='Yinger:BAAALgADCgcJEAAAAA==.Yinglang:BAAALgADCgEJAQAAAA==.Yingling:BAABLgAECn8rAAISAAkJ6RmPQQD+AQASAAkJ6RmPQQD+AQAAAA==.',
Yo='Yohh:BAABLgAECn8wAAIGAAkJ8B2zAQABAwAGAAkJ8B2zAQABAwAAAA==.Yorshka:BAAALgAECgMJAwABLgAECgkJKgASAOYhAA==.',
Yu='Yukara:BAAALgAECgEJAQAAAA==.Yulay:BAAALgADCgkJBwAAAA==.Yuriko:BAABLgAECn83AAIhAAkJ1hONIwAEAgAhAAkJ1hONIwAEAgAAAA==.',
Za='Zadory:BAAALgAECgEJAwAAAA==.Zaidan:BAABLgAECn8UAAIfAAYJDAfzSwCHAAAfAAYJDAfzSwCHAAAAAA==.Zanpaktu:BAAALgAECgYJEwAAAA==.Zaraha:BAAALgADCgEJAQAAAA==.Zata:BAAALgAECgUJBwAAAA==.',
Ze='Zendous:BAAALgAECgcJBwAAAA==.Zeref:BAAALgAECgYJEgAAAA==.Zeur:BAAALgAECgEJAQAAAA==.Zevgrip:BAAALgAECgQJBQAAAA==.',
Zh='Zhia:BAAALgAECgQJBQAAAA==.',
Zi='Zippitydooda:BAAALgAECgEJAQABLgAECgkJEQABAAAAAA==.',
Zo='Zodiacc:BAABLgAECn84AAIMAAkJQxzvBgCJAgAMAAkJQxzvBgCJAgAAAA==.Zornen:BAAALgAECggJDQAAAA==.Zornhealer:BAAALgAECgUJBgABLgAECgYJEwABAAAAAA==.',
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
