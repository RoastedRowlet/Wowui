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

local lookup = {'Shaman-Elemental','Shaman-Restoration','Monk-Mistweaver','DeathKnight-Blood','Warrior-Arms','Warrior-Fury','Warrior-Protection','Mage-Frost','Unknown-Unknown','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Rogue-Subtlety','Monk-Windwalker','Warlock-Affliction','Paladin-Retribution','Hunter-Survival','Druid-Restoration','DemonHunter-Devourer','Evoker-Preservation','Evoker-Devastation','Priest-Discipline','Paladin-Holy','DeathKnight-Unholy','Evoker-Augmentation','Monk-Brewmaster','Priest-Shadow','Druid-Balance','Druid-Guardian','DemonHunter-Havoc','DeathKnight-Frost','Priest-Holy','Shaman-Enhancement','Hunter-Marksmanship','Rogue-Assassination','DemonHunter-Vengeance','Druid-Feral',}
local provider = {region='US',realm='Gorgonnash',name='US',type='weekly',zone=46,date='2026-08-18',data={Aa='Aakira:BAABLgAECn8VAAMBAAkJzQguPgA8AQABAAkJzQguPgA8AQACAAEJuAMA6wAkAAAAAA==.Aangie:BAABLgAECn8YAAIDAAcJngZMPAD0AAADAAcJngZMPAD0AAAAAA==.Aanjie:BAABLgAECn8aAAIDAAYJQwkcbADSAAADAAYJQwkcbADSAAAAAA==.Aathea:BAAALgAECgYJBgAAAA==.',
Ab='Abban:BAAALgAECgMJAwAAAA==.Abom:BAAALgAECgIJAgAAAA==.Abrastal:BAAALgAECgQJCAAAAA==.',
Ad='Adrestia:BAAALgAECgQJBgAAAA==.',
Ak='Akbar:BAAALgAECgUJBQAAAA==.',
Al='Alline:BAABLgAECn8dAAIEAAYJcBLTJgAdAQAEAAYJcBLTJgAdAQAAAA==.Alswaron:BAAALgAECgUJEwAAAA==.',
Am='Amador:BAACLgAFFH8cAAQFAAQJGh/eEwA/AQAFAAQJnB3eEwA/AQAGAAQJkxupFAD5AAAHAAEJnB1eKgBKAAAuAAQKfyoABAUACQl5IucGAIwCAAUACAl5IucGAIwCAAYABAndGulpAA4BAAcAAgmuFo06AHcAAAAA.Amorlan:BAAALgAECgEJAQAAAA==.Amyra:BAAALgAECgEJAQAAAA==.',
An='Annox:BAAALgAECgQJBwAAAA==.',
Ap='Apsallar:BAABLgAECn8gAAIIAAkJzBx7HwChAgAIAAkJzBx7HwChAgAAAA==.',
Ar='Arachne:BAAALgAECgEJAgABLgAECgkJEQAJAAAAAA==.Arayli:BAAALgADCgYJBgAAAA==.Arcanedream:BAAALgAECgUJBQABLgAECgkJCgAJAAAAAA==.Arcanism:BAABLgAECn8cAAIIAAcJshOjngCZAQAIAAcJshOjngCZAQAAAA==.Arlas:BAAALgAECgUJCwABLgAECgYJDAAJAAAAAA==.Arthone:BAAALgADCgUJBQAAAA==.',
As='Aserai:BAAALgADCgMJAwAAAA==.Asstalor:BAABLgAECn8dAAMKAAgJmxAfZQB0AQAKAAgJWxAfZQB0AQALAAEJjxJsPgA0AAAAAA==.',
Au='Auggy:BAAALgAECgMJAwAAAA==.Auryon:BAACLgAFFH8HAAIMAAEJcxjdcgBFAAAMAAEJcxjdcgBFAAAuAAQKfzEAAgwACAkDInsiAFoCAAwACAkDInsiAFoCAAAA.',
Av='Avadacadabra:BAAALgAECgEJAgAAAA==.Avelna:BAAALgADCgcJBwABLgADCgcJDQAJAAAAAA==.',
Az='Azmodea:BAAALgAECgEJAgAAAA==.',
Ba='Baccstab:BAAALgAECgYJDAAAAA==.Bagains:BAAALgADCgcJEwAAAA==.Bangnyfe:BAAALgAFFAIJAgABLgAFFAMJBgANAJgZAA==.Baragor:BAAALgAECgQJBAABLgAFFAQJGAAOABUUAA==.Baraka:BAAALgAECgYJCgAAAA==.Baulder:BAABLgAECn8cAAIGAAcJawdeUQAEAQAGAAcJawdeUQAEAQAAAA==.',
Bi='Bigb:BAAALgAFFAEJAQABLgAFFAkJVwAIAGwmAA==.Bigolcrittie:BAAALgADCgIJAgAAAA==.',
Bl='Bleedwoundz:BAAALgAECgYJCgABLgADCgUJBQAJAAAAAA==.Blerpleberry:BAAALgAECgUJBQAAAA==.Bloodfurry:BAAALgAECgMJAQAAAA==.Bluè:BAABLgAECn8fAAMBAAkJpRl7BADdAQABAAkJpRl7BADdAQACAAUJjBr/TQB5AQAAAA==.',
Bn='Bnakka:BAAALgAFFAEJAQAAAA==.',
Bo='Bobdaunicorn:BAAALgAECgEJAQAAAA==.Boltz:BAAALgAECgMJAwABLgAFFAMJBgAPADgOAA==.Bombalaharis:BAAALgAECgcJDQAAAA==.',
Br='Brekke:BAACLgAFFH8MAAIQAAQJsQ+qSwAWAQAQAAQJsQ+qSwAWAQAuAAQKfy8AAhAACQlgGKs1ACoCABAACQlgGKs1ACoCAAAA.Brokenbow:BAACLgAFFH8HAAMRAAQJjQrZIADSAAARAAMJwgfZIADSAAAMAAEJ7BK/pABJAAAuAAQKfxsAAxEACQmmE3IfAKABABEACQnNDnIfAKABAAwABAkIGMV9AO4AAAAA.',
Bu='Bullshaft:BAAALgAECgEJAQAAAA==.Buntz:BAABLgAECn8qAAIQAAkJgCOZDAAAAwAQAAkJgCOZDAAAAwAAAA==.Bushmethsin:BAACLgAFFH8cAAISAAgJFCNrBQC7AgASAAgJFCNrBQC7AgAuAAQKfxUAAhIACAlVIg0eAE4CABIACAlVIg0eAE4CAAAA.Buttery:BAABLgAECn8UAAIQAAcJABd2hgBjAQAQAAcJABd2hgBjAQAAAA==.',
Bz='Bz:BAAALgADCgcJBwAAAA==.',
Ca='Cabb:BAABLgAECn8ZAAMGAAYJihaARwAoAQAGAAQJGxqARwAoAQAHAAYJsgcjMQC5AAAAAA==.Calcus:BAAALgAECgEJAQAAAA==.',
Ce='Ceedubble:BAAALgAECgkJEAAAAA==.Celestine:BAAALgADCgYJBgABLgAECgkJKAATAEsOAA==.',
Ch='Charmanderz:BAABLgAECn8mAAMUAAgJIxG2FQBxAQAUAAgJIxG2FQBxAQAVAAEJIhWjOwA/AAABLgAECgkJFAAWAO8LAA==.Cherchlglsia:BAAALgADCgQJCAAAAA==.Chewsdee:BAAALgAECgQJBAAAAA==.Christlovesu:BAAALgAECgIJAgAAAA==.Chuckrules:BAAALgADCgcJDgAAAA==.',
Cl='Clackshi:BAAALgAECgYJCgAAAA==.',
Cr='Critable:BAABLgAECn80AAMXAAkJIxY8GwAqAgAXAAkJIxY8GwAqAgAQAAkJuAoXggB2AQAAAA==.',
Cu='Curst:BAAALgAECggJEwAAAA==.',
Da='Dagares:BAAALgADCggJDQAAAA==.Dahnte:BAAALgAECgEJAQAAAA==.',
De='Dechala:BAABLgAECn8oAAITAAkJSw5BUwCMAQATAAkJSw5BUwCMAQAAAA==.Deezknights:BAACLgAFFH8VAAMYAAgJzBwLEwBDAgAYAAgJzBwLEwBDAgAEAAEJAACTWQAAAAAuAAQKfycAAhgACQkGJU4JAFIDABgACQkGJU4JAFIDAAAA.Deezpuffs:BAABLgAFFH8KAAMZAAQJOxVSLgAKAQAZAAQJOxVSLgAKAQAUAAEJpQD5MAAiAAABLgAFFAgJFQAYAMwcAA==.Deezrage:BAAALgADCgYJBgAAAA==.Demonharvest:BAAALgAECgkJCQAAAA==.Derailed:BAAALgADCgEJAgAAAA==.Dergon:BAACLgAFFH8HAAIKAAMJNw3IfADKAAAKAAMJNw3IfADKAAAuAAQKfykAAgoACQloHEUkAE4CAAoACQloHEUkAE4CAAAA.Destiria:BAABLgAECn8kAAMKAAgJuBnfQQDWAQAKAAgJuBnfQQDWAQAPAAMJegd5JwBUAAAAAA==.Devistatorxx:BAAALgAECgYJCgAAAA==.',
Do='Doggyystyle:BAAALgAECgEJAQAAAA==.Dogwalker:BAAALgAFFAIJBAABLgAFFAMJBgAPADgOAA==.Domincan:BAAALgADCgEJAQAAAA==.Donaldpump:BAAALgAECgYJBwAAAA==.Doomedturtle:BAAALgAECgYJCAAAAA==.Doublekill:BAAALgAECgUJDAAAAA==.',
Du='Duergan:BAACLgAFFH8YAAIOAAQJFRTnCgD3AAAOAAQJFRTnCgD3AAAuAAQKfzMABA4ACQnwGCYFAGQBAA4ACQnwGCYFAGQBABoACQkICr4GANgAAAMAAQlFAwRyACEAAAAA.',
['Dà']='Dàrkblade:BAABLgAECn8VAAIQAAcJDxhZDACiAQAQAAcJDxhZDACiAQAAAA==.',
Ea='Eatz:BAAALgADCgYJBgAAAA==.',
Eh='Ehcks:BAAALgAECgQJBAAAAA==.',
Em='Emotionaldmg:BAAALgADCgYJCwAAAA==.',
Fa='Faelyn:BAAALgADCgEJBAAAAA==.Fansy:BAABLgAFFH8IAAIHAAUJggOEDgDDAAAHAAUJggOEDgDDAAAAAA==.',
Fe='Felbeard:BAAALgAECgQJBgAAAA==.Felbreaker:BAAALgAECgEJAQAAAA==.Felspark:BAAALgAECgYJDQAAAA==.Felwind:BAABLgAECn8mAAIMAAcJ6iNZCQDrAQAMAAcJ6iNZCQDrAQAAAA==.Ferus:BAAALgADCgkJCQAAAA==.',
Fi='Fillycheese:BAAALgAECgEJAQAAAA==.',
Fl='Fleurelle:BAAALgAECgkJEQAAAA==.',
Fr='Frollo:BAAALgAECgEJAQAAAA==.Frosstitute:BAAALgAECgMJAwAAAA==.',
Fu='Furfiend:BAACLgAFFH8LAAIYAAQJRBq8VQBGAQAYAAQJRBq8VQBGAQAuAAQKfykAAxgACQndHyUrAFMCABgACQlaHiUrAFMCAAQABQk4G5woABABAAAA.',
Gb='Gb:BAAALgAFFAIJAgABLgAFFAQJDQAbAPIaAA==.',
Gi='Giantdog:BAAALgAECgUJBQAAAA==.Gilraen:BAACLgAFFH8RAAMGAAQJmA5lKAAUAQAGAAQJ8wxlKAAUAQAFAAEJXQ/bRAA9AAAuAAQKf0gAAwYACQmnHsMBAKQCAAYACQnuHMMBAKQCAAUACQn5FgQOAAkCAAAA.Gingerjen:BAABLgAECn8UAAMSAAgJ9wefZQADAQASAAgJ9wefZQADAQAcAAgJcgMvUgDFAAAAAA==.',
Go='Gorgrand:BAAALgAECgcJBwAAAA==.Gothbiotch:BAAALgAECgMJAwAAAA==.',
Gr='Greaseduppig:BAAALgAECgEJAQAAAA==.Greggnog:BAAALgAECgkJDAAAAA==.Greggy:BAAALgAECgUJCQABLgAECgkJDAAJAAAAAA==.Grenache:BAAALgAECgMJBAAAAA==.',
Ha='Hagarirn:BAAALgAECgEJAQAAAA==.Hairypotter:BAAALgADCgUJBQAAAA==.Halfworld:BAAALgADCgYJBgAAAA==.Happydaze:BAACLgAFFH8VAAMEAAQJJQ5fEwDJAAAEAAQJJQ5fEwDJAAAYAAEJcwXOrQAyAAAuAAQKfysAAwQACQlUG+IPAA0CAAQACQkGG+IPAA0CABgAAwloEowsAXMAAAAA.Harshdruid:BAAALgAECgEJAQABLgAFFAMJCwAWAL8SAA==.Haxthedk:BAAALgAECgEJAQAAAA==.Haxthedruid:BAAALgAECgEJAQAAAA==.Haxthemonk:BAAALgAECgEJAQAAAA==.',
He='Hemotoxin:BAAALgAECgMJAwAAAA==.Hendel:BAAALgAECgQJBgAAAA==.Herkaferk:BAABLgAECn8XAAIBAAYJiBMqRQAfAQABAAYJiBMqRQAfAQAAAA==.',
Ho='Hojx:BAAALgAECgEJAQAAAA==.',
Hr='Hrolf:BAABLgAECn9DAAMdAAkJ6hJXBACNAQAdAAkJ6hJXBACNAQASAAEJyRGyzwA1AAABLgAFFAQJGAAOABUUAA==.',
Il='Illiannà:BAABLgAECn8UAAMWAAkJ7wujJQCjAQAWAAkJ7wujJQCjAQAbAAEJwRUsfgBBAAAAAA==.Illidont:BAABLgAECn8WAAIeAAkJWRAYHACcAQAeAAkJWRAYHACcAQAAAA==.Illijr:BAABLgAECn8dAAIeAAkJexSZFQDgAQAeAAkJexSZFQDgAQAAAA==.',
It='Ithil:BAAALgADCgkJDwAAAA==.',
Ja='Jaemison:BAAALgADCgQJAwABLgAECgkJcwAMAG0mAA==.',
Ji='Jicks:BAABLgAECn8jAAIWAAkJ6QtoOgAmAQAWAAkJ6QtoOgAmAQAAAA==.',
Jk='Jkass:BAACLgAFFH8QAAINAAQJcAwlFwDHAAANAAQJcAwlFwDHAAAuAAQKfxsAAg0ACAn+FgccALYBAA0ACAn+FgccALYBAAAA.',
Ju='Judgementdày:BAAALgAECggJCgAAAA==.',
['Jà']='Jàk:BAAALgAECgIJAgAAAA==.',
Ka='Kaldarr:BAAALgAECgEJAQAAAA==.Kamaeria:BAACLgAFFH8WAAIbAAUJxAQuGQCSAAAbAAUJxAQuGQCSAAAuAAQKfzkAAhsACQn0FDAWABkCABsACQn0FDAWABkCAAAA.Kaíros:BAAALgADCgMJAwAAAA==.',
Kh='Khaotica:BAAALgADCgkJCQAAAA==.',
Ki='Kiandara:BAACLgAFFH8dAAMGAAcJARkFHgA5AQAGAAcJARkFHgA5AQAFAAQJwRJAGwAPAQAuAAQKfyQAAwYACQmQHPIMAO4CAAYACQmQHPIMAO4CAAcABQkcG94dAFcBAAAA.Kikkoman:BAABLgAFFH8GAAINAAMJmBltJAAAAQANAAMJmBltJAAAAQAAAA==.Kilmas:BAAALgAECgIJAgAAAA==.Kinetic:BAAALgAECgEJAQAAAA==.Kirant:BAAALgADCggJDQAAAA==.Kirara:BAAALgADCgYJBgAAAA==.',
Ko='Kooz:BAAALgADCgUJBQAAAA==.Kooze:BAAALgADCgUJCAAAAA==.Koozo:BAAALgADCgMJAwAAAA==.Kozar:BAAALgAECgcJBwAAAA==.',
Kt='Kt:BAABLgAECn8aAAIIAAcJNhNlmQBGAQAIAAcJNhNlmQBGAQAAAA==.',
Ku='Kush:BAAALgADCgEJAQABLgAECgkJKgAQAIAjAA==.',
Ky='Kynrath:BAAALgAECgkJDAAAAA==.',
La='Laurie:BAAALgADCgMJBgAAAA==.Lava:BAAALgADCgUJBQABLgAECgkJFQAeAOcdAA==.Lavablast:BAAALgADCgYJCwAAAA==.',
Le='Lelanie:BAAALgADCggJDgAAAA==.',
Li='Lichnfamous:BAACLgAFFH8JAAIYAAQJ/AtTdwAUAQAYAAQJ/AtTdwAUAQAuAAQKfykAAxgACAnRFa9NANkBABgACAnRFa9NANkBAB8ABAnqDOwfAM0AAAAA.Lightfrost:BAAALgAECgMJAwABLgAECgQJBgAJAAAAAA==.Lightning:BAAALgAECgUJCAAAAA==.Likkan:BAAALgAECgEJAQAAAA==.Lilithdawn:BAABLgAECn8jAAIgAAkJvhvsEABdAgAgAAkJvhvsEABdAgAAAA==.',
Lo='Lockwar:BAACLgAFFH8GAAIPAAMJOA4NEQCIAAAPAAMJOA4NEQCIAAAuAAQKfx8ABA8ACQmbF/YKAK8BAA8ACQmbF/YKAK8BAAoABAkUB97lAJIAAAsAAQlPAOlJAAUAAAAA.Louvre:BAABLgAECn8uAAINAAkJtxx2CQCOAgANAAkJtxx2CQCOAgAAAA==.Lowehigh:BAAALgAECgIJAgAAAA==.',
Lu='Lukarian:BAABLgAFFH8GAAIQAAMJiw4hcgDOAAAQAAMJiw4hcgDOAAAAAA==.Luminaughty:BAAALgAECgEJAgAAAA==.',
Ma='Macemen:BAAALgAECgEJAQAAAA==.Magènta:BAAALgAECgMJAwAAAA==.Makthra:BAAALgAECgUJEQAAAA==.Marek:BAAALgADCgUJCAAAAA==.Marionette:BAAALgAECgMJAwAAAA==.Mashka:BAAALgAECgMJAwAAAA==.Mawseeker:BAAALgADCgEJAQAAAA==.',
Me='Megabettegaa:BAACLgAFFH8aAAMYAAQJQBeqOgDuAAAYAAQJQBeqOgDuAAAfAAEJqQSpHwA5AAAuAAQKf4cAAhgACQkGG6gsAE0CABgACQkGG6gsAE0CAAAA.Melbukai:BAAALgAECgUJCAAAAA==.Melbuki:BAAALgAECgUJDAAAAA==.Mennathil:BAAALgADCgEJAQAAAA==.Meric:BAAALgAECgEJAwAAAA==.',
Mi='Microbrew:BAAALgAECgcJDAABLgAFFAMJCgAdAN4KAA==.Midnight:BAAALgAECgcJCQABLgAECgkJCgAJAAAAAA==.Milo:BAAALgAFFAEJAQAAAA==.Miniangel:BAACLgAFFH8RAAMgAAUJjxSaDwBZAQAgAAUJjxSaDwBZAQAbAAIJfQFANwBXAAAuAAQKfx4AAyAACQl8FVYVACoCACAACQl8FVYVACoCABsACAk+EPAoAJMBAAAA.Mixednuts:BAAALgAECgIJAgAAAA==.',
Mo='Molasses:BAACLgAFFH8jAAIIAAUJahQcLQAZAQAIAAUJahQcLQAZAQAuAAQKf0AAAggACQnTHqMXAMsCAAgACQnTHqMXAMsCAAAA.Moof:BAAALgAECgEJAQAAAA==.',
['Má']='Márionette:BAAALgAECgEJAQAAAA==.',
['Mú']='Músic:BAAALgAECgIJAwAAAA==.',
Na='Najitar:BAAALgAECgQJBQAAAA==.Nazaibrew:BAAALgAECggJDAABLgAECgkJOwAWAE4fAA==.Nazera:BAAALgAECgEJAQAAAA==.',
Ne='Necromalus:BAAALgAECgEJAgAAAA==.Neerx:BAAALgADCgUJBQAAAA==.',
Ni='Nimos:BAAALgAECgEJAQAAAA==.',
Nu='Nubkselk:BAABLgAECn80AAITAAkJWh4JFgCTAgATAAkJWh4JFgCTAgAAAA==.Nurishment:BAACLgAFFH8fAAISAAkJyRR+DAArAgASAAkJyRR+DAArAgAuAAQKfyUAAhIACQn7HWwSAKICABIACQn7HWwSAKICAAAA.',
Ny='Nyrr:BAAALgADCgEJAgAAAA==.',
Og='Ogmurka:BAAALgAECgEJAQAAAA==.',
On='Oni:BAAALgADCgUJBQAAAA==.Onitachi:BAABLgAECn8rAAMBAAgJzxH3RgAYAQABAAgJzxH3RgAYAQAhAAQJcAmcLgCDAAAAAA==.',
Op='Optistriker:BAABLgAECn9LAAISAAkJaxknFQChAgASAAkJaxknFQChAgAAAA==.',
Oy='Oythsar:BAAALgADCgQJBAAAAA==.',
Pa='Painfree:BAAALgADCgQJBAAAAA==.Papabear:BAAALgAECgEJAQAAAA==.Parasite:BAAALgAECgEJBAAAAA==.',
Pe='Pemburumalam:BAAALgADCgEJAQAAAA==.',
Pi='Pig:BAABLgAECn8cAAIGAAgJKhjaKwAGAgAGAAgJKhjaKwAGAgABLgAECgkJKgAQAIAjAA==.Pinks:BAAALgADCgkJCQAAAA==.Pizlex:BAAALgAECgcJCQAAAA==.',
Po='Poplockndrop:BAAALgAECgUJBgAAAA==.Portion:BAABLgAECn8uAAIIAAgJWhxQVwDXAQAIAAgJWhxQVwDXAQAAAA==.Portlybob:BAAALgADCgEJAQAAAA==.Potatoe:BAAALgAECgQJBgAAAA==.',
Pr='Pretentious:BAACLgAFFH8GAAIQAAQJrQzUUAANAQAQAAQJrQzUUAANAQAuAAQKfx4AAhAACAmiHysmAI4CABAACAmiHysmAI4CAAAA.Prettyfun:BAAALgADCgUJBQAAAA==.Prettysavage:BAAALgAECgIJAgAAAA==.Primo:BAAALgADCgYJEQAAAA==.',
['Pè']='Pèrsephônè:BAAALgADCgIJAgAAAA==.',
Ra='Radicalism:BAAALgAECgQJBQAAAA==.Raechan:BAAALgAECgEJAQAAAA==.Ranigard:BAAALgAECgUJCAAAAA==.Rantioc:BAAALgAECgYJBgAAAA==.Raugan:BAAALgAECgEJAwAAAA==.',
Re='Reparations:BAABLgAECn8gAAMbAAgJlAgaEQC7AAAbAAgJlAgaEQC7AAAWAAUJugIwYgB0AAAAAA==.Repentofsin:BAAALgAECgQJBAAAAA==.Rexbriefs:BAABLgAECn8+AAIYAAcJ4hNyEgAlAQAYAAcJ4hNyEgAlAQAAAA==.',
Ri='Rice:BAAALgAFFAEJAQABLgAFFAMJBgAPADgOAA==.Riptong:BAAALgADCgEJAQAAAA==.',
Ro='Rovinj:BAAALgAECgkJBwAAAA==.',
Ru='Rukhmear:BAAALgAECgEJAQAAAA==.Rumi:BAABLgAECn8lAAITAAkJLBi8PwDKAQATAAkJLBi8PwDKAQAAAA==.',
Ry='Rydle:BAABLgAFFH8JAAMMAAQJsQ59XwDmAAAMAAQJsQ59XwDmAAAiAAEJYQc0IgAzAAAAAA==.',
Sa='Samedhi:BAAALgAECgQJBQAAAA==.Sanlesh:BAAALgADCgUJBgAAAA==.Sapodillà:BAAALgAECggJDQAAAA==.Sarijevo:BAAALgAECgkJBQAAAA==.Saurax:BAAALgAECgIJAwAAAA==.',
Sc='Scatz:BAAALgADCgIJAgAAAA==.Scott:BAAALgAECgcJCwAAAA==.Scylla:BAAALgAECgYJDwAAAA==.',
Se='Seraxx:BAAALgADCgEJAQAAAA==.Sevrin:BAACLgAFFH8jAAINAAgJshzRAwBrAgANAAgJshzRAwBrAgAuAAQKfy8AAg0ACQlrIx8FAOQCAA0ACQlrIx8FAOQCAAAA.Sevro:BAAALgAECgEJAQAAAA==.',
Sh='Shadowfuryy:BAAALgAECgUJBQAAAA==.Shalati:BAAALgADCgYJBgABLgAECgkJcwAMAG0mAA==.Sharts:BAAALgADCgYJCQAAAA==.Shestrouble:BAACLgAFFH8GAAIIAAIJyhvClgChAAAIAAIJyhvClgChAAAuAAQKfyUAAggACQn1IikKACgDAAgACQn1IikKACgDAAAA.Shiift:BAAALgAECgMJAwABLgAFFAMJDgANAPEiAA==.Shirerat:BAAALgADCgMJBAAAAA==.Shtzson:BAABLgAECn8iAAIaAAkJhxtcAQBaAgAaAAkJhxtcAQBaAgAAAA==.Shyjinx:BAAALgAECgYJBgAAAA==.Shíft:BAAALgAECgUJBQABLgAFFAMJDgANAPEiAA==.Shííft:BAAALgAECgUJBQABLgAFFAMJDgANAPEiAA==.Shîft:BAACLgAFFH8OAAINAAMJ8SJgHQA0AQANAAMJ8SJgHQA0AQAuAAQKfzQAAw0ACQnvI6kGAMMCAA0ACAnPI6kGAMMCACMAAwl0H40SAP0AAAAA.Shïìft:BAAALgAFFAEJAQABLgAFFAMJDgANAPEiAA==.',
Si='Siiwwy:BAAALgAECgMJAwAAAA==.',
Sl='Slice:BAABLgAFFH8JAAMkAAMJJAoABwCGAAAkAAMJJAoABwCGAAAeAAIJ6wJkJQAoAAAAAA==.',
So='Sok:BAAALgAECgEJAwAAAA==.Soktear:BAAALgAECgEJAgAAAA==.Soladin:BAAALgAECgQJBQABLgAFFAMJCgAdAN4KAA==.Soladis:BAAALgAECgcJDAABLgAECgkJIgAaAIcbAA==.Solicide:BAACLgAFFH8KAAQdAAMJ3gqZGQBnAAAdAAMJGQiZGQBnAAASAAIJRwQYLABFAAAlAAEJBg9cHQBCAAAuAAQKfzcABR0ACQlxG2wPAPABAB0ACAniGGwPAPABACUABwnxG9oMAOgBABIAAQlEExvIADoAABwAAQnaDgGPADEAAAAA.Solthicc:BAAALgAECggJDQAAAA==.Sonarra:BAAALgAECgYJBgAAAA==.',
Sp='Sparkle:BAACLgAFFH8nAAIZAAgJoxRJFADRAQAZAAgJoxRJFADRAQAuAAQKf4wAAxkACQkhJt4AAIEDABkACQkhJt4AAIEDABUAAwlKI1oCACkBAAAA.Splatacular:BAAALgADCgEJAQAAAA==.',
St='Stolenhearth:BAABLgAECn8tAAIGAAYJ3w8KDwDfAAAGAAYJ3w8KDwDfAAAAAA==.',
Sv='Svets:BAABLgAECn87AAMWAAkJTh/jCADlAgAWAAkJTh/jCADlAgAgAAEJ3AnKhQArAAAAAA==.',
Sw='Swavey:BAAALgADCgQJBAAAAA==.',
Sy='Sylmeria:BAAALgAECgUJBwAAAA==.Sylphrenna:BAAALgAECgcJCQAAAA==.Syrana:BAAALgADCgEJAQAAAA==.',
Te='Teeanna:BAAALgAECgYJDAAAAA==.Temaile:BAAALgADCgEJBAAAAA==.Tenin:BAAALgADCgEJAQAAAA==.',
Th='Thinmint:BAAALgADCgEJAQAAAA==.Thoranter:BAAALgADCgYJCQAAAA==.',
Ti='Tinnman:BAAALgADCgYJBgAAAA==.',
To='Toughguytony:BAAALgADCgUJBgAAAA==.',
Tr='Trebekk:BAAALgADCgEJAQAAAA==.Treydk:BAACLgAFFH8NAAIYAAQJWh0vTwBUAQAYAAQJWh0vTwBUAQAuAAQKfxwAAxgACQm/HdMZAKwCABgACQl2HdMZAKwCAB8ABQkYHGIZAAgBAAAA.Trreyy:BAABLgAECn8fAAIQAAgJqh5YKACEAgAQAAgJqh5YKACEAgAAAA==.',
Ts='Tsimfuqis:BAABLgAFFH8LAAINAAQJMhJAHgAvAQANAAQJMhJAHgAvAQAAAA==.',
Tw='Twighumper:BAAALgAECgUJBwABLgAECgkJIgAaAIcbAA==.Twizzly:BAAALgAFFAIJAgAAAA==.Twizzy:BAACLgAFFH8VAAIMAAQJAQbiPwCwAAAMAAQJAQbiPwCwAAAuAAQKf0IAAgwACQnyFJwoADwCAAwACQnyFJwoADwCAAEuAAUUBQkWABsAxAQA.',
Ty='Tyranhikar:BAAALgADCgEJAQAAAA==.',
Tz='Tzechan:BAACLgAFFH8GAAIXAAMJ8RpQJgDvAAAXAAMJ8RpQJgDvAAAuAAQKfx8AAxcACQkiG/EdABMCABcACQkiG/EdABMCABAAAgmcEp1BAWoAAAAA.',
Ug='Uggalee:BAAALgAFFAIJAwAAAA==.',
Va='Valtirya:BAAALgAECgQJBgAAAA==.Vampirellaa:BAAALgAECgEJAgAAAA==.Vanaria:BAAALgAECgQJBAAAAA==.Vayzen:BAABLgAECn8YAAIZAAcJDB4uEwBNAgAZAAcJDB4uEwBNAgAAAA==.',
Ve='Velac:BAAALgAECgUJCwAAAA==.',
Vi='Virexus:BAAALgADCgIJAgAAAA==.',
Vo='Voidfree:BAABLgAECn8tAAITAAkJfwwbGADGAAATAAkJfwwbGADGAAAAAA==.',
Vy='Vynarc:BAABLgAECn8qAAIQAAgJihHPZQC1AQAQAAgJihHPZQC1AQAAAA==.',
Wa='Warcrimes:BAAALgAECgEJAQAAAA==.Watervendor:BAABLgAECn8vAAIIAAkJgBvYMABWAgAIAAkJgBvYMABWAgAAAA==.',
We='Wearegroot:BAAALgAECgEJAQAAAA==.Webedeadiy:BAAALgADCgEJAQAAAA==.',
Wh='Whiteknight:BAAALgAECgYJBgAAAA==.',
Wi='Wiggimbottom:BAAALgAECgYJEgAAAA==.Wihtè:BAAALgAECgMJAwAAAA==.Willscarlet:BAAALgADCgQJBAAAAA==.',
Wo='Wolffoxfangs:BAABLgAECn8VAAIMAAcJ/BVvaAByAQAMAAcJ/BVvaAByAQAAAA==.',
Wx='Wxyzptlk:BAAALgADCgYJBgABLgAECgkJIwAgAL4bAA==.',
['Wá']='Wárpaiint:BAABLgAECn8uAAMMAAcJfhM6EwBOAQAMAAQJlho6EwBOAQAiAAcJoQujFwD2AAABLgAECgcJJgASAGcbAA==.',
Xa='Xalatoes:BAAALgAECgUJBQAAAA==.',
Xe='Xeados:BAAALgAECgIJAgAAAA==.Xenos:BAAALgAECgEJAgAAAA==.',
Yi='Yin:BAAALgADCgcJDQAAAA==.',
['Yè']='Yèlloow:BAAALgAECgMJBQAAAA==.',
Za='Zaquel:BAABLgAECn8UAAMMAAgJ/xpCUgCsAQAMAAgJOhdCUgCsAQARAAcJQhJvIgCKAQABLgAFFAQJEwAQAGwPAA==.Zarcissa:BAABLgAECn8VAAIQAAcJnRl5DgCDAQAQAAcJnRl5DgCDAQAAAA==.Zaritus:BAAALgADCgEJAQAAAA==.Zavira:BAAALgADCgcJBwAAAA==.',
Ze='Zerofoxgiven:BAAALgAECgYJBgAAAA==.',
Zy='Zyrin:BAAALgAECgYJDwAAAA==.',
['ßl']='ßlackpanther:BAAALgAECgcJDwAAAA==.',
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
