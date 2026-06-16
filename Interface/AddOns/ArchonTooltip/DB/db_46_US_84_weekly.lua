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
local provider = {region='US',realm='EchoIsles',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aaelless:BAAALgAECgMJBAAAAA==.Aardz:BAAALgAECgQJBAAAAA==.',
Ab='Abeblinkin:BAAALgADCgkJDgAAAA==.Abrakadavar:BAAALgAECgQJBQAAAA==.Abräxis:BAAALgADCgkJCQABLgAECgMJAwABAAAAAA==.',
Ac='Ackspez:BAAALgADCgYJBgAAAA==.',
Ae='Aeless:BAABLgAECn8dAAICAAkJKyIoCwD0AgACAAkJKyIoCwD0AgAAAA==.Aelless:BAAALgAECgYJCAAAAA==.Aenest:BAAALgADCggJCAAAAA==.',
Ai='Aithinne:BAAALgAECgYJCwAAAA==.',
Ak='Akanah:BAAALgADCgcJBwAAAA==.',
Al='Alfira:BAAALgAECgYJEwAAAA==.Alghul:BAAALgAECgMJBAABLgAECgYJEwABAAAAAA==.',
Am='Amalthea:BAAALgADCgkJEAAAAA==.Amoredis:BAAALgADCgYJDQAAAA==.Amorlorin:BAAALgADCggJEwAAAA==.',
An='Anklbiterkat:BAAALgADCgQJBAAAAA==.Anume:BAAALgADCgkJFQAAAA==.',
Ar='Aragan:BAAALgAECgYJDQAAAA==.Aravis:BAABLgAECn8cAAIDAAgJewkhHgASAQADAAgJewkhHgASAQAAAA==.Arese:BAABLgAECn8fAAQEAAYJTiZ/AwA0AgAEAAUJTiZ/AwA0AgAFAAMJlyTzEgHYAAAGAAEJAABTDABpAAAAAA==.Argopol:BAABLgAECn8iAAIHAAgJhyEjBgCbAgAHAAgJhyEjBgCbAgABLgAECgkJKQAIAEMeAA==.Aron:BAAALgADCgMJAgAAAA==.',
As='Ashandra:BAAALgADCgkJDwAAAA==.Ashlyssra:BAABLgAECn8fAAIJAAkJYh39CADXAgAJAAkJYh39CADXAgAAAA==.Asphonix:BAAALgADCgEJAQAAAA==.',
Aw='Awsomesause:BAAALgAECgQJBgAAAA==.',
Az='Azuri:BAAALgAECgQJBQAAAA==.Azzif:BAABLgAECn8cAAIKAAYJAwOQJwB1AAAKAAYJAwOQJwB1AAAAAA==.Azzraell:BAAALgADCgEJAQAAAA==.',
Ba='Babaorumm:BAAALgAECgQJBAAAAA==.Babasha:BAACLgAFFH8JAAILAAQJ6QtlCwAIAQALAAQJ6QtlCwAIAQAuAAQKfxsAAwsABgmSH/UPAK4BAAsABgmSH/UPAK4BAAwABgnADcJPAEUBAAAA.Babybluz:BAABLgAECn8jAAIFAAgJ6gi/pAAwAQAFAAgJ6gi/pAAwAQAAAA==.Baconloaf:BAAALgAECgUJCQAAAA==.Baifeng:BAAALgADCgkJFgAAAA==.Baldilocks:BAAALgADCgQJDAAAAA==.Barlas:BAAALgAECgEJAQAAAA==.Bat:BAAALgADCgEJAQAAAA==.',
Be='Beauriley:BAABLgAECn8xAAMNAAkJHBVgEwC1AQANAAkJHBVgEwC1AQAOAAEJnA7UnQA2AAAAAA==.Behomethan:BAABLgAECn8mAAMMAAkJZBtJKgDlAQAMAAgJOBpJKgDlAQAPAAgJABQZMgBxAQAAAA==.Beyonsláy:BAAALgAECgYJEQAAAA==.',
Bh='Bhipbookie:BAAALgAECgEJBAAAAA==.',
Bi='Billbetaray:BAAALgADCgMJAwAAAA==.',
Bl='Bluerift:BAAALgADCgEJAQAAAA==.Blux:BAAALgAECgEJAQAAAA==.',
Bo='Bobbyb:BAABLgAECn8XAAIQAAcJyxkkVgDAAQAQAAcJyxkkVgDAAQAAAA==.Bolton:BAAALgADCgIJAgAAAA==.Bombchele:BAAALgAECgYJBgABLgAECgkJGQAQAPMaAA==.Boneulngtime:BAAALgADCgUJCgAAAA==.Boon:BAAALgAECgIJAgAAAA==.Bowlofwrong:BAAALgAECgYJBwAAAA==.',
Br='Bratticusrex:BAABLgAECn8jAAIOAAgJEAnKPwBEAQAOAAgJEAnKPwBEAQAAAA==.Brazier:BAAALgAECgQJBAAAAA==.Bresowar:BAAALgAECggJDwAAAA==.',
Bu='Bunnylicious:BAABLgAECn9DAAIMAAkJ5yWcAADaAwAMAAkJ5yWcAADaAwAAAA==.Bunnymedic:BAABLgAECn8WAAIJAAYJIh2vHQDTAQAJAAYJIh2vHQDTAQABLgAECgkJQwAMAOclAA==.',
Ca='Caebrylla:BAABLgAECn85AAIRAAkJfw6qFAD/AQARAAkJfw6qFAD/AQAAAA==.Calistie:BAAALgAECgIJAgAAAA==.Camigatu:BAAALgADCgQJBAAAAA==.Camil:BAABLgAECn8VAAISAAcJIwy4IwDzAAASAAcJIwy4IwDzAAABLgAFFAMJCgATAHsIAA==.Cang:BAAALgAECgIJAgAAAA==.Capulin:BAABLgAECn8kAAIOAAkJsBaQHQAAAgAOAAkJsBaQHQAAAgAAAA==.Catdurid:BAAALgADCgYJBgAAAA==.',
Ce='Cecilbrown:BAAALgADCgcJBgAAAA==.Cecimorte:BAABLgAECn83AAIIAAkJehlQDQAzAgAIAAkJehlQDQAzAgAAAA==.Cephalopod:BAABLgAECn8UAAIUAAgJ1RXEAwD5AQAUAAgJ1RXEAwD5AQAAAA==.',
Ch='Chargeasap:BAAALgAECgMJAwAAAA==.Charttopper:BAAALgAECgYJCQABLgAECggJFAASAEIUAA==.Chibby:BAAALgADCgMJAwAAAA==.Chimichanga:BAAALgAECgcJDAABLgAECggJFAASAEIUAA==.Chonker:BAABLgAECn84AAMVAAkJdSBPBwBAAwAVAAkJdSBPBwBAAwAWAAcJVwxFOgAlAQAAAA==.Chorelock:BAAALgADCgEJAQABLgAECggJFAASAEIUAA==.Chronormu:BAAALgAECgMJAwAAAA==.Chuckforrest:BAAALgAECgQJBAAAAA==.Chultis:BAABLgAECn8bAAQDAAgJuhTUEgCJAQADAAgJuhTUEgCJAQAWAAEJ2wH5jgAeAAAVAAEJAgLF6QAbAAAAAA==.',
Ci='Cihato:BAABLgAECn83AAIHAAkJIxshCQBVAgAHAAkJIxshCQBVAgAAAA==.',
Cl='Claxious:BAABLgAECn8iAAIXAAkJlRl7BgAoAgAXAAkJlRl7BgAoAgAAAA==.Claye:BAACLgAFFH8TAAIMAAQJcRTeNgD/AAAMAAQJcRTeNgD/AAAuAAQKfyoAAgwACQnPHCoRAMICAAwACQnPHCoRAMICAAAA.',
Co='Coldshoulder:BAABLgAECn83AAMFAAkJwx6NGgC5AgAFAAkJwx6NGgC5AgAGAAQJaxM/CwC3AAAAAA==.Corelas:BAABLgAECn8qAAIFAAgJsAvDhQBoAQAFAAgJsAvDhQBoAQAAAA==.Corfellyn:BAAALgAECggJBAAAAA==.Couchdad:BAAALgAECgYJEwAAAA==.',
Cr='Crazymadman:BAABLgAECn8XAAIYAAYJ3wPIGACnAAAYAAYJ3wPIGACnAAAAAA==.Crushingblow:BAAALgAECgkJAwAAAA==.',
Cy='Cyon:BAAALgADCgEJAQAAAA==.',
Da='Daalaria:BAAALgADCgEJAQAAAA==.Darkone:BAAALgAECgEJAQAAAA==.Dawnson:BAABLgAECn8oAAIZAAkJbCBaBQA8AwAZAAkJbCBaBQA8AwAAAA==.',
De='Deadzexcs:BAABLgAECn8WAAIYAAYJ1QqJEgD6AAAYAAYJ1QqJEgD6AAAAAA==.Deathsnear:BAAALgAECgEJAQAAAA==.Demogless:BAABLgAECn8zAAMaAAgJWw1tcAA+AQAaAAgJjgttcAA+AQAbAAYJ9gtjGQDPAAAAAA==.Desyrel:BAAALgAECgYJBgABLgAECgkJIQAcANIHAA==.Devyn:BAAALgADCgUJBQAAAA==.',
Dh='Dharknight:BAAALgAECgEJAQAAAA==.',
Di='Didimissfire:BAEBLgAECn87AAITAAkJlxRKNwD8AQATAAkJlxRKNwD8AQAAAA==.',
Do='Donaghy:BAAALgAECgEJAQAAAA==.Dooms:BAAALgADCgcJBwAAAA==.',
Dp='Dpsmaster:BAABLgAECn8eAAIWAAcJ5AVmUQDDAAAWAAcJ5AVmUQDDAAAAAA==.',
Dr='Dranalis:BAAALgAECggJDwAAAA==.Drdrake:BAAALgADCgcJFAAAAA==.Dredlok:BAAALgAECgQJBwAAAA==.Drufiyo:BAAALgAECgUJBQABLgAECgkJMAAaALUUAA==.',
Du='Dumonster:BAABLgAECn8ZAAIOAAYJyAWCaAC7AAAOAAYJyAWCaAC7AAAAAA==.',
['Dø']='Døll:BAAALgADCgYJBgAAAA==.',
Ea='Eamishal:BAAALgADCgEJAQAAAA==.',
Ei='Eightace:BAAALgAECgQJBgAAAA==.Eirenne:BAAALgAECgYJBwAAAA==.',
Ek='Ekaru:BAAALgADCgEJAQAAAA==.',
El='Elethryia:BAAALgAECgcJDQAAAA==.Elev:BAAALgAECgYJDAAAAA==.Elindril:BAAALgAECgYJEwAAAA==.',
En='Enoth:BAAALgAECggJEQAAAA==.',
Eo='Eowynn:BAACLgAFFH8FAAIMAAIJYiLRRwDHAAAMAAIJYiLRRwDHAAAuAAQKfyYAAgwACQnuH40IACUDAAwACQnuH40IACUDAAAA.',
Er='Erewhon:BAAALgADCgkJCQAAAA==.',
Es='Estella:BAABLgAECn8hAAIFAAYJ7g2QxAD/AAAFAAYJ7g2QxAD/AAAAAA==.',
Ev='Eventhorizon:BAAALgAECgkJBgAAAA==.Evielli:BAAALgADCgUJBQAAAA==.',
Fa='Faeriefire:BAAALgADCggJDQAAAA==.Fanna:BAAALgADCgMJAwAAAA==.Fatbox:BAABLgAECn8jAAIOAAkJMSB0KgCsAQAOAAkJMSB0KgCsAQAAAA==.Faythh:BAABLgAECn8xAAMJAAkJfiGYBwDyAgAJAAkJfiGYBwDyAgAdAAEJVhvrbABMAAAAAA==.',
Fe='Fearblade:BAABLgAECn8VAAIaAAUJnA5RqwDLAAAaAAUJnA5RqwDLAAAAAA==.Fedoran:BAABLgAECn8iAAQDAAkJRB+nCABTAgADAAcJyyGnCABTAgAVAAcJbREpQwCBAQAWAAYJnBxYTgDwAAAAAA==.Felasap:BAAALgAECgcJCAAAAA==.Fenastic:BAABLgAECn8nAAMCAAkJIgf2dwBIAQACAAkJqAb2dwBIAQAeAAMJEAYsHACRAAAAAA==.Fenrisúlfur:BAAALgAECgUJDQAAAA==.Feyrah:BAAALgAECggJCwABLgAFFAIJBQAMAGIiAA==.',
Fi='Filthy:BAAALgAECgkJCQAAAA==.Fiobhe:BAABLgAECn8oAAIZAAgJbho2FwBOAgAZAAgJbho2FwBOAgAAAA==.Fixeruper:BAABLgAECn8cAAIJAAgJswH5SwCuAAAJAAgJswH5SwCuAAAAAA==.',
Fl='Flaggedname:BAAALgADCgMJAwABLgAECggJFAASAEIUAA==.Flubberduck:BAAALgADCggJEAAAAA==.Fluffybeer:BAABLgAECn8gAAIQAAgJrh2WOwAQAgAQAAgJrh2WOwAQAgAAAA==.',
Fo='Fonz:BAAALgAECgYJBgABLgAECgcJGgAZAHYQAA==.Footdig:BAABLgAECn8zAAIVAAkJfSMCBAB9AwAVAAkJfSMCBAB9AwAAAA==.',
Fu='Fuquan:BAAALgAECgYJCgAAAA==.',
Fw='Fwd:BAAALgADCgIJAgAAAA==.',
Ga='Gadzook:BAAALgADCggJFQAAAA==.Garthok:BAAALgADCggJCAAAAA==.Gatolun:BAAALgADCgUJBQAAAA==.',
Gi='Giline:BAAALgAECgEJAQAAAA==.Gimp:BAAALgADCgEJAQAAAA==.Ginja:BAAALgADCgIJAgAAAA==.',
Gl='Glenlizzo:BAAALgADCgYJDQABLgAECgYJFwAHAHcaAA==.Glenroyce:BAABLgAECn8XAAIHAAYJdxpDGgB2AQAHAAYJdxpDGgB2AQAAAA==.Gless:BAAALgAECgcJEAAAAA==.',
Go='Goodfine:BAAALgADCgcJDwAAAA==.Goss:BAAALgAECgMJAwAAAA==.Goteem:BAAALgADCggJDAAAAA==.',
Gr='Grandcross:BAAALgADCgMJAwAAAA==.Grapedrink:BAAALgAECgYJBgABLgAECgkJIwAOADEgAA==.Griimtotem:BAAALgAECgQJBAAAAA==.Groen:BAAALgAECgIJAgABLgAECgkJMQANABwVAA==.',
Gu='Gungnir:BAABLgAECn8dAAMfAAgJnRh/FwD0AQAfAAgJnRh/FwD0AQAgAAYJggf7dwCrAAAAAA==.Gush:BAAALgADCgQJBAAAAA==.Guttertrash:BAAALgAECgIJAgAAAA==.',
Ha='Hae:BAAALgADCgEJAQAAAA==.Haenus:BAAALgAECgYJBgAAAA==.Haill:BAAALgAECggJDwAAAA==.Hamhock:BAABLgAECn8pAAIhAAgJmR4vCwBxAgAhAAgJmR4vCwBxAgABLgAECgkJIwAOADEgAA==.Hammered:BAAALgADCgUJBQABLgAECgYJFwAHAHcaAA==.Hardtobepro:BAAALgAECgcJBwAAAA==.Harleydk:BAAALgADCgUJBQAAAA==.Hawks:BAAALgADCggJCQAAAA==.',
He='Heartsong:BAAALgAECgcJBgAAAA==.',
Ho='Holycrusader:BAABLgAECn8YAAIcAAgJWBJIXQDLAQAcAAgJWBJIXQDLAQAAAA==.Hoop:BAAALgADCgUJEAAAAA==.Hornito:BAAALgAECgYJCAAAAA==.',
Ic='Icerug:BAAALgAECgYJBwABLgAFFAQJCgAVANQUAA==.',
Ih='Ihatepallys:BAAALgAECgUJCQAAAA==.',
Ii='Iikeomgikr:BAAALgADCgEJAQAAAA==.',
Il='Ildefonso:BAAALgAECgEJAQABLgAECgcJGgAZAHYQAA==.Ilduca:BAAALgADCgYJBwAAAA==.Ilidank:BAABLgAECn8bAAIaAAgJOx0EHwBYAgAaAAgJOx0EHwBYAgAAAA==.Ilya:BAAALgAECgUJCwABLgAECggJKQAcAHcbAA==.',
Im='Impotence:BAAALgADCgMJAwAAAA==.',
In='Indigo:BAABLgAECn9XAAMMAAkJbyE0BQBdAwAMAAkJbyE0BQBdAwAPAAYJmxo2LgCGAQAAAA==.Innax:BAAALgADCgEJAQAAAA==.Innron:BAABLgAECn8xAAMhAAkJSxFjGQCyAQAhAAkJSxFjGQCyAQAbAAIJWwNLMQA7AAAAAA==.',
Ir='Irisblue:BAAALgADCgkJDwAAAA==.',
Iy='Iyahli:BAAALgAECgUJDwAAAA==.',
Ja='Jaedia:BAAALgADCgYJCQAAAA==.Jarclian:BAACLgAFFH8NAAIFAAQJNhBDYwAmAQAFAAQJNhBDYwAmAQAuAAQKfz4AAgUACQnRIkARAPECAAUACQnRIkARAPECAAAA.Jaymonk:BAAALgAECgkJDgAAAA==.Jazmon:BAAALgAECgIJAgAAAA==.',
Je='Jezzea:BAAALgADCgkJEgAAAA==.',
Ji='Jimlaheys:BAAALgAECgYJDgAAAA==.Jinjix:BAAALgAECgEJAQAAAA==.Jitt:BAABLgAECn8XAAIaAAYJYxvwTgCVAQAaAAYJYxvwTgCVAQAAAA==.',
Jo='Jolike:BAAALgADCgQJBAAAAA==.Joséphine:BAAALgADCgkJCQAAAA==.',
['Jâ']='Jâten:BAABLgAECn8WAAIfAAkJxBkEDgBkAgAfAAkJxBkEDgBkAgABLgAFFAYJCgAaABgWAA==.Jâtens:BAACLgAFFH8KAAMaAAYJGBaGKAB9AQAaAAYJGBaGKAB9AQAbAAEJAgR1FAAlAAAuAAQKfyIAAhoACAlxH9kcAGQCABoACAlxH9kcAGQCAAAA.',
Ka='Kaelía:BAAALgAECgcJDQAAAA==.Kair:BAACLgAFFH8LAAIfAAMJLwduLACRAAAfAAMJLwduLACRAAAuAAQKfykAAh8ACQnUCq4vAEcBAB8ACQnUCq4vAEcBAAAA.Kairring:BAABLgAECn8iAAITAAkJ4BRgLwAaAgATAAkJ4BRgLwAaAgAAAA==.Kame:BAAALgAECgUJBQAAAA==.Kamehameha:BAABLgAECn8YAAIXAAkJlRXJCQDTAQAXAAkJlRXJCQDTAQAAAA==.Kami:BAABLgAECn80AAIfAAkJ1xMhHADJAQAfAAkJ1xMhHADJAQAAAA==.Kapslock:BAAALgAECgYJBwAAAA==.Karii:BAAALgADCgEJAQAAAA==.Karma:BAAALgADCgcJHAAAAA==.Katsicle:BAABLgAECn8fAAIFAAgJfAORxgD8AAAFAAgJfAORxgD8AAAAAA==.Kattastrophy:BAAALgAECggJEgAAAA==.Katteya:BAAALgAECgYJCQAAAA==.Kattia:BAABLgAECn8oAAITAAkJkA7uTQC0AQATAAkJkA7uTQC0AQAAAA==.Kazmoru:BAAALgAECgEJAQAAAA==.',
Kh='Khalico:BAAALgADCgEJAQAAAA==.Khellendros:BAAALgADCgUJBQABLgAECgYJCgABAAAAAA==.Khir:BAAALgAECgQJBwAAAA==.',
Ki='Killinkair:BAAALgAECgMJAwAAAA==.Kinomihime:BAABLgAECn83AAIFAAkJ3w8PYAC9AQAFAAkJ3w8PYAC9AQAAAA==.Kirajoy:BAABLgAECn9UAAIKAAkJ9QfEEwAOAQAKAAkJ9QfEEwAOAQAAAA==.Kirel:BAAALgADCgEJAQAAAA==.Kithri:BAAALgADCgEJAQAAAA==.Kiymeria:BAAALgAECgYJBgAAAA==.',
Kn='Knyghtt:BAABLgAECn8jAAIOAAgJDw8+NAB4AQAOAAgJDw8+NAB4AQAAAA==.',
Ko='Kogwyn:BAAALgAECggJEQAAAA==.Kogy:BAAALgADCgcJBgABLgAECggJEQABAAAAAA==.',
Kr='Kraviz:BAAALgAECgYJDgAAAA==.Krombopolous:BAAALgADCgkJHgABLgAECgkJMwATAJwRAA==.Krystle:BAABLgAECn8sAAITAAkJqRZaMAAWAgATAAkJqRZaMAAWAgAAAA==.',
Ky='Kydormu:BAAALgADCgEJAQAAAA==.',
['Kä']='Käyfex:BAAALgAECgQJBAAAAA==.',
La='Lazarus:BAAALgAECgkJCQAAAA==.',
Le='Leftyloose:BAAALgADCgkJBAAAAA==.',
Li='Lilfonz:BAABLgAECn8aAAMZAAcJdhARPQBPAQAZAAcJdhARPQBPAQAcAAYJsxgVnQBEAQAAAA==.Livik:BAABLgAECn8aAAIUAAkJzxxiAwBoAgAUAAkJzxxiAwBoAgAAAA==.',
Lo='Lockofdeath:BAAALgADCgYJBwAAAA==.Lockywolf:BAAALgAECgUJBgAAAA==.Logarth:BAAALgAECgYJDAAAAA==.Longbrew:BAAALgADCgEJAQAAAA==.Loppsang:BAAALgAECgYJEgAAAA==.Lorcan:BAABLgAECn82AAIiAAkJdhvnCgA2AgAiAAkJdhvnCgA2AgAAAA==.',
Lr='Lroye:BAACLgAFFH8PAAIjAAQJnBalHAAyAQAjAAQJnBalHAAyAQAuAAQKfxkAAiMABwnqHlgYANQBACMABwnqHlgYANQBAAAA.',
Ls='Lsdarko:BAAALgAECgEJAwAAAA==.',
Lu='Luckyleet:BAAALgADCgQJCwAAAA==.Lucyfer:BAAALgAECggJEgABLgAECgkJIQAcANIHAA==.Lucyferr:BAABLgAECn8ZAAIFAAgJfQXvtQAVAQAFAAgJfQXvtQAVAQABLgAECgkJIQAcANIHAA==.Ludacritts:BAAALgAECgQJBAAAAA==.Ludicrispeed:BAAALgADCgkJFQAAAA==.Luliak:BAACLgAFFH8QAAIRAAYJPCLTBAC+AQARAAYJPCLTBAC+AQAuAAQKfx8AAhEACQnRIlwEAOgCABEACQnRIlwEAOgCAAAA.Lunabren:BAABLgAECn8YAAMWAAcJwwfhSQDgAAAWAAcJwwfhSQDgAAAVAAIJoQYswABDAAAAAA==.Lunamina:BAAALgAECgYJDwAAAA==.',
Ly='Lynvala:BAAALgADCgQJBQAAAA==.Lysdexíc:BAABLgAECn8aAAIaAAkJzhMUQQDCAQAaAAkJzhMUQQDCAQAAAA==.',
['Lì']='Lìllith:BAABLgAECn8sAAMJAAkJLB2qDQCIAgAJAAkJLB2qDQCIAgAkAAQJIwrgTgCXAAABLgAFFAIJBwAcANcbAA==.',
Ma='Majika:BAAALgADCgYJBQAAAA==.Mariophra:BAABLgAECn83AAIMAAkJ1xpKFQCdAgAMAAkJ1xpKFQCdAgAAAA==.Marvelious:BAAALgAFFAEJAQAAAA==.Mattlen:BAAALgADCgYJCAAAAA==.Maximumswag:BAAALgADCgkJLQABLgAECgkJMwATAJwRAA==.Maxmugruith:BAAALgADCgQJBwAAAA==.',
Mc='Mcnastyqt:BAAALgAECgQJBAAAAA==.',
Me='Meatshiéld:BAAALgAECgYJCgAAAA==.',
Mi='Midopamos:BAAALgADCgEJAQAAAA==.Mikki:BAAALgAECgcJDwAAAA==.Missconduct:BAAALgADCgYJBgAAAA==.Misstorgo:BAABLgAECn8dAAINAAgJXR/FCABpAgANAAgJXR/FCABpAgAAAA==.',
Mo='Monfro:BAAALgAECggJEAAAAA==.Moogatoo:BAAALgAECgYJCAAAAA==.Moonbane:BAABLgAECn8sAAIKAAgJUCClAwBRAgAKAAgJUCClAwBRAgAAAA==.Moonfanda:BAAALgADCgIJAgAAAA==.Moonmist:BAAALgADCgEJAQABLgAECggJDwABAAAAAA==.Moor:BAAALgAECgYJDAAAAA==.',
Mu='Mumferd:BAAALgADCgQJBAAAAA==.',
My='Myaquean:BAAALgADCgkJFAAAAA==.Mystogan:BAAALgAECgcJEgAAAA==.Myth:BAAALgAECggJCAAAAA==.Mythelea:BAAALgADCgcJBwAAAA==.',
Na='Nakeefa:BAABLgAECn8nAAMCAAkJdBTbMgAMAgACAAkJdBTbMgAMAgAKAAEJAAA9cgAzAAAAAA==.Natsuu:BAABLgAECn8pAAMTAAkJOBu9RQDMAQATAAgJihy9RQDMAQARAAQJxhHXMwARAQAAAA==.Naturewolf:BAABLgAECn8eAAIDAAgJXRaNFAB0AQADAAgJXRaNFAB0AQAAAA==.',
Ne='Nefertiti:BAAALgAECgcJCAAAAA==.Nekona:BAABLgAECn8VAAQCAAgJTwuEiQBGAQACAAgJTwuEiQBGAQAKAAIJCgmuWwBcAAAeAAEJlwWVNAAzAAAAAA==.Neron:BAACLgAFFH8HAAIcAAIJ1xu8gwCjAAAcAAIJ1xu8gwCjAAAuAAQKfzwAAhwACQlYIHsbAJ0CABwACQlYIHsbAJ0CAAAA.Nethertusk:BAABLgAECn8uAAMCAAkJTBkaMgAPAgACAAkJTBkaMgAPAgAKAAIJYQP2WQBhAAAAAA==.',
Nh='Nhancecntrl:BAACLgAFFH8FAAILAAMJxQtGDwDMAAALAAMJxQtGDwDMAAAuAAQKfyYAAgsACQnRGiAFAJICAAsACQnRGiAFAJICAAAA.',
Ni='Niany:BAAALgAECgYJDgAAAA==.Nightbréaker:BAAALgADCgcJFQAAAA==.Nilospite:BAABLgAECn8tAAINAAgJQR7jCQBSAgANAAgJQR7jCQBSAgABLgAFFAYJHQAIANkYAA==.Nimposter:BAABLgAECn8rAAIQAAkJNRdCNwAfAgAQAAkJNRdCNwAfAgAAAA==.',
Nj='Njoror:BAAALgADCgQJBAAAAA==.',
No='Noodle:BAAALgADCgEJAQAAAA==.Norky:BAAALgAECgUJBQABLgAFFAQJEwAMAHEUAA==.Nottapally:BAAALgAECgcJEgABLgAECggJFAASAEIUAA==.',
Nu='Nullea:BAAALgAECgYJCAAAAA==.',
Ny='Nyxthos:BAAALgADCggJCAAAAA==.',
Ob='Obizi:BAAALgAECgEJAQAAAA==.',
Oc='Ocatarineta:BAAALgADCgIJAgAAAA==.',
Od='Odine:BAAALgAECgEJAgAAAA==.Odito:BAABLgAECn8VAAIWAAYJpRfHLwBbAQAWAAYJpRfHLwBbAQAAAA==.',
Om='Omegalich:BAAALgAECgEJAQAAAA==.',
Oo='Oopslol:BAAALgAECgYJDAAAAA==.',
Os='Osdavalmarro:BAAALgADCgYJGQAAAA==.',
Ot='Othaerion:BAABLgAECn8YAAIZAAkJbw8pKgC7AQAZAAkJbw8pKgC7AQAAAA==.',
Ou='Outerlimits:BAABLgAECn8uAAIlAAgJMRhbCwDAAQAlAAgJMRhbCwDAAQAAAA==.',
Pa='Paindore:BAAALgAECgQJBwAAAA==.Pamboo:BAABLgAECn8xAAIZAAkJzg/8JADcAQAZAAkJzg/8JADcAQAAAA==.',
Pe='Pearle:BAABLgAECn8pAAIIAAkJQx7YCwBOAgAIAAkJQx7YCwBOAgAAAA==.',
Ph='Phyg:BAAALgAECgQJBQABLgAECgUJBwABAAAAAA==.',
Po='Pokimane:BAAALgADCggJDwAAAA==.Polyasap:BAAALgADCgQJBAAAAA==.',
Pr='Priestiô:BAAALgAECgEJAQAAAA==.Pringo:BAAALgAFFAIJAgAAAA==.Proximal:BAAALgAECgcJBwAAAA==.',
Pu='Pukka:BAAALgADCgcJEQABLgAECgkJJAAJADUaAA==.Punk:BAAALgAFFAEJAQAAAA==.',
Qa='Qahnaarin:BAAALgAFFAEJAQAAAA==.',
Ra='Rajax:BAABLgAECn8WAAIOAAkJKhFjHwDyAQAOAAkJKhFjHwDyAQAAAA==.Ralphthedh:BAAALgAECgkJDwAAAA==.Ramindizzle:BAABLgAECn86AAIXAAkJcBbhCADnAQAXAAkJcBbhCADnAQAAAA==.Rangewolf:BAAALgADCgcJDgAAAA==.',
Re='Refreshing:BAAALgADCgIJAgAAAA==.Rejuvasap:BAABLgAECn8aAAQWAAgJMBpWKQC1AQAWAAgJMBpWKQC1AQAVAAUJ6R2JOwCkAQADAAMJqhdgNACGAAAAAA==.Rekki:BAAALgADCgEJAQAAAA==.Reliri:BAAALgADCgMJAwAAAA==.Remlin:BAAALgADCgcJCAAAAA==.Retastic:BAAALgAECgcJBwAAAA==.Retsall:BAAALgADCgUJBQAAAA==.Reâper:BAAALgAECgYJCgAAAA==.',
Ri='Rikal:BAAALgADCgYJEAAAAA==.',
Ro='Rook:BAABLgAECn82AAIXAAkJ8A0qDgB4AQAXAAkJ8A0qDgB4AQAAAA==.Roye:BAACLgAFFH8WAAIcAAYJqxRuJABvAQAcAAYJqxRuJABvAQAuAAQKfx4AAhwACQl1HbYaAMkCABwACQl1HbYaAMkCAAAA.',
Ru='Ruffiyo:BAABLgAECn8wAAMaAAkJtRToPgDJAQAaAAkJrxPoPgDJAQAhAAgJ3Q+LLQBfAQAAAA==.Rugrahfreaky:BAACLgAFFH8KAAIVAAQJ1BQLLAAAAQAVAAQJ1BQLLAAAAQAuAAQKfzkAAhUACQl6ISQFAGMDABUACQl6ISQFAGMDAAAA.Rugrahh:BAABLgAECn8pAAMXAAkJux5MDwDGAgAXAAkJux5MDwDGAgARAAMJaQ9RQgC4AAABLgAFFAQJCgAVANQUAA==.Rugrahx:BAABLgAFFH8FAAIbAAMJ4RkhBwDiAAAbAAMJ4RkhBwDiAAABLgAFFAQJCgAVANQUAA==.Ruthen:BAAALgAECgYJCwAAAA==.Ruìn:BAAALgAECgcJCQAAAA==.',
Sa='Sabermore:BAABLgAECn8cAAIcAAgJlxf/RQDyAQAcAAgJlxf/RQDyAQAAAA==.Sabina:BAABLgAECn83AAIPAAkJgAuZOABRAQAPAAkJgAuZOABRAQAAAA==.Sadako:BAAALgAECgYJBwABLgAECgkJIQAcANIHAA==.Sadness:BAAALgAECgYJDwAAAA==.Sadorick:BAAALgADCgkJLwAAAA==.Safira:BAAALgAECgQJBgABLgAFFAIJBwAcANcbAA==.Sageguy:BAAALgAECgYJEwAAAA==.Samerle:BAAALgADCgEJAQAAAA==.Sango:BAABLgAECn9CAAMhAAkJjxelDwApAgAhAAkJjxelDwApAgAaAAQJ2gKPwQB8AAAAAA==.Saucewalker:BAABLgAFFH8NAAIQAAUJAxrFSwBWAQAQAAUJAxrFSwBWAQAAAA==.Savagelykill:BAABLgAECn8YAAIIAAYJvwq0NQC9AAAIAAYJvwq0NQC9AAAAAA==.',
Sc='Scotch:BAABLgAECn8yAAMcAAkJYRupLQBIAgAcAAkJYRupLQBIAgASAAUJNxVhIwD2AAAAAA==.Scotchnwater:BAABLgAECn8cAAMmAAgJmA/lEgCXAQAmAAgJmA/lEgCXAQAnAAMJIwekGgB0AAAAAA==.Scrubyheals:BAAALgADCgQJBwABLgAECggJFAASAEIUAA==.',
Se='Sendio:BAAALgAECgQJBAAAAA==.Sendor:BAAALgADCgEJAQAAAA==.Senji:BAAALgADCgQJBAAAAA==.',
Sg='Sgtpayne:BAAALgADCgIJAgAAAA==.',
Sh='Shadowcrwlr:BAAALgAECgQJCgAAAA==.Shadowlock:BAAALgAECggJEwAAAA==.Shadowmane:BAAALgADCgQJBAAAAA==.Shaeixia:BAAALgADCggJCgAAAA==.Shamangroo:BAAALgADCggJCQABLgAECgUJFAANAJ0WAA==.Shamanio:BAAALgAECgEJAgAAAA==.Shamichangas:BAAALgAECgEJAQAAAA==.Shammying:BAAALgAECgUJCwAAAA==.Shamsham:BAAALgADCgIJAgAAAA==.Sharaaz:BAAALgAECgMJBgAAAA==.Shivalry:BAAALgADCgkJCwAAAA==.Shmiggy:BAAALgAECgQJCgAAAA==.',
Si='Silverytwo:BAAALgAECgYJBgAAAA==.Silverywine:BAAALgADCgkJCQAAAA==.Silverywolfe:BAAALgAECgQJCQAAAA==.Simony:BAABLgAECn8hAAIcAAkJ0gf2jwBPAQAcAAkJ0gf2jwBPAQAAAA==.Sinton:BAAALgADCgIJAgAAAA==.',
Sk='Skorpyoh:BAAALgADCgYJBgAAAA==.Skovak:BAABLgAECn8VAAISAAkJkA6vFQB2AQASAAkJkA6vFQB2AQAAAA==.Skybright:BAAALgAECggJCwAAAA==.',
So='Soggy:BAAALgAECgcJBwAAAA==.Sorayae:BAABLgAECn8kAAIJAAkJNRr1EwA/AgAJAAkJNRr1EwA/AgAAAA==.',
Sp='Specialk:BAAALgAECgYJDQAAAA==.Spinnykat:BAAALgAECgMJBgAAAA==.Splooshh:BAAALgAECgIJAwABLgAECgkJMAAaALUUAA==.',
St='Starmist:BAAALgADCgMJAwAAAA==.Stinkfoot:BAAALgAECgUJCAAAAA==.Stoo:BAAALgADCgkJHAAAAA==.Stormkissed:BAABLgAECn8bAAMMAAgJlAzVTgByAQAMAAgJlAzVTgByAQAPAAEJQALuvQAcAAAAAA==.Stormweaver:BAAALgAECgUJBQAAAA==.',
Su='Sunil:BAABLgAECn9GAAIJAAkJxx64BQAZAwAJAAkJxx64BQAZAwAAAA==.Suviqhabo:BAAALgAECggJDwAAAA==.',
Sv='Svala:BAAALgADCgYJBgAAAA==.',
Sy='Syclone:BAABLgAECn8zAAINAAkJECa8AABpAwANAAkJECa8AABpAwAAAA==.Syladen:BAAALgAECgYJEgAAAA==.Syleste:BAAALgAECgQJBAABLgAECgkJMwANABAmAA==.Syvi:BAAALgAECgYJCQABLgAECggJEQABAAAAAA==.',
Ta='Tahwe:BAAALgADCgUJBQAAAA==.Tattianna:BAAALgAECgUJDwAAAA==.Tavendar:BAAALgAECgQJBAABLgAFFAQJEwAMAHEUAA==.Tavil:BAAALgADCgMJAwAAAA==.Taírn:BAAALgAECgYJEAAAAA==.',
Te='Techie:BAABLgAECn8gAAMgAAkJTRLWIwD8AQAgAAkJTRLWIwD8AQAoAAUJpASfYgC4AAAAAA==.Teeser:BAAALgAECgYJCwAAAA==.Terradactyl:BAAALgADCgMJAwAAAA==.',
Th='Thesis:BAAALgADCgkJCQAAAA==.Thunderslate:BAABLgAECn8UAAISAAgJQhTREgCYAQASAAgJQhTREgCYAQAAAA==.Thôrin:BAAALgADCgkJFQAAAA==.',
Ti='Tigerlillee:BAAALgADCgcJDQAAAA==.Tigreth:BAABLgAECn82AAMcAAkJ1hTOUADUAQAcAAkJ1hTOUADUAQASAAIJlhSvNgBoAAAAAA==.Timotheus:BAAALgAECgUJDAAAAA==.',
To='Tonï:BAAALgADCggJCAAAAA==.',
Tr='Tragik:BAABLgAECn8mAAILAAkJQA4IEACtAQALAAkJQA4IEACtAQAAAA==.',
Tt='Ttrouble:BAAALgADCgUJBQAAAA==.',
Tu='Tuugadark:BAABLgAECn81AAICAAkJRx0sJABNAgACAAkJRx0sJABNAgAAAA==.Tuugashox:BAAALgAECgUJBQAAAA==.',
Ul='Ulyaoth:BAABLgAECn83AAICAAgJjQvdbgBcAQACAAgJjQvdbgBcAQAAAA==.',
Un='Unnerfable:BAAALgAECgYJCAAAAA==.',
Uw='Uwa:BAAALgADCgMJAwAAAA==.',
Uy='Uy:BAAALgAECgYJDwAAAA==.',
Va='Valakha:BAAALgAECgQJDwAAAA==.Valkyrie:BAAALgAECgQJBgAAAA==.',
Ve='Vedros:BAAALgADCgkJDgAAAA==.Vermouth:BAAALgAECgYJCQAAAA==.Vespertilia:BAAALgAECgEJAQAAAA==.',
Vi='Viktoros:BAAALgAECgIJAgAAAA==.Violetra:BAAALgADCgMJAwAAAA==.',
Vo='Vorcan:BAAALgADCgYJBgAAAA==.Vorukh:BAABLgAECn8eAAQDAAkJcBGFDgDHAQADAAkJcBGFDgDHAQAVAAMJ9gwElwCBAAAHAAEJyw/kfAAhAAAAAA==.',
Vr='Vrave:BAAALgADCgQJBQAAAA==.',
Vy='Vyhlet:BAAALgAECggJEgABLgAECgkJVwAMAG8hAA==.',
Wa='Warlockgroo:BAAALgADCgQJBAABLgAECgUJFAANAJ0WAA==.Warriorgroo:BAABLgAECn8UAAINAAUJnRa6JQD/AAANAAUJnRa6JQD/AAAAAA==.',
We='Wendish:BAAALgAECgEJCgAAAA==.Wertyda:BAABLgAECn8aAAIZAAkJzhSGJgDSAQAZAAkJzhSGJgDSAQAAAA==.Wetnwild:BAAALgAECgUJBQAAAA==.',
Wh='Whácker:BAABLgAECn8UAAMiAAgJOwpYEgB8AQAiAAgJOwpYEgB8AQANAAMJrAguOQCBAAABLgAECgYJEAABAAAAAA==.',
Wi='Wickdlovly:BAAALgADCgEJAQABLgAECggJDwABAAAAAA==.Wickedslicks:BAABLgAECn86AAIWAAkJdCAKCADRAgAWAAkJdCAKCADRAgAAAA==.Wildthangg:BAAALgAECgIJAgAAAA==.',
Wo='Wooddchipper:BAAALgADCgYJBgAAAA==.',
Wr='Wreckshop:BAABLgAECn8ZAAIQAAkJ8xq6SADmAQAQAAkJ8xq6SADmAQAAAA==.',
Wt='Wtfoxtrot:BAAALgADCgkJDAAAAA==.',
Xe='Xenøcide:BAAALgAECgcJEwAAAA==.',
Xi='Xiatus:BAAALgAECgUJBQABLgAECgkJKgAQAOYhAA==.',
Xx='Xxlockz:BAABLgAECn8lAAMCAAkJWRHjZAB0AQACAAgJ8A7jZAB0AQAKAAMJGRGvIACkAAAAAA==.Xxpallyz:BAAALgAECggJCwABLgAECgkJJQACAFkRAA==.',
Yi='Yinger:BAAALgADCgcJEAAAAA==.Yinglang:BAAALgADCgEJAQAAAA==.Yingling:BAABLgAECn8rAAIQAAkJ6RmvQAD+AQAQAAkJ6RmvQAD+AQAAAA==.',
Yo='Yohh:BAABLgAECn8XAAIMAAgJ8xOZMgDlAQAMAAgJ8xOZMgDlAQAAAA==.',
Yu='Yukara:BAAALgADCgYJBgAAAA==.Yulay:BAAALgADCgkJBwAAAA==.Yuriko:BAABLgAECn83AAIgAAkJ1hPVIgACAgAgAAkJ1hPVIgACAgAAAA==.',
Za='Zaidan:BAAALgAECgUJEQAAAA==.Zanpaktu:BAAALgAECgYJEwAAAA==.Zaraha:BAAALgADCgEJAQAAAA==.Zata:BAAALgAECgUJBwAAAA==.',
Ze='Zendous:BAAALgAECgcJBwAAAA==.Zeref:BAAALgAECgYJEgAAAA==.Zeur:BAAALgAECgEJAQAAAA==.Zevgrip:BAAALgAECgQJBQAAAA==.',
Zh='Zhia:BAAALgAECgQJBQAAAA==.',
Zi='Zippitydooda:BAAALgADCgQJBAABLgAECggJDwABAAAAAA==.',
Zo='Zodiacc:BAABLgAECn84AAIHAAkJQxzHBgCJAgAHAAkJQxzHBgCJAgAAAA==.Zornen:BAAALgAECgcJCQAAAA==.Zornhealer:BAAALgAECgUJBgABLgAECgYJEwABAAAAAA==.',
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
