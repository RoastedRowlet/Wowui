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

local lookup = {'Unknown-Unknown','Paladin-Retribution','Paladin-Protection','Paladin-Holy','Warrior-Fury','Warrior-Protection','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Brewmaster','Mage-Frost','DemonHunter-Devourer','DeathKnight-Unholy','Monk-Windwalker','Mage-Arcane','Druid-Balance','Druid-Guardian','DeathKnight-Blood','DemonHunter-Havoc','Druid-Restoration','Warrior-Arms','DemonHunter-Vengeance','Monk-Mistweaver','Warlock-Demonology','Druid-Feral','Shaman-Elemental','DeathKnight-Frost','Evoker-Augmentation','Priest-Holy','Warlock-Affliction','Warlock-Destruction','Mage-Fire','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Priest-Shadow','Evoker-Preservation','Shaman-Restoration',}
local provider = {region='US',realm='ShatteredHalls',name='US',type='weekly',zone=46,date='2026-07-12',data={Ab='Abs:BAAALgADCgEJAQAAAA==.',
Ai='Aimpoint:BAAALgAFFAEJAQABLgAFFAEJBAABAAAAAA==.',
Ak='Ako:BAABLgAECn8tAAMCAAkJJxaTBgDEAQACAAkJYhWTBgDEAQADAAgJagxtGwA8AQAAAA==.',
Al='Alannaria:BAAALgAECgEJBAAAAA==.Alaris:BAAALgAFFAIJAgABLgAFFAcJJAAEAJ8iAA==.Alex:BAAALgAFFAQJBgABLgAFFAgJEQABAAAAAQ==.Alexdh:BAAALgAECgEJAQABLgAFFAgJEQABAAAAAQ==.Allmight:BAAALgADCgIJAgAAAA==.Alx:BAAALgAFFAgJEQAAAQ==.',
Ar='Archom:BAAALgAECgUJBgAAAA==.Ares:BAABLgAECn8pAAMFAAgJzBj8AgDCAQAFAAgJ+xT8AgDCAQAGAAYJpxP0AwAfAQAAAA==.',
At='Ataris:BAAALgAECgYJDQAAAA==.',
Au='Audrey:BAACLgAFFH8SAAMHAAQJexwsCgDSAAAHAAMJpBksCgDSAAAIAAIJLhntcwC2AAAuAAQKfygABAgACQnYI2sOAN4CAAgABwl6JGsOAN4CAAcACAlnFA4ZANgBAAkACAkPGUEMAKABAAAA.',
Av='Avoe:BAAALgADCgYJBgAAAA==.',
Ba='Banakafalata:BAABLgAECn8cAAIKAAcJ8QlFQwDtAAAKAAcJ8QlFQwDtAAABLgAFFAQJEwALAPgIAA==.Barathinnian:BAAALgAECgQJBAAAAA==.Bat:BAABLgAECn8ZAAIMAAYJ0BvYUQCQAQAMAAYJ0BvYUQCQAQAAAA==.',
Be='Beautieful:BAAALgADCgcJEQAAAA==.Bevo:BAAALgAECgYJBgAAAA==.',
Bi='Bigbagofoats:BAAALgAECgEJAQAAAA==.Bigsha:BAAALgADCgYJCwAAAA==.Bishop:BAAALgAECgcJEgAAAA==.',
Bl='Blux:BAAALgADCgUJBQAAAA==.',
Bo='Bondagestyle:BAAALgAECgIJBAABLgAFFAYJGgAIAOAVAA==.Borgor:BAABLgAECn8pAAINAAgJKiIZGwDbAgANAAgJKiIZGwDbAgABLgAFFAQJFQAOAJgiAA==.',
Br='Braindead:BAAALgAECgUJBQAAAA==.Breyle:BAAALgADCgMJAwAAAA==.',
Bt='Btterbean:BAAALgAECgMJBQAAAA==.',
Bu='Burdên:BAABLgAECn8/AAIPAAkJ8hM7AwD4AQAPAAkJ8hM7AwD4AQAAAA==.',
By='Byng:BAAALgAECgEJAQABLgAECgYJDwABAAAAAA==.',
Ch='Chamber:BAAALgAECgQJBAAAAA==.Chambr:BAAALgAECgEJAQAAAA==.Chamchi:BAAALgAECgQJBAAAAA==.Cheri:BAACLgAFFH8MAAIQAAYJGwfcIQASAQAQAAYJGwfcIQASAQAuAAQKfyMAAhAACQlMGaYbACUCABAACQlMGaYbACUCAAAA.',
Co='Codh:BAAALgAECgEJAgABLgAECgUJCwABAAAAAA==.Codum:BAAALgAECgUJCwAAAA==.Coozi:BAAALgAECgEJAQAAAA==.',
Cu='Cubenzi:BAAALgADCgkJBAAAAA==.',
Da='Dackosaur:BAABLgAECn84AAIRAAkJ6SMgAgAlAwARAAkJ6SMgAgAlAwAAAA==.Daedalos:BAABLgAFFH8IAAIMAAQJTgfBJQDIAAAMAAQJTgfBJQDIAAAAAA==.Dageek:BAAALgAECgEJAQAAAA==.Daneikus:BAAALgAECgcJCwAAAA==.Danekriste:BAABLgAECn8SAAIMAAYJyQWczACYAAAMAAYJyQWczACYAAAAAA==.Darkenedone:BAACLgAFFH8lAAISAAgJDRtfDQCnAQASAAgJDRtfDQCnAQAuAAQKfyEAAxIACQlCIlAFANUCABIACQlCIlAFANUCAA0AAgkPEsoUAUsAAAAA.',
Db='Dblackfalcon:BAAALgAECggJEQAAAA==.',
De='Deathaura:BAAALgAECgkJEgAAAA==.Deathbyarrow:BAAALgADCgUJBQAAAA==.Demonex:BAAALgADCgMJAwABLgAFFAEJAQABAAAAAA==.Demono:BAABLgAECn8ZAAMMAAYJaRhHXgCGAQAMAAYJExdHXgCGAQATAAMJiRiVNwDcAAABLgAFFAgJJgAUAFkiAA==.Denton:BAAALgAECgQJBQAAAA==.',
Do='Doggx:BAABLgAECn8xAAIVAAkJbg1OAgBeAQAVAAkJbg1OAgBeAQAAAA==.',
Dr='Dragon:BAAALgAECgcJEAAAAA==.Drfrangelico:BAABLgAECn8jAAMEAAkJ6xGqIgDvAQAEAAkJ6xGqIgDvAQACAAgJ6QY5tgAWAQAAAA==.Drudberymore:BAAALgAECgMJAwAAAA==.Druido:BAACLgAFFH8mAAMUAAgJWSJmAgAfAwAUAAgJWSJmAgAfAwAQAAMJzRIkLgDOAAAuAAQKfzQAAxQACQnEJi0AAO8DABQACQnEJi0AAO8DABAABAnoIRY1AEMBAAAA.Drunkmonk:BAAALgAECggJEAAAAA==.',
Ds='Ds:BAACLgAFFH8cAAIWAAYJ/yCEAQDJAQAWAAYJ/yCEAQDJAQAuAAQKfysAAhYACQl3IygBACcDABYACQl3IygBACcDAAAA.',
Du='Dumdum:BAAALgAECgUJCgAAAA==.',
En='Enjoyby:BAABLgAECn8fAAIXAAgJ4iEbCwDnAgAXAAgJ4iEbCwDnAgAAAA==.',
Er='Erzascarlet:BAAALgADCgIJAgAAAA==.',
Ex='Exayah:BAAALgAECgQJBAAAAA==.',
Fe='Felstyle:BAAALgAECgQJBQAAAA==.',
Fi='Fistwarior:BAAALgAFFAQJBAABLgAFFAkJIwAYAIkeAA==.',
Fr='Frankßuck:BAABLgAECn8rAAMIAAcJqAmQIgCQAAAIAAcJqAmQIgCQAAAJAAYJDQI1LABlAAAAAA==.Friarstrange:BAABLgAECn8ZAAMXAAYJqAyvXgD8AAAXAAYJqAyvXgD8AAAOAAUJ+wpaCAC+AAAAAA==.Frosticle:BAAALgADCgEJAQAAAA==.',
Fu='Fuwawá:BAAALgAECgMJAwAAAA==.',
Ga='Gaebora:BAABLgAECn8hAAMUAAkJwR0AKgAKAgAUAAYJHyEAKgAKAgAZAAMJQhJNLAC1AAAAAA==.',
Gn='Gnomekabobs:BAAALgADCgEJAQABLgAECgkJTwAVAIklAA==.',
Go='Gobbylynn:BAAALgAECgQJBAABLgAECgcJGgAaABMNAA==.',
Gy='Gyllene:BAAALgADCgMJAwAAAA==.',
Ha='Hadory:BAABLgAECn8WAAICAAgJfhDmUgDoAQACAAgJfhDmUgDoAQAAAA==.Hamus:BAAALgAECgIJAwAAAA==.Harakki:BAABLgAECn84AAMbAAkJ/RS2DACsAQAbAAkJ/RS2DACsAQASAAMJewiARgB0AAAAAA==.Hardscope:BAAALgAECgYJEAAAAA==.Havilove:BAAALgADCgQJBAAAAA==.',
He='Heather:BAAALgAECgEJAgAAAA==.Herbie:BAAALgADCgMJBAABLgAECgUJCwABAAAAAA==.',
Ho='Holyroran:BAABLgAECn8eAAIEAAcJ/yEOEwB4AgAEAAcJ/yEOEwB4AgAAAA==.Hopseng:BAAALgAECgQJBQAAAA==.Hotsrock:BAAALgAECgEJAQAAAA==.',
['Hé']='Hécâté:BAAALgAFFAIJAgAAAA==.',
Ia='Iamundeadian:BAEALgAECgYJAwABLgAECgkJAgABAAAAAA==.',
Ic='Icdeadpeeple:BAABLgAECn8aAAMCAAcJRRJ9wQAGAQACAAcJGxB9wQAGAQADAAIJRhaFSwA9AAAAAA==.Icytouch:BAABLgAECn8ZAAILAAgJKhQfZAC2AQALAAgJKhQfZAC2AQAAAA==.',
Il='Illijim:BAAALgAECgQJBQABLgAECgkJPQAKAOshAA==.',
Im='Immortal:BAAALgAECgkJCgAAAA==.',
In='Infinitidaru:BAAALgADCgUJBQAAAA==.',
Ip='Ipwnprince:BAAALgAECgEJAQAAAA==.',
Is='Isityummy:BAAALgAECgIJAQAAAA==.',
['Iá']='Ián:BAEALgAECgYJAQABLgAECgkJAgABAAAAAA==.',
Ja='Jarakk:BAAALgADCgUJCAAAAA==.',
Je='Jedrek:BAAALgAECgEJAQAAAA==.Jellybeanrez:BAABLgAECn8mAAICAAgJ4wd/tAAYAQACAAgJ4wd/tAAYAQAAAA==.',
Jo='Jojolion:BAAALgAECgQJDQAAAA==.Jorrdan:BAABLgAECn8VAAIEAAkJmw5CUAD4AAAEAAkJmw5CUAD4AAAAAA==.',
Ka='Kaidapixi:BAAALgADCgYJBgAAAA==.Kalacia:BAABLgAECn8wAAILAAkJySArEQDzAgALAAkJySArEQDzAgAAAA==.',
Ke='Kehla:BAAALgAECgEJAQAAAA==.Keysbricked:BAAALgAECgQJBgABLgAECgkJGAAaAFUUAA==.',
Ki='Kickflip:BAAALgAECgYJBgABLgAFFAYJFQAcAFwbAA==.Kikthebucket:BAAALgADCgEJAQAAAA==.',
Kr='Kraytoes:BAAALgADCgEJAQAAAA==.Kritz:BAABLgAECn8YAAMRAAkJVg/QGgB3AQARAAkJVg/QGgB3AQAZAAEJyQRkYgAfAAAAAA==.',
Kw='Kwaichang:BAAALgAECgUJBwAAAA==.',
La='Laine:BAABLgAECn8cAAIdAAYJMhyKHwDlAQAdAAYJMhyKHwDlAQAAAA==.Lastexile:BAAALgAECgEJAQAAAA==.',
Le='Leksi:BAAALgAECgQJBAAAAA==.',
Li='Linglinda:BAACLgAFFH8VAAIOAAQJmCLxCACLAQAOAAQJmCLxCACLAQAuAAQKfyYAAg4ACQmSJF0CAEgDAA4ACQmSJF0CAEgDAAAA.',
Lo='Lockstar:BAEALgAECgkJAgAAAA==.Lockwarior:BAACLgAFFH8jAAQYAAkJiR4zJgCwAQAYAAgJiiIzJgCwAQAeAAEJAABkBABbAAAfAAIJDgicFQBTAAAuAAQKfyQAAxgACQm3Is0EAG4DABgACQm3Is0EAG4DAB8AAQkAAM6AAA0AAAAA.Loricarvonri:BAAALgAECgYJDAAAAA==.Lottiedottie:BAAALgAECgQJBAAAAA==.Love:BAAALgAECgQJBAAAAA==.',
Lu='Luciena:BAABLgAECn8hAAITAAkJrg7jIgBhAQATAAkJrg7jIgBhAQAAAA==.Lunarheals:BAABLgAECn8mAAIdAAkJJxk4EgBNAgAdAAkJJxk4EgBNAgAAAA==.Lunasong:BAABLgAECn8gAAIIAAkJSwfFZgB2AQAIAAkJSwfFZgB2AQAAAA==.Luxury:BAAALgAECgMJBgAAAA==.',
Ma='Marcagi:BAAALgADCgEJAQAAAA==.Martibishop:BAAALgAECgMJAwABLgAECgkJLAAXAIkUAA==.Martyguard:BAAALgAECgYJBgABLgAECgkJLAAXAIkUAA==.Martyulon:BAABLgAECn8sAAMXAAkJiRTIIwACAgAXAAkJiRTIIwACAgAOAAUJHQnlXQCgAAAAAA==.Maxlink:BAAALgAECgMJAwAAAA==.',
Me='Melikefire:BAACLgAFFH8QAAIgAAQJ9RGAAgALAQAgAAQJ9RGAAgALAQAuAAQKfywAAiAACQn7HzABALcCACAACQn7HzABALcCAAAA.Melikesword:BAAALgAECgQJBAAAAA==.',
Mo='Molda:BAAALgAECgcJEwAAAA==.Monkjimothy:BAABLgAECn89AAQKAAkJ6yGkCQCXAgAKAAgJ/yCkCQCXAgAOAAYJnh++BAAiAQAXAAMJxQonXgBVAAAAAA==.Monko:BAAALgAECgEJAgABLgAFFAgJJgAUAFkiAA==.Montecult:BAAALgAECgEJAQABLgAECgYJBgABAAAAAA==.Moofasa:BAAALgAECgIJAgAAAA==.Moomie:BAAALgADCgMJAwAAAA==.Moonstrike:BAAALgAECggJEAAAAA==.Mortius:BAAALgAECgEJAQAAAA==.',
Na='Namo:BAAALgAECgMJAwAAAA==.Navier:BAAALgADCgMJAwAAAA==.',
Ne='Nero:BAAALgADCgEJAQAAAA==.',
No='Noice:BAAALgAECgIJAgABLgAFFAYJFQAcAFwbAA==.',
Od='Odinsknight:BAACLgAFFH8HAAIbAAMJbQQZGwCvAAAbAAMJbQQZGwCvAAAuAAQKfysABBsACQmbE+kIAPsBABsACQkCE+kIAPsBAA0AAwmwATsOAVgAABIAAQlSFJ9cADMAAAAA.',
Oo='Oowoo:BAAALgAFFAEJAgAAAA==.',
Ou='Outfoxdu:BAAALgAECgUJBgABLgAECgcJGgAaABMNAA==.',
Pa='Pandáam:BAAALgAECgEJAQAAAA==.Pandåm:BAAALgAECgQJBAAAAA==.Parkeidand:BAAALgAECggJEQAAAA==.Patodeez:BAABLgAFFH8FAAICAAMJmg2hdQDJAAACAAMJmg2hdQDJAAAAAA==.',
Ph='Phreek:BAACLgAFFH8JAAILAAMJfxNreQDlAAALAAMJfxNreQDlAAAuAAQKfx4AAgsACQlxEzp5AN8BAAsACQlxEzp5AN8BAAAA.',
Po='Polystyle:BAAALgAECgQJBgABLgAFFAYJGgAIAOAVAA==.Pookie:BAAALgAECgEJAQAAAA==.Portius:BAAALgAECgIJAwAAAA==.Pouyan:BAABLgAECn84AAIUAAkJhhSaLAD2AQAUAAkJhhSaLAD2AQAAAA==.',
Pr='Prfctpullout:BAAALgADCgIJAgAAAA==.',
Pu='Puddlez:BAAALgAECgEJAgAAAA==.',
Ra='Ra:BAABLgAECn9xAAQMAAkJvhY1BQCHAQAWAAkJwhRxCQDUAQATAAcJVhahHQCPAQAMAAcJpxU1BQCHAQAAAA==.Racinette:BAACLgAFFH8kAAIEAAcJnyJ3DQDfAQAEAAcJnyJ3DQDfAQAuAAQKfxoAAgQACQn7JL8FABADAAQACQn7JL8FABADAAAA.',
Re='Rebexha:BAABLgAECn8WAAILAAgJ8AU0sgAeAQALAAgJ8AU0sgAeAQAAAA==.Redia:BAABLgAECn8XAAMMAAYJpQzIEgC6AAAMAAYJpQzIEgC6AAATAAUJLQogRACmAAAAAA==.Rekless:BAAALgADCgMJAwAAAA==.Relvanas:BAABLgAECn8yAAMhAAgJ6gvhBQD6AAAhAAgJ6gvhBQD6AAAiAAMJKQMVJQBAAAAAAA==.Resist:BAAALgAFFAEJBAAAAA==.',
Ri='Riverside:BAAALgAECgYJDwAAAA==.',
Sa='Saelesth:BAAALgAECggJEAAAAA==.Salvatora:BAAALgAECgEJAQAAAA==.Sambie:BAABLgAECn8vAAIIAAkJ9wO2jgAiAQAIAAkJ9wO2jgAiAQAAAA==.',
Sc='Scannedtron:BAAALgAECgcJBwAAAA==.Scantron:BAAALgAECgcJDAAAAA==.Scrappycocco:BAAALgAECgUJDAAAAA==.Scuffedbones:BAABLgAFFH8HAAINAAUJCgSmkgDnAAANAAUJCgSmkgDnAAAAAA==.Scuffedbop:BAAALgADCgcJDQABLgAFFAUJBwANAAoEAA==.Scuffedfaith:BAACLgAFFH8JAAIjAAQJLBAyKAAKAQAjAAQJLBAyKAAKAQAuAAQKfxsAAyMACAnQGjsWACcCACMABwmFHTsWACcCACQABQnhBGxJALgAAAEuAAUUBQkHAA0ACgQA.',
Se='Sefyra:BAABLgAECn8cAAIIAAgJBRJBVACmAQAIAAgJBRJBVACmAQAAAA==.Setelai:BAAALgADCgUJBQAAAA==.',
Sh='Shadewarior:BAABLgAFFH8JAAINAAQJQhElJQAfAQANAAQJQhElJQAfAQABLgAFFAkJIwAYAIkeAA==.Shamroran:BAAALgAECgEJAgAAAA==.Shankz:BAAALgADCgEJAQAAAA==.Shineyarou:BAAALgADCgMJAwAAAA==.Shishi:BAAALgADCgkJCgAAAA==.',
Si='Sinful:BAAALgAECgIJAgAAAA==.',
Sn='Sneakycress:BAAALgAECgYJCgAAAA==.Snolo:BAABLgAECn8wAAMcAAkJwBH+AwBBAQAcAAkJwBH+AwBBAQAlAAQJ8wRGLgB4AAAAAA==.Snowyrose:BAAALgAECgQJBgABLgAFFAQJFQAOAJgiAA==.',
So='Sorakaa:BAAALgADCgUJBQAAAA==.Soulstoned:BAAALgADCgYJCQAAAA==.',
Sp='Spiritwarior:BAACLgAFFH8RAAMmAAYJNh6LBQDbAQAmAAYJNh6LBQDbAQAaAAMJuwyQOQCpAAAuAAQKfxQAAyYACAm+IgwQANACACYACAm+IgwQANACABoABQk8GuU2AF4BAAEuAAUUCQkjABgAiR4A.Splux:BAAALgAECgUJBQAAAA==.',
St='Starsky:BAAALgADCgUJBgAAAA==.Strangechill:BAAALgAECgUJBQAAAA==.Strangedraco:BAAALgADCgYJBgAAAA==.Strangewood:BAACLgAFFH8UAAIQAAQJ/wZNFACsAAAQAAQJ/wZNFACsAAAuAAQKf0MAAxQACQleGRY6AK0BABQACAnCFxY6AK0BABAACQncEFAkAKgBAAAA.',
Su='Sugarhzopurp:BAAALgAECgcJCAAAAA==.Summerss:BAAALgADCggJCAAAAA==.',
Sw='Swiftlee:BAAALgAECgYJBwAAAA==.',
Th='Thunderfnk:BAABLgAECn8YAAIaAAgJVRTyNgBdAQAaAAgJVRTyNgBdAQAAAA==.Thursday:BAABLgAFFH8JAAIRAAMJehW5CwC6AAARAAMJehW5CwC6AAABLgAFFAYJHAAWAP8gAA==.',
Tr='Trickydice:BAAALgAECggJEgAAAA==.Trust:BAAALgADCgEJAQAAAA==.',
Tw='Twentyfour:BAAALgAECgEJAQABLgAECgYJDwABAAAAAA==.',
Ty='Tysreaper:BAACLgAFFH8IAAMYAAMJHQ8PfADLAAAYAAMJgw4PfADLAAAeAAEJOAoPJwBIAAAuAAQKfxgAAxgACAksEoVcALMBABgACAlWEYVcALMBAB4AAwlxD/kYALMAAAAA.',
Ur='Urickea:BAAALgAECgEJAQAAAA==.',
Va='Valdyr:BAABLgAECn84AAICAAkJbyEdDwDtAgACAAkJbyEdDwDtAgAAAA==.Vannishstrik:BAAALgAECgQJBAAAAA==.Varri:BAAALgADCgMJAwAAAA==.',
Vo='Vodouism:BAAALgAFFAEJAQAAAA==.Vonbane:BAAALgAECgIJAgAAAA==.',
Vu='Vu:BAAALgAECgYJBgAAAA==.',
Wa='Warcawk:BAAALgAECgYJEgAAAA==.Wardsky:BAAALgAECgYJCgAAAA==.',
We='Webbington:BAAALgAECgEJAQAAAA==.',
Wr='Wreckthar:BAACLgAFFH8HAAICAAQJfhg2EgA7AQACAAQJfhg2EgA7AQAuAAQKf1cAAwIACQn2JNwEAFEDAAIACQn2JNwEAFEDAAMAAgk/GaE3AIEAAAAA.',
Xy='Xyla:BAAALgADCgEJAQAAAA==.',
Ze='Zenetrawr:BAACLgAFFH8VAAIcAAQJzg+PNADwAAAcAAQJzg+PNADwAAAuAAQKfzYAAhwACQl7Fy8WACcCABwACQl7Fy8WACcCAAAA.',
Zi='Zingispingus:BAABLgAECn8fAAIQAAgJjQcUQQAKAQAQAAgJjQcUQQAKAQAAAA==.',
['Zô']='Zôrra:BAAALgAECgYJEwAAAA==.',
['Ær']='Ærìs:BAAALgADCgcJBwAAAA==.',
['Ða']='Ðaora:BAAALgADCgkJCgABLgAECggJGwAVANkeAA==.',
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
