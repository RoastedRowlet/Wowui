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

local lookup = {'Warlock-Affliction','Warlock-Demonology','Druid-Restoration','Mage-Frost','Unknown-Unknown','Hunter-BeastMastery','Paladin-Retribution','Druid-Balance','Warrior-Protection','Warrior-Fury','Monk-Mistweaver','Warrior-Arms','DeathKnight-Unholy','Shaman-Elemental','Shaman-Restoration','Paladin-Holy','Paladin-Protection','Priest-Discipline','Priest-Shadow','Shaman-Enhancement','Warlock-Destruction','Monk-Brewmaster','Monk-Windwalker','Hunter-Survival','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Rogue-Assassination','Rogue-Subtlety','Druid-Feral','Priest-Holy','DemonHunter-Devourer','DeathKnight-Blood','Hunter-Marksmanship','DeathKnight-Frost','DemonHunter-Havoc','Mage-Arcane','DemonHunter-Vengeance','Druid-Guardian',}
local provider = {region='US',realm='DarkIron',name='US',type='weekly',zone=46,date='2026-07-28',data={Aa='Aanx:BAABLgAECn8ZAAMBAAYJth3gGgDnAAACAAYJth21gwAxAQABAAQJQhngGgDnAAAAAA==.',
Ab='Abadon:BAAALgAECgQJBgABLgAFFAEJBgADAEcUAA==.Abdorei:BAACLgAFFH8KAAIEAAQJLQcPfgDaAAAEAAQJLQcPfgDaAAAuAAQKfz4AAgQACQnkF0I2AEACAAQACQnkF0I2AEACAAEuAAEKCQkQAAUAAAAA.Absorboat:BAAALgADCgYJCAAAAA==.',
Ac='Accilatem:BAABLgAECn8aAAIGAAcJQh4nHgBRAgAGAAcJQh4nHgBRAgABLgAECgkJIgAEAHIZAA==.Accilatim:BAABLgAECn8iAAIEAAkJchmgLwBaAgAEAAkJchmgLwBaAgAAAA==.',
Ad='Adonsina:BAAALgAECgEJAQABLgAECgkJCwAFAAAAAA==.',
Ae='Aether:BAAALgAECgMJAwAAAA==.',
Ag='Agrromagnet:BAABLgAECn8oAAIHAAkJahhVNgBJAgAHAAkJahhVNgBJAgAAAA==.',
Ai='Aiba:BAABLgAECn8aAAIIAAgJABhUHQDeAQAIAAgJABhUHQDeAQAAAA==.',
Ak='Akcloud:BAABLgAFFH8MAAMJAAQJzBtbEwAKAQAJAAQJSBhbEwAKAQAKAAEJ2yPTHQBoAAAAAA==.',
Al='Alab:BAAALgAECgIJBAABLgAFFAEJAQAFAAAAAA==.Alaeris:BAACLgAFFH8QAAILAAQJNhipKgAbAQALAAQJNhipKgAbAQAuAAQKfyIAAgsACQlaHTYNAMcCAAsACQlaHTYNAMcCAAAA.Albetabeef:BAACLgAFFH8JAAMMAAQJGxTOGQAXAQAMAAQJGxTOGQAXAQAKAAIJJgZQHACUAAAuAAQKfxgAAwwACAn/IHkKAEICAAoABwk2ICAWAJwCAAwABwmjInkKAEICAAAA.Alexei:BAABLgAECn8yAAINAAcJtgv4EwD+AAANAAcJtgv4EwD+AAAAAA==.Aleyeah:BAAALgAECgYJDgABLgAECggJNwAOAPsgAA==.Allhopeisded:BAACLgAFFH8MAAIPAAMJUA46LQCOAAAPAAMJUA46LQCOAAAuAAQKfxoAAg8ACQkXEHk1ANsBAA8ACQkXEHk1ANsBAAAA.Alurelor:BAAALgAECgkJEAAAAA==.Alyreu:BAAALgAECgQJBAABLgAECgYJDQAFAAAAAA==.',
Am='Amanita:BAAALgADCgkJCQAAAA==.Amarah:BAAALgADCgYJBgAAAA==.Amelaista:BAABLgAECn89AAIPAAkJ2QwcRQCZAQAPAAkJ2QwcRQCZAQAAAA==.',
An='Anddi:BAAALgAECgEJAwAAAA==.Andii:BAACLgAFFH8IAAIQAAQJXhmSHwAhAQAQAAQJXhmSHwAhAQAuAAQKfxgABBAACAnIF38/AHoBABAABwnQFn8/AHoBAAcAAgm2B/hJAS8AABEAAQkAAPthAAAAAAAA.Andy:BAACLgAFFH8FAAISAAMJHgocNgCyAAASAAMJHgocNgCyAAAuAAQKfxQAAxIACAkoH6sLALQCABIACAkoH6sLALQCABMAAQkXB32PACsAAAAA.Angusbeef:BAAALgAECgcJBwAAAA==.Antipus:BAAALgAECgQJBQAAAA==.',
Ao='Aoibhoker:BAAALgAECgQJBAABLgAFFAMJCAAUAIobAA==.',
Ar='Arames:BAAALgAECgEJAQAAAA==.Arclo:BAAALgADCgYJBgAAAA==.Arden:BAAALgAECgQJBAABLgAECgYJFwAVANsWAA==.Ardeno:BAABLgAECn8XAAMVAAYJ2xarIwA7AQAVAAYJbwyrIwA7AQACAAUJ2xYsnwAAAQAAAA==.Ardon:BAABLgAECn8sAAMPAAkJ8hrfEwCtAgAPAAkJ8hrfEwCtAgAOAAUJvhsbMQCaAQAAAA==.Armis:BAAALgAECgEJAQAAAA==.',
As='Asteruis:BAABLgAECn8kAAIGAAkJDh6XKwAvAgAGAAkJDh6XKwAvAgAAAA==.',
Av='Avenayra:BAAALgAECgIJAwAAAA==.',
Ay='Ayroon:BAAALgAECgEJAQAAAA==.',
Ba='Baddhealer:BAAALgADCgUJBQAAAA==.Badfurion:BAAALgADCggJCgAAAA==.Balthamel:BAAALgAECgYJDAAAAA==.Bananafang:BAAALgAECgQJBgAAAA==.Bananashoes:BAAALgAECgQJAwAAAA==.Bangerz:BAACLgAFFH9WAAIQAAkJlxyAAABVAwAQAAkJlxyAAABVAwAuAAQKfzwAAxAACQlmILMIAOMCABAACQlmILMIAOMCAAcAAQm4AedYASYAAAAA.Barkendremix:BAABLgAECn80AAMWAAkJYRs1DAByAgAWAAkJYRs1DAByAgAXAAEJFBWCkwA9AAAAAA==.Bathsheber:BAAALgAFFAEJAQABLgAFFAkJIwAEACMjAA==.Baulbuster:BAAALgAECggJEwAAAA==.',
Be='Beanieweenie:BAAALgADCgEJAQAAAA==.Bearden:BAAALgAECgYJCAAAAA==.Beerez:BAAALgADCgcJDQAAAA==.Belroy:BAABLgAECn8fAAIYAAYJKBPuLAA9AQAYAAYJKBPuLAA9AQAAAA==.Beriothien:BAAALgAECgEJAQAAAA==.',
Bi='Bighani:BAAALgAECgUJBwABLgAFFAEJAQAFAAAAAA==.',
Bj='Bjorum:BAACLgAFFH8MAAIUAAQJAR6ZBgBRAQAUAAQJAR6ZBgBRAQAuAAQKfyMAAxQACQmVIpQGAG8CABQACQmVIpQGAG8CAA4AAQnhCLaQACcAAAAA.',
Bo='Bodytwodafa:BAACLgAFFH8QAAMZAAQJgBXcBAAeAQAZAAQJqhLcBAAeAQAaAAMJaA/sRgCtAAAuAAQKfyAABBkACAntIBgGAJUCABkACAkhHhgGAJUCABsABgn4GHARALMBABoABwlwGKItAIUBAAAA.Bomber:BAAALgAFFAEJAQABLgAFFAkJIwAEACMjAA==.Bournemaad:BAAALgADCgMJAwAAAA==.Boyafu:BAAALgAECgEJAQAAAA==.',
Br='Brewsleeroyz:BAAALgAECgkJCQAAAA==.Brucecampbel:BAABLgAECn8UAAINAAcJnRCJDgA2AQANAAcJnRCJDgA2AQAAAA==.',
Bu='Bubbleyou:BAABLgAECn8jAAMRAAkJPxCkBwDaAAARAAkJPxCkBwDaAAAHAAIJuwpjsQEpAAAAAA==.Burnek:BAAALgAECgIJBAABLgAFFAEJAQAFAAAAAA==.',
Ca='Cantarella:BAABLgAECn8+AAMcAAkJzAhzDABlAQAcAAkJ9gdzDABlAQAdAAgJRAZ9KgBEAQAAAA==.Capy:BAAALgAFFAEJBAABLgAFFAcJIAAYAOQeAA==.Carlyle:BAABLgAECn8/AAMHAAkJnR0jGACyAgAHAAkJnR0jGACyAgAQAAUJlxWkPgBKAQAAAA==.Catdaddy:BAAALgADCgYJBwAAAA==.',
Ch='Checkmybio:BAAALgAECgQJBQAAAA==.Cheekyteetah:BAAALgAECgEJAQAAAA==.Cheesecake:BAAALgADCgUJBQAAAA==.Chromehound:BAAALgADCgQJBAAAAA==.Chumdungler:BAAALgAECgMJAwAAAA==.',
Ci='Cindervis:BAAALgADCgYJBgAAAA==.',
Cl='Claoibh:BAABLgAECn8aAAMKAAYJ0RrGBwBFAQAKAAUJ0hvGBwBFAQAMAAYJaBeOBgDgAAABLgAFFAMJCAAUAIobAA==.Clonk:BAAALgAECgUJBgAAAA==.',
Co='Collossuss:BAAALgAECgYJEwAAAA==.Convik:BAAALgAECgkJDQAAAA==.Corruo:BAAALgAECgMJBgAAAA==.',
Cr='Cregga:BAAALgADCgEJAQAAAA==.Crimsonagony:BAAALgADCgUJBQAAAA==.Crosshairs:BAAALgADCgMJAwAAAA==.Crusible:BAAALgADCgEJAQAAAA==.',
Cu='Curacao:BAABLgAECn8YAAIKAAcJAhS/PQBPAQAKAAcJAhS/PQBPAQAAAA==.',
Cy='Cynnari:BAAALgAECgYJDQAAAA==.',
Da='Dabtime:BAABLgAECn8hAAIHAAgJJBPacgCWAQAHAAgJJBPacgCWAQAAAA==.Darkstarr:BAABLgAECn8tAAITAAgJnghzCgD7AAATAAgJnghzCgD7AAAAAA==.Darwynne:BAAALgADCgUJBQAAAA==.',
De='Deathknightm:BAAALgAECgIJAgABLgAFFAEJAQAFAAAAAA==.Dekaar:BAABLgAECn8bAAIeAAYJuwm7KADKAAAeAAYJuwm7KADKAAAAAA==.Demonknight:BAAALgAECgEJAQAAAA==.Deracine:BAAALgAECgcJCgAAAA==.Derek:BAAALgAECgkJEwAAAA==.Desdemonica:BAABLgAECn8dAAIGAAgJ6Aj8dABVAQAGAAgJ6Aj8dABVAQAAAA==.',
Di='Diegoknight:BAAALgADCgEJAgAAAA==.Diggle:BAAALgAECgEJAQAAAA==.Dilvdrood:BAAALgADCgUJBQAAAA==.Dilvish:BAAALgAECgYJEgAAAA==.Dirtyspice:BAAALgAECgIJAQAAAA==.',
Do='Doctrwho:BAAALgAECgEJAQAAAA==.Dohaeris:BAABLgAECn8zAAIfAAkJ9xOcHQDYAQAfAAkJ9xOcHQDYAQAAAA==.Domain:BAABLgAECn8eAAIgAAgJUBjjPgDNAQAgAAgJUBjjPgDNAQABLgAFFAEJAQAFAAAAAA==.Donfalprun:BAABLgAECn8gAAIHAAkJICOxDAD/AgAHAAkJICOxDAD/AgAAAA==.Doomstout:BAABLgAECn8WAAIEAAgJSBKieQCFAQAEAAgJSBKieQCFAQAAAA==.',
Dr='Draconus:BAABLgAECn81AAMhAAkJthc5EgDqAQAhAAkJiBU5EgDqAQANAAQJcRv06wDFAAAAAA==.Dralas:BAABLgAECn8UAAQGAAgJ2g5EXgCMAQAGAAgJLQ5EXgCMAQAYAAIJUw6ATwByAAAiAAEJTAcPjQAuAAAAAA==.Drkillenger:BAAALgAECgkJCQAAAA==.Drunkenchi:BAAALgAECgkJBwAAAA==.',
Dt='Dthealz:BAAALgAECgEJAQAAAA==.',
Du='Duro:BAAALgAECgYJDAABLgAECgYJDAAFAAAAAA==.Durto:BAAALgADCgMJAwABLgAECgQJCAAFAAAAAA==.Duskshade:BAAALgAECgUJCwAAAA==.',
['Dü']='Düsk:BAABLgAECn8VAAINAAkJOQe6eAByAQANAAkJOQe6eAByAQAAAA==.',
Ea='Eachan:BAAALgAECgMJAwAAAA==.',
Ek='Eklipsa:BAAALgAECgEJAQAAAA==.',
El='Elij:BAACLgAFFH8JAAICAAQJYRgqRgA8AQACAAQJYRgqRgA8AQAuAAQKfx8AAgIACAmJHgwiAFoCAAIACAmJHgwiAFoCAAAA.Elufisti:BAAALgAECgEJBgAAAA==.Elunaire:BAACLgAFFH8GAAIDAAEJRxSRbQA9AAADAAEJRxSRbQA9AAAuAAQKfxwAAgMACQkCHJIdAFECAAMACQkCHJIdAFECAAAA.',
Em='Emelec:BAAALgAECgIJAgAAAA==.Emeraldwish:BAACLgAFFH8OAAMDAAQJliCRHgBkAQADAAQJliCRHgBkAQAIAAEJhA3bSgBDAAAuAAQKfx0AAwMACAmlI2sGACUDAAMACAmlI2sGACUDAAgAAQkAAA+wAAAAAAAA.',
En='Endz:BAAALgAECgkJAwAAAA==.',
Er='Eraline:BAAALgADCgYJBgAAAA==.Erthnite:BAAALgAECgcJCAAAAA==.',
Ev='Evinco:BAABLgAECn8aAAIVAAkJhBC8FAAHAQAVAAkJhBC8FAAHAQAAAA==.Evy:BAAALgAECgEJAgAAAA==.',
Ex='Executie:BAACLgAFFH8pAAMMAAkJaBt5AQCLAgAMAAkJaBt5AQCLAgAKAAMJGQzSEgDvAAAuAAQKfyYAAwwACQngG3gGAGQCAAwACQnLGngGAGQCAAoABglLHFw1ANQBAAAA.Exev:BAAALgADCgQJBAAAAA==.',
Ez='Ezmerrelda:BAAALgAECgYJEAAAAA==.',
Fa='Falem:BAAALgADCgYJCgAAAA==.Fancy:BAAALgAECggJDwAAAA==.',
Fe='Fey:BAABLgAECn8iAAICAAkJ5BPfTAC0AQACAAkJ5BPfTAC0AQAAAA==.',
Fi='Fieryember:BAAALgAECgQJBQABLgAFFAEJAQAFAAAAAA==.Fistvendor:BAABLgAECn8UAAIWAAkJxAgRKwBfAQAWAAkJxAgRKwBfAQAAAA==.',
Fl='Flasheals:BAABLgAECn8wAAIQAAkJLBMmIQD6AQAQAAkJLBMmIQD6AQAAAA==.Flatpak:BAAALgADCgEJAgAAAA==.Flobglop:BAAALgAECgEJAQAAAA==.Fluffybum:BAAALgADCgEJAQAAAA==.',
Fo='Foxtrot:BAACLgAFFH8LAAIGAAQJ0A+sLgDfAAAGAAQJ0A+sLgDfAAAuAAQKfyEAAgYACAk6GnAwABoCAAYACAk6GnAwABoCAAAA.',
Fr='Frostine:BAABLgAECn8ZAAIEAAcJtQdC1QBEAQAEAAcJtQdC1QBEAQAAAA==.Frostwave:BAACLgAFFH8LAAMNAAMJKBzuQQDRAAANAAMJKBzuQQDRAAAjAAEJewhEKwA8AAAuAAQKf0YABCMACQmpIJYDAKkCACMACQmVH5YDAKkCACEACAnBHXQMAEYCAA0AAQlDHaxMAVQAAAAA.Frostythot:BAAALgADCgIJAgAAAA==.',
Fu='Fujiyama:BAABLgAECn83AAIOAAgJ+yDADQCOAgAOAAgJ+yDADQCOAgAAAA==.Furryweasal:BAAALgADCgEJAQAAAA==.',
Ga='Garrex:BAAALgADCgUJBQABLgAECggJFQAGAMUWAA==.Garréosh:BAABLgAECn8WAAQJAAcJ6AlkNgCeAAAJAAYJVQpkNgCeAAAKAAQJPQVmewCFAAAMAAIJBwfdbABHAAABLgAFFAQJKAAHAFscAA==.',
Ge='Geodude:BAAALgADCgYJBwAAAA==.',
Gi='Gibborim:BAAALgAECgYJCwAAAA==.Gigilomann:BAAALgAECgMJBQAAAA==.',
Gl='Glacial:BAAALgAECgEJAQAAAA==.Glenndanzig:BAAALgADCgYJBgAAAA==.',
Go='Goldenshield:BAAALgAECgMJCQAAAA==.Golteb:BAAALgAECgQJBAAAAA==.Gonecrazy:BAAALgADCgMJAwAAAA==.Gorthan:BAAALgADCgQJBgAAAA==.',
Gr='Grabandgank:BAAALgADCgYJBgAAAA==.Gravedragon:BAAALgADCgQJBAAAAA==.Groggi:BAAALgAECgYJBAAAAA==.',
Gu='Guaresux:BAEALgADCgEJAQABLgAECgkJGQALAFARAA==.Gurnisson:BAAALgADCgUJBQAAAA==.Gusto:BAABLgAECn8uAAQaAAkJ6AvGLwB5AQAaAAkJXQvGLwB5AQAbAAgJegPMHwD2AAAZAAcJwQf2FQC1AAAAAA==.',
Ha='Hadouken:BAABLgAECn8UAAIHAAkJ5wAytwEnAAAHAAkJ5wAytwEnAAAAAA==.Hafsak:BAAALgAECgUJBQABLgAECgYJDQAFAAAAAA==.Halppme:BAAALgADCgcJBwAAAA==.Hammerfall:BAAALgAECgQJBAAAAA==.Handsome:BAAALgAECgcJBwAAAA==.',
He='Headshotte:BAAALgAECgYJDAAAAA==.Heatindabs:BAABLgAECn8gAAIDAAkJpg46SwBiAQADAAkJpg46SwBiAQAAAA==.Hexed:BAABLgAECn8XAAMkAAYJtQlGQwCpAAAkAAYJtQlGQwCpAAAgAAQJyAJ89ABZAAAAAA==.',
Hi='Hinael:BAAALgAECgEJAQAAAA==.',
Ho='Hoedus:BAAALgAECgcJEAAAAA==.Holyknight:BAAALgAECgYJDwAAAA==.Holymama:BAABLgAECn8gAAMTAAgJeh1MGQD7AQATAAcJdCBMGQD7AQASAAIJIROgYgByAAAAAA==.',
Hu='Hunkwai:BAAALgAFFAIJAgAAAA==.',
Ib='Ibok:BAAALgAECgYJCgAAAA==.',
Ic='Iceberg:BAAALgAFFAIJAwABLgAFFAkJIwAEACMjAA==.Ickma:BAABLgAECn9CAAINAAkJ0x4jGgCqAgANAAkJ0x4jGgCqAgAAAA==.',
Id='Iddou:BAAALgAECgUJCQAAAA==.',
If='Iforget:BAAALgADCgEJAQAAAA==.',
Ik='Ikona:BAAALgADCggJDgAAAA==.',
Im='Impgobrr:BAAALgAECgEJAQAAAA==.Imu:BAAALgAECgIJAwAAAA==.',
In='Incubus:BAAALgADCgEJAgAAAA==.Infari:BAAALgAECgQJBAAAAA==.',
Ir='Irdeldran:BAAALgAECgEJAQAAAA==.',
Ja='Jabjek:BAAALgADCgYJCwAAAA==.Jamaz:BAAALgAECgUJBQAAAA==.Jamwich:BAAALgADCgYJBgAAAA==.Jasonmoloa:BAAALgAECgYJDgAAAA==.',
Je='Jerazia:BAAALgAECgYJBQAAAA==.',
Jo='Johanx:BAAALgADCgMJAwAAAA==.Jordananon:BAAALgAECgMJAwAAAA==.Jordanian:BAAALgAECgMJAwAAAA==.',
['Jî']='Jînxy:BAAALgAECgEJBAAAAA==.',
Ka='Kanamé:BAAALgAECgEJAgAAAA==.Kaollanna:BAABLgAECn8jAAIEAAkJDhYWWQAuAgAEAAkJDhYWWQAuAgAAAA==.Karik:BAAALgAECgUJEQAAAA==.Kaven:BAAALgADCgIJAgAAAA==.',
Ke='Kehma:BAAALgAECgEJAQAAAA==.Keleios:BAAALgADCgYJBgABLgAECgUJDwAFAAAAAA==.Kelisa:BAABLgAECn8wAAMHAAkJPx1ZJwBmAgAHAAkJPx1ZJwBmAgARAAIJ5AtKEABWAAAAAA==.Ketchuptits:BAAALgADCgYJBgAAAA==.',
Ki='Kimaera:BAAALgAECgEJAwAAAA==.Kimjunggheal:BAAALgAECgMJBgAAAA==.Kinkster:BAAALgAECgYJCwABLgAECgYJDQAFAAAAAA==.Kinza:BAAALgADCgkJCQABLgAECggJGgAIAAAYAA==.Kirianserey:BAAALgAECgEJAQAAAA==.Kiwidin:BAABLgAECn8gAAIQAAkJuhXmJgDzAQAQAAkJuhXmJgDzAQAAAA==.',
Ko='Koketsu:BAAALgAECgYJEwAAAA==.',
Kr='Krinxy:BAABLgAECn8VAAIDAAUJFhqSWwA/AQADAAUJFhqSWwA/AQAAAA==.',
Ks='Kschwev:BAAALgADCgYJBgAAAA==.',
Ku='Kuratcha:BAAALgAFFAEJAQAAAA==.',
Ky='Kyý:BAAALgAECgYJDwAAAA==.',
['Kí']='Kíng:BAAALgAFFAEJAQABLgAFFAEJAQAFAAAAAA==.',
La='Lachoneus:BAAALgAECgEJAQAAAA==.Lazyde:BAAALgAFFAIJAgAAAA==.',
Le='Ledgerfeign:BAABLgAECn8qAAICAAkJDg12UwChAQACAAkJDg12UwChAQAAAA==.',
Li='Liadan:BAABLgAECn8lAAIQAAkJ9gx3NACAAQAQAAkJ9gx3NACAAQAAAA==.Lighteye:BAABLgAECn9JAAIDAAkJcRmEFACmAgADAAkJcRmEFACmAgAAAA==.Lilmudatruka:BAAALgADCgEJAQABLgAFFAMJDAAPAFAOAA==.Lindris:BAAALgAECgEJAQAAAA==.',
Lo='Longestibrow:BAAALgAECgMJBQAAAA==.',
Lu='Luminescence:BAAALgADCgQJBgAAAA==.Lunarqt:BAAALgAECgEJAQAAAA==.Lunchy:BAAALgAECgYJCQAAAA==.',
Ly='Lyllow:BAABLgAECn8UAAIbAAYJDhNSGgA1AQAbAAYJDhNSGgA1AQAAAA==.',
['Lø']='Løurent:BAAALgADCgQJBAAAAA==.',
Ma='Macklerina:BAAALgADCgUJCAAAAA==.Magicdorf:BAACLgAFFH8FAAIEAAIJxBR+ngCPAAAEAAIJxBR+ngCPAAAuAAQKfywAAgQACQlMIb8WANECAAQACQlMIb8WANECAAAA.Malphasia:BAAALgADCgYJBgAAAA==.Manhitrogue:BAAALgAFFAEJAQAAAA==.Massivebicep:BAAALgAECgIJAgAAAA==.Mavras:BAAALgADCgEJAQAAAA==.',
Mc='Mcbraintumor:BAAALgAECgQJCQAAAA==.Mcgavin:BAAALgAECgIJAgAAAA==.Mcsleuth:BAAALgAECgQJBgAAAA==.',
Me='Megarayquaza:BAACLgAFFH8LAAIgAAQJEgb8XADYAAAgAAQJEgb8XADYAAAuAAQKfx8AAyQACAkqEmseAMwBACQACAnIC2seAMwBACAACAk1EWliAGMBAAAA.Melissandre:BAAALgAECgUJCAAAAA==.',
Mi='Mikeyouk:BAAALgADCgYJBgAAAA==.Millertime:BAAALgAECgQJBgAAAA==.Misties:BAAALgAECgEJAQAAAA==.',
Mo='Moargoth:BAAALgADCgUJEAAAAA==.Mooneater:BAAALgAECgYJCQAAAA==.Moosedon:BAAALgAECgEJAgABLgAECgkJIAAHACAjAA==.Mordorl:BAAALgADCgcJBwAAAA==.',
Mt='Mtt:BAAALgADCgkJDgAAAA==.',
Mx='Mxx:BAABLgAECn8XAAQGAAUJbiC9TQCAAQAGAAUJbiC9TQCAAQAYAAMJMxTFTQB7AAAiAAEJzAMGlgAjAAAAAA==.',
My='Mylianne:BAABLgAECn8aAAIIAAcJYhw6HQDeAQAIAAcJYhw6HQDeAQAAAA==.Mynameiscole:BAACLgAFFH8IAAIkAAQJgh98AQCSAQAkAAQJgh98AQCSAQAuAAQKfyMAAiQACAmZJq4BAIoDACQACAmZJq4BAIoDAAEuAAUUCQkgACAAIiAA.Myrolan:BAABLgAECn8tAAIkAAkJCCSTAwAcAwAkAAkJCCSTAwAcAwAAAA==.Myrtru:BAAALgAECgkJDgAAAA==.',
['Mí']='Míyagi:BAAALgAECgYJBgAAAA==.',
Na='Naturallight:BAAALgADCgUJCAAAAA==.',
Ne='Neechka:BAAALgADCgUJBQAAAA==.Neosan:BAAALgADCgYJBgABLgAFFAMJCgAIAOciAA==.Nevyn:BAABLgAECn8zAAIlAAkJcR4/AADRAgAlAAkJcR4/AADRAgAAAA==.Newface:BAAALgADCgEJAgAAAA==.Newmoo:BAAALgAECgEJAQAAAA==.',
Ni='Nightsage:BAAALgAECgYJCgAAAA==.Niji:BAABLgAECn8VAAIEAAYJdReREABFAQAEAAYJdReREABFAQABLgAECggJGgAIAAAYAA==.Nininhp:BAABLgAECn8hAAISAAcJpRpbBADRAQASAAcJpRpbBADRAQABLgAECgkJDAAFAAAAAA==.Nithari:BAABLgAECn8/AAIEAAkJeyL8DAARAwAEAAkJeyL8DAARAwAAAA==.',
No='Nobel:BAAALgADCgEJAQAAAA==.Nomanai:BAAALgADCgkJAwAAAA==.Nosst:BAAALgAECgMJBQAAAA==.Nost:BAAALgADCgcJBwAAAA==.Nostu:BAABLgAECn8hAAMSAAkJsBYeFwAeAgASAAkJsBYeFwAeAgATAAEJbhAYhAA2AAAAAA==.Now:BAACLgAFFH8OAAIHAAQJkh9/KABpAQAHAAQJkh9/KABpAQAuAAQKfx8AAwcACAkQIOAtAGsCAAcACAlPHuAtAGsCABEABgmIF7AcADABAAAA.',
Nu='Nukum:BAAALgAECgYJEAABLgAECgkJMgAGAGcZAA==.',
Oh='Ohpa:BAABLgAECn8pAAMCAAkJ7RWbRgDGAQACAAkJdxWbRgDGAQABAAMJbw8OMQBbAAAAAA==.Ohrly:BAAALgAECgEJAQAAAA==.',
Oj='Ojikan:BAABLgAECn8WAAIeAAgJvSKkAwD2AgAeAAgJvSKkAwD2AgAAAA==.Ojpriest:BAAALgAFFAMJAwAAAA==.',
On='Onore:BAAALgAECgEJAQAAAA==.',
Pa='Pallykera:BAAALgAECgEJAQAAAA==.Papamush:BAAALgAECgMJBQAAAA==.Pathogenn:BAAALgAECgYJEAAAAA==.',
Pe='Pepecry:BAAALgAECgUJDgABLgAFFAEJAQAFAAAAAA==.',
Ph='Phoblade:BAABLgAECn8mAAINAAgJNhauUQDOAQANAAgJNhauUQDOAQAAAA==.Phobreeze:BAAALgAECgQJBgAAAA==.Phokk:BAAALgAECgcJBwAAAA==.',
Pi='Pirotess:BAABLgAECn8mAAIHAAkJgwzkDwBMAQAHAAkJgwzkDwBMAQAAAA==.',
Po='Pollymorphh:BAAALgADCgUJBgAAAA==.Ponylion:BAAALgAECgYJCwABLgAECgcJFgAHAMEUAA==.Pooshka:BAABLgAECn8dAAIOAAkJSCJiCgDvAgAOAAkJSCJiCgDvAgAAAA==.Popz:BAAALgAECgEJAQAAAA==.',
Pr='Preorcthego:BAACLgAFFH8ZAAIYAAcJ2yBWBQC6AQAYAAcJ2yBWBQC6AQAuAAQKfykAAxgACAlqJpcAAIsDABgACAlqJpcAAIsDACIAAQm/JHV7AFUAAAAA.Presibro:BAABLgAECn8aAAIJAAcJfCJCCgBOAgAJAAcJfCJCCgBOAgAAAA==.Presiric:BAAALgAECgMJAwAAAA==.Presisarian:BAAALgAECgcJEAAAAA==.',
Pu='Puck:BAAALgAECgYJDQAAAA==.Puppye:BAACLgAFFH8MAAIGAAQJARpjOQA6AQAGAAQJARpjOQA6AQAuAAQKfxgAAgYACAlNHMY0AAoCAAYACAlNHMY0AAoCAAAA.',
Ra='Ranalia:BAAALgAECgYJDAAAAA==.Ranouu:BAABLgAECn8VAAIEAAYJIBW8nACcAQAEAAYJIBW8nACcAQAAAA==.Ratatatatt:BAAALgADCgQJBQAAAA==.Raveena:BAAALgAECgMJAwAAAA==.Rawrrior:BAAALgAECgUJBQAAAA==.',
Re='Reaoibher:BAAALgADCgMJAwABLgAFFAMJCAAUAIobAA==.Recision:BAABLgAECn9BAAImAAkJySKjAQAKAwAmAAkJySKjAQAKAwABLgAFFAIJAgAFAAAAAA==.Reeash:BAABLgAECn8XAAMPAAkJABdTJQAuAgAPAAkJABdTJQAuAgAOAAMJyAt8fAB6AAAAAA==.Reeatar:BAABLgAECn8ZAAIEAAcJ5Rg9oACWAQAEAAcJ5Rg9oACWAQABLgAECgkJFwAPAAAXAA==.Relindor:BAAALgADCgYJBgABLgAFFAQJCAANAJwSAA==.Revelle:BAAALgAECgkJCwAAAA==.Reylord:BAAALgAECgQJBAAAAA==.Rezzan:BAAALgAECgEJAQAAAA==.',
Rh='Rheizen:BAACLgAFFH8MAAIJAAIJfhejEQCUAAAJAAIJfhejEQCUAAAuAAQKf10AAgkACQlHG4gBAEoCAAkACQlHG4gBAEoCAAAA.',
Ri='Riptide:BAAALgAECgEJAQAAAA==.',
Ro='Ron:BAAALgADCgQJBAAAAA==.Ropopo:BAABLgAECn8fAAISAAgJtxkrGQAIAgASAAgJtxkrGQAIAgABLgAFFAQJDAAGAAEaAA==.',
Ru='Runcat:BAABLgAECn8XAAMgAAgJQh6YJQA3AgAgAAgJQh6YJQA3AgAmAAQJ1QbnIwB/AAAAAA==.',
['Rö']='Röyksopp:BAABLgAECn8jAAIEAAgJKw/xfgB6AQAEAAgJKw/xfgB6AQAAAA==.',
Sa='Sabo:BAAALgAECgMJAwAAAA==.Sakona:BAAALgADCgEJAQAAAA==.Salbahe:BAABLgAFFH8PAAINAAQJZg23LwAKAQANAAQJZg23LwAKAQAAAA==.Samarah:BAAALgAECggJCQAAAA==.Sandewor:BAABLgAECn8UAAQRAAYJ4Re8GgBCAQARAAYJ4Re8GgBCAQAHAAMJ0QpKIgGQAAAQAAEJZgcpmAAoAAABLgAECgYJFQAYAPwMAA==.Sanfrancisco:BAAALgAECgIJAwABLgAECgIJAgAFAAAAAA==.Sarafyn:BAABLgAECn8/AAIfAAkJUxm0FQAmAgAfAAkJUxm0FQAmAgAAAA==.Sauceguzzler:BAAALgAECgYJBgAAAA==.Savath:BAAALgADCgYJBgAAAA==.',
Se='Selenagomes:BAAALgAECgEJAQABLgAFFAkJIAAgACIgAA==.Selenor:BAAALgAECgQJBwAAAA==.Seragaki:BAABLgAECn8kAAMSAAkJRRrgDQCPAgASAAkJRRrgDQCPAgATAAYJmxOHNwA3AQAAAA==.Seraphinna:BAAALgADCgEJAQAAAA==.',
Si='Siegescale:BAAALgADCgcJCwAAAA==.Siegrorc:BAABLgAECn86AAIJAAkJWRRLEADjAQAJAAkJWRRLEADjAQAAAA==.Sillidari:BAAALgADCgQJBwAAAA==.Sindrila:BAAALgAFFAEJAQAAAA==.Sionshope:BAAALgAECgUJCQAAAA==.',
Sk='Skragar:BAAALgAECgEJAgAAAA==.',
Sl='Slaybelle:BAAALgADCgYJBgAAAA==.Slayerhunt:BAABLgAECn8VAAQYAAYJ/AzcMgAXAQAYAAYJ2wvcMgAXAQAGAAQJywvegQDiAAAiAAIJqQwGeABgAAAAAA==.Slayerlock:BAAALgAECgYJCQAAAA==.Slayertin:BAAALgAECgYJCwABLgAECgYJFQAYAPwMAA==.Sleptforever:BAAALgAECgEJAQAAAA==.',
Sm='Smallpox:BAAALgAECgQJBAABLgAECgkJBQAFAAAAAA==.',
Sn='Snibdru:BAAALgAECgcJBgAAAA==.Snkrsotoole:BAABLgAECn8cAAIOAAYJgg7eVwDcAAAOAAYJgg7eVwDcAAAAAA==.',
So='Soobz:BAAALgADCgYJBgAAAA==.Sorian:BAAALgAECgUJCQAAAA==.Soulkings:BAAALgADCggJDwAAAA==.Soupies:BAAALgAECgQJBQAAAA==.Soxa:BAAALgADCgIJAgAAAA==.',
Sp='Spiikee:BAAALgAECgIJAgAAAA==.Sprays:BAAALgAECgQJBAAAAA==.',
Sr='Sry:BAAALgAECgYJBAAAAA==.',
St='Steady:BAACLgAFFH8IAAIHAAMJJAzPNAC8AAAHAAMJJAzPNAC8AAAuAAQKfxkAAgcABwluFSuaAEEBAAcABwluFSuaAEEBAAAA.Stiff:BAAALgAECgkJBwAAAA==.Stonehand:BAACLgAFFH8LAAITAAMJ3xBhJADTAAATAAMJ3xBhJADTAAAuAAQKfy0AAhMACQmgFCUaAPQBABMACQmgFCUaAPQBAAAA.Stormsurge:BAAALgAECgQJBQAAAA==.Stownt:BAAALgADCgMJAwAAAA==.Stravas:BAAALgAECgcJBwAAAA==.Strongbow:BAABLgAECn9EAAIGAAgJ9A09EABSAQAGAAgJ9A09EABSAQAAAA==.Stígma:BAAALgAECgEJAQAAAA==.',
Su='Subudai:BAAALgAECgkJEAAAAA==.Sugarboi:BAACLgAFFH8FAAInAAIJXwK+OQBBAAAnAAIJXwK+OQBBAAAuAAQKfy0AAicACQlwCvonABgBACcACQlwCvonABgBAAAA.Sugasuga:BAABLgAECn8ZAAIHAAcJhh5YPQAPAgAHAAcJhh5YPQAPAgAAAA==.Sunnymuffins:BAAALgAECgEJAQAAAA==.',
Sv='Sveetka:BAAALgAECgMJBAAAAA==.',
Sx='Sxytrev:BAAALgAECgQJCQAAAA==.',
Ta='Tabi:BAAALgADCgQJBgAAAA==.Tacoy:BAABLgAECn8fAAIKAAgJxRbaLgCUAQAKAAgJxRbaLgCUAQAAAA==.Tagsy:BAABLgAECn8VAAIGAAgJxRZdOQDJAQAGAAgJxRZdOQDJAQAAAA==.Tay:BAAALgAECgcJCwAAAA==.Tayna:BAAALgADCgYJBgAAAA==.',
Tb='Tbizkut:BAABLgAECn9GAAIVAAkJIRDSCgCVAQAVAAkJIRDSCgCVAQAAAA==.',
Th='Then:BAABLgAECn8pAAIEAAcJSBkhcACaAQAEAAcJSBkhcACaAQAAAA==.Threetimez:BAABLgAECn8XAAIGAAcJJAy1fgBCAQAGAAcJJAy1fgBCAQAAAA==.Thumbmage:BAABLgAECn8UAAIEAAYJxCBiVgDaAQAEAAYJxCBiVgDaAQABLgAFFAUJGgAOAEckAA==.',
Ti='Timemaster:BAABLgAECn8iAAQkAAgJmh0+EwD8AQAkAAgJbB0+EwD8AQAmAAEJYyKaKABiAAAgAAIJnQMT1wBCAAAAAA==.Timepacifist:BAAALgAECgcJCgAAAA==.',
To='Tobeybey:BAAALgAECgIJBgAAAA==.Tockes:BAAALgAECgEJAgAAAA==.Tokido:BAAALgAFFAEJAQAAAA==.Tongpakfu:BAABLgAECn8aAAMLAAQJTRDTdAC8AAALAAQJTRDTdAC8AAAWAAEJyQhaEwAsAAAAAA==.Topflight:BAAALgAECgcJEgAAAA==.',
Tr='Triggered:BAABLgAECn8bAAMHAAgJVBeZUQDsAQAHAAgJVBeZUQDsAQAQAAEJ0AqlngAqAAAAAA==.Troiikka:BAAALgAECgQJBQAAAA==.Troiikâ:BAABLgAECn9EAAQRAAkJphQEEADFAQARAAkJphQEEADFAQAHAAcJNgdI0QDxAAAQAAUJ8QJeawCJAAAAAA==.Troikkâ:BAAALgADCgQJBAAAAA==.Troikâ:BAAALgADCgYJBwAAAA==.Troikä:BAAALgADCgYJBgAAAA==.Trroikâ:BAABLgAECn86AAIJAAgJbhjVEADcAQAJAAgJbhjVEADcAQAAAA==.',
Tt='Tteeffinn:BAAALgADCgYJBgAAAA==.Ttevinn:BAAALgAECgMJBAABLgAECgkJBwAFAAAAAA==.Ttevoker:BAAALgAECgkJBwAAAA==.',
Tu='Tulvie:BAAALgADCgQJCAAAAA==.Tummytickle:BAAALgAECgEJAQAAAA==.Tupacaroni:BAAALgAECgMJAwAAAA==.',
Ty='Tycone:BAAALgAECgcJCgAAAA==.',
Ud='Udderpower:BAAALgAECgkJBQAAAA==.',
Ul='Uldirtydemon:BAAALgAFFAEJAQAAAA==.Uldirtydruid:BAABLgAECn8vAAMDAAgJ6B5/EQDEAgADAAgJ6B5/EQDEAgAnAAUJfBOFMQDkAAAAAA==.',
Up='Update:BAAALgAECgcJCwAAAA==.',
Ur='Urukdrak:BAABLgAECn8kAAMYAAkJJw15HwCgAQAYAAkJkAl5HwCgAQAiAAgJiQ3iMwCcAQAAAA==.',
Uw='Uwantwar:BAAALgAECgYJDwAAAA==.',
Va='Valanquishy:BAAALgADCgEJAgAAAA==.',
Ve='Velaryon:BAAALgAECgQJBAAAAA==.',
Vh='Vhagar:BAAALgAECgYJCAAAAA==.',
Vi='Vidich:BAABLgAECn8UAAMDAAcJYBeQNADJAQADAAcJYBeQNADJAQAIAAIJdgm9egBRAAAAAA==.Viralus:BAAALgADCgEJAQAAAA==.',
Vo='Vodka:BAAALgAECgEJAgAAAA==.Voiddastard:BAAALgADCgkJFwAAAA==.Voidlight:BAAALgADCgcJBwAAAA==.Volcazzic:BAAALgADCgIJAgAAAA==.',
Vy='Vynnara:BAAALgADCgMJAQAAAA==.',
Wa='Wakkaba:BAAALgADCgYJBgAAAA==.Wanaatlarboy:BAABLgAECn84AAMTAAkJWxdyAwDYAQATAAkJWxdyAwDYAQASAAEJ7gH4XgAiAAAAAA==.Waywyrd:BAAALgADCgMJAwAAAA==.',
Wh='Whack:BAAALgADCgcJCAAAAA==.',
Wi='Wipz:BAABLgAFFH8GAAIMAAMJ7gyzDwDBAAAMAAMJ7gyzDwDBAAAAAA==.',
Wu='Wunderbar:BAABLgAECn8eAAIPAAYJKxujTQB6AQAPAAYJKxujTQB6AQAAAA==.Wunderburger:BAAALgAECgYJEQAAAA==.Wunderground:BAAALgAFFAEJAQAAAA==.',
Xa='Xannada:BAABLgAECn9CAAIHAAkJmxKUTADhAQAHAAkJmxKUTADhAQAAAA==.',
Xe='Xenztrazlu:BAAALgAECgQJCwABLgAECgkJDAAFAAAAAA==.',
Ya='Yahknee:BAAALgADCgEJAQAAAA==.Yamcha:BAAALgAECggJCgAAAA==.Yaoli:BAAALgAECgMJBAAAAA==.',
Ye='Yea:BAAALgADCgcJCwAAAA==.',
Yo='Yodadogownz:BAABLgAECn8TAAITAAcJ7xBRMwBMAQATAAcJ7xBRMwBMAQAAAA==.Yoh:BAACLgAFFH8OAAINAAQJ7w97eAATAQANAAQJ7w97eAATAQAuAAQKfxwAAg0ACAlKHVxCAPsBAA0ACAlKHVxCAPsBAAAA.Yoruichee:BAAALgAECgEJBAAAAA==.Yourenotron:BAAALgAECgEJAgAAAA==.',
Yu='Yungdro:BAAALgAECgEJAQAAAA==.',
Za='Zarutobi:BAAALgAECgYJEgABLgAECggJGgAIAAAYAA==.',
Zo='Zob:BAAALgADCgQJBAAAAA==.',
Zu='Zui:BAABLgAECn8pAAIWAAkJahL2GwDFAQAWAAkJahL2GwDFAQAAAA==.',
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
