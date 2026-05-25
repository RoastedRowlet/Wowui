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

local lookup = {'Warlock-Destruction','Warlock-Demonology','Mage-Frost','Monk-Mistweaver','Monk-Windwalker','Paladin-Retribution','DemonHunter-Vengeance','Shaman-Restoration','Paladin-Holy','Unknown-Unknown','Hunter-Marksmanship','Hunter-Survival','Evoker-Augmentation','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Frost','Warrior-Fury','Evoker-Devastation','Priest-Holy','DemonHunter-Devourer','Rogue-Subtlety','Warrior-Arms','Druid-Restoration','DeathKnight-Blood','Monk-Brewmaster','Paladin-Protection','Priest-Discipline','Shaman-Elemental','Evoker-Preservation','Warrior-Protection','Rogue-Outlaw','Druid-Feral','Druid-Guardian','Druid-Balance','Warlock-Affliction','DemonHunter-Havoc','Shaman-Enhancement','Priest-Shadow',}
local provider = {region='US',realm='Anvilmar',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aaril:BAAALgAECgQJEAAAAQ==.',
Ab='Abrams:BAAALgADCgYJBgAAAA==.',
Ad='Adel:BAAALgAECgQJBAAAAA==.',
Ae='Aelitha:BAABLgAECn8ZAAMBAAYJCQZ2OQDOAAABAAYJxAR2OQDOAAACAAYJsQQ0uAC9AAAAAA==.',
Ak='Akaishi:BAAALgADCgIJAgAAAA==.Akali:BAAALgAFFAEJAQAAAA==.Akina:BAAALgADCgYJBwABLgAECgkJJwADACsOAA==.',
Al='Alanie:BAAALgAECgIJAgAAAA==.Alathiana:BAAALgADCgUJCAAAAA==.Alcweaver:BAABLgAECn8dAAMEAAcJgiCdGAAUAgAEAAcJgiCdGAAUAgAFAAYJgA9zNQACAQAAAA==.Alecto:BAAALgAECgMJAwAAAA==.Alindia:BAAALgAECgQJCgABLgAECgkJJwADACsOAA==.Alirrayia:BAAALgAECgQJBAAAAA==.Alirrayiia:BAACLgAFFH8IAAIGAAMJ+AGnXgCyAAAGAAMJ+AGnXgCyAAAuAAQKfygAAgYACQlxEC1NAPsBAAYACQlxEC1NAPsBAAAA.Alkri:BAAALgADCgMJAwAAAA==.Allari:BAAALgAECgYJEwAAAA==.Allikazam:BAAALgADCgYJEwAAAA==.Allystar:BAAALgAECgQJCwAAAA==.Altheia:BAAALgAECgQJBAAAAA==.Alvidor:BAABLgAECn8yAAIDAAgJiQT0oQAdAQADAAgJiQT0oQAdAQAAAA==.',
Am='Ameria:BAAALgADCgUJBQAAAA==.Amybabe:BAAALgAECgEJAQAAAA==.',
An='Anastos:BAAALgAECgUJBQAAAA==.Andydufresne:BAAALgAECgQJCgABLgAECggJPAAHAAUmAA==.Angryqueer:BAAALgADCgEJAQAAAA==.',
Ao='Aowl:BAAALgAECgcJCwAAAA==.',
Ap='Apocketheory:BAAALgADCgIJAgAAAA==.Apolloerosb:BAAALgADCggJDgABLgAECgcJGQAIAHkVAA==.Apollossham:BAABLgAECn8ZAAIIAAcJeRW2MQC9AQAIAAcJeRW2MQC9AQAAAA==.',
Ar='Arkanaun:BAABLgAECn8dAAMGAAYJRBdpcwCUAQAGAAYJRBdpcwCUAQAJAAUJvRQbQwALAQAAAA==.',
As='Ashes:BAAALgAECgcJAQAAAA==.Ashrán:BAAALgAECgYJCQAAAA==.Ashyluna:BAAALgAECgQJBAAAAA==.Astianna:BAAALgADCgMJAwAAAA==.',
Au='Aule:BAAALgAECgIJAwAAAA==.Aurinia:BAAALgADCgQJAgAAAA==.Auroradinlee:BAAALgAECgkJBgAAAA==.Aurore:BAAALgADCgQJBgAAAA==.',
Av='Avradea:BAAALgADCgEJAQABLgAECgkJJwADACsOAA==.',
Az='Azareth:BAAALgADCggJCAAAAA==.',
Ba='Baconatorr:BAAALgAECgQJBQAAAA==.Bagelbags:BAAALgADCgEJAQAAAA==.Bahler:BAAALgADCgUJBQABLgAECgMJAwAKAAAAAA==.Baji:BAABLgAECn8zAAIIAAkJLSI6BQA6AwAIAAkJLSI6BQA6AwAAAA==.Baklan:BAAALgAECgMJAwAAAA==.Barefaall:BAACLgAFFH8KAAILAAYJ+g2CEgDzAAALAAYJ+g2CEgDzAAAuAAQKfzcAAgsACQlAID4CALgCAAsACQlAID4CALgCAAAA.Barefall:BAAALgAFFAIJAgABLgAFFAYJCgALAPoNAA==.Barefalls:BAACLgAFFH8FAAIMAAMJlhy+FAD/AAAMAAMJlhy+FAD/AAAuAAQKfyUAAwwACQkfHngIAHwCAAwACQkfHngIAHwCAAsAAQmMAaCWACIAAAEuAAUUBgkKAAsA+g0A.Barelywolf:BAABLgAECn8dAAMEAAgJkBmhHgDiAQAEAAcJZBmhHgDiAQAFAAQJoBwUKQBDAQABLgAFFAMJBgANACwLAA==.Bashira:BAABLgAECn8eAAIOAAkJsAqrRQCkAQAOAAkJsAqrRQCkAQAAAA==.Bast:BAABLgAECn8nAAMPAAkJYBSjNQAFAgAPAAkJYBSjNQAFAgAQAAQJiQ2uHQCQAAAAAA==.Bastienne:BAAALgAECgMJAwAAAA==.Bastrillan:BAAALgAECgUJBgAAAA==.',
Be='Bearophe:BAAALgAECgEJAgAAAA==.Beerfist:BAAALgAECgEJAQAAAA==.Bellock:BAAALgAECgMJAwAAAA==.Bendroyd:BAAALgAECgIJAgAAAA==.Benisbagina:BAAALgADCggJCQAAAA==.Bergonator:BAABLgAECn8gAAIRAAYJcRC9TwBpAQARAAYJcRC9TwBpAQAAAA==.Berrodiah:BAAALgAECgYJCAABLgAECggJFgASALUYAA==.Bettyswalls:BAAALgAECgMJAwAAAA==.Beyarago:BAAALgAECgUJCQAAAA==.',
Bh='Bheiroth:BAABLgAECn8wAAITAAkJSCTpAgBQAwATAAkJSCTpAgBQAwAAAA==.',
Bi='Birds:BAAALgAECgUJCAAAAA==.',
Bl='Bladeygaga:BAABLgAECn8qAAIUAAkJyhvRFQB3AgAUAAkJyhvRFQB3AgAAAA==.Blasé:BAAALgAECgcJCAAAAA==.Blazingblood:BAAALgADCgUJAQAAAA==.Bloodknight:BAAALgADCgYJCQAAAA==.Bluekrayen:BAAALgAECgUJBQAAAA==.Bluett:BAAALgAECgMJBgAAAA==.Bláckøut:BAAALgADCgYJDAAAAA==.',
Bo='Bodhi:BAABLgAECn8WAAIVAAcJNhAQJwDAAQAVAAcJNhAQJwDAAQAAAA==.Bogertus:BAACLgAFFH8MAAIRAAMJVCQOGAAuAQARAAMJVCQOGAAuAQAuAAQKf0AAAxEACQnSJiMAAJgDABEACQnSJiMAAJgDABYAAgn1HHIpAKUAAAAA.Bonobo:BAAALgAECgQJBAAAAA==.Boomertunes:BAABLgAECn8dAAMCAAgJvxbCOwDTAQACAAgJvxbCOwDTAQABAAIJGwGwRwAAAAAAAA==.',
Br='Brein:BAABLgAECn8yAAIXAAgJ3iXwAwBoAwAXAAgJ3iXwAwBoAwAAAA==.Brewmaster:BAAALgAECgIJAwAAAA==.Brewwmaster:BAABLgAECn8kAAQYAAkJrBg+EgC7AQAYAAkJIBU+EgC7AQAPAAYJtBfWfACKAQAQAAEJ+he5FgA2AAAAAA==.Brickred:BAAALgADCggJDgAAAA==.Brynodd:BAAALgAECgMJBgAAAA==.',
Bu='Bubblybetty:BAAALgAECgEJAQAAAA==.Bucketeer:BAABLgAECn8rAAIDAAkJUR9BFQC/AgADAAkJUR9BFQC/AgAAAA==.Buffs:BAAALgADCgEJAQAAAA==.Bullminator:BAAALgADCgIJAwAAAA==.Bursona:BAAALgAECgEJAQAAAA==.Butterfree:BAAALgAECgUJDAAAAA==.',
Ca='Cards:BAAALgAECgYJCgAAAA==.Carkrash:BAAALgADCgkJFwAAAA==.Casterkang:BAAALgAECgUJCQAAAA==.Catshunter:BAAALgAECgYJDgAAAA==.',
Ce='Celaa:BAABLgAECn8nAAIDAAkJKw4rTgDUAQADAAkJKw4rTgDUAQAAAA==.',
Ch='Chanka:BAAALgAECgQJBgAAAA==.Chantillary:BAAALgAECgMJBgAAAA==.Chargerkang:BAAALgADCgYJBgAAAA==.Chchanges:BAAALgAECgEJAQAAAA==.Cheesy:BAABLgAECn8fAAICAAcJHgohhAAcAQACAAcJHgohhAAcAQAAAA==.Chicken:BAAALgAECgYJEQAAAA==.Chonk:BAAALgADCgEJAQAAAA==.Chopzullee:BAAALgAECgYJEwAAAA==.',
Ci='Cirya:BAAALgAECgUJCAAAAA==.',
Cl='Cleric:BAAALgADCgUJBQAAAA==.Clortho:BAAALgAECgMJAwAAAA==.',
Co='Coljack:BAAALgAECggJCAAAAA==.Colljack:BAACLgAFFH8aAAIJAAUJ9R5yBwBdAQAJAAUJ9R5yBwBdAQAuAAQKfyEAAwkACQkgIZwJANgCAAkACQkgIZwJANgCAAYABQlOEtO5ABIBAAAA.',
Cr='Crocbait:BAAALgAECgcJEQAAAA==.Cryptoe:BAABLgAECn8eAAIDAAkJzRM3PAAOAgADAAkJzRM3PAAOAgAAAA==.',
Cu='Cudlsac:BAAALgAECgQJBQAAAA==.',
Da='Daedelus:BAABLgAECn8WAAMHAAcJORNUGACzAAAUAAcJORMJhwDoAAAHAAUJfg1UGACzAAAAAA==.Daglon:BAAALgAECggJDAAAAA==.Dagz:BAAALgAECgQJBAAAAA==.Dakina:BAAALgADCgYJBgAAAA==.Daraedra:BAAALgADCgYJEgAAAA==.Darkenvoid:BAAALgADCgkJDQAAAA==.',
De='Deathslight:BAAALgAECgQJBwAAAA==.Deeznutticus:BAACLgAFFH8bAAIRAAYJKhaCBgCiAQARAAYJKhaCBgCiAQAuAAQKfx8AAxEABwnCIkgYAIkCABEABwnCIkgYAIkCABYAAQkSFhw8AEEAAAAA.Defnotisis:BAABLgAECn8dAAMZAAgJhxQoIwByAQAZAAcJCRYoIwByAQAFAAgJtAvPNwD2AAABLgAFFAEJAQAKAAAAAA==.Demonspud:BAABLgAECn8dAAIUAAcJhRJNVgBgAQAUAAcJhRJNVgBgAQAAAA==.Denxster:BAAALgAECgYJDgAAAA==.Dersan:BAABLgAECn8aAAIBAAgJ1ABvMwA4AAABAAgJ1ABvMwA4AAAAAA==.Destriant:BAABLgAECn81AAIaAAkJZhlkCAAiAgAaAAkJZhlkCAAiAgAAAA==.Devilschant:BAAALgAECgYJCgAAAA==.Devilshadow:BAAALgAECgUJBwABLgAECgYJCgAKAAAAAA==.Dewburt:BAAALgADCggJCgAAAA==.Deylia:BAAALgADCgkJDwABLgAFFAQJEgAbAJ0YAA==.',
Di='Dilithia:BAAALgAECgQJCwAAAA==.Dillion:BAAALgAECgYJCAAAAA==.Dinonuggies:BAAALgADCgcJBwAAAA==.Dionin:BAAALgADCgYJCQAAAA==.Dira:BAAALgAECgYJEQABLgAFFAUJFwAcACofAA==.Dirkbanne:BAAALgADCgYJBgAAAA==.',
Do='Dodoubleg:BAAALgAECgYJEAAAAA==.Dominique:BAAALgADCgYJBgAAAA==.Donzilch:BAEALgAECgQJBAAAAA==.Donzilly:BAAALgAECgUJBQAAAA==.Dooburt:BAAALgAECgUJBQAAAA==.',
Dr='Dracaric:BAABLgAECn8mAAINAAgJYxenGwDYAQANAAgJYxenGwDYAQAAAA==.Draeca:BAAALgAECgMJBgAAAA==.Dragondznut:BAAALgAECgQJBQAAAA==.Drakhar:BAAALgADCgIJAgABLgAECgYJCwAKAAAAAA==.Drfrostie:BAAALgAECgcJEgAAAA==.Drgunner:BAAALgAECgcJDwAAAA==.Driatin:BAAALgAECgIJBwABLgAECgUJDAAKAAAAAA==.Drkladykikyo:BAABLgAECn8XAAITAAkJFQP/NwD3AAATAAkJFQP/NwD3AAAAAA==.Druroo:BAAALgAECgEJAQABLgAFFAMJAwAKAAAAAA==.Druterr:BAAALgAECgIJAgAAAA==.',
Du='Dumb:BAACLgAFFH8PAAIdAAUJLAyTBgCJAQAdAAUJLAyTBgCJAQAuAAQKfyMAAh0ACAnoG28LAH4CAB0ACAnoG28LAH4CAAAA.Durø:BAABLgAECn8WAAIUAAgJryLZDAAZAwAUAAgJryLZDAAZAwAAAA==.Duskhunter:BAAALgADCgEJAQAAAA==.',
Dy='Dyanisian:BAAALgADCgYJCAAAAA==.',
['Dè']='Dègenerate:BAABLgAECn8zAAIeAAkJlB9kBADCAgAeAAkJlB9kBADCAgAAAA==.',
Ed='Edagerran:BAAALgADCgkJCQAAAA==.',
Ei='Eilae:BAAALgAECgYJEQAAAA==.Eirhakan:BAAALgAECgQJCAAAAA==.',
El='Elrethyl:BAABLgAECn8WAAIGAAcJXhjJYQCNAQAGAAcJXhjJYQCNAQAAAA==.Elvanus:BAAALgADCgYJBgAAAA==.Elêktra:BAABLgAECn8sAAIcAAkJuA4LKQB6AQAcAAkJuA4LKQB6AQAAAA==.',
Ep='Epicnym:BAAALgADCgcJBwAAAA==.Epicsmoke:BAACLgAFFH8GAAIRAAMJ/A16LQC3AAARAAMJ/A16LQC3AAAuAAQKfzwAAhEACQndIicEAAoDABEACQndIicEAAoDAAAA.Epidemius:BAAALgAECgkJCgAAAA==.',
Er='Erevan:BAABLgAECn8uAAMVAAkJ7BOKDQAqAgAVAAkJ7BOKDQAqAgAfAAEJpwABEAAcAAAAAA==.Eroica:BAAALgADCgYJBwAAAA==.Eronys:BAAALgAECgkJAgAAAA==.',
Es='Esdeath:BAABLgAECn8pAAMPAAkJ5hKKRQDPAQAPAAkJ5hKKRQDPAQAYAAYJWgacMwCdAAAAAA==.',
Et='Etharia:BAAALgADCgUJAwAAAA==.',
Ev='Evilsmeghead:BAAALgADCgEJAQAAAA==.',
Ex='Extenze:BAABLgAECn8oAAIUAAkJXx3AFACAAgAUAAkJXx3AFACAAgAAAA==.',
Ez='Ezykiah:BAAALgADCggJHwAAAA==.',
Fa='Falconponch:BAAALgADCgEJAQAAAA==.',
Fe='Felbjorn:BAAALgAECgEJAQAAAA==.Felgibson:BAAALgAECgQJBQAAAA==.Felkang:BAAALgADCgkJCQAAAA==.Ferryman:BAAALgAECgYJDQAAAA==.',
Fl='Flingor:BAAALgAECgYJEAAAAA==.Flokha:BAAALgADCgEJAQAAAA==.',
Fo='Forphium:BAACLgAFFH8XAAIVAAYJ7w+lBACkAQAVAAYJ7w+lBACkAQAuAAQKfxwAAhUACQlbH30NAMQCABUACQlbH30NAMQCAAAA.',
Fr='Fredolf:BAAALgAECgEJAQAAAA==.Freydís:BAAALgAECgUJCwAAAA==.Friarkuck:BAAALgADCggJCAAAAA==.Friedbones:BAAALgAECgMJBgAAAA==.Frostlilliy:BAAALgADCggJCwAAAA==.',
['Fü']='Fürbie:BAAALgAECgIJAwAAAA==.',
Ga='Gahlina:BAAALgAECgQJDAAAAA==.Galdorian:BAAALgADCgYJCQABLgAECgkJHgAOALAKAA==.Galynda:BAAALgADCgQJBQAAAA==.',
Ge='Genjimain:BAABLgAECn8lAAMXAAkJBhqRHgBKAgAXAAkJBhqRHgBKAgAgAAMJ9wyXKACPAAAAAA==.Genjí:BAAALgAECgEJAwAAAA==.Geris:BAAALgAECgQJBQAAAA==.Gertruide:BAAALgADCgUJBQAAAA==.',
Gh='Ghendala:BAAALgADCggJEwAAAA==.',
Gi='Gillesmon:BAAALgAECggJCwABLgAECggJDAAKAAAAAA==.Gincainn:BAAALgAECgEJAgAAAA==.Gird:BAABLgAECn8oAAIJAAgJ4Q24MABtAQAJAAgJ4Q24MABtAQAAAA==.Girdlock:BAAALgAECgYJBwAAAA==.',
Gl='Glaiveyjones:BAAALgAECgEJAQAAAA==.',
Gn='Gnymesis:BAAALgADCgkJEAAAAA==.',
Go='Goatmonger:BAAALgAECgYJBgAAAA==.Goinpostal:BAAALgAECgIJAgAAAA==.Goldblade:BAAALgAECgkJEwAAAA==.Goodvsevil:BAAALgAECgQJBAAAAA==.Gordek:BAABLgAECn8bAAMGAAgJEByHMAAdAgAGAAgJEByHMAAdAgAJAAIJhBBMaQBfAAAAAA==.Gothitelle:BAAALgAECgEJAwAAAA==.Goöse:BAACLgAFFH8ZAAIPAAYJJh7dAwDEAQAPAAYJJh7dAwDEAQAuAAQKfycAAg8ACAmDJusGAGsDAA8ACAmDJusGAGsDAAAA.',
Gr='Grantaron:BAABLgAECn81AAIGAAkJ2iAXEQDEAgAGAAkJ2iAXEQDEAgAAAA==.Gravarii:BAAALgADCgcJEwAAAA==.Grimskul:BAABLgAECn8qAAMPAAkJrRw5FgCgAgAPAAkJrRw5FgCgAgAQAAYJDxSUBwCBAQAAAA==.Grindor:BAAALgADCgEJAQAAAA==.Grntitan:BAAALgAECgQJBwAAAA==.Gruid:BAAALgADCgcJDwAAAA==.',
Gu='Guinessbrew:BAAALgAECgEJAQAAAA==.',
Gw='Gwoohoori:BAAALgAECggJCwAAAA==.',
Gy='Gyra:BAAALgAECgYJEQAAAA==.',
Ha='Halukari:BAABLgAECn8UAAMhAAYJXiCICwDYAQAhAAYJXiCICwDYAQAiAAEJ8gzahgApAAABLgAFFAQJEgAbAJ0YAA==.Harfnan:BAAALgAECgIJAgAAAA==.Harrin:BAABLgAECn8cAAIDAAcJ9g+oiQBIAQADAAcJ9g+oiQBIAQAAAA==.',
He='Healingwater:BAAALgAECgIJAwAAAA==.Herracles:BAAALgADCgYJEwAAAA==.Hezrel:BAAALgAECgYJCgAAAA==.',
Hi='Hierodule:BAAALgAECgEJAQAAAA==.Hiimriven:BAAALgAECgIJAgABLgAECgYJFgAVAFkhAA==.Hinal:BAABLgAECn8fAAIGAAgJEh3NKgA0AgAGAAgJEh3NKgA0AgAAAA==.',
Ho='Hojo:BAAALgADCgUJCAAAAA==.Holyenabler:BAABLgAFFH8IAAIaAAMJCwf9CwCDAAAaAAMJCwf9CwCDAAAAAA==.Hootiehoo:BAAALgADCgMJAwAAAA==.',
Hu='Huflunggoo:BAAALgADCgkJDQAAAA==.Huflungpoop:BAABLgAECn80AAIFAAkJqBqLDQBGAgAFAAkJqBqLDQBGAgAAAA==.Hunterborn:BAAALgAFFAIJAgAAAA==.',
Hy='Hypercube:BAAALgAECgMJAwAAAA==.',
['Hè']='Hèalz:BAAALgADCgcJCQABLgAECgkJJwARAIQcAA==.',
Ic='Ickixia:BAAALgADCgQJBAAAAA==.',
Il='Ilkaressa:BAAALgADCgQJBAAAAA==.Illyríá:BAEBLgAFFH8GAAICAAMJXw4gYADXAAACAAMJXw4gYADXAAABLgAECggJJgABAMEbAA==.Ilun:BAAALgAECgEJAQAAAA==.',
Im='Imcruel:BAACLgAFFH8TAAIDAAYJJhqTHgCoAQADAAYJJhqTHgCoAQAuAAQKfywAAgMACQnNJbAJABkDAAMACQnNJbAJABkDAAAA.Ims:BAAALgAECgcJAQAAAA==.',
In='Ink:BAACLgAFFH8NAAIDAAQJKxGPRgA6AQADAAQJKxGPRgA6AQAuAAQKfycAAgMABwm2IE9MANoBAAMABwm2IE9MANoBAAAA.',
Is='Istaria:BAAALgAECgMJBQAAAA==.Isujr:BAABLgAECn8ZAAIPAAcJ8hIKcQCmAQAPAAcJ8hIKcQCmAQAAAA==.',
Ja='Jacaerys:BAAALgADCgYJBgAAAA==.Jackiegan:BAABLgAECn8kAAQZAAkJOh6aBgCyAgAZAAkJDB6aBgCyAgAFAAEJahGTcgBGAAAEAAEJJgdJmAAeAAAAAA==.Jackson:BAAALgAECgMJBgAAAA==.Jagerdemon:BAAALgAECgcJBwAAAA==.',
Je='Jerce:BAAALgADCgUJBQAAAA==.',
Jh='Jhala:BAAALgADCgcJCAAAAA==.',
Jo='Joshcalc:BAAALgAECgYJCQAAAA==.Joskel:BAABLgAECn8vAAQCAAgJDw2pXwBrAQACAAgJiQypXwBrAQAjAAYJMQToFgDIAAABAAIJNgw1KQBaAAAAAA==.',
Ju='Juacqer:BAAALgAECgMJBgAAAA==.',
Ka='Kaant:BAABLgAECn8yAAMcAAgJFhv3EwAfAgAcAAgJFhv3EwAfAgAIAAcJaxXYPgCAAQAAAA==.Kaeni:BAAALgADCgMJAwAAAA==.Kaidevyn:BAABLgAECn8nAAMQAAgJKxEGDgBHAQAQAAgJKxEGDgBHAQAPAAQJWgoQ6wCRAAAAAA==.Kaiste:BAAALgADCgEJAQAAAA==.Kaleine:BAAALgAECgYJCAAAAA==.Kardren:BAAALgAECgUJDAAAAA==.Kat:BAAALgAECgMJAwAAAA==.',
Ke='Keiko:BAAALgAECggJDwAAAA==.Keiran:BAABLgAECn8zAAMOAAkJ4yKYBQAaAwAOAAkJ4yKYBQAaAwALAAgJpRzPEgCgAgAAAA==.Kelazurin:BAAALgADCgEJAQAAAA==.Kellistair:BAAALgADCgYJBgAAAA==.Keläo:BAAALgADCgUJCQAAAA==.Kenshii:BAAALgAECgEJAQAAAA==.Keyadish:BAAALgADCgYJDQAAAA==.Keys:BAACLgAFFH8HAAIVAAMJlhUbHgDxAAAVAAMJlhUbHgDxAAAuAAQKfyYAAhUACAkTHrkQAJwCABUACAkTHrkQAJwCAAAA.',
Kh='Khalnerys:BAABLgAECn8iAAMNAAgJcgl+OgAaAQANAAgJJgh+OgAaAQASAAUJwQdsEwCxAAAAAA==.Khitt:BAAALgAECgEJAQABLgAECgMJBQAKAAAAAA==.Khoulock:BAACLgAFFH8RAAICAAYJjhJoMQBEAQACAAYJjhJoMQBEAQAuAAQKfzUABAIACQnKIKwLANwCAAIACQm6IKwLANwCACMABQliIoYOAD4BAAEAAwl9ENU+ALkAAAAA.',
Ki='Kimmi:BAAALgAECggJEQAAAA==.Kimmispally:BAAALgAECgIJAwAAAA==.Kiro:BAAALgADCgQJBQAAAA==.',
Kn='Knowimsayin:BAAALgAECgEJAQAAAA==.',
Ko='Kota:BAAALgAECgEJAQAAAA==.Kotateal:BAAALgAECgYJCwAAAA==.',
Kr='Kruelshot:BAACLgAFFH8KAAIOAAQJoRawKAAyAQAOAAQJoRawKAAyAQAuAAQKfxYAAw4ACAnFJK4LANMCAA4ACAnFJK4LANMCAAsABwlqEgAyAKgBAAEuAAUUBgkTAAMAJhoA.Krux:BAAALgAECgEJAQAAAA==.',
Kt='Kthxbye:BAAALgAECgUJBwABLgAECgcJBwAKAAAAAA==.',
Ku='Kumcookies:BAAALgADCgEJAQAAAA==.Kungfuprissy:BAAALgAECgMJBwAAAA==.Kuraishin:BAACLgAFFH8SAAIgAAMJGB5WBwAPAQAgAAMJGB5WBwAPAQAuAAQKf2sAAyAABwkMI7kFAGMCACAABwkMI7kFAGMCACEABAmbHRQaAN4AAAEuAAUUBAkSAA8A4gsA.Kuroakuma:BAAALgAECgYJEAAAAA==.Kuvara:BAAALgADCgkJCgAAAA==.',
Kv='Kvnnp:BAAALgADCgYJBgAAAA==.Kvnpro:BAAALgADCgUJBwAAAA==.Kvnxx:BAAALgADCgUJBQAAAA==.',
Kw='Kwandashadow:BAAALgAECgUJDgAAAA==.',
Ky='Kylemonk:BAAALgADCgEJAQAAAA==.',
['Ké']='Kéres:BAAALgADCgkJEAAAAA==.',
La='Lagspike:BAABLgAECn8dAAIDAAgJqBXagQBXAQADAAgJqBXagQBXAQAAAA==.Latheal:BAAALgAECgMJBAAAAA==.Lavi:BAABLgAECn8dAAIGAAgJDA5ncQBrAQAGAAgJDA5ncQBrAQAAAA==.',
Lb='Lbk:BAAALgADCgIJAgAAAA==.',
Le='Lejeune:BAAALgAECgMJBgAAAA==.Lengex:BAAALgAECggJCwAAAA==.Lero:BAABLgAECn8iAAIZAAkJuCHrAwDzAgAZAAkJuCHrAwDzAgAAAA==.Lerwindion:BAABLgAECn8hAAIbAAgJOR+VCQCiAgAbAAgJOR+VCQCiAgABLgAFFAMJAwAKAAAAAA==.Lescaryn:BAAALgADCgIJAgAAAA==.Lexoh:BAAALgAECgYJEgAAAA==.',
Li='Lilani:BAAALgADCgQJBAAAAA==.Lindir:BAACLgAFFH8NAAIMAAQJ3RrbCgBVAQAMAAQJ3RrbCgBVAQAuAAQKfygAAgwACAk+JKkBAD8DAAwACAk+JKkBAD8DAAAA.Lionelle:BAAALgAECgYJDgAAAA==.Liquor:BAACLgAFFH8SAAIUAAUJ2hnoJwBGAQAUAAUJ2hnoJwBGAQAuAAQKf04AAxQACQmJIUEIAPcCABQACQmJIUEIAPcCAAcAAwnPFDIbAJoAAAAA.Liquorish:BAAALgAECgEJAQABLgAFFAUJEgAUANoZAA==.Lirathiel:BAAALgAECgQJDAAAAA==.Litasfk:BAAALgAECgIJAgAAAA==.Liuni:BAABLgAECn8lAAIZAAkJlRSvGgCxAQAZAAkJlRSvGgCxAQAAAA==.Liyin:BAAALgAECgQJCQABLgAECgkJJwADACsOAA==.',
Lo='Lobopeste:BAABLgAECn8yAAIYAAgJBApuJQD5AAAYAAgJBApuJQD5AAAAAA==.Locknutz:BAAALgADCgMJAwAAAA==.Loracy:BAAALgADCgcJBwAAAA==.Lorelynn:BAABLgAECn8mAAICAAgJ8A1wWwB2AQACAAgJ8A1wWwB2AQAAAA==.',
Lu='Luci:BAABLgAECn8XAAQUAAgJ6RIRQgCgAQAUAAgJkxIRQgCgAQAHAAMJ1Q61JgBGAAAkAAEJAAC1aQAAAAABLgAFFAEJAQAKAAAAAA==.Lucìan:BAABLgAECn8lAAIXAAgJiCE6CgD6AgAXAAgJiCE6CgD6AgAAAA==.Ludociel:BAAALgAECgQJBAAAAA==.Lunaclair:BAACLgAFFH8SAAIPAAQJ4gvpWAAdAQAPAAQJ4gvpWAAdAQAuAAQKf1cAAw8ACQkoHQEfAGwCAA8ACQkoHQEfAGwCABgABwmNEGoiABABAAAA.Lunadrus:BAABLgAECn8mAAIDAAgJogklmwAoAQADAAgJogklmwAoAQAAAA==.Lunarielle:BAACLgAFFH8RAAIOAAQJIRCaLgAkAQAOAAQJIRCaLgAkAQAuAAQKfyEAAg4ACAkXHMYVAIkCAA4ACAkXHMYVAIkCAAAA.',
Ly='Lyriaa:BAAALgADCgYJCwAAAA==.',
Ma='Macalatraz:BAAALgAECgMJBAAAAA==.Macfly:BAABLgAECn8sAAIOAAkJrRpOIgAxAgAOAAkJrRpOIgAxAgAAAA==.Madmeatballs:BAAALgAECgEJAQABLgAECgkJKwADAFEfAA==.Magdala:BAAALgADCgEJAQAAAA==.Magicmissile:BAACLgAFFH8IAAIDAAIJaQwNhACaAAADAAIJaQwNhACaAAAuAAQKfyYAAgMACAk1HuMqAFECAAMACAk1HuMqAFECAAEuAAUUBAkKABEASgwA.Makgora:BAAALgAECgMJBAABLgAECgYJFgAVAFkhAA==.Makhvan:BAAALgAECgQJCgAAAA==.Maksoon:BAAALgAECgUJDAAAAA==.Maladjusted:BAAALgAECgMJBAAAAA==.Maléfique:BAAALgAECgEJAQAAAA==.Mancath:BAAALgAECgkJCwAAAA==.Maplè:BAAALgAECgIJAwABLgAECggJIwAIAKITAA==.Mar:BAAALgADCgMJAwAAAA==.Marlei:BAAALgADCgQJBAABLgAECgkJJwADACsOAA==.Marqose:BAAALgADCgcJDgABLgAECgMJAwAKAAAAAA==.Matan:BAAALgADCgUJBQAAAA==.',
Me='Meeko:BAAALgAFFAIJAwABLgAFFAcJFQAdAC0fAA==.Melfie:BAABLgAECn8aAAIDAAgJdAxdcQB6AQADAAgJdAxdcQB6AQAAAA==.Meliadoul:BAABLgAECn8YAAIDAAgJ7wvseQBnAQADAAgJ7wvseQBnAQAAAA==.Mellyndra:BAABLgAECn8yAAIJAAgJMB9EDwB9AgAJAAgJMB9EDwB9AgAAAA==.Mercüry:BAAALgAECgEJAwAAAA==.Mezhren:BAAALgAECgYJCwAAAA==.',
Mh='Mhoramsgirl:BAAALgADCggJCwAAAA==.',
Mi='Midoriya:BAACLgAFFH8FAAIFAAMJHQfuHQC2AAAFAAMJHQfuHQC2AAAuAAQKfyMAAwUACQlnEV4mAFYBAAUACAkvEl4mAFYBAAQABQmQEWVhAJMAAAAA.Mistjack:BAABLgAFFH8LAAIEAAUJthHbFgBJAQAEAAUJthHbFgBJAQAAAA==.',
Mo='Momdad:BAACLgAFFH8SAAIMAAUJ6xdgDABKAQAMAAUJ6xdgDABKAQAuAAQKfzQAAgwACQnWIGgFALgCAAwACQnWIGgFALgCAAAA.Mongaux:BAAALgADCgQJBQAAAA==.Monkey:BAAALgAECgQJCgAAAA==.Morrígán:BAAALgADCgUJBQAAAA==.Moxi:BAAALgADCggJDQAAAA==.',
Mu='Muamman:BAAALgAECgMJAwAAAA==.Murda:BAAALgADCgYJCgAAAA==.Murphysflaw:BAAALgADCgUJCAAAAA==.Mutegen:BAAALgAFFAEJAQAAAA==.',
Mx='Mxhealeryduf:BAAALgAECgIJAgAAAA==.',
My='Mystallian:BAAALgAECgQJBgAAAA==.Mystí:BAEALgAECgkJBgABLgAECggJJgABAMEbAA==.Mythicplus:BAAALgAECgcJEQAAAA==.',
['Mé']='Mémnoc:BAAALgAECgMJAwAAAA==.',
Na='Nadarien:BAAALgAECgYJDQAAAA==.Nadyia:BAAALgADCgEJAQAAAA==.Nailah:BAAALgADCgcJCwAAAA==.Nannergoat:BAAALgADCgMJAwAAAA==.Nastymikey:BAABLgAECn8bAAIlAAgJNx13BwBzAgAlAAgJNx13BwBzAgAAAA==.Nazdormu:BAABLgAECn8cAAIdAAYJRwTgIQC7AAAdAAYJRwTgIQC7AAAAAA==.',
Ne='Nefarious:BAAALgAECgcJDAAAAA==.Neisen:BAABLgAECn8mAAMJAAgJQBkPEwBTAgAJAAgJQBkPEwBTAgAGAAUJBwKc+gCeAAAAAA==.Neptune:BAAALgADCgYJBgAAAA==.',
No='Norna:BAAALgADCgcJDwAAAA==.Noz:BAAALgADCgkJCQAAAA==.',
Nu='Nufonewhodis:BAABLgAECn8WAAIVAAYJWSF1HQATAgAVAAYJWSF1HQATAgAAAA==.',
Ny='Nykolas:BAAALgAECgEJAQAAAA==.Nymofthedead:BAABLgAECn8jAAMPAAgJ/SE/FACuAgAPAAgJ/SE/FACuAgAQAAMJlBquHACaAAAAAA==.',
Oa='Oakgrove:BAAALgADCgUJBQAAAA==.',
Om='Ombraless:BAAALgADCgMJAwABLgAECgQJCAAKAAAAAA==.',
On='Oneforall:BAAALgAECgkJDAAAAA==.',
Op='Ophrizhani:BAAALgAECgMJAwAAAA==.',
Or='Orangegrove:BAAALgAECgUJAwAAAA==.Orpheal:BAAALgAECgUJBQAAAA==.Orphen:BAAALgAECgMJAwAAAA==.',
Pa='Paddleball:BAAALgADCgQJBAAAAA==.Paladouin:BAAALgAECgYJEwAAAA==.Pandammy:BAAALgAECgkJAgAAAA==.Pantro:BAABLgAECn8UAAMgAAcJeAw4FwAiAQAgAAcJeAw4FwAiAQAhAAEJAACIaQAAAAAAAA==.Papalion:BAAALgAECgYJEwAAAA==.Paragas:BAAALgADCgkJEAAAAA==.Pawbs:BAAALgAECgQJEAAAAA==.',
Pe='Peanuts:BAAALgADCgcJBwAAAA==.Peoplehugger:BAAALgADCgMJAwAAAA==.',
Pi='Pickleburger:BAAALgAECgEJAQAAAA==.Pinklilydrd:BAAALgAECgMJBgAAAA==.',
Pl='Plaindonut:BAAALgAECgcJEwAAAA==.',
Po='Porple:BAAALgADCgIJAwAAAA==.',
Pr='Priestdrago:BAAALgADCgUJBQAAAA==.Prissidebow:BAAALgAECgMJBgAAAA==.',
Qu='Quartz:BAAALgAECgYJCAABLgAFFAMJDAARAFQkAA==.',
Ra='Rahzule:BAAALgADCgYJBwAAAA==.Ralynne:BAABLgAECn8uAAIcAAgJMxQfJACZAQAcAAgJMxQfJACZAQAAAA==.Ravenbrook:BAACLgAFFH8RAAIRAAQJ6iUtBQC2AQARAAQJ6iUtBQC2AQAuAAQKfyMAAxEACAlbJXsEAGIDABEACAlbJXsEAGIDABYAAQkwIDlRAFMAAAAA.Rawrr:BAABLgAECn8dAAIkAAYJBQqALgDUAAAkAAYJBQqALgDUAAAAAA==.Rawrxd:BAAALgAECgEJAgABLgAECggJDgAKAAAAAA==.Raxie:BAACLgAFFH8SAAMbAAQJnRj/GABCAQAbAAQJnRj/GABCAQAmAAEJBQ3SFABRAAAuAAQKfysABBsACAl6G2sPAEwCABsACAl6G2sPAEwCACYABwnIE6slAHUBABMAAQkBBPGHACgAAAAA.Razeth:BAABLgAECn8VAAIMAAYJ8BYmJwBDAQAMAAYJ8BYmJwBDAQAAAA==.',
Re='Reanne:BAAALgAECgYJEAAAAA==.Res:BAAALgAECgYJCwAAAA==.Rescorla:BAAALgAECgkJDAAAAA==.Rethali:BAAALgADCgQJAgAAAA==.Rezr:BAAALgAECggJDgAAAA==.',
Rh='Rhixa:BAAALgADCgUJBQAAAA==.Rhymunky:BAAALgAECgYJDQAAAA==.',
Ri='Rifthor:BAAALgAECgYJEAAAAA==.Rillx:BAAALgADCgQJBgAAAA==.Ripmxi:BAABLgAECn8uAAIDAAkJUhLtSwDbAQADAAkJUhLtSwDbAQAAAA==.',
Ro='Robinski:BAAALgADCgEJAQAAAA==.Robotiss:BAAALgADCgIJAgAAAA==.Rocco:BAAALgADCgYJBwAAAA==.Rodevon:BAAALgADCggJCAAAAA==.Roknasaurus:BAAALgADCgUJCAAAAA==.Romani:BAAALgADCgYJBgAAAA==.Romeo:BAAALgAECgQJBAAAAA==.Ronaldreagnt:BAAALgAECgcJDQAAAA==.',
Ru='Runecat:BAAALgAECgEJAQAAAA==.Runelight:BAACLgAFFH8HAAMbAAMJOQHHKwCbAAAbAAMJOQHHKwCbAAAmAAIJsgG0KABlAAAuAAQKfxQABBsABwnoCTs0ABYBABsABgnUCjs0ABYBABMABQmACcs/AMkAACYAAwkQBQtZAHIAAAAA.Rupertgiless:BAACLgAFFH8MAAICAAUJ1BB9IgB2AQACAAUJ1BB9IgB2AQAuAAQKfyQAAgIACQloGn0iAIsCAAIACQloGn0iAIsCAAAA.',
Sa='Sabeckya:BAAALgAECgQJCgAAAA==.Sacksmasher:BAAALgADCgcJDwAAAA==.Sampleshrimp:BAAALgADCgEJAgAAAA==.Saphyla:BAAALgADCgcJCwAAAA==.Sappheire:BAAALgAECgYJBgAAAA==.Sarcastyx:BAAALgAECgYJBwAAAA==.Sarrod:BAAALgADCgUJBQAAAA==.Saxines:BAAALgAECgYJEQAAAA==.',
Sc='Scaliefox:BAAALgAECgIJAgABLgAECggJMgAJADAfAA==.Scarl:BAAALgADCgUJBQAAAA==.Schwarznacht:BAAALgADCgUJBQAAAA==.Schwarzwölf:BAAALgADCgYJCwAAAA==.Scoots:BAAALgADCgQJBAAAAA==.Scrubs:BAAALgAECgYJDAAAAA==.Scrubsevoker:BAAALgAECgQJBAAAAA==.Scumbum:BAAALgADCgIJAgAAAA==.Scyllo:BAAALgAECgQJBAAAAA==.',
Se='Seekndestroy:BAAALgAECgYJDgAAAA==.Selige:BAAALgAECgQJBAAAAA==.',
Sg='Sgtcuunt:BAAALgADCgQJBAAAAA==.',
Sh='Shaenicor:BAAALgADCgIJAgAAAA==.Shelbo:BAAALgADCgcJEAAAAA==.Shmolda:BAAALgADCgYJBwAAAA==.Shortshammy:BAAALgAECgEJAQABLgAFFAMJCwADACUJAA==.Shror:BAAALgADCgEJAQABLgAECgUJBQAKAAAAAA==.',
Si='Sicarune:BAAALgAECgUJBgAAAA==.Siiegrand:BAABLgAECn8VAAIaAAcJhRDkHgDtAAAaAAcJhRDkHgDtAAAAAA==.Silentswag:BAAALgAECgYJDgAAAA==.Sindrane:BAAALgAECgMJAwABLgAECgkJMgAPAKoUAA==.Sitzho:BAAALgADCgUJCAAAAA==.',
Sk='Skeleton:BAAALgAECgIJAgAAAA==.Skybringer:BAABLgAECn8tAAIGAAYJLw1IqgAGAQAGAAYJLw1IqgAGAQAAAA==.Skyee:BAABLgAECn8qAAMFAAkJvx0LDAC6AgAFAAkJvx0LDAC6AgAEAAMJGxReWwCnAAAAAA==.Skylos:BAAALgAECgEJAgAAAA==.',
Sm='Smexibiotch:BAAALgADCgYJBgAAAA==.',
So='Soapscum:BAAALgADCgQJBAAAAA==.Soarphium:BAAALgAECgIJAgABLgAFFAYJFwAVAO8PAA==.Solararc:BAAALgADCgEJAgAAAA==.Soleana:BAAALgAECgYJBQAAAA==.Sombra:BAAALgAECgMJBAABLgAECgcJDAAKAAAAAA==.Sonicast:BAAALgAECgYJCQAAAA==.Sooie:BAAALgAECgYJEgAAAA==.Soramian:BAAALgADCgcJEgAAAA==.Soulcacher:BAABLgAECn8yAAMPAAkJqhShSwAQAgAPAAgJJxahSwAQAgAYAAgJvQ/tFwB0AQAAAA==.Soxxy:BAAALgAECgEJAQABLgAFFAEJAQAKAAAAAA==.',
Sp='Spellgunner:BAABLgAECn8VAAIDAAgJPxtVUADOAQADAAgJPxtVUADOAQAAAA==.',
St='Stormwulf:BAAALgADCgUJBQABLgAECgMJCQAKAAAAAA==.Stormyprissi:BAAALgAECgQJBAAAAA==.Strombjorn:BAABLgAECn8jAAMIAAgJohM4PACLAQAIAAgJohM4PACLAQAcAAUJwQxmUQDCAAAAAA==.',
['Sø']='Sølaria:BAAALgAECgEJAQAAAA==.',
Ta='Tasireth:BAAALgADCgcJBwAAAA==.',
Te='Tessi:BAABLgAECn8WAAIDAAYJIhGwlwAuAQADAAYJIhGwlwAuAQAAAA==.',
Th='Thalrian:BAAALgAECgQJBQABLgAFFAMJBQARAN8ZAA==.Thefailnym:BAAALgAECggJCQAAAA==.Theylive:BAAALgAECggJEwAAAA==.Thondrin:BAAALgAECgYJCwAAAA==.Thordanil:BAAALgAECgEJAgAAAA==.Thrashedass:BAAALgADCgEJAQAAAA==.',
Ti='Tigerlilliy:BAAALgADCgYJEAAAAA==.Timerek:BAAALgADCgIJAgAAAA==.',
To='Toawulf:BAAALgAECgQJBwABLgAECgMJCQAKAAAAAA==.Tokifuji:BAAALgAECgIJAgABLgAECgQJEAAKAAAAAA==.Toya:BAABLgAECn8xAAIVAAkJZRxOCgBbAgAVAAkJZRxOCgBbAgAAAA==.',
Tr='Trenazen:BAAALgADCgkJCgAAAA==.Trevain:BAAALgAECgEJAgAAAA==.Trimasdrood:BAAALgADCgMJAwAAAA==.Trivia:BAAALgADCgYJFwAAAA==.Trundle:BAAALgAECgEJAwAAAA==.Truthordare:BAABLgAECn8hAAIBAAcJUgiyFgDMAAABAAcJUgiyFgDMAAAAAA==.',
Tu='Turtei:BAAALgAECgEJAQABLgAFFAYJJAAFAKomAA==.Turtl:BAACLgAFFH8kAAIFAAYJqiYIAQBFAgAFAAYJqiYIAQBFAgAuAAQKfysAAgUACQnmJjcAAPgDAAUACQnmJjcAAPgDAAAA.',
Tw='Twohoof:BAAALgADCgEJAQAAAA==.',
Tx='Txìewtkuä:BAAALgADCgkJCQAAAA==.',
Ty='Tyryn:BAAALgADCgMJBAAAAA==.',
Ug='Uglydragon:BAAALgAECgcJDAAAAA==.Uglypally:BAAALgADCgkJCQAAAA==.Uglypetguy:BAAALgAECgIJAgAAAA==.Uglyrogue:BAAALgAECgQJAgAAAA==.Uglyshaman:BAAALgAECgEJAgAAAA==.',
Ul='Ulgrym:BAAALgAECgMJBQAAAA==.Ultimatia:BAAALgADCgMJBwAAAA==.',
Un='Unbalancéd:BAAALgAECgUJDwAAAA==.',
Va='Vahra:BAAALgAECgMJBgAAAA==.Valanther:BAAALgAECgMJAwAAAA==.Valantis:BAAALgADCgEJAQAAAA==.Valgaskav:BAABLgAECn8oAAIGAAkJXyPjBgAgAwAGAAkJXyPjBgAgAwAAAA==.Valimond:BAAALgAECgEJAQABLgAECgMJCQAKAAAAAA==.Valric:BAAALgADCgYJBwAAAA==.Vanarrath:BAAALgADCgYJBwAAAA==.Vandryelle:BAAALgADCgIJAgAAAA==.Varge:BAAALgADCgMJAwAAAA==.Varrathos:BAAALgADCgkJEgAAAA==.Vayl:BAAALgAECgMJAwAAAA==.',
Ve='Velisa:BAAALgADCgYJBgAAAA==.Ventrue:BAAALgADCgMJAwAAAA==.Verdesoul:BAAALgAECgUJCgAAAA==.Vesyra:BAAALgAECgQJBQAAAA==.',
Vi='Viralyn:BAAALgADCgMJAwABLgAECgkJJQAZAJUUAA==.Vixøn:BAAALgAECgIJAwAAAA==.',
Vo='Voidluck:BAABLgAECn8SAAIUAAgJvxBkdABIAQAUAAgJvxBkdABIAQAAAA==.Voker:BAAALgAECgMJCAABLgAECgQJEAAKAAAAAA==.Voladis:BAAALgAECgYJCAAAAA==.Voladro:BAAALgAECgQJBAAAAA==.Volos:BAABLgAECn8pAAIGAAgJORZSRwDRAQAGAAgJORZSRwDRAQAAAA==.Vordaman:BAABLgAECn8tAAIPAAkJYRMqRwDKAQAPAAkJYRMqRwDKAQAAAA==.',
Vy='Vynír:BAACLgAFFH8WAAICAAYJyhsIFQCsAQACAAYJyhsIFQCsAQAuAAQKfy0AAwIACQmgIysHAA0DAAIACQk+IysHAA0DAAEABQkHI40NAOwBAAAA.',
Wa='Waghoba:BAECLgAFFH8gAAIgAAYJfRoQAQC/AQAgAAYJfRoQAQC/AQAuAAQKfyIAAiAACQnMIScGAJwCACAACQnMIScGAJwCAAAA.Waito:BAAALgAECgQJBwAAAA==.Wandä:BAABLgAECn8nAAQZAAkJhxsWCwBlAgAZAAkJnRoWCwBlAgAFAAgJrRHPHgCPAQAEAAEJtQ5kiQAtAAAAAA==.Wardriccan:BAAALgAECgUJCwAAAA==.Warfle:BAAALgADCgYJBgAAAA==.Warhound:BAAALgADCgcJBwAAAA==.Warrionomous:BAACLgAFFH8KAAIRAAQJSgztGwAeAQARAAQJSgztGwAeAQAuAAQKfxkAAhEACAkDG0AWABkCABEACAkDG0AWABkCAAAA.Washu:BAABLgAECn82AAMkAAkJFh0oBwCWAgAkAAkJFh0oBwCWAgAHAAMJTAtZIQB5AAAAAA==.',
Wh='Whimlock:BAAALgADCgQJBAABLgAFFAIJBQADAMQYAA==.Whims:BAAALgAECgYJCgABLgAFFAIJBQADAMQYAA==.Whimzie:BAAALgAECgEJAQABLgAFFAIJBQADAMQYAA==.Whorphium:BAAALgAECggJEgABLgAFFAYJFwAVAO8PAA==.',
Wi='Willow:BAAALgAECgYJCwAAAA==.Winterous:BAAALgAECgEJAwAAAA==.',
Wo='Wonderbread:BAABLgAECn80AAIGAAkJOxKYPwDpAQAGAAkJOxKYPwDpAQAAAA==.',
Wr='Wrager:BAAALgAECgUJBgAAAA==.Wrathofzaun:BAAALgAECgYJDwAAAA==.',
Wy='Wylest:BAAALgADCgcJBwAAAA==.Wynch:BAAALgAECgkJCAAAAA==.',
['Wâ']='Wârwôlf:BAABLgAECn8pAAMOAAkJHCTzAwA3AwAOAAkJHCTzAwA3AwALAAQJ+BWyVQDzAAAAAA==.',
Xe='Xenan:BAABLgAECn8rAAIGAAgJURC5ZACGAQAGAAgJURC5ZACGAQAAAA==.',
Xt='Xtrolldinary:BAAALgAECgQJDwAAAA==.',
Xv='Xvp:BAAALgAECgQJCgAAAA==.',
Xy='Xylophy:BAABLgAECn8pAAIHAAgJ/xQWCgCXAQAHAAgJ/xQWCgCXAQAAAA==.',
Ye='Yeastmode:BAACLgAFFH8OAAIOAAQJdwvwMgAXAQAOAAQJdwvwMgAXAQAuAAQKfycAAg4ACAkVHRseAEgCAA4ACAkVHRseAEgCAAAA.',
Yo='Yonah:BAAALgAECgYJDAAAAA==.',
Yu='Yurc:BAABLgAECn8eAAIeAAgJPhg5DwDMAQAeAAgJPhg5DwDMAQAAAA==.',
Za='Zademan:BAAALgAECgUJBwAAAA==.Zappyu:BAAALgAECgkJBQABLgAECgkJCAAKAAAAAA==.Zarkas:BAAALgAECgEJAQAAAA==.',
Ze='Zeebra:BAAALgAECgYJCgAAAA==.Zeg:BAAALgAECgQJBAAAAA==.Zega:BAAALgAECgEJAQAAAA==.Zegafur:BAABLgAECn8qAAIXAAgJ/RssIwAOAgAXAAgJ/RssIwAOAgAAAA==.Zeolite:BAAALgADCgEJAQAAAA==.Zeruk:BAABLgAECn8XAAMFAAcJjwJ1YACOAAAFAAYJlAJ1YACOAAAEAAcJpQGFagBzAAAAAA==.',
Zi='Zillionbúcks:BAACLgAFFH8aAAIGAAcJhxOOCADcAQAGAAcJhxOOCADcAQAuAAQKfxoAAgYACQn+HdEtAGwCAAYACQn+HdEtAGwCAAAA.',
Zy='Zylcat:BAAALgAECgYJDAAAAA==.',
['Zê']='Zêddicus:BAABLgAECn8wAAMBAAkJpSAYAQDNAgABAAkJpSAYAQDNAgACAAUJHwgM1ACyAAAAAA==.',
['Áq']='Áquafina:BAABLgAECn88AAIDAAkJpg4WSwDeAQADAAkJpg4WSwDeAQAAAA==.',
['Îv']='Îvan:BAAALgADCggJCAAAAA==.',
['Ðö']='Ðö:BAABLgAECn8nAAIRAAkJhBy5CwCKAgARAAkJhBy5CwCKAgAAAA==.',
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
