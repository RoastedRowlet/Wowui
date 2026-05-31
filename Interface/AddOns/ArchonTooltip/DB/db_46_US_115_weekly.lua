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

local lookup = {'Priest-Discipline','Unknown-Unknown','Priest-Holy','Mage-Frost','Paladin-Retribution','Paladin-Holy','Monk-Mistweaver','Priest-Shadow','Warrior-Fury','Monk-Windwalker','DemonHunter-Devourer','DemonHunter-Havoc','DeathKnight-Unholy','Druid-Restoration','Warlock-Demonology','Shaman-Restoration','DeathKnight-Frost','Mage-Arcane','Druid-Balance','Druid-Guardian','Evoker-Preservation','Monk-Brewmaster','Druid-Feral','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Blood','Warrior-Arms','Warrior-Protection','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Enhancement','Shaman-Elemental','DemonHunter-Vengeance','Mage-Fire','Paladin-Protection',}
local provider = {region='US',realm='Gundrak',name='US',type='weekly',zone=46,date='2026-05-30',data={Ad='Adelyne:BAAALgAFFAIJAgABLgAFFAUJDgABAG0SAA==.Adera:BAAALgAECgYJBwAAAA==.',
Af='Aff:BAAALgADCgYJBgAAAA==.',
Ag='Agony:BAAALgAECgQJBgAAAA==.',
Ah='Ahkanon:BAAALgADCgEJAQAAAA==.',
Ai='Aiden:BAAALgAECgEJAgABLgAECgIJAgACAAAAAA==.Aidendk:BAAALgADCgIJAgABLgAECgIJAgACAAAAAA==.Aidenp:BAAALgADCgIJAgABLgAECgIJAgACAAAAAA==.Air:BAAALgADCgcJBwABLgAFFAgJIgADADkbAA==.',
Ak='Aku:BAAALgADCgIJBAAAAA==.',
Al='Aleniastra:BAAALgAECgYJEwAAAA==.Alexyss:BAAALgAECgUJDgAAAA==.Alykard:BAABLgAECn8xAAIEAAkJwhEORAD4AQAEAAkJwhEORAD4AQAAAA==.',
Am='Amyara:BAAALgAECgEJAQAAAA==.',
An='Andronicas:BAABLgAECn8gAAMFAAkJqw6jXACfAQAFAAkJqw6jXACfAQAGAAEJogevnAAtAAAAAA==.Aneira:BAABLgAFFH8YAAIEAAQJHglxXwARAQAEAAQJHglxXwARAQAAAA==.',
Ap='Apexis:BAAALgADCgYJCQAAAA==.',
Ar='Ariaa:BAAALgAECgUJCwAAAA==.Arieyri:BAAALgADCgcJBwAAAA==.Artpop:BAAALgAFFAEJAQABLgAFFAYJEAAHALISAA==.',
As='Ash:BAAALgADCgcJCwAAAA==.Ashvira:BAAALgAECgQJBAAAAA==.Aspect:BAAALgADCgcJDgABLgAECgEJAQACAAAAAA==.Astarael:BAABLgAECn8iAAMIAAkJSheUHQC6AQAIAAgJGhaUHQC6AQADAAcJLQ7mSwCYAAAAAA==.',
Av='Avi:BAABLgAECn8oAAIBAAkJUhWpDwBVAgABAAkJUhWpDwBVAgABLgAECgkJcAAJAHggAA==.',
Ba='Babygurl:BAACLgAFFH8FAAIGAAMJNx80IAAFAQAGAAMJNx80IAAFAQAuAAQKf3YAAgYACQntJasBAJADAAYACQntJasBAJADAAAA.Baragas:BAAALgAECgYJDQAAAA==.Bareback:BAAALgAECgQJBAAAAA==.Barney:BAAALgADCgEJAQAAAA==.Battosaî:BAAALgAECgQJBAAAAA==.',
Be='Beeny:BAACLgAFFH80AAIHAAgJCCNiAQAWAwAHAAgJCCNiAQAWAwAuAAQKf0EAAwcACQlpI4UIAMwCAAcACQlpI4UIAMwCAAoAAQlsEDGJADUAAAAA.Belle:BAACLgAFFH8ZAAMLAAgJxBZaCgAtAgALAAgJxBZaCgAtAgAMAAEJ8Bc/DABWAAAuAAQKfy0AAwsACAnFJhIEAIgDAAsACAmFJhIEAIgDAAwABwk+IFIOAH4CAAAA.Berat:BAAALgADCgQJBAAAAA==.Berzerker:BAAALgADCgcJEwAAAA==.',
Bg='Bgc:BAAALgADCgUJBQAAAA==.',
Bi='Binari:BAAALgAECgMJAwABLgAFFAMJBQAJACoUAA==.Binlock:BAAALgAECgQJBAABLgAFFAMJBQAJACoUAA==.',
Bl='Bl:BAAALgAECgMJAwAAAA==.Bladebear:BAABLgAECn82AAIEAAkJUxUSRQD1AQAEAAkJUxUSRQD1AQAAAA==.',
Bo='Boose:BAAALgAECgYJBgAAAA==.Bootybreaker:BAAALgADCgcJBwAAAA==.',
Br='Brat:BAAALgAECgEJBAABLgAECgkJUwADAPwUAA==.Brewingmist:BAAALgAECgUJBQABLgAFFAMJBQANAEUTAA==.Bréwmaster:BAAALgAECgcJCAABLgAECgkJIgAIAEoXAA==.',
Bu='Bubbelz:BAAALgAECgMJAwAAAA==.Bubbleez:BAAALgADCgUJBQAAAA==.Bubblôseven:BAAALgAECgEJAQAAAA==.Bucklord:BAABLgAECn8iAAMIAAgJjRkAFwAuAgAIAAgJjRkAFwAuAgADAAEJABmiYgA8AAAAAA==.Budin:BAAALgAECggJEgAAAA==.Bullmann:BAAALgADCgQJBAAAAA==.',
Ca='Cannibal:BAABLgAECn80AAIOAAkJLhyNDgDRAgAOAAkJLhyNDgDRAgAAAA==.Caplock:BAABLgAECn8VAAIPAAYJoRFohABRAQAPAAYJoRFohABRAQAAAA==.Capri:BAAALgAECgUJEQAAAA==.',
Ce='Cellun:BAAALgAECgUJEwAAAA==.Centipede:BAAALgAECgYJCQABLgAECgYJFwAQAIAXAA==.Ceredis:BAAALgAECgUJCwAAAA==.',
Ch='Choomoo:BAAALgADCgcJCwABLgAFFAYJFwAHAP8NAA==.',
Cl='Cleankarma:BAAALgADCgEJAwAAAA==.',
Co='Comet:BAAALgAECgEJAQAAAA==.Cool:BAABLgAFFH8FAAIFAAMJ1BO4VADjAAAFAAMJ1BO4VADjAAAAAA==.Corwiggs:BAAALgAECgYJCwAAAA==.',
Cr='Crikey:BAAALgAECgYJDAAAAA==.Crimínal:BAAALgADCgcJCwAAAA==.Cripsee:BAAALgADCgMJAwAAAA==.',
Cu='Curbie:BAAALgAECgIJAwAAAA==.',
Cy='Cyndrixx:BAAALgAECgIJAwAAAA==.',
['Cô']='Cônvict:BAAALgADCgYJBgAAAA==.',
Da='Dargath:BAAALgAECgMJBAAAAA==.',
De='Deacknight:BAABLgAECn8cAAMNAAgJwRuPLgB+AgANAAgJwRuPLgB+AgARAAEJig2BFwAyAAABLgADCgYJBwACAAAAAA==.Deacmonk:BAAALgADCgYJBgABLgADCgYJBwACAAAAAA==.Definitely:BAACLgAFFH8SAAIEAAMJgiOlUQAuAQAEAAMJgiOlUQAuAQAuAAQKfzoAAwQACQlCJFwJABwDAAQACQlCJFwJABwDABIAAQkPICobAD8AAAAA.Deki:BAEALgAECgYJBgABLgAFFAUJEgAFAEYVAA==.Dementiaous:BAAALgAECgIJAwAAAA==.Desariana:BAABLgAECn8lAAIFAAkJcxDJWACpAQAFAAkJcxDJWACpAQAAAA==.',
Di='Diggitie:BAAALgAECgEJAQAAAA==.Ditto:BAABLgAFFH8IAAIHAAQJtA5FJwDhAAAHAAQJtA5FJwDhAAABLgAFFAUJLAATAMEbAA==.',
Do='Domtop:BAAALgAFFAMJBAABLgAFFAYJEAAHALISAA==.Dormas:BAABLgAECn8YAAIUAAcJ3g8KJQADAQAUAAcJ3g8KJQADAQAAAA==.Doug:BAAALgADCgEJAQAAAA==.Doxy:BAAALgAECgcJCQAAAA==.',
Dr='Drakeon:BAABLgAECn8UAAIVAAcJ/g6hFQBhAQAVAAcJ/g6hFQBhAQABLgAECgkJcAAJAHggAA==.',
Ee='Eeryxx:BAAALgAECgEJAQAAAA==.',
El='Eldh:BAABLgAECn8fAAMWAAkJbg6FJQBvAQAWAAkJgQuFJQBvAQAKAAEJoiFkawBhAAAAAA==.Eleison:BAAALgADCgMJAwAAAA==.Elendrial:BAAALgAECgIJAgAAAA==.Elendril:BAAALgADCgcJFQAAAA==.Elisoly:BAACLgAFFH8FAAIGAAIJDQzfNwBuAAAGAAIJDQzfNwBuAAAuAAQKfx8AAgYABgmCHoIeAPkBAAYABgmCHoIeAPkBAAAA.',
Em='Emrald:BAAALgAECgYJEwAAAA==.Emridius:BAAALgAECgEJAQABLgAECggJIAAJAGMgAA==.',
En='Endlessly:BAACLgAFFH8QAAIXAAUJ3hQhBgAtAQAXAAUJ3hQhBgAtAQAuAAQKfyIAAhcACAmfIukDAOsCABcACAmfIukDAOsCAAAA.Enerchi:BAAALgADCgMJAwAAAA==.',
Er='Erivoker:BAAALgAECgYJDAABLgAECgYJEgACAAAAAA==.Errimage:BAAALgAECgYJEgAAAA==.Errishoot:BAAALgAECgUJCQABLgAECgYJEgACAAAAAA==.Ervinia:BAAALgADCgYJCgABLgAECgYJEwACAAAAAA==.',
Ev='Evelinar:BAAALgAECgMJAwAAAA==.Evoslex:BAABLgAECn85AAMYAAkJxCMwBAARAwAYAAkJxCMwBAARAwAZAAYJzx1vEwCsAQAAAA==.',
Ex='Exo:BAECLgAFFH8iAAIaAAcJIhqTBgDjAQAaAAcJIhqTBgDjAQAuAAQKfysAAhoACQkcIroDAPACABoACQkcIroDAPACAAAA.',
Fa='Facerolleh:BAACLgAFFH8wAAMbAAgJ+CEJAQCiAgAbAAgJsyEJAQCiAgAJAAQJZiGMBgCGAQAuAAQKf0YABAkACQmdJc4EAFwDAAkACAn2Jc4EAFwDABsACAl/IiUFAKMCABwAAgmNHSRCAFEAAAAA.Fatedx:BAAALgAECgEJAQAAAA==.',
Fe='Feelgoodinc:BAAALgADCgkJFAAAAA==.',
Fi='Fidah:BAAALgADCgEJAQAAAA==.Firemagemain:BAAALgADCgUJBQABLgAFFAMJBQAJACoUAA==.',
Fl='Flanann:BAAALgAECgEJAQABLgAECgMJCgACAAAAAA==.Flop:BAAALgAECgUJCQABLgAFFAQJCQAEAC8bAA==.Flora:BAAALgAECgEJAwAAAA==.',
Fr='Frostmere:BAAALgADCggJGQAAAA==.',
Fu='Fuknazum:BAAALgAECgEJAQAAAA==.Furcht:BAABLgAECn8cAAINAAYJGhOCmgAfAQANAAYJGhOCmgAfAQAAAA==.',
Ga='Galadar:BAAALgADCgUJBQAAAA==.',
Gi='Giteff:BAABLgAFFH8WAAILAAgJvyQ4AQABAwALAAgJvyQ4AQABAwAAAA==.Gitèff:BAABLgAFFH8QAAILAAcJ0BqDDAAVAgALAAcJ0BqDDAAVAgABLgAFFAgJFgALAL8kAA==.Giveroflife:BAAALgAECgYJCwAAAA==.',
Go='Gourdin:BAAALgAECgQJBQABLgAECgYJCAACAAAAAA==.',
Gr='Gramnpa:BAAALgADCgUJBQAAAA==.Grandpriest:BAAALgAECgMJAwABLgAECgkJPQAFALMeAA==.Gravepriest:BAAALgAECgEJAQAAAA==.Grimtysha:BAAALgAECgYJEAAAAA==.Grimveil:BAAALgAECgYJDQAAAA==.Gromit:BAAALgAECgQJCQAAAA==.Gröuch:BAABLgAFFH8IAAIWAAQJXQqhJwD4AAAWAAQJXQqhJwD4AAAAAA==.',
Ha='Harafar:BAACLgAFFH8FAAITAAUJEASLLACpAAATAAUJEASLLACpAAAuAAQKfxYAAxMACQmTFcMTAB8CABMACQmTFcMTAB8CAA4AAwkQBmKZAGwAAAAA.',
He='Hellbourne:BAABLgAECn8kAAILAAkJ8hi7JAAmAgALAAkJ8hi7JAAmAgAAAA==.',
Hi='Himmel:BAAALgADCgcJCQAAAA==.',
Ho='Hopnhorsé:BAAALgAECgQJBQAAAA==.Hotchoq:BAABLgAFFH8HAAIEAAIJ3QuCkACRAAAEAAIJ3QuCkACRAAAAAA==.',
Hu='Huntchoq:BAABLgAFFH8NAAQdAAUJKw/GEgAqAQAdAAUJTg3GEgAqAQAeAAIJVQg8dACEAAAfAAEJlBEwLwA8AAAAAA==.Huxley:BAAALgADCgMJAwAAAA==.',
Ik='Ikan:BAAALgAECgYJEQAAAA==.',
In='Infest:BAAALgAECgQJCAAAAA==.Inzolethys:BAAALgADCgcJBwAAAA==.',
It='Itchy:BAAALgADCgEJAgAAAA==.Itskiohte:BAABLgAECn8pAAIgAAkJVw6ADQC8AQAgAAkJVw6ADQC8AQAAAA==.',
Ja='Jaggernut:BAAALgADCgUJBQAAAA==.',
Ji='Jimmbo:BAAALgAECgQJBAAAAA==.',
Jo='Johnny:BAAALgAECgIJAgABLgAECgkJOQAYAMQjAA==.',
Ju='Judeau:BAAALgADCgEJAQAAAA==.',
Ka='Kaelthuzzad:BAAALgADCgEJAQAAAA==.Kaitza:BAAALgAECgYJCwAAAA==.Kalzaketh:BAABLgAECn9BAAMYAAkJ7gstMgBMAQAYAAkJ7gstMgBMAQAZAAMJ5QSIMwB5AAAAAA==.Kashari:BAAALgAECgYJCwABLgAECgkJfAAIABUcAA==.Katali:BAABLgAECn8VAAMFAAcJSQw7mwAkAQAFAAcJSQw7mwAkAQAGAAYJCwWsVADLAAAAAA==.Kazuggar:BAACLgAFFH8eAAIQAAUJ+iKFCgDuAQAQAAUJ+iKFCgDuAQAuAAQKfzcAAxAACQmsJW4CAFwDABAACAmCJW4CAFwDACEABQkRFqs3AD4BAAAA.Kazzn:BAAALgAFFAIJAgAAAA==.',
Ke='Kedar:BAAALgAECgYJEQAAAA==.Keg:BAAALgAECgIJAgAAAA==.Kelabar:BAAALgADCgQJBAAAAA==.',
Ki='Kick:BAAALgADCgQJBAABLgAFFAcJGAAEALcWAA==.Kiffs:BAAALgAECgcJCgAAAA==.Kill:BAAALgAFFAEJAgAAAA==.Killerman:BAABLgAFFH8VAAMRAAgJHCLSAAA8AgARAAYJTSXSAAA8AgANAAQJFh2nYwAXAQAAAA==.Kirâ:BAABLgAECn8UAAIJAAgJCxxHGQAPAgAJAAgJCxxHGQAPAgABLgAECgcJEwACAAAAAA==.',
Kr='Kregnar:BAABLgAECn8pAAIbAAkJBRytBgB9AgAbAAkJBRytBgB9AgAAAA==.Kresh:BAAALgAECgcJCwAAAA==.',
Ku='Kucabara:BAAALgAECgIJAwAAAA==.Kuraiwiggs:BAAALgADCgYJDAAAAA==.',
Kw='Kwichang:BAABLgAECn8ZAAIEAAcJuw8KiwBGAQAEAAcJuw8KiwBGAQAAAA==.',
Ky='Kyndariae:BAAALgAECgQJBAAAAA==.',
['Ké']='Kélpo:BAAALgADCgMJBAAAAA==.',
La='Lasagne:BAAALgADCgMJAwAAAA==.',
Le='Lesley:BAAALgAECgEJAQAAAA==.',
Li='Lickynose:BAABLgAECn8pAAIEAAkJYyEqEQDgAgAEAAkJYyEqEQDgAgAAAA==.Lips:BAAALgAECgEJAQAAAA==.',
Ls='Ls:BAABLgAECn8iAAQMAAkJaiPEBwCYAgAMAAgJ3R/EBwCYAgALAAgJnCG9MQAzAgAiAAcJYhW4DABwAQAAAA==.',
Ly='Lythium:BAAALgAECgEJAQAAAA==.',
Ma='Madarabia:BAAALgAECgYJDQAAAA==.Magnius:BAAALgAECgMJAwAAAA==.Makcik:BAAALgAECgEJAQAAAA==.Mamut:BAAALgAECgEJAQAAAA==.Mantisar:BAACLgAFFH8IAAIFAAMJ5RLOVADjAAAFAAMJ5RLOVADjAAAuAAQKfx4AAgUABwnmHmk1ABICAAUABwnmHmk1ABICAAAA.Maxsm:BAABLgAECn8XAAIhAAgJrhmSIQACAgAhAAgJrhmSIQACAgAAAA==.',
Me='Melanippe:BAABLgAECn8XAAIOAAYJDxtuPQCuAQAOAAYJDxtuPQCuAQAAAA==.Meleefox:BAAALgADCgUJBQAAAA==.Melethron:BAABLgAECn8+AAIFAAkJgRy7IABtAgAFAAkJgRy7IABtAgAAAA==.Melioknky:BAAALgAECgYJBgAAAA==.',
Mi='Mid:BAAALgADCgYJBgAAAA==.Mightymage:BAABLgAECn8hAAIEAAgJ4Q1LfQBiAQAEAAgJ4Q1LfQBiAQAAAA==.Millionbaby:BAAALgAECgEJAQAAAA==.Milliondruid:BAAALgAECgMJBAAAAA==.Millionsm:BAAALgADCgQJBQAAAA==.Mirrorimage:BAAALgAFFAEJAgABLgAFFAYJEgAIAAgVAA==.Mirrorx:BAACLgAFFH8SAAIIAAYJCBX4CwB7AQAIAAYJCBX4CwB7AQAuAAQKfzIAAggACQlzIMIHALsCAAgACQlzIMIHALsCAAAA.Miy:BAAALgAECgEJAQAAAA==.',
Mo='Mongon:BAAALgAECgYJBgAAAA==.Moogle:BAAALgAECgIJBAAAAA==.Moomie:BAABLgAECn8iAAIOAAgJAxY4NAC4AQAOAAgJAxY4NAC4AQAAAA==.Moosfel:BAABLgAECn8jAAIXAAcJGhr+DADDAQAXAAcJGhr+DADDAQAAAA==.',
Mt='Mtzz:BAAALgAECgUJBQABLgAECgYJCAACAAAAAA==.',
Mu='Mudcake:BAAALgAECgEJAQAAAA==.',
My='Mygravebroke:BAAALgADCggJCQAAAA==.Mystdragon:BAACLgAFFH8TAAMVAAUJxRu3DgCKAQAVAAUJxRu3DgCKAQAYAAMJlAttPAC0AAAuAAQKfzAAAhUACQm5IRUDABIDABUACQm5IRUDABIDAAEuAAUUCAknAAcAmh0A.Mystweaverr:BAACLgAFFH8nAAMHAAgJmh3EAgDPAgAHAAgJmh3EAgDPAgAKAAEJ9QQEOwA3AAAuAAQKfy8AAwcACQn3H4AJALkCAAcACQn3H4AJALkCAAoAAgkjIqJNALcAAAAA.',
['Mö']='Mörae:BAAALgADCgEJAQABLgAECgYJFwAOAA8bAA==.',
Na='Naddar:BAACLgAFFH8QAAIGAAUJKhhUEwB2AQAGAAUJKhhUEwB2AQAuAAQKf0EAAgYACQneHe0HAPkCAAYACQneHe0HAPkCAAAA.Namadgi:BAABLgAECn8hAAIOAAkJVRpNEwCfAgAOAAkJVRpNEwCfAgAAAA==.Nathria:BAAALgAECgIJAwAAAA==.',
Ne='Netalis:BAABLgAECn8lAAIOAAgJwxTJLQDcAQAOAAgJwxTJLQDcAQAAAA==.',
Ni='Nikonii:BAAALgADCgQJBAAAAA==.',
Nu='Nurckers:BAAALgAECgcJCAAAAA==.',
Oa='Oakinelf:BAAALgADCgcJAQAAAA==.',
Om='Omnishifts:BAAALgAECgEJAgAAAA==.',
Or='Oramo:BAABLgAECn8fAAMaAAgJfCMmBQDwAgAaAAgJxSImBQDwAgANAAYJgCLQYgCPAQAAAA==.',
Ov='Ovaries:BAAALgADCgUJBQABLgAECgQJBQACAAAAAA==.',
Pa='Paktam:BAABLgAECn8XAAIQAAcJzh1+GgBcAgAQAAcJzh1+GgBcAgAAAA==.Paméla:BAAALgAECgcJDgABLgAECgkJcAAJAHggAA==.Paradisya:BAAALgADCggJDgAAAA==.',
Pe='Perceptor:BAAALgAECgEJAQABLgAECgkJKQAUAJMhAA==.Pets:BAAALgAECgEJAQABLgAECgkJUwADAPwUAA==.',
Pl='Placebo:BAAALgAECgUJBQABLgAFFAUJEAAXAN4UAA==.',
Pr='Prothero:BAACLgAFFH8QAAMEAAUJJiDqNQBpAQAEAAUJJiDqNQBpAQASAAEJZRkFBABOAAAuAAQKfxYAAwQACQnGILgWALwCAAQACQnGILgWALwCABIACAkrGAMDAFACAAAA.Proyo:BAAALgADCgUJBQAAAA==.',
['På']='Påthor:BAACLgAFFH8HAAITAAIJkw+PNAB4AAATAAIJkw+PNAB4AAAuAAQKfx8AAxMABwk4HP0eALYBABMABwk4HP0eALYBABQAAwkSEu9JAF0AAAAA.',
Ra='Raikonnen:BAAALgAECgEJAQAAAA==.Rapidstrikes:BAAALgAECgMJBAAAAA==.Rawtoor:BAACLgAFFH8eAAILAAcJYRcRFQDIAQALAAcJYRcRFQDIAQAuAAQKfyEAAgsACAk4IdInAGUCAAsACAk4IdInAGUCAAAA.',
Re='Rebelsister:BAAALgADCgcJEAAAAA==.Refridgerate:BAAALgADCgUJBwAAAA==.',
Ri='Riddagain:BAABLgAECn8bAAMiAAYJeA/1FAAHAQAiAAYJTw/1FAAHAQALAAIJwAugAgErAAAAAA==.Ridgemonk:BAABLgAECn87AAMWAAkJniPVAQBAAwAWAAkJniPVAQBAAwAHAAQJQAGYYABMAAAAAA==.Riggsdk:BAAALgADCgcJBwABLgAFFAgJGwAeAKAiAA==.Riggse:BAAALgAFFAEJAQABLgAFFAgJGwAeAKAiAA==.Riggshunt:BAACLgAFFH8bAAQeAAgJoCLTAACrAQAdAAYJLCQuAAD7AQAeAAYJ8SDTAACrAQAfAAEJAAC/KABKAAAuAAQKfx4ABB4ACAmrJr0IAAcDAB4ABwmYJr0IAAcDAB0ACAmTJIQDAPICAB8AAQmCHGd9AE8AAAAA.Riggspal:BAAALgAFFAIJAgABLgAFFAgJGwAeAKAiAA==.Riggswar:BAAALgAFFAEJAQABLgAFFAgJGwAeAKAiAA==.Riggzs:BAAALgAFFAIJAgABLgAFFAgJGwAeAKAiAA==.',
Ro='Roadkill:BAABLgAECn8gAAIaAAgJnSM4BAALAwAaAAgJnSM4BAALAwAAAA==.Rolltoor:BAAALgAFFAIJAwAAAA==.Roonate:BAAALgADCgUJBQAAAA==.Rosemary:BAAALgAECgQJBAAAAA==.',
Ry='Ryujin:BAAALgAECgQJCQAAAA==.',
Sa='Saiko:BAABLgAFFH8SAAIMAAUJdhlbCgA3AQAMAAUJdhlbCgA3AQAAAA==.Sansa:BAACLgAFFH8TAAIdAAcJZhgrAwDKAQAdAAcJZhgrAwDKAQAuAAQKfyMAAh0ACQlnI00CACMDAB0ACQlnI00CACMDAAAA.Saso:BAACLgAFFH8RAAIEAAYJoxe0KgCQAQAEAAYJoxe0KgCQAQAuAAQKfzQABAQACQmUIsAPAOkCAAQACQmUIsAPAOkCABIAAwkDH0gMAA0BACMAAgnECLALAHcAAAAA.Sastroll:BAAALgAECgUJBQAAAA==.',
Sc='Scorn:BAAALgADCgcJCAAAAA==.Scroll:BAABLgAECn8bAAIHAAgJPBp9GQAmAgAHAAgJPBp9GQAmAgAAAA==.',
Se='Seluvis:BAABLgAECn8WAAIEAAcJ0QGP+QCQAAAEAAcJ0QGP+QCQAAAAAA==.Sentai:BAAALgADCgcJBwAAAA==.Serapayne:BAAALgAECgcJAQAAAA==.',
Sh='Shadow:BAACLgAFFH8aAAILAAYJYhcRHQCSAQALAAYJYhcRHQCSAQAuAAQKf10AAgsACQlmJAkDAEkDAAsACQlmJAkDAEkDAAAA.Shandrilah:BAAALgADCgQJBAAAAA==.Shapeshift:BAAALgADCgUJBQABLgAECgIJAgACAAAAAA==.Shialebuff:BAABLgAECn9BAAQIAAkJ5xgPDwBMAgAIAAkJ5xgPDwBMAgADAAkJzB+DEABMAgABAAQJFxmqMgAqAQAAAA==.Shijin:BAAALgAECgQJBQAAAA==.Shortfuze:BAAALgAECgYJDQAAAA==.',
Si='Sindar:BAAALgADCgUJBQAAAA==.Sinfall:BAAALgAECggJDgAAAA==.Siphon:BAAALgAECgEJAwAAAA==.Siscomp:BAABLgAECn9wAAIJAAkJeCAGDgB8AgAJAAkJeCAGDgB8AgAAAA==.Sixth:BAABLgAECn8XAAIhAAcJ/BqrIgC3AQAhAAcJ/BqrIgC3AQAAAA==.Sizzle:BAAALgADCgMJAwAAAA==.',
Sk='Skateboard:BAAALgADCgEJAQAAAA==.Sky:BAACLgAFFH8fAAIBAAcJlxpiBwBnAgABAAcJlxpiBwBnAgAuAAQKfxQAAwEACAlxE48cALABAAEABwlZEo8cALABAAMABQnyD4hMAAYBAAAA.',
Sl='Sleck:BAAALgAECgYJDAAAAA==.',
Sm='Smooth:BAAALgAECgEJAQABLgAFFAQJEgANAFEdAA==.',
Sn='Snappa:BAAALgADCgYJCwAAAA==.Sniped:BAAALgAFFAEJAQAAAA==.Snugglepuff:BAAALgAECgkJEwAAAA==.',
So='Soapfidas:BAAALgADCggJCgAAAA==.Sonarius:BAACLgAFFH8JAAIEAAQJLxu0QQBJAQAEAAQJLxu0QQBJAQAuAAQKfx0ABAQACAndHyk8AIYCAAQACAndHyk8AIYCABIAAgkCHZwLAKUAACMAAQmyEg8PADwAAAAA.Sophie:BAAALgAECgEJAwAAAA==.',
Sp='Splitterman:BAABLgAFFH8LAAMRAAYJfxM9CABAAQARAAUJ+hc9CABAAQANAAEJkQGX+AAvAAAAAA==.',
Su='Su:BAABLgAECn8yAAIHAAcJ4yVlBwDiAgAHAAcJ4yVlBwDiAgAAAA==.Sudno:BAAALgAECgQJCAABLgAFFAcJGwAPAPAYAA==.Sundae:BAABLgAECn83AAQDAAkJlSFRBwDmAgADAAgJHCNRBwDmAgABAAgJhxulDACGAgAIAAMJ3BbwTAC0AAAAAA==.Sunwukong:BAAALgAECgUJCQAAAA==.Supersinpe:BAAALgAECgIJAgAAAA==.',
Sv='Svdrag:BAAALgAECgMJAwAAAA==.Svendlefyre:BAAALgADCgcJDgABLgAECgkJLgAXAIMZAA==.Svholydrag:BAAALgADCgEJAQAAAA==.Svmishima:BAAALgAECgMJBQAAAA==.',
Sw='Swirly:BAAALgAECgEJAQAAAA==.',
Sy='Sylvie:BAABLgAECn8nAAIeAAkJwRUIIwBBAgAeAAkJwRUIIwBBAgAAAA==.',
['Sý']='Sýlvanas:BAABLgAECn8UAAIfAAUJVxNNFgDuAAAfAAUJVxNNFgDuAAAAAA==.',
Te='Tealç:BAABLgAECn8gAAIcAAcJpheVGACQAQAcAAcJpheVGACQAQABLgAFFAQJGAAcAEcfAA==.Tekk:BAAALgAECgEJAQAAAA==.Tekkys:BAAALgAECgEJAgAAAA==.Tertle:BAAALgADCgUJBQAAAA==.',
Ti='Tiafinia:BAAALgAECgEJAgAAAA==.Tiggerstripe:BAAALgADCgEJAQABLgAECgkJMQAgAEMQAA==.Timmyy:BAAALgAECgYJBgABLgAFFAQJCAANAN4MAA==.Timur:BAAALgAECgMJBAAAAA==.Tinara:BAAALgADCgUJBQAAAA==.',
To='Tome:BAAALgAECgEJAQABLgAECggJGwAHADwaAA==.',
Tr='Trigger:BAAALgAECgIJAgAAAA==.',
Tu='Turlesblows:BAABLgAECn8gAAMJAAgJYyADIQDVAQAJAAgJYyADIQDVAQAcAAEJOxWZRAA7AAAAAA==.',
Tw='Twityy:BAAALgADCgEJAgAAAA==.Twofiveyd:BAABLgAFFH8FAAIYAAQJjA8XKwD6AAAYAAQJjA8XKwD6AAABLgAFFAYJFAAbAGcYAA==.',
Ty='Tyladrhas:BAABLgAECn80AAIiAAkJVB8kAwCfAgAiAAkJVB8kAwCfAgAAAA==.Tyrismaximus:BAAALgAECgMJAwAAAA==.',
Ul='Ulkina:BAAALgADCgYJCQAAAA==.',
Va='Vaelith:BAAALgAECgIJAgAAAA==.Valerine:BAABLgAECn8aAAIEAAkJ/wo9dwBwAQAEAAkJ/wo9dwBwAQAAAA==.Vanoran:BAAALgAECgMJBAAAAA==.Varina:BAAALgAECgcJEwAAAA==.',
Ve='Velsaert:BAAALgAECgEJAQAAAA==.Venki:BAAALgAECgcJCQAAAA==.',
Vi='Vitani:BAAALgADCgIJAgABLgAFFAUJEAAXAN4UAA==.',
Vo='Voidnova:BAABLgAFFH8HAAIEAAMJlRDTdQDXAAAEAAMJlRDTdQDXAAAAAA==.Voidphayze:BAAALgAECgUJDAABLgAFFAMJBQANAEUTAA==.',
Vu='Vulken:BAABLgAECn9nAAIeAAkJESXcCwDhAgAeAAkJESXcCwDhAgAAAA==.',
['Vê']='Vê:BAAALgAECgkJEQAAAA==.',
Wa='Wallace:BAAALgAECgcJDAAAAA==.Walterlight:BAAALgAECgYJDgAAAA==.Watto:BAABLgAECn8VAAMQAAkJOR/0EwCTAgAQAAkJOR/0EwCTAgAhAAEJMBdwiABEAAAAAA==.',
We='Wemongin:BAAALgADCgUJBQAAAA==.',
Wh='Whimsical:BAABLgAECn8XAAIQAAYJgBeySABvAQAQAAYJgBeySABvAQAAAA==.',
Wi='Winnìng:BAABLgAECn8jAAIkAAkJLQzbFwBFAQAkAAkJLQzbFwBFAQAAAA==.',
Wu='Wugong:BAAALgADCgEJAQAAAA==.',
['Wó']='Wórkwórk:BAACLgAFFH8FAAIJAAMJKhROFwCsAAAJAAMJKhROFwCsAAAuAAQKfxsAAwkACQk6Gxg3AMsBAAkABwnRGRg3AMsBABsAAwnsGr8fAO8AAAAA.',
Ze='Zerg:BAAALgAECgIJAgAAAA==.',
Zi='Zich:BAAALgADCgMJAwAAAA==.Zihon:BAABLgAECn8UAAINAAQJTxpu2ADEAAANAAQJTxpu2ADEAAAAAA==.',
Zo='Zodiiak:BAABLgAECn9EAAIgAAkJMR3VBQBrAgAgAAkJMR3VBQBrAgAAAA==.',
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
