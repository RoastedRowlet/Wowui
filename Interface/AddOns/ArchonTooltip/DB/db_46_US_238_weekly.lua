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

local lookup = {'Monk-Brewmaster','Hunter-BeastMastery','Hunter-Survival','Unknown-Unknown','Paladin-Retribution','Priest-Discipline','Priest-Shadow','Hunter-Marksmanship','Mage-Frost','Priest-Holy','Paladin-Protection','Warrior-Protection','DeathKnight-Unholy','Shaman-Restoration','Shaman-Elemental','Druid-Feral','DemonHunter-Havoc','Warlock-Demonology','Warlock-Destruction','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Monk-Mistweaver','DemonHunter-Devourer','Warrior-Arms','Warrior-Fury','Druid-Restoration','DeathKnight-Frost','DeathKnight-Blood','Druid-Guardian','Warlock-Affliction','Shaman-Enhancement','Rogue-Assassination','Rogue-Outlaw','Paladin-Holy','Druid-Balance','Monk-Windwalker','Rogue-Subtlety','Mage-Arcane',}
local provider = {region='US',realm='Wildhammer',name='US',type='weekly',zone=46,date='2026-06-14',data={Aa='Aayrawn:BAAALgAECgcJBwAAAA==.',
Ab='Abaddonaxx:BAAALgADCgYJBgAAAA==.',
Ac='Aceshaman:BAAALgAECggJCgAAAA==.Acesmash:BAABLgAECn8lAAIBAAkJGCI3BgDWAgABAAkJGCI3BgDWAgAAAA==.Ackrenezoth:BAAALgAECgQJBwAAAA==.',
Ad='Adymisk:BAAALgADCgEJAQAAAA==.',
Ag='Agorot:BAAALgAFFAEJAQAAAA==.',
Ak='Akadion:BAAALgADCgcJCgAAAA==.Akatali:BAAALgAECgQJBgAAAA==.',
Al='Aldannia:BAABLgAECn8VAAMCAAcJ4A/QVwBhAQACAAcJ8wzQVwBhAQADAAYJ7gxXMwAVAQAAAA==.Alextros:BAEALgAECgYJEQABLgAECgcJCgAEAAAAAA==.Alloren:BAAALgAECgQJBgAAAA==.Almond:BAAALgAECgEJAgAAAA==.',
Am='Amaranthe:BAAALgAECgEJAQAAAA==.Amrax:BAABLgAECn80AAIFAAkJpRW6PQANAgAFAAkJpRW6PQANAgAAAA==.Amynre:BAABLgAECn8aAAMGAAkJKRCfFQD5AQAGAAkJKRCfFQD5AQAHAAMJ6w33VABvAAAAAA==.',
An='Anarsa:BAAALgAECgUJCgAAAA==.Angstyboi:BAAALgAECgQJBAAAAA==.',
Aq='Aquabat:BAACLgAFFH8ZAAQIAAQJ8h3wEABQAQAIAAQJ4xvwEABQAQADAAMJdBfVGgD3AAACAAMJ0BdMdQCnAAAuAAQKfyYABAMACQlHIuUFAMYCAAMACQmFIOUFAMYCAAgABwmrH38bAEwCAAIABQlwJRgoABgCAAAA.',
Ar='Arvyy:BAABLgAECn8mAAIJAAkJWBp5LABmAgAJAAkJWBp5LABmAgAAAA==.',
As='Ashbringer:BAACLgAFFH8NAAIFAAMJECT0QAAlAQAFAAMJECT0QAAlAQAuAAQKfyYAAgUACQlgI2YWALsCAAUACQlgI2YWALsCAAAA.',
At='Atria:BAACLgAFFH8IAAIJAAQJtQw0dAD4AAAJAAQJtQw0dAD4AAAuAAQKfycAAgkACAlfFxxFAAoCAAkACAlfFxxFAAoCAAAA.Attia:BAABLgAECn8YAAMKAAgJvxM0IwCmAQAKAAgJvxM0IwCmAQAHAAIJDRVCZwB8AAAAAA==.',
Av='Avaris:BAAALgADCgIJAgAAAA==.Avatarbambi:BAAALgADCgUJAgAAAA==.',
Aw='Away:BAAALgAECgYJBgABLgAECgkJJwALAFoQAA==.',
Ax='Axtar:BAABLgAECn8nAAIMAAkJvht/CwAzAgAMAAkJvht/CwAzAgAAAA==.',
Ay='Ayyitzrich:BAAALgADCgQJBAAAAA==.',
Ba='Babarazzar:BAAALgADCgYJBgAAAA==.Baladoria:BAACLgAFFH8MAAIKAAQJURPhFgADAQAKAAQJURPhFgADAQAuAAQKfzcAAgoACQkIImIEADsDAAoACQkIImIEADsDAAAA.Baldkrank:BAAALgAECgEJAQAAAA==.Bananabowman:BAAALgAECgEJAgAAAA==.Barrels:BAABLgAECn8lAAMCAAkJux4cIgBaAgACAAgJLx0cIgBaAgADAAkJnBWVEwAKAgABLgAFFAIJBQANAP4PAA==.Bartab:BAABLgAECn87AAMOAAkJLR6sDADxAgAOAAkJLR6sDADxAgAPAAEJEwMdvQAeAAABLgAECgkJPwAQADEhAA==.Baruku:BAAALgAFFAEJAQAAAA==.Bashfulwaltz:BAAALgAECgcJBwAAAA==.Bastadi:BAABLgAFFH8FAAIOAAIJJyNMSgDCAAAOAAIJJyNMSgDCAAAAAA==.',
Be='Bearemy:BAAALgAECgcJBwAAAA==.Beastling:BAAALgAECgYJDwAAAA==.Beau:BAACLgAFFH8MAAIRAAQJvyO3BgCXAQARAAQJvyO3BgCXAQAuAAQKfzUAAhEACQlTJTcDACIDABEACQlTJTcDACIDAAAA.Beauchi:BAAALgAECgUJBQABLgAFFAQJDAARAL8jAA==.Beauwi:BAAALgAECgQJBgABLgAFFAQJDAARAL8jAA==.Beldin:BAAALgAECgEJAQAAAA==.',
Bi='Bigshekels:BAAALgAECgEJAQAAAA==.Bigulsworth:BAAALgADCgcJCAAAAA==.',
Bl='Blackadder:BAAALgAECgcJEgAAAA==.Blawkk:BAAALgAECgYJBgAAAA==.Blenton:BAAALgAECgEJAQAAAA==.Bloodussy:BAAALgADCgUJBQAAAA==.Bluck:BAAALgADCgcJEQAAAA==.Blueeyesdrag:BAAALgADCgEJAQAAAA==.Blueombre:BAAALgAECgEJAQAAAA==.',
Bo='Boing:BAAALgAFFAIJAgAAAA==.Boltngo:BAAALgADCgIJAgAAAA==.Bombur:BAACLgAFFH8HAAISAAMJVxbVbQDjAAASAAMJVxbVbQDjAAAuAAQKfy8AAxIACQlSHNEkAEsCABIACQlSHNEkAEsCABMAAQkAAB1kAEYAAAAA.Bosstradamus:BAAALgAFFAEJAQABLgAFFAIJAgAEAAAAAA==.Boston:BAAALgAECggJEwAAAA==.Bottles:BAABLgAFFH8FAAINAAIJ/g8n3QCDAAANAAIJ/g8n3QCDAAAAAA==.',
Br='Braesong:BAAALgAECgIJAgAAAA==.Bratva:BAAALgAECgcJAwAAAA==.',
Bu='Bubagony:BAAALgADCgQJBAABLgAFFAUJEwANAPAgAA==.Bubbells:BAAALgADCgEJAQAAAA==.Bullmedic:BAAALgADCgYJBgAAAA==.Burakku:BAABLgAECn8VAAQUAAcJEhnTGgDzAQAUAAcJEhnTGgDzAQAVAAUJJwgCMQDpAAAWAAEJAAC0PgA1AAABLgAFFAUJCAAXALgXAA==.Burguerkiing:BAAALgADCgMJAwAAAA==.Burph:BAAALgADCggJCAAAAA==.Buttonsmash:BAAALgAECgcJEAABLgAFFAcJJgAVAIATAA==.Buzzkill:BAAALgAECgIJAgAAAA==.',
['Bâ']='Bâbyrage:BAAALgADCgcJDwAAAA==.',
Ca='Cairen:BAABLgAECn8kAAIYAAkJMh6ZIgBEAgAYAAkJMh6ZIgBEAgAAAA==.Calzraxx:BAABLgAECn8UAAQZAAcJdxIaMAAEAQAZAAcJPwsaMAAEAQAMAAQJOhOULQDVAAAaAAMJ7ASyjQCIAAAAAA==.Carstaller:BAAALgAECgQJBAAAAA==.Cartons:BAABLgAECn8VAAIFAAgJySAwEwD5AgAFAAgJySAwEwD5AgABLgAFFAIJBQANAP4PAA==.',
Cc='Ccaan:BAAALgAECgkJEQAAAA==.Ccian:BAAALgAECgQJBAAAAA==.',
Ce='Celinn:BAACLgAFFH8FAAMKAAQJtwwEKQB4AAAKAAIJoRMEKQB4AAAGAAIJzAWmQAByAAAuAAQKfzgAAwoACQkPHWcMAJ4CAAoACQkPHWcMAJ4CAAYABwnLFEEgAMsBAAAA.',
Ch='Chadgar:BAAALgADCgUJBwAAAA==.Chalupacabra:BAAALgADCgIJAgAAAA==.Chappie:BAAALgAECgEJAQABLgAFFAQJGQAIAPIdAA==.Charliek:BAABLgAFFH8IAAIaAAQJQA2OKAAPAQAaAAQJQA2OKAAPAQAAAA==.Cherches:BAAALgADCgEJAQAAAA==.Childish:BAAALgAECgYJDQAAAA==.Chimalma:BAAALgAFFAIJBAAAAA==.Chiqui:BAAALgAECgEJAgAAAA==.Chorr:BAAALgAFFAEJAQABLgAFFAIJBAAEAAAAAA==.',
Cl='Clarabow:BAAALgAFFAIJAwAAAA==.Closure:BAABLgAECn8YAAIbAAkJJSPbDADWAgAbAAkJJSPbDADWAgAAAA==.Cloudsx:BAAALgADCgMJAwAAAA==.',
Co='Coatlicue:BAABLgAECn8UAAMKAAkJFx+hEQBVAgAKAAgJRSGhEQBVAgAHAAUJZBTFMQBXAQABLgAFFAIJBAAEAAAAAA==.Coby:BAABLgAECn8XAAIXAAgJrCQECQAIAwAXAAgJrCQECQAIAwAAAA==.Coffins:BAAALgAECgYJEQABLgAFFAIJBQANAP4PAA==.Corgartah:BAAALgAECgMJAwAAAA==.Covell:BAAALgAECgcJDAAAAA==.',
Cr='Crates:BAAALgAECgUJCAABLgAFFAIJBQANAP4PAA==.Crimsonmagic:BAAALgAECgEJAgAAAA==.Crosswalkk:BAAALgADCgMJAwAAAA==.Crygore:BAAALgAECgQJCgABLgAECgIJBgAEAAAAAA==.',
Cu='Curonconagua:BAAALgAECgMJAwAAAA==.',
Cy='Cypherrellik:BAABLgAECn8cAAMRAAkJhRAYHwB9AQARAAkJhRAYHwB9AQAYAAIJHgIg2QA9AAAAAA==.',
['Cò']='Còrgi:BAAALgAECgEJAgABLgAECgkJPQANAIAhAA==.',
Da='Daktok:BAAALgADCgQJBAAAAA==.Damer:BAAALgADCgkJFgAAAA==.Damues:BAAALgAECggJDwAAAA==.Danaric:BAAALgAECgMJBgAAAA==.Dannyphentom:BAABLgAECn8XAAQNAAYJVxWglQA7AQANAAYJVxWglQA7AQAcAAMJxheMIwCwAAAdAAMJmA4qNgCQAAAAAA==.Dargar:BAAALgAECgEJAQAAAA==.Darkling:BAABLgAECn8dAAIRAAcJoB3iEwDxAQARAAcJoB3iEwDxAQAAAA==.Darknyss:BAAALgADCggJCQAAAA==.',
De='Deathfortres:BAAALgAECgcJDAAAAA==.Dedeye:BAAALgADCgMJAwAAAA==.Dekumime:BAAALgAECggJCwAAAA==.Demandred:BAAALgAECgkJEwAAAA==.Demongrass:BAACLgAFFH8KAAIYAAUJexnGPgAnAQAYAAUJexnGPgAnAQAuAAQKfzIAAhgACAkyIEArABkCABgACAkyIEArABkCAAAA.Denaric:BAAALgAECgYJEAAAAA==.Derty:BAAALgAFFAIJAgAAAA==.',
Di='Diviñehymn:BAAALgAECgcJDwAAAA==.',
Do='Donet:BAAALgADCgEJAQAAAA==.Doodaad:BAAALgAECgEJAgAAAA==.Doppy:BAAALgADCgYJBgAAAA==.Doublerack:BAAALgAECgEJAQABLgAECgIJBgAEAAAAAA==.',
Dr='Dragondeezz:BAAALgAECgIJBAABLgAECgIJBgAEAAAAAA==.Dragondznuts:BAACLgAFFH8mAAIVAAcJgBPwCgDzAQAVAAcJgBPwCgDzAQAuAAQKfz0ABBUACQluHtUFALACABUACQluHtUFALACABQAAgnoHupjAKsAABYAAglHCDsfAFUAAAAA.Draxtos:BAEALgAECgcJCgAAAA==.Dreamevil:BAAALgAECgkJBgAAAA==.Drroxso:BAAALgAECgQJBAAAAA==.Dríppy:BAAALgAECgYJCAAAAA==.',
Ea='Eazybake:BAAALgADCgEJAQAAAA==.',
Ei='Eilerra:BAABLgAECn8qAAIJAAgJBCGpIQCVAgAJAAgJBCGpIQCVAgAAAA==.',
El='Elementony:BAABLgAECn85AAIPAAkJpBB0IwD1AQAPAAkJpBB0IwD1AQAAAA==.Elkdruid:BAABLgAECn8eAAMbAAgJxBCXTwBnAQAbAAgJxBCXTwBnAQAeAAEJQAzlNgAbAAABLgAFFAQJCwACAJAVAA==.Elladamri:BAAALgAECgEJAQAAAA==.Elodi:BAAALgAECgEJAQAAAA==.',
Em='Emberglow:BAAALgAECgcJEgAAAA==.Empyrean:BAAALgADCgQJBQAAAA==.Emylia:BAAALgAECgcJEAAAAA==.',
Er='Eresdelor:BAABLgAECn8YAAMMAAkJlROhFwCBAQAMAAkJzhGhFwCBAQAZAAQJLA4XJwC2AAAAAA==.Erre:BAABLgAECn8mAAISAAkJ5h4UHAB7AgASAAkJ5h4UHAB7AgAAAA==.',
Es='Esdeáth:BAAALgADCgEJAQAAAA==.Estia:BAAALgAECgcJCwABLgAFFAIJBAAEAAAAAA==.',
Ev='Evoktor:BAAALgAECgEJAQAAAA==.',
Ex='Exxitwound:BAAALgADCgUJBwAAAA==.',
Fa='Facasdeath:BAAALgAECgYJDAAAAA==.Failure:BAEBLgAECn8cAAIDAAkJ+hQcDQD6AQADAAkJ+hQcDQD6AQABLgAFFAQJDwABACsYAA==.Farmtoon:BAAALgAECgYJDQAAAA==.Fartbroknvis:BAAALgAFFAIJAgAAAA==.',
Fe='Feardapain:BAACLgAFFH8SAAISAAQJLxfxSQAwAQASAAQJLxfxSQAwAQAuAAQKfz0ABBIACQk5IhUPAAEDABIACAk5IhUPAAEDABMAAQkAADFcAFoAAB8AAQkAAP84AAwAAAAA.Feardatpain:BAAALgAFFAEJAQAAAA==.Fellyn:BAAALgADCggJCwAAAA==.',
Ff='Ff:BAABLgAFFH8LAAIJAAMJwABXngCQAAAJAAMJwABXngCQAAAAAA==.',
Fl='Flar:BAAALgAFFAEJAQAAAA==.Flixie:BAABLgAECn8gAAMOAAkJQSHRBQBSAwAOAAkJQSHRBQBSAwAPAAEJByD2hwBdAAABLgAFFAcJLgAXAAcXAA==.Flyingcow:BAAALgAECgkJDgAAAA==.',
Fo='Foenix:BAAALgADCgYJBgAAAA==.Foxoffire:BAAALgAECgMJBwAAAA==.Foxu:BAAALgAECgcJBwAAAA==.Foxymoron:BAAALgAECgcJCwAAAA==.Fozzi:BAABLgAECn8oAAIXAAkJQSExCAAXAwAXAAkJQSExCAAXAwAAAA==.',
Fr='Freakazoid:BAABLgAECn8wAAIHAAkJjx1TEQBNAgAHAAkJjx1TEQBNAgAAAA==.Fritark:BAAALgAECgcJBwABLgAECgkJEwAEAAAAAA==.Fritzyp:BAAALgAECgkJEwAAAA==.Frogzqc:BAAALgAECgEJAgAAAA==.Frostyburn:BAAALgAECgYJEQAAAA==.Frozenrage:BAAALgADCgcJCwAAAA==.',
['Fë']='Fëanor:BAAALgAECggJCwAAAA==.',
Ga='Gabos:BAAALgADCgEJAQAAAA==.Garayice:BAAALgADCgIJAgAAAA==.Garycoleman:BAAALgAECgQJBAAAAA==.Gaxxen:BAAALgAECgUJBQAAAA==.',
Ge='Gena:BAAALgADCgcJCAAAAA==.Geörge:BAACLgAFFH8YAAIHAAcJ5xd7CQDFAQAHAAcJ5xd7CQDFAQAuAAQKfywAAgcACAkxISIIAAIDAAcACAkxISIIAAIDAAAA.',
Gh='Ghostyganja:BAAALgAECgQJBAABLgAFFAMJBQAUAHYWAA==.',
Gi='Giratiña:BAAALgAECgEJAgABLgAFFAIJAwAEAAAAAA==.',
Gl='Glary:BAAALgAECgEJAQAAAA==.Glavendale:BAAALgADCgUJBQAAAA==.',
Go='Goatcheezey:BAAALgADCgYJDAAAAA==.Goblinsox:BAAALgAECgQJBAAAAA==.Goluck:BAAALgAECgEJAQAAAA==.Gordothe:BAAALgADCgUJBQABLgAECgUJBgAEAAAAAA==.',
Gr='Grimel:BAAALgAECgQJCAABLgAECgYJEAAEAAAAAA==.Grimghoul:BAAALgAECgQJCQABLgAECgYJEAAEAAAAAA==.Grimgram:BAAALgAECgYJEAAAAA==.Gripyoulol:BAAALgAECgQJBQAAAA==.Grotelek:BAABLgAECn8hAAIgAAkJTROiDgDDAQAgAAkJTROiDgDDAQAAAA==.Grotret:BAAALgAECgIJAgAAAA==.Grouchy:BAAALgADCgMJAwAAAA==.Grumpywaltz:BAAALgAECgQJBAAAAA==.',
Gu='Gulimath:BAAALgAECgUJBgAAAA==.',
Ha='Haedrath:BAAALgAECgEJAgABLgAECggJKgAJAAQhAA==.Halconotachi:BAABLgAECn9FAAIDAAkJiRpOCgB5AgADAAkJiRpOCgB5AgAAAA==.Hammerfoot:BAAALgAFFAEJAQAAAA==.Haranir:BAAALgAECgYJCAAAAA==.Harcat:BAABLgAECn8dAAMIAAkJGBXHCwCnAQAIAAkJGBXHCwCnAQADAAEJYQF5awAcAAAAAA==.Hartracks:BAAALgAECgUJBQAAAA==.Hatijo:BAAALgAECgYJBwAAAA==.Hawgbawl:BAABLgAECn8iAAIaAAgJbxt/GAAqAgAaAAgJbxt/GAAqAgAAAA==.Hawgdream:BAAALgAECgcJEQAAAA==.',
He='Hellequin:BAACLgAFFH8ZAAIhAAcJJhciAQD3AQAhAAcJJhciAQD3AQAuAAQKfzkAAyEACQkDIj0BACsDACEACQkDIj0BACsDACIAAQkpA4cPACoAAAAA.Henkojin:BAAALgADCgYJBgAAAA==.Heyitzlock:BAAALgAECgYJCQAAAA==.Heyyitzrich:BAAALgAECgQJDQAAAA==.Heyyitzrichh:BAABLgAFFH8JAAISAAMJzBafbQDjAAASAAMJzBafbQDjAAAAAA==.Heyytaco:BAAALgAECggJEgAAAA==.',
Hi='Hiels:BAAALgAECgcJBwAAAA==.Hirogon:BAAALgAECgEJAwAAAA==.',
Ho='Hobb:BAABLgAECn8pAAIFAAkJcB76HQCRAgAFAAkJcB76HQCRAgAAAA==.Holenmymuff:BAAALgADCgUJBQAAAA==.Hollinar:BAABLgAECn8YAAIJAAkJxxLtcADyAQAJAAkJxxLtcADyAQAAAA==.Holyfaux:BAAALgADCgYJBgAAAA==.Holysteel:BAAALgAECgIJAwAAAA==.Hondoe:BAAALgAECgQJCAAAAA==.Hordecow:BAAALgAECgEJAQABLgAFFAEJAgAEAAAAAA==.Hornhelm:BAAALgAECgIJAgAAAA==.',
Hu='Huntoor:BAAALgAECgEJAQABLgAECgYJBgAEAAAAAA==.',
Ic='Icemark:BAACLgAFFH8FAAIJAAMJfxI1KwAJAQAJAAMJfxI1KwAJAQAuAAQKfx8AAgkABwkGHShXADMCAAkABwkGHShXADMCAAAA.',
Ih='Ihavecookies:BAAALgAECgQJBQAAAA==.',
Ij='Ijur:BAAALgAECgQJCAABLgAECgUJBgAEAAAAAA==.',
Ik='Ikayro:BAABLgAECn8cAAIJAAgJdx2AKgDJAgAJAAgJdx2AKgDJAgAAAA==.',
Il='Ilostmyphone:BAAALgAECgEJAQAAAA==.Ilovemysword:BAAALgAECgUJCQAAAA==.Iluvatar:BAABLgAECn8eAAMHAAgJiiFyDQB9AgAHAAgJiiFyDQB9AgAGAAIJwxKMYAB3AAABLgAFFAEJAQAEAAAAAA==.',
Im='Imagine:BAABLgAECn8WAAQVAAkJaRCoDgDhAQAVAAkJaRCoDgDhAQAUAAYJFganPgDwAAAWAAEJtgJUKwAeAAAAAA==.',
In='Infoxticated:BAAALgAECgEJAQAAAA==.',
Ir='Iratedemon:BAAALgAECgMJBAABLgAECgMJAwAEAAAAAA==.Irateknight:BAAALgAECgMJAwAAAA==.Irely:BAAALgAECgIJAgAAAA==.',
Ja='Jadedways:BAAALgAECgEJAgAAAA==.Jasmirangel:BAACLgAFFH8QAAIbAAMJNCAyKQARAQAbAAMJNCAyKQARAQAuAAQKf0UAAhsACAkDJfkGAEYDABsACAkDJfkGAEYDAAAA.',
Je='Jede:BAAALgADCgMJAwAAAA==.',
Jo='Joshallen:BAAALgADCgcJBwAAAA==.',
Ju='Juka:BAABLgAECn8UAAIOAAkJGQdxVwBVAQAOAAkJGQdxVwBVAQAAAA==.Jukks:BAAALgAECgcJEQAAAA==.Juno:BAAALgADCgkJEwAAAA==.Justsumfoo:BAAALgAECgIJBAAAAA==.',
Ka='Kano:BAACLgAFFH8XAAMCAAUJYRnfIAB7AQACAAUJYRnfIAB7AQADAAEJKhRZMwBCAAAuAAQKfy4AAgIACQmII7YKAP4CAAIACQmII7YKAP4CAAAA.Karper:BAAALgAECgEJAQAAAA==.Kataga:BAAALgAECgEJAQAAAA==.Katarm:BAABLgAECn8UAAMMAAkJcggfJQAGAQAMAAkJagQfJQAGAQAZAAUJNgwLQgC7AAAAAA==.Katarru:BAAALgAECgYJDQAAAA==.Kataru:BAAALgADCgIJAgAAAA==.Kayhaus:BAAALgAECgYJBgAAAA==.',
Kh='Khory:BAAALgAFFAIJBAAAAA==.',
Ki='Kirito:BAAALgADCgYJBgAAAA==.',
Kk='Kkiinnoopp:BAABLgAECn8jAAMCAAgJiBa4dgBPAQADAAYJVhYrFQB1AQACAAcJSxS4dgBPAQAAAA==.',
Ko='Korgigor:BAAALgAECgQJBwAAAA==.Kovu:BAAALgAECgcJEgAAAA==.',
Kr='Krisanthemum:BAAALgADCgcJCwAAAA==.Krystrasz:BAAALgAECgQJCwAAAA==.',
Kt='Kt:BAAALgADCgIJAgABLgAECgQJBAAEAAAAAA==.Ktrogue:BAAALgAECgQJBAAAAA==.',
Ku='Kuailiang:BAAALgAECgcJCQAAAA==.Kuraihikari:BAAALgAFFAEJAQAAAA==.Kustaa:BAAALgADCgkJCgABLgAECgkJLAAjAIsXAA==.',
La='Ladezar:BAAALgADCgcJDQAAAA==.Laissen:BAAALgAECgYJCAAAAA==.Lapsung:BAAALgAECgIJBAABLgAECggJGAAKAL8TAA==.Lattemocha:BAABLgAECn8tAAMbAAkJ3x6eMADpAQAbAAYJLR2eMADpAQAkAAkJBhJ7IADCAQAAAA==.',
Le='Lenden:BAAALgAECgMJBgAAAA==.Leprechaun:BAAALgADCgcJCQAAAA==.Leví:BAAALgADCgUJBQAAAA==.Leylas:BAAALgAECgEJAgAAAA==.',
Li='Lighthoove:BAAALgAECgcJBwAAAA==.Lightswìtch:BAAALgADCgEJAQAAAA==.Lilliaz:BAAALgAECgYJBwAAAA==.Linianna:BAAALgAECgYJEgAAAA==.Liriel:BAAALgAECgcJBwAAAA==.',
Lu='Ludlow:BAABLgAECn8dAAICAAgJEgqkfwA8AQACAAgJEgqkfwA8AQAAAA==.Lunastra:BAACLgAFFH8KAAIJAAQJERIfggDYAAAJAAQJERIfggDYAAAuAAQKfyYAAgkACAlOHOdJAPsBAAkACAlOHOdJAPsBAAEuAAUUAgkEAAQAAAAA.Luneztoprime:BAAALgAECgYJCgAAAA==.',
Ly='Lydarra:BAAALgAECgQJBwABLgAECgYJFQAaAFAZAA==.Lyiann:BAAALgADCggJEgAAAA==.Lyákadion:BAAALgAECgEJAQAAAA==.',
['Lâ']='Lâdypriest:BAAALgADCgUJBQAAAA==.',
Ma='Mafi:BAABLgAECn8WAAICAAcJ/RlXWwCQAQACAAcJ/RlXWwCQAQAAAA==.Maggore:BAAALgAECgIJBgAAAA==.Magikiwiks:BAAALgAECgEJAQAAAA==.Magsdk:BAAALgAFFAIJAgABLgAFFAgJIwAUAKEcAA==.Mainlander:BAAALgAECgMJAwAAAA==.Malbogea:BAAALgAFFAEJAQAAAA==.Malusmittens:BAAALgAECgQJBQABLgAFFAUJGgACADsjAA==.Mantonso:BAABLgAECn8xAAIaAAkJDSByDQCWAgAaAAkJDSByDQCWAgAAAA==.Manus:BAAALgADCgIJAgAAAA==.Matt:BAACLgAFFH8JAAIbAAQJMQsQNgDQAAAbAAQJMQsQNgDQAAAuAAQKfyoAAhsACQkiHUoNAO8CABsACQkiHUoNAO8CAAAA.',
Me='Meddicus:BAAALgAECgUJCAAAAA==.Meechydarko:BAAALgAECgUJBQABLgAECgkJOAADALUfAA==.Megalomaniä:BAAALgADCgYJBgABLgAECgcJHgAfAKYYAA==.Megorice:BAAALgAFFAIJBAAAAA==.Megå:BAABLgAECn8eAAMfAAcJphhIFwAJAQASAAYJmBfadABQAQAfAAUJmBtIFwAJAQAAAA==.Mewtwô:BAAALgAECgYJBwAAAA==.',
Mi='Microbrew:BAAALgAECgMJBQAAAA==.Miezra:BAAALgAECgYJCAAAAA==.Mikah:BAAALgAECgYJDwAAAA==.',
Mo='Modayus:BAAALgAECgEJAQAAAA==.Mojomittens:BAACLgAFFH8aAAICAAUJOyNwHACMAQACAAUJOyNwHACMAQAuAAQKfyIAAwIABwlEJOkoADgCAAIABwlEJOkoADgCAAgABQnAFqRAAFcBAAAA.Monstermime:BAAALgAECgIJAgABLgAECggJCwAEAAAAAA==.Monstroqt:BAAALgADCgQJBAAAAA==.Moobiez:BAAALgADCggJCQAAAA==.Morøs:BAAALgADCgYJBgAAAA==.Moxx:BAABLgAECn8ZAAIlAAkJtw45MwA1AQAlAAkJtw45MwA1AQAAAA==.',
Mu='Muffers:BAABLgAECn83AAIlAAkJAxPLGQDgAQAlAAkJAxPLGQDgAQAAAA==.Muffpuff:BAAALgAECgQJBQAAAA==.Mutige:BAAALgADCgEJAQAAAA==.',
My='Mylotus:BAAALgAECgQJBQAAAA==.',
Na='Napkuntt:BAAALgAECgEJAQAAAA==.Napokin:BAAALgAFFAEJAgAAAA==.Napshade:BAABLgAECn8cAAMHAAcJyhuNLABxAQAHAAYJ/xyNLABxAQAKAAYJEhB+SADAAAABLgAFFAEJAgAEAAAAAA==.Natsuu:BAAALgAECgcJDAAAAA==.',
Nb='Nbayoungboyy:BAAALgADCgYJBgABLgAFFAYJHgACAIYhAA==.',
Ne='Necroticoath:BAAALgAECgIJBgABLgAFFAIJBQAOACcjAA==.Neven:BAAALgAECgIJAgAAAA==.',
Ni='Nightor:BAAALgAECgEJAQAAAA==.Nightvenge:BAAALgAFFAIJAgAAAA==.Nikodemos:BAAALgAFFAcJGAAAAQ==.Nivahoof:BAAALgADCgEJAQAAAA==.',
No='Noc:BAABLgAECn8pAAMSAAgJLBkpOAD5AQASAAgJLBkpOAD5AQATAAUJNA+JLQAHAQABLgAFFAMJBgASAF8QAA==.Nomemage:BAAALgADCgEJAQAAAA==.',
Ob='Obe:BAAALgAFFAIJAgAAAA==.Obsidiangel:BAAALgADCggJEAAAAA==.',
Oh='Ohface:BAAALgAECgQJBwABLgAECgIJBgAEAAAAAA==.',
Oo='Oowu:BAAALgADCgkJFAAAAA==.',
Or='Oran:BAABLgAECn8YAAIFAAgJaxjwUgDPAQAFAAgJaxjwUgDPAQAAAA==.Orctrax:BAABLgAECn8aAAMCAAgJVRE1dgBQAQACAAgJVRE1dgBQAQAIAAEJBALAjgAsAAAAAA==.Oricale:BAAALgAECgYJBgAAAA==.',
Os='Osheat:BAACLgAFFH8FAAINAAMJJg1cqQDGAAANAAMJJg1cqQDGAAAuAAQKfyMAAg0ACQndH8goAF0CAA0ACQndH8goAF0CAAAA.Osmodeus:BAAALgAECgUJCAAAAA==.',
Ou='Outplay:BAAALgADCgUJBQAAAA==.',
Ox='Ox:BAAALgAECgEJAQAAAA==.Oxheart:BAAALgAECgEJAQAAAA==.',
Pa='Paltis:BAAALgAECgQJBQAAAA==.Paltonso:BAAALgADCgkJCQAAAA==.Pandaari:BAABLgAECn8WAAIHAAgJFAToSgDiAAAHAAgJFAToSgDiAAAAAA==.Papaschristo:BAAALgADCgUJBQAAAA==.Papasdiablo:BAAALgAECgEJAgAAAA==.Parprapa:BAAALgADCgMJAwAAAA==.',
Pe='Penicillin:BAAALgAECgMJAwAAAA==.Persimmon:BAACLgAFFH8OAAIjAAQJVxzfGgBEAQAjAAQJVxzfGgBEAQAuAAQKfyAAAiMABwmTF6QqALkBACMABwmTF6QqALkBAAAA.Peyton:BAAALgAECgUJBwAAAA==.',
Ph='Philip:BAAALgADCgcJDAAAAA==.Phyrie:BAAALgAECgUJDwABLgAECgYJFQAaAFAZAA==.',
Pi='Pittpete:BAAALgAECgEJAQAAAA==.',
Pl='Plaguepapi:BAAALgAFFAEJAQAAAA==.',
Po='Pollocaotico:BAAALgAFFAIJAgAAAA==.',
Ps='Psythera:BAAALgAECgIJBAABLgAECggJIgAHAPIcAA==.Psythern:BAAALgADCgYJCQABLgAECggJIgAHAPIcAA==.',
Pu='Punkybrewstr:BAABLgAECn8xAAMBAAgJjhYAJACKAQABAAcJURYAJACKAQAlAAgJswr0MABjAQAAAA==.Pureshock:BAAALgAECggJDQAAAA==.Purpderf:BAAALgAFFAEJAQAAAA==.',
Pw='Pwnstar:BAAALgAECgQJCAAAAA==.',
Py='Pykei:BAAALgAECgQJBQAAAA==.Pyrrah:BAAALgAECgEJAQABLgAECgkJJAAGAEIdAA==.Pyrri:BAABLgAECn8kAAQGAAkJQh18FAA4AgAGAAgJaB58FAA4AgAKAAQJ4RXjUQDwAAAHAAMJdRSiWQCsAAAAAA==.Pyrria:BAABLgAECn8WAAMOAAkJvyR+BgBHAwAOAAgJeyR+BgBHAwAPAAUJJhVDQgAnAQABLgAECgkJJAAGAEIdAA==.Pyrris:BAAALgAECgMJAwABLgAECgkJJAAGAEIdAA==.',
Pz='Pznt:BAAALgAECgEJAQAAAA==.',
['Pé']='Péyton:BAAALgAECgcJDgAAAA==.',
['Pì']='Pì:BAAALgADCgEJAgAAAA==.',
['Pô']='Pôws:BAAALgAECgIJAwAAAA==.',
Qu='Quantonbomb:BAABLgAECn8UAAIbAAkJehmLEwCtAgAbAAkJehmLEwCtAgAAAA==.Quezera:BAAALgADCgYJBgAAAA==.',
Ra='Rabuf:BAABLgAECn8sAAMjAAkJixccEgCBAgAjAAkJixccEgCBAgAFAAYJpQ4cwAAHAQAAAA==.Raccoonadin:BAAALgADCgEJAQAAAA==.Radha:BAAALgAECgIJAgABLgAFFAUJEwANAPAgAA==.Ragingwater:BAAALgAECgYJEAAAAA==.Ranadheer:BAAALgAFFAEJAQAAAA==.Raspaigus:BAAALgAECgQJBAAAAA==.Ratfu:BAABLgAECn8UAAIlAAYJOQX/RwD1AAAlAAYJOQX/RwD1AAAAAA==.Raudson:BAABLgAECn8UAAILAAkJDCJUAgATAwALAAkJDCJUAgATAwAAAA==.',
Re='Redizle:BAACLgAFFH8cAAIGAAgJcRa+CACQAgAGAAgJcRa+CACQAgAuAAQKfycABAoACAnxHBkoAK8BAAYACAn7FuUbALcBAAoABgkyHBkoAK8BAAcABQnSEug2ADYBAAAA.Reginrune:BAAALgAECgkJEwAAAA==.Resonance:BAABLgAECn8WAAMPAAcJHBaIOgBJAQAPAAcJ9RWIOgBJAQAgAAMJZwykIwCeAAAAAA==.Restroll:BAAALgADCgUJBQAAAA==.',
Rh='Rhaigar:BAAALgAECgUJCQAAAA==.Rhónatar:BAAALgADCgQJBAAAAA==.',
Ri='Righteouscow:BAAALgAECgEJAQAAAA==.',
Ro='Rohdoog:BAABLgAECn84AAIUAAkJoRfhEwA+AgAUAAkJoRfhEwA+AgAAAA==.Roundabugman:BAACLgAFFH8MAAIPAAMJrh0eLADfAAAPAAMJrh0eLADfAAAuAAQKfycAAw8ACAmSHp0gAN0BAA8ACAmSHp0gAN0BAA4AAwmnFOF3ALIAAAAA.',
Rr='Rr:BAABLgAFFH8MAAMiAAMJyAGaDgB1AAAmAAMJIAGxNQCFAAAiAAMJpAGaDgB1AAAAAA==.',
Ru='Runedyu:BAAALgAECgYJEQAAAA==.',
Ry='Ryanno:BAACLgAFFH8LAAICAAMJpxvIUAACAQACAAMJpxvIUAACAQAuAAQKfyoAAgIACQkwIK0dAHECAAIACQkwIK0dAHECAAAA.Ryannoo:BAAALgAECgYJBQAAAA==.Ryujinhalco:BAAALgAECgEJAQAAAA==.',
Sa='Sabim:BAAALgAECgEJAQAAAA==.Sahomi:BAACLgAFFH8QAAIGAAQJtA2xKAACAQAGAAQJtA2xKAACAQAuAAQKfyQAAwYACQlNCXkoAFIBAAYACQlNCXkoAFIBAAoAAglNBZR3AEwAAAAA.Salana:BAAALgADCgcJBwAAAA==.Samwise:BAAALgAECgYJCAAAAA==.Sarai:BAAALgADCgEJAQAAAA==.Sarcini:BAABLgAECn8uAAILAAkJXhvHBwBdAgALAAkJXhvHBwBdAgAAAA==.Satrina:BAACLgAFFH8NAAINAAQJqRWtXQA0AQANAAQJqRWtXQA0AQAuAAQKfyQAAg0ACAmrIuoyADECAA0ACAmrIuoyADECAAAA.Savvy:BAAALgAECgUJBQABLgAECgYJBgAEAAAAAA==.',
Sc='Scrappy:BAAALgAECgEJAQAAAA==.',
Se='Sedna:BAAALgADCgYJBgABLgAECgYJCAAEAAAAAA==.Selanthe:BAAALgAECgQJBgAAAA==.Seruk:BAAALgAECgEJBAAAAA==.Sevaronk:BAAALgAECgYJBwAAAA==.Seventhghost:BAEALgAECgQJBQABLgAFFAUJEAAHAN0WAA==.',
Sh='Shadowstorme:BAAALgAECgIJBQAAAA==.Shamander:BAABLgAECn8eAAIOAAkJQxh8IgA9AgAOAAkJQxh8IgA9AgAAAA==.Shamsham:BAAALgADCgcJDAAAAA==.Sharabuf:BAAALgAECgEJAQAAAA==.Sharky:BAAALgADCgQJBAAAAA==.Shocka:BAAALgADCgcJCQAAAA==.Shokanki:BAAALgAECgYJCwAAAA==.Shutupcat:BAAALgADCgQJBAABLgADCgUJBQAEAAAAAA==.',
Si='Sicara:BAABLgAECn8uAAIYAAkJQhYTPwDKAQAYAAkJQhYTPwDKAQAAAA==.Silentmage:BAAALgADCgcJCAAAAA==.Silentslock:BAAALgADCgYJBQAAAA==.Sillylilguy:BAACLgAFFH8JAAIgAAMJnBE3AwADAQAgAAMJnBE3AwADAQAuAAQKfxgAAiAACAmEH+8EAMECACAACAmEH+8EAMECAAAA.Sinestro:BAAALgAECgMJAwAAAA==.Sivrogar:BAAALgAECgMJAwAAAA==.',
Sl='Slaik:BAAALgAECgUJDgAAAA==.Slander:BAACLgAFFH8ZAAMNAAYJsx7RMACbAQANAAYJsx7RMACbAQAdAAEJAAB0XgAAAAAuAAQKfzkAAg0ACQmQITgeAJECAA0ACQmQITgeAJECAAAA.',
So='Solemnograve:BAAALgAECgIJAgAAAA==.Somazugzug:BAACLgAFFH8PAAIOAAQJUBsDKgA3AQAOAAQJUBsDKgA3AQAuAAQKfyUAAg4ACQm5GV8uANABAA4ACQm5GV8uANABAAAA.Sothren:BAAALgAECgQJBQABLgADCgkJCQAEAAAAAA==.Souchong:BAAALgAECgIJAgABLgAECggJGAAKAL8TAA==.',
Sp='Spacedguy:BAAALgADCgMJAwAAAA==.Spry:BAAALgAECgEJAQAAAA==.',
St='Staccato:BAAALgAECgEJAQAAAA==.Stanleyy:BAAALgAFFAEJAgABLgAFFAIJBQAOACcjAA==.Starlight:BAAALgAECgIJAgAAAA==.Stepbrother:BAAALgAFFAEJAQABLgAECgkJOAADALUfAA==.',
Su='Sugar:BAABLgAECn8nAAMOAAkJ5RF/TAB7AQAOAAkJ5RF/TAB7AQAPAAUJtw6oVgDrAAAAAA==.Sugars:BAAALgAECgUJBAAAAA==.Sulin:BAAALgADCgUJBwAAAA==.Sungôd:BAAALgADCgEJAQABLgAECgkJMQABAI4WAA==.',
Sw='Swonks:BAAALgAECgMJAwAAAA==.Swyper:BAAALgAECgMJAwAAAA==.',
Sy='Synicism:BAAALgADCgcJDQAAAA==.',
Ta='Taintbubble:BAAALgAECgMJBQAAAA==.Tanktommy:BAAALgAECgUJCAABLgAFFAUJFAANABsbAA==.Tarnished:BAAALgADCgcJCAAAAA==.Tarquitus:BAACLgAFFH8TAAMYAAcJhw5AMABeAQAYAAYJIxFAMABeAQARAAIJeAS+CgCTAAAuAAQKfzwAAxgACAmXIKkcAGYCABgACAnWH6kcAGYCABEACAm8F0sRAFUCAAAA.Tattoosguy:BAAALgADCgEJAQAAAA==.',
Te='Teef:BAABLgAECn8cAAImAAcJFxWgIwB1AQAmAAcJFxWgIwB1AQAAAA==.Tellan:BAAALgADCgcJBwAAAA==.',
Th='Thanatös:BAABLgAECn8cAAMJAAgJbBZHaQCnAQAJAAgJbBZHaQCnAQAnAAQJrxRDDQD1AAAAAA==.Tharros:BAAALgAECgcJDQAAAA==.Thedarkkness:BAABLgAECn8nAAIdAAkJIheMFgCzAQAdAAkJIheMFgCzAQAAAA==.Thekleener:BAAALgAECgEJAQAAAA==.Thorin:BAAALgAECgQJBAABLgAFFAIJBQAOACcjAA==.Thrasher:BAAALgAECgEJAwAAAA==.',
Ti='Tidalwave:BAACLgAFFH8OAAIOAAQJAh60JABTAQAOAAQJAh60JABTAQAuAAQKfy0AAw4ACQnFGbsgAEkCAA4ACQnFGbsgAEkCAA8AAgltC2mrACoAAAAA.Tidus:BAAALgAECgYJEQAAAA==.Tinytotem:BAAALgAECgEJBAAAAA==.Tissue:BAABLgAECn8XAAIRAAcJCArULABjAQARAAcJCArULABjAQAAAA==.',
To='Toasted:BAAALgADCgYJCQABLgAECgMJAwAEAAAAAA==.Tobibi:BAAALgAFFAEJAQABLgAFFAIJBQAOACcjAA==.Todo:BAAALgADCgQJBAAAAA==.Tolip:BAABLgAECn8rAAMbAAgJUQgrdgD1AAAbAAYJgAgrdgD1AAAkAAgJSgTGRwDpAAABLgAFFAEJAQAEAAAAAA==.Tolipally:BAAALgAFFAEJAQAAAA==.Tolipicious:BAAALgADCgUJCQABLgAFFAEJAQAEAAAAAA==.',
Tr='Trauts:BAAALgAECgQJCAAAAA==.Treeadin:BAABLgAECn8nAAILAAkJWhAfFwBmAQALAAkJWhAfFwBmAQAAAA==.Trollcula:BAAALgAECggJDgABLgAFFAQJCwACAJAVAA==.Truthwithin:BAAALgAECgUJEwAAAA==.',
Ts='Tsarrubus:BAABLgAECn8hAAIRAAkJcwmEJABQAQARAAkJcwmEJABQAQAAAA==.',
Tu='Tula:BAAALgAECgUJCwAAAA==.Tusck:BAAALgAECgYJEAAAAA==.',
Tw='Twingert:BAAALgAECgEJAQAAAA==.Twitch:BAAALgAECgYJEwAAAA==.',
Ty='Tyedyemess:BAAALgAECgMJAwAAAA==.Tyledridal:BAAALgAECgMJAwAAAA==.',
['Tà']='Tàylor:BAABLgAECn8cAAIjAAkJOQu1OgCPAQAjAAkJOQu1OgCPAQAAAA==.',
Ub='Ubbaa:BAAALgAECgEJAQAAAA==.',
Ul='Ulghar:BAABLgAECn8rAAIaAAkJNCXDAQBiAwAaAAkJNCXDAQBiAwAAAA==.',
Ur='Ursock:BAAALgAECggJDgAAAA==.',
Uw='Uwuhshake:BAABLgAECn8tAAMbAAkJ7SHWBABrAwAbAAkJ7SHWBABrAwAkAAEJqRt2eQBRAAAAAA==.',
Va='Valdria:BAAALgAECgMJAwAAAA==.Valssien:BAAALgADCgkJCQAAAA==.Vanaria:BAAALgAECgQJBAAAAA==.Vanbrook:BAAALgAECgQJAgAAAA==.Vanden:BAAALgAECgYJDAAAAA==.Vanrion:BAAALgAFFAIJAwAAAA==.Varrodd:BAAALgAECgEJAQAAAA==.Vastextent:BAAALgADCgMJBAAAAA==.',
Ve='Velcro:BAAALgAECgYJEgAAAA==.Velsera:BAAALgAECgYJCAAAAA==.Velvet:BAAALgADCgQJCAAAAA==.Velyn:BAAALgAECgcJDwAAAA==.Velynara:BAAALgADCgIJAgABLgAECgYJCAAEAAAAAA==.Vengefulcry:BAAALgAECgMJAwAAAA==.Vengefül:BAAALgADCgYJCAAAAA==.Vexara:BAAALgAECgQJBAAAAA==.',
Wa='Wanaaga:BAAALgAECggJDgAAAA==.',
We='Wedge:BAAALgAECgEJAQAAAA==.',
Wh='Whohaveaggro:BAAALgAECgEJAwAAAA==.',
Wi='Widestripe:BAAALgADCgYJBgAAAA==.Wilmington:BAAALgADCgIJAgAAAA==.Windfrost:BAAALgADCgUJBQAAAA==.Wino:BAABLgAECn8VAAMmAAgJlxBmHwCYAQAmAAgJdhBmHwCYAQAhAAEJTxGKJQA8AAAAAA==.Wiqui:BAAALgAECgEJBAAAAA==.Witulow:BAABLgAECn8pAAMXAAgJ3w3wTwApAQAXAAcJog/wTwApAQABAAgJrASUPwD6AAAAAA==.',
Wo='Wolfadin:BAACLgAFFH8KAAIFAAQJGwZ+HAC9AAAFAAQJGwZ+HAC9AAAuAAQKfz8AAgUACQmHGpEiAHsCAAUACQmHGpEiAHsCAAAA.Woopac:BAABLgAECn8iAAIaAAgJihyJHQABAgAaAAgJihyJHQABAgAAAA==.',
Wu='Wulfharth:BAAALgAECgYJDwAAAA==.',
Xe='Xenophics:BAACLgAFFH8dAAMFAAcJfREvFgCxAQAFAAcJfREvFgCxAQAjAAEJXwD5UAAgAAAuAAQKf0QABAUACAnOJNsQAN4CAAUACAnOJNsQAN4CACMABAl7EHlWANwAAAsAAQnKBppUACUAAAEuAAUUBAkOAAkAxQoA.Xenophicstwo:BAACLgAFFH8OAAIJAAQJxQqzaAAYAQAJAAQJxQqzaAAYAQAuAAQKfyYAAgkABglMG4h/AHYBAAkABglMG4h/AHYBAAAA.',
Xu='Xuen:BAABLgAECn8VAAIlAAcJ/hN4KwBhAQAlAAcJ/hN4KwBhAQABLgAFFAMJDQAFABAkAA==.',
Ya='Yajsooblwj:BAAALgADCgMJAwAAAA==.',
Za='Zal:BAACLgAFFH8FAAIjAAMJrhtAKgDTAAAjAAMJrhtAKgDTAAAuAAQKfyEABCMACQlPGdojAOQBACMACQlPGdojAOQBAAUABwlsFhiZAEEBAAsAAgkNFWQ0AHYAAAAA.Zanor:BAAALgAECgIJAgAAAA==.Zarranora:BAAALgAECgEJAQAAAA==.Zatannå:BAAALgADCgYJCQAAAA==.',
Ze='Zect:BAABLgAECn8sAAIJAAkJURPnSgD4AQAJAAkJURPnSgD4AQAAAA==.Zenshin:BAAALgAECgIJAgAAAA==.Zentaur:BAAALgAECggJCwAAAA==.Zetzu:BAABLgAECn8XAAIaAAgJlBl6IADsAQAaAAgJlBl6IADsAQAAAA==.',
Zi='Zitfrlt:BAAALgAECgYJCwABLgAECgcJJwADAN4VAA==.',
['Ål']='Ålucard:BAABLgAECn8jAAMGAAkJ8xVeHwDSAQAGAAcJbRReHwDSAQAHAAgJVhhkHwDKAQAAAA==.',
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
