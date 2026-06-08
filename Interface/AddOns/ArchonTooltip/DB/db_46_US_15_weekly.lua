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

local lookup = {'Warlock-Destruction','Warlock-Demonology','Mage-Frost','Monk-Mistweaver','Monk-Windwalker','Paladin-Retribution','DemonHunter-Vengeance','Shaman-Restoration','Paladin-Holy','Unknown-Unknown','Shaman-Elemental','Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival','Evoker-Augmentation','DeathKnight-Unholy','DeathKnight-Frost','Warrior-Fury','Evoker-Devastation','Priest-Holy','DemonHunter-Devourer','Rogue-Subtlety','Warrior-Arms','Druid-Restoration','DeathKnight-Blood','Monk-Brewmaster','Druid-Guardian','Druid-Feral','Paladin-Protection','Priest-Discipline','Shaman-Enhancement','Evoker-Preservation','Warrior-Protection','Rogue-Outlaw','Druid-Balance','Mage-Fire','Warlock-Affliction','DemonHunter-Havoc','Priest-Shadow',}
local provider = {region='US',realm='Anvilmar',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aaril:BAAALgAECgQJGwAAAQ==.',
Ab='Abrams:BAAALgADCgYJCgAAAA==.',
Ad='Adel:BAAALgAECgYJCAAAAA==.',
Ae='Aelitha:BAABLgAECn8ZAAMBAAYJCQZ2OQDOAAABAAYJxAR2OQDOAAACAAYJsQTayQC2AAAAAA==.',
Ak='Akaishi:BAAALgADCgIJAgAAAA==.Akali:BAAALgAFFAIJAwAAAA==.Akina:BAAALgADCgYJBwABLgAECgkJKwADAIEOAA==.',
Al='Alanie:BAAALgAECgIJAgAAAA==.Alathiana:BAAALgADCgUJCAAAAA==.Alcweaver:BAABLgAECn8dAAMEAAcJgiBhHgASAgAEAAcJgiBhHgASAgAFAAYJgA8WPQD+AAAAAA==.Alecto:BAAALgAECgMJAwAAAA==.Alindia:BAAALgAECgQJCgABLgAECgkJKwADAIEOAA==.Alirrayia:BAAALgAECgQJBQAAAA==.Alirrayiia:BAACLgAFFH8IAAIGAAMJ+AGZewCfAAAGAAMJ+AGZewCfAAAuAAQKfyoAAgYACQlwFB4+AAICAAYACQlwFB4+AAICAAAA.Alkri:BAAALgADCgMJAwAAAA==.Allari:BAAALgAECgYJEwAAAA==.Allikazam:BAAALgADCgYJGAAAAA==.Allystar:BAAALgAECgQJDwAAAA==.Altheia:BAAALgAECgQJBAAAAA==.Alvidor:BAABLgAECn9CAAIDAAkJ/wUJhQBnAQADAAkJ/wUJhQBnAQAAAA==.',
Am='Ambrose:BAAALgAECgcJBwAAAA==.Ameria:BAAALgADCgUJBQAAAA==.Amexican:BAAALgAECgEJAQAAAA==.',
An='Anastos:BAAALgAECgUJBQAAAA==.Andydufresne:BAAALgAECgQJDgABLgAECgkJSgAHAKclAA==.Angryqueer:BAAALgADCgEJAQAAAA==.',
Ao='Aowl:BAAALgAECgcJCwAAAA==.',
Ap='Apocketheory:BAAALgADCgIJAgAAAA==.Apolloerosb:BAAALgAECgYJCwABLgAECgcJIAAIACEbAA==.Apolloerosp:BAAALgAECgEJAQABLgAECgcJIAAIACEbAA==.Apollossham:BAABLgAECn8gAAIIAAcJIRsjKAAQAgAIAAcJIRsjKAAQAgAAAA==.',
Ar='Arkanaun:BAABLgAECn8dAAMGAAYJRBdpcwCUAQAGAAYJRBdpcwCUAQAJAAUJvRRASgAIAQAAAA==.',
As='Ashes:BAAALgAECgcJAQAAAA==.Ashrán:BAAALgAECgYJCQAAAA==.Ashyluna:BAAALgAECgQJBAAAAA==.Astianna:BAAALgADCgMJAwAAAA==.',
Au='Aule:BAAALgAECgIJAwAAAA==.Aurinia:BAAALgADCgQJAgAAAA==.Auroradinlee:BAAALgAECgkJBgAAAA==.Aurore:BAAALgADCgQJBgAAAA==.',
Av='Avradea:BAAALgADCgEJAQABLgAECgkJKwADAIEOAA==.',
Az='Azareth:BAAALgADCggJCAAAAA==.',
Ba='Baconatorr:BAAALgAECgQJBQAAAA==.Bagelbags:BAAALgADCgEJAQAAAA==.Bahler:BAAALgADCgUJBQABLgAECgMJAwAKAAAAAA==.Baji:BAABLgAECn87AAMIAAkJLSIhBwAyAwAIAAkJLSIhBwAyAwALAAUJ/hXNRQAMAQAAAA==.Baklan:BAAALgAECgMJAwAAAA==.Barefaall:BAACLgAFFH8RAAIMAAcJExa1BwDeAQAMAAcJExa1BwDeAQAuAAQKf0QAAwwACQllJMkAAEMDAAwACQllJMkAAEMDAA0ABAmFEEmfAPMAAAAA.Barefall:BAACLgAFFH8GAAIOAAMJ3AU4IADBAAAOAAMJ3AU4IADBAAAuAAQKfxUAAg4ACQk4DzkVAPYBAA4ACQk4DzkVAPYBAAEuAAUUBwkRAAwAExYA.Barefalls:BAACLgAFFH8IAAIOAAMJlhzWGgDmAAAOAAMJlhzWGgDmAAAuAAQKfyUAAw4ACQkfHtwKAG0CAA4ACQkfHtwKAG0CAAwAAQmMAaCWACIAAAEuAAUUBwkRAAwAExYA.Barelywolf:BAABLgAECn8mAAMFAAkJwB9mEAA6AgAFAAcJ5CBmEAA6AgAEAAgJLxfpHwAIAgABLgAFFAMJBgAPACwLAA==.Bashira:BAABLgAECn8eAAINAAkJsApHUgCfAQANAAkJsApHUgCfAQAAAA==.Bast:BAABLgAECn8vAAMQAAkJRxZULwA5AgAQAAkJRxZULwA5AgARAAQJiQ1KJQCQAAAAAA==.Bastienne:BAAALgAECgQJCgAAAA==.Bastrillan:BAAALgAECgUJBwAAAA==.',
Be='Bearophe:BAAALgAECgEJAgAAAA==.Beerfist:BAAALgAECgEJAQAAAA==.Belfor:BAAALgAECgMJAwAAAA==.Bellock:BAAALgAECgMJAwAAAA==.Bendroyd:BAAALgAECgIJAgAAAA==.Benisbagina:BAAALgADCggJCQAAAA==.Bergonator:BAABLgAECn8gAAISAAYJcRC9TwBpAQASAAYJcRC9TwBpAQAAAA==.Berrodiah:BAAALgAECgYJCAABLgAECggJFgATALUYAA==.Bettyswalls:BAAALgAECgMJAwAAAA==.Beyarago:BAAALgAECgUJCQAAAA==.',
Bh='Bheiroth:BAABLgAECn8wAAIUAAkJSCQBBAA/AwAUAAkJSCQBBAA/AwAAAA==.',
Bi='Birds:BAAALgAECgkJEQAAAA==.',
Bl='Bladeygaga:BAABLgAECn85AAIVAAkJpR+0CgDrAgAVAAkJpR+0CgDrAgAAAA==.Blasé:BAAALgAECgcJCAAAAA==.Blazingblood:BAAALgADCgUJAQAAAA==.Bloodknight:BAAALgADCgYJCQAAAA==.Bluekrayen:BAAALgAECgUJCAAAAA==.Bluett:BAAALgAECgMJCQAAAA==.Bláckøut:BAAALgADCgYJDAAAAA==.',
Bo='Bodhi:BAABLgAECn8WAAIWAAcJNhAQJwDAAQAWAAcJNhAQJwDAAQAAAA==.Bogertus:BAACLgAFFH8QAAISAAMJgCQNHgAsAQASAAMJgCQNHgAsAQAuAAQKf0AAAxIACQnSJlwAAJIDABIACQnSJlwAAJIDABcAAgn1HHIpAKUAAAAA.Bonobo:BAAALgAECgYJCQAAAA==.Boomertunes:BAABLgAECn8mAAMCAAkJYxgbJABJAgACAAkJYxgbJABJAgABAAIJGwHdTwAAAAAAAA==.',
Br='Brein:BAABLgAECn9EAAIYAAkJ8yWcAADiAwAYAAkJ8yWcAADiAwAAAA==.Brewmaster:BAAALgAECgIJAwAAAA==.Brewwmaster:BAABLgAECn8kAAQZAAkJrBjtFQCwAQAZAAkJIBXtFQCwAQAQAAYJtBfWfACKAQARAAEJ+he5FgA2AAAAAA==.Bricklethumb:BAAALgAECgMJAwABLgAECgYJEgAKAAAAAA==.Brickred:BAAALgADCggJDgAAAA==.Brynodd:BAAALgAECgMJCQAAAA==.',
Bu='Bubblybetty:BAAALgAECgEJAQAAAA==.Bucketeer:BAABLgAECn8rAAIDAAkJUR9RGgC2AgADAAkJUR9RGgC2AgAAAA==.Buffs:BAAALgADCgEJAQAAAA==.Bullminator:BAAALgAECggJDQAAAA==.Bursona:BAAALgAECgEJAQAAAA==.Butterfree:BAAALgAECgUJDAABLgAFFAEJAQAKAAAAAA==.',
Ca='Cards:BAAALgAECgYJCgAAAA==.Carkrash:BAAALgADCgkJFwAAAA==.Casterkang:BAAALgAECgUJCQAAAA==.Catshunter:BAABLgAECn8UAAINAAYJvRwyQACvAQANAAYJvRwyQACvAQAAAA==.',
Ce='Celaa:BAABLgAECn8rAAIDAAkJgQ6UWADNAQADAAkJgQ6UWADNAQAAAA==.',
Ch='Chanka:BAABLgAECn8WAAIBAAYJVQh5HAC4AAABAAYJVQh5HAC4AAAAAA==.Chantillary:BAAALgAECgMJCQAAAA==.Chargerkang:BAAALgADCgYJBgAAAA==.Chchanges:BAAALgAECgEJAQAAAA==.Cheesy:BAABLgAECn8qAAICAAgJFA23ZgBrAQACAAgJFA23ZgBrAQAAAA==.Chicken:BAAALgAECgYJEgAAAA==.Chonk:BAAALgADCgEJAQAAAA==.Chopzullee:BAABLgAECn8ZAAIFAAYJ6QkyWQCfAAAFAAYJ6QkyWQCfAAAAAA==.',
Ci='Cirya:BAAALgAECgUJCQAAAA==.',
Cl='Cleric:BAAALgADCgUJBQAAAA==.Clortho:BAAALgAECgQJCQAAAA==.Clorthö:BAAALgADCgUJBQAAAA==.',
Co='Coljack:BAAALgAECggJCAAAAA==.Colljack:BAACLgAFFH8cAAIJAAYJAhpyBwBdAQAJAAYJAhpyBwBdAQAuAAQKfyEAAwkACQkgIZwJANgCAAkACQkgIZwJANgCAAYABQlOEtO5ABIBAAAA.Coughlin:BAAALgAECgEJAQAAAA==.',
Cr='Crocbait:BAAALgAECgcJEQAAAA==.Cryptoe:BAABLgAECn8eAAIDAAkJzRMlRgADAgADAAkJzRMlRgADAgAAAA==.',
Cu='Cudlsac:BAAALgAECgQJBQAAAA==.',
Da='Daedelus:BAABLgAECn8XAAMVAAgJlBNldQAqAQAVAAgJlBNldQAqAQAHAAUJfg3CGwCvAAAAAA==.Daglon:BAAALgAECggJDAABLgAFFAEJAQAKAAAAAA==.Dagz:BAAALgAECgQJBAAAAA==.Dakina:BAAALgADCgYJBgAAAA==.Daraedra:BAAALgAECgYJBgAAAA==.Darkenvoid:BAAALgADCgkJDQAAAA==.',
De='Deathslight:BAAALgAECgQJBwAAAA==.Deeznutticus:BAACLgAFFH8bAAISAAYJKhbjDQCDAQASAAYJKhbjDQCDAQAuAAQKfyEAAxIABwnCIkgYAIkCABIABwnCIkgYAIkCABcAAgkBHcxWAGoAAAAA.Defnotisis:BAABLgAECn8dAAMaAAgJhxQ2JwBuAQAaAAcJCRY2JwBuAQAFAAgJtAuuQADvAAABLgAFFAIJAwAKAAAAAA==.Defnotkity:BAABLgAFFH8FAAMbAAMJVQ2LJgBmAAAcAAIJ2Qd5FAB6AAAbAAIJiA+LJgBmAAAAAA==.Demonspud:BAABLgAECn8dAAIVAAcJhRJWYQBaAQAVAAcJhRJWYQBaAQAAAA==.Demotard:BAAALgAECgIJAQAAAA==.Denxster:BAAALgAECgYJDgAAAA==.Dersan:BAABLgAECn8gAAIBAAgJ1AB/OgA2AAABAAgJ1AB/OgA2AAAAAA==.Destriant:BAABLgAECn83AAIdAAkJyxmoCQAnAgAdAAkJyxmoCQAnAgAAAA==.Devilschant:BAAALgAECgYJCgAAAA==.Devilshadow:BAAALgAECgUJBwABLgAECgYJCgAKAAAAAA==.Dewburt:BAAALgADCggJCgAAAA==.Deylia:BAAALgAECgYJCwABLgAFFAUJHAAeAO8XAA==.',
Di='Dilithia:BAABLgAECn8VAAIQAAYJqwIkBgGVAAAQAAYJqwIkBgGVAAAAAA==.Dillion:BAAALgAECgYJCAAAAA==.Dinonuggies:BAAALgADCgcJBwAAAA==.Dionin:BAAALgADCgYJCQAAAA==.Dira:BAAALgAFFAIJAgABLgAFFAYJHQAfAK4gAA==.Dirkbanne:BAAALgADCgYJBgAAAA==.',
Do='Dodoubleg:BAAALgAECgYJEAAAAA==.Dominique:BAAALgADCgYJBgAAAA==.Donzilch:BAEALgAECgQJBAAAAA==.Donzilly:BAAALgAECgUJBQAAAA==.Dooburt:BAAALgAECggJDAAAAA==.Doombringers:BAAALgAECgUJBQAAAA==.',
Dr='Dracaric:BAABLgAECn8qAAIPAAkJEhZmFwAVAgAPAAkJEhZmFwAVAgAAAA==.Draeca:BAAALgAECgMJBgAAAA==.Dragondznut:BAAALgAECgQJBQAAAA==.Drakhar:BAAALgADCgIJAgABLgAECgYJCwAKAAAAAA==.Drfrostie:BAAALgAECgcJEgAAAA==.Drgunner:BAAALgAECgcJDwAAAA==.Driatin:BAAALgAFFAEJAQAAAA==.Drkladykikyo:BAABLgAECn8XAAIUAAkJFQN9PgDnAAAUAAkJFQN9PgDnAAAAAA==.Druroo:BAAALgAECgEJAQABLgAFFAQJBwAQADUWAA==.Druterr:BAAALgAECgIJAgABLgAECgcJBwAKAAAAAA==.',
Du='Dumb:BAACLgAFFH8PAAIgAAUJLAyTBgCJAQAgAAUJLAyTBgCJAQAuAAQKfyMAAiAACAnoG28LAH4CACAACAnoG28LAH4CAAAA.Durø:BAABLgAECn8WAAIVAAgJryLZDAAZAwAVAAgJryLZDAAZAwAAAA==.Duskhunter:BAAALgADCgEJAQAAAA==.',
Dy='Dyanisian:BAAALgADCgYJCAAAAA==.',
['Dè']='Dègenerate:BAABLgAECn9CAAIhAAkJjiDfAwDmAgAhAAkJjiDfAwDmAgAAAA==.',
Ed='Edagerran:BAAALgADCgkJCQAAAA==.',
Ei='Eilae:BAABLgAECn8WAAINAAYJIgSDsQDPAAANAAYJIgSDsQDPAAAAAA==.Eirhakan:BAAALgAECgQJCAAAAA==.',
El='Elrethyl:BAABLgAECn8WAAIGAAcJXhiRcACCAQAGAAcJXhiRcACCAQAAAA==.Elvanus:BAAALgADCgYJBgAAAA==.Elêktra:BAABLgAECn8sAAILAAkJuA4zMABwAQALAAkJuA4zMABwAQAAAA==.',
Em='Emet:BAAALgAECgQJBAABLgAECgkJQAALAEMcAA==.',
Ep='Epicnym:BAAALgAECgEJAQAAAA==.Epicsmoke:BAACLgAFFH8LAAISAAMJCxVeLADqAAASAAMJCxVeLADqAAAuAAQKf04AAhIACQkPJb8BAFwDABIACQkPJb8BAFwDAAAA.Epidemius:BAAALgAECgkJCgAAAA==.',
Er='Erevan:BAABLgAECn84AAMWAAkJ3BveBwCeAgAWAAkJ3BveBwCeAgAiAAEJpwABEAAcAAAAAA==.Erinn:BAAALgAECgIJAgAAAA==.Eroica:BAAALgADCgYJBwAAAA==.Eronys:BAAALgAFFAIJAQAAAA==.',
Es='Esdeath:BAABLgAECn8rAAMQAAkJ5hONSADhAQAQAAkJ5hONSADhAQAZAAYJWgbIOgCcAAAAAA==.',
Et='Etharia:BAAALgADCgUJAwAAAA==.',
Ev='Evilsmeghead:BAAALgADCgEJAQAAAA==.',
Ex='Exiledguy:BAAALgADCgYJBgAAAA==.Extenze:BAABLgAECn8oAAIVAAkJXx16GAB4AgAVAAkJXx16GAB4AgAAAA==.',
Ez='Ezykiah:BAAALgAECgEJAQAAAA==.',
Fa='Falconponch:BAAALgADCgEJAQAAAA==.',
Fe='Felbjorn:BAAALgAECgEJAgAAAA==.Felgibson:BAAALgAECgQJBQAAAA==.Felkang:BAAALgADCgkJCQAAAA==.Ferryman:BAAALgAECgYJEQAAAA==.',
Fl='Flingor:BAAALgAECgYJEAAAAA==.Flokha:BAAALgADCgEJAQAAAA==.',
Fo='Forphium:BAACLgAFFH8bAAIWAAcJwQ6lBACkAQAWAAcJwQ6lBACkAQAuAAQKfyAAAhYACQn9IH0NAMQCABYACQn9IH0NAMQCAAAA.',
Fr='Fredolf:BAAALgAECgEJAQAAAA==.Freydís:BAAALgAECgUJCwAAAA==.Freyå:BAAALgAECgIJAgAAAA==.Friarkuck:BAAALgADCggJCAAAAA==.Friedbones:BAAALgAECgMJCQAAAA==.Frostlilliy:BAAALgADCggJCwAAAA==.',
['Fü']='Fürbie:BAAALgAECgIJAwAAAA==.',
Ga='Gahlina:BAABLgAECn8UAAMIAAcJtBb2LwDnAQAIAAcJtBb2LwDnAQALAAEJ1wEzlgAeAAAAAA==.Galdorian:BAAALgADCgYJCQABLgAECgkJHgANALAKAA==.Galynda:BAAALgADCgcJCQAAAA==.',
Ge='Genjimain:BAABLgAECn8lAAMYAAkJBhqRHgBKAgAYAAkJBhqRHgBKAgAcAAMJ9wwXMQCIAAAAAA==.Genjí:BAAALgAECgEJAwAAAA==.Geris:BAAALgAECgQJBQAAAA==.Gertruide:BAAALgADCgUJBQAAAA==.',
Gh='Ghendala:BAAALgADCggJEwAAAA==.',
Gi='Gillesmon:BAAALgAFFAEJAQAAAA==.Gilleyy:BAAALgAECgEJAQABLgAECgYJFAATAJodAA==.Gincainn:BAAALgAECgEJAgAAAA==.Gird:BAABLgAECn8oAAIJAAgJ4Q1XNgBsAQAJAAgJ4Q1XNgBsAQAAAA==.Girdlock:BAAALgAECgYJBwAAAA==.',
Gl='Glaiveyjones:BAAALgAECgEJAQAAAA==.',
Gn='Gnymesis:BAAALgAECgEJAgAAAA==.',
Go='Goatmonger:BAAALgAECgYJBgAAAA==.Goinpostal:BAAALgAECgIJAgAAAA==.Goldblade:BAAALgAECgkJEwAAAA==.Goodvsevil:BAAALgAECgQJBAAAAA==.Gordek:BAABLgAECn8dAAMGAAkJsRqyKQBQAgAGAAkJsRqyKQBQAgAJAAIJhBBBcwBfAAAAAA==.Gothitelle:BAAALgAECgIJBwAAAA==.Goöse:BAACLgAFFH8ZAAIQAAYJJh7dAwDEAQAQAAYJJh7dAwDEAQAuAAQKfycAAhAACAmDJusGAGsDABAACAmDJusGAGsDAAAA.',
Gr='Grantaron:BAABLgAECn83AAIGAAkJ2iBlFgCzAgAGAAkJ2iBlFgCzAgAAAA==.Gravarii:BAAALgADCgcJEwAAAA==.Grimskul:BAABLgAECn8zAAMQAAkJkB2ZGACrAgAQAAkJkB2ZGACrAgARAAYJDxSUBwCBAQAAAA==.Grindor:BAAALgADCgEJAQAAAA==.Grntitan:BAAALgAECgQJCgAAAA==.Gruid:BAAALgADCgcJDwAAAA==.',
Gu='Guinessbrew:BAAALgAECgEJAQAAAA==.',
Gw='Gwoohoori:BAAALgAECggJEwAAAA==.',
Gy='Gyra:BAAALgAECgYJEQAAAA==.Gyrojetli:BAAALgAECgQJBQAAAA==.',
Ha='Halukari:BAABLgAECn8VAAMbAAYJXiCICwDYAQAbAAYJXiCICwDYAQAjAAEJ8gzahgApAAABLgAFFAUJHAAeAO8XAA==.Harfnan:BAAALgAECgIJAgAAAA==.Harrin:BAABLgAECn8dAAIDAAcJ9g/HmgA/AQADAAcJ9g/HmgA/AQAAAA==.',
He='Healingwater:BAAALgAECgIJAwAAAA==.Herracles:BAAALgADCgYJGAAAAA==.Hezrel:BAAALgAECgYJCgAAAA==.',
Hi='Hierodule:BAAALgAECgEJAQAAAA==.Hiimriven:BAAALgAECgIJAgABLgAECgYJFgAWAFkhAA==.Hinal:BAABLgAECn8gAAIGAAkJMhstJQBlAgAGAAkJMhstJQBlAgAAAA==.',
Ho='Hojo:BAAALgADCgUJCAAAAA==.Holyenabler:BAABLgAFFH8OAAIdAAMJqQqoDQCTAAAdAAMJqQqoDQCTAAAAAA==.Hootiehoo:BAAALgADCgMJAwAAAA==.',
Hu='Huflunggoo:BAAALgADCgkJDQAAAA==.Huflungpoop:BAABLgAECn80AAIFAAkJqBpCEAA8AgAFAAkJqBpCEAA8AgAAAA==.Hunterborn:BAAALgAFFAIJAgAAAA==.',
Hy='Hypercube:BAAALgAECgQJBwAAAA==.',
['Hè']='Hèalz:BAAALgAECgYJBQABLgAECgkJLwASAMAdAA==.',
Ic='Ickixia:BAAALgADCgQJBAAAAA==.',
Il='Ilkaressa:BAAALgADCgQJBAAAAA==.Illyríá:BAEBLgAFFH8JAAICAAMJQxGAagDdAAACAAMJQxGAagDdAAABLgAECgkJLwABADobAA==.Ilun:BAAALgAECgIJAgAAAA==.',
Im='Imcruel:BAACLgAFFH8YAAMDAAcJChjCGQAIAgADAAcJChjCGQAIAgAkAAIJLxETBACEAAAuAAQKfzAAAgMACQnNJbEGAEcDAAMACQnNJbEGAEcDAAAA.Ims:BAAALgAECggJBQAAAA==.',
In='Ink:BAACLgAFFH8NAAIDAAQJKxGmWAAuAQADAAQJKxGmWAAuAQAuAAQKfycAAgMABwm2IJ1WANIBAAMABwm2IJ1WANIBAAAA.',
Is='Istaria:BAAALgAECgMJCAAAAA==.Isujr:BAABLgAECn8ZAAIQAAcJ8hIKcQCmAQAQAAcJ8hIKcQCmAQAAAA==.',
Ja='Jacaerys:BAAALgADCgYJBgAAAA==.Jackiegan:BAABLgAECn8kAAQaAAkJOh4KCACrAgAaAAkJDB4KCACrAgAFAAEJahFthgBCAAAEAAEJJgeuvgAeAAAAAA==.Jackson:BAAALgAECgMJCQAAAA==.Jagerdemon:BAAALgAECgcJBwAAAA==.',
Je='Jerce:BAAALgADCgUJBQAAAA==.Jeryatric:BAAALgADCgcJBwAAAA==.',
Jh='Jhala:BAAALgADCgkJDwAAAA==.',
Ji='Jinnxx:BAAALgAECgMJBAABLgAFFAYJHQAfAK4gAA==.',
Jo='Joshcalc:BAAALgAFFAIJAwAAAA==.Joskel:BAABLgAECn8vAAQCAAgJDw1CbABeAQACAAgJiQxCbABeAQAlAAYJMQToFgDIAAABAAIJNgxFLgBZAAAAAA==.',
Ju='Juacqer:BAAALgAECgMJCQAAAA==.Juggarnaut:BAAALgADCgYJCAAAAA==.',
Ka='Kaant:BAABLgAECn9AAAMLAAkJQxzbEQBWAgALAAgJ7R3bEQBWAgAIAAgJOhU7NADTAQAAAA==.Kaeni:BAAALgADCgMJAwAAAA==.Kaidevyn:BAABLgAECn8yAAMRAAkJmhMXCQDlAQARAAkJmhMXCQDlAQAQAAQJWgohCQGRAAAAAA==.Kaiste:BAAALgADCgEJAQAAAA==.Kaleine:BAAALgAECgYJCAAAAA==.Kardren:BAAALgAECgUJDAAAAA==.Kat:BAAALgAECgMJAwAAAA==.',
Ke='Keiko:BAAALgAECggJDwAAAA==.Keiran:BAABLgAECn81AAMNAAkJ4yLeCAAKAwANAAkJ4yLeCAAKAwAMAAgJpRzPEgCgAgAAAA==.Kelazurin:BAAALgADCgEJAQAAAA==.Kellistair:BAAALgADCgYJBgAAAA==.Keläo:BAAALgADCgUJCQAAAA==.Kenshii:BAAALgAECgUJBQAAAA==.Keyadish:BAAALgADCgYJDQAAAA==.Keys:BAACLgAFFH8HAAIWAAMJlhXEJQDkAAAWAAMJlhXEJQDkAAAuAAQKfyYAAhYACAkTHrkQAJwCABYACAkTHrkQAJwCAAAA.',
Kh='Khalnerys:BAABLgAECn8kAAMPAAgJGgoTRAAOAQAPAAgJJggTRAAOAQATAAUJeAk0FQCyAAAAAA==.Khitt:BAAALgAECgEJAQABLgAECgMJCAAKAAAAAA==.Khoulock:BAACLgAFFH8TAAICAAcJlhBoKgB/AQACAAcJlhBoKgB/AQAuAAQKfzUABAIACQnKIMUOANECAAIACQm6IMUOANECACUABQliIgESADYBAAEAAwl9ENU+ALkAAAAA.',
Ki='Kimmi:BAABLgAECn8ZAAMBAAkJKQWXFQDuAAABAAkJKQWXFQDuAAACAAIJ1gBEWAEUAAAAAA==.Kimmispally:BAAALgAECgQJBQAAAA==.Kiro:BAAALgADCgQJBQAAAA==.',
Kn='Knowimsayin:BAAALgAECgEJAQAAAA==.',
Ko='Kota:BAAALgAECgEJAQAAAA==.Kotateal:BAAALgAECgYJCwAAAA==.',
Kr='Kruelshot:BAACLgAFFH8OAAMNAAQJMiPrFgCUAQANAAQJMiPrFgCUAQAOAAEJiwsILgBLAAAuAAQKfxYAAw0ACAnFJD8QAMUCAA0ACAnFJD8QAMUCAAwABwlqEgAyAKgBAAEuAAUUBwkYAAMAChgA.Krux:BAAALgAECgEJAQAAAA==.',
Kt='Kthxbye:BAAALgAECgUJBwABLgAECgcJBwAKAAAAAA==.',
Ku='Kumcookies:BAAALgADCgEJAQAAAA==.Kungfuprissy:BAAALgAECgMJBwAAAA==.Kuraishin:BAACLgAFFH8SAAIcAAMJGB6ACgD4AAAcAAMJGB6ACgD4AAAuAAQKf3sAAxsACAl0JNoEALgCABsACAnnItoEALgCABwABwkMIygHAFkCAAEuAAUUBAkWABAA4gsA.Kuroakuma:BAAALgAECgYJEAAAAA==.Kuvara:BAAALgADCgkJCgAAAA==.',
Kv='Kvnnp:BAAALgADCgYJBgAAAA==.Kvnpro:BAAALgADCgUJBwAAAA==.Kvnxx:BAAALgADCgUJBQAAAA==.',
Kw='Kwandashadow:BAAALgAECgUJDgAAAA==.',
Ky='Kylemonk:BAAALgADCgEJAQAAAA==.',
['Ké']='Kéres:BAAALgADCgkJEAAAAA==.',
La='Lagspike:BAABLgAECn8gAAIDAAgJqBVTlgCnAQADAAgJqBVTlgCnAQAAAA==.Latheal:BAAALgAECgMJBAAAAA==.Latto:BAAALgAFFAIJAgABLgAFFAIJAwAKAAAAAA==.Lavi:BAABLgAECn8dAAIGAAgJDA42iABUAQAGAAgJDA42iABUAQAAAA==.',
Lb='Lbk:BAAALgADCgIJAgAAAA==.',
Le='Lejeune:BAAALgAECgMJCQAAAA==.Lengex:BAAALgAECggJDAAAAA==.Lero:BAABLgAECn8iAAIaAAkJuCH7BADsAgAaAAkJuCH7BADsAgAAAA==.Lerwindion:BAABLgAECn8qAAIeAAkJYx2VCQCiAgAeAAkJYx2VCQCiAgABLgAFFAQJBwAQADUWAA==.Lescaryn:BAAALgADCgIJAgAAAA==.Lexoh:BAAALgAECgYJEgAAAA==.',
Li='Lilani:BAAALgADCgQJBAAAAA==.Lindir:BAACLgAFFH8OAAIOAAUJ3RreDgBAAQAOAAUJ3RreDgBAAQAuAAQKfykAAg4ACAlGJKkBAD8DAA4ACAlGJKkBAD8DAAAA.Lionelle:BAAALgAECgYJDgAAAA==.Liq:BAAALgAECgMJAwABLgAFFAYJHQAVAL0cAA==.Liquor:BAACLgAFFH8dAAIVAAYJvRxvHwCcAQAVAAYJvRxvHwCcAQAuAAQKf1AAAxUACQmJIW8KAO0CABUACQmJIW8KAO0CAAcAAwnPFOkeAJYAAAAA.Liquorish:BAAALgAECgEJAQABLgAFFAYJHQAVAL0cAA==.Lirathiel:BAABLgAECn8UAAMdAAcJiAQPOgBoAAAGAAQJfgP+JgF4AAAdAAUJsgQPOgBoAAAAAA==.Litasfk:BAAALgAECgIJAgAAAA==.Liuni:BAABLgAECn8nAAIaAAkJlRQkHgCsAQAaAAkJlRQkHgCsAQAAAA==.Liyin:BAAALgAECgQJCQABLgAECgkJKwADAIEOAA==.',
Lo='Lobopeste:BAABLgAECn9CAAIZAAkJBgsmIABHAQAZAAkJBgsmIABHAQAAAA==.Locknutz:BAAALgADCgMJAwAAAA==.Loracy:BAAALgADCgcJBwAAAA==.Lorantell:BAAALgAECgMJAwAAAA==.Lorelynn:BAABLgAECn8qAAICAAkJUQ1cUQCiAQACAAkJUQ1cUQCiAQAAAA==.',
Lu='Luci:BAABLgAECn8YAAQVAAgJ6RKlTACTAQAVAAgJkxKlTACTAQAHAAMJ1Q7aLABDAAAmAAEJAACvfQAAAAABLgAFFAIJAwAKAAAAAA==.Lucìan:BAABLgAECn8lAAIYAAgJiCEjDAD2AgAYAAgJiCEjDAD2AgAAAA==.Ludociel:BAAALgAECgQJBAAAAA==.Lunaclair:BAACLgAFFH8WAAIQAAQJ4gt8cAASAQAQAAQJ4gt8cAASAQAuAAQKf2EAAxAACQkoHdglAGMCABAACQkoHdglAGMCABkABwmNEEYoAAkBAAAA.Lunadrus:BAABLgAECn8mAAIDAAgJoglrrQAhAQADAAgJoglrrQAhAQAAAA==.Lunarielle:BAACLgAFFH8YAAINAAQJ8BUFMABCAQANAAQJ8BUFMABCAQAuAAQKfyEAAg0ACAkXHMYVAIkCAA0ACAkXHMYVAIkCAAAA.',
Ly='Lyriaa:BAAALgADCgYJCwAAAA==.',
Ma='Macalatraz:BAAALgAECgMJBwAAAA==.Macfly:BAABLgAECn8yAAINAAkJrRoXJgA9AgANAAkJrRoXJgA9AgAAAA==.Madmeatballs:BAAALgAECgEJAQABLgAECgkJKwADAFEfAA==.Magdala:BAAALgADCgEJAQAAAA==.Magicmissile:BAACLgAFFH8PAAIDAAUJqxEhVAA0AQADAAUJqxEhVAA0AQAuAAQKfyoAAgMACQlqH7cVANACAAMACQlqH7cVANACAAAA.Makgora:BAAALgAECgMJBAABLgAECgYJFgAWAFkhAA==.Makhvan:BAAALgAFFAEJAQAAAA==.Maksoon:BAAALgAFFAIJAwAAAA==.Maladjusted:BAAALgAECgMJBAAAAA==.Maléfique:BAAALgAECgEJAQAAAA==.Mancath:BAAALgAECgkJCwAAAA==.Maplè:BAAALgAECgIJAwABLgAECggJIwAIAKITAA==.Mar:BAAALgADCgMJAwAAAA==.Marlei:BAAALgADCgQJBAABLgAECgkJKwADAIEOAA==.Marqose:BAAALgADCgcJDgABLgAECgMJBgAKAAAAAA==.Matan:BAAALgADCgUJBQAAAA==.',
Me='Meeko:BAAALgAFFAIJBAABLgAFFAgJGwAgAPggAA==.Melfie:BAABLgAECn8qAAIDAAkJTxorJgB9AgADAAkJTxorJgB9AgAAAA==.Meliadoul:BAABLgAECn8dAAIDAAgJ7ws6iQBeAQADAAgJ7ws6iQBeAQAAAA==.Mellyndra:BAABLgAECn88AAIJAAkJ3x4wCQDtAgAJAAkJ3x4wCQDtAgAAAA==.Mercüry:BAAALgAECgEJBAAAAA==.Mezhren:BAAALgAECgYJCwAAAA==.',
Mh='Mhoramsgirl:BAAALgADCggJCwAAAA==.',
Mi='Midoriya:BAACLgAFFH8IAAMFAAMJHQebJgCsAAAFAAMJHQebJgCsAAAEAAMJyQvYOwCUAAAuAAQKfyMAAwUACQlnEQstAEsBAAUACAkvEgstAEsBAAQABQmQEXJ4AJQAAAAA.Mistjack:BAABLgAFFH8LAAIEAAUJthGDIgAqAQAEAAUJthGDIgAqAQAAAA==.',
Mo='Momdad:BAACLgAFFH8SAAIOAAUJ6xczEQAxAQAOAAUJ6xczEQAxAQAuAAQKfzQAAg4ACQnWIBEHAKoCAA4ACQnWIBEHAKoCAAAA.Mongaux:BAAALgADCgQJBQAAAA==.Monkey:BAAALgAECgQJCgAAAA==.Morrígán:BAAALgADCgUJBQAAAA==.Moxi:BAAALgADCggJDwAAAA==.',
Mu='Muamman:BAAALgAECgMJAwAAAA==.Murda:BAAALgADCgYJCgAAAA==.Murphysflaw:BAAALgADCgUJCAAAAA==.Mutegen:BAAALgAFFAEJAQAAAA==.',
Mx='Mxhealeryduf:BAAALgAECgIJAgAAAA==.',
My='Mystallian:BAAALgAECgQJCQAAAA==.Mystí:BAEALgAECgkJBgABLgAECgkJLwABADobAA==.Mythicplus:BAAALgAECgcJEQAAAA==.Mythosaur:BAAALgADCgEJAQAAAA==.',
['Mé']='Mémnoc:BAAALgAECgMJAwAAAA==.',
Na='Nadarien:BAAALgAECgYJDQAAAA==.Nadyia:BAAALgADCgEJAQAAAA==.Nailah:BAAALgADCgcJCwAAAA==.Nannergoat:BAAALgADCgMJAwAAAA==.Nardssenpai:BAAALgAECgIJAwAAAA==.Nastymikey:BAABLgAECn8bAAIfAAgJNx13BwBzAgAfAAgJNx13BwBzAgAAAA==.Nazdormu:BAABLgAECn8gAAIgAAgJIQSzHQADAQAgAAgJIQSzHQADAQAAAA==.',
Ne='Nefarious:BAAALgAECgcJDgAAAA==.Neisen:BAABLgAECn8yAAMJAAkJ9RcNEACOAgAJAAkJ9RcNEACOAgAGAAUJBwKc+gCeAAAAAA==.Neptune:BAAALgADCgYJBgAAAA==.',
No='Norna:BAAALgADCgcJDwAAAA==.Noz:BAAALgADCgkJCQAAAA==.',
Nu='Nufonewhodis:BAABLgAECn8WAAIWAAYJWSF1HQATAgAWAAYJWSF1HQATAgAAAA==.',
Ny='Nykolas:BAAALgAECgEJAQAAAA==.Nymofthedead:BAABLgAECn8vAAMQAAkJQiR1BQBLAwAQAAkJQiR1BQBLAwARAAUJyBOOGAD+AAAAAA==.',
Oa='Oakgrove:BAAALgADCgUJBQAAAA==.',
Om='Ombraless:BAAALgADCgMJAwABLgAECgQJCAAKAAAAAA==.',
On='Oneforall:BAAALgAECgkJDgAAAA==.',
Op='Ophrizhani:BAAALgAECgMJAwAAAA==.',
Or='Orangegrove:BAAALgAECgYJBQAAAA==.Orpheal:BAAALgAECgUJBQAAAA==.Orphen:BAAALgAECgMJAwAAAA==.',
Os='Osìrìs:BAAALgAECgQJCAABLgAECggJJQAYAIghAA==.',
Pa='Paddleball:BAAALgADCgQJBAAAAA==.Paladouin:BAAALgAECgYJEwAAAA==.Pandammy:BAAALgAECgkJBQAAAA==.Pantro:BAABLgAECn8eAAMcAAkJRRe/CAAtAgAcAAkJRRe/CAAtAgAbAAEJAAAQhgAAAAAAAA==.Papalion:BAABLgAECn8YAAINAAYJugxQmgD9AAANAAYJugxQmgD9AAAAAA==.Paragas:BAAALgADCgkJEAAAAA==.Pawbs:BAAALgAECgQJEwAAAA==.',
Pe='Peanuts:BAAALgADCgcJBwAAAA==.Peoplehugger:BAAALgADCgMJAwAAAA==.',
Pi='Pickleburger:BAAALgAECgEJAQAAAA==.Pinkkrayen:BAAALgADCgIJAgAAAA==.Pinklilydrd:BAAALgAECgMJCQAAAA==.',
Pl='Plaindonut:BAAALgAECgcJEwAAAA==.',
Po='Porple:BAAALgAECgcJCQAAAA==.',
Pr='Priestdrago:BAAALgADCgUJBQAAAA==.Prissidebow:BAAALgAECgMJCQAAAA==.',
Qu='Quartz:BAAALgAFFAEJAQABLgAFFAMJEAASAIAkAA==.',
Ra='Rahzule:BAAALgADCgYJBwAAAA==.Ralynne:BAACLgAFFH8HAAILAAMJwA0mMQC8AAALAAMJwA0mMQC8AAAuAAQKfy4AAgsACAkzFJMqAI8BAAsACAkzFJMqAI8BAAAA.Raskus:BAAALgADCgEJAQAAAA==.Ravenbrook:BAACLgAFFH8ZAAISAAUJaSaQBwDFAQASAAUJaSaQBwDFAQAuAAQKfyMAAxIACAlbJXsEAGIDABIACAlbJXsEAGIDABcAAQkwIH1gAFMAAAAA.Rawrr:BAABLgAECn8hAAImAAgJXAt5JgAzAQAmAAgJXAt5JgAzAQAAAA==.Rawrxd:BAAALgAECgEJAgABLgAECggJDgAKAAAAAA==.Raxie:BAACLgAFFH8cAAMeAAUJ7xcCGQB8AQAeAAUJ7xcCGQB8AQAnAAEJBQ3SFABRAAAuAAQKfy0ABB4ACQnXGqMNAIgCAB4ACQnXGqMNAIgCACcABwnIE9orAG8BABQAAQkBBPGHACgAAAAA.Razeth:BAABLgAECn8VAAIOAAYJ8BYYLAA+AQAOAAYJ8BYYLAA+AQAAAA==.',
Re='Reanne:BAAALgAECgYJEAAAAA==.Rebecka:BAAALgAECgEJAQAAAA==.Res:BAAALgAECgYJCwAAAA==.Rescorla:BAAALgAECgkJDAAAAA==.Rethali:BAAALgADCgQJAgAAAA==.Reysola:BAAALgAECgEJAQABLgAECgIJAgAKAAAAAA==.Rezr:BAAALgAECggJDgAAAA==.',
Rh='Rhixa:BAAALgADCgUJBQAAAA==.Rhymunky:BAAALgAECgYJEQAAAA==.',
Ri='Rifthor:BAABLgAECn8WAAQcAAYJYAwQKgCvAAAcAAUJwwsQKgCvAAAbAAMJKQ8sQwCEAAAYAAIJsAJJ3AAmAAAAAA==.Rillx:BAAALgADCgQJBgAAAA==.Ripmxi:BAABLgAECn8uAAIDAAkJUhI1VwDRAQADAAkJUhI1VwDRAQAAAA==.',
Ro='Robinski:BAAALgADCgEJAQAAAA==.Robotiss:BAAALgADCgIJAgAAAA==.Rocco:BAAALgADCgYJBwAAAA==.Rodevon:BAAALgADCggJCAAAAA==.Roknasaurus:BAAALgADCgUJCAAAAA==.Romani:BAAALgADCgYJBgAAAA==.Romeo:BAAALgAECgQJBAAAAA==.Ronaldreagnt:BAAALgAECgcJEQAAAA==.',
Ru='Runecat:BAABLgAFFH8GAAMYAAQJzgroSACOAAAYAAMJVQToSACOAAAjAAIJsQKaQQBWAAAAAA==.Runelight:BAACLgAFFH8IAAMeAAMJOQEXNwCGAAAeAAMJOQEXNwCGAAAnAAIJsgHHMQBbAAAuAAQKfxwABB4ACAlQFD4fAMUBAB4ABwmbFD4fAMUBABQABgn3Co08APIAACcAAwkQBTdmAHAAAAAA.Runeshock:BAAALgAECgYJBgAAAA==.Runestick:BAAALgAECgIJAgAAAA==.Rupertgiless:BAACLgAFFH8RAAICAAYJpg56HgCyAQACAAYJpg56HgCyAQAuAAQKfyYAAgIACQl0G30iAIsCAAIACQl0G30iAIsCAAAA.',
Sa='Sabeckya:BAAALgAECgQJCgAAAA==.Sacksmasher:BAAALgADCgcJDwAAAA==.Sampleshrimp:BAAALgADCgEJAgAAAA==.Saphyla:BAAALgADCgcJDAAAAA==.Sappheire:BAAALgAECgYJBgAAAA==.Sarcastyx:BAAALgAECgcJCAAAAA==.Sarrod:BAAALgADCgUJBQAAAA==.Saxines:BAABLgAECn8VAAIUAAYJpQ9HMwArAQAUAAYJpQ9HMwArAQAAAA==.',
Sc='Scaliefox:BAAALgAECgIJAgABLgAECgkJPAAJAN8eAA==.Scarl:BAAALgADCgUJBQAAAA==.Schwarznacht:BAAALgADCgUJBQAAAA==.Schwarzwölf:BAAALgADCgYJCwAAAA==.Sconzil:BAAALgAECgYJBgAAAA==.Scoots:BAAALgADCgQJBAAAAA==.Scrubs:BAAALgAECgYJDAAAAA==.Scrubsevoker:BAAALgAECgQJCQAAAA==.Scumbum:BAAALgADCgIJAgAAAA==.Scyllo:BAAALgAECgQJBAAAAA==.',
Se='Seekndestroy:BAAALgAECgYJEwAAAA==.Selige:BAAALgAECgQJBAAAAA==.',
Sg='Sgtcuunt:BAAALgADCgQJBAAAAA==.',
Sh='Shackled:BAAALgAECgUJBgAAAA==.Shaenicor:BAAALgADCgIJAgAAAA==.Shankkerz:BAAALgAECgcJBwAAAA==.Shelbo:BAAALgAECgEJAQAAAA==.Shmolda:BAAALgADCgYJBwAAAA==.Shortshammy:BAAALgAECgEJAQABLgAFFAMJCwADACUJAA==.Shror:BAAALgADCgEJAQABLgAECgUJBQAKAAAAAA==.',
Si='Sicarune:BAAALgAECgUJBgAAAA==.Siiegrand:BAABLgAECn8VAAIdAAcJhRC+IwDpAAAdAAcJhRC+IwDpAAAAAA==.Silentswag:BAAALgAFFAEJAQAAAA==.Sindrane:BAAALgAECgMJAwABLgAFFAMJBwAZAIAQAA==.Sitzho:BAAALgADCgUJCAAAAA==.',
Sk='Skeleton:BAAALgAECgIJAgAAAA==.Skybringer:BAABLgAECn81AAIGAAgJmQvSjQBKAQAGAAgJmQvSjQBKAQAAAA==.Skyee:BAABLgAECn8qAAMFAAkJvx0LDAC6AgAFAAkJvx0LDAC6AgAEAAMJGxT2cACoAAAAAA==.Skylos:BAAALgAECgEJAgAAAA==.',
Sm='Smexibiotch:BAAALgADCgYJBgABLgAECgIJAgAKAAAAAA==.',
So='Soapscum:BAAALgADCgQJBAAAAA==.Soarphium:BAAALgAECgIJAgABLgAFFAcJGwAWAMEOAA==.Solararc:BAAALgADCgEJAgAAAA==.Soleana:BAAALgAECgYJBQAAAA==.Sombra:BAAALgAECgMJBgABLgAECgcJDgAKAAAAAA==.Sonicast:BAAALgAECgYJCQAAAA==.Sooie:BAAALgAECgYJEgAAAA==.Soramian:BAAALgADCgcJEgAAAA==.Soulcacher:BAACLgAFFH8HAAMZAAMJgBAcKQCYAAAQAAMJ6w2ElgDUAAAZAAMJlwkcKQCYAAAuAAQKfzIAAxAACQmqFKFLABACABAACAknFqFLABACABkACAm9D0AcAGwBAAAA.Soxxy:BAAALgAECgEJAQABLgAFFAIJAwAKAAAAAA==.',
Sp='Spellgunner:BAABLgAECn8VAAIDAAgJPxvvWwDEAQADAAgJPxvvWwDEAQAAAA==.Spinsaround:BAAALgADCgEJAQAAAA==.',
St='Stormwulf:BAAALgADCgUJBQABLgAECgYJEgAKAAAAAA==.Stormyprissi:BAAALgAECgQJDAAAAA==.Strombjorn:BAABLgAECn8jAAMIAAgJohP0RQCIAQAIAAgJohP0RQCIAQALAAUJwQwYXQC9AAAAAA==.',
['Sø']='Sølaria:BAAALgAECgEJAQAAAA==.',
Ta='Tasireth:BAAALgADCgcJBwAAAA==.',
Te='Tessi:BAACLgAFFH8GAAIDAAMJrgIhkwCYAAADAAMJrgIhkwCYAAAuAAQKfxYAAgMABgkiEbCnACoBAAMABgkiEbCnACoBAAAA.',
Th='Thalrian:BAAALgAECgQJBQABLgAFFAMJBgASAKIZAA==.Thefailnym:BAAALgAECggJDQAAAA==.Theory:BAAALgAECgYJBgABLgAECgkJPwAQACMjAA==.Theylive:BAABLgAECn8dAAIYAAkJJw9pMwDGAQAYAAkJJw9pMwDGAQAAAA==.Thondrin:BAAALgAECgYJCwAAAA==.Thordanil:BAAALgAECgEJAgAAAA==.Thrashedass:BAAALgADCgEJAQAAAA==.',
Ti='Tigerlilliy:BAAALgADCgYJEAAAAA==.Timerek:BAAALgADCgIJAgAAAA==.',
To='Toawulf:BAAALgAECgQJCAABLgAECgYJEgAKAAAAAA==.Toetickla:BAAALgAECgEJAgAAAA==.Tokifuji:BAAALgAECgIJBAABLgAECgQJEwAKAAAAAA==.Toranaar:BAAALgAECgcJBwAAAA==.Toya:BAABLgAECn8xAAIWAAkJZRwUDQBJAgAWAAkJZRwUDQBJAgAAAA==.',
Tr='Trenazen:BAAALgADCgkJCgAAAA==.Trevain:BAAALgAECgEJAgAAAA==.Trimasdrood:BAAALgADCgMJAwAAAA==.Trivia:BAAALgAECgYJBgAAAA==.Trundle:BAAALgAECgEJAwAAAA==.Truthordare:BAABLgAECn8mAAIBAAcJYQn1GADRAAABAAcJYQn1GADRAAAAAA==.Trysla:BAAALgAECgEJAQAAAA==.',
Tu='Turtei:BAAALgAECgEJAQABLgAFFAcJJgAFAE0mAA==.Turtl:BAACLgAFFH8mAAIFAAcJTSbPAACsAgAFAAcJTSbPAACsAgAuAAQKfysAAgUACQnmJjcAAPgDAAUACQnmJjcAAPgDAAAA.',
Tw='Twoevil:BAAALgADCgkJCQAAAA==.Twohoof:BAAALgADCgEJAQAAAA==.',
Tx='Txìewtkuä:BAAALgADCgkJCQAAAA==.',
Ty='Tyryn:BAAALgADCgMJBAAAAA==.',
Ug='Uglydragon:BAAALgAECgcJDAAAAA==.Uglypally:BAAALgADCgkJCQAAAA==.Uglypetguy:BAAALgAECgIJAgAAAA==.Uglyrogue:BAAALgAECgQJAgAAAA==.Uglyshaman:BAAALgAECgEJAgAAAA==.',
Ul='Ulgrym:BAAALgAECgMJBQAAAA==.Ultimatia:BAAALgADCgMJBwAAAA==.',
Un='Unbalancéd:BAABLgAECn8cAAIEAAUJqiIzJADqAQAEAAUJqiIzJADqAQAAAA==.',
Va='Vaeadin:BAAALgAECgEJAQAAAA==.Vahra:BAAALgAECgMJCQAAAA==.Valanther:BAAALgAECgMJAwAAAA==.Valantis:BAAALgADCgEJAQAAAA==.Valgaskav:BAABLgAECn8sAAIGAAkJYCMrCQAXAwAGAAkJYCMrCQAXAwAAAA==.Valimond:BAAALgAECgEJAQABLgAECgYJEgAKAAAAAA==.Valric:BAAALgAECgEJAgAAAA==.Vanarrath:BAAALgADCgYJBwAAAA==.Vandryelle:BAAALgADCgIJAgAAAA==.Varge:BAAALgADCgMJAwAAAA==.Varrathos:BAAALgAECgMJBAAAAA==.Vayl:BAAALgAECgMJAwAAAA==.',
Ve='Vegasnight:BAAALgAECgEJAQAAAA==.Velisa:BAAALgADCgYJBgAAAA==.Ventrue:BAAALgADCgMJAwAAAA==.Verdesoul:BAAALgAECgcJEAAAAA==.Vesyra:BAAALgAECgQJBQAAAA==.',
Vi='Viralyn:BAAALgADCgMJAwABLgAECgkJJwAaAJUUAA==.Vixøn:BAAALgAECgMJBgAAAA==.',
Vo='Voidluck:BAABLgAECn8SAAIVAAgJvxBkdABIAQAVAAgJvxBkdABIAQAAAA==.Voker:BAAALgAECgMJCQABLgAECgQJEwAKAAAAAA==.Voladis:BAAALgAECgYJDQAAAA==.Voladro:BAAALgAECgQJBAAAAA==.Volanie:BAAALgAECgMJAQAAAA==.Volos:BAABLgAECn8tAAIGAAgJORbHUgDGAQAGAAgJORbHUgDGAQAAAA==.Vordaman:BAABLgAECn80AAIQAAkJYRNpSQDeAQAQAAkJYRNpSQDeAQAAAA==.',
Vy='Vynír:BAACLgAFFH8XAAICAAYJtxy6HwCrAQACAAYJtxy6HwCrAQAuAAQKfy4AAwIACQmgI5UIAAsDAAIACQk+I5UIAAsDAAEABQkHI40NAOwBAAAA.',
Wa='Waghoba:BAECLgAFFH8oAAIcAAYJaiIEAQACAgAcAAYJaiIEAQACAgAuAAQKfyIAAhwACQnMIScGAJwCABwACQnMIScGAJwCAAAA.Waito:BAAALgAECgQJBwAAAA==.Wandä:BAABLgAECn85AAQaAAkJQB5bCQCVAgAaAAkJcRxbCQCVAgAFAAkJMRMbGQDdAQAEAAcJMBCcPgBaAQAAAA==.Wardriccan:BAAALgAECggJDgAAAA==.Warfle:BAAALgADCgYJBgAAAA==.Warhound:BAAALgADCgcJBwAAAA==.Warrionomous:BAACLgAFFH8PAAISAAUJLBFXHwAnAQASAAUJLBFXHwAnAQAuAAQKfxsAAhIACAkeG/wZABcCABIACAkeG/wZABcCAAEuAAUUBQkPAAMAqxEA.Washu:BAACLgAFFH8HAAImAAQJgguCEgD7AAAmAAQJgguCEgD7AAAuAAQKf0IAAyYACQnaH40FANoCACYACQnaH40FANoCAAcAAwlMC1khAHkAAAAA.',
Wh='Whimlock:BAAALgADCgQJBAABLgAFFAMJBwADAOUcAA==.Whimzie:BAAALgAECgEJAQABLgAFFAMJBwADAOUcAA==.Whorphium:BAAALgAECggJEgABLgAFFAcJGwAWAMEOAA==.',
Wi='Willow:BAAALgAECgYJCwAAAA==.Winterous:BAAALgAECgQJBwAAAA==.',
Wo='Wonderbread:BAABLgAECn88AAIGAAkJ9xXtNAAiAgAGAAkJ9xXtNAAiAgAAAA==.',
Wr='Wrager:BAAALgAECgUJBgAAAA==.Wrathofzaun:BAAALgAECgYJDwAAAA==.',
Wy='Wylest:BAAALgADCgcJBwAAAA==.Wynch:BAAALgAECgkJCQAAAA==.',
['Wâ']='Wârwôlf:BAABLgAECn8pAAMNAAkJHCRFBgAoAwANAAkJHCRFBgAoAwAMAAQJ+BWyVQDzAAAAAA==.',
Xe='Xenan:BAABLgAECn82AAIGAAkJOxbcNQAfAgAGAAkJOxbcNQAfAgAAAA==.',
Xt='Xtrolldinary:BAABLgAECn8UAAIYAAQJ7AwgiQCbAAAYAAQJ7AwgiQCbAAAAAA==.',
Xv='Xvp:BAAALgAECgQJCgAAAA==.',
Xy='Xylophy:BAABLgAECn8rAAIHAAkJPBRNCQDJAQAHAAkJPBRNCQDJAQAAAA==.',
Ye='Yeastmode:BAACLgAFFH8WAAINAAUJJRDwPAAoAQANAAUJJRDwPAAoAQAuAAQKfy4AAg0ACAksHeMiAE0CAA0ACAksHeMiAE0CAAAA.',
Yo='Yonah:BAAALgAECgYJDAAAAA==.',
Yu='Yurc:BAABLgAECn8nAAIhAAkJeBkiCQBaAgAhAAkJeBkiCQBaAgAAAA==.',
Za='Zademan:BAAALgAECgUJBwAAAA==.Zappyu:BAAALgAECgkJBQABLgAECgkJCQAKAAAAAA==.Zarkas:BAAALgAECgUJBgAAAA==.',
Ze='Zeebra:BAAALgAECgcJEAAAAA==.Zeg:BAAALgAECgQJBAAAAA==.Zega:BAAALgAFFAEJAQAAAA==.Zegafur:BAABLgAECn8wAAIYAAgJnRxXHwBCAgAYAAgJnRxXHwBCAgAAAA==.Zeruk:BAABLgAECn8XAAMFAAcJjwJ1YACOAAAFAAYJlAJ1YACOAAAEAAcJpQFvhgBvAAAAAA==.',
Zi='Zillionbúcks:BAACLgAFFH8cAAIGAAgJWxOYCQAPAgAGAAgJWxOYCQAPAgAuAAQKfxsAAgYACQmvHtEtAGwCAAYACQmvHtEtAGwCAAAA.',
Zu='Zullee:BAAALgADCgkJEgAAAA==.',
Zy='Zylcat:BAAALgAECgYJDAAAAA==.',
['Zê']='Zêddicus:BAABLgAECn8zAAMBAAkJtCCAAQDHAgABAAkJtCCAAQDHAgACAAUJHwgM1ACyAAAAAA==.',
['Áq']='Áquafina:BAABLgAECn88AAIDAAkJpg5zVgDTAQADAAkJpg5zVgDTAQAAAA==.',
['Åñ']='Åñgêl:BAAALgAECgIJAgAAAA==.',
['Îv']='Îvan:BAAALgADCggJCAAAAA==.',
['Ðö']='Ðö:BAABLgAECn8vAAISAAkJwB0pDQCTAgASAAkJwB0pDQCTAgAAAA==.',
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
