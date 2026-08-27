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

local lookup = {'Evoker-Augmentation','Shaman-Enhancement','Hunter-BeastMastery','Mage-Frost','Hunter-Survival','Priest-Discipline','Unknown-Unknown','Monk-Mistweaver','Monk-Brewmaster','Warlock-Demonology','Warrior-Fury','Paladin-Retribution','Paladin-Protection','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Paladin-Holy','DemonHunter-Devourer','Shaman-Restoration','Monk-Windwalker','Priest-Holy','Druid-Guardian','Druid-Balance','Druid-Restoration','Mage-Arcane','Warlock-Destruction','Evoker-Devastation','Warrior-Arms','DemonHunter-Havoc','Druid-Feral','Shaman-Elemental','Evoker-Preservation','Priest-Shadow','Rogue-Subtlety','Rogue-Assassination','Warlock-Affliction','Hunter-Marksmanship','Mage-Fire','Warrior-Protection','Rogue-Outlaw','DemonHunter-Vengeance',}
local provider = {region='US',realm='Gnomeregan',name='US',type='weekly',zone=46,date='2026-08-25',data={Ac='Acehuntura:BAAALgAECgEJAgAAAA==.',
Ad='Adaric:BAAALgAFFAEJAQAAAA==.',
Ae='Aerinin:BAAALgADCgMJAwAAAA==.',
Af='Afflicea:BAAALgAECgMJAwAAAA==.',
Ag='Agantsu:BAAALgAECgYJDQAAAA==.',
Ah='Ahava:BAAALgAECgQJBwAAAA==.',
Ai='Aidoneiscus:BAAALgAECgUJCgABLgAFFAYJEwABAH4aAA==.',
Aj='Ajani:BAAALgAECgYJDAAAAA==.',
Ak='Akamini:BAAALgAECgYJBwABLgAFFAMJCAACAA8XAA==.Akawli:BAAALgAECgIJAwAAAA==.',
Al='Alall:BAAALgAECgMJBgAAAA==.Alauth:BAAALgAECgIJAwAAAA==.Aldara:BAAALgADCgQJBAAAAA==.Aliceandreia:BAAALgADCgUJCgAAAA==.Alliethra:BAAALgAECgYJDQAAAA==.',
Am='Aminall:BAABLgAECn8UAAIDAAcJ9gWwMQCLAAADAAcJ9gWwMQCLAAAAAA==.',
An='Analbutmonke:BAAALgAECggJCgAAAA==.Anarreth:BAAALgADCgUJCgAAAA==.Anauthaho:BAAALgAECgkJDgAAAA==.Andahla:BAAALgADCgkJDgAAAA==.Andore:BAABLgAECn8zAAIEAAkJ8hxIBACbAgAEAAkJ8hxIBACbAgAAAA==.Anewbyss:BAAALgAFFAEJAQAAAA==.Angrymurloc:BAABLgAECn8aAAMFAAcJTAwaKwBJAQAFAAcJTAwaKwBJAQADAAUJMQLA9gBpAAAAAA==.Anthonie:BAAALgADCgYJBgAAAA==.Antoer:BAAALgAECgIJAgAAAA==.Anwyll:BAAALgADCgcJDAAAAA==.',
Ao='Aoir:BAAALgAECgQJBgAAAA==.',
Ap='Aposthmighty:BAAALgAECgYJEAABLgAECgkJGAAGAAISAA==.Apristina:BAAALgAECgkJCQAAAA==.',
Ar='Arcancis:BAAALgADCgQJBAAAAA==.Ariyia:BAAALgAECgMJAwAAAA==.Arlona:BAAALgAECgIJAwABLgAECgYJEAAHAAAAAA==.Arms:BAAALgAECgcJEAAAAA==.Artemyss:BAAALgADCgEJAQAAAA==.',
As='Ashanara:BAAALgAECgQJBAABLgAECgkJNQAIABUaAA==.Asher:BAAALgADCgEJAQAAAA==.Ashnact:BAAALgAECgIJDAAAAA==.Ashraki:BAAALgAECgEJAgAAAA==.Ashreign:BAAALgAECgkJCQAAAA==.Asl:BAAALgADCgcJBwAAAA==.Asonnari:BAAALgADCgEJAQAAAA==.Astraeal:BAABLgAECn8UAAIJAAYJwRHsPAAIAQAJAAYJwRHsPAAIAQAAAA==.Aswell:BAAALgAECgEJAQAAAA==.',
At='Atrania:BAAALgAECgUJCAAAAA==.Atreana:BAABLgAECn82AAIKAAkJ4hVRMAAXAgAKAAkJ4hVRMAAXAgAAAA==.Attykus:BAABLgAECn8xAAILAAgJ/BM1MQDoAQALAAgJ/BM1MQDoAQAAAA==.',
Av='Avalerion:BAACLgAFFH8JAAIMAAMJ/BH6NAC/AAAMAAMJ/BH6NAC/AAAuAAQKfyMAAwwACQmjG8IgAIQCAAwACQmjG8IgAIQCAA0AAglsHc0yAJgAAAAA.Avij:BAAALgAECgQJDQABLgAECgYJDAAHAAAAAA==.',
Ay='Ayoreo:BAAALgADCgMJAwAAAA==.',
Az='Azmodon:BAAALgADCgEJAwAAAA==.',
['Añ']='Añathema:BAAALgAECgMJBAAAAA==.',
Ba='Baldd:BAABLgAECn8aAAIEAAkJUBl5BQBeAgAEAAkJUBl5BQBeAgAAAA==.Balthor:BAABLgAECn8bAAQOAAgJuwXyRQB2AAAPAAYJ1wNJDwGZAAAOAAQJtwbyRQB2AAAQAAIJ8gHdFgA1AAAAAA==.Banfultoxxin:BAAALgADCggJDwAAAA==.Barelybob:BAAALgAECgMJAwABLgAECgkJIgAOAMwbAA==.Barrellroll:BAAALgADCgkJCQAAAA==.Bastam:BAAALgAECgIJAgABLgAECgIJBQAHAAAAAA==.Bat:BAAALgAECgQJBwAAAA==.Bayoneta:BAAALgAFFAEJAQAAAA==.',
Be='Bearlyhealz:BAAALgADCgkJBQAAAA==.Beercats:BAAALgADCgMJBgAAAA==.Bentotc:BAAALgAECgIJAwAAAA==.',
Bi='Bighoot:BAAALgAECgQJCgAAAA==.Bigmancow:BAABLgAECn8nAAIRAAkJTw+/KgC6AQARAAkJTw+/KgC6AQAAAA==.Bigpoppapump:BAAALgAECgQJBwAAAA==.Biomancer:BAAALgAECgYJBgAAAA==.Bismofungion:BAAALgAECgEJAQAAAA==.',
Bl='Bladestalker:BAAALgAECgEJAQAAAA==.Blind:BAAALgAECgYJCAAAAA==.Blindmayhem:BAAALgAECgEJAQAAAA==.Bludgens:BAAALgADCgIJAgAAAA==.Bluecoral:BAAALgADCgEJAQAAAA==.Blunter:BAABLgAECn8TAAISAAcJ5gYdlgDxAAASAAcJ5gYdlgDxAAAAAA==.Blushtime:BAAALgADCgIJAgAAAA==.Bluwhale:BAACLgAFFH8fAAITAAgJJB12AgDEAgATAAgJJB12AgDEAgAuAAQKfyYAAhMACQk+JIULAAEDABMACQk+JIULAAEDAAAA.',
Bo='Bocchi:BAAALgAECgEJAQAAAA==.Bodanky:BAAALgAECgMJBQAAAA==.Bormor:BAAALgAECgkJEwAAAA==.Bowdacious:BAABLgAECn8YAAIDAAUJCAhJMgCIAAADAAUJCAhJMgCIAAAAAA==.Boötes:BAAALgADCgcJBwAAAA==.',
Br='Brago:BAAALgAECgEJAQAAAA==.Braini:BAAALgADCgEJAQAAAA==.Brainpath:BAAALgAFFAIJAgAAAA==.Brasidias:BAAALgAECgYJCwAAAA==.Brickingkeys:BAAALgAECgIJBQAAAA==.Bruja:BAAALgAECgcJBwAAAA==.Brumak:BAAALgAECgkJCgAAAA==.Bruno:BAABLgAECn8rAAMNAAkJgBlEDQDwAQANAAkJgBlEDQDwAQAMAAQJKQcQ+gCfAAAAAA==.',
Bu='Budthespud:BAAALgAECgUJBgAAAA==.Burland:BAAALgAFFAIJAgAAAA==.',
['Bá']='Báthory:BAABLgAECn8UAAISAAkJohyKFgCQAgASAAkJohyKFgCQAgAAAA==.',
Ca='Caedus:BAAALgADCgYJBgAAAA==.Cal:BAAALgAECgYJDAABLgAFFAIJCAAJADMXAA==.Caladin:BAAALgAECgQJBAABLgAFFAIJCAAJADMXAA==.Calamity:BAAALgADCgQJBAAAAA==.Callistos:BAACLgAFFH8IAAIJAAIJMxefQgCaAAAJAAIJMxefQgCaAAAuAAQKfz0AAwkACQmeHnsIAKsCAAkACQmeHnsIAKsCABQAAgkgEX6aADUAAAAA.Camelshammy:BAAALgAECgYJDgAAAA==.Caradyn:BAAALgADCgUJBQABLgAECgYJFAAEACYTAA==.Caris:BAAALgAECgMJAwAAAA==.Castianna:BAABLgAECn8cAAIEAAYJGhE3GQARAQAEAAYJGhE3GQARAQAAAA==.',
Ce='Ceb:BAAALgADCgEJAQABLgAECggJIQAGALUZAA==.Cebastian:BAABLgAECn8hAAMGAAgJtRkXAwBAAgAGAAgJtRkXAwBAAgAVAAUJKBH6CgD3AAAAAA==.Cedarpoint:BAAALgAECgYJBgAAAA==.Celoria:BAAALgADCgUJCQAAAA==.Century:BAACLgAFFH8OAAMWAAIJoBP3FgByAAAXAAIJyw/9IAB4AAAWAAIJoBP3FgByAAAuAAQKf0oABBYACQnOHlgDALwBABcACQl2HC4QAGACABYACQmgGlgDALwBABgAAwk7FFMcAE0AAAAA.Cerriwyn:BAAALgAECgEJAQAAAA==.Cery:BAAALgAECgEJAQAAAA==.',
Ch='Chemikerin:BAAALgAECgEJAQAAAA==.Cheochan:BAAALgAECgUJCAAAAA==.Cherrybaby:BAAALgAECgEJAwAAAA==.Chewbaulk:BAAALgAECgkJBgAAAA==.Chizami:BAAALgAECggJDAABLgAFFAkJHwARAO0OAA==.Chocostarmie:BAAALgADCgQJBAAAAA==.Chug:BAABLgAECn8eAAIUAAkJlyCvCQCqAgAUAAkJlyCvCQCqAgAAAA==.',
Ci='Circa:BAABLgAECn8qAAMEAAkJhxVgQgAUAgAEAAkJOBVgQgAUAgAZAAQJWg7dEAC0AAAAAA==.Cithrel:BAABLgAECn8aAAMaAAkJiQ94FQD/AAAaAAkJiQ94FQD/AAAKAAEJLhGfOAAzAAAAAA==.',
Cl='Claylemian:BAAALgAECgMJAwAAAA==.',
Co='Commanshaman:BAAALgADCgMJAwAAAA==.Conqubine:BAAALgADCgkJDgAAAA==.Corban:BAAALgAECgEJAwAAAA==.',
Cr='Creolix:BAAALgADCgYJBgABLgAECgYJCAAHAAAAAA==.Crocklock:BAABLgAECn8ZAAIKAAcJ6hVJZwBvAQAKAAcJ6hVJZwBvAQAAAA==.',
Cu='Cuddlyblood:BAAALgAECgEJAQAAAA==.Cujo:BAAALgADCgMJAwAAAA==.',
['Cà']='Càssiàn:BAAALgADCgIJAgAAAA==.',
Da='Dallia:BAACLgAFFH8FAAIMAAIJ1gFVrABnAAAMAAIJ1gFVrABnAAAuAAQKfzYAAwwABwmpCTAzAIoAAAwABwmpCTAzAIoAAA0AAwntBZVDAFQAAAAA.Damnatio:BAABLgAECn8gAAIMAAkJmSRdEQDcAgAMAAkJmSRdEQDcAgAAAA==.Damonster:BAAALgAECgIJAwAAAA==.Dandan:BAAALgAECgEJAQAAAA==.Danoma:BAAALgAECgEJAQAAAA==.Danossa:BAAALgAECgEJBAAAAA==.Darkcithyoda:BAAALgAECgMJAwAAAA==.Darkclement:BAABLgAECn8gAAIDAAcJuCHzBgApAgADAAcJuCHzBgApAgABLgAFFAMJCQAMAE4TAA==.Darkin:BAAALgAECgcJCAAAAA==.Darkmist:BAAALgADCgUJBQAAAA==.Darksworn:BAAALgAECgkJDgAAAA==.Darkwiz:BAABLgAECn8bAAIPAAkJcgeOggBeAQAPAAkJcgeOggBeAQAAAA==.Darnala:BAAALgAECgMJAwAAAA==.',
De='Deadlydk:BAAALgADCgMJAwAAAA==.Deathbybob:BAABLgAECn8iAAIOAAkJzBu5BACXAQAOAAkJzBu5BACXAQAAAA==.Deathgriped:BAAALgAECgUJDgAAAA==.Deeper:BAACLgAFFH8PAAIXAAMJVQMTIQB3AAAXAAMJVQMTIQB3AAAuAAQKfyQAAxcACAkSDME3ADYBABcACAkSDME3ADYBABgAAwlqAXXdACgAAAAA.Deezmoonz:BAAALgADCgYJCQAAAA==.Dementos:BAAALgAECgIJAgAAAA==.Demonetra:BAAALgADCgMJAwABLgAECgcJDQAHAAAAAA==.Demonofwar:BAAALgADCgYJDAABLgAECgYJCAAHAAAAAA==.Devils:BAAALgAECgUJCQAAAA==.Dezzi:BAAALgADCgIJAQAAAA==.Dezzii:BAAALgAECgYJCgAAAA==.',
Di='Dirin:BAAALgAECgUJDQABLgAFFAgJFwAWADkTAA==.Disneymagic:BAAALgADCgUJBwAAAA==.Divacup:BAAALgADCgcJBwAAAA==.',
Dm='Dmaan:BAAALgADCgMJAwAAAA==.Dmfortoepics:BAAALgAECgUJBQAAAA==.',
Do='Doomflower:BAAALgAECgcJEQAAAA==.',
Dr='Dragonpebble:BAAALgADCgYJBgABLgAFFAMJBgAKALQRAA==.Drahalah:BAABLgAECn8eAAIPAAgJXR9uOQAaAgAPAAgJXR9uOQAaAgAAAA==.Drakeji:BAABLgAECn82AAMBAAkJnAwuMgBtAQABAAkJnAwuMgBtAQAbAAQJKAGhPwAxAAAAAA==.Dreamliner:BAAALgAECgYJBgAAAA==.Drezind:BAAALgAECgQJBAAAAA==.Drhades:BAAALgAECgEJAgAAAA==.Drhealalot:BAAALgAECgEJAQAAAA==.Drugar:BAAALgAFFAIJAgABLgAFFAUJEgAcAHUcAA==.',
Du='Dumparooski:BAAALgAECgEJAQABLgAFFAEJAQAHAAAAAA==.Dumplingg:BAAALgAECggJDAAAAA==.',
Ea='Earthvoodoo:BAAALgAECgYJDwAAAA==.',
Eb='Eberkenezer:BAAALgAECgQJBAAAAA==.Ebonlight:BAAALgADCgkJFgAAAA==.',
Ec='Echos:BAAALgAECgYJBgAAAA==.Ecnyw:BAAALgADCgMJAwABLgAECgUJCAAHAAAAAA==.',
Ed='Edence:BAAALgAECgMJAwAAAA==.',
Eh='Ehunter:BAAALgAECgUJDQAAAA==.',
Ei='Eillea:BAAALgADCgQJBAAAAA==.',
El='Elegant:BAAALgAECgkJBwAAAA==.Elspeth:BAAALgAECgIJAgAAAA==.Elsyria:BAAALgADCgIJAgABLgAFFAkJLgAMANEgAA==.Eluneslight:BAAALgAECgIJBAAAAA==.',
Em='Emmeri:BAAALgAECgQJBwABLgAECggJMQALAPwTAA==.',
En='Ender:BAAALgAECgkJAgAAAA==.',
Ep='Epi:BAABLgAECn8UAAIdAAgJshKxNgDhAAAdAAgJshKxNgDhAAAAAA==.',
Er='Erianis:BAAALgADCgMJAwAAAA==.Erniethemonk:BAAALgAECgYJEAAAAA==.',
Ev='Evianda:BAAALgADCgkJEAAAAA==.',
Ez='Ezale:BAAALgAECgkJEwAAAA==.Ezpz:BAAALgAECgYJEgAAAA==.',
Fa='Falsetto:BAAALgAECgEJAgAAAA==.Fameral:BAAALgAECgEJAwAAAA==.Faramír:BAABLgAECn8gAAMNAAcJuRi5AwCRAQANAAcJuRi5AwCRAQAMAAEJ5AJHyAEfAAAAAA==.Farrago:BAAALgAECgEJAgAAAA==.Fatébringer:BAAALgAECggJDgABLgAECgcJDgAHAAAAAA==.Fauhna:BAAALgAECgEJAQABLgAFFAIJBgAMACMiAA==.',
Fe='Fennek:BAABLgAECn8XAAIDAAkJ2A6xXACPAQADAAkJ2A6xXACPAQAAAA==.Feorio:BAAALgADCgEJAQABLgAECgYJEAAHAAAAAA==.',
Fi='Fiønaviolet:BAAALgADCgcJBwAAAA==.',
Fo='Fourth:BAAALgAECgIJAwABLgAECgcJEAAHAAAAAA==.',
Fr='Frayla:BAAALgADCgEJAQAAAA==.',
Fu='Furrywhenwet:BAAALgAFFAEJAQAAAA==.Fuzzyxbutt:BAAALgAECgYJDgAAAA==.',
Fy='Fyaaga:BAAALgAECgQJBAABLgAFFAYJCwAIADsSAA==.',
Ga='Galloc:BAAALgADCgkJEQAAAA==.Garaylo:BAACLgAFFH8uAAIMAAkJ0SBdBACgAgAMAAkJ0SBdBACgAgAuAAQKfykAAgwACQn1JMACAKwDAAwACQn1JMACAKwDAAAA.Garroar:BAAALgADCgcJCAAAAA==.',
Ge='Geed:BAAALgADCgEJAQAAAA==.Geoffreys:BAAALgAECgIJBAAAAA==.Gewnzilla:BAAALgAECgIJAgAAAA==.',
Gg='Ggxd:BAAALgADCgkJEAAAAA==.',
Gh='Ghosst:BAABLgAECn8jAAIFAAkJtiLuAgAIAwAFAAkJtiLuAgAIAwAAAA==.',
Gi='Gilberticus:BAAALgADCgMJAwABLgAECgkJZgAUANIiAA==.Gimlithekind:BAAALgAECgEJAQAAAA==.',
Gl='Glen:BAAALgADCgMJAwAAAA==.Gloktar:BAAALgAECgUJBQAAAA==.',
Gn='Gnobliterate:BAACLgAFFH8FAAMQAAIJjghtFQB0AAAPAAIJMwjk2QCIAAAQAAIJ/gZtFQB0AAAuAAQKfywABA8ACQkzEtJuAIcBAA8ACQn2D9JuAIcBABAABgk1DYodAOEAAA4AAgk1E2MVAFEAAAAA.Gnobolts:BAAALgAECgEJAQAAAA==.Gnobull:BAABLgAECn8mAAQWAAkJhxkNAwDQAQAWAAkJCRkNAwDQAQAXAAgJThdYBQCiAQAeAAMJ4AjTOAB2AAAAAA==.Gnochi:BAAALgAECgcJBwAAAA==.Gnudgnimish:BAAALgAFFAIJBAABLgAFFAUJBwAJALkZAA==.',
Go='Goldenblight:BAAALgAECgYJCwAAAA==.Goldenchi:BAAALgAECgEJAQAAAA==.Goldenrage:BAAALgAECgQJBAAAAA==.Goldenshammy:BAAALgAECgEJAQAAAA==.Gomper:BAAALgAECgMJBAAAAA==.Gonforgood:BAAALgADCgYJBgAAAA==.Goonmaxing:BAAALgADCgMJAwAAAA==.Gorilon:BAAALgAECgkJCQAAAA==.',
Gr='Grimclaw:BAAALgADCgYJDgAAAA==.Grimmrot:BAABLgAECn8VAAIGAAYJDgjhRAD1AAAGAAYJDgjhRAD1AAAAAA==.Grimmz:BAAALgADCggJCQAAAA==.Grizk:BAAALgADCgEJAQAAAA==.',
Gu='Guily:BAAALgAECgEJAQAAAA==.Guttris:BAAALgAECgYJEwAAAA==.',
Gw='Gwaineedk:BAAALgAECgMJBQAAAA==.Gwaineelock:BAAALgADCgEJAQAAAA==.Gwaineo:BAAALgAECgEJAQAAAA==.',
Ha='Hagridspells:BAAALgAECgEJAQABLgAECgYJDwAHAAAAAA==.Hahalu:BAAALgAECggJCAAAAA==.Haikusen:BAAALgADCgYJBAABLgAECgYJCAAHAAAAAA==.Halstron:BAACLgAFFH8GAAIMAAIJIyJTfQC8AAAMAAIJIyJTfQC8AAAuAAQKfy4AAwwACQm/IAoQAOYCAAwACQmPIAoQAOYCAA0ABQl7FechAAUBAAAA.Harrykeough:BAAALgAECgQJBwAAAA==.Hassan:BAAALgAECgQJBwAAAA==.Haupaa:BAAALgAECggJCQAAAA==.',
He='Heliòs:BAAALgAECgcJDQAAAA==.Hellwár:BAAALgADCgYJBgAAAA==.',
Ho='Hogfu:BAAALgAECgQJBAAAAA==.Hogshock:BAABLgAECn8bAAQfAAkJTRXRJgDcAQAfAAkJTRXRJgDcAQACAAMJXgfMJACLAAATAAEJhA2B4wAoAAAAAA==.Holocharizrd:BAAALgADCgcJCQAAAA==.Holyrequiem:BAAALgAECgUJBgAAAA==.Holyzel:BAABLgAECn8UAAIMAAkJTg3acQCKAQAMAAkJTg3acQCKAQAAAA==.Hotnsassie:BAAALgADCgMJCQAAAA==.Hound:BAAALgADCgUJCAAAAA==.Hoyt:BAAALgADCgcJBwAAAA==.',
Hs='Hsimingjung:BAACLgAFFH8HAAMJAAUJuRnEGQBWAQAJAAUJuRnEGQBWAQAUAAEJNQt5RAA2AAAuAAQKfykAAwkACQnLITgHAMMCAAkACQnLITgHAMMCABQABAlFIasmAIEBAAAA.',
Hu='Huh:BAABLgAECn8UAAMIAAYJ9BHBDgA6AQAIAAYJ9BHBDgA6AQAUAAQJ7wqZEwBoAAAAAA==.Humanic:BAAALgAECgIJAwAAAA==.Huntari:BAAALgAECgEJAwAAAA==.',
Hy='Hylie:BAACLgAFFH8SAAIKAAQJygmsOwChAAAKAAQJygmsOwChAAAuAAQKfx8AAgoACQnHEFlaALkBAAoACQnHEFlaALkBAAAA.',
['Hè']='Hèlla:BAAALgADCgkJFQAAAA==.',
Ig='Ignisky:BAAALgAECgcJDgABLgAFFAUJEgAcAHUcAA==.',
Il='Illidarie:BAAALgADCgUJCAAAAA==.Illilina:BAAALgADCgEJAQAAAA==.',
Im='Imadragon:BAAALgAECgEJAgABLgAFFAEJAQAHAAAAAA==.Imsofresh:BAAALgADCgEJAQAAAA==.',
In='Innitchiwa:BAAALgAECgEJAgAAAA==.Inte:BAAALgADCgYJBgAAAA==.Inzi:BAAALgAECgEJAwAAAA==.',
Iv='Ivanyr:BAAALgAFFAEJAgABLgAFFAgJFwAWADkTAA==.',
Iz='Izgin:BAABLgAECn8UAAIEAAYJJhN8ugASAQAEAAYJJhN8ugASAQAAAA==.',
Ja='Jadeyn:BAAALgADCgMJAwAAAA==.Jaime:BAAALgADCgYJCQABLgAECgYJCAAHAAAAAA==.Jalet:BAAALgADCgcJDQAAAA==.Janie:BAAALgADCgUJCAABLgADCgYJBgAHAAAAAA==.Jantar:BAABLgAECn8dAAIYAAkJMxrXFwCIAgAYAAkJMxrXFwCIAgAAAA==.Jasonbjorne:BAAALgAECgEJAQAAAA==.',
Je='Jebbyclipse:BAAALgAECgQJCAAAAA==.Jenzö:BAABLgAECn8cAAIfAAYJMRKvSQAOAQAfAAYJMRKvSQAOAQAAAA==.Jeramya:BAAALgADCgQJBAAAAA==.',
Jo='Joeviben:BAABLgAECn8bAAIMAAgJ/AqqsQAcAQAMAAgJ/AqqsQAcAQAAAA==.Jormungandr:BAAALgADCgYJCgABLgAFFAkJKgAEALgRAA==.',
Ju='Jugsy:BAACLgAFFH8GAAIEAAIJxBV3TgCZAAAEAAIJxBV3TgCZAAAuAAQKfxwAAgQACQniGb0uAF4CAAQACQniGb0uAF4CAAAA.Juliza:BAAALgADCgQJBAAAAA==.Jungfer:BAAALgAECgMJBAAAAA==.',
['Jë']='Jënzo:BAAALgADCggJCAABLgAECgkJHAAfADESAA==.',
Ka='Kaerodora:BAAALgADCgYJBgAAAA==.Kaikai:BAAALgAECgQJBQABLgAECggJIQAGALUZAA==.Kalasan:BAAALgAECgIJAgAAAA==.Kaldread:BAAALgAECgQJBgAAAA==.Kaligo:BAABLgAECn9CAAMfAAkJQBrnFABCAgAfAAkJQBrnFABCAgACAAQJrgSuIgCrAAAAAA==.Kalistus:BAABLgAECn8bAAISAAkJtwxlWQB7AQASAAkJtwxlWQB7AQAAAA==.Kallistos:BAAALgAECgEJAQABLgAFFAIJCAAJADMXAA==.Kalygos:BAAALgAECgQJBAABLgAFFAIJCAAJADMXAA==.Karall:BAAALgAECgEJAQAAAA==.Karetha:BAAALgAECgUJCQAAAA==.Katar:BAAALgAECgMJAwAAAA==.Katreset:BAAALgAECgUJCAAAAA==.Kazerath:BAAALgAECgYJBgAAAA==.',
Kd='Kdavid:BAAALgADCgUJCgAAAA==.',
Ke='Kebsy:BAABLgAECn87AAIUAAkJPiRbAwAtAwAUAAkJPiRbAwAtAwAAAA==.Kegfupanda:BAAALgAFFAEJAQAAAA==.Keleion:BAABLgAECn8nAAISAAcJzhDhgwAYAQASAAcJzhDhgwAYAQABLgAECgkJEwAHAAAAAA==.Kelements:BAAALgAFFAEJAQAAAA==.Kelvin:BAAALgAECgQJBAAAAA==.Kelyessada:BAAALgADCgYJBgAAAA==.Kevonjuravis:BAABLgAECn9TAAMJAAkJUw+GAwBpAQAJAAkJjA6GAwBpAQAUAAUJWxCiXQChAAAAAA==.',
Kh='Khalya:BAAALgAECgUJBQAAAA==.Khalyl:BAABLgAECn8WAAIdAAUJJRRnNQDoAAAdAAUJJRRnNQDoAAAAAA==.Khari:BAAALgAECgEJAQAAAA==.Khearts:BAAALgAECgEJAQAAAA==.Kholy:BAAALgADCgYJBgAAAA==.',
Ki='Kiandra:BAAALgADCgkJEAAAAA==.Kidrash:BAAALgADCgcJCAAAAA==.Killah:BAAALgAECgQJBgAAAA==.Kimegh:BAAALgADCgIJAgAAAA==.Kitsunae:BAAALgADCgcJHgAAAA==.',
Kl='Kleredan:BAAALgAECgkJBgAAAA==.',
Ko='Koder:BAACLgAFFH8TAAIBAAYJfhqTHQB0AQABAAYJfhqTHQB0AQAuAAQKfzUABAEACQnnIbEGABIDAAEACQnnIbEGABIDABsABwlXGS8HANABACAAAgkOArJEAEoAAAAA.Kozmoker:BAAALgAECgYJBgAAAA==.',
Kr='Krytus:BAAALgAECgEJAgAAAA==.',
Ku='Kungfu:BAAALgADCgQJBAABLgAECgYJDAAHAAAAAA==.Kungpaochik:BAAALgAECgIJAwABLgAFFAEJAQAHAAAAAA==.Kupó:BAAALgADCgUJBQABLgAECgYJDAAHAAAAAA==.',
Ky='Kyakdeath:BAABLgAECn81AAMPAAgJUho7WgC4AQAPAAgJUho7WgC4AQAQAAEJKwlwPAAuAAAAAA==.',
Kz='Kzo:BAABLgAECn8VAAMVAAgJvxuhGwD/AQAVAAYJSx6hGwD/AQAhAAgJJQ3OCQApAQAAAA==.',
La='Lailyre:BAAALgADCgQJBAAAAA==.Larroy:BAAALgAECgEJAQAAAA==.',
Le='Lecker:BAAALgAECgEJAQAAAA==.Legado:BAAALgAECgUJBwAAAA==.Lenalais:BAAALgAECgEJAgAAAA==.Leonitius:BAAALgAECgYJBwAAAA==.Lepaladine:BAAALgADCgYJCgAAAA==.',
Li='Lilbigcow:BAAALgAECgEJAwAAAA==.Lilithxander:BAAALgAECgUJCQAAAA==.Lilshooter:BAAALgAECgIJAwABLgAFFAQJBAAHAAAAAA==.Lizzybordan:BAABLgAECn8UAAMPAAgJJQ90nAAxAQAPAAgJ4At0nAAxAQAOAAMJ2A+hQACMAAAAAA==.',
Ll='Llaaroyy:BAAALgADCgEJAQAAAA==.Llarroii:BAAALgAECgEJAgAAAA==.',
Lo='Lohdek:BAAALgAECgcJAQAAAA==.Lohhangi:BAAALgADCgEJAgAAAA==.Lovar:BAAALgADCgYJBgAAAA==.',
Lu='Lucinick:BAABLgAECn88AAMiAAkJExaZAgDsAQAiAAkJLBKZAgDsAQAjAAYJ+BnhCgCFAQAAAA==.Lucy:BAAALgADCgIJAgAAAA==.Luxdiei:BAAALgAECgYJBgAAAA==.Luzziem:BAAALgAECgcJEwAAAA==.',
Ly='Lynx:BAAALgAECgEJBgAAAA==.',
['Lï']='Lïlith:BAAALgAECgkJAQAAAA==.',
Ma='Maeven:BAAALgADCgEJAQAAAA==.Margause:BAAALgAECgIJBAAAAA==.Mariskama:BAABLgAECn8jAAIDAAkJ9wWPcgBbAQADAAkJ9wWPcgBbAQAAAA==.Marió:BAAALgADCgMJAwAAAA==.Markusthered:BAAALgAECgMJBAAAAA==.Matrimcautho:BAAALgAECgEJAgAAAA==.Mavereith:BAAALgAECgEJAQAAAA==.Mazza:BAAALgAECgkJEQABLgAECgkJGAAVAGsYAA==.',
Mc='Mcbong:BAAALgAECgQJBwAAAA==.',
Me='Mello:BAAALgADCgYJBgAAAA==.Meowimabear:BAAALgADCgkJEAABLgAECgkJIwAFALYiAA==.Metal:BAAALgAECgQJDgAAAA==.Method:BAAALgADCgEJAQAAAA==.Meuccí:BAAALgAECgcJCwAAAA==.',
Mh='Mhelora:BAABLgAECn8XAAIYAAgJRArgawDxAAAYAAgJRArgawDxAAAAAA==.',
Mi='Mikkais:BAAALgAECgYJEwAAAA==.Mikkehunt:BAAALgAECgEJAQAAAA==.Mimacho:BAAALgAFFAEJAQAAAA==.Mindmuncher:BAAALgAECgIJAgAAAA==.Minimini:BAACLgAFFH8cAAIIAAcJ2RbgDQCqAQAIAAcJ2RbgDQCqAQAuAAQKfy4AAggACQkJHD0SAI0CAAgACQkJHD0SAI0CAAAA.Minni:BAAALgAFFAEJAwAAAA==.',
Mo='Monkeyfu:BAAALgAECgQJBAABLgAECgkJGAAkAMcRAA==.Moolin:BAABLgAECn8pAAIeAAkJigmnGwAvAQAeAAkJigmnGwAvAQAAAA==.Moranthe:BAAALgAECgcJDAABLgAFFAYJCwAIADsSAA==.Mordsyth:BAAALgAECgYJCgAAAA==.Morrowind:BAAALgADCgYJBgAAAA==.Mortis:BAAALgAECgEJAQAAAA==.',
Mu='Muggni:BAAALgAECgkJEQAAAA==.Muggypew:BAABLgAECn8UAAIlAAkJRgFkLgBeAAAlAAkJRgFkLgBeAAAAAA==.Munder:BAABLgAECn8mAAMkAAkJgB3XAwBxAgAkAAkJcBzXAwBxAgAKAAgJ/xkqUwCiAQAAAA==.Murdez:BAAALgAECgYJDgAAAA==.Mustymuppet:BAACLgAFFH8bAAIKAAUJmBcDRwA6AQAKAAUJmBcDRwA6AQAuAAQKfygAAwoACAnzGkA3APwBAAoACAnzGkA3APwBABoAAQlnD7VuADgAAAAA.',
My='Myrotheron:BAAALgADCgMJAwAAAA==.Mysticmeat:BAAALgAECgEJAQAAAA==.Mythicalbug:BAAALgADCgEJAQAAAA==.Mythuneran:BAABLgAECn8jAAMEAAkJyhv9BwAAAgAmAAkJdhe1AgAeAgAEAAcJjR39BwAAAgAAAA==.',
['Mø']='Mørzanna:BAAALgAECgYJCAAAAA==.',
Na='Naheka:BAAALgAECggJEgAAAA==.Nanookigaluk:BAAALgADCgYJBgAAAA==.Narrator:BAAALgAECgEJAgAAAA==.Navikz:BAAALgADCgUJBQAAAA==.',
Ne='Nekrose:BAABLgAECn8aAAIPAAgJwiIdIACJAgAPAAgJwiIdIACJAgAAAA==.Nemini:BAABLgAECn8lAAMVAAkJbA+fBgByAQAVAAkJbA+fBgByAQAhAAEJ7AG0mgAcAAAAAA==.Nena:BAABLgAECn9AAAIXAAkJEhVjCwAIAQAXAAkJEhVjCwAIAQAAAA==.Nenacurses:BAAALgAECgcJDwABLgAECgkJQAAXABIVAA==.Nenafury:BAAALgADCgMJAwABLgAECgkJQAAXABIVAA==.Nephilia:BAAALgADCgYJBgAAAA==.Newfy:BAAALgAFFAEJAwAAAA==.',
Ni='Ninjamage:BAAALgAECgUJBQAAAA==.Nistis:BAAALgAECgYJEQAAAA==.Niteshroud:BAAALgADCgMJAwAAAA==.Nithendroz:BAABLgAECn8YAAMbAAcJZgoDFgC0AAAbAAQJZgsDFgC0AAABAAMJaAjqgQBaAAAAAA==.Nity:BAAALgAECgQJBAAAAA==.Nivek:BAAALgAECgEJAQAAAA==.',
Nn='Nnivek:BAAALgAECgEJAQAAAA==.',
No='Noctaurus:BAABLgAECn8iAAIPAAkJ1QkbaQCUAQAPAAkJ1QkbaQCUAQAAAA==.Noczorro:BAAALgADCgYJBgAAAA==.Nomadhew:BAAALgAECgcJBwAAAA==.Noraice:BAAALgAECgEJAwAAAA==.Notagain:BAACLgAFFH9HAAIMAAkJlx7qAQDrAgAMAAkJlx7qAQDrAgAuAAQKfy4AAgwACQkBI5YHAFoDAAwACQkBI5YHAFoDAAAA.Notapally:BAAALgAECgQJBAAAAA==.Noxcorvus:BAAALgAECgcJDQAAAA==.',
Nu='Nuvo:BAAALgADCgYJBgAAAA==.',
Ny='Nylloc:BAAALgAECgkJCQAAAA==.Nymphàdoria:BAAALgAECgEJAQAAAA==.Nyuxx:BAABLgAECn8uAAITAAkJyBn/AgCbAgATAAkJyBn/AgCbAgAAAA==.',
['Nê']='Nêwfie:BAAALgAECgEJAwABLgAFFAEJAwAHAAAAAA==.',
Oc='Oceanic:BAAALgADCgYJCwAAAA==.Oceans:BAAALgAECgEJAQAAAA==.',
Od='Odphijor:BAAALgAECgkJAQAAAA==.',
Ol='Olenza:BAAALgAECgQJBwAAAA==.Olgreeneyes:BAAALgAECgIJBAAAAA==.',
Or='Orangewhale:BAABLgAECn8UAAIYAAYJChgpTABzAQAYAAYJChgpTABzAQAAAA==.',
Ou='Out:BAAALgAECgYJCwAAAA==.',
Ox='Oxidation:BAAALgADCgcJGgAAAA==.',
Pa='Painspongie:BAAALgADCgQJBQAAAA==.Pallybob:BAAALgAECgQJBAABLgAECgkJIgAOAMwbAA==.Patsajak:BAAALgADCgEJAQAAAA==.Pavo:BAAALgAECgcJCgAAAA==.Paynenecross:BAAALgAECgEJAQAAAA==.',
Pe='Pebbleshifts:BAAALgAECggJDAAAAA==.Peejean:BAAALgAECgYJBgAAAA==.Peyblade:BAAALgAECgYJBgABLgAECgkJHgAZABghAA==.Peybreak:BAAALgAECgIJAgABLgAECgkJHgAZABghAA==.Peychi:BAAALgAECgUJBgABLgAECgkJHgAZABghAA==.Peycicle:BAABLgAECn8eAAIZAAkJGCFKAQDOAgAZAAkJGCFKAQDOAgAAAA==.Peysanity:BAAALgAECgQJBAABLgAECgkJHgAZABghAA==.Peystruction:BAAALgAECgEJAgABLgAECgkJHgAZABghAA==.Peytan:BAABLgAECn8VAAMSAAkJLxiFIwBCAgASAAkJLxiFIwBCAgAdAAEJuQmmdgAuAAABLgAECgkJHgAZABghAA==.Peytin:BAAALgAECgQJBAABLgAECgkJHgAZABghAA==.',
Ph='Phantasm:BAAALgADCgQJBwAAAA==.Phemoid:BAAALgADCgkJCQAAAA==.',
Pi='Pinkywhale:BAAALgAFFAIJAgAAAA==.Pippa:BAABLgAECn8rAAIgAAkJEx2lBADeAgAgAAkJEx2lBADeAgAAAA==.Pitythefu:BAAALgADCgcJBQAAAA==.',
Pl='Planett:BAABLgAECn8lAAMTAAkJChyRFwCNAgATAAkJChyRFwCNAgAfAAEJFgOSwQAcAAAAAA==.',
Po='Poetuck:BAABLgAECn8yAAIEAAkJnxQUTgDyAQAEAAkJnxQUTgDyAQAAAA==.Pokeyruler:BAAALgAECgIJAgAAAA==.Pokeythorn:BAAALgADCgkJFwAAAA==.Polkabob:BAAALgAECgMJAwAAAA==.Pookießear:BAAALgADCgUJBQAAAA==.Powdrpufgirl:BAAALgADCgMJAwABLgAECgYJCAAHAAAAAA==.',
Pr='Proko:BAABLgAECn8vAAMTAAkJbxk4DABvAQATAAcJjBc4DABvAQAfAAcJ2BLHPgA5AQAAAA==.',
Ps='Psychovoodoo:BAAALgAECgIJBwAAAA==.',
Pu='Publicpool:BAAALgADCgEJAQAAAA==.Purfec:BAAALgADCgcJDAAAAA==.',
['Pü']='Püff:BAAALgADCgQJBAABLgAECgYJDAAHAAAAAA==.',
Qa='Qatka:BAAALgAECgcJDAAAAA==.',
Qu='Quiver:BAABLgAECn8iAAIMAAgJ1Q0uhgBjAQAMAAgJ1Q0uhgBjAQAAAA==.Quizle:BAAALgAECgEJAwAAAA==.',
['Qì']='Qìlen:BAABLgAECn8WAAIOAAcJzgyzMgDRAAAOAAcJzgyzMgDRAAAAAA==.',
Ra='Raein:BAABLgAECn8rAAMTAAkJqyLtAwB9AwATAAkJqyLtAwB9AwAfAAYJnBcQQwAnAQAAAA==.Raginghog:BAAALgAECgUJCAAAAA==.Rainn:BAACLgAFFH8LAAMRAAQJ4w9zEwDKAAARAAQJ4w9zEwDKAAAMAAEJ6AExywA1AAAuAAQKfxcABBEACAkGFdEbACUCABEACAkGFdEbACUCAA0ABAmuBZ41AG4AAAwAAQlGBLXEASEAAAAA.Rainnsoul:BAAALgAECgYJDgAAAA==.Rainnspow:BAAALgAFFAIJAgAAAA==.Rakkclaw:BAAALgAECgEJAQABLgAECgEJAQAHAAAAAA==.Ralofurius:BAAALgAECgYJDAAAAA==.Rasril:BAAALgAFFAEJAQAAAA==.Ratched:BAAALgADCgMJAwAAAA==.Raze:BAAALgAECgIJBgAAAA==.',
Re='Red:BAAALgADCgcJEgAAAA==.Redrighthand:BAAALgADCgEJAQAAAA==.Renicus:BAAALgADCgYJCAAAAA==.Renmare:BAABLgAECn8WAAILAAUJOhfLVAD5AAALAAUJOhfLVAD5AAAAAA==.Renmore:BAABLgAECn8VAAIMAAgJMBELdgCCAQAMAAgJMBELdgCCAQAAAA==.Rennzo:BAAALgADCggJDAAAAA==.Reshtargorr:BAAALgAECgEJAwAAAA==.Reze:BAAALgAECgEJAQAAAA==.',
Rg='Rgbpanda:BAAALgAECgQJBQAAAA==.',
Rh='Rhandoom:BAAALgADCgQJBAAAAA==.',
Ri='Ricky:BAAALgAECgEJAQAAAA==.Rikeji:BAAALgAECgkJEgAAAA==.Ripjohnnyarc:BAAALgAECgEJAQAAAA==.Risotto:BAAALgAECgQJBwAAAA==.Riumi:BAAALgAECgMJCQAAAA==.Rivenxi:BAAALgAECgEJAQABLgAECgcJDAAHAAAAAA==.',
Ro='Rocksolid:BAAALgAECgEJAgAAAA==.Ronaspreader:BAAALgAECgYJAwAAAA==.Roskolnikov:BAAALgAECgUJEAAAAA==.',
Ru='Rubymoonbeam:BAABLgAECn8mAAIDAAcJDw7FegBKAQADAAcJDw7FegBKAQAAAA==.Ruele:BAACLgAFFH8LAAIIAAYJOxLBHQCCAQAIAAYJOxLBHQCCAQAuAAQKfxwAAggACQnyH2gNAMUCAAgACQnyH2gNAMUCAAAA.Ruenan:BAABLgAECn8xAAMDAAkJxyaSAQB/AwADAAkJxyaSAQB/AwAlAAMJlhKzaACcAAAAAA==.Ruma:BAAALgAECgQJBAAAAA==.',
Ry='Ryain:BAABLgAECn85AAMXAAkJtg+2LABzAQAXAAkJ9Q22LABzAQAWAAcJnw+lKgAIAQAAAA==.Ryian:BAAALgAECgQJBAAAAA==.',
['Rä']='Räinns:BAABLgAECn8YAAIWAAcJNgo/GAD0AAAWAAcJNgo/GAD0AAAAAA==.',
Sa='Saintstephen:BAAALgADCggJGQAAAA==.Salinasmager:BAAALgAECgYJDQAAAA==.Santajr:BAABLgAECn8eAAInAAYJsAMdOgCMAAAnAAYJsAMdOgCMAAAAAA==.Sapthat:BAABLgAECn8bAAMoAAcJwyH7AwDqAQAoAAYJAyT7AwDqAQAjAAMJXBrkEQDnAAAAAA==.Sarahlina:BAAALgADCgcJBwAAAA==.Sarthrity:BAABLgAECn8aAAIEAAYJNwmi0QDvAAAEAAYJNwmi0QDvAAAAAA==.Satyrs:BAAALgAECgEJAQAAAA==.Savemeh:BAAALgAECgEJAQAAAA==.Savepebble:BAACLgAFFH8GAAIKAAMJtBEtNgCxAAAKAAMJtBEtNgCxAAAuAAQKfx8AAwoACQkzFLtoAGsBAAoACAntD7toAGsBABoABQlfF8weALMAAAAA.',
Sc='Scalesofdoom:BAAALgAECgEJAgAAAA==.Scootsy:BAAALgADCgYJBgAAAA==.',
Se='Seather:BAABLgAECn8cAAIiAAgJ4BvDEwB4AgAiAAgJ4BvDEwB4AgAAAA==.Seirin:BAABLgAECn8rAAIVAAkJbxMEFwAXAgAVAAkJbxMEFwAXAgAAAA==.Seldiane:BAAALgAECgYJCgAAAA==.Selendaa:BAAALgAECgUJEQAAAA==.Senadarra:BAACLgAFFH8jAAIlAAcJ6hcEDgB+AQAlAAcJ6hcEDgB+AQAuAAQKfzcAAiUACQkeIfICALECACUACQkeIfICALECAAAA.Senastera:BAAALgADCgcJDwAAAA==.Sephenroth:BAAALgAECgQJBwAAAA==.Sephiroot:BAAALgADCgIJAgABLgAECgkJGAAGAAISAA==.Sephron:BAABLgAECn8YAAIGAAkJAhLuFQAqAgAGAAkJAhLuFQAqAgAAAA==.Serendipity:BAAALgAECgcJBwABLgAECggJFAAdALISAA==.Serqet:BAABLgAECn8uAAQSAAgJXhZiOwDaAQASAAgJMBViOwDaAQAdAAQJHhZBEAChAAApAAYJGgV4CABxAAAAAA==.Sethen:BAAALgAECgEJAQAAAA==.',
Sh='Shadowhawke:BAAALgADCggJCAAAAA==.Shadowofdoom:BAAALgAECgEJAQAAAA==.Shaloria:BAAALgAECgkJBwAAAA==.Shammology:BAABLgAECn8WAAITAAcJPRJaTQB7AQATAAcJPRJaTQB7AQAAAA==.Shaollyn:BAAALgAECgYJDAAAAA==.Sheri:BAABLgAECn8XAAIZAAkJPhzcAQBpAgAZAAkJPhzcAQBpAgAAAA==.Shizam:BAAALgAECgUJBQAAAA==.Shizzi:BAAALgAECgQJBgAAAA==.Sho:BAAALgAECgEJAgAAAA==.Shotowkhaan:BAABLgAECn8fAAMYAAkJPRNkRgB2AQAYAAkJPRNkRgB2AQAXAAEJaAIkqgAUAAAAAA==.Shotowkhann:BAAALgAECgIJAgAAAA==.Shoyoh:BAAALgAECgQJCQAAAA==.Shízu:BAAALgAECgUJBQAAAA==.',
Si='Sikachu:BAAALgAECgEJAgABLgAECgcJFAAJAN4cAA==.Sillygoose:BAACLgAFFH8qAAIEAAkJuBHuFgA8AgAEAAkJuBHuFgA8AgAuAAQKfyQAAgQACQlJIJEVACcDAAQACQlJIJEVACcDAAAA.Sinadara:BAAALgAECgYJEAAAAA==.Sinïster:BAAALgADCgEJAQABLgAECgYJEAAHAAAAAA==.Siong:BAAALgADCgcJCgABLgAFFAkJLgAMANEgAA==.Siorknav:BAABLgAECn8fAAIMAAgJiQ6IqQApAQAMAAgJiQ6IqQApAQAAAA==.',
Sk='Skalar:BAABLgAECn85AAILAAkJJxGkBgCAAQALAAkJJxGkBgCAAQAAAA==.Skipali:BAAALgAECgIJAwAAAA==.Skodah:BAAALgAECgEJAQABLgAECgYJEAAHAAAAAA==.Skodoh:BAAALgAECgEJAQABLgAECgYJEAAHAAAAAA==.',
Sl='Slaydh:BAAALgAECgEJAQAAAA==.Släyr:BAAALgAECgMJBQAAAA==.',
So='Solunara:BAAALgADCgcJFgAAAA==.Somnambula:BAAALgADCgQJBAAAAA==.Sonadoria:BAABLgAECn8aAAIPAAgJ9w24dQB4AQAPAAgJ9w24dQB4AQAAAA==.Sorrenda:BAAALgADCgkJDwAAAA==.Soup:BAABLgAECn8nAAIeAAkJ/g3QEgCPAQAeAAkJ/g3QEgCPAQAAAA==.',
Sp='Sparow:BAAALgAECgEJAQAAAA==.Spinetarak:BAAALgADCgMJAwAAAA==.',
Sq='Squarey:BAABLgAECn8UAAIEAAkJegV4HAD5AAAEAAkJegV4HAD5AAAAAA==.',
St='Stabbie:BAABLgAECn8XAAIiAAkJdRk8FQD2AQAiAAkJdRk8FQD2AQAAAA==.Stamina:BAAALgADCggJEAAAAA==.Stell:BAAALgAECgYJBwAAAA==.Stinch:BAAALgAECgEJAQABLgAFFAEJAQAHAAAAAA==.Stkawli:BAAALgAECgMJAwAAAA==.Stovik:BAACLgAFFH8IAAMCAAMJDxesCQDDAAACAAMJDxesCQDDAAATAAEJTgoNgAA7AAAuAAQKfy4AAwIACQl1IRgEALYCAAIACQl1IRgEALYCABMABwnREd5IAIsBAAAA.',
Sv='Sventhebrave:BAAALgAECgkJEgAAAA==.',
Sw='Sweeneytod:BAAALgAECgIJCQAAAA==.Sweetpally:BAAALgADCgcJDAAAAA==.',
Sy='Sykill:BAAALgAECgcJCwAAAA==.Sylira:BAACLgAFFH8QAAMVAAYJ5xGpDQBxAQAVAAYJ5xGpDQBxAQAGAAEJMAAnVQARAAAuAAQKfzgAAxUACQmUIggIAOwCABUACQmUIggIAOwCACEAAwkWDo1mAIIAAAAA.Sylk:BAAALgAECgUJBQABLgAECgYJEAAHAAAAAA==.',
['Sö']='Söl:BAAALgAECgQJBAAAAA==.',
Ta='Taintedfel:BAAALgADCgkJCAAAAA==.Takamura:BAAALgAECgcJBwAAAA==.Takedown:BAACLgAFFH8SAAIcAAUJdRyMAwANAQAcAAUJdRyMAwANAQAuAAQKfywAAxwACQlhJHwCACIDABwACQlhJHwCACIDAAsABwkrGsUsAAECAAAA.Talena:BAAALgAECgcJBwAAAA==.Talleral:BAABLgAECn8dAAMGAAkJthbkDgCBAgAGAAkJthbkDgCBAgAVAAEJ2BBNfwAzAAAAAA==.Tallyn:BAAALgAECgEJAQAAAA==.Tamanan:BAAALgAECgYJDQABLgAFFAIJDAABANoJAA==.Tankie:BAAALgADCgEJAQAAAA==.Taurgrim:BAAALgADCgUJCQAAAA==.Tavin:BAAALgAFFAEJAQAAAA==.Tazrav:BAAALgAECgMJAwAAAA==.',
Te='Temamañ:BAACLgAFFH8MAAIBAAIJ2gnFLQBhAAABAAIJ2gnFLQBhAAAuAAQKfxkAAwEACQkyEwYDAK8BAAEACQkyEwYDAK8BACAAAgnoBTkPAC8AAAAA.Terasha:BAAALgAECgkJCQAAAA==.',
Th='Thalid:BAAALgAECgEJAgAAAA==.Tharonix:BAAALgAECgYJEwAAAA==.Thelitch:BAAALgADCgEJAgAAAA==.Theredpanda:BAAALgAECgUJBQAAAA==.Thewarden:BAAALgAECgIJAgAAAA==.Thunderfist:BAAALgADCgEJAQAAAA==.',
Ti='Tic:BAAALgAECgYJBgAAAA==.Tigerwang:BAAALgAECgQJCAAAAA==.Tigrasia:BAAALgADCgYJCwAAAA==.Timaeus:BAACLgAFFH8JAAIEAAMJwg0MRQC2AAAEAAMJwg0MRQC2AAAuAAQKfz4AAgQACQkPIFscALICAAQACQkPIFscALICAAAA.Tinder:BAAALgADCgUJBQABLgAECgYJCAAHAAAAAA==.Tinkkster:BAAALgAECgEJBAAAAA==.',
Tm='Tmbeesknees:BAAALgAECgIJAgAAAA==.',
To='Touch:BAABLgAECn8WAAMhAAYJjw8LRQD6AAAhAAYJjw8LRQD6AAAGAAEJ/QlffwAtAAAAAA==.Touchofkarma:BAAALgADCgcJFAAAAA==.',
Tr='Trifflinhoes:BAAALgAECgUJEAAAAA==.Trishi:BAAALgAECgYJDAAAAA==.Tristtan:BAAALgAECgEJAQAAAA==.Trytoheal:BAAALgAECgIJAwAAAA==.Trôjan:BAAALgAECgYJBwAAAA==.',
Ts='Tsuku:BAAALgAECgUJBQAAAA==.',
Tu='Turningblue:BAAALgADCgUJBAAAAA==.Tusktilldawn:BAABLgAECn8VAAMOAAgJ5RCBGwCAAQAOAAgJzRCBGwCAAQAQAAIJ2wTnNgBBAAAAAA==.',
Tw='Twohoof:BAAALgADCgkJFQAAAA==.',
Ty='Tydrinor:BAAALgAECgcJAQAAAA==.',
['Tä']='Tänithðurden:BAAALgADCggJDgAAAA==.',
Ug='Ugin:BAAALgAECgUJBgAAAA==.',
Un='Unobasho:BAAALgAECgMJAwABLgAFFAQJDQABAH0PAA==.Unoblasto:BAAALgAECgEJAQAAAA==.Unoboxo:BAAALgADCgEJAQABLgAFFAQJDQABAH0PAA==.Unoo:BAAALgADCgEJAQAAAA==.Unovoke:BAACLgAFFH8NAAIBAAQJfQ8qNQDuAAABAAQJfQ8qNQDuAAAuAAQKfzUAAgEACQkrHUcSAFACAAEACQkrHUcSAFACAAAA.',
Va='Valeena:BAAALgADCgEJAQABLgAECgQJBAAHAAAAAA==.Valorash:BAACLgAFFH8FAAIMAAIJgBr0hwCjAAAMAAIJgBr0hwCjAAAuAAQKfzsAAwwACQkIImQMAAIDAAwACQkIImQMAAIDAA0ABgnKG7gPAMkBAAAA.Valorious:BAAALgAECgUJCwAAAA==.Vandaira:BAAALgAECgkJAgAAAA==.Vasillisa:BAAALgAECgMJBQAAAA==.',
Ve='Vearick:BAAALgADCgYJCgAAAA==.Veleyna:BAAALgADCgcJCwAAAA==.Velgryn:BAAALgAECgUJBAAAAA==.Velintha:BAAALgAECgcJCAAAAA==.Venatrix:BAAALgAECgYJEQAAAA==.Vendrith:BAAALgADCgcJBwAAAA==.Venivedivici:BAAALgADCgEJAQAAAA==.Veraxi:BAAALgADCgYJCwABLgAFFAgJFwAWADkTAA==.',
Vi='Vidascare:BAAALgAECgkJAgAAAA==.Vidu:BAAALgADCgUJBQAAAA==.Vision:BAABLgAFFH8GAAIMAAMJ/xNDLQDWAAAMAAMJ/xNDLQDWAAAAAA==.',
Vl='Vluthier:BAAALgADCgYJBgAAAA==.',
Vo='Voidshatter:BAABLgAECn8bAAMdAAcJYgi8NgDgAAAdAAcJYgi8NgDgAAASAAYJcQIO7gBhAAAAAA==.Vonderick:BAAALgAECgQJAwAAAA==.Voodoodog:BAAALgAECgMJBQABLgAECgYJDwAHAAAAAA==.',
Vu='Vulgrimm:BAAALgAECgUJBQAAAA==.',
Vy='Vynlorellas:BAAALgAECgEJAgAAAA==.Vyéra:BAAALgADCgMJBgAAAA==.',
['Vè']='Vèsper:BAAALgAECgMJBQABLgAECgMJCQAHAAAAAA==.',
['Vô']='Vôha:BAAALgAECgEJAQAAAA==.',
Wa='Wakawli:BAAALgADCgYJBgAAAA==.Walex:BAAALgAECgkJBwAAAA==.Wally:BAAALgADCgMJAwAAAA==.Wardmneagle:BAAALgADCgUJCgAAAA==.Wargasm:BAAALgAECgYJDAABLgAECggJFAAPACUPAA==.Wars:BAAALgAECgcJCgAAAA==.Watongo:BAAALgAECgUJBwAAAA==.Watsaheal:BAAALgAECgYJCQAAAA==.',
Wi='Wildborn:BAAALgADCgMJAwAAAA==.Willidan:BAAALgADCgEJAQAAAA==.Winwood:BAAALgADCgUJBwAAAA==.Withdrawals:BAAALgADCgYJBgABLgAECgMJCQAHAAAAAA==.',
Wo='Woeify:BAABLgAECn8VAAICAAcJ5xSuDgDRAQACAAcJ5xSuDgDRAQAAAA==.',
Wr='Wreckless:BAAALgAECggJCAABLgAFFAYJIQAjAAIdAA==.',
Wy='Wynce:BAAALgAECgUJCAAAAA==.',
Xa='Xalana:BAAALgADCgQJBAAAAA==.Xandaer:BAAALgAECggJDAAAAA==.Xarn:BAABLgAECn8hAAIKAAkJtwdvagCOAQAKAAkJtwdvagCOAQAAAA==.',
Xc='Xcïte:BAABLgAECn8bAAQhAAgJwBo1JwCUAQAhAAYJ9hw1JwCUAQAGAAcJPBnECgAyAQAVAAMJ3RtaWADUAAAAAA==.',
Xe='Xenroz:BAAALgADCgcJBwAAAA==.',
Ya='Yaader:BAAALgADCgUJBQAAAA==.Yagudo:BAAALgADCgEJAQAAAA==.Yandòur:BAAALgADCgIJAgABLgAECgkJGgAaAIkPAA==.',
Ye='Yemon:BAAALgAECgUJBQAAAA==.',
Yo='Yodä:BAAALgADCgcJBwAAAA==.Yosh:BAAALgADCgQJBAAAAA==.Yourlock:BAAALgADCgUJBQAAAA==.',
Yr='Yrelya:BAAALgAECgYJCQAAAA==.',
Yu='Yuji:BAACLgAFFH8LAAIMAAMJjAjVfgC4AAAMAAMJjAjVfgC4AAAuAAQKf1cAAgwACQluGOULAKoBAAwACQluGOULAKoBAAAA.',
Za='Zalectra:BAACLgAFFH8WAAIFAAQJHiEsDABkAQAFAAQJHiEsDABkAQAuAAQKfz4AAwUACQm2JUIAAMUDAAUACQm2JUIAAMUDACUAAgmhFhkqAG0AAAAA.Zarnie:BAAALgADCgUJBQAAAA==.',
Ze='Ze:BAAALgAECgYJDAAAAA==.Zelila:BAAALgAECgUJBAAAAA==.Zephyruss:BAAALgADCgMJAwAAAA==.',
Zo='Zoei:BAAALgAECgQJBAAAAA==.',
['Zü']='Zügzüg:BAAALgADCgEJAQAAAA==.',
['Âu']='Âurâ:BAAALgAECgUJBwAAAA==.',
['Ål']='Ålloria:BAABLgAECn8ZAAIdAAgJQRnvEwDzAQAdAAgJQRnvEwDzAQAAAA==.',
['Ón']='Ónix:BAAALgAECgEJAgAAAA==.',
['Óü']='Óüíðåwðíð:BAAALgADCgMJAwAAAA==.',
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
