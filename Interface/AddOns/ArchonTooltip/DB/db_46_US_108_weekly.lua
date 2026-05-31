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

local lookup = {'Evoker-Augmentation','Mage-Frost','Unknown-Unknown','Monk-Mistweaver','Monk-Brewmaster','Warlock-Demonology','Warrior-Fury','Paladin-Holy','DemonHunter-Devourer','Shaman-Restoration','Paladin-Protection','Paladin-Retribution','Druid-Guardian','Druid-Balance','Druid-Restoration','Monk-Windwalker','Mage-Arcane','Warlock-Destruction','Hunter-BeastMastery','DeathKnight-Unholy','Evoker-Devastation','Warrior-Arms','DemonHunter-Havoc','Hunter-Survival','DeathKnight-Frost','DeathKnight-Blood','Shaman-Elemental','Shaman-Enhancement','Evoker-Preservation','Rogue-Assassination','Rogue-Subtlety','Druid-Feral','Hunter-Marksmanship','Warlock-Affliction','Mage-Fire','Warrior-Protection','Rogue-Outlaw','Priest-Holy','DemonHunter-Vengeance','Priest-Discipline','Priest-Shadow',}
local provider = {region='US',realm='Gnomeregan',name='US',type='weekly',zone=46,date='2026-05-30',data={Ac='Acehuntura:BAAALgAECgEJAgAAAA==.',
Ad='Adaric:BAAALgAECgYJCAAAAA==.',
Af='Afflicea:BAAALgAECgMJAwAAAA==.',
Ah='Ahava:BAAALgADCgYJCQAAAA==.',
Ai='Aidoneiscus:BAAALgAECgUJCgABLgAFFAUJEAABAKMXAA==.Aiyaiyai:BAAALgAECgYJDAAAAA==.',
Aj='Ajani:BAAALgAECgYJDAAAAA==.',
Ak='Akawli:BAAALgAECgIJAwAAAA==.',
Al='Alall:BAAALgAECgMJBgAAAA==.Alauth:BAAALgAECgIJAwAAAA==.Aliceandreia:BAAALgADCgUJCgAAAA==.Alliethra:BAAALgAECgQJBQAAAA==.',
Am='Aminall:BAAALgAECgQJCgAAAA==.',
An='Anarreth:BAAALgADCgUJCgAAAA==.Andahla:BAAALgADCgkJCwAAAA==.Andore:BAABLgAECn8eAAICAAYJ9xiOdwBvAQACAAYJ9xiOdwBvAQAAAA==.Anewbyss:BAAALgAECggJDAAAAA==.Angrymurloc:BAAALgAECgcJEQAAAA==.Anthonie:BAAALgADCgYJBgAAAA==.Antoer:BAAALgAECgIJAgAAAA==.Anwyll:BAAALgADCgcJDAAAAA==.',
Ao='Aoir:BAAALgAECgQJBgAAAA==.',
Ap='Aposthmighty:BAAALgAECgQJBwAAAA==.',
Ar='Arcancis:BAAALgADCgQJBAAAAA==.Arlona:BAAALgAECgIJAwABLgAECgYJEAADAAAAAA==.Arms:BAAALgAECgcJDgAAAA==.Artemyss:BAAALgADCgEJAQAAAA==.',
As='Ashanara:BAAALgAECgQJBAABLgAECggJKwAEAFYaAA==.Asher:BAAALgADCgEJAQAAAA==.Ashnact:BAAALgAECgIJCQAAAA==.Ashraki:BAAALgAECgEJAQAAAA==.Ashreign:BAAALgAECgkJCQAAAA==.Asl:BAAALgADCgUJBQAAAA==.Asonnari:BAAALgADCgEJAQAAAA==.Astraeal:BAABLgAECn8UAAIFAAYJwREZOAALAQAFAAYJwREZOAALAQAAAA==.',
At='Atreana:BAABLgAECn82AAIGAAkJ4hVLKwAfAgAGAAkJ4hVLKwAfAgAAAA==.Attykus:BAABLgAECn8uAAIHAAgJ6xM1MQDoAQAHAAgJ6xM1MQDoAQAAAA==.',
Av='Avalerion:BAAALgAECgQJDAAAAA==.Avij:BAAALgAECgQJCgABLgAECgYJCQADAAAAAA==.',
Ay='Ayoreo:BAAALgADCgMJAwAAAA==.',
Az='Azmodon:BAAALgADCgEJAwAAAA==.',
['Añ']='Añathema:BAAALgAECgMJBAAAAA==.',
Ba='Banfultoxxin:BAAALgADCggJDgAAAA==.Barrellroll:BAAALgADCgkJCQAAAA==.Bastam:BAAALgAECgIJAgABLgAECgIJAwADAAAAAA==.Bat:BAAALgAECgQJBwAAAA==.',
Be='Bearlyhealz:BAAALgADCgkJBQAAAA==.Beercats:BAAALgADCgMJBgAAAA==.Bentotc:BAAALgAECgIJAwAAAA==.',
Bi='Bighoot:BAAALgAECgQJCgAAAA==.Bigmancow:BAABLgAECn8nAAIIAAkJTw+BJgC/AQAIAAkJTw+BJgC/AQAAAA==.Bigpoppapump:BAAALgAECgMJBAAAAA==.Bismofungion:BAAALgADCgcJCAAAAA==.',
Bl='Bludgens:BAAALgADCgIJAgAAAA==.Bluecoral:BAAALgADCgEJAQAAAA==.Blunter:BAABLgAECn8TAAIJAAcJ5gYdlgDxAAAJAAcJ5gYdlgDxAAAAAA==.Blushtime:BAAALgADCgIJAgAAAA==.Bluwhale:BAACLgAFFH8eAAIKAAgJ+BwWAQDKAgAKAAgJ+BwWAQDKAgAuAAQKfyYAAgoACQk+JFcJAAcDAAoACQk+JFcJAAcDAAAA.',
Bo='Bocchi:BAAALgAECgEJAQAAAA==.Bodanky:BAAALgAECgMJBQAAAA==.Bormor:BAAALgAECggJDwAAAA==.Bowdacious:BAAALgAECgQJBgAAAA==.Boötes:BAAALgADCgcJBwAAAA==.',
Br='Brago:BAAALgAECgEJAQAAAA==.Braini:BAAALgADCgEJAQAAAA==.Brainpath:BAAALgAECgYJEgAAAA==.Brasidias:BAAALgADCgQJBAAAAA==.Brickingkeys:BAAALgAECgIJAwAAAA==.Brumak:BAAALgAECgkJCgAAAA==.Bruno:BAABLgAECn8jAAMLAAkJRRa7EQCQAQALAAkJRRa7EQCQAQAMAAQJKQcQ+gCfAAAAAA==.',
Bu='Budthespud:BAAALgAECgEJAQAAAA==.Burland:BAAALgAECgMJBgAAAA==.',
['Bá']='Báthory:BAABLgAECn8UAAIJAAkJohzkEwCQAgAJAAkJohzkEwCQAgAAAA==.',
Ca='Cal:BAAALgAECgYJDAABLgAFFAIJBgAFACQSAA==.Calamity:BAAALgADCgQJBAAAAA==.Callistos:BAACLgAFFH8GAAIFAAIJJBLyPQCOAAAFAAIJJBLyPQCOAAAuAAQKfzoAAgUACQlYHjIHALICAAUACQlYHjIHALICAAAA.Camelshammy:BAAALgAECgYJDgAAAA==.Caradyn:BAAALgADCgUJBQABLgAECgYJFAACACYTAA==.Caris:BAAALgAECgMJAwAAAA==.Castianna:BAAALgAECgUJEAAAAA==.',
Ce='Cebastian:BAAALgAECgMJAwAAAA==.Cedarpoint:BAAALgADCgcJCAAAAA==.Celoria:BAAALgADCgUJCQAAAA==.Century:BAABLgAECn8rAAQNAAgJFx1NEQC0AQAOAAgJ/hcEFwD/AQANAAgJxxVNEQC0AQAPAAIJFREexwAwAAAAAA==.Cerriwyn:BAAALgAECgEJAQAAAA==.Cery:BAAALgAECgEJAQAAAA==.',
Ch='Cheochan:BAAALgADCgYJCwAAAA==.Chizami:BAAALgAECggJDAABLgAFFAYJEgAIAJMQAA==.Chocostarmie:BAAALgADCgQJBAAAAA==.Chug:BAABLgAECn8eAAIQAAkJlyAkCACyAgAQAAkJlyAkCACyAgAAAA==.',
Ci='Circa:BAABLgAECn8lAAMCAAgJ4BUbUgDOAQACAAgJhhUbUgDOAQARAAQJWg7dEAC0AAAAAA==.Cithrel:BAABLgAECn8ZAAISAAkJiQ/tEgADAQASAAkJiQ/tEgADAQAAAA==.',
Co='Conqubine:BAAALgADCgkJDgAAAA==.Corban:BAAALgAECgEJAQAAAA==.',
Cr='Creolix:BAAALgADCgYJBgABLgAECgYJCAADAAAAAA==.Crocklock:BAABLgAECn8ZAAIGAAcJ6hWPXQB7AQAGAAcJ6hWPXQB7AQAAAA==.',
Cu='Cuddlyblood:BAAALgAECgEJAQAAAA==.Cujo:BAAALgADCgMJAwAAAA==.',
['Cà']='Càssiàn:BAAALgADCgIJAgAAAA==.',
Da='Dallia:BAABLgAECn8vAAMMAAcJ4Qf90gDQAAAMAAcJ0Ab90gDQAAALAAMJ7QXzPABUAAAAAA==.Damnatio:BAABLgAECn8gAAIMAAkJmSRYDQDlAgAMAAkJmSRYDQDlAgAAAA==.Damonster:BAAALgAECgIJAwAAAA==.Darkclement:BAABLgAECn8VAAITAAcJsx4oMQAAAgATAAcJsx4oMQAAAgABLgAFFAMJCQAMAE4TAA==.Darkin:BAAALgAECgcJCAAAAA==.Darkmist:BAAALgADCgUJBQAAAA==.Darkwiz:BAAALgAECggJCgAAAA==.Davrimbasher:BAAALgADCgEJAQAAAA==.',
De='Deadlydk:BAAALgADCgMJAwAAAA==.Deathbybob:BAAALgAECgQJDAAAAA==.Deathgriped:BAAALgAECgUJDgAAAA==.Deeper:BAABLgAECn8WAAMOAAcJqActRADfAAAOAAcJqActRADfAAAPAAMJagEkzQAqAAAAAA==.Deezmoonz:BAAALgADCgYJCQAAAA==.Dementos:BAAALgADCgkJCgAAAA==.Demonofwar:BAAALgADCgYJDAABLgAECgYJCAADAAAAAA==.Devils:BAAALgAECgUJCQAAAA==.',
Di='Dirin:BAAALgAECgUJDQABLgAECgUJCgADAAAAAA==.Disneymagic:BAAALgADCgUJBwAAAA==.',
Dm='Dmaan:BAAALgADCgMJAwAAAA==.',
Dr='Dragonpebble:BAAALgADCgYJBgABLgAECgkJHQAGAOwTAA==.Drahalah:BAABLgAECn8eAAIUAAgJXR+XMgAgAgAUAAgJXR+XMgAgAgAAAA==.Drakeji:BAABLgAECn8zAAMBAAkJ4AnkMABUAQABAAkJ4AnkMABUAQAVAAQJKAGhPwAxAAAAAA==.Dreamliner:BAAALgAECgYJBgAAAA==.Drezind:BAAALgAECgQJBAAAAA==.Drhealalot:BAAALgAECgEJAQAAAA==.Drugar:BAAALgAECgkJCQABLgAFFAUJEgAWAHUcAA==.',
Du='Dumplingg:BAAALgAECggJDAAAAA==.',
Ea='Earthvoodoo:BAAALgAECgYJDwAAAA==.',
Eb='Ebonlight:BAAALgADCgkJFgAAAA==.',
Ec='Ecnyw:BAAALgADCgMJAwABLgAECgUJCAADAAAAAA==.',
Ed='Edence:BAAALgAECgMJAwAAAA==.',
Eh='Ehunter:BAAALgAECgUJDAAAAA==.',
Ei='Eillea:BAAALgADCgQJBAAAAA==.',
El='Elegant:BAAALgAECgkJBwAAAA==.Elspeth:BAAALgAECgIJAgAAAA==.Elsyria:BAAALgADCgIJAgABLgAFFAcJGQAMAAEgAA==.Eluneslight:BAAALgAECgEJAgAAAA==.',
Em='Emmeri:BAAALgAECgQJBwABLgAECggJLgAHAOsTAA==.',
En='Ender:BAAALgAECgIJAgAAAA==.',
Ep='Epi:BAABLgAECn8UAAIXAAgJshJbLwDmAAAXAAgJshJbLwDmAAAAAA==.',
Er='Erianis:BAAALgADCgMJAwAAAA==.Erniethemonk:BAAALgAECgYJEAAAAA==.',
Ev='Evianda:BAAALgADCggJBwAAAA==.',
Ez='Ezale:BAAALgAECgkJEwAAAA==.Ezpz:BAAALgAECgYJEgAAAA==.',
Fa='Falsetto:BAAALgAECgEJAgAAAA==.Faramír:BAAALgAECgQJBAAAAA==.Fatébringer:BAAALgAECggJDgAAAA==.',
Fe='Fennek:BAAALgAECggJEwAAAA==.',
Fi='Fiønaviolet:BAAALgADCgcJBwAAAA==.',
Fo='Fourth:BAAALgAECgEJAgABLgAECgcJDgADAAAAAA==.',
Fr='Frayla:BAAALgADCgEJAQAAAA==.',
Fu='Fuzzyxbutt:BAAALgAECgYJDgAAAA==.',
Fy='Fyaaga:BAAALgAECgQJBAABLgAECgkJFAAEAIofAA==.',
Ga='Garaylo:BAACLgAFFH8ZAAIMAAcJASA1BwAVAgAMAAcJASA1BwAVAgAuAAQKfykAAgwACQn1JMACAKwDAAwACQn1JMACAKwDAAAA.Garroar:BAAALgADCgcJCAAAAA==.',
Ge='Geed:BAAALgADCgEJAQAAAA==.Gewnzilla:BAAALgAECgIJAgAAAA==.',
Gg='Ggxd:BAAALgADCgkJEAAAAA==.',
Gh='Ghosst:BAABLgAECn8jAAIYAAkJtiLuAgAIAwAYAAkJtiLuAgAIAwAAAA==.',
Gi='Gilberticus:BAAALgADCgMJAwABLgAECgkJRQAQAIIiAA==.Gimlithekind:BAAALgAECgEJAQAAAA==.',
Gl='Glen:BAAALgADCgMJAwAAAA==.',
Gn='Gnobliterate:BAABLgAECn8oAAQUAAkJMRKUYQCSAQAUAAkJ9g+UYQCSAQAZAAYJNQ3ZGQDPAAAaAAIJLRNWQQBuAAAAAA==.Gnobolts:BAAALgAECgEJAQAAAA==.Gnobull:BAAALgAECgQJBAAAAA==.Gnochi:BAAALgAECgcJBwAAAA==.Gnudgnimish:BAAALgAECgYJCgABLgAECgkJJgAFAMshAA==.',
Go='Goldenblight:BAAALgAECgYJCwAAAA==.Goldenchi:BAAALgAECgEJAQAAAA==.Gomper:BAAALgAECgMJBAAAAA==.Gonforgood:BAAALgADCgYJBgAAAA==.Goonmaxing:BAAALgADCgMJAwAAAA==.',
Gr='Grimclaw:BAAALgADCgYJDgAAAA==.Grimmrot:BAAALgAECgYJDQAAAA==.Grimmz:BAAALgADCggJCQAAAA==.Grizk:BAAALgADCgEJAQAAAA==.',
Gu='Guttris:BAAALgAECgYJEQAAAA==.',
Gw='Gwaineedk:BAAALgAECgMJAwAAAA==.',
Ha='Haikusen:BAAALgADCgYJBAABLgAECgYJCAADAAAAAA==.Halstron:BAACLgAFFH8GAAIMAAIJIyJPYwDHAAAMAAIJIyJPYwDHAAAuAAQKfy0AAwwACQm/IFwMAO4CAAwACQmPIFwMAO4CAAsABQl7FXQeAAcBAAAA.Harribel:BAABLgAECn8bAAQaAAgJuwXEPgB7AAAUAAYJ1wP+8wCdAAAaAAQJtwbEPgB7AAAZAAIJ8gHdFgA1AAAAAA==.',
He='Heliòs:BAAALgAECgQJBAAAAA==.Hellwár:BAAALgADCgYJBgAAAA==.',
Ho='Hogfu:BAAALgAECgQJBAAAAA==.Hogshock:BAABLgAECn8bAAQbAAkJTRXRJgDcAQAbAAkJTRXRJgDcAQAcAAMJXgfMJACLAAAKAAEJhA1cygAoAAAAAA==.Holocharizrd:BAAALgADCgcJCQAAAA==.Holyzel:BAAALgAECgkJEgAAAA==.Hotnsassie:BAAALgADCgMJCQAAAA==.Hound:BAAALgADCgUJCAAAAA==.Hoyt:BAAALgADCgcJBwAAAA==.',
Hs='Hsimingjung:BAABLgAECn8mAAMFAAkJyyEoBgDJAgAFAAkJyyEoBgDJAgAQAAEJtB04cgBWAAAAAA==.',
Hu='Humanic:BAAALgAECgIJAwAAAA==.Huntari:BAAALgAECgEJAwAAAA==.',
Hy='Hylie:BAACLgAFFH8IAAIGAAMJmwVMdgC8AAAGAAMJmwVMdgC8AAAuAAQKfx0AAgYACQlnDVlaALkBAAYACQlnDVlaALkBAAAA.',
['Hè']='Hèlla:BAAALgADCgkJFQAAAA==.',
Ig='Ignisky:BAAALgAECgcJDgABLgAFFAUJEgAWAHUcAA==.',
Il='Illidarie:BAAALgADCgUJCAAAAA==.',
Im='Imsofresh:BAAALgADCgEJAQAAAA==.',
In='Inte:BAAALgADCgYJBgAAAA==.Inzi:BAAALgAECgEJAgAAAA==.',
Iz='Izgin:BAABLgAECn8UAAICAAYJJhN7pgAWAQACAAYJJhN7pgAWAQAAAA==.',
Ja='Jadeyn:BAAALgADCgMJAwAAAA==.Jaime:BAAALgADCgYJCQABLgAECgYJCAADAAAAAA==.Jalet:BAAALgADCgcJDQAAAA==.Janie:BAAALgADCgUJCAABLgADCgYJBgADAAAAAA==.Jantar:BAABLgAECn8bAAIPAAkJ4xiQFQCJAgAPAAkJ4xiQFQCJAgAAAA==.Jasonbjorne:BAAALgAECgEJAQAAAA==.',
Je='Jebbyclipse:BAAALgAECgQJCAAAAA==.Jenzö:BAABLgAECn8bAAIbAAYJBhF5QQASAQAbAAYJBhF5QQASAQAAAA==.Jeramya:BAAALgADCgQJBAAAAA==.',
Jo='Joeviben:BAAALgAECgcJEAAAAA==.Jormungandr:BAAALgADCgYJCgABLgADCgcJBwADAAAAAA==.',
Ju='Jugsy:BAABLgAECn8ZAAICAAkJtBfrKABgAgACAAkJtBfrKABgAgAAAA==.Juliza:BAAALgADCgQJBAAAAA==.Jungfer:BAAALgAECgIJAQAAAA==.',
Ka='Kaerodora:BAAALgADCgYJBgAAAA==.Kalasan:BAAALgAECgIJAgAAAA==.Kaldread:BAAALgADCgYJBgAAAA==.Kaligo:BAABLgAECn9CAAMbAAkJQBrYEQBLAgAbAAkJQBrYEQBLAgAcAAQJrgSuIgCrAAAAAA==.Kalistus:BAABLgAECn8bAAIJAAkJtww1UAB+AQAJAAkJtww1UAB+AQAAAA==.Kallistos:BAAALgAECgEJAQABLgAFFAIJBgAFACQSAA==.Kalygos:BAAALgAECgQJBAABLgAFFAIJBgAFACQSAA==.Karall:BAAALgAECgEJAQAAAA==.Karetha:BAAALgAECgUJCQAAAA==.Katar:BAAALgADCgMJAwAAAA==.Katreset:BAAALgAECgUJCAAAAA==.',
Kd='Kdavid:BAAALgADCgUJCgAAAA==.',
Ke='Kebsy:BAABLgAECn8zAAIQAAkJriOYAwAWAwAQAAkJriOYAwAWAwAAAA==.Kegfupanda:BAAALgAECgEJAgAAAA==.Keleion:BAABLgAECn8nAAIJAAcJzhAoZQByAQAJAAcJzhAoZQByAQABLgAECgkJEwADAAAAAA==.Kelements:BAAALgAFFAEJAQAAAA==.Kelyessada:BAAALgADCgYJBgAAAA==.Kevonjuravis:BAABLgAECn8qAAMFAAYJuQ+SPwDrAAAFAAYJlwySPwDrAAAQAAUJWxBQUwCmAAAAAA==.',
Kh='Khalya:BAAALgAECgUJBQAAAA==.Khalyl:BAABLgAECn8VAAIXAAUJSxJnMQDaAAAXAAUJSxJnMQDaAAAAAA==.Kheart:BAAALgAECgEJAQAAAA==.Kholy:BAAALgADCgYJBgAAAA==.',
Ki='Kidrash:BAAALgADCgcJCAAAAA==.Kimegh:BAAALgADCgIJAgAAAA==.Kitsunae:BAAALgADCgcJGwAAAA==.',
Kl='Kleredan:BAAALgAECgkJBgAAAA==.',
Ko='Koder:BAACLgAFFH8QAAIBAAUJoxfMIQAhAQABAAUJoxfMIQAhAQAuAAQKfzQABAEACAmtIbEGABIDAAEACAmtIbEGABIDABUABwlXGUgGANkBAB0AAgkOArJEAEoAAAAA.Kozmoker:BAAALgAECgYJBgAAAA==.',
Kr='Krondys:BAAALgAECgYJBgAAAA==.Krytus:BAAALgAECgEJAgAAAA==.',
Ku='Kupó:BAAALgADCgUJBQABLgAECgYJDAADAAAAAA==.',
Ky='Kyakdeath:BAABLgAECn81AAMUAAgJUhqCUAC/AQAUAAgJUhqCUAC/AQAZAAEJKwmWNAAnAAAAAA==.',
Kz='Kzo:BAAALgAECgYJDQAAAA==.',
La='Lailyre:BAAALgADCgQJBAAAAA==.',
Le='Lecker:BAAALgAECgEJAQAAAA==.Legado:BAAALgAECgUJBwAAAA==.',
Li='Lilbigcow:BAAALgAECgEJAQAAAA==.Lilithxander:BAAALgAECgUJCQAAAA==.Lilshooter:BAAALgAECgIJAwABLgAFFAEJAQADAAAAAA==.Lizzybordan:BAAALgAECgcJDgAAAA==.',
Ll='Llaaroyy:BAAALgADCgEJAQAAAA==.Llarroii:BAAALgAECgEJAgAAAA==.',
Lo='Lovar:BAAALgADCgYJBgAAAA==.',
Lu='Lucinick:BAABLgAECn8fAAMeAAYJBxURDABaAQAeAAYJBxURDABaAQAfAAQJuAruNgDYAAAAAA==.Lucy:BAAALgADCgIJAgAAAA==.Luxdiei:BAAALgAECgYJBgAAAA==.Luzziem:BAAALgAECgQJBAAAAA==.',
Ly='Lynx:BAAALgAECgEJAwAAAA==.',
Ma='Mariskama:BAABLgAECn8dAAITAAgJjwXzegAwAQATAAgJjwXzegAwAQAAAA==.Markusthered:BAAALgAECgMJAwAAAA==.Mazza:BAAALgAECgkJEQAAAA==.',
Mc='Mcbong:BAAALgAECgQJBwAAAA==.',
Me='Mello:BAAALgADCgYJBgAAAA==.Meowimabear:BAAALgADCgkJEAABLgAECgkJIwAYALYiAA==.Metal:BAAALgAECgQJDgAAAA==.Method:BAAALgADCgEJAQAAAA==.Meuccí:BAAALgAECgcJCwAAAA==.',
Mh='Mhelora:BAAALgAECgUJEAAAAA==.',
Mi='Mikkais:BAAALgAECgYJDgAAAA==.Mimacho:BAAALgAECgQJCAAAAA==.Minimini:BAACLgAFFH8QAAIEAAQJExuUGwBAAQAEAAQJExuUGwBAAQAuAAQKfy4AAgQACQkJHIoPAIkCAAQACQkJHIoPAIkCAAAA.Minni:BAAALgAFFAEJAwAAAA==.',
Mo='Moolin:BAABLgAECn8oAAIgAAkJUwkRFwA2AQAgAAkJUwkRFwA2AQAAAA==.Moranthe:BAAALgAECgcJDAABLgAECgkJFAAEAIofAA==.Mordsyth:BAAALgAECgYJCgAAAA==.',
Mu='Muggni:BAAALgAECgkJEQAAAA==.Muggypew:BAABLgAECn8UAAIhAAkJRgF4KQBgAAAhAAkJRgF4KQBgAAAAAA==.Munder:BAABLgAECn8mAAMiAAkJgB3gAgB8AgAiAAkJcBzgAgB8AgAGAAgJ/xlZSwCtAQAAAA==.Mustymuppet:BAACLgAFFH8VAAIGAAQJmBd5NABPAQAGAAQJmBd5NABPAQAuAAQKfygAAwYACAnzGqwxAAUCAAYACAnzGqwxAAUCABIAAQlnD7VuADgAAAAA.',
My='Myrotheron:BAAALgADCgMJAwAAAA==.Mysticmeat:BAAALgAECgEJAQAAAA==.Mythicalbug:BAAALgADCgEJAQAAAA==.Mythuneran:BAABLgAECn8bAAIjAAgJUhcKAwDgAQAjAAgJUhcKAwDgAQAAAA==.',
['Mø']='Mørzanna:BAAALgAECgEJAQAAAA==.',
Na='Nanookigaluk:BAAALgADCgYJBgAAAA==.Narrator:BAAALgAECgEJAgAAAA==.Navikz:BAAALgADCgUJBQAAAA==.',
Ne='Nekrose:BAABLgAECn8aAAIUAAgJwiIuGwCQAgAUAAgJwiIuGwCQAgAAAA==.Nemini:BAAALgAECgQJCQAAAA==.Nena:BAABLgAECn8dAAIOAAYJbBMvNgAiAQAOAAYJbBMvNgAiAQAAAA==.Nenacurses:BAAALgAECgMJAwABLgAECgYJHQAOAGwTAA==.Nephilia:BAAALgADCgYJBgAAAA==.Newfy:BAAALgAFFAEJAgAAAA==.',
Ni='Ninjamage:BAAALgAECgUJBQAAAA==.Nistis:BAAALgAECgYJEQAAAA==.Niteshroud:BAAALgADCgMJAwAAAA==.Nithendroz:BAABLgAECn8YAAMVAAcJZgqrEwC+AAAVAAQJZgurEwC+AAABAAMJaAiBcQBdAAAAAA==.Nity:BAAALgAECgQJBAAAAA==.',
No='Noctaurus:BAABLgAECn8eAAIUAAgJKglnfgBRAQAUAAgJKglnfgBRAQAAAA==.Noczorro:BAAALgADCgYJBgAAAA==.Nomadhew:BAAALgAECgcJBwAAAA==.Noraice:BAAALgAECgEJAQAAAA==.Notagain:BAACLgAFFH8oAAIMAAgJnRvRAwBmAgAMAAgJnRvRAwBmAgAuAAQKfy4AAgwACQkBI5YHAFoDAAwACQkBI5YHAFoDAAAA.Noxcorvus:BAAALgAECgEJAQAAAA==.',
Nu='Nuvo:BAAALgADCgYJBgAAAA==.',
Ny='Nylloc:BAAALgAECgkJCQAAAA==.Nymphàdoria:BAAALgAECgEJAQAAAA==.Nyuxx:BAAALgAECgYJEAAAAA==.',
['Nê']='Nêwfie:BAAALgAECgEJAwABLgAFFAEJAgADAAAAAA==.',
Oc='Oceanic:BAAALgADCgYJCwAAAA==.Oceans:BAAALgADCgIJAgAAAA==.',
Ol='Olenza:BAAALgAECgQJBAAAAA==.Olgreeneyes:BAAALgAECgIJBAAAAA==.',
Or='Orangewhale:BAABLgAECn8UAAIPAAYJChgpTABzAQAPAAYJChgpTABzAQAAAA==.',
Ou='Out:BAAALgAECgYJCwAAAA==.',
Ox='Oxidation:BAAALgADCgcJGgAAAA==.',
Pa='Painspongie:BAAALgADCgQJBQAAAA==.Patsajak:BAAALgADCgEJAQAAAA==.Pavo:BAAALgADCgYJBgAAAA==.',
Pe='Pebbleshifts:BAAALgAECgMJAwAAAA==.Peejean:BAAALgAECgYJBgAAAA==.Peyblade:BAAALgAECgYJBgABLgAECgkJHgARABghAA==.Peybreak:BAAALgAECgIJAgABLgAECgkJHgARABghAA==.Peychi:BAAALgAECgUJBgABLgAECgkJHgARABghAA==.Peycicle:BAABLgAECn8eAAIRAAkJGCFKAQDOAgARAAkJGCFKAQDOAgAAAA==.Peysanity:BAAALgAECgQJBAABLgAECgkJHgARABghAA==.Peystruction:BAAALgAECgEJAgABLgAECgkJHgARABghAA==.Peytan:BAABLgAECn8VAAMJAAkJLxjLIAA8AgAJAAkJLxjLIAA8AgAXAAEJuQmmdgAuAAABLgAECgkJHgARABghAA==.Peytin:BAAALgAECgQJBAABLgAECgkJHgARABghAA==.',
Ph='Phantasm:BAAALgADCgQJBwAAAA==.Phemoid:BAAALgADCgkJCQAAAA==.',
Pi='Pinkywhale:BAAALgAFFAIJAgAAAA==.Pippa:BAABLgAECn8lAAIdAAgJqB3/BQCbAgAdAAgJqB3/BQCbAgAAAA==.Pitythefu:BAAALgADCgcJBQAAAA==.',
Pl='Planett:BAABLgAECn8lAAMKAAkJChxLFACPAgAKAAkJChxLFACPAgAbAAEJFgPXqgAcAAAAAA==.',
Po='Poetuck:BAABLgAECn8yAAICAAkJnxQ7RQD0AQACAAkJnxQ7RQD0AQAAAA==.Pokeyruler:BAAALgAECgIJAgAAAA==.Pokeythorn:BAAALgADCgkJFwAAAA==.Pookießear:BAAALgADCgUJBQAAAA==.Powdrpufgirl:BAAALgADCgMJAwABLgAECgYJCAADAAAAAA==.',
Pr='Proko:BAABLgAECn8lAAMbAAgJ1xLNQAAUAQAbAAYJ/hPNQAAUAQAKAAIJYBGtlwB5AAAAAA==.',
Ps='Psychovoodoo:BAAALgAECgIJBwAAAA==.',
Pu='Publicpool:BAAALgADCgEJAQAAAA==.Purfec:BAAALgADCgcJDAAAAA==.',
Qa='Qatka:BAAALgAECgQJBQAAAA==.',
Qu='Quiver:BAABLgAECn8iAAIMAAgJ1Q1XeQBhAQAMAAgJ1Q1XeQBhAQAAAA==.Quizle:BAAALgAECgEJAQAAAA==.',
['Qì']='Qìlen:BAAALgAECgcJEwAAAA==.',
Ra='Raein:BAABLgAECn8qAAMKAAgJiySABQBGAwAKAAgJiySABQBGAwAbAAYJnBe+OwAqAQAAAA==.Raginghog:BAAALgAECgUJCAAAAA==.Rainn:BAAALgAFFAIJBAAAAA==.Rainnsoul:BAAALgAECgYJDgAAAA==.Rakkclaw:BAAALgAECgEJAQABLgAECgEJAQADAAAAAA==.Ralofurius:BAAALgAECgYJCQAAAA==.Rasril:BAAALgAFFAEJAQAAAA==.Ratched:BAAALgADCgMJAwAAAA==.Raze:BAAALgAECgIJBgAAAA==.',
Re='Red:BAAALgADCgcJEgAAAA==.Redrighthand:BAAALgADCgEJAQAAAA==.Renicus:BAAALgADCgYJCAAAAA==.Renmare:BAABLgAECn8WAAIHAAUJOhc/TAD/AAAHAAUJOhc/TAD/AAAAAA==.Renmore:BAABLgAECn8VAAIMAAgJMBFRZgCJAQAMAAgJMBFRZgCJAQAAAA==.Rennzo:BAAALgADCgcJBwAAAA==.Reshtargorr:BAAALgADCgIJAgAAAA==.',
Rg='Rgbpanda:BAAALgAECgQJBQAAAA==.',
Rh='Rhandoom:BAAALgADCgQJBAAAAA==.',
Ri='Ricky:BAAALgAECgEJAQAAAA==.Rikeji:BAAALgAECgYJCwAAAA==.Risotto:BAAALgAECgMJBQAAAA==.Riumi:BAAALgAECgMJCQAAAA==.Rivenxi:BAAALgAECgEJAQABLgAECgcJDAADAAAAAA==.',
Ro='Rocksolid:BAAALgAECgEJAgAAAA==.Ronaspreader:BAAALgAECgYJAwAAAA==.Roskolnikov:BAAALgAECgUJDwAAAA==.',
Ru='Rubymoonbeam:BAABLgAECn8jAAITAAcJDw6FawBTAQATAAcJDw6FawBTAQAAAA==.Ruele:BAABLgAECn8UAAIEAAkJih9uDwCLAgAEAAkJih9uDwCLAgAAAA==.Ruenan:BAABLgAECn8xAAMTAAkJxybrAACHAwATAAkJxybrAACHAwAhAAMJlhKzaACcAAAAAA==.',
Ry='Ryain:BAABLgAECn85AAMOAAkJtg8JJwB7AQAOAAkJ9Q0JJwB7AQANAAcJnw9EIwAQAQAAAA==.Ryian:BAAALgAECgQJBAAAAA==.',
['Rä']='Räinns:BAABLgAECn8YAAINAAcJNgo/GAD0AAANAAcJNgo/GAD0AAAAAA==.',
Sa='Saintstephen:BAAALgADCggJGQAAAA==.Santajr:BAABLgAECn8UAAIkAAYJXgFnOgBwAAAkAAYJXgFnOgBwAAAAAA==.Sapthat:BAABLgAECn8bAAMlAAcJwyH7AwDqAQAlAAYJAyT7AwDqAQAeAAMJXBrkEQDnAAAAAA==.Sarahlina:BAAALgADCgcJBwAAAA==.Sarthrity:BAABLgAECn8aAAICAAYJNwmmxgDgAAACAAYJNwmmxgDgAAAAAA==.Savemeh:BAAALgAECgEJAQAAAA==.Savepebble:BAABLgAECn8dAAMGAAkJ7BMMXQB8AQAGAAgJnA8MXQB8AQASAAUJXxdBGwC3AAAAAA==.',
Sc='Scalesofdoom:BAAALgAECgEJAgAAAA==.',
Se='Seather:BAABLgAECn8cAAIfAAgJ4BvDEwB4AgAfAAgJ4BvDEwB4AgAAAA==.Seirin:BAABLgAECn8qAAImAAgJrBQgGAD2AQAmAAgJrBQgGAD2AQAAAA==.Selendaa:BAAALgAECgUJEQAAAA==.Senadarra:BAACLgAFFH8XAAIhAAUJCiGNDQBTAQAhAAUJCiGNDQBTAQAuAAQKfzcAAiEACQkeIXMCALoCACEACQkeIXMCALoCAAAA.Sephenroth:BAAALgAECgQJBwAAAA==.Sephron:BAAALgAECggJEQAAAA==.Serendipity:BAAALgADCgYJCQABLgAECggJFAAXALISAA==.Serqet:BAABLgAECn8WAAQJAAYJEBXfZABEAQAJAAYJEBXfZABEAQAnAAQJCAM5JgBWAAAXAAEJAAA4dAAAAAAAAA==.Sethen:BAAALgAECgEJAQAAAA==.',
Sh='Shadowhawke:BAAALgADCggJCAAAAA==.Shammology:BAABLgAECn8WAAIKAAcJPRINRQB9AQAKAAcJPRINRQB9AQAAAA==.Shaollyn:BAAALgADCgUJCgAAAA==.Sheri:BAABLgAECn8UAAIRAAcJPxqEBACSAQARAAcJPxqEBACSAQAAAA==.Shizam:BAAALgAECgUJBQAAAA==.Shizzi:BAAALgAECgQJBgAAAA==.Shotowkhaan:BAABLgAECn8WAAMPAAYJHRXpQgByAQAPAAYJHRXpQgByAQAOAAEJaAKdmAAUAAAAAA==.Shotowkhann:BAAALgAECgIJAgAAAA==.Shoyoh:BAAALgAECgQJCQAAAA==.Shízu:BAAALgADCgkJDAAAAA==.',
Si='Sillygoose:BAACLgAFFH8gAAICAAgJShENDwAzAgACAAgJShENDwAzAgAuAAQKfyQAAgIACQlJIJEVACcDAAIACQlJIJEVACcDAAAA.Sinadara:BAAALgAECgYJEAAAAA==.Sinïster:BAAALgADCgEJAQABLgAECgQJCwADAAAAAA==.Siong:BAAALgADCgcJCgABLgAFFAcJGQAMAAEgAA==.Siorknav:BAABLgAECn8fAAIMAAgJiQ7RlQAtAQAMAAgJiQ7RlQAtAQAAAA==.',
Sk='Skalar:BAABLgAECn8WAAIHAAgJcgo+OwBDAQAHAAgJcgo+OwBDAQAAAA==.Skodah:BAAALgADCgkJEQABLgAECgQJCwADAAAAAA==.',
Sl='Släyr:BAAALgAECgMJBAAAAA==.',
So='Solunara:BAAALgADCgcJFgAAAA==.Somnambula:BAAALgADCgQJBAAAAA==.Sonadoria:BAABLgAECn8ZAAIUAAcJ7Q4WiAA/AQAUAAcJ7Q4WiAA/AQAAAA==.Sorrenda:BAAALgADCgkJDwAAAA==.Soup:BAABLgAECn8nAAIgAAkJ/g0XEACRAQAgAAkJ/g0XEACRAQAAAA==.',
Sp='Sparow:BAAALgAECgEJAQAAAA==.Spinetarak:BAAALgADCgMJAwAAAA==.',
St='Stabbie:BAABLgAECn8XAAIfAAkJdRlNEgD9AQAfAAkJdRlNEgD9AQAAAA==.Stamina:BAAALgADCggJEAAAAA==.Stell:BAAALgAECgYJBwAAAA==.Stkawli:BAAALgAECgMJAwAAAA==.Stovik:BAABLgAECn8sAAMcAAkJdSFKAwC/AgAcAAkJdSFKAwC/AgAKAAcJ0RE4QQCMAQAAAA==.',
Sv='Sventhebrave:BAAALgAECgUJEQAAAA==.',
Sw='Sweeneytod:BAAALgAECgIJBgAAAA==.Sweetpally:BAAALgADCgUJCAAAAA==.',
Sy='Sykill:BAAALgAECgUJBwAAAA==.Sylira:BAACLgAFFH8PAAMmAAYJ5xHRCACQAQAmAAYJ5xHRCACQAQAoAAEJMAAiRgASAAAuAAQKfzcAAyYACQmUIqsGAPYCACYACQmUIqsGAPYCACkAAwkWDsdbAHgAAAAA.Sylk:BAAALgAECgUJBQABLgAECgYJEAADAAAAAA==.',
['Sö']='Söl:BAAALgAECgQJBAAAAA==.',
Ta='Taintedfel:BAAALgADCgkJCAAAAA==.Takamura:BAAALgAECgcJBwAAAA==.Takedown:BAACLgAFFH8SAAIWAAUJdRyMAwANAQAWAAUJdRyMAwANAQAuAAQKfywAAxYACQlhJNABACwDABYACQlhJNABACwDAAcABwkrGsUsAAECAAAA.Talena:BAAALgAECgcJBwAAAA==.Talleral:BAAALgAECgYJCgAAAA==.Tallyn:BAAALgAECgEJAQAAAA==.Tamanan:BAAALgAECgQJBwABLgAECgUJBQADAAAAAA==.Tankie:BAAALgADCgEJAQAAAA==.Taurgrim:BAAALgADCgUJCQAAAA==.Tavin:BAAALgAECgEJAgAAAA==.Tazrav:BAAALgAECgMJAwAAAA==.',
Te='Terasha:BAAALgAECgkJBgAAAA==.',
Th='Thalid:BAAALgADCggJDgAAAA==.Tharonix:BAAALgAECgYJEwAAAA==.Thelitch:BAAALgADCgEJAgAAAA==.Theredpanda:BAAALgAECgUJBQAAAA==.Thewarden:BAAALgAECgIJAgAAAA==.',
Ti='Tic:BAAALgAECgYJBgAAAA==.Tigerwang:BAAALgAECgQJCAAAAA==.Tigrasia:BAAALgADCgYJCwAAAA==.Timaeus:BAABLgAECn80AAICAAkJrBs3JAB2AgACAAkJrBs3JAB2AgAAAA==.Tinder:BAAALgADCgUJBQABLgAECgYJCAADAAAAAA==.',
Tm='Tmbeesknees:BAAALgADCgMJAwAAAA==.',
To='Touch:BAAALgAECgUJCQAAAA==.Touchofkarma:BAAALgADCgcJDAAAAA==.',
Tr='Trifflinhoes:BAAALgAECgUJEAAAAA==.',
Tu='Turningblue:BAAALgADCgUJBAAAAA==.Tusktilldawn:BAAALgAECggJCQAAAA==.',
Tw='Twohoof:BAAALgADCgkJFAAAAA==.',
Ty='Tydrinor:BAAALgAECgcJAQAAAA==.',
['Tä']='Tänithðurden:BAAALgADCggJDgAAAA==.',
Ug='Ugin:BAAALgAECgUJBgAAAA==.',
Un='Unobasho:BAAALgAECgMJAwABLgAFFAQJCwABAH0PAA==.Unoboxo:BAAALgADCgEJAQABLgAFFAQJCwABAH0PAA==.Unovoke:BAACLgAFFH8LAAIBAAQJfQ8QKgD+AAABAAQJfQ8QKgD+AAAuAAQKfzUAAgEACQkrHX8QAEoCAAEACQkrHX8QAEoCAAAA.',
Va='Valeena:BAAALgADCgEJAQAAAA==.Valorash:BAABLgAECn86AAMMAAkJCCJnCQAJAwAMAAkJCCJnCQAJAwALAAYJyhu4DwDJAQAAAA==.Valorious:BAAALgAECgIJAgAAAA==.Vandaira:BAAALgAECgkJAQAAAA==.Vasillisa:BAAALgAECgMJBQAAAA==.',
Ve='Vearick:BAAALgADCgYJCgAAAA==.Veleyna:BAAALgADCgcJCwAAAA==.Velgryn:BAAALgAECgUJBAAAAA==.Velintha:BAAALgAECgcJCAAAAA==.Venatrix:BAAALgAECgYJEQAAAA==.Vendrith:BAAALgADCgcJBwAAAA==.Veraxi:BAAALgADCgYJCwABLgAECgUJCgADAAAAAA==.Vessen:BAAALgADCgUJBwAAAA==.',
Vi='Vidascare:BAAALgAECgkJAgAAAA==.Vidu:BAAALgADCgUJBQAAAA==.Vision:BAAALgADCgYJBgAAAA==.',
Vl='Vluthier:BAAALgADCgYJBgAAAA==.',
Vo='Voidshatter:BAABLgAECn8ZAAMXAAYJaweQNgC+AAAXAAYJaweQNgC+AAAJAAYJcQID2wBaAAAAAA==.Vonderick:BAAALgAECgQJAwAAAA==.Voodoodog:BAAALgAECgMJBQABLgAECgYJDwADAAAAAA==.',
Vu='Vulgrimm:BAAALgAECgMJAwAAAA==.',
Vy='Vynlorellas:BAAALgAECgEJAQAAAA==.Vyéra:BAAALgADCgMJBgAAAA==.',
['Vè']='Vèsper:BAAALgAECgMJBQABLgAECgMJCQADAAAAAA==.',
Wa='Wakawli:BAAALgADCgYJBgAAAA==.Walex:BAAALgAECgkJBwAAAA==.Wally:BAAALgADCgMJAwAAAA==.Wardmneagle:BAAALgADCgUJCgAAAA==.Wargasm:BAAALgAECgQJBwABLgAECgcJDgADAAAAAA==.Watongo:BAAALgAECgUJBwAAAA==.Watsaheal:BAAALgAECgEJAQAAAA==.',
Wi='Wildborn:BAAALgADCgMJAwAAAA==.Willidan:BAAALgADCgEJAQAAAA==.Winwood:BAAALgADCgUJBwAAAA==.Withdrawals:BAAALgADCgYJBgABLgAECgMJCQADAAAAAA==.',
Wo='Woeify:BAABLgAECn8VAAIcAAcJ5xSuDgDRAQAcAAcJ5xSuDgDRAQAAAA==.',
Wr='Wreckless:BAAALgAECggJCAABLgAFFAMJBQAfALIVAA==.',
Wy='Wynce:BAAALgAECgUJCAAAAA==.',
Xa='Xalana:BAAALgADCgQJBAAAAA==.Xandaer:BAAALgAECgIJAwAAAA==.Xarn:BAABLgAECn8hAAIGAAkJtwf4cABNAQAGAAkJtwf4cABNAQAAAA==.',
Xc='Xcïte:BAABLgAECn8XAAQpAAgJwBoIIwCQAQApAAYJ9hwIIwCQAQAmAAMJ3RtaWADUAAAoAAUJsg91SAC2AAAAAA==.',
Xe='Xenroz:BAAALgADCgcJBwAAAA==.',
Ya='Yagudo:BAAALgADCgEJAQAAAA==.Yandòur:BAAALgADCgIJAgABLgAECgkJGQASAIkPAA==.',
Ye='Yemon:BAAALgAECgUJBQAAAA==.',
Yo='Yodä:BAAALgADCgcJBwAAAA==.Yourlock:BAAALgADCgUJBQAAAA==.',
Yr='Yrelya:BAAALgAECgYJBgAAAA==.',
Yu='Yuji:BAABLgAECn9AAAIMAAkJzBJnPQD3AQAMAAkJzBJnPQD3AQAAAA==.',
Za='Zalectra:BAACLgAFFH8UAAIYAAQJHiFsCAB1AQAYAAQJHiFsCAB1AQAuAAQKfz4AAxgACQm2JUIAAMUDABgACQm2JUIAAMUDACEAAgmhFqIlAHAAAAAA.',
Ze='Zelila:BAAALgAECgUJBAAAAA==.',
['Zü']='Zügzüg:BAAALgADCgEJAQAAAA==.',
['Âu']='Âurâ:BAAALgAECgUJBwAAAA==.',
['Ål']='Ålloria:BAAALgAECgYJEwAAAA==.',
['ßl']='ßlackßetty:BAAALgADCgYJBwABLgADCgkJCQADAAAAAA==.',
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
