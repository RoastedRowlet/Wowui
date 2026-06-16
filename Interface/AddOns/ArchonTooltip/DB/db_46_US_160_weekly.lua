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

local lookup = {'Priest-Shadow','Priest-Discipline','Warrior-Protection','DemonHunter-Devourer','Shaman-Restoration','Druid-Restoration','Unknown-Unknown','Paladin-Retribution','Hunter-Survival','DeathKnight-Unholy','Paladin-Holy','Warrior-Arms','Druid-Balance','Priest-Holy','Rogue-Subtlety','Rogue-Assassination','Shaman-Elemental','Evoker-Devastation','Mage-Frost','Evoker-Augmentation','Evoker-Preservation','Warlock-Demonology','Warlock-Destruction','Warrior-Fury','Warlock-Affliction','Monk-Brewmaster','Druid-Feral','Druid-Guardian','Mage-Fire','Monk-Mistweaver','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Blood','Shaman-Enhancement','Paladin-Protection','Rogue-Outlaw','Monk-Windwalker','DemonHunter-Vengeance','Mage-Arcane','DemonHunter-Havoc','DeathKnight-Frost',}
local provider = {region='US',realm="Mug'thol",name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aazmon:BAACLgAFFH8SAAIBAAcJ6hjlBwDmAQABAAcJ6hjlBwDmAQAuAAQKfywAAwEACQlxI4QGACMDAAEACQlxI4QGACMDAAIAAwmYEstSALIAAAAA.',
Ab='Abinjahmin:BAABLgAECn8WAAIDAAgJwgdkJwD0AAADAAgJwgdkJwD0AAAAAA==.',
Ac='Achainoi:BAAALgADCgYJBQAAAA==.Acy:BAACLgAFFH8ZAAIEAAUJdB30MABZAQAEAAUJdB30MABZAQAuAAQKfyUAAgQACAnRH3w6ANkBAAQACAnRH3w6ANkBAAAA.',
Ad='Adjust:BAABLgAFFH8KAAIFAAQJrRvKKgAwAQAFAAQJrRvKKgAwAQABLgAFFAgJJQAGAEYZAA==.',
Ae='Aegris:BAAALgAECgcJBwAAAA==.Aegrisomnia:BAAALgAECgEJAQABLgAECgcJBwAHAAAAAA==.Aejra:BAAALgAECgYJBgABLgAECgcJBwAHAAAAAA==.Aeman:BAABLgAECn8bAAICAAcJHxVvJACoAQACAAcJHxVvJACoAQAAAA==.Aeropunk:BAAALgAECgUJCQAAAA==.Aerys:BAAALgAECgEJAQAAAA==.Aerøs:BAAALgAECgYJDgAAAA==.Aesthetic:BAAALgAECgYJCQAAAA==.',
Af='Afflicting:BAAALgAECgEJBQAAAA==.',
Ag='Aggiz:BAABLgAECn8WAAIIAAkJ4g8cXwCwAQAIAAkJ4g8cXwCwAQABLgAECgkJKAAJABgZAA==.',
Aj='Ajaxprime:BAABLgAFFH8IAAIKAAIJViTHsgC6AAAKAAIJViTHsgC6AAAAAA==.',
Ak='Akiojonës:BAAALgAECgYJCQAAAA==.',
Al='Alabamajane:BAABLgAECn8dAAIIAAcJzQ50qQAmAQAIAAcJzQ50qQAmAQAAAA==.Alathiel:BAAALgAECgEJAgABLgAECggJEwAHAAAAAA==.Alazurindron:BAAALgAECgMJBQAAAA==.Alesîa:BAAALgAECgQJBQAAAA==.Alfabika:BAAALgAECgcJBgAAAA==.Alittlesalty:BAABLgAECn8kAAILAAgJqhuwFQBjAgALAAgJqhuwFQBjAgAAAA==.Alnec:BAAALgAECgMJBQAAAA==.Alronn:BAAALgAECgMJBQAAAA==.Alustrious:BAAALgADCgUJBQABLgAFFAQJDgAMAEQcAA==.Alzim:BAACLgAFFH8VAAINAAQJQRwlGABRAQANAAQJQRwlGABRAQAuAAQKfzwAAw0ACQkkJXkCAEwDAA0ACQkkJXkCAEwDAAYAAQlgH3mpAF8AAAAA.',
Am='Amoki:BAAALgAECgEJAgAAAA==.Amrën:BAACLgAFFH8LAAIOAAMJzxfGHwC1AAAOAAMJzxfGHwC1AAAuAAQKfykAAw4ACAlpEcUmALcBAA4ACAlpEcUmALcBAAEABwm1Cys+ABYBAAAA.',
An='Angry:BAAALgAECgYJBwAAAA==.Animosityy:BAAALgADCgYJBgAAAA==.Antitheist:BAAALgADCgQJBAAAAA==.Antitoo:BAAALgAECgEJAQAAAA==.Antitoos:BAAALgADCggJDAAAAA==.Anymar:BAAALgADCgYJBgAAAA==.',
Aq='Aquemos:BAAALgAECgEJBAAAAA==.',
Ar='Aragos:BAABLgAECn8iAAMPAAgJphhsGADUAQAPAAgJphhsGADUAQAQAAMJGwGaGgBTAAAAAA==.Arazarion:BAAALgADCgIJAgAAAA==.Arcelon:BAAALgAECgIJAwAAAA==.Arcelorz:BAAALgAECgkJBwAAAA==.Arlesia:BAAALgAECgEJAQAAAA==.Arvz:BAABLgAECn8UAAMRAAYJBBweLwClAQARAAYJBBweLwClAQAFAAEJSAdlnwAxAAAAAA==.Arwenatak:BAABLgAECn8iAAMIAAgJUR5wKABfAgAIAAgJUR5wKABfAgALAAEJGhWRiQA0AAAAAA==.Arzelon:BAAALgAFFAMJAwAAAA==.',
As='Asgardian:BAAALgAECgIJBQAAAA==.Ashlari:BAABLgAECn8ZAAISAAcJpQixEAD7AAASAAcJpQixEAD7AAAAAA==.Ashter:BAAALgAECgcJDgAAAA==.Asmuun:BAAALgADCgcJBwABLgAFFAcJEgABAOoYAA==.',
At='Athren:BAABLgAECn8tAAIIAAkJriLIEgDQAgAIAAkJriLIEgDQAgAAAA==.Atøne:BAAALgADCgUJCQAAAA==.',
Av='Averyee:BAAALgADCgQJBAAAAA==.',
Aw='Awmagood:BAAALgAECgEJAQAAAA==.',
Az='Azealiabanks:BAAALgADCgkJDwAAAA==.Azmun:BAABLgAFFH8FAAIEAAQJLxMHRQASAQAEAAQJLxMHRQASAQABLgAFFAcJEgABAOoYAA==.Azzmun:BAABLgAFFH8IAAITAAQJoQ39fgDgAAATAAQJoQ39fgDgAAABLgAFFAcJEgABAOoYAA==.',
Ba='Babyløn:BAAALgAECgQJBAAAAA==.Badcity:BAAALgAECgYJBgAAAA==.Badfish:BAAALgADCgYJBgABLgAECgkJHAAFAGkWAA==.Balgart:BAAALgAECgQJBAAAAA==.Ballador:BAAALgADCgkJDQABLgAECgkJNwATACUPAA==.Barnëy:BAAALgADCgEJAQAAAA==.Barraga:BAAALgAECgIJBAABLgAECggJLQAUADQeAA==.Barragadin:BAAALgAECgQJBAABLgAECggJLQAUADQeAA==.Barrageobama:BAAALgAECgUJBAAAAA==.Barreta:BAAALgAECgcJEwAAAA==.Bashmoar:BAAALgADCggJCAABLgAECggJHgACAIoQAA==.Basle:BAAALgADCgYJBgAAAA==.',
Bd='Bde:BAAALgAECgEJAgAAAA==.',
Be='Beardsize:BAAALgAFFAEJAQABLgAFFAgJJQAGAEYZAA==.Beauregaard:BAAALgADCgUJBQAAAA==.Beck:BAABLgAECn8uAAIFAAkJaQdnVQBbAQAFAAkJaQdnVQBbAQAAAA==.Beefykin:BAAALgAECgMJAwAAAA==.Beeowin:BAAALgADCgcJDwAAAA==.Beevoker:BAABLgAECn8cAAQUAAgJqRFYPAA2AQAUAAgJ0w9YPAA2AQASAAQJqBWZKgDJAAAVAAMJ0wuvOgCVAAAAAA==.Bellamuerté:BAAALgAECgcJEgABLgAECggJHgAWAJMRAA==.Bellámuerté:BAABLgAECn8eAAMWAAgJkxHKVwCVAQAWAAgJ/RDKVwCVAQAXAAUJTAtKMQD0AAAAAA==.Bertox:BAABLgAECn8dAAIWAAkJcCEkFgCeAgAWAAkJcCEkFgCeAgAAAA==.',
Bi='Bigdrandyy:BAAALgAECgkJEgAAAA==.Biggnz:BAAALgADCgcJBAAAAA==.Biggss:BAAALgADCgEJAQAAAA==.Biggsx:BAAALgADCgYJBwAAAA==.Bijali:BAAALgADCgYJBwAAAA==.Bika:BAAALgAECgIJAgABLgAECgcJBgAHAAAAAA==.Binhad:BAAALgAECgUJDQAAAA==.Birdallas:BAABLgAECn8WAAINAAgJYRdOLgCSAQANAAgJYRdOLgCSAQAAAA==.',
Bl='Blackbird:BAAALgAFFAEJAQAAAA==.Bloodlordzz:BAAALgAECgYJDwAAAA==.Bloodlusst:BAABLgAECn8zAAIOAAgJrRYrGgD2AQAOAAgJrRYrGgD2AQAAAA==.Bloodreina:BAABLgAECn8cAAIYAAgJ2B6wDQDoAgAYAAgJ2B6wDQDoAgAAAA==.Blueburry:BAAALgADCgEJAQAAAA==.Blutkind:BAAALgAECgcJBQAAAA==.',
Bo='Bob:BAABLgAECn8nAAMWAAkJ8xxcGQCKAgAWAAgJxBxcGQCKAgAZAAMJDh6IJACXAAAAAA==.Bobatea:BAAALgAECgkJCQAAAA==.Bonelee:BAABLgAECn8fAAIaAAgJBQwiNAB/AQAaAAgJBQwiNAB/AQAAAA==.Boomtang:BAAALgAECgEJAQAAAA==.Boshuun:BAAALgAECgMJAwAAAA==.',
Br='Brahm:BAABLgAECn8UAAMbAAYJhx16EACqAQAbAAYJhx16EACqAQAcAAQJBRBcPwCjAAABLgAECgkJKAARABkdAA==.Brainrotkid:BAACLgAFFH8qAAMTAAgJvRpSFQBCAgATAAcJNR5SFQBCAgAdAAMJzQ8xAwDWAAAuAAQKf0IAAhMACQngI04QAPcCABMACQngI04QAPcCAAAA.Bravoker:BAABLgAECn8tAAMUAAgJNB5tFAA3AgAUAAgJNB5tFAA3AgAVAAIJFATQQwBQAAAAAA==.Brdua:BAAALgAECgkJCQAAAA==.Breadnbudda:BAAALgADCgcJDgAAAA==.Breeze:BAAALgAECgMJBQABLgAECggJGAAeAFUYAA==.Brewzy:BAAALgAECgEJAQABLgAECgkJIgATAHAbAA==.Briale:BAAALgAECgEJBAAAAA==.Brkdemon:BAAALgAECgYJEAAAAA==.Broju:BAAALgAECgQJBAAAAA==.Brosrus:BAAALgAECgUJCgABLgAECgkJLgATAMUaAA==.Brudda:BAAALgADCgEJAgABLgAECggJHQAOAG0bAA==.',
Bu='Budtender:BAABLgAECn8dAAMGAAgJHBHqQQCaAQAGAAgJHBHqQQCaAQAcAAEJJggrOAAXAAAAAA==.Buji:BAAALgAECgIJAgABLgAECgcJHQAIAM0OAA==.Bulkam:BAABLgAECn8aAAMLAAgJBA1tRwBaAQALAAgJBA1tRwBaAQAIAAMJ8gp/JQFUAAAAAA==.Bulldan:BAAALgADCgcJCAAAAA==.Burbuja:BAABLgAECn8sAAQUAAkJViKYBgDuAgAUAAkJOyKYBgDuAgAVAAkJaB4PBgDkAgASAAUJnxVuHABNAQAAAA==.Burr:BAAALgADCgYJBgAAAA==.',
Bz='Bzap:BAAALgADCgYJDwAAAA==.',
['Bö']='Böömer:BAAALgAECgUJBQAAAA==.',
Ca='Callabash:BAACLgAFFH8FAAIFAAQJ1goyRADRAAAFAAQJ1goyRADRAAAuAAQKfzsAAwUACQm4G3oPANICAAUACQm4G3oPANICABEABwlEDaJLAAIBAAAA.Callahan:BAABLgAECn8VAAIbAAgJHhisDQDWAQAbAAgJHhisDQDWAQAAAA==.Calzues:BAAALgAECgYJDAAAAA==.Cameltotemx:BAAALgAECgQJBwAAAA==.Canuimagine:BAAALgAECgUJDQAAAA==.Capa:BAAALgADCggJEQAAAA==.Capricornus:BAAALgAECgEJAQAAAA==.Captórofsin:BAAALgADCgIJAgAAAA==.Catchacharge:BAAALgADCgQJBAAAAA==.Cav:BAABLgAECn8lAAQfAAkJNBk6MgAPAgAgAAgJnhWpIgARAgAfAAgJWBc6MgAPAgAJAAUJMAXePADZAAAAAA==.',
Cd='Cdrom:BAAALgAECgMJAwABLgAFFAcJHwAhAE8fAA==.',
Ce='Celarena:BAABLgAECn87AAIXAAkJcQoHEQAwAQAXAAkJcQoHEQAwAQAAAA==.',
Ch='Chabil:BAABLgAECn8UAAMUAAYJ7ArnXgC5AAAUAAUJewznXgC5AAAVAAMJLxJaOgCXAAAAAA==.Charcol:BAAALgAECgcJDAAAAA==.Chasen:BAAALgADCgQJBQAAAA==.Cheefkdavi:BAAALgAECgIJAgABLgAFFAIJAwAHAAAAAA==.Cheeziit:BAABLgAECn8lAAMcAAkJ7Rw1BgCaAgAcAAkJ7Rw1BgCaAgAGAAIJGQpguwBPAAAAAA==.Chiaki:BAAALgAECgYJBgAAAA==.Chifa:BAAALgAECgUJBQABLgAFFAUJHQACAJ4iAA==.Chilla:BAAALgAECgIJBAAAAA==.Chiller:BAAALgAECgQJBQAAAA==.Chomrogg:BAACLgAFFH8PAAMKAAMJIx1WgAADAQAKAAMJIx1WgAADAQAhAAIJTRRXMwBmAAAuAAQKfxQAAyEABgnHH+krAPgAAAoABgkwG36CAH0BACEABAkZH+krAPgAAAAA.Chop:BAAALgAECgcJEgABLgAECggJEwAHAAAAAA==.Chopzzpala:BAAALgAECgcJCwAAAA==.Choubelle:BAAALgAECgkJCgAAAA==.Chunked:BAAALgAECgYJCgAAAA==.Chyp:BAABLgAECn8rAAIIAAkJThgCQAAEAgAIAAkJThgCQAAEAgAAAA==.Chzdh:BAAALgAECgcJBwABLgAFFAkJBAAHAAAAAA==.Chzlagoo:BAAALgAFFAkJBAAAAA==.Chzpld:BAABLgAECn8YAAIIAAgJjyITIgB8AgAIAAgJjyITIgB8AgABLgAFFAkJBAAHAAAAAA==.Chzpriest:BAABLgAFFH8HAAMBAAQJOhuHEQBWAQABAAQJOhuHEQBWAQACAAMJag15MgC8AAABLgAFFAkJBAAHAAAAAA==.Chzrizz:BAAALgAECggJEAABLgAFFAkJBAAHAAAAAA==.',
Ci='Cichadin:BAABLgAECn8iAAIEAAgJlg/qTADBAQAEAAgJlg/qTADBAQABLgAFFAgJPAAWAG0aAA==.Cichorì:BAACLgAFFH88AAQWAAgJbRpmAQAzAgAWAAcJmB1mAQAzAgAZAAUJeBaWAwBVAQAXAAIJEQhVDQCjAAAuAAQKfzgABBkACQkGJO0BAMMCABYACQkSHf8MABIDABkACQmxHu0BAMMCABcABwmNHVgGAGoCAAAA.Cipa:BAAALgAECgMJBAAAAA==.Circee:BAAALgAECgIJAgAAAA==.',
Cl='Clae:BAABLgAECn8XAAIKAAgJZx4KPABHAgAKAAgJZx4KPABHAgAAAA==.Clone:BAAALgADCgkJCQAAAA==.Clue:BAAALgAECgEJAgAAAA==.',
Co='Cobramaxima:BAAALgAECgEJAQAAAA==.Coddler:BAABLgAFFH8JAAIaAAMJMxuWLwDmAAAaAAMJMxuWLwDmAAABLgAFFAQJBwAGAK4fAA==.Colmer:BAABLgAECn8iAAIWAAkJXhfWNAAEAgAWAAkJXhfWNAAEAgAAAA==.Coochy:BAAALgAECgYJCgAAAA==.Coonowl:BAAALgAECgEJAgAAAA==.Cotten:BAAALgAECgIJAgAAAA==.',
Cr='Creckko:BAAALgAECgEJAgAAAA==.Crei:BAAALgADCgYJBgAAAA==.Crispriest:BAAALgAFFAEJAgAAAA==.Crockito:BAACLgAFFH9HAAIRAAkJuiUrAAB5AwARAAkJuiUrAAB5AwAuAAQKfx4AAhEACQl2JkgAAPQDABEACQl2JkgAAPQDAAAA.Cryi:BAAALgADCggJFgAAAA==.',
Cu='Cub:BAAALgADCgMJAwAAAA==.',
Cy='Cymist:BAACLgAFFH8UAAIGAAYJ/BTtFAC1AQAGAAYJ/BTtFAC1AQAuAAQKfycAAgYACQksIvUHADYDAAYACQksIvUHADYDAAAA.',
['Cî']='Cîpa:BAAALgAECgMJBAAAAA==.',
Da='Dabu:BAABLgAECn8cAAIFAAkJaRYdIQBEAgAFAAkJaRYdIQBEAgAAAA==.Dak:BAABLgAECn8nAAIEAAYJhRZqagBMAQAEAAYJhRZqagBMAQAAAA==.Dampening:BAAALgAECgUJCgAAAA==.Dantar:BAABLgAECn8rAAQRAAgJBArYRgAUAQAiAAYJJQUFGwAZAQARAAgJBArYRgAUAQAFAAYJKAOnsQBhAAAAAA==.Daroll:BAAALgADCgIJAgAAAA==.Darthidan:BAABLgAECn8lAAIIAAkJuQ+/bQCQAQAIAAkJuQ+/bQCQAQAAAA==.Darthir:BAAALgAECggJEAAAAA==.Daìsy:BAABLgAECn8eAAMGAAgJAxXgQgCDAQAGAAgJAxXgQgCDAQANAAMJ8RSAWwC1AAAAAA==.',
De='Deadphen:BAAALgADCgIJAgAAAA==.Deathscythe:BAAALgADCgEJAQAAAA==.Decesare:BAAALgAECgQJBQABLgAFFAQJBwAFACQLAA==.Delaroz:BAABLgAECn8WAAIaAAYJaBdvMQA5AQAaAAYJaBdvMQA5AQAAAA==.Delorean:BAAALgADCgcJFgAAAA==.Demonbourne:BAAALgAECgkJAgAAAA==.Demonjay:BAAALgADCgUJCAABLgAFFAMJCQAjAAMLAA==.Demonphen:BAAALgAFFAIJAgABLgAFFAMJEQAkAOEhAA==.Depoprovera:BAACLgAFFH8JAAIjAAMJAwvYDgCNAAAjAAMJAwvYDgCNAAAuAAQKf0gAAiMACQksF4oKAB8CACMACQksF4oKAB8CAAAA.Deqz:BAACLgAFFH8JAAIJAAQJJhOiFwAQAQAJAAQJJhOiFwAQAQAuAAQKfzoABAkACQkKHxQGAMACAAkACQkKHxQGAMACACAABwmdF7YsAMkBAB8ABgnZHaxzAFQBAAAA.Desmurdius:BAAALgADCgQJBAAAAA==.Destan:BAABLgAECn8mAAIcAAkJiA4AIQBBAQAcAAkJiA4AIQBBAQAAAA==.Destlock:BAAALgADCgcJCwAAAA==.Destroy:BAAALgADCgQJBAAAAA==.',
Df='Dfect:BAAALgADCgYJCAABLgAECggJGAAeAFUYAA==.',
Dh='Dhoko:BAABLgAECn8wAAIIAAgJSgsolQBHAQAIAAgJSgsolQBHAQAAAA==.Dhx:BAAALgAECgUJBQAAAA==.',
Di='Diewithonor:BAAALgAECgYJBgAAAA==.Dilox:BAABLgAECn8vAAMOAAkJYRhgEgBJAgAOAAkJYRhgEgBJAgACAAEJmRKldAA4AAAAAA==.Dirtydee:BAAALgAECgEJAQAAAA==.Dirtyshammy:BAAALgAECgcJEQAAAA==.Dirtysmonk:BAAALgAECgEJAQAAAA==.Disaaya:BAABLgAECn8xAAIfAAkJtxb4MAAUAgAfAAkJtxb4MAAUAgAAAA==.Disbizch:BAAALgAECgQJBwAAAA==.Dizzy:BAAALgAFFAEJAQABLgAFFAgJJQAGAEYZAA==.',
Dk='Dkx:BAAALgAECgEJAQAAAA==.',
Do='Dokromaa:BAACLgAFFH8PAAIKAAUJBxevWAA+AQAKAAUJBxevWAA+AQAuAAQKfyUAAgoACAn3Hf1fAKcBAAoACAn3Hf1fAKcBAAAA.Dominic:BAAALgADCgcJCAAAAA==.Doodlebug:BAACLgAFFH8jAAIhAAcJOhN2EQBoAQAhAAcJOhN2EQBoAQAuAAQKfysAAiEACAmuH+wPAAoCACEACAmuH+wPAAoCAAAA.Dooshrocket:BAAALgAECgMJBAAAAA==.Dorck:BAAALgAECgUJEgAAAA==.Dorzan:BAAALgADCgYJDAAAAA==.Dotix:BAAALgAECgEJAQABLgAECgQJBQAHAAAAAA==.Doughdappy:BAAALgAECgMJBAAAAA==.Doxxz:BAAALgAECgYJCAABLgAECgkJMQAKAEwbAA==.',
Dp='Dpaw:BAAALgAECgIJAgAAAA==.',
Dr='Dracuujin:BAAALgAECgYJCwABLgAFFAcJGQACAO0gAA==.Draeyen:BAAALgAECgEJBgAAAA==.Dragonballs:BAAALgAECgMJAwAAAA==.Dralioli:BAABLgAECn8rAAMLAAgJpgkcPABUAQALAAgJpgkcPABUAQAIAAYJwQOfDgGjAAAAAA==.Dreadloccs:BAACLgAFFH8SAAMWAAYJYBQOLwCAAQAWAAYJ8RMOLwCAAQAXAAEJIgbJGABMAAAuAAQKfxwAAxcACQn4Hv4cAGYBABcABAlhHv4cAGYBABYABQlTH5mWACsBAAAA.Dreams:BAACLgAFFH8KAAIfAAMJ6xG4WwDlAAAfAAMJ6xG4WwDlAAAuAAQKf0sAAx8ACQn1HyYQAMwCAB8ACQn1HyYQAMwCACAAAwnVBk10AG0AAAAA.Dreanil:BAABLgAECn8fAAMFAAgJSRp6HAA1AgAFAAgJSRp6HAA1AgAiAAEJiwRbLgAtAAAAAA==.Drroog:BAAALgAECgQJBQAAAA==.Druidesse:BAAALgADCgkJFQABLgAECgkJGAAcABkYAA==.Druidnosce:BAAALgAECgEJAQAAAA==.Drék:BAAALgADCgUJBQAAAA==.',
Du='Durbekbek:BAAALgADCgcJBwAAAA==.Durond:BAAALgAECgQJBgAAAA==.',
Dw='Dwarfsize:BAAALgAFFAIJAwABLgAFFAgJJQAGAEYZAA==.',
Dy='Dyksuckie:BAAALgADCgUJBQABLgAECggJHAAYANgeAA==.Dymon:BAAALgAECgEJAQAAAA==.',
Dz='Dzievana:BAABLgAECn8XAAMfAAYJ2RBzhQAuAQAfAAYJ2RBzhQAuAQAgAAQJ4AV3JwB3AAAAAA==.',
['Dâ']='Dârn:BAABLgAECn80AAMWAAkJGiH+EQC6AgAWAAgJGiH+EQC6AgAZAAEJAACOIQBsAAAAAA==.',
Ea='Earthygirthy:BAABLgAECn8sAAIDAAgJWSVbBADfAgADAAgJWSVbBADfAgAAAA==.Eaumz:BAAALgAECgUJBgAAAA==.',
Ed='Edron:BAAALgAECgEJAQABLgAECgQJBgAHAAAAAA==.Edwin:BAAALgAECgcJBwAAAA==.',
Ef='Efect:BAABLgAECn8YAAQeAAgJVRjGGgA8AgAeAAgJVRjGGgA8AgAlAAIJpxPrawB3AAAaAAEJ/g/VkQAvAAAAAA==.',
Ei='Eigenbra:BAACLgAFFH8IAAMgAAMJkxfqHQC3AAAgAAMJkxfqHQC3AAAJAAIJlRJjJwCVAAAuAAQKfxYAAyAACAklGYwTACMBACAACAnhGIwTACMBAAkABQlcCa9BALwAAAAA.',
El='Elissra:BAAALgAFFAIJAgAAAA==.Elori:BAAALgADCgIJAgABLgADCgUJBQAHAAAAAA==.Elvispræstly:BAABLgAECn8eAAICAAgJihBdIADJAQACAAgJihBdIADJAQAAAA==.',
Em='Emodeqz:BAABLgAFFH8FAAIKAAMJqwY9sgC7AAAKAAMJqwY9sgC7AAAAAA==.',
En='Endfist:BAAALgAECgkJCwAAAA==.',
Ep='Epilepsy:BAAALgAECgQJBAAAAA==.',
Er='Eroy:BAAALgADCgUJBQAAAA==.Erzza:BAACLgAFFH8JAAILAAMJ6yPGHwAZAQALAAMJ6yPGHwAZAQAuAAQKfyYAAgsACAlMJHwLANMCAAsACAlMJHwLANMCAAAA.',
Es='Esotericzeo:BAAALgADCgIJAgAAAA==.Estrellita:BAAALgADCgUJBQAAAA==.',
Et='Ethernal:BAAALgAECgUJBAAAAA==.',
Eu='Eupherine:BAABLgAECn84AAIOAAkJhyRMAwBbAwAOAAkJhyRMAwBbAwAAAA==.',
Ev='Everbear:BAAALgAECgEJAgABLgAFFAUJHQACAJ4iAA==.Evildrood:BAABLgAECn8zAAINAAkJFR9tCQC8AgANAAkJFR9tCQC8AgAAAA==.',
Ex='Excedrin:BAAALgADCgYJGwAAAA==.',
Ey='Eyegouge:BAAALgADCgYJCwAAAA==.',
Fa='Fappinwith:BAAALgAECgIJAgAAAA==.Farpoog:BAAALgADCgEJAQABLgAECgkJKAAZABAhAA==.Fatsmellycow:BAABLgAECn8kAAMGAAgJgh0lFgCUAgAGAAgJgh0lFgCUAgANAAYJWwnPUADFAAABLgAECgkJEgAHAAAAAA==.Faust:BAAALgAECgEJAQAAAA==.',
Fe='Felwags:BAAALgAECgMJAwAAAA==.Fendrag:BAABLgAECn8aAAIDAAkJYhx8DwDsAQADAAkJYhx8DwDsAQAAAA==.Festers:BAABLgAECn8eAAIPAAgJLxF+HQCmAQAPAAgJLxF+HQCmAQAAAA==.',
Fl='Flappii:BAAALgADCgkJDgAAAA==.Flappyfuros:BAABLgAECn8dAAIVAAkJNQqmHQCWAQAVAAkJNQqmHQCWAQAAAA==.Flaster:BAAALgAECgQJBAAAAA==.Fluffykat:BAABLgAECn84AAINAAkJvRmoEgA+AgANAAkJvRmoEgA+AgAAAA==.',
Fo='Foonnd:BAAALgAECgEJAQABLgAECgcJCgAHAAAAAA==.Foonnz:BAAALgAECgcJCgAAAA==.Fosho:BAACLgAFFH8hAAMRAAgJnxZ8CQAIAgARAAgJnxZ8CQAIAgAFAAEJ4g0KdwBKAAAuAAQKf0YAAxEACQm0I80DACkDABEACQm0I80DACkDAAUABwm9F64kAAMCAAAA.Fourgot:BAABLgAECn8aAAMWAAgJMhGpZgCXAQAWAAgJ7xCpZgCXAQAXAAQJ+wi2TQCFAAAAAA==.Fourwhat:BAAALgADCgQJBQAAAA==.',
Fr='Frapplehok:BAAALgADCgMJAwAAAA==.Fraud:BAAALgAECgYJBgABLgAECggJHAAYANgeAA==.Freddysjr:BAAALgADCgMJAwAAAA==.Freelvlsvnty:BAAALgAECgEJAQAAAA==.Froddy:BAAALgAECgEJAQAAAA==.Frylockk:BAAALgAECgkJEwAAAA==.',
Fu='Fuadrondis:BAAALgAECgIJAgABLgAECgcJBgAHAAAAAA==.Fugoh:BAAALgADCgUJBQAAAA==.Furmancummin:BAAALgAECgUJDgAAAA==.Furrykane:BAEBLgAECn8lAAQNAAkJ5SOlBwDZAgANAAkJ5SOlBwDZAgAcAAIJURnDIwB+AAAbAAEJVxp0MwA0AAAAAA==.Future:BAABLgAECn86AAIiAAkJTh5OBgByAgAiAAkJTh5OBgByAgAAAA==.Fuwu:BAAALgAECgQJBAAAAA==.Fuwywowya:BAAALgAECgIJBAABLgAECgkJFwAjADgcAA==.',
Fw='Fwuffy:BAAALgAECgIJBAAAAA==.',
Ga='Gabrrof:BAAALgADCgkJGAAAAA==.Ganonn:BAAALgADCgYJBgAAAA==.',
Gh='Ghadafi:BAAALgADCgQJBAABLgAFFAIJBwAWAEIbAA==.Ghostmagic:BAAALgADCgUJBQAAAA==.',
Gi='Gillerd:BAAALgADCgUJCgAAAA==.Gills:BAAALgAECgMJBAAAAA==.Giorbs:BAAALgAECgEJAQAAAA==.Girthman:BAAALgAECgUJDAAAAA==.',
Go='Gobbleburble:BAAALgAECgEJAwAAAA==.Goham:BAAALgAECgMJAwAAAA==.Goju:BAABLgAECn8cAAMIAAgJfBdRUwDNAQAIAAgJfBdRUwDNAQALAAEJwxx5iAA3AAAAAA==.Golfpro:BAAALgADCgcJAQAAAA==.Goobe:BAAALgAECgQJDwABLgAECgkJKAAJABgZAA==.Goonela:BAAALgADCgEJAQAAAA==.Goosiee:BAAALgAECgIJAwABLgAFFAQJBwAGAK4fAA==.',
Gr='Grimjaw:BAAALgAECgYJCQAAAA==.Grinkle:BAAALgADCgQJBAAAAA==.Gripncheeks:BAAALgAECgEJAQAAAA==.Griselbrand:BAAALgADCgMJAwAAAA==.Grishum:BAAALgADCgUJCQAAAA==.Grogon:BAAALgAECgkJCQAAAA==.Groldius:BAAALgADCgYJBgAAAA==.Gromlo:BAABLgAECn8tAAIGAAkJsR3WDwDSAgAGAAkJsR3WDwDSAgAAAA==.Growho:BAAALgADCgQJBAABLgAFFAgJIQARAJ8WAA==.Grulog:BAAALgAECggJEwAAAA==.',
Gu='Guatonfate:BAAALgADCgEJAQAAAA==.Guccimann:BAAALgAFFAIJBAAAAA==.Gucciî:BAAALgAECgEJAgAAAA==.Guldav:BAAALgAECgMJAwAAAA==.Gummiebear:BAAALgAECgYJCwAAAA==.Gunny:BAABLgAECn8nAAMfAAkJyxx6LQAjAgAfAAgJUBx6LQAjAgAgAAkJqReDCgDBAQAAAA==.Guuccii:BAAALgAECgcJDAAAAA==.Guuccí:BAAALgAECgUJCQAAAA==.',
['Gã']='Gã:BAACLgAFFH8FAAIEAAIJnBXscgCYAAAEAAIJnBXscgCYAAAuAAQKfysAAwQACAmBI3oSAKwCAAQACAmBI3oSAKwCACYAAQkAAPJAAAAAAAAA.',
Ha='Haeliman:BAAALgAECgEJAgAAAA==.Hagatha:BAAALgAECgkJDQABLgAECgkJKgALAHEgAA==.Haileigh:BAAALgAECgUJDAAAAA==.Haliaeetus:BAAALgAECgMJAwAAAA==.Hazedreality:BAABLgAECn8hAAITAAgJnQibnwA5AQATAAgJnQibnwA5AQAAAA==.',
He='Healems:BAABLgAECn8YAAIcAAkJGRhKCwAqAgAcAAkJGRhKCwAqAgAAAA==.Heekocat:BAAALgADCgcJBwAAAA==.Hellbòund:BAAALgAECgEJAQAAAA==.Hellenkiller:BAAALgADCgEJAQAAAA==.',
Hi='Hikawa:BAACLgAFFH8LAAMTAAQJAyREMQCmAQATAAQJAyREMQCmAQAnAAEJIx4HBQBXAAAuAAQKfzUAAxMACQkXI3sUANwCABMACQm0IHsUANwCACcABwmcIOkDABsCAAAA.Hippocratic:BAAALgAECgQJBQABLgAECgcJJwAIAMMdAA==.',
Ho='Honortheox:BAAALgADCgYJBgAAAA==.Hossdk:BAAALgAECgQJBAABLgAECgYJBgAHAAAAAA==.Hosslight:BAAALgAECgYJBgAAAA==.Hottz:BAABLgAECn8nAAMGAAgJPx7YHwBCAgAGAAgJPx7YHwBCAgAbAAEJqQOuVwAnAAAAAA==.',
Hu='Huaily:BAAALgAECgcJBwAAAA==.Hummice:BAAALgAECgQJBwAAAA==.Huntemall:BAABLgAECn8VAAIfAAkJZBGlNgD/AQAfAAkJZBGlNgD/AQAAAA==.',
Hy='Hyacia:BAAALgAECgEJAwABLgAFFAIJAgAHAAAAAA==.',
['Hà']='Hàvoc:BAACLgAFFH8OAAIEAAQJXAqTUgDwAAAEAAQJXAqTUgDwAAAuAAQKfx8AAgQACAlSGGk2AOkBAAQACAlSGGk2AOkBAAAA.',
['Hä']='Hävoc:BAABLgAECn8cAAITAAgJGBo0PgB/AgATAAgJGBo0PgB/AgABLgAFFAQJDgAEAFwKAA==.',
Ic='Icantseewell:BAAALgADCgMJAwAAAA==.Iceborn:BAAALgAECgkJAQAAAA==.Iceshards:BAABLgAECn9AAAITAAkJtA+iVQDZAQATAAkJtA+iVQDZAQAAAA==.Ichigosdad:BAAALgAECgMJAwAAAA==.',
Id='Idtrapthat:BAAALgAECgUJCAAAAA==.',
If='Ifrozê:BAAALgADCgEJAQABLgAFFAMJCQAjAAMLAA==.',
Ik='Ike:BAAALgAECgcJDwAAAA==.',
Il='Illidank:BAAALgADCgkJCQAAAA==.Illidankior:BAACLgAFFH8WAAIDAAYJUSPoBwCxAQADAAYJUSPoBwCxAQAuAAQKfyEAAwMACQlTIusEAPYCAAMACQlTIusEAPYCAAwAAwmxC3wsAJEAAAEuAAMKCQkJAAcAAAAA.Illirothas:BAABLgAECn8YAAQEAAYJUxOngQAmAQAEAAYJkA+ngQAmAQAoAAMJEhVzTAC9AAAmAAMJlQ4GIgByAAABLgAFFAIJBAAHAAAAAA==.Illisteve:BAAALgAECgYJCwABLgAFFAgJJQAGAEYZAA==.Ilovllamas:BAABLgAFFH8IAAIGAAQJ5QYFPAC6AAAGAAQJ5QYFPAC6AAAAAA==.',
Im='Imawizard:BAABLgAECn9RAAITAAkJ9BpTJQCEAgATAAkJ9BpTJQCEAgAAAA==.Immadewsh:BAAALgAECgYJAgAAAA==.Impoosh:BAABLgAECn8oAAQZAAkJECH+AQCxAgAZAAkJ/SD+AQCxAgAXAAYJuh8BCADLAQAWAAYJmRc7WwCLAQAAAA==.Imsassy:BAABLgAECn8gAAILAAgJ1gxqNAB+AQALAAgJ1gxqNAB+AQAAAA==.',
In='Infectedbøb:BAABLgAECn8kAAIoAAgJBiFQCgCAAgAoAAgJBiFQCgCAAgAAAA==.Infekt:BAAALgAECgcJBwABLgAECggJGAAeAFUYAA==.Infurnal:BAAALgAECgYJBgAAAA==.Inmortuae:BAAALgAFFAIJBAAAAA==.Innovation:BAABLgAECn8jAAIaAAYJqh8lHADBAQAaAAYJqh8lHADBAQAAAA==.',
Ip='Iprayntank:BAABLgAECn8VAAIjAAYJ/AtsIAAEAQAjAAYJ/AtsIAAEAQAAAA==.',
Ir='Ir:BAABLgAECn8YAAMUAAkJeAcZRQASAQAUAAgJdAcZRQASAQAVAAkJKQNHHQAOAQAAAA==.Irissela:BAAALgAECgMJAwAAAA==.',
Iv='Ivalice:BAABLgAECn8eAAQJAAkJ4x5vAwD0AgAJAAkJ4x5vAwD0AgAfAAEJ4hmKzAA5AAAgAAEJkANUlQAkAAAAAA==.',
Iz='Izanamii:BAACLgAFFH8GAAIEAAMJLAWabwCiAAAEAAMJLAWabwCiAAAuAAQKfxoAAgQACAk+EZRZAJUBAAQACAk+EZRZAJUBAAAA.Izüal:BAAALgAECgIJAwABLgAFFAEJAQAHAAAAAA==.',
Ja='Jaaros:BAAALgADCggJCQAAAA==.Jafbe:BAABLgAECn8VAAMLAAcJXx3LFQBbAgALAAcJXx3LFQBbAgAIAAEJWxYYdQFAAAAAAA==.Jaghatai:BAAALgAECgIJAgAAAA==.Jaxxid:BAAALgAECgYJBgAAAA==.Jaymie:BAAALgAECgcJEwABLgAECggJHQAjAMIOAA==.Jazlern:BAAALgAECgMJAwAAAA==.',
Je='Jesil:BAAALgADCgYJAwAAAA==.Jesilpriest:BAAALgAECgQJDQAAAA==.Jesse:BAABLgAECn8lAAIeAAkJLhmcEwB5AgAeAAkJLhmcEwB5AgAAAA==.',
Jh='Jherekal:BAAALgAECgMJBQAAAA==.',
Ji='Jimcarrey:BAABLgAECn8kAAITAAYJlwdS2wDdAAATAAYJlwdS2wDdAAAAAA==.Jimmyc:BAABLgAECn8hAAIfAAgJ/BM+SwC7AQAfAAgJ/BM+SwC7AQAAAA==.',
Jo='Joemauma:BAABLgAECn8oAAITAAkJ0RQbSwD3AQATAAkJ0RQbSwD3AQAAAA==.Johnnaay:BAAALgAECgIJAQAAAA==.Joslin:BAAALgADCgEJAQABLgAFFAYJFAAGAPwUAA==.',
Jp='Jpam:BAAALgAFFAEJAgAAAA==.',
Ju='Juku:BAAALgADCgEJAQAAAA==.July:BAAALgADCgIJAgABLgAECgcJFwARAO8YAA==.Jumbosize:BAACLgAFFH8lAAMGAAgJRhlfBQCvAgAGAAgJRhlfBQCvAgANAAEJrAaFHABEAAAuAAQKfzAAAgYACQl3JcEAALgDAAYACQl3JcEAALgDAAAA.Junrage:BAACLgAFFH8VAAIYAAUJGR78CgBOAQAYAAUJGR78CgBOAQAuAAQKfxQAAxgACQluGxoZAIMCABgACAn/HRoZAIMCAAwAAQl7Cd19ACkAAAAA.Jupîter:BAABLgAECn8UAAQIAAgJzAgutQAVAQAIAAcJ9gkutQAVAQAjAAIJ2AQCRwAlAAALAAIJKAJYmwAjAAAAAA==.Justmeldit:BAAALgAECgIJAgABLgAFFAgJJQAGAEYZAA==.',
Ka='Kaelis:BAAALgAECgUJBAAAAA==.Kaelish:BAAALgAECggJEQAAAA==.Kaerlif:BAABLgAECn8kAAMLAAgJ8xaVHAAdAgALAAgJ8xaVHAAdAgAIAAQJmhHlBQGtAAABLgAFFAYJFAAoADUeAA==.Kaiyley:BAAALgAECgYJEgAAAA==.Kajortak:BAAALgAECgYJCwAAAA==.Kalastrian:BAABLgAECn8hAAIEAAgJbhsLJgAxAgAEAAgJbhsLJgAxAgAAAA==.Kangna:BAAALgADCgIJAgAAAA==.Karatemage:BAAALgAECgcJCQAAAA==.Karateshock:BAABLgAECn83AAIFAAkJ4Bv3EgCxAgAFAAkJ4Bv3EgCxAgAAAA==.Karlor:BAABLgAECn8lAAMYAAkJNxUrIgDfAQAYAAkJ5BQrIgDfAQAMAAEJEAsjfQAqAAAAAA==.Karìn:BAAALgAECgMJCwAAAA==.Kasheeshb:BAAALgAECgQJBAAAAA==.Kashtark:BAAALgAECgEJAQAAAA==.Kastaway:BAAALgADCgYJDgAAAA==.Kayodawn:BAAALgAECgQJBAAAAA==.Kazuren:BAABLgAECn8sAAMUAAkJJRA4JgCtAQAUAAkJJRA4JgCtAQAVAAEJugLdRAAaAAAAAA==.',
Ke='Keahoa:BAAALgADCgcJBwAAAA==.Keano:BAABLgAECn8iAAIIAAkJhSLcCAAgAwAIAAkJhSLcCAAgAwAAAA==.Keeldemall:BAAALgAECgcJBwAAAA==.Kelia:BAAALgAECgEJAgABLgAFFAIJBAAHAAAAAA==.Kelinna:BAABLgAECn9DAAIIAAkJRRuMIwB1AgAIAAkJRRuMIwB1AgAAAA==.Kenichix:BAABLgAECn8iAAIEAAkJVR5OFgDRAgAEAAkJVR5OFgDRAgAAAA==.Kennidan:BAAALgAECgUJCQAAAA==.Kenshìn:BAAALgADCgEJAQAAAA==.Keymaster:BAAALgADCgIJAgAAAA==.',
Kf='Kfcchicken:BAAALgAECgQJBgAAAA==.',
Ki='Killzone:BAAALgAECgYJBQAAAA==.Kippsmithers:BAAALgAECgYJBwAAAA==.Kirin:BAAALgAECgYJDgAAAA==.Kiritoo:BAAALgAFFAIJAwAAAA==.Kitan:BAAALgAECgEJAgAAAA==.Kitri:BAAALgAECgQJCAAAAA==.',
Kl='Klaye:BAAALgAECgYJEwABLgAECgkJKAARABkdAA==.Klotz:BAAALgAECggJEQAAAA==.',
Ko='Kodabonk:BAABLgAECn8nAAMaAAkJDRWyGQDWAQAaAAkJ5hSyGQDWAQAlAAUJjBIpSgDVAAAAAA==.Kodanorth:BAAALgAECgUJDAABLgAECgkJJwAaAA0VAA==.Kombata:BAABLgAECn8bAAIeAAgJSxlxIAASAgAeAAgJSxlxIAASAgAAAA==.Kombatant:BAAALgAECgUJCQAAAA==.Kotara:BAAALgAECgMJBAAAAA==.',
Kr='Kraur:BAAALgAECgkJEgABLgAFFAIJBAAHAAAAAA==.',
Ku='Kumoj:BAAALgAECgQJBAAAAA==.Kunglaoo:BAAALgADCgEJAQAAAA==.Kureth:BAAALgAECgEJBQABLgAECggJEwAHAAAAAA==.',
La='Lag:BAAALgADCgYJBgAAAA==.Lam:BAAALgAECgQJBQAAAA==.Lame:BAAALgAECgIJAgABLgAFFAYJEAAFACYgAA==.Lamlam:BAAALgADCgEJAgAAAA==.Lammp:BAABLgAFFH8HAAIFAAQJchaeMwAMAQAFAAQJchaeMwAMAQABLgAECgkJFQAKAJsYAA==.Lampp:BAAALgAECgQJBQABLgAECgkJFQAKAJsYAA==.Latharis:BAAALgADCgEJAQAAAA==.Laws:BAABLgAECn8qAAIhAAkJHhLUGQCOAQAhAAkJHhLUGQCOAQAAAA==.Lazerlips:BAAALgAFFAIJAgAAAA==.',
Le='Leezerd:BAAALgADCgcJCQAAAA==.Lemmiwinks:BAAALgAECgEJAQAAAA==.Lexsapphire:BAABLgAECn8aAAITAAYJxgPQ9gC2AAATAAYJxgPQ9gC2AAAAAA==.',
Li='Liaeda:BAABLgAECn9RAAIJAAkJmREAEgAaAgAJAAkJmREAEgAaAgAAAA==.Lianshi:BAABLgAECn8rAAMeAAkJPRnUEwB4AgAeAAkJPRnUEwB4AgAlAAEJdASUtAAhAAAAAA==.Lichplease:BAACLgAFFH8TAAIKAAYJSBuiLwCfAQAKAAYJSBuiLwCfAQAuAAQKfzEAAgoACQm5H1MWAL8CAAoACQm5H1MWAL8CAAAA.Lilithandral:BAABLgAECn8bAAIDAAgJIRYHEgDnAQADAAgJIRYHEgDnAQAAAA==.Limitedtank:BAAALgAECgQJDwAAAA==.Linainverse:BAABLgAECn8kAAMTAAgJWwllsgAaAQATAAcJMAplsgAaAQAdAAEJYARXFgAgAAAAAA==.Lithdradra:BAAALgADCgEJAQAAAA==.Livermaw:BAAALgADCgIJAgAAAA==.',
Lo='Logjammin:BAAALgADCgYJBgABLgAECggJFQAmAGcWAA==.Lolo:BAAALgAFFAIJBAABLgAFFAgJIQARAJ8WAA==.Loosie:BAABLgAECn85AAIoAAkJ0CPTAwARAwAoAAkJ0CPTAwARAwAAAA==.Lovely:BAAALgAECgUJCQAAAA==.',
Lu='Lucylepricon:BAAALgAECgQJBwAAAA==.Ludo:BAABLgAECn8VAAIEAAYJ6CDcTgC6AQAEAAYJ6CDcTgC6AQAAAA==.Luduhcris:BAABLgAECn8ZAAMFAAYJ0BlePgCwAQAFAAYJ0BlePgCwAQARAAYJzhXQOwBCAQAAAA==.Luebbersit:BAAALgAECgEJAgAAAA==.Luebberslueb:BAAALgAECgEJAQAAAA==.Luebberstiny:BAAALgADCgEJAwAAAA==.Lugnuts:BAAALgAECgQJBgAAAA==.Luketich:BAACLgAFFH8MAAIjAAQJHQmKAgDbAAAjAAQJHQmKAgDbAAAuAAQKfykAAiMACAl7HoEGAIACACMACAl7HoEGAIACAAAA.Lumiltiand:BAACLgAFFH8UAAQKAAgJYRG+LgCiAQAKAAYJhRK+LgCiAQApAAEJiQqBIwBUAAAhAAEJAADQZAAAAAAuAAQKfyIABAoACAkuIWM7AEkCAAoACAkuIWM7AEkCACEAAgkBCPxQAE4AACkAAQlZD1A7AC0AAAAA.',
['Lú']='Lústì:BAAALgADCgcJCQABLgAFFAYJIAATAJMeAA==.',
Ma='Maav:BAAALgAECgUJBQAAAA==.Mac:BAAALgAECgEJAgAAAA==.Mafia:BAAALgADCgIJAgAAAA==.Mageic:BAAALgAECgkJBgAAAA==.Magistix:BAAALgAECgEJAQABLgAECgYJCwAHAAAAAA==.Maharani:BAAALgAECgIJAgAAAA==.Mahuizmaca:BAABLgAECn8qAAMLAAkJcSCeFQBdAgALAAgJwiCeFQBdAgAIAAkJrBNQWQC+AQAAAA==.Malakaa:BAAALgAECgIJAgAAAA==.Maleficante:BAAALgADCgUJBQABLgAECgkJMAATADcPAA==.Malgoros:BAABLgAECn8xAAMEAAkJiBwJGgB1AgAEAAkJiBwJGgB1AgAoAAIJQhsnYgBEAAAAAA==.Malgrendin:BAABLgAECn8iAAIfAAkJYSKiEQDAAgAfAAkJYSKiEQDAAgAAAA==.Mallock:BAAALgAECgIJAgAAAA==.Malty:BAAALgAECgEJAQABLgAECgkJLQAEAE0fAA==.Maluma:BAAALgADCgYJBgAAAA==.Malédictias:BAABLgAECn8VAAIEAAcJOwTkswC9AAAEAAcJOwTkswC9AAAAAA==.Mamii:BAABLgAECn8mAAMaAAkJriNDAwAcAwAaAAkJViNDAwAcAwAlAAYJECPcEgBdAgAAAA==.Manaag:BAAALgAECgMJBAAAAA==.Manataurus:BAAALgADCgUJBQAAAA==.Manatreat:BAAALgAECgYJBgAAAA==.Mangø:BAAALgAECgYJBgAAAA==.Manuall:BAABLgAECn8WAAIFAAkJLA7gOQDDAQAFAAkJLA7gOQDDAQAAAA==.Maralyn:BAABLgAECn83AAIjAAkJ5QxSGgBCAQAjAAkJ5QxSGgBCAQAAAA==.Marbas:BAAALgAFFAMJBAAAAA==.Marshmellow:BAACLgAFFH8hAAIWAAYJXRtWJgCjAQAWAAYJXRtWJgCjAQAuAAQKfycAAxYACAkJIOchAFkCABYACAkJIOchAFkCABcABAlaF1AnACcBAAAA.Martense:BAABLgAECn8UAAMPAAkJSg2JIACNAQAPAAgJ5gyJIACNAQAQAAUJzQhDFwC6AAAAAA==.Mawly:BAABLgAECn8cAAIWAAcJ6QRauwDSAAAWAAcJ6QRauwDSAAAAAA==.Maxidk:BAABLgAECn8/AAIKAAkJxyW7BgBAAwAKAAkJxyW7BgBAAwAAAA==.Maxidruid:BAAALgAECggJCgABLgAECgkJPwAKAMclAA==.Maxilock:BAAALgADCgYJEgABLgAECgkJPwAKAMclAA==.Maximonk:BAAALgADCgkJDQABLgAECgkJPwAKAMclAA==.Maxipriest:BAAALgADCgUJBQAAAA==.Maxisdamage:BAABLgAECn8+AAITAAkJBxmoMABUAgATAAkJBxmoMABUAgAAAA==.Mazpaladin:BAAALgAECgEJAQAAAA==.',
Mc='Mcclownerson:BAAALgADCgYJDQABLgAECgUJDQAHAAAAAA==.',
Me='Melissarian:BAABLgAECn8sAAITAAgJuQRyvQAJAQATAAgJuQRyvQAJAQAAAA==.Menari:BAAALgAECgIJAwABLgAFFAIJAgAHAAAAAA==.Mereoleona:BAACLgAFFH8HAAIWAAIJQht+jwCdAAAWAAIJQht+jwCdAAAuAAQKfxsAAhYABwk/H4s3APoBABYABwk/H4s3APoBAAAA.',
Mi='Midgemaisel:BAABLgAECn8aAAIFAAkJVgqQUABrAQAFAAkJVgqQUABrAQAAAA==.Mirado:BAABLgAECn8lAAIYAAkJJxzpGgAVAgAYAAkJJxzpGgAVAgAAAA==.Misplacer:BAABLgAECn8VAAIGAAgJqhlEKQAOAgAGAAgJqhlEKQAOAgAAAA==.Mithridates:BAABLgAECn8gAAIXAAgJ+Q1dEAA4AQAXAAgJ+Q1dEAA4AQAAAA==.',
Mk='Mkherp:BAABLgAECn8cAAIBAAgJvBkMFwAQAgABAAgJvBkMFwAQAgAAAA==.',
Mo='Mohg:BAAALgADCgUJCAAAAA==.Momentjess:BAACLgAFFH8dAAICAAUJniI3FADXAQACAAUJniI3FADXAQAuAAQKfyMAAwIACAk4IykEAB0DAAIACAk4IykEAB0DAA4ABwlcF7IiAM8BAAAA.Monkragga:BAAALgAECgkJDwABLgAECggJLQAUADQeAA==.Moolissa:BAAALgADCgEJAQAAAA==.Mooshine:BAAALgAECgcJDAAAAA==.Morrigon:BAAALgAECgYJBgAAAA==.Morrygan:BAAALgAECgEJAgAAAA==.Mortarien:BAAALgAECgQJBwAAAA==.Mortïx:BAABLgAECn85AAIgAAkJKCKnAQD5AgAgAAkJKCKnAQD5AgAAAA==.Mossberg:BAAALgADCgYJCwAAAA==.',
Mu='Munko:BAAALgADCgEJAQABLgAECgEJAgAHAAAAAA==.Muskaan:BAAALgADCgEJBAAAAA==.Mustakakrish:BAAALgAECgEJAQABLgAECgcJBgAHAAAAAA==.',
My='Myrtle:BAAALgADCgEJAQAAAA==.Mystborne:BAAALgAECgIJBgABLgAECgkJHAAFAGkWAA==.',
Na='Nanil:BAAALgADCgYJBgAAAA==.Naraela:BAAALgAECgQJBAAAAA==.',
Ne='Nevernude:BAABLgAECn8mAAILAAkJbSDhCAD6AgALAAkJbSDhCAD6AgAAAA==.Nexflamma:BAAALgAECgYJEwAAAA==.',
Ni='Niaru:BAABLgAECn8YAAIIAAYJ6RNQ2wDhAAAIAAYJ6RNQ2wDhAAAAAA==.Ninjay:BAAALgADCgUJBQAAAA==.Nirathren:BAAALgAECgEJBAABLgAECggJEwAHAAAAAA==.Niwatori:BAABLgAECn8xAAINAAkJZyMJBAAhAwANAAkJZyMJBAAhAwAAAA==.',
No='Noah:BAACLgAFFH8nAAIJAAgJMh6gAACkAgAJAAgJMh6gAACkAgAuAAQKfyAAAgkACAl3Jj4BAFkDAAkACAl3Jj4BAFkDAAAA.Nolarz:BAACLgAFFH8rAAIQAAgJuCEuAADHAgAQAAgJuCEuAADHAgAuAAQKfyIAAxAACAkTJt0AAE4DABAACAkTJt0AAE4DAA8AAQm+H/FeADgAAAAA.Nookg:BAAALgADCgkJCQAAAA==.Nookx:BAAALgAECgUJBgAAAA==.Noor:BAACLgAFFH8IAAIEAAUJoR1SBgC/AQAEAAUJoR1SBgC/AQAuAAQKfxYAAgQACAm9I5kVANUCAAQACAm9I5kVANUCAAEuAAUUCAkSAAgAcBgA.Norbon:BAAALgADCgcJCwAAAA==.Noryn:BAAALgADCgYJBgAAAA==.Nothhelm:BAAALgAECgYJDwAAAA==.',
Nu='Nugnug:BAACLgAFFH8LAAIKAAMJoiMDIgAQAQAKAAMJoiMDIgAQAQAuAAQKfxYAAgoACAn4IWscANQCAAoACAn4IWscANQCAAEuAAUUBAkKAA4A3RUA.Nukthom:BAABLgAECn8kAAIJAAkJMyBNBwCpAgAJAAkJMyBNBwCpAgAAAA==.',
Ny='Nyahbinghi:BAAALgAECggJEwABLgAECgkJGAAcABkYAA==.Nylthoran:BAAALgADCgEJAQAAAA==.Nyneaves:BAABLgAECn8gAAIBAAkJ0hgIFAAvAgABAAkJ0hgIFAAvAgAAAA==.',
Oh='Ohmenwah:BAAALgAECgQJBwAAAA==.',
Oj='Ojplosion:BAAALgAECgMJAwABLgAECgcJDAAHAAAAAA==.Ojpyroblast:BAAALgAECgcJDAAAAA==.',
Om='Omghunter:BAABLgAECn8kAAIEAAkJ3hLtPADRAQAEAAkJ3hLtPADRAQAAAA==.',
On='Ongodx:BAAALgADCgIJAgABLgAECgkJJgAaAK4jAA==.Onisprite:BAABLgAECn8aAAMYAAgJLQyXVABYAQAYAAcJAQ2XVABYAQAMAAQJoAQtXQBjAAAAAA==.',
Op='Optimish:BAAALgAECgEJAQAAAA==.',
Or='Orchaos:BAAALgAECgQJAgAAAA==.Ordhah:BAAALgAFFAEJAQAAAA==.',
Os='Osanna:BAAALgAECgYJDgAAAA==.',
Ou='Outy:BAABLgAECn8cAAMWAAYJyhk8YwCgAQAWAAYJyhk8YwCgAQAXAAEJbgNZfQAhAAAAAA==.',
Ow='Owmyleg:BAABLgAECn8UAAIEAAYJnBNSaABpAQAEAAYJnBNSaABpAQAAAA==.',
Ox='Oxijinn:BAAALgAECgYJCQAAAA==.',
Pa='Pacanuch:BAAALgADCgYJCwAAAA==.Padding:BAAALgADCgMJAwAAAA==.Pakhan:BAABLgAECn8oAAIQAAgJlQz+CwBsAQAQAAgJlQz+CwBsAQAAAA==.Paladina:BAAALgADCgEJAQAAAA==.Paladout:BAABLgAECn8tAAMIAAkJjyDiFwCxAgAIAAkJjyDiFwCxAgAjAAgJ+BgwFQB8AQAAAA==.Palkane:BAEALgADCgQJBAABLgAECgkJJQANAOUjAA==.Palkia:BAAALgAFFAEJAQAAAA==.Pallo:BAAALgAECgEJAgAAAA==.Pandajay:BAAALgAECgYJDgABLgAFFAMJCQAjAAMLAA==.Paona:BAABLgAECn9NAAINAAkJChabFQAgAgANAAkJChabFQAgAgAAAA==.Papafloppa:BAAALgAECggJDwAAAA==.Papithanos:BAAALgAECgEJAQAAAA==.',
Pe='Pengting:BAAALgAECgYJCgAAAA==.Perajuve:BAAALgADCgYJBgABLgAFFAMJBQAlAHYIAA==.Peraroll:BAACLgAFFH8FAAIlAAMJdghQKwCZAAAlAAMJdghQKwCZAAAuAAQKfyoAAiUACQmHHRAJAOcCACUACQmHHRAJAOcCAAAA.Petz:BAABLgAECn8VAAMfAAYJvRspiwAjAQAfAAYJvRspiwAjAQAgAAQJfg6TXADQAAAAAA==.',
Ph='Phaedrah:BAABLgAECn8dAAIUAAgJGwYFSwD8AAAUAAgJGwYFSwD8AAAAAA==.Phenphen:BAACLgAFFH8RAAQkAAMJ4SFpCwCoAAAPAAMJZhujJgDqAAAkAAIJZBtpCwCoAAAQAAEJ+iJTBQBlAAAuAAQKfyQABBAACAlUIt8CALcCABAACAm7Ht8CALcCAA8ABglIH/IyAHMBACQABAkeJFMOACcBAAAA.Phuryphen:BAAALgADCgQJBAABLgAFFAMJEQAkAOEhAA==.Physicyan:BAABLgAECn8WAAICAAkJmhDLGQD/AQACAAkJmhDLGQD/AQAAAA==.',
Pi='Piakchu:BAAALgADCgcJEwAAAA==.Pix:BAAALgAECgIJAwAAAA==.',
Pl='Plonterstank:BAABLgAECn8VAAImAAgJZxYACwCxAQAmAAgJZxYACwCxAQAAAA==.Plzdontdie:BAAALgAECgYJBwAAAA==.',
Po='Pohealer:BAAALgAECgEJAwAAAA==.Pokungfumask:BAAALgADCgIJBAAAAA==.Pookie:BAAALgAECgcJEwABLgAECgkJKAAZABAhAA==.Poombah:BAABLgAECn8rAAMaAAgJxAr/MgAyAQAaAAgJxAr/MgAyAQAlAAEJMwFtwQAIAAAAAA==.Poothang:BAAALgAECgcJCAABLgAECgkJKAAZABAhAA==.Popori:BAAALgADCgcJCQAAAA==.Popshampain:BAABLgAECn8pAAIRAAgJeR2vEgBWAgARAAgJeR2vEgBWAgAAAA==.',
Pr='Preest:BAAALgAECgUJBQABLgAECggJJAALAKobAA==.Proudmoo:BAABLgAECn8jAAILAAkJzR1dDQC7AgALAAkJzR1dDQC7AgAAAA==.Provoke:BAAALgAECgEJAwAAAA==.',
Ps='Psion:BAAALgAECgEJAwAAAA==.Psyrin:BAAALgAECgkJBgAAAA==.',
Pu='Pumaa:BAABLgAECn8YAAITAAYJRhcsrAAkAQATAAYJRhcsrAAkAQAAAA==.',
Qn='Qnz:BAAALgAECgEJAQABLgAECgEJBAAHAAAAAA==.',
Qu='Quelissa:BAAALgAECgkJBgAAAA==.Quickben:BAAALgADCgEJAQAAAA==.',
Ra='Raanz:BAAALgAECgUJDwABLgAECgkJNgANAEAWAA==.Raenlling:BAAALgADCgMJAwAAAA==.Ragehoof:BAABLgAECn8UAAIDAAgJOQwFJQAFAQADAAgJOQwFJQAFAQAAAA==.Raise:BAABLgAECn8aAAIbAAYJ1hUHGQBBAQAbAAYJ1hUHGQBBAQAAAA==.Rathoril:BAABLgAECn8aAAMmAAkJpRKSCwCeAQAmAAkJpRKSCwCeAQAoAAIJeQwmVwBcAAAAAA==.Ratscum:BAAALgAECgQJDAABLgAECgYJDQAHAAAAAA==.Raxik:BAAALgADCgIJAgAAAA==.Raynor:BAAALgAECgIJAgAAAA==.Rayssa:BAABLgAECn8xAAMCAAkJ2SNIAwBwAwACAAkJ2SNIAwBwAwAOAAEJKApddAAkAAAAAA==.',
Re='Redeker:BAABLgAECn8mAAIQAAkJ8RRVBQAjAgAQAAkJ8RRVBQAjAgAAAA==.Regera:BAAALgAECgEJAQAAAA==.Rekonstruct:BAAALgAECgEJAgAAAA==.Renardfurtif:BAAALgAECgYJBwAAAA==.Reninni:BAAALgAECgUJCAAAAA==.Rentahunter:BAAALgAFFAEJAQAAAA==.Revax:BAAALgAECgYJCgABLgAFFAIJBAAHAAAAAA==.Revolatiion:BAAALgADCgEJAQAAAA==.Revolationzs:BAAALgAECgEJAQAAAA==.',
Rh='Rhaanz:BAAALgADCgMJAwABLgAECgkJNgANAEAWAA==.Rhynearas:BAAALgADCgUJCAABLgAECgkJUQAJAJkRAA==.',
Ri='Ridell:BAAALgADCgcJGQAAAA==.Rimasjobas:BAAALgAECgIJAgAAAA==.Rimestar:BAAALgAECgUJBwAAAA==.Rinda:BAAALgADCgUJBQABLgAFFAMJBgALABkkAA==.Ripoodoo:BAAALgAECgYJDQABLgAECgkJKAAZABAhAA==.',
Rn='Rngeesus:BAAALgAECgYJDgAAAA==.Rngnar:BAAALgAFFAIJAwAAAA==.',
Ro='Rocklie:BAAALgADCgYJBgAAAA==.Rocklii:BAAALgAECgIJAwAAAA==.Roguewolf:BAACLgAFFH8GAAINAAMJNwZVNwCYAAANAAMJNwZVNwCYAAAuAAQKfzAAAg0ACQmZFhEWABsCAA0ACQmZFhEWABsCAAAA.Roki:BAABLgAECn8cAAIVAAkJvhIuGABLAQAVAAkJvhIuGABLAQAAAA==.Roll:BAAALgAECgcJDQAAAA==.Rolow:BAABLgAECn8vAAITAAkJfxt/LgBdAgATAAkJfxt/LgBdAgAAAA==.Ronlock:BAAALgAECgIJAgAAAA==.Rooni:BAABLgAFFH8SAAIIAAgJcBgmAgDsAQAIAAgJcBgmAgDsAQAAAA==.Roony:BAAALgAECgcJDAABLgAFFAgJEgAIAHAYAA==.Roper:BAAALgAECgEJAQAAAA==.Rossaruu:BAABLgAECn8UAAIbAAgJcCBMBgCAAgAbAAgJcCBMBgCAAgAAAA==.Rot:BAABLgAECn8eAAQKAAgJICSNFwDuAgAKAAgJFySNFwDuAgAhAAEJ7SJFPABkAAApAAEJxhlgFABNAAAAAA==.Rotaderpz:BAAALgAFFAIJAgABLgAECgYJHAAEAOgWAA==.Royle:BAAALgAFFAIJAwAAAA==.',
Ru='Rune:BAABLgAECn8sAAMKAAkJihs9JwBjAgAKAAkJihs9JwBjAgApAAEJ4woQPAAsAAAAAA==.Runnerjay:BAABLgAECn8kAAIfAAgJQgrXaABsAQAfAAgJQgrXaABsAQABLgAFFAMJCQAjAAMLAA==.Rush:BAABLgAECn8qAAITAAkJdRl7LwBZAgATAAkJdRl7LwBZAgAAAA==.Ruswarlock:BAAALgAECgUJBQAAAA==.Ruuf:BAABLgAECn8XAAIjAAkJOBzoBwBdAgAjAAkJOBzoBwBdAgAAAA==.Ruufus:BAAALgAECgEJAgABLgAECgkJFwAjADgcAA==.',
Ry='Rygik:BAAALgAECgIJBAABLgAECgkJGQAEAMUiAA==.Rysango:BAABLgAECn8ZAAIEAAkJxSLhEQDwAgAEAAkJxSLhEQDwAgAAAA==.Ryuujins:BAACLgAFFH8ZAAICAAcJ7SDkCgBkAgACAAcJ7SDkCgBkAgAuAAQKfyUAAwIACQleJJwDAC8DAAIACQleJJwDAC8DAA4AAwmmGypXANkAAAAA.',
Sa='Saburo:BAAALgAECgcJCgAAAA==.Saelria:BAAALgAECgUJCgAAAA==.Saidar:BAAALgADCgcJCAAAAA==.Sainthoovr:BAACLgAFFH8NAAICAAMJ+R0XKgD3AAACAAMJ+R0XKgD3AAAuAAQKfzcAAwIACQk6JNACAH8DAAIACQk6JNACAH8DAAEABQl1HYUlAJ0BAAAA.Saintluke:BAAALgAECgQJCAAAAA==.Saintmarked:BAAALgAECggJDgAAAA==.Sakuraa:BAABLgAECn8YAAIPAAkJTgfGKQCtAQAPAAkJTgfGKQCtAQAAAA==.Sandia:BAAALgADCgYJCwAAAA==.Saphira:BAAALgAECgcJBwAAAA==.Sausage:BAAALgADCgYJBgAAAA==.',
Sc='Scam:BAAALgADCgcJCAAAAA==.Scumrat:BAAALgAECgYJDQAAAA==.Scyon:BAACLgAFFH8OAAInAAUJKhwMAQBGAQAnAAUJKhwMAQBGAQAuAAQKfz0AAicACAkFIG0BAJACACcACAkFIG0BAJACAAAA.',
Se='Seladorei:BAABLgAECn8sAAIkAAkJUiPdAQDAAgAkAAkJUiPdAQDAAgAAAA==.Senari:BAABLgAECn8vAAIjAAkJWBKmDwDFAQAjAAkJWBKmDwDFAQAAAA==.Sencia:BAAALgAFFAIJAgAAAA==.Seygang:BAAALgADCgYJBgAAAA==.',
Sh='Shadowblazer:BAACLgAFFH8PAAIWAAUJahKNVAAZAQAWAAUJahKNVAAZAQAuAAQKfxwAAhYACAmyGxRLAOgBABYACAmyGxRLAOgBAAAA.Shadowrainz:BAABLgAECn8rAAIBAAkJiRW0GgDuAQABAAkJiRW0GgDuAQAAAA==.Shadozw:BAAALgADCgMJAwAAAA==.Shalizar:BAAALgAECgEJAQAAAA==.Shanda:BAACLgAFFH8QAAIFAAYJJiBvCwAOAgAFAAYJJiBvCwAOAgAuAAQKfyQAAgUACQlnJJYEAGoDAAUACQlnJJYEAGoDAAAA.Shankukindly:BAAALgAECgcJCQAAAA==.Shanto:BAABLgAECn8oAAMRAAkJGR3WDQCKAgARAAkJGR3WDQCKAgAiAAEJAACGKQBDAAAAAA==.Shiftinmojo:BAAALgAECgQJCAAAAA==.Shoumei:BAABLgAECn8mAAMlAAkJqB1JEABFAgAlAAkJqB1JEABFAgAaAAEJ1wKTjwAlAAAAAA==.Shuken:BAAALgAECgQJBgAAAA==.Shwip:BAACLgAFFH8JAAMGAAMJQQi1SQCPAAAGAAMJQQi1SQCPAAANAAEJ6ByHGABaAAAuAAQKfysAAw0ACQnuIa0JAPoCAA0ACAlWIa0JAPoCAAYACQnGFrIbAGYCAAAA.',
Si='Sickalock:BAAALgAECgcJCwABLgAECgkJLgATAMUaAA==.Sickamage:BAABLgAECn8uAAMTAAkJxRrvOAAyAgATAAkJtxnvOAAyAgAnAAMJZxynDwDHAAAAAA==.Sildayven:BAAALgADCgIJAwAAAA==.Silfra:BAAALgAECgcJEQAAAA==.Sillas:BAAALgAECgMJBQAAAA==.Silvinos:BAAALgAECgEJAgAAAA==.Sinsia:BAAALgAECgEJAQABLgAFFAIJAgAHAAAAAA==.',
Sk='Skaajin:BAAALgAECgEJAQAAAA==.',
Sl='Slapparazzi:BAAALgADCgYJBgAAAA==.Sleepingiant:BAAALgAECgUJBQAAAA==.Sleepingmad:BAABLgAFFH8KAAIjAAQJlA02DwCJAAAjAAQJlA02DwCJAAAAAA==.Sloothix:BAAALgAECgcJCgABLgAECgkJCQAHAAAAAA==.Slothbob:BAAALgADCgEJAQABLgAECgMJAwAHAAAAAA==.Slushië:BAAALgAECgQJBgAAAA==.',
Sm='Smilingdev:BAABLgAECn8aAAMXAAYJ0hTUFwDgAAAWAAYJygtEpAD4AAAXAAYJIxTUFwDgAAABLgAECgkJOwAOAJ0dAA==.Smittytank:BAAALgAECgEJAQAAAA==.Smokeswell:BAAALgADCgcJBwAAAA==.',
So='Soulsproxy:BAAALgAECgcJCwAAAA==.',
Sp='Spawwn:BAAALgAECgEJAQABLgAECgkJKAAJABgZAA==.Spazdeath:BAAALgAECgQJBAAAAA==.Spellberg:BAAALgAECgQJBAAAAA==.Spilby:BAAALgADCgEJAgAAAA==.Splat:BAAALgAECgYJBgAAAA==.',
Sq='Squashee:BAAALgAECgUJBQAAAA==.Squishymonk:BAAALgADCgUJBQAAAA==.Sqûïsh:BAAALgAECgEJAgAAAA==.',
Ss='Ssilb:BAAALgAECgUJBQAAAA==.',
St='Stabbz:BAABLgAECn8sAAIPAAkJlhbOEAAgAgAPAAkJlhbOEAAgAgAAAA==.Stavaros:BAAALgADCgYJFgAAAA==.Stepdad:BAAALgAECgIJBAAAAA==.Stevetsin:BAAALgAFFAIJAgAAAA==.Steviewonder:BAABLgAECn8VAAIEAAgJ6CDSGAB9AgAEAAgJ6CDSGAB9AgABLgAECgcJDAAHAAAAAA==.Stillasleep:BAAALgAECgYJEAAAAA==.Stonatroll:BAAALgAECgQJBAABLgAFFAIJBAAHAAAAAA==.Stormdemon:BAABLgAECn8yAAMMAAgJJhybDgAAAgAMAAgJuRibDgAAAgAYAAcJJRyWIQDjAQAAAA==.Stormspellz:BAABLgAECn8qAAIFAAgJEBpQGwA9AgAFAAgJEBpQGwA9AgAAAA==.Stormyspellz:BAABLgAECn8mAAIOAAkJXBslGgALAgAOAAkJXBslGgALAgAAAA==.',
Su='Subwayeater:BAACLgAFFH8KAAIVAAUJMQ3mFgAfAQAVAAUJMQ3mFgAfAQAuAAQKfyQAAxUACAmPEtkfAIABABUACAmPEtkfAIABABQABQm8FPpLAPkAAAAA.Subzro:BAACLgAFFH8GAAITAAIJuAzSogCNAAATAAIJuAzSogCNAAAuAAQKfy4AAhMACAlmGNpBABQCABMACAlmGNpBABQCAAAA.Summäurs:BAAALgADCgMJAwABLgAECggJFAAIAMwIAA==.Supay:BAABLgAECn8ZAAImAAkJ8AhnEQAyAQAmAAkJ8AhnEQAyAQAAAA==.Superhealss:BAACLgAFFH8GAAIGAAMJuwjWSQCOAAAGAAMJuwjWSQCOAAAuAAQKfxgAAwYACQmiERAuAOwBAAYACQmiERAuAOwBAA0ABAncFCRPAMwAAAAA.Suwgo:BAAALgADCgIJAgAAAA==.',
Sy='Sylosis:BAABLgAECn8fAAIKAAgJ3Q2/igBMAQAKAAgJ3Q2/igBMAQAAAA==.Syzzle:BAACLgAFFH8GAAITAAMJuBObOAC5AAATAAMJuBObOAC5AAAuAAQKfxkAAxMACAnxH5M2AJoCABMACAloH5M2AJoCAB0ABAkZHUcIAOcAAAAA.',
Ta='Takkiya:BAAALgAECgEJAQABLgAECgkJHAAVAL4SAA==.Taksham:BAAALgAECgEJAQABLgAECgkJHAAVAL4SAA==.Talicso:BAACLgAFFH8WAAITAAYJhg29QQBrAQATAAYJhg29QQBrAQAuAAQKfy0AAxMACQkfHQEjAI8CABMACQkfHQEjAI8CACcABAkXEeAOANUAAAAA.Talos:BAAALgAECgUJBQABLgAECggJHAAYANgeAA==.Talzinn:BAAALgAECggJCQABLgAECggJHAAYANgeAA==.Tam:BAAALgAECgEJAQABLgAFFAgJJwAJADIeAA==.Tankr:BAAALgAECgUJBQAAAA==.Tarkinal:BAABLgAECn8cAAIFAAkJ7RwFFgCXAgAFAAkJ7RwFFgCXAgAAAA==.',
Te='Teepin:BAAALgADCgEJAQAAAA==.Teezee:BAABLgAECn89AAIIAAkJSyKnDgDuAgAIAAkJSyKnDgDuAgAAAA==.Teitterdrud:BAAALgADCgUJBQAAAA==.Telira:BAAALgAFFAEJAQABLgAFFAIJAgAHAAAAAA==.Temetnosce:BAAALgAECgIJAwABLgAECgcJBwAHAAAAAA==.Tempura:BAABLgAECn8iAAITAAkJcBsZOAA1AgATAAkJcBsZOAA1AgAAAA==.Tenebros:BAAALgAECgEJAgAAAA==.Termakill:BAAALgAECggJCgAAAA==.Testament:BAAALgAECgEJAQAAAA==.',
Th='Thanatus:BAABLgAECn8UAAIKAAYJuBSL2gDYAAAKAAYJuBSL2gDYAAAAAA==.Thath:BAABLgAECn8gAAImAAYJ0iHQCgCuAQAmAAYJ0iHQCgCuAQAAAA==.Thaulnor:BAAALgADCgEJAgAAAA==.Thavus:BAAALgAECgQJBgAAAA==.Thelendris:BAAALgAECgIJAgAAAA==.Themartian:BAABLgAECn8ZAAMeAAYJOBUuKABzAQAeAAYJOBUuKABzAQAlAAMJOQR8ZQB3AAAAAA==.Theshinigami:BAAALgAECgQJBAAAAA==.Thevinny:BAAALgADCgcJCwAAAA==.Thruumm:BAABLgAECn8XAAIIAAgJ+QtakwBKAQAIAAgJ+QtakwBKAQAAAA==.Thunsibution:BAAALgAECgQJBgABLgADCgkJCQAHAAAAAA==.Thydriel:BAAALgADCgcJBwABLgAECggJIAAGAGMcAA==.',
Ti='Tickz:BAABLgAECn8+AAQZAAkJ4yNYAQDjAgAWAAkJ/iJ/CQAFAwAZAAcJhiNYAQDjAgAXAAIJ0xlGNQBLAAAAAA==.Tidepods:BAAALgADCgIJAgAAAA==.Tistic:BAAALgAECgEJAgAAAA==.',
To='Toat:BAAALgAECgUJDQAAAA==.Toeran:BAABLgAECn9MAAMjAAkJ0CAVAwDqAgAjAAkJ0CAVAwDqAgAIAAIJzA4HnwEsAAAAAA==.Tokémon:BAAALgAECgMJAwAAAA==.Totesup:BAAALgAECgYJDQAAAA==.Toxren:BAAALgAECgYJEwABLgAECgkJLQATAOscAA==.',
Tr='Traelin:BAAALgAFFAEJAgABLgAFFAYJFAAGAPwUAA==.Traylesong:BAAALgADCgYJCgAAAA==.Tread:BAACLgAFFH8RAAIYAAUJXB7pHQA1AQAYAAUJXB7pHQA1AQAuAAQKfzEAAhgACAk9JsQGAPECABgACAk9JsQGAPECAAAA.Trickee:BAABLgAECn8bAAITAAgJiQqTqQAoAQATAAgJiQqTqQAoAQABLgAECgkJJgAaAK4jAA==.Trôlol:BAAALgAECgEJAwABLgAECgcJDQAHAAAAAA==.',
Ts='Tskaha:BAABLgAECn8WAAIGAAcJtAqnYgAKAQAGAAcJtAqnYgAKAQAAAA==.',
Tu='Tulip:BAAALgADCgkJFgABLgAECggJIQATAJ0IAA==.',
Ty='Tyria:BAACLgAFFH8IAAIgAAMJ+hSWGgDYAAAgAAMJ+hSWGgDYAAAuAAQKf1cAAiAACQnlHyQCANgCACAACQnlHyQCANgCAAAA.Tyronius:BAAALgAECgUJDAAAAA==.',
Um='Umbraxion:BAABLgAECn8jAAMSAAgJAwzgFQCRAQASAAgJzgrgFQCRAQAUAAIJfQjshgBJAAAAAA==.',
Un='Undeadmerlin:BAAALgAECgYJBgAAAA==.Unholyfaith:BAAALgAECgcJDQAAAA==.',
Ur='Urabrask:BAAALgADCgUJBQABLgAECgYJBgAHAAAAAA==.Urizarah:BAAALgAECgYJCwAAAA==.',
Ut='Utrecht:BAAALgAECgMJAwAAAA==.',
Va='Vaniss:BAABLgAECn8VAAMQAAcJ5BrECAC4AQAQAAcJchfECAC4AQAkAAUJfRQoEAAGAQABLgAECgkJMQAEAIgcAA==.Varg:BAAALgADCgEJAQAAAA==.Varsil:BAAALgAECgQJBQAAAA==.Vashstampede:BAABLgAECn8iAAMIAAYJXiBKfABzAQAIAAYJhhpKfABzAQAjAAMJ/h3kLwCkAAAAAA==.',
Ve='Velithiria:BAABLgAECn8kAAIfAAgJJRTxJAAoAgAfAAgJJRTxJAAoAgAAAA==.Velrik:BAABLgAECn8WAAIQAAcJKRlWCgCQAQAQAAcJKRlWCgCQAQAAAA==.Venerable:BAAALgAFFAEJAQAAAA==.Vengeance:BAAALgAECgEJAwAAAA==.Vernali:BAABLgAECn8gAAIKAAgJ9xcRTwDTAQAKAAgJ9xcRTwDTAQAAAA==.Vernalia:BAAALgAECgEJAgABLgAECggJIAAKAPcXAA==.Vezdew:BAAALgAECgEJAQABLgAFFAYJEQASAEoeAA==.Vezdormi:BAAALgAECgQJBAABLgAFFAYJEQASAEoeAA==.Vezdormu:BAACLgAFFH8RAAMSAAYJSh6eAgBZAQASAAUJniKeAgBZAQAUAAEJ/AzyXwBLAAAuAAQKfyUAAxIACQnPJNkAAG4DABIACQnPJNkAAG4DABQABwlNGaYhAMsBAAAA.Vezzug:BAAALgAECgEJAQABLgAFFAYJEQASAEoeAA==.',
Vi='Vitrixz:BAAALgADCggJHgAAAA==.Vizdicator:BAABLgAECn83AAMjAAkJyhPEEAC6AQAjAAkJyhPEEAC6AQAIAAYJQA6hwQADAQAAAA==.Viztryalle:BAAALgAECgEJAQAAAA==.',
Vu='Vulcãnus:BAABLgAECn8YAAMTAAcJfQo+qQApAQATAAcJfQo+qQApAQAdAAEJdwOREQApAAABLgAECggJFAAIAMwIAA==.',
We='Werse:BAABLgAECn8tAAIOAAkJlB7IDgByAgAOAAkJlB7IDgByAgAAAA==.',
Wh='Whereyougo:BAAALgADCgYJBgAAAA==.Whodi:BAAALgAECgUJCQAAAA==.',
Wi='Willowdusk:BAAALgAECgMJBAABLgAECgYJBgAHAAAAAA==.Willowmist:BAAALgAECgYJBgAAAA==.Willtolive:BAAALgAECggJDgABLgAECgkJFQAfAGQRAA==.Wind:BAAALgAECgQJBAAAAA==.',
Wo='Wolful:BAAALgAECgEJAgABLgAECgkJKgATAHUZAA==.',
Wr='Wrathofpride:BAAALgADCgYJBgAAAA==.',
Xa='Xackta:BAAALgAECgEJAQAAAA==.Xantom:BAAALgADCgYJBgAAAA==.Xatan:BAAALgAECgEJAwAAAA==.Xaverian:BAAALgADCgcJDgAAAA==.',
Xi='Xirim:BAABLgAFFH8GAAIYAAMJFCAkKgAGAQAYAAMJFCAkKgAGAQAAAA==.',
Xj='Xjeshy:BAAALgADCggJGQAAAA==.Xjoshy:BAAALgADCgcJEwAAAA==.',
Xn='Xnatem:BAABLgAECn8wAAIDAAkJQiCoBQC3AgADAAkJQiCoBQC3AgAAAA==.',
Xo='Xoliver:BAAALgADCgcJDQAAAA==.',
Xt='Xtinaz:BAABLgAECn8VAAMXAAYJ2Q3CFwDgAAAXAAYJ2Q3CFwDgAAAWAAEJ8wFwXQEgAAAAAA==.',
Xy='Xyrim:BAAALgAECgUJBQAAAA==.',
['Xë']='Xëllos:BAAALgADCgQJBAAAAA==.',
Ya='Yashiro:BAABLgAECn8zAAILAAkJUA92KgC5AQALAAkJUA92KgC5AQAAAA==.',
Ye='Yeraleth:BAABLgAECn8gAAIGAAgJYxzYFwB4AgAGAAgJYxzYFwB4AgAAAA==.',
Yi='Yisiwang:BAAALgADCgMJAwAAAA==.',
Yo='Yorkj:BAAALgAECgcJDwAAAA==.Yougoboom:BAAALgAECgMJAwAAAA==.',
Yv='Yvonca:BAAALgADCgEJAQAAAA==.',
Za='Zalthorax:BAABLgAECn8iAAQWAAkJShl1IQBbAgAWAAkJhBh1IQBbAgAZAAIJAiLtLABlAAAXAAEJwwMYfAAkAAABLgAFFAIJBAAHAAAAAA==.Zarri:BAAALgADCgUJBQAAAA==.Zatilion:BAACLgAFFH8GAAIIAAMJWgX8fQCxAAAIAAMJWgX8fQCxAAAuAAQKfxwAAggABwm0E36BAGkBAAgABwm0E36BAGkBAAAA.Zayn:BAAALgAECgEJAQAAAA==.',
Ze='Zenju:BAAALgAFFAEJBAAAAA==.Zenki:BAAALgAECgkJEwAAAA==.Zenru:BAABLgAFFH8FAAIhAAUJvwpbJQDDAAAhAAUJvwpbJQDDAAAAAA==.Zepharion:BAAALgAECgYJCQAAAA==.Zephiday:BAACLgAFFH8JAAIBAAMJURL5IwDPAAABAAMJURL5IwDPAAAuAAQKfyAAAgEACAlAG34OAJwCAAEACAlAG34OAJwCAAAA.Zerfonk:BAABLgAECn8VAAIaAAgJ9CJCDADKAgAaAAgJ9CJCDADKAgAAAA==.',
Zh='Zhushii:BAABLgAECn82AAMNAAkJQBb6FwAKAgANAAkJsRX6FwAKAgAbAAYJlg7RGwAnAQAAAA==.',
Zi='Ziggamoo:BAAALgAECgcJDwABLgAECgkJKAAJABgZAA==.Ziggashot:BAABLgAECn8oAAIJAAkJGBmAEgAVAgAJAAkJGBmAEgAVAgAAAA==.Zinsus:BAAALgAECgIJAgABLgAFFAIJBAAHAAAAAA==.',
Zo='Zoloftt:BAAALgADCgYJFgAAAA==.Zoromaak:BAAALgAECgIJAgABLgAFFAUJDwAKAAcXAA==.',
Zu='Zumbao:BAAALgAECgIJAgAAAA==.Zurahahsha:BAABLgAECn8sAAIiAAkJogoxEgCOAQAiAAkJogoxEgCOAQAAAA==.',
Zy='Zynbane:BAAALgAECgkJCQAAAA==.',
['Zè']='Zèd:BAAALgADCgYJBAAAAA==.',
['Ðr']='Ðrow:BAACLgAFFH8PAAIgAAUJExRmFQAUAQAgAAUJExRmFQAUAQAuAAQKfyQAAiAACAmWGdwMAJABACAACAmWGdwMAJABAAAA.',
['Óx']='Óxy:BAABLgAECn8VAAIXAAgJlhJjCgCZAQAXAAgJlhJjCgCZAQAAAA==.',
['Üh']='Ühr:BAAALgAECgYJDwAAAA==.',
['ße']='ßerethor:BAAALgADCgcJCgAAAA==.',
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
