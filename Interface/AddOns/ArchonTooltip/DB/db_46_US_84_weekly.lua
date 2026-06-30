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

local lookup = {'Unknown-Unknown','Warlock-Demonology','Shaman-Restoration','Shaman-Elemental','Druid-Feral','Mage-Arcane','Mage-Frost','Mage-Fire','Druid-Guardian','DeathKnight-Blood','Priest-Holy','Warlock-Destruction','Shaman-Enhancement','Warrior-Protection','Warrior-Fury','DeathKnight-Unholy','Hunter-Survival','Paladin-Protection','Hunter-BeastMastery','Rogue-Outlaw','Druid-Restoration','Druid-Balance','Hunter-Marksmanship','Rogue-Assassination','Paladin-Holy','DemonHunter-Vengeance','DemonHunter-Devourer','Paladin-Retribution','Priest-Discipline','Warlock-Affliction','Monk-Windwalker','Monk-Mistweaver','DemonHunter-Havoc','Warrior-Arms','Rogue-Subtlety','Priest-Shadow','DeathKnight-Frost','Evoker-Preservation','Evoker-Devastation','Monk-Brewmaster',}
local provider = {region='US',realm='EchoIsles',name='US',type='weekly',zone=46,date='2026-06-27',data={Aa='Aaelless:BAAALgAECgMJBAAAAA==.Aardz:BAAALgAECgYJCQAAAA==.',
Ab='Abeblinkin:BAAALgADCgkJDgAAAA==.Abrakadavar:BAAALgAECgQJBQAAAA==.Abräxis:BAAALgADCgkJCQABLgAECgMJAwABAAAAAA==.',
Ac='Acindis:BAAALgAECgIJAgAAAA==.Ackspez:BAAALgADCgYJBgAAAA==.',
Ae='Aeless:BAABLgAECn8fAAICAAkJKyKECwDyAgACAAkJKyKECwDyAgAAAA==.Aelless:BAAALgAECgYJCAAAAA==.Aenest:BAAALgADCggJCAAAAA==.',
Ai='Aiko:BAAALgADCgEJAQAAAA==.Aithinne:BAAALgAECgYJEwAAAA==.',
Ak='Akanah:BAAALgADCgcJBwAAAA==.',
Al='Alch:BAAALgAECgUJAQAAAA==.Alfira:BAAALgAECgYJEwAAAA==.Alghul:BAAALgAECgMJBAABLgAECgYJEwABAAAAAA==.',
Am='Amalthea:BAAALgADCgkJEAAAAA==.Amoredis:BAAALgADCgYJDQAAAA==.Amorlorin:BAAALgADCggJEwAAAA==.',
An='Anklbiterkat:BAAALgADCgQJBAAAAA==.Anume:BAAALgADCgkJFQAAAA==.',
Ar='Aragan:BAABLgAECn8UAAMDAAcJ8BrSCgCtAAADAAMJFxHSCgCtAAAEAAYJnw5QBwCqAAAAAA==.Aravis:BAABLgAECn8nAAIFAAgJmw2oGQBBAQAFAAgJmw2oGQBBAQAAAA==.Arese:BAABLgAECn8fAAQGAAYJTiZ/AwA0AgAGAAUJTiZ/AwA0AgAHAAMJlyTzEgHYAAAIAAEJAABTDABpAAAAAA==.Argopol:BAABLgAECn8iAAIJAAgJhyFUBgCbAgAJAAgJhyFUBgCbAgABLgAECgkJLwAKAEMeAA==.Aron:BAAALgADCgMJAgAAAA==.',
As='Ashandra:BAAALgADCgkJDwAAAA==.Ashlyssra:BAABLgAECn8fAAILAAkJYh0xCQDWAgALAAkJYh0xCQDWAgAAAA==.Asphonix:BAAALgADCgEJAQAAAA==.',
Aw='Awsomesause:BAAALgAECgQJBgAAAA==.',
Az='Azuri:BAAALgAECgYJCAAAAA==.Azzif:BAABLgAECn8hAAIMAAYJowPtJwB4AAAMAAYJowPtJwB4AAAAAA==.Azzraell:BAAALgADCgEJAQAAAA==.',
Ba='Babaorumm:BAAALgAECgQJBAAAAA==.Babasha:BAACLgAFFH8JAAINAAQJ6Qv7CwACAQANAAQJ6Qv7CwACAQAuAAQKfxsAAw0ABgmSH0sQAK0BAA0ABgmSH0sQAK0BAAMABgnADcJPAEUBAAAA.Babybluz:BAABLgAECn8sAAIHAAgJwA3AEgCjAAAHAAgJwA3AEgCjAAAAAA==.Baconloaf:BAAALgAECgUJCQAAAA==.Baifeng:BAAALgADCgkJFgAAAA==.Baldilocks:BAAALgADCgQJDAAAAA==.Barlas:BAAALgAECgEJAQAAAA==.Bat:BAAALgADCgEJAQAAAA==.',
Be='Beauriley:BAABLgAECn8xAAMOAAkJHBWsEwC0AQAOAAkJHBWsEwC0AQAPAAEJnA7vnwA1AAAAAA==.Behomethan:BAABLgAECn8mAAMDAAkJZBtJKgDlAQADAAgJOBpJKgDlAQAEAAgJABTTMgBxAQAAAA==.Berians:BAAALgAECgEJAQAAAA==.Beyonsláy:BAAALgAECgYJEQAAAA==.',
Bh='Bhipbookie:BAAALgAECgEJBAAAAA==.',
Bi='Billbetaray:BAAALgADCgMJAwAAAA==.',
Bl='Bluerift:BAAALgADCgEJAQAAAA==.Blux:BAAALgAECgEJAQAAAA==.',
Bo='Bobbyb:BAABLgAECn8XAAIQAAcJyxkUVwDAAQAQAAcJyxkUVwDAAQAAAA==.Bolton:BAAALgADCgMJAwAAAA==.Bombchele:BAAALgAECgYJBgABLgAECgkJGQAQAPMaAA==.Boneulngtime:BAAALgADCgUJCgAAAA==.Boon:BAAALgAECgIJAgAAAA==.Bowlofwrong:BAAALgAECgYJBwAAAA==.',
Br='Bratticusrex:BAABLgAECn8mAAIPAAgJEQt7QQA/AQAPAAgJEQt7QQA/AQAAAA==.Brazier:BAAALgAECgQJBAAAAA==.Bresowar:BAAALgAECggJEAAAAA==.',
Bu='Bunnylicious:BAABLgAECn9QAAIDAAkJGyatAADZAwADAAkJGyatAADZAwAAAA==.Bunnymedic:BAABLgAECn8WAAILAAYJIh1LHgDSAQALAAYJIh1LHgDSAQABLgAECgkJUAADABsmAA==.',
Ca='Caebrylla:BAABLgAECn88AAIRAAkJhA8yFQD6AQARAAkJhA8yFQD6AQAAAA==.Calistie:BAAALgAECgIJAgAAAA==.Calver:BAAALgADCgQJBAAAAA==.Camigatu:BAAALgADCgQJBAAAAA==.Camil:BAABLgAECn8aAAISAAgJUQxbHQAqAQASAAgJUQxbHQAqAQABLgAFFAMJDQATAHsIAA==.Cang:BAAALgAECgIJAgAAAA==.Capulin:BAABLgAECn8lAAIPAAkJsBYQHgD+AQAPAAkJsBYQHgD+AQAAAA==.Catdurid:BAAALgADCgYJBgAAAA==.',
Ce='Cecilbrown:BAAALgADCgcJBgAAAA==.Cecimorte:BAABLgAECn86AAIKAAkJ4BmbDQAwAgAKAAkJ4BmbDQAwAgAAAA==.Cephalopod:BAABLgAECn8UAAIUAAgJ1RXEAwD5AQAUAAgJ1RXEAwD5AQAAAA==.',
Ch='Chargeasap:BAAALgAECgMJAwAAAA==.Charttopper:BAAALgAECgYJCQABLgAECggJFAASAEIUAA==.Chibby:BAAALgADCgMJAwAAAA==.Chimichanga:BAAALgAECgcJDAABLgAECggJFAASAEIUAA==.Chonker:BAABLgAECn84AAMVAAkJdSB/BwBAAwAVAAkJdSB/BwBAAwAWAAcJVwzlOwAiAQAAAA==.Chorelock:BAAALgADCgEJAQABLgAECggJFAASAEIUAA==.Chronormu:BAAALgAECgMJAwAAAA==.Chuckforrest:BAAALgAECgQJBAAAAA==.Chultis:BAABLgAECn8bAAQFAAgJuhQrEwCLAQAFAAgJuhQrEwCLAQAWAAEJ2wH5jgAeAAAVAAEJAgLF6QAbAAAAAA==.',
Ci='Cihato:BAABLgAECn83AAIJAAkJIxtQCQBVAgAJAAkJIxtQCQBVAgAAAA==.',
Cl='Claxious:BAABLgAECn8iAAIXAAkJlRmeBgAoAgAXAAkJlRmeBgAoAgAAAA==.Claye:BAACLgAFFH8TAAIDAAQJcRTyOAD/AAADAAQJcRTyOAD/AAAuAAQKfysAAgMACQnPHJURAMECAAMACQnPHJURAMECAAAA.Clubbinseals:BAAALgADCgMJAwAAAA==.',
Co='Coldshoulder:BAABLgAECn86AAMHAAkJfx8wGwC4AgAHAAkJfx8wGwC4AgAIAAQJaxOMCwC3AAAAAA==.Corelas:BAABLgAECn8vAAIHAAgJGg3VhwBnAQAHAAgJGg3VhwBnAQAAAA==.Corfellyn:BAAALgAECggJBAAAAA==.Couchdad:BAAALgAECgYJEwAAAA==.',
Cr='Crazymadman:BAABLgAECn8gAAIYAAYJXQfUAQCdAAAYAAYJXQfUAQCdAAAAAA==.Crescentbane:BAAALgAECgEJAQAAAA==.Crushingblow:BAAALgAECgkJAwAAAA==.',
Cy='Cyon:BAAALgADCgEJAQAAAA==.',
Da='Daalaria:BAAALgADCgEJAQAAAA==.Darkle:BAAALgAECgEJAQAAAA==.Darkone:BAAALgAECgEJAQAAAA==.Daul:BAAALgADCgEJAQAAAA==.Dawnson:BAABLgAECn8oAAIZAAkJbCB+BQA7AwAZAAkJbCB+BQA7AwAAAA==.',
De='Deadzexcs:BAABLgAECn8YAAIYAAcJCw26EgD6AAAYAAcJCw26EgD6AAAAAA==.Deathsnear:BAAALgAECgEJAQAAAA==.Demogless:BAABLgAECn87AAMaAAgJbw0tAgDBAAAbAAgJjgsRcgA+AQAaAAYJewwtAgDBAAAAAA==.Desyrel:BAAALgAECgYJBgABLgAECgkJKgAcAKMIAA==.Devyn:BAAALgADCgUJBQAAAA==.',
Dh='Dharknight:BAAALgAECgEJAQAAAA==.',
Di='Didimissfire:BAEBLgAECn87AAITAAkJlxShOAD7AQATAAkJlxShOAD7AQAAAA==.Distal:BAAALgAECgcJBwAAAA==.',
Do='Donaghy:BAAALgAECgEJAQAAAA==.Dooms:BAAALgADCgcJBwAAAA==.',
Dp='Dpsmaster:BAABLgAECn8eAAIWAAcJ5AXKUgDDAAAWAAcJ5AXKUgDDAAAAAA==.',
Dr='Dranalis:BAAALgAECggJEAAAAA==.Drdrake:BAAALgADCgcJFAAAAA==.Dredlok:BAAALgAECgUJEgAAAA==.Drufiyo:BAAALgAECgUJBQABLgAECgkJMAAbALUUAA==.',
Du='Dumonster:BAABLgAECn8fAAIPAAYJWgewCACiAAAPAAYJWgewCACiAAAAAA==.',
['Dø']='Døll:BAAALgADCgYJBgAAAA==.',
Ea='Eamishal:BAAALgADCgEJAQAAAA==.',
Ei='Eightace:BAAALgAECgQJBgAAAA==.Eirenne:BAAALgAECgYJBwAAAA==.',
Ek='Ekaru:BAAALgADCgEJAQAAAA==.',
El='Elethryia:BAAALgAECgcJDQAAAA==.Elev:BAAALgAECgYJDgAAAA==.Elindril:BAAALgAECgYJEwAAAA==.',
En='Enoth:BAAALgAECggJEQAAAA==.',
Eo='Eowynn:BAACLgAFFH8FAAIDAAIJYiI7SgDHAAADAAIJYiI7SgDHAAAuAAQKfyYAAgMACQnuH9MIACQDAAMACQnuH9MIACQDAAAA.',
Er='Erewhon:BAAALgADCgkJCQAAAA==.',
Es='Estella:BAABLgAECn8hAAIHAAYJ7g3rxgD/AAAHAAYJ7g3rxgD/AAAAAA==.',
Ev='Eventhorizon:BAAALgAECgkJBgAAAA==.Evielli:BAAALgADCgUJBQAAAA==.',
Fa='Faeriefire:BAAALgADCggJDQAAAA==.Fanna:BAAALgADCgMJAwAAAA==.Fatbox:BAABLgAECn8jAAIPAAkJMSDgKgCrAQAPAAkJMSDgKgCrAQAAAA==.Faythh:BAABLgAECn8xAAMLAAkJfiHEBwDyAgALAAkJfiHEBwDyAgAdAAEJVhsNbwBMAAAAAA==.',
Fe='Fearblade:BAABLgAECn8VAAIbAAUJnA6erQDLAAAbAAUJnA6erQDLAAAAAA==.Fedoran:BAABLgAECn8iAAQFAAkJRB+nCABTAgAFAAcJyyGnCABTAgAVAAcJbREERACAAQAWAAYJnBxYTgDwAAAAAA==.Felasap:BAAALgAECgcJCAAAAA==.Fenastic:BAABLgAECn8nAAMCAAkJIgcKegBFAQACAAkJqAYKegBFAQAeAAMJEAYsHACRAAAAAA==.Fenrisúlfur:BAAALgAECgUJDQAAAA==.Feyrah:BAAALgAECggJCwABLgAFFAIJBQADAGIiAA==.',
Fi='Filthy:BAAALgAECgkJCQAAAA==.Fiobhe:BAABLgAECn8tAAIZAAgJbhqSFwBNAgAZAAgJbhqSFwBNAgAAAA==.Fixeruper:BAABLgAECn8cAAILAAgJswEOTQCuAAALAAgJswEOTQCuAAAAAA==.',
Fl='Flaggedname:BAAALgADCgMJAwABLgAECggJFAASAEIUAA==.Flubberduck:BAAALgADCggJEAAAAA==.Fluffybeer:BAABLgAECn8gAAIQAAgJrh1wPAAPAgAQAAgJrh1wPAAPAgAAAA==.',
Fo='Fonz:BAAALgAECgYJBgABLgAECgcJGwAZAHYQAA==.Footdig:BAABLgAECn89AAIVAAkJjSMoBAB8AwAVAAkJjSMoBAB8AwAAAA==.',
Fu='Fuquan:BAAALgAECgYJCgAAAA==.',
Fw='Fwd:BAAALgADCgIJAgAAAA==.',
Ga='Gadzook:BAAALgADCggJFQAAAA==.Garthok:BAAALgADCggJCAAAAA==.Gatolun:BAAALgADCgUJBQAAAA==.',
Gi='Giline:BAAALgAECgEJAQAAAA==.Gimp:BAAALgADCgEJAQAAAA==.Ginja:BAAALgADCgIJAgAAAA==.',
Gl='Glenlizzo:BAAALgADCgYJDQABLgAECggJGgAJANgaAA==.Glenroyce:BAABLgAECn8aAAIJAAgJ2BoIBADjAAAJAAgJ2BoIBADjAAAAAA==.Gless:BAABLgAECn8dAAIOAAgJuAqWAgD6AAAOAAgJuAqWAgD6AAAAAA==.',
Go='Goodfine:BAAALgADCgcJDwAAAA==.Goss:BAAALgAECgMJAwAAAA==.Goteem:BAAALgADCggJDAAAAA==.',
Gr='Grandcross:BAAALgADCgMJAwAAAA==.Grapedrink:BAAALgAECgYJDgABLgAECgkJIwAPADEgAA==.Griimtotem:BAAALgAECgQJBAAAAA==.Groen:BAAALgAECgIJAgABLgAECgkJMQAOABwVAA==.',
Gu='Gungnir:BAABLgAECn8dAAMfAAgJnRjtFwD0AQAfAAgJnRjtFwD0AQAgAAYJggfQewCrAAAAAA==.Gush:BAAALgADCgQJBAAAAA==.Guttertrash:BAAALgAECgIJAgAAAA==.',
Gw='Gwendelspear:BAAALgADCgQJBAABLgAECggJEAABAAAAAA==.',
Ha='Hae:BAAALgADCgEJAQAAAA==.Haenus:BAAALgAECgYJDAAAAA==.Haill:BAAALgAECggJEAAAAA==.Hamhock:BAABLgAECn81AAIhAAgJrx4LAQAIAgAhAAgJrx4LAQAIAgABLgAECgkJIwAPADEgAA==.Hammered:BAAALgADCgUJBQABLgAECggJGgAJANgaAA==.Hardtobepro:BAAALgAECgcJBwAAAA==.Harleydk:BAAALgADCgUJBQAAAA==.Hawks:BAAALgADCggJCQAAAA==.',
He='Heartsong:BAAALgAECgcJBgAAAA==.',
Ho='Holycrusader:BAABLgAECn8YAAIcAAgJWBJIXQDLAQAcAAgJWBJIXQDLAQAAAA==.Hoop:BAAALgADCgUJEAAAAA==.Hornito:BAAALgAECgYJCAAAAA==.',
Ic='Icerug:BAAALgAECgYJBwABLgAFFAQJCgAVANQUAA==.',
Ih='Ihatepallys:BAAALgAECgUJDAAAAA==.',
Ii='Iikeomgikr:BAAALgADCgEJAQAAAA==.',
Il='Ildefonso:BAAALgAECgEJAQABLgAECgcJGwAZAHYQAA==.Ilduca:BAAALgADCgYJBwAAAA==.Ilidank:BAABLgAECn8mAAIbAAkJHR+kAADFAgAbAAkJHR+kAADFAgAAAA==.Ilya:BAAALgAECgUJCwABLgAECggJKQAcAHcbAA==.',
Im='Impotence:BAAALgADCgMJAwAAAA==.',
In='Indigo:BAABLgAECn9oAAMDAAkJbyFmBQBcAwADAAkJbyFmBQBcAwAEAAYJvBu5AgBcAQAAAA==.Innax:BAAALgADCgEJAQAAAA==.Innron:BAABLgAECn8xAAMhAAkJSxHyGQCwAQAhAAkJSxHyGQCwAQAaAAIJWwMzMgA7AAAAAA==.',
Ir='Irisblue:BAAALgADCgkJDwAAAA==.',
Iy='Iyahli:BAAALgAECgUJDwAAAA==.',
Ja='Jaedia:BAAALgADCgYJCQAAAA==.Jarclian:BAACLgAFFH8OAAIHAAQJiRT1ZQAXAQAHAAQJiRT1ZQAXAQAuAAQKf0AAAgcACQnRIrcRAPACAAcACQnRIrcRAPACAAAA.Jaymonk:BAAALgAECgkJDgAAAA==.Jazmon:BAAALgAECgIJAgAAAA==.',
Je='Jezzea:BAAALgADCgkJEgAAAA==.',
Ji='Jimlaheys:BAAALgAECgYJDgAAAA==.Jinjix:BAAALgAECgEJAwAAAA==.Jitt:BAABLgAECn8XAAIbAAYJYxv9TwCVAQAbAAYJYxv9TwCVAQAAAA==.',
Jo='Jolike:BAAALgADCgUJBwAAAA==.Joséphine:BAAALgADCgkJGwAAAA==.',
['Jâ']='Jâten:BAABLgAECn8WAAIfAAkJxBlCDgBjAgAfAAkJxBlCDgBjAgABLgAFFAYJCwAbABgWAA==.Jâtens:BAACLgAFFH8LAAMbAAYJGBbLKgB8AQAbAAYJGBbLKgB8AQAaAAEJAgRCFQAlAAAuAAQKfyIAAhsACAlxH2AdAGQCABsACAlxH2AdAGQCAAAA.',
Ka='Kaelía:BAAALgAECggJEwAAAA==.Kair:BAACLgAFFH8LAAIfAAMJLwfrLQCRAAAfAAMJLwfrLQCRAAAuAAQKfykAAh8ACQnUCsMwAEQBAB8ACQnUCsMwAEQBAAAA.Kairring:BAABLgAECn8jAAITAAkJ4BSVMAAZAgATAAkJ4BSVMAAZAgAAAA==.Kame:BAAALgAECgUJBQAAAA==.Kamehameha:BAABLgAECn8YAAIXAAkJlRX/CQDTAQAXAAkJlRX/CQDTAQAAAA==.Kami:BAABLgAECn80AAIfAAkJ1xOrHADJAQAfAAkJ1xOrHADJAQAAAA==.Kapslock:BAAALgAECgYJBwAAAA==.Karii:BAAALgADCgEJAQAAAA==.Karma:BAAALgADCgcJHAAAAA==.Katsicle:BAABLgAECn8lAAIHAAgJiwVhDwDGAAAHAAgJiwVhDwDGAAAAAA==.Kattastrophy:BAABLgAECn8VAAIMAAgJ9QU7GwDLAAAMAAgJ9QU7GwDLAAAAAA==.Katteya:BAAALgAECgYJDwAAAA==.Kattia:BAABLgAECn8pAAITAAkJkA6RTwC0AQATAAkJkA6RTwC0AQAAAA==.Kazmoru:BAAALgAECgEJAQAAAA==.',
Kh='Khalico:BAAALgADCgEJAQAAAA==.Khat:BAAALgAECgUJBQAAAA==.Khellendros:BAAALgADCgUJBQABLgAECgYJCgABAAAAAA==.Khir:BAAALgAECgQJBwAAAA==.',
Ki='Killinkair:BAAALgAECgYJBgAAAA==.Kinomihime:BAABLgAECn83AAIHAAkJ3w+iYQC8AQAHAAkJ3w+iYQC8AQAAAA==.Kirajoy:BAABLgAECn9hAAIMAAkJ/gk5FAANAQAMAAkJ/gk5FAANAQAAAA==.Kirel:BAAALgADCgEJAQAAAA==.Kithri:BAAALgADCgEJAQAAAA==.Kiymeria:BAAALgAECgYJBgAAAA==.',
Kn='Knyghtt:BAABLgAECn8jAAIPAAgJDw+nNQByAQAPAAgJDw+nNQByAQAAAA==.',
Ko='Kogwyn:BAAALgAECggJEQAAAA==.Kogy:BAAALgADCgcJBgABLgAECggJEQABAAAAAA==.',
Kr='Krakor:BAAALgADCgYJBgAAAA==.Kraviz:BAAALgAECgYJDgAAAA==.Krombopolous:BAAALgADCgkJIgABLgAECgkJOgATANsSAA==.Krystle:BAABLgAECn8wAAITAAkJHhc7LwAgAgATAAkJHhc7LwAgAgAAAA==.',
Ky='Kydormu:BAAALgADCgEJAQAAAA==.',
['Kä']='Käyfex:BAAALgAECgQJBAAAAA==.',
La='Lazarus:BAAALgAECgkJCQAAAA==.',
Le='Leftyloose:BAAALgADCgkJBAAAAA==.',
Li='Lilfonz:BAABLgAECn8bAAMZAAcJdhA7PgBMAQAZAAcJdhA7PgBMAQAcAAYJ/RgVnQBEAQAAAA==.Livik:BAABLgAECn8cAAIUAAkJzxxqAwBoAgAUAAkJzxxqAwBoAgAAAA==.',
Lo='Lockofdeath:BAAALgADCgYJBwAAAA==.Lockywolf:BAAALgAECgUJBgAAAA==.Logarth:BAAALgAECgYJDAABLgAECgcJFQADAG4SAA==.Longbrew:BAAALgADCgEJAQAAAA==.Loppsang:BAABLgAECn8VAAMVAAgJnBEMTQBbAQAVAAcJZxEMTQBbAQAWAAEJBQ3xDwAuAAAAAA==.Lorcan:BAABLgAECn82AAIiAAkJdhsuCwA1AgAiAAkJdhsuCwA1AgAAAA==.',
Lr='Lroye:BAACLgAFFH8QAAIjAAQJnBanHQAyAQAjAAQJnBanHQAyAQAuAAQKfxkAAiMABwnqHrcYANQBACMABwnqHrcYANQBAAAA.',
Ls='Lsdarko:BAAALgAECgEJAwAAAA==.',
Lu='Luckyleet:BAAALgADCgQJCwAAAA==.Lucyfer:BAABLgAECn8bAAIEAAkJOQxeAgB4AQAEAAkJOQxeAgB4AQABLgAECgkJKgAcAKMIAA==.Lucyferr:BAABLgAECn8eAAIHAAgJVggOEAC+AAAHAAgJVggOEAC+AAABLgAECgkJKgAcAKMIAA==.Ludacritts:BAAALgAECgQJBAAAAA==.Ludicrispeed:BAAALgADCgkJFQAAAA==.Luliak:BAACLgAFFH8QAAIRAAYJPCI5BQC8AQARAAYJPCI5BQC8AQAuAAQKfyAAAhEACQnRInYEAOYCABEACQnRInYEAOYCAAAA.Lunabren:BAABLgAECn8YAAMWAAcJwwcJSwDgAAAWAAcJwwcJSwDgAAAVAAIJoQYmwgBDAAAAAA==.Lunamina:BAAALgAECgYJEgAAAA==.',
Ly='Lynvala:BAAALgADCgQJBQAAAA==.Lysdexíc:BAABLgAECn8aAAIbAAkJzhP4QQDCAQAbAAkJzhP4QQDCAQAAAA==.',
['Lì']='Lìllith:BAABLgAECn8sAAMLAAkJLB3wDQCHAgALAAkJLB3wDQCHAgAkAAQJIwrgTgCXAAABLgAFFAIJDAAcANYbAA==.',
Ma='Mactheknife:BAAALgADCgIJAgAAAA==.Majika:BAAALgADCgYJBQAAAA==.Mariophra:BAABLgAECn86AAIDAAkJ1xq6FQCdAgADAAkJ1xq6FQCdAgAAAA==.Marvelious:BAAALgAFFAEJAQAAAA==.Mattlen:BAAALgADCgYJCAAAAA==.Maximumswag:BAAALgADCgkJLQABLgAECgkJOgATANsSAA==.Maxmugruith:BAAALgADCgQJBwAAAA==.Maxtheb:BAAALgADCgYJDAAAAA==.',
Mc='Mcnastyqt:BAAALgAECgQJBAAAAA==.',
Me='Meatshiéld:BAAALgAECgYJCgAAAA==.',
Mi='Midopamos:BAAALgADCgEJAQAAAA==.Mikki:BAAALgAECgcJDwAAAA==.Milber:BAAALgADCgYJCgAAAA==.Missconduct:BAAALgADCgYJBgAAAA==.Misstorgo:BAABLgAECn8kAAIOAAkJpR6sAAAkAgAOAAkJpR6sAAAkAgAAAA==.',
Mo='Monfro:BAAALgAECggJEAAAAA==.Moogatoo:BAAALgAECgYJCAABLgAECgcJFwAQAMsZAA==.Moonbane:BAABLgAECn8sAAIMAAgJUCDOAwBQAgAMAAgJUCDOAwBQAgAAAA==.Moonfanda:BAAALgADCgIJAgAAAA==.Moonmist:BAAALgADCgEJAQABLgAECggJEAABAAAAAA==.Moor:BAAALgAECgYJDAAAAA==.',
Mu='Mumferd:BAAALgADCgQJBAAAAA==.',
My='Myaquean:BAAALgADCgkJFAAAAA==.Mystogan:BAAALgAECgcJEgAAAA==.Myth:BAAALgAECggJDAAAAA==.Mythelea:BAAALgAECgQJBAAAAA==.',
Na='Nakeefa:BAABLgAECn8nAAMCAAkJdBRxMwALAgACAAkJdBRxMwALAgAMAAEJAAA9cgAzAAAAAA==.Natah:BAAALgADCgcJBwAAAA==.Natsuu:BAABLgAECn8qAAMTAAkJOBtfRwDMAQATAAgJihxfRwDMAQARAAUJug6+NAAMAQAAAA==.Naturewolf:BAABLgAECn8eAAIFAAgJXRbsFAB2AQAFAAgJXRbsFAB2AQAAAA==.',
Ne='Nefertiti:BAAALgAECgcJCQAAAA==.Nekona:BAABLgAECn8VAAQCAAgJTwuEiQBGAQACAAgJTwuEiQBGAQAMAAIJCgmuWwBcAAAeAAEJlwWVNAAzAAAAAA==.Neron:BAACLgAFFH8MAAIcAAIJ1hvAIgCUAAAcAAIJ1hvAIgCUAAAuAAQKfzwAAhwACQlYIBccAJwCABwACQlYIBccAJwCAAAA.Nethertusk:BAABLgAECn8uAAMCAAkJTBmlMwAKAgACAAkJTBmlMwAKAgAMAAIJYQP2WQBhAAAAAA==.',
Nh='Nhancecntrl:BAACLgAFFH8IAAINAAMJ8QsvBADFAAANAAMJ8QsvBADFAAAuAAQKfykAAg0ACQnRGkUFAJECAA0ACQnRGkUFAJECAAAA.',
Ni='Niany:BAAALgAECgYJDwAAAA==.Nightbréaker:BAAALgADCgcJFQAAAA==.Nilospite:BAABLgAECn8yAAIOAAgJcB6TCQBaAgAOAAgJcB6TCQBaAgABLgAFFAcJHgAKAHIVAA==.Nimposter:BAABLgAECn8rAAIQAAkJNRfIOAAcAgAQAAkJNRfIOAAcAgAAAA==.',
Nj='Njoror:BAAALgADCgQJBAAAAA==.',
No='Noodle:BAAALgADCgEJAQAAAA==.Norky:BAAALgAECgUJBQABLgAFFAQJEwADAHEUAA==.Nottapally:BAAALgAECgcJEgABLgAECggJFAASAEIUAA==.',
Nu='Nullea:BAAALgAECgYJCAAAAA==.',
Ny='Nyxthos:BAAALgADCggJCAAAAA==.',
Ob='Obizi:BAAALgAECgEJAQAAAA==.',
Oc='Ocatarineta:BAAALgADCgIJAgAAAA==.',
Od='Odine:BAAALgAECgEJAgAAAA==.Odito:BAABLgAECn8VAAIWAAYJpRdwMABbAQAWAAYJpRdwMABbAQAAAA==.',
Om='Omegalich:BAAALgAECgEJAQAAAA==.',
Oo='Oopslol:BAAALgAECgYJDAAAAA==.',
Os='Osdavalmarro:BAAALgADCgYJGQAAAA==.',
Ot='Othaerion:BAABLgAECn8YAAIZAAkJbw+sKgC6AQAZAAkJbw+sKgC6AQAAAA==.',
Ou='Outerlimits:BAABLgAECn8uAAIlAAgJMRjRCwC7AQAlAAgJMRjRCwC7AQAAAA==.',
Pa='Paindore:BAAALgAECgQJBwAAAA==.Pamboo:BAABLgAECn8xAAIZAAkJzg/KJQDaAQAZAAkJzg/KJQDaAQAAAA==.Papalegba:BAAALgAECgEJAQAAAA==.',
Pe='Pearle:BAABLgAECn8vAAIKAAkJQx4aDABLAgAKAAkJQx4aDABLAgAAAA==.',
Ph='Phyg:BAAALgAECgQJBQABLgAECgUJBwABAAAAAA==.',
Po='Pokimane:BAAALgADCggJDwAAAA==.Polyasap:BAAALgADCgQJBAAAAA==.',
Pr='Priestiô:BAAALgAECgEJAgAAAA==.Pringo:BAAALgAFFAIJAgAAAA==.Proximal:BAAALgAECgcJBwAAAA==.',
Pu='Pukka:BAAALgADCgcJEQABLgAECgkJJAALADUaAA==.Punk:BAAALgAFFAEJAQAAAA==.',
Qa='Qahnaarin:BAAALgAFFAEJAQAAAA==.',
Ra='Rajax:BAABLgAECn8WAAIPAAkJKhFEIADuAQAPAAkJKhFEIADuAQAAAA==.Ralphthedh:BAAALgAECgkJDwAAAA==.Ramindizzle:BAABLgAECn86AAIXAAkJcBYUCQDnAQAXAAkJcBYUCQDnAQAAAA==.Rangewolf:BAAALgADCgcJDgAAAA==.',
Re='Refreshing:BAAALgAECgQJBQAAAA==.Rejuvasap:BAABLgAECn8aAAQWAAgJMBpWKQC1AQAWAAgJMBpWKQC1AQAVAAUJ6R35OwCkAQAFAAMJqheuNQCHAAAAAA==.Rekki:BAAALgAECgEJAQABLgAECgkJKgAcAKMIAA==.Reliri:BAAALgADCgMJAwAAAA==.Remlin:BAAALgADCgcJCAAAAA==.Retastic:BAAALgAECgcJBwAAAA==.Retsall:BAAALgADCgUJBQAAAA==.Reâper:BAAALgAECgYJCgAAAA==.',
Ri='Rikal:BAAALgADCgYJEAAAAA==.',
Ro='Rook:BAABLgAECn82AAIXAAkJ8A1kDgB4AQAXAAkJ8A1kDgB4AQAAAA==.Roye:BAACLgAFFH8YAAIcAAYJqxSKJgBvAQAcAAYJqxSKJgBvAQAuAAQKfx4AAhwACQl1HbYaAMkCABwACQl1HbYaAMkCAAAA.',
Ru='Ruffiyo:BAABLgAECn8wAAMbAAkJtRSyPwDKAQAbAAkJrxOyPwDKAQAhAAgJ3Q+LLQBfAQAAAA==.Rugonk:BAABLgAFFH8IAAIgAAQJsA+3DgDkAAAgAAQJsA+3DgDkAAABLgAFFAQJCgAVANQUAA==.Rugrahfreaky:BAACLgAFFH8KAAIVAAQJ1BRELQAAAQAVAAQJ1BRELQAAAQAuAAQKfzkAAhUACQl6IVMFAGMDABUACQl6IVMFAGMDAAAA.Rugrahh:BAABLgAECn8pAAMXAAkJux5MDwDGAgAXAAkJux5MDwDGAgARAAMJaQ+QQwC0AAABLgAFFAQJCgAVANQUAA==.Rugrahx:BAABLgAFFH8FAAIaAAMJ4Rl8BwDhAAAaAAMJ4Rl8BwDhAAABLgAFFAQJCgAVANQUAA==.Ruthen:BAAALgAECgYJCwAAAA==.Ruìn:BAAALgAECgcJCQAAAA==.',
Sa='Sabermore:BAABLgAECn8cAAIcAAgJlxcNSADuAQAcAAgJlxcNSADuAQAAAA==.Sabina:BAABLgAECn83AAIEAAkJgAuhOQBQAQAEAAkJgAuhOQBQAQAAAA==.Sadako:BAAALgAECgYJCAABLgAECgkJKgAcAKMIAA==.Sadness:BAAALgAECgYJEwAAAA==.Sadorick:BAAALgADCgkJLwAAAA==.Safira:BAAALgAECgQJBgABLgAFFAIJDAAcANYbAA==.Sageguy:BAABLgAECn8bAAIHAAYJwQVlEwCcAAAHAAYJwQVlEwCcAAAAAA==.Samerle:BAAALgADCgEJAQAAAA==.Sango:BAABLgAECn9DAAMhAAkJcBlXDgBAAgAhAAkJcBlXDgBAAgAbAAQJ2gKPwQB8AAAAAA==.Saucewalker:BAABLgAFFH8TAAIQAAUJkBsvRwBlAQAQAAUJkBsvRwBlAQAAAA==.Savagelykill:BAABLgAECn8YAAIKAAYJvwrINgC7AAAKAAYJvwrINgC7AAAAAA==.',
Sc='Scotch:BAABLgAECn85AAMcAAkJ6ht7LgBHAgAcAAkJ6ht7LgBHAgASAAYJuBe3AgD2AAAAAA==.Scotchnwater:BAABLgAECn8jAAMmAAgJSxFLAQAiAQAmAAgJSxFLAQAiAQAnAAMJIwcQGwB0AAAAAA==.Scrubyheals:BAAALgADCgQJBwABLgAECggJFAASAEIUAA==.',
Se='Sendio:BAAALgAECgQJBAAAAA==.Senji:BAAALgADCgQJBAAAAA==.',
Sg='Sgtpayne:BAAALgADCgIJAgAAAA==.',
Sh='Shadowcrwlr:BAAALgAECgQJCgAAAA==.Shadowlock:BAAALgAECggJEwAAAA==.Shadowmane:BAAALgADCgQJBAAAAA==.Shaeixia:BAAALgADCggJCgAAAA==.Shamangroo:BAAALgAECgEJAQABLgAECgYJFwAOADsWAA==.Shamanio:BAAALgAECgEJAgAAAA==.Shamichangas:BAAALgAECgEJAQAAAA==.Shammying:BAAALgAECgUJCwAAAA==.Shamsham:BAAALgADCgIJAgAAAA==.Sharaaz:BAAALgAECgMJBgAAAA==.Shivalry:BAAALgADCgkJCwAAAA==.Shmiggy:BAAALgAECgQJCgAAAA==.',
Si='Silverytwo:BAAALgAECgYJCQAAAA==.Silverywine:BAAALgADCgkJCQAAAA==.Silverywolfe:BAAALgAECgQJCQAAAA==.Simony:BAABLgAECn8qAAIcAAkJowh8BwA6AQAcAAkJowh8BwA6AQAAAA==.Sinton:BAAALgADCgIJAgAAAA==.',
Sk='Skorpyoh:BAAALgADCgYJBgAAAA==.Skovak:BAABLgAECn8VAAISAAkJkA70FQB2AQASAAkJkA70FQB2AQAAAA==.Skybright:BAAALgAECggJCwAAAA==.',
So='Soggy:BAAALgAECgcJBwAAAA==.Sorayae:BAABLgAECn8kAAILAAkJNRr1EwA/AgALAAkJNRr1EwA/AgAAAA==.',
Sp='Specialk:BAAALgAECgYJDQAAAA==.Spinnykat:BAAALgAECgMJBgAAAA==.Splooshh:BAAALgAECgkJDAABLgAECgkJMAAbALUUAA==.',
St='Starmist:BAAALgADCgMJAwAAAA==.Stinkfoot:BAAALgAECgUJCAAAAA==.Stoo:BAAALgADCgkJHAAAAA==.Stormkissed:BAABLgAECn8fAAMDAAkJIAwNUAByAQADAAkJIAwNUAByAQAEAAEJQALlwQAcAAAAAA==.Stormweaver:BAAALgAECgUJBQAAAA==.',
Su='Sunil:BAABLgAECn9TAAILAAkJxx7kBQAZAwALAAkJxx7kBQAZAwAAAA==.Suviqhabo:BAAALgAECggJDwAAAA==.',
Sv='Svala:BAAALgADCgYJBgAAAA==.',
Sy='Syclic:BAAALgAECgUJBQABLgAECgkJMwAOABAmAA==.Syclone:BAABLgAECn8zAAIOAAkJECbHAABoAwAOAAkJECbHAABoAwAAAA==.Syladen:BAAALgAECgYJEgAAAA==.Syleste:BAAALgAECgQJBAABLgAECgkJMwAOABAmAA==.Syvi:BAAALgAECgYJCQABLgAECggJEQABAAAAAA==.',
Ta='Taetheron:BAAALgAECgEJAQAAAA==.Tahwe:BAAALgADCgUJBQAAAA==.Tattianna:BAAALgAECgYJEgAAAA==.Tavendar:BAAALgAECgkJEQABLgAFFAQJEwADAHEUAA==.Tavil:BAAALgADCgMJAwAAAA==.Taírn:BAAALgAECgYJEAAAAA==.',
Te='Techie:BAABLgAECn8gAAMgAAkJTRKfJAD9AQAgAAkJTRKfJAD9AQAoAAUJpASfYgC4AAAAAA==.Teeser:BAABLgAECn8WAAIcAAYJAwMzHQBfAAAcAAYJAwMzHQBfAAAAAA==.Terradactyl:BAAALgADCgMJAwAAAA==.',
Th='Thesis:BAAALgADCgkJCQAAAA==.Thunderslate:BAABLgAECn8UAAISAAgJQhQcEwCYAQASAAgJQhQcEwCYAQAAAA==.Thôrin:BAAALgAECgUJBQAAAA==.',
Ti='Tigerlillee:BAAALgADCgcJDQAAAA==.Tigreth:BAABLgAECn82AAMcAAkJ1hTbUQDTAQAcAAkJ1hTbUQDTAQASAAIJlhSvNgBoAAAAAA==.Timotheus:BAAALgAECgUJDAAAAA==.',
To='Tonï:BAAALgADCggJCAAAAA==.Totemzasap:BAAALgAECgEJAgAAAA==.',
Tr='Tragik:BAABLgAECn8mAAINAAkJQA5uEACsAQANAAkJQA5uEACsAQAAAA==.',
Tt='Ttrouble:BAAALgADCgUJBQAAAA==.',
Tu='Tuugadark:BAABLgAECn81AAICAAkJRx22JABMAgACAAkJRx22JABMAgAAAA==.Tuugashox:BAAALgAECgUJBQAAAA==.',
Ul='Ulyaoth:BAABLgAECn84AAICAAgJjQspcQBYAQACAAgJjQspcQBYAQAAAA==.',
Un='Unc:BAAALgAECgEJAQAAAA==.Unnerfable:BAAALgAECgYJCAAAAA==.',
Uw='Uwa:BAAALgADCgMJAwAAAA==.',
Uy='Uy:BAAALgAECgYJDwAAAA==.',
Va='Valakha:BAAALgAECgQJDwAAAA==.Valkyrie:BAAALgAECgQJBgAAAA==.',
Ve='Vedros:BAAALgADCgkJDgAAAA==.Vermouth:BAAALgAECgYJDAAAAA==.Vespertilia:BAAALgAECgIJAgAAAA==.',
Vi='Viktoros:BAAALgAECgIJAgAAAA==.Violetra:BAAALgADCgMJAwAAAA==.',
Vo='Vorcan:BAAALgADCgYJBgAAAA==.Vorukh:BAABLgAECn8fAAQFAAkJmxHCDgDIAQAFAAkJmxHCDgDIAQAVAAMJ9gxKmACBAAAJAAEJyw/1gAAhAAAAAA==.',
Vr='Vrave:BAAALgADCgQJBQAAAA==.',
Vy='Vyhlet:BAAALgAECggJEgABLgAECgkJaAADAG8hAA==.',
Wa='Warlockgroo:BAAALgADCgQJBAABLgAECgYJFwAOADsWAA==.Warriorgroo:BAABLgAECn8XAAIOAAYJOxZZJgD/AAAOAAYJOxZZJgD/AAAAAA==.',
We='Wendish:BAAALgAECgEJCgAAAA==.Wertyda:BAABLgAECn8aAAIZAAkJzhT4JgDSAQAZAAkJzhT4JgDSAQAAAA==.Wetnwild:BAAALgAECgUJBQAAAA==.',
Wh='Whácker:BAABLgAECn8UAAMiAAgJOwpYEgB8AQAiAAgJOwpYEgB8AQAOAAMJrAguOQCBAAABLgAECgYJEAABAAAAAA==.',
Wi='Wickdlovly:BAAALgADCgEJAQABLgAECggJEAABAAAAAA==.Wickedslicks:BAABLgAECn87AAIWAAkJdCA9CADQAgAWAAkJdCA9CADQAgAAAA==.Wildthangg:BAAALgAECgIJAgAAAA==.',
Wo='Wooddchipper:BAAALgADCgYJBgAAAA==.',
Wr='Wreckshop:BAABLgAECn8ZAAIQAAkJ8xrzSQDkAQAQAAkJ8xrzSQDkAQAAAA==.',
Wt='Wtfoxtrot:BAAALgADCgkJDAAAAA==.',
Xe='Xenøcide:BAAALgAECgcJEwAAAA==.',
Xi='Xiatus:BAAALgAECgUJBQABLgAECgkJKgAQAOYhAA==.',
Xx='Xxlockz:BAABLgAECn8lAAMCAAkJWREwZwBvAQACAAgJ8A4wZwBvAQAMAAMJGRFLIQCkAAAAAA==.Xxpallyz:BAAALgAECggJCwABLgAECgkJJQACAFkRAA==.',
Yi='Yinger:BAAALgADCgcJEAAAAA==.Yinglang:BAAALgADCgEJAQAAAA==.Yingling:BAABLgAECn8rAAIQAAkJ6RmPQQD+AQAQAAkJ6RmPQQD+AQAAAA==.',
Yo='Yohh:BAABLgAECn8hAAIDAAkJ3RdhAQBYAgADAAkJ3RdhAQBYAgAAAA==.Yorshka:BAAALgAECgMJAwABLgAECgkJKgAQAOYhAA==.',
Yu='Yukara:BAAALgAECgEJAQAAAA==.Yulay:BAAALgADCgkJBwAAAA==.Yuriko:BAABLgAECn83AAIgAAkJ1hONIwAEAgAgAAkJ1hONIwAEAgAAAA==.',
Za='Zadory:BAAALgAECgEJAQAAAA==.Zaidan:BAABLgAECn8UAAIhAAYJDAfzSwCHAAAhAAYJDAfzSwCHAAAAAA==.Zanpaktu:BAAALgAECgYJEwAAAA==.Zaraha:BAAALgADCgEJAQAAAA==.Zata:BAAALgAECgUJBwAAAA==.',
Ze='Zendous:BAAALgAECgcJBwAAAA==.Zeref:BAAALgAECgYJEgAAAA==.Zeur:BAAALgAECgEJAQAAAA==.Zevgrip:BAAALgAECgQJBQAAAA==.',
Zh='Zhia:BAAALgAECgQJBQAAAA==.',
Zi='Zippitydooda:BAAALgAECgEJAQABLgAECggJEAABAAAAAA==.',
Zo='Zodiacc:BAABLgAECn84AAIJAAkJQxzvBgCJAgAJAAkJQxzvBgCJAgAAAA==.Zornen:BAAALgAECggJDQAAAA==.Zornhealer:BAAALgAECgUJBgABLgAECgYJEwABAAAAAA==.',
Zy='Zyxxyz:BAAALgADCgkJCQABLgAECgkJMAAbALUUAA==.',
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
