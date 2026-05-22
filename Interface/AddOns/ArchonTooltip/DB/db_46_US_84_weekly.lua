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

local lookup = {'Unknown-Unknown','Warlock-Demonology','Mage-Arcane','Mage-Frost','Mage-Fire','DeathKnight-Blood','Priest-Holy','Shaman-Enhancement','Shaman-Restoration','Warrior-Protection','Shaman-Elemental','DeathKnight-Unholy','Warrior-Fury','Hunter-Survival','Hunter-BeastMastery','Rogue-Outlaw','Druid-Restoration','Druid-Balance','Druid-Feral','Druid-Guardian','Hunter-Marksmanship','Paladin-Holy','Paladin-Retribution','DemonHunter-Devourer','Priest-Discipline','Warlock-Affliction','DemonHunter-Havoc','DemonHunter-Vengeance','Monk-Windwalker','Warlock-Destruction','Warrior-Arms','Rogue-Subtlety','Priest-Shadow','DeathKnight-Frost','Paladin-Protection','Monk-Mistweaver',}
local provider = {region='US',realm='EchoIsles',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aaelless:BAAALgAECgEJAQAAAA==.',
Ab='Abeblinkin:BAAALgADCgQJBwAAAA==.Abrakadavar:BAAALgAECgQJBQAAAA==.Abräxis:BAAALgADCgkJCQABLgAECgMJAwABAAAAAA==.',
Ac='Ackspez:BAAALgADCgYJBgAAAA==.',
Ae='Aeless:BAABLgAECn8VAAICAAgJayHlDwCYAgACAAgJayHlDwCYAgAAAA==.Aelless:BAAALgAECgMJBQAAAA==.Aenest:BAAALgADCggJCAAAAA==.',
Ai='Aithinne:BAAALgAECgIJAgAAAA==.',
Ak='Akanah:BAAALgADCgcJBwAAAA==.',
Al='Alch:BAAALgADCgkJDgAAAA==.Alfira:BAAALgAECgYJCgAAAA==.Alghul:BAAALgAECgEJAQABLgAECgUJCgABAAAAAA==.',
Am='Amalthea:BAAALgADCgcJBwAAAA==.Amoredis:BAAALgADCgYJBgAAAA==.',
An='Anklbiterkat:BAAALgADCgQJBAAAAA==.Anume:BAAALgADCgQJDgAAAA==.',
Ar='Aravis:BAAALgAECgcJBwAAAA==.Arese:BAABLgAECn8cAAQDAAYJTiZ/AwA0AgADAAUJTiZ/AwA0AgAEAAMJlyTzEgHYAAAFAAEJAABTDABpAAAAAA==.Argopol:BAAALgAECgMJAwABLgAECggJJAAGAMEdAA==.Aron:BAAALgADCgMJAgAAAA==.',
As='Ashandra:BAAALgADCgkJDwAAAA==.Ashlyssra:BAABLgAECn8dAAIHAAgJZh5JBwC3AgAHAAgJZh5JBwC3AgAAAA==.',
Aw='Awsomesause:BAAALgAECgQJBgAAAA==.',
Az='Azuri:BAAALgAECgQJBQAAAA==.Azzif:BAAALgAECgkJEQAAAA==.Azzraell:BAAALgADCgEJAQAAAA==.',
Ba='Babaorumm:BAAALgADCgUJBQAAAA==.Babasha:BAACLgAFFH8FAAIIAAMJwQdgBwDSAAAIAAMJwQdgBwDSAAAuAAQKfxUAAwgABgkfHPMNAGABAAgABQlqIPMNAGABAAkABgnADcJPAEUBAAAA.Babybluz:BAAALgAECgUJCAAAAA==.Baconloaf:BAAALgAECgUJCQAAAA==.Baldilocks:BAAALgADCgQJDAAAAA==.Bat:BAAALgADCgEJAQAAAA==.',
Be='Beauriley:BAABLgAECn8vAAIKAAkJHRX/CwDfAQAKAAkJHRX/CwDfAQAAAA==.Behomethan:BAABLgAECn8mAAMJAAkJZBtJKgDlAQAJAAgJOBpJKgDlAQALAAgJABSHIQCDAQAAAA==.Beyonsláy:BAAALgADCgIJAgAAAA==.',
Bh='Bhipbookie:BAAALgAECgEJBAAAAA==.',
Bi='Billbetaray:BAAALgADCgMJAwAAAA==.',
Bl='Bluerift:BAAALgADCgEJAQAAAA==.',
Bo='Bobbyb:BAAALgAECgYJEQAAAA==.Bombchele:BAAALgAECgYJBgABLgAECggJFwAMAI4aAA==.Boneulngtime:BAAALgADCgUJCgAAAA==.Boon:BAAALgAECgIJAgAAAA==.Bowlofwrong:BAAALgAECgYJBwAAAA==.',
Br='Bratticusrex:BAABLgAECn8YAAINAAYJnAl0QgDoAAANAAYJnAl0QgDoAAAAAA==.Bresowar:BAAALgAECgYJBwAAAA==.',
Bu='Bunnylicious:BAABLgAECn8hAAIJAAgJFiUuAwBLAwAJAAgJFiUuAwBLAwAAAA==.Bunnymedic:BAAALgAECgYJDAABLgAECggJIQAJABYlAA==.',
Ca='Caebrylla:BAABLgAECn8lAAIOAAgJOwxBGQCKAQAOAAgJOwxBGQCKAQAAAA==.Calistie:BAAALgAECgIJAgAAAA==.Camigatu:BAAALgADCgQJBAAAAA==.Camil:BAAALgAECgEJAQABLgAECggJKgAPAE4YAA==.Cang:BAAALgAECgIJAgAAAA==.Capulin:BAABLgAECn8eAAINAAgJmRVbHwClAQANAAgJmRVbHwClAQAAAA==.Catdurid:BAAALgADCgYJBgAAAA==.',
Ce='Cecilbrown:BAAALgADCgMJAwAAAA==.Cecimorte:BAABLgAECn8lAAIGAAgJRRjWDgDHAQAGAAgJRRjWDgDHAQAAAA==.Cephalopod:BAABLgAECn8UAAIQAAgJ1RXEAwD5AQAQAAgJ1RXEAwD5AQAAAA==.',
Ch='Chargeasap:BAAALgAECgMJAwAAAA==.Charttopper:BAAALgAECgYJCQAAAA==.Chibby:BAAALgADCgIJAgAAAA==.Chonker:BAABLgAECn82AAMRAAkJdSBrBABGAwARAAkJdSBrBABGAwASAAYJ4gv7NgDeAAAAAA==.Chorelock:BAAALgADCgEJAQAAAA==.Chronormu:BAAALgAECgMJAwAAAA==.Chuckforrest:BAAALgAECgQJBAAAAA==.Chultis:BAABLgAECn8WAAQTAAcJ+hS4EwAdAQATAAcJ+hS4EwAdAQASAAEJ2wH5jgAeAAARAAEJAgLF6QAbAAAAAA==.',
Ci='Cihato:BAABLgAECn81AAIUAAkJcRpCBQBgAgAUAAkJcRpCBQBgAgAAAA==.',
Cl='Claxious:BAABLgAECn8ZAAIVAAgJFRcICAC0AQAVAAgJFRcICAC0AQAAAA==.Claye:BAACLgAFFH8KAAIJAAQJcAumJAD5AAAJAAQJcAumJAD5AAAuAAQKfyoAAgkACQnPHE8JANMCAAkACQnPHE8JANMCAAAA.',
Co='Coldshoulder:BAABLgAECn8lAAIEAAgJyRtNLAAmAgAEAAgJyRtNLAAmAgAAAA==.Corelas:BAABLgAECn8XAAIEAAYJyQeUsADkAAAEAAYJyQeUsADkAAAAAA==.Corfellyn:BAAALgAECggJBAAAAA==.Couchdad:BAAALgAECgUJCgAAAA==.',
Cr='Crazymadman:BAAALgAECgEJAgAAAA==.Crushingblow:BAAALgAECgkJAwAAAA==.',
Cy='Cyon:BAAALgADCgEJAQAAAA==.',
Da='Daalaria:BAAALgADCgEJAQAAAA==.Darkone:BAAALgADCgUJBQAAAA==.Dawnson:BAABLgAECn8fAAIWAAcJDx7eEwAlAgAWAAcJDx7eEwAlAgAAAA==.',
De='Deadzexcs:BAAALgAECgUJDQAAAA==.Deathsnear:BAAALgAECgEJAQAAAA==.Demogless:BAAALgAECgYJEgAAAA==.Desyrel:BAAALgAECgYJBgABLgAECgcJHgAXAPcGAA==.Devyn:BAAALgADCgUJBQAAAA==.',
Dh='Dharknight:BAAALgAECgEJAQAAAA==.',
Di='Didimissfire:BAEBLgAECn8yAAIPAAkJZBMrJwDzAQAPAAkJZBMrJwDzAQAAAA==.',
Do='Donaghy:BAAALgAECgEJAQAAAA==.Dooms:BAAALgADCgcJBwAAAA==.',
Dp='Dpsmaster:BAAALgAECgYJEwAAAA==.',
Dr='Dranalis:BAAALgAECgYJBwAAAA==.Drdrake:BAAALgADCgcJFAAAAA==.Dredlok:BAAALgADCgkJFwAAAA==.Drufiyo:BAAALgAECgUJBQABLgAECgkJLgAYAH0UAA==.',
Du='Dumonster:BAAALgAECgYJDgAAAA==.',
['Dø']='Døll:BAAALgADCgYJBgAAAA==.',
Ea='Eamishal:BAAALgADCgEJAQAAAA==.',
Ei='Eightace:BAAALgAECgEJAQAAAA==.Eirenne:BAAALgAECgYJBwAAAA==.',
Ek='Ekaru:BAAALgADCgEJAQAAAA==.',
El='Elethryia:BAAALgAECgIJBQAAAA==.Elev:BAAALgADCgYJDAAAAA==.Elindril:BAAALgAECgYJDwAAAA==.',
En='Enoth:BAAALgAECgUJCAAAAA==.',
Eo='Eowynn:BAABLgAECn8cAAIJAAgJhhlCGAAzAgAJAAgJhhlCGAAzAgAAAA==.',
Er='Erewhon:BAAALgADCgkJCQAAAA==.',
Es='Estella:BAABLgAECn8cAAIEAAYJUQvPnwABAQAEAAYJUQvPnwABAQAAAA==.',
Ev='Eventhorizon:BAAALgAECgkJBgAAAA==.Evielli:BAAALgADCgUJBQAAAA==.',
Fa='Faeriefire:BAAALgADCgQJBQAAAA==.Fanna:BAAALgADCgMJAwAAAA==.Fatbox:BAABLgAECn8eAAINAAgJ+h4FMwDfAQANAAgJ+h4FMwDfAQAAAA==.Faythh:BAABLgAECn8vAAMHAAkJfiHMAwAWAwAHAAkJfiHMAwAWAwAZAAEJVhuXTQBOAAAAAA==.',
Fe='Fearblade:BAAALgADCgkJEgAAAA==.Fedoran:BAABLgAECn8gAAQTAAgJgx+nCABTAgATAAYJqiKnCABTAgARAAcJbRGENACBAQASAAYJmBxYTgDwAAAAAA==.Felasap:BAAALgAECgEJAQAAAA==.Fenastic:BAABLgAECn8fAAMCAAgJuwYPdgARAQACAAgJMAYPdgARAQAaAAMJEAYsHACRAAAAAA==.Fenrisúlfur:BAAALgAECgUJDQAAAA==.Feyrah:BAAALgAECgMJAwABLgAECggJHAAJAIYZAA==.',
Fi='Filthy:BAAALgAECgkJCQAAAA==.Fiobhe:BAABLgAECn8VAAIWAAYJ8BbCKAB4AQAWAAYJ8BbCKAB4AQAAAA==.Fixeruper:BAABLgAECn8cAAIHAAgJswHoOQDEAAAHAAgJswHoOQDEAAAAAA==.',
Fl='Flaggedname:BAAALgADCgMJAwAAAA==.Flubberduck:BAAALgADCggJEAAAAA==.Fluffybeer:BAABLgAECn8eAAIMAAgJTh1oKAAYAgAMAAgJTh1oKAAYAgAAAA==.',
Fo='Fonz:BAAALgAECgUJBQABLgAECgcJGgAWAHYQAA==.Footdig:BAABLgAECn8aAAIRAAcJ2CKqDgCgAgARAAcJ2CKqDgCgAgAAAA==.',
Fu='Fuquan:BAAALgAECgMJBAAAAA==.',
Fw='Fwd:BAAALgADCgIJAgAAAA==.',
Ga='Gadzook:BAAALgADCggJFQAAAA==.Gatolun:BAAALgADCgUJBQAAAA==.',
Gi='Giline:BAAALgAECgEJAQAAAA==.Gimp:BAAALgADCgEJAQAAAA==.Ginja:BAAALgADCgIJAgAAAA==.',
Gl='Glenlizzo:BAEALgADCgUJCQABLgAECgUJCAABAAAAAA==.Glenroyce:BAEALgAECgUJCAAAAA==.Gless:BAAALgAECgIJAgAAAA==.',
Go='Goodfine:BAAALgADCgcJDwAAAA==.Goss:BAAALgADCgcJBwAAAA==.',
Gr='Grandcross:BAAALgADCgMJAwAAAA==.',
Gu='Gungnir:BAAALgAECgYJDAAAAA==.Gush:BAAALgADCgQJBAAAAA==.Guttertrash:BAAALgAECgIJAgAAAA==.',
Ha='Hae:BAAALgADCgEJAQAAAA==.Haenus:BAAALgADCgcJCQAAAA==.Haill:BAAALgAECgYJBwAAAA==.Hamhock:BAAALgAECgUJDAABLgAECggJHgANAPoeAA==.Hammered:BAEALgADCgUJBQABLgAECgUJCAABAAAAAA==.Hardtobepro:BAAALgAECgcJBwAAAA==.Harleydk:BAAALgADCgUJBQAAAA==.',
He='Heartsong:BAAALgAECgcJBgAAAA==.',
Ho='Holycrusader:BAABLgAECn8YAAIXAAgJVxJIXQDLAQAXAAgJVxJIXQDLAQAAAA==.',
Ih='Ihatepallys:BAAALgADCgcJEAAAAA==.',
Ii='Iikeomgikr:BAAALgADCgEJAQAAAA==.',
Il='Ilduca:BAAALgADCgQJBAAAAA==.Ilidank:BAAALgAECgYJDAAAAA==.Ilya:BAAALgAECgUJBgAAAA==.',
Im='Impotence:BAAALgADCgMJAwAAAA==.',
In='Indigo:BAABLgAECn8zAAIJAAgJ1B4yDACsAgAJAAgJ1B4yDACsAgAAAA==.Innax:BAAALgADCgEJAQAAAA==.Innron:BAABLgAECn8pAAIbAAgJJBL9EwCNAQAbAAgJJBL9EwCNAQAAAA==.',
Ir='Irisblue:BAAALgADCgQJDgAAAA==.',
Is='Isyclic:BAAALgAECgYJDAABLgAECggJIQAKADshAA==.',
Iy='Iyahli:BAAALgAECgUJDwAAAA==.',
Ja='Jaedia:BAAALgADCgMJAwAAAA==.Jarclian:BAACLgAFFH8MAAIEAAQJNhCMPABBAQAEAAQJNhCMPABBAQAuAAQKfz4AAgQACQnRIicIABEDAAQACQnRIicIABEDAAAA.Jaymonk:BAAALgAECgEJAgAAAA==.Jazmon:BAAALgAECgIJAgAAAA==.',
Je='Jezzea:BAAALgADCgQJCwAAAA==.',
Ji='Jimlaheys:BAAALgAECgYJDgAAAA==.Jitt:BAAALgAECgUJCAAAAA==.',
['Jâ']='Jâtens:BAACLgAFFH8IAAMYAAUJrxQsJgAyAQAYAAUJrxQsJgAyAQAcAAEJAgQUDAAnAAAuAAQKfyIAAhgACAlxH1YSAG8CABgACAlxH1YSAG8CAAAA.',
Ka='Kaelía:BAAALgAECgUJBQAAAA==.Kair:BAABLgAECn8mAAIdAAkJ/QhFIwBCAQAdAAkJ/QhFIwBCAQAAAA==.Kairring:BAAALgAECggJDgAAAA==.Kamehameha:BAABLgAECn8VAAIVAAgJ5RTTCACgAQAVAAgJ5RTTCACgAQAAAA==.Kami:BAABLgAECn80AAIdAAkJ1hPmEQDkAQAdAAkJ1hPmEQDkAQAAAA==.Kapslock:BAAALgAECgYJBwAAAA==.Karii:BAAALgADCgEJAQAAAA==.Karma:BAAALgADCgcJHAAAAA==.Katsicle:BAAALgAECgYJDwAAAA==.Katteya:BAAALgADCgkJMQAAAA==.Kattia:BAABLgAECn8kAAIPAAgJ0Q3BQwB+AQAPAAgJ0Q3BQwB+AQAAAA==.',
Kh='Khalico:BAAALgADCgEJAQAAAA==.Khellendros:BAAALgADCgUJBQABLgAECgYJCgABAAAAAA==.Khir:BAAALgAECgQJBwAAAA==.',
Ki='Kinomihime:BAABLgAECn81AAIEAAkJ3Q8GQwDQAQAEAAkJ3Q8GQwDQAQAAAA==.Kirajoy:BAABLgAECn8yAAIeAAgJYgW4EQDeAAAeAAgJYgW4EQDeAAAAAA==.Kirel:BAAALgADCgEJAQAAAA==.',
Kn='Knyghtt:BAABLgAECn8cAAINAAYJ1Q9VOgAMAQANAAYJ1Q9VOgAMAQAAAA==.',
Ko='Kogwyn:BAAALgAECggJDwAAAA==.Kogy:BAAALgADCgcJBgABLgAECggJDwABAAAAAA==.',
Kr='Kraviz:BAAALgAECgMJBAAAAA==.Krombopolous:BAAALgADCgkJGQABLgAECggJJgAPAFYMAA==.Krystle:BAABLgAECn8ZAAIPAAgJvReMKwDeAQAPAAgJvReMKwDeAQAAAA==.',
Ky='Kydormu:BAAALgADCgEJAQAAAA==.',
['Kä']='Käyfex:BAAALgAECgQJBAAAAA==.',
Le='Leftyloose:BAAALgADCgkJBAAAAA==.',
Li='Lilfonz:BAABLgAECn8aAAMWAAcJdhCBLQBYAQAWAAcJdhCBLQBYAQAXAAYJsxiClQD9AAAAAA==.Livik:BAABLgAECn8UAAIQAAgJ6RyUAwAPAgAQAAgJ6RyUAwAPAgAAAA==.',
Lo='Lockofdeath:BAAALgADCgYJBwAAAA==.Lockywolf:BAAALgAECgUJBgAAAA==.Logarth:BAAALgAECgUJCAAAAA==.Longbrew:BAAALgADCgEJAQAAAA==.Loppsang:BAAALgAECgQJBgAAAA==.Lorcan:BAABLgAECn80AAIfAAkJkxqfBgBEAgAfAAkJkxqfBgBEAgAAAA==.',
Lr='Lroye:BAACLgAFFH8KAAIgAAQJ8xVVDwBJAQAgAAQJ8xVVDwBJAQAuAAQKfxkAAiAABwnsHrsNAPwBACAABwnsHrsNAPwBAAAA.',
Ls='Lsdarko:BAAALgAECgEJAQAAAA==.',
Lu='Luckyleet:BAAALgADCgQJCwAAAA==.Lucyfer:BAAALgAECgUJCgABLgAECgcJHgAXAPcGAA==.Lucyferr:BAAALgAECgUJBQABLgAECgcJHgAXAPcGAA==.Ludicrispeed:BAAALgADCgQJDgAAAA==.Luliak:BAACLgAFFH8NAAIOAAUJNiJhBACGAQAOAAUJNiJhBACGAQAuAAQKfxUAAg4ACAmVH8AJAEQCAA4ACAmVH8AJAEQCAAAA.Lunabren:BAABLgAECn8YAAMSAAcJwwclNgDjAAASAAcJwwclNgDjAAARAAIJoQYCngBDAAAAAA==.Lunamina:BAAALgAECgIJAgAAAA==.',
Ly='Lynvala:BAAALgADCgQJBQAAAA==.Lysdexíc:BAABLgAECn8XAAIYAAgJaBGaTABQAQAYAAgJaBGaTABQAQAAAA==.',
['Lì']='Lìllith:BAABLgAECn8ZAAMHAAgJFRmRHQDyAQAHAAgJFRmRHQDyAQAhAAMJLQngTgCXAAABLgAECgkJOQAXAD4dAA==.',
Ma='Majika:BAAALgADCgYJBQAAAA==.Mariophra:BAABLgAECn8lAAIJAAgJGRpnFQBLAgAJAAgJGRpnFQBLAgAAAA==.Marvelious:BAAALgAFFAEJAQAAAA==.Mattlen:BAAALgADCgYJCAAAAA==.Maximumswag:BAAALgADCgkJCQABLgAECggJJgAPAFYMAA==.Maxmugruith:BAAALgADCgQJBwAAAA==.',
Mc='Mcnastyqt:BAAALgAECgQJBAAAAA==.',
Me='Meatshiéld:BAAALgAECgYJCgAAAA==.',
Mi='Midopamos:BAAALgADCgEJAQAAAA==.Mikki:BAAALgADCgcJDAAAAA==.Missconduct:BAAALgADCgYJBgAAAA==.Misstorgo:BAAALgAECgYJDgAAAA==.',
Mo='Monfro:BAAALgAECgcJDwAAAA==.Moogatoo:BAAALgAECgYJCAAAAA==.Moonbane:BAABLgAECn8sAAIeAAgJTyAFAgBpAgAeAAgJTyAFAgBpAgAAAA==.Moonfanda:BAAALgADCgIJAgAAAA==.Moonmist:BAAALgADCgEJAQABLgAECgYJBwABAAAAAA==.Moor:BAAALgAECgEJAQAAAA==.',
Mu='Mumferd:BAAALgADCgQJBAAAAA==.',
My='Myaquean:BAAALgADCgQJDgAAAA==.Mystogan:BAAALgADCgUJCQAAAA==.Myth:BAAALgADCgUJBQAAAA==.',
Na='Nakeefa:BAABLgAECn8bAAMCAAkJMxNgMgDQAQACAAkJMxNgMgDQAQAeAAEJAAA9cgAzAAAAAA==.Natsuu:BAABLgAECn8cAAIPAAgJohr/MgC+AQAPAAgJohr/MgC+AQAAAA==.Naturewolf:BAABLgAECn8eAAITAAgJWhbZDACKAQATAAgJWhbZDACKAQAAAA==.',
Ne='Nefertiti:BAAALgAECgQJAwAAAA==.Nekona:BAABLgAECn8VAAQCAAgJTwuEiQBGAQACAAgJTwuEiQBGAQAeAAIJCgmuWwBcAAAaAAEJlwWVNAAzAAAAAA==.Neron:BAABLgAECn85AAIXAAkJPh3lFgB7AgAXAAkJPh3lFgB7AgAAAA==.Nethertusk:BAABLgAECn8sAAMCAAkJ1haaJQAKAgACAAkJ1haaJQAKAgAeAAIJYQP2WQBhAAAAAA==.',
Nh='Nhancecntrl:BAAALgAECggJEwAAAA==.',
Ni='Niany:BAAALgAECgUJBwAAAA==.Nightbréaker:BAAALgADCgcJFQAAAA==.Nilospite:BAABLgAECn8aAAIKAAcJqBnVDgCsAQAKAAcJqBnVDgCsAQABLgAFFAUJFgAGAEwZAA==.Nimposter:BAABLgAECn8fAAIMAAgJHBOBTwCNAQAMAAgJHBOBTwCNAQAAAA==.',
Nj='Njoror:BAAALgADCgQJBAAAAA==.',
No='Noodle:BAAALgADCgEJAQAAAA==.Nottapally:BAAALgAECgcJEAAAAA==.',
Nu='Nullea:BAAALgAECgYJCAAAAA==.',
Ny='Nyxthos:BAAALgADCggJCAAAAA==.',
Ob='Obizi:BAAALgADCgcJBwAAAA==.',
Oc='Ocatarineta:BAAALgADCgIJAgAAAA==.',
Od='Odito:BAAALgAECgUJCgAAAA==.',
Oo='Oopslol:BAAALgAECgYJDAAAAA==.',
Os='Osdavalmarro:BAAALgADCgYJGQAAAA==.',
Ot='Othaerion:BAABLgAECn8YAAIWAAkJbw+kHQDJAQAWAAkJbw+kHQDJAQAAAA==.',
Ou='Outerlimits:BAABLgAECn8rAAIiAAcJAhupBAANAgAiAAcJAhupBAANAgAAAA==.',
Pa='Paindore:BAAALgAECgQJBAAAAA==.Pamboo:BAABLgAECn8oAAIWAAgJhRBMIwCfAQAWAAgJhRBMIwCfAQAAAA==.',
Pe='Pearle:BAABLgAECn8kAAIGAAgJwR3VCgANAgAGAAgJwR3VCgANAgAAAA==.',
Ph='Phyg:BAAALgAECgQJBQABLgAECgUJBwABAAAAAA==.',
Po='Pokimane:BAAALgADCggJDwAAAA==.Polyasap:BAAALgADCgQJBAAAAA==.',
Pr='Proximal:BAAALgAECgcJBwAAAA==.',
Pu='Pukka:BAAALgADCgcJEQABLgAECgkJIgAHACwZAA==.Punk:BAAALgAFFAEJAQAAAA==.',
Qa='Qahnaarin:BAAALgADCgEJAQAAAA==.',
Ra='Rajax:BAAALgAECgYJBgAAAA==.Ralphthedh:BAAALgAECggJCQAAAA==.Ramindizzle:BAABLgAECn8xAAIVAAkJ8hQMBgD0AQAVAAkJ8hQMBgD0AQAAAA==.Rangewolf:BAAALgADCgcJDgAAAA==.',
Re='Rejuvasap:BAABLgAECn8aAAQSAAgJLxpWKQC1AQASAAgJLxpWKQC1AQARAAUJ6R3XLQClAQATAAMJqhe4IgCJAAAAAA==.Reliri:BAAALgADCgMJAwAAAA==.Remlin:BAAALgADCgcJCAAAAA==.Retsall:BAAALgADCgUJBQAAAA==.Reâper:BAAALgAECgYJCgAAAA==.',
Ri='Rikal:BAAALgADCgQJCgAAAA==.',
Ro='Rook:BAABLgAECn80AAIVAAkJdw16CQCQAQAVAAkJdw16CQCQAQAAAA==.Roye:BAACLgAFFH8OAAIXAAUJdA9IJwA0AQAXAAUJdA9IJwA0AQAuAAQKfx4AAhcACQl1HbYaAMkCABcACQl1HbYaAMkCAAAA.',
Ru='Ruffiyo:BAABLgAECn8uAAMYAAkJfRQeLADOAQAYAAkJdxMeLADOAQAbAAgJ3Q+LLQBfAQAAAA==.Rugrahfreaky:BAABLgAECn8pAAIRAAkJSBznCQDfAgARAAkJSBznCQDfAgAAAA==.Rugrahh:BAABLgAECn8pAAMVAAkJux5MDwDGAgAVAAkJux5MDwDGAgAOAAMJaQ8cMQDEAAAAAA==.Ruthen:BAAALgAECgYJCwAAAA==.Ruìn:BAAALgAECgMJAwAAAA==.',
Sa='Sabermore:BAAALgAECgQJDAAAAA==.Sabina:BAABLgAECn81AAILAAkJWwvdJgBdAQALAAkJWwvdJgBdAQAAAA==.Sadako:BAAALgAECgYJBgABLgAECgcJHgAXAPcGAA==.Sadness:BAAALgAECgIJAgAAAA==.Sadorick:BAAALgADCgkJLwAAAA==.Safira:BAAALgAECgQJBgABLgAECgkJOQAXAD4dAA==.Sageguy:BAAALgAECgIJAgAAAA==.Sango:BAABLgAECn8xAAMbAAkJ9RP/DADzAQAbAAkJ9RP/DADzAQAYAAQJ2gKPwQB8AAAAAA==.Saucewalker:BAAALgAECgMJAwAAAA==.Savagelykill:BAAALgAECgQJDgAAAA==.',
Sc='Scotch:BAABLgAECn8mAAMXAAgJzRr+NwDZAQAXAAgJzRr+NwDZAQAjAAIJcRHHMQCHAAAAAA==.Scotchnwater:BAAALgAECgUJCAAAAA==.Scrubyheals:BAAALgADCgQJBwAAAA==.',
Se='Sendio:BAAALgAECgQJBAAAAA==.Senji:BAAALgADCgQJBAAAAA==.',
Sg='Sgtpayne:BAAALgADCgIJAgAAAA==.',
Sh='Shadowcrwlr:BAAALgAECgMJBgAAAA==.Shadowlock:BAAALgAECggJEwAAAA==.Shadowmane:BAAALgADCgQJBAAAAA==.Shaeixia:BAAALgADCgcJBwAAAA==.Shamangroo:BAAALgADCggJCQABLgAECgMJAwABAAAAAA==.Shammying:BAAALgAECgUJCAAAAA==.Shamsham:BAAALgADCgIJAgAAAA==.Sharaaz:BAAALgADCgUJBQAAAA==.Shivalry:BAAALgADCgkJCwAAAA==.Shmiggy:BAAALgAECgQJBgAAAA==.',
Si='Silverywine:BAAALgADCgkJCQAAAA==.Silverywolfe:BAAALgAECgIJAgAAAA==.Simony:BAABLgAECn8eAAIXAAcJ9wZenQDvAAAXAAcJ9wZenQDvAAAAAA==.Sinton:BAAALgADCgIJAgAAAA==.',
Sk='Skorpyoh:BAAALgADCgYJBgAAAA==.Skovak:BAAALgAECgYJEAAAAA==.Skybright:BAAALgAECggJCQAAAA==.',
So='Soggy:BAAALgAECgcJBwAAAA==.Sorayae:BAABLgAECn8iAAIHAAkJLBn1EwA/AgAHAAkJLBn1EwA/AgAAAA==.',
Sp='Specialk:BAAALgADCgkJKAAAAA==.Spinnykat:BAAALgAECgIJAgAAAA==.',
St='Starmist:BAAALgADCgMJAwAAAA==.Stinkfoot:BAAALgAECgIJAgAAAA==.Stoo:BAAALgADCgkJHAAAAA==.Stormkissed:BAAALgAECgUJDAAAAA==.Stormweaver:BAAALgAECgUJBQAAAA==.',
Su='Sunil:BAABLgAECn8kAAIHAAgJexThFADjAQAHAAgJexThFADjAQAAAA==.Suviqhabo:BAAALgAECggJDwAAAA==.',
Sv='Svala:BAAALgADCgYJBgAAAA==.',
Sy='Syclone:BAABLgAECn8hAAIKAAgJOyGWBQB3AgAKAAgJOyGWBQB3AgAAAA==.Syladen:BAAALgAECgYJEgAAAA==.Syleste:BAAALgAECgQJBAABLgAECggJIQAKADshAA==.Syvi:BAAALgAECgYJCQABLgAECggJDwABAAAAAA==.',
Ta='Tahwe:BAAALgADCgUJBQAAAA==.Tattianna:BAAALgAECgMJAwAAAA==.Tavendar:BAAALgAECgMJAwABLgAFFAQJCgAJAHALAA==.Tavil:BAAALgADCgMJAwAAAA==.Taírn:BAAALgAECgYJEAAAAA==.',
Te='Techie:BAAALgAECgcJDgAAAA==.Terradactyl:BAAALgADCgMJAwAAAA==.',
Th='Thunderslate:BAAALgAECgcJEAAAAA==.Thôrin:BAAALgADCgkJFQAAAA==.',
Ti='Tigerlillee:BAAALgADCgcJDQAAAA==.Tigreth:BAABLgAECn80AAMXAAkJQhRdNgDfAQAXAAkJQhRdNgDfAQAjAAIJlhSvNgBoAAAAAA==.Timotheus:BAAALgAECgQJBwAAAA==.',
To='Tonï:BAAALgADCggJCAAAAA==.',
Tr='Tragik:BAABLgAECn8jAAIIAAkJYAxxCwCTAQAIAAkJYAxxCwCTAQAAAA==.',
Tt='Ttrouble:BAAALgADCgUJBQAAAA==.',
Tu='Tuugadark:BAABLgAECn8uAAICAAgJvx7HIgCKAgACAAgJvx7HIgCKAgAAAA==.Tuugashox:BAAALgAECgUJBQAAAA==.',
Ul='Ulyaoth:BAABLgAECn8iAAICAAcJMgj8dgAPAQACAAcJMgj8dgAPAQAAAA==.',
Un='Unnerfable:BAAALgAECgYJBwAAAA==.',
Uw='Uwa:BAAALgADCgMJAwAAAA==.',
Uy='Uy:BAAALgAECgYJDwAAAA==.',
Va='Valakha:BAAALgAECgQJCQAAAA==.Valkyrie:BAAALgAECgQJBgAAAA==.',
Ve='Vedros:BAAALgADCgQJBwAAAA==.Vermouth:BAAALgAECgQJBAAAAA==.',
Vi='Viktoros:BAAALgAECgIJAgAAAA==.Violetra:BAAALgADCgMJAwAAAA==.',
Vo='Vorcan:BAAALgADCgYJBgAAAA==.Vorukh:BAABLgAECn8ZAAMTAAkJLxEfCQDWAQATAAkJLxEfCQDWAQAUAAEJyw9URQAmAAAAAA==.',
Vr='Vrave:BAAALgADCgQJBQAAAA==.',
Vy='Vyhlet:BAAALgAECgIJAgABLgAECggJMwAJANQeAA==.',
Wa='Warriorgroo:BAAALgAECgMJAwAAAA==.',
We='Wendish:BAAALgAECgEJCAAAAA==.Wertyda:BAABLgAECn8ZAAIWAAkJsxTRGgDhAQAWAAkJsxTRGgDhAQAAAA==.',
Wh='Whácker:BAABLgAECn8UAAMfAAgJOwpYEgB8AQAfAAgJOwpYEgB8AQAKAAMJrAguOQCBAAABLgAECgYJEAABAAAAAA==.',
Wi='Wickdlovly:BAAALgADCgEJAQABLgAECgYJBwABAAAAAA==.Wickedslicks:BAABLgAECn8qAAISAAgJhh9BCwBTAgASAAgJhh9BCwBTAgAAAA==.Wildthangg:BAAALgAECgIJAgAAAA==.',
Wo='Wooddchipper:BAAALgADCgYJBgAAAA==.',
Wr='Wreckshop:BAABLgAECn8XAAIMAAgJjhqJTwCNAQAMAAgJjhqJTwCNAQAAAA==.',
Wt='Wtfoxtrot:BAAALgADCgkJDAAAAA==.',
Xe='Xenøcide:BAAALgAECgcJEwAAAA==.',
Xx='Xxlockz:BAAALgAECgcJEwABLgAECggJCwABAAAAAA==.Xxpallyz:BAAALgAECggJCwAAAA==.',
Yi='Yinger:BAAALgADCgcJEAAAAA==.Yinglang:BAAALgADCgEJAQAAAA==.Yingling:BAABLgAECn8oAAIMAAkJ6Rn/KAAWAgAMAAkJ6Rn/KAAWAgAAAA==.',
Yo='Yohh:BAAALgAECgMJCAAAAA==.',
Yu='Yukara:BAAALgADCgYJBgAAAA==.Yuriko:BAABLgAECn81AAIkAAkJtBNvFQD9AQAkAAkJtBNvFQD9AQAAAA==.',
Za='Zaidan:BAAALgADCgcJDgAAAA==.Zanpaktu:BAAALgAECgQJBwAAAA==.Zaraha:BAAALgADCgEJAQAAAA==.Zata:BAAALgAECgUJBwAAAA==.',
Ze='Zeref:BAAALgAECgYJEgAAAA==.Zeur:BAAALgAECgEJAQAAAA==.Zevgrip:BAAALgAECgQJBQAAAA==.',
Zh='Zhia:BAAALgAECgQJBQAAAA==.',
Zi='Zippitydooda:BAAALgADCgQJBAABLgAECgYJBwABAAAAAA==.',
Zo='Zodiacc:BAABLgAECn82AAIUAAkJhxsGBACJAgAUAAkJhxsGBACJAgAAAA==.Zornhealer:BAAALgAECgUJBgABLgAECgUJCgABAAAAAA==.',
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
