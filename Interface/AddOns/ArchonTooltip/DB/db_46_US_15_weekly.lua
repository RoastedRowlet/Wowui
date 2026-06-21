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

local lookup = {'Warlock-Destruction','Warlock-Demonology','DeathKnight-Frost','Mage-Frost','Monk-Mistweaver','Monk-Windwalker','Paladin-Retribution','DemonHunter-Vengeance','Shaman-Restoration','Paladin-Holy','Unknown-Unknown','Shaman-Elemental','Hunter-Marksmanship','Hunter-Survival','Hunter-BeastMastery','Evoker-Augmentation','DeathKnight-Unholy','Warrior-Fury','DeathKnight-Blood','Evoker-Devastation','Priest-Holy','DemonHunter-Devourer','Rogue-Subtlety','Warrior-Arms','Druid-Restoration','Monk-Brewmaster','Druid-Guardian','Druid-Feral','Paladin-Protection','Priest-Discipline','Shaman-Enhancement','Evoker-Preservation','Warrior-Protection','Rogue-Outlaw','Druid-Balance','Mage-Fire','Warlock-Affliction','DemonHunter-Havoc','Priest-Shadow',}
local provider = {region='US',realm='Anvilmar',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aaril:BAAALgAECgYJIQAAAQ==.',
Ab='Abrams:BAAALgADCgYJCgAAAA==.',
Ad='Adel:BAAALgAECgYJCAAAAA==.',
Ae='Aelitha:BAABLgAECn8ZAAMBAAYJCQZ2OQDOAAABAAYJxAR2OQDOAAACAAYJsQQV0gCwAAAAAA==.',
Ak='Akaishi:BAAALgADCgIJAgAAAA==.Akali:BAAALgAFFAIJAwABLgAFFAMJBQADABIPAA==.Akina:BAAALgAECgQJBAABLgAECgkJKwAEAIEOAA==.',
Al='Alanie:BAAALgAECgIJAgAAAA==.Alathiana:BAAALgADCgUJCAAAAA==.Alcweaver:BAABLgAECn8dAAMFAAcJgiBKIQASAgAFAAcJgiBKIQASAgAGAAYJgA8TQQD7AAAAAA==.Alecto:BAAALgAECgMJAwAAAA==.Alindia:BAAALgAECgQJCgABLgAECgkJKwAEAIEOAA==.Alirrayia:BAAALgAECgQJBQAAAA==.Alirrayiia:BAACLgAFFH8IAAIHAAMJ+AHVigCcAAAHAAMJ+AHVigCcAAAuAAQKfyoAAgcACQlwFG9CAP8BAAcACQlwFG9CAP8BAAAA.Alkri:BAAALgADCgMJAwAAAA==.Allari:BAAALgAECgYJEwAAAA==.Allikazam:BAAALgADCgYJGAAAAA==.Allystar:BAAALgAECgQJDwAAAA==.Altheia:BAAALgAECgQJBAAAAA==.Alvidor:BAABLgAECn9JAAIEAAkJqQYHiABnAQAEAAkJqQYHiABnAQAAAA==.',
Am='Ambrose:BAAALgAECgcJBwAAAA==.Ameria:BAAALgADCgUJBQAAAA==.Amexican:BAAALgAECgEJAQAAAA==.Amybabe:BAAALgAFFAIJAgAAAA==.',
An='Anastos:BAAALgAECgUJBQAAAA==.Andydufresne:BAAALgAECgQJDwABLgAECgkJUQAIAL8lAA==.Angryqueer:BAAALgADCgEJAQAAAA==.',
Ao='Aowl:BAAALgAECgcJCwAAAA==.',
Ap='Apocketheory:BAAALgADCgIJAgAAAA==.Apolloerosb:BAAALgAECgYJDwABLgAECgcJKQAJAOAbAA==.Apolloerosp:BAAALgAECgQJCQABLgAECgcJKQAJAOAbAA==.Apollossham:BAABLgAECn8pAAIJAAcJ4BuVIwA5AgAJAAcJ4BuVIwA5AgAAAA==.',
Ar='Arkanaun:BAABLgAECn8dAAMHAAYJRBdpcwCUAQAHAAYJRBdpcwCUAQAKAAUJvRTqTAAHAQAAAA==.',
As='Ashes:BAAALgAECgcJAQAAAA==.Ashrán:BAAALgAECgYJCQAAAA==.Ashyluna:BAAALgAECgQJBAAAAA==.Astianna:BAAALgADCgMJAwAAAA==.',
Au='Aule:BAAALgAECgIJAwAAAA==.Aurinia:BAAALgADCgQJAgAAAA==.Auroradinlee:BAAALgAECgkJBgAAAA==.Aurore:BAAALgAECgQJCgAAAA==.',
Av='Avradea:BAAALgAECgEJAQABLgAECgkJKwAEAIEOAA==.',
Az='Azareth:BAAALgADCggJCAAAAA==.',
Ba='Baconatorr:BAAALgAECgQJBQAAAA==.Bagelbags:BAAALgADCgEJAQAAAA==.Bahler:BAAALgADCgUJBQABLgAECgMJAwALAAAAAA==.Baji:BAACLgAFFH8FAAIJAAMJKB47NwAFAQAJAAMJKB47NwAFAQAuAAQKfzsAAwkACQktIvIHADADAAkACQktIvIHADADAAwABQn+FVdKAAsBAAAA.Baklan:BAAALgAECgMJAwAAAA==.Barefaall:BAACLgAFFH8WAAMNAAcJoBcsCgDCAQANAAcJExYsCgDCAQAOAAQJ/hAtEQA9AQAuAAQKf0QAAw0ACQllJOUAAD4DAA0ACQllJOUAAD4DAA8ABAmFENyqAO0AAAAA.Barefall:BAACLgAFFH8KAAIOAAMJYhAmHwDcAAAOAAMJYhAmHwDcAAAuAAQKfxgAAg4ACQn1EQYXAOkBAA4ACQn1EQYXAOkBAAEuAAUUBwkWAA0AoBcA.Barefalls:BAACLgAFFH8OAAIOAAMJlhyGHQDlAAAOAAMJlhyGHQDlAAAuAAQKfzAAAw4ACQk9HwAHAK8CAA4ACQk9HwAHAK8CAA0AAQmMAaCWACIAAAEuAAUUBwkWAA0AoBcA.Barelywolf:BAABLgAECn8mAAMGAAkJwB+FEQA4AgAGAAcJ5CCFEQA4AgAFAAgJLxfZIgAIAgABLgAFFAMJBgAQACwLAA==.Bashira:BAABLgAECn8eAAIPAAkJsAopWQCZAQAPAAkJsAopWQCZAQAAAA==.Bast:BAACLgAFFH8IAAMRAAMJPwdctQC8AAARAAMJPwdctQC8AAADAAEJVgM6LAA4AAAuAAQKfzAAAxEACQlHFtIzAC8CABEACQlHFtIzAC8CAAMABAmJDbMoAI4AAAAA.Bastrillan:BAAALgAECgUJBwAAAA==.',
Be='Bearophe:BAAALgAECgEJAgAAAA==.Beerfist:BAAALgAECgEJAQAAAA==.Belfor:BAAALgAECgMJAwAAAA==.Bellock:BAAALgAECgMJAwAAAA==.Bendroyd:BAAALgAECgIJAgAAAA==.Benisbagina:BAAALgADCggJCQAAAA==.Bergonator:BAABLgAECn8gAAISAAYJcRC9TwBpAQASAAYJcRC9TwBpAQAAAA==.Berrodiah:BAABLgAECn8UAAQDAAgJ8ROZAAAPAQATAAgJKxAWIABTAQADAAUJehSZAAAPAQARAAMJmgsCDAGdAAABLgAECggJFgAUALUYAA==.Bettyswalls:BAAALgAECgMJAwAAAA==.Beyarago:BAAALgAECgcJCwAAAA==.',
Bh='Bheiroth:BAACLgAFFH8FAAIVAAMJ3iCcFAAfAQAVAAMJ3iCcFAAfAQAuAAQKfzIAAhUACQlIJHMEADsDABUACQlIJHMEADsDAAAA.',
Bi='Birds:BAAALgAECgkJEQAAAA==.',
Bl='Bladeygaga:BAABLgAECn85AAIWAAkJpR+jCwDqAgAWAAkJpR+jCwDqAgAAAA==.Blasé:BAAALgAECgcJCAAAAA==.Blazingblood:BAAALgADCgUJAQAAAA==.Bloodknight:BAAALgADCgYJCQAAAA==.Bluekrayen:BAAALgAECgUJCAAAAA==.Bluett:BAAALgAECgMJCQAAAA==.Bláckøut:BAAALgADCgYJDAAAAA==.',
Bo='Bodhi:BAABLgAECn8WAAIXAAcJNhAQJwDAAQAXAAcJNhAQJwDAAQAAAA==.Bogertus:BAACLgAFFH8QAAISAAMJgCTQIgApAQASAAMJgCTQIgApAQAuAAQKf0AAAxIACQnSJnwAAIwDABIACQnSJnwAAIwDABgAAgn1HHIpAKUAAAAA.Bonobo:BAAALgAECgYJCQAAAA==.Boomertunes:BAABLgAECn8mAAMCAAkJYxgtJgBFAgACAAkJYxgtJgBFAgABAAIJGwFHVAAAAAAAAA==.',
Br='Brein:BAABLgAECn9QAAIZAAkJ8yW6AADgAwAZAAkJ8yW6AADgAwAAAA==.Brewmaster:BAAALgAECgIJAwAAAA==.Brewwmaster:BAABLgAECn8kAAQTAAkJrBjhFwClAQATAAkJIBXhFwClAQARAAYJtBfWfACKAQADAAEJ+he5FgA2AAAAAA==.Bricklethumb:BAAALgAECgMJAwABLgAECgYJGAAFAGYYAA==.Brickred:BAAALgADCggJDgAAAA==.Brynodd:BAAALgAECgMJCQAAAA==.',
Bu='Bubblybetty:BAAALgAECgEJAQAAAA==.Bucketeer:BAABLgAECn8rAAIEAAkJUR/MHACwAgAEAAkJUR/MHACwAgAAAA==.Buffs:BAAALgADCgEJAQAAAA==.Bullminator:BAAALgAECggJDgAAAA==.Bursona:BAAALgAECgEJAQAAAA==.Butterfree:BAAALgAECgUJDAABLgAFFAEJAQALAAAAAA==.',
Ca='Cards:BAAALgAECgYJCgAAAA==.Carkrash:BAAALgADCgkJGgAAAA==.Casterkang:BAAALgAECgUJCQAAAA==.Catshunter:BAABLgAECn8WAAIPAAcJbxsyQACvAQAPAAcJbxsyQACvAQAAAA==.',
Ce='Celaa:BAABLgAECn8rAAIEAAkJgQ7CXgDDAQAEAAkJgQ7CXgDDAQAAAA==.',
Ch='Chanka:BAABLgAECn8cAAIBAAYJ6gjOHgCzAAABAAYJ6gjOHgCzAAAAAA==.Chantillary:BAAALgAECgMJCQAAAA==.Chargerkang:BAAALgADCgYJBgAAAA==.Chchanges:BAAALgAECgEJAQAAAA==.Cheesy:BAABLgAECn8qAAICAAgJFA1KbgBfAQACAAgJFA1KbgBfAQAAAA==.Chicken:BAAALgAECgYJEgAAAA==.Chonk:BAAALgADCgEJAQAAAA==.Chopzullee:BAABLgAECn8aAAIGAAcJHglgUgC/AAAGAAcJHglgUgC/AAAAAA==.',
Ci='Circii:BAAALgAECgQJBAAAAA==.Cirya:BAAALgAECgUJCQAAAA==.',
Cl='Cleric:BAAALgADCgUJBQAAAA==.Clortho:BAAALgAECgYJEAAAAA==.Clorthö:BAAALgADCgUJBQAAAA==.',
Co='Coljack:BAAALgAECggJCAAAAA==.Colljack:BAACLgAFFH8gAAIKAAcJkRfNDgDOAQAKAAcJkRfNDgDOAQAuAAQKfyEAAwoACQkgIZwJANgCAAoACQkgIZwJANgCAAcABQlOEtO5ABIBAAAA.Coughlin:BAAALgAECgEJAQAAAA==.',
Cr='Crocbait:BAAALgAECgcJEQAAAA==.Cryptoe:BAACLgAFFH8IAAIEAAMJdhR9gQDUAAAEAAMJdhR9gQDUAAAuAAQKfx4AAgQACQnNE0ZKAPwBAAQACQnNE0ZKAPwBAAAA.',
Cu='Cudlsac:BAAALgAECgQJBQAAAA==.',
Da='Daedelus:BAABLgAECn8mAAMWAAgJ8BXQAwDKAAAIAAYJtxGYFAALAQAWAAgJvBXQAwDKAAAAAA==.Daglon:BAAALgAFFAMJBAAAAA==.Dagz:BAAALgAECgQJBAAAAA==.Dakina:BAAALgADCgYJBgAAAA==.Daraedra:BAAALgAECgYJEgAAAA==.Darkenvoid:BAAALgADCgkJDQAAAA==.',
De='Deathslight:BAAALgAECgQJBwAAAA==.Dedaeste:BAAALgADCgUJBwAAAA==.Deeznutticus:BAACLgAFFH8bAAISAAYJKhYUEQB+AQASAAYJKhYUEQB+AQAuAAQKfyEAAxIABwnCIkgYAIkCABIABwnCIkgYAIkCABgAAgkBHdBcAGoAAAAA.Defnotisis:BAABLgAECn8dAAMaAAgJhxTHKABsAQAaAAcJCRbHKABsAQAGAAgJtAs5RADuAAABLgAFFAMJBQADABIPAA==.Defnotkity:BAABLgAFFH8HAAMbAAMJLg5HLABpAAAcAAIJ2QffFwB0AAAbAAIJzBBHLABpAAAAAA==.Demonspud:BAABLgAECn8dAAIWAAcJhRIXZgBaAQAWAAcJhRIXZgBaAQAAAA==.Demotard:BAAALgAECgIJAQAAAA==.Denxster:BAAALgAECgYJDgAAAA==.Dersan:BAABLgAECn8hAAIBAAgJ1AAtPgA0AAABAAgJ1AAtPgA0AAAAAA==.Destriant:BAABLgAECn83AAIdAAkJyxliCgAkAgAdAAkJyxliCgAkAgAAAA==.Devilschant:BAAALgAECgYJCgAAAA==.Devilshadow:BAAALgAECgUJBwABLgAECgYJCgALAAAAAA==.Dewburt:BAAALgADCggJCgAAAA==.Deylia:BAAALgAECgYJEQABLgAFFAYJIgAeAH0ZAA==.',
Di='Dilithia:BAABLgAECn8bAAIRAAYJ0wKVEgGVAAARAAYJ0wKVEgGVAAAAAA==.Dillion:BAAALgAECgYJCAAAAA==.Dinonuggies:BAAALgADCgcJBwAAAA==.Dionin:BAAALgADCgYJCQAAAA==.Dira:BAAALgAFFAIJAgABLgAFFAYJHQAfAK4gAA==.Dirkbanne:BAAALgADCgYJBgAAAA==.',
Do='Dodoubleg:BAAALgAECgYJEAAAAA==.Dominique:BAAALgADCgYJBgAAAA==.Donzilch:BAEALgAECgQJBAAAAA==.Donzilly:BAAALgAECgUJBQAAAA==.Dooberrt:BAAALgAECgIJAgAAAA==.Dooburt:BAABLgAECn8VAAIHAAkJPxLYYQCtAQAHAAkJPxLYYQCtAQAAAA==.Doombringers:BAAALgAECgUJCAAAAA==.',
Dr='Dracaric:BAABLgAECn8rAAIQAAkJEhbWGAAQAgAQAAkJEhbWGAAQAgAAAA==.Draeca:BAAALgAECgMJBgAAAA==.Dragondznut:BAAALgAECgQJBQAAAA==.Drakhar:BAAALgADCgIJAgABLgAECgcJDQALAAAAAA==.Drfrostie:BAABLgAECn8UAAIEAAcJSBIrmgChAQAEAAcJSBIrmgChAQAAAA==.Drgunner:BAAALgAECgcJDwAAAA==.Driatin:BAAALgAFFAEJAQAAAA==.Drkladykikyo:BAABLgAECn8XAAIVAAkJFQOEQQDmAAAVAAkJFQOEQQDmAAAAAA==.Druroo:BAAALgAECgEJAQABLgAFFAQJBwARADUWAA==.Druterr:BAAALgAECgIJAgABLgAECgcJBwALAAAAAA==.',
Du='Dumb:BAACLgAFFH8PAAIgAAUJLAyTBgCJAQAgAAUJLAyTBgCJAQAuAAQKfyMAAiAACAnoG28LAH4CACAACAnoG28LAH4CAAAA.Durø:BAABLgAECn8WAAIWAAgJryLZDAAZAwAWAAgJryLZDAAZAwAAAA==.Duskhunter:BAAALgADCgEJAQAAAA==.',
Dy='Dyanisian:BAAALgADCgYJCAAAAA==.',
['Dè']='Dègenerate:BAACLgAFFH8FAAIhAAMJDBfmFwDbAAAhAAMJDBfmFwDbAAAuAAQKf0IAAiEACQmOIFAEAOICACEACQmOIFAEAOICAAAA.',
Ed='Edagerran:BAAALgADCgkJCQAAAA==.',
Ei='Eilae:BAABLgAECn8fAAIPAAcJnAVECgBoAAAPAAcJnAVECgBoAAAAAA==.Eirhakan:BAAALgAECgQJCAAAAA==.',
El='Elrethyl:BAABLgAECn8WAAIHAAcJXhgedwCAAQAHAAcJXhgedwCAAQAAAA==.Elvanus:BAAALgADCgYJBgAAAA==.Elêktra:BAABLgAECn8tAAIMAAkJuA5bMwBuAQAMAAkJuA5bMwBuAQAAAA==.',
Em='Emet:BAAALgAECgQJCAABLgAECgkJSAAJAEwbAA==.',
Ep='Epicnym:BAAALgAECgYJBwAAAA==.Epicsmoke:BAACLgAFFH8PAAISAAMJDxy+KwAFAQASAAMJDxy+KwAFAQAuAAQKf1kAAhIACQkPJSICAFYDABIACQkPJSICAFYDAAAA.Epidemius:BAAALgAECgkJCgAAAA==.',
Er='Erevan:BAABLgAECn84AAMXAAkJ3Bu5CACbAgAXAAkJ3Bu5CACbAgAiAAEJpwABEAAcAAAAAA==.Erinn:BAAALgAECgMJBAABLgAECgMJBAALAAAAAA==.Eroica:BAAALgADCgYJBwAAAA==.Eronys:BAAALgAFFAIJAQAAAA==.',
Es='Esdeath:BAABLgAECn8tAAMRAAkJDhRDTwDVAQARAAkJDhRDTwDVAQATAAYJWga2PgCVAAAAAA==.',
Et='Etharia:BAAALgADCgUJAwAAAA==.',
Ev='Evilsmeghead:BAAALgADCgEJAQAAAA==.',
Ex='Exiledguy:BAAALgADCgYJBgAAAA==.Extenze:BAACLgAFFH8FAAIWAAMJUhN9YADOAAAWAAMJUhN9YADOAAAuAAQKfygAAhYACQlfHQAaAHgCABYACQlfHQAaAHgCAAAA.',
Ez='Ezykiah:BAAALgAECgYJBwAAAA==.',
Fa='Falconponch:BAAALgADCgEJAQAAAA==.',
Fe='Felbjorn:BAAALgAECgEJAgAAAA==.Felgibson:BAAALgAECgQJBQAAAA==.Felkang:BAAALgADCgkJCQAAAA==.Ferryman:BAABLgAECn8dAAIPAAcJoRPIYACFAQAPAAcJoRPIYACFAQAAAA==.',
Fl='Flingor:BAAALgAECgYJEAAAAA==.Flokha:BAAALgADCgEJAQAAAA==.',
Fo='Forphium:BAACLgAFFH8cAAIXAAcJwQ6lBACkAQAXAAcJwQ6lBACkAQAuAAQKfyAAAhcACQn9IH0NAMQCABcACQn9IH0NAMQCAAAA.',
Fr='Fredolf:BAAALgAECgEJAQAAAA==.Freydís:BAAALgAECgUJCwAAAA==.Freyå:BAAALgAECgIJAgAAAA==.Friarkuck:BAAALgADCggJCAAAAA==.Friedbones:BAAALgAECgMJCQAAAA==.Frostiepal:BAAALgADCgYJBgAAAA==.Frostlilliy:BAAALgADCggJCwAAAA==.',
['Fü']='Fürbie:BAAALgAECgIJAwAAAA==.',
Ga='Gahlina:BAABLgAECn8VAAMJAAcJtBYGMwDnAQAJAAcJtBYGMwDnAQAMAAEJ1wEzlgAeAAAAAA==.Galdorian:BAAALgADCgYJCQABLgAECgkJHgAPALAKAA==.Galynda:BAAALgADCgcJCQAAAA==.Garshan:BAAALgAECgMJAwAAAA==.',
Ge='Genjimain:BAABLgAECn8lAAMZAAkJBhqRHgBKAgAZAAkJBhqRHgBKAgAcAAMJ9wyiNQCHAAAAAA==.Genjí:BAAALgAECgEJAwAAAA==.Geris:BAAALgAECgQJBQAAAA==.Gertruide:BAAALgADCgUJBQAAAA==.',
Gh='Ghendala:BAAALgADCggJEwAAAA==.',
Gi='Gillesmon:BAAALgAFFAEJAQABLgAFFAMJBAALAAAAAA==.Gilleyy:BAAALgAECgQJBQABLgAECgYJFAAUAJodAA==.Gincainn:BAAALgAECgEJAgAAAA==.Gird:BAABLgAECn8oAAIKAAgJ4Q19OABrAQAKAAgJ4Q19OABrAQAAAA==.Girdlock:BAAALgAECgYJBwAAAA==.',
Gl='Glaiveyjones:BAAALgAECgEJAQAAAA==.',
Gn='Gnymesis:BAAALgAECgYJCAAAAA==.',
Go='Goatmonger:BAAALgAECgYJBgAAAA==.Goinpostal:BAAALgAECgIJAgAAAA==.Goldblade:BAAALgAECgkJEwAAAA==.Goodvsevil:BAAALgAECgQJBAAAAA==.Gordek:BAABLgAECn8dAAMHAAkJsRpILQBLAgAHAAkJsRpILQBLAgAKAAIJhBCsdwBfAAAAAA==.Gothitelle:BAAALgAECgIJBwAAAA==.Goöse:BAACLgAFFH8ZAAIRAAYJJh7dAwDEAQARAAYJJh7dAwDEAQAuAAQKfycAAhEACAmDJusGAGsDABEACAmDJusGAGsDAAAA.',
Gr='Grantaron:BAABLgAECn83AAIHAAkJ2iDYGACuAgAHAAkJ2iDYGACuAgAAAA==.Gravarii:BAAALgADCgcJEwAAAA==.Grimskul:BAABLgAECn8zAAMRAAkJkB3DGgCmAgARAAkJkB3DGgCmAgADAAYJDxSUBwCBAQAAAA==.Grindor:BAAALgADCgEJAQAAAA==.Grntitan:BAAALgAECgQJCgAAAA==.Gruid:BAAALgADCgcJDwAAAA==.',
Gu='Guinessbrew:BAAALgAECgEJAQAAAA==.',
Gw='Gwoohoori:BAAALgAECggJEwAAAA==.',
Gy='Gyra:BAAALgAECgYJEQAAAA==.Gyrojetli:BAAALgAECgQJBQAAAA==.',
Ha='Halukari:BAABLgAECn8XAAMbAAcJbSBqFACzAQAbAAcJbSBqFACzAQAjAAEJ8gzahgApAAABLgAFFAYJIgAeAH0ZAA==.Harfnan:BAAALgAECgIJAgAAAA==.Harrin:BAACLgAFFH8HAAIEAAQJoQQneADpAAAEAAQJoQQneADpAAAuAAQKfx0AAgQABwn2D4WjADUBAAQABwn2D4WjADUBAAAA.',
He='Healingwater:BAAALgAECgIJAwAAAA==.Herracles:BAAALgADCgYJGAAAAA==.Hezrel:BAAALgAECgYJCgAAAA==.',
Hi='Hierodule:BAAALgAECgEJAQAAAA==.Hiimriven:BAAALgAECgIJAgABLgAECgYJFgAXAFkhAA==.Hinal:BAABLgAECn8gAAIHAAkJMhtgKABhAgAHAAkJMhtgKABhAgAAAA==.',
Ho='Hojo:BAAALgADCgUJCAAAAA==.Holyenabler:BAABLgAFFH8SAAIdAAMJegwUDwCQAAAdAAMJegwUDwCQAAAAAA==.Honzo:BAAALgADCgkJCQAAAA==.Hootiehoo:BAAALgADCgMJAwAAAA==.',
Hu='Huflunggoo:BAAALgADCgkJDQAAAA==.Huflungpoop:BAABLgAECn80AAIGAAkJqBpcEQA6AgAGAAkJqBpcEQA6AgAAAA==.Hunterborn:BAAALgAFFAIJAgAAAA==.',
Hy='Hypercube:BAAALgAECgQJBwAAAA==.',
['Hè']='Hèalz:BAAALgAECgYJBgABLgAECgkJNgASAOcdAA==.',
Ic='Ickixia:BAAALgADCgQJBAAAAA==.',
Il='Ilkaressa:BAAALgADCgQJBAAAAA==.Illyríá:BAEBLgAFFH8KAAICAAMJQxGDdQDWAAACAAMJQxGDdQDWAAABLgAECgkJMwABAN4dAA==.Ilun:BAAALgAECgIJAgAAAA==.',
Im='Imcruel:BAACLgAFFH8fAAMEAAcJChh2IQD6AQAEAAcJChh2IQD6AQAkAAMJlBR+AwDSAAAuAAQKfzAAAgQACQnNJaAHAEEDAAQACQnNJaAHAEEDAAAA.Imisis:BAAALgAECgYJCQAAAA==.Ims:BAAALgAECggJBQAAAA==.',
In='Ink:BAACLgAFFH8NAAIEAAQJKxGoYwAbAQAEAAQJKxGoYwAbAQAuAAQKfycAAgQABwm2IB5aAM8BAAQABwm2IB5aAM8BAAAA.',
Is='Istaria:BAAALgAECgMJCAAAAA==.Isujr:BAABLgAECn8ZAAIRAAcJ8hIKcQCmAQARAAcJ8hIKcQCmAQAAAA==.',
Ja='Jacaerys:BAAALgADCgYJBgAAAA==.Jackiegan:BAABLgAECn8rAAQaAAkJBSGfBAD7AgAaAAkJBSGfBAD7AgAGAAEJahE0jwBCAAAFAAEJJgel0wAeAAAAAA==.Jackson:BAAALgAECgMJCQAAAA==.Jagerdemon:BAAALgAECgcJCQAAAA==.',
Je='Jerce:BAAALgADCgUJBQAAAA==.Jeryatric:BAAALgADCgcJBwAAAA==.',
Jh='Jhala:BAAALgADCgkJDwAAAA==.',
Ji='Jinnxx:BAAALgAECgMJBAABLgAFFAYJHQAfAK4gAA==.',
Jo='Joshcalc:BAABLgAFFH8GAAIjAAMJNyPcHAA0AQAjAAMJNyPcHAA0AQAAAA==.Joskel:BAABLgAECn8vAAQCAAgJDw1acwBTAQACAAgJiQxacwBTAQAlAAYJMQToFgDIAAABAAIJNgxpMQBYAAAAAA==.',
Ju='Juacqer:BAAALgAECgMJCQAAAA==.Juggarnaut:BAAALgADCgYJCAAAAA==.',
Ka='Kaant:BAABLgAECn9IAAMJAAkJTBvPEQC/AgAJAAkJTBvPEQC/AgAMAAgJ7R1YEwBTAgAAAA==.Kaeni:BAAALgADCgMJAwAAAA==.Kaidevyn:BAABLgAECn86AAMDAAkJbhaqBwAbAgADAAkJbhaqBwAbAgARAAQJWgp5GQGMAAAAAA==.Kaiste:BAAALgADCgEJAQAAAA==.Kaleine:BAAALgAECgYJCAAAAA==.Kardren:BAAALgAECgUJDAAAAA==.Kat:BAAALgAECgMJAwAAAA==.',
Ke='Keiko:BAAALgAECggJDwAAAA==.Keiran:BAABLgAECn81AAMPAAkJ4yJ+CgACAwAPAAkJ4yJ+CgACAwANAAgJpRzPEgCgAgAAAA==.Kelazurin:BAAALgADCgEJAQAAAA==.Kellistair:BAAALgADCgYJBgAAAA==.Keläo:BAAALgADCgUJCQAAAA==.Kenshii:BAAALgAECgUJBQAAAA==.Keyadish:BAAALgADCgYJDQAAAA==.Keys:BAACLgAFFH8HAAIXAAMJlhXBKQDfAAAXAAMJlhXBKQDfAAAuAAQKfyYAAhcACAkTHrkQAJwCABcACAkTHrkQAJwCAAAA.',
Kh='Khalnerys:BAACLgAFFH8FAAMQAAIJLwacWABsAAAQAAIJLwacWABsAAAUAAEJ5AFgEQAoAAAuAAQKfycABBAACAkaCrNIAAgBABAACAkmCLNIAAgBABQABQl4CZAWAK0AACAAAwlOB0MxAGQAAAAA.Khitt:BAAALgAECgEJAQABLgAECgMJCAALAAAAAA==.Khoulock:BAACLgAFFH8UAAICAAgJIxA9MwB6AQACAAgJIxA9MwB6AQAuAAQKfzUABAIACQnKIDQQAMsCAAIACQm6IDQQAMsCACUABQliItYTADIBAAEAAwl9ENU+ALkAAAAA.',
Ki='Kimmi:BAABLgAECn8ZAAMBAAkJKQVTFwDoAAABAAkJKQVTFwDoAAACAAIJ1gAqaAESAAAAAA==.Kimmispally:BAAALgAECgQJBQAAAA==.Kiro:BAAALgADCgQJBQAAAA==.',
Kn='Knowimsayin:BAAALgAECgEJAQAAAA==.',
Ko='Kota:BAAALgAECgEJAQAAAA==.Kotateal:BAAALgAECgYJCwAAAA==.',
Kr='Kruelshot:BAACLgAFFH8OAAMPAAQJMiORHwCGAQAPAAQJMiORHwCGAQAOAAEJiwv5MQBKAAAuAAQKfxYAAw8ACAnFJGgSAL4CAA8ACAnFJGgSAL4CAA0ABwlqEgAyAKgBAAEuAAUUBwkfAAQAChgA.Krux:BAAALgAECgEJAQAAAA==.',
Kt='Kthxbye:BAAALgAECgUJBwABLgAECgcJCQALAAAAAA==.',
Ku='Kumcookies:BAAALgADCgEJAQAAAA==.Kungfuprissy:BAAALgAECgMJBwAAAA==.Kuraishin:BAACLgAFFH8SAAIcAAMJGB5bDADvAAAcAAMJGB5bDADvAAAuAAQKf5MAAxwACAnsJUgCAAkDABwACAnsJUgCAAkDABsACAnnImkFALYCAAEuAAUUBAkWABEA4gsA.Kuroakuma:BAAALgAECgYJEAAAAA==.Kuvara:BAAALgADCgkJCgAAAA==.',
Kv='Kvnnp:BAAALgADCgYJBgAAAA==.Kvnpro:BAAALgADCgUJBwAAAA==.Kvnxx:BAAALgADCgUJBQAAAA==.',
Kw='Kwandashadow:BAAALgAECgUJDgAAAA==.',
Ky='Kylemonk:BAAALgADCgEJAQAAAA==.',
['Ké']='Kéres:BAAALgADCgkJEAAAAA==.',
La='Lagspike:BAABLgAECn8gAAIEAAgJqBVTlgCnAQAEAAgJqBVTlgCnAQAAAA==.Latheal:BAAALgAECgMJBAAAAA==.Latto:BAABLgAFFH8FAAIDAAMJEg++FgDUAAADAAMJEg++FgDUAAAAAA==.Lavi:BAABLgAECn8dAAIHAAgJDA5skQBPAQAHAAgJDA5skQBPAQAAAA==.',
Lb='Lbk:BAAALgADCgIJAgAAAA==.',
Le='Lejeune:BAAALgAECgMJCQAAAA==.Lengex:BAAALgAECgkJDAAAAA==.Lero:BAABLgAECn8iAAIaAAkJuCFzBQDpAgAaAAkJuCFzBQDpAgAAAA==.Lerwindion:BAABLgAECn8qAAIeAAkJYx2VCQCiAgAeAAkJYx2VCQCiAgABLgAFFAQJBwARADUWAA==.Lescaryn:BAAALgAECgEJAQAAAA==.Lexoh:BAAALgAECgYJEgAAAA==.',
Li='Lilani:BAAALgADCgQJBAAAAA==.Lindir:BAACLgAFFH8PAAIOAAUJ3RpiEQA7AQAOAAUJ3RpiEQA7AQAuAAQKfyoAAg4ACQk9JKkBAD8DAA4ACQk9JKkBAD8DAAAA.Lionelle:BAAALgAECgYJDgAAAA==.Liq:BAAALgAFFAMJAwABLgAFFAYJIgAWAFMdAA==.Liquor:BAACLgAFFH8iAAIWAAYJUx3bIgCmAQAWAAYJUx3bIgCmAQAuAAQKf1AAAxYACQmJIV4LAO0CABYACQmJIV4LAO0CAAgAAwnPFOMgAJYAAAAA.Liquorish:BAAALgAECgEJAQABLgAFFAYJIgAWAFMdAA==.Lirathiel:BAABLgAECn8VAAMdAAcJiAQqPQBoAAAHAAQJfgMnNwF2AAAdAAUJsgQqPQBoAAAAAA==.Litasfk:BAAALgAECgIJAgAAAA==.Liuni:BAACLgAFFH8FAAIaAAMJiQZCPgCuAAAaAAMJiQZCPgCuAAAuAAQKfygAAhoACQmVFG0fAKsBABoACQmVFG0fAKsBAAAA.Liyin:BAAALgAECgQJCQABLgAECgkJKwAEAIEOAA==.',
Lo='Lobopeste:BAABLgAECn9LAAITAAkJTguXIQBFAQATAAkJTguXIQBFAQAAAA==.Locknutz:BAAALgADCgMJAwAAAA==.Loracy:BAAALgADCgcJBwAAAA==.Lorantell:BAAALgAECgMJAwAAAA==.Lorelynn:BAABLgAECn8qAAICAAkJUQ2xVwCWAQACAAkJUQ2xVwCWAQAAAA==.',
Lu='Luci:BAABLgAECn8YAAQWAAgJ6RJ9UACUAQAWAAgJkxJ9UACUAQAIAAMJ1Q7VLwBDAAAmAAEJAADKiAAAAAABLgAFFAMJBQADABIPAA==.Lucìan:BAACLgAFFH8FAAIZAAIJtRM4UQB+AAAZAAIJtRM4UQB+AAAuAAQKfyYAAxkACAmIIQgNAPUCABkACAmIIQgNAPUCACMAAQmmBPsHAB0AAAAA.Ludociel:BAAALgAECgUJCgAAAA==.Luna:BAAALgAECgIJAgABLgAFFAMJCAAVAHUWAA==.Lunaclair:BAACLgAFFH8WAAIRAAQJ4guPfgAKAQARAAQJ4guPfgAKAQAuAAQKf2kAAxEACQnVHWMmAGoCABEACQnVHWMmAGoCABMABwmNED0qAAYBAAAA.Lunadrus:BAABLgAECn8mAAIEAAgJogmdtgAXAQAEAAgJogmdtgAXAQAAAA==.Lunarielle:BAACLgAFFH8eAAIPAAQJCBmWBgDuAAAPAAQJCBmWBgDuAAAuAAQKfyEAAg8ACAkXHMYVAIkCAA8ACAkXHMYVAIkCAAAA.',
Ly='Lyriaa:BAAALgADCgYJCwAAAA==.',
Ma='Macalatraz:BAAALgAECgMJBwAAAA==.Macfly:BAABLgAECn80AAIPAAkJrRpRKgA0AgAPAAkJrRpRKgA0AgAAAA==.Madmeatballs:BAAALgAECgEJAQABLgAECgkJKwAEAFEfAA==.Magdala:BAAALgAECgYJBgAAAA==.Magicmissile:BAACLgAFFH8QAAIEAAYJSg/7XQAkAQAEAAYJSg/7XQAkAQAuAAQKfyoAAgQACQlqH+gXAMoCAAQACQlqH+gXAMoCAAAA.Makgora:BAAALgAECgMJBAABLgAECgYJFgAXAFkhAA==.Makhvan:BAAALgAFFAEJAwAAAA==.Maksoon:BAAALgAFFAIJAwAAAA==.Maladjusted:BAAALgAECgMJBAAAAA==.Malevalous:BAAALgAECgUJBgAAAA==.Maléfique:BAAALgAECgEJAQAAAA==.Mancath:BAAALgAECgkJCwAAAA==.Maplè:BAAALgAECgIJAwABLgAECggJIwAJAKITAA==.Mar:BAAALgADCgMJAwAAAA==.Marlei:BAAALgADCgQJBAABLgAECgkJKwAEAIEOAA==.Marqose:BAAALgADCgcJDgABLgAECgMJBgALAAAAAA==.Matan:BAAALgADCgUJBQAAAA==.',
Me='Medena:BAAALgADCgcJBwAAAA==.Meeko:BAAALgAFFAIJBAABLgAFFAgJIgAgAAQhAA==.Melfie:BAABLgAECn8wAAIEAAkJABxTIQCYAgAEAAkJABxTIQCYAgAAAA==.Meliadoul:BAABLgAECn8fAAIEAAkJwAu9cQCWAQAEAAkJwAu9cQCWAQAAAA==.Mellyndra:BAABLgAECn88AAIKAAkJ3x4SCgDqAgAKAAkJ3x4SCgDqAgAAAA==.Mercüry:BAAALgAECgEJBAAAAA==.Mezhren:BAAALgAECgYJCwAAAA==.',
Mh='Mhoramsgirl:BAAALgADCggJCwAAAA==.',
Mi='Midoriya:BAACLgAFFH8IAAMGAAMJHQexKwCfAAAGAAMJHQexKwCfAAAFAAMJyQtiRgCLAAAuAAQKfyMAAwYACQlnEYMvAEsBAAYACAkvEoMvAEsBAAUABQmQEfmEAJQAAAAA.Mistjack:BAABLgAFFH8LAAIFAAUJthFoKQAkAQAFAAUJthFoKQAkAQAAAA==.',
Mo='Momdad:BAACLgAFFH8SAAIOAAUJ6xdUEwAwAQAOAAUJ6xdUEwAwAQAuAAQKfzQAAg4ACQnWIK4HAKMCAA4ACQnWIK4HAKMCAAAA.Mongaux:BAAALgADCgQJBQAAAA==.Monkey:BAAALgAECgQJCgAAAA==.Morrígán:BAAALgADCgUJBQAAAA==.Moxi:BAAALgADCggJDwAAAA==.',
Mu='Muamman:BAAALgAECgMJAwAAAA==.Murda:BAAALgADCgYJCgAAAA==.Murphysflaw:BAAALgADCgUJCAAAAA==.Mutegen:BAAALgAFFAEJAQAAAA==.',
Mx='Mxhealeryduf:BAAALgAECgIJAgAAAA==.',
My='Mystallian:BAAALgAECgQJCQAAAA==.Mystí:BAEALgAFFAIJAgABLgAECgkJMwABAN4dAA==.Mythicplus:BAAALgAECgcJEQAAAA==.Mythosaur:BAAALgADCgEJAQAAAA==.',
['Mé']='Mélisande:BAAALgADCgQJBgAAAA==.Mémnoc:BAAALgAECgMJAwAAAA==.',
Na='Nadarien:BAAALgAECgYJDQAAAA==.Nadyia:BAAALgADCgEJAQAAAA==.Nailah:BAAALgADCgcJCwAAAA==.Nannergoat:BAAALgADCgMJAwAAAA==.Nastymikey:BAABLgAECn8bAAIfAAgJNx13BwBzAgAfAAgJNx13BwBzAgAAAA==.Nazdormu:BAABLgAECn8hAAIgAAkJzgODHwD5AAAgAAkJzgODHwD5AAAAAA==.',
Ne='Nefarious:BAAALgAECgcJDgAAAA==.Neisen:BAABLgAECn8yAAMKAAkJ9RcZEQCMAgAKAAkJ9RcZEQCMAgAHAAUJBwKc+gCeAAAAAA==.Neocold:BAAALgAECgEJAQAAAA==.Neptune:BAAALgADCgYJBgAAAA==.',
No='Norna:BAAALgADCgcJDwAAAA==.Noz:BAAALgADCgkJCQAAAA==.',
Nu='Nufonewhodis:BAABLgAECn8WAAIXAAYJWSF1HQATAgAXAAYJWSF1HQATAgAAAA==.',
Ny='Nykolas:BAAALgAECgEJAQAAAA==.Nymofthedead:BAABLgAECn8yAAMRAAkJQCRhBgBFAwARAAkJQCRhBgBFAwADAAUJyRMNGwD3AAAAAA==.',
Oa='Oakgrove:BAAALgADCgUJBQAAAA==.',
Om='Ombraless:BAAALgAECgMJAwABLgAECgQJCAALAAAAAA==.',
On='Oneforall:BAAALgAECgkJDgAAAA==.',
Op='Ophrizhani:BAAALgAECgMJAwAAAA==.',
Or='Orangegrove:BAAALgAECgYJBQAAAA==.Orpheal:BAAALgAECgUJBQAAAA==.Orphen:BAAALgAECgUJCAAAAA==.',
Os='Osìrìs:BAAALgAECgQJCwABLgAFFAIJBQAZALUTAA==.',
Pa='Paddleball:BAAALgADCgQJBAAAAA==.Paladouin:BAAALgAECgYJEwAAAA==.Pandammy:BAAALgAECgkJBQAAAA==.Pantro:BAABLgAECn8hAAMcAAkJyRf/CAA4AgAcAAkJyRf/CAA4AgAbAAEJAAC9lAAAAAAAAA==.Papalion:BAABLgAECn8hAAIPAAcJkg7tfQBDAQAPAAcJkg7tfQBDAQAAAA==.Paragas:BAAALgADCgkJEAAAAA==.Pawbs:BAAALgAECgQJEwAAAA==.',
Pe='Peanuts:BAAALgADCgcJBwAAAA==.Peoplehugger:BAAALgADCgMJAwAAAA==.',
Pi='Pickleburger:BAAALgAECgEJAQAAAA==.Pinkkrayen:BAAALgAECgMJAwAAAA==.Pinklilydrd:BAAALgAECgUJEAAAAA==.',
Pl='Plaindonut:BAABLgAECn8YAAMZAAcJCyI4FACpAgAZAAcJCyI4FACpAgAjAAEJowjIjgAxAAAAAA==.',
Po='Porple:BAABLgAECn8WAAIOAAgJfglGKgBPAQAOAAgJfglGKgBPAQAAAA==.',
Pr='Priestdrago:BAAALgADCgUJBQAAAA==.Prissidebow:BAAALgAECgMJCQAAAA==.',
Pu='Puddinpie:BAAALgADCgEJAQAAAA==.',
Qu='Quartz:BAAALgAFFAEJAQABLgAFFAMJEAASAIAkAA==.',
Ra='Rahzule:BAAALgADCgYJBwAAAA==.Ralynne:BAACLgAFFH8HAAIMAAMJwA0dOACuAAAMAAMJwA0dOACuAAAuAAQKfzAAAgwACQkoFS0gAOEBAAwACQkoFS0gAOEBAAAA.Rantis:BAAALgAECgUJBQAAAA==.Raskus:BAAALgADCgYJBgAAAA==.Ravenbrook:BAACLgAFFH8eAAISAAYJrSa7AwBGAgASAAYJrSa7AwBGAgAuAAQKfyMAAxIACAlbJXsEAGIDABIACAlbJXsEAGIDABgAAQkwIJVnAFIAAAAA.Rawrr:BAABLgAECn8kAAImAAkJWQr1KQAuAQAmAAkJWQr1KQAuAQAAAA==.Rawrxd:BAAALgAECgEJAgABLgAECggJDgALAAAAAA==.Raxie:BAACLgAFFH8iAAMeAAYJfRlIHAB+AQAeAAYJfRlIHAB+AQAnAAEJBQ3SFABRAAAuAAQKfy0ABB4ACQnXGqUOAIQCAB4ACQnXGqUOAIQCACcABwnIE9otAGoBABUAAQkBBPGHACgAAAAA.Razeth:BAABLgAECn8VAAIOAAYJ8BZdLgA0AQAOAAYJ8BZdLgA0AQAAAA==.',
Re='Reanne:BAAALgAECgYJEAAAAA==.Rebecka:BAAALgAECgUJBQAAAA==.Res:BAAALgAECgYJCwAAAA==.Rescorla:BAAALgAECgkJDAAAAA==.Rethali:BAAALgADCgQJAgAAAA==.Reysola:BAAALgAECgMJBAAAAA==.Rezr:BAAALgAECggJDgAAAA==.',
Rh='Rhixa:BAAALgADCgUJBQAAAA==.Rhymunky:BAAALgAFFAIJAgAAAA==.',
Ri='Rifthor:BAABLgAECn8YAAQcAAcJHQ4TIwDxAAAcAAYJCQ4TIwDxAAAbAAMJKQ8iSQCFAAAZAAIJsAJJ3AAmAAAAAA==.Rillx:BAAALgADCgQJBgAAAA==.Ripmxi:BAABLgAECn81AAIEAAkJkxXqAQCBAQAEAAkJkxXqAQCBAQAAAA==.',
Ro='Robinski:BAAALgADCgEJAQAAAA==.Robotiss:BAAALgADCgIJAgAAAA==.Rocco:BAAALgADCgYJBwAAAA==.Rodevon:BAAALgADCggJCAAAAA==.Roknasaurus:BAAALgADCgUJCAAAAA==.Romani:BAAALgADCgYJBgAAAA==.Romeo:BAAALgAECgQJBAAAAA==.Ronaldreagnt:BAAALgAECgcJEQAAAA==.',
Ru='Runecat:BAABLgAFFH8MAAMjAAUJbQSdMADAAAAjAAQJbQSdMADAAAAZAAQJSQSwBQBtAAAAAA==.Runelight:BAACLgAFFH8IAAMeAAMJOQFdPQCEAAAeAAMJOQFdPQCEAAAnAAIJsgHvNgBbAAAuAAQKfxwABB4ACAlQFMohAMABAB4ABwmbFMohAMABABUABgn3Co0/APEAACcAAwkQBTJsAG4AAAEuAAUUBQkMACMAbQQA.Runeshock:BAAALgAECgYJBgABLgAFFAUJDAAjAG0EAA==.Runestick:BAAALgAECgMJAwABLgAFFAUJDAAjAG0EAA==.Rupertgiless:BAACLgAFFH8RAAICAAYJpg6dJwCqAQACAAYJpg6dJwCqAQAuAAQKfyYAAgIACQl0G30iAIsCAAIACQl0G30iAIsCAAAA.',
Sa='Sabeckya:BAAALgAECgQJCgAAAA==.Sacksmasher:BAAALgADCgcJDwAAAA==.Sampleshrimp:BAAALgADCgEJAgAAAA==.Saphyla:BAAALgADCgcJDAAAAA==.Sappheire:BAAALgAECgYJBgAAAA==.Sarcastyx:BAAALgAECgcJCAAAAA==.Sarrod:BAAALgADCgUJBQAAAA==.Saxines:BAABLgAECn8dAAIVAAYJ4w/HNQAqAQAVAAYJ4w/HNQAqAQAAAA==.',
Sc='Scaliefox:BAAALgAECgIJAgABLgAECgkJPAAKAN8eAA==.Scarl:BAAALgADCgUJBQAAAA==.Schwarznacht:BAAALgADCgUJBQAAAA==.Schwarzwölf:BAAALgADCgYJCwAAAA==.Sconzil:BAAALgAECggJEQAAAA==.Scoots:BAAALgADCgQJBAAAAA==.Scrubs:BAAALgAECgYJDQAAAA==.Scrubsevoker:BAAALgAECgUJCgAAAA==.Scumbum:BAAALgADCgIJAgAAAA==.Scyllo:BAAALgAECgQJBgAAAA==.',
Se='Seekndestroy:BAABLgAECn8ZAAIMAAcJcQeOVgDhAAAMAAcJcQeOVgDhAAAAAA==.Selige:BAAALgAECgQJBAAAAA==.',
Sg='Sgtcuunt:BAAALgADCgcJBwAAAA==.',
Sh='Shackled:BAAALgAECgYJDQAAAA==.Shaenicor:BAAALgADCgIJAgAAAA==.Shankkerz:BAAALgAECgcJDAAAAA==.Shelbo:BAAALgAECgEJAQAAAA==.Shmolda:BAAALgADCgYJBwAAAA==.Shortshammy:BAAALgAECgEJAQABLgAFFAMJCwAEACUJAA==.Shror:BAAALgADCgEJAQABLgAECgUJBQALAAAAAA==.',
Si='Sicarune:BAAALgAECgUJBgABLgAFFAUJDAAjAG0EAA==.Siiegrand:BAABLgAECn8VAAIdAAcJhRCSJQDoAAAdAAcJhRCSJQDoAAAAAA==.Silentswag:BAABLgAECn8VAAIXAAcJLxTYIACPAQAXAAcJLxTYIACPAQAAAA==.Sindrane:BAAALgAECgMJAwABLgAFFAMJBwATAIAQAA==.Sitzho:BAAALgADCgUJCAAAAA==.',
Sk='Skeleton:BAAALgAECgIJAgAAAA==.Skybringer:BAABLgAECn9CAAIHAAkJfw0yaACeAQAHAAkJfw0yaACeAQAAAA==.Skyee:BAABLgAECn8qAAMGAAkJvx0LDAC6AgAGAAkJvx0LDAC6AgAFAAMJGxRwfACpAAAAAA==.Skylos:BAAALgAECgEJAgAAAA==.',
Sl='Slowburn:BAAALgAECgIJAgABLgAFFAMJBQADABIPAA==.',
Sm='Smexibiotch:BAAALgADCgYJBgABLgAECgIJAgALAAAAAA==.',
So='Soapscum:BAAALgADCgQJBAAAAA==.Soarphium:BAAALgAECgIJAgABLgAFFAcJHAAXAMEOAA==.Solararc:BAAALgADCgEJAgAAAA==.Soleana:BAAALgAECgYJBQAAAA==.Sombra:BAAALgAECgMJBwABLgAECgcJDgALAAAAAA==.Sonicast:BAAALgAECgYJCQAAAA==.Sooie:BAAALgAECgYJEgAAAA==.Soramian:BAAALgADCgcJEgAAAA==.Soulcacher:BAACLgAFFH8HAAMTAAMJgBCnLgCLAAARAAMJ6w1LpwDNAAATAAMJlwmnLgCLAAAuAAQKfzIAAxEACQmqFKFLABACABEACAknFqFLABACABMACAm9D0keAGQBAAAA.Soxxy:BAAALgAECgEJAQABLgAFFAMJBQADABIPAA==.',
Sp='Spellgunner:BAABLgAECn8VAAIEAAgJPxsGYQC+AQAEAAgJPxsGYQC+AQAAAA==.Spinsaround:BAAALgADCgEJAQAAAA==.',
St='Stormwulf:BAAALgADCgUJBQABLgAECgYJGAAFAGYYAA==.Stormyprissi:BAAALgAECgQJDAAAAA==.Strombjorn:BAABLgAECn8jAAMJAAgJohO9SQCIAQAJAAgJohO9SQCIAQAMAAUJwQwHYwC8AAAAAA==.',
['Sø']='Sølaria:BAAALgAECgEJAQAAAA==.',
Ta='Tasireth:BAAALgADCgcJBwAAAA==.',
Te='Tessi:BAACLgAFFH8HAAIEAAMJrgIUoACNAAAEAAMJrgIUoACNAAAuAAQKfxcAAgQABwm3D2OUAFABAAQABwm3D2OUAFABAAAA.',
Th='Thalrian:BAAALgAFFAEJAQABLgAFFAMJCgASAI4eAA==.Thefailnym:BAAALgAECggJEgAAAA==.Theory:BAABLgAECn8UAAMQAAcJLxEwAQAFAQAQAAcJixAwAQAFAQAUAAIJqBKHAQA7AAABLgAFFAIJCAARACAfAA==.Theylive:BAABLgAECn8dAAIZAAkJJw9kNQDFAQAZAAkJJw9kNQDFAQAAAA==.Thondrin:BAAALgAECgcJDQAAAA==.Thordanil:BAAALgAECgUJBwAAAA==.Thrashedass:BAAALgADCgEJAQAAAA==.',
Ti='Tigerlilliy:BAAALgADCgYJEAAAAA==.Timerek:BAAALgADCgIJAgAAAA==.',
To='Toawulf:BAAALgAECgQJCAABLgAECgYJGAAFAGYYAA==.Toetickla:BAAALgAECgEJAgAAAA==.Tokifuji:BAAALgAECgIJBAABLgAECgQJEwALAAAAAA==.Toranaar:BAAALgAECgcJBwAAAA==.Toya:BAABLgAECn80AAIXAAkJZRwFCwBzAgAXAAkJZRwFCwBzAgAAAA==.',
Tr='Trenazen:BAAALgADCgkJCgAAAA==.Trevain:BAAALgAECgEJAgAAAA==.Trimasdrood:BAAALgADCgMJAwAAAA==.Trivia:BAAALgAECgYJEgAAAA==.Trundle:BAAALgAECgEJAwAAAA==.Truthordare:BAABLgAECn8qAAIBAAcJcguTFwDmAAABAAcJcguTFwDmAAAAAA==.Trysla:BAAALgAECgEJAQAAAA==.',
Tu='Turtei:BAAALgAECgEJAQABLgAFFAgJKgAGAFomAA==.Turtl:BAACLgAFFH8qAAIGAAgJWiZaAAAYAwAGAAgJWiZaAAAYAwAuAAQKfysAAgYACQnmJjcAAPgDAAYACQnmJjcAAPgDAAAA.',
Tw='Twoevil:BAAALgADCgkJCQAAAA==.Twohoof:BAAALgADCgEJAQAAAA==.Twosar:BAAALgAECgIJBAAAAA==.',
Tx='Txìewtkuä:BAAALgADCgkJCQAAAA==.',
Ty='Tyryn:BAAALgAECgYJBgAAAA==.',
Ug='Uglydragon:BAAALgAECgcJDAAAAA==.Uglypally:BAAALgADCgkJCQAAAA==.Uglypetguy:BAAALgAECgIJAgAAAA==.Uglyrogue:BAAALgAECgQJAgAAAA==.Uglyshaman:BAAALgAECgEJAgAAAA==.',
Ul='Ulgrym:BAAALgAECgMJBQAAAA==.Ultimatia:BAAALgADCgMJBwAAAA==.',
Un='Unbalancéd:BAABLgAECn8iAAIFAAYJRiIXGgBHAgAFAAYJRiIXGgBHAgAAAA==.',
Va='Vaeadin:BAAALgAECgQJBQAAAA==.Vahra:BAAALgAECgMJCQAAAA==.Valanther:BAAALgAECgMJAwAAAA==.Valantis:BAAALgADCgEJAQAAAA==.Valgaskav:BAACLgAFFH8EAAIHAAMJiyHsPgAtAQAHAAMJiyHsPgAtAQAuAAQKfy4AAgcACQlmIwcKABcDAAcACQlmIwcKABcDAAAA.Valimond:BAAALgAECgEJAQABLgAECgYJGAAFAGYYAA==.Valric:BAAALgAECgUJBgAAAA==.Vanarrath:BAAALgADCgYJBwAAAA==.Vandryelle:BAAALgADCgIJAgAAAA==.Varge:BAAALgADCgMJAwAAAA==.Varrathos:BAAALgAECgMJBAAAAA==.Vayl:BAAALgAECgMJAwAAAA==.',
Ve='Vegasnight:BAAALgAECgYJDQAAAA==.Velisa:BAAALgADCgYJBgAAAA==.Vella:BAAALgAECgEJAQAAAA==.Vellaria:BAAALgADCgUJBwAAAA==.Ventrue:BAAALgADCgMJAwAAAA==.Verdesoul:BAAALgAECgcJEAABLgAECggJDgALAAAAAA==.Vesyra:BAAALgAECgQJBQAAAA==.',
Vi='Viralyn:BAAALgAECgYJBwABLgAFFAMJBQAaAIkGAA==.Vixøn:BAAALgAECgMJBgAAAA==.',
Vo='Voidluck:BAABLgAECn8SAAIWAAgJvxBkdABIAQAWAAgJvxBkdABIAQAAAA==.Voker:BAAALgAECgMJCQABLgAECgQJEwALAAAAAA==.Voladis:BAAALgAECgYJDQAAAA==.Voladro:BAAALgAECgQJBAAAAA==.Volanie:BAAALgAECgQJAwAAAA==.Volos:BAACLgAFFH8FAAIHAAIJ4w0vkQCQAAAHAAIJ4w0vkQCQAAAuAAQKfy4AAgcACAm5FkNZAMABAAcACAm5FkNZAMABAAAA.Vordaman:BAACLgAFFH8FAAIRAAMJRQTwvQCtAAARAAMJRQTwvQCtAAAuAAQKfzQAAhEACQlhEyBOANgBABEACQlhEyBOANgBAAAA.',
Vy='Vynír:BAACLgAFFH8YAAICAAcJ4RzMGAD9AQACAAcJ4RzMGAD9AQAuAAQKfy4AAwIACQmgI7AJAAUDAAIACQk+I7AJAAUDAAEABQkHI40NAOwBAAAA.',
Wa='Waghoba:BAECLgAFFH8sAAIcAAgJYB+4AABcAgAcAAgJYB+4AABcAgAuAAQKfzAAAhwACQnnIlQAAJ0BABwACQnnIlQAAJ0BAAAA.Waito:BAAALgAECgQJBwAAAA==.Wandä:BAABLgAECn85AAQaAAkJQB4QCgCSAgAaAAkJcRwQCgCSAgAGAAkJMRMiGwDXAQAFAAcJMBD6QwBcAQABLgAECggJFgAUALUYAA==.Wardriccan:BAAALgAECggJDgAAAA==.Warfle:BAAALgADCgYJBgAAAA==.Warhound:BAAALgADCgcJBwAAAA==.Warrionomous:BAACLgAFFH8PAAISAAUJLBFXIwAnAQASAAUJLBFXIwAnAQAuAAQKfxsAAhIACAkeG3gbABICABIACAkeG3gbABICAAEuAAUUBgkQAAQASg8A.Washu:BAACLgAFFH8MAAImAAQJFxDcEgANAQAmAAQJFxDcEgANAQAuAAQKf0IAAyYACQnaHzoGANQCACYACQnaHzoGANQCAAgAAwlMC1khAHkAAAAA.',
Wh='Whimlock:BAAALgADCgQJBAABLgAFFAMJBwAEAOUcAA==.Whimzie:BAAALgAECgEJAgABLgAFFAMJBwAEAOUcAA==.Whorphium:BAAALgAECggJEgABLgAFFAcJHAAXAMEOAA==.',
Wi='Willow:BAAALgAECgYJCwAAAA==.Winterous:BAAALgAECgcJDAAAAA==.',
Wo='Wonderbread:BAACLgAFFH8IAAIHAAMJlQSsgwCtAAAHAAMJlQSsgwCtAAAuAAQKfzwAAgcACQn3FcY4AB8CAAcACQn3FcY4AB8CAAAA.',
Wr='Wrager:BAAALgAECgUJBgAAAA==.Wrathofzaun:BAAALgAECgYJDwAAAA==.',
Wy='Wylest:BAAALgADCgcJBwAAAA==.Wynch:BAAALgAECgkJCQAAAA==.',
['Wâ']='Wârwôlf:BAABLgAECn8pAAMPAAkJHCSeBwAhAwAPAAkJHCSeBwAhAwANAAQJ+BWyVQDzAAAAAA==.',
Xe='Xenan:BAABLgAECn82AAIHAAkJOxYJOgAbAgAHAAkJOxYJOgAbAgAAAA==.',
Xt='Xtrolldinary:BAABLgAECn8WAAIZAAUJvQpehgCrAAAZAAUJvQpehgCrAAAAAA==.',
Xv='Xvp:BAAALgAECgQJCgAAAA==.',
Xy='Xylophy:BAABLgAECn8rAAIIAAkJPBTzCQDJAQAIAAkJPBTzCQDJAQAAAA==.',
Ye='Yeastmode:BAACLgAFFH8aAAIPAAYJNBG1IACCAQAPAAYJNBG1IACCAQAuAAQKfy4AAg8ACAksHaUmAEYCAA8ACAksHaUmAEYCAAAA.Yeasty:BAAALgAECgkJBgAAAA==.',
Yo='Yonah:BAAALgAECgYJDAAAAA==.',
Yu='Yurc:BAABLgAECn8nAAIhAAkJeBn/CQBUAgAhAAkJeBn/CQBUAgAAAA==.',
Za='Zademan:BAAALgAECgUJBwAAAA==.Zappyu:BAAALgAECgkJBQABLgAECgkJCQALAAAAAA==.Zarkas:BAAALgAECgUJCwAAAA==.',
Ze='Zeebra:BAAALgAECgcJEQAAAA==.Zeg:BAAALgAFFAMJBAAAAA==.Zega:BAAALgAFFAEJAQAAAA==.Zegafur:BAABLgAECn8zAAIZAAkJXhy/FgCRAgAZAAkJXhy/FgCRAgAAAA==.Zeruk:BAABLgAECn8XAAMGAAcJjwJ1YACOAAAGAAYJlAJ1YACOAAAFAAcJpQHalABuAAAAAA==.',
Zi='Zillionbúcks:BAACLgAFFH8cAAIHAAgJWxPRDQAHAgAHAAgJWxPRDQAHAgAuAAQKfxsAAgcACQmvHtEtAGwCAAcACQmvHtEtAGwCAAAA.',
Zu='Zullee:BAAALgAECgEJAQAAAA==.',
Zy='Zylcat:BAAALgAECgYJDAAAAA==.',
['Zê']='Zêddicus:BAABLgAECn80AAMBAAkJtCCyAQDBAgABAAkJtCCyAQDBAgACAAUJHwgM1ACyAAAAAA==.',
['Áq']='Áquafina:BAABLgAECn88AAIEAAkJpg7lXADIAQAEAAkJpg7lXADIAQAAAA==.',
['Åñ']='Åñgêl:BAAALgAECgIJAgAAAA==.',
['Îv']='Îvan:BAAALgADCggJCAAAAA==.',
['Ðö']='Ðö:BAABLgAECn82AAISAAkJ5x3jCwCqAgASAAkJ5x3jCwCqAgAAAA==.',
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
