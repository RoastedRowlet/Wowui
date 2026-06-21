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

local lookup = {'Shaman-Elemental','Shaman-Restoration','Monk-Mistweaver','DeathKnight-Blood','Warrior-Arms','Warrior-Fury','Warrior-Protection','Mage-Frost','Unknown-Unknown','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Rogue-Subtlety','Paladin-Retribution','Hunter-Survival','Druid-Restoration','DemonHunter-Devourer','Evoker-Preservation','Evoker-Devastation','Priest-Discipline','Paladin-Holy','DeathKnight-Unholy','Evoker-Augmentation','Warlock-Affliction','Monk-Windwalker','Monk-Brewmaster','Druid-Balance','Druid-Guardian','Priest-Shadow','DemonHunter-Havoc','DeathKnight-Frost','Priest-Holy','Shaman-Enhancement','Hunter-Marksmanship','Rogue-Assassination','Druid-Feral',}
local provider = {region='US',realm='Gorgonnash',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aakira:BAABLgAECn8VAAMBAAkJzQgsPgA8AQABAAkJzQgsPgA8AQACAAEJuAMA6wAkAAAAAA==.Aangie:BAABLgAECn8YAAIDAAcJngZMPAD0AAADAAcJngZMPAD0AAAAAA==.Aanjie:BAABLgAECn8aAAIDAAYJQwkYbADSAAADAAYJQwkYbADSAAAAAA==.Aathea:BAAALgAECgYJBgAAAA==.',
Ab='Abban:BAAALgAECgMJAwAAAA==.Abom:BAAALgAECgIJAgAAAA==.Abrastal:BAAALgAECgQJCAAAAA==.',
Ad='Adrestia:BAAALgAECgQJBgAAAA==.',
Ak='Akbar:BAAALgAECgUJBQAAAA==.',
Al='Alline:BAABLgAECn8dAAIEAAYJcBLRJgAdAQAEAAYJcBLRJgAdAQAAAA==.Alswaron:BAAALgAECgUJEwAAAA==.',
Am='Amador:BAACLgAFFH8VAAQFAAQJ8R7iEwA/AQAFAAQJnB3iEwA/AQAGAAMJoRQTQQCdAAAHAAEJnB1jKgBKAAAuAAQKfyoABAUACQl5IucGAIwCAAUACAl5IucGAIwCAAYABAndGulpAA4BAAcAAgmuFo06AHcAAAAA.Amorlan:BAAALgAECgEJAQAAAA==.Amyra:BAAALgAECgEJAQAAAA==.',
An='Annox:BAAALgAECgQJBwAAAA==.',
Ap='Apsallar:BAABLgAECn8dAAIIAAkJzBx9HwChAgAIAAkJzBx9HwChAgAAAA==.',
Ar='Arcanedream:BAAALgAECgUJBQABLgAECgcJCQAJAAAAAA==.Arcanism:BAABLgAECn8cAAIIAAcJshOjngCZAQAIAAcJshOjngCZAQAAAA==.Arlas:BAAALgAECgMJBAAAAA==.Arthone:BAAALgADCgUJBQAAAA==.',
As='Aserai:BAAALgADCgMJAwAAAA==.Asstalor:BAABLgAECn8dAAMKAAgJmxAdZQB0AQAKAAgJWxAdZQB0AQALAAEJjxJqPgA0AAAAAA==.',
Au='Auggy:BAAALgAECgMJAwAAAA==.Auryon:BAACLgAFFH8FAAIMAAEJcxgCnwBQAAAMAAEJcxgCnwBQAAAuAAQKfzAAAgwACAnDIXsiAFoCAAwACAnDIXsiAFoCAAAA.',
Av='Avelna:BAAALgADCgcJBwABLgADCgcJDQAJAAAAAA==.',
Az='Azmodea:BAAALgADCgEJAgAAAA==.',
Ba='Baccstab:BAAALgAECgYJDAAAAA==.Bagains:BAAALgADCgcJEwAAAA==.Bangnyfe:BAAALgAFFAIJAgABLgAFFAMJBQANAJgZAA==.Baraka:BAAALgAECgYJCgAAAA==.Baulder:BAABLgAECn8cAAIGAAcJawdZUQAEAQAGAAcJawdZUQAEAQAAAA==.',
Bi='Bigb:BAAALgAFFAEJAQABLgAFFAkJNwAIAMwkAA==.Bigolcrittie:BAAALgADCgIJAgAAAA==.',
Bl='Blerpleberry:BAAALgAECgUJBQAAAA==.Bloodfurry:BAAALgAECgMJAQAAAA==.Bluè:BAABLgAECn8ZAAMBAAgJ+BTRMAB8AQABAAgJ+BTRMAB8AQACAAUJjBr6TQB5AQAAAA==.',
Bn='Bnakka:BAAALgAFFAEJAQAAAA==.',
Bo='Bobdaunicorn:BAAALgAECgEJAQAAAA==.Boltz:BAAALgAECgMJAwAAAA==.Bombalaharis:BAAALgAECgcJDQAAAA==.',
Br='Brekke:BAACLgAFFH8MAAIOAAQJsQ+1SwAWAQAOAAQJsQ+1SwAWAQAuAAQKfy8AAg4ACQlgGK41ACoCAA4ACQlgGK41ACoCAAAA.Brokenbow:BAACLgAFFH8HAAMPAAQJjQrYIADSAAAPAAMJwgfYIADSAAAMAAEJ7BK+pABJAAAuAAQKfxsAAw8ACQmmE3MfAKABAA8ACQnNDnMfAKABAAwABAkIGMV9AO4AAAAA.',
Bu='Bullshaft:BAAALgAECgEJAQAAAA==.Buntz:BAABLgAECn8qAAIOAAkJgCOXDAAAAwAOAAkJgCOXDAAAAwAAAA==.Bushmethsin:BAACLgAFFH8cAAIQAAgJFCNtBQC7AgAQAAgJFCNtBQC7AgAuAAQKfxUAAhAACAlVIg0eAE4CABAACAlVIg0eAE4CAAAA.Buttery:BAAALgAFFAEJAQAAAA==.',
Bz='Bz:BAAALgADCgcJBwAAAA==.',
Ca='Cabb:BAABLgAECn8WAAMGAAYJihZ+RwAoAQAGAAQJGxp+RwAoAQAHAAYJsgcjMQC5AAAAAA==.',
Ce='Ceedubble:BAAALgAECgkJEAAAAA==.Celestine:BAAALgADCgYJBgABLgAECgkJKAARAEsOAA==.',
Ch='Charmanderz:BAABLgAECn8mAAMSAAgJIxG2FQBxAQASAAgJIxG2FQBxAQATAAEJIhWjOwA/AAABLgAECgkJFAAUAO8LAA==.Cherchlglsia:BAAALgADCgQJCAAAAA==.Chewsdee:BAAALgAECgQJBAAAAA==.Christlovesu:BAAALgAECgIJAgAAAA==.Chuckrules:BAAALgADCgcJDgAAAA==.',
Cl='Clackshi:BAAALgAECgYJCgAAAA==.',
Cr='Critable:BAABLgAECn8yAAMVAAkJIxY+GwAqAgAVAAkJIxY+GwAqAgAOAAgJNggXggB2AQAAAA==.',
Cu='Curst:BAAALgAECggJEwAAAA==.',
Da='Dagares:BAAALgADCggJDQAAAA==.Dahnte:BAAALgAECgEJAQAAAA==.',
De='Dechala:BAABLgAECn8oAAIRAAkJSw5EUwCMAQARAAkJSw5EUwCMAQAAAA==.Deezknights:BAACLgAFFH8UAAMWAAgJzBwWEwBDAgAWAAgJzBwWEwBDAgAEAAEJAACUWQAAAAAuAAQKfycAAhYACQkGJU4JAFIDABYACQkGJU4JAFIDAAAA.Deezpuffs:BAABLgAFFH8KAAMXAAQJOxVSLgAKAQAXAAQJOxVSLgAKAQASAAEJpQD6MAAiAAABLgAFFAgJFAAWAMwcAA==.Deezrage:BAAALgADCgYJBgAAAA==.Derailed:BAAALgADCgEJAgAAAA==.Dergon:BAACLgAFFH8FAAIKAAMJNw3cfADKAAAKAAMJNw3cfADKAAAuAAQKfykAAgoACQloHEMkAE4CAAoACQloHEMkAE4CAAAA.Destiria:BAABLgAECn8kAAMKAAgJuBneQQDWAQAKAAgJuBneQQDWAQAYAAMJegd5JwBUAAAAAA==.Devistatorxx:BAAALgAECgYJCgAAAA==.',
Do='Doggyystyle:BAAALgAECgEJAQAAAA==.Donaldpump:BAAALgAECgYJBwAAAA==.Doomedturtle:BAAALgAECgMJBAAAAA==.Doublekill:BAAALgAECgUJDAAAAA==.',
Du='Duergan:BAACLgAFFH8SAAIZAAQJFRTTFQAQAQAZAAQJFRTTFQAQAQAuAAQKfykABBkACQkDEvkrAGABABkACAkTFPkrAGABABoACAnEBaY4ABkBAAMAAQlFAwRyACEAAAAA.',
['Dà']='Dàrkblade:BAAALgAECgQJBwAAAA==.',
Ea='Eatz:BAAALgADCgYJBgAAAA==.',
Eh='Ehcks:BAAALgAECgQJBAAAAA==.',
Em='Emotionaldmg:BAAALgADCgYJCwAAAA==.',
Fa='Faelyn:BAAALgADCgEJBAAAAA==.Fansy:BAAALgAFFAIJAgAAAA==.',
Fe='Felwind:BAABLgAECn8gAAIMAAcJbyMzAQDrAQAMAAcJbyMzAQDrAQAAAA==.Ferus:BAAALgADCgkJCQAAAA==.',
Fi='Fillycheese:BAAALgAECgEJAQAAAA==.',
Fl='Fleurelle:BAAALgAECgMJAwAAAA==.',
Fr='Frollo:BAAALgAECgEJAQAAAA==.Frosstitute:BAAALgAECgMJAwAAAA==.',
Fu='Furfiend:BAACLgAFFH8IAAIWAAQJYxe+VQBGAQAWAAQJYxe+VQBGAQAuAAQKfykAAxYACQndHyIrAFQCABYACQlaHiIrAFQCAAQABQk4G5koABABAAAA.',
Gi='Giantdog:BAAALgAECgUJBQAAAA==.Gilraen:BAACLgAFFH8MAAMGAAQJ+g1qKAAUAQAGAAQJVgxqKAAUAQAFAAEJXQ/cRAA9AAAuAAQKfz8AAwUACQk3GQUOAAkCAAUACQn5FgUOAAkCAAYACQmSE+QnALwBAAAA.Gingerjen:BAABLgAECn8UAAMQAAgJ9weiZQADAQAQAAgJ9weiZQADAQAbAAgJcgMnUgDFAAAAAA==.',
Go='Gorgrand:BAAALgAECgcJBwAAAA==.Gothbiotch:BAAALgAECgMJAwAAAA==.',
Gr='Greggnog:BAAALgAECgkJDAAAAA==.Greggy:BAAALgAECgUJCQABLgAECgkJDAAJAAAAAA==.Grenache:BAAALgAECgMJBAAAAA==.',
Ha='Hairypotter:BAAALgADCgUJBQAAAA==.Halfworld:BAAALgADCgYJBgAAAA==.Happydaze:BAACLgAFFH8GAAIEAAMJKBFyKgClAAAEAAMJKBFyKgClAAAuAAQKfysAAwQACQlUG+MPAA0CAAQACQkGG+MPAA0CABYAAwloEoEsAXMAAAAA.Harshdruid:BAAALgAECgEJAQABLgAFFAMJCgAUAL8SAA==.Haxthedk:BAAALgAECgEJAQAAAA==.Haxthedruid:BAAALgAECgEJAQAAAA==.Haxthemonk:BAAALgAECgEJAQAAAA==.',
He='Hemotoxin:BAAALgAECgMJAwAAAA==.Hendel:BAAALgAECgQJBgAAAA==.Herkaferk:BAABLgAECn8XAAIBAAYJiBMoRQAfAQABAAYJiBMoRQAfAQAAAA==.',
Ho='Hojx:BAAALgAECgEJAQAAAA==.',
Hr='Hrolf:BAABLgAECn8yAAMcAAgJHRFHHgBbAQAcAAgJHRFHHgBbAQAQAAEJyRGzzwA1AAABLgAFFAQJEgAZABUUAA==.',
Il='Illiannà:BAABLgAECn8UAAMUAAkJ7wugJQCjAQAUAAkJ7wugJQCjAQAdAAEJwRUkfgBBAAAAAA==.Illidont:BAABLgAECn8WAAIeAAkJWRAZHACcAQAeAAkJWRAZHACcAQAAAA==.Illijr:BAABLgAECn8cAAIeAAkJ1BOaFQDgAQAeAAkJ1BOaFQDgAQAAAA==.',
It='Ithil:BAAALgADCgkJDwAAAA==.',
Ja='Jaemison:BAAALgADCgQJAwAAAA==.',
Ji='Jicks:BAABLgAECn8hAAIUAAcJxAxpOgAmAQAUAAcJxAxpOgAmAQAAAA==.',
Jk='Jkass:BAACLgAFFH8IAAINAAMJgQzMBQCPAAANAAMJgQzMBQCPAAAuAAQKfxsAAg0ACAn+FgUcALYBAA0ACAn+FgUcALYBAAAA.',
Ju='Judgementdày:BAAALgAECggJCgAAAA==.',
['Jà']='Jàk:BAAALgAECgIJAgAAAA==.',
Ka='Kaldarr:BAAALgAECgEJAQAAAA==.Kamaeria:BAACLgAFFH8MAAIdAAQJEgOYKAC6AAAdAAQJEgOYKAC6AAAuAAQKfzkAAh0ACQn0FDAWABkCAB0ACQn0FDAWABkCAAEuAAUUBAkOAAwApwUA.Kaíros:BAAALgADCgMJAwAAAA==.',
Kh='Khaotica:BAAALgADCgkJCQAAAA==.',
Ki='Kiandara:BAACLgAFFH8aAAMGAAUJrhkQHgA5AQAGAAUJrhkQHgA5AQAFAAQJwRJGGwAPAQAuAAQKfyQAAwYACQmQHPIMAO4CAAYACQmQHPIMAO4CAAcABQkcG94dAFcBAAAA.Kikkoman:BAABLgAFFH8FAAINAAMJmBlxJAAAAQANAAMJmBlxJAAAAQAAAA==.Kilmas:BAAALgAECgIJAgAAAA==.Kirant:BAAALgADCggJDQAAAA==.Kirara:BAAALgADCgYJBgAAAA==.',
Ko='Kooz:BAAALgADCgUJBQAAAA==.Kooze:BAAALgADCgUJCAAAAA==.Koozo:BAAALgADCgMJAwAAAA==.',
Kt='Kt:BAABLgAECn8aAAIIAAcJNhNkmQBGAQAIAAcJNhNkmQBGAQAAAA==.',
Ku='Kush:BAAALgADCgEJAQABLgAECgkJKgAOAIAjAA==.',
Ky='Kynrath:BAAALgAECgcJCgAAAA==.',
La='Laurie:BAAALgADCgMJBgAAAA==.Lava:BAAALgADCgUJBQABLgAECggJDwAJAAAAAA==.Lavablast:BAAALgADCgYJCwAAAA==.',
Le='Lelanie:BAAALgADCggJDgAAAA==.',
Li='Lichnfamous:BAACLgAFFH8JAAIWAAQJ/AtZdwAUAQAWAAQJ/AtZdwAUAQAuAAQKfykAAxYACAnRFapNANkBABYACAnRFapNANkBAB8ABAnqDOsfAM0AAAAA.Lightfrost:BAAALgAECgIJAgAAAA==.Lightning:BAAALgAECgUJCAAAAA==.Likkan:BAAALgAECgEJAQAAAA==.Lilithdawn:BAABLgAECn8iAAIgAAkJvhvsEABdAgAgAAkJvhvsEABdAgAAAA==.',
Lo='Lockwar:BAABLgAECn8dAAQYAAgJ4Rf1CgCvAQAYAAgJ4Rf1CgCvAQAKAAQJFAfc5QCSAAALAAEJTwDqSQAFAAAAAA==.Louvre:BAABLgAECn8uAAINAAkJtxx0CQCOAgANAAkJtxx0CQCOAgAAAA==.',
Lu='Lukarian:BAABLgAFFH8GAAIOAAMJiw4scgDOAAAOAAMJiw4scgDOAAAAAA==.',
Ma='Macemen:BAAALgAECgEJAQAAAA==.Makthra:BAAALgAECgUJEQAAAA==.Marek:BAAALgADCgUJCAAAAA==.Marionette:BAAALgADCgkJGwAAAA==.Mawseeker:BAAALgADCgEJAQAAAA==.',
Me='Megabettegaa:BAACLgAFFH8TAAMWAAMJlRnWkADqAAAWAAMJlRnWkADqAAAfAAEJqQQdBQBFAAAuAAQKf38AAhYACQnfGpMBAH8BABYACQnfGpMBAH8BAAAA.Mennathil:BAAALgADCgEJAQAAAA==.Meric:BAAALgAECgEJAwAAAA==.',
Mi='Microbrew:BAAALgAECgcJDAABLgAFFAMJBgAcAN4KAA==.Midnight:BAAALgAECgcJCQAAAA==.Milo:BAAALgAFFAEJAQAAAA==.Miniangel:BAACLgAFFH8RAAMgAAUJjxSdDwBZAQAgAAUJjxSdDwBZAQAdAAIJfQE+NwBXAAAuAAQKfx4AAyAACQl8FVYVACoCACAACQl8FVYVACoCAB0ACAk+EPAoAJMBAAAA.Mixednuts:BAAALgAECgIJAgAAAA==.',
Mo='Molasses:BAACLgAFFH8eAAIIAAUJcBLJCADvAAAIAAUJcBLJCADvAAAuAAQKf0AAAggACQnTHqUXAMsCAAgACQnTHqUXAMsCAAAA.Moof:BAAALgAECgEJAQAAAA==.',
['Mú']='Músic:BAAALgAECgIJAwAAAA==.',
Na='Najitar:BAAALgAECgQJBQAAAA==.Nazaibrew:BAAALgAECggJDAABLgAECgkJNwAUAE4fAA==.Nazera:BAAALgAECgEJAQAAAA==.',
Ne='Necromalus:BAAALgAECgEJAgAAAA==.Neerx:BAAALgADCgUJBQAAAA==.',
Nu='Nubkselk:BAABLgAECn8zAAIRAAkJ7x0KFgCTAgARAAkJ7x0KFgCTAgAAAA==.Nurishment:BAACLgAFFH8cAAIQAAgJAhSADAArAgAQAAgJAhSADAArAgAuAAQKfyUAAhAACQn7HWwSAKICABAACQn7HWwSAKICAAAA.',
Ny='Nyrr:BAAALgADCgEJAgAAAA==.',
Og='Ogmurka:BAAALgAECgEJAQAAAA==.',
On='Oni:BAAALgADCgUJBQAAAA==.Onitachi:BAABLgAECn8rAAMBAAgJzxH0RgAYAQABAAgJzxH0RgAYAQAhAAQJcAmbLgCDAAAAAA==.',
Op='Optistriker:BAABLgAECn9LAAIQAAkJaxkmFQChAgAQAAkJaxkmFQChAgAAAA==.',
Oy='Oythsar:BAAALgADCgQJBAAAAA==.',
Pa='Painfree:BAAALgADCgQJBAAAAA==.Papabear:BAAALgAECgEJAQAAAA==.',
Pe='Pemburumalam:BAAALgADCgEJAQAAAA==.',
Pi='Pig:BAABLgAECn8cAAIGAAgJKhjaKwAGAgAGAAgJKhjaKwAGAgABLgAECgkJKgAOAIAjAA==.Pinks:BAAALgADCgkJCQAAAA==.Pizlex:BAAALgAECgcJCQAAAA==.',
Po='Poplockndrop:BAAALgAECgUJBgAAAA==.Portion:BAABLgAECn8uAAIIAAgJWhxPVwDXAQAIAAgJWhxPVwDXAQAAAA==.Portlybob:BAAALgADCgEJAQAAAA==.',
Pr='Pretentious:BAACLgAFFH8GAAIOAAQJrQzjUAANAQAOAAQJrQzjUAANAQAuAAQKfx4AAg4ACAmiHysmAI4CAA4ACAmiHysmAI4CAAAA.Prettyfun:BAAALgADCgUJBQAAAA==.Prettysavage:BAAALgAECgIJAgAAAA==.Primo:BAAALgADCgYJEQAAAA==.',
['Pè']='Pèrsephônè:BAAALgADCgIJAgAAAA==.',
Ra='Radicalism:BAAALgAECgQJBQAAAA==.Raechan:BAAALgAECgEJAQAAAA==.Ranigard:BAAALgAECgUJCAAAAA==.Rantioc:BAAALgAECgUJBQAAAA==.Raugan:BAAALgAECgEJAgAAAA==.',
Re='Reparations:BAABLgAECn8ZAAMdAAgJewVESQDqAAAdAAgJewVESQDqAAAUAAUJugIuYgB0AAAAAA==.Repentofsin:BAAALgAECgQJBAAAAA==.Rexbriefs:BAABLgAECn8pAAIWAAcJjg/5iQBQAQAWAAcJjg/5iQBQAQAAAA==.',
Ri='Rice:BAAALgAFFAEJAQAAAA==.Riptong:BAAALgADCgEJAQAAAA==.',
Ro='Rovinj:BAAALgAECgkJBwAAAA==.',
Ru='Rumi:BAABLgAECn8iAAIRAAgJUxa6PwDKAQARAAgJUxa6PwDKAQAAAA==.',
Ry='Rydle:BAABLgAFFH8IAAMMAAMJDhJ/XwDmAAAMAAMJDhJ/XwDmAAAiAAEJYQeHBgA9AAAAAA==.',
Sa='Samedhi:BAAALgAECgQJBQAAAA==.Sanlesh:BAAALgADCgUJBgAAAA==.Sapodillà:BAAALgAECggJDQAAAA==.Sarijevo:BAAALgAECgkJBQAAAA==.Saurax:BAAALgAECgEJAgAAAA==.',
Sc='Scatz:BAAALgADCgIJAgAAAA==.Scott:BAAALgAECgcJCwAAAA==.Scylla:BAAALgAECgYJDwAAAA==.',
Se='Sevrin:BAACLgAFFH8SAAINAAQJjCCqEgB4AQANAAQJjCCqEgB4AQAuAAQKfy8AAg0ACQlrIx4FAOQCAA0ACQlrIx4FAOQCAAAA.',
Sh='Shadowfuryy:BAAALgAECgUJBQAAAA==.Shalati:BAAALgADCgYJBgAAAA==.Sharts:BAAALgADCgYJCQAAAA==.Shestrouble:BAACLgAFFH8GAAIIAAIJyhvVlgChAAAIAAIJyhvVlgChAAAuAAQKfyAAAggACQmrIiwKACgDAAgACQmrIiwKACgDAAAA.Shiift:BAAALgAECgMJAwABLgAFFAMJDAANAPEiAA==.Shirerat:BAAALgADCgMJBAAAAA==.Shtzson:BAABLgAECn8XAAIaAAkJCBiSEAA3AgAaAAkJCBiSEAA3AgAAAA==.Shyjinx:BAAALgAECgYJBgAAAA==.Shíft:BAAALgAECgUJBQABLgAFFAMJDAANAPEiAA==.Shííft:BAAALgAECgUJBQABLgAFFAMJDAANAPEiAA==.Shîft:BAACLgAFFH8MAAINAAMJ8SJoHQAzAQANAAMJ8SJoHQAzAQAuAAQKfzQAAw0ACQnvI6gGAMMCAA0ACAnPI6gGAMMCACMAAwl0H40SAP0AAAAA.',
Si='Siiwwy:BAAALgAECgMJAwAAAA==.',
Sl='Slice:BAAALgAFFAEJAQAAAA==.',
Sn='Snugglemuff:BAAALgAECgcJDQABLgAFFAQJBgAOAK0MAA==.',
So='Sok:BAAALgAECgEJAwAAAA==.Soladin:BAAALgAECgQJBQABLgAFFAMJBgAcAN4KAA==.Solicide:BAACLgAFFH8GAAMcAAMJ3gpNBQBYAAAcAAMJGQhNBQBYAAAkAAEJBg9cHQBCAAAuAAQKfzUABRwACQlxG20PAPABABwACAniGG0PAPABACQABwnxG9kMAOgBABAAAQlEExvIADoAABsAAQnaDv6OADEAAAAA.Solthicc:BAAALgAECggJDQAAAA==.Sonarra:BAAALgAECgYJBgAAAA==.',
Sp='Sparkle:BAACLgAFFH8iAAIXAAcJUBVrFADPAQAXAAcJUBVrFADPAQAuAAQKf4EAAhcACQkdJt4AAIEDABcACQkdJt4AAIEDAAAA.Splatacular:BAAALgADCgEJAQAAAA==.',
St='Stolenhearth:BAABLgAECn8pAAIGAAYJVwyOWgDmAAAGAAYJVwyOWgDmAAAAAA==.',
Sv='Svets:BAABLgAECn83AAMUAAkJTh/kCADlAgAUAAkJTh/kCADlAgAgAAEJ3AnKhQArAAAAAA==.',
Sw='Swavey:BAAALgADCgQJBAAAAA==.',
Sy='Sylphrenna:BAAALgAECgcJCQAAAA==.Syrana:BAAALgADCgEJAQAAAA==.',
Te='Teeanna:BAAALgAECgIJAgABLgAECgMJBAAJAAAAAA==.Temaile:BAAALgADCgEJBAAAAA==.Tenin:BAAALgADCgEJAQAAAA==.',
Th='Thinmint:BAAALgADCgEJAQAAAA==.Thoranter:BAAALgADCgYJBgAAAA==.',
Ti='Tinnman:BAAALgADCgYJBgAAAA==.',
To='Toughguytony:BAAALgADCgUJBgAAAA==.',
Tr='Trebekk:BAAALgADCgEJAQAAAA==.Treydk:BAACLgAFFH8NAAIWAAQJWh00TwBUAQAWAAQJWh00TwBUAQAuAAQKfxwAAxYACQm/HdMZAKwCABYACQl2HdMZAKwCAB8ABQkYHGIZAAgBAAAA.Trreyy:BAABLgAECn8fAAIOAAgJqh5YKACEAgAOAAgJqh5YKACEAgAAAA==.',
Ts='Tsimfuqis:BAABLgAFFH8LAAINAAQJMhJFHgAvAQANAAQJMhJFHgAvAQAAAA==.',
Tw='Twighumper:BAAALgAECgUJBwABLgAECgkJFwAaAAgYAA==.Twizzly:BAAALgAFFAIJAgAAAA==.Twizzy:BAACLgAFFH8OAAIMAAQJpwV4CwCDAAAMAAQJpwV4CwCDAAAuAAQKf0IAAgwACQnyFJ4oADwCAAwACQnyFJ4oADwCAAAA.',
Ty='Tyranhikar:BAAALgADCgEJAQAAAA==.',
Tz='Tzechan:BAACLgAFFH8GAAIVAAMJ8RpUJgDvAAAVAAMJ8RpUJgDvAAAuAAQKfx8AAxUACQkiG/IdABMCABUACQkiG/IdABMCAA4AAgmcEpRBAWoAAAAA.',
Ug='Uggalee:BAAALgAFFAIJAwAAAA==.',
Va='Valtirya:BAAALgAECgQJBgAAAA==.Vampirellaa:BAAALgAECgEJAQAAAA==.Vayzen:BAABLgAECn8YAAIXAAcJDB4uEwBNAgAXAAcJDB4uEwBNAgAAAA==.',
Ve='Velac:BAAALgAECgUJCwAAAA==.',
Vi='Virexus:BAAALgADCgIJAgAAAA==.',
Vo='Voidfree:BAABLgAECn8oAAIRAAgJqgsncwA7AQARAAgJqgsncwA7AQAAAA==.',
Vy='Vynarc:BAABLgAECn8qAAIOAAgJihHPZQC1AQAOAAgJihHPZQC1AQAAAA==.',
Wa='Warcrimes:BAAALgAECgEJAQAAAA==.Watervendor:BAABLgAECn8vAAIIAAkJgBvbMABWAgAIAAkJgBvbMABWAgAAAA==.',
We='Wearegroot:BAAALgAECgEJAQAAAA==.Webedeadiy:BAAALgADCgEJAQAAAA==.',
Wh='Whiteknight:BAAALgAECgYJBgAAAA==.',
Wi='Wiggimbottom:BAAALgAECgYJEgAAAA==.Wihtè:BAAALgAECgMJAwAAAA==.Willscarlet:BAAALgADCgQJBAAAAA==.',
Wo='Wolffoxfangs:BAABLgAECn8VAAIMAAcJ/BVwaAByAQAMAAcJ/BVwaAByAQAAAA==.',
['Wá']='Wárpaiint:BAABLgAECn8rAAMMAAcJwg04BAD5AAAMAAQJZhE4BAD5AAAiAAcJoQuiFwD2AAABLgAFFAMJCQAIAJURAA==.',
Xa='Xalatoes:BAAALgAECgUJBQAAAA==.',
Xe='Xeados:BAAALgAECgIJAgAAAA==.Xenos:BAAALgADCgEJAQAAAA==.',
Yi='Yin:BAAALgADCgcJDQAAAA==.',
['Yè']='Yèlloow:BAAALgAECgMJBQAAAA==.',
Za='Zaquel:BAAALgAFFAEJAQAAAA==.Zarcissa:BAAALgAECgYJDQAAAA==.Zavira:BAAALgADCgcJBwAAAA==.',
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
