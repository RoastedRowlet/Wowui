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

local lookup = {'Evoker-Augmentation','Unknown-Unknown','Mage-Frost','Hunter-Survival','Hunter-BeastMastery','Monk-Brewmaster','Warlock-Demonology','Warrior-Fury','Paladin-Retribution','Paladin-Protection','Paladin-Holy','DemonHunter-Devourer','Shaman-Restoration','Monk-Windwalker','Druid-Balance','Druid-Guardian','Druid-Restoration','Mage-Arcane','Warlock-Destruction','DeathKnight-Unholy','DeathKnight-Blood','Evoker-Devastation','Warrior-Arms','DemonHunter-Havoc','Monk-Mistweaver','DeathKnight-Frost','Shaman-Elemental','Shaman-Enhancement','Evoker-Preservation','Rogue-Assassination','Rogue-Subtlety','Druid-Feral','Hunter-Marksmanship','Warlock-Affliction','Mage-Fire','Priest-Holy','Priest-Shadow','Warrior-Protection','Rogue-Outlaw','Priest-Discipline','DemonHunter-Vengeance',}
local provider = {region='US',realm='Gnomeregan',name='US',type='weekly',zone=46,date='2026-06-13',data={Ac='Acehuntura:BAAALgAECgEJAgAAAA==.',
Ad='Adaric:BAAALgAFFAEJAQAAAA==.',
Af='Afflicea:BAAALgAECgMJAwAAAA==.',
Ah='Ahava:BAAALgAECgQJBAAAAA==.',
Ai='Aidoneiscus:BAAALgAECgUJCgABLgAFFAYJEwABAH4aAA==.Ainokea:BAAALgAECgIJAgABLgAECgYJDQACAAAAAA==.Aiyaiyai:BAAALgAECgYJDQAAAA==.',
Aj='Ajani:BAAALgAECgYJDAAAAA==.',
Ak='Akamini:BAAALgAECgYJBwAAAA==.Akawli:BAAALgAECgIJAwAAAA==.',
Al='Alall:BAAALgAECgMJBgAAAA==.Alauth:BAAALgAECgIJAwAAAA==.Aliceandreia:BAAALgADCgUJCgAAAA==.Alliethra:BAAALgAECgQJBgAAAA==.',
Am='Aminall:BAAALgAECgYJDQAAAA==.',
An='Anarreth:BAAALgADCgUJCgAAAA==.Andahla:BAAALgADCgkJCwAAAA==.Andore:BAABLgAECn8gAAIDAAcJvhl0XADGAQADAAcJvhl0XADGAQAAAA==.Anewbyss:BAAALgAFFAEJAQAAAA==.Angrymurloc:BAABLgAECn8aAAMEAAcJTAxtKgBOAQAEAAcJTAxtKgBOAQAFAAUJMQLY8QBpAAAAAA==.Anthonie:BAAALgADCgYJBgAAAA==.Antoer:BAAALgAECgIJAgAAAA==.Anwyll:BAAALgADCgcJDAAAAA==.',
Ao='Aoir:BAAALgAECgQJBgAAAA==.',
Ap='Aposthmighty:BAAALgAECgYJEAAAAA==.',
Ar='Arcancis:BAAALgADCgQJBAAAAA==.Ariyia:BAAALgADCgcJBgAAAA==.Arlona:BAAALgAECgIJAwABLgAECgYJEAACAAAAAA==.Arms:BAAALgAECgcJEAAAAA==.Artemyss:BAAALgADCgEJAQAAAA==.',
As='Ashanara:BAAALgAECgQJBAABLgAECgYJDQACAAAAAA==.Asher:BAAALgADCgEJAQAAAA==.Ashnact:BAAALgAECgIJDAAAAA==.Ashraki:BAAALgAECgEJAQAAAA==.Ashreign:BAAALgAECgkJCQAAAA==.Asl:BAAALgADCgcJBwAAAA==.Asonnari:BAAALgADCgEJAQAAAA==.Astraeal:BAABLgAECn8UAAIGAAYJwRFVPAAIAQAGAAYJwRFVPAAIAQAAAA==.',
At='Atreana:BAABLgAECn82AAIHAAkJ4hW3LwAYAgAHAAkJ4hW3LwAYAgAAAA==.Attykus:BAABLgAECn8xAAIIAAgJ/BM1MQDoAQAIAAgJ/BM1MQDoAQAAAA==.',
Av='Avalerion:BAABLgAECn8eAAMJAAkJTxoZIACFAgAJAAkJTxoZIACFAgAKAAIJbB0IMgCYAAAAAA==.Avij:BAAALgAECgQJCwABLgAECgYJCQACAAAAAA==.',
Ay='Ayoreo:BAAALgADCgMJAwAAAA==.',
Az='Azmodon:BAAALgADCgEJAwAAAA==.',
['Añ']='Añathema:BAAALgAECgMJBAAAAA==.',
Ba='Baldd:BAAALgAECgUJBQAAAA==.Banfultoxxin:BAAALgADCggJDwAAAA==.Barrellroll:BAAALgADCgkJCQAAAA==.Bastam:BAAALgAECgIJAgABLgAECgIJBQACAAAAAA==.Bat:BAAALgAECgQJBwAAAA==.',
Be='Bearlyhealz:BAAALgADCgkJBQAAAA==.Beercats:BAAALgADCgMJBgAAAA==.Bentotc:BAAALgAECgIJAwAAAA==.',
Bi='Bighoot:BAAALgAECgQJCgAAAA==.Bigmancow:BAABLgAECn8nAAILAAkJTw/wKQC8AQALAAkJTw/wKQC8AQAAAA==.Bigpoppapump:BAAALgAECgQJBgAAAA==.Biomancer:BAAALgADCgYJBgAAAA==.Bismofungion:BAAALgADCgcJEAAAAA==.',
Bl='Bladestalker:BAAALgAECgEJAQAAAA==.Blindmayhem:BAAALgAECgEJAQAAAA==.Bludgens:BAAALgADCgIJAgAAAA==.Bluecoral:BAAALgADCgEJAQAAAA==.Blunter:BAABLgAECn8TAAIMAAcJ5gYdlgDxAAAMAAcJ5gYdlgDxAAAAAA==.Blushtime:BAAALgADCgIJAgAAAA==.Bluwhale:BAACLgAFFH8fAAINAAgJJB0ZAgDFAgANAAgJJB0ZAgDFAgAuAAQKfyYAAg0ACQk+JCcLAAIDAA0ACQk+JCcLAAIDAAAA.',
Bo='Bocchi:BAAALgAECgEJAQAAAA==.Bodanky:BAAALgAECgMJBQAAAA==.Bormor:BAAALgAECggJEAAAAA==.Bowdacious:BAAALgAECgUJEAAAAA==.Boötes:BAAALgADCgcJBwAAAA==.',
Br='Brago:BAAALgAECgEJAQAAAA==.Braini:BAAALgADCgEJAQAAAA==.Brainpath:BAAALgAFFAIJAgAAAA==.Brasidias:BAAALgADCgQJBAAAAA==.Brickingkeys:BAAALgAECgIJBQAAAA==.Brumak:BAAALgAECgkJCgAAAA==.Bruno:BAABLgAECn8qAAMKAAkJrRgEDQDxAQAKAAkJrRgEDQDxAQAJAAQJKQcQ+gCfAAAAAA==.',
Bu='Budthespud:BAAALgAECgEJAQAAAA==.Burland:BAAALgAFFAIJAgAAAA==.',
['Bá']='Báthory:BAABLgAECn8UAAIMAAkJohwxFgCQAgAMAAkJohwxFgCQAgAAAA==.',
Ca='Caedus:BAAALgADCgYJBgAAAA==.Cal:BAAALgAECgYJDAABLgAFFAIJCAAGADMXAA==.Caladin:BAAALgAECgQJBAABLgAFFAIJCAAGADMXAA==.Calamity:BAAALgADCgQJBAAAAA==.Callistos:BAACLgAFFH8IAAIGAAIJMxdhQQCaAAAGAAIJMxdhQQCaAAAuAAQKfzwAAwYACQlYHlIIAKwCAAYACQlYHlIIAKwCAA4AAgkgEZyXADUAAAAA.Camelshammy:BAAALgAECgYJDgAAAA==.Caradyn:BAAALgADCgUJBQABLgAECgYJFAADACYTAA==.Caris:BAAALgAECgMJAwAAAA==.Castianna:BAAALgAECgUJEQAAAA==.',
Ce='Cebastian:BAAALgAECgYJDQAAAA==.Cedarpoint:BAAALgADCggJEgAAAA==.Celoria:BAAALgADCgUJCQAAAA==.Century:BAABLgAECn8yAAQPAAkJ+xyvDwBjAgAPAAkJXBmvDwBjAgAQAAgJcRjeDwDkAQARAAIJFRGC0gAwAAAAAA==.Cerriwyn:BAAALgAECgEJAQAAAA==.Cery:BAAALgAECgEJAQAAAA==.',
Ch='Cheochan:BAAALgADCgYJDwAAAA==.Chizami:BAAALgAECggJDAABLgAFFAgJFQALANEMAA==.Chocostarmie:BAAALgADCgQJBAAAAA==.Chug:BAABLgAECn8eAAIOAAkJlyB7CQCqAgAOAAkJlyB7CQCqAgAAAA==.',
Ci='Circa:BAABLgAECn8pAAMDAAkJMhVKQQAVAgADAAkJ5BRKQQAVAgASAAQJWg7dEAC0AAAAAA==.Cithrel:BAABLgAECn8ZAAITAAkJiQ8PFQD/AAATAAkJiQ8PFQD/AAAAAA==.',
Cl='Claylemian:BAAALgAECgMJAwAAAA==.',
Co='Conqubine:BAAALgADCgkJDgAAAA==.Corban:BAAALgAECgEJAwAAAA==.',
Cr='Creolix:BAAALgADCgYJBgABLgAECgYJCAACAAAAAA==.Crocklock:BAABLgAECn8ZAAIHAAcJ6hVpZQByAQAHAAcJ6hVpZQByAQAAAA==.',
Cu='Cuddlyblood:BAAALgAECgEJAQAAAA==.Cujo:BAAALgADCgMJAwAAAA==.',
['Cà']='Càssiàn:BAAALgADCgIJAgAAAA==.',
Da='Dallia:BAACLgAFFH8FAAIJAAIJ1gH4pgBnAAAJAAIJ1gH4pgBnAAAuAAQKfy8AAwkABwnhB/jgANkAAAkABwnQBvjgANkAAAoAAwntBapCAFQAAAAA.Damnatio:BAABLgAECn8gAAIJAAkJmSTKEADeAgAJAAkJmSTKEADeAgAAAA==.Damonster:BAAALgAECgIJAwAAAA==.Danossa:BAAALgAECgEJAwAAAA==.Darkclement:BAABLgAECn8VAAIFAAcJsx4IOQD2AQAFAAcJsx4IOQD2AQABLgAFFAMJCQAJAE4TAA==.Darkin:BAAALgAECgcJCAAAAA==.Darkmist:BAAALgADCgUJBQAAAA==.Darkwiz:BAABLgAECn8VAAIUAAkJCwfHggBbAQAUAAkJCwfHggBbAQAAAA==.Davrimbasher:BAAALgADCgEJAQAAAA==.',
De='Deadlydk:BAAALgADCgMJAwAAAA==.Deathbybob:BAABLgAECn8XAAIVAAYJ6hgZHgBjAQAVAAYJ6hgZHgBjAQAAAA==.Deathgriped:BAAALgAECgUJDgAAAA==.Deeper:BAABLgAECn8jAAMPAAgJVwvhNgA2AQAPAAgJVwvhNgA2AQARAAMJagE52wAoAAAAAA==.Deezmoonz:BAAALgADCgYJCQAAAA==.Dementos:BAAALgADCgkJCgAAAA==.Demonofwar:BAAALgADCgYJDAABLgAECgYJCAACAAAAAA==.Devils:BAAALgAECgUJCQAAAA==.Dezzii:BAAALgAECgIJAgAAAA==.',
Di='Dirin:BAAALgAECgUJDQABLgAECgUJCgACAAAAAA==.Disneymagic:BAAALgADCgUJBwAAAA==.Divacup:BAAALgADCgEJAQAAAA==.',
Dm='Dmaan:BAAALgADCgMJAwAAAA==.',
Do='Doomflower:BAAALgAECgEJAQAAAA==.',
Dr='Dragonpebble:BAAALgADCgYJBgABLgAECgkJHwAHADMUAA==.Drahalah:BAABLgAECn8eAAIUAAgJXR+rOAAaAgAUAAgJXR+rOAAaAgAAAA==.Drakeji:BAABLgAECn81AAMBAAkJWQt8MQBuAQABAAkJWQt8MQBuAQAWAAQJKAGhPwAxAAAAAA==.Dreamliner:BAAALgAECgYJBgAAAA==.Drezind:BAAALgAECgQJBAAAAA==.Drhealalot:BAAALgAECgEJAQAAAA==.Drugar:BAAALgAFFAEJAQABLgAFFAUJEgAXAHUcAA==.',
Du='Dumplingg:BAAALgAECggJDAAAAA==.',
Ea='Earthvoodoo:BAAALgAECgYJDwAAAA==.',
Eb='Eberkenezer:BAAALgAECgEJAQAAAA==.Ebonlight:BAAALgADCgkJFgAAAA==.',
Ec='Ecnyw:BAAALgADCgMJAwABLgAECgUJCAACAAAAAA==.',
Ed='Edence:BAAALgAECgMJAwAAAA==.',
Eh='Ehunter:BAAALgAECgUJDQAAAA==.',
Ei='Eillea:BAAALgADCgQJBAAAAA==.',
El='Elegant:BAAALgAECgkJBwAAAA==.Elspeth:BAAALgAECgIJAgAAAA==.Elsyria:BAAALgADCgIJAgABLgAFFAgJIgAJAAEhAA==.Eluneslight:BAAALgAECgEJAwAAAA==.',
Em='Emmeri:BAAALgAECgQJBwABLgAECggJMQAIAPwTAA==.',
En='Ender:BAAALgAECgIJAgAAAA==.',
Ep='Epi:BAABLgAECn8UAAIYAAgJshKWNQDiAAAYAAgJshKWNQDiAAAAAA==.',
Er='Erianis:BAAALgADCgMJAwAAAA==.Erniethemonk:BAAALgAECgYJEAAAAA==.',
Ev='Evianda:BAAALgADCgkJEAAAAA==.',
Ez='Ezale:BAAALgAECgkJEwAAAA==.Ezpz:BAAALgAECgYJEgAAAA==.',
Fa='Falsetto:BAAALgAECgEJAgAAAA==.Fameral:BAAALgAECgEJAQAAAA==.Faramír:BAAALgAECgQJCAAAAA==.Fatébringer:BAAALgAECggJDgABLgAECgcJDgACAAAAAA==.Fauhna:BAAALgAECgEJAQABLgAFFAIJBgAJACMiAA==.',
Fe='Fennek:BAABLgAECn8UAAIFAAgJng+/WgCQAQAFAAgJng+/WgCQAQAAAA==.',
Fi='Fiønaviolet:BAAALgADCgcJBwAAAA==.',
Fo='Fourth:BAAALgAECgEJAgABLgAECgcJEAACAAAAAA==.',
Fr='Frayla:BAAALgADCgEJAQAAAA==.',
Fu='Furrywhenwet:BAAALgAFFAEJAQAAAA==.Fuzzyxbutt:BAAALgAECgYJDgAAAA==.',
Fy='Fyaaga:BAAALgAECgQJBAABLgAFFAYJBwAZAKAOAA==.',
Ga='Garaylo:BAACLgAFFH8iAAIJAAgJASEZBACcAgAJAAgJASEZBACcAgAuAAQKfykAAgkACQn1JMACAKwDAAkACQn1JMACAKwDAAAA.Garroar:BAAALgADCgcJCAAAAA==.',
Ge='Geed:BAAALgADCgEJAQAAAA==.Gewnzilla:BAAALgAECgIJAgAAAA==.',
Gg='Ggxd:BAAALgADCgkJEAAAAA==.',
Gh='Ghosst:BAABLgAECn8jAAIEAAkJtiLuAgAIAwAEAAkJtiLuAgAIAwAAAA==.',
Gi='Gilberticus:BAAALgADCgMJAwABLgAECgkJUAAOAMUiAA==.Gimlithekind:BAAALgAECgEJAQAAAA==.',
Gl='Glen:BAAALgADCgMJAwAAAA==.',
Gn='Gnobliterate:BAABLgAECn8oAAQUAAkJMRI7bACKAQAUAAkJ9g87bACKAQAaAAYJNQ2/HADkAAAVAAIJLROCRwBsAAAAAA==.Gnobolts:BAAALgAECgEJAQAAAA==.Gnobull:BAAALgAFFAEJAQAAAA==.Gnochi:BAAALgAECgcJBwAAAA==.Gnudgnimish:BAAALgAFFAIJBAABLgAFFAUJBwAGALkZAA==.',
Go='Goldenblight:BAAALgAECgYJCwAAAA==.Goldenchi:BAAALgAECgEJAQAAAA==.Goldenrage:BAAALgAECgQJBAAAAA==.Gomper:BAAALgAECgMJBAAAAA==.Gonforgood:BAAALgADCgYJBgAAAA==.Goonmaxing:BAAALgADCgMJAwAAAA==.',
Gr='Grimclaw:BAAALgADCgYJDgAAAA==.Grimmrot:BAAALgAECgYJEgAAAA==.Grimmz:BAAALgADCggJCQAAAA==.Grizk:BAAALgADCgEJAQAAAA==.',
Gu='Guttris:BAAALgAECgYJEwAAAA==.',
Gw='Gwaineedk:BAAALgAECgMJBAAAAA==.',
Ha='Haikusen:BAAALgADCgYJBAABLgAECgYJCAACAAAAAA==.Halstron:BAACLgAFFH8GAAIJAAIJIyK9eAC9AAAJAAIJIyK9eAC9AAAuAAQKfy0AAwkACQm/IHoPAOcCAAkACQmPIHoPAOcCAAoABQl7FXIhAAUBAAAA.Harribel:BAABLgAECn8bAAQVAAgJuwUBRQB3AAAUAAYJ1wNlCgGaAAAVAAQJtwYBRQB3AAAaAAIJ8gHdFgA1AAAAAA==.Hassan:BAAALgAECgEJAQAAAA==.',
He='Heliòs:BAAALgAECgUJBgAAAA==.Hellwár:BAAALgADCgYJBgAAAA==.',
Ho='Hogfu:BAAALgAECgQJBAAAAA==.Hogshock:BAABLgAECn8bAAQbAAkJTRXRJgDcAQAbAAkJTRXRJgDcAQAcAAMJXgfMJACLAAANAAEJhA1G3wAoAAAAAA==.Holocharizrd:BAAALgADCgcJCQAAAA==.Holyrequiem:BAAALgAECgUJBQAAAA==.Holyzel:BAAALgAECgkJEgAAAA==.Hotnsassie:BAAALgADCgMJCQAAAA==.Hound:BAAALgADCgUJCAAAAA==.Hoyt:BAAALgADCgcJBwAAAA==.',
Hs='Hsimingjung:BAACLgAFFH8HAAMGAAUJuRmzGABXAQAGAAUJuRmzGABXAQAOAAEJNQtUQgA2AAAuAAQKfykAAwYACQnLIRYHAMQCAAYACQnLIRYHAMQCAA4ABAlFIfslAIIBAAAA.',
Hu='Humanic:BAAALgAECgIJAwAAAA==.Huntari:BAAALgAECgEJAwAAAA==.',
Hy='Hylie:BAACLgAFFH8NAAIHAAMJYgl3gAC/AAAHAAMJYgl3gAC/AAAuAAQKfx8AAgcACQnHEFlaALkBAAcACQnHEFlaALkBAAAA.',
['Hè']='Hèlla:BAAALgADCgkJFQAAAA==.',
Ig='Ignisky:BAAALgAECgcJDgABLgAFFAUJEgAXAHUcAA==.',
Il='Illidarie:BAAALgADCgUJCAAAAA==.',
Im='Imsofresh:BAAALgADCgEJAQAAAA==.',
In='Innitchiwa:BAAALgAECgEJAgAAAA==.Inte:BAAALgADCgYJBgAAAA==.Inzi:BAAALgAECgEJAwAAAA==.',
Iz='Izgin:BAABLgAECn8UAAIDAAYJJhM5uAASAQADAAYJJhM5uAASAQAAAA==.',
Ja='Jadeyn:BAAALgADCgMJAwAAAA==.Jaime:BAAALgADCgYJCQABLgAECgYJCAACAAAAAA==.Jalet:BAAALgADCgcJDQAAAA==.Janie:BAAALgADCgUJCAABLgADCgYJBgACAAAAAA==.Jantar:BAABLgAECn8bAAIRAAkJ4xiFFwCIAgARAAkJ4xiFFwCIAgAAAA==.Jasonbjorne:BAAALgAECgEJAQAAAA==.',
Je='Jebbyclipse:BAAALgAECgQJCAAAAA==.Jenzö:BAABLgAECn8bAAIbAAYJBhF8SAAOAQAbAAYJBhF8SAAOAQAAAA==.Jeramya:BAAALgADCgQJBAAAAA==.',
Jo='Joeviben:BAABLgAECn8aAAIJAAcJ6grhrQAfAQAJAAcJ6grhrQAfAQAAAA==.Jormungandr:BAAALgADCgYJCgABLgADCgcJBwACAAAAAA==.',
Ju='Jugsy:BAABLgAECn8ZAAIDAAkJtBf3LQBfAgADAAkJtBf3LQBfAgAAAA==.Juliza:BAAALgADCgQJBAAAAA==.Jungfer:BAAALgAECgMJBAAAAA==.',
Ka='Kaerodora:BAAALgADCgYJBgAAAA==.Kalasan:BAAALgAECgIJAgAAAA==.Kaldread:BAAALgAECgMJAwAAAA==.Kaligo:BAABLgAECn9CAAMbAAkJQBqTFABDAgAbAAkJQBqTFABDAgAcAAQJrgSuIgCrAAAAAA==.Kalistus:BAABLgAECn8bAAIMAAkJtww3WAB7AQAMAAkJtww3WAB7AQAAAA==.Kallistos:BAAALgAECgEJAQABLgAFFAIJCAAGADMXAA==.Kalygos:BAAALgAECgQJBAABLgAFFAIJCAAGADMXAA==.Karall:BAAALgAECgEJAQAAAA==.Karetha:BAAALgAECgUJCQAAAA==.Katar:BAAALgADCgMJAwAAAA==.Katreset:BAAALgAECgUJCAAAAA==.',
Kd='Kdavid:BAAALgADCgUJCgAAAA==.',
Ke='Kebsy:BAABLgAECn87AAIOAAkJPiQ9AwAuAwAOAAkJPiQ9AwAuAwAAAA==.Kegfupanda:BAAALgAFFAEJAQAAAA==.Keleion:BAABLgAECn8nAAIMAAcJzhDjgQAYAQAMAAcJzhDjgQAYAQABLgAECgkJEwACAAAAAA==.Kelements:BAAALgAFFAEJAQAAAA==.Kelyessada:BAAALgADCgYJBgAAAA==.Kevonjuravis:BAABLgAECn81AAMGAAcJpRAEMwAyAQAGAAcJUQ4EMwAyAQAOAAUJWxAuXAChAAAAAA==.',
Kh='Khalya:BAAALgAECgUJBQAAAA==.Khalyl:BAABLgAECn8WAAIYAAUJJRRVNADpAAAYAAUJJRRVNADpAAAAAA==.Khari:BAAALgAECgEJAQAAAA==.Kheart:BAAALgAECgEJAQAAAA==.Kholy:BAAALgADCgYJBgAAAA==.',
Ki='Kidrash:BAAALgADCgcJCAAAAA==.Killah:BAAALgAECgQJBgAAAA==.Kimegh:BAAALgADCgIJAgAAAA==.Kitsunae:BAAALgADCgcJHgAAAA==.',
Kl='Kleredan:BAAALgAECgkJBgAAAA==.',
Ko='Koder:BAACLgAFFH8TAAIBAAYJfhoSHAB4AQABAAYJfhoSHAB4AQAuAAQKfzQABAEACAmtIbEGABIDAAEACAmtIbEGABIDABYABwlXGRAHANABAB0AAgkOArJEAEoAAAAA.Kozmoker:BAAALgAECgYJBgAAAA==.',
Kr='Krondys:BAAALgAECgYJBgAAAA==.Krytus:BAAALgAECgEJAgAAAA==.',
Ku='Kungpaochik:BAAALgAECgIJAwAAAA==.Kupó:BAAALgADCgUJBQABLgAECgYJDAACAAAAAA==.',
Ky='Kyakdeath:BAABLgAECn81AAMUAAgJUhrfWAC5AQAUAAgJUhrfWAC5AQAaAAEJKwn1OgAuAAAAAA==.',
Kz='Kzo:BAAALgAECgYJDQAAAA==.',
La='Lailyre:BAAALgADCgQJBAAAAA==.Larroy:BAAALgAECgEJAQAAAA==.',
Le='Lecker:BAAALgAECgEJAQAAAA==.Legado:BAAALgAECgUJBwAAAA==.',
Li='Lilbigcow:BAAALgAECgEJAwAAAA==.Lilithxander:BAAALgAECgUJCQAAAA==.Lilshooter:BAAALgAECgIJAwABLgAFFAQJBAACAAAAAA==.Lizzybordan:BAAALgAECgcJEQAAAA==.',
Ll='Llaaroyy:BAAALgADCgEJAQAAAA==.Llarroii:BAAALgAECgEJAgAAAA==.',
Lo='Lovar:BAAALgADCgYJBgAAAA==.',
Lu='Lucinick:BAABLgAECn8kAAMeAAYJ+Bm9CgCFAQAeAAYJ+Bm9CgCFAQAfAAQJlApLPADVAAAAAA==.Lucy:BAAALgADCgIJAgAAAA==.Luxdiei:BAAALgAECgYJBgAAAA==.Luzziem:BAAALgAECgcJDwAAAA==.',
Ly='Lynx:BAAALgAECgEJBQAAAA==.',
Ma='Mariskama:BAABLgAECn8hAAIFAAkJ2gVhcABbAQAFAAkJ2gVhcABbAQAAAA==.Markusthered:BAAALgAECgMJBAAAAA==.Mazza:BAAALgAECgkJEQAAAA==.',
Mc='Mcbong:BAAALgAECgQJBwAAAA==.',
Me='Mello:BAAALgADCgYJBgAAAA==.Meowimabear:BAAALgADCgkJEAABLgAECgkJIwAEALYiAA==.Metal:BAAALgAECgQJDgAAAA==.Method:BAAALgADCgEJAQAAAA==.Meuccí:BAAALgAECgcJCwAAAA==.',
Mh='Mhelora:BAABLgAECn8VAAIRAAYJ3wsrawDwAAARAAYJ3wsrawDwAAAAAA==.',
Mi='Mikkais:BAAALgAECgYJDgAAAA==.Mimacho:BAAALgAECgQJCAAAAA==.Minimini:BAACLgAFFH8UAAIZAAQJExsZJQA2AQAZAAQJExsZJQA2AQAuAAQKfy4AAhkACQkJHM8RAIwCABkACQkJHM8RAIwCAAAA.Minni:BAAALgAFFAEJAwAAAA==.',
Mo='Moolin:BAABLgAECn8oAAIgAAkJUwkPGwAuAQAgAAkJUwkPGwAuAQAAAA==.Moranthe:BAAALgAECgcJDAABLgAFFAYJBwAZAKAOAA==.Mordsyth:BAAALgAECgYJCgAAAA==.Morrowind:BAAALgADCgYJBgAAAA==.',
Mu='Muggni:BAAALgAECgkJEQAAAA==.Muggypew:BAABLgAECn8UAAIhAAkJRgG7LQBeAAAhAAkJRgG7LQBeAAAAAA==.Munder:BAABLgAECn8mAAMiAAkJgB20AwBzAgAiAAkJcBy0AwBzAgAHAAgJ/xmCUQCmAQAAAA==.Mustymuppet:BAACLgAFFH8ZAAIHAAUJmBdORAA8AQAHAAUJmBdORAA8AQAuAAQKfygAAwcACAnzGn42AP4BAAcACAnzGn42AP4BABMAAQlnD7VuADgAAAAA.',
My='Myrotheron:BAAALgADCgMJAwAAAA==.Mysticmeat:BAAALgAECgEJAQAAAA==.Mythicalbug:BAAALgADCgEJAQAAAA==.Mythuneran:BAABLgAECn8cAAIjAAkJdhejAgAeAgAjAAkJdhejAgAeAgAAAA==.',
['Mø']='Mørzanna:BAAALgAECgYJBwAAAA==.',
Na='Nanookigaluk:BAAALgADCgYJBgAAAA==.Narrator:BAAALgAECgEJAgAAAA==.Navikz:BAAALgADCgUJBQAAAA==.',
Ne='Nekrose:BAABLgAECn8aAAIUAAgJwiKIHwCKAgAUAAgJwiKIHwCKAgAAAA==.Nemini:BAABLgAECn8UAAMkAAYJFAt6OwADAQAkAAYJFAt6OwADAQAlAAEJ7AGwlwAcAAAAAA==.Nena:BAABLgAECn8mAAIPAAYJbBPOOgAjAQAPAAYJbBPOOgAjAQAAAA==.Nenacurses:BAAALgAECgMJBwABLgAECgYJJgAPAGwTAA==.Nephilia:BAAALgADCgYJBgAAAA==.Newfy:BAAALgAFFAEJAwAAAA==.',
Ni='Ninjamage:BAAALgAECgUJBQAAAA==.Nistis:BAAALgAECgYJEQAAAA==.Niteshroud:BAAALgADCgMJAwAAAA==.Nithendroz:BAABLgAECn8YAAMWAAcJZgqrFQC0AAAWAAQJZgurFQC0AAABAAMJaAh4fwBbAAAAAA==.Nity:BAAALgAECgQJBAAAAA==.Nivek:BAAALgAECgEJAQAAAA==.',
Nn='Nnivek:BAAALgAECgEJAQAAAA==.',
No='Noctaurus:BAABLgAECn8iAAIUAAkJ1QnjZgCWAQAUAAkJ1QnjZgCWAQAAAA==.Noczorro:BAAALgADCgYJBgAAAA==.Nomadhew:BAAALgAECgcJBwAAAA==.Noraice:BAAALgAECgEJAwAAAA==.Notagain:BAACLgAFFH8sAAIJAAgJxhuiBgBhAgAJAAgJxhuiBgBhAgAuAAQKfy4AAgkACQkBI5YHAFoDAAkACQkBI5YHAFoDAAAA.Notapally:BAAALgAECgQJBAAAAA==.Noxcorvus:BAAALgAECgcJDQAAAA==.',
Nu='Nuvo:BAAALgADCgYJBgAAAA==.',
Ny='Nylloc:BAAALgAECgkJCQAAAA==.Nymphàdoria:BAAALgAECgEJAQAAAA==.Nyuxx:BAABLgAECn8VAAINAAYJbBNHUQBpAQANAAYJbBNHUQBpAQAAAA==.',
['Nê']='Nêwfie:BAAALgAECgEJAwABLgAFFAEJAwACAAAAAA==.',
Oc='Oceanic:BAAALgADCgYJCwAAAA==.Oceans:BAAALgAECgEJAQAAAA==.',
Od='Odphijor:BAAALgAECgkJAQAAAA==.',
Ol='Olenza:BAAALgAECgQJBQAAAA==.Olgreeneyes:BAAALgAECgIJBAAAAA==.',
Or='Orangewhale:BAABLgAECn8UAAIRAAYJChgpTABzAQARAAYJChgpTABzAQAAAA==.',
Ou='Out:BAAALgAECgYJCwAAAA==.',
Ox='Oxidation:BAAALgADCgcJGgAAAA==.',
Pa='Painspongie:BAAALgADCgQJBQAAAA==.Patsajak:BAAALgADCgEJAQAAAA==.Pavo:BAAALgADCgYJBgAAAA==.',
Pe='Pebbleshifts:BAAALgAECgMJAwAAAA==.Peejean:BAAALgAECgYJBgAAAA==.Peyblade:BAAALgAECgYJBgABLgAECgkJHgASABghAA==.Peybreak:BAAALgAECgIJAgABLgAECgkJHgASABghAA==.Peychi:BAAALgAECgUJBgABLgAECgkJHgASABghAA==.Peycicle:BAABLgAECn8eAAISAAkJGCFKAQDOAgASAAkJGCFKAQDOAgAAAA==.Peysanity:BAAALgAECgQJBAABLgAECgkJHgASABghAA==.Peystruction:BAAALgAECgEJAgABLgAECgkJHgASABghAA==.Peytan:BAABLgAECn8VAAMMAAkJLxj/IgBCAgAMAAkJLxj/IgBCAgAYAAEJuQmmdgAuAAABLgAECgkJHgASABghAA==.Peytin:BAAALgAECgQJBAABLgAECgkJHgASABghAA==.',
Ph='Phantasm:BAAALgADCgQJBwAAAA==.Phemoid:BAAALgADCgkJCQAAAA==.',
Pi='Pinkywhale:BAAALgAFFAIJAgAAAA==.Pippa:BAABLgAECn8pAAIdAAkJ4xyVBADeAgAdAAkJ4xyVBADeAgAAAA==.Pitythefu:BAAALgADCgcJBQAAAA==.',
Pl='Planett:BAABLgAECn8lAAMNAAkJChwZFwCNAgANAAkJChwZFwCNAgAbAAEJFgOovQAcAAAAAA==.',
Po='Poetuck:BAABLgAECn8yAAIDAAkJnxS0TADyAQADAAkJnxS0TADyAQAAAA==.Pokeyruler:BAAALgAECgIJAgAAAA==.Pokeythorn:BAAALgADCgkJFwAAAA==.Pookießear:BAAALgADCgUJBQAAAA==.Powdrpufgirl:BAAALgADCgMJAwABLgAECgYJCAACAAAAAA==.',
Pr='Proko:BAABLgAECn8pAAMbAAkJFxLLPQA5AQAbAAcJ2BLLPQA5AQANAAQJLBW9bgAKAQAAAA==.',
Ps='Psychovoodoo:BAAALgAECgIJBwAAAA==.',
Pu='Publicpool:BAAALgADCgEJAQAAAA==.Purfec:BAAALgADCgcJDAAAAA==.',
Qa='Qatka:BAAALgAECgQJBQAAAA==.',
Qu='Quiver:BAABLgAECn8iAAIJAAgJ1Q0MgwBmAQAJAAgJ1Q0MgwBmAQAAAA==.Quizle:BAAALgAECgEJAgAAAA==.',
['Qì']='Qìlen:BAABLgAECn8VAAIVAAcJzgyNMQDUAAAVAAcJzgyNMQDUAAAAAA==.',
Ra='Raein:BAABLgAECn8rAAMNAAkJqyLHAwB9AwANAAkJqyLHAwB9AwAbAAYJnBcMQgAnAQAAAA==.Raginghog:BAAALgAECgUJCAAAAA==.Rainn:BAACLgAFFH8IAAMLAAMJowvbMACqAAALAAMJowvbMACqAAAJAAEJ6AHwxAA1AAAuAAQKfxcABAsACAkGFYAbACYCAAsACAkGFYAbACYCAAoABAmuBZ41AG4AAAkAAQlGBCq9ASEAAAAA.Rainnsoul:BAAALgAECgYJDgAAAA==.Rakkclaw:BAAALgAECgEJAQABLgAECgEJAQACAAAAAA==.Ralofurius:BAAALgAECgYJCQAAAA==.Rasril:BAAALgAFFAEJAQAAAA==.Ratched:BAAALgADCgMJAwAAAA==.Raze:BAAALgAECgIJBgAAAA==.',
Re='Red:BAAALgADCgcJEgAAAA==.Redrighthand:BAAALgADCgEJAQAAAA==.Renicus:BAAALgADCgYJCAAAAA==.Renmare:BAABLgAECn8WAAIIAAUJOhcoUwD9AAAIAAUJOhcoUwD9AAAAAA==.Renmore:BAABLgAECn8VAAIJAAgJMBEEcwCFAQAJAAgJMBEEcwCFAQAAAA==.Rennzo:BAAALgADCggJDAAAAA==.Reshtargorr:BAAALgAECgEJAwAAAA==.Reze:BAAALgAECgEJAQAAAA==.',
Rg='Rgbpanda:BAAALgAECgQJBQAAAA==.',
Rh='Rhandoom:BAAALgADCgQJBAAAAA==.',
Ri='Ricky:BAAALgAECgEJAQAAAA==.Rikeji:BAAALgAECgYJCwAAAA==.Risotto:BAAALgAECgQJBwAAAA==.Riumi:BAAALgAECgMJCQAAAA==.Rivenxi:BAAALgAECgEJAQABLgAECgcJDAACAAAAAA==.',
Ro='Rocksolid:BAAALgAECgEJAgAAAA==.Ronaspreader:BAAALgAECgYJAwAAAA==.Roskolnikov:BAAALgAECgUJEAAAAA==.',
Ru='Rubymoonbeam:BAABLgAECn8mAAIFAAcJDw5seABKAQAFAAcJDw5seABKAQAAAA==.Ruele:BAACLgAFFH8HAAIZAAYJoA61HgBrAQAZAAYJoA61HgBrAQAuAAQKfxwAAhkACQnyHyYNAMQCABkACQnyHyYNAMQCAAAA.Ruenan:BAABLgAECn8xAAMFAAkJxyZwAQCAAwAFAAkJxyZwAQCAAwAhAAMJlhKzaACcAAAAAA==.',
Ry='Ryain:BAABLgAECn85AAMPAAkJtg+YKwB2AQAPAAkJ9Q2YKwB2AQAQAAcJnw+mKQAIAQAAAA==.Ryian:BAAALgAECgQJBAAAAA==.',
['Rä']='Räinns:BAABLgAECn8YAAIQAAcJNgo/GAD0AAAQAAcJNgo/GAD0AAAAAA==.',
Sa='Saintstephen:BAAALgADCggJGQAAAA==.Santajr:BAABLgAECn8eAAImAAYJsAM3OQCMAAAmAAYJsAM3OQCMAAAAAA==.Sapthat:BAABLgAECn8bAAMnAAcJwyH7AwDqAQAnAAYJAyT7AwDqAQAeAAMJXBrkEQDnAAAAAA==.Sarahlina:BAAALgADCgcJBwAAAA==.Sarthrity:BAABLgAECn8aAAIDAAYJNwkJzwDvAAADAAYJNwkJzwDvAAAAAA==.Savemeh:BAAALgAECgEJAQAAAA==.Savepebble:BAABLgAECn8fAAMHAAkJMxSxZgBvAQAHAAgJ7Q+xZgBvAQATAAUJXxcpHgC0AAAAAA==.',
Sc='Scalesofdoom:BAAALgAECgEJAgAAAA==.',
Se='Seather:BAABLgAECn8cAAIfAAgJ4BvDEwB4AgAfAAgJ4BvDEwB4AgAAAA==.Seirin:BAABLgAECn8rAAIkAAkJbxOeFgAYAgAkAAkJbxOeFgAYAgAAAA==.Seldiane:BAAALgADCgUJBQAAAA==.Selendaa:BAAALgAECgUJEQAAAA==.Senadarra:BAACLgAFFH8cAAIhAAYJZhuGDQCCAQAhAAYJZhuGDQCCAQAuAAQKfzcAAiEACQkeIeUCALECACEACQkeIeUCALECAAAA.Sephenroth:BAAALgAECgQJBwAAAA==.Sephron:BAABLgAECn8VAAIoAAkJ9xFyFQArAgAoAAkJ9xFyFQArAgAAAA==.Serendipity:BAAALgAECgcJBwABLgAECggJFAAYALISAA==.Serqet:BAABLgAECn8lAAQMAAgJfxWKOgDZAQAMAAgJMBWKOgDZAQApAAUJ+gOMJAB2AAAYAAIJuAozaQA2AAAAAA==.Sethen:BAAALgAECgEJAQAAAA==.',
Sh='Shadowhawke:BAAALgADCggJCAAAAA==.Shadowofdoom:BAAALgAECgEJAQAAAA==.Shammology:BAABLgAECn8WAAINAAcJPRIhTAB7AQANAAcJPRIhTAB7AQAAAA==.Shaollyn:BAAALgAECgYJCAAAAA==.Sheri:BAABLgAECn8XAAISAAkJPhzUAQBqAgASAAkJPhzUAQBqAgAAAA==.Shizam:BAAALgAECgUJBQAAAA==.Shizzi:BAAALgAECgQJBgAAAA==.Shotowkhaan:BAABLgAECn8XAAMRAAYJHRWlRgBzAQARAAYJHRWlRgBzAQAPAAEJaAL/pgAUAAAAAA==.Shotowkhann:BAAALgAECgIJAgAAAA==.Shoyoh:BAAALgAECgQJCQAAAA==.Shízu:BAAALgADCgkJDAAAAA==.',
Si='Sillygoose:BAACLgAFFH8mAAIDAAgJvROlEwBOAgADAAgJvROlEwBOAgAuAAQKfyQAAgMACQlJIJEVACcDAAMACQlJIJEVACcDAAAA.Sinadara:BAAALgAECgYJEAAAAA==.Sinïster:BAAALgADCgEJAQABLgAECgYJDwACAAAAAA==.Siong:BAAALgADCgcJCgABLgAFFAgJIgAJAAEhAA==.Siorknav:BAABLgAECn8fAAIJAAgJiQ4ppgArAQAJAAgJiQ4ppgArAQAAAA==.',
Sk='Skalar:BAABLgAECn8oAAIIAAgJ3A7PMgB/AQAIAAgJ3A7PMgB/AQAAAA==.Skipali:BAAALgAECgIJAwAAAA==.Skodah:BAAALgAECgEJAQABLgAECgYJDwACAAAAAA==.',
Sl='Släyr:BAAALgAECgMJBQAAAA==.',
So='Solunara:BAAALgADCgcJFgAAAA==.Somnambula:BAAALgADCgQJBAAAAA==.Sonadoria:BAABLgAECn8aAAIUAAgJ9w2PcwB6AQAUAAgJ9w2PcwB6AQAAAA==.Sorrenda:BAAALgADCgkJDwAAAA==.Soup:BAABLgAECn8nAAIgAAkJ/g2SEgCNAQAgAAkJ/g2SEgCNAQAAAA==.',
Sp='Sparow:BAAALgAECgEJAQAAAA==.Spinetarak:BAAALgADCgMJAwAAAA==.',
St='Stabbie:BAABLgAECn8XAAIfAAkJdRm4FAD4AQAfAAkJdRm4FAD4AQAAAA==.Stamina:BAAALgADCggJEAAAAA==.Stell:BAAALgAECgYJBwAAAA==.Stkawli:BAAALgAECgMJAwAAAA==.Stovik:BAABLgAECn8uAAMcAAkJdSEABAC2AgAcAAkJdSEABAC2AgANAAcJ0RG8RwCLAQAAAA==.',
Sv='Sventhebrave:BAAALgAECgUJEgAAAA==.',
Sw='Sweeneytod:BAAALgAECgIJBwAAAA==.Sweetpally:BAAALgADCgUJCAAAAA==.',
Sy='Sykill:BAAALgAECgUJCAAAAA==.Sylira:BAACLgAFFH8PAAMkAAYJ5xEVDQBzAQAkAAYJ5xEVDQBzAQAoAAEJMABsUgARAAAuAAQKfzgAAyQACQmUItkHAOwCACQACQmUItkHAOwCACUAAwkWDmBkAIUAAAAA.Sylk:BAAALgAECgUJBQABLgAECgYJEAACAAAAAA==.',
['Sö']='Söl:BAAALgAECgQJBAAAAA==.',
Ta='Taintedfel:BAAALgADCgkJCAAAAA==.Takamura:BAAALgAECgcJBwAAAA==.Takedown:BAACLgAFFH8SAAIXAAUJdRyMAwANAQAXAAUJdRyMAwANAQAuAAQKfywAAxcACQlhJGACACMDABcACQlhJGACACMDAAgABwkrGsUsAAECAAAA.Talena:BAAALgAECgcJBwAAAA==.Talleral:BAABLgAECn8WAAMoAAcJ2xYDGwD0AQAoAAcJ2xYDGwD0AQAkAAEJ2BBNfwAzAAAAAA==.Tallyn:BAAALgAECgEJAQAAAA==.Tamanan:BAAALgAECgYJCwAAAA==.Tankie:BAAALgADCgEJAQAAAA==.Taurgrim:BAAALgADCgUJCQAAAA==.Tavin:BAAALgAECgEJAwAAAA==.Tazrav:BAAALgAECgMJAwAAAA==.',
Te='Temamañ:BAAALgAECgYJCAAAAA==.Terasha:BAAALgAECgkJBgAAAA==.',
Th='Thalid:BAAALgADCgkJFQAAAA==.Tharonix:BAAALgAECgYJEwAAAA==.Thelitch:BAAALgADCgEJAgAAAA==.Theredpanda:BAAALgAECgUJBQAAAA==.Thewarden:BAAALgAECgIJAgAAAA==.',
Ti='Tic:BAAALgAECgYJBgAAAA==.Tigerwang:BAAALgAECgQJCAAAAA==.Tigrasia:BAAALgADCgYJCwAAAA==.Timaeus:BAACLgAFFH8GAAIDAAMJwg0FgADeAAADAAMJwg0FgADeAAAuAAQKfzsAAgMACQlzHbEbALMCAAMACQlzHbEbALMCAAAA.Tinder:BAAALgADCgUJBQABLgAECgYJCAACAAAAAA==.',
Tm='Tmbeesknees:BAAALgAECgEJAQAAAA==.',
To='Touch:BAABLgAECn8UAAMlAAYJ2wwBRAD8AAAlAAYJ2wwBRAD8AAAoAAEJ/QmyfAAtAAAAAA==.Touchofkarma:BAAALgADCgcJFAAAAA==.',
Tr='Trifflinhoes:BAAALgAECgUJEAAAAA==.Tristtan:BAAALgAECgEJAQAAAA==.Trôjan:BAAALgADCgMJAwAAAA==.',
Tu='Turningblue:BAAALgADCgUJBAAAAA==.Tusktilldawn:BAABLgAECn8VAAMVAAgJ5RAGGwCCAQAVAAgJzRAGGwCCAQAaAAIJ2wQENQBDAAAAAA==.',
Tw='Twohoof:BAAALgADCgkJFQAAAA==.',
Ty='Tydrinor:BAAALgAECgcJAQAAAA==.',
['Tä']='Tänithðurden:BAAALgADCggJDgAAAA==.',
Ug='Ugin:BAAALgAECgUJBgAAAA==.',
Un='Unobasho:BAAALgAECgMJAwABLgAFFAQJCwABAH0PAA==.Unoboxo:BAAALgADCgEJAQABLgAFFAQJCwABAH0PAA==.Unovoke:BAACLgAFFH8LAAIBAAQJfQ8fMwD0AAABAAQJfQ8fMwD0AAAuAAQKfzUAAgEACQkrHRgSAFACAAEACQkrHRgSAFACAAAA.',
Va='Valeena:BAAALgADCgEJAQABLgAECgQJBAACAAAAAA==.Valorash:BAABLgAECn87AAMJAAkJCCL6CwADAwAJAAkJCCL6CwADAwAKAAYJyhu4DwDJAQAAAA==.Valorious:BAAALgAECgUJCAAAAA==.Vandaira:BAAALgAECgkJAQAAAA==.Vasillisa:BAAALgAECgMJBQAAAA==.',
Ve='Vearick:BAAALgADCgYJCgAAAA==.Veleyna:BAAALgADCgcJCwAAAA==.Velgryn:BAAALgAECgUJBAAAAA==.Velintha:BAAALgAECgcJCAAAAA==.Venatrix:BAAALgAECgYJEQAAAA==.Vendrith:BAAALgADCgcJBwAAAA==.Veraxi:BAAALgADCgYJCwABLgAECgUJCgACAAAAAA==.Vessen:BAAALgADCgUJBwAAAA==.',
Vi='Vidascare:BAAALgAECgkJAgAAAA==.Vidu:BAAALgADCgUJBQAAAA==.Vision:BAAALgADCgYJBgAAAA==.',
Vl='Vluthier:BAAALgADCgYJBgAAAA==.',
Vo='Voidshatter:BAABLgAECn8bAAMYAAcJYgh3NQDjAAAYAAcJYgh3NQDjAAAMAAYJcQIi6gBhAAAAAA==.Vonderick:BAAALgAECgQJAwAAAA==.Voodoodog:BAAALgAECgMJBQABLgAECgYJDwACAAAAAA==.',
Vu='Vulgrimm:BAAALgAECgUJBQAAAA==.',
Vy='Vynlorellas:BAAALgAECgEJAgAAAA==.Vyéra:BAAALgADCgMJBgAAAA==.',
['Vè']='Vèsper:BAAALgAECgMJBQABLgAECgMJCQACAAAAAA==.',
Wa='Wakawli:BAAALgADCgYJBgAAAA==.Walex:BAAALgAECgkJBwAAAA==.Wally:BAAALgADCgMJAwAAAA==.Wardmneagle:BAAALgADCgUJCgAAAA==.Wargasm:BAAALgAECgQJBwABLgAECgcJEQACAAAAAA==.Watongo:BAAALgAECgUJBwAAAA==.Watsaheal:BAAALgAECgUJBQAAAA==.',
Wi='Wildborn:BAAALgADCgMJAwAAAA==.Willidan:BAAALgADCgEJAQAAAA==.Winwood:BAAALgADCgUJBwAAAA==.Withdrawals:BAAALgADCgYJBgABLgAECgMJCQACAAAAAA==.',
Wo='Woeify:BAABLgAECn8VAAIcAAcJ5xSuDgDRAQAcAAcJ5xSuDgDRAQAAAA==.',
Wr='Wreckless:BAAALgAECggJCAABLgAFFAUJDgAeAFYeAA==.',
Wy='Wynce:BAAALgAECgUJCAAAAA==.',
Xa='Xalana:BAAALgADCgQJBAAAAA==.Xandaer:BAAALgAECgIJAwAAAA==.Xarn:BAABLgAECn8hAAIHAAkJtwdvagCOAQAHAAkJtwdvagCOAQAAAA==.',
Xc='Xcïte:BAABLgAECn8YAAQlAAgJwBraJgCVAQAlAAYJ9hzaJgCVAQAkAAMJ3RtaWADUAAAoAAUJtxAZTADRAAAAAA==.',
Xe='Xenroz:BAAALgADCgcJBwAAAA==.',
Ya='Yagudo:BAAALgADCgEJAQAAAA==.Yandòur:BAAALgADCgIJAgABLgAECgkJGQATAIkPAA==.',
Ye='Yemon:BAAALgAECgUJBQAAAA==.',
Yo='Yodä:BAAALgADCgcJBwAAAA==.Yourlock:BAAALgADCgUJBQAAAA==.',
Yr='Yrelya:BAAALgAECgYJCQAAAA==.',
Yu='Yuji:BAACLgAFFH8IAAIJAAMJlQdwfQCyAAAJAAMJlQdwfQCyAAAuAAQKf0cAAgkACQn1FRczADECAAkACQn1FRczADECAAAA.',
Za='Zalectra:BAACLgAFFH8UAAIEAAQJHiGFCwBmAQAEAAQJHiGFCwBmAQAuAAQKfz4AAwQACQm2JUIAAMUDAAQACQm2JUIAAMUDACEAAgmhFnApAG0AAAAA.',
Ze='Zelila:BAAALgAECgUJBAAAAA==.Zephyruss:BAAALgADCgIJAgAAAA==.',
['Zü']='Zügzüg:BAAALgADCgEJAQAAAA==.',
['Âu']='Âurâ:BAAALgAECgUJBwAAAA==.',
['Ål']='Ålloria:BAABLgAECn8VAAIYAAcJFxi7GQCuAQAYAAcJFxi7GQCuAQAAAA==.',
['ßl']='ßlackßetty:BAAALgAECgMJBwAAAA==.',
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
