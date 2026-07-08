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

local lookup = {'Paladin-Retribution','Druid-Restoration','Hunter-Marksmanship','Rogue-Subtlety','Mage-Frost','Mage-Fire','Monk-Brewmaster','Evoker-Devastation','Paladin-Holy','Paladin-Protection','Shaman-Enhancement','Shaman-Restoration','DeathKnight-Unholy','Hunter-Survival','Warrior-Arms','Warrior-Protection','Warrior-Fury','Druid-Guardian','Evoker-Preservation','Unknown-Unknown','DemonHunter-Havoc','Hunter-BeastMastery','Priest-Discipline','Priest-Holy','Warlock-Demonology','Monk-Mistweaver','Evoker-Augmentation','Monk-Windwalker','Shaman-Elemental','Druid-Balance','DemonHunter-Vengeance','Warlock-Destruction','Rogue-Assassination','Rogue-Outlaw','DeathKnight-Blood','DemonHunter-Devourer','Priest-Shadow','DeathKnight-Frost',}
local provider = {region='US',realm='Onyxia',name='US',type='weekly',zone=46,date='2026-07-05',data={Ab='Abrams:BAABLgAECn8mAAIBAAkJZhrdBADTAQABAAkJZhrdBADTAQAAAA==.',
Ad='Addý:BAACLgAFFH8FAAICAAIJpQgDXQBhAAACAAIJpQgDXQBhAAAuAAQKfxgAAgIACQmAF4UoAA0CAAIACQmAF4UoAA0CAAAA.Advanced:BAAALgADCgQJAQAAAA==.',
Ah='Ahimsa:BAACLgAFFH8LAAIDAAQJcxWsFQAUAQADAAQJcxWsFQAUAQAuAAQKf0MAAgMACQmLIyABACoDAAMACQmLIyABACoDAAAA.',
Al='Alisonchains:BAABLgAECn9JAAIEAAgJWySIAAC/AgAEAAgJWySIAAC/AgAAAA==.Alixxia:BAAALgADCgYJBgABLgAFFAMJCAACABgJAA==.Alkyri:BAAALgAECgEJAQAAAA==.Almamun:BAAALgAECgIJBAAAAA==.Alternate:BAACLgAFFH8OAAIFAAQJjRXdVgAvAQAFAAQJjRXdVgAvAQAuAAQKf0UAAwUACQkZILUSAOoCAAUACQkZILUSAOoCAAYAAgkGGHANAJAAAAAA.',
Am='Amigo:BAAALgADCgEJAQAAAA==.Amillerbrew:BAABLgAECn8aAAIHAAgJTxaYJQDXAQAHAAgJTxaYJQDXAQAAAA==.',
An='Anayanci:BAAALgAECgQJDAAAAA==.Anesh:BAAALgAECgMJBQAAAA==.Anjuna:BAAALgAECgYJDwAAAA==.Anshee:BAAALgAECgIJAwAAAA==.Anubrin:BAAALgADCgUJBwAAAA==.',
Ap='Aphian:BAAALgAECgIJAgAAAA==.',
Ar='Arazel:BAAALgAECgEJAQABLgAECgkJJgABAGYaAA==.',
As='Ashenclaw:BAABLgAECn86AAIIAAkJHxwmBAA7AgAIAAkJHxwmBAA7AgAAAA==.',
Au='Auzatryx:BAABLgAECn8VAAIEAAcJ/AzuKwA6AQAEAAcJ/AzuKwA6AQAAAA==.',
Ba='Bagpipe:BAAALgADCgkJCQAAAA==.Bamboom:BAABLgAECn8lAAQJAAgJQhaTBAAxAQAJAAgJQhaTBAAxAQABAAEJFgLk0QEWAAAKAAEJRAHATwARAAAAAA==.Bapbap:BAAALgADCgYJBgAAAA==.',
Be='Beefstick:BAAALgAECgMJAgAAAA==.Belanik:BAAALgAECgEJBQAAAA==.Beleth:BAAALgADCgYJBgAAAA==.',
Bi='Bigblktotem:BAABLgAECn8WAAMLAAYJlAzwFwBDAQALAAYJlAzwFwBDAQAMAAMJHQQiugBZAAABLgAFFAQJGwANAOscAA==.Biggrnmonstr:BAAALgAFFAIJAwABLgAFFAQJGwANAOscAA==.Bigheffin:BAAALgAFFAEJAQABLgAFFAMJBQAOANYMAA==.Bigrabit:BAAALgAECgMJAwAAAA==.Bigslammin:BAAALgAFFAEJAQABLgAFFAMJBwALACoXAA==.Bigxthezug:BAAALgAECgQJBgABLgAFFAMJBQAOANYMAA==.Biirf:BAAALgAECgUJBgAAAA==.',
Bl='Blaine:BAAALgAECgcJEwAAAA==.Blãze:BAAALgADCgIJAgAAAA==.',
Bo='Bogdan:BAAALgADCgEJAQAAAA==.Bomi:BAAALgAECgQJCQAAAA==.Boogiebm:BAABLgAFFH8FAAIHAAUJ2AVvCwDcAAAHAAUJ2AVvCwDcAAAAAA==.Borgon:BAAALgAECgEJAgAAAA==.Bowevil:BAAALgADCgMJAwAAAA==.Boypartz:BAABLgAECn8yAAMPAAkJbR6CBQCyAgAPAAkJbR6CBQCyAgAQAAEJKwmNTQAiAAAAAA==.',
Br='Brayuh:BAAALgAECgEJAwAAAA==.Breakfast:BAAALgAECggJCwABLgAFFAMJBQAOANYMAA==.',
Bu='Bulbasaurus:BAACLgAFFH8eAAIRAAYJ8CX8CQDAAQARAAYJ8CX8CQDAAQAuAAQKfyAAAhEACQn/JHoHADEDABEACQn/JHoHADEDAAAA.Bulloney:BAAALgADCgIJAgAAAA==.Bunana:BAAALgADCgIJAgAAAA==.Burnnotice:BAAALgAECgEJAgAAAA==.Bus:BAAALgAFFAMJBAABLgAFFAkJHAASAP8jAA==.',
Ca='Cabooze:BAAALgAECgYJBwAAAA==.Cacho:BAAALgAECgQJCAAAAA==.Cañonazo:BAAALgAECgEJAQAAAA==.',
Ce='Celeres:BAABLgAECn8iAAITAAgJeBgiEQAqAgATAAgJeBgiEQAqAgAAAA==.Celys:BAAALgAECgUJBgAAAA==.Cerealkillah:BAAALgAECgEJAQAAAA==.',
Ch='Chantilly:BAAALgAECgYJDwAAAA==.Chartreuse:BAAALgADCgMJBAABLgAECgUJCAAUAAAAAA==.Chaw:BAAALgAECgEJAQAAAA==.Cheesecurds:BAAALgADCgcJBwAAAA==.Cheesied:BAAALgADCgQJAwAAAA==.Chios:BAABLgAFFH8IAAIHAAUJ8wc4CAAdAQAHAAUJ8wc4CAAdAQABLgAFFAcJIgAQALEdAA==.Choonzaddy:BAAALgAECgUJBQAAAA==.',
Cl='Cleetiscat:BAAALgAECgYJBgAAAA==.',
Co='Cowabunga:BAAALgADCgEJAQAAAA==.',
Cr='Crow:BAAALgAFFAgJFgAAAQ==.Cryoblade:BAAALgADCgcJDAAAAA==.',
Cu='Curasombras:BAAALgAECgMJAwAAAA==.Cuttanee:BAAALgAECggJDAAAAA==.',
Cy='Cybrpnkbunny:BAAALgAECgUJCAAAAA==.Cyntrx:BAAALgAECgEJAgAAAA==.Cyril:BAAALgADCgkJFwAAAA==.',
Da='Daevon:BAAALgAECgQJEAAAAA==.Daron:BAAALgAECgcJDgABLgAECgcJEQAUAAAAAA==.Darrowreaper:BAABLgAECn8eAAINAAgJzQ3heAByAQANAAgJzQ3heAByAQAAAA==.',
De='Deadcell:BAAALgAECgYJBwAAAA==.Deatheria:BAAALgADCgMJAwAAAA==.Deathstar:BAAALgAECgUJBQAAAA==.Denamage:BAAALgAECgEJAQAAAA==.Denarrage:BAACLgAFFH8WAAIVAAcJvggyDgA0AQAVAAcJvggyDgA0AQAuAAQKfy4AAhUACQnuFK4VAN8BABUACQnuFK4VAN8BAAAA.Denawage:BAAALgAECggJCAAAAA==.',
Dh='Dhigga:BAAALgAECgYJBgAAAA==.',
Di='Dirtytotem:BAACLgAFFH8HAAILAAMJKhdJBAD3AAALAAMJKhdJBAD3AAAuAAQKfxwAAgsACAnWGs0IADQCAAsACAnWGs0IADQCAAAA.Discordia:BAAALgAECggJDQAAAA==.Disprop:BAAALgAECgEJAQAAAA==.Dizyizy:BAAALgAECgUJBwAAAA==.',
Dk='Dkigga:BAAALgAECgcJBgAAAA==.',
Do='Doingmost:BAAALgAECgYJCgAAAA==.Dontnerfspls:BAAALgAECgQJBgABLgAFFAQJGwANAOscAA==.Doomby:BAABLgAECn8ZAAIWAAgJnRJoUACxAQAWAAgJnRJoUACxAQABLgAECgkJOQAVADQbAA==.',
Dr='Drakesh:BAAALgADCgEJAQAAAA==.Drakussy:BAABLgAECn8XAAIIAAkJZQkpCwBmAQAIAAkJZQkpCwBmAQABLgAECgkJOQAVADQbAA==.Drudekay:BAAALgAECgEJAQAAAA==.Druigga:BAAALgAECgUJBgAAAA==.',
Du='Dullslinkie:BAAALgADCgEJAQAAAA==.',
Ei='Eichmann:BAAALgAECgUJBQAAAA==.',
El='Eldarborn:BAAALgAECgUJBQAAAA==.Eldruida:BAAALgAECgIJAwAAAA==.Eleannar:BAAALgAECgEJAQAAAA==.Elficpaladin:BAAALgAECgYJCgAAAA==.Elixxi:BAAALgAECgUJDQAAAA==.Elladin:BAAALgADCgcJBwAAAA==.Ellipsi:BAAALgAECgcJDQAAAA==.Ellipsoro:BAACLgAFFH8LAAINAAMJix5jjgDuAAANAAMJix5jjgDuAAAuAAQKfy8AAg0ACQl4JdwJACEDAA0ACQl4JdwJACEDAAAA.Eltrol:BAACLgAFFH8WAAIWAAQJtAv/TAASAQAWAAQJtAv/TAASAQAuAAQKfxkAAhYACQmfFd8oADsCABYACQmfFd8oADsCAAAA.Eluriana:BAAALgAECgYJCAABLgAFFAYJGwAHAGYSAA==.',
Eq='Eques:BAAALgAFFAMJAwAAAA==.',
Er='Erale:BAAALgADCgYJDAAAAA==.Eredarn:BAAALgADCgEJAQAAAA==.Erienor:BAAALgADCgkJDAAAAA==.',
Ev='Evldrprkchop:BAAALgADCgIJAgAAAA==.',
Ex='Executiepie:BAACLgAFFH8iAAIQAAcJsR1iAQDbAQAQAAcJsR1iAQDbAQAuAAQKfysAAhAACQmTJQEBAF4DABAACQmTJQEBAF4DAAAA.Exodia:BAAALgAECgYJBgAAAA==.',
Fa='Faeris:BAACLgAFFH8NAAMXAAUJShscGgCWAQAXAAUJShscGgCWAQAYAAEJMQ2qEgBPAAAuAAQKfyIAAxgACQkkItMBAFkDABgACQkkItMBAFkDABcAAgnfGodFAI0AAAAA.Faolain:BAABLgAECn8kAAICAAgJQBENRwB0AQACAAgJQBENRwB0AQAAAA==.Farmtorito:BAAALgAECgEJAwABLgAFFAgJGQAZAHweAA==.Fatalis:BAACLgAFFH8xAAIWAAcJcw/yBgDXAQAWAAcJcw/yBgDXAQAuAAQKfywAAxYACQkLHBwbAIMCABYACQkLHBwbAIMCAAMACAlcBLJRAAYBAAAA.Faylin:BAAALgADCgkJGwAAAA==.',
Fe='Fetch:BAAALgAECgkJBgAAAA==.',
Fi='Fiddlestix:BAAALgAECgUJCgAAAA==.Fims:BAAALgAECgYJCgAAAA==.Finarfin:BAAALgADCgkJCQAAAA==.Fireballcat:BAAALgAECgIJAgAAAA==.Fizaw:BAACLgAFFH8NAAIaAAQJlAPbRgCJAAAaAAQJlAPbRgCJAAAuAAQKf0gAAhoACQl5CVhNADgBABoACQl5CVhNADgBAAAA.',
Fl='Floydbussy:BAABLgAFFH8SAAIbAAcJghJECACNAQAbAAcJghJECACNAQAAAA==.',
Fr='Freeng:BAAALgAECgEJAQAAAA==.Freeze:BAAALgAECgEJAQAAAA==.Freyya:BAAALgAECgkJDAAAAA==.Frostitution:BAAALgAECgYJBgAAAA==.Frøzen:BAAALgAECgQJAgAAAA==.',
Fu='Fuzzydots:BAAALgAECgMJBgAAAA==.',
['Fë']='Fëanør:BAABLgAECn8XAAIBAAgJ7RO0ZgCzAQABAAgJ7RO0ZgCzAQAAAA==.',
Ga='Galana:BAAALgAECgIJAgAAAA==.Galnir:BAAALgAECgMJAwAAAA==.Gan:BAAALgAECgEJAQABLgAECgIJBAAUAAAAAA==.Gatorbait:BAAALgAECgQJBAAAAA==.Gaurr:BAAALgAECgMJBgAAAA==.Gazzcool:BAAALgAECgkJBwAAAA==.',
Ge='Genevah:BAAALgADCgEJAQAAAA==.Geneviere:BAAALgAECgYJCAAAAA==.Gex:BAABLgAECn8VAAIbAAkJSAp6NABhAQAbAAkJSAp6NABhAQAAAA==.',
Gh='Ghostzen:BAACLgAFFH8IAAIcAAMJXBpsIwDHAAAcAAMJXBpsIwDHAAAuAAQKfx0AAhwACQlUJQgBALsDABwACQlUJQgBALsDAAAA.',
Gi='Gislain:BAABLgAECn8eAAMMAAgJUBHROgCWAQAMAAgJUBHROgCWAQAdAAYJ3gzpVwDcAAAAAA==.',
Gn='Gnarladin:BAAALgAECgUJCQAAAA==.',
Go='Goldeye:BAAALgADCgMJAwAAAA==.Gooichi:BAAALgAECgEJAgAAAA==.Gothmogsbane:BAABLgAECn8WAAMCAAgJdBHMVgA1AQACAAYJzRHMVgA1AQAeAAgJKwTEUgDcAAAAAA==.',
Gr='Greaves:BAAALgAECgQJBAABLgAFFAgJIAAfANEgAA==.Greyspirit:BAACLgAFFH8RAAISAAQJphuoCwA6AQASAAQJphuoCwA6AQAuAAQKfz0AAhIACQmFIwICACkDABIACQmFIwICACkDAAAA.Grez:BAAALgAECgQJBgAAAA==.Grubnub:BAAALgADCgEJAQABLgAECgkJOwAMAAQdAA==.',
Gu='Gumpy:BAAALgAECggJDAAAAA==.',
Ha='Hador:BAAALgAECgUJCAAAAA==.Halcoldrek:BAAALgAECgMJAwAAAA==.Hamburguesa:BAAALgAECgMJBAAAAA==.Hanta:BAAALgADCgIJAwAAAA==.Harkiel:BAAALgAECgUJBwAAAA==.Haumea:BAAALgAECgMJAwAAAA==.',
Hb='Hbc:BAABLgAFFH8YAAISAAYJLiHxAABAAgASAAYJLiHxAABAAgABLgAFFAcJIgAQALEdAA==.',
He='Heffer:BAAALgAECgEJAgABLgAFFAMJBQAOANYMAA==.Heyz:BAABLgAECn8jAAMXAAgJKRweEQBhAgAXAAgJKRweEQBhAgAYAAEJkwCligAhAAAAAA==.',
Hi='Hibernate:BAAALgADCgIJAgAAAA==.Himbo:BAABLgAECn8VAAIWAAkJoAuQUwCoAQAWAAkJoAuQUwCoAQAAAA==.Hipocrit:BAAALgAECgcJCQAAAA==.',
Ho='Hog:BAAALgAECgYJBwAAAA==.Hogs:BAABLgAFFH8FAAIOAAMJ1gz9CADSAAAOAAMJ1gz9CADSAAAAAA==.Holypoopp:BAACLgAFFH8TAAIJAAQJARsoHgAsAQAJAAQJARsoHgAsAQAuAAQKf1AABAEACQlCIKsSANMCAAEACQlCIKsSANMCAAkABwksGYE4AGsBAAoACQmvDOgYAFQBAAAA.Holyreturn:BAAALgAECgEJAQAAAA==.Holyshock:BAAALgAECgYJCAAAAA==.Hondalorian:BAABLgAECn89AAIWAAkJ7BYZKAA+AgAWAAkJ7BYZKAA+AgAAAA==.Honkmydemon:BAAALgADCgMJAwAAAA==.Honkmyscars:BAAALgAECgEJAQAAAA==.Hordranir:BAAALgADCgIJAgAAAA==.',
Hu='Hulksgrnsack:BAAALgAECgcJCwAAAA==.Huntigga:BAAALgAECgkJCwAAAA==.',
['Hë']='Hëxy:BAAALgADCgYJBgAAAA==.',
Ih='Ihatemeta:BAAALgAFFAIJBAAAAA==.',
Il='Illidaldin:BAAALgADCgcJBwABLgAECgkJKwAgAJkZAA==.',
Im='Imran:BAACLgAFFH8eAAIKAAQJuhCkAwC+AAAKAAQJuhCkAwC+AAAuAAQKf2gAAwoACQlUHYwEALMCAAoACQlUHYwEALMCAAEABwmhBKXPAOoAAAAA.',
In='Inkdawarlock:BAAALgAECgEJAQAAAA==.Innit:BAAALgAECgEJAQABLgAFFAMJBQAOANYMAA==.Inthelayer:BAAALgAFFAEJAgABLgAFFAMJBQAOANYMAA==.',
['Iå']='Iåomai:BAAALgADCgMJAwAAAA==.',
Ja='Jabronee:BAABLgAECn8cAAIRAAYJUBsaNwBrAQARAAYJUBsaNwBrAQAAAA==.',
Je='Jerikoh:BAAALgAECgEJBQAAAA==.Jershdahunta:BAAALgADCgkJDgABLgAECggJDQAUAAAAAA==.Jether:BAABLgAECn8gAAIBAAcJswtqEQDoAAABAAcJswtqEQDoAAAAAA==.',
Jk='Jkingoreborn:BAABLgAECn8gAAIKAAcJjyHmCQAvAgAKAAcJjyHmCQAvAgABLgAECggJIwAWAJQXAA==.',
Jo='Jodormi:BAAALgADCgkJCQABLgAECgkJHQAgAM0YAA==.Jodrin:BAAALgADCgEJAQAAAA==.Jojobaggins:BAABLgAECn8aAAQhAAcJPhpjDQBTAQAEAAUJeRdkMQB8AQAhAAcJFhdjDQBTAQAiAAQJLBpTBwAwAQAAAA==.Jopine:BAAALgAECgEJAQABLgAECgkJHQAgAM0YAA==.',
Ka='Kaadriluna:BAAALgADCggJDQAAAA==.Kaena:BAAALgADCgYJBgAAAA==.Kaey:BAAALgAECgQJBAAAAA==.Kaname:BAAALgAECgYJEAAAAA==.Karach:BAAALgAECgIJAgAAAA==.Katalyst:BAAALgAECgIJAgAAAA==.',
Ke='Keiri:BAAALgADCgMJAwAAAA==.Keyholes:BAABLgAFFH8bAAIjAAYJ5BnnEgBeAQAjAAYJ5BnnEgBeAQABLgAFFAcJIgAQALEdAA==.Keyohs:BAAALgAECgUJBQABLgAFFAcJIgAQALEdAA==.',
Kh='Khe:BAAALgAECgcJCQABLgAECgkJOwAMAAQdAA==.',
Ki='Kittybear:BAAALgAFFAEJAQABLgAFFAkJJAAQAJ8fAA==.',
Kk='Kkoda:BAAALgAECgYJDQAAAA==.',
Ko='Koal:BAABLgAECn8hAAIWAAgJuhg7SADJAQAWAAgJuhg7SADJAQAAAA==.Kodabear:BAAALgADCgcJBwAAAA==.',
Kp='Kpop:BAAALgADCgcJBwABLgAFFAkJTQAWADQmAA==.',
Kr='Kreen:BAAALgADCgcJBwAAAA==.Krom:BAABLgAECn8VAAMBAAcJsATL/AC7AAABAAcJsATL/AC7AAAKAAEJGABWUAADAAABLgAECggJMQAMAD4QAA==.Kronos:BAAALgAECgcJBwABLgAECgYJCgAUAAAAAA==.',
Ku='Kuroneko:BAAALgAFFAIJAwAAAA==.Kushage:BAAALgAECgEJAQAAAA==.',
Ky='Kyomu:BAAALgADCgMJAwAAAA==.Kyracia:BAAALgAECgkJCQAAAA==.',
La='Lara:BAABLgAECn8iAAMWAAgJhg95aAByAQAWAAgJhg95aAByAQADAAYJ/goTSwAmAQAAAA==.Lavaa:BAAALgADCgEJAQAAAA==.',
Le='Leibniz:BAAALgADCgMJAwAAAA==.Lesgoth:BAAALgAECgcJCQAAAA==.Lettussy:BAABLgAFFH8TAAQEAAUJPCGHDADLAQAEAAUJPCGHDADLAQAiAAQJCgd2CAD4AAAhAAEJRwpvEwA8AAABLgAFFAgJHwAFAPYYAA==.Ley:BAAALgAECgUJBgAAAA==.Leya:BAAALgAECgIJAgAAAA==.',
Li='Lightsbelow:BAAALgADCgYJCAAAAA==.Lix:BAACLgAFFH8IAAICAAMJGAkRFgCBAAACAAMJGAkRFgCBAAAuAAQKfykAAgIACQnsES8wAOEBAAIACQnsES8wAOEBAAAA.Lixxi:BAAALgAECgYJCQABLgAFFAMJCAACABgJAA==.',
Lo='Loliruri:BAAALgAECgYJDgAAAA==.Loreleì:BAAALgADCgMJAwAAAA==.Louis:BAAALgAECgEJAQAAAA==.',
Lu='Luffymd:BAAALgAECgQJBwAAAA==.Luminyssa:BAAALgAECgYJBwAAAA==.',
['Lú']='Lúthien:BAABLgAECn80AAIaAAkJ5iKsBwAiAwAaAAkJ5iKsBwAiAwAAAA==.',
Ma='Madoka:BAAALgAECgYJDwAAAA==.Makari:BAAALgADCgMJAwAAAA==.Marditoloko:BAAALgAECgQJBAAAAA==.Matrix:BAAALgAECgcJDQAAAA==.Mavenn:BAAALgAECgEJAQAAAA==.Maxchungus:BAABLgAECn81AAMNAAkJ8yFeGwCjAgANAAkJ8yFeGwCjAgAjAAYJPQ8WJAAgAQAAAA==.',
Me='Meatsuit:BAAALgAECgIJAgAAAA==.Meeoowzer:BAAALgADCgcJBwAAAA==.Meigetsuki:BAAALgADCgQJBAABLgAECgIJBAAUAAAAAA==.Meloo:BAABLgAECn85AAMVAAkJNBv2CgB4AgAVAAkJNBv2CgB4AgAkAAYJ2Aa+vgCvAAAAAA==.Meteor:BAAALgADCgUJBQAAAA==.',
Mi='Mightguy:BAAALgAECgEJAQAAAA==.Mikehawncho:BAAALgAECgQJBwABLgAECgcJHgANAFUbAA==.Mizu:BAAALgAECgMJAwAAAA==.',
Mo='Moknahddon:BAAALgADCgQJBAAAAA==.Moment:BAABLgAECn8iAAIIAAkJNxrWAwBMAgAIAAkJNxrWAwBMAgAAAA==.Morthrisia:BAAALgADCgUJBQABLgAECgEJAQAUAAAAAA==.',
Mu='Muna:BAAALgAECgEJAQAAAA==.Murraneth:BAAALgAECgEJAQAAAA==.Murrmau:BAABLgAECn8aAAIWAAYJ2wnangAEAQAWAAYJ2wnangAEAQAAAA==.Muufarmer:BAAALgADCggJCAAAAA==.',
My='Mydude:BAAALgAECgcJEwAAAA==.',
Na='Naerys:BAAALgAECggJDQAAAA==.Nalguilidan:BAAALgADCgYJBgAAAA==.Natedk:BAAALgAECgIJAwAAAA==.Natmau:BAAALgADCgQJBAAAAA==.Naughtyelf:BAAALgAECgYJCAAAAA==.',
Ne='Nemene:BAAALgADCgEJAQAAAA==.Neyt:BAABLgAECn8pAAMkAAkJKBt1IABSAgAkAAkJKBt1IABSAgAVAAEJiRURcAA1AAAAAA==.',
Ni='Niddalee:BAAALgAECgcJEQAAAA==.Nioh:BAAALgAECgYJDwAAAA==.Niohscuck:BAAALgADCgEJAQAAAA==.Nitesrider:BAAALgAECgQJCAAAAA==.',
No='Nora:BAACLgAFFH9QAAIBAAkJ3iUxAAB5AwABAAkJ3iUxAAB5AwAuAAQKf0gAAwEACQnbJnMAAJcDAAEACQnbJnMAAJcDAAkAAwktFtBcAMIAAAAA.Nori:BAAALgADCgkJDgABLgAFFAkJOAAFAJIjAA==.Noshikoshi:BAAALgAECgIJAwAAAA==.Nostrodom:BAABLgAECn8ZAAICAAgJABHqAwByAQACAAgJABHqAwByAQAAAA==.',
Nu='Nubbs:BAABLgAECn8fAAIcAAkJCx84BwDWAgAcAAkJCx84BwDWAgAAAA==.Nubkillaa:BAAALgAECgYJDgAAAA==.',
Ny='Nyissa:BAAALgAECgMJAwAAAA==.Nyonà:BAAALgADCgQJBAAAAA==.',
Oc='Octas:BAAALgAECgMJAwABLgAFFAYJGwAHAGYSAA==.',
Of='Offen:BAAALgAECgIJAgAAAA==.',
Og='Ogmonkas:BAAALgAECgEJAgAAAA==.',
On='On:BAAALgAECgUJCAAAAA==.Onlyinusa:BAACLgAFFH8LAAISAAQJDyNtAgCKAQASAAQJDyNtAgCKAQAuAAQKfzMAAhIACQnHJHsBAEIDABIACQnHJHsBAEIDAAAA.Onyxnate:BAAALgADCgkJJQAAAA==.',
Op='Opalith:BAAALgAECgIJAgABLgAECgMJAwAUAAAAAA==.Opel:BAAALgAECgIJAgABLgAFFAUJJgAcAKsTAA==.Opi:BAAALgADCgcJBwAAAA==.',
Or='Orbyn:BAAALgADCgEJAQAAAA==.Ortah:BAAALgADCgEJAQAAAA==.',
Ox='Oxyrania:BAAALgADCgEJAQAAAA==.',
Pa='Paladigga:BAAALgAECgkJEAAAAA==.Pandalorenzo:BAAALgAECgEJAQAAAA==.Pandunka:BAAALgAECgEJAQAAAA==.',
Pf='Pfhor:BAAALgAECgYJBgAAAA==.',
Ph='Phillyshiho:BAAALgAECgcJEwABLgAECgkJIQAlAPEQAA==.',
Pi='Pinkdefender:BAAALgAECggJEAABLgAFFAQJGwANAOscAA==.',
Po='Pokeumon:BAAALgADCgEJAQAAAA==.Poor:BAAALgAECgMJBwAAAA==.Poosistrox:BAACLgAFFH8bAAQNAAQJ6xxQRgBnAQANAAQJ6xxQRgBnAQAmAAMJhA6yFwDNAAAjAAEJkAW9PwAyAAAuAAQKfyIAAw0ACAkGILUvAHkCAA0ACAkoHrUvAHkCACMABAlXEGAJAG0AAAAA.Pornelius:BAAALgAECgcJCwABLgAECgkJMgAPAG0eAA==.Posh:BAAALgAECgUJBQABLgAFFAMJCAACABgJAA==.Potumkin:BAAALgADCgQJBgAAAA==.',
Pt='Ptheve:BAACLgAFFH9VAAMVAAkJwiYCAAChAwAVAAkJwiYCAAChAwAkAAgJACHbAACgAgAuAAQKfykAAyQACQmvJXcBAMgDACQACQmoJXcBAMgDABUABwmNJKoUACsCAAAA.',
Pu='Pump:BAAALgADCgEJAQAAAA==.Putang:BAAALgAECgEJAQAAAA==.',
['På']='Pållås:BAAALgADCgMJAwAAAA==.',
Qn='Qnyx:BAABLgAECn8nAAIlAAcJfRKzMgBPAQAlAAcJfRKzMgBPAQAAAA==.',
Ra='Raelindra:BAABLgAECn8dAAIgAAkJzRixBQAQAgAgAAkJzRixBQAQAgAAAA==.Rahnarmight:BAAALgADCgQJBAAAAA==.Rayalla:BAAALgADCgUJBQAAAA==.Raygor:BAAALgAECgkJEQAAAA==.',
Re='Rebuke:BAABLgAECn8gAAIBAAgJjBlZPAATAgABAAgJjBlZPAATAgAAAA==.Renewal:BAAALgAECgUJBgAAAA==.',
Ro='Rookorblood:BAABLgAECn8bAAIRAAYJWwbmYwDKAAARAAYJWwbmYwDKAAAAAA==.Rosewalker:BAACLgAFFH8dAAIHAAYJbCQ4CAAMAgAHAAYJbCQ4CAAMAgAuAAQKf0EAAwcACQk9JToCAD4DAAcACQk9JToCAD4DABwACQnrHjkHANYCAAAA.Rosewall:BAAALgAECgQJBQABLgAFFAYJHQAHAGwkAA==.Rottgut:BAAALgAECgYJDQAAAA==.',
Ru='Rustyjux:BAAALgAECgIJAwAAAA==.',
Ry='Ryachun:BAAALgADCgMJAwAAAA==.Rykò:BAACLgAFFH8MAAIWAAMJbh/UHgD1AAAWAAMJbh/UHgD1AAAuAAQKf0gABBYACQkLJWkEAEoDABYACQkLJWkEAEoDAA4ABgkaB9w7AOEAAAMABQnsEDdeAMgAAAAA.',
Sa='Saintslapaho:BAAALgAECgEJAQAAAA==.Salchaos:BAABLgAECn8eAAQPAAgJCRZ5DwCkAQARAAcJiRZPMgDjAQAPAAcJ2xR5DwCkAQAQAAQJMxAiLgDRAAAAAA==.Samsmith:BAAALgAECgYJBgAAAA==.Sanel:BAAALgADCgcJBwAAAA==.Sassy:BAAALgAFFAMJAwAAAA==.Savork:BAABLgAECn8jAAMWAAgJlBcvOQD5AQAWAAgJlBcvOQD5AQADAAYJog6wRgA6AQAAAA==.Sayafaed:BAACLgAFFH8OAAIkAAQJWgXoKwCSAAAkAAQJWgXoKwCSAAAuAAQKfy0AAiQACQmNDvJNAJwBACQACQmNDvJNAJwBAAAA.Sayamese:BAAALgAECggJEwAAAA==.',
Sc='Scatback:BAABLgAECn86AAQXAAkJeRj3FgAfAgAXAAkJPBL3FgAfAgAYAAgJQxkyGgD5AQAlAAMJvQlqhwAyAAAAAA==.Schwarzmagic:BAAALgAECgYJBgAAAA==.Schwiddylock:BAAALgAECgUJCgAAAA==.Scud:BAABLgAECn8fAAIlAAkJMw2tLwBgAQAlAAkJMw2tLwBgAQAAAA==.Scáthach:BAAALgAECgEJAQAAAA==.',
Se='Seint:BAAALgADCgYJBgAAAA==.Senuna:BAAALgADCgIJAQAAAA==.Seraphae:BAAALgADCgMJAwAAAA==.Seraphnite:BAAALgAECgQJBAAAAA==.',
Sh='Shadowdaddy:BAABLgAECn8hAAIlAAkJ8RDtIgCxAQAlAAkJ8RDtIgCxAQAAAA==.Shadyshifts:BAABLgAFFH8FAAISAAMJbAt8JQCFAAASAAMJbAt8JQCFAAABLgAFFAQJGwANAOscAA==.Shadôwhunt:BAABLgAECn8fAAINAAgJchWAXQDaAQANAAgJchWAXQDaAQAAAA==.Shenlon:BAACLgAFFH8rAAMIAAYJQyGEAQCWAQAbAAYJLx0PFgC9AQAIAAUJISaEAQCWAQAuAAQKfy4ABAgACQm+JJMAAI0DAAgACQmPIZMAAI0DABMABQlvHZETAJEBABsABAmKI9AlAI8BAAAA.Shilor:BAABLgAECn8vAAIXAAkJzBd7AgDNAQAXAAkJzBd7AgDNAQAAAA==.Shogun:BAABLgAECn8XAAIVAAkJERPUHgCEAQAVAAkJERPUHgCEAQAAAA==.Shulamite:BAAALgADCgYJBgAAAA==.Shuye:BAAALgAECgQJBQAAAA==.',
Si='Sicarii:BAAALgAECgEJAQABLgAECgcJDgAUAAAAAA==.Sicarrious:BAAALgAECgcJDgAAAA==.Sinaliska:BAAALgADCgQJBAAAAA==.Sinistr:BAABLgAECn8WAAMMAAcJChyjJwDyAQAMAAcJChyjJwDyAQALAAQJIAUfIgCyAAAAAA==.',
Sk='Skyarc:BAAALgAECgUJBwAAAA==.Skyrun:BAAALgAECgMJBAABLgAECgUJBwAUAAAAAA==.',
Sm='Smiffbrew:BAAALgADCgMJBAAAAA==.Smiffury:BAAALgAECgYJCQAAAA==.',
Sn='Snicks:BAAALgAECgIJAgAAAA==.',
Sq='Squishyshoe:BAAALgAECgEJAQAAAA==.',
St='Stinkythebum:BAABLgAECn8bAAIcAAgJVBo1EwAkAgAcAAgJVBo1EwAkAgAAAA==.Stoneymalone:BAABLgAFFH8FAAIRAAMJ2hyvCwAPAQARAAMJ2hyvCwAPAQAAAA==.Stonksy:BAAALgAFFAEJAQABLgAFFAMJBQAOANYMAA==.Stopusingmet:BAAALgAECgYJBwAAAA==.Stélle:BAABLgAECn8uAAIDAAkJDQ+rDACYAQADAAkJDQ+rDACYAQAAAA==.',
Su='Supdude:BAACLgAFFH8GAAIEAAIJuRmuFACgAAAEAAIJuRmuFACgAAAuAAQKfzkAAwQACQkXI+YDAAMDAAQACQkXI+YDAAMDACIAAQlpHPYNADoAAAAA.',
Ta='Tairnbys:BAAALgAECgMJAwAAAA==.Tanthe:BAAALgAECgEJAQAAAA==.Tazbirkloa:BAAALgADCgIJAgAAAA==.',
Te='Tebzerk:BAAALgAECgcJDgAAAA==.Tekk:BAAALgAECgcJCgAAAA==.Temptress:BAAALgADCgIJAwAAAA==.',
Th='Thatssotank:BAAALgAFFAEJAQABLgAFFAYJDwAFAAQOAA==.Thorokk:BAAALgAECgMJAwAAAA==.Thynrage:BAAALgAECgUJBgAAAA==.',
Ti='Tictac:BAAALgADCgUJBQAAAA==.Tigas:BAACLgAFFH8PAAIRAAMJkCHkJwAWAQARAAMJkCHkJwAWAQAuAAQKfy4AAxEACAnQJN8KALgCABEACAnQJN8KALgCAA8AAQljFnZuAEQAAAAA.',
To='Todimo:BAAALgAECgIJAgAAAA==.Tooth:BAAALgAECgEJAgAAAA==.Tor:BAAALgADCgMJAwABLgAECgcJEQAUAAAAAA==.',
Tr='Trashdragon:BAABLgAECn8xAAMIAAkJWyJzAQDiAgAIAAkJPCFzAQDiAgAbAAgJNx6yDgCKAgAAAA==.Trauma:BAAALgAECgMJAwAAAA==.',
Ty='Tygrans:BAAALgAECgMJAwAAAA==.Typhoonz:BAAALgADCgEJAQAAAA==.',
['Tö']='Töby:BAAALgAECgcJEQAAAA==.',
Ul='Ulric:BAAALgAECgQJBQAAAA==.',
Um='Umgunk:BAAALgAECgQJBQAAAA==.Ummabunbun:BAAALgAECgUJBQAAAA==.',
Un='Unorthodox:BAAALgAECgUJCAAAAA==.',
Us='Usagi:BAABLgAECn8dAAIBAAcJ9huUWADCAQABAAcJ9huUWADCAQAAAA==.',
Ut='Utsuro:BAAALgAECgMJAwABLgAECggJDAAUAAAAAA==.',
Va='Valentino:BAAALgAECgQJBAAAAA==.Vannacutt:BAABLgAECn8UAAIRAAgJkgzZPABSAQARAAgJkgzZPABSAQABLgAECggJDAAUAAAAAA==.Vaz:BAAALgAECgQJBAAAAA==.',
Ve='Velzevul:BAAALgADCgYJDAAAAA==.Vermouth:BAAALgAECgUJCAAAAA==.',
Vi='Vincentx:BAAALgADCgUJCwAAAA==.',
Vv='Vvinter:BAAALgAECgEJAQAAAA==.',
Vy='Vynii:BAACLgAFFH8RAAIkAAQJ3AnXJgCwAAAkAAQJ3AnXJgCwAAAuAAQKf0AABCQACQmFGn0lADgCACQACQl5F30lADgCABUABgmCGDwmAI4BAB8AAQk0D7U1AC8AAAAA.',
Wa='Wallofstars:BAAALgAECgQJBAAAAA==.Wardamage:BAAALgADCgYJBgAAAA==.Wasabi:BAABLgAECn8WAAITAAkJWhSUCwAgAgATAAkJWhSUCwAgAgAAAA==.',
We='Weedcenters:BAAALgAECgUJEAAAAA==.Weenygripper:BAABLgAECn8XAAINAAcJnxHpkABEAQANAAcJnxHpkABEAQABLgAFFAYJDwAFAF0gAA==.',
Wf='Wfaps:BAAALgAECgQJCAAAAA==.',
Wh='Whytho:BAAALgAECgkJDAAAAA==.',
Wo='Wonon:BAAALgAFFAEJAQAAAA==.',
Wu='Wuufi:BAAALgADCgYJBgAAAA==.',
Xa='Xaam:BAAALgAECgUJCAAAAA==.Xaida:BAACLgAFFH8sAAIaAAkJChsZAwAGAwAaAAkJChsZAwAGAwAuAAQKfxYAAwcACQl7DGElAIMBAAcACQl7DGElAIMBABoAAQmUHzyeAFwAAAAA.',
Xe='Xecutioner:BAAALgAECgYJDwAAAA==.',
Xi='Xilantaeki:BAAALgAECgQJBAAAAA==.',
Yq='Yqwegvbwefhu:BAAALgAECgMJBwAAAA==.',
Za='Zangyaku:BAABLgAECn8iAAIjAAkJrCWuAQBCAwAjAAkJrCWuAQBCAwAAAA==.Zanmetsu:BAABLgAECn8dAAMEAAcJrRyNGABDAgAEAAcJrRyNGABDAgAhAAEJjgzsHgA4AAABLgAECgkJIgAjAKwlAA==.Zarlock:BAAALgADCgYJBgAAAA==.',
Ze='Zeji:BAABLgAECn87AAMMAAkJBB1zDwDXAgAMAAkJBB1zDwDXAgAdAAQJmRqISQAOAQAAAA==.Zerocool:BAABLgAECn8fAAIZAAkJBRMrQgAGAgAZAAkJBRMrQgAGAgAAAA==.',
Zu='Zuggernaut:BAAALgADCgYJBgAAAA==.Zugquavious:BAABLgAECn8UAAMPAAcJKQutNwDmAAAPAAYJPAytNwDmAAAQAAcJ1ghbKwDcAAABLgAFFAMJBwALACoXAA==.Zugzug:BAAALgAECgMJAwAAAA==.',
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
