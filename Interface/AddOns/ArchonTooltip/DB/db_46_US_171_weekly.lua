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

local lookup = {'Paladin-Retribution','Druid-Restoration','Hunter-Marksmanship','Rogue-Subtlety','Mage-Frost','Monk-Brewmaster','Evoker-Devastation','Paladin-Holy','Paladin-Protection','Shaman-Enhancement','Shaman-Restoration','DeathKnight-Blood','Warrior-Arms','Warrior-Protection','Warrior-Fury','Druid-Guardian','Evoker-Preservation','Unknown-Unknown','DeathKnight-Unholy','DemonHunter-Havoc','Hunter-BeastMastery','Priest-Discipline','Priest-Holy','Monk-Mistweaver','Evoker-Augmentation','Monk-Windwalker','Shaman-Elemental','Druid-Balance','DemonHunter-Vengeance','Warlock-Destruction','Rogue-Assassination','Rogue-Outlaw','DemonHunter-Devourer','Priest-Shadow','DeathKnight-Frost','Hunter-Survival','Warlock-Demonology',}
local provider = {region='US',realm='Onyxia',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abrams:BAABLgAECn8bAAIBAAgJ+hljRADaAQABAAgJ+hljRADaAQAAAA==.',
Ad='Addý:BAABLgAECn8XAAICAAkJgBd8IgASAgACAAkJgBd8IgASAgAAAA==.Advanced:BAAALgADCgQJAQAAAA==.',
Ah='Ahimsa:BAABLgAECn83AAIDAAkJNR8OAgDGAgADAAkJNR8OAgDGAgAAAA==.',
Al='Alisonchains:BAABLgAECn8kAAIEAAYJFSTQEwDfAQAEAAYJFSTQEwDfAQAAAA==.Alkyri:BAAALgAECgEJAQAAAA==.Alternate:BAABLgAECn80AAIFAAkJYxsXHQCTAgAFAAkJYxsXHQCTAgAAAA==.',
Am='Amigo:BAAALgADCgEJAQAAAA==.Amillerbrew:BAABLgAECn8aAAIGAAgJTxaYJQDXAQAGAAgJTxaYJQDXAQAAAA==.',
An='Anayanci:BAAALgAECgQJDAAAAA==.Anesh:BAAALgAECgMJBQAAAA==.Anjuna:BAAALgAECgYJDwAAAA==.Anshee:BAAALgAECgIJAwAAAA==.Anubrin:BAAALgADCgUJBwAAAA==.',
As='Ashenclaw:BAABLgAECn8sAAIHAAgJNhpKBAAWAgAHAAgJNhpKBAAWAgAAAA==.',
Au='Auzatryx:BAAALgAECgYJCgAAAA==.',
Ba='Bamboom:BAABLgAECn8YAAQIAAcJsBaIIQDRAQAIAAcJsBaIIQDRAQABAAEJFgJShgEXAAAJAAEJRAHATwARAAAAAA==.Bapbap:BAAALgADCgYJBgAAAA==.',
Be='Beefstick:BAAALgAECgMJAgAAAA==.Belanik:BAAALgAECgEJBAAAAA==.Beleth:BAAALgADCgYJBgAAAA==.',
Bi='Bigblktotem:BAABLgAECn8WAAMKAAYJlAzwFwBDAQAKAAYJlAzwFwBDAQALAAMJHQQHmQBbAAABLgAFFAMJCgAMALEYAA==.Biggrnmonstr:BAAALgAECgYJDQABLgAFFAMJCgAMALEYAA==.Bigrabit:BAAALgAECgMJAwAAAA==.Biirf:BAAALgAECgUJBgAAAA==.',
Bl='Blaine:BAAALgAECgMJAwAAAA==.Blãze:BAAALgADCgIJAgAAAA==.',
Bo='Bogdan:BAAALgADCgEJAQAAAA==.Bomi:BAAALgAECgQJCQAAAA==.Boogiebm:BAAALgAECgcJCwAAAA==.Borgon:BAAALgAECgEJAgAAAA==.Bowevil:BAAALgADCgMJAwAAAA==.Boypartz:BAABLgAECn8xAAMNAAkJ4x2SBACoAgANAAkJ4x2SBACoAgAOAAEJKwmNTQAiAAAAAA==.',
Br='Breakfast:BAAALgAECgEJAQAAAA==.',
Bu='Bulbasaurus:BAACLgAFFH8SAAIPAAQJQCVGBgClAQAPAAQJQCVGBgClAQAuAAQKfx8AAg8ACQmjImkGAN0CAA8ACQmjImkGAN0CAAAA.Bulloney:BAAALgADCgIJAgAAAA==.Bunana:BAAALgADCgIJAgAAAA==.Bus:BAAALgAFFAMJBAABLgAFFAkJFwAQAJ8jAA==.',
Ca='Cabooze:BAAALgAECgYJBwAAAA==.Cacho:BAAALgAECgQJCAAAAA==.Cañonazo:BAAALgAECgEJAQAAAA==.',
Ce='Celeres:BAABLgAECn8eAAIRAAgJeBgiEQAqAgARAAgJeBgiEQAqAgAAAA==.Celys:BAAALgAECgUJBgAAAA==.Cerealkillah:BAAALgAECgEJAQAAAA==.',
Ch='Chantilly:BAAALgAECgYJBgAAAA==.Chartreuse:BAAALgADCgMJBAABLgAECgUJCAASAAAAAA==.Chaw:BAAALgAECgEJAQAAAA==.Cheesecurds:BAAALgADCgcJBwAAAA==.Cheesied:BAAALgADCgQJAwAAAA==.Chios:BAAALgAECgUJBQABLgAFFAcJFAAOAJ4YAA==.',
Cl='Cleetiscat:BAAALgAECgYJBgAAAA==.',
Co='Cowabunga:BAAALgADCgEJAQAAAA==.',
Cr='Crow:BAAALgAFFAYJEgAAAQ==.Cryoblade:BAAALgADCgcJDAAAAA==.',
Cu='Cuttanee:BAAALgAECggJDAAAAA==.',
Cy='Cyril:BAAALgADCgkJFwAAAA==.',
Da='Daevon:BAAALgAECgQJEAAAAA==.Daron:BAAALgAECgcJDgABLgAECgcJEQASAAAAAA==.Darrowreaper:BAABLgAECn8eAAITAAgJzQ2SYgB/AQATAAgJzQ2SYgB/AQAAAA==.',
De='Deadcell:BAAALgAECgYJBwAAAA==.Deatheria:BAAALgADCgMJAwAAAA==.Deathstar:BAAALgAECgUJBQAAAA==.Denarrage:BAACLgAFFH8LAAIUAAUJMAmKDQAPAQAUAAUJMAmKDQAPAQAuAAQKfy4AAhQACQnuFFcQAO4BABQACQnuFFcQAO4BAAAA.Denawage:BAAALgAECggJCAAAAA==.',
Di='Dirtytotem:BAAALgAECgcJDwAAAA==.Discordia:BAAALgAECggJDQAAAA==.Disprop:BAAALgAECgEJAQAAAA==.Dizyizy:BAAALgAECgUJBwAAAA==.',
Do='Doingmost:BAAALgAECgEJAQAAAA==.Dontnerfspls:BAAALgAECgMJBQABLgAFFAMJCgAMALEYAA==.Doomby:BAAALgAECgYJDAABLgAECggJJQAUAKgXAA==.',
Dr='Drakesh:BAAALgADCgEJAQAAAA==.Drakussy:BAAALgAECggJDgABLgAECggJJQAUAKgXAA==.Drudekay:BAAALgAECgEJAQAAAA==.',
Du='Dullslinkie:BAAALgADCgEJAQAAAA==.',
El='Eldarborn:BAAALgAECgUJBQAAAA==.Eleannar:BAAALgAECgEJAQAAAA==.Elficpaladin:BAAALgAECgYJCQAAAA==.Elixxi:BAAALgAECgUJCQAAAA==.Elladin:BAAALgADCgcJBwAAAA==.Ellipsi:BAAALgAECgUJCAAAAA==.Ellipsoro:BAACLgAFFH8IAAITAAMJBB4BaAD6AAATAAMJBB4BaAD6AAAuAAQKfy4AAhMACQl4JQIGADEDABMACQl4JQIGADEDAAAA.Eltrol:BAACLgAFFH8IAAIVAAMJbgkOSQDUAAAVAAMJbgkOSQDUAAAuAAQKfxgAAhUACQlyFIAhADUCABUACQlyFIAhADUCAAAA.Eluriana:BAAALgAECgYJCAABLgAFFAUJEwAGAKcRAA==.',
Er='Erale:BAAALgADCgYJDAAAAA==.Eredarn:BAAALgADCgEJAQAAAA==.Erienor:BAAALgADCgkJDAAAAA==.',
Ev='Evldrprkchop:BAAALgADCgIJAgAAAA==.',
Ex='Executiepie:BAACLgAFFH8UAAIOAAcJnhhiAQDbAQAOAAcJnhhiAQDbAQAuAAQKfyIAAg4ACQmiILkCADsDAA4ACQmiILkCADsDAAAA.Exodia:BAAALgAECgYJBgAAAA==.',
Fa='Faeris:BAACLgAFFH8JAAMWAAMJYhePIQDzAAAWAAMJYhePIQDzAAAXAAEJMQ2qEgBPAAAuAAQKfyIAAxcACQkkItMBAFkDABcACQkkItMBAFkDABYAAgnfGodFAI0AAAAA.Faolain:BAABLgAECn8kAAICAAgJQBGPPgB2AQACAAgJQBGPPgB2AQAAAA==.Fatalis:BAACLgAFFH8XAAIVAAYJ8QqzHgBLAQAVAAYJ8QqzHgBLAQAuAAQKfywAAxUACQkLHKQRAJsCABUACQkLHKQRAJsCAAMACAlcBLJRAAYBAAAA.',
Fe='Fetch:BAAALgAECgkJBgAAAA==.',
Fi='Fiddlestix:BAAALgAECgUJCgAAAA==.Fims:BAAALgAECgYJCgAAAA==.Finarfin:BAAALgADCgkJCQAAAA==.Fireballcat:BAAALgADCgMJBQAAAA==.Fizaw:BAABLgAECn83AAIYAAkJcAesPAAlAQAYAAkJcAesPAAlAQAAAA==.',
Fl='Floydbussy:BAABLgAFFH8JAAIZAAUJjAxaKAD8AAAZAAUJjAxaKAD8AAAAAA==.',
Fr='Freeng:BAAALgADCgYJBgAAAA==.Freeze:BAAALgAECgEJAQAAAA==.Freyya:BAAALgAECgEJAQAAAA==.Frøzen:BAAALgAECgIJAgAAAA==.',
Fu='Fuzzydots:BAAALgAECgMJBgAAAA==.',
['Fë']='Fëanør:BAABLgAECn8XAAIBAAgJ7RO0ZgCzAQABAAgJ7RO0ZgCzAQAAAA==.',
Ga='Galnir:BAAALgAECgMJAwAAAA==.Gatorbait:BAAALgAECgQJBAAAAA==.Gaurr:BAAALgAECgMJBAAAAA==.Gazzcool:BAAALgAECgkJBwAAAA==.',
Ge='Geneviere:BAAALgAECgQJBQAAAA==.Gex:BAAALgAECggJDQAAAA==.',
Gh='Ghostzen:BAACLgAFFH8IAAIaAAMJXBr7FgDlAAAaAAMJXBr7FgDlAAAuAAQKfx0AAhoACQlUJQgBALsDABoACQlUJQgBALsDAAAA.',
Gi='Gislain:BAABLgAECn8eAAMLAAgJUBHROgCWAQALAAgJUBHROgCWAQAbAAYJ3gwpRwDmAAAAAA==.',
Go='Goldeye:BAAALgADCgMJAwAAAA==.Gooichi:BAAALgAECgEJAgAAAA==.Gothmogsbane:BAABLgAECn8WAAMCAAgJdBHwTQAzAQACAAYJzRHwTQAzAQAcAAgJKwTEUgDcAAAAAA==.',
Gr='Greaves:BAAALgAECgQJBAABLgAFFAUJFwAdAEkmAA==.Greyspirit:BAABLgAECn8vAAIQAAkJKCAwAwDUAgAQAAkJKCAwAwDUAgAAAA==.Grez:BAAALgAECgQJBgAAAA==.Grubnub:BAAALgADCgEJAQABLgAECgkJNgALAO8bAA==.',
Gu='Gumpy:BAAALgAECggJDAAAAA==.',
Ha='Halcoldrek:BAAALgAECgMJAwAAAA==.Hamburguesa:BAAALgAECgMJBAAAAA==.Hanta:BAAALgADCgIJAwAAAA==.Harkiel:BAAALgAECgUJBwAAAA==.',
He='Heyz:BAABLgAECn8jAAMWAAgJKRw0DQBuAgAWAAgJKRw0DQBuAgAXAAEJkwCligAhAAAAAA==.',
Hi='Hibernate:BAAALgADCgIJAgAAAA==.Himbo:BAAALgAECgcJCQAAAA==.Hipocrit:BAAALgAECgcJCQAAAA==.',
Ho='Hog:BAAALgAECgYJBwAAAA==.Holypoopp:BAABLgAECn88AAQBAAkJnh1PIQBiAgABAAkJnh1PIQBiAgAJAAkJrwwLFABdAQAIAAYJKRR6SgBOAQAAAA==.Hondalorian:BAABLgAECn81AAIVAAkJUBZhJAAmAgAVAAkJUBZhJAAmAgAAAA==.Honkmydemon:BAAALgADCgMJAwAAAA==.Honkmyscars:BAAALgAECgEJAQAAAA==.Hordranir:BAAALgADCgIJAgAAAA==.',
['Hë']='Hëxy:BAAALgADCgYJBgAAAA==.',
Im='Imran:BAACLgAFFH8QAAIJAAMJlgxRCgCfAAAJAAMJlgxRCgCfAAAuAAQKf00AAwkACQkuFlwKAPgBAAkACQkuFlwKAPgBAAEABwmhBKXPAOoAAAAA.',
In='Inkdawarlock:BAAALgAECgEJAQAAAA==.',
['Iå']='Iåomai:BAAALgADCgMJAwAAAA==.',
Ja='Jabronee:BAABLgAECn8bAAIPAAYJUBt1LQB2AQAPAAYJUBt1LQB2AQAAAA==.',
Je='Jerikoh:BAAALgAECgEJAgAAAA==.Jether:BAAALgAECgUJEAAAAA==.',
Jk='Jkingoreborn:BAABLgAECn8bAAIJAAcJ6B9NCgD4AQAJAAcJ6B9NCgD4AQABLgAECggJGAAVACQTAA==.',
Jo='Jodormi:BAAALgADCgkJCQABLgAECgkJHQAeAM0YAA==.Jodrin:BAAALgADCgEJAQAAAA==.Jojobaggins:BAABLgAECn8aAAQfAAcJPhoVCwBhAQAEAAUJeRdkMQB8AQAfAAcJFhcVCwBhAQAgAAQJLBpTBwAwAQAAAA==.Jopine:BAAALgAECgEJAQABLgAECgkJHQAeAM0YAA==.',
Ka='Kaadriluna:BAAALgADCgMJBAAAAA==.Kaena:BAAALgADCgYJBgAAAA==.Kaey:BAAALgAECgQJBAAAAA==.Kaname:BAAALgAECgYJEAAAAA==.Katalyst:BAAALgAECgIJAgAAAA==.',
Ke='Keiri:BAAALgADCgMJAwAAAA==.Keyholes:BAABLgAFFH8MAAIMAAYJJRhsCgB3AQAMAAYJJRhsCgB3AQABLgAFFAcJFAAOAJ4YAA==.Keyohs:BAAALgAECgUJBQABLgAFFAcJFAAOAJ4YAA==.',
Kh='Khe:BAAALgAECgYJBwABLgAECgkJNgALAO8bAA==.',
Ki='Kittybear:BAAALgAFFAEJAQABLgAFFAgJIwAOANwiAA==.',
Kk='Kkoda:BAAALgAECgUJBQAAAA==.',
Ko='Koal:BAABLgAECn8hAAIVAAgJuhhGNgDaAQAVAAgJuhhGNgDaAQAAAA==.Kodabear:BAAALgADCgcJBwAAAA==.',
Kp='Kpop:BAAALgADCgcJBwABLgAFFAkJHwADAHciAA==.',
Kr='Kreen:BAAALgADCgcJBwAAAA==.Krom:BAABLgAECn8VAAMBAAcJsARm0gDKAAABAAcJsARm0gDKAAAJAAEJGABWUAADAAABLgAECggJKgALAD4QAA==.Kronos:BAAALgAECgcJBwABLgAECgYJCgASAAAAAA==.',
Ku='Kuroneko:BAAALgAECgMJAwAAAA==.Kushage:BAAALgAECgEJAQAAAA==.',
Ky='Kyomu:BAAALgADCgMJAwAAAA==.',
La='Lara:BAABLgAECn8iAAMVAAgJhg+EUgB9AQAVAAgJhg+EUgB9AQADAAYJ/goTSwAmAQAAAA==.Lavaa:BAAALgADCgEJAQAAAA==.',
Le='Leibniz:BAAALgADCgMJAwAAAA==.Lesgoth:BAAALgAECgYJBgAAAA==.Lettussy:BAABLgAFFH8NAAQEAAQJGx60DwBbAQAEAAQJGx60DwBbAQAgAAQJCgeUBQAJAQAfAAEJRwqaDgBKAAABLgAFFAYJGQAFAOgbAA==.Ley:BAAALgAECgUJBgAAAA==.Leya:BAAALgAECgIJAgAAAA==.',
Li='Lightsbelow:BAAALgADCgIJAgAAAA==.Lix:BAABLgAECn8YAAICAAYJtQw1aQDYAAACAAYJtQw1aQDYAAAAAA==.',
Lo='Loliruri:BAAALgAECgYJDgAAAA==.Loreleì:BAAALgADCgMJAwAAAA==.Louis:BAAALgAECgEJAQAAAA==.',
Lu='Luffymd:BAAALgAECgQJBwAAAA==.Luminyssa:BAAALgAECgYJBwAAAA==.',
['Lú']='Lúthien:BAABLgAECn80AAIYAAkJ5iJuBQAlAwAYAAkJ5iJuBQAlAwAAAA==.',
Ma='Madoka:BAAALgAECgYJDwAAAA==.Makari:BAAALgADCgMJAwAAAA==.Matrix:BAAALgAECgcJCQAAAA==.Mavenn:BAAALgAECgEJAQAAAA==.Maxchungus:BAABLgAECn81AAMTAAkJ8yGxEwCyAgATAAkJ8yGxEwCyAgAMAAYJPQ8WJAAgAQAAAA==.',
Me='Meatsuit:BAAALgAECgIJAgAAAA==.Meloo:BAABLgAECn8lAAMUAAgJqBdzEQDcAQAUAAgJqBdzEQDcAQAhAAYJ2AZ6owCwAAAAAA==.Meteor:BAAALgADCgUJBQAAAA==.',
Mi='Mightguy:BAAALgAECgEJAQAAAA==.Mikehawncho:BAAALgAECgQJBwABLgAECgcJHgATAFUbAA==.Mizu:BAAALgAECgMJAwAAAA==.',
Mo='Moknahddon:BAAALgADCgQJBAAAAA==.Moment:BAABLgAECn8hAAIHAAkJ0xnNAgBiAgAHAAkJ0xnNAgBiAgAAAA==.Morthrisia:BAAALgADCgUJBQAAAA==.',
Mu='Muna:BAAALgAECgEJAQAAAA==.Murrmau:BAAALgAECgYJDgAAAA==.Muufarmer:BAAALgADCggJCAAAAA==.',
Na='Naerys:BAAALgAECgcJDAAAAA==.Nalguilidan:BAAALgADCgYJBgAAAA==.Natmau:BAAALgADCgQJBAAAAA==.Naughtyelf:BAAALgADCgQJBQAAAA==.',
Ne='Nemene:BAAALgADCgEJAQAAAA==.Neyt:BAABLgAECn8nAAMhAAkJKBuLGQBeAgAhAAkJKBuLGQBeAgAUAAEJiRURcAA1AAAAAA==.',
Ni='Niddalee:BAAALgAECgcJDgAAAA==.Nioh:BAAALgAECgYJDwAAAA==.Niohscuck:BAAALgADCgEJAQAAAA==.Nitesrider:BAAALgAECgQJCAAAAA==.',
No='Nora:BAACLgAFFH8WAAIBAAgJZSBqAwBLAgABAAgJZSBqAwBLAgAuAAQKfzYAAwEACQlwJs4EAH8DAAEACQlwJs4EAH8DAAgAAwktFvFRAMQAAAAA.Nori:BAAALgADCgkJDgABLgAFFAgJKAAFAFIkAA==.Noshikoshi:BAAALgAECgIJAwAAAA==.Nostrodom:BAAALgAECgEJAgAAAA==.',
Nu='Nubbs:BAABLgAECn8XAAIaAAkJwRsnDwAvAgAaAAkJwRsnDwAvAgAAAA==.',
Ny='Nyissa:BAAALgADCgYJCQAAAA==.Nyonà:BAAALgADCgQJBAAAAA==.',
Oc='Octas:BAAALgAECgMJAwABLgAFFAUJEwAGAKcRAA==.',
Of='Offen:BAAALgAECgIJAgAAAA==.',
Og='Ogmonkas:BAAALgAECgEJAgAAAA==.',
On='On:BAAALgAECgQJBgAAAA==.Onlyinusa:BAABLgAECn8ZAAIQAAgJux+vBQB5AgAQAAgJux+vBQB5AgAAAA==.Onyxnate:BAAALgADCgkJJQAAAA==.',
Op='Opalith:BAAALgAECgIJAgABLgAECgMJAwASAAAAAA==.Opel:BAAALgADCgUJCAABLgAFFAQJFAAaAJALAA==.Opi:BAAALgADCgcJBwAAAA==.',
Or='Orbyn:BAAALgADCgEJAQAAAA==.Ortah:BAAALgADCgEJAQAAAA==.',
Ox='Oxyrania:BAAALgADCgEJAQAAAA==.',
Pf='Pfhor:BAAALgAECgYJBgAAAA==.',
Ph='Phillyshiho:BAAALgAECgcJEwABLgAECgkJIQAiAPEQAA==.',
Pi='Pinkdefender:BAAALgAECggJEAABLgAFFAMJCgAMALEYAA==.',
Po='Pokeumon:BAAALgADCgEJAQAAAA==.Poor:BAAALgAECgMJBwAAAA==.Poosistrox:BAACLgAFFH8KAAQMAAMJsRiQLQA6AAATAAIJ2R89jgCxAAAjAAIJYQ6IEgCQAAAMAAEJkAWQLQA6AAAuAAQKfyEAAxMACAkoHrUvAHkCABMACAkoHrUvAHkCAAwABAlvBxw3AIkAAAAA.Pornelius:BAAALgAECgcJCwABLgAECgkJMQANAOMdAA==.Potumkin:BAAALgADCgQJBgAAAA==.',
Pt='Ptheve:BAACLgAFFH8aAAMhAAkJ8B7bAACgAgAhAAgJUB7bAACgAgAUAAMJSiJwCwAnAQAuAAQKfykAAyEACQmvJXcBAMgDACEACQmoJXcBAMgDABQABwmNJKoUACsCAAAA.',
Pu='Pump:BAAALgADCgEJAQAAAA==.Putang:BAAALgAECgEJAQAAAA==.',
['På']='Pållås:BAAALgADCgMJAwAAAA==.',
Qn='Qnyx:BAABLgAECn8nAAIiAAcJfRKQKQBcAQAiAAcJfRKQKQBcAQAAAA==.',
Ra='Raelindra:BAABLgAECn8dAAIeAAkJzRj2AwAhAgAeAAkJzRj2AwAhAgAAAA==.Rayalla:BAAALgADCgUJBQAAAA==.Raygor:BAAALgAECgYJDAAAAA==.',
Re='Rebuke:BAABLgAECn8aAAIBAAgJeRbhQwDbAQABAAgJeRbhQwDbAQAAAA==.',
Ro='Rookorblood:BAABLgAECn8XAAIPAAYJzgWbVQDKAAAPAAYJzgWbVQDKAAAAAA==.Rosewalker:BAACLgAFFH8WAAIGAAUJACRvCQCmAQAGAAUJACRvCQCmAQAuAAQKfzkAAwYACQk9JX4BAEQDAAYACQk9JX4BAEQDABoACQntGzIIAJ8CAAAA.Rosewall:BAAALgAECgQJBQABLgAFFAUJFgAGAAAkAA==.Rottgut:BAAALgAECgYJDQAAAA==.',
Ry='Ryachun:BAAALgADCgMJAwAAAA==.Rykò:BAABLgAECn84AAQVAAkJrR8lCgDjAgAVAAkJrR8lCgDjAgAkAAYJGgekMwDrAAADAAUJ7BA3XgDIAAAAAA==.',
Sa='Salchaos:BAABLgAECn8eAAQNAAgJCRZ5DwCkAQAPAAcJiRZPMgDjAQANAAcJ2xR5DwCkAQAOAAQJMxAiLgDRAAAAAA==.Samsmith:BAAALgAECgYJBgAAAA==.Savork:BAABLgAECn8YAAMVAAgJJBNCZQBMAQAVAAUJ1BNCZQBMAQADAAYJog6IGwCwAAAAAA==.Sayafaed:BAABLgAECn8fAAIhAAkJJgv2UABwAQAhAAkJJgv2UABwAQAAAA==.Sayamese:BAAALgAECggJEwAAAA==.',
Sc='Scatback:BAABLgAECn86AAQWAAkJeRheEQAyAgAWAAkJPBJeEQAyAgAXAAgJQxlaFAAOAgAiAAMJvQm+bAA2AAAAAA==.Schwiddylock:BAAALgAECgUJCgAAAA==.Scud:BAABLgAECn8fAAIiAAkJMw3NJAB7AQAiAAkJMw3NJAB7AQAAAA==.Scáthach:BAAALgADCgYJCAAAAA==.',
Se='Senuna:BAAALgADCgEJAQAAAA==.Seraphae:BAAALgADCgMJAwAAAA==.Seraphnite:BAAALgAECgQJBAAAAA==.',
Sh='Shadowdaddy:BAABLgAECn8hAAIiAAkJ8RBLGgDOAQAiAAkJ8RBLGgDOAQAAAA==.Shadôwhunt:BAABLgAECn8fAAITAAgJchWAXQDaAQATAAgJchWAXQDaAQAAAA==.Shenlon:BAACLgAFFH8lAAMHAAYJ2x6fAACxAQAHAAUJISafAACxAQAZAAUJURkJDgCsAQAuAAQKfy4ABAcACQm+JJMAAI0DAAcACQmPIZMAAI0DABEABQlvHTQRAJEBABkABAmKI9AlAI8BAAAA.Shilor:BAABLgAECn8lAAIWAAgJDRgoFAAOAgAWAAgJDRgoFAAOAgAAAA==.Shogun:BAAALgAECgcJEAAAAA==.Shulamite:BAAALgADCgYJBgAAAA==.Shuye:BAAALgAECgMJBAAAAA==.',
Si='Sicarii:BAAALgAECgEJAQABLgAECgcJDgASAAAAAA==.Sicarrious:BAAALgAECgcJDgAAAA==.Sinaliska:BAAALgADCgQJBAAAAA==.Sinistr:BAABLgAECn8WAAMLAAcJChyjJwDyAQALAAcJChyjJwDyAQAKAAQJIAUfIgCyAAAAAA==.',
Sk='Skyarc:BAAALgAECgUJBgAAAA==.Skyrun:BAAALgAECgMJAwABLgAECgUJBgASAAAAAA==.',
Sm='Smiffbrew:BAAALgADCgMJBAAAAA==.Smiffury:BAAALgAECgYJCQAAAA==.',
Sn='Snicks:BAAALgAECgIJAgAAAA==.',
Sq='Squishyshoe:BAAALgAECgEJAQAAAA==.',
St='Stinkythebum:BAAALgAECgcJDwAAAA==.Stoneymalone:BAAALgAECgIJAwAAAA==.Stélle:BAABLgAECn8VAAIDAAgJRQcREgAUAQADAAgJRQcREgAUAQAAAA==.',
Su='Supdude:BAABLgAECn82AAMEAAkJ/iJzAgAYAwAEAAkJ/iJzAgAYAwAgAAEJaRz2DQA6AAAAAA==.',
Ta='Tairnbys:BAAALgAECgMJAwAAAA==.Tazbirkloa:BAAALgADCgIJAgAAAA==.',
Te='Tebzerk:BAAALgAECgYJDQAAAA==.Tekk:BAAALgAECgcJCgAAAA==.Temptress:BAAALgADCgIJAwAAAA==.',
Th='Thatssotank:BAAALgAECgMJBAABLgAFFAMJBgAFACIOAA==.Thorokk:BAAALgAECgMJAwAAAA==.Thynrage:BAAALgAECgUJBgAAAA==.',
Ti='Tigas:BAABLgAECn8qAAIPAAgJryRRCAC9AgAPAAgJryRRCAC9AgAAAA==.',
To='Tooth:BAAALgAECgEJAgAAAA==.Tor:BAAALgADCgMJAwABLgAECgcJEQASAAAAAA==.',
Tr='Trashdragon:BAABLgAECn8xAAMHAAkJWyILAQDvAgAHAAkJPCELAQDvAgAZAAgJNx6yDgCKAgAAAA==.Trauma:BAAALgAECgMJAwAAAA==.',
Ty='Tygrans:BAAALgADCgUJBQAAAA==.Typhoonz:BAAALgADCgEJAQAAAA==.',
['Tö']='Töby:BAAALgAECgcJEQAAAA==.',
Ul='Ulric:BAAALgAECgQJBQAAAA==.',
Um='Umgunk:BAAALgAECgQJBQAAAA==.Ummabunbun:BAAALgADCgMJAwAAAA==.',
Un='Unorthodox:BAAALgAECgUJCAAAAA==.',
Us='Usagi:BAABLgAECn8bAAIBAAYJ3BqocwBnAQABAAYJ3BqocwBnAQAAAA==.',
Ut='Utsuro:BAAALgAECgMJAwABLgAECggJDAASAAAAAA==.',
Va='Vannacutt:BAABLgAECn8UAAIPAAgJkgw9MQBhAQAPAAgJkgw9MQBhAQABLgAECggJDAASAAAAAA==.Vaz:BAAALgAECgQJBAAAAA==.',
Ve='Velzevul:BAAALgADCgYJBgAAAA==.Vermouth:BAAALgAECgUJCAAAAA==.',
Vi='Vincentx:BAAALgADCgUJCwAAAA==.',
Vv='Vvinter:BAAALgAECgEJAQAAAA==.',
Vy='Vynii:BAABLgAECn8sAAMhAAkJNxQeRACZAQAhAAkJFhAeRACZAQAUAAYJghg8JgCOAQAAAA==.',
Wa='Wardamage:BAAALgADCgYJBgAAAA==.Wasabi:BAAALgAECgcJDwAAAA==.',
We='Weenygripper:BAABLgAECn8XAAITAAcJnxEVdgBRAQATAAcJnxEVdgBRAQABLgAFFAUJDgAFAHYiAA==.',
Wo='Wonon:BAAALgAFFAEJAQAAAA==.Wontonboy:BAAALgADCgEJAQAAAA==.',
Wu='Wuufi:BAAALgADCgYJBgAAAA==.',
Xa='Xaam:BAAALgAECgUJCAAAAA==.Xaida:BAACLgAFFH8QAAIYAAcJrRIVCQD/AQAYAAcJrRIVCQD/AQAuAAQKfxUAAgYACQl7DKkfAIsBAAYACQl7DKkfAIsBAAEuAAUUCQkvABEA+hcA.',
Xe='Xecutioner:BAAALgAECgYJBgAAAA==.',
Xi='Xilantaeki:BAAALgADCgYJCAAAAA==.',
Yq='Yqwegvbwefhu:BAAALgAECgMJBwAAAA==.',
Za='Zangyaku:BAEBLgAECn8iAAIMAAkJrCXPAABTAwAMAAkJrCXPAABTAwAAAA==.Zanmetsu:BAEBLgAECn8dAAMEAAcJrRyNGABDAgAEAAcJrRyNGABDAgAfAAEJjgzsHgA4AAABLgAECgkJIgAMAKwlAA==.Zarlock:BAAALgADCgYJBgAAAA==.',
Ze='Zeji:BAABLgAECn82AAMLAAkJ7xs3DgC6AgALAAkJ7xs3DgC6AgAbAAQJmRrMPAASAQAAAA==.Zerocool:BAABLgAECn8fAAIlAAkJBRMrQgAGAgAlAAkJBRMrQgAGAgAAAA==.',
Zu='Zuggernaut:BAAALgADCgYJBgAAAA==.Zugquavious:BAAALgAECgcJCQABLgAECgcJDwASAAAAAA==.Zugzug:BAAALgAECgMJAwAAAA==.',
Zy='Zyggy:BAABLgAECn8UAAIcAAgJJxFpJQByAQAcAAgJJxFpJQByAQAAAA==.',
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
