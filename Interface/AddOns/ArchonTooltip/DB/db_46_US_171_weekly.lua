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
local provider = {region='US',realm='Onyxia',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abrams:BAABLgAECn8bAAIBAAgJ+hlKTwDCAQABAAgJ+hlKTwDCAQAAAA==.',
Ad='Addý:BAABLgAECn8XAAICAAkJgBcTJQARAgACAAkJgBcTJQARAgAAAA==.Advanced:BAAALgADCgQJAQAAAA==.',
Ah='Ahimsa:BAABLgAECn8+AAIDAAkJoiIUAQAbAwADAAkJoiIUAQAbAwAAAA==.',
Al='Alisonchains:BAABLgAECn8sAAIEAAgJPCDpCACBAgAEAAgJPCDpCACBAgAAAA==.Alkyri:BAAALgAECgEJAQAAAA==.Almamun:BAAALgAECgEJAQAAAA==.Alternate:BAABLgAECn87AAIFAAkJBh6CFwC3AgAFAAkJBh6CFwC3AgAAAA==.',
Am='Amigo:BAAALgADCgEJAQAAAA==.Amillerbrew:BAABLgAECn8aAAIGAAgJTxaYJQDXAQAGAAgJTxaYJQDXAQAAAA==.',
An='Anayanci:BAAALgAECgQJDAAAAA==.Anesh:BAAALgAECgMJBQAAAA==.Anjuna:BAAALgAECgYJDwAAAA==.Anshee:BAAALgAECgIJAwAAAA==.Anubrin:BAAALgADCgUJBwAAAA==.',
Ap='Aphian:BAAALgAECgIJAgAAAA==.',
As='Ashenclaw:BAABLgAECn81AAIHAAgJIRsYBAArAgAHAAgJIRsYBAArAgAAAA==.',
Au='Auzatryx:BAAALgAECgYJDwAAAA==.',
Ba='Bamboom:BAABLgAECn8eAAQIAAcJsBatJADMAQAIAAcJsBatJADMAQABAAEJFgINowEXAAAJAAEJRAHATwARAAAAAA==.Bapbap:BAAALgADCgYJBgAAAA==.',
Be='Beefstick:BAAALgAECgMJAgAAAA==.Belanik:BAAALgAECgEJBQAAAA==.Beleth:BAAALgADCgYJBgAAAA==.',
Bi='Bigblktotem:BAABLgAECn8WAAMKAAYJlAzwFwBDAQAKAAYJlAzwFwBDAQALAAMJHQSWpQBbAAABLgAFFAQJEQAMAMcYAA==.Biggrnmonstr:BAAALgAFFAEJAQABLgAFFAQJEQAMAMcYAA==.Bigheffin:BAAALgAECgIJAgABLgAECggJCQANAAAAAA==.Bigrabit:BAAALgAECgMJAwAAAA==.Bigslammin:BAAALgAECgQJBQAAAA==.Bigxthezug:BAAALgAECgQJBQABLgAECggJCQANAAAAAA==.Biirf:BAAALgAECgUJBgAAAA==.',
Bl='Blaine:BAAALgAECgMJBgAAAA==.Blãze:BAAALgADCgIJAgAAAA==.',
Bo='Bogdan:BAAALgADCgEJAQAAAA==.Bomi:BAAALgAECgQJCQAAAA==.Boogiebm:BAAALgAECgcJCwAAAA==.Borgon:BAAALgAECgEJAgAAAA==.Bowevil:BAAALgADCgMJAwAAAA==.Boypartz:BAABLgAECn8yAAMOAAkJbR6JBAC5AgAOAAkJbR6JBAC5AgAPAAEJKwmNTQAiAAAAAA==.',
Br='Brayuh:BAAALgAECgEJAQAAAA==.Breakfast:BAAALgAECggJCQAAAA==.',
Bu='Bulbasaurus:BAACLgAFFH8VAAIQAAQJQyUcBwC1AQAQAAQJQyUcBwC1AQAuAAQKfx8AAhAACQmjInoHADEDABAACQmjInoHADEDAAAA.Bulloney:BAAALgADCgIJAgAAAA==.Bunana:BAAALgADCgIJAgAAAA==.Bus:BAAALgAFFAMJBAABLgAFFAkJHAARAP8jAA==.',
Ca='Cabooze:BAAALgAECgYJBwAAAA==.Cacho:BAAALgAECgQJCAAAAA==.Cañonazo:BAAALgAECgEJAQAAAA==.',
Ce='Celeres:BAABLgAECn8eAAISAAgJeBgiEQAqAgASAAgJeBgiEQAqAgAAAA==.Celys:BAAALgAECgUJBgAAAA==.Cerealkillah:BAAALgAECgEJAQAAAA==.',
Ch='Chantilly:BAAALgAECgYJDAAAAA==.Chartreuse:BAAALgADCgMJBAABLgAECgUJCAANAAAAAA==.Chaw:BAAALgAECgEJAQAAAA==.Cheesecurds:BAAALgADCgcJBwAAAA==.Cheesied:BAAALgADCgQJAwAAAA==.Chios:BAAALgAECgUJBQABLgAFFAcJGQAPAEobAA==.',
Cl='Cleetiscat:BAAALgAECgYJBgAAAA==.',
Co='Cowabunga:BAAALgADCgEJAQAAAA==.',
Cr='Crow:BAAALgAFFAcJFQAAAQ==.Cryoblade:BAAALgADCgcJDAAAAA==.',
Cu='Cuttanee:BAAALgAECggJDAAAAA==.',
Cy='Cyril:BAAALgADCgkJFwAAAA==.',
Da='Daevon:BAAALgAECgQJEAAAAA==.Daron:BAAALgAECgcJDgABLgAECgcJEQANAAAAAA==.Darrowreaper:BAABLgAECn8eAAIMAAgJzQ2FagB9AQAMAAgJzQ2FagB9AQAAAA==.',
De='Deadcell:BAAALgAECgYJBwAAAA==.Deatheria:BAAALgADCgMJAwAAAA==.Deathstar:BAAALgAECgUJBQAAAA==.Denarrage:BAACLgAFFH8QAAITAAUJUAmDEAD7AAATAAUJUAmDEAD7AAAuAAQKfy4AAhMACQnuFIgSAOYBABMACQnuFIgSAOYBAAAA.Denawage:BAAALgAECggJCAAAAA==.',
Di='Dirtytotem:BAABLgAECn8YAAIKAAgJIBorCAAqAgAKAAgJIBorCAAqAgAAAA==.Discordia:BAAALgAECggJDQAAAA==.Disprop:BAAALgAECgEJAQAAAA==.Dizyizy:BAAALgAECgUJBwAAAA==.',
Do='Doingmost:BAAALgAECgEJAgAAAA==.Dontnerfspls:BAAALgAECgMJBQABLgAFFAQJEQAMAMcYAA==.Doomby:BAAALgAECgYJDAABLgAECggJKwATAMwYAA==.',
Dr='Drakesh:BAAALgADCgEJAQAAAA==.Drakussy:BAAALgAECggJDgABLgAECggJKwATAMwYAA==.Drudekay:BAAALgAECgEJAQAAAA==.',
Du='Dullslinkie:BAAALgADCgEJAQAAAA==.',
El='Eldarborn:BAAALgAECgUJBQAAAA==.Eldruida:BAAALgAECgIJAgAAAA==.Eleannar:BAAALgAECgEJAQAAAA==.Elficpaladin:BAAALgAECgYJCQAAAA==.Elixxi:BAAALgAECgUJCgAAAA==.Elladin:BAAALgADCgcJBwAAAA==.Ellipsi:BAAALgAECgcJDQAAAA==.Ellipsoro:BAACLgAFFH8JAAIMAAMJBB5LdQD0AAAMAAMJBB5LdQD0AAAuAAQKfy4AAgwACQl4JWwHACsDAAwACQl4JWwHACsDAAAA.Eltrol:BAACLgAFFH8MAAIUAAQJawk/SgDuAAAUAAQJawk/SgDuAAAuAAQKfxkAAhQACQmfFakhAEgCABQACQmfFakhAEgCAAAA.Eluriana:BAAALgAECgYJCAABLgAFFAUJFwAGAKcRAA==.',
Er='Erale:BAAALgADCgYJDAAAAA==.Eredarn:BAAALgADCgEJAQAAAA==.Erienor:BAAALgADCgkJDAAAAA==.',
Ev='Evldrprkchop:BAAALgADCgIJAgAAAA==.',
Ex='Executiepie:BAACLgAFFH8ZAAIPAAcJShuuAgAlAgAPAAcJShuuAgAlAgAuAAQKfyIAAg8ACQmiILkCADsDAA8ACQmiILkCADsDAAAA.Exodia:BAAALgAECgYJBgAAAA==.',
Fa='Faeris:BAACLgAFFH8NAAMVAAUJShv/EgCtAQAVAAUJShv/EgCtAQAWAAEJMQ2qEgBPAAAuAAQKfyIAAxYACQkkItMBAFkDABYACQkkItMBAFkDABUAAgnfGodFAI0AAAAA.Faolain:BAABLgAECn8kAAICAAgJQBEVQgB2AQACAAgJQBEVQgB2AQAAAA==.Fatalis:BAACLgAFFH8cAAIUAAYJ8Qo1JwBJAQAUAAYJ8Qo1JwBJAQAuAAQKfywAAxQACQkLHHgVAJECABQACQkLHHgVAJECAAMACAlcBLJRAAYBAAAA.',
Fe='Fetch:BAAALgAECgkJBgAAAA==.',
Fi='Fiddlestix:BAAALgAECgUJCgAAAA==.Fims:BAAALgAECgYJCgAAAA==.Finarfin:BAAALgADCgkJCQAAAA==.Fireballcat:BAAALgAECgIJAgAAAA==.Fizaw:BAABLgAECn89AAIXAAkJSwiSQwAqAQAXAAkJSwiSQwAqAQAAAA==.',
Fl='Floydbussy:BAABLgAFFH8KAAIYAAUJjAzCLQDxAAAYAAUJjAzCLQDxAAAAAA==.',
Fr='Freeng:BAAALgADCgYJBgAAAA==.Freeze:BAAALgAECgEJAQAAAA==.Freyya:BAAALgAECgIJAwAAAA==.Frøzen:BAAALgAECgQJAgAAAA==.',
Fu='Fuzzydots:BAAALgAECgMJBgAAAA==.',
['Fë']='Fëanør:BAABLgAECn8XAAIBAAgJ7RO0ZgCzAQABAAgJ7RO0ZgCzAQAAAA==.',
Ga='Galana:BAAALgADCgEJAQAAAA==.Galnir:BAAALgAECgMJAwAAAA==.Gatorbait:BAAALgAECgQJBAAAAA==.Gaurr:BAAALgAECgMJBgAAAA==.Gazzcool:BAAALgAECgkJBwAAAA==.',
Ge='Geneviere:BAAALgAECgQJBQAAAA==.Gex:BAAALgAECggJDQAAAA==.',
Gh='Ghostzen:BAACLgAFFH8IAAIZAAMJXBq0GwDaAAAZAAMJXBq0GwDaAAAuAAQKfx0AAhkACQlUJQgBALsDABkACQlUJQgBALsDAAAA.',
Gi='Gislain:BAABLgAECn8eAAMLAAgJUBHROgCWAQALAAgJUBHROgCWAQAaAAYJ3gwETQDlAAAAAA==.',
Go='Goldeye:BAAALgADCgMJAwAAAA==.Gooichi:BAAALgAECgEJAgAAAA==.Gothmogsbane:BAABLgAECn8WAAMCAAgJdBHwUQA0AQACAAYJzRHwUQA0AQAbAAgJKwTEUgDcAAAAAA==.',
Gr='Greaves:BAAALgAECgQJBAABLgAFFAUJHAAcAEkmAA==.Greyspirit:BAABLgAECn82AAIRAAkJeiF8AgD9AgARAAkJeiF8AgD9AgAAAA==.Grez:BAAALgAECgQJBgAAAA==.Grubnub:BAAALgADCgEJAQABLgAECgkJOwALAAQdAA==.',
Gu='Gumpy:BAAALgAECggJDAAAAA==.',
Ha='Halcoldrek:BAAALgAECgMJAwAAAA==.Hamburguesa:BAAALgAECgMJBAAAAA==.Hanta:BAAALgADCgIJAwAAAA==.Harkiel:BAAALgAECgUJBwAAAA==.Haumea:BAAALgAECgMJAwAAAA==.',
Hb='Hbc:BAABLgAFFH8GAAIRAAQJDA/jDgDkAAARAAQJDA/jDgDkAAABLgAFFAcJGQAPAEobAA==.',
He='Heyz:BAABLgAECn8jAAMVAAgJKRywDgBkAgAVAAgJKRywDgBkAgAWAAEJkwCligAhAAAAAA==.',
Hi='Hibernate:BAAALgADCgIJAgAAAA==.Himbo:BAAALgAECggJEAAAAA==.Hipocrit:BAAALgAECgcJCQAAAA==.',
Ho='Hog:BAAALgAECgYJBwAAAA==.Holypoopp:BAACLgAFFH8GAAIIAAQJDxS1HQAYAQAIAAQJDxS1HQAYAQAuAAQKf0MABAEACQm1HyoSAMICAAEACQm1HyoSAMICAAkACQmvDN8VAFsBAAgABgkpFHpKAE4BAAAA.Hondalorian:BAABLgAECn89AAIUAAkJ7BZSIQBKAgAUAAkJ7BZSIQBKAgAAAA==.Honkmydemon:BAAALgADCgMJAwAAAA==.Honkmyscars:BAAALgAECgEJAQAAAA==.Hordranir:BAAALgADCgIJAgAAAA==.',
Hu='Hulksgrnsack:BAAALgAECgYJBgAAAA==.',
['Hë']='Hëxy:BAAALgADCgYJBgAAAA==.',
Il='Illidaldin:BAAALgADCgcJBwABLgAECgkJKwAdAJkZAA==.',
Im='Imran:BAACLgAFFH8SAAIJAAMJlgztCwCdAAAJAAMJlgztCwCdAAAuAAQKf04AAwkACQkuFqgLAPMBAAkACQkuFqgLAPMBAAEABwmhBKXPAOoAAAAA.',
In='Inkdawarlock:BAAALgAECgEJAQAAAA==.',
['Iå']='Iåomai:BAAALgADCgMJAwAAAA==.',
Ja='Jabronee:BAABLgAECn8cAAIQAAYJUBu2MQBwAQAQAAYJUBu2MQBwAQAAAA==.',
Je='Jerikoh:BAAALgAECgEJAwAAAA==.Jether:BAAALgAECgUJEgAAAA==.',
Jk='Jkingoreborn:BAABLgAECn8gAAIJAAcJjyF0CAA0AgAJAAcJjyF0CAA0AgABLgAECggJIwAUAJQXAA==.',
Jo='Jodormi:BAAALgADCgkJCQABLgAECgkJHQAdAM0YAA==.Jodrin:BAAALgADCgEJAQAAAA==.Jojobaggins:BAABLgAECn8aAAQeAAcJPhr9CwBcAQAEAAUJeRdkMQB8AQAeAAcJFhf9CwBcAQAfAAQJLBpTBwAwAQAAAA==.Jopine:BAAALgAECgEJAQABLgAECgkJHQAdAM0YAA==.',
Ka='Kaadriluna:BAAALgADCgMJBAAAAA==.Kaena:BAAALgADCgYJBgAAAA==.Kaey:BAAALgAECgQJBAAAAA==.Kaname:BAAALgAECgYJEAAAAA==.Katalyst:BAAALgAECgIJAgAAAA==.',
Ke='Keiri:BAAALgADCgMJAwAAAA==.Keyholes:BAABLgAFFH8RAAIgAAYJaBgADAB8AQAgAAYJaBgADAB8AQABLgAFFAcJGQAPAEobAA==.Keyohs:BAAALgAECgUJBQABLgAFFAcJGQAPAEobAA==.',
Kh='Khe:BAAALgAECgYJBwABLgAECgkJOwALAAQdAA==.',
Ki='Kittybear:BAAALgAFFAEJAQABLgAFFAgJIwAPANwiAA==.',
Kk='Kkoda:BAAALgAECgYJCgAAAA==.',
Ko='Koal:BAABLgAECn8hAAIUAAgJuhh4PADWAQAUAAgJuhh4PADWAQAAAA==.Kodabear:BAAALgADCgcJBwAAAA==.',
Kp='Kpop:BAAALgADCgcJBwABLgAFFAkJLQAUAKclAA==.',
Kr='Kreen:BAAALgADCgcJBwAAAA==.Krom:BAABLgAECn8VAAMBAAcJsAQ95QC5AAABAAcJsAQ95QC5AAAJAAEJGABWUAADAAABLgAECggJKwALAD4QAA==.Kronos:BAAALgAECgcJBwABLgAECgYJCgANAAAAAA==.',
Ku='Kuroneko:BAAALgAECgYJDAAAAA==.Kushage:BAAALgAECgEJAQAAAA==.',
Ky='Kyomu:BAAALgADCgMJAwAAAA==.',
La='Lara:BAABLgAECn8iAAMUAAgJhg8GWgB+AQAUAAgJhg8GWgB+AQADAAYJ/goTSwAmAQAAAA==.Lavaa:BAAALgADCgEJAQAAAA==.',
Le='Leibniz:BAAALgADCgMJAwAAAA==.Lesgoth:BAAALgAECgcJCQAAAA==.Lettussy:BAABLgAFFH8OAAQEAAQJgx/3EABfAQAEAAQJgx/3EABfAQAfAAQJCgeqBgD7AAAeAAEJRwqHEABCAAABLgAFFAcJGwAFAHYZAA==.Ley:BAAALgAECgUJBgAAAA==.Leya:BAAALgAECgIJAgAAAA==.',
Li='Lightsbelow:BAAALgADCgYJCAAAAA==.Lix:BAABLgAECn8fAAICAAcJRxKdRABqAQACAAcJRxKdRABqAQAAAA==.',
Lo='Loliruri:BAAALgAECgYJDgAAAA==.Loreleì:BAAALgADCgMJAwAAAA==.Louis:BAAALgAECgEJAQAAAA==.',
Lu='Luffymd:BAAALgAECgQJBwAAAA==.Luminyssa:BAAALgAECgYJBwAAAA==.',
['Lú']='Lúthien:BAABLgAECn80AAIXAAkJ5iI/BgAjAwAXAAkJ5iI/BgAjAwAAAA==.',
Ma='Madoka:BAAALgAECgYJDwAAAA==.Makari:BAAALgADCgMJAwAAAA==.Matrix:BAAALgAECgcJDQAAAA==.Mavenn:BAAALgAECgEJAQAAAA==.Maxchungus:BAABLgAECn81AAMMAAkJ8yG5FgCrAgAMAAkJ8yG5FgCrAgAgAAYJPQ8WJAAgAQAAAA==.',
Me='Meatsuit:BAAALgAECgIJAgAAAA==.Meloo:BAABLgAECn8rAAMTAAgJzBhiEQD1AQATAAgJzBhiEQD1AQAhAAYJ2AZVsACkAAAAAA==.Meteor:BAAALgADCgUJBQAAAA==.',
Mi='Mightguy:BAAALgAECgEJAQAAAA==.Mikehawncho:BAAALgAECgQJBwABLgAECgcJHgAMAFUbAA==.Mizu:BAAALgAECgMJAwAAAA==.',
Mo='Moknahddon:BAAALgADCgQJBAAAAA==.Moment:BAABLgAECn8hAAIHAAkJ0xlOAwBUAgAHAAkJ0xlOAwBUAgAAAA==.Morthrisia:BAAALgADCgUJBQABLgAECgEJAQANAAAAAA==.',
Mu='Muna:BAAALgAECgEJAQAAAA==.Murrmau:BAABLgAECn8aAAIUAAYJ2wnOiwAOAQAUAAYJ2wnOiwAOAQAAAA==.Muufarmer:BAAALgADCggJCAAAAA==.',
My='Mydude:BAAALgAECgUJBQAAAA==.',
Na='Naerys:BAAALgAECggJDQAAAA==.Nalguilidan:BAAALgADCgYJBgAAAA==.Natmau:BAAALgADCgQJBAAAAA==.Naughtyelf:BAAALgAECgYJBgAAAA==.',
Ne='Nemene:BAAALgADCgEJAQAAAA==.Neyt:BAABLgAECn8pAAMhAAkJKBtdHABWAgAhAAkJKBtdHABWAgATAAEJiRURcAA1AAAAAA==.',
Ni='Niddalee:BAAALgAECgcJEQAAAA==.Nioh:BAAALgAECgYJDwAAAA==.Niohscuck:BAAALgADCgEJAQAAAA==.Nitesrider:BAAALgAECgQJCAAAAA==.',
No='Nora:BAACLgAFFH8kAAIBAAgJ4CPOAAD1AgABAAgJ4CPOAAD1AgAuAAQKfzYAAwEACQlwJs4EAH8DAAEACQlwJs4EAH8DAAgAAwktFppWAMMAAAAA.Nori:BAAALgADCgkJDgABLgAFFAgJLAAFAFIkAA==.Noshikoshi:BAAALgAECgIJAwAAAA==.Nostrodom:BAAALgAECgQJBgAAAA==.',
Nu='Nubbs:BAABLgAECn8XAAIZAAkJwRsDEQAnAgAZAAkJwRsDEQAnAgAAAA==.',
Ny='Nyissa:BAAALgADCgYJCQAAAA==.Nyonà:BAAALgADCgQJBAAAAA==.',
Oc='Octas:BAAALgAECgMJAwABLgAFFAUJFwAGAKcRAA==.',
Of='Offen:BAAALgAECgIJAgAAAA==.',
Og='Ogmonkas:BAAALgAECgEJAgAAAA==.',
On='On:BAAALgAECgUJCAAAAA==.Onlyinusa:BAABLgAECn8bAAIRAAgJdCDyBQCGAgARAAgJdCDyBQCGAgAAAA==.Onyxnate:BAAALgADCgkJJQAAAA==.',
Op='Opalith:BAAALgAECgIJAgABLgAECgMJAwANAAAAAA==.Opel:BAAALgAECgIJAgABLgAFFAUJGQAZADoSAA==.Opi:BAAALgADCgcJBwAAAA==.',
Or='Orbyn:BAAALgADCgEJAQAAAA==.Ortah:BAAALgADCgEJAQAAAA==.',
Ox='Oxyrania:BAAALgADCgEJAQAAAA==.',
Pa='Paladigga:BAAALgAECgkJBgAAAA==.Pandalorenzo:BAAALgADCgEJAQAAAA==.',
Pf='Pfhor:BAAALgAECgYJBgAAAA==.',
Ph='Phillyshiho:BAAALgAECgcJEwABLgAECgkJIQAiAPEQAA==.',
Pi='Pinkdefender:BAAALgAECggJEAABLgAFFAQJEQAMAMcYAA==.',
Po='Pokeumon:BAAALgADCgEJAQAAAA==.Poor:BAAALgAECgMJBwAAAA==.Poosistrox:BAACLgAFFH8RAAQMAAQJxxjfcgD4AAAMAAMJlB3fcgD4AAAjAAMJhA5/EADXAAAgAAEJkAUvMwA4AAAuAAQKfyEAAwwACAkoHrUvAHkCAAwACAkoHrUvAHkCACAABAlvBxw3AIkAAAAA.Pornelius:BAAALgAECgcJCwABLgAECgkJMgAOAG0eAA==.Potumkin:BAAALgADCgQJBgAAAA==.',
Pt='Ptheve:BAACLgAFFH8oAAMTAAkJESYUAAAqAwATAAgJlCYUAAAqAwAhAAgJACHbAACgAgAuAAQKfykAAyEACQmvJXcBAMgDACEACQmoJXcBAMgDABMABwmNJKoUACsCAAAA.',
Pu='Pump:BAAALgADCgEJAQAAAA==.Putang:BAAALgAECgEJAQAAAA==.',
['På']='Pållås:BAAALgADCgMJAwAAAA==.',
Qn='Qnyx:BAABLgAECn8nAAIiAAcJfRLvLABPAQAiAAcJfRLvLABPAQAAAA==.',
Ra='Raelindra:BAABLgAECn8dAAIdAAkJzRiWBAAaAgAdAAkJzRiWBAAaAgAAAA==.Rakii:BAAALgADCgcJBwABLgAECggJDQANAAAAAA==.Rayalla:BAAALgADCgUJBQAAAA==.Raygor:BAAALgAECgYJDQAAAA==.',
Re='Rebuke:BAABLgAECn8bAAIBAAgJlBZpSwDMAQABAAgJlBZpSwDMAQAAAA==.Renewal:BAAALgAECgUJBQAAAA==.',
Ro='Rookorblood:BAABLgAECn8bAAIQAAYJWwa5WQDPAAAQAAYJWwa5WQDPAAAAAA==.Rosewalker:BAACLgAFFH8bAAIGAAUJNiVhCgC0AQAGAAUJNiVhCgC0AQAuAAQKfz0AAwYACQk9JdIBAEADAAYACQk9JdIBAEADABkACQnrHuAFAN8CAAAA.Rosewall:BAAALgAECgQJBQABLgAFFAUJGwAGADYlAA==.Rottgut:BAAALgAECgYJDQAAAA==.',
Ry='Ryachun:BAAALgADCgMJAwAAAA==.Rykò:BAABLgAECn9BAAQUAAkJYiT0AgBWAwAUAAkJYiT0AgBWAwAkAAYJGgcKNwDpAAADAAUJ7BA3XgDIAAAAAA==.',
Sa='Salchaos:BAABLgAECn8eAAQOAAgJCRZ5DwCkAQAQAAcJiRZPMgDjAQAOAAcJ2xR5DwCkAQAPAAQJMxAiLgDRAAAAAA==.Samsmith:BAAALgAECgYJBgAAAA==.Sanel:BAAALgADCgYJBgAAAA==.Savork:BAABLgAECn8jAAMUAAgJlBfSLwAGAgAUAAgJlBfSLwAGAgADAAYJog6FHQCuAAAAAA==.Sayafaed:BAABLgAECn8mAAIhAAkJfA1sSACVAQAhAAkJfA1sSACVAQAAAA==.Sayamese:BAAALgAECggJEwAAAA==.',
Sc='Scatback:BAABLgAECn86AAQVAAkJeRh5EwAlAgAVAAkJPBJ5EwAlAgAWAAgJQxmlFgAFAgAiAAMJvQnrcwA2AAAAAA==.Schwiddylock:BAAALgAECgUJCgAAAA==.Scud:BAABLgAECn8fAAIiAAkJMw1AKgBgAQAiAAkJMw1AKgBgAQAAAA==.Scáthach:BAAALgADCgYJCAAAAA==.',
Se='Seint:BAAALgADCgYJBgAAAA==.Senuna:BAAALgADCgEJAQAAAA==.Seraphae:BAAALgADCgMJAwAAAA==.Seraphnite:BAAALgAECgQJBAAAAA==.',
Sh='Shadowdaddy:BAABLgAECn8hAAIiAAkJ8RD/HQC2AQAiAAkJ8RD/HQC2AQAAAA==.Shadyshifts:BAAALgADCgYJBgABLgAFFAQJEQAMAMcYAA==.Shadôwhunt:BAABLgAECn8fAAIMAAgJchWAXQDaAQAMAAgJchWAXQDaAQAAAA==.Shenlon:BAACLgAFFH8rAAMHAAYJQyHaAACqAQAYAAYJLx0zDgDTAQAHAAUJISbaAACqAQAuAAQKfy4ABAcACQm+JJMAAI0DAAcACQmPIZMAAI0DABIABQlvHUcSAJEBABgABAmKI9AlAI8BAAAA.Shilor:BAABLgAECn8lAAIVAAgJDRhBFgAFAgAVAAgJDRhBFgAFAgAAAA==.Shogun:BAAALgAECggJEQAAAA==.Shulamite:BAAALgADCgYJBgAAAA==.Shuye:BAAALgAECgMJBAAAAA==.',
Si='Sicarii:BAAALgAECgEJAQABLgAECgcJDgANAAAAAA==.Sicarrious:BAAALgAECgcJDgAAAA==.Sinaliska:BAAALgADCgQJBAAAAA==.Sinistr:BAABLgAECn8WAAMLAAcJChyjJwDyAQALAAcJChyjJwDyAQAKAAQJIAUfIgCyAAAAAA==.',
Sk='Skyarc:BAAALgAECgUJBgAAAA==.Skyrun:BAAALgAECgMJAwABLgAECgUJBgANAAAAAA==.',
Sm='Smiffbrew:BAAALgADCgMJBAAAAA==.Smiffury:BAAALgAECgYJCQAAAA==.',
Sn='Snicks:BAAALgAECgIJAgAAAA==.',
Sq='Squishyshoe:BAAALgAECgEJAQAAAA==.',
St='Stinkythebum:BAABLgAECn8ZAAIZAAgJ5RmOEQAhAgAZAAgJ5RmOEQAhAgAAAA==.Stoneymalone:BAAALgAECgIJAwAAAA==.Stélle:BAABLgAECn8bAAIDAAkJvAp/DQBwAQADAAkJvAp/DQBwAQAAAA==.',
Su='Supdude:BAABLgAECn84AAMEAAkJ/iICAwAOAwAEAAkJ/iICAwAOAwAfAAEJaRz2DQA6AAAAAA==.',
Ta='Tairnbys:BAAALgAECgMJAwAAAA==.Tazbirkloa:BAAALgADCgIJAgAAAA==.',
Te='Tebzerk:BAAALgAECgcJDgAAAA==.Tekk:BAAALgAECgcJCgAAAA==.Temptress:BAAALgADCgIJAwAAAA==.',
Th='Thatssotank:BAAALgAECgMJBgABLgAFFAQJCgAFAAgRAA==.Thorokk:BAAALgAECgMJAwAAAA==.Thynrage:BAAALgAECgUJBgAAAA==.',
Ti='Tictac:BAAALgADCgUJBQAAAA==.Tigas:BAACLgAFFH8IAAIQAAMJkCGaHgAiAQAQAAMJkCGaHgAiAQAuAAQKfy4AAxAACAnQJLoIAMICABAACAnQJLoIAMICAA4AAQljFuxfAEQAAAAA.',
To='Tooth:BAAALgAECgEJAgAAAA==.Tor:BAAALgADCgMJAwABLgAECgcJEQANAAAAAA==.',
Tr='Trashdragon:BAABLgAECn8xAAMHAAkJWyIuAQDpAgAHAAkJPCEuAQDpAgAYAAgJNx6yDgCKAgAAAA==.Trauma:BAAALgAECgMJAwAAAA==.',
Ty='Tygrans:BAAALgADCgUJBQAAAA==.Typhoonz:BAAALgADCgEJAQAAAA==.',
['Tö']='Töby:BAAALgAECgcJEQAAAA==.',
Ul='Ulric:BAAALgAECgQJBQAAAA==.',
Um='Umgunk:BAAALgAECgQJBQAAAA==.Ummabunbun:BAAALgADCgMJAwAAAA==.',
Un='Unorthodox:BAAALgAECgUJCAAAAA==.',
Us='Usagi:BAABLgAECn8dAAIBAAcJ9hviTQDFAQABAAcJ9hviTQDFAQAAAA==.',
Ut='Utsuro:BAAALgAECgMJAwABLgAECggJDAANAAAAAA==.',
Va='Vannacutt:BAABLgAECn8UAAIQAAgJkgydNQBdAQAQAAgJkgydNQBdAQABLgAECggJDAANAAAAAA==.Vaz:BAAALgAECgQJBAAAAA==.',
Ve='Velzevul:BAAALgADCgYJBgAAAA==.Vermouth:BAAALgAECgUJCAAAAA==.',
Vi='Vincentx:BAAALgADCgUJCwAAAA==.',
Vv='Vvinter:BAAALgAECgEJAQAAAA==.',
Vy='Vynii:BAACLgAFFH8FAAIhAAQJNgTXUgDTAAAhAAQJNgTXUgDTAAAuAAQKfzMAAyEACQlnFVI3ANIBACEACQlbElI3ANIBABMABgmCGDwmAI4BAAAA.',
Wa='Wardamage:BAAALgADCgYJBgAAAA==.Wasabi:BAAALgAECggJEAAAAA==.',
We='Weenygripper:BAABLgAECn8XAAIMAAcJnxE8gABNAQAMAAcJnxE8gABNAQABLgAFFAUJDgAFAHYiAA==.',
Wf='Wfaps:BAAALgAECgQJCAAAAA==.',
Wo='Wonon:BAAALgAFFAEJAQAAAA==.Wontonboy:BAAALgADCgEJAQAAAA==.',
Wu='Wuufi:BAAALgADCgYJBgAAAA==.',
Xa='Xaam:BAAALgAECgUJCAAAAA==.Xaida:BAACLgAFFH8XAAIXAAcJxBXKCQAaAgAXAAcJxBXKCQAaAgAuAAQKfxUAAgYACQl7DDQiAIYBAAYACQl7DDQiAIYBAAEuAAUUCQkxABIAVxgA.',
Xe='Xecutioner:BAAALgAECgYJDAAAAA==.',
Xi='Xilantaeki:BAAALgADCgYJCAAAAA==.',
Yq='Yqwegvbwefhu:BAAALgAECgMJBwAAAA==.',
Za='Zangyaku:BAEBLgAECn8iAAIgAAkJrCUsAQBNAwAgAAkJrCUsAQBNAwAAAA==.Zanmetsu:BAEBLgAECn8dAAMEAAcJrRyNGABDAgAEAAcJrRyNGABDAgAeAAEJjgzsHgA4AAABLgAECgkJIgAgAKwlAA==.Zarlock:BAAALgADCgYJBgAAAA==.',
Ze='Zeji:BAABLgAECn87AAMLAAkJBB26DADbAgALAAkJBB26DADbAgAaAAQJmRrOQQAQAQAAAA==.Zerocool:BAABLgAECn8fAAIlAAkJBRMrQgAGAgAlAAkJBRMrQgAGAgAAAA==.',
Zu='Zuggernaut:BAAALgADCgYJBgAAAA==.Zugquavious:BAAALgAECgcJDgABLgAECggJGAAKACAaAA==.Zugzug:BAAALgAECgMJAwAAAA==.',
Zy='Zyggy:BAABLgAECn8UAAIbAAgJJxGUKAByAQAbAAgJJxGUKAByAQAAAA==.',
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
