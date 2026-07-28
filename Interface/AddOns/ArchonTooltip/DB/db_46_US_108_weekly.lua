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

local lookup = {'Evoker-Augmentation','Priest-Discipline','Shaman-Enhancement','Hunter-BeastMastery','Mage-Frost','Hunter-Survival','Unknown-Unknown','Monk-Mistweaver','Monk-Brewmaster','Warlock-Demonology','Warrior-Fury','Paladin-Retribution','Paladin-Protection','DeathKnight-Blood','Paladin-Holy','DemonHunter-Devourer','Shaman-Restoration','Monk-Windwalker','Priest-Holy','Druid-Guardian','Druid-Balance','Druid-Restoration','Mage-Arcane','Warlock-Destruction','DeathKnight-Unholy','Evoker-Devastation','Warrior-Arms','DemonHunter-Havoc','DeathKnight-Frost','Druid-Feral','Shaman-Elemental','Evoker-Preservation','Priest-Shadow','Rogue-Subtlety','Rogue-Assassination','Hunter-Marksmanship','Warlock-Affliction','Mage-Fire','Warrior-Protection','Rogue-Outlaw','DemonHunter-Vengeance',}
local provider = {region='US',realm='Gnomeregan',name='US',type='weekly',zone=46,date='2026-07-28',data={Ac='Acehuntura:BAAALgAECgEJAgAAAA==.',
Ad='Adaric:BAAALgAFFAEJAQAAAA==.',
Ae='Aerinin:BAAALgADCgMJAwAAAA==.',
Af='Afflicea:BAAALgAECgMJAwAAAA==.',
Ag='Agantsu:BAAALgAECgYJDQAAAA==.',
Ah='Ahava:BAAALgAECgQJBwAAAA==.',
Ai='Aidoneiscus:BAAALgAECgUJCgABLgAFFAYJEwABAH4aAA==.Ainokea:BAAALgAECgQJBQABLgAECggJHAACANwYAA==.Aiyaiyai:BAAALgAECgYJDQAAAA==.',
Aj='Ajani:BAAALgAECgYJDAAAAA==.',
Ak='Akamini:BAAALgAECgYJBwABLgAFFAMJCAADAA8XAA==.Akawli:BAAALgAECgIJAwAAAA==.',
Al='Alall:BAAALgAECgMJBgAAAA==.Alauth:BAAALgAECgIJAwAAAA==.Aldara:BAAALgADCgQJBAAAAA==.Aliceandreia:BAAALgADCgUJCgAAAA==.Alliethra:BAAALgAECgYJDQAAAA==.',
Am='Aminall:BAABLgAECn8UAAIEAAcJ9gW6KwCLAAAEAAcJ9gW6KwCLAAAAAA==.',
An='Anarreth:BAAALgADCgUJCgAAAA==.Anauthaho:BAAALgAECgcJBwAAAA==.Andahla:BAAALgADCgkJDgAAAA==.Andore:BAABLgAECn8zAAIFAAkJ8hynAwCiAgAFAAkJ8hynAwCiAgAAAA==.Anewbyss:BAAALgAFFAEJAQAAAA==.Angrymurloc:BAABLgAECn8aAAMGAAcJTAwaKwBJAQAGAAcJTAwaKwBJAQAEAAUJMQLA9gBpAAAAAA==.Anthonie:BAAALgADCgYJBgAAAA==.Antoer:BAAALgAECgIJAgAAAA==.Anwyll:BAAALgADCgcJDAAAAA==.',
Ao='Aoir:BAAALgAECgQJBgAAAA==.',
Ap='Aposthmighty:BAAALgAECgYJEAAAAA==.',
Ar='Arcancis:BAAALgADCgQJBAAAAA==.Ariyia:BAAALgAECgMJAwAAAA==.Arlona:BAAALgAECgIJAwABLgAECgYJEAAHAAAAAA==.Arms:BAAALgAECgcJEAAAAA==.Artemyss:BAAALgADCgEJAQAAAA==.',
As='Ashanara:BAAALgAECgQJBAABLgAECgkJNQAIABUaAA==.Asher:BAAALgADCgEJAQAAAA==.Ashnact:BAAALgAECgIJDAAAAA==.Ashraki:BAAALgAECgEJAgAAAA==.Ashreign:BAAALgAECgkJCQAAAA==.Asl:BAAALgADCgcJBwAAAA==.Asonnari:BAAALgADCgEJAQAAAA==.Astraeal:BAABLgAECn8UAAIJAAYJwRHsPAAIAQAJAAYJwRHsPAAIAQAAAA==.Aswell:BAAALgAECgEJAQAAAA==.',
At='Atrania:BAAALgAECgUJCAAAAA==.Atreana:BAABLgAECn82AAIKAAkJ4hVRMAAXAgAKAAkJ4hVRMAAXAgAAAA==.Attykus:BAABLgAECn8xAAILAAgJ/BM1MQDoAQALAAgJ/BM1MQDoAQAAAA==.',
Av='Avalerion:BAACLgAFFH8JAAIMAAMJ/BESMQDGAAAMAAMJ/BESMQDGAAAuAAQKfyMAAwwACQmjG8IgAIQCAAwACQmjG8IgAIQCAA0AAglsHc0yAJgAAAAA.Avij:BAAALgAECgQJDQABLgAECgYJDAAHAAAAAA==.',
Ay='Ayoreo:BAAALgADCgMJAwAAAA==.',
Az='Azmodon:BAAALgADCgEJAwAAAA==.',
['Añ']='Añathema:BAAALgAECgMJBAAAAA==.',
Ba='Baldd:BAABLgAECn8YAAIFAAgJcBruBQAiAgAFAAgJcBruBQAiAgAAAA==.Banfultoxxin:BAAALgADCggJDwAAAA==.Barelybob:BAAALgAECgMJAwABLgAECgkJIQAOAMwbAA==.Barrellroll:BAAALgADCgkJCQAAAA==.Bastam:BAAALgAECgIJAgABLgAECgIJBQAHAAAAAA==.Bat:BAAALgAECgQJBwAAAA==.Bayoneta:BAAALgAFFAEJAQAAAA==.',
Be='Bearlyhealz:BAAALgADCgkJBQAAAA==.Beercats:BAAALgADCgMJBgAAAA==.Bentotc:BAAALgAECgIJAwAAAA==.',
Bi='Bighoot:BAAALgAECgQJCgAAAA==.Bigmancow:BAABLgAECn8nAAIPAAkJTw+/KgC6AQAPAAkJTw+/KgC6AQAAAA==.Bigpoppapump:BAAALgAECgQJBwAAAA==.Biomancer:BAAALgAECgYJBgAAAA==.Bismofungion:BAAALgADCgcJEAAAAA==.',
Bl='Bladestalker:BAAALgAECgEJAQAAAA==.Blind:BAAALgAECgYJCAAAAA==.Blindmayhem:BAAALgAECgEJAQAAAA==.Bludgens:BAAALgADCgIJAgAAAA==.Bluecoral:BAAALgADCgEJAQAAAA==.Blunter:BAABLgAECn8TAAIQAAcJ5gYdlgDxAAAQAAcJ5gYdlgDxAAAAAA==.Blushtime:BAAALgADCgIJAgAAAA==.Bluwhale:BAACLgAFFH8fAAIRAAgJJB12AgDEAgARAAgJJB12AgDEAgAuAAQKfyYAAhEACQk+JIULAAEDABEACQk+JIULAAEDAAAA.',
Bo='Bocchi:BAAALgAECgEJAQAAAA==.Bodanky:BAAALgAECgMJBQAAAA==.Bormor:BAAALgAECgkJEwAAAA==.Bowdacious:BAABLgAECn8YAAIEAAUJCAgzLACIAAAEAAUJCAgzLACIAAAAAA==.Boötes:BAAALgADCgcJBwAAAA==.',
Br='Brago:BAAALgAECgEJAQAAAA==.Braini:BAAALgADCgEJAQAAAA==.Brainpath:BAAALgAFFAIJAgAAAA==.Brasidias:BAAALgAECgYJCwAAAA==.Brickingkeys:BAAALgAECgIJBQAAAA==.Brumak:BAAALgAECgkJCgAAAA==.Bruno:BAABLgAECn8rAAMNAAkJgBlEDQDwAQANAAkJgBlEDQDwAQAMAAQJKQcQ+gCfAAAAAA==.',
Bu='Budthespud:BAAALgAECgUJBgAAAA==.Burland:BAAALgAFFAIJAgAAAA==.',
['Bá']='Báthory:BAABLgAECn8UAAIQAAkJohyKFgCQAgAQAAkJohyKFgCQAgAAAA==.',
Ca='Caedus:BAAALgADCgYJBgAAAA==.Cal:BAAALgAECgYJDAABLgAFFAIJCAAJADMXAA==.Caladin:BAAALgAECgQJBAABLgAFFAIJCAAJADMXAA==.Calamity:BAAALgADCgQJBAAAAA==.Callistos:BAACLgAFFH8IAAIJAAIJMxefQgCaAAAJAAIJMxefQgCaAAAuAAQKfz0AAwkACQmeHnsIAKsCAAkACQmeHnsIAKsCABIAAgkgEX6aADUAAAAA.Camelshammy:BAAALgAECgYJDgAAAA==.Caradyn:BAAALgADCgUJBQABLgAECgYJFAAFACYTAA==.Caris:BAAALgAECgMJAwAAAA==.Castianna:BAABLgAECn8cAAIFAAYJGhFFFgARAQAFAAYJGhFFFgARAQAAAA==.',
Ce='Ceb:BAAALgADCgEJAQABLgAECggJHAACANwYAA==.Cebastian:BAABLgAECn8cAAMCAAgJ3Bh/BADLAQACAAgJ2Bd/BADLAQATAAUJKBGbCQD4AAAAAA==.Cedarpoint:BAAALgAECgYJBgAAAA==.Celoria:BAAALgADCgUJCQAAAA==.Century:BAACLgAFFH8KAAMUAAIJgRETGQBmAAAVAAIJyw/0HQB3AAAUAAIJgRETGQBmAAAuAAQKf0oABBQACQnOHucCAMABABUACQl2HC4QAGACABQACQmgGucCAMABABYAAwk7FAYZAE4AAAAA.Cerriwyn:BAAALgAECgEJAQAAAA==.Cery:BAAALgAECgEJAQAAAA==.',
Ch='Cheochan:BAAALgAECgUJCAAAAA==.Cherrybaby:BAAALgAECgEJAgAAAA==.Chewbaulk:BAAALgAECgkJBgAAAA==.Chizami:BAAALgAECggJDAABLgAFFAgJGQAPANEMAA==.Chocostarmie:BAAALgADCgQJBAAAAA==.Chug:BAABLgAECn8eAAISAAkJlyCvCQCqAgASAAkJlyCvCQCqAgAAAA==.',
Ci='Circa:BAABLgAECn8qAAMFAAkJhxVgQgAUAgAFAAkJOBVgQgAUAgAXAAQJWg7dEAC0AAAAAA==.Cithrel:BAABLgAECn8aAAMYAAkJiQ94FQD/AAAYAAkJiQ94FQD/AAAKAAEJLhFxMgA0AAAAAA==.',
Cl='Claylemian:BAAALgAECgMJAwAAAA==.',
Co='Commanshaman:BAAALgADCgMJAwAAAA==.Conqubine:BAAALgADCgkJDgAAAA==.Corban:BAAALgAECgEJAwAAAA==.',
Cr='Creolix:BAAALgADCgYJBgABLgAECgYJCAAHAAAAAA==.Crocklock:BAABLgAECn8ZAAIKAAcJ6hVJZwBvAQAKAAcJ6hVJZwBvAQAAAA==.',
Cu='Cuddlyblood:BAAALgAECgEJAQAAAA==.Cujo:BAAALgADCgMJAwAAAA==.',
['Cà']='Càssiàn:BAAALgADCgIJAgAAAA==.',
Da='Dallia:BAACLgAFFH8FAAIMAAIJ1gFVrABnAAAMAAIJ1gFVrABnAAAuAAQKfzYAAwwABwmpCYksAIkAAAwABwmpCYksAIkAAA0AAwntBZVDAFQAAAAA.Damnatio:BAABLgAECn8gAAIMAAkJmSRdEQDcAgAMAAkJmSRdEQDcAgAAAA==.Damonster:BAAALgAECgIJAwAAAA==.Dandan:BAAALgAECgEJAQAAAA==.Danoma:BAAALgAECgEJAQAAAA==.Danossa:BAAALgAECgEJBAAAAA==.Darkclement:BAABLgAECn8gAAIEAAcJQSH8BQAmAgAEAAcJQSH8BQAmAgABLgAFFAMJCQAMAE4TAA==.Darkin:BAAALgAECgcJCAAAAA==.Darkmist:BAAALgADCgUJBQAAAA==.Darksworn:BAAALgAECgYJBwAAAA==.Darkwiz:BAABLgAECn8bAAIZAAkJcgeOggBeAQAZAAkJcgeOggBeAQAAAA==.Darnala:BAAALgAECgMJAwAAAA==.',
De='Deadlydk:BAAALgADCgMJAwAAAA==.Deathbybob:BAABLgAECn8hAAIOAAkJzBvdAwCbAQAOAAkJzBvdAwCbAQAAAA==.Deathgriped:BAAALgAECgUJDgAAAA==.Deeper:BAACLgAFFH8PAAIVAAMJVQPpHQB3AAAVAAMJVQPpHQB3AAAuAAQKfyQAAxUACAkSDME3ADYBABUACAkSDME3ADYBABYAAwlqAXXdACgAAAAA.Deezmoonz:BAAALgADCgYJCQAAAA==.Dementos:BAAALgAECgIJAgAAAA==.Demonetra:BAAALgADCgMJAwABLgAECgcJDAAHAAAAAA==.Demonofwar:BAAALgADCgYJDAABLgAECgYJCAAHAAAAAA==.Devils:BAAALgAECgUJCQAAAA==.Dezzi:BAAALgADCgIJAQAAAA==.Dezzii:BAAALgAECgYJCgAAAA==.',
Di='Dirin:BAAALgAECgUJDQABLgAFFAgJFwAUADkTAA==.Disneymagic:BAAALgADCgUJBwAAAA==.Divacup:BAAALgADCgcJBwAAAA==.',
Dm='Dmaan:BAAALgADCgMJAwAAAA==.Dmfortoepics:BAAALgAECgUJBQAAAA==.',
Do='Doomflower:BAAALgAECgYJEAAAAA==.',
Dr='Dragonpebble:BAAALgADCgYJBgABLgAFFAMJBgAKALQRAA==.Drahalah:BAABLgAECn8eAAIZAAgJXR9uOQAaAgAZAAgJXR9uOQAaAgAAAA==.Drakeji:BAABLgAECn82AAMBAAkJnAwuMgBtAQABAAkJnAwuMgBtAQAaAAQJKAGhPwAxAAAAAA==.Dreamliner:BAAALgAECgYJBgAAAA==.Drezind:BAAALgAECgQJBAAAAA==.Drhealalot:BAAALgAECgEJAQAAAA==.Drugar:BAAALgAFFAIJAgABLgAFFAUJEgAbAHUcAA==.',
Du='Dumparooski:BAAALgAECgEJAQABLgAFFAEJAQAHAAAAAA==.Dumplingg:BAAALgAECggJDAAAAA==.',
Ea='Earthvoodoo:BAAALgAECgYJDwAAAA==.',
Eb='Eberkenezer:BAAALgAECgQJBAAAAA==.Ebonlight:BAAALgADCgkJFgAAAA==.',
Ec='Ecnyw:BAAALgADCgMJAwABLgAECgUJCAAHAAAAAA==.',
Ed='Edence:BAAALgAECgMJAwAAAA==.',
Eh='Ehunter:BAAALgAECgUJDQAAAA==.',
Ei='Eillea:BAAALgADCgQJBAAAAA==.',
El='Elegant:BAAALgAECgkJBwAAAA==.Elspeth:BAAALgAECgIJAgAAAA==.Elsyria:BAAALgADCgIJAgABLgAFFAgJKwAMAF8hAA==.Eluneslight:BAAALgAECgIJBAAAAA==.',
Em='Emmeri:BAAALgAECgQJBwABLgAECggJMQALAPwTAA==.',
En='Ender:BAAALgAECgIJAgAAAA==.',
Ep='Epi:BAABLgAECn8UAAIcAAgJshKxNgDhAAAcAAgJshKxNgDhAAAAAA==.',
Er='Erianis:BAAALgADCgMJAwAAAA==.Erniethemonk:BAAALgAECgYJEAAAAA==.',
Ev='Evianda:BAAALgADCgkJEAAAAA==.',
Ez='Ezale:BAAALgAECgkJEwAAAA==.Ezpz:BAAALgAECgYJEgAAAA==.',
Fa='Falsetto:BAAALgAECgEJAgAAAA==.Fameral:BAAALgAECgEJAwAAAA==.Faramír:BAABLgAECn8fAAMNAAYJRhkrBABSAQANAAYJRhkrBABSAQAMAAEJ5AJHyAEfAAAAAA==.Farrago:BAAALgAECgEJAgAAAA==.Fatébringer:BAAALgAECggJDgABLgAECgcJDgAHAAAAAA==.Fauhna:BAAALgAECgEJAQABLgAFFAIJBgAMACMiAA==.',
Fe='Fennek:BAABLgAECn8XAAIEAAkJ2A6xXACPAQAEAAkJ2A6xXACPAQAAAA==.Feorio:BAAALgADCgEJAQABLgAECgYJEAAHAAAAAA==.',
Fi='Fiønaviolet:BAAALgADCgcJBwAAAA==.',
Fo='Fourth:BAAALgAECgIJAwABLgAECgcJEAAHAAAAAA==.',
Fr='Frayla:BAAALgADCgEJAQAAAA==.',
Fu='Furrywhenwet:BAAALgAFFAEJAQAAAA==.Fuzzyxbutt:BAAALgAECgYJDgAAAA==.',
Fy='Fyaaga:BAAALgAECgQJBAABLgAFFAYJCwAIADsSAA==.',
Ga='Galloc:BAAALgADCgkJEQAAAA==.Garaylo:BAACLgAFFH8rAAIMAAgJXyFdBACgAgAMAAgJXyFdBACgAgAuAAQKfykAAgwACQn1JMACAKwDAAwACQn1JMACAKwDAAAA.Garroar:BAAALgADCgcJCAAAAA==.',
Ge='Geed:BAAALgADCgEJAQAAAA==.Geoffreys:BAAALgAECgIJAwAAAA==.Gewnzilla:BAAALgAECgIJAgAAAA==.',
Gg='Ggxd:BAAALgADCgkJEAAAAA==.',
Gh='Ghosst:BAABLgAECn8jAAIGAAkJtiLuAgAIAwAGAAkJtiLuAgAIAwAAAA==.',
Gi='Gilberticus:BAAALgADCgMJAwABLgAECgkJZQASANIiAA==.Gimlithekind:BAAALgAECgEJAQAAAA==.',
Gl='Glen:BAAALgADCgMJAwAAAA==.',
Gn='Gnobliterate:BAACLgAFFH8FAAMdAAIJjgjCEwB2AAAZAAIJMwjk2QCIAAAdAAIJ/gbCEwB2AAAuAAQKfywABBkACQkzEtJuAIcBABkACQn2D9JuAIcBAB0ABgk1DYodAOEAAA4AAgk1E+IRAFEAAAAA.Gnobolts:BAAALgAECgEJAQAAAA==.Gnobull:BAABLgAECn8mAAQUAAkJhxmiAgDUAQAUAAkJCRmiAgDUAQAVAAgJThc/BACqAQAeAAMJ4AjTOAB2AAAAAA==.Gnochi:BAAALgAECgcJBwAAAA==.Gnudgnimish:BAAALgAFFAIJBAABLgAFFAUJBwAJALkZAA==.',
Go='Goldenblight:BAAALgAECgYJCwAAAA==.Goldenchi:BAAALgAECgEJAQAAAA==.Goldenrage:BAAALgAECgQJBAAAAA==.Goldenshammy:BAAALgAECgEJAQAAAA==.Gomper:BAAALgAECgMJBAAAAA==.Gonforgood:BAAALgADCgYJBgAAAA==.Goonmaxing:BAAALgADCgMJAwAAAA==.Gorilon:BAAALgAECgkJCQAAAA==.',
Gr='Grimclaw:BAAALgADCgYJDgAAAA==.Grimmrot:BAABLgAECn8VAAICAAYJDgjhRAD1AAACAAYJDgjhRAD1AAAAAA==.Grimmz:BAAALgADCggJCQAAAA==.Grizk:BAAALgADCgEJAQAAAA==.',
Gu='Guily:BAAALgAECgEJAQAAAA==.Guttris:BAAALgAECgYJEwAAAA==.',
Gw='Gwaineedk:BAAALgAECgMJBQAAAA==.Gwaineo:BAAALgAECgEJAQAAAA==.',
Ha='Hagridspells:BAAALgAECgEJAQABLgAECgYJDwAHAAAAAA==.Haikusen:BAAALgADCgYJBAABLgAECgYJCAAHAAAAAA==.Halstron:BAACLgAFFH8GAAIMAAIJIyJTfQC8AAAMAAIJIyJTfQC8AAAuAAQKfy4AAwwACQm/IAoQAOYCAAwACQmPIAoQAOYCAA0ABQl7FechAAUBAAAA.Harribel:BAABLgAECn8bAAQOAAgJuwXyRQB2AAAZAAYJ1wNJDwGZAAAOAAQJtwbyRQB2AAAdAAIJ8gHdFgA1AAAAAA==.Harrykeough:BAAALgAECgQJBwAAAA==.Hassan:BAAALgAECgQJBwAAAA==.Haupaa:BAAALgAECggJCAAAAA==.',
He='Heliòs:BAAALgAECgYJCgAAAA==.Hellwár:BAAALgADCgYJBgAAAA==.',
Ho='Hogfu:BAAALgAECgQJBAAAAA==.Hogshock:BAABLgAECn8bAAQfAAkJTRXRJgDcAQAfAAkJTRXRJgDcAQADAAMJXgfMJACLAAARAAEJhA2B4wAoAAAAAA==.Holocharizrd:BAAALgADCgcJCQAAAA==.Holyrequiem:BAAALgAECgUJBgAAAA==.Holyzel:BAAALgAECgkJEgAAAA==.Hotnsassie:BAAALgADCgMJCQAAAA==.Hound:BAAALgADCgUJCAAAAA==.Hoyt:BAAALgADCgcJBwAAAA==.',
Hs='Hsimingjung:BAACLgAFFH8HAAMJAAUJuRnEGQBWAQAJAAUJuRnEGQBWAQASAAEJNQt5RAA2AAAuAAQKfykAAwkACQnLITgHAMMCAAkACQnLITgHAMMCABIABAlFIasmAIEBAAAA.',
Hu='Huh:BAAALgAECgYJDwAAAA==.Humanic:BAAALgAECgIJAwAAAA==.Huntari:BAAALgAECgEJAwAAAA==.',
Hy='Hylie:BAACLgAFFH8SAAIKAAQJyglGNQCyAAAKAAQJyglGNQCyAAAuAAQKfx8AAgoACQnHEFlaALkBAAoACQnHEFlaALkBAAAA.',
['Hè']='Hèlla:BAAALgADCgkJFQAAAA==.',
Ig='Ignisky:BAAALgAECgcJDgABLgAFFAUJEgAbAHUcAA==.',
Il='Illidarie:BAAALgADCgUJCAAAAA==.',
Im='Imadragon:BAAALgAECgEJAgABLgAFFAEJAQAHAAAAAA==.Imsofresh:BAAALgADCgEJAQAAAA==.',
In='Innitchiwa:BAAALgAECgEJAgAAAA==.Inte:BAAALgADCgYJBgAAAA==.Inzi:BAAALgAECgEJAwAAAA==.',
Iv='Ivanyr:BAAALgAFFAEJAQABLgAFFAgJFwAUADkTAA==.',
Iz='Izgin:BAABLgAECn8UAAIFAAYJJhN8ugASAQAFAAYJJhN8ugASAQAAAA==.',
Ja='Jadeyn:BAAALgADCgMJAwAAAA==.Jaime:BAAALgADCgYJCQABLgAECgYJCAAHAAAAAA==.Jalet:BAAALgADCgcJDQAAAA==.Janie:BAAALgADCgUJCAABLgADCgYJBgAHAAAAAA==.Jantar:BAABLgAECn8dAAIWAAkJMxrXFwCIAgAWAAkJMxrXFwCIAgAAAA==.Jasonbjorne:BAAALgAECgEJAQAAAA==.',
Je='Jebbyclipse:BAAALgAECgQJCAAAAA==.Jenzö:BAABLgAECn8cAAIfAAYJMRKvSQAOAQAfAAYJMRKvSQAOAQAAAA==.Jeramya:BAAALgADCgQJBAAAAA==.',
Jo='Joeviben:BAABLgAECn8bAAIMAAgJ/AqqsQAcAQAMAAgJ/AqqsQAcAQAAAA==.Jormungandr:BAAALgADCgYJCgABLgADCgcJBwAHAAAAAA==.',
Ju='Jugsy:BAACLgAFFH8GAAIFAAIJxBWmSQCcAAAFAAIJxBWmSQCcAAAuAAQKfxwAAgUACQniGb0uAF4CAAUACQniGb0uAF4CAAAA.Juliza:BAAALgADCgQJBAAAAA==.Jungfer:BAAALgAECgMJBAAAAA==.',
['Jë']='Jënzo:BAAALgADCggJCAABLgAECgkJHAAfADESAA==.',
Ka='Kaerodora:BAAALgADCgYJBgAAAA==.Kalasan:BAAALgAECgIJAgAAAA==.Kaldread:BAAALgAECgQJBgAAAA==.Kaligo:BAABLgAECn9CAAMfAAkJQBrnFABCAgAfAAkJQBrnFABCAgADAAQJrgSuIgCrAAAAAA==.Kalistus:BAABLgAECn8bAAIQAAkJtwxlWQB7AQAQAAkJtwxlWQB7AQAAAA==.Kallistos:BAAALgAECgEJAQABLgAFFAIJCAAJADMXAA==.Kalygos:BAAALgAECgQJBAABLgAFFAIJCAAJADMXAA==.Karall:BAAALgAECgEJAQAAAA==.Karetha:BAAALgAECgUJCQAAAA==.Katar:BAAALgAECgMJAwAAAA==.Katreset:BAAALgAECgUJCAAAAA==.Kazerath:BAAALgAECgUJBQAAAA==.',
Kd='Kdavid:BAAALgADCgUJCgAAAA==.',
Ke='Kebsy:BAABLgAECn87AAISAAkJPiRbAwAtAwASAAkJPiRbAwAtAwAAAA==.Kegfupanda:BAAALgAFFAEJAQAAAA==.Keleion:BAABLgAECn8nAAIQAAcJzhDhgwAYAQAQAAcJzhDhgwAYAQABLgAECgkJEwAHAAAAAA==.Kelements:BAAALgAFFAEJAQAAAA==.Kelvin:BAAALgAECgQJBAAAAA==.Kelyessada:BAAALgADCgYJBgAAAA==.Kevonjuravis:BAABLgAECn9RAAMJAAgJhRDxAwA0AQAJAAgJoQ/xAwA0AQASAAUJWxCiXQChAAAAAA==.',
Kh='Khalya:BAAALgAECgUJBQAAAA==.Khalyl:BAABLgAECn8WAAIcAAUJJRRnNQDoAAAcAAUJJRRnNQDoAAAAAA==.Khari:BAAALgAECgEJAQAAAA==.Kheart:BAAALgAECgEJAQAAAA==.Kholy:BAAALgADCgYJBgAAAA==.',
Ki='Kiandra:BAAALgADCgkJEAAAAA==.Kidrash:BAAALgADCgcJCAAAAA==.Killah:BAAALgAECgQJBgAAAA==.Kimegh:BAAALgADCgIJAgAAAA==.Kitsunae:BAAALgADCgcJHgAAAA==.',
Kl='Kleredan:BAAALgAECgkJBgAAAA==.',
Ko='Koder:BAACLgAFFH8TAAIBAAYJfhqTHQB0AQABAAYJfhqTHQB0AQAuAAQKfzUABAEACQnnIbEGABIDAAEACQnnIbEGABIDABoABwlXGS8HANABACAAAgkOArJEAEoAAAAA.Kozmoker:BAAALgAECgYJBgAAAA==.',
Kr='Krondys:BAAALgAECgYJBgAAAA==.Krytus:BAAALgAECgEJAgAAAA==.',
Ku='Kungfu:BAAALgADCgQJBAABLgAECgYJDAAHAAAAAA==.Kungpaochik:BAAALgAECgIJAwABLgAFFAEJAQAHAAAAAA==.Kupó:BAAALgADCgUJBQABLgAECgYJDAAHAAAAAA==.',
Ky='Kyakdeath:BAABLgAECn81AAMZAAgJUho7WgC4AQAZAAgJUho7WgC4AQAdAAEJKwlwPAAuAAAAAA==.',
Kz='Kzo:BAABLgAECn8VAAMTAAgJvxuhGwD/AQATAAYJSx6hGwD/AQAhAAgJJQ3+BwA1AQAAAA==.',
La='Lailyre:BAAALgADCgQJBAAAAA==.Larroy:BAAALgAECgEJAQAAAA==.',
Le='Lecker:BAAALgAECgEJAQAAAA==.Legado:BAAALgAECgUJBwAAAA==.Lenalais:BAAALgAECgEJAQAAAA==.Leonitius:BAAALgAECgYJBwAAAA==.Lepaladine:BAAALgADCgYJCgAAAA==.',
Li='Lilbigcow:BAAALgAECgEJAwAAAA==.Lilithxander:BAAALgAECgUJCQAAAA==.Lilshooter:BAAALgAECgIJAwABLgAFFAQJBAAHAAAAAA==.Lizzybordan:BAAALgAECgcJEwAAAA==.',
Ll='Llaaroyy:BAAALgADCgEJAQAAAA==.Llarroii:BAAALgAECgEJAgAAAA==.',
Lo='Lohdek:BAAALgAECgcJAQAAAA==.Lohhangi:BAAALgADCgEJAgAAAA==.Lovar:BAAALgADCgYJBgAAAA==.',
Lu='Lucinick:BAABLgAECn86AAMiAAgJXxYUAwCjAQAiAAgJ6hEUAwCjAQAjAAYJ+BnhCgCFAQAAAA==.Lucy:BAAALgADCgIJAgAAAA==.Luxdiei:BAAALgAECgYJBgAAAA==.Luzziem:BAAALgAECgcJEwAAAA==.',
Ly='Lynx:BAAALgAECgEJBgAAAA==.',
['Lï']='Lïlith:BAAALgAECgkJAQAAAA==.',
Ma='Maeven:BAAALgADCgEJAQAAAA==.Margause:BAAALgAECgIJBAAAAA==.Mariskama:BAABLgAECn8jAAIEAAkJ9wWPcgBbAQAEAAkJ9wWPcgBbAQAAAA==.Marió:BAAALgADCgMJAwAAAA==.Markusthered:BAAALgAECgMJBAAAAA==.Matrimcautho:BAAALgAECgEJAgAAAA==.Mazza:BAAALgAECgkJEQABLgAECgkJGAATAGsYAA==.',
Mc='Mcbong:BAAALgAECgQJBwAAAA==.',
Me='Mello:BAAALgADCgYJBgAAAA==.Meowimabear:BAAALgADCgkJEAABLgAECgkJIwAGALYiAA==.Metal:BAAALgAECgQJDgAAAA==.Method:BAAALgADCgEJAQAAAA==.Meuccí:BAAALgAECgcJCwAAAA==.',
Mh='Mhelora:BAABLgAECn8VAAIWAAYJ3wvgawDxAAAWAAYJ3wvgawDxAAAAAA==.',
Mi='Mikkais:BAAALgAECgYJEwAAAA==.Mikkehunt:BAAALgAECgEJAQAAAA==.Mimacho:BAAALgAFFAEJAQAAAA==.Mindmuncher:BAAALgAECgIJAgAAAA==.Minimini:BAACLgAFFH8bAAIIAAYJFRnBEABsAQAIAAYJFRnBEABsAQAuAAQKfy4AAggACQkJHD0SAI0CAAgACQkJHD0SAI0CAAAA.Minni:BAAALgAFFAEJAwAAAA==.',
Mo='Monkeyfu:BAAALgAECgQJBAABLgAFFAEJAwAHAAAAAA==.Moolin:BAABLgAECn8pAAIeAAkJigmnGwAvAQAeAAkJigmnGwAvAQAAAA==.Moranthe:BAAALgAECgcJDAABLgAFFAYJCwAIADsSAA==.Mordsyth:BAAALgAECgYJCgAAAA==.Morrowind:BAAALgADCgYJBgAAAA==.Mortis:BAAALgADCgYJBgAAAA==.',
Mu='Muggni:BAAALgAECgkJEQAAAA==.Muggypew:BAABLgAECn8UAAIkAAkJRgFkLgBeAAAkAAkJRgFkLgBeAAAAAA==.Munder:BAABLgAECn8mAAMlAAkJgB3XAwBxAgAlAAkJcBzXAwBxAgAKAAgJ/xkqUwCiAQAAAA==.Murdez:BAAALgAECgYJDgAAAA==.Mustymuppet:BAACLgAFFH8bAAIKAAUJmBcDRwA6AQAKAAUJmBcDRwA6AQAuAAQKfygAAwoACAnzGkA3APwBAAoACAnzGkA3APwBABgAAQlnD7VuADgAAAAA.',
My='Myrotheron:BAAALgADCgMJAwAAAA==.Mysticmeat:BAAALgAECgEJAQAAAA==.Mythicalbug:BAAALgADCgEJAQAAAA==.Mythuneran:BAABLgAECn8jAAMFAAkJyhusBgAFAgAmAAkJdhe1AgAeAgAFAAcJjR2sBgAFAgAAAA==.',
['Mø']='Mørzanna:BAAALgAECgYJBwAAAA==.',
Na='Naheka:BAAALgAECggJEgAAAA==.Nanookigaluk:BAAALgADCgYJBgAAAA==.Narrator:BAAALgAECgEJAgAAAA==.Navikz:BAAALgADCgUJBQAAAA==.',
Ne='Nekrose:BAABLgAECn8aAAIZAAgJwiIdIACJAgAZAAgJwiIdIACJAgAAAA==.Nemini:BAABLgAECn8kAAMTAAkJbA+BBQB7AQATAAkJbA+BBQB7AQAhAAEJ7AG0mgAcAAAAAA==.Nena:BAABLgAECn9AAAIVAAkJEhVBCQALAQAVAAkJEhVBCQALAQAAAA==.Nenacurses:BAAALgAECgcJDwABLgAECgkJQAAVABIVAA==.Nenafury:BAAALgADCgMJAwABLgAECgkJQAAVABIVAA==.Nephilia:BAAALgADCgYJBgAAAA==.Newfy:BAAALgAFFAEJAwAAAA==.',
Ni='Ninjamage:BAAALgAECgUJBQAAAA==.Nistis:BAAALgAECgYJEQAAAA==.Niteshroud:BAAALgADCgMJAwAAAA==.Nithendroz:BAABLgAECn8YAAMaAAcJZgoDFgC0AAAaAAQJZgsDFgC0AAABAAMJaAjqgQBaAAAAAA==.Nity:BAAALgAECgQJBAAAAA==.Nivek:BAAALgAECgEJAQAAAA==.',
Nn='Nnivek:BAAALgAECgEJAQAAAA==.',
No='Noctaurus:BAABLgAECn8iAAIZAAkJ1QkbaQCUAQAZAAkJ1QkbaQCUAQAAAA==.Noczorro:BAAALgADCgYJBgAAAA==.Nomadhew:BAAALgAECgcJBwAAAA==.Noraice:BAAALgAECgEJAwAAAA==.Notagain:BAACLgAFFH89AAIMAAkJThxGBABtAgAMAAkJThxGBABtAgAuAAQKfy4AAgwACQkBI5YHAFoDAAwACQkBI5YHAFoDAAAA.Notapally:BAAALgAECgQJBAAAAA==.Noxcorvus:BAAALgAECgcJDQAAAA==.',
Nu='Nuvo:BAAALgADCgYJBgAAAA==.',
Ny='Nylloc:BAAALgAECgkJCQAAAA==.Nymphàdoria:BAAALgAECgEJAQAAAA==.Nyuxx:BAABLgAECn8sAAIRAAgJdRpmAwBeAgARAAgJdRpmAwBeAgAAAA==.',
['Nê']='Nêwfie:BAAALgAECgEJAwABLgAFFAEJAwAHAAAAAA==.',
Oc='Oceanic:BAAALgADCgYJCwAAAA==.Oceans:BAAALgAECgEJAQAAAA==.',
Od='Odphijor:BAAALgAECgkJAQAAAA==.',
Ol='Olenza:BAAALgAECgQJBwAAAA==.Olgreeneyes:BAAALgAECgIJBAAAAA==.',
Or='Orangewhale:BAABLgAECn8UAAIWAAYJChgpTABzAQAWAAYJChgpTABzAQAAAA==.',
Ou='Out:BAAALgAECgYJCwAAAA==.',
Ox='Oxidation:BAAALgADCgcJGgAAAA==.',
Pa='Painspongie:BAAALgADCgQJBQAAAA==.Pallybob:BAAALgAECgQJBAABLgAECgkJIQAOAMwbAA==.Patsajak:BAAALgADCgEJAQAAAA==.Pavo:BAAALgAECgcJCgAAAA==.Paynenecross:BAAALgAECgEJAQAAAA==.',
Pe='Pebbleshifts:BAAALgAECgUJBQAAAA==.Peejean:BAAALgAECgYJBgAAAA==.Peyblade:BAAALgAECgYJBgABLgAECgkJHgAXABghAA==.Peybreak:BAAALgAECgIJAgABLgAECgkJHgAXABghAA==.Peychi:BAAALgAECgUJBgABLgAECgkJHgAXABghAA==.Peycicle:BAABLgAECn8eAAIXAAkJGCFKAQDOAgAXAAkJGCFKAQDOAgAAAA==.Peysanity:BAAALgAECgQJBAABLgAECgkJHgAXABghAA==.Peystruction:BAAALgAECgEJAgABLgAECgkJHgAXABghAA==.Peytan:BAABLgAECn8VAAMQAAkJLxiFIwBCAgAQAAkJLxiFIwBCAgAcAAEJuQmmdgAuAAABLgAECgkJHgAXABghAA==.Peytin:BAAALgAECgQJBAABLgAECgkJHgAXABghAA==.',
Ph='Phantasm:BAAALgADCgQJBwAAAA==.Phemoid:BAAALgADCgkJCQAAAA==.',
Pi='Pinkywhale:BAAALgAFFAIJAgAAAA==.Pippa:BAABLgAECn8rAAIgAAkJEx2lBADeAgAgAAkJEx2lBADeAgAAAA==.Pitythefu:BAAALgADCgcJBQAAAA==.',
Pl='Planett:BAABLgAECn8lAAMRAAkJChyRFwCNAgARAAkJChyRFwCNAgAfAAEJFgOSwQAcAAAAAA==.',
Po='Poetuck:BAABLgAECn8yAAIFAAkJnxQUTgDyAQAFAAkJnxQUTgDyAQAAAA==.Pokeyruler:BAAALgAECgIJAgAAAA==.Pokeythorn:BAAALgADCgkJFwAAAA==.Polkabob:BAAALgAECgMJAwAAAA==.Pookießear:BAAALgADCgUJBQAAAA==.Powdrpufgirl:BAAALgADCgMJAwABLgAECgYJCAAHAAAAAA==.',
Pr='Proko:BAABLgAECn8vAAMRAAkJbxlxCgBuAQARAAcJjBdxCgBuAQAfAAcJ2BLHPgA5AQAAAA==.',
Ps='Psychovoodoo:BAAALgAECgIJBwAAAA==.',
Pu='Publicpool:BAAALgADCgEJAQAAAA==.Purfec:BAAALgADCgcJDAAAAA==.',
['Pü']='Püff:BAAALgADCgQJBAABLgAECgYJDAAHAAAAAA==.',
Qa='Qatka:BAAALgAECgQJBgAAAA==.',
Qu='Quiver:BAABLgAECn8iAAIMAAgJ1Q0uhgBjAQAMAAgJ1Q0uhgBjAQAAAA==.Quizle:BAAALgAECgEJAwAAAA==.',
['Qì']='Qìlen:BAABLgAECn8WAAIOAAcJzgyzMgDRAAAOAAcJzgyzMgDRAAAAAA==.',
Ra='Raein:BAABLgAECn8rAAMRAAkJqyLtAwB9AwARAAkJqyLtAwB9AwAfAAYJnBcQQwAnAQAAAA==.Raginghog:BAAALgAECgUJCAAAAA==.Rainn:BAACLgAFFH8LAAMPAAQJ4w/MEQDMAAAPAAQJ4w/MEQDMAAAMAAEJ6AExywA1AAAuAAQKfxcABA8ACAkGFdEbACUCAA8ACAkGFdEbACUCAA0ABAmuBZ41AG4AAAwAAQlGBLXEASEAAAAA.Rainnsoul:BAAALgAECgYJDgAAAA==.Rainnspow:BAAALgAFFAIJAgAAAA==.Rakkclaw:BAAALgAECgEJAQABLgAECgEJAQAHAAAAAA==.Ralofurius:BAAALgAECgYJDAAAAA==.Rasril:BAAALgAFFAEJAQAAAA==.Ratched:BAAALgADCgMJAwAAAA==.Raze:BAAALgAECgIJBgAAAA==.',
Re='Red:BAAALgADCgcJEgAAAA==.Redrighthand:BAAALgADCgEJAQAAAA==.Renicus:BAAALgADCgYJCAAAAA==.Renmare:BAABLgAECn8WAAILAAUJOhfLVAD5AAALAAUJOhfLVAD5AAAAAA==.Renmore:BAABLgAECn8VAAIMAAgJMBELdgCCAQAMAAgJMBELdgCCAQAAAA==.Rennzo:BAAALgADCggJDAAAAA==.Reshtargorr:BAAALgAECgEJAwAAAA==.Reze:BAAALgAECgEJAQAAAA==.',
Rg='Rgbpanda:BAAALgAECgQJBQAAAA==.',
Rh='Rhandoom:BAAALgADCgQJBAAAAA==.',
Ri='Ricky:BAAALgAECgEJAQAAAA==.Rikeji:BAAALgAECgkJEgAAAA==.Risotto:BAAALgAECgQJBwAAAA==.Riumi:BAAALgAECgMJCQAAAA==.Rivenxi:BAAALgAECgEJAQABLgAECgcJDAAHAAAAAA==.',
Ro='Rocksolid:BAAALgAECgEJAgAAAA==.Ronaspreader:BAAALgAECgYJAwAAAA==.Roskolnikov:BAAALgAECgUJEAAAAA==.',
Ru='Rubymoonbeam:BAABLgAECn8mAAIEAAcJDw7FegBKAQAEAAcJDw7FegBKAQAAAA==.Ruele:BAACLgAFFH8LAAIIAAYJOxLBHQCCAQAIAAYJOxLBHQCCAQAuAAQKfxwAAggACQnyH2gNAMUCAAgACQnyH2gNAMUCAAAA.Ruenan:BAABLgAECn8xAAMEAAkJxyaSAQB/AwAEAAkJxyaSAQB/AwAkAAMJlhKzaACcAAAAAA==.Ruma:BAAALgAECgQJBAAAAA==.',
Ry='Ryain:BAABLgAECn85AAMVAAkJtg+2LABzAQAVAAkJ9Q22LABzAQAUAAcJnw+lKgAIAQAAAA==.Ryian:BAAALgAECgQJBAAAAA==.',
['Rä']='Räinns:BAABLgAECn8YAAIUAAcJNgo/GAD0AAAUAAcJNgo/GAD0AAAAAA==.',
Sa='Saintstephen:BAAALgADCggJGQAAAA==.Santajr:BAABLgAECn8eAAInAAYJsAMdOgCMAAAnAAYJsAMdOgCMAAAAAA==.Sapthat:BAABLgAECn8bAAMoAAcJwyH7AwDqAQAoAAYJAyT7AwDqAQAjAAMJXBrkEQDnAAAAAA==.Sarahlina:BAAALgADCgcJBwAAAA==.Sarthrity:BAABLgAECn8aAAIFAAYJNwmi0QDvAAAFAAYJNwmi0QDvAAAAAA==.Satyrs:BAAALgAECgEJAQAAAA==.Savemeh:BAAALgAECgEJAQAAAA==.Savepebble:BAACLgAFFH8GAAIKAAMJtBGoLwDGAAAKAAMJtBGoLwDGAAAuAAQKfx8AAwoACQkzFLtoAGsBAAoACAntD7toAGsBABgABQlfF8weALMAAAAA.',
Sc='Scalesofdoom:BAAALgAECgEJAgAAAA==.',
Se='Seather:BAABLgAECn8cAAIiAAgJ4BvDEwB4AgAiAAgJ4BvDEwB4AgAAAA==.Seirin:BAABLgAECn8rAAITAAkJbxMEFwAXAgATAAkJbxMEFwAXAgAAAA==.Seldiane:BAAALgAECgYJCgAAAA==.Selendaa:BAAALgAECgUJEQAAAA==.Senadarra:BAACLgAFFH8jAAIkAAcJ6hcEDgB+AQAkAAcJ6hcEDgB+AQAuAAQKfzcAAiQACQkeIfICALECACQACQkeIfICALECAAAA.Senastera:BAAALgADCgcJCQAAAA==.Sephenroth:BAAALgAECgQJBwAAAA==.Sephiroot:BAAALgADCgIJAgAAAA==.Sephron:BAABLgAECn8YAAICAAkJAhLuFQAqAgACAAkJAhLuFQAqAgAAAA==.Serendipity:BAAALgAECgcJBwABLgAECggJFAAcALISAA==.Serqet:BAABLgAECn8uAAQQAAgJXhZiOwDaAQAQAAgJMBViOwDaAQAcAAQJHhbHDQChAAApAAYJGgV2BwBxAAAAAA==.Sethen:BAAALgAECgEJAQAAAA==.',
Sh='Shadowhawke:BAAALgADCggJCAAAAA==.Shadowofdoom:BAAALgAECgEJAQAAAA==.Shammology:BAABLgAECn8WAAIRAAcJPRJaTQB7AQARAAcJPRJaTQB7AQAAAA==.Shaollyn:BAAALgAECgYJDAAAAA==.Sheri:BAABLgAECn8XAAIXAAkJPhzcAQBpAgAXAAkJPhzcAQBpAgAAAA==.Shizam:BAAALgAECgUJBQAAAA==.Shizzi:BAAALgAECgQJBgAAAA==.Sho:BAAALgAECgEJAgAAAA==.Shotowkhaan:BAABLgAECn8fAAMWAAkJPRNkRgB2AQAWAAkJPRNkRgB2AQAVAAEJaAIkqgAUAAAAAA==.Shotowkhann:BAAALgAECgIJAgAAAA==.Shoyoh:BAAALgAECgQJCQAAAA==.Shízu:BAAALgAECgUJBQAAAA==.',
Si='Sikachu:BAAALgAECgEJAgABLgAECgcJFAAJAN4cAA==.Sillygoose:BAACLgAFFH8oAAIFAAkJgBHuFgA8AgAFAAkJgBHuFgA8AgAuAAQKfyQAAgUACQlJIJEVACcDAAUACQlJIJEVACcDAAAA.Sinadara:BAAALgAECgYJEAAAAA==.Sinïster:BAAALgADCgEJAQABLgAECgYJEAAHAAAAAA==.Siong:BAAALgADCgcJCgABLgAFFAgJKwAMAF8hAA==.Siorknav:BAABLgAECn8fAAIMAAgJiQ6IqQApAQAMAAgJiQ6IqQApAQAAAA==.',
Sk='Skalar:BAABLgAECn85AAILAAkJJxGuBQCAAQALAAkJJxGuBQCAAQAAAA==.Skipali:BAAALgAECgIJAwAAAA==.Skodah:BAAALgAECgEJAQABLgAECgYJEAAHAAAAAA==.Skodoh:BAAALgAECgEJAQABLgAECgYJEAAHAAAAAA==.',
Sl='Slaydh:BAAALgAECgEJAQAAAA==.Släyr:BAAALgAECgMJBQAAAA==.',
So='Solunara:BAAALgADCgcJFgAAAA==.Somnambula:BAAALgADCgQJBAAAAA==.Sonadoria:BAABLgAECn8aAAIZAAgJ9w24dQB4AQAZAAgJ9w24dQB4AQAAAA==.Sorrenda:BAAALgADCgkJDwAAAA==.Soup:BAABLgAECn8nAAIeAAkJ/g3QEgCPAQAeAAkJ/g3QEgCPAQAAAA==.',
Sp='Sparow:BAAALgAECgEJAQAAAA==.Spinetarak:BAAALgADCgMJAwAAAA==.',
Sq='Squarey:BAAALgAECgkJEwAAAA==.',
St='Stabbie:BAABLgAECn8XAAIiAAkJdRk8FQD2AQAiAAkJdRk8FQD2AQAAAA==.Stamina:BAAALgADCggJEAAAAA==.Stell:BAAALgAECgYJBwAAAA==.Stinch:BAAALgAECgEJAQABLgAFFAEJAQAHAAAAAA==.Stkawli:BAAALgAECgMJAwAAAA==.Stovik:BAACLgAFFH8IAAMDAAMJDxfNCADDAAADAAMJDxfNCADDAAARAAEJTgoNgAA7AAAuAAQKfy4AAwMACQl1IRgEALYCAAMACQl1IRgEALYCABEABwnREd5IAIsBAAAA.',
Sv='Sventhebrave:BAAALgAECgkJEgAAAA==.',
Sw='Sweeneytod:BAAALgAECgIJCQAAAA==.Sweetpally:BAAALgADCgcJDAAAAA==.',
Sy='Sykill:BAAALgAECgUJCQAAAA==.Sylira:BAACLgAFFH8QAAMTAAYJ5xGpDQBxAQATAAYJ5xGpDQBxAQACAAEJMAAnVQARAAAuAAQKfzgAAxMACQmUIggIAOwCABMACQmUIggIAOwCACEAAwkWDo1mAIIAAAAA.Sylk:BAAALgAECgUJBQABLgAECgYJEAAHAAAAAA==.',
['Sö']='Söl:BAAALgAECgQJBAAAAA==.',
Ta='Taintedfel:BAAALgADCgkJCAAAAA==.Takamura:BAAALgAECgcJBwAAAA==.Takedown:BAACLgAFFH8SAAIbAAUJdRyMAwANAQAbAAUJdRyMAwANAQAuAAQKfywAAxsACQlhJHwCACIDABsACQlhJHwCACIDAAsABwkrGsUsAAECAAAA.Talena:BAAALgAECgcJBwAAAA==.Talleral:BAABLgAECn8dAAMCAAkJthbkDgCBAgACAAkJthbkDgCBAgATAAEJ2BBNfwAzAAAAAA==.Tallyn:BAAALgAECgEJAQAAAA==.Tamanan:BAAALgAECgYJCwABLgAFFAIJCAABAA4DAA==.Tankie:BAAALgADCgEJAQAAAA==.Taurgrim:BAAALgADCgUJCQAAAA==.Tavin:BAAALgAFFAEJAQAAAA==.Tazrav:BAAALgAECgMJAwAAAA==.',
Te='Temamañ:BAABLgAFFH8IAAIBAAIJDgOjMABOAAABAAIJDgOjMABOAAAAAA==.Terasha:BAAALgAECgkJCQAAAA==.',
Th='Thalid:BAAALgAECgEJAgAAAA==.Tharonix:BAAALgAECgYJEwAAAA==.Thelitch:BAAALgADCgEJAgAAAA==.Theredpanda:BAAALgAECgUJBQAAAA==.Thewarden:BAAALgAECgIJAgAAAA==.Thunderfist:BAAALgADCgEJAQAAAA==.',
Ti='Tic:BAAALgAECgYJBgAAAA==.Tigerwang:BAAALgAECgQJCAAAAA==.Tigrasia:BAAALgADCgYJCwAAAA==.Timaeus:BAACLgAFFH8JAAIFAAMJwg0eQAC9AAAFAAMJwg0eQAC9AAAuAAQKfz4AAgUACQkPIFscALICAAUACQkPIFscALICAAAA.Tinder:BAAALgADCgUJBQABLgAECgYJCAAHAAAAAA==.Tinkkster:BAAALgAECgEJAwAAAA==.',
Tm='Tmbeesknees:BAAALgAECgEJAQAAAA==.',
To='Touch:BAABLgAECn8WAAMhAAYJjw8LRQD6AAAhAAYJjw8LRQD6AAACAAEJ/QlffwAtAAAAAA==.Touchofkarma:BAAALgADCgcJFAAAAA==.',
Tr='Trifflinhoes:BAAALgAECgUJEAAAAA==.Trishi:BAAALgAECgYJBwAAAA==.Tristtan:BAAALgAECgEJAQAAAA==.Trytoheal:BAAALgAECgIJAwAAAA==.Trôjan:BAAALgAECgYJBgAAAA==.',
Ts='Tsuku:BAAALgAECgUJBQAAAA==.',
Tu='Turningblue:BAAALgADCgUJBAAAAA==.Tusktilldawn:BAABLgAECn8VAAMOAAgJ5RCBGwCAAQAOAAgJzRCBGwCAAQAdAAIJ2wTnNgBBAAAAAA==.',
Tw='Twohoof:BAAALgADCgkJFQAAAA==.',
Ty='Tydrinor:BAAALgAECgcJAQAAAA==.',
['Tä']='Tänithðurden:BAAALgADCggJDgAAAA==.',
Ug='Ugin:BAAALgAECgUJBgAAAA==.',
Un='Unobasho:BAAALgAECgMJAwABLgAFFAQJDQABAH0PAA==.Unoboxo:BAAALgADCgEJAQABLgAFFAQJDQABAH0PAA==.Unoo:BAAALgADCgEJAQAAAA==.Unovoke:BAACLgAFFH8NAAIBAAQJfQ8qNQDuAAABAAQJfQ8qNQDuAAAuAAQKfzUAAgEACQkrHUcSAFACAAEACQkrHUcSAFACAAAA.',
Va='Valeena:BAAALgADCgEJAQABLgAECgQJBAAHAAAAAA==.Valorash:BAACLgAFFH8FAAIMAAIJgBr0hwCjAAAMAAIJgBr0hwCjAAAuAAQKfzsAAwwACQkIImQMAAIDAAwACQkIImQMAAIDAA0ABgnKG7gPAMkBAAAA.Valorious:BAAALgAECgUJCwAAAA==.Vandaira:BAAALgAECgkJAgAAAA==.Vasillisa:BAAALgAECgMJBQAAAA==.',
Ve='Vearick:BAAALgADCgYJCgAAAA==.Veleyna:BAAALgADCgcJCwAAAA==.Velgryn:BAAALgAECgUJBAAAAA==.Velintha:BAAALgAECgcJCAAAAA==.Venatrix:BAAALgAECgYJEQAAAA==.Vendrith:BAAALgADCgcJBwAAAA==.Veraxi:BAAALgADCgYJCwABLgAFFAgJFwAUADkTAA==.',
Vi='Vidascare:BAAALgAECgkJAgAAAA==.Vidu:BAAALgADCgUJBQAAAA==.Vision:BAABLgAFFH8FAAIMAAMJtw8ZNgC4AAAMAAMJtw8ZNgC4AAAAAA==.',
Vl='Vluthier:BAAALgADCgYJBgAAAA==.',
Vo='Voidshatter:BAABLgAECn8bAAMcAAcJYgi8NgDgAAAcAAcJYgi8NgDgAAAQAAYJcQIO7gBhAAAAAA==.Vonderick:BAAALgAECgQJAwAAAA==.Voodoodog:BAAALgAECgMJBQABLgAECgYJDwAHAAAAAA==.',
Vu='Vulgrimm:BAAALgAECgUJBQAAAA==.',
Vy='Vynlorellas:BAAALgAECgEJAgAAAA==.Vyéra:BAAALgADCgMJBgAAAA==.',
['Vè']='Vèsper:BAAALgAECgMJBQABLgAECgMJCQAHAAAAAA==.',
['Vô']='Vôha:BAAALgAECgEJAQAAAA==.',
Wa='Wakawli:BAAALgADCgYJBgAAAA==.Walex:BAAALgAECgkJBwAAAA==.Wally:BAAALgADCgMJAwAAAA==.Wardmneagle:BAAALgADCgUJCgAAAA==.Wargasm:BAAALgAECgQJBwABLgAECgcJEwAHAAAAAA==.Wars:BAAALgAECgYJCQAAAA==.Watongo:BAAALgAECgUJBwAAAA==.Watsaheal:BAAALgAECgYJCQAAAA==.',
Wi='Wildborn:BAAALgADCgMJAwAAAA==.Willidan:BAAALgADCgEJAQAAAA==.Winwood:BAAALgADCgUJBwAAAA==.Withdrawals:BAAALgADCgYJBgABLgAECgMJCQAHAAAAAA==.',
Wo='Woeify:BAABLgAECn8VAAIDAAcJ5xSuDgDRAQADAAcJ5xSuDgDRAQAAAA==.',
Wr='Wreckless:BAAALgAECggJCAABLgAFFAYJIQAjAAIdAA==.',
Wy='Wynce:BAAALgAECgUJCAAAAA==.',
Xa='Xalana:BAAALgADCgQJBAAAAA==.Xandaer:BAAALgAECgcJCwAAAA==.Xarn:BAABLgAECn8hAAIKAAkJtwdvagCOAQAKAAkJtwdvagCOAQAAAA==.',
Xc='Xcïte:BAABLgAECn8bAAQhAAgJwBo1JwCUAQAhAAYJ9hw1JwCUAQACAAcJPBk7CQA0AQATAAMJ3RtaWADUAAAAAA==.',
Xe='Xenroz:BAAALgADCgcJBwAAAA==.',
Ya='Yaader:BAAALgADCgUJBQAAAA==.Yagudo:BAAALgADCgEJAQAAAA==.Yandòur:BAAALgADCgIJAgABLgAECgkJGgAYAIkPAA==.',
Ye='Yemon:BAAALgAECgUJBQAAAA==.',
Yo='Yodä:BAAALgADCgcJBwAAAA==.Yourlock:BAAALgADCgUJBQAAAA==.',
Yr='Yrelya:BAAALgAECgYJCQAAAA==.',
Yu='Yuji:BAACLgAFFH8LAAIMAAMJjAjVfgC4AAAMAAMJjAjVfgC4AAAuAAQKf1YAAgwACQluGKEyADYCAAwACQluGKEyADYCAAAA.',
Za='Zalectra:BAACLgAFFH8WAAIGAAQJHiEsDABkAQAGAAQJHiEsDABkAQAuAAQKfz4AAwYACQm2JUIAAMUDAAYACQm2JUIAAMUDACQAAgmhFhkqAG0AAAAA.',
Ze='Ze:BAAALgAECgYJDAAAAA==.Zelila:BAAALgAECgUJBAAAAA==.Zephyruss:BAAALgADCgMJAwAAAA==.',
Zo='Zoei:BAAALgAECgQJBAAAAA==.',
['Zü']='Zügzüg:BAAALgADCgEJAQAAAA==.',
['Âu']='Âurâ:BAAALgAECgUJBwAAAA==.',
['Ål']='Ålloria:BAABLgAECn8ZAAIcAAgJQRnvEwDzAQAcAAgJQRnvEwDzAQAAAA==.',
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
