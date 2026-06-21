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

local lookup = {'Priest-Discipline','Unknown-Unknown','Priest-Holy','Mage-Frost','Paladin-Retribution','Paladin-Holy','Priest-Shadow','Monk-Mistweaver','Warrior-Fury','Monk-Windwalker','DemonHunter-Devourer','DemonHunter-Havoc','DeathKnight-Unholy','Monk-Brewmaster','Druid-Restoration','Warlock-Demonology','Druid-Balance','Shaman-Restoration','Hunter-BeastMastery','DeathKnight-Frost','Mage-Arcane','DeathKnight-Blood','Druid-Guardian','Evoker-Preservation','Druid-Feral','Evoker-Augmentation','Evoker-Devastation','Warrior-Arms','Warrior-Protection','Paladin-Protection','Hunter-Survival','Hunter-Marksmanship','Shaman-Enhancement','Shaman-Elemental','Mage-Fire','DemonHunter-Vengeance',}
local provider = {region='US',realm='Gundrak',name='US',type='weekly',zone=46,date='2026-06-20',data={Ad='Adelyne:BAAALgAFFAQJBAABLgAFFAUJEgABABkcAA==.Adera:BAAALgAECgYJBwAAAA==.',
Af='Aff:BAAALgADCgYJBgAAAA==.',
Ag='Agony:BAAALgAECgQJBgAAAA==.',
Ah='Ahkanon:BAAALgADCgEJAQAAAA==.Ahoo:BAAALgAECgkJCgAAAA==.',
Ai='Aiden:BAAALgAECgEJAgABLgAECgIJAgACAAAAAA==.Aidendk:BAAALgADCgIJAgABLgAECgIJAgACAAAAAA==.Aidenp:BAAALgADCgIJAgABLgAECgIJAgACAAAAAA==.Air:BAAALgADCgcJBwABLgAFFAgJJwADADkbAA==.',
Ak='Aku:BAAALgADCgIJBAAAAA==.',
Al='Aleniastra:BAAALgAECgYJEwAAAA==.Alexyss:BAAALgAECgUJDgAAAA==.Alykard:BAABLgAECn8xAAIEAAkJwhGVTAD2AQAEAAkJwhGVTAD2AQAAAA==.',
Am='Amelia:BAAALgAECgEJAQAAAA==.Amyara:BAAALgAECgEJAgAAAA==.',
An='Andronicas:BAABLgAECn8mAAMFAAkJ6hLNRQD1AQAFAAkJ6hLNRQD1AQAGAAEJogevnAAtAAAAAA==.Aneira:BAABLgAFFH8gAAIEAAQJSAphbAALAQAEAAQJSAphbAALAQAAAA==.',
Ap='Apexis:BAAALgADCgYJCQAAAA==.',
Ar='Ariaa:BAABLgAECn8YAAIHAAYJOxiYLQBsAQAHAAYJOxiYLQBsAQAAAA==.Arieyri:BAAALgADCgcJBwAAAA==.Artpop:BAAALgAFFAEJAQABLgAFFAcJFwAIAIURAA==.',
As='Aseria:BAAALgAECgYJCAAAAA==.Ash:BAAALgADCgcJCwAAAA==.Ashvira:BAAALgAECgQJBAAAAA==.Aspect:BAAALgADCgcJDgABLgAECgEJAQACAAAAAA==.Astarael:BAABLgAECn8iAAMHAAkJShcCIgC3AQAHAAgJGhYCIgC3AQADAAcJLQ5eUgCVAAAAAA==.',
Av='Avi:BAABLgAECn8oAAIBAAkJUhVREgBSAgABAAkJUhVREgBSAgABLgAECgkJcQAJAHggAA==.',
Ba='Babygurl:BAACLgAFFH8FAAIGAAMJNx8LJQD5AAAGAAMJNx8LJQD5AAAuAAQKf3YAAgYACQntJU0CAIkDAAYACQntJU0CAIkDAAAA.Baragas:BAAALgAECgYJDgAAAA==.Bareback:BAAALgAECgQJBAAAAA==.Barney:BAAALgADCgEJAQAAAA==.Battosaî:BAAALgAECgQJBAAAAA==.',
Be='Beeny:BAACLgAFFH85AAIIAAkJOSRhAgAiAwAIAAkJOSRhAgAiAwAuAAQKf0EAAwgACQlpI4UIAMwCAAgACQlpI4UIAMwCAAoAAQlsEBicADMAAAAA.Belle:BAACLgAFFH8ZAAMLAAgJxBaoFAAMAgALAAgJxBaoFAAMAgAMAAEJ8Bc/DABWAAAuAAQKfy0AAwsACAnFJhIEAIgDAAsACAmFJhIEAIgDAAwABwk+IFIOAH4CAAAA.Berat:BAAALgADCgQJBAAAAA==.Berzerker:BAAALgADCgcJEwAAAA==.',
Bg='Bgc:BAAALgADCgUJBQAAAA==.',
Bi='Binari:BAAALgAECgMJAwABLgAFFAMJBQAJACoUAA==.Binlock:BAAALgAECgQJBAABLgAFFAMJBQAJACoUAA==.',
Bl='Bl:BAAALgAECgMJAwAAAA==.Bladebear:BAABLgAECn82AAIEAAkJUxWBTgDwAQAEAAkJUxWBTgDwAQAAAA==.',
Bo='Boose:BAAALgAECgYJBgAAAA==.Bootybreaker:BAAALgADCgcJBwAAAA==.Boxoflunch:BAAALgAECgEJAQAAAA==.',
Br='Brat:BAAALgAECgEJBAABLgAECgkJVQADAC4VAA==.Brewingmist:BAAALgAECgUJBQABLgAFFAMJBQANAEUTAA==.Bréwmaster:BAABLgAECn8VAAMOAAgJcxhaFAALAgAOAAgJcxhaFAALAgAIAAYJVhGfTAA6AQABLgAECgkJIgAHAEoXAA==.',
Bu='Bubbelz:BAAALgAECgMJAwAAAA==.Bubbleez:BAAALgADCgUJBQAAAA==.Bubblôseven:BAAALgAECgEJAQAAAA==.Bucklord:BAABLgAECn8iAAMHAAgJjRkAFwAuAgAHAAgJjRkAFwAuAgADAAEJABkEbAA6AAAAAA==.Budin:BAAALgAECggJEgAAAA==.Bullmann:BAAALgADCgQJBAAAAA==.Buttons:BAAALgADCgEJAQAAAA==.',
Ca='Cannibal:BAABLgAECn8+AAIPAAkJkxxBDwDaAgAPAAkJkxxBDwDaAgAAAA==.Caplock:BAABLgAECn8VAAIQAAYJoRFohABRAQAQAAYJoRFohABRAQAAAA==.Capri:BAABLgAECn8UAAIRAAcJAwnJRAD5AAARAAcJAwnJRAD5AAAAAA==.',
Ce='Cellun:BAAALgAECgUJEwAAAA==.Centipede:BAAALgAECgYJCQABLgAECgYJFwASAIAXAA==.Ceredis:BAAALgAECgUJCwAAAA==.',
Ch='Chiwolf:BAAALgAECgUJBQAAAA==.Choomoo:BAAALgADCgcJCwABLgAFFAYJGAAIAP8NAA==.',
Cl='Cleankarma:BAAALgADCgEJAwAAAA==.',
Co='Comet:BAAALgAECgEJAQAAAA==.Cool:BAABLgAFFH8FAAIFAAMJ1BO+bADWAAAFAAMJ1BO+bADWAAAAAA==.Corwiggs:BAAALgAECgYJDAAAAA==.',
Cr='Crikey:BAABLgAECn8cAAITAAgJBRxaJwBCAgATAAgJBRxaJwBCAgAAAA==.Crimínal:BAAALgADCgcJCwAAAA==.Cripsee:BAAALgADCgMJAwAAAA==.',
Cu='Curbie:BAAALgAECgIJAwAAAA==.',
Cv='Cvdruid:BAAALgAECgUJBQAAAA==.',
Cy='Cyndrixx:BAAALgAECgIJAwAAAA==.',
['Cô']='Cônvict:BAAALgADCgYJBgAAAA==.',
De='Deacknight:BAABLgAECn8cAAMNAAgJwRuPLgB+AgANAAgJwRuPLgB+AgAUAAEJig2BFwAyAAABLgADCgYJBwACAAAAAA==.Deacmonk:BAAALgADCgYJBgABLgADCgYJBwACAAAAAA==.Definitely:BAACLgAFFH8XAAIEAAQJpyIOPgB2AQAEAAQJpyIOPgB2AQAuAAQKfzsAAwQACQlCJP8LABkDAAQACQlCJP8LABkDABUAAQkPICobAD8AAAAA.Deki:BAEALgAECgYJBgABLgAFFAcJGAAFAPkXAA==.Dementiaous:BAAALgAECgIJAwAAAA==.Desariana:BAABLgAECn8lAAIFAAkJcxAPZgCjAQAFAAkJcxAPZgCjAQAAAA==.',
Di='Diggitie:BAAALgAECgEJAQAAAA==.Ditto:BAABLgAFFH8ZAAIIAAYJRhhyHACPAQAIAAYJRhhyHACPAQAAAA==.',
Do='Domtop:BAABLgAFFH8FAAMWAAMJXAElPABFAAAWAAIJTwElPABFAAAUAAEJdgFgLgAuAAABLgAFFAcJFwAIAIURAA==.Doot:BAAALgAECgIJAgAAAA==.Dormas:BAABLgAECn8YAAIXAAcJ3g8CLAAAAQAXAAcJ3g8CLAAAAQAAAA==.Doug:BAAALgADCgEJAQAAAA==.Doxy:BAAALgAECgcJCQAAAA==.',
Dr='Drakeon:BAABLgAECn8UAAIYAAcJ/g45FwBdAQAYAAcJ/g45FwBdAQABLgAECgkJcQAJAHggAA==.',
Ee='Eeryxx:BAAALgAECgEJAQAAAA==.',
El='Eldh:BAABLgAECn8kAAMOAAkJLBGuIwCNAQAOAAkJ5w2uIwCNAQAKAAEJYiTccgBqAAAAAA==.Eleison:BAAALgADCgMJAwAAAA==.Elendrial:BAAALgAECgIJAgAAAA==.Elendril:BAAALgADCgcJFQAAAA==.Elisoly:BAACLgAFFH8FAAIGAAIJDQyFQABhAAAGAAIJDQyFQABhAAAuAAQKfykAAgYABglrIO4cABwCAAYABglrIO4cABwCAAAA.',
Em='Emrald:BAABLgAECn8UAAIZAAcJrw9xFgBSAQAZAAcJrw9xFgBSAQAAAA==.Emridius:BAAALgAECgEJAwABLgAECggJIQAJAGMgAA==.',
En='Endlessly:BAACLgAFFH8QAAIZAAUJ3hSHCAAiAQAZAAUJ3hSHCAAiAQAuAAQKfyQAAhkACQk2I+kDAOsCABkACQk2I+kDAOsCAAAA.Enerchi:BAAALgADCgMJAwAAAA==.',
Er='Erivoker:BAAALgAECgYJDAABLgAECgYJEgACAAAAAA==.Errimage:BAAALgAECgYJEgAAAA==.Errishoot:BAAALgAECgUJCQABLgAECgYJEgACAAAAAA==.Ervinia:BAAALgADCgYJCgABLgAECgYJEwACAAAAAA==.',
Ev='Evelinar:BAAALgAECgcJDgAAAA==.Evoslex:BAABLgAECn85AAMaAAkJxCPkBAAVAwAaAAkJxCPkBAAVAwAbAAYJzx1vEwCsAQAAAA==.',
Ex='Exo:BAECLgAFFH8rAAIWAAgJ5xlcBwAVAgAWAAgJ5xlcBwAVAgAuAAQKfysAAhYACQkcItYEAOICABYACQkcItYEAOICAAAA.',
Fa='Facerolleh:BAACLgAFFH80AAMcAAgJ+CGHAgCUAgAcAAgJsyGHAgCUAgAJAAQJZiGMBgCGAQAuAAQKf0YABAkACQmdJc4EAFwDAAkACAn2Jc4EAFwDABwACAl/IkEGAJsCAB0AAgmNHaRJAE4AAAAA.Fatedx:BAAALgAECgYJCQAAAA==.',
Fe='Feelgoodinc:BAAALgADCgkJFAAAAA==.',
Fi='Fidah:BAAALgAECgEJAQAAAA==.Firemagemain:BAAALgADCgUJBQABLgAFFAMJBQAJACoUAA==.',
Fl='Flanann:BAAALgAECgEJAQABLgAECgMJDAACAAAAAA==.Flop:BAAALgAECgUJCQABLgAFFAUJEwAEAJIbAA==.Flora:BAAALgAECgEJAwAAAA==.',
Fr='Frostmere:BAAALgADCggJGQAAAA==.',
Fu='Fuknazum:BAAALgAECgEJAQAAAA==.Furcht:BAABLgAECn8dAAINAAcJVBJIhQBZAQANAAcJVBJIhQBZAQAAAA==.',
Ga='Galadar:BAAALgADCgUJBQAAAA==.',
Gh='Ghrael:BAAALgAECgMJBAAAAA==.',
Gi='Giteff:BAABLgAFFH8wAAILAAkJJSVuAABzAwALAAkJJSVuAABzAwAAAA==.Gitèff:BAABLgAFFH8fAAILAAgJkSC+BADKAgALAAgJkSC+BADKAgABLgAFFAkJMAALACUlAA==.Giveroflife:BAABLgAECn8VAAMeAAYJVg0AKwDDAAAFAAYJBQcv7gDNAAAeAAQJjg8AKwDDAAAAAA==.',
Go='Gourdin:BAAALgAECgQJBQABLgAECgYJCAACAAAAAA==.',
Gr='Gramnpa:BAAALgADCgUJBQAAAA==.Grandpriest:BAAALgAECgYJDQAAAA==.Gravepriest:BAAALgAECgEJAQAAAA==.Grimtysha:BAAALgAECgYJEAAAAA==.Grimveil:BAAALgAECgYJDQAAAA==.Gromit:BAAALgAECgQJCQAAAA==.Gröuch:BAABLgAFFH8IAAIOAAQJXQpJLgDwAAAOAAQJXQpJLgDwAAAAAA==.',
Ha='Harafar:BAACLgAFFH8IAAIRAAUJuQfVMAC/AAARAAUJuQfVMAC/AAAuAAQKfx4AAxEACQnuGUcOAHcCABEACQnuGUcOAHcCAA8AAwl7B1qhAG0AAAAA.Hate:BAAALgAECgYJDQABLgAFFAgJIwAEAHkYAA==.',
He='Hellbourne:BAABLgAECn8kAAILAAkJ8hjuKAAmAgALAAkJ8hjuKAAmAgAAAA==.',
Hi='Himmel:BAAALgADCgcJCQAAAA==.',
Ho='Hopnhorsé:BAAALgAECgQJBQAAAA==.Hotchoq:BAABLgAFFH8KAAIEAAMJqgzPhADPAAAEAAMJqgzPhADPAAAAAA==.',
Hu='Huntchoq:BAABLgAFFH8PAAQfAAYJZgxMFwAXAQAfAAUJTg1MFwAXAQATAAMJ1wolbQDJAAAgAAIJdAkCJwB0AAAAAA==.Huxley:BAAALgADCgMJAwAAAA==.',
Ik='Ikan:BAABLgAECn8cAAIGAAkJmxZgAAARAgAGAAkJmxZgAAARAgAAAA==.',
In='Infest:BAAALgAECgQJCAAAAA==.Inzolethys:BAAALgADCgcJBwAAAA==.',
It='Itchy:BAAALgADCgEJAgAAAA==.Itskiohte:BAABLgAECn8pAAIhAAkJVw4EEACyAQAhAAkJVw4EEACyAQAAAA==.',
Ja='Jaggernut:BAAALgADCgUJBQAAAA==.',
Ji='Jimmbo:BAAALgAECgQJBAAAAA==.',
Jo='Johnny:BAAALgAECgIJAgABLgAECgkJOQAaAMQjAA==.',
Ju='Judeau:BAAALgADCgEJAQAAAA==.',
Ka='Kaelthuzzad:BAAALgADCgEJAQAAAA==.Kaitza:BAAALgAECgYJCwAAAA==.Kalzaketh:BAABLgAECn9DAAMaAAkJbQ3dKwCOAQAaAAkJbQ3dKwCOAQAbAAMJ5QSIMwB5AAAAAA==.Kashari:BAAALgAECgYJCwABLgAECgkJfgAHABUcAA==.Katali:BAABLgAECn8VAAMFAAcJSQyvqgAnAQAFAAcJSQyvqgAnAQAGAAYJCwVlWwDIAAAAAA==.Kavothe:BAAALgAECgYJCwAAAA==.Kazo:BAAALgAFFAEJAQAAAA==.Kazuggar:BAACLgAFFH8hAAISAAYJuyKPBwBPAgASAAYJuyKPBwBPAgAuAAQKfzgAAxIACQmsJW4CAFwDABIACAmCJW4CAFwDACIABgkAFc8zAGwBAAAA.Kazzn:BAABLgAFFH8FAAIPAAQJrwgIPQC7AAAPAAQJrwgIPQC7AAAAAA==.',
Ke='Kedar:BAAALgAECgYJEQAAAA==.Keg:BAAALgAECgIJAgAAAA==.Kelabar:BAAALgADCgQJBAAAAA==.',
Ki='Kick:BAAALgADCgQJBAABLgAFFAgJIwAEAHkYAA==.Kiffs:BAAALgAECgcJCgAAAA==.Kill:BAAALgAFFAEJAgAAAA==.Killerman:BAABLgAFFH8uAAQUAAkJaCX5AQBDAgAUAAYJeSb5AQBDAgANAAYJGSLkJQDVAQAWAAMJixhIJADMAAAAAA==.Kirâ:BAABLgAECn8UAAIJAAgJCxxoHQADAgAJAAgJCxxoHQADAgABLgAECgcJEwACAAAAAA==.',
Kr='Kregnar:BAABLgAECn8pAAIcAAkJBRwbCABzAgAcAAkJBRwbCABzAgAAAA==.Kresh:BAAALgAECgcJCwAAAA==.',
Ku='Kucabara:BAAALgAECgIJAwAAAA==.Kuraiwiggs:BAAALgADCgYJDAAAAA==.',
Kw='Kwichang:BAABLgAECn8ZAAIEAAcJuw/xlQBNAQAEAAcJuw/xlQBNAQAAAA==.',
Ky='Kyndariae:BAAALgAECgcJBwAAAA==.',
['Ké']='Kélpo:BAAALgADCgMJBAAAAA==.',
La='Lasagne:BAAALgADCgMJAwAAAA==.',
Le='Leatherkink:BAABLgAFFH8GAAITAAQJTAYXUwADAQATAAQJTAYXUwADAQABLgAFFAcJFwAIAIURAA==.Lesley:BAAALgAECgEJAQAAAA==.',
Li='Lickynose:BAABLgAECn80AAMEAAkJdCKjDwD+AgAEAAkJdCKjDwD+AgAjAAEJEiAoEABdAAAAAA==.Lips:BAAALgAECgEJAQAAAA==.',
Ls='Ls:BAABLgAECn8iAAQMAAkJaiPMCQCNAgAMAAgJ3R/MCQCNAgALAAgJnCG9MQAzAgAkAAcJYhVKDgBtAQAAAA==.',
Ly='Lythium:BAAALgAECggJDAAAAA==.',
Ma='Madarabia:BAAALgAECgYJDQAAAA==.Magnius:BAAALgAECgMJAwAAAA==.Makcik:BAAALgAECgEJAgAAAA==.Mamut:BAAALgAECgEJAQAAAA==.Mantisar:BAACLgAFFH8IAAIFAAMJ5RJzbwDSAAAFAAMJ5RJzbwDSAAAuAAQKfx4AAgUABwnmHvY9AA0CAAUABwnmHvY9AA0CAAAA.Mattdemonn:BAAALgAECgUJBgAAAA==.Maxsm:BAABLgAECn8XAAIiAAgJrhmSIQACAgAiAAgJrhmSIQACAgAAAA==.',
Me='Melanippe:BAABLgAECn8XAAIPAAYJDxtuPQCuAQAPAAYJDxtuPQCuAQAAAA==.Meleefox:BAAALgADCgUJBQAAAA==.Melethron:BAABLgAECn8+AAIFAAkJgRwwJwBnAgAFAAkJgRwwJwBnAgAAAA==.Melioknky:BAAALgAECgYJBgAAAA==.',
Mi='Michaeljfox:BAAALgAECgQJBAAAAA==.Mid:BAAALgADCgYJBgAAAA==.Mightymage:BAABLgAECn8hAAIEAAgJ4Q1zhgBqAQAEAAgJ4Q1zhgBqAQAAAA==.Millie:BAAALgAECgEJAQAAAA==.Millionbaby:BAAALgAECgEJAQAAAA==.Milliondruid:BAAALgAECgMJBAAAAA==.Millionsm:BAAALgADCgQJBQAAAA==.Mirrorimage:BAABLgAFFH8GAAIHAAIJSwdUMQCBAAAHAAIJSwdUMQCBAAABLgAFFAYJEgAHAAgVAA==.Mirrorx:BAACLgAFFH8SAAIHAAYJCBV/EABnAQAHAAYJCBV/EABnAQAuAAQKfzIAAgcACQlzICwJALwCAAcACQlzICwJALwCAAAA.Miy:BAAALgAECgEJAQAAAA==.',
Mo='Mongon:BAAALgAECgYJBgAAAA==.Moogle:BAAALgAECgIJBAAAAA==.Moomie:BAABLgAECn8iAAIPAAgJAxZTOAC1AQAPAAgJAxZTOAC1AQAAAA==.Moosfel:BAABLgAECn8jAAIZAAcJGhpeDwDAAQAZAAcJGhpeDwDAAQAAAA==.Morubine:BAAALgAECgQJBgAAAA==.',
Mt='Mtzz:BAAALgAECgUJBQABLgAECgYJCAACAAAAAA==.',
Mu='Mudcake:BAAALgAECgEJAQAAAA==.',
My='Mygravebroke:BAAALgADCggJCQAAAA==.Mystdragon:BAACLgAFFH8XAAMYAAcJTBcyDgC7AQAYAAYJ6RcyDgC7AQAaAAQJkwzTLQAMAQAuAAQKfzAAAhgACQm5IYADAA4DABgACQm5IYADAA4DAAEuAAUUCAknAAgAmh0A.Mystweaverr:BAACLgAFFH8nAAMIAAgJmh0MBgCzAgAIAAgJmh0MBgCzAgAKAAEJ9QTLRwAxAAAuAAQKfy8AAwgACQn3H4AJALkCAAgACQn3H4AJALkCAAoAAgkjIrZWALMAAAAA.',
['Mö']='Mörae:BAAALgADCgEJAQABLgAECgYJFwAPAA8bAA==.',
Na='Naddar:BAACLgAFFH8WAAIGAAUJpxnGGABdAQAGAAUJpxnGGABdAQAuAAQKf1UAAgYACQkMIJ4GACIDAAYACQkMIJ4GACIDAAAA.Namadgi:BAABLgAECn8uAAIPAAkJiR1fDQDwAgAPAAkJiR1fDQDwAgAAAA==.Nathria:BAAALgAECgIJAwAAAA==.',
Ne='Netalis:BAABLgAECn8lAAIPAAgJwxTIMQDZAQAPAAgJwxTIMQDZAQAAAA==.',
Ni='Nikonii:BAAALgAECgMJBAAAAA==.',
Nu='Nurckers:BAAALgAFFAEJAQAAAA==.',
Oa='Oakinelf:BAAALgADCgcJAQAAAA==.',
Om='Omnishifts:BAAALgAECgEJAgAAAA==.',
Or='Oramo:BAABLgAECn8fAAMWAAgJfCMmBQDwAgAWAAgJxSImBQDwAgANAAYJgCIubQCLAQAAAA==.',
Ov='Ovaries:BAAALgADCgUJBQABLgAECgUJCQACAAAAAA==.',
Pa='Paktam:BAACLgAFFH8GAAISAAMJvRXbSwDCAAASAAMJvRXbSwDCAAAuAAQKfxcAAhIABwnOHaEeAFkCABIABwnOHaEeAFkCAAAA.Paméla:BAAALgAECgcJDwABLgAECgkJcQAJAHggAA==.Paradisya:BAAALgADCggJDgAAAA==.',
Pe='Perceptor:BAAALgAECgEJAQABLgAECgkJKQAXAJMhAA==.Pets:BAAALgAECgEJAQABLgAECgkJVQADAC4VAA==.',
Pi='Pittliaq:BAAALgAECgkJDwAAAA==.',
Pl='Placebo:BAAALgAECgUJBQABLgAFFAUJEAAZAN4UAA==.',
Pr='Prothero:BAACLgAFFH8WAAMEAAYJpCFTJgDfAQAEAAYJpCFTJgDfAQAVAAEJZRk5BwBBAAAuAAQKfxoAAwQACQn8JDIGAFEDAAQACQn8JDIGAFEDABUACAkrGAMDAFACAAAA.Proyo:BAAALgADCgUJBQAAAA==.',
['På']='Påthor:BAACLgAFFH8HAAIRAAIJkw/cPgB4AAARAAIJkw/cPgB4AAAuAAQKfyQAAxEABwmLHAwgAMgBABEABwmLHAwgAMgBABcAAwkSEgJZAFsAAAAA.',
Ra='Raikonnen:BAAALgAECgEJAQAAAA==.Rapidstrikes:BAAALgAECgUJCAAAAA==.Rawtoor:BAACLgAFFH8sAAILAAgJSRitAgCWAQALAAgJSRitAgCWAQAuAAQKfyEAAgsACAk4IdInAGUCAAsACAk4IdInAGUCAAAA.',
Re='Rebelsister:BAAALgADCgcJEAAAAA==.Refridgerate:BAAALgADCgUJBwAAAA==.',
Ri='Riddagain:BAABLgAECn8bAAMkAAYJeA/1FAAHAQAkAAYJTw/1FAAHAQALAAIJwAveHQEsAAAAAA==.Ridgemonk:BAABLgAECn87AAMOAAkJniNTAgA6AwAOAAkJniNTAgA6AwAIAAQJQAGYYABMAAAAAA==.Ridgerock:BAAALgAECgUJAwAAAA==.Riggsdk:BAABLgAFFH8FAAINAAUJMSBYOgCGAQANAAUJMSBYOgCGAQABLgAFFAkJJAATAAUjAA==.Riggse:BAAALgAFFAEJAQABLgAFFAkJJAATAAUjAA==.Riggshunt:BAACLgAFFH8kAAQTAAkJBSPTAACrAQAfAAYJLCQuAAD7AQATAAcJHCPTAACrAQAgAAEJAAC/KABKAAAuAAQKfx4ABBMACAmrJr0IAAcDABMABwmYJr0IAAcDAB8ACAmTJIQDAPICACAAAQmCHGd9AE8AAAAA.Riggspal:BAAALgAFFAIJAgABLgAFFAkJJAATAAUjAA==.Riggswar:BAABLgAFFH8KAAMJAAUJER8XJQAgAQAJAAQJOR4XJQAgAQAcAAIJ0xrgLgCoAAABLgAFFAkJJAATAAUjAA==.Riggzs:BAAALgAFFAIJAgABLgAFFAkJJAATAAUjAA==.',
Ro='Roadkill:BAABLgAECn8gAAIWAAgJnSM4BAALAwAWAAgJnSM4BAALAwAAAA==.Rolltoor:BAABLgAFFH8GAAMKAAMJJRZ0IADWAAAKAAMJJRZ0IADWAAAOAAEJrgSrXwAwAAAAAA==.Roonate:BAAALgADCgUJBQAAAA==.Rosemary:BAAALgAECgQJBAAAAA==.',
Ry='Ryujin:BAAALgAECgQJCQAAAA==.',
Sa='Saiko:BAABLgAFFH8aAAMMAAYJwhgeCQB2AQAMAAYJwhgeCQB2AQALAAQJzw3aTwD9AAAAAA==.Sansa:BAACLgAFFH8aAAMfAAgJPRiEAQBXAgAfAAgJPRiEAQBXAgATAAEJDx1jEABcAAAuAAQKfyMAAh8ACQlnI00CACMDAB8ACQlnI00CACMDAAAA.Saso:BAACLgAFFH8ZAAMEAAcJjR3LGAAvAgAEAAcJjR3LGAAvAgAVAAEJAxM5BgBMAAAuAAQKfzoABAQACQmVImgTAOUCAAQACQmUImgTAOUCABUABglXIy8EALsBACMAAwlnErALAHcAAAAA.Sastroll:BAAALgAECgUJBQAAAA==.',
Sc='Scorn:BAAALgADCgcJCAAAAA==.Scroll:BAABLgAECn8fAAIIAAkJDBndFwBaAgAIAAkJDBndFwBaAgAAAA==.',
Se='Seluvis:BAABLgAECn8WAAIEAAcJ0QGZDQGYAAAEAAcJ0QGZDQGYAAAAAA==.Sentai:BAAALgADCgcJBwAAAA==.Serapayne:BAAALgAECgcJAQAAAA==.Serbitar:BAAALgAECgEJAQAAAA==.',
Sh='Shadow:BAACLgAFFH8iAAILAAgJXRXxFwDzAQALAAgJXRXxFwDzAQAuAAQKf18AAgsACQmbJJkDAE4DAAsACQmbJJkDAE4DAAAA.Shandrilah:BAAALgADCgQJBAAAAA==.Shapeshift:BAAALgADCgUJBQABLgAECgIJAgACAAAAAA==.Shialebuff:BAABLgAECn9NAAQDAAkJYyBIDQCSAgADAAkJPyBIDQCSAgAHAAkJZhzEDQB5AgABAAQJFxk5OgAnAQAAAA==.Shijin:BAAALgAECgUJCQAAAA==.Shortfuze:BAAALgAECgYJDQAAAA==.',
Si='Sindar:BAAALgADCgUJBQAAAA==.Sinfall:BAAALgAECggJDgAAAA==.Siphon:BAAALgAECgEJAwAAAA==.Siscomp:BAABLgAECn9xAAIJAAkJeCDmEABwAgAJAAkJeCDmEABwAgAAAA==.Sixth:BAABLgAECn8XAAIiAAcJ/BqKJwCwAQAiAAcJ/BqKJwCwAQAAAA==.Sizzle:BAAALgADCgMJAwAAAA==.',
Sk='Skateboard:BAAALgADCgEJAQAAAA==.Sky:BAACLgAFFH8rAAIBAAcJ1B+MBwC2AgABAAcJ1B+MBwC2AgAuAAQKfxQAAwEACAlxE48cALABAAEABwlZEo8cALABAAMABQnyD4hMAAYBAAAA.',
Sl='Sleck:BAAALgAECgYJDAAAAA==.',
Sm='Smooth:BAAALgAECgEJAQABLgAFFAYJCAABAEcTAA==.',
Sn='Snappa:BAAALgADCgYJCwAAAA==.Sniped:BAAALgAFFAEJAQAAAA==.Snugglepuff:BAABLgAECn8YAAIJAAkJphRnHAAKAgAJAAkJphRnHAAKAgAAAA==.',
So='Soapfidas:BAAALgADCggJCgAAAA==.Sonarius:BAACLgAFFH8TAAIEAAUJkhuCCAD1AAAEAAUJkhuCCAD1AAAuAAQKfx0ABAQACAndHyk8AIYCAAQACAndHyk8AIYCABUAAgkCHZYNAKMAACMAAQmyEg8PADwAAAAA.Sophie:BAAALgAECgEJAwAAAA==.',
Sp='Splitterman:BAABLgAFFH8gAAQWAAgJZx7dBABQAgAWAAcJFSLdBABQAgAUAAYJOx6gAwDiAQANAAQJVBBLhAAAAQAAAA==.',
Su='Su:BAABLgAECn8yAAIIAAcJ4yVlBwDiAgAIAAcJ4yVlBwDiAgAAAA==.Sudno:BAAALgAECgQJCAABLgAFFAgJIgAQAKQVAA==.Sundae:BAABLgAECn83AAQDAAkJlSHsCADaAgADAAgJHCPsCADaAgABAAgJhxubDgCFAgAHAAMJ3BZ0VgC5AAAAAA==.Sunwukong:BAAALgAECgUJCQAAAA==.Supersinpe:BAAALgAECgIJAgAAAA==.',
Sv='Svdrag:BAAALgAECgMJAwAAAA==.Svendlefyre:BAAALgADCgcJDgABLgAECgkJLgAZAIMZAA==.Svholydrag:BAAALgADCgEJAQAAAA==.Svmishima:BAAALgAECgMJBQAAAA==.',
Sw='Swirly:BAAALgAECgEJAQAAAA==.',
Sy='Sylvie:BAACLgAFFH8HAAITAAMJbAzoBgDjAAATAAMJbAzoBgDjAAAuAAQKfycAAhMACQnBFZ8qADMCABMACQnBFZ8qADMCAAAA.',
['Sý']='Sýlvanas:BAABLgAECn8UAAIgAAUJVxOyGADrAAAgAAUJVxOyGADrAAAAAA==.',
Te='Tealç:BAABLgAECn8gAAIdAAcJpheVGACQAQAdAAcJpheVGACQAQABLgAFFAQJGQAdAEcfAA==.Tekk:BAAALgAECgEJAQAAAA==.Tekkys:BAAALgAECgEJAgAAAA==.Tertle:BAAALgADCgUJBQAAAA==.',
Ti='Tiafinia:BAAALgAECgEJAgAAAA==.Tiggerstripe:BAAALgAECgcJBwABLgAECgkJMQAhAEMQAA==.Timmyy:BAAALgAECgYJBgABLgAFFAQJCwANAGoSAA==.Timur:BAAALgAECgMJBAAAAA==.Tinara:BAAALgADCgUJBQAAAA==.',
To='Tome:BAAALgAECgEJAQABLgAECgkJHwAIAAwZAA==.',
Tr='Trigger:BAAALgAECgIJAgAAAA==.Trunks:BAAALgAECgEJAQABLgAECgYJDQACAAAAAA==.',
Tu='Turlesblows:BAABLgAECn8hAAMJAAgJYyBHJQDMAQAJAAgJYyBHJQDMAQAdAAEJOxWZRAA7AAAAAA==.',
Tw='Twityy:BAAALgADCgEJAgAAAA==.Twofiveyd:BAABLgAFFH8FAAIaAAQJjA83NgDrAAAaAAQJjA83NgDrAAABLgAFFAYJFAAcAGcYAA==.',
Ty='Tyladrhas:BAABLgAECn80AAIkAAkJVB/FAwCXAgAkAAkJVB/FAwCXAgAAAA==.Tyrismaximus:BAAALgAECgcJEwAAAA==.',
Ul='Ulkina:BAAALgADCgYJCQAAAA==.',
Up='Up:BAAALgAECgcJBwAAAA==.',
Va='Vaelith:BAAALgAECgIJAgAAAA==.Vaelyth:BAAALgAECgcJDAAAAA==.Valerine:BAABLgAECn8aAAIEAAkJ/woJgQB1AQAEAAkJ/woJgQB1AQAAAA==.Vanoran:BAAALgAECgMJBAAAAA==.Varina:BAAALgAECgcJEwAAAA==.',
Ve='Velsaert:BAAALgAECgEJAQAAAA==.Venki:BAAALgAECgkJDAAAAA==.',
Vi='Vitani:BAAALgADCgIJAgABLgAFFAUJEAAZAN4UAA==.',
Vo='Voidnova:BAABLgAFFH8HAAIEAAMJlRD9iADHAAAEAAMJlRD9iADHAAAAAA==.Voidphayze:BAAALgAECgUJDAABLgAFFAMJBQANAEUTAA==.',
Vu='Vulken:BAABLgAECn9nAAITAAkJESXkDwDRAgATAAkJESXkDwDRAgAAAA==.',
['Vê']='Vê:BAAALgAECgkJEQAAAA==.',
Wa='Wallace:BAAALgAECgcJDAAAAA==.Walterlight:BAAALgAECgYJDgAAAA==.Watto:BAABLgAECn8ZAAMSAAkJOR9LFwCPAgASAAkJOR9LFwCPAgAiAAUJmRbBSgAKAQAAAA==.',
We='Wemongin:BAAALgADCgUJBQAAAA==.',
Wh='Whimsical:BAABLgAECn8XAAISAAYJgBcsUQBuAQASAAYJgBcsUQBuAQAAAA==.',
Wi='Winnìng:BAACLgAFFH8FAAIeAAMJeQWXEQBxAAAeAAMJeQWXEQBxAAAuAAQKfyQAAh4ACQmmDNQZAEoBAB4ACQmmDNQZAEoBAAAA.',
Wu='Wugong:BAAALgADCgEJAQAAAA==.Wulfi:BAAALgAECgYJBgAAAA==.',
['Wó']='Wórkwórk:BAACLgAFFH8FAAIJAAMJKhROFwCsAAAJAAMJKhROFwCsAAAuAAQKfxsAAwkACQk6Gxg3AMsBAAkABwnRGRg3AMsBABwAAwnsGr8fAO8AAAAA.',
Ze='Zerg:BAAALgAECgIJAgAAAA==.',
Zi='Zich:BAAALgADCgMJAwAAAA==.Zihon:BAABLgAECn8UAAINAAQJTxpC7QDEAAANAAQJTxpC7QDEAAAAAA==.',
Zo='Zodiiak:BAABLgAECn9EAAIhAAkJMR0gBwBgAgAhAAkJMR0gBwBgAgAAAA==.Zombiepanda:BAAALgADCgkJCgAAAA==.',
Zu='Zubb:BAAALgAECgUJBwABLgAECggJEAACAAAAAA==.Zugg:BAAALgAECgIJAgABLgAECggJEAACAAAAAA==.Zuhh:BAAALgAECgUJBwABLgAECggJEAACAAAAAA==.Zupp:BAAALgAECggJEAAAAA==.',
Zx='Zx:BAAALgADCgYJBgAAAA==.',
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
