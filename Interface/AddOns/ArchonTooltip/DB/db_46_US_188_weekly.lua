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

local lookup = {'Unknown-Unknown','Druid-Restoration','Warrior-Protection','Warrior-Fury','Paladin-Holy','Priest-Holy','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Paladin-Retribution','Evoker-Devastation','Warrior-Arms','DemonHunter-Havoc','Paladin-Protection','DemonHunter-Devourer','Rogue-Subtlety','Rogue-Assassination','Druid-Balance','Hunter-BeastMastery','Druid-Guardian','Shaman-Elemental','Shaman-Restoration','Monk-Windwalker','Monk-Mistweaver','Shaman-Enhancement','DeathKnight-Blood','DeathKnight-Unholy','Priest-Shadow','Hunter-Survival','Druid-Feral','Mage-Frost','Monk-Brewmaster','DemonHunter-Vengeance','DeathKnight-Frost','Mage-Arcane','Hunter-Marksmanship','Evoker-Augmentation','Priest-Discipline','Rogue-Outlaw',}
local provider = {region='US',realm='ShadowCouncil',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abear:BAAALgAECgQJBQAAAA==.Abrocklock:BAAALgAECgYJBwAAAA==.',
Ac='Achilês:BAAALgAECgEJAQABLgAECgcJCwABAAAAAA==.',
Ad='Adaluna:BAABLgAECn8VAAICAAkJRwgvTQBHAQACAAkJRwgvTQBHAQAAAA==.Adorabull:BAABLgAECn8lAAMDAAkJ1SFsBQCvAgADAAkJ1SFsBQCvAgAEAAEJ0AYRrwAsAAAAAA==.Adrain:BAAALgAECgQJCwAAAA==.Adwae:BAAALgAECgIJAgAAAA==.',
Ae='Aelyn:BAAALgAECgcJDwAAAA==.Aerendyl:BAAALgAECgEJAQAAAA==.Aevelee:BAAALgAECgYJCQAAAA==.Aevick:BAAALgAECgQJBQAAAA==.',
Al='Alastair:BAAALgADCgEJAQAAAA==.Aleeta:BAAALgAECgQJBAAAAA==.Allucard:BAAALgAECgkJAgAAAA==.',
Am='Amapanda:BAAALgAECgkJCQAAAA==.Amaria:BAAALgAECgMJBAABLgAECggJFQAFAAQcAA==.Amoracchius:BAAALgADCgMJAwAAAA==.',
An='Angelstörm:BAACLgAFFH8IAAIGAAIJPwxAJgBoAAAGAAIJPwxAJgBoAAAuAAQKfz0AAgYACAnOGhwUAB8CAAYACAnOGhwUAB8CAAAA.Anorili:BAAALgADCgYJBgAAAA==.Antarias:BAABLgAECn8cAAQHAAgJqRrHDgBOAQAHAAUJDSPHDgBOAQAIAAYJ3hEcoQAWAQAJAAMJjhioIwB5AAAAAA==.Antarion:BAAALgAECgQJBAAAAA==.',
Ap='Applevendor:BAAALgADCgUJBQAAAA==.',
Ar='Arahil:BAAALgAECgQJBwAAAA==.Arcanio:BAAALgADCgQJBAAAAA==.Arcaux:BAAALgADCggJDgAAAA==.Arckenon:BAABLgAECn9BAAIKAAkJcCRCBgAtAwAKAAkJcCRCBgAtAwAAAA==.',
As='Ashdorei:BAAALgADCgMJAwAAAA==.Ashog:BAAALgAECgYJEgAAAA==.Astranos:BAAALgAECgEJAQABLgAECgkJNQACAHIPAA==.',
At='Athanyr:BAABLgAECn8sAAICAAgJXyU8BQBYAwACAAgJXyU8BQBYAwAAAA==.Atillis:BAAALgADCgYJDAAAAA==.',
Au='Augmentation:BAAALgAECgEJAQAAAA==.Austenpally:BAABLgAECn8gAAMKAAgJKRiHYgCRAQAKAAcJ3haHYgCRAQAFAAYJORKGPQA4AQAAAA==.',
Av='Aveycado:BAAALgADCgMJAQAAAA==.',
Aw='Awake:BAAALgAFFAMJAwAAAA==.',
Ax='Axeflack:BAAALgAECgEJAQAAAA==.Axegor:BAAALgADCgMJAwAAAA==.',
Az='Azrall:BAAALgADCgUJBQAAAA==.',
Ba='Bacuda:BAAALgAECgYJDgAAAA==.Balkris:BAAALgAECgEJAgABLgAECggJHQALAI8PAA==.Baratheon:BAABLgAECn8VAAMMAAkJCg9WFAClAQAMAAkJNg5WFAClAQAEAAcJXgbYXQA4AQAAAA==.',
Be='Beartooth:BAAALgADCgUJBQAAAA==.Beggles:BAAALgADCgEJAQAAAA==.Bereit:BAAALgADCgcJBgAAAA==.',
Bi='Biancadelrio:BAABLgAECn8ZAAINAAYJvxByKQAMAQANAAYJvxByKQAMAQAAAA==.Bigboned:BAAALgADCgEJAQABLgAECgkJHgAOAM0WAA==.Bigmode:BAAALgADCgYJBgAAAA==.',
Bj='Bjorrglbrgl:BAAALgAFFAMJAwAAAA==.',
Bl='Blackmask:BAAALgADCgUJCAAAAA==.Bladekrim:BAAALgAECgEJAgAAAA==.Blindashunae:BAACLgAFFH8bAAIPAAcJdhD2GACrAQAPAAcJdhD2GACrAQAuAAQKfxYAAg8ACQlQHikVANgCAA8ACQlQHikVANgCAAAA.Blindkungfu:BAAALgAECgQJBAAAAA==.Bloodrun:BAAALgADCgkJCgAAAA==.Blook:BAABLgAECn8UAAMQAAgJThUsHQCTAQAQAAgJThUsHQCTAQARAAEJkgg2HwA3AAAAAA==.Bluehazey:BAAALgAECgkJEQAAAA==.Blueleader:BAAALgAECgQJBAAAAA==.Bläz:BAAALgAECgEJAQAAAA==.',
Bo='Boomhammer:BAAALgAFFAIJBAAAAA==.Bootsy:BAAALgAECgcJBAAAAA==.Bopit:BAABLgAECn8VAAMKAAkJ+g6nnwBAAQAKAAYJeA6nnwBAAQAFAAkJ9AzJUAA2AQAAAA==.Botia:BAABLgAECn8UAAISAAYJiwTcVgCZAAASAAYJiwTcVgCZAAAAAA==.',
Br='Bruhh:BAAALgAECgYJBwAAAA==.Brunnera:BAAALgAECgIJAwAAAA==.Bruuenor:BAAALgAECgYJBgAAAA==.Bruul:BAABLgAECn8gAAQKAAcJKxatfABaAQAKAAcJKxatfABaAQAFAAQJ3Q2cVQDHAAAOAAEJ1RAOSQAvAAAAAA==.Brynjolf:BAAALgAECgUJCQAAAA==.',
Ca='Caenji:BAABLgAECn8WAAITAAgJ2guicABHAQATAAgJ2guicABHAQAAAA==.Carcharoth:BAABLgAECn8nAAMJAAkJlBhOCACsAQAJAAcJNRpOCACsAQAIAAYJqBDHowDuAAAAAA==.Carmelina:BAABLgAECn8gAAINAAgJhRp3DQAuAgANAAgJhRp3DQAuAgAAAA==.Catrixona:BAAALgAECgUJCAAAAA==.Caylan:BAAALgADCgQJBAAAAA==.',
Ch='Chadgar:BAAALgADCgIJAgAAAA==.Chaoscaster:BAAALgADCgkJCQABLgAECgYJBgABAAAAAA==.Charroth:BAAALgAECgYJCAAAAA==.Chey:BAABLgAECn8zAAIQAAkJ1iROAgAqAwAQAAkJ1iROAgAqAwAAAA==.Chilai:BAABLgAECn8lAAIUAAkJABhVCgAgAgAUAAkJABhVCgAgAgAAAA==.Chipsahoy:BAABLgAECn8iAAMVAAkJ2x9OCADFAgAVAAkJ2x9OCADFAgAWAAYJdRJ3RQBsAQAAAA==.Chrîstîan:BAAALgADCgYJBgAAAA==.Chíef:BAABLgAFFH8IAAMWAAUJYQkXJAAzAQAWAAUJYQkXJAAzAQAVAAIJNwN6QABhAAAAAA==.',
Ci='Cindrozetha:BAAALgADCgEJAQAAAA==.Ciphérdivine:BAAALgADCgUJBAAAAA==.Citte:BAAALgAFFAEJAgAAAA==.',
Cl='Close:BAAALgADCgUJBQABLgAFFAMJCAAWANEiAA==.',
Co='Conciete:BAABLgAECn8VAAMXAAgJWhXmGgAHAgAXAAgJWhXmGgAHAgAYAAEJBAHidwARAAAAAA==.Conorix:BAAALgAECgUJCAAAAA==.Corvo:BAABLgAECn8WAAIOAAgJSRidDQDPAQAOAAgJSRidDQDPAQAAAA==.Counselor:BAAALgAECgUJCQAAAA==.Courallie:BAAALgAECgEJAQAAAA==.',
Cr='Crataxxis:BAABLgAECn80AAINAAgJBxpgDgAfAgANAAgJBxpgDgAfAgAAAA==.Crynos:BAAALgADCgMJAwAAAA==.Crysandra:BAAALgAECgUJBQAAAA==.',
Cy='Cydon:BAABLgAECn81AAIUAAkJvR6IBAC1AgAUAAkJvR6IBAC1AgAAAA==.',
Da='Daereth:BAAALgAECgYJCQAAAA==.Daerrith:BAAALgAECgUJCQAAAA==.Dala:BAAALgAECgUJBQAAAA==.Damienfox:BAAALgAECgQJBAAAAA==.Dana:BAAALgAECgYJDQABLgAFFAMJDwACABIUAA==.Danellia:BAAALgADCgUJBQAAAA==.Darkreaper:BAAALgAECgQJBAAAAA==.Darrwin:BAABLgAECn8mAAMKAAgJoR+QIABuAgAKAAgJoR+QIABuAgAOAAQJnw0iKwCpAAAAAA==.Dawicker:BAAALgADCgYJDwAAAA==.Daylight:BAAALgAECgYJCQAAAA==.',
De='Dedoria:BAAALgADCgUJBQAAAA==.Defacto:BAAALgADCgMJAwAAAA==.Delat:BAAALgAECgEJAQAAAA==.Delrac:BAABLgAECn8iAAIPAAgJWxEDUQB7AQAPAAgJWxEDUQB7AQAAAA==.Demonalsa:BAAALgAECgEJAQABLgAFFAMJCAAZANMIAA==.Denathrius:BAAALgAECgIJAgABLgAFFAMJBgAPAAEZAA==.Denero:BAABLgAECn8dAAIKAAkJIx7jFgCjAgAKAAkJIx7jFgCjAgAAAA==.Departure:BAAALgAECgQJBwABLgAECgcJFwANAEMcAA==.Derith:BAAALgADCgEJAQAAAA==.',
Df='Dfabness:BAACLgAFFH8FAAIXAAIJDA7XKQCDAAAXAAIJDA7XKQCDAAAuAAQKfyAAAhcACQlKEGgfAJ0BABcACQlKEGgfAJ0BAAAA.',
Di='Dic:BAAALgADCgIJAgABLgAECgMJAwABAAAAAA==.',
Do='Docbushed:BAAALgAECgQJBAABLgAFFAQJDQAIAN0EAA==.Dotbush:BAACLgAFFH8NAAMIAAQJ3QRpXQDxAAAIAAQJ3QRpXQDxAAAJAAEJhwLvJQA3AAAuAAQKfy8ABAgACAnXFktAAA0CAAgACAniFUtAAA0CAAkAAwmrDIBGAJwAAAcAAgnOEesiAH0AAAAA.Dotspot:BAAALgADCgQJBAABLgAECgMJBwABAAAAAA==.',
Dr='Dracthayr:BAABLgAECn86AAILAAkJZRPGBQDqAQALAAkJZRPGBQDqAQAAAA==.Dragonhammer:BAACLgAFFH8LAAIKAAIJGST0XADVAAAKAAIJGST0XADVAAAuAAQKf1EAAgoACQmAJHYFADgDAAoACQmAJHYFADgDAAAA.Drakanna:BAAALgAECgIJAgAAAA==.Draxela:BAAALgAECgUJCQAAAA==.Dreaming:BAABLgAECn8wAAIaAAkJZiLBBAD7AgAaAAkJZiLBBAD7AgABLgAFFAMJCAAWANEiAA==.Drosidon:BAABLgAECn8UAAIbAAYJnAWG5ACzAAAbAAYJnAWG5ACzAAAAAA==.Drubo:BAAALgAECgEJAQAAAA==.',
Ea='Earsog:BAAALgADCgEJAQAAAA==.Earthenfist:BAAALgAECgEJAQAAAA==.',
Eb='Ebebebebe:BAAALgAECgEJAQAAAA==.',
Ef='Efbomb:BAAALgADCgcJBwAAAA==.',
Ei='Eitherindel:BAAALgADCgkJCgAAAA==.',
El='Elanore:BAAALgAECgEJAQAAAA==.Ellaini:BAABLgAECn8RAAIcAAcJCgz8OQAIAQAcAAcJCgz8OQAIAQAAAA==.Ellie:BAABLgAFFH8GAAIWAAQJOBVbKAAfAQAWAAQJOBVbKAAfAQAAAA==.Elseb:BAAALgAECgQJBwAAAA==.',
Em='Emotion:BAAALgADCgYJAQABLgAFFAMJCAAWANEiAA==.',
En='Enchantrêss:BAAALgADCgQJBAABLgAECgcJCwABAAAAAA==.',
Er='Erenara:BAAALgAECgQJCwAAAA==.',
Ev='Evic:BAABLgAECn81AAICAAkJcg/gMwC6AQACAAkJcg/gMwC6AQAAAA==.',
Ew='Ewson:BAAALgADCgcJCwAAAA==.',
Ex='Excrubilis:BAAALgAFFAIJBAAAAA==.',
Fa='Faandango:BAAALgAECgUJBQAAAA==.Faeleader:BAABLgAECn8aAAICAAgJVQ1GRwBfAQACAAgJVQ1GRwBfAQAAAA==.Faevelina:BAAALgAECgUJDAABLgAECgcJCgABAAAAAA==.Faytadori:BAAALgADCgEJAQAAAA==.',
Fe='Felgrrl:BAAALgADCgkJKAAAAA==.Felsite:BAAALgAECgkJAQAAAA==.Feyreh:BAAALgAECgUJAwAAAA==.',
Fi='Fieona:BAAALgADCgYJCwAAAA==.Firethorns:BAAALgAECgQJBQAAAA==.Fistandilias:BAAALgADCgkJCQAAAA==.Fitzbang:BAAALgAECgUJBwAAAA==.',
Fl='Florigrowl:BAAALgAECgMJAwAAAA==.',
Fo='Forever:BAAALgAECgMJBQABLgAFFAMJCAAWANEiAA==.Formortiis:BAAALgADCgEJAQAAAA==.Forrestior:BAABLgAECn8YAAIdAAgJoiShAQBBAwAdAAgJoiShAQBBAwAAAA==.Forsthoof:BAAALgADCgYJBgAAAA==.',
Fr='Fraga:BAAALgAECgYJDgABLgAFFAQJCwAbAJkMAA==.Frailty:BAAALgAECgYJCwAAAA==.Frique:BAAALgAECgUJDgAAAA==.Frostfingers:BAAALgAECgQJBgAAAA==.Frostyfang:BAABLgAECn8kAAMeAAgJ/xxJEACOAQAeAAYJpCBJEACOAQASAAQJthM2TQC7AAAAAA==.Frozenyogert:BAAALgAECgQJBAAAAA==.',
Fu='Fufula:BAAALgADCgQJBAAAAA==.Funkbot:BAAALgAECgYJDAAAAA==.',
['Fä']='Färshadow:BAAALgAECgEJAQAAAA==.',
Ga='Galbur:BAACLgAFFH8LAAIbAAQJmQxJZwARAQAbAAQJmQxJZwARAQAuAAQKfyQAAxsACAmhHqQ3AA0CABsACAlPHaQ3AA0CABoABwkyE8wXAJ0BAAAA.Galdrin:BAAALgAECgcJCgAAAA==.Gaspode:BAAALgADCgcJBwAAAA==.Gassann:BAAALgAECggJDgAAAA==.',
Ge='Geers:BAABLgAECn8dAAIfAAkJ2SLNCwAHAwAfAAkJ2SLNCwAHAwAAAA==.Geta:BAAALgAECgQJBwABLgAECgkJIAAEAF0iAA==.Getacast:BAAALgAECgEJAQABLgAECgkJIAAEAF0iAA==.Getademon:BAAALgADCgEJAQABLgAECgkJIAAEAF0iAA==.Getaform:BAAALgAECgEJAQABLgAECgkJIAAEAF0iAA==.Getagrip:BAAALgAECgQJBgABLgAECgkJIAAEAF0iAA==.Getaheal:BAAALgAECgYJBgABLgAECgkJIAAEAF0iAA==.Getalife:BAAALgADCgQJBAABLgAECgkJIAAEAF0iAA==.Getarage:BAABLgAECn8gAAIEAAkJXSIeFACtAgAEAAkJXSIeFACtAgAAAA==.',
Gh='Ghil:BAABLgAECn8vAAMHAAkJqiO7AAARAwAHAAkJqiO7AAARAwAIAAQJnxXfvADfAAAAAA==.',
Gi='Gigawatt:BAABLgAECn8qAAMVAAkJYRTkKwB9AQAVAAgJ0RHkKwB9AQAWAAMJ9QkhlQCBAAAAAA==.Gildersleeve:BAAALgAECgQJCAAAAA==.Gilia:BAAALgADCgkJMQAAAA==.Girthfist:BAABLgAECn8WAAIgAAgJRSMIBQA5AwAgAAgJRSMIBQA5AwABLgAFFAgJGQADAN8dAA==.',
Gl='Glynixtwo:BAAALgAECgMJBQAAAA==.',
Go='Goldiwarlock:BAAALgADCgcJDgAAAA==.Goloron:BAAALgADCgkJDwAAAA==.',
Gr='Graymayn:BAABLgAECn8ZAAIdAAgJLRrbDgAxAgAdAAgJLRrbDgAxAgAAAA==.Gremel:BAABLgAECn8eAAMeAAYJQyF3FQBIAQAeAAUJsBp3FQBIAQASAAIJsx+bTQC5AAAAAA==.Grimflaps:BAAALgAECgIJAgAAAA==.Grimmist:BAABLgAECn8hAAIYAAcJihjgKgCqAQAYAAcJihjgKgCqAQAAAA==.',
Gu='Guloot:BAABLgAECn8bAAMWAAgJBAZ3eADUAAAWAAgJBAZ3eADUAAAVAAUJtQYmdwBlAAAAAA==.Gunboyten:BAAALgAECgIJAgAAAA==.Gunderthirth:BAACLgAFFH8ZAAIDAAgJ3x2QAgAqAgADAAgJ3x2QAgAqAgAuAAQKfyYAAgMACQnKI6IBAGsDAAMACQnKI6IBAGsDAAAA.Gurkin:BAAALgADCgEJAQAAAA==.',
Gw='Gwaeniiha:BAABLgAECn8pAAIKAAgJMA4EegBfAQAKAAgJMA4EegBfAQAAAA==.Gward:BAAALgAECgUJBgAAAA==.Gwizz:BAABLgAECn8sAAIfAAkJnBvgKQBcAgAfAAkJnBvgKQBcAgAAAA==.',
Ha='Halibard:BAABLgAFFH8GAAIGAAMJuwjNHwCaAAAGAAMJuwjNHwCaAAAAAA==.Halinka:BAAALgADCgYJBgAAAA==.Handsoap:BAABLgAECn8bAAINAAgJZw/YHwBVAQANAAgJZw/YHwBVAQAAAA==.Haquar:BAAALgAECgQJBAAAAA==.Hardhitter:BAAALgAECggJDgAAAA==.',
He='Hehe:BAAALgADCgQJBAAAAA==.Helldog:BAAALgAECgMJAwABLgAECggJJAAhAJIeAA==.Hellumph:BAABLgAECn8kAAIhAAgJkh74AwB0AgAhAAgJkh74AwB0AgAAAA==.Hermesconrad:BAAALgAECggJCgAAAA==.Hevensrath:BAABLgAECn83AAIKAAkJ7R65FQCrAgAKAAkJ7R65FQCrAgAAAA==.',
Ho='Hokuden:BAABLgAECn86AAIiAAkJGhm8BgAKAgAiAAkJGhm8BgAKAgAAAA==.Honina:BAAALgADCgIJAgAAAA==.Hornswaggles:BAAALgAECgQJBAAAAA==.Horsebananas:BAABLgAECn8yAAMdAAgJrRuQGADNAQAdAAcJLRuQGADNAQATAAcJ+xkYRACfAQAAAA==.',
Ht='Htari:BAAALgAECgEJAQAAAA==.',
Hu='Huddington:BAABLgAECn8hAAIjAAgJSRmOAwDMAQAjAAgJSRmOAwDMAQAAAA==.Hussh:BAAALgAECgYJDAABLgAECgkJHgAOAM0WAA==.',
Hy='Hydraness:BAAALgAECgEJAQABLgAECgQJBAABAAAAAA==.',
Ia='Iamcammy:BAAALgAECgYJEAAAAA==.',
Ic='Icedragon:BAAALgAECgEJAQAAAA==.',
Ig='Igknight:BAAALgAECgMJAwABLgAECgkJJAAgANgNAA==.',
Il='Illexi:BAAALgADCgYJBgAAAA==.',
Im='Imariz:BAAALgAECgcJBwAAAA==.Imdarkness:BAAALgAECgcJCwAAAA==.Impquisitor:BAAALgAECgYJBwAAAA==.',
In='Indecent:BAABLgAECn8xAAQIAAkJHh0hFAChAgAIAAkJHh0hFAChAgAJAAYJHBd3FACnAQAHAAMJ3hQLGAC7AAAAAA==.Indeed:BAAALgAECgUJBgAAAA==.Inibble:BAAALgADCgcJBgAAAA==.',
Is='Ishy:BAAALgAECgUJCAAAAA==.',
Ix='Ixelle:BAAALgADCgUJDQABLgAECgUJEAABAAAAAA==.',
Iz='Izomar:BAABLgAECn8gAAIfAAgJahkjRQD1AQAfAAgJahkjRQD1AQAAAA==.',
Ja='Jackieechan:BAAALgAECgUJBQABLgAFFAQJDQAFAEAmAA==.Jackiemays:BAACLgAFFH8NAAMFAAQJQCbiDQC1AQAFAAQJQCbiDQC1AQAKAAEJsQHuqAA1AAAuAAQKfzAAAwUACAkUJEMMALYCAAUACAkUJEMMALYCAAoACAlgGnY9AC8CAAAA.Jaded:BAAALgADCgYJBgAAAA==.Jaleigha:BAAALgADCgYJBwAAAA==.Jamesin:BAAALgAECgYJCAAAAA==.',
Je='Jedaii:BAAALgAECgYJBgAAAA==.Jeff:BAAALgAECgEJAwAAAA==.Jeses:BAABLgAECn8vAAIKAAkJQhbJOQADAgAKAAkJQhbJOQADAgAAAA==.',
Jo='Jollah:BAAALgAECgUJBgAAAA==.',
Ju='Jutic:BAABLgAECn86AAIWAAkJziKXBgAyAwAWAAkJziKXBgAyAwAAAA==.',
Jy='Jyssa:BAAALgADCgEJAQAAAA==.',
['Jö']='Jörmun:BAAALgAFFAIJBAAAAA==.',
Ka='Kaia:BAABLgAECn8lAAIQAAkJgA96FQDbAQAQAAkJgA96FQDbAQAAAA==.Kaldrich:BAAALgAECgEJAQAAAA==.Kamoto:BAAALgAECgQJBAABLgAECgkJKgAVAGEUAA==.Kanetsu:BAAALgADCgIJAgAAAA==.Kardas:BAABLgAECn8YAAMTAAkJuQdAXgByAQATAAkJuQdAXgByAQAkAAMJ1AGLfABSAAAAAA==.Kardio:BAABLgAECn8ZAAMXAAgJqQ2tKwCBAQAXAAgJqQ2tKwCBAQAYAAEJAQpQZwA1AAAAAA==.Kayj:BAAALgADCgYJBwAAAA==.Kayrina:BAAALgADCgkJCgAAAA==.Kazeer:BAAALgAECgcJEQAAAA==.',
Kb='Kbilly:BAABLgAECn83AAIWAAkJKiIDBQBPAwAWAAkJKiIDBQBPAwAAAA==.',
Ke='Kegger:BAAALgAECgEJAQAAAA==.Keylerin:BAACLgAFFH8bAAIQAAYJlSMGCADVAQAQAAYJlSMGCADVAQAuAAQKfyEAAhAACQmAGkgTAH4CABAACQmAGkgTAH4CAAAA.',
Ki='Kibbik:BAACLgAFFH8LAAIcAAQJEgabGwD0AAAcAAQJEgabGwD0AAAuAAQKfysAAhwACQlHExAdAL4BABwACQlHExAdAL4BAAAA.Kija:BAAALgAECgYJBgAAAA==.Kitsunami:BAAALgAECgcJBgAAAA==.',
Kl='Klepal:BAAALgADCgkJCgAAAA==.Klutchshield:BAAALgAECgEJAQAAAA==.',
Kn='Kneecap:BAAALgAECgUJCQAAAA==.Knottes:BAAALgAECgEJAQAAAA==.',
Ko='Kobe:BAAALgAECgYJEwAAAA==.Koharu:BAAALgADCgcJFgAAAA==.Kookykg:BAAALgAECgEJAQAAAA==.',
Kr='Krampus:BAABLgAECn83AAIZAAkJExQ5CQASAgAZAAkJExQ5CQASAgAAAA==.Kranok:BAAALgAECgYJDgAAAA==.Krim:BAAALgADCgUJBgAAAA==.Krimdevourer:BAAALgADCgYJBgAAAA==.Krimhuntress:BAAALgAECgEJAgAAAA==.',
Ku='Kunac:BAAALgAECggJDwAAAA==.',
Ky='Kynessa:BAAALgAECgUJEAAAAA==.Kyrun:BAABLgAECn8rAAIZAAkJjgxXDwCdAQAZAAkJjgxXDwCdAQAAAA==.Kyuutips:BAAALgADCgEJAQAAAA==.',
['Kã']='Kãne:BAACLgAFFH8GAAIlAAIJgwRTTwBnAAAlAAIJgwRTTwBnAAAuAAQKfyQAAyUACQmFERYnAI0BACUACQmFERYnAI0BAAsAAgm9Bpo4AFQAAAAA.',
La='Lamoran:BAAALgADCgkJDwAAAA==.Lannes:BAAALgADCgEJAQAAAA==.Lapz:BAAALgAECgkJEQAAAA==.Lavetra:BAAALgAECgMJBAAAAA==.Lazerdinger:BAAALgAECgEJAQAAAA==.',
Le='Legendary:BAACLgAFFH8IAAIOAAIJ0h2ODQCFAAAOAAIJ0h2ODQCFAAAuAAQKfxQAAg4ACQlbIMQDANcCAA4ACQlbIMQDANcCAAAA.Lethran:BAAALgAECgMJAwAAAA==.',
Lh='Lhani:BAABLgAECn8lAAIGAAgJrRMLHwC0AQAGAAgJrRMLHwC0AQAAAA==.',
Li='Liadrin:BAABLgAECn8eAAIOAAkJzRZ0DwDNAQAOAAkJzRZ0DwDNAQAAAA==.Lie:BAABLgAECn8dAAILAAgJjw8XCQCHAQALAAgJjw8XCQCHAQAAAA==.Liliana:BAAALgADCgkJNwAAAA==.Lirrasha:BAAALgADCgYJBgAAAA==.',
Ll='Llyrael:BAABLgAECn8dAAMGAAgJkgucLABPAQAGAAgJkgucLABPAQAcAAIJxANGhAAkAAAAAA==.',
Lo='Lolineverdie:BAABLgAECn8aAAMCAAkJ4gpaVQAoAQACAAkJ4gpaVQAoAQASAAYJnQLfYgBwAAAAAA==.',
Lu='Luna:BAABLgAECn8iAAMGAAgJEQrzLQCNAQAGAAgJEQrzLQCNAQAcAAgJ1QcnNAAlAQAAAA==.',
Ly='Lyrev:BAAALgAECgYJEwAAAA==.',
['Ló']='Lórien:BAAALgADCgIJAgAAAA==.',
Ma='Macaoidh:BAAALgAECgYJBgAAAA==.Maddeleine:BAAALgAECgYJEgAAAA==.Magicdemon:BAABLgAECn81AAMNAAkJrCXtBwCVAgANAAkJeSXtBwCVAgAPAAgJnSBnGgBiAgAAAA==.Magichunter:BAAALgAECgEJAQABLgAECgkJNQANAKwlAA==.Makall:BAAALgADCgEJAQAAAA==.Makanoa:BAAALgADCgYJBgAAAA==.Malaah:BAABLgAECn87AAIVAAkJtxW9HADjAQAVAAkJtxW9HADjAQAAAA==.Malafar:BAAALgAFFAIJAwAAAA==.Malatrixx:BAAALgAECgEJAQAAAA==.Maldiriel:BAAALgAECggJCAAAAA==.Mallikus:BAAALgADCgkJCgAAAA==.Manofsecks:BAAALgAECgQJDAAAAA==.Mapachote:BAABLgAECn8nAAIkAAgJ0hl9BgASAgAkAAgJ0hl9BgASAgAAAA==.Marodin:BAAALgADCgkJMgAAAA==.Marthaiden:BAAALgAECgkJDgAAAA==.Maryjaina:BAAALgADCgYJBgAAAA==.Mavastus:BAAALgADCgcJBwAAAA==.Mazozul:BAABLgAECn8vAAMmAAkJghVmFgADAgAmAAgJrhNmFgADAgAGAAUJ/BSMOwDwAAAAAA==.',
Me='Meatbaal:BAAALgADCgYJCAAAAA==.Melinaria:BAABLgAECn8oAAMcAAkJMBWxGADlAQAcAAkJMBWxGADlAQAmAAEJ6gENdwAhAAAAAA==.Melisondraa:BAAALgADCgkJCQAAAA==.Meow:BAAALgADCgQJBAAAAA==.Merkala:BAAALgADCgYJCQAAAA==.Metalbot:BAAALgADCgkJCQAAAA==.',
Mi='Miarose:BAAALgAECgUJBgAAAA==.Miggydogg:BAAALgAECgUJCwAAAA==.Mileta:BAABLgAECn8aAAISAAgJyhcDFwD/AQASAAgJyhcDFwD/AQAAAA==.Mimic:BAAALgAECgIJAgAAAA==.Minthammer:BAAALgAECgIJBAABLgAFFAIJBAABAAAAAA==.Mirthias:BAAALgAECgMJAwAAAA==.Mistylady:BAAALgAECgIJAgAAAA==.',
Mo='Monki:BAAALgAECgYJDwAAAA==.Moozohar:BAAALgADCgEJAQAAAA==.Morgorra:BAAALgAECgMJBwAAAA==.Morvila:BAAALgAECgMJAwAAAA==.Mote:BAABLgAECn8eAAMmAAgJxxcPHADMAQAmAAcJUxcPHADMAQAcAAgJyw3vKwBWAQAAAA==.',
Mu='Muertes:BAAALgAECgEJAQAAAA==.Multidollar:BAAALgADCgUJBQABLgAFFAMJBgATAGIWAA==.Muminah:BAAALgAECgMJBgAAAA==.',
['Mô']='Môlly:BAACLgAFFH8MAAIGAAQJ4Bx3DQBOAQAGAAQJ4Bx3DQBOAQAuAAQKfykAAgYACAlfIpUFAPYCAAYACAlfIpUFAPYCAAAA.',
Na='Narnluz:BAABLgAECn8dAAIGAAgJfBdDFgAKAgAGAAgJfBdDFgAKAgAAAA==.Nazor:BAABLgAECn8nAAIPAAgJ1xlsOQDKAQAPAAgJ1xlsOQDKAQAAAA==.',
Ne='Necronic:BAAALgADCgYJCwAAAA==.Necroreign:BAABLgAECn9BAAINAAkJ2hzbCACDAgANAAkJ2hzbCACDAgAAAA==.Neith:BAAALgADCgMJAwAAAA==.Nemera:BAAALgADCgYJCAAAAA==.Nervous:BAABLgAFFH8IAAIWAAMJ0SJbJQAtAQAWAAMJ0SJbJQAtAQAAAA==.Nessee:BAAALgAECgUJEQAAAA==.',
Ni='Niall:BAABLgAECn8yAAIeAAkJ3CFiAgDuAgAeAAkJ3CFiAgDuAgAAAA==.Nilithis:BAABLgAECn8rAAMIAAkJeRnuJwAuAgAIAAkJCxnuJwAuAgAJAAQJGxN/HQCnAAAAAA==.Niú:BAAALgADCgYJBgAAAA==.',
No='Norsehammer:BAABLgAECn8UAAIVAAcJpgnCQwA6AQAVAAcJpgnCQwA6AQABLgAFFAIJBAABAAAAAA==.Nozmua:BAAALgADCgkJDgAAAA==.',
Ny='Nyghtchyld:BAAALgAECgYJEQAAAA==.Nyxlumina:BAAALgAECgIJAgAAAA==.',
['Né']='Néssima:BAABLgAECn8gAAMKAAkJ0RU3YACXAQAKAAkJZw43YACXAQAOAAUJYhuaIwDrAAAAAA==.',
Oa='Oak:BAAALgAECgEJBQAAAA==.Oathfinder:BAAALgAECgcJEAAAAA==.',
Oc='Occurrence:BAABLgAECn8VAAMCAAgJ2gVveQC5AAACAAcJBwRveQC5AAASAAEJZwJokwAeAAAAAA==.Octalexane:BAAALgAECgUJBgAAAA==.',
On='Onebuttonman:BAAALgADCgYJBgAAAA==.Onimusha:BAAALgAECgMJAwAAAA==.',
Or='Ortalbem:BAACLgAFFH8FAAIfAAIJeBP8iQCaAAAfAAIJeBP8iQCaAAAuAAQKfzoAAh8ACQkXI6QOAPECAB8ACQkXI6QOAPECAAAA.',
Ov='Ovi:BAAALgADCgIJAgAAAA==.',
Pa='Pandariee:BAABLgAECn8VAAIbAAgJYw35bQB1AQAbAAgJYw35bQB1AQAAAA==.Pangsh:BAAALgAFFAIJBAAAAA==.Parzval:BAAALgAECgEJAgAAAA==.Paxgor:BAAALgAECgEJAQAAAA==.',
Pe='Pendaemonia:BAABLgAECn82AAINAAkJuRaLDwAOAgANAAkJuRaLDwAOAgAAAA==.Penelopie:BAAALgADCgYJBgAAAA==.Percfirdy:BAAALgADCgUJBQAAAA==.',
Ph='Pherix:BAABLgAECn8cAAIcAAcJ1SA5FQAGAgAcAAcJ1SA5FQAGAgAAAA==.Phiirys:BAAALgAECgEJAQAAAA==.',
Pi='Picaso:BAAALgADCgEJAQAAAA==.Pight:BAAALgAECgYJDgABLgAECggJHQALAI8PAA==.',
Po='Poomacha:BAABLgAECn8nAAITAAcJ6xdcTQChAQATAAcJ6xdcTQChAQAAAA==.',
Pu='Puffthemagic:BAAALgADCgYJCAAAAA==.Punishêr:BAAALgADCgMJAwABLgAECgcJCwABAAAAAA==.',
Py='Pyree:BAABLgAECn8iAAMlAAkJbBC9JwCKAQAlAAkJzA+9JwCKAQALAAcJaAk0GQBzAAAAAA==.Pyxrin:BAAALgAECgcJBwAAAA==.',
['Pø']='Pøë:BAAALgAECgkJEwABLgAFFAIJAgABAAAAAA==.',
Qu='Qu:BAAALgAFFAIJAwABLgAFFAMJAwABAAAAAQ==.',
Qv='Qveemcorkie:BAAALgAECgEJAQAAAA==.',
['Qí']='Qín:BAAALgADCgUJAwAAAA==.',
Ra='Radagust:BAAALgAECgQJBAAAAA==.Radcat:BAAALgAECgEJBAAAAA==.Raenne:BAAALgAECgIJAwAAAA==.Ragebait:BAAALgADCgIJAgAAAA==.Rainfall:BAAALgAECgEJAgAAAA==.Raistlain:BAAALgAECgYJDwAAAA==.Raitha:BAAALgADCgUJCAAAAA==.Ralli:BAABLgAECn8pAAIPAAgJnRn8LgD1AQAPAAgJnRn8LgD1AQAAAA==.Rallsdemon:BAAALgAECgQJBAABLgAECgYJCAABAAAAAA==.Rallsdk:BAAALgAECgYJCAAAAA==.Rallsodins:BAAALgAECgUJBQABLgAECgYJCAABAAAAAA==.Randomguy:BAACLgAFFH8JAAIQAAQJ9RnIEABgAQAQAAQJ9RnIEABgAQAuAAQKfzcAAhAACQl2JUoCACwDABAACQl2JUoCACwDAAAA.Ranulf:BAAALgAECgQJBgAAAA==.Ratava:BAAALgAECgMJAwAAAA==.Ratboy:BAEALgAECgEJAQABLgAECgkJMAAmABwjAA==.Ratrot:BAABLgAECn8eAAIWAAYJJyHhHwA2AgAWAAYJJyHhHwA2AgAAAA==.Ratsdead:BAAALgAECgEJAQAAAA==.Razenath:BAAALgADCgcJDAAAAA==.',
Re='Reinhardt:BAAALgADCgYJBgAAAA==.Rekrella:BAAALgADCgUJBQAAAA==.Reldarus:BAEBLgAECn8wAAMmAAkJHCMzAgCDAwAmAAkJHCMzAgCDAwAGAAQJ+hr8RAAlAQAAAA==.Rena:BAAALgADCgcJBwAAAA==.Rendia:BAAALgADCgMJAwAAAA==.Renik:BAAALgADCgIJAQAAAA==.Revennek:BAAALgAECgUJCgAAAA==.Reverence:BAABLgAECn8eAAIKAAkJ8A1LWQCoAQAKAAkJ8A1LWQCoAQAAAA==.Revilation:BAABLgAECn8cAAIOAAkJYBNcEQCWAQAOAAkJYBNcEQCWAQAAAA==.Rezjyk:BAAALgAECgYJCAABLgAECggJLAAKALMdAA==.Rezzyk:BAABLgAECn8sAAIKAAgJsx1dJQBWAgAKAAgJsx1dJQBWAgAAAA==.',
Rh='Rhonus:BAAALgAECgEJAQAAAA==.Rhyxali:BAABLgAECn8YAAQJAAcJjQp5FgDaAAAHAAYJLAeuFwDgAAAJAAcJAgl5FgDaAAAIAAQJ5AHK+QBmAAAAAA==.',
Ri='Riis:BAAALgAECgUJCwAAAA==.Riiselock:BAABLgAECn8tAAMIAAgJIR5CNwAvAgAIAAcJyR1CNwAvAgAJAAQJFBwuFQDkAAAAAA==.Riiwind:BAAALgADCgQJBAABLgAECgkJAwABAAAAAA==.Riktade:BAAALgADCgYJBgAAAA==.Rilight:BAAALgAECgEJAQABLgAECgkJAwABAAAAAA==.Riptidepod:BAABLgAECn8dAAMWAAgJ7gdNWwAsAQAWAAgJ7gdNWwAsAQAVAAIJ3gJsqgAdAAAAAA==.',
Ro='Robbiebrews:BAAALgADCgUJBQAAAA==.Robear:BAAALgAECgEJAQAAAA==.Rowin:BAAALgADCgUJBQAAAA==.',
Ry='Rynley:BAABLgAECn8WAAMQAAUJASEKJwDAAQAQAAUJASEKJwDAAQAnAAIJWRG2GABwAAAAAA==.',
Sa='Sacredscales:BAABLgAECn8hAAMGAAkJtR5kCwCaAgAGAAcJ3yRkCwCaAgAcAAcJtRSGKgCGAQAAAA==.Sagerremeseb:BAAALgAECgQJBAAAAA==.Sakii:BAABLgAECn8lAAIPAAkJJRJzMwDiAQAPAAkJJRJzMwDiAQAAAA==.Salera:BAAALgADCgQJBAAAAA==.Salvion:BAAALgAECgcJAQAAAA==.Samvimes:BAABLgAECn8kAAIKAAgJXw+IcQBxAQAKAAgJXw+IcQBxAQAAAA==.Sangreene:BAABLgAECn8bAAIcAAgJRxqFEwBYAgAcAAgJRxqFEwBYAgAAAA==.Sargis:BAABLgAECn8+AAMKAAkJ0SIQCgADAwAKAAkJ0SIQCgADAwAFAAgJxxtRGAAuAgAAAA==.Sarial:BAAALgADCgMJAwAAAA==.',
Sc='Schrödinger:BAAALgAECgYJDwABLgAECggJFgAOAEkYAA==.Sciblasts:BAAALgADCgEJAQABLgAECgUJBQABAAAAAA==.Scott:BAACLgAFFH8jAAIPAAcJuyNOBwBZAgAPAAcJuyNOBwBZAgAuAAQKf0YAAg8ACQmaJnUAAO4DAA8ACQmaJnUAAO4DAAAA.Scratchh:BAABLgAECn8dAAIgAAgJlAstNgB0AQAgAAgJlAstNgB0AQAAAA==.',
Se='Searalsa:BAAALgAECgUJBwABLgAFFAMJCAAZANMIAA==.Sentis:BAABLgAECn8eAAISAAgJJwdNPgD5AAASAAgJJwdNPgD5AAAAAA==.',
Sh='Shadowbrooks:BAAALgAECgIJAgAAAA==.Shadowgiver:BAAALgADCgcJDwAAAA==.Shadowsdemon:BAAALgADCgEJAQAAAA==.Shadowsworn:BAAALgAECgEJAQAAAA==.Shagol:BAAALgAECgQJBwAAAA==.Shalriss:BAABLgAECn8kAAIcAAgJIRm7GQDbAQAcAAgJIRm7GQDbAQAAAA==.Shamemoon:BAABLgAECn8cAAIPAAgJQxjqOQDIAQAPAAgJQxjqOQDIAQAAAA==.Shamunroe:BAABLgAECn8pAAMWAAkJMAdaVgA9AQAWAAkJMAdaVgA9AQAVAAUJkxKwWgDZAAAAAA==.Shatterhoof:BAABLgAECn8hAAIeAAcJoQvHGwAGAQAeAAcJoQvHGwAGAQAAAA==.Shelle:BAAALgAECgUJCAAAAA==.Shiftys:BAAALgADCgUJCgABLgAECgUJBgABAAAAAA==.Shingra:BAACLgAFFH8dAAIlAAYJcBkhFQB/AQAlAAYJcBkhFQB/AQAuAAQKfygAAiUACQnGHYEMAHsCACUACQnGHYEMAHsCAAAA.Shoof:BAAALgADCgUJBQAAAA==.',
Si='Sifû:BAAALgADCgcJDgAAAA==.Sigourney:BAAALgAECgUJBQABLgAECggJMgAdAK0bAA==.Silversho:BAAALgAECgMJAwAAAA==.Silvoid:BAAALgADCgMJAwABLgAECgMJAwABAAAAAA==.Silvren:BAABLgAECn8pAAMEAAgJzxbWIwDBAQAEAAgJzxbWIwDBAQAMAAEJvwZoRgArAAAAAA==.Sindarion:BAAALgAECgUJBQABLgAFFAEJAgABAAAAAA==.Sinz:BAAALgAECgEJBQAAAA==.Siph:BAAALgAECgEJAQAAAA==.',
Sk='Skillidan:BAABLgAECn8nAAICAAkJQhqlEgClAgACAAkJQhqlEgClAgAAAA==.',
Sl='Slighttrash:BAABLgAECn8eAAIdAAYJLxdbJQBjAQAdAAYJLxdbJQBjAQAAAA==.Sloppy:BAAALgADCgkJCgAAAA==.',
Sm='Smacka:BAAALgAECgEJAQAAAA==.Smallcrow:BAACLgAFFH8eAAIXAAgJbR64AACUAgAXAAgJbR64AACUAgAuAAQKfxYAAhcABwkuJsQHAP8CABcABwkuJsQHAP8CAAAA.Smøke:BAAALgAECgMJAwAAAA==.',
Sn='Snallygaster:BAAALgADCgYJDAABLgAECgkJIwAUAJ8bAA==.Snowsong:BAAALgAECgEJAQAAAA==.',
Sp='Spamton:BAAALgADCgEJAQAAAA==.Spectrose:BAAALgADCgEJAQAAAA==.Spirit:BAAALgAECgEJAQAAAA==.Spiro:BAAALgAFFAIJAgAAAA==.',
St='Starge:BAAALgAECgUJBwAAAA==.Starre:BAAALgAECgUJBQAAAA==.Steffey:BAABLgAECn8iAAIWAAcJIgxdVwA5AQAWAAcJIgxdVwA5AQAAAA==.Straven:BAABLgAECn8bAAIfAAgJJhTAWQC4AQAfAAgJJhTAWQC4AQAAAA==.Sturgeson:BAACLgAFFH8YAAIDAAYJjRZsCwBRAQADAAYJjRZsCwBRAQAuAAQKfx8AAgMACQlvHQcMAEsCAAMACQlvHQcMAEsCAAAA.',
Su='Sulfato:BAAALgADCgEJAQAAAA==.Sulwen:BAABLgAECn9DAAIGAAkJJBd7FwD9AQAGAAkJJBd7FwD9AQAAAA==.',
Sw='Sweetpotato:BAAALgADCgEJAQAAAA==.Swiftfeet:BAABLgAECn8lAAITAAkJABSgOADkAQATAAkJABSgOADkAQAAAA==.',
Sy='Syrasia:BAAALgADCgUJBQAAAA==.Syselea:BAAALgADCgEJAQAAAA==.',
['Sö']='Söranin:BAABLgAECn8XAAIYAAYJ5xiRKwCmAQAYAAYJ5xiRKwCmAQAAAA==.',
Ta='Tachichan:BAAALgAECgYJBgAAAA==.Tadum:BAAALgADCgEJAQAAAA==.Taeili:BAABLgAECn8gAAMUAAkJIhU5IgAXAQASAAgJ2BVoNgBiAQAUAAYJKxM5IgAXAQAAAA==.Talisse:BAAALgADCgYJBgAAAA==.Tanequil:BAACLgAFFH8IAAICAAMJCgIoTQB3AAACAAMJCgIoTQB3AAAuAAQKfyMAAgIACAmsDNdKAHgBAAIACAmsDNdKAHgBAAAA.Taosha:BAAALgAECgYJBgAAAA==.Targaryian:BAAALgAECgMJAwAAAA==.Tav:BAAALgADCgUJBQAAAA==.Taylea:BAABLgAECn8WAAIfAAcJpA9eogAcAQAfAAcJpA9eogAcAQABLgAECggJJgAKAKEfAA==.',
Te='Techromancer:BAAALgAECgYJCAABLgAECgcJHAAcANUgAA==.Telleria:BAAALgAECgIJAgAAAA==.Tem:BAAALgAECgMJAwAAAA==.Tenumbras:BAAALgAECgYJDAAAAA==.Termonda:BAAALgAECgEJAQAAAA==.Terraclaw:BAAALgADCgUJBwAAAA==.Terrasia:BAAALgADCgYJBgAAAA==.Terrigino:BAAALgAECgIJAwAAAA==.',
Th='Thanatias:BAABLgAECn8XAAIaAAgJ8BQyGQB7AQAaAAgJ8BQyGQB7AQAAAA==.Thantasia:BAABLgAECn8VAAIfAAYJmANb6wCnAAAfAAYJmANb6wCnAAAAAA==.Thauras:BAAALgADCgcJFwAAAA==.Theeslan:BAABLgAECn8aAAIcAAkJ7gJ2QgDgAAAcAAkJ7gJ2QgDgAAAAAA==.Thokdar:BAAALgAECgUJBQAAAA==.Thom:BAACLgAFFH8KAAIiAAQJihCkCwAWAQAiAAQJihCkCwAWAQAuAAQKfykAAyIACAmuI+cAABwDACIACAmuI+cAABwDABsABgmoDjmxACABAAAA.Thør:BAAALgADCgcJDgAAAA==.',
Ti='Tifà:BAAALgAECgUJCAAAAA==.Timothy:BAABLgAECn8bAAINAAkJ7BhWDwAQAgANAAkJ7BhWDwAQAgAAAA==.Tinkphooey:BAAALgAECgYJCwAAAA==.Tinton:BAAALgADCgEJAQAAAA==.',
To='Toishi:BAAALgAECgEJAQAAAA==.Tormmok:BAAALgAECgYJDAAAAA==.Toshindo:BAAALgAECgEJAQAAAA==.',
Tr='Traazz:BAAALgAECgkJAQAAAA==.Trashpally:BAAALgAECgEJAgAAAA==.Tremèndor:BAAALgADCgMJAwAAAA==.Trey:BAAALgAECgEJAQAAAA==.Tristra:BAAALgAECgQJBAAAAA==.',
Ts='Tsuruga:BAABLgAECn83AAIgAAkJQA6mHwCXAQAgAAkJQA6mHwCXAQAAAA==.',
Tu='Turkwise:BAABLgAECn8zAAMUAAkJkhncCAA+AgAUAAkJkhncCAA+AgAeAAQJCBGsHgDuAAAAAA==.',
Ty='Tycondrius:BAAALgAECgEJAQAAAA==.Tyresh:BAAALgAECgEJAQAAAA==.Tyrinor:BAAALgADCgUJBQAAAA==.',
Ul='Ulogasm:BAAALgADCgkJCgAAAA==.',
Us='Usami:BAAALgAECgEJAQAAAA==.',
Ut='Utako:BAAALgADCgUJCgAAAA==.',
Uv='Uvari:BAAALgAECgYJDgAAAA==.',
Va='Vaclar:BAAALgAECgYJBgABLgAFFAQJCwAXAK8hAA==.Valhalaa:BAAALgADCgYJBgAAAA==.Valton:BAACLgAFFH8LAAIXAAQJryFICAB2AQAXAAQJryFICAB2AQAuAAQKf0AAAhcACQlTJqYEAD4DABcACQlTJqYEAD4DAAAA.Vanillanice:BAAALgAECgYJDgAAAA==.Varrfife:BAAALgAECgMJAwAAAA==.Vaxaldan:BAABLgAECn83AAIaAAkJLQ6pGgBtAQAaAAkJLQ6pGgBtAQAAAA==.',
Ve='Velithera:BAAALgADCgMJAwAAAA==.Vellithe:BAABLgAECn8WAAIKAAcJIQpDxgDiAAAKAAcJIQpDxgDiAAAAAA==.Venj:BAAALgAECgUJBgAAAA==.Verhmax:BAAALgADCgYJCwAAAA==.Vestrae:BAACLgAFFH8IAAMCAAQJ1gdBMQDcAAACAAQJ1gdBMQDcAAASAAEJSQFsSAAmAAAuAAQKfyQAAgIACAl+Hm8TAJoCAAIACAl+Hm8TAJoCAAAA.Vex:BAABLgAECn8XAAIIAAgJqhnyNwDtAQAIAAgJqhnyNwDtAQAAAA==.',
Vi='Vianel:BAAALgADCggJCAAAAA==.Vilten:BAAALgAECgQJCwAAAA==.',
Vo='Vodash:BAABLgAECn8hAAIWAAcJ3Rm1LADrAQAWAAcJ3Rm1LADrAQABLgAECgkJNQACAHIPAA==.Vostok:BAABLgAECn8eAAIIAAgJOBwTQgDJAQAIAAgJOBwTQgDJAQAAAA==.',
Wa='Wage:BAAALgADCgQJBQAAAA==.Warmth:BAAALgADCgIJAwAAAA==.',
We='Weekend:BAAALgADCgkJDwAAAA==.Wetsock:BAAALgAECgYJBwAAAA==.',
Wi='Wikket:BAABLgAECn83AAMSAAkJFRsLDAB/AgASAAkJFRsLDAB/AgACAAgJ3AN/bgDXAAAAAA==.',
Wo='Wolvesbayne:BAAALgAECgEJAQAAAA==.',
Wy='Wyelie:BAAALgAECgYJDQAAAA==.Wynono:BAAALgADCgcJBwAAAA==.',
Xd='Xdeadlysinz:BAAALgAECgcJDwAAAA==.',
Xo='Xotha:BAABLgAECn86AAIPAAkJqB6/EgCZAgAPAAkJqB6/EgCZAgAAAA==.',
Xu='Xuen:BAAALgAFFAEJAwAAAA==.',
Xy='Xythera:BAACLgAFFH8GAAIPAAMJARkYTwDdAAAPAAMJARkYTwDdAAAuAAQKfx8AAw8ACQmKIPYVANMCAA8ACQmKIPYVANMCACEAAQmwEIIuADIAAAAA.',
Ye='Yeah:BAAALgADCgYJBgABLgAFFAMJBwAKAEwMAA==.',
Yi='Yinosai:BAAALgAECgUJBwAAAA==.',
Yo='Yougot:BAAALgADCgcJCgAAAA==.',
Yu='Yuji:BAABLgAECn8hAAIJAAYJaR3uCQCJAQAJAAYJaR3uCQCJAQAAAA==.Yukì:BAAALgADCgMJAwAAAA==.Yurie:BAAALgAECgIJAgAAAA==.',
Yv='Yvonna:BAAALgADCgEJAQAAAA==.',
Za='Zaega:BAAALgADCgQJBAABLgAECggJJgAKAKEfAA==.Zahlee:BAAALgAECgQJBAAAAA==.Zalirina:BAAALgADCgIJAgAAAA==.Zanka:BAAALgAECgIJAgAAAA==.Zaridruid:BAAALgAECgkJCgAAAA==.Zarisedra:BAACLgAFFH8dAAMFAAYJBhnCCgDlAQAFAAYJBhnCCgDlAQAKAAEJXgDaOwA2AAAuAAQKfxgAAwUACQkwF8kpAOMBAAUACAkGGMkpAOMBAAoAAQktBuw9ATUAAAAA.Zarissena:BAAALgAECgMJAwAAAA==.Zarris:BAAALgADCgUJDAAAAA==.',
Ze='Zennith:BAAALgADCgMJAwAAAA==.Zernacho:BAABLgAECn8gAAQGAAkJjBrAGwDRAQAGAAYJJhzAGwDRAQAcAAcJ+hFBLgBvAQAmAAMJTROoSAC1AAAAAA==.Zerogasm:BAABLgAECn8YAAITAAkJAhZEKAAnAgATAAkJAhZEKAAnAgAAAA==.Zerolicious:BAAALgAECgMJAwAAAA==.Zerozaddy:BAAALgAECgUJBgAAAA==.Zevvo:BAABLgAECn8uAAIEAAkJECERCADNAgAEAAkJECERCADNAgAAAA==.',
Zi='Ziggysundust:BAAALgADCgMJAwAAAA==.',
Zo='Zoraji:BAABLgAECn86AAIgAAkJdhoxDQBQAgAgAAkJdhoxDQBQAgAAAA==.',
Zu='Zuganova:BAABLgAFFH8SAAMmAAUJDQhlHAA5AQAmAAUJ4QdlHAA5AQAGAAEJ8whwFgA8AAAAAA==.Zuggar:BAABLgAECn8fAAIEAAcJVwhxSgAFAQAEAAcJVwhxSgAFAQAAAA==.',
Zy='Zynhammer:BAABLgAECn8oAAMPAAgJgxFhXQCJAQAPAAgJgxFhXQCJAQANAAEJawZgagAmAAAAAA==.',
['Év']='Évangeline:BAAALgADCgcJBwAAAA==.',
['Ëb']='Ëbony:BAABLgAFFH8FAAITAAMJxxReTADpAAATAAMJxxReTADpAAAAAA==.',
['Ëd']='Ëdën:BAAALgAECgcJCwAAAA==.',
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
