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

local lookup = {'Monk-Brewmaster','Hunter-BeastMastery','Hunter-Survival','Unknown-Unknown','Paladin-Retribution','Priest-Discipline','Priest-Shadow','Hunter-Marksmanship','Mage-Frost','Warrior-Protection','Priest-Holy','Shaman-Restoration','Shaman-Elemental','Druid-Feral','DemonHunter-Havoc','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Monk-Mistweaver','DemonHunter-Devourer','Warrior-Fury','Druid-Restoration','DeathKnight-Frost','DeathKnight-Blood','Druid-Guardian','Warrior-Arms','Warlock-Affliction','Shaman-Enhancement','Rogue-Assassination','Rogue-Outlaw','Paladin-Holy','Druid-Balance','Monk-Windwalker','Paladin-Protection','Rogue-Subtlety','Mage-Arcane',}
local provider = {region='US',realm='Wildhammer',name='US',type='weekly',zone=46,date='2026-05-31',data={Aa='Aayrawn:BAAALgAECgcJBwAAAA==.',
Ab='Abaddonaxx:BAAALgADCgYJBgAAAA==.',
Ac='Aceshaman:BAAALgAECgQJBAAAAA==.Acesmash:BAABLgAECn8lAAIBAAkJGCJnBQDcAgABAAkJGCJnBQDcAgAAAA==.Ackrenezoth:BAAALgAECgQJBwAAAA==.',
Ad='Adymisk:BAAALgADCgEJAQAAAA==.',
Ag='Agorot:BAAALgAFFAEJAQAAAA==.',
Ak='Akadion:BAAALgADCgcJCgAAAA==.Akatali:BAAALgAECgQJBgAAAA==.',
Al='Aldannia:BAABLgAECn8VAAMCAAcJ4A/QVwBhAQACAAcJ8wzQVwBhAQADAAYJ7gwPMAAZAQAAAA==.Alextros:BAEALgAECgYJEQABLgAECgcJCgAEAAAAAA==.Alloren:BAAALgAECgQJBgAAAA==.Almond:BAAALgAECgEJAgAAAA==.',
Am='Amaranthe:BAAALgAECgEJAQAAAA==.Amrax:BAABLgAECn8vAAIFAAkJjxPwQQDpAQAFAAkJjxPwQQDpAQAAAA==.Amynre:BAABLgAECn8aAAMGAAkJKRCfFQD5AQAGAAkJKRCfFQD5AQAHAAMJ6w33VABvAAAAAA==.',
An='Anarsa:BAAALgAECgUJCgAAAA==.Angstyboi:BAAALgAECgQJBAAAAA==.',
Aq='Aquabat:BAACLgAFFH8RAAQDAAQJ8hhaFwD/AAADAAMJdBdaFwD/AAACAAMJ0BdhYwCkAAAIAAEJ8xvxJABVAAAuAAQKfyQABAMACAmyIc4LAFkCAAMACAmvH84LAFkCAAgABwmrH38bAEwCAAIABQlwJRgoABgCAAAA.',
Ar='Arvyy:BAABLgAECn8mAAIJAAkJWBrCJwBnAgAJAAkJWBrCJwBnAgAAAA==.',
As='Ashbringer:BAACLgAFFH8KAAIFAAMJECSNMQAzAQAFAAMJECSNMQAzAQAuAAQKfyYAAgUACQlgI38SAMECAAUACQlgI38SAMECAAAA.',
At='Atria:BAACLgAFFH8FAAIJAAQJKwidoABxAAAJAAQJKwidoABxAAAuAAQKfyMAAgkACAmgFbpJAOgBAAkACAmgFbpJAOgBAAAA.Attia:BAAALgAECgcJEwAAAA==.',
Av='Avaris:BAAALgADCgIJAgAAAA==.Avatarbambi:BAAALgADCgUJAgAAAA==.',
Ax='Axtar:BAABLgAECn8lAAIKAAkJ6RgmDgDxAQAKAAkJ6RgmDgDxAQAAAA==.',
Ay='Ayyitzrich:BAAALgADCgQJBAAAAA==.',
Ba='Babarazzar:BAAALgADCgYJBgAAAA==.Baladoria:BAACLgAFFH8HAAILAAQJ5wp4FwDiAAALAAQJ5wp4FwDiAAAuAAQKfzUAAgsACQlbISEEADcDAAsACQlbISEEADcDAAAA.Baldkrank:BAAALgAECgEJAQAAAA==.Bananabowman:BAAALgAECgEJAgAAAA==.Barrels:BAABLgAECn8lAAMCAAkJux7OHABlAgACAAgJLx3OHABlAgADAAkJnBWOEQATAgAAAA==.Bartab:BAABLgAECn84AAMMAAkJyR2gCwDrAgAMAAkJyR2gCwDrAgANAAEJEwPaqgAfAAABLgAECgkJPgAOADEhAA==.Baruku:BAAALgAFFAEJAQAAAA==.Bashfulwaltz:BAAALgAECgcJBwAAAA==.Bastadi:BAAALgAFFAIJAwAAAA==.',
Be='Bearemy:BAAALgAECgcJBwAAAA==.Beastling:BAAALgAECgYJDwAAAA==.Beau:BAACLgAFFH8HAAIPAAMJ8yIbCwAxAQAPAAMJ8yIbCwAxAQAuAAQKfzQAAg8ACQnMJL8CAB8DAA8ACQnMJL8CAB8DAAAA.Beauchi:BAAALgAECgUJBQABLgAFFAMJBwAPAPMiAA==.Beauwi:BAAALgAECgQJBgABLgAFFAMJBwAPAPMiAA==.Beldin:BAAALgAECgEJAQAAAA==.',
Bi='Bigshekels:BAAALgAECgEJAQAAAA==.Bigulsworth:BAAALgADCgcJCAAAAA==.',
Bl='Blackadder:BAAALgAECgcJEgAAAA==.Blawkk:BAAALgAECgYJBgAAAA==.Blenton:BAAALgAECgEJAQAAAA==.Bloodussy:BAAALgADCgUJBQAAAA==.Bluck:BAAALgADCgcJEQAAAA==.Blueeyesdrag:BAAALgADCgEJAQAAAA==.Blueombre:BAAALgAECgEJAQAAAA==.',
Bo='Boing:BAAALgAECgUJCgAAAA==.Bombur:BAACLgAFFH8GAAIQAAMJVxbZXgDqAAAQAAMJVxbZXgDqAAAuAAQKfy8AAxAACQlSHPAgAFQCABAACQlSHPAgAFQCABEAAQkAAB1kAEYAAAAA.Bosstradamus:BAAALgAFFAEJAQABLgAFFAIJAgAEAAAAAA==.Boston:BAAALgAECggJEwAAAA==.Bottles:BAAALgAFFAIJBAAAAA==.',
Br='Bratva:BAAALgAECgcJAwAAAA==.',
Bu='Bubagony:BAAALgADCgQJBAABLgAFFAQJEQASAPAgAA==.Bubbells:BAAALgADCgEJAQAAAA==.Bullmedic:BAAALgADCgYJBgAAAA==.Burakku:BAABLgAECn8VAAQTAAcJEhnTGgDzAQATAAcJEhnTGgDzAQAUAAUJJwgCMQDpAAAVAAEJAAC0PgA1AAABLgAFFAUJBQAWAMwVAA==.Burguerkiing:BAAALgADCgMJAwAAAA==.Burph:BAAALgADCggJCAAAAA==.Buttonsmash:BAAALgAECgcJEAABLgAFFAcJHAAUAK0RAA==.Buzzkill:BAAALgAECgIJAgAAAA==.',
['Bâ']='Bâbyrage:BAAALgADCgcJDwAAAA==.',
Ca='Cairen:BAABLgAECn8kAAIXAAkJMh6KHwBFAgAXAAkJMh6KHwBFAgAAAA==.Calzraxx:BAAALgAECgkJEwAAAA==.Carstaller:BAAALgAECgQJBAAAAA==.Cartons:BAAALgAECggJDQAAAA==.',
Cc='Ccaan:BAAALgAECgkJEQAAAA==.Ccian:BAAALgAECgQJBAAAAA==.',
Ce='Celinn:BAABLgAECn82AAMLAAkJDx22CgCoAgALAAkJDx22CgCoAgAGAAYJvhLEKQBkAQAAAA==.',
Ch='Chadgar:BAAALgADCgUJBwAAAA==.Chalupacabra:BAAALgADCgIJAgAAAA==.Chappie:BAAALgAECgEJAQABLgAFFAQJEQADAPIYAA==.Charliek:BAABLgAFFH8FAAIYAAMJIQN1NQCpAAAYAAMJIQN1NQCpAAAAAA==.Cherches:BAAALgADCgEJAQAAAA==.Childish:BAAALgAECgYJDQAAAA==.Chimalma:BAAALgAFFAIJBAAAAA==.Chiqui:BAAALgAECgEJAgAAAA==.',
Cl='Clarabow:BAAALgAFFAIJAwAAAA==.Closure:BAABLgAECn8YAAIZAAkJJSPbDADWAgAZAAkJJSPbDADWAgAAAA==.Cloudsx:BAAALgADCgMJAwAAAA==.',
Co='Coatlicue:BAABLgAECn8UAAMLAAkJFx+hEQBVAgALAAgJRSGhEQBVAgAHAAUJZBTFMQBXAQABLgAFFAIJBAAEAAAAAA==.Coby:BAABLgAECn8VAAIWAAgJqSSsBwAIAwAWAAgJqSSsBwAIAwAAAA==.Coffins:BAAALgAECgYJEQABLgAECggJDQAEAAAAAA==.Covell:BAAALgAECgUJBwAAAA==.',
Cr='Crates:BAAALgAECgUJCAABLgAECggJDQAEAAAAAA==.Crimsonmagic:BAAALgAECgEJAgAAAA==.Crosswalkk:BAAALgADCgMJAwAAAA==.Crygore:BAAALgAECgQJCgABLgAECgIJBgAEAAAAAA==.',
Cy='Cypherrellik:BAABLgAECn8cAAMPAAkJhRBWGwCEAQAPAAkJhRBWGwCEAQAXAAIJHgIg2QA9AAAAAA==.',
Da='Daktok:BAAALgADCgQJBAAAAA==.Damer:BAAALgADCgkJFgAAAA==.Damues:BAAALgAECggJDwAAAA==.Danaric:BAAALgAECgMJBgAAAA==.Dannyphentom:BAABLgAECn8XAAQSAAYJVxUEiABBAQASAAYJVxUEiABBAQAaAAMJxheAHgCpAAAbAAMJmA4qNgCQAAAAAA==.Dargar:BAAALgAECgEJAQAAAA==.Darkling:BAABLgAECn8dAAIPAAcJoB08EQD5AQAPAAcJoB08EQD5AQAAAA==.Darknyss:BAAALgADCggJCQAAAA==.',
De='Deathfortres:BAAALgAECgcJCwAAAA==.Dedeye:BAAALgADCgMJAwAAAA==.Dekumime:BAAALgAECggJCwAAAA==.Demandred:BAAALgAECgkJEwAAAA==.Demongrass:BAACLgAFFH8JAAIXAAQJexluMQA4AQAXAAQJexluMQA4AQAuAAQKfzIAAhcACAkyILYnABkCABcACAkyILYnABkCAAAA.Denaric:BAAALgAECgYJEAAAAA==.Derty:BAAALgAFFAEJAQAAAA==.',
Di='Diviñehymn:BAAALgAECgYJDgAAAA==.',
Do='Donet:BAAALgADCgEJAQAAAA==.Doppy:BAAALgADCgYJBgAAAA==.',
Dr='Dragondeezz:BAAALgAECgIJBAABLgAECgIJBgAEAAAAAA==.Dragondznuts:BAACLgAFFH8cAAIUAAcJrREjCAAIAgAUAAcJrREjCAAIAgAuAAQKfzwABBQACQluHl0FALECABQACQluHl0FALECABMAAgnoHitbAKQAABUAAglHCDYcAFsAAAAA.Draxtos:BAEALgAECgcJCgAAAA==.Dreamevil:BAAALgAECgkJBgAAAA==.Drroxso:BAAALgAECgQJBAAAAA==.Dríppy:BAAALgADCggJDQAAAA==.',
Ea='Eazybake:BAAALgADCgEJAQAAAA==.',
Ei='Eilerra:BAABLgAECn8pAAIJAAcJCyGjMwAzAgAJAAcJCyGjMwAzAgAAAA==.',
El='Elementony:BAABLgAECn85AAINAAkJpBB0IwD1AQANAAkJpBB0IwD1AQAAAA==.Elkdruid:BAABLgAECn8eAAMZAAgJxBCXTwBnAQAZAAgJxBCXTwBnAQAcAAEJQAzlNgAbAAABLgAFFAMJAwAEAAAAAA==.Elladamri:BAAALgAECgEJAQAAAA==.Elodi:BAAALgAECgEJAQAAAA==.',
Em='Emberglow:BAAALgAECgcJEgAAAA==.Empyrean:BAAALgADCgQJBQAAAA==.Emylia:BAAALgAECgcJEAAAAA==.',
Er='Eresdelor:BAABLgAECn8YAAMKAAkJlRP7FACNAQAKAAkJzhH7FACNAQAdAAQJLA4XJwC2AAAAAA==.Erre:BAABLgAECn8mAAIQAAkJ5h4LGQCDAgAQAAkJ5h4LGQCDAgAAAA==.',
Es='Esdeáth:BAAALgADCgEJAQAAAA==.Estia:BAAALgAECgMJBQABLgAFFAEJAQAEAAAAAA==.',
Ev='Evoktor:BAAALgAECgEJAQAAAA==.',
Fa='Facasdeath:BAAALgAECgYJDAAAAA==.Failure:BAEBLgAECn8cAAIDAAkJ+hQcDQD6AQADAAkJ+hQcDQD6AQABLgAFFAMJBwABAFEJAA==.Farmtoon:BAAALgAECgYJDQAAAA==.Fartbroknvis:BAAALgAECgIJAgAAAA==.',
Fe='Feardapain:BAACLgAFFH8RAAIQAAQJLxc2PAA4AQAQAAQJLxc2PAA4AQAuAAQKfz0ABBAACQk5IhUPAAEDABAACAk5IhUPAAEDABEAAQkAADFcAFoAAB4AAQkAAP84AAwAAAAA.Feardatpain:BAAALgAFFAEJAQAAAA==.Fellyn:BAAALgADCggJCwAAAA==.',
Ff='Ff:BAABLgAFFH8LAAIJAAMJwACwjgCTAAAJAAMJwACwjgCTAAAAAA==.',
Fl='Flar:BAAALgAFFAEJAQAAAA==.Flixie:BAABLgAECn8aAAIMAAcJNiHfEwCVAgAMAAcJNiHfEwCVAgABLgAFFAYJIgAWAJATAA==.Flyingcow:BAAALgAECgIJAgAAAA==.',
Fo='Foenix:BAAALgADCgYJBgAAAA==.Foxoffire:BAAALgAECgEJAwAAAA==.Foxu:BAAALgAECgcJBwAAAA==.Foxymoron:BAAALgAECgcJCwAAAA==.Fozzi:BAABLgAECn8oAAIWAAkJQSHmBgAYAwAWAAkJQSHmBgAYAwAAAA==.',
Fr='Freakazoid:BAABLgAECn8wAAIHAAkJjx1LDwBKAgAHAAkJjx1LDwBKAgAAAA==.Fritark:BAAALgAECgcJBwABLgAECgkJEAAEAAAAAA==.Fritzyp:BAAALgAECgkJEAAAAA==.Frogzqc:BAAALgAECgEJAgAAAA==.Frostyburn:BAAALgAECgYJEQAAAA==.Frozenrage:BAAALgADCgcJCwAAAA==.',
['Fë']='Fëanor:BAAALgAECggJCgAAAA==.',
Ga='Gabos:BAAALgADCgEJAQAAAA==.Garayice:BAAALgADCgIJAgAAAA==.Garycoleman:BAAALgADCgEJAQAAAA==.Gaxxen:BAAALgAECgUJBQAAAA==.',
Ge='Gena:BAAALgADCgcJCAAAAA==.Geörge:BAACLgAFFH8XAAIHAAYJSxtLCgCOAQAHAAYJSxtLCgCOAQAuAAQKfyoAAgcACAnVICIIAAIDAAcACAnVICIIAAIDAAAA.',
Gh='Ghostyganja:BAAALgAECgQJBAAAAA==.',
Gi='Giratiña:BAAALgAECgEJAQABLgAFFAIJAwAEAAAAAA==.',
Gl='Glary:BAAALgAECgEJAQAAAA==.Glavendale:BAAALgADCgUJBQAAAA==.',
Go='Goatcheezey:BAAALgADCgYJDAAAAA==.Goblinsox:BAAALgAECgQJBAAAAA==.Goluck:BAAALgAECgEJAQAAAA==.Gordothe:BAAALgADCgUJBQABLgAECgUJBgAEAAAAAA==.',
Gr='Grimel:BAAALgAECgQJCAABLgAECgYJEAAEAAAAAA==.Grimghoul:BAAALgAECgQJCQABLgAECgYJEAAEAAAAAA==.Grimgram:BAAALgAECgYJEAAAAA==.Gripyoulol:BAAALgAECgQJBQAAAA==.Grotelek:BAABLgAECn8hAAIfAAkJTRPNDADKAQAfAAkJTRPNDADKAQAAAA==.Grotret:BAAALgAECgIJAgAAAA==.Grouchy:BAAALgADCgMJAwAAAA==.Grumpywaltz:BAAALgAECgQJBAAAAA==.',
Gu='Gulimath:BAAALgAECgUJBgAAAA==.',
Ha='Halconotachi:BAABLgAECn9EAAIDAAkJRRpRCQB8AgADAAkJRRpRCQB8AgAAAA==.Hammerfoot:BAAALgAECgcJBwAAAA==.Haranir:BAAALgAECgYJCAAAAA==.Harcat:BAABLgAECn8VAAIIAAgJjRMDDwBTAQAIAAgJjRMDDwBTAQAAAA==.Hartracks:BAAALgAECgUJBQAAAA==.Hatijo:BAAALgAECgYJBwAAAA==.Hawgbawl:BAABLgAECn8hAAIYAAgJbxuhFQAxAgAYAAgJbxuhFQAxAgAAAA==.Hawgdream:BAAALgAECgYJEAAAAA==.',
He='Hellequin:BAACLgAFFH8XAAIgAAYJgBpSAQC2AQAgAAYJgBpSAQC2AQAuAAQKfzkAAyAACQkDImUBAOcCACAACQkDImUBAOcCACEAAQkpA4cPACoAAAAA.Henkojin:BAAALgADCgYJBgAAAA==.Heyitzlock:BAAALgAECgYJCQAAAA==.Heyyitzrich:BAAALgAECgQJDQAAAA==.Heyyitzrichh:BAABLgAFFH8JAAIQAAMJzBbUXQDtAAAQAAMJzBbUXQDtAAAAAA==.Heyytaco:BAAALgAECggJEgAAAA==.',
Hi='Hiels:BAAALgAECgcJBwAAAA==.Hirogon:BAAALgAECgEJAwAAAA==.',
Ho='Hobb:BAABLgAECn8pAAIFAAkJcB5yGQCVAgAFAAkJcB5yGQCVAgAAAA==.Holenmymuff:BAAALgADCgUJBQAAAA==.Hollinar:BAABLgAECn8YAAIJAAkJxxLtcADyAQAJAAkJxxLtcADyAQAAAA==.Holyfaux:BAAALgADCgYJBgAAAA==.Holysteel:BAAALgAECgIJAwAAAA==.Hondoe:BAAALgAECgQJCAAAAA==.Hordecow:BAAALgAECgEJAQABLgAFFAEJAgAEAAAAAA==.Hornhelm:BAAALgAECgIJAgAAAA==.',
Hu='Huntoor:BAAALgAECgEJAQABLgAECgYJBgAEAAAAAA==.',
Ic='Icemark:BAACLgAFFH8FAAIJAAMJfxI1KwAJAQAJAAMJfxI1KwAJAQAuAAQKfx8AAgkABwkGHShXADMCAAkABwkGHShXADMCAAAA.',
Ih='Ihavecookies:BAAALgAECgMJBAAAAA==.',
Ij='Ijur:BAAALgAECgQJCAABLgAECgUJBgAEAAAAAA==.',
Ik='Ikayro:BAABLgAECn8cAAIJAAgJdx2AKgDJAgAJAAgJdx2AKgDJAgAAAA==.',
Il='Ilostmyphone:BAAALgAECgEJAQAAAA==.Ilovemysword:BAAALgAECgUJCQAAAA==.Iluvatar:BAABLgAECn8aAAMHAAgJzSCLDQBhAgAHAAgJzSCLDQBhAgAGAAIJwxLqYABOAAABLgAFFAEJAQAEAAAAAA==.',
Im='Imagine:BAABLgAECn8UAAQUAAcJTg4iFgBbAQAUAAcJTg4iFgBbAQATAAYJFganPgDwAAAVAAEJtgKqJwAhAAAAAA==.',
In='Infoxticated:BAAALgAECgEJAQAAAA==.',
Ir='Iratedemon:BAAALgAECgMJBAABLgAECgMJAwAEAAAAAA==.Irateknight:BAAALgAECgMJAwAAAA==.Irely:BAAALgADCgYJBgAAAA==.',
Ja='Jadedways:BAAALgAECgEJAQAAAA==.Jasmirangel:BAACLgAFFH8OAAIZAAMJNCCqJQAaAQAZAAMJNCCqJQAaAQAuAAQKf0QAAhkACAkDJSsGAEoDABkACAkDJSsGAEoDAAAA.',
Je='Jede:BAAALgADCgMJAwAAAA==.',
Jo='Joshallen:BAAALgADCgcJBwAAAA==.',
Ju='Juka:BAABLgAECn8UAAIMAAkJGQe2TwBYAQAMAAkJGQe2TwBYAQAAAA==.Jukks:BAAALgAECgcJCgAAAA==.Juno:BAAALgADCgkJEwAAAA==.Justsumfoo:BAAALgAECgIJBAAAAA==.',
Ka='Kano:BAACLgAFFH8VAAICAAUJYRktFQCFAQACAAUJYRktFQCFAQAuAAQKfy4AAgIACQmII0MIAAkDAAIACQmII0MIAAkDAAAA.Katarm:BAABLgAECn8UAAMKAAkJcgipIQANAQAKAAkJagSpIQANAQAdAAUJNgyhOgDDAAAAAA==.Katarru:BAAALgAECgYJDQAAAA==.Kataru:BAAALgADCgIJAgAAAA==.',
Kh='Khory:BAAALgAFFAEJAQAAAA==.',
Ki='Kirito:BAAALgADCgYJBgAAAA==.',
Kk='Kkiinnoopp:BAABLgAECn8jAAMCAAgJiBY0aQBbAQADAAYJVhYrFQB1AQACAAcJSxQ0aQBbAQAAAA==.',
Ko='Korgigor:BAAALgAECgQJBwAAAA==.Kovu:BAAALgAECgcJEgAAAA==.',
Kr='Krisanthemum:BAAALgADCgcJCwAAAA==.Krystrasz:BAAALgAECgQJCwAAAA==.',
Kt='Kt:BAAALgADCgIJAgABLgAECgQJBAAEAAAAAA==.Ktrogue:BAAALgAECgQJBAAAAA==.',
Ku='Kuailiang:BAAALgAECgcJCQAAAA==.Kuraihikari:BAAALgAFFAEJAQAAAA==.Kustaa:BAAALgADCgkJCgABLgAECggJHwAiAFwYAA==.',
La='Ladezar:BAAALgADCgcJDQAAAA==.Laissen:BAAALgAECgYJCAAAAA==.Lapsung:BAAALgAECgIJBAABLgAECgcJEwAEAAAAAA==.Lattemocha:BAABLgAECn8fAAMZAAgJjh2eMADpAQAZAAYJ+RqeMADpAQAjAAgJbxMCJACSAQAAAA==.',
Le='Lenden:BAAALgAECgMJBgAAAA==.Leprechaun:BAAALgADCgcJCQAAAA==.Leví:BAAALgADCgUJBQAAAA==.Leylas:BAAALgAECgEJAgAAAA==.',
Li='Lighthoove:BAAALgAECgcJBwAAAA==.Lilliaz:BAAALgAECgYJBwAAAA==.Linianna:BAAALgAECgYJEgAAAA==.Liriel:BAAALgAECgcJBwAAAA==.',
Lu='Ludlow:BAABLgAECn8cAAICAAcJgwixkAAGAQACAAcJgwixkAAGAQAAAA==.Lunastra:BAACLgAFFH8IAAIJAAMJ7A+RdgDVAAAJAAMJ7A+RdgDVAAAuAAQKfyUAAgkACAmiGeBbALMBAAkACAmiGeBbALMBAAEuAAUUAQkBAAQAAAAA.Luneztoprime:BAAALgAECgYJCgAAAA==.',
Ly='Lydarra:BAAALgAECgQJBwABLgAECgYJFQAYAFAZAA==.Lyiann:BAAALgADCggJEgAAAA==.Lyákadion:BAAALgAECgEJAQAAAA==.',
['Lâ']='Lâdypriest:BAAALgADCgUJBQAAAA==.',
Ma='Mafi:BAABLgAECn8WAAICAAcJ/RnCUQCXAQACAAcJ/RnCUQCXAQAAAA==.Maggore:BAAALgAECgIJBgAAAA==.Magikiwiks:BAAALgAECgEJAQAAAA==.Magsdk:BAAALgAFFAIJAgABLgAFFAcJIAATAAceAA==.Mainlander:BAAALgAECgMJAwAAAA==.Malbogea:BAAALgAECgEJAgAAAA==.Malusmittens:BAAALgAECgQJBQABLgAFFAQJEgACAN4hAA==.Mantonso:BAABLgAECn8xAAIYAAkJDSBYCwCeAgAYAAkJDSBYCwCeAgAAAA==.Matt:BAACLgAFFH8JAAIZAAQJMQvPLQDwAAAZAAQJMQvPLQDwAAAuAAQKfyoAAhkACQkiHfYLAPECABkACQkiHfYLAPECAAAA.',
Me='Meddicus:BAAALgAECgUJCAAAAA==.Meechydarko:BAAALgAECgUJBQABLgAECgkJMgADALMfAA==.Megalomaniä:BAAALgADCgYJBgABLgAECgcJHgAeAKYYAA==.Megorice:BAAALgAECgQJBAAAAA==.Megå:BAABLgAECn8eAAMeAAcJphgrFAALAQAQAAYJmBf0bgBTAQAeAAUJmBsrFAALAQAAAA==.Mewtwô:BAAALgAECgYJBwAAAA==.',
Mi='Microbrew:BAAALgAECgMJBQAAAA==.Miezra:BAAALgAECgYJCAAAAA==.Mikah:BAAALgAECgYJDwAAAA==.',
Mo='Modayus:BAAALgAECgEJAQAAAA==.Mojomittens:BAACLgAFFH8SAAICAAQJ3iHiHQBjAQACAAQJ3iHiHQBjAQAuAAQKfyIAAwIABwlEJB8jAEICAAIABwlEJB8jAEICAAgABQnAFqRAAFcBAAAA.Monstermime:BAAALgAECgIJAgABLgAECggJCwAEAAAAAA==.Monstroqt:BAAALgADCgQJBAAAAA==.Morøs:BAAALgADCgYJBgAAAA==.Moxx:BAABLgAECn8ZAAIkAAkJtw74LQA9AQAkAAkJtw74LQA9AQAAAA==.',
Mu='Muffers:BAABLgAECn8wAAIkAAgJNBF/JQByAQAkAAgJNBF/JQByAQAAAA==.Muffpuff:BAAALgAECgQJBQAAAA==.Mutige:BAAALgADCgEJAQAAAA==.',
My='Mylotus:BAAALgAECgQJBQAAAA==.',
Na='Napkuntt:BAAALgAECgEJAQAAAA==.Napokin:BAAALgAFFAEJAgAAAA==.Napshade:BAABLgAECn8bAAMHAAcJMxuALABUAQAHAAYJSRyALABUAQALAAYJEhCDQwDHAAABLgAFFAEJAgAEAAAAAA==.Natsuu:BAAALgAECgcJDAAAAA==.',
Nb='Nbayoungboyy:BAAALgADCgYJBgABLgAFFAYJHgACAIYhAA==.',
Ne='Necroticoath:BAAALgAECgIJBgABLgAFFAIJAwAEAAAAAA==.Neven:BAAALgAECgIJAgAAAA==.',
Ni='Nightor:BAAALgAECgEJAQAAAA==.Nikodemos:BAAALgAFFAYJFwAAAQ==.Nivahoof:BAAALgADCgEJAQAAAA==.',
No='Noc:BAABLgAECn8jAAMQAAgJVxY1PwDUAQAQAAgJVxY1PwDUAQARAAUJNA+JLQAHAQABLgAECgkJKgAQAEcaAA==.Nomemage:BAAALgADCgEJAQAAAA==.',
Ob='Obe:BAAALgAFFAIJAgAAAA==.Obsidiangel:BAAALgADCggJEAAAAA==.',
Oh='Ohface:BAAALgAECgQJBwABLgAECgIJBgAEAAAAAA==.',
Oo='Oowu:BAAALgADCgQJBAAAAA==.',
Or='Oran:BAAALgAECggJEgAAAA==.Orctrax:BAABLgAECn8aAAMCAAgJVRFwaQBaAQACAAgJVRFwaQBaAQAIAAEJBALAjgAsAAAAAA==.Oricale:BAAALgADCgYJBgAAAA==.',
Os='Osheat:BAACLgAFFH8FAAISAAMJJg1PjwDPAAASAAMJJg1PjwDPAAAuAAQKfyMAAhIACQndHxEkAGMCABIACQndHxEkAGMCAAAA.Osmodeus:BAAALgAECgUJCAAAAA==.',
Ou='Outplay:BAAALgADCgUJBQAAAA==.',
Ox='Oxheart:BAAALgAECgEJAQAAAA==.',
Pa='Paltis:BAAALgAECgQJBQAAAA==.Paltonso:BAAALgADCgkJCQAAAA==.Pandaari:BAABLgAECn8WAAIHAAgJFAQbRgDSAAAHAAgJFAQbRgDSAAAAAA==.Papaschristo:BAAALgADCgUJBQAAAA==.Papasdiablo:BAAALgAECgEJAgAAAA==.Parprapa:BAAALgADCgMJAwAAAA==.',
Pe='Penicillin:BAAALgAECgMJAwAAAA==.Persimmon:BAACLgAFFH8OAAIiAAQJVxzUFgBWAQAiAAQJVxzUFgBWAQAuAAQKfyAAAiIABwmTF28nALsBACIABwmTF28nALsBAAAA.Peyton:BAAALgAECgUJBwAAAA==.',
Ph='Philip:BAAALgADCgcJDAAAAA==.Phyrie:BAAALgAECgUJDwABLgAECgYJFQAYAFAZAA==.',
Pi='Pittpete:BAAALgAECgEJAQAAAA==.',
Pl='Plaguepapi:BAAALgAFFAEJAQAAAA==.',
Po='Pollocaotico:BAAALgAFFAIJAgAAAA==.',
Ps='Psythera:BAAALgAECgIJBAABLgAECggJIgAHAPIcAA==.Psythern:BAAALgADCgYJCQABLgAECggJIgAHAPIcAA==.',
Pu='Punkybrewstr:BAABLgAECn8xAAMBAAgJjhaEIQCMAQABAAcJURaEIQCMAQAkAAgJswr0MABjAQAAAA==.Pureshock:BAAALgAECggJDQAAAA==.Purpderf:BAAALgAFFAEJAQAAAA==.',
Pw='Pwnstar:BAAALgAECgQJCAAAAA==.',
Py='Pykei:BAAALgAECgMJAwAAAA==.Pyrrah:BAAALgAECgEJAQABLgAECgkJJAAGAEIdAA==.Pyrri:BAABLgAECn8kAAQGAAkJQh0iEgA4AgAGAAgJaB4iEgA4AgALAAQJ4RXjUQDwAAAHAAMJdRTKUACnAAAAAA==.Pyrria:BAAALgAECgkJEQABLgAECgkJJAAGAEIdAA==.Pyrris:BAAALgAECgMJAwABLgAECgkJJAAGAEIdAA==.',
Pz='Pznt:BAAALgAECgEJAQAAAA==.',
['Pé']='Péyton:BAAALgAECgYJCAAAAA==.',
['Pì']='Pì:BAAALgADCgEJAgAAAA==.',
['Pô']='Pôws:BAAALgAECgIJAwAAAA==.',
Qu='Quantonbomb:BAABLgAECn8UAAIZAAkJehnnEQCuAgAZAAkJehnnEQCuAgAAAA==.Quezera:BAAALgADCgYJBgAAAA==.',
Ra='Rabuf:BAABLgAECn8fAAMiAAgJXBjTFgA/AgAiAAgJXBjTFgA/AgAFAAYJ6QxsvwAIAQAAAA==.Raccoonadin:BAAALgADCgEJAQAAAA==.Radha:BAAALgAECgIJAgABLgAFFAQJEQASAPAgAA==.Ragingwater:BAAALgAECgYJEAAAAA==.Ranadheer:BAAALgAFFAEJAQAAAA==.Raspaigus:BAAALgAECgQJBAAAAA==.Ratfu:BAABLgAECn8UAAIkAAYJOQX/RwD1AAAkAAYJOQX/RwD1AAAAAA==.Raudson:BAABLgAECn8UAAIlAAkJDCJUAgATAwAlAAkJDCJUAgATAwAAAA==.',
Re='Redizle:BAACLgAFFH8aAAIGAAcJRhSFCgAzAgAGAAcJRhSFCgAzAgAuAAQKfycABAsACAnxHBkoAK8BAAYACAn7FuUbALcBAAsABgkyHBkoAK8BAAcABQnSEug2ADYBAAAA.Reginrune:BAAALgAECgkJEwAAAA==.Resonance:BAABLgAECn8WAAMNAAcJHBZPNABRAQANAAcJ9RVPNABRAQAfAAMJZwykIwCeAAAAAA==.Restroll:BAAALgADCgUJBQAAAA==.',
Rh='Rhaigar:BAAALgAECgUJCQAAAA==.Rhónatar:BAAALgADCgQJBAAAAA==.',
Ri='Righteouscow:BAAALgAECgEJAQAAAA==.',
Ro='Rohdoog:BAABLgAECn8yAAITAAkJWBcrEgA5AgATAAkJWBcrEgA5AgAAAA==.Roundabugman:BAACLgAFFH8LAAINAAMJrh0bJADzAAANAAMJrh0bJADzAAAuAAQKfyMAAw0ACAmQGisuAHMBAA0ACAmQGisuAHMBAAwAAwmnFOF3ALIAAAAA.',
Rr='Rr:BAABLgAFFH8GAAMhAAMJpAFvDAB2AAAhAAMJpAFvDAB2AAAmAAEJ4wDKNwAqAAAAAA==.',
Ru='Runedyu:BAAALgAECgYJDgAAAA==.',
Ry='Ryanno:BAACLgAFFH8IAAICAAMJpxv7PgAQAQACAAMJpxv7PgAQAQAuAAQKfyoAAgIACQkwILIYAH0CAAIACQkwILIYAH0CAAAA.Ryujinhalco:BAAALgADCgMJAwAAAA==.',
Sa='Sabim:BAAALgAECgEJAQAAAA==.Sahomi:BAACLgAFFH8IAAIGAAMJwgqcKwC/AAAGAAMJwgqcKwC/AAAuAAQKfyMAAwYACQkUCHkoAFIBAAYACQkUCHkoAFIBAAsAAglNBZR3AEwAAAAA.Salana:BAAALgADCgcJBwAAAA==.Samwise:BAAALgAECgYJCAAAAA==.Sarai:BAAALgADCgEJAQAAAA==.Sarcini:BAABLgAECn8uAAIlAAkJXhvFBgBiAgAlAAkJXhvFBgBiAgAAAA==.Satrina:BAACLgAFFH8NAAISAAQJqRXPSABCAQASAAQJqRXPSABCAQAuAAQKfyQAAhIACAmrIpotADcCABIACAmrIpotADcCAAAA.Savvy:BAAALgAECgUJBQABLgAECgYJBgAEAAAAAA==.',
Sc='Scrappy:BAAALgAECgEJAQAAAA==.',
Se='Sedna:BAAALgADCgYJBgABLgAECgYJCAAEAAAAAA==.Selanthe:BAAALgAECgQJBgAAAA==.Seruk:BAAALgAECgEJBAAAAA==.Seventhghost:BAEALgAECgIJAgABLgAFFAQJCwAHADEQAA==.',
Sh='Shadowstorme:BAAALgAECgIJBQAAAA==.Shamander:BAABLgAECn8eAAIMAAkJQxjqHgA/AgAMAAkJQxjqHgA/AgAAAA==.Shamsham:BAAALgADCgcJDAAAAA==.Sharky:BAAALgADCgQJBAAAAA==.Shocka:BAAALgADCgcJCQAAAA==.Shokanki:BAAALgAECgYJCwAAAA==.',
Si='Sicara:BAABLgAECn8uAAIXAAkJQhbGOQDKAQAXAAkJQhbGOQDKAQAAAA==.Silentmage:BAAALgADCgcJCAAAAA==.Silentslock:BAAALgADCgYJBQAAAA==.Sillylilguy:BAACLgAFFH8JAAIfAAMJnBE3AwADAQAfAAMJnBE3AwADAQAuAAQKfxgAAh8ACAmEH+8EAMECAB8ACAmEH+8EAMECAAAA.Sinestro:BAAALgAECgMJAwAAAA==.Sivrogar:BAAALgAECgMJAwAAAA==.',
Sl='Slaik:BAAALgAECgUJDgAAAA==.Slander:BAACLgAFFH8YAAMSAAUJ0h6KQQBQAQASAAUJ0h6KQQBQAQAbAAEJAABZUAAAAAAuAAQKfzcAAhIACQmQIYUcAIoCABIACQmQIYUcAIoCAAAA.',
So='Solemnograve:BAAALgAECgIJAgAAAA==.Somazugzug:BAACLgAFFH8HAAIMAAMJfBgfOwDdAAAMAAMJfBgfOwDdAAAuAAQKfyQAAgwACQm5GV8uANABAAwACQm5GV8uANABAAAA.Sothren:BAAALgAECgEJAgABLgADCgkJCQAEAAAAAA==.',
Sp='Spacedguy:BAAALgADCgMJAwAAAA==.Spry:BAAALgAECgEJAQAAAA==.',
St='Staccato:BAAALgAECgEJAQAAAA==.Stanleyy:BAAALgAECgQJBQABLgAFFAIJAwAEAAAAAA==.Stepbrother:BAAALgAECgYJDQABLgAECgkJMgADALMfAA==.',
Su='Sugar:BAABLgAECn8nAAMMAAkJ5RGHRQB+AQAMAAkJ5RGHRQB+AQANAAUJtw6oVgDrAAAAAA==.Sugars:BAAALgAECgUJAwAAAA==.Sulin:BAAALgADCgUJBwAAAA==.Sungôd:BAAALgADCgEJAQABLgAECgkJMQABAI4WAA==.',
Sw='Swonks:BAAALgAECgMJAwAAAA==.Swyper:BAAALgAECgMJAwAAAA==.',
Sy='Synicism:BAAALgADCgcJDQAAAA==.',
Ta='Taintbubble:BAAALgAECgMJBQAAAA==.Tanktommy:BAAALgAECgMJAwABLgAFFAQJDwASABsbAA==.Tarnished:BAAALgADCgcJCAAAAA==.Tarquitus:BAACLgAFFH8SAAMXAAYJ+A4hOAAiAQAXAAUJVxIhOAAiAQAPAAIJeAS+CgCTAAAuAAQKfzwAAxcACAmXIA4aAGYCABcACAnWHw4aAGYCAA8ACAm8F0sRAFUCAAAA.Tattoosguy:BAAALgADCgEJAQAAAA==.',
Te='Teef:BAABLgAECn8cAAImAAcJFxVzIAB5AQAmAAcJFxVzIAB5AQAAAA==.Tellan:BAAALgADCgcJBwAAAA==.',
Th='Thanatös:BAABLgAECn8cAAMJAAgJbBYFXwCrAQAJAAgJbBYFXwCrAQAnAAQJrxRDDQD1AAAAAA==.Tharros:BAAALgAECgcJDAAAAA==.Thedarkkness:BAABLgAECn8lAAIbAAgJuhn5FwCLAQAbAAgJuhn5FwCLAQAAAA==.Thrasher:BAAALgAECgEJAwAAAA==.',
Ti='Tidalwave:BAACLgAFFH8KAAIMAAQJIxuTIgA8AQAMAAQJIxuTIgA8AQAuAAQKfy0AAwwACQnFGTcdAEsCAAwACQnFGTcdAEsCAA0AAgltCw2XAC4AAAAA.Tidus:BAAALgAECgYJEQAAAA==.Tinytotem:BAAALgAECgEJBAAAAA==.Tissue:BAABLgAECn8XAAIPAAcJCArULABjAQAPAAcJCArULABjAQAAAA==.',
To='Toasted:BAAALgADCgYJCQABLgAECgMJAwAEAAAAAA==.Tobibi:BAAALgAECgYJBwABLgAFFAIJAwAEAAAAAA==.Todo:BAAALgADCgQJBAAAAA==.Tolip:BAABLgAECn8rAAMZAAgJUQgrdgD1AAAZAAYJgAgrdgD1AAAjAAgJSgThQQDrAAABLgAFFAEJAQAEAAAAAA==.Tolipally:BAAALgAFFAEJAQAAAA==.Tolipicious:BAAALgADCgUJCQABLgAFFAEJAQAEAAAAAA==.',
Tr='Trauts:BAAALgAECgQJCAAAAA==.Treeadin:BAABLgAECn8fAAIlAAgJ6A9AGwAmAQAlAAgJ6A9AGwAmAQAAAA==.Trollcula:BAAALgAECggJDgABLgAFFAMJAwAEAAAAAA==.Truthwithin:BAAALgAECgUJEgAAAA==.',
Ts='Tsarrubus:BAABLgAECn8hAAIPAAkJcwn2HwBZAQAPAAkJcwn2HwBZAQAAAA==.',
Tu='Tula:BAAALgAECgUJCwAAAA==.Tusck:BAAALgAECgYJDwAAAA==.',
Tw='Twingert:BAAALgAECgEJAQAAAA==.Twitch:BAAALgAECgYJEwAAAA==.',
Ty='Tyedyemess:BAAALgAECgMJAwAAAA==.Tyledridal:BAAALgAECgMJAwAAAA==.',
['Tà']='Tàylor:BAABLgAECn8cAAIiAAkJOQu1OgCPAQAiAAkJOQu1OgCPAQAAAA==.',
Ub='Ubbaa:BAAALgAECgEJAQAAAA==.',
Ul='Ulghar:BAABLgAECn8jAAIYAAkJayQFAwAwAwAYAAkJayQFAwAwAwAAAA==.',
Ur='Ursock:BAAALgAECggJDgAAAA==.',
Uw='Uwuhshake:BAABLgAECn8tAAMZAAkJ7SEpBABvAwAZAAkJ7SEpBABvAwAjAAEJqRuvbwBSAAAAAA==.',
Va='Valdria:BAAALgAECgMJAwAAAA==.Valssien:BAAALgADCgkJCQAAAA==.Vanaria:BAAALgAECgQJBAAAAA==.Vanbrook:BAAALgAECgQJAgAAAA==.Vanden:BAAALgAECgYJDAAAAA==.Vanrion:BAAALgAFFAIJAwAAAA==.Varrodd:BAAALgAECgEJAQAAAA==.Vastextent:BAAALgADCgMJBAAAAA==.',
Ve='Velcro:BAAALgAECgYJEgAAAA==.Velsera:BAAALgAECgYJCAAAAA==.Velvet:BAAALgADCgQJCAAAAA==.Velyn:BAAALgAECgcJDwAAAA==.Velynara:BAAALgADCgIJAgABLgAECgYJCAAEAAAAAA==.Vengefulcry:BAAALgAECgMJAwAAAA==.Vengefül:BAAALgADCgYJCAAAAA==.Vexara:BAAALgAECgQJBAAAAA==.',
Wa='Wanaaga:BAAALgAECggJDgAAAA==.',
We='Wedge:BAAALgAECgEJAQAAAA==.',
Wh='Whohaveaggro:BAAALgAECgEJAgAAAA==.',
Wi='Widestripe:BAAALgADCgEJAQAAAA==.Wilmington:BAAALgADCgIJAgAAAA==.Wino:BAABLgAECn8VAAMmAAgJlxA9HACeAQAmAAgJdhA9HACeAQAgAAEJTxGaIgA8AAAAAA==.Wiqui:BAAALgAECgEJBAAAAA==.Witulow:BAABLgAECn8nAAMWAAgJ3w1SRQAnAQAWAAcJog9SRQAnAQABAAgJVQTLPAD4AAAAAA==.',
Wo='Wolfadin:BAACLgAFFH8JAAIFAAQJAwV+HAC9AAAFAAQJAwV+HAC9AAAuAAQKfzcAAgUACQmNGUYpAEYCAAUACQmNGUYpAEYCAAAA.Woopac:BAABLgAECn8iAAIYAAgJihxYGgAJAgAYAAgJihxYGgAJAgAAAA==.',
Wu='Wulfharth:BAAALgAECgYJDwAAAA==.',
Xe='Xenophics:BAACLgAFFH8aAAMFAAYJThMEGwB4AQAFAAYJThMEGwB4AQAiAAEJXwCOSAAkAAAuAAQKfzwABAUACAngIeYrADoCAAUACAngIeYrADoCACIABAl7EERRAN4AACUAAQnKBrFNACUAAAEuAAUUAwkKAAkAYQsA.Xenophicstwo:BAACLgAFFH8KAAIJAAMJYQvHMgDUAAAJAAMJYQvHMgDUAAAuAAQKfyYAAgkABglMGxx0AHgBAAkABglMGxx0AHgBAAAA.',
Xu='Xuen:BAABLgAECn8VAAIkAAcJ/hN2JwBmAQAkAAcJ/hN2JwBmAQABLgAFFAMJCgAFABAkAA==.',
Ya='Yajsooblwj:BAAALgADCgMJAwAAAA==.',
Za='Zal:BAABLgAECn8fAAQiAAkJTxniIADnAQAiAAkJTxniIADnAQAFAAcJbBYsjAA+AQAlAAIJDRVkNAB2AAAAAA==.Zanor:BAAALgAECgIJAgAAAA==.Zarranora:BAAALgAECgEJAQAAAA==.Zatannå:BAAALgADCgYJCQAAAA==.',
Ze='Zect:BAABLgAECn8sAAIJAAkJURMYQwD9AQAJAAkJURMYQwD9AQAAAA==.Zenshin:BAAALgAECgIJAgAAAA==.Zentaur:BAAALgAECggJCwAAAA==.Zetzu:BAABLgAECn8WAAIYAAgJLRijIQDTAQAYAAgJLRijIQDTAQAAAA==.',
Zi='Zitfrlt:BAAALgAECgEJAQABLgAECgcJDQAEAAAAAA==.',
['Ål']='Ålucard:BAABLgAECn8bAAMHAAgJVhhkHADHAQAHAAgJVhhkHADHAQAGAAQJRBHtOwD5AAAAAA==.',
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
