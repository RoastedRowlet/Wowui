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

local lookup = {'Priest-Discipline','Unknown-Unknown','Priest-Holy','Mage-Frost','Paladin-Retribution','Paladin-Holy','Monk-Mistweaver','Priest-Shadow','Warrior-Fury','Monk-Windwalker','Druid-Restoration','Warlock-Demonology','DeathKnight-Unholy','DeathKnight-Frost','Mage-Arcane','Druid-Guardian','Monk-Brewmaster','Druid-Feral','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Blood','Warrior-Arms','Warrior-Protection','DemonHunter-Devourer','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Enhancement','Shaman-Restoration','Shaman-Elemental','DemonHunter-Vengeance','Evoker-Preservation','Druid-Balance','DemonHunter-Havoc','Mage-Fire','Paladin-Protection',}
local provider = {region='US',realm='Gundrak',name='US',type='weekly',zone=46,date='2026-05-16',data={Ad='Adelyne:BAAALgAFFAIJAgABLgAFFAUJDgABAG0SAA==.Adera:BAAALgAECgYJBwAAAA==.',
Af='Aff:BAAALgADCgYJBgAAAA==.',
Ag='Agony:BAAALgAECgMJAwAAAA==.',
Ah='Ahkanon:BAAALgADCgEJAQAAAA==.',
Ai='Aiden:BAAALgAECgEJAgABLgAECgIJAgACAAAAAA==.Aidendk:BAAALgADCgIJAgABLgAECgIJAgACAAAAAA==.Aidenp:BAAALgADCgIJAgABLgAECgIJAgACAAAAAA==.Air:BAAALgADCgcJBwABLgAFFAcJGwADAJcbAA==.',
Ak='Aku:BAAALgADCgIJBAAAAA==.',
Al='Aleniastra:BAAALgAECgUJDQAAAA==.Alexyss:BAAALgAECgUJDgAAAA==.Alykard:BAABLgAECn8oAAIEAAkJZQ5eSAC/AQAEAAkJZQ5eSAC/AQAAAA==.',
Am='Amyara:BAAALgADCgEJAQAAAA==.',
An='Andronicas:BAABLgAECn8dAAMFAAkJ5w2ARACwAQAFAAkJ5w2ARACwAQAGAAEJogevnAAtAAAAAA==.Aneira:BAABLgAFFH8GAAIEAAIJRgQafwCOAAAEAAIJRgQafwCOAAAAAA==.',
Ap='Apexis:BAAALgADCgYJCQAAAA==.',
Ar='Ariaa:BAAALgAECgIJBAAAAA==.Arieyri:BAAALgADCgcJBwAAAA==.Artpop:BAAALgAFFAEJAQABLgAFFAUJDQAHAJATAA==.',
As='Ash:BAAALgADCgcJCwAAAA==.Aspect:BAAALgADCgcJDgABLgAECgEJAQACAAAAAA==.Astarael:BAABLgAECn8hAAMIAAgJGhYDFgDIAQAIAAgJGhYDFgDIAQADAAYJYw/gWgDIAAAAAA==.',
Av='Avi:BAABLgAECn8XAAIBAAgJkRBlFwDAAQABAAgJkRBlFwDAAQABLgAECgkJbAAJABcgAA==.',
Ba='Babygurl:BAACLgAFFH8FAAIGAAMJVB8jGAAXAQAGAAMJVB8jGAAXAQAuAAQKf3YAAgYACQntJcMAAKIDAAYACQntJcMAAKIDAAAA.Baragas:BAAALgAECgYJCgAAAA==.Barney:BAAALgADCgEJAQAAAA==.Battosaî:BAAALgAECgQJBAAAAA==.',
Be='Beeny:BAACLgAFFH8uAAIHAAcJUSLDAQCdAgAHAAcJUSLDAQCdAgAuAAQKfz8AAwcACAmUI4UIAMwCAAcABwmlJIUIAMwCAAoAAQlsEHprADgAAAAA.Berat:BAAALgADCgQJBAAAAA==.Berzerker:BAAALgADCgcJEwAAAA==.',
Bg='Bgc:BAAALgADCgUJBQAAAA==.',
Bi='Binari:BAAALgAECgMJAwABLgAFFAMJBQAJACoUAA==.Binlock:BAAALgAECgQJBAABLgAFFAMJBQAJACoUAA==.',
Bl='Bl:BAAALgAECgMJAwAAAA==.Bladebear:BAABLgAECn82AAIEAAkJUhX/NAADAgAEAAkJUhX/NAADAgAAAA==.',
Bo='Boose:BAAALgAECgYJBgAAAA==.Bootybreaker:BAAALgADCgcJBwAAAA==.',
Br='Brat:BAAALgAECgEJBAABLgAECggJTQADAHcWAA==.Bréwmaster:BAAALgAECgEJAQABLgAECggJIQAIABoWAA==.',
Bu='Bubbelz:BAAALgAECgMJAwAAAA==.Bubbleez:BAAALgADCgUJBQAAAA==.Bucklord:BAABLgAECn8iAAMIAAgJjRkAFwAuAgAIAAgJjRkAFwAuAgADAAEJABkuVAA/AAAAAA==.Budin:BAAALgAECggJEgAAAA==.Bullmann:BAAALgADCgQJBAAAAA==.',
Ca='Cannibal:BAABLgAECn8mAAILAAkJ5hqCDQCuAgALAAkJ5hqCDQCuAgAAAA==.Caplock:BAABLgAECn8VAAIMAAYJoRFohABRAQAMAAYJoRFohABRAQAAAA==.Capri:BAAALgAECgUJDQAAAA==.',
Ce='Cellun:BAAALgAECgUJEQAAAA==.Centipede:BAAALgAECgYJBgABLgAECgYJEQACAAAAAA==.Ceredis:BAAALgAECgUJCwAAAA==.',
Ch='Choomoo:BAAALgADCgcJCwABLgAFFAUJDQAHAOUJAA==.',
Cl='Cleankarma:BAAALgADCgEJAwAAAA==.',
Co='Comet:BAAALgAECgEJAQAAAA==.Cool:BAAALgAFFAIJAgAAAA==.Corwiggs:BAAALgAECgYJCwAAAA==.',
Cr='Crikey:BAAALgAECgUJBwAAAA==.Crimínal:BAAALgADCgcJCwAAAA==.Cripsee:BAAALgADCgMJAwAAAA==.',
Cu='Curbie:BAAALgAECgIJAwAAAA==.',
Cy='Cyndrixx:BAAALgAECgEJAQAAAA==.',
['Cô']='Cônvict:BAAALgADCgYJBgAAAA==.',
De='Deacknight:BAABLgAECn8cAAMNAAgJwRuPLgB+AgANAAgJwRuPLgB+AgAOAAEJig2BFwAyAAABLgADCgYJBwACAAAAAA==.Deacmonk:BAAALgADCgYJBgABLgADCgYJBwACAAAAAA==.Definitely:BAACLgAFFH8LAAIEAAMJAxs8TQAQAQAEAAMJAxs8TQAQAQAuAAQKfysAAwQACAmaI8MVAJ8CAAQACAmaI8MVAJ8CAA8AAQkPICobAD8AAAAA.Deki:BAEALgAECgYJBgAAAA==.Dementiaous:BAAALgAECgIJAwAAAA==.Desariana:BAABLgAECn8lAAIFAAkJexBIPwDAAQAFAAkJexBIPwDAAQAAAA==.',
Di='Diggitie:BAAALgAECgEJAQAAAA==.Ditto:BAAALgAFFAQJBAAAAA==.',
Do='Dormas:BAABLgAECn8XAAIQAAYJihE/GwDyAAAQAAYJihE/GwDyAAAAAA==.Doug:BAAALgADCgEJAQAAAA==.',
Dr='Drakeon:BAAALgAECgcJDwABLgAECgkJbAAJABcgAA==.',
Ee='Eeryxx:BAAALgAECgEJAQAAAA==.',
El='Eldh:BAABLgAECn8ZAAIRAAgJVAuDJwA2AQARAAgJVAuDJwA2AQAAAA==.Eleison:BAAALgADCgMJAwAAAA==.Elendrial:BAAALgAECgIJAgAAAA==.Elendril:BAAALgADCgcJFQAAAA==.Elisoly:BAACLgAFFH8FAAIGAAIJDQygKwB+AAAGAAIJDQygKwB+AAAuAAQKfxkAAgYABgmiGdEkAJQBAAYABgmiGdEkAJQBAAAA.',
Em='Emrald:BAAALgAECgYJEwAAAA==.',
En='Endlessly:BAACLgAFFH8NAAISAAQJ3hRHAwBjAQASAAQJ3hRHAwBjAQAuAAQKfyIAAhIACAmfIukDAOsCABIACAmfIukDAOsCAAAA.Enerchi:BAAALgADCgMJAwAAAA==.',
Er='Erivoker:BAAALgAECgYJCwABLgAECgYJEgACAAAAAA==.Errimage:BAAALgAECgYJEgAAAA==.Errishoot:BAAALgAECgUJCAABLgAECgYJEgACAAAAAA==.Ervinia:BAAALgADCgYJCgABLgAECgUJDQACAAAAAA==.',
Ev='Evelinar:BAAALgAECgMJAwAAAA==.Evoslex:BAABLgAECn85AAMTAAkJwSP5AgAfAwATAAkJwSP5AgAfAwAUAAYJzx1vEwCsAQAAAA==.',
Ex='Exo:BAECLgAFFH8eAAIVAAUJ6h6JCABpAQAVAAUJ6h6JCABpAQAuAAQKfysAAhUACQktIg8CAA4DABUACQktIg8CAA4DAAAA.',
Fa='Facerolleh:BAACLgAFFH8rAAMWAAcJpCLyAAA7AgAWAAcJUyLyAAA7AgAJAAQJZiGMBgCGAQAuAAQKf0QABAkACAlJJs4EAFwDAAkACAn2Jc4EAFwDABYABwm7IiwGAE8CABcAAgm1HQAAAAAAAAAA.Fatedx:BAAALgADCgIJAgAAAA==.',
Fe='Feelgoodinc:BAAALgADCgkJFAAAAA==.',
Fi='Fidah:BAAALgADCgEJAQAAAA==.Firemagemain:BAAALgADCgUJBQABLgAFFAMJBQAJACoUAA==.',
Fl='Flanann:BAAALgAECgEJAQABLgAECgMJCAACAAAAAA==.Flop:BAAALgAECgUJCQABLgAECggJHQAEAN0fAA==.Flora:BAAALgAECgEJAQAAAA==.',
Fr='Frostmere:BAAALgADCggJGQAAAA==.',
Fu='Fuknazum:BAAALgAECgEJAQAAAA==.Furcht:BAAALgAECgYJEgAAAA==.',
Ga='Galadar:BAAALgADCgUJBQAAAA==.',
Gi='Giteff:BAABLgAFFH8KAAIYAAcJ9iFiAgBxAgAYAAcJ9iFiAgBxAgAAAA==.Gitèff:BAAALgAFFAIJBAABLgAFFAgJCgAYAPYhAA==.Giveroflife:BAAALgADCgcJBwAAAA==.',
Go='Gourdin:BAAALgAECgQJBQABLgAECgYJCAACAAAAAA==.',
Gr='Gramnpa:BAAALgADCgUJBQAAAA==.Gravepriest:BAAALgAECgEJAQAAAA==.Grimtysha:BAAALgAECgYJBwAAAA==.Grimveil:BAAALgAECgYJBwAAAA==.Gromit:BAAALgAECgQJCQAAAA==.',
Ha='Harafar:BAAALgAFFAEJAQAAAA==.',
He='Hellbourne:BAABLgAECn8gAAIYAAgJrBfBLADLAQAYAAgJrBfBLADLAQAAAA==.',
Hi='Himmel:BAAALgADCgcJCQAAAA==.',
Ho='Hopnhorsé:BAAALgADCgEJAQAAAA==.Hotchoq:BAAALgAFFAIJBAAAAA==.',
Hu='Huntchoq:BAABLgAFFH8LAAQZAAUJKw9RDQA2AQAZAAUJfgxRDQA2AQAaAAIJVQhGVACKAAAbAAEJlBF+IgBGAAAAAA==.Huxley:BAAALgADCgMJAwAAAA==.',
Ik='Ikan:BAAALgAECgUJBwAAAA==.',
In='Infest:BAAALgAECgQJCAAAAA==.Inzolethys:BAAALgADCgcJBwAAAA==.',
It='Itchy:BAAALgADCgEJAgAAAA==.Itskiohte:BAABLgAECn8hAAIcAAkJOQ0qCgCwAQAcAAkJOQ0qCgCwAQAAAA==.',
Ja='Jaggernut:BAAALgADCgUJBQAAAA==.',
Jo='Johnny:BAAALgAECgIJAgABLgAECgkJOQATAMEjAA==.',
Ju='Judeau:BAAALgADCgEJAQAAAA==.',
Ka='Kaelthuzzad:BAAALgADCgEJAQAAAA==.Kaitza:BAAALgAECgYJCwAAAA==.Kalzaketh:BAABLgAECn83AAMTAAgJ8gpBLAAzAQATAAgJ8gpBLAAzAQAUAAMJ5QSIMwB5AAAAAA==.Kashari:BAAALgAECgEJAwABLgAECgkJcgAIALQaAA==.Katali:BAAALgAECgMJBQAAAA==.Kazuggar:BAACLgAFFH8TAAIdAAQJGiEgEAByAQAdAAQJGiEgEAByAQAuAAQKfyoAAx0ACAlRJW4CAFwDAB0ACAlRJW4CAFwDAB4AAwleGlJdAM4AAAAA.Kazzn:BAAALgAECgYJBgAAAA==.',
Ke='Kedar:BAAALgAECgYJCwAAAA==.Keg:BAAALgAECgIJAgAAAA==.Kelabar:BAAALgADCgQJBAAAAA==.',
Ki='Kick:BAAALgADCgQJBAABLgAFFAYJFQAEAFwVAA==.Kiffs:BAAALgAECgcJCgAAAA==.Kill:BAAALgAECgUJCwABLgAECggJBAACAAAAAA==.Killerman:BAABLgAFFH8KAAMOAAcJNh1VAwBXAQAOAAUJ7R1VAwBXAQANAAQJvhtuSQAkAQAAAA==.Kirâ:BAAALgAECggJEAAAAA==.',
Kr='Kregnar:BAABLgAECn8fAAIWAAgJFhdjDADMAQAWAAgJFhdjDADMAQAAAA==.Kresh:BAAALgAECgcJCwAAAA==.',
Ku='Kucabara:BAAALgAECgEJAgAAAA==.Kuraiwiggs:BAAALgADCgYJDAAAAA==.Kushyellow:BAAALgADCgEJAQAAAA==.',
Kw='Kwichang:BAABLgAECn8ZAAIEAAcJuw+3bwBbAQAEAAcJuw+3bwBbAQAAAA==.',
['Ké']='Kélpo:BAAALgADCgMJBAAAAA==.',
La='Lasagne:BAAALgADCgMJAwAAAA==.',
Li='Lickynose:BAABLgAECn8hAAIEAAgJFiG9HQBvAgAEAAgJFiG9HQBvAgAAAA==.Lips:BAAALgAECgEJAQAAAA==.',
Ls='Ls:BAABLgAECn8aAAMYAAgJmiG9MQAzAgAYAAgJmiG9MQAzAgAfAAcJYhWVCQB8AQAAAA==.',
Ma='Madarabia:BAAALgAECgYJDQAAAA==.Magnius:BAAALgAECgMJAwAAAA==.Mamut:BAAALgAECgEJAQAAAA==.Mantisar:BAACLgAFFH8FAAIFAAMJ8A1MQQDpAAAFAAMJ8A1MQQDpAAAuAAQKfx4AAgUABwnmHm4kACwCAAUABwnmHm4kACwCAAAA.Maxsm:BAABLgAECn8XAAIeAAgJrhmSIQACAgAeAAgJrhmSIQACAgAAAA==.',
Me='Melanippe:BAABLgAECn8XAAILAAYJDxtuPQCuAQALAAYJDxtuPQCuAQAAAA==.Meleefox:BAAALgADCgUJBQAAAA==.Melethron:BAABLgAECn8+AAIFAAkJghzYEwCQAgAFAAkJghzYEwCQAgAAAA==.Melioknky:BAAALgAECgYJBgAAAA==.',
Mi='Mid:BAAALgADCgYJBgAAAA==.Mightymage:BAABLgAECn8hAAIEAAgJ4Q3CYQB7AQAEAAgJ4Q3CYQB7AQAAAA==.Milliondruid:BAAALgAECgMJBAAAAA==.Millionsm:BAAALgADCgQJBQAAAA==.Mirrorimage:BAAALgAECgMJBQABLgAFFAUJEAAIANgUAA==.Mirrorx:BAACLgAFFH8QAAIIAAUJ2BQTDgBIAQAIAAUJ2BQTDgBIAQAuAAQKfyoAAggACAkgID0NADECAAgACAkgID0NADECAAAA.Miy:BAAALgAECgEJAQAAAA==.',
Mo='Mongon:BAAALgAECgYJBgAAAA==.Moogle:BAAALgAECgIJBAAAAA==.Moomie:BAABLgAECn8cAAILAAgJ0RTTOwC1AQALAAgJ0RTTOwC1AQAAAA==.Moosfel:BAABLgAECn8XAAISAAYJ6xbqEwAaAQASAAYJ6xbqEwAaAQAAAA==.',
Mt='Mtzz:BAAALgAECgUJBQABLgAECgYJCAACAAAAAA==.',
Mu='Mudcake:BAAALgAECgEJAQAAAA==.',
My='Mygravebroke:BAAALgADCggJCQAAAA==.Mystdragon:BAACLgAFFH8OAAIgAAQJCh8eDgBSAQAgAAQJCh8eDgBSAQAuAAQKfzAAAiAACQm9IScCAB0DACAACQm9IScCAB0DAAEuAAUUCAkkAAcAsBoA.Mystweaverr:BAACLgAFFH8kAAMHAAgJsBq+AQCfAgAHAAgJsBq+AQCfAgAKAAEJ9QT9KgA7AAAuAAQKfy8AAwcACQn3H4AJALkCAAcACQn3H4AJALkCAAoAAgkjIq88AL4AAAAA.',
['Mö']='Mörae:BAAALgADCgEJAQABLgAECgYJFwALAA8bAA==.',
Na='Naddar:BAACLgAFFH8NAAIGAAUJRhbBDQB6AQAGAAUJRhbBDQB6AQAuAAQKfzYAAgYACQlpHQ8FAAUDAAYACQlpHQ8FAAUDAAAA.Namadgi:BAABLgAECn8ZAAILAAgJ+hlXGgArAgALAAgJ+hlXGgArAgAAAA==.Nathria:BAAALgAECgIJAwAAAA==.',
Ne='Netalis:BAABLgAECn8eAAILAAgJsxGTLwCbAQALAAgJsxGTLwCbAQAAAA==.',
Ni='Nikonii:BAAALgADCgQJBAAAAA==.',
Nu='Nurckers:BAAALgAECgcJCAAAAA==.',
Oa='Oakinelf:BAAALgADCgcJAQAAAA==.',
Om='Omnishifts:BAAALgAECgEJAQAAAA==.',
Or='Oramo:BAABLgAECn8fAAMVAAgJfCMmBQDwAgAVAAgJxSImBQDwAgANAAYJgCIbSwCZAQAAAA==.',
Ov='Ovaries:BAAALgADCgUJBQABLgAECgQJBQACAAAAAA==.',
Pa='Paktam:BAAALgAECgUJBQAAAA==.Paradisya:BAAALgADCggJDgAAAA==.',
Pe='Perceptor:BAAALgAECgEJAQABLgAECgkJKQAQAJQhAA==.Pets:BAAALgAECgEJAQABLgAECggJTQADAHcWAA==.',
Pl='Placebo:BAAALgAECgUJBQABLgAFFAQJDQASAN4UAA==.',
Pr='Prothero:BAACLgAFFH8PAAMEAAUJoR/GIgB2AQAEAAUJoR/GIgB2AQAPAAEJZRmTAgBSAAAuAAQKfxYAAwQACQnGIAEOANgCAAQACQnGIAEOANgCAA8ACAkrGAMDAFACAAAA.Proyo:BAAALgADCgUJBQAAAA==.',
['På']='Påthor:BAACLgAFFH8HAAIhAAIJkw/rJgCQAAAhAAIJkw/rJgCQAAAuAAQKfx8AAyEABwk4HMUWAMEBACEABwk4HMUWAMEBABAAAwkSErowAGIAAAAA.',
Ra='Raikonnen:BAAALgAECgEJAQAAAA==.Rapidstrikes:BAAALgADCgEJAQAAAA==.Rawtoor:BAACLgAFFH8bAAIYAAYJbRkREgCSAQAYAAYJbRkREgCSAQAuAAQKfyEAAhgACAk4If4jAPgBABgACAk4If4jAPgBAAAA.',
Re='Rebelsister:BAAALgADCgcJEAAAAA==.Refridgerate:BAAALgADCgUJBwAAAA==.',
Ri='Riddagain:BAABLgAECn8VAAMfAAYJeA/1FAAHAQAfAAYJTw/1FAAHAQAYAAIJwAt72gArAAAAAA==.Ridgemonk:BAABLgAECn8pAAMRAAkJOR7WBgCVAgARAAkJOR7WBgCVAgAHAAQJQAGYYABMAAAAAA==.Riggsdk:BAAALgADCgcJBwABLgAFFAgJGgAaAKEiAA==.Riggse:BAAALgAECggJCgABLgAFFAgJGgAaAKEiAA==.Riggshunt:BAACLgAFFH8aAAQaAAgJoSLTAACrAQAZAAYJLCQuAAD7AQAaAAYJ8iDTAACrAQAbAAEJAAC/KABKAAAuAAQKfx4ABBoACAmrJr0IAAcDABoABwmYJr0IAAcDABkACAmTJIQDAPICABsAAQmCHGd9AE8AAAAA.Riggzs:BAAALgAECgUJCAABLgAFFAgJGgAaAKEiAA==.',
Ro='Roadkill:BAABLgAECn8gAAIVAAgJnSM4BAALAwAVAAgJnSM4BAALAwAAAA==.Rolltoor:BAAALgAFFAIJAwAAAA==.Roonate:BAAALgADCgUJBQAAAA==.Rosemary:BAAALgAECgQJBAAAAA==.',
Ry='Ryujin:BAAALgAECgQJCQAAAA==.',
Sa='Saiko:BAABLgAFFH8MAAIiAAQJKBUaBwBCAQAiAAQJKBUaBwBCAQAAAA==.Sansa:BAACLgAFFH8RAAIZAAYJ7hnGAwCQAQAZAAYJ7hnGAwCQAQAuAAQKfyEAAhkACAlmJE0CACMDABkACAlmJE0CACMDAAAA.Saso:BAACLgAFFH8QAAIEAAUJFhsHGwBfAQAEAAUJFhsHGwBfAQAuAAQKfzMABAQACQmRIjQLAPACAAQACQmRIjQLAPACAA8AAwkDH0gMAA0BACMAAgnECLALAHcAAAAA.Sastroll:BAAALgAECgUJBQAAAA==.',
Sc='Scorn:BAAALgADCgcJCAAAAA==.Scroll:BAAALgAECggJEgAAAA==.',
Se='Seluvis:BAAALgAECgYJEQAAAA==.Sentai:BAAALgADCgcJBwAAAA==.Serapayne:BAAALgAECgcJAQAAAA==.',
Sh='Shadow:BAACLgAFFH8LAAIYAAUJWhIjKgAoAQAYAAUJWhIjKgAoAQAuAAQKf1QAAhgACAnFJIsHAOQCABgACAnFJIsHAOQCAAAA.Shandrilah:BAAALgADCgQJBAAAAA==.Shapeshift:BAAALgADCgUJBQABLgAECgIJAgACAAAAAA==.Shialebuff:BAABLgAECn8yAAQDAAkJfR9TEAAcAgADAAkJfR9TEAAcAgAIAAcJCh12EgDvAQABAAEJkwb7WAAuAAAAAA==.Shijin:BAAALgAECgQJBQAAAA==.Shortfuze:BAAALgAECgYJCwAAAA==.',
Si='Sindar:BAAALgADCgUJBQAAAA==.Sinfall:BAAALgAECggJDgAAAA==.Siphon:BAAALgAECgEJAgAAAA==.Siscomp:BAABLgAECn9sAAIJAAkJFyD/CQB+AgAJAAkJFyD/CQB+AgAAAA==.Sixth:BAAALgAECgYJEQAAAA==.Sizzle:BAAALgADCgMJAwAAAA==.',
Sk='Skateboard:BAAALgADCgEJAQAAAA==.Sky:BAACLgAFFH8YAAIBAAcJBxSlBABNAgABAAcJBxSlBABNAgAuAAQKfxQAAwEACAlxE48cALABAAEABwlZEo8cALABAAMABQnyD4hMAAYBAAAA.',
Sl='Sleck:BAAALgAECgYJDAAAAA==.',
Sn='Snappa:BAAALgADCgYJCwAAAA==.Sniped:BAAALgAFFAEJAQAAAA==.Snugglepuff:BAAALgAECggJDQAAAA==.',
So='Soapfidas:BAAALgADCggJCgAAAA==.Sonarius:BAABLgAECn8dAAQEAAgJ3R8pPACGAgAEAAgJ3R8pPACGAgAPAAIJAR1pCQCvAAAjAAEJshIPDwA8AAAAAA==.Sophie:BAAALgAECgEJAQAAAA==.',
Sp='Splitterman:BAAALgAFFAEJAQAAAA==.',
Su='Su:BAABLgAECn8yAAIHAAcJ4yVlBwDiAgAHAAcJ4yVlBwDiAgAAAA==.Sudno:BAAALgAECgQJCAABLgAFFAYJFAAMABYaAA==.Sundae:BAABLgAECn8vAAQDAAkJ8CCRBAD8AgADAAgJHCORBAD8AgABAAgJWRh6GgCiAQAIAAMJ3BavPADIAAAAAA==.Sunwukong:BAAALgAECgUJCQAAAA==.Supersinpe:BAAALgAECgIJAgAAAA==.',
Sv='Svendlefyre:BAAALgADCgcJDgABLgAECggJLQASAMIZAA==.Svholydrag:BAAALgADCgEJAQAAAA==.Svmishima:BAAALgAECgEJAQAAAA==.',
Sy='Sylvie:BAAALgAECgkJEwAAAA==.',
['Sý']='Sýlvanas:BAAALgAECgQJDwAAAA==.',
Te='Tealç:BAABLgAECn8gAAIXAAcJpheVGACQAQAXAAcJpheVGACQAQABLgAFFAQJDgAXADsYAA==.Tekk:BAAALgAECgEJAQAAAA==.Tekkys:BAAALgAECgEJAgAAAA==.Tertle:BAAALgADCgUJBQAAAA==.',
Ti='Tiafinia:BAAALgAECgEJAgAAAA==.Tiggerstripe:BAAALgADCgEJAQABLgAECggJLAAcAA0QAA==.Timmyy:BAAALgAECgYJBgABLgAECgkJFwANAG4cAA==.Timur:BAAALgAECgMJBAAAAA==.Tinara:BAAALgADCgUJBQAAAA==.',
Tr='Trigger:BAAALgAECgIJAgAAAA==.',
Tu='Turlesblows:BAABLgAECn8fAAMJAAgJ4B+LGQDTAQAJAAgJ4B+LGQDTAQAXAAEJOxWZRAA7AAAAAA==.',
Tw='Twityy:BAAALgADCgEJAgAAAA==.Twofiveyd:BAAALgAFFAEJAQABLgAFFAYJFAAWAGcYAA==.',
Ty='Tyladrhas:BAABLgAECn8xAAIfAAgJgh9pAwBZAgAfAAgJgh9pAwBZAgAAAA==.Tyrismaximus:BAAALgAECgMJAwAAAA==.',
Ul='Ulkina:BAAALgADCgYJCQAAAA==.',
Va='Vaelith:BAAALgAECgIJAgAAAA==.Valerine:BAABLgAECn8YAAIEAAcJlw2chQAwAQAEAAcJlw2chQAwAQAAAA==.Vanoran:BAAALgAECgMJBAAAAA==.Varang:BAAALgAECgIJAgAAAA==.Varina:BAAALgAECgcJEwAAAA==.',
Ve='Velsaert:BAAALgADCgcJBwAAAA==.Venki:BAAALgAECgYJBgAAAA==.',
Vo='Voidnova:BAABLgAFFH8HAAIEAAMJlRD/WgDuAAAEAAMJlRD/WgDuAAAAAA==.Voidphayze:BAAALgAECgUJDAABLgAECgkJJQANAF4bAA==.',
Vu='Vulken:BAABLgAECn9nAAIaAAkJECUhBQAKAwAaAAkJECUhBQAKAwAAAA==.',
['Vê']='Vê:BAAALgAECgkJEQAAAA==.',
Wa='Wallace:BAAALgAECgcJDAAAAA==.Walterlight:BAAALgAECgYJDgAAAA==.Watto:BAAALgAFFAEJAQAAAA==.',
We='Wemongin:BAAALgADCgUJBQAAAA==.',
Wh='Whimsical:BAAALgAECgYJEQAAAA==.',
Wi='Winnìng:BAABLgAECn8eAAIkAAgJ2gpVGwDmAAAkAAgJ2gpVGwDmAAAAAA==.',
Wu='Wugong:BAAALgADCgEJAQAAAA==.',
['Wó']='Wórkwórk:BAACLgAFFH8FAAIJAAMJKhROFwCsAAAJAAMJKhROFwCsAAAuAAQKfxsAAwkACQk6Gxg3AMsBAAkABwnRGRg3AMsBABYAAwnsGr8fAO8AAAAA.',
Zi='Zich:BAAALgADCgMJAwAAAA==.Zihon:BAABLgAECn8UAAINAAQJTxpBqgDOAAANAAQJTxpBqgDOAAAAAA==.',
Zo='Zodiiak:BAABLgAECn8+AAIcAAgJgh43CQDGAQAcAAgJgh43CQDGAQAAAA==.',
Zu='Zubb:BAAALgADCgMJAwABLgAECggJEAACAAAAAA==.Zuhh:BAAALgAECgEJAQABLgAECggJEAACAAAAAA==.Zupp:BAAALgAECggJEAAAAA==.',
Zx='Zx:BAAALgADCgYJBgAAAA==.',
['Ér']='Ér:BAAALgAECgkJBQAAAA==.',
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
