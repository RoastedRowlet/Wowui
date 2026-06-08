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

local lookup = {'Paladin-Protection','Paladin-Retribution','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Blood','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Brewmaster','Mage-Frost','Monk-Windwalker','Mage-Arcane','Unknown-Unknown','Druid-Balance','Druid-Guardian','DemonHunter-Devourer','DemonHunter-Havoc','Druid-Restoration','Warrior-Arms','DemonHunter-Vengeance','Monk-Mistweaver','Druid-Feral','DeathKnight-Frost','Shaman-Elemental','Evoker-Augmentation','Priest-Holy','Mage-Fire','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Priest-Shadow','Shaman-Restoration',}
local provider = {region='US',realm='ShatteredHalls',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abs:BAAALgADCgEJAQAAAA==.',
Ak='Ako:BAABLgAECn8UAAMBAAkJfgxzHgAUAQACAAgJfQcuoQAqAQABAAcJMg1zHgAUAQAAAA==.',
Al='Alannaria:BAAALgAECgEJAgAAAA==.Alaris:BAAALgAFFAIJAgABLgAFFAUJIgADAN8kAA==.Alex:BAABLgAECn8ZAAMEAAkJgBf0ZwCOAQAEAAgJKBT0ZwCOAQAFAAUJ7xebJwANAQABLgAFFAUJDAAGAPgIAA==.Allmight:BAAALgADCgIJAgAAAA==.Alx:BAACLgAFFH8MAAQGAAUJ+Ai9XAD/AAAGAAQJiwi9XAD/AAAHAAEJKQk7IgBLAAAIAAEJAADwKgAAAAAuAAQKfzUABAYACAmQIYEXAJICAAYACAmQIYEXAJICAAgABAkgGb0lADABAAcABQlzG0cQACkBAAAA.',
Ar='Archom:BAAALgADCgYJBgAAAA==.Ares:BAAALgAECgYJBgAAAA==.',
At='Ataris:BAAALgAECgUJCAAAAA==.',
Au='Audrey:BAACLgAFFH8LAAMJAAQJRhW+GAD4AAAJAAMJCRC+GAD4AAAKAAEJ/STnhQBrAAAuAAQKfyYABAoACQnYI+kMAOECAAoABwl6JOkMAOECAAkACAlnFLMXAOABAAsACAkPGYwLAKEBAAAA.',
Av='Avoe:BAAALgADCgYJBgAAAA==.',
Ba='Banakafalata:BAABLgAECn8bAAIMAAcJ8QkdQQDtAAAMAAcJ8QkdQQDtAAABLgAFFAMJCgANANMJAA==.Bat:BAAALgAECgYJEgAAAA==.',
Be='Beautieful:BAAALgADCgcJEQAAAA==.Bevo:BAAALgAECgYJBgAAAA==.',
Bi='Bigsha:BAAALgADCgYJCwAAAA==.',
Bl='Blux:BAAALgADCgUJBQAAAA==.',
Bo='Bondagestyle:BAAALgAECgEJAQAAAA==.Borgor:BAABLgAECn8pAAIEAAgJKiIZGwDbAgAEAAgJKiIZGwDbAgABLgAFFAMJCgAOAPQfAA==.',
Br='Braindead:BAAALgAECgUJBQAAAA==.',
Bt='Btterbean:BAAALgAECgMJBQAAAA==.',
Bu='Burdên:BAABLgAECn88AAIPAAkJUxP9AgD8AQAPAAkJUxP9AgD8AQAAAA==.',
By='Byng:BAAALgAECgEJAQABLgAECgYJDwAQAAAAAA==.',
Ch='Chamber:BAAALgAECgQJBAAAAA==.Chambr:BAAALgAECgEJAQAAAA==.Chamchi:BAAALgAECgQJBAAAAA==.Cheri:BAACLgAFFH8MAAIRAAYJGwd3HgAUAQARAAYJGwd3HgAUAQAuAAQKfyMAAhEACQlMGaYbACUCABEACQlMGaYbACUCAAAA.',
Co='Codh:BAAALgAECgEJAgABLgAECgUJCwAQAAAAAA==.Codum:BAAALgAECgUJCwAAAA==.',
Cu='Cubenzi:BAAALgADCgkJBAAAAA==.',
Da='Dackosaur:BAABLgAECn81AAISAAkJfyPZAQAnAwASAAkJfyPZAQAnAwAAAA==.Daedalos:BAAALgAFFAMJAwAAAA==.Dageek:BAAALgAECgEJAQAAAA==.Daneikus:BAAALgAECgcJCwAAAA==.Danekriste:BAABLgAECn8SAAITAAYJyQV0wgCYAAATAAYJyQV0wgCYAAAAAA==.Darkenedone:BAACLgAFFH8jAAIFAAYJ2h5vCgC2AQAFAAYJ2h5vCgC2AQAuAAQKfyEAAwUACQlCIsAEAN4CAAUACQlCIsAEAN4CAAQAAgkPEsoUAUsAAAAA.',
Db='Dblackfalcon:BAAALgAECggJCQAAAA==.',
De='Deathaura:BAAALgAECggJCwAAAA==.Deathbyarrow:BAAALgADCgUJBQAAAA==.Demonex:BAAALgADCgMJAwABLgAECgQJBAAQAAAAAA==.Demono:BAABLgAECn8XAAMTAAYJIhdHXgCGAQATAAYJExdHXgCGAQAUAAEJog6IZgAxAAABLgAFFAcJHQAVAAkjAA==.Denton:BAAALgAECgQJBQAAAA==.',
Do='Doggx:BAABLgAECn8ZAAIWAAkJiwbNKgAWAQAWAAkJiwbNKgAWAQAAAA==.',
Dr='Drfrangelico:BAABLgAECn8iAAMDAAgJ4BHfKQC0AQADAAgJ4BHfKQC0AQACAAgJ6QaIqwAaAQAAAA==.Druido:BAACLgAFFH8dAAIVAAcJCSNKAQARAgAVAAcJCSNKAQARAgAuAAQKfzIAAxUACQnYJS0AAO8DABUACQnYJS0AAO8DABEABAnoIToyAEQBAAAA.Drunkmonk:BAAALgAECggJEAAAAA==.',
Ds='Ds:BAACLgAFFH8aAAIXAAUJ2yI7AgB9AQAXAAUJ2yI7AgB9AQAuAAQKfysAAhcACQl3IygBACcDABcACQl3IygBACcDAAAA.',
Du='Dumdum:BAAALgAECgUJCgAAAA==.',
En='Enjoyby:BAABLgAECn8fAAIYAAgJ4iELCgDoAgAYAAgJ4iELCgDoAgAAAA==.',
Eo='Eocháid:BAAALgAFFAIJBAABLgAFFAIJAgAQAAAAAA==.',
Er='Erzascarlet:BAAALgADCgIJAgAAAA==.',
Ex='Exayah:BAAALgAECgQJBAAAAA==.',
Fi='Fistwarior:BAAALgAECgYJDAABLgAFFAcJIAAGAFweAA==.',
Fr='Frankßuck:BAABLgAECn8kAAMKAAcJOQW4mgD8AAAKAAcJOQW4mgD8AAALAAYJDQKrKQBmAAAAAA==.Friarstrange:BAABLgAECn8UAAIYAAYJqAypVgD6AAAYAAYJqAypVgD6AAAAAA==.Frosticle:BAAALgADCgEJAQAAAA==.',
Fu='Fuwawá:BAAALgAECgMJAwAAAA==.',
Ga='Gaebora:BAABLgAECn8hAAMVAAkJwR0AKgAKAgAVAAYJHyEAKgAKAgAZAAMJQhIvKAC6AAAAAA==.',
Gn='Gnomekabobs:BAAALgADCgEJAQABLgAECgkJSQAWAGglAA==.',
Gy='Gyllene:BAAALgADCgMJAwAAAA==.',
Ha='Hadory:BAABLgAECn8WAAICAAgJfhDmUgDoAQACAAgJfhDmUgDoAQAAAA==.Harakki:BAABLgAECn81AAMaAAkJ3BMoCwC2AQAaAAgJPBUoCwC2AQAFAAMJewjcQgB3AAAAAA==.Hardscope:BAAALgAECgYJEAAAAA==.Havilove:BAAALgADCgQJBAAAAA==.',
He='Heather:BAAALgAECgEJAQAAAA==.Herbie:BAAALgADCgMJBAABLgAECgUJCwAQAAAAAA==.',
Ho='Holyroran:BAABLgAECn8eAAIDAAcJ/yHhEQB7AgADAAcJ/yHhEQB7AgAAAA==.Hopseng:BAAALgADCgcJCAAAAA==.Hotsrock:BAAALgAECgEJAQAAAA==.',
['Hé']='Hécâté:BAAALgAFFAIJAgAAAA==.',
Ia='Iamundeadian:BAEALgAECgYJAwABLgAECgkJAgAQAAAAAA==.',
Ic='Icdeadpeeple:BAABLgAECn8ZAAMCAAYJSRMsuAAHAQACAAYJsRAsuAAHAQABAAIJRhaNRwA9AAAAAA==.Icytouch:BAAALgAECgYJEgAAAA==.',
Il='Illijim:BAAALgAECgQJBQABLgAECgkJOQAMAOshAA==.',
Im='Immortal:BAAALgAECgkJCgAAAA==.',
Ip='Ipwnprince:BAAALgAECgEJAQAAAA==.',
Is='Isityummy:BAAALgAECgIJAQAAAA==.',
Ja='Jarakk:BAAALgADCgUJCAAAAA==.',
Je='Jedrek:BAAALgAECgEJAQAAAA==.Jellybeanrez:BAABLgAECn8mAAICAAgJ4wc7qgAcAQACAAgJ4wc7qgAcAQAAAA==.',
Jo='Jojolion:BAAALgAECgQJCAAAAA==.Jorrdan:BAABLgAECn8VAAIDAAkJmw6QTQD5AAADAAkJmw6QTQD5AAAAAA==.',
Ka='Kaidapixi:BAAALgADCgYJBgAAAA==.Kalacia:BAABLgAECn8wAAINAAkJySCSDwD5AgANAAkJySCSDwD5AgAAAA==.',
Ke='Keysbricked:BAAALgAECgQJBgABLgAECgkJGAAbAFUUAA==.',
Ki='Kickflip:BAAALgAECgYJBgABLgAFFAYJFQAcAFwbAA==.Kikthebucket:BAAALgADCgEJAQAAAA==.',
Kr='Kraytoes:BAAALgADCgEJAQAAAA==.Kritz:BAABLgAECn8VAAMSAAkJVg+wGAB3AQASAAkJVg+wGAB3AQAZAAEJyQTqWAAfAAAAAA==.',
Kw='Kwaichang:BAAALgAECgUJBgAAAA==.',
La='Laine:BAABLgAECn8cAAIdAAYJMhyKHwDlAQAdAAYJMhyKHwDlAQAAAA==.Lastexile:BAAALgAECgEJAQAAAA==.',
Li='Linglinda:BAACLgAFFH8KAAIOAAMJ9B8rFAAVAQAOAAMJ9B8rFAAVAQAuAAQKfyAAAg4ACQnHIl8DACQDAA4ACQnHIl8DACQDAAAA.',
Lo='Lockstar:BAEALgAECgkJAgAAAA==.Lockwarior:BAACLgAFFH8gAAQGAAcJXB7wHAC6AQAGAAYJ7yPwHAC6AQAHAAEJAABkBABbAAAIAAIJDgicFQBTAAAuAAQKfyQAAwYACQm3Is0EAG4DAAYACQm3Is0EAG4DAAgAAQkAAM6AAA0AAAAA.Loricarvonri:BAAALgAECgUJCAAAAA==.Lottiedottie:BAAALgAECgQJBAAAAA==.Love:BAAALgAECgQJBAAAAA==.',
Lu='Luciena:BAABLgAECn8fAAIUAAgJuw8rIABlAQAUAAgJuw8rIABlAQAAAA==.Lunarheals:BAABLgAECn8lAAIdAAkJeRjsEABQAgAdAAkJeRjsEABQAgAAAA==.Lunasong:BAABLgAECn8gAAIKAAkJSwc7XwB8AQAKAAkJSwc7XwB8AQAAAA==.Luxury:BAAALgAECgMJBgAAAA==.',
Ma='Marcagi:BAAALgADCgEJAQAAAA==.Martibishop:BAAALgADCgcJBgABLgAECgkJLAAYAIkUAA==.Martyguard:BAAALgAECgYJBgABLgAECgkJLAAYAIkUAA==.Martyulon:BAABLgAECn8sAAMYAAkJiRQJIQAAAgAYAAkJiRQJIQAAAgAOAAUJHQkWWACiAAAAAA==.Maxlink:BAAALgAECgMJAwAAAA==.',
Me='Melikefire:BAACLgAFFH8HAAIeAAMJyRPzAgDDAAAeAAMJyRPzAgDDAAAuAAQKfyoAAh4ACQnkHIkBAH0CAB4ACQnkHIkBAH0CAAAA.Melikesword:BAAALgAECgQJBAAAAA==.',
Mo='Molda:BAAALgAECgcJEwAAAA==.Monkjimothy:BAABLgAECn85AAQMAAkJ6yH2CACaAgAMAAgJ/yD2CACaAgAOAAYJnh/WPwDyAAAYAAMJxQonXgBVAAAAAA==.Monko:BAAALgAECgEJAQABLgAFFAcJHQAVAAkjAA==.Moomie:BAAALgADCgMJAwAAAA==.Moonstrike:BAAALgAECggJEAAAAA==.Mortius:BAAALgADCgcJDAAAAA==.',
Na='Navier:BAAALgADCgMJAwAAAA==.',
Ne='Nero:BAAALgADCgEJAQAAAA==.',
No='Noice:BAAALgAECgIJAgABLgAFFAYJFQAcAFwbAA==.',
Od='Odinsknight:BAABLgAECn8mAAQaAAgJdRTnCgC8AQAaAAgJxxPnCgC8AQAEAAMJsAE7DgFYAAAFAAEJUhRWVwA0AAAAAA==.',
Pa='Pandáam:BAAALgAECgEJAQAAAA==.Parkeidand:BAAALgAECggJEQAAAA==.Patodeez:BAAALgAFFAMJBAAAAA==.',
Ph='Phreek:BAABLgAECn8eAAINAAkJcRMkcwCNAQANAAkJcRMkcwCNAQAAAA==.',
Po='Pookie:BAAALgAECgEJAQAAAA==.Portius:BAAALgADCggJDQAAAA==.Pouyan:BAABLgAECn84AAIVAAkJhhSbKgD4AQAVAAkJhhSbKgD4AQAAAA==.',
Pr='Prfctpullout:BAAALgADCgIJAgAAAA==.',
Ra='Ra:BAABLgAECn9QAAQXAAkJwRXoCADTAQAXAAkJXBPoCADTAQAUAAcJVhZIGwCTAQATAAIJKQcM8ABOAAAAAA==.Racinette:BAACLgAFFH8iAAIDAAUJ3ySVCwDqAQADAAUJ3ySVCwDqAQAuAAQKfxoAAgMACQn7JL8FABADAAMACQn7JL8FABADAAAA.',
Re='Rebexha:BAABLgAECn8WAAINAAgJ8AV8qQAnAQANAAgJ8AV8qQAnAQAAAA==.Redia:BAAALgAECgUJDAAAAA==.Relvanas:BAABLgAECn8lAAMfAAgJBwdYKQA9AQAfAAgJBwdYKQA9AQAgAAMJKQMnIwBAAAAAAA==.',
Ri='Riverside:BAAALgAECgYJDwAAAA==.',
Sa='Saelesth:BAAALgAECggJEAAAAA==.Sambie:BAABLgAECn8uAAIKAAkJ4wNahQAnAQAKAAkJ4wNahQAnAQAAAA==.',
Sc='Scannedtron:BAAALgAECgcJBwAAAA==.Scantron:BAAALgAECgcJDAAAAA==.Scrappycocco:BAAALgAECgUJDAAAAA==.Scuffedbones:BAABLgAFFH8HAAIEAAUJCgSCgwDuAAAEAAUJCgSCgwDuAAAAAA==.Scuffedbop:BAAALgADCgcJDQABLgAFFAUJBwAEAAoEAA==.Scuffedfaith:BAABLgAECn8bAAMhAAgJ0BrFFAApAgAhAAcJhR3FFAApAgAiAAUJ4QRsSQC4AAABLgAFFAUJBwAEAAoEAA==.',
Se='Sefyra:BAABLgAECn8bAAIKAAgJBRKMTQCtAQAKAAgJBRKMTQCtAQAAAA==.Setelai:BAAALgADCgUJBQAAAA==.',
Sh='Shamroran:BAAALgAECgEJAgAAAA==.Shankz:BAAALgADCgEJAQAAAA==.Shishi:BAAALgADCgkJCgAAAA==.',
Si='Sinful:BAAALgAECgIJAgAAAA==.',
Sn='Sneakycress:BAAALgAECgYJCgAAAA==.Snolo:BAABLgAECn8hAAIcAAgJvhATLwBzAQAcAAgJvhATLwBzAQAAAA==.Snowyrose:BAAALgAECgMJAwABLgAFFAMJCgAOAPQfAA==.',
So='Sorakaa:BAAALgADCgUJBQAAAA==.Soulstoned:BAAALgADCgYJCQAAAA==.',
Sp='Spiritwarior:BAABLgAFFH8GAAMjAAQJtxvAIgBHAQAjAAQJtxvAIgBHAQAbAAEJ0QFoVgAvAAABLgAFFAcJIAAGAFweAA==.Splux:BAAALgAECgUJBQAAAA==.',
St='Starsky:BAAALgADCgUJBgAAAA==.Strangedraco:BAAALgADCgYJBgAAAA==.Strangewood:BAACLgAFFH8KAAIRAAMJXQVTNACVAAARAAMJXQVTNACVAAAuAAQKf0EAAxUACQlMGVI4AKwBABUACAnCF1I4AKwBABEACQmgDvchAKwBAAAA.',
Su='Sugarhzopurp:BAAALgAECgcJCAAAAA==.Summerss:BAAALgADCggJCAAAAA==.',
Sw='Swiftlee:BAAALgAECgYJBwAAAA==.',
Th='Thunderfnk:BAABLgAECn8YAAIbAAgJVRSiMwBfAQAbAAgJVRSiMwBfAQAAAA==.',
Tr='Trickydice:BAAALgAECggJEgAAAA==.Trust:BAAALgADCgEJAQAAAA==.',
Tw='Twentyfour:BAAALgAECgEJAQABLgAECgYJDwAQAAAAAA==.',
Ty='Tysreaper:BAACLgAFFH8GAAIGAAMJgw6QcQDQAAAGAAMJgw6QcQDQAAAuAAQKfxgAAwYACAksEoVcALMBAAYACAlWEYVcALMBAAcAAwlxD/kYALMAAAAA.',
Ur='Urickea:BAAALgAECgEJAQAAAA==.',
Va='Valdyr:BAABLgAECn81AAICAAkJbyFJDQDyAgACAAkJbyFJDQDyAgAAAA==.Vannishstrik:BAAALgAECgQJBAAAAA==.Varri:BAAALgADCgMJAwAAAA==.',
Vo='Vodouism:BAAALgAECgYJBwAAAA==.Vonbane:BAAALgADCgYJCAAAAA==.',
Vu='Vu:BAAALgAECgYJBgAAAA==.',
Wa='Warcawk:BAAALgAECgYJEgAAAA==.Wardsky:BAAALgAECgYJCgAAAA==.',
We='Webbington:BAAALgAECgEJAQAAAA==.',
Wr='Wreckthar:BAABLgAECn9XAAMCAAkJ9iQNBABWAwACAAkJ9iQNBABWAwABAAIJPxmtNACBAAAAAA==.',
Wu='Wu:BAABLgAECn8WAAIOAAgJPBB/LgBDAQAOAAgJPBB/LgBDAQABLgAFFAUJDAAGAPgIAA==.',
Xe='Xelagos:BAAALgAECgcJBwABLgAFFAUJDAAGAPgIAA==.',
Xy='Xyla:BAAALgADCgEJAQAAAA==.',
Ze='Zenetrawr:BAACLgAFFH8PAAIcAAQJOQ5wLwD4AAAcAAQJOQ5wLwD4AAAuAAQKfzQAAhwACQlGF2cVACcCABwACQlGF2cVACcCAAAA.',
Zi='Zingispingus:BAABLgAECn8fAAIRAAgJjQcIPQANAQARAAgJjQcIPQANAQAAAA==.',
['Ær']='Ærìs:BAAALgADCgcJBwAAAA==.',
['Ða']='Ðaora:BAAALgADCgkJCgABLgAECggJGwAWANkeAA==.',
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
