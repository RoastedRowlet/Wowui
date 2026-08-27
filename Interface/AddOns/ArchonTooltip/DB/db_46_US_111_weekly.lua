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

local lookup = {'Shaman-Elemental','Shaman-Restoration','Monk-Mistweaver','Priest-Discipline','DeathKnight-Blood','Warrior-Arms','Warrior-Fury','Warrior-Protection','Mage-Frost','Unknown-Unknown','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Rogue-Subtlety','Monk-Windwalker','Warlock-Affliction','Paladin-Retribution','Hunter-Survival','Druid-Restoration','DemonHunter-Devourer','Evoker-Preservation','Evoker-Devastation','Paladin-Holy','DeathKnight-Unholy','Evoker-Augmentation','Monk-Brewmaster','Priest-Shadow','Druid-Balance','Druid-Guardian','DemonHunter-Havoc','DeathKnight-Frost','Priest-Holy','Shaman-Enhancement','Hunter-Marksmanship','Rogue-Assassination','DemonHunter-Vengeance','Druid-Feral',}
local provider = {region='US',realm='Gorgonnash',name='US',type='weekly',zone=46,date='2026-08-25',data={Aa='Aakira:BAABLgAECn8VAAMBAAkJzQguPgA8AQABAAkJzQguPgA8AQACAAEJuAMA6wAkAAAAAA==.Aangie:BAABLgAECn8YAAIDAAcJngZMPAD0AAADAAcJngZMPAD0AAAAAA==.Aanjie:BAABLgAECn8aAAIDAAYJQwkcbADSAAADAAYJQwkcbADSAAAAAA==.Aathea:BAAALgAECgYJBgAAAA==.',
Ab='Abban:BAAALgAECgMJAwAAAA==.Abom:BAAALgAECgIJAgAAAA==.Abrastal:BAAALgAECgQJCAAAAA==.',
Ad='Adrestia:BAAALgAECgQJBgABLgAECgkJFAAEAO8LAA==.',
Ak='Akbar:BAAALgAECgUJBQAAAA==.',
Al='Alline:BAABLgAECn8dAAIFAAYJcBLTJgAdAQAFAAYJcBLTJgAdAQAAAA==.Alswaron:BAAALgAECgUJEwAAAA==.',
Am='Amador:BAACLgAFFH8cAAQGAAQJGh/eEwA/AQAGAAQJnB3eEwA/AQAHAAQJkxuqFAD5AAAIAAEJnB1eKgBKAAAuAAQKfyoABAYACQl5IucGAIwCAAYACAl5IucGAIwCAAcABAndGulpAA4BAAgAAgmuFo06AHcAAAAA.Amorlan:BAAALgAECgEJAQAAAA==.Amyra:BAAALgAECgEJAQAAAA==.',
An='Annox:BAAALgAECgQJBwAAAA==.',
Ap='Apsallar:BAABLgAECn8gAAIJAAkJzBx7HwChAgAJAAkJzBx7HwChAgAAAA==.',
Ar='Arachne:BAAALgAECgEJAgABLgAECgkJEQAKAAAAAA==.Arayli:BAAALgADCgYJBgAAAA==.Arcanedream:BAAALgAECgUJBQABLgAECgkJCgAKAAAAAA==.Arcanism:BAABLgAECn8cAAIJAAcJshOjngCZAQAJAAcJshOjngCZAQAAAA==.Arlas:BAAALgAECgUJCwABLgAECgYJDAAKAAAAAA==.Arthone:BAAALgADCgUJBQAAAA==.',
As='Aserai:BAAALgADCgMJAwAAAA==.Asstalor:BAABLgAECn8dAAMLAAgJmxAfZQB0AQALAAgJWxAfZQB0AQAMAAEJjxJsPgA0AAAAAA==.',
Au='Auggy:BAAALgAECgMJAwAAAA==.Auryon:BAACLgAFFH8HAAINAAEJcxjYcgBFAAANAAEJcxjYcgBFAAAuAAQKfzEAAg0ACAkDInsiAFoCAA0ACAkDInsiAFoCAAAA.',
Av='Avadacadabra:BAAALgAECgEJAgAAAA==.Avelna:BAAALgADCgcJBwABLgADCgcJDQAKAAAAAA==.',
Az='Azmodea:BAAALgAECgEJAgAAAA==.',
Ba='Baccstab:BAAALgAECgYJDAAAAA==.Bagains:BAAALgADCgcJEwAAAA==.Bangnyfe:BAAALgAFFAIJAgABLgAFFAMJBgAOAJgZAA==.Baragor:BAAALgAECgQJBAABLgAFFAQJGAAPABUUAA==.Baraka:BAAALgAECgYJCgAAAA==.Baulder:BAABLgAECn8cAAIHAAcJawdeUQAEAQAHAAcJawdeUQAEAQAAAA==.',
Bi='Bigb:BAAALgAFFAEJAQABLgAFFAkJVwAJAGwmAA==.Bigolcrittie:BAAALgADCgIJAgAAAA==.',
Bl='Bleedwoundz:BAAALgAECgYJCgAAAA==.Blerpleberry:BAAALgAECgUJBQAAAA==.Bloodfurry:BAAALgAECgMJAQAAAA==.Bluè:BAABLgAECn8fAAMBAAkJpRl1BADdAQABAAkJpRl1BADdAQACAAUJjBr/TQB5AQAAAA==.',
Bn='Bnakka:BAAALgAFFAEJAQAAAA==.',
Bo='Bobdaunicorn:BAAALgAECgEJAQAAAA==.Boltz:BAAALgAECgMJAwABLgAFFAMJBgAQADgOAA==.Bombalaharis:BAAALgAECgcJDQAAAA==.',
Br='Brekke:BAACLgAFFH8MAAIRAAQJsQ+qSwAWAQARAAQJsQ+qSwAWAQAuAAQKfy8AAhEACQlgGKs1ACoCABEACQlgGKs1ACoCAAAA.Brokenbow:BAACLgAFFH8HAAMSAAQJjQrZIADSAAASAAMJwgfZIADSAAANAAEJ7BK/pABJAAAuAAQKfxsAAxIACQmmE3IfAKABABIACQnNDnIfAKABAA0ABAkIGMV9AO4AAAAA.',
Bu='Bullshaft:BAAALgAECgEJAQAAAA==.Buntz:BAABLgAECn8qAAIRAAkJgCOZDAAAAwARAAkJgCOZDAAAAwAAAA==.Bushmethsin:BAACLgAFFH8cAAITAAgJFCNrBQC7AgATAAgJFCNrBQC7AgAuAAQKfxUAAhMACAlVIg0eAE4CABMACAlVIg0eAE4CAAAA.Buttery:BAABLgAECn8UAAIRAAcJABd2hgBjAQARAAcJABd2hgBjAQAAAA==.',
Bz='Bz:BAAALgADCgcJBwAAAA==.',
Ca='Cabb:BAABLgAECn8ZAAMHAAYJihaARwAoAQAHAAQJGxqARwAoAQAIAAYJsgcjMQC5AAAAAA==.Calcus:BAAALgAECgEJAQAAAA==.',
Ce='Ceedubble:BAAALgAECgkJEAAAAA==.Celestine:BAAALgADCgYJBgABLgAECgkJKAAUAEsOAA==.',
Ch='Charmanderz:BAABLgAECn8mAAMVAAgJIxG2FQBxAQAVAAgJIxG2FQBxAQAWAAEJIhWjOwA/AAABLgAECgkJFAAEAO8LAA==.Cherchlglsia:BAAALgADCgQJCAAAAA==.Chewsdee:BAAALgAECgQJBAAAAA==.Christlovesu:BAAALgAECgIJAgAAAA==.Chuckrules:BAAALgADCgcJDgAAAA==.',
Cl='Clackshi:BAAALgAECgYJCgAAAA==.',
Cr='Critable:BAABLgAECn80AAMXAAkJIxY8GwAqAgAXAAkJIxY8GwAqAgARAAkJuAoXggB2AQAAAA==.',
Cu='Curst:BAAALgAECggJEwAAAA==.',
Da='Dagares:BAAALgADCggJDQAAAA==.Dahnte:BAAALgAECgEJAQAAAA==.',
De='Dechala:BAABLgAECn8oAAIUAAkJSw5BUwCMAQAUAAkJSw5BUwCMAQAAAA==.Deezknights:BAACLgAFFH8VAAMYAAgJzBwLEwBDAgAYAAgJzBwLEwBDAgAFAAEJAACTWQAAAAAuAAQKfycAAhgACQkGJU4JAFIDABgACQkGJU4JAFIDAAAA.Deezpuffs:BAABLgAFFH8KAAMZAAQJOxVSLgAKAQAZAAQJOxVSLgAKAQAVAAEJpQD5MAAiAAABLgAFFAgJFQAYAMwcAA==.Deezrage:BAAALgADCgYJBgAAAA==.Demonharvest:BAAALgAECgkJCQAAAA==.Derailed:BAAALgADCgEJAgAAAA==.Dergon:BAACLgAFFH8HAAILAAMJNw3IfADKAAALAAMJNw3IfADKAAAuAAQKfykAAgsACQloHEUkAE4CAAsACQloHEUkAE4CAAAA.Destiria:BAABLgAECn8kAAMLAAgJuBnfQQDWAQALAAgJuBnfQQDWAQAQAAMJegd5JwBUAAAAAA==.Devistatorxx:BAAALgAECgYJCgAAAA==.',
Do='Doggyystyle:BAAALgAECgEJAQAAAA==.Dogwalker:BAAALgAFFAIJBAABLgAFFAMJBgAQADgOAA==.Domincan:BAAALgADCgEJAQAAAA==.Donaldpump:BAAALgAECgYJBwAAAA==.Doomedturtle:BAAALgAECgYJCAAAAA==.Doublekill:BAAALgAECgUJDAAAAA==.',
Du='Duergan:BAACLgAFFH8YAAIPAAQJFRTlCgD3AAAPAAQJFRTlCgD3AAAuAAQKfzQABA8ACQnwGCMFAGQBAA8ACQnwGCMFAGQBABoACQkICr8GANgAAAMAAQmsHFctAFEAAAAA.',
['Dà']='Dàrkblade:BAABLgAECn8VAAIRAAcJDxhVDACiAQARAAcJDxhVDACiAQAAAA==.',
Ea='Eatz:BAAALgADCgYJBgAAAA==.',
Eh='Ehcks:BAAALgAECgQJBAAAAA==.',
Em='Emotionaldmg:BAAALgADCgYJCwAAAA==.',
Fa='Faelyn:BAAALgADCgEJBAAAAA==.Fansy:BAABLgAFFH8IAAIIAAUJggODDgDDAAAIAAUJggODDgDDAAAAAA==.',
Fe='Felbeard:BAAALgAECgQJBgAAAA==.Felbreaker:BAAALgAECgEJAQAAAA==.Felspark:BAAALgAECgYJDQAAAA==.Felwind:BAABLgAECn8mAAINAAcJ6iNWCQDrAQANAAcJ6iNWCQDrAQAAAA==.Ferus:BAAALgADCgkJCQAAAA==.',
Fi='Fillycheese:BAAALgAECgEJAQAAAA==.',
Fl='Fleurelle:BAAALgAECgkJEQAAAA==.',
Fr='Frollo:BAAALgAECgEJAQAAAA==.Frosstitute:BAAALgAECgMJAwAAAA==.',
Fu='Furfiend:BAACLgAFFH8LAAIYAAQJRBq8VQBGAQAYAAQJRBq8VQBGAQAuAAQKfykAAxgACQndHyUrAFMCABgACQlaHiUrAFMCAAUABQk4G5woABABAAAA.',
Gb='Gb:BAAALgAFFAIJAgABLgAFFAQJDQAbAPIaAA==.',
Gi='Giantdog:BAAALgAECgUJBQAAAA==.Gilraen:BAACLgAFFH8RAAMHAAQJmA5lKAAUAQAHAAQJ8wxlKAAUAQAGAAEJXQ/bRAA9AAAuAAQKf0gAAwcACQmnHsQBAKMCAAcACQnuHMQBAKMCAAYACQn5FgQOAAkCAAAA.Gingerjen:BAABLgAECn8UAAMTAAgJ9wefZQADAQATAAgJ9wefZQADAQAcAAgJcgMvUgDFAAAAAA==.',
Go='Gorgrand:BAAALgAECgcJBwAAAA==.Gothbiotch:BAAALgAECgMJAwAAAA==.',
Gr='Greaseduppig:BAAALgAECgEJAQAAAA==.Greggnog:BAAALgAECgkJDAAAAA==.Greggy:BAAALgAECgUJCQABLgAECgkJDAAKAAAAAA==.Grenache:BAAALgAECgMJBAAAAA==.',
Ha='Hagarirn:BAAALgAECgEJAQAAAA==.Hairypotter:BAAALgADCgUJBQABLgAECgYJCgAKAAAAAA==.Halfworld:BAAALgADCgYJBgAAAA==.Happydaze:BAACLgAFFH8VAAMFAAQJJQ5fEwDJAAAFAAQJJQ5fEwDJAAAYAAEJcwXNrQAyAAAuAAQKfysAAwUACQlUG+IPAA0CAAUACQkGG+IPAA0CABgAAwloEowsAXMAAAAA.Harshdruid:BAAALgAECgEJAQABLgAFFAMJCwAEAL8SAA==.Haxthedk:BAAALgAECgEJAQAAAA==.Haxthedruid:BAAALgAECgEJAQAAAA==.Haxthemonk:BAAALgAECgEJAQAAAA==.',
He='Hemotoxin:BAAALgAECgMJAwAAAA==.Hendel:BAAALgAECgQJBgAAAA==.Herkaferk:BAABLgAECn8XAAIBAAYJiBMqRQAfAQABAAYJiBMqRQAfAQAAAA==.',
Ho='Hojx:BAAALgAECgEJAQAAAA==.',
Hr='Hrolf:BAABLgAECn9DAAMdAAkJ6hJVBACNAQAdAAkJ6hJVBACNAQATAAEJyRGyzwA1AAABLgAFFAQJGAAPABUUAA==.',
Il='Illiannà:BAABLgAECn8UAAMEAAkJ7wujJQCjAQAEAAkJ7wujJQCjAQAbAAEJwRUsfgBBAAAAAA==.Illidont:BAABLgAECn8WAAIeAAkJWRAYHACcAQAeAAkJWRAYHACcAQAAAA==.Illijr:BAABLgAECn8dAAIeAAkJexSZFQDgAQAeAAkJexSZFQDgAQAAAA==.',
It='Ithil:BAAALgADCgkJDwAAAA==.',
Ja='Jaemison:BAAALgADCgQJAwABLgAECgkJcwANAG0mAA==.',
Ji='Jicks:BAABLgAECn8jAAIEAAkJ6QtoOgAmAQAEAAkJ6QtoOgAmAQAAAA==.',
Jk='Jkass:BAACLgAFFH8QAAIOAAQJcAwmFwDHAAAOAAQJcAwmFwDHAAAuAAQKfxsAAg4ACAn+FgccALYBAA4ACAn+FgccALYBAAAA.',
Ju='Judgementdày:BAAALgAECggJCgAAAA==.',
['Jà']='Jàk:BAAALgAECgIJAgAAAA==.',
Ka='Kaldarr:BAAALgAECgEJAQAAAA==.Kamaeria:BAACLgAFFH8WAAIbAAUJxAQtGQCSAAAbAAUJxAQtGQCSAAAuAAQKfzkAAhsACQn0FDAWABkCABsACQn0FDAWABkCAAAA.Kaíros:BAAALgADCgMJAwAAAA==.',
Kh='Khaotica:BAAALgADCgkJCQAAAA==.',
Ki='Kiandara:BAACLgAFFH8dAAMHAAcJARkFHgA5AQAHAAcJARkFHgA5AQAGAAQJwRJAGwAPAQAuAAQKfyQAAwcACQmQHPIMAO4CAAcACQmQHPIMAO4CAAgABQkcG94dAFcBAAAA.Kikkoman:BAABLgAFFH8GAAIOAAMJmBltJAAAAQAOAAMJmBltJAAAAQAAAA==.Kilmas:BAAALgAECgIJAgAAAA==.Kinetic:BAAALgAECgEJAQAAAA==.Kirant:BAAALgADCggJDQAAAA==.Kirara:BAAALgADCgYJBgAAAA==.',
Ko='Kooz:BAAALgADCgUJBQAAAA==.Kooze:BAAALgADCgUJCAAAAA==.Koozo:BAAALgADCgMJAwAAAA==.Kozar:BAAALgAECgcJBwAAAA==.',
Kt='Kt:BAABLgAECn8aAAIJAAcJNhNlmQBGAQAJAAcJNhNlmQBGAQAAAA==.',
Ku='Kush:BAAALgADCgEJAQABLgAECgkJKgARAIAjAA==.',
Ky='Kynrath:BAAALgAECgkJDAAAAA==.',
La='Laurie:BAAALgADCgMJBgAAAA==.Lava:BAAALgADCgUJBQABLgAECgkJFQAeAOcdAA==.Lavablast:BAAALgADCgYJCwAAAA==.',
Le='Lelanie:BAAALgADCggJDgAAAA==.',
Li='Lichnfamous:BAACLgAFFH8JAAIYAAQJ/AtTdwAUAQAYAAQJ/AtTdwAUAQAuAAQKfykAAxgACAnRFa9NANkBABgACAnRFa9NANkBAB8ABAnqDOwfAM0AAAAA.Lightfrost:BAAALgAECgMJAwABLgAECgQJBgAKAAAAAA==.Lightning:BAAALgAECgUJCAAAAA==.Likkan:BAAALgAECgEJAQAAAA==.Lilithdawn:BAABLgAECn8jAAIgAAkJvhvsEABdAgAgAAkJvhvsEABdAgAAAA==.',
Lo='Lockwar:BAACLgAFFH8GAAIQAAMJOA4NEQCIAAAQAAMJOA4NEQCIAAAuAAQKfx8ABBAACQmbF/YKAK8BABAACQmbF/YKAK8BAAsABAkUB97lAJIAAAwAAQlPAOlJAAUAAAAA.Louvre:BAABLgAECn8uAAIOAAkJtxx2CQCOAgAOAAkJtxx2CQCOAgAAAA==.Lowehigh:BAAALgAECgIJAgAAAA==.',
Lu='Lukarian:BAABLgAFFH8GAAIRAAMJiw4hcgDOAAARAAMJiw4hcgDOAAAAAA==.Luminaughty:BAAALgAECgEJAgAAAA==.',
Ma='Macemen:BAAALgAECgEJAQAAAA==.Magènta:BAAALgAECgMJAwAAAA==.Makthra:BAAALgAECgUJEQAAAA==.Marek:BAAALgADCgUJCAAAAA==.Marionette:BAAALgAECgMJAwAAAA==.Mashka:BAAALgAECgMJAwAAAA==.Mawseeker:BAAALgADCgEJAQAAAA==.',
Me='Megabettegaa:BAACLgAFFH8aAAMYAAQJQBerOgDuAAAYAAQJQBerOgDuAAAfAAEJqQSpHwA5AAAuAAQKf4cAAhgACQkGG6gsAE0CABgACQkGG6gsAE0CAAAA.Melbukai:BAAALgAECgUJCAAAAA==.Melbuki:BAAALgAECgUJDAAAAA==.Mennathil:BAAALgADCgEJAQAAAA==.Meric:BAAALgAECgEJAwAAAA==.',
Mi='Microbrew:BAAALgAECgcJDAABLgAFFAMJCgAdAN4KAA==.Midnight:BAAALgAECgcJCQABLgAECgkJCgAKAAAAAA==.Milo:BAAALgAFFAEJAQAAAA==.Miniangel:BAACLgAFFH8RAAMgAAUJjxSaDwBZAQAgAAUJjxSaDwBZAQAbAAIJfQFANwBXAAAuAAQKfx4AAyAACQl8FVYVACoCACAACQl8FVYVACoCABsACAk+EPAoAJMBAAAA.Mixednuts:BAAALgAECgIJAgAAAA==.',
Mo='Molasses:BAACLgAFFH8jAAIJAAUJahQaLQAZAQAJAAUJahQaLQAZAQAuAAQKf0AAAgkACQnTHqMXAMsCAAkACQnTHqMXAMsCAAAA.Moof:BAAALgAECgEJAQAAAA==.',
['Má']='Márionette:BAAALgAECgEJAQAAAA==.',
['Mú']='Músic:BAAALgAECgIJAwAAAA==.',
Na='Najitar:BAAALgAECgQJBQAAAA==.Nazaibrew:BAAALgAECggJDAABLgAECgkJOwAEAE4fAA==.Nazera:BAAALgAECgEJAQAAAA==.',
Ne='Necromalus:BAAALgAECgEJAgAAAA==.Neerx:BAAALgADCgUJBQAAAA==.',
Ni='Nimos:BAAALgAECgEJAQAAAA==.',
Nu='Nubkselk:BAABLgAECn80AAIUAAkJWh4JFgCTAgAUAAkJWh4JFgCTAgAAAA==.Nurishment:BAACLgAFFH8fAAITAAkJyRR+DAArAgATAAkJyRR+DAArAgAuAAQKfyUAAhMACQn7HWwSAKICABMACQn7HWwSAKICAAAA.',
Ny='Nyrr:BAAALgADCgEJAgAAAA==.',
Og='Ogmurka:BAAALgAECgEJAQAAAA==.',
On='Oni:BAAALgADCgUJBQAAAA==.Onitachi:BAABLgAECn8rAAMBAAgJzxH3RgAYAQABAAgJzxH3RgAYAQAhAAQJcAmcLgCDAAAAAA==.',
Op='Optistriker:BAABLgAECn9LAAITAAkJaxknFQChAgATAAkJaxknFQChAgAAAA==.',
Oy='Oythsar:BAAALgADCgQJBAAAAA==.',
Pa='Painfree:BAAALgADCgQJBAAAAA==.Papabear:BAAALgAECgEJAQAAAA==.Parasite:BAAALgAECgEJBAAAAA==.',
Pe='Pemburumalam:BAAALgADCgEJAQAAAA==.',
Pi='Pig:BAABLgAECn8cAAIHAAgJKhjaKwAGAgAHAAgJKhjaKwAGAgABLgAECgkJKgARAIAjAA==.Pinks:BAAALgADCgkJCQAAAA==.Pizlex:BAAALgAECgcJCQAAAA==.',
Po='Poplockndrop:BAAALgAECgUJBgAAAA==.Portion:BAABLgAECn8uAAIJAAgJWhxQVwDXAQAJAAgJWhxQVwDXAQAAAA==.Portlybob:BAAALgADCgEJAQAAAA==.Potatoe:BAAALgAECgQJBgAAAA==.',
Pr='Pretentious:BAACLgAFFH8GAAIRAAQJrQzUUAANAQARAAQJrQzUUAANAQAuAAQKfx4AAhEACAmiHysmAI4CABEACAmiHysmAI4CAAAA.Prettyfun:BAAALgADCgUJBQAAAA==.Prettysavage:BAAALgAECgIJAgAAAA==.Primo:BAAALgADCgYJEQAAAA==.',
['Pè']='Pèrsephônè:BAAALgADCgIJAgAAAA==.',
Ra='Radicalism:BAAALgAECgQJBQAAAA==.Raechan:BAAALgAECgEJAQAAAA==.Ranigard:BAAALgAECgUJCAAAAA==.Rantioc:BAAALgAECgYJBgAAAA==.Raugan:BAAALgAECgEJAwAAAA==.',
Re='Reparations:BAABLgAECn8gAAMbAAgJlAgYEQC7AAAbAAgJlAgYEQC7AAAEAAUJugIwYgB0AAAAAA==.Repentofsin:BAAALgAECgQJBAAAAA==.Rexbriefs:BAABLgAECn8+AAIYAAcJ4hNxEgAlAQAYAAcJ4hNxEgAlAQAAAA==.',
Ri='Rice:BAAALgAFFAEJAQABLgAFFAMJBgAQADgOAA==.Riptong:BAAALgADCgEJAQAAAA==.',
Ro='Rockypalboa:BAACLgAFFH8JAAMRAAQJSBAXdQDKAAARAAMJBA0XdQDKAAAXAAMJvgwhPwBlAAAuAAQKfyYAAxcACQk3GNtAAHUBABcACQk3GNtAAHUBABEABwkxF3yGAGMBAAAA.Rovinj:BAAALgAECgkJBwAAAA==.',
Ru='Rukhmear:BAAALgAECgEJAQAAAA==.Rumi:BAABLgAECn8lAAIUAAkJLBi8PwDKAQAUAAkJLBi8PwDKAQAAAA==.',
Ry='Rydle:BAABLgAFFH8JAAMNAAQJsQ59XwDmAAANAAQJsQ59XwDmAAAiAAEJYQc0IgAzAAAAAA==.',
Sa='Samedhi:BAAALgAECgQJBQAAAA==.Sanlesh:BAAALgADCgUJBgAAAA==.Sapodillà:BAAALgAECggJDQAAAA==.Sarijevo:BAAALgAECgkJBQAAAA==.Saurax:BAAALgAECgIJAwAAAA==.',
Sc='Scatz:BAAALgADCgIJAgAAAA==.Scott:BAAALgAECgcJCwAAAA==.Scylla:BAAALgAECgYJDwAAAA==.',
Se='Seraxx:BAAALgADCgEJAQAAAA==.Sevrin:BAACLgAFFH8jAAIOAAgJshzRAwBrAgAOAAgJshzRAwBrAgAuAAQKfy8AAg4ACQlrIx8FAOQCAA4ACQlrIx8FAOQCAAAA.Sevro:BAAALgAECgEJAQAAAA==.',
Sh='Shadowfuryy:BAAALgAECgUJBQAAAA==.Shalati:BAAALgADCgYJBgABLgAECgkJcwANAG0mAA==.Sharts:BAAALgADCgYJCQAAAA==.Shestrouble:BAACLgAFFH8GAAIJAAIJyhvClgChAAAJAAIJyhvClgChAAAuAAQKfyUAAgkACQn1IikKACgDAAkACQn1IikKACgDAAAA.Shiift:BAAALgAECgMJAwABLgAFFAMJDgAOAPEiAA==.Shirerat:BAAALgADCgMJBAAAAA==.Shtzson:BAABLgAECn8iAAIaAAkJhxtYAQBbAgAaAAkJhxtYAQBbAgAAAA==.Shyjinx:BAAALgAECgYJBgAAAA==.Shíft:BAAALgAECgUJBQABLgAFFAMJDgAOAPEiAA==.Shííft:BAAALgAECgUJBQABLgAFFAMJDgAOAPEiAA==.Shîft:BAACLgAFFH8OAAIOAAMJ8SJgHQA0AQAOAAMJ8SJgHQA0AQAuAAQKfzQAAw4ACQnvI6kGAMMCAA4ACAnPI6kGAMMCACMAAwl0H40SAP0AAAAA.Shïìft:BAAALgAFFAEJAQABLgAFFAMJDgAOAPEiAA==.',
Si='Siiwwy:BAAALgAECgMJAwAAAA==.',
Sl='Slice:BAABLgAFFH8JAAMkAAMJJAoABwCGAAAkAAMJJAoABwCGAAAeAAIJ6wJjJQAoAAAAAA==.',
So='Sok:BAAALgAECgEJAwAAAA==.Soktear:BAAALgAECgEJAgAAAA==.Soladin:BAAALgAECgQJBQABLgAFFAMJCgAdAN4KAA==.Soladis:BAAALgAECgcJDAABLgAECgkJIgAaAIcbAA==.Solicide:BAACLgAFFH8KAAQdAAMJ3gqZGQBnAAAdAAMJGQiZGQBnAAATAAIJRwQXLABFAAAlAAEJBg9cHQBCAAAuAAQKfzcABR0ACQlxG2wPAPABAB0ACAniGGwPAPABACUABwnxG9oMAOgBABMAAQlEExvIADoAABwAAQnaDgGPADEAAAAA.Solthicc:BAAALgAECggJDQAAAA==.Sonarra:BAAALgAECgYJBgAAAA==.',
Sp='Sparkle:BAACLgAFFH8nAAIZAAgJoxRJFADRAQAZAAgJoxRJFADRAQAuAAQKf4wAAxkACQkhJt4AAIEDABkACQkhJt4AAIEDABYAAwlKI1sCACkBAAAA.Splatacular:BAAALgADCgEJAQAAAA==.',
St='Stolenhearth:BAABLgAECn8tAAIHAAYJ3w8IDwDfAAAHAAYJ3w8IDwDfAAAAAA==.',
Sv='Svets:BAABLgAECn87AAMEAAkJTh/jCADlAgAEAAkJTh/jCADlAgAgAAEJ3AnKhQArAAAAAA==.',
Sw='Swavey:BAAALgADCgQJBAAAAA==.',
Sy='Sylmeria:BAAALgAECgUJBwAAAA==.Sylphrenna:BAAALgAECgcJCQAAAA==.Syrana:BAAALgADCgEJAQAAAA==.',
Te='Teeanna:BAAALgAECgYJDAAAAA==.Temaile:BAAALgADCgEJBAAAAA==.Tenin:BAAALgADCgEJAQAAAA==.',
Th='Thinmint:BAAALgADCgEJAQAAAA==.Thoranter:BAAALgADCgYJCQAAAA==.',
Ti='Tinnman:BAAALgADCgYJBgAAAA==.',
To='Toughguytony:BAAALgADCgUJBgAAAA==.',
Tr='Trebekk:BAAALgADCgEJAQAAAA==.Treydk:BAACLgAFFH8NAAIYAAQJWh0vTwBUAQAYAAQJWh0vTwBUAQAuAAQKfxwAAxgACQm/HdMZAKwCABgACQl2HdMZAKwCAB8ABQkYHGIZAAgBAAAA.Trreyy:BAABLgAECn8fAAIRAAgJqh5YKACEAgARAAgJqh5YKACEAgAAAA==.',
Ts='Tsimfuqis:BAABLgAFFH8LAAIOAAQJMhJAHgAvAQAOAAQJMhJAHgAvAQAAAA==.',
Tw='Twighumper:BAAALgAECgUJBwABLgAECgkJIgAaAIcbAA==.Twizzly:BAAALgAFFAIJAgAAAA==.Twizzy:BAACLgAFFH8VAAINAAQJAQblPwCwAAANAAQJAQblPwCwAAAuAAQKf0IAAg0ACQnyFJwoADwCAA0ACQnyFJwoADwCAAEuAAUUBQkWABsAxAQA.',
Ty='Tyranhikar:BAAALgADCgEJAQAAAA==.',
Tz='Tzechan:BAACLgAFFH8GAAIXAAMJ8RpQJgDvAAAXAAMJ8RpQJgDvAAAuAAQKfx8AAxcACQkiG/EdABMCABcACQkiG/EdABMCABEAAgmcEp1BAWoAAAAA.',
Ug='Uggalee:BAAALgAFFAIJAwAAAA==.',
Va='Valtirya:BAAALgAECgQJBgAAAA==.Vampirellaa:BAAALgAECgEJAgAAAA==.Vanaria:BAAALgAECgQJBAAAAA==.Vayzen:BAABLgAECn8YAAIZAAcJDB4uEwBNAgAZAAcJDB4uEwBNAgAAAA==.',
Vh='Vhaelak:BAAALgAECgUJCwAAAA==.',
Vi='Virexus:BAAALgADCgIJAgAAAA==.',
Vo='Voidfree:BAABLgAECn8tAAIUAAkJfwwVGADGAAAUAAkJfwwVGADGAAAAAA==.',
Vy='Vynarc:BAABLgAECn8qAAIRAAgJihHPZQC1AQARAAgJihHPZQC1AQAAAA==.',
Wa='Warcrimes:BAAALgAECgEJAQAAAA==.Watervendor:BAABLgAECn8vAAIJAAkJgBvYMABWAgAJAAkJgBvYMABWAgAAAA==.',
We='Wearegroot:BAAALgAECgEJAQAAAA==.Webedeadiy:BAAALgADCgEJAQAAAA==.',
Wh='Whiteknight:BAAALgAECgYJBgAAAA==.',
Wi='Wiggimbottom:BAAALgAECgYJEgAAAA==.Wihtè:BAAALgAECgMJAwAAAA==.Willscarlet:BAAALgADCgQJBAAAAA==.',
Wo='Wolffoxfangs:BAABLgAECn8VAAINAAcJ/BVvaAByAQANAAcJ/BVvaAByAQAAAA==.',
Wx='Wxyzptlk:BAAALgADCgYJBgABLgAECgkJIwAgAL4bAA==.',
['Wá']='Wárpaiint:BAABLgAECn8uAAMNAAcJfhM4EwBOAQANAAQJlho4EwBOAQAiAAcJoQujFwD2AAABLgAECgcJJgATAGcbAA==.',
Xa='Xalatoes:BAAALgAECgUJBQAAAA==.',
Xe='Xeados:BAAALgAECgIJAgAAAA==.Xenos:BAAALgAECgEJAgAAAA==.',
Yi='Yin:BAAALgADCgcJDQAAAA==.',
['Yè']='Yèlloow:BAAALgAECgMJBQAAAA==.',
Za='Zaquel:BAABLgAECn8UAAMNAAgJ/xpCUgCsAQANAAgJOhdCUgCsAQASAAcJQhJvIgCKAQABLgAFFAQJEwARAGwPAA==.Zarcissa:BAABLgAECn8VAAIRAAcJnRl0DgCDAQARAAcJnRl0DgCDAQAAAA==.Zaritus:BAAALgADCgEJAQAAAA==.Zavira:BAAALgADCgcJBwAAAA==.',
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
