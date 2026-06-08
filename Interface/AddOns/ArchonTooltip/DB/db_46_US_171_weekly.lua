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

local lookup = {'Paladin-Retribution','Druid-Restoration','Hunter-Marksmanship','Rogue-Subtlety','Mage-Frost','Monk-Brewmaster','Evoker-Devastation','Paladin-Holy','Paladin-Protection','Shaman-Enhancement','Shaman-Restoration','DeathKnight-Unholy','Unknown-Unknown','Warrior-Arms','Warrior-Protection','Warrior-Fury','Druid-Guardian','Evoker-Preservation','DemonHunter-Havoc','Hunter-BeastMastery','Priest-Discipline','Priest-Holy','Monk-Mistweaver','Evoker-Augmentation','Monk-Windwalker','Shaman-Elemental','Druid-Balance','DemonHunter-Vengeance','Warlock-Destruction','Rogue-Assassination','Rogue-Outlaw','DeathKnight-Blood','DemonHunter-Devourer','Priest-Shadow','DeathKnight-Frost','Hunter-Survival','Warlock-Demonology',}
local provider = {region='US',realm='Onyxia',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abrams:BAABLgAECn8bAAIBAAgJ+hmsUgDHAQABAAgJ+hmsUgDHAQAAAA==.',
Ad='Addý:BAABLgAECn8XAAICAAkJgBeuJgAQAgACAAkJgBeuJgAQAgAAAA==.Advanced:BAAALgADCgQJAQAAAA==.',
Ah='Ahimsa:BAACLgAFFH8HAAIDAAMJ+xpRFwDpAAADAAMJ+xpRFwDpAAAuAAQKfz4AAgMACQmiIjQBABUDAAMACQmiIjQBABUDAAAA.',
Al='Alisonchains:BAABLgAECn8sAAIEAAgJPCDdCQB7AgAEAAgJPCDdCQB7AgAAAA==.Alkyri:BAAALgAECgEJAQAAAA==.Almamun:BAAALgAECgIJAwAAAA==.Alternate:BAACLgAFFH8FAAIFAAMJ7RUzcQDvAAAFAAMJ7RUzcQDvAAAuAAQKfzsAAgUACQkGHnsZALoCAAUACQkGHnsZALoCAAAA.',
Am='Amigo:BAAALgADCgEJAQAAAA==.Amillerbrew:BAABLgAECn8aAAIGAAgJTxaYJQDXAQAGAAgJTxaYJQDXAQAAAA==.',
An='Anayanci:BAAALgAECgQJDAAAAA==.Anesh:BAAALgAECgMJBQAAAA==.Anjuna:BAAALgAECgYJDwAAAA==.Anshee:BAAALgAECgIJAwAAAA==.Anubrin:BAAALgADCgUJBwAAAA==.',
Ap='Aphian:BAAALgAECgIJAgAAAA==.',
As='Ashenclaw:BAABLgAECn81AAIHAAgJIRtZBAAoAgAHAAgJIRtZBAAoAgAAAA==.',
Au='Auzatryx:BAABLgAECn8VAAIEAAcJ/Ay8KQA6AQAEAAcJ/Ay8KQA6AQAAAA==.',
Ba='Bagpipe:BAAALgADCgkJCQAAAA==.Bamboom:BAABLgAECn8fAAQIAAcJsBa8JgDJAQAIAAcJsBa8JgDJAQABAAEJFgIuuAEYAAAJAAEJRAHATwARAAAAAA==.Bapbap:BAAALgADCgYJBgAAAA==.',
Be='Beefstick:BAAALgAECgMJAgAAAA==.Belanik:BAAALgAECgEJBQAAAA==.Beleth:BAAALgADCgYJBgAAAA==.',
Bi='Bigblktotem:BAABLgAECn8WAAMKAAYJlAzwFwBDAQAKAAYJlAzwFwBDAQALAAMJHQRDrgBbAAABLgAFFAQJEQAMAMcYAA==.Biggrnmonstr:BAAALgAFFAIJAgABLgAFFAQJEQAMAMcYAA==.Bigheffin:BAAALgAECgIJAgABLgAECggJCgANAAAAAA==.Bigrabit:BAAALgAECgMJAwAAAA==.Bigslammin:BAAALgAECgQJBQAAAA==.Bigxthezug:BAAALgAECgQJBgABLgAECggJCgANAAAAAA==.Biirf:BAAALgAECgUJBgAAAA==.',
Bl='Blaine:BAAALgAECgQJCgAAAA==.Blãze:BAAALgADCgIJAgAAAA==.',
Bo='Bogdan:BAAALgADCgEJAQAAAA==.Bomi:BAAALgAECgQJCQAAAA==.Boogiebm:BAAALgAECgcJCwAAAA==.Borgon:BAAALgAECgEJAgAAAA==.Bowevil:BAAALgADCgMJAwAAAA==.Boypartz:BAABLgAECn8yAAMOAAkJbR4JBQC0AgAOAAkJbR4JBQC0AgAPAAEJKwmNTQAiAAAAAA==.',
Br='Brayuh:BAAALgAECgEJAgAAAA==.Breakfast:BAAALgAECggJCgAAAA==.',
Bu='Bulbasaurus:BAACLgAFFH8WAAIQAAUJQyV9CQCsAQAQAAUJQyV9CQCsAQAuAAQKfx8AAhAACQmjInoHADEDABAACQmjInoHADEDAAAA.Bulloney:BAAALgADCgIJAgAAAA==.Bunana:BAAALgADCgIJAgAAAA==.Bus:BAAALgAFFAMJBAABLgAFFAkJHAARAP8jAA==.',
Ca='Cabooze:BAAALgAECgYJBwAAAA==.Cacho:BAAALgAECgQJCAAAAA==.Cañonazo:BAAALgAECgEJAQAAAA==.',
Ce='Celeres:BAABLgAECn8eAAISAAgJeBgiEQAqAgASAAgJeBgiEQAqAgAAAA==.Celys:BAAALgAECgUJBgAAAA==.Cerealkillah:BAAALgAECgEJAQAAAA==.',
Ch='Chantilly:BAAALgAECgYJDwAAAA==.Chartreuse:BAAALgADCgMJBAABLgAECgUJCAANAAAAAA==.Chaw:BAAALgAECgEJAQAAAA==.Cheesecurds:BAAALgADCgcJBwAAAA==.Cheesied:BAAALgADCgQJAwAAAA==.Chios:BAAALgAECgUJBQABLgAFFAcJHAAPALEdAA==.',
Cl='Cleetiscat:BAAALgAECgYJBgAAAA==.',
Co='Cowabunga:BAAALgADCgEJAQAAAA==.',
Cr='Crow:BAAALgAFFAcJFQAAAQ==.Cryoblade:BAAALgADCgcJDAAAAA==.',
Cu='Cuttanee:BAAALgAECggJDAAAAA==.',
Cy='Cyril:BAAALgADCgkJFwAAAA==.',
Da='Daevon:BAAALgAECgQJEAAAAA==.Daron:BAAALgAECgcJDgABLgAECgcJEQANAAAAAA==.Darrowreaper:BAABLgAECn8eAAIMAAgJzQ22bwB9AQAMAAgJzQ22bwB9AQAAAA==.',
De='Deadcell:BAAALgAECgYJBwAAAA==.Deatheria:BAAALgADCgMJAwAAAA==.Deathstar:BAAALgAECgUJBQAAAA==.Denarrage:BAACLgAFFH8SAAITAAUJUAlAEwD0AAATAAUJUAlAEwD0AAAuAAQKfy4AAhMACQnuFA8UAOMBABMACQnuFA8UAOMBAAAA.Denawage:BAAALgAECggJCAAAAA==.',
Di='Dirtytotem:BAABLgAECn8ZAAIKAAgJ1hoMCAA4AgAKAAgJ1hoMCAA4AgAAAA==.Discordia:BAAALgAECggJDQAAAA==.Disprop:BAAALgAECgEJAQAAAA==.Dizyizy:BAAALgAECgUJBwAAAA==.',
Dk='Dkigga:BAAALgAECgUJAQAAAA==.',
Do='Doingmost:BAAALgAECgEJAgAAAA==.Dontnerfspls:BAAALgAECgQJBgABLgAFFAQJEQAMAMcYAA==.Doomby:BAABLgAECn8UAAIUAAgJnRJ3SQC5AQAUAAgJnRJ3SQC5AQABLgAECgkJOQATADQbAA==.',
Dr='Drakesh:BAAALgADCgEJAQAAAA==.Drakussy:BAAALgAECggJEwABLgAECgkJOQATADQbAA==.Drudekay:BAAALgAECgEJAQAAAA==.',
Du='Dullslinkie:BAAALgADCgEJAQAAAA==.',
El='Eldarborn:BAAALgAECgUJBQAAAA==.Eldruida:BAAALgAECgIJAgAAAA==.Eleannar:BAAALgAECgEJAQAAAA==.Elficpaladin:BAAALgAECgYJCQAAAA==.Elixxi:BAAALgAECgUJCwAAAA==.Elladin:BAAALgADCgcJBwAAAA==.Ellipsi:BAAALgAECgcJDQAAAA==.Ellipsoro:BAACLgAFFH8KAAIMAAMJBB6DfwD1AAAMAAMJBB6DfwD1AAAuAAQKfy4AAgwACQl4JXkIACcDAAwACQl4JXkIACcDAAAA.Eltrol:BAACLgAFFH8QAAIUAAQJ8QmNRwAMAQAUAAQJ8QmNRwAMAQAuAAQKfxkAAhQACQmfFQslAEICABQACQmfFQslAEICAAAA.Eluriana:BAAALgAECgYJCAABLgAFFAUJGQAGAKcRAA==.',
Eq='Eques:BAAALgAECgYJBgAAAA==.',
Er='Erale:BAAALgADCgYJDAAAAA==.Eredarn:BAAALgADCgEJAQAAAA==.Erienor:BAAALgADCgkJDAAAAA==.',
Ev='Evldrprkchop:BAAALgADCgIJAgAAAA==.',
Ex='Executiepie:BAACLgAFFH8cAAIPAAcJsR0NAwA0AgAPAAcJsR0NAwA0AgAuAAQKfysAAg8ACQmTJc4AAGMDAA8ACQmTJc4AAGMDAAAA.Exodia:BAAALgAECgYJBgAAAA==.',
Fa='Faeris:BAACLgAFFH8NAAMVAAUJShtVFgCdAQAVAAUJShtVFgCdAQAWAAEJMQ2qEgBPAAAuAAQKfyIAAxYACQkkItMBAFkDABYACQkkItMBAFkDABUAAgnfGodFAI0AAAAA.Faolain:BAABLgAECn8kAAICAAgJQBE6RAB2AQACAAgJQBE6RAB2AQAAAA==.Fatalis:BAACLgAFFH8iAAIUAAYJ4AsIKQBTAQAUAAYJ4AsIKQBTAQAuAAQKfywAAxQACQkLHBAYAIoCABQACQkLHBAYAIoCAAMACAlcBLJRAAYBAAAA.Faylin:BAAALgADCgkJCQAAAA==.',
Fe='Fetch:BAAALgAECgkJBgAAAA==.',
Fi='Fiddlestix:BAAALgAECgUJCgAAAA==.Fims:BAAALgAECgYJCgAAAA==.Finarfin:BAAALgADCgkJCQAAAA==.Fireballcat:BAAALgAECgIJAgAAAA==.Fizaw:BAACLgAFFH8HAAIXAAQJ8AKbPQCMAAAXAAQJ8AKbPQCMAAAuAAQKfz0AAhcACQlLCBpKACoBABcACQlLCBpKACoBAAAA.',
Fl='Floydbussy:BAABLgAFFH8LAAIYAAYJngx3IQA7AQAYAAYJngx3IQA7AQAAAA==.',
Fr='Freeng:BAAALgADCgYJBgAAAA==.Freeze:BAAALgAECgEJAQAAAA==.Freyya:BAAALgAECgkJDAAAAA==.Frøzen:BAAALgAECgQJAgAAAA==.',
Fu='Fuzzydots:BAAALgAECgMJBgAAAA==.',
['Fë']='Fëanør:BAABLgAECn8XAAIBAAgJ7RO0ZgCzAQABAAgJ7RO0ZgCzAQAAAA==.',
Ga='Galana:BAAALgADCgQJBAAAAA==.Galnir:BAAALgAECgMJAwAAAA==.Gatorbait:BAAALgAECgQJBAAAAA==.Gaurr:BAAALgAECgMJBgAAAA==.Gazzcool:BAAALgAECgkJBwAAAA==.',
Ge='Geneviere:BAAALgAECgYJCAAAAA==.Gex:BAABLgAECn8UAAIYAAkJhQkVMQBoAQAYAAkJhQkVMQBoAQAAAA==.',
Gh='Ghostzen:BAACLgAFFH8IAAIZAAMJXBr+HgDVAAAZAAMJXBr+HgDVAAAuAAQKfx0AAhkACQlUJQgBALsDABkACQlUJQgBALsDAAAA.',
Gi='Gislain:BAABLgAECn8eAAMLAAgJUBHROgCWAQALAAgJUBHROgCWAQAaAAYJ3gxXUgDeAAAAAA==.',
Go='Goldeye:BAAALgADCgMJAwAAAA==.Gooichi:BAAALgAECgEJAgAAAA==.Gothmogsbane:BAABLgAECn8WAAMCAAgJdBFnVAA0AQACAAYJzRFnVAA0AQAbAAgJKwTEUgDcAAAAAA==.',
Gr='Greaves:BAAALgAECgQJBAABLgAFFAYJHQAcAL8lAA==.Greyspirit:BAACLgAFFH8HAAIRAAQJwBdbDAAYAQARAAQJwBdbDAAYAQAuAAQKfzYAAhEACQl6IdMCAPkCABEACQl6IdMCAPkCAAAA.Grez:BAAALgAECgQJBgAAAA==.Grubnub:BAAALgADCgEJAQABLgAECgkJOwALAAQdAA==.',
Gu='Gumpy:BAAALgAECggJDAAAAA==.',
Ha='Hador:BAAALgAECgUJCAAAAA==.Halcoldrek:BAAALgAECgMJAwAAAA==.Hamburguesa:BAAALgAECgMJBAAAAA==.Hanta:BAAALgADCgIJAwAAAA==.Harkiel:BAAALgAECgUJBwAAAA==.Haumea:BAAALgAECgMJAwAAAA==.',
Hb='Hbc:BAABLgAFFH8KAAIRAAQJ7COdBAClAQARAAQJ7COdBAClAQABLgAFFAcJHAAPALEdAA==.',
He='Heyz:BAABLgAECn8jAAMVAAgJKRz4DwBkAgAVAAgJKRz4DwBkAgAWAAEJkwCligAhAAAAAA==.',
Hi='Hibernate:BAAALgADCgIJAgAAAA==.Himbo:BAAALgAECggJEAAAAA==.Hipocrit:BAAALgAECgcJCQAAAA==.',
Ho='Hog:BAAALgAECgYJBwAAAA==.Holypoopp:BAACLgAFFH8JAAIIAAQJQRbpHwAUAQAIAAQJQRbpHwAUAQAuAAQKf0MABAEACQm1H3gUAL8CAAEACQm1H3gUAL8CAAkACQmvDHcXAFYBAAgABgkpFHpKAE4BAAAA.Hondalorian:BAABLgAECn89AAIUAAkJ7BZ/JABFAgAUAAkJ7BZ/JABFAgAAAA==.Honkmydemon:BAAALgADCgMJAwAAAA==.Honkmyscars:BAAALgAECgEJAQAAAA==.Hordranir:BAAALgADCgIJAgAAAA==.',
Hu='Hulksgrnsack:BAAALgAECgcJCwAAAA==.',
['Hë']='Hëxy:BAAALgADCgYJBgAAAA==.',
Il='Illidaldin:BAAALgADCgcJBwABLgAECgkJKwAdAJkZAA==.',
Im='Imran:BAACLgAFFH8ZAAIJAAQJzQvmCQDJAAAJAAQJzQvmCQDJAAAuAAQKf2cAAwkACQlUHRsEALcCAAkACQlUHRsEALcCAAEABwmhBKXPAOoAAAAA.',
In='Inkdawarlock:BAAALgAECgEJAQAAAA==.',
['Iå']='Iåomai:BAAALgADCgMJAwAAAA==.',
Ja='Jabronee:BAABLgAECn8cAAIQAAYJUBt9NABvAQAQAAYJUBt9NABvAQAAAA==.',
Je='Jerikoh:BAAALgAECgEJAwAAAA==.Jershdahunta:BAAALgADCgkJDgABLgAECggJDQANAAAAAA==.Jether:BAAALgAECgUJEgAAAA==.',
Jk='Jkingoreborn:BAABLgAECn8gAAIJAAcJjyE4CQAxAgAJAAcJjyE4CQAxAgABLgAECggJIwAUAJQXAA==.',
Jo='Jodormi:BAAALgADCgkJCQABLgAECgkJHQAdAM0YAA==.Jodrin:BAAALgADCgEJAQAAAA==.Jojobaggins:BAABLgAECn8aAAQeAAcJPhq2DABVAQAEAAUJeRdkMQB8AQAeAAcJFhe2DABVAQAfAAQJLBpTBwAwAQAAAA==.Jopine:BAAALgAECgEJAQABLgAECgkJHQAdAM0YAA==.',
Ka='Kaadriluna:BAAALgADCgUJBQAAAA==.Kaena:BAAALgADCgYJBgAAAA==.Kaey:BAAALgAECgQJBAAAAA==.Kaname:BAAALgAECgYJEAAAAA==.Katalyst:BAAALgAECgIJAgAAAA==.',
Ke='Keiri:BAAALgADCgMJAwAAAA==.Keyholes:BAABLgAFFH8TAAIgAAYJaBirDwBoAQAgAAYJaBirDwBoAQABLgAFFAcJHAAPALEdAA==.Keyohs:BAAALgAECgUJBQABLgAFFAcJHAAPALEdAA==.',
Kh='Khe:BAAALgAECgcJCQABLgAECgkJOwALAAQdAA==.',
Ki='Kittybear:BAAALgAFFAEJAQABLgAFFAgJIwAPANwiAA==.',
Kk='Kkoda:BAAALgAECgYJDQAAAA==.',
Ko='Koal:BAABLgAECn8hAAIUAAgJuhjXQQDRAQAUAAgJuhjXQQDRAQAAAA==.Kodabear:BAAALgADCgcJBwAAAA==.',
Kp='Kpop:BAAALgADCgcJBwABLgAFFAkJNAAUAKclAA==.',
Kr='Kreen:BAAALgADCgcJBwAAAA==.Krom:BAABLgAECn8VAAMBAAcJsARX7wC+AAABAAcJsARX7wC+AAAJAAEJGABWUAADAAABLgAECggJKwALAD4QAA==.Kronos:BAAALgAECgcJBwABLgAECgYJCgANAAAAAA==.',
Ku='Kuroneko:BAAALgAECggJEAAAAA==.Kushage:BAAALgAECgEJAQAAAA==.',
Ky='Kyomu:BAAALgADCgMJAwAAAA==.',
La='Lara:BAABLgAECn8iAAMUAAgJhg9zYAB5AQAUAAgJhg9zYAB5AQADAAYJ/goTSwAmAQAAAA==.Lavaa:BAAALgADCgEJAQAAAA==.',
Le='Leibniz:BAAALgADCgMJAwAAAA==.Lesgoth:BAAALgAECgcJCQAAAA==.Lettussy:BAABLgAFFH8QAAQEAAQJFiDSEgBhAQAEAAQJFiDSEgBhAQAfAAQJCgeOBwD6AAAeAAEJRwrlEQBCAAABLgAFFAgJHQAFAPQXAA==.Ley:BAAALgAECgUJBgAAAA==.Leya:BAAALgAECgIJAgAAAA==.',
Li='Lightsbelow:BAAALgADCgYJCAAAAA==.Lix:BAABLgAECn8lAAICAAkJrBFOLgDiAQACAAkJrBFOLgDiAQAAAA==.',
Lo='Loliruri:BAAALgAECgYJDgAAAA==.Loreleì:BAAALgADCgMJAwAAAA==.Louis:BAAALgAECgEJAQAAAA==.',
Lu='Luffymd:BAAALgAECgQJBwAAAA==.Luminyssa:BAAALgAECgYJBwAAAA==.',
['Lú']='Lúthien:BAABLgAECn80AAIXAAkJ5iL3BgAiAwAXAAkJ5iL3BgAiAwAAAA==.',
Ma='Madoka:BAAALgAECgYJDwAAAA==.Makari:BAAALgADCgMJAwAAAA==.Matrix:BAAALgAECgcJDQAAAA==.Mavenn:BAAALgAECgEJAQAAAA==.Maxchungus:BAABLgAECn81AAMMAAkJ8yEzGQCoAgAMAAkJ8yEzGQCoAgAgAAYJPQ8WJAAgAQAAAA==.',
Me='Meatsuit:BAAALgAECgIJAgAAAA==.Meigetsuki:BAAALgADCgQJBAABLgAECgIJAwANAAAAAA==.Meloo:BAABLgAECn85AAMTAAkJNBvpCQB7AgATAAkJNBvpCQB7AgAhAAYJ2AaZtQCvAAAAAA==.Meteor:BAAALgADCgUJBQAAAA==.',
Mi='Mightguy:BAAALgAECgEJAQAAAA==.Mikehawncho:BAAALgAECgQJBwABLgAECgcJHgAMAFUbAA==.Mizu:BAAALgAECgMJAwAAAA==.',
Mo='Moknahddon:BAAALgADCgQJBAAAAA==.Moment:BAABLgAECn8hAAIHAAkJ0xmHAwBPAgAHAAkJ0xmHAwBPAgAAAA==.Morthrisia:BAAALgADCgUJBQABLgAECgEJAQANAAAAAA==.',
Mu='Muna:BAAALgAECgEJAQAAAA==.Murrmau:BAABLgAECn8aAAIUAAYJ2wlvlAAJAQAUAAYJ2wlvlAAJAQAAAA==.Muufarmer:BAAALgADCggJCAAAAA==.',
My='Mydude:BAAALgAECgcJDAAAAA==.',
Na='Naerys:BAAALgAECggJDQAAAA==.Nalguilidan:BAAALgADCgYJBgAAAA==.Natedk:BAAALgAECgIJAgAAAA==.Natmau:BAAALgADCgQJBAAAAA==.Naughtyelf:BAAALgAECgYJCAAAAA==.',
Ne='Nemene:BAAALgADCgEJAQAAAA==.Neyt:BAABLgAECn8pAAMhAAkJKBvRHgBRAgAhAAkJKBvRHgBRAgATAAEJiRURcAA1AAAAAA==.',
Ni='Niddalee:BAAALgAECgcJEQAAAA==.Nioh:BAAALgAECgYJDwAAAA==.Niohscuck:BAAALgADCgEJAQAAAA==.Nitesrider:BAAALgAECgQJCAAAAA==.',
No='Nora:BAACLgAFFH8tAAIBAAkJTSUeAAB2AwABAAkJTSUeAAB2AwAuAAQKfz8AAwEACQnEJlgBAIEDAAEACQnEJlgBAIEDAAgAAwktFulZAMIAAAAA.Nori:BAAALgADCgkJDgABLgAFFAgJLAAFAFIkAA==.Noshikoshi:BAAALgAECgIJAwAAAA==.Nostrodom:BAAALgAECgUJCwAAAA==.',
Nu='Nubbs:BAABLgAECn8eAAIZAAkJdR6QBwDGAgAZAAkJdR6QBwDGAgAAAA==.',
Ny='Nyissa:BAAALgAECgMJAwAAAA==.Nyonà:BAAALgADCgQJBAAAAA==.',
Oc='Octas:BAAALgAECgMJAwABLgAFFAUJGQAGAKcRAA==.',
Of='Offen:BAAALgAECgIJAgAAAA==.',
Og='Ogmonkas:BAAALgAECgEJAgAAAA==.',
On='On:BAAALgAECgUJCAAAAA==.Onlyinusa:BAABLgAECn8kAAIRAAkJeyI8AgAUAwARAAkJeyI8AgAUAwAAAA==.Onyxnate:BAAALgADCgkJJQAAAA==.',
Op='Opalith:BAAALgAECgIJAgABLgAECgMJAwANAAAAAA==.Opel:BAAALgAECgIJAgABLgAFFAUJHQAZADoSAA==.Opi:BAAALgADCgcJBwAAAA==.',
Or='Orbyn:BAAALgADCgEJAQAAAA==.Ortah:BAAALgADCgEJAQAAAA==.',
Ox='Oxyrania:BAAALgADCgEJAQAAAA==.',
Pa='Paladigga:BAAALgAECgkJDQAAAA==.Pandalorenzo:BAAALgADCgEJAQAAAA==.',
Pf='Pfhor:BAAALgAECgYJBgAAAA==.',
Ph='Phillyshiho:BAAALgAECgcJEwABLgAECgkJIQAiAPEQAA==.',
Pi='Pinkdefender:BAAALgAECggJEAABLgAFFAQJEQAMAMcYAA==.',
Po='Pokeumon:BAAALgADCgEJAQAAAA==.Poor:BAAALgAECgMJBwAAAA==.Poosistrox:BAACLgAFFH8RAAQMAAQJxxiTgADzAAAMAAMJlB2TgADzAAAjAAMJhA7LEwDNAAAgAAEJkAUPOQA2AAAuAAQKfyEAAwwACAkoHrUvAHkCAAwACAkoHrUvAHkCACAABAlvBxw3AIkAAAAA.Pornelius:BAAALgAECgcJCwABLgAECgkJMgAOAG0eAA==.Potumkin:BAAALgADCgQJBgAAAA==.',
Pt='Ptheve:BAACLgAFFH8xAAMTAAkJHCYqAAAsAwATAAgJpCYqAAAsAwAhAAgJACHbAACgAgAuAAQKfykAAyEACQmvJXcBAMgDACEACQmoJXcBAMgDABMABwmNJKoUACsCAAAA.',
Pu='Pump:BAAALgADCgEJAQAAAA==.Putang:BAAALgAECgEJAQAAAA==.',
['På']='Pållås:BAAALgADCgMJAwAAAA==.',
Qn='Qnyx:BAABLgAECn8nAAIiAAcJfRJYMABVAQAiAAcJfRJYMABVAQAAAA==.',
Ra='Raelindra:BAABLgAECn8dAAIdAAkJzRgNBQAWAgAdAAkJzRgNBQAWAgAAAA==.Rayalla:BAAALgADCgUJBQAAAA==.Raygor:BAAALgAECggJDwAAAA==.',
Re='Rebuke:BAABLgAECn8gAAIBAAgJjBk2OAAWAgABAAgJjBk2OAAWAgAAAA==.Renewal:BAAALgAECgUJBQAAAA==.',
Ro='Rookorblood:BAABLgAECn8bAAIQAAYJWwY+XgDPAAAQAAYJWwY+XgDPAAAAAA==.Rosewalker:BAACLgAFFH8bAAIGAAUJNiWCDACvAQAGAAUJNiWCDACvAQAuAAQKfz0AAwYACQk9JRECAD4DAAYACQk9JRECAD4DABkACQnrHpQGANoCAAAA.Rosewall:BAAALgAECgQJBQABLgAFFAUJGwAGADYlAA==.Rottgut:BAAALgAECgYJDQAAAA==.',
Ru='Rustyjux:BAAALgAECgEJAQAAAA==.',
Ry='Ryachun:BAAALgADCgMJAwAAAA==.Rykò:BAABLgAECn9EAAQUAAkJYiSQAwBRAwAUAAkJYiSQAwBRAwAkAAYJGgdcOQDoAAADAAUJ7BA3XgDIAAAAAA==.',
Sa='Salchaos:BAABLgAECn8eAAQOAAgJCRZ5DwCkAQAQAAcJiRZPMgDjAQAOAAcJ2xR5DwCkAQAPAAQJMxAiLgDRAAAAAA==.Samsmith:BAAALgAECgYJBgAAAA==.Sanel:BAAALgADCgYJBgAAAA==.Sassy:BAAALgAECgQJAgABLgAFFAgJKQASAI4bAA==.Savork:BAABLgAECn8jAAMUAAgJlBctNAABAgAUAAgJlBctNAABAgADAAYJog6wRgA6AQAAAA==.Sayafaed:BAABLgAECn8mAAIhAAkJfA0wTgCPAQAhAAkJfA0wTgCPAQAAAA==.Sayamese:BAAALgAECggJEwAAAA==.',
Sc='Scatback:BAABLgAECn86AAQVAAkJeRg2FQAkAgAVAAkJPBI2FQAkAgAWAAgJQxljGAD8AQAiAAMJvQlPfAA2AAAAAA==.Schwiddylock:BAAALgAECgUJCgAAAA==.Scud:BAABLgAECn8fAAIiAAkJMw1OKwByAQAiAAkJMw1OKwByAQAAAA==.Scáthach:BAAALgADCgYJCAAAAA==.',
Se='Seint:BAAALgADCgYJBgAAAA==.Senuna:BAAALgADCgIJAQAAAA==.Seraphae:BAAALgADCgMJAwAAAA==.Seraphnite:BAAALgAECgQJBAAAAA==.',
Sh='Shadowdaddy:BAABLgAECn8hAAIiAAkJ8RD7HgDFAQAiAAkJ8RD7HgDFAQAAAA==.Shadyshifts:BAAALgADCgYJBgABLgAFFAQJEQAMAMcYAA==.Shadôwhunt:BAABLgAECn8fAAIMAAgJchWAXQDaAQAMAAgJchWAXQDaAQAAAA==.Shenlon:BAACLgAFFH8rAAMHAAYJQyEfAQChAQAYAAYJLx2zEQDJAQAHAAUJISYfAQChAQAuAAQKfy4ABAcACQm+JJMAAI0DAAcACQmPIZMAAI0DABIABQlvHf4SAJEBABgABAmKI9AlAI8BAAAA.Shilor:BAABLgAECn8lAAIVAAgJDRgYGAAEAgAVAAgJDRgYGAAEAgAAAA==.Shogun:BAAALgAECggJEgAAAA==.Shulamite:BAAALgADCgYJBgAAAA==.Shuye:BAAALgAECgQJBQAAAA==.',
Si='Sicarii:BAAALgAECgEJAQABLgAECgcJDgANAAAAAA==.Sicarrious:BAAALgAECgcJDgAAAA==.Sinaliska:BAAALgADCgQJBAAAAA==.Sinistr:BAABLgAECn8WAAMLAAcJChyjJwDyAQALAAcJChyjJwDyAQAKAAQJIAUfIgCyAAAAAA==.',
Sk='Skyarc:BAAALgAECgUJBwAAAA==.Skyrun:BAAALgAECgMJAwABLgAECgUJBwANAAAAAA==.',
Sm='Smiffbrew:BAAALgADCgMJBAAAAA==.Smiffury:BAAALgAECgYJCQAAAA==.',
Sn='Snicks:BAAALgAECgIJAgAAAA==.',
Sq='Squishyshoe:BAAALgAECgEJAQAAAA==.',
St='Stinkythebum:BAABLgAECn8ZAAIZAAgJ5RnrEgAcAgAZAAgJ5RnrEgAcAgAAAA==.Stoneymalone:BAAALgAECgIJAwAAAA==.Stélle:BAABLgAECn8kAAIDAAkJsw1XDACSAQADAAkJsw1XDACSAQAAAA==.',
Su='Supdude:BAABLgAECn84AAMEAAkJ/iJqAwAIAwAEAAkJ/iJqAwAIAwAfAAEJaRz2DQA6AAAAAA==.',
Ta='Tairnbys:BAAALgAECgMJAwAAAA==.Tanthe:BAAALgADCgMJAwAAAA==.Tazbirkloa:BAAALgADCgIJAgAAAA==.',
Te='Tebzerk:BAAALgAECgcJDgAAAA==.Tekk:BAAALgAECgcJCgAAAA==.Temptress:BAAALgADCgIJAwAAAA==.',
Th='Thatssotank:BAAALgAECgYJDQABLgAFFAUJCwAFAAgRAA==.Thorokk:BAAALgAECgMJAwAAAA==.Thynrage:BAAALgAECgUJBgAAAA==.',
Ti='Tictac:BAAALgADCgUJBQAAAA==.Tigas:BAACLgAFFH8LAAIQAAMJkCGQIQAeAQAQAAMJkCGQIQAeAQAuAAQKfy4AAxAACAnQJNAJAL4CABAACAnQJNAJAL4CAA4AAQljFtRmAEQAAAAA.',
To='Tooth:BAAALgAECgEJAgAAAA==.Tor:BAAALgADCgMJAwABLgAECgcJEQANAAAAAA==.',
Tr='Trashdragon:BAABLgAECn8xAAMHAAkJWyJRAQDlAgAHAAkJPCFRAQDlAgAYAAgJNx6yDgCKAgAAAA==.Trauma:BAAALgAECgMJAwAAAA==.',
Ty='Tygrans:BAAALgADCgUJBQAAAA==.Typhoonz:BAAALgADCgEJAQAAAA==.',
['Tö']='Töby:BAAALgAECgcJEQAAAA==.',
Ul='Ulric:BAAALgAECgQJBQAAAA==.',
Um='Umgunk:BAAALgAECgQJBQAAAA==.Ummabunbun:BAAALgADCgMJAwAAAA==.',
Un='Unorthodox:BAAALgAECgUJCAAAAA==.',
Us='Usagi:BAABLgAECn8dAAIBAAcJ9htgUwDFAQABAAcJ9htgUwDFAQAAAA==.',
Ut='Utsuro:BAAALgAECgMJAwABLgAECggJDAANAAAAAA==.',
Va='Vannacutt:BAABLgAECn8UAAIQAAgJkgxuOABdAQAQAAgJkgxuOABdAQABLgAECggJDAANAAAAAA==.Vaz:BAAALgAECgQJBAAAAA==.',
Ve='Velzevul:BAAALgADCgYJBgAAAA==.Vermouth:BAAALgAECgUJCAAAAA==.',
Vi='Vincentx:BAAALgADCgUJCwAAAA==.',
Vv='Vvinter:BAAALgAECgEJAQAAAA==.',
Vy='Vynii:BAACLgAFFH8IAAIhAAQJ3gXwVQDZAAAhAAQJ3gXwVQDZAAAuAAQKfzMAAyEACQlnFc06ANABACEACQlbEs06ANABABMABgmCGDwmAI4BAAAA.',
Wa='Wallofstars:BAAALgAECgQJBAAAAA==.Wardamage:BAAALgADCgYJBgAAAA==.Wasabi:BAAALgAECggJEAAAAA==.',
We='Weedcenters:BAAALgAECgEJAQAAAA==.Weenygripper:BAABLgAECn8XAAIMAAcJnxHuhgBNAQAMAAcJnxHuhgBNAQABLgAFFAUJDgAFAHYiAA==.',
Wf='Wfaps:BAAALgAECgQJCAAAAA==.',
Wo='Wonon:BAAALgAFFAEJAQAAAA==.Wontonboy:BAAALgADCgEJAQAAAA==.',
Wu='Wuufi:BAAALgADCgYJBgAAAA==.',
Xa='Xaam:BAAALgAECgUJCAAAAA==.Xaida:BAACLgAFFH8eAAIXAAgJmxd+BgCAAgAXAAgJmxd+BgCAAgAuAAQKfxYAAwYACQl7DKwjAIYBAAYACQl7DKwjAIYBABcAAQmUH+mOAFwAAAEuAAUUCQkyABIAeBgA.',
Xe='Xecutioner:BAAALgAECgYJDwAAAA==.',
Xi='Xilantaeki:BAAALgAECgQJBAAAAA==.',
Yq='Yqwegvbwefhu:BAAALgAECgMJBwAAAA==.',
Za='Zangyaku:BAEBLgAECn8iAAIgAAkJrCVxAQBKAwAgAAkJrCVxAQBKAwAAAA==.Zanmetsu:BAEBLgAECn8dAAMEAAcJrRyNGABDAgAEAAcJrRyNGABDAgAeAAEJjgzsHgA4AAABLgAECgkJIgAgAKwlAA==.Zarlock:BAAALgADCgYJBgAAAA==.',
Ze='Zeji:BAABLgAECn87AAMLAAkJBB0hDgDYAgALAAkJBB0hDgDYAgAaAAQJmRoXRQAPAQAAAA==.Zerocool:BAABLgAECn8fAAIlAAkJBRMrQgAGAgAlAAkJBRMrQgAGAgAAAA==.',
Zu='Zuggernaut:BAAALgADCgYJBgAAAA==.Zugquavious:BAAALgAECgcJDgABLgAECggJGQAKANYaAA==.Zugzug:BAAALgAECgMJAwAAAA==.',
Zy='Zyggy:BAABLgAECn8UAAIbAAgJJxGpKgBxAQAbAAgJJxGpKgBxAQAAAA==.',
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
