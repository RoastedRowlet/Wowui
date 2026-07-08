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

local lookup = {'Warrior-Fury','DeathKnight-Unholy','Monk-Mistweaver','Priest-Holy','Paladin-Retribution','DemonHunter-Devourer','Unknown-Unknown','Hunter-Survival','Paladin-Holy','Druid-Balance','DeathKnight-Frost','Hunter-BeastMastery','Warlock-Affliction','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Havoc','Monk-Brewmaster','Shaman-Enhancement','Mage-Frost','Priest-Shadow','Warlock-Demonology','Warlock-Destruction','Druid-Feral','DeathKnight-Blood','Rogue-Assassination','Druid-Guardian','Monk-Windwalker','Warrior-Protection','DemonHunter-Vengeance','Rogue-Subtlety','Shaman-Restoration','Shaman-Elemental','Paladin-Protection','Priest-Discipline','Druid-Restoration','Hunter-Marksmanship','Warrior-Arms','Rogue-Outlaw','Mage-Arcane',}
local provider = {region='US',realm='Madoran',name='US',type='weekly',zone=46,date='2026-07-05',data={Aa='Aarhus:BAAALgAECgUJCQAAAA==.Aaronmourne:BAAALgAECgQJBAABLgAECgkJGQABALYJAA==.Aaronyates:BAAALgADCgcJBwABLgAFFAUJDAACALQZAA==.',
Ac='Actualegirl:BAABLgAFFH8GAAIDAAUJLQRLNwDLAAADAAUJLQRLNwDLAAABLgAFFAUJDQAEAAUXAA==.',
Ad='Adrenalin:BAAALgADCgEJAQAAAA==.Adversary:BAAALgAECgMJAwAAAA==.',
Ae='Aerfen:BAABLgAECn8cAAIFAAkJyg2QaQCcAQAFAAkJyg2QaQCcAQAAAA==.',
Ag='Agross:BAAALgADCgYJBgAAAA==.',
Ai='Aimforhead:BAAALgAECgcJDAAAAA==.',
Ak='Akiraha:BAAALgAECgMJBgAAAA==.',
Al='Alexas:BAAALgADCgcJCAAAAA==.Alric:BAABLgAECn80AAIGAAkJYxQeNQDyAQAGAAkJYxQeNQDyAQAAAA==.Alyndra:BAAALgADCgUJBQABLgAECgUJBQAHAAAAAA==.',
Am='Amideus:BAAALgAECgEJAQAAAA==.Amory:BAABLgAECn8mAAICAAkJ9x40IQCDAgACAAkJ9x40IQCDAgAAAA==.',
An='Angela:BAAALgADCgIJAgAAAA==.Annaesthetic:BAAALgAECgEJAwABLgAECgkJOQAIAAgVAA==.',
Ar='Arator:BAAALgADCgEJAgAAAA==.Araña:BAAALgAECgEJAQAAAA==.Arcatraz:BAAALgAECgEJAQAAAA==.Ardaddy:BAAALgAECgYJDQABLgAFFAMJBAAHAAAAAA==.Ardzak:BAAALgAFFAMJBAAAAA==.Arragorn:BAACLgAFFH8IAAIJAAQJFRl9HwAhAQAJAAQJFRl9HwAhAQAuAAQKfycAAgkACQktHLgZADkCAAkACQktHLgZADkCAAAA.',
As='Asendra:BAABLgAECn8mAAIKAAkJ6xnFEQBLAgAKAAkJ6xnFEQBLAgAAAA==.Assaran:BAAALgAECgIJAgAAAA==.Astal:BAACLgAFFH8LAAILAAUJlA/8DwAYAQALAAUJlA/8DwAYAQAuAAQKfx0AAgsACQmfGwkHACwCAAsACQmfGwkHACwCAAAA.',
At='Ate:BAAALgADCgYJBgABLgAECgkJKgAJAE0WAA==.Athenea:BAABLgAECn8aAAIBAAcJUBuYHwDyAQABAAcJUBuYHwDyAQAAAA==.Athénna:BAAALgADCgIJAgABLgAECggJMAAMAIYTAA==.Atulru:BAAALgADCgMJAwAAAA==.',
Av='Avyl:BAAALgADCgcJBwABLgAECgYJGwANAPsRAA==.',
Ay='Ayannar:BAAALgADCgEJAQAAAA==.',
Az='Azriella:BAAALgAECgkJCAAAAA==.Azuren:BAABLgAECn9CAAQOAAkJwBi3AAB9AQAOAAcJzhS3AAB9AQAPAAkJKgsXAgAUAQAQAAEJ8wdcFQAdAAAAAA==.',
Ba='Baal:BAAALgAFFAIJAgAAAA==.Bacon:BAABLgAECn9CAAMRAAkJCyRPBQDtAgARAAkJCyRPBQDtAgAGAAcJKRvcSACsAQAAAA==.Bamboozled:BAABLgAECn8VAAMDAAgJbxNTLQDJAQADAAgJbxNTLQDJAQASAAUJ7ANIBgCSAAAAAA==.Bandìt:BAAALgAECggJCwAAAA==.Bankai:BAABLgAFFH8GAAITAAEJUCXSCwBTAAATAAEJUCXSCwBTAAAAAA==.Barbieque:BAAALgADCgcJBwAAAA==.',
Be='Bearyden:BAAALgADCgEJAQAAAA==.Bedbugs:BAAALgAECgQJBAABLgAFFAUJIQAUAI0eAA==.Beefstrasz:BAABLgAECn8aAAMEAAgJuRdiFAAzAgAEAAgJuRdiFAAzAgAVAAEJpwbTkgAoAAAAAA==.Beyla:BAACLgAFFH8IAAIFAAMJQQobegDBAAAFAAMJQQobegDBAAAuAAQKfycAAgUACQkFF4A1ACsCAAUACQkFF4A1ACsCAAAA.',
Bi='Bioactive:BAAALgADCgYJBgAAAA==.Bishamon:BAABLgAECn9OAAQWAAkJ+yHwBQBeAwAWAAkJ+yHwBQBeAwAXAAEJAADAaQA+AAANAAEJAADlMQA6AAAAAA==.Bizotch:BAAALgAECggJDgAAAA==.',
Bl='Bleau:BAABLgAECn8iAAIYAAkJbxCpEACtAQAYAAkJbxCpEACtAQAAAA==.Blethings:BAAALgAECgMJAwAAAA==.Blinktwice:BAAALgAECgEJAgAAAA==.Bloodimess:BAAALgADCgMJAwAAAA==.Bloodymary:BAABLgAECn8nAAIZAAkJOhXwEwDUAQAZAAkJOhXwEwDUAQAAAA==.Bluebarrie:BAAALgAECgEJAQAAAA==.Blôodräge:BAAALgAECgcJDgAAAA==.',
Bo='Bootelicious:BAAALgADCgIJAgAAAA==.Bouncybean:BAAALgADCgIJAgAAAA==.',
Br='Bradsupinya:BAABLgAECn8kAAIUAAgJEBl7XgDEAQAUAAgJEBl7XgDEAQAAAA==.Branchling:BAAALgAECgcJEgABLgAFFAUJIQAUAI0eAA==.Brewswane:BAAALgAFFAEJAwABLgAFFAcJJAAaAGoWAA==.Bridh:BAABLgAECn8aAAIGAAkJFR5LEQD0AgAGAAkJFR5LEQD0AgABLgAFFAgJHwAXABIcAA==.Bromm:BAAALgAECgEJAQAAAA==.Brunor:BAAALgAECgkJCwAAAA==.',
Bu='Bulkamania:BAAALgAECgMJAwAAAA==.Butterkip:BAACLgAFFH8PAAIVAAUJfBSxFgAvAQAVAAUJfBSxFgAvAQAuAAQKfysAAhUACQlpHikKAOACABUACQlpHikKAOACAAAA.',
['Bë']='Bëarclaw:BAAALgAECgUJBQAAAA==.',
Ca='Cambria:BAAALgAECgMJAwAAAA==.Cantkillme:BAAALgAECgQJBwAAAA==.Canukillme:BAAALgADCgYJBgAAAA==.Carloos:BAAALgAFFAEJAQAAAA==.Carruel:BAAALgADCgUJBQAAAA==.Cazzc:BAAALgAECgUJCAAAAA==.',
Ce='Cellan:BAABLgAECn8XAAICAAcJ6wqKvQABAQACAAcJ6wqKvQABAQAAAA==.Censora:BAAALgAECgEJAQAAAA==.',
Ch='Chicharrones:BAAALgAECgUJBQABLgAECgkJQgARAAskAA==.Chickenshift:BAABLgAECn8nAAMbAAkJ2R7wDAATAgAbAAgJxh3wDAATAgAYAAQJDBnIHAAkAQAAAA==.Chipahoy:BAABLgAECn8nAAIFAAgJdRw/OAAhAgAFAAgJdRw/OAAhAgABLgAECggJRAAUAJwfAA==.Chlorofõrm:BAAALgAECgIJAwABLgAECgkJOQAIAAgVAA==.Chopahoe:BAAALgAECgQJBwAAAA==.Chuggz:BAABLgAECn8gAAIcAAkJ5xE1HwCzAQAcAAkJ5xE1HwCzAQAAAA==.',
Ci='Cindywoohoo:BAAALgADCgYJCAAAAA==.',
Cl='Clamadin:BAAALgAECgIJAgABLgAFFAgJJQAUAKccAA==.Clamius:BAACLgAFFH8lAAIUAAgJpxwjDACOAgAUAAgJpxwjDACOAgAuAAQKfyoAAhQACQkkJRALACEDABQACQkkJRALACEDAAAA.Cliff:BAAALgAECgUJBgAAAA==.',
Co='Colby:BAAALgAECgYJDgAAAA==.Coldass:BAABLgAECn8ZAAIUAAgJwRJjZgCxAQAUAAgJwRJjZgCxAQAAAA==.Coldstone:BAAALgAECgYJCAAAAA==.Commodus:BAAALgADCgQJBAAAAA==.Conduit:BAAALgAECgQJBgAAAA==.Coombrain:BAAALgAECgUJCQAAAA==.Cotopla:BAAALgAECgQJDAAAAA==.',
Cr='Critterzz:BAABLgAECn8aAAIEAAgJ4hb6FwAcAgAEAAgJ4hb6FwAcAgAAAA==.Cryptkeys:BAAALgAECgMJAwAAAA==.',
Cu='Cuziseeu:BAAALgAECgQJBAABLgAECgYJBgAHAAAAAA==.',
Da='Dachyy:BAAALgAECgcJEwAAAA==.Daemonwaters:BAAALgAECgEJAQAAAA==.Dagov:BAAALgAECgYJCAAAAA==.Daiana:BAAALgAECgIJAgAAAA==.Damage:BAAALgAFFAEJAQAAAA==.Darkråii:BAAALgAECgIJAwAAAA==.Dashboy:BAAALgADCgEJAQAAAA==.',
De='Deafniteelf:BAAALgAECgkJDQAAAA==.Deathlentlez:BAABLgAECn8vAAIdAAkJZR86BwCSAgAdAAkJZR86BwCSAgAAAA==.Decaylentlez:BAAALgAECgEJAQABLgAECgkJLwAdAGUfAA==.Deepwinter:BAAALgAECgcJDQABLgAFFAUJDAACALQZAA==.Delphyne:BAABLgAECn8UAAIOAAYJ9wvxEQDrAAAOAAYJ9wvxEQDrAAAAAA==.Delylee:BAAALgAECgIJAgAAAA==.Demandred:BAAALgAECgcJDAAAAA==.Demonhunter:BAABLgAECn8gAAIRAAkJuhiWDgA8AgARAAkJuhiWDgA8AgAAAA==.Demonià:BAABLgAECn8eAAIUAAkJmgqhEQDqAAAUAAkJmgqhEQDqAAAAAA==.Desong:BAAALgADCgYJBwAAAA==.Detharbinger:BAAALgAECgcJDQAAAA==.Dethgripz:BAABLgAFFH8HAAICAAMJGwlPOwC7AAACAAMJGwlPOwC7AAAAAA==.Dezzan:BAAALgADCgQJBwAAAA==.',
Di='Diamondsword:BAAALgAECggJDgAAAA==.Dieanah:BAAALgADCgcJBwAAAA==.',
Dj='Djazz:BAAALgAECgYJCAAAAA==.',
Do='Dochaze:BAABLgAECn8qAAMJAAkJfxyHHwAdAgAJAAgJPB+HHwAdAgAFAAMJjA1KIAGTAAAAAA==.Dogdimmadome:BAAALgAECgYJDwAAAA==.Dolore:BAAALgADCgcJBgAAAA==.Doublejump:BAAALgAECgEJAQABLgAECgkJJwAZADoVAA==.',
Dr='Dragone:BAAALgAECgUJCQAAAA==.Dragun:BAAALgADCgUJBQABLgAECgkJHAAFANoQAA==.Drowsee:BAAALgAECgUJBgAAAA==.Dráconus:BAAALgADCgEJAQAAAA==.',
Du='Dumbdumb:BAAALgAECgQJBgAAAA==.',
Dy='Dyanuh:BAABLgAECn8eAAIVAAYJygIVEwBMAAAVAAYJygIVEwBMAAAAAA==.',
['Dà']='Dàrkscythe:BAABLgAECn8cAAMZAAcJmAVLPACgAAAZAAcJuQRLPACgAAALAAEJiQZqPwAoAAAAAA==.',
Ea='Eazywin:BAAALgAECggJCQAAAA==.',
Eh='Ehlsa:BAAALgADCgcJBwAAAA==.Ehlsi:BAABLgAECn8xAAMeAAkJUR/PAgDFAgAeAAkJUR/PAgDFAgARAAIJ1Bu2DgBVAAAAAA==.Ehress:BAAALgAECgcJEwABLgAFFAUJDAACALQZAA==.',
Ei='Eirinny:BAABLgAECn8tAAITAAkJWQq6EwB9AQATAAkJWQq6EwB9AQAAAA==.',
El='Elindez:BAABLgAECn8nAAIfAAkJUw+YGADVAQAfAAkJUw+YGADVAQAAAA==.Elyviel:BAAALgAFFAEJAQAAAA==.Elàine:BAABLgAECn80AAIMAAgJJgkiFgDGAAAMAAgJJgkiFgDGAAAAAA==.',
Em='Emika:BAAALgADCgUJDgAAAA==.Emyrson:BAAALgAECgQJCQAAAA==.',
En='Encantado:BAAALgAECgUJBQAAAA==.Enemywithin:BAAALgADCgIJAgAAAA==.Enzo:BAAALgADCgYJCwAAAA==.',
Ep='Epicfury:BAAALgAECgYJDgAAAA==.',
Eq='Eq:BAAALgADCgUJBgAAAA==.',
Ez='Ezmee:BAAALgAECgUJEAAAAA==.',
Fa='Facingworlds:BAAALgAECggJDgAAAA==.Fathercaleb:BAAALgAECgIJAwABLgAFFAYJHwAcABEcAA==.Fazed:BAAALgAECgIJBgAAAA==.Fazeo:BAAALgAECgQJBQAAAA==.',
Fe='Featherstep:BAAALgADCgMJAwAAAA==.Felysse:BAAALgADCgEJAQAAAA==.',
Fi='Fireball:BAAALgAECgIJAgABLgAFFAEJAQAHAAAAAA==.',
Fl='Flavio:BAAALgAECgQJCAAAAA==.',
Fo='Fortuna:BAABLgAECn8kAAITAAkJxASQGQA4AQATAAkJxASQGQA4AQAAAA==.',
Fr='Francesca:BAAALgADCgEJAQAAAA==.Frosilen:BAABLgAECn87AAMgAAkJCxDoQQCmAQAgAAkJCxDoQQCmAQAhAAMJaQtgewB9AAAAAA==.Frostbite:BAAALgADCgIJAgAAAA==.',
Ga='Gamaikuba:BAAALgADCggJCQAAAA==.Gamarth:BAAALgAECgYJDQAAAA==.Gatlu:BAABLgAECn8hAAIbAAkJcBYzDQAOAgAbAAkJcBYzDQAOAgAAAA==.Gawdsmackk:BAAALgAECggJDgAAAA==.Gaz:BAAALgADCgMJAwAAAA==.Gazokks:BAAALgADCgcJBwAAAA==.',
Ge='Gedank:BAAALgADCgcJBwAAAA==.Geodemon:BAAALgAECgQJBAAAAA==.Gethealed:BAAALgAECgcJEAAAAA==.Getrektpos:BAAALgADCgMJAwAAAA==.',
Gh='Ghostlock:BAABLgAECn8VAAINAAgJzxn2BQAFAgANAAgJzxn2BQAFAgAAAA==.Ghoztface:BAABLgAECn8oAAMiAAcJcxzHDgDYAQAiAAYJXCDHDgDYAQAFAAcJJxLmmgA/AQAAAA==.Ghöstbeef:BAAALgADCgkJEAABLgAECggJGgAEALkXAA==.',
Gi='Giblock:BAABLgAECn8XAAINAAgJCBRNDwBoAQANAAgJCBRNDwBoAQAAAA==.',
Gl='Glamorus:BAAALgADCgUJBQAAAA==.Glamour:BAAALgAECgQJEAAAAA==.Glitterboy:BAAALgAECgIJAgABLgAFFAgJIwAcACIfAA==.',
Go='Golomojek:BAABLgAECn8WAAIhAAkJugp5RQAeAQAhAAkJugp5RQAeAQAAAA==.Gorkun:BAAALgADCgkJDgAAAA==.Gov:BAACLgAFFH8XAAMRAAYJtR7gEAAcAQAGAAYJIR13PAA0AQARAAUJfhXgEAAcAQAuAAQKfygAAwYACQm/JYsIAEUDAAYACQm/JYsIAEUDABEAAQlSEjpsADkAAAAA.Govndrag:BAAALgADCgEJAQAAAA==.Govs:BAACLgAFFH8GAAQEAAMJohhuIwCgAAAEAAIJBiJuIwCgAAAVAAIJcha/LACYAAAjAAIJdghtQAB4AAAuAAQKfxUAAwQACAmVHqAPAG4CAAQACAmVHqAPAG4CABUAAwmVHhFYALQAAAAA.',
Gr='Gralmerte:BAACLgAFFH8MAAIYAAQJ9CE3AQBxAQAYAAQJ9CE3AQBxAQAuAAQKfzYAAxgACQnNIu4BABYDABgACQnNIu4BABYDACQAAQn3FIfGADwAAAAA.Grawfern:BAAALgAFFAEJAQAAAA==.Graygoyle:BAABLgAECn8hAAIaAAkJSgb7DABbAQAaAAkJSgb7DABbAQAAAA==.Groggaris:BAAALgAECgMJAwAAAA==.Groosalugg:BAABLgAECn8dAAIMAAkJtx2KKwAvAgAMAAkJtx2KKwAvAgAAAA==.',
Gu='Guillotine:BAAALgAECgEJAQAAAA==.Guldave:BAAALgAECgQJBAAAAA==.Guthrie:BAABLgAECn8WAAIJAAcJ2BczKgC9AQAJAAcJ2BczKgC9AQAAAA==.',
Gw='Gwyndolïn:BAABLgAECn8eAAMDAAcJ6RiIMAC4AQADAAcJ6RiIMAC4AQAcAAQJnAR6bQB3AAAAAA==.',
Ha='Hachendis:BAAALgADCgMJAwAAAA==.Haether:BAABLgAECn8uAAIgAAkJdBHnLQD/AQAgAAkJdBHnLQD/AQAAAA==.Haliax:BAAALgAECgEJAQABLgAECgkJGAAFAE0hAA==.Hammatime:BAAALgADCgcJBwAAAA==.Hatsu:BAABLgAECn8VAAIDAAkJSgxFPAB/AQADAAkJSgxFPAB/AQAAAA==.Hawktuahh:BAAALgAECgIJAgAAAA==.',
He='Hellá:BAAALgADCgIJAgAAAA==.Hemandunter:BAAALgAECgEJAQAAAA==.',
Hi='Hildunn:BAAALgAECgQJBgAAAA==.Hingedh:BAABLgAFFH8FAAIGAAMJ9g6uJwCjAAAGAAMJ9g6uJwCjAAABLgAFFAcJIwAfAMccAA==.Hitemup:BAAALgADCgQJBAAAAA==.',
Hk='Hktanker:BAAALgADCgQJBAABLgAECgYJGAAMAKULAA==.',
Ho='Holylentlezz:BAAALgADCgcJBwABLgAECgkJLwAdAGUfAA==.Holymun:BAABLgAECn8cAAIFAAkJ2hBdcwCHAQAFAAkJ2hBdcwCHAQAAAA==.Holyox:BAABLgAECn83AAIFAAkJngxbdgCBAQAFAAkJngxbdgCBAQAAAA==.Hotcheeto:BAAALgAECggJDAAAAA==.',
Ht='Hturtle:BAAALgADCgEJAQAAAA==.Hturtledk:BAABLgAECn8VAAMCAAYJvxaKnwAtAQACAAYJvxaKnwAtAQAZAAEJ3QJYawAUAAAAAA==.',
Hu='Hug:BAAALgAECgUJCAAAAA==.',
['Hü']='Hüntress:BAAALgAFFAEJAgAAAA==.',
Ia='Iacey:BAAALgAECgIJAgAAAA==.',
Im='Imdatroll:BAACLgAFFH8IAAMkAAMJSBNyNwDPAAAkAAMJSBNyNwDPAAAYAAIJrxOuFQCDAAAuAAQKfzIABBgACQneIzYCADEDABgACQneIzYCADEDACQABgkUGRZZAC0BAAoAAgndC9ZyAGEAAAAA.Imgibby:BAAALgADCgYJBgABLgAECggJFwANAAgUAA==.Impius:BAAALgAECgkJCgAAAA==.Impmageddon:BAABLgAECn8aAAMWAAkJnRF6ZQBzAQAWAAkJnRF6ZQBzAQAXAAEJAAASdQAwAAAAAA==.',
In='Inexorable:BAABLgAFFH8IAAIFAAMJjxR7HwCwAAAFAAMJjxR7HwCwAAAAAA==.',
Ir='Irakwa:BAABLgAECn8UAAIMAAUJeQkIwgDDAAAMAAUJeQkIwgDDAAAAAA==.',
It='Itches:BAACLgAFFH8jAAIcAAgJIh8sAQChAgAcAAgJIh8sAQChAgAuAAQKfyAAAhwACAkHJOYDAE8DABwACAkHJOYDAE8DAAAA.',
Iw='Iwamori:BAAALgAECgEJAQAAAA==.',
Iz='Izánámi:BAABLgAECn85AAQIAAgJCBUZAgB0AQAIAAgJCBUZAgB0AQAMAAEJ8A19ywA6AAAlAAEJlwGPmAAeAAAAAA==.',
Ja='Jagon:BAABLgAECn8vAAQQAAkJChogAgCQAQAQAAkJChogAgCQAQAPAAIJtQdgNQBQAAAOAAIJHwzCJQA0AAAAAA==.Jalen:BAAALgAECgYJBgAAAA==.Janvi:BAAALgAECgEJAQAAAA==.Jarbito:BAAALgAECgUJCwAAAA==.Jarico:BAAALgAECgYJDQABLgAECgYJEgAHAAAAAA==.Jasint:BAAALgAECgUJBQABLgAECgkJLwAQAAoaAA==.',
Je='Jebrogue:BAAALgADCgkJDgAAAA==.',
Jh='Jhunts:BAAALgAECggJEAAAAA==.',
Ji='Jinbloom:BAAALgADCgIJAgAAAA==.Jincrush:BAAALgAECgIJAgAAAA==.Jindabutt:BAABLgAECn8mAAISAAkJYyAXBgDbAgASAAkJYyAXBgDbAgAAAA==.Jinfuse:BAAALgADCgUJBQAAAA==.Jintonic:BAAALgAECgcJCAAAAA==.',
Jk='Jkbalo:BAABLgAFFH8FAAMmAAIJHwW5GQA+AAABAAIJ8gBKVgA+AAAmAAIJHwW5GQA+AAAAAA==.Jkrlos:BAAALgAFFAMJBAAAAA==.',
Jo='Jocommande:BAAALgAECgEJAQAAAA==.Jointheraid:BAAALgADCgMJAwAAAA==.Jokerstree:BAAALgADCgYJBgAAAA==.Jorah:BAAALgADCgcJCgAAAA==.Jorkah:BAAALgADCgcJCgAAAA==.',
Jp='Jpdh:BAACLgAFFH8UAAMeAAQJZSO6BAAnAQAGAAQJLSMsLwBpAQAeAAMJ2yK6BAAnAQAuAAQKfyoABB4ACQl3JKQEAHACAAYACQmfIGwYAMMCAB4ACAk8JaQEAHACABEABQmbFo9EAOQAAAAA.Jphunt:BAAALgADCgUJBQABLgAFFAQJFAAeAGUjAA==.',
Ju='Juddory:BAABLgAECn8jAAIUAAgJ8guEqQAsAQAUAAgJ8guEqQAsAQAAAA==.Junksvil:BAAALgAECgYJEgAAAA==.',
['Jø']='Jøhnwick:BAAALgADCgYJBgAAAA==.',
Ka='Kahrahkon:BAAALgAECgQJDgAAAA==.Kalinis:BAAALgAECgIJAwAAAA==.Kanadoria:BAAALgAECgEJAQAAAA==.Kanion:BAAALgAECgYJCgAAAA==.Kargorr:BAAALgAECgMJAwAAAA==.',
Ke='Kenth:BAAALgAECgEJAQAAAA==.',
Kh='Khudoz:BAAALgAECgMJBwAAAA==.',
Ki='Killerelf:BAAALgADCggJCAAAAA==.Killshotz:BAAALgADCgUJBQAAAA==.Kismët:BAAALgAECgEJAQAAAA==.',
Kl='Klid:BAAALgADCgMJAwABLgAFFAIJBQAFAIIUAA==.',
Ko='Koa:BAAALgAECgEJAQAAAA==.Kooch:BAAALgADCgYJBgAAAA==.Korinth:BAECLgAFFH8eAAIiAAYJZhY9CQDiAAAiAAYJZhY9CQDiAAAuAAQKfz0AAiIACQnnG10HAGkCACIACQnnG10HAGkCAAAA.Kovala:BAAALgAECgEJAQAAAA==.',
Kr='Kriaalis:BAACLgAFFH8HAAMgAAMJjgvWMwBQAAAgAAIJYgTWMwBQAAAhAAIJ+ABnLgAiAAAuAAQKfxUAAyAACQlIBct6AO8AACAACAn6BMt6AO8AACEAAQmqBVvDABkAAAAA.Krul:BAAALgADCgMJBgAAAA==.',
Ku='Kurzon:BAAALgADCgMJAwABLgAECgkJHQAMALcdAA==.',
Ky='Kyoka:BAABLgAECn8kAAQEAAgJqxzFDQB+AgAEAAgJ2BvFDQB+AgAjAAUJDBd+LwAkAQAVAAMJpRcEYACYAAAAAA==.Kyra:BAAALgAECgUJDwAAAA==.',
['Kæ']='Kælas:BAAALgAECgEJAgAAAA==.',
La='Lachryma:BAAALgADCgUJBQAAAA==.Laríssa:BAEBLgAFFH8JAAIVAAUJrg2mCwDcAAAVAAUJrg2mCwDcAAAAAA==.Lazuli:BAAALgAECgYJBgABLgAECgkJQgARAAskAA==.',
Le='Legault:BAABLgAECn8rAAInAAkJIB9pAQDmAgAnAAkJIB9pAQDmAgAAAA==.Legionofboom:BAAALgADCgQJBgAAAA==.Lethfel:BAABLgAECn8VAAMWAAgJ4xs4WgCPAQAWAAYJYBw4WgCPAQAXAAYJlRbkIABNAQAAAA==.Lethferal:BAAALgADCgIJAgAAAA==.',
Li='Liacci:BAAALgADCgYJBgAAAA==.Lilgoukii:BAAALgADCgIJAgAAAA==.Lillithfaust:BAAALgAECgMJCQAAAA==.Limbø:BAABLgAECn8eAAIUAAcJLCFSSQD/AQAUAAcJLCFSSQD/AQAAAA==.Lindia:BAAALgADCgEJAQAAAA==.Lionfury:BAAALgADCgcJBwAAAA==.Lionguard:BAAALgAECgEJAQAAAA==.Liquidturtle:BAAALgAECgMJBAAAAA==.Livie:BAABLgAECn8oAAIFAAkJlBgQNQAsAgAFAAkJlBgQNQAsAgAAAA==.',
Lo='Lonelylad:BAAALgAECgEJAQAAAA==.Loneshark:BAAALgAECgYJCQAAAA==.Longwood:BAAALgAECgYJCAAAAA==.Lonon:BAAALgADCgQJBAAAAA==.Loops:BAAALgAECgIJAwAAAA==.Loraddesmos:BAABLgAECn9DAAIXAAkJlhT+BgDrAQAXAAkJlhT+BgDrAQAAAA==.Loriah:BAABLgAECn8wAAIFAAkJShXTRwDvAQAFAAkJShXTRwDvAQAAAA==.Lovan:BAAALgAECgEJAwAAAA==.',
Lu='Lucance:BAAALgAECgIJAgAAAA==.Lullaby:BAABLgAECn8uAAIEAAkJhRcQFgAiAgAEAAkJhRcQFgAiAgAAAA==.Lumot:BAAALgADCgcJCwAAAA==.',
Ma='Maeg:BAAALgAECgIJAgABLgAFFAMJCAAkAEgTAA==.Maireldps:BAAALgAECgQJBAAAAA==.Manawarr:BAAALgAECgEJAQAAAA==.Marcdofu:BAAALgAECgQJBQAAAA==.Maryjanè:BAAALgAECgUJBQAAAA==.Mataquay:BAAALgAECggJEAAAAA==.Maveloris:BAAALgADCgcJBgAAAA==.Mavennes:BAAALgAECgMJAwAAAA==.Mawzshallah:BAACLgAFFH8dAAIKAAYJ5yN2EACiAQAKAAYJ5yN2EACiAQAuAAQKfzMAAwoACQllJWgBAMEDAAoACQllJWgBAMEDABsABQl6FLMTADQBAAAA.Mayli:BAAALgAFFAMJAwAAAA==.',
Mc='Mctanker:BAABLgAECn8aAAMiAAcJUBGKHQApAQAiAAcJUBGKHQApAQAFAAUJBgte9wDCAAAAAA==.',
Me='Meascii:BAACLgAFFH8WAAIjAAUJ6gp5IwAyAQAjAAUJ6gp5IwAyAQAuAAQKfyQAAiMACQlaGRMOAIwCACMACQlaGRMOAIwCAAAA.Medeaeris:BAAALgADCgIJAgAAAA==.Meepmorp:BAAALgAECgEJAQAAAA==.Megs:BAAALgADCgYJBgAAAA==.Merc:BAACLgAFFH8jAAIcAAgJLB7XAgAuAgAcAAgJLB7XAgAuAgAuAAQKfzoAAhwACQksI5kFAPcCABwACQksI5kFAPcCAAAA.',
Mi='Millee:BAABLgAECn8hAAMEAAgJZBx/GAAJAgAEAAgJZBx/GAAJAgAVAAIJpgPGhQA0AAAAAA==.Mincebeef:BAAALgAECgMJAwABLgAECggJGgAEALkXAA==.Mindpuck:BAAALgAECgQJBAAAAA==.Mirefighter:BAAALgAECgMJAwABLgAFFAYJHwAYAB8dAA==.Miremana:BAAALgAECgcJDwABLgAFFAYJHwAYAB8dAA==.Mirespike:BAACLgAFFH8fAAIYAAYJHx09AwCZAQAYAAYJHx09AwCZAQAuAAQKfzIAAhgACQlSIpkDAPgCABgACQlSIpkDAPgCAAAA.Mistylady:BAAALgADCgIJBAAAAA==.',
Mo='Mommacougar:BAAALgADCgEJAQAAAA==.Moondrade:BAAALgAECgUJBQAAAA==.Moosebearowl:BAAALgAFFAIJAgAAAA==.Morfirrann:BAAALgADCgEJAQAAAA==.Morlis:BAAALgAECgQJCAAAAA==.Morlock:BAABLgAECn8rAAMWAAkJvQtXWgCPAQAWAAkJvQtXWgCPAQANAAEJWwgfNQAxAAAAAA==.Morningstahr:BAAALgAECgUJBQAAAA==.',
Mu='Murlen:BAAALgAECgMJBAAAAA==.',
My='Mystris:BAAALgADCgYJBgAAAA==.Mythidru:BAAALgAECgcJDgAAAA==.',
['Mâ']='Mâjestic:BAAALgADCgMJAwAAAA==.',
Na='Naanbread:BAAALgAECgQJBAAAAA==.Naaruto:BAABLgAECn8aAAIFAAgJzQ6+iwBZAQAFAAgJzQ6+iwBZAQAAAA==.Nadia:BAABLgAECn8gAAQjAAYJnBAFCADkAAAjAAYJkBAFCADkAAAEAAUJBAl8TQCtAAAVAAMJ9gJgeABPAAAAAA==.Nanako:BAABLgAECn8zAAIUAAkJrxh5LwBbAgAUAAkJrxh5LwBbAgAAAA==.Naughtyvixen:BAAALgAECgMJAgABLgAECgkJDwAHAAAAAA==.Naughtyvoked:BAAALgAECgYJCgABLgAECgkJDwAHAAAAAA==.Navali:BAAALgAECgMJCAABLgAFFAEJAQAHAAAAAA==.',
Ne='Nefer:BAAALgADCgUJBQAAAA==.Nevicus:BAAALgAECgIJAwAAAA==.',
Ni='Nickayla:BAAALgADCggJCAAAAA==.Nikkaya:BAAALgAECgMJAwABLgAECgYJHgAbAJAcAA==.Nimblecow:BAAALgAECgUJBQAAAA==.Nisdenar:BAAALgADCgkJDgAAAA==.',
No='Noobacleese:BAABLgAECn8wAAIFAAkJrxvsLABNAgAFAAkJrxvsLABNAgAAAA==.Noraviae:BAAALgADCgMJAwAAAA==.Nowahki:BAAALgAECgEJAQAAAA==.',
Nu='Nutbustin:BAABLgAECn8hAAIUAAkJBhntQAAZAgAUAAkJBhntQAAZAgAAAA==.',
Ny='Nyghtrider:BAABLgAECn8YAAIMAAYJpQuloQD+AAAMAAYJpQuloQD+AAAAAA==.Nykayla:BAAALgAECgcJAwAAAA==.Nymëra:BAABLgAECn8fAAIgAAkJ7w1BVABjAQAgAAkJ7w1BVABjAQAAAA==.Nyneeve:BAABLgAECn9BAAIVAAkJBRTaAgCNAQAVAAkJBRTaAgCNAQAAAA==.',
Ob='Obscené:BAAALgAECgQJBAAAAA==.',
Od='Oddessyee:BAAALgADCgcJBwABLgAECggJGAAMAPUYAA==.Oddiee:BAABLgAECn8YAAMCAAcJNw/FrAAZAQACAAcJNw/FrAAZAQAZAAQJzgP0OQB0AAABLgAECggJGAAMAPUYAA==.Odinshunter:BAAALgAECgYJBgAAAA==.Odst:BAAALgADCgUJBwABLgAFFAUJDAACALQZAA==.',
Oh='Ohdatroll:BAABLgAFFH8FAAMDAAIJ0AVWXABIAAADAAIJ0AVWXABIAAAcAAEJIA1tFwA8AAABLgAFFAMJCAAkAEgTAA==.',
Ol='Olgrin:BAAALgADCgkJEgABLgAECgYJBwAHAAAAAA==.',
On='Onepunch:BAAALgAECgEJAQAAAA==.Oneslice:BAAALgAECgUJBgAAAA==.Onyxstar:BAAALgAECgEJAQAAAA==.',
Op='Opera:BAAALgAECgQJBgAAAA==.',
Or='Orangelol:BAAALgAECgUJBQABLgAECgkJIgAhAN4fAA==.Orikkosh:BAABLgAECn8fAAMSAAcJ0haaJQCBAQASAAcJ0haaJQCBAQAcAAIJuwpCcQBNAAAAAA==.Orw:BAAALgAECgIJAgAAAA==.',
Ot='Otsmayo:BAAALgAECgkJBwAAAA==.',
Pa='Palel:BAABLgAECn83AAIJAAkJLRHbKwCyAQAJAAkJLRHbKwCyAQAAAA==.Palpatinee:BAAALgAECgQJBAAAAA==.Pancetta:BAAALgAECgEJAQABLgAECgkJQgARAAskAA==.Parabelum:BAAALgAECgIJAgAAAA==.',
Pb='Pbfearz:BAABLgAECn8WAAMWAAYJhh8TWAC/AQAWAAUJhh8TWAC/AQAXAAEJAADsXgBSAAAAAA==.',
Pe='Peguelo:BAAALgADCgIJAgAAAA==.Pendrágon:BAAALgAECgIJAgAAAA==.Percocetpete:BAACLgAFFH8NAAIEAAUJBRcSEABTAQAEAAUJBRcSEABTAQAuAAQKfx4AAwQACAnaJCQCAE8DAAQACAnaJCQCAE8DABUAAgkmDpN5AEwAAAAA.Peregrine:BAAALgADCgMJAwAAAA==.',
Ph='Phaet:BAACLgAFFH8fAAMWAAYJAyK7LQCOAQAWAAYJAyK7LQCOAQAXAAEJiw5oFQBUAAAuAAQKfzUAAhYACQnxJHQJADMDABYACQnxJHQJADMDAAAA.Phatty:BAAALgADCgMJAwAAAA==.Phaux:BAAALgAECgIJAgAAAA==.Philipp:BAABLgAECn8gAAIKAAkJDwrsLgBlAQAKAAkJDwrsLgBlAQAAAA==.',
Pi='Picco:BAAALgADCgEJAQABLgAECgUJCQAHAAAAAA==.Pixistix:BAAALgAFFAEJAQAAAA==.',
Pl='Plâgue:BAABLgAECn8bAAICAAkJ4xpfTADdAQACAAkJ4xpfTADdAQAAAA==.',
Pn='Pneuma:BAAALgADCgEJAQAAAA==.',
Po='Potentialman:BAAALgAECggJDAAAAA==.',
Pr='Preprot:BAAALgADCgkJCQABLgAECgkJJwAZADoVAA==.Prot:BAAALgAFFAEJAQAAAA==.',
Pu='Punslug:BAAALgAECgYJCgABLgAFFAIJBgAYAM4aAA==.Puntthegnome:BAAALgAFFAEJAQABLgAFFAUJIQAUAI0eAA==.',
['Pó']='Pókóu:BAAALgADCgMJAwAAAA==.',
Ra='Radiance:BAAALgAECgcJDgAAAA==.Raezorian:BAAALgAFFAEJAQABLgAFFAQJBQAcAB8dAA==.Rahmo:BAAALgADCgYJBgAAAA==.Rainforest:BAABLgAECn8eAAIbAAYJkBztGwBuAQAbAAYJkBztGwBuAQAAAA==.Rakiji:BAAALgAECgEJAQAAAA==.Ralphh:BAAALgADCgIJAgAAAA==.Ramdem:BAAALgAECggJEAAAAA==.Ramden:BAABLgAECn86AAIFAAkJPg2+dACEAQAFAAkJPg2+dACEAQAAAA==.Rampant:BAACLgAFFH8MAAICAAUJtBmvTgBVAQACAAUJtBmvTgBVAQAuAAQKfxcAAwIACQkXIEMfAI0CAAIACQkXIEMfAI0CABkAAQmVIBVPAFYAAAAA.Rampscii:BAAALgAECgUJBgABLgAFFAUJDAACALQZAA==.Randalore:BAAALgAECgMJAwABLgAFFAMJCAAkAEgTAA==.Randwulf:BAAALgAECggJEwAAAA==.Ranwong:BAAALgAECgQJCgAAAA==.Ratherton:BAACLgAFFH8hAAIUAAUJjR5sRABfAQAUAAUJjR5sRABfAQAuAAQKfysAAxQACQmbIO0wAK8CABQACQmbIO0wAK8CACgAAwnRHM8NAOkAAAAA.Rathtard:BAABLgAECn8XAAIMAAkJ3BqMIQBfAgAMAAkJ3BqMIQBfAgABLgAFFAUJIQAUAI0eAA==.Rauloso:BAAALgAECgQJEQAAAA==.Ravìn:BAAALgAECgYJDAAAAA==.Rayne:BAAALgAECgcJCAABLgAFFAEJAQAHAAAAAA==.Razz:BAAALgAECgEJAQAAAA==.',
Rd='Rdata:BAAALgADCgkJEAAAAA==.',
Re='Relentlezz:BAAALgADCgMJAwABLgAECgkJLwAdAGUfAA==.Resoluteone:BAABLgAECn9MAAIZAAkJkhViEQD2AQAZAAkJkhViEQD2AQAAAA==.Retnu:BAAALgAECgEJAQAAAA==.Revytwohand:BAACLgAFFH8fAAMcAAYJERwpCwBvAQAcAAUJxSApCwBvAQADAAUJjgzSNADYAAAuAAQKfzQAAhwACQmXJUoEABUDABwACQmXJUoEABUDAAAA.Reáper:BAAALgAECgEJAQAAAA==.',
Rh='Rhagul:BAAALgAFFAIJAgAAAA==.Rhok:BAAALgADCgEJAQAAAA==.Rhokhard:BAAALgADCgEJAwAAAA==.',
Ro='Rocketarena:BAAALgAECgcJDwAAAA==.Rootytooty:BAAALgAECgIJAgAAAA==.Rozelie:BAABLgAFFH8HAAIKAAMJ4hIxMQC9AAAKAAMJ4hIxMQC9AAABLgAFFAcJHwAjAH8aAA==.',
Ry='Ryzarapriest:BAAALgAECgMJBAABLgAFFAEJAQAHAAAAAA==.',
Sa='Sabeladys:BAABLgAECn8oAAIFAAkJRCHLFQDAAgAFAAkJRCHLFQDAAgAAAA==.Sadpeepo:BAAALgADCgIJAgAAAA==.Saifir:BAABLgAECn8pAAIgAAkJBRH1OADMAQAgAAkJBRH1OADMAQAAAA==.Sardmongo:BAAALgADCgcJCgAAAA==.Sardogobo:BAAALgAECgEJAQABLgAECggJIgAWAIEUAA==.Sarduccini:BAABLgAECn8iAAIWAAgJgRTaTADiAQAWAAgJgRTaTADiAQAAAA==.Sargeros:BAAALgAECgQJBAAAAA==.',
Se='Sebastîan:BAAALgAECgEJAQABLgAECgkJIAAWABkZAA==.Sekhmet:BAAALgAECgcJCAAAAA==.Sekio:BAAALgAECgYJCwAAAA==.',
Sh='Shadowpriest:BAAALgADCgEJAQAAAA==.Shamburgyr:BAAALgAECgMJAwABLgAECggJMAAMAIYTAA==.Shampáin:BAAALgADCgEJAQAAAA==.Shanàs:BAAALgAECgEJAQABLgAECgkJGwAFAEYeAA==.Sharayu:BAAALgAECgEJAQAAAA==.Sheamus:BAAALgADCgkJCQAAAA==.Shiftken:BAAALgAECgMJAwAAAA==.Shiftyfive:BAAALgAFFAMJAwAAAA==.Shivà:BAAALgADCgUJCAAAAA==.',
Si='Sigrodah:BAACLgAFFH8PAAMQAAUJ9g8rNQDuAAAQAAQJ9g8rNQDuAAAPAAEJswG2LAA1AAAuAAQKfxkAAxAACAlTH9cRAF0CABAACAlTH9cRAF0CAA4ABAm2EW4pANQAAAAA.Silvalus:BAAALgAECgYJBwAAAA==.Sin:BAAALgAECgkJCQAAAA==.',
Sk='Skaara:BAAALgAECgQJBwAAAA==.Skara:BAAALgADCgEJAQAAAA==.Skiddles:BAAALgADCgIJAgAAAA==.Skinwalker:BAAALgADCgYJCgAAAA==.Skithyryx:BAAALgADCgIJAgAAAA==.Skonka:BAAALgAECgMJAwAAAA==.Skor:BAAALgADCgQJBAAAAA==.Skyblue:BAAALgAECgEJAQAAAA==.Skyeforce:BAAALgAECgMJBQAAAA==.',
Sl='Slipknoth:BAABLgAECn8UAAMJAAYJkRmEUwAsAQAJAAUJFheEUwAsAQAFAAYJoRIQuAAVAQAAAA==.',
Sm='Smellyy:BAAALgADCgEJAQAAAA==.Smite:BAAALgAECgIJAwAAAA==.Smoketurtle:BAAALgAECgUJCAAAAA==.',
Sn='Sno:BAAALgAECgEJAQAAAA==.',
So='Socatoas:BAABLgAECn8ZAAIBAAkJtglqNQBzAQABAAkJtglqNQBzAQAAAA==.Softbanana:BAAALgADCgEJAQAAAA==.Soi:BAAALgAECgYJCgABLgAECgkJGAAFAE0hAA==.Solarion:BAAALgAECgEJAQABLgAECgcJFAAfAEMPAA==.Sonoforak:BAAALgAECgYJBwAAAA==.',
Sp='Sped:BAABLgAECn8zAAQdAAkJih8dBQDKAgAdAAkJih8dBQDKAgAmAAUJswhvLwB6AAABAAEJ9wP3rgAtAAAAAA==.',
St='Stalrun:BAAALgAECgYJCgABLgAECgYJEgAHAAAAAA==.Staraleena:BAAALgAECgUJBQAAAA==.Starrlynn:BAAALgAECgEJAQAAAA==.Stormeyes:BAAALgAECgMJAQABLgAECggJIwAiAOoaAA==.Stormslight:BAABLgAECn8jAAIiAAgJ6hrgDAD3AQAiAAgJ6hrgDAD3AQAAAA==.Stormsteel:BAAALgAECgMJBgAAAA==.Stôrmrägé:BAAALgAECgcJDQAAAA==.',
Sw='Swgchainz:BAAALgAECgcJEwABLgAECgkJLQARADEdAA==.Swiftdéath:BAAALgAECgYJCgAAAA==.Swtbabybilly:BAAALgAECgYJCQAAAA==.',
Sy='Sylvänäs:BAAALgAECgEJAgAAAA==.',
['Sä']='Säberdh:BAAALgADCgYJBgABLgAECgMJAwAHAAAAAA==.',
['Så']='Såran:BAAALgAECgUJCwAAAA==.',
['Sí']='Sílence:BAABLgAECn8VAAIKAAgJrwkUSADsAAAKAAgJrwkUSADsAAAAAA==.',
['Sô']='Sôlrïx:BAAALgAECgUJCgAAAA==.',
Ta='Tabio:BAAALgADCgYJBgAAAA==.Tabios:BAAALgAECgEJAQAAAA==.Tabito:BAAALgAECgEJAQAAAA==.Taby:BAAALgADCgIJAgAAAA==.Talas:BAABLgAECn8wAAIiAAkJnRYtDgDhAQAiAAkJnRYtDgDhAQAAAA==.Taltaelen:BAAALgADCgYJBgABLgAECgkJHwACAA4WAA==.Tamarack:BAABLgAECn8XAAIMAAYJshuJUQB0AQAMAAYJshuJUQB0AQAAAA==.',
Te='Teetsie:BAAALgAFFAEJAQAAAA==.Tehmber:BAAALgAECgQJCAABLgAECgUJBwAHAAAAAA==.Tehmplar:BAAALgAECgUJBwAAAA==.Terrormisu:BAAALgAECgEJAQABLgAECggJGQAFAHEcAA==.',
Th='Thalorien:BAAALgADCgYJBgABLgAECgcJFwAJAIghAA==.Theboart:BAAALgAECgQJCQAAAA==.Thredron:BAABLgAFFH8HAAIJAAMJTAdfNwCQAAAJAAMJTAdfNwCQAAAAAA==.',
Ti='Tilted:BAAALgAECggJCQABLgAECgkJLgAEAIUXAA==.Timebarred:BAAALgAECgEJBAAAAA==.',
To='Tooru:BAACLgAFFH8XAAQMAAYJqhJWOwA2AQAMAAUJMhZWOwA2AQAIAAEJsg5ZMQBNAAAlAAEJXwKTFwBCAAAuAAQKfzYABAwACQm+IYsGACUDAAwACQm+IYsGACUDAAgACAncEOMcALUBACUABgkWGT1LACUBAAAA.Tortiana:BAAALgAECgUJBQAAAA==.Tossko:BAAALgAECgIJAwABLgAECgQJDAAHAAAAAA==.',
Tr='Traefel:BAAALgAECgMJAwAAAA==.Traeflor:BAAALgAECgEJAQAAAA==.Traevok:BAAALgAECgEJAgAAAA==.Trailertrash:BAABLgAECn9EAAIUAAgJnB9NNwA7AgAUAAgJnB9NNwA7AgAAAA==.Treebeef:BAACLgAFFH8dAAIkAAYJpAgrKwALAQAkAAYJpAgrKwALAQAuAAQKfzIAAyQACQkCG+0YAHACACQACQkCG+0YAHACAAoAAQnWA/GMACIAAAAA.Triena:BAAALgAECgQJBgAAAA==.Trirn:BAAALgADCgYJBgAAAA==.Trishool:BAAALgADCgIJAgAAAA==.Trumpeter:BAAALgAECgQJCwAAAA==.Trywind:BAAALgAECgYJBgAAAA==.',
Ts='Tsukuyómi:BAAALgAECgEJAQAAAA==.',
Ty='Tydrielion:BAAALgAECgYJDgAAAA==.Typicaldrood:BAAALgAECgIJAgAAAA==.',
['Tí']='Tízzíts:BAAALgADCgYJBgAAAA==.',
Ul='Ullreich:BAABLgAECn8YAAIMAAcJVwsnjgAjAQAMAAcJVwsnjgAjAQAAAA==.Ulysius:BAACLgAFFH8NAAIFAAQJBRZ7HQDhAAAFAAQJBRZ7HQDhAAAuAAQKfysAAgUACQmWGVs0AC8CAAUACQmWGVs0AC8CAAAA.',
Un='Unfazed:BAAALgAECgEJAQAAAA==.Unicornslayr:BAABLgAECn8qAAIJAAkJTRYTKQDEAQAJAAkJTRYTKQDEAQAAAA==.',
Ur='Urund:BAAALgAECgYJDgAAAA==.',
Uw='Uwantsmoke:BAABLgAECn8eAAIMAAYJMwRsuwDPAAAMAAYJMwRsuwDPAAAAAA==.Uwantsmokee:BAAALgADCgMJAwAAAA==.',
Va='Valgroth:BAAALgAECgIJAwAAAA==.Valkisek:BAACLgAFFH8SAAIUAAQJxhDaXwAhAQAUAAQJxhDaXwAhAQAuAAQKfxkAAhQABwnYGQqbAJ8BABQABwnYGQqbAJ8BAAAA.Valkonigen:BAAALgAECgEJAQAAAA==.Vallarfax:BAABLgAECn8rAAIMAAkJIx/WGACRAgAMAAkJIx/WGACRAgAAAA==.Vandro:BAABLgAECn8qAAQJAAkJlhhuHwAHAgAJAAkJlhhuHwAHAgAFAAQJ4xYbDgANAQAiAAYJ2grlLAC4AAAAAA==.Vantive:BAAALgAECgYJDwAAAA==.Vash:BAAALgAECgEJAQAAAA==.Vashdk:BAACLgAFFH8TAAIZAAYJvRmsFQA/AQAZAAYJvRmsFQA/AQAuAAQKfxUAAhkACAnEFn8QAAMCABkACAnEFn8QAAMCAAAA.Vashmonk:BAACLgAFFH8MAAISAAQJzyO4FAB9AQASAAQJzyO4FAB9AQAuAAQKfxUAAhIACQmcIUQMAHECABIACQmcIUQMAHECAAAA.Vashwar:BAAALgAECgYJBgAAAA==.',
Ve='Vedruid:BAAALgAECggJDwAAAA==.Velaric:BAABLgAECn8vAAMkAAkJyhvFFACkAgAkAAkJyhvFFACkAgAbAAEJ3gv1gQAfAAAAAA==.Velcyn:BAAALgADCgcJDgABLgAECgIJAgAHAAAAAA==.Veldoria:BAAALgAECgQJBgAAAA==.Veloe:BAAALgAECgIJAgAAAA==.Veloranas:BAAALgAECgYJCAAAAA==.Verath:BAAALgADCgEJAQAAAA==.Vespyr:BAABLgAECn8wAAIMAAgJhhN8CAB1AQAMAAgJhhN8CAB1AQAAAA==.Vewdoo:BAABLgAECn8+AAIhAAkJtiS5AgBJAwAhAAkJtiS5AgBJAwAAAA==.',
Vi='Viejoverde:BAAALgAECgQJCAAAAA==.Vipul:BAAALgAECgYJDgAAAA==.Vizimir:BAAALgAECgkJDQAAAA==.',
Vo='Voldune:BAAALgAECgIJAwAAAA==.',
['Vë']='Vëgetå:BAAALgADCgYJBwABLgAECgUJBQAHAAAAAA==.',
Wa='Waiwai:BAAALgAECgEJAgAAAA==.Warfarin:BAAALgAECgEJBAAAAA==.Wascii:BAACLgAFFH8FAAIMAAQJOAvcGAAVAQAMAAQJOAvcGAAVAQAuAAQKfyEAAgwACQkYFX42AAMCAAwACQkYFX42AAMCAAEuAAUUBQkMAAIAtBkA.Waxedthataxe:BAAALgAECgEJAQAAAA==.Waxesaxes:BAAALgAECgQJBwAAAA==.',
We='Weaken:BAAALgAECgUJCwAAAA==.Weskr:BAAALgADCgEJAQABLgAECggJJAAEAKscAA==.',
Wi='Wickedsinner:BAAALgADCgEJAQAAAA==.Wizkerbizkit:BAAALgAECgMJBAAAAA==.',
Wo='Wolvesbane:BAABLgAFFH8FAAIMAAUJbwAYqwBCAAAMAAUJbwAYqwBCAAAAAA==.',
Wy='Wyrmblood:BAAALgAECgcJDgABLgAECgkJNwAVAPsjAA==.Wyrmfur:BAABLgAECn8kAAMbAAgJCCLKAABwAgAbAAgJCCLKAABwAgAYAAQJUh6hHwALAQAAAA==.Wyrmheal:BAABLgAECn83AAIVAAkJ+yO1AAC1AgAVAAkJ+yO1AAC1AgAAAA==.Wyvvie:BAAALgADCgIJAgAAAA==.',
Xa='Xavil:BAAALgAECgEJAQAAAA==.Xavv:BAAALgADCgUJBQAAAA==.',
Xi='Xiba:BAAALgAECgQJBwAAAA==.',
Xl='Xle:BAAALgADCgIJAgAAAA==.',
Ya='Yakoff:BAAALgAECgIJAgAAAA==.Yamihime:BAABLgAECn81AAMRAAkJCxUtGQC4AQARAAgJchYtGQC4AQAGAAkJvwvBXAByAQAAAA==.Yatiri:BAABLgAECn8ZAAMhAAgJxRI+LACUAQAhAAgJxRI+LACUAQAgAAEJQQ6X3gAqAAAAAA==.',
Yo='Yoowuzsup:BAABLgAECn8aAAIhAAcJnBxJMAB+AQAhAAcJnBxJMAB+AQAAAA==.',
Yu='Yureimage:BAABLgAECn8WAAIUAAYJMAtf1wDnAAAUAAYJMAtf1wDnAAAAAA==.',
Za='Zarthus:BAAALgAECggJAgAAAA==.',
Ze='Zeaket:BAACLgAFFH8mAAIIAAgJKR14AQBeAgAIAAgJKR14AQBeAgAuAAQKfy8AAggACQmSIhkBAGEDAAgACQmSIhkBAGEDAAAA.Zedsdeadd:BAAALgAECgYJDwAAAA==.Zephyr:BAABLgAECn8qAAIjAAgJBgjkCADNAAAjAAgJBgjkCADNAAABLgAECggJMAAMAIYTAA==.Zeçhs:BAABLgAECn8YAAIFAAkJTSFZFADxAgAFAAkJTSFZFADxAgAAAA==.',
Zi='Zinek:BAAALgAECgQJBQAAAA==.Zinra:BAAALgAECgUJCwAAAA==.',
Zo='Zoma:BAAALgADCgUJBgAAAA==.Zorcan:BAABLgAECn8oAAINAAkJZxoLBQBBAgANAAkJZxoLBQBBAgAAAA==.',
Zu='Zugzugz:BAAALgAECgEJAgAAAA==.Zulfilith:BAAALgAECgQJBwAAAA==.',
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
