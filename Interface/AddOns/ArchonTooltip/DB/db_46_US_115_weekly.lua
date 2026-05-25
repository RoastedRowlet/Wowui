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

local lookup = {'Priest-Discipline','Unknown-Unknown','Priest-Holy','Mage-Frost','Paladin-Retribution','Paladin-Holy','Monk-Mistweaver','Priest-Shadow','Warrior-Fury','Monk-Windwalker','DeathKnight-Unholy','Druid-Restoration','Warlock-Demonology','Shaman-Restoration','DeathKnight-Frost','Mage-Arcane','Druid-Balance','Druid-Guardian','Monk-Brewmaster','Druid-Feral','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Blood','Warrior-Arms','Warrior-Protection','DemonHunter-Devourer','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Enhancement','Shaman-Elemental','DemonHunter-Havoc','DemonHunter-Vengeance','Evoker-Preservation','Mage-Fire','Paladin-Protection',}
local provider = {region='US',realm='Gundrak',name='US',type='weekly',zone=46,date='2026-05-23',data={Ad='Adelyne:BAAALgAFFAIJAgABLgAFFAUJDgABAG0SAA==.Adera:BAAALgAECgYJBwAAAA==.',
Af='Aff:BAAALgADCgYJBgAAAA==.',
Ag='Agony:BAAALgAECgQJBgAAAA==.',
Ah='Ahkanon:BAAALgADCgEJAQAAAA==.',
Ai='Aiden:BAAALgAECgEJAgABLgAECgIJAgACAAAAAA==.Aidendk:BAAALgADCgIJAgABLgAECgIJAgACAAAAAA==.Aidenp:BAAALgADCgIJAgABLgAECgIJAgACAAAAAA==.Air:BAAALgADCgcJBwABLgAFFAgJIgADADkbAA==.',
Ak='Aku:BAAALgADCgIJBAAAAA==.',
Al='Aleniastra:BAAALgAECgYJEwAAAA==.Alexyss:BAAALgAECgUJDgAAAA==.Alykard:BAABLgAECn8xAAIEAAkJwhESPwAEAgAEAAkJwhESPwAEAgAAAA==.',
Am='Amyara:BAAALgADCgEJAQAAAA==.',
An='Andronicas:BAABLgAECn8dAAMFAAkJ6A0BVACvAQAFAAkJ6A0BVACvAQAGAAEJogevnAAtAAAAAA==.Aneira:BAABLgAFFH8SAAIEAAQJfQZhbgDYAAAEAAQJfQZhbgDYAAAAAA==.',
Ap='Apexis:BAAALgADCgYJCQAAAA==.',
Ar='Ariaa:BAAALgAECgQJCAAAAA==.Arieyri:BAAALgADCgcJBwAAAA==.Artpop:BAAALgAFFAEJAQABLgAFFAYJDwAHALISAA==.',
As='Ash:BAAALgADCgcJCwAAAA==.Ashvira:BAAALgAECgEJAQAAAA==.Aspect:BAAALgADCgcJDgABLgAECgEJAQACAAAAAA==.Astarael:BAABLgAECn8iAAMIAAkJShfzGgDHAQAIAAgJGhbzGgDHAQADAAcJLQ7gWgDIAAAAAA==.',
Av='Avi:BAABLgAECn8YAAIBAAgJcxFqGgDPAQABAAgJcxFqGgDPAQABLgAECgkJcAAJAHggAA==.',
Ba='Babygurl:BAACLgAFFH8FAAIGAAMJNx9LHAAMAQAGAAMJNx9LHAAMAQAuAAQKf3YAAgYACQntJVkBAJUDAAYACQntJVkBAJUDAAAA.Baragas:BAAALgAECgYJDAAAAA==.Bareback:BAAALgAECgQJBAAAAA==.Barney:BAAALgADCgEJAQAAAA==.Battosaî:BAAALgAECgQJBAAAAA==.',
Be='Beeny:BAACLgAFFH8zAAIHAAgJ+SLjAAAgAwAHAAgJ+SLjAAAgAwAuAAQKf0EAAwcACQlpI4UIAMwCAAcACQlpI4UIAMwCAAoAAQlsEAh+ADUAAAAA.Berat:BAAALgADCgQJBAAAAA==.Berzerker:BAAALgADCgcJEwAAAA==.',
Bg='Bgc:BAAALgADCgUJBQAAAA==.',
Bi='Binari:BAAALgAECgMJAwABLgAFFAMJBQAJACoUAA==.Binlock:BAAALgAECgQJBAABLgAFFAMJBQAJACoUAA==.',
Bl='Bl:BAAALgAECgMJAwAAAA==.Bladebear:BAABLgAECn82AAIEAAkJUxUFPwAEAgAEAAkJUxUFPwAEAgAAAA==.',
Bo='Boose:BAAALgAECgYJBgAAAA==.Bootybreaker:BAAALgADCgcJBwAAAA==.',
Br='Brat:BAAALgAECgEJBAAAAA==.Brewingmist:BAAALgAECgUJBQABLgAFFAMJBQALAEUTAA==.Bréwmaster:BAAALgAECgcJCAABLgAECgkJIgAIAEoXAA==.',
Bu='Bubbelz:BAAALgAECgMJAwAAAA==.Bubbleez:BAAALgADCgUJBQAAAA==.Bubblôseven:BAAALgAECgEJAQAAAA==.Bucklord:BAABLgAECn8iAAMIAAgJjRkAFwAuAgAIAAgJjRkAFwAuAgADAAEJABkxXQA9AAAAAA==.Budin:BAAALgAECggJEgAAAA==.Bullmann:BAAALgADCgQJBAAAAA==.',
Ca='Cannibal:BAABLgAECn8nAAIMAAkJ5xqlEACsAgAMAAkJ5xqlEACsAgAAAA==.Caplock:BAABLgAECn8VAAINAAYJoRFohABRAQANAAYJoRFohABRAQAAAA==.Capri:BAAALgAECgUJDQAAAA==.',
Ce='Cellun:BAAALgAECgUJEgAAAA==.Centipede:BAAALgAECgYJCQABLgAECgYJFwAOAIAXAA==.Ceredis:BAAALgAECgUJCwAAAA==.',
Ch='Choomoo:BAAALgADCgcJCwAAAA==.',
Cl='Cleankarma:BAAALgADCgEJAwAAAA==.',
Co='Comet:BAAALgAECgEJAQAAAA==.Cool:BAAALgAFFAMJBAAAAA==.Corwiggs:BAAALgAECgYJCwAAAA==.',
Cr='Crikey:BAAALgAECgYJDAAAAA==.Crimínal:BAAALgADCgcJCwAAAA==.Cripsee:BAAALgADCgMJAwAAAA==.',
Cu='Curbie:BAAALgAECgIJAwAAAA==.',
Cy='Cyndrixx:BAAALgAECgIJAwAAAA==.',
['Cô']='Cônvict:BAAALgADCgYJBgAAAA==.',
De='Deacknight:BAABLgAECn8cAAMLAAgJwRuPLgB+AgALAAgJwRuPLgB+AgAPAAEJig2BFwAyAAABLgADCgYJBwACAAAAAA==.Deacmonk:BAAALgADCgYJBgABLgADCgYJBwACAAAAAA==.Definitely:BAACLgAFFH8OAAIEAAMJRB28VwATAQAEAAMJRB28VwATAQAuAAQKfzgAAwQACAlcJGgVAL4CAAQACAlcJGgVAL4CABAAAQkPICobAD8AAAAA.Deki:BAEALgAECgYJBgAAAA==.Dementiaous:BAAALgAECgIJAwAAAA==.Desariana:BAABLgAECn8lAAIFAAkJcxCkTQDAAQAFAAkJcxCkTQDAAQAAAA==.',
Di='Diggitie:BAAALgAECgEJAQAAAA==.Ditto:BAAALgAFFAQJBAABLgAFFAUJIgARAN4aAA==.',
Do='Domtop:BAAALgAFFAMJBAABLgAFFAYJDwAHALISAA==.Dormas:BAABLgAECn8XAAISAAYJhxG+IwDuAAASAAYJhxG+IwDuAAAAAA==.Doug:BAAALgADCgEJAQAAAA==.Doxy:BAAALgAECgQJBQAAAA==.',
Dr='Drakeon:BAAALgAECgcJEAABLgAECgkJcAAJAHggAA==.',
Ee='Eeryxx:BAAALgAECgEJAQAAAA==.',
El='Eldh:BAABLgAECn8bAAMTAAkJbg4SIwBzAQATAAkJgQsSIwBzAQAKAAEJoiEeYgBjAAAAAA==.Eleison:BAAALgADCgMJAwAAAA==.Elendrial:BAAALgAECgIJAgAAAA==.Elendril:BAAALgADCgcJFQAAAA==.Elisoly:BAACLgAFFH8FAAIGAAIJDQyjMgB1AAAGAAIJDQyjMgB1AAAuAAQKfx8AAgYABgmCHv0bAP0BAAYABgmCHv0bAP0BAAAA.',
Em='Emrald:BAAALgAECgYJEwAAAA==.',
En='Endlessly:BAACLgAFFH8PAAIUAAQJ3hSrBABIAQAUAAQJ3hSrBABIAQAuAAQKfyIAAhQACAmfIukDAOsCABQACAmfIukDAOsCAAAA.Enerchi:BAAALgADCgMJAwAAAA==.',
Er='Erivoker:BAAALgAECgYJDAABLgAECgYJEgACAAAAAA==.Errimage:BAAALgAECgYJEgAAAA==.Errishoot:BAAALgAECgUJCQABLgAECgYJEgACAAAAAA==.Ervinia:BAAALgADCgYJCgABLgAECgYJEwACAAAAAA==.',
Ev='Evelinar:BAAALgAECgMJAwAAAA==.Evoslex:BAABLgAECn85AAMVAAkJxCPRAwAdAwAVAAkJxCPRAwAdAwAWAAYJzx1vEwCsAQAAAA==.',
Ex='Exo:BAECLgAFFH8gAAIXAAYJ2RwGBwCxAQAXAAYJ2RwGBwCxAQAuAAQKfysAAhcACQkcIhoDAPgCABcACQkcIhoDAPgCAAAA.',
Fa='Facerolleh:BAACLgAFFH8wAAMYAAgJ+CGGAACyAgAYAAgJsyGGAACyAgAJAAQJZiGMBgCGAQAuAAQKf0YABAkACQmdJc4EAFwDAAkACAn2Jc4EAFwDABgACAl/InIEAKwCABkAAgmNHXM9AFQAAAAA.Fatedx:BAAALgADCgMJBgAAAA==.',
Fe='Feelgoodinc:BAAALgADCgkJFAAAAA==.',
Fi='Fidah:BAAALgADCgEJAQAAAA==.Firemagemain:BAAALgADCgUJBQABLgAFFAMJBQAJACoUAA==.',
Fl='Flanann:BAAALgAECgEJAQABLgAECgMJCQACAAAAAA==.Flop:BAAALgAECgUJCQABLgAFFAQJCQAEAC8bAA==.Flora:BAAALgAECgEJAgAAAA==.',
Fr='Frostmere:BAAALgADCggJGQAAAA==.',
Fu='Fuknazum:BAAALgAECgEJAQAAAA==.Furcht:BAABLgAECn8cAAILAAYJGhOqnAAKAQALAAYJGhOqnAAKAQAAAA==.',
Ga='Galadar:BAAALgADCgUJBQAAAA==.',
Gi='Giteff:BAABLgAFFH8PAAIaAAcJbiWdAgCcAgAaAAcJbiWdAgCcAgAAAA==.Gitèff:BAABLgAFFH8JAAIaAAUJ9hmnJwBIAQAaAAUJ9hmnJwBIAQABLgAFFAgJDwAaAG4lAA==.Giveroflife:BAAALgAECgUJBQAAAA==.',
Go='Gourdin:BAAALgAECgQJBQABLgAECgYJCAACAAAAAA==.',
Gr='Gramnpa:BAAALgADCgUJBQAAAA==.Grandpriest:BAAALgADCgEJAQABLgAECgkJNQAFAJwdAA==.Gravepriest:BAAALgAECgEJAQAAAA==.Grimtysha:BAAALgAECgYJEAAAAA==.Grimveil:BAAALgAECgYJDQAAAA==.Gromit:BAAALgAECgQJCQAAAA==.Gröuch:BAABLgAFFH8IAAITAAQJZQq7LwDJAAATAAQJZQq7LwDJAAAAAA==.',
Ha='Harafar:BAAALgAFFAMJAwAAAA==.',
He='Hellbourne:BAABLgAECn8hAAIaAAgJrRfCNADTAQAaAAgJrRfCNADTAQAAAA==.',
Hi='Himmel:BAAALgADCgcJCQAAAA==.',
Ho='Hopnhorsé:BAAALgAECgQJBAAAAA==.Hotchoq:BAABLgAFFH8HAAIEAAIJ3QsggwCbAAAEAAIJ3QsggwCbAAAAAA==.',
Hu='Huntchoq:BAABLgAFFH8NAAQbAAUJKw8jEAAwAQAbAAUJTg0jEAAwAQAcAAIJVQi6ZQCFAAAdAAEJlBH0KABGAAAAAA==.Huxley:BAAALgADCgMJAwAAAA==.',
Ik='Ikan:BAAALgAECgYJDQAAAA==.',
In='Infest:BAAALgAECgQJCAAAAA==.Inzolethys:BAAALgADCgcJBwAAAA==.',
It='Itchy:BAAALgADCgEJAgAAAA==.Itskiohte:BAABLgAECn8pAAIeAAkJVw70CwC9AQAeAAkJVw70CwC9AQAAAA==.',
Ja='Jaggernut:BAAALgADCgUJBQAAAA==.',
Ji='Jimmbo:BAAALgAECgQJBAAAAA==.',
Jo='Johnny:BAAALgAECgIJAgABLgAECgkJOQAVAMQjAA==.',
Ju='Judeau:BAAALgADCgEJAQAAAA==.',
Ka='Kaelthuzzad:BAAALgADCgEJAQAAAA==.Kaitza:BAAALgAECgYJCwAAAA==.Kalzaketh:BAABLgAECn8/AAMVAAgJBww8MABOAQAVAAgJBww8MABOAQAWAAMJ5QSIMwB5AAAAAA==.Kashari:BAAALgAECgIJBQABLgAECgkJeQAIABIcAA==.Katali:BAAALgAECgcJEQAAAA==.Kazuggar:BAACLgAFFH8YAAIOAAUJpCJNCADyAQAOAAUJpCJNCADyAQAuAAQKfzIAAw4ACAmCJW4CAFwDAA4ACAmCJW4CAFwDAB8AAwleGlJdAM4AAAAA.Kazzn:BAAALgAECgYJCAAAAA==.',
Ke='Kedar:BAAALgAECgYJEQAAAA==.Keg:BAAALgAECgIJAgAAAA==.Kelabar:BAAALgADCgQJBAAAAA==.',
Ki='Kick:BAAALgADCgQJBAABLgAFFAYJFgAEAFwVAA==.Kiffs:BAAALgAECgcJCgAAAA==.Kill:BAAALgAECgUJDAABLgAECggJBAACAAAAAA==.Killerman:BAABLgAFFH8PAAMPAAcJ4h7qAgCLAQAPAAUJtCHqAgCLAQALAAQJfhyUWgAZAQAAAA==.Kirâ:BAAALgAECggJEAABLgAECgcJEwACAAAAAA==.',
Kr='Kregnar:BAABLgAECn8mAAIYAAgJlRuBCgAZAgAYAAgJlRuBCgAZAgAAAA==.Kresh:BAAALgAECgcJCwAAAA==.',
Ku='Kucabara:BAAALgAECgEJAgAAAA==.Kuraiwiggs:BAAALgADCgYJDAAAAA==.',
Kw='Kwichang:BAABLgAECn8ZAAIEAAcJuw/CfgBdAQAEAAcJuw/CfgBdAQAAAA==.',
['Ké']='Kélpo:BAAALgADCgMJBAAAAA==.',
La='Lasagne:BAAALgADCgMJAwAAAA==.',
Li='Lickynose:BAABLgAECn8pAAIEAAkJYyGWDgDvAgAEAAkJYyGWDgDvAgAAAA==.Lips:BAAALgAECgEJAQAAAA==.',
Ls='Ls:BAABLgAECn8iAAQgAAkJaiO3BgCfAgAgAAgJ3R+3BgCfAgAaAAgJnCG9MQAzAgAhAAcJYhWkCwB1AQAAAA==.',
Ma='Madarabia:BAAALgAECgYJDQAAAA==.Magnius:BAAALgAECgMJAwAAAA==.Mamut:BAAALgAECgEJAQAAAA==.Mantisar:BAACLgAFFH8IAAIFAAMJ5RLKSADxAAAFAAMJ5RLKSADxAAAuAAQKfx4AAgUABwnmHk8vACECAAUABwnmHk8vACECAAAA.Maxsm:BAABLgAECn8XAAIfAAgJrhmSIQACAgAfAAgJrhmSIQACAgAAAA==.',
Me='Melanippe:BAABLgAECn8XAAIMAAYJDxtuPQCuAQAMAAYJDxtuPQCuAQAAAA==.Meleefox:BAAALgADCgUJBQAAAA==.Melethron:BAABLgAECn8+AAIFAAkJgRxOHAB9AgAFAAkJgRxOHAB9AgAAAA==.Melioknky:BAAALgAECgYJBgAAAA==.',
Mi='Mid:BAAALgADCgYJBgAAAA==.Mightymage:BAABLgAECn8hAAIEAAgJ4Q1WcAB9AQAEAAgJ4Q1WcAB9AQAAAA==.Millionbaby:BAAALgAECgEJAQAAAA==.Milliondruid:BAAALgAECgMJBAAAAA==.Millionsm:BAAALgADCgQJBQAAAA==.Mirrorimage:BAAALgAECgMJBQABLgAFFAYJEgAIAAgVAA==.Mirrorx:BAACLgAFFH8SAAIIAAYJCBWsCACVAQAIAAYJCBWsCACVAQAuAAQKfzIAAggACQlzIJUGAMsCAAgACQlzIJUGAMsCAAAA.Miy:BAAALgAECgEJAQAAAA==.',
Mo='Mongon:BAAALgAECgYJBgAAAA==.Moogle:BAAALgAECgIJBAAAAA==.Moomie:BAABLgAECn8iAAIMAAgJAxZkMQC3AQAMAAgJAxZkMQC3AQAAAA==.Moosfel:BAABLgAECn8jAAIUAAcJGhq2CwDKAQAUAAcJGhq2CwDKAQAAAA==.',
Mt='Mtzz:BAAALgAECgUJBQABLgAECgYJCAACAAAAAA==.',
Mu='Mudcake:BAAALgAECgEJAQAAAA==.',
My='Mygravebroke:BAAALgADCggJCQAAAA==.Mystdragon:BAACLgAFFH8QAAMiAAUJxRuUDACZAQAiAAUJxRuUDACZAQAVAAEJnQi9UAA/AAAuAAQKfzAAAiIACQm5Ib0CABYDACIACQm5Ib0CABYDAAEuAAUUCAkkAAcArxoA.Mystweaverr:BAACLgAFFH8kAAMHAAgJrxp+AwCEAgAHAAgJrxp+AwCEAgAKAAEJ9QSgMwA7AAAuAAQKfy8AAwcACQn3H4AJALkCAAcACQn3H4AJALkCAAoAAgkjIghHALkAAAAA.',
['Mö']='Mörae:BAAALgADCgEJAQABLgAECgYJFwAMAA8bAA==.',
Na='Naddar:BAACLgAFFH8PAAIGAAUJRha9EgBhAQAGAAUJRha9EgBhAQAuAAQKfzwAAgYACQneHc4GAP4CAAYACQneHc4GAP4CAAAA.Namadgi:BAABLgAECn8hAAIMAAkJVRrpEQCeAgAMAAkJVRrpEQCeAgAAAA==.Nathria:BAAALgAECgIJAwAAAA==.',
Ne='Nesra:BAAALgAECgIJAgAAAA==.Netalis:BAABLgAECn8lAAIMAAgJwxQgKwDcAQAMAAgJwxQgKwDcAQAAAA==.',
Ni='Nikonii:BAAALgADCgQJBAAAAA==.',
Nu='Nurckers:BAAALgAECgcJCAAAAA==.',
Oa='Oakinelf:BAAALgADCgcJAQAAAA==.',
Om='Omnishifts:BAAALgAECgEJAgAAAA==.',
Or='Oramo:BAABLgAECn8fAAMXAAgJfCMmBQDwAgAXAAgJxSImBQDwAgALAAYJgCKYWwCQAQAAAA==.',
Ov='Ovaries:BAAALgADCgUJBQABLgAECgQJBQACAAAAAA==.',
Pa='Paktam:BAABLgAECn8XAAIOAAcJzh3CFwBfAgAOAAcJzh3CFwBfAgAAAA==.Paméla:BAAALgAECgcJCAABLgAECgkJcAAJAHggAA==.Paradisya:BAAALgADCggJDgAAAA==.',
Pe='Perceptor:BAAALgAECgEJAQABLgAECgkJKQASAJMhAA==.Pets:BAAALgAECgEJAQABLgAECgEJBAACAAAAAA==.',
Pl='Placebo:BAAALgAECgUJBQABLgAFFAQJDwAUAN4UAA==.',
Pr='Prothero:BAACLgAFFH8QAAMEAAUJJiC9KwB0AQAEAAUJJiC9KwB0AQAQAAEJZRktAwBSAAAuAAQKfxYAAwQACQnGIGQTAMsCAAQACQnGIGQTAMsCABAACAkrGAMDAFACAAAA.Proyo:BAAALgADCgUJBQAAAA==.',
['På']='Påthor:BAACLgAFFH8HAAIRAAIJkw8/LgCOAAARAAIJkw8/LgCOAAAuAAQKfx8AAxEABwk4HGwcALcBABEABwk4HGwcALcBABIAAwkSEtQ/AF4AAAAA.',
Ra='Raikonnen:BAAALgAECgEJAQAAAA==.Rapidstrikes:BAAALgAECgEJAQAAAA==.Rawtoor:BAACLgAFFH8cAAIaAAYJbRlUGgCHAQAaAAYJbRlUGgCHAQAuAAQKfyEAAhoACAk4IdInAGUCABoACAk4IdInAGUCAAAA.',
Re='Rebelsister:BAAALgADCgcJEAAAAA==.Refridgerate:BAAALgADCgUJBwAAAA==.',
Ri='Riddagain:BAABLgAECn8bAAMhAAYJeA/1FAAHAQAhAAYJTw/1FAAHAQAaAAIJwAsO9AArAAAAAA==.Ridgemonk:BAABLgAECn8zAAMTAAkJiiAfBADvAgATAAkJiiAfBADvAgAHAAQJQAGYYABMAAAAAA==.Riggsdk:BAAALgADCgcJBwABLgAFFAgJGwAcAKAiAA==.Riggse:BAAALgAFFAEJAQABLgAFFAgJGwAcAKAiAA==.Riggshunt:BAACLgAFFH8bAAQcAAgJoCLTAACrAQAbAAYJLCQuAAD7AQAcAAYJ8SDTAACrAQAdAAEJAAC/KABKAAAuAAQKfx4ABBwACAmrJr0IAAcDABwABwmYJr0IAAcDABsACAmTJIQDAPICAB0AAQmCHGd9AE8AAAAA.Riggspal:BAAALgAFFAIJAgABLgAFFAgJGwAcAKAiAA==.Riggzs:BAAALgAFFAIJAgABLgAFFAgJGwAcAKAiAA==.',
Ro='Roadkill:BAABLgAECn8gAAIXAAgJnSM4BAALAwAXAAgJnSM4BAALAwAAAA==.Rolltoor:BAAALgAFFAIJAwAAAA==.Roonate:BAAALgADCgUJBQAAAA==.Rosemary:BAAALgAECgQJBAAAAA==.',
Ry='Ryujin:BAAALgAECgQJCQAAAA==.',
Sa='Saiko:BAABLgAFFH8RAAIgAAUJ1hgACABKAQAgAAUJ1hgACABKAQAAAA==.Sansa:BAACLgAFFH8TAAIbAAcJZhgFAgDaAQAbAAcJZhgFAgDaAQAuAAQKfyMAAhsACQlnI00CACMDABsACQlnI00CACMDAAAA.Saso:BAACLgAFFH8QAAIEAAUJFhsHGwBfAQAEAAUJFhsHGwBfAQAuAAQKfzMABAQACQmUIhUQAOMCAAQACQmUIhUQAOMCABAAAwkDH0gMAA0BACMAAgnECLALAHcAAAAA.Sastroll:BAAALgAECgUJBQAAAA==.',
Sc='Scorn:BAAALgADCgcJCAAAAA==.Scroll:BAAALgAECggJEgAAAA==.',
Se='Seluvis:BAABLgAECn8UAAIEAAcJlAHa8gCUAAAEAAcJlAHa8gCUAAAAAA==.Sentai:BAAALgADCgcJBwAAAA==.Serapayne:BAAALgAECgcJAQAAAA==.',
Sh='Shadow:BAACLgAFFH8WAAIaAAUJ9hlyJABVAQAaAAUJ9hlyJABVAQAuAAQKf1wAAhoACQkQJOAJAOQCABoACQkQJOAJAOQCAAAA.Shandrilah:BAAALgADCgQJBAAAAA==.Shapeshift:BAAALgADCgUJBQABLgAECgIJAgACAAAAAA==.Shialebuff:BAABLgAECn81AAQDAAkJfR+fFwAfAgADAAkJfR+fFwAfAgAIAAcJEh2qFwDmAQABAAEJkwZ6ZgAuAAAAAA==.Shijin:BAAALgAECgQJBQAAAA==.Shortfuze:BAAALgAECgYJDQAAAA==.',
Si='Sindar:BAAALgADCgUJBQAAAA==.Sinfall:BAAALgAECggJDgAAAA==.Siphon:BAAALgAECgEJAgAAAA==.Siscomp:BAABLgAECn9wAAIJAAkJeCD4CwCGAgAJAAkJeCD4CwCGAgAAAA==.Sixth:BAABLgAECn8XAAIfAAcJ/BpsHwC7AQAfAAcJ/BpsHwC7AQAAAA==.Sizzle:BAAALgADCgMJAwAAAA==.',
Sk='Skateboard:BAAALgADCgEJAQAAAA==.Sky:BAACLgAFFH8eAAIBAAcJdhkbBQB9AgABAAcJdhkbBQB9AgAuAAQKfxQAAwEACAlxE48cALABAAEABwlZEo8cALABAAMABQnyD4hMAAYBAAAA.',
Sl='Sleck:BAAALgAECgYJDAAAAA==.',
Sn='Snappa:BAAALgADCgYJCwAAAA==.Sniped:BAAALgAFFAEJAQAAAA==.Snugglepuff:BAAALgAECgkJEwAAAA==.',
So='Soapfidas:BAAALgADCggJCgAAAA==.Sonarius:BAACLgAFFH8JAAIEAAQJLxu4NQBYAQAEAAQJLxu4NQBYAQAuAAQKfx0ABAQACAndHyk8AIYCAAQACAndHyk8AIYCABAAAgkCHZMKAKoAACMAAQmyEg8PADwAAAAA.Sophie:BAAALgAECgEJAgAAAA==.',
Sp='Splitterman:BAABLgAFFH8GAAIPAAUJtxK7BwA1AQAPAAUJtxK7BwA1AQAAAA==.',
Su='Su:BAABLgAECn8yAAIHAAcJ4yVlBwDiAgAHAAcJ4yVlBwDiAgAAAA==.Sudno:BAAALgAECgQJCAABLgAFFAYJFQANABYaAA==.Sundae:BAABLgAECn83AAQDAAkJlSFIBgDvAgADAAgJHCNIBgDvAgABAAgJhxssCwCRAgAIAAMJ3BZ1RwDEAAAAAA==.Sunwukong:BAAALgAECgUJCQAAAA==.Supersinpe:BAAALgAECgIJAgAAAA==.',
Sv='Svendlefyre:BAAALgADCgcJDgABLgAECgkJLgAUAIMZAA==.Svholydrag:BAAALgADCgEJAQAAAA==.Svmishima:BAAALgAECgEJAQAAAA==.',
Sw='Swirly:BAAALgAECgEJAQAAAA==.',
Sy='Sylvie:BAABLgAECn8eAAIcAAkJmhGfLwD0AQAcAAkJmhGfLwD0AQAAAA==.',
['Sý']='Sýlvanas:BAAALgAECgQJDwAAAA==.',
Te='Tealç:BAABLgAECn8gAAIZAAcJpheVGACQAQAZAAcJpheVGACQAQABLgAFFAQJFAAZACQZAA==.Tekk:BAAALgAECgEJAQAAAA==.Tekkys:BAAALgAECgEJAgAAAA==.Tertle:BAAALgADCgUJBQAAAA==.',
Ti='Tiafinia:BAAALgAECgEJAgAAAA==.Tiggerstripe:BAAALgADCgEJAQABLgAECggJLgAeAIMRAA==.Timmyy:BAAALgAECgYJBgABLgAECgkJFwALAHEcAA==.Timur:BAAALgAECgMJBAAAAA==.Tinara:BAAALgADCgUJBQAAAA==.',
Tr='Trigger:BAAALgAECgIJAgAAAA==.',
Tu='Turlesblows:BAABLgAECn8fAAMJAAgJ4B9gJAA0AgAJAAgJ4B9gJAA0AgAZAAEJOxWZRAA7AAAAAA==.',
Tw='Twityy:BAAALgADCgEJAgAAAA==.Twofiveyd:BAABLgAFFH8FAAIVAAQJjA8jJQAIAQAVAAQJjA8jJQAIAQABLgAFFAYJFAAYAGcYAA==.',
Ty='Tyladrhas:BAABLgAECn80AAIhAAkJVB+pAgCnAgAhAAkJVB+pAgCnAgAAAA==.Tyrismaximus:BAAALgAECgMJAwAAAA==.',
Ul='Ulkina:BAAALgADCgYJCQAAAA==.',
Va='Vaelith:BAAALgAECgIJAgAAAA==.Valerine:BAABLgAECn8aAAIEAAkJ/wrlagCJAQAEAAkJ/wrlagCJAQAAAA==.Vanoran:BAAALgAECgMJBAAAAA==.Varang:BAAALgAECgIJAgAAAA==.Varina:BAAALgAECgcJEwAAAA==.',
Ve='Velsaert:BAAALgADCgcJBwAAAA==.Venki:BAAALgAECgYJBwAAAA==.',
Vi='Vitani:BAAALgADCgEJAQABLgAFFAQJDwAUAN4UAA==.',
Vo='Voidnova:BAABLgAFFH8HAAIEAAMJlRCIagDhAAAEAAMJlRCIagDhAAAAAA==.Voidphayze:BAAALgAECgUJDAABLgAFFAMJBQALAEUTAA==.',
Vu='Vulken:BAABLgAECn9nAAIcAAkJESU+CQDtAgAcAAkJESU+CQDtAgAAAA==.',
['Vê']='Vê:BAAALgAECgkJEQAAAA==.',
Wa='Wallace:BAAALgAECgcJDAAAAA==.Walterlight:BAAALgAECgYJDgAAAA==.Watto:BAABLgAECn8VAAMOAAkJOR+KEQCXAgAOAAkJOR+KEQCXAgAfAAEJMBfufQBEAAAAAA==.',
We='Wemongin:BAAALgADCgUJBQAAAA==.',
Wh='Whimsical:BAABLgAECn8XAAIOAAYJgBd+QgBxAQAOAAYJgBd+QgBxAQAAAA==.',
Wi='Winnìng:BAABLgAECn8gAAIkAAgJJAzvHQD2AAAkAAgJJAzvHQD2AAAAAA==.',
Wu='Wugong:BAAALgADCgEJAQAAAA==.',
['Wó']='Wórkwórk:BAACLgAFFH8FAAIJAAMJKhROFwCsAAAJAAMJKhROFwCsAAAuAAQKfxsAAwkACQk6Gxg3AMsBAAkABwnRGRg3AMsBABgAAwnsGr8fAO8AAAAA.',
Zi='Zich:BAAALgADCgMJAwAAAA==.Zihon:BAABLgAECn8UAAILAAQJTxokyQDFAAALAAQJTxokyQDFAAAAAA==.',
Zo='Zodiiak:BAABLgAECn9EAAIeAAkJMR3tBABxAgAeAAkJMR3tBABxAgAAAA==.',
Zu='Zubb:BAAALgADCgYJCQABLgAECggJEAACAAAAAA==.Zuhh:BAAALgAECgEJAQABLgAECggJEAACAAAAAA==.Zupp:BAAALgAECggJEAAAAA==.',
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
