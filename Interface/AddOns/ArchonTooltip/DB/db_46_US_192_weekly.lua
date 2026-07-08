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

local lookup = {'Paladin-Retribution','Paladin-Protection','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Blood','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Warrior-Fury','Warrior-Protection','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Brewmaster','Mage-Frost','DemonHunter-Devourer','Monk-Windwalker','Mage-Arcane','Unknown-Unknown','Druid-Balance','Druid-Guardian','DemonHunter-Havoc','Druid-Restoration','Warrior-Arms','DemonHunter-Vengeance','Monk-Mistweaver','Druid-Feral','Shaman-Elemental','DeathKnight-Frost','Evoker-Augmentation','Priest-Holy','Mage-Fire','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Priest-Shadow','Evoker-Preservation','Shaman-Restoration',}
local provider = {region='US',realm='ShatteredHalls',name='US',type='weekly',zone=46,date='2026-07-05',data={Ab='Abs:BAAALgADCgEJAQAAAA==.',
Ak='Ako:BAABLgAECn8rAAMBAAkJ7BTeBQCtAQABAAkJJxTeBQCtAQACAAgJagxtGwA8AQAAAA==.',
Al='Alannaria:BAAALgAECgEJAwAAAA==.Alaris:BAAALgAFFAIJAgABLgAFFAYJIwADAAglAA==.Alex:BAACLgAFFH8FAAIEAAMJGgt7qwDIAAAEAAMJGgt7qwDIAAAuAAQKfxkAAwQACQmAF1ptAIoBAAQACAkoFFptAIoBAAUABQnvF8kpAAgBAAEuAAUUBgkRAAYA9A4A.Allmight:BAAALgADCgIJAgAAAA==.Alx:BAACLgAFFH8RAAQGAAYJ9A6FAgD6AAAHAAUJ7gfoQQBIAQAGAAMJFRWFAgD6AAAIAAEJAAB7LgAAAAAuAAQKfzYABAcACAnGIQ8YAJQCAAcACAnGIQ8YAJQCAAgABAkgGb0lADABAAYABQlzG0cQACkBAAAA.',
Ar='Archom:BAAALgAECgQJBAAAAA==.Ares:BAABLgAECn8iAAMJAAgJUhV+AwCAAQAJAAcJwhR+AwCAAQAKAAYJYxJtAwAPAQAAAA==.',
At='Ataris:BAAALgAECgYJDQAAAA==.',
Au='Audrey:BAACLgAFFH8PAAMLAAQJSxd6GwD1AAALAAMJCRB6GwD1AAAMAAIJLhntcwC2AAAuAAQKfygABAwACQnYI2sOAN4CAAwABwl6JGsOAN4CAAsACAlnFA4ZANgBAA0ACAkPGUEMAKABAAAA.',
Av='Avoe:BAAALgADCgYJBgAAAA==.',
Ba='Banakafalata:BAABLgAECn8cAAIOAAcJ8QlFQwDtAAAOAAcJ8QlFQwDtAAABLgAFFAQJEwAPAPgIAA==.Barathinnian:BAAALgAECgQJBAAAAA==.Bat:BAABLgAECn8ZAAIQAAYJ0BvYUQCQAQAQAAYJ0BvYUQCQAQAAAA==.',
Be='Beautieful:BAAALgADCgcJEQAAAA==.Bevo:BAAALgAECgYJBgAAAA==.',
Bi='Bigbagofoats:BAAALgAECgEJAQAAAA==.Bigsha:BAAALgADCgYJCwAAAA==.Bishop:BAAALgAECgcJEgAAAA==.',
Bl='Blux:BAAALgADCgUJBQAAAA==.',
Bo='Bondagestyle:BAAALgAECgIJBAAAAA==.Borgor:BAABLgAECn8pAAIEAAgJKiIZGwDbAgAEAAgJKiIZGwDbAgABLgAFFAQJFQARAJgiAA==.',
Br='Braindead:BAAALgAECgUJBQAAAA==.Breyle:BAAALgADCgMJAwAAAA==.',
Bt='Btterbean:BAAALgAECgMJBQAAAA==.',
Bu='Burdên:BAABLgAECn8/AAISAAkJ8hM7AwD4AQASAAkJ8hM7AwD4AQAAAA==.',
By='Byng:BAAALgAECgEJAQABLgAECgYJDwATAAAAAA==.',
Ch='Chamber:BAAALgAECgQJBAAAAA==.Chambr:BAAALgAECgEJAQAAAA==.Chamchi:BAAALgAECgQJBAAAAA==.Cheri:BAACLgAFFH8MAAIUAAYJGwfcIQASAQAUAAYJGwfcIQASAQAuAAQKfyMAAhQACQlMGaYbACUCABQACQlMGaYbACUCAAAA.',
Co='Codh:BAAALgAECgEJAgABLgAECgUJCwATAAAAAA==.Codum:BAAALgAECgUJCwAAAA==.Coozi:BAAALgAECgEJAQAAAA==.',
Cu='Cubenzi:BAAALgADCgkJBAAAAA==.',
Da='Dackosaur:BAABLgAECn84AAIVAAkJ6SMgAgAlAwAVAAkJ6SMgAgAlAwAAAA==.Daedalos:BAABLgAFFH8HAAIQAAQJTgejJgCxAAAQAAQJTgejJgCxAAAAAA==.Dageek:BAAALgAECgEJAQAAAA==.Daneikus:BAAALgAECgcJCwAAAA==.Danekriste:BAABLgAECn8SAAIQAAYJyQWczACYAAAQAAYJyQWczACYAAAAAA==.Darkenedone:BAACLgAFFH8kAAIFAAcJOx1fDQCnAQAFAAcJOx1fDQCnAQAuAAQKfyEAAwUACQlCIlAFANUCAAUACQlCIlAFANUCAAQAAgkPEsoUAUsAAAAA.',
Db='Dblackfalcon:BAAALgAECggJEQAAAA==.',
De='Deathaura:BAAALgAECgkJEgAAAA==.Deathbyarrow:BAAALgADCgUJBQAAAA==.Demonex:BAAALgADCgMJAwABLgAECgQJBAATAAAAAA==.Demono:BAABLgAECn8ZAAMQAAYJaRhHXgCGAQAQAAYJExdHXgCGAQAWAAMJiRiVNwDcAAABLgAFFAgJJgAXAFkiAA==.Denton:BAAALgAECgQJBQAAAA==.',
Do='Doggx:BAABLgAECn8wAAIYAAkJNQ1SAgA5AQAYAAkJNQ1SAgA5AQAAAA==.',
Dr='Dragon:BAAALgAECgYJCQAAAA==.Drfrangelico:BAABLgAECn8jAAMDAAkJ6xGqIgDvAQADAAkJ6xGqIgDvAQABAAgJ6QY5tgAWAQAAAA==.Drudberymore:BAAALgAECgMJAwAAAA==.Druido:BAACLgAFFH8mAAMXAAgJWSJmAgAfAwAXAAgJWSJmAgAfAwAUAAMJzRIkLgDOAAAuAAQKfzQAAxcACQnEJi0AAO8DABcACQnEJi0AAO8DABQABAnoIRY1AEMBAAAA.Drunkmonk:BAAALgAECggJEAAAAA==.',
Ds='Ds:BAACLgAFFH8cAAIZAAYJ/yCEAQDJAQAZAAYJ/yCEAQDJAQAuAAQKfysAAhkACQl3IygBACcDABkACQl3IygBACcDAAAA.',
Du='Dumdum:BAAALgAECgUJCgAAAA==.',
En='Enjoyby:BAABLgAECn8fAAIaAAgJ4iEbCwDnAgAaAAgJ4iEbCwDnAgAAAA==.',
Er='Erzascarlet:BAAALgADCgIJAgAAAA==.',
Ex='Exayah:BAAALgAECgQJBAAAAA==.',
Fe='Felstyle:BAAALgAECgQJBQAAAA==.',
Fi='Fistwarior:BAAALgAECgcJDgABLgAFFAgJIQAHAH4eAA==.',
Fr='Frankßuck:BAABLgAECn8rAAMMAAcJqAnbHACRAAAMAAcJqAnbHACRAAANAAYJDQI1LABlAAAAAA==.Friarstrange:BAABLgAECn8ZAAMaAAYJqAyvXgD8AAAaAAYJqAyvXgD8AAARAAUJ+wrABgDCAAAAAA==.Frosticle:BAAALgADCgEJAQAAAA==.',
Fu='Fuwawá:BAAALgAECgMJAwAAAA==.',
Ga='Gaebora:BAABLgAECn8hAAMXAAkJwR0AKgAKAgAXAAYJHyEAKgAKAgAbAAMJQhJNLAC1AAAAAA==.',
Gn='Gnomekabobs:BAAALgADCgEJAQABLgAECgkJTwAYAIklAA==.',
Go='Gobbylynn:BAAALgAECgQJBAABLgAECgcJGgAcABMNAA==.',
Gy='Gyllene:BAAALgADCgMJAwAAAA==.',
Ha='Hadory:BAABLgAECn8WAAIBAAgJfhDmUgDoAQABAAgJfhDmUgDoAQAAAA==.Hamus:BAAALgAECgIJAwAAAA==.Harakki:BAABLgAECn84AAMdAAkJ/RS2DACsAQAdAAkJ/RS2DACsAQAFAAMJewiARgB0AAAAAA==.Hardscope:BAAALgAECgYJEAAAAA==.Havilove:BAAALgADCgQJBAAAAA==.',
He='Heather:BAAALgAECgEJAQAAAA==.Herbie:BAAALgADCgMJBAABLgAECgUJCwATAAAAAA==.',
Ho='Holyroran:BAABLgAECn8eAAIDAAcJ/yEOEwB4AgADAAcJ/yEOEwB4AgAAAA==.Hopseng:BAAALgAECgQJBQAAAA==.Hotsrock:BAAALgAECgEJAQAAAA==.',
['Hé']='Hécâté:BAAALgAFFAIJAgAAAA==.',
Ia='Iamundeadian:BAEALgAECgYJAwABLgAECgkJAgATAAAAAA==.',
Ic='Icdeadpeeple:BAABLgAECn8aAAMBAAcJRRJ9wQAGAQABAAcJGxB9wQAGAQACAAIJRhaFSwA9AAAAAA==.Icytouch:BAABLgAECn8YAAIPAAgJhxMfZAC2AQAPAAgJhxMfZAC2AQAAAA==.',
Il='Illijim:BAAALgAECgQJBQABLgAECgkJPQAOAOshAA==.',
Im='Immortal:BAAALgAECgkJCgAAAA==.',
In='Infinitidaru:BAAALgADCgUJBQAAAA==.',
Ip='Ipwnprince:BAAALgAECgEJAQAAAA==.',
Is='Isityummy:BAAALgAECgIJAQAAAA==.',
['Iá']='Ián:BAEALgAECgYJAQABLgAECgkJAgATAAAAAA==.',
Ja='Jarakk:BAAALgADCgUJCAAAAA==.',
Je='Jedrek:BAAALgAECgEJAQAAAA==.Jellybeanrez:BAABLgAECn8mAAIBAAgJ4wd/tAAYAQABAAgJ4wd/tAAYAQAAAA==.',
Jo='Jojolion:BAAALgAECgQJDQAAAA==.Jorrdan:BAABLgAECn8VAAIDAAkJmw5CUAD4AAADAAkJmw5CUAD4AAAAAA==.',
Ka='Kaidapixi:BAAALgADCgYJBgAAAA==.Kalacia:BAABLgAECn8wAAIPAAkJySArEQDzAgAPAAkJySArEQDzAgAAAA==.',
Ke='Kehla:BAAALgAECgEJAQAAAA==.Keysbricked:BAAALgAECgQJBgABLgAECgkJGAAcAFUUAA==.',
Ki='Kickflip:BAAALgAECgYJBgABLgAFFAYJFQAeAFwbAA==.Kikthebucket:BAAALgADCgEJAQAAAA==.',
Kr='Kraytoes:BAAALgADCgEJAQAAAA==.Kritz:BAABLgAECn8YAAMVAAkJVg/QGgB3AQAVAAkJVg/QGgB3AQAbAAEJyQRkYgAfAAAAAA==.',
Kw='Kwaichang:BAAALgAECgUJBgAAAA==.',
La='Laine:BAABLgAECn8cAAIfAAYJMhyKHwDlAQAfAAYJMhyKHwDlAQAAAA==.Lastexile:BAAALgAECgEJAQAAAA==.',
Le='Leksi:BAAALgAECgQJBAAAAA==.',
Li='Linglinda:BAACLgAFFH8VAAIRAAQJmCLxCACLAQARAAQJmCLxCACLAQAuAAQKfyYAAhEACQmSJF0CAEgDABEACQmSJF0CAEgDAAAA.',
Lo='Lockstar:BAEALgAECgkJAgAAAA==.Lockwarior:BAACLgAFFH8hAAQHAAgJfh4zJgCwAQAHAAcJKSMzJgCwAQAGAAEJAABkBABbAAAIAAIJDgicFQBTAAAuAAQKfyQAAwcACQm3Is0EAG4DAAcACQm3Is0EAG4DAAgAAQkAAM6AAA0AAAAA.Loricarvonri:BAAALgAECgYJDAAAAA==.Lottiedottie:BAAALgAECgQJBAAAAA==.Love:BAAALgAECgQJBAAAAA==.',
Lu='Luciena:BAABLgAECn8hAAIWAAkJrg7jIgBhAQAWAAkJrg7jIgBhAQAAAA==.Lunarheals:BAABLgAECn8lAAIfAAkJeRg4EgBNAgAfAAkJeRg4EgBNAgAAAA==.Lunasong:BAABLgAECn8gAAIMAAkJSwfFZgB2AQAMAAkJSwfFZgB2AQAAAA==.Luxury:BAAALgAECgMJBgAAAA==.',
Ma='Marcagi:BAAALgADCgEJAQAAAA==.Martibishop:BAAALgAECgMJAwABLgAECgkJLAAaAIkUAA==.Martyguard:BAAALgAECgYJBgABLgAECgkJLAAaAIkUAA==.Martyulon:BAABLgAECn8sAAMaAAkJiRTIIwACAgAaAAkJiRTIIwACAgARAAUJHQnlXQCgAAAAAA==.Maxlink:BAAALgAECgMJAwAAAA==.',
Me='Melikefire:BAACLgAFFH8QAAIgAAQJ9RGAAgALAQAgAAQJ9RGAAgALAQAuAAQKfywAAiAACQn7HzABALcCACAACQn7HzABALcCAAAA.Melikesword:BAAALgAECgQJBAAAAA==.',
Mo='Molda:BAAALgAECgcJEwAAAA==.Monkjimothy:BAABLgAECn89AAQOAAkJ6yGkCQCXAgAOAAgJ/yCkCQCXAgARAAYJnh/UAwAiAQAaAAMJxQonXgBVAAAAAA==.Monko:BAAALgAECgEJAgABLgAFFAgJJgAXAFkiAA==.Montecult:BAAALgAECgEJAQABLgAECgYJBgATAAAAAA==.Moofasa:BAAALgAECgEJAQAAAA==.Moomie:BAAALgADCgMJAwAAAA==.Moonstrike:BAAALgAECggJEAAAAA==.Mortius:BAAALgADCgcJDAAAAA==.',
Na='Namo:BAAALgAECgMJAwAAAA==.Navier:BAAALgADCgMJAwAAAA==.',
Ne='Nero:BAAALgADCgEJAQAAAA==.',
No='Noice:BAAALgAECgIJAgABLgAFFAYJFQAeAFwbAA==.',
Od='Odinsknight:BAACLgAFFH8HAAIdAAMJbQQZGwCvAAAdAAMJbQQZGwCvAAAuAAQKfysABB0ACQmbE+kIAPsBAB0ACQkCE+kIAPsBAAQAAwmwATsOAVgAAAUAAQlSFJ9cADMAAAAA.',
Oo='Oowoo:BAAALgAFFAEJAgAAAA==.',
Ou='Outfoxdu:BAAALgAECgUJBQABLgAECgcJGgAcABMNAA==.',
Pa='Pandáam:BAAALgAECgEJAQAAAA==.Pandåm:BAAALgAECgQJBAAAAA==.Parkeidand:BAAALgAECggJEQAAAA==.Patodeez:BAABLgAFFH8FAAIBAAMJmg2hdQDJAAABAAMJmg2hdQDJAAAAAA==.',
Ph='Phreek:BAACLgAFFH8JAAIPAAMJfxNreQDlAAAPAAMJfxNreQDlAAAuAAQKfx4AAg8ACQlxEzp5AN8BAA8ACQlxEzp5AN8BAAAA.',
Po='Polystyle:BAAALgAECgQJBAAAAA==.Pookie:BAAALgAECgEJAQAAAA==.Portius:BAAALgAECgEJAQAAAA==.Pouyan:BAABLgAECn84AAIXAAkJhhSaLAD2AQAXAAkJhhSaLAD2AQAAAA==.',
Pr='Prfctpullout:BAAALgADCgIJAgAAAA==.',
Pu='Puddlez:BAAALgAECgEJAgAAAA==.',
Ra='Ra:BAABLgAECn9rAAQQAAkJphYlBgBKAQAZAAkJwhRxCQDUAQAWAAcJVhahHQCPAQAQAAcJcBElBgBKAQAAAA==.Racinette:BAACLgAFFH8jAAIDAAYJCCV3DQDfAQADAAYJCCV3DQDfAQAuAAQKfxoAAgMACQn7JL8FABADAAMACQn7JL8FABADAAAA.',
Re='Rebexha:BAABLgAECn8WAAIPAAgJ8AU0sgAeAQAPAAgJ8AU0sgAeAQAAAA==.Redia:BAABLgAECn8WAAMQAAYJpQyFDwC+AAAQAAYJpQyFDwC+AAAWAAUJLQogRACmAAAAAA==.Rekless:BAAALgADCgMJAwAAAA==.Relvanas:BAABLgAECn8yAAMhAAgJ6gu0BAABAQAhAAgJ6gu0BAABAQAiAAMJKQMVJQBAAAAAAA==.Resist:BAAALgAFFAEJAwAAAA==.',
Ri='Riverside:BAAALgAECgYJDwAAAA==.',
Sa='Saelesth:BAAALgAECggJEAAAAA==.Salvatora:BAAALgAECgEJAQAAAA==.Sambie:BAABLgAECn8vAAIMAAkJ9wO2jgAiAQAMAAkJ9wO2jgAiAQAAAA==.',
Sc='Scannedtron:BAAALgAECgcJBwAAAA==.Scantron:BAAALgAECgcJDAAAAA==.Scrappycocco:BAAALgAECgUJDAAAAA==.Scuffedbones:BAABLgAFFH8HAAIEAAUJCgSmkgDnAAAEAAUJCgSmkgDnAAAAAA==.Scuffedbop:BAAALgADCgcJDQABLgAFFAUJBwAEAAoEAA==.Scuffedfaith:BAACLgAFFH8JAAIjAAQJLBAyKAAKAQAjAAQJLBAyKAAKAQAuAAQKfxsAAyMACAnQGjsWACcCACMABwmFHTsWACcCACQABQnhBGxJALgAAAEuAAUUBQkHAAQACgQA.',
Se='Sefyra:BAABLgAECn8cAAIMAAgJBRJBVACmAQAMAAgJBRJBVACmAQAAAA==.Setelai:BAAALgADCgUJBQAAAA==.',
Sh='Shadewarior:BAABLgAFFH8JAAIEAAQJQhHwHgAmAQAEAAQJQhHwHgAmAQABLgAFFAgJIQAHAH4eAA==.Shamroran:BAAALgAECgEJAgAAAA==.Shankz:BAAALgADCgEJAQAAAA==.Shineyarou:BAAALgADCgMJAwAAAA==.Shishi:BAAALgADCgkJCgAAAA==.',
Si='Sinful:BAAALgAECgIJAgAAAA==.',
Sn='Sneakycress:BAAALgAECgYJCgAAAA==.Snolo:BAABLgAECn8wAAMeAAkJwBEnAwBLAQAeAAkJwBEnAwBLAQAlAAQJ8wRGLgB4AAAAAA==.Snowyrose:BAAALgAECgQJBgABLgAFFAQJFQARAJgiAA==.',
So='Sorakaa:BAAALgADCgUJBQAAAA==.Soulstoned:BAAALgADCgYJCQAAAA==.',
Sp='Spiritwarior:BAACLgAFFH8RAAMmAAYJNh7tAwDnAQAmAAYJNh7tAwDnAQAcAAMJuwyQOQCpAAAuAAQKfxQAAyYACAm+IgwQANACACYACAm+IgwQANACABwABQk8GuU2AF4BAAEuAAUUCAkhAAcAfh4A.Splux:BAAALgAECgUJBQAAAA==.',
St='Starsky:BAAALgADCgUJBgAAAA==.Strangechill:BAAALgADCgIJAgAAAA==.Strangedraco:BAAALgADCgYJBgAAAA==.Strangewood:BAACLgAFFH8UAAIUAAQJ/wb5EACwAAAUAAQJ/wb5EACwAAAuAAQKf0MAAxcACQleGRY6AK0BABcACAnCFxY6AK0BABQACQncEFAkAKgBAAAA.',
Su='Sugarhzopurp:BAAALgAECgcJCAAAAA==.Summerss:BAAALgADCggJCAAAAA==.',
Sw='Swiftlee:BAAALgAECgYJBwAAAA==.',
Th='Thunderfnk:BAABLgAECn8YAAIcAAgJVRTyNgBdAQAcAAgJVRTyNgBdAQAAAA==.Thursday:BAABLgAFFH8IAAIVAAMJehU1DwCBAAAVAAMJehU1DwCBAAABLgAFFAYJHAAZAP8gAA==.',
Tr='Trickydice:BAAALgAECggJEgAAAA==.Trust:BAAALgADCgEJAQAAAA==.',
Tw='Twentyfour:BAAALgAECgEJAQABLgAECgYJDwATAAAAAA==.',
Ty='Tysreaper:BAACLgAFFH8IAAMHAAMJHQ8PfADLAAAHAAMJgw4PfADLAAAGAAEJOAoPJwBIAAAuAAQKfxgAAwcACAksEoVcALMBAAcACAlWEYVcALMBAAYAAwlxD/kYALMAAAAA.',
Ur='Urickea:BAAALgAECgEJAQAAAA==.',
Va='Valdyr:BAABLgAECn84AAIBAAkJbyEdDwDtAgABAAkJbyEdDwDtAgAAAA==.Vannishstrik:BAAALgAECgQJBAAAAA==.Varri:BAAALgADCgMJAwAAAA==.',
Vo='Vodouism:BAAALgAFFAEJAQAAAA==.Vonbane:BAAALgAECgIJAgAAAA==.',
Vu='Vu:BAAALgAECgYJBgAAAA==.',
Wa='Warcawk:BAAALgAECgYJEgAAAA==.Wardsky:BAAALgAECgYJCgAAAA==.',
We='Webbington:BAAALgAECgEJAQAAAA==.',
Wr='Wreckthar:BAABLgAECn9XAAMBAAkJ9iTcBABRAwABAAkJ9iTcBABRAwACAAIJPxmhNwCBAAAAAA==.',
Wu='Wu:BAABLgAECn8WAAIRAAgJPBALMgA+AQARAAgJPBALMgA+AQABLgAFFAYJEQAGAPQOAA==.',
Xe='Xelagos:BAAALgAECgcJBwABLgAFFAYJEQAGAPQOAA==.',
Xy='Xyla:BAAALgADCgEJAQAAAA==.',
Ze='Zenetrawr:BAACLgAFFH8VAAIeAAQJzg+PNADwAAAeAAQJzg+PNADwAAAuAAQKfzYAAh4ACQl7Fy8WACcCAB4ACQl7Fy8WACcCAAAA.',
Zi='Zingispingus:BAABLgAECn8fAAIUAAgJjQcUQQAKAQAUAAgJjQcUQQAKAQAAAA==.',
['Zô']='Zôrra:BAAALgAECgYJDgAAAA==.',
['Ær']='Ærìs:BAAALgADCgcJBwAAAA==.',
['Ða']='Ðaora:BAAALgADCgkJCgABLgAECggJGwAYANkeAA==.',
['ßa']='ßandamonium:BAAALgAECgYJCQAAAA==.',
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
