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

local lookup = {'Unknown-Unknown','Warlock-Demonology','Druid-Feral','Mage-Arcane','Mage-Frost','Mage-Fire','DeathKnight-Blood','Priest-Holy','Warlock-Destruction','Shaman-Enhancement','Shaman-Restoration','Warrior-Protection','Warrior-Fury','Shaman-Elemental','DeathKnight-Unholy','Hunter-Survival','Hunter-BeastMastery','Rogue-Outlaw','Paladin-Protection','Druid-Restoration','Druid-Balance','Druid-Guardian','Hunter-Marksmanship','Paladin-Holy','Rogue-Assassination','DemonHunter-Devourer','Priest-Discipline','Warlock-Affliction','Monk-Windwalker','DemonHunter-Havoc','Paladin-Retribution','DemonHunter-Vengeance','Warrior-Arms','Rogue-Subtlety','Priest-Shadow','DeathKnight-Frost','Monk-Mistweaver','Monk-Brewmaster',}
local provider = {region='US',realm='EchoIsles',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aaelless:BAAALgAECgEJAQAAAA==.Aardz:BAAALgADCgIJAgAAAA==.',
Ab='Abeblinkin:BAAALgADCgYJDQAAAA==.Abrakadavar:BAAALgAECgQJBQAAAA==.Abräxis:BAAALgADCgkJCQABLgAECgMJAwABAAAAAA==.',
Ac='Ackspez:BAAALgADCgYJBgAAAA==.',
Ae='Aeless:BAABLgAECn8ZAAICAAkJKyIhCQD+AgACAAkJKyIhCQD+AgAAAA==.Aelless:BAAALgAECgYJCAAAAA==.Aenest:BAAALgADCggJCAAAAA==.',
Ai='Aithinne:BAAALgAECgMJBQAAAA==.',
Ak='Akanah:BAAALgADCgcJBwAAAA==.',
Al='Alch:BAAALgADCgkJDgAAAA==.Alfira:BAAALgAECgYJEwAAAA==.Alghul:BAAALgAECgMJBAABLgAECgYJEwABAAAAAA==.',
Am='Amalthea:BAAALgADCgcJBwAAAA==.Amoredis:BAAALgADCgYJDQAAAA==.Amorlorin:BAAALgADCggJDQAAAA==.',
An='Anklbiterkat:BAAALgADCgQJBAAAAA==.Anume:BAAALgADCgYJFAAAAA==.',
Ar='Aragan:BAAALgAECgQJBAAAAA==.Aravis:BAABLgAECn8cAAIDAAgJewm3GQAbAQADAAgJewm3GQAbAQAAAA==.Arese:BAABLgAECn8dAAQEAAYJTiZ/AwA0AgAEAAUJTiZ/AwA0AgAFAAMJlyTzEgHYAAAGAAEJAABTDABpAAAAAA==.Argopol:BAAALgAECggJEQABLgAECgkJKAAHAEMeAA==.Aron:BAAALgADCgMJAgAAAA==.',
As='Ashandra:BAAALgADCgkJDwAAAA==.Ashlyssra:BAABLgAECn8fAAIIAAkJYh19BwDjAgAIAAkJYh19BwDjAgAAAA==.',
Aw='Awsomesause:BAAALgAECgQJBgAAAA==.',
Az='Azuri:BAAALgAECgQJBQAAAA==.Azzif:BAABLgAECn8YAAIJAAYJhAKXJAByAAAJAAYJhAKXJAByAAAAAA==.Azzraell:BAAALgADCgEJAQAAAA==.',
Ba='Babaorumm:BAAALgAECgQJBAAAAA==.Babasha:BAACLgAFFH8JAAIKAAQJ6QthCAAYAQAKAAQJ6QthCAAYAQAuAAQKfxcAAwoABgmSH7wOAKYBAAoABgmSH7wOAKYBAAsABgnADcJPAEUBAAAA.Babybluz:BAABLgAECn8cAAIFAAgJJgdUsQADAQAFAAgJJgdUsQADAQAAAA==.Baconloaf:BAAALgAECgUJCQAAAA==.Baifeng:BAAALgADCgkJDwAAAA==.Baldilocks:BAAALgADCgQJDAAAAA==.Barlas:BAAALgAECgEJAQAAAA==.Bat:BAAALgADCgEJAQAAAA==.',
Be='Beauriley:BAABLgAECn8xAAMMAAkJHBXPEADEAQAMAAkJHBXPEADEAQANAAEJnA6MjAA7AAAAAA==.Behomethan:BAABLgAECn8mAAMLAAkJZBtJKgDlAQALAAgJOBpJKgDlAQAOAAgJABTZLAB3AQAAAA==.Beyonsláy:BAAALgAECgUJBQAAAA==.',
Bh='Bhipbookie:BAAALgAECgEJBAAAAA==.',
Bi='Billbetaray:BAAALgADCgMJAwAAAA==.',
Bl='Bluerift:BAAALgADCgEJAQAAAA==.Blux:BAAALgAECgEJAQAAAA==.',
Bo='Bobbyb:BAABLgAECn8UAAIPAAcJKhghWwChAQAPAAcJKhghWwChAQAAAA==.Bombchele:BAAALgAECgYJBgABLgAECgkJGAAPABsZAA==.Boneulngtime:BAAALgADCgUJCgAAAA==.Boon:BAAALgAECgIJAgAAAA==.Bowlofwrong:BAAALgAECgYJBwAAAA==.',
Br='Bratticusrex:BAABLgAECn8fAAINAAgJ5wgEOwBEAQANAAgJ5wgEOwBEAQAAAA==.Bresowar:BAAALgAECgYJBwAAAA==.',
Bu='Bunnylicious:BAABLgAECn8zAAILAAkJkCW+AADJAwALAAkJkCW+AADJAwAAAA==.Bunnymedic:BAAALgAECgYJDAABLgAECgkJMwALAJAlAA==.',
Ca='Caebrylla:BAABLgAECn8yAAIQAAgJnQ2FHACqAQAQAAgJnQ2FHACqAQAAAA==.Calistie:BAAALgAECgIJAgAAAA==.Camigatu:BAAALgADCgQJBAAAAA==.Camil:BAAALgAECgYJBwABLgAFFAIJBQARAPoGAA==.Cang:BAAALgAECgIJAgAAAA==.Capulin:BAABLgAECn8kAAINAAkJsBbtGQAKAgANAAkJsBbtGQAKAgAAAA==.Catdurid:BAAALgADCgYJBgAAAA==.',
Ce='Cecilbrown:BAAALgADCgUJBQAAAA==.Cecimorte:BAABLgAECn8wAAIHAAgJEhouDwD8AQAHAAgJEhouDwD8AQAAAA==.Cephalopod:BAABLgAECn8UAAISAAgJ1RXEAwD5AQASAAgJ1RXEAwD5AQAAAA==.',
Ch='Chargeasap:BAAALgAECgMJAwAAAA==.Charttopper:BAAALgAECgYJCQABLgAECggJFAATAEIUAA==.Chibby:BAAALgADCgMJAwAAAA==.Chimichanga:BAAALgAECgcJCwABLgAECggJFAATAEIUAA==.Chonker:BAABLgAECn84AAMUAAkJdSCNBgBBAwAUAAkJdSCNBgBBAwAVAAcJVwySNAArAQAAAA==.Chorelock:BAAALgADCgEJAQABLgAECggJFAATAEIUAA==.Chronormu:BAAALgAECgMJAwAAAA==.Chuckforrest:BAAALgAECgQJBAAAAA==.Chultis:BAABLgAECn8YAAQDAAgJuhRsEACMAQADAAgJuhRsEACMAQAVAAEJ2wH5jgAeAAAUAAEJAgLF6QAbAAAAAA==.',
Ci='Cihato:BAABLgAECn83AAIWAAkJIxuUBwBeAgAWAAkJIxuUBwBeAgAAAA==.',
Cl='Claxious:BAABLgAECn8gAAIXAAkJ+BhZBgAXAgAXAAkJ+BhZBgAXAgAAAA==.Claye:BAACLgAFFH8TAAILAAQJcRTLKwAQAQALAAQJcRTLKwAQAQAuAAQKfyoAAgsACQnPHKoOAMYCAAsACQnPHKoOAMYCAAAA.',
Co='Coldshoulder:BAABLgAECn8wAAIFAAgJ5R3JLQBLAgAFAAgJ5R3JLQBLAgAAAA==.Corelas:BAABLgAECn8jAAIFAAYJ8AinywDZAAAFAAYJ8AinywDZAAAAAA==.Corfellyn:BAAALgAECggJBAAAAA==.Couchdad:BAAALgAECgYJEwAAAA==.',
Cr='Crazymadman:BAAALgAECgUJDQAAAA==.Crushingblow:BAAALgAECgkJAwAAAA==.',
Cy='Cyon:BAAALgADCgEJAQAAAA==.',
Da='Daalaria:BAAALgADCgEJAQAAAA==.Darkone:BAAALgADCgUJBQAAAA==.Dawnson:BAABLgAECn8nAAIYAAgJOyFaCADxAgAYAAgJOyFaCADxAgAAAA==.',
De='Deadzexcs:BAABLgAECn8UAAIZAAUJbAscFADTAAAZAAUJbAscFADTAAAAAA==.Deathsnear:BAAALgAECgEJAQAAAA==.Demogless:BAABLgAECn8iAAIaAAgJLwldcwAgAQAaAAgJLwldcwAgAQAAAA==.Desyrel:BAAALgAECgYJBgABLgAECgkJIAARAMULAA==.Devyn:BAAALgADCgUJBQAAAA==.',
Dh='Dharknight:BAAALgAECgEJAQAAAA==.',
Di='Didimissfire:BAEBLgAECn87AAIRAAkJlxT6LwAFAgARAAkJlxT6LwAFAgAAAA==.',
Do='Donaghy:BAAALgAECgEJAQAAAA==.Dooms:BAAALgADCgcJBwAAAA==.',
Dp='Dpsmaster:BAABLgAECn8WAAIVAAcJxATyTQC4AAAVAAcJxATyTQC4AAAAAA==.',
Dr='Dranalis:BAAALgAECgYJBwAAAA==.Drdrake:BAAALgADCgcJFAAAAA==.Dredlok:BAAALgAECgQJBAAAAA==.Drufiyo:BAAALgAECgUJBQABLgAECgkJMAAaALUUAA==.',
Du='Dumonster:BAABLgAECn8ZAAINAAYJyAWaXwC8AAANAAYJyAWaXwC8AAAAAA==.',
['Dø']='Døll:BAAALgADCgYJBgAAAA==.',
Ea='Eamishal:BAAALgADCgEJAQAAAA==.',
Ei='Eightace:BAAALgAECgQJAwAAAA==.Eirenne:BAAALgAECgYJBwAAAA==.',
Ek='Ekaru:BAAALgADCgEJAQAAAA==.',
El='Elethryia:BAAALgAECgcJDQAAAA==.Elev:BAAALgAECgQJBAAAAA==.Elindril:BAAALgAECgYJEQAAAA==.',
En='Enoth:BAAALgAECgYJDQAAAA==.',
Eo='Eowynn:BAABLgAECn8mAAILAAkJ7h8kBwAqAwALAAkJ7h8kBwAqAwAAAA==.',
Er='Erewhon:BAAALgADCgkJCQAAAA==.',
Es='Estella:BAABLgAECn8hAAIFAAYJ7g1EsgACAQAFAAYJ7g1EsgACAQAAAA==.',
Ev='Eventhorizon:BAAALgAECgkJBgAAAA==.Evielli:BAAALgADCgUJBQAAAA==.',
Fa='Faeriefire:BAAALgADCggJDQAAAA==.Fanna:BAAALgADCgMJAwAAAA==.Fatbox:BAABLgAECn8iAAINAAkJMSDqJQCzAQANAAkJMSDqJQCzAQAAAA==.Faythh:BAABLgAECn8xAAMIAAkJfiFWBgD+AgAIAAkJfiFWBgD+AgAbAAEJVhtxYABNAAAAAA==.',
Fe='Fearblade:BAAALgAECgUJCwAAAA==.Fedoran:BAABLgAECn8iAAQDAAkJRB+nCABTAgADAAcJyyGnCABTAgAUAAcJbREuPwCDAQAVAAYJnBxYTgDwAAAAAA==.Felasap:BAAALgAECgcJCAAAAA==.Fenastic:BAABLgAECn8lAAMCAAgJSgfxhgAiAQACAAgJvgbxhgAiAQAcAAMJEAYsHACRAAAAAA==.Fenrisúlfur:BAAALgAECgUJDQAAAA==.Feyrah:BAAALgAECggJCwABLgAECgkJJgALAO4fAA==.',
Fi='Filthy:BAAALgAECgkJCQAAAA==.Fiobhe:BAABLgAECn8hAAIYAAYJfRm+KgCjAQAYAAYJfRm+KgCjAQAAAA==.Fixeruper:BAABLgAECn8cAAIIAAgJswG1RQC5AAAIAAgJswG1RQC5AAAAAA==.',
Fl='Flaggedname:BAAALgADCgMJAwABLgAECggJFAATAEIUAA==.Flubberduck:BAAALgADCggJEAAAAA==.Fluffybeer:BAABLgAECn8gAAIPAAgJrh0ONQAXAgAPAAgJrh0ONQAXAgAAAA==.',
Fo='Fonz:BAAALgAECgUJBQABLgAECgcJGgAYAHYQAA==.Footdig:BAABLgAECn8qAAIUAAgJ7SQwBwA3AwAUAAgJ7SQwBwA3AwAAAA==.',
Fu='Fuquan:BAAALgAECgYJCgAAAA==.',
Fw='Fwd:BAAALgADCgIJAgAAAA==.',
Ga='Gadzook:BAAALgADCggJFQAAAA==.Garthok:BAAALgADCggJCAAAAA==.Gatolun:BAAALgADCgUJBQAAAA==.',
Gi='Giline:BAAALgAECgEJAQAAAA==.Gimp:BAAALgADCgEJAQAAAA==.Ginja:BAAALgADCgIJAgAAAA==.',
Gl='Glenlizzo:BAEALgADCgYJDQABLgAECgYJEAABAAAAAA==.Glenroyce:BAEALgAECgYJEAAAAA==.Gless:BAAALgAECgQJCQAAAA==.',
Go='Goodfine:BAAALgADCgcJDwAAAA==.Goss:BAAALgAECgMJAwAAAA==.Goteem:BAAALgADCgIJBgAAAA==.',
Gr='Grandcross:BAAALgADCgMJAwAAAA==.Griimtotem:BAAALgAECgQJBAAAAA==.',
Gu='Gungnir:BAABLgAECn8XAAIdAAgJnRgIFQD7AQAdAAgJnRgIFQD7AQAAAA==.Gush:BAAALgADCgQJBAAAAA==.Guttertrash:BAAALgAECgIJAgAAAA==.',
Ha='Hae:BAAALgADCgEJAQAAAA==.Haenus:BAAALgAECgEJAQAAAA==.Haill:BAAALgAECgYJBwAAAA==.Hamhock:BAABLgAECn8aAAIeAAcJHRtCEwDbAQAeAAcJHRtCEwDbAQABLgAECgkJIgANADEgAA==.Hammered:BAEALgADCgUJBQABLgAECgYJEAABAAAAAA==.Hardtobepro:BAAALgAECgcJBwAAAA==.Harleydk:BAAALgADCgUJBQAAAA==.',
He='Heartsong:BAAALgAECgcJBgAAAA==.',
Ho='Holycrusader:BAABLgAECn8YAAIfAAgJWBJIXQDLAQAfAAgJWBJIXQDLAQAAAA==.Hoop:BAAALgADCgUJBgAAAA==.Hornito:BAAALgAECgYJCAAAAA==.',
Ih='Ihatepallys:BAAALgAECgUJCAAAAA==.',
Ii='Iikeomgikr:BAAALgADCgEJAQAAAA==.',
Il='Ilduca:BAAALgADCgUJBQAAAA==.Ilidank:BAABLgAECn8VAAIaAAcJUxn9QwCkAQAaAAcJUxn9QwCkAQAAAA==.Ilya:BAAALgAECgUJCwABLgAECggJKAAfAHcbAA==.',
Im='Impotence:BAAALgADCgMJAwAAAA==.',
In='Indigo:BAABLgAECn9JAAMLAAkJQiDvBgAtAwALAAkJQiDvBgAtAwAOAAMJChrDTADmAAAAAA==.Innax:BAAALgADCgEJAQAAAA==.Innron:BAABLgAECn8xAAMeAAkJSxE4FgC2AQAeAAkJSxE4FgC2AQAgAAIJWwORLAA7AAAAAA==.',
Ir='Irisblue:BAAALgADCgQJDgAAAA==.',
Iy='Iyahli:BAAALgAECgUJDwAAAA==.',
Ja='Jaedia:BAAALgADCgYJCQAAAA==.Jarclian:BAACLgAFFH8NAAIFAAQJNhAuVAAqAQAFAAQJNhAuVAAqAQAuAAQKfz4AAgUACQnRImgOAPMCAAUACQnRImgOAPMCAAAA.Jaymonk:BAAALgAECgkJDgAAAA==.Jazmon:BAAALgAECgIJAgAAAA==.',
Je='Jezzea:BAAALgADCgYJEQAAAA==.',
Ji='Jimlaheys:BAAALgAECgYJDgAAAA==.Jitt:BAAALgAECgUJEAAAAA==.',
['Jâ']='Jâten:BAAALgAECgcJDQABLgAFFAUJCAAaAK8UAA==.Jâtens:BAACLgAFFH8IAAMaAAUJrxSpOAAfAQAaAAUJrxSpOAAfAQAgAAEJAgTOEAAnAAAuAAQKfyIAAhoACAlxHwsaAGQCABoACAlxHwsaAGQCAAAA.',
Ka='Kaelía:BAAALgAECgcJDAAAAA==.Kair:BAACLgAFFH8HAAIdAAIJCgdQLwBoAAAdAAIJCgdQLwBoAAAuAAQKfycAAh0ACQl/CjkqAFABAB0ACQl/CjkqAFABAAAA.Kairring:BAABLgAECn8aAAIRAAkJbhMuLwAJAgARAAkJbhMuLwAJAgAAAA==.Kame:BAAALgAECgUJBQAAAA==.Kamehameha:BAABLgAECn8YAAIXAAkJlRV/CADgAQAXAAkJlRV/CADgAQAAAA==.Kami:BAABLgAECn80AAIdAAkJ1xNbGQDPAQAdAAkJ1xNbGQDPAQAAAA==.Kapslock:BAAALgAECgYJBwAAAA==.Karii:BAAALgADCgEJAQAAAA==.Karma:BAAALgADCgcJHAAAAA==.Katsicle:BAABLgAECn8fAAIFAAgJfAPEvADxAAAFAAgJfAPEvADxAAAAAA==.Kattastrophy:BAAALgAECgQJBAAAAA==.Katteya:BAAALgADCgkJMQAAAA==.Kattia:BAABLgAECn8mAAIRAAkJ8AwySQCuAQARAAkJ8AwySQCuAQAAAA==.Kazmoru:BAAALgAECgEJAQAAAA==.',
Kh='Khalico:BAAALgADCgEJAQAAAA==.Khellendros:BAAALgADCgUJBQABLgAECgYJCgABAAAAAA==.Khir:BAAALgAECgQJBwAAAA==.',
Ki='Kinomihime:BAABLgAECn83AAIFAAkJ3w8aWAC8AQAFAAkJ3w8aWAC8AQAAAA==.Kirajoy:BAABLgAECn9EAAIJAAkJewabEgAGAQAJAAkJewabEgAGAQAAAA==.Kirel:BAAALgADCgEJAQAAAA==.Kithri:BAAALgADCgEJAQAAAA==.',
Kn='Knyghtt:BAABLgAECn8jAAINAAgJDw/ZLwB6AQANAAgJDw/ZLwB6AQAAAA==.',
Ko='Kogwyn:BAAALgAECggJEQAAAA==.Kogy:BAAALgADCgcJBgABLgAECggJEQABAAAAAA==.',
Kr='Kraviz:BAAALgAECgYJDQAAAA==.Krombopolous:BAAALgADCgkJGQABLgAECggJKQARAHsMAA==.Krystle:BAABLgAECn8lAAIRAAkJqRZMKQAiAgARAAkJqRZMKQAiAgAAAA==.',
Ky='Kydormu:BAAALgADCgEJAQAAAA==.',
['Kä']='Käyfex:BAAALgAECgQJBAAAAA==.',
Le='Leftyloose:BAAALgADCgkJBAAAAA==.',
Li='Lilfonz:BAABLgAECn8aAAMYAAcJdhDiOABRAQAYAAcJdhDiOABRAQAfAAYJsxgVnQBEAQAAAA==.Livik:BAABLgAECn8YAAISAAkJzxwLAwBlAgASAAkJzxwLAwBlAgAAAA==.',
Lo='Lockofdeath:BAAALgADCgYJBwAAAA==.Lockywolf:BAAALgAECgUJBgAAAA==.Logarth:BAAALgAECgYJDAAAAA==.Longbrew:BAAALgADCgEJAQAAAA==.Loppsang:BAAALgAECgYJDgAAAA==.Lorcan:BAABLgAECn82AAIhAAkJdht+CQA8AgAhAAkJdht+CQA8AgAAAA==.',
Lr='Lroye:BAACLgAFFH8OAAIiAAQJnBY4FwA7AQAiAAQJnBY4FwA7AQAuAAQKfxkAAiIABwnqHpoVANoBACIABwnqHpoVANoBAAAA.',
Ls='Lsdarko:BAAALgAECgEJAgAAAA==.',
Lu='Luckyleet:BAAALgADCgQJCwAAAA==.Lucyfer:BAAALgAECgUJCgABLgAECgkJIAARAMULAA==.Lucyferr:BAABLgAECn8YAAIFAAcJKgaouwDyAAAFAAcJKgaouwDyAAABLgAECgkJIAARAMULAA==.Ludacritts:BAAALgAECgQJBAAAAA==.Ludicrispeed:BAAALgADCgYJFAAAAA==.Luliak:BAACLgAFFH8OAAIQAAUJNiJ7CQBrAQAQAAUJNiJ7CQBrAQAuAAQKfx0AAhAACAlpIj8JAH0CABAACAlpIj8JAH0CAAAA.Lunabren:BAABLgAECn8YAAMVAAcJwweRQwDiAAAVAAcJwweRQwDiAAAUAAIJoQZRtgBDAAAAAA==.Lunamina:BAAALgAECgMJBQAAAA==.',
Ly='Lynvala:BAAALgADCgQJBQAAAA==.Lysdexíc:BAABLgAECn8YAAIaAAgJjxMYUAB+AQAaAAgJjxMYUAB+AQAAAA==.',
['Lì']='Lìllith:BAABLgAECn8qAAMIAAkJLB3ECwCTAgAIAAkJLB3ECwCTAgAjAAQJIwrgTgCXAAABLgAFFAIJBwAfANcbAA==.',
Ma='Majika:BAAALgADCgYJBQAAAA==.Mariophra:BAABLgAECn8wAAILAAgJqRuGGgBcAgALAAgJqRuGGgBcAgAAAA==.Marvelious:BAAALgAFFAEJAQAAAA==.Mattlen:BAAALgADCgYJCAAAAA==.Maximumswag:BAAALgADCgkJGwABLgAECggJKQARAHsMAA==.Maxmugruith:BAAALgADCgQJBwAAAA==.',
Mc='Mcnastyqt:BAAALgAECgQJBAAAAA==.',
Me='Meatshiéld:BAAALgAECgYJCgAAAA==.',
Mi='Midopamos:BAAALgADCgEJAQAAAA==.Mikki:BAAALgAECgYJDgAAAA==.Missconduct:BAAALgADCgYJBgAAAA==.Misstorgo:BAABLgAECn8XAAIMAAYJkSCxEADGAQAMAAYJkSCxEADGAQAAAA==.',
Mo='Monfro:BAAALgAECgcJDwAAAA==.Moogatoo:BAAALgAECgYJCAAAAA==.Moonbane:BAABLgAECn8sAAIJAAgJUCATAwBYAgAJAAgJUCATAwBYAgAAAA==.Moonfanda:BAAALgADCgIJAgAAAA==.Moonmist:BAAALgADCgEJAQABLgAECgYJBwABAAAAAA==.Moor:BAAALgAECgYJDAAAAA==.',
Mu='Mumferd:BAAALgADCgQJBAAAAA==.',
My='Myaquean:BAAALgADCgUJEwAAAA==.Mystogan:BAAALgAECgcJDgAAAA==.Myth:BAAALgADCgUJBQAAAA==.',
Na='Nakeefa:BAABLgAECn8nAAMCAAkJdBSZLQAWAgACAAkJdBSZLQAWAgAJAAEJAAA9cgAzAAAAAA==.Natsuu:BAABLgAECn8lAAMRAAkJOBu0OwDZAQARAAgJihy0OwDZAQAQAAQJwA5eMgAIAQAAAA==.Naturewolf:BAABLgAECn8eAAIDAAgJXRayEQB6AQADAAgJXRayEQB6AQAAAA==.',
Ne='Nefertiti:BAAALgAECgcJCAAAAA==.Nekona:BAABLgAECn8VAAQCAAgJTwuEiQBGAQACAAgJTwuEiQBGAQAJAAIJCgmuWwBcAAAcAAEJlwWVNAAzAAAAAA==.Neron:BAACLgAFFH8HAAIfAAIJ1xsObQCoAAAfAAIJ1xsObQCoAAAuAAQKfzwAAh8ACQlYIA0XAKMCAB8ACQlYIA0XAKMCAAAA.Nethertusk:BAABLgAECn8uAAMCAAkJTBnZLAAZAgACAAkJTBnZLAAZAgAJAAIJYQP2WQBhAAAAAA==.',
Nh='Nhancecntrl:BAABLgAECn8lAAIKAAkJlxpTBACZAgAKAAkJlxpTBACZAgAAAA==.',
Ni='Niany:BAAALgAECgYJCQAAAA==.Nightbréaker:BAAALgADCgcJFQAAAA==.Nilospite:BAABLgAECn8oAAIMAAgJQR5/CABeAgAMAAgJQR5/CABeAgABLgAFFAYJHQAHANkYAA==.Nimposter:BAABLgAECn8mAAIPAAgJUhi0RgDbAQAPAAgJUhi0RgDbAQAAAA==.',
Nj='Njoror:BAAALgADCgQJBAAAAA==.',
No='Noodle:BAAALgADCgEJAQAAAA==.Nottapally:BAAALgAECgcJEgABLgAECggJFAATAEIUAA==.',
Nu='Nullea:BAAALgAECgYJCAAAAA==.',
Ny='Nyxthos:BAAALgADCggJCAAAAA==.',
Ob='Obizi:BAAALgAECgEJAQAAAA==.',
Oc='Ocatarineta:BAAALgADCgIJAgAAAA==.',
Od='Odine:BAAALgAECgEJAQAAAA==.Odito:BAABLgAECn8VAAIVAAYJpRelKwBdAQAVAAYJpRelKwBdAQAAAA==.',
Om='Omegalich:BAAALgAECgEJAQAAAA==.',
Oo='Oopslol:BAAALgAECgYJDAAAAA==.',
Os='Osdavalmarro:BAAALgADCgYJGQAAAA==.',
Ot='Othaerion:BAABLgAECn8YAAIYAAkJbw/MJgC9AQAYAAkJbw/MJgC9AQAAAA==.',
Ou='Outerlimits:BAABLgAECn8uAAIkAAgJMRiECQC9AQAkAAgJMRiECQC9AQAAAA==.',
Pa='Paindore:BAAALgAECgQJBAAAAA==.Pamboo:BAABLgAECn8xAAIYAAkJzg+kIQDhAQAYAAkJzg+kIQDhAQAAAA==.',
Pe='Pearle:BAABLgAECn8oAAIHAAkJQx4NCgBaAgAHAAkJQx4NCgBaAgAAAA==.',
Ph='Phyg:BAAALgAECgQJBQABLgAECgUJBwABAAAAAA==.',
Po='Pokimane:BAAALgADCggJDwAAAA==.Polyasap:BAAALgADCgQJBAAAAA==.',
Pr='Pringo:BAAALgAFFAIJAgAAAA==.Proximal:BAAALgAECgcJBwAAAA==.',
Pu='Pukka:BAAALgADCgcJEQABLgAECgkJJAAIADUaAA==.Punk:BAAALgAFFAEJAQAAAA==.',
Qa='Qahnaarin:BAAALgADCgEJAQAAAA==.',
Ra='Rajax:BAAALgAECgcJDQAAAA==.Ralphthedh:BAAALgAECgkJDwAAAA==.Ramindizzle:BAABLgAECn86AAIXAAkJcBazBwD0AQAXAAkJcBazBwD0AQAAAA==.Rangewolf:BAAALgADCgcJDgAAAA==.',
Re='Rejuvasap:BAABLgAECn8aAAQVAAgJMBpWKQC1AQAVAAgJMBpWKQC1AQAUAAUJ6R3qNwClAQADAAMJqhfbLQCGAAAAAA==.Rekki:BAAALgADCgEJAQAAAA==.Reliri:BAAALgADCgMJAwAAAA==.Remlin:BAAALgADCgcJCAAAAA==.Retsall:BAAALgADCgUJBQAAAA==.Reâper:BAAALgAECgYJCgAAAA==.',
Ri='Rikal:BAAALgADCgYJEAAAAA==.',
Ro='Rook:BAABLgAECn82AAIXAAkJ8A0+DACJAQAXAAkJ8A0+DACJAQAAAA==.Roye:BAACLgAFFH8UAAIfAAUJbBeKMAAzAQAfAAUJbBeKMAAzAQAuAAQKfx4AAh8ACQl1HbYaAMkCAB8ACQl1HbYaAMkCAAAA.',
Ru='Ruffiyo:BAABLgAECn8wAAMaAAkJtRSgOQDJAQAaAAkJrxOgOQDJAQAeAAgJ3Q+LLQBfAQAAAA==.Rugrahfreaky:BAACLgAFFH8GAAIUAAMJURMjNQDIAAAUAAMJURMjNQDIAAAuAAQKfzkAAhQACQl6IXoEAGYDABQACQl6IXoEAGYDAAAA.Rugrahh:BAABLgAECn8pAAMXAAkJux5MDwDGAgAXAAkJux5MDwDGAgAQAAMJaQ/6PQC7AAAAAA==.Rugrahx:BAAALgAFFAIJAgAAAA==.Ruthen:BAAALgAECgYJCwAAAA==.Ruìn:BAAALgAECgcJCQAAAA==.',
Sa='Sabermore:BAABLgAECn8ZAAIfAAgJLBYXRwDZAQAfAAgJLBYXRwDZAQAAAA==.Sabina:BAABLgAECn83AAIOAAkJgAteMgBZAQAOAAkJgAteMgBZAQAAAA==.Sadako:BAAALgAECgYJBwABLgAECgkJIAARAMULAA==.Sadness:BAAALgAECgQJCQAAAA==.Sadorick:BAAALgADCgkJLwAAAA==.Safira:BAAALgAECgQJBgABLgAFFAIJBwAfANcbAA==.Sageguy:BAAALgAECgQJCQAAAA==.Samerle:BAAALgADCgEJAQAAAA==.Sango:BAABLgAECn85AAMeAAkJxhaxDgAaAgAeAAkJxhaxDgAaAgAaAAQJ2gKPwQB8AAAAAA==.Saucewalker:BAABLgAFFH8HAAIPAAUJJxQVTwA1AQAPAAUJJxQVTwA1AQAAAA==.Savagelykill:BAABLgAECn8YAAIHAAYJvwq3MADCAAAHAAYJvwq3MADCAAAAAA==.',
Sc='Scotch:BAABLgAECn8sAAMfAAkJ+BnrLgAsAgAfAAkJ+BnrLgAsAgATAAIJcRHHMQCHAAAAAA==.Scotchnwater:BAAALgAECgYJEwAAAA==.Scrubyheals:BAAALgADCgQJBwABLgAECggJFAATAEIUAA==.',
Se='Sendio:BAAALgAECgQJBAAAAA==.Sendor:BAAALgADCgEJAQAAAA==.Senji:BAAALgADCgQJBAAAAA==.',
Sg='Sgtpayne:BAAALgADCgIJAgAAAA==.',
Sh='Shadowcrwlr:BAAALgAECgMJBgAAAA==.Shadowlock:BAAALgAECggJEwAAAA==.Shadowmane:BAAALgADCgQJBAAAAA==.Shaeixia:BAAALgADCggJCgAAAA==.Shamangroo:BAAALgADCggJCQABLgAECgQJCgABAAAAAA==.Shamanio:BAAALgAECgEJAQAAAA==.Shamichangas:BAAALgAECgEJAQAAAA==.Shammying:BAAALgAECgUJCwAAAA==.Shamsham:BAAALgADCgIJAgAAAA==.Sharaaz:BAAALgAECgIJAwAAAA==.Shivalry:BAAALgADCgkJCwAAAA==.Shmiggy:BAAALgAECgQJBgAAAA==.',
Si='Silverytwo:BAAALgADCgMJAwAAAA==.Silverywine:BAAALgADCgkJCQAAAA==.Silverywolfe:BAAALgAECgQJCQAAAA==.Simony:BAABLgAECn8gAAIfAAgJ0wf7pAAUAQAfAAgJ0wf7pAAUAQABLgAECgkJIAARAMULAA==.Sinton:BAAALgADCgIJAgAAAA==.',
Sk='Skorpyoh:BAAALgADCgYJBgAAAA==.Skovak:BAAALgAECgcJEAAAAA==.Skybright:BAAALgAECggJCwAAAA==.',
So='Soggy:BAAALgAECgcJBwAAAA==.Sorayae:BAABLgAECn8kAAIIAAkJNRr1EwA/AgAIAAkJNRr1EwA/AgAAAA==.',
Sp='Specialk:BAAALgAECgQJBwAAAA==.Spinnykat:BAAALgAECgMJBQAAAA==.Splooshh:BAAALgAECgIJAgABLgAECgkJMAAaALUUAA==.',
St='Starmist:BAAALgADCgMJAwAAAA==.Stinkfoot:BAAALgAECgUJCAAAAA==.Stoo:BAAALgADCgkJHAAAAA==.Stormkissed:BAABLgAECn8VAAMLAAYJmA0jZQAMAQALAAYJmA0jZQAMAQAOAAEJQAK2qgAcAAAAAA==.Stormweaver:BAAALgAECgUJBQAAAA==.',
Su='Sunil:BAABLgAECn82AAIIAAkJiBp8CQC7AgAIAAkJiBp8CQC7AgAAAA==.Suviqhabo:BAAALgAECggJDwAAAA==.',
Sv='Svala:BAAALgADCgYJBgAAAA==.',
Sy='Syclone:BAABLgAECn8zAAIMAAkJECZtAABzAwAMAAkJECZtAABzAwAAAA==.Syladen:BAAALgAECgYJEgAAAA==.Syleste:BAAALgAECgQJBAABLgAECgkJMwAMABAmAA==.Syvi:BAAALgAECgYJCQABLgAECggJEQABAAAAAA==.',
Ta='Tahwe:BAAALgADCgUJBQAAAA==.Tattianna:BAAALgAECgQJCgAAAA==.Tavendar:BAAALgAECgMJAwABLgAFFAQJEwALAHEUAA==.Tavil:BAAALgADCgMJAwAAAA==.Taírn:BAAALgAECgYJEAAAAA==.',
Te='Techie:BAABLgAECn8XAAMlAAgJRhIjKAC6AQAlAAgJRhIjKAC6AQAmAAUJpASfYgC4AAAAAA==.Terradactyl:BAAALgADCgMJAwAAAA==.',
Th='Thunderslate:BAABLgAECn8UAAITAAgJQhS7EACfAQATAAgJQhS7EACfAQAAAA==.Thôrin:BAAALgADCgkJFQAAAA==.',
Ti='Tigerlillee:BAAALgADCgcJDQAAAA==.Tigreth:BAABLgAECn82AAMfAAkJ1hTQRwDXAQAfAAkJ1hTQRwDXAQATAAIJlhSvNgBoAAAAAA==.Timotheus:BAAALgAECgUJDAAAAA==.',
To='Tonï:BAAALgADCggJCAAAAA==.',
Tr='Tragik:BAABLgAECn8mAAIKAAkJQA75DQC0AQAKAAkJQA75DQC0AQAAAA==.',
Tt='Ttrouble:BAAALgADCgUJBQAAAA==.',
Tu='Tuugadark:BAABLgAECn81AAICAAkJRx0fIABXAgACAAkJRx0fIABXAgAAAA==.Tuugashox:BAAALgAECgUJBQAAAA==.',
Ul='Ulyaoth:BAABLgAECn8yAAICAAcJPgsWfwAwAQACAAcJPgsWfwAwAQAAAA==.',
Un='Unnerfable:BAAALgAECgYJCAAAAA==.',
Uw='Uwa:BAAALgADCgMJAwAAAA==.',
Uy='Uy:BAAALgAECgYJDwAAAA==.',
Va='Valakha:BAAALgAECgQJDwAAAA==.Valkyrie:BAAALgAECgQJBgAAAA==.',
Ve='Vedros:BAAALgADCgYJDQAAAA==.Vermouth:BAAALgAECgQJBAAAAA==.',
Vi='Viktoros:BAAALgAECgIJAgAAAA==.Violetra:BAAALgADCgMJAwAAAA==.',
Vo='Vorcan:BAAALgADCgYJBgAAAA==.Vorukh:BAABLgAECn8aAAMDAAkJMhHDDADIAQADAAkJMhHDDADIAQAWAAEJyw9MaQAiAAAAAA==.',
Vr='Vrave:BAAALgADCgQJBQAAAA==.',
Vy='Vyhlet:BAAALgAECgIJBAABLgAECgkJSQALAEIgAA==.',
Wa='Warriorgroo:BAAALgAECgQJCgAAAA==.',
We='Wendish:BAAALgAECgEJCQAAAA==.Wertyda:BAABLgAECn8aAAIYAAkJzhRHIwDWAQAYAAkJzhRHIwDWAQAAAA==.Wetnwild:BAAALgAECgUJBQAAAA==.',
Wh='Whácker:BAABLgAECn8UAAMhAAgJOwpYEgB8AQAhAAgJOwpYEgB8AQAMAAMJrAguOQCBAAABLgAECgYJEAABAAAAAA==.',
Wi='Wickdlovly:BAAALgADCgEJAQABLgAECgYJBwABAAAAAA==.Wickedslicks:BAABLgAECn82AAIVAAkJ/B9iCAC7AgAVAAkJ/B9iCAC7AgAAAA==.Wildthangg:BAAALgAECgIJAgAAAA==.',
Wo='Wooddchipper:BAAALgADCgYJBgAAAA==.',
Wr='Wreckshop:BAABLgAECn8YAAIPAAkJGxmlSQDTAQAPAAkJGxmlSQDTAQAAAA==.',
Wt='Wtfoxtrot:BAAALgADCgkJDAAAAA==.',
Xe='Xenøcide:BAAALgAECgcJEwAAAA==.',
Xx='Xxlockz:BAABLgAECn8eAAMCAAgJWxGUeQA7AQACAAcJiw6UeQA7AQAJAAMJGRGVHQCnAAAAAA==.Xxpallyz:BAAALgAECggJCwABLgAECggJHgACAFsRAA==.',
Yi='Yinger:BAAALgADCgcJEAAAAA==.Yinglang:BAAALgADCgEJAQAAAA==.Yingling:BAABLgAECn8rAAIPAAkJ6RmUOgACAgAPAAkJ6RmUOgACAgAAAA==.',
Yo='Yohh:BAAALgAECgUJDAAAAA==.',
Yu='Yukara:BAAALgADCgYJBgAAAA==.Yulay:BAAALgADCgYJBgAAAA==.Yuriko:BAABLgAECn83AAIlAAkJ1hN2HgD+AQAlAAkJ1hN2HgD+AQAAAA==.',
Za='Zaidan:BAAALgAECgQJBwAAAA==.Zanpaktu:BAAALgAECgYJEgAAAA==.Zaraha:BAAALgADCgEJAQAAAA==.Zata:BAAALgAECgUJBwAAAA==.',
Ze='Zendous:BAAALgAECgcJBwAAAA==.Zeref:BAAALgAECgYJEgAAAA==.Zeur:BAAALgAECgEJAQAAAA==.Zevgrip:BAAALgAECgQJBQAAAA==.',
Zh='Zhia:BAAALgAECgQJBQAAAA==.',
Zi='Zippitydooda:BAAALgADCgQJBAABLgAECgYJBwABAAAAAA==.',
Zo='Zodiacc:BAABLgAECn84AAIWAAkJQxy5BQCNAgAWAAkJQxy5BQCNAgAAAA==.Zornen:BAAALgAECgQJBgAAAA==.Zornhealer:BAAALgAECgUJBgABLgAECgYJEwABAAAAAA==.',
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
