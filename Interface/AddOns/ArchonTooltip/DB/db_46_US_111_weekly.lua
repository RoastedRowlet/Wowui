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

local lookup = {'Shaman-Elemental','Shaman-Restoration','Monk-Mistweaver','DeathKnight-Blood','Warrior-Fury','Warrior-Arms','Warrior-Protection','Mage-Frost','Unknown-Unknown','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Rogue-Subtlety','Paladin-Retribution','Hunter-Survival','Druid-Restoration','DemonHunter-Devourer','Evoker-Preservation','Evoker-Devastation','Priest-Discipline','Paladin-Holy','DeathKnight-Unholy','Evoker-Augmentation','Warlock-Affliction','Monk-Windwalker','Monk-Brewmaster','Druid-Balance','Druid-Guardian','Priest-Shadow','DemonHunter-Havoc','DeathKnight-Frost','Priest-Holy','Shaman-Enhancement','Hunter-Marksmanship','Rogue-Assassination','DemonHunter-Vengeance','Druid-Feral',}
local provider = {region='US',realm='Gorgonnash',name='US',type='weekly',zone=46,date='2026-07-05',data={Aa='Aakira:BAABLgAECn8VAAMBAAkJzQguPgA8AQABAAkJzQguPgA8AQACAAEJuAMA6wAkAAAAAA==.Aangie:BAABLgAECn8YAAIDAAcJngZMPAD0AAADAAcJngZMPAD0AAAAAA==.Aanjie:BAABLgAECn8aAAIDAAYJQwkcbADSAAADAAYJQwkcbADSAAAAAA==.Aathea:BAAALgAECgYJBgAAAA==.',
Ab='Abban:BAAALgAECgMJAwAAAA==.Abom:BAAALgAECgIJAgAAAA==.Abrastal:BAAALgAECgQJCAAAAA==.',
Ad='Adrestia:BAAALgAECgQJBgAAAA==.',
Ak='Akbar:BAAALgAECgUJBQAAAA==.',
Al='Alline:BAABLgAECn8dAAIEAAYJcBLTJgAdAQAEAAYJcBLTJgAdAQAAAA==.Alswaron:BAAALgAECgUJEwAAAA==.',
Am='Amador:BAACLgAFFH8ZAAQFAAQJGh/MCwAOAQAGAAQJnB3eEwA/AQAFAAQJkxvMCwAOAQAHAAEJnB1eKgBKAAAuAAQKfyoABAYACQl5IucGAIwCAAYACAl5IucGAIwCAAUABAndGulpAA4BAAcAAgmuFo06AHcAAAAA.Amorlan:BAAALgAECgEJAQAAAA==.Amyra:BAAALgAECgEJAQAAAA==.',
An='Annox:BAAALgAECgQJBwAAAA==.',
Ap='Apsallar:BAABLgAECn8dAAIIAAkJzBx7HwChAgAIAAkJzBx7HwChAgAAAA==.',
Ar='Arcanedream:BAAALgAECgUJBQABLgAECgkJCgAJAAAAAA==.Arcanism:BAABLgAECn8cAAIIAAcJshOjngCZAQAIAAcJshOjngCZAQAAAA==.Arlas:BAAALgAECgMJBgAAAA==.Arthone:BAAALgADCgUJBQAAAA==.',
As='Aserai:BAAALgADCgMJAwAAAA==.Asstalor:BAABLgAECn8dAAMKAAgJmxAfZQB0AQAKAAgJWxAfZQB0AQALAAEJjxJsPgA0AAAAAA==.',
Au='Auggy:BAAALgAECgMJAwAAAA==.Auryon:BAACLgAFFH8HAAIMAAEJcxiGUgBNAAAMAAEJcxiGUgBNAAAuAAQKfzAAAgwACAnDIXsiAFoCAAwACAnDIXsiAFoCAAAA.',
Av='Avelna:BAAALgADCgcJBwABLgADCgcJDQAJAAAAAA==.',
Az='Azmodea:BAAALgADCgEJAgAAAA==.',
Ba='Baccstab:BAAALgAECgYJDAAAAA==.Bagains:BAAALgADCgcJEwAAAA==.Bangnyfe:BAAALgAFFAIJAgABLgAFFAMJBgANAJgZAA==.Baraka:BAAALgAECgYJCgAAAA==.Baulder:BAABLgAECn8cAAIFAAcJawdeUQAEAQAFAAcJawdeUQAEAQAAAA==.',
Bi='Bigb:BAAALgAFFAEJAQABLgAFFAkJPwAIAE4kAA==.Bigolcrittie:BAAALgADCgIJAgAAAA==.',
Bl='Blerpleberry:BAAALgAECgUJBQAAAA==.Bloodfurry:BAAALgAECgMJAQAAAA==.Bluè:BAABLgAECn8bAAMBAAgJCxbWMAB8AQABAAgJCxbWMAB8AQACAAUJjBr/TQB5AQAAAA==.',
Bn='Bnakka:BAAALgAFFAEJAQAAAA==.',
Bo='Bobdaunicorn:BAAALgAECgEJAQAAAA==.Boltz:BAAALgAECgMJAwAAAA==.Bombalaharis:BAAALgAECgcJDQAAAA==.',
Br='Brekke:BAACLgAFFH8MAAIOAAQJsQ+qSwAWAQAOAAQJsQ+qSwAWAQAuAAQKfy8AAg4ACQlgGKs1ACoCAA4ACQlgGKs1ACoCAAAA.Brokenbow:BAACLgAFFH8HAAMPAAQJjQrZIADSAAAPAAMJwgfZIADSAAAMAAEJ7BK/pABJAAAuAAQKfxsAAw8ACQmmE3IfAKABAA8ACQnNDnIfAKABAAwABAkIGMV9AO4AAAAA.',
Bu='Bullshaft:BAAALgAECgEJAQAAAA==.Buntz:BAABLgAECn8qAAIOAAkJgCOZDAAAAwAOAAkJgCOZDAAAAwAAAA==.Bushmethsin:BAACLgAFFH8cAAIQAAgJFCNrBQC7AgAQAAgJFCNrBQC7AgAuAAQKfxUAAhAACAlVIg0eAE4CABAACAlVIg0eAE4CAAAA.Buttery:BAABLgAECn8UAAIOAAcJABd2hgBjAQAOAAcJABd2hgBjAQAAAA==.',
Bz='Bz:BAAALgADCgcJBwAAAA==.',
Ca='Cabb:BAABLgAECn8ZAAMFAAYJihaARwAoAQAFAAQJGxqARwAoAQAHAAYJsgcjMQC5AAAAAA==.',
Ce='Ceedubble:BAAALgAECgkJEAAAAA==.Celestine:BAAALgADCgYJBgABLgAECgkJKAARAEsOAA==.',
Ch='Charmanderz:BAABLgAECn8mAAMSAAgJIxG2FQBxAQASAAgJIxG2FQBxAQATAAEJIhWjOwA/AAABLgAECgkJFAAUAO8LAA==.Cherchlglsia:BAAALgADCgQJCAAAAA==.Chewsdee:BAAALgAECgQJBAAAAA==.Christlovesu:BAAALgAECgIJAgAAAA==.Chuckrules:BAAALgADCgcJDgAAAA==.',
Cl='Clackshi:BAAALgAECgYJCgAAAA==.',
Cr='Critable:BAABLgAECn80AAMVAAkJIxY8GwAqAgAVAAkJIxY8GwAqAgAOAAkJuAoXggB2AQAAAA==.',
Cu='Curst:BAAALgAECggJEwAAAA==.',
Da='Dagares:BAAALgADCggJDQAAAA==.Dahnte:BAAALgAECgEJAQAAAA==.',
De='Dechala:BAABLgAECn8oAAIRAAkJSw5BUwCMAQARAAkJSw5BUwCMAQAAAA==.Deezknights:BAACLgAFFH8VAAMWAAgJzBwLEwBDAgAWAAgJzBwLEwBDAgAEAAEJAACTWQAAAAAuAAQKfycAAhYACQkGJU4JAFIDABYACQkGJU4JAFIDAAAA.Deezpuffs:BAABLgAFFH8KAAMXAAQJOxVSLgAKAQAXAAQJOxVSLgAKAQASAAEJpQD5MAAiAAABLgAFFAgJFQAWAMwcAA==.Deezrage:BAAALgADCgYJBgAAAA==.Derailed:BAAALgADCgEJAgAAAA==.Dergon:BAACLgAFFH8HAAIKAAMJNw3IfADKAAAKAAMJNw3IfADKAAAuAAQKfykAAgoACQloHEUkAE4CAAoACQloHEUkAE4CAAAA.Destiria:BAABLgAECn8kAAMKAAgJuBnfQQDWAQAKAAgJuBnfQQDWAQAYAAMJegd5JwBUAAAAAA==.Devistatorxx:BAAALgAECgYJCgAAAA==.',
Do='Doggyystyle:BAAALgAECgEJAQAAAA==.Dogwalker:BAAALgAFFAIJAwAAAA==.Donaldpump:BAAALgAECgYJBwAAAA==.Doomedturtle:BAAALgAECgYJCAAAAA==.Doublekill:BAAALgAECgUJDAAAAA==.',
Du='Duergan:BAACLgAFFH8XAAIZAAQJFRQKBgAGAQAZAAQJFRQKBgAGAQAuAAQKfy8ABBoACQkDEtQDAOgAABkACAkTFPorAGABABoACQkICtQDAOgAAAMAAQlFAwRyACEAAAAA.',
['Dà']='Dàrkblade:BAAALgAECgcJEQAAAA==.',
Ea='Eatz:BAAALgADCgYJBgAAAA==.',
Eh='Ehcks:BAAALgAECgQJBAAAAA==.',
Em='Emotionaldmg:BAAALgADCgYJCwAAAA==.',
Fa='Faelyn:BAAALgADCgEJBAAAAA==.Fansy:BAAALgAFFAMJAwAAAA==.',
Fe='Felwind:BAABLgAECn8iAAIMAAcJ6iNqBADzAQAMAAcJ6iNqBADzAQAAAA==.Ferus:BAAALgADCgkJCQAAAA==.',
Fi='Fillycheese:BAAALgAECgEJAQAAAA==.',
Fl='Fleurelle:BAAALgAECgUJBwAAAA==.',
Fr='Frollo:BAAALgAECgEJAQAAAA==.Frosstitute:BAAALgAECgMJAwAAAA==.',
Fu='Furfiend:BAACLgAFFH8KAAIWAAQJRBq8VQBGAQAWAAQJRBq8VQBGAQAuAAQKfykAAxYACQndHyUrAFMCABYACQlaHiUrAFMCAAQABQk4G5woABABAAAA.',
Gi='Giantdog:BAAALgAECgUJBQAAAA==.Gilraen:BAACLgAFFH8RAAMFAAQJmA71EgDLAAAFAAQJ8wz1EgDLAAAGAAEJXQ/bRAA9AAAuAAQKfz8AAwYACQk3GQQOAAkCAAYACQn5FgQOAAkCAAUACQmSE+InALwBAAAA.Gingerjen:BAABLgAECn8UAAMQAAgJ9wefZQADAQAQAAgJ9wefZQADAQAbAAgJcgMvUgDFAAAAAA==.',
Go='Gorgrand:BAAALgAECgcJBwAAAA==.Gothbiotch:BAAALgAECgMJAwAAAA==.',
Gr='Greaseduppig:BAAALgAECgEJAQAAAA==.Greggnog:BAAALgAECgkJDAAAAA==.Greggy:BAAALgAECgUJCQABLgAECgkJDAAJAAAAAA==.Grenache:BAAALgAECgMJBAAAAA==.',
Ha='Hairypotter:BAAALgADCgUJBQAAAA==.Halfworld:BAAALgADCgYJBgAAAA==.Happydaze:BAACLgAFFH8IAAMEAAMJKBFpKgClAAAEAAMJKBFpKgClAAAWAAEJcwXmhgA3AAAuAAQKfysAAwQACQlUG+IPAA0CAAQACQkGG+IPAA0CABYAAwloEowsAXMAAAAA.Harshdruid:BAAALgAECgEJAQABLgAFFAMJCgAUAL8SAA==.Haxthedk:BAAALgAECgEJAQAAAA==.Haxthedruid:BAAALgAECgEJAQAAAA==.Haxthemonk:BAAALgAECgEJAQAAAA==.',
He='Hemotoxin:BAAALgAECgMJAwAAAA==.Hendel:BAAALgAECgQJBgAAAA==.Herkaferk:BAABLgAECn8XAAIBAAYJiBMqRQAfAQABAAYJiBMqRQAfAQAAAA==.',
Ho='Hojx:BAAALgAECgEJAQAAAA==.',
Hr='Hrolf:BAABLgAECn8/AAMcAAgJsBIVAwBdAQAcAAgJsBIVAwBdAQAQAAEJyRGyzwA1AAABLgAFFAQJFwAZABUUAA==.',
Il='Illiannà:BAABLgAECn8UAAMUAAkJ7wujJQCjAQAUAAkJ7wujJQCjAQAdAAEJwRUsfgBBAAAAAA==.Illidont:BAABLgAECn8WAAIeAAkJWRAYHACcAQAeAAkJWRAYHACcAQAAAA==.Illijr:BAABLgAECn8cAAIeAAkJ1BOZFQDgAQAeAAkJ1BOZFQDgAQAAAA==.',
It='Ithil:BAAALgADCgkJDwAAAA==.',
Ja='Jaemison:BAAALgADCgQJAwAAAA==.',
Ji='Jicks:BAABLgAECn8iAAIUAAgJOAxoOgAmAQAUAAgJOAxoOgAmAQAAAA==.',
Jk='Jkass:BAACLgAFFH8LAAINAAMJyA16FgCNAAANAAMJyA16FgCNAAAuAAQKfxsAAg0ACAn+FgccALYBAA0ACAn+FgccALYBAAAA.',
Ju='Judgementdày:BAAALgAECggJCgAAAA==.',
['Jà']='Jàk:BAAALgAECgIJAgAAAA==.',
Ka='Kaldarr:BAAALgAECgEJAQAAAA==.Kamaeria:BAACLgAFFH8PAAIdAAQJpwQHEACYAAAdAAQJpwQHEACYAAAuAAQKfzkAAh0ACQn0FDAWABkCAB0ACQn0FDAWABkCAAEuAAUUBAkRAAwApwUA.Kaíros:BAAALgADCgMJAwAAAA==.',
Kh='Khaotica:BAAALgADCgkJCQAAAA==.',
Ki='Kiandara:BAACLgAFFH8aAAMFAAUJrhkFHgA5AQAFAAUJrhkFHgA5AQAGAAQJwRJAGwAPAQAuAAQKfyQAAwUACQmQHPIMAO4CAAUACQmQHPIMAO4CAAcABQkcG94dAFcBAAAA.Kikkoman:BAABLgAFFH8GAAINAAMJmBltJAAAAQANAAMJmBltJAAAAQAAAA==.Kilmas:BAAALgAECgIJAgAAAA==.Kinetic:BAAALgAECgEJAQAAAA==.Kirant:BAAALgADCggJDQAAAA==.Kirara:BAAALgADCgYJBgAAAA==.',
Ko='Kooz:BAAALgADCgUJBQAAAA==.Kooze:BAAALgADCgUJCAAAAA==.Koozo:BAAALgADCgMJAwAAAA==.Kozar:BAAALgAECgcJBwAAAA==.',
Kt='Kt:BAABLgAECn8aAAIIAAcJNhNlmQBGAQAIAAcJNhNlmQBGAQAAAA==.',
Ku='Kush:BAAALgADCgEJAQABLgAECgkJKgAOAIAjAA==.',
Ky='Kynrath:BAAALgAECggJCwAAAA==.',
La='Laurie:BAAALgADCgMJBgAAAA==.Lava:BAAALgADCgUJBQABLgAECggJDwAJAAAAAA==.Lavablast:BAAALgADCgYJCwAAAA==.',
Le='Lelanie:BAAALgADCggJDgAAAA==.',
Li='Lichnfamous:BAACLgAFFH8JAAIWAAQJ/AtTdwAUAQAWAAQJ/AtTdwAUAQAuAAQKfykAAxYACAnRFa9NANkBABYACAnRFa9NANkBAB8ABAnqDOwfAM0AAAAA.Lightfrost:BAAALgAECgIJAgAAAA==.Lightning:BAAALgAECgUJCAAAAA==.Likkan:BAAALgAECgEJAQAAAA==.Lilithdawn:BAABLgAECn8jAAIgAAkJvhvsEABdAgAgAAkJvhvsEABdAgAAAA==.',
Lo='Lockwar:BAABLgAECn8fAAQYAAkJmxf2CgCvAQAYAAkJmxf2CgCvAQAKAAQJFAfe5QCSAAALAAEJTwDpSQAFAAAAAA==.Louvre:BAABLgAECn8uAAINAAkJtxx2CQCOAgANAAkJtxx2CQCOAgAAAA==.Lowehigh:BAAALgAECgEJAQAAAA==.',
Lu='Lukarian:BAABLgAFFH8GAAIOAAMJiw4hcgDOAAAOAAMJiw4hcgDOAAAAAA==.',
Ma='Macemen:BAAALgAECgEJAQAAAA==.Makthra:BAAALgAECgUJEQAAAA==.Marek:BAAALgADCgUJCAAAAA==.Marionette:BAAALgAECgEJAQAAAA==.Mawseeker:BAAALgADCgEJAQAAAA==.',
Me='Megabettegaa:BAACLgAFFH8YAAMWAAMJWRuqOADCAAAWAAMJWRuqOADCAAAfAAEJqQSvEwBBAAAuAAQKf38AAhYACQnfGqgsAE0CABYACQnfGqgsAE0CAAAA.Melbuki:BAAALgAECgUJBwAAAA==.Mennathil:BAAALgADCgEJAQAAAA==.Meric:BAAALgAECgEJAwAAAA==.',
Mi='Microbrew:BAAALgAECgcJDAABLgAFFAMJBgAcAN4KAA==.Midnight:BAAALgAECgcJCQABLgAECgkJCgAJAAAAAA==.Milo:BAAALgAFFAEJAQAAAA==.Miniangel:BAACLgAFFH8RAAMgAAUJjxSaDwBZAQAgAAUJjxSaDwBZAQAdAAIJfQFANwBXAAAuAAQKfx4AAyAACQl8FVYVACoCACAACQl8FVYVACoCAB0ACAk+EPAoAJMBAAAA.Mixednuts:BAAALgAECgIJAgAAAA==.',
Mo='Molasses:BAACLgAFFH8gAAIIAAUJphOLJwDnAAAIAAUJphOLJwDnAAAuAAQKf0AAAggACQnTHqMXAMsCAAgACQnTHqMXAMsCAAAA.Moof:BAAALgAECgEJAQAAAA==.',
['Mú']='Músic:BAAALgAECgIJAwAAAA==.',
Na='Najitar:BAAALgAECgQJBQAAAA==.Nazaibrew:BAAALgAECggJDAABLgAECgkJOwAUAE4fAA==.Nazera:BAAALgAECgEJAQAAAA==.',
Ne='Necromalus:BAAALgAECgEJAgAAAA==.Neerx:BAAALgADCgUJBQAAAA==.',
Nu='Nubkselk:BAABLgAECn8zAAIRAAkJ7x0JFgCTAgARAAkJ7x0JFgCTAgAAAA==.Nurishment:BAACLgAFFH8cAAIQAAgJAhR+DAArAgAQAAgJAhR+DAArAgAuAAQKfyUAAhAACQn7HWwSAKICABAACQn7HWwSAKICAAAA.',
Ny='Nyrr:BAAALgADCgEJAgAAAA==.',
Og='Ogmurka:BAAALgAECgEJAQAAAA==.',
On='Oni:BAAALgADCgUJBQAAAA==.Onitachi:BAABLgAECn8rAAMBAAgJzxH3RgAYAQABAAgJzxH3RgAYAQAhAAQJcAmcLgCDAAAAAA==.',
Op='Optistriker:BAABLgAECn9LAAIQAAkJaxknFQChAgAQAAkJaxknFQChAgAAAA==.',
Oy='Oythsar:BAAALgADCgQJBAAAAA==.',
Pa='Painfree:BAAALgADCgQJBAAAAA==.Papabear:BAAALgAECgEJAQAAAA==.',
Pe='Pemburumalam:BAAALgADCgEJAQAAAA==.',
Pi='Pig:BAABLgAECn8cAAIFAAgJKhjaKwAGAgAFAAgJKhjaKwAGAgABLgAECgkJKgAOAIAjAA==.Pinks:BAAALgADCgkJCQAAAA==.Pizlex:BAAALgAECgcJCQAAAA==.',
Po='Poplockndrop:BAAALgAECgUJBgAAAA==.Portion:BAABLgAECn8uAAIIAAgJWhxQVwDXAQAIAAgJWhxQVwDXAQAAAA==.Portlybob:BAAALgADCgEJAQAAAA==.',
Pr='Pretentious:BAACLgAFFH8GAAIOAAQJrQzUUAANAQAOAAQJrQzUUAANAQAuAAQKfx4AAg4ACAmiHysmAI4CAA4ACAmiHysmAI4CAAAA.Prettyfun:BAAALgADCgUJBQAAAA==.Prettysavage:BAAALgAECgIJAgAAAA==.Primo:BAAALgADCgYJEQAAAA==.',
['Pè']='Pèrsephônè:BAAALgADCgIJAgAAAA==.',
Ra='Radicalism:BAAALgAECgQJBQAAAA==.Raechan:BAAALgAECgEJAQAAAA==.Ranigard:BAAALgAECgUJCAAAAA==.Rantioc:BAAALgAECgUJBQAAAA==.Raugan:BAAALgAECgEJAwAAAA==.',
Re='Reparations:BAABLgAECn8gAAMdAAgJlAidBwDcAAAdAAgJlAidBwDcAAAUAAUJugIwYgB0AAAAAA==.Repentofsin:BAAALgAECgQJBAAAAA==.Rexbriefs:BAABLgAECn84AAIWAAcJbRE2DAALAQAWAAcJbRE2DAALAQAAAA==.',
Ri='Rice:BAAALgAFFAEJAQAAAA==.Riptong:BAAALgADCgEJAQAAAA==.',
Ro='Rovinj:BAAALgAECgkJBwAAAA==.',
Ru='Rukhmear:BAAALgAECgEJAQAAAA==.Rumi:BAABLgAECn8jAAIRAAgJ4xe8PwDKAQARAAgJ4xe8PwDKAQAAAA==.',
Ry='Rydle:BAABLgAFFH8JAAMMAAQJsQ59XwDmAAAMAAQJsQ59XwDmAAAiAAEJYQd3GAA6AAAAAA==.',
Sa='Samedhi:BAAALgAECgQJBQAAAA==.Sanlesh:BAAALgADCgUJBgAAAA==.Sapodillà:BAAALgAECggJDQAAAA==.Sarijevo:BAAALgAECgkJBQAAAA==.Saurax:BAAALgAECgEJAgAAAA==.',
Sc='Scatz:BAAALgADCgIJAgAAAA==.Scott:BAAALgAECgcJCwAAAA==.Scylla:BAAALgAECgYJDwAAAA==.',
Se='Seraxx:BAAALgADCgEJAQAAAA==.Sevrin:BAACLgAFFH8XAAINAAUJjCBlBwBcAQANAAUJjCBlBwBcAQAuAAQKfy8AAg0ACQlrIx8FAOQCAA0ACQlrIx8FAOQCAAAA.',
Sh='Shadowfuryy:BAAALgAECgUJBQAAAA==.Shalati:BAAALgADCgYJBgAAAA==.Sharts:BAAALgADCgYJCQAAAA==.Shestrouble:BAACLgAFFH8GAAIIAAIJyhvClgChAAAIAAIJyhvClgChAAAuAAQKfyUAAggACQn1IikKACgDAAgACQn1IikKACgDAAAA.Shiift:BAAALgAECgMJAwABLgAFFAMJDAANAPEiAA==.Shirerat:BAAALgADCgMJBAAAAA==.Shtzson:BAABLgAECn8iAAIaAAkJhxunAAB9AgAaAAkJhxunAAB9AgAAAA==.Shyjinx:BAAALgAECgYJBgAAAA==.Shíft:BAAALgAECgUJBQABLgAFFAMJDAANAPEiAA==.Shííft:BAAALgAECgUJBQABLgAFFAMJDAANAPEiAA==.Shîft:BAACLgAFFH8MAAINAAMJ8SJgHQA0AQANAAMJ8SJgHQA0AQAuAAQKfzQAAw0ACQnvI6kGAMMCAA0ACAnPI6kGAMMCACMAAwl0H40SAP0AAAAA.Shïìft:BAAALgAFFAEJAQABLgAFFAMJDAANAPEiAA==.',
Si='Siiwwy:BAAALgAECgMJAwAAAA==.',
Sl='Slice:BAABLgAFFH8IAAMkAAMJJAopBACSAAAkAAMJJAopBACSAAAeAAEJ4AGoMgAsAAAAAA==.',
So='Sok:BAAALgAECgEJAwAAAA==.Soktear:BAAALgAECgEJAgAAAA==.Soladin:BAAALgAECgQJBQABLgAFFAMJBgAcAN4KAA==.Soladis:BAAALgADCgYJBgABLgAECgkJIgAaAIcbAA==.Solicide:BAACLgAFFH8GAAMcAAMJ3gr3JwB7AAAcAAMJGQj3JwB7AAAlAAEJBg9cHQBCAAAuAAQKfzUABRwACQlxG2wPAPABABwACAniGGwPAPABACUABwnxG9oMAOgBABAAAQlEExvIADoAABsAAQnaDgGPADEAAAAA.Solthicc:BAAALgAECggJDQAAAA==.Sonarra:BAAALgAECgYJBgAAAA==.',
Sp='Sparkle:BAACLgAFFH8mAAIXAAcJVBVJFADRAQAXAAcJVBVJFADRAQAuAAQKf4oAAxcACQkhJt4AAIEDABcACQkhJt4AAIEDABMAAwlKIxkBADUBAAAA.Splatacular:BAAALgADCgEJAQAAAA==.',
St='Stolenhearth:BAABLgAECn8tAAIFAAYJ3w8oCADoAAAFAAYJ3w8oCADoAAAAAA==.',
Sv='Svets:BAABLgAECn87AAMUAAkJTh/jCADlAgAUAAkJTh/jCADlAgAgAAEJ3AnKhQArAAAAAA==.',
Sw='Swavey:BAAALgADCgQJBAAAAA==.',
Sy='Sylphrenna:BAAALgAECgcJCQAAAA==.Syrana:BAAALgADCgEJAQAAAA==.',
Te='Teeanna:BAAALgAECgMJBQABLgAECgMJBgAJAAAAAA==.Temaile:BAAALgADCgEJBAAAAA==.Tenin:BAAALgADCgEJAQAAAA==.',
Th='Thinmint:BAAALgADCgEJAQAAAA==.Thoranter:BAAALgADCgYJCQAAAA==.',
Ti='Tinnman:BAAALgADCgYJBgAAAA==.',
To='Toughguytony:BAAALgADCgUJBgAAAA==.',
Tr='Trebekk:BAAALgADCgEJAQAAAA==.Treydk:BAACLgAFFH8NAAIWAAQJWh0vTwBUAQAWAAQJWh0vTwBUAQAuAAQKfxwAAxYACQm/HdMZAKwCABYACQl2HdMZAKwCAB8ABQkYHGIZAAgBAAAA.Trreyy:BAABLgAECn8fAAIOAAgJqh5YKACEAgAOAAgJqh5YKACEAgAAAA==.',
Ts='Tsimfuqis:BAABLgAFFH8LAAINAAQJMhJAHgAvAQANAAQJMhJAHgAvAQAAAA==.',
Tw='Twighumper:BAAALgAECgUJBwABLgAECgkJIgAaAIcbAA==.Twizzly:BAAALgAFFAIJAgAAAA==.Twizzy:BAACLgAFFH8RAAIMAAQJpwVQLAC3AAAMAAQJpwVQLAC3AAAuAAQKf0IAAgwACQnyFJwoADwCAAwACQnyFJwoADwCAAAA.',
Ty='Tyranhikar:BAAALgADCgEJAQAAAA==.',
Tz='Tzechan:BAACLgAFFH8GAAIVAAMJ8RpQJgDvAAAVAAMJ8RpQJgDvAAAuAAQKfx8AAxUACQkiG/EdABMCABUACQkiG/EdABMCAA4AAgmcEp1BAWoAAAAA.',
Ug='Uggalee:BAAALgAFFAIJAwAAAA==.',
Va='Valtirya:BAAALgAECgQJBgAAAA==.Vampirellaa:BAAALgAECgEJAQAAAA==.Vanaria:BAAALgAECgQJBAAAAA==.Vayzen:BAABLgAECn8YAAIXAAcJDB4uEwBNAgAXAAcJDB4uEwBNAgAAAA==.',
Ve='Velac:BAAALgAECgUJCwAAAA==.',
Vi='Virexus:BAAALgADCgIJAgAAAA==.',
Vo='Voidfree:BAABLgAECn8tAAIRAAkJfwxgDQDVAAARAAkJfwxgDQDVAAAAAA==.',
Vy='Vynarc:BAABLgAECn8qAAIOAAgJihHPZQC1AQAOAAgJihHPZQC1AQAAAA==.',
Wa='Warcrimes:BAAALgAECgEJAQAAAA==.Watervendor:BAABLgAECn8vAAIIAAkJgBvYMABWAgAIAAkJgBvYMABWAgAAAA==.',
We='Wearegroot:BAAALgAECgEJAQAAAA==.Webedeadiy:BAAALgADCgEJAQAAAA==.',
Wh='Whiteknight:BAAALgAECgYJBgAAAA==.',
Wi='Wiggimbottom:BAAALgAECgYJEgAAAA==.Wihtè:BAAALgAECgMJAwAAAA==.Willscarlet:BAAALgADCgQJBAAAAA==.',
Wo='Wolffoxfangs:BAABLgAECn8VAAIMAAcJ/BVvaAByAQAMAAcJ/BVvaAByAQAAAA==.',
['Wá']='Wárpaiint:BAABLgAECn8rAAMMAAcJwg3cEQDtAAAiAAcJoQujFwD2AAAMAAQJZhHcEQDtAAABLgAFFAMJCQAIAJURAA==.',
Xa='Xalatoes:BAAALgAECgUJBQAAAA==.',
Xe='Xeados:BAAALgAECgIJAgAAAA==.Xenos:BAAALgADCgEJAQAAAA==.',
Yi='Yin:BAAALgADCgcJDQAAAA==.',
['Yè']='Yèlloow:BAAALgAECgMJBQAAAA==.',
Za='Zaquel:BAABLgAECn8UAAMMAAgJ/xpCUgCsAQAMAAgJOhdCUgCsAQAPAAcJQhJvIgCKAQABLgAFFAMJDAAOAM8RAA==.Zarcissa:BAAALgAECgYJDQAAAA==.Zavira:BAAALgADCgcJBwAAAA==.',
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
