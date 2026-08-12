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

local lookup = {'Mage-Frost','Monk-Windwalker','Monk-Brewmaster','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Druid-Restoration','Druid-Guardian','Hunter-Survival','Hunter-BeastMastery','Paladin-Retribution','Priest-Discipline','Shaman-Restoration','Paladin-Holy','DemonHunter-Devourer','Monk-Mistweaver','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','DemonHunter-Havoc','Warrior-Fury','Warrior-Arms','Rogue-Subtlety','Priest-Holy','Priest-Shadow','Hunter-Marksmanship','Druid-Balance','Druid-Feral','Paladin-Protection','Shaman-Elemental','Mage-Arcane','Evoker-Preservation','Evoker-Augmentation','Unknown-Unknown',}
local provider = {region='US',realm='Balnazzar',name='US',type='weekly',zone=46,date='2026-08-11',data={Ad='Adrianmonk:BAAALgAECgYJDgAAAA==.',
Ak='Aktuu:BAABLgAECn8ZAAIBAAgJ2BLtEgBFAQABAAgJ2BLtEgBFAQAAAA==.',
An='Anabel:BAAALgAECgEJAQAAAA==.Andeys:BAAALgAECggJDwAAAA==.Angelius:BAABLgAFFH8FAAICAAMJrA1xJwC0AAACAAMJrA1xJwC0AAAAAA==.Antagonist:BAAALgAFFAEJAwAAAA==.',
Ar='Arasaka:BAAALgAECgIJAgABLgAECgkJHgADAJkTAA==.',
Ba='Backscratch:BAAALgADCgMJAwAAAA==.Badgirl:BAAALgAECgQJBAAAAA==.Baggigy:BAACLgAFFH8MAAMEAAUJ3A50FgDWAAAEAAQJ3A50FgDWAAAFAAMJUwbP+QBzAAAuAAQKfy8ABAQACQmhH6EBACoCAAQABwlrIKEBACoCAAUABgnUHFabADMBAAYABAlABFtKAGUAAAAA.Balance:BAABLgAFFH8IAAMHAAMJcA+MQwCkAAAHAAMJcA+MQwCkAAAIAAEJjgdwQQApAAAAAA==.Bandwagon:BAAALgAECgYJCwAAAA==.',
Be='Bentpanda:BAABLgAECn8bAAMJAAkJwxflEwAGAgAJAAkJaBblEwAGAgAKAAMJfh8+GgAPAQAAAA==.',
Bh='Bhain:BAABLgAFFH8aAAILAAUJrB+HFQBLAQALAAUJrB+HFQBLAQAAAA==.',
Bi='Bigcocko:BAACLgAFFH8kAAIHAAkJUR8dBADeAgAHAAkJUR8dBADeAgAuAAQKfy8AAgcACQmGJYkCAHIDAAcACQmGJYkCAHIDAAAA.Bigwheels:BAAALgAECgQJBQAAAA==.Birchwood:BAAALgAECgYJBgAAAA==.',
Bl='Blarrg:BAAALgAFFAEJAQABLgAFFAUJDAAEANwOAA==.Blocks:BAAALgADCgEJAgAAAA==.',
Bo='Boneriffik:BAAALgAECgUJDQAAAA==.Bossfury:BAAALgAECggJCQAAAA==.',
Br='Brogh:BAABLgAECn8gAAIMAAkJ5RSEEQBcAgAMAAkJ5RSEEQBcAgAAAA==.',
Bu='Buffallo:BAABLgAECn8WAAINAAkJ/AwuOQCdAQANAAkJ/AwuOQCdAQAAAA==.',
Ca='Camouflage:BAABLgAECn9AAAIJAAkJBCW/AgAYAwAJAAkJBCW/AgAYAwAAAA==.Caneangel:BAAALgAFFAIJAgAAAA==.',
Ch='Charvhug:BAAALgAFFAEJAQABLgAFFAIJBgALAAcVAA==.Chilyn:BAABLgAECn8tAAIOAAgJlh6iAQCaAgAOAAgJlh6iAQCaAgAAAA==.',
Co='Coldnbloodÿ:BAABLgAECn8cAAIPAAYJEw6qoQDgAAAPAAYJEw6qoQDgAAAAAA==.Corrupthell:BAABLgAECn8cAAIFAAkJPRGjiABTAQAFAAkJPRGjiABTAQAAAA==.Cowi:BAABLgAECn8XAAINAAYJSQ+sYwAwAQANAAYJSQ+sYwAwAQABLgAFFAIJBwABAF4OAA==.',
Cr='Crispaw:BAAALgAECgYJCwAAAA==.Crispo:BAAALgAECgYJDQAAAA==.',
Da='Dadbod:BAAALgAECgcJEQAAAA==.Dadsmemory:BAAALgAECgEJAQAAAA==.Darylbaryl:BAACLgAFFH8FAAIBAAMJXgnEkQCzAAABAAMJXgnEkQCzAAAuAAQKfxgAAgEACAlKGilcACUCAAEACAlKGilcACUCAAAA.Daswassap:BAAALgAECgYJCgAAAA==.',
De='Deathien:BAAALgADCgUJBQAAAA==.Def:BAAALgAECgIJBgAAAA==.Del:BAAALgAECgQJBgAAAA==.',
Dk='Dkdogg:BAAALgAECgEJAQAAAA==.',
Dr='Dragonfist:BAABLgAECn8eAAQDAAkJmRMYMACVAQADAAcJexMYMACVAQACAAUJOhb6OwAsAQAQAAIJrBwSnQBeAAAAAA==.Driver:BAECLgAFFH8RAAMRAAUJtgsZSQA1AQARAAUJtgsZSQA1AQASAAIJlwhyEQCDAAAuAAQKfzUAAxEACAniHvMZALkCABEACAniHvMZALkCABMABgniGNEUAKQBAAAA.',
['Dä']='Däenerys:BAABLgAECn8VAAIFAAkJyA6/TgDWAQAFAAkJyA6/TgDWAQAAAA==.',
Ee='Eenee:BAAALgADCgEJAQAAAA==.',
Es='Esuna:BAAALgAECgMJBAAAAA==.',
Ew='Ewwf:BAAALgAECgMJBQABLgAFFAgJEwAPABEfAA==.',
Ex='Exemplio:BAABLgAECn8lAAIDAAkJmCTmAwAPAwADAAkJmCTmAwAPAwAAAA==.',
Fa='Fairyboy:BAAALgADCgYJDAAAAA==.',
Fe='Feel:BAAALgADCgQJBAAAAA==.Felbeast:BAAALgAECgEJAQABLgAECgkJHgADAJkTAA==.Felfirehell:BAAALgADCgMJBgAAAA==.',
Fi='Fininho:BAAALgADCgEJAQABLgAFFAEJBQAQAB4MAA==.',
Fl='Flame:BAAALgAECgUJBQAAAA==.',
Fo='Foer:BAAALgAECgEJAgAAAA==.',
Fr='Frahmunda:BAAALgAECgIJBAAAAA==.Frosty:BAABLgAECn8UAAIBAAcJzw3UqACIAQABAAcJzw3UqACIAQAAAA==.Frybeam:BAAALgAECgIJAwAAAA==.',
Gi='Gilfoyle:BAAALgAECgIJBwAAAA==.Giovahni:BAACLgAFFH8bAAMPAAcJ7RX4IACyAQAPAAcJ7RX4IACyAQAUAAEJHQwAIAA/AAAuAAQKfzEAAg8ACAnXH68fAFcCAA8ACAnXH68fAFcCAAAA.',
Gl='Glaivemstake:BAAALgADCgYJDwAAAA==.',
Go='Goat:BAAALgADCgUJCAABLgAECgkJHgADAJkTAA==.',
Gr='Gristlecharm:BAABLgAECn8UAAIBAAcJsAVXyABYAQABAAcJsAVXyABYAQAAAA==.',
Gu='Guz:BAAALgAECgMJAwAAAA==.',
Gw='Gwevon:BAAALgAECgMJAwAAAA==.',
Ha='Hateeho:BAABLgAECn8cAAIVAAgJ3hP0OwBWAQAVAAgJ3hP0OwBWAQAAAA==.Haxxen:BAAALgAECgQJBAAAAA==.',
He='Hellmakerr:BAAALgADCgUJBQAAAA==.Hellspread:BAAALgAECgEJAQAAAA==.',
Ho='Holylight:BAAALgAECgMJBQAAAA==.',
Ja='Jahblestraza:BAAALgAECgEJAwAAAA==.Janaria:BAABLgAFFH8NAAIWAAMJER4QHgAAAQAWAAMJER4QHgAAAQAAAA==.Jandlion:BAAALgADCgYJBgAAAA==.Jaysix:BAAALgAECgUJBQAAAA==.',
Je='Jedah:BAAALgAECgEJBAAAAA==.Jessiescool:BAABLgAECn8aAAILAAYJNQ7SlwBOAQALAAYJNQ7SlwBOAQAAAA==.',
Ji='Jinxnyx:BAABLgAECn8YAAIIAAkJMw4wEAB1AQAIAAkJMw4wEAB1AQAAAA==.',
Jo='Johnnydeman:BAAALgADCgUJBQAAAA==.Jordanpoole:BAAALgAECgQJCgAAAA==.Jovarix:BAABLgAECn8gAAINAAcJ2x95AwB8AgANAAcJ2x95AwB8AgAAAA==.Joyluka:BAACLgAFFH8XAAILAAMJ0CNGLgDTAAALAAMJ0CNGLgDTAAAuAAQKfxsAAgsABwmLJFUnAGYCAAsABwmLJFUnAGYCAAAA.',
Ka='Kadris:BAAALgAECgQJCAAAAA==.Kalvin:BAABLgAECn8dAAIXAAgJiA6QJQBpAQAXAAgJiA6QJQBpAQAAAA==.Kanari:BAABLgAECn8pAAQYAAkJvhEANAA2AQAYAAcJlRMANAA2AQAMAAUJqw3YSADiAAAZAAgJNQaoVwC1AAAAAA==.Kanaroid:BAAALgAECgEJAQAAAA==.Karincross:BAAALgAECggJCAAAAA==.',
Ke='Kelak:BAAALgADCgEJAgAAAA==.',
Ki='Killerkid:BAAALgADCgUJBwAAAA==.Kitaravana:BAAALgAECgIJBgAAAA==.',
La='Lagoles:BAACLgAFFH8PAAMJAAkJVBKlAgC6AQAJAAgJUhKlAgC6AQAKAAEJZxJqXABhAAAuAAQKfzsABAkACQnfI1sDAAIDAAkACQmcIlsDAAIDABoACAl9H5oTAJgCAAoAAQkmIXI/AF8AAAAA.Lance:BAAALgAECgUJBQAAAA==.Landis:BAAALgAECgUJEAAAAA==.',
Le='Leaf:BAAALgAECgIJAwABLgAECgkJQAAJAAQlAA==.Leoben:BAAALgAECgEJBAAAAA==.',
Li='Liltracey:BAAALgAFFAIJAwABLgAFFAMJCAAHAHAPAA==.Linhao:BAAALgAECgEJAQAAAA==.Listeriah:BAAALgADCgUJBgAAAA==.',
Lo='Lockbounty:BAAALgAECgEJAQAAAA==.',
Ma='Macoroni:BAAALgAECgYJCAAAAA==.Malkwas:BAAALgAECgQJBAAAAA==.Mambrú:BAAALgAECgMJAwABLgAECgkJGAAIADMOAA==.',
Mi='Miggles:BAACLgAFFH8QAAIHAAMJRRJaPgC3AAAHAAMJRRJaPgC3AAAuAAQKfzEAAwcACQk5IPYKAA4DAAcACQk5IPYKAA4DABsAAglmDk1sAG8AAAAA.Milo:BAABLgAFFH8MAAIcAAMJbhl3DADuAAAcAAMJbhl3DADuAAAAAA==.Mizzen:BAAALgAECgEJAQABLgAFFAcJIQAZAKMVAA==.',
Mk='Mk:BAEBLgAECn9NAAQCAAkJiiIfBgAfAwACAAgJ3SUfBgAfAwADAAUJpgkaWACoAAAQAAEJiAdRxgAlAAAAAA==.',
Mo='Monzo:BAABLgAECn8kAAMFAAgJ2iEEGQDmAgAFAAgJ2iEEGQDmAgAGAAIJ1A+SPQBcAAABLgAFFAMJCAAHAHAPAA==.Morgane:BAAALgAECgkJCAAAAA==.Morvayne:BAACLgAFFH8MAAIBAAMJrxhJPADVAAABAAMJrxhJPADVAAAuAAQKfz4AAgEACQmqIEwRAPMCAAEACQmqIEwRAPMCAAEuAAUUCQkPAAkAVBIA.Mozzarella:BAAALgAECgkJCQABLgAFFAMJCAARAEYUAA==.',
My='Myneemo:BAABLgAECn8gAAIBAAkJ4RqPLABnAgABAAkJ4RqPLABnAgAAAA==.Myro:BAABLgAECn8nAAILAAgJJw4pIQDbAAALAAgJJw4pIQDbAAAAAA==.',
No='Nomoneydown:BAAALgAECgIJBgAAAA==.Nosam:BAABLgAECn8hAAIRAAcJwhMkaQBqAQARAAcJwhMkaQBqAQAAAA==.',
Nt='Nthegreat:BAAALgAECggJDAAAAA==.',
Nw='Nwf:BAABLgAECn8aAAIVAAgJHRmkJwC9AQAVAAgJHRmkJwC9AQAAAA==.',
['Nè']='Nèbula:BAABLgAECn8vAAQOAAkJvxgUFwBSAgAOAAkJvxgUFwBSAgAdAAYJkxMsCgC/AAALAAEJdAc0uwEmAAAAAA==.',
Or='Ornatas:BAACLgAFFH8OAAIeAAYJuR92GgBHAQAeAAYJuR92GgBHAQAuAAQKfxoAAh4ACQkhIZYVAG8CAB4ACQkhIZYVAG8CAAAA.',
Pa='Pandamonium:BAABLgAECn8dAAQQAAgJPxT8KwBWAQAQAAgJPxT8KwBWAQADAAQJ+APFbgBnAAACAAEJOAlIswAkAAAAAA==.',
Pe='Perdyblues:BAACLgAFFH8QAAIRAAQJ6gJiPgCbAAARAAQJ6gJiPgCbAAAuAAQKfyAAAhEACAkEDBx3AEsBABEACAkEDBx3AEsBAAAA.',
Po='Pom:BAAALgAECgEJAwAAAA==.',
Ps='Psymie:BAABLgAECn8zAAIRAAkJJRiEAwBdAgARAAkJJRiEAwBdAgAAAA==.',
Qi='Qiana:BAABLgAECn8kAAMOAAcJvxN8LgCjAQAOAAcJvxN8LgCjAQALAAIJewaGcgAgAAABLgAECgkJIwAYAL4bAA==.',
Qu='Quickstabbin:BAABLgAECn8bAAICAAgJCQwFSADgAAACAAgJCQwFSADgAAAAAA==.Quinoaffle:BAAALgAECgEJAQABLgAFFAMJCAARAEYUAA==.',
Ra='Rainootra:BAABLgAECn8gAAIcAAgJ5g1yBQARAQAcAAgJ5g1yBQARAQAAAA==.Ralan:BAAALgAECgYJCAABLgAFFAIJBwABAF4OAA==.Raziel:BAAALgADCgEJAQAAAA==.',
Re='Rebirthn:BAAALgAECgcJCQAAAA==.Redronz:BAAALgADCgUJCAABLgAECgkJHgADAJkTAA==.',
Ri='Riffroot:BAAALgADCgMJBAABLgAFFAUJDAAEANwOAA==.Ritheran:BAAALgAECgMJAwABLgAECgkJHgADAJkTAA==.',
Ro='Rocny:BAAALgAECgEJAQAAAA==.',
Sa='Saerus:BAACLgAFFH8KAAIBAAMJORIGQADHAAABAAMJORIGQADHAAAuAAQKfx4AAwEACQkqEChcAMoBAAEACQnjDyhcAMoBAB8ABwkZCWIOAJMAAAAA.',
Sc='Scylla:BAACLgAFFH8SAAIgAAcJvx0uAQBCAgAgAAcJvx0uAQBCAgAuAAQKfywAAyAACQkAJh8AAOUDACAACQkAJh8AAOUDACEAAQmlDkVeAEIAAAEuAAQKBgkPACIAAAAA.',
Se='Sephiroth:BAABLgAECn8VAAILAAkJDhSIQgAdAgALAAkJDhSIQgAdAgAAAA==.Serephant:BAAALgADCgEJAgAAAA==.',
Si='Siege:BAAALgADCgYJBgABLgAECgcJHAAQALYgAA==.Siegeshock:BAAALgADCgUJBgABLgAECgcJHAAQALYgAA==.Silentbobb:BAAALgADCgcJBwAAAA==.',
Sn='Snow:BAAALgAFFAEJAgABLgAECgkJQAAJAAQlAA==.',
So='Soothe:BAABLgAECn8XAAIYAAYJgxkzJQCbAQAYAAYJgxkzJQCbAQAAAA==.',
St='Stormride:BAAALgAECgIJAwAAAA==.',
Su='Sunlion:BAAALgAECgcJBAAAAA==.',
Sw='Swaggasaurus:BAABLgAECn8nAAMLAAkJ9h5AJQBvAgALAAkJ9h5AJQBvAgAOAAEJlwPukQAsAAAAAA==.',
Sy='Sylarien:BAAALgAECgYJCgAAAA==.Syriena:BAAALgADCggJBAAAAA==.',
Ta='Tadok:BAAALgADCgUJBQAAAA==.Talset:BAACLgAFFH8WAAIVAAQJbh3UFABlAQAVAAQJbh3UFABlAQAuAAQKfx8AAhUACAlEHwgUAFECABUACAlEHwgUAFECAAAA.',
Te='Tengoo:BAAALgAECgUJBQAAAA==.',
Th='Thewaitress:BAABLgAFFH8GAAILAAIJBxV5mACHAAALAAIJBxV5mACHAAAAAA==.Thylight:BAAALgAECgYJCAAAAA==.',
To='Tooperdy:BAAALgADCgIJAgAAAA==.',
Tr='Trappe:BAAALgADCgcJBwAAAA==.Traumatize:BAAALgADCgEJAQABLgAECgcJHAAQALYgAA==.',
Tu='Tusker:BAAALgAECgcJDQAAAA==.',
Tw='Twostunz:BAAALgADCgcJDAAAAA==.',
Ty='Tysotcan:BAABLgAFFH8PAAMVAAQJHAxNFAD8AAAVAAQJHAxNFAD8AAAWAAIJggM5HQBeAAAAAA==.',
Ur='Ursalvation:BAAALgADCgUJBQAAAA==.',
Va='Vad:BAAALgAECgIJBwAAAA==.',
Ve='Veew:BAABLgAECn8XAAMVAAgJ8RGROgC8AQAVAAgJOhGROgC8AQAWAAUJshEKGwAZAQAAAA==.',
Vu='Vutraat:BAAALgADCgEJAgAAAA==.',
Vy='Vynaca:BAAALgAECgIJBwAAAA==.',
Wa='Warpedshadow:BAAALgAECggJCwAAAA==.',
Wh='Whitegoddess:BAABLgAECn8pAAIKAAgJTQy8awBqAQAKAAgJTQy8awBqAQAAAA==.',
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
