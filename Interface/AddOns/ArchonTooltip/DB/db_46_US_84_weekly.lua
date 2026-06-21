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

local lookup = {'Unknown-Unknown','Warlock-Demonology','Druid-Feral','Mage-Arcane','Mage-Frost','Mage-Fire','Druid-Guardian','DeathKnight-Blood','Priest-Holy','Warlock-Destruction','Shaman-Enhancement','Shaman-Restoration','Warrior-Protection','Warrior-Fury','Shaman-Elemental','DeathKnight-Unholy','Hunter-Survival','Paladin-Protection','Hunter-BeastMastery','Rogue-Outlaw','Druid-Restoration','Druid-Balance','Hunter-Marksmanship','Rogue-Assassination','Paladin-Holy','DemonHunter-Devourer','DemonHunter-Vengeance','Paladin-Retribution','Priest-Discipline','Warlock-Affliction','Monk-Windwalker','Monk-Mistweaver','DemonHunter-Havoc','Warrior-Arms','Rogue-Subtlety','Priest-Shadow','DeathKnight-Frost','Evoker-Preservation','Evoker-Devastation','Monk-Brewmaster',}
local provider = {region='US',realm='EchoIsles',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aaelless:BAAALgAECgMJBAAAAA==.Aardz:BAAALgAECgQJBAAAAA==.',
Ab='Abeblinkin:BAAALgADCgkJDgAAAA==.Abrakadavar:BAAALgAECgQJBQAAAA==.Abräxis:BAAALgADCgkJCQABLgAECgMJAwABAAAAAA==.',
Ac='Ackspez:BAAALgADCgYJBgAAAA==.',
Ae='Aeless:BAABLgAECn8dAAICAAkJKyKECwDyAgACAAkJKyKECwDyAgAAAA==.Aelless:BAAALgAECgYJCAAAAA==.Aenest:BAAALgADCggJCAAAAA==.',
Ai='Aithinne:BAAALgAECgYJDgAAAA==.',
Ak='Akanah:BAAALgADCgcJBwAAAA==.',
Al='Alch:BAAALgAECgUJAQAAAA==.Alfira:BAAALgAECgYJEwAAAA==.Alghul:BAAALgAECgMJBAABLgAECgYJEwABAAAAAA==.',
Am='Amalthea:BAAALgADCgkJEAAAAA==.Amoredis:BAAALgADCgYJDQAAAA==.Amorlorin:BAAALgADCggJEwAAAA==.',
An='Anklbiterkat:BAAALgADCgQJBAAAAA==.Anume:BAAALgADCgkJFQAAAA==.',
Ar='Aragan:BAAALgAECgYJDQAAAA==.Aravis:BAABLgAECn8jAAIDAAgJmw2mGQBBAQADAAgJmw2mGQBBAQAAAA==.Arese:BAABLgAECn8fAAQEAAYJTiZ/AwA0AgAEAAUJTiZ/AwA0AgAFAAMJlyTzEgHYAAAGAAEJAABTDABpAAAAAA==.Argopol:BAABLgAECn8iAAIHAAgJhyFTBgCbAgAHAAgJhyFTBgCbAgABLgAECgkJLwAIAEMeAA==.Aron:BAAALgADCgMJAgAAAA==.',
As='Ashandra:BAAALgADCgkJDwAAAA==.Ashlyssra:BAABLgAECn8fAAIJAAkJYh0xCQDWAgAJAAkJYh0xCQDWAgAAAA==.Asphonix:BAAALgADCgEJAQAAAA==.',
Aw='Awsomesause:BAAALgAECgQJBgAAAA==.',
Az='Azuri:BAAALgAECgUJBgAAAA==.Azzif:BAABLgAECn8hAAIKAAYJowPrJwB4AAAKAAYJowPrJwB4AAAAAA==.Azzraell:BAAALgADCgEJAQAAAA==.',
Ba='Babaorumm:BAAALgAECgQJBAAAAA==.Babasha:BAACLgAFFH8JAAILAAQJ6Qv9CwACAQALAAQJ6Qv9CwACAQAuAAQKfxsAAwsABgmSH00QAK0BAAsABgmSH00QAK0BAAwABgnADcJPAEUBAAAA.Babybluz:BAABLgAECn8pAAIFAAgJ0QoLmwBDAQAFAAgJ0QoLmwBDAQAAAA==.Baconloaf:BAAALgAECgUJCQAAAA==.Baifeng:BAAALgADCgkJFgAAAA==.Baldilocks:BAAALgADCgQJDAAAAA==.Barlas:BAAALgAECgEJAQAAAA==.Bat:BAAALgADCgEJAQAAAA==.',
Be='Beauriley:BAABLgAECn8xAAMNAAkJHBWuEwC0AQANAAkJHBWuEwC0AQAOAAEJnA7snwA1AAAAAA==.Behomethan:BAABLgAECn8mAAMMAAkJZBtJKgDlAQAMAAgJOBpJKgDlAQAPAAgJABTPMgBxAQAAAA==.Berians:BAAALgAECgEJAQAAAA==.Beyonsláy:BAAALgAECgYJEQAAAA==.',
Bh='Bhipbookie:BAAALgAECgEJBAAAAA==.',
Bi='Billbetaray:BAAALgADCgMJAwAAAA==.',
Bl='Bluerift:BAAALgADCgEJAQAAAA==.Blux:BAAALgAECgEJAQAAAA==.',
Bo='Bobbyb:BAABLgAECn8XAAIQAAcJyxkSVwDAAQAQAAcJyxkSVwDAAQAAAA==.Bolton:BAAALgADCgMJAwAAAA==.Bombchele:BAAALgAECgYJBgABLgAECgkJGQAQAPMaAA==.Boneulngtime:BAAALgADCgUJCgAAAA==.Boon:BAAALgAECgIJAgAAAA==.Bowlofwrong:BAAALgAECgYJBwAAAA==.',
Br='Bratticusrex:BAABLgAECn8lAAIOAAgJKQp6QQA/AQAOAAgJKQp6QQA/AQAAAA==.Brazier:BAAALgAECgQJBAAAAA==.Bresowar:BAAALgAECggJDwAAAA==.',
Bu='Bunnylicious:BAABLgAECn9JAAIMAAkJGyatAADZAwAMAAkJGyatAADZAwAAAA==.Bunnymedic:BAABLgAECn8WAAIJAAYJIh1JHgDSAQAJAAYJIh1JHgDSAQABLgAECgkJSQAMABsmAA==.',
Ca='Caber:BAAALgAECgEJAQABLgAECggJDwABAAAAAA==.Caebrylla:BAABLgAECn88AAIRAAkJhA81FQD6AQARAAkJhA81FQD6AQAAAA==.Calistie:BAAALgAECgIJAgAAAA==.Calver:BAAALgADCgQJBAAAAA==.Camigatu:BAAALgADCgQJBAAAAA==.Camil:BAABLgAECn8aAAISAAgJUQxaHQAqAQASAAgJUQxaHQAqAQABLgAFFAMJCgATAHsIAA==.Cang:BAAALgAECgIJAgAAAA==.Capulin:BAABLgAECn8kAAIOAAkJsBYOHgD+AQAOAAkJsBYOHgD+AQAAAA==.Catdurid:BAAALgADCgYJBgAAAA==.',
Ce='Cecilbrown:BAAALgADCgcJBgAAAA==.Cecimorte:BAABLgAECn86AAIIAAkJ4BmdDQAwAgAIAAkJ4BmdDQAwAgAAAA==.Cephalopod:BAABLgAECn8UAAIUAAgJ1RXEAwD5AQAUAAgJ1RXEAwD5AQAAAA==.',
Ch='Chargeasap:BAAALgAECgMJAwAAAA==.Charttopper:BAAALgAECgYJCQABLgAECggJFAASAEIUAA==.Chibby:BAAALgADCgMJAwAAAA==.Chimichanga:BAAALgAECgcJDAABLgAECggJFAASAEIUAA==.Chonker:BAABLgAECn84AAMVAAkJdSB/BwBAAwAVAAkJdSB/BwBAAwAWAAcJVwzhOwAiAQAAAA==.Chorelock:BAAALgADCgEJAQABLgAECggJFAASAEIUAA==.Chronormu:BAAALgAECgMJAwAAAA==.Chuckforrest:BAAALgAECgQJBAAAAA==.Chultis:BAABLgAECn8bAAQDAAgJuhQpEwCLAQADAAgJuhQpEwCLAQAWAAEJ2wH5jgAeAAAVAAEJAgLF6QAbAAAAAA==.',
Ci='Cihato:BAABLgAECn83AAIHAAkJIxtQCQBVAgAHAAkJIxtQCQBVAgAAAA==.',
Cl='Claxious:BAABLgAECn8iAAIXAAkJlRmeBgAoAgAXAAkJlRmeBgAoAgAAAA==.Claye:BAACLgAFFH8TAAIMAAQJcRTwOAD/AAAMAAQJcRTwOAD/AAAuAAQKfyoAAgwACQnPHJURAMECAAwACQnPHJURAMECAAAA.',
Co='Coldshoulder:BAABLgAECn86AAMFAAkJfx8yGwC4AgAFAAkJfx8yGwC4AgAGAAQJaxOKCwC3AAAAAA==.Corelas:BAABLgAECn8tAAIFAAgJGg3UhwBnAQAFAAgJGg3UhwBnAQAAAA==.Corfellyn:BAAALgAECggJBAAAAA==.Couchdad:BAAALgAECgYJEwAAAA==.',
Cr='Crazymadman:BAABLgAECn8cAAIYAAYJawX/FgDBAAAYAAYJawX/FgDBAAAAAA==.Crushingblow:BAAALgAECgkJAwAAAA==.',
Cy='Cyon:BAAALgADCgEJAQAAAA==.',
Da='Daalaria:BAAALgADCgEJAQAAAA==.Darkone:BAAALgAECgEJAQAAAA==.Daul:BAAALgADCgEJAQAAAA==.Dawnson:BAABLgAECn8oAAIZAAkJbCB9BQA7AwAZAAkJbCB9BQA7AwAAAA==.',
De='Deadzexcs:BAABLgAECn8WAAIYAAYJ1Qq6EgD6AAAYAAYJ1Qq6EgD6AAAAAA==.Deathsnear:BAAALgAECgEJAQAAAA==.Demogless:BAABLgAECn82AAMaAAgJWw0ScgA+AQAaAAgJjgsScgA+AQAbAAYJ9gsmAQCMAAAAAA==.Desyrel:BAAALgAECgYJBgABLgAECgkJKgAcAKMIAA==.Devyn:BAAALgADCgUJBQAAAA==.',
Dh='Dharknight:BAAALgAECgEJAQAAAA==.',
Di='Didimissfire:BAEBLgAECn87AAITAAkJlxSiOAD7AQATAAkJlxSiOAD7AQAAAA==.',
Do='Donaghy:BAAALgAECgEJAQAAAA==.Dooms:BAAALgADCgcJBwAAAA==.',
Dp='Dpsmaster:BAABLgAECn8eAAIWAAcJ5AXDUgDDAAAWAAcJ5AXDUgDDAAAAAA==.',
Dr='Dranalis:BAAALgAECggJDwAAAA==.Drdrake:BAAALgADCgcJFAAAAA==.Dredlok:BAAALgAECgUJDwAAAA==.Drufiyo:BAAALgAECgUJBQABLgAECgkJMAAaALUUAA==.',
Du='Dumonster:BAABLgAECn8cAAIOAAYJOQZCagC4AAAOAAYJOQZCagC4AAAAAA==.',
['Dø']='Døll:BAAALgADCgYJBgAAAA==.',
Ea='Eamishal:BAAALgADCgEJAQAAAA==.',
Ei='Eightace:BAAALgAECgQJBgAAAA==.Eirenne:BAAALgAECgYJBwAAAA==.',
Ek='Ekaru:BAAALgADCgEJAQAAAA==.',
El='Elethryia:BAAALgAECgcJDQAAAA==.Elev:BAAALgAECgYJDgAAAA==.Elindril:BAAALgAECgYJEwAAAA==.',
En='Enoth:BAAALgAECggJEQAAAA==.',
Eo='Eowynn:BAACLgAFFH8FAAIMAAIJYiI6SgDHAAAMAAIJYiI6SgDHAAAuAAQKfyYAAgwACQnuH9UIACQDAAwACQnuH9UIACQDAAAA.',
Er='Erewhon:BAAALgADCgkJCQAAAA==.',
Es='Estella:BAABLgAECn8hAAIFAAYJ7g3lxgD/AAAFAAYJ7g3lxgD/AAAAAA==.',
Ev='Eventhorizon:BAAALgAECgkJBgAAAA==.Evielli:BAAALgADCgUJBQAAAA==.',
Fa='Faeriefire:BAAALgADCggJDQAAAA==.Fanna:BAAALgADCgMJAwAAAA==.Fatbox:BAABLgAECn8jAAIOAAkJMSDgKgCrAQAOAAkJMSDgKgCrAQAAAA==.Faythh:BAABLgAECn8xAAMJAAkJfiHEBwDyAgAJAAkJfiHEBwDyAgAdAAEJVhsLbwBMAAAAAA==.',
Fe='Fearblade:BAABLgAECn8VAAIaAAUJnA6arQDLAAAaAAUJnA6arQDLAAAAAA==.Fedoran:BAABLgAECn8iAAQDAAkJRB+nCABTAgADAAcJyyGnCABTAgAVAAcJbREHRACAAQAWAAYJnBxYTgDwAAAAAA==.Felasap:BAAALgAECgcJCAAAAA==.Fenastic:BAABLgAECn8nAAMCAAkJIgcIegBFAQACAAkJqAYIegBFAQAeAAMJEAYsHACRAAAAAA==.Fenrisúlfur:BAAALgAECgUJDQAAAA==.Feyrah:BAAALgAECggJCwABLgAFFAIJBQAMAGIiAA==.',
Fi='Filthy:BAAALgAECgkJCQAAAA==.Fiobhe:BAABLgAECn8rAAIZAAgJbhqVFwBNAgAZAAgJbhqVFwBNAgAAAA==.Fixeruper:BAABLgAECn8cAAIJAAgJswEITQCuAAAJAAgJswEITQCuAAAAAA==.',
Fl='Flaggedname:BAAALgADCgMJAwABLgAECggJFAASAEIUAA==.Flubberduck:BAAALgADCggJEAAAAA==.Fluffybeer:BAABLgAECn8gAAIQAAgJrh1tPAAPAgAQAAgJrh1tPAAPAgAAAA==.',
Fo='Fonz:BAAALgAECgYJBgABLgAECgcJGwAZAHYQAA==.Footdig:BAABLgAECn80AAIVAAkJfSMoBAB8AwAVAAkJfSMoBAB8AwAAAA==.',
Fu='Fuquan:BAAALgAECgYJCgAAAA==.',
Fw='Fwd:BAAALgADCgIJAgAAAA==.',
Ga='Gadzook:BAAALgADCggJFQAAAA==.Garthok:BAAALgADCggJCAAAAA==.Gatolun:BAAALgADCgUJBQAAAA==.',
Gi='Giline:BAAALgAECgEJAQAAAA==.Gimp:BAAALgADCgEJAQAAAA==.Ginja:BAAALgADCgIJAgAAAA==.',
Gl='Glenlizzo:BAAALgADCgYJDQABLgAECgYJFwAHAHcaAA==.Glenroyce:BAABLgAECn8XAAIHAAYJdxrqGgB2AQAHAAYJdxrqGgB2AQAAAA==.Gless:BAABLgAECn8WAAINAAgJPAZQAQDCAAANAAgJPAZQAQDCAAAAAA==.',
Go='Goodfine:BAAALgADCgcJDwAAAA==.Goss:BAAALgAECgMJAwAAAA==.Goteem:BAAALgADCggJDAAAAA==.',
Gr='Grandcross:BAAALgADCgMJAwAAAA==.Grapedrink:BAAALgAECgYJCQABLgAECgkJIwAOADEgAA==.Griimtotem:BAAALgAECgQJBAAAAA==.Groen:BAAALgAECgIJAgABLgAECgkJMQANABwVAA==.',
Gu='Gungnir:BAABLgAECn8dAAMfAAgJnRjtFwD0AQAfAAgJnRjtFwD0AQAgAAYJggfPewCrAAAAAA==.Gush:BAAALgADCgQJBAAAAA==.Guttertrash:BAAALgAECgIJAgAAAA==.',
Gw='Gwendelspear:BAAALgADCgQJBAABLgAECggJDwABAAAAAA==.',
Ha='Hae:BAAALgADCgEJAQAAAA==.Haenus:BAAALgAECgYJDAAAAA==.Haill:BAAALgAECggJDwAAAA==.Hamhock:BAABLgAECn8uAAIhAAgJmR54CwBvAgAhAAgJmR54CwBvAgABLgAECgkJIwAOADEgAA==.Hammered:BAAALgADCgUJBQABLgAECgYJFwAHAHcaAA==.Hardtobepro:BAAALgAECgcJBwAAAA==.Harleydk:BAAALgADCgUJBQAAAA==.Hawks:BAAALgADCggJCQAAAA==.',
He='Heartsong:BAAALgAECgcJBgAAAA==.',
Ho='Holycrusader:BAABLgAECn8YAAIcAAgJWBJIXQDLAQAcAAgJWBJIXQDLAQAAAA==.Hoop:BAAALgADCgUJEAAAAA==.Hornito:BAAALgAECgYJCAAAAA==.',
Ic='Icerug:BAAALgAECgYJBwABLgAFFAQJCgAVANQUAA==.',
Ih='Ihatepallys:BAAALgAECgUJCQAAAA==.',
Ii='Iikeomgikr:BAAALgADCgEJAQAAAA==.',
Il='Ildefonso:BAAALgAECgEJAQABLgAECgcJGwAZAHYQAA==.Ilduca:BAAALgADCgYJBwAAAA==.Ilidank:BAABLgAECn8hAAIaAAgJPiCYAADqAQAaAAgJPiCYAADqAQAAAA==.Ilya:BAAALgAECgUJCwABLgAECggJKQAcAHcbAA==.',
Im='Impotence:BAAALgADCgMJAwAAAA==.',
In='Indigo:BAABLgAECn9gAAMMAAkJbyFnBQBcAwAMAAkJbyFnBQBcAwAPAAYJrxtSAQAhAQAAAA==.Innax:BAAALgADCgEJAQAAAA==.Innron:BAABLgAECn8xAAMhAAkJSxHzGQCwAQAhAAkJSxHzGQCwAQAbAAIJWwMxMgA7AAAAAA==.',
Ir='Irisblue:BAAALgADCgkJDwAAAA==.',
Iy='Iyahli:BAAALgAECgUJDwAAAA==.',
Ja='Jaedia:BAAALgADCgYJCQAAAA==.Jarclian:BAACLgAFFH8NAAIFAAQJNhASZgAXAQAFAAQJNhASZgAXAQAuAAQKfz4AAgUACQnRIrsRAPACAAUACQnRIrsRAPACAAAA.Jaymonk:BAAALgAECgkJDgAAAA==.Jazmon:BAAALgAECgIJAgAAAA==.',
Je='Jezzea:BAAALgADCgkJEgAAAA==.',
Ji='Jimlaheys:BAAALgAECgYJDgAAAA==.Jinjix:BAAALgAECgEJAgAAAA==.Jitt:BAABLgAECn8XAAIaAAYJYxsDUACVAQAaAAYJYxsDUACVAQAAAA==.',
Jo='Jolike:BAAALgADCgQJBAAAAA==.Joséphine:BAAALgADCgkJEgAAAA==.',
['Jâ']='Jâten:BAABLgAECn8WAAIfAAkJxBlCDgBjAgAfAAkJxBlCDgBjAgABLgAFFAYJCgAaABgWAA==.Jâtens:BAACLgAFFH8KAAMaAAYJGBbdKgB8AQAaAAYJGBbdKgB8AQAbAAEJAgRBFQAlAAAuAAQKfyIAAhoACAlxH2IdAGQCABoACAlxH2IdAGQCAAAA.',
Ka='Kaelía:BAAALgAECgcJDwAAAA==.Kair:BAACLgAFFH8LAAIfAAMJLwfsLQCRAAAfAAMJLwfsLQCRAAAuAAQKfykAAh8ACQnUCsIwAEQBAB8ACQnUCsIwAEQBAAAA.Kairring:BAABLgAECn8jAAITAAkJ4BSVMAAZAgATAAkJ4BSVMAAZAgAAAA==.Kame:BAAALgAECgUJBQAAAA==.Kamehameha:BAABLgAECn8YAAIXAAkJlRX/CQDTAQAXAAkJlRX/CQDTAQAAAA==.Kami:BAABLgAECn80AAIfAAkJ1xOqHADJAQAfAAkJ1xOqHADJAQAAAA==.Kapslock:BAAALgAECgYJBwAAAA==.Karii:BAAALgADCgEJAQAAAA==.Karma:BAAALgADCgcJHAAAAA==.Katsicle:BAABLgAECn8fAAIFAAgJfANLyQD8AAAFAAgJfANLyQD8AAAAAA==.Kattastrophy:BAABLgAECn8VAAIKAAgJ9QU6GwDLAAAKAAgJ9QU6GwDLAAAAAA==.Katteya:BAAALgAECgYJDwAAAA==.Kattia:BAABLgAECn8oAAITAAkJkA6RTwC0AQATAAkJkA6RTwC0AQAAAA==.Kazmoru:BAAALgAECgEJAQAAAA==.',
Kh='Khalico:BAAALgADCgEJAQAAAA==.Khellendros:BAAALgADCgUJBQABLgAECgYJCgABAAAAAA==.Khir:BAAALgAECgQJBwAAAA==.',
Ki='Killinkair:BAAALgAECgYJBgAAAA==.Kinomihime:BAABLgAECn83AAIFAAkJ3w+iYQC8AQAFAAkJ3w+iYQC8AQAAAA==.Kirajoy:BAABLgAECn9aAAIKAAkJoAg5FAANAQAKAAkJoAg5FAANAQAAAA==.Kirel:BAAALgADCgEJAQAAAA==.Kithri:BAAALgADCgEJAQAAAA==.Kiymeria:BAAALgAECgYJBgAAAA==.',
Kn='Knyghtt:BAABLgAECn8jAAIOAAgJDw+mNQByAQAOAAgJDw+mNQByAQAAAA==.',
Ko='Kogwyn:BAAALgAECggJEQAAAA==.Kogy:BAAALgADCgcJBgABLgAECggJEQABAAAAAA==.',
Kr='Krakor:BAAALgADCgYJBgAAAA==.Kraviz:BAAALgAECgYJDgAAAA==.Krombopolous:BAAALgADCgkJIgABLgAECgkJNgATANsSAA==.Krystle:BAABLgAECn8wAAITAAkJHhc8LwAgAgATAAkJHhc8LwAgAgAAAA==.',
Ky='Kydormu:BAAALgADCgEJAQAAAA==.',
['Kä']='Käyfex:BAAALgAECgQJBAAAAA==.',
La='Lazarus:BAAALgAECgkJCQAAAA==.',
Le='Leftyloose:BAAALgADCgkJBAAAAA==.',
Li='Lilfonz:BAABLgAECn8bAAMZAAcJdhA2PgBMAQAZAAcJdhA2PgBMAQAcAAYJ/RgVnQBEAQAAAA==.Livik:BAABLgAECn8cAAIUAAkJzxxqAwBoAgAUAAkJzxxqAwBoAgAAAA==.',
Lo='Lockofdeath:BAAALgADCgYJBwAAAA==.Lockywolf:BAAALgAECgUJBgAAAA==.Logarth:BAAALgAECgYJDAAAAA==.Longbrew:BAAALgADCgEJAQAAAA==.Loppsang:BAAALgAECgYJEgAAAA==.Lorcan:BAABLgAECn82AAIiAAkJdhswCwA1AgAiAAkJdhswCwA1AgAAAA==.',
Lr='Lroye:BAACLgAFFH8PAAIjAAQJnBarHQAyAQAjAAQJnBarHQAyAQAuAAQKfxkAAiMABwnqHrYYANQBACMABwnqHrYYANQBAAAA.',
Ls='Lsdarko:BAAALgAECgEJAwAAAA==.',
Lu='Luckyleet:BAAALgADCgQJCwAAAA==.Lucyfer:BAABLgAECn8bAAIPAAkJOQzZAACIAQAPAAkJOQzZAACIAQABLgAECgkJKgAcAKMIAA==.Lucyferr:BAABLgAECn8ZAAIFAAgJfQVzuAAVAQAFAAgJfQVzuAAVAQABLgAECgkJKgAcAKMIAA==.Ludacritts:BAAALgAECgQJBAAAAA==.Ludicrispeed:BAAALgADCgkJFQAAAA==.Luliak:BAACLgAFFH8QAAIRAAYJPCI5BQC8AQARAAYJPCI5BQC8AQAuAAQKfyAAAhEACQnRIncEAOYCABEACQnRIncEAOYCAAAA.Lunabren:BAABLgAECn8YAAMWAAcJwwcFSwDgAAAWAAcJwwcFSwDgAAAVAAIJoQYnwgBDAAAAAA==.Lunamina:BAAALgAECgYJEgAAAA==.',
Ly='Lynvala:BAAALgADCgQJBQAAAA==.Lysdexíc:BAABLgAECn8aAAIaAAkJzhP2QQDCAQAaAAkJzhP2QQDCAQAAAA==.',
['Lì']='Lìllith:BAABLgAECn8sAAMJAAkJLB3vDQCHAgAJAAkJLB3vDQCHAgAkAAQJIwrgTgCXAAABLgAFFAIJCgAcANcbAA==.',
Ma='Majika:BAAALgADCgYJBQAAAA==.Mariophra:BAABLgAECn86AAIMAAkJ1xq6FQCdAgAMAAkJ1xq6FQCdAgAAAA==.Marvelious:BAAALgAFFAEJAQAAAA==.Mattlen:BAAALgADCgYJCAAAAA==.Maximumswag:BAAALgADCgkJLQABLgAECgkJNgATANsSAA==.Maxmugruith:BAAALgADCgQJBwAAAA==.Maxtheb:BAAALgADCgYJBgAAAA==.',
Mc='Mcnastyqt:BAAALgAECgQJBAAAAA==.',
Me='Meatshiéld:BAAALgAECgYJCgAAAA==.',
Mi='Midopamos:BAAALgADCgEJAQAAAA==.Mikki:BAAALgAECgcJDwAAAA==.Milber:BAAALgADCgUJBQAAAA==.Missconduct:BAAALgADCgYJBgAAAA==.Misstorgo:BAABLgAECn8iAAINAAgJXR/5CABnAgANAAgJXR/5CABnAgAAAA==.',
Mo='Monfro:BAAALgAECggJEAAAAA==.Moogatoo:BAAALgAECgYJCAABLgAECgcJFwAQAMsZAA==.Moonbane:BAABLgAECn8sAAIKAAgJUCDOAwBQAgAKAAgJUCDOAwBQAgAAAA==.Moonfanda:BAAALgADCgIJAgAAAA==.Moonmist:BAAALgADCgEJAQABLgAECggJDwABAAAAAA==.Moor:BAAALgAECgYJDAAAAA==.',
Mu='Mumferd:BAAALgADCgQJBAAAAA==.',
My='Myaquean:BAAALgADCgkJFAAAAA==.Mystogan:BAAALgAECgcJEgAAAA==.Myth:BAAALgAECggJDAAAAA==.Mythelea:BAAALgAECgMJAwAAAA==.',
Na='Nakeefa:BAABLgAECn8nAAMCAAkJdBRwMwALAgACAAkJdBRwMwALAgAKAAEJAAA9cgAzAAAAAA==.Natsuu:BAABLgAECn8pAAMTAAkJOBteRwDMAQATAAgJihxeRwDMAQARAAQJxhG7NAAMAQAAAA==.Naturewolf:BAABLgAECn8eAAIDAAgJXRbpFAB2AQADAAgJXRbpFAB2AQAAAA==.',
Ne='Nefertiti:BAAALgAECgcJCQAAAA==.Nekona:BAABLgAECn8VAAQCAAgJTwuEiQBGAQACAAgJTwuEiQBGAQAKAAIJCgmuWwBcAAAeAAEJlwWVNAAzAAAAAA==.Neron:BAACLgAFFH8KAAIcAAIJ1xvfCQCWAAAcAAIJ1xvfCQCWAAAuAAQKfzwAAhwACQlYIBYcAJwCABwACQlYIBYcAJwCAAAA.Nethertusk:BAABLgAECn8uAAMCAAkJTBmkMwAKAgACAAkJTBmkMwAKAgAKAAIJYQP2WQBhAAAAAA==.',
Nh='Nhancecntrl:BAACLgAFFH8FAAILAAMJxQv+DwDGAAALAAMJxQv+DwDGAAAuAAQKfyYAAgsACQnRGkUFAJECAAsACQnRGkUFAJECAAAA.',
Ni='Niany:BAAALgAECgYJDgAAAA==.Nightbréaker:BAAALgADCgcJFQAAAA==.Nilospite:BAABLgAECn8yAAINAAgJcB6UCQBaAgANAAgJcB6UCQBaAgABLgAFFAcJHgAIAHIVAA==.Nimposter:BAABLgAECn8rAAIQAAkJNRfHOAAcAgAQAAkJNRfHOAAcAgAAAA==.',
Nj='Njoror:BAAALgADCgQJBAAAAA==.',
No='Noodle:BAAALgADCgEJAQAAAA==.Norky:BAAALgAECgUJBQABLgAFFAQJEwAMAHEUAA==.Nottapally:BAAALgAECgcJEgABLgAECggJFAASAEIUAA==.',
Nu='Nullea:BAAALgAECgYJCAAAAA==.',
Ny='Nyxthos:BAAALgADCggJCAAAAA==.',
Ob='Obizi:BAAALgAECgEJAQAAAA==.',
Oc='Ocatarineta:BAAALgADCgIJAgAAAA==.',
Od='Odine:BAAALgAECgEJAgAAAA==.Odito:BAABLgAECn8VAAIWAAYJpRdrMABbAQAWAAYJpRdrMABbAQAAAA==.',
Om='Omegalich:BAAALgAECgEJAQAAAA==.',
Oo='Oopslol:BAAALgAECgYJDAAAAA==.',
Os='Osdavalmarro:BAAALgADCgYJGQAAAA==.',
Ot='Othaerion:BAABLgAECn8YAAIZAAkJbw+pKgC6AQAZAAkJbw+pKgC6AQAAAA==.',
Ou='Outerlimits:BAABLgAECn8uAAIlAAgJMRjRCwC7AQAlAAgJMRjRCwC7AQAAAA==.',
Pa='Paindore:BAAALgAECgQJBwAAAA==.Pamboo:BAABLgAECn8xAAIZAAkJzg/IJQDaAQAZAAkJzg/IJQDaAQAAAA==.',
Pe='Pearle:BAABLgAECn8vAAIIAAkJQx4cDABLAgAIAAkJQx4cDABLAgAAAA==.',
Ph='Phyg:BAAALgAECgQJBQABLgAECgUJBwABAAAAAA==.',
Po='Pokimane:BAAALgADCggJDwAAAA==.Polyasap:BAAALgADCgQJBAAAAA==.',
Pr='Priestiô:BAAALgAECgEJAQAAAA==.Pringo:BAAALgAFFAIJAgAAAA==.Proximal:BAAALgAECgcJBwAAAA==.',
Pu='Pukka:BAAALgADCgcJEQABLgAECgkJJAAJADUaAA==.Punk:BAAALgAFFAEJAQAAAA==.',
Qa='Qahnaarin:BAAALgAFFAEJAQAAAA==.',
Ra='Rajax:BAABLgAECn8WAAIOAAkJKhFDIADuAQAOAAkJKhFDIADuAQAAAA==.Ralphthedh:BAAALgAECgkJDwAAAA==.Ramindizzle:BAABLgAECn86AAIXAAkJcBYUCQDnAQAXAAkJcBYUCQDnAQAAAA==.Rangewolf:BAAALgADCgcJDgAAAA==.',
Re='Refreshing:BAAALgAECgIJAgAAAA==.Rejuvasap:BAABLgAECn8aAAQWAAgJMBpWKQC1AQAWAAgJMBpWKQC1AQAVAAUJ6R38OwCkAQADAAMJqhevNQCHAAAAAA==.Rekki:BAAALgADCgEJAQAAAA==.Reliri:BAAALgADCgMJAwAAAA==.Remlin:BAAALgADCgcJCAAAAA==.Retastic:BAAALgAECgcJBwAAAA==.Retsall:BAAALgADCgUJBQAAAA==.Reâper:BAAALgAECgYJCgAAAA==.',
Ri='Rikal:BAAALgADCgYJEAAAAA==.',
Ro='Rook:BAABLgAECn82AAIXAAkJ8A1jDgB4AQAXAAkJ8A1jDgB4AQAAAA==.Roye:BAACLgAFFH8WAAIcAAYJqxSeJgBvAQAcAAYJqxSeJgBvAQAuAAQKfx4AAhwACQl1HbYaAMkCABwACQl1HbYaAMkCAAAA.',
Ru='Ruffiyo:BAABLgAECn8wAAMaAAkJtRSvPwDKAQAaAAkJrxOvPwDKAQAhAAgJ3Q+LLQBfAQAAAA==.Rugonk:BAAALgAFFAQJBAABLgAFFAQJCgAVANQUAA==.Rugrahfreaky:BAACLgAFFH8KAAIVAAQJ1BRNLQAAAQAVAAQJ1BRNLQAAAQAuAAQKfzkAAhUACQl6IVMFAGMDABUACQl6IVMFAGMDAAAA.Rugrahh:BAABLgAECn8pAAMXAAkJux5MDwDGAgAXAAkJux5MDwDGAgARAAMJaQ+PQwC0AAABLgAFFAQJCgAVANQUAA==.Rugrahx:BAABLgAFFH8FAAIbAAMJ4Rl6BwDhAAAbAAMJ4Rl6BwDhAAABLgAFFAQJCgAVANQUAA==.Ruthen:BAAALgAECgYJCwAAAA==.Ruìn:BAAALgAECgcJCQAAAA==.',
Sa='Sabermore:BAABLgAECn8cAAIcAAgJlxcPSADuAQAcAAgJlxcPSADuAQAAAA==.Sabina:BAABLgAECn83AAIPAAkJgAueOQBQAQAPAAkJgAueOQBQAQAAAA==.Sadako:BAAALgAECgYJCAABLgAECgkJKgAcAKMIAA==.Sadness:BAAALgAECgYJEgAAAA==.Sadorick:BAAALgADCgkJLwAAAA==.Safira:BAAALgAECgQJBgABLgAFFAIJCgAcANcbAA==.Sageguy:BAABLgAECn8WAAIFAAYJVwTjCQBqAAAFAAYJVwTjCQBqAAAAAA==.Samerle:BAAALgADCgEJAQAAAA==.Sango:BAABLgAECn9DAAMhAAkJcBlZDgBAAgAhAAkJcBlZDgBAAgAaAAQJ2gKPwQB8AAAAAA==.Saucewalker:BAABLgAFFH8TAAIQAAUJkBszRwBlAQAQAAUJkBszRwBlAQAAAA==.Savagelykill:BAABLgAECn8YAAIIAAYJvwrGNgC7AAAIAAYJvwrGNgC7AAAAAA==.',
Sc='Scotch:BAABLgAECn8zAAMcAAkJYRt8LgBHAgAcAAkJYRt8LgBHAgASAAUJNxXjIwD2AAAAAA==.Scotchnwater:BAABLgAECn8eAAMmAAgJmA8WEwCXAQAmAAgJmA8WEwCXAQAnAAMJIwcQGwB0AAAAAA==.Scrubyheals:BAAALgADCgQJBwABLgAECggJFAASAEIUAA==.',
Se='Sendio:BAAALgAECgQJBAAAAA==.Senji:BAAALgADCgQJBAAAAA==.',
Sg='Sgtpayne:BAAALgADCgIJAgAAAA==.',
Sh='Shadowcrwlr:BAAALgAECgQJCgAAAA==.Shadowlock:BAAALgAECggJEwAAAA==.Shadowmane:BAAALgADCgQJBAAAAA==.Shaeixia:BAAALgADCggJCgAAAA==.Shamangroo:BAAALgAECgEJAQABLgAECgYJFgANADsWAA==.Shamanio:BAAALgAECgEJAgAAAA==.Shamichangas:BAAALgAECgEJAQAAAA==.Shammying:BAAALgAECgUJCwAAAA==.Shamsham:BAAALgADCgIJAgAAAA==.Sharaaz:BAAALgAECgMJBgAAAA==.Shivalry:BAAALgADCgkJCwAAAA==.Shmiggy:BAAALgAECgQJCgAAAA==.',
Si='Silverytwo:BAAALgAECgYJCQAAAA==.Silverywine:BAAALgADCgkJCQAAAA==.Silverywolfe:BAAALgAECgQJCQAAAA==.Simony:BAABLgAECn8qAAIcAAkJowhrAgBFAQAcAAkJowhrAgBFAQAAAA==.Sinton:BAAALgADCgIJAgAAAA==.',
Sk='Skorpyoh:BAAALgADCgYJBgAAAA==.Skovak:BAABLgAECn8VAAISAAkJkA70FQB2AQASAAkJkA70FQB2AQAAAA==.Skybright:BAAALgAECggJCwAAAA==.',
So='Soggy:BAAALgAECgcJBwAAAA==.Sorayae:BAABLgAECn8kAAIJAAkJNRr1EwA/AgAJAAkJNRr1EwA/AgAAAA==.',
Sp='Specialk:BAAALgAECgYJDQAAAA==.Spinnykat:BAAALgAECgMJBgAAAA==.Splooshh:BAAALgAECgkJDAABLgAECgkJMAAaALUUAA==.',
St='Starmist:BAAALgADCgMJAwAAAA==.Stinkfoot:BAAALgAECgUJCAAAAA==.Stoo:BAAALgADCgkJHAAAAA==.Stormkissed:BAABLgAECn8dAAMMAAgJlAwIUAByAQAMAAgJlAwIUAByAQAPAAEJQALjwQAcAAAAAA==.Stormweaver:BAAALgAECgUJBQAAAA==.',
Su='Sunil:BAABLgAECn9MAAIJAAkJxx7lBQAZAwAJAAkJxx7lBQAZAwAAAA==.Suviqhabo:BAAALgAECggJDwAAAA==.',
Sv='Svala:BAAALgADCgYJBgAAAA==.',
Sy='Syclic:BAAALgAECgUJBQABLgAECgkJMwANABAmAA==.Syclone:BAABLgAECn8zAAINAAkJECbHAABoAwANAAkJECbHAABoAwAAAA==.Syladen:BAAALgAECgYJEgAAAA==.Syleste:BAAALgAECgQJBAABLgAECgkJMwANABAmAA==.Syvi:BAAALgAECgYJCQABLgAECggJEQABAAAAAA==.',
Ta='Tahwe:BAAALgADCgUJBQAAAA==.Tattianna:BAAALgAECgYJEQAAAA==.Tavendar:BAAALgAECgcJDQABLgAFFAQJEwAMAHEUAA==.Tavil:BAAALgADCgMJAwAAAA==.Taírn:BAAALgAECgYJEAAAAA==.',
Te='Techie:BAABLgAECn8gAAMgAAkJTRKfJAD9AQAgAAkJTRKfJAD9AQAoAAUJpASfYgC4AAAAAA==.Teeser:BAAALgAECgYJEQAAAA==.Terradactyl:BAAALgADCgMJAwAAAA==.',
Th='Thesis:BAAALgADCgkJCQAAAA==.Thunderslate:BAABLgAECn8UAAISAAgJQhQbEwCYAQASAAgJQhQbEwCYAQAAAA==.Thôrin:BAAALgADCgkJFQAAAA==.',
Ti='Tigerlillee:BAAALgADCgcJDQAAAA==.Tigreth:BAABLgAECn82AAMcAAkJ1hTdUQDTAQAcAAkJ1hTdUQDTAQASAAIJlhSvNgBoAAAAAA==.Timotheus:BAAALgAECgUJDAAAAA==.',
To='Tonï:BAAALgADCggJCAAAAA==.Totemzasap:BAAALgAECgEJAgAAAA==.',
Tr='Tragik:BAABLgAECn8mAAILAAkJQA5wEACsAQALAAkJQA5wEACsAQAAAA==.',
Tt='Ttrouble:BAAALgADCgUJBQAAAA==.',
Tu='Tuugadark:BAABLgAECn81AAICAAkJRx22JABMAgACAAkJRx22JABMAgAAAA==.Tuugashox:BAAALgAECgUJBQAAAA==.',
Ul='Ulyaoth:BAABLgAECn83AAICAAgJjQsocQBYAQACAAgJjQsocQBYAQAAAA==.',
Un='Unc:BAAALgAECgEJAQAAAA==.Unnerfable:BAAALgAECgYJCAAAAA==.',
Uw='Uwa:BAAALgADCgMJAwAAAA==.',
Uy='Uy:BAAALgAECgYJDwAAAA==.',
Va='Valakha:BAAALgAECgQJDwAAAA==.Valkyrie:BAAALgAECgQJBgAAAA==.',
Ve='Vedros:BAAALgADCgkJDgAAAA==.Vermouth:BAAALgAECgYJDAAAAA==.Vespertilia:BAAALgAECgIJAgAAAA==.',
Vi='Viktoros:BAAALgAECgIJAgAAAA==.Violetra:BAAALgADCgMJAwAAAA==.',
Vo='Vorcan:BAAALgADCgYJBgAAAA==.Vorukh:BAABLgAECn8fAAQDAAkJmxHBDgDIAQADAAkJmxHBDgDIAQAVAAMJ9gxOmACBAAAHAAEJyw/zgAAhAAAAAA==.',
Vr='Vrave:BAAALgADCgQJBQAAAA==.',
Vy='Vyhlet:BAAALgAECggJEgABLgAECgkJYAAMAG8hAA==.',
Wa='Warlockgroo:BAAALgADCgQJBAABLgAECgYJFgANADsWAA==.Warriorgroo:BAABLgAECn8WAAINAAYJOxZYJgD/AAANAAYJOxZYJgD/AAAAAA==.',
We='Wendish:BAAALgAECgEJCgAAAA==.Wertyda:BAABLgAECn8aAAIZAAkJzhT1JgDSAQAZAAkJzhT1JgDSAQAAAA==.Wetnwild:BAAALgAECgUJBQAAAA==.',
Wh='Whácker:BAABLgAECn8UAAMiAAgJOwpYEgB8AQAiAAgJOwpYEgB8AQANAAMJrAguOQCBAAABLgAECgYJEAABAAAAAA==.',
Wi='Wickdlovly:BAAALgADCgEJAQABLgAECggJDwABAAAAAA==.Wickedslicks:BAABLgAECn87AAIWAAkJdCA9CADQAgAWAAkJdCA9CADQAgAAAA==.Wildthangg:BAAALgAECgIJAgAAAA==.',
Wo='Wooddchipper:BAAALgADCgYJBgAAAA==.',
Wr='Wreckshop:BAABLgAECn8ZAAIQAAkJ8xruSQDkAQAQAAkJ8xruSQDkAQAAAA==.',
Wt='Wtfoxtrot:BAAALgADCgkJDAAAAA==.',
Xe='Xenøcide:BAAALgAECgcJEwAAAA==.',
Xi='Xiatus:BAAALgAECgUJBQABLgAECgkJKgAQAOYhAA==.',
Xx='Xxlockz:BAABLgAECn8lAAMCAAkJWREvZwBvAQACAAgJ8A4vZwBvAQAKAAMJGRFIIQCkAAAAAA==.Xxpallyz:BAAALgAECggJCwABLgAECgkJJQACAFkRAA==.',
Yi='Yinger:BAAALgADCgcJEAAAAA==.Yinglang:BAAALgADCgEJAQAAAA==.Yingling:BAABLgAECn8rAAIQAAkJ6RmMQQD+AQAQAAkJ6RmMQQD+AQAAAA==.',
Yo='Yohh:BAABLgAECn8fAAIMAAkJ3ReyAAD3AQAMAAkJ3ReyAAD3AQAAAA==.Yorshka:BAAALgAECgMJAwABLgAECgkJKgAQAOYhAA==.',
Yu='Yukara:BAAALgAECgEJAQAAAA==.Yulay:BAAALgADCgkJBwAAAA==.Yuriko:BAABLgAECn83AAIgAAkJ1hONIwAEAgAgAAkJ1hONIwAEAgAAAA==.',
Za='Zaidan:BAAALgAECgYJEwAAAA==.Zanpaktu:BAAALgAECgYJEwAAAA==.Zaraha:BAAALgADCgEJAQAAAA==.Zata:BAAALgAECgUJBwAAAA==.',
Ze='Zendous:BAAALgAECgcJBwAAAA==.Zeref:BAAALgAECgYJEgAAAA==.Zeur:BAAALgAECgEJAQAAAA==.Zevgrip:BAAALgAECgQJBQAAAA==.',
Zh='Zhia:BAAALgAECgQJBQAAAA==.',
Zi='Zippitydooda:BAAALgADCgQJBAABLgAECggJDwABAAAAAA==.',
Zo='Zodiacc:BAABLgAECn84AAIHAAkJQxzvBgCJAgAHAAkJQxzvBgCJAgAAAA==.Zornen:BAAALgAECgcJCwAAAA==.Zornhealer:BAAALgAECgUJBgABLgAECgYJEwABAAAAAA==.',
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
