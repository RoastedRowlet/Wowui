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

local lookup = {'Monk-Brewmaster','Hunter-BeastMastery','Hunter-Survival','Unknown-Unknown','Paladin-Retribution','Priest-Discipline','Priest-Shadow','Hunter-Marksmanship','Mage-Frost','Priest-Holy','Paladin-Protection','Warrior-Protection','DeathKnight-Unholy','Shaman-Restoration','Shaman-Elemental','Druid-Feral','DemonHunter-Havoc','Warlock-Demonology','Warlock-Destruction','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Monk-Mistweaver','DemonHunter-Devourer','Warrior-Arms','Warrior-Fury','Druid-Restoration','DeathKnight-Frost','DeathKnight-Blood','Druid-Guardian','Warlock-Affliction','Druid-Balance','Shaman-Enhancement','Rogue-Assassination','Rogue-Outlaw','Paladin-Holy','Monk-Windwalker','Rogue-Subtlety','Mage-Arcane',}
local provider = {region='US',realm='Wildhammer',name='US',type='weekly',zone=46,date='2026-06-21',data={Aa='Aayrawn:BAAALgAECgcJBwAAAA==.',
Ab='Abaddonaxx:BAAALgADCgYJBgAAAA==.',
Ac='Aceshaman:BAAALgAECggJCgAAAA==.Acesmash:BAABLgAECn8lAAIBAAkJGCJaBgDWAgABAAkJGCJaBgDWAgAAAA==.Ackrenezoth:BAAALgAECgQJBwAAAA==.',
Ad='Adymisk:BAAALgADCgEJAQAAAA==.',
Ag='Agorot:BAAALgAFFAEJAQAAAA==.',
Ak='Akadion:BAAALgADCgcJCgAAAA==.Akatali:BAAALgAECgQJBgAAAA==.',
Al='Aldannia:BAABLgAECn8VAAMCAAcJ4A/QVwBhAQACAAcJ8wzQVwBhAQADAAYJ7gwGNAAQAQAAAA==.Alextros:BAEALgAECgYJEQABLgAECgcJCgAEAAAAAA==.Alloren:BAAALgAECgQJBgAAAA==.Almond:BAAALgAECgEJAgAAAA==.',
Am='Amaranthe:BAAALgAECgEJAQAAAA==.Amrax:BAABLgAECn80AAIFAAkJpRVcPgAMAgAFAAkJpRVcPgAMAgAAAA==.Amynre:BAABLgAECn8aAAMGAAkJKRCfFQD5AQAGAAkJKRCfFQD5AQAHAAMJ6w33VABvAAAAAA==.',
An='Anarsa:BAAALgAECgUJCgAAAA==.Angstyboi:BAAALgAECgQJBAAAAA==.',
Aq='Aquabat:BAACLgAFFH8cAAQIAAQJ8h1+EQBMAQAIAAQJ4xt+EQBMAQADAAMJdBcvAwCyAAACAAMJ0BcCeQCmAAAuAAQKfyYABAMACQlHIgAGAMQCAAMACQmFIAAGAMQCAAgABwmrH38bAEwCAAIABQlwJRgoABgCAAAA.',
Ar='Arvyy:BAABLgAECn8mAAIJAAkJWBrzLABlAgAJAAkJWBrzLABlAgAAAA==.',
As='Ashbringer:BAACLgAFFH8NAAIFAAMJECTHQwAjAQAFAAMJECTHQwAjAQAuAAQKfyYAAgUACQlgI8EWALoCAAUACQlgI8EWALoCAAAA.',
At='Atria:BAACLgAFFH8IAAIJAAQJtQxAdgDvAAAJAAQJtQxAdgDvAAAuAAQKfycAAgkACAlfF+FFAAkCAAkACAlfF+FFAAkCAAAA.Attia:BAABLgAECn8bAAMKAAkJVBYTHQDdAQAKAAkJVBYTHQDdAQAHAAIJDRVUaAB8AAAAAA==.',
Av='Avaris:BAAALgADCgIJAgAAAA==.Avatarbambi:BAAALgADCgUJAgAAAA==.',
Aw='Away:BAAALgAECgYJBgABLgAECgkJJwALAFoQAA==.',
Ax='Axtar:BAABLgAECn8nAAIMAAkJvhu8CwAyAgAMAAkJvhu8CwAyAgAAAA==.',
Ay='Ayyitzrich:BAAALgADCgQJBAAAAA==.',
Ba='Babarazzar:BAAALgADCgYJBgAAAA==.Baladoria:BAACLgAFFH8NAAIKAAUJVxJrFwACAQAKAAUJVxJrFwACAQAuAAQKfzsAAgoACQkuIhcEAEUDAAoACQkuIhcEAEUDAAAA.Baldkrank:BAAALgAECgEJAQAAAA==.Bananabowman:BAAALgAECgEJAgAAAA==.Barrels:BAABLgAECn8lAAMCAAkJux7LIgBZAgACAAgJLx3LIgBZAgADAAkJnBUQFAAFAgABLgAFFAIJBQANAP4PAA==.Bartab:BAABLgAECn87AAMOAAkJLR7vDADxAgAOAAkJLR7vDADxAgAPAAEJEwPuvwAeAAABLgAECgkJPwAQADEhAA==.Baruku:BAAALgAFFAEJAQAAAA==.Bashfulwaltz:BAAALgAECgcJBwAAAA==.Bastadi:BAABLgAFFH8GAAMOAAIJJyMmTADBAAAOAAIJJyMmTADBAAAPAAEJSB4uCgBdAAAAAA==.',
Be='Bearemy:BAAALgAECgcJBwAAAA==.Beastling:BAAALgAECgYJDwAAAA==.Beau:BAACLgAFFH8MAAIRAAQJvyNBBwCTAQARAAQJvyNBBwCTAQAuAAQKfzcAAhEACQmFJX8CAD0DABEACQmFJX8CAD0DAAAA.Beauchi:BAAALgAECgUJBQABLgAFFAQJDAARAL8jAA==.Beauwi:BAAALgAECgQJBgABLgAFFAQJDAARAL8jAA==.Beldin:BAAALgAECgEJAQAAAA==.',
Bi='Bigshekels:BAAALgAECgEJAQAAAA==.Bigulsworth:BAAALgADCgcJCAAAAA==.',
Bl='Blackadder:BAAALgAECgcJEgAAAA==.Blawkk:BAAALgAECgYJBgAAAA==.Blenton:BAAALgAECgEJAQAAAA==.Bloodussy:BAAALgADCgUJBQAAAA==.Bluck:BAAALgADCgcJEQAAAA==.Blueeyesdrag:BAAALgADCgEJAQAAAA==.Blueombre:BAAALgAECgEJAQAAAA==.',
Bo='Boing:BAAALgAFFAIJAgAAAA==.Boltngo:BAAALgADCgIJAgAAAA==.Bombur:BAACLgAFFH8HAAISAAMJVxa+bwDiAAASAAMJVxa+bwDiAAAuAAQKfy8AAxIACQlSHGUlAEgCABIACQlSHGUlAEgCABMAAQkAAB1kAEYAAAAA.Bosstradamus:BAAALgAFFAEJAQABLgAFFAIJAgAEAAAAAA==.Boston:BAAALgAECggJEwAAAA==.Bottles:BAABLgAFFH8FAAINAAIJ/g9D4gCDAAANAAIJ/g9D4gCDAAAAAA==.',
Br='Braesong:BAAALgAECgIJAgAAAA==.Bratva:BAAALgAECgkJCgAAAA==.',
Bu='Bubagony:BAAALgAFFAEJAQABLgAFFAUJEwANAPAgAA==.Bubbells:BAAALgADCgEJAQAAAA==.Bullmedic:BAAALgADCgYJBgAAAA==.Burakku:BAABLgAECn8VAAQUAAcJEhnTGgDzAQAUAAcJEhnTGgDzAQAVAAUJJwgCMQDpAAAWAAEJAAC0PgA1AAABLgAFFAUJCwAXAKwYAA==.Burguerkiing:BAAALgADCgMJAwAAAA==.Burph:BAAALgADCggJCAAAAA==.Buttonsmash:BAAALgAECgcJEAABLgAFFAgJJwAVAAgSAA==.Buzzkill:BAAALgAECgQJAwAAAA==.',
['Bâ']='Bâbyrage:BAAALgADCgcJDwAAAA==.',
Ca='Cairen:BAABLgAECn8lAAIYAAkJMh6fIQBMAgAYAAkJMh6fIQBMAgAAAA==.Calzraxx:BAABLgAECn8UAAQZAAcJdxLhMAAEAQAZAAcJPwvhMAAEAQAMAAQJOhOULQDVAAAaAAMJ7ASyjQCIAAAAAA==.Carstaller:BAAALgAECgQJBAAAAA==.Cartons:BAABLgAECn8VAAIFAAgJySAwEwD5AgAFAAgJySAwEwD5AgABLgAFFAIJBQANAP4PAA==.',
Cc='Ccaan:BAAALgAECgkJEQAAAA==.Ccian:BAAALgAECgQJBAAAAA==.',
Ce='Celinn:BAACLgAFFH8IAAMKAAQJxQ69IQCtAAAKAAMJnhK9IQCtAAAGAAIJzAVSQgBxAAAuAAQKfzgAAwoACQkPHZIMAJ0CAAoACQkPHZIMAJ0CAAYABwnLFI8gAMkBAAAA.',
Ch='Chadgar:BAAALgADCgUJBwAAAA==.Chalupacabra:BAAALgADCgIJAgAAAA==.Chappie:BAAALgAECgEJAQABLgAFFAQJHAAIAPIdAA==.Charliek:BAABLgAFFH8IAAIaAAQJQA2IKQAPAQAaAAQJQA2IKQAPAQAAAA==.Cherches:BAAALgADCgEJAQAAAA==.Childish:BAAALgAECgYJDQAAAA==.Chimalma:BAAALgAFFAIJBAAAAA==.Chiqui:BAAALgAECgEJAgAAAA==.Chorr:BAAALgAFFAEJAQABLgAFFAIJBAAEAAAAAA==.',
Cl='Clarabow:BAAALgAFFAIJAwAAAA==.Closure:BAABLgAECn8YAAIbAAkJJSPbDADWAgAbAAkJJSPbDADWAgAAAA==.Cloudsx:BAAALgADCgMJAwAAAA==.',
Co='Coatlicue:BAABLgAECn8UAAMKAAkJFx+hEQBVAgAKAAgJRSGhEQBVAgAHAAUJZBTFMQBXAQABLgAFFAIJBAAEAAAAAA==.Coby:BAABLgAECn8XAAIXAAgJrCQkCQAJAwAXAAgJrCQkCQAJAwAAAA==.Coffins:BAAALgAECgYJEQABLgAFFAIJBQANAP4PAA==.Corgartah:BAAALgAECgMJAwAAAA==.Covell:BAAALgAECgcJDAAAAA==.',
Cr='Crates:BAAALgAECgUJCAABLgAFFAIJBQANAP4PAA==.Crimsonmagic:BAAALgAECgEJAgAAAA==.Crosswalkk:BAAALgADCgMJAwAAAA==.Crygore:BAAALgAECgQJCgABLgAECgIJBgAEAAAAAA==.',
Cu='Curonconagua:BAAALgAECgMJAwAAAA==.',
Cy='Cypherrellik:BAABLgAECn8cAAMRAAkJhRCiHwB9AQARAAkJhRCiHwB9AQAYAAIJHgIg2QA9AAAAAA==.',
['Cò']='Còrgi:BAAALgAECgEJAgABLgAECgkJPQANAIAhAA==.',
Da='Daktok:BAAALgADCgQJBAAAAA==.Damer:BAAALgADCgkJFgAAAA==.Damues:BAAALgAECggJDwAAAA==.Danaric:BAAALgAECgMJBgAAAA==.Dannyphentom:BAABLgAECn8XAAQNAAYJVxUAmAA5AQANAAYJVxUAmAA5AQAcAAMJxhdQJACtAAAdAAMJmA4qNgCQAAAAAA==.Dargar:BAAALgAECgEJAQAAAA==.Darkling:BAABLgAECn8dAAIRAAcJoB03FADwAQARAAcJoB03FADwAQAAAA==.Darknyss:BAAALgAECgEJAQAAAA==.',
De='Deathfortres:BAAALgAECgcJDAAAAA==.Dedeye:BAAALgADCgMJAwAAAA==.Deidara:BAAALgAECgYJAQAAAA==.Dekumime:BAAALgAECggJCwAAAA==.Demandred:BAAALgAECgkJEwAAAA==.Demongrass:BAACLgAFFH8KAAIYAAUJexmfQAAmAQAYAAUJexmfQAAmAQAuAAQKfzIAAhgACAkyIMIrABkCABgACAkyIMIrABkCAAAA.Denaric:BAAALgAECgYJEAAAAA==.Derty:BAAALgAFFAIJAwAAAA==.',
Di='Diviñehymn:BAAALgAECgcJDwAAAA==.',
Do='Donet:BAAALgADCgEJAQAAAA==.Doodaad:BAAALgAECgEJAgAAAA==.Doppy:BAAALgADCgYJBgAAAA==.Doublerack:BAAALgAECgIJAgABLgAECgIJBgAEAAAAAA==.',
Dr='Dragondeezz:BAAALgAECgIJBAABLgAECgIJBgAEAAAAAA==.Dragondznuts:BAACLgAFFH8nAAIVAAgJCBJICwDzAQAVAAgJCBJICwDzAQAuAAQKfz0ABBUACQluHuYFALACABUACQluHuYFALACABQAAgnoHjdlAKsAABYAAglHCJ0fAFUAAAAA.Draxtos:BAEALgAECgcJCgAAAA==.Dreamevil:BAAALgAECgkJBgAAAA==.Drroxso:BAAALgAECgQJBAAAAA==.Dríppy:BAAALgAECgYJCgAAAA==.',
Ea='Eazybake:BAAALgADCgEJAQAAAA==.',
Ei='Eilerra:BAABLgAECn8rAAIJAAgJBCE9IgCUAgAJAAgJBCE9IgCUAgAAAA==.',
El='Elementony:BAABLgAECn85AAIPAAkJpBB0IwD1AQAPAAkJpBB0IwD1AQAAAA==.Elkdruid:BAABLgAECn8eAAMbAAgJxBCXTwBnAQAbAAgJxBCXTwBnAQAeAAEJQAzlNgAbAAABLgAFFAQJCwACAJAVAA==.Elladamri:BAAALgAECgEJAQAAAA==.Elodi:BAAALgAECgEJAQAAAA==.',
Em='Emberglow:BAAALgAECgcJEgAAAA==.Empyrean:BAAALgADCgQJBQAAAA==.Emylia:BAAALgAECgcJEAAAAA==.',
Er='Eresdelor:BAABLgAECn8YAAMMAAkJlRPfFwCBAQAMAAkJzhHfFwCBAQAZAAQJLA4XJwC2AAAAAA==.Erre:BAABLgAECn8mAAISAAkJ5h5uHAB6AgASAAkJ5h5uHAB6AgAAAA==.',
Es='Esdeáth:BAAALgADCgEJAQAAAA==.Estia:BAAALgAECgcJCwABLgAFFAIJBAAEAAAAAA==.',
Ev='Evoktor:BAAALgAECgEJAQAAAA==.',
Ex='Exxitwound:BAAALgAECgEJAQAAAA==.',
Fa='Facasdeath:BAAALgAECgYJDAAAAA==.Failure:BAEBLgAECn8cAAIDAAkJ+hQcDQD6AQADAAkJ+hQcDQD6AQABLgAFFAQJDwABACsYAA==.Farmtoon:BAAALgAECgYJDQAAAA==.Fartbroknvis:BAAALgAFFAIJAgAAAA==.',
Fe='Feardapain:BAACLgAFFH8SAAISAAQJLxe3SwAvAQASAAQJLxe3SwAvAQAuAAQKfz0ABBIACQk5IhUPAAEDABIACAk5IhUPAAEDABMAAQkAADFcAFoAAB8AAQkAAP84AAwAAAAA.Feardatpain:BAAALgAFFAEJAQAAAA==.Fellyn:BAAALgADCggJCwAAAA==.',
Ff='Ff:BAABLgAFFH8LAAIJAAMJwADmoQCLAAAJAAMJwADmoQCLAAAAAA==.',
Fl='Flar:BAAALgAFFAEJAQAAAA==.Flixie:BAABLgAECn8gAAMOAAkJQSH7BQBRAwAOAAkJQSH7BQBRAwAPAAEJByCmiQBdAAABLgAFFAcJLgAXAAcXAA==.Flyingcow:BAAALgAECgkJDwAAAA==.',
Fo='Foenix:BAAALgADCgYJBgAAAA==.Foxoffire:BAAALgAECgMJBwAAAA==.Foxu:BAAALgAECgcJBwAAAA==.Foxymoron:BAAALgAECgcJCwAAAA==.Fozzi:BAABLgAECn8oAAIXAAkJQSFICAAYAwAXAAkJQSFICAAYAwAAAA==.',
Fr='Freakazoid:BAABLgAECn8wAAIHAAkJjx3cEQBGAgAHAAkJjx3cEQBGAgAAAA==.Fritark:BAAALgAECgcJBwABLgAECgkJFAAgACcXAA==.Fritzyp:BAABLgAECn8UAAMgAAkJJxd4OwAkAQAgAAcJBxl4OwAkAQAbAAUJtAgSgQC4AAAAAA==.Frogzqc:BAAALgAECgEJAgAAAA==.Frostyburn:BAAALgAECgYJEQAAAA==.Frozenrage:BAAALgADCgcJCwAAAA==.',
['Fë']='Fëanor:BAAALgAECggJCwAAAA==.',
Ga='Gabos:BAAALgADCgEJAQAAAA==.Garayice:BAAALgADCgIJAgAAAA==.Garycoleman:BAAALgAECgQJBAAAAA==.Gaxxen:BAAALgAECgUJBQAAAA==.',
Ge='Gena:BAAALgADCgcJCAAAAA==.Geörge:BAACLgAFFH8ZAAIHAAgJkRZHBgAWAgAHAAgJkRZHBgAWAgAuAAQKfy8AAgcACAlVISIIAAIDAAcACAlVISIIAAIDAAAA.',
Gh='Ghostyganja:BAAALgAECgQJBAABLgAFFAMJBQAUAHYWAA==.',
Gi='Giratiña:BAAALgAECgEJAgABLgAFFAIJAwAEAAAAAA==.',
Gl='Glary:BAAALgAECgEJAQAAAA==.Glavendale:BAAALgADCgUJBQAAAA==.',
Go='Goatcheezey:BAAALgADCgYJDAAAAA==.Goblinsox:BAAALgAECgQJBAAAAA==.Goluck:BAAALgAECgEJAQAAAA==.Gordothe:BAAALgADCgUJBQABLgAECgUJBgAEAAAAAA==.',
Gr='Gremfrost:BAACLgAFFH8LAAIJAAMJ0glfigDEAAAJAAMJ0glfigDEAAAuAAQKfyEAAgkACQmkEQpHAAYCAAkACQmkEQpHAAYCAAAA.Grimel:BAAALgAECgQJCAABLgAECgYJEAAEAAAAAA==.Grimghoul:BAAALgAECgQJCQABLgAECgYJEAAEAAAAAA==.Grimgram:BAAALgAECgYJEAAAAA==.Gripyoulol:BAAALgAECgQJBQAAAA==.Grotelek:BAABLgAECn8hAAIhAAkJTRPkDgDCAQAhAAkJTRPkDgDCAQAAAA==.Grotret:BAAALgAECgIJAgAAAA==.Grouchy:BAAALgADCgMJAwAAAA==.Grumpywaltz:BAAALgAECgQJBAAAAA==.',
Gu='Gulimath:BAAALgAECgUJBgAAAA==.',
['Gà']='Gàrrosh:BAAALgADCgQJBAAAAA==.',
Ha='Haedrath:BAAALgAECgEJAgABLgAECggJKwAJAAQhAA==.Hahoa:BAAALgAECgEJAQAAAA==.Halconotachi:BAABLgAECn9FAAIDAAkJiRqlCgB0AgADAAkJiRqlCgB0AgAAAA==.Hammerfoot:BAAALgAFFAEJAgAAAA==.Haranir:BAAALgAECgYJCAAAAA==.Harcat:BAABLgAECn8dAAMIAAkJGBXyCwCnAQAIAAkJGBXyCwCnAQADAAEJYQGpbAAcAAAAAA==.Hartracks:BAAALgAECgUJBQAAAA==.Hatijo:BAAALgAECgYJBwAAAA==.Hawgbawl:BAABLgAECn8kAAIaAAkJnRvJGAAoAgAaAAkJnRvJGAAoAgAAAA==.Hawgdream:BAAALgAECgcJEgAAAA==.',
He='Hellequin:BAACLgAFFH8ZAAIiAAcJJhcrAQD3AQAiAAcJJhcrAQD3AQAuAAQKfzkAAyIACQkDIj0BACsDACIACQkDIj0BACsDACMAAQkpA4cPACoAAAAA.Henkojin:BAAALgADCgYJBgAAAA==.Heyitzlock:BAAALgAECgYJCQAAAA==.Heyyitzrich:BAAALgAECgQJDQAAAA==.Heyyitzrichh:BAABLgAFFH8JAAISAAMJzBaibwDjAAASAAMJzBaibwDjAAAAAA==.Heyytaco:BAAALgAECggJEgAAAA==.',
Hi='Hiels:BAAALgAECgcJBwAAAA==.Hirogon:BAAALgAECgEJAwAAAA==.',
Ho='Hobb:BAABLgAECn8pAAIFAAkJcB5sHgCQAgAFAAkJcB5sHgCQAgAAAA==.Holenmymuff:BAAALgADCgUJBQAAAA==.Hollinar:BAABLgAECn8YAAIJAAkJxxLtcADyAQAJAAkJxxLtcADyAQAAAA==.Holyfaux:BAAALgADCgYJBgAAAA==.Holysteel:BAAALgAECgIJAwAAAA==.Hondoe:BAAALgAECgQJCAAAAA==.Hordecow:BAAALgAECgIJAgABLgAFFAEJAgAEAAAAAA==.Hornhelm:BAAALgAECgIJBgAAAA==.',
Hu='Huntoor:BAAALgAECgEJAQABLgAECgYJBgAEAAAAAA==.',
Ic='Icemark:BAACLgAFFH8FAAIJAAMJfxI1KwAJAQAJAAMJfxI1KwAJAQAuAAQKfx8AAgkABwkGHShXADMCAAkABwkGHShXADMCAAAA.',
Ih='Ihavecookies:BAAALgAECgQJBQAAAA==.',
Ij='Ijur:BAAALgAECgQJCAABLgAECgUJBgAEAAAAAA==.',
Ik='Ikayro:BAABLgAECn8cAAIJAAgJdx2AKgDJAgAJAAgJdx2AKgDJAgAAAA==.',
Il='Ilostmyphone:BAAALgAECgEJAQAAAA==.Ilovemysword:BAAALgAECgUJCQAAAA==.Iluvatar:BAABLgAECn8eAAMHAAgJiiGPDQB7AgAHAAgJiiGPDQB7AgAGAAIJwxKOYQB2AAABLgAFFAEJAQAEAAAAAA==.',
Im='Imagine:BAABLgAECn8WAAQVAAkJaRDSDgDhAQAVAAkJaRDSDgDhAQAUAAYJFganPgDwAAAWAAEJtgLYKwAeAAAAAA==.',
In='Infoxticated:BAAALgAECgEJAQAAAA==.',
Ir='Iratedemon:BAAALgAECgMJBAABLgAECgMJAwAEAAAAAA==.Irateknight:BAAALgAECgMJAwAAAA==.Irely:BAAALgAECgIJAgAAAA==.',
Ja='Jadedways:BAAALgAECgEJAgAAAA==.Jasmirangel:BAACLgAFFH8RAAIbAAQJ6BkfKgARAQAbAAQJ6BkfKgARAQAuAAQKf0UAAhsACAkDJR8HAEUDABsACAkDJR8HAEUDAAAA.',
Je='Jede:BAAALgADCgMJAwAAAA==.',
Jo='Joshallen:BAAALgADCgcJBwAAAA==.',
Ju='Juka:BAABLgAECn8UAAIOAAkJGQd0WABVAQAOAAkJGQd0WABVAQAAAA==.Jukks:BAABLgAECn8UAAIMAAcJmgubJAAMAQAMAAcJmgubJAAMAQAAAA==.Juno:BAAALgADCgkJEwAAAA==.Justsumfoo:BAAALgAECgIJBAAAAA==.',
Ka='Kano:BAACLgAFFH8YAAMCAAYJehWcIgB7AQACAAYJehWcIgB7AQADAAEJKhQ+NABCAAAuAAQKfy4AAgIACQmIIwgLAPwCAAIACQmIIwgLAPwCAAAA.Karper:BAAALgAECgEJAQAAAA==.Kataga:BAAALgAECgEJAQAAAA==.Katarm:BAABLgAECn8UAAMMAAkJcgiDJQAGAQAMAAkJagSDJQAGAQAZAAUJNgwiQwC7AAAAAA==.Katarru:BAAALgAECgYJDQAAAA==.Kataru:BAAALgADCgIJAgAAAA==.Kayhaus:BAAALgAECgYJDAAAAA==.',
Kh='Khory:BAAALgAFFAIJBAAAAA==.',
Ki='Killrah:BAAALgAECgEJAgAAAA==.Kirito:BAAALgADCgYJBgAAAA==.',
Kk='Kkiinnoopp:BAABLgAECn8jAAMCAAgJiBYpeABPAQADAAYJVhYrFQB1AQACAAcJSxQpeABPAQAAAA==.',
Ko='Korgigor:BAAALgAECgQJBwAAAA==.Kovu:BAAALgAECgcJEgAAAA==.',
Kr='Krisanthemum:BAAALgADCgcJCwAAAA==.Krystrasz:BAAALgAECgQJCwAAAA==.',
Kt='Kt:BAAALgADCgIJAgABLgAECgQJBAAEAAAAAA==.Ktrogue:BAAALgAECgQJBAAAAA==.',
Ku='Kuailiang:BAAALgAECgcJCwAAAA==.Kuraihikari:BAAALgAFFAEJAQAAAA==.Kustaa:BAAALgADCgkJCgABLgAECgkJLAAkAIsXAA==.',
La='Ladezar:BAAALgADCgcJDQAAAA==.Laissen:BAAALgAECgYJCAAAAA==.Lapsung:BAAALgAECgIJBAABLgAECgkJGwAKAFQWAA==.Lattemocha:BAABLgAECn8tAAMbAAkJ3x6eMADpAQAbAAYJLR2eMADpAQAgAAkJBhLYIADCAQAAAA==.',
Le='Lenden:BAAALgAECgMJBgAAAA==.Leprechaun:BAAALgADCgcJCQAAAA==.Leví:BAAALgADCgUJBQAAAA==.Leylas:BAAALgAECgEJAgAAAA==.',
Li='Lighthoove:BAAALgAECgcJBwAAAA==.Lightswìtch:BAAALgADCgEJAQAAAA==.Lilliaz:BAAALgAECgYJBwAAAA==.Linianna:BAAALgAECgYJEgAAAA==.Liriel:BAAALgAECgcJBwAAAA==.',
Lu='Ludlow:BAABLgAECn8dAAICAAgJEgpHgQA8AQACAAgJEgpHgQA8AQAAAA==.Lunastra:BAACLgAFFH8KAAIJAAQJERJBhADPAAAJAAQJERJBhADPAAAuAAQKfyYAAgkACAlOHKFKAPsBAAkACAlOHKFKAPsBAAEuAAUUAgkEAAQAAAAA.Luneztoprime:BAAALgAECgYJCgAAAA==.',
Ly='Lydarra:BAAALgAECgQJBwABLgAECgYJFQAaAFAZAA==.Lyiann:BAAALgADCggJEgAAAA==.Lyákadion:BAAALgAECgEJAQAAAA==.',
['Lâ']='Lâdypriest:BAAALgADCgUJBQAAAA==.',
Ma='Mafi:BAABLgAECn8WAAICAAcJ/RmyXACPAQACAAcJ/RmyXACPAQAAAA==.Maggore:BAAALgAECgIJBgAAAA==.Magikiwiks:BAAALgAECgEJAQAAAA==.Magsdk:BAAALgAFFAIJAgABLgAFFAgJJAAUAKEcAA==.Mainlander:BAAALgAECgMJAwAAAA==.Malbogea:BAAALgAFFAEJAQAAAA==.Malusmittens:BAAALgAECgQJBQABLgAFFAUJGwACADsjAA==.Mantonso:BAABLgAECn8xAAIaAAkJDSCiDQCUAgAaAAkJDSCiDQCUAgAAAA==.Manus:BAAALgADCgIJAgAAAA==.Matt:BAACLgAFFH8JAAIbAAQJMQsFNwDQAAAbAAQJMQsFNwDQAAAuAAQKfyoAAhsACQkiHWwNAO8CABsACQkiHWwNAO8CAAAA.',
Me='Meddicus:BAAALgAECgUJCAAAAA==.Meechydarko:BAAALgAECgUJBQABLgAFFAQJCQADAP4TAA==.Megalomaniä:BAAALgADCgYJBgABLgAECgcJHgAfAKYYAA==.Megorice:BAABLgAFFH8FAAISAAIJhAT4tQBsAAASAAIJhAT4tQBsAAAAAA==.Megå:BAABLgAECn8eAAMfAAcJphirFwAHAQASAAYJmBc4dQBPAQAfAAUJmBurFwAHAQAAAA==.Mewtwô:BAAALgAECgYJBwAAAA==.',
Mi='Microbrew:BAAALgAECgMJBQAAAA==.Miezra:BAAALgAECgYJCAAAAA==.Mikah:BAAALgAECgYJDwAAAA==.',
Mo='Modayus:BAAALgAECgEJAQAAAA==.Mojomittens:BAACLgAFFH8bAAICAAUJOyPcHgCJAQACAAUJOyPcHgCJAQAuAAQKfyIAAwIABwlEJK8pADcCAAIABwlEJK8pADcCAAgABQnAFqRAAFcBAAAA.Monstermime:BAAALgAECgIJAgABLgAECggJCwAEAAAAAA==.Monstroqt:BAAALgADCgQJBAAAAA==.Moobiez:BAAALgADCggJCQAAAA==.Moonpièz:BAAALgAECgEJAQAAAA==.Morøs:BAAALgADCgYJBgAAAA==.Moxx:BAABLgAECn8ZAAIlAAkJtw4kNAAzAQAlAAkJtw4kNAAzAQAAAA==.',
Mu='Muffers:BAABLgAECn83AAIlAAkJAxMuGgDgAQAlAAkJAxMuGgDgAQAAAA==.Muffpuff:BAAALgAECgQJBQAAAA==.Mutige:BAAALgADCgEJAQAAAA==.',
My='Mylotus:BAAALgAECgQJBQAAAA==.',
Na='Napkuntt:BAAALgAECgEJAQAAAA==.Napokin:BAAALgAFFAEJAgAAAA==.Napshade:BAABLgAECn8cAAMHAAcJyhvALABwAQAHAAYJ/xzALABwAQAKAAYJEhApSQDAAAABLgAFFAEJAgAEAAAAAA==.Natsuu:BAAALgAECgcJDAAAAA==.',
Nb='Nbayoungboyy:BAAALgADCgYJBgABLgAFFAYJHgACAIYhAA==.',
Ne='Necroticoath:BAAALgAECgIJBgABLgAFFAIJBgAOACcjAA==.Neuro:BAAALgAFFAMJBAAAAA==.Neven:BAAALgAECgIJAgAAAA==.',
Ni='Nightor:BAAALgAECgEJAQAAAA==.Nightvenge:BAAALgAFFAMJBAAAAA==.Nikodemos:BAAALgAFFAgJGgAAAQ==.Nivahoof:BAAALgADCgEJAQAAAA==.',
No='Noc:BAABLgAECn8rAAMSAAgJLBl+OAD3AQASAAgJLBl+OAD3AQATAAUJNA+JLQAHAQABLgAFFAMJBgASAF8QAA==.Nomemage:BAAALgADCgEJAQAAAA==.',
Ob='Obe:BAAALgAFFAIJAgAAAA==.Obsidiangel:BAAALgADCggJEAAAAA==.',
Oh='Ohface:BAAALgAECgQJBwABLgAECgIJBgAEAAAAAA==.',
Oo='Oowu:BAAALgADCgkJFAAAAA==.',
Or='Oran:BAABLgAECn8YAAIFAAgJaxi4UwDOAQAFAAgJaxi4UwDOAQAAAA==.Orb:BAAALgAECgYJBgAAAA==.Orctrax:BAABLgAECn8aAAMCAAgJVRGrdwBQAQACAAgJVRGrdwBQAQAIAAEJBALAjgAsAAAAAA==.Oricale:BAAALgAECgYJBgAAAA==.',
Os='Osheat:BAACLgAFFH8FAAINAAMJJg0drQDGAAANAAMJJg0drQDGAAAuAAQKfyMAAg0ACQndHzYpAFwCAA0ACQndHzYpAFwCAAAA.Osmodeus:BAAALgAECgUJCAAAAA==.',
Ou='Outplay:BAAALgADCgUJBQAAAA==.',
Ox='Ox:BAAALgAECgEJAQAAAA==.Oxheart:BAAALgAECgEJAQAAAA==.',
Oz='Ozzymo:BAAALgAECgcJCwAAAA==.',
Pa='Paltis:BAAALgAECgQJBQAAAA==.Paltonso:BAAALgADCgkJCQAAAA==.Pandaari:BAABLgAECn8WAAIHAAgJFAQtTADfAAAHAAgJFAQtTADfAAAAAA==.Papaschristo:BAAALgADCgUJBQAAAA==.Papasdiablo:BAAALgAECgEJAgAAAA==.Parprapa:BAAALgADCgMJAwAAAA==.',
Pe='Penicillin:BAAALgAECgMJAwAAAA==.Persimmon:BAACLgAFFH8OAAIkAAQJVxyFGwBDAQAkAAQJVxyFGwBDAQAuAAQKfyAAAiQABwmTF/4qALgBACQABwmTF/4qALgBAAAA.Peyton:BAAALgAECgUJBwAAAA==.',
Ph='Philip:BAAALgADCgcJDAAAAA==.Phyrie:BAAALgAECgUJDwABLgAECgYJFQAaAFAZAA==.',
Pi='Pittpete:BAAALgAECgEJAQAAAA==.',
Pl='Plaguepapi:BAAALgAFFAEJAQAAAA==.',
Po='Pollocaotico:BAAALgAFFAIJAgAAAA==.',
Ps='Psythera:BAAALgAECgIJBAABLgAECggJIgAHAPIcAA==.Psythern:BAAALgADCgYJCQABLgAECggJIgAHAPIcAA==.',
Pu='Punkybrewstr:BAABLgAECn8xAAMBAAgJjhZFJACKAQABAAcJURZFJACKAQAlAAgJswr0MABjAQAAAA==.Pureshock:BAAALgAECggJDQAAAA==.Purpderf:BAAALgAFFAEJAQAAAA==.',
Pw='Pwnstar:BAAALgAECgQJCAAAAA==.',
Py='Pykei:BAAALgAECgQJBgAAAA==.Pyrrah:BAAALgAECgEJAQABLgAECgkJJAAGAEIdAA==.Pyrri:BAABLgAECn8kAAQGAAkJQh2vFAA3AgAGAAgJaB6vFAA3AgAKAAQJ4RXjUQDwAAAHAAMJdRSOWgCrAAAAAA==.Pyrria:BAABLgAECn8XAAMOAAkJvySdBgBGAwAOAAgJeySdBgBGAwAPAAUJJhXyQgAnAQABLgAECgkJJAAGAEIdAA==.Pyrris:BAAALgAECgMJAwABLgAECgkJJAAGAEIdAA==.',
Pz='Pznt:BAAALgAECgEJAQAAAA==.',
['Pé']='Péyton:BAAALgAECggJDwAAAA==.',
['Pì']='Pì:BAAALgADCgEJAgAAAA==.',
['Pô']='Pôws:BAAALgAECgIJAwAAAA==.',
Qu='Quantonbomb:BAABLgAECn8UAAIbAAkJehm8EwCtAgAbAAkJehm8EwCtAgAAAA==.Quezera:BAAALgAECgEJAQAAAA==.',
Ra='Rabuf:BAABLgAECn8sAAMkAAkJixd1EgB+AgAkAAkJixd1EgB+AgAFAAYJpQ6nwQAGAQAAAA==.Raccoonadin:BAAALgADCgEJAQAAAA==.Radha:BAAALgAECgIJAgABLgAFFAUJEwANAPAgAA==.Ragingwater:BAAALgAECgYJEAAAAA==.Ranadheer:BAAALgAFFAEJAQAAAA==.Raspaigus:BAAALgAECgQJBAAAAA==.Ratfu:BAABLgAECn8UAAIlAAYJOQX/RwD1AAAlAAYJOQX/RwD1AAAAAA==.Raudson:BAABLgAECn8UAAILAAkJDCJUAgATAwALAAkJDCJUAgATAwAAAA==.',
Re='Redizle:BAACLgAFFH8cAAIGAAgJcRZ8CQCNAgAGAAgJcRZ8CQCNAgAuAAQKfycABAoACAnxHBkoAK8BAAYACAn7FuUbALcBAAoABgkyHBkoAK8BAAcABQnSEug2ADYBAAAA.Reginrune:BAAALgAECgkJEwAAAA==.Resonance:BAABLgAECn8WAAMPAAcJHBYZOwBJAQAPAAcJ9RUZOwBJAQAhAAMJZwykIwCeAAAAAA==.Restroll:BAAALgADCgUJBQAAAA==.',
Rh='Rhaigar:BAAALgAECgUJCQAAAA==.Rhónatar:BAAALgADCgQJBAAAAA==.',
Ri='Righteouscow:BAAALgAECgEJAQAAAA==.',
Ro='Rohdoog:BAABLgAECn84AAIUAAkJoRdBFAA7AgAUAAkJoRdBFAA7AgAAAA==.Roundabugman:BAACLgAFFH8MAAIPAAMJrh2ILQDdAAAPAAMJrh2ILQDdAAAuAAQKfycAAw8ACAmSHgMhANwBAA8ACAmSHgMhANwBAA4AAwmnFOF3ALIAAAAA.',
Rr='Rr:BAABLgAFFH8NAAMjAAMJyAH+DgB1AAAmAAMJIAHaNgCEAAAjAAMJpAH+DgB1AAAAAA==.',
Ru='Runedyu:BAAALgAECgYJEQAAAA==.',
Ry='Ryanno:BAACLgAFFH8LAAICAAMJpxveUwABAQACAAMJpxveUwABAQAuAAQKfyoAAgIACQkwIEweAHACAAIACQkwIEweAHACAAAA.Ryannoo:BAAALgAECgYJBQAAAA==.Ryujinhalco:BAAALgAECgEJAQAAAA==.',
Sa='Sabim:BAAALgAECgEJAQAAAA==.Sahomi:BAACLgAFFH8QAAIGAAQJtA2mKQABAQAGAAQJtA2mKQABAQAuAAQKfyoAAwYACQk8EYcBADwBAAYACQk8EYcBADwBAAoAAglNBZR3AEwAAAAA.Salana:BAAALgADCgcJBwAAAA==.Samwise:BAAALgAECgYJCAAAAA==.Sarai:BAAALgADCgEJAQAAAA==.Sarcini:BAABLgAECn8uAAILAAkJXhvpBwBcAgALAAkJXhvpBwBcAgAAAA==.Satrina:BAACLgAFFH8NAAINAAQJqRWcYAA0AQANAAQJqRWcYAA0AQAuAAQKfyQAAg0ACAmrIlwzADECAA0ACAmrIlwzADECAAAA.Savvy:BAAALgAECgUJBQABLgAECgYJBgAEAAAAAA==.',
Sc='Scrappy:BAAALgAECgEJAQAAAA==.',
Se='Sedna:BAAALgADCgYJBgABLgAECgYJCAAEAAAAAA==.Selanthe:BAAALgAECgQJBgAAAA==.Seruk:BAAALgAECgEJBAAAAA==.Sevaronk:BAAALgAECgYJBwAAAA==.Seventhghost:BAEALgAECgQJBQABLgAFFAUJEAAHAN0WAA==.',
Sh='Shadowstorme:BAAALgAECgIJBQAAAA==.Shamander:BAABLgAECn8eAAIOAAkJQxj1IgA9AgAOAAkJQxj1IgA9AgAAAA==.Shamsham:BAAALgADCgcJDAAAAA==.Sharabuf:BAAALgAECgEJAQAAAA==.Sharky:BAAALgADCgQJBAAAAA==.Shocka:BAAALgADCgcJCQAAAA==.Shokanki:BAAALgAECgYJCwAAAA==.Shutupcat:BAAALgADCgQJBAABLgADCgUJBQAEAAAAAA==.',
Si='Sicara:BAABLgAECn8uAAIYAAkJQhaoPwDKAQAYAAkJQhaoPwDKAQAAAA==.Silentmage:BAAALgADCgcJCAAAAA==.Silentslock:BAAALgADCgYJBQAAAA==.Sillylilguy:BAACLgAFFH8JAAIhAAMJnBE3AwADAQAhAAMJnBE3AwADAQAuAAQKfxgAAiEACAmEH+8EAMECACEACAmEH+8EAMECAAAA.Sinestro:BAAALgAECgMJAwAAAA==.Sivrogar:BAAALgAECgMJAwAAAA==.',
Sl='Slaik:BAAALgAECgUJDgAAAA==.Slander:BAACLgAFFH8bAAMNAAYJsx7pMwCaAQANAAYJsx7pMwCaAQAdAAEJAADRYAAAAAAuAAQKfz8AAg0ACQnVIwYBADACAA0ACQnVIwYBADACAAAA.',
So='Solemnograve:BAAALgAECgIJAgAAAA==.Somazugzug:BAACLgAFFH8PAAIOAAQJUBtjKwA2AQAOAAQJUBtjKwA2AQAuAAQKfyUAAg4ACQm5GV8uANABAA4ACQm5GV8uANABAAAA.Sothren:BAAALgAECgQJBQABLgADCgkJCQAEAAAAAA==.Souchong:BAAALgAECgIJAgABLgAECgkJGwAKAFQWAA==.',
Sp='Spacedguy:BAAALgADCgMJAwAAAA==.Spry:BAAALgAECgEJAQAAAA==.',
St='Staccato:BAAALgAECgEJAQAAAA==.Stanleyy:BAAALgAFFAEJAgABLgAFFAIJBgAOACcjAA==.Starlight:BAAALgAECgIJAgAAAA==.Stepbrother:BAAALgAFFAIJAwABLgAFFAQJCQADAP4TAA==.',
Su='Sugar:BAABLgAECn8nAAMOAAkJ5RFMTQB8AQAOAAkJ5RFMTQB8AQAPAAUJtw6oVgDrAAAAAA==.Sugars:BAAALgAECgUJBAAAAA==.Sulin:BAAALgADCgUJBwAAAA==.Sungôd:BAAALgADCgEJAQABLgAECgkJMQABAI4WAA==.',
Sw='Swonks:BAAALgAECgMJAwAAAA==.Swyper:BAAALgAECgMJAwAAAA==.',
Sy='Synicism:BAAALgADCgcJDQAAAA==.',
Ta='Taintbubble:BAAALgAECgMJBQAAAA==.Tanktommy:BAAALgAECgUJCAABLgAFFAUJGQANAGwbAA==.Tarnished:BAAALgADCgcJCAAAAA==.Tarquitus:BAACLgAFFH8YAAMYAAgJcg2/BgAeAQAYAAcJcA+/BgAeAQARAAIJeAS+CgCTAAAuAAQKfzwAAxgACAmXIAgdAGYCABgACAnWHwgdAGYCABEACAm8F0sRAFUCAAAA.Tattoosguy:BAAALgADCgEJAQAAAA==.',
Te='Teef:BAABLgAECn8cAAImAAcJFxXyIwB1AQAmAAcJFxXyIwB1AQAAAA==.Tellan:BAAALgADCgcJBwAAAA==.',
Th='Thanatös:BAABLgAECn8cAAMJAAgJbBZYagCnAQAJAAgJbBZYagCnAQAnAAQJrxRDDQD1AAAAAA==.Tharros:BAAALgAECgcJDQAAAA==.Thedarkkness:BAABLgAECn8nAAIdAAkJIhfrFgCwAQAdAAkJIhfrFgCwAQAAAA==.Thekleener:BAAALgAECgEJAQAAAA==.Thorin:BAAALgAECgQJBAABLgAFFAIJBgAOACcjAA==.Thrasher:BAAALgAECgEJAwAAAA==.',
Ti='Tidalwave:BAACLgAFFH8OAAIOAAQJAh4DJgBSAQAOAAQJAh4DJgBSAQAuAAQKfy0AAw4ACQnFGSUhAEkCAA4ACQnFGSUhAEkCAA8AAgltC++tACoAAAAA.Tidus:BAAALgAECgYJEQAAAA==.Tinytotem:BAAALgAECgEJBAAAAA==.Tissue:BAABLgAECn8XAAIRAAcJCArULABjAQARAAcJCArULABjAQAAAA==.',
To='Toasted:BAAALgADCgYJCQABLgAECgMJAwAEAAAAAA==.Tobibi:BAAALgAFFAEJAQABLgAFFAIJBgAOACcjAA==.Todo:BAAALgADCgQJBAAAAA==.Tolip:BAABLgAECn8rAAMbAAgJUQgrdgD1AAAbAAYJgAgrdgD1AAAgAAgJSgSjSADpAAABLgAFFAEJAQAEAAAAAA==.Tolipally:BAAALgAFFAEJAQAAAA==.Tolipicious:BAAALgADCgUJCQABLgAFFAEJAQAEAAAAAA==.Topsykret:BAAALgAECgEJAgAAAA==.Topsyy:BAAALgAECgEJAQAAAA==.',
Tr='Trauts:BAAALgAECgQJCAAAAA==.Treeadin:BAABLgAECn8nAAILAAkJWhBNFwBmAQALAAkJWhBNFwBmAQAAAA==.Trollcula:BAAALgAECggJDgABLgAFFAQJCwACAJAVAA==.Truthwithin:BAAALgAECgUJEwAAAA==.',
Ts='Tsarrubus:BAABLgAECn8hAAIRAAkJcwk2JQBPAQARAAkJcwk2JQBPAQAAAA==.',
Tu='Tula:BAAALgAECgUJCwAAAA==.Tusck:BAAALgAECgYJEAAAAA==.',
Tw='Twingert:BAAALgAECgEJAQAAAA==.Twitch:BAAALgAECgYJEwAAAA==.',
Ty='Tyedyemess:BAAALgAECgMJAwAAAA==.Tyledridal:BAAALgAECgMJAwAAAA==.',
['Tà']='Tàylor:BAABLgAECn8cAAIkAAkJOQu1OgCPAQAkAAkJOQu1OgCPAQAAAA==.',
Ub='Ubbaa:BAAALgAECgEJAQAAAA==.',
Ul='Ulghar:BAABLgAECn8rAAIaAAkJNCXNAQBfAwAaAAkJNCXNAQBfAwAAAA==.',
Ur='Ursock:BAAALgAECggJDgAAAA==.',
Uw='Uwuhshake:BAABLgAECn8tAAMbAAkJ7SH2BABrAwAbAAkJ7SH2BABrAwAgAAEJqRvhegBRAAAAAA==.',
Va='Valdria:BAAALgAECgMJAwAAAA==.Valssien:BAAALgADCgkJCQAAAA==.Vanaria:BAAALgAECgQJBAAAAA==.Vanbrook:BAAALgAECgQJAgAAAA==.Vanden:BAAALgAECgYJDAAAAA==.Vanrion:BAAALgAFFAIJAwAAAA==.Varrodd:BAAALgAECgEJAQAAAA==.Vastextent:BAAALgAECgEJAQAAAA==.',
Ve='Velcro:BAAALgAECgYJEgAAAA==.Velsera:BAAALgAECgYJCAAAAA==.Velvet:BAAALgADCgQJCAAAAA==.Velyn:BAAALgAECgcJDwAAAA==.Velynara:BAAALgADCgIJAgABLgAECgYJCAAEAAAAAA==.Vengefulcry:BAAALgAECgMJAwAAAA==.Vengefül:BAAALgADCgYJCAAAAA==.Vexara:BAAALgAECgQJBAAAAA==.',
Wa='Wanaaga:BAAALgAECggJDgAAAA==.',
We='Wedge:BAAALgAECgEJAQAAAA==.',
Wh='Whohaveaggro:BAAALgAECgEJBQAAAA==.',
Wi='Widestripe:BAAALgADCgYJBgAAAA==.Wilmington:BAAALgADCgIJAgAAAA==.Windfrost:BAAALgADCgUJBQAAAA==.Wino:BAABLgAECn8VAAMmAAgJlxCuHwCYAQAmAAgJdhCuHwCYAQAiAAEJTxHyJQA8AAAAAA==.Wiqui:BAAALgAECgEJBAAAAA==.Witulow:BAABLgAECn8pAAMXAAgJ3w1gUQApAQAXAAcJog9gUQApAQABAAgJrAQEQAD6AAAAAA==.',
Wo='Wolfadin:BAACLgAFFH8KAAIFAAQJGwZ+HAC9AAAFAAQJGwZ+HAC9AAAuAAQKf0EAAgUACQmOGg0jAHkCAAUACQmOGg0jAHkCAAAA.Woopac:BAABLgAECn8iAAIaAAgJihzuHQD/AQAaAAgJihzuHQD/AQAAAA==.',
Wu='Wulfharth:BAAALgAECgYJDwAAAA==.',
Xe='Xenophics:BAACLgAFFH8eAAMFAAcJfRG7FwCwAQAFAAcJfRG7FwCwAQAkAAEJXwA6UgAgAAAuAAQKf0QABAUACAnOJEgRAN0CAAUACAnOJEgRAN0CACQABAl7EEpXANoAAAsAAQnKBoxVACUAAAEuAAUUBQkTAAkA8wwA.Xenophicstwo:BAACLgAFFH8TAAIJAAUJ8wymZQAXAQAJAAUJ8wymZQAXAQAuAAQKfyYAAgkABglMG76AAHYBAAkABglMG76AAHYBAAAA.',
Xu='Xuen:BAABLgAECn8VAAIlAAcJ/hPtKwBgAQAlAAcJ/hPtKwBgAQABLgAFFAMJDQAFABAkAA==.',
Ya='Yajsooblwj:BAAALgADCgMJAwAAAA==.',
Za='Zal:BAACLgAFFH8FAAIkAAMJrhsIKwDSAAAkAAMJrhsIKwDSAAAuAAQKfyEABCQACQlPGR8kAOQBACQACQlPGR8kAOQBAAUABwlsFo+aAEABAAsAAgkNFWQ0AHYAAAAA.Zanor:BAAALgAECgIJAgAAAA==.Zarranora:BAAALgAECgEJAQAAAA==.Zatannå:BAAALgADCgYJCQAAAA==.',
Ze='Zect:BAABLgAECn8sAAIJAAkJUROkSwD4AQAJAAkJUROkSwD4AQAAAA==.Zenshin:BAAALgAECgIJAgAAAA==.Zentaur:BAAALgAECggJCwAAAA==.Zetzu:BAABLgAECn8cAAIaAAgJHRsLAQCEAQAaAAgJHRsLAQCEAQAAAA==.',
Zi='Zitfrlt:BAAALgAECgYJDwABLgAFFAQJBwADAFILAA==.',
['Ål']='Ålucard:BAABLgAECn8jAAMGAAkJ8xWjHwDRAQAGAAcJbRSjHwDRAQAHAAgJVhiLHwDJAQAAAA==.',
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
