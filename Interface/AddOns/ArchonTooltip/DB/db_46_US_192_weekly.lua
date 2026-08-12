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

local lookup = {'DeathKnight-Unholy','Paladin-Retribution','Paladin-Protection','Paladin-Holy','Unknown-Unknown','Warrior-Fury','Warrior-Protection','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Brewmaster','Mage-Frost','DemonHunter-Devourer','Monk-Windwalker','Mage-Arcane','Druid-Balance','Druid-Guardian','DeathKnight-Blood','DemonHunter-Havoc','Druid-Restoration','Warrior-Arms','Evoker-Devastation','DemonHunter-Vengeance','Monk-Mistweaver','Warlock-Demonology','Druid-Feral','Shaman-Elemental','DeathKnight-Frost','Evoker-Augmentation','Priest-Holy','Warlock-Affliction','Warlock-Destruction','Mage-Fire','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Priest-Shadow','Evoker-Preservation','Shaman-Restoration',}
local provider = {region='US',realm='ShatteredHalls',name='US',type='weekly',zone=46,date='2026-08-11',data={Ab='Abs:BAAALgADCgEJAQAAAA==.Abuloki:BAAALgADCgYJBgAAAA==.',
Ai='Aimpoint:BAAALgAFFAIJAgABLgAFFAIJBgABAHMYAA==.',
Ak='Ako:BAABLgAECn9DAAMCAAkJsBqqBQBUAgACAAkJsBqqBQBUAgADAAgJpwxtGwA8AQAAAA==.',
Al='Alannaria:BAAALgAECgEJBAAAAA==.Alaris:BAAALgAFFAIJAgABLgAFFAcJJAAEAJ8iAA==.Alex:BAAALgAFFAQJBgABLgAFFAgJEgAFAAAAAQ==.Alexdh:BAAALgAECgQJBAABLgAFFAgJEgAFAAAAAQ==.Allmight:BAAALgADCgIJAgAAAA==.Alx:BAAALgAFFAgJEgAAAQ==.',
Ar='Archom:BAAALgAECgUJBgAAAA==.Ares:BAABLgAECn8+AAMGAAgJkB5CAgByAgAGAAgJkB5CAgByAgAHAAYJ5hMyBgAYAQAAAA==.',
At='Ataris:BAAALgAECgYJDQAAAA==.',
Au='Audrey:BAACLgAFFH8aAAQIAAUJPB+qBwAfAQAIAAMJUR2qBwAfAQAJAAIJLhntcwC2AAAKAAIJoAx/HgBCAAAuAAQKfygABAkACQnYI2sOAN4CAAkABwl6JGsOAN4CAAgACAlnFA4ZANgBAAoACAkPGUEMAKABAAAA.',
Av='Avoe:BAAALgADCgYJBgAAAA==.',
Ba='Banakafalata:BAABLgAECn8cAAILAAcJ8QlFQwDtAAALAAcJ8QlFQwDtAAABLgAFFAUJFQAMALIKAA==.Barathinnian:BAAALgAECgQJBAAAAA==.Bat:BAABLgAECn8ZAAINAAYJ0BvYUQCQAQANAAYJ0BvYUQCQAQAAAA==.',
Be='Beautieful:BAAALgAECgEJAQAAAA==.Bevo:BAAALgAECgYJBgAAAA==.',
Bi='Bigbagofoats:BAAALgAECgEJAQAAAA==.Bigsha:BAAALgADCgYJCwAAAA==.Bishop:BAAALgAECgcJEgAAAA==.',
Bl='Blindnotdeaf:BAAALgAECgEJAQAAAA==.Blux:BAAALgADCgUJBQAAAA==.',
Bo='Bondagestyle:BAAALgAECgIJBAABLgAFFAYJGgAJAOAVAA==.Borgor:BAABLgAECn8pAAIBAAgJKiIZGwDbAgABAAgJKiIZGwDbAgABLgAFFAUJGAAOAJgiAA==.',
Br='Braindead:BAAALgAECgUJBQAAAA==.Brewtal:BAAALgAFFAEJAQABLgAFFAIJBgABAHMYAA==.Breyle:BAAALgADCgMJAwAAAA==.',
Bt='Btterbean:BAAALgAECgMJBQAAAA==.',
Bu='Burdên:BAABLgAECn8/AAIPAAkJ8hM7AwD4AQAPAAkJ8hM7AwD4AQAAAA==.',
By='Byng:BAAALgAECgEJAQABLgAECgYJDwAFAAAAAA==.',
Ch='Chamber:BAAALgAECgQJBAAAAA==.Chamberlain:BAAALgADCgIJAgAAAA==.Chambr:BAAALgAECgEJAQAAAA==.Chamchi:BAAALgAECgQJBAAAAA==.Cheri:BAACLgAFFH8MAAIQAAYJGwfcIQASAQAQAAYJGwfcIQASAQAuAAQKfyMAAhAACQlMGaYbACUCABAACQlMGaYbACUCAAAA.',
Co='Codh:BAAALgAECgEJAgABLgAECgUJDQAFAAAAAA==.Codum:BAAALgAECgUJDQAAAA==.Coozi:BAAALgAECgEJAQAAAA==.',
Cu='Cubenzi:BAAALgADCgkJBAAAAA==.',
Da='Dackosaur:BAABLgAECn84AAIRAAkJ6SMgAgAlAwARAAkJ6SMgAgAlAwAAAA==.Daedalos:BAABLgAFFH8JAAINAAQJTgfQLwC4AAANAAQJTgfQLwC4AAAAAA==.Dageek:BAAALgAECgEJAQAAAA==.Daneikus:BAAALgAECggJDAAAAA==.Danekriste:BAABLgAECn8SAAINAAYJyQWczACYAAANAAYJyQWczACYAAAAAA==.Darkenedone:BAACLgAFFH8lAAISAAgJDRtfDQCnAQASAAgJDRtfDQCnAQAuAAQKfyEAAxIACQlCIlAFANUCABIACQlCIlAFANUCAAEAAgkPEsoUAUsAAAAA.',
Db='Dblackfalcon:BAAALgAECggJEQAAAA==.',
De='Deathaura:BAAALgAECgkJEgAAAA==.Deathbyarrow:BAAALgADCgUJBQAAAA==.Demonex:BAAALgADCgMJAwABLgAFFAEJAQAFAAAAAA==.Demono:BAABLgAECn8ZAAMNAAYJaRhHXgCGAQANAAYJExdHXgCGAQATAAMJiRiVNwDcAAABLgAFFAgJJgAUAFkiAA==.Denton:BAAALgAECgQJBQAAAA==.',
Do='Doggx:BAABLgAECn9KAAIVAAkJuhTaAQD3AQAVAAkJuhTaAQD3AQAAAA==.',
Dr='Dragon:BAABLgAECn8dAAIWAAgJEhKZAQCCAQAWAAgJEhKZAQCCAQAAAA==.Drfrangelico:BAABLgAECn8jAAMEAAkJ6xGqIgDvAQAEAAkJ6xGqIgDvAQACAAgJ6QY5tgAWAQAAAA==.Drudberymore:BAAALgAECgUJBQAAAA==.Druido:BAACLgAFFH8mAAMUAAgJWSJmAgAfAwAUAAgJWSJmAgAfAwAQAAMJzRIkLgDOAAAuAAQKfzQAAxQACQnEJi0AAO8DABQACQnEJi0AAO8DABAABAnoIRY1AEMBAAAA.Drunkmonk:BAAALgAECggJEAAAAA==.',
Ds='Ds:BAACLgAFFH8cAAIXAAYJ/yCEAQDJAQAXAAYJ/yCEAQDJAQAuAAQKfysAAhcACQl3IygBACcDABcACQl3IygBACcDAAAA.',
Du='Dumdum:BAAALgAECgUJCgAAAA==.',
En='Enjoyby:BAABLgAECn8fAAIYAAgJ4iEbCwDnAgAYAAgJ4iEbCwDnAgAAAA==.',
Er='Erzascarlet:BAAALgADCgIJAgAAAA==.',
Ex='Exayah:BAAALgAECgQJBAAAAA==.',
Fe='Felstyle:BAAALgAECgQJBQAAAA==.',
Fi='Fistwarior:BAABLgAFFH8LAAMOAAcJGAtABQBmAQAOAAcJCwtABQBmAQALAAQJIQRMEgC6AAABLgAFFAkJJQAZAGAhAA==.',
Fr='Frankßuck:BAABLgAECn8sAAMJAAcJqAmkKgCsAAAJAAcJqAmkKgCsAAAKAAYJDQI1LABlAAAAAA==.Friarstrange:BAABLgAECn8ZAAMYAAYJqAyvXgD8AAAYAAYJqAyvXgD8AAAOAAUJ+wqPDAC5AAAAAA==.Frosticle:BAAALgADCgEJAQAAAA==.',
Fu='Fuwawá:BAAALgAECgMJAwAAAA==.',
Ga='Gaebora:BAABLgAECn8hAAMUAAkJwR0AKgAKAgAUAAYJHyEAKgAKAgAaAAMJQhJNLAC1AAAAAA==.',
Gn='Gnomekabobs:BAAALgADCgEJAQABLgAECgkJTwAVAIklAA==.',
Go='Gobbylynn:BAAALgAECgQJBAABLgAECgcJGgAbABMNAA==.',
Gy='Gyllene:BAAALgADCgMJAwAAAA==.',
Ha='Hadory:BAABLgAECn8WAAICAAgJfhDmUgDoAQACAAgJfhDmUgDoAQAAAA==.Hamus:BAAALgAECgIJAwAAAA==.Harakki:BAABLgAECn84AAMcAAkJ/RS2DACsAQAcAAkJ/RS2DACsAQASAAMJewiARgB0AAAAAA==.Hardscope:BAAALgAECgYJEAAAAA==.Havilove:BAAALgADCgQJBAAAAA==.',
He='Heather:BAAALgAECgIJBAAAAA==.Herbie:BAAALgADCgMJBAABLgAECgUJDQAFAAAAAA==.',
Ho='Holyroran:BAABLgAECn8eAAIEAAcJ/yEOEwB4AgAEAAcJ/yEOEwB4AgAAAA==.Hopseng:BAAALgAECgQJBQAAAA==.Hotsrock:BAAALgAECgEJAQAAAA==.',
['Hé']='Hécâté:BAAALgAFFAIJAgAAAA==.',
Ia='Iamundeadian:BAEALgAECgYJAwABLgAECgkJAgAFAAAAAA==.',
Ic='Icdeadpeeple:BAABLgAECn8cAAMCAAgJuhJ9wQAGAQACAAgJ3xB9wQAGAQADAAIJRhaFSwA9AAAAAA==.Icytouch:BAABLgAECn8ZAAIMAAgJKhQfZAC2AQAMAAgJKhQfZAC2AQAAAA==.',
Il='Illijim:BAAALgAECgQJBQABLgAECgkJPQALAOshAA==.',
Im='Immortal:BAAALgAECgkJCgAAAA==.',
In='Infinitidaru:BAAALgADCgUJBQAAAA==.',
Ip='Ipwnprince:BAAALgAECgEJAQAAAA==.',
Is='Isityummy:BAAALgAECgIJAQAAAA==.',
['Iá']='Ián:BAEALgAECgYJAQABLgAECgkJAgAFAAAAAA==.',
Ja='Jarakk:BAAALgADCgUJCAAAAA==.',
Je='Jedrek:BAAALgAECgEJAQAAAA==.Jellybeanrez:BAABLgAECn8mAAICAAgJ4wd/tAAYAQACAAgJ4wd/tAAYAQAAAA==.',
Jo='Jojolion:BAAALgAECgcJEgAAAA==.Jorrdan:BAABLgAECn8VAAIEAAkJmw5CUAD4AAAEAAkJmw5CUAD4AAAAAA==.',
Ka='Kaidapixi:BAAALgADCgYJBgAAAA==.Kalacia:BAABLgAECn8wAAIMAAkJySArEQDzAgAMAAkJySArEQDzAgAAAA==.',
Ke='Kehla:BAAALgAECgEJAQAAAA==.Keysbricked:BAAALgAECgQJBgABLgAECgkJGAAbAFUUAA==.',
Ki='Kickflip:BAAALgAECgYJBgABLgAFFAYJFQAdAFwbAA==.Kikthebucket:BAAALgADCgEJAQAAAA==.',
Kr='Kraytoes:BAAALgADCgEJAQAAAA==.Kritz:BAABLgAECn8YAAMRAAkJVg/QGgB3AQARAAkJVg/QGgB3AQAaAAEJyQRkYgAfAAAAAA==.',
Kw='Kwaichang:BAAALgAECgUJBwAAAA==.',
La='Laine:BAABLgAECn8cAAIeAAYJMhyKHwDlAQAeAAYJMhyKHwDlAQAAAA==.Lastexile:BAAALgAECgEJAQAAAA==.',
Le='Leksi:BAAALgAECgQJBAAAAA==.',
Li='Linglinda:BAACLgAFFH8YAAIOAAUJmCLxCACLAQAOAAUJmCLxCACLAQAuAAQKfygAAg4ACQm9JF0CAEgDAA4ACQm9JF0CAEgDAAAA.',
Lo='Lockstar:BAEALgAECgkJAgAAAA==.Lockwarior:BAACLgAFFH8lAAQZAAkJYCEzJgCwAQAZAAkJYCEzJgCwAQAfAAEJAABkBABbAAAgAAIJDgicFQBTAAAuAAQKfyQAAxkACQm3Is0EAG4DABkACQm3Is0EAG4DACAAAQkAAM6AAA0AAAAA.Loricarvonri:BAAALgAECgYJDAAAAA==.Lottiedottie:BAAALgAECgQJBAAAAA==.Love:BAAALgAECgQJBAAAAA==.',
Lu='Luciena:BAABLgAECn8hAAITAAkJrg7jIgBhAQATAAkJrg7jIgBhAQAAAA==.Lunarheals:BAABLgAECn8mAAIeAAkJJxk4EgBNAgAeAAkJJxk4EgBNAgAAAA==.Lunasong:BAABLgAECn8gAAIJAAkJSwfFZgB2AQAJAAkJSwfFZgB2AQAAAA==.Luxury:BAAALgAECgMJBgAAAA==.',
Ma='Marcagi:BAAALgADCgEJAQAAAA==.Martibishop:BAAALgAECgMJAwABLgAECgkJLAAYAIkUAA==.Martyguard:BAAALgAECgYJBgABLgAECgkJLAAYAIkUAA==.Martyulon:BAABLgAECn8sAAMYAAkJiRTIIwACAgAYAAkJiRTIIwACAgAOAAUJHQnlXQCgAAAAAA==.Maxlink:BAAALgAECgMJAwAAAA==.',
Me='Melikefire:BAACLgAFFH8RAAIhAAUJ9RGAAgALAQAhAAUJ9RGAAgALAQAuAAQKfywAAiEACQn7HzABALcCACEACQn7HzABALcCAAAA.Melikehorny:BAAALgAFFAEJAgAAAA==.Melikesword:BAAALgAECgQJBAAAAA==.Melwina:BAAALgAECgEJAQAAAA==.',
Mo='Molda:BAAALgAECgcJEwAAAA==.Monkjimothy:BAABLgAECn89AAQLAAkJ6yGkCQCXAgALAAgJ/yCkCQCXAgAOAAYJnh9qBwAcAQAYAAMJxQonXgBVAAAAAA==.Monko:BAAALgAFFAEJAQABLgAFFAgJJgAUAFkiAA==.Montecult:BAAALgAECgEJAQABLgAECgYJBgAFAAAAAA==.Moofasa:BAAALgAECgIJAgAAAA==.Moomie:BAAALgADCgMJAwAAAA==.Moonfailia:BAAALgADCgkJCQABLgAFFAUJFQAMALIKAA==.Moonstrike:BAAALgAECggJEAAAAA==.Mortius:BAAALgAECgMJBAAAAA==.',
Na='Namo:BAAALgAECgMJAwAAAA==.Navier:BAAALgADCgMJAwAAAA==.',
Ne='Nero:BAAALgADCgEJAQAAAA==.',
No='Noice:BAAALgAECgIJAgABLgAFFAYJFQAdAFwbAA==.Noodles:BAAALgAECgMJAwABLgAECggJIgANAH0WAA==.',
Od='Odinsknight:BAACLgAFFH8HAAIcAAMJbQQZGwCvAAAcAAMJbQQZGwCvAAAuAAQKfysABBwACQmbE+kIAPsBABwACQkCE+kIAPsBAAEAAwmwATsOAVgAABIAAQlSFJ9cADMAAAAA.',
Oo='Oowoo:BAAALgAFFAEJAgAAAA==.',
Ou='Outfoxdu:BAAALgAECgUJBwABLgAECgcJGgAbABMNAA==.',
Pa='Pandáam:BAAALgAECgEJAQAAAA==.Pandåm:BAAALgAECgQJBAAAAA==.Parkeidand:BAAALgAECggJEQAAAA==.Patodeez:BAABLgAFFH8GAAICAAMJJRKhdQDJAAACAAMJJRKhdQDJAAAAAA==.',
Ph='Phreek:BAACLgAFFH8JAAIMAAMJfxNreQDlAAAMAAMJfxNreQDlAAAuAAQKfx4AAgwACQlxEzp5AN8BAAwACQlxEzp5AN8BAAAA.',
Po='Polystyle:BAAALgAECgQJBgABLgAFFAYJGgAJAOAVAA==.Pookie:BAAALgAECgEJAQAAAA==.Portius:BAAALgAECgIJBQAAAA==.Pouyan:BAABLgAECn84AAIUAAkJhhSaLAD2AQAUAAkJhhSaLAD2AQAAAA==.',
Pr='Prfctpullout:BAAALgADCgIJAgAAAA==.',
Pu='Puddlez:BAAALgAECgMJBAAAAA==.',
Ra='Ra:BAABLgAECn97AAQNAAkJZBcFCACEAQAXAAkJwhRxCQDUAQANAAcJ/xUFCACEAQATAAcJMBnMCAAiAQAAAA==.Racinette:BAACLgAFFH8kAAIEAAcJnyJ3DQDfAQAEAAcJnyJ3DQDfAQAuAAQKfxoAAgQACQn7JL8FABADAAQACQn7JL8FABADAAAA.',
Re='Rebexha:BAABLgAECn8WAAIMAAgJ8AU0sgAeAQAMAAgJ8AU0sgAeAQAAAA==.Redia:BAABLgAECn8eAAMNAAYJHRDzEQD6AAANAAYJHRDzEQD6AAATAAUJLQogRACmAAAAAA==.Rekless:BAAALgADCgMJAwAAAA==.Relvanas:BAABLgAECn8yAAMiAAgJ6guUCADvAAAiAAgJ6guUCADvAAAjAAMJKQMVJQBAAAAAAA==.Resist:BAABLgAFFH8GAAIBAAIJcxitWQCoAAABAAIJcxitWQCoAAAAAA==.',
Ri='Riverside:BAAALgAECgYJDwAAAA==.',
Sa='Saelesth:BAAALgAECggJEAAAAA==.Salvatora:BAAALgAECgEJAQAAAA==.Sambie:BAABLgAECn8vAAIJAAkJ9wO2jgAiAQAJAAkJ9wO2jgAiAQAAAA==.',
Sc='Scannedtron:BAAALgAECgcJBwAAAA==.Scantron:BAAALgAECgcJDAAAAA==.Scrappycocco:BAAALgAECgUJDAAAAA==.Scuffedbones:BAABLgAFFH8HAAIBAAUJCgSmkgDnAAABAAUJCgSmkgDnAAAAAA==.Scuffedbop:BAAALgADCgcJDQABLgAFFAUJBwABAAoEAA==.Scuffedfaith:BAACLgAFFH8JAAIkAAQJLBAyKAAKAQAkAAQJLBAyKAAKAQAuAAQKfxsAAyQACAnQGjsWACcCACQABwmFHTsWACcCACUABQnhBGxJALgAAAEuAAUUBQkHAAEACgQA.',
Se='Sefyra:BAABLgAECn8eAAIJAAgJ9xJBVACmAQAJAAgJ9xJBVACmAQAAAA==.Setelai:BAAALgADCgUJBQAAAA==.',
Sh='Shadewarior:BAABLgAFFH8JAAIBAAQJQhHCMwAEAQABAAQJQhHCMwAEAQABLgAFFAkJJQAZAGAhAA==.Shamroran:BAAALgAECgEJAgAAAA==.Shankz:BAAALgADCgEJAQAAAA==.Shineyarou:BAAALgADCgMJAwAAAA==.Shishi:BAAALgADCgkJCgAAAA==.Shortonfaith:BAAALgAECgIJAgAAAA==.',
Si='Sinful:BAAALgAECgIJAgAAAA==.',
Sn='Sneakycress:BAAALgAECgcJCgAAAA==.Snolo:BAABLgAECn8wAAMdAAkJwBHnBQA0AQAdAAkJwBHnBQA0AQAmAAQJ8wRGLgB4AAAAAA==.Snowyrose:BAAALgAECgQJBgABLgAFFAUJGAAOAJgiAA==.',
So='Sorakaa:BAAALgADCgUJBQAAAA==.Soulstoned:BAAALgADCgYJCQAAAA==.',
Sp='Spiritwarior:BAACLgAFFH8kAAMbAAkJIxJCBgAjAgAbAAkJIxJCBgAjAgAnAAcJvRrbBgDvAQAuAAQKfxQAAycACAm+IgwQANACACcACAm+IgwQANACABsABQk8GuU2AF4BAAEuAAUUCQklABkAYCEA.Splux:BAAALgAECgUJBQAAAA==.',
St='Starsky:BAAALgAECgUJBgAAAA==.Strangechill:BAAALgAECgUJBQAAAA==.Strangedraco:BAAALgADCgYJBgAAAA==.Strangesoul:BAAALgADCggJBQAAAA==.Strangewood:BAACLgAFFH8XAAMQAAUJ/waQFwDFAAAQAAUJ/waQFwDFAAAUAAEJtAtEMwAtAAAuAAQKf0UAAxQACQleGRY6AK0BABQACAnCFxY6AK0BABAACQlSFFAkAKgBAAAA.',
Su='Sugarhzopurp:BAAALgAECgcJCAAAAA==.Summerss:BAAALgADCggJCAAAAA==.Suncrashkid:BAAALgAECgEJAQAAAA==.',
Sw='Swiftlee:BAAALgAECgYJBwAAAA==.',
Th='Thunderfnk:BAABLgAECn8YAAIbAAgJVRTyNgBdAQAbAAgJVRTyNgBdAQAAAA==.Thursday:BAABLgAFFH8JAAIRAAMJehXBDwCqAAARAAMJehXBDwCqAAABLgAFFAYJHAAXAP8gAA==.',
Tr='Tradravia:BAAALgAECgEJAgAAAA==.Trickydice:BAAALgAECgkJEgAAAA==.Trust:BAAALgADCgEJAQAAAA==.',
Tw='Twentyfour:BAAALgAECgEJAQABLgAECgYJDwAFAAAAAA==.',
Ty='Tysreaper:BAACLgAFFH8IAAMZAAMJHQ8PfADLAAAZAAMJgw4PfADLAAAfAAEJOAoPJwBIAAAuAAQKfxgAAxkACAksEoVcALMBABkACAlWEYVcALMBAB8AAwlxD/kYALMAAAAA.',
Ur='Urickea:BAAALgAECgEJAQAAAA==.',
Va='Valdyr:BAABLgAECn84AAICAAkJbyEdDwDtAgACAAkJbyEdDwDtAgAAAA==.Vannishstrik:BAAALgAECgQJBAAAAA==.Varmo:BAAALgAECgEJAQAAAA==.Varri:BAAALgADCgMJAwAAAA==.',
Vo='Vodouism:BAAALgAFFAEJAQAAAA==.Vonbane:BAAALgAECgIJAgAAAA==.',
Vu='Vu:BAAALgAECgYJBgAAAA==.',
Wa='Warcawk:BAAALgAECgYJEgAAAA==.Wardsky:BAAALgAECgYJCgAAAA==.',
We='Webbington:BAAALgAECgEJAQAAAA==.',
Wr='Wreckthar:BAACLgAFFH8HAAICAAQJfhiFGgApAQACAAQJfhiFGgApAQAuAAQKf1cAAwIACQn2JNwEAFEDAAIACQn2JNwEAFEDAAMAAgk/GaE3AIEAAAAA.',
Xr='Xrypto:BAAALgAECgEJAQAAAA==.',
Xy='Xyla:BAAALgADCgEJAQAAAA==.',
Ze='Zenetrawr:BAACLgAFFH8WAAIdAAQJwhOPNADwAAAdAAQJwhOPNADwAAAuAAQKfzYAAh0ACQl7Fy8WACcCAB0ACQl7Fy8WACcCAAAA.',
Zi='Zingispingus:BAABLgAECn8fAAIQAAgJjQcUQQAKAQAQAAgJjQcUQQAKAQAAAA==.',
['Zô']='Zôrra:BAABLgAECn8aAAMeAAYJehBOCQAhAQAeAAYJehBOCQAhAQAlAAEJAAAVMwAAAAAAAA==.',
['Ær']='Ærìs:BAAALgADCgcJBwAAAA==.',
['Ða']='Ðaora:BAAALgADCgkJCgABLgAECgkJGwAVANkeAA==.',
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
