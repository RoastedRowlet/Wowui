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

local lookup = {'Warrior-Fury','DeathKnight-Unholy','Monk-Mistweaver','Priest-Holy','Paladin-Retribution','DemonHunter-Devourer','Unknown-Unknown','Hunter-Survival','Paladin-Holy','Druid-Balance','DeathKnight-Frost','Hunter-BeastMastery','Warlock-Affliction','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Havoc','Monk-Brewmaster','Mage-Frost','Priest-Shadow','Warlock-Demonology','Warlock-Destruction','Druid-Feral','DeathKnight-Blood','Rogue-Assassination','Druid-Guardian','Monk-Windwalker','Warrior-Protection','DemonHunter-Vengeance','Shaman-Enhancement','Rogue-Subtlety','Shaman-Restoration','Shaman-Elemental','Paladin-Protection','Priest-Discipline','Druid-Restoration','Hunter-Marksmanship','Rogue-Outlaw','Mage-Arcane','Warrior-Arms',}
local provider = {region='US',realm='Madoran',name='US',type='weekly',zone=46,date='2026-06-27',data={Aa='Aarhus:BAAALgAECgUJCQAAAA==.Aaronmourne:BAAALgAECgQJBAABLgAECgkJGQABALYJAA==.Aaronyates:BAAALgADCgcJBwABLgAFFAUJDAACALQZAA==.',
Ac='Actualegirl:BAABLgAFFH8GAAIDAAUJLQRLNwDLAAADAAUJLQRLNwDLAAABLgAFFAUJDQAEAAUXAA==.',
Ad='Adversary:BAAALgADCgMJAwAAAA==.',
Ae='Aerfen:BAABLgAECn8cAAIFAAkJyg2QaQCcAQAFAAkJyg2QaQCcAQAAAA==.',
Ag='Agross:BAAALgADCgYJBgAAAA==.',
Ai='Aimforhead:BAAALgAECgcJDAAAAA==.',
Ak='Akiraha:BAAALgAECgMJAwAAAA==.',
Al='Alexas:BAAALgADCgcJCAAAAA==.Alric:BAABLgAECn80AAIGAAkJYxQeNQDyAQAGAAkJYxQeNQDyAQAAAA==.Alyndra:BAAALgADCgUJBQABLgAECgUJBQAHAAAAAA==.',
Am='Amideus:BAAALgAECgEJAQAAAA==.Amory:BAABLgAECn8mAAICAAkJ9x40IQCDAgACAAkJ9x40IQCDAgAAAA==.',
An='Angela:BAAALgADCgIJAgAAAA==.Annaesthetic:BAAALgAECgEJAwABLgAECgkJNAAIAIkUAA==.',
Ar='Arator:BAAALgADCgEJAgAAAA==.Araña:BAAALgAECgEJAQAAAA==.Arcatraz:BAAALgAECgEJAQAAAA==.Ardaddy:BAAALgAECgYJDQABLgAFFAMJBAAHAAAAAA==.Ardzak:BAAALgAFFAMJBAAAAA==.Arragorn:BAACLgAFFH8IAAIJAAQJFRl9HwAhAQAJAAQJFRl9HwAhAQAuAAQKfycAAgkACQktHLgZADkCAAkACQktHLgZADkCAAAA.',
As='Asendra:BAABLgAECn8mAAIKAAkJ6xnFEQBLAgAKAAkJ6xnFEQBLAgAAAA==.Assaran:BAAALgAECgIJAgAAAA==.Astal:BAACLgAFFH8LAAILAAUJlA/8DwAYAQALAAUJlA/8DwAYAQAuAAQKfx0AAgsACQmfGwkHACwCAAsACQmfGwkHACwCAAAA.',
At='Ate:BAAALgADCgYJBgABLgAECgkJKgAJAE0WAA==.Athenea:BAABLgAECn8aAAIBAAcJUBuYHwDyAQABAAcJUBuYHwDyAQAAAA==.Athénna:BAAALgADCgIJAgABLgAECggJLAAMAFwRAA==.Atulru:BAAALgADCgMJAwAAAA==.',
Av='Avyl:BAAALgADCgcJBwABLgAECgYJGwANAPsRAA==.',
Ay='Ayannar:BAAALgADCgEJAQAAAA==.',
Az='Azriella:BAAALgAECgkJBgAAAA==.Azuren:BAABLgAECn8xAAQOAAkJMgq9AQDhAAAOAAkJMgq9AQDhAAAPAAYJeQ3WEgDdAAAQAAEJ8wfCDwAdAAAAAA==.',
Ba='Baal:BAAALgAFFAIJAgAAAA==.Bacon:BAABLgAECn9CAAMRAAkJCyRPBQDtAgARAAkJCyRPBQDtAgAGAAcJKRvcSACsAQAAAA==.Bamboozled:BAABLgAECn8VAAMDAAgJbxNTLQDJAQADAAgJbxNTLQDJAQASAAUJ7ANQBACbAAAAAA==.Bandìt:BAAALgAECggJCwAAAA==.Bankai:BAAALgAFFAEJBAAAAA==.Barbieque:BAAALgADCgcJBwAAAA==.',
Be='Bearyden:BAAALgADCgEJAQAAAA==.Bedbugs:BAAALgAECgQJBAABLgAFFAUJIQATAI0eAA==.Beefstrasz:BAABLgAECn8aAAMEAAgJuRdiFAAzAgAEAAgJuRdiFAAzAgAUAAEJpwbTkgAoAAAAAA==.Beyla:BAACLgAFFH8HAAIFAAMJQQobegDBAAAFAAMJQQobegDBAAAuAAQKfycAAgUACQkFF4A1ACsCAAUACQkFF4A1ACsCAAAA.',
Bi='Bioactive:BAAALgADCgYJBgAAAA==.Bishamon:BAABLgAECn9OAAQVAAkJ+yHwBQBeAwAVAAkJ+yHwBQBeAwAWAAEJAADAaQA+AAANAAEJAADlMQA6AAAAAA==.Bizotch:BAAALgAECggJDgAAAA==.',
Bl='Bleau:BAABLgAECn8iAAIXAAkJbxCpEACtAQAXAAkJbxCpEACtAQAAAA==.Blethings:BAAALgAECgMJAwAAAA==.Blinktwice:BAAALgAECgEJAgAAAA==.Bloodimess:BAAALgADCgMJAwAAAA==.Bloodymary:BAABLgAECn8nAAIYAAkJOhXwEwDUAQAYAAkJOhXwEwDUAQAAAA==.Bluebarrie:BAAALgAECgEJAQAAAA==.Blôodräge:BAAALgAECgcJDgAAAA==.',
Bo='Bootelicious:BAAALgADCgIJAgAAAA==.Bouncybean:BAAALgADCgIJAgAAAA==.',
Br='Bradsupinya:BAABLgAECn8kAAITAAgJEBl7XgDEAQATAAgJEBl7XgDEAQAAAA==.Branchling:BAAALgAECgcJEgABLgAFFAUJIQATAI0eAA==.Brewswane:BAAALgAFFAEJAwABLgAFFAcJJAAZAGoWAA==.Bridh:BAABLgAECn8aAAIGAAkJFR5LEQD0AgAGAAkJFR5LEQD0AgABLgAFFAgJHwAWABIcAA==.Bromm:BAAALgAECgEJAQAAAA==.Brunor:BAAALgAECgkJCwAAAA==.',
Bu='Bulkamania:BAAALgAECgMJAwAAAA==.Butterkip:BAACLgAFFH8PAAIUAAUJfBSxFgAvAQAUAAUJfBSxFgAvAQAuAAQKfysAAhQACQlpHikKAOACABQACQlpHikKAOACAAAA.',
['Bë']='Bëarclaw:BAAALgAECgUJBQAAAA==.',
Ca='Cambria:BAAALgAECgMJAwAAAA==.Cantkillme:BAAALgAECgQJBwAAAA==.Canukillme:BAAALgADCgYJBgAAAA==.Carruel:BAAALgADCgUJBQAAAA==.Cazzc:BAAALgAECgUJCAAAAA==.',
Ce='Cellan:BAABLgAECn8WAAICAAcJ6wqKvQABAQACAAcJ6wqKvQABAQAAAA==.Censora:BAAALgAECgEJAQAAAA==.',
Ch='Chicharrones:BAAALgAECgUJBQABLgAECgkJQgARAAskAA==.Chickenshift:BAABLgAECn8lAAMaAAgJRCDwDAATAgAaAAcJXB/wDAATAgAXAAQJ4RjIHAAkAQAAAA==.Chipahoy:BAABLgAECn8nAAIFAAgJdRw/OAAhAgAFAAgJdRw/OAAhAgABLgAECggJRAATAJwfAA==.Chopahoe:BAAALgAECgQJBwAAAA==.Chuggz:BAABLgAECn8gAAIbAAkJ5xE1HwCzAQAbAAkJ5xE1HwCzAQAAAA==.',
Cl='Clamadin:BAAALgAECgIJAgABLgAFFAgJJQATAKccAA==.Clamius:BAACLgAFFH8lAAITAAgJpxwjDACOAgATAAgJpxwjDACOAgAuAAQKfyoAAhMACQkkJRALACEDABMACQkkJRALACEDAAAA.Cliff:BAAALgAECgUJBgAAAA==.',
Co='Colby:BAAALgAECgYJDgAAAA==.Coldass:BAABLgAECn8ZAAITAAgJwRJjZgCxAQATAAgJwRJjZgCxAQAAAA==.Commodus:BAAALgADCgQJBAAAAA==.Conduit:BAAALgAECgQJBQAAAA==.Coombrain:BAAALgAECgUJCQAAAA==.Cotopla:BAAALgAECgQJDAAAAA==.',
Cr='Critterzz:BAABLgAECn8aAAIEAAgJ4hb6FwAcAgAEAAgJ4hb6FwAcAgAAAA==.Cryptkeys:BAAALgAECgMJAwAAAA==.',
Cu='Cuziseeu:BAAALgAECgQJBAABLgAECgYJBgAHAAAAAA==.',
Da='Dachyy:BAAALgAECgYJEgAAAA==.Daemonwaters:BAAALgAECgEJAQAAAA==.Dagov:BAAALgAECgYJCAAAAA==.Daiana:BAAALgAECgIJAgAAAA==.Damage:BAAALgAFFAEJAQAAAA==.Darkråii:BAAALgAECgIJAwAAAA==.Dashboy:BAAALgADCgEJAQAAAA==.',
De='Deafniteelf:BAAALgAECgkJDQAAAA==.Deatharmonic:BAAALgAFFAIJBAAAAA==.Deathlentlez:BAABLgAECn8vAAIcAAkJZR86BwCSAgAcAAkJZR86BwCSAgAAAA==.Decaylentlez:BAAALgAECgEJAQABLgAECgkJLwAcAGUfAA==.Deepwinter:BAAALgAECgcJDQABLgAFFAUJDAACALQZAA==.Delphyne:BAABLgAECn8UAAIPAAYJ9wvxEQDrAAAPAAYJ9wvxEQDrAAAAAA==.Delylee:BAAALgAECgIJAgAAAA==.Demandred:BAAALgAECgcJDAAAAA==.Demonhunter:BAABLgAECn8gAAIRAAkJuhiWDgA8AgARAAkJuhiWDgA8AgAAAA==.Demonià:BAABLgAECn8ZAAITAAkJ7waFqQAsAQATAAkJ7waFqQAsAQAAAA==.Desong:BAAALgADCgYJBwAAAA==.Detharbinger:BAAALgAECgcJDQAAAA==.Dezzan:BAAALgADCgQJBwAAAA==.',
Di='Diamondsword:BAAALgAECggJDgAAAA==.Dieanah:BAAALgADCgcJBwAAAA==.',
Dj='Djazz:BAAALgAECgIJAgAAAA==.',
Do='Dochaze:BAABLgAECn8qAAMJAAkJfxyHHwAdAgAJAAgJPB+HHwAdAgAFAAMJjA1KIAGTAAAAAA==.Dogdimmadome:BAAALgAECgYJDwAAAA==.Dolore:BAAALgADCgcJBgAAAA==.Doublejump:BAAALgAECgEJAQABLgAECgkJJwAYADoVAA==.',
Dr='Dragone:BAAALgAECgUJCQAAAA==.Dragun:BAAALgADCgUJBQABLgAECggJGwAFAJQQAA==.Drowsee:BAAALgAECgEJAQAAAA==.',
Du='Dumbdumb:BAAALgAECgQJBgAAAA==.',
Dy='Dyanuh:BAABLgAECn8eAAIUAAYJygJxDQBOAAAUAAYJygJxDQBOAAAAAA==.',
['Dà']='Dàrkscythe:BAABLgAECn8cAAMYAAcJmAVLPACgAAAYAAcJuQRLPACgAAALAAEJiQZqPwAoAAAAAA==.',
Ea='Eazywin:BAAALgAECggJCQAAAA==.',
Eh='Ehlsa:BAAALgADCgcJBwAAAA==.Ehlsi:BAABLgAECn8wAAMdAAkJUR/PAgDFAgAdAAkJUR/PAgDFAgARAAEJgxrwXwBNAAAAAA==.Ehress:BAAALgAECgcJEwABLgAFFAUJDAACALQZAA==.',
Ei='Eirinny:BAABLgAECn8tAAIeAAkJWQq6EwB9AQAeAAkJWQq6EwB9AQAAAA==.',
El='Elindez:BAABLgAECn8nAAIfAAkJUw+YGADVAQAfAAkJUw+YGADVAQAAAA==.Elyviel:BAAALgAFFAEJAQAAAA==.Elàine:BAABLgAECn80AAIMAAgJJgl9DgDVAAAMAAgJJgl9DgDVAAAAAA==.',
Em='Emika:BAAALgADCgUJDgAAAA==.Emyrson:BAAALgAECgQJCQAAAA==.',
En='Encantado:BAAALgAECgUJBQAAAA==.Enemywithin:BAAALgADCgIJAgAAAA==.Enzo:BAAALgADCgYJCwAAAA==.',
Ep='Epicfury:BAAALgAECgYJDgAAAA==.',
Eq='Eq:BAAALgADCgUJBgAAAA==.',
Ez='Ezmee:BAAALgAECgUJEAAAAA==.',
Fa='Facingworlds:BAAALgAECggJDgAAAA==.Fathercaleb:BAAALgAECgIJAwABLgAFFAYJHwAbABEcAA==.Fazed:BAAALgAECgIJBgAAAA==.Fazeo:BAAALgAECgIJAgAAAA==.',
Fe='Featherstep:BAAALgADCgMJAwAAAA==.Felysse:BAAALgADCgEJAQAAAA==.',
Fi='Fireball:BAAALgAECgIJAgABLgAFFAEJAQAHAAAAAA==.',
Fl='Flavio:BAAALgAECgQJCAAAAA==.',
Fo='Fortuna:BAABLgAECn8kAAIeAAkJxASQGQA4AQAeAAkJxASQGQA4AQAAAA==.',
Fr='Francesca:BAAALgADCgEJAQAAAA==.Frosilen:BAABLgAECn87AAMgAAkJCxDoQQCmAQAgAAkJCxDoQQCmAQAhAAMJaQtgewB9AAAAAA==.Frostbite:BAAALgADCgIJAgAAAA==.',
Ga='Gamaikuba:BAAALgADCggJCQAAAA==.Gamarth:BAAALgAECgYJDQAAAA==.Gatlu:BAABLgAECn8hAAIaAAkJcBYzDQAOAgAaAAkJcBYzDQAOAgAAAA==.Gawdsmackk:BAAALgAECggJDgAAAA==.Gaz:BAAALgADCgMJAwAAAA==.Gazokks:BAAALgADCgcJBwAAAA==.',
Ge='Gedank:BAAALgADCgcJBwAAAA==.Geodemon:BAAALgAECgQJBAAAAA==.Gethealed:BAAALgAECgcJEAAAAA==.Getrektpos:BAAALgADCgMJAwAAAA==.',
Gh='Ghostlock:BAABLgAECn8VAAINAAgJzxn2BQAFAgANAAgJzxn2BQAFAgAAAA==.Ghoztface:BAABLgAECn8oAAMiAAcJcxzHDgDYAQAiAAYJXCDHDgDYAQAFAAcJJxLmmgA/AQAAAA==.Ghöstbeef:BAAALgADCgkJEAABLgAECggJGgAEALkXAA==.',
Gi='Giblock:BAABLgAECn8XAAINAAgJCBRNDwBoAQANAAgJCBRNDwBoAQAAAA==.',
Gl='Glamour:BAAALgAECgQJEAAAAA==.Glitterboy:BAAALgAECgIJAgABLgAFFAgJIwAbACIfAA==.',
Go='Golomojek:BAABLgAECn8WAAIhAAkJuwp5RQAeAQAhAAkJuwp5RQAeAQAAAA==.Gorkun:BAAALgADCgkJDgAAAA==.Gov:BAACLgAFFH8XAAMRAAYJtR7gEAAcAQAGAAYJIR13PAA0AQARAAUJfhXgEAAcAQAuAAQKfygAAwYACQm/JYsIAEUDAAYACQm/JYsIAEUDABEAAQlSEjpsADkAAAAA.Govndrag:BAAALgADCgEJAQAAAA==.Govs:BAACLgAFFH8GAAQEAAMJohhuIwCgAAAEAAIJBiJuIwCgAAAUAAIJcha/LACYAAAjAAIJdghtQAB4AAAuAAQKfxUAAwQACAmVHqAPAG4CAAQACAmVHqAPAG4CABQAAwmVHhFYALQAAAAA.',
Gr='Gralmerte:BAACLgAFFH8JAAIXAAMJgiLZAQAGAQAXAAMJgiLZAQAGAQAuAAQKfzYAAxcACQnNIu4BABYDABcACQnNIu4BABYDACQAAQn3FIfGADwAAAAA.Grawfern:BAAALgAECgkJEgAAAA==.Graygoyle:BAABLgAECn8hAAIZAAkJSgb7DABbAQAZAAkJSgb7DABbAQAAAA==.Groggaris:BAAALgAECgMJAwAAAA==.Groosalugg:BAABLgAECn8dAAIMAAkJtx2KKwAvAgAMAAkJtx2KKwAvAgAAAA==.',
Gu='Guillotine:BAAALgAECgEJAQAAAA==.Guldave:BAAALgAECgQJBAAAAA==.Guthrie:BAABLgAECn8WAAIJAAcJ2BczKgC9AQAJAAcJ2BczKgC9AQAAAA==.',
Gw='Gwyndolïn:BAABLgAECn8eAAMDAAcJ6RiIMAC4AQADAAcJ6RiIMAC4AQAbAAQJnAR6bQB3AAAAAA==.',
Ha='Hachendis:BAAALgADCgMJAwAAAA==.Haether:BAABLgAECn8uAAIgAAkJdBHnLQD/AQAgAAkJdBHnLQD/AQAAAA==.Haliax:BAAALgAECgEJAQABLgAECgkJGAAFAE0hAA==.Hammatime:BAAALgADCgcJBwAAAA==.Hatsu:BAABLgAECn8VAAIDAAkJSgxFPAB/AQADAAkJSgxFPAB/AQAAAA==.Hawktuahh:BAAALgAECgIJAgAAAA==.',
He='Hellá:BAAALgADCgIJAgAAAA==.Hemandunter:BAAALgAECgEJAQAAAA==.',
Hi='Hildunn:BAAALgAECgQJBgAAAA==.Hingedh:BAABLgAFFH8FAAIGAAMJ9g6uJwCjAAAGAAMJ9g6uJwCjAAABLgAFFAcJIwAfAMccAA==.Hitemup:BAAALgADCgQJBAAAAA==.',
Hk='Hktanker:BAAALgADCgQJBAABLgAECgYJGAAMAKULAA==.',
Ho='Holylentlezz:BAAALgADCgcJBwABLgAECgkJLwAcAGUfAA==.Holymun:BAABLgAECn8bAAIFAAgJlBBdcwCHAQAFAAgJlBBdcwCHAQAAAA==.Holyox:BAABLgAECn83AAIFAAkJngxbdgCBAQAFAAkJngxbdgCBAQAAAA==.Hotcheeto:BAAALgAECgcJCwAAAA==.',
Ht='Hturtle:BAAALgADCgEJAQAAAA==.Hturtledk:BAABLgAECn8VAAMCAAYJvxaKnwAtAQACAAYJvxaKnwAtAQAYAAEJ3QJYawAUAAAAAA==.',
Hu='Hug:BAAALgAECgUJCAAAAA==.',
['Hü']='Hüntress:BAAALgAFFAEJAgAAAA==.',
Ia='Iacey:BAAALgAECgIJAgAAAA==.',
Im='Imdatroll:BAACLgAFFH8IAAMkAAMJSBNyNwDPAAAkAAMJSBNyNwDPAAAXAAIJrxOuFQCDAAAuAAQKfzIABBcACQneIzYCADEDABcACQneIzYCADEDACQABgkUGRZZAC0BAAoAAgndC9ZyAGEAAAAA.Imgibby:BAAALgADCgYJBgABLgAECggJFwANAAgUAA==.Impius:BAAALgAECgkJCgAAAA==.Impmageddon:BAABLgAECn8aAAMVAAkJnRF6ZQBzAQAVAAkJnRF6ZQBzAQAWAAEJAAASdQAwAAAAAA==.',
In='Inexorable:BAABLgAFFH8IAAIFAAMJjxR7HwCwAAAFAAMJjxR7HwCwAAAAAA==.',
Ir='Irakwa:BAABLgAECn8UAAIMAAUJeQkIwgDDAAAMAAUJeQkIwgDDAAAAAA==.',
It='Itches:BAACLgAFFH8jAAIbAAgJIh8sAQChAgAbAAgJIh8sAQChAgAuAAQKfyAAAhsACAkHJOYDAE8DABsACAkHJOYDAE8DAAAA.',
Iw='Iwamori:BAAALgAECgEJAQAAAA==.',
Iz='Izánámi:BAABLgAECn80AAQIAAgJiRQQAgAuAQAIAAgJiRQQAgAuAQAMAAEJ8A19ywA6AAAlAAEJlwGPmAAeAAAAAA==.',
Ja='Jagon:BAABLgAECn8vAAQQAAkJChpzAQCRAQAQAAkJChpzAQCRAQAOAAIJtQdgNQBQAAAPAAIJHwzCJQA0AAAAAA==.Jalen:BAAALgAECgYJBgAAAA==.Janvi:BAAALgAECgEJAQAAAA==.Jarbito:BAAALgAECgUJCwAAAA==.Jarico:BAAALgAECgYJDQABLgAECgYJEgAHAAAAAA==.Jasint:BAAALgAECgUJBQABLgAECgkJLwAQAAoaAA==.',
Je='Jebrogue:BAAALgADCgkJDgAAAA==.',
Jh='Jhunts:BAAALgAECggJEAAAAA==.',
Ji='Jinbloom:BAAALgADCgIJAgAAAA==.Jincrush:BAAALgAECgIJAgAAAA==.Jindabutt:BAABLgAECn8mAAISAAkJYyAXBgDbAgASAAkJYyAXBgDbAgAAAA==.Jinfuse:BAAALgADCgUJBQAAAA==.Jintonic:BAAALgAECgcJCAAAAA==.',
Jk='Jkbalo:BAAALgAFFAIJBAAAAA==.Jkrlos:BAAALgAFFAMJBAAAAA==.',
Jo='Jocommande:BAAALgAECgEJAQAAAA==.Jointheraid:BAAALgADCgMJAwAAAA==.Jokerstree:BAAALgADCgYJBgAAAA==.Jorah:BAAALgADCgcJCgAAAA==.Jorkah:BAAALgADCgcJCgAAAA==.',
Jp='Jpdh:BAACLgAFFH8UAAMdAAQJZSO6BAAnAQAGAAQJLSMsLwBpAQAdAAMJ2yK6BAAnAQAuAAQKfygABB0ACQl3JKQEAHACAAYACQlSH2wYAMMCAB0ACAk8JaQEAHACABEABAkyF49EAOQAAAAA.Jphunt:BAAALgADCgUJBQABLgAFFAQJFAAdAGUjAA==.',
Ju='Juddory:BAABLgAECn8jAAITAAgJ8AuEqQAsAQATAAgJ8AuEqQAsAQAAAA==.Junksvil:BAAALgAECgYJEgAAAA==.',
['Jø']='Jøhnwick:BAAALgADCgYJBgAAAA==.',
Ka='Kahrahkon:BAAALgAECgQJDgAAAA==.Kalinis:BAAALgAECgIJAwAAAA==.Kanadoria:BAAALgAECgEJAQAAAA==.Kanion:BAAALgAECgYJCgAAAA==.Kargorr:BAAALgAECgIJAgAAAA==.',
Ke='Kenth:BAAALgAECgEJAQAAAA==.',
Kh='Khudoz:BAAALgAECgMJBwAAAA==.',
Ki='Killerelf:BAAALgADCggJCAAAAA==.Killshotz:BAAALgADCgUJBQAAAA==.Kismët:BAAALgAECgEJAQAAAA==.',
Kl='Klid:BAAALgADCgMJAwABLgAFFAIJBQAFAIIUAA==.',
Ko='Koa:BAAALgAECgEJAQAAAA==.Kooch:BAAALgADCgYJBgAAAA==.Korinth:BAECLgAFFH8eAAIiAAYJZhY9CQDiAAAiAAYJZhY9CQDiAAAuAAQKfz0AAiIACQnnG10HAGkCACIACQnnG10HAGkCAAAA.Kovala:BAAALgAECgEJAQAAAA==.',
Kr='Kriaalis:BAABLgAECn8VAAMgAAkJSAXLegDvAAAgAAgJ+gTLegDvAAAhAAEJqgVbwwAZAAAAAA==.',
Ku='Kurzon:BAAALgADCgMJAwABLgAECgkJHQAMALcdAA==.',
Ky='Kyra:BAAALgAECgUJDwAAAA==.',
['Kæ']='Kælas:BAAALgAECgEJAgAAAA==.',
La='Lachryma:BAAALgADCgUJBQAAAA==.Laríssa:BAEBLgAFFH8JAAIUAAUJrg0LCADdAAAUAAUJrg0LCADdAAAAAA==.Lazuli:BAAALgAECgYJBgABLgAECgkJQgARAAskAA==.',
Le='Legault:BAABLgAECn8rAAImAAkJIB9pAQDmAgAmAAkJIB9pAQDmAgAAAA==.Legionofboom:BAAALgADCgQJBgAAAA==.Lethfel:BAABLgAECn8VAAMVAAgJ4xs4WgCPAQAVAAYJYBw4WgCPAQAWAAYJlRbkIABNAQAAAA==.Lethferal:BAAALgADCgIJAgAAAA==.',
Li='Liacci:BAAALgADCgYJBgAAAA==.Lilgoukii:BAAALgADCgIJAgAAAA==.Lillithfaust:BAAALgAECgMJBgAAAA==.Limbø:BAABLgAECn8eAAITAAcJLCFSSQD/AQATAAcJLCFSSQD/AQAAAA==.Lindia:BAAALgADCgEJAQAAAA==.Lionfury:BAAALgADCgcJBwAAAA==.Lionguard:BAAALgAECgEJAQAAAA==.Liquidturtle:BAAALgAECgMJBAAAAA==.Livie:BAABLgAECn8oAAIFAAkJlBgQNQAsAgAFAAkJlBgQNQAsAgAAAA==.',
Lo='Lonelylad:BAAALgAECgEJAQAAAA==.Loneshark:BAAALgAECgYJCQAAAA==.Longwood:BAAALgAECgYJCAAAAA==.Lonon:BAAALgADCgQJBAAAAA==.Loops:BAAALgAECgIJAwAAAA==.Loraddesmos:BAABLgAECn9DAAIWAAkJlhT+BgDrAQAWAAkJlhT+BgDrAQAAAA==.Loriah:BAABLgAECn8wAAIFAAkJShXTRwDvAQAFAAkJShXTRwDvAQAAAA==.Lovan:BAAALgAECgEJAwAAAA==.',
Lu='Lucance:BAAALgADCgkJDwAAAA==.Lullaby:BAABLgAECn8uAAIEAAkJhRcQFgAiAgAEAAkJhRcQFgAiAgAAAA==.Lumot:BAAALgADCgcJCwAAAA==.',
Ma='Maeg:BAAALgAECgIJAgABLgAFFAMJCAAkAEgTAA==.Maireldps:BAAALgAECgMJAwAAAA==.Manawarr:BAAALgADCgEJAQAAAA==.Marcdofu:BAAALgAECgMJAwAAAA==.Maryjanè:BAAALgAECgUJBQAAAA==.Mataquay:BAAALgAECggJEAAAAA==.Maveloris:BAAALgADCgcJBgAAAA==.Mawzshallah:BAACLgAFFH8dAAIKAAYJPSR2EACiAQAKAAYJPSR2EACiAQAuAAQKfzMAAwoACQllJWgBAMEDAAoACQllJWgBAMEDABoABQl6FLMTADQBAAAA.Mayli:BAAALgAFFAMJAwAAAA==.',
Mc='Mctanker:BAABLgAECn8aAAMiAAcJUBGKHQApAQAiAAcJUBGKHQApAQAFAAUJBgte9wDCAAAAAA==.',
Me='Meascii:BAACLgAFFH8WAAIjAAUJ6gp/CAAmAQAjAAUJ6gp/CAAmAQAuAAQKfyQAAiMACQlaGRMOAIwCACMACQlaGRMOAIwCAAAA.Medeaeris:BAAALgADCgIJAgAAAA==.Meepmorp:BAAALgAECgEJAQAAAA==.Merc:BAACLgAFFH8jAAIbAAgJLB7XAgAuAgAbAAgJLB7XAgAuAgAuAAQKfzoAAhsACQksI5kFAPcCABsACQksI5kFAPcCAAAA.',
Mi='Millee:BAABLgAECn8hAAMEAAgJZBx/GAAJAgAEAAgJZBx/GAAJAgAUAAIJpgPGhQA0AAAAAA==.Mincebeef:BAAALgAECgMJAwABLgAECggJGgAEALkXAA==.Mindpuck:BAAALgAECgQJBAAAAA==.Mirefighter:BAAALgADCggJCgABLgAFFAYJHwAXAB8dAA==.Miremana:BAAALgAECgcJDwABLgAFFAYJHwAXAB8dAA==.Mirespike:BAACLgAFFH8fAAIXAAYJHx09AwCZAQAXAAYJHx09AwCZAQAuAAQKfzIAAhcACQlSIpkDAPgCABcACQlSIpkDAPgCAAAA.Mistylady:BAAALgADCgIJBAAAAA==.',
Mo='Mommacougar:BAAALgADCgEJAQAAAA==.Moondrade:BAAALgAECgIJAgAAAA==.Moosebearowl:BAAALgAFFAIJAgAAAA==.Morfirrann:BAAALgADCgEJAQAAAA==.Morlis:BAAALgAECgQJBgAAAA==.Morlock:BAABLgAECn8rAAMVAAkJvQtXWgCPAQAVAAkJvQtXWgCPAQANAAEJWwgfNQAxAAAAAA==.Morningstahr:BAAALgAECgUJBQAAAA==.',
Mu='Murlen:BAAALgAECgMJBAAAAA==.',
My='Mystris:BAAALgADCgYJBgAAAA==.Mythidru:BAAALgAECgcJDgAAAA==.',
['Mâ']='Mâjestic:BAAALgADCgMJAwAAAA==.',
Na='Naanbread:BAAALgAECgQJBAAAAA==.Naaruto:BAABLgAECn8aAAIFAAgJzQ6+iwBZAQAFAAgJzQ6+iwBZAQAAAA==.Nadia:BAABLgAECn8cAAQjAAYJ4Q/oBgCxAAAjAAYJ1g/oBgCxAAAEAAUJBAl8TQCtAAAUAAMJ9gJgeABPAAAAAA==.Nanako:BAABLgAECn8zAAITAAkJrxh5LwBbAgATAAkJrxh5LwBbAgAAAA==.Naughtyvixen:BAAALgAECgMJAgABLgAECgMJAwAHAAAAAA==.Naughtyvoked:BAAALgAECgYJCgABLgAECgMJAwAHAAAAAA==.Navali:BAAALgAECgMJCAABLgAFFAEJAQAHAAAAAA==.',
Ne='Nefer:BAAALgADCgUJBQAAAA==.Nevicus:BAAALgAECgIJAwAAAA==.',
Ni='Nickayla:BAAALgADCggJCAAAAA==.Nikkaya:BAAALgAECgMJAwABLgAECgYJHgAaAJAcAA==.Nimblecow:BAAALgAECgUJBQAAAA==.Nisdenar:BAAALgADCgkJDgAAAA==.',
No='Noobacleese:BAABLgAECn8wAAIFAAkJrxvsLABNAgAFAAkJrxvsLABNAgAAAA==.Noraviae:BAAALgADCgMJAwAAAA==.Nowahki:BAAALgAECgEJAQAAAA==.',
Nu='Nutbustin:BAABLgAECn8hAAITAAkJBhntQAAZAgATAAkJBhntQAAZAgAAAA==.',
Ny='Nyghtrider:BAABLgAECn8YAAIMAAYJpQswFwB1AAAMAAYJpQswFwB1AAAAAA==.Nykayla:BAAALgAECgcJAwAAAA==.Nymëra:BAABLgAECn8fAAIgAAkJ7w1BVABjAQAgAAkJ7w1BVABjAQAAAA==.Nyneeve:BAABLgAECn87AAIUAAkJThMAHADlAQAUAAkJThMAHADlAQAAAA==.',
Ob='Obscené:BAAALgAECgQJBAAAAA==.',
Od='Oddessyee:BAAALgADCgcJBwABLgAECggJGAAMAPUYAA==.Oddiee:BAABLgAECn8YAAMCAAcJNw/FrAAZAQACAAcJNw/FrAAZAQAYAAQJzgP0OQB0AAABLgAECggJGAAMAPUYAA==.Odinshunter:BAAALgAECgYJBgAAAA==.Odst:BAAALgADCgUJBwABLgAFFAUJDAACALQZAA==.',
Oh='Ohdatroll:BAAALgAFFAIJBAABLgAFFAMJCAAkAEgTAA==.',
Ol='Olgrin:BAAALgADCgkJEgABLgAECgYJBwAHAAAAAA==.',
On='Onepunch:BAAALgAECgEJAQAAAA==.Oneslice:BAAALgAECgUJBgAAAA==.Onyxstar:BAAALgAECgEJAQAAAA==.',
Op='Opera:BAAALgAECgQJBgAAAA==.',
Or='Orikkosh:BAABLgAECn8fAAMSAAcJ0haaJQCBAQASAAcJ0haaJQCBAQAbAAIJuwpCcQBNAAAAAA==.Orw:BAAALgAECgIJAgAAAA==.',
Ot='Otsmayo:BAAALgAECgkJBwAAAA==.',
Pa='Palel:BAABLgAECn83AAIJAAkJLRHbKwCyAQAJAAkJLRHbKwCyAQAAAA==.Palpatinee:BAAALgAECgQJBAAAAA==.Pancetta:BAAALgAECgEJAQABLgAECgkJQgARAAskAA==.Parabelum:BAAALgAECgIJAgAAAA==.',
Pb='Pbfearz:BAABLgAECn8WAAMVAAYJhh8TWAC/AQAVAAUJhh8TWAC/AQAWAAEJAADsXgBSAAAAAA==.',
Pe='Peguelo:BAAALgADCgIJAgAAAA==.Pendrágon:BAAALgAECgIJAgAAAA==.Percocetpete:BAACLgAFFH8NAAIEAAUJBRcSEABTAQAEAAUJBRcSEABTAQAuAAQKfx4AAwQACAnaJCQCAE8DAAQACAnaJCQCAE8DABQAAgkmDpN5AEwAAAAA.Peregrine:BAAALgADCgMJAwAAAA==.',
Ph='Phaet:BAACLgAFFH8fAAMVAAYJAyK7LQCOAQAVAAYJAyK7LQCOAQAWAAEJiw5oFQBUAAAuAAQKfzUAAhUACQnxJHQJADMDABUACQnxJHQJADMDAAAA.Phatty:BAAALgADCgMJAwAAAA==.Phaux:BAAALgAECgIJAgAAAA==.Philipp:BAABLgAECn8gAAIKAAkJDwrsLgBlAQAKAAkJDwrsLgBlAQAAAA==.',
Pi='Picco:BAAALgADCgEJAQABLgAECgUJCQAHAAAAAA==.Pixistix:BAAALgAFFAEJAQAAAA==.',
Pl='Plâgue:BAABLgAECn8bAAICAAkJ4xpfTADdAQACAAkJ4xpfTADdAQAAAA==.',
Pn='Pneuma:BAAALgADCgEJAQAAAA==.',
Po='Potentialman:BAAALgAECggJDAAAAA==.',
Pr='Preprot:BAAALgADCgkJCQABLgAECgkJJwAYADoVAA==.Prot:BAAALgAFFAEJAQAAAA==.',
Pu='Punslug:BAAALgAECgYJCgABLgAFFAIJBgAXAM4aAA==.Puntthegnome:BAAALgAFFAEJAQABLgAFFAUJIQATAI0eAA==.',
['Pó']='Pókóu:BAAALgADCgMJAwAAAA==.',
Ra='Radiance:BAAALgAECgcJDgAAAA==.Raezorian:BAAALgAFFAEJAQABLgAFFAQJBQAbAB8dAA==.Rahmo:BAAALgADCgYJBgAAAA==.Rainforest:BAABLgAECn8eAAIaAAYJkBztAwDnAAAaAAYJkBztAwDnAAAAAA==.Rakiji:BAAALgAECgEJAQAAAA==.Ralphh:BAAALgADCgIJAgAAAA==.Ramdem:BAAALgAECggJEAAAAA==.Ramden:BAABLgAECn86AAIFAAkJPg2+dACEAQAFAAkJPg2+dACEAQAAAA==.Rampant:BAACLgAFFH8MAAICAAUJtBmjEQBCAQACAAUJtBmjEQBCAQAuAAQKfxcAAwIACQkXIEMfAI0CAAIACQkXIEMfAI0CABgAAQmVIBVPAFYAAAAA.Rampscii:BAAALgAECgQJBQABLgAFFAUJDAACALQZAA==.Randalore:BAAALgAECgMJAwABLgAFFAMJCAAkAEgTAA==.Randwulf:BAAALgAECggJEwAAAA==.Ranwong:BAAALgAECgQJCgAAAA==.Ratherton:BAACLgAFFH8hAAITAAUJjR5sRABfAQATAAUJjR5sRABfAQAuAAQKfysAAxMACQmbIO0wAK8CABMACQmbIO0wAK8CACcAAwnRHM8NAOkAAAAA.Rathtard:BAABLgAECn8XAAIMAAkJ3BqMIQBfAgAMAAkJ3BqMIQBfAgABLgAFFAUJIQATAI0eAA==.Rauloso:BAAALgAECgQJEQAAAA==.Ravìn:BAAALgAECgYJDAAAAA==.Rayne:BAAALgAECgcJCAABLgAFFAEJAQAHAAAAAA==.Razz:BAAALgAECgEJAQAAAA==.',
Rd='Rdata:BAAALgADCgkJEAAAAA==.',
Re='Relentlezz:BAAALgADCgMJAwABLgAECgkJLwAcAGUfAA==.Resoluteone:BAABLgAECn9MAAIYAAkJkhViEQD2AQAYAAkJkhViEQD2AQAAAA==.Retnu:BAAALgADCggJEAAAAA==.Revytwohand:BAACLgAFFH8fAAMbAAYJERwpCwBvAQAbAAUJxSApCwBvAQADAAUJjgzSNADYAAAuAAQKfzQAAhsACQmXJUoEABUDABsACQmXJUoEABUDAAAA.',
Rh='Rhagul:BAAALgAFFAIJAgAAAA==.Rhok:BAAALgADCgEJAQAAAA==.Rhokhard:BAAALgADCgEJAwAAAA==.',
Ro='Rocketarena:BAAALgAECgcJDwAAAA==.Rootytooty:BAAALgAECgIJAgAAAA==.Rozelie:BAABLgAFFH8HAAIKAAMJ4hIxMQC9AAAKAAMJ4hIxMQC9AAABLgAFFAcJHwAjAH8aAA==.',
Ry='Ryzarapriest:BAAALgAECgMJBAABLgAFFAEJAQAHAAAAAA==.',
Sa='Sabeladys:BAABLgAECn8oAAIFAAkJRCHLFQDAAgAFAAkJRCHLFQDAAgAAAA==.Sadpeepo:BAAALgADCgIJAgAAAA==.Saifir:BAABLgAECn8pAAIgAAkJBRH1OADMAQAgAAkJBRH1OADMAQAAAA==.Sardmongo:BAAALgADCgcJCgAAAA==.Sardogobo:BAAALgAECgEJAQABLgAECggJIgAVAIEUAA==.Sarduccini:BAABLgAECn8iAAIVAAgJgRTaTADiAQAVAAgJgRTaTADiAQAAAA==.Sargeros:BAAALgAECgQJBAAAAA==.',
Se='Sebastîan:BAAALgAECgEJAQABLgAECgkJHwAVAKUYAA==.Sekhmet:BAAALgAECgcJCAAAAA==.Sekio:BAAALgAECgYJCwAAAA==.',
Sh='Shadowpriest:BAAALgADCgEJAQAAAA==.Shamburgyr:BAAALgAECgMJAwABLgAECggJLAAMAFwRAA==.Shampáin:BAAALgADCgEJAQAAAA==.Shanàs:BAAALgAECgEJAQABLgAECgkJGwAFAEYeAA==.Sharayu:BAAALgAECgEJAQAAAA==.Sheamus:BAAALgADCgkJCQAAAA==.Shiftken:BAAALgAECgMJAwAAAA==.Shiftyfive:BAAALgAFFAMJAwAAAA==.Shivà:BAAALgADCgUJCAAAAA==.',
Si='Sigrodah:BAACLgAFFH8PAAMQAAUJ9g8rNQDuAAAQAAQJ9g8rNQDuAAAOAAEJswG2LAA1AAAuAAQKfxkAAxAACAlTH9cRAF0CABAACAlTH9cRAF0CAA8ABAm2EW4pANQAAAAA.Silvalus:BAAALgAECgYJBwAAAA==.Sin:BAAALgAECgkJCQAAAA==.',
Sk='Skaara:BAAALgAECgQJBwAAAA==.Skara:BAAALgADCgEJAQAAAA==.Skiddles:BAAALgADCgIJAgAAAA==.Skinwalker:BAAALgADCgYJCgAAAA==.Skithyryx:BAAALgADCgIJAgAAAA==.Skonka:BAAALgAECgMJAwAAAA==.Skor:BAAALgADCgQJBAAAAA==.Skyblue:BAAALgAECgEJAQAAAA==.Skyeforce:BAAALgAECgMJBQAAAA==.',
Sl='Slipknoth:BAABLgAECn8UAAMJAAYJkRmEUwAsAQAJAAUJFheEUwAsAQAFAAYJoRIQuAAVAQAAAA==.',
Sm='Smellyy:BAAALgADCgEJAQAAAA==.Smite:BAAALgAECgIJAwAAAA==.Smoketurtle:BAAALgAECgUJCAAAAA==.',
Sn='Sno:BAAALgAECgEJAQAAAA==.',
So='Socatoas:BAABLgAECn8ZAAIBAAkJtglqNQBzAQABAAkJtglqNQBzAQAAAA==.Softbanana:BAAALgADCgEJAQAAAA==.Soi:BAAALgAECgYJCgABLgAECgkJGAAFAE0hAA==.Solarion:BAAALgAECgEJAQABLgAECgcJFAAfAHwPAA==.Sonoforak:BAAALgAECgYJBwAAAA==.',
Sp='Sped:BAABLgAECn8zAAQcAAkJih8dBQDKAgAcAAkJih8dBQDKAgAoAAUJswhvLwB6AAABAAEJ9wP3rgAtAAAAAA==.',
St='Stalrun:BAAALgAECgYJCgABLgAECgYJEgAHAAAAAA==.Staraleena:BAAALgAECgUJBQAAAA==.Starrlynn:BAAALgAECgEJAQAAAA==.Stormeyes:BAAALgAECgMJAQABLgAECggJIwAiAOoaAA==.Stormslight:BAABLgAECn8jAAIiAAgJ6hrgDAD3AQAiAAgJ6hrgDAD3AQAAAA==.Stormsteel:BAAALgAECgMJBQAAAA==.Stôrmrägé:BAAALgAECgcJDQAAAA==.',
Sw='Swgchainz:BAAALgAECgcJEwABLgAECgkJLQARADEdAA==.Swiftdéath:BAAALgAECgYJCgAAAA==.Swtbabybilly:BAAALgAECgYJCQAAAA==.',
Sy='Sylvänäs:BAAALgAECgEJAQAAAA==.',
['Sä']='Säberdh:BAAALgADCgYJBgABLgAECgMJAwAHAAAAAA==.',
['Så']='Såran:BAAALgAECgUJCwAAAA==.',
['Sí']='Sílence:BAABLgAECn8VAAIKAAgJrwkUSADsAAAKAAgJrwkUSADsAAAAAA==.',
['Sô']='Sôlrïx:BAAALgAECgUJCgAAAA==.',
Ta='Tabio:BAAALgADCgYJBgAAAA==.Tabios:BAAALgAECgEJAQAAAA==.Tabito:BAAALgAECgEJAQAAAA==.Taby:BAAALgADCgIJAgAAAA==.Talas:BAABLgAECn8wAAIiAAkJnRYtDgDhAQAiAAkJnRYtDgDhAQAAAA==.Taltaelen:BAAALgADCgYJBgABLgAECgkJHwACAEAWAA==.Tamarack:BAABLgAECn8XAAIMAAYJshuJUQB0AQAMAAYJshuJUQB0AQAAAA==.',
Te='Teetsie:BAAALgAFFAEJAQAAAA==.Tehmber:BAAALgAECgQJCAABLgAECgUJBwAHAAAAAA==.Tehmplar:BAAALgAECgUJBwAAAA==.Terrormisu:BAAALgAECgEJAQABLgAECggJGQAFAHEcAA==.',
Th='Thalorien:BAAALgADCgYJBgABLgAECgcJFwAJAIghAA==.Theboart:BAAALgAECgQJCQAAAA==.Thredron:BAABLgAFFH8HAAIJAAMJTAdfNwCQAAAJAAMJTAdfNwCQAAAAAA==.',
Ti='Tilted:BAAALgAECggJCQABLgAECgkJLgAEAIUXAA==.Timebarred:BAAALgAECgEJBAAAAA==.',
To='Tooru:BAACLgAFFH8XAAQMAAYJqhJWOwA2AQAMAAUJMhZWOwA2AQAIAAEJsg5ZMQBNAAAlAAEJXwKsEQBDAAAuAAQKfzYABAwACQm+IYsGACUDAAwACQm+IYsGACUDAAgACAncEOMcALUBACUABgkWGT1LACUBAAAA.Tortiana:BAAALgAECgUJBQAAAA==.Tossko:BAAALgAECgIJAwABLgAECgQJDAAHAAAAAA==.',
Tr='Traefel:BAAALgAECgMJAwAAAA==.Traeflor:BAAALgAECgEJAQAAAA==.Traevok:BAAALgAECgEJAgAAAA==.Trailertrash:BAABLgAECn9EAAITAAgJnB9NNwA7AgATAAgJnB9NNwA7AgAAAA==.Treebeef:BAACLgAFFH8dAAIkAAYJpAgrKwALAQAkAAYJpAgrKwALAQAuAAQKfzIAAyQACQkCG+0YAHACACQACQkCG+0YAHACAAoAAQnWA/GMACIAAAAA.Triena:BAAALgAECgQJBgAAAA==.Trirn:BAAALgADCgYJBgAAAA==.Trishool:BAAALgADCgIJAgAAAA==.Trumpeter:BAAALgAECgQJCwAAAA==.Trywind:BAAALgAECgYJBgAAAA==.',
Ts='Tsukuyómi:BAAALgAECgEJAQAAAA==.',
Ty='Tyberos:BAABLgAECn8kAAQEAAgJqxzFDQB+AgAEAAgJ2BvFDQB+AgAjAAUJDBd+LwAkAQAUAAMJpRcEYACYAAAAAA==.Tydrielion:BAAALgAECgYJDgAAAA==.Typicaldrood:BAAALgAECgIJAgAAAA==.',
['Tí']='Tízzíts:BAAALgADCgYJBgAAAA==.',
Ul='Ullreich:BAABLgAECn8YAAIMAAcJVwsnjgAjAQAMAAcJVwsnjgAjAQAAAA==.Ulysius:BAACLgAFFH8LAAIFAAQJBRaEFADkAAAFAAQJBRaEFADkAAAuAAQKfysAAgUACQmWGVs0AC8CAAUACQmWGVs0AC8CAAAA.',
Un='Unfazed:BAAALgAECgEJAQAAAA==.Unicornslayr:BAABLgAECn8qAAIJAAkJTRYTKQDEAQAJAAkJTRYTKQDEAQAAAA==.',
Ur='Urund:BAAALgAECgYJDgAAAA==.',
Uw='Uwantsmoke:BAABLgAECn8eAAIMAAYJMwRsuwDPAAAMAAYJMwRsuwDPAAAAAA==.Uwantsmokee:BAAALgADCgMJAwAAAA==.',
Va='Valgroth:BAAALgAECgIJAwAAAA==.Valkisek:BAACLgAFFH8SAAITAAQJxhDaXwAhAQATAAQJxhDaXwAhAQAuAAQKfxkAAhMABwnYGQqbAJ8BABMABwnYGQqbAJ8BAAAA.Valkonigen:BAAALgAECgEJAQAAAA==.Vallarfax:BAABLgAECn8rAAIMAAkJIx/WGACRAgAMAAkJIx/WGACRAgAAAA==.Vandro:BAABLgAECn8qAAQJAAkJlhhuHwAHAgAJAAkJlhhuHwAHAgAFAAQJ4xZ7CQAQAQAiAAYJ2grlLAC4AAAAAA==.Vantive:BAAALgAECgYJDwAAAA==.Vash:BAAALgAECgEJAQAAAA==.Vashdk:BAACLgAFFH8TAAIYAAYJvRmsFQA/AQAYAAYJvRmsFQA/AQAuAAQKfxUAAhgACAnEFn8QAAMCABgACAnEFn8QAAMCAAAA.Vashmonk:BAACLgAFFH8MAAISAAQJzyO4FAB9AQASAAQJzyO4FAB9AQAuAAQKfxUAAhIACQmcIUQMAHECABIACQmcIUQMAHECAAAA.Vashwar:BAAALgAECgYJBgAAAA==.',
Ve='Vedruid:BAAALgAECggJDwAAAA==.Velaric:BAABLgAECn8vAAMkAAkJyhvFFACkAgAkAAkJyhvFFACkAgAaAAEJ3gv1gQAfAAAAAA==.Velcyn:BAAALgADCgcJDgABLgAECgIJAgAHAAAAAA==.Veldoria:BAAALgAECgQJBgAAAA==.Veloe:BAAALgAECgIJAgAAAA==.Veloranas:BAAALgADCgIJAgAAAA==.Verath:BAAALgADCgEJAQAAAA==.Vespyr:BAABLgAECn8sAAIMAAgJXBGvCAA0AQAMAAgJXBGvCAA0AQAAAA==.Vewdoo:BAABLgAECn8+AAIhAAkJtiS5AgBJAwAhAAkJtiS5AgBJAwAAAA==.',
Vi='Viejoverde:BAAALgAECgQJCAAAAA==.Vipul:BAAALgAECgYJDgAAAA==.Vizimir:BAAALgAECgkJCgAAAA==.',
Vo='Voldune:BAAALgAECgIJAwAAAA==.',
['Vë']='Vëgetå:BAAALgADCgYJBwABLgAECgUJBQAHAAAAAA==.',
Wa='Waiwai:BAAALgAECgEJAgAAAA==.Warfarin:BAAALgAECgEJBAAAAA==.Wascii:BAABLgAECn8hAAIMAAkJGBV+NgADAgAMAAkJGBV+NgADAgABLgAFFAUJDAACALQZAA==.Waxedthataxe:BAAALgAECgEJAQAAAA==.Waxesaxes:BAAALgAECgQJBwAAAA==.',
We='Weaken:BAAALgAECgUJCwAAAA==.Weskr:BAAALgADCgEJAQABLgAECggJJAAEAKscAA==.',
Wi='Wickedsinner:BAAALgADCgEJAQAAAA==.Wizkerbizkit:BAAALgAECgMJAwAAAA==.',
Wo='Wolvesbane:BAABLgAFFH8FAAIMAAUJbwAYqwBCAAAMAAUJbwAYqwBCAAAAAA==.',
Wy='Wyrmblood:BAAALgAECgcJDgABLgAECgkJLwAUAJQjAA==.Wyrmfur:BAABLgAECn8kAAMaAAgJCCKJAABuAgAaAAgJCCKJAABuAgAXAAQJUh6hHwALAQAAAA==.Wyrmheal:BAABLgAECn8vAAIUAAkJlCMhBgDwAgAUAAkJlCMhBgDwAgAAAA==.Wyvvie:BAAALgADCgIJAgAAAA==.',
Xa='Xavil:BAAALgAECgEJAQAAAA==.Xavv:BAAALgADCgUJBQAAAA==.',
Xi='Xiba:BAAALgAECgQJBwAAAA==.',
Xl='Xle:BAAALgADCgIJAgAAAA==.',
Ya='Yakoff:BAAALgAECgIJAgAAAA==.Yamihime:BAABLgAECn81AAMRAAkJCxUtGQC4AQARAAgJchYtGQC4AQAGAAkJvwvBXAByAQAAAA==.Yatiri:BAABLgAECn8ZAAMhAAgJxRI+LACUAQAhAAgJxRI+LACUAQAgAAEJQQ6X3gAqAAAAAA==.',
Yo='Yoowuzsup:BAABLgAECn8aAAIhAAcJnBxJMAB+AQAhAAcJnBxJMAB+AQAAAA==.',
Yu='Yureimage:BAABLgAECn8WAAITAAYJMAtf1wDnAAATAAYJMAtf1wDnAAAAAA==.',
Za='Zarthus:BAAALgAECggJAgAAAA==.',
Ze='Zeaket:BAACLgAFFH8mAAIIAAgJKR14AQBeAgAIAAgJKR14AQBeAgAuAAQKfy8AAggACQmSIhkBAGEDAAgACQmSIhkBAGEDAAAA.Zedsdeadd:BAAALgAECgYJDwAAAA==.Zephyr:BAABLgAECn8qAAIjAAgJBgjXBQDSAAAjAAgJBgjXBQDSAAABLgAECggJLAAMAFwRAA==.Zeçhs:BAABLgAECn8YAAIFAAkJTSFZFADxAgAFAAkJTSFZFADxAgAAAA==.',
Zi='Zinek:BAAALgAECgQJBQAAAA==.Zinra:BAAALgAECgUJCwAAAA==.',
Zo='Zoma:BAAALgADCgUJBgAAAA==.Zorcan:BAABLgAECn8oAAINAAkJZxoLBQBBAgANAAkJZxoLBQBBAgAAAA==.',
Zu='Zugzugz:BAAALgAECgEJAgAAAA==.Zulfilith:BAAALgAECgMJBQAAAA==.',
['Zà']='Zàrgothrax:BAAALgADCgYJDgAAAA==.',
['Zð']='Zðltrain:BAAALgAECgQJEAAAAA==.',
['Ál']='Álfruen:BAAALgAECgUJBgAAAA==.',
['Ãi']='Ãinz:BAAALgAECgMJAwAAAA==.',
['Èx']='Èxecutioner:BAAALgADCgMJAwAAAA==.',
['Ða']='Ðachee:BAAALgAECgQJCQAAAA==.',
['Ðå']='Ðånger:BAAALgAECgMJAgAAAA==.',
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
