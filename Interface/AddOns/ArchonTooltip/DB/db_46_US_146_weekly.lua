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

local lookup = {'Warrior-Fury','DeathKnight-Unholy','Monk-Mistweaver','Priest-Holy','Paladin-Retribution','DemonHunter-Devourer','Unknown-Unknown','Hunter-Survival','Paladin-Holy','Druid-Balance','DeathKnight-Frost','Warlock-Affliction','Evoker-Preservation','Evoker-Devastation','DemonHunter-Havoc','Mage-Frost','Priest-Shadow','Warlock-Demonology','Warlock-Destruction','Druid-Feral','DeathKnight-Blood','Rogue-Assassination','Druid-Guardian','Monk-Windwalker','Warrior-Protection','DemonHunter-Vengeance','Shaman-Enhancement','Rogue-Subtlety','Hunter-BeastMastery','Shaman-Restoration','Shaman-Elemental','Paladin-Protection','Priest-Discipline','Druid-Restoration','Hunter-Marksmanship','Evoker-Augmentation','Monk-Brewmaster','Rogue-Outlaw','Mage-Arcane','Warrior-Arms',}
local provider = {region='US',realm='Madoran',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aarhus:BAAALgAECgQJBQAAAA==.Aaronmourne:BAAALgAECgQJBAABLgAECgkJGAABALYJAA==.Aaronyates:BAAALgADCgcJBwABLgAECgkJFwACABcgAA==.',
Ac='Actualegirl:BAABLgAFFH8GAAIDAAUJLQSoNADMAAADAAUJLQSoNADMAAABLgAFFAUJDQAEAAUXAA==.',
Ad='Adversary:BAAALgADCgMJAwAAAA==.',
Ae='Aerfen:BAABLgAECn8cAAIFAAkJyg3VZgCfAQAFAAkJyg3VZgCfAQAAAA==.',
Ag='Agross:BAAALgADCgYJBgAAAA==.',
Ai='Aimforhead:BAAALgAECgcJDAAAAA==.',
Al='Alexas:BAAALgADCgcJCAAAAA==.Alric:BAABLgAECn80AAIGAAkJYxSDNADxAQAGAAkJYxSDNADxAQAAAA==.Alyndra:BAAALgADCgUJBQABLgAECgUJBQAHAAAAAA==.',
Am='Amideus:BAAALgAECgEJAQAAAA==.Amory:BAABLgAECn8mAAICAAkJ9x6xIACEAgACAAkJ9x6xIACEAgAAAA==.',
An='Angela:BAAALgADCgIJAgAAAA==.Annaesthetic:BAAALgAECgEJAwABLgAECggJLwAIAGEVAA==.',
Ar='Arator:BAAALgADCgEJAgAAAA==.Araña:BAAALgAECgEJAQAAAA==.Arcatraz:BAAALgAECgEJAQAAAA==.Ardaddy:BAAALgAECgYJDQABLgAFFAMJBAAHAAAAAA==.Ardzak:BAAALgAFFAMJBAAAAA==.Arragorn:BAACLgAFFH8IAAIJAAQJFRmPHgAiAQAJAAQJFRmPHgAiAQAuAAQKfycAAgkACQktHFUZADoCAAkACQktHFUZADoCAAAA.',
As='Asendra:BAABLgAECn8mAAIKAAkJ6xlCEQBOAgAKAAkJ6xlCEQBOAgAAAA==.Assaran:BAAALgAECgIJAgAAAA==.Astal:BAACLgAFFH8LAAILAAUJlA8pDwAYAQALAAUJlA8pDwAYAQAuAAQKfx0AAgsACQmfG9AGADECAAsACQmfG9AGADECAAAA.',
At='Athenea:BAABLgAECn8aAAIBAAcJUBsoHwD0AQABAAcJUBsoHwD0AQAAAA==.Atulru:BAAALgADCgMJAwAAAA==.',
Av='Avyl:BAAALgADCgcJBwABLgAECgYJGwAMAPsRAA==.',
Az='Azriella:BAAALgAECgcJAwAAAA==.Azuren:BAABLgAECn8pAAMNAAkJgwdVGABKAQANAAkJgwdVGABKAQAOAAYJkwzzEgDWAAAAAA==.',
Ba='Baal:BAAALgAFFAIJAgAAAA==.Bacon:BAABLgAECn9AAAMPAAkJCyQcBQDvAgAPAAkJCyQcBQDvAgAGAAcJ8hfVRwCrAQAAAA==.Bamboozled:BAAALgAFFAEJAQAAAA==.Bandìt:BAAALgAECggJCwAAAA==.Bankai:BAAALgAFFAEJBAAAAA==.Barbieque:BAAALgADCgcJBwAAAA==.',
Be='Bearyden:BAAALgADCgEJAQAAAA==.Bedbugs:BAAALgAECgQJBAABLgAFFAUJHwAQAI0eAA==.Beefstrasz:BAABLgAECn8aAAMEAAgJuRcNFAA0AgAEAAgJuRcNFAA0AgARAAEJpwYWkAAoAAAAAA==.Beyla:BAACLgAFFH8GAAIFAAMJQQoudgDCAAAFAAMJQQoudgDCAAAuAAQKfycAAgUACQkFFwQ0AC4CAAUACQkFFwQ0AC4CAAAA.',
Bi='Bioactive:BAAALgADCgYJBgAAAA==.Bishamon:BAABLgAECn9MAAQSAAkJ+yHwBQBeAwASAAkJ+yHwBQBeAwATAAEJAADAaQA+AAAMAAEJAADlMQA6AAAAAA==.Bizotch:BAAALgAECggJDgAAAA==.',
Bl='Bleau:BAABLgAECn8iAAIUAAkJbxBVEACsAQAUAAkJbxBVEACsAQAAAA==.Blethings:BAAALgAECgMJAwAAAA==.Blinktwice:BAAALgAECgEJAgAAAA==.Bloodimess:BAAALgADCgMJAwAAAA==.Bloodymary:BAABLgAECn8nAAIVAAkJOhWNEwDXAQAVAAkJOhWNEwDXAQAAAA==.Bluebarrie:BAAALgAECgEJAQAAAA==.Blôodräge:BAAALgAECgcJDgAAAA==.',
Bo='Bouncybean:BAAALgADCgIJAgAAAA==.',
Br='Bradsupinya:BAABLgAECn8kAAIQAAgJEBnwXADFAQAQAAgJEBnwXADFAQAAAA==.Branchling:BAAALgAECgcJEgABLgAFFAUJHwAQAI0eAA==.Brewswane:BAAALgAFFAEJAwABLgAFFAcJJAAWAGoWAA==.Bridh:BAABLgAECn8aAAIGAAkJFR5LEQD0AgAGAAkJFR5LEQD0AgABLgAFFAcJHgATAOYdAA==.Bromm:BAAALgAECgEJAQAAAA==.Brunor:BAAALgAECgkJBAAAAA==.',
Bu='Bulkamania:BAAALgAECgMJAwAAAA==.Butterkip:BAACLgAFFH8PAAIRAAUJfBTIFQAwAQARAAUJfBTIFQAwAQAuAAQKfysAAhEACQlpHikKAOACABEACQlpHikKAOACAAAA.',
['Bë']='Bëarclaw:BAAALgAECgUJBQAAAA==.',
Ca='Cambria:BAAALgAECgMJAwAAAA==.Cantkillme:BAAALgAECgQJBwAAAA==.Canukillme:BAAALgADCgYJBgAAAA==.Carruel:BAAALgADCgUJBQAAAA==.Cazzc:BAAALgAECgUJCAAAAA==.',
Ce='Cellan:BAABLgAECn8WAAICAAcJ6wqsugACAQACAAcJ6wqsugACAQAAAA==.',
Ch='Chicharrones:BAAALgAECgUJBQABLgAECgkJQAAPAAskAA==.Chickenshift:BAABLgAECn8iAAMXAAgJRCCgDAATAgAXAAcJJR+gDAATAgAUAAQJ4RgkHAAkAQAAAA==.Chipahoy:BAABLgAECn8nAAIFAAgJdRwuNwAiAgAFAAgJdRwuNwAiAgABLgAECggJRAAQAJwfAA==.Chopahoe:BAAALgAECgQJBwAAAA==.Chuggz:BAABLgAECn8gAAIYAAkJ5xGyHgCzAQAYAAkJ5xGyHgCzAQAAAA==.',
Cl='Clamadin:BAAALgAECgIJAgABLgAFFAgJJQAQAKccAA==.Clamius:BAACLgAFFH8lAAIQAAgJpxyvCgCXAgAQAAgJpxyvCgCXAgAuAAQKfyoAAhAACQkkJbUKACEDABAACQkkJbUKACEDAAAA.Cliff:BAAALgAECgUJBgAAAA==.',
Co='Colby:BAAALgAECgYJDgAAAA==.Coldass:BAABLgAECn8ZAAIQAAgJwRICZQCxAQAQAAgJwRICZQCxAQAAAA==.Commodus:BAAALgADCgQJBAAAAA==.Conduit:BAAALgAECgMJBAAAAA==.Coombrain:BAAALgAECgUJCQAAAA==.Cotopla:BAAALgAECgQJDAAAAA==.',
Cr='Critterzz:BAABLgAECn8aAAIEAAgJ4hb6FwAcAgAEAAgJ4hb6FwAcAgAAAA==.Cryptkeys:BAAALgAECgMJAwAAAA==.',
Cu='Cuziseeu:BAAALgAECgQJBAABLgAECgYJBgAHAAAAAA==.',
Da='Dachyy:BAAALgAECgYJEgAAAA==.Daemonwaters:BAAALgAECgEJAQAAAA==.Dagov:BAAALgAECgYJCAAAAA==.Daiana:BAAALgAECgIJAgAAAA==.Damage:BAAALgAFFAEJAQAAAA==.Darkråii:BAAALgAECgIJAwAAAA==.Dashboy:BAAALgADCgEJAQAAAA==.',
De='Deafniteelf:BAAALgAECgkJDQAAAA==.Deatharmonic:BAAALgAECgUJBQAAAA==.Deathlentlez:BAABLgAECn8vAAIZAAkJZR8OBwCTAgAZAAkJZR8OBwCTAgAAAA==.Decaylentlez:BAAALgAECgEJAQABLgAECgkJLwAZAGUfAA==.Deepwinter:BAAALgAECgcJDQABLgAECgkJFwACABcgAA==.Delphyne:BAABLgAECn8UAAIOAAYJ9wuhEQDrAAAOAAYJ9wuhEQDrAAAAAA==.Demonhunter:BAABLgAECn8gAAIPAAkJuhhNDgA9AgAPAAkJuhhNDgA9AgAAAA==.Demonià:BAABLgAECn8WAAIQAAgJaQYcpwAsAQAQAAgJaQYcpwAsAQAAAA==.Desong:BAAALgADCgYJBwAAAA==.Detharbinger:BAAALgAECgcJDQAAAA==.Dezzan:BAAALgADCgQJBwAAAA==.',
Di='Diamondsword:BAAALgAECggJDgAAAA==.Dieanah:BAAALgADCgcJBwAAAA==.',
Do='Dochaze:BAABLgAECn8qAAMJAAkJfxyHHwAdAgAJAAgJPB+HHwAdAgAFAAMJjA1BHAGTAAAAAA==.Dogdimmadome:BAAALgAECgYJDwAAAA==.Dolore:BAAALgADCgcJBgAAAA==.Doublejump:BAAALgAECgEJAQABLgAECgkJJwAVADoVAA==.',
Dr='Dragone:BAAALgAECgUJCQAAAA==.Dragun:BAAALgADCgUJBQABLgAECggJGQAFACMQAA==.',
Du='Dumbdumb:BAAALgAECgQJBgAAAA==.',
Dy='Dyanuh:BAABLgAECn8bAAIRAAYJIQIRaAB3AAARAAYJIQIRaAB3AAAAAA==.',
['Dà']='Dàrkscythe:BAABLgAECn8cAAMVAAcJmAX8OgCjAAAVAAcJuQT8OgCjAAALAAEJiQYBPgAoAAAAAA==.',
Ea='Eazywin:BAAALgAECggJCQAAAA==.',
Eh='Ehlsa:BAAALgADCgcJBwAAAA==.Ehlsi:BAABLgAECn8vAAIaAAkJUR/DAgDFAgAaAAkJUR/DAgDFAgAAAA==.Ehress:BAAALgAECgcJEwABLgAECgkJFwACABcgAA==.',
Ei='Eirinny:BAABLgAECn8tAAIbAAkJWQpMEwB+AQAbAAkJWQpMEwB+AQAAAA==.',
El='Elindez:BAABLgAECn8nAAIcAAkJUw8FGADXAQAcAAkJUw8FGADXAQAAAA==.Elyviel:BAAALgAFFAEJAQAAAA==.Elàine:BAABLgAECn8sAAIdAAgJmAhcdgBOAQAdAAgJmAhcdgBOAQAAAA==.',
Em='Emika:BAAALgADCgUJDgAAAA==.Emyrson:BAAALgAECgQJCQAAAA==.',
En='Enemywithin:BAAALgADCgIJAgAAAA==.Enzo:BAAALgADCgYJCwAAAA==.',
Ep='Epicfury:BAAALgAECgYJDgAAAA==.',
Eq='Eq:BAAALgADCgUJBgAAAA==.',
Ez='Ezmee:BAAALgAECgUJDgAAAA==.',
Fa='Facingworlds:BAAALgAECggJDgAAAA==.Fathercaleb:BAAALgAECgIJAwABLgAFFAUJHgAYAMUgAA==.Fazed:BAAALgAECgIJBgAAAA==.Fazeo:BAAALgAECgIJAgAAAA==.',
Fe='Featherstep:BAAALgADCgMJAwAAAA==.Felysse:BAAALgADCgEJAQAAAA==.',
Fi='Fireball:BAAALgAECgIJAgABLgAFFAEJAQAHAAAAAA==.',
Fl='Flavio:BAAALgAECgQJCAAAAA==.',
Fo='Fortuna:BAABLgAECn8kAAIbAAkJxAT+GAA5AQAbAAkJxAT+GAA5AQAAAA==.',
Fr='Francesca:BAAALgADCgEJAQAAAA==.Frosilen:BAABLgAECn87AAMeAAkJCxDVQACmAQAeAAkJCxDVQACmAQAfAAMJaQvpeAB+AAAAAA==.Frostbite:BAAALgADCgIJAgAAAA==.',
Ga='Gamaikuba:BAAALgADCggJCQAAAA==.Gamarth:BAAALgAECgYJDQAAAA==.Gatlu:BAABLgAECn8hAAIXAAkJcBbqDAAOAgAXAAkJcBbqDAAOAgAAAA==.Gato:BAAALgADCgIJAgAAAA==.Gawdsmackk:BAAALgAECgcJDQAAAA==.Gaz:BAAALgADCgMJAwAAAA==.Gazokks:BAAALgADCgcJBwAAAA==.',
Ge='Gedank:BAAALgADCgcJBwAAAA==.Geodemon:BAAALgAECgQJBAAAAA==.Gethealed:BAAALgAECgcJEAAAAA==.Getrektpos:BAAALgADCgMJAwAAAA==.',
Gh='Ghostlock:BAABLgAECn8VAAIMAAgJzxn2BQAFAgAMAAgJzxn2BQAFAgAAAA==.Ghoztface:BAABLgAECn8oAAMgAAcJcxzHDgDYAQAgAAYJXCDHDgDYAQAFAAcJJxL2mABAAQAAAA==.Ghöstbeef:BAAALgADCgkJEAABLgAECggJGgAEALkXAA==.',
Gi='Giblock:BAABLgAECn8XAAIMAAgJCBTdDgBpAQAMAAgJCBTdDgBpAQAAAA==.',
Gl='Glamour:BAAALgAECgQJEAAAAA==.Glitterboy:BAAALgAECgIJAgABLgAFFAgJIwAYACIfAA==.',
Go='Golomojek:BAAALgAECggJEwAAAA==.Gorkun:BAAALgADCgkJDgAAAA==.Gov:BAACLgAFFH8WAAMPAAUJAR/PDwAiAQAGAAUJCR38OQA2AQAPAAUJfhXPDwAiAQAuAAQKfygAAwYACQm/JYsIAEUDAAYACQm/JYsIAEUDAA8AAQlSEjpsADkAAAAA.Govndrag:BAAALgADCgEJAQAAAA==.Govs:BAACLgAFFH8GAAQEAAMJohhtIgChAAAEAAIJBiJtIgChAAARAAIJchZPKwCZAAAhAAIJdghoPgB4AAAuAAQKfxUAAwQACAmVHlkPAG8CAAQACAmVHlkPAG8CABEAAwmVHt5WALQAAAAA.',
Gr='Gralmerte:BAABLgAECn82AAMUAAkJzSLjAQAWAwAUAAkJzSLjAQAWAwAiAAEJ9xSHxgA8AAAAAA==.Grawfern:BAAALgAECgkJEgAAAA==.Graygoyle:BAABLgAECn8hAAIWAAkJSgbUDABbAQAWAAkJSgbUDABbAQAAAA==.Groggaris:BAAALgAECgMJAwAAAA==.Groosalugg:BAABLgAECn8dAAIdAAkJtx1dKgAwAgAdAAkJtx1dKgAwAgAAAA==.',
Gu='Guillotine:BAAALgAECgEJAQAAAA==.Guldave:BAAALgAECgQJBAAAAA==.Guthrie:BAABLgAECn8VAAIJAAcJxheqKQC+AQAJAAcJxheqKQC+AQAAAA==.',
Gw='Gwyndolïn:BAABLgAECn8cAAMDAAcJqBVfLwC3AQADAAcJqBVfLwC3AQAYAAQJnAQ3awB5AAAAAA==.',
Ha='Hachendis:BAAALgADCgMJAwAAAA==.Haether:BAABLgAECn8tAAIeAAkJdBEMLQD/AQAeAAkJdBEMLQD/AQAAAA==.Haiku:BAAALgAECgEJAQAAAA==.Haliax:BAAALgAECgEJAQABLgAECgkJGAAFAE0hAA==.Hammatime:BAAALgADCgcJBwAAAA==.Hatsu:BAABLgAECn8VAAIDAAkJSgzOOgB+AQADAAkJSgzOOgB+AQAAAA==.Hawktuahh:BAAALgAECgIJAgAAAA==.',
He='Hellá:BAAALgADCgIJAgAAAA==.Hemandunter:BAAALgAECgEJAQAAAA==.',
Hi='Hildunn:BAAALgAECgQJBgAAAA==.Hingedh:BAABLgAFFH8FAAIGAAMJ9g6uJwCjAAAGAAMJ9g6uJwCjAAABLgAFFAcJIQAcAMccAA==.Hitemup:BAAALgADCgQJBAAAAA==.',
Hk='Hktanker:BAAALgADCgQJBAABLgAECgYJFgAdAI8KAA==.',
Ho='Holylentlezz:BAAALgADCgcJBwABLgAECgkJLwAZAGUfAA==.Holymun:BAABLgAECn8ZAAIFAAgJIxDFcQCIAQAFAAgJIxDFcQCIAQAAAA==.Holyox:BAABLgAECn83AAIFAAkJngxdcwCFAQAFAAkJngxdcwCFAQAAAA==.Hotcheeto:BAAALgAECgcJCQAAAA==.',
Ht='Hturtle:BAAALgADCgEJAQAAAA==.Hturtledk:BAABLgAECn8VAAMCAAYJvxbDnQAtAQACAAYJvxbDnQAtAQAVAAEJ3QKPagAUAAAAAA==.',
Hu='Hug:BAAALgAECgUJCAAAAA==.',
['Hü']='Hüntress:BAAALgAFFAEJAgAAAA==.',
Ia='Iacey:BAAALgAECgIJAgAAAA==.',
Im='Imdatroll:BAACLgAFFH8IAAMiAAMJSBP9NQDPAAAiAAMJSBP9NQDPAAAUAAIJrxOnFACDAAAuAAQKfzIABBQACQneIzYCADEDABQACQneIzYCADEDACIABgkUGWdYAC0BAAoAAgndCwFxAGEAAAAA.Imgibby:BAAALgADCgYJBgABLgAECggJFwAMAAgUAA==.Impius:BAAALgAECgkJCgAAAA==.Impmageddon:BAABLgAECn8aAAMSAAkJnRFyYwB3AQASAAkJnRFyYwB3AQATAAEJAAASdQAwAAAAAA==.',
In='Inexorable:BAABLgAFFH8FAAIFAAMJjxR7HwCwAAAFAAMJjxR7HwCwAAAAAA==.',
Ir='Irakwa:BAABLgAECn8UAAIdAAUJeQldvgDDAAAdAAUJeQldvgDDAAAAAA==.',
It='Itches:BAACLgAFFH8jAAIYAAgJIh8MAQCkAgAYAAgJIh8MAQCkAgAuAAQKfyAAAhgACAkHJOYDAE8DABgACAkHJOYDAE8DAAAA.',
Iw='Iwamori:BAAALgAECgEJAQAAAA==.',
Iz='Izánámi:BAABLgAECn8vAAQIAAcJYRU6HwCiAQAIAAcJYRU6HwCiAQAdAAEJ8A19ywA6AAAjAAEJlwGPmAAeAAAAAA==.',
Ja='Jagon:BAABLgAECn8oAAQkAAkJChqFEQBWAgAkAAkJChqFEQBWAgANAAIJtQerNABQAAAOAAIJHwwnJQA0AAAAAA==.Jalen:BAAALgAECgYJBgAAAA==.Janvi:BAAALgADCgUJBAAAAA==.Jarbito:BAAALgAECgUJCwAAAA==.Jarico:BAAALgAECgYJCgABLgAECgYJEgAHAAAAAA==.Jasint:BAAALgAECgUJBQABLgAECgkJKAAkAAoaAA==.',
Je='Jebrogue:BAAALgADCgkJDgAAAA==.',
Jh='Jhunts:BAAALgAECggJEAAAAA==.',
Ji='Jinbloom:BAAALgADCgIJAgAAAA==.Jincrush:BAAALgAECgIJAgAAAA==.Jindabutt:BAABLgAECn8mAAIlAAkJYyDqBQDcAgAlAAkJYyDqBQDcAgAAAA==.Jinfuse:BAAALgADCgUJBQAAAA==.Jintonic:BAAALgAECgcJCAAAAA==.',
Jk='Jkbalo:BAAALgAFFAIJBAAAAA==.Jkrlos:BAAALgAFFAMJBAAAAA==.',
Jo='Jocommande:BAAALgAECgEJAQAAAA==.Jointheraid:BAAALgADCgMJAwAAAA==.Jokerstree:BAAALgADCgYJBgAAAA==.Jorah:BAAALgADCgcJCgAAAA==.Jorkah:BAAALgADCgcJCgAAAA==.',
Jp='Jpdh:BAACLgAFFH8TAAMaAAQJZSNwBAApAQAGAAQJLSOJLABrAQAaAAMJ2yJwBAApAQAuAAQKfygABBoACQl3JIwEAHECAAYACQlSH2wYAMMCABoACAk8JYwEAHECAA8ABAkyF49EAOQAAAAA.Jphunt:BAAALgADCgUJBQABLgAFFAQJEwAaAGUjAA==.',
Ju='Juddory:BAABLgAECn8iAAIQAAcJQwuApwAsAQAQAAcJQwuApwAsAQAAAA==.Junksvil:BAAALgAECgYJEgAAAA==.',
['Jø']='Jøhnwick:BAAALgADCgYJBgAAAA==.',
Ka='Kahrahkon:BAAALgAECgQJDgAAAA==.Kalinis:BAAALgAECgIJAwAAAA==.Kanadoria:BAAALgAECgEJAQAAAA==.Kanion:BAAALgAECgYJCgAAAA==.',
Ke='Kenth:BAAALgAECgEJAQAAAA==.',
Kh='Khudoz:BAAALgAECgMJBwAAAA==.',
Ki='Killerelf:BAAALgADCggJCAAAAA==.Killshotz:BAAALgADCgUJBQAAAA==.Kismët:BAAALgAECgEJAQAAAA==.',
Kl='Klid:BAAALgADCgMJAwABLgAFFAIJBQAFAIIUAA==.',
Ko='Koa:BAAALgAECgEJAQAAAA==.Kooch:BAAALgADCgYJBgAAAA==.Korinth:BAECLgAFFH8dAAIgAAUJPBLcCADkAAAgAAUJPBLcCADkAAAuAAQKfz0AAiAACQnnGzcHAGkCACAACQnnGzcHAGkCAAAA.',
Kr='Kriaalis:BAABLgAECn8UAAMeAAkJXwTPeADvAAAeAAgJ9APPeADvAAAfAAEJqgVXvwAZAAAAAA==.',
Ku='Kurzon:BAAALgADCgMJAwABLgAECgkJHQAdALcdAA==.',
Ky='Kyra:BAAALgAECgUJCgAAAA==.',
['Kæ']='Kælas:BAAALgAECgEJAgAAAA==.',
La='Lachryma:BAAALgADCgUJBQAAAA==.Laríssa:BAEALgAECgkJEwAAAA==.Lazuli:BAAALgAECgYJBgABLgAECgkJQAAPAAskAA==.',
Le='Legault:BAABLgAECn8rAAImAAkJIB9gAQDnAgAmAAkJIB9gAQDnAgAAAA==.Legionofboom:BAAALgADCgQJBgAAAA==.Lethfel:BAABLgAECn8VAAMSAAgJ4xsXWACUAQASAAYJYBwXWACUAQATAAYJlRbkIABNAQAAAA==.Lethferal:BAAALgADCgIJAgAAAA==.',
Li='Liacci:BAAALgADCgYJBgAAAA==.Lilgoukii:BAAALgADCgIJAgAAAA==.Lillithfaust:BAAALgAECgMJBgAAAA==.Limbø:BAABLgAECn8eAAIQAAcJLCE8SAAAAgAQAAcJLCE8SAAAAgAAAA==.Lindia:BAAALgADCgEJAQAAAA==.Lionfury:BAAALgADCgcJBwAAAA==.Liquidturtle:BAAALgAECgMJBAAAAA==.Livie:BAABLgAECn8oAAIFAAkJlBguNAAtAgAFAAkJlBguNAAtAgAAAA==.',
Lo='Lonelylad:BAAALgAECgEJAQAAAA==.Loneshark:BAAALgAECgYJCQAAAA==.Longwood:BAAALgAECgYJCAAAAA==.Lonon:BAAALgADCgQJBAAAAA==.Loops:BAAALgAECgIJAwAAAA==.Loraddesmos:BAABLgAECn9CAAITAAkJaxTLBgDsAQATAAkJaxTLBgDsAQAAAA==.Loriah:BAABLgAECn8wAAIFAAkJShXORgDvAQAFAAkJShXORgDvAQAAAA==.Lovan:BAAALgAECgEJAgAAAA==.',
Lu='Lucance:BAAALgADCgkJDwAAAA==.Lullaby:BAABLgAECn8uAAIEAAkJhRe5FQAiAgAEAAkJhRe5FQAiAgAAAA==.Lumot:BAAALgADCgcJCwAAAA==.',
Ma='Maeg:BAAALgAECgIJAgABLgAFFAMJCAAiAEgTAA==.Maireldps:BAAALgAECgEJAQAAAA==.Marcdofu:BAAALgAECgMJAwAAAA==.Maryjanè:BAAALgAECgUJBQAAAA==.Mataquay:BAAALgAECgYJDAAAAA==.Maveloris:BAAALgADCgcJBgAAAA==.Mawzshallah:BAACLgAFFH8bAAIKAAUJryRbDwCkAQAKAAUJryRbDwCkAQAuAAQKfzMAAwoACQllJWgBAMEDAAoACQllJWgBAMEDABcABQl6FLMTADQBAAAA.Mayli:BAAALgAFFAMJAwAAAA==.',
Mc='Mctanker:BAABLgAECn8aAAMgAAcJUBEhHQApAQAgAAcJUBEhHQApAQAFAAUJBgv/8QDFAAAAAA==.',
Me='Meascii:BAACLgAFFH8MAAIhAAUJIggmIgA0AQAhAAUJIggmIgA0AQAuAAQKfyQAAiEACQlaGdANAI4CACEACQlaGdANAI4CAAAA.Medeaeris:BAAALgADCgIJAgAAAA==.Meepmorp:BAAALgAECgEJAQAAAA==.Merc:BAACLgAFFH8eAAIYAAcJgyCYAgAyAgAYAAcJgyCYAgAyAgAuAAQKfzoAAhgACQksI3AFAPgCABgACQksI3AFAPgCAAAA.',
Mi='Millee:BAABLgAECn8dAAMEAAgJhReoHADcAQAEAAgJhReoHADcAQARAAIJpgNwggA1AAAAAA==.Mincebeef:BAAALgAECgMJAwABLgAECggJGgAEALkXAA==.Mindpuck:BAAALgAECgQJBAAAAA==.Mirefighter:BAAALgADCggJCgABLgAFFAUJHgAUAE4kAA==.Miremana:BAAALgAECgcJDwABLgAFFAUJHgAUAE4kAA==.Mirespike:BAACLgAFFH8eAAIUAAUJTiQAAwCbAQAUAAUJTiQAAwCbAQAuAAQKfzIAAhQACQlSIpkDAPgCABQACQlSIpkDAPgCAAAA.Mistylady:BAAALgADCgIJBAAAAA==.',
Mo='Mommacougar:BAAALgADCgEJAQAAAA==.Moondrade:BAAALgAECgEJAQAAAA==.Moosebearowl:BAAALgAFFAIJAgAAAA==.Morfirrann:BAAALgADCgEJAQAAAA==.Morlis:BAAALgAECgQJBgAAAA==.Morlock:BAABLgAECn8rAAMSAAkJvQtRWACTAQASAAkJvQtRWACTAQAMAAEJWwgfNQAxAAAAAA==.Morningstahr:BAAALgAECgUJBQAAAA==.',
Mu='Murlen:BAAALgAECgMJBAAAAA==.',
My='Mystris:BAAALgADCgYJBgAAAA==.Mythidru:BAAALgAECgcJDgAAAA==.',
['Mâ']='Mâjestic:BAAALgADCgMJAwAAAA==.',
Na='Naanbread:BAAALgAECgQJBAAAAA==.Naaruto:BAABLgAECn8aAAIFAAgJzQ60iQBaAQAFAAgJzQ60iQBaAQAAAA==.Nadia:BAABLgAECn8XAAQhAAYJwQwUPgATAQAhAAYJmQsUPgATAQAEAAUJBAl3TACsAAARAAMJ9gL0dQBQAAAAAA==.Nanako:BAABLgAECn8vAAIQAAkJsRffLgBbAgAQAAkJsRffLgBbAgAAAA==.Naughtyvixen:BAAALgAECgMJAgABLgABCgIJAgAHAAAAAA==.Naughtyvoked:BAAALgAECgYJCgABLgABCgIJAgAHAAAAAA==.Navali:BAAALgAECgMJCAABLgAFFAEJAQAHAAAAAA==.',
Ne='Nefer:BAAALgADCgUJBQAAAA==.Nevicus:BAAALgAECgIJAwAAAA==.',
Ni='Nickayla:BAAALgADCggJCAAAAA==.Nikkaya:BAAALgADCgYJBgABLgAECgYJGwAXABwaAA==.Nimblecow:BAAALgAECgUJBQAAAA==.Nisdenar:BAAALgADCgkJDgAAAA==.',
No='Noobacleese:BAABLgAECn8wAAIFAAkJrxsgLABOAgAFAAkJrxsgLABOAgAAAA==.Noraviae:BAAALgADCgMJAwAAAA==.',
Nu='Nutbustin:BAABLgAECn8hAAIQAAkJBhnRPwAaAgAQAAkJBhnRPwAaAgAAAA==.',
Ny='Nyghtrider:BAABLgAECn8WAAIdAAYJjwqangD+AAAdAAYJjwqangD+AAAAAA==.Nykayla:BAAALgAECgcJAwAAAA==.Nymëra:BAABLgAECn8bAAIeAAkJig3mUgBjAQAeAAkJig3mUgBjAQAAAA==.Nyneeve:BAABLgAECn84AAIRAAkJ8hGvGwDmAQARAAkJ8hGvGwDmAQAAAA==.',
Ob='Obscené:BAAALgAECgQJBAAAAA==.',
Od='Oddessyee:BAAALgADCgcJBwABLgAECggJGAAdAPUYAA==.Oddiee:BAABLgAECn8YAAMCAAcJNw/cqAAcAQACAAcJNw/cqAAcAQAVAAQJzgP0OQB0AAABLgAECggJGAAdAPUYAA==.Odinshunter:BAAALgAECgYJBgAAAA==.Odst:BAAALgADCgUJBwABLgAECgkJFwACABcgAA==.',
Oh='Ohdatroll:BAAALgAFFAIJBAABLgAFFAMJCAAiAEgTAA==.',
Ol='Olgrin:BAAALgADCgkJEgABLgAECgYJBwAHAAAAAA==.',
On='Onepunch:BAAALgAECgEJAQAAAA==.Oneslice:BAAALgAECgUJBgAAAA==.Onyxstar:BAAALgAECgEJAQAAAA==.',
Op='Opera:BAAALgAECgQJBgAAAA==.',
Or='Orikkosh:BAABLgAECn8fAAMlAAcJ0hY0JQCBAQAlAAcJ0hY0JQCBAQAYAAIJuwpCcQBNAAAAAA==.',
Ot='Otsmayo:BAAALgAECgkJBwAAAA==.',
Pa='Palel:BAABLgAECn83AAIJAAkJLREmKwC0AQAJAAkJLREmKwC0AQAAAA==.Palpatinee:BAAALgAECgQJBAAAAA==.Pancetta:BAAALgAECgEJAQABLgAECgkJQAAPAAskAA==.Parabelum:BAAALgAECgIJAgAAAA==.',
Pb='Pbfearz:BAABLgAECn8WAAMSAAYJhh8TWAC/AQASAAUJhh8TWAC/AQATAAEJAADsXgBSAAAAAA==.',
Pe='Peguelo:BAAALgADCgIJAgAAAA==.Pendrágon:BAAALgAECgIJAgAAAA==.Percocetpete:BAACLgAFFH8NAAIEAAUJBRdPDwBWAQAEAAUJBRdPDwBWAQAuAAQKfx4AAwQACAnaJCQCAE8DAAQACAnaJCQCAE8DABEAAgkmDm13AEwAAAAA.Peregrine:BAAALgADCgMJAwAAAA==.',
Ph='Phaet:BAACLgAFFH8eAAMSAAUJfySXKgCRAQASAAUJfySXKgCRAQATAAEJiw5oFQBUAAAuAAQKfzUAAhIACQnxJHQJADMDABIACQnxJHQJADMDAAAA.Phatty:BAAALgADCgMJAwAAAA==.Phaux:BAAALgAECgIJAgAAAA==.Philipp:BAABLgAECn8gAAIKAAkJDwqtLQBoAQAKAAkJDwqtLQBoAQAAAA==.',
Pi='Picco:BAAALgADCgEJAQABLgAECgUJCQAHAAAAAA==.Pixistix:BAAALgAFFAEJAQAAAA==.',
Pl='Plâgue:BAABLgAECn8bAAICAAkJ4xqSSgDgAQACAAkJ4xqSSgDgAQAAAA==.',
Pn='Pneuma:BAAALgADCgEJAQAAAA==.',
Po='Potentialman:BAAALgAECgcJCwAAAA==.',
Pr='Preprot:BAAALgADCgkJCQABLgAECgkJJwAVADoVAA==.Prot:BAAALgAECgQJBAAAAA==.',
Pu='Punslug:BAAALgAECgYJCgABLgAFFAIJBgAUAM4aAA==.',
['Pó']='Pókóu:BAAALgADCgMJAwAAAA==.',
Ra='Radiance:BAAALgAECgcJBwAAAA==.Raezorian:BAAALgAECggJDgABLgAECgkJNQAYANoiAA==.Rahmo:BAAALgADCgYJBgAAAA==.Rainforest:BAABLgAECn8bAAIXAAYJHBpCGwBuAQAXAAYJHBpCGwBuAQAAAA==.Rakiji:BAAALgAECgEJAQAAAA==.Ralphh:BAAALgADCgIJAgAAAA==.Ramdem:BAAALgAECggJEAAAAA==.Ramden:BAABLgAECn84AAIFAAkJQwv+cQCHAQAFAAkJQwv+cQCHAQAAAA==.Rampant:BAABLgAECn8XAAMCAAkJFyC3HgCOAgACAAkJFyC3HgCOAgAVAAEJlSDZTQBXAAAAAA==.Rampscii:BAAALgAECgQJBQABLgAECgkJFwACABcgAA==.Randalore:BAAALgAECgMJAwABLgAFFAMJCAAiAEgTAA==.Randwulf:BAAALgAECggJEwAAAA==.Ranwong:BAAALgAECgQJCgAAAA==.Ratherton:BAACLgAFFH8fAAIQAAUJjR6rQgBoAQAQAAUJjR6rQgBoAQAuAAQKfysAAxAACQmbIO0wAK8CABAACQmbIO0wAK8CACcAAwnRHM8NAOkAAAAA.Rathtard:BAABLgAECn8XAAIdAAkJ3BqhIABgAgAdAAkJ3BqhIABgAgABLgAFFAUJHwAQAI0eAA==.Rauloso:BAAALgAECgQJEQAAAA==.Ravìn:BAAALgAECgYJDAAAAA==.Rayne:BAAALgAECgcJCAABLgAFFAEJAQAHAAAAAA==.',
Rd='Rdata:BAAALgADCgYJBgAAAA==.',
Re='Relentlezz:BAAALgADCgMJAwABLgAECgkJLwAZAGUfAA==.Resoluteone:BAABLgAECn9MAAIVAAkJkhX6EAD5AQAVAAkJkhX6EAD5AQAAAA==.Retnu:BAAALgADCggJEAAAAA==.Revytwohand:BAACLgAFFH8eAAMYAAUJxSCOCgBxAQAYAAUJxSCOCgBxAQADAAQJgwuHMgDYAAAuAAQKfzQAAhgACQmXJSkEABYDABgACQmXJSkEABYDAAAA.',
Rh='Rhagul:BAAALgAFFAEJAQAAAA==.Rhok:BAAALgADCgEJAQAAAA==.Rhokhard:BAAALgADCgEJAwAAAA==.',
Ro='Rocketarena:BAAALgAECgcJDwAAAA==.Rootytooty:BAAALgAECgIJAgAAAA==.Rozelie:BAABLgAFFH8HAAIKAAMJ4hLMLwC9AAAKAAMJ4hLMLwC9AAABLgAFFAcJHgAhAH8aAA==.',
Ry='Ryzarapriest:BAAALgAECgMJBAABLgAFFAEJAQAHAAAAAA==.',
Sa='Sabeladys:BAABLgAECn8oAAIFAAkJRCE4FQDBAgAFAAkJRCE4FQDBAgAAAA==.Sadpeepo:BAAALgADCgIJAgAAAA==.Saifir:BAABLgAECn8pAAIeAAkJBRECOADLAQAeAAkJBRECOADLAQAAAA==.Sardmongo:BAAALgADCgcJCgAAAA==.Sardogobo:BAAALgAECgEJAQABLgAECggJIgASAIEUAA==.Sarduccini:BAABLgAECn8iAAISAAgJgRTaTADiAQASAAgJgRTaTADiAQAAAA==.Sargeros:BAAALgAECgQJBAAAAA==.',
Se='Sebastîan:BAAALgAECgEJAQABLgAECgkJHgASAD8XAA==.Sekhmet:BAAALgAECgcJCAAAAA==.Sekio:BAAALgAECgYJCwAAAA==.',
Sh='Shadowpriest:BAAALgADCgEJAQAAAA==.Shamburgyr:BAAALgAECgMJAwABLgAECggJIgAdAFENAA==.Shanàs:BAAALgAECgEJAQABLgAECgkJGwAFAEYeAA==.Sharayu:BAAALgADCgQJBAAAAA==.Shiftken:BAAALgAECgMJAwAAAA==.Shiftyfive:BAAALgAFFAMJAwAAAA==.Shivà:BAAALgADCgUJCAAAAA==.',
Si='Sigrodah:BAACLgAFFH8PAAMkAAUJ9g8TMwD0AAAkAAQJ9g8TMwD0AAANAAEJswGjKwA1AAAuAAQKfxkAAyQACAlTH9cRAF0CACQACAlTH9cRAF0CAA4ABAm2EW4pANQAAAAA.Silvalus:BAAALgAECgYJBwAAAA==.Sin:BAAALgAECgkJCAAAAA==.',
Sk='Skaara:BAAALgAECgQJBwAAAA==.Skara:BAAALgADCgEJAQAAAA==.Skiddles:BAAALgADCgIJAgAAAA==.Skinwalker:BAAALgADCgYJCgAAAA==.Skithyryx:BAAALgADCgIJAgAAAA==.Skor:BAAALgADCgQJBAAAAA==.Skyblue:BAAALgAECgEJAQAAAA==.Skyeforce:BAAALgAECgMJBAAAAA==.',
Sl='Slipknoth:BAABLgAECn8UAAMJAAYJkRmEUwAsAQAJAAUJFheEUwAsAQAFAAYJoRIQuAAVAQAAAA==.',
Sm='Smellyy:BAAALgADCgEJAQAAAA==.Smoketurtle:BAAALgAECgUJCAAAAA==.',
Sn='Sno:BAAALgAECgEJAQAAAA==.',
So='Socatoas:BAABLgAECn8YAAIBAAkJtgn8MwB5AQABAAkJtgn8MwB5AQAAAA==.Softbanana:BAAALgADCgEJAQAAAA==.Soi:BAAALgAECgYJCgABLgAECgkJGAAFAE0hAA==.Solarion:BAAALgAECgEJAQABLgAECgQJDQAHAAAAAA==.Sonoforak:BAAALgAECgYJBwAAAA==.',
Sp='Sped:BAABLgAECn8tAAQZAAkJih8CBQDLAgAZAAkJih8CBQDLAgAoAAUJswhvLwB6AAABAAEJ9wP3rgAtAAAAAA==.',
St='Stalrun:BAAALgAECgYJCgABLgAECgYJEgAHAAAAAA==.Staraleena:BAAALgAECgUJBQAAAA==.Stormeyes:BAAALgAECgMJAQABLgAECgcJIgAgAJAbAA==.Stormslight:BAABLgAECn8iAAIgAAcJkBvNEACzAQAgAAcJkBvNEACzAQAAAA==.Stormsteel:BAAALgAECgEJAwAAAA==.Stôrmrägé:BAAALgAECgcJDQAAAA==.',
Sw='Swgchainz:BAAALgAECgcJEwABLgAECgkJLQAPADEdAA==.Swiftdéath:BAAALgAECgYJCgAAAA==.Swtbabybilly:BAAALgAECgYJCQAAAA==.',
['Sä']='Säberdh:BAAALgADCgYJBgABLgAECgMJAwAHAAAAAA==.',
['Så']='Såran:BAAALgAECgUJCwAAAA==.',
['Sí']='Sílence:BAABLgAECn8UAAIKAAcJvAgRRwDsAAAKAAcJvAgRRwDsAAAAAA==.',
['Sô']='Sôlrïx:BAAALgAECgUJCgAAAA==.',
Ta='Tabio:BAAALgADCgYJBgAAAA==.Tabito:BAAALgAECgEJAQAAAA==.Talas:BAABLgAECn8wAAIgAAkJnRbsDQDhAQAgAAkJnRbsDQDhAQAAAA==.Taltaelen:BAAALgADCgYJBgABLgAECgkJFgACAOILAA==.Tamarack:BAABLgAECn8XAAIdAAYJshuJUQB0AQAdAAYJshuJUQB0AQAAAA==.',
Te='Teetsie:BAAALgAFFAEJAQAAAA==.Tehmber:BAAALgAECgQJCAABLgAECgUJBwAHAAAAAA==.Tehmplar:BAAALgAECgUJBwAAAA==.Terrormisu:BAAALgAECgEJAQABLgAECggJGQAFAHEcAA==.',
Th='Thalorien:BAAALgADCgYJBgABLgAECgcJFwAJAIghAA==.Theboart:BAAALgAECgQJCQAAAA==.Thredron:BAABLgAFFH8HAAIJAAMJTAcmNgCQAAAJAAMJTAcmNgCQAAAAAA==.',
Ti='Tilted:BAAALgAECggJCQABLgAECgkJLgAEAIUXAA==.Timebarred:BAAALgAECgEJBAAAAA==.',
To='Tooru:BAACLgAFFH8WAAMdAAUJvBbBNwA3AQAdAAUJMhbBNwA3AQAIAAEJsg4hMABNAAAuAAQKfzYABB0ACQm+IYsGACUDAB0ACQm+IYsGACUDAAgACAncEFkcALoBACMABgkWGT1LACUBAAAA.Tortiana:BAAALgAECgUJBQAAAA==.Tossko:BAAALgAECgIJAwABLgAECgQJDAAHAAAAAA==.',
Tr='Traefel:BAAALgAECgEJAQAAAA==.Traeflor:BAAALgAECgEJAQAAAA==.Traevok:BAAALgAECgEJAgAAAA==.Trailertrash:BAABLgAECn9EAAIQAAgJnB+BNgA8AgAQAAgJnB+BNgA8AgAAAA==.Treebeef:BAACLgAFFH8cAAIiAAUJ7QkJKgALAQAiAAUJ7QkJKgALAQAuAAQKfzIAAyIACQkCG+0YAHACACIACQkCG+0YAHACAAoAAQnWA/GMACIAAAAA.Triena:BAAALgAECgQJBgAAAA==.Trirn:BAAALgADCgYJBgAAAA==.Trumpeter:BAAALgAECgQJCwAAAA==.Trywind:BAAALgAECgUJBQAAAA==.',
Ts='Tsukuyómi:BAAALgAECgEJAQAAAA==.',
Ty='Tyberos:BAABLgAECn8kAAQEAAgJqxzFDQB+AgAEAAgJ2BvFDQB+AgAhAAUJDBd+LwAkAQARAAMJpRfPXgCYAAAAAA==.Tydrielion:BAAALgAECgYJDgAAAA==.Typicaldrood:BAAALgAECgIJAgAAAA==.',
['Tí']='Tízzíts:BAAALgADCgYJBgAAAA==.',
Ul='Ullreich:BAABLgAECn8YAAIdAAcJVwt4iwAjAQAdAAcJVwt4iwAjAQAAAA==.Ulysius:BAACLgAFFH8IAAIFAAQJjROpRAAdAQAFAAQJjROpRAAdAQAuAAQKfysAAgUACQmWGXEzADACAAUACQmWGXEzADACAAAA.',
Un='Unfazed:BAAALgAECgEJAQAAAA==.Unicornslayr:BAABLgAECn8qAAIJAAkJTRaKKADFAQAJAAkJTRaKKADFAQAAAA==.',
Ur='Urund:BAAALgAECgYJDgAAAA==.',
Uw='Uwantsmoke:BAABLgAECn8eAAIdAAYJMwTEtwDPAAAdAAYJMwTEtwDPAAAAAA==.Uwantsmokee:BAAALgADCgMJAwAAAA==.',
Va='Valgroth:BAAALgAECgIJAwAAAA==.Valkisek:BAACLgAFFH8RAAIQAAQJxhAFXQAwAQAQAAQJxhAFXQAwAQAuAAQKfxcAAhAABwnYFwqbAJ8BABAABwnYFwqbAJ8BAAAA.Valkonigen:BAAALgAECgEJAQAAAA==.Vallarfax:BAABLgAECn8rAAIdAAkJIx/wFwCTAgAdAAkJIx/wFwCTAgAAAA==.Vandro:BAABLgAECn8kAAMJAAkJlhgPHwAIAgAJAAkJlhgPHwAIAgAgAAYJ2gpELAC4AAAAAA==.Vantive:BAAALgAECgYJDwAAAA==.Vash:BAAALgAECgEJAQAAAA==.Vashdk:BAACLgAFFH8SAAIVAAUJ9x2nFABCAQAVAAUJ9x2nFABCAQAuAAQKfxUAAhUACAnEFn8QAAMCABUACAnEFn8QAAMCAAAA.Vashmonk:BAACLgAFFH8MAAIlAAQJzyOnEwB+AQAlAAQJzyOnEwB+AQAuAAQKfxUAAiUACQmcIRUMAHICACUACQmcIRUMAHICAAAA.Vashwar:BAAALgAECgYJBgAAAA==.',
Ve='Vedruid:BAAALgAECggJDwAAAA==.Velaric:BAABLgAECn8vAAMiAAkJyht/FACkAgAiAAkJyht/FACkAgAXAAEJ3gvWfQAfAAAAAA==.Velcyn:BAAALgADCgcJDgABLgAECgIJAgAHAAAAAA==.Veldoria:BAAALgAECgQJBgAAAA==.Veloe:BAAALgAECgIJAgAAAA==.Verath:BAAALgADCgEJAQAAAA==.Vespyr:BAABLgAECn8iAAIdAAgJUQ1UYQB/AQAdAAgJUQ1UYQB/AQAAAA==.Vewdoo:BAABLgAECn84AAIfAAkJtiSdAgBKAwAfAAkJtiSdAgBKAwAAAA==.',
Vi='Viejoverde:BAAALgAECgQJCAAAAA==.Vipul:BAAALgAECgYJDgAAAA==.Vizimir:BAAALgAECgcJBwAAAA==.',
Vo='Voldune:BAAALgAECgIJAwAAAA==.',
['Vë']='Vëgetå:BAAALgADCgYJBwABLgAECgUJBQAHAAAAAA==.',
Wa='Waiwai:BAAALgAECgEJAgAAAA==.Warfarin:BAAALgAECgEJBAAAAA==.Wascii:BAABLgAECn8hAAIdAAkJGBUuNQAEAgAdAAkJGBUuNQAEAgABLgAECgkJFwACABcgAA==.Waxedthataxe:BAAALgAECgEJAQAAAA==.Waxesaxes:BAAALgAECgQJBwAAAA==.',
We='Weaken:BAAALgAECgUJCwAAAA==.Weskr:BAAALgADCgEJAQABLgAECggJJAAEAKscAA==.',
Wi='Wickedsinner:BAAALgADCgEJAQAAAA==.',
Wo='Wolvesbane:BAABLgAFFH8FAAIdAAUJbwCypABCAAAdAAUJbwCypABCAAAAAA==.',
Wy='Wyrmblood:BAAALgAECgcJDgABLgAECgkJLwARAJQjAA==.Wyrmfur:BAABLgAECn8WAAMXAAgJgyDBBgCJAgAXAAgJgyDBBgCJAgAUAAQJUh7aHgALAQAAAA==.Wyrmheal:BAABLgAECn8vAAIRAAkJlCP3BQDzAgARAAkJlCP3BQDzAgAAAA==.Wyvvie:BAAALgADCgIJAgAAAA==.',
Xa='Xavil:BAAALgAECgEJAQAAAA==.Xavv:BAAALgADCgUJBQAAAA==.',
Xi='Xiba:BAAALgAECgQJBwAAAA==.',
Xl='Xle:BAAALgADCgIJAgAAAA==.',
Ya='Yakoff:BAAALgAECgIJAgAAAA==.Yamihime:BAABLgAECn81AAMPAAkJCxW9GAC4AQAPAAgJcha9GAC4AQAGAAkJvwthWwByAQAAAA==.Yatiri:BAABLgAECn8ZAAMfAAgJxRJdKwCVAQAfAAgJxRJdKwCVAQAeAAEJQg512gAqAAAAAA==.',
Yo='Yoowuzsup:BAABLgAECn8aAAIfAAcJnByJLwB/AQAfAAcJnByJLwB/AQAAAA==.',
Yu='Yureimage:BAABLgAECn8WAAIQAAYJMAuw1ADnAAAQAAYJMAuw1ADnAAAAAA==.',
Za='Zarthus:BAAALgAECggJAgAAAA==.',
Ze='Zeaket:BAACLgAFFH8mAAIIAAgJKR1WAQBeAgAIAAgJKR1WAQBeAgAuAAQKfy8AAggACQmSIhkBAGEDAAgACQmSIhkBAGEDAAAA.Zedsdeadd:BAAALgAECgYJDQAAAA==.Zephyr:BAABLgAECn8jAAIhAAcJtwbiPQATAQAhAAcJtwbiPQATAQABLgAECggJIgAdAFENAA==.Zeçhs:BAABLgAECn8YAAIFAAkJTSFZFADxAgAFAAkJTSFZFADxAgAAAA==.',
Zi='Zinek:BAAALgAECgQJBQAAAA==.Zinra:BAAALgAECgUJCQAAAA==.',
Zo='Zoma:BAAALgADCgUJBgAAAA==.Zorcan:BAABLgAECn8oAAIMAAkJZxraBABEAgAMAAkJZxraBABEAgAAAA==.',
Zu='Zugzugz:BAAALgAECgEJAgAAAA==.Zulfilith:BAAALgAECgMJBQAAAA==.',
['Zà']='Zàrgothrax:BAAALgADCgYJDgAAAA==.',
['Zð']='Zðltrain:BAAALgAECgQJCgAAAA==.',
['Ál']='Álfruen:BAAALgAECgUJBgAAAA==.',
['Ãi']='Ãinz:BAAALgAECgMJAwAAAA==.',
['Èx']='Èxecutioner:BAAALgADCgMJAwAAAA==.',
['Ða']='Ðachee:BAAALgAECgQJCQAAAA==.',
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
