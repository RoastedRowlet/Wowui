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

local lookup = {'Warlock-Destruction','Warlock-Demonology','Unknown-Unknown','Mage-Frost','Monk-Mistweaver','Monk-Windwalker','Paladin-Retribution','DemonHunter-Vengeance','Shaman-Restoration','Paladin-Holy','Shaman-Elemental','Hunter-Marksmanship','Hunter-Survival','Hunter-BeastMastery','Evoker-Augmentation','DeathKnight-Unholy','DeathKnight-Frost','Warrior-Fury','Evoker-Devastation','Priest-Holy','DemonHunter-Devourer','Rogue-Subtlety','Warrior-Arms','Druid-Restoration','DeathKnight-Blood','Monk-Brewmaster','Druid-Guardian','Druid-Feral','Paladin-Protection','Priest-Discipline','Shaman-Enhancement','Evoker-Preservation','Warrior-Protection','Rogue-Outlaw','Druid-Balance','Mage-Fire','Warlock-Affliction','DemonHunter-Havoc','Priest-Shadow',}
local provider = {region='US',realm='Anvilmar',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aaril:BAAALgAECgYJIQAAAQ==.',
Ab='Abrams:BAAALgADCgYJCgAAAA==.',
Ad='Adel:BAAALgAECgYJCAAAAA==.',
Ae='Aelitha:BAABLgAECn8ZAAMBAAYJCQZ2OQDOAAABAAYJxAR2OQDOAAACAAYJsQRuzwCzAAAAAA==.',
Ak='Akaishi:BAAALgADCgIJAgAAAA==.Akali:BAAALgAFFAIJAwABLgAFFAMJBAADAAAAAA==.Akina:BAAALgADCgYJBwABLgAECgkJKwAEAIEOAA==.',
Al='Alanie:BAAALgAECgIJAgAAAA==.Alathiana:BAAALgADCgUJCAAAAA==.Alcweaver:BAABLgAECn8dAAMFAAcJgiBqIAASAgAFAAcJgiBqIAASAgAGAAYJgA+GPwD+AAAAAA==.Alecto:BAAALgAECgMJAwAAAA==.Alindia:BAAALgAECgQJCgABLgAECgkJKwAEAIEOAA==.Alirrayia:BAAALgAECgQJBQAAAA==.Alirrayiia:BAACLgAFFH8IAAIHAAMJ+AFOhgCcAAAHAAMJ+AFOhgCcAAAuAAQKfyoAAgcACQlwFGdBAAACAAcACQlwFGdBAAACAAAA.Alkri:BAAALgADCgMJAwAAAA==.Allari:BAAALgAECgYJEwAAAA==.Allikazam:BAAALgADCgYJGAAAAA==.Allystar:BAAALgAECgQJDwAAAA==.Altheia:BAAALgAECgQJBAAAAA==.Alvidor:BAABLgAECn9JAAIEAAkJqQYchgBnAQAEAAkJqQYchgBnAQAAAA==.',
Am='Ambrose:BAAALgAECgcJBwAAAA==.Ameria:BAAALgADCgUJBQAAAA==.Amexican:BAAALgAECgEJAQAAAA==.',
An='Anastos:BAAALgAECgUJBQAAAA==.Andydufresne:BAAALgAECgQJDgABLgAECgkJSgAIAKclAA==.Angryqueer:BAAALgADCgEJAQAAAA==.',
Ao='Aowl:BAAALgAECgcJCwAAAA==.',
Ap='Apocketheory:BAAALgADCgIJAgAAAA==.Apolloerosb:BAAALgAECgYJCwABLgAECgcJIwAJACEbAA==.Apolloerosp:BAAALgAECgMJAwABLgAECgcJIwAJACEbAA==.Apollossham:BAABLgAECn8jAAIJAAcJIRsYKgAPAgAJAAcJIRsYKgAPAgAAAA==.',
Ar='Arkanaun:BAABLgAECn8dAAMHAAYJRBdpcwCUAQAHAAYJRBdpcwCUAQAKAAUJvRQyTAAIAQAAAA==.',
As='Ashes:BAAALgAECgcJAQAAAA==.Ashrán:BAAALgAECgYJCQAAAA==.Ashyluna:BAAALgAECgQJBAAAAA==.Astianna:BAAALgADCgMJAwAAAA==.',
Au='Aule:BAAALgAECgIJAwAAAA==.Aurinia:BAAALgADCgQJAgAAAA==.Auroradinlee:BAAALgAECgkJBgAAAA==.Aurore:BAAALgAECgQJCgAAAA==.',
Av='Avradea:BAAALgAECgEJAQABLgAECgkJKwAEAIEOAA==.',
Az='Azareth:BAAALgADCggJCAAAAA==.',
Ba='Baconatorr:BAAALgAECgQJBQAAAA==.Bagelbags:BAAALgADCgEJAQAAAA==.Bahler:BAAALgADCgUJBQABLgAECgMJAwADAAAAAA==.Baji:BAABLgAECn87AAMJAAkJLSK3BwAxAwAJAAkJLSK3BwAxAwALAAUJ/hUcSQAMAQAAAA==.Baklan:BAAALgAECgMJAwAAAA==.Barefaall:BAACLgAFFH8WAAMMAAcJoBdqCQDMAQAMAAcJExZqCQDMAQANAAQJ/hCAEAA9AQAuAAQKf0QAAwwACQllJNgAAD8DAAwACQllJNgAAD8DAA4ABAmFEJanAO0AAAAA.Barefall:BAACLgAFFH8JAAINAAMJYhBjHgDcAAANAAMJYhBjHgDcAAAuAAQKfxUAAg0ACQk4D3IWAO4BAA0ACQk4D3IWAO4BAAEuAAUUBwkWAAwAoBcA.Barefalls:BAACLgAFFH8LAAINAAMJlhzJHADlAAANAAMJlhzJHADlAAAuAAQKfzAAAw0ACQk9H+AGALECAA0ACQk9H+AGALECAAwAAQmMAaCWACIAAAEuAAUUBwkWAAwAoBcA.Barelywolf:BAABLgAECn8mAAMGAAkJwB8uEQA5AgAGAAcJ5CAuEQA5AgAFAAgJLxcNIgAHAgABLgAFFAMJBgAPACwLAA==.Bashira:BAABLgAECn8eAAIOAAkJsApoVwCZAQAOAAkJsApoVwCZAQAAAA==.Bast:BAACLgAFFH8HAAMQAAMJPweNrwC/AAAQAAMJPweNrwC/AAARAAEJVgM8KgA4AAAuAAQKfy8AAxAACQlHFl4yADICABAACQlHFl4yADICABEABAmJDcInAI8AAAAA.Bastrillan:BAAALgAECgUJBwAAAA==.',
Be='Bearophe:BAAALgAECgEJAgAAAA==.Beerfist:BAAALgAECgEJAQAAAA==.Belfor:BAAALgAECgMJAwAAAA==.Bellock:BAAALgAECgMJAwAAAA==.Bendroyd:BAAALgAECgIJAgAAAA==.Benisbagina:BAAALgADCggJCQAAAA==.Bergonator:BAABLgAECn8gAAISAAYJcRC9TwBpAQASAAYJcRC9TwBpAQAAAA==.Berrodiah:BAAALgAECggJDwABLgAECggJFgATALUYAA==.Bettyswalls:BAAALgAECgMJAwAAAA==.Beyarago:BAAALgAECgUJCQAAAA==.',
Bh='Bheiroth:BAABLgAECn8yAAIUAAkJSCRWBAA8AwAUAAkJSCRWBAA8AwAAAA==.',
Bi='Birds:BAAALgAECgkJEQAAAA==.',
Bl='Bladeygaga:BAABLgAECn85AAIVAAkJpR9iCwDqAgAVAAkJpR9iCwDqAgAAAA==.Blasé:BAAALgAECgcJCAAAAA==.Blazingblood:BAAALgADCgUJAQAAAA==.Bloodknight:BAAALgADCgYJCQAAAA==.Bluekrayen:BAAALgAECgUJCAAAAA==.Bluett:BAAALgAECgMJCQAAAA==.Bláckøut:BAAALgADCgYJDAAAAA==.',
Bo='Bodhi:BAABLgAECn8WAAIWAAcJNhAQJwDAAQAWAAcJNhAQJwDAAQAAAA==.Bogertus:BAACLgAFFH8QAAISAAMJgCRJIQApAQASAAMJgCRJIQApAQAuAAQKf0AAAxIACQnSJmsAAI8DABIACQnSJmsAAI8DABcAAgn1HHIpAKUAAAAA.Bonobo:BAAALgAECgYJCQAAAA==.Boomertunes:BAABLgAECn8mAAMCAAkJYxiIJQBGAgACAAkJYxiIJQBGAgABAAIJGwHVUgAAAAAAAA==.',
Br='Brein:BAABLgAECn9LAAIYAAkJ8yWvAADgAwAYAAkJ8yWvAADgAwAAAA==.Brewmaster:BAAALgAECgIJAwAAAA==.Brewwmaster:BAABLgAECn8kAAQZAAkJrBhCFwCqAQAZAAkJIBVCFwCqAQAQAAYJtBfWfACKAQARAAEJ+he5FgA2AAAAAA==.Bricklethumb:BAAALgAECgMJAwABLgAECgYJGAAFAGYYAA==.Brickred:BAAALgADCggJDgAAAA==.Brynodd:BAAALgAECgMJCQAAAA==.',
Bu='Bubblybetty:BAAALgAECgEJAQAAAA==.Bucketeer:BAABLgAECn8rAAIEAAkJUR8lHACwAgAEAAkJUR8lHACwAgAAAA==.Buffs:BAAALgADCgEJAQAAAA==.Bullminator:BAAALgAECggJDgAAAA==.Bursona:BAAALgAECgEJAQAAAA==.Butterfree:BAAALgAECgUJDAABLgAFFAEJAQADAAAAAA==.',
Ca='Cards:BAAALgAECgYJCgAAAA==.Carkrash:BAAALgADCgkJGgAAAA==.Casterkang:BAAALgAECgUJCQAAAA==.Catshunter:BAABLgAECn8UAAIOAAYJvRwyQACvAQAOAAYJvRwyQACvAQAAAA==.',
Ce='Celaa:BAABLgAECn8rAAIEAAkJgQ5DXQDEAQAEAAkJgQ5DXQDEAQAAAA==.',
Ch='Chanka:BAABLgAECn8YAAIBAAYJVQgoHgC0AAABAAYJVQgoHgC0AAAAAA==.Chantillary:BAAALgAECgMJCQAAAA==.Chargerkang:BAAALgADCgYJBgAAAA==.Chchanges:BAAALgAECgEJAQAAAA==.Cheesy:BAABLgAECn8qAAICAAgJFA3VawBkAQACAAgJFA3VawBkAQAAAA==.Chicken:BAAALgAECgYJEgAAAA==.Chonk:BAAALgADCgEJAQAAAA==.Chopzullee:BAABLgAECn8ZAAIGAAYJ6QnQXACfAAAGAAYJ6QnQXACfAAAAAA==.',
Ci='Cirya:BAAALgAECgUJCQAAAA==.',
Cl='Cleric:BAAALgADCgUJBQAAAA==.Clortho:BAAALgAECgUJDgAAAA==.Clorthö:BAAALgADCgUJBQAAAA==.',
Co='Coljack:BAAALgAECggJCAAAAA==.Colljack:BAACLgAFFH8gAAIKAAcJkRcEDgDOAQAKAAcJkRcEDgDOAQAuAAQKfyEAAwoACQkgIZwJANgCAAoACQkgIZwJANgCAAcABQlOEtO5ABIBAAAA.Coughlin:BAAALgAECgEJAQAAAA==.',
Cr='Crocbait:BAAALgAECgcJEQAAAA==.Cryptoe:BAACLgAFFH8HAAIEAAMJuhAHgADeAAAEAAMJuhAHgADeAAAuAAQKfx4AAgQACQnNEwVJAP0BAAQACQnNEwVJAP0BAAAA.',
Cu='Cudlsac:BAAALgAECgQJBQAAAA==.',
Da='Daedelus:BAABLgAECn8hAAMVAAgJkxSYVwB9AQAVAAgJXxSYVwB9AQAIAAYJtxFJFAALAQAAAA==.Daglon:BAAALgAFFAIJAwAAAA==.Dagz:BAAALgAECgQJBAAAAA==.Dakina:BAAALgADCgYJBgAAAA==.Daraedra:BAAALgAECgYJDwAAAA==.Darkenvoid:BAAALgADCgkJDQAAAA==.',
De='Deathslight:BAAALgAECgQJBwAAAA==.Dedaeste:BAAALgADCgUJBwAAAA==.Deeznutticus:BAACLgAFFH8bAAISAAYJKhYjEAB/AQASAAYJKhYjEAB/AQAuAAQKfyEAAxIABwnCIkgYAIkCABIABwnCIkgYAIkCABcAAgkBHaZaAGoAAAAA.Defnotisis:BAABLgAECn8dAAMaAAgJhxRVKABsAQAaAAcJCRZVKABsAQAGAAgJtAtBQwDvAAABLgAFFAMJBAADAAAAAA==.Defnotkity:BAABLgAFFH8GAAMbAAMJVQ3sKgBnAAAcAAIJ2QfEFgB0AAAbAAIJiA/sKgBnAAAAAA==.Demonspud:BAABLgAECn8dAAIVAAcJhRKjZABaAQAVAAcJhRKjZABaAQAAAA==.Demotard:BAAALgAECgIJAQAAAA==.Denxster:BAAALgAECgYJDgAAAA==.Dersan:BAABLgAECn8hAAIBAAgJ1ADwPAA1AAABAAgJ1ADwPAA1AAAAAA==.Destriant:BAABLgAECn83AAIdAAkJyxk1CgAlAgAdAAkJyxk1CgAlAgAAAA==.Devilschant:BAAALgAECgYJCgAAAA==.Devilshadow:BAAALgAECgUJBwABLgAECgYJCgADAAAAAA==.Dewburt:BAAALgADCggJCgAAAA==.Deylia:BAAALgAECgYJEQABLgAFFAUJIQAeALkYAA==.',
Di='Dilithia:BAABLgAECn8bAAIQAAYJ0wK2DQGWAAAQAAYJ0wK2DQGWAAAAAA==.Dillion:BAAALgAECgYJCAAAAA==.Dinonuggies:BAAALgADCgcJBwAAAA==.Dionin:BAAALgADCgYJCQAAAA==.Dira:BAAALgAFFAIJAgABLgAFFAYJHQAfAK4gAA==.Dirkbanne:BAAALgADCgYJBgAAAA==.',
Do='Dodoubleg:BAAALgAECgYJEAAAAA==.Dominique:BAAALgADCgYJBgAAAA==.Donzilch:BAEALgAECgQJBAAAAA==.Donzilly:BAAALgAECgUJBQAAAA==.Dooburt:BAAALgAECggJEgAAAA==.Doombringers:BAAALgAECgUJCAAAAA==.',
Dr='Dracaric:BAABLgAECn8qAAIPAAkJEhY+GAATAgAPAAkJEhY+GAATAgAAAA==.Draeca:BAAALgAECgMJBgAAAA==.Dragondznut:BAAALgAECgQJBQAAAA==.Drakhar:BAAALgADCgIJAgABLgAECgYJCwADAAAAAA==.Drfrostie:BAAALgAECgcJEwAAAA==.Drgunner:BAAALgAECgcJDwAAAA==.Driatin:BAAALgAFFAEJAQAAAA==.Drkladykikyo:BAABLgAECn8XAAIUAAkJFQOUQADmAAAUAAkJFQOUQADmAAAAAA==.Druroo:BAAALgAECgEJAQABLgAFFAQJBwAQADUWAA==.Druterr:BAAALgAECgIJAgABLgAECgcJBwADAAAAAA==.',
Du='Dumb:BAACLgAFFH8PAAIgAAUJLAyTBgCJAQAgAAUJLAyTBgCJAQAuAAQKfyMAAiAACAnoG28LAH4CACAACAnoG28LAH4CAAAA.Durø:BAABLgAECn8WAAIVAAgJryLZDAAZAwAVAAgJryLZDAAZAwAAAA==.Duskhunter:BAAALgADCgEJAQAAAA==.',
Dy='Dyanisian:BAAALgADCgYJCAAAAA==.',
['Dè']='Dègenerate:BAABLgAECn9CAAIhAAkJjiA8BADjAgAhAAkJjiA8BADjAgAAAA==.',
Ed='Edagerran:BAAALgADCgkJCQAAAA==.',
Ei='Eilae:BAABLgAECn8bAAIOAAcJ2wT8nQD/AAAOAAcJ2wT8nQD/AAAAAA==.Eirhakan:BAAALgAECgQJCAAAAA==.',
El='Elrethyl:BAABLgAECn8WAAIHAAcJXhhfdQCBAQAHAAcJXhhfdQCBAQAAAA==.Elvanus:BAAALgADCgYJBgAAAA==.Elêktra:BAABLgAECn8tAAILAAkJuA5YMgBwAQALAAkJuA5YMgBwAQAAAA==.',
Em='Emet:BAAALgAECgQJBAABLgAECgkJRwAJAEwbAA==.',
Ep='Epicnym:BAAALgAECgEJAQAAAA==.Epicsmoke:BAACLgAFFH8OAAISAAMJDxwDKgAGAQASAAMJDxwDKgAGAQAuAAQKf1QAAhIACQkPJQoCAFgDABIACQkPJQoCAFgDAAAA.Epidemius:BAAALgAECgkJCgAAAA==.',
Er='Erevan:BAABLgAECn84AAMWAAkJ3BuJCACcAgAWAAkJ3BuJCACcAgAiAAEJpwABEAAcAAAAAA==.Erinn:BAAALgAECgIJAgAAAA==.Eroica:BAAALgADCgYJBwAAAA==.Eronys:BAAALgAFFAIJAQAAAA==.',
Es='Esdeath:BAABLgAECn8sAAMQAAkJ5hNATQDYAQAQAAkJ5hNATQDYAQAZAAYJWgalPQCXAAAAAA==.',
Et='Etharia:BAAALgADCgUJAwAAAA==.',
Ev='Evilsmeghead:BAAALgADCgEJAQAAAA==.',
Ex='Exiledguy:BAAALgADCgYJBgAAAA==.Extenze:BAABLgAECn8oAAIVAAkJXx2SGQB4AgAVAAkJXx2SGQB4AgAAAA==.',
Ez='Ezykiah:BAAALgAECgEJAQAAAA==.',
Fa='Falconponch:BAAALgADCgEJAQAAAA==.',
Fe='Felbjorn:BAAALgAECgEJAgAAAA==.Felgibson:BAAALgAECgQJBQAAAA==.Felkang:BAAALgADCgkJCQAAAA==.Ferryman:BAABLgAECn8ZAAIOAAcJoRO8XgCGAQAOAAcJoRO8XgCGAQAAAA==.',
Fl='Flingor:BAAALgAECgYJEAAAAA==.Flokha:BAAALgADCgEJAQAAAA==.',
Fo='Forphium:BAACLgAFFH8cAAIWAAcJwQ6lBACkAQAWAAcJwQ6lBACkAQAuAAQKfyAAAhYACQn9IH0NAMQCABYACQn9IH0NAMQCAAAA.',
Fr='Fredolf:BAAALgAECgEJAQAAAA==.Freydís:BAAALgAECgUJCwAAAA==.Freyå:BAAALgAECgIJAgAAAA==.Friarkuck:BAAALgADCggJCAAAAA==.Friedbones:BAAALgAECgMJCQAAAA==.Frostlilliy:BAAALgADCggJCwAAAA==.',
['Fü']='Fürbie:BAAALgAECgIJAwAAAA==.',
Ga='Gahlina:BAABLgAECn8VAAMJAAcJtBYvMgDnAQAJAAcJtBYvMgDnAQALAAEJ1wEzlgAeAAAAAA==.Galdorian:BAAALgADCgYJCQABLgAECgkJHgAOALAKAA==.Galynda:BAAALgADCgcJCQAAAA==.',
Ge='Genjimain:BAABLgAECn8lAAMYAAkJBhqRHgBKAgAYAAkJBhqRHgBKAgAcAAMJ9wxLNACHAAAAAA==.Genjí:BAAALgAECgEJAwAAAA==.Geris:BAAALgAECgQJBQAAAA==.Gertruide:BAAALgADCgUJBQAAAA==.',
Gh='Ghendala:BAAALgADCggJEwAAAA==.',
Gi='Gillesmon:BAAALgAFFAEJAQABLgAFFAIJAwADAAAAAA==.Gilleyy:BAAALgAECgQJBQABLgAECgYJFAATAJodAA==.Gincainn:BAAALgAECgEJAgAAAA==.Gird:BAABLgAECn8oAAIKAAgJ4Q3iNwBrAQAKAAgJ4Q3iNwBrAQAAAA==.Girdlock:BAAALgAECgYJBwAAAA==.',
Gl='Glaiveyjones:BAAALgAECgEJAQAAAA==.',
Gn='Gnymesis:BAAALgAECgYJCAAAAA==.',
Go='Goatmonger:BAAALgAECgYJBgAAAA==.Goinpostal:BAAALgAECgIJAgAAAA==.Goldblade:BAAALgAECgkJEwAAAA==.Goodvsevil:BAAALgAECgQJBAAAAA==.Gordek:BAABLgAECn8dAAMHAAkJsRp6LABMAgAHAAkJsRp6LABMAgAKAAIJhBBudgBfAAAAAA==.Gothitelle:BAAALgAECgIJBwAAAA==.Goöse:BAACLgAFFH8ZAAIQAAYJJh7dAwDEAQAQAAYJJh7dAwDEAQAuAAQKfycAAhAACAmDJusGAGsDABAACAmDJusGAGsDAAAA.',
Gr='Grantaron:BAABLgAECn83AAIHAAkJ2iA2GACvAgAHAAkJ2iA2GACvAgAAAA==.Gravarii:BAAALgADCgcJEwAAAA==.Grimskul:BAABLgAECn8zAAMQAAkJkB1MGgCnAgAQAAkJkB1MGgCnAgARAAYJDxSUBwCBAQAAAA==.Grindor:BAAALgADCgEJAQAAAA==.Grntitan:BAAALgAECgQJCgAAAA==.Gruid:BAAALgADCgcJDwAAAA==.',
Gu='Guinessbrew:BAAALgAECgEJAQAAAA==.',
Gw='Gwoohoori:BAAALgAECggJEwAAAA==.',
Gy='Gyra:BAAALgAECgYJEQAAAA==.Gyrojetli:BAAALgAECgQJBQAAAA==.',
Ha='Halukari:BAABLgAECn8VAAMbAAYJXiCICwDYAQAbAAYJXiCICwDYAQAjAAEJ8gzahgApAAABLgAFFAUJIQAeALkYAA==.Harfnan:BAAALgAECgIJAgAAAA==.Harrin:BAACLgAFFH8HAAIEAAQJpgQudQD2AAAEAAQJpgQudQD2AAAuAAQKfx0AAgQABwn2D5yhADUBAAQABwn2D5yhADUBAAAA.',
He='Healingwater:BAAALgAECgIJAwAAAA==.Herracles:BAAALgADCgYJGAAAAA==.Hezrel:BAAALgAECgYJCgAAAA==.',
Hi='Hierodule:BAAALgAECgEJAQAAAA==.Hiimriven:BAAALgAECgIJAgABLgAECgYJFgAWAFkhAA==.Hinal:BAABLgAECn8gAAIHAAkJMhugJwBjAgAHAAkJMhugJwBjAgAAAA==.',
Ho='Hojo:BAAALgADCgUJCAAAAA==.Holyenabler:BAABLgAFFH8RAAIdAAMJegyJDgCRAAAdAAMJegyJDgCRAAAAAA==.Honzo:BAAALgADCgkJCQAAAA==.Hootiehoo:BAAALgADCgMJAwAAAA==.',
Hu='Huflunggoo:BAAALgADCgkJDQAAAA==.Huflungpoop:BAABLgAECn80AAIGAAkJqBoVEQA7AgAGAAkJqBoVEQA7AgAAAA==.Hunterborn:BAAALgAFFAIJAgAAAA==.',
Hy='Hypercube:BAAALgAECgQJBwAAAA==.',
['Hè']='Hèalz:BAAALgAECgYJBgABLgAECgkJNgASAOkdAA==.',
Ic='Ickixia:BAAALgADCgQJBAAAAA==.',
Il='Ilkaressa:BAAALgADCgQJBAAAAA==.Illyríá:BAEBLgAFFH8KAAICAAMJQxFNcgDXAAACAAMJQxFNcgDXAAABLgAECgkJLwABADobAA==.Ilun:BAAALgAECgIJAgAAAA==.',
Im='Imcruel:BAACLgAFFH8fAAMEAAcJChiBHgAHAgAEAAcJChiBHgAHAgAkAAMJlBQ/AwDSAAAuAAQKfzAAAgQACQnNJUsHAEIDAAQACQnNJUsHAEIDAAAA.Imisis:BAAALgAECgYJCQAAAA==.Ims:BAAALgAECggJBQAAAA==.',
In='Ink:BAACLgAFFH8NAAIEAAQJKxF/YAAqAQAEAAQJKxF/YAAqAQAuAAQKfycAAgQABwm2IN9YAM8BAAQABwm2IN9YAM8BAAAA.',
Is='Istaria:BAAALgAECgMJCAAAAA==.Isujr:BAABLgAECn8ZAAIQAAcJ8hIKcQCmAQAQAAcJ8hIKcQCmAQAAAA==.',
Ja='Jacaerys:BAAALgADCgYJBgAAAA==.Jackiegan:BAABLgAECn8rAAQaAAkJBSF7BAD7AgAaAAkJBSF7BAD7AgAGAAEJahGYjABCAAAFAAEJJgfVzAAeAAAAAA==.Jackson:BAAALgAECgMJCQAAAA==.Jagerdemon:BAAALgAECgcJCAAAAA==.',
Je='Jerce:BAAALgADCgUJBQAAAA==.Jeryatric:BAAALgADCgcJBwAAAA==.',
Jh='Jhala:BAAALgADCgkJDwAAAA==.',
Ji='Jinnxx:BAAALgAECgMJBAABLgAFFAYJHQAfAK4gAA==.',
Jo='Joshcalc:BAABLgAFFH8FAAIjAAIJNiQiLADUAAAjAAIJNiQiLADUAAAAAA==.Joskel:BAABLgAECn8vAAQCAAgJDw3hcABXAQACAAgJiQzhcABXAQAlAAYJMQToFgDIAAABAAIJNgxjMABYAAAAAA==.',
Ju='Juacqer:BAAALgAECgMJCQAAAA==.Juggarnaut:BAAALgADCgYJCAAAAA==.',
Ka='Kaant:BAABLgAECn9HAAMJAAkJTBteEQDAAgAJAAkJTBteEQDAAgALAAgJ7R35EgBUAgAAAA==.Kaeni:BAAALgADCgMJAwAAAA==.Kaidevyn:BAABLgAECn80AAMRAAkJWBaVBwAbAgARAAkJWBaVBwAbAgAQAAQJWgomFAGOAAAAAA==.Kaiste:BAAALgADCgEJAQAAAA==.Kaleine:BAAALgAECgYJCAAAAA==.Kardren:BAAALgAECgUJDAAAAA==.Kat:BAAALgAECgMJAwAAAA==.',
Ke='Keiko:BAAALgAECggJDwAAAA==.Keiran:BAABLgAECn81AAMOAAkJ4yINCgAEAwAOAAkJ4yINCgAEAwAMAAgJpRzPEgCgAgAAAA==.Kelazurin:BAAALgADCgEJAQAAAA==.Kellistair:BAAALgADCgYJBgAAAA==.Keläo:BAAALgADCgUJCQAAAA==.Kenshii:BAAALgAECgUJBQAAAA==.Keyadish:BAAALgADCgYJDQAAAA==.Keys:BAACLgAFFH8HAAIWAAMJlhWFKADfAAAWAAMJlhWFKADfAAAuAAQKfyYAAhYACAkTHrkQAJwCABYACAkTHrkQAJwCAAAA.',
Kh='Khalnerys:BAACLgAFFH8FAAMPAAIJLwbuVQBvAAAPAAIJLwbuVQBvAAATAAEJ5AHnEAAoAAAuAAQKfycABA8ACAkaCgBHAAsBAA8ACAkmCABHAAsBABMABQl4CTwWAK0AACAAAwlOB5UwAGUAAAAA.Khitt:BAAALgAECgEJAQABLgAECgMJCAADAAAAAA==.Khoulock:BAACLgAFFH8TAAICAAcJlhDdMAB6AQACAAcJlhDdMAB6AQAuAAQKfzUABAIACQnKIMcPAM0CAAIACQm6IMcPAM0CACUABQliIkoTADMBAAEAAwl9ENU+ALkAAAAA.',
Ki='Kimmi:BAABLgAECn8ZAAMBAAkJKQXTFgDpAAABAAkJKQXTFgDpAAACAAIJ1gANYwEUAAAAAA==.Kimmispally:BAAALgAECgQJBQAAAA==.Kiro:BAAALgADCgQJBQAAAA==.',
Kn='Knowimsayin:BAAALgAECgEJAQAAAA==.',
Ko='Kota:BAAALgAECgEJAQAAAA==.Kotateal:BAAALgAECgYJCwAAAA==.',
Kr='Kruelshot:BAACLgAFFH8OAAMOAAQJMiOIHACJAQAOAAQJMiOIHACJAQANAAEJiwvDMABKAAAuAAQKfxYAAw4ACAnFJLMRAMACAA4ACAnFJLMRAMACAAwABwlqEgAyAKgBAAEuAAUUBwkfAAQAChgA.Krux:BAAALgAECgEJAQAAAA==.',
Kt='Kthxbye:BAAALgAECgUJBwABLgAECgcJCAADAAAAAA==.',
Ku='Kumcookies:BAAALgADCgEJAQAAAA==.Kungfuprissy:BAAALgAECgMJBwAAAA==.Kuraishin:BAACLgAFFH8SAAIcAAMJGB7dCwDwAAAcAAMJGB7dCwDwAAAuAAQKf5AAAxwACAnsJTkCAAkDABwACAnsJTkCAAkDABsACAnnIjkFALcCAAEuAAUUBAkWABAA4gsA.Kuroakuma:BAAALgAECgYJEAAAAA==.Kuvara:BAAALgADCgkJCgAAAA==.',
Kv='Kvnnp:BAAALgADCgYJBgAAAA==.Kvnpro:BAAALgADCgUJBwAAAA==.Kvnxx:BAAALgADCgUJBQAAAA==.',
Kw='Kwandashadow:BAAALgAECgUJDgAAAA==.',
Ky='Kylemonk:BAAALgADCgEJAQAAAA==.',
['Ké']='Kéres:BAAALgADCgkJEAAAAA==.',
La='Lagspike:BAABLgAECn8gAAIEAAgJqBVTlgCnAQAEAAgJqBVTlgCnAQAAAA==.Latheal:BAAALgAECgMJBAAAAA==.Latto:BAAALgAFFAMJBAAAAA==.Lavi:BAABLgAECn8dAAIHAAgJDA4xjgBSAQAHAAgJDA4xjgBSAQAAAA==.',
Lb='Lbk:BAAALgADCgIJAgAAAA==.',
Le='Lejeune:BAAALgAECgMJCQAAAA==.Lengex:BAAALgAECggJDAAAAA==.Lero:BAABLgAECn8iAAIaAAkJuCFNBQDqAgAaAAkJuCFNBQDqAgAAAA==.Lerwindion:BAABLgAECn8qAAIeAAkJYx2VCQCiAgAeAAkJYx2VCQCiAgABLgAFFAQJBwAQADUWAA==.Lescaryn:BAAALgADCgIJAgAAAA==.Lexoh:BAAALgAECgYJEgAAAA==.',
Li='Lilani:BAAALgADCgQJBAAAAA==.Lindir:BAACLgAFFH8PAAINAAUJ3Rq+EAA8AQANAAUJ3Rq+EAA8AQAuAAQKfyoAAg0ACQk9JKkBAD8DAA0ACQk9JKkBAD8DAAAA.Lionelle:BAAALgAECgYJDgAAAA==.Liq:BAAALgAFFAEJAQABLgAFFAYJIgAVAFMdAA==.Liquor:BAACLgAFFH8iAAIVAAYJUx13IACpAQAVAAYJUx13IACpAQAuAAQKf1AAAxUACQmJISELAO0CABUACQmJISELAO0CAAgAAwnPFE0gAJYAAAAA.Liquorish:BAAALgAECgEJAQABLgAFFAYJIgAVAFMdAA==.Lirathiel:BAABLgAECn8VAAMdAAcJiARUPABoAAAHAAQJfgNWMQF4AAAdAAUJsgRUPABoAAAAAA==.Litasfk:BAAALgAECgIJAgAAAA==.Liuni:BAABLgAECn8oAAIaAAkJlRQYHwCrAQAaAAkJlRQYHwCrAQAAAA==.Liyin:BAAALgAECgQJCQABLgAECgkJKwAEAIEOAA==.',
Lo='Lobopeste:BAABLgAECn9GAAIZAAkJTgv5IABIAQAZAAkJTgv5IABIAQAAAA==.Locknutz:BAAALgADCgMJAwAAAA==.Loracy:BAAALgADCgcJBwAAAA==.Lorantell:BAAALgAECgMJAwAAAA==.Lorelynn:BAABLgAECn8qAAICAAkJUQ3vVQCaAQACAAkJUQ3vVQCaAQAAAA==.',
Lu='Luci:BAABLgAECn8YAAQVAAgJ6RJtTwCUAQAVAAgJkxJtTwCUAQAIAAMJ1Q7+LgBDAAAmAAEJAAAehQAAAAABLgAFFAMJBAADAAAAAA==.Lucìan:BAACLgAFFH8FAAIYAAIJtRNLTwB+AAAYAAIJtRNLTwB+AAAuAAQKfyUAAhgACAmIIcwMAPUCABgACAmIIcwMAPUCAAAA.Ludociel:BAAALgAECgQJBQAAAA==.Lunaclair:BAACLgAFFH8WAAIQAAQJ4gtKegANAQAQAAQJ4gtKegANAQAuAAQKf2UAAxAACQlUHaYlAGsCABAACQlUHaYlAGsCABkABwmNELMpAAcBAAAA.Lunadrus:BAABLgAECn8mAAIEAAgJoglytAAXAQAEAAgJoglytAAXAQAAAA==.Lunarielle:BAACLgAFFH8bAAIOAAQJCBlVLQBQAQAOAAQJCBlVLQBQAQAuAAQKfyEAAg4ACAkXHMYVAIkCAA4ACAkXHMYVAIkCAAAA.',
Ly='Lyriaa:BAAALgADCgYJCwAAAA==.',
Ma='Macalatraz:BAAALgAECgMJBwAAAA==.Macfly:BAABLgAECn8zAAIOAAkJrRo/KQA1AgAOAAkJrRo/KQA1AgAAAA==.Madmeatballs:BAAALgAECgEJAQABLgAECgkJKwAEAFEfAA==.Magdala:BAAALgAECgEJAQAAAA==.Magicmissile:BAACLgAFFH8PAAIEAAUJqxG6WgA0AQAEAAUJqxG6WgA0AQAuAAQKfyoAAgQACQlqH04XAMsCAAQACQlqH04XAMsCAAAA.Makgora:BAAALgAECgMJBAABLgAECgYJFgAWAFkhAA==.Makhvan:BAAALgAFFAEJAQAAAA==.Maksoon:BAAALgAFFAIJAwAAAA==.Maladjusted:BAAALgAECgMJBAAAAA==.Malevalous:BAAALgAECgQJBAAAAA==.Maléfique:BAAALgAECgEJAQAAAA==.Mancath:BAAALgAECgkJCwAAAA==.Maplè:BAAALgAECgIJAwABLgAECggJIwAJAKITAA==.Mar:BAAALgADCgMJAwAAAA==.Marlei:BAAALgADCgQJBAABLgAECgkJKwAEAIEOAA==.Marqose:BAAALgADCgcJDgABLgAECgMJBgADAAAAAA==.Matan:BAAALgADCgUJBQAAAA==.',
Me='Medena:BAAALgADCgcJBwAAAA==.Meeko:BAAALgAFFAIJBAABLgAFFAgJIgAgAAQhAA==.Melfie:BAABLgAECn8wAAIEAAkJABybIACZAgAEAAkJABybIACZAgAAAA==.Meliadoul:BAABLgAECn8fAAIEAAkJwAsDcACXAQAEAAkJwAsDcACXAQAAAA==.Mellyndra:BAABLgAECn88AAIKAAkJ3x7iCQDsAgAKAAkJ3x7iCQDsAgAAAA==.Mercüry:BAAALgAECgEJBAAAAA==.Mezhren:BAAALgAECgYJCwAAAA==.',
Mh='Mhoramsgirl:BAAALgADCggJCwAAAA==.',
Mi='Midoriya:BAACLgAFFH8IAAMGAAMJHQdBKgCfAAAGAAMJHQdBKgCfAAAFAAMJyQsaQwCMAAAuAAQKfyMAAwYACQlnEcguAEsBAAYACAkvEsguAEsBAAUABQmQEd+AAJQAAAAA.Mistjack:BAABLgAFFH8LAAIFAAUJthE8JwAlAQAFAAUJthE8JwAlAQAAAA==.',
Mo='Momdad:BAACLgAFFH8SAAINAAUJ6xfNEgAwAQANAAUJ6xfNEgAwAQAuAAQKfzQAAg0ACQnWIIIHAKYCAA0ACQnWIIIHAKYCAAAA.Mongaux:BAAALgADCgQJBQAAAA==.Monkey:BAAALgAECgQJCgAAAA==.Morrígán:BAAALgADCgUJBQAAAA==.Moxi:BAAALgADCggJDwAAAA==.',
Mu='Muamman:BAAALgAECgMJAwAAAA==.Murda:BAAALgADCgYJCgAAAA==.Murphysflaw:BAAALgADCgUJCAAAAA==.Mutegen:BAAALgAFFAEJAQAAAA==.',
Mx='Mxhealeryduf:BAAALgAECgIJAgAAAA==.',
My='Mystallian:BAAALgAECgQJCQAAAA==.Mystí:BAEALgAFFAIJAgABLgAECgkJLwABADobAA==.Mythicplus:BAAALgAECgcJEQAAAA==.Mythosaur:BAAALgADCgEJAQAAAA==.',
['Mé']='Mélisande:BAAALgADCgQJBgAAAA==.Mémnoc:BAAALgAECgMJAwAAAA==.',
Na='Nadarien:BAAALgAECgYJDQAAAA==.Nadyia:BAAALgADCgEJAQAAAA==.Nailah:BAAALgADCgcJCwAAAA==.Nannergoat:BAAALgADCgMJAwAAAA==.Nardssenpai:BAAALgAFFAIJAgAAAA==.Nastymikey:BAABLgAECn8bAAIfAAgJNx13BwBzAgAfAAgJNx13BwBzAgAAAA==.Nazdormu:BAABLgAECn8gAAIgAAgJIQQcHwD6AAAgAAgJIQQcHwD6AAAAAA==.',
Ne='Nefarious:BAAALgAECgcJDgAAAA==.Neisen:BAABLgAECn8yAAMKAAkJ9RfgEACNAgAKAAkJ9RfgEACNAgAHAAUJBwKc+gCeAAAAAA==.Neocold:BAAALgAECgEJAQAAAA==.Neptune:BAAALgADCgYJBgAAAA==.',
No='Norna:BAAALgADCgcJDwAAAA==.Noz:BAAALgADCgkJCQAAAA==.',
Nu='Nufonewhodis:BAABLgAECn8WAAIWAAYJWSF1HQATAgAWAAYJWSF1HQATAgAAAA==.',
Ny='Nykolas:BAAALgAECgEJAQAAAA==.Nymofthedead:BAABLgAECn8wAAMQAAkJPyQVBgBHAwAQAAkJPyQVBgBHAwARAAUJyRMuGgD7AAAAAA==.',
Oa='Oakgrove:BAAALgADCgUJBQAAAA==.',
Om='Ombraless:BAAALgADCgMJAwABLgAECgQJCAADAAAAAA==.',
On='Oneforall:BAAALgAECgkJDgAAAA==.',
Op='Ophrizhani:BAAALgAECgMJAwAAAA==.',
Or='Orangegrove:BAAALgAECgYJBQAAAA==.Orpheal:BAAALgAECgUJBQAAAA==.Orphen:BAAALgAECgMJAwAAAA==.',
Os='Osìrìs:BAAALgAECgQJCwABLgAFFAIJBQAYALUTAA==.',
Pa='Paddleball:BAAALgADCgQJBAAAAA==.Paladouin:BAAALgAECgYJEwAAAA==.Pandammy:BAAALgAECgkJBQAAAA==.Pantro:BAABLgAECn8hAAMcAAkJyRfbCAA2AgAcAAkJyRfbCAA2AgAbAAEJAAA1kAAAAAAAAA==.Papalion:BAABLgAECn8dAAIOAAcJ2wyAewBDAQAOAAcJ2wyAewBDAQAAAA==.Paragas:BAAALgADCgkJEAAAAA==.Pawbs:BAAALgAECgQJEwAAAA==.',
Pe='Peanuts:BAAALgADCgcJBwAAAA==.Peoplehugger:BAAALgADCgMJAwAAAA==.',
Pi='Pickleburger:BAAALgAECgEJAQAAAA==.Pinkkrayen:BAAALgADCgkJCwAAAA==.Pinklilydrd:BAAALgAECgUJDwAAAA==.',
Pl='Plaindonut:BAABLgAECn8YAAMYAAcJCyLrEwCpAgAYAAcJCyLrEwCpAgAjAAEJowg4jAAxAAAAAA==.',
Po='Porple:BAABLgAECn8VAAINAAgJQQmaKQBTAQANAAgJQQmaKQBTAQAAAA==.',
Pr='Priestdrago:BAAALgADCgUJBQAAAA==.Prissidebow:BAAALgAECgMJCQAAAA==.',
Pu='Puddinpie:BAAALgADCgEJAQAAAA==.',
Qu='Quartz:BAAALgAFFAEJAQABLgAFFAMJEAASAIAkAA==.',
Ra='Rahzule:BAAALgADCgYJBwAAAA==.Ralynne:BAACLgAFFH8HAAILAAMJwA1PNgCuAAALAAMJwA1PNgCuAAAuAAQKfy4AAgsACAkzFJEsAI8BAAsACAkzFJEsAI8BAAAA.Raskus:BAAALgADCgUJBQAAAA==.Ravenbrook:BAACLgAFFH8dAAISAAUJvCZfCADRAQASAAUJvCZfCADRAQAuAAQKfyMAAxIACAlbJXsEAGIDABIACAlbJXsEAGIDABcAAQkwIA1lAFMAAAAA.Rawrr:BAABLgAECn8iAAImAAgJXAubKAAyAQAmAAgJXAubKAAyAQAAAA==.Rawrxd:BAAALgAECgEJAgABLgAECggJDgADAAAAAA==.Raxie:BAACLgAFFH8hAAMeAAUJuRglGwB/AQAeAAUJuRglGwB/AQAnAAEJBQ3SFABRAAAuAAQKfy0ABB4ACQnXGlcOAIYCAB4ACQnXGlcOAIYCACcABwnIE0gtAGwBABQAAQkBBPGHACgAAAAA.Razeth:BAABLgAECn8VAAINAAYJ8BavLQA5AQANAAYJ8BavLQA5AQAAAA==.',
Re='Reanne:BAAALgAECgYJEAAAAA==.Rebecka:BAAALgAECgQJBAAAAA==.Res:BAAALgAECgYJCwAAAA==.Rescorla:BAAALgAECgkJDAAAAA==.Rethali:BAAALgADCgQJAgAAAA==.Reysola:BAAALgAECgEJAQABLgAECgIJAgADAAAAAA==.Rezr:BAAALgAECggJDgAAAA==.',
Rh='Rhixa:BAAALgADCgUJBQAAAA==.Rhymunky:BAAALgAFFAEJAQAAAA==.',
Ri='Rifthor:BAABLgAECn8WAAQcAAYJYAy6LACtAAAcAAUJxQu6LACtAAAbAAMJKQ83RwCFAAAYAAIJsAJJ3AAmAAAAAA==.Rillx:BAAALgADCgQJBgAAAA==.Ripmxi:BAABLgAECn8vAAIEAAkJAhMfVgDXAQAEAAkJAhMfVgDXAQAAAA==.',
Ro='Robinski:BAAALgADCgEJAQAAAA==.Robotiss:BAAALgADCgIJAgAAAA==.Rocco:BAAALgADCgYJBwAAAA==.Rodevon:BAAALgADCggJCAAAAA==.Roknasaurus:BAAALgADCgUJCAAAAA==.Romani:BAAALgADCgYJBgAAAA==.Romeo:BAAALgAECgQJBAAAAA==.Ronaldreagnt:BAAALgAECgcJEQAAAA==.',
Ru='Runecat:BAABLgAFFH8KAAMjAAQJbQQ8LwDAAAAjAAQJbQQ8LwDAAAAYAAMJVQQQTwB/AAAAAA==.Runelight:BAACLgAFFH8IAAMeAAMJOQFEOwCFAAAeAAMJOQFEOwCFAAAnAAIJsgFBNQBbAAAuAAQKfxwABB4ACAlQFAMhAMMBAB4ABwmbFAMhAMMBABQABgn3CqA+APEAACcAAwkQBf5pAHAAAAEuAAUUBAkKACMAbQQA.Runeshock:BAAALgAECgYJBgABLgAFFAQJCgAjAG0EAA==.Runestick:BAAALgAECgIJAgABLgAFFAQJCgAjAG0EAA==.Rupertgiless:BAACLgAFFH8RAAICAAYJpg7dJACqAQACAAYJpg7dJACqAQAuAAQKfyYAAgIACQl0G30iAIsCAAIACQl0G30iAIsCAAAA.',
Sa='Sabeckya:BAAALgAECgQJCgAAAA==.Sacksmasher:BAAALgADCgcJDwAAAA==.Sampleshrimp:BAAALgADCgEJAgAAAA==.Saphyla:BAAALgADCgcJDAAAAA==.Sappheire:BAAALgAECgYJBgAAAA==.Sarcastyx:BAAALgAECgcJCAAAAA==.Sarrod:BAAALgADCgUJBQAAAA==.Saxines:BAABLgAECn8aAAIUAAYJ4w/hNAAqAQAUAAYJ4w/hNAAqAQAAAA==.',
Sc='Scaliefox:BAAALgAECgIJAgABLgAECgkJPAAKAN8eAA==.Scarl:BAAALgADCgUJBQAAAA==.Schwarznacht:BAAALgADCgUJBQAAAA==.Schwarzwölf:BAAALgADCgYJCwAAAA==.Sconzil:BAAALgAECggJDAAAAA==.Scoots:BAAALgADCgQJBAAAAA==.Scrubs:BAAALgAECgYJDAAAAA==.Scrubsevoker:BAAALgAECgQJCQAAAA==.Scumbum:BAAALgADCgIJAgAAAA==.Scyllo:BAAALgAECgQJBgAAAA==.',
Se='Seekndestroy:BAABLgAECn8VAAILAAcJcQf8VADhAAALAAcJcQf8VADhAAAAAA==.Selige:BAAALgAECgQJBAAAAA==.',
Sg='Sgtcuunt:BAAALgADCgcJBwAAAA==.',
Sh='Shackled:BAAALgAECgUJCwAAAA==.Shaenicor:BAAALgADCgIJAgAAAA==.Shankkerz:BAAALgAECgcJCAAAAA==.Shelbo:BAAALgAECgEJAQAAAA==.Shmolda:BAAALgADCgYJBwAAAA==.Shortshammy:BAAALgAECgEJAQABLgAFFAMJCwAEACUJAA==.Shror:BAAALgADCgEJAQABLgAECgUJBQADAAAAAA==.',
Si='Sicarune:BAAALgAECgUJBgABLgAFFAQJCgAjAG0EAA==.Siiegrand:BAABLgAECn8VAAIdAAcJhRAQJQDpAAAdAAcJhRAQJQDpAAAAAA==.Silentswag:BAABLgAECn8VAAIWAAcJLxRRIACPAQAWAAcJLxRRIACPAQAAAA==.Sindrane:BAAALgAECgMJAwABLgAFFAMJBwAZAIAQAA==.Sitzho:BAAALgADCgUJCAAAAA==.',
Sk='Skeleton:BAAALgAECgIJAgAAAA==.Skybringer:BAABLgAECn9AAAIHAAgJsAxVigBZAQAHAAgJsAxVigBZAQAAAA==.Skyee:BAABLgAECn8qAAMGAAkJvx0LDAC6AgAGAAkJvx0LDAC6AgAFAAMJGxS9eACpAAAAAA==.Skylos:BAAALgAECgEJAgAAAA==.',
Sl='Slowburn:BAAALgAECgIJAgABLgAFFAMJBAADAAAAAA==.',
Sm='Smexibiotch:BAAALgADCgYJBgABLgAECgIJAgADAAAAAA==.',
So='Soapscum:BAAALgADCgQJBAAAAA==.Soarphium:BAAALgAECgIJAgABLgAFFAcJHAAWAMEOAA==.Solararc:BAAALgADCgEJAgAAAA==.Soleana:BAAALgAECgYJBQAAAA==.Sombra:BAAALgAECgMJBwABLgAECgcJDgADAAAAAA==.Sonicast:BAAALgAECgYJCQAAAA==.Sooie:BAAALgAECgYJEgAAAA==.Soramian:BAAALgADCgcJEgAAAA==.Soulcacher:BAACLgAFFH8HAAMZAAMJgBCuLACSAAAQAAMJ6w1togDQAAAZAAMJlwmuLACSAAAuAAQKfzIAAxAACQmqFKFLABACABAACAknFqFLABACABkACAm9D8cdAGYBAAAA.Soxxy:BAAALgAECgEJAQABLgAFFAMJBAADAAAAAA==.',
Sp='Spellgunner:BAABLgAECn8VAAIEAAgJPxvMXwC+AQAEAAgJPxvMXwC+AQAAAA==.Spinsaround:BAAALgADCgEJAQAAAA==.',
St='Stormwulf:BAAALgADCgUJBQABLgAECgYJGAAFAGYYAA==.Stormyprissi:BAAALgAECgQJDAAAAA==.Strombjorn:BAABLgAECn8jAAMJAAgJohOdSACIAQAJAAgJohOdSACIAQALAAUJwQxCYQC9AAAAAA==.',
['Sø']='Sølaria:BAAALgAECgEJAQAAAA==.',
Ta='Tasireth:BAAALgADCgcJBwAAAA==.',
Te='Tessi:BAACLgAFFH8HAAIEAAMJrgLQmgCYAAAEAAMJrgLQmgCYAAAuAAQKfxcAAgQABwm3D4KSAFABAAQABwm3D4KSAFABAAAA.',
Th='Thalrian:BAAALgAFFAEJAQABLgAFFAMJBwASAFscAA==.Thefailnym:BAAALgAECggJDQAAAA==.Theory:BAAALgAECgcJDQABLgAFFAIJBgAQACAfAA==.Theylive:BAABLgAECn8dAAIYAAkJJw/dNADFAQAYAAkJJw/dNADFAQAAAA==.Thondrin:BAAALgAECgYJCwAAAA==.Thordanil:BAAALgAECgUJBwAAAA==.Thrashedass:BAAALgADCgEJAQAAAA==.',
Ti='Tigerlilliy:BAAALgADCgYJEAAAAA==.Timerek:BAAALgADCgIJAgAAAA==.',
To='Toawulf:BAAALgAECgQJCAABLgAECgYJGAAFAGYYAA==.Toetickla:BAAALgAECgEJAgAAAA==.Tokifuji:BAAALgAECgIJBAABLgAECgQJEwADAAAAAA==.Toranaar:BAAALgAECgcJBwAAAA==.Toya:BAABLgAECn80AAIWAAkJZRy7CgB1AgAWAAkJZRy7CgB1AgAAAA==.',
Tr='Trenazen:BAAALgADCgkJCgAAAA==.Trevain:BAAALgAECgEJAgAAAA==.Trimasdrood:BAAALgADCgMJAwAAAA==.Trivia:BAAALgAECgYJDwAAAA==.Trundle:BAAALgAECgEJAwAAAA==.Truthordare:BAABLgAECn8qAAIBAAcJcgsXFwDmAAABAAcJcgsXFwDmAAAAAA==.Trysla:BAAALgAECgEJAQAAAA==.',
Tu='Turtei:BAAALgAECgEJAQABLgAFFAgJKgAGAFomAA==.Turtl:BAACLgAFFH8qAAIGAAgJWiZNAAAaAwAGAAgJWiZNAAAaAwAuAAQKfysAAgYACQnmJjcAAPgDAAYACQnmJjcAAPgDAAAA.',
Tw='Twoevil:BAAALgADCgkJCQAAAA==.Twohoof:BAAALgADCgEJAQAAAA==.Twosar:BAAALgADCgEJAQAAAA==.',
Tx='Txìewtkuä:BAAALgADCgkJCQAAAA==.',
Ty='Tyryn:BAAALgADCgMJBAAAAA==.',
Ug='Uglydragon:BAAALgAECgcJDAAAAA==.Uglypally:BAAALgADCgkJCQAAAA==.Uglypetguy:BAAALgAECgIJAgAAAA==.Uglyrogue:BAAALgAECgQJAgAAAA==.Uglyshaman:BAAALgAECgEJAgAAAA==.',
Ul='Ulgrym:BAAALgAECgMJBQAAAA==.Ultimatia:BAAALgADCgMJBwAAAA==.',
Un='Unbalancéd:BAABLgAECn8iAAIFAAYJRiJfGQBHAgAFAAYJRiJfGQBHAgAAAA==.',
Va='Vaeadin:BAAALgAECgEJAQAAAA==.Vahra:BAAALgAECgMJCQAAAA==.Valanther:BAAALgAECgMJAwAAAA==.Valantis:BAAALgADCgEJAQAAAA==.Valgaskav:BAABLgAECn8uAAIHAAkJZiOxCQAZAwAHAAkJZiOxCQAZAwAAAA==.Valimond:BAAALgAECgEJAQABLgAECgYJGAAFAGYYAA==.Valric:BAAALgAECgUJBQAAAA==.Vanarrath:BAAALgADCgYJBwAAAA==.Vandryelle:BAAALgADCgIJAgAAAA==.Varge:BAAALgADCgMJAwAAAA==.Varrathos:BAAALgAECgMJBAAAAA==.Vayl:BAAALgAECgMJAwAAAA==.',
Ve='Vegasnight:BAAALgAECgYJDQAAAA==.Velisa:BAAALgADCgYJBgAAAA==.Vellaria:BAAALgADCgUJBwAAAA==.Ventrue:BAAALgADCgMJAwAAAA==.Verdesoul:BAAALgAECgcJEAABLgAECggJFwABAHQIAA==.Vesyra:BAAALgAECgQJBQAAAA==.',
Vi='Viralyn:BAAALgAECgEJAQABLgAECgkJKAAaAJUUAA==.Vixøn:BAAALgAECgMJBgAAAA==.',
Vo='Voidluck:BAABLgAECn8SAAIVAAgJvxBkdABIAQAVAAgJvxBkdABIAQAAAA==.Voker:BAAALgAECgMJCQABLgAECgQJEwADAAAAAA==.Voladis:BAAALgAECgYJDQAAAA==.Voladro:BAAALgAECgQJBAAAAA==.Volanie:BAAALgAECgMJAQAAAA==.Volos:BAACLgAFFH8FAAIHAAIJ4w2ejACQAAAHAAIJ4w2ejACQAAAuAAQKfy0AAgcACAk5Fl1XAMMBAAcACAk5Fl1XAMMBAAAA.Vordaman:BAABLgAECn80AAIQAAkJYRPrTADZAQAQAAkJYRPrTADZAQAAAA==.',
Vy='Vynír:BAACLgAFFH8YAAICAAcJ4RxdFgD+AQACAAcJ4RxdFgD+AQAuAAQKfy4AAwIACQmgI1YJAAcDAAIACQk+I1YJAAcDAAEABQkHI40NAOwBAAAA.',
Wa='Waghoba:BAECLgAFFH8qAAIcAAcJ/iGbAABeAgAcAAcJ/iGbAABeAgAuAAQKfyQAAhwACQnMIScGAJwCABwACQnMIScGAJwCAAAA.Waito:BAAALgAECgQJBwAAAA==.Wandä:BAABLgAECn85AAQaAAkJQB7iCQCTAgAaAAkJcRziCQCTAgAGAAkJMROcGgDYAQAFAAcJMBBzQgBbAQAAAA==.Wardriccan:BAAALgAECggJDgAAAA==.Warfle:BAAALgADCgYJBgAAAA==.Warhound:BAAALgADCgcJBwAAAA==.Warrionomous:BAACLgAFFH8PAAISAAUJLBEXIgAnAQASAAUJLBEXIgAnAQAuAAQKfxsAAhIACAkeGw4bABQCABIACAkeGw4bABQCAAEuAAUUBQkPAAQAqxEA.Washu:BAACLgAFFH8LAAImAAQJFxDMEQASAQAmAAQJFxDMEQASAQAuAAQKf0IAAyYACQnaHxIGANYCACYACQnaHxIGANYCAAgAAwlMC1khAHkAAAAA.',
Wh='Whimlock:BAAALgADCgQJBAABLgAFFAMJBwAEAOUcAA==.Whimzie:BAAALgAECgEJAgABLgAFFAMJBwAEAOUcAA==.Whorphium:BAAALgAECggJEgABLgAFFAcJHAAWAMEOAA==.',
Wi='Willow:BAAALgAECgYJCwAAAA==.Winterous:BAAALgAECgcJDAAAAA==.',
Wo='Wonderbread:BAACLgAFFH8FAAIHAAMJgANmiACYAAAHAAMJgANmiACYAAAuAAQKfzwAAgcACQn3Fdg3ACACAAcACQn3Fdg3ACACAAAA.',
Wr='Wrager:BAAALgAECgUJBgAAAA==.Wrathofzaun:BAAALgAECgYJDwAAAA==.',
Wy='Wylest:BAAALgADCgcJBwAAAA==.Wynch:BAAALgAECgkJCQAAAA==.',
['Wâ']='Wârwôlf:BAABLgAECn8pAAMOAAkJHCQtBwAiAwAOAAkJHCQtBwAiAwAMAAQJ+BWyVQDzAAAAAA==.',
Xe='Xenan:BAABLgAECn82AAIHAAkJOxYbOQAcAgAHAAkJOxYbOQAcAgAAAA==.',
Xt='Xtrolldinary:BAABLgAECn8UAAIYAAQJ7AwVjACbAAAYAAQJ7AwVjACbAAAAAA==.',
Xv='Xvp:BAAALgAECgQJCgAAAA==.',
Xy='Xylophy:BAABLgAECn8rAAIIAAkJPBTICQDJAQAIAAkJPBTICQDJAQAAAA==.',
Ye='Yeastmode:BAACLgAFFH8ZAAIOAAUJNREKQAAnAQAOAAUJNREKQAAnAQAuAAQKfy4AAg4ACAksHZwlAEcCAA4ACAksHZwlAEcCAAAA.',
Yo='Yonah:BAAALgAECgYJDAAAAA==.',
Yu='Yurc:BAABLgAECn8nAAIhAAkJeBm3CQBVAgAhAAkJeBm3CQBVAgAAAA==.',
Za='Zademan:BAAALgAECgUJBwAAAA==.Zappyu:BAAALgAECgkJBQABLgAECgkJCQADAAAAAA==.Zarkas:BAAALgAECgUJBgAAAA==.',
Ze='Zeebra:BAAALgAECgcJEQAAAA==.Zeg:BAAALgAFFAIJAwAAAA==.Zega:BAAALgAFFAEJAQAAAA==.Zegafur:BAABLgAECn8yAAIYAAgJrhwRIABDAgAYAAgJrhwRIABDAgAAAA==.Zeruk:BAABLgAECn8XAAMGAAcJjwJ1YACOAAAGAAYJlAJ1YACOAAAFAAcJpQELkABuAAAAAA==.',
Zi='Zillionbúcks:BAACLgAFFH8cAAIHAAgJWxN+DAAIAgAHAAgJWxN+DAAIAgAuAAQKfxsAAgcACQmvHtEtAGwCAAcACQmvHtEtAGwCAAAA.',
Zu='Zullee:BAAALgADCgkJEgAAAA==.',
Zy='Zylcat:BAAALgAECgYJDAAAAA==.',
['Zê']='Zêddicus:BAABLgAECn80AAMBAAkJtCClAQDDAgABAAkJtCClAQDDAgACAAUJHwgM1ACyAAAAAA==.',
['Áq']='Áquafina:BAABLgAECn88AAIEAAkJpg5qWwDIAQAEAAkJpg5qWwDIAQAAAA==.',
['Åñ']='Åñgêl:BAAALgAECgIJAgAAAA==.',
['Îv']='Îvan:BAAALgADCggJCAAAAA==.',
['Ðö']='Ðö:BAABLgAECn82AAISAAkJ6R2uCwCrAgASAAkJ6R2uCwCrAgAAAA==.',
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
