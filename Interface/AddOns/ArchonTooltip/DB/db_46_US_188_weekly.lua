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

local lookup = {'Unknown-Unknown','Druid-Restoration','Warrior-Protection','Warrior-Fury','Priest-Holy','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Paladin-Retribution','Shaman-Restoration','Paladin-Holy','Evoker-Devastation','Warrior-Arms','DemonHunter-Havoc','Paladin-Protection','Druid-Feral','DemonHunter-Devourer','Rogue-Subtlety','Rogue-Assassination','Druid-Balance','Hunter-BeastMastery','Druid-Guardian','Shaman-Elemental','Monk-Windwalker','Monk-Mistweaver','Shaman-Enhancement','DeathKnight-Blood','DeathKnight-Unholy','Priest-Shadow','Hunter-Survival','Mage-Frost','Monk-Brewmaster','DemonHunter-Vengeance','DeathKnight-Frost','Mage-Arcane','Hunter-Marksmanship','Evoker-Augmentation','Priest-Discipline','Rogue-Outlaw',}
local provider = {region='US',realm='ShadowCouncil',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abear:BAAALgAECgQJBQAAAA==.Abrocklock:BAAALgAECgYJCQAAAA==.',
Ac='Achilês:BAAALgAECgEJAQABLgAECggJDAABAAAAAA==.',
Ad='Adaluna:BAABLgAECn8WAAICAAkJtAiTUQBGAQACAAkJtAiTUQBGAQAAAA==.Adorabull:BAACLgAFFH8JAAIDAAMJRyIbEAApAQADAAMJRyIbEAApAQAuAAQKfyUAAwMACQnVIZkGAJ4CAAMACQnVIZkGAJ4CAAQAAQnQBhGvACwAAAAA.Adrain:BAAALgAECgQJCwAAAA==.Adwae:BAAALgAECgIJAgAAAA==.',
Ae='Aelyn:BAAALgAECgcJDwAAAA==.Aerendyl:BAAALgAECgEJAQAAAA==.Aevelee:BAAALgAECggJDwAAAA==.Aevick:BAAALgAECgQJBQAAAA==.',
Al='Alastair:BAAALgADCgEJAQAAAA==.Aleeta:BAAALgAECgQJBgAAAA==.Allucard:BAAALgAECgkJAgAAAA==.',
Am='Amapanda:BAAALgAECgkJCQAAAA==.Amaria:BAAALgAECgkJBgAAAA==.Amoracchius:BAAALgADCgMJAwAAAA==.',
An='Angelstörm:BAACLgAFFH8IAAIFAAIJPwynKwBkAAAFAAIJPwynKwBkAAAuAAQKf0AAAgUACQloGZ0SAEYCAAUACQloGZ0SAEYCAAAA.Anjali:BAAALgAECgEJAQAAAA==.Anorili:BAAALgADCgYJBgAAAA==.Antarias:BAABLgAECn8eAAQGAAkJQhpuEQBIAQAGAAUJDSNuEQBIAQAHAAcJqhLcnwD/AAAIAAMJjhgDJwB5AAAAAA==.Antarion:BAAALgAECgQJBAAAAA==.',
Ap='Applevendor:BAAALgADCgUJBQAAAA==.',
Ar='Arahil:BAAALgAECgQJBwAAAA==.Arcanio:BAAALgADCgQJBAAAAA==.Arcaux:BAAALgADCggJDgAAAA==.Arckenon:BAACLgAFFH8FAAIJAAMJQh1qVQD/AAAJAAMJQh1qVQD/AAAuAAQKf0EAAgkACQlwJEoIACYDAAkACQlwJEoIACYDAAAA.',
As='Ashdorei:BAAALgADCgMJAwAAAA==.Ashog:BAABLgAECn8WAAIKAAYJ4RYKPwCtAQAKAAYJ4RYKPwCtAQAAAA==.Astranos:BAAALgAECgEJAQABLgAECgkJQgACALQPAA==.',
At='Athanyr:BAABLgAECn8sAAICAAgJXyUNBgBUAwACAAgJXyUNBgBUAwAAAA==.Atillis:BAAALgADCgYJDAAAAA==.',
Au='Augmentation:BAAALgAECgEJAQAAAA==.Austenpally:BAABLgAECn8hAAMJAAkJ3Rj6bgCOAQAJAAcJ3hb6bgCOAQALAAcJkREPNwBwAQAAAA==.',
Av='Aveycado:BAAALgADCgYJAQAAAA==.Aviane:BAAALgAECgYJBgAAAA==.',
Ax='Axeflack:BAAALgAECgEJAQAAAA==.Axegor:BAAALgADCgMJAwAAAA==.',
Az='Azrall:BAAALgAECgIJAgAAAA==.',
Ba='Bacuda:BAAALgAECgYJDwAAAA==.Balkris:BAAALgAECgEJAgABLgAECggJHgAMAI8PAA==.Baratheon:BAABLgAECn8VAAMNAAkJCg9eFwCdAQANAAkJNg5eFwCdAQAEAAcJXgbYXQA4AQAAAA==.Batya:BAAALgAECgIJAgAAAA==.',
Be='Beartooth:BAAALgADCgUJBQAAAA==.Bearynice:BAAALgADCgUJBQAAAA==.Beggles:BAAALgADCgEJAQAAAA==.Bereit:BAAALgADCgcJBgAAAA==.',
Bi='Biancadelrio:BAABLgAECn8kAAIOAAgJVRB5IABwAQAOAAgJVRB5IABwAQAAAA==.Bigboned:BAAALgADCgEJAQABLgAECgkJHgAPAM0WAA==.Bigmode:BAAALgADCgYJBgAAAA==.',
Bj='Bjorrglbrgl:BAABLgAFFH8HAAIQAAMJexnLDADiAAAQAAMJexnLDADiAAAAAA==.',
Bl='Blackmask:BAAALgADCgUJCAAAAA==.Blackzune:BAAALgAECgEJAQAAAA==.Bladekrim:BAAALgAECgEJAgAAAA==.Blindashunae:BAACLgAFFH8cAAIRAAgJuQ6OGQDYAQARAAgJuQ6OGQDYAQAuAAQKfxYAAhEACQlQHikVANgCABEACQlQHikVANgCAAAA.Blindkungfu:BAAALgAECgQJBAAAAA==.Bloodrun:BAAALgADCgkJCgAAAA==.Blook:BAABLgAECn8UAAMSAAgJThVwIACOAQASAAgJThVwIACOAQATAAEJkgg2HwA3AAAAAA==.Bluehazey:BAAALgAECgkJEQAAAA==.Blueleader:BAAALgAECgQJBAAAAA==.Bläz:BAAALgAECgEJAQAAAA==.',
Bo='Boomhammer:BAAALgAFFAIJBAAAAA==.Bootsy:BAAALgAECgcJBAAAAA==.Bopit:BAABLgAECn8VAAMJAAkJ+g6nnwBAAQAJAAYJeA6nnwBAAQALAAkJ9AzJUAA2AQAAAA==.Botia:BAABLgAECn8UAAIUAAYJiwSRXgCYAAAUAAYJiwSRXgCYAAAAAA==.',
Br='Bruhh:BAAALgAECgYJBwAAAA==.Brunnera:BAAALgAECgIJAwAAAA==.Bruuenor:BAAALgAECgYJBwAAAA==.Bruul:BAABLgAECn8gAAQJAAcJKxa+jABVAQAJAAcJKxa+jABVAQALAAQJ3Q1nWwDFAAAPAAEJ1RAJUAAuAAAAAA==.Brynjolf:BAAALgAECgUJCQAAAA==.',
Ca='Caenji:BAABLgAECn8XAAIVAAkJOAv7ZgBwAQAVAAkJOAv7ZgBwAQAAAA==.Carcharoth:BAABLgAECn8nAAMIAAkJlBiiCQCoAQAIAAcJNRqiCQCoAQAHAAYJqBBWrADqAAAAAA==.Carmelina:BAABLgAECn8oAAIOAAgJJBxuDgA7AgAOAAgJJBxuDgA7AgAAAA==.Catrixona:BAAALgAECgUJCAAAAA==.Caylan:BAAALgADCgQJBAAAAA==.',
Ch='Chadgar:BAAALgADCgIJAgAAAA==.Chaoscaster:BAAALgADCgkJCQABLgAECgYJBgABAAAAAA==.Charroth:BAAALgAECgYJCAAAAA==.Chey:BAABLgAECn86AAISAAkJ3ySxAgApAwASAAkJ3ySxAgApAwAAAA==.Chilai:BAABLgAECn8lAAIWAAkJABj8CwAdAgAWAAkJABj8CwAdAgAAAA==.Chipsahoy:BAABLgAECn8iAAMXAAkJ2x/jCQC+AgAXAAkJ2x/jCQC+AgAKAAYJdRJ3RQBsAQAAAA==.Chrîstîan:BAAALgADCgYJBgAAAA==.Chíef:BAABLgAFFH8TAAMKAAYJ6B8BCAA6AgAKAAYJ6B8BCAA6AgAXAAIJNwMwTQBYAAAAAA==.',
Ci='Cindrozetha:BAAALgADCgEJAQAAAA==.Ciphérdivine:BAAALgADCgUJBAAAAA==.Citte:BAAALgAFFAEJAgAAAA==.',
Cl='Close:BAAALgADCgUJBQABLgAFFAMJCQAKANEiAA==.',
Co='Conciete:BAABLgAECn8VAAMYAAgJWhXmGgAHAgAYAAgJWhXmGgAHAgAZAAEJBAHidwARAAAAAA==.Conorix:BAAALgAECgUJCAAAAA==.Constantiine:BAAALgAECgEJAQAAAA==.Corvo:BAABLgAECn8ZAAIPAAkJ7RheCgAhAgAPAAkJ7RheCgAhAgAAAA==.Counselor:BAAALgAECgUJCQAAAA==.Courallie:BAAALgAECgEJAQAAAA==.',
Cr='Crataxxis:BAABLgAECn9GAAIOAAkJ0xtICQCTAgAOAAkJ0xtICQCTAgAAAA==.Crynos:BAAALgADCgMJAwAAAA==.Crysandra:BAAALgAECgUJBQAAAA==.',
Cy='Cydon:BAABLgAECn81AAIWAAkJvR5uBQCwAgAWAAkJvR5uBQCwAgAAAA==.',
Da='Daereth:BAAALgAECgYJCQAAAA==.Daerrith:BAAALgAECgUJCQAAAA==.Dala:BAAALgAECgUJBQAAAA==.Damienfox:BAAALgAECgQJBgAAAA==.Dana:BAAALgAFFAEJAQABLgAFFAMJDwACABIUAA==.Danellia:BAAALgADCgUJBQAAAA==.Darkreaper:BAAALgAECgQJBAAAAA==.Darrwin:BAABLgAECn8mAAMJAAgJoR8DJgBqAgAJAAgJoR8DJgBqAgAPAAQJnw0nLwCoAAAAAA==.Dawicker:BAAALgADCgYJDwAAAA==.Daylight:BAAALgAECgYJCQAAAA==.',
De='Dedoria:BAAALgADCgUJBQAAAA==.Defacto:BAAALgADCgMJAwAAAA==.Delat:BAAALgAECgEJAQAAAA==.Delrac:BAABLgAECn8iAAIRAAgJWxEhWAB7AQARAAgJWxEhWAB7AQAAAA==.Demonalsa:BAAALgAECgEJAQABLgAFFAMJCgAaAFIJAA==.Denathrius:BAAALgAECgIJAwABLgAFFAQJBwARAAEZAA==.Denero:BAABLgAECn8dAAIJAAkJIx5gGwCeAgAJAAkJIx5gGwCeAgAAAA==.Departure:BAAALgAECgQJBwABLgAECgcJFwAOAEMcAA==.Derith:BAAALgADCgEJAQAAAA==.',
Df='Dfabness:BAACLgAFFH8KAAIYAAMJ5xCJJAC8AAAYAAMJ5xCJJAC8AAAuAAQKfyAAAhgACQlKEIkjAJIBABgACQlKEIkjAJIBAAAA.',
Di='Dic:BAAALgADCgIJAgABLgAECgMJAwABAAAAAA==.',
Do='Docbush:BAAALgAECgEJAQABLgAFFAQJDgAHAPkEAA==.Docbushed:BAAALgAECgQJBAABLgAFFAQJDgAHAPkEAA==.Dotbush:BAACLgAFFH8OAAMHAAQJ+QS0awDmAAAHAAQJ+QS0awDmAAAIAAEJhwKXKwA0AAAuAAQKfzAABAcACQlsFRpHAMQBAAcACQmVFBpHAMQBAAgAAwmrDIBGAJwAAAYAAgnOEcInAHwAAAAA.Dotspot:BAAALgADCgQJBAABLgAECgMJBwABAAAAAA==.',
Dr='Dracthayr:BAABLgAECn86AAIMAAkJZROVBgDgAQAMAAkJZROVBgDgAQAAAA==.Dragonhammer:BAACLgAFFH8LAAIJAAIJGSSCbwDNAAAJAAIJGSSCbwDNAAAuAAQKf1EAAgkACQmAJDEHADMDAAkACQmAJDEHADMDAAAA.Drakanna:BAAALgAECgIJAgAAAA==.Draxela:BAAALgAECgcJEwAAAA==.Dreaming:BAABLgAECn8wAAIbAAkJZiLBBAD7AgAbAAkJZiLBBAD7AgABLgAFFAMJCQAKANEiAA==.Drosidon:BAABLgAECn8UAAIcAAYJnAUm+QCwAAAcAAYJnAUm+QCwAAAAAA==.Drubo:BAAALgAECgIJAgAAAA==.Drx:BAAALgAECgYJBgABLgAECgkJKwAXADgVAA==.',
Ea='Earsog:BAAALgADCgEJAQAAAA==.Earthenfist:BAAALgAECgEJAQAAAA==.',
Eb='Ebebebebe:BAAALgAECgEJAQAAAA==.',
Ef='Efbomb:BAAALgADCgcJBwAAAA==.',
Ei='Eitherindel:BAAALgADCgkJCgAAAA==.',
El='Elanore:BAAALgAECgEJAQAAAA==.Ellaini:BAABLgAECn8SAAIdAAgJoAvxMQBSAQAdAAgJoAvxMQBSAQAAAA==.Ellie:BAABLgAFFH8OAAIKAAQJpBvnJgBEAQAKAAQJpBvnJgBEAQAAAA==.Elseb:BAAALgAECgQJBwAAAA==.',
Em='Emberlyn:BAAALgAECgIJBAAAAA==.Emotion:BAAALgADCgYJAQABLgAFFAMJCQAKANEiAA==.',
En='Enchantrêss:BAAALgAECggJCAABLgAECggJDAABAAAAAA==.Endo:BAAALgAECgEJAQAAAA==.',
Er='Erenara:BAAALgAECgQJCwAAAA==.',
Ev='Evic:BAABLgAECn9CAAICAAkJtA87NgC+AQACAAkJtA87NgC+AQAAAA==.',
Ew='Ewson:BAAALgADCgcJCwAAAA==.',
Ex='Excrubilis:BAAALgAFFAIJBAAAAA==.',
Fa='Faandango:BAAALgAECgUJBQAAAA==.Faeleader:BAABLgAECn8aAAICAAgJVQ3CSwBdAQACAAgJVQ3CSwBdAQAAAA==.Faevelina:BAAALgAECgUJDAABLgAECgkJCgABAAAAAA==.Faytadori:BAAALgADCgEJAQAAAA==.',
Fe='Felgrrl:BAAALgADCgkJNQAAAA==.Fester:BAAALgAECgEJAQAAAA==.Feyreh:BAAALgAECgYJBgAAAA==.',
Fi='Fieona:BAAALgADCgYJCwAAAA==.Firethorns:BAAALgAECgQJBgAAAA==.Fistandilias:BAAALgADCgkJCQAAAA==.Fitzbang:BAAALgAECgUJBwAAAA==.',
Fl='Florigrowl:BAAALgAECgMJAwAAAA==.',
Fo='Forever:BAAALgAECgMJBQABLgAFFAMJCQAKANEiAA==.Formortiis:BAAALgADCgEJAQAAAA==.Forrestior:BAABLgAECn8YAAIeAAgJoiShAQBBAwAeAAgJoiShAQBBAwAAAA==.Forsthoof:BAAALgADCgYJBgAAAA==.',
Fr='Fraga:BAAALgAECgYJDgABLgAFFAUJDQAcAJkMAA==.Frailty:BAAALgAECgYJCwAAAA==.Frique:BAABLgAECn8UAAIKAAYJPhuVNADbAQAKAAYJPhuVNADbAQAAAA==.Frostfingers:BAAALgAECgQJBgAAAA==.Frostyfang:BAABLgAECn8kAAMQAAgJ/xzJEgCKAQAQAAYJpCDJEgCKAQAUAAQJthNoVAC5AAAAAA==.Frozenyogert:BAAALgAECgQJBAAAAA==.',
Fu='Fufula:BAAALgADCgQJBAAAAA==.Funkbot:BAAALgAECgYJDAAAAA==.Furgilicious:BAAALgAECgEJAQABLgAECgYJDwABAAAAAA==.',
['Fä']='Färshadow:BAAALgAECgEJAQAAAA==.',
Ga='Galbur:BAACLgAFFH8NAAMcAAUJmQxWfAAKAQAcAAQJmQxWfAAKAQAbAAIJ+RFCPQA1AAAuAAQKfycAAxwACQndHswiAHkCABwACQnsHMwiAHkCABsACAkUFcwXAJ0BAAAA.Galdrin:BAAALgAECgkJCgAAAA==.Gaspode:BAAALgADCgcJBwAAAA==.Gassann:BAAALgAECggJDgAAAA==.',
Ge='Geers:BAABLgAECn8dAAIfAAkJ2SJ0DgAEAwAfAAkJ2SJ0DgAEAwAAAA==.Geta:BAAALgAECgQJBwABLgAECgkJIAAEAF0iAA==.Getacast:BAAALgAECgEJAQABLgAECgkJIAAEAF0iAA==.Getademon:BAAALgADCgEJAQABLgAECgkJIAAEAF0iAA==.Getaform:BAAALgAECgEJAQABLgAECgkJIAAEAF0iAA==.Getagrip:BAAALgAECgQJBgABLgAECgkJIAAEAF0iAA==.Getaheal:BAAALgAECgYJBgABLgAECgkJIAAEAF0iAA==.Getalife:BAAALgAECgIJAgABLgAECgkJIAAEAF0iAA==.Getarage:BAABLgAECn8gAAIEAAkJXSIeFACtAgAEAAkJXSIeFACtAgAAAA==.',
Gh='Ghil:BAABLgAECn8vAAMGAAkJqiMFAQAFAwAGAAkJqiMFAQAFAwAHAAQJnxXfvADfAAAAAA==.',
Gi='Gigawatt:BAABLgAECn8rAAMXAAkJOBVWKwCVAQAXAAgJxxJWKwCVAQAKAAMJ9QnpogCBAAAAAA==.Gildersleeve:BAAALgAECgQJCQAAAA==.Gilia:BAAALgADCgkJOAAAAA==.Girthfist:BAABLgAECn8WAAIgAAgJRSMIBQA5AwAgAAgJRSMIBQA5AwABLgAFFAgJGQADAN8dAA==.',
Gl='Glynixtwo:BAAALgAECgMJBQAAAA==.',
Go='Goldiwarlock:BAAALgADCgcJDgAAAA==.Goloron:BAAALgADCgkJDwAAAA==.',
Gr='Graymayn:BAABLgAECn8aAAIeAAkJ8BlkCgB3AgAeAAkJ8BlkCgB3AgAAAA==.Gremel:BAABLgAECn8kAAQWAAgJRB1cHQBdAQAWAAUJaxhcHQBdAQAQAAUJsBqeGABFAQAUAAMJGRzzQwD4AAAAAA==.Grimdor:BAAALgAECgYJDAAAAA==.Grimflaps:BAAALgAECgMJBQAAAA==.Grimmist:BAABLgAECn8hAAIZAAcJihiwMQCrAQAZAAcJihiwMQCrAQAAAA==.',
Gu='Guloot:BAABLgAECn8bAAMKAAgJBAZ8hADQAAAKAAgJBAZ8hADQAAAXAAUJtQbuggBlAAAAAA==.Gunboyten:BAAALgAECgIJAgAAAA==.Gunderthirth:BAACLgAFFH8ZAAIDAAgJ3x08AQDnAQADAAgJ3x08AQDnAQAuAAQKfy0AAwMACQmnJKIBAGsDAAMACQmnJKIBAGsDAAQABQmMIlkuAJYBAAAA.Gurkin:BAAALgADCgEJAQAAAA==.',
Gw='Gwaeniiha:BAABLgAECn8wAAIJAAgJQRM1YQCsAQAJAAgJQRM1YQCsAQAAAA==.Gward:BAAALgAECgUJBgAAAA==.Gwizz:BAABLgAECn8sAAIfAAkJnBsrLwBaAgAfAAkJnBsrLwBaAgAAAA==.',
Ha='Halibard:BAABLgAFFH8NAAIFAAUJSwgOFgAJAQAFAAUJSwgOFgAJAQAAAA==.Halinka:BAAALgADCgYJBgAAAA==.Handsoap:BAABLgAECn8eAAIOAAkJdA7WHgB/AQAOAAkJdA7WHgB/AQAAAA==.Haquar:BAAALgAECgQJBgAAAA==.Hardhitter:BAABLgAECn8lAAQNAAkJpxWhEgDLAQANAAgJbRWhEgDLAQADAAcJbAqIIAAoAQAEAAMJiA+FfQB6AAAAAA==.',
He='Hehe:BAAALgADCgQJBAAAAA==.Helldog:BAAALgAECgMJAwABLgAECgkJJQAhALYeAA==.Hellumph:BAABLgAECn8lAAIhAAkJth6xAgDJAgAhAAkJth6xAgDJAgAAAA==.Hellwraith:BAAALgADCgcJBwABLgAECgkJJQAhALYeAA==.Hermesconrad:BAAALgAECgkJEwAAAA==.Hevensrath:BAABLgAECn85AAIJAAkJdx9WFgC7AgAJAAkJdx9WFgC7AgAAAA==.',
Ho='Hokuden:BAABLgAECn86AAIiAAkJGhlJCAAIAgAiAAkJGhlJCAAIAgAAAA==.Honina:BAAALgADCgIJAgAAAA==.Hornswaggles:BAAALgAECgQJBAAAAA==.Horsebananas:BAABLgAECn83AAMeAAkJ0xzwCgBwAgAeAAkJchrwCgBwAgAVAAcJ+xkYRACfAQAAAA==.',
Ht='Htari:BAAALgAFFAIJAgAAAA==.',
Hu='Huddington:BAABLgAECn8jAAIjAAkJ1RfcAgAOAgAjAAkJ1RfcAgAOAgAAAA==.Hussh:BAAALgAECgYJDAABLgAECgkJHgAPAM0WAA==.',
Hy='Hydraness:BAAALgAECgEJAQABLgAECgQJBAABAAAAAA==.',
Ia='Iamcammy:BAAALgAECgYJEAAAAA==.',
Ic='Icedragon:BAAALgAECgEJAQAAAA==.',
Ig='Igknight:BAAALgAECgMJAwABLgAECgkJLAAgALEPAA==.',
Il='Illexi:BAAALgADCgYJBgAAAA==.',
Im='Imariz:BAAALgAECgcJBwAAAA==.Imdarkness:BAAALgAECggJDAAAAA==.Impquisitor:BAAALgAECgYJBwAAAA==.',
In='Indecent:BAABLgAECn8zAAQHAAkJOh1iFQCjAgAHAAkJOh1iFQCjAgAIAAYJHBd3FACnAQAGAAMJ3hQLGAC7AAAAAA==.Indeed:BAAALgAECgUJBgAAAA==.Inibble:BAAALgADCgcJBgAAAA==.',
Ir='Irozi:BAAALgADCgUJBQAAAA==.',
Is='Ishy:BAAALgAECgUJCAAAAA==.',
Ix='Ixelle:BAAALgADCgUJDQABLgAECgYJEQABAAAAAA==.',
Iz='Izomar:BAABLgAECn8gAAIfAAgJahn5SwD0AQAfAAgJahn5SwD0AQAAAA==.',
Ja='Jackieechan:BAAALgAECgcJBwABLgAFFAUJDwALAL8kAA==.Jackiemays:BAACLgAFFH8PAAMLAAUJvyTBEACqAQALAAQJQCbBEACqAQAJAAIJsQE8xQA1AAAuAAQKfzEAAwsACAkUJPUNALICAAsACAkUJPUNALICAAkACAlgGnY9AC8CAAAA.Jaded:BAAALgAECgUJBQAAAA==.Jaleigha:BAAALgADCgYJBwAAAA==.Jamesin:BAAALgAECgYJCAAAAA==.',
Je='Jedaii:BAAALgAECgYJBgAAAA==.Jeff:BAAALgAECgEJAwAAAA==.Jeses:BAABLgAECn8vAAIJAAkJQhacQQD/AQAJAAkJQhacQQD/AQAAAA==.',
Jo='Jollah:BAAALgAECgUJBgAAAA==.',
Ju='Jutic:BAACLgAFFH8JAAIKAAMJ/hhpQADdAAAKAAMJ/hhpQADdAAAuAAQKfzoAAgoACQnOIv4HAC0DAAoACQnOIv4HAC0DAAAA.',
Jy='Jyssa:BAAALgADCgEJAQAAAA==.',
['Jö']='Jörmun:BAAALgAFFAIJBAAAAA==.',
Ka='Kageken:BAAALgADCgUJBQABLgAECgQJBwABAAAAAA==.Kaia:BAABLgAECn8lAAISAAkJgA88GADVAQASAAkJgA88GADVAQAAAA==.Kaldrich:BAAALgAECgEJAgAAAA==.Kamoto:BAAALgAECgQJBAABLgAECgkJKwAXADgVAA==.Kanetsu:BAAALgADCgIJAgAAAA==.Kardas:BAABLgAECn8YAAMVAAkJuQcoagBpAQAVAAkJuQcoagBpAQAkAAMJ1AGLfABSAAAAAA==.Kardio:BAACLgAFFH8FAAIYAAQJ6gxGJwCvAAAYAAQJ6gxGJwCvAAAuAAQKfxoAAxgACAn+EK0rAIEBABgACAn+EK0rAIEBABkAAQkBClBnADUAAAAA.Kayj:BAAALgADCgYJBwAAAA==.Kayrina:BAAALgADCgkJCgAAAA==.Kazeer:BAABLgAECn8bAAIJAAkJLQgdmABBAQAJAAkJLQgdmABBAQAAAA==.',
Kb='Kbilly:BAABLgAECn9BAAIKAAkJVyL2BQBPAwAKAAkJVyL2BQBPAwAAAA==.',
Ke='Kegger:BAAALgAECgEJAQAAAA==.Keirani:BAAALgAECgEJAQAAAA==.Keylerin:BAACLgAFFH8eAAISAAYJlSN9DAC9AQASAAYJlSN9DAC9AQAuAAQKfyEAAhIACQmAGkgTAH4CABIACQmAGkgTAH4CAAAA.',
Ki='Kibbik:BAACLgAFFH8NAAIdAAUJcAheHwDxAAAdAAUJcAheHwDxAAAuAAQKfy0AAh0ACQkyFxsaAPMBAB0ACQkyFxsaAPMBAAAA.Kija:BAAALgAECgYJBgAAAA==.Kitsunami:BAAALgAECgcJBgAAAA==.',
Kl='Klepal:BAAALgADCgkJCgAAAA==.Klutchshield:BAAALgAECgEJAQAAAA==.',
Kn='Kneecap:BAAALgAECgUJCQAAAA==.Knottes:BAAALgAECgIJBQAAAA==.',
Ko='Kobe:BAAALgAECgYJEwAAAA==.Koharu:BAAALgADCggJHAAAAA==.Kookykg:BAAALgAECgEJAQAAAA==.',
Kr='Krampus:BAABLgAECn85AAIaAAkJExScCgAKAgAaAAkJExScCgAKAgAAAA==.Kranok:BAAALgAECgYJDgAAAA==.Krim:BAAALgADCgUJBgAAAA==.Krimdevourer:BAAALgADCgYJBgAAAA==.Krimhuntress:BAAALgAECgEJAgAAAA==.',
Ku='Kunac:BAABLgAECn8VAAIEAAgJTBY0IQDmAQAEAAgJTBY0IQDmAQAAAA==.',
Ky='Kynessa:BAAALgAECgYJEQAAAA==.Kyrun:BAABLgAECn8rAAIaAAkJjgy6EQCUAQAaAAkJjgy6EQCUAQAAAA==.Kyuutips:BAAALgAECgEJAQAAAA==.',
['Kã']='Kãne:BAACLgAFFH8JAAIlAAIJ+AxVUQB+AAAlAAIJ+AxVUQB+AAAuAAQKfyQAAyUACQmFEV4rAI8BACUACQmFEV4rAI8BAAwAAgm9Bpo4AFQAAAAA.',
La='Lamoran:BAAALgADCgkJDwAAAA==.Lannes:BAAALgAECgEJAgAAAA==.Lapz:BAAALgAECgkJEQAAAA==.Lavetra:BAAALgAECgMJBAAAAA==.Lazerdinger:BAAALgAECgEJAQAAAA==.',
Le='Legendary:BAACLgAFFH8IAAIPAAIJ0h0BEAB/AAAPAAIJ0h0BEAB/AAAuAAQKfxQAAg8ACQlbIMQDANcCAA8ACQlbIMQDANcCAAAA.Lethran:BAAALgAECgYJCQAAAA==.',
Lh='Lhani:BAABLgAECn8oAAIFAAkJORLoHQDRAQAFAAkJORLoHQDRAQAAAA==.',
Li='Liadrin:BAABLgAECn8eAAIPAAkJzRZ0DwDNAQAPAAkJzRZ0DwDNAQAAAA==.Lie:BAABLgAECn8eAAIMAAgJjw8rCgB7AQAMAAgJjw8rCgB7AQAAAA==.Liliana:BAAALgADCgkJNwAAAA==.Lirrasha:BAAALgADCgYJDwAAAA==.',
Ll='Llyrael:BAABLgAECn8eAAMFAAkJ/gomKgByAQAFAAkJ/gomKgByAQAdAAIJxAPEkwAjAAAAAA==.',
Lo='Lolineverdie:BAABLgAECn8aAAMCAAkJ4grgWQAoAQACAAkJ4grgWQAoAQAUAAYJnQKBawBvAAAAAA==.',
Lu='Luna:BAABLgAECn8iAAMFAAgJEQrzLQCNAQAFAAgJEQrzLQCNAQAdAAgJ1QeIOQArAQAAAA==.',
Ly='Lyrev:BAAALgAECgYJEwAAAA==.',
['Ló']='Lórien:BAAALgADCgIJAgAAAA==.',
Ma='Macaoidh:BAAALgAECgYJBgAAAA==.Maddeleine:BAABLgAECn8iAAQFAAgJlhVDGAAHAgAFAAgJlhVDGAAHAgAdAAMJzRCqWgCnAAAmAAQJtApvVQCnAAAAAA==.Magicdemon:BAABLgAECn83AAMOAAkJ2iURCQCXAgAOAAkJpyURCQCXAgARAAgJnSAVHQBjAgAAAA==.Magichunter:BAAALgAECgEJAQABLgAECgkJNwAOANolAA==.Makall:BAAALgADCgEJAQAAAA==.Makanoa:BAAALgAECgMJBAAAAA==.Malaah:BAABLgAECn9BAAIXAAkJvhUnHgDuAQAXAAkJvhUnHgDuAQAAAA==.Malafar:BAAALgAFFAIJAwAAAA==.Malatrixx:BAAALgAECggJCQAAAA==.Maldiriel:BAAALgAECggJCAAAAA==.Mallikus:BAAALgADCgkJCgAAAA==.Manofsecks:BAAALgAECgQJDAAAAA==.Mansuno:BAAALgAECgYJBgAAAA==.Mapachote:BAABLgAECn8vAAIkAAgJ6B2rBABiAgAkAAgJ6B2rBABiAgAAAA==.Marodin:BAAALgADCgkJOAAAAA==.Marthaiden:BAAALgAECgkJDgAAAA==.Maryjaina:BAAALgADCgYJBgAAAA==.Mavastus:BAAALgADCgcJBwAAAA==.Mazozul:BAABLgAECn82AAQmAAkJ1RbYFwASAgAmAAgJTBXYFwASAgAFAAUJ/BR2PwDsAAAdAAUJOA/5SwDcAAAAAA==.',
Me='Meatbaal:BAAALgADCgYJCAAAAA==.Melinaria:BAABLgAECn8oAAMdAAkJMBXwGgDsAQAdAAkJMBXwGgDsAQAmAAEJ6gFMhgAhAAAAAA==.Melisondraa:BAAALgADCgkJCQAAAA==.Meow:BAAALgADCgQJBAAAAA==.Merkala:BAAALgADCgYJCQAAAA==.Metalbot:BAAALgADCgkJCQAAAA==.',
Mi='Miarose:BAAALgAECgUJBgAAAA==.Miggydogg:BAAALgAECgUJCwAAAA==.Mileta:BAABLgAECn8bAAIUAAkJSRdDEgBCAgAUAAkJSRdDEgBCAgAAAA==.Mimic:BAAALgAECgIJAgAAAA==.Minthammer:BAAALgAECgIJBAABLgAFFAIJBAABAAAAAA==.Mirthias:BAAALgAECgMJAwAAAA==.Mistlock:BAAALgAECgQJBAAAAA==.Mistylady:BAAALgAECgIJAgAAAA==.',
Mj='Mjöllnir:BAABLgAECn8UAAIXAAcJpgnCQwA6AQAXAAcJpgnCQwA6AQAAAA==.',
Mo='Monki:BAAALgAECgYJEAAAAA==.Moozohar:BAAALgADCgEJAQAAAA==.Morgorra:BAAALgAECgMJBwAAAA==.Mormekil:BAAALgAECgIJAgAAAA==.Morvila:BAAALgAECgMJAwAAAA==.Mote:BAABLgAECn8nAAMdAAkJpxCpHQDXAQAdAAkJpxCpHQDXAQAmAAcJUxd4HwDPAQAAAA==.',
Mu='Muertes:BAAALgAECgEJAQAAAA==.Multidollar:BAAALgADCgUJBQABLgAFFAUJDgAVANsSAA==.Muminah:BAAALgAECgMJBgAAAA==.',
['Mô']='Môlly:BAACLgAFFH8NAAIFAAUJQR7cCQCmAQAFAAUJQR7cCQCmAQAuAAQKfysAAgUACQkGIZUFAPYCAAUACQkGIZUFAPYCAAAA.',
Na='Narnluz:BAABLgAECn8dAAIFAAgJfBcwGQD+AQAFAAgJfBcwGQD+AQAAAA==.Nastiepastie:BAAALgADCgYJBgAAAA==.Nazor:BAABLgAECn8nAAIRAAgJ1xkVPwDJAQARAAgJ1xkVPwDJAQAAAA==.',
Ne='Necronic:BAAALgADCgYJCwAAAA==.Necroreign:BAABLgAECn9IAAIOAAkJZB7tBgDEAgAOAAkJZB7tBgDEAgAAAA==.Neith:BAAALgADCgMJAwAAAA==.Nemera:BAAALgADCgYJCAAAAA==.Nervous:BAABLgAFFH8JAAIKAAMJ0SKALgAgAQAKAAMJ0SKALgAgAQAAAA==.Nessee:BAAALgAECgYJEgAAAA==.',
Ni='Niall:BAABLgAECn8yAAIQAAkJ3CEaAwDnAgAQAAkJ3CEaAwDnAgAAAA==.Nilithis:BAABLgAECn8rAAMHAAkJeRmPLAAlAgAHAAkJCxmPLAAlAgAIAAQJGxNrIACmAAAAAA==.Niú:BAAALgADCgYJBgAAAA==.',
No='Nozmua:BAAALgADCgkJDgAAAA==.',
Ny='Nyghtchyld:BAAALgAECgcJEgAAAA==.Nyxlumina:BAAALgAECgIJAgAAAA==.',
['Né']='Néssima:BAABLgAECn8gAAMJAAkJ0RXFaQCZAQAJAAkJZw7FaQCZAQAPAAUJYhuaIwDrAAAAAA==.',
Oa='Oak:BAAALgAECgEJBQAAAA==.Oathfinder:BAAALgAECgcJEAAAAA==.',
Oc='Occurrence:BAABLgAECn8VAAMCAAgJ2gUDgQC1AAACAAcJBwQDgQC1AAAUAAEJZwIJoQAeAAAAAA==.Octalexane:BAAALgAECgUJBgAAAA==.',
Om='Omalu:BAAALgAECgEJAQABLgAECggJHgAMAI8PAA==.',
On='Onebuttonman:BAAALgADCgYJBgAAAA==.Onimusha:BAAALgAECgMJAwAAAA==.',
Or='Ortalbem:BAACLgAFFH8FAAIfAAIJeBOcmwCWAAAfAAIJeBOcmwCWAAAuAAQKfzoAAh8ACQkXI3YRAO8CAB8ACQkXI3YRAO8CAAAA.',
Ov='Ovi:BAAALgADCgIJAgAAAA==.',
Pa='Pandariee:BAABLgAECn8VAAIcAAgJYw2+eQBtAQAcAAgJYw2+eQBtAQAAAA==.Pangsh:BAABLgAFFH8IAAIgAAMJBAVqPwCjAAAgAAMJBAVqPwCjAAAAAA==.Parzval:BAAALgAECgEJAgAAAA==.Paxgor:BAAALgAECgEJAQAAAA==.',
Pe='Pendaemonia:BAABLgAECn82AAIOAAkJuRYeEgAHAgAOAAkJuRYeEgAHAgAAAA==.Penelopie:BAAALgADCgYJBgAAAA==.Percfirdy:BAAALgADCgUJBQAAAA==.',
Ph='Pherix:BAABLgAECn8cAAIdAAcJ1SCDFwALAgAdAAcJ1SCDFwALAgAAAA==.Phiirys:BAAALgAECgEJAQAAAA==.',
Pi='Picaso:BAAALgADCgEJAQAAAA==.Pight:BAAALgAECggJEAABLgAECggJHgAMAI8PAA==.',
Po='Poomacha:BAABLgAECn8pAAIVAAgJRhVQSQDBAQAVAAgJRhVQSQDBAQAAAA==.Popstar:BAAALgAECgEJAQAAAA==.',
Pu='Puffthemagic:BAAALgADCgYJCAAAAA==.Punishêr:BAAALgADCgMJAwABLgAECggJDAABAAAAAA==.',
Py='Pyree:BAABLgAECn8kAAMlAAkJgxB9KwCOAQAlAAkJ4w99KwCOAQAMAAcJaAlGGwBvAAAAAA==.Pyxrin:BAAALgAECgcJBwAAAA==.',
['Pø']='Pøë:BAAALgAECgkJEwABLgAFFAMJCAAGAEsNAA==.',
Qu='Qu:BAAALgAFFAIJAwABLgAFFAMJBwAQAHsZAQ==.',
Qv='Qveemcorkie:BAAALgAECgEJAQAAAA==.',
['Qí']='Qín:BAAALgADCgUJAwAAAA==.',
Ra='Radagust:BAAALgAECgQJBAAAAA==.Radcat:BAAALgAECgEJBAAAAA==.Raenne:BAAALgAECgMJBQAAAA==.Ragebait:BAAALgADCgIJAgAAAA==.Rainfall:BAAALgAECgEJAgAAAA==.Raistlain:BAAALgAECgYJDwAAAA==.Raitha:BAAALgADCgUJCAAAAA==.Ralli:BAABLgAECn8qAAIRAAgJohkUMwD2AQARAAgJohkUMwD2AQAAAA==.Rallsdemon:BAAALgAECgQJBAABLgAECgcJCgABAAAAAA==.Rallsdk:BAAALgAECgcJCgAAAA==.Rallsodins:BAAALgAECgYJBgABLgAECgcJCgABAAAAAA==.Randomguy:BAACLgAFFH8MAAISAAQJ9RmEFABgAQASAAQJ9RmEFABgAQAuAAQKfzgAAhIACQnYJSMCAD0DABIACQnYJSMCAD0DAAAA.Ranulf:BAAALgAECgQJBgAAAA==.Ratava:BAAALgAECgUJBQAAAA==.Ratboy:BAEALgAECgEJAQABLgAECgkJMgAmABwjAA==.Ratrot:BAABLgAECn8pAAIKAAgJKh4EEwCxAgAKAAgJKh4EEwCxAgAAAA==.Ratsdead:BAAALgAECgEJAQAAAA==.Razenath:BAAALgADCgcJDAAAAA==.',
Re='Reddemon:BAAALgADCgkJCQAAAA==.Reinhardt:BAAALgADCgYJBgAAAA==.Rekrella:BAAALgADCgUJBQAAAA==.Reldarus:BAEBLgAECn8yAAMmAAkJHCO6AgCEAwAmAAkJHCO6AgCEAwAFAAQJ+hr8RAAlAQAAAA==.Rena:BAAALgADCgcJBwAAAA==.Rendia:BAAALgADCgMJAwAAAA==.Renik:BAAALgADCgIJAQAAAA==.Revennek:BAAALgAECgUJCgAAAA==.Reverence:BAABLgAECn8eAAIJAAkJ8A13YACtAQAJAAkJ8A13YACtAQAAAA==.Revilation:BAABLgAECn8cAAIPAAkJYBOLEwCOAQAPAAkJYBOLEwCOAQAAAA==.Rezjyk:BAAALgAECgYJCAABLgAECgkJNAAJANwcAA==.Rezzyk:BAABLgAECn80AAIJAAkJ3BybGQCoAgAJAAkJ3BybGQCoAgAAAA==.',
Rh='Rhonus:BAAALgAECgEJAQAAAA==.Rhyxali:BAABLgAECn8fAAQIAAgJfgwLEQAwAQAIAAgJfgwLEQAwAQAGAAYJLAeGGwDdAAAHAAQJ5AHK+QBmAAAAAA==.',
Ri='Riis:BAAALgAECgYJDAAAAA==.Riiselock:BAABLgAECn8tAAMHAAgJIR5CNwAvAgAHAAcJyR1CNwAvAgAIAAQJFByXFwDiAAAAAA==.Riiwind:BAAALgADCgQJBAABLgAECgkJAwABAAAAAA==.Riktade:BAAALgADCgYJBgAAAA==.Rilight:BAAALgAECgMJAwABLgAECgkJAwABAAAAAA==.Riptidepod:BAABLgAECn8gAAMKAAkJ5Qj9UwBgAQAKAAkJ5Qj9UwBgAQAXAAIJ3gKXvQAcAAAAAA==.',
Ro='Robbiebrews:BAAALgADCgUJBQAAAA==.Robear:BAAALgAECgEJAQAAAA==.Robeart:BAAALgAECgEJAQAAAA==.Rowin:BAAALgADCgUJBQAAAA==.',
Ru='Ruddigore:BAAALgAECgEJAQAAAA==.',
Ry='Rynley:BAABLgAECn8WAAMSAAUJASEKJwDAAQASAAUJASEKJwDAAQAnAAIJWRE4GwBwAAAAAA==.',
Sa='Sacredscales:BAABLgAECn8hAAMFAAkJtR5kCwCaAgAFAAcJ3yRkCwCaAgAdAAcJtRSGKgCGAQAAAA==.Sagerremeseb:BAAALgAECgQJBgAAAA==.Sakii:BAABLgAECn8lAAIRAAkJJRJFOQDeAQARAAkJJRJFOQDeAQAAAA==.Salera:BAAALgADCgQJBAAAAA==.Salvion:BAAALgAECgcJAQABLgAECgkJJwARANcZAA==.Samvimes:BAABLgAECn8wAAIJAAkJow9oXAC3AQAJAAkJow9oXAC3AQAAAA==.Sangreene:BAABLgAECn8dAAIdAAgJRxqFEwBYAgAdAAgJRxqFEwBYAgAAAA==.Sargis:BAACLgAFFH8IAAIJAAMJkRjaWQD2AAAJAAMJkRjaWQD2AAAuAAQKf0sAAwkACQmnI4cIACQDAAkACQmnI4cIACQDAAsACAnHG/saACoCAAAA.Sarial:BAAALgADCgMJAwAAAA==.',
Sc='Schrödinger:BAAALgAECgYJDwABLgAECgkJGQAPAO0YAA==.Sciblasts:BAAALgADCgEJAQABLgAECgYJEAABAAAAAA==.Scott:BAACLgAFFH8oAAIRAAgJxyFVBQC2AgARAAgJxyFVBQC2AgAuAAQKf0YAAhEACQmaJnUAAO4DABEACQmaJnUAAO4DAAAA.Scratchh:BAABLgAECn8dAAIgAAgJlAstNgB0AQAgAAgJlAstNgB0AQAAAA==.',
Se='Searalsa:BAAALgAECgUJCAABLgAFFAMJCgAaAFIJAA==.Sentis:BAABLgAECn8fAAIUAAgJOge4QwD5AAAUAAgJOge4QwD5AAAAAA==.',
Sh='Shadowbrooks:BAAALgAECgIJAgAAAA==.Shadowgiver:BAAALgADCgcJDwAAAA==.Shadowsdemon:BAAALgADCgEJAQAAAA==.Shadowsworn:BAAALgAECgEJAQAAAA==.Shagol:BAAALgAECgQJBwAAAA==.Shalriss:BAABLgAECn8nAAIdAAkJCBsQEABbAgAdAAkJCBsQEABbAgAAAA==.Shamemoon:BAABLgAECn8fAAIRAAkJjhe1LgAJAgARAAkJjhe1LgAJAgAAAA==.Shamunroe:BAABLgAECn8pAAMKAAkJMAcdXwA5AQAKAAkJMAcdXwA5AQAXAAUJkxKwWgDZAAAAAA==.Shatterhoof:BAABLgAECn8hAAIQAAcJoQs6IAAAAQAQAAcJoQs6IAAAAQAAAA==.Shelle:BAAALgAECgYJCgAAAA==.Shiftys:BAAALgADCgUJCgABLgAFFAIJAgABAAAAAA==.Shingra:BAACLgAFFH8oAAIlAAYJohwlGACcAQAlAAYJohwlGACcAQAuAAQKfygAAiUACQnGHfYNAIACACUACQnGHfYNAIACAAAA.Shoof:BAAALgADCgUJBQAAAA==.',
Si='Sifû:BAAALgADCgcJDgAAAA==.Sigourney:BAAALgAECgUJBQABLgAECgkJNwAeANMcAA==.Silversho:BAAALgAECgUJBQAAAA==.Silvoid:BAAALgADCgMJAwABLgAECgUJBQABAAAAAA==.Silvren:BAABLgAECn8xAAMEAAgJKRgZIADuAQAEAAgJKRgZIADuAQANAAEJvwZoRgArAAAAAA==.Sindarion:BAAALgAECgUJBQABLgAFFAEJAgABAAAAAA==.Sinnerr:BAAALgAECgEJAQAAAA==.Sinz:BAAALgAECgEJBQAAAA==.Siph:BAAALgAECgEJAQAAAA==.',
Sk='Skillidan:BAABLgAECn8nAAICAAkJQhq3FACiAgACAAkJQhq3FACiAgAAAA==.',
Sl='Slighttrash:BAABLgAECn8pAAIeAAgJlhQBGQDYAQAeAAgJlhQBGQDYAQAAAA==.Sloppy:BAAALgADCgkJCgAAAA==.',
Sm='Smacka:BAAALgAECgEJAQAAAA==.Smallcrow:BAACLgAFFH8jAAMYAAgJbR5rAQCBAgAYAAgJbR5rAQCBAgAZAAEJQwuEWgBDAAAuAAQKfxYAAhgABwkuJsQHAP8CABgABwkuJsQHAP8CAAAA.Smores:BAAALgADCgkJCQAAAA==.Smøke:BAAALgAECgMJAwAAAA==.',
Sn='Snallygaster:BAAALgADCgYJDAABLgAECgkJIwAWAJ8bAA==.Snowsong:BAAALgAECgEJAQAAAA==.',
Sp='Spamton:BAAALgADCgEJAQAAAA==.Spectrose:BAAALgADCgEJAQAAAA==.Spirit:BAAALgAECgEJAgAAAA==.Spiro:BAAALgAFFAIJAgABLgAFFAMJCAAGAEsNAA==.Spøngè:BAAALgADCgMJAwAAAA==.',
St='Starge:BAAALgAFFAEJAgAAAA==.Starre:BAAALgAECgUJBQAAAA==.Steffey:BAABLgAECn8iAAIKAAcJIgwKYAA2AQAKAAcJIgwKYAA2AQAAAA==.Straven:BAABLgAECn8jAAIfAAgJrRQ2XwC/AQAfAAgJrRQ2XwC/AQAAAA==.Sturgeson:BAACLgAFFH8jAAIDAAYJaRyzCACgAQADAAYJaRyzCACgAQAuAAQKfx8AAgMACQlvHQcMAEsCAAMACQlvHQcMAEsCAAAA.',
Su='Sulfato:BAAALgADCgEJAQAAAA==.Sulwen:BAABLgAECn9RAAIFAAkJUhqZDACaAgAFAAkJUhqZDACaAgAAAA==.Suzakã:BAAALgAECgcJBwAAAA==.',
Sw='Sweetpotato:BAAALgADCgEJAQAAAA==.Swiftfeet:BAABLgAECn8lAAIVAAkJABTgQQDYAQAVAAkJABTgQQDYAQAAAA==.',
Sy='Syrasia:BAAALgADCgUJBQAAAA==.Syselea:BAAALgADCgEJAQAAAA==.',
['Sö']='Söranin:BAABLgAECn8dAAIZAAYJ5xhyMgCnAQAZAAYJ5xhyMgCnAQAAAA==.',
Ta='Tachichan:BAAALgAECgYJBgAAAA==.Tadum:BAAALgADCgEJAQAAAA==.Taeili:BAABLgAECn8gAAMWAAkJIhX+JwATAQAUAAgJ2BVoNgBiAQAWAAYJKxP+JwATAQAAAA==.Talisse:BAAALgADCgYJBgAAAA==.Tanequil:BAACLgAFFH8JAAICAAMJCgKEVwBnAAACAAMJCgKEVwBnAAAuAAQKfyQAAgIACQlJDNdKAHgBAAIACQlJDNdKAHgBAAAA.Taosha:BAAALgAECgcJCAAAAA==.Targaryian:BAAALgAECgMJAwAAAA==.Tav:BAAALgADCgUJBQAAAA==.Taylea:BAABLgAECn8WAAIfAAcJpA9HswAZAQAfAAcJpA9HswAZAQABLgAECgkJJgAJAKEfAA==.',
Te='Techromancer:BAAALgAECgYJCAABLgAECgcJHAAdANUgAA==.Telleria:BAAALgAECgIJAgAAAA==.Tem:BAAALgAECgMJAwAAAA==.Tenumbras:BAAALgAECgYJDAAAAA==.Termonda:BAAALgAECgEJAQAAAA==.Terraclaw:BAAALgADCgUJBwAAAA==.Terrasia:BAAALgADCgYJBgAAAA==.Terrigino:BAAALgAECgUJAwAAAA==.',
Th='Thanatias:BAABLgAECn8aAAIbAAkJmhTbFQC6AQAbAAkJmhTbFQC6AQAAAA==.Thantasia:BAABLgAECn8WAAIfAAcJogPZ0wDoAAAfAAcJogPZ0wDoAAAAAA==.Thauras:BAAALgADCgcJFwAAAA==.Theeslan:BAABLgAECn8iAAIdAAkJqQO3QgACAQAdAAkJqQO3QgACAQAAAA==.Thokdar:BAAALgAECgUJBQAAAA==.Thom:BAACLgAFFH8MAAIiAAUJihBNEAALAQAiAAUJihBNEAALAQAuAAQKfysAAyIACQksJOcAABwDACIACQksJOcAABwDABwABgmoDjmxACABAAAA.Thør:BAAALgADCgcJDgAAAA==.',
Ti='Tiernay:BAAALgADCgEJAQAAAA==.Tifà:BAAALgAECgUJCAAAAA==.Timothy:BAABLgAECn8bAAIOAAkJ7BjYEQALAgAOAAkJ7BjYEQALAgAAAA==.Timothyjohn:BAAALgAECgEJAQAAAA==.Tinkphooey:BAAALgAECgYJCwAAAA==.Tinton:BAAALgADCgEJAQAAAA==.',
To='Toishi:BAAALgAECgEJAQAAAA==.Tormmok:BAAALgAECgYJDAAAAA==.Toshiden:BAAALgADCgEJAgAAAA==.Toshindo:BAAALgAECgEJAgAAAA==.',
Tr='Traazz:BAAALgAECgkJAwAAAA==.Trashpally:BAAALgAECgEJAgAAAA==.Tremèndor:BAAALgADCgMJAwAAAA==.Trey:BAAALgAECgEJAQAAAA==.Tristra:BAAALgAECgQJBAAAAA==.',
Ts='Tsuruga:BAABLgAECn85AAIgAAkJQA4BIgCWAQAgAAkJQA4BIgCWAQAAAA==.',
Tu='Turkwise:BAABLgAECn83AAMWAAkJVx1YBgCWAgAWAAkJVx1YBgCWAgAQAAQJCBGsHgDuAAAAAA==.',
Ty='Tycondrius:BAAALgAECgEJAQAAAA==.Tyresh:BAAALgAECgEJAQAAAA==.Tyrinor:BAAALgADCgUJBQAAAA==.',
Ul='Ulogasm:BAAALgADCgkJCgAAAA==.',
Us='Usami:BAAALgAECgEJAQAAAA==.',
Ut='Utako:BAAALgADCgUJCgAAAA==.',
Uv='Uvari:BAABLgAECn8ZAAIFAAgJ1w77JwCCAQAFAAgJ1w77JwCCAQAAAA==.',
Va='Vaclar:BAAALgAFFAMJAwABLgAFFAUJDAAYAK8hAA==.Valhalaa:BAAALgADCgYJBgAAAA==.Valkryee:BAAALgAECgUJBQAAAA==.Valton:BAACLgAFFH8MAAIYAAUJryE8CwBoAQAYAAUJryE8CwBoAQAuAAQKf0QAAhgACQmEJqgEAAsDABgACQmEJqgEAAsDAAAA.Vanillanice:BAAALgAECggJEAAAAA==.Varrfife:BAAALgAECgQJBAAAAA==.Vaxaldan:BAABLgAECn85AAIbAAkJLQ4KHgBkAQAbAAkJLQ4KHgBkAQAAAA==.',
Ve='Velestre:BAAALgAECgUJBQAAAA==.Velithera:BAAALgADCgMJAwAAAA==.Vellithe:BAABLgAECn8WAAIJAAcJIQpo1QDpAAAJAAcJIQpo1QDpAAAAAA==.Venj:BAAALgAECgUJBgAAAA==.Verhmax:BAAALgADCgYJCwAAAA==.Verton:BAAALgADCgYJBgAAAA==.Vestrae:BAACLgAFFH8KAAMCAAUJIgobLAD/AAACAAUJIgobLAD/AAAUAAEJSQEsVAAmAAAuAAQKfyYAAgIACQnwHG8TAJoCAAIACQnwHG8TAJoCAAAA.Vex:BAABLgAECn8YAAIHAAkJbxreJQBFAgAHAAkJbxreJQBFAgAAAA==.',
Vi='Vianel:BAAALgADCggJCAAAAA==.Vilten:BAAALgAECgQJCwAAAA==.Virus:BAAALgAECgkJCQAAAA==.',
Vo='Vodash:BAABLgAECn8hAAIKAAcJ3RneMQDoAQAKAAcJ3RneMQDoAQABLgAECgkJQgACALQPAA==.Voidwrench:BAAALgADCgYJBgAAAA==.Vostok:BAABLgAECn8eAAIHAAgJOBzFRwDCAQAHAAgJOBzFRwDCAQAAAA==.',
Wa='Wage:BAAALgADCgQJBQAAAA==.Warmth:BAAALgADCgIJAwAAAA==.',
We='Weekend:BAAALgADCgkJDwAAAA==.Wetsock:BAAALgAECgYJBwAAAA==.',
Wi='Wikket:BAABLgAECn85AAMUAAkJPRw6DQCCAgAUAAkJPRw6DQCCAgACAAgJ3APCdQDSAAAAAA==.',
Wo='Wolvesbayne:BAAALgAECgEJAQAAAA==.',
Wy='Wyelie:BAAALgAECgYJDQAAAA==.Wynono:BAAALgADCgcJBwAAAA==.',
Xd='Xdeadlysinz:BAAALgAECgcJDwAAAA==.',
Xo='Xotha:BAABLgAECn88AAIRAAkJqB4TFQCXAgARAAkJqB4TFQCXAgAAAA==.',
Xu='Xuen:BAAALgAFFAEJAwAAAA==.',
Xy='Xythera:BAACLgAFFH8HAAIRAAQJARnKXQDPAAARAAQJARnKXQDPAAAuAAQKfx8AAxEACQmKIPYVANMCABEACQmKIPYVANMCACEAAQmwEIkzADIAAAAA.',
Ye='Yeah:BAAALgADCgYJBgABLgAFFAMJBwAJAEwMAA==.',
Yi='Yinosai:BAAALgAECgYJCAAAAA==.',
Yo='Yougot:BAAALgADCgcJCgAAAA==.',
Yu='Yuji:BAABLgAECn8hAAIIAAYJaR1yCwCFAQAIAAYJaR1yCwCFAQAAAA==.Yukì:BAAALgADCgMJAwAAAA==.Yurie:BAAALgAECgIJAgAAAA==.',
Yv='Yvonna:BAAALgADCgEJAQAAAA==.',
Za='Zaega:BAAALgADCgQJBAABLgAECgkJJgAJAKEfAA==.Zahlee:BAAALgAECgQJBAAAAA==.Zaldin:BAAALgADCgYJCgAAAA==.Zalirina:BAAALgADCgIJAgAAAA==.Zanka:BAAALgAECgIJAgAAAA==.Zaridruid:BAAALgAECgkJCgAAAA==.Zarisedra:BAACLgAFFH8pAAMLAAYJiR+KCAAnAgALAAYJiR+KCAAnAgAJAAEJXgDaOwA2AAAuAAQKfxgAAwsACQkwF8kpAOMBAAsACAkGGMkpAOMBAAkAAQktBuw9ATUAAAAA.Zarissena:BAAALgAECgYJAwAAAA==.Zarris:BAAALgADCgUJDAAAAA==.',
Ze='Zennith:BAAALgADCgMJAwAAAA==.Zernacho:BAABLgAECn8gAAQFAAkJjBoGHwDHAQAFAAYJJhwGHwDHAQAdAAcJ+hFBLgBvAQAmAAMJTRP/UgCxAAAAAA==.Zerogasm:BAABLgAECn8YAAIVAAkJAhY8LwAbAgAVAAkJAhY8LwAbAgAAAA==.Zerolicious:BAAALgAECgMJBgAAAA==.Zeromojo:BAAALgAECgMJAwAAAA==.Zerostarbear:BAAALgAECgEJAQAAAA==.Zerozaddy:BAAALgAECgUJBgAAAA==.Zevvo:BAABLgAECn8wAAIEAAkJECEaCgDBAgAEAAkJECEaCgDBAgAAAA==.',
Zi='Ziggysundust:BAAALgADCgMJAwAAAA==.',
Zo='Zoraji:BAABLgAECn86AAIgAAkJdhq1DgBMAgAgAAkJdhq1DgBMAgAAAA==.',
Zu='Zuganova:BAABLgAFFH8SAAMmAAUJDQhmIwAoAQAmAAUJ4QdmIwAoAQAFAAEJ8whwFgA8AAAAAA==.Zuggar:BAABLgAECn8fAAIEAAcJVwjxUAAFAQAEAAcJVwjxUAAFAQAAAA==.',
Zy='Zynhammer:BAABLgAECn8oAAMRAAgJgxFhXQCJAQARAAgJgxFhXQCJAQAOAAEJawb3dgAmAAAAAA==.',
['Év']='Évangeline:BAAALgADCgcJBwAAAA==.',
['Ëb']='Ëbony:BAABLgAFFH8LAAIVAAQJNRrKLABRAQAVAAQJNRrKLABRAQAAAA==.',
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
