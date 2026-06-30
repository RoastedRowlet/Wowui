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

local lookup = {'Monk-Brewmaster','Hunter-BeastMastery','Hunter-Survival','Unknown-Unknown','Paladin-Retribution','Priest-Discipline','Priest-Shadow','Hunter-Marksmanship','Mage-Frost','Priest-Holy','Paladin-Protection','Warrior-Protection','DeathKnight-Unholy','Shaman-Restoration','Shaman-Elemental','Druid-Feral','DemonHunter-Havoc','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Monk-Mistweaver','DemonHunter-Devourer','Warrior-Arms','Warrior-Fury','Druid-Restoration','DeathKnight-Frost','DeathKnight-Blood','Druid-Guardian','Druid-Balance','Shaman-Enhancement','Rogue-Assassination','Rogue-Outlaw','Paladin-Holy','Monk-Windwalker','Rogue-Subtlety','Mage-Arcane',}
local provider = {region='US',realm='Wildhammer',name='US',type='weekly',zone=46,date='2026-06-28',data={Aa='Aayrawn:BAAALgAECggJCQAAAA==.',
Ab='Abaddonaxx:BAAALgADCgYJBgAAAA==.',
Ac='Aceshaman:BAAALgAECggJCgAAAA==.Acesmash:BAABLgAECn8lAAIBAAkJGCJaBgDWAgABAAkJGCJaBgDWAgAAAA==.Ackrenezoth:BAAALgAECgQJBwAAAA==.',
Ad='Adymisk:BAAALgADCgEJAQAAAA==.',
Ag='Agorot:BAAALgAFFAEJAQAAAA==.',
Ak='Akadion:BAAALgADCgcJCgAAAA==.Akatali:BAAALgAECgQJBgAAAA==.',
Al='Aldannia:BAABLgAECn8VAAMCAAcJ4A/QVwBhAQACAAcJ8wzQVwBhAQADAAYJ7gwINAAQAQAAAA==.Alextros:BAEALgAECgYJEQABLgAECgcJCwAEAAAAAA==.Alloren:BAAALgAECgQJBgAAAA==.Almond:BAAALgAECgEJAgAAAA==.',
Am='Amaranthe:BAAALgAECgEJAQAAAA==.Amrax:BAABLgAECn80AAIFAAkJpRVbPgAMAgAFAAkJpRVbPgAMAgAAAA==.Amynre:BAABLgAECn8aAAMGAAkJKRCfFQD5AQAGAAkJKRCfFQD5AQAHAAMJ6w33VABvAAAAAA==.',
An='Anarsa:BAAALgAECgUJCgAAAA==.Angstyboi:BAAALgAECgQJBAAAAA==.',
Aq='Aquabat:BAACLgAFFH8cAAQIAAQJ8h17EQBMAQAIAAQJ4xt7EQBMAQADAAMJdBcgCACtAAACAAMJ0BcGeQCmAAAuAAQKfyYABAMACQlHIv8FAMQCAAMACQmFIP8FAMQCAAgABwmrH38bAEwCAAIABQlwJRgoABgCAAAA.Aquabàt:BAAALgAFFAQJBAABLgAFFAQJHAAIAPIdAA==.',
Ar='Arvyy:BAACLgAFFH8FAAIJAAMJ6w6gIgDRAAAJAAMJ6w6gIgDRAAAuAAQKfyYAAgkACQlYGu8sAGUCAAkACQlYGu8sAGUCAAAA.',
As='Ashbringer:BAACLgAFFH8PAAIFAAMJECTJQwAjAQAFAAMJECTJQwAjAQAuAAQKfyYAAgUACQlgI8EWALoCAAUACQlgI8EWALoCAAAA.',
At='Atria:BAACLgAFFH8IAAIJAAQJtQxBdgDvAAAJAAQJtQxBdgDvAAAuAAQKfycAAgkACAlfF99FAAkCAAkACAlfF99FAAkCAAAA.Attia:BAABLgAECn8bAAMKAAkJVBYWHQDdAQAKAAkJVBYWHQDdAQAHAAIJDRVbaAB8AAAAAA==.',
Av='Avaris:BAAALgADCgIJAgAAAA==.Avatarbambi:BAAALgADCgUJAgAAAA==.',
Aw='Away:BAAALgAECgYJBgABLgAECgkJJwALAFoQAA==.',
Ax='Axtar:BAABLgAECn8nAAIMAAkJvhu7CwAyAgAMAAkJvhu7CwAyAgAAAA==.',
Ay='Ayyitzrich:BAAALgADCgQJBAAAAA==.',
Ba='Babarazzar:BAAALgADCgYJBgAAAA==.Baladoria:BAACLgAFFH8NAAIKAAUJVxJsFwACAQAKAAUJVxJsFwACAQAuAAQKfzsAAgoACQkuIhYEAEUDAAoACQkuIhYEAEUDAAAA.Baldkrank:BAAALgAECgEJAQAAAA==.Bananabowman:BAAALgAECgEJAgAAAA==.Barrels:BAABLgAECn8lAAMCAAkJux7JIgBZAgACAAgJLx3JIgBZAgADAAkJnBUNFAAFAgABLgAFFAIJBQANAP4PAA==.Bartab:BAABLgAECn87AAMOAAkJLR7vDADxAgAOAAkJLR7vDADxAgAPAAEJEwPwvwAeAAABLgAECgkJPwAQADEhAA==.Baruku:BAAALgAFFAEJAQAAAA==.Bashfulwaltz:BAAALgAECggJCQAAAA==.Bastadi:BAABLgAFFH8HAAMOAAIJJyMpTADBAAAOAAIJJyMpTADBAAAPAAEJSB4KGABcAAAAAA==.Bazuul:BAAALgAECgEJAQAAAA==.',
Be='Bearemy:BAAALgAECgcJBwAAAA==.Beastling:BAAALgAECgYJDwAAAA==.Beau:BAACLgAFFH8MAAIRAAQJvyNBBwCTAQARAAQJvyNBBwCTAQAuAAQKfzcAAhEACQmFJX0CAD0DABEACQmFJX0CAD0DAAAA.Beauchi:BAAALgAECgUJBQABLgAFFAQJDAARAL8jAA==.Beauwi:BAAALgAECgQJBgABLgAFFAQJDAARAL8jAA==.Beldin:BAAALgAECgEJAQAAAA==.',
Bi='Bigshekels:BAAALgAECgEJAQAAAA==.Bigulsworth:BAAALgADCgcJCAAAAA==.',
Bl='Blackadder:BAAALgAECgcJEgAAAA==.Blawkk:BAAALgAECgYJBgAAAA==.Blenton:BAAALgAECgEJAQAAAA==.Blessthem:BAAALgAECgEJAQAAAA==.Bloodussy:BAAALgADCgUJBQAAAA==.Bluck:BAAALgADCgcJEQAAAA==.Blueeyesdrag:BAAALgADCgEJAQAAAA==.Blueombre:BAAALgAECgEJAQAAAA==.',
Bo='Boing:BAAALgAFFAIJAgAAAA==.Boltngo:BAAALgADCgIJAgAAAA==.Bombur:BAACLgAFFH8HAAISAAMJVxbBbwDiAAASAAMJVxbBbwDiAAAuAAQKfy8AAxIACQlSHGYlAEgCABIACQlSHGYlAEgCABMAAQkAAB1kAEYAAAAA.Bosstradamus:BAAALgAFFAEJAQABLgAFFAIJAgAEAAAAAA==.Boston:BAAALgAECggJEwAAAA==.Bottles:BAABLgAFFH8FAAINAAIJ/g9E4gCDAAANAAIJ/g9E4gCDAAAAAA==.',
Br='Braesong:BAAALgAECgIJBAAAAA==.Bratva:BAAALgAECgkJCgAAAA==.',
Bu='Bubagony:BAABLgAFFH8FAAMUAAQJUgkmBACQAAAUAAIJmRAmBACQAAASAAMJmALEJgCPAAABLgAFFAUJEwANAPAgAA==.Bubbells:BAAALgADCgEJAQAAAA==.Buffmedaddy:BAAALgAECgIJAgAAAA==.Bullmedic:BAAALgADCgYJBgAAAA==.Burakku:BAABLgAECn8VAAQVAAcJEhnTGgDzAQAVAAcJEhnTGgDzAQAWAAUJJwgCMQDpAAAXAAEJAAC0PgA1AAABLgAFFAYJDQAYACIYAA==.Burguerkiing:BAAALgADCgMJAwAAAA==.Burph:BAAALgADCggJCAAAAA==.Buttonsmash:BAAALgAECgcJEAABLgAFFAgJJwAWAAgSAA==.Buzzkill:BAAALgAECgUJBQAAAA==.',
['Bâ']='Bâbyrage:BAAALgADCgcJDwAAAA==.',
Ca='Cairen:BAABLgAECn8lAAIZAAkJMh6dIQBMAgAZAAkJMh6dIQBMAgAAAA==.Calzraxx:BAABLgAECn8UAAQaAAcJdxLhMAAEAQAaAAcJPwvhMAAEAQAMAAQJOhOULQDVAAAbAAMJ7ASyjQCIAAAAAA==.Carstaller:BAAALgAECgQJBAAAAA==.Cartons:BAABLgAECn8VAAIFAAgJySAwEwD5AgAFAAgJySAwEwD5AgABLgAFFAIJBQANAP4PAA==.',
Cc='Ccaan:BAAALgAECgkJEQAAAA==.Ccian:BAAALgAECgQJBAAAAA==.',
Ce='Celinn:BAACLgAFFH8JAAMKAAQJrA+/IQCtAAAKAAMJ0hO/IQCtAAAGAAIJzAVSQgBxAAAuAAQKfzgAAwoACQkPHZMMAJ0CAAoACQkPHZMMAJ0CAAYABwnLFJAgAMkBAAAA.',
Ch='Chadgar:BAAALgADCgUJBwAAAA==.Chalupacabra:BAAALgADCgIJAgAAAA==.Chappie:BAAALgAECgEJAQABLgAFFAQJHAAIAPIdAA==.Charliek:BAABLgAFFH8IAAIbAAQJQA2KKQAPAQAbAAQJQA2KKQAPAQAAAA==.Cherches:BAAALgADCgEJAQAAAA==.Childish:BAAALgAECgYJDQAAAA==.Chimalma:BAAALgAFFAIJBAAAAA==.Chingoblingo:BAAALgAECgEJAgAAAA==.Chiqui:BAAALgAECgEJAgAAAA==.Chorr:BAAALgAFFAEJAQABLgAFFAIJBAAEAAAAAA==.',
Cl='Clarabow:BAAALgAFFAIJAwAAAA==.Closure:BAABLgAECn8YAAIcAAkJJSPbDADWAgAcAAkJJSPbDADWAgAAAA==.Cloudsx:BAAALgADCgMJAwAAAA==.',
Co='Coatlicue:BAABLgAECn8UAAMKAAkJFx+hEQBVAgAKAAgJRSGhEQBVAgAHAAUJZBTFMQBXAQABLgAFFAIJBAAEAAAAAA==.Coby:BAABLgAECn8XAAIYAAgJrCQjCQAJAwAYAAgJrCQjCQAJAwAAAA==.Coffins:BAAALgAECgYJEQABLgAFFAIJBQANAP4PAA==.Corgartah:BAAALgAECgMJAwAAAA==.Covell:BAAALgAECgcJDAAAAA==.',
Cr='Crates:BAAALgAECgUJCAABLgAFFAIJBQANAP4PAA==.Crimsonmagic:BAAALgAECgEJAgAAAA==.Crosswalkk:BAAALgADCgMJAwAAAA==.Crygore:BAAALgAECgQJCgABLgAECgIJBgAEAAAAAA==.',
Cu='Curonconagua:BAAALgAECgMJAwAAAA==.',
Cy='Cypherrellik:BAABLgAECn8cAAMRAAkJhRCjHwB9AQARAAkJhRCjHwB9AQAZAAIJHgIg2QA9AAAAAA==.',
['Cò']='Còrgi:BAAALgAECgEJAwABLgAECgkJPQANAIAhAA==.',
Da='Daktok:BAAALgADCgQJBAAAAA==.Damer:BAAALgADCgkJFgAAAA==.Damues:BAAALgAECggJDwAAAA==.Danaric:BAAALgAECgMJBgAAAA==.Dannyphentom:BAABLgAECn8XAAQNAAYJVxUEmAA5AQANAAYJVxUEmAA5AQAdAAMJxhdPJACtAAAeAAMJmA4qNgCQAAAAAA==.Dargar:BAAALgAECgEJAQAAAA==.Darkling:BAABLgAECn8dAAIRAAcJoB03FADwAQARAAcJoB03FADwAQAAAA==.Darknyss:BAAALgAECgIJAgAAAA==.',
De='Deathfortres:BAAALgAECgcJDwAAAA==.Dedeye:BAAALgADCgMJAwAAAA==.Deidara:BAAALgAECgYJAQAAAA==.Dekumime:BAAALgAECgkJDQAAAA==.Demandred:BAAALgAECgkJEwAAAA==.Demongrass:BAACLgAFFH8PAAIZAAUJMRo9DgA8AQAZAAUJMRo9DgA8AQAuAAQKfzIAAhkACAkyIL8rABkCABkACAkyIL8rABkCAAAA.Denaric:BAAALgAECgYJEAAAAA==.Derty:BAAALgAFFAIJAwAAAA==.',
Di='Diviñehymn:BAAALgAECgcJDwAAAA==.',
Do='Donet:BAAALgADCgEJAQAAAA==.Doodaad:BAAALgAECgEJAgAAAA==.Doppy:BAAALgADCgYJBgAAAA==.Doublerack:BAAALgAFFAEJAQABLgAECgIJBgAEAAAAAA==.',
Dr='Dragondeezz:BAAALgAECgIJBAABLgAECgIJBgAEAAAAAA==.Dragondznuts:BAACLgAFFH8nAAIWAAgJCBJJCwDzAQAWAAgJCBJJCwDzAQAuAAQKfz0ABBYACQluHuYFALACABYACQluHuYFALACABUAAgnoHjdlAKsAABcAAglHCJ0fAFUAAAAA.Draxtos:BAEALgAECgcJCwAAAA==.Dreamevil:BAAALgAECgkJBgAAAA==.Drroxso:BAAALgAECgQJBAAAAA==.Dríppy:BAAALgAECgYJCgAAAA==.',
Ea='Eazybake:BAAALgADCgEJAQAAAA==.',
Ei='Eilerra:BAABLgAECn8rAAIJAAgJBCE6IgCUAgAJAAgJBCE6IgCUAgAAAA==.',
El='Elementony:BAABLgAECn85AAIPAAkJpBB0IwD1AQAPAAkJpBB0IwD1AQAAAA==.Elkdruid:BAABLgAECn8eAAMcAAgJxBCXTwBnAQAcAAgJxBCXTwBnAQAfAAEJQAzlNgAbAAABLgAFFAUJDQACAJAVAA==.Elladamri:BAAALgAECgEJAQAAAA==.Elodi:BAAALgAECgEJAQAAAA==.',
Em='Emberglow:BAAALgAECgcJEgAAAA==.Empyrean:BAAALgADCgQJBQAAAA==.Emylia:BAAALgAECgcJEAAAAA==.',
Er='Eresdelor:BAABLgAECn8YAAMMAAkJlRPeFwCBAQAMAAkJzhHeFwCBAQAaAAQJLA4XJwC2AAAAAA==.Erre:BAABLgAECn8mAAISAAkJ5h5uHAB6AgASAAkJ5h5uHAB6AgAAAA==.',
Es='Esdeáth:BAAALgADCgEJAQAAAA==.Estia:BAAALgAECgcJCwABLgAFFAIJBAAEAAAAAA==.',
Ev='Evoktor:BAAALgAECgEJAQAAAA==.',
Ex='Exxitwound:BAAALgAECgEJAgAAAA==.',
Fa='Facasdeath:BAAALgAECgYJDAAAAA==.Failure:BAEBLgAECn8cAAIDAAkJ+hQcDQD6AQADAAkJ+hQcDQD6AQABLgAFFAUJEQABACsYAA==.Farmtoon:BAAALgAECgYJDQAAAA==.Fartbroknvis:BAAALgAFFAIJAgAAAA==.',
Fe='Feardapain:BAACLgAFFH8SAAISAAQJLxe7SwAvAQASAAQJLxe7SwAvAQAuAAQKfz0ABBIACQk5IhUPAAEDABIACAk5IhUPAAEDABMAAQkAADFcAFoAABQAAQkAAP84AAwAAAAA.Feardatpain:BAAALgAFFAEJAQAAAA==.Fellyn:BAAALgADCggJCwAAAA==.',
Ff='Ff:BAABLgAFFH8LAAIJAAMJwADqoQCLAAAJAAMJwADqoQCLAAAAAA==.',
Fl='Flar:BAAALgAFFAEJAQAAAA==.Flixie:BAABLgAECn8gAAMOAAkJQSH6BQBRAwAOAAkJQSH6BQBRAwAPAAEJByCmiQBdAAABLgAFFAcJLgAYAAcXAA==.Flyingcow:BAAALgAECgkJDwAAAA==.',
Fo='Foenix:BAAALgADCgYJBgAAAA==.Foxoffire:BAAALgAECgMJBwAAAA==.Foxu:BAAALgAECgcJBwAAAA==.Foxymoron:BAAALgAECgcJCwAAAA==.Fozzi:BAABLgAECn8oAAIYAAkJQSFHCAAYAwAYAAkJQSFHCAAYAwAAAA==.',
Fr='Freakazoid:BAABLgAECn8wAAIHAAkJjx3bEQBGAgAHAAkJjx3bEQBGAgAAAA==.Fritark:BAAALgAECgcJBwABLgAECgkJFAAgACcXAA==.Fritzyp:BAABLgAECn8UAAMgAAkJJxd6OwAkAQAgAAcJBxl6OwAkAQAcAAUJtAgRgQC4AAAAAA==.Frogzqc:BAAALgAECgEJAgAAAA==.Frostyburn:BAAALgAECgYJEQAAAA==.Frozenrage:BAAALgADCgcJCwAAAA==.',
['Fë']='Fëanor:BAAALgAECggJDAAAAA==.',
Ga='Gabos:BAAALgADCgEJAQAAAA==.Garayice:BAAALgADCgIJAgAAAA==.Garycoleman:BAAALgAECgQJBAAAAA==.Gaxxen:BAAALgAECgUJBQAAAA==.',
Ge='Gena:BAAALgADCgcJCAAAAA==.Geörge:BAACLgAFFH8bAAIHAAgJWxdHBgAWAgAHAAgJWxdHBgAWAgAuAAQKfy8AAgcACAlVISIIAAIDAAcACAlVISIIAAIDAAAA.',
Gh='Ghostyganja:BAAALgAECgQJBAABLgAFFAMJBQAVAHYWAA==.',
Gi='Giratiña:BAAALgAECgEJAgABLgAFFAIJAwAEAAAAAA==.',
Gl='Glary:BAAALgAECgEJAQAAAA==.Glavendale:BAAALgADCgUJBQAAAA==.',
Go='Goatcheezey:BAAALgADCgYJDAAAAA==.Goblinsox:BAAALgAECgQJBAAAAA==.Goluck:BAAALgAECgEJAQAAAA==.Gordothe:BAAALgADCgUJBQABLgAECgUJBgAEAAAAAA==.',
Gr='Gremfrost:BAACLgAFFH8OAAIJAAMJ0gklKQC1AAAJAAMJ0gklKQC1AAAuAAQKfyEAAgkACQmkEQhHAAYCAAkACQmkEQhHAAYCAAAA.Grimel:BAAALgAECgQJCAABLgAECgYJEAAEAAAAAA==.Grimghoul:BAAALgAECgQJCQABLgAECgYJEAAEAAAAAA==.Grimgram:BAAALgAECgYJEAAAAA==.Gripyoulol:BAAALgAECgQJBQAAAA==.Grotelek:BAABLgAECn8hAAIhAAkJTRPjDgDCAQAhAAkJTRPjDgDCAQAAAA==.Grotret:BAAALgAECgIJAgAAAA==.Grouchy:BAAALgADCgMJAwAAAA==.Grumpywaltz:BAAALgAECgQJBAAAAA==.',
Gu='Gulimath:BAAALgAECgUJBgAAAA==.',
['Gà']='Gàrrosh:BAAALgADCgQJBAAAAA==.',
Ha='Haedrath:BAAALgAECgEJAgABLgAECggJKwAJAAQhAA==.Hahoa:BAAALgAFFAMJAwABLgAFFAIJBAAEAAAAAA==.Halconotachi:BAABLgAECn9FAAIDAAkJiRqkCgB0AgADAAkJiRqkCgB0AgAAAA==.Halcosutchi:BAAALgAECgQJBAAAAA==.Hammerfoot:BAAALgAFFAEJAgAAAA==.Haranir:BAAALgAECgcJCgAAAA==.Harcat:BAABLgAECn8dAAMIAAkJGBXyCwCnAQAIAAkJGBXyCwCnAQADAAEJYQGqbAAcAAAAAA==.Hartracks:BAAALgAECgUJBQAAAA==.Hatijo:BAAALgAECgYJBwAAAA==.Hawgbawl:BAABLgAECn8kAAIbAAkJnRvKGAAoAgAbAAkJnRvKGAAoAgAAAA==.Hawgdream:BAAALgAECgcJEgAAAA==.',
He='Hellequin:BAACLgAFFH8ZAAIiAAcJJhcrAQD3AQAiAAcJJhcrAQD3AQAuAAQKfzkAAyIACQkDIj0BACsDACIACQkDIj0BACsDACMAAQkpA4cPACoAAAAA.Henkojin:BAAALgADCgYJBgAAAA==.Heyitzlock:BAAALgAECgYJCQAAAA==.Heyyitzrich:BAAALgAECgQJDQAAAA==.Heyyitzrichh:BAABLgAFFH8KAAISAAMJzBambwDjAAASAAMJzBambwDjAAAAAA==.Heyytaco:BAAALgAECggJEgAAAA==.',
Hi='Hiels:BAAALgAECgcJBwAAAA==.Hirogon:BAAALgAECgEJAwAAAA==.',
Ho='Hobb:BAABLgAECn8pAAIFAAkJcB5sHgCQAgAFAAkJcB5sHgCQAgAAAA==.Holenmymuff:BAAALgADCgUJBQAAAA==.Hollinar:BAABLgAECn8YAAIJAAkJxxLtcADyAQAJAAkJxxLtcADyAQAAAA==.Holyfaux:BAAALgADCgYJBgAAAA==.Holysteel:BAAALgAECgIJAwAAAA==.Hondoe:BAAALgAECgQJCAAAAA==.Hordecow:BAAALgAECgIJAgABLgAFFAEJAgAEAAAAAA==.Hornhelm:BAAALgAECgYJDQAAAA==.',
Hu='Huntoor:BAAALgAECgEJAQABLgAECgYJBgAEAAAAAA==.',
Ic='Icemark:BAACLgAFFH8FAAIJAAMJfxI1KwAJAQAJAAMJfxI1KwAJAQAuAAQKfx8AAgkABwkGHShXADMCAAkABwkGHShXADMCAAAA.',
Ih='Ihavecookies:BAAALgAECgUJBgAAAA==.',
Ij='Ijur:BAAALgAECgQJCAABLgAECgUJBgAEAAAAAA==.',
Ik='Ikayro:BAABLgAECn8cAAIJAAgJdx2AKgDJAgAJAAgJdx2AKgDJAgAAAA==.',
Il='Ilostmyphone:BAAALgAECgEJAQAAAA==.Ilovemysword:BAAALgAECgUJCQAAAA==.Iluvatar:BAABLgAECn8eAAMHAAgJiiGNDQB7AgAHAAgJiiGNDQB7AgAGAAIJwxKPYQB2AAABLgAFFAEJAQAEAAAAAA==.',
Im='Imagine:BAABLgAECn8WAAQWAAkJaRDRDgDhAQAWAAkJaRDRDgDhAQAVAAYJFganPgDwAAAXAAEJtgLYKwAeAAAAAA==.',
In='Infoxticated:BAAALgAECgEJAQAAAA==.',
Ir='Iratedemon:BAAALgAECgMJBAABLgAECgQJBAAEAAAAAA==.Irateknight:BAAALgAECgQJBAAAAA==.Irely:BAAALgAECgIJAgAAAA==.',
Ja='Jadedways:BAAALgAECgEJAgAAAA==.Jasmirangel:BAACLgAFFH8TAAIcAAQJRRocKgARAQAcAAQJRRocKgARAQAuAAQKf0YAAhwACAkDJR8HAEUDABwACAkDJR8HAEUDAAAA.',
Je='Jede:BAAALgADCgMJAwAAAA==.',
Jo='Joshallen:BAAALgADCgcJBwAAAA==.',
Ju='Juka:BAABLgAECn8UAAIOAAkJGQd0WABVAQAOAAkJGQd0WABVAQAAAA==.Jukks:BAABLgAECn8UAAIMAAcJmgubJAAMAQAMAAcJmgubJAAMAQAAAA==.Juno:BAAALgADCgkJEwAAAA==.Justsumfoo:BAAALgAECgIJBAAAAA==.',
Ka='Kano:BAACLgAFFH8YAAMCAAYJehWbIgB7AQACAAYJehWbIgB7AQADAAEJKhRANABCAAAuAAQKfy4AAgIACQmIIwYLAP0CAAIACQmIIwYLAP0CAAAA.Karper:BAAALgAECgEJAQAAAA==.Kataga:BAAALgAECgEJAQAAAA==.Katarm:BAABLgAECn8UAAMMAAkJcgiDJQAGAQAMAAkJagSDJQAGAQAaAAUJNgwjQwC7AAAAAA==.Katarru:BAAALgAECgYJDQAAAA==.Kataru:BAAALgADCgIJAgAAAA==.Kawada:BAAALgAECgEJAQAAAA==.Kayhaus:BAAALgAECgcJEwAAAA==.',
Kh='Khory:BAAALgAFFAIJBAAAAA==.',
Ki='Killrah:BAAALgAECgEJAgAAAA==.Kirito:BAAALgADCgYJBgAAAA==.',
Kk='Kkiinnoopp:BAABLgAECn8jAAMCAAgJiBYneABPAQADAAYJVhYrFQB1AQACAAcJSxQneABPAQAAAA==.',
Ko='Korgigor:BAAALgAECgQJBwAAAA==.Kovu:BAAALgAECgcJEgAAAA==.',
Kr='Krisanthemum:BAAALgADCgcJCwAAAA==.Krystrasz:BAAALgAECgQJCwAAAA==.',
Kt='Kt:BAAALgADCgIJAgABLgAECgQJBAAEAAAAAA==.Ktrogue:BAAALgAECgQJBAAAAA==.',
Ku='Kuailiang:BAAALgAECgcJCwAAAA==.Kuraihikari:BAAALgAFFAEJAQAAAA==.Kustaa:BAAALgADCgkJCgABLgAECgkJLAAkAIsXAA==.',
La='Ladezar:BAAALgADCgcJDQAAAA==.Laissen:BAAALgAECgcJCQAAAA==.Lapsung:BAAALgAECgIJBAABLgAECgkJGwAKAFQWAA==.Lattemocha:BAABLgAECn8tAAMcAAkJ3x6eMADpAQAcAAYJLR2eMADpAQAgAAkJBhLcIADCAQAAAA==.',
Le='Lenden:BAAALgAECgMJBgAAAA==.Leprechaun:BAAALgADCgcJCQAAAA==.Leví:BAAALgADCgUJBQAAAA==.Leylas:BAAALgAECgEJAgAAAA==.',
Li='Lighthoove:BAAALgAECgcJBwAAAA==.Lightswìtch:BAAALgADCgEJAQAAAA==.Lilliaz:BAAALgAECgYJBwAAAA==.Linianna:BAAALgAECgYJEgAAAA==.Liriel:BAAALgAECgcJBwAAAA==.',
Lu='Ludlow:BAABLgAECn8dAAICAAgJEgpGgQA8AQACAAgJEgpGgQA8AQAAAA==.Lunastra:BAACLgAFFH8KAAIJAAQJERJChADPAAAJAAQJERJChADPAAAuAAQKfycAAgkACAlOHJ9KAPsBAAkACAlOHJ9KAPsBAAEuAAUUAgkEAAQAAAAA.Lunatonne:BAAALgAECgIJAgAAAA==.Luneztoprime:BAAALgAECgYJCgAAAA==.',
Ly='Lydarra:BAAALgAECgQJBwABLgAECgYJFwAbAPYZAA==.Lyiann:BAAALgADCggJEgAAAA==.Lyákadion:BAAALgAECgEJAQAAAA==.',
['Lâ']='Lâdypriest:BAAALgADCgUJBQAAAA==.',
Ma='Mafi:BAABLgAECn8WAAICAAcJ/RmyXACPAQACAAcJ/RmyXACPAQAAAA==.Maggore:BAAALgAECgIJBgAAAA==.Magikiwiks:BAAALgAECgEJAQAAAA==.Magsdk:BAAALgAFFAIJAgABLgAFFAgJJAAVAKEcAA==.Mainlander:BAAALgAECgMJAwAAAA==.Malbogea:BAAALgAFFAEJAQAAAA==.Malusmittens:BAAALgAECgQJBQABLgAFFAUJGwACADsjAA==.Mantonso:BAABLgAECn8xAAIbAAkJDSCjDQCUAgAbAAkJDSCjDQCUAgAAAA==.Manus:BAAALgAECgMJAwAAAA==.Matt:BAACLgAFFH8JAAIcAAQJMQsENwDQAAAcAAQJMQsENwDQAAAuAAQKfyoAAhwACQkiHWwNAO8CABwACQkiHWwNAO8CAAAA.',
Me='Meddicus:BAAALgAECgUJCAAAAA==.Meechydarko:BAAALgAECgUJBQABLgAFFAQJCwADAGAUAA==.Megalomaniä:BAAALgADCgYJBgABLgAECgcJHgAUAKYYAA==.Megorice:BAABLgAFFH8HAAISAAIJQQXyLwBdAAASAAIJQQXyLwBdAAAAAA==.Megå:BAABLgAECn8eAAMUAAcJphiqFwAHAQASAAYJmBc5dQBPAQAUAAUJmBuqFwAHAQAAAA==.Mewtwô:BAAALgAECgYJBwAAAA==.',
Mi='Microbrew:BAAALgAECgMJBQAAAA==.Miezra:BAAALgAECgYJCAAAAA==.Mikah:BAAALgAECgYJDwAAAA==.Mikeoxmall:BAAALgAECgEJAQAAAA==.',
Mo='Modayus:BAAALgAECgEJAQAAAA==.Mojomittens:BAACLgAFFH8bAAICAAUJOyPcHgCJAQACAAUJOyPcHgCJAQAuAAQKfyIAAwIABwlEJK4pADcCAAIABwlEJK4pADcCAAgABQnAFqRAAFcBAAAA.Monstermime:BAAALgAECgIJAgABLgAECgkJDQAEAAAAAA==.Monstroqt:BAAALgADCgQJBAAAAA==.Moobiez:BAAALgADCggJCQAAAA==.Moonpièz:BAAALgAECgEJAgAAAA==.Morøs:BAAALgADCgYJBgAAAA==.Moxx:BAABLgAECn8ZAAIlAAkJtw4lNAAzAQAlAAkJtw4lNAAzAQAAAA==.',
Mu='Muffers:BAABLgAECn83AAIlAAkJAxMuGgDgAQAlAAkJAxMuGgDgAQAAAA==.Muffpuff:BAAALgAECgQJBQAAAA==.Mutige:BAAALgADCgEJAQAAAA==.',
My='Mylotus:BAAALgAECgQJBQAAAA==.',
Na='Napkuntt:BAAALgAECgEJAQAAAA==.Napokin:BAAALgAFFAEJAgAAAA==.Napshade:BAABLgAECn8cAAMHAAcJyhvCLABwAQAHAAYJ/xzCLABwAQAKAAYJEhAuSQDAAAABLgAFFAEJAgAEAAAAAA==.Natsuu:BAAALgAECgcJDAAAAA==.',
Nb='Nbayoungboyy:BAAALgADCgYJBgABLgAFFAYJHgACAIYhAA==.',
Ne='Necroticoath:BAAALgAECgIJBgABLgAFFAIJBwAOACcjAA==.Neuro:BAABLgAFFH8FAAIJAAMJ6QTOMgB3AAAJAAMJ6QTOMgB3AAAAAA==.Neven:BAAALgAECgIJAgAAAA==.',
Ni='Nightor:BAAALgAECgEJAQAAAA==.Nightvenge:BAAALgAFFAMJBAAAAA==.Nikodemos:BAAALgAFFAgJGwAAAQ==.Nivahoof:BAAALgADCgEJAQAAAA==.',
No='Noc:BAABLgAECn8tAAMSAAgJTRmAOAD3AQASAAgJTRmAOAD3AQATAAUJNA+JLQAHAQABLgAFFAMJCAASADYSAA==.Nomemage:BAAALgADCgEJAQAAAA==.',
Ob='Obe:BAAALgAFFAIJAgAAAA==.Obsidiangel:BAAALgADCggJEAAAAA==.',
Oh='Ohface:BAAALgAECgQJBwABLgAECgIJBgAEAAAAAA==.',
Oo='Oowu:BAAALgADCgkJFAAAAA==.',
Or='Oran:BAABLgAECn8YAAIFAAgJaxi4UwDOAQAFAAgJaxi4UwDOAQAAAA==.Orb:BAAALgAECgYJBgAAAA==.Orctrax:BAABLgAECn8aAAMCAAgJVRGpdwBQAQACAAgJVRGpdwBQAQAIAAEJBALAjgAsAAAAAA==.Oricale:BAAALgAECgYJBgAAAA==.',
Os='Osheat:BAACLgAFFH8FAAINAAMJJg0erQDGAAANAAMJJg0erQDGAAAuAAQKfyMAAg0ACQndHzcpAFwCAA0ACQndHzcpAFwCAAAA.Osmodeus:BAAALgAECgUJCAAAAA==.',
Ou='Outplay:BAAALgADCgUJBQAAAA==.',
Ox='Ox:BAAALgAECgEJAQAAAA==.Oxheart:BAAALgAECgEJAQAAAA==.',
Oz='Ozzymo:BAAALgAECgcJCwAAAA==.',
Pa='Paltis:BAAALgAECgQJBQAAAA==.Paltonso:BAAALgADCgkJCQAAAA==.Pandaari:BAABLgAECn8WAAIHAAgJFAQwTADfAAAHAAgJFAQwTADfAAAAAA==.Papaschristo:BAAALgADCgUJBQAAAA==.Papasdiablo:BAAALgAECgEJAgAAAA==.Parprapa:BAAALgADCgMJAwAAAA==.',
Pe='Penicillin:BAAALgAECgMJAwAAAA==.Persimmon:BAACLgAFFH8PAAIkAAQJVxyEGwBDAQAkAAQJVxyEGwBDAQAuAAQKfyAAAiQABwmTF/8qALgBACQABwmTF/8qALgBAAAA.Peyton:BAAALgAECgUJBwAAAA==.',
Ph='Philip:BAAALgADCgcJDAAAAA==.Phyrie:BAAALgAECgUJDwABLgAECgYJFwAbAPYZAA==.',
Pi='Pittpete:BAAALgAECgEJAQAAAA==.',
Pl='Plaguepapi:BAAALgAFFAEJAQAAAA==.',
Po='Pollocaotico:BAAALgAFFAIJAgAAAA==.',
Ps='Psythera:BAAALgAECgIJBAABLgAECggJIgAHAPIcAA==.Psythern:BAAALgADCgYJCQABLgAECggJIgAHAPIcAA==.',
Pu='Punkybrewstr:BAABLgAECn8xAAMBAAgJjhZFJACKAQABAAcJURZFJACKAQAlAAgJswr0MABjAQAAAA==.Pureshock:BAAALgAECggJDQAAAA==.Purpderf:BAAALgAFFAEJAQAAAA==.',
Pw='Pwnstar:BAAALgAECgQJCAAAAA==.',
Py='Pykei:BAAALgAECgQJBwAAAA==.Pyrrah:BAAALgAECgEJAQABLgAECgkJJAAGAEIdAA==.Pyrri:BAABLgAECn8kAAQGAAkJQh2wFAA3AgAGAAgJaB6wFAA3AgAKAAQJ4RXjUQDwAAAHAAMJdRSQWgCrAAAAAA==.Pyrria:BAABLgAECn8XAAMOAAkJvySbBgBGAwAOAAgJeySbBgBGAwAPAAUJJhX1QgAnAQABLgAECgkJJAAGAEIdAA==.Pyrris:BAAALgAECgMJBAABLgAECgkJJAAGAEIdAA==.',
Pz='Pznt:BAAALgAECgEJAQAAAA==.',
['Pé']='Péyton:BAAALgAECggJEAAAAA==.',
['Pì']='Pì:BAAALgADCgEJAgAAAA==.',
['Pô']='Pôws:BAAALgAECgIJAwAAAA==.',
Qu='Quantonbomb:BAABLgAECn8UAAIcAAkJehm8EwCtAgAcAAkJehm8EwCtAgAAAA==.Quezera:BAAALgAECgEJAQAAAA==.',
Ra='Rabuf:BAABLgAECn8sAAMkAAkJixd0EgB+AgAkAAkJixd0EgB+AgAFAAYJpQ6rwQAGAQAAAA==.Raccoonadin:BAAALgADCgEJAQAAAA==.Radha:BAAALgAECgIJAgABLgAFFAUJEwANAPAgAA==.Ragingwater:BAAALgAECgYJEAAAAA==.Ranadheer:BAAALgAFFAEJAQAAAA==.Raspaigus:BAAALgAECgQJBAAAAA==.Ratfu:BAABLgAECn8UAAIlAAYJOQX/RwD1AAAlAAYJOQX/RwD1AAAAAA==.Raudson:BAABLgAECn8UAAILAAkJDCJUAgATAwALAAkJDCJUAgATAwAAAA==.',
Re='Redizle:BAACLgAFFH8cAAIGAAgJcRZ9CQCNAgAGAAgJcRZ9CQCNAgAuAAQKfycABAoACAnxHBkoAK8BAAYACAn7FuUbALcBAAoABgkyHBkoAK8BAAcABQnSEug2ADYBAAAA.Reginrune:BAAALgAECgkJEwAAAA==.Resonance:BAABLgAECn8WAAMPAAcJHBYcOwBJAQAPAAcJ9RUcOwBJAQAhAAMJZwykIwCeAAAAAA==.Restroll:BAAALgADCgUJBQAAAA==.',
Rh='Rhaigar:BAAALgAECgUJCQAAAA==.Rhónatar:BAAALgADCgQJBAAAAA==.',
Ri='Righteouscow:BAAALgAECgEJAQAAAA==.',
Ro='Rohdoog:BAABLgAECn84AAIVAAkJoRdAFAA7AgAVAAkJoRdAFAA7AgAAAA==.Roundabugman:BAACLgAFFH8MAAIPAAMJrh2LLQDdAAAPAAMJrh2LLQDdAAAuAAQKfycAAw8ACAmSHgEhANwBAA8ACAmSHgEhANwBAA4AAwmnFOF3ALIAAAAA.',
Rr='Rr:BAABLgAFFH8NAAMjAAMJyAH9DgB1AAAmAAMJIAHeNgCEAAAjAAMJpAH9DgB1AAAAAA==.',
Ru='Runedyu:BAAALgAECgYJEQAAAA==.',
Ry='Ryanno:BAACLgAFFH8LAAICAAMJpxvkUwABAQACAAMJpxvkUwABAQAuAAQKfyoAAgIACQkwIEoeAHACAAIACQkwIEoeAHACAAAA.Ryannoo:BAAALgAECgYJBQAAAA==.Ryujinhalco:BAAALgAECgEJAQAAAA==.',
Sa='Sabim:BAAALgAECgEJAQAAAA==.Sahomi:BAACLgAFFH8SAAIGAAUJQgynKQABAQAGAAUJQgynKQABAQAuAAQKfyoAAwYACQk8EYEDAEEBAAYACQk8EYEDAEEBAAoAAglNBZR3AEwAAAAA.Salana:BAAALgADCgcJBwAAAA==.Samwise:BAAALgAECgYJCAAAAA==.Sarai:BAAALgADCgEJAQAAAA==.Sarcini:BAABLgAECn8uAAILAAkJXhvpBwBcAgALAAkJXhvpBwBcAgAAAA==.Satrina:BAACLgAFFH8NAAINAAQJqRWdYAA0AQANAAQJqRWdYAA0AQAuAAQKfyQAAg0ACAmrIl8zADECAA0ACAmrIl8zADECAAAA.Savvy:BAAALgAECgYJBwABLgAECgcJBwAEAAAAAA==.',
Sc='Scrappy:BAAALgAECgEJAQAAAA==.',
Se='Sedna:BAAALgADCgYJBgABLgAECgYJCAAEAAAAAA==.Selanthe:BAAALgAECgQJBgAAAA==.Seruk:BAAALgAECgEJBAAAAA==.Seventhghost:BAEALgAECgQJBQABLgAFFAYJEQAHAK0XAA==.',
Sh='Shadowstorme:BAAALgAECgIJBQAAAA==.Shamander:BAABLgAECn8eAAIOAAkJQxj3IgA9AgAOAAkJQxj3IgA9AgAAAA==.Shamsham:BAAALgADCgcJDAAAAA==.Sharabuf:BAAALgAECgEJAQAAAA==.Sharky:BAAALgADCgQJBAAAAA==.Shocka:BAAALgADCgcJCQAAAA==.Shokanki:BAAALgAECgYJCwAAAA==.Shutupcat:BAAALgADCgQJBAABLgADCgUJBQAEAAAAAA==.',
Si='Sicara:BAABLgAECn8uAAIZAAkJQhapPwDKAQAZAAkJQhapPwDKAQAAAA==.Silentmage:BAAALgADCgcJCAAAAA==.Silentslock:BAAALgADCgYJBQAAAA==.Sillylilguy:BAACLgAFFH8JAAIhAAMJnBE3AwADAQAhAAMJnBE3AwADAQAuAAQKfxgAAiEACAmEH+8EAMECACEACAmEH+8EAMECAAAA.Sinestro:BAAALgAECgQJBAAAAA==.Sivrogar:BAAALgAECgMJAwAAAA==.',
Sl='Slaik:BAAALgAECgYJDwAAAA==.Slander:BAACLgAFFH8cAAMNAAcJkhzoMwCaAQANAAcJkhzoMwCaAQAeAAEJAADTYAAAAAAuAAQKfz8AAg0ACQnVI1QCACoCAA0ACQnVI1QCACoCAAAA.',
Sm='Smartbuff:BAAALgAECgEJAQAAAA==.',
So='Solemnograve:BAAALgAECgIJAgAAAA==.Somazugzug:BAACLgAFFH8RAAIOAAUJvhlsKwA2AQAOAAUJvhlsKwA2AQAuAAQKfyUAAg4ACQm5GV8uANABAA4ACQm5GV8uANABAAAA.Sothren:BAAALgAECgQJBQABLgADCgkJCQAEAAAAAA==.Souchong:BAAALgAECgMJAwABLgAECgkJGwAKAFQWAA==.',
Sp='Spacedguy:BAAALgADCgMJAwAAAA==.Spry:BAAALgAECgEJAQAAAA==.',
St='Staccato:BAAALgAECgEJAQAAAA==.Stanleyy:BAAALgAFFAEJAgABLgAFFAIJBwAOACcjAA==.Starlight:BAAALgAECgIJAgAAAA==.Stepbrother:BAABLgAFFH8FAAINAAMJYgh9KwDCAAANAAMJYgh9KwDCAAABLgAFFAQJCwADAGAUAA==.',
Su='Sugar:BAABLgAECn8nAAMOAAkJ5RFQTQB8AQAOAAkJ5RFQTQB8AQAPAAUJtw6oVgDrAAAAAA==.Sugars:BAAALgAECgUJBAAAAA==.Sulin:BAAALgADCgUJBwAAAA==.Sungôd:BAAALgADCgEJAQABLgAECgkJMQABAI4WAA==.',
Sw='Swonks:BAAALgAECgMJAwAAAA==.Swyper:BAAALgAECgMJAwAAAA==.',
Sy='Synicism:BAAALgADCgcJDQAAAA==.',
Ta='Taintbubble:BAAALgAECgMJBQAAAA==.Tanktommy:BAAALgAFFAEJAQABLgAFFAUJHQANAGwbAA==.Tarnished:BAAALgADCgcJCAAAAA==.Tarquitus:BAACLgAFFH8YAAMZAAgJcg1tEgAQAQAZAAcJcA9tEgAQAQARAAIJeAS+CgCTAAAuAAQKfzwAAxkACAmXIAYdAGYCABkACAnWHwYdAGYCABEACAm8F0sRAFUCAAAA.Tattoosguy:BAAALgADCgEJAQAAAA==.',
Te='Teef:BAABLgAECn8cAAImAAcJFxXyIwB1AQAmAAcJFxXyIwB1AQAAAA==.Tellan:BAAALgADCgcJBwAAAA==.',
Th='Thanatös:BAABLgAECn8cAAMJAAgJbBZYagCnAQAJAAgJbBZYagCnAQAnAAQJrxRDDQD1AAAAAA==.Tharros:BAAALgAECgcJDQAAAA==.Thedarkkness:BAABLgAECn8nAAIeAAkJIhfqFgCwAQAeAAkJIhfqFgCwAQAAAA==.Thekleener:BAAALgAECgEJAQAAAA==.Thorin:BAAALgAECgQJBAABLgAFFAIJBwAOACcjAA==.Thrasher:BAAALgAECgEJAwAAAA==.',
Ti='Tidalwave:BAACLgAFFH8OAAIOAAQJAh4GJgBSAQAOAAQJAh4GJgBSAQAuAAQKfy0AAw4ACQnFGSghAEkCAA4ACQnFGSghAEkCAA8AAgltC/StACoAAAAA.Tidus:BAAALgAECgYJEQAAAA==.Tinytotem:BAAALgAECgEJBAAAAA==.Tissue:BAABLgAECn8XAAIRAAcJCArULABjAQARAAcJCArULABjAQAAAA==.',
To='Toasted:BAAALgADCgYJCQABLgAECgMJAwAEAAAAAA==.Tobibi:BAAALgAFFAEJAQABLgAFFAIJBwAOACcjAA==.Todo:BAAALgADCgQJBAAAAA==.Tolip:BAABLgAECn8rAAMcAAgJUQgrdgD1AAAcAAYJgAgrdgD1AAAgAAgJSgSlSADpAAABLgAFFAEJAQAEAAAAAA==.Tolipally:BAAALgAFFAEJAQAAAA==.Tolipicious:BAAALgADCgUJCQABLgAFFAEJAQAEAAAAAA==.Topsykret:BAAALgAECgEJAwAAAA==.Topsyy:BAAALgAECgEJAQAAAA==.',
Tr='Trauts:BAAALgAECgQJCAAAAA==.Treeadin:BAABLgAECn8nAAILAAkJWhBNFwBmAQALAAkJWhBNFwBmAQAAAA==.Trollcula:BAAALgAECggJDgABLgAFFAUJDQACAJAVAA==.Truthwithin:BAAALgAECgUJEwAAAA==.',
Ts='Tsarrubus:BAABLgAECn8hAAIRAAkJcwk4JQBPAQARAAkJcwk4JQBPAQAAAA==.',
Tu='Tula:BAAALgAECgUJCwAAAA==.Tusck:BAAALgAECgYJEAAAAA==.',
Tw='Twingert:BAAALgAECgEJAQAAAA==.Twitch:BAAALgAECgYJEwAAAA==.',
Ty='Tyedyemess:BAAALgAECgMJAwAAAA==.',
['Tà']='Tàylor:BAABLgAECn8cAAIkAAkJOQu1OgCPAQAkAAkJOQu1OgCPAQAAAA==.',
Ub='Ubbaa:BAAALgAECgEJAQAAAA==.',
Ul='Ulghar:BAABLgAECn8rAAIbAAkJNCXMAQBfAwAbAAkJNCXMAQBfAwAAAA==.',
Ur='Ursock:BAAALgAECggJDgAAAA==.',
Uw='Uwuhshake:BAABLgAECn8tAAMcAAkJ7SH2BABrAwAcAAkJ7SH2BABrAwAgAAEJqRvjegBRAAAAAA==.',
Va='Valdria:BAAALgAECgMJAwAAAA==.Valssien:BAAALgADCgkJCQAAAA==.Vanaria:BAAALgAECgQJBAAAAA==.Vanbrook:BAAALgAECgQJAgAAAA==.Vanden:BAAALgAECgYJDAAAAA==.Vanrion:BAAALgAFFAIJAwAAAA==.Varrodd:BAAALgAECgEJAQAAAA==.Vastextent:BAAALgAECgEJAQAAAA==.',
Ve='Velcro:BAAALgAECgYJEgAAAA==.Velsera:BAAALgAECgYJCAAAAA==.Velvet:BAAALgADCgQJCAAAAA==.Velyn:BAAALgAECgcJDwAAAA==.Velynara:BAAALgADCgIJAgABLgAECgYJCAAEAAAAAA==.Vengefulcry:BAAALgAECgMJAwAAAA==.Vengefül:BAAALgADCgYJCAAAAA==.Vexara:BAAALgAECgQJBAAAAA==.',
Wa='Wanaaga:BAAALgAECggJDgAAAA==.',
We='Wedge:BAAALgAECgEJAQAAAA==.',
Wh='Whack:BAAALgAECgQJBAAAAA==.Whohaveaggro:BAAALgAECgEJBQAAAA==.',
Wi='Widestripe:BAAALgADCgYJBgAAAA==.Wilmington:BAAALgADCgIJAgAAAA==.Windfrost:BAAALgADCgUJBQAAAA==.Wino:BAABLgAECn8VAAMmAAgJlxCuHwCYAQAmAAgJdhCuHwCYAQAiAAEJTxHyJQA8AAAAAA==.Wiqui:BAAALgAECgEJBAAAAA==.Witulow:BAABLgAECn8pAAMYAAgJ3w1dUQApAQAYAAcJog9dUQApAQABAAgJrAQGQAD6AAAAAA==.',
Wo='Wolfadin:BAACLgAFFH8KAAIFAAQJGwZ+HAC9AAAFAAQJGwZ+HAC9AAAuAAQKf0EAAgUACQmOGg0jAHkCAAUACQmOGg0jAHkCAAAA.Woopac:BAABLgAECn8iAAIbAAgJihzvHQD/AQAbAAgJihzvHQD/AQAAAA==.Wowdad:BAAALgAECgQJBAAAAA==.',
Wu='Wulfharth:BAAALgAECgYJDwAAAA==.',
Xe='Xenophics:BAACLgAFFH8iAAMFAAgJbBK4FwCwAQAFAAgJbBK4FwCwAQAkAAEJXwA3UgAgAAAuAAQKf0QABAUACAnOJEkRAN0CAAUACAnOJEkRAN0CACQABAl7EEpXANoAAAsAAQnKBoxVACUAAAEuAAUUBQkTAAkA8wwA.Xenophicstwo:BAACLgAFFH8TAAIJAAUJ8wyoZQAXAQAJAAUJ8wyoZQAXAQAuAAQKfyYAAgkABglMG72AAHYBAAkABglMG72AAHYBAAAA.',
Xu='Xuen:BAABLgAECn8VAAIlAAcJ/hPuKwBgAQAlAAcJ/hPuKwBgAQABLgAFFAMJDwAFABAkAA==.',
Ya='Yajsooblwj:BAAALgADCgMJAwAAAA==.',
Za='Zal:BAACLgAFFH8FAAIkAAMJrhsFKwDSAAAkAAMJrhsFKwDSAAAuAAQKfyEABCQACQlPGR8kAOQBACQACQlPGR8kAOQBAAUABwlsFo6aAEABAAsAAgkNFWQ0AHYAAAAA.Zall:BAAALgAECgYJBwAAAA==.Zankanohalco:BAAALgADCgEJAQAAAA==.Zanor:BAAALgAECgIJAgAAAA==.Zarranora:BAAALgAECgEJAQAAAA==.Zatannå:BAAALgADCgYJCQAAAA==.',
Ze='Zect:BAABLgAECn8sAAIJAAkJUROiSwD4AQAJAAkJUROiSwD4AQAAAA==.Zenshin:BAAALgAECgMJAwAAAA==.Zentaur:BAAALgAECgkJDQAAAA==.Zetzu:BAABLgAECn8cAAIbAAgJHRt1AgCHAQAbAAgJHRt1AgCHAQAAAA==.',
Zi='Zitfrlt:BAABLgAECn8UAAIbAAYJexf6AwAzAQAbAAYJexf6AwAzAQABLgAFFAQJCQADAEIMAA==.',
['Ål']='Ålucard:BAABLgAECn8jAAMGAAkJ8xWlHwDQAQAGAAcJbRSlHwDQAQAHAAgJVhiKHwDJAQAAAA==.',
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
