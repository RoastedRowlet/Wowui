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

local lookup = {'Unknown-Unknown','Druid-Restoration','Warrior-Protection','Warrior-Fury','Priest-Holy','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Paladin-Retribution','Shaman-Restoration','Paladin-Holy','Evoker-Devastation','Warrior-Arms','DemonHunter-Havoc','Paladin-Protection','Druid-Feral','DemonHunter-Devourer','Rogue-Subtlety','Rogue-Assassination','Druid-Balance','Hunter-BeastMastery','Druid-Guardian','Shaman-Elemental','Monk-Windwalker','Monk-Mistweaver','Shaman-Enhancement','Evoker-Augmentation','DeathKnight-Blood','DeathKnight-Unholy','Priest-Shadow','Hunter-Survival','Mage-Frost','Monk-Brewmaster','DemonHunter-Vengeance','DeathKnight-Frost','Mage-Arcane','Hunter-Marksmanship','Priest-Discipline','Rogue-Outlaw',}
local provider = {region='US',realm='ShadowCouncil',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abear:BAAALgAECgQJBQAAAA==.Abrocklock:BAAALgAECgYJCQAAAA==.',
Ac='Achilês:BAAALgAECgEJAQABLgAECgkJDgABAAAAAA==.',
Ad='Adaluna:BAABLgAECn8XAAICAAkJ2wmXUgBFAQACAAkJ2wmXUgBFAQAAAA==.Adorabull:BAACLgAFFH8JAAIDAAMJRyLxEAAnAQADAAMJRyLxEAAnAQAuAAQKfyUAAwMACQnVIbwGAJwCAAMACQnVIbwGAJwCAAQAAQnQBhGvACwAAAAA.Adrain:BAAALgAECgQJCwAAAA==.Adwae:BAAALgAECgIJAgAAAA==.',
Ae='Aelyn:BAAALgAECgcJDwAAAA==.Aerendyl:BAAALgAECgEJAQAAAA==.Aevelee:BAAALgAECggJDwAAAA==.Aevick:BAAALgAECgQJBQAAAA==.',
Al='Alastair:BAAALgADCgEJAQAAAA==.Aleeta:BAAALgAECgQJBgAAAA==.Allucard:BAAALgAECgkJAgAAAA==.',
Am='Amapanda:BAAALgAECgkJCQAAAA==.Amaria:BAAALgAECgkJBgAAAA==.Amoracchius:BAAALgADCgMJAwAAAA==.',
An='Angelstörm:BAACLgAFFH8IAAIFAAIJPwy9LABkAAAFAAIJPwy9LABkAAAuAAQKf0AAAgUACQloGe4SAEUCAAUACQloGe4SAEUCAAAA.Anjali:BAAALgAECgEJAQAAAA==.Anorili:BAAALgADCgYJBgAAAA==.Antarias:BAABLgAECn8eAAQGAAkJQhrVEQBIAQAGAAUJDSPVEQBIAQAHAAcJqhJoogD7AAAIAAMJjhi9JwB5AAAAAA==.Antarion:BAAALgAECgQJBAAAAA==.',
Ap='Applevendor:BAAALgADCgUJBQAAAA==.',
Ar='Arahil:BAAALgAECgQJBwAAAA==.Arcanio:BAAALgADCgQJBAAAAA==.Arcaux:BAAALgADCggJDgAAAA==.Arckenon:BAACLgAFFH8GAAIJAAMJQh2rWQD9AAAJAAMJQh2rWQD9AAAuAAQKf0EAAgkACQlwJKYIACUDAAkACQlwJKYIACUDAAAA.',
As='Ashdorei:BAAALgADCgMJAwAAAA==.Ashog:BAABLgAECn8WAAIKAAYJ4RYYQACtAQAKAAYJ4RYYQACtAQAAAA==.Astranos:BAAALgAECgEJAQABLgAECgkJRwACAB8QAA==.',
At='Athanyr:BAABLgAECn8sAAICAAgJXyU6BgBUAwACAAgJXyU6BgBUAwAAAA==.Atillis:BAAALgADCgYJDAAAAA==.',
Au='Augmentation:BAAALgAECgEJAQAAAA==.Austenpally:BAABLgAECn8hAAMJAAkJ3RhlcACNAQAJAAcJ3hZlcACNAQALAAcJkRGeNwBvAQAAAA==.',
Av='Aveycado:BAAALgAECgEJAQAAAA==.Aviane:BAAALgAECgYJBgAAAA==.',
Ax='Axeflack:BAAALgAECgEJAQAAAA==.Axegor:BAAALgADCgMJAwAAAA==.',
Az='Azrall:BAAALgAECgIJAgAAAA==.',
Ba='Bacuda:BAAALgAECgYJEAAAAA==.Badwolf:BAAALgADCgQJBAAAAA==.Balkris:BAAALgAECgEJAgABLgAECggJHgAMAI8PAA==.Baratheon:BAABLgAECn8VAAMNAAkJCg+5FwCdAQANAAkJNg65FwCdAQAEAAcJXgbYXQA4AQAAAA==.Batya:BAAALgAECgIJAgAAAA==.',
Be='Beartooth:BAAALgADCgUJBQAAAA==.Bearynice:BAAALgADCgUJBQAAAA==.Beggles:BAAALgADCgEJAQAAAA==.Bereit:BAAALgADCgcJBgAAAA==.',
Bi='Biancadelrio:BAABLgAECn8lAAIOAAgJYhGXIQBsAQAOAAgJYhGXIQBsAQAAAA==.Bigboned:BAAALgADCgEJAQABLgAECgkJHgAPAM0WAA==.Bigmode:BAAALgADCgYJBgAAAA==.Bigwolves:BAAALgADCgIJAgAAAA==.',
Bj='Bjorrglbrgl:BAABLgAFFH8IAAIQAAMJexlNDQDiAAAQAAMJexlNDQDiAAAAAA==.',
Bl='Blackmask:BAAALgADCgUJCAAAAA==.Blackzune:BAAALgAECgEJAQAAAA==.Bladekrim:BAAALgAECgEJAgAAAA==.Blindashunae:BAACLgAFFH8cAAIRAAgJuQ6wGwDVAQARAAgJuQ6wGwDVAQAuAAQKfxYAAhEACQlQHikVANgCABEACQlQHikVANgCAAAA.Blindkungfu:BAAALgAECgQJBAAAAA==.Bloodrun:BAAALgADCgkJCgAAAA==.Blook:BAABLgAECn8UAAMSAAgJThXzIACOAQASAAgJThXzIACOAQATAAEJkgg2HwA3AAAAAA==.Bluehazey:BAAALgAECgkJEQAAAA==.Blueleader:BAAALgAECgQJBAAAAA==.Bläz:BAAALgAECgEJAQAAAA==.',
Bo='Boomhammer:BAAALgAFFAIJBAAAAA==.Bootsy:BAAALgAECgcJBAAAAA==.Bopit:BAABLgAECn8WAAMJAAkJ+g6nnwBAAQAJAAYJeA6nnwBAAQALAAkJ9AzJUAA2AQAAAA==.Botia:BAABLgAECn8UAAIUAAYJiwQqYACYAAAUAAYJiwQqYACYAAAAAA==.',
Br='Braedia:BAAALgAECgEJAQAAAA==.Bruhh:BAAALgAECgYJBwAAAA==.Brunnera:BAAALgAECgIJAwAAAA==.Bruuenor:BAAALgAECgYJBwAAAA==.Bruul:BAABLgAECn8mAAQJAAgJ0xmEOgAZAgAJAAgJ0xmEOgAZAgALAAQJ3Q3HXADCAAAPAAEJ1RBEUQAuAAAAAA==.Brynjolf:BAAALgAECgUJCQAAAA==.',
Ca='Caenji:BAABLgAECn8XAAIVAAkJOAsLaQBwAQAVAAkJOAsLaQBwAQAAAA==.Carcharoth:BAABLgAECn8nAAMIAAkJlBjuCQCnAQAIAAcJNRruCQCnAQAHAAYJqBCRrgDmAAAAAA==.Carmelina:BAABLgAECn8oAAIOAAgJJBzDDgA6AgAOAAgJJBzDDgA6AgAAAA==.Catrixona:BAAALgAECgUJCAAAAA==.Caylan:BAAALgADCgQJBAAAAA==.',
Ch='Chadgar:BAAALgADCgIJAgAAAA==.Chaoscaster:BAAALgADCgkJCQABLgAECgYJBgABAAAAAA==.Charroth:BAAALgAECgYJCAAAAA==.Chey:BAABLgAECn88AAISAAkJ3yTMAgAnAwASAAkJ3yTMAgAnAwAAAA==.Chilai:BAABLgAECn8lAAIWAAkJABgxDAAeAgAWAAkJABgxDAAeAgAAAA==.Chipsahoy:BAABLgAECn8iAAMXAAkJ2x8bCgC8AgAXAAkJ2x8bCgC8AgAKAAYJdRJ3RQBsAQAAAA==.Chrîstîan:BAAALgADCgYJBgAAAA==.Chíef:BAABLgAFFH8TAAMKAAYJ6B8HCQA4AgAKAAYJ6B8HCQA4AgAXAAIJNwPoTwBYAAAAAA==.',
Ci='Cindrozetha:BAAALgADCgEJAQAAAA==.Ciphérdivine:BAAALgADCgUJBAAAAA==.Citte:BAAALgAFFAEJAgAAAA==.',
Cl='Close:BAAALgADCgUJBQABLgAFFAMJCQAKANEiAA==.',
Co='Conciete:BAABLgAECn8VAAMYAAgJWhXmGgAHAgAYAAgJWhXmGgAHAgAZAAEJBAHidwARAAAAAA==.Conorix:BAAALgAECgUJCAAAAA==.Constantiine:BAAALgAECgEJAQAAAA==.Corvo:BAABLgAECn8ZAAIPAAkJ7RiNCgAhAgAPAAkJ7RiNCgAhAgAAAA==.Counselor:BAAALgAECgUJCQAAAA==.Courallie:BAAALgAECgEJAQAAAA==.',
Cr='Crataxxis:BAABLgAECn9JAAIOAAkJ+BuGCQCSAgAOAAkJ+BuGCQCSAgAAAA==.Crynos:BAAALgADCgMJAwAAAA==.Crysandra:BAAALgAECgUJBQAAAA==.',
Cy='Cydon:BAABLgAECn84AAIWAAkJvR6dBQCwAgAWAAkJvR6dBQCwAgAAAA==.',
Da='Daereth:BAAALgAECgYJCQAAAA==.Daerrith:BAAALgAECgUJCQAAAA==.Dala:BAAALgAECgUJBQAAAA==.Damienfox:BAAALgAECgQJBgAAAA==.Dana:BAAALgAFFAEJAQABLgAFFAMJDwACABIUAA==.Danellia:BAAALgADCgUJBQAAAA==.Darkreaper:BAAALgAECgQJBAAAAA==.Darrwin:BAABLgAECn8mAAMJAAgJoR/EJgBpAgAJAAgJoR/EJgBpAgAPAAQJnw3ULwCoAAAAAA==.Dawicker:BAAALgADCgYJDwAAAA==.Daylight:BAAALgAECgYJCQAAAA==.',
De='Dedoria:BAAALgADCgUJBQAAAA==.Defacto:BAAALgADCgMJAwAAAA==.Delat:BAAALgAECgEJAQAAAA==.Delrac:BAABLgAECn8iAAIRAAgJWxFMWQB8AQARAAgJWxFMWQB8AQAAAA==.Demonalsa:BAAALgAECgEJAgABLgAFFAQJDAAaAFIJAA==.Denathrius:BAAALgAECgIJAwABLgAFFAQJBwARAAEZAA==.Denero:BAABLgAECn8dAAIJAAkJIx75GwCdAgAJAAkJIx75GwCdAgAAAA==.Departure:BAAALgAECgQJBwABLgAECgcJFwAOAEMcAA==.Derith:BAAALgADCgEJAQAAAA==.',
Df='Dfabness:BAACLgAFFH8KAAIYAAMJ5xDSJQC8AAAYAAMJ5xDSJQC8AAAuAAQKfyAAAhgACQlKEFskAJABABgACQlKEFskAJABAAAA.',
Di='Dic:BAAALgADCgIJAgABLgAECgMJAwABAAAAAA==.',
Do='Docbush:BAAALgAECgEJAQABLgAFFAQJDgAHAPkEAA==.Docbushed:BAAALgAECgQJBAABLgAFFAQJDgAHAPkEAA==.Dotbush:BAACLgAFFH8OAAMHAAQJ+QQ6bgDmAAAHAAQJ+QQ6bgDmAAAIAAEJhwKiLAAzAAAuAAQKfzAABAcACQlsFc5IAMABAAcACQmVFM5IAMABAAgAAwmrDIBGAJwAAAYAAgnOEcYoAHwAAAAA.Dotspot:BAAALgADCgQJBAABLgAECgMJBwABAAAAAA==.',
Dr='Dracthayr:BAABLgAECn86AAIMAAkJZROuBgDhAQAMAAkJZROuBgDhAQAAAA==.Dragonhammer:BAACLgAFFH8LAAIJAAIJGST0cwDMAAAJAAIJGST0cwDMAAAuAAQKf1EAAgkACQmAJIIHADEDAAkACQmAJIIHADEDAAAA.Drakanna:BAAALgAECgIJAgAAAA==.Draxela:BAABLgAECn8aAAIbAAcJfAjqAQC7AAAbAAcJfAjqAQC7AAAAAA==.Dreaming:BAABLgAECn8wAAIcAAkJZiLBBAD7AgAcAAkJZiLBBAD7AgABLgAFFAMJCQAKANEiAA==.Drosidon:BAABLgAECn8UAAIdAAYJnAWn/QCvAAAdAAYJnAWn/QCvAAAAAA==.Drubo:BAAALgAECgIJAgAAAA==.Drx:BAAALgAECgYJBgABLgAECgkJLAAXAKIVAA==.',
Ea='Earsog:BAAALgADCgEJAQAAAA==.Earthenfist:BAAALgAECgEJAQAAAA==.',
Eb='Ebebebebe:BAAALgAECgEJAQAAAA==.',
Ef='Efbomb:BAAALgADCgcJBwAAAA==.',
Ei='Eitherindel:BAAALgADCgkJCgAAAA==.',
El='Elanore:BAAALgAECgUJBgAAAA==.Ellaini:BAABLgAECn8SAAIeAAgJoAtiMwBMAQAeAAgJoAtiMwBMAQAAAA==.Ellie:BAABLgAFFH8SAAIKAAQJhB/yAQBkAQAKAAQJhB/yAQBkAQAAAA==.Elseb:BAAALgAECgQJBwAAAA==.',
Em='Emberlyn:BAAALgAECgIJBQAAAA==.Emotion:BAAALgADCgYJAQABLgAFFAMJCQAKANEiAA==.',
En='Enchantrêss:BAAALgAECggJCAABLgAECgkJDgABAAAAAA==.Endo:BAAALgAECgEJAQAAAA==.',
Er='Erenara:BAAALgAECgQJCwAAAA==.',
Ev='Evic:BAABLgAECn9HAAICAAkJHxDMNgC+AQACAAkJHxDMNgC+AQAAAA==.',
Ew='Ewson:BAAALgADCgcJCwAAAA==.',
Ex='Excrubilis:BAAALgAFFAIJBAAAAA==.',
Fa='Faandango:BAAALgAECgUJBQAAAA==.Faeleader:BAABLgAECn8aAAICAAgJVQ2UTABdAQACAAgJVQ2UTABdAQAAAA==.Faevelina:BAAALgAECgUJDAABLgAECgkJCgABAAAAAA==.Fannypacker:BAAALgAECgkJAQAAAA==.Fatshamer:BAAALgAECgEJAQAAAA==.Faytadori:BAAALgADCgEJAQAAAA==.',
Fe='Felgrrl:BAAALgADCgkJNQAAAA==.Fester:BAAALgAECgEJAQAAAA==.Feyreh:BAAALgAECgcJCAAAAA==.',
Fi='Fieona:BAAALgADCgYJCwAAAA==.Firethorns:BAAALgAECgQJBgAAAA==.Fistandilias:BAAALgADCgkJCQAAAA==.Fitzbang:BAAALgAECgUJBwAAAA==.',
Fl='Florigrowl:BAAALgAECgMJAwAAAA==.',
Fo='Forever:BAAALgAECgMJBQABLgAFFAMJCQAKANEiAA==.Formortiis:BAAALgADCgEJAQAAAA==.Forrestior:BAABLgAECn8YAAIfAAgJoiShAQBBAwAfAAgJoiShAQBBAwAAAA==.Forsthoof:BAAALgADCgYJBgAAAA==.',
Fr='Fraga:BAAALgAECgYJDgABLgAFFAUJDQAdAJkMAA==.Frailty:BAAALgAECgYJCwAAAA==.Frique:BAABLgAECn8aAAIKAAYJ0x3bLAAFAgAKAAYJ0x3bLAAFAgAAAA==.Frostfingers:BAAALgAECgQJBgAAAA==.Frostyfang:BAABLgAECn8kAAMQAAgJ/xw8EwCKAQAQAAYJpCA8EwCKAQAUAAQJthPEVQC5AAAAAA==.Frozenyogert:BAAALgAECgQJBAAAAA==.',
Fu='Fufula:BAAALgADCgQJBAAAAA==.Funkbot:BAAALgAECgYJDAAAAA==.Furgilicious:BAAALgAECgEJAgABLgAECgYJEAABAAAAAA==.',
['Fä']='Färshadow:BAAALgAECgEJAQAAAA==.',
Ga='Galbur:BAACLgAFFH8NAAMdAAUJmQx4gAAGAQAdAAQJmQx4gAAGAQAcAAIJ+RE2PwA1AAAuAAQKfycAAx0ACQndHl8jAHgCAB0ACQnsHF8jAHgCABwACAkUFcwXAJ0BAAAA.Galdrin:BAAALgAECgkJCgAAAA==.Gaspode:BAAALgADCgcJBwAAAA==.Gassann:BAAALgAECggJDgAAAA==.',
Ge='Geers:BAABLgAECn8dAAIgAAkJ2SLwDgADAwAgAAkJ2SLwDgADAwAAAA==.Geta:BAAALgAECgQJBwABLgAECgkJIAAEAF0iAA==.Getacast:BAAALgAECgEJAQABLgAECgkJIAAEAF0iAA==.Getademon:BAAALgADCgEJAQABLgAECgkJIAAEAF0iAA==.Getaform:BAAALgAECgEJAQABLgAECgkJIAAEAF0iAA==.Getagrip:BAAALgAECgQJBgABLgAECgkJIAAEAF0iAA==.Getaheal:BAAALgAECgYJBgABLgAECgkJIAAEAF0iAA==.Getalife:BAAALgAECgIJAgABLgAECgkJIAAEAF0iAA==.Getarage:BAABLgAECn8gAAIEAAkJXSIeFACtAgAEAAkJXSIeFACtAgAAAA==.',
Gh='Ghil:BAABLgAECn8vAAMGAAkJqiMTAQADAwAGAAkJqiMTAQADAwAHAAQJnxXfvADfAAAAAA==.',
Gi='Gigawatt:BAABLgAECn8sAAMXAAkJohUOLACVAQAXAAgJQBMOLACVAQAKAAMJ9QnDpQCBAAAAAA==.Gildersleeve:BAAALgAECgQJCQAAAA==.Gilia:BAAALgADCgkJOAAAAA==.Girthfist:BAABLgAECn8WAAIhAAgJRSMIBQA5AwAhAAgJRSMIBQA5AwABLgAFFAgJGQADAN8dAA==.',
Gl='Glynixtwo:BAAALgAECgMJBQAAAA==.',
Go='Goldiwarlock:BAAALgADCgcJDgAAAA==.Goloron:BAAALgADCgkJDwAAAA==.',
Gr='Graymayn:BAABLgAECn8aAAIfAAkJ8BmsCgB0AgAfAAkJ8BmsCgB0AgAAAA==.Gremel:BAABLgAECn8mAAQWAAgJfR2lHABoAQAWAAUJLhmlHABoAQAQAAUJsBo6GQBFAQAUAAMJGRziRAD5AAAAAA==.Grimdor:BAAALgAECgYJDAAAAA==.Grimflaps:BAAALgAECgMJBQAAAA==.Grimmist:BAABLgAECn8hAAIZAAcJihjMMgCsAQAZAAcJihjMMgCsAQAAAA==.',
Gu='Guloot:BAABLgAECn8bAAMKAAgJBAa7hgDQAAAKAAgJBAa7hgDQAAAXAAUJtQaxhQBkAAAAAA==.Gunboyten:BAAALgAECgIJAgAAAA==.Gunderthirth:BAACLgAFFH8ZAAIDAAgJ3x08AQDnAQADAAgJ3x08AQDnAQAuAAQKfy0AAwMACQmnJKIBAGsDAAMACQmnJKIBAGsDAAQABQmMIt0uAJQBAAAA.Gurkin:BAAALgADCgEJAQAAAA==.',
Gw='Gwaeniiha:BAABLgAECn8zAAIJAAkJwxOxYgCrAQAJAAkJwxOxYgCrAQAAAA==.Gward:BAAALgAECgUJBgAAAA==.Gwizz:BAABLgAECn8sAAIgAAkJnBsFMABZAgAgAAkJnBsFMABZAgAAAA==.',
Ha='Halibard:BAABLgAFFH8OAAIFAAUJSwjDFgAIAQAFAAUJSwjDFgAIAQAAAA==.Halinka:BAAALgADCgYJBgAAAA==.Handsoap:BAABLgAECn8eAAIOAAkJdA7YHwB7AQAOAAkJdA7YHwB7AQAAAA==.Haquar:BAAALgAECgQJCQAAAA==.Hardhitter:BAABLgAECn8nAAQNAAkJpxUfEwDKAQANAAgJbRUfEwDKAQADAAcJigz3HgA7AQAEAAMJhg8WfwB6AAAAAA==.',
He='Hehe:BAAALgADCgQJBAAAAA==.Helldog:BAAALgAECgMJAwABLgAECgkJJQAiALYeAA==.Hellumph:BAABLgAECn8lAAIiAAkJth6/AgDJAgAiAAkJth6/AgDJAgAAAA==.Hellwraith:BAAALgADCggJDgABLgAECgkJJQAiALYeAA==.Hermesconrad:BAAALgAECgkJEwAAAA==.Hevensrath:BAABLgAECn85AAIJAAkJdx/nFgC5AgAJAAkJdx/nFgC5AgAAAA==.',
Ho='Hokuden:BAABLgAECn86AAIjAAkJGhmBCAAFAgAjAAkJGhmBCAAFAgAAAA==.Honina:BAAALgADCgIJAgAAAA==.Hornswaggles:BAAALgAECgQJBAAAAA==.Horsebananas:BAAALgAECgIJBAABLgAECgkJOAAfANMcAA==.',
Ht='Htari:BAAALgAFFAIJAgAAAA==.',
Hu='Huddington:BAABLgAECn8jAAIkAAkJ1RfvAgAMAgAkAAkJ1RfvAgAMAgAAAA==.Hussh:BAAALgAECgYJDAABLgAECgkJHgAPAM0WAA==.',
Hy='Hydraness:BAAALgAECgEJAQABLgAECgQJBAABAAAAAA==.',
Ia='Iamcammy:BAAALgAECgYJEAAAAA==.',
Ic='Icedragon:BAAALgAECgkJBwAAAA==.',
Ig='Igknight:BAAALgAECgMJAwABLgAECgkJLAAhALEPAA==.',
Il='Illexi:BAAALgADCgYJBgAAAA==.',
Im='Imariz:BAAALgAECgcJBwAAAA==.Imdarkness:BAAALgAECgkJDgAAAA==.Impquisitor:BAAALgAECgYJBwAAAA==.',
In='Indecent:BAABLgAECn8zAAQHAAkJOh3gFQCiAgAHAAkJOh3gFQCiAgAIAAYJHBd3FACnAQAGAAMJ3hQLGAC7AAAAAA==.Indeed:BAAALgAECgUJBgAAAA==.Inibble:BAAALgADCgcJBgAAAA==.',
Ir='Irozi:BAAALgADCgUJBQAAAA==.',
Is='Ishy:BAAALgAECgUJCAAAAA==.',
Ix='Ixelle:BAAALgADCgUJDQABLgAECgYJEQABAAAAAA==.',
Iz='Izomar:BAABLgAECn8gAAIgAAgJahkZTQD0AQAgAAgJahkZTQD0AQAAAA==.',
Ja='Jackieechan:BAAALgAECgcJBwABLgAFFAUJDwALAL8kAA==.Jackiemays:BAACLgAFFH8PAAMLAAUJvySjEQCpAQALAAQJQCajEQCpAQAJAAIJsQF2ywA1AAAuAAQKfzEAAwsACAkUJDIOALACAAsACAkUJDIOALACAAkACAlgGnY9AC8CAAAA.Jaded:BAAALgAECgUJBQAAAA==.Jaleigha:BAAALgADCgcJDgAAAA==.Jamesin:BAAALgAECgYJCAAAAA==.',
Je='Jedaii:BAAALgAECgYJBgAAAA==.Jeff:BAAALgAECgEJAwAAAA==.Jeses:BAABLgAECn8vAAIJAAkJQhaKQgD/AQAJAAkJQhaKQgD/AQAAAA==.',
Jo='Jollah:BAAALgAECgUJBgAAAA==.',
Ju='Jutic:BAACLgAFFH8JAAIKAAMJ/hjCQgDcAAAKAAMJ/hjCQgDcAAAuAAQKfzoAAgoACQnOIj4IACwDAAoACQnOIj4IACwDAAAA.',
Jy='Jyssa:BAAALgADCgEJAQAAAA==.',
['Jö']='Jörmun:BAAALgAFFAIJBAAAAA==.',
Ka='Kageken:BAAALgADCgUJBQABLgAECgQJBwABAAAAAA==.Kaia:BAABLgAECn8lAAISAAkJgA/NGADUAQASAAkJgA/NGADUAQAAAA==.Kaldrich:BAAALgAECgMJBAAAAA==.Kamoto:BAAALgAECgQJBAABLgAECgkJLAAXAKIVAA==.Kanetsu:BAAALgADCgIJAgAAAA==.Kardas:BAABLgAECn8YAAMVAAkJuQdHbABpAQAVAAkJuQdHbABpAQAlAAMJ1AGLfABSAAAAAA==.Kardio:BAACLgAFFH8FAAIYAAQJ6gyiKACvAAAYAAQJ6gyiKACvAAAuAAQKfxoAAxgACAn+EK0rAIEBABgACAn+EK0rAIEBABkAAQkBClBnADUAAAAA.Kayj:BAAALgAECgEJAQAAAA==.Kayrina:BAAALgADCgkJCgAAAA==.Kazeer:BAABLgAECn8bAAIJAAkJLQjWmgBAAQAJAAkJLQjWmgBAAQAAAA==.',
Kb='Kbilly:BAABLgAECn9EAAIKAAkJVyIpBgBOAwAKAAkJVyIpBgBOAwAAAA==.',
Ke='Kegger:BAAALgAECgEJAQAAAA==.Keirani:BAAALgAECgEJAQAAAA==.Keylerin:BAACLgAFFH8eAAISAAYJlSNzDQC7AQASAAYJlSNzDQC7AQAuAAQKfyEAAhIACQmAGkgTAH4CABIACQmAGkgTAH4CAAAA.',
Ki='Kibbik:BAACLgAFFH8NAAIeAAUJcAheIADxAAAeAAUJcAheIADxAAAuAAQKfy0AAh4ACQkyF8waAO8BAB4ACQkyF8waAO8BAAAA.Kija:BAAALgAECgYJBgAAAA==.Kitsunami:BAAALgAECgcJBgAAAA==.',
Kl='Klepal:BAAALgADCgkJCgAAAA==.Klutchshield:BAAALgAECgEJAQAAAA==.',
Kn='Kneecap:BAAALgAECgUJCQAAAA==.Knottes:BAAALgAECgIJBgAAAA==.',
Ko='Kobe:BAAALgAECgYJEwAAAA==.Koharu:BAAALgADCggJHAAAAA==.Kookykg:BAAALgAECgEJAQAAAA==.',
Kr='Krampus:BAABLgAECn85AAIaAAkJExTZCgAKAgAaAAkJExTZCgAKAgAAAA==.Kranok:BAAALgAECgYJDgAAAA==.Krim:BAAALgADCgUJBgAAAA==.Krimdevourer:BAAALgADCgYJBgAAAA==.Krimhuntress:BAAALgAECgEJAgAAAA==.',
Ku='Kunac:BAABLgAECn8WAAIEAAgJTBbpIQDjAQAEAAgJTBbpIQDjAQAAAA==.',
Ky='Kynessa:BAAALgAECgYJEQAAAA==.Kyrun:BAABLgAECn8uAAIaAAkJSw0oEgCTAQAaAAkJSw0oEgCTAQAAAA==.Kyuutips:BAAALgAECgEJAQAAAA==.',
['Kã']='Kãne:BAACLgAFFH8JAAIbAAIJ+AznUwB6AAAbAAIJ+AznUwB6AAAuAAQKfyQAAxsACQmFEQIsAI0BABsACQmFEQIsAI0BAAwAAgm9Bpo4AFQAAAAA.',
La='Lamoran:BAAALgADCgkJDwAAAA==.Lannes:BAAALgAECgEJAwAAAA==.Lapz:BAAALgAECgkJEQAAAA==.Lavetra:BAAALgAECgMJBAAAAA==.Lazerdinger:BAAALgAECgEJAQAAAA==.',
Le='Legendary:BAACLgAFFH8IAAIPAAIJ0h2PEAB+AAAPAAIJ0h2PEAB+AAAuAAQKfxQAAg8ACQlbIMQDANcCAA8ACQlbIMQDANcCAAAA.Lethran:BAAALgAECgYJCQAAAA==.',
Lh='Lhani:BAABLgAECn8oAAIFAAkJORJ7HgDRAQAFAAkJORJ7HgDRAQAAAA==.',
Li='Liadrin:BAABLgAECn8eAAIPAAkJzRZ0DwDNAQAPAAkJzRZ0DwDNAQAAAA==.Lie:BAABLgAECn8eAAIMAAgJjw9LCgB7AQAMAAgJjw9LCgB7AQAAAA==.Liliana:BAAALgADCgkJNwAAAA==.Lirrasha:BAAALgADCgYJDwAAAA==.',
Ll='Llyrael:BAABLgAECn8eAAMFAAkJ/grFKgByAQAFAAkJ/grFKgByAQAeAAIJxAOilgAjAAAAAA==.',
Lo='Lolineverdie:BAABLgAECn8aAAMCAAkJ4gqUWgAoAQACAAkJ4gqUWgAoAQAUAAYJnQI1bQBvAAAAAA==.',
Lu='Luna:BAABLgAECn8iAAMFAAgJEQrzLQCNAQAFAAgJEQrzLQCNAQAeAAgJ1QcBOwAmAQAAAA==.',
Ly='Lyrev:BAAALgAECgYJEwAAAA==.',
['Ló']='Lórien:BAAALgADCgIJAgAAAA==.',
Ma='Macaoidh:BAAALgAECgYJBgAAAA==.Maddeleine:BAABLgAECn8jAAQFAAgJlhWpGAAHAgAFAAgJlhWpGAAHAgAeAAMJzRDBWwCnAAAmAAQJtAriVwCgAAAAAA==.Magicdemon:BAABLgAECn83AAMOAAkJ2iVRCQCVAgAOAAkJpyVRCQCVAgARAAgJnSCeHQBjAgAAAA==.Magichunter:BAAALgAECgEJAQABLgAECgkJNwAOANolAA==.Makall:BAAALgADCgEJAQAAAA==.Makanoa:BAAALgAECgMJBAAAAA==.Malaah:BAABLgAECn9BAAIXAAkJvhWgHgDtAQAXAAkJvhWgHgDtAQAAAA==.Malafar:BAAALgAFFAIJAwAAAA==.Malatrixx:BAAALgAECggJCQAAAA==.Maldiriel:BAAALgAECggJCAAAAA==.Mallikus:BAAALgADCgkJCgAAAA==.Manofsecks:BAAALgAECgQJDAAAAA==.Mansuno:BAAALgAECgcJBwAAAA==.Mapachote:BAABLgAECn8vAAIlAAgJ6B3MBABhAgAlAAgJ6B3MBABhAgAAAA==.Marodin:BAAALgADCgkJOAAAAA==.Marthaiden:BAAALgAECgkJDgAAAA==.Maryjaina:BAAALgADCgYJBgAAAA==.Maully:BAAALgAECgEJAQAAAA==.Mavastus:BAAALgADCgcJBwAAAA==.Mazozul:BAABLgAECn85AAQmAAkJ1RaAGAAPAgAmAAgJTBWAGAAPAgAFAAUJ/BRgQADsAAAeAAYJvg0+TQDbAAAAAA==.',
Me='Meatbaal:BAAALgADCgYJCAAAAA==.Melinaria:BAABLgAECn8oAAMeAAkJMBVBHADjAQAeAAkJMBVBHADjAQAmAAEJ6gFXiQAhAAAAAA==.Melisondraa:BAAALgADCgkJCQAAAA==.Meow:BAAALgADCgQJBAAAAA==.Merkala:BAAALgADCgYJCQAAAA==.Metalbot:BAAALgADCgkJCQAAAA==.',
Mi='Miarose:BAAALgAECgUJBgAAAA==.Miggydogg:BAAALgAECgUJCwAAAA==.Mileta:BAABLgAECn8bAAIUAAkJSRfnEgA+AgAUAAkJSRfnEgA+AgAAAA==.Mimic:BAAALgAECgIJAgAAAA==.Minthammer:BAAALgAECgIJBAABLgAFFAIJBAABAAAAAA==.Mirthias:BAAALgAECgMJAwAAAA==.Mistlock:BAAALgAECgQJBAAAAA==.Mistylady:BAAALgAECgIJAgAAAA==.',
Mj='Mjöllnir:BAABLgAECn8UAAIXAAcJpgnCQwA6AQAXAAcJpgnCQwA6AQAAAA==.',
Mo='Monki:BAAALgAFFAEJAQAAAA==.Moozohar:BAAALgADCgEJAQAAAA==.Morgorra:BAAALgAECgMJBwAAAA==.Mormekil:BAAALgAECgIJAgAAAA==.Morvila:BAAALgAECgMJAwAAAA==.Mote:BAABLgAECn8oAAMeAAkJwRCnHgDQAQAeAAkJwRCnHgDQAQAmAAcJUxf3HwDNAQAAAA==.',
Mu='Muertes:BAAALgAECgEJAQAAAA==.Multidollar:BAAALgADCgUJBQABLgAFFAUJEQAVAKIVAA==.Muminah:BAAALgAECgMJBgAAAA==.',
['Mô']='Môlly:BAACLgAFFH8NAAIFAAUJQR6WCgCiAQAFAAUJQR6WCgCiAQAuAAQKfysAAgUACQkGIZUFAPYCAAUACQkGIZUFAPYCAAAA.',
Na='Narnluz:BAABLgAECn8dAAIFAAgJfBeeGQD+AQAFAAgJfBeeGQD+AQAAAA==.Nastiepastie:BAAALgADCgYJBgAAAA==.Nazor:BAABLgAECn8nAAIRAAgJ1xnvPwDJAQARAAgJ1xnvPwDJAQAAAA==.',
Ne='Necronic:BAAALgADCgYJCwAAAA==.Necroreign:BAABLgAECn9IAAIOAAkJZB4YBwDCAgAOAAkJZB4YBwDCAgAAAA==.Neith:BAAALgADCgMJAwAAAA==.Nemera:BAAALgADCgYJCAAAAA==.Nervous:BAABLgAFFH8JAAIKAAMJ0SKpMAAfAQAKAAMJ0SKpMAAfAQAAAA==.Nessee:BAAALgAECgYJEgAAAA==.',
Ni='Niall:BAABLgAECn8yAAIQAAkJ3CEtAwDnAgAQAAkJ3CEtAwDnAgAAAA==.Nilithis:BAABLgAECn8rAAMHAAkJeRkCLgAgAgAHAAkJCxkCLgAgAgAIAAQJGxMEIQCmAAAAAA==.Niú:BAAALgADCgYJBgAAAA==.',
No='Nozmua:BAAALgADCgkJDgAAAA==.',
Ny='Nyghtchyld:BAAALgAECgcJEgAAAA==.Nyxlumina:BAAALgAECgIJAgAAAA==.',
['Né']='Néssima:BAABLgAECn8hAAMJAAkJ0RVXbACVAQAJAAkJZw5XbACVAQAPAAUJYhuaIwDrAAAAAA==.',
Oa='Oak:BAAALgAECgEJBQAAAA==.Oathfinder:BAAALgAECgcJEAAAAA==.',
Oc='Occurrence:BAABLgAECn8VAAMCAAgJ2gWHggC0AAACAAcJBwSHggC0AAAUAAEJZwLoowAeAAAAAA==.Octalexane:BAAALgAECgUJBgAAAA==.',
Om='Omalu:BAAALgAECgEJAQABLgAECggJHgAMAI8PAA==.',
On='Onebuttonman:BAAALgADCgYJBgAAAA==.Onimusha:BAAALgAECgMJAwAAAA==.',
Or='Ortalbem:BAACLgAFFH8GAAIgAAIJeBOOngCPAAAgAAIJeBOOngCPAAAuAAQKfzoAAiAACQkXI/IRAO4CACAACQkXI/IRAO4CAAAA.',
Ov='Ovi:BAAALgADCgIJAgAAAA==.',
Pa='Pandariee:BAABLgAECn8VAAIdAAgJYw23fABqAQAdAAgJYw23fABqAQAAAA==.Pangsh:BAABLgAFFH8IAAIhAAMJBAWoQACjAAAhAAMJBAWoQACjAAAAAA==.Parzval:BAAALgAECgEJAgAAAA==.Paxgor:BAAALgAECgEJAQAAAA==.',
Pe='Pendaemonia:BAABLgAECn82AAIOAAkJuRZ+EgAFAgAOAAkJuRZ+EgAFAgAAAA==.Penelopie:BAAALgADCgYJBgAAAA==.Percfirdy:BAAALgADCgUJBQAAAA==.',
Ph='Pherix:BAABLgAECn8cAAIeAAcJ1SC+FwAKAgAeAAcJ1SC+FwAKAgAAAA==.Phiirys:BAAALgAECgEJAQAAAA==.',
Pi='Picaso:BAAALgADCgEJAQAAAA==.Pight:BAAALgAECggJEAABLgAECggJHgAMAI8PAA==.',
Po='Poomacha:BAABLgAECn8qAAIVAAgJRhXiSgDBAQAVAAgJRhXiSgDBAQAAAA==.Popstar:BAAALgAECgEJAQAAAA==.',
Pu='Puffthemagic:BAAALgADCgYJCAAAAA==.Punishêr:BAAALgADCgMJAwABLgAECgkJDgABAAAAAA==.',
Py='Pyree:BAABLgAECn8kAAMbAAkJgxCKLACLAQAbAAkJ4w+KLACLAQAMAAcJaAm0GwBvAAAAAA==.Pyxrin:BAAALgAECgcJBwAAAA==.',
['Pø']='Pøë:BAAALgAECgkJEwABLgAFFAMJCQAGAEsNAA==.',
Qu='Qu:BAAALgAFFAIJBAABLgAFFAMJCAAQAHsZAQ==.',
Qv='Qveemcorkie:BAAALgAECgEJAQAAAA==.',
['Qí']='Qín:BAAALgADCgUJAwAAAA==.',
Ra='Radagust:BAAALgAECgQJBAAAAA==.Radcat:BAAALgAECgEJBAAAAA==.Raenne:BAAALgAECgMJBQAAAA==.Ragebait:BAAALgADCgIJAgAAAA==.Rainfall:BAAALgAECgEJAgAAAA==.Raistlain:BAAALgAECgYJDwAAAA==.Raitha:BAAALgADCgUJCAAAAA==.Ralli:BAACLgAFFH8HAAIRAAMJIBvXTgAAAQARAAMJIBvXTgAAAQAuAAQKfyoAAhEACAmiGa8zAPcBABEACAmiGa8zAPcBAAAA.Rallsdemon:BAAALgAECgQJBAABLgAECgcJCgABAAAAAA==.Rallsdk:BAAALgAECgcJCgAAAA==.Rallsodins:BAAALgAECgYJBgABLgAECgcJCgABAAAAAA==.Randomguy:BAACLgAFFH8MAAISAAQJ9RnFFQBeAQASAAQJ9RnFFQBeAQAuAAQKfzgAAhIACQnYJT0CADsDABIACQnYJT0CADsDAAAA.Ranulf:BAAALgAECgQJBgAAAA==.Ratava:BAAALgAECgUJBQAAAA==.Ratboy:BAEALgAECgEJAQABLgAECgkJMgAmABwjAA==.Ratrot:BAABLgAECn8qAAIKAAgJKh5tEwCxAgAKAAgJKh5tEwCxAgAAAA==.Ratsdead:BAAALgAECgEJAQAAAA==.Razenath:BAAALgADCgcJDAAAAA==.',
Re='Reddemon:BAAALgAECgEJAQAAAA==.Reinhardt:BAAALgADCgYJBgAAAA==.Rekrella:BAAALgADCgUJBQAAAA==.Reldarus:BAEBLgAECn8yAAMmAAkJHCPUAgCBAwAmAAkJHCPUAgCBAwAFAAQJ+hr8RAAlAQAAAA==.Rena:BAAALgADCgcJBwAAAA==.Rendia:BAAALgADCgMJAwAAAA==.Renik:BAAALgADCgIJAQAAAA==.Revennek:BAAALgAECgUJCgAAAA==.Reverence:BAABLgAECn8eAAIJAAkJ8A36YgCqAQAJAAkJ8A36YgCqAQAAAA==.Revilation:BAABLgAECn8cAAIPAAkJYBPZEwCOAQAPAAkJYBPZEwCOAQAAAA==.Rezjyk:BAAALgAECgYJCAABLgAECgkJNAAJANwcAA==.Rezzyk:BAABLgAECn80AAIJAAkJ3Bw+GgCmAgAJAAkJ3Bw+GgCmAgAAAA==.',
Rh='Rhonus:BAAALgAECgEJAQAAAA==.Rhyxali:BAABLgAECn8gAAQIAAgJfgxwEQAvAQAIAAgJfgxwEQAvAQAGAAYJLAdRHADcAAAHAAQJ5AHK+QBmAAAAAA==.',
Ri='Riidefi:BAAALgADCgMJAwABLgAECgkJAwABAAAAAA==.Riis:BAAALgAECgYJDAAAAA==.Riiselock:BAABLgAECn8tAAMHAAgJIR5CNwAvAgAHAAcJyR1CNwAvAgAIAAQJFBwNGADhAAAAAA==.Riiwind:BAAALgADCgQJBAABLgAECgkJAwABAAAAAA==.Riktade:BAAALgADCgYJBgAAAA==.Rilight:BAAALgAECgMJAwABLgAECgkJAwABAAAAAA==.Riptidepod:BAABLgAECn8gAAMKAAkJ5QhgVQBgAQAKAAkJ5QhgVQBgAQAXAAIJ3gJ9wQAcAAAAAA==.',
Ro='Robbiebrews:BAAALgADCgUJBQAAAA==.Robear:BAAALgAECgEJAQAAAA==.Robeart:BAAALgAECgEJAgAAAA==.Rowin:BAAALgADCgUJBQAAAA==.',
Ru='Ruddigore:BAAALgAECgEJAQAAAA==.Ruubyy:BAAALgAECgEJAQAAAA==.',
Ry='Rynley:BAABLgAECn8WAAMSAAUJASEKJwDAAQASAAUJASEKJwDAAQAnAAIJWRH4GwBtAAAAAA==.',
Sa='Sacredscales:BAABLgAECn8hAAMFAAkJtR5kCwCaAgAFAAcJ3yRkCwCaAgAeAAcJtRSGKgCGAQAAAA==.Sagerremeseb:BAAALgAECgQJCQAAAA==.Sakii:BAABLgAECn8lAAIRAAkJJRIFOgDfAQARAAkJJRIFOgDfAQAAAA==.Salera:BAAALgADCgQJBAAAAA==.Salvion:BAAALgAECgcJAQABLgAECgkJJwARANcZAA==.Samvimes:BAABLgAECn9CAAIJAAkJmBIcAQDYAQAJAAkJmBIcAQDYAQAAAA==.Sangreene:BAABLgAECn8dAAIeAAgJRxqFEwBYAgAeAAgJRxqFEwBYAgAAAA==.Sargis:BAACLgAFFH8IAAIJAAMJkRhjXQD1AAAJAAMJkRhjXQD1AAAuAAQKf0wAAwkACQmnI+YIACMDAAkACQmnI+YIACMDAAsACAnHG1sbACkCAAAA.Sarial:BAAALgADCgMJAwAAAA==.',
Sc='Schrödinger:BAAALgAECgYJDwABLgAECgkJGQAPAO0YAA==.Sciblasts:BAAALgADCgEJAQABLgAECgYJEAABAAAAAA==.Scott:BAACLgAFFH8oAAIRAAgJxyE3BgCwAgARAAgJxyE3BgCwAgAuAAQKf0YAAhEACQmaJnUAAO4DABEACQmaJnUAAO4DAAAA.Scratchh:BAABLgAECn8dAAIhAAgJlAstNgB0AQAhAAgJlAstNgB0AQAAAA==.',
Se='Searalsa:BAAALgAECgUJCAABLgAFFAQJDAAaAFIJAA==.Sentis:BAABLgAECn8fAAIUAAgJOgfBRAD5AAAUAAgJOgfBRAD5AAAAAA==.',
Sh='Shadowbrooks:BAAALgAECgIJAgAAAA==.Shadowgiver:BAAALgADCgcJDwAAAA==.Shadowsdemon:BAAALgADCgEJAQAAAA==.Shadowsworn:BAAALgAECgEJAQAAAA==.Shagol:BAAALgAECgQJBwAAAA==.Shalriss:BAABLgAECn8nAAIeAAkJCBtLEABZAgAeAAkJCBtLEABZAgAAAA==.Shamemoon:BAABLgAECn8fAAIRAAkJjhdYLwAJAgARAAkJjhdYLwAJAgAAAA==.Shamunroe:BAABLgAECn8pAAMKAAkJMAfAYAA5AQAKAAkJMAfAYAA5AQAXAAUJkxKwWgDZAAAAAA==.Shatterhoof:BAABLgAECn8iAAIQAAgJZAwGIQAAAQAQAAgJZAwGIQAAAQAAAA==.Shelle:BAAALgAECgYJCgAAAA==.Shiftys:BAAALgADCgUJCgABLgAFFAIJAgABAAAAAA==.Shingra:BAACLgAFFH8oAAIbAAYJohyaGQCYAQAbAAYJohyaGQCYAQAuAAQKfygAAhsACQnGHSoOAH8CABsACQnGHSoOAH8CAAAA.Shoof:BAAALgADCgUJBQAAAA==.',
Si='Sifû:BAAALgADCgcJDgAAAA==.Sigourney:BAAALgAECgUJBQABLgAECgkJOAAfANMcAA==.Silversho:BAAALgAECgUJBQAAAA==.Silvoid:BAAALgADCgMJAwABLgAECgUJBQABAAAAAA==.Silvren:BAABLgAECn8zAAMEAAgJJhiBIADsAQAEAAgJJhiBIADsAQANAAEJvwZoRgArAAAAAA==.Sindarion:BAAALgAECgUJBQABLgAFFAEJAgABAAAAAA==.Sinnerr:BAAALgAECgEJAQAAAA==.Sinz:BAAALgAECgEJBQAAAA==.Siph:BAAALgAECgEJAQAAAA==.',
Sk='Skillidan:BAABLgAECn8nAAICAAkJQhopFQChAgACAAkJQhopFQChAgAAAA==.',
Sl='Slayde:BAAALgAECgEJAQAAAA==.Slighttrash:BAABLgAECn8qAAIfAAgJlhQnGADgAQAfAAgJlhQnGADgAQAAAA==.Sloppy:BAAALgADCgkJCgAAAA==.',
Sm='Smacka:BAAALgAECgEJAQAAAA==.Smallcrow:BAACLgAFFH8jAAMYAAgJbR6PAQB+AgAYAAgJbR6PAQB+AgAZAAEJQwvMXgBDAAAuAAQKfxYAAhgABwkuJsQHAP8CABgABwkuJsQHAP8CAAAA.Smores:BAAALgADCgkJEgAAAA==.Smøke:BAAALgAECgMJAwAAAA==.',
Sn='Snallygaster:BAAALgADCgYJDAABLgAECgkJIwAWAJ8bAA==.Snowsong:BAAALgAECgEJAQAAAA==.',
So='Soff:BAAALgAECgEJAQAAAA==.',
Sp='Spamton:BAAALgADCgEJAQAAAA==.Spectrose:BAAALgADCgEJAQAAAA==.Spirit:BAAALgAECgEJAgAAAA==.Spiro:BAAALgAFFAIJAgABLgAFFAMJCQAGAEsNAA==.Spøngè:BAAALgADCgMJAwAAAA==.',
St='Starge:BAAALgAFFAEJAgAAAA==.Starre:BAAALgAECgUJBQAAAA==.Steffey:BAABLgAECn8jAAIKAAgJOgu1YQA2AQAKAAgJOgu1YQA2AQAAAA==.Straven:BAABLgAECn8jAAIgAAgJrRR/YAC/AQAgAAgJrRR/YAC/AQAAAA==.Sturgeson:BAACLgAFFH8jAAIDAAYJaRxcCQCdAQADAAYJaRxcCQCdAQAuAAQKfx8AAgMACQlvHQcMAEsCAAMACQlvHQcMAEsCAAAA.',
Su='Sulfato:BAAALgADCgEJAQAAAA==.Sulwen:BAABLgAECn9RAAIFAAkJUhrZDACZAgAFAAkJUhrZDACZAgAAAA==.Suzakã:BAAALgAECgkJEAAAAA==.',
Sw='Sweetpotato:BAAALgADCgEJAQAAAA==.Swiftfeet:BAABLgAECn8lAAIVAAkJABRJQwDYAQAVAAkJABRJQwDYAQAAAA==.',
Sy='Syrasia:BAAALgADCgUJBQAAAA==.Syselea:BAAALgADCgEJAQAAAA==.',
['Sö']='Söranin:BAABLgAECn8dAAIZAAYJ5xiyMwCoAQAZAAYJ5xiyMwCoAQAAAA==.',
Ta='Tachichan:BAAALgAECgYJBgAAAA==.Tadum:BAAALgADCgEJAQAAAA==.Taeili:BAABLgAECn8gAAMWAAkJIhXhKAATAQAUAAgJ2BVoNgBiAQAWAAYJKxPhKAATAQAAAA==.Talisse:BAAALgADCgYJBgAAAA==.Tanequil:BAACLgAFFH8JAAICAAMJCgJuWQBnAAACAAMJCgJuWQBnAAAuAAQKfyQAAgIACQlJDNdKAHgBAAIACQlJDNdKAHgBAAAA.Taosha:BAAALgAECgcJCAAAAA==.Targaryian:BAAALgAECgMJAwAAAA==.Tav:BAAALgADCgUJBQAAAA==.Taylea:BAABLgAECn8WAAIgAAcJpA9ZtQAZAQAgAAcJpA9ZtQAZAQABLgAECgkJJgAJAKEfAA==.',
Te='Techromancer:BAAALgAECgYJCAABLgAECgcJHAAeANUgAA==.Telleria:BAAALgAECgIJAgAAAA==.Tem:BAAALgAECgMJAwAAAA==.Tenumbras:BAAALgAECgYJDAAAAA==.Terraclaw:BAAALgADCgUJBwAAAA==.Terrasia:BAAALgADCgYJBgAAAA==.Terrigino:BAAALgAECgUJAwAAAA==.',
Th='Thanatias:BAABLgAECn8aAAIcAAkJmhR/FgC1AQAcAAkJmhR/FgC1AQAAAA==.Thantasia:BAABLgAECn8WAAIgAAcJogN61gDoAAAgAAcJogN61gDoAAAAAA==.Thauras:BAAALgADCgcJFwAAAA==.Theeslan:BAABLgAECn8kAAIeAAkJ1QOHRAD8AAAeAAkJ1QOHRAD8AAAAAA==.Thokdar:BAAALgAECgUJBQAAAA==.Thom:BAACLgAFFH8MAAIjAAUJihAmEQALAQAjAAUJihAmEQALAQAuAAQKfysAAyMACQksJOcAABwDACMACQksJOcAABwDAB0ABgmoDjmxACABAAAA.Thør:BAAALgADCgcJDgAAAA==.',
Ti='Tiernay:BAAALgADCgEJAQAAAA==.Tifà:BAAALgAECgUJCAAAAA==.Timothy:BAABLgAECn8bAAIOAAkJ7Bg1EgAJAgAOAAkJ7Bg1EgAJAgAAAA==.Timothyjohn:BAAALgAECgEJAQAAAA==.Tinkphooey:BAAALgAECgYJCwAAAA==.Tinton:BAAALgADCgEJAQAAAA==.',
To='Toishi:BAAALgAECgEJAQAAAA==.Tormmok:BAAALgAECgYJDAAAAA==.Toshiden:BAAALgADCgEJAgAAAA==.Toshindo:BAAALgAECgEJAgAAAA==.',
Tr='Traazz:BAAALgAECgkJAwAAAA==.Trashpally:BAAALgAECgEJAgAAAA==.Tremèndor:BAAALgADCgMJAwAAAA==.Trey:BAAALgAECgEJAQAAAA==.Tristra:BAAALgAECgQJBAAAAA==.',
Ts='Tsuruga:BAABLgAECn85AAIhAAkJQA5fIgCWAQAhAAkJQA5fIgCWAQAAAA==.',
Tu='Turkwise:BAABLgAECn85AAMWAAkJVx2ABgCWAgAWAAkJVx2ABgCWAgAQAAQJCBGsHgDuAAAAAA==.',
Ty='Tycondrius:BAAALgAECgEJAQAAAA==.Tyresh:BAAALgAECgEJAQAAAA==.Tyrinor:BAAALgADCgUJBQAAAA==.',
Ul='Ulogasm:BAAALgADCgkJCgAAAA==.',
Us='Usami:BAAALgAECgEJAQAAAA==.',
Ut='Utako:BAAALgADCgUJCgAAAA==.',
Uv='Uvari:BAABLgAECn8bAAIFAAgJ1w6iKACBAQAFAAgJ1w6iKACBAQAAAA==.',
Va='Vaclar:BAAALgAFFAMJAwABLgAFFAUJDQAYAK8hAA==.Valhalaa:BAAALgADCgYJBgAAAA==.Valkryee:BAAALgAECggJCQAAAA==.Valton:BAACLgAFFH8NAAIYAAUJryHNCwBnAQAYAAUJryHNCwBnAQAuAAQKf0UAAhgACQmEJsQAAHoDABgACQmEJsQAAHoDAAAA.Vanillanice:BAAALgAECggJEAAAAA==.Varrfife:BAAALgAECgQJBAAAAA==.Vaxaldan:BAABLgAECn85AAIcAAkJLQ6PHgBiAQAcAAkJLQ6PHgBiAQAAAA==.',
Ve='Velestre:BAAALgAECgUJBQAAAA==.Velithera:BAAALgADCgMJAwAAAA==.Vellithe:BAABLgAECn8iAAIJAAcJnQ86AwAWAQAJAAcJnQ86AwAWAQAAAA==.Venj:BAAALgAECgUJBgAAAA==.Verhmax:BAAALgADCgYJCwAAAA==.Verton:BAAALgADCgYJBgAAAA==.Vestrae:BAACLgAFFH8KAAMCAAUJIgpRLQD/AAACAAUJIgpRLQD/AAAUAAEJSQHXVgAmAAAuAAQKfyYAAgIACQnwHG8TAJoCAAIACQnwHG8TAJoCAAAA.Vex:BAABLgAECn8YAAIHAAkJbxr1JgBBAgAHAAkJbxr1JgBBAgAAAA==.',
Vi='Vianel:BAAALgADCggJCAAAAA==.Vilten:BAAALgAECgQJCwAAAA==.Virus:BAAALgAECgkJCQAAAA==.',
Vo='Vodash:BAABLgAECn8iAAIKAAgJnRi3MgDoAQAKAAgJnRi3MgDoAQABLgAECgkJRwACAB8QAA==.Voidwrench:BAAALgADCgYJBgAAAA==.Vostok:BAABLgAECn8eAAIHAAgJOBwrSQC+AQAHAAgJOBwrSQC+AQAAAA==.',
Wa='Wage:BAAALgADCgQJBQAAAA==.Warmth:BAAALgADCgIJAwAAAA==.',
We='Weekend:BAAALgADCgkJDwAAAA==.Wetsock:BAAALgAECgYJBwAAAA==.',
Wi='Wikket:BAABLgAECn85AAMUAAkJPRyvDQB/AgAUAAkJPRyvDQB/AgACAAgJ3AMldwDQAAAAAA==.',
Wo='Wolvesbayne:BAAALgAECgEJAQAAAA==.',
Wy='Wyelie:BAAALgAECgYJDgAAAA==.Wynono:BAAALgADCgcJBwAAAA==.',
Xd='Xdeadlysinz:BAAALgAECgcJDwAAAA==.',
Xo='Xotha:BAABLgAECn9BAAIRAAkJqB5mFQCYAgARAAkJqB5mFQCYAgAAAA==.',
Xu='Xuen:BAAALgAFFAEJAwAAAA==.',
Xy='Xythera:BAACLgAFFH8HAAIRAAQJARloYADPAAARAAQJARloYADPAAAuAAQKfx8AAxEACQmKIPYVANMCABEACQmKIPYVANMCACIAAQmwEH80ADIAAAAA.',
Ye='Yeah:BAAALgADCgYJBgABLgAFFAMJBwAJAEwMAA==.',
Yi='Yinosai:BAAALgAECgYJCAAAAA==.',
Yo='Yougot:BAAALgADCgcJCgAAAA==.',
Yu='Yuji:BAABLgAECn8hAAIIAAYJaR2+CwCEAQAIAAYJaR2+CwCEAQAAAA==.Yukì:BAAALgADCgMJAwAAAA==.Yurie:BAAALgAECgIJAgAAAA==.',
Yv='Yvonna:BAAALgADCgEJAQAAAA==.',
Za='Zaega:BAAALgADCgQJBAABLgAECgkJJgAJAKEfAA==.Zahlee:BAAALgAECgQJBAAAAA==.Zaldin:BAAALgADCgYJCgAAAA==.Zalirina:BAAALgADCgIJAgAAAA==.Zanka:BAAALgAECgIJAgAAAA==.Zaridruid:BAAALgAECgkJCgAAAA==.Zarisedra:BAACLgAFFH8pAAMLAAYJiR9dCQAlAgALAAYJiR9dCQAlAgAJAAEJXgDaOwA2AAAuAAQKfxgAAwsACQkwF8kpAOMBAAsACAkGGMkpAOMBAAkAAQktBuw9ATUAAAAA.Zarissena:BAAALgAECgYJAwAAAA==.Zarris:BAAALgADCgUJDAAAAA==.',
Ze='Zennith:BAAALgADCgMJAwAAAA==.Zernacho:BAABLgAECn8gAAQFAAkJjBqgHwDHAQAFAAYJJhygHwDHAQAeAAcJ+hFBLgBvAQAmAAMJTRMSVACxAAAAAA==.Zerogasm:BAABLgAECn8YAAIVAAkJAhZuMAAaAgAVAAkJAhZuMAAaAgAAAA==.Zerolicious:BAAALgAECgQJCAAAAA==.Zeromojo:BAAALgAECgUJBQAAAA==.Zerostarbear:BAAALgAECgEJAQAAAA==.Zerozaddy:BAAALgAECgUJBgAAAA==.Zevvo:BAABLgAECn8wAAIEAAkJECFUCgC/AgAEAAkJECFUCgC/AgAAAA==.',
Zi='Ziggysundust:BAAALgADCgMJAwAAAA==.',
Zo='Zoraji:BAABLgAECn86AAIhAAkJdhryDgBLAgAhAAkJdhryDgBLAgAAAA==.',
Zu='Zuganova:BAABLgAFFH8SAAMmAAUJDQjIJAAnAQAmAAUJ4QfIJAAnAQAFAAEJ8whwFgA8AAAAAA==.Zuggar:BAABLgAECn8fAAIEAAcJVwjNUgD/AAAEAAcJVwjNUgD/AAAAAA==.',
Zy='Zynhammer:BAABLgAECn8oAAMRAAgJgxFhXQCJAQARAAgJgxFhXQCJAQAOAAEJawbLeQAmAAAAAA==.',
['Év']='Évangeline:BAAALgADCgcJBwAAAA==.',
['Ëb']='Ëbony:BAABLgAFFH8MAAIVAAQJNRoHMABQAQAVAAQJNRoHMABQAQAAAA==.',
['Ëd']='Ëdën:BAAALgAECgcJEwAAAA==.',
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
