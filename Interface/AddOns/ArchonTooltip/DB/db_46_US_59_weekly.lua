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

local lookup = {'Warlock-Affliction','Warlock-Demonology','Druid-Restoration','Mage-Frost','Hunter-BeastMastery','Unknown-Unknown','Paladin-Retribution','Druid-Balance','Warrior-Protection','Warrior-Fury','DemonHunter-Devourer','Monk-Mistweaver','Warrior-Arms','DeathKnight-Unholy','Shaman-Elemental','Shaman-Restoration','Paladin-Holy','Paladin-Protection','Priest-Discipline','Priest-Shadow','Shaman-Enhancement','Warlock-Destruction','Monk-Brewmaster','Monk-Windwalker','Hunter-Survival','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Rogue-Assassination','Rogue-Subtlety','Druid-Feral','Priest-Holy','DeathKnight-Blood','DeathKnight-Frost','DemonHunter-Vengeance','DemonHunter-Havoc','Hunter-Marksmanship','Mage-Arcane','Druid-Guardian',}
local provider = {region='US',realm='DarkIron',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aanx:BAABLgAECn8ZAAMBAAYJth1AGgDnAAACAAYJth1EgQA2AQABAAQJQhlAGgDnAAAAAA==.',
Ab='Abadon:BAAALgAECgQJBgABLgAFFAEJBgADAEcUAA==.Abdorei:BAACLgAFFH8JAAIEAAQJIQdOewDnAAAEAAQJIQdOewDnAAAuAAQKfz4AAgQACQnkF041AEECAAQACQnkF041AEECAAAA.Absorboat:BAAALgADCgYJCAAAAA==.',
Ac='Accilatem:BAABLgAECn8aAAIFAAcJQh4nHgBRAgAFAAcJQh4nHgBRAgABLgAECgkJIgAEAHIZAA==.Accilatim:BAABLgAECn8iAAIEAAkJchkILwBaAgAEAAkJchkILwBaAgAAAA==.',
Ad='Adonsina:BAAALgAECgEJAQABLgAECgkJCwAGAAAAAA==.',
Ae='Aether:BAAALgAECgMJAwAAAA==.',
Ag='Agrromagnet:BAABLgAECn8oAAIHAAkJahhVNgBJAgAHAAkJahhVNgBJAgAAAA==.',
Ai='Aiba:BAABLgAECn8aAAIIAAgJABj5HADdAQAIAAgJABj5HADdAQAAAA==.',
Ak='Akcloud:BAABLgAFFH8MAAMJAAQJzBuLEgALAQAJAAQJSBiLEgALAQAKAAEJ2yPTHQBoAAAAAA==.',
Al='Alab:BAAALgAECgIJBAABLgAECggJHgALAFAYAA==.Alaeris:BAACLgAFFH8QAAIMAAQJNhh9KAAcAQAMAAQJNhh9KAAcAQAuAAQKfyIAAgwACQlaHesMAMcCAAwACQlaHesMAMcCAAAA.Albetabeef:BAACLgAFFH8JAAMNAAQJGxTEGAAYAQANAAQJGxTEGAAYAQAKAAIJJgZQHACUAAAuAAQKfxgAAw0ACAn/IEcKAEMCAAoABwk2ICAWAJwCAA0ABwmjIkcKAEMCAAAA.Alexei:BAABLgAECn8bAAIOAAcJXgdFtQAKAQAOAAcJXgdFtQAKAQAAAA==.Aleyeah:BAAALgAECgYJDgABLgAECggJNwAPAPsgAA==.Allhopeisded:BAABLgAECn8VAAIQAAYJaRD2YwAqAQAQAAYJaRD2YwAqAQAAAA==.Alurelor:BAAALgAECgkJDwAAAA==.Alyreu:BAAALgAECgQJBAABLgAECgYJDQAGAAAAAA==.',
Am='Amanita:BAAALgADCgkJCQAAAA==.Amarah:BAAALgADCgYJBgAAAA==.Amelaista:BAABLgAECn89AAIQAAkJ2QwGRACZAQAQAAkJ2QwGRACZAQAAAA==.',
An='Anddi:BAAALgAECgEJAwAAAA==.Andii:BAACLgAFFH8IAAIRAAQJXhmqHgAhAQARAAQJXhmqHgAhAQAuAAQKfxgABBEACAnIF38/AHoBABEABwnQFn8/AHoBAAcAAgm2B0KnASoAABIAAQkAAGBgAAAAAAAA.Andy:BAACLgAFFH8FAAITAAMJHgpYNAC0AAATAAMJHgpYNAC0AAAuAAQKfxQAAxMACAkoH2ALALcCABMACAkoH2ALALcCABQAAQkXB+OMACsAAAAA.Angusbeef:BAAALgAECgcJBwAAAA==.Antipus:BAAALgAECgQJBQAAAA==.',
Ao='Aoibhoker:BAAALgAECgQJBAABLgAECgkJMgAVAIoiAA==.',
Ar='Arclo:BAAALgADCgYJBgAAAA==.Arden:BAAALgAECgQJBAABLgAECgYJFwAWANsWAA==.Ardeno:BAABLgAECn8XAAMWAAYJ2xarIwA7AQAWAAYJbwyrIwA7AQACAAUJ2xbLnAAEAQAAAA==.Ardon:BAABLgAECn8sAAMQAAkJ8hp3EwCtAgAQAAkJ8hp3EwCtAgAPAAUJvhsbMQCaAQAAAA==.Armis:BAAALgADCgUJBQAAAA==.',
As='Asteruis:BAABLgAECn8kAAIFAAkJDh57KgAvAgAFAAkJDh57KgAvAgAAAA==.',
Av='Avenayra:BAAALgAECgIJAwAAAA==.',
Ay='Ayroon:BAAALgAECgEJAQAAAA==.',
Ba='Baddhealer:BAAALgADCgUJBQAAAA==.Badfurion:BAAALgADCggJCgAAAA==.Balthamel:BAAALgAECgYJDAAAAA==.Bananafang:BAAALgAECgQJBgAAAA==.Bananashoes:BAAALgAECgQJAwAAAA==.Bangerz:BAACLgAFFH9AAAIRAAgJKhNMBwBBAgARAAgJKhNMBwBBAgAuAAQKfzwAAxEACQlmILMIAOMCABEACQlmILMIAOMCAAcAAQm4AedYASYAAAAA.Barkendremix:BAABLgAECn80AAMXAAkJYRsDDABzAgAXAAkJYRsDDABzAgAYAAEJFBW0kAA9AAAAAA==.Bathsheber:BAAALgAFFAEJAQABLgAFFAgJGQAEAK0iAA==.Baulbuster:BAAALgAECggJCgAAAA==.',
Be='Beanieweenie:BAAALgADCgEJAQAAAA==.Beerez:BAAALgADCgcJDQAAAA==.Belroy:BAABLgAECn8fAAIZAAYJKBMqLABCAQAZAAYJKBMqLABCAQAAAA==.Beriothien:BAAALgAECgEJAQAAAA==.',
Bj='Bjorum:BAACLgAFFH8LAAIVAAQJAR4MBgBYAQAVAAQJAR4MBgBYAQAuAAQKfyMAAxUACQmVImIGAHACABUACQmVImIGAHACAA8AAQnhCLaQACcAAAAA.',
Bo='Bodytwodafa:BAACLgAFFH8PAAMaAAQJgBW7BAAeAQAaAAQJNBK7BAAeAQAbAAMJaA9+RACxAAAuAAQKfyAABBoACAntIBgGAJUCABoACAkhHhgGAJUCABwABgn4GDgRALMBABsABwlwGNksAIcBAAAA.Bournemaad:BAAALgADCgMJAwAAAA==.Boyafu:BAAALgAECgEJAQAAAA==.',
Br='Brucecampbel:BAAALgAECgQJDAAAAA==.',
Bu='Bubbleyou:BAABLgAECn8ZAAMSAAYJZBDQKADNAAASAAYJZBDQKADNAAAHAAIJuwr/nwEsAAAAAA==.Burnek:BAAALgAECgIJBAABLgAECggJHgALAFAYAA==.',
Ca='Cantarella:BAABLgAECn8+AAMdAAkJzAhQDABlAQAdAAkJ9gdQDABlAQAeAAgJRAblKQBEAQAAAA==.Capy:BAAALgAFFAEJBAABLgAFFAUJEgAZAN8iAA==.Carlyle:BAABLgAECn81AAMHAAkJnR2EFwC0AgAHAAkJnR2EFwC0AgARAAUJlxXlPQBLAQAAAA==.Catdaddy:BAAALgADCgYJBwAAAA==.',
Ch='Checkmybio:BAAALgAECgQJBQAAAA==.Cheekyteetah:BAAALgAECgEJAQAAAA==.Cheesecake:BAAALgADCgUJBQAAAA==.Chromehound:BAAALgADCgQJBAAAAA==.Chumdungler:BAAALgAECgMJAwAAAA==.',
Ci='Cindervis:BAAALgADCgYJBgAAAA==.',
Cl='Clonk:BAAALgAECgUJBgAAAA==.',
Co='Collossuss:BAAALgAECgYJEwAAAA==.Convik:BAAALgAECgkJBwAAAA==.',
Cr='Cregga:BAAALgADCgEJAQAAAA==.Crimsonagony:BAAALgADCgUJBQAAAA==.Crosshairs:BAAALgADCgMJAwAAAA==.Crusible:BAAALgADCgEJAQAAAA==.',
Cu='Cuddles:BAAALgADCgUJBQAAAA==.Curacao:BAABLgAECn8YAAIKAAcJAhSIPABSAQAKAAcJAhSIPABSAQAAAA==.',
Cy='Cynnari:BAAALgAECgYJDQAAAA==.',
Da='Dabtime:BAABLgAECn8hAAIHAAgJJBPacgCWAQAHAAgJJBPacgCWAQAAAA==.Darkstarr:BAAALgAECgYJDwAAAA==.',
De='Deathknightm:BAAALgAECgIJAgABLgAECgkJHAAJAHYVAA==.Dekaar:BAABLgAECn8bAAIfAAYJuwnOJwDKAAAfAAYJuwnOJwDKAAAAAA==.Demonknight:BAAALgAECgEJAQAAAA==.Deracine:BAAALgAECgcJCgAAAA==.Derek:BAAALgAECggJDwAAAA==.Desdemonica:BAABLgAECn8dAAIFAAgJ6AjHcgBVAQAFAAgJ6AjHcgBVAQAAAA==.',
Di='Diegoknight:BAAALgADCgEJAgAAAA==.Diggle:BAAALgADCggJCAAAAA==.Dilvdrood:BAAALgADCgUJBQAAAA==.Dilvish:BAAALgAECgYJEgAAAA==.',
Do='Doctrwho:BAAALgAECgEJAQAAAA==.Dohaeris:BAABLgAECn8yAAIgAAkJ9xMVHQDYAQAgAAkJ9xMVHQDYAQAAAA==.Domain:BAABLgAECn8eAAILAAgJUBgQPgDMAQALAAgJUBgQPgDMAQAAAA==.Donfalprun:BAABLgAECn8gAAIHAAkJICNPDAABAwAHAAkJICNPDAABAwAAAA==.Doomstout:BAABLgAECn8WAAIEAAgJSBLFdwCGAQAEAAgJSBLFdwCGAQAAAA==.',
Dr='Draconus:BAABLgAECn8zAAMhAAkJfhXCEQDvAQAhAAkJUBPCEQDvAQAOAAQJcRsC6QDFAAAAAA==.Dralas:BAAALgAECggJDwAAAA==.Drkillenger:BAAALgAECgkJCQAAAA==.',
Du='Duro:BAAALgAECgYJDAABLgAECgYJDAAGAAAAAA==.Durto:BAAALgADCgMJAwABLgAECgQJCAAGAAAAAA==.Duskshade:BAAALgAECgUJCQAAAA==.',
['Dü']='Düsk:BAABLgAECn8VAAIOAAkJOQcldgB1AQAOAAkJOQcldgB1AQAAAA==.',
Ea='Eachan:BAAALgAECgMJAwAAAA==.',
El='Elij:BAACLgAFFH8JAAICAAQJYRjZQwA9AQACAAQJYRjZQwA9AQAuAAQKfx8AAgIACAmJHm8hAFsCAAIACAmJHm8hAFsCAAAA.Elufisti:BAAALgAECgEJBAAAAA==.Elunaire:BAACLgAFFH8GAAIDAAEJRxRUawA9AAADAAEJRxRUawA9AAAuAAQKfxwAAgMACQkCHJIdAFECAAMACQkCHJIdAFECAAAA.',
Em='Emelec:BAAALgAECgIJAgAAAA==.Emeraldwish:BAACLgAFFH8OAAMDAAQJliBzHQBlAQADAAQJliBzHQBlAQAIAAEJhA2iSABDAAAuAAQKfx0AAwMACAmlI2sGACUDAAMACAmlI2sGACUDAAgAAQkAALSsAAAAAAAA.',
Er='Eraline:BAAALgADCgYJBgAAAA==.Erthnite:BAAALgAECgYJBwAAAA==.',
Ev='Evinco:BAABLgAECn8aAAIWAAkJhBBJFAAIAQAWAAkJhBBJFAAIAQAAAA==.Evy:BAAALgAECgEJAgAAAA==.',
Ex='Executie:BAACLgAFFH8aAAMNAAgJbhGNBgDtAQANAAgJbhGNBgDtAQAKAAMJGQzSEgDvAAAuAAQKfyYAAw0ACQngG3gGAGQCAA0ACQnLGngGAGQCAAoABglLHFw1ANQBAAAA.Exev:BAAALgADCgQJBAAAAA==.',
Fa='Falin:BAAALgAECgEJAQAAAA==.Fancy:BAAALgAECgcJBwAAAA==.',
Fe='Fey:BAABLgAECn8iAAICAAkJ5BPsSgC5AQACAAkJ5BPsSgC5AQAAAA==.',
Fi='Fieryember:BAAALgAECgQJBQABLgAECggJHgALAFAYAA==.Fistvendor:BAABLgAECn8UAAIXAAkJxAiaKgBfAQAXAAkJxAiaKgBfAQAAAA==.',
Fl='Flasheals:BAABLgAECn8wAAIRAAkJLBO+IAD7AQARAAkJLBO+IAD7AQAAAA==.Flatpak:BAAALgADCgEJAgAAAA==.Flobglop:BAAALgAECgEJAQAAAA==.Fluffybum:BAAALgADCgEJAQAAAA==.',
Fo='Foxtrot:BAABLgAECn8hAAIFAAgJOhotLwAbAgAFAAgJOhotLwAbAgAAAA==.',
Fr='Frenzaoibh:BAAALgAECgYJEQABLgAECgkJMgAVAIoiAA==.Frostine:BAABLgAECn8ZAAIEAAcJtQdC1QBEAQAEAAcJtQdC1QBEAQAAAA==.Frostwave:BAACLgAFFH8GAAMOAAIJmB4HrwDAAAAOAAIJmB4HrwDAAAAiAAEJewhKKQA8AAAuAAQKf0YABCIACQmpIIIDAKsCACIACQmVH4IDAKsCACEACAnBHS8MAEgCAA4AAQlDHblGAVQAAAAA.Frostythot:BAAALgADCgIJAgAAAA==.',
Fu='Fujiyama:BAABLgAECn83AAIPAAgJ+yBcDQCQAgAPAAgJ+yBcDQCQAgAAAA==.Furryweasal:BAAALgADCgEJAQAAAA==.',
Ga='Garrex:BAAALgADCgUJBQABLgAECggJFQAFAMUWAA==.Garréosh:BAAALgAECgUJCgABLgAFFAQJEwAHAAocAA==.',
Ge='Geodude:BAAALgADCgYJBwAAAA==.',
Gi='Gibborim:BAAALgAECgYJCwAAAA==.Gigilomann:BAAALgAECgIJBAAAAA==.',
Gl='Glacial:BAAALgAECgEJAQAAAA==.Glenndanzig:BAAALgADCgYJBgAAAA==.',
Go='Goldenshield:BAAALgAECgMJCQAAAA==.Golteb:BAAALgAECgQJBAAAAA==.Gonecrazy:BAAALgADCgMJAwAAAA==.Gorthan:BAAALgADCgQJBgAAAA==.',
Gr='Grabandgank:BAAALgADCgYJBgAAAA==.Groggi:BAAALgAECgYJBAAAAA==.',
Gu='Guaresux:BAEALgADCgEJAQABLgAECgkJGQAMAFARAA==.Gurnisson:BAAALgADCgUJBQAAAA==.Gusto:BAABLgAECn8uAAQbAAkJ6AuoLgB9AQAbAAkJXQuoLgB9AQAcAAgJegNjHwD3AAAaAAcJwQegFQC1AAAAAA==.',
Ha='Hadouken:BAABLgAECn8UAAIHAAkJ5wCAsAEnAAAHAAkJ5wCAsAEnAAAAAA==.Hafsak:BAAALgAECgUJBQAAAA==.Halppme:BAAALgADCgcJBwAAAA==.Hammerfall:BAAALgAECgQJBAAAAA==.Handsome:BAAALgAECgcJBwAAAA==.',
He='Headshotte:BAAALgAECgYJDAAAAA==.Heatindabs:BAABLgAECn8gAAIDAAkJpg5uSgBiAQADAAkJpg5uSgBiAQAAAA==.Hexed:BAAALgAECgYJEwAAAA==.',
Hi='Hinael:BAAALgAECgEJAQAAAA==.',
Ho='Holyknight:BAAALgAECgYJDwAAAA==.Holymama:BAABLgAECn8gAAMUAAgJeh0IGQD8AQAUAAcJdCAIGQD8AQATAAIJIROrYABzAAAAAA==.',
Hu='Hunkwai:BAAALgAFFAIJAgAAAA==.',
Ib='Ibok:BAAALgAECgYJCgAAAA==.',
Ic='Iceberg:BAAALgAFFAIJAwABLgAFFAgJGQAEAK0iAA==.Ickma:BAABLgAECn9CAAIOAAkJ0x6lGQCrAgAOAAkJ0x6lGQCrAgAAAA==.',
Id='Iddou:BAAALgAECgUJCQAAAA==.',
Ik='Ikona:BAAALgADCggJDgAAAA==.',
Im='Impgobrr:BAAALgAECgEJAQAAAA==.Imu:BAAALgAECgIJAwAAAA==.',
In='Incubus:BAAALgADCgEJAgAAAA==.Infari:BAAALgAECgQJBAAAAA==.',
Ir='Irdeldran:BAAALgAECgEJAQAAAA==.',
Ja='Jabjek:BAAALgADCgYJCwAAAA==.Jamaz:BAAALgAECgQJBAAAAA==.Jamwich:BAAALgADCgYJBgAAAA==.Jasonmoloa:BAAALgAECgYJDgAAAA==.',
Je='Jerazia:BAAALgAECgYJBQAAAA==.',
Jo='Johanx:BAAALgADCgMJAwAAAA==.Jordananon:BAAALgAECgMJAwAAAA==.Jordanian:BAAALgAECgMJAwAAAA==.',
['Jî']='Jînxy:BAAALgAECgEJBAAAAA==.',
Ka='Kanamé:BAAALgAECgEJAgAAAA==.Kaollanna:BAABLgAECn8jAAIEAAkJDhYWWQAuAgAEAAkJDhYWWQAuAgAAAA==.Karik:BAAALgAECgUJEQAAAA==.Kaven:BAAALgADCgIJAgAAAA==.',
Ke='Kehma:BAAALgAECgEJAQAAAA==.Keleios:BAAALgADCgYJBgABLgAECgUJDwAGAAAAAA==.Kelisa:BAABLgAECn8uAAIHAAkJPx2oJgBnAgAHAAkJPx2oJgBnAgAAAA==.Ketchuptits:BAAALgADCgYJBgAAAA==.',
Ki='Kimjunggheal:BAAALgAECgMJBgAAAA==.Kinkster:BAAALgAECgYJCwABLgAECgYJDQAGAAAAAA==.Kinza:BAAALgADCgkJCQABLgAECggJGgAIAAAYAA==.Kiwidin:BAABLgAECn8gAAIRAAkJuhXmJgDzAQARAAkJuhXmJgDzAQAAAA==.',
Ko='Koketsu:BAAALgAECgYJEgAAAA==.',
Kr='Krinxy:BAABLgAECn8VAAIDAAUJFhqSWwA/AQADAAUJFhqSWwA/AQAAAA==.',
Ks='Kschwev:BAAALgADCgYJBgAAAA==.',
Ku='Kuratcha:BAAALgAECgUJCgABLgAECggJHgALAFAYAA==.',
Ky='Kylee:BAAALgAECgkJAQAAAA==.Kyý:BAAALgAECgYJDwAAAA==.',
['Kí']='Kíng:BAAALgAECgYJEwABLgAECggJHgALAFAYAA==.',
La='Lachoneus:BAAALgAECgEJAQAAAA==.Lazyde:BAAALgAECggJCwABLgAECgkJQQAjAMkiAA==.',
Le='Ledgerfeign:BAABLgAECn8qAAICAAkJDg1TUgCkAQACAAkJDg1TUgCkAQAAAA==.',
Li='Liadan:BAABLgAECn8jAAIRAAgJkAyCMwCDAQARAAgJkAyCMwCDAQAAAA==.Lighteye:BAABLgAECn9JAAIDAAkJcRkXFACnAgADAAkJcRkXFACnAgAAAA==.Lilmudatruka:BAAALgADCgEJAQABLgAECgYJFQAQAGkQAA==.Lindris:BAAALgAECgEJAQAAAA==.',
Lo='Longestibrow:BAAALgAECgMJBQAAAA==.',
Lu='Luminescence:BAAALgADCgQJBgAAAA==.Lunarqt:BAAALgAECgEJAQAAAA==.Lunchy:BAAALgAECgYJCQAAAA==.',
Ly='Lyllow:BAABLgAECn8UAAIcAAYJDhMSGgA0AQAcAAYJDhMSGgA0AQAAAA==.',
['Lø']='Løurent:BAAALgADCgQJBAAAAA==.',
Ma='Macklerina:BAAALgADCgQJBwAAAA==.Magicdorf:BAACLgAFFH8FAAIEAAIJxBR7mwCXAAAEAAIJxBR7mwCXAAAuAAQKfywAAgQACQlMIS0WANICAAQACQlMIS0WANICAAAA.Malphasia:BAAALgADCgYJBgAAAA==.Manhitrogue:BAAALgAECgcJEAAAAA==.Massivebicep:BAAALgAECgIJAgAAAA==.Mavras:BAAALgADCgEJAQAAAA==.',
Mc='Mcbraintumor:BAAALgAECgQJCQAAAA==.Mcsleuth:BAAALgAECgQJBgAAAA==.',
Me='Megarayquaza:BAACLgAFFH8LAAILAAQJEgZ9WgDYAAALAAQJEgZ9WgDYAAAuAAQKfx8AAyQACAkqEmseAMwBACQACAnIC2seAMwBAAsACAk1ERxhAGMBAAAA.',
Mi='Mikeyouk:BAAALgADCgYJBgAAAA==.Millertime:BAAALgAECgMJAwAAAA==.Misties:BAAALgAECgEJAQAAAA==.',
Mo='Moargoth:BAAALgADCgUJEAAAAA==.Mooneater:BAAALgAECgYJCAAAAA==.Moosedon:BAAALgAECgEJAgABLgAECgkJIAAHACAjAA==.Mordorl:BAAALgADCgcJBwAAAA==.',
Mt='Mtt:BAAALgADCgkJDgAAAA==.',
Mx='Mxx:BAABLgAECn8XAAQFAAUJbiC9TQCAAQAFAAUJbiC9TQCAAQAZAAMJMxQSTQB7AAAlAAEJzAMGlgAjAAAAAA==.',
My='Mylianne:BAABLgAECn8aAAIIAAcJYhzgHADeAQAIAAcJYhzgHADeAQAAAA==.Mynameiscole:BAACLgAFFH8IAAIkAAQJgh98AQCSAQAkAAQJgh98AQCSAQAuAAQKfyMAAiQACAmZJq4BAIoDACQACAmZJq4BAIoDAAEuAAUUBwkUAAsAAx4A.Myrolan:BAABLgAECn8tAAIkAAkJCCRhAwAeAwAkAAkJCCRhAwAeAwAAAA==.Myrtru:BAAALgAECgkJDgAAAA==.',
['Mí']='Míyagi:BAAALgAECgYJBgAAAA==.',
Na='Naturallight:BAAALgADCgUJCAAAAA==.',
Ne='Neechka:BAAALgADCgUJBQAAAA==.Neosan:BAAALgADCgYJBgABLgAFFAMJCgAIAOciAA==.Nevyn:BAABLgAECn8fAAImAAgJBxS5BACfAQAmAAgJBxS5BACfAQAAAA==.Newface:BAAALgADCgEJAgAAAA==.Newmoo:BAAALgAECgEJAQAAAA==.',
Ni='Nightsage:BAAALgAECgUJCQAAAA==.Niji:BAAALgAECgYJDwABLgAECggJGgAIAAAYAA==.Nininhp:BAABLgAECn8bAAITAAcJZRM2JQCjAQATAAcJZRM2JQCjAQAAAA==.Nithari:BAABLgAECn8/AAIEAAkJeyKLDAASAwAEAAkJeyKLDAASAwAAAA==.',
No='Nobel:BAAALgADCgEJAQAAAA==.Nomanai:BAAALgADCgkJAwAAAA==.Nosst:BAAALgAECgMJBQAAAA==.Nost:BAAALgADCgcJBwAAAA==.Nostu:BAABLgAECn8hAAMTAAkJsBZ4FgAhAgATAAkJsBZ4FgAhAgAUAAEJbhCZgQA2AAAAAA==.Now:BAACLgAFFH8OAAIHAAQJkh/vJQBrAQAHAAQJkh/vJQBrAQAuAAQKfx8AAwcACAkQIOAtAGsCAAcACAlPHuAtAGsCABIABgmIF0YcADABAAAA.',
Nu='Nukum:BAAALgAECgYJEAABLgAECggJJgAFAAAaAA==.',
Oh='Ohpa:BAABLgAECn8lAAMCAAgJohTwRQDHAQACAAgJohTwRQDHAQABAAMJhwjbLwBbAAAAAA==.Ohrly:BAAALgAECgEJAQAAAA==.',
Oj='Ojikan:BAABLgAECn8WAAIfAAgJvSKkAwD2AgAfAAgJvSKkAwD2AgAAAA==.Ojpriest:BAAALgAFFAMJAwAAAA==.',
On='Onore:BAAALgAECgEJAQAAAA==.',
Pa='Pallykera:BAAALgAECgEJAQAAAA==.Papamush:BAAALgAECgMJBQAAAA==.Pathogenn:BAAALgAECgYJEAAAAA==.',
Pe='Pepecry:BAAALgAECgUJDgABLgAECggJHgALAFAYAA==.',
Ph='Phoblade:BAABLgAECn8mAAIOAAgJNhaLUADPAQAOAAgJNhaLUADPAQAAAA==.Phobreeze:BAAALgAECgQJBgAAAA==.Phokk:BAAALgAECgcJBwAAAA==.',
Pi='Pirotess:BAABLgAECn8XAAIHAAkJdQnXvgAHAQAHAAkJdQnXvgAHAQAAAA==.',
Po='Pollymorphh:BAAALgADCgUJBQAAAA==.Ponylion:BAAALgAECgYJCwABLgAECgcJEQAGAAAAAA==.Pooshka:BAABLgAECn8dAAIPAAkJSCJiCgDvAgAPAAkJSCJiCgDvAgAAAA==.Popz:BAAALgAECgEJAQAAAA==.',
Pr='Preorcthego:BAACLgAFFH8WAAIZAAQJ4yb1BAC8AQAZAAQJ4yb1BAC8AQAuAAQKfykAAxkACAlqJpcAAIsDABkACAlqJpcAAIsDACUAAQm/JHV7AFUAAAEuAAUUBgkjAA4AmiEA.Presibro:BAABLgAECn8aAAIJAAcJfCIBCgBPAgAJAAcJfCIBCgBPAgAAAA==.Presiric:BAAALgAECgMJAwAAAA==.Presisarian:BAAALgAECgYJDwAAAA==.',
Pu='Puck:BAAALgAECgYJDQAAAA==.Puppye:BAACLgAFFH8MAAIFAAQJARr/NQA7AQAFAAQJARr/NQA7AQAuAAQKfxgAAgUACAlNHHAzAAoCAAUACAlNHHAzAAoCAAAA.',
Ra='Ranalia:BAAALgAECgQJBQAAAA==.Ranouu:BAABLgAECn8VAAIEAAYJIBW8nACcAQAEAAYJIBW8nACcAQAAAA==.Ratatatatt:BAAALgADCgQJBQAAAA==.',
Re='Reaoibher:BAAALgADCgMJAwABLgAECgkJMgAVAIoiAA==.Recision:BAABLgAECn9BAAIjAAkJySKZAQAKAwAjAAkJySKZAQAKAwAAAA==.Reeash:BAABLgAECn8XAAMQAAkJABeTJAAvAgAQAAkJABeTJAAvAgAPAAMJyAtoegB6AAAAAA==.Reeatar:BAABLgAECn8ZAAIEAAcJ5Rg9oACWAQAEAAcJ5Rg9oACWAQABLgAECgkJFwAQAAAXAA==.Relindor:BAAALgADCgYJBgABLgAFFAQJCAAOAJwSAA==.Revelle:BAAALgAECgkJCwAAAA==.',
Rh='Rheizen:BAABLgAECn8+AAIJAAgJbhkZDgAGAgAJAAgJbhkZDgAGAgAAAA==.',
Ri='Riptide:BAAALgAECgEJAQAAAA==.',
Ro='Ron:BAAALgADCgQJBAAAAA==.Ropopo:BAABLgAECn8fAAITAAgJtxmmGAAKAgATAAgJtxmmGAAKAgABLgAFFAQJDAAFAAEaAA==.',
Ru='Runcat:BAABLgAECn8XAAMLAAgJQh4NJQA3AgALAAgJQh4NJQA3AgAjAAQJ1QZLIwB/AAAAAA==.',
['Rö']='Röyksopp:BAABLgAECn8iAAIEAAgJAw4DfQB6AQAEAAgJAw4DfQB6AQAAAA==.',
Sa='Sabo:BAAALgAECgMJAwAAAA==.Sakona:BAAALgADCgEJAQAAAA==.Salbahe:BAAALgAFFAIJAwAAAA==.Samarah:BAAALgAECgcJCAAAAA==.Sandewor:BAABLgAECn8UAAQSAAYJ4RdUGgBCAQASAAYJ4RdUGgBCAQAHAAMJ0QpKHgGQAAARAAEJZgdMlgAoAAABLgAECgYJFQAZAPwMAA==.Sanfrancisco:BAAALgAECgIJAwABLgAECgIJAgAGAAAAAA==.Sarafyn:BAABLgAECn8/AAIgAAkJUxlcFQAmAgAgAAkJUxlcFQAmAgAAAA==.Sauceguzzler:BAAALgAECgYJBgAAAA==.Savath:BAAALgADCgYJBgAAAA==.',
Se='Selenagomes:BAAALgAECgEJAQABLgAFFAcJFAALAAMeAA==.Selenor:BAAALgAECgQJBwAAAA==.Seragaki:BAABLgAECn8kAAMTAAkJRRqODQCSAgATAAkJRRqODQCSAgAUAAYJmxNuNgA6AQAAAA==.Seraphinna:BAAALgADCgEJAQAAAA==.',
Si='Siegescale:BAAALgADCgcJCwAAAA==.Siegrorc:BAABLgAECn86AAIJAAkJWRQBEADkAQAJAAkJWRQBEADkAQAAAA==.Sillidari:BAAALgADCgQJBwAAAA==.Sindrila:BAAALgAECgYJDwAAAA==.Sionshope:BAAALgAECgUJCQAAAA==.',
Sk='Skragar:BAAALgAECgEJAgAAAA==.',
Sl='Slayerhunt:BAABLgAECn8VAAQZAAYJ/AwMMgAcAQAZAAYJ2wsMMgAcAQAFAAQJywvegQDiAAAlAAIJqQwGeABgAAAAAA==.Slayerlock:BAAALgAECgYJCQAAAA==.Slayertin:BAAALgAECgYJCwABLgAECgYJFQAZAPwMAA==.',
Sm='Smallpox:BAAALgAECgQJBAABLgAECgkJBQAGAAAAAA==.',
Sn='Snibdru:BAAALgAECgcJBgAAAA==.Snkrsotoole:BAABLgAECn8cAAIPAAYJgw4+VgDdAAAPAAYJgw4+VgDdAAAAAA==.',
So='Soobz:BAAALgADCgYJBgAAAA==.Sorian:BAAALgAECgUJCQAAAA==.Soulkings:BAAALgADCggJDwAAAA==.Soupies:BAAALgAECgQJBQAAAA==.Soxa:BAAALgADCgIJAgAAAA==.',
Sp='Spiikee:BAAALgAECgIJAgAAAA==.Sprays:BAAALgAECgQJBAAAAA==.',
Sr='Sry:BAAALgAECgYJBAAAAA==.',
St='Steady:BAABLgAECn8ZAAIHAAcJbhVEmABBAQAHAAcJbhVEmABBAQAAAA==.Stonehand:BAACLgAFFH8GAAIUAAMJsQqjJgC/AAAUAAMJsQqjJgC/AAAuAAQKfy0AAhQACQmgFDMZAPsBABQACQmgFDMZAPsBAAAA.Stormsurge:BAAALgAECgQJBQAAAA==.Stownt:BAAALgADCgMJAwAAAA==.Stravas:BAAALgAECgcJBwAAAA==.Strongbow:BAABLgAECn8hAAIFAAgJ9gpdZgByAQAFAAgJ9gpdZgByAQAAAA==.',
Su='Subudai:BAAALgAECgkJEAAAAA==.Sugarboi:BAACLgAFFH8FAAInAAIJXwKyNgBDAAAnAAIJXwKyNgBDAAAuAAQKfy0AAicACQlwCgMnABgBACcACQlwCgMnABgBAAAA.Sugasuga:BAABLgAECn8ZAAIHAAcJhh4+PAARAgAHAAcJhh4+PAARAgAAAA==.Sunnymuffins:BAAALgADCgYJBQAAAA==.',
Sv='Sveetka:BAAALgAECgMJBAAAAA==.',
Sx='Sxytrev:BAAALgAECgQJCQAAAA==.',
Ta='Tabi:BAAALgADCgQJBgAAAA==.Tacoy:BAABLgAECn8fAAIKAAgJxRZoLQCbAQAKAAgJxRZoLQCbAQAAAA==.Tagsy:BAABLgAECn8VAAIFAAgJxRZdOQDJAQAFAAgJxRZdOQDJAQAAAA==.Tay:BAAALgAECgcJCwAAAA==.Tayna:BAAALgADCgYJBgAAAA==.',
Tb='Tbizkut:BAABLgAECn9GAAIWAAkJIRCLCgCWAQAWAAkJIRCLCgCWAQAAAA==.',
Th='Then:BAABLgAECn8pAAIEAAcJSBk/bgCaAQAEAAcJSBk/bgCaAQAAAA==.Threetimez:BAABLgAECn8XAAIFAAcJJAw1fABCAQAFAAcJJAw1fABCAQAAAA==.Thumbmage:BAABLgAECn8UAAIEAAYJxCAUVQDaAQAEAAYJxCAUVQDaAQABLgAFFAQJDgAPANUiAA==.',
Ti='Timemaster:BAABLgAECn8hAAQkAAcJzx3eEgD+AQAkAAcJmR3eEgD+AQAjAAEJYyLuJwBiAAALAAIJnQMT1wBCAAAAAA==.Timepacifist:BAAALgAECgcJCgAAAA==.',
To='Tobeybey:BAAALgAECgIJBAAAAA==.Tokido:BAAALgAFFAEJAQAAAA==.Tongpakfu:BAABLgAECn8ZAAIMAAQJTRCHcQC8AAAMAAQJTRCHcQC8AAAAAA==.Topflight:BAAALgAECgcJEgAAAA==.',
Tr='Triggered:BAABLgAECn8bAAMHAAgJVBeZUQDsAQAHAAgJVBeZUQDsAQARAAEJ0AqlngAqAAAAAA==.Troiikâ:BAABLgAECn9CAAQSAAkJphQEEADFAQASAAkJphQEEADFAQAHAAcJNgdgzQDzAAARAAUJ8QJWagCJAAAAAA==.Troikkâ:BAAALgADCgQJBAAAAA==.Troikâ:BAAALgADCgYJBwAAAA==.Trroikâ:BAABLgAECn83AAIJAAgJ6RaCEQDOAQAJAAgJ6RaCEQDOAQAAAA==.',
Tt='Tteeffinn:BAAALgADCgYJBgAAAA==.Ttevinn:BAAALgAECgMJBAABLgAECgkJBwAGAAAAAA==.Ttevoker:BAAALgAECgkJBwAAAA==.',
Tu='Tulvie:BAAALgADCgQJCAAAAA==.Tummytickle:BAAALgAECgEJAQAAAA==.Tupacaroni:BAAALgAECgMJAwAAAA==.',
Ty='Tycone:BAAALgAECgcJCgAAAA==.',
Ud='Udderpower:BAAALgAECgkJBQAAAA==.',
Ul='Uldirtydruid:BAABLgAECn8vAAMDAAgJ6B45EQDEAgADAAgJ6B45EQDEAgAnAAUJfBNMMADkAAAAAA==.',
Ur='Urukdrak:BAABLgAECn8kAAMZAAkJJw3MHgClAQAZAAkJkAnMHgClAQAlAAgJiQ3iMwCcAQAAAA==.',
Uw='Uwantwar:BAAALgAECgYJDgAAAA==.',
Va='Valanquishy:BAAALgADCgEJAgAAAA==.',
Ve='Velaryon:BAAALgAECgQJBAAAAA==.',
Vh='Vhagar:BAAALgAECgIJAwAAAA==.',
Vi='Vidich:BAAALgAFFAEJAQAAAA==.Viralus:BAAALgADCgEJAQAAAA==.',
Vo='Vodka:BAAALgAECgEJAgAAAA==.Voiddastard:BAAALgADCgkJFwAAAA==.Voidlight:BAAALgADCgcJBwAAAA==.Volcazzic:BAAALgADCgIJAgAAAA==.',
Vy='Vynnara:BAAALgADCgMJAQAAAA==.',
Wa='Wakkaba:BAAALgADCgYJBgAAAA==.Wanaatlarboy:BAABLgAECn8vAAMUAAkJZRZvEwA1AgAUAAkJZRZvEwA1AgATAAEJ7gH4XgAiAAAAAA==.Waywyrd:BAAALgADCgMJAwAAAA==.',
Wh='Whack:BAAALgADCgcJCAAAAA==.',
Wu='Wunderbar:BAABLgAECn8eAAIQAAYJKxtxTAB6AQAQAAYJKxtxTAB6AQAAAA==.Wunderburger:BAAALgAECgYJEQAAAA==.Wunderground:BAAALgAECgYJDwAAAA==.',
Xa='Xannada:BAABLgAECn9CAAIHAAkJmxKJSwDiAQAHAAkJmxKJSwDiAQAAAA==.',
Xe='Xenztrazlu:BAAALgAECgQJCAABLgAECgcJGwATAGUTAA==.',
Ya='Yahknee:BAAALgADCgEJAQAAAA==.Yaoli:BAAALgAECgMJBAAAAA==.',
Ye='Yea:BAAALgADCgcJCwAAAA==.',
Yo='Yodadogownz:BAABLgAECn8TAAIUAAcJ7xCQMgBPAQAUAAcJ7xCQMgBPAQAAAA==.Yoh:BAACLgAFFH8OAAIOAAQJ7w85dAAXAQAOAAQJ7w85dAAXAQAuAAQKfxwAAg4ACAlKHQ9BAP0BAA4ACAlKHQ9BAP0BAAAA.Yoruichee:BAAALgAECgEJAQAAAA==.Yourenotron:BAAALgAECgEJAgAAAA==.',
Yu='Yungdro:BAAALgAECgEJAQAAAA==.',
Za='Zarutobi:BAAALgAECgYJEgABLgAECggJGgAIAAAYAA==.',
Zo='Zob:BAAALgADCgQJBAAAAA==.',
Zu='Zui:BAABLgAECn8pAAIXAAkJahK0GwDFAQAXAAkJahK0GwDFAQAAAA==.',
['Zù']='Zùg:BAAALgADCgIJAQAAAA==.',
['Ðo']='Ðongknight:BAAALgAFFAIJBAABLgAFFAQJDgAKANAZAA==.',
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
