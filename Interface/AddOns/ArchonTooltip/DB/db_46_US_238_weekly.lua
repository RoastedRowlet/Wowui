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

local lookup = {'Monk-Brewmaster','Hunter-BeastMastery','Hunter-Survival','Unknown-Unknown','Paladin-Retribution','Priest-Discipline','Priest-Shadow','Hunter-Marksmanship','Mage-Frost','Priest-Holy','Warrior-Protection','DeathKnight-Unholy','Shaman-Restoration','Shaman-Elemental','Druid-Feral','DemonHunter-Havoc','Warlock-Demonology','Warlock-Destruction','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Monk-Mistweaver','DemonHunter-Devourer','Warrior-Fury','Druid-Restoration','DeathKnight-Frost','DeathKnight-Blood','Druid-Guardian','Warrior-Arms','Warlock-Affliction','Shaman-Enhancement','Rogue-Assassination','Rogue-Outlaw','Paladin-Holy','Druid-Balance','Monk-Windwalker','Paladin-Protection','Rogue-Subtlety','Mage-Arcane',}
local provider = {region='US',realm='Wildhammer',name='US',type='weekly',zone=46,date='2026-06-07',data={Aa='Aayrawn:BAAALgAECgcJBwAAAA==.',
Ab='Abaddonaxx:BAAALgADCgYJBgAAAA==.',
Ac='Aceshaman:BAAALgAECgUJBgAAAA==.Acesmash:BAABLgAECn8lAAIBAAkJGCLcBQDZAgABAAkJGCLcBQDZAgAAAA==.Ackrenezoth:BAAALgAECgQJBwAAAA==.',
Ad='Adymisk:BAAALgADCgEJAQAAAA==.',
Ag='Agorot:BAAALgAFFAEJAQAAAA==.',
Ak='Akadion:BAAALgADCgcJCgAAAA==.Akatali:BAAALgAECgQJBgAAAA==.',
Al='Aldannia:BAABLgAECn8VAAMCAAcJ4A/QVwBhAQACAAcJ8wzQVwBhAQADAAYJ7gz5MQAYAQAAAA==.Alextros:BAEALgAECgYJEQABLgAECgcJCgAEAAAAAA==.Alloren:BAAALgAECgQJBgAAAA==.Almond:BAAALgAECgEJAgAAAA==.',
Am='Amaranthe:BAAALgAECgEJAQAAAA==.Amrax:BAABLgAECn8yAAIFAAkJpRWmOgAOAgAFAAkJpRWmOgAOAgAAAA==.Amynre:BAABLgAECn8aAAMGAAkJKRCfFQD5AQAGAAkJKRCfFQD5AQAHAAMJ6w33VABvAAAAAA==.',
An='Anarsa:BAAALgAECgUJCgAAAA==.Angstyboi:BAAALgAECgQJBAAAAA==.',
Aq='Aquabat:BAACLgAFFH8VAAQIAAQJExttEABKAQAIAAQJBBltEABKAQADAAMJdBfQGAD5AAACAAMJ0BdZbgChAAAuAAQKfyYABAMACQlHIroMAFYCAAMACQmFILoMAFYCAAgABwmrH38bAEwCAAIABQlwJRgoABgCAAAA.',
Ar='Arvyy:BAABLgAECn8mAAIJAAkJWBqvKgBpAgAJAAkJWBqvKgBpAgAAAA==.',
As='Ashbringer:BAACLgAFFH8NAAIFAAMJECR3OQArAQAFAAMJECR3OQArAQAuAAQKfyYAAgUACQlgI7EUAL4CAAUACQlgI7EUAL4CAAAA.',
At='Atria:BAACLgAFFH8IAAIJAAQJuwwKcAD2AAAJAAQJuwwKcAD2AAAuAAQKfycAAgkACAlfF2FCAA8CAAkACAlfF2FCAA8CAAAA.Attia:BAABLgAECn8VAAMKAAcJBRbBJgCDAQAKAAcJBRbBJgCDAQAHAAEJRhe6dgBDAAAAAA==.',
Av='Avaris:BAAALgADCgIJAgAAAA==.Avatarbambi:BAAALgADCgUJAgAAAA==.',
Ax='Axtar:BAABLgAECn8lAAILAAkJ6RhcDwDnAQALAAkJ6RhcDwDnAQAAAA==.',
Ay='Ayyitzrich:BAAALgADCgQJBAAAAA==.',
Ba='Babarazzar:BAAALgADCgYJBgAAAA==.Baladoria:BAACLgAFFH8LAAIKAAQJphISFgD+AAAKAAQJphISFgD+AAAuAAQKfzYAAgoACQlbIasEAC8DAAoACQlbIasEAC8DAAAA.Baldkrank:BAAALgAECgEJAQAAAA==.Bananabowman:BAAALgAECgEJAgAAAA==.Barrels:BAABLgAECn8lAAMCAAkJux6wHwBfAgACAAgJLx2wHwBfAgADAAkJnBWLEgARAgABLgAFFAIJBQAMAP4PAA==.Bartab:BAABLgAECn87AAMNAAkJLR7bCwDzAgANAAkJLR7bCwDzAgAOAAEJEwPctAAeAAABLgAECgkJPwAPADEhAA==.Baruku:BAAALgAFFAEJAQAAAA==.Bashfulwaltz:BAAALgAECgcJBwAAAA==.Bastadi:BAAALgAFFAIJBAAAAA==.',
Be='Bearemy:BAAALgAECgcJBwAAAA==.Beastling:BAAALgAECgYJDwAAAA==.Beau:BAACLgAFFH8LAAIQAAQJvyNeBQCfAQAQAAQJvyNeBQCfAQAuAAQKfzUAAhAACQlTJdYCACYDABAACQlTJdYCACYDAAAA.Beauchi:BAAALgAECgUJBQABLgAFFAQJCwAQAL8jAA==.Beauwi:BAAALgAECgQJBgABLgAFFAQJCwAQAL8jAA==.Beldin:BAAALgAECgEJAQAAAA==.',
Bi='Bigshekels:BAAALgAECgEJAQAAAA==.Bigulsworth:BAAALgADCgcJCAAAAA==.',
Bl='Blackadder:BAAALgAECgcJEgAAAA==.Blawkk:BAAALgAECgYJBgAAAA==.Blenton:BAAALgAECgEJAQAAAA==.Bloodussy:BAAALgADCgUJBQAAAA==.Bluck:BAAALgADCgcJEQAAAA==.Blueeyesdrag:BAAALgADCgEJAQAAAA==.Blueombre:BAAALgAECgEJAQAAAA==.',
Bo='Boing:BAAALgAFFAIJAgAAAA==.Boltngo:BAAALgADCgIJAgAAAA==.Bombur:BAACLgAFFH8HAAIRAAMJVxbBZwDmAAARAAMJVxbBZwDmAAAuAAQKfy8AAxEACQlSHGgjAE0CABEACQlSHGgjAE0CABIAAQkAAB1kAEYAAAAA.Bosstradamus:BAAALgAFFAEJAQABLgAFFAIJAgAEAAAAAA==.Boston:BAAALgAECggJEwAAAA==.Bottles:BAABLgAFFH8FAAIMAAIJ/g9OzQCLAAAMAAIJ/g9OzQCLAAAAAA==.',
Br='Braesong:BAAALgAECgIJAgAAAA==.Bratva:BAAALgAECgcJAwAAAA==.',
Bu='Bubagony:BAAALgADCgQJBAABLgAFFAUJEwAMAPAgAA==.Bubbells:BAAALgADCgEJAQAAAA==.Bullmedic:BAAALgADCgYJBgAAAA==.Burakku:BAABLgAECn8VAAQTAAcJEhnTGgDzAQATAAcJEhnTGgDzAQAUAAUJJwgCMQDpAAAVAAEJAAC0PgA1AAABLgAFFAUJCAAWALgXAA==.Burguerkiing:BAAALgADCgMJAwAAAA==.Burph:BAAALgADCggJCAAAAA==.Buttonsmash:BAAALgAECgcJEAABLgAFFAcJIQAUAFUSAA==.Buzzkill:BAAALgAECgIJAgAAAA==.',
['Bâ']='Bâbyrage:BAAALgADCgcJDwAAAA==.',
Ca='Cairen:BAABLgAECn8kAAIXAAkJMh5FIQBEAgAXAAkJMh5FIQBEAgAAAA==.Calzraxx:BAAALgAECgkJEwAAAA==.Carstaller:BAAALgAECgQJBAAAAA==.Cartons:BAABLgAECn8VAAIFAAgJySAwEwD5AgAFAAgJySAwEwD5AgABLgAFFAIJBQAMAP4PAA==.',
Cc='Ccaan:BAAALgAECgkJEQAAAA==.Ccian:BAAALgAECgQJBAAAAA==.',
Ce='Celinn:BAACLgAFFH8FAAMKAAQJtwyLJgB6AAAKAAIJoROLJgB6AAAGAAIJzAVgPAByAAAuAAQKfzcAAwoACQkPHacLAKECAAoACQkPHacLAKECAAYABgniEo8rAG4BAAAA.',
Ch='Chadgar:BAAALgADCgUJBwAAAA==.Chalupacabra:BAAALgADCgIJAgAAAA==.Chappie:BAAALgAECgEJAQABLgAFFAQJFQAIABMbAA==.Charliek:BAABLgAFFH8IAAIYAAQJQA2WJQAPAQAYAAQJQA2WJQAPAQAAAA==.Cherches:BAAALgADCgEJAQAAAA==.Childish:BAAALgAECgYJDQAAAA==.Chimalma:BAAALgAFFAIJBAAAAA==.Chiqui:BAAALgAECgEJAgAAAA==.Chorr:BAAALgAECgMJAwABLgAFFAIJBAAEAAAAAA==.',
Cl='Clarabow:BAAALgAFFAIJAwAAAA==.Closure:BAABLgAECn8YAAIZAAkJJSPbDADWAgAZAAkJJSPbDADWAgAAAA==.Cloudsx:BAAALgADCgMJAwAAAA==.',
Co='Coatlicue:BAABLgAECn8UAAMKAAkJFx+hEQBVAgAKAAgJRSGhEQBVAgAHAAUJZBTFMQBXAQABLgAFFAIJBAAEAAAAAA==.Coby:BAABLgAECn8VAAIWAAgJqSRmCAAIAwAWAAgJqSRmCAAIAwAAAA==.Coffins:BAAALgAECgYJEQABLgAFFAIJBQAMAP4PAA==.Corgartah:BAAALgADCgYJBgAAAA==.Covell:BAAALgAECgcJDAAAAA==.',
Cr='Crates:BAAALgAECgUJCAABLgAFFAIJBQAMAP4PAA==.Crimsonmagic:BAAALgAECgEJAgAAAA==.Crosswalkk:BAAALgADCgMJAwAAAA==.Crygore:BAAALgAECgQJCgABLgAECgIJBgAEAAAAAA==.',
Cy='Cypherrellik:BAABLgAECn8cAAMQAAkJhRBmHQCBAQAQAAkJhRBmHQCBAQAXAAIJHgIg2QA9AAAAAA==.',
['Cò']='Còrgi:BAAALgAECgEJAQABLgAECgkJPQAMAIAhAA==.',
Da='Daktok:BAAALgADCgQJBAAAAA==.Damer:BAAALgADCgkJFgAAAA==.Damues:BAAALgAECggJDwAAAA==.Danaric:BAAALgAECgMJBgAAAA==.Dannyphentom:BAABLgAECn8XAAQMAAYJVxXbjgBAAQAMAAYJVxXbjgBAAQAaAAMJxhdZIQCyAAAbAAMJmA4qNgCQAAAAAA==.Dargar:BAAALgAECgEJAQAAAA==.Darkling:BAABLgAECn8dAAIQAAcJoB22EgD1AQAQAAcJoB22EgD1AQAAAA==.Darknyss:BAAALgADCggJCQAAAA==.',
De='Deathfortres:BAAALgAECgcJCwAAAA==.Dedeye:BAAALgADCgMJAwAAAA==.Dekumime:BAAALgAECggJCwAAAA==.Demandred:BAAALgAECgkJEwAAAA==.Demongrass:BAACLgAFFH8KAAIXAAUJexntNwAyAQAXAAUJexntNwAyAQAuAAQKfzIAAhcACAkyII4pABoCABcACAkyII4pABoCAAAA.Denaric:BAAALgAECgYJEAAAAA==.Derty:BAAALgAFFAIJAgAAAA==.',
Di='Diviñehymn:BAAALgAECgcJDwAAAA==.',
Do='Donet:BAAALgADCgEJAQAAAA==.Doppy:BAAALgADCgYJBgAAAA==.',
Dr='Dragondeezz:BAAALgAECgIJBAABLgAECgIJBgAEAAAAAA==.Dragondznuts:BAACLgAFFH8hAAIUAAcJVRLMCQD1AQAUAAcJVRLMCQD1AQAuAAQKfz0ABBQACQluHqwFALECABQACQluHqwFALECABMAAgnoHo5gAKsAABUAAglHCJwdAFoAAAAA.Draxtos:BAEALgAECgcJCgAAAA==.Dreamevil:BAAALgAECgkJBgAAAA==.Drroxso:BAAALgAECgQJBAAAAA==.Dríppy:BAAALgAECgQJBAAAAA==.',
Ea='Eazybake:BAAALgADCgEJAQAAAA==.',
Ei='Eilerra:BAABLgAECn8pAAIJAAcJCyG+NgA3AgAJAAcJCyG+NgA3AgAAAA==.',
El='Elementony:BAABLgAECn85AAIOAAkJpBB0IwD1AQAOAAkJpBB0IwD1AQAAAA==.Elkdruid:BAABLgAECn8eAAMZAAgJxBCXTwBnAQAZAAgJxBCXTwBnAQAcAAEJQAzlNgAbAAABLgAFFAQJBwACAKQKAA==.Elladamri:BAAALgAECgEJAQAAAA==.Elodi:BAAALgAECgEJAQAAAA==.',
Em='Emberglow:BAAALgAECgcJEgAAAA==.Empyrean:BAAALgADCgQJBQAAAA==.Emylia:BAAALgAECgcJEAAAAA==.',
Er='Eresdelor:BAABLgAECn8YAAMLAAkJlROFFgCFAQALAAkJzhGFFgCFAQAdAAQJLA4XJwC2AAAAAA==.Erre:BAABLgAECn8mAAIRAAkJ5h7OGgB+AgARAAkJ5h7OGgB+AgAAAA==.',
Es='Esdeáth:BAAALgADCgEJAQAAAA==.Estia:BAAALgAECgcJCwABLgAFFAIJBAAEAAAAAA==.',
Ev='Evoktor:BAAALgAECgEJAQAAAA==.',
Fa='Facasdeath:BAAALgAECgYJDAAAAA==.Failure:BAEBLgAECn8cAAIDAAkJ+hQcDQD6AQADAAkJ+hQcDQD6AQABLgAFFAQJCwABAOcSAA==.Farmtoon:BAAALgAECgYJDQAAAA==.Fartbroknvis:BAAALgAFFAIJAgAAAA==.',
Fe='Feardapain:BAACLgAFFH8SAAIRAAQJLxdoQwA1AQARAAQJLxdoQwA1AQAuAAQKfz0ABBEACQk5IhUPAAEDABEACAk5IhUPAAEDABIAAQkAADFcAFoAAB4AAQkAAP84AAwAAAAA.Feardatpain:BAAALgAFFAEJAQAAAA==.Fellyn:BAAALgADCggJCwAAAA==.',
Ff='Ff:BAABLgAFFH8LAAIJAAMJwAALmACTAAAJAAMJwAALmACTAAAAAA==.',
Fl='Flar:BAAALgAFFAEJAQAAAA==.Flixie:BAABLgAECn8fAAINAAkJQSFQBQBUAwANAAkJQSFQBQBUAwABLgAFFAYJIgAWAJATAA==.Flyingcow:BAAALgAECgIJAwAAAA==.',
Fo='Foenix:BAAALgADCgYJBgAAAA==.Foxoffire:BAAALgAECgIJBQAAAA==.Foxu:BAAALgAECgcJBwAAAA==.Foxymoron:BAAALgAECgcJCwAAAA==.Fozzi:BAABLgAECn8oAAIWAAkJQSGbBwAYAwAWAAkJQSGbBwAYAwAAAA==.',
Fr='Freakazoid:BAABLgAECn8wAAIHAAkJjx13EABPAgAHAAkJjx13EABPAgAAAA==.Fritark:BAAALgAECgcJBwABLgAECgkJEwAEAAAAAA==.Fritzyp:BAAALgAECgkJEwAAAA==.Frogzqc:BAAALgAECgEJAgAAAA==.Frostyburn:BAAALgAECgYJEQAAAA==.Frozenrage:BAAALgADCgcJCwAAAA==.',
['Fë']='Fëanor:BAAALgAECggJCgAAAA==.',
Ga='Gabos:BAAALgADCgEJAQAAAA==.Garayice:BAAALgADCgIJAgAAAA==.Garycoleman:BAAALgADCgEJAQAAAA==.Gaxxen:BAAALgAECgUJBQAAAA==.',
Ge='Gena:BAAALgADCgcJCAAAAA==.Geörge:BAACLgAFFH8YAAIHAAcJ5xcfCADNAQAHAAcJ5xcfCADNAQAuAAQKfywAAgcACAkxISIIAAIDAAcACAkxISIIAAIDAAAA.',
Gh='Ghostyganja:BAAALgAECgQJBAABLgAFFAMJAwAEAAAAAA==.',
Gi='Giratiña:BAAALgAECgEJAgABLgAFFAIJAwAEAAAAAA==.',
Gl='Glary:BAAALgAECgEJAQAAAA==.Glavendale:BAAALgADCgUJBQAAAA==.',
Go='Goatcheezey:BAAALgADCgYJDAAAAA==.Goblinsox:BAAALgAECgQJBAAAAA==.Goluck:BAAALgAECgEJAQAAAA==.Gordothe:BAAALgADCgUJBQABLgAECgUJBgAEAAAAAA==.',
Gr='Grimel:BAAALgAECgQJCAABLgAECgYJEAAEAAAAAA==.Grimghoul:BAAALgAECgQJCQABLgAECgYJEAAEAAAAAA==.Grimgram:BAAALgAECgYJEAAAAA==.Gripyoulol:BAAALgAECgQJBQAAAA==.Grotelek:BAABLgAECn8hAAIfAAkJTRPnDQDGAQAfAAkJTRPnDQDGAQAAAA==.Grotret:BAAALgAECgIJAgAAAA==.Grouchy:BAAALgADCgMJAwAAAA==.Grumpywaltz:BAAALgAECgQJBAAAAA==.',
Gu='Gulimath:BAAALgAECgUJBgAAAA==.',
Ha='Haedrath:BAAALgAECgEJAQABLgAECgcJKQAJAAshAA==.Halconotachi:BAABLgAECn9EAAIDAAkJRRofCgB5AgADAAkJRRofCgB5AgAAAA==.Hammerfoot:BAAALgAECgcJBwAAAA==.Haranir:BAAALgAECgYJCAAAAA==.Harcat:BAABLgAECn8aAAMIAAgJ7BSqDgBkAQAIAAgJ7BSqDgBkAQADAAEJYQEYaAAdAAAAAA==.Hartracks:BAAALgAECgUJBQAAAA==.Hatijo:BAAALgAECgYJBwAAAA==.Hawgbawl:BAABLgAECn8iAAIYAAgJbxtvFwAuAgAYAAgJbxtvFwAuAgAAAA==.Hawgdream:BAAALgAECgcJEQAAAA==.',
He='Hellequin:BAACLgAFFH8ZAAIgAAcJJhfoAAAHAgAgAAcJJhfoAAAHAgAuAAQKfzkAAyAACQkDIpEBAOICACAACQkDIpEBAOICACEAAQkpA4cPACoAAAAA.Henkojin:BAAALgADCgYJBgAAAA==.Heyitzlock:BAAALgAECgYJCQAAAA==.Heyyitzrich:BAAALgAECgQJDQAAAA==.Heyyitzrichh:BAABLgAFFH8JAAIRAAMJzBZaZgDpAAARAAMJzBZaZgDpAAAAAA==.Heyytaco:BAAALgAECggJEgAAAA==.',
Hi='Hiels:BAAALgAECgcJBwAAAA==.Hirogon:BAAALgAECgEJAwAAAA==.',
Ho='Hobb:BAABLgAECn8pAAIFAAkJcB70GwCUAgAFAAkJcB70GwCUAgAAAA==.Holenmymuff:BAAALgADCgUJBQAAAA==.Hollinar:BAABLgAECn8YAAIJAAkJxxLtcADyAQAJAAkJxxLtcADyAQAAAA==.Holyfaux:BAAALgADCgYJBgAAAA==.Holysteel:BAAALgAECgIJAwAAAA==.Hondoe:BAAALgAECgQJCAAAAA==.Hordecow:BAAALgAECgEJAQABLgAFFAEJAgAEAAAAAA==.Hornhelm:BAAALgAECgIJAgAAAA==.',
Hu='Huntoor:BAAALgAECgEJAQABLgAECgYJBgAEAAAAAA==.',
Ic='Icemark:BAACLgAFFH8FAAIJAAMJfxI1KwAJAQAJAAMJfxI1KwAJAQAuAAQKfx8AAgkABwkGHShXADMCAAkABwkGHShXADMCAAAA.',
Ih='Ihavecookies:BAAALgAECgQJBQAAAA==.',
Ij='Ijur:BAAALgAECgQJCAABLgAECgUJBgAEAAAAAA==.',
Ik='Ikayro:BAABLgAECn8cAAIJAAgJdx2AKgDJAgAJAAgJdx2AKgDJAgAAAA==.',
Il='Ilostmyphone:BAAALgAECgEJAQAAAA==.Ilovemysword:BAAALgAECgUJCQAAAA==.Iluvatar:BAABLgAECn8eAAMHAAgJiiHCDACAAgAHAAgJiiHCDACAAgAGAAIJwxJgXAB2AAABLgAFFAEJAQAEAAAAAA==.',
Im='Imagine:BAABLgAECn8WAAQUAAkJaRAJDgDoAQAUAAkJaRAJDgDoAQATAAYJFganPgDwAAAVAAEJtgKCKQAhAAAAAA==.',
In='Infoxticated:BAAALgAECgEJAQAAAA==.',
Ir='Iratedemon:BAAALgAECgMJBAABLgAECgMJAwAEAAAAAA==.Irateknight:BAAALgAECgMJAwAAAA==.Irely:BAAALgAECgIJAgAAAA==.',
Ja='Jadedways:BAAALgAECgEJAgAAAA==.Jasmirangel:BAACLgAFFH8PAAIZAAMJNCBPKAAWAQAZAAMJNCBPKAAWAQAuAAQKf0QAAhkACAkDJZgGAEcDABkACAkDJZgGAEcDAAAA.',
Je='Jede:BAAALgADCgMJAwAAAA==.',
Jo='Joshallen:BAAALgADCgcJBwAAAA==.',
Ju='Juka:BAABLgAECn8UAAINAAkJGQf7UwBXAQANAAkJGQf7UwBXAQAAAA==.Jukks:BAAALgAECgcJEAAAAA==.Juno:BAAALgADCgkJEwAAAA==.Justsumfoo:BAAALgAECgIJBAAAAA==.',
Ka='Kano:BAACLgAFFH8XAAMCAAUJYRnKGwCAAQACAAUJYRnKGwCAAQADAAEJKhS4MABCAAAuAAQKfy4AAgIACQmII5kJAAMDAAIACQmII5kJAAMDAAAA.Karper:BAAALgAECgEJAQAAAA==.Katarm:BAABLgAECn8UAAMLAAkJcgi2IwAHAQALAAkJagS2IwAHAQAdAAUJNgxKPgDDAAAAAA==.Katarru:BAAALgAECgYJDQAAAA==.Kataru:BAAALgADCgIJAgAAAA==.',
Kh='Khory:BAAALgAFFAIJBAAAAA==.',
Ki='Kirito:BAAALgADCgYJBgAAAA==.',
Kk='Kkiinnoopp:BAABLgAECn8jAAMCAAgJiBYfcABWAQADAAYJVhYrFQB1AQACAAcJSxQfcABWAQAAAA==.',
Ko='Korgigor:BAAALgAECgQJBwAAAA==.Kovu:BAAALgAECgcJEgAAAA==.',
Kr='Krisanthemum:BAAALgADCgcJCwAAAA==.Krystrasz:BAAALgAECgQJCwAAAA==.',
Kt='Kt:BAAALgADCgIJAgABLgAECgQJBAAEAAAAAA==.Ktrogue:BAAALgAECgQJBAAAAA==.',
Ku='Kuailiang:BAAALgAECgcJCQAAAA==.Kuraihikari:BAAALgAFFAEJAQAAAA==.Kustaa:BAAALgADCgkJCgABLgAECggJJQAiAJMYAA==.',
La='Ladezar:BAAALgADCgcJDQAAAA==.Laissen:BAAALgAECgYJCAAAAA==.Lapsung:BAAALgAECgIJBAABLgAECgcJFQAKAAUWAA==.Lattemocha:BAABLgAECn8lAAMZAAgJNR+eMADpAQAZAAYJLR2eMADpAQAjAAgJghPQJQCSAQAAAA==.',
Le='Lenden:BAAALgAECgMJBgAAAA==.Leprechaun:BAAALgADCgcJCQAAAA==.Leví:BAAALgADCgUJBQAAAA==.Leylas:BAAALgAECgEJAgAAAA==.',
Li='Lighthoove:BAAALgAECgcJBwAAAA==.Lightswìtch:BAAALgADCgEJAQAAAA==.Lilliaz:BAAALgAECgYJBwAAAA==.Linianna:BAAALgAECgYJEgAAAA==.Liriel:BAAALgAECgcJBwAAAA==.',
Lu='Ludlow:BAABLgAECn8dAAICAAgJEgrieABDAQACAAgJEgrieABDAQAAAA==.Lunastra:BAACLgAFFH8JAAIJAAQJ7A8IfwDVAAAJAAQJ7A8IfwDVAAAuAAQKfyYAAgkACAlOHNFGAAECAAkACAlOHNFGAAECAAEuAAUUAgkEAAQAAAAA.Luneztoprime:BAAALgAECgYJCgAAAA==.',
Ly='Lydarra:BAAALgAECgQJBwABLgAECgYJFQAYAFAZAA==.Lyiann:BAAALgADCggJEgAAAA==.Lyákadion:BAAALgAECgEJAQAAAA==.',
['Lâ']='Lâdypriest:BAAALgADCgUJBQAAAA==.',
Ma='Mafi:BAABLgAECn8WAAICAAcJ/RlPVwCTAQACAAcJ/RlPVwCTAQAAAA==.Maggore:BAAALgAECgIJBgAAAA==.Magikiwiks:BAAALgAECgEJAQAAAA==.Magsdk:BAAALgAFFAIJAgABLgAFFAcJIQATAAceAA==.Mainlander:BAAALgAECgMJAwAAAA==.Malbogea:BAAALgAECgEJAgAAAA==.Malusmittens:BAAALgAECgQJBQABLgAFFAQJFQACACojAA==.Mantonso:BAABLgAECn8xAAIYAAkJDSCWDACbAgAYAAkJDSCWDACbAgAAAA==.Matt:BAACLgAFFH8JAAIZAAQJMQvIMQDlAAAZAAQJMQvIMQDlAAAuAAQKfyoAAhkACQkiHa8MAPACABkACQkiHa8MAPACAAAA.',
Me='Meddicus:BAAALgAECgUJCAAAAA==.Meechydarko:BAAALgAECgUJBQABLgAECgkJMwADALMfAA==.Megalomaniä:BAAALgADCgYJBgABLgAECgcJHgAeAKYYAA==.Megorice:BAAALgAFFAIJAgAAAA==.Megå:BAABLgAECn8eAAMeAAcJphjOFQAKAQARAAYJmBdFcgBQAQAeAAUJmBvOFQAKAQAAAA==.Mewtwô:BAAALgAECgYJBwAAAA==.',
Mi='Microbrew:BAAALgAECgMJBQAAAA==.Miezra:BAAALgAECgYJCAAAAA==.Mikah:BAAALgAECgYJDwAAAA==.',
Mo='Modayus:BAAALgAECgEJAQAAAA==.Mojomittens:BAACLgAFFH8VAAICAAQJKiPoGQCIAQACAAQJKiPoGQCIAQAuAAQKfyIAAwIABwlEJHYmAD0CAAIABwlEJHYmAD0CAAgABQnAFqRAAFcBAAAA.Monstermime:BAAALgAECgIJAgABLgAECggJCwAEAAAAAA==.Monstroqt:BAAALgADCgQJBAAAAA==.Moobiez:BAAALgADCgIJAgAAAA==.Morøs:BAAALgADCgYJBgAAAA==.Moxx:BAABLgAECn8ZAAIkAAkJtw6CMAA5AQAkAAkJtw6CMAA5AQAAAA==.',
Mu='Muffers:BAABLgAECn83AAIkAAkJAxORGADjAQAkAAkJAxORGADjAQAAAA==.Muffpuff:BAAALgAECgQJBQAAAA==.Mutige:BAAALgADCgEJAQAAAA==.',
My='Mylotus:BAAALgAECgQJBQAAAA==.',
Na='Napkuntt:BAAALgAECgEJAQAAAA==.Napokin:BAAALgAFFAEJAgAAAA==.Napshade:BAABLgAECn8cAAMHAAcJyhsnKwBzAQAHAAYJ/xwnKwBzAQAKAAYJEhApRgDCAAABLgAFFAEJAgAEAAAAAA==.Natsuu:BAAALgAECgcJDAAAAA==.',
Nb='Nbayoungboyy:BAAALgADCgYJBgABLgAFFAYJHgACAIYhAA==.',
Ne='Necroticoath:BAAALgAECgIJBgABLgAFFAIJBAAEAAAAAA==.Neven:BAAALgAECgIJAgAAAA==.',
Ni='Nightor:BAAALgAECgEJAQAAAA==.Nikodemos:BAAALgAFFAcJGAAAAQ==.Nivahoof:BAAALgADCgEJAQAAAA==.',
No='Noc:BAABLgAECn8nAAMRAAgJVBhhOwDnAQARAAgJVBhhOwDnAQASAAUJNA+JLQAHAQABLgAECgkJMwARAAkhAA==.Nomemage:BAAALgADCgEJAQAAAA==.',
Ob='Obe:BAAALgAFFAIJAgAAAA==.Obsidiangel:BAAALgADCggJEAAAAA==.',
Oh='Ohface:BAAALgAECgQJBwABLgAECgIJBgAEAAAAAA==.',
Oo='Oowu:BAAALgADCgkJDQAAAA==.',
Or='Oran:BAABLgAECn8YAAIFAAgJaxgdTwDQAQAFAAgJaxgdTwDQAQAAAA==.Orctrax:BAABLgAECn8aAAMCAAgJVREWcABWAQACAAgJVREWcABWAQAIAAEJBALAjgAsAAAAAA==.Oricale:BAAALgAECgYJBgAAAA==.',
Os='Osheat:BAACLgAFFH8FAAIMAAMJJg1CnQDOAAAMAAMJJg1CnQDOAAAuAAQKfyMAAgwACQndH6UmAGECAAwACQndH6UmAGECAAAA.Osmodeus:BAAALgAECgUJCAAAAA==.',
Ou='Outplay:BAAALgADCgUJBQAAAA==.',
Ox='Oxheart:BAAALgAECgEJAQAAAA==.',
Pa='Paltis:BAAALgAECgQJBQAAAA==.Paltonso:BAAALgADCgkJCQAAAA==.Pandaari:BAABLgAECn8WAAIHAAgJFASnRwDoAAAHAAgJFASnRwDoAAAAAA==.Papaschristo:BAAALgADCgUJBQAAAA==.Papasdiablo:BAAALgAECgEJAgAAAA==.Parprapa:BAAALgADCgMJAwAAAA==.',
Pe='Penicillin:BAAALgAECgMJAwAAAA==.Persimmon:BAACLgAFFH8OAAIiAAQJVxwvGQBNAQAiAAQJVxwvGQBNAQAuAAQKfyAAAiIABwmTF04pALoBACIABwmTF04pALoBAAAA.Peyton:BAAALgAECgUJBwAAAA==.',
Ph='Philip:BAAALgADCgcJDAAAAA==.Phyrie:BAAALgAECgUJDwABLgAECgYJFQAYAFAZAA==.',
Pi='Pittpete:BAAALgAECgEJAQAAAA==.',
Pl='Plaguepapi:BAAALgAFFAEJAQAAAA==.',
Po='Pollocaotico:BAAALgAFFAIJAgAAAA==.',
Ps='Psythera:BAAALgAECgIJBAABLgAECggJIgAHAPIcAA==.Psythern:BAAALgADCgYJCQABLgAECggJIgAHAPIcAA==.',
Pu='Punkybrewstr:BAABLgAECn8xAAMBAAgJjhb0IgCLAQABAAcJURb0IgCLAQAkAAgJswr0MABjAQAAAA==.Pureshock:BAAALgAECggJDQAAAA==.Purpderf:BAAALgAFFAEJAQAAAA==.',
Pw='Pwnstar:BAAALgAECgQJCAAAAA==.',
Py='Pykei:BAAALgAECgMJAwAAAA==.Pyrrah:BAAALgAECgEJAQABLgAECgkJJAAGAEIdAA==.Pyrri:BAABLgAECn8kAAQGAAkJQh1wEwA6AgAGAAgJaB5wEwA6AgAKAAQJ4RXjUQDwAAAHAAMJdRTHVQCxAAAAAA==.Pyrria:BAABLgAECn8UAAMNAAkJvyTyBQBJAwANAAgJeyTyBQBJAwAOAAUJBhQ6QwAYAQABLgAECgkJJAAGAEIdAA==.Pyrris:BAAALgAECgMJAwABLgAECgkJJAAGAEIdAA==.',
Pz='Pznt:BAAALgAECgEJAQAAAA==.',
['Pé']='Péyton:BAAALgAECgcJDQAAAA==.',
['Pì']='Pì:BAAALgADCgEJAgAAAA==.',
['Pô']='Pôws:BAAALgAECgIJAwAAAA==.',
Qu='Quantonbomb:BAABLgAECn8UAAIZAAkJehnoEgCuAgAZAAkJehnoEgCuAgAAAA==.Quezera:BAAALgADCgYJBgAAAA==.',
Ra='Rabuf:BAABLgAECn8lAAMiAAgJkxj6FgBIAgAiAAgJkxj6FgBIAgAFAAYJ6QxsvwAIAQAAAA==.Raccoonadin:BAAALgADCgEJAQAAAA==.Radha:BAAALgAECgIJAgABLgAFFAUJEwAMAPAgAA==.Ragingwater:BAAALgAECgYJEAAAAA==.Ranadheer:BAAALgAFFAEJAQAAAA==.Raspaigus:BAAALgAECgQJBAAAAA==.Ratfu:BAABLgAECn8UAAIkAAYJOQX/RwD1AAAkAAYJOQX/RwD1AAAAAA==.Raudson:BAABLgAECn8UAAIlAAkJDCJUAgATAwAlAAkJDCJUAgATAwAAAA==.',
Re='Redizle:BAACLgAFFH8bAAIGAAcJRhQ+DQAjAgAGAAcJRhQ+DQAjAgAuAAQKfycABAoACAnxHBkoAK8BAAYACAn7FuUbALcBAAoABgkyHBkoAK8BAAcABQnSEug2ADYBAAAA.Reginrune:BAAALgAECgkJEwAAAA==.Resonance:BAABLgAECn8WAAMOAAcJHBYrOABJAQAOAAcJ9RUrOABJAQAfAAMJZwykIwCeAAAAAA==.Restroll:BAAALgADCgUJBQAAAA==.',
Rh='Rhaigar:BAAALgAECgUJCQAAAA==.Rhónatar:BAAALgADCgQJBAAAAA==.',
Ri='Righteouscow:BAAALgAECgEJAQAAAA==.',
Ro='Rohdoog:BAABLgAECn84AAITAAkJoRccEwA/AgATAAkJoRccEwA/AgAAAA==.Roundabugman:BAACLgAFFH8MAAIOAAMJrh3AKADrAAAOAAMJrh3AKADrAAAuAAQKfycAAw4ACAmSHh0fAN4BAA4ACAmSHh0fAN4BAA0AAwmnFOF3ALIAAAAA.',
Rr='Rr:BAABLgAFFH8JAAMhAAMJpAGoDQB1AAAhAAMJpAGoDQB1AAAmAAMJfgDtNABqAAAAAA==.',
Ru='Runedyu:BAAALgAECgYJEQAAAA==.',
Ry='Ryanno:BAACLgAFFH8LAAICAAMJpxvGSAAIAQACAAMJpxvGSAAIAQAuAAQKfyoAAgIACQkwIEQbAHcCAAIACQkwIEQbAHcCAAAA.Ryannoo:BAAALgAECgYJBQAAAA==.Ryujinhalco:BAAALgADCgMJAwAAAA==.',
Sa='Sabim:BAAALgAECgEJAQAAAA==.Sahomi:BAACLgAFFH8MAAIGAAQJhw2LJQAFAQAGAAQJhw2LJQAFAQAuAAQKfyQAAwYACQlNCXkoAFIBAAYACQlNCXkoAFIBAAoAAglNBZR3AEwAAAAA.Salana:BAAALgADCgcJBwAAAA==.Samwise:BAAALgAECgYJCAAAAA==.Sarai:BAAALgADCgEJAQAAAA==.Sarcini:BAABLgAECn8uAAIlAAkJXhtOBwBfAgAlAAkJXhtOBwBfAgAAAA==.Satrina:BAACLgAFFH8NAAIMAAQJqRWWVAA9AQAMAAQJqRWWVAA9AQAuAAQKfyQAAgwACAmrIvIwADQCAAwACAmrIvIwADQCAAAA.Savvy:BAAALgAECgUJBQABLgAECgYJBgAEAAAAAA==.',
Sc='Scrappy:BAAALgAECgEJAQAAAA==.',
Se='Sedna:BAAALgADCgYJBgABLgAECgYJCAAEAAAAAA==.Selanthe:BAAALgAECgQJBgAAAA==.Seruk:BAAALgAECgEJBAAAAA==.Sevaronk:BAAALgAECgEJAQAAAA==.Seventhghost:BAEALgAECgIJAgABLgAFFAQJCwAHADEQAA==.',
Sh='Shadowstorme:BAAALgAECgIJBQAAAA==.Shamander:BAABLgAECn8eAAINAAkJQxjzIAA+AgANAAkJQxjzIAA+AgAAAA==.Shamsham:BAAALgADCgcJDAAAAA==.Sharky:BAAALgADCgQJBAAAAA==.Shocka:BAAALgADCgcJCQAAAA==.Shokanki:BAAALgAECgYJCwAAAA==.',
Si='Sicara:BAABLgAECn8uAAIXAAkJQhYUPQDJAQAXAAkJQhYUPQDJAQAAAA==.Silentmage:BAAALgADCgcJCAAAAA==.Silentslock:BAAALgADCgYJBQAAAA==.Sillylilguy:BAACLgAFFH8JAAIfAAMJnBE3AwADAQAfAAMJnBE3AwADAQAuAAQKfxgAAh8ACAmEH+8EAMECAB8ACAmEH+8EAMECAAAA.Sinestro:BAAALgAECgMJAwAAAA==.Sivrogar:BAAALgAECgMJAwAAAA==.',
Sl='Slaik:BAAALgAECgUJDgAAAA==.Slander:BAACLgAFFH8YAAMMAAUJ0h6fTgBHAQAMAAUJ0h6fTgBHAQAbAAEJAAARWAAAAAAuAAQKfzkAAgwACQmQIcAcAJMCAAwACQmQIcAcAJMCAAAA.',
So='Solemnograve:BAAALgAECgIJAgAAAA==.Somazugzug:BAACLgAFFH8LAAINAAQJhhpxJwAyAQANAAQJhhpxJwAyAQAuAAQKfyUAAg0ACQm5GV8uANABAA0ACQm5GV8uANABAAAA.Sothren:BAAALgAECgQJBQABLgADCgkJCQAEAAAAAA==.',
Sp='Spacedguy:BAAALgADCgMJAwAAAA==.Spry:BAAALgAECgEJAQAAAA==.',
St='Staccato:BAAALgAECgEJAQAAAA==.Stanleyy:BAAALgAFFAEJAgABLgAFFAIJBAAEAAAAAA==.Starlight:BAAALgAECgIJAgAAAA==.Stepbrother:BAAALgAFFAEJAQABLgAECgkJMwADALMfAA==.',
Su='Sugar:BAABLgAECn8nAAMNAAkJ5RFBSQB+AQANAAkJ5RFBSQB+AQAOAAUJtw6oVgDrAAAAAA==.Sugars:BAAALgAECgUJBAAAAA==.Sulin:BAAALgADCgUJBwAAAA==.Sungôd:BAAALgADCgEJAQABLgAECgkJMQABAI4WAA==.',
Sw='Swonks:BAAALgAECgMJAwAAAA==.Swyper:BAAALgAECgMJAwAAAA==.',
Sy='Synicism:BAAALgADCgcJDQAAAA==.',
Ta='Taintbubble:BAAALgAECgMJBQAAAA==.Tanktommy:BAAALgAECgUJCAABLgAFFAQJDwAMABsbAA==.Tarnished:BAAALgADCgcJCAAAAA==.Tarquitus:BAACLgAFFH8TAAMXAAcJhw5zKQBsAQAXAAYJIxFzKQBsAQAQAAIJeAS+CgCTAAAuAAQKfzwAAxcACAmXIG8bAGYCABcACAnWH28bAGYCABAACAm8F0sRAFUCAAAA.Tattoosguy:BAAALgADCgEJAQAAAA==.',
Te='Teef:BAABLgAECn8cAAImAAcJFxVBIgB1AQAmAAcJFxVBIgB1AQAAAA==.Tellan:BAAALgADCgcJBwAAAA==.',
Th='Thanatös:BAABLgAECn8cAAMJAAgJbBbsYwCxAQAJAAgJbBbsYwCxAQAnAAQJrxRDDQD1AAAAAA==.Tharros:BAAALgAECgcJDQAAAA==.Thedarkkness:BAABLgAECn8lAAIbAAgJuhm2GQCHAQAbAAgJuhm2GQCHAQAAAA==.Thorin:BAAALgAECgQJBAABLgAFFAIJBAAEAAAAAA==.Thrasher:BAAALgAECgEJAwAAAA==.',
Ti='Tidalwave:BAACLgAFFH8OAAINAAQJAh5kIABYAQANAAQJAh5kIABYAQAuAAQKfy0AAw0ACQnFGUofAEoCAA0ACQnFGUofAEoCAA4AAgltC+SjACoAAAAA.Tidus:BAAALgAECgYJEQAAAA==.Tinytotem:BAAALgAECgEJBAAAAA==.Tissue:BAABLgAECn8XAAIQAAcJCArULABjAQAQAAcJCArULABjAQAAAA==.',
To='Toasted:BAAALgADCgYJCQABLgAECgMJAwAEAAAAAA==.Tobibi:BAAALgAECgYJBwABLgAFFAIJBAAEAAAAAA==.Todo:BAAALgADCgQJBAAAAA==.Tolip:BAABLgAECn8rAAMZAAgJUQgrdgD1AAAZAAYJgAgrdgD1AAAjAAgJSgRcRQDqAAABLgAFFAEJAQAEAAAAAA==.Tolipally:BAAALgAFFAEJAQAAAA==.Tolipicious:BAAALgADCgUJCQABLgAFFAEJAQAEAAAAAA==.',
Tr='Trauts:BAAALgAECgQJCAAAAA==.Treeadin:BAABLgAECn8lAAIlAAgJ1RD/GgA0AQAlAAgJ1RD/GgA0AQAAAA==.Trollcula:BAAALgAECggJDgABLgAFFAQJBwACAKQKAA==.Truthwithin:BAAALgAECgUJEwAAAA==.',
Ts='Tsarrubus:BAABLgAECn8hAAIQAAkJcwlrIgBUAQAQAAkJcwlrIgBUAQAAAA==.',
Tu='Tula:BAAALgAECgUJCwAAAA==.Tusck:BAAALgAECgYJEAAAAA==.',
Tw='Twingert:BAAALgAECgEJAQAAAA==.Twitch:BAAALgAECgYJEwAAAA==.',
Ty='Tyedyemess:BAAALgAECgMJAwAAAA==.Tyledridal:BAAALgAECgMJAwAAAA==.',
['Tà']='Tàylor:BAABLgAECn8cAAIiAAkJOQu1OgCPAQAiAAkJOQu1OgCPAQAAAA==.',
Ub='Ubbaa:BAAALgAECgEJAQAAAA==.',
Ul='Ulghar:BAABLgAECn8rAAIYAAkJNCV+AQBmAwAYAAkJNCV+AQBmAwAAAA==.',
Ur='Ursock:BAAALgAECggJDgAAAA==.',
Uw='Uwuhshake:BAABLgAECn8tAAMZAAkJ7SF8BABtAwAZAAkJ7SF8BABtAwAjAAEJqRs9dQBRAAAAAA==.',
Va='Valdria:BAAALgAECgMJAwAAAA==.Valssien:BAAALgADCgkJCQAAAA==.Vanaria:BAAALgAECgQJBAAAAA==.Vanbrook:BAAALgAECgQJAgAAAA==.Vanden:BAAALgAECgYJDAAAAA==.Vanrion:BAAALgAFFAIJAwAAAA==.Varrodd:BAAALgAECgEJAQAAAA==.Vastextent:BAAALgADCgMJBAAAAA==.',
Ve='Velcro:BAAALgAECgYJEgAAAA==.Velsera:BAAALgAECgYJCAAAAA==.Velvet:BAAALgADCgQJCAAAAA==.Velyn:BAAALgAECgcJDwAAAA==.Velynara:BAAALgADCgIJAgABLgAECgYJCAAEAAAAAA==.Vengefulcry:BAAALgAECgMJAwAAAA==.Vengefül:BAAALgADCgYJCAAAAA==.Vexara:BAAALgAECgQJBAAAAA==.',
Wa='Wanaaga:BAAALgAECggJDgAAAA==.',
We='Wedge:BAAALgAECgEJAQAAAA==.',
Wh='Whohaveaggro:BAAALgAECgEJAwAAAA==.',
Wi='Widestripe:BAAALgADCgYJBgAAAA==.Wilmington:BAAALgADCgIJAgAAAA==.Wino:BAABLgAECn8VAAMmAAgJlxAjHgCZAQAmAAgJdhAjHgCZAQAgAAEJTxFAJAA8AAAAAA==.Wiqui:BAAALgAECgEJBAAAAA==.Witulow:BAABLgAECn8pAAMWAAgJ3w1rSwAoAQAWAAcJog9rSwAoAQABAAgJrATnPQD8AAAAAA==.',
Wo='Wolfadin:BAACLgAFFH8JAAIFAAQJAwV+HAC9AAAFAAQJAwV+HAC9AAAuAAQKfzoAAgUACQmHGnkiAHMCAAUACQmHGnkiAHMCAAAA.Woopac:BAABLgAECn8iAAIYAAgJihwvHAAHAgAYAAgJihwvHAAHAgAAAA==.',
Wu='Wulfharth:BAAALgAECgYJDwAAAA==.',
Xe='Xenophics:BAACLgAFFH8aAAMFAAYJThNXIgBrAQAFAAYJThNXIgBrAQAiAAEJXwAJTQAkAAAuAAQKf0IABAUACAmVJA4WALYCAAUACAmVJA4WALYCACIABAl7EEJUANwAACUAAQnKBq1RACUAAAEuAAUUBAkOAAkAxQoA.Xenophicstwo:BAACLgAFFH8OAAIJAAQJxQpbYgAdAQAJAAQJxQpbYgAdAQAuAAQKfyYAAgkABglMG5l6AH0BAAkABglMG5l6AH0BAAAA.',
Xu='Xuen:BAABLgAECn8VAAIkAAcJ/hPnKQBhAQAkAAcJ/hPnKQBhAQABLgAFFAMJDQAFABAkAA==.',
Ya='Yajsooblwj:BAAALgADCgMJAwAAAA==.',
Za='Zal:BAACLgAFFH8FAAIiAAMJrhsnKADbAAAiAAMJrhsnKADbAAAuAAQKfyEABCIACQlPGaEiAOYBACIACQlPGaEiAOYBAAUABwlsFi6TAEIBACUAAgkNFWQ0AHYAAAAA.Zanor:BAAALgAECgIJAgAAAA==.Zarranora:BAAALgAECgEJAQAAAA==.Zatannå:BAAALgADCgYJCQAAAA==.',
Ze='Zect:BAABLgAECn8sAAIJAAkJURNkRwD/AQAJAAkJURNkRwD/AQAAAA==.Zenshin:BAAALgAECgIJAgAAAA==.Zentaur:BAAALgAECggJCwAAAA==.Zetzu:BAABLgAECn8WAAIYAAgJLRimIwDRAQAYAAgJLRimIwDRAQAAAA==.',
Zi='Zitfrlt:BAAALgAECgMJBQABLgAECggJGQAMAGkSAA==.',
['Ål']='Ålucard:BAABLgAECn8fAAMHAAgJVhj4HQDOAQAHAAgJVhj4HQDOAQAGAAYJjROKKACDAQAAAA==.',
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
