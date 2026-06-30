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

local lookup = {'Mage-Frost','Monk-Windwalker','Monk-Brewmaster','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Druid-Restoration','Druid-Guardian','Hunter-Survival','Paladin-Retribution','Priest-Discipline','Shaman-Restoration','Paladin-Holy','DemonHunter-Devourer','Monk-Mistweaver','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Unknown-Unknown','Warrior-Fury','Warrior-Arms','Rogue-Subtlety','Priest-Holy','Priest-Shadow','Hunter-Marksmanship','Druid-Balance','Druid-Feral','Paladin-Protection','Shaman-Elemental','Mage-Arcane','Evoker-Preservation','Evoker-Augmentation','Hunter-BeastMastery',}
local provider = {region='US',realm='Balnazzar',name='US',type='weekly',zone=46,date='2026-06-27',data={Ad='Adrianmonk:BAAALgAECgYJDgAAAA==.',
Ak='Aktuu:BAABLgAECn8WAAIBAAgJShGNBwA/AQABAAgJShGNBwA/AQAAAA==.',
An='Andeys:BAAALgAECggJDwAAAA==.Angelius:BAABLgAFFH8FAAICAAMJrA1xJwC0AAACAAMJrA1xJwC0AAAAAA==.',
Ar='Arasaka:BAAALgAECgIJAgABLgAECgkJHgADAJkTAA==.',
Ba='Badgirl:BAAALgAECgQJBAAAAA==.Baggigy:BAACLgAFFH8KAAMEAAMJehF0FgDWAAAEAAMJehF0FgDWAAAFAAIJUwbP+QBzAAAuAAQKfygABAQACQnTHaEAAOIBAAQABwmwHKEAAOIBAAUABgnUHFabADMBAAYABAlABFtKAGUAAAAA.Balance:BAABLgAFFH8IAAMHAAMJcA+MQwCkAAAHAAMJcA+MQwCkAAAIAAEJjgdwQQApAAAAAA==.Bandwagon:BAAALgAECgYJCwAAAA==.',
Be='Bentpanda:BAABLgAECn8YAAIJAAkJaBblEwAGAgAJAAkJaBblEwAGAgAAAA==.',
Bh='Bhain:BAABLgAFFH8WAAIKAAUJrB/CCABQAQAKAAUJrB/CCABQAQAAAA==.',
Bi='Bigcocko:BAACLgAFFH8hAAIHAAgJ3h0dBADeAgAHAAgJ3h0dBADeAgAuAAQKfy4AAgcACQmGJYkCAHIDAAcACQmGJYkCAHIDAAAA.Bigwheels:BAAALgAECgMJAwAAAA==.Birchwood:BAAALgAECgYJBgAAAA==.',
Bl='Blarrg:BAAALgAFFAEJAQABLgAFFAMJCgAEAHoRAA==.Blocks:BAAALgADCgEJAgAAAA==.',
Bo='Boneriffik:BAAALgAECgUJDQAAAA==.Bossfury:BAAALgAECggJCQAAAA==.',
Br='Brogh:BAABLgAECn8fAAILAAkJ4hSEEQBcAgALAAkJ4hSEEQBcAgAAAA==.',
Bu='Buffallo:BAABLgAECn8WAAIMAAkJ/AwuOQCdAQAMAAkJ/AwuOQCdAQAAAA==.',
Ca='Camouflage:BAABLgAECn9AAAIJAAkJBCW/AgAYAwAJAAkJBCW/AgAYAwAAAA==.Caneangel:BAAALgAFFAIJAgAAAA==.',
Ch='Charvhug:BAAALgAFFAEJAQABLgAFFAIJBQAKAAcVAA==.Chilyn:BAABLgAECn8ZAAINAAUJESD6AwARAQANAAUJESD6AwARAQAAAA==.',
Co='Coldnbloodÿ:BAABLgAECn8cAAIOAAYJEw6qoQDgAAAOAAYJEw6qoQDgAAAAAA==.Corrupthell:BAABLgAECn8ZAAIFAAgJihGjiABTAQAFAAgJihGjiABTAQAAAA==.Cowi:BAABLgAECn8WAAIMAAYJ+g6sYwAwAQAMAAYJ+g6sYwAwAQABLgAFFAIJBwABAF4OAA==.',
Cr='Crispaw:BAAALgAECgYJCwAAAA==.Crispo:BAAALgAECgYJDQAAAA==.',
Da='Dadbod:BAAALgAECgcJEQAAAA==.Dadsmemory:BAAALgAECgEJAQAAAA==.Darylbaryl:BAACLgAFFH8FAAIBAAMJXgnEkQCzAAABAAMJXgnEkQCzAAAuAAQKfxgAAgEACAlKGilcACUCAAEACAlKGilcACUCAAAA.Daswassap:BAAALgAECgYJCgAAAA==.',
De='Def:BAAALgAECgIJBgAAAA==.Del:BAAALgAECgQJBgAAAA==.',
Dk='Dkdogg:BAAALgAECgEJAQAAAA==.',
Dr='Dragonfist:BAABLgAECn8eAAQDAAkJmRMYMACVAQADAAcJexMYMACVAQACAAUJOhb6OwAsAQAPAAIJrBwSnQBeAAAAAA==.Driver:BAECLgAFFH8QAAMQAAUJtgsZSQA1AQAQAAUJtgsZSQA1AQARAAIJ3QZyEQCDAAAuAAQKfzUAAxAACAniHvMZALkCABAACAniHvMZALkCABIABgniGNEUAKQBAAAA.',
['Dä']='Däenerys:BAABLgAECn8VAAIFAAkJyA6/TgDWAQAFAAkJyA6/TgDWAQAAAA==.',
Es='Esuna:BAAALgAECgMJBAAAAA==.',
Ew='Ewwf:BAAALgAECgMJBQABLgAFFAgJEwAOABEfAA==.',
Ex='Exemplio:BAABLgAECn8lAAIDAAkJmCTmAwAPAwADAAkJmCTmAwAPAwAAAA==.',
Fa='Fairyboy:BAAALgADCgYJDAAAAA==.',
Fe='Feel:BAAALgADCgQJBAAAAA==.Felbeast:BAAALgAECgEJAQABLgAECgkJHgADAJkTAA==.Felfirehell:BAAALgADCgMJBgAAAA==.',
Fi='Fininho:BAAALgADCgEJAQABLgAFFAEJAQATAAAAAA==.',
Fl='Flame:BAAALgAECgUJBQAAAA==.',
Fo='Foer:BAAALgAECgEJAgAAAA==.',
Fr='Frahmunda:BAAALgAECgIJBAAAAA==.Frosty:BAABLgAECn8UAAIBAAcJzw3UqACIAQABAAcJzw3UqACIAQAAAA==.Frybeam:BAAALgAECgIJAwAAAA==.',
Gi='Gilfoyle:BAAALgAECgIJBwAAAA==.Giovahni:BAACLgAFFH8WAAIOAAcJ7RX4IACyAQAOAAcJ7RX4IACyAQAuAAQKfzEAAg4ACAnXH68fAFcCAA4ACAnXH68fAFcCAAAA.',
Gl='Glaivemstake:BAAALgADCgYJDwAAAA==.',
Go='Goat:BAAALgADCgUJCAABLgAECgkJHgADAJkTAA==.',
Gr='Gristlecharm:BAABLgAECn8UAAIBAAcJsAVXyABYAQABAAcJsAVXyABYAQAAAA==.',
Gw='Gwevon:BAAALgAECgMJAwAAAA==.',
Ha='Hateeho:BAABLgAECn8cAAIUAAgJ3hP0OwBWAQAUAAgJ3hP0OwBWAQAAAA==.Haxxen:BAAALgAECgQJBAAAAA==.',
Ho='Holylight:BAAALgAECgMJBQAAAA==.',
Ja='Jahblestraza:BAAALgAECgEJAwAAAA==.Janaria:BAABLgAFFH8LAAIVAAMJER4QHgAAAQAVAAMJER4QHgAAAQAAAA==.Jandlion:BAAALgADCgYJBgAAAA==.Jaysix:BAAALgAECgUJBQAAAA==.',
Je='Jedah:BAAALgAECgEJBAAAAA==.Jessiescool:BAABLgAECn8aAAIKAAYJNQ7SlwBOAQAKAAYJNQ7SlwBOAQAAAA==.',
Ji='Jinxnyx:BAABLgAECn8YAAIIAAkJMw4wEAB1AQAIAAkJMw4wEAB1AQAAAA==.',
Jo='Johnnydeman:BAAALgADCgUJBQAAAA==.Jordanpoole:BAAALgAECgQJCgAAAA==.Jovarix:BAAALgAECgUJBQAAAA==.Joyluka:BAACLgAFFH8SAAIKAAMJJCMzGwDBAAAKAAMJJCMzGwDBAAAuAAQKfxsAAgoABwmLJFUnAGYCAAoABwmLJFUnAGYCAAAA.',
Ka='Kalvin:BAABLgAECn8dAAIWAAgJiA6QJQBpAQAWAAgJiA6QJQBpAQAAAA==.Kanari:BAABLgAECn8mAAQXAAkJPhAANAA2AQAXAAcJlRMANAA2AQALAAUJxgnYSADiAAAYAAgJNQaoVwC1AAAAAA==.',
Ke='Kelak:BAAALgADCgEJAgAAAA==.',
Ki='Killerkid:BAAALgADCgUJBwAAAA==.Kitaravana:BAAALgAECgIJBgAAAA==.',
La='Lagoles:BAACLgAFFH8MAAIJAAYJlBJcAgBLAQAJAAYJlBJcAgBLAQAuAAQKfzoAAwkACQkuI1sDAAIDAAkACQmcIlsDAAIDABkACAl9H5oTAJgCAAAA.Lance:BAAALgAECgUJBQAAAA==.Landis:BAAALgAECgUJEAAAAA==.',
Le='Leaf:BAAALgAECgIJAwABLgAECgkJQAAJAAQlAA==.Leoben:BAAALgAECgEJBAAAAA==.',
Li='Liltracey:BAAALgAFFAIJAwABLgAFFAMJCAAHAHAPAA==.Listeriah:BAAALgADCgUJBgAAAA==.',
Lo='Lockbounty:BAAALgAECgEJAQAAAA==.',
Ma='Mambrú:BAAALgAECgMJAwABLgAECgkJGAAIADMOAA==.',
Mi='Miggles:BAACLgAFFH8QAAIHAAMJRRJaPgC3AAAHAAMJRRJaPgC3AAAuAAQKfzEAAwcACQk5IPYKAA4DAAcACQk5IPYKAA4DABoAAglmDk1sAG8AAAAA.Milo:BAABLgAFFH8MAAIbAAMJbhl3DADuAAAbAAMJbhl3DADuAAAAAA==.',
Mk='Mk:BAEBLgAECn9NAAQCAAkJiiLIAAAYAgACAAgJ3SXIAAAYAgADAAUJpgkaWACoAAAPAAEJiAdRxgAlAAAAAA==.',
Mo='Monzo:BAABLgAECn8kAAMFAAgJ2iEEGQDmAgAFAAgJ2iEEGQDmAgAGAAIJ1A+SPQBcAAABLgAFFAMJCAAHAHAPAA==.Morgane:BAAALgAECgcJCAAAAA==.Morvayne:BAACLgAFFH8KAAIBAAMJvRbjfQDbAAABAAMJvRbjfQDbAAAuAAQKfz4AAgEACQmqIEwRAPMCAAEACQmqIEwRAPMCAAEuAAUUBgkMAAkAlBIA.Mozzarella:BAAALgAECgEJAQABLgAFFAMJCAAQAEYUAA==.',
My='Myneemo:BAABLgAECn8gAAIBAAkJ4RqPLABnAgABAAkJ4RqPLABnAgAAAA==.Myro:BAABLgAECn8nAAIKAAgJJw7+CwDmAAAKAAgJJw7+CwDmAAAAAA==.',
No='Nomoneydown:BAAALgAECgIJBgAAAA==.Nosam:BAABLgAECn8hAAIQAAcJwhMkaQBqAQAQAAcJwhMkaQBqAQAAAA==.',
Nt='Nthegreat:BAAALgAECggJDAAAAA==.',
Nw='Nwf:BAABLgAECn8aAAIUAAgJHRmkJwC9AQAUAAgJHRmkJwC9AQAAAA==.',
['Nè']='Nèbula:BAABLgAECn8uAAQNAAgJhBkUFwBSAgANAAgJhBkUFwBSAgAcAAYJkxNqAwDIAAAKAAEJdAc0uwEmAAAAAA==.',
Or='Ornatas:BAACLgAFFH8NAAIdAAUJMiF2GgBHAQAdAAUJMiF2GgBHAQAuAAQKfxgAAh0ACAm0HJYVAG8CAB0ACAm0HJYVAG8CAAAA.',
Pa='Pandamonium:BAABLgAECn8dAAQPAAgJPxT8KwBWAQAPAAgJPxT8KwBWAQADAAQJ+APFbgBnAAACAAEJOAlIswAkAAAAAA==.',
Pe='Perdyblues:BAACLgAFFH8JAAIQAAMJgwKSlQCXAAAQAAMJgwKSlQCXAAAuAAQKfx8AAhAACAmzChx3AEsBABAACAmzChx3AEsBAAAA.',
Po='Pom:BAAALgAECgEJAwAAAA==.',
Ps='Psymie:BAAALgAECgYJEgAAAA==.',
Qi='Qiana:BAABLgAECn8dAAINAAcJvxN8LgCjAQANAAcJvxN8LgCjAQAAAA==.',
Qu='Quickstabbin:BAABLgAECn8bAAICAAgJCQwFSADgAAACAAgJCQwFSADgAAAAAA==.Quinoaffle:BAAALgAECgEJAQABLgAFFAMJCAAQAEYUAA==.',
Ra='Rainootra:BAAALgAECggJEQAAAA==.Ralan:BAAALgAECgYJBwABLgAFFAIJBwABAF4OAA==.Raziel:BAAALgADCgEJAQAAAA==.',
Re='Rebirthn:BAAALgAECgcJCQAAAA==.Redronz:BAAALgADCgUJCAABLgAECgkJHgADAJkTAA==.',
Ri='Riffroot:BAAALgADCgEJAQAAAA==.Ritheran:BAAALgAECgMJAwABLgAECgkJHgADAJkTAA==.',
Ro='Rocny:BAAALgAECgEJAQAAAA==.',
Sa='Saerus:BAACLgAFFH8HAAIBAAMJegxCIwDFAAABAAMJegxCIwDFAAAuAAQKfx4AAwEACQkqEChcAMoBAAEACQnjDyhcAMoBAB4ABwkZCWIOAJMAAAAA.',
Sc='Scylla:BAACLgAFFH8SAAIfAAcJvx0uAQBCAgAfAAcJvx0uAQBCAgAuAAQKfywAAx8ACQkAJh8AAOUDAB8ACQkAJh8AAOUDACAAAQmlDkVeAEIAAAEuAAQKBgkPABMAAAAA.',
Se='Sephiroth:BAABLgAECn8VAAIKAAkJDhSIQgAdAgAKAAkJDhSIQgAdAgAAAA==.Serephant:BAAALgADCgEJAgAAAA==.',
Si='Siege:BAAALgADCgYJBgABLgAECgcJGAAPAPwfAA==.Siegeshock:BAAALgADCgUJBgABLgAECgcJGAAPAPwfAA==.Silentbobb:BAAALgADCgcJBwAAAA==.',
Sn='Snow:BAAALgAFFAEJAgABLgAECgkJQAAJAAQlAA==.',
So='Soothe:BAABLgAECn8XAAIXAAYJgxkzJQCbAQAXAAYJgxkzJQCbAQAAAA==.',
St='Stormride:BAAALgAECgIJAwAAAA==.',
Sw='Swaggasaurus:BAABLgAECn8nAAMKAAkJ+B5AJQBvAgAKAAkJ+B5AJQBvAgANAAEJlwPukQAsAAAAAA==.',
Sy='Sylarien:BAAALgAECgYJCgAAAA==.Syriena:BAAALgADCggJAwAAAA==.',
Ta='Tadok:BAAALgADCgUJBQAAAA==.Talset:BAACLgAFFH8WAAIUAAQJbh3UFABlAQAUAAQJbh3UFABlAQAuAAQKfx8AAhQACAlEHwgUAFECABQACAlEHwgUAFECAAAA.',
Te='Tengoo:BAAALgAECgUJBQAAAA==.',
Th='Thewaitress:BAABLgAFFH8FAAIKAAIJBxV5mACHAAAKAAIJBxV5mACHAAAAAA==.Thylight:BAAALgAECgYJCAAAAA==.',
To='Tooperdy:BAAALgADCgIJAgAAAA==.',
Tr='Trappe:BAAALgADCgcJBwAAAA==.Traumatize:BAAALgADCgEJAQABLgAECgcJGAAPAPwfAA==.',
Tu='Tusker:BAAALgAECgcJDQAAAA==.',
Tw='Twostunz:BAAALgADCgcJDAAAAA==.',
Ty='Tysotcan:BAAALgAFFAIJAgAAAA==.',
Ur='Ursalvation:BAAALgADCgUJBQAAAA==.',
Va='Vad:BAAALgAECgIJBwAAAA==.',
Ve='Veew:BAABLgAECn8XAAMUAAgJ8RGROgC8AQAUAAgJOhGROgC8AQAVAAUJshEKGwAZAQAAAA==.',
Vu='Vutraat:BAAALgADCgEJAgAAAA==.',
Vy='Vynaca:BAAALgAECgIJBwAAAA==.',
Wa='Warpedshadow:BAAALgAECggJCwAAAA==.',
Wh='Whitegoddess:BAABLgAECn8pAAIhAAgJTQy8awBqAQAhAAgJTQy8awBqAQAAAA==.',
Wo='Wontan:BAAALgAECgcJCAAAAA==.',
Wu='Wukong:BAAALgAECgQJBAAAAA==.',
Xa='Xania:BAAALgAECgIJBwAAAA==.',
Yu='Yungmage:BAABLgAECn8dAAIBAAcJYBuQggDMAQABAAcJYBuQggDMAQAAAA==.',
Za='Zaifu:BAAALgAECgIJBwAAAA==.',
Zi='Ziggy:BAABLgAECn8ZAAIBAAkJABhSRQBoAgABAAkJABhSRQBoAgAAAA==.',
['Èl']='Èlfman:BAABLgAECn8VAAIHAAcJJhjeNADIAQAHAAcJJhjeNADIAQAAAA==.',
['Øm']='Ømega:BAAALgAECgEJAQAAAA==.',
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
