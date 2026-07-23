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

local lookup = {'Warrior-Fury','DeathKnight-Unholy','Monk-Mistweaver','Priest-Holy','Paladin-Retribution','Hunter-BeastMastery','DemonHunter-Devourer','Unknown-Unknown','Hunter-Survival','Paladin-Holy','Druid-Balance','DeathKnight-Frost','Warlock-Affliction','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Havoc','Monk-Brewmaster','Shaman-Enhancement','Mage-Frost','Priest-Shadow','Warlock-Demonology','Warlock-Destruction','Druid-Feral','DeathKnight-Blood','Rogue-Assassination','Druid-Guardian','Monk-Windwalker','Warrior-Protection','Priest-Discipline','DemonHunter-Vengeance','Rogue-Subtlety','Shaman-Restoration','Shaman-Elemental','Paladin-Protection','Druid-Restoration','Hunter-Marksmanship','Warrior-Arms','Rogue-Outlaw','Mage-Arcane',}
local provider = {region='US',realm='Madoran',name='US',type='weekly',zone=46,date='2026-07-19',data={Aa='Aarhus:BAAALgAECgUJCQAAAA==.Aaronmourne:BAAALgAECgQJBAABLgAECgkJGQABALYJAA==.Aaronyates:BAAALgADCgcJBwABLgAFFAUJDAACALQZAA==.',
Ac='Actualegirl:BAABLgAFFH8GAAIDAAUJLQRLNwDLAAADAAUJLQRLNwDLAAABLgAFFAUJDQAEAAUXAA==.',
Ad='Adrenalin:BAAALgADCgEJAQAAAA==.Adversary:BAAALgAECgMJAwAAAA==.',
Ae='Aerfen:BAABLgAECn8cAAIFAAkJyg2QaQCcAQAFAAkJyg2QaQCcAQAAAA==.',
Ag='Agross:BAAALgADCgYJBgAAAA==.',
Ai='Aimforhead:BAAALgAECgcJDAAAAA==.Aiyanna:BAAALgADCggJDAABLgAECgYJGAAGAKULAA==.',
Ak='Akiraha:BAAALgAECgMJCwAAAA==.',
Al='Alexas:BAAALgADCgcJCAAAAA==.Alric:BAABLgAECn80AAIHAAkJYxQeNQDyAQAHAAkJYxQeNQDyAQAAAA==.Alyndra:BAAALgADCgUJBQABLgAECgUJBQAIAAAAAA==.',
Am='Amideus:BAAALgAECgEJAQAAAA==.Amory:BAABLgAECn8mAAICAAkJ9x40IQCDAgACAAkJ9x40IQCDAgAAAA==.',
An='Angela:BAAALgADCgIJAgAAAA==.Annaesthetic:BAAALgAECgEJAwABLgAECgkJOQAJAAgVAA==.',
Ar='Arator:BAAALgADCgEJAgAAAA==.Araña:BAAALgAECgEJAQAAAA==.Arcatraz:BAAALgAECgEJAQAAAA==.Ardaddy:BAAALgAECgYJDQABLgAFFAMJBAAIAAAAAA==.Ardzak:BAAALgAFFAMJBAAAAA==.Arragorn:BAACLgAFFH8IAAIKAAQJFRl9HwAhAQAKAAQJFRl9HwAhAQAuAAQKfycAAgoACQktHLgZADkCAAoACQktHLgZADkCAAAA.Arthora:BAAALgAECgYJBgAAAA==.Arverick:BAAALgAECgYJBgAAAA==.',
As='Asendra:BAABLgAECn8mAAILAAkJ6xnFEQBLAgALAAkJ6xnFEQBLAgAAAA==.Assaran:BAAALgAECgIJAgAAAA==.Astal:BAACLgAFFH8LAAIMAAUJlA/8DwAYAQAMAAUJlA/8DwAYAQAuAAQKfx0AAgwACQmfGwkHACwCAAwACQmfGwkHACwCAAAA.',
At='Ate:BAAALgADCgYJBgABLgAECgkJKgAKAE0WAA==.Athenea:BAABLgAECn8aAAIBAAcJUBuYHwDyAQABAAcJUBuYHwDyAQAAAA==.Athénna:BAAALgADCgIJAgABLgAECggJNQAGAEQUAA==.Atulru:BAAALgADCgMJAwAAAA==.',
Av='Avyl:BAAALgADCgcJBwABLgAECgYJGwANAPsRAA==.',
Ay='Ayannar:BAAALgADCgEJAQAAAA==.',
Az='Azriella:BAAALgAECgkJDQAAAA==.Azuren:BAABLgAECn9EAAQOAAkJwBg4AQB3AQAOAAcJzhQ4AQB3AQAPAAkJVQvfAgAwAQAQAAEJ8wejGwAbAAAAAA==.',
Ba='Baal:BAAALgAFFAIJAgAAAA==.Bacon:BAABLgAECn9CAAMRAAkJCyRPBQDtAgARAAkJCyRPBQDtAgAHAAcJKRvcSACsAQAAAA==.Bamboozled:BAABLgAECn8VAAMDAAgJbxNTLQDJAQADAAgJbxNTLQDJAQASAAUJ7AORCACJAAABLgAECgkJJgAGAL4XAA==.Bandìt:BAAALgAECggJCwAAAA==.Bankai:BAABLgAFFH8GAAITAAEJUCVMEABLAAATAAEJUCVMEABLAAAAAA==.Barbieque:BAAALgADCgcJBwAAAA==.',
Be='Bearyden:BAAALgADCgEJAQAAAA==.Bedbugs:BAAALgAECgQJBAABLgAFFAUJIQAUAI0eAA==.Beefstrasz:BAABLgAECn8aAAMEAAgJuRdiFAAzAgAEAAgJuRdiFAAzAgAVAAEJpwbTkgAoAAAAAA==.Beyla:BAACLgAFFH8IAAIFAAMJQQobegDBAAAFAAMJQQobegDBAAAuAAQKfycAAgUACQkFF4A1ACsCAAUACQkFF4A1ACsCAAAA.',
Bi='Bioactive:BAAALgADCgYJBgAAAA==.Bishamon:BAABLgAECn9OAAQWAAkJ+yHwBQBeAwAWAAkJ+yHwBQBeAwAXAAEJAADAaQA+AAANAAEJAADlMQA6AAAAAA==.Bizotch:BAAALgAECggJDgAAAA==.',
Bl='Bleau:BAABLgAECn8iAAIYAAkJbxCpEACtAQAYAAkJbxCpEACtAQAAAA==.Blethings:BAAALgAECgMJAwAAAA==.Blinktwice:BAAALgAECgEJAgAAAA==.Bloodimess:BAAALgADCgMJAwAAAA==.Bloodrayna:BAAALgAECgYJBAAAAA==.Bloodymary:BAABLgAECn8nAAIZAAkJOhXwEwDUAQAZAAkJOhXwEwDUAQAAAA==.Bluebarrie:BAAALgAECgEJAQAAAA==.Bluwolferine:BAAALgAECgkJCQAAAA==.Blôodräge:BAAALgAECgcJDgAAAA==.',
Bo='Bootelicious:BAAALgADCgIJAgAAAA==.Bouncybean:BAAALgADCgIJAgAAAA==.',
Br='Bradsupinya:BAABLgAECn8kAAIUAAgJEBl7XgDEAQAUAAgJEBl7XgDEAQAAAA==.Branchling:BAAALgAECgcJEgABLgAFFAUJIQAUAI0eAA==.Brewswane:BAAALgAFFAEJAwABLgAFFAkJKwAaAFsUAA==.Bridh:BAABLgAECn8aAAIHAAkJFR5LEQD0AgAHAAkJFR5LEQD0AgABLgAFFAgJHwAXABIcAA==.Bromm:BAAALgAECgEJAQAAAA==.Brunor:BAAALgAECgkJDAAAAA==.',
Bu='Bulkamania:BAAALgAECgMJAwAAAA==.Butterkip:BAACLgAFFH8PAAIVAAUJfBSxFgAvAQAVAAUJfBSxFgAvAQAuAAQKfysAAhUACQlpHikKAOACABUACQlpHikKAOACAAAA.',
['Bë']='Bëarclaw:BAAALgAECgUJBQAAAA==.',
Ca='Cambria:BAAALgAECgMJAwAAAA==.Cantkillme:BAAALgAECgQJBwAAAA==.Canukillme:BAAALgADCgYJBgAAAA==.Carloos:BAAALgAFFAEJAQAAAA==.Carruel:BAAALgADCgUJBQAAAA==.Cazzc:BAAALgAECgUJCAAAAA==.',
Ce='Cellan:BAABLgAECn8XAAICAAcJ6wqKvQABAQACAAcJ6wqKvQABAQAAAA==.Censora:BAAALgAECgEJAQAAAA==.',
Ch='Chicharrones:BAAALgAECgUJBQABLgAECgkJQgARAAskAA==.Chickenshift:BAABLgAECn8tAAMbAAkJnB/wDAATAgAbAAgJpR7wDAATAgAYAAQJoBvIHAAkAQAAAA==.Chipahoy:BAABLgAECn8nAAIFAAgJdRw/OAAhAgAFAAgJdRw/OAAhAgABLgAECggJRAAUAJwfAA==.Chlorofõrm:BAAALgAECgIJAwABLgAECgkJOQAJAAgVAA==.Chopahoe:BAAALgAECgQJBwAAAA==.Chuggz:BAABLgAECn8gAAIcAAkJ5xE1HwCzAQAcAAkJ5xE1HwCzAQAAAA==.',
Ci='Cindywoohoo:BAAALgAECgMJAwAAAA==.',
Cl='Clamadin:BAAALgAECgIJAgABLgAFFAgJJQAUAKccAA==.Clamius:BAACLgAFFH8lAAIUAAgJpxwjDACOAgAUAAgJpxwjDACOAgAuAAQKfyoAAhQACQkkJRALACEDABQACQkkJRALACEDAAAA.Cliff:BAAALgAECgUJBgAAAA==.',
Co='Colby:BAAALgAECgYJDgAAAA==.Coldass:BAABLgAECn8ZAAIUAAgJwRJjZgCxAQAUAAgJwRJjZgCxAQAAAA==.Coldstone:BAAALgAECgYJCAAAAA==.Commodus:BAAALgADCgQJBAAAAA==.Conduit:BAAALgAECgUJBwAAAA==.Coombrain:BAAALgAECgUJCQAAAA==.Cotopla:BAAALgAECgQJDAAAAA==.',
Cr='Critterzz:BAABLgAECn8aAAIEAAgJ4hb6FwAcAgAEAAgJ4hb6FwAcAgAAAA==.Cryptkeys:BAAALgAECgMJAwAAAA==.',
Cu='Cuziseeu:BAAALgAECgQJBAABLgAECgYJBgAIAAAAAA==.',
Da='Dachyy:BAAALgAECgcJEwAAAA==.Daemonwaters:BAAALgAECgEJAQAAAA==.Dagov:BAAALgAECgYJCAAAAA==.Daiana:BAAALgAECgIJAgAAAA==.Damage:BAAALgAFFAEJAQAAAA==.Damocles:BAAALgAECgEJAQABLgAECggJJAAEAKscAA==.Darkråii:BAAALgAECgIJAwAAAA==.Dashboy:BAAALgADCgEJAQAAAA==.',
De='Deafniteelf:BAAALgAECgkJDQAAAA==.Deathlentlez:BAABLgAECn8vAAIdAAkJZR86BwCSAgAdAAkJZR86BwCSAgAAAA==.Decaylentlez:BAAALgAECgEJAQABLgAECgkJLwAdAGUfAA==.Deepwinter:BAAALgAECgcJDQABLgAFFAUJDAACALQZAA==.Delphyne:BAABLgAECn8UAAIOAAYJ9wvxEQDrAAAOAAYJ9wvxEQDrAAAAAA==.Delylee:BAAALgAECgIJAgAAAA==.Demandred:BAAALgAECgcJDAAAAA==.Demonhunter:BAABLgAECn8gAAIRAAkJuhiWDgA8AgARAAkJuhiWDgA8AgAAAA==.Demonià:BAABLgAECn8jAAIUAAkJ7Ao1FAANAQAUAAkJ7Ao1FAANAQAAAA==.Descimus:BAABLgAECn8kAAQEAAgJqxzFDQB+AgAEAAgJ2BvFDQB+AgAeAAUJDBd+LwAkAQAVAAMJpRcEYACYAAAAAA==.Desong:BAAALgADCgYJBwAAAA==.Detharbinger:BAAALgAECgcJDQAAAA==.Dethgripz:BAABLgAFFH8KAAICAAQJPQ1MKwAWAQACAAQJPQ1MKwAWAQAAAA==.Dezzan:BAAALgADCgQJBwAAAA==.',
Di='Diamathius:BAAALgAECgQJBAAAAA==.Diamondsword:BAAALgAECggJDgAAAA==.Dieanah:BAAALgADCgcJBwAAAA==.',
Dj='Djazz:BAAALgAECgcJCQAAAA==.',
Do='Dochaze:BAABLgAECn8qAAMKAAkJfxyHHwAdAgAKAAgJPB+HHwAdAgAFAAMJjA1KIAGTAAAAAA==.Dogdimmadome:BAAALgAECgYJDwAAAA==.Dolore:BAAALgADCgcJBgAAAA==.Donut:BAAALgADCgIJAgABLgAECgkJLQAFAFEaAA==.Doublejump:BAAALgAECgEJAQABLgAECgkJJwAZADoVAA==.',
Dr='Dragone:BAAALgAECgUJCQAAAA==.Dragun:BAAALgADCgUJBQABLgAECgkJLQAFAFEaAA==.Drowsee:BAAALgAECgUJBgAAAA==.Dráconus:BAAALgADCgMJAwAAAA==.',
Du='Dumbdumb:BAAALgAECgQJBgAAAA==.',
Dy='Dyanuh:BAABLgAECn8eAAIVAAYJygIeagB2AAAVAAYJygIeagB2AAAAAA==.',
['Dà']='Dàrkscythe:BAABLgAECn8cAAMZAAcJmAVLPACgAAAZAAcJuQRLPACgAAAMAAEJiQZqPwAoAAAAAA==.',
Ea='Eazywin:BAAALgAECggJCQAAAA==.',
Eh='Ehlsa:BAAALgADCgcJBwAAAA==.Ehlsi:BAABLgAECn8xAAMfAAkJUR/PAgDFAgAfAAkJUR/PAgDFAgARAAIJ1BslFABWAAAAAA==.Ehress:BAAALgAECgcJEwABLgAFFAUJDAACALQZAA==.',
Ei='Eirinny:BAABLgAECn8tAAITAAkJWQq6EwB9AQATAAkJWQq6EwB9AQAAAA==.',
El='Elindez:BAABLgAECn8nAAIgAAkJUw+YGADVAQAgAAkJUw+YGADVAQAAAA==.Elyviel:BAAALgAFFAEJAQAAAA==.Elàine:BAABLgAECn83AAIGAAgJLQvVGwDWAAAGAAgJLQvVGwDWAAAAAA==.',
Em='Emika:BAAALgADCgUJDgAAAA==.Emyrson:BAAALgAECgQJCQAAAA==.',
En='Encantado:BAAALgAECgUJBQAAAA==.Enemywithin:BAAALgADCgIJAgAAAA==.Enzo:BAAALgADCgYJCwAAAA==.',
Ep='Epicfury:BAAALgAECgYJDgAAAA==.',
Eq='Eq:BAAALgADCgUJBgAAAA==.',
Ez='Ezmee:BAABLgAECn8ZAAIUAAYJkQ3wFgD1AAAUAAYJkQ3wFgD1AAAAAA==.',
Fa='Facingworlds:BAAALgAECggJDgAAAA==.Fathercaleb:BAAALgAECgIJAwABLgAFFAcJIAAcAFsaAA==.Fazed:BAAALgAECgIJBgAAAA==.Fazeo:BAAALgAECgQJBQAAAA==.',
Fe='Featherstep:BAAALgADCgMJAwAAAA==.Felysse:BAAALgADCgEJAQAAAA==.',
Fi='Fireball:BAAALgAECgIJAgABLgAFFAEJAQAIAAAAAA==.',
Fl='Flavio:BAAALgAECgQJCAAAAA==.',
Fo='Fortuna:BAABLgAECn8kAAITAAkJxASQGQA4AQATAAkJxASQGQA4AQAAAA==.',
Fr='Francesca:BAAALgADCgEJAQAAAA==.Frosilen:BAABLgAECn87AAMhAAkJCxDoQQCmAQAhAAkJCxDoQQCmAQAiAAMJaQtgewB9AAAAAA==.Frostbite:BAAALgADCgIJAgAAAA==.',
Ga='Gamaikuba:BAAALgADCggJCQAAAA==.Gamarth:BAAALgAECgYJDQAAAA==.Gatlu:BAABLgAECn8hAAIbAAkJcBYzDQAOAgAbAAkJcBYzDQAOAgAAAA==.Gawdsmackk:BAAALgAECggJDgAAAA==.Gaz:BAAALgADCgMJAwAAAA==.Gazokks:BAAALgADCgcJBwAAAA==.',
Ge='Gedank:BAAALgADCgcJBwAAAA==.Geodemon:BAAALgAECgQJBAAAAA==.Gethealed:BAAALgAECgcJEAAAAA==.Getrektpos:BAAALgADCgMJAwAAAA==.',
Gh='Ghostlock:BAABLgAECn8VAAINAAgJzxn2BQAFAgANAAgJzxn2BQAFAgAAAA==.Ghoztface:BAABLgAECn8oAAMjAAcJcxzHDgDYAQAjAAYJXCDHDgDYAQAFAAcJJxLmmgA/AQAAAA==.Ghöstbeef:BAAALgADCgkJEAABLgAECggJGgAEALkXAA==.',
Gi='Giblock:BAABLgAECn8XAAINAAgJCBRNDwBoAQANAAgJCBRNDwBoAQAAAA==.',
Gl='Glamorus:BAAALgAECgUJBQAAAA==.Glamour:BAAALgAECgQJEQAAAA==.Glitterboy:BAAALgAECgIJAgABLgAFFAgJIwAcACIfAA==.',
Go='Golomojek:BAABLgAECn8aAAIiAAkJVA2jCQD1AAAiAAkJVA2jCQD1AAAAAA==.Gorkun:BAAALgADCgkJDgAAAA==.Gov:BAACLgAFFH8YAAMRAAcJMBvgEAAcAQAHAAcJ4Bl3PAA0AQARAAUJfhXgEAAcAQAuAAQKfygAAwcACQm/JYsIAEUDAAcACQm/JYsIAEUDABEAAQlSEjpsADkAAAAA.Govndrag:BAAALgADCgEJAQAAAA==.Govs:BAACLgAFFH8GAAQEAAMJohhuIwCgAAAEAAIJBiJuIwCgAAAVAAIJcha/LACYAAAeAAIJdghtQAB4AAAuAAQKfxUAAwQACAmVHqAPAG4CAAQACAmVHqAPAG4CABUAAwmVHhFYALQAAAAA.',
Gr='Gralmerte:BAACLgAFFH8OAAMYAAQJ9CEpAgBUAQAYAAQJ9CEpAgBUAQAkAAIJdB7zFQCwAAAuAAQKfzYAAxgACQnNIu4BABYDABgACQnNIu4BABYDACQAAQn3FIfGADwAAAAA.Grawfern:BAAALgAFFAEJAQAAAA==.Graygoyle:BAABLgAECn8hAAIaAAkJSgb7DABbAQAaAAkJSgb7DABbAQAAAA==.Groggaris:BAAALgAECgMJAwAAAA==.Groosalugg:BAABLgAECn8dAAIGAAkJtx2KKwAvAgAGAAkJtx2KKwAvAgAAAA==.',
Gu='Guillotine:BAAALgAECgEJAQAAAA==.Guldave:BAAALgAECgQJBAAAAA==.Guthrie:BAABLgAECn8WAAIKAAcJ2BczKgC9AQAKAAcJ2BczKgC9AQAAAA==.',
Gw='Gwyndolïn:BAABLgAECn8eAAMDAAcJ6RiIMAC4AQADAAcJ6RiIMAC4AQAcAAQJnAR6bQB3AAAAAA==.',
Ha='Hachendis:BAAALgADCgMJAwAAAA==.Haether:BAABLgAECn8uAAIhAAkJdBHnLQD/AQAhAAkJdBHnLQD/AQAAAA==.Haliax:BAAALgAECgEJAQABLgAECgkJGAAFAE0hAA==.Hammatime:BAAALgADCgcJBwAAAA==.Hatsu:BAABLgAECn8VAAIDAAkJSgxFPAB/AQADAAkJSgxFPAB/AQAAAA==.Hawktuahh:BAAALgAECgIJAgAAAA==.',
He='Hellá:BAAALgADCgIJAgAAAA==.Hemandunter:BAAALgAECgEJAQAAAA==.',
Hi='Hildunn:BAAALgAECgQJBgAAAA==.Hingedh:BAABLgAFFH8FAAIHAAMJ9g6uJwCjAAAHAAMJ9g6uJwCjAAABLgAFFAcJJAAgAMccAA==.Hitemup:BAAALgADCgQJBAAAAA==.',
Hk='Hktanker:BAAALgADCgQJBAABLgAECgYJGAAGAKULAA==.',
Ho='Holylentlezz:BAAALgADCgcJBwABLgAECgkJLwAdAGUfAA==.Holymun:BAABLgAECn8tAAIFAAkJURrbAwBlAgAFAAkJURrbAwBlAgAAAA==.Holyox:BAABLgAECn84AAIFAAkJngxbdgCBAQAFAAkJngxbdgCBAQAAAA==.Hotcheeto:BAAALgAECgkJEwAAAA==.',
Ht='Hturtle:BAAALgADCgEJAQAAAA==.Hturtledk:BAABLgAECn8VAAMCAAYJvxaKnwAtAQACAAYJvxaKnwAtAQAZAAEJ3QJYawAUAAAAAA==.',
Hu='Hug:BAAALgAECgUJCAAAAA==.',
['Hü']='Hüntress:BAAALgAFFAEJAgAAAA==.',
Ia='Iacey:BAAALgAECgIJAgAAAA==.',
Im='Imdatroll:BAACLgAFFH8IAAMkAAMJSBNyNwDPAAAkAAMJSBNyNwDPAAAYAAIJrxOuFQCDAAAuAAQKfzIABBgACQneIzYCADEDABgACQneIzYCADEDACQABgkUGRZZAC0BAAsAAgndC9ZyAGEAAAAA.Imgibby:BAAALgADCgYJBgABLgAECggJFwANAAgUAA==.Impius:BAAALgAECgkJCgAAAA==.Impmageddon:BAABLgAECn8aAAMWAAkJnRF6ZQBzAQAWAAkJnRF6ZQBzAQAXAAEJAAASdQAwAAAAAA==.',
In='Inexorable:BAABLgAFFH8IAAIFAAMJjxR7HwCwAAAFAAMJjxR7HwCwAAAAAA==.',
Ir='Irakwa:BAABLgAECn8UAAIGAAUJeQkIwgDDAAAGAAUJeQkIwgDDAAAAAA==.',
It='Itches:BAACLgAFFH8jAAIcAAgJIh8sAQChAgAcAAgJIh8sAQChAgAuAAQKfyAAAhwACAkHJOYDAE8DABwACAkHJOYDAE8DAAAA.',
Iw='Iwamori:BAAALgAECgEJAQAAAA==.',
Iz='Izánámi:BAABLgAECn85AAQJAAgJCBUOAwBoAQAJAAgJCBUOAwBoAQAGAAEJ8A19ywA6AAAlAAEJlwGPmAAeAAAAAA==.',
Ja='Jaason:BAAALgAECgYJBgABLgAFFAMJBQAQAHYRAA==.Jagon:BAACLgAFFH8FAAIQAAMJdhHaHAC2AAAQAAMJdhHaHAC2AAAuAAQKfy8ABBAACQkKGvARAFMCABAACQkKGvARAFMCAA8AAgm1B2A1AFAAAA4AAgkfDMIlADQAAAAA.Jalen:BAAALgAECgYJBgAAAA==.Janvi:BAAALgAECgEJAgAAAA==.Jarbito:BAAALgAECgUJCwAAAA==.Jarico:BAAALgAECgYJDQABLgAECgYJEgAIAAAAAA==.Jasint:BAAALgAECgUJBQABLgAFFAMJBQAQAHYRAA==.',
Je='Jebrogue:BAAALgADCgkJDgAAAA==.',
Jh='Jhunts:BAAALgAECggJEAAAAA==.',
Ji='Jinbloom:BAAALgADCgIJAgAAAA==.Jincrush:BAAALgAECgIJAgAAAA==.Jindabutt:BAABLgAECn8mAAISAAkJYyAXBgDbAgASAAkJYyAXBgDbAgAAAA==.Jinfuse:BAAALgADCgUJBQAAAA==.Jinkybell:BAAALgAECgUJBQAAAA==.Jintonic:BAAALgAECgcJCAAAAA==.',
Jk='Jkbalo:BAABLgAFFH8FAAMmAAIJHwXoHwA6AAABAAIJ8gBKVgA+AAAmAAIJHwXoHwA6AAAAAA==.Jkrlos:BAAALgAFFAMJBAAAAA==.',
Jo='Jocommande:BAAALgAECgEJAQAAAA==.Jointheraid:BAAALgADCgMJAwAAAA==.Jokerstree:BAAALgADCgYJBgAAAA==.Jorah:BAAALgADCgcJCgAAAA==.Jorkah:BAAALgADCgcJCgAAAA==.',
Jp='Jpdh:BAACLgAFFH8UAAMfAAQJZSO6BAAnAQAHAAQJLSMsLwBpAQAfAAMJ2yK6BAAnAQAuAAQKfyoABB8ACQl3JKQEAHACAAcACQmfIGwYAMMCAB8ACAk8JaQEAHACABEABQmbFo9EAOQAAAAA.Jphunt:BAAALgADCgUJBQABLgAFFAQJFAAfAGUjAA==.',
Ju='Juddory:BAABLgAECn8kAAIUAAgJjw2EqQAsAQAUAAgJjw2EqQAsAQAAAA==.Junksvil:BAAALgAECgYJEgAAAA==.',
['Jø']='Jøhnwick:BAAALgADCgYJBgAAAA==.',
Ka='Kahrahkon:BAAALgAECgQJDgAAAA==.Kalinis:BAAALgAECgIJAwAAAA==.Kanadoria:BAAALgAECgQJBgAAAA==.Kanion:BAAALgAECgYJCgAAAA==.Kargorr:BAAALgAECgMJAwAAAA==.',
Ke='Kenth:BAAALgAECgEJAQAAAA==.Keranøs:BAAALgAECgEJAQAAAA==.',
Kh='Khudoz:BAAALgAECgMJBwAAAA==.',
Ki='Killerelf:BAAALgADCggJCAAAAA==.Killshotz:BAAALgADCgUJBQAAAA==.Kismët:BAAALgAECgEJAQAAAA==.',
Kl='Klid:BAAALgADCgMJAwABLgAFFAIJBQAFAIIUAA==.',
Ko='Koa:BAAALgAECgEJAQAAAA==.Kooch:BAAALgADCgYJBgAAAA==.Korinth:BAECLgAFFH8fAAMjAAcJURM9CQDiAAAjAAYJZhY9CQDiAAAFAAEJ6AMAAAAAAAAuAAQKfz0AAiMACQnnG10HAGkCACMACQnnG10HAGkCAAAA.Kovala:BAAALgAECgEJAQAAAA==.',
Kr='Kriaalis:BAACLgAFFH8MAAMhAAMJFgTBMQBwAAAhAAMJFgTBMQBwAAAiAAIJ+ACcOQAfAAAuAAQKfxUAAyEACQlIBct6AO8AACEACAn6BMt6AO8AACIAAQmqBVvDABkAAAAA.Krul:BAAALgADCgQJBwAAAA==.',
Ku='Kurzon:BAAALgADCgMJAwABLgAECgkJHQAGALcdAA==.',
Ky='Kyra:BAAALgAECgUJDwAAAA==.',
['Kæ']='Kælas:BAAALgAECgEJAgAAAA==.',
La='Lachryma:BAAALgADCgUJBQAAAA==.Laríssa:BAEBLgAFFH8JAAIVAAUJrg0tEADPAAAVAAUJrg0tEADPAAAAAA==.Layala:BAAALgAECgEJAQAAAA==.Lazuli:BAAALgAECgYJBgABLgAECgkJQgARAAskAA==.',
Le='Legault:BAABLgAECn8rAAInAAkJIB9pAQDmAgAnAAkJIB9pAQDmAgAAAA==.Legionofboom:BAAALgADCgQJBgAAAA==.Lethfel:BAABLgAECn8VAAMWAAgJ4xs4WgCPAQAWAAYJYBw4WgCPAQAXAAYJlRbkIABNAQAAAA==.Lethferal:BAAALgADCgIJAgAAAA==.',
Li='Liacci:BAAALgADCgYJBgAAAA==.Lilgoukii:BAAALgADCgIJAgAAAA==.Lillithfaust:BAAALgAECgMJCQAAAA==.Lilreaper:BAAALgADCggJCQAAAA==.Limbø:BAABLgAECn8eAAIUAAcJLCFSSQD/AQAUAAcJLCFSSQD/AQAAAA==.Lindia:BAAALgADCgEJAQAAAA==.Lionfury:BAAALgAECgEJAgAAAA==.Lionguard:BAAALgAECgUJBQAAAA==.Liquidturtle:BAAALgAECgMJBAAAAA==.Livie:BAABLgAECn8oAAIFAAkJlBgQNQAsAgAFAAkJlBgQNQAsAgAAAA==.',
Lo='Lonelylad:BAAALgAECgEJAQAAAA==.Loneshark:BAAALgAECgYJCQAAAA==.Longwood:BAAALgAECgYJCAAAAA==.Lonon:BAAALgADCgQJBAAAAA==.Loops:BAAALgAECgIJAwAAAA==.Loraddesmos:BAACLgAFFH8FAAIXAAMJXAXUBwCZAAAXAAMJXAXUBwCZAAAuAAQKf0MAAhcACQmWFP4GAOsBABcACQmWFP4GAOsBAAAA.Loriah:BAABLgAECn8wAAIFAAkJShXTRwDvAQAFAAkJShXTRwDvAQAAAA==.Lovan:BAAALgAECgEJAwAAAA==.',
Lu='Lucance:BAAALgAECgIJAgAAAA==.Lullaby:BAABLgAECn8vAAIEAAkJhRcQFgAiAgAEAAkJhRcQFgAiAgAAAA==.Lumot:BAAALgADCgcJCwAAAA==.',
Ma='Maeg:BAAALgAECgIJAgABLgAFFAMJCAAkAEgTAA==.Mahll:BAAALgAFFAIJAgABLgAFFAMJBwAUAMQZAA==.Maireldps:BAAALgAECgYJDAAAAA==.Manawarr:BAAALgAECgIJAwAAAA==.Marcdofu:BAAALgAECgQJBQAAAA==.Maryjanè:BAAALgAECgUJBQAAAA==.Mataquay:BAAALgAECggJEAAAAA==.Maveloris:BAAALgADCgcJBgAAAA==.Mavennes:BAAALgAECgQJAwAAAA==.Mawzshallah:BAACLgAFFH8dAAILAAYJ5yN2EACiAQALAAYJ5yN2EACiAQAuAAQKfzMAAwsACQllJWgBAMEDAAsACQllJWgBAMEDABsABQl6FLMTADQBAAAA.Mayli:BAAALgAFFAMJAwAAAA==.',
Mc='Mctanker:BAABLgAECn8aAAMjAAcJUBGKHQApAQAjAAcJUBGKHQApAQAFAAUJBgte9wDCAAAAAA==.',
Me='Meascii:BAACLgAFFH8aAAIeAAUJ6gpwDwAgAQAeAAUJ6gpwDwAgAQAuAAQKfyQAAh4ACQlaGRMOAIwCAB4ACQlaGRMOAIwCAAAA.Medeaeris:BAAALgADCgIJAgAAAA==.Meepmorp:BAAALgAECgEJAQAAAA==.Megs:BAAALgADCgYJBgAAAA==.Merc:BAACLgAFFH8jAAIcAAgJLB7XAgAuAgAcAAgJLB7XAgAuAgAuAAQKfzoAAhwACQksI5kFAPcCABwACQksI5kFAPcCAAAA.',
Mi='Millee:BAABLgAECn8hAAMEAAgJZBx/GAAJAgAEAAgJZBx/GAAJAgAVAAIJpgPGhQA0AAAAAA==.Mincebeef:BAAALgAECgMJAwABLgAECggJGgAEALkXAA==.Mindpuck:BAAALgAECgQJBAAAAA==.Mirefighter:BAAALgAECgMJAwABLgAFFAcJIAAYABYdAA==.Miremana:BAAALgAECgcJDwABLgAFFAcJIAAYABYdAA==.Mirespike:BAACLgAFFH8gAAIYAAcJFh09AwCZAQAYAAcJFh09AwCZAQAuAAQKfzIAAhgACQlSIpkDAPgCABgACQlSIpkDAPgCAAAA.Mistylady:BAAALgADCgIJBAAAAA==.',
Mo='Mommacougar:BAAALgADCgEJAQAAAA==.Moondrade:BAAALgAECgUJBQAAAA==.Moosebearowl:BAAALgAFFAMJAwAAAA==.Morfirrann:BAAALgADCgEJAQAAAA==.Morlis:BAAALgAECgQJCAAAAA==.Morlock:BAABLgAECn8rAAMWAAkJvQtXWgCPAQAWAAkJvQtXWgCPAQANAAEJWwgfNQAxAAAAAA==.Morningstahr:BAAALgAECgUJBQAAAA==.',
Mu='Murlen:BAAALgAECgMJBAAAAA==.',
My='Mystris:BAAALgADCgYJBgAAAA==.Mythidru:BAAALgAECgcJDgAAAA==.',
['Mâ']='Mâjestic:BAAALgADCgMJAwAAAA==.',
Na='Naanbread:BAAALgAFFAIJAgAAAA==.Naaruto:BAABLgAECn8aAAIFAAgJzQ6+iwBZAQAFAAgJzQ6+iwBZAQAAAA==.Nadia:BAABLgAECn8gAAQeAAYJnBCrCwDkAAAeAAYJkBCrCwDkAAAEAAUJBAl8TQCtAAAVAAMJ9gJgeABPAAAAAA==.Nanako:BAABLgAECn8zAAIUAAkJrxh5LwBbAgAUAAkJrxh5LwBbAgAAAA==.Naughtyvixen:BAAALgAECgMJAgABLgAECgkJGwAdAAYJAA==.Naughtyvoked:BAAALgAECgYJCgABLgAECgkJGwAdAAYJAA==.Navali:BAAALgAECgMJCAABLgAFFAEJAQAIAAAAAA==.',
Ne='Nefer:BAAALgADCgUJBQAAAA==.Nevicus:BAAALgAECgIJAwAAAA==.',
Ni='Nickayla:BAAALgADCggJCAAAAA==.Nikkaya:BAAALgAECgMJAwABLgAECgYJHgAbAJAcAA==.Nimblecow:BAAALgAECgUJBQAAAA==.Nisdenar:BAAALgADCgkJDgAAAA==.',
No='Noobacleese:BAABLgAECn8wAAIFAAkJrxvsLABNAgAFAAkJrxvsLABNAgAAAA==.Noraviae:BAAALgADCgMJAwAAAA==.',
Nu='Nutbustin:BAABLgAECn8hAAIUAAkJBhntQAAZAgAUAAkJBhntQAAZAgAAAA==.',
Ny='Nyghtrider:BAABLgAECn8YAAIGAAYJpQuloQD+AAAGAAYJpQuloQD+AAAAAA==.Nykayla:BAAALgAECgcJAwAAAA==.Nymëra:BAABLgAECn8fAAIhAAkJ7w1BVABjAQAhAAkJ7w1BVABjAQAAAA==.Nyneeve:BAABLgAECn9BAAIVAAkJBRRkBACLAQAVAAkJBRRkBACLAQAAAA==.',
Ob='Obscené:BAAALgAECgQJBAAAAA==.',
Od='Oddessyee:BAAALgADCgcJBwABLgAECggJGAAGAPUYAA==.Oddiee:BAABLgAECn8YAAMCAAcJNw/FrAAZAQACAAcJNw/FrAAZAQAZAAQJzgP0OQB0AAABLgAECggJGAAGAPUYAA==.Odinshunter:BAAALgAECgYJBgAAAA==.Odst:BAAALgADCgUJBwABLgAFFAUJDAACALQZAA==.',
Oh='Ohdatroll:BAABLgAFFH8FAAMDAAIJ0AVWXABIAAADAAIJ0AVWXABIAAAcAAEJIA0jHQA8AAABLgAFFAMJCAAkAEgTAA==.',
Ol='Olgrin:BAAALgAECgEJAQABLgAECgYJCwAIAAAAAA==.',
On='Onepunch:BAAALgAECgEJAQAAAA==.Oneslice:BAAALgAECgUJBgAAAA==.Onyxstar:BAAALgAECgEJAQAAAA==.',
Op='Opera:BAAALgAECgQJBgAAAA==.',
Or='Orangelol:BAAALgAECgUJBQABLgAFFAMJBQAiAAkhAA==.Orikkosh:BAABLgAECn8fAAMSAAcJ0haaJQCBAQASAAcJ0haaJQCBAQAcAAIJuwpCcQBNAAAAAA==.Orw:BAAALgAECgIJAgAAAA==.',
Ot='Otsmayo:BAAALgAECgkJBwAAAA==.',
Pa='Palel:BAABLgAECn83AAIKAAkJLRHbKwCyAQAKAAkJLRHbKwCyAQAAAA==.Palpatinee:BAAALgAECgQJBAAAAA==.Pancetta:BAAALgAECgEJAQABLgAECgkJQgARAAskAA==.Parabelum:BAAALgAECgIJAgAAAA==.',
Pb='Pbfearz:BAABLgAECn8WAAMWAAYJhh8TWAC/AQAWAAUJhh8TWAC/AQAXAAEJAADsXgBSAAAAAA==.',
Pe='Peguelo:BAAALgADCgIJAgAAAA==.Pendrágon:BAAALgAECgIJAgAAAA==.Percocetpete:BAACLgAFFH8NAAIEAAUJBRcSEABTAQAEAAUJBRcSEABTAQAuAAQKfx4AAwQACAnaJCQCAE8DAAQACAnaJCQCAE8DABUAAgkmDpN5AEwAAAAA.Peregrine:BAAALgADCgMJAwAAAA==.',
Ph='Phaet:BAACLgAFFH8gAAMWAAcJmyK7LQCOAQAWAAcJmyK7LQCOAQAXAAEJiw5oFQBUAAAuAAQKfzUAAhYACQnxJHQJADMDABYACQnxJHQJADMDAAAA.Phatty:BAAALgADCgMJAwAAAA==.Phaux:BAAALgAECgIJAgAAAA==.Philipp:BAABLgAECn8gAAILAAkJDwrsLgBlAQALAAkJDwrsLgBlAQAAAA==.',
Pi='Picco:BAAALgADCgEJAQABLgAECgUJCQAIAAAAAA==.Pixistix:BAAALgAFFAEJAQAAAA==.',
Pl='Plâgue:BAABLgAECn8bAAICAAkJ4xpfTADdAQACAAkJ4xpfTADdAQAAAA==.',
Pn='Pneuma:BAAALgADCgEJAQAAAA==.',
Po='Potentialman:BAAALgAECggJDAAAAA==.',
Pr='Preprot:BAAALgADCgkJCQABLgAECgkJJwAZADoVAA==.Prot:BAAALgAFFAEJAQAAAA==.',
Pu='Punslug:BAAALgAECgYJCgABLgAFFAIJBgAYAM4aAA==.Puntthegnome:BAAALgAFFAMJBAABLgAFFAUJIQAUAI0eAA==.',
['Pó']='Pókóu:BAAALgADCgMJAwAAAA==.',
Ra='Radiance:BAAALgAECgcJEwAAAA==.Raezorian:BAAALgAFFAEJAQABLgAFFAQJBQAcAB8dAA==.Rahmo:BAAALgADCgYJBgAAAA==.Rainforest:BAABLgAECn8eAAIbAAYJkBztGwBuAQAbAAYJkBztGwBuAQAAAA==.Rakiji:BAAALgAECgEJAQAAAA==.Ralphh:BAAALgADCgIJAgAAAA==.Ramdem:BAAALgAECggJEAAAAA==.Ramden:BAABLgAECn86AAIFAAkJPg2+dACEAQAFAAkJPg2+dACEAQAAAA==.Rampant:BAACLgAFFH8MAAICAAUJtBmvTgBVAQACAAUJtBmvTgBVAQAuAAQKfxcAAwIACQkXIEMfAI0CAAIACQkXIEMfAI0CABkAAQmVIBVPAFYAAAAA.Rampscii:BAAALgAECgUJBgABLgAFFAUJDAACALQZAA==.Randalore:BAAALgAECgMJAwABLgAFFAMJCAAkAEgTAA==.Randwulf:BAAALgAECggJEwAAAA==.Ranwong:BAAALgAECgQJCgAAAA==.Ratherton:BAACLgAFFH8hAAIUAAUJjR5sRABfAQAUAAUJjR5sRABfAQAuAAQKfysAAxQACQmbIO0wAK8CABQACQmbIO0wAK8CACgAAwnRHM8NAOkAAAAA.Rathtard:BAABLgAECn8XAAIGAAkJ3BqMIQBfAgAGAAkJ3BqMIQBfAgABLgAFFAUJIQAUAI0eAA==.Rauloso:BAAALgAECgQJEQAAAA==.Ravìn:BAAALgAECgYJDAAAAA==.Rayne:BAAALgAECgcJCAABLgAFFAEJAQAIAAAAAA==.Razz:BAAALgAECgEJAwAAAA==.',
Rd='Rdata:BAAALgADCgkJEAAAAA==.',
Re='Relentlezz:BAAALgADCgMJAwABLgAECgkJLwAdAGUfAA==.Resoluteone:BAABLgAECn9MAAIZAAkJkhViEQD2AQAZAAkJkhViEQD2AQAAAA==.Retnu:BAAALgAECgEJAQAAAA==.Revytwohand:BAACLgAFFH8gAAMcAAcJWxopCwBvAQAcAAYJxx0pCwBvAQADAAUJjgzSNADYAAAuAAQKfzQAAhwACQmXJUoEABUDABwACQmXJUoEABUDAAAA.Reáper:BAAALgAECgEJAQAAAA==.',
Rh='Rhagul:BAAALgAFFAIJAgAAAA==.Rhok:BAAALgADCgEJAQAAAA==.Rhokhard:BAAALgADCgEJAwAAAA==.',
Ro='Rocketarena:BAAALgAECgcJDwAAAA==.Rootytooty:BAAALgAECgIJAgAAAA==.Rozelie:BAABLgAFFH8HAAILAAMJ4hIxMQC9AAALAAMJ4hIxMQC9AAABLgAFFAcJHwAeAH8aAA==.',
Ry='Ryzarapriest:BAAALgAECgMJBAABLgAFFAEJAQAIAAAAAA==.',
['Ré']='Réaper:BAAALgADCgEJAQAAAA==.',
Sa='Sabeladys:BAABLgAECn8oAAIFAAkJRCHLFQDAAgAFAAkJRCHLFQDAAgAAAA==.Sadpeepo:BAAALgADCgIJAgAAAA==.Saifir:BAABLgAECn8pAAIhAAkJBRH1OADMAQAhAAkJBRH1OADMAQAAAA==.Sardmongo:BAAALgADCgcJCgAAAA==.Sardogobo:BAAALgAECgEJAQABLgAECggJIgAWAIEUAA==.Sarduccini:BAABLgAECn8iAAIWAAgJgRTaTADiAQAWAAgJgRTaTADiAQAAAA==.Sargeros:BAAALgAECgQJBAAAAA==.',
Se='Sebastîan:BAAALgAECgEJAQABLgAECgkJIAAWABkZAA==.Sekhmet:BAAALgAECgcJCAAAAA==.Sekio:BAAALgAECgYJCwAAAA==.',
Sh='Shadowpriest:BAAALgADCgEJAQAAAA==.Shamburgyr:BAAALgAECgMJAwABLgAECggJNQAGAEQUAA==.Shampáin:BAAALgAECgIJAgAAAA==.Shanàs:BAAALgAECgEJAQABLgAECgkJGwAFAEYeAA==.Sharayu:BAAALgAECgMJBAAAAA==.Shea:BAAALgADCgYJBgAAAA==.Sheamus:BAAALgADCgkJCQAAAA==.Shiftken:BAAALgAECgMJAwAAAA==.Shiftyfive:BAAALgAFFAMJAwAAAA==.Shivà:BAAALgADCgUJCAAAAA==.',
Si='Siara:BAAALgAECgEJAQAAAA==.Sigrodah:BAACLgAFFH8PAAMQAAUJ9g8rNQDuAAAQAAQJ9g8rNQDuAAAPAAEJswG2LAA1AAAuAAQKfxkAAxAACAlTH9cRAF0CABAACAlTH9cRAF0CAA4ABAm2EW4pANQAAAAA.Silvalus:BAAALgAECgYJCwAAAA==.Silvertide:BAAALgAECgkJCQAAAA==.Sin:BAAALgAECgkJCQAAAA==.',
Sk='Skaara:BAAALgAECgQJBwAAAA==.Skara:BAAALgADCgEJAQAAAA==.Skiddles:BAAALgADCgIJAgAAAA==.Skinwalker:BAAALgADCgYJCgAAAA==.Skithyryx:BAAALgADCgIJAgAAAA==.Skonka:BAAALgAECgMJAwAAAA==.Skor:BAAALgADCgQJBAAAAA==.Skyblue:BAAALgAECgEJAQAAAA==.Skyeforce:BAAALgAECgMJBAAAAA==.',
Sl='Slipknoth:BAABLgAECn8UAAMKAAYJkRmEUwAsAQAKAAUJFheEUwAsAQAFAAYJoRIQuAAVAQAAAA==.',
Sm='Smellyy:BAAALgADCgEJAQAAAA==.Smite:BAAALgAECgUJCAAAAA==.Smoketurtle:BAAALgAECgUJCAAAAA==.',
Sn='Sno:BAAALgAECgEJAQAAAA==.',
So='Socatoas:BAABLgAECn8ZAAIBAAkJtglqNQBzAQABAAkJtglqNQBzAQAAAA==.Softbanana:BAAALgADCgEJAQAAAA==.Soi:BAAALgAECgYJCgABLgAECgkJGAAFAE0hAA==.Solarion:BAAALgAECgEJAQABLgAECgcJFAAgAEMPAA==.Sonoforak:BAAALgAECgYJCAAAAA==.',
Sp='Sped:BAACLgAFFH8FAAIdAAMJ9Rd4CwDZAAAdAAMJ9Rd4CwDZAAAuAAQKfzkABB0ACQmKHx0FAMoCAB0ACQmKHx0FAMoCACYABQmzCG8vAHoAAAEAAQn3A/euAC0AAAAA.',
St='Stalrun:BAAALgAECgYJCgABLgAECgYJEgAIAAAAAA==.Staraleena:BAAALgAECgUJBQAAAA==.Starrlynn:BAAALgAECgEJAQAAAA==.Stormeyes:BAAALgAECgMJAQABLgAECggJIwAjAOoaAA==.Stormslight:BAABLgAECn8jAAIjAAgJ6hrgDAD3AQAjAAgJ6hrgDAD3AQAAAA==.Stormsteel:BAAALgAECgMJBgAAAA==.Stôrmrägé:BAAALgAECgcJDQAAAA==.',
Sw='Swgchainz:BAAALgAECgcJEwABLgAECgkJLQARADEdAA==.Swiftdéath:BAAALgAECgYJCgAAAA==.Swtbabybilly:BAAALgAECgYJCQAAAA==.',
Sy='Sylvänäs:BAAALgAFFAEJAQAAAA==.',
['Sä']='Säberdh:BAAALgADCgYJBgABLgAECgMJAwAIAAAAAA==.',
['Så']='Såran:BAAALgAECgUJCwAAAA==.',
['Sí']='Sílence:BAABLgAECn8VAAILAAgJrwkUSADsAAALAAgJrwkUSADsAAAAAA==.',
['Sô']='Sôlrïx:BAAALgAECgUJCgAAAA==.',
Ta='Tabio:BAAALgADCgYJBgAAAA==.Tabios:BAAALgAECgEJAQAAAA==.Tabito:BAAALgAECgEJAQAAAA==.Taby:BAAALgADCgIJAgAAAA==.Talas:BAABLgAECn8wAAIjAAkJnRYtDgDhAQAjAAkJnRYtDgDhAQAAAA==.Taltaelen:BAAALgADCgYJBgABLgAECgkJHwACAA4WAA==.Tamarack:BAABLgAECn8XAAIGAAYJshuJUQB0AQAGAAYJshuJUQB0AQAAAA==.',
Te='Teetsie:BAAALgAFFAEJAQAAAA==.Tehmber:BAAALgAECgQJCAABLgAECgYJCAAIAAAAAA==.Tehmplar:BAAALgAECgYJCAAAAA==.Terrormisu:BAAALgAECgEJAQABLgAECggJGQAFAHEcAA==.',
Th='Thalorien:BAAALgADCgYJBgABLgAECgcJFwAKAIghAA==.Theboart:BAAALgAECgQJCQAAAA==.Tholindis:BAAALgAECgUJBQAAAA==.Thredron:BAABLgAFFH8HAAIKAAMJTAdfNwCQAAAKAAMJTAdfNwCQAAAAAA==.',
Ti='Tilted:BAAALgAECgkJCwABLgAECgkJLwAEAIUXAA==.Timebarred:BAAALgAECgEJBAAAAA==.',
To='Tooru:BAACLgAFFH8XAAQGAAYJqhJWOwA2AQAGAAUJMhZWOwA2AQAJAAEJsg5ZMQBNAAAlAAEJXwIGHQA+AAAuAAQKfzYABAYACQm+IYsGACUDAAYACQm+IYsGACUDAAkACAncEOMcALUBACUABgkWGT1LACUBAAAA.Tortiana:BAAALgAECgUJBQAAAA==.Tossko:BAAALgAECgIJAwABLgAECgQJDAAIAAAAAA==.',
Tr='Traefel:BAAALgAECgMJAwAAAA==.Traeflor:BAAALgAECgEJAQAAAA==.Traevok:BAAALgAECgEJAgAAAA==.Trailertrash:BAABLgAECn9EAAIUAAgJnB9NNwA7AgAUAAgJnB9NNwA7AgAAAA==.Treebeef:BAACLgAFFH8dAAIkAAYJpAgrKwALAQAkAAYJpAgrKwALAQAuAAQKfzIAAyQACQkCG+0YAHACACQACQkCG+0YAHACAAsAAQnWA/GMACIAAAAA.Triena:BAAALgAECgQJBgAAAA==.Trirn:BAAALgADCgYJBgAAAA==.Trishool:BAAALgAECgEJAQAAAA==.Trumpeter:BAAALgAECgQJCwAAAA==.Trywind:BAAALgAECgYJBgAAAA==.',
Ts='Tsukuyómi:BAAALgAECgEJAQAAAA==.',
Ty='Tydrielion:BAAALgAECgYJDgAAAA==.Typicaldrood:BAAALgAECgIJAgAAAA==.',
['Tí']='Tízzíts:BAAALgADCgYJBgAAAA==.',
Ul='Ullreich:BAABLgAECn8YAAIGAAcJVwsnjgAjAQAGAAcJVwsnjgAjAQAAAA==.Ulysius:BAACLgAFFH8OAAIFAAQJRha1JgDcAAAFAAQJRha1JgDcAAAuAAQKfysAAgUACQmWGVs0AC8CAAUACQmWGVs0AC8CAAAA.',
Un='Unfazed:BAAALgAECgEJAQAAAA==.Unicornslayr:BAABLgAECn8qAAIKAAkJTRYTKQDEAQAKAAkJTRYTKQDEAQAAAA==.',
Ur='Urund:BAAALgAECgYJDgAAAA==.Uruquizas:BAAALgAECgUJBQAAAA==.',
Uw='Uwantsmoke:BAABLgAECn8eAAIGAAYJMwRsuwDPAAAGAAYJMwRsuwDPAAAAAA==.Uwantsmokee:BAAALgADCgMJAwAAAA==.',
Va='Valgroth:BAAALgAECgIJAwAAAA==.Valkisek:BAACLgAFFH8SAAIUAAQJxhDaXwAhAQAUAAQJxhDaXwAhAQAuAAQKfxoAAhQACAlzGgqbAJ8BABQACAlzGgqbAJ8BAAAA.Valkonigen:BAAALgAECgEJAQAAAA==.Vallarfax:BAABLgAECn8rAAIGAAkJIx/WGACRAgAGAAkJIx/WGACRAgAAAA==.Vandaam:BAAALgAECgEJAQAAAA==.Vandro:BAACLgAFFH8GAAIKAAMJWgyuFQCdAAAKAAMJWgyuFQCdAAAuAAQKfzAABAoACQkPGlkCAAwCAAoACQkPGlkCAAwCAAUABAnjFhcUAAsBACMABgnaCuUsALgAAAAA.Vantive:BAAALgAECgYJDwAAAA==.Vash:BAAALgAECgEJAQAAAA==.Vashdk:BAACLgAFFH8TAAIZAAYJvRmsFQA/AQAZAAYJvRmsFQA/AQAuAAQKfxUAAhkACAnEFn8QAAMCABkACAnEFn8QAAMCAAAA.Vashmonk:BAACLgAFFH8MAAISAAQJzyO4FAB9AQASAAQJzyO4FAB9AQAuAAQKfxUAAhIACQmcIUQMAHECABIACQmcIUQMAHECAAAA.Vashwar:BAAALgAECgYJBgAAAA==.',
Ve='Vedruid:BAAALgAECggJDwAAAA==.Velaric:BAABLgAECn8vAAMkAAkJyhvFFACkAgAkAAkJyhvFFACkAgAbAAEJ3gv1gQAfAAAAAA==.Velcyn:BAAALgADCgcJDgABLgAECgIJAgAIAAAAAA==.Veldoria:BAAALgAECgQJBgAAAA==.Veloe:BAAALgAECgIJAgAAAA==.Veloranas:BAABLgAECn8dAAIUAAkJmRFuBwDJAQAUAAkJmRFuBwDJAQAAAA==.Verath:BAAALgADCgEJAQAAAA==.Vespyr:BAABLgAECn81AAIGAAgJRBTXCQCiAQAGAAgJRBTXCQCiAQAAAA==.Vespyrlynd:BAAALgAECgYJBgABLgAECggJNQAGAEQUAA==.Vewdoo:BAACLgAFFH8HAAIiAAMJMR0uEwDoAAAiAAMJMR0uEwDoAAAuAAQKf0QAAiIACQm2JLkCAEkDACIACQm2JLkCAEkDAAAA.',
Vi='Viejoverde:BAAALgAECgQJCAAAAA==.Vipul:BAAALgAECgYJDgABLgAFFAEJAgAIAAAAAA==.Vizimir:BAAALgAECgkJEgAAAA==.',
Vo='Voldune:BAAALgAECgIJAwAAAA==.',
['Vë']='Vëgetå:BAAALgADCgYJBwABLgAECgUJBQAIAAAAAA==.',
Wa='Waiwai:BAAALgAECgEJAgAAAA==.Warfarin:BAAALgAECgEJBAAAAA==.Wascii:BAACLgAFFH8IAAIGAAQJSxAVHQAkAQAGAAQJSxAVHQAkAQAuAAQKfyEAAgYACQkYFX42AAMCAAYACQkYFX42AAMCAAEuAAUUBQkMAAIAtBkA.Waxedthataxe:BAAALgAECgEJAQAAAA==.Waxesaxes:BAAALgAECgQJBwAAAA==.',
We='Weaken:BAAALgAECgUJCwAAAA==.Weskr:BAAALgADCgEJAQABLgAECggJJAAEAKscAA==.',
Wi='Wickedsinner:BAAALgADCgEJAQAAAA==.Wizkerbizkit:BAAALgAECgMJBQAAAA==.',
Wo='Wolvesbane:BAABLgAFFH8FAAIGAAUJbwAYqwBCAAAGAAUJbwAYqwBCAAAAAA==.',
Wy='Wyrmblood:BAAALgAECgcJDgABLgAECgkJOAAVAPsjAA==.Wyrmfur:BAABLgAECn8lAAMbAAgJCCIlAQBtAgAbAAgJCCIlAQBtAgAYAAQJUh6hHwALAQABLgAECgkJOAAVAPsjAA==.Wyrmheal:BAABLgAECn84AAIVAAkJ+yMbAQCwAgAVAAkJ+yMbAQCwAgAAAA==.Wyvvie:BAAALgADCgIJAgAAAA==.',
Xa='Xavil:BAAALgAECgEJAQAAAA==.Xavv:BAAALgADCgUJBQAAAA==.',
Xi='Xiba:BAAALgAECgQJBwAAAA==.',
Xl='Xle:BAAALgADCgIJAgAAAA==.',
Ya='Yakoff:BAAALgAECgUJBQAAAA==.Yamihime:BAABLgAECn82AAMRAAkJURYtGQC4AQARAAgJ5xctGQC4AQAHAAkJvwvBXAByAQAAAA==.Yatiri:BAABLgAECn8kAAMiAAkJoh2EAQChAgAiAAkJoh2EAQChAgAhAAEJQQ6X3gAqAAAAAA==.',
Yo='Yoowuzsup:BAABLgAECn8aAAIiAAcJnBxJMAB+AQAiAAcJnBxJMAB+AQAAAA==.',
Yu='Yureimage:BAABLgAECn8WAAIUAAYJMAtf1wDnAAAUAAYJMAtf1wDnAAAAAA==.',
Za='Zarthus:BAAALgAECggJAgAAAA==.',
Ze='Zeaket:BAACLgAFFH8tAAIJAAkJbB14AQBeAgAJAAkJbB14AQBeAgAuAAQKfy8AAgkACQmSIhkBAGEDAAkACQmSIhkBAGEDAAAA.Zedsdeadd:BAAALgAECgYJDwAAAA==.Zephyr:BAABLgAECn8qAAIeAAgJBggjDQDIAAAeAAgJBggjDQDIAAABLgAECggJNQAGAEQUAA==.Zerrayna:BAAALgAECgQJBwAAAA==.Zeçhs:BAABLgAECn8YAAIFAAkJTSFZFADxAgAFAAkJTSFZFADxAgAAAA==.',
Zi='Zinek:BAAALgAECgQJBQAAAA==.Zinra:BAAALgAECgUJDwAAAA==.',
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
