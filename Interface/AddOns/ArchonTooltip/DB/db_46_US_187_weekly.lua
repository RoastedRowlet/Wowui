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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','Unknown-Unknown','Paladin-Retribution','Paladin-Protection','Evoker-Augmentation','Paladin-Holy','Warrior-Fury','Warrior-Protection','Shaman-Restoration','Shaman-Elemental','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Destruction','Warlock-Demonology','Evoker-Preservation','Rogue-Subtlety','Mage-Frost','Mage-Fire','Mage-Arcane','Rogue-Assassination','Priest-Holy','Priest-Discipline','Druid-Feral','Druid-Balance','Druid-Guardian','Druid-Restoration','Priest-Shadow',}
local provider = {region='US',realm='Sentinels',name='US',type='weekly',zone=46,date='2026-06-27',data={Aa='Aandheeog:BAAALgAECggJEAAAAA==.',
Ab='Absqwas:BAAALgAECgcJCwAAAA==.',
Ad='Adaina:BAAALgAFFAMJBAAAAA==.Adrax:BAAALgADCgcJDAAAAA==.Adronys:BAAALgADCgkJGgAAAA==.',
Ah='Aheeaheehahe:BAACLgAFFH8UAAIBAAQJKg+SEgAGAQABAAQJKg+SEgAGAQAuAAQKfzwAAwEACQkcHtQeAG0CAAEACQkcHtQeAG0CAAIAAwn5CDU4AD4AAAAA.',
Ai='Aiirsby:BAAALgAECgEJAQAAAA==.Ailanissa:BAAALgAECgQJCQAAAA==.Ailasaa:BAABLgAECn8dAAQDAAcJ7CJ6BwAOAgADAAUJLSZ6BwAOAgAEAAcJjBbUHACWAQAFAAIJgxcJ3AB+AAABLgAFFAIJAgAGAAAAAA==.Ailassa:BAAALgAFFAIJAgAAAA==.',
Am='Ametiszt:BAAALgAECgkJAQAAAA==.',
An='Ananya:BAAALgADCgMJAwAAAA==.Anbraxas:BAAALgAECgcJDwAAAA==.Aneesa:BAABLgAECn8eAAMHAAcJqBdDhwBhAQAHAAcJqBdDhwBhAQAIAAEJowMfWAAfAAAAAA==.',
Ao='Ao:BAAALgAECgYJBwAAAA==.',
Ar='Artax:BAAALgAECgYJDwAAAA==.',
As='Asdanot:BAABLgAECn8cAAIJAAkJ2xC+JQCxAQAJAAkJ2xC+JQCxAQAAAA==.Ashbahn:BAABLgAECn85AAMKAAkJsQvqOABpAQAKAAkJsQvqOABpAQAHAAcJbhGBnwA4AQAAAA==.Ashes:BAAALgAECgQJCQABLgAECgkJOQAKALELAA==.Ashmodai:BAAALgADCgQJBAAAAA==.Astovidatu:BAABLgAECn8eAAIHAAgJug7jDgDDAAAHAAgJug7jDgDDAAAAAA==.',
At='Atkascha:BAAALgADCgEJAQAAAA==.',
Au='Aurimas:BAAALgADCgEJAQAAAA==.Auroranova:BAABLgAECn85AAMHAAkJPw81ZQClAQAHAAkJPw81ZQClAQAKAAIJZwj4fgBOAAAAAA==.',
Ax='Axél:BAAALgAECgUJDAAAAA==.',
Az='Azlilar:BAAALgAECgEJAQABLgAECgQJCwAGAAAAAA==.',
Ba='Baddragon:BAAALgAECgYJBgABLgAFFAcJFgAHABkUAA==.',
Be='Berringer:BAAALgAECgQJCwAAAA==.',
Bi='Bigbuns:BAAALgAECgQJBAAAAA==.',
Bl='Bluedreamm:BAAALgAECgQJCgAAAA==.',
Br='Braei:BAAALgAECgcJDwAAAA==.Brilleleante:BAAALgADCgkJLwAAAA==.Brochacho:BAAALgAECgcJBwAAAA==.Broxmorn:BAAALgAECgEJAQAAAA==.',
Ca='Cala:BAAALgAFFAMJBAABLgAFFAcJIQACAD8fAA==.Canimai:BAACLgAFFH8MAAILAAMJagg6PgCxAAALAAMJagg6PgCxAAAuAAQKfygAAwsACQmBEYgwAIsBAAsACQkkD4gwAIsBAAwAAwmnEQlGAFoAAAAA.Carla:BAAALgADCgkJEAAAAA==.',
Ce='Cemetery:BAAALgAECgcJBwABLgAECggJEAAGAAAAAA==.',
Ch='Chudmeister:BAAALgAECgcJBgAAAA==.',
Co='Colin:BAAALgAECgQJCQABLgAFFAEJAQAGAAAAAA==.Corneliastr:BAAALgAFFAQJBAAAAA==.',
Cr='Crazynaga:BAABLgAECn8VAAIFAAYJnwVXlgDwAAAFAAYJnwVXlgDwAAAAAA==.Crisspy:BAACLgAFFH8VAAMNAAUJNgzvQwDYAAANAAQJPwzvQwDYAAAOAAUJBQm3LgDYAAAuAAQKfzYAAw4ACQkAExUjAM0BAA4ACQkAExUjAM0BAA0AAgnVCFexAGYAAAAA.',
Cu='Cubes:BAACLgAFFH8ZAAMPAAcJpiB6AAAjAgAPAAYJSyZ6AAAjAgAQAAEJ5RIbXQBHAAAuAAQKfy8ABA8ACQnzJRYBALgDAA8ACQnzJRYBALgDABEABgnNGJotAKMBABAAAwk/DlCFAJMAAAAA.Cutebunny:BAAALgADCgYJBgAAAA==.',
Da='Daisyspark:BAAALgAECgEJBAAAAA==.',
De='Deadlylight:BAAALgAECgEJAQAAAA==.Deathcrocker:BAECLgAFFH8eAAISAAcJ4SRLAACGAgASAAcJ4SRLAACGAgAuAAQKfxoAAhIACQkDJmwAAMsDABIACQkDJmwAAMsDAAAA.Decksey:BAAALgADCgEJAQABLgADCgYJCQAGAAAAAA==.Decksters:BAAALgADCgYJCQAAAA==.',
Di='Divinebeef:BAABLgAECn8WAAIHAAgJBBcmTQD7AQAHAAgJBBcmTQD7AQABLgAFFAcJFgAHABkUAA==.',
Do='Dogs:BAACLgAFFH8PAAILAAUJyiP8EAB+AQALAAUJyiP8EAB+AQAuAAQKfxsAAgsACAnrG9cNAOYCAAsACAnrG9cNAOYCAAEuAAUUCAkSAAEAcRYA.Domar:BAABLgAECn8UAAIOAAcJSxMrOABXAQAOAAcJSxMrOABXAQAAAA==.Doomslayer:BAABLgAECn8lAAQTAAkJ7BruUQDOAQATAAkJ7BruUQDOAQASAAUJgAL3MwCgAAAUAAEJUgp8PwAoAAAAAA==.Doraei:BAABLgAECn8VAAITAAgJmw5qewBsAQATAAgJmw5qewBsAQAAAA==.Dothippo:BAABLgAECn8qAAMVAAcJthutCADBAQAVAAcJthutCADBAQAWAAEJFgR1KAEpAAAAAA==.',
Dr='Drutastic:BAAALgAECgIJAgAAAA==.',
Du='Dumach:BAAALgADCgYJBgAAAA==.Dunk:BAABLgAECn8lAAMHAAkJSRfbXwCxAQAHAAkJSRfbXwCxAQAKAAMJIg1OaACUAAAAAA==.',
Ea='Easy:BAAALgAECgUJCAABLgAECgYJBgAGAAAAAA==.',
Ec='Eclipsus:BAAALgADCgcJCAABLgAFFAMJAwAGAAAAAA==.',
Ed='Edamen:BAAALgAECgUJBQAAAA==.',
Eh='Ehrathorn:BAAALgAECgMJAwAAAA==.',
El='Elennoxx:BAAALgAECgEJAgAAAA==.Elf:BAAALgADCgUJBQAAAA==.Elijah:BAAALgAECgYJBgAAAA==.Elonaara:BAAALgADCgcJBwAAAA==.Elunëth:BAAALgADCgQJBAABLgAFFAYJHAAXAGsgAA==.',
Ep='Ephie:BAAALgADCgcJBwAAAA==.',
Et='Ether:BAAALgAECgMJBQAAAA==.',
Fa='Faedryl:BAAALgADCgQJBAAAAA==.Fandrin:BAAALgADCgUJBQAAAA==.Farg:BAAALgAECgEJAQAAAA==.Farslaw:BAAALgAECgQJBQAAAA==.',
Fe='Feledara:BAABLgAECn8rAAILAAkJVREnJADTAQALAAkJVREnJADTAQAAAA==.Felshort:BAAALgAECgEJAQABLgAFFAQJGQAQAOsfAA==.',
Fi='Fionaweaver:BAAALgADCgIJAgAAAA==.',
Fo='Foebane:BAAALgAECgYJEAABLgAECgYJGwAYADwjAA==.',
Fr='Freezing:BAAALgAECgEJAwAAAA==.Frieren:BAACLgAFFH8ZAAMZAAgJ4ReFCgDLAQAZAAgJ4ReFCgDLAQAaAAIJPiHUAwDEAAAuAAQKfyUABBkACQl9Il0NAFoDABkACQl9Il0NAFoDABoAAQnTIAcNAFkAABsAAQkbDx0aAEcAAAAA.Froslass:BAABLgAECn8ZAAITAAgJfx1dSgDjAQATAAgJfx1dSgDjAQAAAA==.',
Fu='Funk:BAAALgAECgEJAQAAAA==.',
Ge='Gencrocker:BAEALgAECgMJAwABLgAFFAcJHgASAOEkAA==.Getoffenris:BAAALgAFFAQJBAAAAA==.',
Gl='Gloryhammer:BAABLgAECn8lAAQIAAkJHBuNCABPAgAIAAkJHBuNCABPAgAKAAUJKAXGawDLAAAHAAEJaxmmQwEzAAAAAA==.',
Go='Gobbs:BAABLgAECn8eAAMcAAYJNxeJCwBzAQAcAAYJ4g+JCwBzAQAYAAYJJxZeLQAxAQABLgAECggJHgABAJEbAA==.',
Gr='Grandma:BAAALgAECgEJAQAAAA==.',
Ha='Haldrian:BAAALgAECgcJEQAAAA==.Havack:BAAALgADCgEJAQAAAA==.',
He='Healslvt:BAAALgAECgEJAQAAAA==.Hexkittin:BAABLgAECn8bAAINAAcJVRTvVQBeAQANAAcJVRTvVQBeAQAAAA==.',
Hi='Hixon:BAAALgADCgMJAgAAAA==.',
Ho='Holyhota:BAACLgAFFH8JAAMdAAQJyRimCgC6AAAdAAMJMB2mCgC6AAAeAAMJQwr7OgCVAAAuAAQKfxcAAx0ACAk7IdELAJMCAB0ACAk7IdELAJMCAB4AAQmED+N7ADAAAAAA.Hop:BAACLgAFFH8JAAIfAAMJ3BjUDADqAAAfAAMJ3BjUDADqAAAuAAQKfzgAAh8ACQkPHHIGAIACAB8ACQkPHHIGAIACAAAA.Hota:BAAALgAECgYJBwABLgAFFAQJCQAdAMkYAA==.Hotamnk:BAAALgAFFAIJAwABLgAFFAQJCQAdAMkYAA==.',
If='Iffri:BAAALgADCgEJAQAAAA==.',
Il='Ilos:BAAALgADCgEJAQAAAA==.',
In='Inarius:BAAALgAECgEJAQAAAA==.',
Ir='Iraedies:BAAALgADCgEJAgAAAA==.Ironborn:BAAALgAFFAMJAwAAAA==.',
Iv='Ivakor:BAAALgAECgYJEgAAAA==.Ivyy:BAACLgAFFH8VAAIgAAYJeiGwDADRAQAgAAYJeiGwDADRAQAuAAQKfxcAAiAACAkSIrkNAMACACAACAkSIrkNAMACAAEuAAUUCAkeABgAkhYA.',
Ja='Jackswagz:BAABLgAECn8pAAMNAAkJHhTaOgDDAQANAAkJHhTaOgDDAQAOAAQJbAd7cgCUAAAAAA==.Jaszuny:BAABLgAECn8yAAIDAAkJUhniBQBAAgADAAkJUhniBQBAAgAAAA==.',
Je='Jezlyn:BAAALgAECgUJBQAAAA==.',
['Jö']='Jösîah:BAAALgAECgMJAwAAAA==.',
Ka='Kaladyn:BAAALgADCgIJAwABLgAECggJFAASAEIaAA==.Kasho:BAAALgAECgIJAgAAAA==.Katrixi:BAAALgAECgUJBQAAAA==.Katsumotosan:BAAALgADCggJDQAAAA==.',
Ke='Kev:BAABLgAECn8qAAQZAAcJ6iSFNQBDAgAZAAcJ6iSFNQBDAgAbAAIJMiTbDwDEAAAaAAEJAAA8EgAXAAAAAA==.Kevlarr:BAAALgADCgcJBwAAAA==.',
Ko='Kombatgodess:BAAALgADCgcJDQAAAA==.',
Ku='Kurgen:BAAALgADCgUJCgAAAA==.Kurorn:BAAALgAECggJCQAAAA==.',
Kv='Kvasir:BAABLgAECn9KAAITAAkJSR1MFgDBAgATAAkJSR1MFgDBAgAAAA==.',
Ky='Kynolight:BAAALgAECgQJAwAAAA==.',
['Kâ']='Kânna:BAAALgAECgQJBQAAAA==.',
La='Lalaise:BAAALgAECgMJAwAAAA==.Lanaria:BAAALgAECgMJAwAAAA==.Lancayne:BAAALgADCgIJAQAAAA==.',
Li='Lichkingstoy:BAACLgAFFH8WAAIHAAcJGRSiHgCNAQAHAAcJGRSiHgCNAQAuAAQKfyAAAgcACQljG9oxAFsCAAcACQljG9oxAFsCAAAA.Lieb:BAAALgAECgUJBQAAAA==.Lihrna:BAAALgAECgIJAwAAAA==.Littlecutie:BAAALgADCgMJAwAAAA==.',
Lo='Lolamarie:BAAALgADCgQJCQAAAA==.',
Lu='Lunareclipse:BAAALgAECgIJAgAAAA==.Luniaira:BAAALgAECggJDgAAAA==.Lushara:BAAALgAECgEJAQAAAA==.',
Ma='Maedy:BAAALgADCgQJBAABLgAFFAQJDQAJAIsDAA==.Maegii:BAAALgADCgEJAQAAAA==.Manafist:BAAALgADCgMJAwABLgAECgYJGwAYADwjAA==.Manistas:BAAALgAECgEJAQAAAA==.Manta:BAABLgAECn8gAAMSAAgJKRW7JgAeAQATAAcJXw5HjwBiAQASAAUJjhy7JgAeAQAAAA==.Maroon:BAAALgAECggJEwAAAA==.',
Me='Menasor:BAAALgADCgQJBAAAAA==.',
Mi='Micaa:BAAALgAECgYJEAAAAA==.Minarielle:BAAALgADCgUJBQAAAA==.Mingó:BAAALgAECgUJBwAAAA==.Miracle:BAAALgAFFAMJBAAAAA==.Mirana:BAAALgADCgEJAQAAAA==.Mirzza:BAAALgAECgQJBQAAAA==.Mistake:BAAALgAECgYJEgAAAA==.Mistymiz:BAAALgAECgYJCAAAAA==.',
Mo='Mockra:BAAALgAECgQJBgAAAA==.Monkcrocker:BAECLgAFFH8VAAIRAAcJeCRJAQDPAgARAAcJeCRJAQDPAgAuAAQKfxUAAhEABwnxJcANALcCABEABwnxJcANALcCAAEuAAUUBwkeABIA4SQA.',
Mv='Mvmx:BAAALgAECgIJAgAAAA==.',
['Mé']='Méthan:BAAALgADCgQJBAAAAA==.',
Na='Nabarke:BAAALgAECgcJCwAAAA==.Naturestrike:BAAALgADCgcJDAAAAA==.Naztherune:BAAALgADCgQJBQAAAA==.',
Ni='Nier:BAAALgAECgQJBwAAAA==.Nightsilver:BAAALgADCgkJIwAAAA==.',
No='Noisemarine:BAAALgAECgQJBAAAAA==.Nooxi:BAAALgADCggJCAABLgAECgcJCwAGAAAAAA==.Nosidh:BAAALgAECgMJBAAAAA==.Nospheratus:BAAALgAFFAMJAwABLgAFFAUJEAASAGULAA==.Notsofresh:BAAALgADCgMJAwAAAA==.',
Nx='Nx:BAAALgAECgMJBAAAAA==.',
Ny='Nylianna:BAACLgAFFH8RAAMHAAQJcBKmZQDjAAAHAAMJThimZQDjAAAKAAMJMRAhMAC1AAAuAAQKf0AAAwcACQkYImkMACsDAAcACQkYImkMACsDAAoACQkjFocYAEMCAAAA.',
Oa='Oaken:BAAALgADCgkJCQAAAA==.',
Ob='Obscurity:BAACLgAFFH8NAAIQAAYJWxzPAgA3AgAQAAYJWxzPAgA3AgAuAAQKfxUAAxAABgnlIageACQCABAABgnlIageACQCAA8AAQn3FVwMAEYAAAAA.',
Og='Ogganborn:BAABLgAECn8lAAIBAAYJgx/WSwC+AQABAAYJgx/WSwC+AQAAAA==.',
Ol='Olovis:BAAALgAECgQJBAAAAA==.',
On='Oneira:BAAALgAECgQJBAAAAA==.',
Or='Orange:BAAALgAECgQJBQAAAA==.Orrark:BAAALgADCgEJAQAAAA==.',
Ph='Phatmyke:BAAALgADCgEJAQAAAA==.',
Pi='Pikal:BAABLgAECn8bAAIHAAcJ2hLjmgBAAQAHAAcJ2hLjmgBAAQAAAA==.',
Pr='Priestigory:BAABLgAECn8wAAMRAAkJgh10DABuAgARAAkJoRx0DABuAgAPAAQJORLBbAB5AAAAAA==.',
Pv='Pvtcrocker:BAEBLgAFFH8KAAIhAAYJNx8eAQDCAQAhAAYJNx8eAQDCAQABLgAFFAcJHgASAOEkAA==.',
Py='Pyrithyr:BAABLgAECn8ZAAMIAAgJLxtTFACJAQAIAAUJbyJTFACJAQAHAAgJjBOifQBzAQABLgAFFAIJAgAGAAAAAA==.',
Qu='Quelyne:BAAALgADCgMJAwAAAA==.Quink:BAAALgAECgMJAwABLgAECgcJCwAGAAAAAA==.Quintus:BAAALgAECgUJBgAAAA==.',
Ra='Raelyn:BAAALgAECgYJCwABLgAFFAMJCgAiAIgiAA==.Raevaela:BAAALgADCgQJBwABLgAECgcJFQAPABkcAA==.Railiana:BAABLgAECn8kAAIBAAkJZQnjeABOAQABAAkJZQnjeABOAQAAAA==.Ravelin:BAAALgADCgkJGQAAAA==.',
Re='Regrowth:BAABLgAECn9AAAUiAAkJQiHRBQBaAwAiAAkJQiHRBQBaAwAgAAIJqBzcWgCpAAAfAAMJVxUOOAB6AAAhAAIJ+BtgDABOAAAAAA==.Reminesce:BAAALgADCgEJAQAAAA==.',
Rh='Rholune:BAAALgAECgUJDQAAAA==.',
Ro='Roberta:BAAALgADCgQJBgAAAA==.',
Rp='Rplooker:BAAALgADCgcJEgABLgAECgcJFgAPAJwPAA==.',
Ru='Ruby:BAACLgAFFH8OAAIMAAgJNhkRAQD/AQAMAAgJNhkRAQD/AQAuAAQKfxwAAgwACAmbJbUBAGgDAAwACAmbJbUBAGgDAAAA.Ruhai:BAAALgAECgYJCwAAAA==.',
['Rà']='Ràistlin:BAABLgAECn8aAAIZAAYJNA4IxwD/AAAZAAYJNA4IxwD/AAAAAA==.',
Sa='Saelki:BAAALgAECgMJAwAAAA==.',
Se='Sephiran:BAABLgAECn8xAAMjAAkJ8B1BDgByAgAjAAkJ8B1BDgByAgAeAAgJyRf9GAAKAgAAAA==.',
Sh='Shagra:BAAALgAECgcJEQAAAA==.Shagraq:BAAALgADCgEJAQAAAA==.Shielen:BAABLgAECn8bAAIYAAYJPCNTFwDgAQAYAAYJPCNTFwDgAQAAAA==.Shoepert:BAABLgAECn84AAILAAkJbSWSBAAbAwALAAkJbSWSBAAbAwAAAA==.',
Si='Sib:BAABLgAFFH8HAAIFAAQJShGcEQAMAQAFAAQJShGcEQAMAQAAAA==.Sifrina:BAAALgADCgEJAQAAAA==.Sini:BAAALgAECgcJBQABLgAFFAkJNAAFANglAA==.Sinna:BAAALgAECgkJBwAAAA==.',
Sj='Sj:BAAALgADCgYJBgABLgAECgYJGwAYADwjAA==.',
So='Southpaw:BAAALgAECgIJAgAAAA==.',
Sp='Splatugle:BAAALgAECgcJBQAAAA==.',
Sq='Squiggles:BAAALgAECgIJAgAAAA==.',
St='Stdot:BAABLgAECn8cAAMTAAkJNxS9TgDWAQATAAkJaRC9TgDWAQASAAYJ5BREIwA5AQAAAA==.Stormstrike:BAAALgAECgIJAgAAAA==.',
Sw='Sway:BAAALgAECgUJBwABLgAECgYJBgAGAAAAAA==.',
Ta='Tairn:BAAALgADCgQJBgAAAA==.Taluria:BAAALgAECgcJEAAAAA==.',
Te='Tempus:BAACLgAFFH8VAAIKAAUJ5BvgEgCZAQAKAAUJ5BvgEgCZAQAuAAQKfykABAoACQnEHKITAHICAAoACAk7HqITAHICAAgAAgndFGQ4AH0AAAcAAQn9CqyuASoAAAAA.Tenletters:BAAALgAFFAIJBAAAAA==.',
Th='That:BAAALgADCgYJBgAAAA==.Thrasius:BAAALgADCgYJBgAAAA==.',
Ti='Tikimon:BAAALgAECgEJAQAAAA==.Tinkernine:BAAALgAECgUJBQAAAA==.',
To='Tobofrog:BAABLgAFFH8FAAIgAAUJ3g5wJgD6AAAgAAUJ3g5wJgD6AAAAAA==.Toboo:BAAALgAECgcJBgAAAA==.Tolocforu:BAAALgAECgQJBgAAAA==.',
Tr='Trainedtiger:BAAALgAFFAEJBAAAAA==.',
Ty='Tyrgrim:BAAALgAECgcJEAAAAA==.',
Ul='Uldyssian:BAAALgAECgMJAwABLgAFFAQJEQAHAHASAA==.Ulfhednósh:BAAALgAECgIJAgAAAA==.',
Un='Union:BAAALgAECgEJAgAAAA==.Unwavering:BAAALgADCgEJAQAAAA==.',
Up='Uppies:BAAALgAECgQJCAAAAA==.',
Uw='Uwuforyou:BAABLgAECn8gAAQEAAgJIxQlHwCBAQAEAAgJIxQlHwCBAQADAAUJpwxVHgCpAAAFAAEJ5wGZPgEXAAAAAA==.',
Va='Valalexis:BAAALgAECgEJAQAAAA==.',
Ve='Velawynn:BAACLgAFFH8bAAIdAAcJ+huBBAAkAgAdAAcJ+huBBAAkAgAuAAQKfy4AAx0ACQm6HhsFAP8CAB0ACQm6HhsFAP8CACMABAlhDutYALEAAAAA.Velladonna:BAAALgAECgYJDAAAAA==.Veronica:BAACLgAFFH8aAAMTAAcJfh17FwAjAgATAAYJPBl7FwAjAgASAAYJKh8cBABvAQAuAAQKfx0AAxIACQlXI/ICABYDABIACQlXI/ICABYDABMABgn9GjV+AIcBAAEuAAUUCQknACMArCAA.',
Vh='Vhenir:BAAALgADCgcJDQAAAA==.',
Vi='Vixa:BAAALgAECgQJBwAAAA==.',
Vo='Voidbro:BAAALgAECgMJBQAAAA==.',
Vy='Vynlordian:BAAALgAECgQJBgAAAA==.',
Wd='Wdfourty:BAAALgAECgEJAQAAAA==.',
Wy='Wyrdengilly:BAAALgADCgYJBgAAAA==.',
Xa='Xamot:BAAALgAFFAEJAQABLgAFFAUJFQAJAJUVAA==.Xarou:BAAALgAECgQJBgAAAA==.',
Xy='Xylanthria:BAAALgAFFAIJAgABLgAFFAQJEQAHAHASAA==.',
Ya='Yanyan:BAABLgAECn8ZAAIPAAcJKA7ROgAWAQAPAAcJKA7ROgAWAQAAAA==.',
Zi='Zilgius:BAABLgAECn8dAAMMAAcJSRz3GQBrAQAMAAYJ7h33GQBrAQALAAcJZRm/NwBoAQABLgAECgkJMQAjAPAdAA==.Zinjari:BAAALgADCgEJAQAAAA==.',
Zl='Zlambo:BAAALgAECgMJBQABLgAFFAMJAwAGAAAAAA==.',
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
