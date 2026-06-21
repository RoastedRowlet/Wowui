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

local lookup = {'Warlock-Affliction','Warlock-Demonology','Druid-Restoration','Mage-Frost','Hunter-BeastMastery','Unknown-Unknown','Paladin-Retribution','Druid-Balance','Warrior-Protection','Warrior-Fury','DemonHunter-Devourer','Monk-Mistweaver','Warrior-Arms','DeathKnight-Unholy','Shaman-Elemental','Shaman-Restoration','Paladin-Holy','Paladin-Protection','Priest-Discipline','Priest-Shadow','Shaman-Enhancement','Warlock-Destruction','Monk-Brewmaster','Monk-Windwalker','Hunter-Survival','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Rogue-Assassination','Rogue-Subtlety','Druid-Feral','Priest-Holy','DeathKnight-Blood','DeathKnight-Frost','DemonHunter-Havoc','Hunter-Marksmanship','Mage-Arcane','DemonHunter-Vengeance','Druid-Guardian',}
local provider = {region='US',realm='DarkIron',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aanx:BAABLgAECn8ZAAMBAAYJth3hGgDnAAACAAYJth2xgwAxAQABAAQJQhnhGgDnAAAAAA==.',
Ab='Abadon:BAAALgAECgQJBgABLgAFFAEJBgADAEcUAA==.Abdorei:BAACLgAFFH8KAAIEAAQJLQcwfgDaAAAEAAQJLQcwfgDaAAAuAAQKfz4AAgQACQnkF0Q2AEACAAQACQnkF0Q2AEACAAAA.Absorboat:BAAALgADCgYJCAAAAA==.',
Ac='Accilatem:BAABLgAECn8aAAIFAAcJQh4nHgBRAgAFAAcJQh4nHgBRAgABLgAECgkJIgAEAHIZAA==.Accilatim:BAABLgAECn8iAAIEAAkJchmmLwBaAgAEAAkJchmmLwBaAgAAAA==.',
Ad='Adonsina:BAAALgAECgEJAQABLgAECgkJCwAGAAAAAA==.',
Ae='Aether:BAAALgAECgMJAwAAAA==.',
Ag='Agrromagnet:BAABLgAECn8oAAIHAAkJahhVNgBJAgAHAAkJahhVNgBJAgAAAA==.',
Ai='Aiba:BAABLgAECn8aAAIIAAgJABhSHQDeAQAIAAgJABhSHQDeAQAAAA==.',
Ak='Akcloud:BAABLgAFFH8MAAMJAAQJzBtXEwAKAQAJAAQJSBhXEwAKAQAKAAEJ2yPTHQBoAAAAAA==.',
Al='Alab:BAAALgAECgIJBAABLgAECggJHgALAFAYAA==.Alaeris:BAACLgAFFH8QAAIMAAQJNhikKgAbAQAMAAQJNhikKgAbAQAuAAQKfyIAAgwACQlaHTsNAMcCAAwACQlaHTsNAMcCAAAA.Albetabeef:BAACLgAFFH8JAAMNAAQJGxTVGQAXAQANAAQJGxTVGQAXAQAKAAIJJgZQHACUAAAuAAQKfxgAAw0ACAn/IHsKAEICAAoABwk2ICAWAJwCAA0ABwmjInsKAEICAAAA.Alexei:BAABLgAECn8hAAIOAAcJ1QdUBADPAAAOAAcJ1QdUBADPAAAAAA==.Aleyeah:BAAALgAECgYJDgABLgAECggJNwAPAPsgAA==.Allhopeisded:BAABLgAECn8YAAIQAAkJFxB2NQDbAQAQAAkJFxB2NQDbAQAAAA==.Alurelor:BAAALgAECgkJEAAAAA==.Alyreu:BAAALgAECgQJBAABLgAECgYJDQAGAAAAAA==.',
Am='Amanita:BAAALgADCgkJCQAAAA==.Amarah:BAAALgADCgYJBgAAAA==.Amelaista:BAABLgAECn89AAIQAAkJ2QwXRQCZAQAQAAkJ2QwXRQCZAQAAAA==.',
An='Anddi:BAAALgAECgEJAwAAAA==.Andii:BAACLgAFFH8IAAIRAAQJXhmYHwAhAQARAAQJXhmYHwAhAQAuAAQKfxgABBEACAnIF38/AHoBABEABwnQFn8/AHoBAAcAAgm2B/hJAS8AABIAAQkAAPthAAAAAAAA.Andy:BAACLgAFFH8FAAITAAMJHgojNgCyAAATAAMJHgojNgCyAAAuAAQKfxQAAxMACAkoH6sLALQCABMACAkoH6sLALQCABQAAQkXB3ePACsAAAAA.Angusbeef:BAAALgAECgcJBwAAAA==.Antipus:BAAALgAECgQJBQAAAA==.',
Ao='Aoibhoker:BAAALgAECgQJBAABLgAFFAMJBQAVAHMSAA==.',
Ar='Arames:BAAALgAECgEJAQAAAA==.Arclo:BAAALgADCgYJBgAAAA==.Arden:BAAALgAECgQJBAABLgAECgYJFwAWANsWAA==.Ardeno:BAABLgAECn8XAAMWAAYJ2xarIwA7AQAWAAYJbwyrIwA7AQACAAUJ2xYonwAAAQAAAA==.Ardon:BAABLgAECn8sAAMQAAkJ8hreEwCtAgAQAAkJ8hreEwCtAgAPAAUJvhsbMQCaAQAAAA==.Armis:BAAALgADCgUJBQAAAA==.',
As='Asteruis:BAABLgAECn8kAAIFAAkJDh6YKwAvAgAFAAkJDh6YKwAvAgAAAA==.',
Av='Avenayra:BAAALgAECgIJAwAAAA==.',
Ay='Ayroon:BAAALgAECgEJAQAAAA==.',
Ba='Baddhealer:BAAALgADCgUJBQAAAA==.Badfurion:BAAALgADCggJCgAAAA==.Balthamel:BAAALgAECgYJDAAAAA==.Bananafang:BAAALgAECgQJBgAAAA==.Bananashoes:BAAALgAECgQJAwAAAA==.Bangerz:BAACLgAFFH9LAAIRAAgJhxfRBACNAgARAAgJhxfRBACNAgAuAAQKfzwAAxEACQlmILMIAOMCABEACQlmILMIAOMCAAcAAQm4AedYASYAAAAA.Barkendremix:BAABLgAECn80AAMXAAkJYRs0DAByAgAXAAkJYRs0DAByAgAYAAEJFBWCkwA9AAAAAA==.Bathsheber:BAAALgAFFAEJAQABLgAFFAgJGQAEAK0iAA==.Baulbuster:BAAALgAECggJEAAAAA==.',
Be='Beanieweenie:BAAALgADCgEJAQAAAA==.Beerez:BAAALgADCgcJDQAAAA==.Belroy:BAABLgAECn8fAAIZAAYJKBPqLAA9AQAZAAYJKBPqLAA9AQAAAA==.Beriothien:BAAALgAECgEJAQAAAA==.',
Bj='Bjorum:BAACLgAFFH8MAAIVAAQJAR6bBgBRAQAVAAQJAR6bBgBRAQAuAAQKfyMAAxUACQmVIpQGAG8CABUACQmVIpQGAG8CAA8AAQnhCLaQACcAAAAA.',
Bo='Bodytwodafa:BAACLgAFFH8PAAMaAAQJgBXeBAAeAQAaAAQJNBLeBAAeAQAbAAMJaA/lRgCtAAAuAAQKfyAABBoACAntIBgGAJUCABoACAkhHhgGAJUCABwABgn4GHARALMBABsABwlwGKAtAIUBAAAA.Bournemaad:BAAALgADCgMJAwAAAA==.Boyafu:BAAALgAECgEJAQAAAA==.',
Br='Brucecampbel:BAAALgAECgQJDAAAAA==.',
Bu='Bubbleyou:BAABLgAECn8aAAMSAAcJKhDeIgD+AAASAAcJKhDeIgD+AAAHAAIJuwpisQEpAAAAAA==.Burnek:BAAALgAECgIJBAABLgAECggJHgALAFAYAA==.',
Ca='Cantarella:BAABLgAECn8+AAMdAAkJzAh0DABlAQAdAAkJ9gd0DABlAQAeAAgJRAZ9KgBEAQAAAA==.Capy:BAAALgAFFAEJBAABLgAFFAUJFAAZAN8iAA==.Carlyle:BAABLgAECn82AAMHAAkJnR0jGACyAgAHAAkJnR0jGACyAgARAAUJlxWiPgBKAQAAAA==.Catdaddy:BAAALgADCgYJBwAAAA==.',
Ch='Checkmybio:BAAALgAECgQJBQAAAA==.Cheekyteetah:BAAALgAECgEJAQAAAA==.Cheesecake:BAAALgADCgUJBQAAAA==.Chromehound:BAAALgADCgQJBAAAAA==.Chumdungler:BAAALgAECgMJAwAAAA==.',
Ci='Cindervis:BAAALgADCgYJBgAAAA==.',
Cl='Clonk:BAAALgAECgUJBgAAAA==.',
Co='Collossuss:BAAALgAECgYJEwAAAA==.Convik:BAAALgAECgkJDQAAAA==.',
Cr='Cregga:BAAALgADCgEJAQAAAA==.Crimsonagony:BAAALgADCgUJBQAAAA==.Crosshairs:BAAALgADCgMJAwAAAA==.Crusible:BAAALgADCgEJAQAAAA==.',
Cu='Cuddles:BAAALgADCgUJBQAAAA==.Curacao:BAABLgAECn8YAAIKAAcJAhS+PQBPAQAKAAcJAhS+PQBPAQAAAA==.',
Cy='Cynnari:BAAALgAECgYJDQAAAA==.',
Da='Dabtime:BAABLgAECn8hAAIHAAgJJBPacgCWAQAHAAgJJBPacgCWAQAAAA==.Darkstarr:BAABLgAECn8XAAIUAAcJQgbOAQDnAAAUAAcJQgbOAQDnAAAAAA==.',
De='Deathknightm:BAAALgAECgIJAgABLgAECgkJHAAJAHYVAA==.Dekaar:BAABLgAECn8bAAIfAAYJuwm6KADKAAAfAAYJuwm6KADKAAAAAA==.Demonknight:BAAALgAECgEJAQAAAA==.Deracine:BAAALgAECgcJCgAAAA==.Derek:BAAALgAECgkJEwAAAA==.Desdemonica:BAABLgAECn8dAAIFAAgJ6AgBdQBVAQAFAAgJ6AgBdQBVAQAAAA==.',
Di='Diegoknight:BAAALgADCgEJAgAAAA==.Diggle:BAAALgAECgEJAQAAAA==.Dilvdrood:BAAALgADCgUJBQAAAA==.Dilvish:BAAALgAECgYJEgAAAA==.',
Do='Doctrwho:BAAALgAECgEJAQAAAA==.Dohaeris:BAABLgAECn8yAAIgAAkJ9xOaHQDYAQAgAAkJ9xOaHQDYAQAAAA==.Domain:BAABLgAECn8eAAILAAgJUBjgPgDNAQALAAgJUBjgPgDNAQAAAA==.Donfalprun:BAABLgAECn8gAAIHAAkJICOvDAD/AgAHAAkJICOvDAD/AgAAAA==.Doomstout:BAABLgAECn8WAAIEAAgJSBKieQCFAQAEAAgJSBKieQCFAQAAAA==.',
Dr='Draconus:BAABLgAECn8zAAMhAAkJfhU4EgDqAQAhAAkJUBM4EgDqAQAOAAQJcRvq6wDFAAAAAA==.Dralas:BAAALgAECggJEQAAAA==.Drkillenger:BAAALgAECgkJCQAAAA==.Drunkenchi:BAAALgAECgkJBwAAAA==.',
Du='Duro:BAAALgAECgYJDAABLgAECgYJDAAGAAAAAA==.Durto:BAAALgADCgMJAwABLgAECgQJCAAGAAAAAA==.Duskshade:BAAALgAECgUJCwAAAA==.',
['Dü']='Düsk:BAABLgAECn8VAAIOAAkJOQe3eAByAQAOAAkJOQe3eAByAQAAAA==.',
Ea='Eachan:BAAALgAECgMJAwAAAA==.',
El='Elij:BAACLgAFFH8JAAICAAQJYRhJRgA8AQACAAQJYRhJRgA8AQAuAAQKfx8AAgIACAmJHgsiAFoCAAIACAmJHgsiAFoCAAAA.Elufisti:BAAALgAECgEJBAAAAA==.Elunaire:BAACLgAFFH8GAAIDAAEJRxSSbQA9AAADAAEJRxSSbQA9AAAuAAQKfxwAAgMACQkCHJIdAFECAAMACQkCHJIdAFECAAAA.',
Em='Emelec:BAAALgAECgIJAgAAAA==.Emeraldwish:BAACLgAFFH8OAAMDAAQJliCVHgBkAQADAAQJliCVHgBkAQAIAAEJhA3fSgBDAAAuAAQKfx0AAwMACAmlI2sGACUDAAMACAmlI2sGACUDAAgAAQkAAAewAAAAAAAA.',
En='Endz:BAAALgAECgkJAwAAAA==.',
Er='Eraline:BAAALgADCgYJBgAAAA==.Erthnite:BAAALgAECgYJBwAAAA==.',
Ev='Evinco:BAABLgAECn8aAAIWAAkJhBC8FAAHAQAWAAkJhBC8FAAHAQAAAA==.Evy:BAAALgAECgEJAgAAAA==.',
Ex='Executie:BAACLgAFFH8bAAMNAAgJARLbBgDxAQANAAgJARLbBgDxAQAKAAMJGQzSEgDvAAAuAAQKfyYAAw0ACQngG3gGAGQCAA0ACQnLGngGAGQCAAoABglLHFw1ANQBAAAA.Exev:BAAALgADCgQJBAAAAA==.',
Fa='Falin:BAAALgAECgEJAQAAAA==.Fancy:BAAALgAECgcJCwAAAA==.',
Fe='Fey:BAABLgAECn8iAAICAAkJ5BPfTAC0AQACAAkJ5BPfTAC0AQAAAA==.',
Fi='Fieryember:BAAALgAECgQJBQABLgAECggJHgALAFAYAA==.Fistvendor:BAABLgAECn8UAAIXAAkJxAgOKwBfAQAXAAkJxAgOKwBfAQAAAA==.',
Fl='Flasheals:BAABLgAECn8wAAIRAAkJLBMoIQD6AQARAAkJLBMoIQD6AQAAAA==.Flatpak:BAAALgADCgEJAgAAAA==.Flobglop:BAAALgAECgEJAQAAAA==.Fluffybum:BAAALgADCgEJAQAAAA==.',
Fo='Foxtrot:BAABLgAECn8hAAIFAAgJOhpxMAAaAgAFAAgJOhpxMAAaAgAAAA==.',
Fr='Frenzaoibh:BAAALgAECgYJEQABLgAFFAMJBQAVAHMSAA==.Frostine:BAABLgAECn8ZAAIEAAcJtQdC1QBEAQAEAAcJtQdC1QBEAQAAAA==.Frostwave:BAACLgAFFH8IAAMOAAMJdRiYDgCcAAAOAAMJdRiYDgCcAAAiAAEJewhHKwA8AAAuAAQKf0YABCIACQmpIJYDAKkCACIACQmVH5YDAKkCACEACAnBHXYMAEYCAA4AAQlDHaFMAVQAAAAA.Frostythot:BAAALgADCgIJAgAAAA==.',
Fu='Fujiyama:BAABLgAECn83AAIPAAgJ+yDBDQCOAgAPAAgJ+yDBDQCOAgAAAA==.Furryweasal:BAAALgADCgEJAQAAAA==.',
Ga='Garrex:BAAALgADCgUJBQABLgAECggJFQAFAMUWAA==.Garréosh:BAABLgAECn8UAAQJAAYJRQtjNgCeAAAJAAUJJQxjNgCeAAAKAAQJPQVjewCFAAANAAIJBwfebABHAAABLgAFFAQJFAAHAAocAA==.',
Ge='Geodude:BAAALgADCgYJBwAAAA==.',
Gi='Gibborim:BAAALgAECgYJCwAAAA==.Gigilomann:BAAALgAECgMJBQAAAA==.',
Gl='Glacial:BAAALgAECgEJAQAAAA==.Glenndanzig:BAAALgADCgYJBgAAAA==.',
Go='Goldenshield:BAAALgAECgMJCQAAAA==.Golteb:BAAALgAECgQJBAAAAA==.Gonecrazy:BAAALgADCgMJAwAAAA==.Gorthan:BAAALgADCgQJBgAAAA==.',
Gr='Grabandgank:BAAALgADCgYJBgAAAA==.Groggi:BAAALgAECgYJBAAAAA==.',
Gu='Guaresux:BAEALgADCgEJAQABLgAECgkJGQAMAFARAA==.Gurnisson:BAAALgADCgUJBQAAAA==.Gusto:BAABLgAECn8uAAQbAAkJ6AvELwB5AQAbAAkJXQvELwB5AQAcAAgJegPLHwD2AAAaAAcJwQf3FQC1AAAAAA==.',
Ha='Hadouken:BAABLgAECn8UAAIHAAkJ5wAwtwEnAAAHAAkJ5wAwtwEnAAAAAA==.Hafsak:BAAALgAECgUJBQAAAA==.Halppme:BAAALgADCgcJBwAAAA==.Hammerfall:BAAALgAECgQJBAAAAA==.Handsome:BAAALgAECgcJBwAAAA==.',
He='Headshotte:BAAALgAECgYJDAAAAA==.Heatindabs:BAABLgAECn8gAAIDAAkJpg4+SwBiAQADAAkJpg4+SwBiAQAAAA==.Hexed:BAAALgAECgYJEwAAAA==.',
Hi='Hinael:BAAALgAECgEJAQAAAA==.',
Ho='Holyknight:BAAALgAECgYJDwAAAA==.Holymama:BAABLgAECn8gAAMUAAgJeh1MGQD7AQAUAAcJdCBMGQD7AQATAAIJIROeYgByAAAAAA==.',
Hu='Hunkwai:BAAALgAFFAIJAgAAAA==.',
Ib='Ibok:BAAALgAECgYJCgAAAA==.',
Ic='Iceberg:BAAALgAFFAIJAwABLgAFFAgJGQAEAK0iAA==.Ickma:BAABLgAECn9CAAIOAAkJ0x4jGgCqAgAOAAkJ0x4jGgCqAgAAAA==.',
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
Ke='Kehma:BAAALgAECgEJAQAAAA==.Keleios:BAAALgADCgYJBgABLgAECgUJDwAGAAAAAA==.Kelisa:BAABLgAECn8uAAIHAAkJPx1aJwBmAgAHAAkJPx1aJwBmAgAAAA==.Ketchuptits:BAAALgADCgYJBgAAAA==.',
Ki='Kimjunggheal:BAAALgAECgMJBgAAAA==.Kinkster:BAAALgAECgYJCwABLgAECgYJDQAGAAAAAA==.Kinza:BAAALgADCgkJCQABLgAECggJGgAIAAAYAA==.Kiwidin:BAABLgAECn8gAAIRAAkJuhXmJgDzAQARAAkJuhXmJgDzAQAAAA==.',
Ko='Koketsu:BAAALgAECgYJEwAAAA==.',
Kr='Krinxy:BAABLgAECn8VAAIDAAUJFhqSWwA/AQADAAUJFhqSWwA/AQAAAA==.',
Ks='Kschwev:BAAALgADCgYJBgAAAA==.',
Ku='Kuratcha:BAAALgAECgcJDQABLgAECggJHgALAFAYAA==.',
Ky='Kylee:BAAALgAECgkJAQAAAA==.Kyý:BAAALgAECgYJDwAAAA==.',
['Kí']='Kíng:BAAALgAECgYJEwABLgAECggJHgALAFAYAA==.',
La='Lachoneus:BAAALgAECgEJAQAAAA==.Lazyde:BAAALgAFFAIJAgAAAA==.',
Le='Ledgerfeign:BAABLgAECn8qAAICAAkJDg11UwChAQACAAkJDg11UwChAQAAAA==.',
Li='Liadan:BAABLgAECn8jAAIRAAgJkAx2NACAAQARAAgJkAx2NACAAQAAAA==.Lighteye:BAABLgAECn9JAAIDAAkJcRmDFACmAgADAAkJcRmDFACmAgAAAA==.Lilmudatruka:BAAALgADCgEJAQABLgAECgkJGAAQABcQAA==.Lindris:BAAALgAECgEJAQAAAA==.',
Lo='Longestibrow:BAAALgAECgMJBQAAAA==.',
Lu='Luminescence:BAAALgADCgQJBgAAAA==.Lunarqt:BAAALgAECgEJAQAAAA==.Lunchy:BAAALgAECgYJCQAAAA==.',
Ly='Lyllow:BAABLgAECn8UAAIcAAYJDhNSGgA1AQAcAAYJDhNSGgA1AQAAAA==.',
['Lø']='Løurent:BAAALgADCgQJBAAAAA==.',
Ma='Macklerina:BAAALgADCgUJCAAAAA==.Magicdorf:BAACLgAFFH8FAAIEAAIJxBSNngCPAAAEAAIJxBSNngCPAAAuAAQKfywAAgQACQlMIcIWANECAAQACQlMIcIWANECAAAA.Malphasia:BAAALgADCgYJBgAAAA==.Manhitrogue:BAAALgAECgcJEAAAAA==.Massivebicep:BAAALgAECgIJAgAAAA==.Mavras:BAAALgADCgEJAQAAAA==.',
Mc='Mcbraintumor:BAAALgAECgQJCQAAAA==.Mcsleuth:BAAALgAECgQJBgAAAA==.',
Me='Megarayquaza:BAACLgAFFH8LAAILAAQJEgYKXQDYAAALAAQJEgYKXQDYAAAuAAQKfx8AAyMACAkqEmseAMwBACMACAnIC2seAMwBAAsACAk1EWpiAGMBAAAA.',
Mi='Mikeyouk:BAAALgADCgYJBgAAAA==.Millertime:BAAALgAECgQJBgAAAA==.Misties:BAAALgAECgEJAQAAAA==.',
Mo='Moargoth:BAAALgADCgUJEAAAAA==.Mooneater:BAAALgAECgYJCAAAAA==.Moosedon:BAAALgAECgEJAgABLgAECgkJIAAHACAjAA==.Mordorl:BAAALgADCgcJBwAAAA==.',
Mt='Mtt:BAAALgADCgkJDgAAAA==.',
Mx='Mxx:BAABLgAECn8XAAQFAAUJbiC9TQCAAQAFAAUJbiC9TQCAAQAZAAMJMxTCTQB7AAAkAAEJzAMGlgAjAAAAAA==.',
My='Mylianne:BAABLgAECn8aAAIIAAcJYhw4HQDeAQAIAAcJYhw4HQDeAQAAAA==.Mynameiscole:BAACLgAFFH8IAAIjAAQJgh98AQCSAQAjAAQJgh98AQCSAQAuAAQKfyMAAiMACAmZJq4BAIoDACMACAmZJq4BAIoDAAEuAAUUBwkUAAsAAx4A.Myrolan:BAABLgAECn8tAAIjAAkJCCSVAwAcAwAjAAkJCCSVAwAcAwAAAA==.Myrtru:BAAALgAECgkJDgAAAA==.',
['Mí']='Míyagi:BAAALgAECgYJBgAAAA==.',
Na='Naturallight:BAAALgADCgUJCAAAAA==.',
Ne='Neechka:BAAALgADCgUJBQAAAA==.Neosan:BAAALgADCgYJBgABLgAFFAMJCgAIAOciAA==.Nevyn:BAABLgAECn8gAAIlAAkJchTIBACgAQAlAAkJchTIBACgAQAAAA==.Newface:BAAALgADCgEJAgAAAA==.Newmoo:BAAALgAECgEJAQAAAA==.',
Ni='Nightsage:BAAALgAECgUJCQAAAA==.Niji:BAAALgAECgYJDwABLgAECggJGgAIAAAYAA==.Nininhp:BAABLgAECn8bAAITAAcJZRPZJQChAQATAAcJZRPZJQChAQAAAA==.Nithari:BAABLgAECn8/AAIEAAkJeyIBDQARAwAEAAkJeyIBDQARAwAAAA==.',
No='Nobel:BAAALgADCgEJAQAAAA==.Nomanai:BAAALgADCgkJAwAAAA==.Nosst:BAAALgAECgMJBQAAAA==.Nost:BAAALgADCgcJBwAAAA==.Nostu:BAABLgAECn8hAAMTAAkJsBYdFwAeAgATAAkJsBYdFwAeAgAUAAEJbhAQhAA2AAAAAA==.Now:BAACLgAFFH8OAAIHAAQJkh+TKABpAQAHAAQJkh+TKABpAQAuAAQKfx8AAwcACAkQIOAtAGsCAAcACAlPHuAtAGsCABIABgmIF7AcADABAAAA.',
Nu='Nukum:BAAALgAECgYJEAABLgAECggJKgAFAJgaAA==.',
Oh='Ohpa:BAABLgAECn8nAAMCAAkJshSaRgDGAQACAAkJ3ROaRgDGAQABAAMJbw8OMQBbAAAAAA==.Ohrly:BAAALgAECgEJAQAAAA==.',
Oj='Ojikan:BAABLgAECn8WAAIfAAgJvSKkAwD2AgAfAAgJvSKkAwD2AgAAAA==.Ojpriest:BAAALgAFFAMJAwAAAA==.',
On='Onore:BAAALgAECgEJAQAAAA==.',
Pa='Pallykera:BAAALgAECgEJAQAAAA==.Papamush:BAAALgAECgMJBQAAAA==.Pathogenn:BAAALgAECgYJEAAAAA==.',
Pe='Pepecry:BAAALgAECgUJDgABLgAECggJHgALAFAYAA==.',
Ph='Phoblade:BAABLgAECn8mAAIOAAgJNhaoUQDPAQAOAAgJNhaoUQDPAQAAAA==.Phobreeze:BAAALgAECgQJBgAAAA==.Phokk:BAAALgAECgcJBwAAAA==.',
Pi='Pirotess:BAABLgAECn8ZAAIHAAkJAAruwgAEAQAHAAkJAAruwgAEAQAAAA==.',
Po='Pollymorphh:BAAALgADCgUJBgAAAA==.Ponylion:BAAALgAECgYJCwABLgAECgcJEQAGAAAAAA==.Pooshka:BAABLgAECn8dAAIPAAkJSCJiCgDvAgAPAAkJSCJiCgDvAgAAAA==.Popz:BAAALgAECgEJAQAAAA==.',
Pr='Preorcthego:BAACLgAFFH8WAAIZAAQJ4yZWBQC6AQAZAAQJ4yZWBQC6AQAuAAQKfykAAxkACAlqJpcAAIsDABkACAlqJpcAAIsDACQAAQm/JHV7AFUAAAEuAAUUBgkkAA4AmiEA.Presibro:BAABLgAECn8aAAIJAAcJfCJDCgBOAgAJAAcJfCJDCgBOAgAAAA==.Presiric:BAAALgAECgMJAwAAAA==.Presisarian:BAAALgAECgYJDwAAAA==.',
Pu='Puck:BAAALgAECgYJDQAAAA==.Puppye:BAACLgAFFH8MAAIFAAQJARpnOQA6AQAFAAQJARpnOQA6AQAuAAQKfxgAAgUACAlNHMU0AAoCAAUACAlNHMU0AAoCAAAA.',
Ra='Ranalia:BAAALgAECgQJBgAAAA==.Ranouu:BAABLgAECn8VAAIEAAYJIBW8nACcAQAEAAYJIBW8nACcAQAAAA==.Ratatatatt:BAAALgADCgQJBQAAAA==.',
Re='Reaoibher:BAAALgADCgMJAwABLgAFFAMJBQAVAHMSAA==.Recision:BAABLgAECn9BAAImAAkJySKjAQAKAwAmAAkJySKjAQAKAwABLgAFFAIJAgAGAAAAAA==.Reeash:BAABLgAECn8XAAMQAAkJABdRJQAuAgAQAAkJABdRJQAuAgAPAAMJyAt7fAB6AAAAAA==.Reeatar:BAABLgAECn8ZAAIEAAcJ5Rg9oACWAQAEAAcJ5Rg9oACWAQABLgAECgkJFwAQAAAXAA==.Relindor:BAAALgADCgYJBgABLgAFFAQJCAAOAJwSAA==.Revelle:BAAALgAECgkJCwAAAA==.',
Rh='Rheizen:BAABLgAECn9IAAIJAAkJ/RdZAADoAQAJAAkJ/RdZAADoAQAAAA==.',
Ri='Riptide:BAAALgAECgEJAQAAAA==.',
Ro='Ron:BAAALgADCgQJBAAAAA==.Ropopo:BAABLgAECn8fAAITAAgJtxkpGQAIAgATAAgJtxkpGQAIAgABLgAFFAQJDAAFAAEaAA==.',
Ru='Runcat:BAABLgAECn8XAAMLAAgJQh6bJQA3AgALAAgJQh6bJQA3AgAmAAQJ1QbmIwB/AAAAAA==.',
['Rö']='Röyksopp:BAABLgAECn8iAAIEAAgJAw7yfgB6AQAEAAgJAw7yfgB6AQAAAA==.',
Sa='Sabo:BAAALgAECgMJAwAAAA==.Sakona:BAAALgADCgEJAQAAAA==.Salbahe:BAABLgAFFH8GAAIOAAMJ8gd0tAC9AAAOAAMJ8gd0tAC9AAAAAA==.Samarah:BAAALgAECgcJCAAAAA==.Sandewor:BAABLgAECn8UAAQSAAYJ4Re8GgBCAQASAAYJ4Re8GgBCAQAHAAMJ0QpEIgGQAAARAAEJZgcrmAAoAAABLgAECgYJFQAZAPwMAA==.Sanfrancisco:BAAALgAECgIJAwABLgAECgIJAgAGAAAAAA==.Sarafyn:BAABLgAECn8/AAIgAAkJUxm0FQAmAgAgAAkJUxm0FQAmAgAAAA==.Sauceguzzler:BAAALgAECgYJBgAAAA==.Savath:BAAALgADCgYJBgAAAA==.',
Se='Selenagomes:BAAALgAECgEJAQABLgAFFAcJFAALAAMeAA==.Selenor:BAAALgAECgQJBwAAAA==.Seragaki:BAABLgAECn8kAAMTAAkJRRrgDQCPAgATAAkJRRrgDQCPAgAUAAYJmxOCNwA3AQAAAA==.Seraphinna:BAAALgADCgEJAQAAAA==.',
Si='Siegescale:BAAALgADCgcJCwAAAA==.Siegrorc:BAABLgAECn86AAIJAAkJWRRMEADjAQAJAAkJWRRMEADjAQAAAA==.Sillidari:BAAALgADCgQJBwAAAA==.Sindrila:BAAALgAECgYJDwAAAA==.Sionshope:BAAALgAECgUJCQAAAA==.',
Sk='Skragar:BAAALgAECgEJAgAAAA==.',
Sl='Slayerhunt:BAABLgAECn8VAAQZAAYJ/AzYMgAXAQAZAAYJ2wvYMgAXAQAFAAQJywvegQDiAAAkAAIJqQwGeABgAAAAAA==.Slayerlock:BAAALgAECgYJCQAAAA==.Slayertin:BAAALgAECgYJCwABLgAECgYJFQAZAPwMAA==.',
Sm='Smallpox:BAAALgAECgQJBAABLgAECgkJBQAGAAAAAA==.',
Sn='Snibdru:BAAALgAECgcJBgAAAA==.Snkrsotoole:BAABLgAECn8cAAIPAAYJgw7dVwDcAAAPAAYJgw7dVwDcAAAAAA==.',
So='Soobz:BAAALgADCgYJBgAAAA==.Sorian:BAAALgAECgUJCQAAAA==.Soulkings:BAAALgADCggJDwAAAA==.Soupies:BAAALgAECgQJBQAAAA==.Soxa:BAAALgADCgIJAgAAAA==.',
Sp='Spiikee:BAAALgAECgIJAgAAAA==.Sprays:BAAALgAECgQJBAAAAA==.',
Sr='Sry:BAAALgAECgYJBAAAAA==.',
St='Steady:BAABLgAECn8ZAAIHAAcJbhUtmgBBAQAHAAcJbhUtmgBBAQAAAA==.Stonehand:BAACLgAFFH8IAAIUAAMJ3xBgJADTAAAUAAMJ3xBgJADTAAAuAAQKfy0AAhQACQmgFCUaAPQBABQACQmgFCUaAPQBAAAA.Stormsurge:BAAALgAECgQJBQAAAA==.Stownt:BAAALgADCgMJAwAAAA==.Stravas:BAAALgAECgcJBwAAAA==.Strongbow:BAABLgAECn8sAAIFAAgJFgsEBAAFAQAFAAgJFgsEBAAFAQAAAA==.',
Su='Subudai:BAAALgAECgkJEAAAAA==.Sugarboi:BAACLgAFFH8FAAInAAIJXwLAOQBBAAAnAAIJXwLAOQBBAAAuAAQKfy0AAicACQlwCvsnABgBACcACQlwCvsnABgBAAAA.Sugasuga:BAABLgAECn8ZAAIHAAcJhh5dPQAPAgAHAAcJhh5dPQAPAgAAAA==.Sunnymuffins:BAAALgAECgEJAQAAAA==.',
Sv='Sveetka:BAAALgAECgMJBAAAAA==.',
Sx='Sxytrev:BAAALgAECgQJCQAAAA==.',
Ta='Tabi:BAAALgADCgQJBgAAAA==.Tacoy:BAABLgAECn8fAAIKAAgJxRbZLgCUAQAKAAgJxRbZLgCUAQAAAA==.Tagsy:BAABLgAECn8VAAIFAAgJxRZdOQDJAQAFAAgJxRZdOQDJAQAAAA==.Tay:BAAALgAECgcJCwAAAA==.Tayna:BAAALgADCgYJBgAAAA==.',
Tb='Tbizkut:BAABLgAECn9GAAIWAAkJIRDSCgCVAQAWAAkJIRDSCgCVAQAAAA==.',
Th='Then:BAABLgAECn8pAAIEAAcJSBkgcACaAQAEAAcJSBkgcACaAQAAAA==.Threetimez:BAABLgAECn8XAAIFAAcJJAy3fgBCAQAFAAcJJAy3fgBCAQAAAA==.Thumbmage:BAABLgAECn8UAAIEAAYJxCBjVgDaAQAEAAYJxCBjVgDaAQABLgAFFAQJDgAPANUiAA==.',
Ti='Timemaster:BAABLgAECn8hAAQjAAcJzx1AEwD8AQAjAAcJmR1AEwD8AQAmAAEJYyKYKABiAAALAAIJnQMT1wBCAAAAAA==.Timepacifist:BAAALgAECgcJCgAAAA==.',
To='Tobeybey:BAAALgAECgIJBQAAAA==.Tokido:BAAALgAFFAEJAQAAAA==.Tongpakfu:BAABLgAECn8ZAAIMAAQJTRDMdAC8AAAMAAQJTRDMdAC8AAAAAA==.Topflight:BAAALgAECgcJEgAAAA==.',
Tr='Triggered:BAABLgAECn8bAAMHAAgJVBeZUQDsAQAHAAgJVBeZUQDsAQARAAEJ0AqlngAqAAAAAA==.Troiikâ:BAABLgAECn9EAAQSAAkJphQEEADFAQASAAkJphQEEADFAQAHAAcJNgdH0QDxAAARAAUJ8QJhawCJAAAAAA==.Troikkâ:BAAALgADCgQJBAAAAA==.Troikâ:BAAALgADCgYJBwAAAA==.Trroikâ:BAABLgAECn84AAIJAAgJ+xbWEADcAQAJAAgJ+xbWEADcAQAAAA==.',
Tt='Tteeffinn:BAAALgADCgYJBgAAAA==.Ttevinn:BAAALgAECgMJBAABLgAECgkJBwAGAAAAAA==.Ttevoker:BAAALgAECgkJBwAAAA==.',
Tu='Tulvie:BAAALgADCgQJCAAAAA==.Tummytickle:BAAALgAECgEJAQAAAA==.Tupacaroni:BAAALgAECgMJAwAAAA==.',
Ty='Tycone:BAAALgAECgcJCgAAAA==.',
Ud='Udderpower:BAAALgAECgkJBQAAAA==.',
Ul='Uldirtydruid:BAABLgAECn8vAAMDAAgJ6B5/EQDEAgADAAgJ6B5/EQDEAgAnAAUJfBOFMQDkAAAAAA==.',
Ur='Urukdrak:BAABLgAECn8kAAMZAAkJJw16HwCgAQAZAAkJkAl6HwCgAQAkAAgJiQ3iMwCcAQAAAA==.',
Uw='Uwantwar:BAAALgAECgYJDwAAAA==.',
Va='Valanquishy:BAAALgADCgEJAgAAAA==.',
Ve='Velaryon:BAAALgAECgQJBAAAAA==.',
Vh='Vhagar:BAAALgAECgIJAwAAAA==.',
Vi='Vidich:BAAALgAFFAEJAQAAAA==.Viralus:BAAALgADCgEJAQAAAA==.',
Vo='Vodka:BAAALgAECgEJAgAAAA==.Voiddastard:BAAALgADCgkJFwAAAA==.Voidlight:BAAALgADCgcJBwAAAA==.Volcazzic:BAAALgADCgIJAgAAAA==.',
Vy='Vynnara:BAAALgADCgMJAQAAAA==.',
Wa='Wakkaba:BAAALgADCgYJBgAAAA==.Wanaatlarboy:BAABLgAECn84AAMUAAkJehdjAAD5AQAUAAkJehdjAAD5AQATAAEJ7gH4XgAiAAAAAA==.Waywyrd:BAAALgADCgMJAwAAAA==.',
Wh='Whack:BAAALgADCgcJCAAAAA==.',
Wu='Wunderbar:BAABLgAECn8eAAIQAAYJKxueTQB6AQAQAAYJKxueTQB6AQAAAA==.Wunderburger:BAAALgAECgYJEQAAAA==.Wunderground:BAAALgAECgYJDwAAAA==.',
Xa='Xannada:BAABLgAECn9CAAIHAAkJmxKYTADhAQAHAAkJmxKYTADhAQAAAA==.',
Xe='Xenztrazlu:BAAALgAECgQJCAABLgAECgcJGwATAGUTAA==.',
Ya='Yahknee:BAAALgADCgEJAQAAAA==.Yaoli:BAAALgAECgMJBAAAAA==.',
Ye='Yea:BAAALgADCgcJCwAAAA==.',
Yo='Yodadogownz:BAABLgAECn8TAAIUAAcJ7xBMMwBMAQAUAAcJ7xBMMwBMAQAAAA==.Yoh:BAACLgAFFH8OAAIOAAQJ7w+AeAATAQAOAAQJ7w+AeAATAQAuAAQKfxwAAg4ACAlKHVlCAPsBAA4ACAlKHVlCAPsBAAAA.Yoruichee:BAAALgAECgEJAgAAAA==.Yourenotron:BAAALgAECgEJAgAAAA==.',
Yu='Yungdro:BAAALgAECgEJAQAAAA==.',
Za='Zarutobi:BAAALgAECgYJEgABLgAECggJGgAIAAAYAA==.',
Zo='Zob:BAAALgADCgQJBAAAAA==.',
Zu='Zui:BAABLgAECn8pAAIXAAkJahL1GwDFAQAXAAkJahL1GwDFAQAAAA==.',
['Zù']='Zùg:BAAALgADCgIJAQAAAA==.',
['Ðo']='Ðongknight:BAAALgAFFAIJBAAAAA==.',
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
