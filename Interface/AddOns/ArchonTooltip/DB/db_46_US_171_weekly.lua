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

local lookup = {'Paladin-Retribution','Druid-Restoration','Hunter-Marksmanship','Rogue-Subtlety','Mage-Frost','Mage-Fire','Monk-Brewmaster','Evoker-Devastation','Paladin-Holy','Paladin-Protection','Shaman-Enhancement','Shaman-Restoration','DeathKnight-Unholy','Unknown-Unknown','Warrior-Arms','Warrior-Protection','Warrior-Fury','Druid-Guardian','Evoker-Preservation','DemonHunter-Havoc','Hunter-BeastMastery','Priest-Discipline','Priest-Holy','Monk-Mistweaver','Evoker-Augmentation','Monk-Windwalker','Shaman-Elemental','Druid-Balance','DemonHunter-Vengeance','Warlock-Destruction','Rogue-Assassination','Rogue-Outlaw','DeathKnight-Blood','DemonHunter-Devourer','Priest-Shadow','DeathKnight-Frost','Hunter-Survival','Warlock-Demonology',}
local provider = {region='US',realm='Onyxia',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abrams:BAABLgAECn8jAAIBAAkJaBoZAQDZAQABAAkJaBoZAQDZAQAAAA==.',
Ad='Addý:BAACLgAFFH8FAAICAAIJpQgGXQBhAAACAAIJpQgGXQBhAAAuAAQKfxgAAgIACQmAF4coAA0CAAIACQmAF4coAA0CAAAA.Advanced:BAAALgADCgQJAQAAAA==.',
Ah='Ahimsa:BAACLgAFFH8KAAIDAAQJcxW5FQAUAQADAAQJcxW5FQAUAQAuAAQKf0MAAgMACQmLIyABACoDAAMACQmLIyABACoDAAAA.',
Al='Alisonchains:BAABLgAECn85AAIEAAgJUCSzBADvAgAEAAgJUCSzBADvAgAAAA==.Alkyri:BAAALgAECgEJAQAAAA==.Almamun:BAAALgAECgIJBAAAAA==.Alternate:BAACLgAFFH8MAAIFAAQJjRX1VgAvAQAFAAQJjRX1VgAvAQAuAAQKf0UAAwUACQkZILoSAOoCAAUACQkZILoSAOoCAAYAAgkGGG4NAJAAAAAA.',
Am='Amigo:BAAALgADCgEJAQAAAA==.Amillerbrew:BAABLgAECn8aAAIHAAgJTxaYJQDXAQAHAAgJTxaYJQDXAQAAAA==.',
An='Anayanci:BAAALgAECgQJDAAAAA==.Anesh:BAAALgAECgMJBQAAAA==.Anjuna:BAAALgAECgYJDwAAAA==.Anshee:BAAALgAECgIJAwAAAA==.Anubrin:BAAALgADCgUJBwAAAA==.',
Ap='Aphian:BAAALgAECgIJAgAAAA==.',
As='Ashenclaw:BAABLgAECn86AAIIAAkJHxwmBAA7AgAIAAkJHxwmBAA7AgAAAA==.',
Au='Auzatryx:BAABLgAECn8VAAIEAAcJ/AztKwA6AQAEAAcJ/AztKwA6AQAAAA==.',
Ba='Bagpipe:BAAALgADCgkJCQAAAA==.Bamboom:BAABLgAECn8jAAQJAAcJ7RdZAQAjAQAJAAcJ7RdZAQAjAQABAAEJFgLh0QEWAAAKAAEJRAHATwARAAAAAA==.Bapbap:BAAALgADCgYJBgAAAA==.',
Be='Beefstick:BAAALgAECgMJAgAAAA==.Belanik:BAAALgAECgEJBQAAAA==.Beleth:BAAALgADCgYJBgAAAA==.',
Bi='Bigblktotem:BAABLgAECn8WAAMLAAYJlAzwFwBDAQALAAYJlAzwFwBDAQAMAAMJHQQbugBZAAABLgAFFAQJGwANAOscAA==.Biggrnmonstr:BAAALgAFFAIJAwABLgAFFAQJGwANAOscAA==.Bigheffin:BAAALgAECgIJAwABLgAECggJCwAOAAAAAA==.Bigrabit:BAAALgAECgMJAwAAAA==.Bigslammin:BAAALgAECgQJCwABLgAECggJHAALANYaAA==.Bigxthezug:BAAALgAECgQJBgABLgAECggJCwAOAAAAAA==.Biirf:BAAALgAECgUJBgAAAA==.',
Bl='Blaine:BAAALgAECgYJEAAAAA==.Blãze:BAAALgADCgIJAgAAAA==.',
Bo='Bogdan:BAAALgADCgEJAQAAAA==.Bomi:BAAALgAECgQJCQAAAA==.Boogiebm:BAAALgAECgcJCwAAAA==.Borgon:BAAALgAECgEJAgAAAA==.Bowevil:BAAALgADCgMJAwAAAA==.Boypartz:BAABLgAECn8yAAMPAAkJbR6CBQCyAgAPAAkJbR6CBQCyAgAQAAEJKwmNTQAiAAAAAA==.',
Br='Brayuh:BAAALgAECgEJAwAAAA==.Breakfast:BAAALgAECggJCwAAAA==.',
Bu='Bulbasaurus:BAACLgAFFH8cAAIRAAUJ8yUJCgDAAQARAAUJ8yUJCgDAAQAuAAQKfx8AAhEACQmjInoHADEDABEACQmjInoHADEDAAAA.Bulloney:BAAALgADCgIJAgAAAA==.Bunana:BAAALgADCgIJAgAAAA==.Bus:BAAALgAFFAMJBAABLgAFFAkJHAASAP8jAA==.',
Ca='Cabooze:BAAALgAECgYJBwAAAA==.Cacho:BAAALgAECgQJCAAAAA==.Cañonazo:BAAALgAECgEJAQAAAA==.',
Ce='Celeres:BAABLgAECn8eAAITAAgJeBgiEQAqAgATAAgJeBgiEQAqAgAAAA==.Celys:BAAALgAECgUJBgAAAA==.Cerealkillah:BAAALgAECgEJAQAAAA==.',
Ch='Chantilly:BAAALgAECgYJDwAAAA==.Chartreuse:BAAALgADCgMJBAABLgAECgUJCAAOAAAAAA==.Chaw:BAAALgAECgEJAQAAAA==.Cheesecurds:BAAALgADCgcJBwAAAA==.Cheesied:BAAALgADCgQJAwAAAA==.Chios:BAAALgAECgUJBQABLgAFFAcJHwAQALEdAA==.',
Cl='Cleetiscat:BAAALgAECgYJBgAAAA==.',
Co='Cowabunga:BAAALgADCgEJAQAAAA==.',
Cr='Crow:BAAALgAFFAgJFgAAAQ==.Cryoblade:BAAALgADCgcJDAAAAA==.',
Cu='Cuttanee:BAAALgAECggJDAAAAA==.',
Cy='Cyril:BAAALgADCgkJFwAAAA==.',
Da='Daevon:BAAALgAECgQJEAAAAA==.Daron:BAAALgAECgcJDgABLgAECgcJEQAOAAAAAA==.Darrowreaper:BAABLgAECn8eAAINAAgJzQ3feAByAQANAAgJzQ3feAByAQAAAA==.',
De='Deadcell:BAAALgAECgYJBwAAAA==.Deatheria:BAAALgADCgMJAwAAAA==.Deathstar:BAAALgAECgUJBQAAAA==.Denarrage:BAACLgAFFH8VAAIUAAYJxQgwDgA0AQAUAAYJxQgwDgA0AQAuAAQKfy4AAhQACQnuFK8VAN8BABQACQnuFK8VAN8BAAAA.Denawage:BAAALgAECggJCAAAAA==.',
Di='Dirtytotem:BAABLgAECn8cAAILAAgJ1hrNCAA0AgALAAgJ1hrNCAA0AgAAAA==.Discordia:BAAALgAECggJDQAAAA==.Disprop:BAAALgAECgEJAQAAAA==.Dizyizy:BAAALgAECgUJBwAAAA==.',
Dk='Dkigga:BAAALgAECgYJAwAAAA==.',
Do='Doingmost:BAAALgAECgYJCgAAAA==.Dontnerfspls:BAAALgAECgQJBgABLgAFFAQJGwANAOscAA==.Doomby:BAABLgAECn8ZAAIVAAgJnRKVBADrAAAVAAgJnRKVBADrAAABLgAECgkJOQAUADQbAA==.',
Dr='Drakesh:BAAALgADCgEJAQAAAA==.Drakussy:BAABLgAECn8XAAIIAAkJZQkpCwBmAQAIAAkJZQkpCwBmAQABLgAECgkJOQAUADQbAA==.Drudekay:BAAALgAECgEJAQAAAA==.',
Du='Dullslinkie:BAAALgADCgEJAQAAAA==.',
El='Eldarborn:BAAALgAECgUJBQAAAA==.Eldruida:BAAALgAECgIJAwAAAA==.Eleannar:BAAALgAECgEJAQAAAA==.Elficpaladin:BAAALgAECgYJCgAAAA==.Elixxi:BAAALgAECgUJDQAAAA==.Elladin:BAAALgADCgcJBwAAAA==.Ellipsi:BAAALgAECgcJDQAAAA==.Ellipsoro:BAACLgAFFH8KAAINAAMJBB5qjgDuAAANAAMJBB5qjgDuAAAuAAQKfy8AAg0ACQl4JdwJACEDAA0ACQl4JdwJACEDAAAA.Eltrol:BAACLgAFFH8UAAIVAAQJdAsCTQASAQAVAAQJdAsCTQASAQAuAAQKfxkAAhUACQmfFeAoADsCABUACQmfFeAoADsCAAAA.Eluriana:BAAALgAECgYJCAABLgAFFAYJGgAHAGYSAA==.',
Eq='Eques:BAAALgAECgYJDQAAAA==.',
Er='Erale:BAAALgADCgYJDAAAAA==.Eredarn:BAAALgADCgEJAQAAAA==.Erienor:BAAALgADCgkJDAAAAA==.',
Ev='Evldrprkchop:BAAALgADCgIJAgAAAA==.',
Ex='Executiepie:BAACLgAFFH8fAAIQAAcJsR1iAQDbAQAQAAcJsR1iAQDbAQAuAAQKfysAAhAACQmTJQEBAF4DABAACQmTJQEBAF4DAAAA.Exodia:BAAALgAECgYJBgAAAA==.',
Fa='Faeris:BAACLgAFFH8NAAMWAAUJShsuGgCWAQAWAAUJShsuGgCWAQAXAAEJMQ2qEgBPAAAuAAQKfyIAAxcACQkkItMBAFkDABcACQkkItMBAFkDABYAAgnfGodFAI0AAAAA.Faolain:BAABLgAECn8kAAICAAgJQBESRwB0AQACAAgJQBESRwB0AQAAAA==.Fatalis:BAACLgAFFH8mAAIVAAcJjQ3sJAByAQAVAAcJjQ3sJAByAQAuAAQKfywAAxUACQkLHB0bAIMCABUACQkLHB0bAIMCAAMACAlcBLJRAAYBAAAA.Faylin:BAAALgADCgkJGwAAAA==.',
Fe='Fetch:BAAALgAECgkJBgAAAA==.',
Fi='Fiddlestix:BAAALgAECgUJCgAAAA==.Fims:BAAALgAECgYJCgAAAA==.Finarfin:BAAALgADCgkJCQAAAA==.Fireballcat:BAAALgAECgIJAgAAAA==.Fizaw:BAACLgAFFH8LAAIYAAQJlAPXRgCJAAAYAAQJlAPXRgCJAAAuAAQKf0gAAhgACQl5CVZNADgBABgACQl5CVZNADgBAAAA.',
Fl='Floydbussy:BAABLgAFFH8PAAIZAAYJJxQWBADvAAAZAAYJJxQWBADvAAAAAA==.',
Fr='Freeng:BAAALgAECgEJAQAAAA==.Freeze:BAAALgAECgEJAQAAAA==.Freyya:BAAALgAECgkJDAAAAA==.Frøzen:BAAALgAECgQJAgAAAA==.',
Fu='Fuzzydots:BAAALgAECgMJBgAAAA==.',
['Fë']='Fëanør:BAABLgAECn8XAAIBAAgJ7RO0ZgCzAQABAAgJ7RO0ZgCzAQAAAA==.',
Ga='Galana:BAAALgAECgIJAgAAAA==.Galnir:BAAALgAECgMJAwAAAA==.Gatorbait:BAAALgAECgQJBAAAAA==.Gaurr:BAAALgAECgMJBgAAAA==.Gazzcool:BAAALgAECgkJBwAAAA==.',
Ge='Genevah:BAAALgADCgEJAQAAAA==.Geneviere:BAAALgAECgYJCAAAAA==.Gex:BAABLgAECn8UAAIZAAkJhQl5NABhAQAZAAkJhQl5NABhAQAAAA==.',
Gh='Ghostzen:BAACLgAFFH8IAAIaAAMJXBpsIwDHAAAaAAMJXBpsIwDHAAAuAAQKfx0AAhoACQlUJQgBALsDABoACQlUJQgBALsDAAAA.',
Gi='Gislain:BAABLgAECn8eAAMMAAgJUBHROgCWAQAMAAgJUBHROgCWAQAbAAYJ3gzmVwDcAAAAAA==.',
Gn='Gnarladin:BAAALgAECgUJCQAAAA==.',
Go='Goldeye:BAAALgADCgMJAwAAAA==.Gooichi:BAAALgAECgEJAgAAAA==.Gothmogsbane:BAABLgAECn8WAAMCAAgJdBHRVgA1AQACAAYJzRHRVgA1AQAcAAgJKwTEUgDcAAAAAA==.',
Gr='Greaves:BAAALgAECgQJBAABLgAFFAYJHQAdAL8lAA==.Greyspirit:BAACLgAFFH8OAAISAAQJBxuoCwA6AQASAAQJBxuoCwA6AQAuAAQKfz0AAhIACQmFIwICACkDABIACQmFIwICACkDAAAA.Grez:BAAALgAECgQJBgAAAA==.Grubnub:BAAALgADCgEJAQABLgAECgkJOwAMAAQdAA==.',
Gu='Gumpy:BAAALgAECggJDAAAAA==.',
Ha='Hador:BAAALgAECgUJCAAAAA==.Halcoldrek:BAAALgAECgMJAwAAAA==.Hamburguesa:BAAALgAECgMJBAAAAA==.Hanta:BAAALgADCgIJAwAAAA==.Harkiel:BAAALgAECgUJBwAAAA==.Haumea:BAAALgAECgMJAwAAAA==.',
Hb='Hbc:BAABLgAFFH8VAAISAAYJkB4vAABCAgASAAYJkB4vAABCAgABLgAFFAcJHwAQALEdAA==.',
He='Heffer:BAAALgAECgEJAgABLgAECggJCwAOAAAAAA==.Heyz:BAABLgAECn8jAAMWAAgJKRwcEQBhAgAWAAgJKRwcEQBhAgAXAAEJkwCligAhAAAAAA==.',
Hi='Hibernate:BAAALgADCgIJAgAAAA==.Himbo:BAABLgAECn8VAAIVAAkJoAuRUwCoAQAVAAkJoAuRUwCoAQAAAA==.Hipocrit:BAAALgAECgcJCQAAAA==.',
Ho='Hog:BAAALgAECgYJBwAAAA==.Holypoopp:BAACLgAFFH8QAAIJAAQJkBktHgAsAQAJAAQJkBktHgAsAQAuAAQKf1AABAEACQlCIKoSANMCAAEACQlCIKoSANMCAAkABwksGYE4AGsBAAoACQmvDOgYAFQBAAAA.Hondalorian:BAABLgAECn89AAIVAAkJ7BYaKAA+AgAVAAkJ7BYaKAA+AgAAAA==.Honkmydemon:BAAALgADCgMJAwAAAA==.Honkmyscars:BAAALgAECgEJAQAAAA==.Hordranir:BAAALgADCgIJAgAAAA==.',
Hu='Hulksgrnsack:BAAALgAECgcJCwAAAA==.Huntigga:BAAALgAECgkJBwAAAA==.',
['Hë']='Hëxy:BAAALgADCgYJBgAAAA==.',
Ih='Ihatemeta:BAAALgAFFAEJAQAAAA==.',
Il='Illidaldin:BAAALgADCgcJBwABLgAECgkJKwAeAJkZAA==.',
Im='Imran:BAACLgAFFH8bAAIKAAQJzQsFCwDFAAAKAAQJzQsFCwDFAAAuAAQKf2cAAwoACQlUHYwEALMCAAoACQlUHYwEALMCAAEABwmhBKXPAOoAAAAA.',
In='Inkdawarlock:BAAALgAECgEJAQAAAA==.Innit:BAAALgAECgEJAQABLgAECggJCwAOAAAAAA==.Inthelayer:BAAALgAECgYJCAABLgAECggJCwAOAAAAAA==.',
['Iå']='Iåomai:BAAALgADCgMJAwAAAA==.',
Ja='Jabronee:BAABLgAECn8cAAIRAAYJUBsZNwBrAQARAAYJUBsZNwBrAQAAAA==.',
Je='Jerikoh:BAAALgAECgEJBQAAAA==.Jershdahunta:BAAALgADCgkJDgABLgAECggJDQAOAAAAAA==.Jether:BAABLgAECn8aAAIBAAcJTgQRDAGqAAABAAcJTgQRDAGqAAAAAA==.',
Jk='Jkingoreborn:BAABLgAECn8gAAIKAAcJjyHmCQAvAgAKAAcJjyHmCQAvAgABLgAECggJIwAVAJQXAA==.',
Jo='Jodormi:BAAALgADCgkJCQABLgAECgkJHQAeAM0YAA==.Jodrin:BAAALgADCgEJAQAAAA==.Jojobaggins:BAABLgAECn8aAAQfAAcJPhpkDQBTAQAEAAUJeRdkMQB8AQAfAAcJFhdkDQBTAQAgAAQJLBpTBwAwAQAAAA==.Jopine:BAAALgAECgEJAQABLgAECgkJHQAeAM0YAA==.',
Ka='Kaadriluna:BAAALgADCggJDQAAAA==.Kaena:BAAALgADCgYJBgAAAA==.Kaey:BAAALgAECgQJBAAAAA==.Kaname:BAAALgAECgYJEAAAAA==.Katalyst:BAAALgAECgIJAgAAAA==.',
Ke='Keiri:BAAALgADCgMJAwAAAA==.Keyholes:BAABLgAFFH8XAAIhAAYJaBjuEgBeAQAhAAYJaBjuEgBeAQABLgAFFAcJHwAQALEdAA==.Keyohs:BAAALgAECgUJBQABLgAFFAcJHwAQALEdAA==.',
Kh='Khe:BAAALgAECgcJCQABLgAECgkJOwAMAAQdAA==.',
Ki='Kittybear:BAAALgAFFAEJAQABLgAFFAgJIwAQANwiAA==.',
Kk='Kkoda:BAAALgAECgYJDQAAAA==.',
Ko='Koal:BAABLgAECn8hAAIVAAgJuhg5SADJAQAVAAgJuhg5SADJAQAAAA==.Kodabear:BAAALgADCgcJBwAAAA==.',
Kp='Kpop:BAAALgADCgcJBwABLgAFFAkJRAAVAPglAA==.',
Kr='Kreen:BAAALgADCgcJBwAAAA==.Krom:BAABLgAECn8VAAMBAAcJsATH/AC7AAABAAcJsATH/AC7AAAKAAEJGABWUAADAAABLgAECggJMQAMAD4QAA==.Kronos:BAAALgAECgcJBwABLgAECgYJCgAOAAAAAA==.',
Ku='Kuroneko:BAAALgAFFAIJAwAAAA==.Kushage:BAAALgAECgEJAQAAAA==.',
Ky='Kyomu:BAAALgADCgMJAwAAAA==.Kyracia:BAAALgAECgcJBwAAAA==.',
La='Lara:BAABLgAECn8iAAMVAAgJhg98aAByAQAVAAgJhg98aAByAQADAAYJ/goTSwAmAQAAAA==.Lavaa:BAAALgADCgEJAQAAAA==.',
Le='Leibniz:BAAALgADCgMJAwAAAA==.Lesgoth:BAAALgAECgcJCQAAAA==.Lettussy:BAABLgAFFH8TAAQEAAUJPCGQDADLAQAEAAUJPCGQDADLAQAgAAQJCgd2CAD4AAAfAAEJRwpuEwA8AAABLgAFFAgJHgAFAPsXAA==.Ley:BAAALgAECgUJBgAAAA==.Leya:BAAALgAECgIJAgAAAA==.',
Li='Lightsbelow:BAAALgADCgYJCAAAAA==.Lix:BAACLgAFFH8FAAICAAMJGAmcSwCOAAACAAMJGAmcSwCOAAAuAAQKfygAAgIACQmsETIwAOEBAAIACQmsETIwAOEBAAAA.Lixxi:BAAALgAECgYJBgABLgAFFAMJBQACABgJAA==.',
Lo='Loliruri:BAAALgAECgYJDgAAAA==.Loreleì:BAAALgADCgMJAwAAAA==.Louis:BAAALgAECgEJAQAAAA==.',
Lu='Luffymd:BAAALgAECgQJBwAAAA==.Luminyssa:BAAALgAECgYJBwAAAA==.',
['Lú']='Lúthien:BAABLgAECn80AAIYAAkJ5iKuBwAiAwAYAAkJ5iKuBwAiAwAAAA==.',
Ma='Madoka:BAAALgAECgYJDwAAAA==.Makari:BAAALgADCgMJAwAAAA==.Marditoloko:BAAALgAECgQJBAAAAA==.Matrix:BAAALgAECgcJDQAAAA==.Mavenn:BAAALgAECgEJAQAAAA==.Maxchungus:BAABLgAECn81AAMNAAkJ8yFeGwCjAgANAAkJ8yFeGwCjAgAhAAYJPQ8WJAAgAQAAAA==.',
Me='Meatsuit:BAAALgAECgIJAgAAAA==.Meigetsuki:BAAALgADCgQJBAABLgAECgIJBAAOAAAAAA==.Meloo:BAABLgAECn85AAMUAAkJNBv3CgB4AgAUAAkJNBv3CgB4AgAiAAYJ2Aa+vgCvAAAAAA==.Meteor:BAAALgADCgUJBQAAAA==.',
Mi='Mightguy:BAAALgAECgEJAQAAAA==.Mikehawncho:BAAALgAECgQJBwABLgAECgcJHgANAFUbAA==.Mizu:BAAALgAECgMJAwAAAA==.',
Mo='Moknahddon:BAAALgADCgQJBAAAAA==.Moment:BAABLgAECn8hAAIIAAkJ0xnWAwBMAgAIAAkJ0xnWAwBMAgAAAA==.Morthrisia:BAAALgADCgUJBQABLgAECgEJAQAOAAAAAA==.',
Mu='Muna:BAAALgAECgEJAQAAAA==.Murraneth:BAAALgAECgEJAQAAAA==.Murrmau:BAABLgAECn8aAAIVAAYJ2wnangAEAQAVAAYJ2wnangAEAQAAAA==.Muufarmer:BAAALgADCggJCAAAAA==.',
My='Mydude:BAAALgAECgcJEwAAAA==.',
Na='Naerys:BAAALgAECggJDQAAAA==.Nalguilidan:BAAALgADCgYJBgAAAA==.Natedk:BAAALgAECgIJAwAAAA==.Natmau:BAAALgADCgQJBAAAAA==.Naughtyelf:BAAALgAECgYJCAAAAA==.',
Ne='Nemene:BAAALgADCgEJAQAAAA==.Neyt:BAABLgAECn8pAAMiAAkJKBt3IABSAgAiAAkJKBt3IABSAgAUAAEJiRURcAA1AAAAAA==.',
Ni='Niddalee:BAAALgAECgcJEQAAAA==.Nioh:BAAALgAECgYJDwAAAA==.Niohscuck:BAAALgADCgEJAQAAAA==.Nitesrider:BAAALgAECgQJCAAAAA==.',
No='Nora:BAACLgAFFH8/AAIBAAkJiCUxAAB5AwABAAkJiCUxAAB5AwAuAAQKf0gAAwEACQnbJnMAAJcDAAEACQnbJnMAAJcDAAkAAwktFs9cAMIAAAAA.Nori:BAAALgADCgkJDgABLgAFFAgJMgAFAFIkAA==.Noshikoshi:BAAALgAECgIJAwAAAA==.Nostrodom:BAAALgAECgYJEAAAAA==.',
Nu='Nubbs:BAABLgAECn8fAAIaAAkJCx84BwDWAgAaAAkJCx84BwDWAgAAAA==.Nubkillaa:BAAALgAECgMJAwAAAA==.',
Ny='Nyissa:BAAALgAECgMJAwAAAA==.Nyonà:BAAALgADCgQJBAAAAA==.',
Oc='Octas:BAAALgAECgMJAwABLgAFFAYJGgAHAGYSAA==.',
Of='Offen:BAAALgAECgIJAgAAAA==.',
Og='Ogmonkas:BAAALgAECgEJAgAAAA==.',
On='On:BAAALgAECgUJCAAAAA==.Onlyinusa:BAACLgAFFH8GAAISAAMJNSELAQAXAQASAAMJNSELAQAXAQAuAAQKfy4AAhIACQlmJHsBAEIDABIACQlmJHsBAEIDAAAA.Onyxnate:BAAALgADCgkJJQAAAA==.',
Op='Opalith:BAAALgAECgIJAgABLgAECgMJAwAOAAAAAA==.Opel:BAAALgAECgIJAgABLgAFFAUJJQAaAKASAA==.Opi:BAAALgADCgcJBwAAAA==.',
Or='Orbyn:BAAALgADCgEJAQAAAA==.Ortah:BAAALgADCgEJAQAAAA==.',
Ox='Oxyrania:BAAALgADCgEJAQAAAA==.',
Pa='Paladigga:BAAALgAECgkJEAAAAA==.Pandalorenzo:BAAALgADCgEJAQAAAA==.',
Pf='Pfhor:BAAALgAECgYJBgAAAA==.',
Ph='Phillyshiho:BAAALgAECgcJEwABLgAECgkJIQAjAPEQAA==.',
Pi='Pinkdefender:BAAALgAECggJEAABLgAFFAQJGwANAOscAA==.',
Po='Pokeumon:BAAALgADCgEJAQAAAA==.Poor:BAAALgAECgMJBwAAAA==.Poosistrox:BAACLgAFFH8bAAQNAAQJ6xxVRgBnAQANAAQJ6xxVRgBnAQAkAAMJhA6yFwDNAAAhAAEJkAW/PwAyAAAuAAQKfyIAAw0ACAkoHrUvAHkCAA0ACAkoHrUvAHkCACEABAnvDBw3AIkAAAAA.Pornelius:BAAALgAECgcJCwABLgAECgkJMgAPAG0eAA==.Potumkin:BAAALgADCgQJBgAAAA==.',
Pt='Ptheve:BAACLgAFFH9DAAMUAAkJeiYGAACPAwAUAAkJeiYGAACPAwAiAAgJACHbAACgAgAuAAQKfykAAyIACQmvJXcBAMgDACIACQmoJXcBAMgDABQABwmNJKoUACsCAAAA.',
Pu='Pump:BAAALgADCgEJAQAAAA==.Putang:BAAALgAECgEJAQAAAA==.',
['På']='Pållås:BAAALgADCgMJAwAAAA==.',
Qn='Qnyx:BAABLgAECn8nAAIjAAcJfRKwMgBPAQAjAAcJfRKwMgBPAQAAAA==.',
Ra='Raelindra:BAABLgAECn8dAAIeAAkJzRixBQAQAgAeAAkJzRixBQAQAgAAAA==.Rahnarmight:BAAALgADCgQJBAAAAA==.Rayalla:BAAALgADCgUJBQAAAA==.Raygor:BAAALgAECgkJEQAAAA==.',
Re='Rebuke:BAABLgAECn8gAAIBAAgJjBlcPAATAgABAAgJjBlcPAATAgAAAA==.Renewal:BAAALgAECgUJBQAAAA==.',
Ro='Rookorblood:BAABLgAECn8bAAIRAAYJWwbfYwDKAAARAAYJWwbfYwDKAAAAAA==.Rosewalker:BAACLgAFFH8cAAIHAAYJbCRCCAAMAgAHAAYJbCRCCAAMAgAuAAQKf0EAAwcACQk9JToCAD4DAAcACQk9JToCAD4DABoACQnrHjkHANYCAAAA.Rosewall:BAAALgAECgQJBQABLgAFFAYJHAAHAGwkAA==.Rottgut:BAAALgAECgYJDQAAAA==.',
Ru='Rustyjux:BAAALgAECgIJAwAAAA==.',
Ry='Ryachun:BAAALgADCgMJAwAAAA==.Rykò:BAACLgAFFH8JAAIVAAMJbh9gRAAlAQAVAAMJbh9gRAAlAQAuAAQKf0QABBUACQliJGoEAEoDABUACQliJGoEAEoDACUABgkaB9k7AOEAAAMABQnsEDdeAMgAAAAA.',
Sa='Salchaos:BAABLgAECn8eAAQPAAgJCRZ5DwCkAQARAAcJiRZPMgDjAQAPAAcJ2xR5DwCkAQAQAAQJMxAiLgDRAAAAAA==.Samsmith:BAAALgAECgYJBgAAAA==.Sanel:BAAALgADCgcJBwAAAA==.Sassy:BAAALgAFFAMJAwAAAA==.Savork:BAABLgAECn8jAAMVAAgJlBcwOQD5AQAVAAgJlBcwOQD5AQADAAYJog6wRgA6AQAAAA==.Sayafaed:BAACLgAFFH8LAAIiAAQJpAPWaQC5AAAiAAQJpAPWaQC5AAAuAAQKfy0AAiIACQmNDvRNAJwBACIACQmNDvRNAJwBAAAA.Sayamese:BAAALgAECggJEwAAAA==.',
Sc='Scatback:BAABLgAECn86AAQWAAkJeRj2FgAfAgAWAAkJPBL2FgAfAgAXAAgJQxkxGgD5AQAjAAMJvQlihwAyAAAAAA==.Schwiddylock:BAAALgAECgUJCgAAAA==.Scud:BAABLgAECn8fAAIjAAkJMw2qLwBgAQAjAAkJMw2qLwBgAQAAAA==.Scáthach:BAAALgADCgcJEAAAAA==.',
Se='Seint:BAAALgADCgYJBgAAAA==.Senuna:BAAALgADCgIJAQAAAA==.Seraphae:BAAALgADCgMJAwAAAA==.Seraphnite:BAAALgAECgQJBAAAAA==.',
Sh='Shadowdaddy:BAABLgAECn8hAAIjAAkJ8RDrIgCxAQAjAAkJ8RDrIgCxAQAAAA==.Shadyshifts:BAABLgAFFH8FAAISAAMJbAt6JQCFAAASAAMJbAt6JQCFAAABLgAFFAQJGwANAOscAA==.Shadôwhunt:BAABLgAECn8fAAINAAgJchWAXQDaAQANAAgJchWAXQDaAQAAAA==.Shenlon:BAACLgAFFH8rAAMIAAYJQyGFAQCWAQAZAAYJLx0JFgC9AQAIAAUJISaFAQCWAQAuAAQKfy4ABAgACQm+JJMAAI0DAAgACQmPIZMAAI0DABMABQlvHZETAJEBABkABAmKI9AlAI8BAAAA.Shilor:BAABLgAECn8nAAIWAAkJ3hamGQADAgAWAAkJ3hamGQADAgAAAA==.Shogun:BAABLgAECn8VAAIUAAkJ6BHUHgCEAQAUAAkJ6BHUHgCEAQAAAA==.Shulamite:BAAALgADCgYJBgAAAA==.Shuye:BAAALgAECgQJBQAAAA==.',
Si='Sicarii:BAAALgAECgEJAQABLgAECgcJDgAOAAAAAA==.Sicarrious:BAAALgAECgcJDgAAAA==.Sinaliska:BAAALgADCgQJBAAAAA==.Sinistr:BAABLgAECn8WAAMMAAcJChyjJwDyAQAMAAcJChyjJwDyAQALAAQJIAUfIgCyAAAAAA==.',
Sk='Skyarc:BAAALgAECgUJBwAAAA==.Skyrun:BAAALgAECgMJBAABLgAECgUJBwAOAAAAAA==.',
Sm='Smiffbrew:BAAALgADCgMJBAAAAA==.Smiffury:BAAALgAECgYJCQAAAA==.',
Sn='Snicks:BAAALgAECgIJAgAAAA==.',
Sq='Squishyshoe:BAAALgAECgEJAQAAAA==.',
St='Stinkythebum:BAABLgAECn8bAAIaAAgJVBo1EwAkAgAaAAgJVBo1EwAkAgAAAA==.Stoneymalone:BAAALgAECgIJAwAAAA==.Stopusingmet:BAAALgAECgYJBwAAAA==.Stélle:BAABLgAECn8sAAIDAAkJRQ6qDACYAQADAAkJRQ6qDACYAQAAAA==.',
Su='Supdude:BAACLgAFFH8GAAIEAAIJuRkaBQCtAAAEAAIJuRkaBQCtAAAuAAQKfzkAAwQACQkXI+YDAAMDAAQACQkXI+YDAAMDACAAAQlpHPYNADoAAAAA.',
Ta='Tairnbys:BAAALgAECgMJAwAAAA==.Tanthe:BAAALgAECgEJAQAAAA==.Tazbirkloa:BAAALgADCgIJAgAAAA==.',
Te='Tebzerk:BAAALgAECgcJDgAAAA==.Tekk:BAAALgAECgcJCgAAAA==.Temptress:BAAALgADCgIJAwAAAA==.',
Th='Thatssotank:BAAALgAECgYJDQABLgAFFAUJDQAFAAgRAA==.Thorokk:BAAALgAECgMJAwAAAA==.Thynrage:BAAALgAECgUJBgAAAA==.',
Ti='Tictac:BAAALgADCgUJBQAAAA==.Tigas:BAACLgAFFH8PAAIRAAMJkCFqBAC3AAARAAMJkCFqBAC3AAAuAAQKfy4AAxEACAnQJN0KALgCABEACAnQJN0KALgCAA8AAQljFnhuAEQAAAAA.',
To='Todimo:BAAALgAECgIJAgAAAA==.Tooth:BAAALgAECgEJAgAAAA==.Tor:BAAALgADCgMJAwABLgAECgcJEQAOAAAAAA==.',
Tr='Trashdragon:BAABLgAECn8xAAMIAAkJWyJzAQDiAgAIAAkJPCFzAQDiAgAZAAgJNx6yDgCKAgAAAA==.Trauma:BAAALgAECgMJAwAAAA==.',
Ty='Tygrans:BAAALgADCgUJBQAAAA==.Typhoonz:BAAALgADCgEJAQAAAA==.',
['Tö']='Töby:BAAALgAECgcJEQAAAA==.',
Ul='Ulric:BAAALgAECgQJBQAAAA==.',
Um='Umgunk:BAAALgAECgQJBQAAAA==.Ummabunbun:BAAALgADCgMJAwAAAA==.',
Un='Unorthodox:BAAALgAECgUJCAAAAA==.',
Us='Usagi:BAABLgAECn8dAAIBAAcJ9huWWADCAQABAAcJ9huWWADCAQAAAA==.',
Ut='Utsuro:BAAALgAECgMJAwABLgAECggJDAAOAAAAAA==.',
Va='Vannacutt:BAABLgAECn8UAAIRAAgJkgzYPABSAQARAAgJkgzYPABSAQABLgAECggJDAAOAAAAAA==.Vaz:BAAALgAECgQJBAAAAA==.',
Ve='Velzevul:BAAALgADCgYJDAAAAA==.Vermouth:BAAALgAECgUJCAAAAA==.',
Vi='Vincentx:BAAALgADCgUJCwAAAA==.',
Vv='Vvinter:BAAALgAECgEJAQAAAA==.',
Vy='Vynii:BAACLgAFFH8OAAIiAAQJKAncWQDiAAAiAAQJKAncWQDiAAAuAAQKf0AABCIACQmFGn8lADgCACIACQl5F38lADgCABQABgmCGDwmAI4BAB0AAQk0D7E1AC8AAAAA.',
Wa='Wallofstars:BAAALgAECgQJBAAAAA==.Wardamage:BAAALgADCgYJBgAAAA==.Wasabi:BAABLgAECn8WAAITAAkJVhSUCwAgAgATAAkJVhSUCwAgAgAAAA==.',
We='Weedcenters:BAAALgAECgQJBQAAAA==.Weenygripper:BAABLgAECn8XAAINAAcJnxHokABEAQANAAcJnxHokABEAQABLgAFFAYJDwAFAF0gAA==.',
Wf='Wfaps:BAAALgAECgQJCAAAAA==.',
Wh='Whytho:BAAALgAECgcJBwAAAA==.',
Wo='Wonon:BAAALgAFFAEJAQAAAA==.Wontonboy:BAAALgAECgEJAgAAAA==.',
Wu='Wuufi:BAAALgADCgYJBgAAAA==.',
Xa='Xaam:BAAALgAECgUJCAAAAA==.Xaida:BAACLgAFFH8nAAIYAAkJ4hkaAwAGAwAYAAkJ4hkaAwAGAwAuAAQKfxYAAwcACQl7DF4lAIMBAAcACQl7DF4lAIMBABgAAQmUHzSeAFwAAAAA.',
Xe='Xecutioner:BAAALgAECgYJDwAAAA==.',
Xi='Xilantaeki:BAAALgAECgQJBAAAAA==.',
Yq='Yqwegvbwefhu:BAAALgAECgMJBwAAAA==.',
Za='Zangyaku:BAABLgAECn8iAAIhAAkJrCWvAQBCAwAhAAkJrCWvAQBCAwAAAA==.Zanmetsu:BAABLgAECn8dAAMEAAcJrRyNGABDAgAEAAcJrRyNGABDAgAfAAEJjgzsHgA4AAABLgAECgkJIgAhAKwlAA==.Zarlock:BAAALgADCgYJBgAAAA==.',
Ze='Zeji:BAABLgAECn87AAMMAAkJBB1yDwDXAgAMAAkJBB1yDwDXAgAbAAQJmRqESQAOAQAAAA==.Zerocool:BAABLgAECn8fAAImAAkJBRMrQgAGAgAmAAkJBRMrQgAGAgAAAA==.',
Zu='Zuggernaut:BAAALgADCgYJBgAAAA==.Zugquavious:BAABLgAECn8UAAMPAAcJKQusNwDmAAAPAAYJPAysNwDmAAAQAAcJ1ghbKwDcAAABLgAECggJHAALANYaAA==.Zugzug:BAAALgAECgMJAwAAAA==.',
Zy='Zyggy:BAABLgAECn8UAAIcAAgJJxHsLABxAQAcAAgJJxHsLABxAQAAAA==.',
['ßa']='ßadfish:BAABLgAECn8iAAIBAAkJ/CPqGADTAgABAAkJ/CPqGADTAgAAAA==.',
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
