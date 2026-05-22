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

local lookup = {'Warlock-Destruction','Warlock-Demonology','Monk-Brewmaster','Mage-Frost','Monk-Mistweaver','Monk-Windwalker','Paladin-Retribution','Shaman-Restoration','Paladin-Holy','Unknown-Unknown','Hunter-Marksmanship','Hunter-Survival','Hunter-BeastMastery','DeathKnight-Unholy','Warrior-Fury','Evoker-Devastation','Priest-Holy','DemonHunter-Devourer','Rogue-Subtlety','Warrior-Arms','Druid-Restoration','DeathKnight-Blood','DeathKnight-Frost','Paladin-Protection','Priest-Discipline','Evoker-Augmentation','Evoker-Preservation','Warrior-Protection','Shaman-Elemental','Rogue-Outlaw','Druid-Feral','Warlock-Affliction','Druid-Guardian','DemonHunter-Vengeance','DemonHunter-Havoc','Shaman-Enhancement','Priest-Shadow',}
local provider = {region='US',realm='Anvilmar',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aaril:BAAALgAECgMJCAAAAQ==.',
Ad='Adel:BAAALgAECgEJAQAAAA==.',
Ae='Aelitha:BAABLgAECn8ZAAMBAAYJCQZ2OQDOAAABAAYJxAR2OQDOAAACAAYJsQRsoAC9AAAAAA==.',
Ak='Akaishi:BAAALgADCgIJAgAAAA==.Akali:BAAALgAFFAEJAQABLgAECggJHQADAIcUAA==.Akina:BAAALgADCgYJBwABLgAECgkJIwAEALMMAA==.',
Al='Alanie:BAAALgADCgYJBgAAAA==.Alathiana:BAAALgADCgUJCAAAAA==.Alcweaver:BAABLgAECn8aAAMFAAcJgiBpGgDLAQAFAAcJgiBpGgDLAQAGAAYJgA9WKwARAQAAAA==.Alecto:BAAALgAECgMJAwAAAA==.Alindia:BAAALgAECgQJCgABLgAECgkJIwAEALMMAA==.Alirrayia:BAAALgAECgQJBAAAAA==.Alirrayiia:BAACLgAFFH8IAAIHAAMJ+AE5TAC7AAAHAAMJ+AE5TAC7AAAuAAQKfygAAgcACQmeEC1NAPsBAAcACQmeEC1NAPsBAAAA.Alkri:BAAALgADCgMJAwAAAA==.Allari:BAAALgAECgYJEwAAAA==.Allikazam:BAAALgADCgYJCQAAAA==.Allystar:BAAALgAECgMJBwAAAA==.Altheia:BAAALgAECgQJBAAAAA==.Alvidor:BAABLgAECn8qAAIEAAgJaAMYngAEAQAEAAgJaAMYngAEAQAAAA==.',
Am='Ameria:BAAALgADCgUJBQAAAA==.',
An='Anastos:BAAALgAECgUJBQAAAA==.Andydufresne:BAAALgAECgQJCAAAAA==.Angryqueer:BAAALgADCgEJAQAAAA==.',
Ao='Aowl:BAAALgAECgcJCwAAAA==.',
Ap='Apocketheory:BAAALgADCgIJAgAAAA==.Apolloerosb:BAAALgADCggJDgABLgAECgcJFQAIALITAA==.Apollossham:BAABLgAECn8VAAIIAAcJshPULgCfAQAIAAcJshPULgCfAQAAAA==.',
Ar='Arkanaun:BAABLgAECn8dAAMHAAYJRBdpcwCUAQAHAAYJRBdpcwCUAQAJAAUJvRTnOQAQAQAAAA==.',
As='Ashes:BAAALgAECgcJAQAAAA==.Ashrán:BAAALgAECgYJCQAAAA==.Ashyluna:BAAALgAECgQJBAAAAA==.Astianna:BAAALgADCgMJAwAAAA==.',
Au='Aule:BAAALgAECgEJAQAAAA==.Aurinia:BAAALgADCgQJAgAAAA==.Auroradinlee:BAAALgAECgkJBgAAAA==.Aurore:BAAALgADCgQJBgAAAA==.',
Av='Avradea:BAAALgADCgEJAQABLgAECgkJIwAEALMMAA==.',
Az='Azareth:BAAALgADCggJCAAAAA==.',
Ba='Baconatorr:BAAALgAECgMJAwAAAA==.Bagelbags:BAAALgADCgEJAQAAAA==.Bahler:BAAALgADCgUJBQABLgAECgMJAwAKAAAAAA==.Baji:BAABLgAECn8tAAIIAAgJcyPGBgD7AgAIAAgJcyPGBgD7AgAAAA==.Baklan:BAAALgAECgMJAwAAAA==.Barefaall:BAACLgAFFH8JAAILAAUJ6Q4wDwD1AAALAAUJ6Q4wDwD1AAAuAAQKfzcAAgsACQk/IKgBAM0CAAsACQk/IKgBAM0CAAAA.Barefall:BAAALgAFFAIJAgABLgAFFAUJCQALAOkOAA==.Barefalls:BAACLgAFFH8FAAIMAAMJlhyYEAAMAQAMAAMJlhyYEAAMAQAuAAQKfyUAAwwACQkfHhYGAIkCAAwACQkfHhYGAIkCAAsAAQmMAaCWACIAAAEuAAUUBQkJAAsA6Q4A.Barelywolf:BAABLgAECn8bAAMFAAcJYhkyGADhAQAFAAcJYhkyGADhAQAGAAMJ/RxHLwD7AAABLgAFFAIJAwAKAAAAAA==.Bashira:BAABLgAECn8bAAINAAgJKQt4SQBsAQANAAgJKQt4SQBsAQAAAA==.Bast:BAABLgAECn8cAAIOAAgJExLlUACJAQAOAAgJExLlUACJAQAAAA==.Bastrillan:BAAALgAECgEJAQAAAA==.',
Be='Bearophe:BAAALgAECgEJAgAAAA==.Beerfist:BAAALgAECgEJAQAAAA==.Bellock:BAAALgAECgMJAwAAAA==.Benisbagina:BAAALgADCggJCQAAAA==.Bergonator:BAABLgAECn8gAAIPAAYJcRC9TwBpAQAPAAYJcRC9TwBpAQAAAA==.Berrodiah:BAAALgAECgYJCAABLgAECggJFgAQALUYAA==.Bettyswalls:BAAALgAECgMJAwAAAA==.Beyarago:BAAALgAECgUJCQAAAA==.',
Bh='Bheiroth:BAABLgAECn8sAAIRAAgJBiRoBQDmAgARAAgJBiRoBQDmAgAAAA==.',
Bi='Birds:BAAALgAECgQJBgAAAA==.',
Bl='Bladeygaga:BAABLgAECn8kAAISAAgJ8RzYHAAjAgASAAgJ8RzYHAAjAgAAAA==.Blasé:BAAALgAECgcJCAAAAA==.Blazingblood:BAAALgADCgUJAQAAAA==.Bloodknight:BAAALgADCgYJCQAAAA==.Bluett:BAAALgAECgEJAQAAAA==.Bláckøut:BAAALgADCgYJDAAAAA==.',
Bo='Bodhi:BAABLgAECn8WAAITAAcJNhAQJwDAAQATAAcJNhAQJwDAAQAAAA==.Bogertus:BAACLgAFFH8KAAIPAAMJIiQEFQAqAQAPAAMJIiQEFQAqAQAuAAQKfzgAAw8ACQnMJiQAAI8DAA8ACQnMJiQAAI8DABQAAgn1HHIpAKUAAAAA.Boomertunes:BAABLgAECn8bAAMCAAcJWBd5QwCSAQACAAcJWBd5QwCSAQABAAIJGwHgPwAAAAAAAA==.',
Br='Brein:BAABLgAECn8qAAIVAAgJuCVoAwBfAwAVAAgJuCVoAwBfAwAAAA==.Brewmaster:BAAALgAECgIJAwAAAA==.Brewwmaster:BAABLgAECn8kAAQWAAkJqxg6DgDQAQAWAAkJHxU6DgDQAQAOAAYJtBfWfACKAQAXAAEJ+he5FgA2AAAAAA==.Brickred:BAAALgADCggJDgAAAA==.Brynodd:BAAALgAECgEJAQAAAA==.',
Bu='Bubblybetty:BAAALgAECgEJAQAAAA==.Bucketeer:BAABLgAECn8oAAIEAAkJAx+IEgC1AgAEAAkJAx+IEgC1AgAAAA==.Buffs:BAAALgADCgEJAQAAAA==.Bursona:BAAALgAECgEJAQAAAA==.Butterfree:BAAALgAECgUJDAAAAA==.',
Ca='Cards:BAAALgAECgYJCgAAAA==.Carkrash:BAAALgADCgkJFwAAAA==.Casterkang:BAAALgAECgUJCQAAAA==.Catshunter:BAAALgAECgYJDQAAAA==.',
Ce='Celaa:BAABLgAECn8jAAIEAAkJswycRwDBAQAEAAkJswycRwDBAQAAAA==.',
Ch='Chanka:BAAALgAECgQJBAAAAA==.Chantillary:BAAALgAECgEJAQAAAA==.Chargerkang:BAAALgADCgYJBgAAAA==.Chchanges:BAAALgAECgEJAQAAAA==.Cheesy:BAABLgAECn8XAAICAAcJ+geVewAFAQACAAcJ+geVewAFAQAAAA==.Chicken:BAAALgAECgYJDQAAAA==.Chonk:BAAALgADCgEJAQAAAA==.Chopzullee:BAAALgAECgYJEgAAAA==.',
Ci='Cirya:BAAALgAECgUJCAAAAA==.',
Cl='Cleric:BAAALgADCgUJBQAAAA==.Clortho:BAAALgADCgkJIAAAAA==.',
Co='Coljack:BAAALgAECggJCAAAAA==.Colljack:BAACLgAFFH8VAAIJAAUJ9R54DACKAQAJAAUJ9R54DACKAQAuAAQKfyEAAwkACQkgIZwJANgCAAkACQkgIZwJANgCAAcABQlOEtO5ABIBAAAA.',
Cr='Crocbait:BAAALgAECgcJEQAAAA==.Cryptoe:BAABLgAECn8YAAIEAAgJXA7ZXgCCAQAEAAgJXA7ZXgCCAQAAAA==.',
Cu='Cudlsac:BAAALgAECgQJBQAAAA==.',
Da='Daedelus:BAAALgAECgcJEQAAAA==.Daglon:BAAALgAECggJDAAAAA==.Dagz:BAAALgAECgQJBAAAAA==.Dakina:BAAALgADCgYJBgAAAA==.Daraedra:BAAALgADCgYJEgAAAA==.Darkenvoid:BAAALgADCgkJDQAAAA==.',
De='Deathslight:BAAALgAECgQJBwAAAA==.Deeznutticus:BAACLgAFFH8TAAIPAAUJ7BanCwBHAQAPAAUJ7BanCwBHAQAuAAQKfx8AAw8ABwnCIkgYAIkCAA8ABwnCIkgYAIkCABQAAQkSFhw8AEEAAAAA.Defnotisis:BAABLgAECn8dAAMDAAgJhxRoHQB9AQADAAcJCRZoHQB9AQAGAAgJtAugLQAEAQAAAA==.Demonspud:BAABLgAECn8cAAISAAcJChI+SABeAQASAAcJChI+SABeAQAAAA==.Denxster:BAAALgAECgUJBgAAAA==.Dersan:BAAALgAECgcJEgAAAA==.Destriant:BAABLgAECn8yAAIYAAgJORonCQBCAgAYAAgJORonCQBCAgAAAA==.Devilschant:BAAALgAECgYJCgAAAA==.Devilshadow:BAAALgAECgUJBwABLgAECgYJCgAKAAAAAA==.Dewburt:BAAALgADCggJCgAAAA==.Deylia:BAAALgADCgYJBgABLgAFFAQJDgAZAC0UAA==.',
Di='Dilithia:BAAALgAECgMJBwAAAA==.Dillion:BAAALgAECgYJCAAAAA==.Dinonuggies:BAAALgADCgcJBwAAAA==.Dionin:BAAALgADCgYJCQAAAA==.Dira:BAAALgAECgYJEAAAAA==.Dirkbanne:BAAALgADCgYJBgAAAA==.',
Do='Dodoubleg:BAAALgAECgYJEAAAAA==.Dominique:BAAALgADCgYJBgAAAA==.Donzilch:BAEALgAECgQJBAAAAA==.Donzilly:BAAALgAECgUJBQAAAA==.Dooburt:BAAALgADCgYJBgAAAA==.',
Dr='Dracaric:BAABLgAECn8iAAIaAAgJIxaMGADDAQAaAAgJIxaMGADDAQAAAA==.Dragondznut:BAAALgAECgQJBQAAAA==.Drfrostie:BAAALgAECgcJCgAAAA==.Drgunner:BAAALgAECgcJDwAAAA==.Driatin:BAAALgAECgIJBAABLgAECgUJDAAKAAAAAA==.Drkladykikyo:BAAALgAECgcJDwAAAA==.Druroo:BAAALgAECgEJAQABLgAECggJHwAZADkfAA==.Druterr:BAAALgAECgIJAgAAAA==.',
Du='Dumb:BAACLgAFFH8PAAIbAAUJLAyTBgCJAQAbAAUJLAyTBgCJAQAuAAQKfyMAAhsACAnoG28LAH4CABsACAnoG28LAH4CAAAA.Durø:BAABLgAECn8WAAISAAgJryLZDAAZAwASAAgJryLZDAAZAwAAAA==.',
Dy='Dyanisian:BAAALgADCgYJCAAAAA==.',
['Dè']='Dègenerate:BAABLgAECn8tAAIcAAgJASHuBQBuAgAcAAgJASHuBQBuAgAAAA==.',
Ed='Edagerran:BAAALgADCgkJCQAAAA==.',
Ei='Eilae:BAAALgAECgQJCgAAAA==.Eirhakan:BAAALgAECgQJCAAAAA==.',
El='Elrethyl:BAABLgAECn8WAAIHAAcJXhiMUQCKAQAHAAcJXhiMUQCKAQAAAA==.Elvanus:BAAALgADCgYJBgAAAA==.Elêktra:BAABLgAECn8pAAIdAAgJ5Q/oJwBXAQAdAAgJ5Q/oJwBXAQAAAA==.',
Ep='Epicnym:BAAALgADCgcJBwAAAA==.Epicsmoke:BAABLgAECn80AAIPAAkJtiJKAwAEAwAPAAkJtiJKAwAEAwAAAA==.Epidemius:BAAALgAECgkJCgAAAA==.',
Er='Erevan:BAABLgAECn8lAAMTAAgJug4yGQB2AQATAAgJug4yGQB2AQAeAAEJpwABEAAcAAAAAA==.Eroica:BAAALgADCgYJBwAAAA==.',
Es='Esdeath:BAABLgAECn8oAAMOAAgJfxQjTQCTAQAOAAgJfxQjTQCTAQAWAAYJWgZ9KwCoAAAAAA==.',
Et='Etharia:BAAALgADCgUJAwAAAA==.',
Ev='Evilsmeghead:BAAALgADCgEJAQAAAA==.',
Ex='Extenze:BAABLgAECn8mAAISAAgJtRxpHQAfAgASAAgJtRxpHQAfAgAAAA==.',
Ez='Ezykiah:BAAALgADCggJGQAAAA==.',
Fa='Falconponch:BAAALgADCgEJAQAAAA==.',
Fe='Felgibson:BAAALgAECgQJBQAAAA==.Felkang:BAAALgADCgkJCQAAAA==.Ferryman:BAAALgAECgQJBwAAAA==.',
Fl='Flingor:BAAALgAECgYJEAAAAA==.Flokha:BAAALgADCgEJAQAAAA==.',
Fo='Forphium:BAACLgAFFH8VAAITAAUJPxKlBACkAQATAAUJPxKlBACkAQAuAAQKfxwAAhMACQlbH30NAMQCABMACQlbH30NAMQCAAAA.',
Fr='Fredolf:BAAALgADCgkJDgAAAA==.Freydís:BAAALgAECgUJCwAAAA==.Friarkuck:BAAALgADCggJCAAAAA==.Friedbones:BAAALgAECgEJAQAAAA==.Frostlilliy:BAAALgADCggJCwAAAA==.',
Ga='Gahlina:BAAALgAECgMJCAAAAA==.Galdorian:BAAALgADCgYJCQABLgAECggJGwANACkLAA==.Galynda:BAAALgADCgQJBQAAAA==.',
Ge='Genjimain:BAABLgAECn8lAAMVAAkJBhqRHgBKAgAVAAkJBhqRHgBKAgAfAAMJ9wzOIQCRAAAAAA==.Genjí:BAAALgAECgEJAwAAAA==.Geris:BAAALgAECgQJBQAAAA==.Gertruide:BAAALgADCgUJBQAAAA==.',
Gh='Ghendala:BAAALgADCggJEwAAAA==.',
Gi='Gillesmon:BAAALgAECgYJCAABLgAECggJDAAKAAAAAA==.Gincainn:BAAALgAECgEJAgAAAA==.Gird:BAABLgAECn8oAAIJAAgJ4Q0IKgBvAQAJAAgJ4Q0IKgBvAQAAAA==.',
Gl='Glaiveyjones:BAAALgAECgEJAQAAAA==.',
Gn='Gnymesis:BAAALgADCgkJEAAAAA==.',
Go='Goatmonger:BAAALgAECgYJBgAAAA==.Goinpostal:BAAALgAECgIJAgAAAA==.Goldblade:BAAALgAECgkJCwAAAA==.Goodvsevil:BAAALgAECgQJBAAAAA==.Gordek:BAABLgAECn8bAAMHAAgJDxzSJAApAgAHAAgJDxzSJAApAgAJAAIJhBBZXgBfAAAAAA==.Gothitelle:BAAALgAECgEJAQAAAA==.Goöse:BAACLgAFFH8XAAIOAAUJ7iHdAwDEAQAOAAUJ7iHdAwDEAQAuAAQKfycAAg4ACAmDJusGAGsDAA4ACAmDJusGAGsDAAAA.',
Gr='Grantaron:BAABLgAECn8yAAIHAAgJjiBAGADXAgAHAAgJjiBAGADXAgAAAA==.Gravarii:BAAALgADCgcJEwAAAA==.Grimskul:BAABLgAECn8hAAMOAAgJexf5PgDBAQAOAAgJMRf5PgDBAQAXAAYJDxSUBwCBAQAAAA==.Grindor:BAAALgADCgEJAQAAAA==.Grntitan:BAAALgAECgQJBAAAAA==.Gruid:BAAALgADCgcJDwAAAA==.',
Gu='Guinessbrew:BAAALgAECgEJAQAAAA==.',
Gw='Gwoohoori:BAAALgAECggJCwAAAA==.',
Gy='Gyra:BAAALgAECgYJEQAAAA==.',
Ha='Halukari:BAAALgAECgYJEwABLgAFFAQJDgAZAC0UAA==.Harfnan:BAAALgAECgIJAgAAAA==.Harrin:BAABLgAECn8bAAIEAAcJ9g9FdABSAQAEAAcJ9g9FdABSAQAAAA==.',
He='Healingwater:BAAALgAECgIJAwAAAA==.Herracles:BAAALgADCgYJCQAAAA==.Hezrel:BAAALgAECgYJCgAAAA==.',
Hi='Hierodule:BAAALgAECgEJAQAAAA==.Hiimriven:BAAALgAECgIJAgABLgAECgYJFgATAFkhAA==.Hinal:BAABLgAECn8YAAIHAAgJ1hskLQADAgAHAAgJ1hskLQADAgAAAA==.',
Ho='Hojo:BAAALgADCgUJCAAAAA==.Holyenabler:BAABLgAFFH8FAAIYAAMJCwecCQCHAAAYAAMJCwecCQCHAAAAAA==.Hootiehoo:BAAALgADCgMJAwAAAA==.',
Hu='Huflunggoo:BAAALgADCgkJDQAAAA==.Huflungpoop:BAABLgAECn8wAAIGAAgJVhoQEAD6AQAGAAgJVhoQEAD6AQAAAA==.Hunterborn:BAAALgAFFAIJAgAAAA==.',
Hy='Hypercube:BAAALgADCggJDwAAAA==.',
['Hè']='Hèalz:BAAALgADCgcJCQABLgAECgkJHgAPAIAZAA==.',
Ic='Ickixia:BAAALgADCgQJBAAAAA==.',
Il='Ilkaressa:BAAALgADCgQJBAAAAA==.Illyríá:BAEALgAFFAIJAgABLgAECggJHgABAJwYAA==.Ilun:BAAALgAECgEJAQAAAA==.',
Im='Imcruel:BAACLgAFFH8RAAIEAAUJCh6sFwBrAQAEAAUJCh6sFwBrAQAuAAQKfyoAAgQACQmvJSgHAB0DAAQACQmvJSgHAB0DAAAA.',
In='Ink:BAACLgAFFH8KAAIEAAQJCg81PQBAAQAEAAQJCg81PQBAAQAuAAQKfyUAAgQABwm2IC08AOcBAAQABwm2IC08AOcBAAAA.',
Is='Istaria:BAAALgAECgEJAQAAAA==.Isujr:BAABLgAECn8ZAAIOAAcJ8hIKcQCmAQAOAAcJ8hIKcQCmAQAAAA==.',
Ja='Jacaerys:BAAALgADCgYJBgAAAA==.Jackiegan:BAABLgAECn8bAAMDAAkJ3R2MBQCxAgADAAkJ3R2MBQCxAgAFAAEJJgcffAAeAAAAAA==.Jackson:BAAALgAECgEJAQAAAA==.Jagerdemon:BAAALgAECgcJBwAAAA==.',
Je='Jerce:BAAALgADCgUJBQAAAA==.',
Jh='Jhala:BAAALgADCgcJCAAAAA==.',
Jo='Joshcalc:BAAALgAECgYJBwAAAA==.Joskel:BAABLgAECn8oAAMCAAgJdQy7VQBcAQACAAgJdQy7VQBcAQAgAAYJMQToFgDIAAAAAA==.',
Ju='Juacqer:BAAALgAECgEJAQAAAA==.',
Ka='Kaant:BAABLgAECn8qAAMdAAgJ/xmlEwD7AQAdAAgJ/xmlEwD7AQAIAAcJSxVNNgB5AQAAAA==.Kaeni:BAAALgADCgMJAwAAAA==.Kaidevyn:BAABLgAECn8iAAMXAAcJEBH5BwByAQAXAAcJEBH5BwByAQAOAAQJWgr7xwCaAAAAAA==.Kaiste:BAAALgADCgEJAQAAAA==.Kaleine:BAAALgAECgIJAgAAAA==.Kardren:BAAALgAECgUJCgAAAA==.',
Ke='Keiko:BAAALgAECggJDQAAAA==.Keiran:BAABLgAECn8wAAMNAAgJpCO9CADVAgANAAgJpCO9CADVAgALAAgJpRzPEgCgAgAAAA==.Kelazurin:BAAALgADCgEJAQAAAA==.Kellistair:BAAALgADCgYJBgAAAA==.Keläo:BAAALgADCgUJCQAAAA==.Keyadish:BAAALgADCgYJDQAAAA==.Keys:BAABLgAECn8mAAITAAgJEx65EACcAgATAAgJEx65EACcAgAAAA==.',
Kh='Khalnerys:BAABLgAECn8iAAMaAAgJcgl5MgASAQAaAAgJJgh5MgASAQAQAAUJwQfAEAC3AAAAAA==.Khoulock:BAACLgAFFH8PAAICAAUJIBffGQAjAQACAAUJIBffGQAjAQAuAAQKfzUABAIACQnJICwIAOgCAAIACQm6ICwIAOgCACAABQliIloKAEsBAAEAAwl9ENU+ALkAAAAA.',
Ki='Kimmi:BAAALgAECggJCgAAAA==.Kimmispally:BAAALgAECgIJAwAAAA==.Kiro:BAAALgADCgQJBQAAAA==.',
Kn='Knowimsayin:BAAALgAECgEJAQAAAA==.',
Ko='Kotateal:BAAALgAECgYJCwAAAA==.',
Kr='Kruelshot:BAABLgAECn8VAAMNAAgJxSSfBwDkAgANAAgJxSSfBwDkAgALAAcJahIAMgCoAQABLgAFFAUJEQAEAAoeAA==.Krux:BAAALgAECgEJAQAAAA==.',
Kt='Kthxbye:BAAALgAECgUJBwABLgAECgcJBwAKAAAAAA==.',
Ku='Kumcookies:BAAALgADCgEJAQAAAA==.Kungfuprissy:BAAALgAECgMJBwAAAA==.Kuraishin:BAACLgAFFH8MAAIfAAIJ8hUeCQCzAAAfAAIJ8hUeCQCzAAAuAAQKf2AAAx8ABwmVIpoEAF4CAB8ABwmVIpoEAF4CACEABAmbHRQaAN4AAAEuAAUUBAkSAA4A4gsA.Kuroakuma:BAAALgAECgYJEAAAAA==.Kuvara:BAAALgADCgkJCgAAAA==.',
Kv='Kvnnp:BAAALgADCgYJBgAAAA==.Kvnpro:BAAALgADCgUJBwAAAA==.Kvnxx:BAAALgADCgUJBQAAAA==.',
Kw='Kwandashadow:BAAALgAECgUJDQAAAA==.',
Ky='Kylemonk:BAAALgADCgEJAQAAAA==.',
['Ké']='Kéres:BAAALgADCgkJEAAAAA==.',
La='Lagspike:BAABLgAECn8dAAIEAAgJpxVQcwBUAQAEAAgJpxVQcwBUAQAAAA==.Latheal:BAAALgADCggJEwAAAA==.Lavi:BAABLgAECn8dAAIHAAgJDA6gXgBqAQAHAAgJDA6gXgBqAQAAAA==.',
Lb='Lbk:BAAALgADCgIJAgAAAA==.',
Le='Lejeune:BAAALgAECgEJAQAAAA==.Lengex:BAAALgAECgcJCQAAAA==.Lero:BAABLgAECn8iAAIDAAkJuCHkAgD8AgADAAkJuCHkAgD8AgAAAA==.Lerwindion:BAABLgAECn8fAAIZAAgJOR+VCQCiAgAZAAgJOR+VCQCiAgAAAA==.Lescaryn:BAAALgADCgIJAgAAAA==.Lexoh:BAAALgAECgYJEgAAAA==.',
Li='Lilani:BAAALgADCgQJBAAAAA==.Lindir:BAACLgAFFH8JAAIMAAMJlBtCEQAGAQAMAAMJlBtCEQAGAQAuAAQKfygAAgwACAk8JKkBAD8DAAwACAk8JKkBAD8DAAAA.Lionelle:BAAALgAECgYJDgAAAA==.Liquor:BAACLgAFFH8NAAISAAQJNBZBIQBDAQASAAQJNBZBIQBDAQAuAAQKf0EAAxIACQl9IUMHAOgCABIACQl9IUMHAOgCACIAAwnPFAEXAJ8AAAAA.Liquorish:BAAALgADCgEJAQABLgAFFAQJDQASADQWAA==.Lirathiel:BAAALgAECgMJCAAAAA==.Litasfk:BAAALgAECgIJAgAAAA==.Liuni:BAABLgAECn8iAAIDAAgJ0RR+HgB0AQADAAgJ0RR+HgB0AQAAAA==.Liyin:BAAALgAECgQJCQABLgAECgkJIwAEALMMAA==.',
Lo='Lobopeste:BAABLgAECn8qAAIWAAgJ3gd9IQDxAAAWAAgJ3gd9IQDxAAAAAA==.Locknutz:BAAALgADCgMJAwAAAA==.Loracy:BAAALgADCgcJBwAAAA==.Lorelynn:BAABLgAECn8iAAICAAgJ7w0FUABsAQACAAgJ7w0FUABsAQAAAA==.',
Lu='Luci:BAABLgAECn8XAAQSAAgJ6RLJOACXAQASAAgJkxLJOACXAQAiAAMJ1Q7kIABJAAAjAAEJAAA8WwAAAAABLgAECggJHQADAIcUAA==.Lucìan:BAABLgAECn8lAAIVAAgJhyH6BwD9AgAVAAgJhyH6BwD9AgAAAA==.Ludociel:BAAALgAECgQJBAAAAA==.Lunaclair:BAACLgAFFH8SAAIOAAQJ4gvnRQAsAQAOAAQJ4gvnRQAsAQAuAAQKf0kAAw4ACAnNHBMoABoCAA4ACAnNHBMoABoCABYAAglRBv9CAD4AAAAA.Lunadrus:BAABLgAECn8dAAIEAAcJPgp/lgASAQAEAAcJPgp/lgASAQAAAA==.Lunarielle:BAACLgAFFH8KAAINAAMJiA6LOADkAAANAAMJiA6LOADkAAAuAAQKfx4AAg0ACAkXHMYVAIkCAA0ACAkXHMYVAIkCAAAA.',
Ly='Lyriaa:BAAALgADCgYJCwAAAA==.',
Ma='Macfly:BAABLgAECn8oAAINAAgJMhl4LwDMAQANAAgJMhl4LwDMAQAAAA==.Madmeatballs:BAAALgAECgEJAQABLgAECgkJKAAEAAMfAA==.Magicmissile:BAACLgAFFH8HAAIEAAIJpAtOdgCeAAAEAAIJpAtOdgCeAAAuAAQKfyEAAgQACAnSHL8vABgCAAQACAnSHL8vABgCAAAA.Makgora:BAAALgAECgMJBAABLgAECgYJFgATAFkhAA==.Makhvan:BAAALgAECgQJCgAAAA==.Maksoon:BAAALgAECgUJDAAAAA==.Maladjusted:BAAALgAECgMJBAAAAA==.Maléfique:BAAALgADCgkJEAAAAA==.Mancath:BAAALgAECgkJCwAAAA==.Maplè:BAAALgAECgIJAwABLgAECggJHgAIAKMTAA==.Mar:BAAALgADCgMJAwAAAA==.Marlei:BAAALgADCgQJBAABLgAECgkJIwAEALMMAA==.Marqose:BAAALgADCgYJCgAAAA==.Matan:BAAALgADCgUJBQAAAA==.',
Me='Meeko:BAAALgAFFAEJAQABLgAFFAcJEAAbAO4aAA==.Melfie:BAAALgAECgcJEgAAAA==.Meliadoul:BAABLgAECn8VAAIEAAcJuAvokAAcAQAEAAcJuAvokAAcAQAAAA==.Mellyndra:BAABLgAECn8qAAIJAAgJ6R5zDQBxAgAJAAgJ6R5zDQBxAgAAAA==.Mercüry:BAAALgAECgEJAwAAAA==.Mezhren:BAAALgAECgYJCwAAAA==.',
Mh='Mhoramsgirl:BAAALgADCggJCwAAAA==.',
Mi='Midoriya:BAABLgAECn8jAAMGAAkJZxEHHwBjAQAGAAgJLxIHHwBjAQAFAAUJkBGGTgCSAAAAAA==.Mistjack:BAABLgAFFH8KAAIFAAUJsRDDEABWAQAFAAUJsRDDEABWAQAAAA==.',
Mo='Momdad:BAACLgAFFH8NAAIMAAQJPxYxCgBQAQAMAAQJPxYxCgBQAQAuAAQKfzQAAgwACQnUIGkDAM8CAAwACQnUIGkDAM8CAAAA.Mongaux:BAAALgADCgQJBQAAAA==.Monkey:BAAALgAECgQJCgAAAA==.Morrígán:BAAALgADCgUJBQAAAA==.Moxi:BAAALgADCggJDQAAAA==.',
Mu='Muamman:BAAALgAECgMJAwAAAA==.Murda:BAAALgADCgYJCgAAAA==.Murphysflaw:BAAALgADCgUJCAAAAA==.Mutegen:BAAALgAFFAEJAQAAAA==.',
Mx='Mxhealeryduf:BAAALgAECgIJAgAAAA==.',
My='Mystallian:BAAALgAECgIJAgAAAA==.Mystí:BAEALgAECgkJBgABLgAECggJHgABAJwYAA==.Mythicplus:BAAALgAECgcJDgAAAA==.',
['Mé']='Mémnoc:BAAALgAECgMJAwAAAA==.',
Na='Nadarien:BAAALgAECgYJDQAAAA==.Nadyia:BAAALgADCgEJAQAAAA==.Nailah:BAAALgADCgcJCwAAAA==.Nannergoat:BAAALgADCgMJAwAAAA==.Nastymikey:BAABLgAECn8bAAIkAAgJNx13BwBzAgAkAAgJNx13BwBzAgAAAA==.Nazdormu:BAABLgAECn8ZAAIbAAYJ3AJ7HwCwAAAbAAYJ3AJ7HwCwAAAAAA==.',
Ne='Nefarious:BAAALgAECgcJCAAAAA==.Neisen:BAABLgAECn8eAAMJAAgJtRWpKQByAQAJAAcJxxSpKQByAQAHAAUJBwKc+gCeAAAAAA==.Neptune:BAAALgADCgYJBgAAAA==.',
No='Norna:BAAALgADCgcJDwAAAA==.Noz:BAAALgADCgkJCQAAAA==.',
Nu='Nufonewhodis:BAABLgAECn8WAAITAAYJWSF1HQATAgATAAYJWSF1HQATAgAAAA==.',
Ny='Nykolas:BAAALgADCgkJDAAAAA==.Nymofthedead:BAABLgAECn8fAAMOAAcJjSSdJAArAgAOAAcJjSSdJAArAgAXAAIJ+x/yHABTAAAAAA==.',
Oa='Oakgrove:BAAALgADCgQJBAAAAA==.',
Om='Ombraless:BAAALgADCgMJAwABLgAECgQJCAAKAAAAAA==.',
On='Oneforall:BAAALgAECgkJCwAAAA==.',
Op='Ophrizhani:BAAALgAECgMJAwAAAA==.',
Or='Orangegrove:BAAALgAECgMJAwAAAA==.Orpheal:BAAALgAECgUJBQAAAA==.Orphen:BAAALgADCgcJDQAAAA==.',
Pa='Paddleball:BAAALgADCgQJBAAAAA==.Paladouin:BAAALgAECgYJEwAAAA==.Pandammy:BAAALgAECgkJAgAAAA==.Pantro:BAAALgAECgYJEwAAAA==.Papalion:BAAALgAECgQJDAAAAA==.Paragas:BAAALgADCgkJEAAAAA==.Pawbs:BAAALgAECgQJDgAAAA==.',
Pe='Peanuts:BAAALgADCgcJBwAAAA==.Peoplehugger:BAAALgADCgMJAwAAAA==.',
Pi='Pickleburger:BAAALgAECgEJAQAAAA==.Pinklilydrd:BAAALgAECgEJAQAAAA==.',
Pl='Plaindonut:BAAALgAECgcJEwAAAA==.',
Pr='Priestdrago:BAAALgADCgUJBQAAAA==.Prissidebow:BAAALgAECgEJAQAAAA==.',
Qu='Quartz:BAAALgAECgEJAQABLgAFFAMJCgAPACIkAA==.',
Ra='Rahzule:BAAALgADCgYJBwAAAA==.Ralynne:BAABLgAECn8pAAIdAAgJPBJmIACKAQAdAAgJPBJmIACKAQAAAA==.Ravenbrook:BAACLgAFFH8QAAIPAAQJBSbnAgDCAQAPAAQJBSbnAgDCAQAuAAQKfyMAAw8ACAlbJXsEAGIDAA8ACAlbJXsEAGIDABQAAQkwIIdCAFQAAAAA.Rawrr:BAABLgAECn8ZAAIjAAYJqQlsJgDeAAAjAAYJqQlsJgDeAAAAAA==.Raxie:BAACLgAFFH8OAAMZAAQJLRSxFQA2AQAZAAQJLRSxFQA2AQAlAAEJBQ3SFABRAAAuAAQKfyoABBkACAl6Gz0MAFQCABkACAl6Gz0MAFQCACUABwm2EGIlAEkBABEAAQkBBPGHACgAAAAA.Razeth:BAABLgAECn8VAAIMAAYJ8BYyIABKAQAMAAYJ8BYyIABKAQAAAA==.',
Re='Reanne:BAAALgAECgYJEAAAAA==.Res:BAAALgAECgYJCwAAAA==.Rescorla:BAAALgAECgkJDAAAAA==.Rethali:BAAALgADCgQJAgAAAA==.Rezr:BAAALgAECggJDgAAAA==.',
Rh='Rhixa:BAAALgADCgUJBQAAAA==.Rhymunky:BAAALgAECgQJBwAAAA==.',
Ri='Rifthor:BAAALgAECgYJDwAAAA==.Rillx:BAAALgADCgQJBgAAAA==.Ripmxi:BAABLgAECn8qAAIEAAgJphHRXwCAAQAEAAgJphHRXwCAAQAAAA==.',
Ro='Robinski:BAAALgADCgEJAQAAAA==.Robotiss:BAAALgADCgIJAgAAAA==.Rocco:BAAALgADCgYJBwAAAA==.Rodevon:BAAALgADCggJCAAAAA==.Roknasaurus:BAAALgADCgUJCAAAAA==.Romani:BAAALgADCgYJBgAAAA==.Romeo:BAAALgADCgMJAwAAAA==.Ronaldreagnt:BAAALgAECgcJDAAAAA==.',
Ru='Runelight:BAABLgAECn8UAAQZAAcJ5wmmKwAaAQAZAAYJ1AqmKwAaAQARAAUJgAl1OADNAAAlAAMJDQWbTwBpAAAAAA==.Rupertgiless:BAACLgAFFH8KAAICAAQJ1g7vNwAfAQACAAQJ1g7vNwAfAQAuAAQKfyQAAgIACQloGn0iAIsCAAIACQloGn0iAIsCAAAA.',
Sa='Sabeckya:BAAALgAECgQJCgAAAA==.Sacksmasher:BAAALgADCgcJDwAAAA==.Sampleshrimp:BAAALgADCgEJAgAAAA==.Saphyla:BAAALgADCgcJCwAAAA==.Sarcastyx:BAAALgAECgYJBwAAAA==.Sarrod:BAAALgADCgUJBQAAAA==.Saxines:BAAALgAECgYJEQAAAA==.',
Sc='Scaliefox:BAAALgAECgIJAgABLgAECggJKgAJAOkeAA==.Scarl:BAAALgADCgUJBQAAAA==.Schwarznacht:BAAALgADCgUJBQAAAA==.Schwarzwölf:BAAALgADCgYJCwAAAA==.Scoots:BAAALgADCgQJBAAAAA==.Scrubs:BAAALgAECgYJDAAAAA==.Scrubsevoker:BAAALgADCgcJDwAAAA==.Scumbum:BAAALgADCgIJAgAAAA==.Scyllo:BAAALgAECgQJBAAAAA==.',
Se='Seekndestroy:BAAALgAECgQJBwAAAA==.Selige:BAAALgAECgQJBAAAAA==.',
Sg='Sgtcuunt:BAAALgADCgQJBAAAAA==.',
Sh='Shaenicor:BAAALgADCgIJAgAAAA==.Shelbo:BAAALgADCgcJEAAAAA==.Shortshammy:BAAALgAECgEJAQABLgAFFAMJCwAEACUJAA==.Shror:BAAALgADCgEJAQABLgAECgUJBQAKAAAAAA==.',
Si='Sicarune:BAAALgAECgEJAQAAAA==.Siiegrand:BAABLgAECn8VAAIYAAcJgxDHGgDrAAAYAAcJgxDHGgDrAAAAAA==.Silentswag:BAAALgAECgQJCAAAAA==.Sindrane:BAAALgADCgIJAwABLgAECgkJLQAOAKYUAA==.Sitzho:BAAALgADCgUJCAAAAA==.',
Sk='Skeleton:BAAALgAECgIJAgAAAA==.Skybringer:BAABLgAECn8jAAIHAAYJFAxHkwABAQAHAAYJFAxHkwABAQAAAA==.Skyee:BAABLgAECn8oAAMGAAkJAh0LDAC6AgAGAAkJAh0LDAC6AgAFAAMJGxQ7SgClAAAAAA==.Skylos:BAAALgAECgEJAgAAAA==.',
Sm='Smexibiotch:BAAALgADCgYJBgAAAA==.',
So='Soapscum:BAAALgADCgQJBAAAAA==.Soarphium:BAAALgAECgIJAgABLgAFFAUJFQATAD8SAA==.Solararc:BAAALgADCgEJAgAAAA==.Soleana:BAAALgAECgYJBQAAAA==.Sonicast:BAAALgAECgYJCQAAAA==.Sooie:BAAALgAECgYJEgAAAA==.Soramian:BAAALgADCgcJEgAAAA==.Soulcacher:BAABLgAECn8tAAMOAAkJphShSwAQAgAOAAgJIhahSwAQAgAWAAcJrQ6vFwBOAQAAAA==.Soxxy:BAAALgAECgEJAQABLgAECggJHQADAIcUAA==.',
Sp='Spellgunner:BAABLgAECn8VAAIEAAgJPxsMQADaAQAEAAgJPxsMQADaAQAAAA==.',
St='Stormwulf:BAAALgADCgUJBQABLgAECgMJBAAKAAAAAA==.Strombjorn:BAABLgAECn8eAAIIAAgJoxPfWAAlAQAIAAgJoxPfWAAlAQAAAA==.',
['Sø']='Sølaria:BAAALgAECgEJAQAAAA==.',
Ta='Tasireth:BAAALgADCgcJBwAAAA==.',
Te='Tessi:BAABLgAECn8UAAIEAAYJNRGjggA2AQAEAAYJNRGjggA2AQAAAA==.',
Th='Thalrian:BAAALgAECgQJBQABLgAECggJNgAPAOEjAA==.Thefailnym:BAAALgAECggJCAAAAA==.Theylive:BAAALgAECggJDwAAAA==.Thondrin:BAAALgAECgYJCgAAAA==.Thordanil:BAAALgAECgEJAQAAAA==.Thrashedass:BAAALgADCgEJAQAAAA==.',
Ti='Tigerlilliy:BAAALgADCgYJEAAAAA==.Tim:BAAALgADCgkJEQAAAA==.Timerek:BAAALgADCgIJAgAAAA==.',
To='Toawulf:BAAALgAECgMJAwABLgAECgMJBAAKAAAAAA==.Toya:BAABLgAECn8qAAITAAgJtRvrDwDfAQATAAgJtRvrDwDfAQAAAA==.',
Tr='Trenazen:BAAALgADCgkJCgAAAA==.Trevain:BAAALgAECgEJAQAAAA==.Trimasdrood:BAAALgADCgMJAwAAAA==.Trivia:BAAALgADCgYJFwAAAA==.Trundle:BAAALgAECgEJAgAAAA==.Truthordare:BAABLgAECn8gAAIBAAYJzAmyEwDNAAABAAYJzAmyEwDNAAAAAA==.',
Tu='Turtei:BAAALgAECgEJAQABLgAFFAYJHgAGAMcjAA==.Turtl:BAACLgAFFH8eAAIGAAYJxyO0AAAsAgAGAAYJxyO0AAAsAgAuAAQKfysAAgYACQnmJjQAAIoDAAYACQnmJjQAAIoDAAAA.',
Tw='Twohoof:BAAALgADCgEJAQAAAA==.',
Tx='Txìewtkuä:BAAALgADCgkJCQAAAA==.',
Ty='Tyryn:BAAALgADCgMJBAAAAA==.',
Ug='Uglydragon:BAAALgAECgcJDAAAAA==.Uglypally:BAAALgADCgkJCQAAAA==.Uglypetguy:BAAALgAECgIJAgAAAA==.Uglyrogue:BAAALgAECgQJAgAAAA==.Uglyshaman:BAAALgAECgEJAgAAAA==.',
Ul='Ulgrym:BAAALgAECgEJAQAAAA==.Ultimatia:BAAALgADCgMJBwAAAA==.',
Un='Unbalancéd:BAAALgAECgQJCQAAAA==.',
Va='Vahra:BAAALgAECgEJAQAAAA==.Valanther:BAAALgAECgMJAwAAAA==.Valantis:BAAALgADCgEJAQAAAA==.Valgaskav:BAABLgAECn8eAAIHAAgJfiI5IQA9AgAHAAgJfiI5IQA9AgAAAA==.Valimond:BAAALgAECgEJAQABLgAECgMJBAAKAAAAAA==.Valric:BAAALgADCgYJBwAAAA==.Vanarrath:BAAALgADCgYJBwAAAA==.Vandryelle:BAAALgADCgIJAgAAAA==.Varge:BAAALgADCgMJAwAAAA==.Varrathos:BAAALgADCgkJEgAAAA==.Vayl:BAAALgAECgMJAwAAAA==.',
Ve='Velisa:BAAALgADCgYJBgAAAA==.Ventrue:BAAALgADCgMJAwAAAA==.Verdesoul:BAAALgAECgQJBgAAAA==.Vesyra:BAAALgAECgQJBQAAAA==.',
Vi='Viralyn:BAAALgADCgMJAwABLgAECggJIgADANEUAA==.Vixøn:BAAALgAECgIJAgAAAA==.',
Vo='Voidluck:BAABLgAECn8SAAISAAgJuhBkdABIAQASAAgJuhBkdABIAQAAAA==.Voker:BAAALgAECgIJBgABLgAECgQJDgAKAAAAAA==.Voladis:BAAALgAECgYJBwAAAA==.Voladro:BAAALgAECgQJBAAAAA==.Volos:BAABLgAECn8jAAIHAAgJORaSOgDQAQAHAAgJORaSOgDQAQAAAA==.Vordaman:BAABLgAECn8nAAIOAAgJFhXYUQCGAQAOAAgJFhXYUQCGAQAAAA==.',
Vy='Vynír:BAACLgAFFH8VAAICAAUJex+9DgBoAQACAAUJex+9DgBoAQAuAAQKfy0AAwIACQmfI98EABgDAAIACQk8I98EABgDAAEABQkHI40NAOwBAAAA.',
Wa='Waghoba:BAECLgAFFH8bAAIfAAYJiBieAADOAQAfAAYJiBieAADOAQAuAAQKfyAAAh8ACAkkIScGAJwCAB8ACAkkIScGAJwCAAAA.Waito:BAAALgAECgQJBwAAAA==.Wandä:BAABLgAECn8dAAQDAAgJ2Ro/EQDxAQADAAgJHBk/EQDxAQAGAAgJrREsGgCOAQAFAAEJtQ7PbwAsAAAAAA==.Wardriccan:BAAALgAECgUJCwAAAA==.Warfle:BAAALgADCgYJBgAAAA==.Warrionomous:BAACLgAFFH8FAAIPAAIJuAhkLgCKAAAPAAIJuAhkLgCKAAAuAAQKfxkAAg8ACAkDG2kQACsCAA8ACAkDG2kQACsCAAEuAAUUAgkHAAQApAsA.Washu:BAABLgAECn8sAAMjAAgJjx2MCgAgAgAjAAgJjx2MCgAgAgAiAAMJTAtZIQB5AAAAAA==.',
Wh='Whimlock:BAAALgADCgQJBAABLgAFFAIJBQAEAMQYAA==.Whims:BAAALgAECgYJCAABLgAFFAIJBQAEAMQYAA==.Whimzie:BAAALgAECgEJAQABLgAFFAIJBQAEAMQYAA==.Whorphium:BAAALgAECggJEgABLgAFFAUJFQATAD8SAA==.',
Wi='Willow:BAAALgAECgYJCwAAAA==.Winterous:BAAALgAECgEJAQAAAA==.',
Wo='Wonderbread:BAABLgAECn8pAAIHAAgJLxJhXQDLAQAHAAgJLxJhXQDLAQAAAA==.',
Wr='Wrager:BAAALgAECgUJBgAAAA==.Wrathofzaun:BAAALgAECgYJDwAAAA==.',
Wy='Wylest:BAAALgADCgcJBwAAAA==.Wynch:BAAALgAECgkJCAAAAA==.',
['Wâ']='Wârwôlf:BAABLgAECn8hAAMNAAkJCyO2BAASAwANAAkJCyO2BAASAwALAAQJ+BWyVQDzAAAAAA==.',
Xe='Xenan:BAABLgAECn8mAAIHAAgJGQ1mZgBXAQAHAAgJGQ1mZgBXAQAAAA==.',
Xt='Xtrolldinary:BAAALgAECgQJDgAAAA==.',
Xv='Xvp:BAAALgAECgQJCgAAAA==.',
Xy='Xylophy:BAABLgAECn8kAAIiAAcJyBNsCwBOAQAiAAcJyBNsCwBOAQAAAA==.',
Ye='Yeastmode:BAACLgAFFH8NAAINAAQJtgv0JQAlAQANAAQJtgv0JQAlAQAuAAQKfycAAg0ACAkVHXoVAF0CAA0ACAkVHXoVAF0CAAAA.',
Yo='Yonah:BAAALgAECgYJDAAAAA==.',
Yu='Yurc:BAABLgAECn8cAAIcAAcJ4hcZEQCGAQAcAAcJ4hcZEQCGAQAAAA==.',
Za='Zademan:BAAALgAECgUJBwAAAA==.Zappyu:BAAALgAECgkJBQABLgAECgkJCAAKAAAAAA==.',
Ze='Zeebra:BAAALgAECgMJBAAAAA==.Zeg:BAAALgAECgQJBAAAAA==.Zega:BAAALgAECgEJAQAAAA==.Zegafur:BAABLgAECn8qAAIVAAgJ/BsRHgANAgAVAAgJ/BsRHgANAgAAAA==.Zeolite:BAAALgADCgEJAQAAAA==.Zeruk:BAABLgAECn8XAAMGAAcJjwJ1YACOAAAGAAYJlAJ1YACOAAAFAAcJpAGqVQB0AAAAAA==.',
Zi='Zillionbúcks:BAACLgAFFH8YAAIHAAYJ+hLmBQCRAQAHAAYJ+hLmBQCRAQAuAAQKfxoAAgcACQn+HdEtAGwCAAcACQn+HdEtAGwCAAAA.',
Zy='Zylcat:BAAALgAECgYJCQAAAA==.',
['Zê']='Zêddicus:BAABLgAECn8sAAMBAAgJ6B5TAgBPAgABAAgJ6B5TAgBPAgACAAUJHwgM1ACyAAAAAA==.',
['Áq']='Áquafina:BAABLgAECn8zAAIEAAkJwQxKRwDCAQAEAAkJwQxKRwDCAQAAAA==.',
['Îv']='Îvan:BAAALgADCggJCAAAAA==.',
['Ðö']='Ðö:BAABLgAECn8eAAIPAAkJgBmPEAAqAgAPAAkJgBmPEAAqAgAAAA==.',
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
