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

local lookup = {'Unknown-Unknown','Priest-Holy','Mage-Frost','Paladin-Retribution','Paladin-Holy','Priest-Shadow','Monk-Mistweaver','Priest-Discipline','Warrior-Fury','Monk-Windwalker','DemonHunter-Devourer','DemonHunter-Havoc','DeathKnight-Unholy','Monk-Brewmaster','Druid-Restoration','Warlock-Demonology','Shaman-Restoration','DeathKnight-Frost','Mage-Arcane','DeathKnight-Blood','Druid-Guardian','Evoker-Preservation','Druid-Feral','Evoker-Augmentation','Evoker-Devastation','Warrior-Arms','Warrior-Protection','Paladin-Protection','Druid-Balance','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Enhancement','Shaman-Elemental','Mage-Fire','DemonHunter-Vengeance',}
local provider = {region='US',realm='Gundrak',name='US',type='weekly',zone=46,date='2026-06-13',data={Ad='Adelyne:BAAALgAFFAQJBAAAAA==.Adera:BAAALgAECgYJBwAAAA==.',
Af='Aff:BAAALgADCgYJBgAAAA==.',
Ag='Agony:BAAALgAECgQJBgAAAA==.',
Ah='Ahkanon:BAAALgADCgEJAQAAAA==.Ahoo:BAAALgAECgkJCgAAAA==.',
Ai='Aiden:BAAALgAECgEJAgABLgAECgIJAgABAAAAAA==.Aidendk:BAAALgADCgIJAgABLgAECgIJAgABAAAAAA==.Aidenp:BAAALgADCgIJAgABLgAECgIJAgABAAAAAA==.Air:BAAALgADCgcJBwABLgAFFAgJJwACADkbAA==.',
Ak='Aku:BAAALgADCgIJBAAAAA==.',
Al='Aleniastra:BAAALgAECgYJEwAAAA==.Alexyss:BAAALgAECgUJDgAAAA==.Alykard:BAABLgAECn8xAAIDAAkJwhFESwD2AQADAAkJwhFESwD2AQAAAA==.',
Am='Amelia:BAAALgAECgEJAQAAAA==.Amyara:BAAALgAECgEJAgAAAA==.',
An='Andronicas:BAABLgAECn8mAAMEAAkJ6hK3RAD2AQAEAAkJ6hK3RAD2AQAFAAEJogevnAAtAAAAAA==.Aneira:BAABLgAFFH8dAAIDAAQJHAmFaQAYAQADAAQJHAmFaQAYAQAAAA==.',
Ap='Apexis:BAAALgADCgYJCQAAAA==.',
Ar='Ariaa:BAABLgAECn8YAAIGAAYJOxhrMQBVAQAGAAYJOxhrMQBVAQAAAA==.Arieyri:BAAALgADCgcJBwAAAA==.Artpop:BAAALgAFFAEJAQABLgAFFAcJFwAHAIURAA==.',
As='Aseria:BAAALgAECgYJCAAAAA==.Ash:BAAALgADCgcJCwAAAA==.Ashvira:BAAALgAECgQJBAAAAA==.Aspect:BAAALgADCgcJDgABLgAECgEJAQABAAAAAA==.Astarael:BAABLgAECn8iAAMGAAkJShdZIQC6AQAGAAgJGhZZIQC6AQACAAcJLQ4jUQCVAAAAAA==.',
Av='Avi:BAABLgAECn8oAAIIAAkJUhX4EQBTAgAIAAkJUhX4EQBTAgABLgAECgkJcQAJAHggAA==.',
Ba='Babygurl:BAACLgAFFH8FAAIFAAMJNx8HJAD6AAAFAAMJNx8HJAD6AAAuAAQKf3YAAgUACQntJTMCAIoDAAUACQntJTMCAIoDAAAA.Baragas:BAAALgAECgYJDgAAAA==.Bareback:BAAALgAECgQJBAAAAA==.Barney:BAAALgADCgEJAQAAAA==.Battosaî:BAAALgAECgQJBAAAAA==.',
Be='Beeny:BAACLgAFFH84AAIHAAgJDiQKAgAkAwAHAAgJDiQKAgAkAwAuAAQKf0EAAwcACQlpI4UIAMwCAAcACQlpI4UIAMwCAAoAAQlsEBOZADMAAAAA.Belle:BAACLgAFFH8ZAAMLAAgJxBaTEgAQAgALAAgJxBaTEgAQAgAMAAEJ8Bc/DABWAAAuAAQKfy0AAwsACAnFJhIEAIgDAAsACAmFJhIEAIgDAAwABwk+IFIOAH4CAAAA.Berat:BAAALgADCgQJBAAAAA==.Berzerker:BAAALgADCgcJEwAAAA==.',
Bg='Bgc:BAAALgADCgUJBQAAAA==.',
Bi='Binari:BAAALgAECgMJAwABLgAFFAMJBQAJACoUAA==.Binlock:BAAALgAECgQJBAABLgAFFAMJBQAJACoUAA==.',
Bl='Bl:BAAALgAECgMJAwAAAA==.Bladebear:BAABLgAECn82AAIDAAkJUxUqTQDxAQADAAkJUxUqTQDxAQAAAA==.',
Bo='Boose:BAAALgAECgYJBgAAAA==.Bootybreaker:BAAALgADCgcJBwAAAA==.Boxoflunch:BAAALgAECgEJAQAAAA==.',
Br='Brat:BAAALgAECgEJBAABLgAECgkJVQACAC4VAA==.Brewingmist:BAAALgAECgUJBQABLgAFFAMJBQANAEUTAA==.Bréwmaster:BAABLgAECn8UAAMOAAcJZxqdGgDOAQAOAAcJZxqdGgDOAQAHAAYJVhHVSgA5AQABLgAECgkJIgAGAEoXAA==.',
Bu='Bubbelz:BAAALgAECgMJAwAAAA==.Bubbleez:BAAALgADCgUJBQAAAA==.Bubblôseven:BAAALgAECgEJAQAAAA==.Bucklord:BAABLgAECn8iAAMGAAgJjRkAFwAuAgAGAAgJjRkAFwAuAgACAAEJABlTagA6AAAAAA==.Budin:BAAALgAECggJEgAAAA==.Bullmann:BAAALgADCgQJBAAAAA==.',
Ca='Cannibal:BAABLgAECn8+AAIPAAkJkxwHDwDbAgAPAAkJkxwHDwDbAgAAAA==.Caplock:BAABLgAECn8VAAIQAAYJoRFohABRAQAQAAYJoRFohABRAQAAAA==.Capri:BAAALgAECgYJEwAAAA==.',
Ce='Cellun:BAAALgAECgUJEwAAAA==.Centipede:BAAALgAECgYJCQABLgAECgYJFwARAIAXAA==.Ceredis:BAAALgAECgUJCwAAAA==.',
Ch='Chiwolf:BAAALgAECgQJAwAAAA==.Choomoo:BAAALgADCgcJCwABLgAFFAYJGAAHAP8NAA==.',
Cl='Cleankarma:BAAALgADCgEJAwAAAA==.',
Co='Comet:BAAALgAECgEJAQAAAA==.Cool:BAABLgAFFH8FAAIEAAMJ1BMgaQDWAAAEAAMJ1BMgaQDWAAAAAA==.Corwiggs:BAAALgAECgYJCwAAAA==.',
Cr='Crikey:BAAALgAECgYJDAAAAA==.Crimínal:BAAALgADCgcJCwAAAA==.Cripsee:BAAALgADCgMJAwAAAA==.',
Cu='Curbie:BAAALgAECgIJAwAAAA==.',
Cv='Cvdruid:BAAALgAECgUJBQAAAA==.',
Cy='Cyndrixx:BAAALgAECgIJAwAAAA==.',
['Cô']='Cônvict:BAAALgADCgYJBgAAAA==.',
De='Deacknight:BAABLgAECn8cAAMNAAgJwRuPLgB+AgANAAgJwRuPLgB+AgASAAEJig2BFwAyAAABLgADCgYJBwABAAAAAA==.Deacmonk:BAAALgADCgYJBgABLgADCgYJBwABAAAAAA==.Definitely:BAACLgAFFH8VAAIDAAMJgiNraAAbAQADAAMJgiNraAAbAQAuAAQKfzsAAwMACQlCJJELABoDAAMACQlCJJELABoDABMAAQkPICobAD8AAAAA.Deki:BAEALgAECgYJBgABLgAFFAcJGAAEAPkXAA==.Dementiaous:BAAALgAECgIJAwAAAA==.Desariana:BAABLgAECn8lAAIEAAkJcxChYwCmAQAEAAkJcxChYwCmAQAAAA==.',
Di='Diggitie:BAAALgAECgEJAQAAAA==.Ditto:BAABLgAFFH8TAAIHAAYJKhPjKwADAQAHAAYJKhPjKwADAQAAAA==.',
Do='Domtop:BAABLgAFFH8FAAMUAAMJXAHoOQBJAAAUAAIJTwHoOQBJAAASAAEJdgFNLAAuAAABLgAFFAcJFwAHAIURAA==.Doot:BAAALgAECgIJAgAAAA==.Dormas:BAABLgAECn8YAAIVAAcJ3g/6KgAAAQAVAAcJ3g/6KgAAAQAAAA==.Doug:BAAALgADCgEJAQAAAA==.Doxy:BAAALgAECgcJCQAAAA==.',
Dr='Drakeon:BAABLgAECn8UAAIWAAcJ/g4DFwBcAQAWAAcJ/g4DFwBcAQABLgAECgkJcQAJAHggAA==.',
Ee='Eeryxx:BAAALgAECgEJAQAAAA==.',
El='Eldh:BAABLgAECn8kAAMOAAkJLBFWIwCNAQAOAAkJ5w1WIwCNAQAKAAEJYiTucABrAAAAAA==.Eleison:BAAALgADCgMJAwAAAA==.Elendrial:BAAALgAECgIJAgAAAA==.Elendril:BAAALgADCgcJFQAAAA==.Elisoly:BAACLgAFFH8FAAIFAAIJDQwfPwBhAAAFAAIJDQwfPwBhAAAuAAQKfyUAAgUABgmCHq8gAPsBAAUABgmCHq8gAPsBAAAA.',
Em='Emrald:BAAALgAECgYJEwAAAA==.Emridius:BAAALgAECgEJAwABLgAECggJIQAJAGMgAA==.',
En='Endlessly:BAACLgAFFH8QAAIXAAUJ3hQrCAAiAQAXAAUJ3hQrCAAiAQAuAAQKfyQAAhcACQk2I+kDAOsCABcACQk2I+kDAOsCAAAA.Enerchi:BAAALgADCgMJAwAAAA==.',
Er='Erivoker:BAAALgAECgYJDAABLgAECgYJEgABAAAAAA==.Errimage:BAAALgAECgYJEgAAAA==.Errishoot:BAAALgAECgUJCQABLgAECgYJEgABAAAAAA==.Ervinia:BAAALgADCgYJCgABLgAECgYJEwABAAAAAA==.',
Ev='Evelinar:BAAALgAECgYJCQAAAA==.Evoslex:BAABLgAECn85AAMYAAkJxCPHBAAWAwAYAAkJxCPHBAAWAwAZAAYJzx1vEwCsAQAAAA==.',
Ex='Exo:BAECLgAFFH8nAAIUAAgJ5xnABgAaAgAUAAgJ5xnABgAaAgAuAAQKfysAAhQACQkcIrIEAOUCABQACQkcIrIEAOUCAAAA.',
Fa='Facerolleh:BAACLgAFFH80AAMaAAgJ+CEwAgCYAgAaAAgJsyEwAgCYAgAJAAQJZiGMBgCGAQAuAAQKf0YABAkACQmdJc4EAFwDAAkACAn2Jc4EAFwDABoACAl/IhgGAJwCABsAAgmNHVZIAE8AAAAA.Fatedx:BAAALgAECgUJBwAAAA==.',
Fe='Feelgoodinc:BAAALgADCgkJFAAAAA==.',
Fi='Fidah:BAAALgAECgEJAQAAAA==.Firemagemain:BAAALgADCgUJBQABLgAFFAMJBQAJACoUAA==.',
Fl='Flanann:BAAALgAECgEJAQABLgAECgMJDAABAAAAAA==.Flop:BAAALgAECgUJCQABLgAFFAUJEAADAJIbAA==.Flora:BAAALgAECgEJAwAAAA==.',
Fr='Frostmere:BAAALgADCggJGQAAAA==.',
Fu='Fuknazum:BAAALgAECgEJAQAAAA==.Furcht:BAABLgAECn8dAAINAAcJVBIkgwBaAQANAAcJVBIkgwBaAQAAAA==.',
Ga='Galadar:BAAALgADCgUJBQAAAA==.',
Gh='Ghrael:BAAALgAECgMJBAAAAA==.',
Gi='Giteff:BAABLgAFFH8qAAILAAkJJSViAAB2AwALAAkJJSViAAB2AwAAAA==.Gitèff:BAABLgAFFH8XAAILAAcJAiOfCgBkAgALAAcJAiOfCgBkAgABLgAFFAkJKgALACUlAA==.Giveroflife:BAABLgAECn8UAAMcAAYJVg1pKgDDAAAEAAYJAQf+6ADQAAAcAAQJjg9pKgDDAAAAAA==.',
Go='Gourdin:BAAALgAECgQJBQABLgAECgYJCAABAAAAAA==.',
Gr='Gramnpa:BAAALgADCgUJBQAAAA==.Grandpriest:BAAALgAECgQJBwABLgAECgkJRQAEAEQgAA==.Gravepriest:BAAALgAECgEJAQAAAA==.Grimtysha:BAAALgAECgYJEAAAAA==.Grimveil:BAAALgAECgYJDQAAAA==.Gromit:BAAALgAECgQJCQAAAA==.Gröuch:BAABLgAFFH8IAAIOAAQJXQpGLQDwAAAOAAQJXQpGLQDwAAAAAA==.',
Ha='Harafar:BAACLgAFFH8IAAIdAAUJuQdkLwDAAAAdAAUJuQdkLwDAAAAuAAQKfx4AAx0ACQnuGd0NAHoCAB0ACQnuGd0NAHoCAA8AAwl7B0GfAG8AAAAA.Hate:BAAALgAECgYJDQABLgAFFAcJHQADAMQZAA==.',
He='Hellbourne:BAABLgAECn8kAAILAAkJ8hhhKAAmAgALAAkJ8hhhKAAmAgAAAA==.',
Hi='Himmel:BAAALgADCgcJCQAAAA==.',
Ho='Hopnhorsé:BAAALgAECgQJBQAAAA==.Hotchoq:BAABLgAFFH8KAAIDAAMJqgzNgQDbAAADAAMJqgzNgQDbAAAAAA==.',
Hu='Huntchoq:BAABLgAFFH8PAAQeAAYJZgy4FgAXAQAeAAUJTg24FgAXAQAfAAMJ1wrFaADJAAAgAAIJdAl6JQB5AAAAAA==.Huxley:BAAALgADCgMJAwAAAA==.',
Ik='Ikan:BAAALgAECgYJEwAAAA==.',
In='Infest:BAAALgAECgQJCAAAAA==.Inzolethys:BAAALgADCgcJBwAAAA==.',
It='Itchy:BAAALgADCgEJAgAAAA==.Itskiohte:BAABLgAECn8pAAIhAAkJVw6nDwCzAQAhAAkJVw6nDwCzAQAAAA==.',
Ja='Jaggernut:BAAALgADCgUJBQAAAA==.',
Ji='Jimmbo:BAAALgAECgQJBAAAAA==.',
Jo='Johnny:BAAALgAECgIJAgABLgAECgkJOQAYAMQjAA==.',
Ju='Judeau:BAAALgADCgEJAQAAAA==.',
Ka='Kaelthuzzad:BAAALgADCgEJAQAAAA==.Kaitza:BAAALgAECgYJCwAAAA==.Kalzaketh:BAABLgAECn9DAAMYAAkJbQ06KwCPAQAYAAkJbQ06KwCPAQAZAAMJ5QSIMwB5AAAAAA==.Kashari:BAAALgAECgYJCwABLgAECgkJfgAGABUcAA==.Katali:BAABLgAECn8VAAMEAAcJSQwjpwAqAQAEAAcJSQwjpwAqAQAFAAYJCwU+WgDKAAAAAA==.Kazo:BAAALgAFFAEJAQAAAA==.Kazuggar:BAACLgAFFH8gAAIRAAYJnyKhBwA/AgARAAYJnyKhBwA/AgAuAAQKfzgAAxEACQmsJW4CAFwDABEACAmCJW4CAFwDACIABgkAFfQyAG0BAAAA.Kazzn:BAABLgAFFH8FAAIPAAQJrwiWOwC7AAAPAAQJrwiWOwC7AAAAAA==.',
Ke='Kedar:BAAALgAECgYJEQAAAA==.Keg:BAAALgAECgIJAgAAAA==.Kelabar:BAAALgADCgQJBAAAAA==.',
Ki='Kick:BAAALgADCgQJBAABLgAFFAcJHQADAMQZAA==.Kiffs:BAAALgAECgcJCgAAAA==.Kill:BAAALgAFFAEJAgAAAA==.Killerman:BAABLgAFFH8nAAQSAAkJqCOlAQBEAgASAAYJdSalAQBEAgANAAYJTx93IwDTAQAUAAMJixiiIwDOAAAAAA==.Kirâ:BAABLgAECn8UAAIJAAgJCxzxHAAFAgAJAAgJCxzxHAAFAgABLgAECgcJEwABAAAAAA==.',
Kr='Kregnar:BAABLgAECn8pAAIaAAkJBRzoBwB0AgAaAAkJBRzoBwB0AgAAAA==.Kresh:BAAALgAECgcJCwAAAA==.',
Ku='Kucabara:BAAALgAECgIJAwAAAA==.Kuraiwiggs:BAAALgADCgYJDAAAAA==.',
Kw='Kwichang:BAABLgAECn8ZAAIDAAcJuw+ykwBNAQADAAcJuw+ykwBNAQAAAA==.',
Ky='Kyndariae:BAAALgAECgYJBgAAAA==.',
['Ké']='Kélpo:BAAALgADCgMJBAAAAA==.',
La='Lasagne:BAAALgADCgMJAwAAAA==.',
Le='Leatherkink:BAABLgAFFH8GAAIfAAQJTAavTwADAQAfAAQJTAavTwADAQABLgAFFAcJFwAHAIURAA==.Lesley:BAAALgAECgEJAQAAAA==.',
Li='Lickynose:BAABLgAECn8zAAMDAAkJdCIjDwD/AgADAAkJdCIjDwD/AgAjAAEJEiCvDwBdAAAAAA==.Lips:BAAALgAECgEJAQAAAA==.',
Ls='Ls:BAABLgAECn8iAAQMAAkJaiOACQCPAgAMAAgJ3R+ACQCPAgALAAgJnCG9MQAzAgAkAAcJYhUJDgBtAQAAAA==.',
Ly='Lythium:BAAALgAECggJDAAAAA==.',
Ma='Madarabia:BAAALgAECgYJDQAAAA==.Magnius:BAAALgAECgMJAwAAAA==.Makcik:BAAALgAECgEJAQAAAA==.Mamut:BAAALgAECgEJAQAAAA==.Mantisar:BAACLgAFFH8IAAIEAAMJ5RJrawDTAAAEAAMJ5RJrawDTAAAuAAQKfx4AAgQABwnmHt48AA8CAAQABwnmHt48AA8CAAAA.Mattdemonn:BAAALgAECgQJBAAAAA==.Maxsm:BAABLgAECn8XAAIiAAgJrhmSIQACAgAiAAgJrhmSIQACAgAAAA==.',
Me='Melanippe:BAABLgAECn8XAAIPAAYJDxtuPQCuAQAPAAYJDxtuPQCuAQAAAA==.Meleefox:BAAALgADCgUJBQAAAA==.Melethron:BAABLgAECn8+AAIEAAkJgRx7JgBoAgAEAAkJgRx7JgBoAgAAAA==.Melioknky:BAAALgAECgYJBgAAAA==.',
Mi='Michaeljfox:BAAALgAECgQJBAAAAA==.Mid:BAAALgADCgYJBgAAAA==.Mightymage:BAABLgAECn8hAAIDAAgJ4Q12hABrAQADAAgJ4Q12hABrAQAAAA==.Millie:BAAALgAECgEJAQAAAA==.Millionbaby:BAAALgAECgEJAQAAAA==.Milliondruid:BAAALgAECgMJBAAAAA==.Millionsm:BAAALgADCgQJBQAAAA==.Mirrorimage:BAABLgAFFH8GAAIGAAIJSwfeLwCBAAAGAAIJSwfeLwCBAAABLgAFFAYJEgAGAAgVAA==.Mirrorx:BAACLgAFFH8SAAIGAAYJCBW5DwBpAQAGAAYJCBW5DwBpAQAuAAQKfzIAAgYACQlzIP4IAL4CAAYACQlzIP4IAL4CAAAA.Miy:BAAALgAECgEJAQAAAA==.',
Mo='Mongon:BAAALgAECgYJBgAAAA==.Moogle:BAAALgAECgIJBAAAAA==.Moomie:BAABLgAECn8iAAIPAAgJAxayNwC2AQAPAAgJAxayNwC2AQAAAA==.Moosfel:BAABLgAECn8jAAIXAAcJGhoHDwC/AQAXAAcJGhoHDwC/AQAAAA==.Morubine:BAAALgAECgQJBgAAAA==.',
Mt='Mtzz:BAAALgAECgUJBQABLgAECgYJCAABAAAAAA==.',
Mu='Mudcake:BAAALgAECgEJAQAAAA==.',
My='Mygravebroke:BAAALgADCggJCQAAAA==.Mystdragon:BAACLgAFFH8UAAMWAAUJxRtEEQB5AQAWAAUJxRtEEQB5AQAYAAMJbQ5kQQC8AAAuAAQKfzAAAhYACQm5IXMDAA4DABYACQm5IXMDAA4DAAEuAAUUCAknAAcAmh0A.Mystweaverr:BAACLgAFFH8nAAMHAAgJmh1fBQC1AgAHAAgJmh1fBQC1AgAKAAEJ9QSaRQAxAAAuAAQKfy8AAwcACQn3H4AJALkCAAcACQn3H4AJALkCAAoAAgkjInZVALMAAAAA.',
['Mö']='Mörae:BAAALgADCgEJAQABLgAECgYJFwAPAA8bAA==.',
Na='Naddar:BAACLgAFFH8UAAIFAAUJpxnyFwBeAQAFAAUJpxnyFwBeAQAuAAQKf1UAAgUACQkMIHQGACQDAAUACQkMIHQGACQDAAAA.Namadgi:BAABLgAECn8tAAIPAAkJiR0pDQDwAgAPAAkJiR0pDQDwAgAAAA==.Nathria:BAAALgAECgIJAwAAAA==.',
Ne='Netalis:BAABLgAECn8lAAIPAAgJwxQrMQDaAQAPAAgJwxQrMQDaAQAAAA==.',
Ni='Nikonii:BAAALgAECgMJAwAAAA==.',
Nu='Nurckers:BAAALgAECgcJCAAAAA==.',
Oa='Oakinelf:BAAALgADCgcJAQAAAA==.',
Om='Omnishifts:BAAALgAECgEJAgAAAA==.',
Or='Oramo:BAABLgAECn8fAAMUAAgJfCMmBQDwAgAUAAgJxSImBQDwAgANAAYJgCKrawCLAQAAAA==.',
Ov='Ovaries:BAAALgADCgUJBQABLgAECgUJCQABAAAAAA==.',
Pa='Paktam:BAACLgAFFH8GAAIRAAMJvRVySQDDAAARAAMJvRVySQDDAAAuAAQKfxcAAhEABwnOHQseAFkCABEABwnOHQseAFkCAAAA.Paméla:BAAALgAECgcJDwABLgAECgkJcQAJAHggAA==.Paradisya:BAAALgADCggJDgAAAA==.',
Pe='Perceptor:BAAALgAECgEJAQABLgAECgkJKQAVAJMhAA==.Pets:BAAALgAECgEJAQABLgAECgkJVQACAC4VAA==.',
Pi='Pittliaq:BAAALgAECgkJCgAAAA==.',
Pl='Placebo:BAAALgAECgUJBQABLgAFFAUJEAAXAN4UAA==.',
Pr='Prothero:BAACLgAFFH8WAAMDAAYJpCFmJADpAQADAAYJpCFmJADpAQATAAEJZRmzBgBBAAAuAAQKfxkAAwMACQm0I+kIADIDAAMACQm0I+kIADIDABMACAkrGAMDAFACAAAA.Proyo:BAAALgADCgUJBQAAAA==.',
['På']='Påthor:BAACLgAFFH8HAAIdAAIJkw8APQB4AAAdAAIJkw8APQB4AAAuAAQKfyMAAx0ABwl6HOkgAL0BAB0ABwl6HOkgAL0BABUAAwkSEpFWAFsAAAAA.',
Ra='Raikonnen:BAAALgAECgEJAQAAAA==.Rapidstrikes:BAAALgAECgUJCAAAAA==.Rawtoor:BAACLgAFFH8mAAILAAcJShiJFAAAAgALAAcJShiJFAAAAgAuAAQKfyEAAgsACAk4IdInAGUCAAsACAk4IdInAGUCAAAA.',
Re='Rebelsister:BAAALgADCgcJEAAAAA==.Refridgerate:BAAALgADCgUJBwAAAA==.',
Ri='Riddagain:BAABLgAECn8bAAMkAAYJeA/1FAAHAQAkAAYJTw/1FAAHAQALAAIJwAsZGQEsAAAAAA==.Ridgemonk:BAABLgAECn87AAMOAAkJniNBAgA6AwAOAAkJniNBAgA6AwAHAAQJQAGYYABMAAAAAA==.Ridgerock:BAAALgAECgUJAwAAAA==.Riggsdk:BAAALgAECgMJAwABLgAFFAgJHwAfAKAiAA==.Riggse:BAAALgAFFAEJAQABLgAFFAgJHwAfAKAiAA==.Riggshunt:BAACLgAFFH8fAAQfAAgJoCLTAACrAQAeAAYJLCQuAAD7AQAfAAYJ8SDTAACrAQAgAAEJAAC/KABKAAAuAAQKfx4ABB8ACAmrJr0IAAcDAB8ABwmYJr0IAAcDAB4ACAmTJIQDAPICACAAAQmCHGd9AE8AAAAA.Riggspal:BAAALgAFFAIJAgABLgAFFAgJHwAfAKAiAA==.Riggswar:BAABLgAFFH8KAAMJAAUJER+FIwAhAQAJAAQJOR6FIwAhAQAaAAIJ0xoNLQCpAAABLgAFFAgJHwAfAKAiAA==.Riggzs:BAAALgAFFAIJAgABLgAFFAgJHwAfAKAiAA==.',
Ro='Roadkill:BAABLgAECn8gAAIUAAgJnSM4BAALAwAUAAgJnSM4BAALAwAAAA==.Rolltoor:BAABLgAFFH8GAAMKAAMJJRZWHwDXAAAKAAMJJRZWHwDXAAAOAAEJrgQUXgAwAAAAAA==.Roonate:BAAALgADCgUJBQAAAA==.Rosemary:BAAALgAECgQJBAAAAA==.',
Ry='Ryujin:BAAALgAECgQJCQAAAA==.',
Sa='Saiko:BAABLgAFFH8ZAAMMAAYJuBc5CAB9AQAMAAYJuBc5CAB9AQALAAQJzw19TQD9AAAAAA==.Sansa:BAACLgAFFH8ZAAIeAAgJPRhjAQBYAgAeAAgJPRhjAQBYAgAuAAQKfyMAAh4ACQlnI00CACMDAB4ACQlnI00CACMDAAAA.Saso:BAACLgAFFH8ZAAMDAAcJjR0FFwA2AgADAAcJjR0FFwA2AgATAAEJAxPOBQBMAAAuAAQKfzoABAMACQmVIt8SAOYCAAMACQmUIt8SAOYCABMABglXIxwEALsBACMAAwlnErALAHcAAAAA.Sastroll:BAAALgAECgUJBQAAAA==.',
Sc='Scorn:BAAALgADCgcJCAAAAA==.Scroll:BAABLgAECn8eAAIHAAkJ1RhIFwBZAgAHAAkJ1RhIFwBZAgAAAA==.',
Se='Seluvis:BAABLgAECn8WAAIDAAcJ0QEICgGYAAADAAcJ0QEICgGYAAAAAA==.Sentai:BAAALgADCgcJBwAAAA==.Serapayne:BAAALgAECgcJAQAAAA==.Serbitar:BAAALgAECgEJAQAAAA==.',
Sh='Shadow:BAACLgAFFH8cAAILAAcJxxSwHADCAQALAAcJxxSwHADCAQAuAAQKf18AAgsACQmbJG8DAE4DAAsACQmbJG8DAE4DAAAA.Shandrilah:BAAALgADCgQJBAAAAA==.Shapeshift:BAAALgADCgUJBQABLgAECgIJAgABAAAAAA==.Shialebuff:BAABLgAECn9JAAQGAAkJZhyQDQB6AgAGAAkJZhyQDQB6AgACAAkJzB+/EgBEAgAIAAQJFxmROQApAQAAAA==.Shijin:BAAALgAECgUJCQAAAA==.Shortfuze:BAAALgAECgYJDQAAAA==.',
Si='Sindar:BAAALgADCgUJBQAAAA==.Sinfall:BAAALgAECggJDgAAAA==.Siphon:BAAALgAECgEJAwAAAA==.Siscomp:BAABLgAECn9xAAIJAAkJeCCQEAByAgAJAAkJeCCQEAByAgAAAA==.Sixth:BAABLgAECn8XAAIiAAcJ/BrpJgCxAQAiAAcJ/BrpJgCxAQAAAA==.Sizzle:BAAALgADCgMJAwAAAA==.',
Sk='Skateboard:BAAALgADCgEJAQAAAA==.Sky:BAACLgAFFH8rAAIIAAcJ1B+sBgC7AgAIAAcJ1B+sBgC7AgAuAAQKfxQAAwgACAlxE48cALABAAgABwlZEo8cALABAAIABQnyD4hMAAYBAAAA.',
Sl='Sleck:BAAALgAECgYJDAAAAA==.',
Sm='Smooth:BAAALgAECgEJAQABLgAFFAYJCAAIAEcTAA==.',
Sn='Snappa:BAAALgADCgYJCwAAAA==.Sniped:BAAALgAFFAEJAQAAAA==.Snugglepuff:BAABLgAECn8XAAIJAAkJphQHHAAMAgAJAAkJphQHHAAMAgAAAA==.',
So='Soapfidas:BAAALgADCggJCgAAAA==.Sonarius:BAACLgAFFH8QAAIDAAUJkht2SwBPAQADAAUJkht2SwBPAQAuAAQKfx0ABAMACAndHyk8AIYCAAMACAndHyk8AIYCABMAAgkCHSgNAKMAACMAAQmyEg8PADwAAAAA.Sophie:BAAALgAECgEJAwAAAA==.',
Sp='Splitterman:BAABLgAFFH8YAAQUAAcJLyCOBQAzAgAUAAcJJSCOBQAzAgASAAUJrxy5BwBpAQANAAMJLRU3uwCrAAAAAA==.',
Su='Su:BAABLgAECn8yAAIHAAcJ4yVlBwDiAgAHAAcJ4yVlBwDiAgAAAA==.Sudno:BAAALgAECgQJCAAAAA==.Sundae:BAABLgAECn83AAQCAAkJlSG4CADbAgACAAgJHCO4CADbAgAIAAgJhxtSDgCHAgAGAAMJ3BZjVQC6AAAAAA==.Sunwukong:BAAALgAECgUJCQAAAA==.Supersinpe:BAAALgAECgIJAgAAAA==.',
Sv='Svdrag:BAAALgAECgMJAwAAAA==.Svendlefyre:BAAALgADCgcJDgABLgAECgkJLgAXAIMZAA==.Svholydrag:BAAALgADCgEJAQAAAA==.Svmishima:BAAALgAECgMJBQAAAA==.',
Sw='Swirly:BAAALgAECgEJAQAAAA==.',
Sy='Sylvie:BAABLgAECn8nAAIfAAkJwRWJKQA0AgAfAAkJwRWJKQA0AgAAAA==.',
['Sý']='Sýlvanas:BAABLgAECn8UAAIgAAUJVxNJGADrAAAgAAUJVxNJGADrAAAAAA==.',
Te='Tealç:BAABLgAECn8gAAIbAAcJpheVGACQAQAbAAcJpheVGACQAQABLgAFFAQJGQAbAEcfAA==.Tekk:BAAALgAECgEJAQAAAA==.Tekkys:BAAALgAECgEJAgAAAA==.Tertle:BAAALgADCgUJBQAAAA==.',
Ti='Tiafinia:BAAALgAECgEJAgAAAA==.Tiggerstripe:BAAALgADCgEJAQABLgAECgkJMQAhAEMQAA==.Timmyy:BAAALgAECgYJBgABLgAFFAQJCQANAAAOAA==.Timur:BAAALgAECgMJBAAAAA==.Tinara:BAAALgADCgUJBQAAAA==.',
To='Tome:BAAALgAECgEJAQABLgAECgkJHgAHANUYAA==.',
Tr='Trigger:BAAALgAECgIJAgAAAA==.',
Tu='Turlesblows:BAABLgAECn8hAAMJAAgJYyDfJADOAQAJAAgJYyDfJADOAQAbAAEJOxWZRAA7AAAAAA==.',
Tw='Twityy:BAAALgADCgEJAgAAAA==.Twofiveyd:BAABLgAFFH8FAAIYAAQJjA8JNADwAAAYAAQJjA8JNADwAAABLgAFFAYJFAAaAGcYAA==.',
Ty='Tyladrhas:BAABLgAECn80AAIkAAkJVB+2AwCXAgAkAAkJVB+2AwCXAgAAAA==.Tyrismaximus:BAAALgAECgYJDQAAAA==.',
Ul='Ulkina:BAAALgADCgYJCQAAAA==.',
Up='Up:BAAALgAECgYJBgAAAA==.',
Va='Vaelith:BAAALgAECgIJAgAAAA==.Vaelyth:BAAALgAECgcJBwAAAA==.Valerine:BAABLgAECn8aAAIDAAkJ/woufwB2AQADAAkJ/woufwB2AQAAAA==.Vanoran:BAAALgAECgMJBAAAAA==.Varina:BAAALgAECgcJEwAAAA==.',
Ve='Velsaert:BAAALgAECgEJAQAAAA==.Venki:BAAALgAECgkJDAAAAA==.',
Vi='Vitani:BAAALgADCgIJAgABLgAFFAUJEAAXAN4UAA==.',
Vo='Voidnova:BAABLgAFFH8HAAIDAAMJlRDIhQDTAAADAAMJlRDIhQDTAAAAAA==.Voidphayze:BAAALgAECgUJDAABLgAFFAMJBQANAEUTAA==.',
Vu='Vulken:BAABLgAECn9nAAIfAAkJESU8DwDTAgAfAAkJESU8DwDTAgAAAA==.',
['Vê']='Vê:BAAALgAECgkJEQAAAA==.',
Wa='Wallace:BAAALgAECgcJDAAAAA==.Walterlight:BAAALgAECgYJDgAAAA==.Watto:BAABLgAECn8ZAAMRAAkJOR/XFgCPAgARAAkJOR/XFgCPAgAiAAUJmRaBSQAKAQAAAA==.',
We='Wemongin:BAAALgADCgUJBQAAAA==.',
Wh='Whimsical:BAABLgAECn8XAAIRAAYJgBfbTwBuAQARAAYJgBfbTwBuAQAAAA==.',
Wi='Winnìng:BAACLgAFFH8FAAIcAAMJeQX+EAByAAAcAAMJeQX+EAByAAAuAAQKfyQAAhwACQmmDIEZAEoBABwACQmmDIEZAEoBAAAA.',
Wu='Wugong:BAAALgADCgEJAQAAAA==.Wulfi:BAAALgAECgYJBgAAAA==.',
['Wó']='Wórkwórk:BAACLgAFFH8FAAIJAAMJKhROFwCsAAAJAAMJKhROFwCsAAAuAAQKfxsAAwkACQk6Gxg3AMsBAAkABwnRGRg3AMsBABoAAwnsGr8fAO8AAAAA.',
Ze='Zerg:BAAALgAECgIJAgAAAA==.',
Zi='Zich:BAAALgADCgMJAwAAAA==.Zihon:BAABLgAECn8UAAINAAQJTxpR6gDDAAANAAQJTxpR6gDDAAAAAA==.',
Zo='Zodiiak:BAABLgAECn9EAAIhAAkJMR3wBgBgAgAhAAkJMR3wBgBgAgAAAA==.',
Zu='Zubb:BAAALgAECgUJBgABLgAECggJEAABAAAAAA==.Zugg:BAAALgAECgIJAgABLgAECggJEAABAAAAAA==.Zuhh:BAAALgAECgEJAgABLgAECggJEAABAAAAAA==.Zupp:BAAALgAECggJEAAAAA==.',
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
