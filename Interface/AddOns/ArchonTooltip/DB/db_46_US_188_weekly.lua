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

local lookup = {'Unknown-Unknown','Warrior-Protection','Warrior-Fury','Priest-Holy','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Paladin-Retribution','Druid-Restoration','Paladin-Holy','Monk-Brewmaster','Evoker-Devastation','Paladin-Protection','DemonHunter-Devourer','Rogue-Subtlety','Rogue-Assassination','Hunter-BeastMastery','Druid-Guardian','Shaman-Elemental','Shaman-Restoration','Mage-Frost','DeathKnight-Blood','Monk-Windwalker','Monk-Mistweaver','DemonHunter-Havoc','Priest-Shadow','Hunter-Survival','DeathKnight-Unholy','Druid-Feral','Druid-Balance','DemonHunter-Vengeance','DeathKnight-Frost','Mage-Arcane','Shaman-Enhancement','Evoker-Augmentation','Priest-Discipline','Rogue-Outlaw','Warrior-Arms',}
local provider = {region='US',realm='ShadowCouncil',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abear:BAAALgAECgQJBQAAAA==.Abrocklock:BAAALgAECgYJBwAAAA==.',
Ac='Achilês:BAAALgAECgEJAQABLgAECgYJCQABAAAAAA==.',
Ad='Adaluna:BAAALgAECggJCAAAAA==.Adorabull:BAABLgAECn8iAAMCAAkJECGzBACVAgACAAkJECGzBACVAgADAAEJ0AYRrwAsAAAAAA==.Adrain:BAAALgAECgQJCwAAAA==.Adwae:BAAALgAECgIJAgAAAA==.',
Ae='Aelyn:BAAALgAECgcJDwAAAA==.Aerendyl:BAAALgAECgEJAQAAAA==.Aevelee:BAAALgAECgUJBQAAAA==.Aevick:BAAALgAECgQJBQAAAA==.',
Al='Alastair:BAAALgADCgEJAQAAAA==.Aleeta:BAAALgADCggJFAAAAA==.Allucard:BAAALgAECgkJAQAAAA==.',
Am='Amapanda:BAAALgAECggJCAAAAA==.Amaria:BAAALgAECgMJBAABLgAECgcJEwABAAAAAA==.Amoracchius:BAAALgADCgMJAwAAAA==.',
An='Angelstörm:BAABLgAECn8oAAIEAAgJ3heYHgDrAQAEAAgJ3heYHgDrAQAAAA==.Anorili:BAAALgADCgYJBgAAAA==.Antarias:BAABLgAECn8UAAQFAAYJgiAICgBUAQAFAAUJDSMICgBUAQAGAAUJrBQcoQAWAQAHAAIJthqoLAA8AAAAAA==.Antarion:BAAALgAECgQJBAAAAA==.',
Ap='Applevendor:BAAALgADCgUJBQAAAA==.',
Ar='Arahil:BAAALgAECgQJBwAAAA==.Arcanio:BAAALgADCgQJBAAAAA==.Arcaux:BAAALgADCggJDgAAAA==.Arckenon:BAABLgAECn80AAIIAAkJViNXBQAeAwAIAAkJViNXBQAeAwAAAA==.',
As='Ashdorei:BAAALgADCgMJAwAAAA==.Ashog:BAAALgAECgYJDwAAAA==.Astranos:BAAALgAECgEJAQABLgAECggJJwAJADYPAA==.',
At='Athanyr:BAABLgAECn8pAAIJAAgJXyWyAwBaAwAJAAgJXyWyAwBaAwAAAA==.Atillis:BAAALgADCgYJDAAAAA==.',
Au='Augmentation:BAAALgAECgEJAQAAAA==.Austenpally:BAABLgAECn8XAAMKAAYJCRL5MgA5AQAKAAYJCRL5MgA5AQAIAAUJPBRTmwD1AAAAAA==.',
Aw='Awake:BAAALgAECgQJBAABLgAECgkJJQALAKQgAA==.',
Ax='Axeflack:BAAALgAECgEJAQAAAA==.Axegor:BAAALgADCgMJAwAAAA==.',
Ba='Bacuda:BAAALgAECgUJDQAAAA==.Balkris:BAAALgADCgkJCQABLgAECgYJFQAMAIkQAA==.Baratheon:BAAALgAECgkJEQAAAA==.',
Be='Beartooth:BAAALgADCgUJBQAAAA==.Beggles:BAAALgADCgEJAQAAAA==.Bereit:BAAALgADCgcJBgAAAA==.',
Bi='Biancadelrio:BAAALgAECgYJDQAAAA==.Bigboned:BAAALgADCgEJAQABLgAECgkJHgANAM0WAA==.Bigmode:BAAALgADCgYJBgAAAA==.',
Bj='Bjorrglbrgl:BAAALgAECgMJBAABLgAECgcJEAABAAAAAA==.',
Bl='Blackmask:BAAALgADCgUJCAAAAA==.Blindashunae:BAACLgAFFH8YAAIOAAYJJRKeFgB4AQAOAAYJJRKeFgB4AQAuAAQKfxYAAg4ACQlQHikVANgCAA4ACQlQHikVANgCAAAA.Blindkungfu:BAAALgAECgQJBAAAAA==.Bloodrun:BAAALgADCggJCAAAAA==.Blook:BAABLgAECn8UAAMPAAgJTRX3FACjAQAPAAgJTRX3FACjAQAQAAEJkgg2HwA3AAAAAA==.Bluehazey:BAAALgAECggJDwAAAA==.Bläz:BAAALgAECgEJAQAAAA==.',
Bo='Bootsy:BAAALgAECgcJBAAAAA==.Bopit:BAABLgAECn8UAAMIAAgJUA+nnwBAAQAIAAYJeA6nnwBAAQAKAAgJGA7JUAA2AQAAAA==.Botia:BAAALgAECgcJEwAAAA==.',
Br='Bruhh:BAAALgAECgYJBwAAAA==.Brunnera:BAAALgAECgIJAwAAAA==.Bruul:BAABLgAECn8YAAIIAAYJOxkabgBJAQAIAAYJOxkabgBJAQAAAA==.Brynjolf:BAAALgAECgUJCQAAAA==.',
Ca='Caenji:BAABLgAECn8WAAIRAAgJ2gtQVgBHAQARAAgJ2gtQVgBHAQAAAA==.Carcharoth:BAABLgAECn8iAAMHAAgJCBggCQBnAQAHAAYJAhogCQBnAQAGAAUJrg//rACnAAAAAA==.Carmelina:BAAALgAECgcJEgAAAA==.Catrixona:BAAALgAECgUJCAAAAA==.Caylan:BAAALgADCgQJBAAAAA==.',
Ch='Chadgar:BAAALgADCgIJAgAAAA==.Chaoscaster:BAAALgADCgkJCQABLgAECgYJBgABAAAAAA==.Chey:BAABLgAECn8wAAIPAAkJnyRUAQA2AwAPAAkJnyRUAQA2AwAAAA==.Chilai:BAABLgAECn8bAAISAAgJ2hbpDQCaAQASAAgJ2hbpDQCaAQAAAA==.Chipsahoy:BAABLgAECn8aAAMTAAgJ4x6fDQBEAgATAAgJ4x6fDQBEAgAUAAYJdRJ3RQBsAQAAAA==.Chrîstîan:BAAALgADCgUJBQAAAA==.Chíef:BAAALgAFFAMJAwABLgAFFAUJEwAVAKMaAA==.',
Ci='Cindrozetha:BAAALgADCgEJAQAAAA==.Ciphérdivine:BAAALgADCgUJBAAAAA==.',
Cl='Close:BAAALgADCgUJBQABLgAECgkJMAAWAGYiAA==.',
Co='Conciete:BAABLgAECn8VAAMXAAgJWhXmGgAHAgAXAAgJWhXmGgAHAgAYAAEJBAHidwARAAAAAA==.Conorix:BAAALgAECgUJCAAAAA==.Corvo:BAAALgAECgcJEgAAAA==.Counselor:BAAALgAECgUJCQAAAA==.Courallie:BAAALgADCgUJAwAAAA==.',
Cr='Crataxxis:BAABLgAECn8rAAIZAAgJ9RTnEwCQAQAZAAgJ9RTnEwCQAQAAAA==.Crynos:BAAALgADCgMJAwAAAA==.Crysandra:BAAALgAECgUJBQAAAA==.',
Cy='Cydon:BAABLgAECn8rAAISAAgJfh/QBABwAgASAAgJfh/QBABwAgAAAA==.',
Da='Daereth:BAAALgAECgYJCQAAAA==.Daerrith:BAAALgAECgUJCQAAAA==.Damienfox:BAAALgADCggJDwAAAA==.Dana:BAAALgAECgYJBgAAAA==.Danellia:BAAALgADCgUJBQAAAA==.Darkreaper:BAAALgAECgQJBAAAAA==.Darrwin:BAABLgAECn8eAAMIAAcJfR5mQAC/AQAIAAcJfR5mQAC/AQANAAMJlgx6KQB9AAAAAA==.Dawicker:BAAALgADCgYJDwAAAA==.Daylight:BAAALgAECgYJCQAAAA==.',
De='Defacto:BAAALgADCgMJAwAAAA==.Delat:BAAALgAECgEJAQAAAA==.Delrac:BAABLgAECn8aAAIOAAgJXQtJWAAvAQAOAAgJXQtJWAAvAQAAAA==.Demonalsa:BAAALgAECgEJAQABLgAECgUJBwABAAAAAA==.Denero:BAAALgAECggJEQAAAA==.Departure:BAAALgAECgQJBwABLgAECgYJFQAZAAIcAA==.Derith:BAAALgADCgEJAQAAAA==.',
Df='Dfabness:BAABLgAECn8dAAIXAAgJIxDHHAB5AQAXAAgJIxDHHAB5AQAAAA==.',
Di='Dic:BAAALgADCgIJAgABLgADCgMJAwABAAAAAA==.',
Do='Docbushed:BAAALgAECgEJAQABLgAFFAMJCQAGAM8DAA==.Dotbush:BAACLgAFFH8JAAMGAAMJzwOMXwC4AAAGAAMJzwOMXwC4AAAHAAEJhwJ0HQA4AAAuAAQKfy8ABAYACAnVFktAAA0CAAYACAngFUtAAA0CAAcAAwmrDIBGAJwAAAUAAgnOEU0YAIIAAAAA.Dotspot:BAAALgADCgQJBAABLgAECgMJBwABAAAAAA==.',
Dr='Dracthayr:BAABLgAECn83AAIMAAkJZBMKBAADAgAMAAkJZBMKBAADAgAAAA==.Dragonhammer:BAABLgAECn9BAAIIAAkJHyTWAwA4AwAIAAkJHyTWAwA4AwAAAA==.Drakanna:BAAALgAECgIJAgAAAA==.Draxela:BAAALgADCggJFAAAAA==.Dreaming:BAABLgAECn8wAAIWAAkJZiLXAwByAgAWAAkJZiLXAwByAgAAAA==.Drosidon:BAAALgAECgcJEwAAAA==.Drubo:BAAALgAECgEJAQAAAA==.',
Ea='Earsog:BAAALgADCgEJAQAAAA==.Earthenfist:BAAALgAECgEJAQAAAA==.',
Eb='Ebebebebe:BAAALgAECgEJAQAAAA==.',
Ef='Efbomb:BAAALgADCgcJBwAAAA==.',
Ei='Eitherindel:BAAALgADCggJCAAAAA==.',
El='Ellaini:BAABLgAECn8RAAIaAAcJCgzPKgApAQAaAAcJCgzPKgApAQAAAA==.Ellie:BAAALgAFFAEJAQABLgAFFAMJBgAKADcNAA==.Elseb:BAAALgAECgIJAwAAAA==.',
Em='Emotion:BAAALgADCgYJAQABLgAECgkJMAAWAGYiAA==.',
En='Enchantrêss:BAAALgADCgQJBAABLgAECgYJCQABAAAAAA==.',
Er='Erenara:BAAALgAECgQJCwAAAA==.',
Ev='Evic:BAABLgAECn8nAAIJAAgJNg+1NgB3AQAJAAgJNg+1NgB3AQAAAA==.',
Ew='Ewson:BAAALgADCgcJCwAAAA==.',
Ex='Excrubilis:BAAALgAFFAIJAwAAAA==.',
Fa='Faandango:BAAALgAECgUJBQAAAA==.Faeleader:BAAALgAECgYJEQAAAA==.Faevelina:BAAALgAECgUJDAABLgAECgcJCgABAAAAAA==.Faytadori:BAAALgADCgEJAQAAAA==.',
Fe='Felgrrl:BAAALgADCgkJIwAAAA==.Felsite:BAAALgAECgkJAQAAAA==.Feyreh:BAAALgAECgMJAwAAAA==.',
Fi='Fieona:BAAALgADCgYJCwAAAA==.Firethorns:BAAALgADCgMJAwAAAA==.Fistandilias:BAAALgADCgkJCQAAAA==.Fitzbang:BAAALgAECgUJBwAAAA==.',
Fl='Florigrowl:BAAALgADCggJFAAAAA==.',
Fo='Forever:BAAALgAECgMJBQABLgAECgkJMAAWAGYiAA==.Formortiis:BAAALgADCgEJAQAAAA==.Forrestior:BAABLgAECn8YAAIbAAgJoiShAQBBAwAbAAgJoiShAQBBAwAAAA==.Forsthoof:BAAALgADCgYJBgAAAA==.',
Fr='Fraga:BAAALgAECgYJDgABLgAFFAMJCAAcAEkNAA==.Frailty:BAAALgAECgUJBgAAAA==.Frique:BAAALgAECgQJBAAAAA==.Frostfingers:BAAALgADCggJDwAAAA==.Frostyfang:BAABLgAECn8cAAMdAAgJuRzODQB6AQAdAAYJZCDODQB6AQAeAAQJhBEPRQCjAAAAAA==.Frozenyogert:BAAALgAECgQJBAAAAA==.',
Fu='Fufula:BAAALgADCgQJBAAAAA==.Funkbot:BAAALgAECgYJDAAAAA==.',
['Fä']='Färshadow:BAAALgAECgEJAQAAAA==.',
Ga='Galbur:BAACLgAFFH8IAAIcAAMJSQ0zbwCWAAAcAAMJSQ0zbwCWAAAuAAQKfyQAAxwACAmcHlwpABYCABwACAlKHVwpABYCABYABwkyE8wXAJ0BAAAA.Galdrin:BAAALgAECgcJCgAAAA==.Gaspode:BAAALgADCgcJBwAAAA==.Gassann:BAAALgAECggJDgAAAA==.',
Ge='Geers:BAAALgAECgcJEwAAAA==.Geta:BAAALgAECgQJBwABLgAECgkJIAADAF0iAA==.Getacast:BAAALgAECgEJAQABLgAECgkJIAADAF0iAA==.Getademon:BAAALgADCgEJAQABLgAECgkJIAADAF0iAA==.Getaform:BAAALgAECgEJAQABLgAECgkJIAADAF0iAA==.Getaheal:BAAALgAECgYJBgABLgAECgkJIAADAF0iAA==.Getalife:BAAALgADCgQJBAABLgAECgkJIAADAF0iAA==.Getarage:BAABLgAECn8gAAIDAAkJXSIeFACtAgADAAkJXSIeFACtAgAAAA==.',
Gh='Ghil:BAABLgAECn8mAAMFAAgJXiJHAgBXAgAFAAgJXiJHAgBXAgAGAAQJnxXfvADfAAAAAA==.',
Gi='Gigawatt:BAABLgAECn8jAAMTAAgJVxFxIgB+AQATAAgJVxFxIgB+AQAUAAIJEgz/iABSAAAAAA==.Gildersleeve:BAAALgAECgQJBwAAAA==.Gilia:BAAALgADCgkJLAAAAA==.Girthfist:BAABLgAECn8WAAILAAgJRSMIBQA5AwALAAgJRSMIBQA5AwABLgAFFAcJGAACAEYdAA==.',
Gl='Glynixtwo:BAAALgAECgIJAgAAAA==.',
Go='Goldiwarlock:BAAALgADCgYJCgAAAA==.Goloron:BAAALgADCgkJDwAAAA==.',
Gr='Graymayn:BAAALgAECgYJEAAAAA==.Gremel:BAAALgAECgYJEgAAAA==.Grimmist:BAABLgAECn8hAAIYAAcJiRj8HgClAQAYAAcJiRj8HgClAQAAAA==.',
Gu='Guloot:BAABLgAECn8bAAMUAAgJAgbaXgDWAAAUAAgJAgbaXgDWAAATAAUJtQYnXwBpAAAAAA==.Gunboyten:BAAALgAECgIJAgAAAA==.Gunderthirth:BAACLgAFFH8YAAICAAcJRh0aAgD3AQACAAcJRh0aAgD3AQAuAAQKfx4AAgIACQnKI6IBAGsDAAIACQnKI6IBAGsDAAAA.Gurkin:BAAALgADCgEJAQAAAA==.',
Gw='Gwaeniiha:BAABLgAECn8eAAIIAAcJFAyyeQAxAQAIAAcJFAyyeQAxAQAAAA==.Gward:BAAALgAECgUJBgAAAA==.Gwizz:BAABLgAECn8jAAIVAAgJKxxYMAAXAgAVAAgJKxxYMAAXAgAAAA==.',
Ha='Halinka:BAAALgADCgYJBgAAAA==.Handsoap:BAABLgAECn8XAAIZAAcJlBC5HAAvAQAZAAcJlBC5HAAvAQAAAA==.Haquar:BAAALgADCggJFAAAAA==.Hardhitter:BAAALgAECgEJAwAAAA==.',
He='Hehe:BAAALgADCgQJBAAAAA==.Hellumph:BAABLgAECn8bAAIfAAYJ/BtPCQCEAQAfAAYJ/BtPCQCEAQAAAA==.Hermesconrad:BAAALgAECgEJAgAAAA==.Hevensrath:BAABLgAECn8uAAIIAAgJ2xz9IwAvAgAIAAgJ2xz9IwAvAgAAAA==.',
Ho='Hokuden:BAABLgAECn83AAIgAAkJGhkCBAAnAgAgAAkJGhkCBAAnAgAAAA==.Honina:BAAALgADCgIJAgAAAA==.Hornswaggles:BAAALgAECgQJBAAAAA==.Horsebananas:BAABLgAECn8iAAMRAAgJTBkYRACfAQARAAcJGRkYRACfAQAbAAcJeBezHQBkAQAAAA==.',
Ht='Htari:BAAALgAECgEJAQAAAA==.',
Hu='Huddington:BAABLgAECn8ZAAIhAAgJVBfaAgDRAQAhAAgJVBfaAgDRAQAAAA==.Hussh:BAAALgAECgYJDAABLgAECgkJHgANAM0WAA==.',
Hy='Hydraness:BAAALgAECgEJAQABLgAECgQJBAABAAAAAA==.',
['Hø']='Hørse:BAAALgAECgEJAQABLgAECggJIgARAEwZAA==.',
Ia='Iamcammy:BAAALgAECgYJEAAAAA==.',
Il='Illexi:BAAALgADCgYJBgAAAA==.',
Im='Imariz:BAAALgAECgcJBwAAAA==.Imdarkness:BAAALgAECgYJCQAAAA==.Impquisitor:BAAALgAECgYJBwAAAA==.',
In='Indecent:BAABLgAECn8tAAQGAAgJqRv/HQA1AgAGAAgJqRv/HQA1AgAHAAYJHBd3FACnAQAFAAMJ3hQLGAC7AAAAAA==.Indeed:BAAALgAECgEJAQAAAA==.Inibble:BAAALgADCgEJAQAAAA==.',
Is='Ishy:BAAALgAECgUJCAAAAA==.',
Ix='Ixelle:BAAALgADCgUJDQABLgAECgQJCwABAAAAAA==.',
Iz='Izomar:BAABLgAECn8bAAIVAAgJKxh7OgDvAQAVAAgJKxh7OgDvAQAAAA==.',
Ja='Jackieechan:BAAALgAECgMJAwABLgAFFAMJCQAKAJAmAA==.Jackiemays:BAACLgAFFH8JAAMKAAMJkCaSEQBRAQAKAAMJkCaSEQBRAQAIAAEJsQE9fQA9AAAuAAQKfzAAAwoACAkUJDIIAMcCAAoACAkUJDIIAMcCAAgACAlgGnY9AC8CAAAA.Jaded:BAAALgADCgYJBgAAAA==.Jaleigha:BAAALgADCgYJBgAAAA==.Jamesin:BAAALgAECgEJAgAAAA==.',
Je='Jedaii:BAAALgAECgYJBgAAAA==.Jeff:BAAALgAECgEJAwAAAA==.Jeses:BAABLgAECn8pAAIIAAgJvhVURQCvAQAIAAgJvhVURQCvAQAAAA==.',
Jo='Jollah:BAAALgAECgUJBgAAAA==.',
Ju='Jutic:BAABLgAECn83AAIUAAkJsiLCAwA7AwAUAAkJsiLCAwA7AwAAAA==.',
Jy='Jyssa:BAAALgADCgEJAQAAAA==.',
['Jö']='Jörmun:BAAALgAECgEJAQAAAA==.',
Ka='Kaia:BAABLgAECn8kAAIPAAgJzhBkFACpAQAPAAgJzhBkFACpAQAAAA==.Kaldrich:BAAALgADCgYJBgAAAA==.Kamoto:BAAALgADCgkJHwABLgAECggJIwATAFcRAA==.Kanetsu:BAAALgADCgIJAgAAAA==.Kardas:BAAALgAECggJEwAAAA==.Kardio:BAABLgAECn8ZAAMXAAgJqQ2tKwCBAQAXAAgJqQ2tKwCBAQAYAAEJAQpQZwA1AAAAAA==.Kayrina:BAAALgADCggJCAAAAA==.Kazeer:BAAALgAECgcJEAAAAA==.',
Kb='Kbilly:BAABLgAECn8uAAIUAAkJ1SEfAwBOAwAUAAkJ1SEfAwBOAwAAAA==.',
Ke='Kegger:BAAALgAECgEJAQAAAA==.Keylerin:BAACLgAFFH8XAAIPAAUJ9yVeBQCoAQAPAAUJ9yVeBQCoAQAuAAQKfyAAAg8ACQnWGUgTAH4CAA8ACQnWGUgTAH4CAAAA.',
Ki='Kibbik:BAACLgAFFH8IAAIaAAMJmQQeGgDFAAAaAAMJmQQeGgDFAAAuAAQKfyoAAhoACAmNFCodAIcBABoACAmNFCodAIcBAAAA.Kija:BAAALgAECgYJBgAAAA==.Kitsunami:BAAALgAECgcJBgAAAA==.',
Kl='Klepal:BAAALgADCggJCAAAAA==.Klutchshield:BAAALgAECgEJAQAAAA==.',
Kn='Kneecap:BAAALgAECgQJBAAAAA==.',
Ko='Kobe:BAAALgAECgYJDwAAAA==.Koharu:BAAALgADCgcJEgAAAA==.Kookykg:BAAALgAECgEJAQAAAA==.',
Kr='Krampus:BAABLgAECn8uAAIiAAgJahRvCQDDAQAiAAgJahRvCQDDAQAAAA==.Kranok:BAAALgAECgUJDQAAAA==.Krim:BAAALgADCgUJBgAAAA==.Krimdevourer:BAAALgADCgYJBgAAAA==.Krimhuntress:BAAALgAECgEJAgAAAA==.',
Ku='Kunac:BAAALgAECgUJBgAAAA==.',
Ky='Kynessa:BAAALgAECgQJCwAAAA==.Kyrun:BAABLgAECn8kAAIiAAgJsArVDgBTAQAiAAgJsArVDgBTAQAAAA==.',
['Kã']='Kãne:BAABLgAECn8kAAMjAAkJhREFHwCRAQAjAAkJhREFHwCRAQAMAAIJvQaaOABUAAAAAA==.',
La='Lamoran:BAAALgADCgkJDwAAAA==.Lannes:BAAALgADCgEJAQAAAA==.Lapz:BAAALgAECgUJBQAAAA==.Lavetra:BAAALgAECgMJBAAAAA==.Lazerdinger:BAAALgAECgEJAQAAAA==.',
Le='Legendary:BAACLgAFFH8IAAINAAIJ0h1LCQCOAAANAAIJ0h1LCQCOAAAuAAQKfxQAAg0ACQlbIMQDANcCAA0ACQlbIMQDANcCAAAA.',
Lh='Lhani:BAABLgAECn8hAAIEAAcJvQ9tJwBDAQAEAAcJvQ9tJwBDAQAAAA==.',
Li='Liadrin:BAABLgAECn8eAAINAAkJzRZ0DwDNAQANAAkJzRZ0DwDNAQAAAA==.Lie:BAABLgAECn8VAAIMAAYJiRBHCwAgAQAMAAYJiRBHCwAgAQAAAA==.Liliana:BAAALgADCgkJKwAAAA==.',
Ll='Llyrael:BAABLgAECn8UAAMEAAYJXg1YLgATAQAEAAYJXg1YLgATAQAaAAIJxAMIbAAlAAAAAA==.',
Lo='Lolineverdie:BAABLgAECn8ZAAMJAAkJdQoDTAAYAQAJAAkJdQoDTAAYAQAeAAYJnQL6TwB1AAAAAA==.',
Lu='Lucilline:BAAALgAFFAIJAgAAAA==.Luna:BAABLgAECn8iAAMEAAgJEQrzLQCNAQAEAAgJEQrzLQCNAQAaAAgJ1gf0KAA0AQAAAA==.',
Ly='Lyrev:BAAALgAECgYJDgAAAA==.',
['Ló']='Lórien:BAAALgADCgIJAgAAAA==.',
Ma='Macaoidh:BAAALgAECgYJBgAAAA==.Maddeleine:BAAALgAECgYJDgAAAA==.Magicdemon:BAABLgAECn8uAAMOAAgJziKzEgBuAgAOAAgJnSCzEgBuAgAZAAQJpSS0KgBwAQAAAA==.Magichunter:BAAALgAECgEJAQABLgAECggJLgAOAM4iAA==.Makall:BAAALgADCgEJAQAAAA==.Malaah:BAABLgAECn8qAAITAAkJrRS3HACoAQATAAkJrRS3HACoAQAAAA==.Malafar:BAAALgAECgUJBQAAAA==.Malatrixx:BAAALgAECgEJAQAAAA==.Maldiriel:BAAALgAECggJCAAAAA==.Mallikus:BAAALgADCggJCAAAAA==.Manofsecks:BAAALgAECgQJCgAAAA==.Mapachote:BAAALgAECgYJEgAAAA==.Marodin:BAAALgADCgkJLQAAAA==.Marthaiden:BAAALgAECggJDAAAAA==.Maryjaina:BAAALgADCgYJBgAAAA==.Mavastus:BAAALgADCgcJBwAAAA==.Mazozul:BAABLgAECn8kAAMkAAgJphNiFgDNAQAkAAgJXxBiFgDNAQAEAAQJ1hR6PAC2AAAAAA==.',
Me='Meatbaal:BAAALgADCgYJCAAAAA==.Melinaria:BAABLgAECn8jAAMaAAgJihP9HACJAQAaAAgJihP9HACJAQAkAAEJ6gE/YAAhAAAAAA==.Melisondraa:BAAALgADCgkJCQAAAA==.Meow:BAAALgADCgQJBAAAAA==.Merkala:BAAALgADCgYJCQAAAA==.Metalbot:BAAALgADCgkJCQAAAA==.',
Mi='Miarose:BAAALgAECgUJBgAAAA==.Miggydogg:BAAALgAECgUJCwAAAA==.Mileta:BAAALgAECgUJEQAAAA==.Mimic:BAAALgAECgIJAgAAAA==.Minthammer:BAAALgAECgIJBAAAAA==.Mirthias:BAAALgAECgMJAwAAAA==.',
Mo='Monki:BAAALgAECgUJCgAAAA==.Moozohar:BAAALgADCgEJAQAAAA==.Morgorra:BAAALgAECgMJBwAAAA==.Morvila:BAAALgAECgMJAwAAAA==.Mote:BAABLgAECn8ZAAMkAAgJfxPVHgB8AQAkAAYJmRTVHgB8AQAaAAgJOwwLJABVAQAAAA==.',
Mu='Muertes:BAAALgAECgEJAQAAAA==.Multidollar:BAAALgADCgUJBQAAAA==.Muminah:BAAALgAECgMJBQAAAA==.',
['Mô']='Môlly:BAACLgAFFH8IAAIEAAMJJSGuDQAZAQAEAAMJJSGuDQAZAQAuAAQKfykAAgQACAlfIpUFAPYCAAQACAlfIpUFAPYCAAAA.',
Na='Narnluz:BAABLgAECn8cAAIEAAgJfRdjEAAdAgAEAAgJfRdjEAAdAgAAAA==.Nazor:BAABLgAECn8nAAIOAAgJ1hnRKwDSAQAOAAgJ1hnRKwDSAQAAAA==.',
Ne='Necronic:BAAALgADCgYJCwAAAA==.Necroreign:BAABLgAECn81AAIZAAkJtxipCQA1AgAZAAkJtxipCQA1AgAAAA==.Neith:BAAALgADCgMJAwAAAA==.Nemera:BAAALgADCgYJCAAAAA==.Nervous:BAAALgAECgcJDAABLgAECgkJMAAWAGYiAA==.Nessee:BAAALgAECgQJDAAAAA==.',
Ni='Niall:BAABLgAECn8vAAIdAAkJRiF+AQD1AgAdAAkJRiF+AQD1AgAAAA==.Nilithis:BAABLgAECn8rAAMGAAkJeRkxHABAAgAGAAkJCxkxHABAAgAHAAQJGxOBFwCwAAAAAA==.Niú:BAAALgADCgYJBgAAAA==.',
No='Norsehammer:BAABLgAECn8UAAITAAcJpgnCQwA6AQATAAcJpgnCQwA6AQAAAA==.Nozmua:BAAALgADCgkJDgAAAA==.',
Ny='Nyghtchyld:BAAALgAECgYJEAAAAA==.Nyxlumina:BAAALgAECgEJAQAAAA==.',
['Né']='Néssima:BAABLgAECn8bAAMIAAgJ0xe8WAB6AQAIAAgJWg+8WAB6AQANAAUJYhuaIwDrAAAAAA==.',
Oa='Oak:BAAALgAECgEJAwAAAA==.Oathfinder:BAAALgAECgcJEAAAAA==.',
Oc='Occurrence:BAABLgAECn8VAAMJAAgJ2QUGaAC5AAAJAAcJBwQGaAC5AAAeAAEJZwJseAAeAAAAAA==.Octalexane:BAAALgAECgUJBgAAAA==.',
On='Onimusha:BAAALgAECgMJAwAAAA==.',
Or='Ortalbem:BAABLgAECn81AAIVAAkJ+CJwCQADAwAVAAkJ+CJwCQADAwAAAA==.',
Ov='Ovi:BAAALgADCgIJAgAAAA==.',
Pa='Pandariee:BAAALgAECggJDgAAAA==.Pangsh:BAAALgAFFAEJAQAAAA==.Parzval:BAAALgAECgEJAQAAAA==.Paxgor:BAAALgADCgUJAQAAAA==.',
Pe='Pendaemonia:BAABLgAECn82AAIZAAkJuRaTCgAhAgAZAAkJuRaTCgAhAgAAAA==.Penelopie:BAAALgADCgYJBgAAAA==.',
Ph='Pherix:BAAALgAECgUJEQAAAA==.Phiirys:BAAALgAECgEJAQAAAA==.',
Pi='Picaso:BAAALgADCgEJAQAAAA==.',
Po='Poomacha:BAABLgAECn8iAAIRAAYJjhWhWQA+AQARAAYJjhWhWQA+AQAAAA==.',
Pu='Puffthemagic:BAAALgADCgYJCAAAAA==.',
Py='Pyree:BAABLgAECn8gAAMjAAgJ1BFzJgBaAQAjAAgJHhFzJgBaAQAMAAcJZgntFABzAAAAAA==.',
['Pø']='Pøë:BAAALgAECgkJEwABLgAFFAIJAgABAAAAAA==.',
Qu='Qu:BAAALgAECgcJEAAAAQ==.',
Qv='Qveemcorkie:BAAALgAECgEJAQAAAA==.',
['Qí']='Qín:BAAALgADCgUJAwAAAA==.',
Ra='Radagust:BAAALgAECgQJBAAAAA==.Raenne:BAAALgAECgIJAwAAAA==.Ragebait:BAAALgADCgIJAgAAAA==.Rainfall:BAAALgAECgEJAgAAAA==.Raistlain:BAAALgAECgYJDwAAAA==.Raitha:BAAALgADCgUJCAAAAA==.Ralli:BAABLgAECn8jAAIOAAgJVBcgMQC5AQAOAAgJVBcgMQC5AQAAAA==.Rallsdemon:BAAALgAECgQJBAAAAA==.Rallsdk:BAAALgAECgIJAgABLgAECgQJBAABAAAAAA==.Rallsodins:BAAALgAECgEJAQABLgAECgQJBAABAAAAAA==.Randomguy:BAABLgAECn80AAIPAAkJdSUoAQBBAwAPAAkJdSUoAQBBAwAAAA==.Ranulf:BAAALgAECgIJAgAAAA==.Ratava:BAAALgAECgMJAwAAAA==.Ratboy:BAEALgAECgEJAQABLgAECggJJwAkANoiAA==.Ratrot:BAAALgAECgYJEgAAAA==.Razenath:BAAALgADCgUJBQAAAA==.',
Re='Rekrella:BAAALgADCgUJBQAAAA==.Reldarus:BAEBLgAECn8nAAMkAAgJ2iKzAwAjAwAkAAgJ2iKzAwAjAwAEAAQJ+hr8RAAlAQAAAA==.Rena:BAAALgADCgcJBwAAAA==.Rendia:BAAALgADCgMJAwAAAA==.Renik:BAAALgADCgIJAQAAAA==.Revennek:BAAALgAECgUJBgAAAA==.Reverence:BAABLgAECn8YAAIIAAgJsgvtZABdAQAIAAgJsgvtZABdAQAAAA==.Revilation:BAABLgAECn8cAAINAAkJYBP7DACeAQANAAkJYBP7DACeAQAAAA==.Rezjyk:BAAALgAECgEJAgABLgAECgcJHwAIAOYZAA==.Rezzyk:BAABLgAECn8fAAIIAAcJ5hnUSwCcAQAIAAcJ5hnUSwCcAQAAAA==.',
Rh='Rhonus:BAAALgAECgEJAQAAAA==.Rhyxali:BAAALgAECgUJCwAAAA==.',
Ri='Riis:BAAALgAECgQJCAAAAA==.Riiselock:BAABLgAECn8tAAMGAAgJIR5CNwAvAgAGAAcJyR1CNwAvAgAHAAQJFBwpEQDmAAAAAA==.Riktade:BAAALgADCgYJBgAAAA==.Rilight:BAAALgADCgYJBgABLgAECggJEQABAAAAAA==.Riptidepod:BAABLgAECn8bAAMUAAcJhgfhUAAKAQAUAAcJhgfhUAAKAQATAAIJ3gK0iQAdAAAAAA==.',
Ro='Robbiebrews:BAAALgADCgUJBQAAAA==.Rowin:BAAALgADCgUJBQAAAA==.',
Ry='Rynley:BAABLgAECn8WAAMPAAUJASEKJwDAAQAPAAUJASEKJwDAAQAlAAIJWRHBEgBzAAAAAA==.',
Sa='Sacredscales:BAABLgAECn8hAAMEAAkJtR5kCwCaAgAEAAcJ3yRkCwCaAgAaAAcJtRSGKgCGAQAAAA==.Sagerremeseb:BAAALgADCggJFAAAAA==.Sakii:BAABLgAECn8ZAAIOAAgJfAyaWQArAQAOAAgJfAyaWQArAQAAAA==.Salera:BAAALgADCgQJBAAAAA==.Samvimes:BAABLgAECn8iAAIIAAgJXw8LUgCLAQAIAAgJXw8LUgCLAQAAAA==.Sangreene:BAABLgAECn8bAAIaAAgJRxqFEwBYAgAaAAgJRxqFEwBYAgAAAA==.Sargis:BAABLgAECn84AAMIAAkJgiENBwAFAwAIAAkJgiENBwAFAwAKAAgJyBvJEQA+AgAAAA==.Sarial:BAAALgADCgMJAwAAAA==.',
Sc='Schrödinger:BAAALgAECgYJDwABLgAECgcJEgABAAAAAA==.Sciblasts:BAAALgADCgEJAQABLgADCgkJDAABAAAAAA==.Scott:BAACLgAFFH8gAAIOAAYJRST5AgAVAgAOAAYJRST5AgAVAgAuAAQKfzgAAg4ACQmMJnUAAO4DAA4ACQmMJnUAAO4DAAAA.Scratchh:BAABLgAECn8dAAILAAgJlAstNgB0AQALAAgJlAstNgB0AQAAAA==.',
Se='Searalsa:BAAALgAECgUJBwAAAA==.Sentis:BAABLgAECn8aAAIeAAYJOQjsPQDBAAAeAAYJOQjsPQDBAAAAAA==.',
Sh='Shadowbrooks:BAAALgAECgIJAgAAAA==.Shadowgiver:BAAALgADCgcJDwAAAA==.Shadowsdemon:BAAALgADCgEJAQAAAA==.Shadowsworn:BAAALgAECgEJAQAAAA==.Shagol:BAAALgAECgQJBwAAAA==.Shalriss:BAABLgAECn8gAAIaAAcJ5BhgGgCgAQAaAAcJ5BhgGgCgAQAAAA==.Shamemoon:BAABLgAECn8YAAIOAAcJCxfqRABsAQAOAAcJCxfqRABsAQAAAA==.Shamunroe:BAABLgAECn8gAAMUAAgJoAcOTAAdAQAUAAgJoAcOTAAdAQATAAQJKhGwWgDZAAAAAA==.Shatterhoof:BAABLgAECn8bAAIdAAYJqgvMFwDvAAAdAAYJqgvMFwDvAAAAAA==.Shelle:BAAALgAECgIJAwAAAA==.Shiftys:BAAALgADCgUJCgABLgAECgMJBQABAAAAAA==.Shingra:BAACLgAFFH8XAAIjAAUJJBjiFABHAQAjAAUJJBjiFABHAQAuAAQKfx4AAiMACQlvHOIPAHkCACMACQlvHOIPAHkCAAAA.Shoof:BAAALgADCgUJBQAAAA==.',
Si='Sifû:BAAALgADCgcJDgAAAA==.Sigourney:BAAALgAECgUJBQABLgAECggJIgARAEwZAA==.Silversho:BAAALgAECgIJAgAAAA==.Silvoid:BAAALgADCgMJAwAAAA==.Silvren:BAABLgAECn8dAAMDAAcJQRUdKwBcAQADAAcJQRUdKwBcAQAmAAEJvwZoRgArAAAAAA==.Sindarion:BAAALgAECgUJBQAAAA==.Sinz:BAAALgAECgEJBQAAAA==.Siph:BAAALgAECgEJAQAAAA==.',
Sk='Skillidan:BAABLgAECn8iAAIJAAgJZRu2FABeAgAJAAgJZRu2FABeAgAAAA==.',
Sl='Slighttrash:BAAALgAECgYJEgAAAA==.Sloppy:BAAALgADCggJCAAAAA==.',
Sm='Smacka:BAAALgAECgEJAQAAAA==.Smallcrow:BAACLgAFFH8XAAIXAAYJQB25AAACAgAXAAYJQB25AAACAgAuAAQKfxUAAhcABwkuJsQHAP8CABcABwkuJsQHAP8CAAAA.Smøke:BAAALgAECgMJAwAAAA==.',
Sn='Snallygaster:BAAALgADCgYJDAABLgAECggJHgASAAwcAA==.Snowsong:BAAALgAECgEJAQAAAA==.',
Sp='Spectrose:BAAALgADCgEJAQAAAA==.Spirit:BAAALgAECgEJAQAAAA==.Spiro:BAAALgAFFAIJAgAAAA==.',
St='Starge:BAAALgAECgQJBgAAAA==.Starre:BAAALgADCgQJBAAAAA==.Steffey:BAABLgAECn8bAAIUAAYJswpCWADuAAAUAAYJswpCWADuAAAAAA==.Straven:BAAALgAECgcJEAAAAA==.Sturgeson:BAACLgAFFH8XAAICAAUJGRqkCQA5AQACAAUJGRqkCQA5AQAuAAQKfx8AAgIACQlkHQcMAEsCAAIACQlkHQcMAEsCAAAA.',
Su='Sulwen:BAABLgAECn8qAAIEAAkJJBcmEgAGAgAEAAkJJBcmEgAGAgAAAA==.',
Sw='Sweetpotato:BAAALgADCgEJAQAAAA==.Swiftfeet:BAABLgAECn8gAAIRAAgJQBRsPACaAQARAAgJQBRsPACaAQAAAA==.',
Sy='Syrasia:BAAALgADCgUJBQAAAA==.Syselea:BAAALgADCgEJAQAAAA==.',
['Sö']='Söranin:BAAALgAECgUJDwAAAA==.',
Ta='Tachichan:BAAALgAECgYJBgAAAA==.Tadum:BAAALgADCgEJAQAAAA==.Taeili:BAABLgAECn8WAAMeAAgJ1hVoNgBiAQAeAAgJ1hVoNgBiAQASAAEJjhUcPgA7AAAAAA==.Talisse:BAAALgADCgYJBgAAAA==.Tanequil:BAACLgAFFH8GAAIJAAMJCgKyPQB+AAAJAAMJCgKyPQB+AAAuAAQKfyMAAgkACAmsDNdKAHgBAAkACAmsDNdKAHgBAAAA.Targaryian:BAAALgAECgMJAwAAAA==.Taylea:BAABLgAECn8VAAIVAAcJpA8IhgAxAQAVAAcJpA8IhgAxAQABLgAECgcJHgAIAH0eAA==.',
Te='Techromancer:BAAALgAECgUJBQABLgAECgUJEQABAAAAAA==.Tem:BAAALgADCgMJAwAAAA==.Tenumbras:BAAALgAECgYJDAAAAA==.Termonda:BAAALgAECgEJAQAAAA==.Terraclaw:BAAALgADCgUJBwAAAA==.Terrasia:BAAALgADCgYJBgAAAA==.Terrigino:BAAALgAECgEJAQAAAA==.',
Th='Thanatias:BAABLgAECn8UAAIWAAcJ9hQfFQBPAQAWAAcJ9hQfFQBPAQAAAA==.Thantasia:BAAALgAECgYJDwAAAA==.Thauras:BAAALgADCgcJDgAAAA==.Theeslan:BAAALgAECgkJCQAAAA==.Thom:BAACLgAFFH8GAAIgAAMJNRPgCADgAAAgAAMJNRPgCADgAAAuAAQKfykAAyAACAmuI+cAABwDACAACAmuI+cAABwDABwABgmoDjmxACABAAAA.Thør:BAAALgADCgcJDgAAAA==.',
Ti='Tifà:BAAALgAECgUJCAAAAA==.Timothy:BAABLgAECn8XAAIZAAgJkhfoEgCcAQAZAAgJkhfoEgCcAQAAAA==.Tinkphooey:BAAALgAECgYJCwAAAA==.Tinton:BAAALgADCgEJAQAAAA==.',
To='Tormmok:BAAALgAECgYJDAAAAA==.Toshindo:BAAALgADCgQJBAAAAA==.',
Tr='Trashpally:BAAALgAECgEJAgAAAA==.Tremèndor:BAAALgADCgMJAwAAAA==.Trey:BAAALgAECgEJAQAAAA==.Tristra:BAAALgAECgQJBAAAAA==.',
Ts='Tsuruga:BAABLgAECn8uAAILAAgJEg9VIABnAQALAAgJEg9VIABnAQAAAA==.',
Tu='Turkwise:BAABLgAECn8lAAMSAAgJJBe8CwC9AQASAAgJJBe8CwC9AQAdAAQJCBGsHgDuAAAAAA==.',
Ty='Tycondrius:BAAALgAECgEJAQAAAA==.Tyresh:BAAALgAECgEJAQAAAA==.Tyrinor:BAAALgADCgUJBQAAAA==.',
Ul='Ulogasm:BAAALgADCggJCAAAAA==.',
Us='Usami:BAAALgAECgEJAQAAAA==.',
Ut='Utako:BAAALgADCgUJCgAAAA==.',
Uv='Uvari:BAAALgAECgIJAgAAAA==.',
Va='Valhalaa:BAAALgADCgYJBgAAAA==.Valton:BAACLgAFFH8HAAIXAAMJbx57DQAaAQAXAAMJbx57DQAaAQAuAAQKfzgAAhcACAmIJvoCAAYDABcACAmIJvoCAAYDAAAA.Vanillanice:BAAALgAECgUJCAAAAA==.Varrfife:BAAALgAECgMJAwAAAA==.Vaxaldan:BAABLgAECn8uAAIWAAgJNQ8gGgAeAQAWAAgJNQ8gGgAeAQAAAA==.',
Ve='Velithera:BAAALgADCgMJAwAAAA==.Vellithe:BAABLgAECn8WAAIIAAcJIAohoADtAAAIAAcJIAohoADtAAAAAA==.Venj:BAAALgAECgUJBgAAAA==.Verhmax:BAAALgADCgYJCwAAAA==.Vestrae:BAACLgAFFH8GAAMJAAMJzQWSNAChAAAJAAMJzQWSNAChAAAeAAEJSQHeNgAuAAAuAAQKfyQAAgkACAl+Hm8TAJoCAAkACAl+Hm8TAJoCAAAA.Vex:BAABLgAECn8UAAIGAAYJ9BruTgBxAQAGAAYJ9BruTgBxAQAAAA==.',
Vi='Vianel:BAAALgADCggJCAAAAA==.Vilten:BAAALgAECgQJCwAAAA==.',
Vo='Vodash:BAABLgAECn8aAAIUAAcJOhmHIgDpAQAUAAcJOhmHIgDpAQABLgAECggJJwAJADYPAA==.Vostok:BAABLgAECn8aAAIGAAgJNhznPwAOAgAGAAgJNhznPwAOAgAAAA==.',
Wa='Wage:BAAALgADCgQJBQAAAA==.Warmth:BAAALgADCgIJAwAAAA==.',
We='Weekend:BAAALgADCgkJDwAAAA==.Wetsock:BAAALgAECgYJBwAAAA==.',
Wi='Wikket:BAABLgAECn8uAAMeAAgJthrlEQD5AQAeAAgJthrlEQD5AQAJAAgJ3AM9XgDYAAAAAA==.',
Wy='Wyelie:BAAALgAECgYJBwAAAA==.Wynono:BAAALgADCgcJBwAAAA==.',
Xd='Xdeadlysinz:BAAALgAECgcJCQAAAA==.',
Xo='Xotha:BAABLgAECn8xAAIOAAgJTx4MGwAwAgAOAAgJTx4MGwAwAgAAAA==.',
Xu='Xuen:BAAALgAFFAEJAgAAAA==.',
Xy='Xythera:BAACLgAFFH8GAAIOAAMJARmOOgDwAAAOAAMJARmOOgDwAAAuAAQKfx8AAw4ACQmJIPYVANMCAA4ACQmJIPYVANMCAB8AAQmwEDYlADIAAAAA.',
Ye='Yeah:BAAALgADCgYJBgABLgAECgkJMgANAOUiAA==.',
Yi='Yinosai:BAAALgAECgIJAgAAAA==.',
Yo='Yougot:BAAALgADCgcJCgAAAA==.',
Yu='Yuji:BAABLgAECn8hAAIHAAYJaR0RBwCYAQAHAAYJaR0RBwCYAQAAAA==.Yukì:BAAALgADCgMJAwAAAA==.Yurie:BAAALgAECgIJAgAAAA==.',
Yv='Yvonna:BAAALgADCgEJAQAAAA==.',
Za='Zaega:BAAALgADCgQJBAABLgAECgcJHgAIAH0eAA==.Zahlee:BAAALgAECgQJBAAAAA==.Zalirina:BAAALgADCgIJAgAAAA==.Zanka:BAAALgAECgIJAgAAAA==.Zaridruid:BAAALgAECgkJCgAAAA==.Zarisedra:BAACLgAFFH8XAAMKAAUJNxozCgCsAQAKAAUJNxozCgCsAQAIAAEJXgDaOwA2AAAuAAQKfxgAAwoACQkwF8kpAOMBAAoACAkGGMkpAOMBAAgAAQktBuw9ATUAAAAA.Zarissena:BAAALgAECgMJAwAAAA==.Zarris:BAAALgADCgUJDAAAAA==.',
Ze='Zennith:BAAALgADCgMJAwAAAA==.Zernacho:BAABLgAECn8bAAQEAAgJPBtqFQDfAQAEAAYJJRxqFQDfAQAaAAYJ5xFBLgBvAQAkAAIJbhL9RQBwAAAAAA==.Zerogasm:BAAALgAECggJEAAAAA==.Zerolicious:BAAALgADCgUJBgAAAA==.Zerozaddy:BAAALgAECgUJBgAAAA==.Zevvo:BAABLgAECn8tAAIDAAgJmiFpCACZAgADAAgJmiFpCACZAgAAAA==.',
Zo='Zoraji:BAABLgAECn83AAILAAkJxBmQCgBSAgALAAkJxBmQCgBSAgAAAA==.',
Zu='Zuganova:BAABLgAFFH8SAAMkAAUJDQgaEwBUAQAkAAUJ4QcaEwBUAQAEAAEJ8whwFgA8AAAAAA==.Zuggar:BAABLgAECn8fAAIDAAcJVwieOwAIAQADAAcJVwieOwAIAQAAAA==.',
Zy='Zynhammer:BAABLgAECn8kAAMOAAgJghFhXQCJAQAOAAgJghFhXQCJAQAZAAEJawbTTwAtAAAAAA==.',
['Év']='Évangeline:BAAALgADCgcJBwAAAA==.',
['Ëb']='Ëbony:BAAALgAFFAEJAgAAAA==.',
['Ëd']='Ëdën:BAAALgAECgcJCgAAAA==.',
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
