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

local lookup = {'Priest-Shadow','Priest-Discipline','Warrior-Protection','DemonHunter-Devourer','Shaman-Restoration','Druid-Restoration','Unknown-Unknown','Paladin-Retribution','Hunter-Survival','DeathKnight-Unholy','Paladin-Holy','Warrior-Arms','Druid-Balance','Priest-Holy','Rogue-Subtlety','Rogue-Assassination','Shaman-Elemental','Paladin-Protection','Evoker-Devastation','Mage-Frost','Evoker-Augmentation','Hunter-BeastMastery','Evoker-Preservation','Warlock-Demonology','Warlock-Destruction','Warrior-Fury','Warlock-Affliction','Monk-Brewmaster','Druid-Feral','Druid-Guardian','Mage-Fire','Monk-Mistweaver','Hunter-Marksmanship','DeathKnight-Blood','Shaman-Enhancement','Rogue-Outlaw','Monk-Windwalker','DemonHunter-Vengeance','Mage-Arcane','DemonHunter-Havoc','DeathKnight-Frost',}
local provider = {region='US',realm="Mug'thol",name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aazmon:BAACLgAFFH8SAAIBAAcJ6hh6CADjAQABAAcJ6hh6CADjAQAuAAQKfywAAwEACQlxI4QGACMDAAEACQlxI4QGACMDAAIAAwmYEtlTALEAAAAA.',
Ab='Abinjahmin:BAABLgAECn8WAAIDAAgJwgfzJwD0AAADAAgJwgfzJwD0AAAAAA==.',
Ac='Achainoi:BAAALgADCgYJBQAAAA==.Acy:BAACLgAFFH8dAAIEAAUJdB3iBgDpAAAEAAUJdB3iBgDpAAAuAAQKfyUAAgQACAnRH0s7ANoBAAQACAnRH0s7ANoBAAAA.',
Ad='Adjust:BAABLgAFFH8KAAIFAAQJrRvJLAAvAQAFAAQJrRvJLAAvAQABLgAFFAgJJQAGAEYZAA==.',
Ae='Aegris:BAAALgAECgcJBwAAAA==.Aegrisomnia:BAAALgAECgEJAQABLgAECgcJBwAHAAAAAA==.Aejra:BAAALgAECgYJBgABLgAECgcJBwAHAAAAAA==.Aeman:BAABLgAECn8gAAICAAcJHxVOJQClAQACAAcJHxVOJQClAQAAAA==.Aeropunk:BAAALgAECgUJCQAAAA==.Aerys:BAAALgAECgQJBQAAAA==.Aerøs:BAAALgAECgYJDgAAAA==.Aesthetic:BAAALgAECgYJCQAAAA==.',
Af='Afflicting:BAAALgAECgEJBQAAAA==.',
Ag='Aggiz:BAABLgAECn8WAAIIAAkJ4g8zYQCuAQAIAAkJ4g8zYQCuAQABLgAECgkJKAAJABgZAA==.',
Aj='Ajaxprime:BAABLgAFFH8IAAIKAAIJViQKuAC4AAAKAAIJViQKuAC4AAAAAA==.',
Ak='Akiojonës:BAAALgAECgYJCQAAAA==.',
Al='Alabamajane:BAABLgAECn8dAAIIAAcJzQ5LrQAjAQAIAAcJzQ5LrQAjAQAAAA==.Alathiel:BAAALgAECgEJAgABLgAECggJEwAHAAAAAA==.Alazurindron:BAAALgAECgMJBQAAAA==.Alesîa:BAAALgAECgQJBQAAAA==.Alfabika:BAAALgAECgcJBgAAAA==.Alittlesalty:BAABLgAECn8kAAILAAgJqhuwFQBjAgALAAgJqhuwFQBjAgAAAA==.Alnec:BAAALgAECgMJBQAAAA==.Alronn:BAAALgAECgMJBQAAAA==.Alustrious:BAAALgADCgUJBQABLgAFFAQJDgAMAEQcAA==.Alzim:BAACLgAFFH8WAAINAAQJQRxpGQBPAQANAAQJQRxpGQBPAQAuAAQKfzwAAw0ACQkkJZECAEsDAA0ACQkkJZECAEsDAAYAAQlgHxarAF8AAAAA.',
Am='Amoki:BAAALgAECgEJAgAAAA==.Amrën:BAACLgAFFH8LAAIOAAMJzxezIAC0AAAOAAMJzxezIAC0AAAuAAQKfykAAw4ACAlpEcUmALcBAA4ACAlpEcUmALcBAAEABwm1C7s/ABEBAAAA.',
An='Angry:BAAALgAECgcJCQAAAA==.Animosityy:BAAALgADCgYJBgAAAA==.Antitheist:BAAALgADCgQJBAAAAA==.Antitoo:BAAALgAECgEJAQAAAA==.Antitoos:BAAALgADCggJDAAAAA==.Anymar:BAAALgADCgYJBgAAAA==.',
Aq='Aquemos:BAAALgAECgEJBAAAAA==.',
Ar='Aragos:BAABLgAECn8iAAMPAAgJphjXGADUAQAPAAgJphjXGADUAQAQAAMJGwGaGgBTAAAAAA==.Arazarion:BAAALgADCgIJAgAAAA==.Arcelon:BAAALgAECgIJAwAAAA==.Arcelorz:BAAALgAECgkJBwAAAA==.Arlesia:BAAALgAECgEJAQAAAA==.Arvz:BAABLgAECn8UAAMRAAYJBBweLwClAQARAAYJBBweLwClAQAFAAEJSAdlnwAxAAAAAA==.Arwenatak:BAABLgAECn8kAAQIAAgJUR47KQBdAgAIAAgJUR47KQBdAgASAAIJfRUuAgB5AAALAAEJGhU8iwA0AAAAAA==.Arzelon:BAAALgAFFAMJAwAAAA==.',
As='Asgardian:BAAALgAECgIJBQAAAA==.Ashlari:BAABLgAECn8ZAAITAAcJpQj4EAD7AAATAAcJpQj4EAD7AAAAAA==.Ashter:BAAALgAECgcJDgAAAA==.Asmun:BAAALgAECgEJAQABLgAFFAcJEgABAOoYAA==.Asmuun:BAAALgADCgcJBwABLgAFFAcJEgABAOoYAA==.',
At='Athren:BAABLgAECn8tAAIIAAkJriJmEwDOAgAIAAkJriJmEwDOAgAAAA==.Atøne:BAAALgADCgUJCQAAAA==.',
Av='Averyee:BAAALgADCgQJBAAAAA==.',
Aw='Awmagood:BAAALgAECgEJAQAAAA==.',
Az='Azealiabanks:BAAALgADCgkJDwAAAA==.Azmun:BAABLgAFFH8GAAIEAAUJLxOZRwARAQAEAAUJLxOZRwARAQABLgAFFAcJEgABAOoYAA==.Azzmun:BAABLgAFFH8IAAIUAAQJoQ2AfwDYAAAUAAQJoQ2AfwDYAAABLgAFFAcJEgABAOoYAA==.',
Ba='Babyløn:BAAALgAECgQJBAAAAA==.Badcity:BAAALgAECgYJBgAAAA==.Badfish:BAAALgADCgYJBgABLgAECgkJHAAFAGkWAA==.Balgart:BAAALgAECgQJBAAAAA==.Ballador:BAAALgADCgkJDQABLgAECgkJNwAUACUPAA==.Barnëy:BAAALgADCgEJAQAAAA==.Barraga:BAAALgAECgIJBAABLgAECggJLQAVADQeAA==.Barragadin:BAAALgAECgQJCAABLgAECggJLQAVADQeAA==.Barrageobama:BAAALgAECgUJBAAAAA==.Barreta:BAABLgAECn8UAAIWAAcJ5wUxoQD/AAAWAAcJ5wUxoQD/AAAAAA==.Bashmoar:BAAALgADCggJCAABLgAECggJHwACAIoQAA==.Basle:BAAALgADCgYJBgAAAA==.',
Bd='Bde:BAAALgAECgEJAgAAAA==.',
Be='Beardsize:BAAALgAFFAEJAQABLgAFFAgJJQAGAEYZAA==.Beauregaard:BAAALgADCgUJBQAAAA==.Beck:BAABLgAECn8uAAIFAAkJaQfMVgBbAQAFAAkJaQfMVgBbAQAAAA==.Beefykin:BAAALgAECgMJAwAAAA==.Beeowin:BAAALgADCgcJDwAAAA==.Beevoker:BAABLgAECn8cAAQVAAgJqRGxPQAzAQAVAAgJ0w+xPQAzAQATAAQJqBWZKgDJAAAXAAMJ0wuvOgCVAAAAAA==.Bellamuerté:BAAALgAECgcJEgABLgAECggJHgAYAJMRAA==.Bellámuerté:BAABLgAECn8eAAMYAAgJkxGSWACTAQAYAAgJ/RCSWACTAQAZAAUJTAtKMQD0AAAAAA==.Bertox:BAABLgAECn8dAAIYAAkJcCGrFgCcAgAYAAkJcCGrFgCcAgAAAA==.',
Bi='Bigdrandyy:BAAALgAECgkJEgAAAA==.Biggnz:BAAALgADCgcJBAAAAA==.Biggss:BAAALgADCgEJAQAAAA==.Biggsx:BAAALgADCgYJBwAAAA==.Bijali:BAAALgADCgYJBwAAAA==.Bika:BAAALgAECgIJAgABLgAECgcJBgAHAAAAAA==.Binhad:BAAALgAECgUJDQAAAA==.Birdallas:BAABLgAECn8WAAINAAgJYRdOLgCSAQANAAgJYRdOLgCSAQAAAA==.',
Bl='Blackbird:BAAALgAFFAEJAQAAAA==.Bloodlordzz:BAAALgAECgYJEAAAAA==.Bloodlusst:BAABLgAECn8zAAIOAAgJrRaRGgD1AQAOAAgJrRaRGgD1AQAAAA==.Bloodreina:BAABLgAECn8cAAIaAAgJ2B6wDQDoAgAaAAgJ2B6wDQDoAgAAAA==.Blueburry:BAAALgADCgEJAQAAAA==.Blutkind:BAAALgAECgcJBQAAAA==.',
Bo='Bob:BAABLgAECn8nAAMYAAkJ8xznGQCIAgAYAAgJxBznGQCIAgAbAAMJDh50JQCXAAAAAA==.Bobatea:BAAALgAECgkJCQAAAA==.Bonelee:BAABLgAECn8fAAIcAAgJBQwiNAB/AQAcAAgJBQwiNAB/AQAAAA==.Boomtang:BAAALgAECgEJAQAAAA==.Boshuun:BAAALgAECgMJAwAAAA==.',
Br='Brahm:BAABLgAECn8UAAMdAAYJhx3iEACqAQAdAAYJhx3iEACqAQAeAAQJBRAKQQCjAAABLgAECgkJKgARABkdAA==.Brainrotkid:BAACLgAFFH8vAAMUAAgJvRpnFwA5AgAUAAcJNR5nFwA5AgAfAAQJcw5xAADYAAAuAAQKf0IAAhQACQngI8sQAPYCABQACQngI8sQAPYCAAAA.Bravoker:BAABLgAECn8tAAMVAAgJNB6mFAA3AgAVAAgJNB6mFAA3AgAXAAIJFATQQwBQAAAAAA==.Brdua:BAAALgAECgkJCQAAAA==.Breadnbudda:BAAALgAECgMJAwAAAA==.Breeze:BAAALgAECgMJBQABLgAECggJGAAgAFUYAA==.Brewzy:BAAALgAECgEJAQABLgAECgkJIgAUAHAbAA==.Briale:BAAALgAECgEJBAAAAA==.Brkdemon:BAAALgAFFAIJAgAAAA==.Broju:BAAALgAECgQJBAAAAA==.Brosrus:BAAALgAECgUJCgABLgAECgkJLgAUAMUaAA==.Brudda:BAAALgADCgEJAgABLgAECggJHQAOAG0bAA==.',
Bu='Budtender:BAABLgAECn8dAAMGAAgJHBHqQQCaAQAGAAgJHBHqQQCaAQAeAAEJJggrOAAXAAAAAA==.Buji:BAAALgAECgIJAgABLgAECgcJHQAIAM0OAA==.Bulkam:BAABLgAECn8aAAMLAAgJBA1tRwBaAQALAAgJBA1tRwBaAQAIAAMJ8gp/JQFUAAAAAA==.Bulldan:BAAALgADCgcJCAAAAA==.Burbuja:BAABLgAECn8sAAQVAAkJViK7BgDtAgAVAAkJOyK7BgDtAgAXAAkJaB4PBgDkAgATAAUJnxVuHABNAQAAAA==.Burr:BAAALgADCgYJBgAAAA==.',
Bz='Bzap:BAAALgADCgYJDwAAAA==.',
['Bö']='Böömer:BAAALgAECgUJBQAAAA==.',
Ca='Callabash:BAACLgAFFH8FAAIFAAQJ1gpTRgDRAAAFAAQJ1gpTRgDRAAAuAAQKfzsAAwUACQm4G+gPANICAAUACQm4G+gPANICABEABwlEDR5NAAEBAAAA.Callahan:BAABLgAECn8VAAIdAAgJHhjwDQDWAQAdAAgJHhjwDQDWAQAAAA==.Calzues:BAAALgAECgYJDAAAAA==.Cameltotemx:BAAALgAECgQJBwAAAA==.Canuimagine:BAAALgAECgUJDQAAAA==.Capa:BAAALgAFFAEJAQAAAA==.Capricornus:BAAALgAECgEJAQAAAA==.Captórofsin:BAAALgADCgIJAgAAAA==.Catchacharge:BAAALgADCgQJBAAAAA==.Cav:BAABLgAECn8lAAQWAAkJNBmGMwAOAgAhAAgJnhWpIgARAgAWAAgJWBeGMwAOAgAJAAUJMAWkPQDVAAAAAA==.',
Cd='Cdrom:BAAALgAECgMJAwABLgAFFAgJIAAiAJodAA==.',
Ce='Celarena:BAABLgAECn87AAIZAAkJcQp1EQAvAQAZAAkJcQp1EQAvAQAAAA==.',
Ch='Chabil:BAABLgAECn8UAAMVAAYJ7ApkYAC5AAAVAAUJewxkYAC5AAAXAAMJLxJaOgCXAAAAAA==.Charcol:BAAALgAECgcJDAAAAA==.Chasen:BAAALgADCgQJBQAAAA==.Cheefkdavi:BAEALgAECgMJAwABLgAFFAIJAwAHAAAAAA==.Cheeziit:BAABLgAECn8lAAMeAAkJ7RxhBgCaAgAeAAkJ7RxhBgCaAgAGAAIJGQpguwBPAAAAAA==.Chiaki:BAAALgAECgYJBgAAAA==.Chifa:BAAALgAECgUJBQABLgAFFAYJHgACAGghAA==.Chilla:BAAALgAECgIJBAAAAA==.Chiller:BAAALgAECgQJBQAAAA==.Chomrogg:BAACLgAFFH8PAAMKAAMJIx03hQD+AAAKAAMJIx03hQD+AAAiAAIJTRRgNQBhAAAuAAQKfxQAAyIABgnHH5EsAPcAAAoABgkwG36CAH0BACIABAkZH5EsAPcAAAAA.Chop:BAAALgAECgcJEgABLgAECggJEwAHAAAAAA==.Chopzzpala:BAAALgAECgcJCwAAAA==.Choubelle:BAAALgAECgkJCgAAAA==.Chunked:BAAALgAECgYJCgAAAA==.Chyp:BAABLgAECn8rAAIIAAkJThgEQQADAgAIAAkJThgEQQADAgAAAA==.Chzdh:BAAALgAECgcJBwABLgAFFAkJBAAHAAAAAA==.Chzlagoo:BAAALgAFFAkJBAAAAA==.Chzpld:BAABLgAECn8YAAIIAAgJjyLbIgB6AgAIAAgJjyLbIgB6AgABLgAFFAkJBAAHAAAAAA==.Chzpriest:BAABLgAFFH8HAAMBAAQJGRtlEgBVAQABAAQJGRtlEgBVAQACAAMJag07NAC7AAABLgAFFAkJBAAHAAAAAA==.Chzrizz:BAAALgAECggJEAABLgAFFAkJBAAHAAAAAA==.',
Ci='Cichadin:BAABLgAECn8iAAIEAAgJlg/qTADBAQAEAAgJlg/qTADBAQABLgAFFAgJQgAYAGkaAA==.Cichorì:BAACLgAFFH9CAAQYAAgJaRpmAQAzAgAYAAcJlB1mAQAzAgAbAAUJeBbdAwBSAQAZAAIJEQhVDQCjAAAuAAQKfzgABBsACQkGJAMCAMICABgACQkSHf8MABIDABsACQmxHgMCAMICABkABwmNHVgGAGoCAAAA.Cipa:BAAALgAECgMJBAAAAA==.Circee:BAAALgAECgIJAgAAAA==.',
Cl='Clae:BAABLgAECn8XAAIKAAgJZx4KPABHAgAKAAgJZx4KPABHAgAAAA==.Clone:BAAALgADCgkJCQAAAA==.Clue:BAAALgAECgEJAwAAAA==.',
Co='Cobramaxima:BAAALgAECgEJAQAAAA==.Coddler:BAABLgAFFH8JAAIcAAMJMxu3MADlAAAcAAMJMxu3MADlAAABLgAFFAQJCAAGAFghAA==.Colmer:BAABLgAECn8iAAIYAAkJXhcnNgABAgAYAAkJXhcnNgABAgAAAA==.Coochy:BAAALgAECgYJCgAAAA==.Coonowl:BAAALgAECgEJAgAAAA==.Cotten:BAAALgAECgIJAgAAAA==.',
Cr='Creckko:BAAALgAECgEJAgAAAA==.Crei:BAAALgADCgYJBgAAAA==.Crispriest:BAAALgAFFAEJAgAAAA==.Crockito:BAACLgAFFH9QAAIRAAkJvSUHAABbAwARAAkJvSUHAABbAwAuAAQKfx4AAhEACQl2JkgAAPQDABEACQl2JkgAAPQDAAAA.Cryi:BAAALgADCggJFgAAAA==.',
Cu='Cub:BAAALgADCgMJAwAAAA==.',
Cy='Cymist:BAACLgAFFH8UAAIGAAYJ/BQNFgCzAQAGAAYJ/BQNFgCzAQAuAAQKfycAAgYACQksIiYIADUDAAYACQksIiYIADUDAAAA.',
['Cî']='Cîpa:BAAALgAECgMJBAAAAA==.',
Da='Dabu:BAABLgAECn8cAAIFAAkJaRbEIQBEAgAFAAkJaRbEIQBEAgAAAA==.Dak:BAABLgAECn8nAAIEAAYJhRbJawBNAQAEAAYJhRbJawBNAQAAAA==.Dampening:BAAALgAECgUJCgAAAA==.Dantar:BAABLgAECn8rAAQRAAgJBApqSAASAQAjAAYJJQUFGwAZAQARAAgJBApqSAASAQAFAAYJKAPrtABhAAAAAA==.Daroll:BAAALgADCgIJAgAAAA==.Darthidan:BAABLgAECn8lAAIIAAkJuQ9ocACNAQAIAAkJuQ9ocACNAQAAAA==.Darthir:BAAALgAECggJEAAAAA==.Daìsy:BAABLgAECn8eAAMGAAgJAxW8QwCCAQAGAAgJAxW8QwCCAQANAAMJ8RSAWwC1AAAAAA==.',
De='Deadphen:BAAALgADCgIJAgAAAA==.Deathscythe:BAAALgADCgEJAQAAAA==.Decesare:BAAALgAECgQJBQABLgAFFAQJBwAFACQLAA==.Delaroz:BAABLgAECn8WAAIcAAYJaBfwMQA5AQAcAAYJaBfwMQA5AQAAAA==.Delorean:BAAALgADCgcJFgAAAA==.Demonbourne:BAAALgAECgkJAgAAAA==.Demonjay:BAAALgADCgUJCAABLgAFFAMJCwASAMALAA==.Demonphen:BAAALgAFFAIJAgABLgAFFAMJEQAkAOEhAA==.Depoprovera:BAACLgAFFH8LAAISAAMJwAv5DgCRAAASAAMJwAv5DgCRAAAuAAQKf0gAAhIACQksF7oKAB4CABIACQksF7oKAB4CAAAA.Deqz:BAACLgAFFH8JAAIJAAQJJhMzGAAQAQAJAAQJJhMzGAAQAQAuAAQKfzoABAkACQkKH2UGALsCAAkACQkKH2UGALsCACEABwmdF7YsAMkBABYABgnZHS92AFMBAAAA.Desmurdius:BAAALgADCgQJBAAAAA==.Destan:BAABLgAECn8mAAIeAAkJiA7EIQBBAQAeAAkJiA7EIQBBAQAAAA==.Destlock:BAAALgADCgcJCwAAAA==.Destroy:BAAALgADCgQJBAAAAA==.',
Df='Dfect:BAAALgADCgYJCAABLgAECggJGAAgAFUYAA==.',
Dh='Dhoko:BAABLgAECn8wAAIIAAgJSgt6mABEAQAIAAgJSgt6mABEAQAAAA==.Dhx:BAAALgAECgUJBQAAAA==.',
Di='Diewithonor:BAAALgAECgYJBgAAAA==.Dilox:BAABLgAECn8vAAMOAAkJYRiuEgBIAgAOAAkJYRiuEgBIAgACAAEJmRIkdwA4AAAAAA==.Dirtydee:BAAALgAECgQJBwAAAA==.Dirtyshammy:BAAALgAECgcJEQAAAA==.Dirtysmonk:BAAALgAECgEJAQAAAA==.Disaaya:BAABLgAECn8xAAIWAAkJtxYjMgAUAgAWAAkJtxYjMgAUAgAAAA==.Disbizch:BAAALgAECgQJBwAAAA==.Dizzy:BAAALgAFFAEJAgABLgAFFAgJJQAGAEYZAA==.',
Dk='Dkx:BAAALgAECgEJAQAAAA==.',
Do='Dokromaa:BAACLgAFFH8PAAIKAAUJBxctXQA5AQAKAAUJBxctXQA5AQAuAAQKfyUAAgoACAn3HYJhAKYBAAoACAn3HYJhAKYBAAAA.Dominic:BAAALgADCgcJCAAAAA==.Doodlebug:BAACLgAFFH8kAAIiAAgJfRJzEgBkAQAiAAgJfRJzEgBkAQAuAAQKfysAAiIACAmuH0AQAAgCACIACAmuH0AQAAgCAAAA.Dooshrocket:BAAALgAECgMJBAAAAA==.Dorck:BAAALgAECgUJEgAAAA==.Dorzan:BAAALgADCgYJDAAAAA==.Dotix:BAAALgAECgEJAgABLgAECgQJBgAHAAAAAA==.Doughdappy:BAAALgAECgMJBAAAAA==.Doxxz:BAAALgAECgYJCAABLgAECgkJMQAKAEwbAA==.',
Dp='Dpaw:BAAALgAECgIJAgAAAA==.',
Dr='Dracuujin:BAAALgAECgYJCwABLgAFFAcJGQACAO0gAA==.Draeyen:BAAALgAECgEJBgAAAA==.Dragonballs:BAAALgAECgMJAwAAAA==.Dralioli:BAABLgAECn8tAAMLAAkJagklPQBRAQALAAgJpgklPQBRAQAIAAcJQgQRFAGhAAAAAA==.Dreadloccs:BAACLgAFFH8TAAMYAAcJ3hGuMQB/AQAYAAYJ8ROuMQB/AQAZAAIJuwXjAgBOAAAuAAQKfxwAAxkACQn4Hv4cAGYBABkABAlhHv4cAGYBABgABQlTH5mWACsBAAAA.Dreams:BAACLgAFFH8NAAIWAAMJehPqBQD+AAAWAAMJehPqBQD+AAAuAAQKf0sAAxYACQn1H9UQAMoCABYACQn1H9UQAMoCACEAAwnVBk10AG0AAAAA.Dreanil:BAABLgAECn8fAAMFAAgJSRp6HAA1AgAFAAgJSRp6HAA1AgAjAAEJiwRbLgAtAAAAAA==.Drroog:BAAALgAECgQJBgAAAA==.Druidesse:BAAALgADCgkJFQABLgAECgkJGAAeABkYAA==.Druidnosce:BAAALgAECgEJAQAAAA==.Drék:BAAALgADCgUJBQAAAA==.',
Du='Durbekbek:BAAALgADCgcJBwAAAA==.Durond:BAAALgAECgQJBgAAAA==.',
Dw='Dwarfsize:BAAALgAFFAIJAwABLgAFFAgJJQAGAEYZAA==.',
Dy='Dyksuckie:BAAALgADCgUJBQABLgAECggJHAAaANgeAA==.Dymon:BAAALgAECgEJAQAAAA==.',
Dz='Dzievana:BAABLgAECn8XAAMWAAYJ2RAtiAAuAQAWAAYJ2RAtiAAuAQAhAAQJ4AUYKAB3AAAAAA==.',
['Dâ']='Dârn:BAABLgAECn80AAMYAAkJGiF0EgC5AgAYAAgJGiF0EgC5AgAbAAEJAACOIQBsAAAAAA==.',
Ea='Earthygirthy:BAABLgAECn8uAAIDAAkJ5CNyBADeAgADAAkJ5CNyBADeAgAAAA==.Eaumz:BAAALgAECgUJBgAAAA==.',
Ed='Edron:BAAALgAECgEJAQABLgAECgQJBgAHAAAAAA==.Edwin:BAAALgAECgcJBwAAAA==.',
Ef='Efect:BAABLgAECn8YAAQgAAgJVRhwGwA8AgAgAAgJVRhwGwA8AgAlAAIJpxODbQB3AAAcAAEJ/g9jkwAvAAAAAA==.',
Ei='Eigenbra:BAACLgAFFH8IAAMhAAMJkxcRHwCzAAAhAAMJkxcRHwCzAAAJAAIJlRJBKACVAAAuAAQKfxYAAyEACAklGeETACMBACEACAnhGOETACMBAAkABQlcCRFCALwAAAAA.',
El='Elissra:BAAALgAFFAIJAgAAAA==.Elori:BAAALgADCgIJAgABLgADCgUJBQAHAAAAAA==.Elvispræstly:BAABLgAECn8fAAICAAgJihBoIQDDAQACAAgJihBoIQDDAQAAAA==.',
Em='Emodeqz:BAABLgAFFH8FAAIKAAMJqwYxuAC4AAAKAAMJqwYxuAC4AAAAAA==.',
En='Endfist:BAAALgAECgkJCwAAAA==.',
Ep='Epilepsy:BAAALgAECgQJBAAAAA==.',
Er='Eroy:BAAALgADCgUJBQAAAA==.Erzza:BAACLgAFFH8JAAILAAMJ6yPAIAAYAQALAAMJ6yPAIAAYAQAuAAQKfyYAAgsACAlMJLELANICAAsACAlMJLELANICAAAA.',
Es='Esotericzeo:BAAALgADCgIJAgAAAA==.Estrellita:BAAALgADCgUJBQAAAA==.',
Et='Ethernal:BAAALgAECgUJBAAAAA==.',
Eu='Eupherine:BAABLgAECn84AAIOAAkJhyRhAwBaAwAOAAkJhyRhAwBaAwAAAA==.',
Ev='Everbear:BAAALgAECgEJAgABLgAFFAYJHgACAGghAA==.Evildrood:BAABLgAECn8zAAINAAkJFR/GCQC4AgANAAkJFR/GCQC4AgAAAA==.',
Ex='Excedrin:BAAALgADCgYJHAAAAA==.',
Ey='Eyegouge:BAAALgADCgYJCwAAAA==.',
Fa='Fappinwith:BAAALgAECgIJAgAAAA==.Farpoog:BAAALgADCgEJAQABLgAECgkJKAAbABAhAA==.Fatsmellycow:BAABLgAECn8kAAMGAAgJgh2AFgCUAgAGAAgJgh2AFgCUAgANAAYJWwkWUgDGAAABLgAECgkJEgAHAAAAAA==.Faust:BAAALgAECgEJAQAAAA==.',
Fe='Felwags:BAAALgAECgMJAwAAAA==.Fendrag:BAABLgAECn8aAAIDAAkJYhzFDwDrAQADAAkJYhzFDwDrAQAAAA==.Festers:BAABLgAECn8fAAIPAAgJhRF3HQCqAQAPAAgJhRF3HQCqAQAAAA==.',
Fl='Flappii:BAAALgADCgkJDgAAAA==.Flappyfuros:BAABLgAECn8dAAIXAAkJNQqmHQCWAQAXAAkJNQqmHQCWAQAAAA==.Flaster:BAAALgAECgQJBAAAAA==.Fluffykat:BAABLgAECn84AAINAAkJvRnrEgA+AgANAAkJvRnrEgA+AgAAAA==.',
Fo='Foonnd:BAAALgAECgEJAQABLgAECgcJCgAHAAAAAA==.Foonnz:BAAALgAECgcJCgAAAA==.Fosho:BAACLgAFFH8hAAMRAAgJnxZqCgAGAgARAAgJnxZqCgAGAgAFAAEJ4g2KegBKAAAuAAQKf0YAAxEACQm0I/MDACgDABEACQm0I/MDACgDAAUABwm9F64kAAMCAAAA.Fourgot:BAABLgAECn8aAAMYAAgJMhGpZgCXAQAYAAgJ7xCpZgCXAQAZAAQJ+wi2TQCFAAAAAA==.Fourwhat:BAAALgADCgQJBQAAAA==.',
Fr='Frank:BAAALgAECgUJBQABLgAECgkJLwAlAJoiAA==.Frapplehok:BAAALgADCgMJAwAAAA==.Fraud:BAAALgAECgYJBgABLgAECggJHAAaANgeAA==.Freddysjr:BAAALgADCgMJAwAAAA==.Freelvlsvnty:BAAALgAECgEJAQAAAA==.Froddy:BAAALgAECgIJAgAAAA==.Frylockk:BAAALgAECgkJEwAAAA==.',
Fu='Fuadrondis:BAAALgAECgIJAgABLgAECgcJBgAHAAAAAA==.Fugoh:BAAALgADCgUJBQAAAA==.Furmancummin:BAAALgAECgUJDgAAAA==.Furrykane:BAEBLgAECn8lAAQNAAkJ5SPVBwDZAgANAAkJ5SPVBwDZAgAeAAIJURnDIwB+AAAdAAEJVxp0MwA0AAAAAA==.Future:BAABLgAECn86AAIjAAkJTh6FBgBxAgAjAAkJTh6FBgBxAgAAAA==.Fuwu:BAAALgAECgQJBAAAAA==.Fuwywowya:BAAALgAECgIJBAABLgAECgkJFwASADgcAA==.',
Fw='Fwuffy:BAAALgAECgIJBAAAAA==.',
Ga='Gabrrof:BAAALgADCgkJGAAAAA==.Ganonn:BAAALgADCgYJBgAAAA==.',
Gh='Ghadafi:BAAALgADCgQJBAABLgAFFAIJBwAYAEIbAA==.Ghostmagic:BAAALgADCgUJBQAAAA==.',
Gi='Gillerd:BAAALgADCgUJCgAAAA==.Gills:BAAALgAECgMJBAAAAA==.Giorbs:BAAALgAECgEJAQAAAA==.Girthman:BAAALgAECgUJDAAAAA==.',
Go='Gobbleburble:BAAALgAECgEJAwAAAA==.Goham:BAAALgAECgMJAwAAAA==.Goju:BAABLgAECn8cAAMIAAgJfBfOVADLAQAIAAgJfBfOVADLAQALAAEJwxwQigA3AAAAAA==.Golfpro:BAAALgADCgcJAQAAAA==.Goobe:BAAALgAECgQJDwABLgAECgkJKAAJABgZAA==.Goonela:BAAALgADCgEJAQAAAA==.Goosiee:BAAALgAECgIJBAABLgAFFAQJCAAGAFghAA==.',
Gr='Grimjaw:BAAALgAECgYJCQAAAA==.Grinkle:BAAALgADCgQJBAAAAA==.Gripncheeks:BAAALgAECgEJAQAAAA==.Griselbrand:BAAALgADCgMJAwAAAA==.Grishum:BAAALgADCgUJCQAAAA==.Grogon:BAAALgAECgkJDgAAAA==.Groldius:BAAALgADCgYJBgAAAA==.Gromlo:BAABLgAECn8tAAIGAAkJsR0MEADSAgAGAAkJsR0MEADSAgAAAA==.Growho:BAAALgADCgQJBAABLgAFFAgJIQARAJ8WAA==.Grulog:BAAALgAECggJEwAAAA==.',
Gu='Guatonfate:BAAALgADCgEJAQAAAA==.Guccimann:BAAALgAFFAIJBAAAAA==.Gucciî:BAAALgAECgEJAgAAAA==.Guldav:BAAALgAECgMJAwAAAA==.Gummiebear:BAAALgAECgYJCwAAAA==.Gunny:BAABLgAECn8nAAMWAAkJyxy0LgAiAgAWAAgJUBy0LgAiAgAhAAkJqRe2CgDBAQAAAA==.Guuccii:BAAALgAECgcJDAAAAA==.Guuccí:BAAALgAECgUJCQAAAA==.',
['Gã']='Gã:BAACLgAFFH8FAAIEAAIJnBUrdgCYAAAEAAIJnBUrdgCYAAAuAAQKfysAAwQACAmBI98SAKwCAAQACAmBI98SAKwCACYAAQkAAFJCAAAAAAAA.',
Ha='Haeliman:BAAALgAECgEJAgAAAA==.Hagatha:BAAALgAECgkJDQABLgAECgkJKgALAHEgAA==.Haileigh:BAAALgAECgUJDAAAAA==.Haliaeetus:BAAALgAECgMJAwAAAA==.Hazedreality:BAABLgAECn8hAAIUAAgJnQivoQA4AQAUAAgJnQivoQA4AQAAAA==.',
He='Healems:BAABLgAECn8YAAIeAAkJGRiACwAqAgAeAAkJGRiACwAqAgAAAA==.Heekocat:BAAALgADCgcJBwAAAA==.Hellbòund:BAAALgAECgEJAQAAAA==.Hellenkiller:BAAALgADCgEJAQAAAA==.',
Hi='Hikawa:BAACLgAFFH8LAAMUAAQJAySSMgCgAQAUAAQJAySSMgCgAQAnAAEJIx5iBQBXAAAuAAQKfzUAAxQACQkXIwsVANsCABQACQm0IAsVANsCACcABwmcIOkDABsCAAAA.Hippocratic:BAAALgAECgQJBQABLgAECgcJJwAIAMMdAA==.',
Ho='Honortheox:BAAALgADCgYJBgAAAA==.Hossdk:BAAALgAECgQJBAABLgAECgYJBgAHAAAAAA==.Hosslight:BAAALgAECgYJBgAAAA==.Hottz:BAABLgAECn8nAAMGAAgJPx7YHwBCAgAGAAgJPx7YHwBCAgAdAAEJqQNwWgAnAAAAAA==.',
Hu='Huaily:BAAALgAECgcJBwAAAA==.Hummice:BAAALgAECgUJCgAAAA==.Huntemall:BAABLgAECn8VAAIWAAkJZBHiNwD+AQAWAAkJZBHiNwD+AQAAAA==.Hunteraqui:BAAALgADCgQJBAAAAA==.',
Hy='Hyacia:BAAALgAECgEJAwABLgAFFAIJAwAHAAAAAA==.',
['Hà']='Hàvoc:BAACLgAFFH8RAAIEAAQJrArgCADAAAAEAAQJrArgCADAAAAuAAQKfx8AAgQACAlSGBA3AOoBAAQACAlSGBA3AOoBAAAA.',
['Hä']='Hävoc:BAABLgAECn8cAAIUAAgJGBo0PgB/AgAUAAgJGBo0PgB/AgABLgAFFAQJEQAEAKwKAA==.',
Ic='Icantseewell:BAAALgADCgMJAwAAAA==.Iceborn:BAAALgAECgkJAQAAAA==.Iceshards:BAABLgAECn9AAAIUAAkJtA8UVwDYAQAUAAkJtA8UVwDYAQAAAA==.Ichigosdad:BAAALgAECgMJAwAAAA==.',
Id='Idtrapthat:BAAALgAECgUJCAAAAA==.',
If='Ifrozê:BAAALgADCgEJAQABLgAFFAMJCwASAMALAA==.',
Ik='Ike:BAAALgAECgcJDwAAAA==.',
Il='Illidank:BAAALgADCgkJCQAAAA==.Illidankior:BAACLgAFFH8XAAIDAAcJFiKICACtAQADAAcJFiKICACtAQAuAAQKfyEAAwMACQlTIusEAPYCAAMACQlTIusEAPYCAAwAAwmxC3wsAJEAAAEuAAMKCQkJAAcAAAAA.Illirothas:BAABLgAECn8YAAQEAAYJUxOngQAmAQAEAAYJkA+ngQAmAQAoAAMJEhVzTAC9AAAmAAMJlQ4GIgByAAABLgAECgkJIwAYALAZAA==.Illisteve:BAAALgAECgYJCwABLgAFFAgJJQAGAEYZAA==.Illuminatti:BAAALgADCgQJBQABLgAECggJIgAVANYPAA==.Ilovllamas:BAABLgAFFH8IAAIGAAQJ5QZ3PQC6AAAGAAQJ5QZ3PQC6AAAAAA==.',
Im='Imawizard:BAABLgAECn9RAAIUAAkJ9Br+JQCEAgAUAAkJ9Br+JQCEAgAAAA==.Immadewsh:BAAALgAECgYJAgAAAA==.Impoosh:BAABLgAECn8oAAQbAAkJECH+AQCxAgAbAAkJ/SD+AQCxAgAZAAYJuh9DCADKAQAYAAYJmRcpXQCHAQAAAA==.Imsassy:BAABLgAECn8gAAILAAgJ1gxmNQB7AQALAAgJ1gxmNQB7AQAAAA==.',
In='Infectedbøb:BAABLgAECn8kAAIoAAgJBiGTCgB/AgAoAAgJBiGTCgB/AgAAAA==.Infekt:BAAALgAECgcJBwABLgAECggJGAAgAFUYAA==.Infurnal:BAAALgAECgYJBgAAAA==.Inmortuae:BAAALgAFFAIJBAABLgAECgkJIwAYALAZAA==.Innovation:BAABLgAECn8jAAIcAAYJqh9vHADBAQAcAAYJqh9vHADBAQAAAA==.',
Ip='Iprayntank:BAABLgAECn8VAAISAAYJ/AtsIAAEAQASAAYJ/AtsIAAEAQAAAA==.',
Ir='Ir:BAABLgAECn8YAAMVAAkJeAfBRgAPAQAVAAgJdAfBRgAPAQAXAAkJKQObHQAOAQAAAA==.Irissela:BAAALgAECgMJAwAAAA==.',
Iv='Ivalice:BAABLgAECn8eAAQJAAkJ4x5vAwD0AgAJAAkJ4x5vAwD0AgAWAAEJ4hmKzAA5AAAhAAEJkANUlQAkAAAAAA==.',
Iz='Izanamii:BAACLgAFFH8GAAIEAAMJLAWQcgCiAAAEAAMJLAWQcgCiAAAuAAQKfxoAAgQACAk+EZRZAJUBAAQACAk+EZRZAJUBAAAA.Izüal:BAAALgAECgIJAwABLgAFFAEJAQAHAAAAAA==.',
Ja='Jaaros:BAAALgADCggJCQAAAA==.Jackhasaids:BAAALgAECgIJAgAAAA==.Jafbe:BAABLgAECn8VAAMLAAcJXx0nFgBaAgALAAcJXx0nFgBaAgAIAAEJWxa3ewFAAAAAAA==.Jaghatai:BAAALgAECgIJAgAAAA==.Jaxxid:BAAALgAECgYJBgAAAA==.Jaymie:BAAALgAECgcJEwABLgAECggJHQASAMIOAA==.Jazlern:BAAALgAECgMJAwAAAA==.',
Je='Jesil:BAAALgADCgYJBAAAAA==.Jesilpriest:BAAALgAECgUJDgAAAA==.Jesse:BAABLgAECn8lAAIgAAkJLhkYFAB6AgAgAAkJLhkYFAB6AgAAAA==.',
Jh='Jherekal:BAAALgAECgMJBQAAAA==.',
Ji='Jimcarrey:BAABLgAECn8kAAIUAAYJlwf33QDdAAAUAAYJlwf33QDdAAAAAA==.Jimmyc:BAABLgAECn8oAAIWAAgJDBbeAgBEAQAWAAgJDBbeAgBEAQAAAA==.',
Jo='Joemauma:BAABLgAECn8oAAIUAAkJ0RRkTAD2AQAUAAkJ0RRkTAD2AQAAAA==.Johnnaay:BAAALgAECgIJAQAAAA==.Joslin:BAAALgADCgEJAQABLgAFFAYJFAAGAPwUAA==.',
Jp='Jpam:BAAALgAFFAEJAgAAAA==.',
Ju='Juku:BAAALgADCgEJAQAAAA==.July:BAAALgADCgIJAgABLgAECgcJFwARAO8YAA==.Jumbosize:BAACLgAFFH8lAAMGAAgJRhkCBgCsAgAGAAgJRhkCBgCsAgANAAEJrAaFHABEAAAuAAQKfzAAAgYACQl3JcEAALgDAAYACQl3JcEAALgDAAAA.Junrage:BAACLgAFFH8VAAIaAAUJGR78CgBOAQAaAAUJGR78CgBOAQAuAAQKfxQAAxoACQluGxoZAIMCABoACAn/HRoZAIMCAAwAAQl7CbiAACkAAAAA.Jupîter:BAABLgAECn8VAAQIAAkJvQlouQASAQAIAAgJ3gpouQASAQASAAIJ2AQCRwAlAAALAAIJKAJBnQAjAAAAAA==.Justmeldit:BAAALgAECgIJAgABLgAFFAgJJQAGAEYZAA==.',
Ka='Kaelis:BAAALgAECgUJBAAAAA==.Kaelish:BAAALgAECggJEQAAAA==.Kaerlif:BAABLgAECn8kAAMLAAgJ8xb0HAAcAgALAAgJ8xb0HAAcAgAIAAQJmhG+CQGsAAABLgAFFAcJFQAoAOkaAA==.Kaiyley:BAAALgAECgYJEgAAAA==.Kajortak:BAAALgAECgYJCwAAAA==.Kalastrian:BAABLgAECn8jAAIEAAkJzBuUJgAyAgAEAAkJzBuUJgAyAgAAAA==.Kangna:BAAALgADCgIJAgAAAA==.Karatemage:BAAALgAECgcJCQAAAA==.Karateshock:BAABLgAECn83AAIFAAkJ4BtlEwCxAgAFAAkJ4BtlEwCxAgAAAA==.Karlor:BAABLgAECn8lAAMaAAkJNxWgIgDdAQAaAAkJ5BSgIgDdAQAMAAEJEAtXgQApAAAAAA==.Karìn:BAAALgAECgMJDQAAAA==.Kasheeshb:BAAALgAECgQJBAAAAA==.Kashtark:BAAALgAECgEJAQAAAA==.Kastaway:BAAALgADCgYJEgAAAA==.Kayodawn:BAAALgAECgQJBAAAAA==.Kazuren:BAABLgAECn8sAAMVAAkJJRCkJgCsAQAVAAkJJRCkJgCsAQAXAAEJugLoRQAaAAAAAA==.',
Ke='Keahoa:BAAALgADCgcJBwAAAA==.Keano:BAABLgAECn8iAAIIAAkJhSIyCQAfAwAIAAkJhSIyCQAfAwAAAA==.Keeldemall:BAAALgAECgcJBwAAAA==.Kelia:BAAALgAECgEJAgABLgAECgkJIwAYALAZAA==.Kelinna:BAABLgAECn9IAAIIAAkJRRs6JAB0AgAIAAkJRRs6JAB0AgAAAA==.Kenichix:BAABLgAECn8iAAIEAAkJVR5OFgDRAgAEAAkJVR5OFgDRAgAAAA==.Kennidan:BAAALgAECgUJCQAAAA==.Kenshìn:BAAALgADCgEJAQAAAA==.Keymaster:BAAALgADCgIJAgAAAA==.',
Kf='Kfcchicken:BAAALgAECgQJBgAAAA==.',
Ki='Killzone:BAAALgAECgYJBQAAAA==.Kippsmithers:BAAALgAECgYJBwAAAA==.Kirin:BAABLgAECn8WAAIRAAgJqRyTAADbAQARAAgJqRyTAADbAQAAAA==.Kiritoo:BAEALgAFFAIJAwAAAA==.Kitan:BAAALgAECgEJAgAAAA==.Kitri:BAAALgAECgQJCAAAAA==.',
Kl='Klaye:BAAALgAECgYJEwABLgAECgkJKgARABkdAA==.Klotz:BAAALgAECggJEQAAAA==.',
Ko='Kodabonk:BAABLgAECn8nAAMcAAkJDRX3GQDWAQAcAAkJ5hT3GQDWAQAlAAUJjBLVSwDTAAAAAA==.Kodanorth:BAAALgAECgUJDAABLgAECgkJJwAcAA0VAA==.Kombata:BAABLgAECn8bAAIgAAgJSxkvIQATAgAgAAgJSxkvIQATAgAAAA==.Kombatant:BAAALgAECgUJCQAAAA==.Kotara:BAAALgAECgMJBAAAAA==.',
Kr='Kraur:BAAALgAECgkJEgABLgAECgkJIwAYALAZAA==.',
Ku='Kumoj:BAAALgAECgQJBAAAAA==.Kunglaoo:BAAALgADCgEJAQAAAA==.Kureth:BAAALgAECgEJBQABLgAECggJEwAHAAAAAA==.',
['Kì']='Kìngpin:BAAALgAECgEJAQABLgAECggJDwAHAAAAAA==.',
La='Lag:BAAALgADCgYJBgAAAA==.Lam:BAAALgAECgQJBQAAAA==.Lame:BAAALgAECgIJAgABLgAFFAcJEgAFABkhAA==.Lamlam:BAAALgADCgEJAgAAAA==.Lammp:BAABLgAFFH8HAAIFAAQJchalNQAMAQAFAAQJchalNQAMAQABLgAECgkJFQAKAJsYAA==.Lampp:BAAALgAECgQJBQABLgAECgkJFQAKAJsYAA==.Latharis:BAAALgADCgEJAQAAAA==.Laws:BAABLgAECn8qAAIiAAkJHhJNGgCLAQAiAAkJHhJNGgCLAQAAAA==.Lazerlips:BAAALgAFFAIJAgAAAA==.',
Le='Leezerd:BAAALgADCgcJCQAAAA==.Lemmiwinks:BAAALgAECgEJAQAAAA==.Lexsapphire:BAABLgAECn8aAAIUAAYJxgPl+QC2AAAUAAYJxgPl+QC2AAAAAA==.',
Li='Liaeda:BAABLgAECn9RAAIJAAkJmREaEgAYAgAJAAkJmREaEgAYAgAAAA==.Lianshi:BAABLgAECn8rAAMgAAkJPRlOFAB4AgAgAAkJPRlOFAB4AgAlAAEJdAT1twAhAAAAAA==.Lichplease:BAACLgAFFH8UAAIKAAcJmhn0MgCdAQAKAAcJmhn0MgCdAQAuAAQKfzEAAgoACQm5H/4WAL0CAAoACQm5H/4WAL0CAAAA.Lilithandral:BAABLgAECn8bAAIDAAgJIRYHEgDnAQADAAgJIRYHEgDnAQAAAA==.Limitedtank:BAAALgAECgQJDwAAAA==.Linainverse:BAABLgAECn8nAAMUAAkJ7wnlegCDAQAUAAkJwwnlegCDAQAfAAEJYAQbFwAgAAAAAA==.Lithdradra:BAAALgADCgEJAQAAAA==.Livermaw:BAAALgADCgIJAgAAAA==.',
Lo='Logjammin:BAAALgADCgYJBgABLgAECggJFQAmAGcWAA==.Lolo:BAAALgAFFAIJBAABLgAFFAgJIQARAJ8WAA==.Loosie:BAABLgAECn85AAIoAAkJ0CMDBAAOAwAoAAkJ0CMDBAAOAwAAAA==.Lovely:BAAALgAECgYJCwAAAA==.',
Lu='Lucylepricon:BAAALgAECgQJBwAAAA==.Ludo:BAABLgAECn8VAAIEAAYJ6CDcTgC6AQAEAAYJ6CDcTgC6AQAAAA==.Luduhcris:BAABLgAECn8eAAMFAAYJ0BljPwCwAQAFAAYJ0BljPwCwAQARAAYJHRkQMwBwAQAAAA==.Luebbersit:BAAALgAECgEJAgAAAA==.Luebberslueb:BAAALgAECgEJAQAAAA==.Luebberstiny:BAAALgADCgEJAwAAAA==.Lugnuts:BAAALgAECgQJBgAAAA==.Luketich:BAACLgAFFH8MAAISAAQJHQmKAgDbAAASAAQJHQmKAgDbAAAuAAQKfykAAhIACAl7HoEGAIACABIACAl7HoEGAIACAAAA.Lumiltiand:BAACLgAFFH8UAAQKAAgJYRFTMgCfAQAKAAYJhRJTMgCfAQApAAEJiQoxJQBUAAAiAAEJAAA0aAAAAAAuAAQKfyIABAoACAkuIWM7AEkCAAoACAkuIWM7AEkCACIAAgkBCBZSAE4AACkAAQlZDyU9ACwAAAAA.',
Lw='Lwaxana:BAAALgAECgEJAgAAAA==.',
['Lú']='Lústì:BAAALgADCgcJCQABLgAFFAYJIAAUAJMeAA==.',
Ma='Maav:BAAALgAECgUJBQAAAA==.Mac:BAAALgAECgEJAgAAAA==.Mafia:BAAALgADCgIJAgAAAA==.Mageic:BAAALgAECgkJBgAAAA==.Magistix:BAAALgAECgEJAQABLgAECgYJCwAHAAAAAA==.Maharani:BAAALgAECgIJAgAAAA==.Mahuizmaca:BAABLgAECn8qAAMLAAkJcSAAFgBcAgALAAgJwiAAFgBcAgAIAAkJrBOMWgC9AQAAAA==.Malakaa:BAAALgAECgIJAgAAAA==.Maleficante:BAAALgADCgUJBQABLgAECgkJMAAUADcPAA==.Malgoros:BAABLgAECn8xAAMEAAkJiBxqGgB2AgAEAAkJiBxqGgB2AgAoAAIJQhueZABEAAAAAA==.Malgrendin:BAABLgAECn8iAAIWAAkJYSJOEgC/AgAWAAkJYSJOEgC/AgAAAA==.Mallock:BAAALgAECgIJAgAAAA==.Malty:BAAALgAECgEJAQABLgAECgkJLQAEAE0fAA==.Maluma:BAAALgADCgYJBgAAAA==.Malédictias:BAABLgAECn8VAAIEAAcJOwSPtgC9AAAEAAcJOwSPtgC9AAAAAA==.Mamii:BAABLgAECn8mAAMcAAkJriNeAwAbAwAcAAkJViNeAwAbAwAlAAYJECPcEgBdAgAAAA==.Manaag:BAAALgAECgMJBAAAAA==.Manataurus:BAAALgADCgUJBQAAAA==.Manatreat:BAAALgAECgYJBgAAAA==.Mangø:BAAALgAECgYJBgAAAA==.Manuall:BAABLgAECn8WAAIFAAkJLA7rOgDDAQAFAAkJLA7rOgDDAQAAAA==.Maralyn:BAABLgAECn83AAISAAkJ5QyyGgBCAQASAAkJ5QyyGgBCAQAAAA==.Marbas:BAAALgAFFAMJBAAAAA==.Marshmellow:BAACLgAFFH8hAAIYAAYJXRs3KQCjAQAYAAYJXRs3KQCjAQAuAAQKfycAAxgACAkJIIYiAFcCABgACAkJIIYiAFcCABkABAlaF1AnACcBAAAA.Martense:BAABLgAECn8YAAMPAAkJmA85IQCMAQAPAAgJ5gw5IQCMAQAQAAUJUw6TFwC6AAAAAA==.Mawly:BAABLgAECn8cAAIYAAcJ6QSivQDPAAAYAAcJ6QSivQDPAAAAAA==.Maxidk:BAABLgAECn8/AAIKAAkJxyULBwA+AwAKAAkJxyULBwA+AwAAAA==.Maxidruid:BAAALgAECggJCgABLgAECgkJPwAKAMclAA==.Maxilock:BAAALgADCgYJEgABLgAECgkJPwAKAMclAA==.Maximonk:BAAALgADCgkJDQABLgAECgkJPwAKAMclAA==.Maxipriest:BAAALgADCgUJBQAAAA==.Maxisdamage:BAABLgAECn8+AAIUAAkJBxmGMQBTAgAUAAkJBxmGMQBTAgAAAA==.Mazpaladin:BAAALgAECgEJAQAAAA==.',
Mc='Mcclownerson:BAAALgADCgYJDQABLgAECgUJDQAHAAAAAA==.',
Me='Melissarian:BAABLgAECn8uAAIUAAkJBgUowAAJAQAUAAkJBgUowAAJAQAAAA==.Menari:BAAALgAECgIJBAABLgAFFAIJAwAHAAAAAA==.Mereoleona:BAACLgAFFH8HAAIYAAIJQhvykgCdAAAYAAIJQhvykgCdAAAuAAQKfxsAAhgABwk/Hzs4APgBABgABwk/Hzs4APgBAAAA.',
Mi='Midgemaisel:BAABLgAECn8aAAIFAAkJVgrXUQBsAQAFAAkJVgrXUQBsAQAAAA==.Mirado:BAABLgAECn8lAAIaAAkJJxxyGwASAgAaAAkJJxxyGwASAgAAAA==.Misplacer:BAABLgAECn8VAAIGAAgJqhlEKQAOAgAGAAgJqhlEKQAOAgAAAA==.Mithridates:BAABLgAECn8gAAIZAAgJ+Q21EAA4AQAZAAgJ+Q21EAA4AQAAAA==.',
Mk='Mkherp:BAABLgAECn8cAAIBAAgJvBl0FwANAgABAAgJvBl0FwANAgAAAA==.',
Mo='Mohg:BAAALgADCgUJCAAAAA==.Momentjess:BAACLgAFFH8eAAICAAYJaCFDFQDUAQACAAYJaCFDFQDUAQAuAAQKfyQAAwIACQkxIikEAB0DAAIACQkxIikEAB0DAA4ABwlcF7IiAM8BAAAA.Monkragga:BAAALgAECgkJDwABLgAECggJLQAVADQeAA==.Moolissa:BAAALgADCgEJAQAAAA==.Mooshine:BAAALgAECgcJDAAAAA==.Morrigon:BAAALgAECgYJBgAAAA==.Morrygan:BAAALgAECgEJAgAAAA==.Mortarien:BAAALgAECgQJBwAAAA==.Mortïx:BAABLgAECn85AAIhAAkJKCK5AQD4AgAhAAkJKCK5AQD4AgAAAA==.Mossberg:BAAALgADCgYJEgAAAA==.',
Mu='Munko:BAAALgADCgEJAQABLgAECgEJAgAHAAAAAA==.Muskaan:BAAALgAECgEJAQAAAA==.Mustakakrish:BAAALgAECgEJAQABLgAECgcJBgAHAAAAAA==.',
My='Myrtle:BAAALgADCgEJAQAAAA==.Mystborne:BAAALgAECgIJBgABLgAECgkJHAAFAGkWAA==.',
Na='Nahbgahblyn:BAAALgADCgEJAQAAAA==.Nanil:BAAALgADCgYJCgAAAA==.Naraela:BAAALgAECgQJBAAAAA==.',
Ne='Nevernude:BAABLgAECn8mAAILAAkJbSAVCQD5AgALAAkJbSAVCQD5AgAAAA==.Nexflamma:BAAALgAECgYJEwAAAA==.',
Ni='Niaru:BAABLgAECn8YAAIIAAYJ6RPv3wDeAAAIAAYJ6RPv3wDeAAAAAA==.Ninjay:BAAALgADCgUJBQAAAA==.Nirathren:BAAALgAECgEJBAABLgAECggJEwAHAAAAAA==.Niwatori:BAABLgAECn8xAAINAAkJZyMjBAAgAwANAAkJZyMjBAAgAwAAAA==.',
No='Noah:BAACLgAFFH8nAAIJAAgJMh6zAACiAgAJAAgJMh6zAACiAgAuAAQKfyAAAgkACAl3Jj4BAFkDAAkACAl3Jj4BAFkDAAAA.Nolarz:BAACLgAFFH8yAAIQAAkJYyI0AADDAgAQAAkJYyI0AADDAgAuAAQKfyIAAxAACAkTJt0AAE4DABAACAkTJt0AAE4DAA8AAQm+H/FeADgAAAAA.Nookg:BAAALgADCgkJCQAAAA==.Nookx:BAAALgAECgcJCQAAAA==.Noor:BAACLgAFFH8IAAIEAAUJoR1SBgC/AQAEAAUJoR1SBgC/AQAuAAQKfxYAAgQACAm9I5kVANUCAAQACAm9I5kVANUCAAEuAAUUCQkTAAgAqxUA.Norbon:BAAALgADCgcJCwAAAA==.Noryn:BAAALgADCgYJBgAAAA==.Nothhelm:BAAALgAECgYJDwAAAA==.',
Nu='Nugnug:BAACLgAFFH8LAAIKAAMJoiMDIgAQAQAKAAMJoiMDIgAQAQAuAAQKfxYAAgoACAn4IWscANQCAAoACAn4IWscANQCAAEuAAUUBAkKAA4A3RUA.Nukthom:BAABLgAECn8kAAIJAAkJMyB6BwCnAgAJAAkJMyB6BwCnAgAAAA==.',
Ny='Nyahbinghi:BAAALgAECggJEwABLgAECgkJGAAeABkYAA==.Nylthoran:BAAALgADCgEJAQAAAA==.Nyneaves:BAABLgAECn8gAAIBAAkJ0hhaFAArAgABAAkJ0hhaFAArAgAAAA==.',
Ob='Objekt:BAAALgADCgEJAQABLgAECggJGAAgAFUYAA==.',
Oh='Ohmenwah:BAAALgAECgQJBwAAAA==.',
Oj='Ojplosion:BAAALgAECgMJAwABLgAECgcJDAAHAAAAAA==.Ojpyroblast:BAAALgAECgcJDAAAAA==.',
Om='Omghunter:BAABLgAECn8kAAIEAAkJ3hLYPQDRAQAEAAkJ3hLYPQDRAQAAAA==.',
On='Ongodx:BAAALgADCgIJAgABLgAECgkJJgAcAK4jAA==.Onisprite:BAABLgAECn8aAAMaAAgJLQyXVABYAQAaAAcJAQ2XVABYAQAMAAQJoATFXwBjAAAAAA==.',
Op='Optimish:BAAALgAECgEJAQAAAA==.',
Or='Orchaos:BAAALgAECgQJAgAAAA==.Ordhah:BAAALgAFFAEJAQAAAA==.',
Os='Osanna:BAAALgAECgYJDgAAAA==.',
Ou='Outy:BAABLgAECn8cAAMYAAYJyhk8YwCgAQAYAAYJyhk8YwCgAQAZAAEJbgNZfQAhAAAAAA==.',
Ow='Owmyleg:BAABLgAECn8UAAIEAAYJnBNSaABpAQAEAAYJnBNSaABpAQAAAA==.',
Ox='Oxijinn:BAAALgAECgYJCQAAAA==.',
Pa='Pacanuch:BAAALgADCgYJCwAAAA==.Padding:BAAALgADCgMJAwAAAA==.Pakhan:BAABLgAECn8oAAIQAAgJlQwlDABsAQAQAAgJlQwlDABsAQAAAA==.Paladina:BAAALgADCgEJAQAAAA==.Paladout:BAABLgAECn8tAAMIAAkJjyCBGACwAgAIAAkJjyCBGACwAgASAAgJ+Bh6FQB8AQAAAA==.Palkane:BAEALgADCgQJBAABLgAECgkJJQANAOUjAA==.Palkia:BAAALgAFFAEJAQAAAA==.Pallo:BAAALgAECgEJAgAAAA==.Pandajay:BAAALgAECgcJDwABLgAFFAMJCwASAMALAA==.Paona:BAABLgAECn9NAAINAAkJChYsFgAdAgANAAkJChYsFgAdAgAAAA==.Papafloppa:BAAALgAFFAQJBAAAAA==.Papithanos:BAAALgAECgEJAQAAAA==.',
Pe='Pengting:BAAALgAECgYJCgAAAA==.Perajuve:BAAALgADCgYJBgABLgAFFAMJBQAlAHYIAA==.Peraroll:BAACLgAFFH8FAAIlAAMJdgi3LACZAAAlAAMJdgi3LACZAAAuAAQKfyoAAiUACQmHHRAJAOcCACUACQmHHRAJAOcCAAAA.Petz:BAABLgAECn8VAAMWAAYJvRvwjQAjAQAWAAYJvRvwjQAjAQAhAAQJfg6TXADQAAAAAA==.',
Ph='Phaedrah:BAABLgAECn8dAAIVAAgJGwbtTAD5AAAVAAgJGwbtTAD5AAAAAA==.Phenphen:BAACLgAFFH8RAAQkAAMJ4SHKCwCoAAAPAAMJZhvVJwDqAAAkAAIJZBvKCwCoAAAQAAEJ+iJTBQBlAAAuAAQKfyQABBAACAlUIt8CALcCABAACAm7Ht8CALcCAA8ABglIH/IyAHMBACQABAkeJGMOACYBAAAA.Phuryphen:BAAALgADCgQJBAABLgAFFAMJEQAkAOEhAA==.Physicyan:BAABLgAECn8WAAICAAkJmhCtGgD6AQACAAkJmhCtGgD6AQAAAA==.',
Pi='Piakchu:BAAALgADCgcJEwAAAA==.Pix:BAAALgAECgIJAwAAAA==.',
Pl='Plonterstank:BAABLgAECn8VAAImAAgJZxYACwCxAQAmAAgJZxYACwCxAQAAAA==.Plzdontdie:BAAALgAECgYJBwAAAA==.',
Po='Pohealer:BAAALgAECgEJAwAAAA==.Pokungfumask:BAAALgADCgIJBAAAAA==.Pookie:BAAALgAECgcJEwABLgAECgkJKAAbABAhAA==.Poombah:BAABLgAECn8rAAMcAAgJxAqCMwAyAQAcAAgJxAqCMwAyAQAlAAEJMwFjxQAIAAAAAA==.Poothang:BAAALgAECgcJCAABLgAECgkJKAAbABAhAA==.Popori:BAAALgADCgcJCQAAAA==.Popshampain:BAABLgAECn8qAAIRAAgJeR0MEwBWAgARAAgJeR0MEwBWAgAAAA==.',
Pr='Preest:BAAALgAECgUJBQABLgAECggJJAALAKobAA==.Proudmoo:BAABLgAECn8jAAILAAkJzR2ZDQC6AgALAAkJzR2ZDQC6AgAAAA==.Provoke:BAAALgAECgEJAwAAAA==.',
Ps='Psion:BAAALgAECgEJAwAAAA==.Psyrin:BAAALgAECgkJBgAAAA==.',
Pu='Pumaa:BAABLgAECn8YAAIUAAYJRhdDrgAkAQAUAAYJRhdDrgAkAQAAAA==.',
Qn='Qnz:BAAALgAECgEJAQABLgAECgEJBAAHAAAAAA==.',
Qu='Quelissa:BAAALgAECgkJBgAAAA==.Quickben:BAAALgADCgEJAQAAAA==.',
Ra='Raanz:BAAALgAECgUJDwABLgAECgkJNgANAEAWAA==.Raenlling:BAAALgADCgMJAwAAAA==.Ragehoof:BAABLgAECn8UAAIDAAgJOQyYJQAFAQADAAgJOQyYJQAFAQAAAA==.Raise:BAABLgAECn8aAAIdAAYJ1hWTGQBCAQAdAAYJ1hWTGQBCAQAAAA==.Ratchetsw:BAAALgAECgUJBQAAAA==.Rathorian:BAAALgAECgIJAgAAAA==.Rathoril:BAABLgAECn8aAAMmAAkJpRK7CwCeAQAmAAkJpRK7CwCeAQAoAAIJeQwLWQBcAAAAAA==.Ratscum:BAAALgAECgQJDAABLgAECgYJDQAHAAAAAA==.Raxik:BAAALgADCgIJAgAAAA==.Raynor:BAAALgAECgIJAgAAAA==.Rayssa:BAABLgAECn8xAAMCAAkJ2SNmAwBtAwACAAkJ2SNmAwBtAwAOAAEJKAoqdgAkAAAAAA==.',
Re='Redeker:BAABLgAECn8nAAIQAAkJ8RRmBQAjAgAQAAkJ8RRmBQAjAgAAAA==.Regera:BAAALgAECgEJAQAAAA==.Rekonstruct:BAAALgAECgEJAgAAAA==.Renardfurtif:BAAALgAECgYJBwAAAA==.Reninni:BAAALgAECgUJCAAAAA==.Renneth:BAAALgAECgIJBAAAAA==.Rentahunter:BAAALgAFFAEJAQAAAA==.Revax:BAAALgAECgYJCgABLgAECgkJIwAYALAZAA==.Revolatiion:BAAALgADCgEJAQAAAA==.Revolationzs:BAAALgAECgEJAQAAAA==.',
Rh='Rhaanz:BAAALgADCgMJAwABLgAECgkJNgANAEAWAA==.Rhynearas:BAAALgADCgUJCAABLgAECgkJUQAJAJkRAA==.',
Ri='Ridell:BAAALgADCgcJGQAAAA==.Rimasjobas:BAAALgAECgIJAgAAAA==.Rimestar:BAAALgAECgUJBwAAAA==.Rinda:BAAALgADCgUJBQABLgAFFAMJBwALABkkAA==.Ripoodoo:BAAALgAECgYJDQABLgAECgkJKAAbABAhAA==.',
Rn='Rngeesus:BAAALgAECgYJDgAAAA==.Rngnar:BAAALgAFFAIJAwAAAA==.',
Ro='Rocklie:BAAALgADCgYJBgAAAA==.Rocklii:BAAALgAECgIJAwAAAA==.Roguewolf:BAACLgAFFH8GAAINAAMJNwb4OACYAAANAAMJNwb4OACYAAAuAAQKfzAAAg0ACQmZFnIWABoCAA0ACQmZFnIWABoCAAAA.Roki:BAABLgAECn8cAAIXAAkJvhJzGABMAQAXAAkJvhJzGABMAQAAAA==.Roll:BAAALgAECgcJDQAAAA==.Rolow:BAABLgAECn8vAAIUAAkJfxtYLwBbAgAUAAkJfxtYLwBbAgAAAA==.Ronlock:BAAALgAECgIJAgAAAA==.Rooni:BAABLgAFFH8TAAIIAAkJqxUmAgDsAQAIAAkJqxUmAgDsAQAAAA==.Roony:BAAALgAECgcJDAABLgAFFAkJEwAIAKsVAA==.Roper:BAAALgAECgEJAQAAAA==.Rossaruu:BAABLgAECn8UAAIdAAgJcCB1BgCAAgAdAAgJcCB1BgCAAgAAAA==.Rot:BAABLgAECn8eAAQKAAgJICSNFwDuAgAKAAgJFySNFwDuAgAiAAEJ7SJFPABkAAApAAEJxhlgFABNAAAAAA==.Rotaderpz:BAAALgAFFAIJAgABLgAECgYJHAAEAOgWAA==.Royle:BAAALgAFFAIJAwAAAA==.',
Ru='Rune:BAABLgAECn8tAAMKAAkJihvGJwBjAgAKAAkJihvGJwBjAgApAAEJ4wrkPQArAAAAAA==.Runnerjay:BAABLgAECn8kAAIWAAgJQgrsagBsAQAWAAgJQgrsagBsAQABLgAFFAMJCwASAMALAA==.Rush:BAABLgAECn8qAAIUAAkJdRlHMABYAgAUAAkJdRlHMABYAgAAAA==.Ruswarlock:BAAALgAECgUJBQAAAA==.Ruuf:BAABLgAECn8XAAISAAkJOBzoBwBdAgASAAkJOBzoBwBdAgAAAA==.Ruufus:BAAALgAECgEJAgABLgAECgkJFwASADgcAA==.',
Ry='Rygik:BAAALgAECgIJBAABLgAECgkJGQAEAMUiAA==.Rysango:BAABLgAECn8ZAAIEAAkJxSLhEQDwAgAEAAkJxSLhEQDwAgAAAA==.Ryuujins:BAACLgAFFH8ZAAICAAcJ7SDfCwBgAgACAAcJ7SDfCwBgAgAuAAQKfycAAwIACQleJJwDAC8DAAIACQleJJwDAC8DAA4AAwmmGypXANkAAAAA.',
Sa='Saburo:BAAALgAECgcJCgAAAA==.Saelria:BAAALgAECgUJCgAAAA==.Saidar:BAAALgADCgcJCAAAAA==.Sainthoovr:BAACLgAFFH8NAAICAAMJ+R2EKwD1AAACAAMJ+R2EKwD1AAAuAAQKfzcAAwIACQk6JOoCAH0DAAIACQk6JOoCAH0DAAEABQl1HfQlAJwBAAAA.Saintluke:BAAALgAECgQJCAAAAA==.Saintmarked:BAAALgAECggJDgAAAA==.Sakuraa:BAABLgAECn8YAAIPAAkJTgfGKQCtAQAPAAkJTgfGKQCtAQAAAA==.Sandia:BAAALgADCgYJCwAAAA==.Sapheera:BAAALgAECgEJAQABLgAECggJJAAIAFEeAA==.Saphira:BAAALgAECgcJBwAAAA==.Sausage:BAAALgADCgYJBgAAAA==.',
Sc='Scam:BAAALgADCgcJCAAAAA==.Scumrat:BAAALgAECgYJDQAAAA==.Scyon:BAACLgAFFH8OAAInAAUJKhwhAQBFAQAnAAUJKhwhAQBFAQAuAAQKfz0AAicACAkFIHEBAJACACcACAkFIHEBAJACAAAA.',
Se='Seladorei:BAABLgAECn8sAAIkAAkJUiPlAQC/AgAkAAkJUiPlAQC/AgAAAA==.Senari:BAABLgAECn8wAAISAAkJWBLpDwDFAQASAAkJWBLpDwDFAQAAAA==.Sencia:BAAALgAFFAIJAwAAAA==.Seygang:BAAALgADCgYJBgAAAA==.',
Sh='Shadowblazer:BAACLgAFFH8PAAIYAAUJahLqVgAZAQAYAAUJahLqVgAZAQAuAAQKfxwAAhgACAmyGxRLAOgBABgACAmyGxRLAOgBAAAA.Shadowrainz:BAABLgAECn8rAAIBAAkJiRW9GwDnAQABAAkJiRW9GwDnAQABLgAFFAIJAgAHAAAAAA==.Shadozw:BAAALgADCgMJAwAAAA==.Shalizar:BAAALgAECgEJAQAAAA==.Shanda:BAACLgAFFH8SAAMFAAcJGSG9BACBAgAFAAcJGSG9BACBAgARAAEJaxRoVQA+AAAuAAQKfyQAAgUACQlnJMcEAGkDAAUACQlnJMcEAGkDAAAA.Shankukindly:BAAALgAECgcJCQAAAA==.Shanto:BAABLgAECn8qAAMRAAkJGR0yDgCJAgARAAkJGR0yDgCJAgAjAAEJAACGKQBDAAAAAA==.Shiftinmojo:BAAALgAECgQJCAAAAA==.Shoumei:BAABLgAECn8mAAMlAAkJqB2OEABFAgAlAAkJqB2OEABFAgAcAAEJ1wKTjwAlAAAAAA==.Shuken:BAAALgAECgQJBgAAAA==.Shwip:BAACLgAFFH8JAAMGAAMJQQh3SwCPAAAGAAMJQQh3SwCPAAANAAEJ6ByHGABaAAAuAAQKfysAAw0ACQnuIa0JAPoCAA0ACAlWIa0JAPoCAAYACQnGFiMcAGYCAAAA.',
Si='Sickalock:BAAALgAECgcJCwABLgAECgkJLgAUAMUaAA==.Sickamage:BAABLgAECn8uAAMUAAkJxRryOQAxAgAUAAkJtxnyOQAxAgAnAAMJZxynDwDHAAAAAA==.Sildayven:BAAALgADCgIJAwAAAA==.Silfra:BAAALgAECgcJEQAAAA==.Sillas:BAAALgAECgMJBQAAAA==.Silvinos:BAAALgAECgEJAgAAAA==.Sinsia:BAAALgAECgEJAQABLgAFFAIJAwAHAAAAAA==.',
Sk='Skaajin:BAAALgAECgEJAQAAAA==.',
Sl='Slapparazzi:BAAALgADCgYJBgAAAA==.Sleepingiant:BAAALgAECgUJBQAAAA==.Sleepingmad:BAABLgAFFH8KAAISAAQJlA3BDwCHAAASAAQJlA3BDwCHAAAAAA==.Sloothix:BAAALgAECgcJCgABLgAECgkJCQAHAAAAAA==.Slothbob:BAAALgADCgEJAQABLgAECgMJAwAHAAAAAA==.Slushië:BAAALgAECgQJBgAAAA==.',
Sm='Smilingdev:BAABLgAECn8aAAMZAAYJ0hQ+GADgAAAYAAYJyguipgD0AAAZAAYJIxQ+GADgAAABLgAECgkJOwAOAJ0dAA==.Smittytank:BAAALgAECgEJAQAAAA==.Smokeswell:BAAALgADCgcJBwAAAA==.',
Sn='Snagglepuss:BAAALgAECgIJAwAAAA==.',
So='Soulsproxy:BAAALgAECgcJCwAAAA==.',
Sp='Spawwn:BAAALgAECgEJAQABLgAECgkJKAAJABgZAA==.Spazdeath:BAAALgAECgQJBAAAAA==.Spellberg:BAAALgAECgQJBAAAAA==.Spilby:BAAALgADCgEJAgAAAA==.Splat:BAAALgAECgYJBgAAAA==.',
Sq='Squashee:BAAALgAECgUJBQAAAA==.Squishymonk:BAAALgADCgUJBQAAAA==.Sqûïsh:BAAALgAECgEJAgAAAA==.',
Ss='Ssilb:BAAALgAECgUJBQAAAA==.',
St='Stabbz:BAABLgAECn8sAAIPAAkJlhZREQAeAgAPAAkJlhZREQAeAgAAAA==.Stavaros:BAAALgADCgYJFgAAAA==.Stepdad:BAAALgAECgIJBAAAAA==.Stevetsin:BAAALgAFFAIJAgAAAA==.Steviewonder:BAABLgAECn8VAAIEAAgJ6CBLGQB9AgAEAAgJ6CBLGQB9AgABLgAECgcJDAAHAAAAAA==.Stillasleep:BAAALgAECgYJEAAAAA==.Stonatroll:BAAALgAECgQJBAABLgAECgkJIwAYALAZAA==.Stormdemon:BAABLgAECn80AAMMAAkJJRziDgD/AQAMAAkJJRniDgD/AQAaAAcJJRwIIgDiAQAAAA==.Stormspellz:BAABLgAECn8qAAIFAAgJEBpQGwA9AgAFAAgJEBpQGwA9AgAAAA==.Stormyspellz:BAABLgAECn8mAAIOAAkJXBslGgALAgAOAAkJXBslGgALAgAAAA==.',
Su='Subwayeater:BAACLgAFFH8KAAIXAAUJMQ14FwAeAQAXAAUJMQ14FwAeAQAuAAQKfyQAAxcACAmPEtkfAIABABcACAmPEtkfAIABABUABQm8FAFNAPkAAAAA.Subzro:BAACLgAFFH8GAAIUAAIJuAwopQCHAAAUAAIJuAwopQCHAAAuAAQKfy4AAhQACAlmGMVCABMCABQACAlmGMVCABMCAAAA.Summäurs:BAAALgADCgMJAwABLgAECgkJFQAIAL0JAA==.Supay:BAABLgAECn8ZAAImAAkJ8AiwEQAzAQAmAAkJ8AiwEQAzAQAAAA==.Superhealss:BAACLgAFFH8GAAIGAAMJuwiYSwCOAAAGAAMJuwiYSwCOAAAuAAQKfxgAAwYACQmiEVkuAOwBAAYACQmiEVkuAOwBAA0ABAncFItRAMgAAAAA.Suwgo:BAAALgADCgIJAgAAAA==.',
Sy='Sylosis:BAABLgAECn8fAAIKAAgJ3Q3IjQBKAQAKAAgJ3Q3IjQBKAQAAAA==.Syzzle:BAACLgAFFH8GAAIUAAMJuBObOAC5AAAUAAMJuBObOAC5AAAuAAQKfxkAAxQACAnxH5M2AJoCABQACAloH5M2AJoCAB8ABAkZHUcIAOcAAAAA.',
Ta='Takkiya:BAAALgAECgEJAQABLgAECgkJHAAXAL4SAA==.Taksham:BAAALgAECgEJAQABLgAECgkJHAAXAL4SAA==.Talicso:BAACLgAFFH8XAAIUAAcJmQzlRQBbAQAUAAcJmQzlRQBbAQAuAAQKfy0AAxQACQkfHa4jAI4CABQACQkfHa4jAI4CACcABAkXEeAOANUAAAAA.Talos:BAAALgAECgUJBQABLgAECggJHAAaANgeAA==.Talzinn:BAAALgAECggJCQABLgAECggJHAAaANgeAA==.Tam:BAAALgAECgEJAQABLgAFFAgJJwAJADIeAA==.Tankr:BAAALgAECgUJBQAAAA==.Tarkinal:BAABLgAECn8cAAIFAAkJ7RxuFgCWAgAFAAkJ7RxuFgCWAgAAAA==.',
Te='Teepin:BAAALgADCgEJAQAAAA==.Teezee:BAABLgAECn89AAIIAAkJSyIoDwDsAgAIAAkJSyIoDwDsAgAAAA==.Teitterdrud:BAAALgADCgUJBQAAAA==.Telira:BAAALgAFFAEJAQABLgAFFAIJAgAHAAAAAA==.Temetnosce:BAAALgAECgIJAwABLgAECgcJBwAHAAAAAA==.Tempura:BAABLgAECn8iAAIUAAkJcBvrOAA1AgAUAAkJcBvrOAA1AgAAAA==.Tenebros:BAAALgAECgEJAgAAAA==.Termakill:BAAALgAECggJCgAAAA==.Testament:BAAALgAECgEJAQAAAA==.',
Th='Thanatus:BAABLgAECn8UAAIKAAYJuBS03gDWAAAKAAYJuBS03gDWAAAAAA==.Thath:BAABLgAECn8gAAImAAYJ0iH5CgCuAQAmAAYJ0iH5CgCuAQAAAA==.Thaulnor:BAAALgADCgEJAgAAAA==.Thavus:BAAALgAECgQJBgAAAA==.Themartian:BAABLgAECn8ZAAMgAAYJOBUuKABzAQAgAAYJOBUuKABzAQAlAAMJOQR8ZQB3AAAAAA==.Thepet:BAAALgAECgYJBgAAAA==.Theshinigami:BAAALgAECgQJBAAAAA==.Thevinny:BAAALgADCgcJCwAAAA==.Thruumm:BAABLgAECn8XAAIIAAgJ+QvilgBHAQAIAAgJ+QvilgBHAQAAAA==.Thunsibution:BAAALgAECgQJBgABLgADCgkJCQAHAAAAAA==.Thydriel:BAAALgADCgcJBwABLgAECggJIAAGAGMcAA==.',
Ti='Tickz:BAABLgAECn8+AAQbAAkJ4yNYAQDjAgAYAAkJ/iLfCQACAwAbAAcJhiNYAQDjAgAZAAIJ0xlNNgBLAAAAAA==.Tidepods:BAAALgADCgIJAgAAAA==.Tistic:BAAALgAECgEJAgAAAA==.',
To='Toat:BAAALgAECgUJDQAAAA==.Toeran:BAABLgAECn9MAAMSAAkJ0CAvAwDqAgASAAkJ0CAvAwDqAgAIAAIJzA6npQEsAAAAAA==.Tokémon:BAAALgAECgMJAwAAAA==.Totesup:BAAALgAECgYJDQAAAA==.Toxren:BAABLgAFFH8FAAILAAMJ/hClBABuAAALAAMJ/hClBABuAAAAAA==.',
Tr='Traelin:BAAALgAFFAIJAwABLgAFFAYJFAAGAPwUAA==.Traylesong:BAAALgADCgYJCgAAAA==.Tread:BAACLgAFFH8RAAIaAAUJXB4PHwA1AQAaAAUJXB4PHwA1AQAuAAQKfzEAAhoACAk9JvkGAO4CABoACAk9JvkGAO4CAAAA.Trickee:BAABLgAECn8bAAIUAAgJiQrZqwAoAQAUAAgJiQrZqwAoAQABLgAECgkJJgAcAK4jAA==.Trisdale:BAAALgAECgEJAgAAAA==.Trôlol:BAAALgAECgEJAwABLgAECgcJDQAHAAAAAA==.',
Ts='Tskaha:BAABLgAECn8WAAIGAAcJtArNYwAJAQAGAAcJtArNYwAJAQAAAA==.',
Tu='Tulip:BAAALgADCgkJFgABLgAECggJIQAUAJ0IAA==.',
Ty='Tyria:BAACLgAFFH8IAAIhAAMJ+hShGwDTAAAhAAMJ+hShGwDTAAAuAAQKf1sAAiEACQnOINUBAPACACEACQnOINUBAPACAAAA.Tyronius:BAAALgAECgUJDAAAAA==.',
Um='Umbraxion:BAABLgAECn8jAAMTAAgJAwzgFQCRAQATAAgJzgrgFQCRAQAVAAIJfQiNigBHAAAAAA==.',
Un='Undeadmerlin:BAAALgAECgYJBgAAAA==.Unholyfaith:BAAALgAECgcJDQAAAA==.',
Ur='Urabrask:BAAALgADCgUJBQABLgAECgYJBgAHAAAAAA==.Urizarah:BAAALgAECgYJCwAAAA==.',
Ut='Utrecht:BAAALgAECgMJBQAAAA==.',
Va='Vaniss:BAABLgAECn8VAAMQAAcJ5BrlCAC4AQAQAAcJchflCAC4AQAkAAUJfRReEAAEAQABLgAECgkJMQAEAIgcAA==.Varg:BAAALgADCgEJAQAAAA==.Varsil:BAAALgAECgQJBQAAAA==.Vashstampede:BAABLgAECn8iAAMIAAYJXiCIfwBwAQAIAAYJhhqIfwBwAQASAAMJ/h2gMACkAAAAAA==.',
Ve='Velithiria:BAABLgAECn8kAAIWAAgJJRTxJAAoAgAWAAgJJRTxJAAoAgAAAA==.Velrik:BAABLgAECn8WAAIQAAcJKRltCgCRAQAQAAcJKRltCgCRAQAAAA==.Venerable:BAAALgAFFAEJAQAAAA==.Vengeance:BAAALgAECgEJAwAAAA==.Vernali:BAABLgAECn8gAAIKAAgJ9xdgUADSAQAKAAgJ9xdgUADSAQAAAA==.Vernalia:BAAALgAECgEJAgABLgAECggJIAAKAPcXAA==.Vezdew:BAAALgAECgMJAwABLgAFFAcJEgATAK8aAA==.Vezdormi:BAAALgAECgQJBAABLgAFFAcJEgATAK8aAA==.Vezdormu:BAACLgAFFH8SAAMTAAcJrxq5AgBYAQATAAYJbB25AgBYAQAVAAEJ/AyYYgBLAAAuAAQKfyUAAxMACQnPJNkAAG4DABMACQnPJNkAAG4DABUABwlNGe0hAMsBAAAA.Vezzug:BAAALgAECgEJAQABLgAFFAcJEgATAK8aAA==.',
Vi='Vitrixz:BAAALgADCggJHgAAAA==.Vizdicator:BAABLgAECn84AAMSAAkJ2hPEEAC6AQASAAkJ2hPEEAC6AQAIAAYJQA4KxAADAQAAAA==.Viztryalle:BAAALgAECgEJAQAAAA==.',
Vu='Vulcãnus:BAABLgAECn8ZAAMUAAgJ1wmmqwAoAQAUAAgJ1wmmqwAoAQAfAAEJdwOREQApAAABLgAECgkJFQAIAL0JAA==.',
We='Werse:BAABLgAECn8tAAIOAAkJlB7IDgByAgAOAAkJlB7IDgByAgAAAA==.',
Wh='Whereyougo:BAAALgADCgYJBgAAAA==.Whodi:BAAALgAECgUJCQAAAA==.',
Wi='Willowdusk:BAAALgAECgMJBAABLgAECgYJBgAHAAAAAA==.Willowmist:BAAALgAECgYJBgAAAA==.Willtolive:BAAALgAECggJDgABLgAECgkJFQAWAGQRAA==.Wind:BAAALgAECgQJBAAAAA==.',
Wo='Wolful:BAAALgAECgEJAgABLgAECgkJKgAUAHUZAA==.Womanizer:BAAALgAECgEJAQAAAA==.',
Wr='Wrathofpride:BAAALgADCgYJBgAAAA==.',
Xa='Xackta:BAAALgAECgEJAQAAAA==.Xantom:BAAALgADCgYJBgAAAA==.Xatan:BAAALgAECgEJAwAAAA==.Xaverian:BAAALgADCggJFQAAAA==.',
Xi='Xirim:BAABLgAFFH8GAAIaAAMJFCC0KwAFAQAaAAMJFCC0KwAFAQAAAA==.',
Xj='Xjeshy:BAAALgADCggJGQAAAA==.Xjoshy:BAAALgADCgcJEwAAAA==.',
Xn='Xnatem:BAABLgAECn8xAAIDAAkJkiDQBQC2AgADAAkJkiDQBQC2AgAAAA==.',
Xo='Xoliver:BAAALgAECgQJBAAAAA==.',
Xt='Xtinaz:BAABLgAECn8VAAMZAAYJ2Q0iGADgAAAZAAYJ2Q0iGADgAAAYAAEJ8wGtYwEdAAAAAA==.',
Xy='Xyrim:BAAALgAECgUJBQAAAA==.',
['Xë']='Xëllos:BAAALgADCgQJBAAAAA==.',
Ya='Yashiro:BAABLgAECn80AAILAAkJgBD+KgC4AQALAAkJgBD+KgC4AQAAAA==.',
Ye='Yeraleth:BAABLgAECn8gAAIGAAgJYxzYFwB4AgAGAAgJYxzYFwB4AgAAAA==.',
Yi='Yisiwang:BAAALgADCgMJAwAAAA==.',
Yo='Yorkj:BAAALgAECgcJDwAAAA==.Yougoboom:BAAALgAECgMJAwAAAA==.',
Yv='Yvonca:BAAALgADCgEJAQAAAA==.',
Za='Zalthorax:BAABLgAECn8jAAQYAAkJsBkEIgBaAgAYAAkJ6hgEIgBaAgAbAAIJAiIqLgBkAAAZAAEJwwMYfAAkAAAAAA==.Zarri:BAAALgADCgUJBQAAAA==.Zatilion:BAACLgAFFH8GAAIIAAMJWgU3ggCxAAAIAAMJWgU3ggCxAAAuAAQKfxwAAggABwm0E1yDAGgBAAgABwm0E1yDAGgBAAAA.Zayn:BAAALgAECgEJAQAAAA==.',
Ze='Zenju:BAABLgAFFH8FAAIRAAEJ2xoJUwBJAAARAAEJ2xoJUwBJAAAAAA==.Zenki:BAAALgAECgkJEwAAAA==.Zenru:BAABLgAFFH8FAAIiAAUJvwoGJwC8AAAiAAUJvwoGJwC8AAAAAA==.Zepharion:BAAALgAECgYJCQAAAA==.Zephiday:BAACLgAFFH8JAAIBAAMJURIIJQDPAAABAAMJURIIJQDPAAAuAAQKfyAAAgEACAlAG34OAJwCAAEACAlAG34OAJwCAAAA.Zerfonk:BAABLgAECn8VAAIcAAgJ9CJCDADKAgAcAAgJ9CJCDADKAgAAAA==.',
Zh='Zhushii:BAABLgAECn82AAMNAAkJQBaqGAAHAgANAAkJsRWqGAAHAgAdAAYJlg5YHAAoAQAAAA==.',
Zi='Ziggamoo:BAAALgAECgcJDwABLgAECgkJKAAJABgZAA==.Ziggashot:BAABLgAECn8oAAIJAAkJGBncCABZAgAJAAkJGBncCABZAgAAAA==.Zinsus:BAAALgAECgIJAgABLgAECgkJIwAYALAZAA==.',
Zo='Zoloftt:BAAALgADCgYJFgAAAA==.Zoromaak:BAAALgAECgIJAgABLgAFFAUJDwAKAAcXAA==.',
Zu='Zumbao:BAAALgAECgIJAgAAAA==.Zurahahsha:BAABLgAECn8sAAIjAAkJogqaEgCNAQAjAAkJogqaEgCNAQAAAA==.',
Zy='Zynbane:BAAALgAECgkJCQAAAA==.',
['Zè']='Zèd:BAAALgADCgYJBAAAAA==.',
['Ðr']='Ðrow:BAACLgAFFH8PAAIhAAUJExQ5FgAPAQAhAAUJExQ5FgAPAQAuAAQKfyQAAiEACAmWGRQNAI8BACEACAmWGRQNAI8BAAAA.',
['Óx']='Óxy:BAACLgAFFH8FAAIZAAMJcANcEgCkAAAZAAMJcANcEgCkAAAuAAQKfxYAAhkACAkpFLgJAKsBABkACAkpFLgJAKsBAAAA.',
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
