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

local lookup = {'Warrior-Fury','DeathKnight-Unholy','Monk-Mistweaver','Priest-Holy','Paladin-Retribution','DemonHunter-Devourer','Unknown-Unknown','Hunter-Survival','Paladin-Holy','Druid-Balance','DeathKnight-Frost','Warlock-Affliction','Evoker-Preservation','Evoker-Devastation','DemonHunter-Havoc','Monk-Brewmaster','Mage-Frost','Priest-Shadow','Warlock-Demonology','Warlock-Destruction','Druid-Feral','DeathKnight-Blood','Rogue-Assassination','Druid-Guardian','Monk-Windwalker','Warrior-Protection','DemonHunter-Vengeance','Shaman-Enhancement','Rogue-Subtlety','Hunter-BeastMastery','Shaman-Restoration','Shaman-Elemental','Paladin-Protection','Priest-Discipline','Druid-Restoration','Hunter-Marksmanship','Evoker-Augmentation','Rogue-Outlaw','Mage-Arcane','Warrior-Arms',}
local provider = {region='US',realm='Madoran',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aarhus:BAAALgAECgQJBQAAAA==.Aaronmourne:BAAALgAECgQJBAABLgAECgkJGAABALYJAA==.Aaronyates:BAAALgADCgcJBwABLgAFFAQJBwACAIoZAA==.',
Ac='Actualegirl:BAABLgAFFH8GAAIDAAUJLQRLNwDLAAADAAUJLQRLNwDLAAABLgAFFAUJDQAEAAUXAA==.',
Ad='Adversary:BAAALgADCgMJAwAAAA==.',
Ae='Aerfen:BAABLgAECn8cAAIFAAkJyg2RaQCcAQAFAAkJyg2RaQCcAQAAAA==.',
Ag='Agross:BAAALgADCgYJBgAAAA==.',
Ai='Aimforhead:BAAALgAECgcJDAAAAA==.',
Ak='Akiraha:BAAALgAECgIJAgAAAA==.',
Al='Alexas:BAAALgADCgcJCAAAAA==.Alric:BAABLgAECn80AAIGAAkJYxQfNQDyAQAGAAkJYxQfNQDyAQAAAA==.Alyndra:BAAALgADCgUJBQABLgAECgUJBQAHAAAAAA==.',
Am='Amideus:BAAALgAECgEJAQAAAA==.Amory:BAABLgAECn8mAAICAAkJ9x4yIQCDAgACAAkJ9x4yIQCDAgAAAA==.',
An='Angela:BAAALgADCgIJAgAAAA==.Annaesthetic:BAAALgAECgEJAwABLgAECgkJMQAIAGESAA==.',
Ar='Arator:BAAALgADCgEJAgAAAA==.Araña:BAAALgAECgEJAQAAAA==.Arcatraz:BAAALgAECgEJAQAAAA==.Ardaddy:BAAALgAECgYJDQABLgAFFAMJBAAHAAAAAA==.Ardzak:BAAALgAFFAMJBAAAAA==.Arragorn:BAACLgAFFH8IAAIJAAQJFRmDHwAhAQAJAAQJFRmDHwAhAQAuAAQKfycAAgkACQktHLoZADkCAAkACQktHLoZADkCAAAA.',
As='Asendra:BAABLgAECn8mAAIKAAkJ6xnEEQBLAgAKAAkJ6xnEEQBLAgAAAA==.Assaran:BAAALgAECgIJAgAAAA==.Astal:BAACLgAFFH8LAAILAAUJlA/7DwAYAQALAAUJlA/7DwAYAQAuAAQKfx0AAgsACQmfGwkHACwCAAsACQmfGwkHACwCAAAA.',
At='Ate:BAAALgADCgYJBgABLgAECgkJKgAJAE0WAA==.Athenea:BAABLgAECn8aAAIBAAcJUBuYHwDyAQABAAcJUBuYHwDyAQAAAA==.Atulru:BAAALgADCgMJAwAAAA==.',
Av='Avyl:BAAALgADCgcJBwABLgAECgYJGwAMAPsRAA==.',
Az='Azriella:BAAALgAECggJBQAAAA==.Azuren:BAABLgAECn8rAAMNAAkJgwegGABKAQANAAkJgwegGABKAQAOAAYJeQ3XEgDdAAAAAA==.',
Ba='Baal:BAAALgAFFAIJAgAAAA==.Bacon:BAABLgAECn9AAAMPAAkJCyRPBQDtAgAPAAkJCyRPBQDtAgAGAAcJ8hfdSACsAQAAAA==.Bamboozled:BAABLgAECn8VAAMDAAgJbxNRLQDJAQADAAgJbxNRLQDJAQAQAAUJ7AOeAQCkAAAAAA==.Bandìt:BAAALgAECggJCwAAAA==.Bankai:BAAALgAFFAEJBAAAAA==.Barbieque:BAAALgADCgcJBwAAAA==.',
Be='Bearyden:BAAALgADCgEJAQAAAA==.Bedbugs:BAAALgAECgQJBAABLgAFFAUJIAARAI0eAA==.Beefstrasz:BAABLgAECn8aAAMEAAgJuRdiFAAzAgAEAAgJuRdiFAAzAgASAAEJpwbMkgAoAAAAAA==.Beyla:BAACLgAFFH8GAAIFAAMJQQolegDBAAAFAAMJQQolegDBAAAuAAQKfycAAgUACQkFF4M1ACsCAAUACQkFF4M1ACsCAAAA.',
Bi='Bioactive:BAAALgADCgYJBgAAAA==.Bishamon:BAABLgAECn9NAAQTAAkJ+yHwBQBeAwATAAkJ+yHwBQBeAwAUAAEJAADAaQA+AAAMAAEJAADlMQA6AAAAAA==.Bizotch:BAAALgAECggJDgAAAA==.',
Bl='Bleau:BAABLgAECn8iAAIVAAkJbxCoEACtAQAVAAkJbxCoEACtAQAAAA==.Blethings:BAAALgAECgMJAwAAAA==.Blinktwice:BAAALgAECgEJAgAAAA==.Bloodimess:BAAALgADCgMJAwAAAA==.Bloodymary:BAABLgAECn8nAAIWAAkJOhXvEwDUAQAWAAkJOhXvEwDUAQAAAA==.Bluebarrie:BAAALgAECgEJAQAAAA==.Blôodräge:BAAALgAECgcJDgAAAA==.',
Bo='Bouncybean:BAAALgADCgIJAgAAAA==.',
Br='Bradsupinya:BAABLgAECn8kAAIRAAgJEBl8XgDEAQARAAgJEBl8XgDEAQAAAA==.Branchling:BAAALgAECgcJEgABLgAFFAUJIAARAI0eAA==.Brewswane:BAAALgAFFAEJAwABLgAFFAcJJAAXAGoWAA==.Bridh:BAABLgAECn8aAAIGAAkJFR5LEQD0AgAGAAkJFR5LEQD0AgABLgAFFAgJHwAUABIcAA==.Bromm:BAAALgAECgEJAQAAAA==.Brunor:BAAALgAECgkJBwAAAA==.',
Bu='Bulkamania:BAAALgAECgMJAwAAAA==.Butterkip:BAACLgAFFH8PAAISAAUJfBSyFgAvAQASAAUJfBSyFgAvAQAuAAQKfysAAhIACQlpHikKAOACABIACQlpHikKAOACAAAA.',
['Bë']='Bëarclaw:BAAALgAECgUJBQAAAA==.',
Ca='Cambria:BAAALgAECgMJAwAAAA==.Cantkillme:BAAALgAECgQJBwAAAA==.Canukillme:BAAALgADCgYJBgAAAA==.Carruel:BAAALgADCgUJBQAAAA==.Cazzc:BAAALgAECgUJCAAAAA==.',
Ce='Cellan:BAABLgAECn8WAAICAAcJ6wqCvQABAQACAAcJ6wqCvQABAQAAAA==.Censora:BAAALgAECgEJAQAAAA==.',
Ch='Chicharrones:BAAALgAECgUJBQABLgAECgkJQAAPAAskAA==.Chickenshift:BAABLgAECn8kAAMYAAgJRCDwDAATAgAYAAcJJR/wDAATAgAVAAQJ4RjGHAAkAQAAAA==.Chipahoy:BAABLgAECn8nAAIFAAgJdRxCOAAhAgAFAAgJdRxCOAAhAgABLgAECggJRAARAJwfAA==.Chopahoe:BAAALgAECgQJBwAAAA==.Chuggz:BAABLgAECn8gAAIZAAkJ5xE1HwCzAQAZAAkJ5xE1HwCzAQAAAA==.',
Cl='Clamadin:BAAALgAECgIJAgABLgAFFAgJJQARAKccAA==.Clamius:BAACLgAFFH8lAAIRAAgJpxwyDACOAgARAAgJpxwyDACOAgAuAAQKfyoAAhEACQkkJRMLACADABEACQkkJRMLACADAAAA.Cliff:BAAALgAECgUJBgAAAA==.',
Co='Colby:BAAALgAECgYJDgAAAA==.Coldass:BAABLgAECn8ZAAIRAAgJwRJiZgCxAQARAAgJwRJiZgCxAQAAAA==.Commodus:BAAALgADCgQJBAAAAA==.Conduit:BAAALgAECgQJBQAAAA==.Coombrain:BAAALgAECgUJCQAAAA==.Cotopla:BAAALgAECgQJDAAAAA==.',
Cr='Critterzz:BAABLgAECn8aAAIEAAgJ4hb6FwAcAgAEAAgJ4hb6FwAcAgAAAA==.Cryptkeys:BAAALgAECgMJAwAAAA==.',
Cu='Cuziseeu:BAAALgAECgQJBAABLgAECgYJBgAHAAAAAA==.',
Da='Dachyy:BAAALgAECgYJEgAAAA==.Daemonwaters:BAAALgAECgEJAQAAAA==.Dagov:BAAALgAECgYJCAAAAA==.Daiana:BAAALgAECgIJAgAAAA==.Damage:BAAALgAFFAEJAQAAAA==.Darkråii:BAAALgAECgIJAwAAAA==.Dashboy:BAAALgADCgEJAQAAAA==.',
De='Deafniteelf:BAAALgAECgkJDQAAAA==.Deatharmonic:BAAALgAFFAIJAwAAAA==.Deathlentlez:BAABLgAECn8vAAIaAAkJZR87BwCSAgAaAAkJZR87BwCSAgAAAA==.Decaylentlez:BAAALgAECgEJAQABLgAECgkJLwAaAGUfAA==.Deepwinter:BAAALgAECgcJDQABLgAFFAQJBwACAIoZAA==.Delphyne:BAABLgAECn8UAAIOAAYJ9wvxEQDrAAAOAAYJ9wvxEQDrAAAAAA==.Demandred:BAAALgAECgcJDAAAAA==.Demonhunter:BAABLgAECn8gAAIPAAkJuhiXDgA8AgAPAAkJuhiXDgA8AgAAAA==.Demonià:BAABLgAECn8XAAIRAAgJFweBqQAsAQARAAgJFweBqQAsAQAAAA==.Desong:BAAALgADCgYJBwAAAA==.Detharbinger:BAAALgAECgcJDQAAAA==.Dezzan:BAAALgADCgQJBwAAAA==.',
Di='Diamondsword:BAAALgAECggJDgAAAA==.Dieanah:BAAALgADCgcJBwAAAA==.',
Dj='Djazz:BAAALgAECgIJAgAAAA==.',
Do='Dochaze:BAABLgAECn8qAAMJAAkJfxyHHwAdAgAJAAgJPB+HHwAdAgAFAAMJjA1FIAGTAAAAAA==.Dogdimmadome:BAAALgAECgYJDwAAAA==.Dolore:BAAALgADCgcJBgAAAA==.Doublejump:BAAALgAECgEJAQABLgAECgkJJwAWADoVAA==.',
Dr='Dragone:BAAALgAECgUJCQAAAA==.Dragun:BAAALgADCgUJBQABLgAECggJGQAFACMQAA==.Drowsee:BAAALgAECgEJAQAAAA==.',
Du='Dumbdumb:BAAALgAECgQJBgAAAA==.',
Dy='Dyanuh:BAABLgAECn8bAAISAAYJIQISagB2AAASAAYJIQISagB2AAAAAA==.',
['Dà']='Dàrkscythe:BAABLgAECn8cAAMWAAcJmAVJPACgAAAWAAcJuQRJPACgAAALAAEJiQZqPwAoAAAAAA==.',
Ea='Eazywin:BAAALgAECggJCQAAAA==.',
Eh='Ehlsa:BAAALgADCgcJBwAAAA==.Ehlsi:BAABLgAECn8wAAMbAAkJUR/PAgDFAgAbAAkJUR/PAgDFAgAPAAEJgxrtXwBNAAAAAA==.Ehress:BAAALgAECgcJEwABLgAFFAQJBwACAIoZAA==.',
Ei='Eirinny:BAABLgAECn8tAAIcAAkJWQq6EwB9AQAcAAkJWQq6EwB9AQAAAA==.',
El='Elindez:BAABLgAECn8nAAIdAAkJUw+ZGADVAQAdAAkJUw+ZGADVAQAAAA==.Elyviel:BAAALgAFFAEJAQAAAA==.Elàine:BAABLgAECn8yAAIeAAgJJgk8BgC4AAAeAAgJJgk8BgC4AAAAAA==.',
Em='Emika:BAAALgADCgUJDgAAAA==.Emyrson:BAAALgAECgQJCQAAAA==.',
En='Enemywithin:BAAALgADCgIJAgAAAA==.Enzo:BAAALgADCgYJCwAAAA==.',
Ep='Epicfury:BAAALgAECgYJDgAAAA==.',
Eq='Eq:BAAALgADCgUJBgAAAA==.',
Ez='Ezmee:BAAALgAECgUJDwAAAA==.',
Fa='Facingworlds:BAAALgAECggJDgAAAA==.Fathercaleb:BAAALgAECgIJAwABLgAFFAYJHwAZABEcAA==.Fazed:BAAALgAECgIJBgAAAA==.Fazeo:BAAALgAECgIJAgAAAA==.',
Fe='Featherstep:BAAALgADCgMJAwAAAA==.Felysse:BAAALgADCgEJAQAAAA==.',
Fi='Fireball:BAAALgAECgIJAgABLgAFFAEJAQAHAAAAAA==.',
Fl='Flavio:BAAALgAECgQJCAAAAA==.',
Fo='Fortuna:BAABLgAECn8kAAIcAAkJxASPGQA4AQAcAAkJxASPGQA4AQAAAA==.',
Fr='Francesca:BAAALgADCgEJAQAAAA==.Frosilen:BAABLgAECn87AAMfAAkJCxDjQQCmAQAfAAkJCxDjQQCmAQAgAAMJaQteewB9AAAAAA==.Frostbite:BAAALgADCgIJAgAAAA==.',
Ga='Gamaikuba:BAAALgADCggJCQAAAA==.Gamarth:BAAALgAECgYJDQAAAA==.Gatlu:BAABLgAECn8hAAIYAAkJcBYzDQAOAgAYAAkJcBYzDQAOAgAAAA==.Gato:BAAALgADCgIJAgAAAA==.Gawdsmackk:BAAALgAECgcJDQAAAA==.Gaz:BAAALgADCgMJAwAAAA==.Gazokks:BAAALgADCgcJBwAAAA==.',
Ge='Gedank:BAAALgADCgcJBwAAAA==.Geodemon:BAAALgAECgQJBAAAAA==.Gethealed:BAAALgAECgcJEAAAAA==.Getrektpos:BAAALgADCgMJAwAAAA==.',
Gh='Ghostlock:BAABLgAECn8VAAIMAAgJzxn2BQAFAgAMAAgJzxn2BQAFAgAAAA==.Ghoztface:BAABLgAECn8oAAMhAAcJcxzHDgDYAQAhAAYJXCDHDgDYAQAFAAcJJxLqmgA/AQAAAA==.Ghöstbeef:BAAALgADCgkJEAABLgAECggJGgAEALkXAA==.',
Gi='Giblock:BAABLgAECn8XAAIMAAgJCBRODwBoAQAMAAgJCBRODwBoAQAAAA==.',
Gl='Glamour:BAAALgAECgQJEAAAAA==.Glitterboy:BAAALgAECgIJAgABLgAFFAgJIwAZACIfAA==.',
Go='Golomojek:BAABLgAECn8UAAIgAAgJGwp3RQAeAQAgAAgJGwp3RQAeAQAAAA==.Gorkun:BAAALgADCgkJDgAAAA==.Gov:BAACLgAFFH8XAAMPAAYJtR7eEAAcAQAGAAYJIR2DPAA0AQAPAAUJfhXeEAAcAQAuAAQKfygAAwYACQm/JYsIAEUDAAYACQm/JYsIAEUDAA8AAQlSEjpsADkAAAAA.Govndrag:BAAALgADCgEJAQAAAA==.Govs:BAACLgAFFH8GAAQEAAMJohhtIwCgAAAEAAIJBiJtIwCgAAASAAIJcha8LACYAAAiAAIJdghwQAB4AAAuAAQKfxUAAwQACAmVHqAPAG4CAAQACAmVHqAPAG4CABIAAwmVHgxYALQAAAAA.',
Gr='Gralmerte:BAACLgAFFH8GAAIVAAMJgiK3AAD3AAAVAAMJgiK3AAD3AAAuAAQKfzYAAxUACQnNIu4BABYDABUACQnNIu4BABYDACMAAQn3FIfGADwAAAAA.Grawfern:BAAALgAECgkJEgAAAA==.Graygoyle:BAABLgAECn8hAAIXAAkJSgb8DABbAQAXAAkJSgb8DABbAQAAAA==.Groggaris:BAAALgAECgMJAwAAAA==.Groosalugg:BAABLgAECn8dAAIeAAkJtx2KKwAvAgAeAAkJtx2KKwAvAgAAAA==.',
Gu='Guillotine:BAAALgAECgEJAQAAAA==.Guldave:BAAALgAECgQJBAAAAA==.Guthrie:BAABLgAECn8WAAIJAAcJ2BcxKgC9AQAJAAcJ2BcxKgC9AQAAAA==.',
Gw='Gwyndolïn:BAABLgAECn8dAAMDAAcJrhiEMAC4AQADAAcJrhiEMAC4AQAZAAQJnAR6bQB3AAAAAA==.',
Ha='Hachendis:BAAALgADCgMJAwAAAA==.Haether:BAABLgAECn8tAAIfAAkJdBHmLQD/AQAfAAkJdBHmLQD/AQAAAA==.Haiku:BAAALgAECgEJAQAAAA==.Haliax:BAAALgAECgEJAQABLgAECgkJGAAFAE0hAA==.Hammatime:BAAALgADCgcJBwAAAA==.Hatsu:BAABLgAECn8VAAIDAAkJSgxCPAB/AQADAAkJSgxCPAB/AQAAAA==.Hawktuahh:BAAALgAECgIJAgAAAA==.',
He='Hellá:BAAALgADCgIJAgAAAA==.Hemandunter:BAAALgAECgEJAQAAAA==.',
Hi='Hildunn:BAAALgAECgQJBgAAAA==.Hingedh:BAABLgAFFH8FAAIGAAMJ9g6uJwCjAAAGAAMJ9g6uJwCjAAABLgAFFAcJIgAdAMccAA==.Hitemup:BAAALgADCgQJBAAAAA==.',
Hk='Hktanker:BAAALgADCgQJBAABLgAECgYJFgAeAI8KAA==.',
Ho='Holylentlezz:BAAALgADCgcJBwABLgAECgkJLwAaAGUfAA==.Holymun:BAABLgAECn8ZAAIFAAgJIxBicwCHAQAFAAgJIxBicwCHAQAAAA==.Holyox:BAABLgAECn83AAIFAAkJngxedgCBAQAFAAkJngxedgCBAQAAAA==.Hotcheeto:BAAALgAECgcJCQAAAA==.',
Ht='Hturtle:BAAALgADCgEJAQAAAA==.Hturtledk:BAABLgAECn8VAAMCAAYJvxaHnwAtAQACAAYJvxaHnwAtAQAWAAEJ3QJYawAUAAAAAA==.',
Hu='Hug:BAAALgAECgUJCAAAAA==.',
['Hü']='Hüntress:BAAALgAFFAEJAgAAAA==.',
Ia='Iacey:BAAALgAECgIJAgAAAA==.',
Im='Imdatroll:BAACLgAFFH8IAAMjAAMJSBN4NwDPAAAjAAMJSBN4NwDPAAAVAAIJrxOqFQCDAAAuAAQKfzIABBUACQneIzYCADEDABUACQneIzYCADEDACMABgkUGRhZAC0BAAoAAgndC9RyAGEAAAAA.Imgibby:BAAALgADCgYJBgABLgAECggJFwAMAAgUAA==.Impius:BAAALgAECgkJCgAAAA==.Impmageddon:BAABLgAECn8aAAMTAAkJnRF5ZQBzAQATAAkJnRF5ZQBzAQAUAAEJAAASdQAwAAAAAA==.',
In='Inexorable:BAABLgAFFH8GAAIFAAMJjxR7HwCwAAAFAAMJjxR7HwCwAAAAAA==.',
Ir='Irakwa:BAABLgAECn8UAAIeAAUJeQkDwgDDAAAeAAUJeQkDwgDDAAAAAA==.',
It='Itches:BAACLgAFFH8jAAIZAAgJIh8sAQChAgAZAAgJIh8sAQChAgAuAAQKfyAAAhkACAkHJOYDAE8DABkACAkHJOYDAE8DAAAA.',
Iw='Iwamori:BAAALgAECgEJAQAAAA==.',
Iz='Izánámi:BAABLgAECn8xAAQIAAgJYRLqHwCdAQAIAAgJYRLqHwCdAQAeAAEJ8A19ywA6AAAkAAEJlwGPmAAeAAAAAA==.',
Ja='Jagon:BAABLgAECn8pAAQlAAkJChryEQBTAgAlAAkJChryEQBTAgANAAIJtQdhNQBQAAAOAAIJHwzCJQA0AAAAAA==.Jalen:BAAALgAECgYJBgAAAA==.Janvi:BAAALgADCgUJBAAAAA==.Jarbito:BAAALgAECgUJCwAAAA==.Jarico:BAAALgAECgYJCgABLgAECgYJEgAHAAAAAA==.Jasint:BAAALgAECgUJBQABLgAECgkJKQAlAAoaAA==.',
Je='Jebrogue:BAAALgADCgkJDgAAAA==.',
Jh='Jhunts:BAAALgAECggJEAAAAA==.',
Ji='Jinbloom:BAAALgADCgIJAgAAAA==.Jincrush:BAAALgAECgIJAgAAAA==.Jindabutt:BAABLgAECn8mAAIQAAkJYyAXBgDbAgAQAAkJYyAXBgDbAgAAAA==.Jinfuse:BAAALgADCgUJBQAAAA==.Jintonic:BAAALgAECgcJCAAAAA==.',
Jk='Jkbalo:BAAALgAFFAIJBAAAAA==.Jkrlos:BAAALgAFFAMJBAAAAA==.',
Jo='Jocommande:BAAALgAECgEJAQAAAA==.Jointheraid:BAAALgADCgMJAwAAAA==.Jokerstree:BAAALgADCgYJBgAAAA==.Jorah:BAAALgADCgcJCgAAAA==.Jorkah:BAAALgADCgcJCgAAAA==.',
Jp='Jpdh:BAACLgAFFH8TAAMbAAQJZSO6BAAnAQAGAAQJLSM+LwBpAQAbAAMJ2yK6BAAnAQAuAAQKfygABBsACQl3JKQEAHACAAYACQlSH2wYAMMCABsACAk8JaQEAHACAA8ABAkyF49EAOQAAAAA.Jphunt:BAAALgADCgUJBQABLgAFFAQJEwAbAGUjAA==.',
Ju='Juddory:BAABLgAECn8jAAIRAAgJ8AuAqQAsAQARAAgJ8AuAqQAsAQAAAA==.Junksvil:BAAALgAECgYJEgAAAA==.',
['Jø']='Jøhnwick:BAAALgADCgYJBgAAAA==.',
Ka='Kahrahkon:BAAALgAECgQJDgAAAA==.Kalinis:BAAALgAECgIJAwAAAA==.Kanadoria:BAAALgAECgEJAQAAAA==.Kanion:BAAALgAECgYJCgAAAA==.Kargorr:BAAALgAECgIJAgAAAA==.',
Ke='Kenth:BAAALgAECgEJAQAAAA==.',
Kh='Khudoz:BAAALgAECgMJBwAAAA==.',
Ki='Killerelf:BAAALgADCggJCAAAAA==.Killshotz:BAAALgADCgUJBQAAAA==.Kismët:BAAALgAECgEJAQAAAA==.',
Kl='Klid:BAAALgADCgMJAwABLgAFFAIJBQAFAIIUAA==.',
Ko='Koa:BAAALgAECgEJAQAAAA==.Kooch:BAAALgADCgYJBgAAAA==.Korinth:BAECLgAFFH8eAAIhAAYJZhY9CQDiAAAhAAYJZhY9CQDiAAAuAAQKfz0AAiEACQnnG10HAGkCACEACQnnG10HAGkCAAAA.',
Kr='Kriaalis:BAABLgAECn8UAAMfAAkJXwTEegDvAAAfAAgJ9APEegDvAAAgAAEJqgVZwwAZAAAAAA==.',
Ku='Kurzon:BAAALgADCgMJAwABLgAECgkJHQAeALcdAA==.',
Ky='Kyra:BAAALgAECgUJDgAAAA==.',
['Kæ']='Kælas:BAAALgAECgEJAgAAAA==.',
La='Lachryma:BAAALgADCgUJBQAAAA==.Laríssa:BAEBLgAFFH8FAAISAAUJ2AW1IgDeAAASAAUJ2AW1IgDeAAAAAA==.Lazuli:BAAALgAECgYJBgABLgAECgkJQAAPAAskAA==.',
Le='Legault:BAABLgAECn8rAAImAAkJIB9pAQDmAgAmAAkJIB9pAQDmAgAAAA==.Legionofboom:BAAALgADCgQJBgAAAA==.Lethfel:BAABLgAECn8VAAMTAAgJ4xs6WgCPAQATAAYJYBw6WgCPAQAUAAYJlRbkIABNAQAAAA==.Lethferal:BAAALgADCgIJAgAAAA==.',
Li='Liacci:BAAALgADCgYJBgAAAA==.Lilgoukii:BAAALgADCgIJAgAAAA==.Lillithfaust:BAAALgAECgMJBgAAAA==.Limbø:BAABLgAECn8eAAIRAAcJLCFVSQD/AQARAAcJLCFVSQD/AQAAAA==.Lindia:BAAALgADCgEJAQAAAA==.Lionfury:BAAALgADCgcJBwAAAA==.Liquidturtle:BAAALgAECgMJBAAAAA==.Livie:BAABLgAECn8oAAIFAAkJlBgSNQAsAgAFAAkJlBgSNQAsAgAAAA==.',
Lo='Lonelylad:BAAALgAECgEJAQAAAA==.Loneshark:BAAALgAECgYJCQAAAA==.Longwood:BAAALgAECgYJCAAAAA==.Lonon:BAAALgADCgQJBAAAAA==.Loops:BAAALgAECgIJAwAAAA==.Loraddesmos:BAABLgAECn9CAAIUAAkJaxT+BgDrAQAUAAkJaxT+BgDrAQAAAA==.Loriah:BAABLgAECn8wAAIFAAkJShXVRwDvAQAFAAkJShXVRwDvAQAAAA==.Lovan:BAAALgAECgEJAwAAAA==.',
Lu='Lucance:BAAALgADCgkJDwAAAA==.Lullaby:BAABLgAECn8uAAIEAAkJhRcQFgAiAgAEAAkJhRcQFgAiAgAAAA==.Lumot:BAAALgADCgcJCwAAAA==.',
Ma='Maeg:BAAALgAECgIJAgABLgAFFAMJCAAjAEgTAA==.Maireldps:BAAALgAECgEJAQAAAA==.Marcdofu:BAAALgAECgMJAwAAAA==.Maryjanè:BAAALgAECgUJBQAAAA==.Mataquay:BAAALgAECggJEAAAAA==.Maveloris:BAAALgADCgcJBgAAAA==.Mawzshallah:BAACLgAFFH8cAAIKAAUJrySCEACiAQAKAAUJrySCEACiAQAuAAQKfzMAAwoACQllJWgBAMEDAAoACQllJWgBAMEDABgABQl6FLMTADQBAAAA.Mayli:BAAALgAFFAMJAwAAAA==.',
Mc='Mctanker:BAABLgAECn8aAAMhAAcJUBGKHQApAQAhAAcJUBGKHQApAQAFAAUJBgtb9wDCAAAAAA==.',
Me='Meascii:BAACLgAFFH8RAAIiAAUJlwn8AgALAQAiAAUJlwn8AgALAQAuAAQKfyQAAiIACQlaGRQOAIwCACIACQlaGRQOAIwCAAAA.Medeaeris:BAAALgADCgIJAgAAAA==.Meepmorp:BAAALgAECgEJAQAAAA==.Merc:BAACLgAFFH8iAAIZAAcJgyDYAgAuAgAZAAcJgyDYAgAuAgAuAAQKfzoAAhkACQksI5kFAPcCABkACQksI5kFAPcCAAAA.',
Mi='Millee:BAABLgAECn8fAAMEAAgJFhp8GAAJAgAEAAgJFhp8GAAJAgASAAIJpgO/hQA0AAAAAA==.Mincebeef:BAAALgAECgMJAwABLgAECggJGgAEALkXAA==.Mindpuck:BAAALgAECgQJBAAAAA==.Mirefighter:BAAALgADCggJCgABLgAFFAYJHwAVAB8dAA==.Miremana:BAAALgAECgcJDwABLgAFFAYJHwAVAB8dAA==.Mirespike:BAACLgAFFH8fAAIVAAYJHx08AwCZAQAVAAYJHx08AwCZAQAuAAQKfzIAAhUACQlSIpkDAPgCABUACQlSIpkDAPgCAAAA.Mistylady:BAAALgADCgIJBAAAAA==.',
Mo='Mommacougar:BAAALgADCgEJAQAAAA==.Moondrade:BAAALgAECgEJAQAAAA==.Moosebearowl:BAAALgAFFAIJAgAAAA==.Morfirrann:BAAALgADCgEJAQAAAA==.Morlis:BAAALgAECgQJBgAAAA==.Morlock:BAABLgAECn8rAAMTAAkJvQtZWgCPAQATAAkJvQtZWgCPAQAMAAEJWwgfNQAxAAAAAA==.Morningstahr:BAAALgAECgUJBQAAAA==.',
Mu='Murlen:BAAALgAECgMJBAAAAA==.',
My='Mystris:BAAALgADCgYJBgAAAA==.Mythidru:BAAALgAECgcJDgAAAA==.',
['Mâ']='Mâjestic:BAAALgADCgMJAwAAAA==.',
Na='Naanbread:BAAALgAECgQJBAAAAA==.Naaruto:BAABLgAECn8aAAIFAAgJzQ6/iwBZAQAFAAgJzQ6/iwBZAQAAAA==.Nadia:BAABLgAECn8XAAQiAAYJwQy0PwAMAQAiAAYJmQu0PwAMAQAEAAUJBAl2TQCtAAASAAMJ9gJXeABPAAAAAA==.Nanako:BAABLgAECn8zAAIRAAkJrxiPAgBIAQARAAkJrxiPAgBIAQAAAA==.Naughtyvixen:BAAALgAECgMJAgABLgAECgMJAwAHAAAAAA==.Naughtyvoked:BAAALgAECgYJCgABLgAECgMJAwAHAAAAAA==.Navali:BAAALgAECgMJCAABLgAFFAEJAQAHAAAAAA==.',
Ne='Nefer:BAAALgADCgUJBQAAAA==.Nevicus:BAAALgAECgIJAwAAAA==.',
Ni='Nickayla:BAAALgADCggJCAAAAA==.Nikkaya:BAAALgADCgYJBgABLgAECgYJGwAYABwaAA==.Nimblecow:BAAALgAECgUJBQAAAA==.Nisdenar:BAAALgADCgkJDgAAAA==.',
No='Noobacleese:BAABLgAECn8wAAIFAAkJrxvvLABNAgAFAAkJrxvvLABNAgAAAA==.Noraviae:BAAALgADCgMJAwAAAA==.Nowahki:BAAALgAECgEJAQAAAA==.',
Nu='Nutbustin:BAABLgAECn8hAAIRAAkJBhnvQAAZAgARAAkJBhnvQAAZAgAAAA==.',
Ny='Nyghtrider:BAABLgAECn8WAAIeAAYJjwqhoQD+AAAeAAYJjwqhoQD+AAAAAA==.Nykayla:BAAALgAECgcJAwAAAA==.Nymëra:BAABLgAECn8fAAIfAAkJ7w3EAwCyAAAfAAkJ7w3EAwCyAAAAAA==.Nyneeve:BAABLgAECn87AAISAAkJThMAHADlAQASAAkJThMAHADlAQAAAA==.',
Ob='Obscené:BAAALgAECgQJBAAAAA==.',
Od='Oddessyee:BAAALgADCgcJBwABLgAECggJGAAeAPUYAA==.Oddiee:BAABLgAECn8YAAMCAAcJNw/ArAAZAQACAAcJNw/ArAAZAQAWAAQJzgP0OQB0AAABLgAECggJGAAeAPUYAA==.Odinshunter:BAAALgAECgYJBgAAAA==.Odst:BAAALgADCgUJBwABLgAFFAQJBwACAIoZAA==.',
Oh='Ohdatroll:BAAALgAFFAIJBAABLgAFFAMJCAAjAEgTAA==.',
Ol='Olgrin:BAAALgADCgkJEgABLgAECgYJBwAHAAAAAA==.',
On='Onepunch:BAAALgAECgEJAQAAAA==.Oneslice:BAAALgAECgUJBgAAAA==.Onyxstar:BAAALgAECgEJAQAAAA==.',
Op='Opera:BAAALgAECgQJBgAAAA==.',
Or='Orikkosh:BAABLgAECn8fAAMQAAcJ0haWJQCBAQAQAAcJ0haWJQCBAQAZAAIJuwpCcQBNAAAAAA==.Orw:BAAALgAECgIJAgAAAA==.',
Ot='Otsmayo:BAAALgAECgkJBwAAAA==.',
Pa='Palel:BAABLgAECn83AAIJAAkJLRHYKwCyAQAJAAkJLRHYKwCyAQAAAA==.Palpatinee:BAAALgAECgQJBAAAAA==.Pancetta:BAAALgAECgEJAQABLgAECgkJQAAPAAskAA==.Parabelum:BAAALgAECgIJAgAAAA==.',
Pb='Pbfearz:BAABLgAECn8WAAMTAAYJhh8TWAC/AQATAAUJhh8TWAC/AQAUAAEJAADsXgBSAAAAAA==.',
Pe='Peguelo:BAAALgADCgIJAgAAAA==.Pendrágon:BAAALgAECgIJAgAAAA==.Percocetpete:BAACLgAFFH8NAAIEAAUJBRcUEABTAQAEAAUJBRcUEABTAQAuAAQKfx4AAwQACAnaJCQCAE8DAAQACAnaJCQCAE8DABIAAgkmDop5AEwAAAAA.Peregrine:BAAALgADCgMJAwAAAA==.',
Ph='Phaet:BAACLgAFFH8fAAMTAAYJAyLkLQCOAQATAAYJAyLkLQCOAQAUAAEJiw5oFQBUAAAuAAQKfzUAAhMACQnxJHQJADMDABMACQnxJHQJADMDAAAA.Phatty:BAAALgADCgMJAwAAAA==.Phaux:BAAALgAECgIJAgAAAA==.Philipp:BAABLgAECn8gAAIKAAkJDwrqLgBlAQAKAAkJDwrqLgBlAQAAAA==.',
Pi='Picco:BAAALgADCgEJAQABLgAECgUJCQAHAAAAAA==.Pixistix:BAAALgAFFAEJAQAAAA==.',
Pl='Plâgue:BAABLgAECn8bAAICAAkJ4xpbTADdAQACAAkJ4xpbTADdAQAAAA==.',
Pn='Pneuma:BAAALgADCgEJAQAAAA==.',
Po='Potentialman:BAAALgAECggJDAAAAA==.',
Pr='Preprot:BAAALgADCgkJCQABLgAECgkJJwAWADoVAA==.Prot:BAAALgAFFAEJAQAAAA==.',
Pu='Punslug:BAAALgAECgYJCgABLgAFFAIJBgAVAM4aAA==.',
['Pó']='Pókóu:BAAALgADCgMJAwAAAA==.',
Ra='Radiance:BAAALgAECgcJBwAAAA==.Raezorian:BAAALgAECggJDgABLgAECgkJNQAZANoiAA==.Rahmo:BAAALgADCgYJBgAAAA==.Rainforest:BAABLgAECn8bAAIYAAYJHBrsGwBuAQAYAAYJHBrsGwBuAQAAAA==.Rakiji:BAAALgAECgEJAQAAAA==.Ralphh:BAAALgADCgIJAgAAAA==.Ramdem:BAAALgAECggJEAAAAA==.Ramden:BAABLgAECn84AAIFAAkJQwvBdACEAQAFAAkJQwvBdACEAQAAAA==.Rampant:BAACLgAFFH8HAAICAAQJihmzTgBVAQACAAQJihmzTgBVAQAuAAQKfxcAAwIACQkXIEMfAI0CAAIACQkXIEMfAI0CABYAAQmVIBZPAFYAAAAA.Rampscii:BAAALgAECgQJBQABLgAFFAQJBwACAIoZAA==.Randalore:BAAALgAECgMJAwABLgAFFAMJCAAjAEgTAA==.Randwulf:BAAALgAECggJEwAAAA==.Ranwong:BAAALgAECgQJCgAAAA==.Ratherton:BAACLgAFFH8gAAIRAAUJjR6ORABfAQARAAUJjR6ORABfAQAuAAQKfysAAxEACQmbIO0wAK8CABEACQmbIO0wAK8CACcAAwnRHM8NAOkAAAAA.Rathtard:BAABLgAECn8XAAIeAAkJ3BqMIQBfAgAeAAkJ3BqMIQBfAgABLgAFFAUJIAARAI0eAA==.Rauloso:BAAALgAECgQJEQAAAA==.Ravìn:BAAALgAECgYJDAAAAA==.Rayne:BAAALgAECgcJCAABLgAFFAEJAQAHAAAAAA==.',
Rd='Rdata:BAAALgADCgYJBgAAAA==.',
Re='Relentlezz:BAAALgADCgMJAwABLgAECgkJLwAaAGUfAA==.Resoluteone:BAABLgAECn9MAAIWAAkJkhVjEQD2AQAWAAkJkhVjEQD2AQAAAA==.Retnu:BAAALgADCggJEAAAAA==.Revytwohand:BAACLgAFFH8fAAMZAAYJERwpCwBvAQAZAAUJxSApCwBvAQADAAUJjgzPNADYAAAuAAQKfzQAAhkACQmXJUoEABUDABkACQmXJUoEABUDAAAA.',
Rh='Rhagul:BAAALgAFFAIJAgAAAA==.Rhok:BAAALgADCgEJAQAAAA==.Rhokhard:BAAALgADCgEJAwAAAA==.',
Ro='Rocketarena:BAAALgAECgcJDwAAAA==.Rootytooty:BAAALgAECgIJAgAAAA==.Rozelie:BAABLgAFFH8HAAIKAAMJ4hI0MQC9AAAKAAMJ4hI0MQC9AAABLgAFFAcJHgAiAH8aAA==.',
Ry='Ryzarapriest:BAAALgAECgMJBAABLgAFFAEJAQAHAAAAAA==.',
Sa='Sabeladys:BAABLgAECn8oAAIFAAkJRCHLFQDAAgAFAAkJRCHLFQDAAgAAAA==.Sadpeepo:BAAALgADCgIJAgAAAA==.Saifir:BAABLgAECn8pAAIfAAkJBRHuOADMAQAfAAkJBRHuOADMAQAAAA==.Sardmongo:BAAALgADCgcJCgAAAA==.Sardogobo:BAAALgAECgEJAQABLgAECggJIgATAIEUAA==.Sarduccini:BAABLgAECn8iAAITAAgJgRTaTADiAQATAAgJgRTaTADiAQAAAA==.Sargeros:BAAALgAECgQJBAAAAA==.',
Se='Sebastîan:BAAALgAECgEJAQABLgAECgkJHgATAD8XAA==.Sekhmet:BAAALgAECgcJCAAAAA==.Sekio:BAAALgAECgYJCwAAAA==.',
Sh='Shadowpriest:BAAALgADCgEJAQAAAA==.Shamburgyr:BAAALgAECgMJAwABLgAECggJJwAeAMMQAA==.Shanàs:BAAALgAECgEJAQABLgAECgkJGwAFAEYeAA==.Sharayu:BAAALgADCgQJBAAAAA==.Sheamus:BAAALgADCgkJCQAAAA==.Shiftken:BAAALgAECgMJAwAAAA==.Shiftyfive:BAAALgAFFAMJAwAAAA==.Shivà:BAAALgADCgUJCAAAAA==.',
Si='Sigrodah:BAACLgAFFH8PAAMlAAUJ9g8pNQDuAAAlAAQJ9g8pNQDuAAANAAEJswG2LAA1AAAuAAQKfxkAAyUACAlTH9cRAF0CACUACAlTH9cRAF0CAA4ABAm2EW4pANQAAAAA.Silvalus:BAAALgAECgYJBwAAAA==.Sin:BAAALgAECgkJCQAAAA==.',
Sk='Skaara:BAAALgAECgQJBwAAAA==.Skara:BAAALgADCgEJAQAAAA==.Skiddles:BAAALgADCgIJAgAAAA==.Skinwalker:BAAALgADCgYJCgAAAA==.Skithyryx:BAAALgADCgIJAgAAAA==.Skor:BAAALgADCgQJBAAAAA==.Skyblue:BAAALgAECgEJAQAAAA==.Skyeforce:BAAALgAECgMJBQAAAA==.',
Sl='Slipknoth:BAABLgAECn8UAAMJAAYJkRmEUwAsAQAJAAUJFheEUwAsAQAFAAYJoRIQuAAVAQAAAA==.',
Sm='Smellyy:BAAALgADCgEJAQAAAA==.Smoketurtle:BAAALgAECgUJCAAAAA==.',
Sn='Sno:BAAALgAECgEJAQAAAA==.',
So='Socatoas:BAABLgAECn8YAAIBAAkJtgloNQBzAQABAAkJtgloNQBzAQAAAA==.Softbanana:BAAALgADCgEJAQAAAA==.Soi:BAAALgAECgYJCgABLgAECgkJGAAFAE0hAA==.Solarion:BAAALgAECgEJAQABLgAECgYJEwAdAAEQAA==.Sonoforak:BAAALgAECgYJBwAAAA==.',
Sp='Sped:BAABLgAECn8zAAQaAAkJih8fBQDKAgAaAAkJih8fBQDKAgAoAAUJswhvLwB6AAABAAEJ9wP3rgAtAAAAAA==.',
St='Stalrun:BAAALgAECgYJCgABLgAECgYJEgAHAAAAAA==.Staraleena:BAAALgAECgUJBQAAAA==.Stormeyes:BAAALgAECgMJAQABLgAECggJIwAhAOoaAA==.Stormslight:BAABLgAECn8jAAIhAAgJ6hrfDAD3AQAhAAgJ6hrfDAD3AQAAAA==.Stormsteel:BAAALgAECgMJBQAAAA==.Stôrmrägé:BAAALgAECgcJDQAAAA==.',
Sw='Swgchainz:BAAALgAECgcJEwABLgAECgkJLQAPADEdAA==.Swiftdéath:BAAALgAECgYJCgAAAA==.Swtbabybilly:BAAALgAECgYJCQAAAA==.',
Sy='Sylvänäs:BAAALgAECgEJAQAAAA==.',
['Sä']='Säberdh:BAAALgADCgYJBgABLgAECgMJAwAHAAAAAA==.',
['Så']='Såran:BAAALgAECgUJCwAAAA==.',
['Sí']='Sílence:BAABLgAECn8UAAIKAAcJvAgQSADsAAAKAAcJvAgQSADsAAAAAA==.',
['Sô']='Sôlrïx:BAAALgAECgUJCgAAAA==.',
Ta='Tabio:BAAALgADCgYJBgAAAA==.Tabito:BAAALgAECgEJAQAAAA==.Talas:BAABLgAECn8wAAIhAAkJnRYtDgDhAQAhAAkJnRYtDgDhAQAAAA==.Taltaelen:BAAALgADCgYJBgABLgAECgkJHQACAM0UAA==.Tamarack:BAABLgAECn8XAAIeAAYJshuJUQB0AQAeAAYJshuJUQB0AQAAAA==.',
Te='Teetsie:BAAALgAFFAEJAQAAAA==.Tehmber:BAAALgAECgQJCAABLgAECgUJBwAHAAAAAA==.Tehmplar:BAAALgAECgUJBwAAAA==.Terrormisu:BAAALgAECgEJAQABLgAECggJGQAFAHEcAA==.',
Th='Thalorien:BAAALgADCgYJBgABLgAECgcJFwAJAIghAA==.Theboart:BAAALgAECgQJCQAAAA==.Thredron:BAABLgAFFH8HAAIJAAMJTAdeNwCQAAAJAAMJTAdeNwCQAAAAAA==.',
Ti='Tilted:BAAALgAECggJCQABLgAECgkJLgAEAIUXAA==.Timebarred:BAAALgAECgEJBAAAAA==.',
To='Tooru:BAACLgAFFH8XAAQeAAYJqhJYOwA2AQAeAAUJMhZYOwA2AQAIAAEJsg5YMQBNAAAkAAEJXwJYBgBDAAAuAAQKfzYABB4ACQm+IYsGACUDAB4ACQm+IYsGACUDAAgACAncEOQcALUBACQABgkWGT1LACUBAAAA.Tortiana:BAAALgAECgUJBQAAAA==.Tossko:BAAALgAECgIJAwABLgAECgQJDAAHAAAAAA==.',
Tr='Traefel:BAAALgAECgMJAwAAAA==.Traeflor:BAAALgAECgEJAQAAAA==.Traevok:BAAALgAECgEJAgAAAA==.Trailertrash:BAABLgAECn9EAAIRAAgJnB9SNwA7AgARAAgJnB9SNwA7AgAAAA==.Treebeef:BAACLgAFFH8dAAIjAAYJpAgyKwALAQAjAAYJpAgyKwALAQAuAAQKfzIAAyMACQkCG+0YAHACACMACQkCG+0YAHACAAoAAQnWA/GMACIAAAAA.Triena:BAAALgAECgQJBgAAAA==.Trirn:BAAALgADCgYJBgAAAA==.Trumpeter:BAAALgAECgQJCwAAAA==.Trywind:BAAALgAECgYJBgAAAA==.',
Ts='Tsukuyómi:BAAALgAECgEJAQAAAA==.',
Ty='Tyberos:BAABLgAECn8kAAQEAAgJqxzFDQB+AgAEAAgJ2BvFDQB+AgAiAAUJDBd+LwAkAQASAAMJpRf7XwCYAAAAAA==.Tydrielion:BAAALgAECgYJDgAAAA==.Typicaldrood:BAAALgAECgIJAgAAAA==.',
['Tí']='Tízzíts:BAAALgADCgYJBgAAAA==.',
Ul='Ullreich:BAABLgAECn8YAAIeAAcJVwspjgAjAQAeAAcJVwspjgAjAQAAAA==.Ulysius:BAACLgAFFH8IAAIFAAQJjROlRwAdAQAFAAQJjROlRwAdAQAuAAQKfysAAgUACQmWGV00AC8CAAUACQmWGV00AC8CAAAA.',
Un='Unfazed:BAAALgAECgEJAQAAAA==.Unicornslayr:BAABLgAECn8qAAIJAAkJTRYQKQDEAQAJAAkJTRYQKQDEAQAAAA==.',
Ur='Urund:BAAALgAECgYJDgAAAA==.',
Uw='Uwantsmoke:BAABLgAECn8eAAIeAAYJMwRmuwDPAAAeAAYJMwRmuwDPAAAAAA==.Uwantsmokee:BAAALgADCgMJAwAAAA==.',
Va='Valgroth:BAAALgAECgIJAwAAAA==.Valkisek:BAACLgAFFH8RAAIRAAQJxhD1XwAhAQARAAQJxhD1XwAhAQAuAAQKfxgAAhEABwnYFwqbAJ8BABEABwnYFwqbAJ8BAAAA.Valkonigen:BAAALgAECgEJAQAAAA==.Vallarfax:BAABLgAECn8rAAIeAAkJIx/XGACRAgAeAAkJIx/XGACRAgAAAA==.Vandro:BAABLgAECn8kAAMJAAkJlhhtHwAHAgAJAAkJlhhtHwAHAgAhAAYJ2grlLAC4AAAAAA==.Vantive:BAAALgAECgYJDwAAAA==.Vash:BAAALgAECgEJAQAAAA==.Vashdk:BAACLgAFFH8TAAIWAAYJvRm1FQA/AQAWAAYJvRm1FQA/AQAuAAQKfxUAAhYACAnEFn8QAAMCABYACAnEFn8QAAMCAAAA.Vashmonk:BAACLgAFFH8MAAIQAAQJzyPEFAB9AQAQAAQJzyPEFAB9AQAuAAQKfxUAAhAACQmcIUMMAHECABAACQmcIUMMAHECAAAA.Vashwar:BAAALgAECgYJBgAAAA==.',
Ve='Vedruid:BAAALgAECggJDwAAAA==.Velaric:BAABLgAECn8vAAMjAAkJyhvFFACkAgAjAAkJyhvFFACkAgAYAAEJ3gvzgQAfAAAAAA==.Velcyn:BAAALgADCgcJDgABLgAECgIJAgAHAAAAAA==.Veldoria:BAAALgAECgQJBgAAAA==.Veloe:BAAALgAECgIJAgAAAA==.Verath:BAAALgADCgEJAQAAAA==.Vespyr:BAABLgAECn8nAAIeAAgJwxBvAwAhAQAeAAgJwxBvAwAhAQAAAA==.Vewdoo:BAABLgAECn84AAIgAAkJtiS5AgBJAwAgAAkJtiS5AgBJAwAAAA==.',
Vi='Viejoverde:BAAALgAECgQJCAAAAA==.Vipul:BAAALgAECgYJDgAAAA==.Vizimir:BAAALgAECggJCQAAAA==.',
Vo='Voldune:BAAALgAECgIJAwAAAA==.',
['Vë']='Vëgetå:BAAALgADCgYJBwABLgAECgUJBQAHAAAAAA==.',
Wa='Waiwai:BAAALgAECgEJAgAAAA==.Warfarin:BAAALgAECgEJBAAAAA==.Wascii:BAABLgAECn8hAAIeAAkJGBV+NgADAgAeAAkJGBV+NgADAgABLgAFFAQJBwACAIoZAA==.Waxedthataxe:BAAALgAECgEJAQAAAA==.Waxesaxes:BAAALgAECgQJBwAAAA==.',
We='Weaken:BAAALgAECgUJCwAAAA==.Weskr:BAAALgADCgEJAQABLgAECggJJAAEAKscAA==.',
Wi='Wickedsinner:BAAALgADCgEJAQAAAA==.Wizkerbizkit:BAAALgAECgMJAwAAAA==.',
Wo='Wolvesbane:BAABLgAFFH8FAAIeAAUJbwAYqwBCAAAeAAUJbwAYqwBCAAAAAA==.',
Wy='Wyrmblood:BAAALgAECgcJDgABLgAECgkJLwASAJQjAA==.Wyrmfur:BAABLgAECn8eAAMYAAgJCCI8AABkAgAYAAgJCCI8AABkAgAVAAQJUh6gHwALAQAAAA==.Wyrmheal:BAABLgAECn8vAAISAAkJlCMhBgDwAgASAAkJlCMhBgDwAgAAAA==.Wyvvie:BAAALgADCgIJAgAAAA==.',
Xa='Xavil:BAAALgAECgEJAQAAAA==.Xavv:BAAALgADCgUJBQAAAA==.',
Xi='Xiba:BAAALgAECgQJBwAAAA==.',
Xl='Xle:BAAALgADCgIJAgAAAA==.',
Ya='Yakoff:BAAALgAECgIJAgAAAA==.Yamihime:BAABLgAECn81AAMPAAkJCxUuGQC4AQAPAAgJchYuGQC4AQAGAAkJvwvBXAByAQAAAA==.Yatiri:BAABLgAECn8ZAAMgAAgJxRI6LACUAQAgAAgJxRI6LACUAQAfAAEJQg6X3gAqAAAAAA==.',
Yo='Yoowuzsup:BAABLgAECn8aAAIgAAcJnBxHMAB+AQAgAAcJnBxHMAB+AQAAAA==.',
Yu='Yureimage:BAABLgAECn8WAAIRAAYJMAtZ1wDnAAARAAYJMAtZ1wDnAAAAAA==.',
Za='Zarthus:BAAALgAECggJAgAAAA==.',
Ze='Zeaket:BAACLgAFFH8mAAIIAAgJKR14AQBeAgAIAAgJKR14AQBeAgAuAAQKfy8AAggACQmSIhkBAGEDAAgACQmSIhkBAGEDAAAA.Zedsdeadd:BAAALgAECgYJDQAAAA==.Zephyr:BAABLgAECn8mAAIiAAcJDAhAAwB0AAAiAAcJDAhAAwB0AAABLgAECggJJwAeAMMQAA==.Zeçhs:BAABLgAECn8YAAIFAAkJTSFZFADxAgAFAAkJTSFZFADxAgAAAA==.',
Zi='Zinek:BAAALgAECgQJBQAAAA==.Zinra:BAAALgAECgUJCgAAAA==.',
Zo='Zoma:BAAALgADCgUJBgAAAA==.Zorcan:BAABLgAECn8oAAIMAAkJZxoLBQBBAgAMAAkJZxoLBQBBAgAAAA==.',
Zu='Zugzugz:BAAALgAECgEJAgAAAA==.Zulfilith:BAAALgAECgMJBQAAAA==.',
['Zà']='Zàrgothrax:BAAALgADCgYJDgAAAA==.',
['Zð']='Zðltrain:BAAALgAECgQJDAAAAA==.',
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
