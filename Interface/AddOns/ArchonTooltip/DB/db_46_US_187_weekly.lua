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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','Unknown-Unknown','Paladin-Retribution','Paladin-Protection','Evoker-Augmentation','Paladin-Holy','Warrior-Fury','Warrior-Protection','Shaman-Restoration','Shaman-Elemental','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Destruction','Warlock-Demonology','Evoker-Preservation','Rogue-Subtlety','Mage-Frost','Mage-Fire','Mage-Arcane','Rogue-Assassination','Priest-Holy','Priest-Discipline','Druid-Feral','Druid-Balance','Druid-Restoration','Druid-Guardian','Priest-Shadow',}
local provider = {region='US',realm='Sentinels',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aandheeog:BAAALgAECggJEAAAAA==.',
Ab='Absqwas:BAAALgAECgUJCAAAAA==.',
Ad='Adaina:BAAALgAECgYJCwAAAA==.Adrax:BAAALgADCgcJDAAAAA==.Adronys:BAAALgADCgkJGgAAAA==.',
Ah='Aheeaheehahe:BAACLgAFFH8MAAIBAAMJQQ+GXgDgAAABAAMJQQ+GXgDgAAAuAAQKfzwAAwEACQkcHuEdAG8CAAEACQkcHuEdAG8CAAIAAwn5CGc3AD4AAAAA.',
Ai='Ailanissa:BAAALgAECgQJCQAAAA==.Ailasaa:BAABLgAECn8dAAQDAAcJ7CJ6BwAOAgADAAUJLSZ6BwAOAgAEAAcJjBYtHACXAQAFAAIJgxet2AB+AAABLgAFFAEJAQAGAAAAAA==.Ailassa:BAAALgAFFAEJAQAAAA==.',
Am='Ametiszt:BAAALgAECgkJAQAAAA==.',
An='Anbraxas:BAAALgAECgYJDgAAAA==.Aneesa:BAABLgAECn8eAAMHAAcJqBfXgwBlAQAHAAcJqBfXgwBlAQAIAAEJowPCVgAfAAAAAA==.',
Ao='Ao:BAAALgAECgYJBwAAAA==.',
Ar='Artax:BAAALgAECgYJDwAAAA==.',
As='Asdanot:BAABLgAECn8cAAIJAAkJ2xDcJAC1AQAJAAkJ2xDcJAC1AQAAAA==.Ashbahn:BAABLgAECn85AAMKAAkJsQv1NwBrAQAKAAkJsQv1NwBrAQAHAAcJbhEVnAA7AQAAAA==.Ashes:BAAALgAECgQJCQABLgAECgkJOQAKALELAA==.Ashmodai:BAAALgADCgQJBAAAAA==.Astovidatu:BAABLgAECn8XAAIHAAgJJA3TjQBTAQAHAAgJJA3TjQBTAQAAAA==.',
At='Atkascha:BAAALgADCgEJAQAAAA==.',
Au='Auroranova:BAABLgAECn81AAMHAAkJ0g6uYgCoAQAHAAkJ0g6uYgCoAQAKAAIJZwi6fABQAAAAAA==.',
Ax='Axél:BAAALgAECgUJDAAAAA==.',
Ba='Baddragon:BAAALgAECgYJBgABLgAFFAcJFgAHABkUAA==.',
Be='Berringer:BAAALgAECgQJCwAAAA==.',
Bi='Bigbuns:BAAALgAECgQJBAAAAA==.',
Bl='Bluedreamm:BAAALgAECgQJCgAAAA==.',
Br='Braei:BAAALgAECgYJDgAAAA==.Brilleleante:BAAALgADCgkJLwAAAA==.Brochacho:BAAALgAECgcJBwAAAA==.Broxmorn:BAAALgAECgEJAQAAAA==.',
Ca='Cala:BAAALgAFFAMJBAABLgAFFAcJIAACAAgfAA==.Canimai:BAACLgAFFH8LAAILAAMJaghuPACxAAALAAMJaghuPACxAAAuAAQKfygAAwsACQmBESQvAJEBAAsACQkkDyQvAJEBAAwAAwmnEdtEAFoAAAAA.Carla:BAAALgADCgkJEAAAAA==.',
Ch='Chudmeister:BAAALgAECgcJBgAAAA==.',
Co='Colin:BAAALgAECgQJCQABLgAFFAEJAQAGAAAAAA==.Corneliastr:BAAALgAFFAQJBAAAAA==.',
Cr='Crazynaga:BAABLgAECn8VAAIFAAYJnwVXlgDwAAAFAAYJnwVXlgDwAAAAAA==.Crisspy:BAACLgAFFH8VAAMNAAUJNgzHQQDZAAANAAQJPwzHQQDZAAAOAAUJBQkqLQDZAAAuAAQKfzYAAw4ACQkAE3IiAM4BAA4ACQkAE3IiAM4BAA0AAgnVCCauAGYAAAAA.',
Cu='Cubes:BAACLgAFFH8ZAAMPAAcJpiB6AAAjAgAPAAYJSyZ6AAAjAgAQAAEJ5RL2WABHAAAuAAQKfy8ABA8ACQnzJRYBALgDAA8ACQnzJRYBALgDABEABgnNGJotAKMBABAAAwk/DlGBAJMAAAAA.Cutebunny:BAAALgADCgYJBgAAAA==.',
Da='Daisyspark:BAAALgAECgEJBAAAAA==.',
De='Deadlylight:BAAALgADCgUJBQAAAA==.Deathcrocker:BAECLgAFFH8dAAISAAcJ4SRLAACGAgASAAcJ4SRLAACGAgAuAAQKfxoAAhIACQkDJmwAAMsDABIACQkDJmwAAMsDAAAA.Decksey:BAAALgADCgEJAQABLgADCgYJCQAGAAAAAA==.Decksters:BAAALgADCgYJCQAAAA==.',
Di='Divinebeef:BAABLgAECn8WAAIHAAgJBBcmTQD7AQAHAAgJBBcmTQD7AQABLgAFFAcJFgAHABkUAA==.',
Do='Dogs:BAACLgAFFH8PAAILAAUJyiMTEAB/AQALAAUJyiMTEAB/AQAuAAQKfxsAAgsACAnrG9cNAOYCAAsACAnrG9cNAOYCAAEuAAUUBwkZAAcAPxwA.Domar:BAAALgAECgcJEwAAAA==.Doomslayer:BAABLgAECn8lAAQTAAkJ7BriUADOAQATAAkJ7BriUADOAQASAAUJgAL3MwCgAAAUAAEJUgqcPQApAAAAAA==.Doraei:BAABLgAECn8VAAITAAgJmw6oeABvAQATAAgJmw6oeABvAQAAAA==.Dothippo:BAABLgAECn8qAAMVAAcJthtkCADCAQAVAAcJthtkCADCAQAWAAEJFgR1KAEpAAAAAA==.',
Dr='Drutastic:BAAALgAECgIJAgAAAA==.',
Du='Dumach:BAAALgADCgYJBgAAAA==.Dunk:BAABLgAECn8lAAMHAAkJSRe4XgCxAQAHAAkJSRe4XgCxAQAKAAMJIg0CZwCWAAAAAA==.',
Ea='Easy:BAAALgAECgUJCAABLgAECgYJBgAGAAAAAA==.',
Ec='Eclipsus:BAAALgADCgcJCAAAAA==.',
Ed='Edamen:BAAALgAECgUJBQAAAA==.',
Eh='Ehrathorn:BAAALgAECgIJAgAAAA==.',
El='Elennoxx:BAAALgAECgEJAQAAAA==.Elf:BAAALgADCgUJBQAAAA==.Elijah:BAAALgAECgYJBgAAAA==.Elonaara:BAAALgADCgEJAQAAAA==.Elunëth:BAAALgADCgQJBAABLgAFFAUJGwAXABEjAA==.',
Ep='Ephie:BAAALgADCgcJBwAAAA==.',
Et='Ether:BAAALgAECgMJBQAAAA==.',
Fa='Faedryl:BAAALgADCgQJBAAAAA==.Fandrin:BAAALgADCgUJBQAAAA==.Farg:BAAALgAECgEJAQAAAA==.Farslaw:BAAALgAECgQJBQAAAA==.',
Fe='Feledara:BAABLgAECn8rAAILAAkJVREtIwDYAQALAAkJVREtIwDYAQAAAA==.Felshort:BAAALgAECgEJAQABLgAFFAQJFQAQAOsfAA==.',
Fi='Fionaweaver:BAAALgADCgIJAgAAAA==.',
Fo='Foebane:BAAALgAECgYJDAABLgAECgYJGwAYADwjAA==.',
Fr='Freezing:BAAALgAECgEJAwAAAA==.Frieren:BAACLgAFFH8ZAAMZAAgJ4ReFCgDLAQAZAAgJ4ReFCgDLAQAaAAIJPiGKAwDFAAAuAAQKfyUABBkACQl9Il0NAFoDABkACQl9Il0NAFoDABoAAQnTIAcNAFkAABsAAQkbDx0aAEcAAAAA.Froslass:BAABLgAECn8ZAAITAAgJfx0SSQDlAQATAAgJfx0SSQDlAQAAAA==.',
Fu='Funk:BAAALgAECgEJAQAAAA==.',
Ge='Gencrocker:BAEALgAECgMJAwABLgAFFAcJHQASAOEkAA==.Getoffenris:BAAALgAFFAMJAwAAAA==.',
Gl='Gloryhammer:BAABLgAECn8lAAQIAAkJHBuNCABPAgAIAAkJHBuNCABPAgAKAAUJKAXGawDLAAAHAAEJaxmmQwEzAAAAAA==.',
Go='Gobbs:BAABLgAECn8dAAMcAAYJABSJCwBzAQAcAAYJ4g+JCwBzAQAYAAYJ8BK2LAAxAQABLgAECggJHgABAJEbAA==.',
Ha='Haldrian:BAAALgAECgcJEAAAAA==.Havack:BAAALgADCgEJAQAAAA==.',
He='Healslvt:BAAALgAECgEJAQAAAA==.Hexkittin:BAABLgAECn8bAAINAAcJVRSIVABeAQANAAcJVRSIVABeAQAAAA==.',
Hi='Hixon:BAAALgADCgMJAgAAAA==.',
Ho='Holyhota:BAACLgAFFH8JAAMdAAQJyRimCgC6AAAdAAMJMB2mCgC6AAAeAAMJQwoSOQCWAAAuAAQKfxcAAx0ACAk7IdELAJMCAB0ACAk7IdELAJMCAB4AAQmED0x5ADAAAAAA.Hop:BAACLgAFFH8GAAIfAAMJdBOFDQDYAAAfAAMJdBOFDQDYAAAuAAQKfzgAAh8ACQkPHFgGAH8CAB8ACQkPHFgGAH8CAAAA.Hota:BAAALgAECgYJBwABLgAFFAQJCQAdAMkYAA==.Hotamnk:BAAALgAFFAIJAwABLgAFFAQJCQAdAMkYAA==.',
If='Iffri:BAAALgADCgEJAQAAAA==.',
In='Inarius:BAAALgAECgEJAQAAAA==.',
Ir='Iraedies:BAAALgADCgEJAgAAAA==.Ironborn:BAAALgAFFAMJAwAAAA==.',
Iv='Ivakor:BAAALgAECgYJEgAAAA==.Ivyy:BAACLgAFFH8TAAIgAAUJKSLhEwB1AQAgAAUJKSLhEwB1AQAuAAQKfxcAAiAACAkSIrkNAMACACAACAkSIrkNAMACAAEuAAUUBwkdABgAPhkA.',
Ja='Jackswagz:BAABLgAECn8pAAMNAAkJHhTaOQDDAQANAAkJHhTaOQDDAQAOAAQJbAddcACUAAAAAA==.Jaszuny:BAABLgAECn8yAAIDAAkJUhnJBQBAAgADAAkJUhnJBQBAAgAAAA==.',
Je='Jezlyn:BAAALgAECgUJBQAAAA==.',
['Jö']='Jösîah:BAAALgAECgMJAwAAAA==.',
Ka='Kaladyn:BAAALgADCgIJAwABLgAECggJFAASAEIaAA==.Kasho:BAAALgAECgIJAgAAAA==.Katsumotosan:BAAALgADCggJDQAAAA==.',
Ke='Kev:BAABLgAECn8qAAQZAAcJ6iSqNABDAgAZAAcJ6iSqNABDAgAbAAIJMiTbDwDEAAAaAAEJAAA8EgAXAAAAAA==.Kevlarr:BAAALgADCgcJBwAAAA==.',
Ko='Kombatgodess:BAAALgADCgcJDQAAAA==.',
Ku='Kurgen:BAAALgADCgUJCgAAAA==.Kurorn:BAAALgAECggJCQAAAA==.',
Kv='Kvasir:BAABLgAECn9BAAITAAkJvBxWFwC4AgATAAkJvBxWFwC4AgAAAA==.',
Ky='Kynolight:BAAALgAECgQJAwAAAA==.',
['Kâ']='Kânna:BAAALgAECgQJBQAAAA==.',
La='Lalaise:BAAALgAECgMJAwAAAA==.Lanaria:BAAALgAECgMJAwAAAA==.Lancayne:BAAALgADCgIJAQAAAA==.',
Li='Lichkingstoy:BAACLgAFFH8WAAIHAAcJGRS8HACNAQAHAAcJGRS8HACNAQAuAAQKfyAAAgcACQljG9oxAFsCAAcACQljG9oxAFsCAAAA.Lieb:BAAALgAECgUJAwAAAA==.Lihrna:BAAALgAECgIJAwAAAA==.Littlecutie:BAAALgADCgMJAwAAAA==.',
Lo='Lolamarie:BAAALgADCgQJCQAAAA==.',
Lu='Lunareclipse:BAAALgAECgIJAgAAAA==.Luniaira:BAAALgAECggJDgAAAA==.Lushara:BAAALgAECgEJAQAAAA==.',
Ma='Maedy:BAAALgADCgQJBAABLgAFFAQJDQAJAIsDAA==.Maegii:BAAALgADCgEJAQAAAA==.Manafist:BAAALgADCgMJAwABLgAECgYJGwAYADwjAA==.Manistas:BAAALgAECgEJAQAAAA==.Manta:BAABLgAECn8gAAMSAAgJKRUuJgAfAQATAAcJXw5HjwBiAQASAAUJjhwuJgAfAQAAAA==.Maroon:BAAALgAECggJEwAAAA==.',
Me='Menasor:BAAALgADCgQJBAAAAA==.',
Mi='Micaa:BAAALgAECgYJEAAAAA==.Minarielle:BAAALgADCgUJBQAAAA==.Mingó:BAAALgAECgUJBwAAAA==.Miracle:BAAALgAFFAMJBAAAAA==.Mirana:BAAALgADCgEJAQAAAA==.Mirzza:BAAALgAECgQJBQAAAA==.Mistake:BAAALgAECgYJEgAAAA==.',
Mo='Mockra:BAAALgAECgQJBgAAAA==.Monkcrocker:BAECLgAFFH8VAAIRAAcJeCQZAQDRAgARAAcJeCQZAQDRAgAuAAQKfxUAAhEABwnxJcANALcCABEABwnxJcANALcCAAEuAAUUBwkdABIA4SQA.',
Mv='Mvmx:BAAALgAECgIJAgAAAA==.',
['Mé']='Méthan:BAAALgADCgQJBAAAAA==.',
Na='Nabarke:BAAALgAECgcJCgAAAA==.Naztherune:BAAALgADCgQJBQAAAA==.',
Ni='Nier:BAAALgAECgQJBwAAAA==.Nightsilver:BAAALgADCgkJIwAAAA==.',
No='Nooxi:BAAALgADCggJCAAAAA==.Nosidh:BAAALgAECgMJBAAAAA==.Nospheratus:BAAALgAFFAMJAwABLgAFFAUJEAASAGULAA==.Notsofresh:BAAALgADCgMJAwAAAA==.',
Nx='Nx:BAAALgAECgEJAQAAAA==.',
Ny='Nylianna:BAACLgAFFH8QAAMHAAQJcBL0YQDkAAAHAAMJThj0YQDkAAAKAAMJMRAILwC1AAAuAAQKf0AAAwcACQkYImkMACsDAAcACQkYImkMACsDAAoACQkjFi0YAEQCAAAA.',
Oa='Oaken:BAAALgADCgkJCQAAAA==.',
Ob='Obscurity:BAABLgAFFH8HAAIQAAQJ2Az+MwDPAAAQAAQJ2Az+MwDPAAAAAA==.',
Og='Ogganborn:BAABLgAECn8iAAIBAAYJFR/ETAC3AQABAAYJFR/ETAC3AQAAAA==.',
Ol='Olovis:BAAALgAECgQJBAAAAA==.',
On='Oneira:BAAALgAECgQJBAAAAA==.',
Or='Orange:BAAALgAECgQJBQAAAA==.Orrark:BAAALgADCgEJAQAAAA==.',
Pi='Pikal:BAABLgAECn8bAAIHAAcJ2hJWlwBDAQAHAAcJ2hJWlwBDAQAAAA==.',
Pr='Priestigory:BAABLgAECn8wAAMRAAkJgh1IDABvAgARAAkJoRxIDABvAgAPAAQJORJAawB5AAAAAA==.',
Pv='Pvtcrocker:BAEALgAFFAEJAQABLgAFFAcJHQASAOEkAA==.',
Py='Pyrithyr:BAABLgAECn8XAAMIAAgJphgFFACJAQAIAAUJbyIFFACJAQAHAAgJ+w/gegB2AQABLgAFFAEJAQAGAAAAAA==.',
Qu='Quelyne:BAAALgADCgMJAwAAAA==.Quink:BAAALgAECgMJAwAAAA==.Quintus:BAAALgAECgUJBgAAAA==.',
Ra='Raelyn:BAAALgAECgUJCgABLgAFFAMJCQAhAIgiAA==.Raevaela:BAAALgADCgQJBwABLgAECgcJFQAPABkcAA==.Railiana:BAABLgAECn8hAAIBAAgJ4AiddgBOAQABAAgJ4AiddgBOAQAAAA==.Ravelin:BAAALgADCgkJGQAAAA==.',
Re='Regrowth:BAABLgAECn8/AAUhAAkJQiGjBQBbAwAhAAkJQiGjBQBbAwAgAAIJqBxWWQCpAAAfAAMJVxWuNgB6AAAiAAEJhhvcXQBPAAAAAA==.Reminesce:BAAALgADCgEJAQAAAA==.',
Rh='Rholune:BAAALgAECgUJDQAAAA==.',
Ro='Roberta:BAAALgADCgQJBgAAAA==.',
Rp='Rplooker:BAAALgADCgcJEgABLgAECgcJFgAPAJwPAA==.',
Ru='Ruby:BAACLgAFFH8OAAIMAAgJNhkRAQD/AQAMAAgJNhkRAQD/AQAuAAQKfxwAAgwACAmbJbUBAGgDAAwACAmbJbUBAGgDAAAA.Ruhai:BAAALgAECgYJCwAAAA==.',
['Rà']='Ràistlin:BAABLgAECn8aAAIZAAYJNA62xAD/AAAZAAYJNA62xAD/AAAAAA==.',
Sa='Saelki:BAAALgAECgMJAwAAAA==.',
Se='Sephiran:BAABLgAECn8wAAMjAAkJ8B0RDgB0AgAjAAkJ8B0RDgB0AgAeAAgJyRd6GAAMAgAAAA==.',
Sh='Shagra:BAAALgAECgcJEQAAAA==.Shagraq:BAAALgADCgEJAQAAAA==.Shielen:BAABLgAECn8bAAIYAAYJPCPgFgDhAQAYAAYJPCPgFgDhAQAAAA==.Shoepert:BAABLgAECn84AAILAAkJbSVeBAAeAwALAAkJbSVeBAAeAwAAAA==.',
Si='Sib:BAAALgAFFAMJAwAAAA==.Sifrina:BAAALgADCgEJAQAAAA==.Sini:BAAALgAECgcJBQAAAA==.Sinna:BAAALgAECgkJBwAAAA==.',
Sj='Sj:BAAALgADCgYJBgABLgAECgYJGwAYADwjAA==.',
So='Southpaw:BAAALgAECgIJAgAAAA==.',
Sp='Splatugle:BAAALgAECgcJBQAAAA==.',
Sq='Squiggles:BAAALgAECgIJAgAAAA==.',
St='Stdot:BAABLgAECn8cAAMTAAkJNxTDTADZAQATAAkJaRDDTADZAQASAAYJ5BSwIgA6AQAAAA==.Stormstrike:BAAALgADCgkJDwAAAA==.',
Sw='Sway:BAAALgAECgUJBwABLgAECgYJBgAGAAAAAA==.',
Ta='Tairn:BAAALgADCgQJBgAAAA==.Taluria:BAAALgAECgcJDwAAAA==.',
Te='Tempus:BAACLgAFFH8VAAIKAAUJ5BsJEgCaAQAKAAUJ5BsJEgCaAQAuAAQKfykABAoACQnEHFYTAHMCAAoACAk7HlYTAHMCAAgAAgndFJE3AH0AAAcAAQn9Ct6nASoAAAAA.Tenletters:BAAALgAFFAIJBAAAAA==.',
Th='That:BAAALgADCgYJBgAAAA==.Thrasius:BAAALgADCgYJBgAAAA==.',
Ti='Tikimon:BAAALgADCgkJJgAAAA==.Tinkernine:BAAALgADCgEJAQAAAA==.',
To='Tobofrog:BAABLgAFFH8FAAIgAAUJ3g5VJQD6AAAgAAUJ3g5VJQD6AAAAAA==.Toboo:BAAALgAECgcJBgAAAA==.Tolocforu:BAAALgAECgQJBgAAAA==.',
Tr='Trainedtiger:BAAALgAFFAEJBAAAAA==.',
Ty='Tyrgrim:BAAALgAECgcJDwAAAA==.',
Ul='Uldyssian:BAAALgAECgMJAwABLgAFFAQJEAAHAHASAA==.Ulfhednósh:BAAALgAECgIJAgAAAA==.',
Un='Union:BAAALgAECgEJAgAAAA==.Unwavering:BAAALgADCgEJAQAAAA==.',
Up='Uppies:BAAALgAECgQJCAAAAA==.',
Uw='Uwuforyou:BAABLgAECn8gAAQEAAgJIxRaHgCCAQAEAAgJIxRaHgCCAQADAAUJpwzLHQCpAAAFAAEJ5wEKOQEXAAAAAA==.',
Va='Valalexis:BAAALgAECgEJAQAAAA==.',
Ve='Velawynn:BAACLgAFFH8bAAIdAAcJ+hsVBAAmAgAdAAcJ+hsVBAAmAgAuAAQKfy4AAx0ACQm6HhsFAP8CAB0ACQm6HhsFAP8CACMABAlhDkVXALMAAAAA.Velladonna:BAAALgAECgYJDAAAAA==.Veronica:BAACLgAFFH8aAAMTAAcJfh0KFQAkAgATAAYJPBkKFQAkAgASAAYJKh8cBABvAQAuAAQKfx0AAxIACQlXI9cCABkDABIACQlXI9cCABkDABMABgn9GjV+AIcBAAEuAAUUCQkXACMA+xsA.',
Vh='Vhenir:BAAALgADCgcJDQAAAA==.',
Vi='Vixa:BAAALgAECgQJBwAAAA==.',
Vo='Voidbro:BAAALgAECgMJBQAAAA==.',
Wy='Wyrdengilly:BAAALgADCgYJBgAAAA==.',
Xa='Xamot:BAAALgAFFAEJAQABLgAFFAUJFAAJABETAA==.Xarou:BAAALgAECgQJBgAAAA==.',
Ya='Yanyan:BAAALgAECgYJEwAAAA==.',
Zi='Zilgius:BAABLgAECn8dAAMMAAcJSRyKGQBsAQALAAcJZRmiNgBsAQAMAAYJ7h2KGQBsAQABLgAECgkJMAAjAPAdAA==.Zinjari:BAAALgADCgEJAQAAAA==.',
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
