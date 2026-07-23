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

local lookup = {'Paladin-Retribution','Druid-Restoration','Hunter-Marksmanship','Rogue-Subtlety','Unknown-Unknown','Mage-Frost','Mage-Fire','Monk-Brewmaster','Evoker-Devastation','Paladin-Holy','Paladin-Protection','Shaman-Enhancement','Shaman-Restoration','DeathKnight-Unholy','Hunter-Survival','Druid-Guardian','Warrior-Arms','Warrior-Protection','Warrior-Fury','Evoker-Preservation','DemonHunter-Havoc','Hunter-BeastMastery','Priest-Discipline','Priest-Holy','Warlock-Demonology','Monk-Mistweaver','Evoker-Augmentation','Monk-Windwalker','Shaman-Elemental','Druid-Balance','DemonHunter-Vengeance','Warlock-Destruction','Rogue-Assassination','Rogue-Outlaw','DeathKnight-Blood','DemonHunter-Devourer','Priest-Shadow','DeathKnight-Frost',}
local provider = {region='US',realm='Onyxia',name='US',type='weekly',zone=46,date='2026-07-19',data={Ab='Abrams:BAABLgAECn8pAAIBAAkJERtcBgDvAQABAAkJERtcBgDvAQAAAA==.',
Ad='Addý:BAACLgAFFH8FAAICAAIJpQgDXQBhAAACAAIJpQgDXQBhAAAuAAQKfxgAAgIACQmAF4UoAA0CAAIACQmAF4UoAA0CAAAA.Advanced:BAAALgADCgQJAQAAAA==.',
Ah='Ahimsa:BAACLgAFFH8LAAIDAAQJcxWsFQAUAQADAAQJcxWsFQAUAQAuAAQKf0MAAgMACQmLIyABACoDAAMACQmLIyABACoDAAAA.',
Al='Alisonchains:BAABLgAECn9TAAIEAAkJxCN0AAAoAwAEAAkJxCN0AAAoAwAAAA==.Alixxia:BAAALgADCgYJBgABLgAFFAMJCAACABgJAA==.Alkyri:BAAALgAECgEJAQAAAA==.Almamun:BAAALgAECgIJBAABLgAECgUJBQAFAAAAAA==.Alternate:BAACLgAFFH8SAAIGAAQJjRWAKQARAQAGAAQJjRWAKQARAQAuAAQKf0UAAwYACQkZILUSAOoCAAYACQkZILUSAOoCAAcAAgkGGHANAJAAAAAA.',
Am='Amigo:BAAALgADCgEJAQAAAA==.Amillerbrew:BAABLgAECn8aAAIIAAgJTxaYJQDXAQAIAAgJTxaYJQDXAQAAAA==.',
An='Anayanci:BAAALgAECgQJDAAAAA==.Anesh:BAAALgAECgMJBQAAAA==.Anjuna:BAAALgAECgYJDwAAAA==.Anshee:BAAALgAECgIJAwAAAA==.Anubrin:BAAALgADCgkJEQAAAA==.',
Ap='Aphian:BAAALgAECgIJAgAAAA==.',
Ar='Arazel:BAAALgAECgEJAQABLgAECgkJKQABABEbAA==.',
As='Ashenclaw:BAABLgAECn86AAIJAAkJHxwmBAA7AgAJAAkJHxwmBAA7AgAAAA==.',
Au='Auzatryx:BAABLgAECn8VAAIEAAcJ/AzuKwA6AQAEAAcJ/AzuKwA6AQAAAA==.',
Av='Avadakablam:BAAALgAECgYJBgAAAA==.',
Az='Azophi:BAAALgAECgUJBQAAAA==.',
Ba='Bagpipe:BAAALgADCgkJCQAAAA==.Bamboom:BAABLgAECn8mAAQKAAgJQhYGBgBEAQAKAAgJQhYGBgBEAQABAAIJvQMgXgAeAAALAAEJRAHATwARAAAAAA==.Bapbap:BAAALgADCgYJBgAAAA==.',
Be='Beefstick:BAAALgAECgMJAgAAAA==.Belanik:BAAALgAECgEJBQAAAA==.Beleth:BAAALgADCgYJBgAAAA==.',
Bi='Bigblktotem:BAABLgAECn8WAAMMAAYJlAzwFwBDAQAMAAYJlAzwFwBDAQANAAMJHQQiugBZAAABLgAFFAQJHAAOAOscAA==.Biggrnmonstr:BAAALgAFFAIJAwABLgAFFAQJHAAOAOscAA==.Bigheffin:BAAALgAFFAEJAQABLgAFFAMJBQAPANYMAA==.Bigrabit:BAAALgAECgMJAwAAAA==.Bigslammin:BAAALgAFFAEJAQABLgAFFAMJBwAMACoXAA==.Bigxthezug:BAAALgAECgQJBgABLgAFFAMJBQAPANYMAA==.Biirf:BAAALgAECgUJBgAAAA==.',
Bl='Blaine:BAABLgAECn8VAAIQAAcJKCLiEQDSAQAQAAcJKCLiEQDSAQAAAA==.Blãze:BAAALgADCgIJAgAAAA==.',
Bo='Bogdan:BAAALgADCgEJAQAAAA==.Bomi:BAAALgAECgQJCQAAAA==.Boogiebm:BAABLgAFFH8FAAIIAAUJ2AUoDgDXAAAIAAUJ2AUoDgDXAAAAAA==.Borgon:BAAALgAECgEJAgAAAA==.Bowevil:BAAALgADCgMJAwAAAA==.Boypartz:BAABLgAECn8yAAMRAAkJbR6CBQCyAgARAAkJbR6CBQCyAgASAAEJKwmNTQAiAAAAAA==.',
Br='Brayuh:BAAALgAECgEJAwAAAA==.Breakfast:BAAALgAECggJCwABLgAFFAMJBQAPANYMAA==.',
Bu='Bulbasaurus:BAACLgAFFH8fAAITAAYJ8CX8CQDAAQATAAYJ8CX8CQDAAQAuAAQKfyAAAhMACQn/JHoHADEDABMACQn/JHoHADEDAAAA.Bulloney:BAAALgADCgIJAgAAAA==.Bunana:BAAALgADCgIJAgAAAA==.Burnnotice:BAAALgAECgEJAgAAAA==.Bus:BAAALgAFFAMJBAABLgAFFAkJHQAQAA8kAA==.',
Ca='Cabooze:BAAALgAECgYJBwAAAA==.Cacho:BAAALgAECgQJCAAAAA==.Cañonazo:BAAALgAECgEJAQAAAA==.',
Ce='Celeres:BAACLgAFFH8GAAIUAAMJjg6KDwCIAAAUAAMJjg6KDwCIAAAuAAQKfyIAAhQACAl4GCIRACoCABQACAl4GCIRACoCAAAA.Celys:BAAALgAECgUJBgAAAA==.Cerealkillah:BAAALgAECgEJAQAAAA==.',
Ch='Chantilly:BAAALgAECgYJDwAAAA==.Chartreuse:BAAALgADCgMJBAABLgAECgUJCAAFAAAAAA==.Chaw:BAAALgAECgEJAQAAAA==.Cheesecurds:BAAALgADCgcJBwAAAA==.Cheesied:BAAALgADCgQJAwAAAA==.Chios:BAABLgAFFH8OAAIIAAUJSQ4sCQA2AQAIAAUJSQ4sCQA2AQABLgAFFAcJJgASAOQdAA==.Choonzaddy:BAAALgAECgUJBQAAAA==.',
Cl='Cleetiscat:BAAALgAECgYJBgAAAA==.',
Co='Cowabunga:BAAALgADCgEJAQAAAA==.',
Cr='Crow:BAAALgAFFAgJFgAAAQ==.Cryoblade:BAAALgADCgcJDAAAAA==.',
Cu='Curasombras:BAAALgAECgMJAwAAAA==.Cuttanee:BAAALgAECggJDAAAAA==.',
Cy='Cybrpnkbunny:BAAALgAECgUJCAAAAA==.Cyntrx:BAAALgAECgEJAgAAAA==.Cyril:BAAALgADCgkJFwAAAA==.',
Da='Daevon:BAAALgAECgQJEAAAAA==.Daron:BAAALgAECgcJDgABLgAECgcJEQAFAAAAAA==.Darrowreaper:BAABLgAECn8eAAIOAAgJzQ3heAByAQAOAAgJzQ3heAByAQAAAA==.',
De='Deadcell:BAAALgAECgYJBwAAAA==.Deatheria:BAAALgADCgMJAwAAAA==.Deathstar:BAAALgAECgUJBQAAAA==.Denamage:BAAALgAFFAEJAQAAAA==.Denarrage:BAACLgAFFH8WAAIVAAcJvggyDgA0AQAVAAcJvggyDgA0AQAuAAQKfy4AAhUACQnuFK4VAN8BABUACQnuFK4VAN8BAAAA.Denawage:BAAALgAECggJCAAAAA==.',
Dh='Dhigga:BAAALgAECgYJBgAAAA==.',
Di='Dirtytotem:BAACLgAFFH8HAAIMAAMJKhc4BgDrAAAMAAMJKhc4BgDrAAAuAAQKfxwAAgwACAnWGs0IADQCAAwACAnWGs0IADQCAAAA.Discordia:BAAALgAECggJDQAAAA==.Disprop:BAAALgAECgEJAQAAAA==.Dizyizy:BAAALgAECgUJBwAAAA==.',
Dk='Dkigga:BAAALgAECgcJBgAAAA==.',
Do='Doingmost:BAAALgAECgYJCgAAAA==.Dontnerfspls:BAAALgAECgQJBgABLgAFFAQJHAAOAOscAA==.Doomby:BAABLgAECn8ZAAIWAAgJnRJoUACxAQAWAAgJnRJoUACxAQABLgAECgkJOQAVADQbAA==.',
Dr='Drakesh:BAAALgADCgEJAQAAAA==.Drakussy:BAABLgAECn8XAAIJAAkJZQkpCwBmAQAJAAkJZQkpCwBmAQABLgAECgkJOQAVADQbAA==.Drudekay:BAAALgAECgEJAQAAAA==.Druigga:BAAALgAECgUJBgAAAA==.',
Du='Dullslinkie:BAAALgADCgEJAQAAAA==.',
Ei='Eichmann:BAAALgAECgUJBQAAAA==.',
El='Eldarborn:BAAALgAECgUJBQAAAA==.Eldruida:BAAALgAECgIJAwAAAA==.Eleannar:BAAALgAECgEJAQAAAA==.Elficpaladin:BAAALgAECgYJCgAAAA==.Elixxi:BAAALgAECgUJDQAAAA==.Elladin:BAAALgADCgcJBwAAAA==.Ellipsi:BAAALgAECgcJDQAAAA==.Ellipsoro:BAACLgAFFH8LAAIOAAMJix5jjgDuAAAOAAMJix5jjgDuAAAuAAQKfy8AAg4ACQl4JdwJACEDAA4ACQl4JdwJACEDAAAA.Eltrol:BAACLgAFFH8WAAIWAAQJtAv/TAASAQAWAAQJtAv/TAASAQAuAAQKfxkAAhYACQmfFd8oADsCABYACQmfFd8oADsCAAAA.Eluriana:BAAALgAECgYJCAABLgAFFAYJGwAIAGYSAA==.',
Eq='Eques:BAABLgAFFH8FAAIOAAMJaBnuNgDsAAAOAAMJaBnuNgDsAAAAAA==.',
Er='Erale:BAAALgADCgYJDAAAAA==.Eredarn:BAAALgADCgEJAQAAAA==.Erienor:BAAALgADCgkJDAAAAA==.',
Ev='Evldrprkchop:BAAALgADCgIJAgAAAA==.',
Ex='Executiepie:BAACLgAFFH8mAAISAAcJ5B1iAQDbAQASAAcJ5B1iAQDbAQAuAAQKfysAAhIACQmTJQEBAF4DABIACQmTJQEBAF4DAAAA.Exodia:BAAALgAECgYJBgAAAA==.',
Fa='Faeris:BAACLgAFFH8NAAMXAAUJShscGgCWAQAXAAUJShscGgCWAQAYAAEJMQ2qEgBPAAAuAAQKfyIAAxgACQkkItMBAFkDABgACQkkItMBAFkDABcAAgnfGodFAI0AAAAA.Faolain:BAABLgAECn8kAAICAAgJQBENRwB0AQACAAgJQBENRwB0AQAAAA==.Farmtorito:BAAALgAECgEJBAABLgAFFAgJGQAZAHweAA==.Fatalis:BAACLgAFFH84AAIWAAcJGBB3CwDGAQAWAAcJGBB3CwDGAQAuAAQKfywAAxYACQkLHBwbAIMCABYACQkLHBwbAIMCAAMACAlcBLJRAAYBAAAA.Faylin:BAAALgADCgkJJAAAAA==.',
Fi='Fiddlestix:BAAALgAECgUJCgAAAA==.Fims:BAAALgAECgYJCgAAAA==.Finarfin:BAAALgADCgkJCQAAAA==.Fireballcat:BAAALgAECgIJAgAAAA==.Fizaw:BAACLgAFFH8RAAIaAAQJvgM6KQByAAAaAAQJvgM6KQByAAAuAAQKf0gAAhoACQl5CVhNADgBABoACQl5CVhNADgBAAAA.',
Fl='Floydbussy:BAABLgAFFH8SAAIbAAcJghJxDABzAQAbAAcJghJxDABzAQAAAA==.',
Fr='Freeng:BAAALgAECgEJAQAAAA==.Freeze:BAAALgAECgEJAQAAAA==.Freyya:BAAALgAECgkJDAAAAA==.Frøzen:BAAALgAECgQJAgAAAA==.',
Fu='Fuzzydots:BAAALgAECgMJBgAAAA==.',
['Fë']='Fëanør:BAABLgAECn8XAAIBAAgJ7RO0ZgCzAQABAAgJ7RO0ZgCzAQAAAA==.',
Ga='Galana:BAAALgAECgIJAgAAAA==.Galnir:BAAALgAECgMJAwAAAA==.Gan:BAAALgAECgEJAQABLgAECgUJBQAFAAAAAA==.Gatorbait:BAAALgAECgQJBAAAAA==.Gaurr:BAAALgAECgMJBgAAAA==.Gazzcool:BAAALgAECgkJBwAAAA==.',
Ge='Genevah:BAAALgADCgEJAgAAAA==.Geneviere:BAAALgAECgYJCwAAAA==.Gex:BAABLgAECn8VAAIbAAkJSAp6NABhAQAbAAkJSAp6NABhAQAAAA==.',
Gh='Ghostzen:BAACLgAFFH8IAAIcAAMJXBpsIwDHAAAcAAMJXBpsIwDHAAAuAAQKfx0AAhwACQlUJQgBALsDABwACQlUJQgBALsDAAAA.',
Gi='Gianna:BAAALgAECgEJAQAAAA==.Gislain:BAABLgAECn8eAAMNAAgJUBHROgCWAQANAAgJUBHROgCWAQAdAAYJ3gzpVwDcAAAAAA==.',
Gn='Gnarladin:BAAALgAECgUJCQAAAA==.',
Go='Goldeye:BAAALgADCgMJAwAAAA==.Gooichi:BAAALgAECgEJAgAAAA==.Gothmogsbane:BAABLgAECn8WAAMCAAgJdBHMVgA1AQACAAYJzRHMVgA1AQAeAAgJKwTEUgDcAAAAAA==.',
Gr='Greaves:BAAALgAECgQJBAABLgAFFAgJIQAfAFQiAA==.Greyspirit:BAACLgAFFH8VAAIQAAQJgRxqBgAkAQAQAAQJgRxqBgAkAQAuAAQKfz0AAhAACQmFIwICACkDABAACQmFIwICACkDAAAA.Grez:BAAALgAECgQJBgAAAA==.Grubnub:BAAALgADCgEJAQABLgAECgkJOwANAAQdAA==.',
Gu='Gumpy:BAAALgAECggJDAAAAA==.',
Ha='Hador:BAAALgAECgUJCAAAAA==.Halcoldrek:BAAALgAECgMJAwAAAA==.Hamburguesa:BAAALgAECgMJBAAAAA==.Hanta:BAAALgADCgIJAwAAAA==.Harkiel:BAAALgAECgUJBwAAAA==.Haumea:BAAALgAECgMJAwAAAA==.',
Hb='Hbc:BAABLgAFFH8YAAIQAAYJLiF7AQAuAgAQAAYJLiF7AQAuAgABLgAFFAcJJgASAOQdAA==.',
He='Heffer:BAAALgAECgEJAgABLgAFFAMJBQAPANYMAA==.Heyz:BAABLgAECn8jAAMXAAgJKRweEQBhAgAXAAgJKRweEQBhAgAYAAEJkwCligAhAAAAAA==.',
Hi='Hibernate:BAAALgADCgIJAgAAAA==.Himbo:BAABLgAECn8VAAIWAAkJoAuQUwCoAQAWAAkJoAuQUwCoAQAAAA==.Hipocrit:BAAALgAECgcJCQAAAA==.',
Ho='Hog:BAAALgAECgYJBwAAAA==.Hogs:BAABLgAFFH8FAAIPAAMJ1gy4CwDGAAAPAAMJ1gy4CwDGAAAAAA==.Holypoopp:BAACLgAFFH8XAAIKAAQJYRxADAAYAQAKAAQJYRxADAAYAQAuAAQKf1AABAEACQlCIKsSANMCAAEACQlCIKsSANMCAAoABwksGYE4AGsBAAsACQmvDOgYAFQBAAAA.Holyreturn:BAAALgAECgUJBQAAAA==.Holyshock:BAAALgAECgYJCAAAAA==.Hondalorian:BAABLgAECn89AAIWAAkJ7BYZKAA+AgAWAAkJ7BYZKAA+AgAAAA==.Honkmydemon:BAAALgADCgMJAwAAAA==.Honkmyscars:BAAALgAECgEJAQAAAA==.Hordranir:BAAALgADCgIJAgAAAA==.',
Hu='Hulksgrnsack:BAAALgAECgcJEwAAAA==.Huntigga:BAAALgAECgkJCwAAAA==.',
['Hë']='Hëxy:BAAALgADCgYJBgAAAA==.',
Ih='Ihatemeta:BAAALgAFFAIJBAAAAA==.',
Il='Illidaldin:BAAALgADCgcJBwABLgAECgkJKwAgAJkZAA==.',
Im='Imran:BAACLgAFFH8kAAILAAQJGxbtAwDqAAALAAQJGxbtAwDqAAAuAAQKf24AAwsACQngHowEALMCAAsACQngHowEALMCAAEABwmhBKXPAOoAAAAA.',
In='Inkdawarlock:BAAALgAECgEJAQAAAA==.Innit:BAAALgAECgEJAQABLgAFFAMJBQAPANYMAA==.Inphyy:BAAALgAECgYJEAAAAA==.Inthelayer:BAAALgAFFAEJAgABLgAFFAMJBQAPANYMAA==.',
['Iå']='Iåomai:BAAALgADCgMJAwAAAA==.',
Ja='Jabronee:BAABLgAECn8cAAITAAYJUBsaNwBrAQATAAYJUBsaNwBrAQAAAA==.',
Je='Jerikoh:BAAALgAECgEJBQAAAA==.Jershdahunta:BAAALgADCgkJDgABLgAECggJDQAFAAAAAA==.Jether:BAABLgAECn8kAAIBAAcJrA0XFgD4AAABAAcJrA0XFgD4AAAAAA==.',
Jk='Jkingoreborn:BAABLgAECn8gAAILAAcJjyHmCQAvAgALAAcJjyHmCQAvAgABLgAECggJIwAWAJQXAA==.',
Jo='Jodormi:BAAALgADCgkJCQABLgAECgkJHQAgAM0YAA==.Jodrin:BAAALgADCgEJAQAAAA==.Jojobaggins:BAABLgAECn8aAAQhAAcJPhpjDQBTAQAEAAUJeRdkMQB8AQAhAAcJFhdjDQBTAQAiAAQJLBpTBwAwAQAAAA==.Jopine:BAAALgAECgEJAQABLgAECgkJHQAgAM0YAA==.',
Ka='Kaadriluna:BAAALgADCggJDQAAAA==.Kaena:BAAALgADCgYJBgAAAA==.Kaey:BAAALgAECgQJBAAAAA==.Karach:BAAALgAECgIJAgAAAA==.Katalyst:BAAALgAECgIJAgAAAA==.',
Ke='Keiri:BAAALgADCgMJAwAAAA==.Keyholes:BAABLgAFFH8eAAIjAAYJ5BnnEgBeAQAjAAYJ5BnnEgBeAQABLgAFFAcJJgASAOQdAA==.Keyohs:BAAALgAECgUJBQABLgAFFAcJJgASAOQdAA==.',
Kh='Khe:BAAALgAECgcJCQABLgAECgkJOwANAAQdAA==.',
Ki='Kittybear:BAAALgAFFAEJAQABLgAFFAkJJAASAJ8fAA==.',
Kk='Kkoda:BAAALgAECgYJDQAAAA==.',
Ko='Koal:BAABLgAECn8hAAIWAAgJuhg7SADJAQAWAAgJuhg7SADJAQAAAA==.Kodabear:BAAALgADCgcJBwAAAA==.',
Kp='Kpop:BAAALgADCgcJBwABLgAFFAkJUQAWADQmAA==.',
Kr='Kreen:BAAALgADCgcJBwAAAA==.Krom:BAABLgAECn8aAAMBAAcJEgUVMwBkAAABAAcJEgUVMwBkAAALAAEJGABWUAADAAABLgAECggJMgANAD4QAA==.Kronos:BAAALgAECgcJBwABLgAECgYJCgAFAAAAAA==.',
Ku='Kuroneko:BAAALgAFFAIJAwAAAA==.Kushage:BAAALgAECgEJAQAAAA==.',
Ky='Kyomu:BAAALgADCgMJAwAAAA==.Kyracia:BAAALgAECgkJCQAAAA==.',
La='Lara:BAABLgAECn8iAAMWAAgJhg95aAByAQAWAAgJhg95aAByAQADAAYJ/goTSwAmAQAAAA==.Lavaa:BAAALgADCgEJAQAAAA==.',
Le='Leibniz:BAAALgADCgMJAwAAAA==.Lesgoth:BAAALgAECgcJCQAAAA==.Lettussy:BAABLgAFFH8TAAQEAAUJPCGHDADLAQAEAAUJPCGHDADLAQAiAAQJCgd2CAD4AAAhAAEJRwpvEwA8AAABLgAFFAgJHwAGAPYYAA==.Ley:BAAALgAECgUJBgAAAA==.Leya:BAAALgAECgIJAgAAAA==.',
Li='Lightsbelow:BAAALgADCgYJCAAAAA==.Lix:BAACLgAFFH8IAAICAAMJGAlLHAB/AAACAAMJGAlLHAB/AAAuAAQKfykAAgIACQnsES8wAOEBAAIACQnsES8wAOEBAAAA.Lixxi:BAAALgAECgYJCwABLgAFFAMJCAACABgJAA==.',
Lo='Loreleì:BAAALgADCgMJAwAAAA==.Louis:BAAALgAECgEJAQAAAA==.',
Lu='Luffymd:BAAALgAECgQJBwAAAA==.Luminyssa:BAAALgAECgYJBwAAAA==.',
['Lú']='Lúthien:BAABLgAECn80AAIaAAkJ5iKsBwAiAwAaAAkJ5iKsBwAiAwAAAA==.',
Ma='Madoka:BAAALgAECgYJDwAAAA==.Makari:BAAALgADCgMJAwAAAA==.Marditoloko:BAAALgAECgQJBAAAAA==.Matrix:BAAALgAECgcJDQAAAA==.Mavenn:BAAALgAECgEJAQAAAA==.Maxchungus:BAABLgAECn81AAMOAAkJ8yFeGwCjAgAOAAkJ8yFeGwCjAgAjAAYJPQ8WJAAgAQAAAA==.',
Me='Meatsuit:BAAALgAECgIJAgAAAA==.Meeoowzer:BAAALgAECgQJBgAAAA==.Meigetsuki:BAAALgADCgQJBAABLgAECgUJBQAFAAAAAA==.Meloo:BAABLgAECn85AAMVAAkJNBv2CgB4AgAVAAkJNBv2CgB4AgAkAAYJ2Aa+vgCvAAAAAA==.Meteor:BAAALgADCgUJBQAAAA==.',
Mi='Mightguy:BAAALgAECgEJAQAAAA==.Mikehawncho:BAAALgAECgQJBwABLgAECgcJHgAOAFUbAA==.Mizu:BAAALgAECgMJAwAAAA==.',
Mo='Moknahddon:BAAALgADCgQJBAAAAA==.Moment:BAABLgAECn8iAAIJAAkJNxrWAwBMAgAJAAkJNxrWAwBMAgAAAA==.Mookyblaylok:BAAALgAECgMJAwABLgAECgkJUwAEAMQjAA==.Morthrisia:BAAALgADCgUJBQABLgAECgEJAQAFAAAAAA==.',
Mu='Muhjo:BAAALgAECgIJAgAAAA==.Muna:BAAALgAECgEJAQAAAA==.Murraneth:BAAALgAECgEJAQAAAA==.Murrmau:BAABLgAECn8aAAIWAAYJ2wnangAEAQAWAAYJ2wnangAEAQAAAA==.Muufarmer:BAAALgADCggJCAAAAA==.',
My='Mydude:BAAALgAECgcJEwAAAA==.',
Na='Naerys:BAAALgAECggJDQAAAA==.Nalguilidan:BAAALgADCgYJBgAAAA==.Natedk:BAAALgAECgIJAwAAAA==.Natmau:BAAALgADCgQJBAAAAA==.Naughtyelf:BAAALgAECgYJCAAAAA==.',
Ne='Nemene:BAAALgADCgEJAQAAAA==.Neyt:BAABLgAECn8pAAMkAAkJKBt1IABSAgAkAAkJKBt1IABSAgAVAAEJiRURcAA1AAAAAA==.',
Ni='Niddalee:BAAALgAECgcJEQAAAA==.Nioh:BAAALgAECgYJDwAAAA==.Niohscuck:BAAALgADCgEJAQAAAA==.Nitesrider:BAAALgAECgQJCAAAAA==.',
No='Nora:BAACLgAFFH9cAAIBAAkJCCYxAAB5AwABAAkJCCYxAAB5AwAuAAQKf0gAAwEACQnbJnMAAJcDAAEACQnbJnMAAJcDAAoAAwktFtBcAMIAAAAA.Nori:BAAALgADCgkJDgABLgAFFAkJOwAGAAslAA==.Noshikoshi:BAAALgAECgIJAwAAAA==.Nostrodom:BAABLgAECn8aAAICAAkJWRBaBACpAQACAAkJWRBaBACpAQAAAA==.',
Nu='Nubbs:BAACLgAFFH8GAAIcAAIJiht5DwCiAAAcAAIJiht5DwCiAAAuAAQKfx8AAhwACQkLHzgHANYCABwACQkLHzgHANYCAAAA.Nubkillaa:BAABLgAECn8VAAITAAcJihluAwDFAQATAAcJihluAwDFAQAAAA==.',
Ny='Nyissa:BAAALgAECgMJAwAAAA==.Nyonà:BAAALgADCgQJBAAAAA==.',
Oc='Octas:BAAALgAECgMJAwABLgAFFAYJGwAIAGYSAA==.',
Of='Offen:BAAALgAECgIJAgAAAA==.',
Og='Ogmonkas:BAAALgAECgEJAgAAAA==.',
On='On:BAAALgAECgUJCAAAAA==.Onlyinusa:BAACLgAFFH8OAAIQAAQJDyOuAwB+AQAQAAQJDyOuAwB+AQAuAAQKfzMAAhAACQnHJHsBAEIDABAACQnHJHsBAEIDAAAA.Onyxnate:BAAALgADCgkJJQAAAA==.',
Op='Opalith:BAAALgAECgIJAgABLgAECgMJAwAFAAAAAA==.Opel:BAAALgAECgIJAgABLgAFFAUJJgAcAKsTAA==.Opi:BAAALgADCgcJBwAAAA==.',
Or='Orbyn:BAAALgADCgEJAQAAAA==.Ortah:BAAALgADCgEJAQAAAA==.',
Ox='Oxyrania:BAAALgADCgEJAQAAAA==.',
Pa='Paladigga:BAAALgAECgkJEAAAAA==.Pandalorenzo:BAAALgAECgEJAQAAAA==.Pandunka:BAAALgAECgEJAQAAAA==.',
Pf='Pfhor:BAAALgAECgYJBgAAAA==.',
Ph='Phillyshiho:BAAALgAECgcJEwABLgAECgkJIQAlAPEQAA==.',
Pi='Pinkdefender:BAAALgAECggJEAABLgAFFAQJHAAOAOscAA==.',
Po='Pokeumon:BAAALgADCgEJAQAAAA==.Poor:BAAALgAECgMJBwAAAA==.Poosistrox:BAACLgAFFH8cAAQOAAQJ6xxQRgBnAQAOAAQJ6xxQRgBnAQAmAAMJhA6yFwDNAAAjAAEJkAW9PwAyAAAuAAQKfyIAAw4ACAkoHrUvAHkCAA4ACAkoHrUvAHkCACMABAkiDBw3AIkAAAAA.Pornelius:BAAALgAECgcJCwABLgAECgkJMgARAG0eAA==.Posh:BAAALgAECgYJCgABLgAFFAMJCAACABgJAA==.Potumkin:BAAALgADCgQJBgAAAA==.',
Pt='Ptheve:BAACLgAFFH9iAAMVAAkJ1yYDAACfAwAVAAkJ1yYDAACfAwAkAAgJACHbAACgAgAuAAQKfykAAyQACQmvJXcBAMgDACQACQmoJXcBAMgDABUABwmNJKoUACsCAAAA.',
Pu='Pump:BAAALgADCgEJAQAAAA==.Putang:BAAALgAECgEJAQAAAA==.',
['På']='Pållås:BAAALgADCgMJAwAAAA==.',
Qn='Qnyx:BAABLgAECn8nAAIlAAcJfRKzMgBPAQAlAAcJfRKzMgBPAQAAAA==.',
Ra='Raelindra:BAABLgAECn8dAAIgAAkJzRixBQAQAgAgAAkJzRixBQAQAgAAAA==.Rahnarmight:BAAALgADCgQJBAAAAA==.Rayalla:BAAALgADCgUJBQAAAA==.Raygor:BAAALgAECgkJEQAAAA==.',
Re='Rebuke:BAABLgAECn8gAAIBAAgJjBlZPAATAgABAAgJjBlZPAATAgAAAA==.Renewal:BAAALgAECgUJBgAAAA==.',
Ro='Rookorblood:BAABLgAECn8bAAITAAYJWwbmYwDKAAATAAYJWwbmYwDKAAAAAA==.Rosewalker:BAACLgAFFH8eAAIIAAcJwyM4CAAMAgAIAAcJwyM4CAAMAgAuAAQKf0EAAwgACQk9JToCAD4DAAgACQk9JToCAD4DABwACQnrHjkHANYCAAAA.Rosewall:BAAALgAECgQJBQABLgAFFAcJHgAIAMMjAA==.Rottgut:BAAALgAECgYJDQAAAA==.',
Ru='Rustyjux:BAAALgAECgIJAwAAAA==.',
Ry='Ryachun:BAAALgADCgMJAwAAAA==.Rykò:BAACLgAFFH8MAAIWAAMJbh/mKQDmAAAWAAMJbh/mKQDmAAAuAAQKf0gABBYACQkLJWkEAEoDABYACQkLJWkEAEoDAA8ABgkaB9w7AOEAAAMABQnsEDdeAMgAAAAA.',
Sa='Saintslapaho:BAAALgAECgEJAQAAAA==.Salchaos:BAABLgAECn8eAAQRAAgJCRZ5DwCkAQATAAcJiRZPMgDjAQARAAcJ2xR5DwCkAQASAAQJMxAiLgDRAAAAAA==.Samsmith:BAAALgAECgYJBgAAAA==.Sanel:BAAALgADCgcJBwAAAA==.Sassy:BAAALgAFFAMJAwAAAA==.Savork:BAABLgAECn8jAAMWAAgJlBcvOQD5AQAWAAgJlBcvOQD5AQADAAYJog6wRgA6AQAAAA==.Sayafaed:BAACLgAFFH8SAAIkAAQJWgXnMwCSAAAkAAQJWgXnMwCSAAAuAAQKfy0AAiQACQmNDvJNAJwBACQACQmNDvJNAJwBAAAA.Sayamese:BAAALgAECggJEwAAAA==.',
Sc='Scatback:BAABLgAECn86AAQXAAkJeRj3FgAfAgAXAAkJPBL3FgAfAgAYAAgJQxkyGgD5AQAlAAMJvQlqhwAyAAAAAA==.Schwarzmagic:BAAALgAECgYJBgAAAA==.Schwiddylock:BAAALgAECgUJCgAAAA==.Scud:BAABLgAECn8fAAIlAAkJMw2tLwBgAQAlAAkJMw2tLwBgAQAAAA==.Scáthach:BAAALgAECgEJAQAAAA==.',
Se='Seint:BAAALgADCgYJBgAAAA==.Senuna:BAAALgADCgIJAQAAAA==.Seraphae:BAAALgADCgMJAwAAAA==.Seraphnite:BAAALgAECgQJBAAAAA==.',
Sh='Shadowdaddy:BAABLgAECn8hAAIlAAkJ8RDtIgCxAQAlAAkJ8RDtIgCxAQAAAA==.Shadyshifts:BAABLgAFFH8FAAIQAAMJbAt8JQCFAAAQAAMJbAt8JQCFAAABLgAFFAQJHAAOAOscAA==.Shadôwhunt:BAABLgAECn8fAAIOAAgJchWAXQDaAQAOAAgJchWAXQDaAQAAAA==.Shamigga:BAAALgAECgUJBQAAAA==.Shenlon:BAACLgAFFH8rAAMJAAYJQyGEAQCWAQAbAAYJLx0PFgC9AQAJAAUJISaEAQCWAQAuAAQKfy4ABAkACQm+JJMAAI0DAAkACQmPIZMAAI0DABQABQlvHZETAJEBABsABAmKI9AlAI8BAAAA.Shilor:BAABLgAECn8vAAIXAAkJzBfAAwDQAQAXAAkJzBfAAwDQAQAAAA==.Shogun:BAABLgAECn8XAAIVAAkJERPUHgCEAQAVAAkJERPUHgCEAQAAAA==.Shulamite:BAAALgADCgYJBgAAAA==.Shuye:BAAALgAECgQJBQAAAA==.',
Si='Sicarii:BAAALgAECgEJAwABLgAECgcJDgAFAAAAAA==.Sicarrious:BAAALgAECgcJDgAAAA==.Sinaliska:BAAALgADCgQJBAAAAA==.Sinistr:BAABLgAECn8WAAMNAAcJChyjJwDyAQANAAcJChyjJwDyAQAMAAQJIAUfIgCyAAAAAA==.',
Sk='Skyarc:BAAALgAECgUJBwAAAA==.Skyrun:BAAALgAECgMJBAABLgAECgUJBwAFAAAAAA==.',
Sm='Smiffbrew:BAAALgADCgMJBAAAAA==.Smiffury:BAAALgAECgYJCQAAAA==.',
Sn='Snicks:BAAALgAECgIJAgAAAA==.',
Sq='Squishyshoe:BAAALgAECgEJAQAAAA==.',
St='Stinkythebum:BAABLgAECn8bAAIcAAgJVBo1EwAkAgAcAAgJVBo1EwAkAgAAAA==.Stoneymalone:BAABLgAFFH8GAAITAAMJ2hw4EQD9AAATAAMJ2hw4EQD9AAAAAA==.Stonksy:BAAALgAFFAEJAQABLgAFFAMJBQAPANYMAA==.Stopusingmet:BAAALgAECgYJBwAAAA==.Stélle:BAABLgAECn8uAAIDAAkJDQ+rDACYAQADAAkJDQ+rDACYAQAAAA==.',
Su='Supdude:BAACLgAFFH8GAAIEAAIJuRlrGgCWAAAEAAIJuRlrGgCWAAAuAAQKfzkAAwQACQkXI+YDAAMDAAQACQkXI+YDAAMDACIAAQlpHPYNADoAAAAA.',
Sy='Sypha:BAAALgAECgYJDgAAAA==.',
Ta='Tairnbys:BAAALgAECgMJAwAAAA==.Tanthe:BAAALgAECgEJAQAAAA==.Tazbirkloa:BAAALgAECgIJAgAAAA==.',
Te='Tebzerk:BAAALgAECgcJDgAAAA==.Tekk:BAAALgAECgcJCgAAAA==.Temptress:BAAALgADCgIJAwAAAA==.',
Th='Thatssotank:BAAALgAFFAEJAQABLgAFFAcJFAAGAMgTAA==.Thorokk:BAAALgAECgMJAwAAAA==.Thynrage:BAAALgAECgUJBgAAAA==.',
Ti='Tictac:BAAALgADCgUJBQAAAA==.Tigas:BAACLgAFFH8PAAITAAMJkCHkJwAWAQATAAMJkCHkJwAWAQAuAAQKfy4AAxMACAnQJN8KALgCABMACAnQJN8KALgCABEAAQljFnZuAEQAAAAA.',
To='Todimo:BAAALgAECgQJBQAAAA==.Tooth:BAAALgAECgEJAgAAAA==.Tor:BAAALgADCgMJAwABLgAECgcJEQAFAAAAAA==.',
Tr='Trashdragon:BAABLgAECn8xAAMJAAkJWyJzAQDiAgAJAAkJPCFzAQDiAgAbAAgJNx6yDgCKAgAAAA==.Trauma:BAAALgAECgMJAwAAAA==.',
Ty='Tygrans:BAAALgAECgMJAwAAAA==.Typhoonz:BAAALgADCgEJAQAAAA==.',
['Tö']='Töby:BAAALgAECgcJEQAAAA==.',
Ul='Ulric:BAAALgAECgQJBQAAAA==.',
Um='Umgunk:BAAALgAECgQJBQAAAA==.Ummabunbun:BAAALgAECgUJBQAAAA==.',
Un='Unorthodox:BAAALgAECgUJCAAAAA==.',
Us='Usagi:BAABLgAECn8dAAIBAAcJ9huUWADCAQABAAcJ9huUWADCAQAAAA==.',
Ut='Utsuro:BAAALgAECgMJAwABLgAECggJDAAFAAAAAA==.',
Va='Valentino:BAAALgAECgQJBAAAAA==.Vannacutt:BAABLgAECn8UAAITAAgJkgzZPABSAQATAAgJkgzZPABSAQABLgAECggJDAAFAAAAAA==.Vaz:BAAALgAECgQJBAAAAA==.',
Ve='Velzevul:BAAALgADCgcJEgAAAA==.Vermouth:BAAALgAECgUJCAAAAA==.',
Vi='Vincentx:BAAALgADCgUJCwAAAA==.',
Vv='Vvinter:BAAALgAECgEJAQAAAA==.',
Vy='Vynii:BAACLgAFFH8VAAIkAAQJewpHJgDTAAAkAAQJewpHJgDTAAAuAAQKf0AABCQACQmFGn0lADgCACQACQl5F30lADgCABUABgmCGDwmAI4BAB8AAQk0D7U1AC8AAAAA.',
Wa='Wallofstars:BAAALgAECgQJBAAAAA==.Wardamage:BAAALgADCgYJBgAAAA==.Wasabi:BAABLgAECn8WAAIUAAkJWhSUCwAgAgAUAAkJWhSUCwAgAgAAAA==.',
We='Weedcenters:BAABLgAECn8YAAMCAAcJExxaAgBAAgACAAcJExxaAgBAAgAeAAQJRQGOmwAmAAAAAA==.Weenygripper:BAABLgAECn8XAAIOAAcJnxHpkABEAQAOAAcJnxHpkABEAQABLgAFFAYJDwAGAF0gAA==.',
Wf='Wfaps:BAAALgAECgQJCAAAAA==.',
Wh='Whytho:BAAALgAECgkJDAAAAA==.',
Wo='Wonon:BAAALgAFFAEJAQAAAA==.',
Wu='Wuufi:BAAALgADCgYJBgAAAA==.',
Xa='Xaam:BAAALgAECgUJCAAAAA==.Xaida:BAACLgAFFH8wAAIaAAkJChsZAwAGAwAaAAkJChsZAwAGAwAuAAQKfxYAAwgACQl7DGElAIMBAAgACQl7DGElAIMBABoAAQmUHzyeAFwAAAAA.',
Xe='Xecutioner:BAAALgAECgYJDwAAAA==.',
Xi='Xilantaeki:BAAALgAECgQJBAAAAA==.',
Yq='Yqwegvbwefhu:BAAALgAECgMJBwAAAA==.',
Za='Zangyaku:BAABLgAECn8iAAIjAAkJrCWuAQBCAwAjAAkJrCWuAQBCAwAAAA==.Zanmetsu:BAABLgAECn8dAAMEAAcJrRyNGABDAgAEAAcJrRyNGABDAgAhAAEJjgzsHgA4AAABLgAECgkJIgAjAKwlAA==.Zarlock:BAAALgADCgYJBgAAAA==.',
Ze='Zeji:BAABLgAECn87AAMNAAkJBB1zDwDXAgANAAkJBB1zDwDXAgAdAAQJmRqISQAOAQAAAA==.Zerocool:BAABLgAECn8fAAIZAAkJBRMrQgAGAgAZAAkJBRMrQgAGAgAAAA==.',
Zu='Zuggernaut:BAAALgADCgYJBgAAAA==.Zugquavious:BAABLgAECn8UAAMRAAcJKQutNwDmAAARAAYJPAytNwDmAAASAAcJ1ghbKwDcAAABLgAFFAMJBwAMACoXAA==.Zugzug:BAAALgAECgMJAwAAAA==.',
Zy='Zyggy:BAABLgAECn8XAAIeAAgJLhLuLABxAQAeAAgJLhLuLABxAQAAAA==.',
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
