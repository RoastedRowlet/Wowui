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

local lookup = {'Warlock-Affliction','Warlock-Demonology','Druid-Restoration','Mage-Frost','Hunter-BeastMastery','Unknown-Unknown','Paladin-Retribution','Druid-Balance','Warrior-Protection','Warrior-Fury','Monk-Mistweaver','Warrior-Arms','Shaman-Elemental','Shaman-Restoration','Paladin-Holy','Paladin-Protection','Priest-Discipline','Priest-Shadow','Shaman-Enhancement','Warlock-Destruction','Monk-Brewmaster','Monk-Windwalker','Hunter-Survival','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Rogue-Subtlety','Rogue-Assassination','Druid-Feral','Priest-Holy','DemonHunter-Devourer','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Vengeance','DemonHunter-Havoc','Hunter-Marksmanship','Mage-Arcane','Druid-Guardian',}
local provider = {region='US',realm='DarkIron',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aanx:BAABLgAECn8ZAAMBAAYJth2cFgDrAAACAAYJth2WeQA7AQABAAQJQhmcFgDrAAAAAA==.',
Ab='Abadon:BAAALgAECgQJBgABLgAFFAEJBQADAEcUAA==.Abdorei:BAABLgAECn8wAAIEAAgJUhbgWQC3AQAEAAgJUhbgWQC3AQAAAA==.Absorboat:BAAALgADCgYJCAAAAA==.',
Ac='Accilatem:BAABLgAECn8aAAIFAAcJQh4nHgBRAgAFAAcJQh4nHgBRAgABLgAECgkJIgAEAHIZAA==.Accilatim:BAABLgAECn8iAAIEAAkJchntKQBcAgAEAAkJchntKQBcAgAAAA==.',
Ad='Adonsina:BAAALgAECgEJAQABLgAECgkJCwAGAAAAAA==.',
Ae='Aether:BAAALgAECgMJAwAAAA==.',
Ag='Agrromagnet:BAABLgAECn8oAAIHAAkJahhVNgBJAgAHAAkJahhVNgBJAgAAAA==.',
Ai='Aiba:BAABLgAECn8ZAAIIAAgJ1hc0GwDXAQAIAAgJ1hc0GwDXAQAAAA==.',
Ak='Akcloud:BAABLgAFFH8LAAMJAAQJmhu2DgAkAQAJAAQJFhi2DgAkAQAKAAEJ2yPTHQBoAAAAAA==.',
Al='Alab:BAAALgAECgEJAgAAAA==.Alaeris:BAACLgAFFH8MAAILAAQJnBbuIAASAQALAAQJnBbuIAASAQAuAAQKfyAAAgsACAlPH3cOAJYCAAsACAlPH3cOAJYCAAAA.Albetabeef:BAACLgAFFH8JAAMMAAQJGxQwEgAhAQAMAAQJGxQwEgAhAQAKAAIJJgZQHACUAAAuAAQKfxgAAwwACAn/IOgIAEcCAAoABwk2ICAWAJwCAAwABwmjIugIAEcCAAAA.Alexei:BAAALgAECgkJDQAAAA==.Aleyeah:BAAALgAECgUJCgABLgAECggJNwANAPsgAA==.Allhopeisded:BAABLgAECn8UAAIOAAYJog5eagD9AAAOAAYJog5eagD9AAAAAA==.Alurelor:BAAALgAECggJDAAAAA==.Alyreu:BAAALgAECgQJBAABLgAECgYJDQAGAAAAAA==.',
Am='Amanita:BAAALgADCgkJCQAAAA==.Amarah:BAAALgADCgYJBgAAAA==.Amelaista:BAABLgAECn81AAIOAAgJBQ1GSgBpAQAOAAgJBQ1GSgBpAQAAAA==.',
An='Anddi:BAAALgAECgEJAwAAAA==.Andii:BAACLgAFFH8HAAIPAAMJMBvOIwDsAAAPAAMJMBvOIwDsAAAuAAQKfxgABA8ACAnIF38/AHoBAA8ABwnQFn8/AHoBAAcAAgm2B3uKASkAABAAAQkAAOBXAAAAAAAA.Andy:BAACLgAFFH8FAAIRAAMJHgqkKwC8AAARAAMJHgqkKwC8AAAuAAQKfxQAAxEACAkoHw0KALMCABEACAkoHw0KALMCABIAAQkXB0l+ACwAAAAA.Angusbeef:BAAALgADCgQJBAAAAA==.Antipus:BAAALgAECgQJBQAAAA==.',
Ao='Aoibhoker:BAAALgAECgQJBAABLgAECgkJMgATAIoiAA==.',
Ar='Arclo:BAAALgADCgYJBgAAAA==.Arden:BAAALgAECgQJBAABLgAECgYJFwAUANsWAA==.Ardeno:BAABLgAECn8XAAMUAAYJ2xarIwA7AQAUAAYJbwyrIwA7AQACAAUJ2xajkwAKAQAAAA==.Ardon:BAABLgAECn8sAAMOAAkJ8hrIEACxAgAOAAkJ8hrIEACxAgANAAUJvhsbMQCaAQAAAA==.Armis:BAAALgADCgUJBQAAAA==.',
As='Asteruis:BAABLgAECn8kAAIFAAkJDh4OIwBAAgAFAAkJDh4OIwBAAgAAAA==.',
Av='Avenayra:BAAALgAECgIJAwAAAA==.',
Ay='Ayroon:BAAALgAECgEJAQAAAA==.',
Ba='Baddhealer:BAAALgADCgUJBQAAAA==.Badfurion:BAAALgADCggJCgAAAA==.Balthamel:BAAALgAECgYJDAAAAA==.Bananafang:BAAALgAECgQJBgAAAA==.Bananashoes:BAAALgAECgMJAgAAAA==.Bangerz:BAACLgAFFH84AAIPAAgJeg9sBgAnAgAPAAgJeg9sBgAnAgAuAAQKfzwAAw8ACQlmILMIAOMCAA8ACQlmILMIAOMCAAcAAQm4AedYASYAAAAA.Barkendremix:BAABLgAECn80AAMVAAkJYRuhCgB5AgAVAAkJYRuhCgB5AgAWAAEJFBX0gQA+AAAAAA==.Bathsheber:BAAALgAFFAEJAQABLgAFFAcJGAAEANsiAA==.Baulbuster:BAAALgAECgYJBwAAAA==.',
Be='Beanieweenie:BAAALgADCgEJAQAAAA==.Beerez:BAAALgADCgcJDQAAAA==.Belroy:BAABLgAECn8fAAIXAAYJKBPwKABIAQAXAAYJKBPwKABIAQAAAA==.Beriothien:BAAALgAECgEJAQAAAA==.',
Bj='Bjorum:BAACLgAFFH8GAAITAAMJsR20CQD3AAATAAMJsR20CQD3AAAuAAQKfyMAAxMACQmVInEFAHgCABMACQmVInEFAHgCAA0AAQnhCLaQACcAAAAA.',
Bo='Bodytwodafa:BAACLgAFFH8NAAMYAAQJShTTAwA2AQAYAAQJQhHTAwA2AQAZAAMJDA9LOgC7AAAuAAQKfyAABBgACAntIBgGAJUCABgACAkhHhgGAJUCABoABgn4GBgQALYBABkABwlwGJIoAIUBAAAA.Bournemaad:BAAALgADCgMJAwAAAA==.Boyafu:BAAALgAECgEJAQAAAA==.',
Br='Brucecampbel:BAAALgAECgMJCQAAAA==.',
Bu='Bubbleyou:BAABLgAECn8ZAAMQAAYJZBBfJQDPAAAQAAYJZBBfJQDPAAAHAAIJuwoThQErAAAAAA==.Burnek:BAAALgAECgIJBAABLgAECgYJEwAGAAAAAA==.',
Ca='Cantarella:BAABLgAECn8xAAMbAAgJRAYcJgBIAQAbAAgJRAYcJgBIAQAcAAcJ2QLxFADFAAAAAA==.Carlyle:BAABLgAECn8pAAMHAAkJgxuLHwBzAgAHAAkJgxuLHwBzAgAPAAIJUx5kWwCtAAAAAA==.Catdaddy:BAAALgADCgYJBwAAAA==.',
Ch='Checkmybio:BAAALgAECgQJBQAAAA==.Cheekyteetah:BAAALgAECgEJAQAAAA==.Cheesecake:BAAALgADCgUJBQAAAA==.Chromehound:BAAALgADCgQJBAAAAA==.Chumdungler:BAAALgAECgMJAwAAAA==.',
Ci='Cindervis:BAAALgADCgYJBgAAAA==.',
Cl='Clonk:BAAALgAECgUJBgAAAA==.',
Co='Collossuss:BAAALgAECgYJEwAAAA==.Convik:BAAALgAECgcJBwAAAA==.',
Cr='Cregga:BAAALgADCgEJAQAAAA==.Crimsonagony:BAAALgADCgUJBQAAAA==.Crosshairs:BAAALgADCgMJAwAAAA==.',
Cu='Cuddles:BAAALgADCgUJBQAAAA==.Curacao:BAABLgAECn8YAAIKAAcJAhSqNgBYAQAKAAcJAhSqNgBYAQAAAA==.',
Cy='Cynnari:BAAALgAECgYJDQAAAA==.',
Da='Dabtime:BAABLgAECn8hAAIHAAgJJBPacgCWAQAHAAgJJBPacgCWAQAAAA==.Darkstarr:BAAALgAECgQJBgAAAA==.',
De='Deathknightm:BAAALgAECgIJAgABLgAECgkJHAAJAHYVAA==.Dekaar:BAABLgAECn8bAAIdAAYJuwmmIgDMAAAdAAYJuwmmIgDMAAAAAA==.Demonknight:BAAALgAECgEJAQAAAA==.Deracine:BAAALgAECgcJCgAAAA==.Derek:BAAALgAECgcJCAAAAA==.Desdemonica:BAABLgAECn8dAAIFAAgJ6AjlZQBfAQAFAAgJ6AjlZQBfAQAAAA==.',
Di='Diegoknight:BAAALgADCgEJAgAAAA==.Diggle:BAAALgADCggJCAAAAA==.Dilvdrood:BAAALgADCgUJBQAAAA==.Dilvish:BAAALgAECgYJEgAAAA==.',
Do='Doctrwho:BAAALgADCgIJAgAAAA==.Dohaeris:BAABLgAECn8yAAIeAAkJ9xNCGgDgAQAeAAkJ9xNCGgDgAQAAAA==.Domain:BAABLgAECn8eAAIfAAgJUBjiNwDQAQAfAAgJUBjiNwDQAQAAAA==.Donfalprun:BAABLgAECn8gAAIHAAkJICPSCQAFAwAHAAkJICPSCQAFAwAAAA==.Doomstout:BAABLgAECn8WAAIEAAgJSBJwbQCGAQAEAAgJSBJwbQCGAQAAAA==.',
Dr='Draconus:BAABLgAECn8zAAMgAAkJfhVnDwD4AQAgAAkJUBNnDwD4AQAhAAQJcRuI1wDFAAAAAA==.Dralas:BAAALgAECgYJCwAAAA==.',
Du='Duro:BAAALgAECgYJDAABLgAECgYJDAAGAAAAAA==.Durto:BAAALgADCgMJAwABLgAECgQJCAAGAAAAAA==.Duskshade:BAAALgAECgQJBAAAAA==.',
['Dü']='Düsk:BAABLgAECn8VAAIhAAkJOQc5awB7AQAhAAkJOQc5awB7AQAAAA==.',
Ea='Eachan:BAAALgAECgMJAwAAAA==.',
El='Elij:BAACLgAFFH8JAAICAAQJYRjBNABPAQACAAQJYRjBNABPAQAuAAQKfx8AAgIACAmJHnodAGUCAAIACAmJHnodAGUCAAAA.Elunaire:BAACLgAFFH8FAAIDAAEJRxTBXgBCAAADAAEJRxTBXgBCAAAuAAQKfxwAAgMACQkCHJIdAFECAAMACQkCHJIdAFECAAAA.',
Em='Emelec:BAAALgAECgIJAgAAAA==.Emeraldwish:BAACLgAFFH8NAAIDAAQJliAFGQByAQADAAQJliAFGQByAQAuAAQKfx0AAwMACAmlI2sGACUDAAMACAmlI2sGACUDAAgAAQkAAFOdAAAAAAAA.',
Er='Eraline:BAAALgADCgYJBgAAAA==.Erthnite:BAAALgAECgQJBAAAAA==.',
Ev='Evinco:BAABLgAECn8aAAIUAAkJhBA1EgAKAQAUAAkJhBA1EgAKAQAAAA==.Evy:BAAALgAECgEJAgAAAA==.',
Ex='Executie:BAACLgAFFH8ZAAMMAAcJAxSpBQDAAQAMAAcJAxSpBQDAAQAKAAMJGQzSEgDvAAAuAAQKfyYAAwwACQngG3gGAGQCAAwACQnLGngGAGQCAAoABglLHFw1ANQBAAAA.',
Fa='Falin:BAAALgAECgEJAQAAAA==.Fancy:BAAALgAECgYJBQAAAA==.',
Fe='Fey:BAABLgAECn8iAAICAAkJ5BObQwDFAQACAAkJ5BObQwDFAQAAAA==.',
Fi='Fieryember:BAAALgAECgQJBQABLgAECgYJEwAGAAAAAA==.Fistvendor:BAABLgAECn8UAAIVAAkJxAjoJwBgAQAVAAkJxAjoJwBgAQAAAA==.',
Fl='Flasheals:BAABLgAECn8pAAIPAAkJ5RBKJQDHAQAPAAkJ5RBKJQDHAQAAAA==.Flatpak:BAAALgADCgEJAgAAAA==.Flobglop:BAAALgAECgEJAQAAAA==.Fluffybum:BAAALgADCgEJAQAAAA==.',
Fo='Foxtrot:BAABLgAECn8gAAIFAAgJOhpOKAAnAgAFAAgJOhpOKAAnAgAAAA==.',
Fr='Frenzaoibh:BAAALgAECgYJCgABLgAECgkJMgATAIoiAA==.Frostine:BAABLgAECn8ZAAIEAAcJtQdC1QBEAQAEAAcJtQdC1QBEAQAAAA==.Frostwave:BAABLgAECn8+AAMgAAgJ/yBxCgBSAgAgAAgJwR1xCgBSAgAiAAgJ1R5ZBgAUAgAAAA==.Frostythot:BAAALgADCgIJAgAAAA==.',
Fu='Fujiyama:BAABLgAECn83AAINAAgJ+yBeCwCXAgANAAgJ+yBeCwCXAgAAAA==.Furryweasal:BAAALgADCgEJAQAAAA==.',
Ga='Garrex:BAAALgADCgUJBQABLgAECggJFQAFAMUWAA==.Garréosh:BAAALgAECgUJCgABLgAFFAMJDQAHAN4YAA==.',
Ge='Geodude:BAAALgADCgYJBwAAAA==.',
Gi='Gibborim:BAAALgAECgYJCwAAAA==.Gigilomann:BAAALgAECgIJBAAAAA==.',
Gl='Glenndanzig:BAAALgADCgYJBgAAAA==.',
Go='Goldenshield:BAAALgAECgMJCQAAAA==.Golteb:BAAALgAECgQJBAAAAA==.Gonecrazy:BAAALgADCgMJAwAAAA==.Gorthan:BAAALgADCgQJBgAAAA==.',
Gr='Grabandgank:BAAALgADCgYJBgAAAA==.Groggi:BAAALgAECgYJBAAAAA==.',
Gu='Guaresux:BAEALgADCgEJAQABLgAECggJGAALABkSAA==.Gurnisson:BAAALgADCgUJBQAAAA==.Gusto:BAABLgAECn8uAAQZAAkJ6AuBKgB5AQAZAAkJXQuBKgB5AQAaAAgJegMoHQD/AAAYAAcJwQcFFAC4AAAAAA==.',
Ha='Hadouken:BAABLgAECn8UAAIHAAkJ5wAxiwEpAAAHAAkJ5wAxiwEpAAAAAA==.Hafsak:BAAALgAECgUJBQAAAA==.Halppme:BAAALgADCgcJBwAAAA==.Hammerfall:BAAALgAECgQJBAAAAA==.Handsome:BAAALgAECgcJBwAAAA==.',
He='Headshotte:BAAALgAECgYJDAAAAA==.Heatindabs:BAABLgAECn8gAAIDAAkJpg5cRQBnAQADAAkJpg5cRQBnAQAAAA==.Hexed:BAAALgAECgQJCgAAAA==.',
Hi='Hinael:BAAALgAECgEJAQAAAA==.',
Ho='Holyknight:BAAALgAECgYJDgAAAA==.Holymama:BAABLgAECn8gAAMSAAgJeh2pFgD4AQASAAcJdCCpFgD4AQARAAIJIRNLVQB1AAAAAA==.',
Hu='Hunkwai:BAAALgAFFAIJAgAAAA==.',
Ib='Ibok:BAAALgAECgYJCgAAAA==.',
Ic='Ickma:BAABLgAECn9AAAIhAAgJQCDxIwBhAgAhAAgJQCDxIwBhAgAAAA==.',
Id='Iddou:BAAALgAECgMJBAAAAA==.',
Ik='Ikona:BAAALgADCggJDgAAAA==.',
Im='Impgobrr:BAAALgAECgEJAQAAAA==.Imu:BAAALgADCggJDgAAAA==.',
In='Incubus:BAAALgADCgEJAgAAAA==.Infari:BAAALgAECgQJBAAAAA==.',
Ir='Irdeldran:BAAALgAECgEJAQAAAA==.',
Ja='Jabjek:BAAALgADCgYJCwAAAA==.Jamaz:BAAALgAECgQJBAAAAA==.Jamwich:BAAALgADCgYJBgAAAA==.Jasonmoloa:BAAALgAECgYJDgAAAA==.',
Je='Jerazia:BAAALgAECgYJBQAAAA==.',
Jo='Johanx:BAAALgADCgMJAwAAAA==.Jordananon:BAAALgAECgMJAwAAAA==.Jordanian:BAAALgAECgMJAwAAAA==.',
['Jî']='Jînxy:BAAALgAECgEJAwAAAA==.',
Ka='Kanamé:BAAALgAECgEJAQAAAA==.Kaollanna:BAABLgAECn8jAAIEAAkJDhYWWQAuAgAEAAkJDhYWWQAuAgAAAA==.Karik:BAAALgAECgQJDQAAAA==.Kaven:BAAALgADCgIJAgAAAA==.',
Ke='Kehma:BAAALgAECgEJAQAAAA==.Kelisa:BAABLgAECn8uAAIHAAkJPx0CIQBsAgAHAAkJPx0CIQBsAgAAAA==.Ketchuptits:BAAALgADCgYJBgAAAA==.',
Ki='Kimjunggheal:BAAALgAECgMJBgAAAA==.Kinkster:BAAALgAECgYJCwABLgAECgYJDQAGAAAAAA==.Kinza:BAAALgADCgkJCQABLgAECggJGQAIANYXAA==.Kiwidin:BAABLgAECn8gAAIPAAkJuhXmJgDzAQAPAAkJuhXmJgDzAQAAAA==.',
Ko='Koketsu:BAAALgAECgYJDAAAAA==.',
Kr='Krinxy:BAABLgAECn8VAAIDAAUJFhqSWwA/AQADAAUJFhqSWwA/AQAAAA==.',
Ks='Kschwev:BAAALgADCgYJBgAAAA==.',
Ku='Kuratcha:BAAALgAECgUJCgABLgAECgYJEwAGAAAAAA==.',
Ky='Kylee:BAAALgAECgkJAQAAAA==.Kyý:BAAALgAECgYJDwAAAA==.',
['Kí']='Kíng:BAAALgAECgYJEwAAAA==.',
La='Lazyde:BAAALgAECggJCwABLgAECggJOAAjANEiAA==.',
Le='Ledgerfeign:BAABLgAECn8qAAICAAkJDg3mSQCxAQACAAkJDg3mSQCxAQAAAA==.',
Li='Liadan:BAABLgAECn8bAAIPAAgJXgvHMQB6AQAPAAgJXgvHMQB6AQAAAA==.Lighteye:BAABLgAECn9AAAIDAAgJxBr7FwBzAgADAAgJxBr7FwBzAgAAAA==.Lilmudatruka:BAAALgADCgEJAQABLgAECgYJFAAOAKIOAA==.',
Lo='Longestibrow:BAAALgAECgMJBQAAAA==.',
Lu='Luminescence:BAAALgADCgQJBgAAAA==.Lunarqt:BAAALgAECgEJAQAAAA==.Lunchy:BAAALgAECgYJCQAAAA==.',
Ly='Lyllow:BAABLgAECn8UAAIaAAYJDhOzGAA1AQAaAAYJDhOzGAA1AQAAAA==.',
['Lø']='Løurent:BAAALgADCgQJBAAAAA==.',
Ma='Magicdorf:BAACLgAFFH8FAAIEAAIJxBTniQCaAAAEAAIJxBTniQCaAAAuAAQKfywAAgQACQlMIQcTANMCAAQACQlMIQcTANMCAAAA.Malphasia:BAAALgADCgYJBgAAAA==.Manhitrogue:BAAALgAECgQJBAAAAA==.Massivebicep:BAAALgAECgIJAgAAAA==.Mavras:BAAALgADCgEJAQAAAA==.',
Mc='Mcbraintumor:BAAALgAECgQJBwAAAA==.Mcsleuth:BAAALgAECgQJBgAAAA==.',
Me='Megarayquaza:BAACLgAFFH8KAAIfAAMJrAVDYACsAAAfAAMJrAVDYACsAAAuAAQKfx8AAyQACAkqEmseAMwBACQACAnIC2seAMwBAB8ACAk1EQNYAGYBAAAA.',
Mi='Mikeyouk:BAAALgADCgYJBgAAAA==.Misties:BAAALgAECgEJAQAAAA==.',
Mo='Moargoth:BAAALgADCgUJEAAAAA==.Mooneater:BAAALgAECgYJCAAAAA==.Moosedon:BAAALgAECgEJAgABLgAECgkJIAAHACAjAA==.Mordorl:BAAALgADCgcJBwAAAA==.',
Mt='Mtt:BAAALgADCgkJDgAAAA==.',
Mx='Mxx:BAABLgAECn8XAAQFAAUJbiC9TQCAAQAFAAUJbiC9TQCAAQAXAAMJMxTsRwB+AAAlAAEJzAMGlgAjAAAAAA==.',
My='Mylianne:BAABLgAECn8aAAIIAAcJYhw+GgDfAQAIAAcJYhw+GgDfAQAAAA==.Mynameiscole:BAACLgAFFH8IAAIkAAQJgh98AQCSAQAkAAQJgh98AQCSAQAuAAQKfyMAAiQACAmZJq4BAIoDACQACAmZJq4BAIoDAAEuAAUUBgkTAB8AiR0A.Myrolan:BAABLgAECn8tAAIkAAkJCCRhAgAqAwAkAAkJCCRhAgAqAwAAAA==.Myrtru:BAAALgAECgkJCgAAAA==.',
['Mí']='Míyagi:BAAALgAECgYJBgAAAA==.',
Na='Naturallight:BAAALgADCgUJCAAAAA==.',
Ne='Neechka:BAAALgADCgUJBQAAAA==.Neosan:BAAALgADCgYJBgABLgAFFAMJCgAIAOciAA==.Nevyn:BAABLgAECn8fAAImAAgJBxQeBACpAQAmAAgJBxQeBACpAQAAAA==.Newface:BAAALgADCgEJAgAAAA==.Newmoo:BAAALgAECgEJAQAAAA==.',
Ni='Nightsage:BAAALgAECgUJCQAAAA==.Niji:BAAALgAECgQJCAABLgAECggJGQAIANYXAA==.Nininhp:BAAALgAECgUJDwABLgAECgYJDQAGAAAAAA==.Nithari:BAABLgAECn82AAIEAAgJgCHoIgB7AgAEAAgJgCHoIgB7AgAAAA==.',
No='Nobel:BAAALgADCgEJAQAAAA==.Nomanai:BAAALgADCgkJAwAAAA==.Nosst:BAAALgAECgMJBQAAAA==.Nost:BAAALgADCgcJBwAAAA==.Nostu:BAABLgAECn8hAAMRAAkJsBaxEwAiAgARAAkJsBaxEwAiAgASAAEJbhCEcwA3AAAAAA==.Now:BAACLgAFFH8NAAIHAAQJ+h4VGwB1AQAHAAQJ+h4VGwB1AQAuAAQKfx8AAwcACAkQIOAtAGsCAAcACAlPHuAtAGsCABAABgmIF5MZADMBAAAA.',
Nu='Nukum:BAAALgAECgYJEAABLgAECggJGAAFANYZAA==.',
Oh='Ohpa:BAABLgAECn8lAAMCAAgJohSwPwDRAQACAAgJohSwPwDRAQABAAMJhwhBKgBbAAAAAA==.Ohrly:BAAALgAECgEJAQAAAA==.',
Oj='Ojikan:BAABLgAECn8WAAIdAAgJvSKkAwD2AgAdAAgJvSKkAwD2AgAAAA==.Ojpriest:BAAALgAFFAMJAwAAAA==.',
Pa='Pallykera:BAAALgAECgEJAQAAAA==.Papamush:BAAALgAECgMJBQAAAA==.Pathogenn:BAAALgAECgYJEAAAAA==.',
Pe='Pepecry:BAAALgAECgUJDgABLgAECgYJEwAGAAAAAA==.',
Ph='Phoblade:BAABLgAECn8mAAIhAAgJNhbdSADVAQAhAAgJNhbdSADVAQAAAA==.Phobreeze:BAAALgAECgIJAgAAAA==.Phokk:BAAALgAECgcJBwAAAA==.',
Pi='Pirotess:BAAALgAECgYJDgAAAA==.',
Po='Pollymorphh:BAAALgADCgUJBQAAAA==.Ponylion:BAAALgAECgYJCwABLgAECgcJEQAGAAAAAA==.Pooshka:BAABLgAECn8dAAINAAkJSCJiCgDvAgANAAkJSCJiCgDvAgAAAA==.Popz:BAAALgAECgEJAQAAAA==.',
Pr='Preorcthego:BAACLgAFFH8WAAIXAAQJ4yZBAwDIAQAXAAQJ4yZBAwDIAQAuAAQKfykAAxcACAlqJpcAAIsDABcACAlqJpcAAIsDACUAAQm/JHV7AFUAAAEuAAUUBgkbACEAHyEA.Presibro:BAABLgAECn8XAAIJAAYJPyATEQDBAQAJAAYJPyATEQDBAQAAAA==.Presiric:BAAALgAECgMJAwAAAA==.Presisarian:BAAALgAECgYJDwAAAA==.',
Pu='Puck:BAAALgAECgYJDQAAAA==.Puppye:BAACLgAFFH8MAAIFAAQJARrsJgBJAQAFAAQJARrsJgBJAQAuAAQKfxgAAgUACAlNHKgrABgCAAUACAlNHKgrABgCAAAA.',
Ra='Ranalia:BAAALgADCgQJBAAAAA==.Ranouu:BAABLgAECn8VAAIEAAYJIBW8nACcAQAEAAYJIBW8nACcAQAAAA==.Ratatatatt:BAAALgADCgQJBQAAAA==.',
Re='Reaoibher:BAAALgADCgMJAwABLgAECgkJMgATAIoiAA==.Recision:BAABLgAECn84AAIjAAgJ0SIiAwCfAgAjAAgJ0SIiAwCfAgAAAA==.Reeash:BAABLgAECn8XAAMOAAkJABehIAAyAgAOAAkJABehIAAyAgANAAMJyAt3bQCAAAAAAA==.Reeatar:BAABLgAECn8ZAAIEAAcJ5Rg9oACWAQAEAAcJ5Rg9oACWAQABLgAECgkJFwAOAAAXAA==.Relindor:BAAALgADCgYJBgABLgAFFAQJCAAhAJwSAA==.Revelle:BAAALgAECgkJCwAAAA==.',
Rh='Rheizen:BAABLgAECn8tAAIJAAcJGxWGFQCFAQAJAAcJGxWGFQCFAQAAAA==.',
Ri='Riptide:BAAALgAECgEJAQAAAA==.',
Ro='Ron:BAAALgADCgQJBAAAAA==.Ropopo:BAABLgAECn8fAAIRAAgJtxkOFgAHAgARAAgJtxkOFgAHAgABLgAFFAQJDAAFAAEaAA==.',
Ru='Runcat:BAABLgAECn8XAAMfAAgJQh76IQA1AgAfAAgJQh76IQA1AgAjAAQJ1Qb/HwCAAAAAAA==.',
['Rö']='Röyksopp:BAABLgAECn8cAAIEAAgJXwzNfQBhAQAEAAgJXwzNfQBhAQAAAA==.',
Sa='Sabo:BAAALgADCgQJBQAAAA==.Sakona:BAAALgADCgEJAQAAAA==.Salbahe:BAAALgAECgUJBQAAAA==.Samarah:BAAALgAECgcJCAAAAA==.Sandewor:BAABLgAECn8UAAQQAAYJ4RfgFwBFAQAQAAYJ4RfgFwBFAQAHAAMJ0QpYDAGHAAAPAAEJZgcDjQAoAAABLgAECgYJFQAXAPwMAA==.Sanfrancisco:BAAALgAECgIJAwABLgAECgIJAgAGAAAAAA==.Sarafyn:BAABLgAECn82AAIeAAgJ5hg5GgDgAQAeAAgJ5hg5GgDgAQAAAA==.Sauceguzzler:BAAALgAECgYJBgAAAA==.Savath:BAAALgADCgYJBgAAAA==.',
Se='Selenagomes:BAAALgAECgEJAQABLgAFFAYJEwAfAIkdAA==.Selenor:BAAALgAECgQJBwAAAA==.Seragaki:BAABLgAECn8hAAMRAAgJIRvREABGAgARAAgJIRvREABGAgASAAYJgxAROQAMAQAAAA==.Seraphinna:BAAALgADCgEJAQAAAA==.',
Si='Siegescale:BAAALgADCgQJBAAAAA==.Siegrorc:BAABLgAECn8xAAIJAAgJghKLFgB5AQAJAAgJghKLFgB5AQAAAA==.Sillidari:BAAALgADCgQJBwAAAA==.Sindrila:BAAALgAECgYJBwAAAA==.Sionshope:BAAALgAECgUJCQAAAA==.',
Sk='Skragar:BAAALgAECgEJAgAAAA==.',
Sl='Slayerhunt:BAABLgAECn8VAAQXAAYJ/Ax7LgAiAQAXAAYJ2wt7LgAiAQAFAAQJywvegQDiAAAlAAIJqQwGeABgAAAAAA==.Slayertin:BAAALgAECgYJCwABLgAECgYJFQAXAPwMAA==.',
Sn='Snibdru:BAAALgAECgcJBgAAAA==.Snkrsotoole:BAABLgAECn8cAAINAAYJgw6nTQDiAAANAAYJgw6nTQDiAAAAAA==.',
So='Soobz:BAAALgADCgYJBgAAAA==.Sorian:BAAALgAECgUJCQAAAA==.Soulkings:BAAALgADCggJDwAAAA==.Soupies:BAAALgAECgQJBQAAAA==.Soxa:BAAALgADCgIJAgAAAA==.',
Sp='Spiikee:BAAALgADCgQJBAAAAA==.Sprays:BAAALgAECgQJBAAAAA==.',
Sr='Sry:BAAALgAECgYJBAAAAA==.',
St='Steady:BAABLgAECn8YAAIHAAcJThXJigBAAQAHAAcJThXJigBAAQAAAA==.Stonehand:BAABLgAECn8tAAISAAkJoBSoFgD4AQASAAkJoBSoFgD4AQAAAA==.Stormsurge:BAAALgAECgMJAwAAAA==.Stownt:BAAALgADCgMJAwAAAA==.Stravas:BAAALgAECgcJBwAAAA==.Strongbow:BAAALgAECgYJDQAAAA==.',
Su='Subudai:BAAALgAECgkJEAAAAA==.Sugarboi:BAACLgAFFH8FAAInAAIJXwKwKQBHAAAnAAIJXwKwKQBHAAAuAAQKfy0AAicACQlwCishAB8BACcACQlwCishAB8BAAAA.Sugasuga:BAABLgAECn8VAAIHAAcJqh3KOwD8AQAHAAcJqh3KOwD8AQAAAA==.Sunnymuffins:BAAALgADCgYJBQAAAA==.',
Sv='Sveetka:BAAALgAECgMJBAAAAA==.',
Sx='Sxytrev:BAAALgAECgQJCQAAAA==.',
Ta='Tabi:BAAALgADCgQJBgAAAA==.Tacoy:BAABLgAECn8fAAIKAAgJxRYaKQCgAQAKAAgJxRYaKQCgAQAAAA==.Tagsy:BAABLgAECn8VAAIFAAgJxRZdOQDJAQAFAAgJxRZdOQDJAQAAAA==.Tay:BAAALgAECgcJCwAAAA==.Tayna:BAAALgADCgYJBgAAAA==.',
Tb='Tbizkut:BAABLgAECn8/AAIUAAgJnxDJCwBlAQAUAAgJnxDJCwBlAQAAAA==.',
Th='Then:BAABLgAECn8pAAIEAAcJSBnuYwCdAQAEAAcJSBnuYwCdAQAAAA==.Threetimez:BAABLgAECn8UAAIFAAcJJAxobwBKAQAFAAcJJAxobwBKAQAAAA==.Thumbmage:BAAALgAECgYJDgABLgAFFAMJBgANAL0iAA==.',
Ti='Timemaster:BAABLgAECn8eAAMkAAYJwhtoGgCKAQAkAAYJwhtoGgCKAQAfAAIJnQMT1wBCAAAAAA==.Timepacifist:BAAALgAECgcJCgAAAA==.',
To='Tokido:BAAALgAFFAEJAQAAAA==.Tongpakfu:BAABLgAECn8ZAAILAAQJTRB8YQC6AAALAAQJTRB8YQC6AAAAAA==.Topflight:BAAALgAECgcJEgAAAA==.',
Tr='Triggered:BAABLgAECn8bAAMHAAgJVBeZUQDsAQAHAAgJVBeZUQDsAQAPAAEJ0AqlngAqAAAAAA==.Troiikâ:BAABLgAECn9CAAQQAAkJphQEEADFAQAQAAkJphQEEADFAQAHAAcJNgf6vADvAAAPAAUJ8QK6YwCJAAAAAA==.Troikâ:BAAALgADCgYJBwAAAA==.Trroikâ:BAABLgAECn8rAAIJAAgJJhBgHQAvAQAJAAgJJhBgHQAvAQAAAA==.',
Tt='Tteeffinn:BAAALgADCgYJBgAAAA==.Ttevinn:BAAALgAECgMJBAABLgAECgkJBwAGAAAAAA==.Ttevoker:BAAALgAECgkJBwAAAA==.',
Tu='Tulvie:BAAALgADCgQJCAAAAA==.Tupacaroni:BAAALgAECgMJAwAAAA==.',
Ty='Tycone:BAAALgAECgcJCgAAAA==.',
Ul='Uldirtydruid:BAABLgAECn8qAAIDAAgJ6B6QDwDGAgADAAgJ6B6QDwDGAgAAAA==.',
Ur='Urukdrak:BAABLgAECn8kAAMXAAkJJw36GwCuAQAXAAkJkAn6GwCuAQAlAAgJiQ3iMwCcAQAAAA==.',
Uw='Uwantwar:BAAALgAECgUJCQAAAA==.',
Va='Valanquishy:BAAALgADCgEJAgAAAA==.',
Ve='Velaryon:BAAALgAECgQJBAAAAA==.',
Vh='Vhagar:BAAALgAECgIJAwAAAA==.',
Vi='Vidich:BAAALgAFFAEJAQAAAA==.Viralus:BAAALgADCgEJAQAAAA==.',
Vo='Vodka:BAAALgAECgEJAgAAAA==.Voiddastard:BAAALgADCgkJFwAAAA==.Voidlight:BAAALgADCgcJBwAAAA==.Volcazzic:BAAALgADCgIJAgAAAA==.',
Vy='Vynnara:BAAALgADCgMJAQAAAA==.',
Wa='Wakkaba:BAAALgADCgYJBgAAAA==.Wanaatlarboy:BAABLgAECn8eAAMSAAcJABFiLgBGAQASAAcJABFiLgBGAQARAAEJ7gH4XgAiAAAAAA==.Waywyrd:BAAALgADCgMJAwAAAA==.',
Wh='Whack:BAAALgADCgcJCAAAAA==.',
Wi='Willowëd:BAAALgAECgkJAwAAAA==.',
Wu='Wunderbar:BAABLgAECn8eAAIOAAYJKxtKRQB9AQAOAAYJKxtKRQB9AQAAAA==.Wunderburger:BAAALgAECgYJEQAAAA==.Wunderground:BAAALgAECgYJDgAAAA==.',
Xa='Xannada:BAABLgAECn85AAIHAAgJHRATaQCDAQAHAAgJHRATaQCDAQAAAA==.',
Xe='Xenztrazlu:BAAALgAECgQJAQABLgAECgYJDQAGAAAAAA==.',
Ya='Yaoli:BAAALgAECgMJBAAAAA==.',
Ye='Yea:BAAALgADCgcJCwAAAA==.',
Yo='Yodadogownz:BAABLgAECn8TAAISAAcJ7xCrLQBKAQASAAcJ7xCrLQBKAQAAAA==.Yoh:BAACLgAFFH8NAAIhAAQJ7w9UXwAeAQAhAAQJ7w9UXwAeAQAuAAQKfxwAAiEACAlKHZU6AAICACEACAlKHZU6AAICAAAA.Yourenotron:BAAALgAECgEJAgAAAA==.',
Yu='Yungdro:BAAALgAECgEJAQAAAA==.',
Za='Zarutobi:BAAALgAECgYJEgABLgAECggJGQAIANYXAA==.',
Zo='Zob:BAAALgADCgQJBAAAAA==.',
Zu='Zui:BAABLgAECn8pAAIVAAkJahKXGQDHAQAVAAkJahKXGQDHAQAAAA==.',
['Zù']='Zùg:BAAALgADCgIJAQAAAA==.',
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
