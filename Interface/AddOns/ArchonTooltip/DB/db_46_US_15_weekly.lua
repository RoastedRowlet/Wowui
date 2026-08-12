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

local lookup = {'Warlock-Destruction','Warlock-Demonology','DeathKnight-Frost','Mage-Frost','Monk-Mistweaver','Monk-Windwalker','Paladin-Retribution','Unknown-Unknown','Shaman-Restoration','Paladin-Holy','Shaman-Elemental','Hunter-Survival','Hunter-Marksmanship','Hunter-BeastMastery','Evoker-Augmentation','DeathKnight-Unholy','Warrior-Fury','DeathKnight-Blood','Priest-Holy','DemonHunter-Devourer','Rogue-Subtlety','Warrior-Arms','Druid-Restoration','DemonHunter-Havoc','Druid-Balance','DemonHunter-Vengeance','Paladin-Protection','Monk-Brewmaster','Druid-Guardian','Druid-Feral','Priest-Discipline','Shaman-Enhancement','Evoker-Preservation','Warrior-Protection','Rogue-Outlaw','Priest-Shadow','Warlock-Affliction','Mage-Fire','Evoker-Devastation',}
local provider = {region='US',realm='Anvilmar',name='US',type='weekly',zone=46,date='2026-08-11',data={Aa='Aaril:BAAALgAECgcJKAAAAQ==.',
Ab='Abrams:BAAALgAECgEJAQAAAA==.',
Ad='Adel:BAAALgAECgYJDQAAAA==.',
Ae='Aelitha:BAABLgAECn8ZAAMBAAYJCQZ2OQDOAAABAAYJxAR2OQDOAAACAAYJsQQU0gCwAAAAAA==.',
Ak='Akaishi:BAAALgADCgIJAgAAAA==.Akali:BAAALgAFFAIJAwABLgAFFAQJEAADAEUWAA==.Akina:BAAALgAECgQJBAABLgAECgkJKwAEAIEOAA==.',
Al='Alanie:BAAALgAECgIJAgAAAA==.Alathiana:BAAALgADCgUJCAAAAA==.Alcweaver:BAABLgAECn8dAAMFAAcJgiBJIQASAgAFAAcJgiBJIQASAgAGAAYJgA8UQQD7AAAAAA==.Aldea:BAAALgAECgEJAQAAAA==.Alecto:BAAALgAECgMJAwAAAA==.Alialista:BAAALgAECgEJAQAAAA==.Alindia:BAAALgAECgQJCgABLgAECgkJKwAEAIEOAA==.Alirrayia:BAAALgAECgQJBQAAAA==.Alirrayiia:BAACLgAFFH8RAAIHAAYJrgRpKgDhAAAHAAYJrgRpKgDhAAAuAAQKfyoAAgcACQlwFG5CAP8BAAcACQlwFG5CAP8BAAAA.Alkri:BAAALgADCgMJAwAAAA==.Allari:BAAALgAECgYJEwAAAA==.Allikazam:BAAALgADCgYJGAAAAA==.Allystar:BAAALgAECgUJEgAAAA==.Altheia:BAAALgAECgQJBAAAAA==.Althorin:BAAALgAECgEJAwAAAA==.Alvidor:BAABLgAECn9QAAIEAAkJIAkIiABnAQAEAAkJIAkIiABnAQAAAA==.',
Am='Ambrose:BAAALgAECgcJBwAAAA==.Ameria:BAAALgADCgUJBQAAAA==.Ames:BAAALgAECgkJAwAAAA==.Amethen:BAAALgADCgEJAQAAAA==.Amexican:BAAALgAECgEJAQAAAA==.Amybabe:BAAALgAFFAIJAgAAAA==.',
An='Anastos:BAAALgAECgUJBQAAAA==.Andydufresne:BAAALgAECgQJDwABLgAFFAEJAwAIAAAAAA==.Anestesiax:BAAALgAECgIJBAAAAA==.Angryqueer:BAAALgADCgEJAQAAAA==.',
Ao='Aowl:BAAALgAECgcJCwAAAA==.',
Ap='Apocketheory:BAAALgADCgIJAgAAAA==.Apolloerosb:BAAALgAECgYJDwABLgAECgcJLgAJANccAA==.Apolloerosc:BAAALgAECgUJCAABLgAECgcJLgAJANccAA==.Apolloerosp:BAAALgAECgYJEwABLgAECgcJLgAJANccAA==.Apollossham:BAABLgAECn8uAAIJAAcJ1xyWIwA5AgAJAAcJ1xyWIwA5AgAAAA==.',
Ar='Archpaladin:BAAALgAECgQJBAAAAA==.Arkanaun:BAABLgAECn8dAAMHAAYJRBdpcwCUAQAHAAYJRBdpcwCUAQAKAAUJvRTvTAAHAQAAAA==.',
As='Ashes:BAAALgAECgcJAQAAAA==.Ashrán:BAAALgAECgYJCQAAAA==.Ashyluna:BAAALgAECgQJBAAAAA==.Astianna:BAAALgADCgMJAwAAAA==.',
Au='Aule:BAAALgAECgIJAwAAAA==.Aurinia:BAAALgADCgQJAgAAAA==.Auroradinlee:BAAALgAECgkJBgAAAA==.',
Av='Avradea:BAAALgAECgEJAQABLgAECgkJKwAEAIEOAA==.',
Az='Azareth:BAAALgADCggJCAAAAA==.',
Ba='Babbayagga:BAAALgAECgEJAQAAAA==.Baconatorr:BAAALgAECgQJBQAAAA==.Bagelbags:BAAALgADCgEJAQAAAA==.Bahler:BAAALgADCgUJBQABLgAECgMJAwAIAAAAAA==.Baji:BAACLgAFFH8TAAIJAAQJax6/EgA7AQAJAAQJax6/EgA7AQAuAAQKfzsAAwkACQktIvAHADADAAkACQktIvAHADADAAsABQn+FVlKAAsBAAAA.Baklan:BAAALgAECgMJAwAAAA==.Barefaall:BAACLgAFFH8vAAQMAAkJBh0YAgDfAQAMAAUJGCAYAgDfAQANAAcJHxcTCgDCAQAOAAEJxR2lWABmAAAuAAQKf1gABA0ACQlnJOUAAD4DAA0ACQllJOUAAD4DAAwACAldIvQAAKkCAA4ABAn0IH0PAHsBAAAA.Barefall:BAACLgAFFH8MAAIMAAMJYhCNDgC0AAAMAAMJYhCNDgC0AAAuAAQKfx0AAgwACQnCFNwEACsBAAwACQnCFNwEACsBAAEuAAUUCQkvAAwABh0A.Barefalls:BAACLgAFFH8RAAIMAAMJshyYDADTAAAMAAMJshyYDADTAAAuAAQKfzAAAwwACQk9H/8GAK8CAAwACQk9H/8GAK8CAA0AAQmMAaCWACIAAAEuAAUUCQkvAAwABh0A.Barelywolf:BAABLgAECn8mAAMGAAkJwB+EEQA4AgAGAAcJ5CCEEQA4AgAFAAgJLxfXIgAIAgABLgAFFAMJBgAPACwLAA==.Bashira:BAABLgAECn8eAAIOAAkJsAonWQCZAQAOAAkJsAonWQCZAQAAAA==.Bast:BAACLgAFFH8IAAMQAAMJPwdVtQC8AAAQAAMJPwdVtQC8AAADAAEJVgM4LAA4AAAuAAQKfzUAAxAACQnuFtMzAC8CABAACQnuFtMzAC8CAAMABAmJDbIoAI4AAAAA.Bastrillan:BAAALgAECgUJBwAAAA==.Bathøry:BAAALgAECgkJAwAAAA==.',
Be='Bearophe:BAAALgAECgEJAgAAAA==.Beerfist:BAAALgAECgEJAQAAAA==.Belfor:BAAALgAECgMJAwAAAA==.Bellock:BAAALgAECgMJAwAAAA==.Bendroyd:BAAALgAECgIJAgAAAA==.Benisbagina:BAAALgADCggJCQAAAA==.Bergonator:BAABLgAECn8gAAIRAAYJcRC9TwBpAQARAAYJcRC9TwBpAQAAAA==.Berrodiah:BAACLgAFFH8GAAMDAAMJzApiEACqAAADAAMJmgliEACqAAAQAAMJrAOtxQCgAAAuAAQKfx0ABAMACAl7GvoBAPcBAAMABwmNG/oBAPcBABIACAkrEBcgAFMBABAAAwmaCwsMAZ0AAAAA.Bettyswalls:BAAALgAECgMJAwAAAA==.Beyarago:BAAALgAECgcJCwAAAA==.',
Bh='Bheiroth:BAACLgAFFH8IAAITAAQJZCCcFAAfAQATAAQJZCCcFAAfAQAuAAQKfzIAAhMACQlIJHIEADsDABMACQlIJHIEADsDAAAA.',
Bi='Birds:BAAALgAECgkJEQAAAA==.',
Bl='Bladeygaga:BAABLgAECn85AAIUAAkJpR+hCwDqAgAUAAkJpR+hCwDqAgAAAA==.Blasé:BAAALgAECgcJCAAAAA==.Blazingblood:BAAALgADCgUJAQAAAA==.Bloodknight:BAAALgADCgYJCQAAAA==.Bluekrayen:BAAALgAECgUJCAAAAA==.Bluett:BAAALgAECgUJCwAAAA==.Bláckøut:BAAALgADCgYJDAAAAA==.',
Bo='Bodhi:BAABLgAECn8WAAIVAAcJNhAQJwDAAQAVAAcJNhAQJwDAAQAAAA==.Bogertus:BAACLgAFFH8RAAIRAAMJgCTIIgApAQARAAMJgCTIIgApAQAuAAQKf0AAAxEACQnSJnwAAIwDABEACQnSJnwAAIwDABYAAgn1HHIpAKUAAAAA.Bonobo:BAAALgAECgYJCQAAAA==.Boomertunes:BAABLgAECn8mAAMCAAkJYxgtJgBFAgACAAkJYxgtJgBFAgABAAIJGwFEVAAAAAAAAA==.',
Br='Brein:BAACLgAFFH8FAAIXAAMJgBhlFgDDAAAXAAMJgBhlFgDDAAAuAAQKf14AAhcACQkSJroAAOADABcACQkSJroAAOADAAAA.Brewmaster:BAAALgAECgIJAwAAAA==.Brewwmaster:BAABLgAECn8kAAQSAAkJrBjiFwCmAQASAAkJIBXiFwCmAQAQAAYJtBfWfACKAQADAAEJ+he5FgA2AAAAAA==.Bricklethumb:BAAALgAECgMJAwABLgAECgYJGAAFAGYYAA==.Brickred:BAAALgAECgIJAgAAAA==.Brynodd:BAAALgAECgUJDAAAAA==.',
Bu='Bubblybetty:BAAALgAECgEJAQAAAA==.Bucketeer:BAABLgAECn8rAAIEAAkJUR/KHACwAgAEAAkJUR/KHACwAgAAAA==.Buffs:BAAALgADCgEJAQAAAA==.Bullminator:BAAALgAECggJDgAAAA==.Bursona:BAAALgAECgEJAQAAAA==.Butterfree:BAAALgAECgUJDAABLgAFFAEJAQAIAAAAAA==.',
['Bô']='Bôngo:BAAALgAECgYJBgAAAA==.',
Ca='Canaprey:BAAALgAECgEJAQAAAA==.Cards:BAAALgAECgYJCgAAAA==.Carkrash:BAAALgAECgUJBQAAAA==.Casterkang:BAAALgAECgUJCQAAAA==.Catshunter:BAABLgAECn8dAAIOAAgJdxzNCQDfAQAOAAgJdxzNCQDfAQAAAA==.',
Ce='Celaa:BAABLgAECn8rAAIEAAkJgQ7BXgDDAQAEAAkJgQ7BXgDDAQAAAA==.',
Ch='Chanka:BAABLgAECn8mAAIBAAYJmA0ACADCAAABAAYJmA0ACADCAAAAAA==.Chantillary:BAAALgAECgUJDAAAAA==.Chargerkang:BAAALgADCgYJBgAAAA==.Charise:BAAALgAECgMJAwAAAA==.Chchanges:BAAALgAECgEJAQAAAA==.Cheesy:BAABLgAECn8qAAICAAgJFA1LbgBfAQACAAgJFA1LbgBfAQAAAA==.Chicken:BAAALgAECgYJEgAAAA==.Chonk:BAAALgADCgEJAQAAAA==.Chopzullee:BAABLgAECn8oAAIGAAgJSBGsBAB3AQAGAAgJSBGsBAB3AQAAAA==.',
Ci='Circii:BAAALgAECgQJBAAAAA==.Cirya:BAAALgAECgcJCwAAAA==.',
Cl='Cleric:BAAALgADCgUJBQAAAA==.Clortho:BAABLgAECn8mAAMYAAYJQxCZCgD3AAAYAAYJQxCZCgD3AAAUAAEJ6gFhPwEWAAAAAA==.Clorthö:BAAALgADCgUJBQAAAA==.',
Co='Coldrune:BAAALgADCgUJBQABLgAFFAcJEAAZADQIAA==.Coljack:BAAALgAECggJCAAAAA==.Colljack:BAACLgAFFH8iAAIKAAgJjBvBDgDOAQAKAAgJjBvBDgDOAQAuAAQKfyEAAwoACQkgIZwJANgCAAoACQkgIZwJANgCAAcABQlOEtO5ABIBAAAA.Coughlin:BAAALgAECgEJAQAAAA==.',
Cr='Crocbait:BAAALgAECgcJEQAAAA==.Cryptoe:BAACLgAFFH8MAAIEAAMJdhRTgQDUAAAEAAMJdhRTgQDUAAAuAAQKfyQAAgQACQklGLMNAIgBAAQACQklGLMNAIgBAAAA.Cryptwo:BAAALgAFFAEJAwABLgAFFAMJDAAEAHYUAA==.',
Cu='Cudlsac:BAAALgAECgQJBQAAAA==.',
Da='Daedelus:BAABLgAECn8uAAMUAAkJCBfNCwBBAQAUAAkJ2hbNCwBBAQAaAAgJsRBEBQDXAAAAAA==.Daglon:BAABLgAECn8dAAMHAAgJIhi5CQDWAQAHAAcJQhu5CQDWAQAbAAQJtwd8OgBzAAABLgAFFAMJBAAIAAAAAA==.Dagz:BAAALgAECgQJBAABLgAFFAMJBAAIAAAAAA==.Dakina:BAAALgADCgYJBgAAAA==.Daraedra:BAABLgAECn8hAAIEAAcJ0wTALgCZAAAEAAcJ0wTALgCZAAAAAA==.Darkenvoid:BAAALgADCgkJDQAAAA==.',
De='Deathslight:BAAALgAECgQJBwAAAA==.Dedaeste:BAAALgADCgUJBwAAAA==.Deeznutticus:BAACLgAFFH8lAAIRAAkJIBV2BAAZAgARAAkJIBV2BAAZAgAuAAQKfyEAAxEABwnCIkgYAIkCABEABwnCIkgYAIkCABYAAgkBHdBcAGoAAAAA.Defnotisis:BAABLgAECn8dAAMcAAgJhxTKKABsAQAcAAcJCRbKKABsAQAGAAgJtAs7RADuAAABLgAFFAQJEAADAEUWAA==.Defnotkity:BAABLgAFFH8HAAMdAAMJLg5JLABpAAAeAAIJ2QfiFwB0AAAdAAIJzBBJLABpAAAAAA==.Demonspud:BAABLgAECn8dAAIUAAcJhRIYZgBaAQAUAAcJhRIYZgBaAQAAAA==.Demotard:BAAALgAECgIJAQAAAA==.Denxster:BAAALgAECgYJDgAAAA==.Dersan:BAABLgAECn8nAAIBAAgJ8AAuPgA0AAABAAgJ8AAuPgA0AAAAAA==.Destriant:BAABLgAECn83AAIbAAkJyxliCgAkAgAbAAkJyxliCgAkAgAAAA==.Devilschant:BAAALgAECgYJCgAAAA==.Devilshadow:BAAALgAECgUJBwABLgAECgYJCgAIAAAAAA==.Dewbert:BAAALgADCgQJBAAAAA==.Dewburt:BAAALgAECgEJAQAAAA==.Deylia:BAAALgAECggJEwABLgAFFAcJJQAfAEMXAA==.',
Dh='Dhyana:BAAALgAECgIJAgABLgAECgMJCAAIAAAAAA==.',
Di='Dilithia:BAABLgAECn8gAAIQAAYJpQOhEgGVAAAQAAYJpQOhEgGVAAAAAA==.Dillion:BAAALgAECgYJCAAAAA==.Dinonuggies:BAAALgADCgcJBwAAAA==.Dionin:BAAALgAECgEJAQAAAA==.Dira:BAAALgAFFAIJAgABLgAFFAgJIgAgAA4aAA==.Dirkbanne:BAAALgADCgYJBgAAAA==.Dizzyhealz:BAAALgADCgEJAQAAAA==.Dizzyhuntres:BAAALgAECgEJAQAAAA==.',
Do='Dodoubleg:BAAALgAECgYJEAAAAA==.Dominique:BAAALgADCgYJBgAAAA==.Donzilch:BAEALgAECgQJBAAAAA==.Donzilly:BAAALgAECgUJBQAAAA==.Dooberrt:BAAALgAECgIJAgAAAA==.Dooburt:BAABLgAECn8ZAAIHAAkJtBJIFQAyAQAHAAkJtBJIFQAyAQAAAA==.Doombringers:BAAALgAECgUJCAAAAA==.',
Dr='Dracaric:BAABLgAECn8rAAIPAAkJEhbUGAAQAgAPAAkJEhbUGAAQAgAAAA==.Draeca:BAAALgAECgUJCQAAAA==.Dragondznut:BAAALgAECgQJBQAAAA==.Drakhar:BAAALgADCgIJAgABLgAECgcJDQAIAAAAAA==.Drfrostie:BAABLgAECn8UAAIEAAcJSBIrmgChAQAEAAcJSBIrmgChAQAAAA==.Drgunner:BAAALgAECgcJDwAAAA==.Driatin:BAAALgAFFAEJAQAAAA==.Drkladykikyo:BAABLgAECn8XAAITAAkJFQOLQQDmAAATAAkJFQOLQQDmAAAAAA==.Druroo:BAAALgAECgEJAQABLgAFFAQJBwAQADUWAA==.Druterr:BAAALgAECgIJAgABLgAFFAMJBAAIAAAAAA==.',
Du='Dumb:BAACLgAFFH8PAAIhAAUJLAyTBgCJAQAhAAUJLAyTBgCJAQAuAAQKfyMAAiEACAnoG28LAH4CACEACAnoG28LAH4CAAAA.Durø:BAABLgAECn8WAAIUAAgJryLZDAAZAwAUAAgJryLZDAAZAwAAAA==.Duskhunter:BAAALgADCgEJAQAAAA==.',
Dy='Dyanisian:BAAALgADCgYJCAAAAA==.',
['Dè']='Dègenerate:BAACLgAFFH8TAAIiAAQJuh7wBwBaAQAiAAQJuh7wBwBaAQAuAAQKf0QAAiIACQmOIE8EAOICACIACQmOIE8EAOICAAAA.',
Ed='Edagerran:BAAALgADCgkJCQAAAA==.Eddy:BAABLgAFFH8GAAIgAAMJrgc9DQCGAAAgAAMJrgc9DQCGAAAAAA==.',
Ei='Eilae:BAABLgAECn8iAAIOAAkJvwa9KQCwAAAOAAkJvwa9KQCwAAAAAA==.Eirhakan:BAAALgAECgQJCAAAAA==.',
El='Elrethyl:BAABLgAECn8WAAIHAAcJXhgadwCAAQAHAAcJXhgadwCAAQAAAA==.Elvanus:BAAALgADCgYJBgAAAA==.Elêktra:BAABLgAECn8vAAILAAkJSA9dMwBuAQALAAkJSA9dMwBuAQAAAA==.',
Em='Emet:BAAALgAECgQJDAABLgAECgkJTwAJACAeAA==.',
Ep='Epicnym:BAAALgAECgYJBwAAAA==.Epicsmoke:BAACLgAFFH8UAAIRAAMJDxzCGgDOAAARAAMJDxzCGgDOAAAuAAQKf24AAhEACQkaJSECAFYDABEACQkaJSECAFYDAAAA.Epidemius:BAAALgAECgkJCgAAAA==.',
Er='Erevan:BAABLgAECn84AAMVAAkJ3Bu8CACbAgAVAAkJ3Bu8CACbAgAjAAEJpwABEAAcAAAAAA==.Erinn:BAAALgAECgMJBgAAAA==.Eroica:BAAALgADCgYJBwAAAA==.Eronys:BAAALgAFFAIJAQAAAA==.',
Es='Esdeath:BAABLgAECn8tAAMQAAkJDhRETwDVAQAQAAkJDhRETwDVAQASAAYJWga4PgCVAAAAAA==.',
Et='Etharia:BAAALgADCgUJAwAAAA==.',
Ev='Evilsmeghead:BAAALgADCgEJAQAAAA==.',
Ex='Exiledguy:BAAALgADCgYJBgAAAA==.Extenze:BAACLgAFFH8HAAIUAAMJUhNxYADOAAAUAAMJUhNxYADOAAAuAAQKfy4AAhQACQnSHv4ZAHgCABQACQnSHv4ZAHgCAAAA.',
Ez='Ezykiah:BAAALgAECgYJCgAAAA==.',
Fa='Falconponch:BAAALgADCgEJAQAAAA==.',
Fe='Feda:BAAALgAECgIJAgAAAA==.Felbjorn:BAAALgAECgEJAgAAAA==.Felgibson:BAAALgAECgQJBQAAAA==.Felkang:BAAALgADCgkJCQAAAA==.Fergusmcld:BAAALgADCgIJAgAAAA==.Ferryman:BAABLgAECn8gAAIOAAkJ+hLEYACFAQAOAAkJ+hLEYACFAQAAAA==.',
Fi='Fieryfrost:BAAALgADCgEJAQAAAA==.',
Fl='Flingor:BAAALgAECgYJEAAAAA==.Flokha:BAAALgADCgEJAQAAAA==.',
Fo='Forphium:BAACLgAFFH8eAAIVAAgJQA2lBACkAQAVAAgJQA2lBACkAQAuAAQKfyAAAhUACQn9IH0NAMQCABUACQn9IH0NAMQCAAAA.',
Fr='Fredolf:BAAALgAECgEJAQAAAA==.Freespirit:BAABLgAFFH8SAAMNAAYJqx31BACfAQANAAUJ3CL1BACfAQAOAAMJ4xRkLQDuAAABLgAFFAkJPQAkANQiAA==.Freydís:BAAALgAECgUJCwAAAA==.Freyå:BAAALgAECgIJAgAAAA==.Friarkuck:BAAALgADCggJCAAAAA==.Friedbones:BAAALgAECgUJDAAAAA==.Frostiedk:BAAALgAECgEJAQAAAA==.Frostieheals:BAAALgAECgQJBQAAAA==.Frostiepal:BAAALgAECgMJAwAAAA==.Frostlilliy:BAAALgADCggJCwAAAA==.',
['Fü']='Fürbie:BAAALgAECgIJAwAAAA==.',
Ga='Gahlina:BAABLgAECn8WAAMJAAgJ2xQIMwDnAQAJAAgJ2xQIMwDnAQALAAEJ1wEzlgAeAAAAAA==.Galdorian:BAAALgADCgYJCQABLgAECgkJHgAOALAKAA==.Galynda:BAAALgADCgcJCQAAAA==.Ganhammer:BAAALgAECggJBQAAAA==.Garshan:BAAALgAECgMJBAAAAA==.',
Ge='Genevieve:BAAALgAECgUJDAAAAA==.Genjimain:BAABLgAECn8lAAMXAAkJBhqRHgBKAgAXAAkJBhqRHgBKAgAeAAMJ9wyhNQCHAAAAAA==.Genjí:BAAALgAECgEJAwAAAA==.Geris:BAAALgAECgQJBQAAAA==.Gertruide:BAAALgADCgUJBQAAAA==.',
Gh='Ghendala:BAAALgADCggJEwAAAA==.',
Gi='Gillesmon:BAAALgAFFAMJBAAAAA==.Gilleyy:BAAALgAECgcJCAAAAA==.Gincainn:BAAALgAECgEJAgAAAA==.Gird:BAABLgAECn8oAAIKAAgJ4Q1+OABrAQAKAAgJ4Q1+OABrAQAAAA==.Girdlock:BAAALgAECgYJBwAAAA==.',
Gl='Glaiveyjones:BAAALgAECgEJAQAAAA==.',
Gn='Gnymesis:BAABLgAECn8VAAMlAAcJFh7nAQDFAQAlAAYJxx/nAQDFAQACAAMJvResFQDHAAAAAA==.',
Go='Goatmonger:BAAALgAECgYJBgAAAA==.Goinpostal:BAAALgAECgIJAgAAAA==.Goldblade:BAAALgAECgkJEwAAAA==.Goodvsevil:BAAALgAECgQJBAAAAA==.Gordek:BAABLgAECn8dAAMHAAkJsRpHLQBLAgAHAAkJsRpHLQBLAgAKAAIJhBCpdwBfAAAAAA==.Gorlthov:BAAALgAFFAEJAQABLgAFFAQJGAARACIkAA==.Gothitelle:BAAALgAECgIJBwAAAA==.Goöse:BAACLgAFFH8ZAAIQAAYJJh7dAwDEAQAQAAYJJh7dAwDEAQAuAAQKfycAAhAACAmDJusGAGsDABAACAmDJusGAGsDAAAA.',
Gr='Grantaron:BAABLgAECn83AAIHAAkJ2iDYGACuAgAHAAkJ2iDYGACuAgAAAA==.Gravarii:BAAALgADCgcJEwAAAA==.Grimskul:BAABLgAECn8zAAMQAAkJkB3DGgCmAgAQAAkJkB3DGgCmAgADAAYJDxSUBwCBAQAAAA==.Grindor:BAAALgADCgEJAQAAAA==.Grntitan:BAAALgAECgQJDwAAAA==.Gruid:BAAALgADCgcJDwAAAA==.',
Gu='Guinessbrew:BAAALgAECgEJAQAAAA==.',
Gw='Gwoohoori:BAAALgAECggJEwAAAA==.',
Gy='Gyra:BAAALgAECgYJEQAAAA==.Gyrojetli:BAAALgAECgQJBQAAAA==.',
Ha='Halukari:BAABLgAECn8jAAMdAAcJryKFAgD6AQAdAAcJryKFAgD6AQAZAAUJ5xoSCQAyAQABLgAFFAcJJQAfAEMXAA==.Harfnan:BAAALgAECgIJAgAAAA==.Harrin:BAACLgAFFH8MAAIEAAQJMQXYRgCwAAAEAAQJMQXYRgCwAAAuAAQKfx0AAgQABwn2D4ijADUBAAQABwn2D4ijADUBAAAA.',
He='Healingwater:BAAALgAECgIJAwAAAA==.Herracles:BAAALgAECgcJDgAAAA==.',
Hi='Hierodule:BAAALgAECgEJAQAAAA==.Hiimriven:BAAALgAECgIJAgABLgAECgYJFgAVAFkhAA==.Hinal:BAABLgAECn8gAAIHAAkJMhtdKABhAgAHAAkJMhtdKABhAgAAAA==.',
Ho='Hojo:BAAALgADCgUJCAAAAA==.Holyenabler:BAABLgAFFH8UAAIbAAMJegwUDwCQAAAbAAMJegwUDwCQAAAAAA==.Honzo:BAAALgADCgkJCQAAAA==.Hootiehoo:BAAALgADCgMJAwAAAA==.',
Hu='Huflunggoo:BAAALgADCgkJDQAAAA==.Huflungpoop:BAABLgAECn80AAIGAAkJqBpcEQA6AgAGAAkJqBpcEQA6AgAAAA==.Hunterborn:BAAALgAFFAIJAgAAAA==.',
Hy='Hypercube:BAAALgAECgQJBwAAAA==.',
['Hè']='Hèalz:BAAALgAECgYJBgABLgAECgkJSgARAB0gAA==.',
Ic='Icasemydps:BAAALgAECgEJAQAAAA==.Icespiçe:BAAALgAECgkJCQAAAA==.Ickixia:BAAALgADCgQJBAAAAA==.',
Il='Ilkaressa:BAAALgADCgQJBAAAAA==.Ilun:BAAALgAECgIJAgAAAA==.',
Im='Imcruel:BAACLgAFFH8yAAMEAAgJJxpbIQD6AQAEAAgJJxpbIQD6AQAmAAMJlBR8AwDSAAAuAAQKfzAAAgQACQnNJZ8HAEEDAAQACQnNJZ8HAEEDAAAA.Imisis:BAAALgAECgcJCgAAAA==.Ims:BAAALgAECggJCAAAAA==.',
In='Ink:BAACLgAFFH8NAAIEAAQJKxGMYwAbAQAEAAQJKxGMYwAbAQAuAAQKfycAAgQABwm2IB1aAM8BAAQABwm2IB1aAM8BAAAA.',
Is='Istaria:BAAALgAECgMJCAAAAA==.Isujr:BAABLgAECn8ZAAIQAAcJ8hIKcQCmAQAQAAcJ8hIKcQCmAQAAAA==.',
Ja='Jacaerys:BAAALgADCgYJBgAAAA==.Jackiegan:BAABLgAECn8rAAQcAAkJBSGfBAD7AgAcAAkJBSGfBAD7AgAGAAEJahEzjwBCAAAFAAEJJgel0wAeAAAAAA==.Jackson:BAAALgAECgcJDQAAAA==.Jagerdemon:BAAALgAECgkJCQAAAA==.Jagerpalster:BAAALgAECgEJAQABLgAECgkJCQAIAAAAAA==.Jagershamer:BAAALgAECgMJAwABLgAECgkJCQAIAAAAAA==.Jasperine:BAAALgAECgIJAgABLgAFFAkJPQAkANQiAA==.',
Jc='Jckskellngtn:BAAALgADCgMJAwAAAA==.',
Je='Jerce:BAAALgADCgUJBQAAAA==.Jeryatric:BAAALgADCgcJBwAAAA==.',
Jh='Jhala:BAAALgADCgkJDwAAAA==.',
Ji='Jinnxx:BAAALgAECgMJBAABLgAFFAgJIgAgAA4aAA==.',
Jo='Joshcalc:BAABLgAFFH8GAAIZAAMJNyPVHAA0AQAZAAMJNyPVHAA0AQAAAA==.Joskel:BAABLgAECn8vAAQCAAgJDw1acwBTAQACAAgJiQxacwBTAQAlAAYJMQToFgDIAAABAAIJNgxqMQBYAAAAAA==.',
Ju='Juacqer:BAAALgAECgUJDAAAAA==.Juggarnaut:BAAALgADCgYJCAAAAA==.',
Ka='Kaant:BAABLgAECn9PAAMJAAkJIB7QEQC/AgAJAAkJIB7QEQC/AgALAAgJox5WEwBTAgAAAA==.Kaeni:BAAALgADCgMJAwAAAA==.Kaetiegh:BAAALgAECgEJAQAAAA==.Kaidevyn:BAABLgAECn9PAAMDAAkJdxtsAgC/AQADAAkJdxtsAgC/AQAQAAQJWgqEGQGMAAAAAA==.Kaiste:BAAALgADCgEJAQAAAA==.Kaleine:BAAALgAECgYJCAAAAA==.Kardead:BAAALgAECgMJAwAAAA==.Kardren:BAAALgAECgUJDAAAAA==.Kat:BAAALgAECgMJAwAAAA==.',
Ke='Keiko:BAAALgAECggJDwAAAA==.Keiran:BAABLgAECn81AAMOAAkJ4yJ7CgACAwAOAAkJ4yJ7CgACAwANAAgJpRzPEgCgAgAAAA==.Kelazurin:BAAALgADCgEJAQAAAA==.Kellistair:BAAALgADCgYJBgABLgADCgcJEAAIAAAAAA==.Keläo:BAAALgADCgUJCQAAAA==.Kenix:BAAALgAECgEJAQABLgAECgcJDgAIAAAAAA==.Kenshii:BAAALgAECgUJBQAAAA==.Keyadish:BAAALgADCgYJDQAAAA==.Keys:BAACLgAFFH8HAAIVAAMJlhW+KQDfAAAVAAMJlhW+KQDfAAAuAAQKfyYAAhUACAkTHrkQAJwCABUACAkTHrkQAJwCAAAA.',
Kh='Khalnerys:BAACLgAFFH8FAAMPAAIJLwadWABsAAAPAAIJLwadWABsAAAnAAEJ5AFeEQAoAAAuAAQKfykABA8ACQk1CrZIAAgBAA8ACQmACLZIAAgBACcABQl4CY8WAK0AACEAAwlOB0IxAGQAAAAA.Khaotick:BAECLgAFFH8SAAQBAAcJpg8jBQDsAAACAAQJGhASKADsAAABAAMJAhIjBQDsAAAlAAEJAADDHAAAAAAuAAQKfxUABAEACAlDHAUXAOsAAAIAAwmPHm6qAO4AAAEABQmLGgUXAOsAACUAAQkAALg0ADIAAAEuAAQKCQk1AAEA3h0A.Khemiko:BAAALgAECgMJAwAAAA==.Khitt:BAAALgAECgEJAQABLgAECgMJCAAIAAAAAA==.Khoulock:BAACLgAFFH8WAAICAAkJ2Q4aMwB6AQACAAkJ2Q4aMwB6AQAuAAQKfzUABAIACQnKIDQQAMsCAAIACQm6IDQQAMsCACUABQliItUTADIBAAEAAwl9ENU+ALkAAAAA.',
Ki='Kimmi:BAABLgAECn8cAAMBAAkJNAlVFwDoAAABAAkJNAlVFwDoAAACAAIJ1gAqaAESAAAAAA==.Kimmispally:BAAALgAECgcJCAAAAA==.Kiro:BAAALgADCgQJBQAAAA==.',
Kn='Knowimsayin:BAAALgAECgEJAQAAAA==.',
Ko='Kota:BAAALgAECgEJAwAAAA==.Kotablue:BAAALgAECgEJAQAAAA==.Kotalock:BAAALgAECgcJCgAAAA==.Kotateal:BAAALgAECgYJCwAAAA==.Kotawar:BAAALgAECgIJBAAAAA==.',
Kr='Krelian:BAAALgADCgEJAQAAAA==.Kristinal:BAAALgADCgUJBQAAAA==.Kruelshot:BAACLgAFFH8QAAMOAAQJMiORHwCGAQAOAAQJMiORHwCGAQAMAAEJiwv6MQBKAAAuAAQKfxYAAw4ACAnFJGUSAL4CAA4ACAnFJGUSAL4CAA0ABwlqEgAyAKgBAAEuAAUUCAkyAAQAJxoA.Krux:BAAALgAECgEJAQAAAA==.',
Kt='Kthxbye:BAAALgAECgUJBwABLgAECgkJCQAIAAAAAA==.',
Ku='Kumcookies:BAAALgADCgEJAQAAAA==.Kungfuprissy:BAAALgAECgMJBwAAAA==.Kuraishin:BAACLgAFFH8UAAIeAAMJXB9bDADvAAAeAAMJXB9bDADvAAAuAAQKf5oAAx4ACQnNJUgCAAkDAB4ACQnNJUgCAAkDAB0ACAnnImkFALYCAAEuAAUUBAkcABAAew8A.Kuroakuma:BAAALgAECgYJEAAAAA==.Kuterr:BAAALgAFFAMJBAAAAA==.Kuvara:BAAALgADCgkJCgAAAA==.',
Kv='Kvnnp:BAAALgADCgYJBgAAAA==.Kvnpro:BAAALgADCgUJBwAAAA==.Kvnxx:BAAALgADCgUJBQAAAA==.',
Kw='Kwandashadow:BAAALgAECgUJDgAAAA==.',
Ky='Kylemonk:BAAALgADCgEJAQAAAA==.Kyrae:BAAALgADCgcJEAAAAA==.',
['Ké']='Kéres:BAAALgADCgkJEAAAAA==.',
La='Lagspike:BAABLgAECn8gAAIEAAgJqBVTlgCnAQAEAAgJqBVTlgCnAQAAAA==.Latheal:BAAALgAECgYJCAAAAA==.Latto:BAACLgAFFH8QAAMDAAQJRRY0CAAgAQADAAQJRRY0CAAgAQAQAAIJLAi0bwB6AAAuAAQKfxUABAMACQkiFCcWACgBABIABglrExclACoBAAMABAnWFycWACgBABAAAgkgBCtbAUgAAAAA.Lavi:BAABLgAECn8dAAIHAAgJDA5rkQBPAQAHAAgJDA5rkQBPAQAAAA==.',
Lb='Lbk:BAAALgADCgIJAgAAAA==.',
Le='Lejeune:BAAALgAECgUJDAAAAA==.Lengex:BAABLgAECn8YAAIiAAkJ5xNGBABvAQAiAAkJ5xNGBABvAQAAAA==.Lero:BAABLgAECn8iAAIcAAkJuCF0BQDpAgAcAAkJuCF0BQDpAgAAAA==.Lerwindion:BAABLgAECn8qAAIfAAkJYx2VCQCiAgAfAAkJYx2VCQCiAgABLgAFFAQJBwAQADUWAA==.Lescaryn:BAAALgAECgEJAQAAAA==.Lexoh:BAAALgAECgYJEgAAAA==.',
Li='Lilani:BAAALgADCgYJCgAAAA==.Lillyth:BAAALgAECgEJAQABLgAECgMJCAAIAAAAAA==.Lindir:BAACLgAFFH8RAAIMAAcJoBpjEQA7AQAMAAcJoBpjEQA7AQAuAAQKfy0AAgwACQk9JKkBAD8DAAwACQk9JKkBAD8DAAAA.Lionelle:BAAALgAECgYJDgAAAA==.Liq:BAABLgAFFH8FAAIHAAQJGRaGOAC1AAAHAAQJGRaGOAC1AAABLgAFFAgJJQAUAF4YAA==.Liquid:BAAALgAECgMJAwABLgAFFAgJJQAUAF4YAA==.Liquor:BAACLgAFFH8lAAIUAAgJXhjGIgCmAQAUAAgJXhjGIgCmAQAuAAQKf1AAAxQACQmJIVwLAO0CABQACQmJIVwLAO0CABoAAwnPFOQgAJYAAAAA.Liquorish:BAAALgAECgEJAQABLgAFFAgJJQAUAF4YAA==.Lirathiel:BAABLgAECn8WAAMbAAgJ6AQqPQBoAAAHAAUJOQQwNwF2AAAbAAUJsgQqPQBoAAAAAA==.Litasfk:BAAALgAECgIJAgAAAA==.Liuni:BAACLgAFFH8IAAIcAAQJXQfnFgCRAAAcAAQJXQfnFgCRAAAuAAQKfykAAhwACQmKFnEfAKsBABwACQmKFnEfAKsBAAAA.Liyin:BAAALgAECgQJCQABLgAECgkJKwAEAIEOAA==.',
Lo='Lobopeste:BAABLgAECn9dAAISAAkJ9xEQBQB/AQASAAkJ9xEQBQB/AQAAAA==.Loborocco:BAAALgAECgYJBwAAAA==.Lobotrigger:BAAALgAECgUJBQABLgAECgkJXQASAPcRAA==.Locknutz:BAAALgADCgMJAwAAAA==.Loracy:BAAALgADCgcJBwAAAA==.Lorantell:BAAALgAECgQJBAAAAA==.Lorelynn:BAABLgAECn8qAAICAAkJUQ2wVwCWAQACAAkJUQ2wVwCWAQAAAA==.',
Lu='Luci:BAABLgAECn8YAAQUAAgJ6RJ4UACUAQAUAAgJkxJ4UACUAQAaAAMJ1Q7ZLwBDAAAYAAEJAADNiAAAAAABLgAFFAQJEAADAEUWAA==.Lucìan:BAACLgAFFH8FAAIXAAIJtRM0UQB+AAAXAAIJtRM0UQB+AAAuAAQKfygAAxcACQm6HwgNAPUCABcACQm6HwgNAPUCABkAAQmmBC8tABkAAAAA.Ludociel:BAAALgAECgUJCgAAAA==.Luna:BAAALgAECgUJBwABLgAFFAQJCwATADwaAA==.Lunaclair:BAACLgAFFH8cAAIQAAQJew+KfgAKAQAQAAQJew+KfgAKAQAuAAQKf2wAAxAACQk8IGMmAGoCABAACQk8IGMmAGoCABIABwmNEEEqAAYBAAAA.Lunadrus:BAABLgAECn8mAAIEAAgJogmitgAXAQAEAAgJogmitgAXAQAAAA==.Lunarielle:BAACLgAFFH8gAAIOAAQJCBluMABPAQAOAAQJCBluMABPAQAuAAQKfyEAAg4ACAkXHMYVAIkCAA4ACAkXHMYVAIkCAAAA.',
Ly='Lyriaa:BAAALgADCgYJCwAAAA==.',
Ma='Mabrito:BAABLgAFFH8WAAIUAAkJBxLPDQDeAQAUAAkJBxLPDQDeAQAAAA==.Macalatraz:BAAALgAECgUJCQAAAA==.Macfly:BAABLgAECn8/AAIOAAkJFBtPKgA0AgAOAAkJFBtPKgA0AgAAAA==.Madmeatballs:BAAALgAECgEJAQABLgAECgkJKwAEAFEfAA==.Magdala:BAAALgAECgYJBgAAAA==.Magicmissile:BAACLgAFFH8QAAIEAAYJSg/gXQAkAQAEAAYJSg/gXQAkAQAuAAQKfyoAAgQACQlqH+YXAMoCAAQACQlqH+YXAMoCAAAA.Makgora:BAAALgAECgMJBAABLgAECgYJFgAVAFkhAA==.Makhvan:BAABLgAFFH8JAAIQAAMJ6hldQwDWAAAQAAMJ6hldQwDWAAAAAA==.Maksoon:BAABLgAFFH8FAAIRAAIJvhUjQwCVAAARAAIJvhUjQwCVAAAAAA==.Maladjusted:BAAALgAECgMJBAAAAA==.Malevalous:BAAALgAFFAEJAQABLgAFFAQJEwAHAGwPAA==.Maléfique:BAAALgAECgIJAgAAAA==.Mancath:BAAALgAECgkJCwAAAA==.Maplè:BAAALgAECgIJAwABLgAECggJIwAJAKITAA==.Mar:BAAALgADCgMJAwAAAA==.Marlei:BAAALgADCgQJBAABLgAECgkJKwAEAIEOAA==.Marqose:BAAALgADCgcJDgABLgAECgcJDgAIAAAAAA==.Matan:BAAALgADCgUJBQAAAA==.',
Me='Medena:BAAALgAECgEJAQAAAA==.Medorin:BAAALgADCgEJAQAAAA==.Meeko:BAABLgAFFH8GAAIhAAMJohoNDwCsAAAhAAMJohoNDwCsAAABLgAFFAkJSwAhAHQlAA==.Melfie:BAABLgAECn81AAIEAAkJqx1SIQCYAgAEAAkJqx1SIQCYAgAAAA==.Meliadoul:BAABLgAECn8fAAIEAAkJwAu/cQCWAQAEAAkJwAu/cQCWAQAAAA==.Mellyndra:BAABLgAECn88AAIKAAkJ3x4SCgDqAgAKAAkJ3x4SCgDqAgAAAA==.Mercüry:BAAALgAECgEJBQAAAA==.Mezhren:BAAALgAECgYJCwAAAA==.',
Mh='Mhoramsgirl:BAAALgADCggJCwAAAA==.',
Mi='Midoriya:BAACLgAFFH8IAAMGAAMJHQewKwCfAAAGAAMJHQewKwCfAAAFAAMJyQtmRgCLAAAuAAQKfyMAAwYACQlnEYYvAEsBAAYACAkvEoYvAEsBAAUABQmQEfqEAJQAAAAA.Mihoshi:BAABLgAECn8ZAAITAAgJvBNqBADRAQATAAgJvBNqBADRAQAAAA==.Mistjack:BAABLgAFFH8LAAIFAAUJthFsKQAkAQAFAAUJthFsKQAkAQAAAA==.',
Mo='Momdad:BAACLgAFFH8SAAIMAAUJ6xdUEwAwAQAMAAUJ6xdUEwAwAQAuAAQKfzQAAgwACQnWIK0HAKMCAAwACQnWIK0HAKMCAAAA.Mongaux:BAAALgADCgQJBQAAAA==.Monkey:BAAALgAECgQJCgAAAA==.Morrígán:BAAALgADCgUJBQAAAA==.Moxi:BAAALgAECgMJAwAAAA==.',
Mu='Muamman:BAAALgAECgMJAwAAAA==.Murda:BAAALgADCgYJCgAAAA==.Murphysflaw:BAAALgAECgIJAgAAAA==.Mutegen:BAAALgAFFAEJAQAAAA==.',
Mx='Mxhealeryduf:BAAALgAECgIJAgAAAA==.',
My='Mystallian:BAAALgAECgUJCwAAAA==.Mystí:BAEALgAFFAIJAgABLgAECgkJNQABAN4dAA==.Mythicplus:BAAALgAECgcJEQAAAA==.Mythosaur:BAAALgADCgEJAQAAAA==.',
['Mä']='Märtyr:BAABLgAECn8WAAIHAAgJOhJpDgCCAQAHAAgJOhJpDgCCAQAAAA==.',
['Må']='Måzikeen:BAAALgAECgEJAQAAAA==.',
['Mé']='Mélisande:BAAALgADCgQJBgAAAA==.Mémnoc:BAAALgAECgMJAwAAAA==.',
Na='Nadarien:BAAALgAECgYJDQAAAA==.Nadyia:BAAALgADCgEJAQAAAA==.Nailah:BAAALgADCgcJCwAAAA==.Nannergoat:BAAALgADCgMJAwAAAA==.Nastymikey:BAABLgAECn8bAAIgAAgJNx13BwBzAgAgAAgJNx13BwBzAgAAAA==.Nazdormu:BAABLgAECn8hAAIhAAkJzgOEHwD5AAAhAAkJzgOEHwD5AAAAAA==.',
Ne='Nediablo:BAAALgADCgEJAQAAAA==.Nefarious:BAAALgAECgcJDgAAAA==.Nefarius:BAAALgAECgEJAQABLgAFFAEJAQAIAAAAAA==.Neisen:BAABLgAECn86AAMKAAkJ9hgaEQCMAgAKAAkJ9hgaEQCMAgAHAAUJBwKc+gCeAAAAAA==.Neocold:BAAALgAECgEJAQAAAA==.Neptune:BAAALgADCgYJBgAAAA==.',
Ni='Nizzlix:BAAALgAECgMJAwAAAA==.',
No='Norna:BAAALgADCgcJDwAAAA==.Noz:BAAALgADCgkJCQAAAA==.',
Nu='Nufonewhodis:BAABLgAECn8WAAIVAAYJWSF1HQATAgAVAAYJWSF1HQATAgAAAA==.',
Ny='Nykolas:BAAALgAECgEJAQAAAA==.Nymlindra:BAAALgAECgUJBgABLgAECgkJLwALAEgPAA==.Nymofthedead:BAABLgAECn82AAMQAAkJmiRhBgBFAwAQAAkJmiRhBgBFAwADAAUJyRMNGwD3AAAAAA==.',
Oa='Oakgrove:BAAALgAECgEJAQAAAA==.',
Ol='Olgathory:BAAALgAECgMJAwAAAA==.',
Om='Ombraless:BAAALgAECgMJAwABLgAECgQJCAAIAAAAAA==.',
On='Oneforall:BAAALgAECgkJDgAAAA==.',
Op='Ophrizhani:BAAALgAECgMJAwAAAA==.',
Or='Orangegrove:BAAALgAECgYJBQAAAA==.Orpheal:BAAALgAECgUJBQAAAA==.Orphen:BAAALgAECggJEAAAAA==.',
Os='Osìrìs:BAAALgAECgQJCwABLgAFFAIJBQAXALUTAA==.',
Ou='Outtkast:BAAALgAECgYJBgAAAA==.',
Pa='Paddleball:BAAALgADCgQJBAAAAA==.Paladouin:BAAALgAECgYJEwAAAA==.Pandammy:BAAALgAECgkJBQAAAA==.Pantro:BAABLgAECn8hAAMeAAkJyRcACQA4AgAeAAkJyRcACQA4AgAdAAEJAAC9lAAAAAAAAA==.Papalion:BAABLgAECn8kAAIOAAkJlg5oIwDPAAAOAAkJlg5oIwDPAAAAAA==.Papaya:BAAALgADCgYJBgAAAA==.Paragas:BAAALgADCgkJEAAAAA==.Pawbs:BAAALgAECgQJEwAAAA==.',
Pe='Peanuts:BAAALgADCgcJBwAAAA==.Peoplehugger:BAAALgADCgMJAwAAAA==.',
Pi='Pickleburger:BAAALgAECgEJAQAAAA==.Pikake:BAAALgAECgEJAQAAAA==.Pinkkrayen:BAAALgAECgQJBwAAAA==.Pinklilydrd:BAABLgAECn8dAAMXAAYJuxQHCABRAQAXAAYJuxQHCABRAQAZAAQJ7QjraQB5AAAAAA==.',
Pl='Plaindonut:BAABLgAECn8vAAMXAAkJ8iG+AAByAwAXAAkJ8iG+AAByAwAZAAEJowjLjgAxAAAAAA==.',
Po='Polyphia:BAAALgADCgQJBAAAAA==.Porple:BAABLgAECn8YAAIMAAgJcQtJKgBPAQAMAAgJcQtJKgBPAQAAAA==.',
Pr='Priestdrago:BAAALgADCgUJBQAAAA==.Prissidebow:BAAALgAECgUJDAAAAA==.',
Pu='Puddinpie:BAAALgADCgEJAQAAAA==.',
Qu='Quartz:BAAALgAFFAEJAQABLgAFFAMJEQARAIAkAA==.',
Ra='Raegan:BAAALgAECgEJAwAAAA==.Rahzule:BAAALgADCgYJBwAAAA==.Ralynne:BAACLgAFFH8HAAILAAMJwA0bOACuAAALAAMJwA0bOACuAAAuAAQKfzAAAgsACQkoFSwgAOEBAAsACQkoFSwgAOEBAAAA.Rantis:BAABLgAECn8iAAMeAAgJbwyKBQAPAQAeAAgJWQyKBQAPAQAdAAcJkwnUCwDEAAAAAA==.Raskus:BAAALgADCgYJBgAAAA==.Ravenbrook:BAACLgAFFH8mAAIRAAcJbCG5AwBGAgARAAcJbCG5AwBGAgAuAAQKfyQAAxEACQlVJXsEAGIDABEACQlVJXsEAGIDABYAAQkwIJVnAFIAAAAA.Rawrr:BAABLgAECn8kAAIYAAkJWQr6KQAuAQAYAAkJWQr6KQAuAQAAAA==.Rawrxd:BAAALgAECgEJAgABLgAECggJDgAIAAAAAA==.Raxie:BAACLgAFFH8lAAMfAAcJQxc3HAB+AQAfAAcJQxc3HAB+AQAkAAEJBQ3SFABRAAAuAAQKfy0ABB8ACQnXGqUOAIQCAB8ACQnXGqUOAIQCACQABwnIE90tAGoBABMAAQkBBPGHACgAAAAA.Razeth:BAABLgAECn8VAAIMAAYJ8BZgLgA0AQAMAAYJ8BZgLgA0AQAAAA==.',
Re='Reanne:BAAALgAECgYJEAAAAA==.Rebecka:BAAALgAECgYJBgAAAA==.Res:BAAALgAECgYJCwAAAA==.Rescorla:BAAALgAECgkJDAAAAA==.Rethali:BAAALgADCgQJAgAAAA==.Reysola:BAAALgAECgMJBAABLgAECgMJBgAIAAAAAA==.Rezr:BAAALgAECggJDgAAAA==.',
Rh='Rhixa:BAAALgADCgUJBQAAAA==.Rhymunky:BAAALgAFFAMJBAAAAA==.',
Ri='Rifthor:BAABLgAECn8iAAQeAAgJdRqzAQAOAgAeAAgJdRqzAQAOAgAdAAMJKQ8kSQCFAAAXAAIJsAJJ3AAmAAAAAA==.Riftrion:BAAALgAECgQJBAAAAA==.Rillx:BAAALgADCgQJBgAAAA==.Ripmxi:BAACLgAFFH8HAAIEAAQJlAatSACpAAAEAAQJlAatSACpAAAuAAQKfz4AAgQACQk8FhAMAKEBAAQACQk8FhAMAKEBAAAA.',
Ro='Robinski:BAAALgADCgEJAQAAAA==.Robotiss:BAAALgADCgIJAgAAAA==.Rocco:BAAALgADCgYJBwAAAA==.Rodevon:BAAALgADCggJCAAAAA==.Roknasaurus:BAAALgADCgUJCAAAAA==.Romani:BAAALgADCgYJBgAAAA==.Romeo:BAAALgAECgQJBAAAAA==.Ronaldreagnt:BAAALgAECgcJEQAAAA==.',
Ru='Runecat:BAABLgAFFH8QAAMZAAcJNAicMADAAAAZAAQJbQScMADAAAAXAAYJCgdqGgCfAAAAAA==.Runelight:BAACLgAFFH8IAAMfAAMJOQFaPQCEAAAfAAMJOQFaPQCEAAAkAAIJsgHyNgBbAAAuAAQKfxwABB8ACAlQFM4hAMABAB8ABwmbFM4hAMABABMABgn3CpM/APEAACQAAwkQBT9sAG4AAAEuAAUUBwkQABkANAgA.Runeshock:BAAALgAFFAMJAwABLgAFFAcJEAAZADQIAA==.Runestick:BAAALgAECgMJBAABLgAFFAcJEAAZADQIAA==.Rupertgiless:BAACLgAFFH8TAAICAAcJIQ1zJwCqAQACAAcJIQ1zJwCqAQAuAAQKfyYAAgIACQl0G30iAIsCAAIACQl0G30iAIsCAAAA.',
Sa='Sabeckya:BAAALgAECgQJCgAAAA==.Sacksmasher:BAAALgADCgcJDwAAAA==.Sainttristan:BAAALgAECgEJAQAAAA==.Sampleshrimp:BAAALgADCgEJAgAAAA==.Saphyla:BAAALgAECgQJBQAAAA==.Sappheire:BAAALgAECgYJBgAAAA==.Sarcastyx:BAAALgAECggJCgAAAA==.Sarrod:BAAALgADCgUJBQAAAA==.Sarrow:BAAALgADCgkJCQAAAA==.Savvy:BAAALgAECgEJAgABLgAFFAMJCAAQAD8HAA==.Saxines:BAABLgAECn8dAAITAAYJ4w/ONQAqAQATAAYJ4w/ONQAqAQAAAA==.',
Sc='Scaliefox:BAAALgAECgIJAgABLgAECgkJPAAKAN8eAA==.Scarl:BAAALgADCgUJBQAAAA==.Schwarznacht:BAAALgADCgUJBQAAAA==.Schwarzwölf:BAAALgADCgYJCwAAAA==.Sconzil:BAABLgAECn8kAAIEAAgJSApmGQAPAQAEAAgJSApmGQAPAQAAAA==.Scoots:BAAALgADCgQJBAAAAA==.Scrubs:BAAALgAECgcJEAAAAA==.Scrubsevoker:BAAALgAECgYJDgAAAA==.Scumbum:BAAALgADCgIJAgAAAA==.Scyllo:BAAALgAECgQJBgAAAA==.',
Se='Seekndestroy:BAABLgAECn8cAAILAAkJtgneEwCnAAALAAkJtgneEwCnAAAAAA==.Selige:BAAALgAECgQJBAAAAA==.',
Sg='Sgtcuunt:BAAALgAECgUJBQAAAA==.',
Sh='Shackled:BAAALgAECgYJEgAAAA==.Shaenicor:BAAALgADCgIJAgAAAA==.Shankkerz:BAAALgAECgcJDAAAAA==.Shelbo:BAAALgAECgEJAQAAAA==.Shmolda:BAAALgADCgYJBwAAAA==.Shortshammy:BAAALgAECgEJAQABLgAFFAMJCwAEACUJAA==.Shror:BAAALgADCgEJAQABLgAECgUJBQAIAAAAAA==.',
Si='Sicarune:BAAALgAECgUJBgABLgAFFAcJEAAZADQIAA==.Siiegrand:BAABLgAECn8VAAIbAAcJhRCSJQDoAAAbAAcJhRCSJQDoAAAAAA==.Silentswag:BAABLgAECn8VAAIVAAcJLxTZIACPAQAVAAcJLxTZIACPAQAAAA==.Simonx:BAAALgAECgEJAQAAAA==.Sindrane:BAAALgAECgMJAwABLgAFFAMJBwASAIAQAA==.Sitzho:BAAALgADCgUJDQAAAA==.',
Sk='Skeleton:BAAALgAECgIJAgAAAA==.Skybringer:BAABLgAECn9kAAIHAAkJnRXrDACYAQAHAAkJnRXrDACYAQAAAA==.Skyee:BAABLgAECn8qAAMGAAkJvx0LDAC6AgAGAAkJvx0LDAC6AgAFAAMJGxRxfACpAAAAAA==.Skylos:BAAALgAECgEJAgAAAA==.',
Sl='Slowburn:BAAALgAECgIJAgABLgAFFAQJEAADAEUWAA==.',
Sm='Smexibiotch:BAAALgADCgYJBgABLgAECggJCgAIAAAAAA==.Smolbeans:BAAALgADCgUJBQAAAA==.',
So='Soapscum:BAAALgADCgQJBAAAAA==.Soarphium:BAAALgAECgIJAgABLgAFFAgJHgAVAEANAA==.Solararc:BAAALgADCgEJAgAAAA==.Soleana:BAAALgAECgYJBQAAAA==.Sombra:BAAALgAECgMJBwABLgAECgcJDgAIAAAAAA==.Sonicast:BAAALgAECgYJCQAAAA==.Sooie:BAAALgAECgYJEgAAAA==.Soramian:BAAALgADCgcJEgAAAA==.Sosneaky:BAAALgADCgIJAgAAAA==.Soulcacher:BAACLgAFFH8HAAMSAAMJgBChLgCLAAAQAAMJ6w1HpwDNAAASAAMJlwmhLgCLAAAuAAQKfzIAAxAACQmqFKFLABACABAACAknFqFLABACABIACAm9D0oeAGQBAAAA.Soxxy:BAAALgAECgEJAQABLgAFFAQJEAADAEUWAA==.',
Sp='Sparhawk:BAAALgAECgYJBgAAAA==.Spellgunner:BAABLgAECn8VAAIEAAgJPxsFYQC+AQAEAAgJPxsFYQC+AQAAAA==.Spinsaround:BAAALgADCgEJAQAAAA==.',
St='Starshines:BAAALgADCgkJCQAAAA==.Stormwulf:BAAALgADCgUJBQABLgAECgYJGAAFAGYYAA==.Stormyprissi:BAAALgAECgQJDAAAAA==.Strombjorn:BAABLgAECn8jAAMJAAgJohPASQCIAQAJAAgJohPASQCIAQALAAUJwQwLYwC8AAAAAA==.',
Sw='Switch:BAAALgAECgEJAQAAAA==.',
['Sø']='Sølaria:BAAALgAECgEJAQAAAA==.',
Ta='Tasireth:BAAALgADCgcJBwAAAA==.',
Te='Tessi:BAACLgAFFH8HAAIEAAMJrgIFoACNAAAEAAMJrgIFoACNAAAuAAQKfxcAAgQABwm3D2aUAFABAAQABwm3D2aUAFABAAAA.',
Th='Thaloran:BAABLgAECn8ZAAIbAAgJpxyvAQA9AgAbAAgJpxyvAQA9AgAAAA==.Thalrian:BAAALgAFFAEJAQABLgAFFAQJGAARACIkAA==.Thefailnym:BAABLgAECn8jAAMMAAgJmRpaAgDaAQAMAAgJKxpaAgDaAQAOAAUJUxmqsADjAAAAAA==.Theory:BAABLgAECn8UAAMPAAcJ9hCkCQDWAAAPAAcJUxCkCQDWAAAnAAIJqBICCQA7AAABLgAFFAMJDAAQANQcAA==.Theylive:BAABLgAECn8dAAIXAAkJJw9iNQDFAQAXAAkJJw9iNQDFAQAAAA==.Thondrin:BAAALgAECgcJDQAAAA==.Thordanil:BAAALgAECgcJEAAAAA==.Thrashedass:BAAALgADCgEJAQAAAA==.',
Ti='Tigerlilliy:BAAALgADCgYJEAAAAA==.Timerek:BAAALgADCgIJAgAAAA==.Tipride:BAAALgAECgkJBwAAAA==.',
To='Toawulf:BAAALgAECgQJCAABLgAECgYJGAAFAGYYAA==.Toetickla:BAAALgAECgEJAgAAAA==.Tokifuji:BAAALgAECgIJBAABLgAECgQJEwAIAAAAAA==.Toranaar:BAAALgAECgcJBwABLgAFFAMJBAAIAAAAAA==.Toya:BAABLgAECn80AAIVAAkJZRwHCwBzAgAVAAkJZRwHCwBzAgAAAA==.',
Tr='Trenazen:BAAALgADCgkJCgAAAA==.Trevain:BAAALgAECgEJAgAAAA==.Trimasdrood:BAAALgADCgMJAwAAAA==.Trivia:BAABLgAECn8rAAINAAgJSw+bAgBRAQANAAgJSw+bAgBRAQAAAA==.Trundle:BAAALgAECgEJAwAAAA==.Truthordare:BAABLgAECn8tAAIBAAcJ5AuVFwDmAAABAAcJ5AuVFwDmAAAAAA==.Trysla:BAAALgAECgEJAQAAAA==.',
Tu='Turtei:BAAALgAECgEJAQABLgAFFAkJLAAGAFQmAA==.Turtl:BAACLgAFFH8sAAIGAAkJVCZaAAAYAwAGAAkJVCZaAAAYAwAuAAQKfysAAgYACQnmJjcAAPgDAAYACQnmJjcAAPgDAAAA.',
Tw='Twoevil:BAAALgADCgkJCQAAAA==.Twohoof:BAAALgADCgEJAQAAAA==.Twosar:BAAALgAECgIJBAAAAA==.',
Tx='Txìewtkuä:BAAALgADCgkJCQAAAA==.',
Ty='Tydiablo:BAAALgAECgEJAQAAAA==.Tyryn:BAAALgAECgYJBgAAAA==.',
Ug='Uglydragon:BAAALgAECgcJDAAAAA==.Uglypally:BAAALgADCgkJCQAAAA==.Uglypetguy:BAAALgAECgIJAgAAAA==.Uglyrogue:BAAALgAECgQJAgAAAA==.Uglyshaman:BAAALgAECgEJAgAAAA==.',
Ul='Ulgrym:BAAALgAECgQJBgAAAA==.Ultimatia:BAAALgAECgEJAQAAAA==.',
Un='Unbalancéd:BAABLgAECn8pAAIFAAcJUSIYGgBHAgAFAAcJUSIYGgBHAgAAAA==.',
Va='Vaeadin:BAAALgAECgQJBQAAAA==.Vahra:BAAALgAECgUJDAAAAA==.Valanther:BAAALgAECgMJAwAAAA==.Valantis:BAAALgADCgEJAQAAAA==.Valgaskav:BAACLgAFFH8IAAIHAAUJoyC8EgBmAQAHAAUJoyC8EgBmAQAuAAQKfy4AAgcACQlmIwkKABcDAAcACQlmIwkKABcDAAAA.Valimond:BAAALgAECgEJAQABLgAECgYJGAAFAGYYAA==.Vanarrath:BAAALgADCgYJBwAAAA==.Vandryelle:BAAALgADCgIJAgAAAA==.Varge:BAAALgADCgMJAwAAAA==.Varrathos:BAAALgAECgMJBAAAAA==.Vayl:BAAALgAECgMJAwAAAA==.',
Ve='Vegasnight:BAAALgAECgYJEgAAAA==.Vehstmw:BAABLgAFFH8GAAMFAAMJPRVCKQCIAAAFAAMJPRVCKQCIAAAGAAEJsALuJQApAAAAAA==.Velisa:BAAALgADCgYJBgAAAA==.Vella:BAAALgAECgQJBwAAAA==.Vellaria:BAAALgADCgUJBwAAAA==.Ventrue:BAAALgADCgMJAwAAAA==.Verdesoul:BAAALgAECgcJEgABLgAECgkJHwAHAAMMAA==.Vesyra:BAAALgAECgQJBQAAAA==.',
Vi='Vikkrum:BAAALgAECgEJAQABLgAECgEJAgAIAAAAAA==.Viralyn:BAAALgAECgYJEAABLgAFFAQJCAAcAF0HAA==.Vixøn:BAAALgAECgMJBwAAAA==.',
Vo='Voidluck:BAABLgAECn8SAAIUAAgJvxBkdABIAQAUAAgJvxBkdABIAQAAAA==.Voker:BAAALgAECgMJCQABLgAECgQJEwAIAAAAAA==.Voladis:BAAALgAECgYJDQAAAA==.Voladro:BAAALgAECgYJBgAAAA==.Volanie:BAAALgAECgQJAwAAAA==.Volava:BAAALgAECgcJBQAAAA==.Volos:BAACLgAFFH8FAAIHAAIJ4w0tkQCQAAAHAAIJ4w0tkQCQAAAuAAQKfzAAAgcACQneF0FZAMABAAcACQneF0FZAMABAAAA.Vordaman:BAACLgAFFH8SAAMDAAQJeQeeCwDgAAADAAQJIAeeCwDgAAAQAAMJgQeUVwCsAAAuAAQKfzQAAhAACQlhEyVOANgBABAACQlhEyVOANgBAAAA.',
Vy='Vynír:BAACLgAFFH8dAAICAAgJZxuxGAD9AQACAAgJZxuxGAD9AQAuAAQKfy4AAwIACQmgI7AJAAUDAAIACQk+I7AJAAUDAAEABQkHI40NAOwBAAAA.',
Wa='Waandur:BAAALgAECgYJCgAAAA==.Waghoba:BAACLgAFFH8xAAIeAAgJwR+4AABcAgAeAAgJwR+4AABcAgAuAAQKf1EAAh4ACQmdJhMAAJADAB4ACQmdJhMAAJADAAAA.Waito:BAAALgAECgQJBwAAAA==.Wandä:BAABLgAECn9FAAQcAAkJOCAQCgCSAgAcAAkJcRwQCgCSAgAGAAkJQBoiBACUAQAFAAgJEhL6QwBcAQABLgAFFAMJBgADAMwKAA==.Wardriccan:BAAALgAECggJDgAAAA==.Warfle:BAAALgADCgYJBgAAAA==.Warhound:BAAALgADCgcJBwAAAA==.Warrionomous:BAACLgAFFH8VAAIRAAUJchwADQBFAQARAAUJchwADQBFAQAuAAQKfxsAAhEACAkeG3gbABICABEACAkeG3gbABICAAEuAAUUBgkQAAQASg8A.Washu:BAACLgAFFH8PAAIYAAQJpBDeEgANAQAYAAQJpBDeEgANAQAuAAQKf0IAAxgACQnaHzsGANQCABgACQnaHzsGANQCABoAAwlMC1khAHkAAAAA.',
Wh='Whimlock:BAAALgADCgQJBAABLgAFFAMJBwAEAOUcAA==.Whimzie:BAAALgAECgEJAgABLgAFFAMJBwAEAOUcAA==.Whorphium:BAAALgAECggJEgABLgAFFAgJHgAVAEANAA==.',
Wi='Willow:BAAALgAECgYJCwAAAA==.Winterous:BAAALgAECgkJDgAAAA==.',
Wo='Wonderbread:BAACLgAFFH8VAAIHAAQJDQxnJwDsAAAHAAQJDQxnJwDsAAAuAAQKfzwAAgcACQn3FcQ4AB8CAAcACQn3FcQ4AB8CAAAA.',
Wr='Wrager:BAAALgAECgUJBgAAAA==.Wrathofzaun:BAAALgAECgYJDwAAAA==.',
Wy='Wylest:BAAALgADCgcJBwAAAA==.Wynch:BAAALgAECgkJCQAAAA==.',
['Wâ']='Wârwôlf:BAABLgAECn8pAAMOAAkJHCScBwAhAwAOAAkJHCScBwAhAwANAAQJ+BWyVQDzAAAAAA==.',
Xe='Xenan:BAABLgAECn85AAIHAAkJoRYFOgAbAgAHAAkJoRYFOgAbAgAAAA==.',
Xt='Xtrolldinary:BAABLgAECn8bAAIXAAYJ5QzDDQDOAAAXAAYJ5QzDDQDOAAAAAA==.',
Xv='Xvp:BAAALgAECgQJCgAAAA==.',
Xy='Xylophy:BAABLgAECn8rAAIaAAkJPBTzCQDJAQAaAAkJPBTzCQDJAQAAAA==.',
Ye='Yeastmode:BAACLgAFFH8iAAIOAAcJQxHJFAB9AQAOAAcJQxHJFAB9AQAuAAQKfy8AAg4ACQmkG6QmAEYCAA4ACQmkG6QmAEYCAAAA.Yeasty:BAAALgAFFAEJAwAAAA==.',
Yo='Yonah:BAAALgAECgYJDAAAAA==.',
Yu='Yurc:BAABLgAECn8nAAIiAAkJeBn+CQBUAgAiAAkJeBn+CQBUAgAAAA==.',
Za='Zademan:BAAALgAECgUJBwAAAA==.Zappyu:BAAALgAECgkJBQABLgAECgkJCQAIAAAAAA==.Zarkas:BAAALgAECgcJEgAAAA==.Zarquaza:BAAALgAECgYJBgAAAA==.',
Ze='Zeebra:BAABLgAECn8bAAIOAAgJcRJqEgBWAQAOAAgJcRJqEgBWAQAAAA==.Zeg:BAABLgAFFH8GAAIJAAMJ0BgbQgDeAAAJAAMJ0BgbQgDeAAAAAA==.Zega:BAAALgAFFAEJAQAAAA==.Zegafur:BAABLgAECn8zAAIXAAkJXhzBFgCRAgAXAAkJXhzBFgCRAgAAAA==.Zeruk:BAABLgAECn8XAAMGAAcJjwJ1YACOAAAGAAYJlAJ1YACOAAAFAAcJpQHflABuAAAAAA==.',
Zi='Zillionbúcks:BAACLgAFFH8fAAIHAAkJmBPBDQAHAgAHAAkJmBPBDQAHAgAuAAQKfxsAAgcACQmvHtEtAGwCAAcACQmvHtEtAGwCAAAA.',
Zu='Zullee:BAAALgAECgEJAQAAAA==.',
Zy='Zylcat:BAAALgAECgYJDAAAAA==.',
['Zê']='Zêddicus:BAACLgAFFH8HAAIBAAQJzQg+DgDCAAABAAQJzQg+DgDCAAAuAAQKfzkAAwEACQm4ILIBAMECAAEACQm4ILIBAMECAAIABQkfCAzUALIAAAAA.',
['Ác']='Áchilles:BAAALgADCgEJAQAAAA==.',
['Áq']='Áquafina:BAABLgAECn88AAIEAAkJpg7kXADIAQAEAAkJpg7kXADIAQAAAA==.',
['Åñ']='Åñgêl:BAAALgAECggJCgAAAA==.',
['Îv']='Îvan:BAAALgADCggJCAAAAA==.',
['Ðö']='Ðö:BAABLgAECn9KAAIRAAkJHSBeAQDUAgARAAkJHSBeAQDUAgAAAA==.',
['ßr']='ßruenor:BAAALgAECgYJDAAAAA==.',
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
