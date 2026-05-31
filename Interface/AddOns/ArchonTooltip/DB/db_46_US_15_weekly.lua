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

local lookup = {'Warlock-Destruction','Warlock-Demonology','Mage-Frost','Monk-Mistweaver','Monk-Windwalker','Paladin-Retribution','DemonHunter-Vengeance','Shaman-Restoration','Paladin-Holy','Unknown-Unknown','Shaman-Elemental','Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival','Evoker-Augmentation','DeathKnight-Unholy','DeathKnight-Frost','Warrior-Fury','Evoker-Devastation','Priest-Holy','DemonHunter-Devourer','Rogue-Subtlety','Warrior-Arms','Druid-Restoration','DeathKnight-Blood','Monk-Brewmaster','Paladin-Protection','Priest-Discipline','Shaman-Enhancement','Evoker-Preservation','Warrior-Protection','Rogue-Outlaw','Druid-Feral','Druid-Guardian','Druid-Balance','Mage-Fire','Warlock-Affliction','DemonHunter-Havoc','Priest-Shadow',}
local provider = {region='US',realm='Anvilmar',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aaril:BAAALgAECgQJFwAAAQ==.',
Ab='Abrams:BAAALgADCgYJBgAAAA==.',
Ad='Adel:BAAALgAECgYJCAAAAA==.',
Ae='Aelitha:BAABLgAECn8ZAAMBAAYJCQZ2OQDOAAABAAYJxAR2OQDOAAACAAYJsQRSwgC6AAAAAA==.',
Ak='Akaishi:BAAALgADCgIJAgAAAA==.Akali:BAAALgAFFAEJAQAAAA==.Akina:BAAALgADCgYJBwABLgAECgkJKwADAIEOAA==.',
Al='Alanie:BAAALgAECgIJAgAAAA==.Alathiana:BAAALgADCgUJCAAAAA==.Alcweaver:BAABLgAECn8dAAMEAAcJgiDTGwATAgAEAAcJgiDTGwATAgAFAAYJgA/zOQABAQAAAA==.Alecto:BAAALgAECgMJAwAAAA==.Alindia:BAAALgAECgQJCgABLgAECgkJKwADAIEOAA==.Alirrayia:BAAALgAECgQJBAAAAA==.Alirrayiia:BAACLgAFFH8IAAIGAAMJ+AHgbQCmAAAGAAMJ+AHgbQCmAAAuAAQKfygAAgYACQlxEC1NAPsBAAYACQlxEC1NAPsBAAAA.Alkri:BAAALgADCgMJAwAAAA==.Allari:BAAALgAECgYJEwAAAA==.Allikazam:BAAALgADCgYJEwAAAA==.Allystar:BAAALgAECgQJDwAAAA==.Altheia:BAAALgAECgQJBAAAAA==.Alvidor:BAABLgAECn87AAIDAAkJeQUujABEAQADAAkJeQUujABEAQAAAA==.',
Am='Ameria:BAAALgADCgUJBQAAAA==.Amexican:BAAALgAECgEJAQAAAA==.Amybabe:BAAALgAECgEJAQAAAA==.',
An='Anastos:BAAALgAECgUJBQAAAA==.Andydufresne:BAAALgAECgQJDQABLgAECggJQwAHAAgmAA==.Angryqueer:BAAALgADCgEJAQAAAA==.',
Ao='Aowl:BAAALgAECgcJCwAAAA==.',
Ap='Apocketheory:BAAALgADCgIJAgAAAA==.Apolloerosb:BAAALgAECgYJBgABLgAECgcJHgAIACEbAA==.Apolloerosp:BAAALgAECgEJAQABLgAECgcJHgAIACEbAA==.Apollossham:BAABLgAECn8eAAIIAAcJIRuiJQASAgAIAAcJIRuiJQASAgAAAA==.',
Ar='Arkanaun:BAABLgAECn8dAAMGAAYJRBdpcwCUAQAGAAYJRBdpcwCUAQAJAAUJvRRwRwAIAQAAAA==.',
As='Ashes:BAAALgAECgcJAQAAAA==.Ashrán:BAAALgAECgYJCQAAAA==.Ashyluna:BAAALgAECgQJBAAAAA==.Astianna:BAAALgADCgMJAwAAAA==.',
Au='Aule:BAAALgAECgIJAwAAAA==.Aurinia:BAAALgADCgQJAgAAAA==.Auroradinlee:BAAALgAECgkJBgAAAA==.Aurore:BAAALgADCgQJBgAAAA==.',
Av='Avradea:BAAALgADCgEJAQABLgAECgkJKwADAIEOAA==.',
Az='Azareth:BAAALgADCggJCAAAAA==.',
Ba='Baconatorr:BAAALgAECgQJBQAAAA==.Bagelbags:BAAALgADCgEJAQAAAA==.Bahler:BAAALgADCgUJBQABLgAECgMJAwAKAAAAAA==.Baji:BAABLgAECn87AAMIAAkJLSJjBgA2AwAIAAkJLSJjBgA2AwALAAUJ/hWOQgANAQAAAA==.Baklan:BAAALgAECgMJAwAAAA==.Barefaall:BAACLgAFFH8RAAIMAAcJExbCBQDqAQAMAAcJExbCBQDqAQAuAAQKf0QAAwwACQllJK4AAEkDAAwACQllJK4AAEkDAA0ABAmFEM2VAPkAAAAA.Barefall:BAAALgAFFAMJBAABLgAFFAcJEQAMABMWAA==.Barefalls:BAACLgAFFH8FAAIOAAMJlhy+FwD6AAAOAAMJlhy+FwD6AAAuAAQKfyUAAw4ACQkfHu0JAHICAA4ACQkfHu0JAHICAAwAAQmMAaCWACIAAAEuAAUUBwkRAAwAExYA.Barelywolf:BAABLgAECn8kAAMFAAgJgh9jEAAwAgAFAAcJLCBjEAAwAgAEAAcJZBlPIgDiAQABLgAFFAMJBgAPACwLAA==.Bashira:BAABLgAECn8eAAINAAkJsAqaTACjAQANAAkJsAqaTACjAQAAAA==.Bast:BAABLgAECn8vAAMQAAkJRxYvLAA7AgAQAAkJRxYvLAA7AgARAAQJiQ2KIQCLAAAAAA==.Bastienne:BAAALgAECgQJCgAAAA==.Bastrillan:BAAALgAECgUJBwAAAA==.',
Be='Bearophe:BAAALgAECgEJAgAAAA==.Beerfist:BAAALgAECgEJAQAAAA==.Belfor:BAAALgAECgMJAwAAAA==.Bellock:BAAALgAECgMJAwAAAA==.Bendroyd:BAAALgAECgIJAgAAAA==.Benisbagina:BAAALgADCggJCQAAAA==.Bergonator:BAABLgAECn8gAAISAAYJcRC9TwBpAQASAAYJcRC9TwBpAQAAAA==.Berrodiah:BAAALgAECgYJCAABLgAECggJFgATALUYAA==.Bettyswalls:BAAALgAECgMJAwAAAA==.Beyarago:BAAALgAECgUJCQAAAA==.',
Bh='Bheiroth:BAABLgAECn8wAAIUAAkJSCSJAwBHAwAUAAkJSCSJAwBHAwAAAA==.',
Bi='Birds:BAAALgAECggJDwAAAA==.',
Bl='Bladeygaga:BAABLgAECn8yAAIVAAkJvR1PDwC2AgAVAAkJvR1PDwC2AgAAAA==.Blasé:BAAALgAECgcJCAAAAA==.Blazingblood:BAAALgADCgUJAQAAAA==.Bloodknight:BAAALgADCgYJCQAAAA==.Bluekrayen:BAAALgAECgUJCAAAAA==.Bluett:BAAALgAECgMJCQAAAA==.Bláckøut:BAAALgADCgYJDAAAAA==.',
Bo='Bodhi:BAABLgAECn8WAAIWAAcJNhAQJwDAAQAWAAcJNhAQJwDAAQAAAA==.Bogertus:BAACLgAFFH8OAAISAAMJfCRZGwAvAQASAAMJfCRZGwAvAQAuAAQKf0AAAxIACQnSJjsAAJQDABIACQnSJjsAAJQDABcAAgn1HHIpAKUAAAAA.Bonobo:BAAALgAECgYJBwAAAA==.Boomertunes:BAABLgAECn8kAAMCAAgJIhh0NgDzAQACAAgJIhh0NgDzAQABAAIJGwFQTAAAAAAAAA==.',
Br='Brein:BAABLgAECn87AAIYAAkJliXGAADXAwAYAAkJliXGAADXAwAAAA==.Brewmaster:BAAALgAECgIJAwAAAA==.Brewwmaster:BAABLgAECn8kAAQZAAkJrBhZFAC0AQAZAAkJIBVZFAC0AQAQAAYJtBfWfACKAQARAAEJ+he5FgA2AAAAAA==.Bricklethumb:BAAALgAECgMJAwABLgAECgMJDAAKAAAAAA==.Brickred:BAAALgADCggJDgAAAA==.Brynodd:BAAALgAECgMJCQAAAA==.',
Bu='Bubblybetty:BAAALgAECgEJAQAAAA==.Bucketeer:BAABLgAECn8rAAIDAAkJUR8qGACzAgADAAkJUR8qGACzAgAAAA==.Buffs:BAAALgADCgEJAQAAAA==.Bullminator:BAAALgAECgcJCAAAAA==.Bursona:BAAALgAECgEJAQAAAA==.Butterfree:BAAALgAECgUJDAABLgAFFAEJAQAKAAAAAA==.',
Ca='Cards:BAAALgAECgYJCgAAAA==.Carkrash:BAAALgADCgkJFwAAAA==.Casterkang:BAAALgAECgUJCQAAAA==.Catshunter:BAAALgAECgYJEAAAAA==.',
Ce='Celaa:BAABLgAECn8rAAIDAAkJgQ7FUwDJAQADAAkJgQ7FUwDJAQAAAA==.',
Ch='Chanka:BAAALgAECgYJEQAAAA==.Chantillary:BAAALgAECgMJCQAAAA==.Chargerkang:BAAALgADCgYJBgAAAA==.Chchanges:BAAALgAECgEJAQAAAA==.Cheesy:BAABLgAECn8nAAICAAgJugubZgBlAQACAAgJugubZgBlAQAAAA==.Chicken:BAAALgAECgYJEQAAAA==.Chonk:BAAALgADCgEJAQAAAA==.Chopzullee:BAABLgAECn8VAAIFAAYJgQnFVAChAAAFAAYJgQnFVAChAAAAAA==.',
Ci='Cirya:BAAALgAECgUJCQAAAA==.',
Cl='Cleric:BAAALgADCgUJBQAAAA==.Clortho:BAAALgAECgMJBgAAAA==.',
Co='Coljack:BAAALgAECggJCAAAAA==.Colljack:BAACLgAFFH8bAAIJAAYJAhqyDgCsAQAJAAYJAhqyDgCsAQAuAAQKfyEAAwkACQkgIZwJANgCAAkACQkgIZwJANgCAAYABQlOEtO5ABIBAAAA.Coughlin:BAAALgAECgEJAQAAAA==.',
Cr='Crocbait:BAAALgAECgcJEQAAAA==.Cryptoe:BAABLgAECn8eAAIDAAkJzRN1RwDuAQADAAkJzRN1RwDuAQAAAA==.',
Cu='Cudlsac:BAAALgAECgQJBQAAAA==.',
Da='Daedelus:BAABLgAECn8WAAMHAAcJORNbGgCvAAAVAAcJORNCjgDlAAAHAAUJfg1bGgCvAAAAAA==.Daglon:BAAALgAECggJDAAAAA==.Dagz:BAAALgAECgQJBAAAAA==.Dakina:BAAALgADCgYJBgAAAA==.Daraedra:BAAALgAECgUJBQAAAA==.Darkenvoid:BAAALgADCgkJDQAAAA==.',
De='Deathslight:BAAALgAECgQJBwAAAA==.Deeznutticus:BAACLgAFFH8bAAISAAYJKhZQCgCRAQASAAYJKhZQCgCRAQAuAAQKfyEAAxIABwnCIkgYAIkCABIABwnCIkgYAIkCABcAAgkBHetQAGoAAAAA.Defnotisis:BAABLgAECn8dAAMaAAgJhxSMJQBvAQAaAAcJCRaMJQBvAQAFAAgJtAtZPAD2AAABLgAFFAEJAQAKAAAAAA==.Defnotkity:BAAALgAECgEJAQAAAA==.Demonspud:BAABLgAECn8dAAIVAAcJhRJLXABaAQAVAAcJhRJLXABaAQAAAA==.Denxster:BAAALgAECgYJDgAAAA==.Dersan:BAABLgAECn8gAAIBAAgJ1ABjNwA2AAABAAgJ1ABjNwA2AAAAAA==.Destriant:BAABLgAECn81AAIbAAkJZhmECQAdAgAbAAkJZhmECQAdAgAAAA==.Devilschant:BAAALgAECgYJCgAAAA==.Devilshadow:BAAALgAECgUJBwABLgAECgYJCgAKAAAAAA==.Dewburt:BAAALgADCggJCgAAAA==.Deylia:BAAALgAECgIJAgABLgAFFAUJFwAcADgXAA==.',
Di='Dilithia:BAAALgAECgQJDwAAAA==.Dillion:BAAALgAECgYJCAAAAA==.Dinonuggies:BAAALgADCgcJBwAAAA==.Dionin:BAAALgADCgYJCQAAAA==.Dira:BAAALgAFFAIJAgABLgAFFAYJHQAdAK4gAA==.Dirkbanne:BAAALgADCgYJBgAAAA==.',
Do='Dodoubleg:BAAALgAECgYJEAAAAA==.Dominique:BAAALgADCgYJBgAAAA==.Donzilch:BAEALgAECgQJBAAAAA==.Donzilly:BAAALgAECgUJBQAAAA==.Dooburt:BAAALgAECgYJBgAAAA==.',
Dr='Dracaric:BAABLgAECn8oAAIPAAgJYxffHQDPAQAPAAgJYxffHQDPAQAAAA==.Draeca:BAAALgAECgMJBgAAAA==.Dragondznut:BAAALgAECgQJBQAAAA==.Drakhar:BAAALgADCgIJAgABLgAECgYJCwAKAAAAAA==.Drfrostie:BAAALgAECgcJEgAAAA==.Drgunner:BAAALgAECgcJDwAAAA==.Driatin:BAAALgAFFAEJAQAAAA==.Drkladykikyo:BAABLgAECn8XAAIUAAkJFQPCOwDvAAAUAAkJFQPCOwDvAAAAAA==.Druroo:BAAALgAECgEJAQABLgAFFAQJBwAQADUWAA==.Druterr:BAAALgAECgIJAgAAAA==.',
Du='Dumb:BAACLgAFFH8PAAIeAAUJLAyTBgCJAQAeAAUJLAyTBgCJAQAuAAQKfyMAAh4ACAnoG28LAH4CAB4ACAnoG28LAH4CAAAA.Durø:BAABLgAECn8WAAIVAAgJryLZDAAZAwAVAAgJryLZDAAZAwAAAA==.Duskhunter:BAAALgADCgEJAQAAAA==.',
Dy='Dyanisian:BAAALgADCgYJCAAAAA==.',
['Dè']='Dègenerate:BAABLgAECn87AAIfAAkJhCB0AwDsAgAfAAkJhCB0AwDsAgAAAA==.',
Ed='Edagerran:BAAALgADCgkJCQAAAA==.',
Ei='Eilae:BAABLgAECn8VAAINAAYJIgTQpwDTAAANAAYJIgTQpwDTAAAAAA==.Eirhakan:BAAALgAECgQJCAAAAA==.',
El='Elrethyl:BAABLgAECn8WAAIGAAcJXhj8aACDAQAGAAcJXhj8aACDAQAAAA==.Elvanus:BAAALgADCgYJBgAAAA==.Elêktra:BAABLgAECn8sAAILAAkJuA6vLAB4AQALAAkJuA6vLAB4AQAAAA==.',
Ep='Epicnym:BAAALgAECgEJAQAAAA==.Epicsmoke:BAACLgAFFH8IAAISAAMJHxI3KwDjAAASAAMJHxI3KwDjAAAuAAQKf0UAAhIACQnoI44CADwDABIACQnoI44CADwDAAAA.Epidemius:BAAALgAECgkJCgAAAA==.',
Er='Erevan:BAABLgAECn84AAMWAAkJ4hsOBwCkAgAWAAkJ4hsOBwCkAgAgAAEJpwABEAAcAAAAAA==.Eroica:BAAALgADCgYJBwAAAA==.Eronys:BAAALgAFFAIJAQAAAA==.',
Es='Esdeath:BAABLgAECn8pAAMQAAkJ5hLiSwDMAQAQAAkJ5hLiSwDMAQAZAAYJWga4NwCdAAAAAA==.',
Et='Etharia:BAAALgADCgUJAwAAAA==.',
Ev='Evilsmeghead:BAAALgADCgEJAQAAAA==.',
Ex='Exiledguy:BAAALgADCgYJBgAAAA==.Extenze:BAABLgAECn8oAAIVAAkJXx0IFwB4AgAVAAkJXx0IFwB4AgAAAA==.',
Ez='Ezykiah:BAAALgADCggJHwAAAA==.',
Fa='Falconponch:BAAALgADCgEJAQAAAA==.',
Fe='Felbjorn:BAAALgAECgEJAgAAAA==.Felgibson:BAAALgAECgQJBQAAAA==.Felkang:BAAALgADCgkJCQAAAA==.Ferryman:BAAALgAECgYJEQAAAA==.',
Fl='Flingor:BAAALgAECgYJEAAAAA==.Flokha:BAAALgADCgEJAQAAAA==.',
Fo='Forphium:BAACLgAFFH8YAAIWAAYJ7w+lBACkAQAWAAYJ7w+lBACkAQAuAAQKfx4AAhYACQn9IH0NAMQCABYACQn9IH0NAMQCAAAA.',
Fr='Fredolf:BAAALgAECgEJAQAAAA==.Freydís:BAAALgAECgUJCwAAAA==.Freyå:BAAALgAECgIJAgAAAA==.Friarkuck:BAAALgADCggJCAAAAA==.Friedbones:BAAALgAECgMJCQAAAA==.Frostlilliy:BAAALgADCggJCwAAAA==.',
['Fü']='Fürbie:BAAALgAECgIJAwAAAA==.',
Ga='Gahlina:BAAALgAECgYJEwAAAA==.Galdorian:BAAALgADCgYJCQABLgAECgkJHgANALAKAA==.Galynda:BAAALgADCgcJCAAAAA==.',
Ge='Genjimain:BAABLgAECn8lAAMYAAkJBhqRHgBKAgAYAAkJBhqRHgBKAgAhAAMJ9wyBLQCIAAAAAA==.Genjí:BAAALgAECgEJAwAAAA==.Geris:BAAALgAECgQJBQAAAA==.Gertruide:BAAALgADCgUJBQAAAA==.',
Gh='Ghendala:BAAALgADCggJEwAAAA==.',
Gi='Gillesmon:BAAALgAECggJCwABLgAECggJDAAKAAAAAA==.Gincainn:BAAALgAECgEJAgAAAA==.Gird:BAABLgAECn8oAAIJAAgJ4Q01NABsAQAJAAgJ4Q01NABsAQAAAA==.Girdlock:BAAALgAECgYJBwAAAA==.',
Gl='Glaiveyjones:BAAALgAECgEJAQAAAA==.',
Gn='Gnymesis:BAAALgAECgEJAgAAAA==.',
Go='Goatmonger:BAAALgAECgYJBgAAAA==.Goinpostal:BAAALgAECgIJAgAAAA==.Goldblade:BAAALgAECgkJEwAAAA==.Goodvsevil:BAAALgAECgQJBAAAAA==.Gordek:BAABLgAECn8bAAMGAAgJEBz6NgANAgAGAAgJEBz6NgANAgAJAAIJhBA1bwBfAAAAAA==.Gothitelle:BAAALgAECgIJBQAAAA==.Goöse:BAACLgAFFH8ZAAIQAAYJJh7dAwDEAQAQAAYJJh7dAwDEAQAuAAQKfycAAhAACAmDJusGAGsDABAACAmDJusGAGsDAAAA.',
Gr='Grantaron:BAABLgAECn81AAIGAAkJ2iAQFAC2AgAGAAkJ2iAQFAC2AgAAAA==.Gravarii:BAAALgADCgcJEwAAAA==.Grimskul:BAABLgAECn8zAAMQAAkJkB0wFgCvAgAQAAkJkB0wFgCvAgARAAYJDxSUBwCBAQAAAA==.Grindor:BAAALgADCgEJAQAAAA==.Grntitan:BAAALgAECgQJCgAAAA==.Gruid:BAAALgADCgcJDwAAAA==.',
Gu='Guinessbrew:BAAALgAECgEJAQAAAA==.',
Gw='Gwoohoori:BAAALgAECggJEwAAAA==.',
Gy='Gyra:BAAALgAECgYJEQAAAA==.Gyrojetli:BAAALgAECgEJAQAAAA==.',
Ha='Halukari:BAABLgAECn8UAAMiAAYJXiCICwDYAQAiAAYJXiCICwDYAQAjAAEJ8gzahgApAAABLgAFFAUJFwAcADgXAA==.Harfnan:BAAALgAECgIJAgAAAA==.Harrin:BAABLgAECn8dAAIDAAcJ9g8SlAA1AQADAAcJ9g8SlAA1AQAAAA==.',
He='Healingwater:BAAALgAECgIJAwAAAA==.Herracles:BAAALgADCgYJEwAAAA==.Hezrel:BAAALgAECgYJCgAAAA==.',
Hi='Hierodule:BAAALgAECgEJAQAAAA==.Hiimriven:BAAALgAECgIJAgABLgAECgYJFgAWAFkhAA==.Hinal:BAABLgAECn8fAAIGAAgJEh0yMAAnAgAGAAgJEh0yMAAnAgAAAA==.',
Ho='Hojo:BAAALgADCgUJCAAAAA==.Holyenabler:BAABLgAFFH8LAAIbAAMJ1gmBDACVAAAbAAMJ1gmBDACVAAAAAA==.Hootiehoo:BAAALgADCgMJAwAAAA==.',
Hu='Huflunggoo:BAAALgADCgkJDQAAAA==.Huflungpoop:BAABLgAECn80AAIFAAkJqBoMDwBCAgAFAAkJqBoMDwBCAgAAAA==.Hunterborn:BAAALgAFFAIJAgAAAA==.',
Hy='Hypercube:BAAALgAECgQJBwAAAA==.',
Ic='Ickixia:BAAALgADCgQJBAAAAA==.',
Il='Ilkaressa:BAAALgADCgQJBAAAAA==.Illyríá:BAEBLgAFFH8GAAICAAMJXw54agDWAAACAAMJXw54agDWAAABLgAECgkJLwABADobAA==.Ilun:BAAALgAECgEJAQAAAA==.',
Im='Imcruel:BAACLgAFFH8XAAMDAAcJChijEgAVAgADAAcJChijEgAVAgAkAAEJJwrCBABAAAAuAAQKfzAAAgMACQnNJcsFAEMDAAMACQnNJcsFAEMDAAAA.Ims:BAAALgAECggJAwAAAA==.',
In='Ink:BAACLgAFFH8NAAIDAAQJKxFeTwAyAQADAAQJKxFeTwAyAQAuAAQKfycAAgMABwm2ILFRAM8BAAMABwm2ILFRAM8BAAAA.',
Is='Istaria:BAAALgAECgMJCAAAAA==.Isujr:BAABLgAECn8ZAAIQAAcJ8hIKcQCmAQAQAAcJ8hIKcQCmAQAAAA==.',
Ja='Jacaerys:BAAALgADCgYJBgAAAA==.Jackiegan:BAABLgAECn8kAAQaAAkJOh51BwCtAgAaAAkJDB51BwCtAgAFAAEJahFyfwBCAAAEAAEJJgdrrgAeAAAAAA==.Jackson:BAAALgAECgMJCQAAAA==.Jagerdemon:BAAALgAECgcJBwAAAA==.',
Je='Jerce:BAAALgADCgUJBQAAAA==.Jeryatric:BAAALgADCgcJBwAAAA==.',
Jh='Jhala:BAAALgADCgcJDAAAAA==.',
Jo='Joshcalc:BAAALgAFFAEJAQAAAA==.Joskel:BAABLgAECn8vAAQCAAgJDw3YZgBlAQACAAgJiQzYZgBlAQAlAAYJMQToFgDIAAABAAIJNgyrKwBaAAAAAA==.',
Ju='Juacqer:BAAALgAECgMJCQAAAA==.',
Ka='Kaant:BAABLgAECn87AAMLAAkJwBuOEQBNAgALAAgJVx2OEQBNAgAIAAgJ+hQuNwC4AQAAAA==.Kaeni:BAAALgADCgMJAwAAAA==.Kaidevyn:BAABLgAECn8sAAMRAAgJjBLrDAB5AQARAAgJjBLrDAB5AQAQAAQJWgqA/ACRAAAAAA==.Kaiste:BAAALgADCgEJAQAAAA==.Kaleine:BAAALgAECgYJCAAAAA==.Kardren:BAAALgAECgUJDAAAAA==.Kat:BAAALgAECgMJAwAAAA==.',
Ke='Keiko:BAAALgAECggJDwAAAA==.Keiran:BAABLgAECn8zAAMNAAkJ4yJlBwARAwANAAkJ4yJlBwARAwAMAAgJpRzPEgCgAgAAAA==.Kelazurin:BAAALgADCgEJAQAAAA==.Kellistair:BAAALgADCgYJBgAAAA==.Keläo:BAAALgADCgUJCQAAAA==.Kenshii:BAAALgAECgUJBQAAAA==.Keyadish:BAAALgADCgYJDQAAAA==.Keys:BAACLgAFFH8HAAIWAAMJlhVpIgDoAAAWAAMJlhVpIgDoAAAuAAQKfyYAAhYACAkTHrkQAJwCABYACAkTHrkQAJwCAAAA.',
Kh='Khalnerys:BAABLgAECn8iAAMPAAgJcgl5PwAKAQAPAAgJJgh5PwAKAQATAAUJwQfZFACuAAAAAA==.Khitt:BAAALgAECgEJAQABLgAECgMJCAAKAAAAAA==.Khoulock:BAACLgAFFH8TAAICAAcJlhASIgCMAQACAAcJlhASIgCMAQAuAAQKfzUABAIACQnKIGQNANUCAAIACQm6IGQNANUCACUABQliIocQADgBAAEAAwl9ENU+ALkAAAAA.',
Ki='Kimmi:BAABLgAECn8ZAAMBAAkJKQUiFADxAAABAAkJKQUiFADxAAACAAIJ1gB+SwEUAAAAAA==.Kimmispally:BAAALgAECgIJAwAAAA==.Kiro:BAAALgADCgQJBQAAAA==.',
Kn='Knowimsayin:BAAALgAECgEJAQAAAA==.',
Ko='Kota:BAAALgAECgEJAQAAAA==.Kotateal:BAAALgAECgYJCwAAAA==.',
Kr='Kruelshot:BAACLgAFFH8NAAMNAAQJ8x/iEwCLAQANAAQJ8x/iEwCLAQAOAAEJiwvRKwBMAAAuAAQKfxYAAw0ACAnFJGkOAMoCAA0ACAnFJGkOAMoCAAwABwlqEgAyAKgBAAEuAAUUBwkXAAMAChgA.Krux:BAAALgAECgEJAQAAAA==.',
Kt='Kthxbye:BAAALgAECgUJBwABLgAECgcJBwAKAAAAAA==.',
Ku='Kumcookies:BAAALgADCgEJAQAAAA==.Kungfuprissy:BAAALgAECgMJBwAAAA==.Kuraishin:BAACLgAFFH8SAAIhAAMJGB7WCAAAAQAhAAMJGB7WCAAAAQAuAAQKf3sAAyIACAl0JFoEALsCACIACAnnIloEALsCACEABwkMI38GAFwCAAEuAAUUBAkWABAA4gsA.Kuroakuma:BAAALgAECgYJEAAAAA==.Kuvara:BAAALgADCgkJCgAAAA==.',
Kv='Kvnnp:BAAALgADCgYJBgAAAA==.Kvnpro:BAAALgADCgUJBwAAAA==.Kvnxx:BAAALgADCgUJBQAAAA==.',
Kw='Kwandashadow:BAAALgAECgUJDgAAAA==.',
Ky='Kylemonk:BAAALgADCgEJAQAAAA==.',
['Ké']='Kéres:BAAALgADCgkJEAAAAA==.',
La='Lagspike:BAABLgAECn8dAAIDAAgJqBVTlgCnAQADAAgJqBVTlgCnAQAAAA==.Latheal:BAAALgAECgMJBAAAAA==.Lavi:BAABLgAECn8dAAIGAAgJDA57ggBPAQAGAAgJDA57ggBPAQAAAA==.',
Lb='Lbk:BAAALgADCgIJAgAAAA==.',
Le='Lejeune:BAAALgAECgMJCQAAAA==.Lengex:BAAALgAECggJCwAAAA==.Lero:BAABLgAECn8iAAIaAAkJuCGgBADuAgAaAAkJuCGgBADuAgAAAA==.Lerwindion:BAABLgAECn8oAAIcAAgJOR+VCQCiAgAcAAgJOR+VCQCiAgABLgAFFAQJBwAQADUWAA==.Lescaryn:BAAALgADCgIJAgAAAA==.Lexoh:BAAALgAECgYJEgAAAA==.',
Li='Lilani:BAAALgADCgQJBAAAAA==.Lindir:BAACLgAFFH8NAAIOAAQJ3RomDQBPAQAOAAQJ3RomDQBPAQAuAAQKfygAAg4ACAk+JKkBAD8DAA4ACAk+JKkBAD8DAAAA.Lionelle:BAAALgAECgYJDgAAAA==.Liquor:BAACLgAFFH8XAAIVAAUJhxyrKgBPAQAVAAUJhxyrKgBPAQAuAAQKf04AAxUACQmJIYEJAO4CABUACQmJIYEJAO4CAAcAAwnPFFgdAJYAAAAA.Liquorish:BAAALgAECgEJAQABLgAFFAUJFwAVAIccAA==.Lirathiel:BAAALgAECgYJEwAAAA==.Litasfk:BAAALgAECgIJAgAAAA==.Liuni:BAABLgAECn8lAAIaAAkJlRTWHACtAQAaAAkJlRTWHACtAQAAAA==.Liyin:BAAALgAECgQJCQABLgAECgkJKwADAIEOAA==.',
Lo='Lobopeste:BAABLgAECn87AAIZAAkJUgnoIQApAQAZAAkJUgnoIQApAQAAAA==.Locknutz:BAAALgADCgMJAwAAAA==.Loracy:BAAALgADCgcJBwAAAA==.Lorantell:BAAALgAECgMJAwAAAA==.Lorelynn:BAABLgAECn8oAAICAAgJNA4PYQBzAQACAAgJNA4PYQBzAQAAAA==.',
Lu='Luci:BAABLgAECn8YAAQVAAgJ6RIPSACWAQAVAAgJkxIPSACWAQAHAAMJ1Q5dKgBEAAAmAAEJAADPdAAAAAABLgAFFAEJAQAKAAAAAA==.Lucìan:BAABLgAECn8lAAIYAAgJiCFRCwD4AgAYAAgJiCFRCwD4AgAAAA==.Ludociel:BAAALgAECgQJBAAAAA==.Lunaclair:BAACLgAFFH8WAAIQAAQJ4gtMZQAUAQAQAAQJ4gtMZQAUAQAuAAQKf1wAAxAACQkoHe0iAGYCABAACQkoHe0iAGYCABkABwmNENIlAAsBAAAA.Lunadrus:BAABLgAECn8mAAIDAAgJognJqwANAQADAAgJognJqwANAQAAAA==.Lunarielle:BAACLgAFFH8UAAINAAQJjBQ8KgBCAQANAAQJjBQ8KgBCAQAuAAQKfyEAAg0ACAkXHMYVAIkCAA0ACAkXHMYVAIkCAAAA.',
Ly='Lyriaa:BAAALgADCgYJCwAAAA==.',
Ma='Macalatraz:BAAALgAECgMJBwAAAA==.Macfly:BAABLgAECn8xAAINAAkJrRoCIgBGAgANAAkJrRoCIgBGAgAAAA==.Madmeatballs:BAAALgAECgEJAQABLgAECgkJKwADAFEfAA==.Magdala:BAAALgADCgEJAQAAAA==.Magicmissile:BAACLgAFFH8LAAIDAAMJhg/XcADgAAADAAMJhg/XcADgAAAuAAQKfykAAgMACAkcIIUjAHkCAAMACAkcIIUjAHkCAAEuAAUUBQkOABIAOg8A.Makgora:BAAALgAECgMJBAABLgAECgYJFgAWAFkhAA==.Makhvan:BAAALgAECgQJCgAAAA==.Maksoon:BAAALgAFFAIJAgAAAA==.Maladjusted:BAAALgAECgMJBAAAAA==.Maléfique:BAAALgAECgEJAQAAAA==.Mancath:BAAALgAECgkJCwAAAA==.Maplè:BAAALgAECgIJAwABLgAECggJIwAIAKITAA==.Mar:BAAALgADCgMJAwAAAA==.Marlei:BAAALgADCgQJBAABLgAECgkJKwADAIEOAA==.Marqose:BAAALgADCgcJDgABLgAECgMJBgAKAAAAAA==.Matan:BAAALgADCgUJBQAAAA==.',
Me='Meeko:BAAALgAFFAIJBAABLgAFFAgJGwAeAPggAA==.Melfie:BAABLgAECn8jAAIDAAkJzRkFJQByAgADAAkJzRkFJQByAgAAAA==.Meliadoul:BAABLgAECn8cAAIDAAgJ7wt8igBHAQADAAgJ7wt8igBHAQAAAA==.Mellyndra:BAABLgAECn87AAIJAAkJ3x5UCADyAgAJAAkJ3x5UCADyAgAAAA==.Mercüry:BAAALgAECgEJBAAAAA==.Mezhren:BAAALgAECgYJCwAAAA==.',
Mh='Mhoramsgirl:BAAALgADCggJCwAAAA==.',
Mi='Midoriya:BAACLgAFFH8IAAMFAAMJHQfAIgCvAAAFAAMJHQfAIgCvAAAEAAMJyQsJNACXAAAuAAQKfyMAAwUACQlnETMqAFABAAUACAkvEjMqAFABAAQABQmQEf5tAJMAAAAA.Mistjack:BAABLgAFFH8LAAIEAAUJthHsHAA0AQAEAAUJthHsHAA0AQAAAA==.',
Mo='Momdad:BAACLgAFFH8SAAIOAAUJ6xfTDgBEAQAOAAUJ6xfTDgBEAQAuAAQKfzQAAg4ACQnWIF4GALACAA4ACQnWIF4GALACAAAA.Mongaux:BAAALgADCgQJBQAAAA==.Monkey:BAAALgAECgQJCgAAAA==.Morrígán:BAAALgADCgUJBQAAAA==.Moxi:BAAALgADCggJDwAAAA==.',
Mu='Muamman:BAAALgAECgMJAwAAAA==.Murda:BAAALgADCgYJCgAAAA==.Murphysflaw:BAAALgADCgUJCAAAAA==.Mutegen:BAAALgAFFAEJAQAAAA==.',
Mx='Mxhealeryduf:BAAALgAECgIJAgAAAA==.',
My='Mystallian:BAAALgAECgQJCQAAAA==.Mystí:BAEALgAECgkJBgABLgAECgkJLwABADobAA==.Mythicplus:BAAALgAECgcJEQAAAA==.',
['Mé']='Mémnoc:BAAALgAECgMJAwAAAA==.',
Na='Nadarien:BAAALgAECgYJDQAAAA==.Nadyia:BAAALgADCgEJAQAAAA==.Nailah:BAAALgADCgcJCwAAAA==.Nannergoat:BAAALgADCgMJAwAAAA==.Nastymikey:BAABLgAECn8bAAIdAAgJNx13BwBzAgAdAAgJNx13BwBzAgAAAA==.Nazdormu:BAABLgAECn8fAAIeAAgJIQSwHAAEAQAeAAgJIQSwHAAEAQAAAA==.',
Ne='Nefarious:BAAALgAECgcJDgAAAA==.Neisen:BAABLgAECn8sAAMJAAgJQBlTFABWAgAJAAgJQBlTFABWAgAGAAUJBwKc+gCeAAAAAA==.Neptune:BAAALgADCgYJBgAAAA==.',
No='Norna:BAAALgADCgcJDwAAAA==.Noz:BAAALgADCgkJCQAAAA==.',
Nu='Nufonewhodis:BAABLgAECn8WAAIWAAYJWSF1HQATAgAWAAYJWSF1HQATAgAAAA==.',
Ny='Nykolas:BAAALgAECgEJAQAAAA==.Nymofthedead:BAABLgAECn8oAAMQAAgJiCO4EQDNAgAQAAgJiCO4EQDNAgARAAQJHhbxGQDOAAAAAA==.',
Oa='Oakgrove:BAAALgADCgUJBQAAAA==.',
Om='Ombraless:BAAALgADCgMJAwABLgAECgQJCAAKAAAAAA==.',
On='Oneforall:BAAALgAECgkJDgAAAA==.',
Op='Ophrizhani:BAAALgAECgMJAwAAAA==.',
Or='Orangegrove:BAAALgAECgYJBQAAAA==.Orpheal:BAAALgAECgUJBQAAAA==.Orphen:BAAALgAECgMJAwAAAA==.',
Os='Osìrìs:BAAALgAECgQJBAABLgAECggJJQAYAIghAA==.',
Pa='Paddleball:BAAALgADCgQJBAAAAA==.Paladouin:BAAALgAECgYJEwAAAA==.Pandammy:BAAALgAECgkJBQAAAA==.Pantro:BAABLgAECn8dAAMhAAkJzBaMCAAkAgAhAAkJzBaMCAAkAgAiAAEJAAD9eQAAAAAAAA==.Papalion:BAABLgAECn8XAAINAAYJugwpkQACAQANAAYJugwpkQACAQAAAA==.Paragas:BAAALgADCgkJEAAAAA==.Pawbs:BAAALgAECgQJEQAAAA==.',
Pe='Peanuts:BAAALgADCgcJBwAAAA==.Peoplehugger:BAAALgADCgMJAwAAAA==.',
Pi='Pickleburger:BAAALgAECgEJAQAAAA==.Pinklilydrd:BAAALgAECgMJCQAAAA==.',
Pl='Plaindonut:BAAALgAECgcJEwAAAA==.',
Po='Porple:BAAALgAECgYJBwAAAA==.',
Pr='Priestdrago:BAAALgADCgUJBQAAAA==.Prissidebow:BAAALgAECgMJCQAAAA==.',
Qu='Quartz:BAAALgAECgYJCQABLgAFFAMJDgASAHwkAA==.',
Ra='Rahzule:BAAALgADCgYJBwAAAA==.Ralynne:BAABLgAECn8uAAILAAgJMxS9JwCVAQALAAgJMxS9JwCVAQAAAA==.Raskus:BAAALgADCgEJAQAAAA==.Ravenbrook:BAACLgAFFH8XAAISAAUJaCboBQDIAQASAAUJaCboBQDIAQAuAAQKfyMAAxIACAlbJXsEAGIDABIACAlbJXsEAGIDABcAAQkwIPtZAFMAAAAA.Rawrr:BAABLgAECn8gAAImAAgJKguVIwA3AQAmAAgJKguVIwA3AQAAAA==.Rawrxd:BAAALgAECgEJAgABLgAECggJDgAKAAAAAA==.Raxie:BAACLgAFFH8XAAMcAAUJOBfeFQCGAQAcAAUJOBfeFQCGAQAnAAEJBQ3SFABRAAAuAAQKfy0ABBwACQnXGnMMAIkCABwACQnXGnMMAIkCACcABwnIE94oAGkBABQAAQkBBPGHACgAAAAA.Razeth:BAABLgAECn8VAAIOAAYJ8BY1KgA/AQAOAAYJ8BY1KgA/AQAAAA==.',
Re='Reanne:BAAALgAECgYJEAAAAA==.Res:BAAALgAECgYJCwAAAA==.Rescorla:BAAALgAECgkJDAAAAA==.Rethali:BAAALgADCgQJAgAAAA==.Rezr:BAAALgAECggJDgAAAA==.',
Rh='Rhixa:BAAALgADCgUJBQAAAA==.Rhymunky:BAAALgAECgYJDQAAAA==.',
Ri='Rifthor:BAAALgAECgYJEgAAAA==.Rillx:BAAALgADCgQJBgAAAA==.Ripmxi:BAABLgAECn8uAAIDAAkJUhKbVwC+AQADAAkJUhKbVwC+AQAAAA==.',
Ro='Robinski:BAAALgADCgEJAQAAAA==.Robotiss:BAAALgADCgIJAgAAAA==.Rocco:BAAALgADCgYJBwAAAA==.Rodevon:BAAALgADCggJCAAAAA==.Roknasaurus:BAAALgADCgUJCAAAAA==.Romani:BAAALgADCgYJBgAAAA==.Romeo:BAAALgAECgQJBAAAAA==.Ronaldreagnt:BAAALgAECgcJDgAAAA==.',
Ru='Runecat:BAAALgAFFAIJAgAAAA==.Runelight:BAACLgAFFH8IAAMcAAMJOQHHMQCMAAAcAAMJOQHHMQCMAAAnAAIJsgFdLQBhAAAuAAQKfxQABBwABwnoCfc5AAEBABwABgnUCvc5AAEBABQABQmACYVEAL8AACcAAwkQBY9dAHEAAAAA.Runeshock:BAAALgAECgYJBgAAAA==.Runestick:BAAALgAECgIJAgAAAA==.Rupertgiless:BAACLgAFFH8NAAICAAUJ1BD8KQBxAQACAAUJ1BD8KQBxAQAuAAQKfyYAAgIACQl0G30iAIsCAAIACQl0G30iAIsCAAAA.',
Sa='Sabeckya:BAAALgAECgQJCgAAAA==.Sacksmasher:BAAALgADCgcJDwAAAA==.Sampleshrimp:BAAALgADCgEJAgAAAA==.Saphyla:BAAALgADCgcJCwAAAA==.Sappheire:BAAALgAECgYJBgAAAA==.Sarcastyx:BAAALgAECgYJBwAAAA==.Sarrod:BAAALgADCgUJBQAAAA==.Saxines:BAAALgAECgYJEQAAAA==.',
Sc='Scaliefox:BAAALgAECgIJAgABLgAECgkJOwAJAN8eAA==.Scarl:BAAALgADCgUJBQAAAA==.Schwarznacht:BAAALgADCgUJBQAAAA==.Schwarzwölf:BAAALgADCgYJCwAAAA==.Scoots:BAAALgADCgQJBAAAAA==.Scrubs:BAAALgAECgYJDAAAAA==.Scrubsevoker:BAAALgAECgQJCAAAAA==.Scumbum:BAAALgADCgIJAgAAAA==.Scyllo:BAAALgAECgQJBAAAAA==.',
Se='Seekndestroy:BAAALgAECgYJEgAAAA==.Selige:BAAALgAECgQJBAAAAA==.',
Sg='Sgtcuunt:BAAALgADCgQJBAAAAA==.',
Sh='Shaenicor:BAAALgADCgIJAgAAAA==.Shankkerz:BAAALgAECgYJBgAAAA==.Shelbo:BAAALgADCgcJEAAAAA==.Shmolda:BAAALgADCgYJBwAAAA==.Shortshammy:BAAALgAECgEJAQABLgAFFAMJCwADACUJAA==.Shror:BAAALgADCgEJAQABLgAECgUJBQAKAAAAAA==.',
Si='Sicarune:BAAALgAECgUJBgAAAA==.Siiegrand:BAABLgAECn8VAAIbAAcJhRCIIQDsAAAbAAcJhRCIIQDsAAAAAA==.Silentswag:BAAALgAECgYJDgAAAA==.Sindrane:BAAALgAECgMJAwABLgAECgkJMgAQAKoUAA==.Sitzho:BAAALgADCgUJCAAAAA==.',
Sk='Skeleton:BAAALgAECgIJAgAAAA==.Skybringer:BAABLgAECn8wAAIGAAcJYQxYoAAbAQAGAAcJYQxYoAAbAQAAAA==.Skyee:BAABLgAECn8qAAMFAAkJvx0LDAC6AgAFAAkJvx0LDAC6AgAEAAMJGxRQZwCoAAAAAA==.Skylos:BAAALgAECgEJAgAAAA==.',
Sm='Smexibiotch:BAAALgADCgYJBgABLgADCggJCAAKAAAAAA==.',
So='Soapscum:BAAALgADCgQJBAAAAA==.Soarphium:BAAALgAECgIJAgABLgAFFAYJGAAWAO8PAA==.Solararc:BAAALgADCgEJAgAAAA==.Soleana:BAAALgAECgYJBQAAAA==.Sombra:BAAALgAECgMJBgABLgAECgcJDgAKAAAAAA==.Sonicast:BAAALgAECgYJCQAAAA==.Sooie:BAAALgAECgYJEgAAAA==.Soramian:BAAALgADCgcJEgAAAA==.Soulcacher:BAABLgAECn8yAAMQAAkJqhShSwAQAgAQAAgJJxahSwAQAgAZAAgJvQ+AGgBvAQAAAA==.Soxxy:BAAALgAECgEJAQABLgAFFAEJAQAKAAAAAA==.',
Sp='Spellgunner:BAABLgAECn8VAAIDAAgJPxvkVgDAAQADAAgJPxvkVgDAAQAAAA==.Spinsaround:BAAALgADCgEJAQAAAA==.',
St='Stormwulf:BAAALgADCgUJBQABLgAECgMJDAAKAAAAAA==.Stormyprissi:BAAALgAECgQJCAAAAA==.Strombjorn:BAABLgAECn8jAAMIAAgJohO8QQCKAQAIAAgJohO8QQCKAQALAAUJwQy3VwDBAAAAAA==.',
['Sø']='Sølaria:BAAALgAECgEJAQAAAA==.',
Ta='Tasireth:BAAALgADCgcJBwAAAA==.',
Te='Tessi:BAACLgAFFH8GAAIDAAMJrgLSigCZAAADAAMJrgLSigCZAAAuAAQKfxYAAgMABgkiET6dACUBAAMABgkiET6dACUBAAAA.',
Th='Thalrian:BAAALgAECgQJBQABLgAFFAMJBQASAKIZAA==.Thefailnym:BAAALgAECggJCgAAAA==.Theylive:BAABLgAECn8dAAIYAAkJIw+MMQDHAQAYAAkJIw+MMQDHAQAAAA==.Thondrin:BAAALgAECgYJCwAAAA==.Thordanil:BAAALgAECgEJAgAAAA==.Thrashedass:BAAALgADCgEJAQAAAA==.',
Ti='Tigerlilliy:BAAALgADCgYJEAAAAA==.Timerek:BAAALgADCgIJAgAAAA==.',
To='Toawulf:BAAALgAECgQJCAABLgAECgMJDAAKAAAAAA==.Toetickla:BAAALgAECgEJAQAAAA==.Tokifuji:BAAALgAECgIJAwABLgAECgQJEQAKAAAAAA==.Toya:BAABLgAECn8xAAIWAAkJZRziCwBPAgAWAAkJZRziCwBPAgAAAA==.',
Tr='Trenazen:BAAALgADCgkJCgAAAA==.Trevain:BAAALgAECgEJAgAAAA==.Trimasdrood:BAAALgADCgMJAwAAAA==.Trivia:BAAALgAECgUJBQAAAA==.Trundle:BAAALgAECgEJAwAAAA==.Truthordare:BAABLgAECn8hAAIBAAcJUggBGQDGAAABAAcJUggBGQDGAAAAAA==.Trysla:BAAALgAECgEJAQAAAA==.',
Tu='Turtei:BAAALgAECgEJAQABLgAFFAcJJQAFAE0mAA==.Turtl:BAACLgAFFH8lAAIFAAcJTSaNAACwAgAFAAcJTSaNAACwAgAuAAQKfysAAgUACQnmJjcAAPgDAAUACQnmJjcAAPgDAAAA.',
Tw='Twohoof:BAAALgADCgEJAQAAAA==.',
Tx='Txìewtkuä:BAAALgADCgkJCQAAAA==.',
Ty='Tyryn:BAAALgADCgMJBAAAAA==.',
Ug='Uglydragon:BAAALgAECgcJDAAAAA==.Uglypally:BAAALgADCgkJCQAAAA==.Uglypetguy:BAAALgAECgIJAgAAAA==.Uglyrogue:BAAALgAECgQJAgAAAA==.Uglyshaman:BAAALgAECgEJAgAAAA==.',
Ul='Ulgrym:BAAALgAECgMJBQAAAA==.Ultimatia:BAAALgADCgMJBwAAAA==.',
Un='Unbalancéd:BAABLgAECn8XAAIEAAUJqiIYIQDrAQAEAAUJqiIYIQDrAQAAAA==.',
Va='Vaeadin:BAAALgAECgEJAQAAAA==.Vahra:BAAALgAECgMJCQAAAA==.Valanther:BAAALgAECgMJAwAAAA==.Valantis:BAAALgADCgEJAQAAAA==.Valgaskav:BAABLgAECn8oAAIGAAkJXyPKCAAQAwAGAAkJXyPKCAAQAwAAAA==.Valimond:BAAALgAECgEJAQABLgAECgMJDAAKAAAAAA==.Valric:BAAALgAECgEJAQAAAA==.Vanarrath:BAAALgADCgYJBwAAAA==.Vandryelle:BAAALgADCgIJAgAAAA==.Varge:BAAALgADCgMJAwAAAA==.Varrathos:BAAALgADCgkJEgAAAA==.Vayl:BAAALgAECgMJAwAAAA==.',
Ve='Velisa:BAAALgADCgYJBgAAAA==.Ventrue:BAAALgADCgMJAwAAAA==.Verdesoul:BAAALgAECgcJDQAAAA==.Vesyra:BAAALgAECgQJBQAAAA==.',
Vi='Viralyn:BAAALgADCgMJAwABLgAECgkJJQAaAJUUAA==.Vixøn:BAAALgAECgMJBQAAAA==.',
Vo='Voidluck:BAABLgAECn8SAAIVAAgJvxBkdABIAQAVAAgJvxBkdABIAQAAAA==.Voker:BAAALgAECgMJCQABLgAECgQJEQAKAAAAAA==.Voladis:BAAALgAECgYJCgAAAA==.Voladro:BAAALgAECgQJBAAAAA==.Volos:BAABLgAECn8pAAIGAAgJORaeTwDBAQAGAAgJORaeTwDBAQAAAA==.Vordaman:BAABLgAECn8tAAIQAAkJYRNvTQDHAQAQAAkJYRNvTQDHAQAAAA==.',
Vy='Vynír:BAACLgAFFH8XAAICAAYJvhzWGAC0AQACAAYJvhzWGAC0AQAuAAQKfy4AAwIACQmgI4gHABADAAIACQk+I4gHABADAAEABQkHI40NAOwBAAAA.',
Wa='Waghoba:BAECLgAFFH8iAAIhAAYJaxxdAQC8AQAhAAYJaxxdAQC8AQAuAAQKfyIAAiEACQnMIScGAJwCACEACQnMIScGAJwCAAAA.Waito:BAAALgAECgQJBwAAAA==.Wandä:BAABLgAECn8wAAQaAAkJ7BywCACXAgAaAAkJcRywCACXAgAFAAgJrRHOIQCLAQAEAAEJtQ77nAAuAAAAAA==.Wardriccan:BAAALgAECggJDgAAAA==.Warfle:BAAALgADCgYJBgAAAA==.Warhound:BAAALgADCgcJBwAAAA==.Warrionomous:BAACLgAFFH8OAAISAAUJOg+AHQAnAQASAAUJOg+AHQAnAQAuAAQKfxsAAhIACAklG8wXABsCABIACAklG8wXABsCAAAA.Washu:BAABLgAECn8/AAMmAAkJOB+3BQDIAgAmAAkJOB+3BQDIAgAHAAMJTAtZIQB5AAAAAA==.',
Wh='Whimlock:BAAALgADCgQJBAABLgAFFAMJBwADAOUcAA==.Whimzie:BAAALgAECgEJAQABLgAFFAMJBwADAOUcAA==.Whorphium:BAAALgAECggJEgABLgAFFAYJGAAWAO8PAA==.',
Wi='Willow:BAAALgAECgYJCwAAAA==.Winterous:BAAALgAECgEJBAAAAA==.',
Wo='Wonderbread:BAABLgAECn88AAIGAAkJ9xX3MAAkAgAGAAkJ9xX3MAAkAgAAAA==.',
Wr='Wrager:BAAALgAECgUJBgAAAA==.Wrathofzaun:BAAALgAECgYJDwAAAA==.',
Wy='Wylest:BAAALgADCgcJBwAAAA==.Wynch:BAAALgAECgkJCQAAAA==.',
['Wâ']='Wârwôlf:BAABLgAECn8pAAMNAAkJHCQwBQAvAwANAAkJHCQwBQAvAwAMAAQJ+BWyVQDzAAAAAA==.',
Xe='Xenan:BAABLgAECn80AAIGAAkJBRUcNgAQAgAGAAkJBRUcNgAQAgAAAA==.',
Xt='Xtrolldinary:BAAALgAECgQJEQAAAA==.',
Xv='Xvp:BAAALgAECgQJCgAAAA==.',
Xy='Xylophy:BAABLgAECn8rAAIHAAkJPBR/CADTAQAHAAkJPBR/CADTAQAAAA==.',
Ye='Yeastmode:BAACLgAFFH8UAAINAAUJDhDcNAArAQANAAUJDhDcNAArAQAuAAQKfycAAg0ACAkVHQUjAEECAA0ACAkVHQUjAEECAAAA.',
Yo='Yonah:BAAALgAECgYJDAAAAA==.',
Yu='Yurc:BAABLgAECn8lAAIfAAgJBBuBCwAfAgAfAAgJBBuBCwAfAgAAAA==.',
Za='Zademan:BAAALgAECgUJBwAAAA==.Zappyu:BAAALgAECgkJBQABLgAECgkJCQAKAAAAAA==.Zarkas:BAAALgAECgEJAQAAAA==.',
Ze='Zeebra:BAAALgAECgYJCgAAAA==.Zeg:BAAALgAECgQJBAAAAA==.Zega:BAAALgAECgEJAQAAAA==.Zegafur:BAABLgAECn8qAAIYAAgJ/RtpJQAOAgAYAAgJ/RtpJQAOAgAAAA==.Zeruk:BAABLgAECn8XAAMFAAcJjwJ1YACOAAAFAAYJlAJ1YACOAAAEAAcJpQGPegBvAAAAAA==.',
Zi='Zillionbúcks:BAACLgAFFH8bAAIGAAcJyRN1DADKAQAGAAcJyRN1DADKAQAuAAQKfxsAAgYACQmvHtEtAGwCAAYACQmvHtEtAGwCAAAA.',
Zu='Zullee:BAAALgADCgkJCQAAAA==.',
Zy='Zylcat:BAAALgAECgYJDAAAAA==.',
['Zê']='Zêddicus:BAABLgAECn8wAAMBAAkJpSBWAQDFAgABAAkJpSBWAQDFAgACAAUJHwgM1ACyAAAAAA==.',
['Áq']='Áquafina:BAABLgAECn88AAIDAAkJpg5hUgDNAQADAAkJpg5hUgDNAQAAAA==.',
['Åñ']='Åñgêl:BAAALgADCggJCAAAAA==.',
['Îv']='Îvan:BAAALgADCggJCAAAAA==.',
['Ðö']='Ðö:BAABLgAECn8uAAISAAkJDB3+DACJAgASAAkJDB3+DACJAgAAAA==.',
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
