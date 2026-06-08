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

local lookup = {'Shaman-Elemental','Shaman-Restoration','Monk-Mistweaver','DeathKnight-Blood','Warrior-Arms','Warrior-Fury','Warrior-Protection','Mage-Frost','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Unknown-Unknown','Paladin-Retribution','Hunter-Survival','Druid-Restoration','DemonHunter-Devourer','Evoker-Preservation','Evoker-Devastation','Paladin-Holy','DeathKnight-Unholy','Evoker-Augmentation','Warlock-Affliction','Monk-Windwalker','Monk-Brewmaster','Druid-Guardian','DemonHunter-Havoc','Priest-Discipline','Rogue-Subtlety','Priest-Shadow','Priest-Holy','Shaman-Enhancement','Rogue-Assassination','Druid-Feral','Druid-Balance','DeathKnight-Frost','Hunter-Marksmanship',}
local provider = {region='US',realm='Gorgonnash',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aakira:BAABLgAECn8VAAMBAAkJzQhEOgA9AQABAAkJzQhEOgA9AQACAAEJuAOR3AAkAAAAAA==.Aangie:BAABLgAECn8YAAIDAAcJngZMPAD0AAADAAcJngZMPAD0AAAAAA==.Aanjie:BAABLgAECn8aAAIDAAYJQwmpYgDRAAADAAYJQwmpYgDRAAAAAA==.Aathea:BAAALgAECgYJBgAAAA==.',
Ab='Abban:BAAALgAECgMJAwAAAA==.Abom:BAAALgAECgIJAgAAAA==.Abrastal:BAAALgAECgQJCAAAAA==.',
Ad='Adrestia:BAAALgAECgQJBgAAAA==.',
Ak='Akbar:BAAALgAECgUJBQAAAA==.',
Al='Alline:BAABLgAECn8XAAIEAAYJ+QsyMgDIAAAEAAYJ+QsyMgDIAAAAAA==.Alswaron:BAAALgAECgUJEwAAAA==.',
Am='Amador:BAACLgAFFH8RAAQFAAQJGR6YEQA6AQAFAAQJxByYEQA6AQAGAAIJrxEXIQBTAAAHAAEJnB2PJgBOAAAuAAQKfyoABAUACQl5Ik4GAJACAAUACAl5Ik4GAJACAAYABAndGulpAA4BAAcAAgmuFo06AHcAAAAA.Amorlan:BAAALgAECgEJAQAAAA==.Amyra:BAAALgAECgEJAQAAAA==.',
An='Annox:BAAALgAECgQJBwAAAA==.',
Ap='Apsallar:BAABLgAECn8ZAAIIAAgJUBpxPAAiAgAIAAgJUBpxPAAiAgAAAA==.',
Ar='Arcanism:BAABLgAECn8cAAIIAAcJshOjngCZAQAIAAcJshOjngCZAQAAAA==.Arlas:BAAALgAECgIJAwAAAA==.Arthone:BAAALgADCgUJBQAAAA==.',
As='Aserai:BAAALgADCgMJAwAAAA==.Asstalor:BAABLgAECn8dAAMJAAgJmxCJXgB/AQAJAAgJWxCJXgB/AQAKAAEJjxIKOwA0AAAAAA==.',
Au='Auggy:BAAALgAECgMJAwAAAA==.Auryon:BAABLgAECn8wAAILAAgJwyH5HgBhAgALAAgJwyH5HgBhAgAAAA==.',
Av='Avelna:BAAALgADCgcJBwABLgADCgcJDQAMAAAAAA==.',
Az='Azmodea:BAAALgADCgEJAgAAAA==.',
Ba='Baccstab:BAAALgAECgYJDAAAAA==.Bagains:BAAALgADCgcJEwAAAA==.Baraka:BAAALgAECgYJCgAAAA==.Baulder:BAABLgAECn8cAAIGAAcJawcGTAANAQAGAAcJawcGTAANAQAAAA==.',
Bi='Bigb:BAAALgAFFAEJAQABLgAFFAkJKAAIALcjAA==.Bigolcrittie:BAAALgADCgIJAgAAAA==.',
Bl='Blerpleberry:BAAALgAECgUJBQAAAA==.Bloodfurry:BAAALgAECgMJAQAAAA==.Bluè:BAABLgAECn8ZAAMBAAgJ+BTlLQB9AQABAAgJ+BTlLQB9AQACAAUJjBrWSQB6AQAAAA==.',
Bn='Bnakka:BAAALgAECgYJBgABLgAECgcJFQANAOgXAA==.',
Bo='Bobdaunicorn:BAAALgAECgEJAQAAAA==.Boltz:BAAALgAECgMJAwAAAA==.Bombalaharis:BAAALgAECgcJDQAAAA==.',
Br='Brekke:BAACLgAFFH8KAAINAAQJVQ1HSAAOAQANAAQJVQ1HSAAOAQAuAAQKfy8AAg0ACQlgGLExAC8CAA0ACQlgGLExAC8CAAAA.Brokenbow:BAACLgAFFH8GAAMOAAQJXwj4HwDEAAAOAAMJ2wT4HwDEAAALAAEJ7BJSkwBJAAAuAAQKfxsAAw4ACQmmE0AdAK4BAA4ACQnNDkAdAK4BAAsABAkIGMV9AO4AAAAA.',
Bu='Bullshaft:BAAALgAECgEJAQAAAA==.Buntz:BAABLgAECn8qAAINAAkJgCMNCwAFAwANAAkJgCMNCwAFAwAAAA==.Bushmethsin:BAACLgAFFH8ZAAIPAAYJcyM3CABbAgAPAAYJcyM3CABbAgAuAAQKfxUAAg8ACAlVIg0eAE4CAA8ACAlVIg0eAE4CAAAA.Buttery:BAAALgAECgcJEQAAAA==.',
Bz='Bz:BAAALgADCgcJBwAAAA==.',
Ca='Cabb:BAABLgAECn8VAAMGAAYJihY8RAArAQAGAAQJGxo8RAArAQAHAAYJyQUQMwCiAAAAAA==.',
Ce='Ceedubble:BAAALgAECgkJDgAAAA==.Celestine:BAAALgADCgYJBgABLgAECgkJKAAQAEsOAA==.',
Ch='Charmanderz:BAABLgAECn8mAAMRAAgJIxHEFAB2AQARAAgJIxHEFAB2AQASAAEJIhWjOwA/AAAAAA==.Cherchlglsia:BAAALgADCgQJCAAAAA==.Chewsdee:BAAALgAECgQJBAAAAA==.Christlovesu:BAAALgAECgIJAgAAAA==.Chuckrules:BAAALgADCgcJDgAAAA==.',
Cl='Clackshi:BAAALgAECgYJCgAAAA==.',
Cr='Critable:BAABLgAECn8xAAMTAAkJaxWIGgAlAgATAAkJaxWIGgAlAgANAAgJNggXggB2AQAAAA==.',
Cu='Curst:BAAALgAECggJEwAAAA==.',
Da='Dagares:BAAALgADCggJDQAAAA==.Dahnte:BAAALgAECgEJAQAAAA==.',
De='Dechala:BAABLgAECn8oAAIQAAkJSw59TwCLAQAQAAkJSw59TwCLAQAAAA==.Deezknights:BAACLgAFFH8TAAMUAAcJ/x8oGAD7AQAUAAcJ/x8oGAD7AQAEAAEJAABNUAAAAAAuAAQKfycAAhQACQkGJU4JAFIDABQACQkGJU4JAFIDAAAA.Deezpuffs:BAABLgAFFH8KAAMVAAQJOxXDKAASAQAVAAQJOxXDKAASAQARAAEJpQDOLQAiAAABLgAFFAcJEwAUAP8fAA==.Deezrage:BAAALgADCgYJBgAAAA==.Derailed:BAAALgADCgEJAgAAAA==.Dergon:BAACLgAFFH8FAAIJAAMJNw38cgDOAAAJAAMJNw38cgDOAAAuAAQKfykAAgkACQloHPkhAFQCAAkACQloHPkhAFQCAAAA.Destiria:BAABLgAECn8kAAMJAAgJuBnZPQDfAQAJAAgJuBnZPQDfAQAWAAMJegd5JwBUAAAAAA==.Devistatorxx:BAAALgAECgYJCgAAAA==.',
Do='Doggyystyle:BAAALgAECgEJAQAAAA==.Donaldpump:BAAALgAECgYJBwAAAA==.Doomedturtle:BAAALgAECgMJBAAAAA==.Doublekill:BAAALgAECgUJDAAAAA==.',
Du='Duergan:BAACLgAFFH8OAAIXAAQJ6xBcFgAJAQAXAAQJ6xBcFgAJAQAuAAQKfykABBcACQkDEpkpAGEBABcACAkTFJkpAGEBABgACAnEBYs2ABsBAAMAAQlFAwRyACEAAAAA.',
['Dà']='Dàrkblade:BAAALgAECgIJAwAAAA==.',
Ea='Eatz:BAAALgADCgYJBgAAAA==.',
Eh='Ehcks:BAAALgAECgQJBAAAAA==.',
Em='Emotionaldmg:BAAALgADCgYJCwAAAA==.',
Fa='Faelyn:BAAALgADCgEJBAAAAA==.Fansy:BAAALgAECgEJAQAAAA==.',
Fe='Felwind:BAAALgAECgcJEQAAAA==.',
Fi='Fillycheese:BAAALgAECgEJAQAAAA==.',
Fl='Fleurelle:BAAALgAECgIJAgAAAA==.',
Fr='Frollo:BAAALgAECgEJAQAAAA==.Frosstitute:BAAALgAECgMJAwAAAA==.',
Fu='Furfiend:BAACLgAFFH8FAAIUAAIJUhWIswCjAAAUAAIJUhWIswCjAAAuAAQKfykAAxQACQndH10oAFgCABQACQlaHl0oAFgCAAQABQk4G5smABQBAAAA.',
Gi='Giantdog:BAAALgAECgUJBQAAAA==.Gilraen:BAACLgAFFH8JAAMGAAMJew9iMgDTAAAGAAMJSg1iMgDTAAAFAAEJXQ+ZPAA+AAAuAAQKfz0AAwUACQk3GZcMABICAAUACQn5FpcMABICAAYACQknE0wmAL8BAAAA.Gingerjen:BAAALgAECggJEgAAAA==.',
Go='Gorgrand:BAAALgAECgcJBwAAAA==.Gothbiotch:BAAALgAECgMJAwAAAA==.',
Gr='Greggnog:BAAALgAECgkJDAAAAA==.Greggy:BAAALgAECgUJCQABLgAECgkJDAAMAAAAAA==.Grenache:BAAALgAECgMJBAAAAA==.',
Ha='Hairypotter:BAAALgADCgIJAgAAAA==.Halfworld:BAAALgADCgYJBgAAAA==.Happydaze:BAABLgAECn8oAAMEAAkJ1xrVDwAAAgAEAAkJiRrVDwAAAgAUAAIJ2ReB7gChAAAAAA==.Haxthedk:BAAALgAECgEJAQAAAA==.Haxthedruid:BAAALgAECgEJAQAAAA==.Haxthemonk:BAAALgAECgEJAQAAAA==.',
He='Hemotoxin:BAAALgAECgMJAwAAAA==.Hendel:BAAALgAECgQJBgAAAA==.Herkaferk:BAAALgAECgYJEwAAAA==.',
Ho='Hojx:BAAALgAECgEJAQAAAA==.',
Hr='Hrolf:BAABLgAECn8jAAIZAAgJVRDUHQBLAQAZAAgJVRDUHQBLAQABLgAFFAQJDgAXAOsQAA==.',
Il='Illiannà:BAAALgAECggJEgABLgAECggJJgARACMRAA==.Illidont:BAABLgAECn8WAAIaAAkJWRDgGQCgAQAaAAkJWRDgGQCgAQAAAA==.Illijr:BAABLgAECn8cAAIaAAkJ1BP1EwDkAQAaAAkJ1BP1EwDkAQAAAA==.',
It='Ithil:BAAALgADCgkJDwAAAA==.',
Ja='Jaemison:BAAALgADCgQJAwAAAA==.',
Ji='Jicks:BAABLgAECn8gAAIbAAcJpAkuNgAuAQAbAAcJpAkuNgAuAQAAAA==.',
Jk='Jkass:BAABLgAECn8bAAIcAAgJ/hZOGgC3AQAcAAgJ/hZOGgC3AQAAAA==.',
Ju='Judgementdày:BAAALgAECggJCgAAAA==.',
['Jà']='Jàk:BAAALgAECgIJAgAAAA==.',
Ka='Kamaeria:BAACLgAFFH8JAAIdAAMJRwIoKQCUAAAdAAMJRwIoKQCUAAAuAAQKfzEAAh0ACQndEWAaAOwBAB0ACQndEWAaAOwBAAEuAAUUBAkIAAsArAQA.Kaíros:BAAALgADCgMJAwAAAA==.',
Kh='Khaotica:BAAALgADCgkJCQAAAA==.',
Ki='Kiandara:BAACLgAFFH8aAAMGAAUJrhmuGQA9AQAGAAUJrhmuGQA9AQAFAAQJwRJjFwASAQAuAAQKfyQAAwYACQmQHPIMAO4CAAYACQmQHPIMAO4CAAcABQkcG94dAFcBAAAA.Kikkoman:BAABLgAFFH8FAAIcAAMJmBmcIAAIAQAcAAMJmBmcIAAIAQAAAA==.Kilmas:BAAALgAECgIJAgAAAA==.Kirant:BAAALgADCggJDQAAAA==.Kirara:BAAALgADCgYJBgAAAA==.',
Ko='Kooz:BAAALgADCgUJBQAAAA==.Kooze:BAAALgADCgUJCAAAAA==.Koozo:BAAALgADCgMJAwAAAA==.',
Kt='Kt:BAABLgAECn8aAAIIAAcJNhN7kwBLAQAIAAcJNhN7kwBLAQAAAA==.',
Ku='Kush:BAAALgADCgEJAQABLgAECgkJKgANAIAjAA==.',
Ky='Kynrath:BAAALgAECgYJCQAAAA==.',
La='Laurie:BAAALgADCgMJBgAAAA==.Lava:BAAALgADCgUJBQABLgAECggJDwAMAAAAAA==.Lavablast:BAAALgADCgYJCwAAAA==.',
Le='Lelanie:BAAALgADCggJDgAAAA==.',
Li='Lichnfamous:BAABLgAECn8iAAIUAAgJsxTAUADKAQAUAAgJsxTAUADKAQAAAA==.Lightfrost:BAAALgADCgIJAgAAAA==.Lightning:BAAALgAECgUJCAAAAA==.Likkan:BAAALgAECgEJAQAAAA==.Lilithdawn:BAABLgAECn8hAAIeAAkJvhumDwBgAgAeAAkJvhumDwBgAgAAAA==.',
Lo='Lockwar:BAABLgAECn8aAAQWAAcJrRbTCQCzAQAWAAcJrRbTCQCzAQAJAAQJFAdW3QCWAAAKAAEJTwCTRQAFAAAAAA==.Louvre:BAABLgAECn8uAAIcAAkJtxyNCACTAgAcAAkJtxyNCACTAgAAAA==.',
Lu='Lukarian:BAABLgAFFH8GAAINAAMJiw6GZQDSAAANAAMJiw6GZQDSAAAAAA==.',
Ma='Makthra:BAAALgAECgUJEQAAAA==.Marek:BAAALgADCgUJCAAAAA==.Marionette:BAAALgADCggJGQAAAA==.Mawseeker:BAAALgADCgEJAQAAAA==.',
Me='Megabettegaa:BAACLgAFFH8KAAIUAAMJGRYshQDrAAAUAAMJGRYshQDrAAAuAAQKf3UAAhQACQlsGKApAFICABQACQlsGKApAFICAAAA.Mennathil:BAAALgADCgEJAQAAAA==.Meric:BAAALgAECgEJAQAAAA==.',
Mi='Microbrew:BAAALgAECgcJCQABLgAECgkJNQAZAHEbAA==.Midnight:BAAALgAECgcJCQAAAA==.Milo:BAAALgAFFAEJAQAAAA==.Miniangel:BAACLgAFFH8PAAMeAAUJjxQMDQBjAQAeAAUJjxQMDQBjAQAdAAIJfQEUMgBXAAAuAAQKfx4AAx4ACQl8FfMTACwCAB4ACQl8FfMTACwCAB0ACAk+EPAoAJMBAAAA.Mixednuts:BAAALgAECgIJAgAAAA==.',
Mo='Molasses:BAACLgAFFH8SAAIIAAQJHg8PXAAnAQAIAAQJHg8PXAAnAQAuAAQKfz0AAggACQnTHo8VANECAAgACQnTHo8VANECAAAA.Moof:BAAALgAECgEJAQAAAA==.',
['Mú']='Músic:BAAALgAECgIJAgAAAA==.',
Na='Najitar:BAAALgAECgQJBQAAAA==.Nazaibrew:BAAALgAECggJCwABLgAECgkJMgAbAIgeAA==.Nazera:BAAALgAECgEJAQAAAA==.',
Ne='Necromalus:BAAALgAECgEJAgAAAA==.Neerx:BAAALgADCgUJBQAAAA==.',
Nu='Nubkselk:BAABLgAECn8zAAIQAAkJ7x28FACTAgAQAAkJ7x28FACTAgAAAA==.Nurishment:BAACLgAFFH8cAAIPAAgJAhQ8CQBIAgAPAAgJAhQ8CQBIAgAuAAQKfyUAAg8ACQn7HWwSAKICAA8ACQn7HWwSAKICAAAA.',
Ny='Nyrr:BAAALgADCgEJAgAAAA==.',
Og='Ogmurka:BAAALgAECgEJAQAAAA==.',
On='Oni:BAAALgADCgUJBQAAAA==.Onitachi:BAABLgAECn8rAAMBAAgJzxFUQgAaAQABAAgJzxFUQgAaAQAfAAQJcAlqKgCJAAAAAA==.',
Op='Optistriker:BAABLgAECn9LAAIPAAkJaxkkFAChAgAPAAkJaxkkFAChAgAAAA==.',
Oy='Oythsar:BAAALgADCgQJBAAAAA==.',
Pa='Painfree:BAAALgADCgQJBAAAAA==.Papabear:BAAALgAECgEJAQAAAA==.',
Pe='Pemburumalam:BAAALgADCgEJAQAAAA==.',
Pi='Pig:BAABLgAECn8cAAIGAAgJKhjaKwAGAgAGAAgJKhjaKwAGAgABLgAECgkJKgANAIAjAA==.Pinks:BAAALgADCgkJCQAAAA==.Pizlex:BAAALgAECgMJAwAAAA==.',
Po='Poplockndrop:BAAALgAECgUJBgAAAA==.Portion:BAABLgAECn8uAAIIAAgJWhzAUwDbAQAIAAgJWhzAUwDbAQAAAA==.Portlybob:BAAALgADCgEJAQAAAA==.',
Pr='Pretentious:BAABLgAECn8eAAINAAgJoh8rJgCOAgANAAgJoh8rJgCOAgAAAA==.Prettyfun:BAAALgADCgUJBQAAAA==.Prettysavage:BAAALgAECgIJAgAAAA==.Primo:BAAALgADCgYJEQAAAA==.',
['Pè']='Pèrsephônè:BAAALgADCgIJAgAAAA==.',
Ra='Radicalism:BAAALgAECgQJBQAAAA==.Raechan:BAAALgAECgEJAQAAAA==.Ranigard:BAAALgAECgUJCAAAAA==.Rantioc:BAAALgAECgUJBQAAAA==.Raugan:BAAALgAECgEJAQAAAA==.',
Re='Reparations:BAABLgAECn8XAAMdAAgJewUlRAD2AAAdAAgJewUlRAD2AAAbAAMJxQFabAA+AAAAAA==.Repentofsin:BAAALgAECgQJBAAAAA==.Rexbriefs:BAABLgAECn8dAAIUAAcJZAv1lgAxAQAUAAcJZAv1lgAxAQAAAA==.',
Ri='Rice:BAAALgAECgYJDQAAAA==.Riptong:BAAALgADCgEJAQAAAA==.',
Ro='Rovinj:BAAALgAECgkJBwAAAA==.',
Ru='Rumi:BAABLgAECn8iAAIQAAgJUxaGPADJAQAQAAgJUxaGPADJAQAAAA==.',
Ry='Rydle:BAAALgAFFAMJBAAAAA==.',
Sa='Samedhi:BAAALgAECgQJBQAAAA==.Sanlesh:BAAALgADCgUJBgAAAA==.Sapodillà:BAAALgAECggJDQAAAA==.Sarijevo:BAAALgAECgkJBQAAAA==.Saurax:BAAALgAECgEJAgAAAA==.',
Sc='Scatz:BAAALgADCgIJAgAAAA==.Scott:BAAALgAECgcJCwAAAA==.Scylla:BAAALgAECgYJDwAAAA==.',
Se='Sevrin:BAACLgAFFH8NAAIcAAQJBSC/EABzAQAcAAQJBSC/EABzAQAuAAQKfywAAhwACQkaIwAFAN0CABwACQkaIwAFAN0CAAAA.',
Sh='Shadowfuryy:BAAALgAECgUJBQAAAA==.Shalati:BAAALgADCgYJBgAAAA==.Sharts:BAAALgADCgYJBwAAAA==.Shestrouble:BAACLgAFFH8GAAIIAAIJyhsVjQCnAAAIAAIJyhsVjQCnAAAuAAQKfxoAAggACQk7IKkTAN4CAAgACQk7IKkTAN4CAAAA.Shirerat:BAAALgADCgMJBAAAAA==.Shtzson:BAABLgAECn8WAAIYAAkJ5xeYDwA6AgAYAAkJ5xeYDwA6AgAAAA==.Shyjinx:BAAALgAECgYJBgAAAA==.Shíft:BAAALgAECgUJBQABLgAFFAMJBgAcAOsaAA==.Shííft:BAAALgAECgUJBQABLgAFFAMJBgAcAOsaAA==.Shîft:BAACLgAFFH8GAAIcAAMJ6xrBHwARAQAcAAMJ6xrBHwARAQAuAAQKfzEAAxwACQnQI/MFAMgCABwACAnPI/MFAMgCACAAAwkgHyUSAPgAAAAA.',
Si='Siiwwy:BAAALgAECgMJAwAAAA==.',
Sl='Slice:BAAALgAECgYJEQAAAA==.',
Sn='Snugglemuff:BAAALgAECgcJDQABLgAECgkJHgANAKIfAA==.',
So='Sok:BAAALgAECgEJAgAAAA==.Soladin:BAAALgAECgQJBQABLgAECgkJNQAZAHEbAA==.Solicide:BAABLgAECn81AAUZAAkJcRsaDgDwAQAZAAgJ4hgaDgDwAQAhAAcJ8RvrCwDoAQAPAAEJRBMbyAA6AAAiAAEJ2g5ahwAxAAAAAA==.Solthicc:BAAALgAECggJDQAAAA==.Sonarra:BAAALgAECgYJBgAAAA==.',
Sp='Sparkle:BAACLgAFFH8cAAIVAAcJMw+DHgBOAQAVAAcJMw+DHgBOAQAuAAQKf28AAhUACQmYJGQCAFUDABUACQmYJGQCAFUDAAAA.Splatacular:BAAALgADCgEJAQAAAA==.',
St='Stolenhearth:BAABLgAECn8pAAIGAAYJVwxkVQDsAAAGAAYJVwxkVQDsAAAAAA==.',
Sv='Svets:BAABLgAECn8yAAMbAAkJiB5JCADnAgAbAAkJiB5JCADnAgAeAAEJ3AnKhQArAAAAAA==.',
Sw='Swavey:BAAALgADCgQJBAAAAA==.',
Sy='Sylphrenna:BAAALgAECgQJBAAAAA==.Syrana:BAAALgADCgEJAQAAAA==.',
Te='Teeanna:BAAALgAECgIJAgABLgAECgIJAwAMAAAAAA==.Temaile:BAAALgADCgEJBAAAAA==.Tenin:BAAALgADCgEJAQAAAA==.',
Th='Thinmint:BAAALgADCgEJAQAAAA==.',
Ti='Tinnman:BAAALgADCgYJBgAAAA==.',
To='Toughguytony:BAAALgADCgUJBgAAAA==.',
Tr='Trebekk:BAAALgADCgEJAQAAAA==.Treydk:BAACLgAFFH8NAAIUAAQJWh1LQQBgAQAUAAQJWh1LQQBgAQAuAAQKfxwAAxQACQm/HUsXALMCABQACQl2HUsXALMCACMABQkYHHoXAAsBAAAA.Trreyy:BAABLgAECn8fAAINAAgJqh5YKACEAgANAAgJqh5YKACEAgAAAA==.',
Ts='Tsimfuqis:BAABLgAFFH8JAAIcAAQJMhLQGgA1AQAcAAQJMhLQGgA1AQAAAA==.',
Tw='Twighumper:BAAALgAECgMJBQABLgAECgkJFgAYAOcXAA==.Twizzy:BAACLgAFFH8IAAILAAQJrAQ3VwDjAAALAAQJrAQ3VwDjAAAuAAQKf0IAAgsACQnyFM8kAEMCAAsACQnyFM8kAEMCAAAA.',
Ty='Tyranhikar:BAAALgADCgEJAQAAAA==.',
Tz='Tzechan:BAACLgAFFH8GAAITAAMJ8RoHJAD0AAATAAMJ8RoHJAD0AAAuAAQKfx8AAxMACQkiGxIcABgCABMACQkiGxIcABgCAA0AAgmcEkMuAW4AAAAA.',
Ug='Uggalee:BAAALgAFFAIJAwAAAA==.',
Va='Valtirya:BAAALgAECgQJBgAAAA==.Vampirellaa:BAAALgADCgcJBgAAAA==.Vayzen:BAABLgAECn8YAAIVAAcJDB4uEwBNAgAVAAcJDB4uEwBNAgAAAA==.',
Vi='Virexus:BAAALgADCgIJAgAAAA==.',
Vo='Voidfree:BAABLgAECn8iAAIQAAgJiwnUcwAtAQAQAAgJiwnUcwAtAQAAAA==.',
Vy='Vynarc:BAABLgAECn8qAAINAAgJihHPZQC1AQANAAgJihHPZQC1AQAAAA==.',
Wa='Warcrimes:BAAALgAECgEJAQAAAA==.Watervendor:BAABLgAECn8vAAIIAAkJgBvYLABfAgAIAAkJgBvYLABfAgAAAA==.',
We='Wearegroot:BAAALgAECgEJAQAAAA==.Webedeadiy:BAAALgADCgEJAQAAAA==.',
Wi='Wiggimbottom:BAAALgAECgYJEgAAAA==.Wihtè:BAAALgAECgMJAwAAAA==.Willscarlet:BAAALgADCgQJBAAAAA==.',
Wo='Wolffoxfangs:BAABLgAECn8VAAILAAcJ/BW7YAB4AQALAAcJ/BW7YAB4AQAAAA==.',
['Wá']='Wárpaiint:BAABLgAECn8jAAIkAAcJoQtBFgD4AAAkAAcJoQtBFgD4AAABLgAFFAMJBQAIAGIEAA==.',
Xa='Xalatoes:BAAALgAECgUJBQAAAA==.',
Xe='Xeados:BAAALgAECgIJAgAAAA==.',
Yi='Yin:BAAALgADCgcJDQAAAA==.',
['Yè']='Yèlloow:BAAALgAECgMJBQAAAA==.',
Za='Zaquel:BAAALgAECgcJEgAAAA==.Zarcissa:BAAALgAECgYJDQAAAA==.Zavira:BAAALgADCgcJBwAAAA==.',
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
