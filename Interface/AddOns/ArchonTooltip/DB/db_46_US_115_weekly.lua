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

local lookup = {'Monk-Mistweaver','Priest-Discipline','Unknown-Unknown','Priest-Holy','Mage-Frost','DeathKnight-Unholy','Paladin-Retribution','Paladin-Holy','Priest-Shadow','Warrior-Fury','Monk-Windwalker','DemonHunter-Devourer','DemonHunter-Havoc','Monk-Brewmaster','Druid-Restoration','Warlock-Demonology','Druid-Balance','Shaman-Restoration','Hunter-BeastMastery','DeathKnight-Frost','Mage-Arcane','DeathKnight-Blood','Druid-Guardian','Evoker-Preservation','Druid-Feral','Evoker-Augmentation','Evoker-Devastation','Warrior-Arms','Warrior-Protection','Paladin-Protection','Hunter-Survival','Hunter-Marksmanship','Shaman-Enhancement','Shaman-Elemental','Mage-Fire','DemonHunter-Vengeance','Warlock-Affliction',}
local provider = {region='US',realm='Gundrak',name='US',type='weekly',zone=46,date='2026-07-05',data={Ad='Adelyne:BAABLgAFFH8GAAIBAAQJcxBgNwDLAAABAAQJcxBgNwDLAAABLgAFFAUJEgACABkcAA==.Adera:BAAALgAECgYJBwAAAA==.',
Af='Aff:BAAALgADCgYJBgAAAA==.',
Ag='Agony:BAAALgAECgQJBgAAAA==.',
Ah='Ahkanon:BAAALgADCgEJAQAAAA==.Ahoo:BAAALgAECgkJCgAAAA==.',
Ai='Aiden:BAAALgAECgEJAgABLgAECgIJAgADAAAAAA==.Aidendk:BAAALgADCgIJAgABLgAECgIJAgADAAAAAA==.Aidenp:BAAALgADCgIJAgABLgAECgIJAgADAAAAAA==.Air:BAAALgADCgcJBwABLgAFFAkJKAAEAFcbAA==.',
Ak='Aku:BAAALgADCgIJBAAAAA==.',
Al='Aleniastra:BAAALgAECgYJEwAAAA==.Alexyss:BAAALgAECgUJDgAAAA==.Alykard:BAABLgAECn8xAAIFAAkJwhGTTAD2AQAFAAkJwhGTTAD2AQAAAA==.',
Am='Amazing:BAAALgAFFAEJAQABLgAFFAMJBQAGAEUTAA==.Amelia:BAAALgAECgEJAQAAAA==.Amyara:BAAALgAECgUJBgAAAA==.',
An='Andronicas:BAABLgAECn8mAAMHAAkJ6hLLRQD1AQAHAAkJ6hLLRQD1AQAIAAEJogevnAAtAAAAAA==.Aneira:BAABLgAFFH8kAAIFAAQJEAtxIQANAQAFAAQJEAtxIQANAQAAAA==.',
Ap='Apexis:BAAALgADCgYJCQAAAA==.',
Ar='Ariaa:BAABLgAECn8YAAIJAAYJOxiaLQBsAQAJAAYJOxiaLQBsAQAAAA==.Arieyri:BAAALgADCgcJBwAAAA==.Artpop:BAAALgAFFAEJAQABLgAFFAcJFwABAIURAA==.',
As='Aseria:BAAALgAECgYJCAAAAA==.Ash:BAAALgADCgcJCwAAAA==.Ashvira:BAAALgAECgQJBAAAAA==.Aspect:BAAALgADCgcJDgABLgAECgEJAQADAAAAAA==.Astarael:BAABLgAECn8iAAMJAAkJShcDIgC3AQAJAAgJGhYDIgC3AQAEAAcJLQ5jUgCVAAAAAA==.',
Av='Avi:BAABLgAECn8oAAICAAkJUhVQEgBSAgACAAkJUhVQEgBSAgABLgAECgkJcQAKAHggAA==.',
Ba='Babygurl:BAACLgAFFH8FAAIIAAMJNx8HJQD5AAAIAAMJNx8HJQD5AAAuAAQKf3YAAggACQntJUwCAIkDAAgACQntJUwCAIkDAAAA.Baragas:BAAALgAECgYJDgAAAA==.Bareback:BAAALgAECgQJBAAAAA==.Barney:BAAALgADCgEJAQAAAA==.Battosaî:BAAALgAECgQJBAAAAA==.',
Be='Beeny:BAACLgAFFH9DAAIBAAkJMCRgAgAiAwABAAkJMCRgAgAiAwAuAAQKf0EAAwEACQlpI4UIAMwCAAEACQlpI4UIAMwCAAsAAQlsEBmcADMAAAAA.Belle:BAACLgAFFH8ZAAMMAAgJxBaXFAAMAgAMAAgJxBaXFAAMAgANAAEJ8Bc/DABWAAAuAAQKfy0AAwwACAnFJhIEAIgDAAwACAmFJhIEAIgDAA0ABwk+IFIOAH4CAAAA.Berat:BAAALgADCgQJBAAAAA==.Berzerker:BAAALgAECgMJAwAAAA==.',
Bg='Bgc:BAAALgADCgUJBQAAAA==.',
Bi='Binari:BAAALgAECgMJAwABLgAFFAMJBQAKACoUAA==.Binlock:BAAALgAECgQJBAABLgAFFAMJBQAKACoUAA==.',
Bl='Bl:BAAALgAECgMJAwAAAA==.Bladebear:BAABLgAECn82AAIFAAkJUxWATgDwAQAFAAkJUxWATgDwAQAAAA==.Blinkynbrain:BAAALgAECgEJAQAAAA==.',
Bo='Boose:BAAALgAECgYJBgAAAA==.Bootybreaker:BAAALgADCgcJBwAAAA==.Boxoflunch:BAAALgAECgEJAQAAAA==.',
Br='Brat:BAAALgAECgEJBAABLgAECgkJVQAEAC4VAA==.Brewingmist:BAAALgAECgUJBQABLgAFFAMJBQAGAEUTAA==.Bréwmaster:BAABLgAECn8aAAMOAAgJ2RlbFAALAgAOAAgJ2RlbFAALAgABAAYJVhGiTAA6AQABLgAECgkJIgAJAEoXAA==.',
Bu='Bubbelz:BAAALgAECgMJAwAAAA==.Bubbleez:BAAALgADCgUJBQAAAA==.Bubblôseven:BAAALgAECgEJAQAAAA==.Bucklord:BAABLgAECn8iAAMJAAgJjRkAFwAuAgAJAAgJjRkAFwAuAgAEAAEJABkIbAA6AAAAAA==.Budin:BAAALgAECggJEgAAAA==.Bullmann:BAAALgADCgQJBAAAAA==.Buttons:BAAALgAECgIJAwAAAA==.',
Ca='Cannibal:BAABLgAECn8+AAIPAAkJkxxBDwDaAgAPAAkJkxxBDwDaAgAAAA==.Caplock:BAABLgAECn8VAAIQAAYJoRFohABRAQAQAAYJoRFohABRAQAAAA==.Capri:BAABLgAECn8XAAIRAAcJ1wnNRAD5AAARAAcJ1wnNRAD5AAAAAA==.Casiopia:BAAALgAECgEJAQAAAA==.',
Ce='Cellun:BAAALgAECgUJEwAAAA==.Centipede:BAAALgAECgYJCQABLgAECgYJFwASAIAXAA==.Ceredis:BAAALgAECgUJCwAAAA==.',
Ch='Chiwolf:BAAALgAECgYJDAABLgAECgkJMgATAO4bAA==.Choomoo:BAAALgADCgcJCwABLgAFFAcJHwABALENAA==.',
Cl='Cleankarma:BAAALgADCgEJAwAAAA==.',
Co='Comet:BAAALgAECgEJAQAAAA==.Cool:BAABLgAFFH8GAAIHAAMJ1BOzbADWAAAHAAMJ1BOzbADWAAAAAA==.Corwiggs:BAAALgAECgYJDwAAAA==.',
Cr='Crikey:BAABLgAECn8cAAITAAgJBRxZJwBCAgATAAgJBRxZJwBCAgAAAA==.Crimínal:BAAALgADCgcJCwAAAA==.Cripsee:BAAALgADCgMJAwAAAA==.',
Cu='Curbie:BAAALgAECgIJAwAAAA==.',
Cv='Cvdruid:BAAALgAECgUJBQAAAA==.',
Cy='Cyndrixx:BAAALgAECgIJAwAAAA==.',
['Cô']='Cônvict:BAAALgADCgYJBgAAAA==.',
De='Deacknight:BAABLgAECn8cAAMGAAgJwRuPLgB+AgAGAAgJwRuPLgB+AgAUAAEJig2BFwAyAAABLgADCgYJBwADAAAAAA==.Deacmonk:BAAALgADCgYJBgABLgADCgYJBwADAAAAAA==.Definitely:BAACLgAFFH8XAAIFAAQJpyLrPQB2AQAFAAQJpyLrPQB2AQAuAAQKfzsAAwUACQlCJPwLABkDAAUACQlCJPwLABkDABUAAQkPICobAD8AAAAA.Deki:BAEALgAECgYJBgABLgAFFAcJGgAHAPkXAA==.Dementiaous:BAAALgAECgIJAwAAAA==.Desariana:BAABLgAECn8lAAIHAAkJcxAMZgCjAQAHAAkJcxAMZgCjAQAAAA==.',
Di='Diggitie:BAAALgAECgEJAQAAAA==.Ditto:BAABLgAFFH8ZAAIBAAYJRhhkCQCZAQABAAYJRhhkCQCZAQAAAA==.',
Do='Domtop:BAABLgAFFH8FAAMWAAMJXAEjPABFAAAWAAIJTwEjPABFAAAUAAEJdgFeLgAuAAABLgAFFAcJFwABAIURAA==.Doot:BAAALgAECgIJAgAAAA==.Dormas:BAABLgAECn8ZAAIXAAgJRRAALAAAAQAXAAgJRRAALAAAAQAAAA==.Doug:BAAALgADCgEJAQAAAA==.Doxy:BAAALgAECgcJCQAAAA==.',
Dr='Drakeon:BAABLgAECn8UAAIYAAcJ/g45FwBcAQAYAAcJ/g45FwBcAQABLgAECgkJcQAKAHggAA==.',
Ee='Eeryxx:BAAALgAECgEJAQAAAA==.',
El='Eldh:BAABLgAECn8nAAMOAAkJSBGxIwCNAQAOAAkJAw6xIwCNAQALAAEJYiSSDgBWAAAAAA==.Eleison:BAAALgADCgMJAwAAAA==.Elendrial:BAAALgAECgIJAgAAAA==.Elendril:BAAALgADCgcJFQAAAA==.Elisoly:BAACLgAFFH8FAAIIAAIJDQyEQABhAAAIAAIJDQyEQABhAAAuAAQKfzgAAggACQkiINQDAFkBAAgACQkiINQDAFkBAAAA.',
Em='Emrald:BAABLgAECn8ZAAIZAAcJzBFJBADKAAAZAAcJzBFJBADKAAAAAA==.Emridius:BAAALgAECgEJAwABLgAECggJIQAKAGMgAA==.',
En='Endlessly:BAACLgAFFH8QAAIZAAUJ3hSHCAAiAQAZAAUJ3hSHCAAiAQAuAAQKfyQAAhkACQk2I+kDAOsCABkACQk2I+kDAOsCAAAA.Enerchi:BAAALgADCgMJAwAAAA==.',
Er='Erivoker:BAAALgAECgYJDAABLgAECgYJEgADAAAAAA==.Errimage:BAAALgAECgYJEgAAAA==.Errishoot:BAAALgAECgUJCQABLgAECgYJEgADAAAAAA==.Ervinia:BAAALgADCgYJCgABLgAECgYJEwADAAAAAA==.',
Ev='Evelinar:BAAALgAECgcJDwAAAA==.Evoslex:BAABLgAECn85AAMaAAkJxCPkBAAVAwAaAAkJxCPkBAAVAwAbAAYJzx1vEwCsAQAAAA==.',
Ex='Exo:BAECLgAFFH8zAAIWAAgJ5xlNBwAVAgAWAAgJ5xlNBwAVAgAuAAQKfysAAhYACQkcItQEAOICABYACQkcItQEAOICAAAA.',
Fa='Facerolleh:BAACLgAFFH89AAMcAAkJhyCGAgCUAgAcAAkJSiCGAgCUAgAKAAQJZiGMBgCGAQAuAAQKf0YABAoACQmdJc4EAFwDAAoACAn2Jc4EAFwDABwACAl/IkEGAJsCAB0AAgmNHahJAE4AAAAA.Fatedx:BAAALgAECgYJCQAAAA==.',
Fe='Feelgoodinc:BAAALgADCgkJFAAAAA==.',
Fi='Fidah:BAAALgAECgEJAQAAAA==.Firemagemain:BAAALgADCgUJBQABLgAFFAMJBQAKACoUAA==.',
Fl='Flanann:BAAALgAECgEJAQABLgAECgMJDAADAAAAAA==.Flop:BAAALgAECgUJCQABLgAFFAUJFgAFAJIbAA==.Flora:BAAALgAECgEJAwAAAA==.',
Fr='Frostmere:BAAALgADCggJGQAAAA==.Frozenite:BAAALgAECgQJBAAAAA==.',
Fu='Fuknazum:BAAALgAECgEJAQAAAA==.Furcht:BAABLgAECn8dAAIGAAcJVBJLhQBZAQAGAAcJVBJLhQBZAQAAAA==.',
Ga='Galadar:BAAALgADCgUJBQAAAA==.',
Gh='Ghrael:BAAALgAECgMJBAAAAA==.',
Gi='Giteff:BAABLgAFFH88AAIMAAkJJSVsAABzAwAMAAkJJSVsAABzAwAAAA==.Gitèff:BAABLgAFFH81AAIMAAgJISMUAgDHAgAMAAgJISMUAgDHAgABLgAFFAkJPAAMACUlAA==.Giveroflife:BAABLgAECn8YAAMeAAcJlg5FBwCDAAAHAAYJBQcy7gDNAAAeAAYJlg5FBwCDAAAAAA==.',
Go='Gourdin:BAAALgAECgQJBQABLgAECgUJBQADAAAAAA==.',
Gr='Gramnpa:BAAALgADCgUJBQAAAA==.Grandpriest:BAAALgAECgYJEgAAAA==.Gravepriest:BAAALgAECgEJAQAAAA==.Grimtysha:BAAALgAECgYJEAAAAA==.Grimveil:BAAALgAECgYJDQAAAA==.Gromit:BAAALgAECgQJCQAAAA==.Gröuch:BAABLgAFFH8IAAIOAAQJXQo/LgDwAAAOAAQJXQo/LgDwAAAAAA==.',
Ha='Harafar:BAACLgAFFH8JAAIRAAUJuQfSMAC/AAARAAUJuQfSMAC/AAAuAAQKfx4AAxEACQnuGUgOAHcCABEACQnuGUgOAHcCAA8AAwl7B1mhAG0AAAAA.Hate:BAAALgAECgYJDQABLgAFFAgJIwAFAHkYAA==.',
He='Hellbourne:BAABLgAECn8kAAIMAAkJ8hjqKAAmAgAMAAkJ8hjqKAAmAgAAAA==.',
Hi='Himmel:BAAALgADCgcJCQAAAA==.',
Ho='Hopnhorsé:BAAALgAECgQJBQAAAA==.Hotchoq:BAABLgAFFH8KAAIFAAMJqgyxhADPAAAFAAMJqgyxhADPAAAAAA==.',
Hu='Huntchoq:BAABLgAFFH8PAAQfAAYJZgxLFwAXAQAfAAUJTg1LFwAXAQATAAMJ1woibQDJAAAgAAIJdAn4JgB0AAAAAA==.Huxley:BAAALgADCgMJAwAAAA==.',
Ik='Ikan:BAABLgAECn8cAAIIAAkJqRYlAgDRAQAIAAkJqRYlAgDRAQAAAA==.',
In='Infest:BAAALgAECgQJCAAAAA==.Inzolethys:BAAALgADCgcJBwAAAA==.',
It='Itchy:BAAALgADCgEJAgAAAA==.Itskiohte:BAABLgAECn8pAAIhAAkJVw4DEACyAQAhAAkJVw4DEACyAQAAAA==.',
Ja='Jaggernut:BAAALgADCgUJBQAAAA==.',
Ji='Jimmbo:BAAALgAECgQJBAAAAA==.',
Jo='Johnny:BAAALgAECgIJAgABLgAECgkJOQAaAMQjAA==.',
Ju='Judeau:BAAALgADCgEJAQAAAA==.',
Ka='Kaelthuzzad:BAAALgADCgEJAQAAAA==.Kaitza:BAAALgAECgYJCwAAAA==.Kalzaketh:BAABLgAECn9DAAMaAAkJbQ3dKwCOAQAaAAkJbQ3dKwCOAQAbAAMJ5QSIMwB5AAAAAA==.Kashari:BAAALgAECgYJCwABLgAECgkJfgAJABUcAA==.Katali:BAABLgAECn8VAAMHAAcJSQyvqgAnAQAHAAcJSQyvqgAnAQAIAAYJCwVlWwDIAAAAAA==.Kavothe:BAAALgAECgYJCwAAAA==.Kazo:BAAALgAFFAEJAQAAAA==.Kazuggar:BAACLgAFFH8iAAISAAYJuyKJBwBPAgASAAYJuyKJBwBPAgAuAAQKfzoAAxIACQmsJW4CAFwDABIACAmCJW4CAFwDACIABgkAFdEzAGwBAAAA.Kazzn:BAABLgAFFH8FAAIPAAQJrwgCPQC7AAAPAAQJrwgCPQC7AAAAAA==.',
Ke='Kedar:BAAALgAECgYJEQAAAA==.Keg:BAAALgAECgIJAgAAAA==.Kelabar:BAAALgADCgQJBAAAAA==.',
Ki='Kibbler:BAAALgAECgUJCAAAAA==.Kick:BAAALgADCgQJBAABLgAFFAgJIwAFAHkYAA==.Kiffs:BAAALgAECgcJCgAAAA==.Kill:BAAALgAFFAEJAgAAAA==.Killerman:BAABLgAFFH8/AAQUAAkJ8yXAAACJAgAUAAcJRiLAAACJAgAGAAYJ6iLSJQDVAQAWAAMJixhBJADMAAAAAA==.Kirâ:BAABLgAECn8UAAIKAAgJCxxqHQADAgAKAAgJCxxqHQADAgABLgAECgcJEwADAAAAAA==.',
Kr='Kregnar:BAABLgAECn8pAAIcAAkJBRwbCABzAgAcAAkJBRwbCABzAgAAAA==.Kresh:BAAALgAECgcJCwAAAA==.',
Ku='Kucabara:BAAALgAECgIJAwAAAA==.Kuraiwiggs:BAAALgADCgYJDAAAAA==.',
Kw='Kwichang:BAABLgAECn8aAAIFAAcJ9Q/2lQBNAQAFAAcJ9Q/2lQBNAQAAAA==.',
Ky='Kyndariae:BAAALgAECgcJCgAAAA==.',
['Ké']='Kélpo:BAAALgADCgMJBAAAAA==.',
La='Lasagne:BAAALgADCgMJAwAAAA==.',
Le='Leatherkink:BAABLgAFFH8GAAITAAQJTAYXUwADAQATAAQJTAYXUwADAQABLgAFFAcJFwABAIURAA==.Lesley:BAAALgAECgEJAQABLgAFFAEJAQADAAAAAA==.',
Li='Lickynose:BAABLgAECn85AAMFAAkJtCKfDwD+AgAFAAkJtCKfDwD+AgAjAAEJEiAqEABdAAAAAA==.Lips:BAAALgAECgEJAQAAAA==.',
Ls='Ls:BAABLgAECn8iAAQNAAkJaiPLCQCNAgANAAgJ3R/LCQCNAgAMAAgJnCG9MQAzAgAkAAcJYhVKDgBtAQAAAA==.',
Ly='Lythium:BAAALgAECggJDAAAAA==.',
Ma='Madarabia:BAAALgAECgYJDQAAAA==.Magnius:BAAALgAECgMJAwAAAA==.Makcik:BAAALgAECgEJAgAAAA==.Mamut:BAAALgAECgEJAQAAAA==.Mantisar:BAACLgAFFH8IAAIHAAMJ5RJobwDSAAAHAAMJ5RJobwDSAAAuAAQKfx4AAgcABwnmHvM9AA0CAAcABwnmHvM9AA0CAAAA.Mattdemonn:BAAALgAECgYJDAAAAA==.Maxsm:BAABLgAECn8XAAIiAAgJrhmSIQACAgAiAAgJrhmSIQACAgAAAA==.',
Mc='Mcnuggetliaq:BAAALgAECgEJAQAAAA==.',
Me='Melanippe:BAABLgAECn8XAAIPAAYJDxtuPQCuAQAPAAYJDxtuPQCuAQAAAA==.Meleefox:BAAALgADCgUJBQAAAA==.Melethron:BAABLgAECn9AAAMHAAkJgRwvJwBnAgAHAAkJgRwvJwBnAgAIAAIJXgEVFQAgAAAAAA==.Melioknky:BAAALgAECgYJBgAAAA==.Melista:BAAALgAECgIJAgABLgAECggJFwAlAOoDAA==.',
Mi='Michaeljfox:BAAALgAECgQJBAAAAA==.Mid:BAAALgADCgYJBgAAAA==.Mightymage:BAABLgAECn8hAAIFAAgJ4Q11hgBqAQAFAAgJ4Q11hgBqAQAAAA==.Millie:BAAALgAECgEJAQAAAA==.Millionbaby:BAAALgAECgEJAQAAAA==.Milliondruid:BAAALgAECgMJBAAAAA==.Millionsm:BAAALgADCgQJBQAAAA==.Mirrorimage:BAABLgAFFH8GAAIJAAIJSwdWMQCBAAAJAAIJSwdWMQCBAAABLgAFFAcJHAAJADITAA==.Mirrorx:BAACLgAFFH8cAAIJAAcJMhOQBQBfAQAJAAcJMhOQBQBfAQAuAAQKfzYAAgkACQlzIC0JALwCAAkACQlzIC0JALwCAAAA.Miy:BAAALgAECgEJAQAAAA==.',
Mo='Mongon:BAAALgAECgYJBgAAAA==.Moogle:BAAALgAECgIJBAAAAA==.Moomie:BAABLgAECn8iAAIPAAgJAxZQOAC1AQAPAAgJAxZQOAC1AQAAAA==.Moosfel:BAABLgAECn8jAAIZAAcJGhpfDwDAAQAZAAcJGhpfDwDAAQAAAA==.Morubine:BAAALgAECgQJBgAAAA==.',
Mt='Mtzz:BAAALgAECgUJBQAAAA==.',
Mu='Mudcake:BAAALgAECgEJAQAAAA==.',
My='Mygravebroke:BAAALgADCggJCQAAAA==.Mystdragon:BAACLgAFFH8ZAAMYAAgJJhgpDgC7AQAYAAYJ6RcpDgC7AQAaAAUJJg/ULQAMAQAuAAQKfzAAAhgACQm5IYADAA4DABgACQm5IYADAA4DAAEuAAUUCQk4AAEA/x4A.Mystweaverr:BAACLgAFFH84AAMBAAkJ/x4KBgCzAgABAAkJ/x4KBgCzAgALAAEJ9QTKRwAxAAAuAAQKfy8AAwEACQn3H4AJALkCAAEACQn3H4AJALkCAAsAAgkjIrdWALMAAAAA.',
['Mö']='Mörae:BAAALgADCgEJAQABLgAECgYJFwAPAA8bAA==.',
Na='Naddar:BAACLgAFFH8YAAIIAAUJwxm+GABdAQAIAAUJwhm+GABdAQAuAAQKf1UAAggACQkMIJ0GACIDAAgACQkMIJ0GACIDAAAA.Namadgi:BAABLgAECn8zAAIPAAkJiR1fDQDwAgAPAAkJiR1fDQDwAgAAAA==.Nathria:BAAALgAECgIJAwAAAA==.',
Ne='Netalis:BAABLgAECn8lAAIPAAgJwxTFMQDZAQAPAAgJwxTFMQDZAQAAAA==.',
Ni='Nikonii:BAAALgAECgcJCgAAAA==.',
Nu='Nurckers:BAAALgAFFAEJAQAAAA==.',
Oa='Oakinelf:BAAALgADCgcJAQAAAA==.',
Om='Omnishifts:BAAALgAECgEJAgAAAA==.',
Or='Oramo:BAABLgAECn8fAAMWAAgJfCMmBQDwAgAWAAgJxSImBQDwAgAGAAYJgCIvbQCLAQAAAA==.',
Ov='Ovaries:BAAALgAECgQJBAABLgAECgUJCQADAAAAAA==.',
Pa='Paktam:BAACLgAFFH8GAAISAAMJvRXcSwDCAAASAAMJvRXcSwDCAAAuAAQKfxcAAhIABwnOHaIeAFkCABIABwnOHaIeAFkCAAAA.Paméla:BAAALgAECgcJDwABLgAECgkJcQAKAHggAA==.Paradisya:BAAALgADCggJDgAAAA==.',
Pe='Perceptor:BAAALgAECgEJAQABLgAECgkJKQAXAJMhAA==.Pets:BAAALgAECgEJAQABLgAECgkJVQAEAC4VAA==.',
Pi='Pittliaq:BAAALgAECgkJDwAAAA==.',
Pl='Placebo:BAAALgAECgUJBQABLgAFFAUJEAAZAN4UAA==.',
Pr='Prothero:BAACLgAFFH8YAAMFAAcJzR85JgDfAQAFAAcJzR85JgDfAQAVAAEJZRk2BwBBAAAuAAQKfxoAAwUACQn8JDIGAFEDAAUACQn8JDIGAFEDABUACAkrGAMDAFACAAAA.Proyo:BAAALgADCgUJBQAAAA==.',
['På']='Påthor:BAACLgAFFH8HAAIRAAIJkw/XPgB4AAARAAIJkw/XPgB4AAAuAAQKfzMAAxEACQl/IvIBANUBABEACQl/IvIBANUBABcAAwkSEgNZAFsAAAAA.',
Ra='Raikonnen:BAAALgAECgEJAQAAAA==.Rapidstrikes:BAAALgAECgUJCAAAAA==.Rawtoor:BAACLgAFFH8sAAIMAAgJSRhFFgD/AQAMAAgJSRhFFgD/AQAuAAQKfyEAAgwACAk4IdInAGUCAAwACAk4IdInAGUCAAAA.',
Re='Rebelsister:BAAALgADCgcJEAAAAA==.Refridgerate:BAAALgADCgUJBwAAAA==.',
Ri='Riddagain:BAABLgAECn8bAAMkAAYJeA/1FAAHAQAkAAYJTw/1FAAHAQAMAAIJwAvjHQEsAAAAAA==.Ridgemonk:BAACLgAFFH8HAAIOAAMJSR4mCwDgAAAOAAMJSR4mCwDgAAAuAAQKfzsAAw4ACQmeI1MCADoDAA4ACQmeI1MCADoDAAEABAlAAZhgAEwAAAAA.Ridgerock:BAAALgAECgUJAwAAAA==.Riggsdk:BAABLgAFFH8SAAMGAAYJDCJyCQD8AQAGAAYJDCJyCQD8AQAWAAEJAABOJgAAAAABLgAFFAkJKgATAJAkAA==.Riggse:BAAALgAFFAEJAQABLgAFFAkJKgATAJAkAA==.Riggshunt:BAACLgAFFH8qAAQTAAkJkCTTAACrAQAfAAYJLCQuAAD7AQATAAcJ3yTTAACrAQAgAAEJAAC/KABKAAAuAAQKfx4ABBMACAmrJr0IAAcDABMABwmYJr0IAAcDAB8ACAmTJIQDAPICACAAAQmCHGd9AE8AAAAA.Riggspal:BAABLgAFFH8TAAIHAAYJASV3AwAkAgAHAAYJASV3AwAkAgABLgAFFAkJKgATAJAkAA==.Riggswar:BAABLgAFFH8KAAMKAAUJER8PJQAgAQAKAAQJOR4PJQAgAQAcAAIJ0xrbLgCoAAABLgAFFAkJKgATAJAkAA==.Riggzs:BAAALgAFFAIJAgABLgAFFAkJKgATAJAkAA==.',
Ro='Roadkill:BAABLgAECn8gAAIWAAgJnSM4BAALAwAWAAgJnSM4BAALAwAAAA==.Rolltoor:BAABLgAFFH8GAAMLAAMJJRZ1IADWAAALAAMJJRZ1IADWAAAOAAEJrgSnXwAwAAAAAA==.Roonate:BAAALgADCgUJBQAAAA==.Rosemary:BAAALgAECgQJBAAAAA==.',
Ry='Ryujin:BAAALgAECgQJCQAAAA==.',
Sa='Saiko:BAABLgAFFH8bAAMNAAYJwhgfCQB2AQANAAYJwhgfCQB2AQAMAAQJzw3QTwD9AAAAAA==.Sansa:BAACLgAFFH8bAAMfAAgJPRiEAQBXAgAfAAgJPRiEAQBXAgATAAIJBB9yKwC6AAAuAAQKfyMAAh8ACQlnI00CACMDAB8ACQlnI00CACMDAAAA.Saranite:BAAALgAFFAEJAgAAAA==.Saso:BAACLgAFFH8dAAMFAAcJjR23GAAvAgAFAAcJjR23GAAvAgAVAAIJLBf8AgBTAAAuAAQKfzsABAUACQmVImQTAOUCAAUACQmUImQTAOUCABUABglXIy8EALsBACMAAwlnErALAHcAAAAA.Sastroll:BAAALgAECgUJBQAAAA==.',
Sc='Scorn:BAAALgADCgcJCAAAAA==.Scroll:BAACLgAFFH8MAAIBAAQJSxGuEwDqAAABAAQJSxGuEwDqAAAuAAQKfycAAgEACQlYHfQAAMICAAEACQlYHfQAAMICAAAA.',
Se='Seluvis:BAABLgAECn8WAAIFAAcJ0QGeDQGYAAAFAAcJ0QGeDQGYAAAAAA==.Sentai:BAAALgADCgcJBwAAAA==.Serapayne:BAAALgAECgcJAQAAAA==.Serbitar:BAAALgAECgEJAgAAAA==.',
Sh='Shadow:BAACLgAFFH8oAAIMAAgJmRXeFwDzAQAMAAgJmRXeFwDzAQAuAAQKf18AAgwACQmbJJkDAE4DAAwACQmbJJkDAE4DAAAA.Shandrilah:BAAALgADCgQJBAAAAA==.Shapeshift:BAAALgADCgUJBQABLgAECgIJAgADAAAAAA==.Shialebuff:BAABLgAECn9PAAQEAAkJHSFIDQCSAgAEAAkJHSFIDQCSAgAJAAkJZhzDDQB5AgACAAQJFxk4OgAnAQAAAA==.Shijin:BAAALgAECgUJCQAAAA==.Shortfuze:BAAALgAECgYJDQAAAA==.',
Si='Sindar:BAAALgADCgUJBQAAAA==.Sinfall:BAAALgAECggJDgAAAA==.Siphon:BAAALgAECgEJAwAAAA==.Siscomp:BAABLgAECn9xAAIKAAkJeCDmEABwAgAKAAkJeCDmEABwAgAAAA==.Sixth:BAABLgAECn8XAAIiAAcJ/BqKJwCwAQAiAAcJ/BqKJwCwAQAAAA==.Sizzle:BAAALgADCgMJAwAAAA==.',
Sk='Skateboard:BAAALgADCgEJAQAAAA==.Sky:BAACLgAFFH8wAAICAAkJuRqIBwC2AgACAAkJuRqIBwC2AgAuAAQKfxQAAwIACAlxE48cALABAAIABwlZEo8cALABAAQABQnyD4hMAAYBAAAA.',
Sl='Sleck:BAAALgAECgYJDAAAAA==.',
Sm='Smooth:BAAALgAECgEJAQABLgAFFAYJCAACAEcTAA==.',
Sn='Snappa:BAAALgADCgYJCwAAAA==.Sniped:BAAALgAFFAEJAQAAAA==.Snugglepuff:BAABLgAECn8ZAAIKAAkJSBVoHAAKAgAKAAkJSBVoHAAKAgAAAA==.',
So='Soapfidas:BAAALgADCggJCgAAAA==.Sonarius:BAACLgAFFH8WAAMFAAUJkhs5TQBFAQAFAAUJkhs5TQBFAQAjAAEJCQP/BAA0AAAuAAQKfx0ABAUACAndHyk8AIYCAAUACAndHyk8AIYCABUAAgkCHZYNAKMAACMAAQmyEg8PADwAAAAA.Sophie:BAAALgAECgEJAwAAAA==.',
Sp='Splitterman:BAABLgAFFH81AAQWAAgJmyTRBABQAgAWAAcJFSLRBABQAgAUAAcJ5SNSAQAbAgAGAAQJYxy8IwAOAQAAAA==.',
St='Starfur:BAAALgAFFAEJAQAAAA==.Starphil:BAAALgAFFAEJAQAAAA==.',
Su='Su:BAABLgAECn8yAAIBAAcJ4yVlBwDiAgABAAcJ4yVlBwDiAgAAAA==.Sudno:BAAALgAECgQJCAABLgAFFAgJIgAQAKQVAA==.Sundae:BAABLgAECn83AAQEAAkJlSHsCADaAgAEAAgJHCPsCADaAgACAAgJhxubDgCFAgAJAAMJ3BZ4VgC5AAAAAA==.Sunwukong:BAAALgAECgUJCQAAAA==.Supersinpe:BAAALgAECgIJAgAAAA==.',
Sv='Svdrag:BAAALgAECgMJAwAAAA==.Svendlefyre:BAAALgADCgcJDgABLgAECgkJLgAZAIMZAA==.Svholydrag:BAAALgADCgEJAQAAAA==.Svmishima:BAAALgAECgMJBQAAAA==.',
Sw='Swirly:BAAALgAECgEJAQAAAA==.',
Sy='Sylvie:BAACLgAFFH8KAAITAAQJ3Aq2GAAWAQATAAQJ3Aq2GAAWAQAuAAQKfycAAhMACQnBFZ0qADMCABMACQnBFZ0qADMCAAAA.',
['Sý']='Sýlvanas:BAABLgAECn8UAAIgAAUJVxOzGADrAAAgAAUJVxOzGADrAAAAAA==.',
Te='Tealç:BAABLgAECn8gAAIdAAcJpheVGACQAQAdAAcJpheVGACQAQABLgAFFAQJGQAdAEcfAA==.Tekk:BAAALgAECgEJAQAAAA==.Tekkys:BAAALgAECgEJAgAAAA==.Tertle:BAAALgADCgUJBQAAAA==.',
Th='Thunyeth:BAAALgADCgMJAwAAAA==.',
Ti='Tiafinia:BAAALgAECgEJAgAAAA==.Tiggerstripe:BAAALgAFFAEJAQAAAA==.Timmyy:BAAALgAECgYJBgABLgAFFAQJCwAGAGoSAA==.Timur:BAAALgAECgMJBAAAAA==.Tinara:BAAALgADCgUJBQAAAA==.',
To='Tome:BAAALgAFFAEJAQABLgAFFAQJDAABAEsRAA==.',
Tr='Trigger:BAAALgAECgIJAgAAAA==.Trunks:BAAALgAECgEJAQABLgAECgYJEgADAAAAAA==.',
Tu='Turlesblows:BAABLgAECn8hAAMKAAgJYyBIJQDMAQAKAAgJYyBIJQDMAQAdAAEJOxWZRAA7AAAAAA==.',
Tw='Twityy:BAAALgADCgEJAgAAAA==.Twofiveyd:BAABLgAFFH8FAAIaAAQJjA84NgDrAAAaAAQJjA84NgDrAAABLgAFFAYJFAAcAGcYAA==.',
Ty='Tyladrhas:BAABLgAECn80AAIkAAkJVB/FAwCXAgAkAAkJVB/FAwCXAgAAAA==.Tyrismaximus:BAABLgAECn8eAAIHAAcJZhahBwB5AQAHAAcJZhahBwB5AQAAAA==.',
Ul='Ulkina:BAAALgADCgYJCQAAAA==.',
Up='Up:BAAALgAECgcJCwAAAA==.',
Va='Vaelith:BAAALgAECgIJAgAAAA==.Vaelyth:BAAALgAECgkJEQAAAA==.Valerine:BAABLgAECn8aAAIFAAkJ/woHgQB1AQAFAAkJ/woHgQB1AQAAAA==.Vanoran:BAAALgAECgMJBAAAAA==.Varina:BAAALgAECgcJEwAAAA==.',
Ve='Velmadinkley:BAAALgAECgMJAwABLgAECgYJEgADAAAAAA==.Velsaert:BAAALgAECgEJAQAAAA==.Venki:BAAALgAECgkJDAAAAA==.',
Vi='Vitani:BAAALgADCgIJAgABLgAFFAUJEAAZAN4UAA==.',
Vo='Voidnova:BAABLgAFFH8HAAIFAAMJlRDgiADHAAAFAAMJlRDgiADHAAAAAA==.Voidphayze:BAAALgAECgUJDAABLgAFFAMJBQAGAEUTAA==.',
Vu='Vulken:BAABLgAECn9nAAITAAkJESXiDwDRAgATAAkJESXiDwDRAgAAAA==.',
['Vê']='Vê:BAABLgAECn8XAAMFAAkJLxr+TwBHAgAFAAkJphj+TwBHAgAVAAIJ6SI8AwBnAAAAAA==.',
Wa='Wallace:BAAALgAECgcJDAAAAA==.Walterlight:BAAALgAECgYJDgAAAA==.Watto:BAABLgAECn8ZAAMSAAkJOR9LFwCPAgASAAkJOR9LFwCPAgAiAAUJmRbGSgAKAQAAAA==.',
We='Wemongin:BAAALgADCgUJBQAAAA==.',
Wh='Whimsical:BAABLgAECn8XAAISAAYJgBcxUQBuAQASAAYJgBcxUQBuAQAAAA==.',
Wi='Winnìng:BAACLgAFFH8GAAIeAAMJ8gWYEQBxAAAeAAMJ8gWYEQBxAAAuAAQKfyQAAh4ACQmmDNMZAEoBAB4ACQmmDNMZAEoBAAAA.',
Wu='Wugong:BAAALgADCgEJAQAAAA==.Wulfi:BAAALgAECgYJBgAAAA==.',
['Wó']='Wórkwórk:BAACLgAFFH8FAAIKAAMJKhROFwCsAAAKAAMJKhROFwCsAAAuAAQKfxsAAwoACQk6Gxg3AMsBAAoABwnRGRg3AMsBABwAAwnsGr8fAO8AAAAA.',
Ze='Zerg:BAAALgAECgIJAgAAAA==.',
Zi='Zich:BAAALgADCgMJAwAAAA==.Zihon:BAABLgAECn8UAAIGAAQJTxpN7QDEAAAGAAQJTxpN7QDEAAAAAA==.',
Zo='Zodiiak:BAABLgAECn9EAAIhAAkJMR0gBwBgAgAhAAkJMR0gBwBgAgAAAA==.Zombiepanda:BAAALgAECgUJBwAAAA==.',
Zu='Zubb:BAAALgAECgUJBwABLgAECggJEgADAAAAAA==.Zugg:BAAALgAECgIJAgABLgAECggJEgADAAAAAA==.Zuhh:BAAALgAECgcJEQABLgAECggJEgADAAAAAA==.Zupp:BAAALgAECggJEgAAAA==.Zuvv:BAAALgADCgEJAQABLgAECggJEgADAAAAAA==.',
Zx='Zx:BAAALgADCgYJBgAAAA==.',
['Äs']='Äsher:BAAALgAECgEJAgABLgAECgUJCQADAAAAAA==.',
['Ér']='Ér:BAAALgAECgkJBgAAAA==.',
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
