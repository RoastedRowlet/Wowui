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

local lookup = {'Unknown-Unknown','Druid-Restoration','Warrior-Protection','Warrior-Fury','Priest-Holy','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Paladin-Retribution','Shaman-Restoration','Paladin-Holy','Evoker-Devastation','Warrior-Arms','DemonHunter-Havoc','Druid-Feral','DemonHunter-Devourer','Rogue-Subtlety','Rogue-Assassination','Druid-Balance','Paladin-Protection','Hunter-BeastMastery','Druid-Guardian','Shaman-Elemental','Monk-Windwalker','Monk-Mistweaver','Shaman-Enhancement','Evoker-Augmentation','DeathKnight-Blood','DeathKnight-Unholy','Priest-Shadow','Hunter-Survival','Mage-Frost','Monk-Brewmaster','DemonHunter-Vengeance','DeathKnight-Frost','Mage-Arcane','Hunter-Marksmanship','Priest-Discipline','Rogue-Outlaw',}
local provider = {region='US',realm='ShadowCouncil',name='US',type='weekly',zone=46,date='2026-07-05',data={Ab='Abear:BAAALgAECgQJBQAAAA==.Abrocklock:BAAALgAECgYJCQAAAA==.',
Ac='Achilês:BAAALgAECgEJAQABLgAFFAEJAQABAAAAAA==.',
Ad='Adaluna:BAABLgAECn8XAAICAAkJ2wmSUgBFAQACAAkJ2wmSUgBFAQAAAA==.Adorabull:BAACLgAFFH8JAAIDAAMJRyLxEAAnAQADAAMJRyLxEAAnAQAuAAQKfygAAwMACQkOIroGAJwCAAMACQkOIroGAJwCAAQAAQnQBhGvACwAAAAA.Adrain:BAAALgAECgQJCwAAAA==.Adwae:BAAALgAECgIJAgAAAA==.',
Ae='Aeiou:BAAALgAECgUJBQAAAA==.Aelyn:BAAALgAECgcJDwAAAA==.Aevelee:BAAALgAECggJEwAAAA==.Aevick:BAAALgAECgQJBQAAAA==.',
Al='Alastair:BAAALgADCgEJAQAAAA==.Aleeta:BAAALgAECgQJBgAAAA==.Allucard:BAAALgAECgkJAgAAAA==.',
Am='Amapanda:BAAALgAECgkJCQAAAA==.Amaria:BAAALgAECgkJBgAAAA==.Amoracchius:BAAALgADCgMJAwAAAA==.',
An='Angelstörm:BAACLgAFFH8IAAIFAAIJPwy+LABkAAAFAAIJPwy+LABkAAAuAAQKf0AAAgUACQloGe4SAEUCAAUACQloGe4SAEUCAAAA.Anjali:BAAALgAECgEJAQAAAA==.Anorili:BAAALgADCgYJBgAAAA==.Antarias:BAABLgAECn8eAAQGAAkJQhrTEQBIAQAGAAUJDSPTEQBIAQAHAAcJqhJpogD7AAAIAAMJjhi/JwB5AAAAAA==.Antarion:BAAALgAECgQJBAAAAA==.',
Ap='Applevendor:BAAALgADCgUJBQAAAA==.',
Ar='Arahil:BAAALgAECgQJBwAAAA==.Arcanio:BAAALgADCgQJBAAAAA==.Arcaux:BAAALgADCggJDgAAAA==.Arckenon:BAACLgAFFH8IAAIJAAMJQh2eWQD9AAAJAAMJQh2eWQD9AAAuAAQKf0EAAgkACQlwJKcIACUDAAkACQlwJKcIACUDAAAA.',
As='Ashdorei:BAAALgADCgMJAwAAAA==.Ashog:BAABLgAECn8XAAIKAAcJGRYcQACtAQAKAAcJGRYcQACtAQAAAA==.Astranos:BAAALgAECgEJAQABLgAECgkJRwACAB8QAA==.',
At='Athanyr:BAABLgAECn8sAAICAAgJXyU6BgBUAwACAAgJXyU6BgBUAwAAAA==.Atillis:BAAALgAECgUJBQAAAA==.',
Au='Augmentation:BAAALgAECgEJAQAAAA==.Austenpally:BAABLgAECn8hAAMJAAkJ3RhicACNAQAJAAcJ3hZicACNAQALAAcJkRGgNwBvAQAAAA==.',
Av='Aveycado:BAAALgAECgIJAgAAAA==.Aviane:BAAALgAECgYJBgAAAA==.',
Ax='Axeflack:BAAALgAECgEJAQAAAA==.Axegor:BAAALgADCgMJAwAAAA==.',
Az='Azrall:BAAALgAECgIJAgAAAA==.',
Ba='Bacuda:BAAALgAECgYJEAAAAA==.Badwolf:BAAALgADCgQJBAAAAA==.Balkris:BAAALgAECgEJAgABLgAECggJHgAMAI8PAA==.Baratheon:BAABLgAECn8VAAMNAAkJCg+6FwCdAQANAAkJNg66FwCdAQAEAAcJXgbYXQA4AQAAAA==.Batya:BAAALgAECgIJAgAAAA==.',
Be='Beartooth:BAAALgADCgUJBQAAAA==.Bearynice:BAAALgADCgUJBQAAAA==.Beggles:BAAALgADCgEJAQAAAA==.Bereit:BAAALgADCgcJBgAAAA==.',
Bi='Biancadelrio:BAABLgAECn8lAAIOAAgJYhGYIQBsAQAOAAgJYhGYIQBsAQAAAA==.Bigboned:BAAALgADCgEJAQABLgAECgkJIwAJAAYaAA==.Bigmode:BAAALgADCgYJBgAAAA==.Bigwolves:BAAALgADCgIJAgAAAA==.',
Bj='Bjorrglbrgl:BAABLgAFFH8JAAIPAAMJexlPDQDiAAAPAAMJexlPDQDiAAAAAA==.',
Bl='Blackmask:BAAALgADCgUJCAAAAA==.Blackzune:BAAALgAECgEJAQAAAA==.Bladekrim:BAAALgAECgEJAgAAAA==.Blindashunae:BAACLgAFFH8hAAIQAAgJGhCbGwDVAQAQAAgJGhCbGwDVAQAuAAQKfxYAAhAACQlQHikVANgCABAACQlQHikVANgCAAAA.Blindkungfu:BAAALgAECgQJBAAAAA==.Bloodrun:BAAALgADCgkJCgAAAA==.Blook:BAABLgAECn8UAAMRAAgJThXzIACOAQARAAgJThXzIACOAQASAAEJkgg2HwA3AAAAAA==.Bluehazey:BAAALgAECgkJEQAAAA==.Blueleader:BAAALgAECgQJBAAAAA==.Bläz:BAAALgAECgEJAQAAAA==.',
Bo='Boomhammer:BAAALgAFFAIJBAAAAA==.Bootsy:BAAALgAECgcJBAAAAA==.Bopit:BAABLgAECn8XAAMJAAkJ+g6nnwBAAQAJAAYJeA6nnwBAAQALAAkJ9AzJUAA2AQAAAA==.Botia:BAABLgAECn8XAAITAAcJ3gUwYACYAAATAAcJ3gUwYACYAAAAAA==.',
Br='Braedia:BAAALgAECgEJAQAAAA==.Bruhh:BAAALgAECgYJBwAAAA==.Brunnera:BAAALgAECgIJAwAAAA==.Bruuenor:BAAALgAECgYJCAAAAA==.Bruul:BAABLgAECn8mAAQJAAgJ0xmAOgAZAgAJAAgJ0xmAOgAZAgALAAQJ3Q3HXADCAAAUAAEJ1RBEUQAuAAAAAA==.Brynjolf:BAAALgAECgUJCQAAAA==.',
Ca='Caenji:BAABLgAECn8XAAIVAAkJOAsIaQBwAQAVAAkJOAsIaQBwAQAAAA==.Carcharoth:BAABLgAECn8nAAMIAAkJlBjuCQCnAQAIAAcJNRruCQCnAQAHAAYJqBCRrgDmAAAAAA==.Carmelina:BAABLgAECn8oAAIOAAgJJBzBDgA6AgAOAAgJJBzBDgA6AgAAAA==.Catrixona:BAAALgAECgUJCAAAAA==.Caylan:BAAALgADCgQJBAAAAA==.',
Ch='Chadgar:BAAALgADCgIJAgAAAA==.Chaoscaster:BAAALgADCgkJCQABLgAECgYJBgABAAAAAA==.Charroth:BAAALgAECgYJCAAAAA==.Chey:BAABLgAECn9AAAIRAAkJ4iTMAgAnAwARAAkJ4iTMAgAnAwAAAA==.Chilai:BAABLgAECn8lAAIWAAkJABgwDAAeAgAWAAkJABgwDAAeAgAAAA==.Chipsahoy:BAABLgAECn8iAAMXAAkJ2x8bCgC8AgAXAAkJ2x8bCgC8AgAKAAYJdRJ3RQBsAQAAAA==.Chrîstîan:BAAALgADCgYJBgAAAA==.Chíef:BAABLgAFFH8VAAMKAAgJxB8ECQA5AgAKAAcJDiAECQA5AgAXAAMJ/gLnTwBYAAAAAA==.',
Ci='Cindrozetha:BAAALgADCgEJAQAAAA==.Citte:BAAALgAFFAEJAgAAAA==.',
Cl='Close:BAAALgADCgUJBQABLgAFFAMJCQAKANEiAA==.',
Co='Conciete:BAABLgAECn8VAAMYAAgJWhXmGgAHAgAYAAgJWhXmGgAHAgAZAAEJBAHidwARAAAAAA==.Conorix:BAAALgAECgUJCAAAAA==.Constantiine:BAAALgAECgEJAQAAAA==.Corvo:BAABLgAECn8ZAAIUAAkJ7RiNCgAhAgAUAAkJ7RiNCgAhAgAAAA==.Counselor:BAAALgAECgUJCQAAAA==.Courallie:BAAALgAECgEJAQAAAA==.',
Cr='Crataxxis:BAABLgAECn9JAAIOAAkJ+BuHCQCSAgAOAAkJ+BuHCQCSAgAAAA==.Crynos:BAAALgADCgMJAwAAAA==.Crysandra:BAAALgAECgUJBQAAAA==.',
Cy='Cydon:BAABLgAECn84AAIWAAkJvR6dBQCwAgAWAAkJvR6dBQCwAgAAAA==.',
Da='Daereth:BAAALgAECgYJCQAAAA==.Daerrith:BAAALgAECgUJCQAAAA==.Dala:BAAALgAECgUJBQAAAA==.Damienfox:BAAALgAECgQJBgAAAA==.Dana:BAAALgAFFAEJAQABLgAFFAMJDwACABIUAA==.Danellia:BAAALgADCgUJBQAAAA==.Darkreaper:BAAALgAECgQJBAAAAA==.Darrwin:BAABLgAECn8pAAMJAAgJTSDEJgBpAgAJAAgJTSDEJgBpAgAUAAQJUg7SLwCoAAAAAA==.Dawicker:BAAALgADCgYJDwAAAA==.Daylight:BAAALgAECgYJCQAAAA==.',
De='Deathspacito:BAAALgAECgEJAgAAAA==.Dedoria:BAAALgADCgUJBQAAAA==.Defacto:BAAALgADCgMJAwAAAA==.Delat:BAAALgAECgEJAQAAAA==.Delrac:BAABLgAECn8iAAIQAAgJWxFKWQB8AQAQAAgJWxFKWQB8AQAAAA==.Demonalsa:BAAALgAECgEJAgABLgAFFAQJDQAaAFIJAA==.Denathrius:BAAALgAECgIJAwABLgAFFAQJBwAQAAEZAA==.Denero:BAABLgAECn8dAAIJAAkJIx77GwCdAgAJAAkJIx77GwCdAgAAAA==.Departure:BAAALgAECgQJBwABLgAECgcJFwAOAEMcAA==.Derith:BAAALgADCgEJAQAAAA==.',
Df='Dfabness:BAACLgAFFH8KAAIYAAMJ5xDTJQC8AAAYAAMJ5xDTJQC8AAAuAAQKfyMAAhgACQnnElskAJABABgACQnnElskAJABAAAA.',
Di='Dic:BAAALgADCgIJAgABLgAECgMJAwABAAAAAA==.Diizmyster:BAAALgAECgkJBAAAAA==.',
Do='Docbush:BAAALgAECgEJAQABLgAFFAQJDgAHAPkEAA==.Docbushed:BAAALgAECgQJBAABLgAFFAQJDgAHAPkEAA==.Dogberry:BAAALgAECgEJAQAAAA==.Dotbush:BAACLgAFFH8OAAMHAAQJ+QQjbgDmAAAHAAQJ+QQjbgDmAAAIAAEJhwKhLAAzAAAuAAQKfzAABAcACQlsFc9IAMABAAcACQmVFM9IAMABAAgAAwmrDIBGAJwAAAYAAgnOEcYoAHwAAAAA.Dotspot:BAAALgADCgQJBAABLgAECgMJBwABAAAAAA==.',
Dr='Dracthayr:BAABLgAECn86AAIMAAkJZROuBgDhAQAMAAkJZROuBgDhAQAAAA==.Dragonhammer:BAACLgAFFH8LAAIJAAIJGSTpcwDMAAAJAAIJGSTpcwDMAAAuAAQKf1EAAgkACQmAJIMHADEDAAkACQmAJIMHADEDAAAA.Drakanna:BAAALgAECgIJAgAAAA==.Draxela:BAABLgAECn8gAAIbAAcJTQmhBwC0AAAbAAcJTQmhBwC0AAAAAA==.Dreaming:BAABLgAECn8wAAIcAAkJZiLBBAD7AgAcAAkJZiLBBAD7AgABLgAFFAMJCQAKANEiAA==.Drosidon:BAABLgAECn8UAAIdAAYJnAWy/QCvAAAdAAYJnAWy/QCvAAAAAA==.Drubo:BAAALgAECgIJAgAAAA==.Drx:BAAALgAECggJDwABLgAECgkJLAAXALEVAA==.',
Ea='Earsog:BAAALgADCgEJAQAAAA==.Earthenfist:BAAALgAECgEJAQAAAA==.',
Eb='Ebebebebe:BAAALgAECgEJAQAAAA==.',
Ef='Efbomb:BAAALgADCgcJBwAAAA==.',
Ei='Eitherindel:BAAALgADCgkJCgAAAA==.',
El='Elanore:BAAALgAECgUJBgAAAA==.Ellaini:BAABLgAECn8SAAIeAAgJoAtmMwBMAQAeAAgJoAtmMwBMAQAAAA==.Ellie:BAABLgAFFH8VAAIKAAQJDSAjCgBcAQAKAAQJDSAjCgBcAQAAAA==.Elseb:BAAALgAECgQJBwAAAA==.',
Em='Emberlyn:BAAALgAECgIJBQAAAA==.Emotion:BAAALgADCgYJAQABLgAFFAMJCQAKANEiAA==.',
En='Enchantrêss:BAAALgAECggJCAABLgAFFAEJAQABAAAAAA==.Endo:BAAALgAECgEJAQAAAA==.',
Er='Erenara:BAAALgAECgQJCwAAAA==.',
Ev='Evic:BAABLgAECn9HAAICAAkJHxDKNgC+AQACAAkJHxDKNgC+AQAAAA==.Evielyn:BAAALgAECgMJAwAAAA==.',
Ew='Ewson:BAAALgADCgcJCwAAAA==.',
Ex='Excrubilis:BAAALgAFFAIJBAAAAA==.',
Fa='Faandango:BAAALgAECgUJBQAAAA==.Faeleader:BAABLgAECn8aAAICAAgJVQ2PTABdAQACAAgJVQ2PTABdAQAAAA==.Faevelina:BAAALgAECgUJDAABLgAECgkJCgABAAAAAA==.Fannypacker:BAAALgAECgkJAgAAAA==.Fatshamer:BAAALgAECgYJBgAAAA==.Faytadori:BAAALgADCgEJAQAAAA==.',
Fe='Felgrrl:BAAALgAECgEJAQAAAA==.Fester:BAAALgAECgEJAQAAAA==.Feyreh:BAAALgAECgcJCAAAAA==.',
Fi='Fieona:BAAALgADCgYJCwAAAA==.Firethorns:BAAALgAECgQJBgAAAA==.Fistandilias:BAAALgADCgkJCQAAAA==.Fitzbang:BAAALgAECgUJBwAAAA==.',
Fl='Florigrowl:BAAALgAECgMJAwAAAA==.',
Fo='Forever:BAAALgAECgMJBQABLgAFFAMJCQAKANEiAA==.Formortiis:BAAALgADCgEJAQAAAA==.Forrestior:BAABLgAECn8YAAIfAAgJoiShAQBBAwAfAAgJoiShAQBBAwAAAA==.Forsthoof:BAAALgADCgYJBgAAAA==.',
Fr='Fraga:BAAALgAECgYJDgABLgAFFAUJDQAdAJkMAA==.Frailty:BAAALgAECgYJDAAAAA==.Frawst:BAAALgAECgMJAwAAAA==.Frique:BAABLgAECn8cAAIKAAYJ0x3bLAAFAgAKAAYJ0x3bLAAFAgAAAA==.Frostfingers:BAAALgAECgQJBgAAAA==.Frostyfang:BAABLgAECn8kAAMPAAgJ/xw+EwCKAQAPAAYJpCA+EwCKAQATAAQJthPLVQC5AAAAAA==.Frozenyogert:BAAALgAECgQJBAAAAA==.',
Fu='Fufula:BAAALgADCgQJBAAAAA==.Funkbot:BAAALgAECgYJDAAAAA==.Furgilicious:BAAALgAECgEJAgABLgAECgYJEAABAAAAAA==.',
['Fä']='Färshadow:BAAALgAECgEJAQAAAA==.',
Ga='Galbur:BAACLgAFFH8NAAMdAAUJmQxwgAAGAQAdAAQJmQxwgAAGAQAcAAIJ+REzPwA1AAAuAAQKfycAAx0ACQndHl8jAHgCAB0ACQnsHF8jAHgCABwACAkUFcwXAJ0BAAAA.Galdrin:BAAALgAECgkJCgAAAA==.Gaspode:BAAALgADCgcJBwAAAA==.Gassann:BAAALgAECggJDgAAAA==.',
Ge='Geers:BAABLgAECn8dAAIgAAkJ2SLsDgADAwAgAAkJ2SLsDgADAwAAAA==.Geta:BAAALgAECgQJBwABLgAECgkJIAAEAF0iAA==.Getacast:BAAALgAECgEJAQABLgAECgkJIAAEAF0iAA==.Getademon:BAAALgADCgEJAQABLgAECgkJIAAEAF0iAA==.Getaform:BAAALgAECgEJAQABLgAECgkJIAAEAF0iAA==.Getagrip:BAAALgAECgQJBgABLgAECgkJIAAEAF0iAA==.Getaheal:BAAALgAECgYJBgABLgAECgkJIAAEAF0iAA==.Getalife:BAAALgAECgIJAgABLgAECgkJIAAEAF0iAA==.Getarage:BAABLgAECn8gAAIEAAkJXSIeFACtAgAEAAkJXSIeFACtAgAAAA==.',
Gh='Ghil:BAABLgAECn8vAAMGAAkJqiMTAQADAwAGAAkJqiMTAQADAwAHAAQJnxXfvADfAAAAAA==.',
Gi='Gigawatt:BAABLgAECn8sAAMXAAkJsRUQLACVAQAXAAgJURMQLACVAQAKAAMJ9QnJpQCBAAAAAA==.Gildersleeve:BAAALgAECgQJCQAAAA==.Gilia:BAAALgAECgEJAQAAAA==.Girthfist:BAABLgAECn8WAAIhAAgJRSMIBQA5AwAhAAgJRSMIBQA5AwABLgAFFAgJGQADAN8dAA==.',
Gl='Glynixtwo:BAAALgAECgMJBQAAAA==.',
Go='Goldiwarlock:BAAALgADCgcJEAAAAA==.Goloron:BAAALgADCgkJDwAAAA==.',
Gr='Graymayn:BAABLgAECn8aAAIfAAkJ8BmrCgB0AgAfAAkJ8BmrCgB0AgAAAA==.Gremel:BAABLgAECn8mAAQWAAgJfR2lHABoAQAWAAUJLhmlHABoAQAPAAUJsBo8GQBFAQATAAMJGRznRAD5AAAAAA==.Grimdor:BAAALgAECgYJDAAAAA==.Grimflaps:BAAALgAECgMJBQAAAA==.Grimmist:BAABLgAECn8hAAIZAAcJihjOMgCsAQAZAAcJihjOMgCsAQAAAA==.',
Gu='Guloot:BAABLgAECn8bAAMKAAgJBAbBhgDQAAAKAAgJBAbBhgDQAAAXAAUJtQavhQBkAAAAAA==.Gunboyten:BAAALgAECgMJAwAAAA==.Gunderthirth:BAACLgAFFH8ZAAIDAAgJ3x08AQDnAQADAAgJ3x08AQDnAQAuAAQKfy0AAwMACQmnJKIBAGsDAAMACQmnJKIBAGsDAAQABQmMIt4uAJQBAAAA.Gurkin:BAAALgADCgEJAQAAAA==.',
Gw='Gwaeniiha:BAABLgAECn88AAIJAAkJkBQcBQDIAQAJAAkJkBQcBQDIAQAAAA==.Gward:BAAALgAECgUJBgAAAA==.Gwizz:BAABLgAECn8sAAIgAAkJnBsCMABZAgAgAAkJnBsCMABZAgAAAA==.',
Ha='Halibard:BAABLgAFFH8PAAIFAAUJCQrDFgAIAQAFAAUJCQrDFgAIAQAAAA==.Halinka:BAAALgADCgYJBgAAAA==.Handsoap:BAABLgAECn8eAAIOAAkJdA7bHwB7AQAOAAkJdA7bHwB7AQAAAA==.Haquar:BAAALgAECgQJCQAAAA==.Hardhitter:BAABLgAECn88AAQNAAkJzxlrAQCKAQANAAkJvRZrAQCKAQADAAgJfxaDAgBPAQAEAAYJJxVtCADiAAAAAA==.',
He='Hehe:BAAALgADCgQJBAAAAA==.Helldog:BAAALgAECgMJAwABLgAECgkJJQAiALYeAA==.Hellumph:BAABLgAECn8lAAIiAAkJth6/AgDJAgAiAAkJth6/AgDJAgAAAA==.Hellwraith:BAAALgADCggJDgABLgAECgkJJQAiALYeAA==.Hermesconrad:BAAALgAECgkJEwAAAA==.Hevensrath:BAABLgAECn85AAIJAAkJdx/nFgC5AgAJAAkJdx/nFgC5AgAAAA==.',
Ho='Hokuden:BAABLgAECn86AAIjAAkJGhmBCAAFAgAjAAkJGhmBCAAFAgAAAA==.Holliday:BAAALgAECgEJAgAAAA==.Holphie:BAAALgAECgUJBQAAAA==.Honina:BAAALgADCgIJAgAAAA==.Hornswaggles:BAAALgAECgQJBAAAAA==.Horsebananas:BAAALgAECgMJBgABLgAECgkJOAAfANMcAA==.',
Ht='Htari:BAAALgAFFAIJAgAAAA==.',
Hu='Huddington:BAABLgAECn8jAAIkAAkJ1RfvAgAMAgAkAAkJ1RfvAgAMAgAAAA==.Hussh:BAAALgAECgYJDAABLgAECgkJIwAJAAYaAA==.',
Hy='Hydraness:BAAALgAECgEJAQABLgAECgQJBAABAAAAAA==.',
Ia='Iamcammy:BAAALgAECgYJEAAAAA==.',
Ic='Icedragon:BAAALgAECgkJBwAAAA==.',
Ig='Igknight:BAAALgAECgMJAwABLgAFFAIJAwABAAAAAA==.',
Il='Illexi:BAAALgADCgYJBgAAAA==.',
Im='Imariz:BAAALgAECgcJBwAAAA==.Imdarkness:BAAALgAFFAEJAQAAAA==.Impquisitor:BAAALgAECgYJBwAAAA==.',
In='Indecent:BAABLgAECn8zAAQHAAkJOh3hFQCiAgAHAAkJOh3hFQCiAgAIAAYJHBd3FACnAQAGAAMJ3hQLGAC7AAAAAA==.Indeed:BAAALgAECgUJBgAAAA==.Inibble:BAAALgADCgcJBgAAAA==.',
Ir='Irozi:BAAALgAECgEJAQAAAA==.',
Is='Ishy:BAAALgAECgUJCAAAAA==.',
Ix='Ixelle:BAAALgADCgUJDQABLgAECgYJEQABAAAAAA==.',
Iz='Izomar:BAABLgAECn8gAAIgAAgJahkXTQD0AQAgAAgJahkXTQD0AQAAAA==.',
Ja='Jack:BAAALgAECgEJAQAAAA==.Jackieechan:BAAALgAECgcJBwABLgAFFAUJDwALAL8kAA==.Jackiemays:BAACLgAFFH8PAAMLAAUJvySWEQCpAQALAAQJQCaWEQCpAQAJAAIJsQFtywA1AAAuAAQKfzEAAwsACAkUJDIOALECAAsACAkUJDIOALECAAkACAlgGnY9AC8CAAAA.Jaded:BAAALgAECgUJBQAAAA==.Jaleigha:BAAALgADCgcJDgAAAA==.Jamesin:BAAALgAECgYJCAAAAA==.',
Je='Jedaii:BAAALgAECgYJBgAAAA==.Jeff:BAAALgAECgEJAwAAAA==.Jeses:BAABLgAECn8vAAIJAAkJQhaJQgD/AQAJAAkJQhaJQgD/AQAAAA==.',
Jo='Joe:BAAALgAECgEJAQAAAA==.Johmjohm:BAAALgAECgQJBAAAAA==.Jollah:BAAALgAECgUJBgAAAA==.',
Ju='Jutic:BAACLgAFFH8JAAIKAAMJ/hjIQgDcAAAKAAMJ/hjIQgDcAAAuAAQKfzoAAgoACQnOIj0IACwDAAoACQnOIj0IACwDAAAA.',
Jy='Jyssa:BAAALgADCgEJAQAAAA==.',
['Jö']='Jörmun:BAAALgAFFAIJBAAAAA==.',
Ka='Kageken:BAAALgADCgUJBQABLgAECgQJBwABAAAAAA==.Kaia:BAABLgAECn8lAAIRAAkJgA/NGADUAQARAAkJgA/NGADUAQAAAA==.Kaldrich:BAAALgAECgMJBAAAAA==.Kamoto:BAAALgAECgQJBAABLgAECgkJLAAXALEVAA==.Kanetsu:BAAALgADCgIJAgAAAA==.Kardas:BAABLgAECn8YAAMVAAkJuQdDbABpAQAVAAkJuQdDbABpAQAlAAMJ1AGLfABSAAAAAA==.Kardio:BAACLgAFFH8FAAIYAAQJ6gygKACvAAAYAAQJ6gygKACvAAAuAAQKfxoAAxgACAn+EK0rAIEBABgACAn+EK0rAIEBABkAAQkBClBnADUAAAAA.Kayj:BAAALgAECgEJAgAAAA==.Kayrina:BAAALgADCgkJCgAAAA==.Kazeer:BAABLgAECn8gAAIJAAkJJAnUmgBAAQAJAAkJJAnUmgBAAQAAAA==.',
Kb='Kbilly:BAABLgAECn9EAAIKAAkJVyIoBgBOAwAKAAkJVyIoBgBOAwAAAA==.',
Ke='Kegger:BAAALgAECgEJAQAAAA==.Keirani:BAAALgAECgEJAQAAAA==.Keylerin:BAACLgAFFH8fAAIRAAcJXR5tDQC7AQARAAcJXR5tDQC7AQAuAAQKfyEAAhEACQmAGkgTAH4CABEACQmAGkgTAH4CAAAA.',
Ki='Kibbik:BAACLgAFFH8NAAIeAAUJcAhdIADxAAAeAAUJcAhdIADxAAAuAAQKfy0AAh4ACQkyF8waAO8BAB4ACQkyF8waAO8BAAAA.Kija:BAAALgAECgYJBgAAAA==.Kitoro:BAAALgAECgEJAQAAAA==.Kitsunami:BAAALgAECgcJBgAAAA==.',
Kl='Klepal:BAAALgADCgkJCgAAAA==.Klutchshield:BAAALgAECgEJAQAAAA==.',
Kn='Kneecap:BAAALgAECgUJCQAAAA==.Knottes:BAAALgAECgIJBwAAAA==.',
Ko='Kobe:BAAALgAECgYJEwAAAA==.Koharu:BAAALgADCggJHAAAAA==.Kookykg:BAAALgAECgEJAQAAAA==.',
Kr='Krampus:BAABLgAECn85AAIaAAkJExTZCgAKAgAaAAkJExTZCgAKAgAAAA==.Kranok:BAAALgAECgYJDgAAAA==.Krim:BAAALgADCgUJBgAAAA==.Krimdevourer:BAAALgADCgYJBgAAAA==.Krimhuntress:BAAALgAECgEJAgAAAA==.',
Ku='Kunac:BAABLgAECn8aAAIEAAkJSRbqIQDjAQAEAAkJSRbqIQDjAQAAAA==.',
Ky='Kynessa:BAAALgAECgYJEQAAAA==.Kyrun:BAABLgAECn8xAAIaAAkJBg9OAwALAQAaAAkJBg9OAwALAQAAAA==.Kyuutips:BAAALgAECgEJAQAAAA==.',
['Kã']='Kãne:BAACLgAFFH8JAAIbAAIJ+AzqUwB6AAAbAAIJ+AzqUwB6AAAuAAQKfyQAAxsACQmFEQQsAI0BABsACQmFEQQsAI0BAAwAAgm9Bpo4AFQAAAAA.',
La='Lamoran:BAAALgADCgkJDwAAAA==.Lannes:BAAALgAECgEJAwAAAA==.Lapz:BAAALgAECgkJEQAAAA==.Lavetra:BAAALgAECgMJBAAAAA==.Lazerdinger:BAAALgAECgEJAQAAAA==.',
Le='Legendary:BAACLgAFFH8IAAIUAAIJ0h2QEAB+AAAUAAIJ0h2QEAB+AAAuAAQKfxQAAhQACQlbIMQDANcCABQACQlbIMQDANcCAAAA.Lethran:BAAALgAECgYJCQAAAA==.',
Lh='Lhani:BAABLgAECn8oAAIFAAkJORJ8HgDRAQAFAAkJORJ8HgDRAQAAAA==.',
Li='Liadrin:BAABLgAECn8jAAMJAAkJBhptBgCYAQAUAAkJzRZ0DwDNAQAJAAUJvyJtBgCYAQAAAA==.Lie:BAABLgAECn8eAAIMAAgJjw9LCgB7AQAMAAgJjw9LCgB7AQAAAA==.Liliana:BAAALgADCgkJNwAAAA==.Lirrasha:BAAALgADCgYJDwAAAA==.',
Ll='Llyrael:BAABLgAECn8eAAMFAAkJ/grLKgByAQAFAAkJ/grLKgByAQAeAAIJxAOplgAjAAAAAA==.',
Lo='Lolineverdie:BAABLgAECn8aAAMCAAkJ4gqOWgAoAQACAAkJ4gqOWgAoAQATAAYJnQI2bQBvAAAAAA==.',
Lu='Luna:BAABLgAECn8iAAMFAAgJEQrzLQCNAQAFAAgJEQrzLQCNAQAeAAgJ1QcFOwAmAQAAAA==.',
Ly='Lyrev:BAAALgAECgYJEwAAAA==.',
['Ló']='Lórien:BAAALgAECgEJAQAAAA==.',
Ma='Macaoidh:BAAALgAECgYJBgAAAA==.Maddeleine:BAABLgAECn8jAAQFAAgJlhWrGAAHAgAFAAgJlhWrGAAHAgAeAAMJzRDKWwCnAAAmAAQJtArjVwCgAAAAAA==.Magicdemon:BAABLgAECn83AAMOAAkJ2iVRCQCVAgAOAAkJpyVRCQCVAgAQAAgJnSCcHQBjAgAAAA==.Magichunter:BAAALgAECgEJAQABLgAECgkJNwAOANolAA==.Makall:BAAALgADCgEJAQAAAA==.Makanoa:BAAALgAECgYJCQAAAA==.Malaah:BAABLgAECn9BAAIXAAkJvhWeHgDtAQAXAAkJvhWeHgDtAQAAAA==.Malafar:BAAALgAFFAIJAwAAAA==.Malatrixx:BAAALgAECggJCQAAAA==.Maldiriel:BAAALgAECggJCAAAAA==.Mallikus:BAAALgADCgkJCgAAAA==.Manofsecks:BAAALgAECgQJDAAAAA==.Mansuno:BAAALgAECgcJBwAAAA==.Mapachote:BAABLgAECn8vAAIlAAgJ6B3MBABhAgAlAAgJ6B3MBABhAgAAAA==.Marodin:BAAALgAECgEJAQAAAA==.Marthaiden:BAAALgAECgkJDgAAAA==.Maryjaina:BAAALgADCgYJBgAAAA==.Maully:BAAALgAECgEJAQAAAA==.Mavastus:BAAALgADCgcJBwAAAA==.Mazozul:BAABLgAECn9CAAQmAAkJ1RaBGAAPAgAmAAkJixSBGAAPAgAeAAYJLA5yBgD4AAAFAAUJ/BRnQADsAAAAAA==.',
Me='Meatbaal:BAAALgAECgIJAgAAAA==.Medïc:BAAALgADCgIJAgAAAA==.Melinaria:BAABLgAECn8oAAMeAAkJMBVBHADjAQAeAAkJMBVBHADjAQAmAAEJ6gFXiQAhAAAAAA==.Melisondraa:BAAALgADCgkJCQAAAA==.Meow:BAAALgADCgQJBAAAAA==.Merkala:BAAALgADCgYJCQAAAA==.Metalbot:BAAALgADCgkJCQAAAA==.',
Mi='Miarose:BAAALgAECgUJBgAAAA==.Miggydogg:BAAALgAECgUJCwAAAA==.Mileta:BAABLgAECn8bAAITAAkJSRfpEgA+AgATAAkJSRfpEgA+AgAAAA==.Mimic:BAAALgAECgIJAgAAAA==.Minthammer:BAAALgAECgIJBAABLgAFFAIJBAABAAAAAA==.Mirthias:BAAALgAECgMJAwAAAA==.Mistlock:BAAALgAECgQJBAAAAA==.Mistylady:BAAALgAECgIJAgAAAA==.',
Mj='Mjöllnir:BAABLgAECn8UAAIXAAcJpgnCQwA6AQAXAAcJpgnCQwA6AQAAAA==.',
Mo='Monki:BAAALgAFFAEJAQAAAA==.Moozohar:BAAALgADCgEJAQAAAA==.Morgorra:BAAALgAECgMJBwAAAA==.Mormekil:BAAALgAECgIJAgAAAA==.Morvila:BAAALgAECgMJAwAAAA==.Mote:BAABLgAECn8sAAMeAAkJ7RSnHgDQAQAeAAkJ7RSnHgDQAQAmAAcJUxf6HwDNAQAAAA==.',
Mu='Muertes:BAAALgAECgEJAQAAAA==.Multidollar:BAAALgADCgUJBQABLgAFFAUJFQAVAL8WAA==.Muminah:BAAALgAECgMJBgAAAA==.',
['Mô']='Môlly:BAACLgAFFH8NAAIFAAUJQR6VCgCiAQAFAAUJQR6VCgCiAQAuAAQKfysAAgUACQkGIZUFAPYCAAUACQkGIZUFAPYCAAAA.',
Na='Narnluz:BAABLgAECn8dAAIFAAgJfBegGQD+AQAFAAgJfBegGQD+AQAAAA==.Nastiepastie:BAAALgADCgYJBgAAAA==.Nazor:BAABLgAECn8nAAIQAAgJ1xnzPwDJAQAQAAgJ1xnzPwDJAQABLgAFFAMJAwABAAAAAA==.',
Ne='Necronic:BAAALgADCgYJCwAAAA==.Necroreign:BAABLgAECn9RAAIOAAkJ5x5UAQA5AgAOAAkJ5x5UAQA5AgAAAA==.Neith:BAAALgADCgMJAwAAAA==.Nemera:BAAALgADCgYJCAAAAA==.Nervous:BAABLgAFFH8JAAIKAAMJ0SKzMAAfAQAKAAMJ0SKzMAAfAQAAAA==.Nessee:BAAALgAECgYJEgAAAA==.',
Ni='Niall:BAABLgAECn8zAAIPAAkJ3yEtAwDnAgAPAAkJ3yEtAwDnAgAAAA==.Nilithis:BAABLgAECn8rAAMHAAkJeRkCLgAgAgAHAAkJCxkCLgAgAgAIAAQJGxMGIQCmAAAAAA==.Niú:BAAALgADCgYJBgAAAA==.',
No='Nozmua:BAAALgADCgkJDgAAAA==.',
Ny='Nyghtchyld:BAAALgAECgcJEgAAAA==.Nyxlumina:BAAALgAECgIJAgAAAA==.',
['Né']='Néssima:BAABLgAECn8iAAMJAAkJ0RVTbACVAQAJAAkJZw5TbACVAQAUAAUJYhuaIwDrAAAAAA==.',
Oa='Oak:BAAALgAECgEJBQAAAA==.Oathfinder:BAAALgAECgcJEAAAAA==.',
Oc='Occurrence:BAABLgAECn8VAAMCAAgJ2gWIggC0AAACAAcJBwSIggC0AAATAAEJZwLtowAeAAAAAA==.Octalexane:BAAALgAECgUJBgABLgAECgkJIAAKAOUIAA==.',
Om='Omalu:BAAALgAECgEJAQABLgAECggJHgAMAI8PAA==.',
On='Onebuttonman:BAAALgADCgYJBgAAAA==.Onimusha:BAAALgAECgMJAwAAAA==.',
Or='Ortalbem:BAACLgAFFH8HAAIgAAIJVBRaPQCNAAAgAAIJVBRaPQCNAAAuAAQKfzoAAiAACQkXI+4RAO4CACAACQkXI+4RAO4CAAAA.',
Ov='Ovi:BAAALgADCgIJAgAAAA==.',
Pa='Pandariee:BAABLgAECn8VAAIdAAgJYw26fABqAQAdAAgJYw26fABqAQAAAA==.Pangsh:BAABLgAFFH8IAAIhAAMJBAWbQACjAAAhAAMJBAWbQACjAAAAAA==.Parzval:BAAALgAECgEJAgAAAA==.Paxgor:BAAALgAECgEJAQAAAA==.',
Pe='Pendaemonia:BAABLgAECn82AAIOAAkJuRZ7EgAFAgAOAAkJuRZ7EgAFAgAAAA==.Penelopie:BAAALgADCgYJBgAAAA==.Percfirdy:BAAALgADCgUJBQAAAA==.',
Ph='Pherix:BAABLgAECn8cAAIeAAcJ1SC+FwAKAgAeAAcJ1SC+FwAKAgAAAA==.Phiirys:BAAALgAECgEJAQAAAA==.',
Pi='Picaso:BAAALgADCgEJAQAAAA==.Pight:BAAALgAECggJEAABLgAECggJHgAMAI8PAA==.',
Po='Poomacha:BAABLgAECn8rAAIVAAgJexXhSgDBAQAVAAgJexXhSgDBAQAAAA==.Popout:BAAALgADCgUJBAAAAA==.Popstar:BAAALgAECgEJAQAAAA==.',
Pu='Puffthemagic:BAAALgADCgYJCAAAAA==.Punishêr:BAAALgADCgMJAwABLgAFFAEJAQABAAAAAA==.',
Py='Pyree:BAABLgAECn8kAAMbAAkJgxCLLACLAQAbAAkJ4w+LLACLAQAMAAcJaAm0GwBvAAAAAA==.Pyxrin:BAAALgAECgcJBwAAAA==.',
['Pø']='Pøë:BAAALgAECgkJEwABLgAFFAQJBQAQAFwHAA==.',
Qu='Qu:BAAALgAFFAIJBQABLgAFFAMJCQAPAHsZAQ==.Quina:BAAALgADCgIJAgAAAA==.',
Qv='Qveemcorkie:BAAALgAECgEJAQAAAA==.',
['Qí']='Qín:BAAALgADCgUJAwAAAA==.',
Ra='Radagust:BAAALgAECgQJBAAAAA==.Radcat:BAAALgAECgEJBAAAAA==.Raenne:BAAALgAECgMJBQAAAA==.Ragebait:BAAALgADCgIJAgAAAA==.Rainfall:BAAALgAECgEJAgAAAA==.Raistlain:BAAALgAECgYJDwAAAA==.Raitha:BAAALgADCgUJCAAAAA==.Ralli:BAACLgAFFH8IAAIQAAMJIBvFTgAAAQAQAAMJIBvFTgAAAQAuAAQKfy0AAhAACAmiGa4zAPcBABAACAmiGa4zAPcBAAAA.Rallsdemon:BAAALgAECgQJBAABLgAFFAQJBwAjAHENAA==.Rallsdk:BAABLgAFFH8HAAMjAAQJcQ1mBwDhAAAjAAMJKA5mBwDhAAAdAAEJTAtmgAA+AAAAAA==.Rallsodins:BAAALgAECgYJBgABLgAFFAQJBwAjAHENAA==.Randomguy:BAACLgAFFH8NAAIRAAQJ9Rm8FQBeAQARAAQJ9Rm8FQBeAQAuAAQKfzgAAhEACQnYJT0CADsDABEACQnYJT0CADsDAAAA.Ranulf:BAAALgAECgQJBgAAAA==.Ratava:BAAALgAECgcJCQAAAA==.Ratboy:BAEALgAECgEJAQABLgAECgkJMgAmABwjAA==.Ratrot:BAABLgAECn8qAAIKAAgJKh5tEwCxAgAKAAgJKh5tEwCxAgAAAA==.Ratsdead:BAAALgAECgEJAQAAAA==.Razenath:BAAALgADCgcJDAAAAA==.',
Re='Reddemon:BAAALgAECgEJAQAAAA==.Redhourn:BAAALgAECgMJAwAAAA==.Reinhardt:BAAALgADCgYJBgAAAA==.Rekrella:BAAALgADCgUJBQAAAA==.Reldarus:BAEBLgAECn8yAAMmAAkJHCPTAgCBAwAmAAkJHCPTAgCBAwAFAAQJ+hr8RAAlAQAAAA==.Rena:BAAALgADCgcJBwAAAA==.Rendia:BAAALgADCgMJAwAAAA==.Renik:BAAALgADCgIJAQAAAA==.Revennek:BAAALgAECgUJCgAAAA==.Reverence:BAABLgAECn8eAAIJAAkJ8A35YgCqAQAJAAkJ8A35YgCqAQAAAA==.Revilation:BAABLgAECn8cAAIUAAkJYBPZEwCOAQAUAAkJYBPZEwCOAQAAAA==.Rezjyk:BAAALgAECgYJCAABLgAECgkJNAAJANwcAA==.Rezzyk:BAABLgAECn80AAIJAAkJ3Bw+GgCmAgAJAAkJ3Bw+GgCmAgAAAA==.',
Rh='Rhonus:BAAALgAECgEJAQAAAA==.Rhyxali:BAABLgAECn8hAAQIAAkJOAxxEQAvAQAIAAkJOAxxEQAvAQAGAAYJLAdQHADcAAAHAAQJ5AHK+QBmAAAAAA==.',
Ri='Riidefi:BAAALgADCgMJAwABLgAECgkJAwABAAAAAA==.Riilock:BAAALgAECgIJAgABLgAECgkJAwABAAAAAA==.Riis:BAAALgAECgYJDAAAAA==.Riiselock:BAABLgAECn8tAAMHAAgJIR5CNwAvAgAHAAcJyR1CNwAvAgAIAAQJFBwOGADhAAAAAA==.Riiwind:BAAALgADCgQJBAABLgAECgkJAwABAAAAAA==.Riktade:BAAALgADCgYJBgAAAA==.Rilight:BAAALgAECgQJBAABLgAECgkJAwABAAAAAA==.Riptidepod:BAABLgAECn8gAAMKAAkJ5QhmVQBgAQAKAAkJ5QhmVQBgAQAXAAIJ3gJ/wQAcAAAAAA==.',
Ro='Robbiebrews:BAAALgADCgUJBQAAAA==.Robear:BAAALgAECgEJAQAAAA==.Robeart:BAAALgAECgEJAgAAAA==.Rolim:BAAALgADCgIJAgAAAA==.Romic:BAAALgAECgEJAQAAAA==.Rowin:BAAALgADCgUJBQAAAA==.',
Ru='Ruddigore:BAAALgAECgEJAQAAAA==.Ruubyy:BAAALgAECgEJAQAAAA==.',
Ry='Rynley:BAABLgAECn8WAAMRAAUJASEKJwDAAQARAAUJASEKJwDAAQAnAAIJWRH3GwBtAAAAAA==.',
Sa='Sacredscales:BAABLgAECn8hAAMFAAkJtR5kCwCaAgAFAAcJ3yRkCwCaAgAeAAcJtRSGKgCGAQAAAA==.Sagerremeseb:BAAALgAECgQJCQAAAA==.Sakii:BAABLgAECn8lAAIQAAkJJRIGOgDfAQAQAAkJJRIGOgDfAQAAAA==.Salera:BAAALgADCgQJBAAAAA==.Salvion:BAAALgAECgcJAQABLgAFFAMJAwABAAAAAA==.Samvimes:BAABLgAECn9HAAIJAAkJMRMBBQDOAQAJAAkJMRMBBQDOAQAAAA==.Sangreene:BAABLgAECn8dAAIeAAgJRxqFEwBYAgAeAAgJRxqFEwBYAgAAAA==.Sargis:BAACLgAFFH8IAAIJAAMJkRhaXQD1AAAJAAMJkRhaXQD1AAAuAAQKf0wAAwkACQmnI+gIACMDAAkACQmnI+gIACMDAAsACAnHG1gbACkCAAAA.Sarial:BAAALgADCgMJAwAAAA==.',
Sc='Schrödinger:BAAALgAECgYJDwABLgAECgkJGQAUAO0YAA==.Sciblasts:BAAALgADCgEJAQABLgAECggJGAAWAP0MAA==.Scott:BAACLgAFFH8oAAIQAAgJxyExBgCwAgAQAAgJxyExBgCwAgAuAAQKf0YAAhAACQmaJnUAAO4DABAACQmaJnUAAO4DAAAA.Scratchh:BAABLgAECn8dAAIhAAgJlAstNgB0AQAhAAgJlAstNgB0AQAAAA==.',
Se='Searalsa:BAAALgAECgUJCAABLgAFFAQJDQAaAFIJAA==.Sentis:BAABLgAECn8fAAITAAgJOgfERAD5AAATAAgJOgfERAD5AAAAAA==.Serjankins:BAAALgAECgYJBwAAAA==.',
Sh='Shadowbrooks:BAAALgAECgIJAgAAAA==.Shadowgiver:BAAALgADCgcJDwAAAA==.Shadowsdemon:BAAALgADCgEJAQAAAA==.Shadowsworn:BAAALgAECgEJAQAAAA==.Shagol:BAAALgAECgQJBwAAAA==.Shalriss:BAABLgAECn8nAAIeAAkJCBtLEABZAgAeAAkJCBtLEABZAgAAAA==.Shambolance:BAAALgADCgEJAQAAAA==.Shamemoon:BAABLgAECn8fAAIQAAkJjhdZLwAJAgAQAAkJjhdZLwAJAgAAAA==.Shamunroe:BAABLgAECn8pAAMKAAkJMAfGYAA5AQAKAAkJMAfGYAA5AQAXAAUJkxKwWgDZAAAAAA==.Shatterhoof:BAABLgAECn8jAAIPAAkJTgwGIQAAAQAPAAkJTgwGIQAAAQAAAA==.Shelle:BAAALgAECgYJCgAAAA==.Shiftys:BAAALgADCgUJCgABLgAFFAIJAwABAAAAAA==.Shingra:BAACLgAFFH8qAAIbAAgJxRaUGQCZAQAbAAgJxRaUGQCZAQAuAAQKfygAAhsACQnGHSgOAH8CABsACQnGHSgOAH8CAAAA.Shoof:BAAALgADCgUJBQAAAA==.',
Si='Sifû:BAAALgADCgcJDgAAAA==.Sigourney:BAAALgAECgUJBgABLgAECgkJOAAfANMcAA==.Silversho:BAAALgAECgUJBQAAAA==.Silvoid:BAAALgADCgMJAwABLgAECgUJBQABAAAAAA==.Silvren:BAABLgAECn8zAAMEAAgJJhiCIADsAQAEAAgJJhiCIADsAQANAAEJvwZoRgArAAAAAA==.Sindarion:BAAALgAECgUJBQABLgAFFAEJAgABAAAAAA==.Sinkrim:BAAALgAECgMJBAAAAA==.Sinnerr:BAAALgAECgEJAQAAAA==.Sinz:BAAALgAECgEJBQAAAA==.Siph:BAAALgAECgEJAQAAAA==.',
Sk='Skillidan:BAABLgAECn8nAAICAAkJQhopFQChAgACAAkJQhopFQChAgAAAA==.',
Sl='Slayde:BAAALgAECgEJAQAAAA==.Slighttrash:BAABLgAECn8qAAIfAAgJlhQjGADgAQAfAAgJlhQjGADgAQAAAA==.Sloppy:BAAALgADCgkJCgAAAA==.',
Sm='Smacka:BAAALgAECgEJAQAAAA==.Smallcrow:BAACLgAFFH8jAAMYAAgJbR6PAQB+AgAYAAgJbR6PAQB+AgAZAAEJQwvMXgBDAAAuAAQKfxYAAhgABwkuJsQHAP8CABgABwkuJsQHAP8CAAAA.Smores:BAAALgADCgkJEgAAAA==.Smøke:BAAALgAECgMJAwAAAA==.',
Sn='Snallygaster:BAAALgADCgYJDAABLgAECgkJIwAWAJ8bAA==.Snowsong:BAAALgAECgEJAQAAAA==.',
So='Soff:BAAALgAECgEJAQAAAA==.',
Sp='Spamton:BAAALgADCgEJAQAAAA==.Spectrose:BAAALgADCgEJAQAAAA==.Spirit:BAAALgAECgEJAgAAAA==.Spiro:BAAALgAFFAIJAgABLgAFFAQJBQAQAFwHAA==.Spøngè:BAAALgADCgMJAwAAAA==.',
St='Starge:BAAALgAFFAEJAwAAAA==.Starre:BAAALgAECgYJBwAAAA==.Steffey:BAABLgAECn8kAAIKAAkJfgq7YQA2AQAKAAkJfgq7YQA2AQAAAA==.Stoikk:BAAALgADCgEJAQAAAA==.Straven:BAABLgAECn8qAAIgAAkJ4RXeCwAxAQAgAAkJ4RXeCwAxAQAAAA==.Sturgeson:BAACLgAFFH8lAAIDAAgJURpZCQCdAQADAAgJURpZCQCdAQAuAAQKfx8AAgMACQlvHQcMAEsCAAMACQlvHQcMAEsCAAAA.',
Su='Sulfato:BAAALgADCgEJAQAAAA==.Sulwen:BAABLgAECn9ZAAMFAAkJoh5CAQBLAgAFAAkJoh5CAQBLAgAeAAEJ1AayGgAjAAAAAA==.Supertank:BAAALgADCgUJBQAAAA==.Suzakã:BAABLgAECn8UAAIgAAkJuAgPCgBLAQAgAAkJuAgPCgBLAQAAAA==.',
Sw='Sweetpotato:BAAALgADCgEJAQAAAA==.Swiftfeet:BAABLgAECn8lAAIVAAkJABRHQwDYAQAVAAkJABRHQwDYAQAAAA==.',
Sy='Syrasia:BAAALgADCgUJBQAAAA==.Syselea:BAAALgADCgEJAQAAAA==.',
['Sö']='Söranin:BAABLgAECn8dAAIZAAYJ5xi0MwCoAQAZAAYJ5xi0MwCoAQAAAA==.',
Ta='Tachichan:BAAALgAECgYJBgAAAA==.Tadum:BAAALgADCgEJAQAAAA==.Taeili:BAABLgAECn8gAAMWAAkJIhXfKAATAQATAAgJ2BVoNgBiAQAWAAYJKxPfKAATAQAAAA==.Talisse:BAAALgADCgYJBgAAAA==.Tanequil:BAACLgAFFH8JAAICAAMJCgJrWQBnAAACAAMJCgJrWQBnAAAuAAQKfyQAAgIACQlJDNdKAHgBAAIACQlJDNdKAHgBAAAA.Taosha:BAAALgAECgcJCAAAAA==.Targaryian:BAAALgAECgMJAwAAAA==.Tav:BAAALgADCgUJBQAAAA==.Taylea:BAABLgAECn8WAAIgAAcJpA9etQAZAQAgAAcJpA9etQAZAQABLgAECgkJKQAJAE0gAA==.',
Te='Techromancer:BAAALgAECgYJCAABLgAECgcJHAAeANUgAA==.Telleria:BAAALgAECgMJBAAAAA==.Tem:BAAALgAECgMJAwAAAA==.Tenumbras:BAAALgAECgYJDAAAAA==.Termonda:BAAALgAECgEJAQAAAA==.Terraclaw:BAAALgADCgUJBwAAAA==.Terrasia:BAAALgADCgYJBgAAAA==.Terrigino:BAAALgAECgUJAwAAAA==.',
Th='Thanatias:BAABLgAECn8aAAIcAAkJmhSAFgC1AQAcAAkJmhSAFgC1AQAAAA==.Thantasia:BAABLgAECn8WAAIgAAcJogOA1gDoAAAgAAcJogOA1gDoAAAAAA==.Thauras:BAAALgADCgcJFwAAAA==.Theeslan:BAABLgAECn8pAAIeAAkJ/QQ0CwCcAAAeAAkJ/QQ0CwCcAAAAAA==.Thokdar:BAAALgAECgUJBQAAAA==.Thom:BAACLgAFFH8MAAIjAAUJihAoEQALAQAjAAUJihAoEQALAQAuAAQKfysAAyMACQksJOcAABwDACMACQksJOcAABwDAB0ABgmoDjmxACABAAAA.Thør:BAAALgADCgcJDgAAAA==.',
Ti='Tiernay:BAAALgADCgEJAQAAAA==.Tifà:BAAALgAECgUJCAAAAA==.Timothy:BAABLgAECn8bAAIOAAkJ7BgzEgAJAgAOAAkJ7BgzEgAJAgAAAA==.Timothyjohn:BAAALgAECgUJBQAAAA==.Tinkphooey:BAAALgAECgYJCwAAAA==.Tinton:BAAALgADCgEJAQAAAA==.',
To='Toishi:BAAALgAECgEJAQAAAA==.Tormmok:BAAALgAECgYJDAAAAA==.Toshiden:BAAALgAECgEJAQAAAA==.Toshindo:BAAALgAECgEJAgAAAA==.Totemkib:BAAALgAECgEJAQAAAA==.',
Tr='Traazz:BAAALgAECgkJAwAAAA==.Trashpally:BAAALgAECgEJAgAAAA==.Tremèndor:BAAALgADCgMJAwAAAA==.Trey:BAAALgAECgEJAQAAAA==.Tristra:BAAALgAECgQJBAAAAA==.',
Ts='Tsuruga:BAABLgAECn85AAIhAAkJQA5iIgCWAQAhAAkJQA5iIgCWAQAAAA==.',
Tu='Turkwise:BAABLgAECn86AAMWAAkJVx1+BgCWAgAWAAkJVx1+BgCWAgAPAAQJCBGsHgDuAAAAAA==.',
Ty='Tycondrius:BAAALgAECgEJAQAAAA==.Tyresh:BAAALgAECgEJAQAAAA==.Tyrinor:BAAALgADCgUJBQAAAA==.',
Ul='Ulogasm:BAAALgADCgkJCgAAAA==.',
Us='Usami:BAAALgAECgEJAQAAAA==.',
Ut='Utako:BAAALgADCgUJCgAAAA==.',
Uv='Uvari:BAABLgAECn8bAAIFAAgJ1w6nKACBAQAFAAgJ1w6nKACBAQAAAA==.',
Va='Vaclar:BAAALgAFFAMJAwABLgAFFAUJDQAYAK8hAA==.Valhalaa:BAAALgADCgYJBgAAAA==.Valkryee:BAAALgAECggJCQAAAA==.Valton:BAACLgAFFH8NAAIYAAUJryHOCwBnAQAYAAUJryHOCwBnAQAuAAQKf0YAAhgACQmEJsQAAHoDABgACQmEJsQAAHoDAAAA.Vanillanice:BAABLgAECn8UAAMdAAgJ5wuqrwAVAQAdAAYJjw6qrwAVAQAcAAcJHwhNCACDAAAAAA==.Varrfife:BAAALgAECgQJBAAAAA==.Vaxaldan:BAABLgAECn85AAIcAAkJLQ6QHgBiAQAcAAkJLQ6QHgBiAQAAAA==.',
Ve='Velestre:BAAALgAECgUJBQAAAA==.Velithera:BAAALgADCgMJAwAAAA==.Vellithe:BAABLgAECn8iAAIJAAcJpw+FDgAIAQAJAAcJpw+FDgAIAQAAAA==.Venj:BAAALgAECgUJBgAAAA==.Verhmax:BAAALgADCgYJCwAAAA==.Verton:BAAALgADCgYJBgAAAA==.Vestrae:BAACLgAFFH8KAAMCAAUJIgpJLQD/AAACAAUJIgpJLQD/AAATAAEJSQHTVgAmAAAuAAQKfyYAAgIACQnwHG8TAJoCAAIACQnwHG8TAJoCAAAA.Vex:BAABLgAECn8YAAIHAAkJbxr1JgBBAgAHAAkJbxr1JgBBAgAAAA==.',
Vi='Vianel:BAAALgADCggJCAAAAA==.Vilten:BAAALgAECgQJCwAAAA==.Virus:BAAALgAECgkJCQAAAA==.',
Vo='Vodash:BAABLgAECn8jAAIKAAgJmhi4MgDoAQAKAAgJmhi4MgDoAQABLgAECgkJRwACAB8QAA==.Voidwrench:BAAALgAECgMJAwABLgAECgkJIQAIADgMAA==.Vostok:BAABLgAECn8eAAIHAAgJOBwtSQC+AQAHAAgJOBwtSQC+AQAAAA==.',
Wa='Wage:BAAALgADCgQJBQAAAA==.Warmth:BAAALgADCgIJAwAAAA==.Warranni:BAAALgAECgMJAwAAAA==.',
We='Weekend:BAAALgADCgkJDwAAAA==.Wetsock:BAAALgAECgYJBwAAAA==.',
Wi='Wikket:BAABLgAECn85AAMTAAkJPRywDQB/AgATAAkJPRywDQB/AgACAAgJ3AMldwDQAAAAAA==.',
Wo='Wolvesbayne:BAAALgAECgEJAQAAAA==.',
Wy='Wyelie:BAAALgAECgYJDgAAAA==.Wynono:BAAALgADCgcJBwAAAA==.',
Xd='Xdeadlysinz:BAAALgAECgcJDwAAAA==.',
Xo='Xotha:BAACLgAFFH8HAAIQAAIJCxf9LwB3AAAQAAIJCxf9LwB3AAAuAAQKf0EAAhAACQmoHmQVAJgCABAACQmoHmQVAJgCAAAA.',
Xu='Xuen:BAAALgAFFAEJAwAAAA==.',
Xy='Xythera:BAACLgAFFH8HAAIQAAQJARldYADPAAAQAAQJARldYADPAAAuAAQKfyIAAxAACQmKIPYVANMCABAACQmKIPYVANMCACIAAQmwEIM0ADIAAAAA.',
Ya='Yaákov:BAAALgAFFAMJAwAAAA==.',
Ye='Yeah:BAAALgADCgYJBgABLgAFFAMJDAAJACAYAA==.',
Yi='Yinosai:BAAALgAECgYJCQAAAA==.',
Yo='Yougot:BAAALgADCgcJCgAAAA==.',
Yu='Yuji:BAABLgAECn8hAAIIAAYJaR2+CwCEAQAIAAYJaR2+CwCEAQAAAA==.Yukì:BAAALgADCgMJAwAAAA==.Yurie:BAAALgAECgIJAgAAAA==.',
Yv='Yvonna:BAAALgADCgEJAQAAAA==.',
Za='Zaega:BAAALgADCgQJBAABLgAECgkJKQAJAE0gAA==.Zahlee:BAAALgAECgQJBAAAAA==.Zaldin:BAAALgAECgUJCgAAAA==.Zalirina:BAAALgADCgIJAgAAAA==.Zanka:BAAALgAECgIJAgAAAA==.Zaridruid:BAAALgAECgkJCgAAAA==.Zarisedra:BAACLgAFFH8rAAMLAAgJYR1bCQAlAgALAAgJYR1bCQAlAgAJAAEJXgDaOwA2AAAuAAQKfxgAAwsACQkwF8kpAOMBAAsACAkGGMkpAOMBAAkAAQktBuw9ATUAAAAA.Zarissena:BAAALgAECgYJAwAAAA==.Zarris:BAAALgADCgUJDAAAAA==.',
Ze='Zennith:BAAALgADCgMJAwAAAA==.Zernacho:BAABLgAECn8gAAQFAAkJjBqhHwDHAQAFAAYJJhyhHwDHAQAeAAcJ+hFBLgBvAQAmAAMJTRMRVACxAAAAAA==.Zerogasm:BAABLgAECn8dAAIVAAkJbBZvMAAaAgAVAAkJbBZvMAAaAgAAAA==.Zerolicious:BAAALgAECgQJCAAAAA==.Zeromojo:BAAALgAECgUJBQAAAA==.Zerostarbear:BAAALgAECgEJAgAAAA==.Zerozaddy:BAAALgAECgUJBgAAAA==.Zevvo:BAABLgAECn8wAAIEAAkJECFXCgC/AgAEAAkJECFXCgC/AgAAAA==.',
Zi='Ziggysundust:BAAALgADCgMJAwAAAA==.',
Zo='Zoraji:BAABLgAECn86AAIhAAkJdhrzDgBLAgAhAAkJdhrzDgBLAgAAAA==.',
Zu='Zuganova:BAABLgAFFH8SAAMmAAUJDQi/JAAnAQAmAAUJ4Qe/JAAnAQAFAAEJ8whwFgA8AAAAAA==.Zuggar:BAABLgAECn8fAAIEAAcJVwjTUgD/AAAEAAcJVwjTUgD/AAAAAA==.',
Zy='Zynhammer:BAABLgAECn8oAAMQAAgJgxFhXQCJAQAQAAgJgxFhXQCJAQAOAAEJawbNeQAmAAAAAA==.',
['Év']='Évangeline:BAAALgADCgcJBwAAAA==.',
['Ëb']='Ëbony:BAABLgAFFH8PAAIVAAUJIhsDMABQAQAVAAUJIhsDMABQAQAAAA==.',
['Ëd']='Ëdën:BAABLgAECn8hAAICAAgJDRIjAwCmAQACAAgJDRIjAwCmAQAAAA==.',
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
