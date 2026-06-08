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
local provider = {region='US',realm='DarkIron',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aanx:BAABLgAECn8ZAAMBAAYJth2WGADpAAACAAYJth3vfgA2AQABAAQJQhmWGADpAAAAAA==.',
Ab='Abadon:BAAALgAECgQJBgABLgAFFAEJBQADAEcUAA==.Abdorei:BAACLgAFFH8GAAIEAAQJAwaJdwDiAAAEAAQJAwaJdwDiAAAuAAQKfzcAAgQACQlFFs9CAA0CAAQACQlFFs9CAA0CAAAA.Absorboat:BAAALgADCgYJCAAAAA==.',
Ac='Accilatem:BAABLgAECn8aAAIFAAcJQh4nHgBRAgAFAAcJQh4nHgBRAgABLgAECgkJIgAEAHIZAA==.Accilatim:BAABLgAECn8iAAIEAAkJchneLABfAgAEAAkJchneLABfAgAAAA==.',
Ad='Adonsina:BAAALgAECgEJAQABLgAECgkJCwAGAAAAAA==.',
Ae='Aether:BAAALgAECgMJAwAAAA==.',
Ag='Agrromagnet:BAABLgAECn8oAAIHAAkJahhVNgBJAgAHAAkJahhVNgBJAgAAAA==.',
Ai='Aiba:BAABLgAECn8ZAAIIAAgJ1henHADWAQAIAAgJ1henHADWAQAAAA==.',
Ak='Akcloud:BAABLgAFFH8MAAMJAAQJzBtsEAAaAQAJAAQJSBhsEAAaAQAKAAEJ2yPTHQBoAAAAAA==.',
Al='Alab:BAAALgAECgIJBAABLgAECggJHgALAFAYAA==.Alaeris:BAACLgAFFH8QAAIMAAQJNhj5IwAfAQAMAAQJNhj5IwAfAQAuAAQKfyIAAgwACQlaHSYMAMcCAAwACQlaHSYMAMcCAAAA.Albetabeef:BAACLgAFFH8JAAMNAAQJGxTuFQAbAQANAAQJGxTuFQAbAQAKAAIJJgZQHACUAAAuAAQKfxgAAw0ACAn/ILQJAEUCAAoABwk2ICAWAJwCAA0ABwmjIrQJAEUCAAAA.Alexei:BAABLgAECn8VAAIOAAcJEQfNrwALAQAOAAcJEQfNrwALAQAAAA==.Aleyeah:BAAALgAECgYJDgABLgAECggJNwAPAPsgAA==.Allhopeisded:BAABLgAECn8UAAIQAAYJog7ubwD8AAAQAAYJog7ubwD8AAAAAA==.Alurelor:BAAALgAECgkJDwAAAA==.Alyreu:BAAALgAECgQJBAABLgAECgYJDQAGAAAAAA==.',
Am='Amanita:BAAALgADCgkJCQAAAA==.Amarah:BAAALgADCgYJBgAAAA==.Amelaista:BAABLgAECn89AAIQAAkJ2QxeQQCaAQAQAAkJ2QxeQQCaAQAAAA==.',
An='Anddi:BAAALgAECgEJAwAAAA==.Andii:BAACLgAFFH8IAAIRAAQJXhn0HAArAQARAAQJXhn0HAArAQAuAAQKfxgABBEACAnIF38/AHoBABEABwnQFn8/AHoBAAcAAgm2B6CYASoAABIAAQkAAKNcAAAAAAAA.Andy:BAACLgAFFH8FAAITAAMJHgqHMAC1AAATAAMJHgqHMAC1AAAuAAQKfxQAAxMACAkoH8EKALgCABMACAkoH8EKALgCABQAAQkXBzWHACsAAAAA.Angusbeef:BAAALgAECgcJBwAAAA==.Antipus:BAAALgAECgQJBQAAAA==.',
Ao='Aoibhoker:BAAALgAECgQJBAABLgAECgkJMgAVAIoiAA==.',
Ar='Arclo:BAAALgADCgYJBgAAAA==.Arden:BAAALgAECgQJBAABLgAECgYJFwAWANsWAA==.Ardeno:BAABLgAECn8XAAMWAAYJ2xarIwA7AQAWAAYJbwyrIwA7AQACAAUJ2xZnmQAGAQAAAA==.Ardon:BAABLgAECn8sAAMQAAkJ8hpgEgCvAgAQAAkJ8hpgEgCvAgAPAAUJvhsbMQCaAQAAAA==.Armis:BAAALgADCgUJBQAAAA==.',
As='Asteruis:BAABLgAECn8kAAIFAAkJDh7yJgA4AgAFAAkJDh7yJgA4AgAAAA==.',
Av='Avenayra:BAAALgAECgIJAwAAAA==.',
Ay='Ayroon:BAAALgAECgEJAQAAAA==.',
Ba='Baddhealer:BAAALgADCgUJBQAAAA==.Badfurion:BAAALgADCggJCgAAAA==.Balthamel:BAAALgAECgYJDAAAAA==.Bananafang:BAAALgAECgQJBgAAAA==.Bananashoes:BAAALgAECgMJAgAAAA==.Bangerz:BAACLgAFFH9AAAIRAAgJKhOTBQBXAgARAAgJKhOTBQBXAgAuAAQKfzwAAxEACQlmILMIAOMCABEACQlmILMIAOMCAAcAAQm4AedYASYAAAAA.Barkendremix:BAABLgAECn80AAMXAAkJYRtwCwB2AgAXAAkJYRtwCwB2AgAYAAEJFBUcigA9AAAAAA==.Bathsheber:BAAALgAFFAEJAQABLgAFFAcJGAAEANsiAA==.Baulbuster:BAAALgAECggJCgAAAA==.',
Be='Beanieweenie:BAAALgADCgEJAQAAAA==.Beerez:BAAALgADCgcJDQAAAA==.Belroy:BAABLgAECn8fAAIZAAYJKBOpKgBIAQAZAAYJKBOpKgBIAQAAAA==.Beriothien:BAAALgAECgEJAQAAAA==.',
Bj='Bjorum:BAACLgAFFH8KAAIVAAQJAR4FBQBgAQAVAAQJAR4FBQBgAQAuAAQKfyMAAxUACQmVIusFAHQCABUACQmVIusFAHQCAA8AAQnhCLaQACcAAAAA.',
Bo='Bodytwodafa:BAACLgAFFH8PAAMaAAQJgBU8BAAoAQAaAAQJNBI8BAAoAQAbAAMJaA8SQAC3AAAuAAQKfyAABBoACAntIBgGAJUCABoACAkhHhgGAJUCABwABgn4GM0QALUBABsABwlwGDsrAIkBAAAA.Bournemaad:BAAALgADCgMJAwAAAA==.Boyafu:BAAALgAECgEJAQAAAA==.',
Br='Brucecampbel:BAAALgAECgMJCQAAAA==.',
Bu='Bubbleyou:BAABLgAECn8ZAAMSAAYJZBBsJwDNAAASAAYJZBBsJwDNAAAHAAIJuwqWkQEsAAAAAA==.Burnek:BAAALgAECgIJBAABLgAECggJHgALAFAYAA==.',
Ca='Cantarella:BAABLgAECn84AAMdAAkJSgd4DQBEAQAdAAkJCgZ4DQBEAQAeAAgJRAZKKABEAQAAAA==.Capy:BAAALgAFFAEJAgABLgAFFAUJEgAZAN8iAA==.Carlyle:BAABLgAECn8tAAMHAAkJgxuvIgBxAgAHAAkJgxuvIgBxAgARAAUJlxUlPABLAQAAAA==.Catdaddy:BAAALgADCgYJBwAAAA==.',
Ch='Checkmybio:BAAALgAECgQJBQAAAA==.Cheekyteetah:BAAALgAECgEJAQAAAA==.Cheesecake:BAAALgADCgUJBQAAAA==.Chromehound:BAAALgADCgQJBAAAAA==.Chumdungler:BAAALgAECgMJAwAAAA==.',
Ci='Cindervis:BAAALgADCgYJBgAAAA==.',
Cl='Clonk:BAAALgAECgUJBgAAAA==.',
Co='Collossuss:BAAALgAECgYJEwAAAA==.Convik:BAAALgAECgkJBwAAAA==.',
Cr='Cregga:BAAALgADCgEJAQAAAA==.Crimsonagony:BAAALgADCgUJBQAAAA==.Crosshairs:BAAALgADCgMJAwAAAA==.Crusible:BAAALgADCgEJAQAAAA==.',
Cu='Cuddles:BAAALgADCgUJBQAAAA==.Curacao:BAABLgAECn8YAAIKAAcJAhTEOQBXAQAKAAcJAhTEOQBXAQAAAA==.',
Cy='Cynnari:BAAALgAECgYJDQAAAA==.',
Da='Dabtime:BAABLgAECn8hAAIHAAgJJBPacgCWAQAHAAgJJBPacgCWAQAAAA==.Darkstarr:BAAALgAECgUJCAAAAA==.David:BAAALgAECgYJBgABLgAECgkJLwAZAEkiAA==.',
De='Deathknightm:BAAALgAECgIJAgABLgAECgkJHAAJAHYVAA==.Dekaar:BAABLgAECn8bAAIfAAYJuwl6JQDMAAAfAAYJuwl6JQDMAAAAAA==.Demonknight:BAAALgAECgEJAQAAAA==.Deracine:BAAALgAECgcJCgAAAA==.Derek:BAAALgAECggJDwAAAA==.Desdemonica:BAABLgAECn8dAAIFAAgJ6AjFbABbAQAFAAgJ6AjFbABbAQAAAA==.',
Di='Diegoknight:BAAALgADCgEJAgAAAA==.Diggle:BAAALgADCggJCAAAAA==.Dilvdrood:BAAALgADCgUJBQAAAA==.Dilvish:BAAALgAECgYJEgAAAA==.',
Do='Doctrwho:BAAALgADCgIJAgAAAA==.Dohaeris:BAABLgAECn8yAAIgAAkJ9xO0GwDbAQAgAAkJ9xO0GwDbAQAAAA==.Domain:BAABLgAECn8eAAILAAgJUBjZOwDMAQALAAgJUBjZOwDMAQAAAA==.Donfalprun:BAABLgAECn8gAAIHAAkJICM1CwAEAwAHAAkJICM1CwAEAwAAAA==.Doomstout:BAABLgAECn8WAAIEAAgJSBKwdACKAQAEAAgJSBKwdACKAQAAAA==.',
Dr='Draconus:BAABLgAECn8zAAMhAAkJfhWoEAD1AQAhAAkJUBOoEAD1AQAOAAQJcRuT4gDFAAAAAA==.Dralas:BAAALgAECgcJDQAAAA==.Drkillenger:BAAALgAECgkJCQAAAA==.',
Du='Duro:BAAALgAECgYJDAABLgAECgYJDAAGAAAAAA==.Durto:BAAALgADCgMJAwABLgAECgQJCAAGAAAAAA==.Duskshade:BAAALgAECgQJBQAAAA==.',
['Dü']='Düsk:BAABLgAECn8VAAIOAAkJOQd4cAB7AQAOAAkJOQd4cAB7AQAAAA==.',
Ea='Eachan:BAAALgAECgMJAwAAAA==.',
El='Elij:BAACLgAFFH8JAAICAAQJYRhWPgBAAQACAAQJYRhWPgBAAQAuAAQKfx8AAgIACAmJHm0fAGICAAIACAmJHm0fAGICAAAA.Elunaire:BAACLgAFFH8FAAIDAAEJRxQ+ZgA+AAADAAEJRxQ+ZgA+AAAuAAQKfxwAAgMACQkCHJIdAFECAAMACQkCHJIdAFECAAAA.',
Em='Emelec:BAAALgAECgIJAgAAAA==.Emeraldwish:BAACLgAFFH8OAAMDAAQJliCkGwBtAQADAAQJliCkGwBtAQAIAAEJhA37QwBFAAAuAAQKfx0AAwMACAmlI2sGACUDAAMACAmlI2sGACUDAAgAAQkAAOylAAAAAAAA.',
Er='Eraline:BAAALgADCgYJBgAAAA==.Erthnite:BAAALgAECgQJBAAAAA==.',
Ev='Evinco:BAABLgAECn8aAAIWAAkJhBBoEwAJAQAWAAkJhBBoEwAJAQAAAA==.Evy:BAAALgAECgEJAgAAAA==.',
Ex='Executie:BAACLgAFFH8ZAAMNAAcJAxSlBwC1AQANAAcJAxSlBwC1AQAKAAMJGQzSEgDvAAAuAAQKfyYAAw0ACQngG3gGAGQCAA0ACQnLGngGAGQCAAoABglLHFw1ANQBAAAA.Exev:BAAALgADCgMJAwAAAA==.',
Fa='Falin:BAAALgAECgEJAQAAAA==.Fancy:BAAALgAECgYJBQAAAA==.',
Fe='Fey:BAABLgAECn8iAAICAAkJ5BPFRwC/AQACAAkJ5BPFRwC/AQAAAA==.',
Fi='Fieryember:BAAALgAECgQJBQABLgAECggJHgALAFAYAA==.Fistvendor:BAABLgAECn8UAAIXAAkJxAiXKQBfAQAXAAkJxAiXKQBfAQAAAA==.',
Fl='Flasheals:BAABLgAECn8wAAIRAAkJLBOLHwD7AQARAAkJLBOLHwD7AQAAAA==.Flatpak:BAAALgADCgEJAgAAAA==.Flobglop:BAAALgAECgEJAQAAAA==.Fluffybum:BAAALgADCgEJAQAAAA==.',
Fo='Foxtrot:BAABLgAECn8hAAIFAAgJOhogLAAhAgAFAAgJOhogLAAhAgAAAA==.',
Fr='Frenzaoibh:BAAALgAECgYJDwABLgAECgkJMgAVAIoiAA==.Frostine:BAABLgAECn8ZAAIEAAcJtQdC1QBEAQAEAAcJtQdC1QBEAQAAAA==.Frostwave:BAABLgAECn9GAAQiAAkJqSAlAwCwAgAiAAkJlR8lAwCwAgAhAAgJwR1uCwBNAgAOAAEJQx1ROgFUAAAAAA==.Frostythot:BAAALgADCgIJAgAAAA==.',
Fu='Fujiyama:BAABLgAECn83AAIPAAgJ+yCRDACRAgAPAAgJ+yCRDACRAgAAAA==.Furryweasal:BAAALgADCgEJAQAAAA==.',
Ga='Garrex:BAAALgADCgUJBQABLgAECggJFQAFAMUWAA==.Garréosh:BAAALgAECgUJCgABLgAFFAMJDwAHAMEcAA==.',
Ge='Geodude:BAAALgADCgYJBwAAAA==.',
Gi='Gibborim:BAAALgAECgYJCwAAAA==.Gigilomann:BAAALgAECgIJBAAAAA==.',
Gl='Glenndanzig:BAAALgADCgYJBgAAAA==.',
Go='Goldenshield:BAAALgAECgMJCQAAAA==.Golteb:BAAALgAECgQJBAAAAA==.Gonecrazy:BAAALgADCgMJAwAAAA==.Gorthan:BAAALgADCgQJBgAAAA==.',
Gr='Grabandgank:BAAALgADCgYJBgAAAA==.Groggi:BAAALgAECgYJBAAAAA==.',
Gu='Guaresux:BAEALgADCgEJAQABLgAECgkJGQAMAFARAA==.Gurnisson:BAAALgADCgUJBQAAAA==.Gusto:BAABLgAECn8uAAQbAAkJ6AutLACAAQAbAAkJXQutLACAAQAcAAgJegM3HgD+AAAaAAcJwQcAFQC1AAAAAA==.',
Ha='Hadouken:BAABLgAECn8UAAIHAAkJ5wAvogEnAAAHAAkJ5wAvogEnAAAAAA==.Hafsak:BAAALgAECgUJBQAAAA==.Halppme:BAAALgADCgcJBwAAAA==.Hammerfall:BAAALgAECgQJBAAAAA==.Handsome:BAAALgAECgcJBwAAAA==.',
He='Headshotte:BAAALgAECgYJDAAAAA==.Heatindabs:BAABLgAECn8gAAIDAAkJpg57SABjAQADAAkJpg57SABjAQAAAA==.Hexed:BAAALgAECgUJDgAAAA==.',
Hi='Hinael:BAAALgAECgEJAQAAAA==.',
Ho='Holyknight:BAAALgAECgYJDwAAAA==.Holymama:BAABLgAECn8gAAMUAAgJeh0UGAD/AQAUAAcJdCAUGAD/AQATAAIJIRM5XABzAAAAAA==.',
Hu='Hunkwai:BAAALgAFFAIJAgAAAA==.',
Ib='Ibok:BAAALgAECgYJCgAAAA==.',
Ic='Iceberg:BAAALgAFFAIJAwABLgAFFAcJGAAEANsiAA==.Ickma:BAABLgAECn9CAAIOAAkJ0x4RGACuAgAOAAkJ0x4RGACuAgAAAA==.',
Id='Iddou:BAAALgAECgUJCQAAAA==.',
Ik='Ikona:BAAALgADCggJDgAAAA==.',
Im='Impgobrr:BAAALgAECgEJAQAAAA==.Imu:BAAALgAECgEJAQAAAA==.',
In='Incubus:BAAALgADCgEJAgAAAA==.Infari:BAAALgAECgQJBAAAAA==.',
Ir='Irdeldran:BAAALgAECgEJAQAAAA==.',
Ja='Jabjek:BAAALgADCgYJCwAAAA==.Jamaz:BAAALgAECgQJBAAAAA==.Jamwich:BAAALgADCgYJBgAAAA==.Jasonmoloa:BAAALgAECgYJDgAAAA==.',
Je='Jerazia:BAAALgAECgYJBQAAAA==.',
Jo='Johanx:BAAALgADCgMJAwAAAA==.Jordananon:BAAALgAECgMJAwAAAA==.Jordanian:BAAALgAECgMJAwAAAA==.',
['Jî']='Jînxy:BAAALgAECgEJBAAAAA==.',
Ka='Kanamé:BAAALgAECgEJAQAAAA==.Kaollanna:BAABLgAECn8jAAIEAAkJDhYWWQAuAgAEAAkJDhYWWQAuAgAAAA==.Karik:BAAALgAECgUJEQAAAA==.Kaven:BAAALgADCgIJAgAAAA==.',
Ke='Kehma:BAAALgAECgEJAQAAAA==.Keleios:BAAALgADCgYJBgABLgAECgUJDwAGAAAAAA==.Kelisa:BAABLgAECn8uAAIHAAkJPx07JABqAgAHAAkJPx07JABqAgAAAA==.Ketchuptits:BAAALgADCgYJBgAAAA==.',
Ki='Kimjunggheal:BAAALgAECgMJBgAAAA==.Kinkster:BAAALgAECgYJCwABLgAECgYJDQAGAAAAAA==.Kinza:BAAALgADCgkJCQABLgAECggJGQAIANYXAA==.Kiwidin:BAABLgAECn8gAAIRAAkJuhXmJgDzAQARAAkJuhXmJgDzAQAAAA==.',
Ko='Koketsu:BAAALgAECgYJDQAAAA==.',
Kr='Krinxy:BAABLgAECn8VAAIDAAUJFhqSWwA/AQADAAUJFhqSWwA/AQAAAA==.',
Ks='Kschwev:BAAALgADCgYJBgAAAA==.',
Ku='Kuratcha:BAAALgAECgUJCgABLgAECggJHgALAFAYAA==.',
Ky='Kylee:BAAALgAECgkJAQAAAA==.Kyý:BAAALgAECgYJDwAAAA==.',
['Kí']='Kíng:BAAALgAECgYJEwABLgAECggJHgALAFAYAA==.',
La='Lachoneus:BAAALgAECgEJAQAAAA==.Lazyde:BAAALgAECggJCwABLgAECgkJQQAjAMkiAA==.',
Le='Ledgerfeign:BAABLgAECn8qAAICAAkJDg2hTgCqAQACAAkJDg2hTgCqAQAAAA==.',
Li='Liadan:BAABLgAECn8jAAIRAAgJkAz0MQCEAQARAAgJkAz0MQCEAQAAAA==.Lighteye:BAABLgAECn9JAAIDAAkJcRkxEwCpAgADAAkJcRkxEwCpAgAAAA==.Lilmudatruka:BAAALgADCgEJAQABLgAECgYJFAAQAKIOAA==.Lindris:BAAALgAECgEJAQAAAA==.',
Lo='Longestibrow:BAAALgAECgMJBQAAAA==.',
Lu='Luminescence:BAAALgADCgQJBgAAAA==.Lunarqt:BAAALgAECgEJAQAAAA==.Lunchy:BAAALgAECgYJCQAAAA==.',
Ly='Lyllow:BAABLgAECn8UAAIcAAYJDhOUGQA0AQAcAAYJDhOUGQA0AQAAAA==.',
['Lø']='Løurent:BAAALgADCgQJBAAAAA==.',
Ma='Magicdorf:BAACLgAFFH8FAAIEAAIJxBTJkwCXAAAEAAIJxBTJkwCXAAAuAAQKfywAAgQACQlMIdEUANYCAAQACQlMIdEUANYCAAAA.Malphasia:BAAALgADCgYJBgAAAA==.Manhitrogue:BAAALgAECgcJCwAAAA==.Massivebicep:BAAALgAECgIJAgAAAA==.Mavras:BAAALgADCgEJAQAAAA==.',
Mc='Mcbraintumor:BAAALgAECgQJCAAAAA==.Mcsleuth:BAAALgAECgQJBgAAAA==.',
Me='Megarayquaza:BAACLgAFFH8LAAILAAQJEgbwUwDfAAALAAQJEgbwUwDfAAAuAAQKfx8AAyQACAkqEmseAMwBACQACAnIC2seAMwBAAsACAk1ESpeAGIBAAAA.',
Mi='Mikeyouk:BAAALgADCgYJBgAAAA==.Misties:BAAALgAECgEJAQAAAA==.',
Mo='Moargoth:BAAALgADCgUJEAAAAA==.Mooneater:BAAALgAECgYJCAAAAA==.Moosedon:BAAALgAECgEJAgABLgAECgkJIAAHACAjAA==.Mordorl:BAAALgADCgcJBwAAAA==.',
Mt='Mtt:BAAALgADCgkJDgAAAA==.',
Mx='Mxx:BAABLgAECn8XAAQFAAUJbiC9TQCAAQAFAAUJbiC9TQCAAQAZAAMJMxS4SgB+AAAlAAEJzAMGlgAjAAAAAA==.',
My='Mylianne:BAABLgAECn8aAAIIAAcJYhylGwDfAQAIAAcJYhylGwDfAQAAAA==.Mynameiscole:BAACLgAFFH8IAAIkAAQJgh98AQCSAQAkAAQJgh98AQCSAQAuAAQKfyMAAiQACAmZJq4BAIoDACQACAmZJq4BAIoDAAAA.Myrolan:BAABLgAECn8tAAIkAAkJCCTyAgAiAwAkAAkJCCTyAgAiAwAAAA==.Myrtru:BAAALgAECgkJDQAAAA==.',
['Mí']='Míyagi:BAAALgAECgYJBgAAAA==.',
Na='Naturallight:BAAALgADCgUJCAAAAA==.',
Ne='Neechka:BAAALgADCgUJBQAAAA==.Neosan:BAAALgADCgYJBgABLgAFFAMJCgAIAOciAA==.Nevyn:BAABLgAECn8fAAImAAgJBxRsBACkAQAmAAgJBxRsBACkAQAAAA==.Newface:BAAALgADCgEJAgAAAA==.Newmoo:BAAALgAECgEJAQAAAA==.',
Ni='Nightsage:BAAALgAECgUJCQAAAA==.Niji:BAAALgAECgYJDwABLgAECggJGQAIANYXAA==.Nininhp:BAAALgAECgYJEQAAAA==.Nithari:BAABLgAECn8/AAIEAAkJeyKOCwAXAwAEAAkJeyKOCwAXAwAAAA==.',
No='Nobel:BAAALgADCgEJAQAAAA==.Nomanai:BAAALgADCgkJAwAAAA==.Nosst:BAAALgAECgMJBQAAAA==.Nost:BAAALgADCgcJBwAAAA==.Nostu:BAABLgAECn8hAAMTAAkJsBZWFQAjAgATAAkJsBZWFQAjAgAUAAEJbhBlfAA2AAAAAA==.Now:BAACLgAFFH8OAAIHAAQJkh8zIABxAQAHAAQJkh8zIABxAQAuAAQKfx8AAwcACAkQIOAtAGsCAAcACAlPHuAtAGsCABIABgmIFyIbADEBAAAA.',
Nu='Nukum:BAAALgAECgYJEAABLgAECggJIAAFAAAaAA==.',
Oh='Ohpa:BAABLgAECn8lAAMCAAgJohT0QgDNAQACAAgJohT0QgDNAQABAAMJhwhHLQBbAAAAAA==.Ohrly:BAAALgAECgEJAQAAAA==.',
Oj='Ojikan:BAABLgAECn8WAAIfAAgJvSKkAwD2AgAfAAgJvSKkAwD2AgAAAA==.Ojpriest:BAAALgAFFAMJAwAAAA==.',
Pa='Pallykera:BAAALgAECgEJAQAAAA==.Papamush:BAAALgAECgMJBQAAAA==.Pathogenn:BAAALgAECgYJEAAAAA==.',
Pe='Pepecry:BAAALgAECgUJDgABLgAECggJHgALAFAYAA==.',
Ph='Phoblade:BAABLgAECn8mAAIOAAgJNhY8TQDUAQAOAAgJNhY8TQDUAQAAAA==.Phobreeze:BAAALgAECgQJBgAAAA==.Phokk:BAAALgAECgcJBwAAAA==.',
Pi='Pirotess:BAAALgAECgYJDgAAAA==.',
Po='Pollymorphh:BAAALgADCgUJBQAAAA==.Ponylion:BAAALgAECgYJCwABLgAECgcJEQAGAAAAAA==.Pooshka:BAABLgAECn8dAAIPAAkJSCJiCgDvAgAPAAkJSCJiCgDvAgAAAA==.Popz:BAAALgAECgEJAQAAAA==.',
Pr='Preorcthego:BAACLgAFFH8WAAIZAAQJ4ybwAwDAAQAZAAQJ4ybwAwDAAQAuAAQKfykAAxkACAlqJpcAAIsDABkACAlqJpcAAIsDACUAAQm/JHV7AFUAAAEuAAUUBgkfAA4AHyEA.Presibro:BAABLgAECn8XAAIJAAYJPyAeEgC8AQAJAAYJPyAeEgC8AQAAAA==.Presiric:BAAALgAECgMJAwAAAA==.Presisarian:BAAALgAECgYJDwAAAA==.',
Pu='Puck:BAAALgAECgYJDQAAAA==.Puppye:BAACLgAFFH8MAAIFAAQJARrtLgBFAQAFAAQJARrtLgBFAQAuAAQKfxgAAgUACAlNHAEwABECAAUACAlNHAEwABECAAAA.',
Ra='Ranalia:BAAALgAECgEJAQAAAA==.Ranouu:BAABLgAECn8VAAIEAAYJIBW8nACcAQAEAAYJIBW8nACcAQAAAA==.Ratatatatt:BAAALgADCgQJBQAAAA==.',
Re='Reaoibher:BAAALgADCgMJAwABLgAECgkJMgAVAIoiAA==.Recision:BAABLgAECn9BAAIjAAkJySJwAQAMAwAjAAkJySJwAQAMAwAAAA==.Reeash:BAABLgAECn8XAAMQAAkJABfXIgAwAgAQAAkJABfXIgAwAgAPAAMJyAtSdQB6AAAAAA==.Reeatar:BAABLgAECn8ZAAIEAAcJ5Rg9oACWAQAEAAcJ5Rg9oACWAQABLgAECgkJFwAQAAAXAA==.Relindor:BAAALgADCgYJBgABLgAFFAQJCAAOAJwSAA==.Revelle:BAAALgAECgkJCwAAAA==.',
Rh='Rheizen:BAABLgAECn82AAIJAAgJWRZiEADWAQAJAAgJWRZiEADWAQAAAA==.',
Ri='Riptide:BAAALgAECgEJAQAAAA==.',
Ro='Ron:BAAALgADCgQJBAAAAA==.Ropopo:BAABLgAECn8fAAITAAgJtxmKFwALAgATAAgJtxmKFwALAgABLgAFFAQJDAAFAAEaAA==.',
Ru='Runcat:BAABLgAECn8XAAMLAAgJQh6FIwA3AgALAAgJQh6FIwA3AgAjAAQJ1QbDIQB/AAAAAA==.',
['Rö']='Röyksopp:BAABLgAECn8iAAIEAAgJAw76dgCEAQAEAAgJAw76dgCEAQAAAA==.',
Sa='Sabo:BAAALgADCgQJBQAAAA==.Sakona:BAAALgADCgEJAQAAAA==.Salbahe:BAAALgAFFAEJAQAAAA==.Samarah:BAAALgAECgcJCAAAAA==.Sandewor:BAABLgAECn8UAAQSAAYJ4RdTGQBDAQASAAYJ4RdTGQBDAQAHAAMJ0QqKFAGQAAARAAEJZgc9kgAoAAABLgAECgYJFQAZAPwMAA==.Sanfrancisco:BAAALgAECgIJAwABLgAECgIJAgAGAAAAAA==.Sarafyn:BAABLgAECn8/AAIgAAkJUxlEFAApAgAgAAkJUxlEFAApAgAAAA==.Sauceguzzler:BAAALgAECgYJBgAAAA==.Savath:BAAALgADCgYJBgAAAA==.',
Se='Selenagomes:BAAALgAECgEJAQABLgAFFAQJCAAkAIIfAA==.Selenor:BAAALgAECgQJBwAAAA==.Seragaki:BAABLgAECn8jAAMTAAkJRRrLDACUAgATAAkJRRrLDACUAgAUAAYJgxCoOwAbAQAAAA==.Seraphinna:BAAALgADCgEJAQAAAA==.',
Si='Siegescale:BAAALgADCgYJCgAAAA==.Siegrorc:BAABLgAECn86AAIJAAkJWRQmDwDoAQAJAAkJWRQmDwDoAQAAAA==.Sillidari:BAAALgADCgQJBwAAAA==.Sindrila:BAAALgAECgYJCQAAAA==.Sionshope:BAAALgAECgUJCQAAAA==.',
Sk='Skragar:BAAALgAECgEJAgAAAA==.',
Sl='Slayerhunt:BAABLgAECn8VAAQZAAYJ/AxmMAAhAQAZAAYJ2wtmMAAhAQAFAAQJywvegQDiAAAlAAIJqQwGeABgAAAAAA==.Slayerlock:BAAALgAECgIJAgAAAA==.Slayertin:BAAALgAECgYJCwABLgAECgYJFQAZAPwMAA==.',
Sm='Smallpox:BAAALgAECgQJBAAAAA==.',
Sn='Snibdru:BAAALgAECgcJBgAAAA==.Snkrsotoole:BAABLgAECn8cAAIPAAYJgw59UgDdAAAPAAYJgw59UgDdAAAAAA==.',
So='Soobz:BAAALgADCgYJBgAAAA==.Sorian:BAAALgAECgUJCQAAAA==.Soulkings:BAAALgADCggJDwAAAA==.Soupies:BAAALgAECgQJBQAAAA==.Soxa:BAAALgADCgIJAgAAAA==.',
Sp='Spiikee:BAAALgAECgIJAgAAAA==.Sprays:BAAALgAECgQJBAAAAA==.',
Sr='Sry:BAAALgAECgYJBAAAAA==.',
St='Steady:BAABLgAECn8ZAAIHAAcJbhUokQBEAQAHAAcJbhUokQBEAQAAAA==.Stonehand:BAABLgAECn8tAAIUAAkJoBQ0GAD+AQAUAAkJoBQ0GAD+AQAAAA==.Stormsurge:BAAALgAECgMJAwAAAA==.Stownt:BAAALgADCgMJAwAAAA==.Stravas:BAAALgAECgcJBwAAAA==.Strongbow:BAABLgAECn8YAAIFAAgJDQlPaABmAQAFAAgJDQlPaABmAQAAAA==.',
Su='Subudai:BAAALgAECgkJEAAAAA==.Sugarboi:BAACLgAFFH8FAAInAAIJXwLPMABEAAAnAAIJXwLPMABEAAAuAAQKfy0AAicACQlwCrMkABkBACcACQlwCrMkABkBAAAA.Sugasuga:BAABLgAECn8VAAIHAAcJqh1CQAD7AQAHAAcJqh1CQAD7AQAAAA==.Sunnymuffins:BAAALgADCgYJBQAAAA==.',
Sv='Sveetka:BAAALgAECgMJBAAAAA==.',
Sx='Sxytrev:BAAALgAECgQJCQAAAA==.',
Ta='Tabi:BAAALgADCgQJBgAAAA==.Tacoy:BAABLgAECn8fAAIKAAgJxRZkKwCgAQAKAAgJxRZkKwCgAQAAAA==.Tagsy:BAABLgAECn8VAAIFAAgJxRZdOQDJAQAFAAgJxRZdOQDJAQAAAA==.Tay:BAAALgAECgcJCwAAAA==.Tayna:BAAALgADCgYJBgAAAA==.',
Tb='Tbizkut:BAABLgAECn9GAAIWAAkJIRDBCQCbAQAWAAkJIRDBCQCbAQAAAA==.',
Th='Then:BAABLgAECn8pAAIEAAcJSBnHaQChAQAEAAcJSBnHaQChAQAAAA==.Threetimez:BAABLgAECn8VAAIFAAcJJAyrdgBGAQAFAAcJJAyrdgBGAQAAAA==.Thumbmage:BAABLgAECn8UAAIEAAYJxCChUgDeAQAEAAYJxCChUgDeAQABLgAFFAQJCgAPAIUfAA==.',
Ti='Timemaster:BAABLgAECn8eAAMkAAYJwhuTHACHAQAkAAYJwhuTHACHAQALAAIJnQMT1wBCAAAAAA==.Timepacifist:BAAALgAECgcJCgAAAA==.',
To='Tobeybey:BAAALgAECgIJAgAAAA==.Tokido:BAAALgAFFAEJAQAAAA==.Tongpakfu:BAABLgAECn8ZAAIMAAQJTRBragC7AAAMAAQJTRBragC7AAAAAA==.Topflight:BAAALgAECgcJEgAAAA==.',
Tr='Triggered:BAABLgAECn8bAAMHAAgJVBeZUQDsAQAHAAgJVBeZUQDsAQARAAEJ0AqlngAqAAAAAA==.Troiikâ:BAABLgAECn9CAAQSAAkJphQEEADFAQASAAkJphQEEADFAQAHAAcJNgfIxAD1AAARAAUJ8QKQZwCJAAAAAA==.Troikkâ:BAAALgADCgQJBAAAAA==.Troikâ:BAAALgADCgYJBwAAAA==.Trroikâ:BAABLgAECn8uAAIJAAgJGBLhGwBMAQAJAAgJGBLhGwBMAQAAAA==.',
Tt='Tteeffinn:BAAALgADCgYJBgAAAA==.Ttevinn:BAAALgAECgMJBAABLgAECgkJBwAGAAAAAA==.Ttevoker:BAAALgAECgkJBwAAAA==.',
Tu='Tulvie:BAAALgADCgQJCAAAAA==.Tummytickle:BAAALgAECgEJAQAAAA==.Tupacaroni:BAAALgAECgMJAwAAAA==.',
Ty='Tycone:BAAALgAECgcJCgAAAA==.',
Ul='Uldirtydruid:BAABLgAECn8qAAIDAAgJ6B6GEADFAgADAAgJ6B6GEADFAgAAAA==.',
Ur='Urukdrak:BAABLgAECn8kAAMZAAkJJw17HQCsAQAZAAkJkAl7HQCsAQAlAAgJiQ3iMwCcAQAAAA==.',
Uw='Uwantwar:BAAALgAECgUJDAAAAA==.',
Va='Valanquishy:BAAALgADCgEJAgAAAA==.',
Ve='Velaryon:BAAALgAECgQJBAAAAA==.',
Vh='Vhagar:BAAALgAECgIJAwAAAA==.',
Vi='Vidich:BAAALgAFFAEJAQAAAA==.Viralus:BAAALgADCgEJAQAAAA==.',
Vo='Vodka:BAAALgAECgEJAgAAAA==.Voiddastard:BAAALgADCgkJFwAAAA==.Voidlight:BAAALgADCgcJBwAAAA==.Volcazzic:BAAALgADCgIJAgAAAA==.',
Vy='Vynnara:BAAALgADCgMJAQAAAA==.',
Wa='Wakkaba:BAAALgADCgYJBgAAAA==.Wanaatlarboy:BAABLgAECn8mAAMUAAgJzxKQIwCkAQAUAAgJzxKQIwCkAQATAAEJ7gH4XgAiAAAAAA==.Waywyrd:BAAALgADCgMJAwAAAA==.',
Wh='Whack:BAAALgADCgcJCAAAAA==.',
Wi='Willowëd:BAAALgAECgkJBAAAAA==.',
Wu='Wunderbar:BAABLgAECn8eAAIQAAYJKxt8SQB7AQAQAAYJKxt8SQB7AQAAAA==.Wunderburger:BAAALgAECgYJEQAAAA==.Wunderground:BAAALgAECgYJDwAAAA==.',
Xa='Xannada:BAABLgAECn9CAAIHAAkJmxIbSADjAQAHAAkJmxIbSADjAQAAAA==.',
Xe='Xenztrazlu:BAAALgAECgQJBQABLgAECgYJEQAGAAAAAA==.',
Ya='Yaoli:BAAALgAECgMJBAAAAA==.',
Ye='Yea:BAAALgADCgcJCwAAAA==.',
Yo='Yodadogownz:BAABLgAECn8TAAIUAAcJ7xClMABTAQAUAAcJ7xClMABTAQAAAA==.Yoh:BAACLgAFFH8OAAIOAAQJ7w9VagAcAQAOAAQJ7w9VagAcAQAuAAQKfxwAAg4ACAlKHXQ+AAACAA4ACAlKHXQ+AAACAAAA.Yourenotron:BAAALgAECgEJAgAAAA==.',
Yu='Yungdro:BAAALgAECgEJAQAAAA==.',
Za='Zarutobi:BAAALgAECgYJEgABLgAECggJGQAIANYXAA==.',
Zo='Zob:BAAALgADCgQJBAAAAA==.',
Zu='Zui:BAABLgAECn8pAAIXAAkJahLhGgDGAQAXAAkJahLhGgDGAQAAAA==.',
['Zù']='Zùg:BAAALgADCgIJAQAAAA==.',
['Ðo']='Ðongknight:BAAALgAFFAIJAgABLgAFFAQJDgAKANAZAA==.',
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
