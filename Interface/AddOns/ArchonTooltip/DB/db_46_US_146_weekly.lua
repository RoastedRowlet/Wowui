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

local lookup = {'Warrior-Fury','DeathKnight-Unholy','Monk-Mistweaver','Priest-Holy','Paladin-Retribution','Hunter-BeastMastery','DemonHunter-Devourer','Unknown-Unknown','Hunter-Survival','Paladin-Holy','Druid-Guardian','Druid-Balance','DeathKnight-Frost','Warlock-Affliction','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Havoc','Monk-Brewmaster','Shaman-Enhancement','Mage-Frost','Priest-Shadow','Warlock-Demonology','Warlock-Destruction','Druid-Feral','DeathKnight-Blood','Rogue-Assassination','Monk-Windwalker','Warrior-Protection','Priest-Discipline','DemonHunter-Vengeance','Rogue-Subtlety','Shaman-Restoration','Shaman-Elemental','Paladin-Protection','Druid-Restoration','Hunter-Marksmanship','Warrior-Arms','Rogue-Outlaw','Mage-Arcane',}
local provider = {region='US',realm='Madoran',name='US',type='weekly',zone=46,date='2026-07-28',data={Aa='Aarhus:BAAALgAECgUJCQAAAA==.Aaronmourne:BAAALgAECgQJBAABLgAECgkJGQABALYJAA==.Aaronyates:BAAALgADCgcJBwABLgAFFAUJDAACALQZAA==.',
Ac='Actualegirl:BAABLgAFFH8GAAIDAAUJLQRLNwDLAAADAAUJLQRLNwDLAAABLgAFFAUJDQAEAAUXAA==.',
Ad='Adrenalin:BAAALgADCgEJAQAAAA==.Adversary:BAAALgAECgUJCAAAAA==.',
Ae='Aerfen:BAABLgAECn8cAAIFAAkJyg2QaQCcAQAFAAkJyg2QaQCcAQAAAA==.',
Ag='Agross:BAAALgADCgYJBgAAAA==.',
Ai='Aimforhead:BAAALgAECgcJDAAAAA==.Aiyanna:BAAALgADCggJEgABLgAECgYJGAAGAKULAA==.',
Ak='Akiraha:BAAALgAECgMJDAAAAA==.',
Al='Alexas:BAAALgADCgcJCAAAAA==.Alric:BAABLgAECn80AAIHAAkJYxQeNQDyAQAHAAkJYxQeNQDyAQAAAA==.Alyndra:BAAALgADCgUJBQABLgAECgUJBQAIAAAAAA==.',
Am='Amideus:BAAALgAECgEJAQAAAA==.Amory:BAABLgAECn8mAAICAAkJ9x40IQCDAgACAAkJ9x40IQCDAgAAAA==.',
An='Angela:BAAALgADCgIJAgAAAA==.Annaesthetic:BAAALgAECgEJAwABLgAECgkJOQAJAAgVAA==.',
Ar='Arator:BAAALgADCgEJAgAAAA==.Araña:BAAALgAECgEJAQAAAA==.Arcatraz:BAAALgAECgEJAQAAAA==.Ardaddy:BAAALgAECgYJDQABLgAFFAMJBAAIAAAAAA==.Ardzak:BAAALgAFFAMJBAAAAA==.Arragorn:BAACLgAFFH8IAAIKAAQJFRl9HwAhAQAKAAQJFRl9HwAhAQAuAAQKfycAAgoACQktHLgZADkCAAoACQktHLgZADkCAAAA.Arthora:BAAALgAECgYJBgAAAA==.Arthurworgen:BAAALgADCgYJBgABLgAECgkJLQALAJwfAA==.Arverick:BAAALgAECgYJBgAAAA==.',
As='Asendra:BAABLgAECn8mAAIMAAkJ6xnFEQBLAgAMAAkJ6xnFEQBLAgAAAA==.Assaran:BAAALgAECgIJAgAAAA==.Astal:BAACLgAFFH8LAAINAAUJlA/8DwAYAQANAAUJlA/8DwAYAQAuAAQKfx0AAg0ACQmfGwkHACwCAA0ACQmfGwkHACwCAAAA.',
At='Ate:BAAALgADCgYJBgABLgAECgkJKgAKAE0WAA==.Athenea:BAABLgAECn8aAAIBAAcJUBuYHwDyAQABAAcJUBuYHwDyAQAAAA==.Athénna:BAAALgADCgIJAgABLgAECgkJOQAGAK0UAA==.Atulru:BAAALgADCgMJAwAAAA==.',
Av='Avyl:BAAALgADCgcJBwABLgAECgYJGwAOAPsRAA==.',
Ay='Ayannar:BAAALgADCgEJAQAAAA==.',
Az='Azriella:BAAALgAECgkJDgAAAA==.Azuren:BAABLgAECn9LAAQPAAkJbRovAQCcAQAPAAcJChcvAQCcAQAQAAkJVQs1AwA1AQARAAEJ8wcrHgAaAAAAAA==.',
Ba='Baal:BAAALgAFFAIJAgAAAA==.Bacon:BAABLgAECn9CAAMSAAkJCyRPBQDtAgASAAkJCyRPBQDtAgAHAAcJKRvcSACsAQAAAA==.Bamboozled:BAABLgAECn8VAAMDAAgJbxNTLQDJAQADAAgJbxNTLQDJAQATAAUJ7AOoCQCCAAABLgAFFAMJBAAGAGIIAA==.Bandìt:BAAALgAECggJCwAAAA==.Bankai:BAABLgAFFH8GAAIUAAEJUCULEgBLAAAUAAEJUCULEgBLAAAAAA==.Barbieque:BAAALgADCgcJBwAAAA==.',
Be='Bearyden:BAAALgADCgEJAQAAAA==.Bedbugs:BAAALgAECgQJBAABLgAFFAUJIQAVAI0eAA==.Beefstrasz:BAABLgAECn8aAAMEAAgJuRdiFAAzAgAEAAgJuRdiFAAzAgAWAAEJpwbTkgAoAAAAAA==.Beyla:BAACLgAFFH8IAAIFAAMJQQobegDBAAAFAAMJQQobegDBAAAuAAQKfycAAgUACQkFF4A1ACsCAAUACQkFF4A1ACsCAAAA.',
Bi='Bioactive:BAAALgADCgYJBgAAAA==.Bishamon:BAABLgAECn9OAAQXAAkJ+yHwBQBeAwAXAAkJ+yHwBQBeAwAYAAEJAADAaQA+AAAOAAEJAADlMQA6AAAAAA==.Bizotch:BAAALgAECggJDgAAAA==.',
Bl='Bleau:BAABLgAECn8iAAIZAAkJbxCpEACtAQAZAAkJbxCpEACtAQAAAA==.Blethings:BAAALgAECgMJAwAAAA==.Blinktwice:BAAALgAECgEJAgAAAA==.Bloodimess:BAAALgADCgMJAwAAAA==.Bloodrayna:BAAALgAECgYJBAAAAA==.Bloodymary:BAABLgAECn8nAAIaAAkJOhXwEwDUAQAaAAkJOhXwEwDUAQAAAA==.Bluebarrie:BAAALgAECgEJAQAAAA==.Bluwolferine:BAAALgAECgkJCQAAAA==.Blôodräge:BAAALgAECgcJDgAAAA==.',
Bo='Bootelicious:BAAALgADCgIJAgAAAA==.Bouncybean:BAAALgADCgIJAgAAAA==.',
Br='Bradsupinya:BAABLgAECn8kAAIVAAgJEBl7XgDEAQAVAAgJEBl7XgDEAQAAAA==.Branchling:BAAALgAECgcJEgABLgAFFAUJIQAVAI0eAA==.Brewswane:BAAALgAFFAEJAwABLgAFFAkJLAAbAFsUAA==.Bridh:BAABLgAECn8aAAIHAAkJFR5LEQD0AgAHAAkJFR5LEQD0AgABLgAFFAgJHwAYABIcAA==.Bromm:BAAALgAECgEJAQAAAA==.Brunor:BAAALgAECgkJDAAAAA==.',
Bu='Bulkamania:BAAALgAECgMJAwAAAA==.Butterkip:BAACLgAFFH8PAAIWAAUJfBSxFgAvAQAWAAUJfBSxFgAvAQAuAAQKfysAAhYACQlpHikKAOACABYACQlpHikKAOACAAAA.',
['Bë']='Bëarclaw:BAAALgAECgUJBQAAAA==.',
Ca='Cai:BAAALgAECgMJAwABLgAECgkJLQAVAN8PAA==.Cambria:BAAALgAECgMJAwAAAA==.Cantkillme:BAAALgAECgQJBwAAAA==.Canukillme:BAAALgADCgYJBgAAAA==.Carloos:BAAALgAFFAEJAQAAAA==.Carruel:BAAALgADCgUJBQAAAA==.Cazzc:BAAALgAECgUJCAAAAA==.',
Ce='Cellan:BAABLgAECn8XAAICAAcJ6wqKvQABAQACAAcJ6wqKvQABAQAAAA==.Censora:BAAALgAECgEJAQAAAA==.',
Ch='Cheww:BAAALgADCgUJBQAAAA==.Chicharrones:BAAALgAECgUJBQABLgAECgkJQgASAAskAA==.Chickenshift:BAABLgAECn8tAAMLAAkJnB/wDAATAgALAAgJpR7wDAATAgAZAAQJoBvIHAAkAQAAAA==.Chipahoy:BAABLgAECn8nAAIFAAgJdRw/OAAhAgAFAAgJdRw/OAAhAgABLgAECggJRAAVAJwfAA==.Chlorofõrm:BAAALgAECgIJAwABLgAECgkJOQAJAAgVAA==.Chopahoe:BAAALgAECgQJBwAAAA==.Chuggz:BAABLgAECn8gAAIcAAkJ5xE1HwCzAQAcAAkJ5xE1HwCzAQAAAA==.',
Ci='Cindywoohoo:BAAALgAECgMJBQAAAA==.',
Cl='Clamadin:BAAALgAECgIJAgABLgAFFAgJJQAVAKccAA==.Clamius:BAACLgAFFH8lAAIVAAgJpxwjDACOAgAVAAgJpxwjDACOAgAuAAQKfyoAAhUACQkkJRALACEDABUACQkkJRALACEDAAAA.Cliff:BAAALgAECgUJBgAAAA==.',
Co='Colby:BAAALgAECgYJDgAAAA==.Coldass:BAABLgAECn8ZAAIVAAgJwRJjZgCxAQAVAAgJwRJjZgCxAQAAAA==.Coldstone:BAAALgAECgYJCAAAAA==.Commodus:BAAALgADCgQJBAAAAA==.Conduit:BAAALgAECgUJBwAAAA==.Coombrain:BAAALgAECgUJCQAAAA==.Cotopla:BAAALgAECgQJDAAAAA==.',
Cr='Critterzz:BAABLgAECn8aAAIEAAgJ4hb6FwAcAgAEAAgJ4hb6FwAcAgAAAA==.Cryptkeys:BAAALgAECgMJAwAAAA==.',
Cu='Cuziseeu:BAAALgAECgQJBAABLgAECgYJBgAIAAAAAA==.',
Da='Dachyy:BAAALgAECgkJEwAAAA==.Daemonwaters:BAAALgAECgEJAQAAAA==.Dagov:BAAALgAECgYJCAAAAA==.Daiana:BAAALgAECgIJAgAAAA==.Damage:BAAALgAFFAEJAQAAAA==.Damocles:BAAALgAFFAEJAQAAAA==.Darkråii:BAAALgAECgIJAwAAAA==.Dashboy:BAAALgADCgEJAQAAAA==.',
De='Deafniteelf:BAAALgAECgkJDQAAAA==.Deathlentlez:BAABLgAECn8vAAIdAAkJZR86BwCSAgAdAAkJZR86BwCSAgAAAA==.Decaylentlez:BAAALgAECgEJAQABLgAECgkJLwAdAGUfAA==.Deepwinter:BAAALgAECgcJDQABLgAFFAUJDAACALQZAA==.Delphyne:BAABLgAECn8UAAIPAAYJ9wvxEQDrAAAPAAYJ9wvxEQDrAAAAAA==.Delylee:BAAALgAECgIJAgAAAA==.Demandred:BAAALgAECgcJDAAAAA==.Demonhunter:BAABLgAECn8gAAISAAkJuhiWDgA8AgASAAkJuhiWDgA8AgAAAA==.Demonià:BAABLgAECn8jAAIVAAkJ7Ap9FwAHAQAVAAkJ7Ap9FwAHAQAAAA==.Descimus:BAABLgAECn8kAAQEAAgJqxzFDQB+AgAEAAgJ2BvFDQB+AgAeAAUJDBd+LwAkAQAWAAMJpRcEYACYAAAAAA==.Desong:BAAALgADCgYJBwAAAA==.Detharbinger:BAAALgAECgcJDQAAAA==.Dethgripz:BAABLgAFFH8LAAICAAUJNAyCIABVAQACAAUJNAyCIABVAQAAAA==.Dezzan:BAAALgADCgQJBwAAAA==.',
Di='Diamathius:BAAALgAECgQJBAAAAA==.Diamondsword:BAAALgAECggJDgAAAA==.Dieanah:BAAALgADCgcJBwAAAA==.',
Dj='Djazz:BAAALgAECggJCgAAAA==.',
Do='Dochaze:BAABLgAECn8qAAMKAAkJfxyHHwAdAgAKAAgJPB+HHwAdAgAFAAMJjA1KIAGTAAAAAA==.Dogdimmadome:BAAALgAECgYJDwAAAA==.Dolore:BAAALgADCgcJBgAAAA==.Donut:BAAALgADCgIJAgABLgAECgkJLgAFAFEaAA==.Doublejump:BAAALgAECgEJAQABLgAECgkJJwAaADoVAA==.',
Dr='Dragone:BAAALgAECgUJCQAAAA==.Dragun:BAAALgADCgUJBQABLgAECgkJLgAFAFEaAA==.Drowsee:BAAALgAECgUJBgAAAA==.Dráconus:BAAALgADCgMJAwAAAA==.',
Du='Dumbdumb:BAAALgAECgQJBgAAAA==.',
Dy='Dyanuh:BAABLgAECn8eAAIWAAYJygIeagB2AAAWAAYJygIeagB2AAAAAA==.',
['Dà']='Dàrkscythe:BAABLgAECn8cAAMaAAcJmAVLPACgAAAaAAcJuQRLPACgAAANAAEJiQZqPwAoAAAAAA==.',
Ea='Eazywin:BAAALgAECggJCQAAAA==.',
Eh='Ehlsa:BAAALgADCgcJBwAAAA==.Ehlsi:BAABLgAECn8xAAMfAAkJUR/PAgDFAgAfAAkJUR/PAgDFAgASAAIJ1BvOFgBUAAAAAA==.Ehress:BAAALgAECgcJEwABLgAFFAUJDAACALQZAA==.',
Ei='Eirinny:BAABLgAECn8tAAIUAAkJWQq6EwB9AQAUAAkJWQq6EwB9AQAAAA==.',
El='Elindez:BAABLgAECn8nAAIgAAkJUw+YGADVAQAgAAkJUw+YGADVAQAAAA==.Elyviel:BAAALgAFFAEJAQAAAA==.Elàine:BAABLgAECn83AAIGAAgJLQu0HwDMAAAGAAgJLQu0HwDMAAAAAA==.',
Em='Emika:BAAALgADCgUJDgAAAA==.Emyrson:BAAALgAECgQJCQAAAA==.',
En='Encantado:BAAALgAECgUJBQAAAA==.Enemywithin:BAAALgADCgIJAgAAAA==.Enzo:BAAALgADCgYJCwAAAA==.',
Ep='Epicfury:BAAALgAECgYJDgAAAA==.',
Eq='Eq:BAAALgADCgUJBgAAAA==.',
Ez='Ezmee:BAABLgAECn8aAAIVAAYJkQ02GgDxAAAVAAYJkQ02GgDxAAAAAA==.',
Fa='Facingworlds:BAAALgAECggJDgAAAA==.Fathercaleb:BAAALgAECgIJAwABLgAFFAcJIAAcAFsaAA==.Fazed:BAAALgAECgIJBgAAAA==.Fazeo:BAAALgAECgQJBQAAAA==.',
Fe='Featherstep:BAAALgADCgMJAwAAAA==.Felysse:BAAALgADCgEJAQAAAA==.',
Fi='Fireball:BAAALgAECgIJAgABLgAFFAEJAQAIAAAAAA==.',
Fl='Flavio:BAAALgAECgQJCAAAAA==.',
Fo='Fortuna:BAABLgAECn8kAAIUAAkJxASQGQA4AQAUAAkJxASQGQA4AQAAAA==.',
Fr='Francesca:BAAALgADCgEJAQAAAA==.Frosilen:BAABLgAECn87AAMhAAkJCxDoQQCmAQAhAAkJCxDoQQCmAQAiAAMJaQtgewB9AAAAAA==.Frostbite:BAAALgADCgIJAgAAAA==.',
Ga='Gamaikuba:BAAALgADCggJCQAAAA==.Gamarth:BAAALgAECgYJDQAAAA==.Gatlu:BAABLgAECn8hAAILAAkJcBYzDQAOAgALAAkJcBYzDQAOAgAAAA==.Gawdsmackk:BAAALgAECggJDgABLgAFFAEJAQAIAAAAAA==.Gaz:BAAALgADCgMJAwAAAA==.Gazokks:BAAALgADCgcJBwAAAA==.',
Ge='Gedank:BAAALgADCgcJBwAAAA==.Geodemon:BAAALgAECgQJBAAAAA==.Gethealed:BAAALgAECgcJEAAAAA==.Getrektpos:BAAALgADCgMJAwAAAA==.',
Gh='Ghostlock:BAABLgAECn8VAAIOAAgJzxn2BQAFAgAOAAgJzxn2BQAFAgAAAA==.Ghoztface:BAABLgAECn8oAAMjAAcJcxzHDgDYAQAjAAYJXCDHDgDYAQAFAAcJJxLmmgA/AQAAAA==.Ghöstbeef:BAAALgADCgkJEAABLgAECggJGgAEALkXAA==.',
Gi='Giblock:BAABLgAECn8XAAIOAAgJCBRNDwBoAQAOAAgJCBRNDwBoAQAAAA==.',
Gl='Glamorus:BAAALgAECgUJBQAAAA==.Glamour:BAAALgAECgQJEgAAAA==.Glitterboy:BAAALgAECgIJAgABLgAFFAgJIwAcACIfAA==.',
Go='Golomojek:BAABLgAECn8aAAIiAAkJVA0bCwD2AAAiAAkJVA0bCwD2AAAAAA==.Gorkun:BAAALgADCgkJDgAAAA==.Gov:BAACLgAFFH8YAAMSAAcJMBvgEAAcAQAHAAcJ4Bl3PAA0AQASAAUJfhXgEAAcAQAuAAQKfygAAwcACQm/JYsIAEUDAAcACQm/JYsIAEUDABIAAQlSEjpsADkAAAAA.Govndrag:BAAALgADCgEJAQAAAA==.Govs:BAACLgAFFH8GAAQEAAMJohhuIwCgAAAEAAIJBiJuIwCgAAAWAAIJcha/LACYAAAeAAIJdghtQAB4AAAuAAQKfxUAAwQACAmVHqAPAG4CAAQACAmVHqAPAG4CABYAAwmVHhFYALQAAAAA.',
Gr='Gralmerte:BAACLgAFFH8QAAMZAAQJFiI1AgBmAQAZAAQJFiI1AgBmAQAkAAIJdB6uFwCsAAAuAAQKfzYAAxkACQnNIu4BABYDABkACQnNIu4BABYDACQAAQn3FIfGADwAAAAA.Grawfern:BAAALgAFFAEJAQAAAA==.Graygoyle:BAABLgAECn8hAAIbAAkJSgb7DABbAQAbAAkJSgb7DABbAQAAAA==.Groggaris:BAAALgAECgMJAwAAAA==.Groosalugg:BAABLgAECn8dAAIGAAkJtx2KKwAvAgAGAAkJtx2KKwAvAgAAAA==.',
Gu='Guillotine:BAAALgAECgEJAQAAAA==.Guldave:BAAALgAECgQJBAAAAA==.Guthrie:BAABLgAECn8WAAIKAAcJ2BczKgC9AQAKAAcJ2BczKgC9AQAAAA==.',
Gw='Gwyndolïn:BAABLgAECn8eAAMDAAcJ6RiIMAC4AQADAAcJ6RiIMAC4AQAcAAQJnAR6bQB3AAAAAA==.',
Ha='Hachendis:BAAALgADCgMJAwAAAA==.Haether:BAABLgAECn8uAAIhAAkJdBHnLQD/AQAhAAkJdBHnLQD/AQAAAA==.Haliax:BAAALgAECgEJAQABLgAECgkJGAAFAE0hAA==.Hammatime:BAAALgADCgcJBwAAAA==.Hatsu:BAABLgAECn8VAAIDAAkJSgxFPAB/AQADAAkJSgxFPAB/AQAAAA==.Hawktuahh:BAAALgAECgIJAgAAAA==.',
He='Hellá:BAAALgADCgIJAgAAAA==.Hemandunter:BAAALgAECgEJAQAAAA==.Hext:BAAALgAECgIJAgAAAA==.',
Hi='Hildunn:BAAALgAECgQJBgAAAA==.Hingedh:BAABLgAFFH8FAAIHAAMJ9g6uJwCjAAAHAAMJ9g6uJwCjAAABLgAFFAcJJAAgAMccAA==.Hitemup:BAAALgADCgQJBAAAAA==.',
Hk='Hktanker:BAAALgADCgQJBAABLgAECgYJGAAGAKULAA==.',
Ho='Holylentlezz:BAAALgADCgcJBwABLgAECgkJLwAdAGUfAA==.Holymun:BAABLgAECn8uAAIFAAkJURqRBABeAgAFAAkJURqRBABeAgAAAA==.Holyox:BAABLgAECn84AAIFAAkJngxbdgCBAQAFAAkJngxbdgCBAQAAAA==.Hotcheeto:BAAALgAECgkJEwAAAA==.',
Ht='Hturtle:BAAALgADCgEJAQAAAA==.Hturtledk:BAABLgAECn8VAAMCAAYJvxaKnwAtAQACAAYJvxaKnwAtAQAaAAEJ3QJYawAUAAAAAA==.',
Hu='Hug:BAAALgAECgUJCAAAAA==.',
['Hü']='Hüntress:BAAALgAFFAEJAgAAAA==.',
Ia='Iacey:BAAALgAECgIJAgAAAA==.',
Im='Imdatroll:BAACLgAFFH8IAAMkAAMJSBNyNwDPAAAkAAMJSBNyNwDPAAAZAAIJrxOuFQCDAAAuAAQKfzIABBkACQneIzYCADEDABkACQneIzYCADEDACQABgkUGRZZAC0BAAwAAgndC9ZyAGEAAAAA.Imgibby:BAAALgADCgYJBgABLgAECggJFwAOAAgUAA==.Impius:BAAALgAECgkJCgAAAA==.Impmageddon:BAABLgAECn8aAAMXAAkJnRF6ZQBzAQAXAAkJnRF6ZQBzAQAYAAEJAAASdQAwAAAAAA==.',
In='Inexorable:BAABLgAFFH8IAAIFAAMJjxR7HwCwAAAFAAMJjxR7HwCwAAAAAA==.',
Ir='Irakwa:BAABLgAECn8UAAIGAAUJeQkIwgDDAAAGAAUJeQkIwgDDAAAAAA==.',
It='Itches:BAACLgAFFH8jAAIcAAgJIh8sAQChAgAcAAgJIh8sAQChAgAuAAQKfyAAAhwACAkHJOYDAE8DABwACAkHJOYDAE8DAAAA.',
Iw='Iwamori:BAAALgAECgEJAQAAAA==.',
Iz='Izánámi:BAABLgAECn85AAQJAAgJCBVoAwBfAQAJAAgJCBVoAwBfAQAGAAEJ8A19ywA6AAAlAAEJlwGPmAAeAAAAAA==.',
Ja='Jaason:BAAALgAECgYJBgABLgAFFAMJBQARAHYRAA==.Jagon:BAACLgAFFH8FAAIRAAMJdhEpIACoAAARAAMJdhEpIACoAAAuAAQKfy8ABBEACQkKGvARAFMCABEACQkKGvARAFMCABAAAgm1B2A1AFAAAA8AAgkfDMIlADQAAAAA.Jalen:BAAALgAECgYJBgAAAA==.Janvi:BAAALgAECgMJBQAAAA==.Jarbito:BAAALgAECgUJCwAAAA==.Jarico:BAAALgAECgYJEAABLgAECgYJEgAIAAAAAA==.Jasint:BAAALgAECgUJBQABLgAFFAMJBQARAHYRAA==.',
Je='Jebrogue:BAAALgADCgkJDgAAAA==.',
Jh='Jhunts:BAAALgAECggJEAAAAA==.',
Ji='Jinbloom:BAAALgADCgIJAgAAAA==.Jincrush:BAAALgAECgIJAgAAAA==.Jindabutt:BAABLgAECn8mAAITAAkJYyAXBgDbAgATAAkJYyAXBgDbAgAAAA==.Jinfuse:BAAALgADCgUJBQAAAA==.Jinkybell:BAAALgAECgUJBwAAAA==.Jintonic:BAAALgAECgcJCAAAAA==.',
Jk='Jkbalo:BAABLgAFFH8FAAMmAAIJHwWAIgA6AAABAAIJ8gBKVgA+AAAmAAIJHwWAIgA6AAAAAA==.Jkrlos:BAAALgAFFAMJBAAAAA==.',
Jo='Jocommande:BAAALgAECgEJAQAAAA==.Jointheraid:BAAALgADCgMJAwAAAA==.Jokerstree:BAAALgADCgYJBgAAAA==.Jorah:BAAALgADCgcJCgAAAA==.Jorkah:BAAALgADCgcJCgAAAA==.',
Jp='Jpdh:BAACLgAFFH8UAAMfAAQJZSO6BAAnAQAHAAQJLSMsLwBpAQAfAAMJ2yK6BAAnAQAuAAQKfyoABB8ACQl3JKQEAHACAAcACQmfIGwYAMMCAB8ACAk8JaQEAHACABIABQmbFo9EAOQAAAAA.Jphunt:BAAALgADCgUJBQABLgAFFAQJFAAfAGUjAA==.',
Ju='Juddory:BAABLgAECn8kAAIVAAgJjw2EqQAsAQAVAAgJjw2EqQAsAQAAAA==.Junksvil:BAAALgAECgYJEgAAAA==.',
['Jø']='Jøhnwick:BAAALgADCgYJBgAAAA==.',
Ka='Kahrahkon:BAAALgAECgQJDgAAAA==.Kalinis:BAAALgAECgIJAwAAAA==.Kanadoria:BAAALgAECgQJBgAAAA==.Kanion:BAAALgAECgYJCgAAAA==.Kargorr:BAAALgAECgMJAwAAAA==.',
Ke='Kenth:BAAALgAECgEJAQAAAA==.Keranøs:BAAALgAECgEJAQAAAA==.',
Kh='Khudoz:BAAALgAECgMJBwAAAA==.',
Ki='Killerelf:BAAALgADCggJCAAAAA==.Killshotz:BAAALgADCgUJBQAAAA==.Kismët:BAAALgAECgEJAQAAAA==.',
Kl='Klid:BAAALgADCgMJAwABLgAFFAIJBQAFAIIUAA==.',
Ko='Koa:BAAALgAECgEJAQAAAA==.Kooch:BAAALgADCgYJBgAAAA==.Korinth:BAECLgAFFH8fAAMjAAcJURM9CQDiAAAjAAYJZhY9CQDiAAAFAAEJ6AMAAAAAAAAuAAQKfz0AAiMACQnnG10HAGkCACMACQnnG10HAGkCAAAA.Kovala:BAAALgAECgEJAQAAAA==.',
Kr='Kriaalis:BAACLgAFFH8MAAMhAAMJFgRGNwBoAAAhAAMJFgRGNwBoAAAiAAIJ+ADXPgAdAAAuAAQKfxUAAyEACQlIBct6AO8AACEACAn6BMt6AO8AACIAAQmqBVvDABkAAAAA.Krul:BAAALgADCgQJBwAAAA==.',
Ku='Kunitsu:BAAALgAFFAEJAQAAAA==.Kurzon:BAAALgADCgMJAwABLgAECgkJHQAGALcdAA==.',
Ky='Kyra:BAAALgAECgUJDwAAAA==.',
['Kæ']='Kælas:BAAALgAECgEJAgAAAA==.',
La='Lachryma:BAAALgADCgUJBQAAAA==.Laríssa:BAEBLgAFFH8JAAIWAAUJrg1ZEgDMAAAWAAUJrg1ZEgDMAAAAAA==.Layala:BAAALgAECgEJAQAAAA==.Lazuli:BAAALgAECgYJBgABLgAECgkJQgASAAskAA==.',
Le='Legault:BAABLgAECn8rAAInAAkJIB9pAQDmAgAnAAkJIB9pAQDmAgAAAA==.Legionofboom:BAAALgADCgQJBgAAAA==.Lethfel:BAABLgAECn8VAAMXAAgJ4xs4WgCPAQAXAAYJYBw4WgCPAQAYAAYJlRbkIABNAQAAAA==.Lethferal:BAAALgADCgIJAgAAAA==.',
Li='Liacci:BAAALgADCgYJBgAAAA==.Lideyvia:BAAALgADCggJCAAAAA==.Lilgoukii:BAAALgADCgIJAgAAAA==.Lillithfaust:BAAALgAECgMJCQAAAA==.Lilreaper:BAAALgADCgkJCwAAAA==.Limbø:BAABLgAECn8eAAIVAAcJLCFSSQD/AQAVAAcJLCFSSQD/AQAAAA==.Lindia:BAAALgADCgEJAQAAAA==.Lionfury:BAAALgAECgEJAgAAAA==.Lionguard:BAAALgAECgUJBQAAAA==.Liquidturtle:BAAALgAECgMJBAAAAA==.Livie:BAABLgAECn8oAAIFAAkJlBgQNQAsAgAFAAkJlBgQNQAsAgAAAA==.',
Lo='Lonelylad:BAAALgAECgEJAQAAAA==.Loneshark:BAAALgAECgYJCQAAAA==.Longwood:BAAALgAECgYJCAAAAA==.Lonon:BAAALgADCgQJBAAAAA==.Loops:BAAALgAECgIJBAAAAA==.Loraddesmos:BAACLgAFFH8FAAIYAAMJXAX/CACVAAAYAAMJXAX/CACVAAAuAAQKf0MAAhgACQmWFP4GAOsBABgACQmWFP4GAOsBAAAA.Loriah:BAABLgAECn8wAAIFAAkJShXTRwDvAQAFAAkJShXTRwDvAQAAAA==.Lovan:BAAALgAECgEJAwAAAA==.',
Lu='Lucance:BAAALgAECgIJAgAAAA==.Lullaby:BAABLgAECn8vAAIEAAkJhRcQFgAiAgAEAAkJhRcQFgAiAgAAAA==.Lumot:BAAALgADCgcJCwAAAA==.',
Ma='Maeg:BAAALgAECgIJAgABLgAFFAMJCAAkAEgTAA==.Mahll:BAAALgAFFAIJAgABLgAFFAMJCgAVAMgbAA==.Maireldps:BAAALgAECgcJDgAAAA==.Manawarr:BAAALgAECgIJAwAAAA==.Marcdofu:BAAALgAECgQJBQAAAA==.Maryjanè:BAAALgAECgUJBQAAAA==.Mataquay:BAAALgAECggJEAAAAA==.Maveloris:BAAALgADCgcJBgAAAA==.Mavennes:BAAALgAECgQJAwAAAA==.Mawzshallah:BAACLgAFFH8dAAIMAAYJ5yN2EACiAQAMAAYJ5yN2EACiAQAuAAQKfzMAAwwACQllJWgBAMEDAAwACQllJWgBAMEDAAsABQl6FLMTADQBAAAA.Mayli:BAAALgAFFAMJAwAAAA==.',
Mc='Mctanker:BAABLgAECn8aAAMjAAcJUBGKHQApAQAjAAcJUBGKHQApAQAFAAUJBgte9wDCAAAAAA==.',
Me='Meascii:BAACLgAFFH8bAAIeAAUJlQsfEQAZAQAeAAUJlQsfEQAZAQAuAAQKfyQAAh4ACQlaGRMOAIwCAB4ACQlaGRMOAIwCAAAA.Medeaeris:BAAALgADCgIJAgAAAA==.Meepmorp:BAAALgAECgEJAQAAAA==.Megs:BAAALgADCgYJBgAAAA==.Merc:BAACLgAFFH8jAAIcAAgJLB7XAgAuAgAcAAgJLB7XAgAuAgAuAAQKfzoAAhwACQksI5kFAPcCABwACQksI5kFAPcCAAAA.',
Mi='Millee:BAABLgAECn8hAAMEAAgJZBx/GAAJAgAEAAgJZBx/GAAJAgAWAAIJpgPGhQA0AAAAAA==.Mincebeef:BAAALgAECgMJAwABLgAECggJGgAEALkXAA==.Mindpuck:BAAALgAECgQJBAAAAA==.Mirefighter:BAAALgAECgMJAwABLgAFFAcJIAAZABYdAA==.Miremana:BAAALgAECgcJDwABLgAFFAcJIAAZABYdAA==.Mirespike:BAACLgAFFH8gAAIZAAcJFh09AwCZAQAZAAcJFh09AwCZAQAuAAQKfzIAAhkACQlSIpkDAPgCABkACQlSIpkDAPgCAAAA.Mistylady:BAAALgADCgIJBAAAAA==.',
Mo='Mommacougar:BAAALgADCgEJAQAAAA==.Moondrade:BAAALgAECgUJBQAAAA==.Moosebearowl:BAAALgAFFAMJAwAAAA==.Morfirrann:BAAALgADCgEJAQAAAA==.Morlis:BAAALgAECgQJCAAAAA==.Morlock:BAABLgAECn8rAAMXAAkJvQtXWgCPAQAXAAkJvQtXWgCPAQAOAAEJWwgfNQAxAAAAAA==.Morningstahr:BAAALgAECgUJBQAAAA==.',
Mu='Murlen:BAAALgAECgMJBAAAAA==.',
My='Mystris:BAAALgADCgYJBgAAAA==.Mythidru:BAAALgAECgcJDgAAAA==.',
['Mâ']='Mâjestic:BAAALgADCgMJAwAAAA==.',
Na='Naanbread:BAAALgAFFAIJAgAAAA==.Naaruto:BAABLgAECn8aAAIFAAgJzQ6+iwBZAQAFAAgJzQ6+iwBZAQAAAA==.Nanako:BAABLgAECn8zAAIVAAkJrxh5LwBbAgAVAAkJrxh5LwBbAgAAAA==.Naughtyvixen:BAAALgAECgMJAgABLgAECgkJJAAdAOAJAA==.Naughtyvoked:BAAALgAECgYJCgABLgAECgkJJAAdAOAJAA==.Navali:BAAALgAECgMJCAABLgAFFAEJAQAIAAAAAA==.',
Ne='Nefer:BAAALgADCgUJBQAAAA==.Nevicus:BAAALgAECgIJAwAAAA==.',
Ni='Nickayla:BAAALgADCggJCAAAAA==.Nikkaya:BAAALgAECgMJAwABLgAECgYJHgALAJAcAA==.Nimblecow:BAAALgAECgUJBQAAAA==.Nisdenar:BAAALgADCgkJDgAAAA==.',
No='Noobacleese:BAABLgAECn8wAAIFAAkJrxvsLABNAgAFAAkJrxvsLABNAgAAAA==.Noraviae:BAAALgADCgMJAwAAAA==.',
Nu='Nutbustin:BAABLgAECn8hAAIVAAkJBhntQAAZAgAVAAkJBhntQAAZAgAAAA==.',
Ny='Nyghtrider:BAABLgAECn8YAAIGAAYJpQuloQD+AAAGAAYJpQuloQD+AAAAAA==.Nykayla:BAAALgAECgcJAwAAAA==.Nymëra:BAABLgAECn8fAAIhAAkJ7w1BVABjAQAhAAkJ7w1BVABjAQAAAA==.Nyneeve:BAABLgAECn9BAAIWAAkJBRQjBQCGAQAWAAkJBRQjBQCGAQAAAA==.',
Ob='Obscené:BAAALgAECgQJBAAAAA==.',
Od='Oddessyee:BAAALgADCgcJBwABLgAECggJGAAGAPUYAA==.Oddiee:BAABLgAECn8YAAMCAAcJNw/FrAAZAQACAAcJNw/FrAAZAQAaAAQJzgP0OQB0AAABLgAECggJGAAGAPUYAA==.Odinshunter:BAAALgAECgYJBgAAAA==.Odst:BAAALgADCgUJBwABLgAFFAUJDAACALQZAA==.',
Oh='Ohdatroll:BAABLgAFFH8FAAMDAAIJ0AVWXABIAAADAAIJ0AVWXABIAAAcAAEJIA3yHwA3AAABLgAFFAMJCAAkAEgTAA==.',
Ol='Olgrin:BAAALgAECgEJAgABLgAECgYJCwAIAAAAAA==.',
On='Onepunch:BAAALgAECgEJAQAAAA==.Oneslice:BAAALgAECgUJBgAAAA==.Onyxstar:BAAALgAECgEJAQAAAA==.',
Op='Opera:BAAALgAECgQJBgAAAA==.',
Or='Orangelol:BAAALgAECgUJBQABLgAFFAMJBQAiAAkhAA==.Orikkosh:BAABLgAECn8fAAMTAAcJ0haaJQCBAQATAAcJ0haaJQCBAQAcAAIJuwpCcQBNAAAAAA==.Orw:BAAALgAECgMJAwAAAA==.',
Ot='Otsmayo:BAAALgAECgkJBwAAAA==.',
Pa='Palel:BAABLgAECn83AAIKAAkJLRHbKwCyAQAKAAkJLRHbKwCyAQAAAA==.Palpatinee:BAAALgAECgQJBAAAAA==.Pancetta:BAAALgAECgEJAQABLgAECgkJQgASAAskAA==.Parabelum:BAAALgAECgIJAgAAAA==.',
Pb='Pbfearz:BAABLgAECn8WAAMXAAYJhh8TWAC/AQAXAAUJhh8TWAC/AQAYAAEJAADsXgBSAAAAAA==.',
Pe='Peguelo:BAAALgADCgIJAgAAAA==.Pendrágon:BAAALgAECgIJAgAAAA==.Percocetpete:BAACLgAFFH8NAAIEAAUJBRcSEABTAQAEAAUJBRcSEABTAQAuAAQKfx4AAwQACAnaJCQCAE8DAAQACAnaJCQCAE8DABYAAgkmDpN5AEwAAAAA.Peregrine:BAAALgADCgMJAwAAAA==.',
Ph='Phaet:BAACLgAFFH8gAAMXAAcJmyK7LQCOAQAXAAcJmyK7LQCOAQAYAAEJiw5oFQBUAAAuAAQKfzUAAhcACQnxJHQJADMDABcACQnxJHQJADMDAAAA.Phatty:BAAALgADCgMJAwAAAA==.Phaux:BAAALgAECgIJAgAAAA==.Philipp:BAABLgAECn8gAAIMAAkJDwrsLgBlAQAMAAkJDwrsLgBlAQAAAA==.',
Pi='Picco:BAAALgADCgEJAQABLgAECgUJCQAIAAAAAA==.Piper:BAABLgAECn8gAAQeAAYJnBBYDQDjAAAeAAYJkBBYDQDjAAAEAAUJBAl8TQCtAAAWAAMJ9gJgeABPAAAAAA==.Pixistix:BAAALgAFFAEJAQAAAA==.',
Pl='Plâgue:BAABLgAECn8bAAICAAkJ4xpfTADdAQACAAkJ4xpfTADdAQAAAA==.',
Pn='Pneuma:BAAALgADCgEJAQAAAA==.',
Po='Potentialman:BAAALgAECggJDAAAAA==.',
Pr='Preprot:BAAALgADCgkJCQABLgAECgkJJwAaADoVAA==.Prot:BAAALgAFFAEJAQAAAA==.',
Pu='Punslug:BAAALgAECgYJCgABLgAFFAIJBgAZAM4aAA==.Puntthegnome:BAABLgAFFH8FAAICAAMJownRTQC2AAACAAMJownRTQC2AAABLgAFFAUJIQAVAI0eAA==.',
['Pó']='Pókóu:BAAALgADCgMJAwAAAA==.',
Ra='Radiance:BAAALgAECgcJEwAAAA==.Raezorian:BAAALgAFFAEJAQABLgAFFAQJBQAcAB8dAA==.Rahmo:BAAALgADCgYJBgAAAA==.Rainforest:BAABLgAECn8eAAILAAYJkBztGwBuAQALAAYJkBztGwBuAQAAAA==.Rakiji:BAAALgAECgEJAQAAAA==.Ralphh:BAAALgADCgIJAgAAAA==.Ramdem:BAAALgAECggJEAAAAA==.Ramden:BAABLgAECn86AAIFAAkJPg2+dACEAQAFAAkJPg2+dACEAQAAAA==.Rampant:BAACLgAFFH8MAAICAAUJtBmvTgBVAQACAAUJtBmvTgBVAQAuAAQKfxcAAwIACQkXIEMfAI0CAAIACQkXIEMfAI0CABoAAQmVIBVPAFYAAAAA.Rampscii:BAAALgAECgUJBgABLgAFFAUJDAACALQZAA==.Randalore:BAAALgAECgMJAwABLgAFFAMJCAAkAEgTAA==.Randwulf:BAAALgAECggJEwAAAA==.Ranwong:BAAALgAECgQJCgAAAA==.Ratherton:BAACLgAFFH8hAAIVAAUJjR5sRABfAQAVAAUJjR5sRABfAQAuAAQKfysAAxUACQmbIO0wAK8CABUACQmbIO0wAK8CACgAAwnRHM8NAOkAAAAA.Rathtard:BAABLgAECn8XAAIGAAkJ3BqMIQBfAgAGAAkJ3BqMIQBfAgABLgAFFAUJIQAVAI0eAA==.Rauloso:BAAALgAECgQJEQAAAA==.Ravìn:BAAALgAECgYJDAAAAA==.Rayne:BAAALgAECgcJCAABLgAFFAEJAQAIAAAAAA==.Razz:BAAALgAECgEJBAAAAA==.',
Rd='Rdata:BAAALgADCgkJEAAAAA==.',
Re='Relentlezz:BAAALgADCgMJAwABLgAECgkJLwAdAGUfAA==.Resoluteone:BAABLgAECn9MAAIaAAkJkhViEQD2AQAaAAkJkhViEQD2AQAAAA==.Retnu:BAAALgAECgEJAQAAAA==.Revytwohand:BAACLgAFFH8gAAMcAAcJWxopCwBvAQAcAAYJxx0pCwBvAQADAAUJjgzSNADYAAAuAAQKfzQAAhwACQmXJUoEABUDABwACQmXJUoEABUDAAAA.Reáper:BAAALgAECgEJAQAAAA==.',
Rh='Rhagul:BAAALgAFFAIJAgAAAA==.Rhok:BAAALgADCgEJAQAAAA==.Rhokhard:BAAALgADCgEJAwAAAA==.',
Ro='Rocketarena:BAAALgAECgcJDwAAAA==.Rootytooty:BAAALgAECgIJAgAAAA==.Rozelie:BAABLgAFFH8HAAIMAAMJ4hIxMQC9AAAMAAMJ4hIxMQC9AAABLgAFFAcJHwAeAH8aAA==.',
Ry='Ryzarapriest:BAAALgAECgMJBAABLgAFFAEJAQAIAAAAAA==.',
Sa='Sabeladys:BAABLgAECn8oAAIFAAkJRCHLFQDAAgAFAAkJRCHLFQDAAgAAAA==.Sadpeepo:BAAALgADCgIJAgAAAA==.Saifir:BAABLgAECn8pAAIhAAkJBRH1OADMAQAhAAkJBRH1OADMAQAAAA==.Sardmongo:BAAALgADCgcJCgAAAA==.Sardogobo:BAAALgAECgEJAQABLgAECggJIgAXAIEUAA==.Sarduccini:BAABLgAECn8iAAIXAAgJgRTaTADiAQAXAAgJgRTaTADiAQAAAA==.Sargeros:BAAALgAECgQJBAAAAA==.',
Sc='Schizo:BAAALgADCgEJAQAAAA==.',
Se='Sebastîan:BAAALgAECgEJAQABLgAECgkJIAAXABkZAA==.Sekhmet:BAAALgAECgcJCAAAAA==.Sekio:BAAALgAECgYJCwAAAA==.',
Sh='Shadowpriest:BAAALgADCgEJAQAAAA==.Shamburgyr:BAAALgAECgMJAwABLgAECgkJOQAGAK0UAA==.Shampáin:BAAALgAECgIJAgAAAA==.Shanàs:BAAALgAECgEJAQABLgAECgkJGwAFAEYeAA==.Sharayu:BAAALgAECgMJBwAAAA==.Shea:BAAALgADCgYJBgAAAA==.Sheamus:BAAALgADCgkJCQAAAA==.Shiftken:BAAALgAECgMJAwAAAA==.Shiftyfive:BAAALgAFFAMJAwAAAA==.Shivà:BAAALgADCgUJCAAAAA==.',
Si='Siara:BAAALgAECgEJAQAAAA==.Sigrodah:BAACLgAFFH8PAAMRAAUJ9g8rNQDuAAARAAQJ9g8rNQDuAAAQAAEJswG2LAA1AAAuAAQKfxkAAxEACAlTH9cRAF0CABEACAlTH9cRAF0CAA8ABAm2EW4pANQAAAAA.Silvalus:BAAALgAECgYJCwAAAA==.Silvertide:BAAALgAECgkJCQAAAA==.Sin:BAAALgAECgkJCQAAAA==.',
Sk='Skaara:BAAALgAECgQJBwAAAA==.Skara:BAAALgADCgEJAQAAAA==.Skiddles:BAAALgADCgIJAgAAAA==.Skinwalker:BAAALgADCgYJCgAAAA==.Skithyryx:BAAALgADCgIJAgAAAA==.Skonka:BAAALgAECgYJCQAAAA==.Skor:BAAALgADCgQJBAAAAA==.Skyblue:BAAALgAECgEJAQAAAA==.Skyeforce:BAAALgAECgQJCQAAAA==.',
Sl='Slipknoth:BAABLgAECn8UAAMKAAYJkRmEUwAsAQAKAAUJFheEUwAsAQAFAAYJoRIQuAAVAQAAAA==.',
Sm='Smellydeath:BAAALgAECgEJAQAAAA==.Smellyy:BAAALgADCgEJAQAAAA==.Smite:BAAALgAECgUJCAAAAA==.Smoketurtle:BAAALgAECgUJCAAAAA==.',
Sn='Sno:BAAALgAECgEJAQAAAA==.Snyper:BAAALgADCgYJBgAAAA==.',
So='Socatoas:BAABLgAECn8ZAAIBAAkJtglqNQBzAQABAAkJtglqNQBzAQAAAA==.Softbanana:BAAALgADCgEJAQAAAA==.Soi:BAAALgAECgYJCgABLgAECgkJGAAFAE0hAA==.Solarion:BAAALgAECgEJAQABLgAECgcJFAAgAEMPAA==.Sonoforak:BAAALgAECgYJCwAAAA==.Sontauren:BAAALgADCgEJAQAAAA==.',
Sp='Sped:BAACLgAFFH8FAAIdAAMJ9RfNDADVAAAdAAMJ9RfNDADVAAAuAAQKfzsABB0ACQlQIh0FAMoCAB0ACQlQIh0FAMoCACYABQmzCG8vAHoAAAEAAQn3A/euAC0AAAAA.',
St='Stalrun:BAAALgAECgYJCgABLgAECgYJEgAIAAAAAA==.Staraleena:BAAALgAECgUJBQAAAA==.Starrlynn:BAAALgAECgEJAQAAAA==.Stormeyes:BAAALgAECgMJAQABLgAECggJJAAjAOoaAA==.Stormslight:BAABLgAECn8kAAIjAAgJ6hrgDAD3AQAjAAgJ6hrgDAD3AQAAAA==.Stormsteel:BAAALgAECgQJBwAAAA==.Stôrmrägé:BAAALgAECgcJDQAAAA==.',
Sw='Swgchainz:BAAALgAECgcJEwABLgAECgkJLQASADEdAA==.Swiftdéath:BAAALgAECgYJCgAAAA==.Swtbabybilly:BAAALgAECgYJCQAAAA==.',
Sy='Sylvänäs:BAAALgAFFAEJAQAAAA==.',
['Sä']='Säberdh:BAAALgADCgYJBgABLgAECgMJAwAIAAAAAA==.',
['Så']='Såran:BAAALgAECgUJCwAAAA==.',
['Sí']='Sílence:BAACLgAFFH8GAAIMAAIJ2gJAJQBNAAAMAAIJ2gJAJQBNAAAuAAQKfxUAAgwACAmvCRRIAOwAAAwACAmvCRRIAOwAAAAA.',
['Sô']='Sôlrïx:BAAALgAECgUJCgAAAA==.',
Ta='Tabio:BAAALgADCgYJBgAAAA==.Tabios:BAAALgAECgEJAQAAAA==.Tabito:BAAALgAECgEJAQAAAA==.Taby:BAAALgADCgIJAgAAAA==.Talas:BAABLgAECn8wAAIjAAkJnRYtDgDhAQAjAAkJnRYtDgDhAQAAAA==.Taltaelen:BAAALgADCgYJBgABLgAECgkJHwACAA4WAA==.Tamarack:BAABLgAECn8XAAIGAAYJshuJUQB0AQAGAAYJshuJUQB0AQAAAA==.',
Te='Teetsie:BAAALgAFFAEJAQAAAA==.Tehmber:BAAALgAECgQJCAABLgAECgcJCQAIAAAAAA==.Tehmplar:BAAALgAECgcJCQAAAA==.Terrormisu:BAAALgAECgEJAQABLgAECggJGQAFAHEcAA==.',
Th='Thalorien:BAAALgADCgYJBgABLgAECgcJFwAKAIghAA==.Theboart:BAAALgAECgQJCQAAAA==.Tholindis:BAAALgAECgUJBQAAAA==.Thredron:BAABLgAFFH8HAAIKAAMJTAdfNwCQAAAKAAMJTAdfNwCQAAAAAA==.',
Ti='Tilted:BAAALgAECgkJCwABLgAECgkJLwAEAIUXAA==.Timebarred:BAAALgAECgEJBAAAAA==.',
To='Tooru:BAACLgAFFH8XAAQGAAYJqhJWOwA2AQAGAAUJMhZWOwA2AQAJAAEJsg5ZMQBNAAAlAAEJXwJAHwA8AAAuAAQKfzYABAYACQm+IYsGACUDAAYACQm+IYsGACUDAAkACAncEOMcALUBACUABgkWGT1LACUBAAAA.Tortiana:BAAALgAECgUJBQAAAA==.Tossko:BAAALgAECgIJAwABLgAECgQJDAAIAAAAAA==.',
Tr='Traefel:BAAALgAECgMJAwAAAA==.Traeflor:BAAALgAECgEJAQAAAA==.Traevok:BAAALgAECgEJAgAAAA==.Trailertrash:BAABLgAECn9EAAIVAAgJnB9NNwA7AgAVAAgJnB9NNwA7AgAAAA==.Treebeef:BAACLgAFFH8dAAIkAAYJpAgrKwALAQAkAAYJpAgrKwALAQAuAAQKfzIAAyQACQkCG+0YAHACACQACQkCG+0YAHACAAwAAQnWA/GMACIAAAAA.Triena:BAAALgAECgQJBgAAAA==.Trirn:BAAALgADCgYJBgAAAA==.Trishool:BAAALgAECgEJAQAAAA==.Trumpeter:BAAALgAECgQJCwAAAA==.Trywind:BAAALgAECgYJBgAAAA==.',
Ts='Tsukuyómi:BAAALgAECgEJAQAAAA==.',
Ty='Tydrielion:BAAALgAECgYJDgAAAA==.Typicaldrood:BAAALgAECgIJAgAAAA==.',
['Tí']='Tízzíts:BAAALgADCgYJBgAAAA==.',
Ul='Ullreich:BAABLgAECn8YAAIGAAcJVwsnjgAjAQAGAAcJVwsnjgAjAQAAAA==.Ulysius:BAACLgAFFH8OAAIFAAQJRhbdKgDaAAAFAAQJRhbdKgDaAAAuAAQKfysAAgUACQmWGVs0AC8CAAUACQmWGVs0AC8CAAAA.',
Un='Unfazed:BAAALgAECgEJAQAAAA==.Unicornslayr:BAABLgAECn8qAAIKAAkJTRYTKQDEAQAKAAkJTRYTKQDEAQAAAA==.',
Ur='Urund:BAAALgAECgYJDgAAAA==.Uruquizas:BAAALgAECgUJBQAAAA==.',
Uw='Uwantsmoke:BAABLgAECn8eAAIGAAYJMwRsuwDPAAAGAAYJMwRsuwDPAAAAAA==.Uwantsmokee:BAAALgADCgMJAwAAAA==.',
Va='Valgroth:BAAALgAECgIJAwAAAA==.Valkisek:BAACLgAFFH8SAAIVAAQJxhDaXwAhAQAVAAQJxhDaXwAhAQAuAAQKfxoAAhUACAlzGgqbAJ8BABUACAlzGgqbAJ8BAAAA.Valkonigen:BAAALgAECgEJAQAAAA==.Vallarfax:BAABLgAECn8rAAIGAAkJIx/WGACRAgAGAAkJIx/WGACRAgAAAA==.Vandaam:BAAALgAECgEJAQAAAA==.Vandro:BAACLgAFFH8GAAIKAAMJWgxVGACMAAAKAAMJWgxVGACMAAAuAAQKfzAABAoACQkPGsECAAsCAAoACQkPGsECAAsCAAUABAnjFv4WAAcBACMABgnaCuUsALgAAAAA.Vantive:BAAALgAECgYJDwAAAA==.Vash:BAAALgAECgEJAQAAAA==.Vashdk:BAACLgAFFH8TAAIaAAYJvRmsFQA/AQAaAAYJvRmsFQA/AQAuAAQKfxUAAhoACAnEFn8QAAMCABoACAnEFn8QAAMCAAAA.Vashmonk:BAACLgAFFH8MAAITAAQJzyO4FAB9AQATAAQJzyO4FAB9AQAuAAQKfxUAAhMACQmcIUQMAHECABMACQmcIUQMAHECAAAA.Vashwar:BAAALgAECgYJBgAAAA==.',
Ve='Vedruid:BAAALgAECggJDwAAAA==.Velaric:BAABLgAECn8vAAMkAAkJyhvFFACkAgAkAAkJyhvFFACkAgALAAEJ3gv1gQAfAAAAAA==.Velcyn:BAAALgADCgcJDgABLgAECgIJAgAIAAAAAA==.Veldoria:BAAALgAECgQJBgAAAA==.Veloe:BAAALgAECgIJAgAAAA==.Veloranas:BAABLgAECn8eAAIVAAkJmRGzCADEAQAVAAkJmRGzCADEAQAAAA==.Verath:BAAALgADCgEJAQAAAA==.Vespyr:BAABLgAECn85AAIGAAkJrRRKCADeAQAGAAkJrRRKCADeAQAAAA==.Vespyrlynd:BAAALgAECgYJCgABLgAECgkJOQAGAK0UAA==.Vewdoo:BAACLgAFFH8HAAIiAAMJMR2RFQDgAAAiAAMJMR2RFQDgAAAuAAQKf0YAAiIACQnOJLkCAEkDACIACQnOJLkCAEkDAAAA.',
Vi='Viejoverde:BAAALgAECgQJCAAAAA==.Vipul:BAAALgAECgYJDgABLgAFFAEJAgAIAAAAAA==.Vizimir:BAAALgAECgkJEwAAAA==.',
Vo='Voldune:BAAALgAECgIJAwAAAA==.',
['Vë']='Vëgetå:BAAALgADCgYJBwABLgAECgUJBQAIAAAAAA==.',
Wa='Waiwai:BAAALgAECgEJAgAAAA==.Warfarin:BAAALgAECgEJBAAAAA==.Wascii:BAACLgAFFH8IAAIGAAQJSxAHIQAbAQAGAAQJSxAHIQAbAQAuAAQKfyEAAgYACQkYFX42AAMCAAYACQkYFX42AAMCAAEuAAUUBQkMAAIAtBkA.Waxedthataxe:BAAALgAECgEJAQAAAA==.Waxesaxes:BAAALgAECgQJBwAAAA==.',
We='Weaken:BAAALgAECgUJCwAAAA==.Weskr:BAAALgADCgEJAQABLgAFFAEJAQAIAAAAAA==.',
Wi='Wickedsinner:BAAALgADCgEJAQAAAA==.Wizkerbizkit:BAAALgAECgMJBQAAAA==.',
Wo='Wolvesbane:BAABLgAFFH8FAAIGAAUJbwAYqwBCAAAGAAUJbwAYqwBCAAAAAA==.',
Wy='Wyrmblood:BAABLgAECn8VAAMjAAcJpCQcAQBvAgAjAAcJByQcAQBvAgAFAAcJbiJmLABQAgABLgAECgkJOAAWAPsjAA==.Wyrmfur:BAABLgAECn8lAAMLAAgJCCJYAQBmAgALAAgJCCJYAQBmAgAZAAQJUh6hHwALAQABLgAECgkJOAAWAPsjAA==.Wyrmheal:BAABLgAECn84AAIWAAkJ+yNLAQCnAgAWAAkJ+yNLAQCnAgAAAA==.Wyvvie:BAAALgADCgIJAgAAAA==.',
Xa='Xavil:BAAALgAECgEJAQAAAA==.Xavv:BAAALgADCgUJBQAAAA==.',
Xi='Xiba:BAAALgAECgQJBwAAAA==.',
Xl='Xle:BAAALgADCgIJAgAAAA==.',
Ya='Yakoff:BAAALgAECgUJBQAAAA==.Yamihime:BAABLgAECn82AAMSAAkJURYtGQC4AQASAAgJ5xctGQC4AQAHAAkJvwvBXAByAQAAAA==.Yatiri:BAABLgAECn8qAAMiAAkJ1R28AQCnAgAiAAkJ1R28AQCnAgAhAAEJQQ6X3gAqAAAAAA==.',
Yo='Yoowuzsup:BAABLgAECn8aAAIiAAcJnBxJMAB+AQAiAAcJnBxJMAB+AQAAAA==.',
Yu='Yureimage:BAABLgAECn8WAAIVAAYJMAtf1wDnAAAVAAYJMAtf1wDnAAAAAA==.',
Za='Zarthus:BAAALgAECggJAgAAAA==.',
Ze='Zeaket:BAACLgAFFH8uAAIJAAkJ4B2dAACGAgAJAAkJ4B2dAACGAgAuAAQKfy8AAgkACQmSIhkBAGEDAAkACQmSIhkBAGEDAAAA.Zedsdeadd:BAAALgAECgYJDwAAAA==.Zephyr:BAABLgAECn8qAAIeAAgJBghADwDEAAAeAAgJBghADwDEAAABLgAECgkJOQAGAK0UAA==.Zerrayna:BAAALgAECgUJCAAAAA==.Zeçhs:BAABLgAECn8YAAIFAAkJTSFZFADxAgAFAAkJTSFZFADxAgAAAA==.',
Zi='Zinek:BAAALgAECgQJBQAAAA==.Zinra:BAAALgAECgUJEAAAAA==.',
Zo='Zoma:BAAALgADCgUJBgAAAA==.Zorcan:BAABLgAECn8oAAIOAAkJZxoLBQBBAgAOAAkJZxoLBQBBAgAAAA==.',
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
