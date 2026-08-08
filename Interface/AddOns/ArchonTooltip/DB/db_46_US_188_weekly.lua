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

local lookup = {'Unknown-Unknown','Druid-Restoration','Warrior-Protection','Warrior-Fury','Paladin-Retribution','Priest-Holy','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Shaman-Restoration','Paladin-Holy','Evoker-Devastation','Warrior-Arms','DemonHunter-Havoc','Druid-Feral','DemonHunter-Devourer','Rogue-Subtlety','Rogue-Assassination','Druid-Balance','Paladin-Protection','Hunter-BeastMastery','Druid-Guardian','Shaman-Elemental','Monk-Windwalker','Monk-Mistweaver','Shaman-Enhancement','Evoker-Augmentation','DeathKnight-Blood','DeathKnight-Unholy','Evoker-Preservation','Priest-Shadow','Hunter-Survival','Mage-Frost','Monk-Brewmaster','DemonHunter-Vengeance','DeathKnight-Frost','Mage-Arcane','Hunter-Marksmanship','Priest-Discipline','Rogue-Outlaw',}
local provider = {region='US',realm='ShadowCouncil',name='US',type='weekly',zone=46,date='2026-08-04',data={Ab='Abear:BAAALgAECgQJBQAAAA==.Abrocklock:BAAALgAECgYJCQAAAA==.',
Ac='Achilês:BAAALgAECgEJAQABLgAFFAEJAQABAAAAAA==.',
Ad='Adaluna:BAABLgAECn8XAAICAAkJ2wmSUgBFAQACAAkJ2wmSUgBFAQAAAA==.Adorabull:BAACLgAFFH8JAAIDAAMJRyLxEAAnAQADAAMJRyLxEAAnAQAuAAQKfygAAwMACQkOIroGAJwCAAMACQkOIroGAJwCAAQAAQnQBhGvACwAAAAA.Adrain:BAAALgAECgQJCwAAAA==.Adwae:BAAALgAECgIJAgAAAA==.',
Ae='Aeiou:BAAALgAECgUJBQAAAA==.Aelyn:BAAALgAECgcJDwAAAA==.Aevelee:BAABLgAECn8UAAIFAAkJPRPVFgAYAQAFAAkJPRPVFgAYAQAAAA==.Aevick:BAAALgAECgQJBQAAAA==.',
Al='Alastair:BAAALgADCgEJAQAAAA==.Aleeta:BAAALgAECgQJBgAAAA==.Alleriae:BAAALgAECgIJAgAAAA==.Allucard:BAAALgAECgkJAgAAAA==.',
Am='Amapanda:BAAALgAECgkJCQAAAA==.Amaria:BAAALgAECgkJBgAAAA==.Amoracchius:BAAALgADCgMJAwAAAA==.',
An='Anduîiîn:BAAALgAECgIJAgAAAA==.Angelsdêmon:BAAALgAECgEJAQABLgAFFAEJAQABAAAAAA==.Angelstörm:BAACLgAFFH8IAAIGAAIJPwy+LABkAAAGAAIJPwy+LABkAAAuAAQKf0AAAgYACQloGe4SAEUCAAYACQloGe4SAEUCAAAA.Anjali:BAAALgAECgEJAQAAAA==.Anorili:BAAALgADCgYJBgAAAA==.Antarias:BAABLgAECn8fAAQHAAkJuxrTEQBIAQAHAAUJASTTEQBIAQAIAAcJqhJpogD7AAAJAAMJjhi/JwB5AAAAAA==.Antarion:BAAALgAECgQJBAAAAA==.',
Ap='Applevendor:BAAALgADCgUJBQAAAA==.',
Ar='Arahil:BAAALgAECgQJBwAAAA==.Arcanio:BAAALgADCgQJBAAAAA==.Arcaux:BAAALgADCggJDgAAAA==.Arckenon:BAACLgAFFH8IAAIFAAMJQh2eWQD9AAAFAAMJQh2eWQD9AAAuAAQKf0EAAgUACQlwJKcIACUDAAUACQlwJKcIACUDAAAA.',
As='Ashdorei:BAAALgADCgMJAwAAAA==.Ashog:BAABLgAECn8XAAIKAAcJGRYcQACtAQAKAAcJGRYcQACtAQAAAA==.Astranos:BAAALgAECgEJAQABLgAECgkJRwACAB8QAA==.',
At='Athanyr:BAABLgAECn8sAAICAAgJXyU6BgBUAwACAAgJXyU6BgBUAwAAAA==.Atillis:BAAALgAECgUJBQAAAA==.',
Au='Augmentation:BAAALgAECgEJAQAAAA==.Austenpally:BAABLgAECn8hAAMFAAkJ3RhicACNAQAFAAcJ3hZicACNAQALAAcJkRGgNwBvAQAAAA==.',
Av='Aveycado:BAAALgAECgMJBAAAAA==.Aviane:BAAALgAECgYJBgAAAA==.',
Ax='Axeflack:BAAALgAFFAEJAgAAAA==.Axegor:BAAALgADCgMJAwAAAA==.',
Az='Azrall:BAAALgAECgIJAgAAAA==.',
Ba='Bacuda:BAAALgAECgYJEAAAAA==.Badwolf:BAAALgADCgQJBAAAAA==.Balkris:BAAALgAECgEJAgABLgAECggJHgAMAI8PAA==.Baratheon:BAABLgAECn8VAAMNAAkJCg+6FwCdAQANAAkJNg66FwCdAQAEAAcJXgbYXQA4AQAAAA==.Batya:BAAALgAECgIJAgAAAA==.',
Be='Beartooth:BAAALgADCgUJBQAAAA==.Bearynice:BAAALgADCgUJBQAAAA==.Beggles:BAAALgADCgEJAQAAAA==.Bereit:BAAALgADCgcJBgAAAA==.',
Bi='Biancadelrio:BAABLgAECn8oAAIOAAkJfBKYIQBsAQAOAAkJfBKYIQBsAQAAAA==.Bigboned:BAAALgADCgEJAQABLgAECgkJIwAFAAYaAA==.Bigmode:BAAALgADCgYJBgAAAA==.Bigwolves:BAAALgADCgIJAgAAAA==.',
Bj='Bjorrglbrgl:BAABLgAFFH8JAAIPAAMJexlPDQDiAAAPAAMJexlPDQDiAAAAAA==.',
Bl='Blackmask:BAAALgADCgUJCAAAAA==.Blackzune:BAAALgAECgEJAQAAAA==.Bladekrim:BAAALgAECgEJAgAAAA==.Blindashunae:BAACLgAFFH8kAAIQAAkJNRObGwDVAQAQAAkJNRObGwDVAQAuAAQKfxYAAhAACQlQHikVANgCABAACQlQHikVANgCAAAA.Blindkungfu:BAAALgAECgQJBAAAAA==.Bloodrun:BAAALgADCgkJCgAAAA==.Blook:BAABLgAECn8UAAMRAAgJThXzIACOAQARAAgJThXzIACOAQASAAEJkgg2HwA3AAAAAA==.Bluehazey:BAAALgAECgkJEQAAAA==.Blueleader:BAAALgAECgQJBAAAAA==.Bläz:BAAALgAECgEJAQAAAA==.',
Bo='Bonks:BAAALgAECgEJAwAAAA==.Boomhammer:BAAALgAFFAIJBAAAAA==.Bootsy:BAAALgAECgcJBAAAAA==.Bopit:BAABLgAECn8XAAMFAAkJ+g6nnwBAAQAFAAYJeA6nnwBAAQALAAkJ9AzJUAA2AQAAAA==.Botia:BAABLgAECn8YAAITAAcJ3gUwYACYAAATAAcJ3gUwYACYAAAAAA==.',
Br='Braedia:BAAALgAECgEJAQAAAA==.Bruhh:BAAALgAECgYJBwAAAA==.Brunnera:BAAALgAECgIJAwAAAA==.Bruuenor:BAAALgAECgYJCAAAAA==.Bruul:BAABLgAECn8mAAQFAAgJ0xmAOgAZAgAFAAgJ0xmAOgAZAgALAAQJ3Q3HXADCAAAUAAEJ1RBEUQAuAAAAAA==.Brynjolf:BAAALgAECgUJCQAAAA==.',
Ca='Caenji:BAABLgAECn8XAAIVAAkJOAsIaQBwAQAVAAkJOAsIaQBwAQAAAA==.Carcharoth:BAABLgAECn8nAAMJAAkJlBjuCQCnAQAJAAcJNRruCQCnAQAIAAYJqBCRrgDmAAAAAA==.Carmelina:BAABLgAECn8oAAIOAAgJJBzBDgA6AgAOAAgJJBzBDgA6AgAAAA==.Catrixona:BAAALgAECgUJCAAAAA==.Caylan:BAAALgADCgQJBAAAAA==.',
Ch='Chadgar:BAAALgADCgIJAgAAAA==.Chaoscaster:BAAALgADCgkJCQABLgAECgYJBgABAAAAAA==.Charroth:BAAALgAECgYJCAAAAA==.Chey:BAABLgAECn9CAAIRAAkJ4iTMAgAnAwARAAkJ4iTMAgAnAwAAAA==.Chilai:BAABLgAECn8mAAIWAAkJABgwDAAeAgAWAAkJABgwDAAeAgAAAA==.Chipsahoy:BAABLgAECn8iAAMXAAkJ2x8bCgC8AgAXAAkJ2x8bCgC8AgAKAAYJdRJ3RQBsAQAAAA==.Chrîstîan:BAAALgADCgcJCgAAAA==.Chíef:BAABLgAFFH8VAAMKAAgJxB8ECQA5AgAKAAcJDiAECQA5AgAXAAMJ/gLnTwBYAAAAAA==.',
Ci='Cindrozetha:BAAALgADCgEJAQAAAA==.Citte:BAAALgAFFAEJAgAAAA==.',
Cl='Close:BAAALgADCgUJBQABLgAFFAMJCQAKANEiAA==.',
Co='Conciete:BAABLgAECn8VAAMYAAgJWhXmGgAHAgAYAAgJWhXmGgAHAgAZAAEJBAHidwARAAAAAA==.Conorix:BAAALgAECgUJCAAAAA==.Constantiine:BAAALgAECgEJAQAAAA==.Corvo:BAABLgAECn8ZAAIUAAkJ7RiNCgAhAgAUAAkJ7RiNCgAhAgAAAA==.Counselor:BAAALgAECgUJCQAAAA==.Courallie:BAAALgAECgEJAQAAAA==.',
Cr='Crataxxis:BAABLgAECn9JAAIOAAkJ+BuHCQCSAgAOAAkJ+BuHCQCSAgAAAA==.Crynos:BAAALgADCgMJAwAAAA==.Crysandra:BAAALgAECgUJBQAAAA==.',
Cy='Cydon:BAABLgAECn9BAAIWAAkJvR6dBQCwAgAWAAkJvR6dBQCwAgAAAA==.',
Da='Daereth:BAAALgAECgYJCQAAAA==.Daerrith:BAAALgAECgUJCQAAAA==.Dala:BAAALgAECgUJBQAAAA==.Damienfox:BAAALgAECgQJBgAAAA==.Dana:BAAALgAFFAEJAQABLgAFFAYJDAAZAGceAA==.Danellia:BAAALgADCgUJBQAAAA==.Darkreaper:BAAALgAECgQJBAAAAA==.Darrwin:BAABLgAECn8tAAMFAAgJTSDEJgBpAgAFAAgJTSDEJgBpAgAUAAQJUg7SLwCoAAAAAA==.Dawicker:BAAALgADCggJEQAAAA==.Daylight:BAAALgAECgYJCQAAAA==.',
De='Deathspacito:BAAALgAECgEJAgAAAA==.Dedoria:BAAALgADCgUJCAAAAA==.Defacto:BAAALgADCgMJAwAAAA==.Delat:BAAALgAECgEJAQAAAA==.Delrac:BAABLgAECn8iAAIQAAgJWxFKWQB8AQAQAAgJWxFKWQB8AQAAAA==.Demonalsa:BAAALgAECgUJBgABLgAFFAQJDQAaAFIJAA==.Denathrius:BAAALgAECgIJAwABLgAFFAUJCAAQALQTAA==.Denero:BAABLgAECn8dAAIFAAkJIx77GwCdAgAFAAkJIx77GwCdAgAAAA==.Departure:BAAALgAECgQJBwABLgAECgcJFwAOAEMcAA==.Derith:BAAALgADCgEJAQAAAA==.',
Df='Dfabness:BAACLgAFFH8KAAIYAAMJ5xDTJQC8AAAYAAMJ5xDTJQC8AAAuAAQKfyMAAhgACQnnElskAJABABgACQnnElskAJABAAAA.',
Di='Dic:BAAALgADCgIJAgABLgAECgMJAwABAAAAAA==.Diizmyster:BAAALgAECgkJBAAAAA==.',
Do='Docbush:BAAALgAECgEJAQABLgAFFAQJDgAIAPkEAA==.Docbushed:BAAALgAECgQJBAABLgAFFAQJDgAIAPkEAA==.Dogberry:BAAALgAECgEJAQAAAA==.Dotbush:BAACLgAFFH8OAAMIAAQJ+QQjbgDmAAAIAAQJ+QQjbgDmAAAJAAEJhwKhLAAzAAAuAAQKfzAABAgACQlsFc9IAMABAAgACQmVFM9IAMABAAkAAwmrDIBGAJwAAAcAAgnOEcYoAHwAAAAA.Dotspot:BAAALgADCgQJBAABLgAECgMJBwABAAAAAA==.',
Dr='Dracthayr:BAABLgAECn86AAIMAAkJZROuBgDhAQAMAAkJZROuBgDhAQAAAA==.Dragonhammer:BAACLgAFFH8LAAIFAAIJGSTpcwDMAAAFAAIJGSTpcwDMAAAuAAQKf1EAAgUACQmAJIMHADEDAAUACQmAJIMHADEDAAAA.Drakanna:BAAALgAECgIJAgAAAA==.Draxela:BAABLgAECn8gAAIbAAcJTQlHDQCcAAAbAAcJTQlHDQCcAAAAAA==.Dreaming:BAABLgAECn8wAAIcAAkJZiLBBAD7AgAcAAkJZiLBBAD7AgABLgAFFAMJCQAKANEiAA==.Drosidon:BAABLgAECn8VAAIdAAcJXQay/QCvAAAdAAcJXQay/QCvAAAAAA==.Drubo:BAAALgAECgUJBQAAAA==.Druiisa:BAAALgAECgEJAQABLgAECgcJIAAbAE0JAA==.Drx:BAABLgAECn8dAAMbAAgJRQm7BwD+AAAbAAgJRQm7BwD+AAAeAAgJdwfoBADvAAABLgAECgkJNgAXAA4VAA==.',
Ea='Earsog:BAAALgADCgEJAQAAAA==.Earthenfist:BAAALgAECgEJAQAAAA==.',
Eb='Ebebebebe:BAAALgAECgEJAQAAAA==.',
Ef='Efbomb:BAAALgADCgcJBwAAAA==.',
Ei='Eitherindel:BAAALgADCgkJCgAAAA==.',
El='Elanore:BAAALgAECgUJBwAAAA==.Ellaini:BAABLgAECn8SAAIfAAgJoAtmMwBMAQAfAAgJoAtmMwBMAQAAAA==.Ellie:BAABLgAFFH8VAAIKAAQJDSATEQBJAQAKAAQJDSATEQBJAQAAAA==.Elloise:BAAALgADCgYJBgAAAA==.Elseb:BAAALgAECgQJCQAAAA==.',
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
Fo='Forever:BAAALgAECgMJBQABLgAFFAMJCQAKANEiAA==.Formortiis:BAAALgADCgEJAQAAAA==.Forrestior:BAABLgAECn8YAAIgAAgJoiShAQBBAwAgAAgJoiShAQBBAwAAAA==.Forsthoof:BAAALgADCgYJBgAAAA==.',
Fr='Fraga:BAAALgAECgYJDgABLgAFFAYJDgAdAM4NAA==.Frailty:BAAALgAECgYJDAAAAA==.Frawst:BAAALgAECgMJAwAAAA==.Frique:BAABLgAECn8fAAIKAAkJLxjbLAAFAgAKAAkJLxjbLAAFAgAAAA==.Frostfingers:BAAALgAECgQJBgAAAA==.Frostyfang:BAABLgAECn8kAAMPAAgJ/xw+EwCKAQAPAAYJpCA+EwCKAQATAAQJthPLVQC5AAAAAA==.Frozenyogert:BAAALgAECgQJBAAAAA==.',
Fu='Fufula:BAAALgADCgQJBAAAAA==.Funkbot:BAAALgAECgYJDAAAAA==.Furgilicious:BAAALgAECgEJAgABLgAECgYJEAABAAAAAA==.',
['Fä']='Färshadow:BAAALgAECgEJAQAAAA==.',
Ga='Galbur:BAACLgAFFH8OAAMdAAYJzg1wgAAGAQAdAAUJzg1wgAAGAQAcAAIJ+REzPwA1AAAuAAQKfykAAx0ACQnFIV8jAHgCAB0ACQnUH18jAHgCABwACAkUFcwXAJ0BAAAA.Galdrin:BAAALgAECgkJCgAAAA==.Galifreya:BAAALgADCgEJAQAAAA==.Gaspode:BAAALgADCgcJBwAAAA==.Gassann:BAAALgAECggJDgAAAA==.',
Ge='Geers:BAABLgAECn8dAAIhAAkJ2SLsDgADAwAhAAkJ2SLsDgADAwAAAA==.Geta:BAAALgAECgQJBwABLgAECgkJIAAEAF0iAA==.Getacast:BAAALgAECgEJAQABLgAECgkJIAAEAF0iAA==.Getademon:BAAALgADCgEJAQABLgAECgkJIAAEAF0iAA==.Getaform:BAAALgAECgEJAQABLgAECgkJIAAEAF0iAA==.Getagrip:BAAALgAECgQJBgABLgAECgkJIAAEAF0iAA==.Getaheal:BAAALgAECgYJBgABLgAECgkJIAAEAF0iAA==.Getalife:BAAALgAECgIJAgABLgAECgkJIAAEAF0iAA==.Getarage:BAABLgAECn8gAAIEAAkJXSIeFACtAgAEAAkJXSIeFACtAgAAAA==.',
Gh='Ghil:BAABLgAECn8vAAMHAAkJqiMTAQADAwAHAAkJqiMTAQADAwAIAAQJnxXfvADfAAAAAA==.',
Gi='Gigawatt:BAABLgAECn82AAMXAAkJDhVgBQCdAQAXAAkJDhVgBQCdAQAKAAMJ/ArJpQCBAAAAAA==.Gildersleeve:BAAALgAECgQJCQAAAA==.Gilia:BAAALgAECggJCQAAAA==.Girthfist:BAABLgAECn8WAAIiAAgJRSMIBQA5AwAiAAgJRSMIBQA5AwABLgAFFAkJGgADABgdAA==.',
Gl='Glynixtwo:BAAALgAECgMJBQAAAA==.',
Go='Goldiwarlock:BAAALgADCgcJFAAAAA==.Goloron:BAAALgADCgkJDwAAAA==.',
Gr='Graymayn:BAABLgAECn8aAAIgAAkJ8BmrCgB0AgAgAAkJ8BmrCgB0AgAAAA==.Gremel:BAABLgAECn8oAAQPAAkJ4B8rBQARAQAWAAUJLhmlHABoAQAPAAcJ1BwrBQARAQATAAMJGRznRAD5AAAAAA==.Gribby:BAAALgAECgcJBwAAAA==.Grimdor:BAAALgAECgYJDAAAAA==.Grimflaps:BAAALgAECgMJBQAAAA==.Grimmist:BAABLgAECn8hAAIZAAcJihjOMgCsAQAZAAcJihjOMgCsAQAAAA==.',
Gu='Guloot:BAABLgAECn8bAAMKAAgJBAbBhgDQAAAKAAgJBAbBhgDQAAAXAAUJtQavhQBkAAAAAA==.Gunboyten:BAAALgAECgMJAwAAAA==.Gunderthirth:BAACLgAFFH8aAAIDAAkJGB08AQDnAQADAAkJGB08AQDnAQAuAAQKfy0AAwMACQmnJKIBAGsDAAMACQmnJKIBAGsDAAQABQmMIt4uAJQBAAAA.Gurkin:BAAALgADCgEJAQAAAA==.',
Gw='Gwaeniiha:BAABLgAECn9SAAIFAAkJSxfcBgATAgAFAAkJSxfcBgATAgAAAA==.Gward:BAAALgAECgUJBgAAAA==.Gwizz:BAABLgAECn8sAAIhAAkJnBsCMABZAgAhAAkJnBsCMABZAgAAAA==.',
Ha='Halibard:BAABLgAFFH8RAAIGAAUJKAvDFgAIAQAGAAUJKAvDFgAIAQAAAA==.Halinka:BAAALgADCgYJBgAAAA==.Handsoap:BAABLgAECn8eAAIOAAkJdA7bHwB7AQAOAAkJdA7bHwB7AQAAAA==.Haquar:BAAALgAECgQJCQAAAA==.Hardhitter:BAABLgAECn9NAAQNAAkJyBo3AgCzAQADAAgJdxnKAgDFAQANAAkJ7RY3AgCzAQAEAAYJMRZBDQDsAAAAAA==.',
He='Hehe:BAAALgADCgQJBAAAAA==.Helldog:BAAALgAECgMJAwABLgAECgkJJQAjALYeAA==.Hellumph:BAABLgAECn8lAAIjAAkJth6/AgDJAgAjAAkJth6/AgDJAgAAAA==.Hellwraith:BAAALgADCggJDgABLgAECgkJJQAjALYeAA==.Hermesconrad:BAABLgAECn8UAAQZAAkJbQ3HOQCKAQAZAAkJbQ3HOQCKAQAYAAcJbAqyQQD5AAAiAAEJWgc5FwAZAAAAAA==.Hevensrath:BAABLgAECn85AAIFAAkJdx/nFgC5AgAFAAkJdx/nFgC5AgAAAA==.',
Ho='Hokuden:BAABLgAECn86AAIkAAkJGhmBCAAFAgAkAAkJGhmBCAAFAgAAAA==.Holphie:BAAALgAECgUJBQAAAA==.Honina:BAAALgADCgIJAgAAAA==.Hornswaggles:BAAALgAECgQJBAAAAA==.Horsebananas:BAAALgAECgMJBgABLgAECgkJRQAgANwdAA==.',
Ht='Htari:BAAALgAFFAIJAwAAAA==.',
Hu='Huddington:BAABLgAECn8jAAIlAAkJ1RfvAgAMAgAlAAkJ1RfvAgAMAgAAAA==.Hussh:BAAALgAECgYJDAABLgAECgkJIwAFAAYaAA==.',
Hy='Hydraness:BAAALgAECgEJAQABLgAECgQJBAABAAAAAA==.',
Ia='Iamcammy:BAAALgAECgYJEAAAAA==.',
Ic='Icedragon:BAAALgAECgkJBwAAAA==.',
Ig='Igknight:BAAALgAECgMJAwABLgAFFAIJAwABAAAAAA==.',
Il='Illexi:BAAALgADCgYJBgAAAA==.',
Im='Imariz:BAAALgAECgcJBwAAAA==.Imdarkness:BAAALgAFFAEJAQAAAA==.Impquisitor:BAAALgAECgYJBwAAAA==.',
In='Indecent:BAABLgAECn8zAAQIAAkJOh3hFQCiAgAIAAkJOh3hFQCiAgAJAAYJHBd3FACnAQAHAAMJ3hQLGAC7AAAAAA==.Indeed:BAAALgAECgUJBgAAAA==.Inibble:BAAALgAECgEJAQAAAA==.',
Ir='Irozi:BAAALgAECgEJAQAAAA==.',
Is='Ishy:BAAALgAECgUJCAAAAA==.',
Ix='Ixelle:BAAALgADCgUJDQABLgAECgYJEQABAAAAAA==.',
Iz='Izomar:BAABLgAECn8gAAIhAAgJahkXTQD0AQAhAAgJahkXTQD0AQAAAA==.',
Ja='Jack:BAAALgAECgEJAgAAAA==.Jackieechan:BAAALgAFFAEJAQABLgAFFAUJDwALAL8kAA==.Jackiemays:BAACLgAFFH8PAAMLAAUJvySWEQCpAQALAAQJQCaWEQCpAQAFAAIJsQFtywA1AAAuAAQKfzEAAwsACAkUJDIOALECAAsACAkUJDIOALECAAUACAlgGnY9AC8CAAAA.Jaded:BAAALgAECgcJDQAAAA==.Jaleigha:BAAALgADCgcJDgAAAA==.Jamesin:BAAALgAECgYJCAAAAA==.',
Je='Jedaii:BAAALgAECgYJBgAAAA==.Jeff:BAAALgAECgEJAwAAAA==.Jeses:BAABLgAECn8vAAIFAAkJQhaJQgD/AQAFAAkJQhaJQgD/AQABLgAFFAIJBQAVAPcLAA==.',
Jo='Joe:BAAALgAECgEJAQAAAA==.Johmjohm:BAAALgAECgQJBAAAAA==.Jollah:BAAALgAECgUJBgAAAA==.',
Ju='Justankh:BAAALgAECgEJAQAAAA==.Jutic:BAACLgAFFH8JAAIKAAMJ/hjIQgDcAAAKAAMJ/hjIQgDcAAAuAAQKfzoAAgoACQnOIj0IACwDAAoACQnOIj0IACwDAAAA.',
Jy='Jyssa:BAAALgADCgEJAQAAAA==.',
['Jö']='Jörmun:BAAALgAFFAIJBAAAAA==.',
Ka='Kaelys:BAAALgAECgEJAQAAAA==.Kageken:BAAALgADCgUJBQABLgAECgQJBwABAAAAAA==.Kaia:BAABLgAECn8lAAIRAAkJgA/NGADUAQARAAkJgA/NGADUAQAAAA==.Kaldrich:BAAALgAECgMJBAAAAA==.Kamoto:BAAALgAECgUJBQABLgAECgkJNgAXAA4VAA==.Kanetsu:BAAALgADCgIJAgAAAA==.Kardas:BAABLgAECn8YAAMVAAkJuQdDbABpAQAVAAkJuQdDbABpAQAmAAMJ1AGLfABSAAAAAA==.Kardio:BAACLgAFFH8FAAIYAAQJ6gygKACvAAAYAAQJ6gygKACvAAAuAAQKfxoAAxgACAn+EK0rAIEBABgACAn+EK0rAIEBABkAAQkBClBnADUAAAAA.Kayj:BAAALgAECgEJAgAAAA==.Kayrina:BAAALgADCgkJCgAAAA==.Kazeer:BAABLgAECn8gAAIFAAkJJAnUmgBAAQAFAAkJJAnUmgBAAQAAAA==.',
Kb='Kbilly:BAABLgAECn9EAAIKAAkJVyIoBgBOAwAKAAkJVyIoBgBOAwAAAA==.',
Ke='Kegger:BAAALgAECgEJAQAAAA==.Keirani:BAAALgAECgEJAQAAAA==.Keylerin:BAACLgAFFH8fAAIRAAcJXR5tDQC7AQARAAcJXR5tDQC7AQAuAAQKfyEAAhEACQmAGkgTAH4CABEACQmAGkgTAH4CAAAA.',
Ki='Kibbik:BAACLgAFFH8NAAIfAAUJcAhdIADxAAAfAAUJcAhdIADxAAAuAAQKfy0AAh8ACQkyF8waAO8BAB8ACQkyF8waAO8BAAAA.Kiboom:BAAALgADCgMJAwABLgAFFAUJDQAfAHAIAA==.Kija:BAAALgAECgcJDAAAAA==.Kitoro:BAAALgAECgEJAQAAAA==.Kitsunami:BAAALgAECgcJBgAAAA==.',
Kl='Klepal:BAAALgADCgkJCgAAAA==.Klutchshield:BAAALgAECgEJAQAAAA==.',
Kn='Kneecap:BAAALgAECgUJCQAAAA==.Knottes:BAAALgAECgIJCAAAAA==.',
Ko='Kobe:BAAALgAECgYJEwAAAA==.Koharu:BAAALgADCggJHAAAAA==.Kookykg:BAAALgAECgEJAQAAAA==.',
Kr='Krampus:BAABLgAECn85AAIaAAkJExTZCgAKAgAaAAkJExTZCgAKAgAAAA==.Kranok:BAAALgAECgYJDgAAAA==.Krennthis:BAAALgAECgIJAgABLgAECgYJEQABAAAAAA==.Krim:BAAALgADCgUJBgAAAA==.Krimdevourer:BAAALgADCgYJBgAAAA==.Krimhuntress:BAAALgAECgEJAgAAAA==.',
Ku='Kunac:BAABLgAECn8aAAIEAAkJSRbqIQDjAQAEAAkJSRbqIQDjAQAAAA==.',
Ky='Kynessa:BAAALgAECgYJEQAAAA==.Kyran:BAAALgAECgYJBgAAAA==.Kyrron:BAAALgAECgYJDQAAAA==.Kyrun:BAABLgAECn84AAIaAAkJlg+iBQAQAQAaAAkJlg+iBQAQAQAAAA==.Kyuutips:BAAALgAECgEJAQAAAA==.',
['Kã']='Kãne:BAACLgAFFH8QAAIbAAMJaQxuJACTAAAbAAMJaQxuJACTAAAuAAQKfyQAAxsACQmFEQQsAI0BABsACQmFEQQsAI0BAAwAAgm9Bpo4AFQAAAAA.',
La='Lamoran:BAAALgADCgkJDwAAAA==.Lannes:BAAALgAECgEJAwAAAA==.Lapz:BAAALgAECgkJEQAAAA==.Lavetra:BAAALgAECgMJBAAAAA==.Lazerdinger:BAAALgAECgEJAQAAAA==.',
Le='Legendary:BAACLgAFFH8IAAIUAAIJ0h2QEAB+AAAUAAIJ0h2QEAB+AAAuAAQKfxQAAhQACQlbIMQDANcCABQACQlbIMQDANcCAAAA.Lethran:BAAALgAECgYJCQAAAA==.',
Lh='Lhani:BAABLgAECn8oAAIGAAkJORJ8HgDRAQAGAAkJORJ8HgDRAQAAAA==.',
Li='Liadrin:BAABLgAECn8jAAMFAAkJBhrUDACKAQAUAAkJzRZ0DwDNAQAFAAUJvyLUDACKAQAAAA==.Lie:BAABLgAECn8eAAIMAAgJjw9LCgB7AQAMAAgJjw9LCgB7AQAAAA==.Liliana:BAAALgADCgkJNwAAAA==.Lirrasha:BAAALgADCgYJDwAAAA==.',
Ll='Llyrael:BAABLgAECn8eAAMGAAkJ/grLKgByAQAGAAkJ/grLKgByAQAfAAIJxAOplgAjAAAAAA==.',
Lo='Lolineverdie:BAABLgAECn8aAAMCAAkJ4gqOWgAoAQACAAkJ4gqOWgAoAQATAAYJnQI2bQBvAAAAAA==.Lothoriel:BAAALgAECgEJAQAAAA==.',
Lu='Luna:BAABLgAECn8iAAMGAAgJEQrzLQCNAQAGAAgJEQrzLQCNAQAfAAgJ1QcFOwAmAQAAAA==.',
Ly='Lyrev:BAAALgAECgYJEwAAAA==.',
['Ló']='Lórien:BAAALgAECgEJAQAAAA==.',
Ma='Macaoidh:BAAALgAECgYJBgAAAA==.Maddeleine:BAABLgAECn8lAAQGAAgJlhWrGAAHAgAGAAgJlhWrGAAHAgAfAAMJzRDKWwCnAAAnAAQJtArjVwCgAAAAAA==.Magicdemon:BAABLgAECn83AAMOAAkJ2iVRCQCVAgAOAAkJpyVRCQCVAgAQAAgJnSCcHQBjAgAAAA==.Magichunter:BAAALgAECgEJAQABLgAECgkJNwAOANolAA==.Makall:BAAALgADCgEJAQAAAA==.Makanoa:BAAALgAECgYJCQAAAA==.Malaah:BAABLgAECn9LAAIXAAkJghhhBwBbAQAXAAkJghhhBwBbAQAAAA==.Malafar:BAAALgAFFAIJAwAAAA==.Malatrixx:BAAALgAECggJCQAAAA==.Maldiriel:BAAALgAECggJCAAAAA==.Mallikus:BAAALgADCgkJCgAAAA==.Manofsecks:BAAALgAECgQJDAAAAA==.Mansuno:BAAALgAECggJDQAAAA==.Mapachote:BAABLgAECn8vAAImAAgJ6B3MBABhAgAmAAgJ6B3MBABhAgAAAA==.Marodin:BAAALgAECgEJAQAAAA==.Marthaiden:BAAALgAECgkJDgAAAA==.Maryjaina:BAAALgADCgYJBgAAAA==.Mashedpotato:BAAALgADCgQJBAAAAA==.Maully:BAAALgAFFAEJAgAAAA==.Mavastus:BAAALgADCgcJBwAAAA==.Mazboda:BAABLgAECn8YAAMIAAkJNxQ3BQDwAQAIAAkJYhM3BQDwAQAHAAEJ2gtuEgAyAAAAAA==.Mazozul:BAABLgAECn9DAAQnAAkJ1RaBGAAPAgAnAAkJixSBGAAPAgAGAAUJ/BRnQADsAAAfAAYJLA5TDADqAAAAAA==.',
Me='Meatbaal:BAAALgAECgMJAwAAAA==.Medïc:BAAALgADCgIJAgAAAA==.Melinaria:BAABLgAECn8oAAMfAAkJMBVBHADjAQAfAAkJMBVBHADjAQAnAAEJ6gFXiQAhAAAAAA==.Melisondraa:BAAALgADCgkJCQAAAA==.Meow:BAAALgADCgQJBAAAAA==.Merkabai:BAAALgAECgIJAgAAAA==.Merkala:BAAALgADCgYJCQAAAA==.Metalbot:BAAALgADCgkJCQAAAA==.',
Mi='Miarose:BAAALgAECgUJBgAAAA==.Miggydogg:BAAALgAECgUJCwAAAA==.Mileta:BAABLgAECn8bAAITAAkJSRfpEgA+AgATAAkJSRfpEgA+AgAAAA==.Mimic:BAAALgAECgIJAgAAAA==.Minthammer:BAAALgAECgIJBAABLgAFFAIJBAABAAAAAA==.Mirilkka:BAAALgADCgkJCQAAAA==.Mirthias:BAAALgAECgMJAwAAAA==.Mistlock:BAAALgAECgQJBAAAAA==.Mistylady:BAAALgAECgIJAgAAAA==.',
Mj='Mjöllnir:BAABLgAECn8UAAIXAAcJpgnCQwA6AQAXAAcJpgnCQwA6AQAAAA==.',
Mo='Monki:BAAALgAFFAEJAQABLgAFFAUJDQAfAHAIAA==.Moozohar:BAAALgADCgEJAQAAAA==.Morgorra:BAAALgAECgMJBwAAAA==.Mormekil:BAAALgAECgIJAgAAAA==.Morvila:BAAALgAECgMJAwAAAA==.Mote:BAABLgAECn8sAAMfAAkJ7RSnHgDQAQAfAAkJ7RSnHgDQAQAnAAcJUxf6HwDNAQAAAA==.',
Mu='Muertes:BAAALgAECgEJAQAAAA==.Multidollar:BAAALgADCgUJBQABLgAFFAYJFgAVAJcTAA==.Muminah:BAAALgAECgMJBgAAAA==.',
['Mô']='Môlly:BAACLgAFFH8OAAIGAAYJ5h6VCgCiAQAGAAYJ5h6VCgCiAQAuAAQKfysAAgYACQkGIZUFAPYCAAYACQkGIZUFAPYCAAAA.',
Na='Narnluz:BAABLgAECn8dAAIGAAgJfBegGQD+AQAGAAgJfBegGQD+AQAAAA==.Nastiepastie:BAAALgADCgYJBgAAAA==.Nazor:BAABLgAECn8nAAIQAAgJ1xnzPwDJAQAQAAgJ1xnzPwDJAQAAAA==.',
Ne='Necronic:BAAALgADCgYJCwAAAA==.Necroreign:BAABLgAECn9YAAIOAAkJ7h+iAQCoAgAOAAkJ7h+iAQCoAgAAAA==.Neith:BAAALgADCgMJAwAAAA==.Nemera:BAAALgADCgYJCAAAAA==.Nervous:BAABLgAFFH8JAAIKAAMJ0SKzMAAfAQAKAAMJ0SKzMAAfAQAAAA==.Nessee:BAAALgAECgYJEgAAAA==.',
Ni='Niall:BAABLgAECn8zAAIPAAkJ3yEtAwDnAgAPAAkJ3yEtAwDnAgAAAA==.Nilithis:BAABLgAECn8rAAMIAAkJeRkCLgAgAgAIAAkJCxkCLgAgAgAJAAQJGxMGIQCmAAAAAA==.Niú:BAAALgADCgYJBgAAAA==.',
No='Norixa:BAAALgADCgkJCQAAAA==.Nozmua:BAAALgADCgkJDgAAAA==.',
Ny='Nyghtchyld:BAAALgAECgcJEgAAAA==.Nyxlumina:BAAALgAECgIJAgAAAA==.',
['Né']='Néssima:BAABLgAECn8jAAMFAAkJ0RVTbACVAQAFAAkJZw5TbACVAQAUAAUJYhuaIwDrAAAAAA==.',
['Nø']='Nøx:BAAALgAFFAEJAQAAAA==.',
Oa='Oak:BAAALgAECgEJBQAAAA==.Oathfinder:BAAALgAECgcJEAAAAA==.',
Oc='Occurrence:BAABLgAECn8VAAMCAAgJ2gWIggC0AAACAAcJBwSIggC0AAATAAEJZwLtowAeAAAAAA==.Octalexane:BAAALgAECgUJBgABLgAECgkJIAAKAOUIAA==.',
Om='Omalu:BAAALgAECgEJAQABLgAECggJHgAMAI8PAA==.',
On='Onebuttonman:BAAALgADCgYJBgAAAA==.Onimusha:BAAALgAECgMJAwAAAA==.',
Or='Ortalbem:BAACLgAFFH8HAAIhAAIJVBSrUwCGAAAhAAIJVBSrUwCGAAAuAAQKfzoAAiEACQkXI+4RAO4CACEACQkXI+4RAO4CAAAA.',
Ov='Ovi:BAAALgADCgIJAgAAAA==.',
Pa='Pandariee:BAABLgAECn8VAAIdAAgJYw26fABqAQAdAAgJYw26fABqAQAAAA==.Pangsh:BAABLgAFFH8IAAIiAAMJBAWbQACjAAAiAAMJBAWbQACjAAAAAA==.Parzval:BAAALgAECgEJAgAAAA==.Paxgor:BAAALgAECgEJAQAAAA==.',
Pe='Pendaemonia:BAABLgAECn82AAIOAAkJuRZ7EgAFAgAOAAkJuRZ7EgAFAgAAAA==.Penelopie:BAAALgADCgYJBgAAAA==.Percfirdy:BAAALgADCgUJBQAAAA==.',
Ph='Pherix:BAABLgAECn8cAAIfAAcJ1SC+FwAKAgAfAAcJ1SC+FwAKAgAAAA==.Phiirys:BAAALgAECgYJBgAAAA==.',
Pi='Picaso:BAAALgADCgEJAQAAAA==.Pight:BAAALgAECggJEAABLgAECggJHgAMAI8PAA==.',
Po='Poomacha:BAABLgAECn8rAAIVAAgJexXhSgDBAQAVAAgJexXhSgDBAQAAAA==.Popout:BAAALgADCgUJBAAAAA==.Popstar:BAAALgAECgEJAQAAAA==.',
Pu='Puffthemagic:BAAALgADCgYJCAAAAA==.Punishêr:BAAALgADCgMJAwABLgAFFAEJAQABAAAAAA==.',
Py='Pyree:BAABLgAECn8kAAMbAAkJgxCLLACLAQAbAAkJ4w+LLACLAQAMAAcJaAm0GwBvAAAAAA==.Pyxrin:BAAALgAECgcJBwAAAA==.',
['Pø']='Pøë:BAAALgAECgkJEwABLgAFFAQJBQAQAFwHAA==.',
Qu='Qu:BAAALgAFFAIJBQABLgAFFAMJCQAPAHsZAQ==.Quina:BAAALgADCgIJAgAAAA==.',
Qv='Qveemcorkie:BAAALgAECgEJAQAAAA==.',
['Qí']='Qín:BAAALgADCgUJAwAAAA==.',
Ra='Radagust:BAAALgAECgQJBAAAAA==.Radcat:BAAALgAECgEJBAAAAA==.Raenne:BAAALgAECgMJBQAAAA==.Ragebait:BAAALgADCgIJAgAAAA==.Rainfall:BAAALgAECgEJAgAAAA==.Rainvelle:BAAALgAECgUJBQAAAA==.Raistlain:BAAALgAECgYJDwAAAA==.Raitha:BAAALgADCgUJCAAAAA==.Ralli:BAACLgAFFH8JAAMQAAQJIBvFTgAAAQAQAAMJIBvFTgAAAQAOAAEJAADSJgAAAAAuAAQKfy0AAhAACAmiGa4zAPcBABAACAmiGa4zAPcBAAAA.Rallsdemon:BAAALgAECgQJBAABLgAFFAQJBwAkAHENAA==.Rallsdk:BAABLgAFFH8HAAMkAAQJcQ39DADLAAAkAAMJKA79DADLAAAdAAEJTAuspAA4AAAAAA==.Rallsodins:BAAALgAECgYJBgABLgAFFAQJBwAkAHENAA==.Randomguy:BAACLgAFFH8PAAIRAAQJ9Rm8FQBeAQARAAQJ9Rm8FQBeAQAuAAQKfzgAAhEACQnYJT0CADsDABEACQnYJT0CADsDAAAA.Ranulf:BAAALgAECgQJBgAAAA==.Ratava:BAAALgAECggJCgAAAA==.Ratboy:BAEALgAECgEJAQABLgAECgkJMgAnABwjAA==.Ratrot:BAABLgAECn8tAAMKAAkJPB5tEwCxAgAKAAkJPB5tEwCxAgAXAAEJiw4jKwAsAAAAAA==.Ratsdead:BAAALgAECgEJAQAAAA==.Razenath:BAAALgADCgcJDAAAAA==.',
Re='Reddemon:BAAALgAECgEJAQAAAA==.Redhourn:BAAALgAECgMJAwAAAA==.Reinhardt:BAAALgADCgYJBgAAAA==.Rekrella:BAAALgADCgUJBQAAAA==.Reldarus:BAEBLgAECn8yAAMnAAkJHCPTAgCBAwAnAAkJHCPTAgCBAwAGAAQJ+hr8RAAlAQAAAA==.Rena:BAAALgADCgcJBwAAAA==.Rendia:BAAALgADCgMJAwAAAA==.Renik:BAAALgADCgIJAQAAAA==.Revennek:BAAALgAECgUJCgAAAA==.Reverence:BAABLgAECn8eAAIFAAkJ8A35YgCqAQAFAAkJ8A35YgCqAQAAAA==.Revilation:BAABLgAECn8cAAIUAAkJYBPZEwCOAQAUAAkJYBPZEwCOAQAAAA==.Rezjyk:BAAALgAECgYJCAABLgAECgkJNgAFANwcAA==.Rezzyk:BAABLgAECn82AAIFAAkJ3Bw+GgCmAgAFAAkJ3Bw+GgCmAgAAAA==.',
Rh='Rhonus:BAAALgAECgcJCAAAAA==.Rhyxali:BAABLgAECn8lAAQJAAkJIA1xEQAvAQAJAAkJOAxxEQAvAQAHAAYJLAdQHADcAAAIAAUJkgp9GQChAAAAAA==.',
Ri='Riidefi:BAAALgADCgMJAwABLgAECgkJDAABAAAAAA==.Riilock:BAAALgAECgMJAwABLgAECgkJDAABAAAAAA==.Riis:BAAALgAECgYJDAAAAA==.Riiselock:BAABLgAECn8tAAMIAAgJIR5CNwAvAgAIAAcJyR1CNwAvAgAJAAQJFBwOGADhAAAAAA==.Riivive:BAAALgAECggJCAAAAA==.Riktade:BAAALgADCgYJBgAAAA==.Rilight:BAAALgAECgQJBAABLgAECgkJDAABAAAAAA==.Riptidepod:BAABLgAECn8gAAMKAAkJ5QhmVQBgAQAKAAkJ5QhmVQBgAQAXAAIJ3gJ/wQAcAAAAAA==.',
Ro='Robbiebrews:BAAALgADCgUJBQAAAA==.Robear:BAAALgAECgEJAQAAAA==.Robeart:BAAALgAECgEJAgAAAA==.Rolim:BAAALgADCgIJAgAAAA==.Rowin:BAAALgADCgUJBQAAAA==.',
Ru='Ruddigore:BAAALgAECgEJAQAAAA==.Ruubyy:BAAALgAECgEJAQAAAA==.',
Ry='Rynley:BAABLgAECn8WAAMRAAUJASEKJwDAAQARAAUJASEKJwDAAQAoAAIJWRH3GwBtAAAAAA==.',
Sa='Sableanne:BAAALgADCgMJBAAAAA==.Sacredscales:BAABLgAECn8hAAMGAAkJtR5kCwCaAgAGAAcJ3yRkCwCaAgAfAAcJtRSGKgCGAQAAAA==.Sagerremeseb:BAAALgAECgQJCQAAAA==.Sakii:BAABLgAECn8lAAIQAAkJJRIGOgDfAQAQAAkJJRIGOgDfAQAAAA==.Salera:BAAALgADCgQJBAAAAA==.Salvion:BAAALgAECgcJAQABLgAECgkJJwAQANcZAA==.Samvimes:BAABLgAECn9QAAIFAAkJMxQWCQDVAQAFAAkJMxQWCQDVAQAAAA==.Sangreene:BAABLgAECn8dAAIfAAgJRxqFEwBYAgAfAAgJRxqFEwBYAgAAAA==.Sargis:BAACLgAFFH8KAAIFAAMJpxxaXQD1AAAFAAMJpxxaXQD1AAAuAAQKf2EAAwUACQklJOgIACMDAAUACQklJOgIACMDAAsACAnHG1gbACkCAAAA.Sarial:BAAALgADCgMJAwAAAA==.',
Sc='Schrödinger:BAAALgAECgYJDwABLgAECgkJGQAUAO0YAA==.Sciblasts:BAAALgADCgEJAQABLgAECgkJHgAWAM4LAA==.Scott:BAACLgAFFH8pAAIQAAkJaB8xBgCwAgAQAAkJaB8xBgCwAgAuAAQKf0YAAhAACQmaJnUAAO4DABAACQmaJnUAAO4DAAAA.Scratchh:BAABLgAECn8dAAIiAAgJlAstNgB0AQAiAAgJlAstNgB0AQAAAA==.Scrolls:BAAALgAECgEJAwAAAA==.',
Se='Searalsa:BAAALgAECgUJCAABLgAFFAQJDQAaAFIJAA==.Sentis:BAABLgAECn8fAAITAAgJOgfERAD5AAATAAgJOgfERAD5AAAAAA==.Serissa:BAAALgAECgIJAgAAAA==.Serjankins:BAAALgAECgYJCgAAAA==.',
Sh='Shadowbrooks:BAAALgAECgIJAgAAAA==.Shadowgiver:BAAALgADCgcJDwAAAA==.Shadowsdemon:BAAALgADCgEJAQAAAA==.Shadowsworn:BAAALgAECgEJAQAAAA==.Shagol:BAAALgAECgQJBwAAAA==.Shalriss:BAABLgAECn8nAAIfAAkJCBtLEABZAgAfAAkJCBtLEABZAgAAAA==.Shambolance:BAAALgADCgEJAQAAAA==.Shamemoon:BAABLgAECn8fAAIQAAkJjhdZLwAJAgAQAAkJjhdZLwAJAgAAAA==.Shamunroe:BAABLgAECn8pAAMKAAkJMAfGYAA5AQAKAAkJMAfGYAA5AQAXAAUJkxKwWgDZAAAAAA==.Shatterhoof:BAABLgAECn8jAAIPAAkJTgwGIQAAAQAPAAkJTgwGIQAAAQAAAA==.Shelle:BAAALgAECgYJCgAAAA==.Shiftys:BAAALgADCgUJCgABLgAFFAIJAwABAAAAAA==.Shingra:BAACLgAFFH8qAAIbAAgJxRaUGQCZAQAbAAgJxRaUGQCZAQAuAAQKfygAAhsACQnGHSgOAH8CABsACQnGHSgOAH8CAAAA.Shoof:BAAALgADCgUJBQAAAA==.Shyzngiggles:BAAALgAFFAEJAQABLgAFFAQJBQAQAFwHAA==.Shënzi:BAAALgAECgcJBwAAAA==.',
Si='Sifû:BAAALgADCgcJDgAAAA==.Sigourney:BAAALgAECgcJCwABLgAECgkJRQAgANwdAA==.Silversalt:BAAALgAECgIJAgABLgAECgUJBQABAAAAAA==.Silversho:BAAALgAECgUJBQAAAA==.Silvoid:BAAALgADCgMJAwABLgAECgUJBQABAAAAAA==.Silvren:BAABLgAECn83AAMEAAgJ1BgWCABLAQAEAAgJ1BgWCABLAQANAAEJvwZoRgArAAAAAA==.Sindarion:BAAALgAECgUJBQABLgAFFAEJAgABAAAAAA==.Sinkrim:BAAALgAECgMJBAAAAA==.Sinnerr:BAAALgAECgEJAQAAAA==.Sinz:BAAALgAECgEJBQAAAA==.Siph:BAAALgAECgEJAQAAAA==.',
Sk='Skillidan:BAABLgAECn8nAAICAAkJQhopFQChAgACAAkJQhopFQChAgAAAA==.',
Sl='Slayde:BAAALgAECgEJAQAAAA==.Slighttrash:BAABLgAECn8tAAIgAAkJiBQjGADgAQAgAAkJiBQjGADgAQAAAA==.Sloppy:BAAALgADCgkJCgAAAA==.',
Sm='Smacka:BAAALgAECgEJAQAAAA==.Smallcrow:BAACLgAFFH8lAAMYAAkJYB6PAQB+AgAYAAkJYB6PAQB+AgAZAAEJQwvMXgBDAAAuAAQKfxYAAhgABwkuJsQHAP8CABgABwkuJsQHAP8CAAAA.Smores:BAAALgADCgkJEgAAAA==.Smøke:BAAALgAECgMJAwAAAA==.',
Sn='Snallygaster:BAAALgADCgYJDAABLgAECgkJIwAWAJ8bAA==.Snowsong:BAAALgAECgEJAQAAAA==.',
So='Soff:BAAALgAECgEJAQAAAA==.Somdot:BAAALgAECgkJCQABLgAFFAcJBwAJAJ4AAA==.Somdots:BAABLgAFFH8HAAIJAAcJngDlFAAiAAAJAAcJngDlFAAiAAAAAA==.',
Sp='Spamton:BAAALgADCgEJAQAAAA==.Spectrose:BAAALgADCgEJAQAAAA==.Spirit:BAAALgAECgEJAgAAAA==.Spiro:BAAALgAFFAIJAgABLgAFFAQJBQAQAFwHAA==.Spøngè:BAAALgADCgMJAwAAAA==.',
St='Starge:BAAALgAFFAEJAwAAAA==.Starre:BAAALgAECgYJBwAAAA==.Steffey:BAABLgAECn8kAAIKAAkJfgq7YQA2AQAKAAkJfgq7YQA2AQAAAA==.Stoikk:BAAALgADCgEJAQAAAA==.Straven:BAABLgAECn8qAAIhAAkJ4RUqFAAxAQAhAAkJ4RUqFAAxAQAAAA==.Sturgeson:BAACLgAFFH8lAAIDAAgJURpZCQCdAQADAAgJURpZCQCdAQAuAAQKfx8AAgMACQlvHQcMAEsCAAMACQlvHQcMAEsCAAAA.',
Su='Sulfato:BAAALgADCgEJAQAAAA==.Sulwen:BAABLgAECn9oAAMGAAkJyB4kAQDjAgAGAAkJyB4kAQDjAgAfAAEJ1AYRLAAgAAAAAA==.Supertank:BAAALgADCgUJBQAAAA==.Suzakã:BAABLgAECn8WAAIhAAkJ0wl5EABVAQAhAAkJ0wl5EABVAQAAAA==.',
Sw='Sweetpotato:BAAALgADCgEJAQAAAA==.Swiftfeet:BAABLgAECn8lAAIVAAkJABRHQwDYAQAVAAkJABRHQwDYAQAAAA==.',
Sy='Syrasia:BAAALgADCgUJBQAAAA==.Syselea:BAAALgADCgEJAQAAAA==.',
['Sö']='Söranin:BAABLgAECn8dAAIZAAYJ5xi0MwCoAQAZAAYJ5xi0MwCoAQAAAA==.',
Ta='Tachichan:BAAALgAECgYJBgAAAA==.Tadum:BAAALgADCgEJAQAAAA==.Taeili:BAABLgAECn8gAAMWAAkJIhXfKAATAQATAAgJ2BVoNgBiAQAWAAYJKxPfKAATAQAAAA==.Tagilla:BAAALgADCgcJBwAAAA==.Talisse:BAAALgADCgYJBgAAAA==.Tanequil:BAACLgAFFH8KAAICAAQJdwJrWQBnAAACAAQJdwJrWQBnAAAuAAQKfycAAgIACQnfDddKAHgBAAIACQnfDddKAHgBAAAA.Taosha:BAAALgAECgcJDAAAAA==.Targaryian:BAAALgAECgMJAwAAAA==.Tav:BAAALgADCgUJBQAAAA==.Taylea:BAABLgAECn8WAAIhAAcJpA9etQAZAQAhAAcJpA9etQAZAQABLgAECgkJLQAFAE0gAA==.',
Te='Techromancer:BAAALgAECgYJCAABLgAECgcJHAAfANUgAA==.Telleria:BAAALgAECgMJBAAAAA==.Tem:BAAALgAECgMJAwAAAA==.Tenumbras:BAAALgAECgYJDAAAAA==.Termonda:BAAALgAECgEJAQAAAA==.Terraclaw:BAAALgADCgUJBwAAAA==.Terrasia:BAAALgADCgYJBgAAAA==.Terrigino:BAAALgAECgUJAwAAAA==.',
Th='Thanatias:BAABLgAECn8aAAIcAAkJmhSAFgC1AQAcAAkJmhSAFgC1AQAAAA==.Thantasia:BAABLgAECn8WAAIhAAcJogOA1gDoAAAhAAcJogOA1gDoAAAAAA==.Thauras:BAAALgADCgcJFwAAAA==.Theeslan:BAABLgAECn83AAIfAAkJDgmeDADlAAAfAAkJDgmeDADlAAAAAA==.Theodis:BAAALgAECgIJAgAAAA==.Thokdar:BAAALgAECgUJBQAAAA==.Thom:BAACLgAFFH8MAAIkAAUJihAoEQALAQAkAAUJihAoEQALAQAuAAQKfysAAyQACQksJOcAABwDACQACQksJOcAABwDAB0ABgmoDjmxACABAAAA.Thør:BAAALgADCgcJDgAAAA==.',
Ti='Tiernay:BAAALgADCgEJAQAAAA==.Tifà:BAAALgAECgUJCAAAAA==.Timothy:BAABLgAECn8bAAIOAAkJ7BgzEgAJAgAOAAkJ7BgzEgAJAgAAAA==.Timothyjohn:BAAALgAECgYJBgAAAA==.Tinkphooey:BAAALgAECgYJCwAAAA==.Tinton:BAAALgADCgEJAQAAAA==.',
To='Toishi:BAAALgAECgEJAQAAAA==.Tormmok:BAAALgAECgYJDAAAAA==.Tosh:BAAALgAECgQJBAAAAA==.Toshiden:BAAALgAECgEJAQAAAA==.Toshin:BAAALgAECgMJAwAAAA==.Toshindo:BAAALgAECgEJAgAAAA==.Totemkib:BAAALgAECgEJBAABLgAFFAUJDQAfAHAIAA==.',
Tr='Traazz:BAAALgAECgkJAwAAAA==.Trashpally:BAAALgAECgEJAgAAAA==.Tremèndor:BAAALgADCgMJAwAAAA==.Trey:BAAALgAECgEJAQAAAA==.Tristra:BAAALgAECgQJBAAAAA==.',
Ts='Tsuruga:BAABLgAECn85AAIiAAkJQA5iIgCWAQAiAAkJQA5iIgCWAQAAAA==.',
Tu='Turkwise:BAABLgAECn87AAMWAAkJVx1+BgCWAgAWAAkJVx1+BgCWAgAPAAQJCBGsHgDuAAAAAA==.',
Ty='Tycondrius:BAAALgAECgEJAQAAAA==.Tyresh:BAAALgAECgEJAQAAAA==.Tyrinor:BAAALgADCgUJBQAAAA==.',
Ul='Ulogasm:BAAALgADCgkJCgAAAA==.',
Us='Usami:BAAALgAECgEJAQAAAA==.',
Ut='Utako:BAAALgAECgIJAgAAAA==.',
Uv='Uvari:BAABLgAECn8dAAIGAAkJYhCnKACBAQAGAAkJYhCnKACBAQAAAA==.',
Va='Vaclar:BAABLgAFFH8GAAINAAQJKxnaCwD5AAANAAQJKxnaCwD5AAABLgAFFAYJDgAYAA8gAA==.Valhalaa:BAAALgADCgYJBgAAAA==.Valkryee:BAAALgAECgkJDQAAAA==.Valton:BAACLgAFFH8OAAMYAAYJDyDOCwBnAQAYAAUJryHOCwBnAQAiAAEJjBmNHgBLAAAuAAQKf0cAAhgACQmEJsQAAHoDABgACQmEJsQAAHoDAAAA.Vanillanice:BAABLgAECn8UAAMdAAgJ5wuqrwAVAQAdAAYJjw6qrwAVAQAcAAcJHwgKDgCCAAAAAA==.Varrfife:BAAALgAECgQJBAAAAA==.Vaxaldan:BAABLgAECn85AAIcAAkJLQ6QHgBiAQAcAAkJLQ6QHgBiAQAAAA==.',
Ve='Velestre:BAAALgAECgUJBQAAAA==.Velithera:BAAALgADCgMJAwAAAA==.Vellithe:BAABLgAECn8iAAIFAAcJpw8LGQAHAQAFAAcJpw8LGQAHAQAAAA==.Vengy:BAAALgAECgIJAgABLgAECgYJEgABAAAAAA==.Venj:BAAALgAECgUJBgAAAA==.Verhmax:BAAALgADCgYJCwAAAA==.Verton:BAAALgADCgYJBgAAAA==.Vestrae:BAACLgAFFH8LAAMCAAYJcg5JLQD/AAACAAYJcg5JLQD/AAATAAEJSQHTVgAmAAAuAAQKfykAAgIACQnvHW8TAJoCAAIACQnvHW8TAJoCAAAA.Vex:BAABLgAECn8YAAIIAAkJbxr1JgBBAgAIAAkJbxr1JgBBAgAAAA==.',
Vi='Vianel:BAAALgADCggJCAAAAA==.Vilten:BAAALgAECgQJCwAAAA==.Virus:BAAALgAECgkJCQAAAA==.',
Vo='Vodash:BAABLgAECn8jAAIKAAgJmhi4MgDoAQAKAAgJmhi4MgDoAQABLgAECgkJRwACAB8QAA==.Voidwrench:BAAALgAECgMJAwABLgAECgkJJQAJACANAA==.Vostok:BAABLgAECn8eAAIIAAgJOBwtSQC+AQAIAAgJOBwtSQC+AQAAAA==.',
Wa='Wage:BAAALgADCgQJBQAAAA==.Warmth:BAAALgADCgIJAwAAAA==.Warranni:BAAALgAECgUJBQAAAA==.',
We='Weekend:BAAALgAECgEJAQAAAA==.Weslyan:BAAALgAECgEJAQAAAA==.Wetsock:BAAALgAECgYJBwAAAA==.',
Wi='Wikket:BAABLgAECn85AAMTAAkJPRywDQB/AgATAAkJPRywDQB/AgACAAgJ3AMldwDQAAAAAA==.',
Wo='Wolvesbayne:BAAALgAECgEJAQAAAA==.',
Wy='Wyelie:BAAALgAECggJEQAAAA==.Wynono:BAAALgADCgcJBwAAAA==.',
Xa='Xade:BAAALgAFFAEJAQAAAA==.',
Xd='Xdeadlysinz:BAAALgAECgcJDwAAAA==.',
Xo='Xotha:BAACLgAFFH8MAAIQAAIJCxcqPgB1AAAQAAIJCxcqPgB1AAAuAAQKf0IAAhAACQmoHmQVAJgCABAACQmoHmQVAJgCAAAA.',
Xu='Xuen:BAAALgAFFAEJAwAAAA==.',
Xy='Xythera:BAACLgAFFH8IAAIQAAUJtBNdYADPAAAQAAUJtBNdYADPAAAuAAQKfyUAAxAACQnMIvYVANMCABAACQn9IfYVANMCACMAAglDFEILAEgAAAAA.',
Ya='Yaákov:BAABLgAFFH8FAAIQAAMJMgi1OgCIAAAQAAMJMgi1OgCIAAABLgAECgkJJwAQANcZAA==.',
Ye='Yeah:BAAALgADCgYJBgABLgAFFAQJDwAFAD0VAA==.',
Yi='Yinosai:BAAALgAECgYJDAAAAA==.',
Yo='Yougot:BAAALgAECgEJAgAAAA==.',
Yu='Yuji:BAABLgAECn8hAAIJAAYJaR2+CwCEAQAJAAYJaR2+CwCEAQAAAA==.Yukì:BAAALgADCgMJAwAAAA==.Yurie:BAAALgAECgIJAgAAAA==.',
Yv='Yvonna:BAAALgADCgEJAQAAAA==.',
Za='Zaega:BAAALgADCgQJBAABLgAECgkJLQAFAE0gAA==.Zahlee:BAAALgAECgQJBAAAAA==.Zaldin:BAAALgAECgUJCgAAAA==.Zalirina:BAAALgAECgIJAgAAAA==.Zanka:BAAALgAECgIJAgAAAA==.Zaridruid:BAAALgAECgkJCgAAAA==.Zarisedra:BAACLgAFFH8rAAMLAAgJYR1bCQAlAgALAAgJYR1bCQAlAgAFAAEJXgDaOwA2AAAuAAQKfxgAAwsACQkwF8kpAOMBAAsACAkGGMkpAOMBAAUAAQktBuw9ATUAAAAA.Zarissena:BAAALgAECgYJAwAAAA==.Zarris:BAAALgADCgUJDAAAAA==.',
Ze='Zennith:BAAALgADCgMJAwAAAA==.Zerdah:BAAALgAECgEJAwAAAA==.Zernacho:BAABLgAECn8gAAQGAAkJjBqhHwDHAQAGAAYJJhyhHwDHAQAfAAcJ+hFBLgBvAQAnAAMJTRMRVACxAAAAAA==.Zerogasm:BAABLgAECn8lAAIVAAkJxxukBQBIAgAVAAkJxxukBQBIAgAAAA==.Zerolazerfur:BAAALgAECgEJAgAAAA==.Zerolicious:BAAALgAECgQJCAAAAA==.Zeromessiah:BAAALgAECgYJBgAAAA==.Zeromojo:BAAALgAECgUJBQAAAA==.Zerozaddy:BAAALgAECgUJBgAAAA==.Zevvo:BAABLgAECn8wAAIEAAkJECFXCgC/AgAEAAkJECFXCgC/AgAAAA==.',
Zi='Ziggysundust:BAAALgADCgMJAwAAAA==.',
Zo='Zoraji:BAABLgAECn86AAIiAAkJdhrzDgBLAgAiAAkJdhrzDgBLAgAAAA==.',
Zu='Zuganova:BAABLgAFFH8SAAMnAAUJDQi/JAAnAQAnAAUJ4Qe/JAAnAQAGAAEJ8whwFgA8AAAAAA==.Zuggar:BAABLgAECn8fAAIEAAcJVwjTUgD/AAAEAAcJVwjTUgD/AAAAAA==.',
Zy='Zynhammer:BAABLgAECn8oAAMQAAgJgxFhXQCJAQAQAAgJgxFhXQCJAQAOAAEJawbNeQAmAAAAAA==.',
['Év']='Évangeline:BAAALgADCgcJBwAAAA==.',
['Ëb']='Ëbony:BAABLgAFFH8QAAIVAAYJhhsDMABQAQAVAAYJhhsDMABQAQAAAA==.',
['Ëd']='Ëdën:BAABLgAECn8pAAICAAkJrhQ0AwAmAgACAAkJrhQ0AwAmAgAAAA==.',
['Ðø']='Ðøc:BAAALgAECgEJAwAAAA==.',
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
