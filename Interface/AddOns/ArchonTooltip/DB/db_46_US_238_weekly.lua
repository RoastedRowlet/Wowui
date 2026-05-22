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

local lookup = {'Monk-Brewmaster','Unknown-Unknown','Paladin-Retribution','Priest-Discipline','Priest-Shadow','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Frost','Warrior-Protection','Priest-Holy','Shaman-Restoration','Shaman-Elemental','Druid-Guardian','Warlock-Affliction','DemonHunter-Havoc','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','DemonHunter-Devourer','Druid-Restoration','DeathKnight-Frost','DeathKnight-Blood','Warrior-Arms','Monk-Mistweaver','Shaman-Enhancement','Rogue-Assassination','Rogue-Outlaw','Warrior-Fury','Monk-Windwalker','Paladin-Holy','Paladin-Protection','Rogue-Subtlety','Mage-Arcane','Druid-Balance',}
local provider = {region='US',realm='Wildhammer',name='US',type='weekly',zone=46,date='2026-05-17',data={Ab='Abaddonaxx:BAAALgADCgYJBgAAAA==.',
Ac='Acesmash:BAABLgAECn8lAAIBAAkJGCLMAwDoAgABAAkJGCLMAwDoAgAAAA==.Ackrenezoth:BAAALgAECgQJBwAAAA==.',
Ad='Adymisk:BAAALgADCgEJAQAAAA==.',
Ag='Agorot:BAAALgAFFAEJAQAAAA==.',
Ak='Akadion:BAAALgADCgcJCgAAAA==.Akatali:BAAALgAECgQJBgAAAA==.',
Al='Aldannia:BAAALgAECgkJEAAAAA==.Alextros:BAEALgAECgYJEQABLgAECgcJCgACAAAAAA==.Alloren:BAAALgAECgQJBAAAAA==.Almond:BAAALgAECgEJAgAAAA==.',
Am='Amrax:BAABLgAECn8kAAIDAAgJSg+fYQBwAQADAAgJSg+fYQBwAQAAAA==.Amynre:BAABLgAECn8aAAMEAAkJKRCfFQD5AQAEAAkJKRCfFQD5AQAFAAMJ6w33VABvAAAAAA==.',
An='Anarsa:BAAALgAECgUJCgAAAA==.Angstyboi:BAAALgAECgQJBAAAAA==.',
Aq='Aquabat:BAACLgAFFH8LAAQGAAMJTxklGAC/AAAGAAIJcx8lGAC/AAAHAAMJWRLQTACiAAAIAAEJ8xvxJABVAAAuAAQKfyQABAYACAmyIWgIAGkCAAYACAmvH2gIAGkCAAgABwmrH38bAEwCAAcABQlwJRgoABgCAAAA.',
Ar='Arvyy:BAABLgAECn8iAAIJAAkJyhhlIwBZAgAJAAkJyhhlIwBZAgAAAA==.',
As='Ashbringer:BAABLgAECn8lAAIDAAkJYCO4CwDZAgADAAkJYCO4CwDZAgAAAA==.',
At='Atria:BAABLgAECn8aAAIJAAgJZA/HxwBYAQAJAAgJZA/HxwBYAQAAAA==.Attia:BAAALgAECgcJEgAAAA==.',
Av='Avaris:BAAALgADCgIJAgAAAA==.Avatarbambi:BAAALgADCgUJAgAAAA==.',
Ax='Axtar:BAABLgAECn8lAAIKAAkJ5xiVCgAIAgAKAAkJ5xiVCgAIAgAAAA==.',
Ay='Ayyitzrich:BAAALgADCgQJBAAAAA==.',
Ba='Babarazzar:BAAALgADCgYJBgAAAA==.Baladoria:BAABLgAECn8tAAILAAkJESEWAwA3AwALAAkJESEWAwA3AwAAAA==.Bananabowman:BAAALgAECgEJAgAAAA==.Barrels:BAABLgAECn8cAAMGAAkJERovDQAfAgAGAAkJmxUvDQAfAgAHAAgJIBU6SQB8AQAAAA==.Bartab:BAABLgAECn8sAAMMAAgJxxxPEQB/AgAMAAgJxxxPEQB/AgANAAEJEwO7jQAfAAABLgAECgkJLAAOANIbAA==.Baruku:BAAALgAFFAEJAQAAAA==.Bastadi:BAAALgAECgMJBgABLgAECgYJFAAPAL8gAA==.',
Be='Beastling:BAAALgADCgcJCQAAAA==.Beau:BAABLgAECn8wAAIQAAkJDCPPAgD1AgAQAAkJDCPPAgD1AgAAAA==.Beauwi:BAAALgAECgQJBgABLgAECgkJMAAQAAwjAA==.',
Bi='Bigshekels:BAAALgAECgEJAQAAAA==.Bigulsworth:BAAALgADCgQJAwAAAA==.',
Bl='Blackadder:BAAALgAECgcJEgAAAA==.Blenton:BAAALgAECgEJAQAAAA==.Bloodussy:BAAALgADCgUJBQAAAA==.Bluck:BAAALgADCgcJEQAAAA==.Blueeyesdrag:BAAALgADCgEJAQAAAA==.',
Bo='Boing:BAAALgAECgUJCgAAAA==.Bombur:BAABLgAECn8rAAMRAAgJMxlrOwC5AQARAAgJMxlrOwC5AQASAAEJAAAdZABGAAAAAA==.Bosstradamus:BAAALgAECgYJBgABLgAFFAIJAgACAAAAAA==.Boston:BAAALgAECggJEwAAAA==.Bottles:BAAALgAFFAEJAQAAAA==.',
Bu='Bubagony:BAAALgADCgQJBAABLgAFFAQJDgATAFwdAA==.Bullmedic:BAAALgADCgYJBgAAAA==.Burakku:BAABLgAECn8VAAQUAAcJEhnTGgDzAQAUAAcJEhnTGgDzAQAVAAUJJwgCMQDpAAAWAAEJAAC0PgA1AAABLgAFFAQJEQAEAMchAA==.Burguerkiing:BAAALgADCgMJAwAAAA==.Burph:BAAALgADCggJCAAAAA==.Buttonsmash:BAAALgAECgcJEAABLgAFFAYJGgAVAMgSAA==.Buzzkill:BAAALgADCgMJAwAAAA==.',
['Bâ']='Bâbyrage:BAAALgADCgcJDwAAAA==.',
Ca='Cairen:BAABLgAECn8fAAIXAAkJqBsiHwAgAgAXAAkJqBsiHwAgAgAAAA==.Calzraxx:BAAALgAECgkJEQAAAA==.Carstaller:BAAALgAECgMJAwAAAA==.Cartons:BAAALgAECggJDQAAAA==.',
Cc='Ccaan:BAAALgAECgkJEQAAAA==.Ccian:BAAALgAECgQJBAAAAA==.',
Ce='Celinn:BAABLgAECn8oAAMLAAkJKBxLDwA1AgALAAkJKBxLDwA1AgAEAAEJuxm9UQBLAAAAAA==.',
Ch='Chadgar:BAAALgADCgUJBwAAAA==.Chalupacabra:BAAALgADCgIJAgAAAA==.Chappie:BAAALgAECgEJAQABLgAFFAMJCwAGAE8ZAA==.Charliek:BAAALgAFFAIJAgAAAA==.Cherches:BAAALgADCgEJAQAAAA==.Childish:BAAALgAECgUJCAAAAA==.Chimalma:BAAALgAFFAIJAwAAAA==.Chiqui:BAAALgAECgEJAQAAAA==.',
Cl='Clarabow:BAAALgAFFAIJAwAAAA==.Closure:BAABLgAECn8WAAIYAAgJ4CLbDADWAgAYAAgJ4CLbDADWAgAAAA==.Cloudsx:BAAALgADCgMJAwAAAA==.',
Co='Coatlicue:BAABLgAECn8UAAMLAAkJGB+hEQBVAgALAAgJRSGhEQBVAgAFAAUJZBTFMQBXAQABLgAFFAIJAwACAAAAAA==.Coby:BAAALgAECgcJEgAAAA==.Coffins:BAAALgAECgYJEQABLgAECggJDQACAAAAAA==.Covell:BAAALgAECgUJBwAAAA==.',
Cr='Crates:BAAALgAECgUJCAABLgAECggJDQACAAAAAA==.Crimsonmagic:BAAALgAECgEJAgAAAA==.Crosswalkk:BAAALgADCgMJAwAAAA==.Crygore:BAAALgAECgQJCgABLgAECgIJBgACAAAAAA==.',
Cy='Cypherrellik:BAABLgAECn8aAAMQAAgJMhHwGgBNAQAQAAgJMhHwGgBNAQAXAAIJHgIg2QA9AAAAAA==.',
Da='Daktok:BAAALgADCgQJBAAAAA==.Damer:BAAALgADCgkJFgAAAA==.Damues:BAAALgAECggJDwAAAA==.Danaric:BAAALgAECgMJBgAAAA==.Dannyphentom:BAABLgAECn8VAAQZAAYJgxTrFQC3AAATAAUJVw7DtwDIAAAZAAMJxhfrFQC3AAAaAAMJmA4qNgCQAAAAAA==.Dargar:BAAALgAECgEJAQAAAA==.Darkling:BAABLgAECn8dAAIQAAcJoB0nDQD9AQAQAAcJoB0nDQD9AQAAAA==.Darknyss:BAAALgADCgUJBQAAAA==.',
De='Dedeye:BAAALgADCgMJAwAAAA==.Dekumime:BAAALgAECgQJBAAAAA==.Demandred:BAAALgAECgkJEQAAAA==.Demongrass:BAACLgAFFH8HAAIXAAMJdh0TOQD9AAAXAAMJdh0TOQD9AAAuAAQKfy8AAhcACAnnH3kiAIMCABcACAnnH3kiAIMCAAAA.Denaric:BAAALgAECgYJEAAAAA==.Derty:BAAALgAECgUJBgAAAA==.',
Di='Diviñehymn:BAAALgAECgYJCQAAAA==.',
Do='Donet:BAAALgADCgEJAQAAAA==.Doppy:BAAALgADCgYJBgAAAA==.',
Dr='Dragondeezz:BAAALgAECgIJBAABLgAECgIJBgACAAAAAA==.Dragondznuts:BAACLgAFFH8aAAIVAAYJyBJoBwDUAQAVAAYJyBJoBwDUAQAuAAQKfzcABBUACQkhHAYHAFMCABUACQkhHAYHAFMCABQAAgnoHtFNAK4AABYAAglHCPAXAF0AAAAA.Draxtos:BAEALgAECgcJCgAAAA==.Dreamevil:BAAALgAECgkJBgAAAA==.Drroxso:BAAALgAECgQJBAAAAA==.',
Ea='Eazybake:BAAALgADCgEJAQAAAA==.',
Ei='Eilerra:BAABLgAECn8cAAIJAAcJjhoyRgDPAQAJAAcJjhoyRgDPAQAAAA==.Eithan:BAAALgADCgMJAwAAAA==.',
El='Elementony:BAABLgAECn85AAINAAkJpBB0IwD1AQANAAkJpBB0IwD1AQAAAA==.Elkdruid:BAABLgAECn8dAAMYAAgJshCXTwBnAQAYAAgJshCXTwBnAQAOAAEJQAzlNgAbAAAAAA==.Elladamri:BAAALgAECgEJAQAAAA==.Elodi:BAAALgAECgEJAQAAAA==.',
Em='Emberglow:BAAALgAECgYJDAAAAA==.Empyrean:BAAALgADCgQJBQAAAA==.Emylia:BAAALgAECgcJEAAAAA==.',
Er='Eresdelor:BAABLgAECn8YAAMKAAkJlRODEACeAQAKAAkJzhGDEACeAQAbAAQJLA4XJwC2AAAAAA==.Erre:BAABLgAECn8mAAIRAAkJ3x5rEQCUAgARAAkJ3x5rEQCUAgAAAA==.',
Es='Esdeáth:BAAALgADCgEJAQAAAA==.Estia:BAAALgAECgIJAgABLgAECgUJDgACAAAAAA==.',
Ev='Evoktor:BAAALgAECgEJAQAAAA==.',
Fa='Facasdeath:BAAALgAECgYJDAAAAA==.Failure:BAEBLgAECn8ZAAIGAAkJ+hQcDQD6AQAGAAkJ+hQcDQD6AQAAAA==.Farmtoon:BAAALgAECgYJDQAAAA==.',
Fe='Feardapain:BAACLgAFFH8OAAIRAAQJVRRYKgBAAQARAAQJVRRYKgBAAQAuAAQKfzkABBEACQk5IhUPAAEDABEACAk5IhUPAAEDABIAAQkAADFcAFoAAA8AAQkAAP84AAwAAAAA.Feardatpain:BAAALgAFFAEJAQAAAA==.Fellyn:BAAALgADCggJCwAAAA==.',
Ff='Ff:BAABLgAFFH8HAAIJAAMJwADFcwCkAAAJAAMJwADFcwCkAAAAAA==.',
Fl='Flar:BAAALgAECgUJCgAAAA==.Flixie:BAABLgAECn8XAAIMAAYJ2iFPGAA/AgAMAAYJ2iFPGAA/AgABLgAFFAUJFAAcAPoTAA==.',
Fo='Foenix:BAAALgADCgYJBgAAAA==.Foxoffire:BAAALgAECgEJAgAAAA==.Foxymoron:BAAALgAECgcJCwAAAA==.Fozzi:BAABLgAECn8oAAIcAAkJQSHKBAAcAwAcAAkJQSHKBAAcAwAAAA==.',
Fr='Freakazoid:BAABLgAECn8wAAIFAAkJjx3ACgBlAgAFAAkJjx3ACgBlAgAAAA==.Fritark:BAAALgAECgcJBwABLgAECgcJDQACAAAAAA==.Fritzyp:BAAALgAECgcJDQAAAA==.Frogzqc:BAAALgAECgEJAgAAAA==.Frostyburn:BAAALgAECgYJEAAAAA==.Frozenrage:BAAALgADCgcJCwAAAA==.',
['Fë']='Fëanor:BAAALgAECggJBAAAAA==.',
Ga='Gabos:BAAALgADCgEJAQAAAA==.Garayice:BAAALgADCgIJAgAAAA==.Gaxxen:BAAALgAECgUJBQAAAA==.',
Ge='Gena:BAAALgADCgcJBwAAAA==.Geörge:BAACLgAFFH8XAAIFAAYJSxsHBQC4AQAFAAYJSxsHBQC4AQAuAAQKfykAAgUACAnUICIIAAIDAAUACAnUICIIAAIDAAAA.',
Gl='Glary:BAAALgAECgEJAQAAAA==.Glavendale:BAAALgADCgUJBQAAAA==.',
Go='Goatcheezey:BAAALgADCgYJDAAAAA==.Goblinsox:BAAALgAECgQJBAAAAA==.Goluck:BAAALgAECgEJAQAAAA==.Gordothe:BAAALgADCgUJBQABLgAECgUJBgACAAAAAA==.',
Gr='Grimel:BAAALgAECgQJCAABLgAECgYJEAACAAAAAA==.Grimghoul:BAAALgAECgQJCQABLgAECgYJEAACAAAAAA==.Grimgram:BAAALgAECgYJEAAAAA==.Gripyoulol:BAAALgAECgQJBQAAAA==.Grotelek:BAABLgAECn8hAAIdAAkJTRNXCQDSAQAdAAkJTRNXCQDSAQAAAA==.Grotret:BAAALgAECgIJAgAAAA==.Grouchy:BAAALgADCgMJAwAAAA==.Grumpywaltz:BAAALgAECgQJBAAAAA==.',
Gu='Gulimath:BAAALgAECgUJBgAAAA==.',
Ha='Halconotachi:BAABLgAECn84AAIGAAkJwBhsBwB7AgAGAAkJwBhsBwB7AgAAAA==.Hammerfoot:BAAALgAECgcJBwAAAA==.Haranir:BAAALgAECgEJAwAAAA==.Harcat:BAAALgAECggJEQAAAA==.Hartracks:BAAALgAECgUJBQAAAA==.Hatijo:BAAALgAECgYJBwAAAA==.Hawgbawl:BAAALgAECgYJEwAAAA==.Hawgdream:BAAALgAECgQJBwAAAA==.',
He='Hellequin:BAACLgAFFH8UAAIeAAUJBh5LAgBnAQAeAAUJBh5LAgBnAQAuAAQKfzkAAx4ACQkDItcAAAEDAB4ACQkDItcAAAEDAB8AAQkpA4cPACoAAAAA.Heyitzlock:BAAALgAECgYJCQAAAA==.Heyyitzrich:BAAALgAECgQJDQAAAA==.Heyyitzrichh:BAABLgAFFH8GAAIRAAMJhRVITQDpAAARAAMJhRVITQDpAAAAAA==.Heyytaco:BAAALgAECggJEgAAAA==.',
Hi='Hirogon:BAAALgAECgEJAwAAAA==.',
Ho='Hobb:BAABLgAECn8pAAIDAAkJcB4tEQCrAgADAAkJcB4tEQCrAgAAAA==.Hollinar:BAABLgAECn8YAAIJAAkJxxLtcADyAQAJAAkJxxLtcADyAQAAAA==.Holyfaux:BAAALgADCgYJBgAAAA==.Holysteel:BAAALgAECgEJAQAAAA==.Hondoe:BAAALgAECgQJBwAAAA==.',
Hu='Huntoor:BAAALgAECgEJAQABLgAECgYJBgACAAAAAA==.',
Ic='Icemark:BAACLgAFFH8FAAIJAAMJfxI1KwAJAQAJAAMJfxI1KwAJAQAuAAQKfx8AAgkABwkGHShXADMCAAkABwkGHShXADMCAAAA.',
Ih='Ihavecookies:BAAALgAECgEJAQAAAA==.',
Ij='Ijur:BAAALgAECgQJCAAAAA==.',
Ik='Ikayro:BAABLgAECn8cAAIJAAgJdx2AKgDJAgAJAAgJdx2AKgDJAgAAAA==.',
Il='Ilostmyphone:BAAALgAECgEJAQAAAA==.Ilovemysword:BAAALgAECgUJCQAAAA==.Iluvatar:BAABLgAECn8WAAMFAAgJzSAPCgBvAgAFAAgJzSAPCgBvAgAEAAIJyRLVUABPAAABLgAFFAEJAQACAAAAAA==.',
Im='Imagine:BAABLgAECn8UAAQVAAcJTg68EgBgAQAVAAcJTg68EgBgAQAUAAYJFganPgDwAAAWAAEJtgJiIQAhAAAAAA==.',
In='Infoxticated:BAAALgAECgEJAQAAAA==.',
Ir='Iratedemon:BAAALgAECgMJBAAAAA==.',
Ja='Jasmirangel:BAACLgAFFH8IAAIYAAMJmx+ZHQAcAQAYAAMJmx+ZHQAcAQAuAAQKf0IAAhgACAkDJXsEAE0DABgACAkDJXsEAE0DAAAA.',
Je='Jede:BAAALgADCgMJAwAAAA==.',
Ju='Juka:BAAALgAECggJEwAAAA==.Jukks:BAAALgAECgcJBwAAAA==.Juno:BAAALgADCgkJEwAAAA==.Justsumfoo:BAAALgAECgIJBAAAAA==.',
Ka='Kano:BAACLgAFFH8QAAIHAAQJKxswCwAIAQAHAAQJKxswCwAIAQAuAAQKfy4AAgcACQmIIz4EACADAAcACQmIIz4EACADAAAA.Katarm:BAAALgAECggJDAAAAA==.Katarru:BAAALgAECgYJDQAAAA==.Kataru:BAAALgADCgIJAgAAAA==.',
Ke='Kegpaw:BAAALgAECgMJBQAAAA==.',
Kh='Khory:BAAALgAECgUJDgAAAA==.',
Ki='Kirito:BAAALgADCgYJBgAAAA==.',
Kk='Kkiinnoopp:BAABLgAECn8jAAMHAAgJgRaaUwBeAQAGAAYJVhYrFQB1AQAHAAcJRBSaUwBeAQAAAA==.',
Ko='Korgigor:BAAALgAECgQJBwAAAA==.Kovu:BAAALgAECgcJEgAAAA==.',
Kr='Krisanthemum:BAAALgADCgcJCwAAAA==.Krystrasz:BAAALgAECgQJCwAAAA==.',
Kt='Kt:BAAALgADCgIJAgABLgAECgQJBAACAAAAAA==.Ktrogue:BAAALgAECgQJBAAAAA==.',
Ku='Kuraihikari:BAAALgAFFAEJAQAAAA==.Kustaa:BAAALgADCgkJCgABLgAECggJEwACAAAAAA==.',
La='Ladezar:BAAALgADCgcJDQAAAA==.Laissen:BAAALgAECgQJBgAAAA==.Lapsung:BAAALgAECgEJAwABLgAECgcJEgACAAAAAA==.Lattemocha:BAAALgAECggJEwAAAA==.',
Le='Lenden:BAAALgAECgMJAwAAAA==.Leprechaun:BAAALgADCgcJCQAAAA==.Leví:BAAALgADCgUJBQAAAA==.Leylas:BAAALgAECgEJAgAAAA==.',
Li='Lighthoove:BAAALgAECgcJBwAAAA==.Lilliaz:BAAALgAECgYJBwAAAA==.Linianna:BAAALgAECgYJEgAAAA==.Liriel:BAAALgAECgcJBgAAAA==.',
Lu='Ludlow:BAABLgAECn8XAAIHAAYJ8wXSdQAFAQAHAAYJ8wXSdQAFAQAAAA==.Lunastra:BAACLgAFFH8GAAIJAAIJNRYCcgCnAAAJAAIJNRYCcgCnAAAuAAQKfyUAAgkACAmiGSxKAMMBAAkACAmiGSxKAMMBAAEuAAQKBQkOAAIAAAAA.Luneztoprime:BAAALgAECgQJBgAAAA==.',
Ly='Lydarra:BAAALgAECgQJBgABLgAECgYJFQAgAFAZAA==.Lyiann:BAAALgADCggJEgAAAA==.Lyákadion:BAAALgAECgEJAQAAAA==.',
['Lâ']='Lâdypriest:BAAALgADCgUJBQAAAA==.',
Ma='Mafi:BAABLgAECn8UAAIHAAYJGRvKUABmAQAHAAYJGRvKUABmAQAAAA==.Maggore:BAAALgAECgIJBgAAAA==.Magikiwiks:BAAALgAECgEJAQAAAA==.Magsdk:BAAALgAFFAIJAgABLgAFFAYJHQAUAIogAA==.Mainlander:BAAALgAECgMJAwAAAA==.Malusmittens:BAAALgAECgQJBQABLgAFFAQJEAAHALEcAA==.Mantonso:BAABLgAECn8rAAIgAAgJ3CFyDQDqAgAgAAgJ3CFyDQDqAgAAAA==.Matt:BAACLgAFFH8IAAIYAAQJMQs7IwD9AAAYAAQJMQs7IwD9AAAuAAQKfygAAhgACQk6HGALANQCABgACQk6HGALANQCAAAA.',
Me='Meddicus:BAAALgAECgUJCAAAAA==.Meechydarko:BAAALgAECgUJBQABLgAECggJJAAHAP0gAA==.Megalomaniä:BAAALgADCgYJBgABLgAECgcJGwAPAKYYAA==.Megå:BAABLgAECn8bAAMPAAcJphiwDgAVAQARAAYJmBeTWwBbAQAPAAUJmBuwDgAVAQAAAA==.Mewtwô:BAAALgAECgYJBgAAAA==.',
Mi='Microbrew:BAAALgAECgMJBQAAAA==.Miezra:BAAALgAECgYJCAAAAA==.Mikah:BAAALgAECgYJDwAAAA==.',
Mo='Modayus:BAAALgAECgEJAQAAAA==.Mojomittens:BAACLgAFFH8QAAIHAAQJsRysDwBxAQAHAAQJsRysDwBxAQAuAAQKfyIAAwcABwlEJLIXAFYCAAcABwlEJLIXAFYCAAgABQnAFqRAAFcBAAAA.Monstermime:BAAALgAECgEJAQABLgAECgQJBAACAAAAAA==.Monstroqt:BAAALgADCgQJBAAAAA==.Morøs:BAAALgADCgYJBgAAAA==.Moxx:BAABLgAECn8ZAAIhAAkJtg4xJgA8AQAhAAkJtg4xJgA8AQAAAA==.',
Mu='Muffers:BAABLgAECn8mAAIhAAYJThMRLQAWAQAhAAYJThMRLQAWAQAAAA==.Muffpuff:BAAALgAECgQJBQAAAA==.Mutige:BAAALgADCgEJAQAAAA==.',
My='Mylotus:BAAALgAECgEJAgAAAA==.',
Na='Napkuntt:BAAALgAECgEJAQAAAA==.Napokin:BAAALgAFFAEJAgAAAA==.Napshade:BAABLgAECn8bAAMFAAcJMhsWIwBnAQAFAAYJSRwWIwBnAQALAAYJEhC7OgDOAAABLgAFFAEJAgACAAAAAA==.Natsuu:BAAALgAECgcJCgAAAA==.',
Nb='Nbayoungboyy:BAAALgADCgYJBgABLgAFFAUJFAAHAAMlAA==.',
Ne='Necroticoath:BAAALgAECgIJBgABLgAECgYJFAAPAL8gAA==.Neven:BAAALgAECgIJAgAAAA==.',
Ni='Nightor:BAAALgAECgEJAQAAAA==.Nikodemos:BAAALgAFFAYJFwAAAQ==.Nivahoof:BAAALgADCgEJAQAAAA==.',
No='Noc:BAABLgAECn8cAAMRAAgJVxIQSACRAQARAAgJVxIQSACRAQASAAUJNA+JLQAHAQABLgAECggJIQARAHgXAA==.Nomemage:BAAALgADCgEJAQAAAA==.',
Ob='Obe:BAAALgAFFAIJAgAAAA==.Obsidiangel:BAAALgADCggJEAAAAA==.',
Oh='Ohface:BAAALgAECgQJBQABLgAECgIJBgACAAAAAA==.',
Or='Oran:BAAALgAECggJEgAAAA==.Orctrax:BAABLgAECn8aAAMHAAgJVhHCUwBeAQAHAAgJVhHCUwBeAQAIAAEJBALAjgAsAAAAAA==.',
Os='Osheat:BAABLgAECn8jAAITAAkJ1x/XGQBzAgATAAkJ1x/XGQBzAgAAAA==.Osmodeus:BAAALgAECgUJCAAAAA==.',
Ou='Outplay:BAAALgADCgUJBQAAAA==.',
Ox='Oxheart:BAAALgAECgEJAQAAAA==.',
Pa='Paltis:BAAALgAECgQJBAAAAA==.Paltonso:BAAALgADCgkJCQAAAA==.Pandaari:BAABLgAECn8WAAIFAAgJFAQDOQDpAAAFAAgJFAQDOQDpAAAAAA==.Papaschristo:BAAALgADCgUJBQAAAA==.Papasdiablo:BAAALgAECgEJAgAAAA==.',
Pe='Persimmon:BAACLgAFFH8GAAIiAAMJ5h8TGAAdAQAiAAMJ5h8TGAAdAQAuAAQKfyAAAiIABwmTF5kfAMYBACIABwmTF5kfAMYBAAAA.Peyton:BAAALgAECgUJBwAAAA==.',
Ph='Philip:BAAALgADCgcJDAAAAA==.Phyrie:BAAALgAECgUJDAABLgAECgYJFQAgAFAZAA==.',
Pi='Pittpete:BAAALgAECgEJAQAAAA==.',
Ps='Psythera:BAAALgAECgIJBAABLgAECggJIgAFAPIcAA==.Psythern:BAAALgADCgYJCQABLgAECggJIgAFAPIcAA==.',
Pu='Punkybrewstr:BAABLgAECn8nAAMhAAgJHRD0MABjAQAhAAgJZAr0MABjAQABAAYJgg9WMgAGAQAAAA==.Pureshock:BAAALgAECggJDQAAAA==.Purpderf:BAAALgAFFAEJAQAAAA==.',
Pw='Pwnstar:BAAALgAECgQJCAAAAA==.',
Py='Pykei:BAAALgADCgcJDQAAAA==.Pyrri:BAABLgAECn8kAAQEAAkJQh3kDQBHAgAEAAgJaR7kDQBHAgALAAQJ4RXjUQDwAAAFAAMJdRQbQwC3AAAAAA==.Pyrria:BAAALgAECgcJBwABLgAECgkJJAAEAEIdAA==.',
Pz='Pznt:BAAALgAECgEJAQAAAA==.',
['Pé']='Péyton:BAAALgAECgYJBgAAAA==.',
['Pì']='Pì:BAAALgADCgEJAgAAAA==.',
['Pô']='Pôws:BAAALgAECgIJAwAAAA==.',
Qu='Quantonbomb:BAAALgAECgkJEgAAAA==.Quezera:BAAALgADCgYJBgAAAA==.',
Ra='Rabuf:BAAALgAECggJEwAAAA==.Raccoonadin:BAAALgADCgEJAQAAAA==.Radha:BAAALgAECgIJAgAAAA==.Ragingwater:BAAALgAECgYJEAAAAA==.Ranadheer:BAAALgAFFAEJAQAAAA==.Raspaigus:BAAALgAECgQJBAAAAA==.Ratfu:BAABLgAECn8UAAIhAAYJOQX/RwD1AAAhAAYJOQX/RwD1AAAAAA==.Raudson:BAABLgAECn8UAAIjAAkJDCJUAgATAwAjAAkJDCJUAgATAwAAAA==.',
Re='Redizle:BAACLgAFFH8XAAIEAAYJdhanCQDrAQAEAAYJdhanCQDrAQAuAAQKfycABAsACAnwHBkoAK8BAAQACAn6FuUbALcBAAsABgkyHBkoAK8BAAUABQnSEug2ADYBAAAA.Reginrune:BAAALgAECgkJEQAAAA==.Resonance:BAABLgAECn8WAAMNAAcJHBZ0KQBbAQANAAcJ9RV0KQBbAQAdAAMJZwykIwCeAAAAAA==.Restroll:BAAALgADCgQJBAAAAA==.',
Rh='Rhaigar:BAAALgAECgUJCQAAAA==.Rhónatar:BAAALgADCgQJBAAAAA==.',
Ri='Righteouscow:BAAALgAECgEJAQAAAA==.',
Ro='Rohdoog:BAABLgAECn8iAAIUAAgJahYVGwC5AQAUAAgJahYVGwC5AQAAAA==.Roundabugman:BAACLgAFFH8IAAINAAMJ3x1qKACfAAANAAMJ3x1qKACfAAAuAAQKfx8AAw0ACAmQGs0kAHoBAA0ACAmQGs0kAHoBAAwAAwmnFOF3ALIAAAAA.',
Rr='Rr:BAAALgAFFAEJAQAAAA==.',
Ru='Runedyu:BAAALgAECgYJCQAAAA==.',
Ry='Ryanno:BAABLgAECn8lAAIHAAkJSB8kEwB4AgAHAAkJSB8kEwB4AgAAAA==.Ryujinhalco:BAAALgADCgMJAwAAAA==.',
Sa='Sabim:BAAALgAECgEJAQAAAA==.Sahomi:BAABLgAECn8gAAMEAAkJFQh5KABSAQAEAAkJFQh5KABSAQALAAIJTQWUdwBMAAAAAA==.Salana:BAAALgADCgcJBwAAAA==.Samwise:BAAALgAECgYJCAAAAA==.Sarai:BAAALgADCgEJAQAAAA==.Sarcini:BAABLgAECn8pAAIjAAgJYBiLCQDqAQAjAAgJYBiLCQDqAQAAAA==.Satrina:BAACLgAFFH8FAAITAAMJNBPsZwDtAAATAAMJNBPsZwDtAAAuAAQKfyIAAhMACAmnItIhAEYCABMACAmnItIhAEYCAAAA.Savvy:BAAALgAECgQJBAAAAA==.',
Sc='Scrappy:BAAALgAECgEJAQAAAA==.',
Se='Sedna:BAAALgADCgYJBgABLgAECgYJCAACAAAAAA==.Selanthe:BAAALgAECgQJBgAAAA==.Seruk:BAAALgAECgEJBAAAAA==.Seventhghost:BAEALgAECgIJAgABLgAFFAQJCgAFADEQAA==.',
Sh='Shadowstorme:BAAALgAECgIJBQAAAA==.Shamander:BAABLgAECn8WAAIMAAgJsxhlIgD1AQAMAAgJsxhlIgD1AQAAAA==.Shamsham:BAAALgADCgcJDAAAAA==.Sharky:BAAALgADCgEJAQAAAA==.Shocka:BAAALgADCgcJCQAAAA==.Shokanki:BAAALgAECgYJCwAAAA==.',
Si='Sicara:BAABLgAECn8uAAIXAAkJNBbCLgDPAQAXAAkJNBbCLgDPAQAAAA==.Silentmage:BAAALgADCgcJCAAAAA==.Silentslock:BAAALgADCgYJBQAAAA==.Sillylilguy:BAACLgAFFH8JAAIdAAMJnBE3AwADAQAdAAMJnBE3AwADAQAuAAQKfxgAAh0ACAmEH+8EAMECAB0ACAmEH+8EAMECAAAA.Sivrogar:BAAALgAECgMJAwAAAA==.',
Sl='Slaik:BAAALgAECgQJCAAAAA==.Slander:BAACLgAFFH8VAAMTAAUJ0h41JABxAQATAAUJ0h41JABxAQAaAAEJAABePAAAAAAuAAQKfzcAAhMACQmQIYEUAJYCABMACQmQIYEUAJYCAAAA.',
So='Solemnograve:BAAALgAECgIJAgAAAA==.Somazugzug:BAABLgAECn8hAAIMAAkJZxdfLgDQAQAMAAkJZxdfLgDQAQAAAA==.Sothren:BAAALgAECgEJAgABLgADCgkJCQACAAAAAA==.',
Sp='Spacedguy:BAAALgADCgMJAwAAAA==.Spry:BAAALgAECgEJAQAAAA==.',
St='Staccato:BAAALgAECgEJAQAAAA==.',
Su='Sugar:BAABLgAECn8kAAMMAAgJshE9OQCdAQAMAAgJshE9OQCdAQANAAUJtw6oVgDrAAAAAA==.Sugars:BAAALgAECgUJAgAAAA==.Sulin:BAAALgADCgUJBwAAAA==.Sungôd:BAAALgADCgEJAQAAAA==.',
Sw='Swonks:BAAALgAECgMJAwAAAA==.Swyper:BAAALgAECgMJAwAAAA==.',
Sy='Synicism:BAAALgADCgcJDQAAAA==.',
Ta='Taintbubble:BAAALgAECgIJAgAAAA==.Tarnished:BAAALgADCgcJCAAAAA==.Tarquitus:BAACLgAFFH8RAAMXAAUJxg/1QQDeAAAXAAQJihT1QQDeAAAQAAIJeAS+CgCTAAAuAAQKfzwAAxcACAmUIHATAG8CABcACAnUH3ATAG8CABAACAm8F0sRAFUCAAAA.Tattoosguy:BAAALgADCgEJAQAAAA==.',
Te='Teef:BAABLgAECn8aAAIkAAYJyheXHwBIAQAkAAYJyheXHwBIAQAAAA==.Tellan:BAAALgADCgYJBgAAAA==.',
Th='Thanatös:BAABLgAECn8cAAMJAAgJbBZFTAC9AQAJAAgJbBZFTAC9AQAlAAQJrxRDDQD1AAAAAA==.Tharros:BAAALgAECgcJBwAAAA==.Thedarkkness:BAABLgAECn8lAAIaAAgJuhkJEgCiAQAaAAgJuhkJEgCiAQAAAA==.Thrasher:BAAALgAECgEJAwAAAA==.',
Ti='Tidalwave:BAACLgAFFH8HAAIMAAQJPxniGQA1AQAMAAQJPxniGQA1AQAuAAQKfysAAwwACAnNGNojAOwBAAwACAnNGNojAOwBAA0AAgltC5F9AC4AAAAA.Tidus:BAAALgAECgYJEQAAAA==.Tinytotem:BAAALgAECgEJBAAAAA==.Tissue:BAABLgAECn8XAAIQAAcJCArULABjAQAQAAcJCArULABjAQAAAA==.',
To='Toasted:BAAALgADCgYJCQAAAA==.Tobibi:BAAALgAECgQJBAABLgAECgYJFAAPAL8gAA==.Todo:BAAALgADCgQJBAAAAA==.Tolip:BAABLgAECn8qAAMYAAgJUQgrdgD1AAAYAAYJgAgrdgD1AAAmAAgJSgTVNwDpAAAAAA==.Tolipally:BAAALgAECgUJCQABLgAECggJKgAYAFEIAA==.Tolipicious:BAAALgADCgUJCQABLgAECggJKgAYAFEIAA==.',
Tr='Trauts:BAAALgAECgQJCAAAAA==.Treeadin:BAAALgAECggJEwAAAA==.Trollcula:BAAALgAECggJDgABLgAECggJHQAYALIQAA==.Truthwithin:BAAALgAECgUJEAAAAA==.',
Ts='Tsarrubus:BAABLgAECn8hAAIQAAkJcgmzGABiAQAQAAkJcgmzGABiAQAAAA==.',
Tu='Tula:BAAALgAECgUJCwAAAA==.Tusck:BAAALgAECgUJCAAAAA==.',
Tw='Twingert:BAAALgADCggJFAAAAA==.Twitch:BAAALgAECgYJEgAAAA==.',
Ty='Tyedyemess:BAAALgAECgMJAwAAAA==.',
['Tà']='Tàylor:BAABLgAECn8cAAIiAAkJOQu1OgCPAQAiAAkJOQu1OgCPAQAAAA==.',
Ub='Ubbaa:BAAALgAECgEJAQAAAA==.',
Ul='Ulghar:BAABLgAECn8dAAIgAAkJWyLbBADlAgAgAAkJWyLbBADlAgAAAA==.',
Ur='Ursock:BAAALgAECggJDgAAAA==.',
Uw='Uwuhshake:BAABLgAECn8iAAIYAAgJMCTlBQAvAwAYAAgJMCTlBQAvAwAAAA==.',
Va='Valdria:BAAALgAECgMJAwAAAA==.Valssien:BAAALgADCgkJCQAAAA==.Vanaria:BAAALgAECgQJBAAAAA==.Vanbrook:BAAALgAECgQJAgAAAA==.Vanden:BAAALgAECgYJDAAAAA==.Vanrion:BAAALgAFFAIJAwAAAA==.Varrodd:BAAALgADCgEJAQAAAA==.Vastextent:BAAALgADCgMJBAAAAA==.',
Ve='Velcro:BAAALgAECgYJEgAAAA==.Velsera:BAAALgAECgYJCAAAAA==.Velvet:BAAALgADCgQJCAAAAA==.Velyn:BAAALgAECgcJDwAAAA==.Velynara:BAAALgADCgIJAgABLgAECgYJCAACAAAAAA==.Vengefulcry:BAAALgAECgMJAwAAAA==.Vengefül:BAAALgADCgYJCAAAAA==.Vexara:BAAALgAECgQJBAAAAA==.',
Wa='Wanaaga:BAAALgAECggJDgAAAA==.',
We='Wedge:BAAALgAECgEJAQAAAA==.',
Wh='Whohaveaggro:BAAALgAECgEJAgAAAA==.',
Wi='Wilmington:BAAALgADCgIJAgAAAA==.Wino:BAAALgAECggJDQAAAA==.Wiqui:BAAALgAECgEJAwAAAA==.Witulow:BAABLgAECn8ZAAIcAAcJog8SNAAjAQAcAAcJog8SNAAjAQAAAA==.',
Wo='Wolfadin:BAACLgAFFH8FAAIDAAQJBQJ+HAC9AAADAAQJBQJ+HAC9AAAuAAQKfzcAAgMACQmNGXMeAFYCAAMACQmNGXMeAFYCAAAA.Woopac:BAABLgAECn8iAAIgAAgJhhxUEwAYAgAgAAgJhhxUEwAYAgAAAA==.',
Wu='Wulfharth:BAAALgAECgYJDwAAAA==.',
Xe='Xenophics:BAACLgAFFH8XAAMDAAUJTxToIwA9AQADAAUJTxToIwA9AQAiAAEJXwB9OgAxAAAuAAQKfzUAAwMACAk1HuQ2AOkBAAMABwkcIuQ2AOkBACMAAQnKBp5AACYAAAEuAAUUAwkFAAkAIgcA.Xenophicstwo:BAACLgAFFH8FAAIJAAMJIgfHMgDUAAAJAAMJIgfHMgDUAAAuAAQKfyIAAgkABgnyGj1lAHsBAAkABgnyGj1lAHsBAAAA.',
Xu='Xuen:BAAALgAECgcJEQABLgAECgkJJQADAGAjAA==.',
Ya='Yajsooblwj:BAAALgADCgMJAwAAAA==.',
Za='Zal:BAABLgAECn8fAAQiAAkJTxkpGgDyAQAiAAkJTxkpGgDyAQADAAcJbBZqbQBWAQAjAAIJDRVkNAB2AAAAAA==.Zanor:BAAALgAECgIJAgAAAA==.Zarranora:BAAALgAECgEJAQAAAA==.Zatannå:BAAALgADCgYJCQAAAA==.',
Ze='Zect:BAABLgAECn8kAAIJAAkJoQ4BTAC9AQAJAAkJoQ4BTAC9AQAAAA==.Zenshin:BAAALgAECgIJAgAAAA==.Zentaur:BAAALgAECgQJBAAAAA==.Zetzu:BAABLgAECn8WAAIgAAgJKxgzGQDjAQAgAAgJKxgzGQDjAQAAAA==.',
['Ål']='Ålucard:BAAALgAECggJEwAAAA==.',
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
