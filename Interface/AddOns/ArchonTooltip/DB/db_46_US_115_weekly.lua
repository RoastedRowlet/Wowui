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

local lookup = {'Priest-Discipline','Unknown-Unknown','Priest-Holy','Mage-Frost','Paladin-Retribution','Paladin-Holy','Monk-Mistweaver','Priest-Shadow','Warrior-Fury','Monk-Windwalker','DemonHunter-Devourer','DemonHunter-Havoc','DeathKnight-Unholy','Druid-Restoration','Warlock-Demonology','Shaman-Restoration','DeathKnight-Frost','Mage-Arcane','DeathKnight-Blood','Druid-Guardian','Evoker-Preservation','Monk-Brewmaster','Druid-Feral','Evoker-Augmentation','Evoker-Devastation','Warrior-Arms','Warrior-Protection','Druid-Balance','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Enhancement','Shaman-Elemental','Mage-Fire','DemonHunter-Vengeance','Paladin-Protection',}
local provider = {region='US',realm='Gundrak',name='US',type='weekly',zone=46,date='2026-06-06',data={Ad='Adelyne:BAAALgAFFAMJAwABLgAFFAUJEgABABkcAA==.Adera:BAAALgAECgYJBwAAAA==.',
Af='Aff:BAAALgADCgYJBgAAAA==.',
Ag='Agony:BAAALgAECgQJBgAAAA==.',
Ah='Ahkanon:BAAALgADCgEJAQAAAA==.Ahoo:BAAALgAECgQJBAAAAA==.',
Ai='Aiden:BAAALgAECgEJAgABLgAECgIJAgACAAAAAA==.Aidendk:BAAALgADCgIJAgABLgAECgIJAgACAAAAAA==.Aidenp:BAAALgADCgIJAgABLgAECgIJAgACAAAAAA==.Air:BAAALgADCgcJBwABLgAFFAgJJwADADkbAA==.',
Ak='Aku:BAAALgADCgIJBAAAAA==.',
Al='Aleniastra:BAAALgAECgYJEwAAAA==.Alexyss:BAAALgAECgUJDgAAAA==.Alykard:BAABLgAECn8xAAIEAAkJwhFgSAD8AQAEAAkJwhFgSAD8AQAAAA==.',
Am='Amyara:BAAALgAECgEJAQAAAA==.',
An='Andronicas:BAABLgAECn8mAAMFAAkJ6hIFQQD5AQAFAAkJ6hIFQQD5AQAGAAEJogevnAAtAAAAAA==.Aneira:BAABLgAFFH8dAAIEAAQJHAkuYwAZAQAEAAQJHAkuYwAZAQAAAA==.',
Ap='Apexis:BAAALgADCgYJCQAAAA==.',
Ar='Ariaa:BAAALgAECgYJEgAAAA==.Arieyri:BAAALgADCgcJBwAAAA==.Artpop:BAAALgAFFAEJAQABLgAFFAYJFQAHAK0TAA==.',
As='Ash:BAAALgADCgcJCwAAAA==.Ashvira:BAAALgAECgQJBAAAAA==.Aspect:BAAALgADCgcJDgABLgAECgEJAQACAAAAAA==.Astarael:BAABLgAECn8iAAMIAAkJShepHwDAAQAIAAgJGhapHwDAAQADAAcJLQ6GTgCWAAAAAA==.',
Av='Avi:BAABLgAECn8oAAIBAAkJUhUbEQBUAgABAAkJUhUbEQBUAgABLgAECgkJcQAJAHggAA==.',
Ba='Babygurl:BAACLgAFFH8FAAIGAAMJNx9rIgAAAQAGAAMJNx9rIgAAAQAuAAQKf3YAAgYACQntJfsBAIwDAAYACQntJfsBAIwDAAAA.Baragas:BAAALgAECgYJDgAAAA==.Bareback:BAAALgAECgQJBAAAAA==.Barney:BAAALgADCgEJAQAAAA==.Battosaî:BAAALgAECgQJBAAAAA==.',
Be='Beeny:BAACLgAFFH80AAIHAAgJCCNNAgABAwAHAAgJCCNNAgABAwAuAAQKf0EAAwcACQlpI4UIAMwCAAcACQlpI4UIAMwCAAoAAQlsECaSADMAAAAA.Belle:BAACLgAFFH8ZAAMLAAgJxBZqDgAfAgALAAgJxBZqDgAfAgAMAAEJ8Bc/DABWAAAuAAQKfy0AAwsACAnFJhIEAIgDAAsACAmFJhIEAIgDAAwABwk+IFIOAH4CAAAA.Berat:BAAALgADCgQJBAAAAA==.Berzerker:BAAALgADCgcJEwAAAA==.',
Bg='Bgc:BAAALgADCgUJBQAAAA==.',
Bi='Binari:BAAALgAECgMJAwABLgAFFAMJBQAJACoUAA==.Binlock:BAAALgAECgQJBAABLgAFFAMJBQAJACoUAA==.',
Bl='Bl:BAAALgAECgMJAwAAAA==.Bladebear:BAABLgAECn82AAIEAAkJUxUvSQD5AQAEAAkJUxUvSQD5AQAAAA==.',
Bo='Boose:BAAALgAECgYJBgAAAA==.Bootybreaker:BAAALgADCgcJBwAAAA==.',
Br='Brat:BAAALgAECgEJBAABLgAECgkJVQADAC4VAA==.Brewingmist:BAAALgAECgUJBQABLgAFFAMJBQANAEUTAA==.Bréwmaster:BAAALgAECgcJDgABLgAECgkJIgAIAEoXAA==.',
Bu='Bubbelz:BAAALgAECgMJAwAAAA==.Bubbleez:BAAALgADCgUJBQAAAA==.Bubblôseven:BAAALgAECgEJAQAAAA==.Bucklord:BAABLgAECn8iAAMIAAgJjRkAFwAuAgAIAAgJjRkAFwAuAgADAAEJABnXZgA7AAAAAA==.Budin:BAAALgAECggJEgAAAA==.Bullmann:BAAALgADCgQJBAAAAA==.',
Ca='Cannibal:BAABLgAECn89AAIOAAkJahzGDgDXAgAOAAkJahzGDgDXAgAAAA==.Caplock:BAABLgAECn8VAAIPAAYJoRFohABRAQAPAAYJoRFohABRAQAAAA==.Capri:BAAALgAECgYJEgAAAA==.',
Ce='Cellun:BAAALgAECgUJEwAAAA==.Centipede:BAAALgAECgYJCQABLgAECgYJFwAQAIAXAA==.Ceredis:BAAALgAECgUJCwAAAA==.',
Ch='Choomoo:BAAALgADCgcJCwAAAA==.',
Cl='Cleankarma:BAAALgADCgEJAwAAAA==.',
Co='Comet:BAAALgAECgEJAQAAAA==.Cool:BAABLgAFFH8FAAIFAAMJ1BM7YADaAAAFAAMJ1BM7YADaAAAAAA==.Corwiggs:BAAALgAECgYJCwAAAA==.',
Cr='Crikey:BAAALgAECgYJDAAAAA==.Crimínal:BAAALgADCgcJCwAAAA==.Cripsee:BAAALgADCgMJAwAAAA==.',
Cu='Curbie:BAAALgAECgIJAwAAAA==.',
Cv='Cvdruid:BAAALgAECgUJBQAAAA==.',
Cy='Cyndrixx:BAAALgAECgIJAwAAAA==.',
['Cô']='Cônvict:BAAALgADCgYJBgAAAA==.',
Da='Dargath:BAAALgAECgMJBAAAAA==.',
De='Deacknight:BAABLgAECn8cAAMNAAgJwRuPLgB+AgANAAgJwRuPLgB+AgARAAEJig2BFwAyAAABLgADCgYJBwACAAAAAA==.Deacmonk:BAAALgADCgYJBgABLgADCgYJBwACAAAAAA==.Definitely:BAACLgAFFH8SAAIEAAMJgiMVXgAkAQAEAAMJgiMVXgAkAQAuAAQKfzsAAwQACQlCJKoKAB8DAAQACQlCJKoKAB8DABIAAQkPICobAD8AAAAA.Deki:BAEALgAECgYJBgABLgAFFAYJFgAFAG4aAA==.Dementiaous:BAAALgAECgIJAwAAAA==.Desariana:BAABLgAECn8lAAIFAAkJcxDuXgCpAQAFAAkJcxDuXgCpAQAAAA==.',
Di='Diggitie:BAAALgAECgEJAQAAAA==.Ditto:BAABLgAFFH8NAAIHAAUJMQ24LQDbAAAHAAUJMQ24LQDbAAAAAA==.',
Do='Domtop:BAABLgAFFH8FAAMTAAMJXAEzNQBNAAATAAIJTwEzNQBNAAARAAEJdgGLJwAuAAABLgAFFAYJFQAHAK0TAA==.Dormas:BAABLgAECn8YAAIUAAcJ3g+HKAAAAQAUAAcJ3g+HKAAAAQAAAA==.Doug:BAAALgADCgEJAQAAAA==.Doxy:BAAALgAECgcJCQAAAA==.',
Dr='Drakeon:BAABLgAECn8UAAIVAAcJ/g5WFgBhAQAVAAcJ/g5WFgBhAQABLgAECgkJcQAJAHggAA==.',
Ee='Eeryxx:BAAALgAECgEJAQAAAA==.',
El='Eldh:BAABLgAECn8kAAMWAAkJLBH3IQCQAQAWAAkJ5w33IQCQAQAKAAEJYiQWbABrAAAAAA==.Eleison:BAAALgADCgMJAwAAAA==.Elendrial:BAAALgAECgIJAgAAAA==.Elendril:BAAALgADCgcJFQAAAA==.Elisoly:BAACLgAFFH8FAAIGAAIJDQzwOwBnAAAGAAIJDQzwOwBnAAAuAAQKfyUAAgYABgmCHl4fAP0BAAYABgmCHl4fAP0BAAAA.',
Em='Emrald:BAAALgAECgYJEwAAAA==.Emridius:BAAALgAECgEJAgABLgAECggJIAAJAGMgAA==.',
En='Endlessly:BAACLgAFFH8QAAIXAAUJ3hRJBwAoAQAXAAUJ3hRJBwAoAQAuAAQKfyIAAhcACAmfIukDAOsCABcACAmfIukDAOsCAAAA.Enerchi:BAAALgADCgMJAwAAAA==.',
Er='Erivoker:BAAALgAECgYJDAABLgAECgYJEgACAAAAAA==.Errimage:BAAALgAECgYJEgAAAA==.Errishoot:BAAALgAECgUJCQABLgAECgYJEgACAAAAAA==.Ervinia:BAAALgADCgYJCgABLgAECgYJEwACAAAAAA==.',
Ev='Evelinar:BAAALgAECgMJAwAAAA==.Evoslex:BAABLgAECn85AAMYAAkJxCOMBAAYAwAYAAkJxCOMBAAYAwAZAAYJzx1vEwCsAQAAAA==.',
Ex='Exo:BAECLgAFFH8jAAITAAcJIhq3CADZAQATAAcJIhq3CADZAQAuAAQKfysAAhMACQkcIkIEAOsCABMACQkcIkIEAOsCAAAA.',
Fa='Facerolleh:BAACLgAFFH8wAAMaAAgJ+CG4AQCSAgAaAAgJsyG4AQCSAgAJAAQJZiGMBgCGAQAuAAQKf0YABAkACQmdJc4EAFwDAAkACAn2Jc4EAFwDABoACAl/Iq0FAJ8CABsAAgmNHXhFAFAAAAAA.Fatedx:BAAALgAECgEJAQAAAA==.',
Fe='Feelgoodinc:BAAALgADCgkJFAAAAA==.',
Fi='Fidah:BAAALgAECgEJAQAAAA==.Firemagemain:BAAALgADCgUJBQABLgAFFAMJBQAJACoUAA==.',
Fl='Flanann:BAAALgAECgEJAQABLgAECgMJDAACAAAAAA==.Flop:BAAALgAECgUJCQABLgAFFAUJDwAEAJIbAA==.Flora:BAAALgAECgEJAwAAAA==.',
Fr='Frostmere:BAAALgADCggJGQAAAA==.',
Fu='Fuknazum:BAAALgAECgEJAQAAAA==.Furcht:BAABLgAECn8cAAINAAYJGhN+ogAfAQANAAYJGhN+ogAfAQAAAA==.',
Ga='Galadar:BAAALgADCgUJBQAAAA==.',
Gi='Giteff:BAABLgAFFH8iAAILAAkJRSSGAABcAwALAAkJRSSGAABcAwAAAA==.Gitèff:BAABLgAFFH8XAAILAAcJAiOsBwBzAgALAAcJAiOsBwBzAgABLgAFFAkJIgALAEUkAA==.Giveroflife:BAAALgAECgYJEAAAAA==.',
Go='Gourdin:BAAALgAECgQJBQABLgAECgYJCAACAAAAAA==.',
Gr='Gramnpa:BAAALgADCgUJBQAAAA==.Grandpriest:BAAALgAECgQJBwABLgAECgYJBgACAAAAAA==.Gravepriest:BAAALgAECgEJAQAAAA==.Grimtysha:BAAALgAECgYJEAAAAA==.Grimveil:BAAALgAECgYJDQAAAA==.Gromit:BAAALgAECgQJCQAAAA==.Gröuch:BAABLgAFFH8IAAIWAAQJXQrDKgDzAAAWAAQJXQrDKgDzAAAAAA==.',
Ha='Harafar:BAACLgAFFH8FAAIcAAUJEATbMACoAAAcAAUJEATbMACoAAAuAAQKfx4AAxwACQnuGRoNAHwCABwACQnuGRoNAHwCAA4AAwl7B0GbAHAAAAAA.Hate:BAAALgAECgYJDAABLgAFFAcJGQAEALcWAA==.',
He='Hellbourne:BAABLgAECn8kAAILAAkJ8hj9JgAlAgALAAkJ8hj9JgAlAgAAAA==.',
Hi='Himmel:BAAALgADCgcJCQAAAA==.',
Ho='Hopnhorsé:BAAALgAECgQJBQAAAA==.Hotchoq:BAABLgAFFH8IAAIEAAIJJg4YlwCTAAAEAAIJJg4YlwCTAAAAAA==.',
Hu='Huntchoq:BAABLgAFFH8PAAQdAAYJZgwGFQAYAQAdAAUJTg0GFQAYAQAeAAMJ1wo5YADNAAAfAAIJdAnYIgB5AAAAAA==.Huxley:BAAALgADCgMJAwAAAA==.',
Ik='Ikan:BAAALgAECgYJEQAAAA==.',
In='Infest:BAAALgAECgQJCAAAAA==.Inzolethys:BAAALgADCgcJBwAAAA==.',
It='Itchy:BAAALgADCgEJAgAAAA==.Itskiohte:BAABLgAECn8pAAIgAAkJVw6tDgC5AQAgAAkJVw6tDgC5AQAAAA==.',
Ja='Jaggernut:BAAALgADCgUJBQAAAA==.',
Ji='Jimmbo:BAAALgAECgQJBAAAAA==.',
Jo='Johnny:BAAALgAECgIJAgABLgAECgkJOQAYAMQjAA==.',
Ju='Judeau:BAAALgADCgEJAQAAAA==.',
Ka='Kaelthuzzad:BAAALgADCgEJAQAAAA==.Kaitza:BAAALgAECgYJCwAAAA==.Kalzaketh:BAABLgAECn9BAAMYAAkJ7gu7MwBZAQAYAAkJ7gu7MwBZAQAZAAMJ5QSIMwB5AAAAAA==.Kashari:BAAALgAECgYJCwABLgAECgkJfgAIABUcAA==.Katali:BAABLgAECn8VAAMFAAcJSQw8oQAqAQAFAAcJSQw8oQAqAQAGAAYJCwXxVwDLAAAAAA==.Kazuggar:BAACLgAFFH8eAAIQAAUJ+iJCDQDjAQAQAAUJ+iJCDQDjAQAuAAQKfzgAAxAACQmsJW4CAFwDABAACAmCJW4CAFwDACEABgkAFbgwAG4BAAAA.Kazzn:BAAALgAFFAMJAwAAAA==.',
Ke='Kedar:BAAALgAECgYJEQAAAA==.Keg:BAAALgAECgIJAgAAAA==.Kelabar:BAAALgADCgQJBAAAAA==.',
Ki='Kick:BAAALgADCgQJBAABLgAFFAcJGQAEALcWAA==.Kiffs:BAAALgAECgcJCgAAAA==.Kill:BAAALgAFFAEJAgAAAA==.Killerman:BAABLgAFFH8eAAQRAAgJhCNKAQA2AgARAAYJWCVKAQA2AgANAAUJXx9EMQCIAQATAAMJixgzIQDQAAAAAA==.Kirâ:BAABLgAECn8UAAIJAAgJCxxmGwAMAgAJAAgJCxxmGwAMAgABLgAECgcJEwACAAAAAA==.',
Kr='Kregnar:BAABLgAECn8pAAIaAAkJBRxUBwB4AgAaAAkJBRxUBwB4AgAAAA==.Kresh:BAAALgAECgcJCwAAAA==.',
Ku='Kucabara:BAAALgAECgIJAwAAAA==.Kuraiwiggs:BAAALgADCgYJDAAAAA==.',
Kw='Kwichang:BAABLgAECn8ZAAIEAAcJuw8jjgBWAQAEAAcJuw8jjgBWAQAAAA==.',
Ky='Kyndariae:BAAALgAECgUJBQAAAA==.',
['Ké']='Kélpo:BAAALgADCgMJBAAAAA==.',
La='Lasagne:BAAALgADCgMJAwAAAA==.',
Le='Leatherkink:BAAALgAFFAQJBAABLgAFFAYJFQAHAK0TAA==.Lesley:BAAALgAECgEJAQAAAA==.',
Li='Lickynose:BAABLgAECn8vAAMEAAkJVSKEDgABAwAEAAkJVSKEDgABAwAiAAEJEiChDgBeAAAAAA==.Lips:BAAALgAECgEJAQAAAA==.',
Ls='Ls:BAABLgAECn8iAAQMAAkJaiPBCACSAgAMAAgJ3R/BCACSAgALAAgJnCG9MQAzAgAjAAcJYhVjDQBtAQAAAA==.',
Ly='Lythium:BAAALgAECggJCQAAAA==.',
Ma='Madarabia:BAAALgAECgYJDQAAAA==.Magnius:BAAALgAECgMJAwAAAA==.Makcik:BAAALgAECgEJAQAAAA==.Mamut:BAAALgAECgEJAQAAAA==.Mantisar:BAACLgAFFH8IAAIFAAMJ5RJ4YQDYAAAFAAMJ5RJ4YQDYAAAuAAQKfx4AAgUABwnmHks5ABICAAUABwnmHks5ABICAAAA.Mattdemonn:BAAALgADCgQJBAAAAA==.Maxsm:BAABLgAECn8XAAIhAAgJrhmSIQACAgAhAAgJrhmSIQACAgAAAA==.',
Me='Melanippe:BAABLgAECn8XAAIOAAYJDxtuPQCuAQAOAAYJDxtuPQCuAQAAAA==.Meleefox:BAAALgADCgUJBQAAAA==.Melethron:BAABLgAECn8+AAIFAAkJgRwHJABrAgAFAAkJgRwHJABrAgAAAA==.Melioknky:BAAALgAECgYJBgAAAA==.',
Mi='Michaeljfox:BAAALgAECgQJBAAAAA==.Mid:BAAALgADCgYJBgAAAA==.Mightymage:BAABLgAECn8hAAIEAAgJ4Q0SfwBzAQAEAAgJ4Q0SfwBzAQAAAA==.Millionbaby:BAAALgAECgEJAQAAAA==.Milliondruid:BAAALgAECgMJBAAAAA==.Millionsm:BAAALgADCgQJBQAAAA==.Mirrorimage:BAABLgAFFH8GAAIIAAIJSwdoKwCIAAAIAAIJSwdoKwCIAAABLgAFFAYJEgAIAAgVAA==.Mirrorx:BAACLgAFFH8SAAIIAAYJCBVKDgBrAQAIAAYJCBVKDgBrAQAuAAQKfzIAAggACQlzIH8IAMICAAgACQlzIH8IAMICAAAA.Miy:BAAALgAECgEJAQAAAA==.',
Mo='Mongon:BAAALgAECgYJBgAAAA==.Moogle:BAAALgAECgIJBAAAAA==.Moomie:BAABLgAECn8iAAIOAAgJAxYqNgC3AQAOAAgJAxYqNgC3AQAAAA==.Moosfel:BAABLgAECn8jAAIXAAcJGhosDgDBAQAXAAcJGhosDgDBAQAAAA==.',
Mt='Mtzz:BAAALgAECgUJBQABLgAECgYJCAACAAAAAA==.',
Mu='Mudcake:BAAALgAECgEJAQAAAA==.',
My='Mygravebroke:BAAALgADCggJCQAAAA==.Mystdragon:BAACLgAFFH8UAAMVAAUJxRsWEAB8AQAVAAUJxRsWEAB8AQAYAAMJbQ4iPADFAAAuAAQKfzAAAhUACQm5IUsDABEDABUACQm5IUsDABEDAAEuAAUUCAknAAcAmh0A.Mystweaverr:BAACLgAFFH8nAAMHAAgJmh0eBAC9AgAHAAgJmh0eBAC9AgAKAAEJ9QS4PwA3AAAuAAQKfy8AAwcACQn3H4AJALkCAAcACQn3H4AJALkCAAoAAgkjItdRALQAAAAA.',
['Mö']='Mörae:BAAALgADCgEJAQABLgAECgYJFwAOAA8bAA==.',
Na='Naddar:BAACLgAFFH8SAAIGAAUJpxkvFQByAQAGAAUJpxkvFQByAQAuAAQKf0wAAgYACQnSHxkGACMDAAYACQnSHxkGACMDAAAA.Namadgi:BAABLgAECn8nAAIOAAkJnBs7EQC9AgAOAAkJnBs7EQC9AgAAAA==.Nathria:BAAALgAECgIJAwAAAA==.',
Ne='Netalis:BAABLgAECn8lAAIOAAgJwxSqLwDbAQAOAAgJwxSqLwDbAQAAAA==.',
Ni='Nikonii:BAAALgAECgEJAQAAAA==.',
Nu='Nurckers:BAAALgAECgcJCAAAAA==.',
Oa='Oakinelf:BAAALgADCgcJAQAAAA==.',
Om='Omnishifts:BAAALgAECgEJAgAAAA==.',
Or='Oramo:BAABLgAECn8fAAMTAAgJfCMmBQDwAgATAAgJxSImBQDwAgANAAYJgCJoaACNAQAAAA==.',
Ov='Ovaries:BAAALgADCgUJBQABLgAECgQJBwACAAAAAA==.',
Pa='Paktam:BAACLgAFFH8GAAIQAAMJvRU+RADFAAAQAAMJvRU+RADFAAAuAAQKfxcAAhAABwnOHZocAFoCABAABwnOHZocAFoCAAAA.Paméla:BAAALgAECgcJDwABLgAECgkJcQAJAHggAA==.Paradisya:BAAALgADCggJDgAAAA==.',
Pe='Perceptor:BAAALgAECgEJAQABLgAECgkJKQAUAJMhAA==.Pets:BAAALgAECgEJAQABLgAECgkJVQADAC4VAA==.',
Pl='Placebo:BAAALgAECgUJBQABLgAFFAUJEAAXAN4UAA==.',
Pr='Prothero:BAACLgAFFH8WAAMEAAYJpCG8HQDyAQAEAAYJpCG8HQDyAQASAAEJZRluBQBGAAAuAAQKfxYAAwQACQnGIFQYAMECAAQACQnGIFQYAMECABIACAkrGAMDAFACAAAA.Proyo:BAAALgADCgUJBQAAAA==.',
['På']='Påthor:BAACLgAFFH8HAAIcAAIJkw9AOQB4AAAcAAIJkw9AOQB4AAAuAAQKfyMAAxwABwl6HHMfAL4BABwABwl6HHMfAL4BABQAAwkSEhlRAFsAAAAA.',
Ra='Raikonnen:BAAALgAECgEJAQAAAA==.Rapidstrikes:BAAALgAECgMJBAAAAA==.Rawtoor:BAACLgAFFH8fAAILAAcJYReIGgC7AQALAAcJYReIGgC7AQAuAAQKfyEAAgsACAk4IdInAGUCAAsACAk4IdInAGUCAAAA.',
Re='Rebelsister:BAAALgADCgcJEAAAAA==.Refridgerate:BAAALgADCgUJBwAAAA==.',
Ri='Riddagain:BAABLgAECn8bAAMjAAYJeA/1FAAHAQAjAAYJTw/1FAAHAQALAAIJwAvBDgErAAAAAA==.Ridgemonk:BAABLgAECn87AAMWAAkJniMVAgA9AwAWAAkJniMVAgA9AwAHAAQJQAGYYABMAAAAAA==.Riggsdk:BAAALgADCgcJBwABLgAFFAgJGwAeAKAiAA==.Riggse:BAAALgAFFAEJAQABLgAFFAgJGwAeAKAiAA==.Riggshunt:BAACLgAFFH8bAAQeAAgJoCLTAACrAQAdAAYJLCQuAAD7AQAeAAYJ8SDTAACrAQAfAAEJAAC/KABKAAAuAAQKfx4ABB4ACAmrJr0IAAcDAB4ABwmYJr0IAAcDAB0ACAmTJIQDAPICAB8AAQmCHGd9AE8AAAAA.Riggspal:BAAALgAFFAIJAgABLgAFFAgJGwAeAKAiAA==.Riggswar:BAABLgAFFH8GAAMJAAUJYB26RwBVAAAJAAQJ+Bu6RwBVAAAaAAIJ0xoAAAAAAAABLgAFFAgJGwAeAKAiAA==.Riggzs:BAAALgAFFAIJAgABLgAFFAgJGwAeAKAiAA==.',
Ro='Roadkill:BAABLgAECn8gAAITAAgJnSM4BAALAwATAAgJnSM4BAALAwAAAA==.Rolltoor:BAABLgAFFH8FAAIKAAMJJRYhHQDgAAAKAAMJJRYhHQDgAAAAAA==.Roonate:BAAALgADCgUJBQAAAA==.Rosemary:BAAALgAECgQJBAAAAA==.',
Ry='Ryujin:BAAALgAECgQJCQAAAA==.',
Sa='Saiko:BAABLgAFFH8UAAIMAAYJuBemBgCDAQAMAAYJuBemBgCDAQAAAA==.Sansa:BAACLgAFFH8ZAAIdAAgJPRj/AABfAgAdAAgJPRj/AABfAgAuAAQKfyMAAh0ACQlnI00CACMDAB0ACQlnI00CACMDAAAA.Saso:BAACLgAFFH8WAAIEAAYJ2xzdIgDUAQAEAAYJ2xzdIgDUAQAuAAQKfzkABAQACQmVIn4RAOwCAAQACQmUIn4RAOwCABIABglXI+sDAL4BACIAAgnECLALAHcAAAAA.Sastroll:BAAALgAECgUJBQAAAA==.',
Sc='Scorn:BAAALgADCgcJCAAAAA==.Scroll:BAABLgAECn8bAAIHAAgJPBqkGwAnAgAHAAgJPBqkGwAnAgAAAA==.',
Se='Seluvis:BAABLgAECn8WAAIEAAcJ0QH2AgGdAAAEAAcJ0QH2AgGdAAAAAA==.Sentai:BAAALgADCgcJBwAAAA==.Serapayne:BAAALgAECgcJAQAAAA==.Serbitar:BAAALgAECgEJAQAAAA==.',
Sh='Shadow:BAACLgAFFH8cAAILAAcJxxSCFwDTAQALAAcJxxSCFwDTAQAuAAQKf18AAgsACQmbJG4DAEkDAAsACQmbJG4DAEkDAAAA.Shandrilah:BAAALgADCgQJBAAAAA==.Shapeshift:BAAALgADCgUJBQABLgAECgIJAgACAAAAAA==.Shialebuff:BAABLgAECn9IAAQIAAkJZhzkDAB+AgAIAAkJZhzkDAB+AgADAAkJzB+6EQBGAgABAAQJFxkmNwApAQAAAA==.Shijin:BAAALgAECgQJBwAAAA==.Shortfuze:BAAALgAECgYJDQAAAA==.',
Si='Sindar:BAAALgADCgUJBQAAAA==.Sinfall:BAAALgAECggJDgAAAA==.Siphon:BAAALgAECgEJAwAAAA==.Siscomp:BAABLgAECn9xAAIJAAkJeCCMDwB3AgAJAAkJeCCMDwB3AgAAAA==.Sixth:BAABLgAECn8XAAIhAAcJ/BoNJQCyAQAhAAcJ/BoNJQCyAQAAAA==.Sizzle:BAAALgADCgMJAwAAAA==.',
Sk='Skateboard:BAAALgADCgEJAQAAAA==.Sky:BAACLgAFFH8lAAIBAAcJgx8tBQC+AgABAAcJgx8tBQC+AgAuAAQKfxQAAwEACAlxE48cALABAAEABwlZEo8cALABAAMABQnyD4hMAAYBAAAA.',
Sl='Sleck:BAAALgAECgYJDAAAAA==.',
Sm='Smooth:BAAALgAECgEJAQABLgAFFAYJCAABAEcTAA==.',
Sn='Snappa:BAAALgADCgYJCwAAAA==.Sniped:BAAALgAFFAEJAQAAAA==.Snugglepuff:BAAALgAECgkJEwAAAA==.',
So='Soapfidas:BAAALgADCggJCgAAAA==.Sonarius:BAACLgAFFH8PAAIEAAUJkhtzRABSAQAEAAUJkhtzRABSAQAuAAQKfx0ABAQACAndHyk8AIYCAAQACAndHyk8AIYCABIAAgkCHW8MAKQAACIAAQmyEg8PADwAAAAA.Sophie:BAAALgAECgEJAwAAAA==.',
Sp='Splitterman:BAABLgAFFH8SAAQTAAcJJSBtBAA6AgATAAcJJSBtBAA6AgARAAUJ+hdtCgAyAQANAAEJkQHQDAEvAAAAAA==.',
Su='Su:BAABLgAECn8yAAIHAAcJ4yVlBwDiAgAHAAcJ4yVlBwDiAgAAAA==.Sudno:BAAALgAECgQJCAABLgAFFAcJGwAPAPAYAA==.Sundae:BAABLgAECn83AAQDAAkJlSEOCADeAgADAAgJHCMOCADeAgABAAgJhxuYDQCIAgAIAAMJ3BY9UQDBAAAAAA==.Sunwukong:BAAALgAECgUJCQAAAA==.Supersinpe:BAAALgAECgIJAgAAAA==.',
Sv='Svdrag:BAAALgAECgMJAwAAAA==.Svendlefyre:BAAALgADCgcJDgABLgAECgkJLgAXAIMZAA==.Svholydrag:BAAALgADCgEJAQAAAA==.Svmishima:BAAALgAECgMJBQAAAA==.',
Sw='Swirly:BAAALgAECgEJAQAAAA==.',
Sy='Sylvie:BAABLgAECn8nAAIeAAkJwRXJJgA5AgAeAAkJwRXJJgA5AgAAAA==.',
['Sý']='Sýlvanas:BAABLgAECn8UAAIfAAUJVxNxFwDsAAAfAAUJVxNxFwDsAAAAAA==.',
Te='Tealç:BAABLgAECn8gAAIbAAcJpheVGACQAQAbAAcJpheVGACQAQABLgAFFAQJGAAbAEcfAA==.Tekk:BAAALgAECgEJAQAAAA==.Tekkys:BAAALgAECgEJAgAAAA==.Tertle:BAAALgADCgUJBQAAAA==.',
Ti='Tiafinia:BAAALgAECgEJAgAAAA==.Tiggerstripe:BAAALgADCgEJAQABLgAECgkJMQAgAEMQAA==.Timmyy:BAAALgAECgYJBgABLgAFFAQJCAANAN4MAA==.Timur:BAAALgAECgMJBAAAAA==.Tinara:BAAALgADCgUJBQAAAA==.',
To='Tome:BAAALgAECgEJAQABLgAECggJGwAHADwaAA==.',
Tr='Trigger:BAAALgAECgIJAgAAAA==.',
Tu='Turlesblows:BAABLgAECn8gAAMJAAgJYyAgIwDUAQAJAAgJYyAgIwDUAQAbAAEJOxWZRAA7AAAAAA==.',
Tw='Twityy:BAAALgADCgEJAgAAAA==.Twofiveyd:BAABLgAFFH8FAAIYAAQJjA9hMAD1AAAYAAQJjA9hMAD1AAABLgAFFAYJFAAaAGcYAA==.',
Ty='Tyladrhas:BAABLgAECn80AAIjAAkJVB9yAwCYAgAjAAkJVB9yAwCYAgAAAA==.Tyrismaximus:BAAALgAECgQJBgAAAA==.',
Ul='Ulkina:BAAALgADCgYJCQAAAA==.',
Va='Vaelith:BAAALgAECgIJAgAAAA==.Vaelyth:BAAALgAECgcJBwAAAA==.Valerine:BAABLgAECn8aAAIEAAkJ/wr4eACAAQAEAAkJ/wr4eACAAQAAAA==.Vanoran:BAAALgAECgMJBAAAAA==.Varina:BAAALgAECgcJEwAAAA==.',
Ve='Velsaert:BAAALgAECgEJAQAAAA==.Venki:BAAALgAECgkJDAAAAA==.',
Vi='Vitani:BAAALgADCgIJAgABLgAFFAUJEAAXAN4UAA==.',
Vo='Voidnova:BAABLgAFFH8HAAIEAAMJlRC0fgDUAAAEAAMJlRC0fgDUAAAAAA==.Voidphayze:BAAALgAECgUJDAABLgAFFAMJBQANAEUTAA==.',
Vu='Vulken:BAABLgAECn9nAAIeAAkJESW/DQDaAgAeAAkJESW/DQDaAgAAAA==.',
['Vê']='Vê:BAAALgAECgkJEQAAAA==.',
Wa='Wallace:BAAALgAECgcJDAAAAA==.Walterlight:BAAALgAECgYJDgAAAA==.Watto:BAABLgAECn8ZAAMQAAkJOR/FFQCQAgAQAAkJOR/FFQCQAgAhAAUJmRYxRgALAQABLgAFFAMJBQANAGMPAA==.',
We='Wemongin:BAAALgADCgUJBQAAAA==.',
Wh='Whimsical:BAABLgAECn8XAAIQAAYJgBf/TABuAQAQAAYJgBf/TABuAQAAAA==.',
Wi='Winnìng:BAABLgAECn8jAAIkAAkJLQx7GQBBAQAkAAkJLQx7GQBBAQAAAA==.',
Wu='Wugong:BAAALgADCgEJAQAAAA==.',
['Wó']='Wórkwórk:BAACLgAFFH8FAAIJAAMJKhROFwCsAAAJAAMJKhROFwCsAAAuAAQKfxsAAwkACQk6Gxg3AMsBAAkABwnRGRg3AMsBABoAAwnsGr8fAO8AAAAA.',
Ze='Zerg:BAAALgAECgIJAgAAAA==.',
Zi='Zich:BAAALgADCgMJAwAAAA==.Zihon:BAABLgAECn8UAAINAAQJTxqO4wDEAAANAAQJTxqO4wDEAAAAAA==.',
Zo='Zodiiak:BAABLgAECn9EAAIgAAkJMR18BgBkAgAgAAkJMR18BgBkAgAAAA==.',
Zu='Zubb:BAAALgADCgYJCQABLgAECggJEAACAAAAAA==.Zugg:BAAALgAECgIJAgABLgAECggJEAACAAAAAA==.Zuhh:BAAALgAECgEJAgABLgAECggJEAACAAAAAA==.Zupp:BAAALgAECggJEAAAAA==.',
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
