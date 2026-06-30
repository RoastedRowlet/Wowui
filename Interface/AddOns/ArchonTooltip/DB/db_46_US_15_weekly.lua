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

local lookup = {'Warlock-Destruction','Warlock-Demonology','DeathKnight-Frost','Mage-Frost','Monk-Mistweaver','Monk-Windwalker','Paladin-Retribution','DemonHunter-Vengeance','Shaman-Restoration','Paladin-Holy','Unknown-Unknown','Shaman-Elemental','Hunter-Marksmanship','Hunter-Survival','Hunter-BeastMastery','Evoker-Augmentation','DeathKnight-Unholy','Warrior-Fury','DeathKnight-Blood','Priest-Holy','DemonHunter-Devourer','Rogue-Subtlety','Warrior-Arms','Druid-Restoration','DemonHunter-Havoc','Paladin-Protection','Monk-Brewmaster','Druid-Guardian','Druid-Feral','Priest-Discipline','Shaman-Enhancement','Evoker-Preservation','Warrior-Protection','Rogue-Outlaw','Evoker-Devastation','Druid-Balance','Mage-Fire','Warlock-Affliction','Priest-Shadow',}
local provider = {region='US',realm='Anvilmar',name='US',type='weekly',zone=46,date='2026-06-27',data={Aa='Aaril:BAAALgAECgYJIQAAAQ==.',
Ab='Abrams:BAAALgADCgYJCgAAAA==.',
Ad='Adel:BAAALgAECgYJCAAAAA==.',
Ae='Aelitha:BAABLgAECn8ZAAMBAAYJCQZ2OQDOAAABAAYJxAR2OQDOAAACAAYJsQQU0gCwAAAAAA==.',
Ak='Akaishi:BAAALgADCgIJAgAAAA==.Akali:BAAALgAFFAIJAwABLgAFFAMJCAADAAkVAA==.Akina:BAAALgAECgQJBAABLgAECgkJKwAEAIEOAA==.',
Al='Alanie:BAAALgAECgIJAgAAAA==.Alathiana:BAAALgADCgUJCAAAAA==.Alcweaver:BAABLgAECn8dAAMFAAcJgiBJIQASAgAFAAcJgiBJIQASAgAGAAYJgA8UQQD7AAAAAA==.Alecto:BAAALgAECgMJAwAAAA==.Alindia:BAAALgAECgQJCgABLgAECgkJKwAEAIEOAA==.Alirrayia:BAAALgAECgQJBQAAAA==.Alirrayiia:BAACLgAFFH8IAAIHAAMJ+AHOigCcAAAHAAMJ+AHOigCcAAAuAAQKfyoAAgcACQlwFG5CAP8BAAcACQlwFG5CAP8BAAAA.Alkri:BAAALgADCgMJAwAAAA==.Allari:BAAALgAECgYJEwAAAA==.Allikazam:BAAALgADCgYJGAAAAA==.Allystar:BAAALgAECgQJDwAAAA==.Altheia:BAAALgAECgQJBAAAAA==.Alvidor:BAABLgAECn9JAAIEAAkJqQYIiABnAQAEAAkJqQYIiABnAQAAAA==.',
Am='Ambrose:BAAALgAECgcJBwAAAA==.Ameria:BAAALgADCgUJBQAAAA==.Amethen:BAAALgADCgEJAQAAAA==.Amexican:BAAALgAECgEJAQAAAA==.Amybabe:BAAALgAFFAIJAgAAAA==.',
An='Anastos:BAAALgAECgUJBQAAAA==.Andydufresne:BAAALgAECgQJDwABLgAECgkJUQAIAL8lAA==.Anestesiax:BAAALgAECgIJBAAAAA==.Angryqueer:BAAALgADCgEJAQAAAA==.',
Ao='Aowl:BAAALgAECgcJCwAAAA==.',
Ap='Apocketheory:BAAALgADCgIJAgAAAA==.Apolloerosb:BAAALgAECgYJDwABLgAECgcJLQAJAOAbAA==.Apolloerosp:BAAALgAECgYJCQABLgAECgcJLQAJAOAbAA==.Apollossham:BAABLgAECn8tAAIJAAcJ4BuWIwA5AgAJAAcJ4BuWIwA5AgAAAA==.',
Ar='Arkanaun:BAABLgAECn8dAAMHAAYJRBdpcwCUAQAHAAYJRBdpcwCUAQAKAAUJvRTvTAAHAQAAAA==.',
As='Ashes:BAAALgAECgcJAQAAAA==.Ashrán:BAAALgAECgYJCQAAAA==.Ashyluna:BAAALgAECgQJBAAAAA==.Astianna:BAAALgADCgMJAwAAAA==.',
Au='Aule:BAAALgAECgIJAwAAAA==.Aurinia:BAAALgADCgQJAgAAAA==.Auroradinlee:BAAALgAECgkJBgAAAA==.Aurore:BAAALgAECgQJCgAAAA==.',
Av='Avradea:BAAALgAECgEJAQABLgAECgkJKwAEAIEOAA==.',
Az='Azareth:BAAALgADCggJCAAAAA==.',
Ba='Babbayagga:BAAALgAECgEJAQAAAA==.Baconatorr:BAAALgAECgQJBQAAAA==.Bagelbags:BAAALgADCgEJAQAAAA==.Bahler:BAAALgADCgUJBQABLgAECgMJAwALAAAAAA==.Baji:BAACLgAFFH8IAAIJAAMJKB4dEQDFAAAJAAMJKB4dEQDFAAAuAAQKfzsAAwkACQktIvAHADADAAkACQktIvAHADADAAwABQn+FVlKAAsBAAAA.Baklan:BAAALgAECgMJAwAAAA==.Barefaall:BAACLgAFFH8XAAMNAAcJoBcTCgDCAQANAAcJExYTCgDCAQAOAAQJ/hAuEQA9AQAuAAQKf0cABA0ACQllJOUAAD4DAA0ACQllJOUAAD4DAA4AAwmLHXECABIBAA8ABAmFEOCqAO0AAAAA.Barefall:BAACLgAFFH8MAAIOAAMJYhBsBgDPAAAOAAMJYhBsBgDPAAAuAAQKfx0AAg4ACQnCFNkBAEMBAA4ACQnCFNkBAEMBAAEuAAUUBwkXAA0AoBcA.Barefalls:BAACLgAFFH8RAAIOAAMJshwfBQD0AAAOAAMJshwfBQD0AAAuAAQKfzAAAw4ACQk9H/8GAK8CAA4ACQk9H/8GAK8CAA0AAQmMAaCWACIAAAEuAAUUBwkXAA0AoBcA.Barelywolf:BAABLgAECn8mAAMGAAkJwB+EEQA4AgAGAAcJ5CCEEQA4AgAFAAgJLxfXIgAIAgABLgAFFAMJBgAQACwLAA==.Bashira:BAABLgAECn8eAAIPAAkJsAonWQCZAQAPAAkJsAonWQCZAQAAAA==.Bast:BAACLgAFFH8IAAMRAAMJPwdVtQC8AAARAAMJPwdVtQC8AAADAAEJVgM4LAA4AAAuAAQKfzIAAxEACQljFtMzAC8CABEACQljFtMzAC8CAAMABAmJDbIoAI4AAAAA.Bastrillan:BAAALgAECgUJBwAAAA==.',
Be='Bearophe:BAAALgAECgEJAgAAAA==.Beerfist:BAAALgAECgEJAQAAAA==.Belfor:BAAALgAECgMJAwAAAA==.Bellock:BAAALgAECgMJAwAAAA==.Bendroyd:BAAALgAECgIJAgAAAA==.Benisbagina:BAAALgADCggJCQAAAA==.Bergonator:BAABLgAECn8gAAISAAYJcRC9TwBpAQASAAYJcRC9TwBpAQAAAA==.Berrodiah:BAABLgAECn8bAAQDAAgJOBqXAADwAQADAAcJfxuXAADwAQATAAgJKxAXIABTAQARAAMJmgsLDAGdAAAAAA==.Bettyswalls:BAAALgAECgMJAwAAAA==.Beyarago:BAAALgAECgcJCwAAAA==.',
Bh='Bheiroth:BAACLgAFFH8FAAIUAAMJ3iCcFAAfAQAUAAMJ3iCcFAAfAQAuAAQKfzIAAhQACQlIJHIEADsDABQACQlIJHIEADsDAAAA.',
Bi='Birds:BAAALgAECgkJEQAAAA==.',
Bl='Bladeygaga:BAABLgAECn85AAIVAAkJpR+hCwDqAgAVAAkJpR+hCwDqAgAAAA==.Blasé:BAAALgAECgcJCAAAAA==.Blazingblood:BAAALgADCgUJAQAAAA==.Bloodknight:BAAALgADCgYJCQAAAA==.Bluekrayen:BAAALgAECgUJCAAAAA==.Bluett:BAAALgAECgMJCQAAAA==.Bláckøut:BAAALgADCgYJDAAAAA==.',
Bo='Bodhi:BAABLgAECn8WAAIWAAcJNhAQJwDAAQAWAAcJNhAQJwDAAQAAAA==.Bogertus:BAACLgAFFH8RAAISAAMJgCTIIgApAQASAAMJgCTIIgApAQAuAAQKf0AAAxIACQnSJnwAAIwDABIACQnSJnwAAIwDABcAAgn1HHIpAKUAAAAA.Bonobo:BAAALgAECgYJCQAAAA==.Boomertunes:BAABLgAECn8mAAMCAAkJYxgtJgBFAgACAAkJYxgtJgBFAgABAAIJGwFEVAAAAAAAAA==.',
Br='Brein:BAACLgAFFH8FAAIYAAMJgBhWCgDUAAAYAAMJgBhWCgDUAAAuAAQKf1gAAhgACQn/JboAAOADABgACQn/JboAAOADAAAA.Brewmaster:BAAALgAECgIJAwAAAA==.Brewwmaster:BAABLgAECn8kAAQTAAkJrBjiFwCmAQATAAkJIBXiFwCmAQARAAYJtBfWfACKAQADAAEJ+he5FgA2AAAAAA==.Bricklethumb:BAAALgAECgMJAwABLgAECgYJGAAFAGYYAA==.Brickred:BAAALgADCggJDgAAAA==.Brynodd:BAAALgAECgMJCQAAAA==.',
Bu='Bubblybetty:BAAALgAECgEJAQAAAA==.Bucketeer:BAABLgAECn8rAAIEAAkJUR/KHACwAgAEAAkJUR/KHACwAgAAAA==.Buffs:BAAALgADCgEJAQAAAA==.Bullminator:BAAALgAECggJDgAAAA==.Bursona:BAAALgAECgEJAQAAAA==.Butterfree:BAAALgAECgUJDAABLgAFFAEJAQALAAAAAA==.',
['Bô']='Bôngo:BAAALgAECgUJBQAAAA==.',
Ca='Cards:BAAALgAECgYJCgAAAA==.Carkrash:BAAALgAECgUJBQAAAA==.Casterkang:BAAALgAECgUJCQAAAA==.Catshunter:BAABLgAECn8bAAIPAAcJRh0bBgBxAQAPAAcJRh0bBgBxAQAAAA==.',
Ce='Celaa:BAABLgAECn8rAAIEAAkJgQ7BXgDDAQAEAAkJgQ7BXgDDAQAAAA==.',
Ch='Chanka:BAABLgAECn8cAAIBAAYJ6gjQHgCzAAABAAYJ6gjQHgCzAAAAAA==.Chantillary:BAAALgAECgMJCQAAAA==.Chargerkang:BAAALgADCgYJBgAAAA==.Chchanges:BAAALgAECgEJAQAAAA==.Cheesy:BAABLgAECn8qAAICAAgJFA1LbgBfAQACAAgJFA1LbgBfAQAAAA==.Chicken:BAAALgAECgYJEgAAAA==.Chonk:BAAALgADCgEJAQAAAA==.Chopzullee:BAABLgAECn8fAAIGAAcJhQtcBADIAAAGAAcJhQtcBADIAAAAAA==.',
Ci='Circii:BAAALgAECgQJBAAAAA==.Cirya:BAAALgAECgUJCQAAAA==.',
Cl='Cleric:BAAALgADCgUJBQAAAA==.Clortho:BAABLgAECn8UAAMZAAYJEg4HBQC9AAAZAAYJEg4HBQC9AAAVAAEJ6gFhPwEWAAAAAA==.Clorthö:BAAALgADCgUJBQAAAA==.',
Co='Coljack:BAAALgAECggJCAAAAA==.Colljack:BAACLgAFFH8gAAIKAAcJkRfBDgDOAQAKAAcJkRfBDgDOAQAuAAQKfyEAAwoACQkgIZwJANgCAAoACQkgIZwJANgCAAcABQlOEtO5ABIBAAAA.Coughlin:BAAALgAECgEJAQAAAA==.',
Cr='Crocbait:BAAALgAECgcJEQAAAA==.Cryptoe:BAACLgAFFH8KAAIEAAMJdhSOKgCiAAAEAAMJdhSOKgCiAAAuAAQKfyAAAgQACQnVE0NKAPwBAAQACQnVE0NKAPwBAAAA.',
Cu='Cudlsac:BAAALgAECgQJBQAAAA==.',
Da='Daedelus:BAABLgAECn8oAAMVAAgJ3heOBgAOAQAVAAgJqheOBgAOAQAIAAYJtxGYFAALAQAAAA==.Daglon:BAABLgAECn8ZAAMHAAgJXBN3BQBtAQAHAAYJ+hh3BQBtAQAaAAQJtwd8OgBzAAAAAA==.Dagz:BAAALgAECgQJBAAAAA==.Dakina:BAAALgADCgYJBgAAAA==.Daraedra:BAABLgAECn8VAAIEAAYJJwPyGgBhAAAEAAYJJwPyGgBhAAAAAA==.Darkenvoid:BAAALgADCgkJDQAAAA==.',
De='Deathslight:BAAALgAECgQJBwAAAA==.Dedaeste:BAAALgADCgUJBwAAAA==.Deeznutticus:BAACLgAFFH8cAAISAAYJKhYKEQB+AQASAAYJKhYKEQB+AQAuAAQKfyEAAxIABwnCIkgYAIkCABIABwnCIkgYAIkCABcAAgkBHdBcAGoAAAAA.Defnotisis:BAABLgAECn8dAAMbAAgJhxTKKABsAQAbAAcJCRbKKABsAQAGAAgJtAs7RADuAAABLgAFFAMJCAADAAkVAA==.Defnotkity:BAABLgAFFH8HAAMcAAMJLg5JLABpAAAdAAIJ2QfiFwB0AAAcAAIJzBBJLABpAAAAAA==.Demonspud:BAABLgAECn8dAAIVAAcJhRIYZgBaAQAVAAcJhRIYZgBaAQAAAA==.Demotard:BAAALgAECgIJAQAAAA==.Denxster:BAAALgAECgYJDgAAAA==.Dersan:BAABLgAECn8jAAIBAAgJ1gAuPgA0AAABAAgJ1gAuPgA0AAAAAA==.Destriant:BAABLgAECn83AAIaAAkJyxliCgAkAgAaAAkJyxliCgAkAgAAAA==.Devilschant:BAAALgAECgYJCgAAAA==.Devilshadow:BAAALgAECgUJBwABLgAECgYJCgALAAAAAA==.Dewbert:BAAALgADCgQJBAAAAA==.Dewburt:BAAALgADCggJCgAAAA==.Deylia:BAAALgAECgYJEQABLgAFFAYJIwAeAH0ZAA==.',
Di='Dilithia:BAABLgAECn8bAAIRAAYJ0wKhEgGVAAARAAYJ0wKhEgGVAAAAAA==.Dillion:BAAALgAECgYJCAAAAA==.Dinonuggies:BAAALgADCgcJBwAAAA==.Dionin:BAAALgAECgEJAQAAAA==.Dira:BAAALgAFFAIJAgABLgAFFAcJHgAfAC8dAA==.Dirkbanne:BAAALgADCgYJBgAAAA==.Dizzyhealz:BAAALgADCgEJAQAAAA==.Dizzyhuntres:BAAALgAECgEJAQAAAA==.',
Do='Dodoubleg:BAAALgAECgYJEAAAAA==.Dominique:BAAALgADCgYJBgAAAA==.Donzilch:BAEALgAECgQJBAAAAA==.Donzilly:BAAALgAECgUJBQAAAA==.Dooberrt:BAAALgAECgIJAgAAAA==.Dooburt:BAABLgAECn8YAAIHAAkJvhIIBwBDAQAHAAkJvhIIBwBDAQAAAA==.Doombringers:BAAALgAECgUJCAAAAA==.',
Dr='Dracaric:BAABLgAECn8rAAIQAAkJEhbUGAAQAgAQAAkJEhbUGAAQAgAAAA==.Draeca:BAAALgAECgMJBgAAAA==.Dragondznut:BAAALgAECgQJBQAAAA==.Drakhar:BAAALgADCgIJAgABLgAECgcJDQALAAAAAA==.Drfrostie:BAABLgAECn8UAAIEAAcJSBIrmgChAQAEAAcJSBIrmgChAQAAAA==.Drgunner:BAAALgAECgcJDwAAAA==.Driatin:BAAALgAFFAEJAQAAAA==.Drkladykikyo:BAABLgAECn8XAAIUAAkJFQOLQQDmAAAUAAkJFQOLQQDmAAAAAA==.Druroo:BAAALgAECgEJAQABLgAFFAQJBwARADUWAA==.Druterr:BAAALgAECgIJAgABLgAFFAMJAwALAAAAAA==.',
Du='Dumb:BAACLgAFFH8PAAIgAAUJLAyTBgCJAQAgAAUJLAyTBgCJAQAuAAQKfyMAAiAACAnoG28LAH4CACAACAnoG28LAH4CAAAA.Durø:BAABLgAECn8WAAIVAAgJryLZDAAZAwAVAAgJryLZDAAZAwAAAA==.Duskhunter:BAAALgADCgEJAQAAAA==.',
Dy='Dyanisian:BAAALgADCgYJCAAAAA==.',
['Dè']='Dègenerate:BAACLgAFFH8IAAIhAAMJDBeUCACkAAAhAAMJDBeUCACkAAAuAAQKf0IAAiEACQmOIE8EAOICACEACQmOIE8EAOICAAAA.',
Ed='Edagerran:BAAALgADCgkJCQAAAA==.',
Ei='Eilae:BAABLgAECn8hAAIPAAgJYgZbFACTAAAPAAgJYgZbFACTAAAAAA==.Eirhakan:BAAALgAECgQJCAAAAA==.',
El='Elrethyl:BAABLgAECn8WAAIHAAcJXhgadwCAAQAHAAcJXhgadwCAAQAAAA==.Elvanus:BAAALgADCgYJBgAAAA==.Elêktra:BAABLgAECn8uAAIMAAkJSA9dMwBuAQAMAAkJSA9dMwBuAQAAAA==.',
Em='Emet:BAAALgAECgQJDAABLgAECgkJTAAJAEwbAA==.',
Ep='Epicnym:BAAALgAECgYJBwAAAA==.Epicsmoke:BAACLgAFFH8UAAISAAMJDxziCgDoAAASAAMJDxziCgDoAAAuAAQKf2EAAhIACQkaJSECAFYDABIACQkaJSECAFYDAAAA.Epidemius:BAAALgAECgkJCgAAAA==.',
Er='Erevan:BAABLgAECn84AAMWAAkJ3Bu8CACbAgAWAAkJ3Bu8CACbAgAiAAEJpwABEAAcAAAAAA==.Erinn:BAAALgAECgMJBgAAAA==.Eroica:BAAALgADCgYJBwAAAA==.Eronys:BAAALgAFFAIJAQAAAA==.',
Es='Esdeath:BAABLgAECn8tAAMRAAkJDhRETwDVAQARAAkJDhRETwDVAQATAAYJWga4PgCVAAAAAA==.',
Et='Etharia:BAAALgADCgUJAwAAAA==.',
Ev='Evilsmeghead:BAAALgADCgEJAQAAAA==.',
Ex='Exiledguy:BAAALgADCgYJBgAAAA==.Extenze:BAACLgAFFH8FAAIVAAMJUhNxYADOAAAVAAMJUhNxYADOAAAuAAQKfy4AAhUACQnSHvwBAMMBABUACQnSHvwBAMMBAAAA.',
Ez='Ezykiah:BAAALgAECgYJCgAAAA==.',
Fa='Falconponch:BAAALgADCgEJAQAAAA==.',
Fe='Felbjorn:BAAALgAECgEJAgAAAA==.Felgibson:BAAALgAECgQJBQAAAA==.Felkang:BAAALgADCgkJCQAAAA==.Fergusmcld:BAAALgADCgIJAgAAAA==.Ferryman:BAABLgAECn8fAAIPAAgJjBLEYACFAQAPAAgJjBLEYACFAQAAAA==.',
Fl='Flingor:BAAALgAECgYJEAAAAA==.Flokha:BAAALgADCgEJAQAAAA==.',
Fo='Forphium:BAACLgAFFH8cAAIWAAcJwQ6lBACkAQAWAAcJwQ6lBACkAQAuAAQKfyAAAhYACQn9IH0NAMQCABYACQn9IH0NAMQCAAAA.',
Fr='Fredolf:BAAALgAECgEJAQAAAA==.Freydís:BAAALgAECgUJCwAAAA==.Freyå:BAAALgAECgIJAgAAAA==.Friarkuck:BAAALgADCggJCAAAAA==.Friedbones:BAAALgAECgMJCQAAAA==.Frostiepal:BAAALgADCgYJBgAAAA==.Frostlilliy:BAAALgADCggJCwAAAA==.',
['Fü']='Fürbie:BAAALgAECgIJAwAAAA==.',
Ga='Gahlina:BAABLgAECn8WAAMJAAgJ3hQIMwDnAQAJAAgJ3hQIMwDnAQAMAAEJ1wEzlgAeAAAAAA==.Galdorian:BAAALgADCgYJCQABLgAECgkJHgAPALAKAA==.Galynda:BAAALgADCgcJCQAAAA==.Garshan:BAAALgAECgMJBAAAAA==.',
Ge='Genjimain:BAABLgAECn8lAAMYAAkJBhqRHgBKAgAYAAkJBhqRHgBKAgAdAAMJ9wyhNQCHAAAAAA==.Genjí:BAAALgAECgEJAwAAAA==.Geris:BAAALgAECgQJBQAAAA==.Gertruide:BAAALgADCgUJBQAAAA==.',
Gh='Ghendala:BAAALgADCggJEwAAAA==.',
Gi='Gillesmon:BAAALgAFFAEJAQABLgAECggJGQAHAFwTAA==.Gilleyy:BAAALgAECgQJBQABLgAECgYJFAAjAJodAA==.Gincainn:BAAALgAECgEJAgAAAA==.Gird:BAABLgAECn8oAAIKAAgJ4Q1+OABrAQAKAAgJ4Q1+OABrAQAAAA==.Girdlock:BAAALgAECgYJBwAAAA==.',
Gl='Glaiveyjones:BAAALgAECgEJAQAAAA==.',
Gn='Gnymesis:BAAALgAECgYJDgAAAA==.',
Go='Goatmonger:BAAALgAECgYJBgAAAA==.Goinpostal:BAAALgAECgIJAgAAAA==.Goldblade:BAAALgAECgkJEwAAAA==.Goodvsevil:BAAALgAECgQJBAAAAA==.Gordek:BAABLgAECn8dAAMHAAkJsRpHLQBLAgAHAAkJsRpHLQBLAgAKAAIJhBCpdwBfAAAAAA==.Gorlthov:BAAALgAFFAEJAQABLgAFFAMJDQASAIQfAA==.Gothitelle:BAAALgAECgIJBwAAAA==.Goöse:BAACLgAFFH8ZAAIRAAYJJh7dAwDEAQARAAYJJh7dAwDEAQAuAAQKfycAAhEACAmDJusGAGsDABEACAmDJusGAGsDAAAA.',
Gr='Grantaron:BAABLgAECn83AAIHAAkJ2iDYGACuAgAHAAkJ2iDYGACuAgAAAA==.Gravarii:BAAALgADCgcJEwAAAA==.Grimskul:BAABLgAECn8zAAMRAAkJkB3DGgCmAgARAAkJkB3DGgCmAgADAAYJDxSUBwCBAQAAAA==.Grindor:BAAALgADCgEJAQAAAA==.Grntitan:BAAALgAECgQJCgAAAA==.Gruid:BAAALgADCgcJDwAAAA==.',
Gu='Guinessbrew:BAAALgAECgEJAQAAAA==.',
Gw='Gwoohoori:BAAALgAECggJEwAAAA==.',
Gy='Gyra:BAAALgAECgYJEQAAAA==.Gyrojetli:BAAALgAECgQJBQAAAA==.',
Ha='Halukari:BAABLgAECn8cAAMcAAcJvSGDAQCTAQAcAAcJvSGDAQCTAQAkAAEJ8gzahgApAAABLgAFFAYJIwAeAH0ZAA==.Harfnan:BAAALgAECgIJAgAAAA==.Harrin:BAACLgAFFH8MAAIEAAQJNgXnIwDCAAAEAAQJNgXnIwDCAAAuAAQKfx0AAgQABwn2D4ijADUBAAQABwn2D4ijADUBAAAA.',
He='Healingwater:BAAALgAECgIJAwAAAA==.Herracles:BAAALgADCgYJGAAAAA==.',
Hi='Hierodule:BAAALgAECgEJAQAAAA==.Hiimriven:BAAALgAECgIJAgABLgAECgYJFgAWAFkhAA==.Hinal:BAABLgAECn8gAAIHAAkJMhtdKABhAgAHAAkJMhtdKABhAgAAAA==.',
Ho='Hojo:BAAALgADCgUJCAAAAA==.Holyenabler:BAABLgAFFH8UAAIaAAMJegylBABmAAAaAAMJegylBABmAAAAAA==.Honzo:BAAALgADCgkJCQAAAA==.Hootiehoo:BAAALgADCgMJAwAAAA==.',
Hu='Huflunggoo:BAAALgADCgkJDQAAAA==.Huflungpoop:BAABLgAECn80AAIGAAkJqBpcEQA6AgAGAAkJqBpcEQA6AgAAAA==.Hunterborn:BAAALgAFFAIJAgAAAA==.',
Hy='Hypercube:BAAALgAECgQJBwAAAA==.',
['Hè']='Hèalz:BAAALgAECgYJBgABLgAECgkJOwASADUeAA==.',
Ic='Ickixia:BAAALgADCgQJBAAAAA==.',
Il='Ilkaressa:BAAALgADCgQJBAAAAA==.Illyríá:BAEBLgAFFH8KAAICAAMJQxFpdQDWAAACAAMJQxFpdQDWAAABLgAECgkJNQABAN4dAA==.Ilun:BAAALgAECgIJAgAAAA==.',
Im='Imcruel:BAACLgAFFH8hAAMEAAcJChhbIQD6AQAEAAcJChhbIQD6AQAlAAMJlBR8AwDSAAAuAAQKfzAAAgQACQnNJZ8HAEEDAAQACQnNJZ8HAEEDAAAA.Imisis:BAAALgAECgYJCQAAAA==.Ims:BAAALgAECggJCAAAAA==.',
In='Ink:BAACLgAFFH8NAAIEAAQJKxGMYwAbAQAEAAQJKxGMYwAbAQAuAAQKfycAAgQABwm2IB1aAM8BAAQABwm2IB1aAM8BAAAA.',
Is='Istaria:BAAALgAECgMJCAAAAA==.Isujr:BAABLgAECn8ZAAIRAAcJ8hIKcQCmAQARAAcJ8hIKcQCmAQAAAA==.',
Ja='Jacaerys:BAAALgADCgYJBgAAAA==.Jackiegan:BAABLgAECn8rAAQbAAkJBSGfBAD7AgAbAAkJBSGfBAD7AgAGAAEJahEzjwBCAAAFAAEJJgel0wAeAAAAAA==.Jackson:BAAALgAECgMJCQAAAA==.Jagerdemon:BAAALgAECgcJCQAAAA==.',
Jc='Jckskellngtn:BAAALgADCgMJAwAAAA==.',
Je='Jerce:BAAALgADCgUJBQAAAA==.Jeryatric:BAAALgADCgcJBwAAAA==.',
Jh='Jhala:BAAALgADCgkJDwAAAA==.',
Ji='Jinnxx:BAAALgAECgMJBAABLgAFFAcJHgAfAC8dAA==.',
Jo='Joshcalc:BAABLgAFFH8GAAIkAAMJNyPVHAA0AQAkAAMJNyPVHAA0AQAAAA==.Joskel:BAABLgAECn8vAAQCAAgJDw1acwBTAQACAAgJiQxacwBTAQAmAAYJMQToFgDIAAABAAIJNgxqMQBYAAAAAA==.',
Ju='Juacqer:BAAALgAECgMJCQAAAA==.Juggarnaut:BAAALgADCgYJCAAAAA==.',
Ka='Kaant:BAABLgAECn9MAAMJAAkJTBvQEQC/AgAJAAkJTBvQEQC/AgAMAAgJox5WEwBTAgAAAA==.Kaeni:BAAALgADCgMJAwAAAA==.Kaidevyn:BAABLgAECn8/AAMDAAkJjxeqBwAbAgADAAkJjxeqBwAbAgARAAQJWgqEGQGMAAAAAA==.Kaiste:BAAALgADCgEJAQAAAA==.Kaleine:BAAALgAECgYJCAAAAA==.Kardren:BAAALgAECgUJDAAAAA==.Kat:BAAALgAECgMJAwAAAA==.',
Ke='Keiko:BAAALgAECggJDwAAAA==.Keiran:BAABLgAECn81AAMPAAkJ4yJ7CgACAwAPAAkJ4yJ7CgACAwANAAgJpRzPEgCgAgAAAA==.Kelazurin:BAAALgADCgEJAQAAAA==.Kellistair:BAAALgADCgYJBgAAAA==.Keläo:BAAALgADCgUJCQAAAA==.Kenshii:BAAALgAECgUJBQAAAA==.Keyadish:BAAALgADCgYJDQAAAA==.Keys:BAACLgAFFH8HAAIWAAMJlhW+KQDfAAAWAAMJlhW+KQDfAAAuAAQKfyYAAhYACAkTHrkQAJwCABYACAkTHrkQAJwCAAAA.',
Kh='Khalnerys:BAACLgAFFH8FAAMQAAIJLwadWABsAAAQAAIJLwadWABsAAAjAAEJ5AFeEQAoAAAuAAQKfycABBAACAkaCrZIAAgBABAACAkmCLZIAAgBACMABQl4CY8WAK0AACAAAwlOB0IxAGQAAAAA.Khitt:BAAALgAECgEJAQABLgAECgMJCAALAAAAAA==.Khoulock:BAACLgAFFH8UAAICAAgJIxAaMwB6AQACAAgJIxAaMwB6AQAuAAQKfzUABAIACQnKIDQQAMsCAAIACQm6IDQQAMsCACYABQliItUTADIBAAEAAwl9ENU+ALkAAAAA.',
Ki='Kimmi:BAABLgAECn8ZAAMBAAkJKQVVFwDoAAABAAkJKQVVFwDoAAACAAIJ1gAqaAESAAAAAA==.Kimmispally:BAAALgAECgQJBQAAAA==.Kiro:BAAALgADCgQJBQAAAA==.',
Kn='Knowimsayin:BAAALgAECgEJAQAAAA==.',
Ko='Kota:BAAALgAECgEJAgAAAA==.Kotalock:BAAALgAECgYJBgAAAA==.Kotateal:BAAALgAECgYJCwAAAA==.',
Kr='Krelian:BAAALgADCgEJAQAAAA==.Kruelshot:BAACLgAFFH8PAAMPAAQJMiORHwCGAQAPAAQJMiORHwCGAQAOAAEJiwv6MQBKAAAuAAQKfxYAAw8ACAnFJGUSAL4CAA8ACAnFJGUSAL4CAA0ABwlqEgAyAKgBAAEuAAUUBwkhAAQAChgA.Krux:BAAALgAECgEJAQAAAA==.',
Kt='Kthxbye:BAAALgAECgUJBwABLgAECgcJCQALAAAAAA==.',
Ku='Kumcookies:BAAALgADCgEJAQAAAA==.Kungfuprissy:BAAALgAECgMJBwAAAA==.Kuraishin:BAACLgAFFH8UAAIdAAMJXB9bDADvAAAdAAMJXB9bDADvAAAuAAQKf5oAAx0ACQnMJUgCAAkDAB0ACQnMJUgCAAkDABwACAnnImkFALYCAAEuAAUUBAkcABEAew8A.Kuroakuma:BAAALgAECgYJEAAAAA==.Kuterr:BAAALgAFFAMJAwAAAA==.Kuvara:BAAALgADCgkJCgAAAA==.',
Kv='Kvnnp:BAAALgADCgYJBgAAAA==.Kvnpro:BAAALgADCgUJBwAAAA==.Kvnxx:BAAALgADCgUJBQAAAA==.',
Kw='Kwandashadow:BAAALgAECgUJDgAAAA==.',
Ky='Kylemonk:BAAALgADCgEJAQAAAA==.',
['Ké']='Kéres:BAAALgADCgkJEAAAAA==.',
La='Lagspike:BAABLgAECn8gAAIEAAgJqBVTlgCnAQAEAAgJqBVTlgCnAQAAAA==.Latheal:BAAALgAECgMJBAAAAA==.Latto:BAABLgAFFH8IAAMDAAMJCRW+FgDUAAADAAMJCRW+FgDUAAARAAEJeAcTXwBDAAAAAA==.Lavi:BAABLgAECn8dAAIHAAgJDA5rkQBPAQAHAAgJDA5rkQBPAQAAAA==.',
Lb='Lbk:BAAALgADCgIJAgAAAA==.',
Le='Lejeune:BAAALgAECgMJCQAAAA==.Lengex:BAAALgAECgkJDAAAAA==.Lero:BAABLgAECn8iAAIbAAkJuCF0BQDpAgAbAAkJuCF0BQDpAgAAAA==.Lerwindion:BAABLgAECn8qAAIeAAkJYx2VCQCiAgAeAAkJYx2VCQCiAgABLgAFFAQJBwARADUWAA==.Lescaryn:BAAALgAECgEJAQAAAA==.Lexoh:BAAALgAECgYJEgAAAA==.',
Li='Lilani:BAAALgADCgQJBAAAAA==.Lindir:BAACLgAFFH8PAAIOAAUJ3RpjEQA7AQAOAAUJ3RpjEQA7AQAuAAQKfyoAAg4ACQk9JKkBAD8DAA4ACQk9JKkBAD8DAAAA.Lionelle:BAAALgAECgYJDgAAAA==.Liq:BAAALgAFFAMJAwABLgAFFAYJIgAVAFMdAA==.Liquor:BAACLgAFFH8iAAIVAAYJUx3GIgCmAQAVAAYJUx3GIgCmAQAuAAQKf1AAAxUACQmJIVwLAO0CABUACQmJIVwLAO0CAAgAAwnPFOQgAJYAAAAA.Liquorish:BAAALgAECgEJAQABLgAFFAYJIgAVAFMdAA==.Lirathiel:BAABLgAECn8WAAMaAAgJ5wQqPQBoAAAHAAUJOQQwNwF2AAAaAAUJsgQqPQBoAAAAAA==.Litasfk:BAAALgAECgIJAgAAAA==.Liuni:BAACLgAFFH8FAAIbAAMJiQY3PgCuAAAbAAMJiQY3PgCuAAAuAAQKfygAAhsACQmVFHEfAKsBABsACQmVFHEfAKsBAAAA.Liyin:BAAALgAECgQJCQABLgAECgkJKwAEAIEOAA==.',
Lo='Lobopeste:BAABLgAECn9NAAITAAkJTgvjAwDKAAATAAkJTgvjAwDKAAAAAA==.Loborocco:BAAALgAECgYJBgAAAA==.Locknutz:BAAALgADCgMJAwAAAA==.Loracy:BAAALgADCgcJBwAAAA==.Lorantell:BAAALgAECgMJAwAAAA==.Lorelynn:BAABLgAECn8qAAICAAkJUQ2wVwCWAQACAAkJUQ2wVwCWAQAAAA==.',
Lu='Luci:BAABLgAECn8YAAQVAAgJ6RJ4UACUAQAVAAgJkxJ4UACUAQAIAAMJ1Q7ZLwBDAAAZAAEJAADNiAAAAAABLgAFFAMJCAADAAkVAA==.Lucìan:BAACLgAFFH8FAAIYAAIJtRM0UQB+AAAYAAIJtRM0UQB+AAAuAAQKfyYAAxgACAmIIQgNAPUCABgACAmIIQgNAPUCACQAAQmmBFcSAB0AAAAA.Ludociel:BAAALgAECgUJCgAAAA==.Luna:BAAALgAECgIJAgABLgAFFAMJCgAUAH4eAA==.Lunaclair:BAACLgAFFH8cAAIRAAQJew9hJgDKAAARAAQJew9hJgDKAAAuAAQKf2kAAxEACQnVHWMmAGoCABEACQnVHWMmAGoCABMABwmNEEEqAAYBAAAA.Lunadrus:BAABLgAECn8mAAIEAAgJogmitgAXAQAEAAgJogmitgAXAQAAAA==.Lunarielle:BAACLgAFFH8gAAIPAAQJCBluMABPAQAPAAQJCBluMABPAQAuAAQKfyEAAg8ACAkXHMYVAIkCAA8ACAkXHMYVAIkCAAAA.',
Ly='Lyriaa:BAAALgADCgYJCwAAAA==.',
Ma='Macalatraz:BAAALgAECgMJBwAAAA==.Macfly:BAABLgAECn80AAIPAAkJrRpPKgA0AgAPAAkJrRpPKgA0AgAAAA==.Madmeatballs:BAAALgAECgEJAQABLgAECgkJKwAEAFEfAA==.Magdala:BAAALgAECgYJBgAAAA==.Magicmissile:BAACLgAFFH8QAAIEAAYJSg/gXQAkAQAEAAYJSg/gXQAkAQAuAAQKfyoAAgQACQlqH+YXAMoCAAQACQlqH+YXAMoCAAAA.Makgora:BAAALgAECgMJBAABLgAECgYJFgAWAFkhAA==.Makhvan:BAABLgAFFH8FAAIRAAIJdB2+LwCkAAARAAIJdB2+LwCkAAAAAA==.Maksoon:BAABLgAFFH8FAAISAAIJvhVeGQBTAAASAAIJvhVeGQBTAAAAAA==.Maladjusted:BAAALgAECgMJBAAAAA==.Malevalous:BAAALgAFFAEJAQABLgAFFAMJCQAHAM8RAA==.Maléfique:BAAALgAECgEJAQAAAA==.Mancath:BAAALgAECgkJCwAAAA==.Maplè:BAAALgAECgIJAwABLgAECggJIwAJAKITAA==.Mar:BAAALgADCgMJAwAAAA==.Marlei:BAAALgADCgQJBAABLgAECgkJKwAEAIEOAA==.Marqose:BAAALgADCgcJDgABLgAECgMJBgALAAAAAA==.Matan:BAAALgADCgUJBQAAAA==.',
Me='Medena:BAAALgADCgcJBwAAAA==.Meeko:BAABLgAFFH8FAAIgAAIJJRlYCgBbAAAgAAIJJRlYCgBbAAABLgAFFAgJJAAgAAQhAA==.Melfie:BAABLgAECn8wAAIEAAkJABxSIQCYAgAEAAkJABxSIQCYAgAAAA==.Meliadoul:BAABLgAECn8fAAIEAAkJwAu/cQCWAQAEAAkJwAu/cQCWAQAAAA==.Mellyndra:BAABLgAECn88AAIKAAkJ3x4SCgDqAgAKAAkJ3x4SCgDqAgAAAA==.Mercüry:BAAALgAECgEJBAAAAA==.Mezhren:BAAALgAECgYJCwAAAA==.',
Mh='Mhoramsgirl:BAAALgADCggJCwAAAA==.',
Mi='Midoriya:BAACLgAFFH8IAAMGAAMJHQewKwCfAAAGAAMJHQewKwCfAAAFAAMJyQtmRgCLAAAuAAQKfyMAAwYACQlnEYYvAEsBAAYACAkvEoYvAEsBAAUABQmQEfqEAJQAAAAA.Mistjack:BAABLgAFFH8LAAIFAAUJthFsKQAkAQAFAAUJthFsKQAkAQAAAA==.',
Mo='Momdad:BAACLgAFFH8SAAIOAAUJ6xdUEwAwAQAOAAUJ6xdUEwAwAQAuAAQKfzQAAg4ACQnWIK0HAKMCAA4ACQnWIK0HAKMCAAAA.Mongaux:BAAALgADCgQJBQAAAA==.Monkey:BAAALgAECgQJCgAAAA==.Morrígán:BAAALgADCgUJBQAAAA==.Moxi:BAAALgADCggJEAAAAA==.',
Mu='Muamman:BAAALgAECgMJAwAAAA==.Murda:BAAALgADCgYJCgAAAA==.Murphysflaw:BAAALgADCgUJCAAAAA==.Mutegen:BAAALgAFFAEJAQAAAA==.',
Mx='Mxhealeryduf:BAAALgAECgIJAgAAAA==.',
My='Mystallian:BAAALgAECgQJCQAAAA==.Mystí:BAEALgAFFAIJAgABLgAECgkJNQABAN4dAA==.Mythicplus:BAAALgAECgcJEQAAAA==.Mythosaur:BAAALgADCgEJAQAAAA==.',
['Må']='Måzikeen:BAAALgAECgEJAQAAAA==.',
['Mé']='Mélisande:BAAALgADCgQJBgAAAA==.Mémnoc:BAAALgAECgMJAwAAAA==.',
Na='Nadarien:BAAALgAECgYJDQAAAA==.Nadyia:BAAALgADCgEJAQAAAA==.Nailah:BAAALgADCgcJCwAAAA==.Nannergoat:BAAALgADCgMJAwAAAA==.Nastymikey:BAABLgAECn8bAAIfAAgJNx13BwBzAgAfAAgJNx13BwBzAgAAAA==.Nazdormu:BAABLgAECn8hAAIgAAkJzgOEHwD5AAAgAAkJzgOEHwD5AAAAAA==.',
Ne='Nefarious:BAAALgAECgcJDgAAAA==.Nefarius:BAAALgAECgEJAQABLgAFFAEJAQALAAAAAA==.Neisen:BAABLgAECn8zAAMKAAkJ9RcaEQCMAgAKAAkJ9RcaEQCMAgAHAAUJBwKc+gCeAAAAAA==.Neocold:BAAALgAECgEJAQAAAA==.Neptune:BAAALgADCgYJBgAAAA==.',
Ni='Nizzlix:BAAALgAECgMJAwAAAA==.',
No='Norna:BAAALgADCgcJDwAAAA==.Noz:BAAALgADCgkJCQAAAA==.',
Nu='Nufonewhodis:BAABLgAECn8WAAIWAAYJWSF1HQATAgAWAAYJWSF1HQATAgAAAA==.',
Ny='Nykolas:BAAALgAECgEJAQAAAA==.Nymlindra:BAAALgAECgUJBQABLgAECgkJLgAMAEgPAA==.Nymofthedead:BAABLgAECn80AAMRAAkJPyRhBgBFAwARAAkJPyRhBgBFAwADAAUJyRMNGwD3AAAAAA==.',
Oa='Oakgrove:BAAALgADCgUJBQAAAA==.',
Om='Ombraless:BAAALgAECgMJAwABLgAECgQJCAALAAAAAA==.',
On='Oneforall:BAAALgAECgkJDgAAAA==.',
Op='Ophrizhani:BAAALgAECgMJAwAAAA==.',
Or='Orangegrove:BAAALgAECgYJBQAAAA==.Orpheal:BAAALgAECgUJBQAAAA==.Orphen:BAAALgAECggJEAAAAA==.',
Os='Osìrìs:BAAALgAECgQJCwABLgAFFAIJBQAYALUTAA==.',
Pa='Paddleball:BAAALgADCgQJBAAAAA==.Paladouin:BAAALgAECgYJEwAAAA==.Pandammy:BAAALgAECgkJBQAAAA==.Pantro:BAABLgAECn8hAAMdAAkJyRcACQA4AgAdAAkJyRcACQA4AgAcAAEJAAC9lAAAAAAAAA==.Papalion:BAABLgAECn8jAAIPAAgJCw7sfQBDAQAPAAgJCw7sfQBDAQAAAA==.Paragas:BAAALgADCgkJEAAAAA==.Pawbs:BAAALgAECgQJEwAAAA==.',
Pe='Peanuts:BAAALgADCgcJBwAAAA==.Peoplehugger:BAAALgADCgMJAwAAAA==.',
Pi='Pickleburger:BAAALgAECgEJAQAAAA==.Pinkkrayen:BAAALgAECgQJBwAAAA==.Pinklilydrd:BAAALgAECgUJEAAAAA==.',
Pl='Plaindonut:BAABLgAECn8jAAMYAAcJfyPpAABXAgAYAAcJfyPpAABXAgAkAAEJowjLjgAxAAAAAA==.',
Po='Porple:BAABLgAECn8XAAIOAAgJ3QlJKgBPAQAOAAgJ3QlJKgBPAQAAAA==.',
Pr='Priestdrago:BAAALgADCgUJBQAAAA==.Prissidebow:BAAALgAECgMJCQAAAA==.',
Pu='Puddinpie:BAAALgADCgEJAQAAAA==.',
Qu='Quartz:BAAALgAFFAEJAQABLgAFFAMJEQASAIAkAA==.',
Ra='Rahzule:BAAALgADCgYJBwAAAA==.Ralynne:BAACLgAFFH8HAAIMAAMJwA0bOACuAAAMAAMJwA0bOACuAAAuAAQKfzAAAgwACQkoFSwgAOEBAAwACQkoFSwgAOEBAAAA.Rantis:BAAALgAECggJDQAAAA==.Raskus:BAAALgADCgYJBgAAAA==.Ravenbrook:BAACLgAFFH8gAAISAAYJrSa5AwBGAgASAAYJrSa5AwBGAgAuAAQKfyMAAxIACAlbJXsEAGIDABIACAlbJXsEAGIDABcAAQkwIJVnAFIAAAAA.Rawrr:BAABLgAECn8kAAIZAAkJWQr6KQAuAQAZAAkJWQr6KQAuAQAAAA==.Rawrxd:BAAALgAECgEJAgABLgAECggJDgALAAAAAA==.Raxie:BAACLgAFFH8jAAMeAAYJfRk3HAB+AQAeAAYJfRk3HAB+AQAnAAEJBQ3SFABRAAAuAAQKfy0ABB4ACQnXGqUOAIQCAB4ACQnXGqUOAIQCACcABwnIE90tAGoBABQAAQkBBPGHACgAAAAA.Razeth:BAABLgAECn8VAAIOAAYJ8BZgLgA0AQAOAAYJ8BZgLgA0AQAAAA==.',
Re='Reanne:BAAALgAECgYJEAAAAA==.Rebecka:BAAALgAECgYJBgAAAA==.Res:BAAALgAECgYJCwAAAA==.Rescorla:BAAALgAECgkJDAAAAA==.Rethali:BAAALgADCgQJAgAAAA==.Reysola:BAAALgAECgMJBAABLgAECgMJBgALAAAAAA==.Rezr:BAAALgAECggJDgAAAA==.',
Rh='Rhixa:BAAALgADCgUJBQAAAA==.Rhymunky:BAAALgAFFAIJAgAAAA==.',
Ri='Rifthor:BAABLgAECn8dAAQdAAcJIxIkAgAHAQAdAAYJAxUkAgAHAQAcAAMJKQ8kSQCFAAAYAAIJsAJJ3AAmAAAAAA==.Rillx:BAAALgADCgQJBgAAAA==.Ripmxi:BAABLgAECn87AAIEAAkJPBbdBACQAQAEAAkJPBbdBACQAQAAAA==.',
Ro='Robinski:BAAALgADCgEJAQAAAA==.Robotiss:BAAALgADCgIJAgAAAA==.Rocco:BAAALgADCgYJBwAAAA==.Rodevon:BAAALgADCggJCAAAAA==.Roknasaurus:BAAALgADCgUJCAAAAA==.Romani:BAAALgADCgYJBgAAAA==.Romeo:BAAALgAECgQJBAAAAA==.Ronaldreagnt:BAAALgAECgcJEQAAAA==.',
Ru='Runecat:BAABLgAFFH8NAAMkAAUJbQScMADAAAAkAAQJbQScMADAAAAYAAQJyQVMEQBwAAAAAA==.Runelight:BAACLgAFFH8IAAMeAAMJOQFaPQCEAAAeAAMJOQFaPQCEAAAnAAIJsgHyNgBbAAAuAAQKfxwABB4ACAlQFM4hAMABAB4ABwmbFM4hAMABABQABgn3CpM/APEAACcAAwkQBT9sAG4AAAEuAAUUBQkNACQAbQQA.Runeshock:BAAALgAECgcJDQABLgAFFAUJDQAkAG0EAA==.Runestick:BAAALgAECgMJAwABLgAFFAUJDQAkAG0EAA==.Rupertgiless:BAACLgAFFH8RAAICAAYJpg5zJwCqAQACAAYJpg5zJwCqAQAuAAQKfyYAAgIACQl0G30iAIsCAAIACQl0G30iAIsCAAAA.',
Sa='Sabeckya:BAAALgAECgQJCgAAAA==.Sacksmasher:BAAALgADCgcJDwAAAA==.Sainttristan:BAAALgAECgEJAQAAAA==.Sampleshrimp:BAAALgADCgEJAgAAAA==.Saphyla:BAAALgADCgcJDAAAAA==.Sappheire:BAAALgAECgYJBgAAAA==.Sarcastyx:BAAALgAECgcJCAAAAA==.Sarrod:BAAALgADCgUJBQAAAA==.Saxines:BAABLgAECn8dAAIUAAYJ4w/ONQAqAQAUAAYJ4w/ONQAqAQAAAA==.',
Sc='Scaliefox:BAAALgAECgIJAgABLgAECgkJPAAKAN8eAA==.Scarl:BAAALgADCgUJBQAAAA==.Schwarznacht:BAAALgADCgUJBQAAAA==.Schwarzwölf:BAAALgADCgYJCwAAAA==.Sconzil:BAAALgAECggJEQAAAA==.Scoots:BAAALgADCgQJBAAAAA==.Scrubs:BAAALgAECgYJDQAAAA==.Scrubsevoker:BAAALgAECgUJCgAAAA==.Scumbum:BAAALgADCgIJAgAAAA==.Scyllo:BAAALgAECgQJBgAAAA==.',
Se='Seekndestroy:BAABLgAECn8bAAIMAAgJ8QgtCQCCAAAMAAgJ8QgtCQCCAAAAAA==.Selige:BAAALgAECgQJBAAAAA==.',
Sg='Sgtcuunt:BAAALgAECgUJBQAAAA==.',
Sh='Shackled:BAAALgAECgYJEQAAAA==.Shaenicor:BAAALgADCgIJAgAAAA==.Shankkerz:BAAALgAECgcJDAAAAA==.Shelbo:BAAALgAECgEJAQAAAA==.Shmolda:BAAALgADCgYJBwAAAA==.Shortshammy:BAAALgAECgEJAQABLgAFFAMJCwAEACUJAA==.Shror:BAAALgADCgEJAQABLgAECgUJBQALAAAAAA==.',
Si='Sicarune:BAAALgAECgUJBgABLgAFFAUJDQAkAG0EAA==.Siiegrand:BAABLgAECn8VAAIaAAcJhRCSJQDoAAAaAAcJhRCSJQDoAAAAAA==.Silentswag:BAABLgAECn8VAAIWAAcJLxTZIACPAQAWAAcJLxTZIACPAQAAAA==.Sindrane:BAAALgAECgMJAwABLgAFFAMJBwATAIAQAA==.Sitzho:BAAALgADCgUJCAAAAA==.',
Sk='Skeleton:BAAALgAECgIJAgAAAA==.Skybringer:BAABLgAECn9LAAIHAAkJXhBDCgADAQAHAAkJXhBDCgADAQAAAA==.Skyee:BAABLgAECn8qAAMGAAkJvx0LDAC6AgAGAAkJvx0LDAC6AgAFAAMJGxRxfACpAAAAAA==.Skylos:BAAALgAECgEJAgAAAA==.',
Sl='Slowburn:BAAALgAECgIJAgABLgAFFAMJCAADAAkVAA==.',
Sm='Smexibiotch:BAAALgADCgYJBgABLgAECgIJAgALAAAAAA==.',
So='Soapscum:BAAALgADCgQJBAAAAA==.Soarphium:BAAALgAECgIJAgABLgAFFAcJHAAWAMEOAA==.Solararc:BAAALgADCgEJAgAAAA==.Soleana:BAAALgAECgYJBQAAAA==.Sombra:BAAALgAECgMJBwABLgAECgcJDgALAAAAAA==.Sonicast:BAAALgAECgYJCQAAAA==.Sooie:BAAALgAECgYJEgAAAA==.Soramian:BAAALgADCgcJEgAAAA==.Sosneaky:BAAALgADCgIJAgAAAA==.Soulcacher:BAACLgAFFH8HAAMTAAMJgBChLgCLAAARAAMJ6w1HpwDNAAATAAMJlwmhLgCLAAAuAAQKfzIAAxEACQmqFKFLABACABEACAknFqFLABACABMACAm9D0oeAGQBAAAA.Soxxy:BAAALgAECgEJAQABLgAFFAMJCAADAAkVAA==.',
Sp='Spellgunner:BAABLgAECn8VAAIEAAgJPxsFYQC+AQAEAAgJPxsFYQC+AQAAAA==.Spinsaround:BAAALgADCgEJAQAAAA==.',
St='Stormwulf:BAAALgADCgUJBQABLgAECgYJGAAFAGYYAA==.Stormyprissi:BAAALgAECgQJDAAAAA==.Strombjorn:BAABLgAECn8jAAMJAAgJohPASQCIAQAJAAgJohPASQCIAQAMAAUJwQwLYwC8AAAAAA==.',
['Sø']='Sølaria:BAAALgAECgEJAQAAAA==.',
Ta='Tasireth:BAAALgADCgcJBwAAAA==.',
Te='Tessi:BAACLgAFFH8HAAIEAAMJrgIFoACNAAAEAAMJrgIFoACNAAAuAAQKfxcAAgQABwm3D2aUAFABAAQABwm3D2aUAFABAAAA.',
Th='Thalrian:BAAALgAFFAEJAQABLgAFFAMJDQASAIQfAA==.Thefailnym:BAABLgAECn8YAAMOAAgJ6BdlEgAWAgAOAAgJeRdlEgAWAgAPAAQJUxmqsADjAAAAAA==.Theory:BAABLgAECn8UAAMQAAcJLxGVAwDzAAAQAAcJixCVAwDzAAAjAAIJqBJaAwA8AAABLgAFFAIJCAARACAfAA==.Theylive:BAABLgAECn8dAAIYAAkJJw9iNQDFAQAYAAkJJw9iNQDFAQAAAA==.Thondrin:BAAALgAECgcJDQAAAA==.Thordanil:BAAALgAECgUJBwAAAA==.Thrashedass:BAAALgADCgEJAQAAAA==.',
Ti='Tigerlilliy:BAAALgADCgYJEAAAAA==.Timerek:BAAALgADCgIJAgAAAA==.',
To='Toawulf:BAAALgAECgQJCAABLgAECgYJGAAFAGYYAA==.Toetickla:BAAALgAECgEJAgAAAA==.Tokifuji:BAAALgAECgIJBAABLgAECgQJEwALAAAAAA==.Toranaar:BAAALgAECgcJBwABLgAFFAMJAwALAAAAAA==.Toya:BAABLgAECn80AAIWAAkJZRwHCwBzAgAWAAkJZRwHCwBzAgAAAA==.',
Tr='Trenazen:BAAALgADCgkJCgAAAA==.Trevain:BAAALgAECgEJAgAAAA==.Trimasdrood:BAAALgADCgMJAwAAAA==.Trivia:BAABLgAECn8VAAINAAYJdwYHAwBwAAANAAYJdwYHAwBwAAAAAA==.Trundle:BAAALgAECgEJAwAAAA==.Truthordare:BAABLgAECn8tAAIBAAcJ5AuVFwDmAAABAAcJ5AuVFwDmAAAAAA==.Trysla:BAAALgAECgEJAQAAAA==.',
Tu='Turtei:BAAALgAECgEJAQABLgAFFAgJKgAGAFomAA==.Turtl:BAACLgAFFH8qAAIGAAgJWiZaAAAYAwAGAAgJWiZaAAAYAwAuAAQKfysAAgYACQnmJjcAAPgDAAYACQnmJjcAAPgDAAAA.',
Tw='Twoevil:BAAALgADCgkJCQAAAA==.Twohoof:BAAALgADCgEJAQAAAA==.Twosar:BAAALgAECgIJBAAAAA==.',
Tx='Txìewtkuä:BAAALgADCgkJCQAAAA==.',
Ty='Tyryn:BAAALgAECgYJBgAAAA==.',
Ug='Uglydragon:BAAALgAECgcJDAAAAA==.Uglypally:BAAALgADCgkJCQAAAA==.Uglypetguy:BAAALgAECgIJAgAAAA==.Uglyrogue:BAAALgAECgQJAgAAAA==.Uglyshaman:BAAALgAECgEJAgAAAA==.',
Ul='Ulgrym:BAAALgAECgMJBQAAAA==.Ultimatia:BAAALgADCgMJBwAAAA==.',
Un='Unbalancéd:BAABLgAECn8iAAIFAAYJRiIYGgBHAgAFAAYJRiIYGgBHAgAAAA==.',
Va='Vaeadin:BAAALgAECgQJBQAAAA==.Vahra:BAAALgAECgMJCQAAAA==.Valanther:BAAALgAECgMJAwAAAA==.Valantis:BAAALgADCgEJAQAAAA==.Valgaskav:BAACLgAFFH8EAAIHAAMJiyHgPgAtAQAHAAMJiyHgPgAtAQAuAAQKfy4AAgcACQlmIwkKABcDAAcACQlmIwkKABcDAAAA.Valimond:BAAALgAECgEJAQABLgAECgYJGAAFAGYYAA==.Valric:BAAALgAECgUJBgAAAA==.Vanarrath:BAAALgADCgYJBwAAAA==.Vandryelle:BAAALgADCgIJAgAAAA==.Varge:BAAALgADCgMJAwAAAA==.Varrathos:BAAALgAECgMJBAAAAA==.Vayl:BAAALgAECgMJAwAAAA==.',
Ve='Vegasnight:BAAALgAECgYJDQAAAA==.Velisa:BAAALgADCgYJBgAAAA==.Vella:BAAALgAECgQJBQAAAA==.Vellaria:BAAALgADCgUJBwAAAA==.Ventrue:BAAALgADCgMJAwAAAA==.Verdesoul:BAAALgAECgcJEAABLgAECggJDgALAAAAAA==.Vesyra:BAAALgAECgQJBQAAAA==.',
Vi='Viralyn:BAAALgAECgYJDQABLgAFFAMJBQAbAIkGAA==.Vixøn:BAAALgAECgMJBgAAAA==.',
Vo='Voidluck:BAABLgAECn8SAAIVAAgJvxBkdABIAQAVAAgJvxBkdABIAQAAAA==.Voker:BAAALgAECgMJCQABLgAECgQJEwALAAAAAA==.Voladis:BAAALgAECgYJDQAAAA==.Voladro:BAAALgAECgQJBAAAAA==.Volanie:BAAALgAECgQJAwAAAA==.Volava:BAAALgAECgcJBQAAAA==.Volos:BAACLgAFFH8FAAIHAAIJ4w0tkQCQAAAHAAIJ4w0tkQCQAAAuAAQKfy4AAgcACAm5FkFZAMABAAcACAm5FkFZAMABAAAA.Vordaman:BAACLgAFFH8IAAIRAAMJywUFKwC5AAARAAMJywUFKwC5AAAuAAQKfzQAAhEACQlhEyVOANgBABEACQlhEyVOANgBAAAA.',
Vy='Vynír:BAACLgAFFH8YAAICAAcJ4RyxGAD9AQACAAcJ4RyxGAD9AQAuAAQKfy4AAwIACQmgI7AJAAUDAAIACQk+I7AJAAUDAAEABQkHI40NAOwBAAAA.',
Wa='Waghoba:BAECLgAFFH8tAAIdAAgJYB+4AABcAgAdAAgJYB+4AABcAgAuAAQKfz4AAh0ACQnNJSQAAAADAB0ACQnNJSQAAAADAAAA.Waito:BAAALgAECgQJBwAAAA==.Wandä:BAABLgAECn86AAQbAAkJQB4QCgCSAgAbAAkJcRwQCgCSAgAGAAkJMRMjGwDXAQAFAAcJpxH6QwBcAQABLgAECggJGwADADgaAA==.Wardriccan:BAAALgAECggJDgAAAA==.Warfle:BAAALgADCgYJBgAAAA==.Warhound:BAAALgADCgcJBwAAAA==.Warrionomous:BAACLgAFFH8SAAISAAUJ/hjnCAACAQASAAUJ/hjnCAACAQAuAAQKfxsAAhIACAkeG3gbABICABIACAkeG3gbABICAAEuAAUUBgkQAAQASg8A.Washu:BAACLgAFFH8PAAIZAAQJpBDeEgANAQAZAAQJpBDeEgANAQAuAAQKf0IAAxkACQnaHzsGANQCABkACQnaHzsGANQCAAgAAwlMC1khAHkAAAAA.',
Wh='Whimlock:BAAALgADCgQJBAABLgAFFAMJBwAEAOUcAA==.Whimzie:BAAALgAECgEJAgABLgAFFAMJBwAEAOUcAA==.Whorphium:BAAALgAECggJEgABLgAFFAcJHAAWAMEOAA==.',
Wi='Willow:BAAALgAECgYJCwAAAA==.Winterous:BAAALgAECgcJDAAAAA==.',
Wo='Wonderbread:BAACLgAFFH8LAAIHAAMJlQcfHQC1AAAHAAMJlQcfHQC1AAAuAAQKfzwAAgcACQn3FcQ4AB8CAAcACQn3FcQ4AB8CAAAA.',
Wr='Wrager:BAAALgAECgUJBgAAAA==.Wrathofzaun:BAAALgAECgYJDwAAAA==.',
Wy='Wylest:BAAALgADCgcJBwAAAA==.Wynch:BAAALgAECgkJCQAAAA==.',
['Wâ']='Wârwôlf:BAABLgAECn8pAAMPAAkJHCScBwAhAwAPAAkJHCScBwAhAwANAAQJ+BWyVQDzAAAAAA==.',
Xe='Xenan:BAABLgAECn82AAIHAAkJOxYFOgAbAgAHAAkJOxYFOgAbAgAAAA==.',
Xt='Xtrolldinary:BAABLgAECn8aAAIYAAYJdgtbBwCYAAAYAAYJdgtbBwCYAAAAAA==.',
Xv='Xvp:BAAALgAECgQJCgAAAA==.',
Xy='Xylophy:BAABLgAECn8rAAIIAAkJPBTzCQDJAQAIAAkJPBTzCQDJAQAAAA==.',
Ye='Yeastmode:BAACLgAFFH8cAAIPAAYJNBG0IACCAQAPAAYJNBG0IACCAQAuAAQKfy4AAg8ACAksHaQmAEYCAA8ACAksHaQmAEYCAAAA.Yeasty:BAAALgAFFAEJAgAAAA==.',
Yo='Yonah:BAAALgAECgYJDAAAAA==.',
Yu='Yurc:BAABLgAECn8nAAIhAAkJeBn+CQBUAgAhAAkJeBn+CQBUAgAAAA==.',
Za='Zademan:BAAALgAECgUJBwAAAA==.Zappyu:BAAALgAECgkJBQABLgAECgkJCQALAAAAAA==.Zarkas:BAAALgAECgcJEgAAAA==.Zarquaza:BAAALgAECgYJBgAAAA==.',
Ze='Zeebra:BAABLgAECn8XAAIPAAcJ6xBLCQApAQAPAAcJ6xBLCQApAQAAAA==.Zeg:BAAALgAFFAMJBAAAAA==.Zega:BAAALgAFFAEJAQAAAA==.Zegafur:BAABLgAECn8zAAIYAAkJXhzBFgCRAgAYAAkJXhzBFgCRAgAAAA==.Zeruk:BAABLgAECn8XAAMGAAcJjwJ1YACOAAAGAAYJlAJ1YACOAAAFAAcJpQHflABuAAAAAA==.',
Zi='Zillionbúcks:BAACLgAFFH8cAAIHAAgJWxPBDQAHAgAHAAgJWxPBDQAHAgAuAAQKfxsAAgcACQmvHtEtAGwCAAcACQmvHtEtAGwCAAAA.',
Zu='Zullee:BAAALgAECgEJAQAAAA==.',
Zy='Zylcat:BAAALgAECgYJDAAAAA==.',
['Zê']='Zêddicus:BAABLgAECn81AAMBAAkJtCCyAQDBAgABAAkJtCCyAQDBAgACAAUJHwgM1ACyAAAAAA==.',
['Áq']='Áquafina:BAABLgAECn88AAIEAAkJpg7kXADIAQAEAAkJpg7kXADIAQAAAA==.',
['Åñ']='Åñgêl:BAAALgAECgIJAgAAAA==.',
['Îv']='Îvan:BAAALgADCggJCAAAAA==.',
['Ðö']='Ðö:BAABLgAECn87AAISAAkJNR7kCwCqAgASAAkJNR7kCwCqAgAAAA==.',
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
