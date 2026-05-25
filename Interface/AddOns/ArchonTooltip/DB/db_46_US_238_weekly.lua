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

local lookup = {'Monk-Brewmaster','Hunter-BeastMastery','Hunter-Survival','Unknown-Unknown','Paladin-Retribution','Priest-Discipline','Priest-Shadow','Hunter-Marksmanship','Mage-Frost','Warrior-Protection','Priest-Holy','Shaman-Restoration','Shaman-Elemental','Druid-Guardian','DemonHunter-Havoc','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','DemonHunter-Devourer','Warrior-Fury','Druid-Restoration','DeathKnight-Frost','DeathKnight-Blood','Warrior-Arms','Warlock-Affliction','Monk-Mistweaver','Shaman-Enhancement','Rogue-Assassination','Rogue-Outlaw','Paladin-Holy','Druid-Balance','Monk-Windwalker','Paladin-Protection','Rogue-Subtlety','Mage-Arcane',}
local provider = {region='US',realm='Wildhammer',name='US',type='weekly',zone=46,date='2026-05-24',data={Ab='Abaddonaxx:BAAALgADCgYJBgAAAA==.',
Ac='Acesmash:BAABLgAECn8lAAIBAAkJGCKvBADhAgABAAkJGCKvBADhAgAAAA==.Ackrenezoth:BAAALgAECgQJBwAAAA==.',
Ad='Adymisk:BAAALgADCgEJAQAAAA==.',
Ag='Agorot:BAAALgAFFAEJAQAAAA==.',
Ak='Akadion:BAAALgADCgcJCgAAAA==.Akatali:BAAALgAECgQJBgAAAA==.',
Al='Aldannia:BAABLgAECn8VAAMCAAcJ4A/QVwBhAQACAAcJ8wzQVwBhAQADAAYJ7gwYLQAbAQAAAA==.Alextros:BAEALgAECgYJEQABLgAECgcJCgAEAAAAAA==.Alloren:BAAALgAECgQJBQAAAA==.Almond:BAAALgAECgEJAgAAAA==.',
Am='Amrax:BAABLgAECn8sAAIFAAgJYhL8WgCfAQAFAAgJYhL8WgCfAQAAAA==.Amynre:BAABLgAECn8aAAMGAAkJKRCfFQD5AQAGAAkJKRCfFQD5AQAHAAMJ6w33VABvAAAAAA==.',
An='Anarsa:BAAALgAECgUJCgAAAA==.Angstyboi:BAAALgAECgQJBAAAAA==.',
Aq='Aquabat:BAACLgAFFH8OAAQDAAQJ8hiMFAAEAQADAAMJdBeMFAAEAQACAAMJ0BfoYACUAAAIAAEJ8xvxJABVAAAuAAQKfyQABAMACAmyIYgKAF8CAAMACAmvH4gKAF8CAAgABwmrH38bAEwCAAIABQlwJRgoABgCAAAA.',
Ar='Arvyy:BAABLgAECn8mAAIJAAkJWBq8IwB0AgAJAAkJWBq8IwB0AgAAAA==.',
As='Ashbringer:BAACLgAFFH8HAAIFAAMJECTVKQA9AQAFAAMJECTVKQA9AQAuAAQKfyYAAgUACQlgI+APAM4CAAUACQlgI+APAM4CAAAA.',
At='Atria:BAABLgAECn8aAAIJAAgJZA/HxwBYAQAJAAgJZA/HxwBYAQAAAA==.Attia:BAAALgAECgcJEgAAAA==.',
Av='Avaris:BAAALgADCgIJAgAAAA==.Avatarbambi:BAAALgADCgUJAgAAAA==.',
Ax='Axtar:BAABLgAECn8lAAIKAAkJ6RiQDAD9AQAKAAkJ6RiQDAD9AQAAAA==.',
Ay='Ayyitzrich:BAAALgADCgQJBAAAAA==.',
Ba='Babarazzar:BAAALgADCgYJBgAAAA==.Baladoria:BAABLgAECn80AAILAAkJWyF/AwA+AwALAAkJWyF/AwA+AwAAAA==.Bananabowman:BAAALgAECgEJAgAAAA==.Barrels:BAABLgAECn8fAAMCAAkJlB0zHgBIAgACAAgJ3xszHgBIAgADAAkJnBViEAATAgAAAA==.Bartab:BAABLgAECn81AAMMAAkJehpDEACmAgAMAAkJehpDEACmAgANAAEJEwPOnQAfAAABLgAECgkJMQAOABEcAA==.Baruku:BAAALgAFFAEJAQAAAA==.Bastadi:BAAALgAFFAIJAgAAAA==.',
Be='Beastling:BAAALgAECgYJCgAAAA==.Beau:BAABLgAECn8zAAIPAAkJzCQWAgAoAwAPAAkJzCQWAgAoAwAAAA==.Beauwi:BAAALgAECgQJBgABLgAECgkJMwAPAMwkAA==.',
Bi='Bigshekels:BAAALgAECgEJAQAAAA==.Bigulsworth:BAAALgADCgcJCAAAAA==.',
Bl='Blackadder:BAAALgAECgcJEgAAAA==.Blawkk:BAAALgAECgYJBgAAAA==.Blenton:BAAALgAECgEJAQAAAA==.Bloodussy:BAAALgADCgUJBQAAAA==.Bluck:BAAALgADCgcJEQAAAA==.Blueeyesdrag:BAAALgADCgEJAQAAAA==.Blueombre:BAAALgAECgEJAQAAAA==.',
Bo='Boing:BAAALgAECgUJCgAAAA==.Bombur:BAABLgAECn8tAAMQAAgJVRsaNADzAQAQAAgJVRsaNADzAQARAAEJAAAdZABGAAAAAA==.Bosstradamus:BAAALgAECgYJBgABLgAFFAIJAgAEAAAAAA==.Boston:BAAALgAECggJEwAAAA==.Bottles:BAAALgAFFAIJAwAAAA==.',
Br='Bratva:BAAALgAECgcJAQAAAA==.',
Bu='Bubagony:BAAALgADCgQJBAABLgAFFAQJEAASAPAgAA==.Bubbells:BAAALgADCgEJAQAAAA==.Bullmedic:BAAALgADCgYJBgAAAA==.Burakku:BAABLgAECn8VAAQTAAcJEhnTGgDzAQATAAcJEhnTGgDzAQAUAAUJJwgCMQDpAAAVAAEJAAC0PgA1AAABLgAFFAQJFQAGAMchAA==.Burguerkiing:BAAALgADCgMJAwAAAA==.Burph:BAAALgADCggJCAAAAA==.Buttonsmash:BAAALgAECgcJEAABLgAFFAYJGgAUAMgSAA==.Buzzkill:BAAALgADCgUJCAAAAA==.',
['Bâ']='Bâbyrage:BAAALgADCgcJDwAAAA==.',
Ca='Cairen:BAABLgAECn8gAAIWAAkJqBvRJAAfAgAWAAkJqBvRJAAfAgAAAA==.Calzraxx:BAAALgAECgkJEgAAAA==.Carstaller:BAAALgAECgMJAwAAAA==.Cartons:BAAALgAECggJDQAAAA==.',
Cc='Ccaan:BAAALgAECgkJEQAAAA==.Ccian:BAAALgAECgQJBAAAAA==.',
Ce='Celinn:BAABLgAECn8tAAMLAAkJDx1sCQCwAgALAAkJDx1sCQCwAgAGAAEJuxkbXABKAAAAAA==.',
Ch='Chadgar:BAAALgADCgUJBwAAAA==.Chalupacabra:BAAALgADCgIJAgAAAA==.Chappie:BAAALgAECgEJAQABLgAFFAQJDgADAPIYAA==.Charliek:BAABLgAFFH8FAAIXAAMJIQOULwCrAAAXAAMJIQOULwCrAAAAAA==.Cherches:BAAALgADCgEJAQAAAA==.Childish:BAAALgAECgYJDQAAAA==.Chimalma:BAAALgAFFAIJAwAAAA==.Chiqui:BAAALgAECgEJAgAAAA==.',
Cl='Clarabow:BAAALgAFFAIJAwAAAA==.Closure:BAABLgAECn8YAAIYAAkJJSPbDADWAgAYAAkJJSPbDADWAgAAAA==.Cloudsx:BAAALgADCgMJAwAAAA==.',
Co='Coatlicue:BAABLgAECn8UAAMLAAkJFx+hEQBVAgALAAgJRSGhEQBVAgAHAAUJZBTFMQBXAQABLgAFFAIJAwAEAAAAAA==.Coby:BAAALgAECgcJEgAAAA==.Coffins:BAAALgAECgYJEQABLgAECggJDQAEAAAAAA==.Covell:BAAALgAECgUJBwAAAA==.',
Cr='Crates:BAAALgAECgUJCAABLgAECggJDQAEAAAAAA==.Crimsonmagic:BAAALgAECgEJAgAAAA==.Crosswalkk:BAAALgADCgMJAwAAAA==.Crygore:BAAALgAECgQJCgABLgAECgIJBgAEAAAAAA==.',
Cy='Cypherrellik:BAABLgAECn8cAAMPAAkJhRByGACLAQAPAAkJhRByGACLAQAWAAIJHgIg2QA9AAAAAA==.',
Da='Daktok:BAAALgADCgQJBAAAAA==.Damer:BAAALgADCgkJFgAAAA==.Damues:BAAALgAECggJDwAAAA==.Danaric:BAAALgAECgMJBgAAAA==.Dannyphentom:BAABLgAECn8XAAQSAAYJVxU8fwBCAQASAAYJVxU8fwBCAQAZAAMJxhfnGgCyAAAaAAMJmA4qNgCQAAAAAA==.Dargar:BAAALgAECgEJAQAAAA==.Darkling:BAABLgAECn8dAAIPAAcJoB1VDwD/AQAPAAcJoB1VDwD/AQAAAA==.Darknyss:BAAALgADCgUJBQAAAA==.',
De='Dedeye:BAAALgADCgMJAwAAAA==.Dekumime:BAAALgAECgQJBAAAAA==.Demandred:BAAALgAECgkJEwAAAA==.Demongrass:BAACLgAFFH8HAAIWAAMJdh3bQwDyAAAWAAMJdh3bQwDyAAAuAAQKfzIAAhYACAkyIMokAB8CABYACAkyIMokAB8CAAAA.Denaric:BAAALgAECgYJEAAAAA==.Derty:BAAALgAECgUJBgAAAA==.',
Di='Diviñehymn:BAAALgAECgYJDQAAAA==.',
Do='Donet:BAAALgADCgEJAQAAAA==.Doppy:BAAALgADCgYJBgAAAA==.',
Dr='Dragondeezz:BAAALgAECgIJBAABLgAECgIJBgAEAAAAAA==.Dragondznuts:BAACLgAFFH8aAAIUAAYJyBL3CQDMAQAUAAYJyBL3CQDMAQAuAAQKfzcABBQACQkhHC4IAFACABQACQkhHC4IAFACABMAAgnoHl9XAK0AABUAAglHCJUaAFwAAAAA.Draxtos:BAEALgAECgcJCgAAAA==.Dreamevil:BAAALgAECgkJBgAAAA==.Drroxso:BAAALgAECgQJBAAAAA==.Dríppy:BAAALgADCgYJBgAAAA==.',
Ea='Eazybake:BAAALgADCgEJAQAAAA==.',
Ei='Eilerra:BAABLgAECn8iAAIJAAcJDh0WQwD5AQAJAAcJDh0WQwD5AQAAAA==.Eithan:BAAALgADCgMJAwAAAA==.',
El='Elementony:BAABLgAECn85AAINAAkJpBB0IwD1AQANAAkJpBB0IwD1AQAAAA==.Elkdruid:BAABLgAECn8eAAMYAAgJxBCXTwBnAQAYAAgJxBCXTwBnAQAOAAEJQAzlNgAbAAAAAA==.Elladamri:BAAALgAECgEJAQAAAA==.Elodi:BAAALgAECgEJAQAAAA==.',
Em='Emberglow:BAAALgAECgcJEgAAAA==.Empyrean:BAAALgADCgQJBQAAAA==.Emylia:BAAALgAECgcJEAAAAA==.',
Er='Eresdelor:BAABLgAECn8YAAMKAAkJlRO5EgCaAQAKAAkJzhG5EgCaAQAbAAQJLA4XJwC2AAAAAA==.Erre:BAABLgAECn8mAAIQAAkJ5h5JFgCKAgAQAAkJ5h5JFgCKAgAAAA==.',
Es='Esdeáth:BAAALgADCgEJAQAAAA==.Estia:BAAALgAECgIJAgABLgAECgUJEQAEAAAAAA==.',
Ev='Evoktor:BAAALgAECgEJAQAAAA==.',
Fa='Facasdeath:BAAALgAECgYJDAAAAA==.Failure:BAEBLgAECn8ZAAIDAAkJ+hQcDQD6AQADAAkJ+hQcDQD6AQAAAA==.Farmtoon:BAAALgAECgYJDQAAAA==.',
Fe='Feardapain:BAACLgAFFH8RAAIQAAQJLxd+MgBFAQAQAAQJLxd+MgBFAQAuAAQKfzsABBAACQk5IhUPAAEDABAACAk5IhUPAAEDABEAAQkAADFcAFoAABwAAQkAAP84AAwAAAAA.Feardatpain:BAAALgAFFAEJAQAAAA==.Fellyn:BAAALgADCggJCwAAAA==.',
Ff='Ff:BAABLgAFFH8JAAIJAAMJwACchACcAAAJAAMJwACchACcAAAAAA==.',
Fl='Flar:BAAALgAECgUJCgAAAA==.Flixie:BAABLgAECn8XAAIMAAYJ2iHBHAA8AgAMAAYJ2iHBHAA8AgABLgAFFAUJHgAdADMVAA==.Flyingcow:BAAALgAECgIJAgAAAA==.',
Fo='Foenix:BAAALgADCgYJBgAAAA==.Foxoffire:BAAALgAECgEJAgAAAA==.Foxymoron:BAAALgAECgcJCwAAAA==.Fozzi:BAABLgAECn8oAAIdAAkJQSEOBgAaAwAdAAkJQSEOBgAaAwAAAA==.',
Fr='Freakazoid:BAABLgAECn8wAAIHAAkJjx2rDQBYAgAHAAkJjx2rDQBYAgAAAA==.Fritark:BAAALgAECgcJBwABLgAECgcJDQAEAAAAAA==.Fritzyp:BAAALgAECgcJDQAAAA==.Frogzqc:BAAALgAECgEJAgAAAA==.Frostyburn:BAAALgAECgYJEQAAAA==.Frozenrage:BAAALgADCgcJCwAAAA==.',
['Fë']='Fëanor:BAAALgAECggJBQAAAA==.',
Ga='Gabos:BAAALgADCgEJAQAAAA==.Garayice:BAAALgADCgIJAgAAAA==.Garycoleman:BAAALgADCgEJAQAAAA==.Gaxxen:BAAALgAECgUJBQAAAA==.',
Ge='Gena:BAAALgADCgcJCAAAAA==.Geörge:BAACLgAFFH8XAAIHAAYJSxtxBwCrAQAHAAYJSxtxBwCrAQAuAAQKfykAAgcACAnVICIIAAIDAAcACAnVICIIAAIDAAAA.',
Gh='Ghostyganja:BAAALgAECgEJAQAAAA==.',
Gl='Glary:BAAALgAECgEJAQAAAA==.Glavendale:BAAALgADCgUJBQAAAA==.',
Go='Goatcheezey:BAAALgADCgYJDAAAAA==.Goblinsox:BAAALgAECgQJBAAAAA==.Goluck:BAAALgAECgEJAQAAAA==.Gordothe:BAAALgADCgUJBQABLgAECgUJBgAEAAAAAA==.',
Gr='Grimel:BAAALgAECgQJCAABLgAECgYJEAAEAAAAAA==.Grimghoul:BAAALgAECgQJCQABLgAECgYJEAAEAAAAAA==.Grimgram:BAAALgAECgYJEAAAAA==.Gripyoulol:BAAALgAECgQJBQAAAA==.Grotelek:BAABLgAECn8hAAIeAAkJTRN3CwDLAQAeAAkJTRN3CwDLAQAAAA==.Grotret:BAAALgAECgIJAgAAAA==.Grouchy:BAAALgADCgMJAwAAAA==.Grumpywaltz:BAAALgAECgQJBAAAAA==.',
Gu='Gulimath:BAAALgAECgUJBgAAAA==.',
Ha='Halconotachi:BAABLgAECn9BAAIDAAkJRRoHCACFAgADAAkJRRoHCACFAgAAAA==.Hammerfoot:BAAALgAECgcJBwAAAA==.Haranir:BAAALgAECgEJAwAAAA==.Harcat:BAAALgAECggJEQAAAA==.Hartracks:BAAALgAECgUJBQAAAA==.Hatijo:BAAALgAECgYJBwAAAA==.Hawgbawl:BAABLgAECn8bAAIXAAYJTRwcKgCMAQAXAAYJTRwcKgCMAQAAAA==.Hawgdream:BAAALgAECgYJDQAAAA==.',
He='Hellequin:BAACLgAFFH8VAAIfAAYJIRo0AQC3AQAfAAYJIRo0AQC3AQAuAAQKfzkAAx8ACQkDIiMBAO8CAB8ACQkDIiMBAO8CACAAAQkpA4cPACoAAAAA.Henkojin:BAAALgADCgYJBgAAAA==.Heyitzlock:BAAALgAECgYJCQAAAA==.Heyyitzrich:BAAALgAECgQJDQAAAA==.Heyyitzrichh:BAABLgAFFH8HAAIQAAMJzBbyVQDyAAAQAAMJzBbyVQDyAAAAAA==.Heyytaco:BAAALgAECggJEgAAAA==.',
Hi='Hiels:BAAALgAECgcJBwAAAA==.Hirogon:BAAALgAECgEJAwAAAA==.',
Ho='Hobb:BAABLgAECn8pAAIFAAkJcB6lFQCmAgAFAAkJcB6lFQCmAgAAAA==.Holenmymuff:BAAALgADCgUJBQAAAA==.Hollinar:BAABLgAECn8YAAIJAAkJxxLtcADyAQAJAAkJxxLtcADyAQAAAA==.Holyfaux:BAAALgADCgYJBgAAAA==.Holysteel:BAAALgAECgEJAQAAAA==.Hondoe:BAAALgAECgQJBwAAAA==.Hordecow:BAAALgAECgEJAQABLgAFFAEJAgAEAAAAAA==.',
Hu='Huntoor:BAAALgAECgEJAQABLgAECgYJBgAEAAAAAA==.',
Ic='Icemark:BAACLgAFFH8FAAIJAAMJfxI1KwAJAQAJAAMJfxI1KwAJAQAuAAQKfx8AAgkABwkGHShXADMCAAkABwkGHShXADMCAAAA.',
Ih='Ihavecookies:BAAALgAECgEJAQAAAA==.',
Ij='Ijur:BAAALgAECgQJCAABLgAECgUJBgAEAAAAAA==.',
Ik='Ikayro:BAABLgAECn8cAAIJAAgJdx2AKgDJAgAJAAgJdx2AKgDJAgAAAA==.',
Il='Ilostmyphone:BAAALgAECgEJAQAAAA==.Ilovemysword:BAAALgAECgUJCQAAAA==.Iluvatar:BAABLgAECn8WAAMHAAgJzSC0DABnAgAHAAgJzSC0DABnAgAGAAIJwxLkWgBOAAABLgAFFAEJAQAEAAAAAA==.',
Im='Imagine:BAABLgAECn8UAAQUAAcJTg4FFQBbAQAUAAcJTg4FFQBbAQATAAYJFganPgDwAAAVAAEJtgIGJQAhAAAAAA==.',
In='Infoxticated:BAAALgAECgEJAQAAAA==.',
Ir='Iratedemon:BAAALgAECgMJBAAAAA==.',
Ja='Jadedways:BAAALgAECgEJAQAAAA==.Jasmirangel:BAACLgAFFH8LAAIYAAMJNCDsIQAeAQAYAAMJNCDsIQAeAQAuAAQKf0QAAhgACAkDJWoFAEsDABgACAkDJWoFAEsDAAAA.',
Je='Jede:BAAALgADCgMJAwAAAA==.',
Ju='Juka:BAABLgAECn8UAAIMAAkJGQekSQBZAQAMAAkJGQekSQBZAQAAAA==.Jukks:BAAALgAECgcJBwAAAA==.Juno:BAAALgADCgkJEwAAAA==.Justsumfoo:BAAALgAECgIJBAAAAA==.',
Ka='Kano:BAACLgAFFH8RAAICAAQJKxswCwAIAQACAAQJKxswCwAIAQAuAAQKfy4AAgIACQmII3AGAA8DAAIACQmII3AGAA8DAAAA.Katarm:BAAALgAECgkJDwAAAA==.Katarru:BAAALgAECgYJDQAAAA==.Kataru:BAAALgADCgIJAgAAAA==.',
Ke='Kegpaw:BAAALgAECgMJBQAAAA==.',
Kh='Khory:BAAALgAECgUJEQAAAA==.',
Ki='Kirito:BAAALgADCgYJBgAAAA==.',
Kk='Kkiinnoopp:BAABLgAECn8jAAMCAAgJiBbxYQBXAQADAAYJVhYrFQB1AQACAAcJSxTxYQBXAQAAAA==.',
Ko='Korgigor:BAAALgAECgQJBwAAAA==.Kovu:BAAALgAECgcJEgAAAA==.',
Kr='Krisanthemum:BAAALgADCgcJCwAAAA==.Krystrasz:BAAALgAECgQJCwAAAA==.',
Kt='Kt:BAAALgADCgIJAgABLgAECgQJBAAEAAAAAA==.Ktrogue:BAAALgAECgQJBAAAAA==.',
Ku='Kuailiang:BAAALgAECgcJCQAAAA==.Kuraihikari:BAAALgAFFAEJAQAAAA==.Kustaa:BAAALgADCgkJCgABLgAECggJGwAhAGoVAA==.',
La='Ladezar:BAAALgADCgcJDQAAAA==.Laissen:BAAALgAECgYJCAAAAA==.Lapsung:BAAALgAECgEJAwABLgAECgcJEgAEAAAAAA==.Lattemocha:BAABLgAECn8bAAMYAAgJjh2eMADpAQAYAAYJ+RqeMADpAQAiAAgJnBHKJAB6AQAAAA==.',
Le='Lenden:BAAALgAECgMJAwAAAA==.Leprechaun:BAAALgADCgcJCQAAAA==.Leví:BAAALgADCgUJBQAAAA==.Leylas:BAAALgAECgEJAgAAAA==.',
Li='Lighthoove:BAAALgAECgcJBwAAAA==.Lilliaz:BAAALgAECgYJBwAAAA==.Linianna:BAAALgAECgYJEgAAAA==.Liriel:BAAALgAECgcJBwAAAA==.',
Lu='Ludlow:BAABLgAECn8bAAICAAcJ4gZniwD6AAACAAcJ4gZniwD6AAAAAA==.Lunastra:BAACLgAFFH8IAAIJAAMJ7A8RbADhAAAJAAMJ7A8RbADhAAAuAAQKfyUAAgkACAmiGStXAL0BAAkACAmiGStXAL0BAAEuAAQKBQkRAAQAAAAA.Luneztoprime:BAAALgAECgQJBgAAAA==.',
Ly='Lydarra:BAAALgAECgQJBwABLgAECgYJFQAXAFAZAA==.Lyiann:BAAALgADCggJEgAAAA==.Lyákadion:BAAALgAECgEJAQAAAA==.',
['Lâ']='Lâdypriest:BAAALgADCgUJBQAAAA==.',
Ma='Mafi:BAABLgAECn8VAAICAAcJYhklSgCYAQACAAcJYhklSgCYAQAAAA==.Maggore:BAAALgAECgIJBgAAAA==.Magikiwiks:BAAALgAECgEJAQAAAA==.Magsdk:BAAALgAFFAIJAgABLgAFFAYJHgATAIogAA==.Mainlander:BAAALgAECgMJAwAAAA==.Malbogea:BAAALgAECgEJAQAAAA==.Malusmittens:BAAALgAECgQJBQABLgAFFAQJEQACAN4hAA==.Mantonso:BAABLgAECn8vAAIXAAgJViJyDQDqAgAXAAgJViJyDQDqAgAAAA==.Matt:BAACLgAFFH8JAAIYAAQJMQsxKQD5AAAYAAQJMQsxKQD5AAAuAAQKfyoAAhgACQkiHQMLAPECABgACQkiHQMLAPECAAAA.',
Me='Meddicus:BAAALgAECgUJCAAAAA==.Meechydarko:BAAALgAECgUJBQABLgAECggJKgACAP0gAA==.Megalomaniä:BAAALgADCgYJBgABLgAECgcJHgAcAKYYAA==.Megorice:BAAALgADCgEJAQAAAA==.Megå:BAABLgAECn8eAAMcAAcJphjOEQAUAQAQAAYJmBfkaABXAQAcAAUJmBvOEQAUAQAAAA==.Mewtwô:BAAALgAECgYJBwAAAA==.',
Mi='Microbrew:BAAALgAECgMJBQAAAA==.Miezra:BAAALgAECgYJCAAAAA==.Mikah:BAAALgAECgYJDwAAAA==.',
Mo='Modayus:BAAALgAECgEJAQAAAA==.Mojomittens:BAACLgAFFH8RAAICAAQJ3iGcFABxAQACAAQJ3iGcFABxAQAuAAQKfyIAAwIABwlEJAQeAEkCAAIABwlEJAQeAEkCAAgABQnAFqRAAFcBAAAA.Monstermime:BAAALgAECgIJAgABLgAECgQJBAAEAAAAAA==.Monstroqt:BAAALgADCgQJBAAAAA==.Morøs:BAAALgADCgYJBgAAAA==.Moxx:BAABLgAECn8ZAAIjAAkJtw5AKgA/AQAjAAkJtw5AKgA/AQAAAA==.',
Mu='Muffers:BAABLgAECn8sAAIjAAcJ4xHsKABIAQAjAAcJ4xHsKABIAQAAAA==.Muffpuff:BAAALgAECgQJBQAAAA==.Mutige:BAAALgADCgEJAQAAAA==.',
My='Mylotus:BAAALgAECgQJBQAAAA==.',
Na='Napkuntt:BAAALgAECgEJAQAAAA==.Napokin:BAAALgAFFAEJAgAAAA==.Napshade:BAABLgAECn8bAAMHAAcJMxtYKQBfAQAHAAYJSRxYKQBfAQALAAYJEhCqPwDNAAABLgAFFAEJAgAEAAAAAA==.Natsuu:BAAALgAECgcJDAAAAA==.',
Nb='Nbayoungboyy:BAAALgADCgYJBgABLgAFFAUJGAACAD4lAA==.',
Ne='Necroticoath:BAAALgAECgIJBgABLgAFFAIJAgAEAAAAAA==.Neven:BAAALgAECgIJAgAAAA==.',
Ni='Nightor:BAAALgAECgEJAQAAAA==.Nikodemos:BAAALgAFFAYJFwAAAQ==.Nivahoof:BAAALgADCgEJAQAAAA==.',
No='Noc:BAABLgAECn8fAAMQAAgJyRNmRAC5AQAQAAgJyRNmRAC5AQARAAUJNA+JLQAHAQABLgAECggJJQAQAN4bAA==.Nomemage:BAAALgADCgEJAQAAAA==.',
Ob='Obe:BAAALgAFFAIJAgAAAA==.Obsidiangel:BAAALgADCggJEAAAAA==.',
Oh='Ohface:BAAALgAECgQJBgABLgAECgIJBgAEAAAAAA==.',
Or='Oran:BAAALgAECggJEgAAAA==.Orctrax:BAABLgAECn8aAAMCAAgJVRHMYQBXAQACAAgJVRHMYQBXAQAIAAEJBALAjgAsAAAAAA==.Oricale:BAAALgADCgYJBgAAAA==.',
Os='Osheat:BAACLgAFFH8FAAISAAMJJg1ffgDaAAASAAMJJg1ffgDaAAAuAAQKfyMAAhIACQndH0ogAGgCABIACQndH0ogAGgCAAAA.Osmodeus:BAAALgAECgUJCAAAAA==.',
Ou='Outplay:BAAALgADCgUJBQAAAA==.',
Ox='Oxheart:BAAALgAECgEJAQAAAA==.',
Pa='Paltis:BAAALgAECgQJBAAAAA==.Paltonso:BAAALgADCgkJCQAAAA==.Pandaari:BAABLgAECn8WAAIHAAgJFASJPgDvAAAHAAgJFASJPgDvAAAAAA==.Papaschristo:BAAALgADCgUJBQAAAA==.Papasdiablo:BAAALgAECgEJAgAAAA==.Parprapa:BAAALgADCgMJAwAAAA==.',
Pe='Persimmon:BAACLgAFFH8KAAIhAAQJHxo8FABWAQAhAAQJHxo8FABWAQAuAAQKfyAAAiEABwmTF4EkAL8BACEABwmTF4EkAL8BAAAA.Peyton:BAAALgAECgUJBwAAAA==.',
Ph='Philip:BAAALgADCgcJDAAAAA==.Phyrie:BAAALgAECgUJDwABLgAECgYJFQAXAFAZAA==.',
Pi='Pittpete:BAAALgAECgEJAQAAAA==.',
Pl='Plaguepapi:BAAALgAFFAEJAQAAAA==.',
Ps='Psythera:BAAALgAECgIJBAABLgAECggJIgAHAPIcAA==.Psythern:BAAALgADCgYJCQABLgAECggJIgAHAPIcAA==.',
Pu='Punkybrewstr:BAABLgAECn8vAAMBAAgJPxZUHwCPAQABAAcJURZUHwCPAQAjAAgJZAr0MABjAQAAAA==.Pureshock:BAAALgAECggJDQAAAA==.Purpderf:BAAALgAFFAEJAQAAAA==.',
Pw='Pwnstar:BAAALgAECgQJCAAAAA==.',
Py='Pykei:BAAALgADCgcJDQAAAA==.Pyrri:BAABLgAECn8kAAQGAAkJQh1vEABBAgAGAAgJaB5vEABBAgALAAQJ4RXjUQDwAAAHAAMJdRRzSwC1AAAAAA==.Pyrria:BAAALgAECgcJDgABLgAECgkJJAAGAEIdAA==.',
Pz='Pznt:BAAALgAECgEJAQAAAA==.',
['Pé']='Péyton:BAAALgAECgYJBwAAAA==.',
['Pì']='Pì:BAAALgADCgEJAgAAAA==.',
['Pô']='Pôws:BAAALgAECgIJAwAAAA==.',
Qu='Quantonbomb:BAAALgAECgkJEwAAAA==.Quezera:BAAALgADCgYJBgAAAA==.',
Ra='Rabuf:BAABLgAECn8bAAMhAAgJahUSGQAaAgAhAAgJahUSGQAaAgAFAAYJawtsvwAIAQAAAA==.Raccoonadin:BAAALgADCgEJAQAAAA==.Radha:BAAALgAECgIJAgABLgAFFAQJEAASAPAgAA==.Ragingwater:BAAALgAECgYJEAAAAA==.Ranadheer:BAAALgAFFAEJAQAAAA==.Raspaigus:BAAALgAECgQJBAAAAA==.Ratfu:BAABLgAECn8UAAIjAAYJOQX/RwD1AAAjAAYJOQX/RwD1AAAAAA==.Raudson:BAABLgAECn8UAAIkAAkJDCJUAgATAwAkAAkJDCJUAgATAwAAAA==.',
Re='Redizle:BAACLgAFFH8YAAIGAAYJCxdzDADzAQAGAAYJCxdzDADzAQAuAAQKfycABAsACAnwHBkoAK8BAAYACAn6FuUbALcBAAsABgkyHBkoAK8BAAcABQnSEug2ADYBAAAA.Reginrune:BAAALgAECgkJEwAAAA==.Resonance:BAABLgAECn8WAAMNAAcJHBZSMABUAQANAAcJ9RVSMABUAQAeAAMJZwykIwCeAAAAAA==.Restroll:BAAALgADCgQJBAAAAA==.',
Rh='Rhaigar:BAAALgAECgUJCQAAAA==.Rhónatar:BAAALgADCgQJBAAAAA==.',
Ri='Righteouscow:BAAALgAECgEJAQAAAA==.',
Ro='Rohdoog:BAABLgAECn8rAAITAAkJLhcDEQA/AgATAAkJLhcDEQA/AgAAAA==.Roundabugman:BAACLgAFFH8LAAINAAMJrh2oHwAAAQANAAMJrh2oHwAAAQAuAAQKfyMAAw0ACAmQGpMqAHQBAA0ACAmQGpMqAHQBAAwAAwmnFOF3ALIAAAAA.',
Rr='Rr:BAAALgAFFAEJAQAAAA==.',
Ru='Runedyu:BAAALgAECgYJDQAAAA==.',
Ry='Ryanno:BAACLgAFFH8FAAICAAIJhBQIVwCmAAACAAIJhBQIVwCmAAAuAAQKfyoAAgIACQkwIO0UAIMCAAIACQkwIO0UAIMCAAAA.Ryujinhalco:BAAALgADCgMJAwAAAA==.',
Sa='Sabim:BAAALgAECgEJAQAAAA==.Sahomi:BAACLgAFFH8FAAIGAAMJwwY0KADDAAAGAAMJwwY0KADDAAAuAAQKfyIAAwYACQkUCHkoAFIBAAYACQkUCHkoAFIBAAsAAglNBZR3AEwAAAAA.Salana:BAAALgADCgcJBwAAAA==.Samwise:BAAALgAECgYJCAAAAA==.Sarai:BAAALgADCgEJAQAAAA==.Sarcini:BAABLgAECn8uAAIkAAkJXhvjBQBnAgAkAAkJXhvjBQBnAgAAAA==.Satrina:BAACLgAFFH8JAAISAAQJ0BINRgA9AQASAAQJ0BINRgA9AQAuAAQKfyQAAhIACAmrImQpADsCABIACAmrImQpADsCAAAA.Savvy:BAAALgAECgQJBAAAAA==.',
Sc='Scrappy:BAAALgAECgEJAQAAAA==.',
Se='Sedna:BAAALgADCgYJBgABLgAECgYJCAAEAAAAAA==.Selanthe:BAAALgAECgQJBgAAAA==.Seruk:BAAALgAECgEJBAAAAA==.Seventhghost:BAEALgAECgIJAgABLgAFFAQJCgAHADEQAA==.',
Sh='Shadowstorme:BAAALgAECgIJBQAAAA==.Shamander:BAABLgAECn8YAAIMAAkJqhfeHwAnAgAMAAkJqhfeHwAnAgAAAA==.Shamsham:BAAALgADCgcJDAAAAA==.Sharky:BAAALgADCgEJAQAAAA==.Shocka:BAAALgADCgcJCQAAAA==.Shokanki:BAAALgAECgYJCwAAAA==.',
Si='Sicara:BAABLgAECn8uAAIWAAkJQha5NQDRAQAWAAkJQha5NQDRAQAAAA==.Silentmage:BAAALgADCgcJCAAAAA==.Silentslock:BAAALgADCgYJBQAAAA==.Sillylilguy:BAACLgAFFH8JAAIeAAMJnBE3AwADAQAeAAMJnBE3AwADAQAuAAQKfxgAAh4ACAmEH+8EAMECAB4ACAmEH+8EAMECAAAA.Sivrogar:BAAALgAECgMJAwAAAA==.',
Sl='Slaik:BAAALgAECgUJCgAAAA==.Slander:BAACLgAFFH8VAAMSAAUJ0h51NABdAQASAAUJ0h51NABdAQAaAAEJAABDRwAAAAAuAAQKfzcAAhIACQmQIbAZAI0CABIACQmQIbAZAI0CAAAA.',
So='Solemnograve:BAAALgAECgIJAgAAAA==.Somazugzug:BAABLgAECn8jAAIMAAkJHxlfLgDQAQAMAAkJHxlfLgDQAQAAAA==.Sothren:BAAALgAECgEJAgABLgADCgkJCQAEAAAAAA==.',
Sp='Spacedguy:BAAALgADCgMJAwAAAA==.Spry:BAAALgAECgEJAQAAAA==.',
St='Staccato:BAAALgAECgEJAQAAAA==.Stepbrother:BAAALgAECgQJBgABLgAECggJKgACAP0gAA==.',
Su='Sugar:BAABLgAECn8lAAMMAAgJshE9OQCdAQAMAAgJshE9OQCdAQANAAUJtw6oVgDrAAAAAA==.Sugars:BAAALgAECgUJAgAAAA==.Sulin:BAAALgADCgUJBwAAAA==.Sungôd:BAAALgADCgEJAQAAAA==.',
Sw='Swonks:BAAALgAECgMJAwAAAA==.Swyper:BAAALgAECgMJAwAAAA==.',
Sy='Synicism:BAAALgADCgcJDQAAAA==.',
Ta='Taintbubble:BAAALgAECgMJBAAAAA==.Tarnished:BAAALgADCgcJCAAAAA==.Tarquitus:BAACLgAFFH8SAAMWAAYJ+A4LMgAnAQAWAAUJVxILMgAnAQAPAAIJeAS+CgCTAAAuAAQKfzwAAxYACAmXIKoXAG0CABYACAnWH6oXAG0CAA8ACAm8F0sRAFUCAAAA.Tattoosguy:BAAALgADCgEJAQAAAA==.',
Te='Teef:BAABLgAECn8cAAIlAAcJFxX9HQB9AQAlAAcJFxX9HQB9AQAAAA==.Tellan:BAAALgADCgcJBwAAAA==.',
Th='Thanatös:BAABLgAECn8cAAMJAAgJbBa7WAC5AQAJAAgJbBa7WAC5AQAmAAQJrxRDDQD1AAAAAA==.Tharros:BAAALgAECgcJCwAAAA==.Thedarkkness:BAABLgAECn8lAAIaAAgJuhmnFQCSAQAaAAgJuhmnFQCSAQAAAA==.Thrasher:BAAALgAECgEJAwAAAA==.',
Ti='Tidalwave:BAACLgAFFH8HAAIMAAQJPxkrIQAuAQAMAAQJPxkrIQAuAQAuAAQKfy0AAwwACQnFGUQaAE4CAAwACQnFGUQaAE4CAA0AAgltC66LAC4AAAAA.Tidus:BAAALgAECgYJEQAAAA==.Tinytotem:BAAALgAECgEJBAAAAA==.Tissue:BAABLgAECn8XAAIPAAcJCArULABjAQAPAAcJCArULABjAQAAAA==.',
To='Toasted:BAAALgADCgYJCQAAAA==.Tobibi:BAAALgAECgYJBwABLgAFFAIJAgAEAAAAAA==.Todo:BAAALgADCgQJBAAAAA==.Tolip:BAABLgAECn8rAAMYAAgJUQgrdgD1AAAYAAYJgAgrdgD1AAAiAAgJSgRhPQDsAAAAAA==.Tolipally:BAAALgAECgUJCwABLgAECggJKwAYAFEIAA==.Tolipicious:BAAALgADCgUJCQABLgAECggJKwAYAFEIAA==.',
Tr='Trauts:BAAALgAECgQJCAAAAA==.Treeadin:BAABLgAECn8bAAIkAAgJfQ6wGwAPAQAkAAgJfQ6wGwAPAQAAAA==.Trollcula:BAAALgAECggJDgABLgAECggJHgAYAMQQAA==.Truthwithin:BAAALgAECgUJEQAAAA==.',
Ts='Tsarrubus:BAABLgAECn8hAAIPAAkJcwnIHABdAQAPAAkJcwnIHABdAQAAAA==.',
Tu='Tula:BAAALgAECgUJCwAAAA==.Tusck:BAAALgAECgYJDQAAAA==.',
Tw='Twingert:BAAALgADCggJFAAAAA==.Twitch:BAAALgAECgYJEwAAAA==.',
Ty='Tyedyemess:BAAALgAECgMJAwAAAA==.',
['Tà']='Tàylor:BAABLgAECn8cAAIhAAkJOQu1OgCPAQAhAAkJOQu1OgCPAQAAAA==.',
Ub='Ubbaa:BAAALgAECgEJAQAAAA==.',
Ul='Ulghar:BAABLgAECn8gAAIXAAkJCiO2BAD9AgAXAAkJCiO2BAD9AgAAAA==.',
Ur='Ursock:BAAALgAECggJDgAAAA==.',
Uw='Uwuhshake:BAABLgAECn8qAAIYAAgJRSR6BgA4AwAYAAgJRSR6BgA4AwAAAA==.',
Va='Valdria:BAAALgAECgMJAwAAAA==.Valssien:BAAALgADCgkJCQAAAA==.Vanaria:BAAALgAECgQJBAAAAA==.Vanbrook:BAAALgAECgQJAgAAAA==.Vanden:BAAALgAECgYJDAAAAA==.Vanrion:BAAALgAFFAIJAwAAAA==.Varrodd:BAAALgADCgEJAQAAAA==.Vastextent:BAAALgADCgMJBAAAAA==.',
Ve='Velcro:BAAALgAECgYJEgAAAA==.Velsera:BAAALgAECgYJCAAAAA==.Velvet:BAAALgADCgQJCAAAAA==.Velyn:BAAALgAECgcJDwAAAA==.Velynara:BAAALgADCgIJAgABLgAECgYJCAAEAAAAAA==.Vengefulcry:BAAALgAECgMJAwAAAA==.Vengefül:BAAALgADCgYJCAAAAA==.Vexara:BAAALgAECgQJBAAAAA==.',
Wa='Wanaaga:BAAALgAECggJDgAAAA==.',
We='Wedge:BAAALgAECgEJAQAAAA==.',
Wh='Whohaveaggro:BAAALgAECgEJAgAAAA==.',
Wi='Wilmington:BAAALgADCgIJAgAAAA==.Wino:BAABLgAECn8VAAMlAAgJlxBkGQCoAQAlAAgJdhBkGQCoAQAfAAEJTxE5IAA+AAAAAA==.Wiqui:BAAALgAECgEJBAAAAA==.Witulow:BAABLgAECn8gAAMdAAgJ3w2XPQAnAQAdAAcJog+XPQAnAQABAAcJeQSQQQDZAAAAAA==.',
Wo='Wolfadin:BAACLgAFFH8GAAIFAAQJBQJ+HAC9AAAFAAQJBQJ+HAC9AAAuAAQKfzcAAgUACQmNGTAkAFUCAAUACQmNGTAkAFUCAAAA.Woopac:BAABLgAECn8iAAIXAAgJihxwFwAQAgAXAAgJihxwFwAQAgAAAA==.',
Wu='Wulfharth:BAAALgAECgYJDwAAAA==.',
Xe='Xenophics:BAACLgAFFH8YAAMFAAYJGxOhEwCJAQAFAAYJGxOhEwCJAQAhAAEJXwB+QgAqAAAuAAQKfzYAAwUACAk1Hhc3AEYCAAUABwkcIhc3AEYCACQAAQnKBgVIACYAAAEuAAUUAwkIAAkATQgA.Xenophicstwo:BAACLgAFFH8IAAIJAAMJTQjHMgDUAAAJAAMJTQjHMgDUAAAuAAQKfyYAAgkABglMG+VuAIIBAAkABglMG+VuAIIBAAAA.',
Xu='Xuen:BAAALgAFFAEJAQABLgAFFAMJBwAFABAkAA==.',
Ya='Yajsooblwj:BAAALgADCgMJAwAAAA==.',
Za='Zal:BAABLgAECn8fAAQhAAkJTxlwHgDrAQAhAAkJTxlwHgDrAQAFAAcJbBaegABPAQAkAAIJDRVkNAB2AAAAAA==.Zanor:BAAALgAECgIJAgAAAA==.Zarranora:BAAALgAECgEJAQAAAA==.Zatannå:BAAALgADCgYJCQAAAA==.',
Ze='Zect:BAABLgAECn8sAAIJAAkJUROuPQALAgAJAAkJUROuPQALAgAAAA==.Zenshin:BAAALgAECgIJAgAAAA==.Zentaur:BAAALgAECgQJBAAAAA==.Zetzu:BAABLgAECn8WAAIXAAgJLRi9HgDXAQAXAAgJLRi9HgDXAQAAAA==.',
['Ål']='Ålucard:BAABLgAECn8XAAMHAAgJVhjEGQDUAQAHAAgJVhjEGQDUAQAGAAEJqAcNbQAnAAAAAA==.',
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
