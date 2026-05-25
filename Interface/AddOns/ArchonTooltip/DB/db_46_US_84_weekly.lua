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

local lookup = {'Unknown-Unknown','Warlock-Demonology','Druid-Feral','Mage-Arcane','Mage-Frost','Mage-Fire','DeathKnight-Blood','Priest-Holy','Shaman-Enhancement','Shaman-Restoration','Warrior-Protection','Warrior-Fury','Shaman-Elemental','DeathKnight-Unholy','Hunter-Survival','Hunter-BeastMastery','Rogue-Outlaw','Druid-Restoration','Druid-Balance','Druid-Guardian','Hunter-Marksmanship','Paladin-Holy','DemonHunter-Devourer','Priest-Discipline','Warlock-Affliction','Monk-Windwalker','Paladin-Retribution','DemonHunter-Havoc','DemonHunter-Vengeance','Warlock-Destruction','Warrior-Arms','Rogue-Subtlety','Priest-Shadow','DeathKnight-Frost','Paladin-Protection','Monk-Mistweaver','Monk-Brewmaster',}
local provider = {region='US',realm='EchoIsles',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aaelless:BAAALgAECgEJAQAAAA==.Aardz:BAAALgADCgIJAgAAAA==.',
Ab='Abeblinkin:BAAALgADCgYJDQAAAA==.Abrakadavar:BAAALgAECgQJBQAAAA==.Abräxis:BAAALgADCgkJCQABLgAECgMJAwABAAAAAA==.',
Ac='Ackspez:BAAALgADCgYJBgAAAA==.',
Ae='Aeless:BAABLgAECn8WAAICAAkJcSBrCwDeAgACAAkJcSBrCwDeAgAAAA==.Aelless:BAAALgAECgMJBQAAAA==.Aenest:BAAALgADCggJCAAAAA==.',
Ai='Aithinne:BAAALgAECgMJBQAAAA==.',
Ak='Akanah:BAAALgADCgcJBwAAAA==.',
Al='Alch:BAAALgADCgkJDgAAAA==.Alfira:BAAALgAECgYJDgAAAA==.Alghul:BAAALgAECgEJAQABLgAECgUJDgABAAAAAA==.',
Am='Amalthea:BAAALgADCgcJBwAAAA==.Amoredis:BAAALgADCgYJDQAAAA==.Amorlorin:BAAALgADCggJCQAAAA==.',
An='Anklbiterkat:BAAALgADCgQJBAAAAA==.Anume:BAAALgADCgYJFAAAAA==.',
Ar='Aravis:BAABLgAECn8VAAIDAAgJrQg+FwAhAQADAAgJrQg+FwAhAQAAAA==.Arese:BAABLgAECn8cAAQEAAYJTiZ/AwA0AgAEAAUJTiZ/AwA0AgAFAAMJlyTzEgHYAAAGAAEJAABTDABpAAAAAA==.Argopol:BAAALgAECgcJCgABLgAECgkJJgAHABoeAA==.Aron:BAAALgADCgMJAgAAAA==.',
As='Ashandra:BAAALgADCgkJDwAAAA==.Ashlyssra:BAABLgAECn8fAAIIAAkJYh2CBgDrAgAIAAkJYh2CBgDrAgAAAA==.',
Aw='Awsomesause:BAAALgAECgQJBgAAAA==.',
Az='Azuri:BAAALgAECgQJBQAAAA==.Azzif:BAAALgAECgkJEQAAAA==.Azzraell:BAAALgADCgEJAQAAAA==.',
Ba='Babaorumm:BAAALgAECgQJBAAAAA==.Babasha:BAACLgAFFH8JAAIJAAQJ6QuYBgAeAQAJAAQJ6QuYBgAeAQAuAAQKfxcAAwkABgmSH/oMAKsBAAkABgmSH/oMAKsBAAoABgnADcJPAEUBAAAA.Babybluz:BAAALgAECggJEwAAAA==.Baconloaf:BAAALgAECgUJCQAAAA==.Baifeng:BAAALgADCgkJCQAAAA==.Baldilocks:BAAALgADCgQJDAAAAA==.Bat:BAAALgADCgEJAQAAAA==.',
Be='Beauriley:BAABLgAECn8xAAMLAAkJHBXgDgDSAQALAAkJHBXgDgDSAQAMAAEJnA7tgQA8AAAAAA==.Behomethan:BAABLgAECn8mAAMKAAkJZBtJKgDlAQAKAAgJOBpJKgDlAQANAAgJABRYKQB4AQAAAA==.Beyonsláy:BAAALgADCgIJAgAAAA==.',
Bh='Bhipbookie:BAAALgAECgEJBAAAAA==.',
Bi='Billbetaray:BAAALgADCgMJAwAAAA==.',
Bl='Bluerift:BAAALgADCgEJAQAAAA==.Blux:BAAALgAECgEJAQAAAA==.',
Bo='Bobbyb:BAABLgAECn8UAAIOAAcJKhhcUwCmAQAOAAcJKhhcUwCmAQAAAA==.Bombchele:BAAALgAECgYJBgABLgAECgkJGAAOABsZAA==.Boneulngtime:BAAALgADCgUJCgAAAA==.Boon:BAAALgAECgIJAgAAAA==.Bowlofwrong:BAAALgAECgYJBwAAAA==.',
Br='Bratticusrex:BAABLgAECn8cAAIMAAYJnAndTgDiAAAMAAYJnAndTgDiAAAAAA==.Bresowar:BAAALgAECgYJBwAAAA==.',
Bu='Bunnylicious:BAABLgAECn8qAAIKAAkJXiMLAgCOAwAKAAkJXiMLAgCOAwAAAA==.Bunnymedic:BAAALgAECgYJDAABLgAECgkJKgAKAF4jAA==.',
Ca='Caebrylla:BAABLgAECn8sAAIPAAgJ0QyOGwCiAQAPAAgJ0QyOGwCiAQAAAA==.Calistie:BAAALgAECgIJAgAAAA==.Camigatu:BAAALgADCgQJBAAAAA==.Camil:BAAALgAECgYJBwABLgAFFAIJBQAQAPoGAA==.Cang:BAAALgAECgIJAgAAAA==.Capulin:BAABLgAECn8iAAIMAAgJpRZYIQDBAQAMAAgJpRZYIQDBAQAAAA==.Catdurid:BAAALgADCgYJBgAAAA==.',
Ce='Cecilbrown:BAAALgADCgUJBQAAAA==.Cecimorte:BAABLgAECn8sAAIHAAgJEhp5DQACAgAHAAgJEhp5DQACAgAAAA==.Cephalopod:BAABLgAECn8UAAIRAAgJ1RXEAwD5AQARAAgJ1RXEAwD5AQAAAA==.',
Ch='Chargeasap:BAAALgAECgMJAwAAAA==.Charttopper:BAAALgAECgYJCQAAAA==.Chibby:BAAALgADCgMJAwAAAA==.Chonker:BAABLgAECn84AAMSAAkJdSC4BQBEAwASAAkJdSC4BQBEAwATAAcJVwxMMAAtAQAAAA==.Chorelock:BAAALgADCgEJAQAAAA==.Chronormu:BAAALgAECgMJAwAAAA==.Chuckforrest:BAAALgAECgQJBAAAAA==.Chultis:BAABLgAECn8YAAQDAAgJuhRSDgCbAQADAAgJuhRSDgCbAQATAAEJ2wH5jgAeAAASAAEJAgLF6QAbAAAAAA==.',
Ci='Cihato:BAABLgAECn83AAIUAAkJIxt+BgBiAgAUAAkJIxt+BgBiAgAAAA==.',
Cl='Claxious:BAABLgAECn8dAAIVAAgJshixCADLAQAVAAgJshixCADLAQAAAA==.Claye:BAACLgAFFH8PAAIKAAQJahF1KQADAQAKAAQJahF1KQADAQAuAAQKfyoAAgoACQnPHLgMAMoCAAoACQnPHLgMAMoCAAAA.',
Co='Coldshoulder:BAABLgAECn8sAAIFAAgJgBwCMgAzAgAFAAgJgBwCMgAzAgAAAA==.Corelas:BAABLgAECn8eAAIFAAYJhQgwvwDtAAAFAAYJhQgwvwDtAAAAAA==.Corfellyn:BAAALgAECggJBAAAAA==.Couchdad:BAAALgAECgUJDgAAAA==.',
Cr='Crazymadman:BAAALgAECgQJCAAAAA==.Crushingblow:BAAALgAECgkJAwAAAA==.',
Cy='Cyon:BAAALgADCgEJAQAAAA==.',
Da='Daalaria:BAAALgADCgEJAQAAAA==.Darkone:BAAALgADCgUJBQAAAA==.Dawnson:BAABLgAECn8jAAIWAAgJQx6TDgCGAgAWAAgJQx6TDgCGAgAAAA==.',
De='Deadzexcs:BAAALgAECgUJEAAAAA==.Deathsnear:BAAALgAECgEJAQAAAA==.Demogless:BAABLgAECn8aAAIXAAgJowe7dAARAQAXAAgJowe7dAARAQAAAA==.Desyrel:BAAALgAECgYJBgABLgAECgkJIAAQAMULAA==.Devyn:BAAALgADCgUJBQAAAA==.',
Dh='Dharknight:BAAALgAECgEJAQAAAA==.',
Di='Didimissfire:BAEBLgAECn87AAIQAAkJlxREKgAKAgAQAAkJlxREKgAKAgAAAA==.',
Do='Donaghy:BAAALgAECgEJAQAAAA==.Dooms:BAAALgADCgcJBwAAAA==.',
Dp='Dpsmaster:BAABLgAECn8VAAITAAYJWAX7TACnAAATAAYJWAX7TACnAAAAAA==.',
Dr='Dranalis:BAAALgAECgYJBwAAAA==.Drdrake:BAAALgADCgcJFAAAAA==.Dredlok:BAAALgADCgkJFwAAAA==.Drufiyo:BAAALgAECgUJBQABLgAECgkJMAAXALUUAA==.',
Du='Dumonster:BAABLgAECn8VAAIMAAYJ6gT0XQCsAAAMAAYJ6gT0XQCsAAAAAA==.',
['Dø']='Døll:BAAALgADCgYJBgAAAA==.',
Ea='Eamishal:BAAALgADCgEJAQAAAA==.',
Ei='Eightace:BAAALgAECgEJAQAAAA==.Eirenne:BAAALgAECgYJBwAAAA==.',
Ek='Ekaru:BAAALgADCgEJAQAAAA==.',
El='Elethryia:BAAALgAECgcJDAAAAA==.Elev:BAAALgADCgYJEQAAAA==.Elindril:BAAALgAECgYJDwAAAA==.',
En='Enoth:BAAALgAECgUJCAAAAA==.',
Eo='Eowynn:BAABLgAECn8fAAIKAAkJjBq3EQCVAgAKAAkJjBq3EQCVAgAAAA==.',
Er='Erewhon:BAAALgADCgkJCQAAAA==.',
Es='Estella:BAABLgAECn8hAAIFAAYJ7g1ErQALAQAFAAYJ7g1ErQALAQAAAA==.',
Ev='Eventhorizon:BAAALgAECgkJBgAAAA==.Evielli:BAAALgADCgUJBQAAAA==.',
Fa='Faeriefire:BAAALgADCggJDQAAAA==.Fanna:BAAALgADCgMJAwAAAA==.Fatbox:BAABLgAECn8gAAIMAAkJTR5WKACUAQAMAAkJTR5WKACUAQAAAA==.Faythh:BAABLgAECn8xAAMIAAkJfiFOBQAJAwAIAAkJfiFOBQAJAwAYAAEJVhvWWQBNAAAAAA==.',
Fe='Fearblade:BAAALgAECgUJBQAAAA==.Fedoran:BAABLgAECn8hAAQDAAkJXR6nCABTAgADAAcJlyCnCABTAgASAAcJbRHzOwCCAQATAAYJnBxYTgDwAAAAAA==.Felasap:BAAALgAECgcJCAAAAA==.Fenastic:BAABLgAECn8jAAMCAAgJJgfqfwAkAQACAAgJmgbqfwAkAQAZAAMJEAYsHACRAAAAAA==.Fenrisúlfur:BAAALgAECgUJDQAAAA==.Feyrah:BAAALgAECggJCwABLgAECgkJHwAKAIwaAA==.',
Fi='Filthy:BAAALgAECgkJCQAAAA==.Fiobhe:BAABLgAECn8cAAIWAAYJfRmeJwCnAQAWAAYJfRmeJwCnAQAAAA==.Fixeruper:BAABLgAECn8cAAIIAAgJswFxQQDAAAAIAAgJswFxQQDAAAAAAA==.',
Fl='Flaggedname:BAAALgADCgMJAwAAAA==.Flubberduck:BAAALgADCggJEAAAAA==.Fluffybeer:BAABLgAECn8eAAIOAAgJUB2jNAAJAgAOAAgJUB2jNAAJAgAAAA==.',
Fo='Fonz:BAAALgAECgUJBQABLgAECgcJGgAWAHYQAA==.Footdig:BAABLgAECn8pAAISAAgJACSgBwAjAwASAAgJACSgBwAjAwAAAA==.',
Fu='Fuquan:BAAALgAECgYJCgAAAA==.',
Fw='Fwd:BAAALgADCgIJAgAAAA==.',
Ga='Gadzook:BAAALgADCggJFQAAAA==.Gatolun:BAAALgADCgUJBQAAAA==.',
Gi='Giline:BAAALgAECgEJAQAAAA==.Gimp:BAAALgADCgEJAQAAAA==.Ginja:BAAALgADCgIJAgAAAA==.',
Gl='Glenlizzo:BAEALgADCgYJCgABLgAECgYJDAABAAAAAA==.Glenroyce:BAEALgAECgYJDAAAAA==.Gless:BAAALgAECgMJBQAAAA==.',
Go='Goodfine:BAAALgADCgcJDwAAAA==.Goss:BAAALgAECgMJAwAAAA==.Goteem:BAAALgADCgIJBgAAAA==.',
Gr='Grandcross:BAAALgADCgMJAwAAAA==.Griimtotem:BAAALgAECgQJBAAAAA==.',
Gu='Gungnir:BAABLgAECn8UAAIaAAgJrBb4FwDKAQAaAAgJrBb4FwDKAQAAAA==.Gush:BAAALgADCgQJBAAAAA==.Guttertrash:BAAALgAECgIJAgAAAA==.',
Ha='Hae:BAAALgADCgEJAQAAAA==.Haenus:BAAALgAECgEJAQAAAA==.Haill:BAAALgAECgYJBwAAAA==.Hamhock:BAAALgAECgcJEwABLgAECgkJIAAMAE0eAA==.Hammered:BAEALgADCgUJBQABLgAECgYJDAABAAAAAA==.Hardtobepro:BAAALgAECgcJBwAAAA==.Harleydk:BAAALgADCgUJBQAAAA==.',
He='Heartsong:BAAALgAECgcJBgAAAA==.',
Ho='Holycrusader:BAABLgAECn8YAAIbAAgJWBJIXQDLAQAbAAgJWBJIXQDLAQAAAA==.Hoop:BAAALgADCgUJBQAAAA==.Hornito:BAAALgAECgYJCAAAAA==.',
Ih='Ihatepallys:BAAALgAECgMJAwAAAA==.',
Ii='Iikeomgikr:BAAALgADCgEJAQAAAA==.',
Il='Ilduca:BAAALgADCgUJBQAAAA==.Ilidank:BAAALgAECgcJDgAAAA==.Ilya:BAAALgAECgUJCwABLgAECggJKAAbAHcbAA==.',
Im='Impotence:BAAALgADCgMJAwAAAA==.',
In='Indigo:BAABLgAECn89AAIKAAkJgh8pBwAXAwAKAAkJgh8pBwAXAwAAAA==.Innax:BAAALgADCgEJAQAAAA==.Innron:BAABLgAECn8xAAMcAAkJSxHAEwC9AQAcAAkJSxHAEwC9AQAdAAIJWwMrKQA7AAAAAA==.',
Ir='Irisblue:BAAALgADCgQJDgAAAA==.',
Iy='Iyahli:BAAALgAECgUJDwAAAA==.',
Ja='Jaedia:BAAALgADCgMJAwAAAA==.Jarclian:BAACLgAFFH8NAAIFAAQJNhDGSQA1AQAFAAQJNhDGSQA1AQAuAAQKfz4AAgUACQnRIiQMAAEDAAUACQnRIiQMAAEDAAAA.Jaymonk:BAAALgAECgYJCAAAAA==.Jazmon:BAAALgAECgIJAgAAAA==.',
Je='Jezzea:BAAALgADCgYJEQAAAA==.',
Ji='Jimlaheys:BAAALgAECgYJDgAAAA==.Jitt:BAAALgAECgUJDAAAAA==.',
['Jâ']='Jâten:BAAALgAECgcJDQABLgAFFAUJCAAXAK8UAA==.Jâtens:BAACLgAFFH8IAAMXAAUJrxQCMAArAQAXAAUJrxQCMAArAQAdAAEJAgSVDgAnAAAuAAQKfyIAAhcACAlxH5gXAGwCABcACAlxH5gXAGwCAAAA.',
Ka='Kaelía:BAAALgAECgYJBgAAAA==.Kair:BAACLgAFFH8FAAIaAAIJNANeKgBhAAAaAAIJNANeKgBhAAAuAAQKfycAAhoACQl/CkwmAFYBABoACQl/CkwmAFYBAAAA.Kairring:BAABLgAECn8WAAIQAAgJ4hPuOwDFAQAQAAgJ4hPuOwDFAQAAAA==.Kame:BAAALgAECgUJBQAAAA==.Kamehameha:BAABLgAECn8YAAIVAAkJlRWRBwDoAQAVAAkJlRWRBwDoAQAAAA==.Kami:BAABLgAECn80AAIaAAkJ1xOvFgDXAQAaAAkJ1xOvFgDXAQAAAA==.Kapslock:BAAALgAECgYJBwAAAA==.Karii:BAAALgADCgEJAQAAAA==.Karma:BAAALgADCgcJHAAAAA==.Katsicle:BAABLgAECn8XAAIFAAgJ/wGY1gDHAAAFAAgJ/wGY1gDHAAAAAA==.Katteya:BAAALgADCgkJMQAAAA==.Kattia:BAABLgAECn8lAAIQAAkJ7wyJQQCyAQAQAAkJ7wyJQQCyAQAAAA==.',
Kh='Khalico:BAAALgADCgEJAQAAAA==.Khellendros:BAAALgADCgUJBQABLgAECgYJCgABAAAAAA==.Khir:BAAALgAECgQJBwAAAA==.',
Ki='Kinomihime:BAABLgAECn83AAIFAAkJ3w+sTgDTAQAFAAkJ3w+sTgDTAQAAAA==.Kirajoy:BAABLgAECn87AAIeAAkJdQaVEAANAQAeAAkJdQaVEAANAQAAAA==.Kirel:BAAALgADCgEJAQAAAA==.Kithri:BAAALgADCgEJAQAAAA==.',
Kn='Knyghtt:BAABLgAECn8jAAIMAAgJDw94KwCBAQAMAAgJDw94KwCBAQAAAA==.',
Ko='Kogwyn:BAAALgAECggJEQAAAA==.Kogy:BAAALgADCgcJBgABLgAECggJEQABAAAAAA==.',
Kr='Kraviz:BAAALgAECgMJBQAAAA==.Krombopolous:BAAALgADCgkJGQABLgAECggJKAAQAFYMAA==.Krystle:BAABLgAECn8hAAIQAAgJ7RhAMADxAQAQAAgJ7RhAMADxAQAAAA==.',
Ky='Kydormu:BAAALgADCgEJAQAAAA==.',
['Kä']='Käyfex:BAAALgAECgQJBAAAAA==.',
Le='Leftyloose:BAAALgADCgkJBAAAAA==.',
Li='Lilfonz:BAABLgAECn8aAAMWAAcJdhAZNQBTAQAWAAcJdhAZNQBTAQAbAAYJsxgVnQBEAQAAAA==.Livik:BAABLgAECn8WAAIRAAgJah1CBAAaAgARAAgJah1CBAAaAgAAAA==.',
Lo='Lockofdeath:BAAALgADCgYJBwAAAA==.Lockywolf:BAAALgAECgUJBgAAAA==.Logarth:BAAALgAECgYJDAAAAA==.Longbrew:BAAALgADCgEJAQAAAA==.Loppsang:BAAALgAECgUJCgAAAA==.Lorcan:BAABLgAECn82AAIfAAkJdhtJCABGAgAfAAkJdhtJCABGAgAAAA==.',
Lr='Lroye:BAACLgAFFH8MAAIgAAQJ8xV/FABAAQAgAAQJ8xV/FABAAQAuAAQKfxkAAiAABwnqHlETAOQBACAABwnqHlETAOQBAAAA.',
Ls='Lsdarko:BAAALgAECgEJAQAAAA==.',
Lu='Luckyleet:BAAALgADCgQJCwAAAA==.Lucyfer:BAAALgAECgUJCgABLgAECgkJIAAQAMULAA==.Lucyferr:BAAALgAECgYJEQABLgAECgkJIAAQAMULAA==.Ludacritts:BAAALgAECgQJBAAAAA==.Ludicrispeed:BAAALgADCgYJFAAAAA==.Luliak:BAACLgAFFH8NAAIPAAUJNiI6BwB0AQAPAAUJNiI6BwB0AQAuAAQKfx0AAg8ACAlpIvcHAIUCAA8ACAlpIvcHAIUCAAAA.Lunabren:BAABLgAECn8YAAMTAAcJwwejPgDiAAATAAcJwwejPgDiAAASAAIJoQYhrgBDAAAAAA==.Lunamina:BAAALgAECgMJBQAAAA==.',
Ly='Lynvala:BAAALgADCgQJBQAAAA==.Lysdexíc:BAABLgAECn8XAAIXAAgJaRFCWQBYAQAXAAgJaRFCWQBYAQAAAA==.',
['Lì']='Lìllith:BAABLgAECn8hAAMIAAgJMhoGFQAHAgAIAAgJMhoGFQAHAgAhAAQJIwrgTgCXAAABLgAFFAIJBQAbANISAA==.',
Ma='Majika:BAAALgADCgYJBQAAAA==.Mariophra:BAABLgAECn8sAAIKAAgJKxuzGQBQAgAKAAgJKxuzGQBQAgAAAA==.Marvelious:BAAALgAFFAEJAQAAAA==.Mattlen:BAAALgADCgYJCAAAAA==.Maximumswag:BAAALgADCgkJEgABLgAECggJKAAQAFYMAA==.Maxmugruith:BAAALgADCgQJBwAAAA==.',
Mc='Mcnastyqt:BAAALgAECgQJBAAAAA==.',
Me='Meatshiéld:BAAALgAECgYJCgAAAA==.',
Mi='Midopamos:BAAALgADCgEJAQAAAA==.Mikki:BAAALgAECgYJCQAAAA==.Missconduct:BAAALgADCgYJBgAAAA==.Misstorgo:BAAALgAECgYJEgAAAA==.',
Mo='Monfro:BAAALgAECgcJDwAAAA==.Moogatoo:BAAALgAECgYJCAAAAA==.Moonbane:BAABLgAECn8sAAIeAAgJUCCqAgBfAgAeAAgJUCCqAgBfAgAAAA==.Moonfanda:BAAALgADCgIJAgAAAA==.Moonmist:BAAALgADCgEJAQABLgAECgYJBwABAAAAAA==.Moor:BAAALgAECgYJBwAAAA==.',
Mu='Mumferd:BAAALgADCgQJBAAAAA==.',
My='Myaquean:BAAALgADCgUJEwAAAA==.Mystogan:BAAALgAECgcJBwAAAA==.Myth:BAAALgADCgUJBQAAAA==.',
Na='Nakeefa:BAABLgAECn8gAAMCAAkJhBMyNADwAQACAAkJhBMyNADwAQAeAAEJAAA9cgAzAAAAAA==.Natsuu:BAABLgAECn8jAAMQAAkJXxryNADfAQAQAAgJihzyNADfAQAPAAQJSAztMAD9AAAAAA==.Naturewolf:BAABLgAECn8eAAIDAAgJXRbFDwCEAQADAAgJXRbFDwCEAQAAAA==.',
Ne='Nefertiti:BAAALgAECgcJCAAAAA==.Nekona:BAABLgAECn8VAAQCAAgJTwuEiQBGAQACAAgJTwuEiQBGAQAeAAIJCgmuWwBcAAAZAAEJlwWVNAAzAAAAAA==.Neron:BAACLgAFFH8FAAIbAAIJ0hI6ZwCeAAAbAAIJ0hI6ZwCeAAAuAAQKfzwAAhsACQlYIOgTALACABsACQlYIOgTALACAAAA.Nethertusk:BAABLgAECn8uAAMCAAkJTBkwKAAhAgACAAkJTBkwKAAhAgAeAAIJYQP2WQBhAAAAAA==.',
Nh='Nhancecntrl:BAABLgAECn8cAAIJAAkJPBgKBQBuAgAJAAkJPBgKBQBuAgAAAA==.',
Ni='Niany:BAAALgAECgYJCQAAAA==.Nightbréaker:BAAALgADCgcJFQAAAA==.Nilospite:BAABLgAECn8gAAILAAcJlRtMDgDbAQALAAcJlRtMDgDbAQABLgAFFAUJGwAHAIQcAA==.Nimposter:BAABLgAECn8jAAIOAAgJCBXGUQCrAQAOAAgJCBXGUQCrAQAAAA==.',
Nj='Njoror:BAAALgADCgQJBAAAAA==.',
No='Noodle:BAAALgADCgEJAQAAAA==.Nottapally:BAAALgAECgcJEQAAAA==.',
Nu='Nullea:BAAALgAECgYJCAAAAA==.',
Ny='Nyxthos:BAAALgADCggJCAAAAA==.',
Ob='Obizi:BAAALgAECgEJAQAAAA==.',
Oc='Ocatarineta:BAAALgADCgIJAgAAAA==.',
Od='Odito:BAAALgAECgYJEAAAAA==.',
Oo='Oopslol:BAAALgAECgYJDAAAAA==.',
Os='Osdavalmarro:BAAALgADCgYJGQAAAA==.',
Ot='Othaerion:BAABLgAECn8YAAIWAAkJbw/5IwDAAQAWAAkJbw/5IwDAAQAAAA==.',
Ou='Outerlimits:BAABLgAECn8uAAIiAAgJMRg4CADFAQAiAAgJMRg4CADFAQAAAA==.',
Pa='Paindore:BAAALgAECgQJBAAAAA==.Pamboo:BAABLgAECn8xAAIWAAkJzg84HwDjAQAWAAkJzg84HwDjAQAAAA==.',
Pe='Pearle:BAABLgAECn8mAAIHAAkJGh5VCQBUAgAHAAkJGh5VCQBUAgAAAA==.',
Ph='Phyg:BAAALgAECgQJBQABLgAECgUJBwABAAAAAA==.',
Po='Pokimane:BAAALgADCggJDwAAAA==.Polyasap:BAAALgADCgQJBAAAAA==.',
Pr='Proximal:BAAALgAECgcJBwAAAA==.',
Pu='Pukka:BAAALgADCgcJEQABLgAECgkJJAAIADUaAA==.Punk:BAAALgAFFAEJAQAAAA==.',
Qa='Qahnaarin:BAAALgADCgEJAQAAAA==.',
Ra='Rajax:BAAALgAECgcJDQAAAA==.Ralphthedh:BAAALgAECgkJDwAAAA==.Ramindizzle:BAABLgAECn86AAIVAAkJcBbVBgD7AQAVAAkJcBbVBgD7AQAAAA==.Rangewolf:BAAALgADCgcJDgAAAA==.',
Re='Rejuvasap:BAABLgAECn8aAAQTAAgJMBpWKQC1AQATAAgJMBpWKQC1AQASAAUJ6R3HNAClAQADAAMJqhfFKQCGAAAAAA==.Reliri:BAAALgADCgMJAwAAAA==.Remlin:BAAALgADCgcJCAAAAA==.Retsall:BAAALgADCgUJBQAAAA==.Reâper:BAAALgAECgYJCgAAAA==.',
Ri='Rikal:BAAALgADCgYJEAAAAA==.',
Ro='Rook:BAABLgAECn82AAIVAAkJ8A0iCwCRAQAVAAkJ8A0iCwCRAQAAAA==.Roye:BAACLgAFFH8SAAIbAAUJ8BagJgBDAQAbAAUJ8BagJgBDAQAuAAQKfx4AAhsACQl1HbYaAMkCABsACQl1HbYaAMkCAAAA.',
Ru='Ruffiyo:BAABLgAECn8wAAMXAAkJtRTENQDPAQAXAAkJrxPENQDPAQAcAAgJ3Q+LLQBfAQAAAA==.Rugrahfreaky:BAABLgAECn8xAAISAAkJGx/lBgAuAwASAAkJGx/lBgAuAwAAAA==.Rugrahh:BAABLgAECn8pAAMVAAkJux5MDwDGAgAVAAkJux5MDwDGAgAPAAMJaQ+7OQC/AAAAAA==.Ruthen:BAAALgAECgYJCwAAAA==.Ruìn:BAAALgAECgcJCQAAAA==.',
Sa='Sabermore:BAABLgAECn8UAAIbAAgJkhQPTQDBAQAbAAgJkhQPTQDBAQAAAA==.Sabina:BAABLgAECn83AAINAAkJgAtNLgBbAQANAAkJgAtNLgBbAQAAAA==.Sadako:BAAALgAECgYJBwABLgAECgkJIAAQAMULAA==.Sadness:BAAALgAECgMJBQAAAA==.Sadorick:BAAALgADCgkJLwAAAA==.Safira:BAAALgAECgQJBgABLgAFFAIJBQAbANISAA==.Sageguy:BAAALgAECgMJBQAAAA==.Samerle:BAAALgADCgEJAQAAAA==.Sango:BAABLgAECn85AAMcAAkJxhbYDAAiAgAcAAkJxhbYDAAiAgAXAAQJ2gKPwQB8AAAAAA==.Saucewalker:BAAALgAECgYJCQAAAA==.Savagelykill:BAAALgAECgQJDgAAAA==.',
Sc='Scotch:BAABLgAECn8pAAMbAAgJtRuTOgD4AQAbAAgJtRuTOgD4AQAjAAIJcRHHMQCHAAAAAA==.Scotchnwater:BAAALgAECgYJDQAAAA==.Scrubyheals:BAAALgADCgQJBwAAAA==.',
Se='Sendio:BAAALgAECgQJBAAAAA==.Sendor:BAAALgADCgEJAQAAAA==.Senji:BAAALgADCgQJBAAAAA==.',
Sg='Sgtpayne:BAAALgADCgIJAgAAAA==.',
Sh='Shadowcrwlr:BAAALgAECgMJBgAAAA==.Shadowlock:BAAALgAECggJEwAAAA==.Shadowmane:BAAALgADCgQJBAAAAA==.Shaeixia:BAAALgADCggJCgAAAA==.Shamangroo:BAAALgADCggJCQABLgAECgQJCgABAAAAAA==.Shammying:BAAALgAECgUJCwAAAA==.Shamsham:BAAALgADCgIJAgAAAA==.Sharaaz:BAAALgAECgIJAgAAAA==.Shivalry:BAAALgADCgkJCwAAAA==.Shmiggy:BAAALgAECgQJBgAAAA==.',
Si='Silverywine:BAAALgADCgkJCQAAAA==.Silverywolfe:BAAALgAECgMJBQAAAA==.Simony:BAABLgAECn8gAAIbAAgJ0wcBkgAuAQAbAAgJ0wcBkgAuAQABLgAECgkJIAAQAMULAA==.Sinton:BAAALgADCgIJAgAAAA==.',
Sk='Skorpyoh:BAAALgADCgYJBgAAAA==.Skovak:BAAALgAECgcJEAAAAA==.Skybright:BAAALgAECggJCwAAAA==.',
So='Soggy:BAAALgAECgcJBwAAAA==.Sorayae:BAABLgAECn8kAAIIAAkJNRr1EwA/AgAIAAkJNRr1EwA/AgAAAA==.',
Sp='Specialk:BAAALgAECgMJAwAAAA==.Spinnykat:BAAALgAECgMJBQAAAA==.Splooshh:BAAALgAECgIJAgABLgAECgkJMAAXALUUAA==.',
St='Starmist:BAAALgADCgMJAwAAAA==.Stinkfoot:BAAALgAECgQJBgAAAA==.Stoo:BAAALgADCgkJHAAAAA==.Stormkissed:BAAALgAECgUJEAAAAA==.Stormweaver:BAAALgAECgUJBQAAAA==.',
Su='Sunil:BAABLgAECn8tAAIIAAkJ2RRBEQAzAgAIAAkJ2RRBEQAzAgAAAA==.Suviqhabo:BAAALgAECggJDwAAAA==.',
Sv='Svala:BAAALgADCgYJBgAAAA==.',
Sy='Syclone:BAABLgAECn8qAAILAAkJECZQAAB8AwALAAkJECZQAAB8AwAAAA==.Syladen:BAAALgAECgYJEgAAAA==.Syleste:BAAALgAECgQJBAABLgAECgkJKgALABAmAA==.Syvi:BAAALgAECgYJCQABLgAECggJEQABAAAAAA==.',
Ta='Tahwe:BAAALgADCgUJBQAAAA==.Tattianna:BAAALgAECgQJCgAAAA==.Tavendar:BAAALgAECgMJAwABLgAFFAQJDwAKAGoRAA==.Tavil:BAAALgADCgMJAwAAAA==.Taírn:BAAALgAECgYJEAAAAA==.',
Te='Techie:BAABLgAECn8WAAMkAAgJExI7JAC3AQAkAAgJExI7JAC3AQAlAAUJpASfYgC4AAAAAA==.Terradactyl:BAAALgADCgMJAwAAAA==.',
Th='Thunderslate:BAABLgAECn8UAAIjAAgJQhQ4DwCjAQAjAAgJQhQ4DwCjAQAAAA==.Thôrin:BAAALgADCgkJFQAAAA==.',
Ti='Tigerlillee:BAAALgADCgcJDQAAAA==.Tigreth:BAABLgAECn82AAMbAAkJ1hTkPgDrAQAbAAkJ1hTkPgDrAQAjAAIJlhSvNgBoAAAAAA==.Timotheus:BAAALgAECgUJDAAAAA==.',
To='Tonï:BAAALgADCggJCAAAAA==.',
Tr='Tragik:BAABLgAECn8mAAIJAAkJQA5nDAC1AQAJAAkJQA5nDAC1AQAAAA==.',
Tt='Ttrouble:BAAALgADCgUJBQAAAA==.',
Tu='Tuugadark:BAABLgAECn81AAICAAkJRx2hHABfAgACAAkJRx2hHABfAgAAAA==.Tuugashox:BAAALgAECgUJBQAAAA==.',
Ul='Ulyaoth:BAABLgAECn8sAAICAAcJ1gl/fgAnAQACAAcJ1gl/fgAnAQAAAA==.',
Un='Unnerfable:BAAALgAECgYJCAAAAA==.',
Uw='Uwa:BAAALgADCgMJAwAAAA==.',
Uy='Uy:BAAALgAECgYJDwAAAA==.',
Va='Valakha:BAAALgAECgQJCwAAAA==.Valkyrie:BAAALgAECgQJBgAAAA==.',
Ve='Vedros:BAAALgADCgYJDQAAAA==.Vermouth:BAAALgAECgQJBAAAAA==.',
Vi='Viktoros:BAAALgAECgIJAgAAAA==.Violetra:BAAALgADCgMJAwAAAA==.',
Vo='Vorcan:BAAALgADCgYJBgAAAA==.Vorukh:BAABLgAECn8ZAAMDAAkJMhFZCwDRAQADAAkJMhFZCwDRAQAUAAEJyw+aWgAjAAAAAA==.',
Vr='Vrave:BAAALgADCgQJBQAAAA==.',
Vy='Vyhlet:BAAALgAECgIJBAABLgAECgkJPQAKAIIfAA==.',
Wa='Warriorgroo:BAAALgAECgQJCgAAAA==.',
We='Wendish:BAAALgAECgEJCQAAAA==.Wertyda:BAABLgAECn8aAAIWAAkJzhSlIADYAQAWAAkJzhSlIADYAQAAAA==.Wetnwild:BAAALgAECgUJBQAAAA==.',
Wh='Whácker:BAABLgAECn8UAAMfAAgJOwpYEgB8AQAfAAgJOwpYEgB8AQALAAMJrAguOQCBAAABLgAECgYJEAABAAAAAA==.',
Wi='Wickdlovly:BAAALgADCgEJAQABLgAECgYJBwABAAAAAA==.Wickedslicks:BAABLgAECn8yAAITAAgJkh+9DQBWAgATAAgJkh+9DQBWAgAAAA==.Wildthangg:BAAALgAECgIJAgAAAA==.',
Wo='Wooddchipper:BAAALgADCgYJBgAAAA==.',
Wr='Wreckshop:BAABLgAECn8YAAIOAAkJGxmJQwDWAQAOAAkJGxmJQwDWAQAAAA==.',
Wt='Wtfoxtrot:BAAALgADCgkJDAAAAA==.',
Xe='Xenøcide:BAAALgAECgcJEwAAAA==.',
Xx='Xxlockz:BAABLgAECn8aAAMCAAgJERB0dAA7AQACAAcJhw10dAA7AQAeAAMJHxDXGwCnAAAAAA==.Xxpallyz:BAAALgAECggJCwABLgAECggJGgACABEQAA==.',
Yi='Yinger:BAAALgADCgcJEAAAAA==.Yinglang:BAAALgADCgEJAQAAAA==.Yingling:BAABLgAECn8rAAIOAAkJ6RmQNQAFAgAOAAkJ6RmQNQAFAgAAAA==.',
Yo='Yohh:BAAALgAECgUJDAAAAA==.',
Yu='Yukara:BAAALgADCgYJBgAAAA==.Yulay:BAAALgADCgYJBgAAAA==.Yuriko:BAABLgAECn83AAIkAAkJ1hNWGwD9AQAkAAkJ1hNWGwD9AQAAAA==.',
Za='Zaidan:BAAALgAECgQJBwAAAA==.Zanpaktu:BAAALgAECgYJDQAAAA==.Zaraha:BAAALgADCgEJAQAAAA==.Zata:BAAALgAECgUJBwAAAA==.',
Ze='Zendous:BAAALgAECgcJBwAAAA==.Zeref:BAAALgAECgYJEgAAAA==.Zeur:BAAALgAECgEJAQAAAA==.Zevgrip:BAAALgAECgQJBQAAAA==.',
Zh='Zhia:BAAALgAECgQJBQAAAA==.',
Zi='Zippitydooda:BAAALgADCgQJBAABLgAECgYJBwABAAAAAA==.',
Zo='Zodiacc:BAABLgAECn84AAIUAAkJQxz5BACPAgAUAAkJQxz5BACPAgAAAA==.Zornhealer:BAAALgAECgUJBgABLgAECgUJDgABAAAAAA==.Zorrn:BAAALgAECgQJBQABLgAECgUJDgABAAAAAA==.',
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
