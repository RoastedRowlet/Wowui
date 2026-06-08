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

local lookup = {'Warrior-Fury','DeathKnight-Unholy','Monk-Mistweaver','Priest-Holy','Paladin-Retribution','DemonHunter-Devourer','Unknown-Unknown','Hunter-Survival','Paladin-Holy','Druid-Balance','DeathKnight-Frost','Evoker-Preservation','Evoker-Devastation','DemonHunter-Havoc','Hunter-Marksmanship','Mage-Frost','Priest-Shadow','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Druid-Feral','DeathKnight-Blood','Druid-Guardian','Monk-Windwalker','Warrior-Protection','DemonHunter-Vengeance','Shaman-Enhancement','Rogue-Subtlety','Hunter-BeastMastery','Shaman-Restoration','Shaman-Elemental','Paladin-Protection','Priest-Discipline','Druid-Restoration','Rogue-Assassination','Evoker-Augmentation','Monk-Brewmaster','Rogue-Outlaw','Mage-Arcane','Warrior-Arms',}
local provider = {region='US',realm='Madoran',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aarhus:BAAALgAECgQJBQAAAA==.Aaronmourne:BAAALgAECgQJBAABLgAECgkJGAABALYJAA==.Aaronyates:BAAALgADCgcJBwABLgAECgkJFwACABcgAA==.',
Ac='Actualegirl:BAABLgAFFH8GAAIDAAUJLQQrLwDSAAADAAUJLQQrLwDSAAABLgAFFAUJDQAEAAUXAA==.',
Ad='Adversary:BAAALgADCgMJAwAAAA==.',
Ae='Aerfen:BAABLgAECn8cAAIFAAkJyg1uYgChAQAFAAkJyg1uYgChAQAAAA==.',
Ag='Agross:BAAALgADCgYJBgAAAA==.',
Ai='Aimforhead:BAAALgAECgcJDAAAAA==.',
Al='Alexas:BAAALgADCgcJCAAAAA==.Alric:BAABLgAECn80AAIGAAkJYxSmMgDwAQAGAAkJYxSmMgDwAQAAAA==.Alyndra:BAAALgADCgUJBQABLgAECgUJBQAHAAAAAA==.',
Am='Amideus:BAAALgAECgEJAQAAAA==.Amory:BAABLgAECn8mAAICAAkJ9x7HHgCHAgACAAkJ9x7HHgCHAgAAAA==.',
An='Angela:BAAALgADCgIJAgAAAA==.Annaesthetic:BAAALgAECgEJAgABLgAECggJLwAIAGEVAA==.',
Ar='Arator:BAAALgADCgEJAgAAAA==.Araña:BAAALgAECgEJAQAAAA==.Arcatraz:BAAALgAECgEJAQAAAA==.Ardaddy:BAAALgAECgYJDQABLgAFFAMJBAAHAAAAAA==.Ardzak:BAAALgAFFAMJBAAAAA==.Arragorn:BAACLgAFFH8IAAIJAAQJFRnbHAArAQAJAAQJFRnbHAArAQAuAAQKfycAAgkACQktHEAYADsCAAkACQktHEAYADsCAAAA.',
As='Asendra:BAABLgAECn8mAAIKAAkJ6xljEABQAgAKAAkJ6xljEABQAgAAAA==.Assaran:BAAALgAECgIJAgAAAA==.Astal:BAACLgAFFH8LAAILAAUJlA8WDQAYAQALAAUJlA8WDQAYAQAuAAQKfx0AAgsACQmfGzsGADUCAAsACQmfGzsGADUCAAAA.',
At='Athenea:BAABLgAECn8aAAIBAAcJUBs0HgD2AQABAAcJUBs0HgD2AQAAAA==.Atulru:BAAALgADCgMJAwAAAA==.',
Az='Azuren:BAABLgAECn8pAAMMAAkJgwc9FwBUAQAMAAkJgwc9FwBUAQANAAYJkwxcEgDXAAAAAA==.',
Ba='Baal:BAAALgAFFAIJAgAAAA==.Bacon:BAABLgAECn85AAMOAAkJCySgBADzAgAOAAkJCySgBADzAgAGAAcJTRaJTgCOAQAAAA==.Bamboozled:BAAALgAECgYJCAABLgAECgkJIAAPAA0VAA==.Bandìt:BAAALgAECggJCwAAAA==.Bankai:BAAALgAFFAEJAwAAAA==.Barbieque:BAAALgADCgcJBwAAAA==.',
Be='Bearyden:BAAALgADCgEJAQAAAA==.Bedbugs:BAAALgAECgQJBAABLgAFFAUJHQAQALMdAA==.Beefstrasz:BAABLgAECn8WAAMEAAcJ1xIJJQCOAQAEAAcJ1xIJJQCOAQARAAEJpwYeigAoAAAAAA==.Beyla:BAACLgAFFH8FAAIFAAMJIwjfbwC+AAAFAAMJIwjfbwC+AAAuAAQKfycAAgUACQkFFzMxADECAAUACQkFFzMxADECAAAA.',
Bi='Bioactive:BAAALgADCgYJBgAAAA==.Bishamon:BAABLgAECn9EAAQSAAkJ+yHwBQBeAwASAAkJ+yHwBQBeAwATAAEJAADAaQA+AAAUAAEJAADlMQA6AAAAAA==.Bizotch:BAAALgAECggJDgAAAA==.',
Bl='Bleau:BAABLgAECn8gAAIVAAgJPBDEEwByAQAVAAgJPBDEEwByAQAAAA==.Blethings:BAAALgAECgMJAwAAAA==.Blinktwice:BAAALgAECgEJAgAAAA==.Bloodimess:BAAALgADCgMJAwAAAA==.Bloodymary:BAABLgAECn8nAAIWAAkJOhVJEgDeAQAWAAkJOhVJEgDeAQAAAA==.Bluebarrie:BAAALgAECgEJAQAAAA==.Blôodräge:BAAALgAECgcJDgAAAA==.',
Bo='Bouncybean:BAAALgADCgIJAgAAAA==.',
Br='Bradsupinya:BAABLgAECn8kAAIQAAgJEBlLWgDIAQAQAAgJEBlLWgDIAQAAAA==.Branchling:BAAALgAECgcJEgABLgAFFAUJHQAQALMdAA==.Brewswane:BAAALgAFFAEJAwAAAA==.Bridh:BAABLgAECn8aAAIGAAkJFR5LEQD0AgAGAAkJFR5LEQD0AgABLgAFFAcJHgATAOYdAA==.Bromm:BAAALgAECgEJAQAAAA==.',
Bu='Bulkamania:BAAALgAECgMJAwAAAA==.Butterkip:BAACLgAFFH8PAAIRAAUJfBSzEwAzAQARAAUJfBSzEwAzAQAuAAQKfysAAhEACQlpHikKAOACABEACQlpHikKAOACAAAA.',
['Bë']='Bëarclaw:BAAALgAECgUJBQAAAA==.',
Ca='Cambria:BAAALgAECgMJAwAAAA==.Cantkillme:BAAALgAECgQJBwAAAA==.Canukillme:BAAALgADCgYJBgAAAA==.Carruel:BAAALgADCgUJBQAAAA==.Cazzc:BAAALgAECgUJCAAAAA==.',
Ce='Cellan:BAABLgAECn8WAAICAAcJ6wrYtAAEAQACAAcJ6wrYtAAEAQAAAA==.',
Ch='Chicharrones:BAAALgAECgUJBQABLgAECgkJOQAOAAskAA==.Chickenshift:BAABLgAECn8eAAMXAAcJJR/HCwAUAgAXAAcJJR/HCwAUAgAVAAEJuRWBRQA/AAAAAA==.Chipahoy:BAABLgAECn8nAAIFAAgJdRwlNAAlAgAFAAgJdRwlNAAlAgABLgAECggJRAAQAJwfAA==.Chopahoe:BAAALgAECgQJBwAAAA==.Chuggz:BAABLgAECn8gAAIYAAkJ5xFAHQC2AQAYAAkJ5xFAHQC2AQAAAA==.',
Cl='Clamadin:BAAALgAECgIJAgABLgAFFAgJJQAQAKccAA==.Clamius:BAACLgAFFH8lAAIQAAgJpxx3BwCiAgAQAAgJpxx3BwCiAgAuAAQKfygAAhAACAkMJVcRAEADABAACAkMJVcRAEADAAAA.Cliff:BAAALgAECgUJBgAAAA==.',
Co='Colby:BAAALgAECgYJDgAAAA==.Coldass:BAABLgAECn8ZAAIQAAgJwRILYQC3AQAQAAgJwRILYQC3AQAAAA==.Commodus:BAAALgADCgQJBAAAAA==.Conduit:BAAALgAECgMJAwAAAA==.Coombrain:BAAALgAECgUJCQAAAA==.Cotopla:BAAALgAECgQJDAAAAA==.',
Cr='Critterzz:BAABLgAECn8aAAIEAAgJ4hb6FwAcAgAEAAgJ4hb6FwAcAgAAAA==.Cryptkeys:BAAALgAECgMJAwAAAA==.',
Cu='Cuziseeu:BAAALgAECgQJBAABLgAECgYJBgAHAAAAAA==.',
Da='Dachyy:BAAALgAECgYJEQAAAA==.Daemonwaters:BAAALgAECgEJAQAAAA==.Dagov:BAAALgAECgYJCAAAAA==.Daiana:BAAALgAECgIJAgAAAA==.Damage:BAAALgAFFAEJAQAAAA==.Darkråii:BAAALgAECgIJAwAAAA==.Dashboy:BAAALgADCgEJAQAAAA==.',
De='Deafniteelf:BAAALgAECgkJDQAAAA==.Deathlentlez:BAABLgAECn8vAAIZAAkJZR9/BgCZAgAZAAkJZR9/BgCZAgAAAA==.Decaylentlez:BAAALgAECgEJAQABLgAECgkJLwAZAGUfAA==.Deepwinter:BAAALgAECgYJDAABLgAECgkJFwACABcgAA==.Delphyne:BAAALgAECgYJEwAAAA==.Demonhunter:BAABLgAECn8gAAIOAAkJuhhMDQBAAgAOAAkJuhhMDQBAAgAAAA==.Demonià:BAAALgAECgcJEQAAAA==.Desong:BAAALgADCgYJBwAAAA==.Detharbinger:BAAALgAECgcJDAAAAA==.Dezzan:BAAALgADCgQJBwAAAA==.',
Di='Diamondsword:BAAALgAECggJDgAAAA==.',
Do='Dochaze:BAABLgAECn8qAAMJAAkJfxyHHwAdAgAJAAgJPB+HHwAdAgAFAAMJjA0EEgGUAAAAAA==.Dogdimmadome:BAAALgAECgYJDwAAAA==.Dolore:BAAALgADCgcJBgAAAA==.Doublejump:BAAALgAECgEJAQABLgAECgkJJwAWADoVAA==.',
Dr='Dragone:BAAALgAECgUJCQAAAA==.Dragun:BAAALgADCgUJBQABLgAECggJEwAHAAAAAA==.',
Du='Dumbdumb:BAAALgAECgQJBgAAAA==.',
Dy='Dyanuh:BAABLgAECn8bAAIRAAYJIQKMYwB6AAARAAYJIQKMYwB6AAAAAA==.',
['Dà']='Dàrkscythe:BAABLgAECn8cAAMWAAcJmAVMOACoAAAWAAcJuQRMOACoAAALAAEJiQbpOQApAAAAAA==.',
Ea='Eazywin:BAAALgAECggJCQAAAA==.',
Eh='Ehlsa:BAAALgADCgcJBwAAAA==.Ehlsi:BAABLgAECn8uAAIaAAkJUR+JAgDHAgAaAAkJUR+JAgDHAgAAAA==.Ehress:BAAALgAECgcJEwABLgAECgkJFwACABcgAA==.',
Ei='Eirinny:BAABLgAECn8tAAIbAAkJWQoIEgCFAQAbAAkJWQoIEgCFAQAAAA==.',
El='Elindez:BAABLgAECn8nAAIcAAkJUw8BFwDXAQAcAAkJUw8BFwDXAQAAAA==.Elyviel:BAAALgAFFAEJAQAAAA==.Elàine:BAABLgAECn8mAAIdAAgJkgfhdgBFAQAdAAgJkgfhdgBFAQAAAA==.',
Em='Emika:BAAALgADCgUJCQAAAA==.Emyrson:BAAALgAECgQJCQAAAA==.',
En='Enemywithin:BAAALgADCgIJAgAAAA==.Enzo:BAAALgADCgYJCwAAAA==.',
Ep='Epicfury:BAAALgAECgYJDgAAAA==.',
Eq='Eq:BAAALgADCgUJBgAAAA==.',
Ez='Ezmee:BAAALgAECgUJDgAAAA==.',
Fa='Facingworlds:BAAALgAECggJDgAAAA==.Fathercaleb:BAAALgAECgIJAwABLgAFFAUJHgAYAMUgAA==.Fazed:BAAALgAECgIJBgAAAA==.Fazeo:BAAALgAECgIJAgAAAA==.',
Fe='Featherstep:BAAALgADCgMJAwAAAA==.Felysse:BAAALgADCgEJAQAAAA==.',
Fi='Fireball:BAAALgAECgIJAgABLgAFFAEJAQAHAAAAAA==.',
Fl='Flavio:BAAALgAECgQJCAAAAA==.',
Fo='Fortuna:BAABLgAECn8jAAIbAAgJYwRZHAAJAQAbAAgJYwRZHAAJAQAAAA==.',
Fr='Francesca:BAAALgADCgEJAQAAAA==.Frosilen:BAABLgAECn87AAMeAAkJCxD/PQCoAQAeAAkJCxD/PQCoAQAfAAMJaQvccwB+AAAAAA==.Frostbite:BAAALgADCgIJAgAAAA==.',
Ga='Gamaikuba:BAAALgADCggJCQAAAA==.Gamarth:BAAALgAECgYJDQAAAA==.Gatlu:BAABLgAECn8hAAIXAAkJcBYPDAAPAgAXAAkJcBYPDAAPAgAAAA==.Gato:BAAALgADCgIJAgAAAA==.Gawdsmackk:BAAALgAECgcJDQAAAA==.Gaz:BAAALgADCgMJAwAAAA==.Gazokks:BAAALgADCgcJBwAAAA==.',
Ge='Gedank:BAAALgADCgcJBwAAAA==.Geodemon:BAAALgAECgQJBAAAAA==.Gethealed:BAAALgAECgcJEAAAAA==.Getrektpos:BAAALgADCgMJAwAAAA==.',
Gh='Ghostlock:BAABLgAECn8VAAIUAAgJzxn2BQAFAgAUAAgJzxn2BQAFAgAAAA==.Ghoztface:BAABLgAECn8oAAMgAAcJcxzHDgDYAQAgAAYJXCDHDgDYAQAFAAcJJxKHkwBAAQAAAA==.Ghöstbeef:BAAALgADCgkJEAABLgAECgcJFgAEANcSAA==.',
Gi='Giblock:BAABLgAECn8XAAIUAAgJCBTeDQBqAQAUAAgJCBTeDQBqAQAAAA==.',
Gl='Glamour:BAAALgAECgQJEAAAAA==.Glitterboy:BAAALgAECgIJAgABLgAFFAgJIwAYACIfAA==.',
Go='Golomojek:BAAALgAECgcJDgAAAA==.Gorkun:BAAALgADCgkJDgAAAA==.Gov:BAACLgAFFH8WAAMOAAUJAR+uDQAlAQAGAAUJCR2DNAA8AQAOAAUJfhWuDQAlAQAuAAQKfygAAwYACQm/JYsIAEUDAAYACQm/JYsIAEUDAA4AAQlSEjpsADkAAAAA.Govndrag:BAAALgADCgEJAQAAAA==.Govs:BAACLgAFFH8GAAQEAAMJohgJIACkAAAEAAIJBiIJIACkAAARAAIJchYuKACcAAAhAAIJdggDOgB5AAAuAAQKfxUAAwQACAmVHlYOAHMCAAQACAmVHlYOAHMCABEAAwmVHn5UALQAAAAA.',
Gr='Gralmerte:BAABLgAECn82AAMVAAkJzSKyAQAaAwAVAAkJzSKyAQAaAwAiAAEJ9xSHxgA8AAAAAA==.Grawfern:BAAALgAECgkJEgAAAA==.Graygoyle:BAABLgAECn8hAAIjAAkJSgZYDABcAQAjAAkJSgZYDABcAQAAAA==.Groggaris:BAAALgAECgMJAwAAAA==.Groosalugg:BAABLgAECn8dAAIdAAkJtx3nJgA5AgAdAAkJtx3nJgA5AgAAAA==.',
Gu='Guillotine:BAAALgADCgcJCgAAAA==.Guldave:BAAALgAECgQJBAAAAA==.Guthrie:BAABLgAECn8VAAIJAAcJxhdFKAC/AQAJAAcJxhdFKAC/AQAAAA==.',
Gw='Gwyndolïn:BAABLgAECn8WAAMDAAYJgQ9XVgD7AAADAAYJgQ9XVgD7AAAYAAQJnATRZgB5AAAAAA==.',
Ha='Hachendis:BAAALgADCgMJAwAAAA==.Haether:BAABLgAECn8tAAIeAAkJdBEaKwAAAgAeAAkJdBEaKwAAAgAAAA==.Haiku:BAAALgAECgEJAQAAAA==.Haliax:BAAALgAECgEJAQABLgAECgkJGAAFAE0hAA==.Hammatime:BAAALgADCgcJBwAAAA==.Hatsu:BAABLgAECn8VAAIDAAkJSgxeNwB9AQADAAkJSgxeNwB9AQAAAA==.Hawktuahh:BAAALgAECgIJAgAAAA==.',
He='Hellá:BAAALgADCgIJAgAAAA==.Hemandunter:BAAALgAECgEJAQAAAA==.',
Hi='Hildunn:BAAALgAECgQJBgAAAA==.Hingedh:BAABLgAFFH8FAAIGAAMJ9g6uJwCjAAAGAAMJ9g6uJwCjAAABLgAFFAYJHQAcAJUgAA==.Hitemup:BAAALgADCgQJBAAAAA==.',
Ho='Holylentlezz:BAAALgADCgcJBwABLgAECgkJLwAZAGUfAA==.Holymun:BAAALgAECggJEwAAAA==.Holyox:BAABLgAECn8wAAIFAAkJAAyGcwB8AQAFAAkJAAyGcwB8AQAAAA==.Hotcheeto:BAAALgAECgMJAwAAAA==.',
Ht='Hturtle:BAAALgADCgEJAQAAAA==.Hturtledk:BAABLgAECn8VAAMCAAYJvxbAlwAwAQACAAYJvxbAlwAwAQAWAAEJ3QJjZgAUAAAAAA==.',
Hu='Hug:BAAALgAECgUJCAAAAA==.',
['Hü']='Hüntress:BAAALgAFFAEJAQAAAA==.',
Ia='Iacey:BAAALgAECgIJAgAAAA==.',
Im='Imdatroll:BAACLgAFFH8IAAMiAAMJSBPhNADWAAAiAAMJSBPhNADWAAAVAAIJrxN2EgCKAAAuAAQKfzIABBUACQneIzYCADEDABUACQneIzYCADEDACIABgkUGWVWACwBAAoAAgndCyRtAGEAAAAA.Imgibby:BAAALgADCgYJBgABLgAECggJFwAUAAgUAA==.Impius:BAAALgAECgkJCgAAAA==.Impmageddon:BAABLgAECn8aAAMSAAkJnREtYAB8AQASAAkJnREtYAB8AQATAAEJAAASdQAwAAAAAA==.',
In='Inexorable:BAABLgAFFH8FAAIFAAMJjxR7HwCwAAAFAAMJjxR7HwCwAAAAAA==.',
Ir='Irakwa:BAAALgAECgUJEQAAAA==.',
It='Itches:BAACLgAFFH8jAAIYAAgJIh/FAACxAgAYAAgJIh/FAACxAgAuAAQKfyAAAhgACAkHJOYDAE8DABgACAkHJOYDAE8DAAAA.',
Iw='Iwamori:BAAALgAECgEJAQAAAA==.',
Iz='Izánámi:BAABLgAECn8vAAQIAAcJYRVLHgClAQAIAAcJYRVLHgClAQAdAAEJ8A19ywA6AAAPAAEJlwGPmAAeAAAAAA==.',
Ja='Jagon:BAABLgAECn8iAAQkAAkJ/RiWEgBEAgAkAAkJ/RiWEgBEAgAMAAIJtQfcMgBSAAANAAIJHww/JAA0AAAAAA==.Jalen:BAAALgAECgYJBgAAAA==.Janvi:BAAALgADCgUJBAAAAA==.Jarbito:BAAALgAECgUJCwAAAA==.Jarico:BAAALgAECgIJBAABLgAECgYJEgAHAAAAAA==.Jasint:BAAALgAECgUJBQABLgAECgkJIgAkAP0YAA==.',
Je='Jebrogue:BAAALgADCgkJDgAAAA==.',
Jh='Jhunts:BAAALgAECggJEAAAAA==.',
Ji='Jinbloom:BAAALgADCgIJAgAAAA==.Jincrush:BAAALgAECgIJAgAAAA==.Jindabutt:BAABLgAECn8mAAIlAAkJYyCbBQDeAgAlAAkJYyCbBQDeAgAAAA==.Jinfuse:BAAALgADCgUJBQAAAA==.Jintonic:BAAALgAECgcJCAAAAA==.',
Jk='Jkbalo:BAAALgAFFAIJAwAAAA==.Jkrlos:BAAALgAFFAEJAQAAAA==.',
Jo='Jocommande:BAAALgAECgEJAQAAAA==.Jointheraid:BAAALgADCgMJAwAAAA==.Jokerstree:BAAALgADCgYJBgAAAA==.Jorah:BAAALgADCgMJAwAAAA==.Jorkah:BAAALgADCgcJCgAAAA==.',
Jp='Jpdh:BAACLgAFFH8PAAMaAAQJsh3lAwArAQAGAAQJGxyYNQA4AQAaAAMJ2yLlAwArAQAuAAQKfygABBoACQl3JEYEAHICAAYACQlSH2wYAMMCABoACAk8JUYEAHICAA4ABAkyF49EAOQAAAAA.Jphunt:BAAALgADCgUJBQABLgAFFAQJDwAaALIdAA==.',
Ju='Juddory:BAABLgAECn8hAAIQAAcJKws2oQA0AQAQAAcJKws2oQA0AQAAAA==.Junksvil:BAAALgAECgYJEgAAAA==.',
['Jø']='Jøhnwick:BAAALgADCgYJBgAAAA==.',
Ka='Kahrahkon:BAAALgAECgQJDgAAAA==.Kalinis:BAAALgAECgIJAwAAAA==.Kanion:BAAALgAECgYJCgAAAA==.',
Ke='Kenth:BAAALgAECgEJAQAAAA==.',
Kh='Khudoz:BAAALgAECgMJBwAAAA==.',
Ki='Killerelf:BAAALgADCggJCAAAAA==.Killshotz:BAAALgADCgUJBQAAAA==.Kismët:BAAALgAECgEJAQAAAA==.',
Kl='Klid:BAAALgADCgMJAwABLgAFFAIJBQAFAIIUAA==.',
Ko='Koa:BAAALgAECgEJAQAAAA==.Kooch:BAAALgADCgYJBgAAAA==.Korinth:BAECLgAFFH8dAAIgAAUJPBLsBwDrAAAgAAUJPBLsBwDrAAAuAAQKfz0AAiAACQnnG7IGAGwCACAACQnnG7IGAGwCAAAA.',
Kr='Kriaalis:BAAALgAFFAEJAQAAAA==.',
Ku='Kurzon:BAAALgADCgMJAwABLgAECgkJHQAdALcdAA==.',
Ky='Kyra:BAAALgAECgQJBgAAAA==.',
['Kæ']='Kælas:BAAALgAECgEJAgAAAA==.',
La='Lachryma:BAAALgADCgUJBQAAAA==.Laríssa:BAEALgAECgkJEwAAAA==.Lazuli:BAAALgAECgYJBgABLgAECgkJOQAOAAskAA==.',
Le='Legault:BAABLgAECn8rAAImAAkJIR9VAQDmAgAmAAkJIR9VAQDmAgAAAA==.Legionofboom:BAAALgADCgQJBgAAAA==.Lethfel:BAABLgAECn8VAAMSAAgJ4xvBVQCWAQASAAYJYBzBVQCWAQATAAYJlRbkIABNAQAAAA==.Lethferal:BAAALgADCgIJAgAAAA==.',
Li='Liacci:BAAALgADCgYJBgAAAA==.Lilgoukii:BAAALgADCgIJAgAAAA==.Lillithfaust:BAAALgAECgMJBgAAAA==.Limbø:BAABLgAECn8eAAIQAAcJLCEBRgADAgAQAAcJLCEBRgADAgAAAA==.Lindia:BAAALgADCgEJAQAAAA==.Lionfury:BAAALgADCgcJBwAAAA==.Liquidturtle:BAAALgAECgMJBAAAAA==.Livie:BAABLgAECn8lAAIFAAgJThaLUgDHAQAFAAgJThaLUgDHAQAAAA==.',
Lo='Lonelylad:BAAALgAECgEJAQAAAA==.Loneshark:BAAALgAECgYJCQAAAA==.Longwood:BAAALgAECgYJCAAAAA==.Lonon:BAAALgADCgQJBAAAAA==.Loops:BAAALgAECgIJAwAAAA==.Loraddesmos:BAABLgAECn9AAAITAAkJaxROBgDvAQATAAkJaxROBgDvAQAAAA==.Loriah:BAABLgAECn8wAAIFAAkJShWCQwDxAQAFAAkJShWCQwDxAQAAAA==.Lovan:BAAALgAECgEJAQAAAA==.',
Lu='Lucance:BAAALgADCgkJDwAAAA==.Lullaby:BAABLgAECn8uAAIEAAkJhReRFAAlAgAEAAkJhReRFAAlAgAAAA==.Lumot:BAAALgADCgcJCwAAAA==.',
Ma='Maeg:BAAALgAECgIJAgABLgAFFAMJCAAiAEgTAA==.Marcdofu:BAAALgAECgMJAwAAAA==.Maryjanè:BAAALgAECgUJBQAAAA==.Mataquay:BAAALgAECgYJDAAAAA==.Maveloris:BAAALgADCgcJBgAAAA==.Mawzshallah:BAACLgAFFH8aAAIKAAUJryS1DQCjAQAKAAUJryS1DQCjAQAuAAQKfzMAAwoACQllJWgBAMEDAAoACQllJWgBAMEDABcABQl6FLMTADQBAAAA.Mayli:BAAALgAECggJEAAAAA==.',
Mc='Mctanker:BAABLgAECn8aAAMgAAcJUBEKHAApAQAgAAcJUBEKHAApAQAFAAUJBgvJ6QDFAAAAAA==.',
Me='Meascii:BAACLgAFFH8HAAIhAAQJEAeOKADsAAAhAAQJEAeOKADsAAAuAAQKfyMAAiEACQlaGR0NAI8CACEACQlaGR0NAI8CAAAA.Medeaeris:BAAALgADCgIJAgAAAA==.Meepmorp:BAAALgAECgEJAQAAAA==.Merc:BAACLgAFFH8cAAIYAAYJ1iBuBADKAQAYAAYJ1iBuBADKAQAuAAQKfzgAAhgACQkAIzUFAPYCABgACQkAIzUFAPYCAAAA.',
Mi='Millee:BAABLgAECn8dAAMEAAgJhRdhGwDeAQAEAAgJhRdhGwDeAQARAAIJpgOCfAA2AAAAAA==.Mincebeef:BAAALgAECgMJAwABLgAECgcJFgAEANcSAA==.Mindpuck:BAAALgAECgQJBAAAAA==.Mirefighter:BAAALgADCggJCgABLgAFFAUJHgAVAE4kAA==.Miremana:BAAALgAECgcJDwABLgAFFAUJHgAVAE4kAA==.Mirespike:BAACLgAFFH8eAAIVAAUJTiRvAgChAQAVAAUJTiRvAgChAQAuAAQKfzIAAhUACQlSIpkDAPgCABUACQlSIpkDAPgCAAAA.Mistylady:BAAALgADCgIJBAAAAA==.',
Mo='Mommacougar:BAAALgADCgEJAQAAAA==.Moondrade:BAAALgAECgEJAQAAAA==.Moosebearowl:BAAALgAFFAIJAgAAAA==.Morfirrann:BAAALgADCgEJAQAAAA==.Morlis:BAAALgAECgMJBQAAAA==.Morlock:BAABLgAECn8rAAMSAAkJvQsdVACbAQASAAkJvQsdVACbAQAUAAEJWwgfNQAxAAAAAA==.Morningstahr:BAAALgAECgUJBQAAAA==.',
Mu='Murlen:BAAALgAECgMJBAAAAA==.',
My='Mystris:BAAALgADCgYJBgAAAA==.Mythidru:BAAALgAECgcJDgAAAA==.',
['Mâ']='Mâjestic:BAAALgADCgMJAwAAAA==.',
Na='Naanbread:BAAALgAECgQJBAAAAA==.Naaruto:BAABLgAECn8aAAIFAAgJzQ6QgwBcAQAFAAgJzQ6QgwBcAQAAAA==.Nadia:BAAALgAECgQJDQAAAA==.Nanako:BAABLgAECn8pAAIQAAkJMhdxLwBVAgAQAAkJMhdxLwBVAgAAAA==.Naughtyvixen:BAAALgAECgMJAgABLgABCgIJAgAHAAAAAA==.Naughtyvoked:BAAALgAECgYJCgABLgABCgIJAgAHAAAAAA==.Navali:BAAALgAECgMJCAABLgAFFAEJAQAHAAAAAA==.',
Ne='Nefer:BAAALgADCgUJBQAAAA==.Nevicus:BAAALgAECgEJAgAAAA==.',
Ni='Nickayla:BAAALgADCggJCAAAAA==.Nikkaya:BAAALgADCgYJBgABLgAECgYJGwAXABwaAA==.Nimblecow:BAAALgAECgUJBQAAAA==.Nisdenar:BAAALgADCgkJDgAAAA==.',
No='Nohealzforu:BAAALgADCgcJCgAAAA==.Noobacleese:BAABLgAECn8wAAIFAAkJrxuUKQBRAgAFAAkJrxuUKQBRAgAAAA==.Noraviae:BAAALgADCgMJAwAAAA==.',
Nu='Nutbustin:BAABLgAECn8hAAIQAAkJBhmpOwAlAgAQAAkJBhmpOwAlAgAAAA==.',
Ny='Nyghtrider:BAABLgAECn8WAAIdAAYJjwo/lwAEAQAdAAYJjwo/lwAEAQAAAA==.Nymëra:BAABLgAECn8bAAIeAAkJig1PTwBmAQAeAAkJig1PTwBmAQAAAA==.Nyneeve:BAABLgAECn8yAAIRAAgJihLeIgCpAQARAAgJihLeIgCpAQAAAA==.',
Ob='Obscené:BAAALgAECgQJBAAAAA==.',
Od='Oddessyee:BAAALgADCgcJBwABLgAECggJGAAdAPUYAA==.Oddiee:BAABLgAECn8YAAMCAAcJNw+7oQAgAQACAAcJNw+7oQAgAQAWAAQJzgP0OQB0AAABLgAECggJGAAdAPUYAA==.Odinshunter:BAAALgAECgEJAQAAAA==.Odst:BAAALgADCgUJBwABLgAECgkJFwACABcgAA==.',
Oh='Ohdatroll:BAAALgAFFAIJBAABLgAFFAMJCAAiAEgTAA==.',
Ol='Olgrin:BAAALgADCgkJEgABLgAECgEJAQAHAAAAAA==.',
On='Onepunch:BAAALgAECgEJAQAAAA==.Oneslice:BAAALgAECgUJBgAAAA==.Onyxstar:BAAALgAECgEJAQAAAA==.',
Op='Opera:BAAALgAECgQJBgAAAA==.',
Or='Orikkosh:BAABLgAECn8fAAMlAAcJ0hYUJACDAQAlAAcJ0hYUJACDAQAYAAIJuwpCcQBNAAAAAA==.',
Ot='Otsmayo:BAAALgAECgkJBwAAAA==.',
Pa='Palel:BAABLgAECn83AAIJAAkJLRG7KQC1AQAJAAkJLRG7KQC1AQAAAA==.Palpatinee:BAAALgAECgQJBAAAAA==.Pancetta:BAAALgADCgQJBAABLgAECgkJOQAOAAskAA==.Parabelum:BAAALgAECgIJAgAAAA==.',
Pb='Pbfearz:BAABLgAECn8WAAMSAAYJhh8TWAC/AQASAAUJhh8TWAC/AQATAAEJAADsXgBSAAAAAA==.',
Pe='Peguelo:BAAALgADCgIJAgAAAA==.Pendrágon:BAAALgAECgIJAgAAAA==.Percocetpete:BAACLgAFFH8NAAIEAAUJBRe3DQBaAQAEAAUJBRe3DQBaAQAuAAQKfx4AAwQACAnaJCQCAE8DAAQACAnaJCQCAE8DABEAAgkmDqJyAEwAAAAA.Peregrine:BAAALgADCgMJAwAAAA==.',
Ph='Phaet:BAACLgAFFH8eAAMSAAUJfyTGIwCZAQASAAUJfyTGIwCZAQATAAEJiw5oFQBUAAAuAAQKfzUAAhIACQnxJHQJADMDABIACQnxJHQJADMDAAAA.Phatty:BAAALgADCgMJAwAAAA==.Phaux:BAAALgAECgIJAgAAAA==.Philipp:BAABLgAECn8gAAIKAAkJDwq/KwBpAQAKAAkJDwq/KwBpAQAAAA==.',
Pi='Picco:BAAALgADCgEJAQABLgAECgUJCQAHAAAAAA==.Pixistix:BAAALgAFFAEJAQAAAA==.',
Pl='Plâgue:BAABLgAECn8bAAICAAkJ4xp3RgDnAQACAAkJ4xp3RgDnAQAAAA==.',
Pn='Pneuma:BAAALgADCgEJAQAAAA==.',
Po='Potentialman:BAAALgAECgcJCwAAAA==.',
Pu='Punslug:BAAALgAECgYJCgABLgAFFAIJBQAVAM4aAA==.',
['Pó']='Pókóu:BAAALgADCgMJAwAAAA==.',
Ra='Raezorian:BAAALgAECggJDgABLgAECgkJNQAYANoiAA==.Rahmo:BAAALgADCgYJBgAAAA==.Rainforest:BAABLgAECn8bAAIXAAYJHBqlGQBvAQAXAAYJHBqlGQBvAQAAAA==.Rakiji:BAAALgAECgEJAQAAAA==.Ralphh:BAAALgADCgIJAgAAAA==.Ramdem:BAAALgAECggJCAAAAA==.Ramden:BAABLgAECn84AAIFAAkJQwtsbQCIAQAFAAkJQwtsbQCIAQAAAA==.Rampant:BAABLgAECn8XAAMCAAkJFyDWHACSAgACAAkJFyDWHACSAgAWAAEJlSABSwBYAAAAAA==.Rampscii:BAAALgAECgQJBQABLgAECgkJFwACABcgAA==.Randalore:BAAALgAECgMJAwABLgAFFAMJCAAiAEgTAA==.Randwulf:BAAALgAECggJEwAAAA==.Ranwong:BAAALgAECgQJCgAAAA==.Ratherton:BAACLgAFFH8dAAIQAAUJsx3zOwBsAQAQAAUJsx3zOwBsAQAuAAQKfysAAxAACQmbIO0wAK8CABAACQmbIO0wAK8CACcAAwnRHM8NAOkAAAAA.Rathtard:BAABLgAECn8WAAIdAAkJ3BrbHQBoAgAdAAkJ3BrbHQBoAgABLgAFFAUJHQAQALMdAA==.Rauloso:BAAALgAECgQJEQAAAA==.Ravìn:BAAALgAECgYJDAAAAA==.Rayne:BAAALgAECgcJCAABLgAFFAEJAQAHAAAAAA==.',
Rd='Rdata:BAAALgADCgQJBAAAAA==.',
Re='Relentlezz:BAAALgADCgMJAwABLgAECgkJLwAZAGUfAA==.Resoluteone:BAABLgAECn9MAAIWAAkJkhXxDwD/AQAWAAkJkhXxDwD/AQAAAA==.Retnu:BAAALgADCggJEAAAAA==.Revytwohand:BAACLgAFFH8eAAMYAAUJxSArCQB4AQAYAAUJxSArCQB4AQADAAQJgwsTLQDeAAAuAAQKfzQAAhgACQmXJccDABoDABgACQmXJccDABoDAAAA.',
Rh='Rhagul:BAAALgAECgcJCAAAAA==.Rhok:BAAALgADCgEJAQAAAA==.Rhokhard:BAAALgADCgEJAwAAAA==.',
Ro='Rocketarena:BAAALgAECgcJDwAAAA==.Rootytooty:BAAALgADCgQJBAAAAA==.Rozelie:BAABLgAFFH8HAAIKAAMJ4hLMLAC9AAAKAAMJ4hLMLAC9AAABLgAFFAcJHgAhAH8aAA==.',
Ry='Ryzarapriest:BAAALgAECgMJBAABLgAFFAEJAQAHAAAAAA==.',
Sa='Sabeladys:BAABLgAECn8oAAIFAAkJRCGQEwDFAgAFAAkJRCGQEwDFAgAAAA==.Sadpeepo:BAAALgADCgIJAgAAAA==.Saifir:BAABLgAECn8pAAIeAAkJBRG3NQDMAQAeAAkJBRG3NQDMAQAAAA==.Sardmongo:BAAALgADCgcJCgAAAA==.Sardogobo:BAAALgAECgEJAQABLgAECggJIgASAIEUAA==.Sarduccini:BAABLgAECn8iAAISAAgJgRTaTADiAQASAAgJgRTaTADiAQAAAA==.Sargeros:BAAALgAECgQJBAAAAA==.',
Se='Sebastîan:BAAALgAECgEJAQABLgAECgkJHgASAD8XAA==.Sekhmet:BAAALgAECgcJCAAAAA==.Sekio:BAAALgAECgYJCwAAAA==.',
Sh='Shadowpriest:BAAALgADCgEJAQAAAA==.Shamburgyr:BAAALgAECgMJAwABLgAECggJHAAdAI8LAA==.Shanàs:BAAALgAECgEJAQABLgAECgkJGwAFAEYeAA==.Sharayu:BAAALgADCgQJBAAAAA==.Shiftken:BAAALgAECgMJAwAAAA==.Shiftyfive:BAAALgAFFAEJAQAAAA==.Shivà:BAAALgADCgUJCAAAAA==.',
Si='Sigrodah:BAACLgAFFH8PAAMkAAUJ9g+ULgD8AAAkAAQJ9g+ULgD8AAAMAAEJswGsKQA1AAAuAAQKfxkAAyQACAlTH9cRAF0CACQACAlTH9cRAF0CAA0ABAm2EW4pANQAAAAA.Silvalus:BAAALgAECgEJAQAAAA==.Sin:BAAALgAECgkJCAAAAA==.',
Sk='Skaara:BAAALgAECgQJBwAAAA==.Skara:BAAALgADCgEJAQAAAA==.Skiddles:BAAALgADCgIJAgAAAA==.Skinwalker:BAAALgADCgYJCgAAAA==.Skithyryx:BAAALgADCgIJAgAAAA==.Skor:BAAALgADCgQJBAAAAA==.Skyblue:BAAALgAECgEJAQAAAA==.Skyeforce:BAAALgAECgEJAgAAAA==.',
Sl='Slipknoth:BAABLgAECn8UAAMJAAYJkRmEUwAsAQAJAAUJFheEUwAsAQAFAAYJoRIQuAAVAQAAAA==.',
Sm='Smellyy:BAAALgADCgEJAQAAAA==.Smoketurtle:BAAALgAECgUJCAAAAA==.',
Sn='Sno:BAAALgAECgEJAQAAAA==.',
So='Socatoas:BAABLgAECn8YAAIBAAkJtgm5MQB+AQABAAkJtgm5MQB+AQAAAA==.Softbanana:BAAALgADCgEJAQAAAA==.Soi:BAAALgAECgYJCgABLgAECgkJGAAFAE0hAA==.Solarion:BAAALgAECgEJAQABLgAECgQJCAAHAAAAAA==.Sonoforak:BAAALgAECgYJBwAAAA==.',
Sp='Sped:BAABLgAECn8tAAQZAAkJih+MBADQAgAZAAkJih+MBADQAgAoAAUJswhvLwB6AAABAAEJ9wP3rgAtAAAAAA==.',
St='Stalrun:BAAALgAECgYJCgABLgAECgYJEgAHAAAAAA==.Staraleena:BAAALgAECgUJBQAAAA==.Stormeyes:BAAALgAECgEJAQABLgAECgcJIgAgAJAbAA==.Stormslight:BAABLgAECn8iAAIgAAcJkBsYEAC0AQAgAAcJkBsYEAC0AQAAAA==.Stormsteel:BAAALgAECgEJAgAAAA==.Stôrmrägé:BAAALgAECgcJDQAAAA==.',
Sw='Swgchainz:BAAALgAECgcJEwABLgAECgkJLQAOADEdAA==.Swiftdéath:BAAALgAECgYJCgAAAA==.Swtbabybilly:BAAALgAECgEJAQAAAA==.',
['Sä']='Säberdh:BAAALgADCgYJBgABLgAECgMJAwAHAAAAAA==.',
['Så']='Såran:BAAALgAECgUJCwAAAA==.',
['Sí']='Sílence:BAABLgAECn8UAAIKAAcJvAhuRADsAAAKAAcJvAhuRADsAAAAAA==.',
['Sô']='Sôlrïx:BAAALgAECgUJCgAAAA==.',
Ta='Tabio:BAAALgADCgYJBgAAAA==.Tabito:BAAALgAECgEJAQAAAA==.Talas:BAABLgAECn8wAAIgAAkJnRY3DQDjAQAgAAkJnRY3DQDjAQAAAA==.Taltaelen:BAAALgADCgYJBgABLgAECgkJFgACAOILAA==.Tamarack:BAABLgAECn8XAAIdAAYJshuJUQB0AQAdAAYJshuJUQB0AQAAAA==.',
Te='Teetsie:BAAALgAFFAEJAQAAAA==.Tehmber:BAAALgAECgQJCAABLgAECgUJBwAHAAAAAA==.Tehmplar:BAAALgAECgUJBwAAAA==.',
Th='Thalorien:BAAALgADCgYJBgABLgAECgcJFwAJAIghAA==.Theboart:BAAALgAECgQJCQAAAA==.Thredron:BAABLgAFFH8HAAIJAAMJTAdwMgCcAAAJAAMJTAdwMgCcAAAAAA==.',
Ti='Timebarred:BAAALgAECgEJBAAAAA==.',
To='Tooru:BAACLgAFFH8WAAMdAAUJvBbOMABBAQAdAAUJMhbOMABBAQAIAAEJsg6YLQBNAAAuAAQKfzYABB0ACQm+IYsGACUDAB0ACQm+IYsGACUDAAgACAncECcbAL8BAA8ABgkWGT1LACUBAAAA.Tortiana:BAAALgAECgUJBQAAAA==.Tossko:BAAALgAECgIJAgABLgAECgQJDAAHAAAAAA==.',
Tr='Traefel:BAAALgAECgEJAQAAAA==.Traeflor:BAAALgAECgEJAQAAAA==.Traevok:BAAALgAECgEJAgAAAA==.Trailertrash:BAABLgAECn9EAAIQAAgJnB+fNAA/AgAQAAgJnB+fNAA/AgAAAA==.Treebeef:BAACLgAFFH8cAAIiAAUJ7QmuJQAjAQAiAAUJ7QmuJQAjAQAuAAQKfzIAAyIACQkCG+0YAHACACIACQkCG+0YAHACAAoAAQnWA/GMACIAAAAA.Triena:BAAALgAECgQJBgAAAA==.Trirn:BAAALgADCgYJBgAAAA==.Trumpeter:BAAALgAECgQJCwAAAA==.Trywind:BAAALgAECgUJBQAAAA==.',
Ts='Tsukuyómi:BAAALgAECgEJAQAAAA==.',
Ty='Tyberos:BAABLgAECn8kAAQEAAgJqxzFDQB+AgAEAAgJ2BvFDQB+AgAhAAUJDBd+LwAkAQARAAMJpRe4WwCaAAAAAA==.Tydrielion:BAAALgAECgYJDgAAAA==.Typicaldrood:BAAALgAECgIJAgAAAA==.',
['Tí']='Tízzíts:BAAALgADCgYJBgAAAA==.',
Ul='Ullreich:BAABLgAECn8YAAIdAAcJVwskhAApAQAdAAcJVwskhAApAQAAAA==.Ulysius:BAACLgAFFH8IAAIFAAQJjRPmPQAgAQAFAAQJjRPmPQAgAQAuAAQKfysAAgUACQmWGdIwADICAAUACQmWGdIwADICAAAA.',
Un='Unfazed:BAAALgAECgEJAQAAAA==.Unicornslayr:BAABLgAECn8qAAIJAAkJTRZFJwDGAQAJAAkJTRZFJwDGAQAAAA==.',
Ur='Urund:BAAALgAECgYJDgAAAA==.',
Uw='Uwantsmoke:BAABLgAECn8eAAIdAAYJMwTDrwDTAAAdAAYJMwTDrwDTAAAAAA==.Uwantsmokee:BAAALgADCgMJAwAAAA==.',
Va='Valgroth:BAAALgAECgIJAwAAAA==.Valkisek:BAACLgAFFH8NAAIQAAQJvQzBXwAgAQAQAAQJvQzBXwAgAQAuAAQKfxYAAhAABwnYFwqbAJ8BABAABwnYFwqbAJ8BAAAA.Valkonigen:BAAALgAECgEJAQAAAA==.Vallarfax:BAABLgAECn8rAAIdAAkJIx8AFgCZAgAdAAkJIx8AFgCZAgAAAA==.Vandro:BAABLgAECn8eAAIJAAkJlhjiHQAJAgAJAAkJlhjiHQAJAgAAAA==.Vantive:BAAALgAECgYJDwAAAA==.Vash:BAAALgAECgEJAQAAAA==.Vashdk:BAACLgAFFH8SAAIWAAUJ9x0PEgBLAQAWAAUJ9x0PEgBLAQAuAAQKfxUAAhYACAnEFn8QAAMCABYACAnEFn8QAAMCAAAA.Vashmonk:BAACLgAFFH8MAAIlAAQJzyNQEQCEAQAlAAQJzyNQEQCEAQAuAAQKfxUAAiUACQmcIYoLAHQCACUACQmcIYoLAHQCAAAA.Vashwar:BAAALgAECgYJBgAAAA==.',
Ve='Vedruid:BAAALgAECggJDwAAAA==.Velaric:BAABLgAECn8vAAMiAAkJyhvOEwCkAgAiAAkJyhvOEwCkAgAXAAEJ3gvzdAAfAAAAAA==.Velcyn:BAAALgADCgcJDgABLgAECgIJAgAHAAAAAA==.Veldoria:BAAALgAECgQJBgAAAA==.Veloe:BAAALgAECgIJAgAAAA==.Verath:BAAALgADCgEJAQAAAA==.Vespyr:BAABLgAECn8cAAIdAAgJjws+YwByAQAdAAgJjws+YwByAQAAAA==.Vewdoo:BAABLgAECn8zAAIfAAkJkiS1AgBCAwAfAAkJkiS1AgBCAwAAAA==.',
Vi='Viejoverde:BAAALgAECgQJBwAAAA==.Vipul:BAAALgAECgYJDgAAAA==.Vizimir:BAAALgAECgYJBAAAAA==.',
Vo='Voldune:BAAALgAECgIJAwAAAA==.',
['Vë']='Vëgetå:BAAALgADCgYJBwABLgAECgUJBQAHAAAAAA==.',
Wa='Waiwai:BAAALgAECgEJAgAAAA==.Warfarin:BAAALgAECgEJBAAAAA==.Wascii:BAABLgAECn8hAAIdAAkJGBWjMQAKAgAdAAkJGBWjMQAKAgABLgAECgkJFwACABcgAA==.Waxedthataxe:BAAALgAECgEJAQAAAA==.Waxesaxes:BAAALgAECgQJBwAAAA==.',
We='Weaken:BAAALgAECgUJCwAAAA==.Weskr:BAAALgADCgEJAQABLgAECggJJAAEAKscAA==.',
Wi='Wickedsinner:BAAALgADCgEJAQAAAA==.',
Wo='Wolvesbane:BAABLgAFFH8FAAIdAAUJbwARlwBFAAAdAAUJbwARlwBFAAAAAA==.',
Wy='Wyrmblood:BAAALgAECgcJDgABLgAECgkJLwARAJQjAA==.Wyrmfur:BAAALgAECggJDwAAAA==.Wyrmheal:BAABLgAECn8vAAIRAAkJlCOIBQD3AgARAAkJlCOIBQD3AgAAAA==.Wyvvie:BAAALgADCgIJAgAAAA==.',
Xa='Xavil:BAAALgAECgEJAQAAAA==.Xavv:BAAALgADCgUJBQAAAA==.',
Xi='Xiba:BAAALgAECgQJBwAAAA==.',
Xl='Xle:BAAALgADCgIJAgAAAA==.',
Ya='Yakoff:BAAALgAECgIJAgAAAA==.Yamihime:BAABLgAECn81AAMOAAkJCxVfFwC6AQAOAAgJchZfFwC6AQAGAAkJvwtlWAByAQAAAA==.Yatiri:BAAALgAECggJEwAAAA==.',
Yo='Yoowuzsup:BAABLgAECn8aAAIfAAcJnBxdLQCAAQAfAAcJnBxdLQCAAQAAAA==.',
Yu='Yureimage:BAABLgAECn8WAAIQAAYJMAtszQDwAAAQAAYJMAtszQDwAAAAAA==.',
Za='Zarthus:BAAALgAECggJAgAAAA==.',
Ze='Zeaket:BAACLgAFFH8mAAIIAAgJKR35AABjAgAIAAgJKR35AABjAgAuAAQKfy8AAggACQmSIhkBAGEDAAgACQmSIhkBAGEDAAAA.Zedsdeadd:BAAALgAECgYJDQAAAA==.Zephyr:BAABLgAECn8iAAIhAAcJtwbLOgAWAQAhAAcJtwbLOgAWAQABLgAECggJHAAdAI8LAA==.Zeçhs:BAABLgAECn8YAAIFAAkJTSFZFADxAgAFAAkJTSFZFADxAgAAAA==.',
Zi='Zinek:BAAALgAECgQJBQAAAA==.Zinra:BAAALgAECgIJBAAAAA==.',
Zo='Zoma:BAAALgADCgUJBgAAAA==.Zorcan:BAABLgAECn8lAAIUAAgJMxrNBwDfAQAUAAgJMxrNBwDfAQAAAA==.',
Zu='Zugzugz:BAAALgAECgEJAgAAAA==.Zulfilith:BAAALgAECgMJBQAAAA==.',
['Zà']='Zàrgothrax:BAAALgADCgYJDgAAAA==.',
['Zð']='Zðltrain:BAAALgAECgMJBgAAAA==.',
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
