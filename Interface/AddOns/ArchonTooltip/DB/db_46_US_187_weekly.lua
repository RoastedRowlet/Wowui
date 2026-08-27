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

local lookup = {'Mage-Frost','Hunter-BeastMastery','Hunter-Marksmanship','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Retribution','Paladin-Protection','Evoker-Augmentation','Paladin-Holy','Unknown-Unknown','Hunter-Survival','Warrior-Fury','Warrior-Protection','Shaman-Restoration','Shaman-Elemental','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','DeathKnight-Blood','Druid-Guardian','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Destruction','Warlock-Demonology','Evoker-Preservation','Rogue-Subtlety','Mage-Fire','Mage-Arcane','Rogue-Assassination','Priest-Holy','Priest-Discipline','Druid-Feral','Druid-Balance','Druid-Restoration','Priest-Shadow',}
local provider = {region='US',realm='Sentinels',name='US',type='weekly',zone=46,date='2026-08-25',data={Aa='Aandheeog:BAAALgAECggJEAAAAA==.',
Ab='Absqwas:BAAALgAECggJDAAAAA==.',
Ad='Adaina:BAACLgAFFH8OAAIBAAUJdgkhNwDpAAABAAUJdgkhNwDpAAAuAAQKfx8AAgEACQlyHEQEAJwCAAEACQlyHEQEAJwCAAAA.Adrax:BAAALgADCgcJDAAAAA==.Adronys:BAAALgADCgkJGgAAAA==.',
Ah='Aheeaheehahe:BAACLgAFFH8ZAAICAAUJ/xHQKwD0AAACAAUJ/xHQKwD0AAAuAAQKfzwAAwIACQkcHtQeAG0CAAIACQkcHtQeAG0CAAMAAwn5CDU4AD4AAAAA.',
Ai='Aiirsby:BAAALgAECgEJAwAAAA==.Ailanissa:BAAALgAECgkJEgAAAA==.Ailasaa:BAABLgAECn8dAAQEAAcJ7CJ6BwAOAgAEAAUJLSZ6BwAOAgAFAAcJjBbUHACWAQAGAAIJgxcJ3AB+AAABLgAFFAUJBwABAEUUAA==.Ailassa:BAABLgAFFH8HAAIBAAQJRRQtKgApAQABAAQJRRQtKgApAQAAAA==.',
Am='Ametiszt:BAAALgAECgkJAQAAAA==.',
An='Ananya:BAAALgADCgMJAwAAAA==.Anbraxas:BAAALgAECgcJDwAAAA==.Anixee:BAABLgAECn8eAAMHAAcJqBdDhwBhAQAHAAcJqBdDhwBhAQAIAAEJowMfWAAfAAAAAA==.',
Ao='Ao:BAAALgAECgYJBwAAAA==.',
Ar='Archon:BAAALgAECgEJAQAAAA==.Artax:BAAALgAECgYJDwAAAA==.',
As='Asdanot:BAABLgAECn8cAAIJAAkJ2xC+JQCxAQAJAAkJ2xC+JQCxAQAAAA==.Ashbahn:BAABLgAECn85AAMKAAkJsQvqOABpAQAKAAkJsQvqOABpAQAHAAcJbhGBnwA4AQAAAA==.Ashes:BAAALgAECgQJCQABLgAECgkJOQAKALELAA==.Ashmodai:BAAALgADCgQJBAAAAA==.Astovidatu:BAACLgAFFH8FAAIHAAMJDgXCQwCVAAAHAAMJDgXCQwCVAAAuAAQKfycAAgcACAntEo8WACkBAAcACAntEo8WACkBAAAA.',
At='Atkascha:BAAALgADCgEJAQAAAA==.',
Au='Aurimas:BAAALgADCgEJAQAAAA==.Auroranova:BAABLgAECn9IAAQHAAkJbhKsDwBzAQAHAAkJlBCsDwBzAQAIAAQJhBHnCwCiAAAKAAIJZwj4fgBOAAAAAA==.',
Ax='Axél:BAAALgAECgcJDgAAAA==.',
Az='Azlilar:BAAALgAECgEJAQABLgAECgQJCwALAAAAAA==.',
Ba='Baddragon:BAAALgAECgYJBgABLgAFFAgJHQAHACMUAA==.',
Be='Berringer:BAAALgAECgQJCwAAAA==.',
Bi='Bigbuns:BAAALgAECgQJBAAAAA==.',
Bl='Bluedreamm:BAAALgAECgQJCwAAAA==.',
Br='Braei:BAAALgAECgcJDwAAAA==.Brilleleante:BAAALgADCgkJMgAAAA==.Brochacho:BAAALgAECgcJBwAAAA==.Broxmorn:BAAALgAECgIJAgAAAA==.',
Ca='Cala:BAAALgAFFAMJBAABLgAFFAkJQAAMAP0kAA==.Canimai:BAACLgAFFH8NAAINAAMJagg6PgCxAAANAAMJagg6PgCxAAAuAAQKfzYAAw4ACQndHvYAAM0CAA4ACQndHvYAAM0CAA0ACQk1D4gwAIsBAAAA.Carla:BAAALgADCgkJEAAAAA==.',
Ce='Cemetery:BAAALgAECgkJCgAAAA==.',
Ch='Chudmeister:BAAALgAECgcJBgAAAA==.',
Co='Colin:BAAALgAECgQJCQABLgAFFAEJAQALAAAAAA==.Corneliastr:BAAALgAFFAcJBAAAAA==.',
Cr='Crazynaga:BAABLgAECn8VAAIGAAYJnwVXlgDwAAAGAAYJnwVXlgDwAAAAAA==.Crisspy:BAACLgAFFH8VAAMPAAUJNgzvQwDYAAAPAAQJPwzvQwDYAAAQAAUJBQm3LgDYAAAuAAQKfzYAAxAACQkAExUjAM0BABAACQkAExUjAM0BAA8AAgnVCFexAGYAAAAA.',
Cu='Cubes:BAACLgAFFH8vAAMRAAkJtSUiAAB2AwARAAkJtSUiAAB2AwASAAEJ5RIbXQBHAAAuAAQKfy8ABBEACQnzJRYBALgDABEACQnzJRYBALgDABMABgnNGJotAKMBABIAAwk/DlCFAJMAAAAA.Cutebunny:BAAALgADCgYJBgAAAA==.',
Da='Daisyspark:BAAALgAECgEJBAAAAA==.',
De='Deadlylight:BAAALgAECgEJAQAAAA==.Deathcrocker:BAECLgAFFH8gAAIUAAgJnCJLAACGAgAUAAgJnCJLAACGAgAuAAQKfxoAAhQACQkDJmwAAMsDABQACQkDJmwAAMsDAAEuAAUUCQkYABUA/R0A.Decksey:BAAALgADCgEJAQABLgADCgYJCQALAAAAAA==.Decksters:BAAALgADCgYJCQAAAA==.',
Di='Divinebeef:BAABLgAECn8WAAIHAAgJBBcmTQD7AQAHAAgJBBcmTQD7AQABLgAFFAgJHQAHACMUAA==.',
Do='Dogs:BAACLgAFFH8RAAINAAcJiBv8EAB+AQANAAcJiBv8EAB+AQAuAAQKfxsAAg0ACAnrG9cNAOYCAA0ACAnrG9cNAOYCAAEuAAUUCAkZAAIA8R0A.Domar:BAABLgAECn8UAAIQAAcJSxMrOABXAQAQAAcJSxMrOABXAQAAAA==.Doomslayer:BAABLgAECn8lAAQWAAkJ7BruUQDOAQAWAAkJ7BruUQDOAQAUAAUJgAL3MwCgAAAXAAEJUgp8PwAoAAAAAA==.Doraei:BAABLgAECn8VAAIWAAgJmw5qewBsAQAWAAgJmw5qewBsAQAAAA==.Dothippo:BAABLgAECn8qAAMYAAcJthutCADBAQAYAAcJthutCADBAQAZAAEJFgR1KAEpAAAAAA==.',
Dp='Dpn:BAAALgAECgIJAgABLgAFFAcJAgALAAAAAA==.',
Dr='Drachunter:BAAALgADCgMJAwAAAA==.Drutastic:BAAALgAECgIJAgAAAA==.',
Du='Dumach:BAAALgADCgYJDAAAAA==.Dunk:BAABLgAECn8lAAMHAAkJSRfbXwCxAQAHAAkJSRfbXwCxAQAKAAMJIg1OaACUAAAAAA==.',
Ea='Easy:BAAALgAECgUJCAABLgAECgYJBgALAAAAAA==.',
Ec='Eclipsus:BAAALgADCgcJCAABLgAFFAMJAwALAAAAAA==.',
Ed='Edamen:BAAALgAECgUJBQAAAA==.',
Eh='Ehrathorn:BAAALgAECgMJAwAAAA==.',
El='Elennoxx:BAAALgAECgEJAgAAAA==.Elf:BAAALgADCgUJBQAAAA==.Elijah:BAAALgAECgYJBgAAAA==.Elonaara:BAAALgADCgcJBwAAAA==.Elunëth:BAAALgADCgQJBAABLgAFFAYJHgAaAGsgAA==.',
Ep='Ephie:BAAALgADCgcJBwAAAA==.',
Et='Ether:BAAALgAECgMJBQAAAA==.',
Ex='Exarchstrike:BAAALgAECgUJBQAAAA==.',
Fa='Faedryl:BAAALgADCgQJBAAAAA==.Fandrin:BAAALgADCgUJBQAAAA==.Farg:BAAALgAECgEJAQAAAA==.Farslaw:BAAALgAECgQJBQAAAA==.',
Fe='Feledara:BAABLgAECn8tAAINAAkJrxEnJADTAQANAAkJrxEnJADTAQAAAA==.Felshort:BAAALgAECgEJAQABLgAFFAYJIAASAD8dAA==.',
Fi='Fionaweaver:BAAALgADCgIJAgAAAA==.',
Fo='Foebane:BAAALgAECgYJEAABLgAECgYJGwAbADwjAA==.',
Fr='Freezing:BAAALgAECgEJAwAAAA==.Frieren:BAACLgAFFH8aAAMBAAkJUxeFCgDLAQABAAgJ4ReFCgDLAQAcAAMJphzUAwDEAAAuAAQKfyUABAEACQl9Il0NAFoDAAEACQl9Il0NAFoDABwAAQnTIAcNAFkAAB0AAQkbDx0aAEcAAAAA.Froslass:BAABLgAECn8ZAAIWAAgJfx1dSgDjAQAWAAgJfx1dSgDjAQAAAA==.',
Fu='Funk:BAAALgAECgEJAQAAAA==.',
Ge='Gencrocker:BAEBLgAFFH8OAAIIAAgJxByZAABpAgAIAAgJxByZAABpAgABLgAFFAkJGAAVAP0dAA==.Getoffenris:BAABLgAFFH8HAAINAAQJiBJhNwDVAAANAAQJiBJhNwDVAAAAAA==.',
Gl='Gloryhammer:BAABLgAECn8mAAQIAAkJHBuNCABPAgAIAAkJHBuNCABPAgAKAAYJogfGawDLAAAHAAEJaxmmQwEzAAAAAA==.',
Go='Gobbs:BAABLgAECn8jAAMbAAkJqBpYAwCzAQAbAAkJ/hlYAwCzAQAeAAYJ4g+JCwBzAQAAAA==.',
Gr='Grandma:BAAALgAECgEJAQAAAA==.Grimmi:BAAALgAECgEJAQAAAA==.',
Ha='Haldrian:BAAALgAECgcJEQAAAA==.Havack:BAAALgADCgEJAQAAAA==.',
He='Healslvt:BAAALgAECgEJAQAAAA==.Hexkittin:BAABLgAECn8bAAIPAAcJVRTvVQBeAQAPAAcJVRTvVQBeAQAAAA==.',
Hi='Hixon:BAAALgADCgMJAgAAAA==.',
Ho='Holyhota:BAACLgAFFH8JAAMfAAQJyRimCgC6AAAfAAMJMB2mCgC6AAAgAAMJQwr7OgCVAAAuAAQKfxcAAx8ACAk7IdELAJMCAB8ACAk7IdELAJMCACAAAQmED+N7ADAAAAAA.Hop:BAACLgAFFH8OAAIhAAMJ3BiQBwC2AAAhAAMJ3BiQBwC2AAAuAAQKfzgAAiEACQkPHHIGAIACACEACQkPHHIGAIACAAAA.Hota:BAAALgAECgYJBwABLgAFFAQJCQAfAMkYAA==.Hotamnk:BAAALgAFFAIJAwABLgAFFAQJCQAfAMkYAA==.Hozdis:BAAALgAECgEJAgAAAA==.',
If='Iffri:BAAALgADCgEJAQAAAA==.',
Il='Ilos:BAAALgADCgEJAQAAAA==.',
In='Inarius:BAAALgAECgEJAQAAAA==.',
Ir='Iraedies:BAAALgADCgEJAgAAAA==.Ironborn:BAAALgAFFAMJAwAAAA==.',
Iv='Ivakor:BAAALgAECgcJEwAAAA==.Ivyy:BAACLgAFFH8YAAIiAAYJiyGwDADRAQAiAAYJiyGwDADRAQAuAAQKfxcAAiIACAkSIrkNAMACACIACAkSIrkNAMACAAEuAAUUCQlCABsAFBsA.',
Ja='Jackswagz:BAABLgAECn8pAAMPAAkJHhTaOgDDAQAPAAkJHhTaOgDDAQAQAAQJbAd7cgCUAAAAAA==.Jakol:BAAALgADCgkJGQAAAA==.Jaszuny:BAABLgAECn80AAIEAAkJUhniBQBAAgAEAAkJUhniBQBAAgAAAA==.',
Je='Jezlyn:BAAALgAECgUJBQAAAA==.',
Jo='Johyah:BAABLgAFFH8MAAISAAYJ2RjlCgDkAQASAAYJ2RjlCgDkAQAAAA==.',
['Jö']='Jösîah:BAAALgAECgMJAwAAAA==.',
Ka='Kaladyn:BAAALgADCgIJAwABLgAECgkJGAAXAIwbAA==.Kalisandra:BAAALgAECgQJBAAAAA==.Kasho:BAAALgAECgIJAgAAAA==.Katrixi:BAAALgAECgUJBQAAAA==.Katsumotosan:BAAALgADCggJDQAAAA==.',
Ke='Kev:BAABLgAECn8qAAQBAAcJ6iSFNQBDAgABAAcJ6iSFNQBDAgAdAAIJMiTbDwDEAAAcAAEJAAA8EgAXAAAAAA==.Kevlarr:BAAALgADCgcJBwAAAA==.',
Ko='Kombatgodess:BAAALgAECgIJAgAAAA==.',
Kr='Krahne:BAAALgAECgMJAwAAAA==.',
Ku='Kurgen:BAAALgADCgUJCgAAAA==.',
Kv='Kvasir:BAABLgAECn9SAAIWAAkJex6fBABnAgAWAAkJex6fBABnAgAAAA==.',
Ky='Kynolight:BAAALgAECgQJAwAAAA==.',
['Kâ']='Kânna:BAAALgAECgQJBQAAAA==.',
['Kú']='Kúrorn:BAAALgAECggJCQABLgAECgEJAgALAAAAAA==.',
La='Lalaise:BAAALgAECgMJAwAAAA==.Lalasmira:BAAALgAECgEJAQAAAA==.Lanaria:BAAALgAECgMJAwAAAA==.Lancayne:BAAALgADCgIJAQAAAA==.',
Li='Lichkingstoy:BAACLgAFFH8dAAIHAAgJIxSiHgCNAQAHAAgJIxSiHgCNAQAuAAQKfyEAAgcACQniHdoxAFsCAAcACQniHdoxAFsCAAAA.Lieb:BAAALgAECgkJBQAAAA==.Lihrna:BAAALgAECgUJBgAAAA==.Littlecutie:BAAALgADCgMJAwAAAA==.',
Ll='Llilth:BAAALgADCgMJBAAAAA==.',
Lo='Lolamarie:BAAALgADCgQJCQAAAA==.',
Lu='Lunareclipse:BAAALgAECgIJAgAAAA==.Luniaira:BAAALgAECggJDgAAAA==.Lushara:BAAALgAECgEJAQAAAA==.',
Ma='Maedy:BAAALgADCgQJBAABLgAFFAQJEwAJAAsGAA==.Maegii:BAAALgADCgEJAQAAAA==.Manafist:BAAALgADCgMJAwABLgAECgYJGwAbADwjAA==.Manistas:BAAALgAECgEJAQAAAA==.Manta:BAABLgAECn8gAAMUAAgJKRW7JgAeAQAWAAcJXw5HjwBiAQAUAAUJjhy7JgAeAQAAAA==.Maroon:BAAALgAECggJEwAAAA==.',
Me='Menasor:BAAALgADCgQJBAAAAA==.',
Mi='Micaa:BAAALgAECgYJEAAAAA==.Minarielle:BAAALgADCgUJBQAAAA==.Mingó:BAAALgAECgUJBwAAAA==.Miracle:BAAALgAFFAMJBAAAAA==.Mirana:BAAALgADCgEJAQAAAA==.Mirzza:BAAALgAECgQJBQAAAA==.Mistake:BAAALgAECgYJEgAAAA==.Mistymiz:BAAALgAECgYJCAAAAA==.',
Mo='Mockra:BAAALgAECgQJBgAAAA==.Monkcrocker:BAECLgAFFH8VAAITAAcJeCRJAQDPAgATAAcJeCRJAQDPAgAuAAQKfxUAAhMABwnxJcANALcCABMABwnxJcANALcCAAEuAAUUCQkYABUA/R0A.',
Mv='Mvmx:BAAALgAECgIJAgAAAA==.',
['Mé']='Méthan:BAAALgADCgQJBAAAAA==.',
Na='Nabarke:BAAALgAECgcJCwAAAA==.Naturestrike:BAAALgAECgYJDQAAAA==.Naztherune:BAAALgADCgQJBQAAAA==.',
Ne='Nexaliah:BAAALgADCgkJCwABLgAFFAQJFAAKACAZAA==.',
Ni='Nier:BAAALgAECgUJCAAAAA==.Nightsilver:BAAALgADCgkJIwAAAA==.',
No='Noisemarine:BAAALgAECgQJBAAAAA==.Nooxi:BAAALgADCggJCAABLgAECggJDAALAAAAAA==.Nosidh:BAAALgAECgMJBAAAAA==.Nospheratus:BAAALgAFFAMJBAABLgAFFAYJEQAUAKcKAA==.Notsofresh:BAAALgADCgMJAwAAAA==.',
Nx='Nx:BAAALgAECgMJBgAAAA==.',
Ny='Nylianna:BAACLgAFFH8UAAMKAAQJIBl6DwAHAQAKAAMJYCB6DwAHAQAHAAMJThimZQDjAAAuAAQKf0QAAwcACQkYImkMACsDAAcACQkYImkMACsDAAoACQkjFocYAEMCAAAA.',
Oa='Oaken:BAAALgADCgkJDQAAAA==.',
Ob='Obscurity:BAACLgAFFH8NAAISAAYJWxz1CQD3AQASAAYJWxz1CQD3AQAuAAQKfxkAAxIACAlWH6geACQCABIABgnlIageACQCABEAAwk5F9oKANEAAAAA.',
Og='Ogganborn:BAABLgAECn8nAAICAAgJHx/WSwC+AQACAAgJHx/WSwC+AQAAAA==.',
Ol='Olovis:BAAALgAECgQJBAAAAA==.',
On='Oneira:BAAALgAECgQJBAAAAA==.',
Or='Orange:BAAALgAECgQJBQAAAA==.Orrark:BAAALgADCgEJAQAAAA==.',
Ph='Phatmyke:BAAALgADCgEJAQAAAA==.',
Pi='Pikal:BAABLgAECn8bAAIHAAcJ2hLjmgBAAQAHAAcJ2hLjmgBAAQAAAA==.',
Pr='Priestigory:BAABLgAECn8wAAMTAAkJgh10DABuAgATAAkJoRx0DABuAgARAAQJORLBbAB5AAAAAA==.',
Pv='Pvtcrocker:BAEBLgAFFH8YAAIVAAkJ/R0ZAQCqAgAVAAkJ/R0ZAQCqAgAAAA==.',
Py='Pyrithyr:BAABLgAECn8ZAAMIAAgJLxtTFACJAQAIAAUJbyJTFACJAQAHAAgJjBOifQBzAQABLgAFFAUJBwABAEUUAA==.',
Qu='Quelyne:BAAALgADCgMJAwAAAA==.Quink:BAAALgAECgMJAwABLgAECggJDAALAAAAAA==.Quintus:BAAALgAECgUJBgAAAA==.',
Ra='Raelyn:BAAALgAECgYJDgABLgAFFAMJDAAjAIgiAA==.Raevaela:BAAALgADCgQJBwABLgAECgcJFQARABkcAA==.Railiana:BAABLgAECn8kAAICAAkJaQnjeABOAQACAAkJaQnjeABOAQAAAA==.',
Re='Regrowth:BAABLgAECn9CAAUjAAkJaSLRBQBaAwAjAAkJaSLRBQBaAwAiAAIJqBzcWgCpAAAhAAQJNhjeDgBdAAAVAAIJ+BvPGwBKAAAAAA==.Reminesce:BAAALgADCgEJAQAAAA==.',
Rh='Rholune:BAAALgAECgUJDQAAAA==.',
Ro='Roberta:BAAALgADCgQJBgAAAA==.',
Rp='Rplooker:BAAALgADCgcJEgABLgAECgcJFgARAJwPAA==.',
Ru='Ruby:BAACLgAFFH8OAAIOAAgJNhkRAQD/AQAOAAgJNhkRAQD/AQAuAAQKfxwAAg4ACAmbJbUBAGgDAA4ACAmbJbUBAGgDAAAA.Ruhai:BAAALgAECgYJCwAAAA==.',
['Rà']='Ràistlin:BAABLgAECn8aAAIBAAYJNA4IxwD/AAABAAYJNA4IxwD/AAAAAA==.',
Sa='Saelki:BAAALgAECgMJAwAAAA==.',
Se='Secarium:BAAALgAECgEJAQAAAA==.Sephiran:BAABLgAECn88AAMkAAkJ4h9BDgByAgAkAAkJ4h9BDgByAgAgAAgJRxmsBQC+AQAAAA==.Seppuku:BAAALgAECgcJDQABLgAECgkJCgALAAAAAA==.',
Sh='Shaami:BAACLgAFFH8xAAMjAAkJahrCAQDxAgAjAAkJahrCAQDxAgAiAAUJlhMdEQAOAQAuAAQKfzIAAyMACQlCH+YLAOACACMACQlCH+YLAOACACIACAn6GEMrAKcBAAAA.Shagra:BAAALgAECgkJEwAAAA==.Shagraq:BAAALgADCgEJAQAAAA==.Shaomei:BAABLgAFFH8HAAICAAQJTAfcLwDlAAACAAQJTAfcLwDlAAABLgAFFAUJFAAEAA8dAA==.Shielen:BAABLgAECn8bAAIbAAYJPCNTFwDgAQAbAAYJPCNTFwDgAQAAAA==.Shoepert:BAABLgAECn84AAINAAkJbSWSBAAbAwANAAkJbSWSBAAbAwAAAA==.',
Si='Sib:BAABLgAFFH8IAAIGAAQJLRM+JQDxAAAGAAQJLRM+JQDxAAAAAA==.Sicario:BAAALgAECgIJAgAAAA==.Sifrina:BAAALgADCgEJAQAAAA==.Sini:BAAALgAECgcJBQAAAA==.Sinna:BAAALgAECgkJBwAAAA==.',
Sj='Sj:BAAALgADCgYJBgABLgAECgYJGwAbADwjAA==.',
So='Southpaw:BAAALgAECgIJAgAAAA==.',
Sq='Squiggles:BAAALgAECgIJAgAAAA==.',
St='Stdot:BAABLgAECn8dAAMWAAkJKBW9TgDWAQAWAAkJaRC9TgDWAQAUAAYJZhZEIwA5AQAAAA==.Stormstrike:BAAALgAECgkJEwAAAA==.',
Sw='Sway:BAAALgAECgUJBwABLgAECgYJBgALAAAAAA==.',
Ta='Tairn:BAAALgADCgQJBgAAAA==.Taluria:BAAALgAECgcJEAAAAA==.',
Te='Tempus:BAACLgAFFH8VAAIKAAUJ5BvgEgCZAQAKAAUJ5BvgEgCZAQAuAAQKfykABAoACQnEHKITAHICAAoACAk7HqITAHICAAgAAgndFGQ4AH0AAAcAAQn9CqyuASoAAAAA.Tenletters:BAAALgAFFAIJBAAAAA==.',
Th='That:BAAALgADCgYJBgAAAA==.Thrasius:BAAALgADCgYJBgAAAA==.',
Ti='Tibbey:BAAALgADCgcJBwAAAA==.Tikimon:BAAALgAECgEJAQAAAA==.Tinkernine:BAAALgAFFAIJAwAAAA==.',
To='Tobofrog:BAABLgAFFH8FAAIiAAUJ3g5wJgD6AAAiAAUJ3g5wJgD6AAAAAA==.Toboo:BAAALgAECgcJBgAAAA==.Tolocforu:BAAALgAECgQJBgAAAA==.',
Tr='Trainedtiger:BAAALgAFFAEJBAAAAA==.',
Ty='Tyrgrim:BAAALgAECgcJEAAAAA==.',
Uk='Ukio:BAABLgAECn8gAAQXAAkJmxgkAgDgAQAXAAcJqBokAgDgAQAUAAgJKhMCGwCFAQAWAAQJEhF5HADTAAAAAA==.',
Ul='Uldyssian:BAAALgAECgMJAwABLgAFFAQJFAAKACAZAA==.Ulfhednósh:BAAALgAECgIJAgAAAA==.',
Un='Union:BAAALgAECgEJAgAAAA==.Unwavering:BAAALgADCgEJAQAAAA==.',
Up='Uppies:BAAALgAECgQJCAAAAA==.',
Uw='Uwuforyou:BAABLgAECn8gAAQFAAgJIxQlHwCBAQAFAAgJIxQlHwCBAQAEAAUJpwxVHgCpAAAGAAEJ5wGZPgEXAAAAAA==.',
Va='Valalexis:BAAALgAECgEJAQAAAA==.',
Ve='Veedaddy:BAAALgADCgQJAwABLgAECgUJBQALAAAAAA==.Velawynn:BAACLgAFFH80AAMfAAkJSB92AAASAwAfAAkJSB92AAASAwAkAAMJpRS7EgDTAAAuAAQKfy4AAx8ACQm6HhsFAP8CAB8ACQm6HhsFAP8CACQABAlhDutYALEAAAAA.Velladonna:BAAALgAECgYJDAAAAA==.Veronica:BAACLgAFFH8aAAMWAAcJfh17FwAjAgAWAAYJPBl7FwAjAgAUAAYJKh8cBABvAQAuAAQKfx0AAxQACQlXI/ICABYDABQACQlXI/ICABYDABYABgn9GjV+AIcBAAEuAAUUCQk9ACQAtiIA.',
Vh='Vhenir:BAAALgADCgcJDQAAAA==.',
Vi='Vixa:BAAALgAECgQJBwAAAA==.',
Vo='Voidbro:BAAALgAECgMJBQAAAA==.Voidâge:BAACLgAFFH8iAAMBAAkJ1h0JDQA6AgABAAkJ1h0JDQA6AgAcAAIJ3QYOBQCKAAAuAAQKfyYAAxwACAlQId0DAMABAAEACAlGIfhWADQCABwABQlmId0DAMABAAAA.',
Vr='Vrag:BAAALgAECgEJAQAAAA==.',
Vy='Vynlordian:BAAALgAECgQJBgAAAA==.',
Wd='Wdfourty:BAAALgAECgEJAQAAAA==.',
Wy='Wyrdengilly:BAAALgADCgYJBgAAAA==.',
Xa='Xamot:BAABLgAECn8VAAIGAAgJNAwvbQBJAQAGAAgJNAwvbQBJAQABLgAFFAUJFgAJAJUVAA==.Xarou:BAAALgAECgQJBgAAAA==.',
Xe='Xenu:BAABLgAFFH8FAAIZAAMJzg7lNAC1AAAZAAMJzg7lNAC1AAABLgAFFAMJDAAZAHgQAA==.',
Xi='Xiuying:BAAALgADCgEJAQAAAA==.',
Xy='Xylanthria:BAAALgAFFAIJBAABLgAFFAQJFAAKACAZAA==.',
Ya='Yanyan:BAABLgAECn8aAAIRAAgJrA3ROgAWAQARAAgJrA3ROgAWAQAAAA==.',
Zi='Zilgius:BAABLgAECn8iAAMNAAcJJx0VCwAaAQAOAAYJ7h33GQBrAQANAAcJihoVCwAaAQABLgAECgkJPAAkAOIfAA==.Zinjari:BAAALgADCgEJAQAAAA==.',
Zl='Zlambo:BAAALgAECgMJBQABLgAFFAMJAwALAAAAAA==.',
Zy='Zynri:BAAALgADCgYJBwAAAA==.',
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
