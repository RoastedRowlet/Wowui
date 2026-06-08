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

local lookup = {'Unknown-Unknown','Warlock-Demonology','Druid-Feral','Mage-Arcane','Mage-Frost','Mage-Fire','Druid-Guardian','DeathKnight-Blood','Priest-Holy','Warlock-Destruction','Shaman-Enhancement','Shaman-Restoration','Warrior-Protection','Warrior-Fury','Shaman-Elemental','DeathKnight-Unholy','Hunter-Survival','Hunter-BeastMastery','Rogue-Outlaw','Paladin-Protection','Druid-Restoration','Druid-Balance','Hunter-Marksmanship','Paladin-Holy','Rogue-Assassination','DemonHunter-Devourer','Paladin-Retribution','Priest-Discipline','Warlock-Affliction','Monk-Windwalker','DemonHunter-Havoc','DemonHunter-Vengeance','Warrior-Arms','Rogue-Subtlety','Priest-Shadow','DeathKnight-Frost','Evoker-Preservation','Evoker-Devastation','Monk-Mistweaver','Monk-Brewmaster',}
local provider = {region='US',realm='EchoIsles',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aaelless:BAAALgAECgMJBAAAAA==.Aardz:BAAALgAECgQJBAAAAA==.',
Ab='Abeblinkin:BAAALgADCgkJDgAAAA==.Abrakadavar:BAAALgAECgQJBQAAAA==.Abräxis:BAAALgADCgkJCQABLgAECgMJAwABAAAAAA==.',
Ac='Ackspez:BAAALgADCgYJBgAAAA==.',
Ae='Aeless:BAABLgAECn8dAAICAAkJKyJHCgD5AgACAAkJKyJHCgD5AgAAAA==.Aelless:BAAALgAECgYJCAAAAA==.Aenest:BAAALgADCggJCAAAAA==.',
Ai='Aithinne:BAAALgAECgMJBQAAAA==.',
Ak='Akanah:BAAALgADCgcJBwAAAA==.',
Al='Alch:BAAALgADCgkJEgAAAA==.Alfira:BAAALgAECgYJEwAAAA==.Alghul:BAAALgAECgMJBAABLgAECgYJEwABAAAAAA==.',
Am='Amalthea:BAAALgADCgkJEAAAAA==.Amoredis:BAAALgADCgYJDQAAAA==.Amorlorin:BAAALgADCggJDQAAAA==.',
An='Anklbiterkat:BAAALgADCgQJBAAAAA==.Anume:BAAALgADCgkJFQAAAA==.',
Ar='Aragan:BAAALgAECgQJBwAAAA==.Aravis:BAABLgAECn8cAAIDAAgJewnWGwAZAQADAAgJewnWGwAZAQAAAA==.Arese:BAABLgAECn8fAAQEAAYJTiZ/AwA0AgAEAAUJTiZ/AwA0AgAFAAMJlyTzEgHYAAAGAAEJAABTDABpAAAAAA==.Argopol:BAABLgAECn8ZAAIHAAgJOCH1BQCWAgAHAAgJOCH1BQCWAgABLgAECgkJKAAIAEMeAA==.Aron:BAAALgADCgMJAgAAAA==.',
As='Ashandra:BAAALgADCgkJDwAAAA==.Ashlyssra:BAABLgAECn8fAAIJAAkJYh1XCADZAgAJAAkJYh1XCADZAgAAAA==.Asphonix:BAAALgADCgEJAQAAAA==.',
Aw='Awsomesause:BAAALgAECgQJBgAAAA==.',
Az='Azuri:BAAALgAECgQJBQAAAA==.Azzif:BAABLgAECn8bAAIKAAYJmQKFJgBzAAAKAAYJmQKFJgBzAAAAAA==.Azzraell:BAAALgADCgEJAQAAAA==.',
Ba='Babaorumm:BAAALgAECgQJBAAAAA==.Babasha:BAACLgAFFH8JAAILAAQJ6Qv7CQANAQALAAQJ6Qv7CQANAQAuAAQKfxsAAwsABgmSHyYPALEBAAsABgmSHyYPALEBAAwABgnADcJPAEUBAAAA.Babybluz:BAABLgAECn8hAAIFAAgJJgfVsgAZAQAFAAgJJgfVsgAZAQAAAA==.Baconloaf:BAAALgAECgUJCQAAAA==.Baifeng:BAAALgADCgkJDwAAAA==.Baldilocks:BAAALgADCgQJDAAAAA==.Barlas:BAAALgAECgEJAQAAAA==.Bat:BAAALgADCgEJAQAAAA==.',
Be='Beauriley:BAABLgAECn8xAAMNAAkJHBVkEgC4AQANAAkJHBVkEgC4AQAOAAEJnA4RlAA7AAAAAA==.Behomethan:BAABLgAECn8mAAMMAAkJZBtJKgDlAQAMAAgJOBpJKgDlAQAPAAgJABT+LwBxAQAAAA==.Beyonsláy:BAAALgAECgYJCwAAAA==.',
Bh='Bhipbookie:BAAALgAECgEJBAAAAA==.',
Bi='Billbetaray:BAAALgADCgMJAwAAAA==.',
Bl='Bluerift:BAAALgADCgEJAQAAAA==.Blux:BAAALgAECgEJAQAAAA==.',
Bo='Bobbyb:BAABLgAECn8XAAIQAAcJyxl4UgDFAQAQAAcJyxl4UgDFAQAAAA==.Bolton:BAAALgADCgIJAgAAAA==.Bombchele:BAAALgAECgYJBgABLgAECgkJGQAQAPMaAA==.Boneulngtime:BAAALgADCgUJCgAAAA==.Boon:BAAALgAECgIJAgAAAA==.Bowlofwrong:BAAALgAECgYJBwAAAA==.',
Br='Bratticusrex:BAABLgAECn8fAAIOAAgJ5wgvPgBEAQAOAAgJ5wgvPgBEAQAAAA==.Bresowar:BAAALgAECgYJBwAAAA==.',
Bu='Bunnylicious:BAABLgAECn87AAIMAAkJxyWxAADSAwAMAAkJxyWxAADSAwAAAA==.Bunnymedic:BAAALgAECgYJEAABLgAECgkJOwAMAMclAA==.',
Ca='Caebrylla:BAABLgAECn85AAIRAAkJfw7IEwAEAgARAAkJfw7IEwAEAgAAAA==.Calistie:BAAALgAECgIJAgAAAA==.Camigatu:BAAALgADCgQJBAAAAA==.Camil:BAAALgAECgcJDgABLgAFFAIJBwASAKkHAA==.Cang:BAAALgAECgIJAgAAAA==.Capulin:BAABLgAECn8kAAIOAAkJsBbrGwAIAgAOAAkJsBbrGwAIAgAAAA==.Catdurid:BAAALgADCgYJBgAAAA==.',
Ce='Cecilbrown:BAAALgADCgcJBgAAAA==.Cecimorte:BAABLgAECn83AAIIAAkJehlzDAA5AgAIAAkJehlzDAA5AgAAAA==.Cephalopod:BAABLgAECn8UAAITAAgJ1RXEAwD5AQATAAgJ1RXEAwD5AQAAAA==.',
Ch='Chargeasap:BAAALgAECgMJAwAAAA==.Charttopper:BAAALgAECgYJCQABLgAECggJFAAUAEIUAA==.Chibby:BAAALgADCgMJAwAAAA==.Chimichanga:BAAALgAECgcJDAABLgAECggJFAAUAEIUAA==.Chonker:BAABLgAECn84AAMVAAkJdSDzBgBAAwAVAAkJdSDzBgBAAwAWAAcJVwwSOAAmAQAAAA==.Chorelock:BAAALgADCgEJAQABLgAECggJFAAUAEIUAA==.Chronormu:BAAALgAECgMJAwAAAA==.Chuckforrest:BAAALgAECgQJBAAAAA==.Chultis:BAABLgAECn8bAAQDAAgJuhTUEQCLAQADAAgJuhTUEQCLAQAWAAEJ2wH5jgAeAAAVAAEJAgLF6QAbAAAAAA==.',
Ci='Cihato:BAABLgAECn83AAIHAAkJIxuJCABWAgAHAAkJIxuJCABWAgAAAA==.',
Cl='Claxious:BAABLgAECn8iAAIXAAkJlRklBgAqAgAXAAkJlRklBgAqAgAAAA==.Claye:BAACLgAFFH8TAAIMAAQJcRQ2MgACAQAMAAQJcRQ2MgACAQAuAAQKfyoAAgwACQnPHCkQAMMCAAwACQnPHCkQAMMCAAAA.',
Co='Coldshoulder:BAABLgAECn83AAMFAAkJwx79GAC9AgAFAAkJwx79GAC9AgAGAAQJaxN6CgC5AAAAAA==.Corelas:BAABLgAECn8jAAIFAAYJ8AiRzQDwAAAFAAYJ8AiRzQDwAAAAAA==.Corfellyn:BAAALgAECggJBAAAAA==.Couchdad:BAAALgAECgYJEwAAAA==.',
Cr='Crazymadman:BAAALgAECgYJDwAAAA==.Crushingblow:BAAALgAECgkJAwAAAA==.',
Cy='Cyon:BAAALgADCgEJAQAAAA==.',
Da='Daalaria:BAAALgADCgEJAQAAAA==.Darkone:BAAALgAECgEJAQAAAA==.Dawnson:BAABLgAECn8oAAIYAAkJbCDuBAA9AwAYAAkJbCDuBAA9AwAAAA==.',
De='Deadzexcs:BAABLgAECn8UAAIZAAUJbAsnFQDNAAAZAAUJbAsnFQDNAAAAAA==.Deathsnear:BAAALgAECgEJAQAAAA==.Demogless:BAABLgAECn8oAAIaAAgJjgvcbAA9AQAaAAgJjgvcbAA9AQAAAA==.Desyrel:BAAALgAECgYJBgABLgAECgkJIQAbANIHAA==.Devyn:BAAALgADCgUJBQAAAA==.',
Dh='Dharknight:BAAALgAECgEJAQAAAA==.',
Di='Didimissfire:BAEBLgAECn87AAISAAkJlxT8MwABAgASAAkJlxT8MwABAgAAAA==.',
Do='Donaghy:BAAALgAECgEJAQAAAA==.Dooms:BAAALgADCgcJBwAAAA==.',
Dp='Dpsmaster:BAABLgAECn8eAAIWAAcJ5AVkTgDEAAAWAAcJ5AVkTgDEAAAAAA==.',
Dr='Dranalis:BAAALgAECgYJBwAAAA==.Drdrake:BAAALgADCgcJFAAAAA==.Dredlok:BAAALgAECgQJBwAAAA==.Drufiyo:BAAALgAECgUJBQABLgAECgkJMAAaALUUAA==.',
Du='Dumonster:BAABLgAECn8ZAAIOAAYJyAVwZAC8AAAOAAYJyAVwZAC8AAAAAA==.',
['Dø']='Døll:BAAALgADCgYJBgAAAA==.',
Ea='Eamishal:BAAALgADCgEJAQAAAA==.',
Ei='Eightace:BAAALgAECgQJBgAAAA==.Eirenne:BAAALgAECgYJBwAAAA==.',
Ek='Ekaru:BAAALgADCgEJAQAAAA==.',
El='Elethryia:BAAALgAECgcJDQAAAA==.Elev:BAAALgAECgQJBgAAAA==.Elindril:BAAALgAECgYJEwAAAA==.',
En='Enoth:BAAALgAECgYJDQAAAA==.',
Eo='Eowynn:BAABLgAECn8mAAIMAAkJ7h/4BwAnAwAMAAkJ7h/4BwAnAwAAAA==.',
Er='Erewhon:BAAALgADCgkJCQAAAA==.',
Es='Estella:BAABLgAECn8hAAIFAAYJ7g3HvgAGAQAFAAYJ7g3HvgAGAQAAAA==.',
Ev='Eventhorizon:BAAALgAECgkJBgAAAA==.Evielli:BAAALgADCgUJBQAAAA==.',
Fa='Faeriefire:BAAALgADCggJDQAAAA==.Fanna:BAAALgADCgMJAwAAAA==.Fatbox:BAABLgAECn8jAAIOAAkJMSC8KACwAQAOAAkJMSC8KACwAQAAAA==.Faythh:BAABLgAECn8xAAMJAAkJfiH5BgD2AgAJAAkJfiH5BgD2AgAcAAEJVhuAZwBNAAAAAA==.',
Fe='Fearblade:BAAALgAECgUJDAAAAA==.Fedoran:BAABLgAECn8iAAQDAAkJRB+nCABTAgADAAcJyyGnCABTAgAVAAcJbRFxQQCCAQAWAAYJnBxYTgDwAAAAAA==.Felasap:BAAALgAECgcJCAAAAA==.Fenastic:BAABLgAECn8nAAMCAAkJIgfbcgBPAQACAAkJqAbbcgBPAQAdAAMJEAYsHACRAAAAAA==.Fenrisúlfur:BAAALgAECgUJDQAAAA==.Feyrah:BAAALgAECggJCwABLgAECgkJJgAMAO4fAA==.',
Fi='Filthy:BAAALgAECgkJCQAAAA==.Fiobhe:BAABLgAECn8hAAIYAAYJfRnTLACiAQAYAAYJfRnTLACiAQAAAA==.Fixeruper:BAABLgAECn8cAAIJAAgJswGFSQCvAAAJAAgJswGFSQCvAAAAAA==.',
Fl='Flaggedname:BAAALgADCgMJAwABLgAECggJFAAUAEIUAA==.Flubberduck:BAAALgADCggJEAAAAA==.Fluffybeer:BAABLgAECn8gAAIQAAgJrh2xOAAVAgAQAAgJrh2xOAAVAgAAAA==.',
Fo='Fonz:BAAALgAECgYJBgABLgAECgcJGgAYAHYQAA==.Footdig:BAABLgAECn8zAAIVAAkJfSO5AwB9AwAVAAkJfSO5AwB9AwAAAA==.',
Fu='Fuquan:BAAALgAECgYJCgAAAA==.',
Fw='Fwd:BAAALgADCgIJAgAAAA==.',
Ga='Gadzook:BAAALgADCggJFQAAAA==.Garthok:BAAALgADCggJCAAAAA==.Gatolun:BAAALgADCgUJBQAAAA==.',
Gi='Giline:BAAALgAECgEJAQAAAA==.Gimp:BAAALgADCgEJAQAAAA==.Ginja:BAAALgADCgIJAgAAAA==.',
Gl='Glenlizzo:BAEALgADCgYJDQABLgAECgYJFAAHAEoaAA==.Glenroyce:BAEBLgAECn8UAAIHAAYJShoPGQB0AQAHAAYJShoPGQB0AQAAAA==.Gless:BAAALgAECgQJDQAAAA==.',
Go='Goodfine:BAAALgADCgcJDwAAAA==.Goss:BAAALgAECgMJAwAAAA==.Goteem:BAAALgADCggJDAAAAA==.',
Gr='Grandcross:BAAALgADCgMJAwAAAA==.Griimtotem:BAAALgAECgQJBAAAAA==.',
Gu='Gungnir:BAABLgAECn8XAAIeAAgJnRhvFgD2AQAeAAgJnRhvFgD2AQAAAA==.Gush:BAAALgADCgQJBAAAAA==.Guttertrash:BAAALgAECgIJAgAAAA==.',
Ha='Hae:BAAALgADCgEJAQAAAA==.Haenus:BAAALgAECgYJBgAAAA==.Haill:BAAALgAECgYJBwAAAA==.Hamhock:BAABLgAECn8hAAIfAAcJ8R3EEAAMAgAfAAcJ8R3EEAAMAgABLgAECgkJIwAOADEgAA==.Hammered:BAEALgADCgUJBQABLgAECgYJFAAHAEoaAA==.Hardtobepro:BAAALgAECgcJBwAAAA==.Harleydk:BAAALgADCgUJBQAAAA==.Hawks:BAAALgADCggJCQAAAA==.',
He='Heartsong:BAAALgAECgcJBgAAAA==.',
Ho='Holycrusader:BAABLgAECn8YAAIbAAgJWBJIXQDLAQAbAAgJWBJIXQDLAQAAAA==.Hoop:BAAALgADCgUJDQAAAA==.Hornito:BAAALgAECgYJCAAAAA==.',
Ic='Icerug:BAAALgAECgEJAQAAAA==.',
Ih='Ihatepallys:BAAALgAECgUJCQAAAA==.',
Ii='Iikeomgikr:BAAALgADCgEJAQAAAA==.',
Il='Ilduca:BAAALgADCgUJBQAAAA==.Ilidank:BAABLgAECn8aAAIaAAcJxByBMAD5AQAaAAcJxByBMAD5AQAAAA==.Ilya:BAAALgAECgUJCwABLgAECggJKQAbAHcbAA==.',
Im='Impotence:BAAALgADCgMJAwAAAA==.',
In='Indigo:BAABLgAECn9PAAMMAAkJ+SCjBQBOAwAMAAkJ+SCjBQBOAwAPAAMJDxpmUADlAAAAAA==.Innax:BAAALgADCgEJAQAAAA==.Innron:BAABLgAECn8xAAMfAAkJSxESGACyAQAfAAkJSxESGACyAQAgAAIJWwMSLwA7AAAAAA==.',
Ir='Irisblue:BAAALgADCgkJDwAAAA==.',
Iy='Iyahli:BAAALgAECgUJDwAAAA==.',
Ja='Jaedia:BAAALgADCgYJCQAAAA==.Jarclian:BAACLgAFFH8NAAIFAAQJNhDDXAAmAQAFAAQJNhDDXAAmAQAuAAQKfz4AAgUACQnRIhYQAPYCAAUACQnRIhYQAPYCAAAA.Jaymonk:BAAALgAECgkJDgAAAA==.Jazmon:BAAALgAECgIJAgAAAA==.',
Je='Jezzea:BAAALgADCgkJEgAAAA==.',
Ji='Jimlaheys:BAAALgAECgYJDgAAAA==.Jinjix:BAAALgAECgEJAQAAAA==.Jitt:BAAALgAECgUJEAAAAA==.',
Jo='Jolike:BAAALgADCgQJBAAAAA==.',
['Jâ']='Jâten:BAABLgAECn8WAAIeAAkJxBkVDQBpAgAeAAkJxBkVDQBpAgABLgAFFAYJCQAaAJATAA==.Jâtens:BAACLgAFFH8JAAMaAAYJkBPZKQBnAQAaAAYJkBPZKQBnAQAgAAEJAgS2EgAlAAAuAAQKfyIAAhoACAlxH6QbAGQCABoACAlxH6QbAGQCAAAA.',
Ka='Kaelía:BAAALgAECgcJDAAAAA==.Kair:BAACLgAFFH8IAAIeAAMJLwd1KACeAAAeAAMJLwd1KACeAAAuAAQKfykAAh4ACQnUCiItAEsBAB4ACQnUCiItAEsBAAAA.Kairring:BAABLgAECn8gAAISAAkJxxQrLQAdAgASAAkJxxQrLQAdAgAAAA==.Kame:BAAALgAECgUJBQAAAA==.Kamehameha:BAABLgAECn8YAAIXAAkJlRUdCQDaAQAXAAkJlRUdCQDaAQAAAA==.Kami:BAABLgAECn80AAIeAAkJ1xMYGwDKAQAeAAkJ1xMYGwDKAQAAAA==.Kapslock:BAAALgAECgYJBwAAAA==.Karii:BAAALgADCgEJAQAAAA==.Karma:BAAALgADCgcJHAAAAA==.Katsicle:BAABLgAECn8fAAIFAAgJfAPNwAADAQAFAAgJfAPNwAADAQAAAA==.Kattastrophy:BAAALgAECgYJCgAAAA==.Katteya:BAAALgAECgMJAwAAAA==.Kattia:BAABLgAECn8oAAISAAkJkA44SQC6AQASAAkJkA44SQC6AQAAAA==.Kazmoru:BAAALgAECgEJAQAAAA==.',
Kh='Khalico:BAAALgADCgEJAQAAAA==.Khellendros:BAAALgADCgUJBQABLgAECgYJCgABAAAAAA==.Khir:BAAALgAECgQJBwAAAA==.',
Ki='Kinomihime:BAABLgAECn83AAIFAAkJ3w9IWgDIAQAFAAkJ3w9IWgDIAQAAAA==.Kirajoy:BAABLgAECn9MAAIKAAkJBgeNEwAIAQAKAAkJBgeNEwAIAQAAAA==.Kirel:BAAALgADCgEJAQAAAA==.Kithri:BAAALgADCgEJAQAAAA==.',
Kn='Knyghtt:BAABLgAECn8jAAIOAAgJDw9mMgB6AQAOAAgJDw9mMgB6AQAAAA==.',
Ko='Kogwyn:BAAALgAECggJEQAAAA==.Kogy:BAAALgADCgcJBgABLgAECggJEQABAAAAAA==.',
Kr='Kraviz:BAAALgAECgYJDgAAAA==.Krombopolous:BAAALgADCgkJGQABLgAECgkJLwASAKAQAA==.Krystle:BAABLgAECn8nAAISAAkJqRaMLQAbAgASAAkJqRaMLQAbAgAAAA==.',
Ky='Kydormu:BAAALgADCgEJAQAAAA==.',
['Kä']='Käyfex:BAAALgAECgQJBAAAAA==.',
La='Lazarus:BAAALgAECgkJCQAAAA==.',
Le='Leftyloose:BAAALgADCgkJBAAAAA==.',
Li='Lilfonz:BAABLgAECn8aAAMYAAcJdhBHOwBQAQAYAAcJdhBHOwBQAQAbAAYJsxgVnQBEAQAAAA==.Livik:BAABLgAECn8aAAITAAkJzxxIAwBlAgATAAkJzxxIAwBlAgAAAA==.',
Lo='Lockofdeath:BAAALgADCgYJBwAAAA==.Lockywolf:BAAALgAECgUJBgAAAA==.Logarth:BAAALgAECgYJDAAAAA==.Longbrew:BAAALgADCgEJAQAAAA==.Loppsang:BAAALgAECgYJEgAAAA==.Lorcan:BAABLgAECn82AAIhAAkJdhtRCgA5AgAhAAkJdhtRCgA5AgAAAA==.',
Lr='Lroye:BAACLgAFFH8PAAIiAAQJnBY7GgA4AQAiAAQJnBY7GgA4AQAuAAQKfxkAAiIABwnqHhcXANYBACIABwnqHhcXANYBAAAA.',
Ls='Lsdarko:BAAALgAECgEJAwAAAA==.',
Lu='Luckyleet:BAAALgADCgQJCwAAAA==.Lucyfer:BAAALgAECgUJCgABLgAECgkJIQAbANIHAA==.Lucyferr:BAABLgAECn8ZAAIFAAgJfQUmsAAdAQAFAAgJfQUmsAAdAQABLgAECgkJIQAbANIHAA==.Ludacritts:BAAALgAECgQJBAAAAA==.Ludicrispeed:BAAALgADCgkJFQAAAA==.Luliak:BAACLgAFFH8QAAIRAAYJPCLAAwDGAQARAAYJPCLAAwDGAQAuAAQKfx8AAhEACQnRIvgDAO8CABEACQnRIvgDAO8CAAAA.Lunabren:BAABLgAECn8YAAMWAAcJwwcrRwDhAAAWAAcJwwcrRwDhAAAVAAIJoQbHuwBDAAAAAA==.Lunamina:BAAALgAECgQJCQAAAA==.',
Ly='Lynvala:BAAALgADCgQJBQAAAA==.Lysdexíc:BAABLgAECn8aAAIaAAkJzhO4PgDBAQAaAAkJzhO4PgDBAQAAAA==.',
['Lì']='Lìllith:BAABLgAECn8sAAMJAAkJLB3JDACLAgAJAAkJLB3JDACLAgAjAAQJIwrgTgCXAAABLgAFFAIJBwAbANcbAA==.',
Ma='Majika:BAAALgADCgYJBQAAAA==.Mariophra:BAABLgAECn83AAIMAAkJ1xo4FACdAgAMAAkJ1xo4FACdAgAAAA==.Marvelious:BAAALgAFFAEJAQAAAA==.Mattlen:BAAALgADCgYJCAAAAA==.Maximumswag:BAAALgADCgkJJAABLgAECgkJLwASAKAQAA==.Maxmugruith:BAAALgADCgQJBwAAAA==.',
Mc='Mcnastyqt:BAAALgAECgQJBAAAAA==.',
Me='Meatshiéld:BAAALgAECgYJCgAAAA==.',
Mi='Midopamos:BAAALgADCgEJAQAAAA==.Mikki:BAAALgAECgcJDwAAAA==.Missconduct:BAAALgADCgYJBgAAAA==.Misstorgo:BAABLgAECn8ZAAINAAYJ1yArEQDJAQANAAYJ1yArEQDJAQAAAA==.',
Mo='Monfro:BAAALgAECgcJDwAAAA==.Moogatoo:BAAALgAECgYJCAAAAA==.Moonbane:BAABLgAECn8sAAIKAAgJUCBoAwBVAgAKAAgJUCBoAwBVAgAAAA==.Moonfanda:BAAALgADCgIJAgAAAA==.Moonmist:BAAALgADCgEJAQABLgAECgYJBwABAAAAAA==.Moor:BAAALgAECgYJDAAAAA==.',
Mu='Mumferd:BAAALgADCgQJBAAAAA==.',
My='Myaquean:BAAALgADCgkJFAAAAA==.Mystogan:BAAALgAECgcJEgAAAA==.Myth:BAAALgAECggJCAAAAA==.Mythelea:BAAALgADCgYJBgAAAA==.',
Na='Nakeefa:BAABLgAECn8nAAMCAAkJdBRxMAARAgACAAkJdBRxMAARAgAKAAEJAAA9cgAzAAAAAA==.Natsuu:BAABLgAECn8mAAMSAAkJOBsoQQDTAQASAAgJihwoQQDTAQARAAQJxhF5MgAUAQAAAA==.Naturewolf:BAABLgAECn8eAAIDAAgJXRYmEwB5AQADAAgJXRYmEwB5AQAAAA==.',
Ne='Nefertiti:BAAALgAECgcJCAAAAA==.Nekona:BAABLgAECn8VAAQCAAgJTwuEiQBGAQACAAgJTwuEiQBGAQAKAAIJCgmuWwBcAAAdAAEJlwWVNAAzAAAAAA==.Neron:BAACLgAFFH8HAAIbAAIJ1xt4eQClAAAbAAIJ1xt4eQClAAAuAAQKfzwAAhsACQlYIIoZAKACABsACQlYIIoZAKACAAAA.Nethertusk:BAABLgAECn8uAAMCAAkJTBnpLwATAgACAAkJTBnpLwATAgAKAAIJYQP2WQBhAAAAAA==.',
Nh='Nhancecntrl:BAABLgAECn8mAAILAAkJ0RrFBACWAgALAAkJ0RrFBACWAgAAAA==.',
Ni='Niany:BAAALgAECgYJCwAAAA==.Nightbréaker:BAAALgADCgcJFQAAAA==.Nilospite:BAABLgAECn8oAAINAAgJQR5SCQBXAgANAAgJQR5SCQBXAgABLgAFFAYJHQAIANkYAA==.Nimposter:BAABLgAECn8qAAIQAAkJNRc5NAAlAgAQAAkJNRc5NAAlAgAAAA==.',
Nj='Njoror:BAAALgADCgQJBAAAAA==.',
No='Noodle:BAAALgADCgEJAQAAAA==.Norky:BAAALgAECgUJBQABLgAFFAQJEwAMAHEUAA==.Nottapally:BAAALgAECgcJEgABLgAECggJFAAUAEIUAA==.',
Nu='Nullea:BAAALgAECgYJCAAAAA==.',
Ny='Nyxthos:BAAALgADCggJCAAAAA==.',
Ob='Obizi:BAAALgAECgEJAQAAAA==.',
Oc='Ocatarineta:BAAALgADCgIJAgAAAA==.',
Od='Odine:BAAALgAECgEJAQAAAA==.Odito:BAABLgAECn8VAAIWAAYJpRfhLQBcAQAWAAYJpRfhLQBcAQAAAA==.',
Om='Omegalich:BAAALgAECgEJAQAAAA==.',
Oo='Oopslol:BAAALgAECgYJDAAAAA==.',
Os='Osdavalmarro:BAAALgADCgYJGQAAAA==.',
Ot='Othaerion:BAABLgAECn8YAAIYAAkJbw/lKAC7AQAYAAkJbw/lKAC7AQAAAA==.',
Ou='Outerlimits:BAABLgAECn8uAAIkAAgJMRiVCgDCAQAkAAgJMRiVCgDCAQAAAA==.',
Pa='Paindore:BAAALgAECgQJBAAAAA==.Pamboo:BAABLgAECn8xAAIYAAkJzg+xIwDdAQAYAAkJzg+xIwDdAQAAAA==.',
Pe='Pearle:BAABLgAECn8oAAIIAAkJQx4QCwBUAgAIAAkJQx4QCwBUAgAAAA==.',
Ph='Phyg:BAAALgAECgQJBQABLgAECgUJBwABAAAAAA==.',
Po='Pokimane:BAAALgADCggJDwAAAA==.Polyasap:BAAALgADCgQJBAAAAA==.',
Pr='Pringo:BAAALgAFFAIJAgAAAA==.Proximal:BAAALgAECgcJBwAAAA==.',
Pu='Pukka:BAAALgADCgcJEQABLgAECgkJJAAJADUaAA==.Punk:BAAALgAFFAEJAQAAAA==.',
Qa='Qahnaarin:BAAALgAFFAEJAQAAAA==.',
Ra='Rajax:BAABLgAECn8WAAIOAAkJKhHOHQD5AQAOAAkJKhHOHQD5AQAAAA==.Ralphthedh:BAAALgAECgkJDwAAAA==.Ramindizzle:BAABLgAECn86AAIXAAkJcBZXCADsAQAXAAkJcBZXCADsAQAAAA==.Rangewolf:BAAALgADCgcJDgAAAA==.',
Re='Rejuvasap:BAABLgAECn8aAAQWAAgJMBpWKQC1AQAWAAgJMBpWKQC1AQAVAAUJ6R0VOgCkAQADAAMJqhd2MQCGAAAAAA==.Rekki:BAAALgADCgEJAQAAAA==.Reliri:BAAALgADCgMJAwAAAA==.Remlin:BAAALgADCgcJCAAAAA==.Retsall:BAAALgADCgUJBQAAAA==.Reâper:BAAALgAECgYJCgAAAA==.',
Ri='Rikal:BAAALgADCgYJEAAAAA==.',
Ro='Rook:BAABLgAECn82AAIXAAkJ8A1ODQB/AQAXAAkJ8A1ODQB/AQAAAA==.Roye:BAACLgAFFH8VAAIbAAYJqxS5HgB2AQAbAAYJqxS5HgB2AQAuAAQKfx4AAhsACQl1HbYaAMkCABsACQl1HbYaAMkCAAAA.',
Ru='Ruffiyo:BAABLgAECn8wAAMaAAkJtRT9PADIAQAaAAkJrxP9PADIAQAfAAgJ3Q+LLQBfAQAAAA==.Rugrahfreaky:BAACLgAFFH8GAAIVAAMJURNhOQDCAAAVAAMJURNhOQDCAAAuAAQKfzkAAhUACQl6Ic8EAGQDABUACQl6Ic8EAGQDAAAA.Rugrahh:BAABLgAECn8pAAMXAAkJux5MDwDGAgAXAAkJux5MDwDGAgARAAMJaQ92QAC6AAAAAA==.Rugrahx:BAABLgAFFH8FAAIgAAMJ8BlLBgDmAAAgAAMJ8BlLBgDmAAAAAA==.Ruthen:BAAALgAECgYJCwAAAA==.Ruìn:BAAALgAECgcJCQAAAA==.',
Sa='Sabermore:BAABLgAECn8cAAIbAAgJlxdYQgD1AQAbAAgJlxdYQgD1AQAAAA==.Sabina:BAABLgAECn83AAIPAAkJgAs7NgBRAQAPAAkJgAs7NgBRAQAAAA==.Sadako:BAAALgAECgYJBwABLgAECgkJIQAbANIHAA==.Sadness:BAAALgAECgQJCQAAAA==.Sadorick:BAAALgADCgkJLwAAAA==.Safira:BAAALgAECgQJBgABLgAFFAIJBwAbANcbAA==.Sageguy:BAAALgAECgQJDQAAAA==.Samerle:BAAALgADCgEJAQAAAA==.Sango:BAABLgAECn9CAAMfAAkJjxeZDgArAgAfAAkJjxeZDgArAgAaAAQJ2gKPwQB8AAAAAA==.Saucewalker:BAABLgAFFH8MAAIQAAUJAxqdRQBWAQAQAAUJAxqdRQBWAQAAAA==.Savagelykill:BAABLgAECn8YAAIIAAYJvwp8MwDBAAAIAAYJvwp8MwDBAAAAAA==.',
Sc='Scotch:BAABLgAECn8xAAMbAAkJYRsZKwBKAgAbAAkJYRsZKwBKAgAUAAUJNxUOIgD3AAAAAA==.Scotchnwater:BAABLgAECn8aAAMlAAcJuQ5sFgBgAQAlAAcJuQ5sFgBgAQAmAAMJIwfdGQB0AAAAAA==.Scrubyheals:BAAALgADCgQJBwABLgAECggJFAAUAEIUAA==.',
Se='Sendio:BAAALgAECgQJBAAAAA==.Sendor:BAAALgADCgEJAQAAAA==.Senji:BAAALgADCgQJBAAAAA==.',
Sg='Sgtpayne:BAAALgADCgIJAgAAAA==.',
Sh='Shadowcrwlr:BAAALgAECgQJCgAAAA==.Shadowlock:BAAALgAECggJEwAAAA==.Shadowmane:BAAALgADCgQJBAAAAA==.Shaeixia:BAAALgADCggJCgAAAA==.Shamangroo:BAAALgADCggJCQABLgAECgUJDwABAAAAAA==.Shamanio:BAAALgAECgEJAgAAAA==.Shamichangas:BAAALgAECgEJAQAAAA==.Shammying:BAAALgAECgUJCwAAAA==.Shamsham:BAAALgADCgIJAgAAAA==.Sharaaz:BAAALgAECgMJBgAAAA==.Shivalry:BAAALgADCgkJCwAAAA==.Shmiggy:BAAALgAECgQJBgAAAA==.',
Si='Silverytwo:BAAALgADCgMJAwAAAA==.Silverywine:BAAALgADCgkJCQAAAA==.Silverywolfe:BAAALgAECgQJCQAAAA==.Simony:BAABLgAECn8hAAIbAAkJ0gfWiQBRAQAbAAkJ0gfWiQBRAQAAAA==.Sinton:BAAALgADCgIJAgAAAA==.',
Sk='Skorpyoh:BAAALgADCgYJBgAAAA==.Skovak:BAABLgAECn8VAAIUAAkJkA6rFAB4AQAUAAkJkA6rFAB4AQAAAA==.Skybright:BAAALgAECggJCwAAAA==.',
So='Soggy:BAAALgAECgcJBwAAAA==.Sorayae:BAABLgAECn8kAAIJAAkJNRr1EwA/AgAJAAkJNRr1EwA/AgAAAA==.',
Sp='Specialk:BAAALgAECgQJBwAAAA==.Spinnykat:BAAALgAECgMJBgAAAA==.Splooshh:BAAALgAECgIJAwABLgAECgkJMAAaALUUAA==.',
St='Starmist:BAAALgADCgMJAwAAAA==.Stinkfoot:BAAALgAECgUJCAAAAA==.Stoo:BAAALgADCgkJHAAAAA==.Stormkissed:BAABLgAECn8XAAMMAAYJRw9kYAArAQAMAAYJRw9kYAArAQAPAAEJQAIotQAcAAAAAA==.Stormweaver:BAAALgAECgUJBQAAAA==.',
Su='Sunil:BAABLgAECn8+AAIJAAkJlhs6CQDJAgAJAAkJlhs6CQDJAgAAAA==.Suviqhabo:BAAALgAECggJDwAAAA==.',
Sv='Svala:BAAALgADCgYJBgAAAA==.',
Sy='Syclone:BAABLgAECn8zAAINAAkJECadAABtAwANAAkJECadAABtAwAAAA==.Syladen:BAAALgAECgYJEgAAAA==.Syleste:BAAALgAECgQJBAABLgAECgkJMwANABAmAA==.Syvi:BAAALgAECgYJCQABLgAECggJEQABAAAAAA==.',
Ta='Tahwe:BAAALgADCgUJBQAAAA==.Tattianna:BAAALgAECgQJCgAAAA==.Tavendar:BAAALgAECgMJAwABLgAFFAQJEwAMAHEUAA==.Tavil:BAAALgADCgMJAwAAAA==.Taírn:BAAALgAECgYJEAAAAA==.',
Te='Techie:BAABLgAECn8gAAMnAAkJTRLHIQD7AQAnAAkJTRLHIQD7AQAoAAUJpASfYgC4AAAAAA==.Teeser:BAAALgAECgUJBQAAAA==.Terradactyl:BAAALgADCgMJAwAAAA==.',
Th='Thunderslate:BAABLgAECn8UAAIUAAgJQhQNEgCZAQAUAAgJQhQNEgCZAQAAAA==.Thôrin:BAAALgADCgkJFQAAAA==.',
Ti='Tigerlillee:BAAALgADCgcJDQAAAA==.Tigreth:BAABLgAECn82AAMbAAkJ1hQCTQDWAQAbAAkJ1hQCTQDWAQAUAAIJlhSvNgBoAAAAAA==.Timotheus:BAAALgAECgUJDAAAAA==.',
To='Tonï:BAAALgADCggJCAAAAA==.',
Tr='Tragik:BAABLgAECn8mAAILAAkJQA5CDwCwAQALAAkJQA5CDwCwAQAAAA==.',
Tt='Ttrouble:BAAALgADCgUJBQAAAA==.',
Tu='Tuugadark:BAABLgAECn81AAICAAkJRx0lIgBTAgACAAkJRx0lIgBTAgAAAA==.Tuugashox:BAAALgAECgUJBQAAAA==.',
Ul='Ulyaoth:BAABLgAECn83AAICAAgJjQv6aQBkAQACAAgJjQv6aQBkAQAAAA==.',
Un='Unnerfable:BAAALgAECgYJCAAAAA==.',
Uw='Uwa:BAAALgADCgMJAwAAAA==.',
Uy='Uy:BAAALgAECgYJDwAAAA==.',
Va='Valakha:BAAALgAECgQJDwAAAA==.Valkyrie:BAAALgAECgQJBgAAAA==.',
Ve='Vedros:BAAALgADCgkJDgAAAA==.Vermouth:BAAALgAECgQJBAAAAA==.',
Vi='Viktoros:BAAALgAECgIJAgAAAA==.Violetra:BAAALgADCgMJAwAAAA==.',
Vo='Vorcan:BAAALgADCgYJBgAAAA==.Vorukh:BAABLgAECn8cAAQDAAkJMhHXDQDHAQADAAkJMhHXDQDHAQAVAAIJxg/ipQBeAAAHAAEJyw8PdAAhAAAAAA==.',
Vr='Vrave:BAAALgADCgQJBQAAAA==.',
Vy='Vyhlet:BAAALgAECgYJCgABLgAECgkJTwAMAPkgAA==.',
Wa='Warriorgroo:BAAALgAECgUJDwAAAA==.',
We='Wendish:BAAALgAECgEJCgAAAA==.Wertyda:BAABLgAECn8aAAIYAAkJzhREJQDTAQAYAAkJzhREJQDTAQAAAA==.Wetnwild:BAAALgAECgUJBQAAAA==.',
Wh='Whácker:BAABLgAECn8UAAMhAAgJOwpYEgB8AQAhAAgJOwpYEgB8AQANAAMJrAguOQCBAAABLgAECgYJEAABAAAAAA==.',
Wi='Wickdlovly:BAAALgADCgEJAQABLgAECgYJBwABAAAAAA==.Wickedslicks:BAABLgAECn85AAIWAAkJ/B/MCAC+AgAWAAkJ/B/MCAC+AgAAAA==.Wildthangg:BAAALgAECgIJAgAAAA==.',
Wo='Wooddchipper:BAAALgADCgYJBgAAAA==.',
Wr='Wreckshop:BAABLgAECn8ZAAIQAAkJ8xoHRgDoAQAQAAkJ8xoHRgDoAQAAAA==.',
Wt='Wtfoxtrot:BAAALgADCgkJDAAAAA==.',
Xe='Xenøcide:BAAALgAECgcJEwAAAA==.',
Xx='Xxlockz:BAABLgAECn8lAAMCAAkJWRFhYAB7AQACAAgJ8A5hYAB7AQAKAAMJGRFIHwCmAAAAAA==.Xxpallyz:BAAALgAECggJCwABLgAECgkJJQACAFkRAA==.',
Yi='Yinger:BAAALgADCgcJEAAAAA==.Yinglang:BAAALgADCgEJAQAAAA==.Yingling:BAABLgAECn8rAAIQAAkJ6RlbPgABAgAQAAkJ6RlbPgABAgAAAA==.',
Yo='Yohh:BAAALgAECgUJDAAAAA==.',
Yu='Yukara:BAAALgADCgYJBgAAAA==.Yulay:BAAALgADCgkJBwAAAA==.Yuriko:BAABLgAECn83AAInAAkJ1hMQIQAAAgAnAAkJ1hMQIQAAAgAAAA==.',
Za='Zaidan:BAAALgAECgUJDAAAAA==.Zanpaktu:BAAALgAECgYJEwAAAA==.Zaraha:BAAALgADCgEJAQAAAA==.Zata:BAAALgAECgUJBwAAAA==.',
Ze='Zendous:BAAALgAECgcJBwAAAA==.Zeref:BAAALgAECgYJEgAAAA==.Zeur:BAAALgAECgEJAQAAAA==.Zevgrip:BAAALgAECgQJBQAAAA==.',
Zh='Zhia:BAAALgAECgQJBQAAAA==.',
Zi='Zippitydooda:BAAALgADCgQJBAABLgAECgYJBwABAAAAAA==.',
Zo='Zodiacc:BAABLgAECn84AAIHAAkJQxxaBgCKAgAHAAkJQxxaBgCKAgAAAA==.Zornen:BAAALgAECgQJBgAAAA==.Zornhealer:BAAALgAECgUJBgABLgAECgYJEwABAAAAAA==.',
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
