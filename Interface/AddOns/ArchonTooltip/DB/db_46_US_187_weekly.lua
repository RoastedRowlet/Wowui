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

local lookup = {'Mage-Frost','Hunter-BeastMastery','Hunter-Marksmanship','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Retribution','Paladin-Protection','Evoker-Augmentation','Paladin-Holy','Unknown-Unknown','Warrior-Fury','Warrior-Protection','Shaman-Restoration','Shaman-Elemental','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Destruction','Warlock-Demonology','Evoker-Preservation','Rogue-Subtlety','Mage-Fire','Mage-Arcane','Rogue-Assassination','Priest-Holy','Priest-Discipline','Druid-Feral','Druid-Balance','Druid-Guardian','Druid-Restoration','Priest-Shadow',}
local provider = {region='US',realm='Sentinels',name='US',type='weekly',zone=46,date='2026-07-05',data={Aa='Aandheeog:BAAALgAECggJEAAAAA==.',
Ab='Absqwas:BAAALgAECgcJCwAAAA==.',
Ad='Adaina:BAABLgAFFH8FAAIBAAMJ3gKAOwCVAAABAAMJ3gKAOwCVAAAAAA==.Adrax:BAAALgADCgcJDAAAAA==.Adronys:BAAALgADCgkJGgAAAA==.',
Ah='Aheeaheehahe:BAACLgAFFH8WAAICAAUJKg82HAABAQACAAUJKg82HAABAQAuAAQKfzwAAwIACQkcHtQeAG0CAAIACQkcHtQeAG0CAAMAAwn5CDU4AD4AAAAA.',
Ai='Aiirsby:BAAALgAECgEJAgAAAA==.Ailanissa:BAAALgAECgQJCQAAAA==.Ailasaa:BAABLgAECn8dAAQEAAcJ7CJ6BwAOAgAEAAUJLSZ6BwAOAgAFAAcJjBbUHACWAQAGAAIJgxcJ3AB+AAABLgAFFAMJBAABAG8NAA==.Ailassa:BAABLgAFFH8EAAIBAAMJbw1eMADCAAABAAMJbw1eMADCAAAAAA==.',
Am='Ametiszt:BAAALgAECgkJAQAAAA==.',
An='Ananya:BAAALgADCgMJAwAAAA==.Anbraxas:BAAALgAECgcJDwAAAA==.Aneesa:BAABLgAECn8eAAMHAAcJqBdDhwBhAQAHAAcJqBdDhwBhAQAIAAEJowMfWAAfAAAAAA==.',
Ao='Ao:BAAALgAECgYJBwAAAA==.',
Ar='Artax:BAAALgAECgYJDwAAAA==.',
As='Asdanot:BAABLgAECn8cAAIJAAkJ2xC+JQCxAQAJAAkJ2xC+JQCxAQAAAA==.Ashbahn:BAABLgAECn85AAMKAAkJsQvqOABpAQAKAAkJsQvqOABpAQAHAAcJbhGBnwA4AQAAAA==.Ashes:BAAALgAECgQJCQABLgAECgkJOQAKALELAA==.Ashmodai:BAAALgADCgQJBAAAAA==.Astovidatu:BAABLgAECn8eAAIHAAgJtQ60FgC7AAAHAAgJtQ60FgC7AAAAAA==.',
At='Atkascha:BAAALgADCgEJAQAAAA==.',
Au='Aurimas:BAAALgADCgEJAQAAAA==.Auroranova:BAABLgAECn8/AAQHAAkJchE1ZQClAQAHAAkJPw81ZQClAQAIAAQJhBHYBQCsAAAKAAIJZwj4fgBOAAAAAA==.',
Ax='Axél:BAAALgAECgYJDQAAAA==.',
Az='Azlilar:BAAALgAECgEJAQABLgAECgQJCwALAAAAAA==.',
Ba='Baddragon:BAAALgAECgYJBgABLgAFFAgJGQAHAAQUAA==.',
Be='Berringer:BAAALgAECgQJCwAAAA==.',
Bi='Bigbuns:BAAALgAECgQJBAAAAA==.',
Bl='Bluedreamm:BAAALgAECgQJCgAAAA==.',
Br='Braei:BAAALgAECgcJDwAAAA==.Brilleleante:BAAALgADCgkJLwAAAA==.Brochacho:BAAALgAECgcJBwAAAA==.Broxmorn:BAAALgAECgEJAQAAAA==.',
Ca='Cala:BAAALgAFFAMJBAABLgAFFAgJIwADAFMeAA==.Canimai:BAACLgAFFH8NAAIMAAMJagg6PgCxAAAMAAMJagg6PgCxAAAuAAQKfygAAwwACQmBEYgwAIsBAAwACQkkD4gwAIsBAA0AAwmnEQlGAFoAAAAA.Carla:BAAALgADCgkJEAAAAA==.',
Ce='Cemetery:BAAALgAECgkJCgAAAA==.',
Ch='Chudmeister:BAAALgAECgcJBgAAAA==.',
Co='Colin:BAAALgAECgQJCQABLgAFFAEJAQALAAAAAA==.Corneliastr:BAAALgAFFAQJBAAAAA==.',
Cr='Crazynaga:BAABLgAECn8VAAIGAAYJnwVXlgDwAAAGAAYJnwVXlgDwAAAAAA==.Crisspy:BAACLgAFFH8VAAMOAAUJNgzvQwDYAAAOAAQJPwzvQwDYAAAPAAUJBQm3LgDYAAAuAAQKfzYAAw8ACQkAExUjAM0BAA8ACQkAExUjAM0BAA4AAgnVCFexAGYAAAAA.',
Cu='Cubes:BAACLgAFFH8aAAMQAAgJhCF6AAAjAgAQAAcJXSZ6AAAjAgARAAEJ5RIbXQBHAAAuAAQKfy8ABBAACQnzJRYBALgDABAACQnzJRYBALgDABIABgnNGJotAKMBABEAAwk/DlCFAJMAAAAA.Cutebunny:BAAALgADCgYJBgAAAA==.',
Da='Daisyspark:BAAALgAECgEJBAAAAA==.',
De='Deadlylight:BAAALgAECgEJAQAAAA==.Deathcrocker:BAECLgAFFH8eAAITAAcJ4SRLAACGAgATAAcJ4SRLAACGAgAuAAQKfxoAAhMACQkDJmwAAMsDABMACQkDJmwAAMsDAAAA.Decksey:BAAALgADCgEJAQABLgADCgYJCQALAAAAAA==.Decksters:BAAALgADCgYJCQAAAA==.',
Di='Divinebeef:BAABLgAECn8WAAIHAAgJBBcmTQD7AQAHAAgJBBcmTQD7AQABLgAFFAgJGQAHAAQUAA==.',
Do='Dogs:BAACLgAFFH8PAAIMAAUJyiP8EAB+AQAMAAUJyiP8EAB+AQAuAAQKfxsAAgwACAnrG9cNAOYCAAwACAnrG9cNAOYCAAEuAAUUCAkSAAIAgxYA.Domar:BAABLgAECn8UAAIPAAcJSxMrOABXAQAPAAcJSxMrOABXAQAAAA==.Doomslayer:BAABLgAECn8lAAQUAAkJ7BruUQDOAQAUAAkJ7BruUQDOAQATAAUJgAL3MwCgAAAVAAEJUgp8PwAoAAAAAA==.Doraei:BAABLgAECn8VAAIUAAgJmw5qewBsAQAUAAgJmw5qewBsAQAAAA==.Dothippo:BAABLgAECn8qAAMWAAcJthutCADBAQAWAAcJthutCADBAQAXAAEJFgR1KAEpAAAAAA==.',
Dr='Drutastic:BAAALgAECgIJAgAAAA==.',
Du='Dumach:BAAALgADCgYJBgAAAA==.Dunk:BAABLgAECn8lAAMHAAkJSRfbXwCxAQAHAAkJSRfbXwCxAQAKAAMJIg1OaACUAAAAAA==.',
Ea='Easy:BAAALgAECgUJCAABLgAECgYJBgALAAAAAA==.',
Ec='Eclipsus:BAAALgADCgcJCAABLgAFFAMJAwALAAAAAA==.',
Ed='Edamen:BAAALgAECgUJBQAAAA==.',
Eh='Ehrathorn:BAAALgAECgMJAwAAAA==.',
El='Elennoxx:BAAALgAECgEJAgAAAA==.Elf:BAAALgADCgUJBQAAAA==.Elijah:BAAALgAECgYJBgAAAA==.Elonaara:BAAALgADCgcJBwAAAA==.Elunëth:BAAALgADCgQJBAABLgAFFAYJHAAYAGsgAA==.',
Ep='Ephie:BAAALgADCgcJBwAAAA==.',
Et='Ether:BAAALgAECgMJBQAAAA==.',
Fa='Faedryl:BAAALgADCgQJBAAAAA==.Fandrin:BAAALgADCgUJBQAAAA==.Farg:BAAALgAECgEJAQAAAA==.Farslaw:BAAALgAECgQJBQAAAA==.',
Fe='Feledara:BAABLgAECn8rAAIMAAkJVREnJADTAQAMAAkJVREnJADTAQAAAA==.Felshort:BAAALgAECgEJAQABLgAFFAQJGwARAOsfAA==.',
Fi='Fionaweaver:BAAALgADCgIJAgAAAA==.',
Fo='Foebane:BAAALgAECgYJEAABLgAECgYJGwAZADwjAA==.',
Fr='Freezing:BAAALgAECgEJAwAAAA==.Frieren:BAACLgAFFH8ZAAMBAAgJ4ReFCgDLAQABAAgJ4ReFCgDLAQAaAAIJPiHUAwDEAAAuAAQKfyUABAEACQl9Il0NAFoDAAEACQl9Il0NAFoDABoAAQnTIAcNAFkAABsAAQkbDx0aAEcAAAAA.Froslass:BAABLgAECn8ZAAIUAAgJfx1dSgDjAQAUAAgJfx1dSgDjAQAAAA==.',
Fu='Funk:BAAALgAECgEJAQAAAA==.',
Ge='Gencrocker:BAEALgAECgMJAwABLgAFFAcJHgATAOEkAA==.Getoffenris:BAAALgAFFAQJBAAAAA==.',
Gl='Gloryhammer:BAABLgAECn8lAAQIAAkJHBuNCABPAgAIAAkJHBuNCABPAgAKAAUJKAXGawDLAAAHAAEJaxmmQwEzAAAAAA==.',
Go='Gobbs:BAABLgAECn8eAAMcAAYJNxeJCwBzAQAcAAYJ4g+JCwBzAQAZAAYJJxZeLQAxAQABLgAECggJHgACAJEbAA==.',
Gr='Grandma:BAAALgAECgEJAQAAAA==.Grimmi:BAAALgAECgEJAQAAAA==.',
Ha='Haldrian:BAAALgAECgcJEQAAAA==.Havack:BAAALgADCgEJAQAAAA==.',
He='Healslvt:BAAALgAECgEJAQAAAA==.Hexkittin:BAABLgAECn8bAAIOAAcJVRTvVQBeAQAOAAcJVRTvVQBeAQAAAA==.',
Hi='Hixon:BAAALgADCgMJAgAAAA==.',
Ho='Holyhota:BAACLgAFFH8JAAMdAAQJyRimCgC6AAAdAAMJMB2mCgC6AAAeAAMJQwr7OgCVAAAuAAQKfxcAAx0ACAk7IdELAJMCAB0ACAk7IdELAJMCAB4AAQmED+N7ADAAAAAA.Hop:BAACLgAFFH8MAAIfAAMJ3Bh8BADCAAAfAAMJ3Bh8BADCAAAuAAQKfzgAAh8ACQkPHHIGAIACAB8ACQkPHHIGAIACAAAA.Hota:BAAALgAECgYJBwABLgAFFAQJCQAdAMkYAA==.Hotamnk:BAAALgAFFAIJAwABLgAFFAQJCQAdAMkYAA==.',
If='Iffri:BAAALgADCgEJAQAAAA==.',
Il='Ilos:BAAALgADCgEJAQAAAA==.',
In='Inarius:BAAALgAECgEJAQAAAA==.',
Ir='Iraedies:BAAALgADCgEJAgAAAA==.Ironborn:BAAALgAFFAMJAwAAAA==.',
Iv='Ivakor:BAAALgAECgcJEwAAAA==.Ivyy:BAACLgAFFH8YAAIgAAYJiyGwDADRAQAgAAYJiyGwDADRAQAuAAQKfxcAAiAACAkSIrkNAMACACAACAkSIrkNAMACAAEuAAUUCQknABkAvhcA.',
Ja='Jackswagz:BAABLgAECn8pAAMOAAkJHhTaOgDDAQAOAAkJHhTaOgDDAQAPAAQJbAd7cgCUAAAAAA==.Jakol:BAAALgADCgkJGQAAAA==.Jaszuny:BAABLgAECn8yAAIEAAkJUhniBQBAAgAEAAkJUhniBQBAAgAAAA==.',
Je='Jezlyn:BAAALgAECgUJBQAAAA==.',
['Jö']='Jösîah:BAAALgAECgMJAwAAAA==.',
Ka='Kaladyn:BAAALgADCgIJAwABLgAECgkJGAAVAIwbAA==.Kasho:BAAALgAECgIJAgAAAA==.Katrixi:BAAALgAECgUJBQAAAA==.Katsumotosan:BAAALgADCggJDQAAAA==.',
Ke='Kev:BAABLgAECn8qAAQBAAcJ6iSFNQBDAgABAAcJ6iSFNQBDAgAbAAIJMiTbDwDEAAAaAAEJAAA8EgAXAAAAAA==.Kevlarr:BAAALgADCgcJBwAAAA==.',
Ko='Kombatgodess:BAAALgADCgcJDQAAAA==.',
Ku='Kurgen:BAAALgADCgUJCgAAAA==.Kurorn:BAAALgAECggJCQAAAA==.',
Kv='Kvasir:BAABLgAECn9LAAIUAAkJSR3LAgBHAgAUAAkJSR3LAgBHAgAAAA==.',
Ky='Kynolight:BAAALgAECgQJAwAAAA==.',
['Kâ']='Kânna:BAAALgAECgQJBQAAAA==.',
La='Lalaise:BAAALgAECgMJAwAAAA==.Lanaria:BAAALgAECgMJAwAAAA==.Lancayne:BAAALgADCgIJAQAAAA==.',
Li='Lichkingstoy:BAACLgAFFH8ZAAIHAAgJBBSiHgCNAQAHAAgJBBSiHgCNAQAuAAQKfyAAAgcACQljG9oxAFsCAAcACQljG9oxAFsCAAAA.Lieb:BAAALgAECgUJBQAAAA==.Lihrna:BAAALgAECgIJAwAAAA==.Littlecutie:BAAALgADCgMJAwAAAA==.',
Lo='Lolamarie:BAAALgADCgQJCQAAAA==.',
Lu='Lunareclipse:BAAALgAECgIJAgAAAA==.Luniaira:BAAALgAECggJDgAAAA==.Lushara:BAAALgAECgEJAQAAAA==.',
Ma='Maedy:BAAALgADCgQJBAABLgAFFAQJEAAJAK8EAA==.Maegii:BAAALgADCgEJAQAAAA==.Manafist:BAAALgADCgMJAwABLgAECgYJGwAZADwjAA==.Manistas:BAAALgAECgEJAQAAAA==.Manta:BAABLgAECn8gAAMTAAgJKRW7JgAeAQAUAAcJXw5HjwBiAQATAAUJjhy7JgAeAQAAAA==.Maroon:BAAALgAECggJEwAAAA==.',
Me='Menasor:BAAALgADCgQJBAAAAA==.',
Mi='Micaa:BAAALgAECgYJEAAAAA==.Minarielle:BAAALgADCgUJBQAAAA==.Mingó:BAAALgAECgUJBwAAAA==.Miracle:BAAALgAFFAMJBAAAAA==.Mirana:BAAALgADCgEJAQAAAA==.Mirzza:BAAALgAECgQJBQAAAA==.Mistake:BAAALgAECgYJEgAAAA==.Mistymiz:BAAALgAECgYJCAAAAA==.',
Mo='Mockra:BAAALgAECgQJBgAAAA==.Monkcrocker:BAECLgAFFH8VAAISAAcJeCRJAQDPAgASAAcJeCRJAQDPAgAuAAQKfxUAAhIABwnxJcANALcCABIABwnxJcANALcCAAEuAAUUBwkeABMA4SQA.',
Mv='Mvmx:BAAALgAECgIJAgAAAA==.',
['Mé']='Méthan:BAAALgADCgQJBAAAAA==.',
Na='Nabarke:BAAALgAECgcJCwAAAA==.Naturestrike:BAAALgADCgcJEQAAAA==.Naztherune:BAAALgADCgQJBQAAAA==.',
Ni='Nier:BAAALgAECgQJBwAAAA==.Nightsilver:BAAALgADCgkJIwAAAA==.',
No='Noisemarine:BAAALgAECgQJBAAAAA==.Nooxi:BAAALgADCggJCAABLgAECgcJCwALAAAAAA==.Nosidh:BAAALgAECgMJBAAAAA==.Nospheratus:BAAALgAFFAMJBAABLgAFFAYJEQATAKcKAA==.Notsofresh:BAAALgADCgMJAwAAAA==.',
Nx='Nx:BAAALgAECgMJBgAAAA==.',
Ny='Nylianna:BAACLgAFFH8UAAMKAAQJIBlfCQAYAQAKAAMJYCBfCQAYAQAHAAMJThimZQDjAAAuAAQKf0AAAwcACQkYImkMACsDAAcACQkYImkMACsDAAoACQkjFocYAEMCAAAA.',
Oa='Oaken:BAAALgADCgkJCQAAAA==.',
Ob='Obscurity:BAACLgAFFH8NAAIRAAYJWxyEBAAtAgARAAYJWxyEBAAtAgAuAAQKfxcAAxEABgnlIageACQCABEABgnlIageACQCABAAAQn3FZYRAEUAAAAA.',
Og='Ogganborn:BAABLgAECn8nAAICAAgJHx/WSwC+AQACAAgJHx/WSwC+AQAAAA==.',
Ol='Olovis:BAAALgAECgQJBAAAAA==.',
On='Oneira:BAAALgAECgQJBAAAAA==.',
Or='Orange:BAAALgAECgQJBQAAAA==.Orrark:BAAALgADCgEJAQAAAA==.',
Ph='Phatmyke:BAAALgADCgEJAQAAAA==.',
Pi='Pikal:BAABLgAECn8bAAIHAAcJ2hLjmgBAAQAHAAcJ2hLjmgBAAQAAAA==.',
Pr='Priestigory:BAABLgAECn8wAAMSAAkJgh10DABuAgASAAkJoRx0DABuAgAQAAQJORLBbAB5AAAAAA==.',
Pv='Pvtcrocker:BAEBLgAFFH8MAAIhAAYJ0R+jAQDJAQAhAAYJ0R+jAQDJAQABLgAFFAcJHgATAOEkAA==.',
Py='Pyrithyr:BAABLgAECn8ZAAMIAAgJLxtTFACJAQAIAAUJbyJTFACJAQAHAAgJjBOifQBzAQABLgAFFAMJBAABAG8NAA==.',
Qu='Quelyne:BAAALgADCgMJAwAAAA==.Quink:BAAALgAECgMJAwABLgAECgcJCwALAAAAAA==.Quintus:BAAALgAECgUJBgAAAA==.',
Ra='Raelyn:BAAALgAECgYJDgABLgAFFAMJCgAiAIgiAA==.Raevaela:BAAALgADCgQJBwABLgAECgcJFQAQABkcAA==.Railiana:BAABLgAECn8kAAICAAkJaQnjeABOAQACAAkJaQnjeABOAQAAAA==.',
Re='Regrowth:BAABLgAECn9AAAUiAAkJQiHRBQBaAwAiAAkJQiHRBQBaAwAgAAIJqBzcWgCpAAAfAAMJVxUOOAB6AAAhAAIJ+Bs/EQBOAAAAAA==.Reminesce:BAAALgADCgEJAQAAAA==.',
Rh='Rholune:BAAALgAECgUJDQAAAA==.',
Ro='Roberta:BAAALgADCgQJBgAAAA==.',
Rp='Rplooker:BAAALgADCgcJEgABLgAECgcJFgAQAJwPAA==.',
Ru='Ruby:BAACLgAFFH8OAAINAAgJNhkRAQD/AQANAAgJNhkRAQD/AQAuAAQKfxwAAg0ACAmbJbUBAGgDAA0ACAmbJbUBAGgDAAAA.Ruhai:BAAALgAECgYJCwAAAA==.',
['Rà']='Ràistlin:BAABLgAECn8aAAIBAAYJNA4IxwD/AAABAAYJNA4IxwD/AAAAAA==.',
Sa='Saelki:BAAALgAECgMJAwAAAA==.',
Se='Sephiran:BAABLgAECn84AAMjAAkJ8B1BDgByAgAjAAkJ8B1BDgByAgAeAAgJRxnnAgCxAQAAAA==.',
Sh='Shagra:BAAALgAECgkJEwAAAA==.Shagraq:BAAALgADCgEJAQAAAA==.Shaomei:BAAALgAFFAIJAgABLgAFFAUJEwAEAA8dAA==.Shielen:BAABLgAECn8bAAIZAAYJPCNTFwDgAQAZAAYJPCNTFwDgAQAAAA==.Shoepert:BAABLgAECn84AAIMAAkJbSWSBAAbAwAMAAkJbSWSBAAbAwAAAA==.',
Si='Sib:BAABLgAFFH8IAAIGAAQJLRO/GAAHAQAGAAQJLRO/GAAHAQAAAA==.Sifrina:BAAALgADCgEJAQAAAA==.Sini:BAAALgAECgcJBQAAAA==.Sinna:BAAALgAECgkJBwAAAA==.',
Sj='Sj:BAAALgADCgYJBgABLgAECgYJGwAZADwjAA==.',
So='Southpaw:BAAALgAECgIJAgAAAA==.',
Sp='Splatugle:BAAALgAECgcJBQAAAA==.',
Sq='Squiggles:BAAALgAECgIJAgAAAA==.',
St='Stdot:BAABLgAECn8cAAMUAAkJNxS9TgDWAQAUAAkJaRC9TgDWAQATAAYJ5BREIwA5AQAAAA==.Stormstrike:BAAALgAECgMJAwAAAA==.',
Sw='Sway:BAAALgAECgUJBwABLgAECgYJBgALAAAAAA==.',
Ta='Tairn:BAAALgADCgQJBgAAAA==.Taluria:BAAALgAECgcJEAAAAA==.',
Te='Tempus:BAACLgAFFH8VAAIKAAUJ5BvgEgCZAQAKAAUJ5BvgEgCZAQAuAAQKfykABAoACQnEHKITAHICAAoACAk7HqITAHICAAgAAgndFGQ4AH0AAAcAAQn9CqyuASoAAAAA.Tenletters:BAAALgAFFAIJBAAAAA==.',
Th='That:BAAALgADCgYJBgAAAA==.Thrasius:BAAALgADCgYJBgAAAA==.',
Ti='Tikimon:BAAALgAECgEJAQAAAA==.Tinkernine:BAAALgAECgUJBQAAAA==.',
To='Tobofrog:BAABLgAFFH8FAAIgAAUJ3g5wJgD6AAAgAAUJ3g5wJgD6AAAAAA==.Toboo:BAAALgAECgcJBgAAAA==.Tolocforu:BAAALgAECgQJBgAAAA==.',
Tr='Trainedtiger:BAAALgAFFAEJBAAAAA==.',
Ty='Tyrgrim:BAAALgAECgcJEAAAAA==.',
Ul='Uldyssian:BAAALgAECgMJAwABLgAFFAQJFAAKACAZAA==.Ulfhednósh:BAAALgAECgIJAgAAAA==.',
Un='Union:BAAALgAECgEJAgAAAA==.Unwavering:BAAALgADCgEJAQAAAA==.',
Up='Uppies:BAAALgAECgQJCAAAAA==.',
Uw='Uwuforyou:BAABLgAECn8gAAQFAAgJIxQlHwCBAQAFAAgJIxQlHwCBAQAEAAUJpwxVHgCpAAAGAAEJ5wGZPgEXAAAAAA==.',
Va='Valalexis:BAAALgAECgEJAQAAAA==.',
Ve='Velawynn:BAACLgAFFH8cAAIdAAgJtByBBAAkAgAdAAgJtByBBAAkAgAuAAQKfy4AAx0ACQm6HhsFAP8CAB0ACQm6HhsFAP8CACMABAlhDutYALEAAAAA.Velladonna:BAAALgAECgYJDAAAAA==.Veronica:BAACLgAFFH8aAAMUAAcJfh17FwAjAgAUAAYJPBl7FwAjAgATAAYJKh8cBABvAQAuAAQKfx0AAxMACQlXI/ICABYDABMACQlXI/ICABYDABQABgn9GjV+AIcBAAEuAAUUCQkwACMAMiEA.',
Vh='Vhenir:BAAALgADCgcJDQAAAA==.',
Vi='Vixa:BAAALgAECgQJBwAAAA==.',
Vo='Voidbro:BAAALgAECgMJBQAAAA==.',
Vr='Vrag:BAAALgAECgEJAQAAAA==.',
Vy='Vynlordian:BAAALgAECgQJBgAAAA==.',
Wd='Wdfourty:BAAALgAECgEJAQAAAA==.',
Wy='Wyrdengilly:BAAALgADCgYJBgAAAA==.',
Xa='Xamot:BAAALgAFFAEJAQABLgAFFAUJFgAJAJUVAA==.Xarou:BAAALgAECgQJBgAAAA==.',
Xy='Xylanthria:BAAALgAFFAIJBAABLgAFFAQJFAAKACAZAA==.',
Ya='Yanyan:BAABLgAECn8ZAAIQAAcJKA7ROgAWAQAQAAcJKA7ROgAWAQAAAA==.',
Zi='Zilgius:BAABLgAECn8dAAMNAAcJSRz3GQBrAQANAAYJ7h33GQBrAQAMAAcJZRm/NwBoAQABLgAECgkJOAAjAPAdAA==.Zinjari:BAAALgADCgEJAQAAAA==.',
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
