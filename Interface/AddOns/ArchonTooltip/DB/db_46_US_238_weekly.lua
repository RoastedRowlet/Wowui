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

local lookup = {'Monk-Brewmaster','Hunter-BeastMastery','Hunter-Survival','Unknown-Unknown','Paladin-Retribution','Priest-Discipline','Priest-Shadow','Hunter-Marksmanship','DemonHunter-Devourer','Mage-Frost','Priest-Holy','Paladin-Protection','Warrior-Protection','DeathKnight-Unholy','Shaman-Restoration','Shaman-Elemental','Druid-Feral','DemonHunter-Havoc','Warlock-Demonology','Warlock-Destruction','DeathKnight-Frost','Warlock-Affliction','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Monk-Mistweaver','Warrior-Arms','Warrior-Fury','DeathKnight-Blood','Druid-Restoration','Druid-Guardian','Druid-Balance','Shaman-Enhancement','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Paladin-Holy','Monk-Windwalker','Mage-Arcane',}
local provider = {region='US',realm='Wildhammer',name='US',type='weekly',zone=46,date='2026-07-28',data={Aa='Aayrawn:BAAALgAECggJCQAAAA==.',
Ab='Abaddonaxx:BAAALgADCgYJBgAAAA==.',
Ac='Aceshaman:BAAALgAECggJCgAAAA==.Acesmash:BAABLgAECn8lAAIBAAkJGCJaBgDWAgABAAkJGCJaBgDWAgAAAA==.Ackrenezoth:BAAALgAECgQJBwAAAA==.',
Ad='Adymisk:BAAALgADCgEJAQAAAA==.',
Ag='Agorot:BAAALgAFFAEJAQAAAA==.',
Ak='Akadion:BAAALgADCgcJCgAAAA==.Akatali:BAAALgAECgQJBgAAAA==.',
Al='Aldannia:BAABLgAECn8VAAMCAAcJ4A/QVwBhAQACAAcJ8wzQVwBhAQADAAYJ7gwINAAQAQAAAA==.Alextros:BAEALgAECggJEwAAAA==.Alloren:BAAALgAECgQJBgAAAA==.Almond:BAAALgAECgEJAgAAAA==.Alorinis:BAAALgAECgYJBgABLgAFFAEJAQAEAAAAAA==.',
Am='Amaranthe:BAAALgAECgEJAQAAAA==.Amrax:BAABLgAECn80AAIFAAkJpRVbPgAMAgAFAAkJpRVbPgAMAgAAAA==.Amynre:BAABLgAECn8aAAMGAAkJKRCfFQD5AQAGAAkJKRCfFQD5AQAHAAMJ6w33VABvAAAAAA==.',
An='Anarsa:BAAALgAECgUJCgAAAA==.Angery:BAAALgAECgIJAgAAAA==.Angstyboi:BAAALgAECgQJBAAAAA==.',
Ap='Apostate:BAAALgADCgEJAQAAAA==.',
Aq='Aquabat:BAACLgAFFH8cAAQIAAQJ8h17EQBMAQAIAAQJ4xt7EQBMAQADAAMJdBdmGwD2AAACAAMJ0BcGeQCmAAAuAAQKfycABAMACQlHIv8FAMQCAAMACQmFIP8FAMQCAAgABwmrH38bAEwCAAIABQlwJRgoABgCAAAA.Aquabàt:BAABLgAFFH8FAAIJAAQJbgUfLgC5AAAJAAQJbgUfLgC5AAABLgAFFAQJHAAIAPIdAA==.',
Ar='Arvyy:BAACLgAFFH8GAAIKAAMJ9w+qPADKAAAKAAMJ9w+qPADKAAAuAAQKfycAAgoACQlYGu8sAGUCAAoACQlYGu8sAGUCAAAA.',
As='Ashbringer:BAACLgAFFH8PAAIFAAMJECTJQwAjAQAFAAMJECTJQwAjAQAuAAQKfyYAAgUACQlgI8EWALoCAAUACQlgI8EWALoCAAAA.',
At='Atria:BAACLgAFFH8IAAIKAAQJtQxBdgDvAAAKAAQJtQxBdgDvAAAuAAQKfycAAgoACAlfF99FAAkCAAoACAlfF99FAAkCAAAA.Attia:BAABLgAECn8bAAMLAAkJVBYWHQDdAQALAAkJVBYWHQDdAQAHAAIJDRVbaAB8AAAAAA==.',
Au='Autumarra:BAAALgAECgUJBQAAAA==.',
Av='Avaris:BAAALgADCgIJAgAAAA==.Avatarbambi:BAAALgADCgUJAgAAAA==.',
Aw='Away:BAAALgAECgYJBgABLgAECgkJJwAMAFoQAA==.',
Ax='Axtar:BAABLgAECn8nAAINAAkJvhu7CwAyAgANAAkJvhu7CwAyAgAAAA==.',
Ay='Ayyitzrich:BAAALgADCgQJBAAAAA==.',
Ba='Babarazzar:BAAALgADCgYJBgAAAA==.Baladoria:BAACLgAFFH8NAAILAAUJVxJsFwACAQALAAUJVxJsFwACAQAuAAQKfzsAAgsACQkuIhYEAEUDAAsACQkuIhYEAEUDAAAA.Baldkrank:BAAALgAECgEJAQAAAA==.Bananabowman:BAAALgAECgEJAgAAAA==.Barrels:BAABLgAECn8lAAMCAAkJux7JIgBZAgACAAgJLx3JIgBZAgADAAkJnBUNFAAFAgABLgAFFAIJBQAOAP4PAA==.Bartab:BAABLgAECn87AAMPAAkJLR7vDADxAgAPAAkJLR7vDADxAgAQAAEJEwPwvwAeAAABLgAECgkJSwARAF8hAA==.Baruku:BAAALgAFFAEJAQAAAA==.Bashfulwaltz:BAAALgAECggJCQAAAA==.Bastadi:BAABLgAFFH8HAAMPAAIJJyMpTADBAAAPAAIJJyMpTADBAAAQAAEJSB6bLABTAAAAAA==.Bazuul:BAAALgAECgEJAgAAAA==.',
Be='Bearemy:BAAALgAECgcJBwAAAA==.Beastling:BAAALgAECgYJDwAAAA==.Beau:BAACLgAFFH8SAAISAAQJvyNBBwCTAQASAAQJvyNBBwCTAQAuAAQKfzwAAhIACQmTJX0CAD0DABIACQmTJX0CAD0DAAAA.Beauchi:BAAALgAECgUJBQABLgAFFAQJEgASAL8jAA==.Beauwi:BAAALgAECgQJBgABLgAFFAQJEgASAL8jAA==.Beldin:BAAALgAECgEJAQAAAA==.',
Bi='Bigshekels:BAAALgAECgEJAQAAAA==.Bigulsworth:BAAALgADCgcJCAAAAA==.',
Bl='Blackadder:BAAALgAECgcJEgAAAA==.Blawkk:BAAALgAECgYJBgAAAA==.Blenton:BAAALgAECgEJAQAAAA==.Blessthem:BAAALgAECgEJAwAAAA==.Bloodussy:BAAALgADCgUJBQAAAA==.Bluck:BAAALgADCgcJEQAAAA==.Blueeyesdrag:BAAALgADCgEJAQAAAA==.Blueombre:BAAALgAECgEJAQAAAA==.',
Bo='Boing:BAAALgAFFAIJAgAAAA==.Boltngo:BAAALgADCgIJAgAAAA==.Bombur:BAACLgAFFH8HAAITAAMJVxbBbwDiAAATAAMJVxbBbwDiAAAuAAQKfy8AAxMACQlSHGYlAEgCABMACQlSHGYlAEgCABQAAQkAAB1kAEYAAAAA.Bosstradamus:BAAALgAFFAEJAQABLgAFFAIJAgAEAAAAAA==.Boston:BAAALgAECggJEwAAAA==.Bottles:BAACLgAFFH8FAAIOAAIJ/g9E4gCDAAAOAAIJ/g9E4gCDAAAuAAQKfxQAAw4ACQkDHjcXALsCAA4ACQkDHjcXALsCABUAAgmeFGcrAHkAAAAA.',
Br='Braesong:BAAALgAECgIJBAAAAA==.Bratva:BAAALgAECgkJDAAAAA==.',
Bu='Bubagony:BAABLgAFFH8HAAMWAAQJUgm8CQB8AAATAAMJmAJZRACCAAAWAAIJmRC8CQB8AAABLgAFFAUJFAAOAPAgAA==.Bubbells:BAAALgADCgEJAQAAAA==.Buffmedaddy:BAAALgAECgIJAgABLgAECgcJBwAEAAAAAA==.Bullmedic:BAAALgADCgYJBgAAAA==.Burakku:BAABLgAECn8aAAQXAAcJEhnTGgDzAQAXAAcJEhnTGgDzAQAYAAUJJwgCMQDpAAAZAAEJAAC0PgA1AAABLgAFFAcJDgAaADsVAA==.Burguerkiing:BAAALgADCgMJAwAAAA==.Burph:BAAALgADCggJCAAAAA==.Buttonsmash:BAAALgAECgcJEAABLgAFFAgJJwAYAAgSAA==.Buzzkill:BAAALgAECgkJDwAAAA==.',
['Bâ']='Bâbyrage:BAAALgADCgcJDwAAAA==.',
Ca='Cairen:BAABLgAECn8lAAIJAAkJMh6dIQBMAgAJAAkJMh6dIQBMAgAAAA==.Calzraxx:BAABLgAECn8UAAQbAAcJdxLhMAAEAQAbAAcJPwvhMAAEAQANAAQJOhOULQDVAAAcAAMJ7ASyjQCIAAAAAA==.Carstaller:BAAALgAECgQJBQAAAA==.Cartons:BAABLgAECn8VAAIFAAgJySAwEwD5AgAFAAgJySAwEwD5AgABLgAFFAIJBQAOAP4PAA==.',
Cc='Ccaan:BAAALgAECgkJEQAAAA==.Ccian:BAAALgAECgQJBAAAAA==.',
Ce='Celinn:BAACLgAFFH8JAAMLAAQJrA+/IQCtAAALAAMJ0hO/IQCtAAAGAAIJzAVSQgBxAAAuAAQKfzgAAwsACQkPHZMMAJ0CAAsACQkPHZMMAJ0CAAYABwnLFJAgAMkBAAAA.',
Ch='Chadgar:BAAALgADCgUJBwAAAA==.Chalupacabra:BAAALgADCgIJAgAAAA==.Chappie:BAAALgAECgEJAQABLgAFFAQJHAAIAPIdAA==.Charliek:BAABLgAFFH8IAAIcAAQJQA2KKQAPAQAcAAQJQA2KKQAPAQAAAA==.Cherches:BAAALgADCgEJAQAAAA==.Childish:BAAALgAECgYJDQAAAA==.Chimalma:BAAALgAFFAIJBAAAAA==.Chingoblingo:BAAALgAECgEJAgAAAA==.Chiqui:BAAALgAECgEJAgAAAA==.Chorr:BAAALgAFFAIJAgABLgAFFAMJCAAdAJIPAA==.',
Cl='Clarabow:BAAALgAFFAIJAwAAAA==.Closure:BAABLgAECn8YAAIeAAkJJSPbDADWAgAeAAkJJSPbDADWAgAAAA==.Cloudsx:BAAALgADCgMJAwAAAA==.Clowns:BAAALgADCggJCAAAAA==.',
Co='Coatlicue:BAABLgAECn8UAAMLAAkJFx+hEQBVAgALAAgJRSGhEQBVAgAHAAUJZBTFMQBXAQABLgAFFAIJBAAEAAAAAA==.Coby:BAABLgAECn8aAAIaAAkJ9iMjCQAJAwAaAAkJ9iMjCQAJAwAAAA==.Coffins:BAAALgAECgYJEQABLgAFFAIJBQAOAP4PAA==.Corgartah:BAAALgAECgMJAwAAAA==.Covell:BAAALgAECgcJDAAAAA==.',
Cr='Crates:BAAALgAECgUJCAABLgAFFAIJBQAOAP4PAA==.Crimsonmagic:BAAALgAECgEJAgAAAA==.Croakam:BAAALgADCggJCAABLgAFFAgJGAAJAHINAA==.Crosswalkk:BAAALgADCgMJAwAAAA==.Crygore:BAAALgAECgQJCgABLgAECgIJBgAEAAAAAA==.',
Cu='Curonconagua:BAAALgAECgMJAwAAAA==.',
Cy='Cypherrellik:BAABLgAECn8cAAMSAAkJhRCjHwB9AQASAAkJhRCjHwB9AQAJAAIJHgIg2QA9AAAAAA==.',
['Cò']='Còrgi:BAAALgAECgEJAwABLgAECgkJPQAOAIAhAA==.',
Da='Daktok:BAAALgAECgEJAQAAAA==.Damer:BAAALgADCgkJFgAAAA==.Damues:BAAALgAECggJDwAAAA==.Danaric:BAAALgAECgMJBgAAAA==.Dannyphentom:BAABLgAECn8XAAQOAAYJVxUEmAA5AQAOAAYJVxUEmAA5AQAVAAMJxhdPJACtAAAdAAMJmA4qNgCQAAAAAA==.Dargar:BAAALgAECgEJAgAAAA==.Darkling:BAABLgAECn8dAAISAAcJoB03FADwAQASAAcJoB03FADwAQAAAA==.Darknyss:BAAALgAECgMJAwAAAA==.',
De='Deathfortres:BAAALgAECgcJEgAAAA==.Dedeye:BAAALgADCgMJAwAAAA==.Deidara:BAAALgAECgkJCQAAAA==.Dekumime:BAAALgAECgkJDQAAAA==.Demandred:BAAALgAECgkJEwAAAA==.Demongrass:BAACLgAFFH8UAAIJAAYJ2ReaFQBpAQAJAAYJ2ReaFQBpAQAuAAQKfzIAAgkACAkyIL8rABkCAAkACAkyIL8rABkCAAAA.Denaric:BAAALgAECgYJEAAAAA==.Derty:BAAALgAFFAIJAwAAAA==.Devilwalk:BAAALgAFFAEJAQAAAA==.',
Dg='Dgore:BAAALgAECgEJAwABLgAECgIJBgAEAAAAAA==.',
Di='Diviñehymn:BAAALgAECgcJDwAAAA==.',
Do='Donet:BAAALgADCgEJAQAAAA==.Doodaad:BAAALgAECgEJAgAAAA==.Doppy:BAAALgADCgYJBgAAAA==.Doublerack:BAAALgAFFAEJAgABLgAECgIJBgAEAAAAAA==.',
Dr='Dragondeezz:BAAALgAECgIJBAABLgAECgIJBgAEAAAAAA==.Dragondznuts:BAACLgAFFH8nAAIYAAgJCBJJCwDzAQAYAAgJCBJJCwDzAQAuAAQKfz0ABBgACQluHuYFALACABgACQluHuYFALACABcAAgnoHjdlAKsAABkAAglHCJ0fAFUAAAAA.Draxtos:BAEALgAECgcJDgABLgAECggJEwAEAAAAAA==.Dreamevil:BAAALgAECgkJBgAAAA==.Drroxso:BAAALgAECgQJBAAAAA==.Dríppy:BAAALgAECgYJCgAAAA==.',
Ea='Eazybake:BAAALgADCgEJAQAAAA==.',
Ei='Eilerra:BAACLgAFFH8FAAIKAAIJnxs3TwCMAAAKAAIJnxs3TwCMAAAuAAQKfzAAAgoACQk/IjoiAJQCAAoACQk/IjoiAJQCAAAA.',
El='Elementony:BAABLgAECn85AAIQAAkJpBB0IwD1AQAQAAkJpBB0IwD1AQAAAA==.Elkdruid:BAABLgAECn8eAAMeAAgJxBCXTwBnAQAeAAgJxBCXTwBnAQAfAAEJQAzlNgAbAAABLgAFFAUJDgACAJAVAA==.Elladamri:BAAALgAECgEJAQAAAA==.Elodi:BAAALgAECgEJAQAAAA==.',
Em='Emberglow:BAAALgAECgcJEgAAAA==.Empyrean:BAAALgADCgQJBQAAAA==.Emylia:BAAALgAECgcJEAAAAA==.',
Er='Eresdelor:BAABLgAECn8YAAMNAAkJlRPeFwCBAQANAAkJzhHeFwCBAQAbAAQJLA4XJwC2AAAAAA==.Erre:BAABLgAECn8mAAITAAkJ5h5uHAB6AgATAAkJ5h5uHAB6AgAAAA==.',
Es='Esdeáth:BAAALgADCgEJAQAAAA==.Estia:BAAALgAECgcJCwABLgAFFAMJCAAdAJIPAA==.',
Ev='Evoktor:BAAALgAECgEJAQAAAA==.',
Ex='Exxitwound:BAAALgAECgEJAgAAAA==.',
Fa='Facasdeath:BAAALgAECgYJDAAAAA==.Failure:BAEBLgAECn8dAAIDAAkJ+hQcDQD6AQADAAkJ+hQcDQD6AQABLgAFFAUJGAABACsYAA==.Fallenhunt:BAAALgAECgEJAQAAAA==.Farmtoon:BAAALgAECgYJDQAAAA==.Fartbroknvis:BAAALgAFFAIJAgAAAA==.',
Fe='Feardapain:BAACLgAFFH8SAAITAAQJLxe7SwAvAQATAAQJLxe7SwAvAQAuAAQKfz0ABBMACQk5IhUPAAEDABMACAk5IhUPAAEDABQAAQkAADFcAFoAABYAAQkAAP84AAwAAAAA.Feardatpain:BAAALgAFFAEJAQAAAA==.Fellyn:BAAALgADCggJCwAAAA==.',
Ff='Ff:BAABLgAFFH8LAAIKAAMJwADqoQCLAAAKAAMJwADqoQCLAAAAAA==.',
Fl='Flar:BAAALgAFFAEJAQAAAA==.Flixie:BAABLgAECn8gAAMPAAkJQSH6BQBRAwAPAAkJQSH6BQBRAwAQAAEJByCmiQBdAAABLgAFFAkJMwAaAC4XAA==.Flyingcow:BAAALgAECgkJDwAAAA==.',
Fo='Foenix:BAAALgADCgYJBgAAAA==.Foxoffire:BAAALgAECgUJCgAAAA==.Foxu:BAAALgAECgcJBwAAAA==.Foxymoron:BAAALgAECgcJCwAAAA==.Fozzi:BAABLgAECn8wAAIaAAkJQSFHCAAYAwAaAAkJQSFHCAAYAwAAAA==.',
Fr='Freakazoid:BAABLgAECn8wAAIHAAkJjx3bEQBGAgAHAAkJjx3bEQBGAgAAAA==.Fritark:BAAALgAECgcJBwABLgAECgkJFAAgACcXAA==.Fritzyp:BAABLgAECn8UAAMgAAkJJxd6OwAkAQAgAAcJBxl6OwAkAQAeAAUJtAgRgQC4AAAAAA==.Frogzqc:BAAALgAECgEJAgAAAA==.Frostyburn:BAAALgAECgYJEQAAAA==.Frozenrage:BAAALgADCgcJCwAAAA==.',
['Fë']='Fëanor:BAAALgAECggJDAAAAA==.',
Ga='Gabos:BAAALgADCgEJAQAAAA==.Garayice:BAAALgADCgIJAgAAAA==.Garycoleman:BAAALgAECgQJBAAAAA==.Gaxxen:BAAALgAECgUJBQAAAA==.',
Ge='Gena:BAAALgADCgcJCAAAAA==.Geörge:BAACLgAFFH8bAAIHAAgJWxdHBgAWAgAHAAgJWxdHBgAWAgAuAAQKfy8AAgcACAlVISIIAAIDAAcACAlVISIIAAIDAAAA.',
Gh='Ghostyganja:BAAALgAECgQJBAABLgAFFAMJBQAXAHYWAA==.',
Gi='Giratiña:BAAALgAECgEJAgABLgAFFAIJAwAEAAAAAA==.',
Gl='Glary:BAAALgAECgEJAQAAAA==.Glavendale:BAAALgADCgUJBQAAAA==.',
Go='Goatcheezey:BAAALgADCgYJDAAAAA==.Goblinsox:BAAALgAECgQJBAAAAA==.Goluck:BAAALgAECgEJAQABLgAECgUJBQAEAAAAAA==.Gordothe:BAAALgADCgUJBQABLgAECgUJBgAEAAAAAA==.',
Gr='Gremfrost:BAACLgAFFH8OAAIKAAMJ0gkGRQCqAAAKAAMJ0gkGRQCqAAAuAAQKfyEAAgoACQmkEQhHAAYCAAoACQmkEQhHAAYCAAAA.Grimel:BAAALgAECgQJCAABLgAECgYJEAAEAAAAAA==.Grimghoul:BAAALgAECgQJCQABLgAECgYJEAAEAAAAAA==.Grimgram:BAAALgAECgYJEAAAAA==.Gripyoulol:BAAALgAECgQJBQAAAA==.Grotelek:BAABLgAECn8hAAIhAAkJTRPjDgDCAQAhAAkJTRPjDgDCAQAAAA==.Grotret:BAAALgAECgIJAgAAAA==.Grouchy:BAAALgADCgMJAwAAAA==.Grumpywaltz:BAAALgAECgQJBAAAAA==.Grìm:BAAALgADCgYJBgAAAA==.',
Gu='Gulimath:BAAALgAECgUJBgAAAA==.',
['Gà']='Gàrrosh:BAAALgADCgYJBQAAAA==.',
Ha='Haedrath:BAAALgAECgUJCgABLgAFFAIJBQAKAJ8bAA==.Hahoa:BAAALgAFFAMJAwABLgAFFAMJCAAdAJIPAA==.Halcojakka:BAAALgAECgMJAwAAAA==.Halconotachi:BAABLgAECn9FAAIDAAkJiRqkCgB0AgADAAkJiRqkCgB0AgAAAA==.Halcosutchi:BAAALgAECgQJBQAAAA==.Halcozaraki:BAAALgAECgUJCAAAAA==.Hammerfoot:BAAALgAFFAEJAgAAAA==.Haranir:BAAALgAFFAEJAgAAAA==.Harcat:BAABLgAECn8dAAMIAAkJGBXyCwCnAQAIAAkJGBXyCwCnAQADAAEJYQGqbAAcAAAAAA==.Hartracks:BAAALgAECgUJBQAAAA==.Hatijo:BAAALgAECgYJBwAAAA==.Hawgbawl:BAABLgAECn8kAAIcAAkJohvKGAAoAgAcAAkJohvKGAAoAgAAAA==.Hawgdream:BAAALgAECgcJEgAAAA==.',
He='Hellequin:BAACLgAFFH8dAAMiAAgJ9BYrAQD3AQAiAAgJjxYrAQD3AQAjAAIJIxNNGQCqAAAuAAQKfzkAAyIACQkDIj0BACsDACIACQkDIj0BACsDACQAAQkpA4cPACoAAAAA.Henkojin:BAAALgADCgYJBgAAAA==.Heyitzlock:BAAALgAECgYJCQAAAA==.Heyyitzrich:BAAALgAECgQJDQAAAA==.Heyyitzrichh:BAABLgAFFH8KAAITAAMJzBambwDjAAATAAMJzBambwDjAAAAAA==.Heyytaco:BAAALgAECggJEgAAAA==.',
Hi='Hiels:BAAALgAECgcJBwAAAA==.Hirogon:BAAALgAECgEJAwAAAA==.',
Ho='Hobb:BAACLgAFFH8FAAIFAAIJghHakwCMAAAFAAIJghHakwCMAAAuAAQKfykAAgUACQlwHmweAJACAAUACQlwHmweAJACAAAA.Holenmymuff:BAAALgADCgUJBQAAAA==.Hollinar:BAABLgAECn8YAAIKAAkJxxLtcADyAQAKAAkJxxLtcADyAQAAAA==.Holyfaux:BAAALgADCgYJBgAAAA==.Holyfox:BAAALgAECgEJAQAAAA==.Holysteel:BAAALgAECgIJAwAAAA==.Hondoe:BAAALgAECgQJCAAAAA==.Hordecow:BAAALgAECgQJBwABLgAFFAEJAgAEAAAAAA==.Hornhelm:BAAALgAECgYJDQAAAA==.',
Hu='Huntoor:BAAALgAECgEJAQABLgAECgYJBgAEAAAAAA==.',
Ic='Icemark:BAACLgAFFH8FAAIKAAMJfxI1KwAJAQAKAAMJfxI1KwAJAQAuAAQKfx8AAgoABwkGHShXADMCAAoABwkGHShXADMCAAAA.',
Ih='Ihavecookies:BAAALgAECgUJBgAAAA==.',
Ij='Ijur:BAAALgAECgQJCAABLgAECgUJBgAEAAAAAA==.',
Ik='Ikayro:BAABLgAECn8cAAIKAAgJdx2AKgDJAgAKAAgJdx2AKgDJAgAAAA==.',
Il='Ilostmyphone:BAAALgAECgEJAQAAAA==.Ilovemysword:BAAALgAECgUJCQAAAA==.Iluvatar:BAABLgAECn8eAAMHAAgJiiGNDQB7AgAHAAgJiiGNDQB7AgAGAAIJwxKPYQB2AAABLgAFFAEJAQAEAAAAAA==.',
Im='Imagine:BAABLgAECn8WAAQYAAkJaRDRDgDhAQAYAAkJaRDRDgDhAQAXAAYJFganPgDwAAAZAAEJtgLYKwAeAAAAAA==.',
In='Infoxticated:BAAALgAECgEJAQAAAA==.',
Ir='Iratedemon:BAAALgAECgMJBAABLgAECgQJBAAEAAAAAA==.Irateknight:BAAALgAECgQJBAAAAA==.Irely:BAAALgAECgIJAgAAAA==.',
Is='Isegrim:BAAALgADCggJCAAAAA==.',
Ja='Jadedways:BAAALgAECgEJAgAAAA==.Jasmirangel:BAACLgAFFH8TAAIeAAQJRRocKgARAQAeAAQJRRocKgARAQAuAAQKf0YAAh4ACAkDJR8HAEUDAB4ACAkDJR8HAEUDAAAA.',
Je='Jede:BAAALgADCgMJAwAAAA==.',
Jo='Joshallen:BAAALgADCgcJBwAAAA==.',
Ju='Juka:BAABLgAECn8fAAMPAAkJGQd0WABVAQAPAAkJGQd0WABVAQAhAAgJVwapBgDZAAAAAA==.Jukks:BAABLgAECn8UAAINAAcJmgubJAAMAQANAAcJmgubJAAMAQAAAA==.Juno:BAAALgADCgkJEwAAAA==.Justsumfoo:BAAALgAECgIJBAAAAA==.',
Ka='Kanky:BAAALgAECgQJBgABLgAECgkJEgAEAAAAAA==.Kano:BAACLgAFFH8YAAMCAAYJfBWbIgB7AQACAAYJfBWbIgB7AQADAAEJKhRANABCAAAuAAQKfy4AAgIACQmIIwYLAP0CAAIACQmIIwYLAP0CAAAA.Karper:BAAALgAECgEJAQAAAA==.Kashimo:BAAALgAECggJCAAAAA==.Kataga:BAAALgAECgEJAQAAAA==.Katarm:BAABLgAECn8UAAMNAAkJcgiDJQAGAQANAAkJagSDJQAGAQAbAAUJNgwjQwC7AAAAAA==.Katarru:BAAALgAECgYJDQAAAA==.Kataru:BAAALgADCgIJAgAAAA==.Kawada:BAAALgAECggJCwAAAA==.Kayhaus:BAABLgAECn8fAAITAAkJhRDJBQDCAQATAAkJhRDJBQDCAQAAAA==.',
Kh='Khory:BAACLgAFFH8IAAMdAAMJkg88GACKAAAdAAIJIRY8GACKAAAOAAIJWwIZAQFoAAAuAAQKfxQAAx0ABwnAGiIiAEIBAB0ABwnAGiIiAEIBAA4ABAnZDADuAMMAAAAA.',
Ki='Killrah:BAAALgAECgEJAgAAAA==.Kirito:BAAALgADCgYJBgAAAA==.',
Kk='Kkiinnoopp:BAABLgAECn8jAAMCAAgJiBYneABPAQADAAYJVhYrFQB1AQACAAcJSxQneABPAQAAAA==.',
Ko='Korgigor:BAAALgAECgQJBwAAAA==.Kovu:BAAALgAECgcJEgAAAA==.',
Kr='Krisanthemum:BAAALgADCgcJCwAAAA==.Krystrasz:BAAALgAECgQJCwAAAA==.',
Kt='Kt:BAAALgADCgIJAgABLgAECgQJBAAEAAAAAA==.Ktrogue:BAAALgAECgQJBAAAAA==.',
Ku='Kuailiang:BAAALgAFFAMJBAAAAA==.Kuraihikari:BAAALgAFFAEJAQAAAA==.Kustaa:BAAALgADCgkJCgABLgAECgkJLAAlAIsXAA==.',
La='Ladezar:BAAALgADCgcJDQAAAA==.Laissen:BAAALgAECggJCgAAAA==.Lapsung:BAAALgAECgIJBAABLgAECgkJGwALAFQWAA==.Lattemocha:BAABLgAECn8tAAMeAAkJ3x6eMADpAQAeAAYJLR2eMADpAQAgAAkJBhLcIADCAQAAAA==.',
Le='Lenden:BAAALgAECgMJBgAAAA==.Leprechaun:BAAALgADCgcJCQAAAA==.Leví:BAAALgADCgUJBQAAAA==.Leylas:BAAALgAECgEJAgAAAA==.',
Li='Lighthoove:BAAALgAECgcJBwAAAA==.Lightswìtch:BAAALgADCgEJAQAAAA==.Lilliaz:BAAALgAECgYJBwAAAA==.Linianna:BAAALgAECgYJEgAAAA==.Liriel:BAAALgAECgcJBwAAAA==.',
Lo='Loahdk:BAAALgAECgkJAQAAAA==.',
Lu='Ludlow:BAABLgAECn8dAAICAAgJEgpGgQA8AQACAAgJEgpGgQA8AQAAAA==.Lunastra:BAACLgAFFH8KAAIKAAQJERJChADPAAAKAAQJERJChADPAAAuAAQKfykAAgoACQn2HZ9KAPsBAAoACQn2HZ9KAPsBAAEuAAUUAwkIAB0Akg8A.Lunatonne:BAAALgAECgkJEAAAAA==.Luneztoprime:BAAALgAECgYJCgAAAA==.',
Ly='Lydarra:BAAALgAECgQJBwABLgAECggJHwAcAJwaAA==.Lyiann:BAAALgADCggJEgAAAA==.Lyákadion:BAAALgAECgEJAQAAAA==.',
['Lâ']='Lâdypriest:BAAALgADCgUJBQAAAA==.',
Ma='Mafi:BAABLgAECn8WAAICAAcJ/RmyXACPAQACAAcJ/RmyXACPAQAAAA==.Maggore:BAAALgAECgIJBgAAAA==.Magikiwiks:BAAALgAECgEJAQAAAA==.Magron:BAAALgAECgUJBQAAAA==.Magsdk:BAABLgAFFH8GAAIOAAIJqBHtiQBIAAAOAAIJqBHtiQBIAAABLgAFFAgJJAAXAKEcAA==.Mainlander:BAAALgAECgMJAwAAAA==.Malbogea:BAAALgAFFAEJAQAAAA==.Malusmittens:BAAALgAECgQJBQABLgAFFAUJGwACADsjAA==.Mantonso:BAABLgAECn8xAAIcAAkJDSCjDQCUAgAcAAkJDSCjDQCUAgAAAA==.Manus:BAAALgAECgMJAwAAAA==.Matt:BAACLgAFFH8JAAIeAAQJMQsENwDQAAAeAAQJMQsENwDQAAAuAAQKfyoAAh4ACQkiHWwNAO8CAB4ACQkiHWwNAO8CAAAA.',
Me='Meddicus:BAAALgAECgUJCAAAAA==.Meechydarko:BAAALgAECgUJBQABLgAFFAQJDQADAGAUAA==.Megalomaniä:BAAALgADCgYJBgABLgAECgcJHgAWAKYYAA==.Megorice:BAABLgAFFH8LAAITAAMJbwWnPQCYAAATAAMJbwWnPQCYAAAAAA==.Megå:BAABLgAECn8eAAMWAAcJphiqFwAHAQATAAYJmBc5dQBPAQAWAAUJmBuqFwAHAQAAAA==.Mewtwô:BAAALgAECgYJBwAAAA==.',
Mi='Microbrew:BAAALgAECgMJBQAAAA==.Miedillø:BAABLgAFFH8PAAIOAAUJzBvEVwBDAQAOAAUJzBvEVwBDAQABLgAFFAkJHwACAEMaAA==.Miezra:BAAALgAECgYJCAAAAA==.Mikah:BAAALgAECgYJDwAAAA==.Mikeoxmall:BAAALgAECgkJDQAAAA==.',
Mo='Modayus:BAAALgAECgEJAQAAAA==.Mojomittens:BAACLgAFFH8bAAICAAUJOyPcHgCJAQACAAUJOyPcHgCJAQAuAAQKfyIAAwIABwlEJK4pADcCAAIABwlEJK4pADcCAAgABQnAFqRAAFcBAAAA.Monstermime:BAAALgAECgIJAgABLgAECgkJDQAEAAAAAA==.Monstroqt:BAAALgADCgQJBAAAAA==.Moobiez:BAAALgADCggJCQAAAA==.Moonpièz:BAAALgAECgEJAgAAAA==.Morøs:BAAALgADCgYJBgAAAA==.Moxx:BAABLgAECn8ZAAImAAkJtw4lNAAzAQAmAAkJtw4lNAAzAQAAAA==.',
Mu='Muffers:BAABLgAECn83AAImAAkJAxMuGgDgAQAmAAkJAxMuGgDgAQAAAA==.Muffpuff:BAAALgAECgQJBQAAAA==.Mutige:BAAALgADCgEJAQAAAA==.',
My='Mylotus:BAAALgAECgQJBQAAAA==.Myserie:BAAALgAECgEJAQAAAA==.',
Na='Napkuntt:BAAALgAECgEJAQAAAA==.Napokin:BAAALgAFFAEJAgAAAA==.Napshade:BAABLgAECn8cAAMHAAcJyhvCLABwAQAHAAYJ/xzCLABwAQALAAYJEhAuSQDAAAABLgAFFAEJAgAEAAAAAA==.Nastian:BAAALgAECgEJAQAAAA==.Natsuu:BAAALgAECgcJDAAAAA==.',
Nb='Nbayoungboyy:BAAALgADCgYJBgABLgAFFAYJHgACAIYhAA==.',
Ne='Necroticoath:BAAALgAECgIJBgABLgAFFAIJBwAPACcjAA==.Neuro:BAABLgAFFH8GAAIKAAMJ7QaVQgC0AAAKAAMJ7QaVQgC0AAAAAA==.Neven:BAAALgAECgIJAgAAAA==.',
Ni='Nightor:BAAALgAECgEJAQAAAA==.Nightvenge:BAAALgAFFAMJBAAAAA==.Nikodemos:BAAALgAFFAkJHAAAAQ==.Nivahoof:BAAALgADCgEJAQAAAA==.',
No='Noc:BAABLgAECn8zAAMTAAgJDBukBQDHAQATAAgJDBukBQDHAQAUAAUJNA+JLQAHAQABLgAFFAMJCAATADYSAA==.Nomemage:BAAALgADCgEJAQAAAA==.',
Ob='Obe:BAAALgAFFAIJAgAAAA==.Obsidiangel:BAAALgADCggJEAAAAA==.',
Oh='Ohface:BAAALgAECgQJBwABLgAECgIJBgAEAAAAAA==.',
Oo='Oowu:BAAALgADCgkJGQAAAA==.',
Or='Oran:BAABLgAECn8YAAIFAAgJaxi4UwDOAQAFAAgJaxi4UwDOAQAAAA==.Orb:BAAALgAECgYJBgAAAA==.Orctrax:BAABLgAECn8aAAMCAAgJVRGpdwBQAQACAAgJVRGpdwBQAQAIAAEJBALAjgAsAAAAAA==.Oricale:BAAALgAECgYJBgAAAA==.',
Os='Osheat:BAACLgAFFH8FAAIOAAMJJg0erQDGAAAOAAMJJg0erQDGAAAuAAQKfyMAAg4ACQndHzcpAFwCAA4ACQndHzcpAFwCAAAA.Osmodeus:BAAALgAECgUJCAAAAA==.',
Ou='Outplay:BAAALgADCgUJBQAAAA==.',
Ox='Ox:BAAALgAECgEJAQAAAA==.Oxheart:BAAALgAECgEJAQAAAA==.',
Oz='Ozzymo:BAAALgAECgcJCwAAAA==.',
Pa='Paltis:BAAALgAECgQJBQAAAA==.Paltonso:BAAALgADCgkJCQAAAA==.Pandaari:BAABLgAECn8WAAIHAAgJFAQwTADfAAAHAAgJFAQwTADfAAAAAA==.Papaschristo:BAAALgADCgUJBQAAAA==.Papasdiablo:BAAALgAECgEJAgAAAA==.Parprapa:BAAALgADCgMJAwAAAA==.',
Pe='Penicillin:BAAALgAECgMJAwAAAA==.Persimmon:BAACLgAFFH8PAAIlAAQJVxyEGwBDAQAlAAQJVxyEGwBDAQAuAAQKfyAAAiUABwmTF/8qALgBACUABwmTF/8qALgBAAAA.Peyton:BAAALgAECgUJBwAAAA==.',
Ph='Philip:BAAALgADCgcJDAAAAA==.Phyrie:BAAALgAECgUJDwABLgAECggJHwAcAJwaAA==.',
Pi='Pittpete:BAAALgAECgEJAQAAAA==.',
Pl='Plaguepapi:BAAALgAFFAEJAQAAAA==.',
Po='Pollocaotico:BAAALgAFFAIJAgAAAA==.',
Ps='Psythera:BAAALgAECgIJBAABLgAECggJIgAHAPIcAA==.Psythern:BAAALgADCgYJCQABLgAECggJIgAHAPIcAA==.',
Pu='Punkybrewstr:BAABLgAECn8xAAMBAAgJjhZFJACKAQABAAcJURZFJACKAQAmAAgJswr0MABjAQAAAA==.Pureshock:BAAALgAECggJDQAAAA==.Purpderf:BAAALgAFFAEJAQAAAA==.',
Pw='Pwnstar:BAAALgAECgQJCAAAAA==.',
Py='Pykei:BAAALgAECgQJBwAAAA==.Pyrrah:BAAALgAECgEJAQABLgAECgkJJAAGAEIdAA==.Pyrri:BAABLgAECn8kAAQGAAkJQh2wFAA3AgAGAAgJaB6wFAA3AgALAAQJ4RXjUQDwAAAHAAMJdRSQWgCrAAAAAA==.Pyrria:BAABLgAECn8XAAMPAAkJvySbBgBGAwAPAAgJeySbBgBGAwAQAAUJJhX1QgAnAQABLgAECgkJJAAGAEIdAA==.Pyrris:BAAALgAECgMJBAABLgAECgkJJAAGAEIdAA==.',
Pz='Pznt:BAAALgAECgEJAQAAAA==.',
['Pé']='Péyton:BAAALgAECggJEAAAAA==.',
['Pì']='Pì:BAAALgADCgEJAgAAAA==.',
['Pô']='Pôws:BAAALgAECgIJAwAAAA==.',
Qu='Quanchì:BAAALgAECgEJAgABLgAFFAMJBAAEAAAAAA==.Quantonbomb:BAABLgAECn8UAAIeAAkJehm8EwCtAgAeAAkJehm8EwCtAgAAAA==.Quezera:BAAALgAECgIJAQAAAA==.',
Ra='Rabuf:BAABLgAECn8sAAMlAAkJixd0EgB+AgAlAAkJixd0EgB+AgAFAAYJpQ6rwQAGAQAAAA==.Raccoonadin:BAAALgADCgEJAQAAAA==.Radha:BAAALgAECgIJAgABLgAFFAUJFAAOAPAgAA==.Ragingwater:BAAALgAECgYJEAAAAA==.Ranadheer:BAAALgAFFAEJAQAAAA==.Raspaigus:BAAALgAECgQJBAAAAA==.Ratfu:BAABLgAECn8UAAImAAYJOQX/RwD1AAAmAAYJOQX/RwD1AAAAAA==.Raucus:BAAALgAECgEJAQAAAA==.Raudson:BAABLgAECn8UAAIMAAkJDCJUAgATAwAMAAkJDCJUAgATAwAAAA==.',
Re='Redizle:BAACLgAFFH8cAAIGAAgJcRZ9CQCNAgAGAAgJcRZ9CQCNAgAuAAQKfycABAsACAnxHBkoAK8BAAYACAn7FuUbALcBAAsABgkyHBkoAK8BAAcABQnSEug2ADYBAAAA.Reginrune:BAAALgAECgkJEwAAAA==.Resonance:BAABLgAECn8WAAMQAAcJHBYcOwBJAQAQAAcJ9RUcOwBJAQAhAAMJZwykIwCeAAAAAA==.Restroll:BAAALgADCgUJBQAAAA==.',
Rh='Rhaenyr:BAAALgAECgEJAQAAAA==.Rhaigar:BAAALgAECgUJCQAAAA==.Rhónatar:BAAALgADCgQJBAAAAA==.',
Ri='Righteouscow:BAAALgAECgEJAQAAAA==.',
Ro='Rohdoog:BAABLgAECn84AAIXAAkJoRdAFAA7AgAXAAkJoRdAFAA7AgAAAA==.Roundabugman:BAACLgAFFH8MAAIQAAMJrh2LLQDdAAAQAAMJrh2LLQDdAAAuAAQKfycAAxAACAmSHgEhANwBABAACAmSHgEhANwBAA8AAwmnFOF3ALIAAAAA.',
Rr='Rr:BAABLgAFFH8NAAMkAAMJyAH9DgB1AAAjAAMJIAHeNgCEAAAkAAMJpAH9DgB1AAAAAA==.',
Ru='Runedyu:BAAALgAECgYJEgAAAA==.',
Ry='Ryanno:BAACLgAFFH8NAAICAAMJpxvkUwABAQACAAMJpxvkUwABAQAuAAQKfysAAgIACQmqIEoeAHACAAIACQmqIEoeAHACAAAA.Ryujinhalco:BAAALgAECgMJBAAAAA==.',
Sa='Sabim:BAAALgAECgEJAQAAAA==.Sahomi:BAACLgAFFH8TAAIGAAUJQgynKQABAQAGAAUJQgynKQABAQAuAAQKfyoAAwYACQk8EZEIAEMBAAYACQk8EZEIAEMBAAsAAglNBZR3AEwAAAAA.Salana:BAAALgADCgcJBwAAAA==.Samwise:BAAALgAECgYJCAAAAA==.Sarai:BAAALgADCgEJAQAAAA==.Sarcini:BAABLgAECn8uAAIMAAkJXhvpBwBcAgAMAAkJXhvpBwBcAgAAAA==.Satrina:BAACLgAFFH8NAAIOAAQJqRWdYAA0AQAOAAQJqRWdYAA0AQAuAAQKfyQAAg4ACAmrIl8zADECAA4ACAmrIl8zADECAAAA.Savvy:BAAALgAECgYJBwABLgAFFAEJAgAEAAAAAA==.',
Sc='Scrappy:BAAALgAECgEJAQAAAA==.',
Se='Sedna:BAAALgADCgYJBgABLgAECgYJCAAEAAAAAA==.Selanthe:BAAALgAECgQJBgAAAA==.Seruk:BAAALgAECgEJBAAAAA==.Seventhghost:BAEALgAFFAEJAQABLgAFFAcJEwAHAKgYAA==.',
Sh='Shadowstorme:BAAALgAECgIJBQAAAA==.Shalaylee:BAAALgAECgEJAgAAAA==.Shamander:BAABLgAECn8eAAIPAAkJQxj3IgA9AgAPAAkJQxj3IgA9AgAAAA==.Shamsham:BAAALgADCgcJDAAAAA==.Sharabuf:BAAALgAECgEJAQAAAA==.Sharky:BAAALgAECgEJAQAAAA==.Shocka:BAAALgADCgcJCQAAAA==.Shokanki:BAAALgAECgYJCwABLgAFFAMJBAAEAAAAAA==.Shutupcat:BAAALgADCgQJBAABLgADCgYJCAAEAAAAAA==.',
Si='Sicara:BAABLgAECn8uAAIJAAkJQhapPwDKAQAJAAkJQhapPwDKAQAAAA==.Silentmage:BAAALgADCgcJCAAAAA==.Silentslock:BAAALgADCgYJBQAAAA==.Sillylilguy:BAACLgAFFH8JAAIhAAMJnBE3AwADAQAhAAMJnBE3AwADAQAuAAQKfxgAAiEACAmEH+8EAMECACEACAmEH+8EAMECAAAA.Sinestro:BAAALgAECgQJBAAAAA==.Sivrogar:BAAALgAECgMJAwAAAA==.',
Sl='Slaik:BAAALgAECgYJDwAAAA==.Slander:BAACLgAFFH8cAAMOAAcJkhzoMwCaAQAOAAcJkhzoMwCaAQAdAAEJAADTYAAAAAAuAAQKfz8AAg4ACQncIzUFABkCAA4ACQncIzUFABkCAAAA.Slapbøx:BAAALgAECgUJCAAAAA==.',
Sm='Smartbuff:BAAALgAECgEJAQAAAA==.',
So='Solemnograve:BAAALgAECgIJAgAAAA==.Somazugzug:BAACLgAFFH8SAAIPAAUJvhlsKwA2AQAPAAUJvhlsKwA2AQAuAAQKfyUAAg8ACQm5GV8uANABAA8ACQm5GV8uANABAAAA.Sosukehalco:BAAALgAECgUJBgAAAA==.Sothren:BAAALgAECgQJBQABLgADCgkJCQAEAAAAAA==.Souchong:BAAALgAECgMJAwABLgAECgkJGwALAFQWAA==.',
Sp='Spacedguy:BAAALgADCgkJEwAAAA==.Spry:BAAALgAECgEJAQAAAA==.',
St='Staccato:BAAALgAECgEJAQAAAA==.Stanleyy:BAAALgAFFAEJAgABLgAFFAIJBwAPACcjAA==.Starlight:BAAALgAECgIJAgAAAA==.Stepbrother:BAABLgAFFH8GAAIOAAMJYggYUwCsAAAOAAMJYggYUwCsAAABLgAFFAQJDQADAGAUAA==.',
Su='Sugar:BAABLgAECn8nAAMPAAkJ5RFQTQB8AQAPAAkJ5RFQTQB8AQAQAAUJtw6oVgDrAAAAAA==.Sugars:BAAALgAECgUJBAAAAA==.Sulin:BAAALgADCgUJBwAAAA==.Sungôd:BAAALgADCgEJAQABLgAECgkJMQABAI4WAA==.',
Sw='Swonks:BAAALgAECgMJAwAAAA==.Swyper:BAAALgAECgMJAwAAAA==.',
Sy='Synicism:BAAALgADCgcJDQAAAA==.',
Ta='Taintbubble:BAAALgAECgMJBQAAAA==.Tanktommy:BAAALgAFFAQJBAABLgAFFAUJJwAOAB0dAA==.Tarnished:BAAALgADCgcJCAAAAA==.Tarquitus:BAACLgAFFH8YAAMJAAgJcg3VMQBeAQAJAAcJcA/VMQBeAQASAAIJeAS+CgCTAAAuAAQKfzwAAwkACAmXIAYdAGYCAAkACAnWHwYdAGYCABIACAm8F0sRAFUCAAAA.Tattoosguy:BAAALgADCgEJAQAAAA==.',
Te='Teef:BAABLgAECn8cAAIjAAcJFxXyIwB1AQAjAAcJFxXyIwB1AQAAAA==.Tellan:BAAALgADCgcJBwAAAA==.',
Th='Thanatös:BAABLgAECn8cAAMKAAgJbBZYagCnAQAKAAgJbBZYagCnAQAnAAQJrxRDDQD1AAAAAA==.Tharros:BAAALgAECgcJDQAAAA==.Thedarkkness:BAABLgAECn8nAAIdAAkJIhfqFgCwAQAdAAkJIhfqFgCwAQAAAA==.Thekleener:BAAALgAECgEJAQAAAA==.Thorin:BAAALgAECgQJBAABLgAFFAIJBwAPACcjAA==.Thrasher:BAAALgAECgEJAwAAAA==.',
Ti='Tidalwave:BAACLgAFFH8OAAIPAAQJAh4GJgBSAQAPAAQJAh4GJgBSAQAuAAQKfy0AAw8ACQnFGSghAEkCAA8ACQnFGSghAEkCABAAAgltC/StACoAAAAA.Tidus:BAAALgAECgYJEQAAAA==.Tinytotem:BAAALgAECgEJBAAAAA==.Tissue:BAABLgAECn8XAAISAAcJCArULABjAQASAAcJCArULABjAQAAAA==.',
To='Toasted:BAAALgADCgYJCQABLgAECgMJAwAEAAAAAA==.Tobibi:BAAALgAFFAEJAQABLgAFFAIJBwAPACcjAA==.Todo:BAAALgADCgQJBAAAAA==.Tolip:BAABLgAECn8rAAMeAAgJUQgrdgD1AAAeAAYJgAgrdgD1AAAgAAgJSgSlSADpAAABLgAFFAEJAQAEAAAAAA==.Tolipally:BAAALgAFFAEJAQAAAA==.Tolipicious:BAAALgADCgUJCQABLgAFFAEJAQAEAAAAAA==.Topsykret:BAAALgAECgEJAwAAAA==.Topsyy:BAAALgAECgEJAQAAAA==.',
Tr='Trauts:BAAALgAECgQJCAAAAA==.Treeadin:BAABLgAECn8nAAIMAAkJWhBNFwBmAQAMAAkJWhBNFwBmAQAAAA==.Trollcula:BAAALgAECggJDgABLgAFFAUJDgACAJAVAA==.Truthwithin:BAAALgAECgUJEwAAAA==.',
Ts='Tsarrubus:BAABLgAECn8hAAISAAkJcwk4JQBPAQASAAkJcwk4JQBPAQAAAA==.',
Tu='Tula:BAAALgAECgUJCwAAAA==.Tulwinn:BAAALgAECgEJAQABLgAFFAgJGQAiALscAA==.Tusck:BAAALgAECgcJEQAAAA==.',
Tw='Twingert:BAAALgAECgEJAQAAAA==.Twitch:BAAALgAECgYJEwAAAA==.',
Ty='Tyedyemess:BAAALgAECgMJAwAAAA==.',
['Tà']='Tàylor:BAABLgAECn8cAAIlAAkJOQu1OgCPAQAlAAkJOQu1OgCPAQAAAA==.',
Ub='Ubbaa:BAAALgAECgEJAQAAAA==.',
Ul='Ulghar:BAACLgAFFH8JAAIcAAMJ9SKSDQAuAQAcAAMJ9SKSDQAuAQAuAAQKfysAAhwACQk0JcwBAF8DABwACQk0JcwBAF8DAAAA.',
Ur='Ursock:BAAALgAECggJDgAAAA==.',
Uw='Uwuhshake:BAABLgAECn8tAAMeAAkJ7SH2BABrAwAeAAkJ7SH2BABrAwAgAAEJqRvjegBRAAAAAA==.',
Va='Valadation:BAAALgAECgQJBQAAAA==.Valdria:BAAALgAECgMJAwAAAA==.Valssien:BAAALgADCgkJCQAAAA==.Vanaria:BAAALgAECgQJBAAAAA==.Vanbrook:BAAALgAECgQJAgAAAA==.Vanden:BAAALgAECgYJDAAAAA==.Vanrion:BAAALgAFFAIJAwAAAA==.Varrodd:BAAALgAECgEJAQAAAA==.Vastextent:BAAALgAECgEJAQAAAA==.',
Ve='Velcro:BAAALgAECgYJEgAAAA==.Velsera:BAAALgAECgYJCAAAAA==.Velvet:BAAALgADCgQJCAAAAA==.Velyn:BAAALgAECgcJDwAAAA==.Velynara:BAAALgADCgIJAgABLgAECgYJCAAEAAAAAA==.Vengefulcry:BAAALgAECgMJAwAAAA==.Vengefül:BAAALgADCgYJCAAAAA==.Vexara:BAAALgAECgQJBAAAAA==.',
Wa='Wanaaga:BAAALgAECggJDgAAAA==.',
We='Wedge:BAAALgAECgEJAQAAAA==.',
Wh='Whack:BAAALgAECgkJEAAAAA==.Whohaveaggro:BAAALgAECgIJBgAAAA==.',
Wi='Widestripe:BAAALgADCgYJBgAAAA==.Wilmington:BAAALgADCgIJAgAAAA==.Windfrost:BAAALgADCgYJCAAAAA==.Wino:BAABLgAECn8VAAMjAAgJlxCuHwCYAQAjAAgJdhCuHwCYAQAiAAEJTxHyJQA8AAAAAA==.Wiqui:BAAALgAECgEJBAAAAA==.Witulow:BAABLgAECn8pAAMaAAgJ3w1dUQApAQAaAAcJog9dUQApAQABAAgJrAQGQAD6AAAAAA==.',
Wo='Wolfadin:BAACLgAFFH8KAAIFAAQJGwZ+HAC9AAAFAAQJGwZ+HAC9AAAuAAQKf0EAAgUACQmOGg0jAHkCAAUACQmOGg0jAHkCAAAA.Woopac:BAABLgAECn8iAAIcAAgJihzvHQD/AQAcAAgJihzvHQD/AQAAAA==.Wowdad:BAAALgAECgQJBAAAAA==.',
Wu='Wulfharth:BAAALgAECgYJDwAAAA==.',
Wy='Wy:BAAALgADCgkJCQAAAA==.',
Xe='Xenophics:BAACLgAFFH8qAAMFAAgJJxbqCADgAQAFAAgJJxbqCADgAQAlAAEJXwA3UgAgAAAuAAQKf0gABAUACAnOJEkRAN0CAAUACAnOJEkRAN0CACUABAl7EEpXANoAAAwAAQnKBoxVACUAAAEuAAUUBQkXAAoAGQ8A.Xenophicstwo:BAACLgAFFH8XAAIKAAUJGQ+oZQAXAQAKAAUJGQ+oZQAXAQAuAAQKfyYAAgoABglMG72AAHYBAAoABglMG72AAHYBAAAA.',
Xu='Xuen:BAABLgAECn8VAAImAAcJ/hPuKwBgAQAmAAcJ/hPuKwBgAQABLgAFFAMJDwAFABAkAA==.',
Ya='Yajsooblwj:BAAALgADCgMJAwAAAA==.',
Za='Zal:BAACLgAFFH8FAAIlAAMJrhsFKwDSAAAlAAMJrhsFKwDSAAAuAAQKfyEABCUACQlPGR8kAOQBACUACQlPGR8kAOQBAAUABwlsFo6aAEABAAwAAgkNFWQ0AHYAAAAA.Zall:BAAALgAFFAEJAQAAAA==.Zankanohalco:BAAALgADCgEJAQAAAA==.Zanor:BAAALgAECgIJAgAAAA==.Zarranora:BAAALgAECgEJAQAAAA==.Zatannå:BAAALgADCgYJCQAAAA==.',
Ze='Zect:BAABLgAECn8sAAIKAAkJUROiSwD4AQAKAAkJUROiSwD4AQAAAA==.Zenshin:BAAALgAECgMJAwAAAA==.Zentaur:BAAALgAECgkJDQAAAA==.Zetzu:BAABLgAECn8cAAIcAAgJHRvVBQB9AQAcAAgJHRvVBQB9AQAAAA==.',
Zi='Zitfrlt:BAABLgAECn8UAAIcAAYJexfWCAAtAQAcAAYJexfWCAAtAQABLgAFFAQJEAADAFkQAA==.',
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
