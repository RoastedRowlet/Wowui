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

local lookup = {'Paladin-Retribution','Paladin-Protection','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Blood','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Warrior-Protection','Warrior-Fury','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Brewmaster','Mage-Frost','DemonHunter-Devourer','Monk-Windwalker','Mage-Arcane','Unknown-Unknown','Druid-Balance','Druid-Guardian','DemonHunter-Havoc','Druid-Restoration','Warrior-Arms','DemonHunter-Vengeance','Monk-Mistweaver','Druid-Feral','Shaman-Elemental','DeathKnight-Frost','Evoker-Augmentation','Priest-Holy','Mage-Fire','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Priest-Shadow','Evoker-Preservation','Shaman-Restoration',}
local provider = {region='US',realm='ShatteredHalls',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abs:BAAALgADCgEJAQAAAA==.',
Ak='Ako:BAABLgAECn8dAAMBAAkJqRKZAwAHAQACAAgJIAxtGwA8AQABAAkJ5RGZAwAHAQAAAA==.',
Al='Alannaria:BAAALgAECgEJAwAAAA==.Alaris:BAAALgAFFAIJAgABLgAFFAUJIgADAN8kAA==.Alex:BAACLgAFFH8FAAIEAAMJGguBqwDIAAAEAAMJGguBqwDIAAAuAAQKfxkAAwQACQmAF1ptAIoBAAQACAkoFFptAIoBAAUABQnvF8YpAAgBAAEuAAUUBgkQAAYA9A4A.Allmight:BAAALgADCgIJAgAAAA==.Alx:BAACLgAFFH8QAAQGAAYJ9A56AAAKAQAHAAUJ7gcCQgBIAQAGAAMJFRV6AAAKAQAIAAEJAAB8LgAAAAAuAAQKfzYABAcACAnGIQ8YAJQCAAcACAnGIQ8YAJQCAAgABAkgGb0lADABAAYABQlzG0cQACkBAAAA.',
Ar='Ares:BAABLgAECn8WAAMJAAYJjBIbAQDfAAAJAAYJ9REbAQDfAAAKAAEJXRG2mwA8AAAAAA==.',
At='Ataris:BAAALgAECgYJDQAAAA==.',
Au='Audrey:BAACLgAFFH8OAAMLAAQJSxd6GwD1AAALAAMJCRB6GwD1AAAMAAIJLhnvcwC2AAAuAAQKfygABAwACQnYI24OAN4CAAwABwl6JG4OAN4CAAsACAlnFBEZANgBAA0ACAkPGUAMAKABAAAA.',
Av='Avoe:BAAALgADCgYJBgAAAA==.',
Ba='Banakafalata:BAABLgAECn8bAAIOAAcJ8QlCQwDtAAAOAAcJ8QlCQwDtAAABLgAFFAQJEAAPAAgIAA==.Barathinnian:BAAALgAECgQJBAAAAA==.Bat:BAABLgAECn8WAAIQAAYJ0BvdUQCQAQAQAAYJ0BvdUQCQAQAAAA==.',
Be='Beautieful:BAAALgADCgcJEQAAAA==.Bevo:BAAALgAECgYJBgAAAA==.',
Bi='Bigsha:BAAALgADCgYJCwAAAA==.Bishop:BAAALgAECgcJEgAAAA==.',
Bl='Blux:BAAALgADCgUJBQAAAA==.',
Bo='Bondagestyle:BAAALgAECgIJBAAAAA==.Borgor:BAABLgAECn8pAAIEAAgJKiIZGwDbAgAEAAgJKiIZGwDbAgABLgAFFAQJEAARAKEhAA==.',
Br='Braindead:BAAALgAECgUJBQAAAA==.',
Bt='Btterbean:BAAALgAECgMJBQAAAA==.',
Bu='Burdên:BAABLgAECn88AAISAAkJUxM6AwD4AQASAAkJUxM6AwD4AQAAAA==.',
By='Byng:BAAALgAECgEJAQABLgAECgYJDwATAAAAAA==.',
Ch='Chamber:BAAALgAECgQJBAAAAA==.Chambr:BAAALgAECgEJAQAAAA==.Chamchi:BAAALgAECgQJBAAAAA==.Cheri:BAACLgAFFH8MAAIUAAYJGwfjIQASAQAUAAYJGwfjIQASAQAuAAQKfyMAAhQACQlMGaYbACUCABQACQlMGaYbACUCAAAA.',
Co='Codh:BAAALgAECgEJAgABLgAECgUJCwATAAAAAA==.Codum:BAAALgAECgUJCwAAAA==.Coozi:BAAALgAECgEJAQAAAA==.',
Cu='Cubenzi:BAAALgADCgkJBAAAAA==.',
Da='Dackosaur:BAABLgAECn81AAIVAAkJfyMgAgAlAwAVAAkJfyMgAgAlAwAAAA==.Daedalos:BAAALgAFFAMJAwAAAA==.Dageek:BAAALgAECgEJAQAAAA==.Daneikus:BAAALgAECgcJCwAAAA==.Danekriste:BAABLgAECn8SAAIQAAYJyQWbzACYAAAQAAYJyQWbzACYAAAAAA==.Darkenedone:BAACLgAFFH8jAAIFAAYJ2h5oDQCnAQAFAAYJ2h5oDQCnAQAuAAQKfyEAAwUACQlCIlMFANUCAAUACQlCIlMFANUCAAQAAgkPEsoUAUsAAAAA.',
Db='Dblackfalcon:BAAALgAECggJEQAAAA==.',
De='Deathaura:BAAALgAECgkJEgAAAA==.Deathbyarrow:BAAALgADCgUJBQAAAA==.Demonex:BAAALgADCgMJAwABLgAECgQJBAATAAAAAA==.Demono:BAABLgAECn8ZAAMQAAYJaRhHXgCGAQAQAAYJExdHXgCGAQAWAAMJiRiTNwDcAAABLgAFFAgJIwAXAFkiAA==.Denton:BAAALgAECgQJBQAAAA==.',
Do='Doggx:BAABLgAECn8iAAIYAAkJqQkBJABFAQAYAAkJqQkBJABFAQAAAA==.',
Dr='Dragon:BAAALgAECgMJAwAAAA==.Drfrangelico:BAABLgAECn8jAAMDAAkJ6xGpIgDvAQADAAkJ6xGpIgDvAQABAAgJ6QY7tgAWAQAAAA==.Drudberymore:BAAALgAECgMJAwAAAA==.Druido:BAACLgAFFH8jAAMXAAgJWSJnAgAfAwAXAAgJWSJnAgAfAwAUAAMJzRIoLgDOAAAuAAQKfzQAAxcACQnEJi0AAO8DABcACQnEJi0AAO8DABQABAnoIRQ1AEMBAAAA.Drunkmonk:BAAALgAECggJEAAAAA==.',
Ds='Ds:BAACLgAFFH8cAAIZAAYJ/yCEAQDJAQAZAAYJ/yCEAQDJAQAuAAQKfysAAhkACQl3IygBACcDABkACQl3IygBACcDAAAA.',
Du='Dumdum:BAAALgAECgUJCgAAAA==.',
En='Enjoyby:BAABLgAECn8fAAIaAAgJ4iEdCwDnAgAaAAgJ4iEdCwDnAgAAAA==.',
Er='Erzascarlet:BAAALgADCgIJAgAAAA==.',
Ex='Exayah:BAAALgAECgQJBAAAAA==.',
Fi='Fistwarior:BAAALgAECgcJDgABLgAFFAcJIAAHAFweAA==.',
Fr='Frankßuck:BAABLgAECn8kAAMMAAcJOQUppQD3AAAMAAcJOQUppQD3AAANAAYJDQI3LABlAAAAAA==.Friarstrange:BAABLgAECn8UAAIaAAYJqAytXgD8AAAaAAYJqAytXgD8AAAAAA==.Frosticle:BAAALgADCgEJAQAAAA==.',
Fu='Fuwawá:BAAALgAECgMJAwAAAA==.',
Ga='Gaebora:BAABLgAECn8hAAMXAAkJwR0AKgAKAgAXAAYJHyEAKgAKAgAbAAMJQhJNLAC1AAAAAA==.',
Gn='Gnomekabobs:BAAALgADCgEJAQABLgAECgkJTwAYAIklAA==.',
Go='Gobbylynn:BAAALgAECgEJAQABLgAECgcJGgAcABMNAA==.',
Gy='Gyllene:BAAALgADCgMJAwAAAA==.',
Ha='Hadory:BAABLgAECn8WAAIBAAgJfhDmUgDoAQABAAgJfhDmUgDoAQAAAA==.Hamus:BAAALgAECgEJAQAAAA==.Harakki:BAABLgAECn81AAMdAAkJ3BO2DACsAQAdAAgJPBW2DACsAQAFAAMJewh/RgB0AAAAAA==.Hardscope:BAAALgAECgYJEAAAAA==.Havilove:BAAALgADCgQJBAAAAA==.',
He='Heather:BAAALgAECgEJAQAAAA==.Herbie:BAAALgADCgMJBAABLgAECgUJCwATAAAAAA==.',
Ho='Holyroran:BAABLgAECn8eAAIDAAcJ/yEPEwB4AgADAAcJ/yEPEwB4AgAAAA==.Hopseng:BAAALgADCgcJCAAAAA==.Hotsrock:BAAALgAECgEJAQAAAA==.',
['Hé']='Hécâté:BAAALgAFFAIJAgAAAA==.',
Ia='Iamundeadian:BAEALgAECgYJAwABLgAECgkJAgATAAAAAA==.',
Ic='Icdeadpeeple:BAABLgAECn8ZAAMBAAYJSRN9wQAGAQABAAYJsRB9wQAGAQACAAIJRhaFSwA9AAAAAA==.Icytouch:BAABLgAECn8XAAIPAAgJhxMgZAC2AQAPAAgJhxMgZAC2AQAAAA==.',
Il='Illijim:BAAALgAECgQJBQABLgAECgkJOgAOAOshAA==.',
Im='Immortal:BAAALgAECgkJCgAAAA==.',
Ip='Ipwnprince:BAAALgAECgEJAQAAAA==.',
Is='Isityummy:BAAALgAECgIJAQAAAA==.',
['Iá']='Ián:BAEALgAECgYJAQABLgAECgkJAgATAAAAAA==.',
Ja='Jarakk:BAAALgADCgUJCAAAAA==.',
Je='Jedrek:BAAALgAECgEJAQAAAA==.Jellybeanrez:BAABLgAECn8mAAIBAAgJ4weBtAAYAQABAAgJ4weBtAAYAQAAAA==.',
Jo='Jojolion:BAAALgAECgQJDQAAAA==.Jorrdan:BAABLgAECn8VAAIDAAkJmw5CUAD4AAADAAkJmw5CUAD4AAAAAA==.',
Ka='Kaidapixi:BAAALgADCgYJBgAAAA==.Kalacia:BAABLgAECn8wAAIPAAkJySAvEQDzAgAPAAkJySAvEQDzAgAAAA==.',
Ke='Kehla:BAAALgAECgEJAQAAAA==.Keysbricked:BAAALgAECgQJBgABLgAECgkJGAAcAFUUAA==.',
Ki='Kickflip:BAAALgAECgYJBgABLgAFFAYJFQAeAFwbAA==.Kikthebucket:BAAALgADCgEJAQAAAA==.',
Kr='Kraytoes:BAAALgADCgEJAQAAAA==.Kritz:BAABLgAECn8YAAMVAAkJVg/PGgB3AQAVAAkJVg/PGgB3AQAbAAEJyQReYgAfAAAAAA==.',
Kw='Kwaichang:BAAALgAECgUJBgAAAA==.',
La='Laine:BAABLgAECn8cAAIfAAYJMhyKHwDlAQAfAAYJMhyKHwDlAQAAAA==.Lastexile:BAAALgAECgEJAQAAAA==.',
Le='Leksi:BAAALgAECgEJAQAAAA==.',
Li='Linglinda:BAACLgAFFH8QAAIRAAQJoSHwCACLAQARAAQJoSHwCACLAQAuAAQKfyMAAhEACQl2JF0CAEgDABEACQl2JF0CAEgDAAAA.',
Lo='Lockstar:BAEALgAECgkJAgAAAA==.Lockwarior:BAACLgAFFH8gAAQHAAcJXB5iJgCwAQAHAAYJ7yNiJgCwAQAGAAEJAABkBABbAAAIAAIJDgicFQBTAAAuAAQKfyQAAwcACQm3Is0EAG4DAAcACQm3Is0EAG4DAAgAAQkAAM6AAA0AAAAA.Loricarvonri:BAAALgAECgUJCAAAAA==.Lottiedottie:BAAALgAECgQJBAAAAA==.Love:BAAALgAECgQJBAAAAA==.',
Lu='Luciena:BAABLgAECn8fAAIWAAgJuw/iIgBhAQAWAAgJuw/iIgBhAQAAAA==.Lunarheals:BAABLgAECn8lAAIfAAkJeRg5EgBNAgAfAAkJeRg5EgBNAgAAAA==.Lunasong:BAABLgAECn8gAAIMAAkJSwfIZgB2AQAMAAkJSwfIZgB2AQAAAA==.Luxury:BAAALgAECgMJBgAAAA==.',
Ma='Marcagi:BAAALgADCgEJAQAAAA==.Martibishop:BAAALgADCgcJBgABLgAECgkJLAAaAIkUAA==.Martyguard:BAAALgAECgYJBgABLgAECgkJLAAaAIkUAA==.Martyulon:BAABLgAECn8sAAMaAAkJiRTJIwACAgAaAAkJiRTJIwACAgARAAUJHQnmXQCgAAAAAA==.Maxlink:BAAALgAECgMJAwAAAA==.',
Me='Melikefire:BAACLgAFFH8NAAIgAAQJ9RGAAgALAQAgAAQJ9RGAAgALAQAuAAQKfywAAiAACQn7HzABALcCACAACQn7HzABALcCAAAA.Melikesword:BAAALgAECgQJBAAAAA==.',
Mo='Molda:BAAALgAECgcJEwAAAA==.Monkjimothy:BAABLgAECn86AAQOAAkJ6yGkCQCXAgAOAAgJ/yCkCQCXAgARAAYJnh+hQwDwAAAaAAMJxQonXgBVAAAAAA==.Monko:BAAALgAECgEJAgABLgAFFAgJIwAXAFkiAA==.Moomie:BAAALgADCgMJAwAAAA==.Moonstrike:BAAALgAECggJEAAAAA==.Mortius:BAAALgADCgcJDAAAAA==.',
Na='Navier:BAAALgADCgMJAwAAAA==.',
Ne='Nero:BAAALgADCgEJAQAAAA==.',
No='Noice:BAAALgAECgIJAgABLgAFFAYJFQAeAFwbAA==.',
Od='Odinsknight:BAACLgAFFH8GAAIdAAMJbQQcGwCvAAAdAAMJbQQcGwCvAAAuAAQKfysABB0ACQmbE+gIAPsBAB0ACQkCE+gIAPsBAAQAAwmwATsOAVgAAAUAAQlSFKBcADMAAAAA.',
Oo='Oowoo:BAAALgAFFAEJAQAAAA==.',
Pa='Pandáam:BAAALgAECgEJAQAAAA==.Pandåm:BAAALgAECgQJBAAAAA==.Parkeidand:BAAALgAECggJEQAAAA==.Patodeez:BAABLgAFFH8FAAIBAAMJmg2sdQDJAAABAAMJmg2sdQDJAAAAAA==.',
Ph='Phreek:BAACLgAFFH8IAAIPAAMJfxOLeQDlAAAPAAMJfxOLeQDlAAAuAAQKfx4AAg8ACQlxEzp5AN8BAA8ACQlxEzp5AN8BAAAA.',
Po='Pookie:BAAALgAECgEJAQAAAA==.Portius:BAAALgADCggJDQAAAA==.Pouyan:BAABLgAECn84AAIXAAkJhhSdLAD2AQAXAAkJhhSdLAD2AQAAAA==.',
Pr='Prfctpullout:BAAALgADCgIJAgAAAA==.',
Pu='Puddlez:BAAALgAECgEJAgAAAA==.',
Ra='Ra:BAABLgAECn9XAAQZAAkJyxVxCQDUAQAZAAkJZhNxCQDUAQAWAAcJVhahHQCPAQAQAAIJKQeB/QBOAAAAAA==.Racinette:BAACLgAFFH8iAAIDAAUJ3ySCDQDfAQADAAUJ3ySCDQDfAQAuAAQKfxoAAgMACQn7JL8FABADAAMACQn7JL8FABADAAAA.',
Re='Rebexha:BAABLgAECn8WAAIPAAgJ8AUusgAeAQAPAAgJ8AUusgAeAQAAAA==.Redia:BAABLgAECn8UAAMQAAYJpQxbBQCbAAAWAAUJLQoeRACmAAAQAAYJpQxbBQCbAAAAAA==.Rekless:BAAALgADCgMJAwAAAA==.Relvanas:BAABLgAECn8yAAMhAAgJ9AsMAQAcAQAhAAgJ9AsMAQAcAQAiAAMJKQMUJQBAAAAAAA==.Resist:BAAALgAFFAEJAQAAAA==.',
Ri='Riverside:BAAALgAECgYJDwAAAA==.',
Sa='Saelesth:BAAALgAECggJEAAAAA==.Salvatora:BAAALgAECgEJAQAAAA==.Sambie:BAABLgAECn8uAAIMAAkJ4wO2jgAiAQAMAAkJ4wO2jgAiAQAAAA==.',
Sc='Scannedtron:BAAALgAECgcJBwAAAA==.Scantron:BAAALgAECgcJDAAAAA==.Scrappycocco:BAAALgAECgUJDAAAAA==.Scuffedbones:BAABLgAFFH8HAAIEAAUJCgSokgDnAAAEAAUJCgSokgDnAAAAAA==.Scuffedbop:BAAALgADCgcJDQABLgAFFAUJBwAEAAoEAA==.Scuffedfaith:BAACLgAFFH8JAAIjAAQJLBA4KAAKAQAjAAQJLBA4KAAKAQAuAAQKfxsAAyMACAnQGjkWACcCACMABwmFHTkWACcCACQABQnhBGxJALgAAAEuAAUUBQkHAAQACgQA.',
Se='Sefyra:BAABLgAECn8bAAIMAAgJBRJCVACmAQAMAAgJBRJCVACmAQAAAA==.Setelai:BAAALgADCgUJBQAAAA==.',
Sh='Shadewarior:BAAALgAFFAQJBAABLgAFFAcJIAAHAFweAA==.Shamroran:BAAALgAECgEJAgAAAA==.Shankz:BAAALgADCgEJAQAAAA==.Shishi:BAAALgADCgkJCgAAAA==.',
Si='Sinful:BAAALgAECgIJAgAAAA==.',
Sn='Sneakycress:BAAALgAECgYJCgAAAA==.Snolo:BAABLgAECn8wAAMeAAkJ4RGhAABrAQAeAAkJ4RGhAABrAQAlAAQJ8wRGLgB4AAAAAA==.Snowyrose:BAAALgAECgMJAwABLgAFFAQJEAARAKEhAA==.',
So='Sorakaa:BAAALgADCgUJBQAAAA==.Soulstoned:BAAALgADCgYJCQAAAA==.',
Sp='Spiritwarior:BAACLgAFFH8IAAMmAAUJUhfsKABCAQAmAAQJtxvsKABCAQAcAAMJGQmSOQCpAAAuAAQKfxQAAyYACAm+IgwQANACACYACAm+IgwQANACABwABQk8GuI2AF4BAAEuAAUUBwkgAAcAXB4A.Splux:BAAALgAECgUJBQAAAA==.',
St='Starsky:BAAALgADCgUJBgAAAA==.Strangechill:BAAALgADCgIJAgAAAA==.Strangedraco:BAAALgADCgYJBgAAAA==.Strangewood:BAACLgAFFH8OAAIUAAQJfQRdMwCzAAAUAAQJfQRdMwCzAAAuAAQKf0EAAxcACQlMGRk6AK0BABcACAnCFxk6AK0BABQACQmgDk0kAKgBAAAA.',
Su='Sugarhzopurp:BAAALgAECgcJCAAAAA==.Summerss:BAAALgADCggJCAAAAA==.',
Sw='Swiftlee:BAAALgAECgYJBwAAAA==.',
Th='Thunderfnk:BAABLgAECn8YAAIcAAgJVRTvNgBdAQAcAAgJVRTvNgBdAQAAAA==.Thursday:BAABLgAFFH8GAAIVAAMJChUwAwCDAAAVAAMJChUwAwCDAAABLgAFFAYJHAAZAP8gAA==.',
Tr='Trickydice:BAAALgAECggJEgAAAA==.Trust:BAAALgADCgEJAQAAAA==.',
Tw='Twentyfour:BAAALgAECgEJAQABLgAECgYJDwATAAAAAA==.',
Ty='Tysreaper:BAACLgAFFH8IAAMHAAMJHQ8ifADLAAAHAAMJgw4ifADLAAAGAAEJOAoNJwBIAAAuAAQKfxgAAwcACAksEoVcALMBAAcACAlWEYVcALMBAAYAAwlxD/kYALMAAAAA.',
Ur='Urickea:BAAALgAECgEJAQAAAA==.',
Va='Valdyr:BAABLgAECn81AAIBAAkJbyEaDwDtAgABAAkJbyEaDwDtAgAAAA==.Vannishstrik:BAAALgAECgQJBAAAAA==.Varri:BAAALgADCgMJAwAAAA==.',
Vo='Vodouism:BAAALgAFFAEJAQAAAA==.Vonbane:BAAALgADCgYJCAAAAA==.',
Vu='Vu:BAAALgAECgYJBgAAAA==.',
Wa='Warcawk:BAAALgAECgYJEgAAAA==.Wardsky:BAAALgAECgYJCgAAAA==.',
We='Webbington:BAAALgAECgEJAQAAAA==.',
Wr='Wreckthar:BAABLgAECn9XAAMBAAkJ9iTaBABRAwABAAkJ9iTaBABRAwACAAIJPxmfNwCBAAAAAA==.',
Wu='Wu:BAABLgAECn8WAAIRAAgJPBAKMgA+AQARAAgJPBAKMgA+AQABLgAFFAYJEAAGAPQOAA==.',
Xe='Xelagos:BAAALgAECgcJBwABLgAFFAYJEAAGAPQOAA==.',
Xy='Xyla:BAAALgADCgEJAQAAAA==.',
Ze='Zenetrawr:BAACLgAFFH8UAAIeAAQJzg+NNADwAAAeAAQJzg+NNADwAAAuAAQKfzYAAh4ACQl7Fy8WACcCAB4ACQl7Fy8WACcCAAAA.',
Zi='Zingispingus:BAABLgAECn8fAAIUAAgJjQcPQQAKAQAUAAgJjQcPQQAKAQAAAA==.',
['Zô']='Zôrra:BAAALgAECgUJBQAAAA==.',
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
