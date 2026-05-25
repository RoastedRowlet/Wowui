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

local lookup = {'Unknown-Unknown','Warrior-Protection','Warrior-Fury','Paladin-Holy','Priest-Holy','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Paladin-Retribution','Druid-Restoration','Monk-Brewmaster','Evoker-Devastation','Paladin-Protection','DemonHunter-Devourer','Rogue-Subtlety','Rogue-Assassination','Druid-Balance','Hunter-BeastMastery','DemonHunter-Havoc','Druid-Guardian','Shaman-Elemental','Shaman-Restoration','Mage-Frost','Monk-Windwalker','Monk-Mistweaver','Shaman-Enhancement','DeathKnight-Blood','DeathKnight-Unholy','Priest-Shadow','Hunter-Survival','Druid-Feral','DemonHunter-Vengeance','DeathKnight-Frost','Mage-Arcane','Hunter-Marksmanship','Evoker-Augmentation','Priest-Discipline','Rogue-Outlaw','Warrior-Arms',}
local provider = {region='US',realm='ShadowCouncil',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abear:BAAALgAECgQJBQAAAA==.Abrocklock:BAAALgAECgYJBwAAAA==.',
Ac='Achilês:BAAALgAECgEJAQABLgAECgYJCgABAAAAAA==.',
Ad='Adaluna:BAAALgAECgkJEAAAAA==.Adorabull:BAABLgAECn8lAAMCAAkJ1SGRBAC9AgACAAkJ1SGRBAC9AgADAAEJ0AYRrwAsAAAAAA==.Adrain:BAAALgAECgQJCwAAAA==.Adwae:BAAALgAECgIJAgAAAA==.',
Ae='Aelyn:BAAALgAECgcJDwAAAA==.Aerendyl:BAAALgAECgEJAQAAAA==.Aevelee:BAAALgAECgUJBQAAAA==.Aevick:BAAALgAECgQJBQAAAA==.',
Al='Alastair:BAAALgADCgEJAQAAAA==.Aleeta:BAAALgAECgEJAQAAAA==.Allucard:BAAALgAECgkJAgAAAA==.',
Am='Amapanda:BAAALgAECgkJCQAAAA==.Amaria:BAAALgAECgMJBAABLgAECggJFQAEAAQcAA==.Amoracchius:BAAALgADCgMJAwAAAA==.',
An='Angelstörm:BAABLgAECn8zAAIFAAgJ3heYHgDrAQAFAAgJ3heYHgDrAQAAAA==.Anorili:BAAALgADCgYJBgAAAA==.Antarias:BAABLgAECn8YAAQGAAYJgiAWDgBEAQAGAAUJDSMWDgBEAQAHAAUJrBQcoQAWAQAIAAIJtho3MgA8AAAAAA==.Antarion:BAAALgAECgQJBAAAAA==.',
Ap='Applevendor:BAAALgADCgUJBQAAAA==.',
Ar='Arahil:BAAALgAECgQJBwAAAA==.Arcanio:BAAALgADCgQJBAAAAA==.Arcaux:BAAALgADCggJDgAAAA==.Arckenon:BAABLgAECn89AAIJAAkJiCNxBwAZAwAJAAkJiCNxBwAZAwAAAA==.',
As='Ashdorei:BAAALgADCgMJAwAAAA==.Ashog:BAAALgAECgYJEgAAAA==.Astranos:BAAALgAECgEJAQABLgAECggJLgAKADUQAA==.',
At='Athanyr:BAABLgAECn8qAAIKAAgJXyWlBABZAwAKAAgJXyWlBABZAwAAAA==.Atillis:BAAALgADCgYJDAAAAA==.',
Au='Augmentation:BAAALgAECgEJAQAAAA==.Austenpally:BAABLgAECn8dAAMEAAYJORKsOQA6AQAEAAYJORKsOQA6AQAJAAUJdBd4oQAUAQAAAA==.',
Av='Aveycado:BAAALgADCgMJAQAAAA==.',
Aw='Awake:BAAALgAECgQJBAABLgAECgkJLAALAE8hAA==.',
Ax='Axeflack:BAAALgAECgEJAQAAAA==.Axegor:BAAALgADCgMJAwAAAA==.',
Ba='Bacuda:BAAALgAECgUJDQAAAA==.Balkris:BAAALgAECgEJAQABLgAECggJGgAMAI8PAA==.Baratheon:BAAALgAECgkJEQAAAA==.',
Be='Beartooth:BAAALgADCgUJBQAAAA==.Beggles:BAAALgADCgEJAQAAAA==.Bereit:BAAALgADCgcJBgAAAA==.',
Bi='Biancadelrio:BAAALgAECgYJEwAAAA==.Bigboned:BAAALgADCgEJAQABLgAECgkJHgANAM0WAA==.Bigmode:BAAALgADCgYJBgAAAA==.',
Bj='Bjorrglbrgl:BAAALgAECgMJBQABLgAFFAIJAwABAAAAAA==.',
Bl='Blackmask:BAAALgADCgUJCAAAAA==.Bladekrim:BAAALgAECgEJAQAAAA==.Blindashunae:BAACLgAFFH8aAAIOAAYJnhIUHgBzAQAOAAYJnhIUHgBzAQAuAAQKfxYAAg4ACQlQHikVANgCAA4ACQlQHikVANgCAAAA.Blindkungfu:BAAALgAECgQJBAAAAA==.Bloodrun:BAAALgADCggJCAAAAA==.Blook:BAABLgAECn8UAAMPAAgJThWUGgCaAQAPAAgJThWUGgCaAQAQAAEJkgg2HwA3AAAAAA==.Bluehazey:BAAALgAECgkJEQAAAA==.Blueleader:BAAALgAECgQJBAAAAA==.Bläz:BAAALgAECgEJAQAAAA==.',
Bo='Boomhammer:BAAALgAFFAIJBAAAAA==.Bootsy:BAAALgAECgcJBAAAAA==.Bopit:BAABLgAECn8UAAMJAAgJUQ+nnwBAAQAJAAYJeA6nnwBAAQAEAAgJGQ7JUAA2AQAAAA==.Botia:BAABLgAECn8UAAIRAAYJiwTwUACZAAARAAYJiwTwUACZAAAAAA==.',
Br='Bruhh:BAAALgAECgYJBwAAAA==.Brunnera:BAAALgAECgIJAwAAAA==.Bruul:BAABLgAECn8bAAMJAAcJKxYwcQBsAQAJAAcJKxYwcQBsAQANAAEJ1RBpQwAvAAAAAA==.Brynjolf:BAAALgAECgUJCQAAAA==.',
Ca='Caenji:BAABLgAECn8WAAISAAgJ2gu7ZwBFAQASAAgJ2gu7ZwBFAQAAAA==.Carcharoth:BAABLgAECn8kAAMIAAgJ7xlQBwCyAQAIAAcJNRpQBwCyAQAHAAUJrg/lvgDbAAAAAA==.Carmelina:BAABLgAECn8YAAITAAcJBhsOEQDkAQATAAcJBhsOEQDkAQAAAA==.Catrixona:BAAALgAECgUJCAAAAA==.Caylan:BAAALgADCgQJBAAAAA==.',
Ch='Chadgar:BAAALgADCgIJAgAAAA==.Chaoscaster:BAAALgADCgkJCQABLgAECgYJBgABAAAAAA==.Charroth:BAAALgAECgYJCAAAAA==.Chey:BAABLgAECn8xAAIPAAkJ1iTSAQA0AwAPAAkJ1iTSAQA0AwAAAA==.Chilai:BAABLgAECn8lAAIUAAkJABjsCAAiAgAUAAkJABjsCAAiAgAAAA==.Chipsahoy:BAABLgAECn8fAAMVAAgJUx/pDgBbAgAVAAgJUx/pDgBbAgAWAAYJdRJ3RQBsAQAAAA==.Chrîstîan:BAAALgADCgYJBgAAAA==.Chíef:BAABLgAFFH8HAAMWAAQJ7ga4LgDxAAAWAAQJ7ga4LgDxAAAVAAIJNwNoOQBmAAABLgAFFAUJEwAXAKMaAA==.',
Ci='Cindrozetha:BAAALgADCgEJAQAAAA==.Ciphérdivine:BAAALgADCgUJBAAAAA==.Citte:BAAALgAECgEJAQABLgAECgUJBQABAAAAAA==.',
Cl='Close:BAAALgADCgUJBQABLgAFFAIJAgABAAAAAA==.',
Co='Conciete:BAABLgAECn8VAAMYAAgJWhXmGgAHAgAYAAgJWhXmGgAHAgAZAAEJBAHidwARAAAAAA==.Conorix:BAAALgAECgUJCAAAAA==.Corvo:BAABLgAECn8UAAINAAgJyxeRDADPAQANAAgJyxeRDADPAQAAAA==.Counselor:BAAALgAECgUJCQAAAA==.Courallie:BAAALgAECgEJAQAAAA==.',
Cr='Crataxxis:BAABLgAECn8wAAITAAgJnhhaDgAKAgATAAgJnhhaDgAKAgAAAA==.Crynos:BAAALgADCgMJAwAAAA==.Crysandra:BAAALgAECgUJBQAAAA==.',
Cy='Cydon:BAABLgAECn8xAAIUAAgJlx/6BQBxAgAUAAgJlx/6BQBxAgAAAA==.',
Da='Daereth:BAAALgAECgYJCQAAAA==.Daerrith:BAAALgAECgUJCQAAAA==.Damienfox:BAAALgAECgEJAQAAAA==.Dana:BAAALgAECgYJDAABLgAFFAMJDwAKABIUAA==.Danellia:BAAALgADCgUJBQAAAA==.Darkreaper:BAAALgAECgQJBAAAAA==.Darrwin:BAABLgAECn8jAAMJAAgJnR4AMgAXAgAJAAgJnR4AMgAXAgANAAQJnw3dJwCqAAAAAA==.Dawicker:BAAALgADCgYJDwAAAA==.Daylight:BAAALgAECgYJCQAAAA==.',
De='Dedoria:BAAALgADCgUJBQAAAA==.Defacto:BAAALgADCgMJAwAAAA==.Delat:BAAALgAECgEJAQAAAA==.Delrac:BAABLgAECn8iAAIOAAgJWxEHSgCGAQAOAAgJWxEHSgCGAQAAAA==.Demonalsa:BAAALgAECgEJAQABLgAFFAMJCAAaANMIAA==.Denero:BAABLgAECn8aAAIJAAkJIx6UEwCyAgAJAAkJIx6UEwCyAgAAAA==.Departure:BAAALgAECgQJBwABLgAECgYJFQATAAIcAA==.Derith:BAAALgADCgEJAQAAAA==.',
Df='Dfabness:BAABLgAECn8gAAIYAAkJShBlHACiAQAYAAkJShBlHACiAQAAAA==.',
Di='Dic:BAAALgADCgIJAgABLgAECgMJAwABAAAAAA==.',
Do='Docbushed:BAAALgAECgQJBAABLgAFFAQJDQAHAN0EAA==.Dotbush:BAACLgAFFH8NAAMHAAQJ3QRSVADyAAAHAAQJ3QRSVADyAAAIAAEJhwIbIgA4AAAuAAQKfy8ABAcACAnXFktAAA0CAAcACAniFUtAAA0CAAgAAwmrDIBGAJwAAAYAAgnOESofAH8AAAAA.Dotspot:BAAALgADCgQJBAABLgAECgMJBwABAAAAAA==.',
Dr='Dracthayr:BAABLgAECn86AAIMAAkJZRMOBQD1AQAMAAkJZRMOBQD1AQAAAA==.Dragonhammer:BAACLgAFFH8HAAIJAAIJHx9JXAC6AAAJAAIJHx9JXAC6AAAuAAQKf0sAAgkACQl/JJUEAEIDAAkACQl/JJUEAEIDAAAA.Drakanna:BAAALgAECgIJAgAAAA==.Draxela:BAAALgAECgQJBQAAAA==.Dreaming:BAABLgAECn8wAAIbAAkJZiISBQC7AgAbAAkJZiISBQC7AgABLgAFFAIJAgABAAAAAA==.Drosidon:BAABLgAECn8UAAIcAAYJnAXN1ACzAAAcAAYJnAXN1ACzAAAAAA==.Drubo:BAAALgAECgEJAQAAAA==.',
Ea='Earsog:BAAALgADCgEJAQAAAA==.Earthenfist:BAAALgAECgEJAQAAAA==.',
Eb='Ebebebebe:BAAALgAECgEJAQAAAA==.',
Ef='Efbomb:BAAALgADCgcJBwAAAA==.',
Ei='Eitherindel:BAAALgADCggJCAAAAA==.',
El='Elanore:BAAALgADCgIJAQAAAA==.Ellaini:BAABLgAECn8RAAIdAAcJCgyrMgAnAQAdAAcJCgyrMgAnAQAAAA==.Ellie:BAAALgAFFAMJBAAAAA==.Elseb:BAAALgAECgQJBwAAAA==.',
Em='Emotion:BAAALgADCgYJAQABLgAFFAIJAgABAAAAAA==.',
En='Enchantrêss:BAAALgADCgQJBAABLgAECgYJCgABAAAAAA==.',
Er='Erenara:BAAALgAECgQJCwAAAA==.',
Ev='Evic:BAABLgAECn8uAAIKAAgJNRB+OgCJAQAKAAgJNRB+OgCJAQAAAA==.',
Ew='Ewson:BAAALgADCgcJCwAAAA==.',
Ex='Excrubilis:BAAALgAFFAIJBAAAAA==.',
Fa='Faandango:BAAALgAECgUJBQAAAA==.Faeleader:BAABLgAECn8XAAIKAAYJBRDZUwAeAQAKAAYJBRDZUwAeAQAAAA==.Faevelina:BAAALgAECgUJDAABLgAECgcJCgABAAAAAA==.Faytadori:BAAALgADCgEJAQAAAA==.',
Fe='Felgrrl:BAAALgADCgkJJgAAAA==.Felsite:BAAALgAECgkJAQAAAA==.Feyreh:BAAALgAECgUJAwAAAA==.',
Fi='Fieona:BAAALgADCgYJCwAAAA==.Firethorns:BAAALgADCgMJAwAAAA==.Fistandilias:BAAALgADCgkJCQAAAA==.Fitzbang:BAAALgAECgUJBwAAAA==.',
Fl='Florigrowl:BAAALgADCggJFAAAAA==.',
Fo='Forever:BAAALgAECgMJBQABLgAFFAIJAgABAAAAAA==.Formortiis:BAAALgADCgEJAQAAAA==.Forrestior:BAABLgAECn8YAAIeAAgJoiShAQBBAwAeAAgJoiShAQBBAwAAAA==.Forsthoof:BAAALgADCgYJBgAAAA==.',
Fr='Fraga:BAAALgAECgYJDgABLgAFFAQJCwAcAJkMAA==.Frailty:BAAALgAECgUJCgAAAA==.Frique:BAAALgAECgUJCQAAAA==.Frostfingers:BAAALgAECgIJAgAAAA==.Frostyfang:BAABLgAECn8kAAMfAAgJ/xy6DgCVAQAfAAYJpCC6DgCVAQARAAQJthN6RwC8AAAAAA==.Frozenyogert:BAAALgAECgQJBAAAAA==.',
Fu='Fufula:BAAALgADCgQJBAAAAA==.Funkbot:BAAALgAECgYJDAAAAA==.',
['Fä']='Färshadow:BAAALgAECgEJAQAAAA==.',
Ga='Galbur:BAACLgAFFH8LAAIcAAQJmQzhWAAdAQAcAAQJmQzhWAAdAQAuAAQKfyQAAxwACAmhHoMyABECABwACAlPHYMyABECABsABwkyE8wXAJ0BAAAA.Galdrin:BAAALgAECgcJCgAAAA==.Gaspode:BAAALgADCgcJBwAAAA==.Gassann:BAAALgAECggJDgAAAA==.',
Ge='Geers:BAABLgAECn8dAAIXAAkJ2SIhCgAUAwAXAAkJ2SIhCgAUAwAAAA==.Geta:BAAALgAECgQJBwABLgAECgkJIAADAF0iAA==.Getacast:BAAALgAECgEJAQABLgAECgkJIAADAF0iAA==.Getademon:BAAALgADCgEJAQABLgAECgkJIAADAF0iAA==.Getaform:BAAALgAECgEJAQABLgAECgkJIAADAF0iAA==.Getaheal:BAAALgAECgYJBgABLgAECgkJIAADAF0iAA==.Getalife:BAAALgADCgQJBAABLgAECgkJIAADAF0iAA==.Getarage:BAABLgAECn8gAAIDAAkJXSIeFACtAgADAAkJXSIeFACtAgAAAA==.',
Gh='Ghil:BAABLgAECn8vAAMGAAkJqiONAAAdAwAGAAkJqiONAAAdAwAHAAQJnxXfvADfAAAAAA==.',
Gi='Gigawatt:BAABLgAECn8mAAMVAAkJ/xOLKQB3AQAVAAgJYRGLKQB3AQAWAAMJWgk7iwB+AAAAAA==.Gildersleeve:BAAALgAECgQJCAAAAA==.Gilia:BAAALgADCgkJLwAAAA==.Girthfist:BAABLgAECn8WAAILAAgJRSMIBQA5AwALAAgJRSMIBQA5AwABLgAFFAcJGAACAEkdAA==.',
Gl='Glynixtwo:BAAALgAECgMJBQAAAA==.',
Go='Goldiwarlock:BAAALgADCgcJCwAAAA==.Goloron:BAAALgADCgkJDwAAAA==.',
Gr='Graymayn:BAABLgAECn8WAAIeAAYJbh0kGgCvAQAeAAYJbh0kGgCvAQAAAA==.Gremel:BAABLgAECn8YAAMfAAYJoB3+FQAvAQAfAAUJWBj+FQAvAQARAAIJShs6TwCfAAAAAA==.Grimflaps:BAAALgAECgIJAgAAAA==.Grimmist:BAABLgAECn8hAAIZAAcJihgzJgCpAQAZAAcJihgzJgCpAQAAAA==.',
Gu='Guloot:BAABLgAECn8bAAMWAAgJBAZSbwDUAAAWAAgJBAZSbwDUAAAVAAUJtQZZbgBlAAAAAA==.Gunboyten:BAAALgAECgIJAgAAAA==.Gunderthirth:BAACLgAFFH8YAAICAAcJSR08AQDnAQACAAcJSR08AQDnAQAuAAQKfyYAAgIACQnKI6IBAGsDAAIACQnKI6IBAGsDAAAA.Gurkin:BAAALgADCgEJAQAAAA==.',
Gw='Gwaeniiha:BAABLgAECn8lAAIJAAgJFA2XbgBxAQAJAAgJFA2XbgBxAQAAAA==.Gward:BAAALgAECgUJBgAAAA==.Gwizz:BAABLgAECn8qAAIXAAkJcBs+JgBmAgAXAAkJcBs+JgBmAgAAAA==.',
Ha='Halibard:BAABLgAFFH8GAAIFAAMJuwgnGwCxAAAFAAMJuwgnGwCxAAAAAA==.Halinka:BAAALgADCgYJBgAAAA==.Handsoap:BAABLgAECn8ZAAITAAgJZw/jHABYAQATAAgJZw/jHABYAQAAAA==.Haquar:BAAALgAECgEJAQAAAA==.Hardhitter:BAAALgAECgUJCgAAAA==.',
He='Hehe:BAAALgADCgQJBAAAAA==.Helldog:BAAALgAECgMJAwABLgAECgYJIQAgAB0hAA==.Hellumph:BAABLgAECn8hAAIgAAYJHSGbBwDbAQAgAAYJHSGbBwDbAQAAAA==.Hermesconrad:BAAALgAECgEJAgAAAA==.Hevensrath:BAABLgAECn83AAIJAAkJ7R5+EgC5AgAJAAkJ7R5+EgC5AgAAAA==.',
Ho='Hokuden:BAABLgAECn86AAIhAAkJGhnMBQASAgAhAAkJGhnMBQASAgAAAA==.Honina:BAAALgADCgIJAgAAAA==.Hornswaggles:BAAALgAECgQJBAAAAA==.Horsebananas:BAABLgAECn8qAAMeAAgJpRp8GgCsAQAeAAcJlxl8GgCsAQASAAcJ+xkYRACfAQAAAA==.',
Ht='Htari:BAAALgAECgEJAQAAAA==.',
Hu='Huddington:BAABLgAECn8hAAIiAAgJSRkbAwDcAQAiAAgJSRkbAwDcAQAAAA==.Hussh:BAAALgAECgYJDAABLgAECgkJHgANAM0WAA==.',
Hy='Hydraness:BAAALgAECgEJAQABLgAECgQJBAABAAAAAA==.',
['Hø']='Hørse:BAAALgAECgEJAQABLgAECggJKgAeAKUaAA==.',
Ia='Iamcammy:BAAALgAECgYJEAAAAA==.',
Ig='Igknight:BAAALgAECgMJAwABLgAECgcJEwABAAAAAA==.',
Il='Illexi:BAAALgADCgYJBgAAAA==.',
Im='Imariz:BAAALgAECgcJBwAAAA==.Imdarkness:BAAALgAECgYJCgAAAA==.Impquisitor:BAAALgAECgYJBwAAAA==.',
In='Indecent:BAABLgAECn8xAAQHAAkJHh2oEQCoAgAHAAkJHh2oEQCoAgAIAAYJHBd3FACnAQAGAAMJ3hQLGAC7AAAAAA==.Indeed:BAAALgAECgUJBgAAAA==.Inibble:BAAALgADCgcJBgAAAA==.',
Is='Ishy:BAAALgAECgUJCAAAAA==.',
Ix='Ixelle:BAAALgADCgUJDQABLgAECgQJDwABAAAAAA==.',
Iz='Izomar:BAABLgAECn8gAAIXAAgJahmwPwACAgAXAAgJahmwPwACAgAAAA==.',
Ja='Jackieechan:BAAALgAECgMJAwABLgAFFAQJDQAEAEAmAA==.Jackiemays:BAACLgAFFH8NAAMEAAQJQCZRCwC6AQAEAAQJQCZRCwC6AQAJAAEJsQEdlQA6AAAuAAQKfzAAAwQACAkUJOcKALsCAAQACAkUJOcKALsCAAkACAlgGnY9AC8CAAAA.Jaded:BAAALgADCgYJBgAAAA==.Jaleigha:BAAALgADCgYJBwAAAA==.Jamesin:BAAALgAECgYJCAAAAA==.',
Je='Jedaii:BAAALgAECgYJBgAAAA==.Jeff:BAAALgAECgEJAwAAAA==.Jeses:BAABLgAECn8vAAIJAAkJQhb1MQAXAgAJAAkJQhb1MQAXAgAAAA==.',
Jo='Jollah:BAAALgAECgUJBgAAAA==.',
Ju='Jutic:BAABLgAECn86AAIWAAkJziJXBQA3AwAWAAkJziJXBQA3AwAAAA==.',
Jy='Jyssa:BAAALgADCgEJAQAAAA==.',
['Jö']='Jörmun:BAAALgAFFAIJBAAAAA==.',
Ka='Kaia:BAABLgAECn8lAAIPAAkJgA8kEwDmAQAPAAkJgA8kEwDmAQAAAA==.Kaldrich:BAAALgADCgYJBgAAAA==.Kamoto:BAAALgAECgQJBAABLgAECgkJJgAVAP8TAA==.Kanetsu:BAAALgADCgIJAgAAAA==.Kardas:BAABLgAECn8VAAMSAAgJmQfCbwAzAQASAAgJmQfCbwAzAQAjAAMJ1AGLfABSAAAAAA==.Kardio:BAABLgAECn8ZAAMYAAgJqQ2tKwCBAQAYAAgJqQ2tKwCBAQAZAAEJAQpQZwA1AAAAAA==.Kayj:BAAALgADCgYJBgAAAA==.Kayrina:BAAALgADCggJCAAAAA==.Kazeer:BAAALgAECgcJEQAAAA==.',
Kb='Kbilly:BAABLgAECn8zAAIWAAkJ1SGvBABFAwAWAAkJ1SGvBABFAwAAAA==.',
Ke='Kegger:BAAALgAECgEJAQAAAA==.Keylerin:BAACLgAFFH8aAAIPAAUJ9yWJCgCJAQAPAAUJ9yWJCgCJAQAuAAQKfyEAAg8ACQmAGkgTAH4CAA8ACQmAGkgTAH4CAAAA.',
Ki='Kibbik:BAACLgAFFH8LAAIdAAQJEgYwGAADAQAdAAQJEgYwGAADAQAuAAQKfyoAAh0ACAmNFC8cAPsBAB0ACAmNFC8cAPsBAAAA.Kija:BAAALgAECgYJBgAAAA==.Kitsunami:BAAALgAECgcJBgAAAA==.',
Kl='Klepal:BAAALgADCggJCAAAAA==.Klutchshield:BAAALgAECgEJAQAAAA==.',
Kn='Kneecap:BAAALgAECgUJCQAAAA==.Knottes:BAAALgAECgEJAQAAAA==.',
Ko='Kobe:BAAALgAECgYJDwAAAA==.Koharu:BAAALgADCgcJEwAAAA==.Kookykg:BAAALgAECgEJAQAAAA==.',
Kr='Krampus:BAABLgAECn83AAIaAAkJExQQCAAUAgAaAAkJExQQCAAUAgAAAA==.Kranok:BAAALgAECgYJDgAAAA==.Krim:BAAALgADCgUJBgAAAA==.Krimdevourer:BAAALgADCgYJBgAAAA==.Krimhuntress:BAAALgAECgEJAgAAAA==.',
Ku='Kunac:BAAALgAECgYJDAAAAA==.',
Ky='Kynessa:BAAALgAECgQJDwAAAA==.Kyrun:BAABLgAECn8oAAIaAAkJ5ws9DgCUAQAaAAkJ5ws9DgCUAQAAAA==.',
['Kã']='Kãne:BAACLgAFFH8GAAIkAAIJgwT/RgBtAAAkAAIJgwT/RgBtAAAuAAQKfyQAAyQACQmFEb0jAJsBACQACQmFEb0jAJsBAAwAAgm9Bpo4AFQAAAAA.',
La='Lamoran:BAAALgADCgkJDwAAAA==.Lannes:BAAALgADCgEJAQAAAA==.Lapz:BAAALgAECgkJDgAAAA==.Lavetra:BAAALgAECgMJBAAAAA==.Lazerdinger:BAAALgAECgEJAQAAAA==.',
Le='Legendary:BAACLgAFFH8IAAINAAIJ0h2fCwCIAAANAAIJ0h2fCwCIAAAuAAQKfxQAAg0ACQlbIMQDANcCAA0ACQlbIMQDANcCAAAA.Lethran:BAAALgAECgMJAwAAAA==.',
Lh='Lhani:BAABLgAECn8jAAIFAAgJrRM+HAC/AQAFAAgJrRM+HAC/AQAAAA==.',
Li='Liadrin:BAABLgAECn8eAAINAAkJzRZ0DwDNAQANAAkJzRZ0DwDNAQAAAA==.Lie:BAABLgAECn8aAAIMAAgJjw9WCACLAQAMAAgJjw9WCACLAQAAAA==.Liliana:BAAALgADCgkJMgAAAA==.',
Ll='Llyrael:BAABLgAECn8aAAMFAAYJWA6tMgAZAQAFAAYJWA6tMgAZAQAdAAIJxANSegAlAAAAAA==.',
Lo='Lolineverdie:BAABLgAECn8aAAMKAAkJ4go7UQAnAQAKAAkJ4go7UQAnAQARAAYJnQIvXABwAAAAAA==.',
Lu='Luna:BAABLgAECn8iAAMFAAgJEQrzLQCNAQAFAAgJEQrzLQCNAQAdAAgJ1Qe6LgA8AQAAAA==.',
Ly='Lyrev:BAAALgAECgYJEwAAAA==.',
['Ló']='Lórien:BAAALgADCgIJAgAAAA==.',
Ma='Macaoidh:BAAALgAECgYJBgAAAA==.Maddeleine:BAAALgAECgYJEAAAAA==.Magicdemon:BAABLgAECn81AAMTAAkJrCXuBgCbAgATAAkJeSXuBgCbAgAOAAgJnSDZFwBqAgAAAA==.Magichunter:BAAALgAECgEJAQABLgAECgkJNQATAKwlAA==.Makall:BAAALgADCgEJAQAAAA==.Malaah:BAABLgAECn8qAAIVAAkJrRRkIwCeAQAVAAkJrRRkIwCeAQAAAA==.Malafar:BAAALgAFFAEJAQAAAA==.Malatrixx:BAAALgAECgEJAQAAAA==.Maldiriel:BAAALgAECggJCAAAAA==.Mallikus:BAAALgADCggJCAAAAA==.Manofsecks:BAAALgAECgQJDAAAAA==.Mapachote:BAABLgAECn8fAAIjAAcJcRehCQCzAQAjAAcJcRehCQCzAQAAAA==.Marodin:BAAALgADCgkJMAAAAA==.Marthaiden:BAAALgAECgkJDgAAAA==.Maryjaina:BAAALgADCgYJBgAAAA==.Mavastus:BAAALgADCgcJBwAAAA==.Mazozul:BAABLgAECn8rAAMlAAkJCxUsFQADAgAlAAgJKRMsFQADAgAFAAUJ/BS0OADzAAAAAA==.',
Me='Meatbaal:BAAALgADCgYJCAAAAA==.Melinaria:BAABLgAECn8lAAMdAAgJfxTsHwCeAQAdAAgJfxTsHwCeAQAlAAEJ6gEqbgAhAAAAAA==.Melisondraa:BAAALgADCgkJCQAAAA==.Meow:BAAALgADCgQJBAAAAA==.Merkala:BAAALgADCgYJCQAAAA==.Metalbot:BAAALgADCgkJCQAAAA==.',
Mi='Miarose:BAAALgAECgUJBgAAAA==.Miggydogg:BAAALgAECgUJCwAAAA==.Mileta:BAABLgAECn8XAAIRAAYJBRk0JgBsAQARAAYJBRk0JgBsAQAAAA==.Mimic:BAAALgAECgIJAgAAAA==.Minthammer:BAAALgAECgIJBAABLgAFFAIJBAABAAAAAA==.Mirthias:BAAALgAECgMJAwAAAA==.',
Mo='Monki:BAAALgAECgYJDwAAAA==.Moozohar:BAAALgADCgEJAQAAAA==.Morgorra:BAAALgAECgMJBwAAAA==.Morvila:BAAALgAECgMJAwAAAA==.Mote:BAABLgAECn8cAAMlAAgJyxNRJAB9AQAlAAYJABVRJAB9AQAdAAgJyw1ZJwBqAQAAAA==.',
Mu='Muertes:BAAALgAECgEJAQAAAA==.Multidollar:BAAALgADCgUJBQABLgAECgkJQQASAC0hAA==.Muminah:BAAALgAECgMJBgAAAA==.',
['Mô']='Môlly:BAACLgAFFH8MAAIFAAQJ4BxyCwBaAQAFAAQJ4BxyCwBaAQAuAAQKfykAAgUACAlfIpUFAPYCAAUACAlfIpUFAPYCAAAA.',
Na='Narnluz:BAABLgAECn8dAAIFAAgJfBcRFAARAgAFAAgJfBcRFAARAgAAAA==.Nazor:BAABLgAECn8nAAIOAAgJ1xlSNQDRAQAOAAgJ1xlSNQDRAQAAAA==.',
Ne='Necronic:BAAALgADCgYJCwAAAA==.Necroreign:BAABLgAECn8+AAITAAkJ+BlCCgBTAgATAAkJ+BlCCgBTAgAAAA==.Neith:BAAALgADCgMJAwAAAA==.Nemera:BAAALgADCgYJCAAAAA==.Nervous:BAAALgAFFAIJAgAAAA==.Nessee:BAAALgAECgQJEAAAAA==.',
Ni='Niall:BAABLgAECn8yAAIfAAkJ3CHtAQD6AgAfAAkJ3CHtAQD6AgAAAA==.Nilithis:BAABLgAECn8rAAMHAAkJeRnDIwA3AgAHAAkJCxnDIwA3AgAIAAQJGxOFGwCpAAAAAA==.Niú:BAAALgADCgYJBgAAAA==.',
No='Norsehammer:BAABLgAECn8UAAIVAAcJpgnCQwA6AQAVAAcJpgnCQwA6AQABLgAFFAIJBAABAAAAAA==.Nozmua:BAAALgADCgkJDgAAAA==.',
Ny='Nyghtchyld:BAAALgAECgYJEAAAAA==.Nyxlumina:BAAALgAECgEJAQAAAA==.',
['Né']='Néssima:BAABLgAECn8dAAMJAAgJ0xdkagB6AQAJAAgJWg9kagB6AQANAAUJYhuaIwDrAAAAAA==.',
Oa='Oak:BAAALgAECgEJBAAAAA==.Oathfinder:BAAALgAECgcJEAAAAA==.',
Oc='Occurrence:BAABLgAECn8VAAMKAAgJ2gXUcwC5AAAKAAcJBwTUcwC5AAARAAEJZwJ8iAAeAAAAAA==.Octalexane:BAAALgAECgUJBgAAAA==.',
On='Onebuttonman:BAAALgADCgYJBgAAAA==.Onimusha:BAAALgAECgMJAwAAAA==.',
Or='Ortalbem:BAABLgAECn86AAIXAAkJFyNXDAAAAwAXAAkJFyNXDAAAAwAAAA==.',
Ov='Ovi:BAAALgADCgIJAgAAAA==.',
Pa='Pandariee:BAABLgAECn8VAAIcAAgJYw2hZQB4AQAcAAgJYw2hZQB4AQAAAA==.Pangsh:BAAALgAFFAEJAgAAAA==.Parzval:BAAALgAECgEJAgAAAA==.Paxgor:BAAALgAECgEJAQAAAA==.',
Pe='Pendaemonia:BAABLgAECn82AAITAAkJuRahDQAVAgATAAkJuRahDQAVAgAAAA==.Penelopie:BAAALgADCgYJBgAAAA==.',
Ph='Pherix:BAABLgAECn8cAAIdAAcJ1SAoEwATAgAdAAcJ1SAoEwATAgAAAA==.Phiirys:BAAALgAECgEJAQAAAA==.',
Pi='Picaso:BAAALgADCgEJAQAAAA==.Pight:BAAALgAECgUJBgABLgAECggJGgAMAI8PAA==.',
Po='Poomacha:BAABLgAECn8lAAISAAYJORfYYgBSAQASAAYJORfYYgBSAQAAAA==.',
Pu='Puffthemagic:BAAALgADCgYJCAAAAA==.',
Py='Pyree:BAABLgAECn8iAAMkAAkJbBAfJACZAQAkAAkJzA8fJACZAQAMAAcJaAmtFwBzAAAAAA==.',
['Pø']='Pøë:BAAALgAECgkJEwABLgAFFAIJAgABAAAAAA==.',
Qu='Qu:BAAALgAFFAIJAwAAAQ==.',
Qv='Qveemcorkie:BAAALgAECgEJAQAAAA==.',
['Qí']='Qín:BAAALgADCgUJAwAAAA==.',
Ra='Radagust:BAAALgAECgQJBAAAAA==.Radcat:BAAALgAECgEJAgAAAA==.Raenne:BAAALgAECgIJAwAAAA==.Ragebait:BAAALgADCgIJAgAAAA==.Rainfall:BAAALgAECgEJAgAAAA==.Raistlain:BAAALgAECgYJDwAAAA==.Raitha:BAAALgADCgUJCAAAAA==.Ralli:BAABLgAECn8jAAIOAAgJVhf4OwC3AQAOAAgJVhf4OwC3AQAAAA==.Rallsdemon:BAAALgAECgQJBAAAAA==.Rallsdk:BAAALgAECgMJAwABLgAECgQJBAABAAAAAA==.Rallsodins:BAAALgAECgIJAgABLgAECgQJBAABAAAAAA==.Randomguy:BAACLgAFFH8IAAIPAAQJtBd5DwBcAQAPAAQJtBd5DwBcAQAuAAQKfzcAAg8ACQl2Jc8BADUDAA8ACQl2Jc8BADUDAAAA.Ranulf:BAAALgAECgQJBgAAAA==.Ratava:BAAALgAECgMJAwAAAA==.Ratboy:BAEALgAECgEJAQABLgAECgkJMAAlABwjAA==.Ratrot:BAABLgAECn8YAAIWAAYJJyGdHAA5AgAWAAYJJyGdHAA5AgAAAA==.Ratsdead:BAAALgAECgEJAQAAAA==.Razenath:BAAALgADCgcJDAAAAA==.',
Re='Reinhardt:BAAALgADCgYJBgAAAA==.Rekrella:BAAALgADCgUJBQAAAA==.Reldarus:BAEBLgAECn8wAAMlAAkJHCPiAQCPAwAlAAkJHCPiAQCPAwAFAAQJ+hr8RAAlAQAAAA==.Rena:BAAALgADCgcJBwAAAA==.Rendia:BAAALgADCgMJAwAAAA==.Renik:BAAALgADCgIJAQAAAA==.Revennek:BAAALgAECgUJCgAAAA==.Reverence:BAABLgAECn8eAAIJAAkJ8A3RSgDHAQAJAAkJ8A3RSgDHAQAAAA==.Revilation:BAABLgAECn8cAAINAAkJYBPUDwCZAQANAAkJYBPUDwCZAQAAAA==.Rezjyk:BAAALgAECgYJCAABLgAECggJJwAJAFscAA==.Rezzyk:BAABLgAECn8nAAIJAAgJWxwpJQBPAgAJAAgJWxwpJQBPAgAAAA==.',
Rh='Rhonus:BAAALgAECgEJAQAAAA==.Rhyxali:BAAALgAECgYJEAAAAA==.',
Ri='Riis:BAAALgAECgQJCgAAAA==.Riiselock:BAABLgAECn8tAAMHAAgJIR5CNwAvAgAHAAcJyR1CNwAvAgAIAAQJFByPEwDnAAAAAA==.Riiwind:BAAALgADCgQJBAABLgAECgkJDQABAAAAAA==.Riktade:BAAALgADCgYJBgAAAA==.Rilight:BAAALgAECgEJAQABLgAECgkJDQABAAAAAA==.Riptidepod:BAABLgAECn8bAAMWAAcJhgf0XgAHAQAWAAcJhgf0XgAHAQAVAAIJ3gLAnAAdAAAAAA==.',
Ro='Robbiebrews:BAAALgADCgUJBQAAAA==.Rowin:BAAALgADCgUJBQAAAA==.',
Ry='Rynley:BAABLgAECn8WAAMPAAUJASEKJwDAAQAPAAUJASEKJwDAAQAmAAIJWRGqFgBwAAAAAA==.',
Sa='Sacredscales:BAABLgAECn8hAAMFAAkJtR5kCwCaAgAFAAcJ3yRkCwCaAgAdAAcJtRSGKgCGAQAAAA==.Sagerremeseb:BAAALgAECgEJAQAAAA==.Sakii:BAABLgAECn8iAAIOAAkJohBNNgDMAQAOAAkJohBNNgDMAQAAAA==.Salera:BAAALgADCgQJBAAAAA==.Samvimes:BAABLgAECn8kAAIJAAgJXw9xZACHAQAJAAgJXw9xZACHAQAAAA==.Sangreene:BAABLgAECn8bAAIdAAgJRxqFEwBYAgAdAAgJRxqFEwBYAgAAAA==.Sargis:BAABLgAECn88AAMJAAkJ0SJXCAAPAwAJAAkJ0SJXCAAPAwAEAAgJxxseFgAzAgAAAA==.Sarial:BAAALgADCgMJAwAAAA==.',
Sc='Schrödinger:BAAALgAECgYJDwABLgAECggJFAANAMsXAA==.Sciblasts:BAAALgADCgEJAQABLgADCgkJDAABAAAAAA==.Scott:BAACLgAFFH8jAAIOAAcJuyN7BABmAgAOAAcJuyN7BABmAgAuAAQKf0YAAg4ACQmaJmIAAI4DAA4ACQmaJmIAAI4DAAAA.Scratchh:BAABLgAECn8dAAILAAgJlAstNgB0AQALAAgJlAstNgB0AQAAAA==.',
Se='Searalsa:BAAALgAECgUJBwABLgAFFAMJCAAaANMIAA==.Sentis:BAABLgAECn8aAAIRAAYJOQgLSAC5AAARAAYJOQgLSAC5AAAAAA==.',
Sh='Shadowbrooks:BAAALgAECgIJAgAAAA==.Shadowgiver:BAAALgADCgcJDwAAAA==.Shadowsdemon:BAAALgADCgEJAQAAAA==.Shadowsworn:BAAALgAECgEJAQAAAA==.Shagol:BAAALgAECgQJBwAAAA==.Shalriss:BAABLgAECn8iAAIdAAgJIRlNFwDpAQAdAAgJIRlNFwDpAQAAAA==.Shamemoon:BAABLgAECn8aAAIOAAgJ1xdUNwDIAQAOAAgJ1xdUNwDIAQAAAA==.Shamunroe:BAABLgAECn8pAAMWAAkJMAfOTwA9AQAWAAkJMAfOTwA9AQAVAAUJkxKwWgDZAAAAAA==.Shatterhoof:BAABLgAECn8gAAIfAAcJgwtfGAAUAQAfAAcJgwtfGAAUAQAAAA==.Shelle:BAAALgAECgQJBwAAAA==.Shiftys:BAAALgADCgUJCgABLgAECgUJBgABAAAAAA==.Shingra:BAACLgAFFH8cAAIkAAUJJBqYGgA4AQAkAAUJJBqYGgA4AQAuAAQKfygAAiQACQnGHXALAIUCACQACQnGHXALAIUCAAAA.Shoof:BAAALgADCgUJBQAAAA==.',
Si='Sifû:BAAALgADCgcJDgAAAA==.Sigourney:BAAALgAECgUJBQABLgAECggJKgAeAKUaAA==.Silversho:BAAALgAECgIJAgAAAA==.Silvoid:BAAALgADCgMJAwAAAA==.Silvren:BAABLgAECn8pAAMDAAgJzxaAIADGAQADAAgJzxaAIADGAQAnAAEJvwZoRgArAAAAAA==.Sindarion:BAAALgAECgUJBQAAAA==.Sinz:BAAALgAECgEJBQAAAA==.Siph:BAAALgAECgEJAQAAAA==.',
Sk='Skillidan:BAABLgAECn8kAAIKAAgJ6RtmFwBpAgAKAAgJ6RtmFwBpAgAAAA==.',
Sl='Slighttrash:BAABLgAECn8YAAIeAAYJThI5KAA7AQAeAAYJThI5KAA7AQAAAA==.Sloppy:BAAALgADCggJCAAAAA==.',
Sm='Smacka:BAAALgAECgEJAQAAAA==.Smallcrow:BAACLgAFFH8YAAIYAAcJuRrbAQAAAgAYAAcJuRrbAQAAAgAuAAQKfxUAAhgABwkuJsQHAP8CABgABwkuJsQHAP8CAAAA.Smøke:BAAALgAECgMJAwAAAA==.',
Sn='Snallygaster:BAAALgADCgYJDAABLgAECggJIAAUADocAA==.Snowsong:BAAALgAECgEJAQAAAA==.',
Sp='Spamton:BAAALgADCgEJAQAAAA==.Spectrose:BAAALgADCgEJAQAAAA==.Spirit:BAAALgAECgEJAQAAAA==.Spiro:BAAALgAFFAIJAgAAAA==.',
St='Starge:BAAALgAECgQJBgAAAA==.Starre:BAAALgAECgUJBQAAAA==.Steffey:BAABLgAECn8hAAIWAAcJIgxjUAA7AQAWAAcJIgxjUAA7AQAAAA==.Straven:BAABLgAECn8XAAIXAAgJihOjVQC/AQAXAAgJihOjVQC/AQAAAA==.Sturgeson:BAACLgAFFH8XAAICAAUJGRrNDAAqAQACAAUJGRrNDAAqAQAuAAQKfx8AAgIACQlvHQcMAEsCAAIACQlvHQcMAEsCAAAA.',
Su='Sulwen:BAABLgAECn8yAAIFAAkJJBfcFQD9AQAFAAkJJBfcFQD9AQAAAA==.',
Sw='Sweetpotato:BAAALgADCgEJAQAAAA==.Swiftfeet:BAABLgAECn8iAAISAAgJ5RRaRwCfAQASAAgJ5RRaRwCfAQAAAA==.',
Sy='Syrasia:BAAALgADCgUJBQAAAA==.Syselea:BAAALgADCgEJAQAAAA==.',
['Sö']='Söranin:BAABLgAECn8VAAIZAAYJ5xipJgCmAQAZAAYJ5xipJgCmAQAAAA==.',
Ta='Tachichan:BAAALgAECgYJBgAAAA==.Tadum:BAAALgADCgEJAQAAAA==.Taeili:BAABLgAECn8bAAMUAAkJIhXQJgDYAAARAAgJ2BVoNgBiAQAUAAUJfA7QJgDYAAAAAA==.Talisse:BAAALgADCgYJBgAAAA==.Tanequil:BAACLgAFFH8IAAIKAAMJCgI7RgB+AAAKAAMJCgI7RgB+AAAuAAQKfyMAAgoACAmsDNdKAHgBAAoACAmsDNdKAHgBAAAA.Targaryian:BAAALgAECgMJAwAAAA==.Tav:BAAALgADCgUJBQAAAA==.Taylea:BAABLgAECn8WAAIXAAcJpA8RnAAnAQAXAAcJpA8RnAAnAQABLgAECggJIwAJAJ0eAA==.',
Te='Techromancer:BAAALgAECgYJCAABLgAECgcJHAAdANUgAA==.Tem:BAAALgAECgMJAwAAAA==.Tenumbras:BAAALgAECgYJDAAAAA==.Termonda:BAAALgAECgEJAQAAAA==.Terraclaw:BAAALgADCgUJBwAAAA==.Terrasia:BAAALgADCgYJBgAAAA==.Terrigino:BAAALgAECgIJAgAAAA==.',
Th='Thanatias:BAABLgAECn8VAAIbAAcJmBV7GwBOAQAbAAcJmBV7GwBOAQAAAA==.Thantasia:BAABLgAECn8VAAIXAAYJmAMr2gDBAAAXAAYJmAMr2gDBAAAAAA==.Thauras:BAAALgADCgcJFwAAAA==.Theeslan:BAAALgAECgkJEQAAAA==.Thokdar:BAAALgAECgUJBQAAAA==.Thom:BAACLgAFFH8KAAIhAAQJihAeCQAfAQAhAAQJihAeCQAfAQAuAAQKfykAAyEACAmuI+cAABwDACEACAmuI+cAABwDABwABgmoDjmxACABAAAA.Thør:BAAALgADCgcJDgAAAA==.',
Ti='Tifà:BAAALgAECgUJCAAAAA==.Timothy:BAABLgAECn8aAAITAAgJGhlCEgDQAQATAAgJGhlCEgDQAQAAAA==.Tinkphooey:BAAALgAECgYJCwAAAA==.Tinton:BAAALgADCgEJAQAAAA==.',
To='Tormmok:BAAALgAECgYJDAAAAA==.Toshindo:BAAALgADCgUJBAAAAA==.',
Tr='Trashpally:BAAALgAECgEJAgAAAA==.Tremèndor:BAAALgADCgMJAwAAAA==.Trey:BAAALgAECgEJAQAAAA==.Tristra:BAAALgAECgQJBAAAAA==.',
Ts='Tsuruga:BAABLgAECn83AAILAAkJQA4tHQCcAQALAAkJQA4tHQCcAQAAAA==.',
Tu='Turkwise:BAABLgAECn8vAAMUAAkJGhfWCQAPAgAUAAkJGhfWCQAPAgAfAAQJCBGsHgDuAAAAAA==.',
Ty='Tycondrius:BAAALgAECgEJAQAAAA==.Tyresh:BAAALgAECgEJAQAAAA==.Tyrinor:BAAALgADCgUJBQAAAA==.',
Ul='Ulogasm:BAAALgADCggJCAAAAA==.',
Us='Usami:BAAALgAECgEJAQAAAA==.',
Ut='Utako:BAAALgADCgUJCgAAAA==.',
Uv='Uvari:BAAALgAECgYJCAAAAA==.',
Va='Vaclar:BAAALgAECgUJBQABLgAFFAQJCwAYAK8hAA==.Valhalaa:BAAALgADCgYJBgAAAA==.Valton:BAACLgAFFH8LAAIYAAQJryFZBgB/AQAYAAQJryFZBgB/AQAuAAQKf0AAAhgACQlTJocAAH0DABgACQlTJocAAH0DAAAA.Vanillanice:BAAALgAECgUJCAAAAA==.Varrfife:BAAALgAECgMJAwAAAA==.Vaxaldan:BAABLgAECn83AAIbAAkJLQ5EGABwAQAbAAkJLQ5EGABwAQAAAA==.',
Ve='Velithera:BAAALgADCgMJAwAAAA==.Vellithe:BAABLgAECn8WAAIJAAcJIQo8swD4AAAJAAcJIQo8swD4AAAAAA==.Venj:BAAALgAECgUJBgAAAA==.Verhmax:BAAALgADCgYJCwAAAA==.Vestrae:BAACLgAFFH8IAAMKAAQJ1gfYKwDmAAAKAAQJ1gfYKwDmAAARAAEJSQHPQAArAAAuAAQKfyQAAgoACAl+Hm8TAJoCAAoACAl+Hm8TAJoCAAAA.Vex:BAABLgAECn8WAAIHAAcJ6hpfQwC5AQAHAAcJ6hpfQwC5AQAAAA==.',
Vi='Vianel:BAAALgADCggJCAAAAA==.Vilten:BAAALgAECgQJCwAAAA==.',
Vo='Vodash:BAABLgAECn8hAAIWAAcJ3RlKKADvAQAWAAcJ3RlKKADvAQABLgAECggJLgAKADUQAA==.Vostok:BAABLgAECn8cAAIHAAgJOBznPwAOAgAHAAgJOBznPwAOAgAAAA==.',
Wa='Wage:BAAALgADCgQJBQAAAA==.Warmth:BAAALgADCgIJAwAAAA==.',
We='Weekend:BAAALgADCgkJDwAAAA==.Wetsock:BAAALgAECgYJBwAAAA==.',
Wi='Wikket:BAABLgAECn83AAMRAAkJFRu7CgCCAgARAAkJFRu7CgCCAgAKAAgJ3ANMaQDYAAAAAA==.',
Wo='Wolvesbayne:BAAALgAECgEJAQAAAA==.',
Wy='Wyelie:BAAALgAECgYJDAAAAA==.Wynono:BAAALgADCgcJBwAAAA==.',
Xd='Xdeadlysinz:BAAALgAECgcJCQAAAA==.',
Xo='Xotha:BAABLgAECn8xAAIOAAgJUR4yIgArAgAOAAgJUR4yIgArAgAAAA==.',
Xu='Xuen:BAAALgAFFAEJAwAAAA==.',
Xy='Xythera:BAACLgAFFH8GAAIOAAMJARnQRQDoAAAOAAMJARnQRQDoAAAuAAQKfx8AAw4ACQmKIPYVANMCAA4ACQmKIPYVANMCACAAAQmwEOAqADIAAAAA.',
Ye='Yeah:BAAALgADCgYJBgABLgAFFAMJBwAJAEwMAA==.',
Yi='Yinosai:BAAALgAECgQJBgAAAA==.',
Yo='Yougot:BAAALgADCgcJCgAAAA==.',
Yu='Yuji:BAABLgAECn8hAAIIAAYJaR3YCACQAQAIAAYJaR3YCACQAQAAAA==.Yukì:BAAALgADCgMJAwAAAA==.Yurie:BAAALgAECgIJAgAAAA==.',
Yv='Yvonna:BAAALgADCgEJAQAAAA==.',
Za='Zaega:BAAALgADCgQJBAABLgAECggJIwAJAJ0eAA==.Zahlee:BAAALgAECgQJBAAAAA==.Zalirina:BAAALgADCgIJAgAAAA==.Zanka:BAAALgAECgIJAgAAAA==.Zaridruid:BAAALgAECgkJCgAAAA==.Zarisedra:BAACLgAFFH8cAAMEAAUJWBryDQCYAQAEAAUJWBryDQCYAQAJAAEJXgDaOwA2AAAuAAQKfxgAAwQACQkwF8kpAOMBAAQACAkGGMkpAOMBAAkAAQktBuw9ATUAAAAA.Zarissena:BAAALgAECgMJAwAAAA==.Zarris:BAAALgADCgUJDAAAAA==.',
Ze='Zennith:BAAALgADCgMJAwAAAA==.Zernacho:BAABLgAECn8dAAQFAAgJPRttGQDYAQAFAAYJJhxtGQDYAQAdAAcJ+hFBLgBvAQAlAAIJbhJIUQBuAAAAAA==.Zerogasm:BAABLgAECn8XAAISAAkJAhZhIgAwAgASAAkJAhZhIgAwAgAAAA==.Zerolicious:BAAALgADCgUJBgAAAA==.Zerozaddy:BAAALgAECgUJBgAAAA==.Zevvo:BAABLgAECn8uAAIDAAkJECGoBgDZAgADAAkJECGoBgDZAgAAAA==.',
Zi='Ziggysundust:BAAALgADCgMJAwAAAA==.',
Zo='Zoraji:BAABLgAECn86AAILAAkJdhoMDABWAgALAAkJdhoMDABWAgAAAA==.',
Zu='Zuganova:BAABLgAFFH8SAAMlAAUJDQjOFwBRAQAlAAUJ4QfOFwBRAQAFAAEJ8whwFgA8AAAAAA==.Zuggar:BAABLgAECn8fAAIDAAcJVwgDRQAIAQADAAcJVwgDRQAIAQAAAA==.',
Zy='Zynhammer:BAABLgAECn8kAAMOAAgJgxFhXQCJAQAOAAgJgxFhXQCJAQATAAEJawaaXwAoAAAAAA==.',
['Év']='Évangeline:BAAALgADCgcJBwAAAA==.',
['Ëb']='Ëbony:BAAALgAFFAEJAgABLgAFFAIJAgABAAAAAA==.',
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
