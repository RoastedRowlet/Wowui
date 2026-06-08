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

local lookup = {'Evoker-Augmentation','Unknown-Unknown','Mage-Frost','Hunter-Survival','Hunter-BeastMastery','Monk-Mistweaver','Monk-Brewmaster','Warlock-Demonology','Warrior-Fury','Paladin-Retribution','Paladin-Protection','Paladin-Holy','DemonHunter-Devourer','Shaman-Restoration','Monk-Windwalker','Druid-Guardian','Druid-Balance','Druid-Restoration','Mage-Arcane','Warlock-Destruction','DeathKnight-Unholy','Evoker-Devastation','Warrior-Arms','DemonHunter-Havoc','DeathKnight-Frost','DeathKnight-Blood','Shaman-Elemental','Shaman-Enhancement','Evoker-Preservation','Rogue-Assassination','Rogue-Subtlety','Druid-Feral','Hunter-Marksmanship','Warlock-Affliction','Mage-Fire','Warrior-Protection','Rogue-Outlaw','Priest-Holy','DemonHunter-Vengeance','Priest-Discipline','Priest-Shadow',}
local provider = {region='US',realm='Gnomeregan',name='US',type='weekly',zone=46,date='2026-06-06',data={Ac='Acehuntura:BAAALgAECgEJAgAAAA==.',
Ad='Adaric:BAAALgAECgYJCAAAAA==.',
Af='Afflicea:BAAALgAECgMJAwAAAA==.',
Ah='Ahava:BAAALgADCgYJCQAAAA==.',
Ai='Aidoneiscus:BAAALgAECgUJCgABLgAFFAUJEQABAKMXAA==.Ainokea:BAAALgAECgEJAQABLgAECgQJBwACAAAAAA==.Aiyaiyai:BAAALgAECgYJDQAAAA==.',
Aj='Ajani:BAAALgAECgYJDAAAAA==.',
Ak='Akawli:BAAALgAECgIJAwAAAA==.',
Al='Alall:BAAALgAECgMJBgAAAA==.Alauth:BAAALgAECgIJAwAAAA==.Aliceandreia:BAAALgADCgUJCgAAAA==.Alliethra:BAAALgAECgQJBgAAAA==.',
Am='Aminall:BAAALgAECgYJDAAAAA==.',
An='Anarreth:BAAALgADCgUJCgAAAA==.Andahla:BAAALgADCgkJCwAAAA==.Andore:BAABLgAECn8gAAIDAAcJvhlpWADOAQADAAcJvhlpWADOAQAAAA==.Anewbyss:BAAALgAECggJDAAAAA==.Angrymurloc:BAABLgAECn8XAAMEAAcJHQszKwBEAQAEAAcJHQszKwBEAQAFAAUJMQLp5gBrAAAAAA==.Anthonie:BAAALgADCgYJBgAAAA==.Antoer:BAAALgAECgIJAgAAAA==.Anwyll:BAAALgADCgcJDAAAAA==.',
Ao='Aoir:BAAALgAECgQJBgAAAA==.',
Ap='Aposthmighty:BAAALgAECgYJDQAAAA==.',
Ar='Arcancis:BAAALgADCgQJBAAAAA==.Ariyia:BAAALgADCgYJBAAAAA==.Arlona:BAAALgAECgIJAwABLgAECgYJEAACAAAAAA==.Arms:BAAALgAECgcJEAAAAA==.Artemyss:BAAALgADCgEJAQAAAA==.',
As='Ashanara:BAAALgAECgQJBAABLgAECgkJMwAGAOoZAA==.Asher:BAAALgADCgEJAQAAAA==.Ashnact:BAAALgAECgIJCQAAAA==.Ashraki:BAAALgAECgEJAQAAAA==.Ashreign:BAAALgAECgkJCQAAAA==.Asl:BAAALgADCgcJBwAAAA==.Asonnari:BAAALgADCgEJAQAAAA==.Astraeal:BAABLgAECn8UAAIHAAYJwRFpOgALAQAHAAYJwRFpOgALAQAAAA==.',
At='Atreana:BAABLgAECn82AAIIAAkJ4hX+LQAaAgAIAAkJ4hX+LQAaAgAAAA==.Attykus:BAABLgAECn8xAAIJAAgJ/BM1MQDoAQAJAAgJ/BM1MQDoAQAAAA==.',
Av='Avalerion:BAABLgAECn8UAAMKAAcJaBhHXQCtAQAKAAcJoxdHXQCtAQALAAIJbB0wMACZAAAAAA==.Avij:BAAALgAECgQJCgABLgAECgYJCQACAAAAAA==.',
Ay='Ayoreo:BAAALgADCgMJAwAAAA==.',
Az='Azmodon:BAAALgADCgEJAwAAAA==.',
['Añ']='Añathema:BAAALgAECgMJBAAAAA==.',
Ba='Banfultoxxin:BAAALgADCggJDwAAAA==.Barrellroll:BAAALgADCgkJCQAAAA==.Bastam:BAAALgAECgIJAgABLgAECgIJBAACAAAAAA==.Bat:BAAALgAECgQJBwAAAA==.',
Be='Bearlyhealz:BAAALgADCgkJBQAAAA==.Beercats:BAAALgADCgMJBgAAAA==.Bentotc:BAAALgAECgIJAwAAAA==.',
Bi='Bighoot:BAAALgAECgQJCgAAAA==.Bigmancow:BAABLgAECn8nAAIMAAkJTw+YKAC9AQAMAAkJTw+YKAC9AQAAAA==.Bigpoppapump:BAAALgAECgQJBgAAAA==.Biomancer:BAAALgADCgYJBgAAAA==.Bismofungion:BAAALgADCgcJEAAAAA==.',
Bl='Bludgens:BAAALgADCgIJAgAAAA==.Bluecoral:BAAALgADCgEJAQAAAA==.Blunter:BAABLgAECn8TAAINAAcJ5gYdlgDxAAANAAcJ5gYdlgDxAAAAAA==.Blushtime:BAAALgADCgIJAgAAAA==.Bluwhale:BAACLgAFFH8eAAIOAAgJ+By0AQC/AgAOAAgJ+By0AQC/AgAuAAQKfyYAAg4ACQk+JGUKAAQDAA4ACQk+JGUKAAQDAAAA.',
Bo='Bocchi:BAAALgAECgEJAQAAAA==.Bodanky:BAAALgAECgMJBQAAAA==.Bormor:BAAALgAECggJEAAAAA==.Bowdacious:BAAALgAECgUJCwAAAA==.Boötes:BAAALgADCgcJBwAAAA==.',
Br='Brago:BAAALgAECgEJAQAAAA==.Braini:BAAALgADCgEJAQAAAA==.Brainpath:BAAALgAECgYJEgAAAA==.Brasidias:BAAALgADCgQJBAAAAA==.Brickingkeys:BAAALgAECgIJBAAAAA==.Brumak:BAAALgAECgkJCgAAAA==.Bruno:BAABLgAECn8qAAMLAAkJrRhoDADyAQALAAkJrRhoDADyAQAKAAQJKQcQ+gCfAAAAAA==.',
Bu='Budthespud:BAAALgAECgEJAQAAAA==.Burland:BAAALgAECgQJBwAAAA==.',
['Bá']='Báthory:BAABLgAECn8UAAINAAkJohxAFQCPAgANAAkJohxAFQCPAgAAAA==.',
Ca='Caedus:BAAALgADCgYJBgAAAA==.Cal:BAAALgAECgYJDAABLgAFFAIJCAAHADMXAA==.Caladin:BAAALgAECgQJBAABLgAFFAIJCAAHADMXAA==.Calamity:BAAALgADCgQJBAAAAA==.Callistos:BAACLgAFFH8IAAIHAAIJMxdwPgCdAAAHAAIJMxdwPgCdAAAuAAQKfzwAAwcACQlYHtUHAK8CAAcACQlYHtUHAK8CAA8AAgkgER6RADQAAAAA.Camelshammy:BAAALgAECgYJDgAAAA==.Caradyn:BAAALgADCgUJBQABLgAECgYJFAADACYTAA==.Caris:BAAALgAECgMJAwAAAA==.Castianna:BAAALgAECgUJEQAAAA==.',
Ce='Cebastian:BAAALgAECgQJBwAAAA==.Cedarpoint:BAAALgADCggJEgAAAA==.Celoria:BAAALgADCgUJCQAAAA==.Century:BAABLgAECn8rAAQQAAgJFx3qEgCxAQARAAgJ/hdaGAD9AQAQAAgJxxXqEgCxAQASAAIJFRFjzQAwAAAAAA==.Cerriwyn:BAAALgAECgEJAQAAAA==.Cery:BAAALgAECgEJAQAAAA==.',
Ch='Cheochan:BAAALgADCgYJDwAAAA==.Chizami:BAAALgAECggJDAABLgAFFAcJFAAMAGUOAA==.Chocostarmie:BAAALgADCgQJBAAAAA==.Chug:BAABLgAECn8eAAIPAAkJlyDpCACsAgAPAAkJlyDpCACsAgAAAA==.',
Ci='Circa:BAABLgAECn8nAAMDAAgJ4BXUVgDSAQADAAgJhhXUVgDSAQATAAQJWg7dEAC0AAAAAA==.Cithrel:BAABLgAECn8ZAAIUAAkJiQ8jFAABAQAUAAkJiQ8jFAABAQAAAA==.',
Cl='Claylemian:BAAALgAECgMJAwAAAA==.',
Co='Conqubine:BAAALgADCgkJDgAAAA==.Corban:BAAALgAECgEJAgAAAA==.',
Cr='Creolix:BAAALgADCgYJBgABLgAECgYJCAACAAAAAA==.Crocklock:BAABLgAECn8ZAAIIAAcJ6hXqYgB1AQAIAAcJ6hXqYgB1AQAAAA==.',
Cu='Cuddlyblood:BAAALgAECgEJAQAAAA==.Cujo:BAAALgADCgMJAwAAAA==.',
['Cà']='Càssiàn:BAAALgADCgIJAgAAAA==.',
Da='Dallia:BAABLgAECn8vAAMKAAcJ4Qc42QDZAAAKAAcJ0AY42QDZAAALAAMJ7QUhQABUAAAAAA==.Damnatio:BAABLgAECn8gAAIKAAkJmSRPDwDiAgAKAAkJmSRPDwDiAgAAAA==.Damonster:BAAALgAECgIJAwAAAA==.Danossa:BAAALgAECgEJAgAAAA==.Darkclement:BAABLgAECn8VAAIFAAcJsx6vNQD7AQAFAAcJsx6vNQD7AQABLgAFFAMJCQAKAE4TAA==.Darkin:BAAALgAECgcJCAAAAA==.Darkmist:BAAALgADCgUJBQAAAA==.Darkwiz:BAAALgAECgkJDwAAAA==.Davrimbasher:BAAALgADCgEJAQAAAA==.',
De='Deadlydk:BAAALgADCgMJAwAAAA==.Deathbybob:BAAALgAECgYJEgAAAA==.Deathgriped:BAAALgAECgUJDgAAAA==.Deeper:BAABLgAECn8bAAMRAAgJ8ApoNQAzAQARAAgJ8ApoNQAzAQASAAMJagEm1gAoAAAAAA==.Deezmoonz:BAAALgADCgYJCQAAAA==.Dementos:BAAALgADCgkJCgAAAA==.Demonofwar:BAAALgADCgYJDAABLgAECgYJCAACAAAAAA==.Devils:BAAALgAECgUJCQAAAA==.',
Di='Dirin:BAAALgAECgUJDQABLgAECgUJCgACAAAAAA==.Disneymagic:BAAALgADCgUJBwAAAA==.',
Dm='Dmaan:BAAALgADCgMJAwAAAA==.',
Dr='Dragonpebble:BAAALgADCgYJBgABLgAECgkJHwAIADMUAA==.Drahalah:BAABLgAECn8eAAIVAAgJXR/yNQAfAgAVAAgJXR/yNQAfAgAAAA==.Drakeji:BAABLgAECn80AAMBAAkJWQtILwByAQABAAkJWQtILwByAQAWAAQJKAGhPwAxAAAAAA==.Dreamliner:BAAALgAECgYJBgAAAA==.Drezind:BAAALgAECgQJBAAAAA==.Drhealalot:BAAALgAECgEJAQAAAA==.Drugar:BAAALgAECgkJCQABLgAFFAUJEgAXAHUcAA==.',
Du='Dumplingg:BAAALgAECggJDAAAAA==.',
Ea='Earthvoodoo:BAAALgAECgYJDwAAAA==.',
Eb='Eberkenezer:BAAALgAECgEJAQAAAA==.Ebonlight:BAAALgADCgkJFgAAAA==.',
Ec='Ecnyw:BAAALgADCgMJAwABLgAECgUJCAACAAAAAA==.',
Ed='Edence:BAAALgAECgMJAwAAAA==.',
Eh='Ehunter:BAAALgAECgUJDQAAAA==.',
Ei='Eillea:BAAALgADCgQJBAAAAA==.',
El='Elegant:BAAALgAECgkJBwAAAA==.Elspeth:BAAALgAECgIJAgAAAA==.Elsyria:BAAALgADCgIJAgABLgAFFAcJHQAKAMEhAA==.Eluneslight:BAAALgAECgEJAwAAAA==.',
Em='Emmeri:BAAALgAECgQJBwABLgAECggJMQAJAPwTAA==.',
En='Ender:BAAALgAECgIJAgAAAA==.',
Ep='Epi:BAABLgAECn8UAAIYAAgJshLDMgDjAAAYAAgJshLDMgDjAAAAAA==.',
Er='Erianis:BAAALgADCgMJAwAAAA==.Erniethemonk:BAAALgAECgYJEAAAAA==.',
Ev='Evianda:BAAALgADCgkJEAAAAA==.',
Ez='Ezale:BAAALgAECgkJEwAAAA==.Ezpz:BAAALgAECgYJEgAAAA==.',
Fa='Falsetto:BAAALgAECgEJAgAAAA==.Faramír:BAAALgAECgQJBQAAAA==.Fatébringer:BAAALgAECggJDgABLgAECgcJDgACAAAAAA==.Fauhna:BAAALgAECgEJAQABLgAFFAIJBgAKACMiAA==.',
Fe='Fennek:BAABLgAECn8UAAIFAAgJng8XVQCXAQAFAAgJng8XVQCXAQAAAA==.',
Fi='Fiønaviolet:BAAALgADCgcJBwAAAA==.',
Fo='Fourth:BAAALgAECgEJAgABLgAECgcJEAACAAAAAA==.',
Fr='Frayla:BAAALgADCgEJAQAAAA==.',
Fu='Furrywhenwet:BAAALgAFFAEJAQAAAA==.Fuzzyxbutt:BAAALgAECgYJDgAAAA==.',
Fy='Fyaaga:BAAALgAECgQJBAABLgAFFAYJBwAGAKAOAA==.',
Ga='Garaylo:BAACLgAFFH8dAAIKAAcJwSFjBgBHAgAKAAcJwSFjBgBHAgAuAAQKfykAAgoACQn1JMACAKwDAAoACQn1JMACAKwDAAAA.Garroar:BAAALgADCgcJCAAAAA==.',
Ge='Geed:BAAALgADCgEJAQAAAA==.Gewnzilla:BAAALgAECgIJAgAAAA==.',
Gg='Ggxd:BAAALgADCgkJEAAAAA==.',
Gh='Ghosst:BAABLgAECn8jAAIEAAkJtiLuAgAIAwAEAAkJtiLuAgAIAwAAAA==.',
Gi='Gilberticus:BAAALgADCgMJAwABLgAECgkJSgAPAMUiAA==.Gimlithekind:BAAALgAECgEJAQAAAA==.',
Gl='Glen:BAAALgADCgMJAwAAAA==.',
Gn='Gnobliterate:BAABLgAECn8oAAQVAAkJMRJnZgCSAQAVAAkJ9g9nZgCSAQAZAAYJNQ3yGgDmAAAaAAIJLRPzRABtAAAAAA==.Gnobolts:BAAALgAECgEJAQAAAA==.Gnobull:BAAALgAECgcJCwAAAA==.Gnochi:BAAALgAECgcJBwAAAA==.Gnudgnimish:BAAALgAFFAIJBAABLgAFFAUJBwAHALkZAA==.',
Go='Goldenblight:BAAALgAECgYJCwAAAA==.Goldenchi:BAAALgAECgEJAQAAAA==.Goldenrage:BAAALgAECgQJBAAAAA==.Gomper:BAAALgAECgMJBAAAAA==.Gonforgood:BAAALgADCgYJBgAAAA==.Goonmaxing:BAAALgADCgMJAwAAAA==.',
Gr='Grimclaw:BAAALgADCgYJDgAAAA==.Grimmrot:BAAALgAECgYJDQAAAA==.Grimmz:BAAALgADCggJCQAAAA==.Grizk:BAAALgADCgEJAQAAAA==.',
Gu='Guttris:BAAALgAECgYJEQAAAA==.',
Gw='Gwaineedk:BAAALgAECgMJAwAAAA==.',
Ha='Haikusen:BAAALgADCgYJBAABLgAECgYJCAACAAAAAA==.Halstron:BAACLgAFFH8GAAIKAAIJIyK7bgDBAAAKAAIJIyK7bgDBAAAuAAQKfy0AAwoACQm/IB8OAOsCAAoACQmPIB8OAOsCAAsABQl7FTMgAAYBAAAA.Harribel:BAABLgAECn8bAAQaAAgJuwUmQgB6AAAVAAYJ1wMuAAGdAAAaAAQJtwYmQgB6AAAZAAIJ8gHdFgA1AAAAAA==.',
He='Heliòs:BAAALgAECgQJBAAAAA==.Hellwár:BAAALgADCgYJBgAAAA==.',
Ho='Hogfu:BAAALgAECgQJBAAAAA==.Hogshock:BAABLgAECn8bAAQbAAkJTRXRJgDcAQAbAAkJTRXRJgDcAQAcAAMJXgfMJACLAAAOAAEJhA261QAoAAAAAA==.Holocharizrd:BAAALgADCgcJCQAAAA==.Holyrequiem:BAAALgADCgEJAQAAAA==.Holyzel:BAAALgAECgkJEgAAAA==.Hotnsassie:BAAALgADCgMJCQAAAA==.Hound:BAAALgADCgUJCAAAAA==.Hoyt:BAAALgADCgcJBwAAAA==.',
Hs='Hsimingjung:BAACLgAFFH8HAAMHAAUJuRlpFgBcAQAHAAUJuRlpFgBcAQAPAAEJNQsZPgA6AAAuAAQKfykAAwcACQnLIbAGAMcCAAcACQnLIbAGAMcCAA8ABAlFIXskAIIBAAAA.',
Hu='Humanic:BAAALgAECgIJAwAAAA==.Huntari:BAAALgAECgEJAwAAAA==.',
Hy='Hylie:BAACLgAFFH8MAAIIAAMJXgd0fAC8AAAIAAMJXgd0fAC8AAAuAAQKfx0AAggACQlnDVlaALkBAAgACQlnDVlaALkBAAAA.',
['Hè']='Hèlla:BAAALgADCgkJFQAAAA==.',
Ig='Ignisky:BAAALgAECgcJDgABLgAFFAUJEgAXAHUcAA==.',
Il='Illidarie:BAAALgADCgUJCAAAAA==.',
Im='Imsofresh:BAAALgADCgEJAQAAAA==.',
In='Inte:BAAALgADCgYJBgAAAA==.Inzi:BAAALgAECgEJAwAAAA==.',
Iz='Izgin:BAABLgAECn8UAAIDAAYJJhMUsgAaAQADAAYJJhMUsgAaAQAAAA==.',
Ja='Jadeyn:BAAALgADCgMJAwAAAA==.Jaime:BAAALgADCgYJCQABLgAECgYJCAACAAAAAA==.Jalet:BAAALgADCgcJDQAAAA==.Janie:BAAALgADCgUJCAABLgADCgYJBgACAAAAAA==.Jantar:BAABLgAECn8bAAISAAkJ4xi+FgCIAgASAAkJ4xi+FgCIAgAAAA==.Jasonbjorne:BAAALgAECgEJAQAAAA==.',
Je='Jebbyclipse:BAAALgAECgQJCAAAAA==.Jenzö:BAABLgAECn8bAAIbAAYJBhE4RQAOAQAbAAYJBhE4RQAOAQAAAA==.Jeramya:BAAALgADCgQJBAAAAA==.',
Jo='Joeviben:BAABLgAECn8WAAIKAAcJDAr8rgAVAQAKAAcJDAr8rgAVAQAAAA==.Jormungandr:BAAALgADCgYJCgABLgADCgcJBwACAAAAAA==.',
Ju='Jugsy:BAABLgAECn8ZAAIDAAkJtBfYKwBkAgADAAkJtBfYKwBkAgAAAA==.Juliza:BAAALgADCgQJBAAAAA==.Jungfer:BAAALgAECgMJBAAAAA==.',
Ka='Kaerodora:BAAALgADCgYJBgAAAA==.Kalasan:BAAALgAECgIJAgAAAA==.Kaldread:BAAALgAECgMJAwAAAA==.Kaligo:BAABLgAECn9CAAMbAAkJQBp1EwBEAgAbAAkJQBp1EwBEAgAcAAQJrgSuIgCrAAAAAA==.Kalistus:BAABLgAECn8bAAINAAkJtwxGVQB7AQANAAkJtwxGVQB7AQAAAA==.Kallistos:BAAALgAECgEJAQABLgAFFAIJCAAHADMXAA==.Kalygos:BAAALgAECgQJBAABLgAFFAIJCAAHADMXAA==.Karall:BAAALgAECgEJAQAAAA==.Karetha:BAAALgAECgUJCQAAAA==.Katar:BAAALgADCgMJAwAAAA==.Katreset:BAAALgAECgUJCAAAAA==.',
Kd='Kdavid:BAAALgADCgUJCgAAAA==.',
Ke='Kebsy:BAABLgAECn87AAIPAAkJPSTlAgAxAwAPAAkJPSTlAgAxAwAAAA==.Kegfupanda:BAAALgAFFAEJAQAAAA==.Keleion:BAABLgAECn8nAAINAAcJzhCFfQAYAQANAAcJzhCFfQAYAQABLgAECgkJEwACAAAAAA==.Kelements:BAAALgAFFAEJAQAAAA==.Kelyessada:BAAALgADCgYJBgAAAA==.Kevonjuravis:BAABLgAECn8sAAMHAAcJzw3XOQANAQAHAAcJMgvXOQANAQAPAAUJWxCtWAChAAAAAA==.',
Kh='Khalya:BAAALgAECgUJBQAAAA==.Khalyl:BAABLgAECn8WAAIYAAUJJRSWMQDqAAAYAAUJJRSWMQDqAAAAAA==.Kheart:BAAALgAECgEJAQAAAA==.Kholy:BAAALgADCgYJBgAAAA==.',
Ki='Kidrash:BAAALgADCgcJCAAAAA==.Killah:BAAALgAECgMJAwAAAA==.Kimegh:BAAALgADCgIJAgAAAA==.Kitsunae:BAAALgADCgcJGwAAAA==.',
Kl='Kleredan:BAAALgAECgkJBgAAAA==.',
Ko='Koder:BAACLgAFFH8RAAIBAAUJoxetJwAXAQABAAUJoxetJwAXAQAuAAQKfzQABAEACAmtIbEGABIDAAEACAmtIbEGABIDABYABwlXGa0GANMBAB0AAgkOArJEAEoAAAAA.Kozmoker:BAAALgAECgYJBgAAAA==.',
Kr='Krondys:BAAALgAECgYJBgAAAA==.Krytus:BAAALgAECgEJAgAAAA==.',
Ku='Kupó:BAAALgADCgUJBQABLgAECgYJDAACAAAAAA==.',
Ky='Kyakdeath:BAABLgAECn81AAMVAAgJUhoCVQC+AQAVAAgJUhoCVQC+AQAZAAEJKwkVNwAuAAAAAA==.',
Kz='Kzo:BAAALgAECgYJDQAAAA==.',
La='Lailyre:BAAALgADCgQJBAAAAA==.',
Le='Lecker:BAAALgAECgEJAQAAAA==.Legado:BAAALgAECgUJBwAAAA==.',
Li='Lilbigcow:BAAALgAECgEJAgAAAA==.Lilithxander:BAAALgAECgUJCQAAAA==.Lilshooter:BAAALgAECgIJAwABLgAFFAMJAwACAAAAAA==.Lizzybordan:BAAALgAECgcJDgAAAA==.',
Ll='Llaaroyy:BAAALgADCgEJAQAAAA==.Llarroii:BAAALgAECgEJAgAAAA==.',
Lo='Lovar:BAAALgADCgYJBgAAAA==.',
Lu='Lucinick:BAABLgAECn8fAAMeAAYJBxXGDABTAQAeAAYJBxXGDABTAQAfAAQJlAryOQDVAAAAAA==.Lucy:BAAALgADCgIJAgAAAA==.Luxdiei:BAAALgAECgYJBgAAAA==.Luzziem:BAAALgAECgQJCAAAAA==.',
Ly='Lynx:BAAALgAECgEJBAAAAA==.',
Ma='Mariskama:BAABLgAECn8fAAIFAAgJuQUfgAAxAQAFAAgJuQUfgAAxAQAAAA==.Markusthered:BAAALgAECgMJAwAAAA==.Mazza:BAAALgAECgkJEQAAAA==.',
Mc='Mcbong:BAAALgAECgQJBwAAAA==.',
Me='Mello:BAAALgADCgYJBgAAAA==.Meowimabear:BAAALgADCgkJEAABLgAECgkJIwAEALYiAA==.Metal:BAAALgAECgQJDgAAAA==.Method:BAAALgADCgEJAQAAAA==.Meuccí:BAAALgAECgcJCwAAAA==.',
Mh='Mhelora:BAAALgAECgUJEAAAAA==.',
Mi='Mikkais:BAAALgAECgYJDgAAAA==.Mimacho:BAAALgAECgQJCAAAAA==.Minimini:BAACLgAFFH8QAAIGAAQJExu8IAA6AQAGAAQJExu8IAA6AQAuAAQKfy4AAgYACQkJHM8QAIoCAAYACQkJHM8QAIoCAAAA.Minni:BAAALgAFFAEJAwAAAA==.',
Mo='Moolin:BAABLgAECn8oAAIgAAkJUwkTGQA0AQAgAAkJUwkTGQA0AQAAAA==.Moranthe:BAAALgAECgcJDAABLgAFFAYJBwAGAKAOAA==.Mordsyth:BAAALgAECgYJCgAAAA==.',
Mu='Muggni:BAAALgAECgkJEQAAAA==.Muggypew:BAABLgAECn8UAAIhAAkJRgEWLABeAAAhAAkJRgEWLABeAAAAAA==.Munder:BAABLgAECn8mAAMiAAkJgB1dAwB2AgAiAAkJcBxdAwB2AgAIAAgJ/xk2TwCoAQAAAA==.Mustymuppet:BAACLgAFFH8ZAAIIAAUJmBcmPgBBAQAIAAUJmBcmPgBBAQAuAAQKfygAAwgACAnzGsE0AAACAAgACAnzGsE0AAACABQAAQlnD7VuADgAAAAA.',
My='Myrotheron:BAAALgADCgMJAwAAAA==.Mysticmeat:BAAALgAECgEJAQAAAA==.Mythicalbug:BAAALgADCgEJAQAAAA==.Mythuneran:BAABLgAECn8cAAIjAAkJdhdpAgAgAgAjAAkJdhdpAgAgAgAAAA==.',
['Mø']='Mørzanna:BAAALgAECgYJBgAAAA==.',
Na='Nanookigaluk:BAAALgADCgYJBgAAAA==.Narrator:BAAALgAECgEJAgAAAA==.Navikz:BAAALgADCgUJBQAAAA==.',
Ne='Nekrose:BAABLgAECn8aAAIVAAgJwiKoHQCOAgAVAAgJwiKoHQCOAgAAAA==.Nemini:BAAALgAECgYJDwAAAA==.Nena:BAABLgAECn8jAAIRAAYJbBPHOAAiAQARAAYJbBPHOAAiAQAAAA==.Nenacurses:BAAALgAECgMJBwABLgAECgYJIwARAGwTAA==.Nephilia:BAAALgADCgYJBgAAAA==.Newfy:BAAALgAFFAEJAwAAAA==.',
Ni='Ninjamage:BAAALgAECgUJBQAAAA==.Nistis:BAAALgAECgYJEQAAAA==.Niteshroud:BAAALgADCgMJAwAAAA==.Nithendroz:BAABLgAECn8YAAMWAAcJZgq3FAC4AAAWAAQJZgu3FAC4AAABAAMJaAhMegBcAAAAAA==.Nity:BAAALgAECgQJBAAAAA==.',
No='Noctaurus:BAABLgAECn8fAAIVAAgJ4QlhgABaAQAVAAgJ4QlhgABaAQAAAA==.Noczorro:BAAALgADCgYJBgAAAA==.Nomadhew:BAAALgAECgcJBwAAAA==.Noraice:BAAALgAECgEJAgAAAA==.Notagain:BAACLgAFFH8sAAIKAAgJxhu/BABuAgAKAAgJxhu/BABuAgAuAAQKfy4AAgoACQkBI5YHAFoDAAoACQkBI5YHAFoDAAAA.Notapally:BAAALgAECgQJBAAAAA==.Noxcorvus:BAAALgAECgcJDQAAAA==.',
Nu='Nuvo:BAAALgADCgYJBgAAAA==.',
Ny='Nylloc:BAAALgAECgkJCQAAAA==.Nymphàdoria:BAAALgAECgEJAQAAAA==.Nyuxx:BAAALgAECgYJEAAAAA==.',
['Nê']='Nêwfie:BAAALgAECgEJAwABLgAFFAEJAwACAAAAAA==.',
Oc='Oceanic:BAAALgADCgYJCwAAAA==.Oceans:BAAALgAECgEJAQAAAA==.',
Od='Odphijor:BAAALgAECgkJAQAAAA==.',
Ol='Olenza:BAAALgAECgQJBAAAAA==.Olgreeneyes:BAAALgAECgIJBAAAAA==.',
Or='Orangewhale:BAABLgAECn8UAAISAAYJChgpTABzAQASAAYJChgpTABzAQAAAA==.',
Ou='Out:BAAALgAECgYJCwAAAA==.',
Ox='Oxidation:BAAALgADCgcJGgAAAA==.',
Pa='Painspongie:BAAALgADCgQJBQAAAA==.Patsajak:BAAALgADCgEJAQAAAA==.Pavo:BAAALgADCgYJBgAAAA==.',
Pe='Pebbleshifts:BAAALgAECgMJAwAAAA==.Peejean:BAAALgAECgYJBgAAAA==.Peyblade:BAAALgAECgYJBgABLgAECgkJHgATABghAA==.Peybreak:BAAALgAECgIJAgABLgAECgkJHgATABghAA==.Peychi:BAAALgAECgUJBgABLgAECgkJHgATABghAA==.Peycicle:BAABLgAECn8eAAITAAkJGCFKAQDOAgATAAkJGCFKAQDOAgAAAA==.Peysanity:BAAALgAECgQJBAABLgAECgkJHgATABghAA==.Peystruction:BAAALgAECgEJAgABLgAECgkJHgATABghAA==.Peytan:BAABLgAECn8VAAMNAAkJLxiTIQBCAgANAAkJLxiTIQBCAgAYAAEJuQmmdgAuAAABLgAECgkJHgATABghAA==.Peytin:BAAALgAECgQJBAABLgAECgkJHgATABghAA==.',
Ph='Phantasm:BAAALgADCgQJBwAAAA==.Phemoid:BAAALgADCgkJCQAAAA==.',
Pi='Pinkywhale:BAAALgAFFAIJAgAAAA==.Pippa:BAABLgAECn8nAAIdAAgJqB1HBgCbAgAdAAgJqB1HBgCbAgAAAA==.Pitythefu:BAAALgADCgcJBQAAAA==.',
Pl='Planett:BAABLgAECn8lAAMOAAkJChwTFgCNAgAOAAkJChwTFgCNAgAbAAEJFgPitAAcAAAAAA==.',
Po='Poetuck:BAABLgAECn8yAAIDAAkJnxRUSAD8AQADAAkJnxRUSAD8AQAAAA==.Pokeyruler:BAAALgAECgIJAgAAAA==.Pokeythorn:BAAALgADCgkJFwAAAA==.Pookießear:BAAALgADCgUJBQAAAA==.Powdrpufgirl:BAAALgADCgMJAwABLgAECgYJCAACAAAAAA==.',
Pr='Proko:BAABLgAECn8nAAMbAAgJFhPdRAAQAQAbAAYJ/hPdRAAQAQAOAAMJyBQDgwDHAAAAAA==.',
Ps='Psychovoodoo:BAAALgAECgIJBwAAAA==.',
Pu='Publicpool:BAAALgADCgEJAQAAAA==.Purfec:BAAALgADCgcJDAAAAA==.',
Qa='Qatka:BAAALgAECgQJBQAAAA==.',
Qu='Quiver:BAABLgAECn8iAAIKAAgJ1Q0kfQBpAQAKAAgJ1Q0kfQBpAQAAAA==.Quizle:BAAALgAECgEJAQAAAA==.',
['Qì']='Qìlen:BAABLgAECn8VAAIaAAcJzgw3LwDaAAAaAAcJzgw3LwDaAAAAAA==.',
Ra='Raein:BAABLgAECn8qAAMOAAgJiyQvBgBEAwAOAAgJiyQvBgBEAwAbAAYJnBcYPwAnAQAAAA==.Raginghog:BAAALgAECgUJCAAAAA==.Rainn:BAABLgAFFH8FAAIMAAMJDQYGMwCZAAAMAAMJDQYGMwCZAAAAAA==.Rainnsoul:BAAALgAECgYJDgAAAA==.Rakkclaw:BAAALgAECgEJAQABLgAECgEJAQACAAAAAA==.Ralofurius:BAAALgAECgYJCQAAAA==.Rasril:BAAALgAFFAEJAQAAAA==.Ratched:BAAALgADCgMJAwAAAA==.Raze:BAAALgAECgIJBgAAAA==.',
Re='Red:BAAALgADCgcJEgAAAA==.Redrighthand:BAAALgADCgEJAQAAAA==.Renicus:BAAALgADCgYJCAAAAA==.Renmare:BAABLgAECn8WAAIJAAUJOhddUAD+AAAJAAUJOhddUAD+AAAAAA==.Renmore:BAABLgAECn8VAAIKAAgJMBGUbQCIAQAKAAgJMBGUbQCIAQAAAA==.Rennzo:BAAALgADCggJDAAAAA==.Reshtargorr:BAAALgAECgEJAgAAAA==.',
Rg='Rgbpanda:BAAALgAECgQJBQAAAA==.',
Rh='Rhandoom:BAAALgADCgQJBAAAAA==.',
Ri='Ricky:BAAALgAECgEJAQAAAA==.Rikeji:BAAALgAECgYJCwAAAA==.Risotto:BAAALgAECgMJBQAAAA==.Riumi:BAAALgAECgMJCQAAAA==.Rivenxi:BAAALgAECgEJAQABLgAECgcJDAACAAAAAA==.',
Ro='Rocksolid:BAAALgAECgEJAgAAAA==.Ronaspreader:BAAALgAECgYJAwAAAA==.Roskolnikov:BAAALgAECgUJEAAAAA==.',
Ru='Rubymoonbeam:BAABLgAECn8jAAIFAAcJDw7YcgBOAQAFAAcJDw7YcgBOAQAAAA==.Ruele:BAACLgAFFH8HAAIGAAYJoA7QGgBvAQAGAAYJoA7QGgBvAQAuAAQKfxkAAgYACQmKH4sOAKUCAAYACQmKH4sOAKUCAAAA.Ruenan:BAABLgAECn8xAAMFAAkJxyY0AQCEAwAFAAkJxyY0AQCEAwAhAAMJlhKzaACcAAAAAA==.',
Ry='Ryain:BAABLgAECn85AAMRAAkJtg+/KQB3AQARAAkJ9Q2/KQB3AQAQAAcJnw8+JwAIAQAAAA==.Ryian:BAAALgAECgQJBAAAAA==.',
['Rä']='Räinns:BAABLgAECn8YAAIQAAcJNgo/GAD0AAAQAAcJNgo/GAD0AAAAAA==.',
Sa='Saintstephen:BAAALgADCggJGQAAAA==.Santajr:BAABLgAECn8eAAIkAAYJsAPhNgCOAAAkAAYJsAPhNgCOAAAAAA==.Sapthat:BAABLgAECn8bAAMlAAcJwyH7AwDqAQAlAAYJAyT7AwDqAQAeAAMJXBrkEQDnAAAAAA==.Sarahlina:BAAALgADCgcJBwAAAA==.Sarthrity:BAABLgAECn8aAAIDAAYJNwkhyAD4AAADAAYJNwkhyAD4AAAAAA==.Savemeh:BAAALgAECgEJAQAAAA==.Savepebble:BAABLgAECn8fAAMIAAkJMxRMYQB5AQAIAAgJ7Q9MYQB5AQAUAAUJXxfoHAC2AAAAAA==.',
Sc='Scalesofdoom:BAAALgAECgEJAgAAAA==.',
Se='Seather:BAABLgAECn8cAAIfAAgJ4BvDEwB4AgAfAAgJ4BvDEwB4AgAAAA==.Seirin:BAABLgAECn8qAAImAAgJrBTGGQDuAQAmAAgJrBTGGQDuAQAAAA==.Selendaa:BAAALgAECgUJEQAAAA==.Senadarra:BAACLgAFFH8cAAIhAAYJZhufCwCQAQAhAAYJZhufCwCQAQAuAAQKfzcAAiEACQkeIbUCALQCACEACQkeIbUCALQCAAAA.Sephenroth:BAAALgAECgQJBwAAAA==.Sephron:BAAALgAECggJEgAAAA==.Serendipity:BAAALgAECgcJBwABLgAECggJFAAYALISAA==.Serqet:BAABLgAECn8dAAQNAAYJIxZwZgBNAQANAAYJIxZwZgBNAQAnAAUJ+gPvIgB2AAAYAAEJAAAVfQAAAAAAAA==.Sethen:BAAALgAECgEJAQAAAA==.',
Sh='Shadowhawke:BAAALgADCggJCAAAAA==.Shadowofdoom:BAAALgAECgEJAQAAAA==.Shammology:BAABLgAECn8WAAIOAAcJPRI2SQB8AQAOAAcJPRI2SQB8AQAAAA==.Shaollyn:BAAALgAECgEJAQAAAA==.Sheri:BAABLgAECn8XAAITAAkJPhytAQBxAgATAAkJPhytAQBxAgAAAA==.Shizam:BAAALgAECgUJBQAAAA==.Shizzi:BAAALgAECgQJBgAAAA==.Shotowkhaan:BAABLgAECn8XAAMSAAYJHRUWRQByAQASAAYJHRUWRQByAQARAAEJaAK0oAAUAAAAAA==.Shotowkhann:BAAALgAECgIJAgAAAA==.Shoyoh:BAAALgAECgQJCQAAAA==.Shízu:BAAALgADCgkJDAAAAA==.',
Si='Sillygoose:BAACLgAFFH8mAAIDAAgJvRNyDwBVAgADAAgJvRNyDwBVAgAuAAQKfyQAAgMACQlJIJEVACcDAAMACQlJIJEVACcDAAAA.Sinadara:BAAALgAECgYJEAAAAA==.Sinïster:BAAALgADCgEJAQABLgAECgUJDAACAAAAAA==.Siong:BAAALgADCgcJCgABLgAFFAcJHQAKAMEhAA==.Siorknav:BAABLgAECn8fAAIKAAgJiQ66nwAsAQAKAAgJiQ66nwAsAQAAAA==.',
Sk='Skalar:BAABLgAECn8iAAIJAAgJwA3MMgB4AQAJAAgJwA3MMgB4AQAAAA==.Skipali:BAAALgAECgIJAgAAAA==.Skodah:BAAALgAECgEJAQABLgAECgUJDAACAAAAAA==.',
Sl='Släyr:BAAALgAECgMJBAAAAA==.',
So='Solunara:BAAALgADCgcJFgAAAA==.Somnambula:BAAALgADCgQJBAAAAA==.Sonadoria:BAABLgAECn8aAAIVAAgJ9w3ObQCAAQAVAAgJ9w3ObQCAAQAAAA==.Sorrenda:BAAALgADCgkJDwAAAA==.Soup:BAABLgAECn8nAAIgAAkJ/g1UEQCSAQAgAAkJ/g1UEQCSAQAAAA==.',
Sp='Sparow:BAAALgAECgEJAQAAAA==.Spinetarak:BAAALgADCgMJAwAAAA==.',
St='Stabbie:BAABLgAECn8XAAIfAAkJdRm7EwD5AQAfAAkJdRm7EwD5AQAAAA==.Stamina:BAAALgADCggJEAAAAA==.Stell:BAAALgAECgYJBwAAAA==.Stkawli:BAAALgAECgMJAwAAAA==.Stovik:BAABLgAECn8tAAMcAAkJdSGxAwC6AgAcAAkJdSGxAwC6AgAOAAcJ0REbRQCLAQAAAA==.',
Sv='Sventhebrave:BAAALgAECgUJEgAAAA==.',
Sw='Sweeneytod:BAAALgAECgIJBwAAAA==.Sweetpally:BAAALgADCgUJCAAAAA==.',
Sy='Sykill:BAAALgAECgUJCAAAAA==.Sylira:BAACLgAFFH8PAAMmAAYJ5xFCCwB7AQAmAAYJ5xFCCwB7AQAoAAEJMACnTAARAAAuAAQKfzgAAyYACQmUIksHAO8CACYACQmUIksHAO8CACkAAwkWDjBfAIwAAAAA.Sylk:BAAALgAECgUJBQABLgAECgYJEAACAAAAAA==.',
['Sö']='Söl:BAAALgAECgQJBAAAAA==.',
Ta='Taintedfel:BAAALgADCgkJCAAAAA==.Takamura:BAAALgAECgcJBwAAAA==.Takedown:BAACLgAFFH8SAAIXAAUJdRyMAwANAQAXAAUJdRyMAwANAQAuAAQKfywAAxcACQlhJBACACcDABcACQlhJBACACcDAAkABwkrGsUsAAECAAAA.Talena:BAAALgAECgcJBwAAAA==.Talleral:BAAALgAECgcJEAAAAA==.Tallyn:BAAALgAECgEJAQAAAA==.Tamanan:BAAALgAECgYJCwABLgAECgkJKQAoAM8OAA==.Tankie:BAAALgADCgEJAQAAAA==.Taurgrim:BAAALgADCgUJCQAAAA==.Tavin:BAAALgAECgEJAgAAAA==.Tazrav:BAAALgAECgMJAwAAAA==.',
Te='Terasha:BAAALgAECgkJBgAAAA==.',
Th='Thalid:BAAALgADCggJDgAAAA==.Tharonix:BAAALgAECgYJEwAAAA==.Thelitch:BAAALgADCgEJAgAAAA==.Theredpanda:BAAALgAECgUJBQAAAA==.Thewarden:BAAALgAECgIJAgAAAA==.',
Ti='Tic:BAAALgAECgYJBgAAAA==.Tigerwang:BAAALgAECgQJCAAAAA==.Tigrasia:BAAALgADCgYJCwAAAA==.Timaeus:BAABLgAECn87AAIDAAkJcx3lGQC4AgADAAkJcx3lGQC4AgAAAA==.Tinder:BAAALgADCgUJBQABLgAECgYJCAACAAAAAA==.',
Tm='Tmbeesknees:BAAALgAECgEJAQAAAA==.',
To='Touch:BAABLgAECn8UAAMpAAYJ2wwdQQADAQApAAYJ2wwdQQADAQAoAAEJ/Ql4dgAtAAAAAA==.Touchofkarma:BAAALgADCgcJDAAAAA==.',
Tr='Trifflinhoes:BAAALgAECgUJEAAAAA==.',
Tu='Turningblue:BAAALgADCgUJBAAAAA==.Tusktilldawn:BAAALgAECggJDQAAAA==.',
Tw='Twohoof:BAAALgADCgkJFQAAAA==.',
Ty='Tydrinor:BAAALgAECgcJAQAAAA==.',
['Tä']='Tänithðurden:BAAALgADCggJDgAAAA==.',
Ug='Ugin:BAAALgAECgUJBgAAAA==.',
Un='Unobasho:BAAALgAECgMJAwABLgAFFAQJCwABAH0PAA==.Unoboxo:BAAALgADCgEJAQABLgAFFAQJCwABAH0PAA==.Unovoke:BAACLgAFFH8LAAIBAAQJfQ+ELwD4AAABAAQJfQ+ELwD4AAAuAAQKfzUAAgEACQkrHY8RAFACAAEACQkrHY8RAFACAAAA.',
Va='Valeena:BAAALgADCgEJAQABLgAECgQJBAACAAAAAA==.Valorash:BAABLgAECn87AAMKAAkJCCLSCgAHAwAKAAkJCCLSCgAHAwALAAYJyhu4DwDJAQAAAA==.Valorious:BAAALgAECgMJAwAAAA==.Vandaira:BAAALgAECgkJAQAAAA==.Vasillisa:BAAALgAECgMJBQAAAA==.',
Ve='Vearick:BAAALgADCgYJCgAAAA==.Veleyna:BAAALgADCgcJCwAAAA==.Velgryn:BAAALgAECgUJBAAAAA==.Velintha:BAAALgAECgcJCAAAAA==.Venatrix:BAAALgAECgYJEQAAAA==.Vendrith:BAAALgADCgcJBwAAAA==.Veraxi:BAAALgADCgYJCwABLgAECgUJCgACAAAAAA==.Vessen:BAAALgADCgUJBwAAAA==.',
Vi='Vidascare:BAAALgAECgkJAgAAAA==.Vidu:BAAALgADCgUJBQAAAA==.Vision:BAAALgADCgYJBgAAAA==.',
Vl='Vluthier:BAAALgADCgYJBgAAAA==.',
Vo='Voidshatter:BAABLgAECn8bAAMYAAcJYgiwMgDjAAAYAAcJYgiwMgDjAAANAAYJcQJ/4QBhAAAAAA==.Vonderick:BAAALgAECgQJAwAAAA==.Voodoodog:BAAALgAECgMJBQABLgAECgYJDwACAAAAAA==.',
Vu='Vulgrimm:BAAALgAECgMJAwAAAA==.',
Vy='Vynlorellas:BAAALgAECgEJAQAAAA==.Vyéra:BAAALgADCgMJBgAAAA==.',
['Vè']='Vèsper:BAAALgAECgMJBQABLgAECgMJCQACAAAAAA==.',
Wa='Wakawli:BAAALgADCgYJBgAAAA==.Walex:BAAALgAECgkJBwAAAA==.Wally:BAAALgADCgMJAwAAAA==.Wardmneagle:BAAALgADCgUJCgAAAA==.Wargasm:BAAALgAECgQJBwABLgAECgcJDgACAAAAAA==.Watongo:BAAALgAECgUJBwAAAA==.Watsaheal:BAAALgAECgUJBQAAAA==.',
Wi='Wildborn:BAAALgADCgMJAwAAAA==.Willidan:BAAALgADCgEJAQAAAA==.Winwood:BAAALgADCgUJBwAAAA==.Withdrawals:BAAALgADCgYJBgABLgAECgMJCQACAAAAAA==.',
Wo='Woeify:BAABLgAECn8VAAIcAAcJ5xSuDgDRAQAcAAcJ5xSuDgDRAQAAAA==.',
Wr='Wreckless:BAAALgAECggJCAABLgAFFAQJCQAeALkdAA==.',
Wy='Wynce:BAAALgAECgUJCAAAAA==.',
Xa='Xalana:BAAALgADCgQJBAAAAA==.Xandaer:BAAALgAECgIJAwAAAA==.Xarn:BAABLgAECn8hAAIIAAkJtwdKdgBIAQAIAAkJtwdKdgBIAQAAAA==.',
Xc='Xcïte:BAABLgAECn8YAAQpAAgJwBqMJQCXAQApAAYJ9hyMJQCXAQAmAAMJ3RtaWADUAAAoAAUJtxDXSADRAAAAAA==.',
Xe='Xenroz:BAAALgADCgcJBwAAAA==.',
Ya='Yagudo:BAAALgADCgEJAQAAAA==.Yandòur:BAAALgADCgIJAgABLgAECgkJGQAUAIkPAA==.',
Ye='Yemon:BAAALgAECgUJBQAAAA==.',
Yo='Yodä:BAAALgADCgcJBwAAAA==.Yourlock:BAAALgADCgUJBQAAAA==.',
Yr='Yrelya:BAAALgAECgYJCQAAAA==.',
Yu='Yuji:BAACLgAFFH8FAAIKAAMJ3wXhdACxAAAKAAMJ3wXhdACxAAAuAAQKf0MAAgoACQlYFKI3ABgCAAoACQlYFKI3ABgCAAAA.',
Za='Zalectra:BAACLgAFFH8UAAIEAAQJHiHJCQBrAQAEAAQJHiHJCQBrAQAuAAQKfz4AAwQACQm2JUIAAMUDAAQACQm2JUIAAMUDACEAAgmhFg8oAG0AAAAA.',
Ze='Zelila:BAAALgAECgUJBAAAAA==.',
['Zü']='Zügzüg:BAAALgADCgEJAQAAAA==.',
['Âu']='Âurâ:BAAALgAECgUJBwAAAA==.',
['Ål']='Ålloria:BAABLgAECn8UAAIYAAcJFxhlGACvAQAYAAcJFxhlGACvAQAAAA==.',
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
