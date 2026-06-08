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
local provider = {region='US',realm='ShadowCouncil',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abear:BAAALgAECgQJBQAAAA==.Abrocklock:BAAALgAECgYJCQAAAA==.',
Ac='Achilês:BAAALgAECgEJAQABLgAECggJDAABAAAAAA==.',
Ad='Adaluna:BAABLgAECn8WAAICAAkJtAhTTwBHAQACAAkJtAhTTwBHAQAAAA==.Adorabull:BAACLgAFFH8GAAIDAAIJfiHaGQC7AAADAAIJfiHaGQC7AAAuAAQKfyUAAwMACQnVIRUGAKQCAAMACQnVIRUGAKQCAAQAAQnQBhGvACwAAAAA.Adrain:BAAALgAECgQJCwAAAA==.Adwae:BAAALgAECgIJAgAAAA==.',
Ae='Aelyn:BAAALgAECgcJDwAAAA==.Aerendyl:BAAALgAECgEJAQAAAA==.Aevelee:BAAALgAECgcJDgAAAA==.Aevick:BAAALgAECgQJBQAAAA==.',
Al='Alastair:BAAALgADCgEJAQAAAA==.Aleeta:BAAALgAECgQJBgAAAA==.Allucard:BAAALgAECgkJAgAAAA==.',
Am='Amapanda:BAAALgAECgkJCQAAAA==.Amaria:BAAALgAECgkJBgAAAA==.Amoracchius:BAAALgADCgMJAwAAAA==.',
An='Angelstörm:BAACLgAFFH8IAAIFAAIJPwyTKABoAAAFAAIJPwyTKABoAAAuAAQKf0AAAgUACQloGZMRAEgCAAUACQloGZMRAEgCAAAA.Anorili:BAAALgADCgYJBgAAAA==.Antarias:BAABLgAECn8eAAQGAAkJQho5EABLAQAGAAUJDSM5EABLAQAHAAcJqhLPmgADAQAIAAMJjhiZJQB5AAAAAA==.Antarion:BAAALgAECgQJBAAAAA==.',
Ap='Applevendor:BAAALgADCgUJBQAAAA==.',
Ar='Arahil:BAAALgAECgQJBwAAAA==.Arcanio:BAAALgADCgQJBAAAAA==.Arcaux:BAAALgADCggJDgAAAA==.Arckenon:BAABLgAECn9BAAIJAAkJcCRrBwAqAwAJAAkJcCRrBwAqAwAAAA==.',
As='Ashdorei:BAAALgADCgMJAwAAAA==.Ashog:BAABLgAECn8WAAIKAAYJ4RZvPACvAQAKAAYJ4RZvPACvAQAAAA==.Astranos:BAAALgAECgEJAQABLgAECgkJPAACAHIPAA==.',
At='Athanyr:BAABLgAECn8sAAICAAgJXyWuBQBWAwACAAgJXyWuBQBWAwAAAA==.Atillis:BAAALgADCgYJDAAAAA==.',
Au='Augmentation:BAAALgAECgEJAQAAAA==.Austenpally:BAABLgAECn8hAAMJAAkJ3RjVaQCQAQAJAAcJ3hbVaQCQAQALAAcJkRF5NQBwAQAAAA==.',
Av='Aveycado:BAAALgADCgYJAQAAAA==.',
Ax='Axeflack:BAAALgAECgEJAQAAAA==.Axegor:BAAALgADCgMJAwAAAA==.',
Az='Azrall:BAAALgAECgIJAgAAAA==.',
Ba='Bacuda:BAAALgAECgYJDwAAAA==.Balkris:BAAALgAECgEJAgABLgAECggJHQAMAI8PAA==.Baratheon:BAABLgAECn8VAAMNAAkJCg9FFgCgAQANAAkJNg5FFgCgAQAEAAcJXgbYXQA4AQAAAA==.Batya:BAAALgAECgIJAgAAAA==.',
Be='Beartooth:BAAALgADCgUJBQAAAA==.Bearynice:BAAALgADCgUJBQAAAA==.Beggles:BAAALgADCgEJAQAAAA==.Bereit:BAAALgADCgcJBgAAAA==.',
Bi='Biancadelrio:BAABLgAECn8eAAIOAAcJiRBrJQA7AQAOAAcJiRBrJQA7AQAAAA==.Bigboned:BAAALgADCgEJAQABLgAECgkJHgAPAM0WAA==.Bigmode:BAAALgADCgYJBgAAAA==.',
Bj='Bjorrglbrgl:BAABLgAFFH8GAAIQAAMJexlTCwDqAAAQAAMJexlTCwDqAAAAAA==.',
Bl='Blackmask:BAAALgADCgUJCAAAAA==.Bladekrim:BAAALgAECgEJAgAAAA==.Blindashunae:BAACLgAFFH8cAAIRAAgJuQ41FQDlAQARAAgJuQ41FQDlAQAuAAQKfxYAAhEACQlQHikVANgCABEACQlQHikVANgCAAAA.Blindkungfu:BAAALgAECgQJBAAAAA==.Bloodrun:BAAALgADCgkJCgAAAA==.Blook:BAABLgAECn8UAAMSAAgJThUZHwCOAQASAAgJThUZHwCOAQATAAEJkgg2HwA3AAAAAA==.Bluehazey:BAAALgAECgkJEQAAAA==.Blueleader:BAAALgAECgQJBAAAAA==.Bläz:BAAALgAECgEJAQAAAA==.',
Bo='Boomhammer:BAAALgAFFAIJBAAAAA==.Bootsy:BAAALgAECgcJBAAAAA==.Bopit:BAABLgAECn8VAAMJAAkJ+g6nnwBAAQAJAAYJeA6nnwBAAQALAAkJ9AzJUAA2AQAAAA==.Botia:BAABLgAECn8UAAIUAAYJiwQOWwCZAAAUAAYJiwQOWwCZAAAAAA==.',
Br='Bruhh:BAAALgAECgYJBwAAAA==.Brunnera:BAAALgAECgIJAwAAAA==.Bruuenor:BAAALgAECgYJBwAAAA==.Bruul:BAABLgAECn8gAAQJAAcJKxZxhgBXAQAJAAcJKxZxhgBXAQALAAQJ3Q0EWQDGAAAPAAEJ1RDwTAAuAAAAAA==.Brynjolf:BAAALgAECgUJCQAAAA==.',
Ca='Caenji:BAABLgAECn8XAAIVAAkJOAtAYQB3AQAVAAkJOAtAYQB3AQAAAA==.Carcharoth:BAABLgAECn8nAAMIAAkJlBj6CACqAQAIAAcJNRr6CACqAQAHAAYJqBAOqADsAAAAAA==.Carmelina:BAABLgAECn8lAAIOAAgJAhsEDgA0AgAOAAgJAhsEDgA0AgAAAA==.Catrixona:BAAALgAECgUJCAAAAA==.Caylan:BAAALgADCgQJBAAAAA==.',
Ch='Chadgar:BAAALgADCgIJAgAAAA==.Chaoscaster:BAAALgADCgkJCQABLgAECgYJBgABAAAAAA==.Charroth:BAAALgAECgYJCAAAAA==.Chey:BAABLgAECn83AAISAAkJ3yRxAgAsAwASAAkJ3yRxAgAsAwAAAA==.Chilai:BAABLgAECn8lAAIWAAkJABg1CwAdAgAWAAkJABg1CwAdAgAAAA==.Chipsahoy:BAABLgAECn8iAAMXAAkJ2x81CQDAAgAXAAkJ2x81CQDAAgAKAAYJdRJ3RQBsAQAAAA==.Chrîstîan:BAAALgADCgYJBgAAAA==.Chíef:BAABLgAFFH8NAAMKAAYJrRdjDgDXAQAKAAYJrRdjDgDXAQAXAAIJNwP4RgBgAAAAAA==.',
Ci='Cindrozetha:BAAALgADCgEJAQAAAA==.Ciphérdivine:BAAALgADCgUJBAAAAA==.Citte:BAAALgAFFAEJAgAAAA==.',
Cl='Close:BAAALgADCgUJBQABLgAFFAMJCQAKANEiAA==.',
Co='Conciete:BAABLgAECn8VAAMYAAgJWhXmGgAHAgAYAAgJWhXmGgAHAgAZAAEJBAHidwARAAAAAA==.Conorix:BAAALgAECgUJCAAAAA==.Constantiine:BAAALgAECgEJAQAAAA==.Corvo:BAABLgAECn8YAAIPAAgJ5hjoDQDYAQAPAAgJ5hjoDQDYAQAAAA==.Counselor:BAAALgAECgUJCQAAAA==.Courallie:BAAALgAECgEJAQAAAA==.',
Cr='Crataxxis:BAABLgAECn89AAIOAAkJ8BgtCwBkAgAOAAkJ8BgtCwBkAgAAAA==.Crynos:BAAALgADCgMJAwAAAA==.Crysandra:BAAALgAECgUJBQAAAA==.',
Cy='Cydon:BAABLgAECn81AAIWAAkJvR4WBQCxAgAWAAkJvR4WBQCxAgAAAA==.',
Da='Daereth:BAAALgAECgYJCQAAAA==.Daerrith:BAAALgAECgUJCQAAAA==.Dala:BAAALgAECgUJBQAAAA==.Damienfox:BAAALgAECgQJBgAAAA==.Dana:BAAALgAECgYJDQABLgAFFAMJDwACABIUAA==.Danellia:BAAALgADCgUJBQAAAA==.Darkreaper:BAAALgAECgQJBAAAAA==.Darrwin:BAABLgAECn8mAAMJAAgJoR+YIwBtAgAJAAgJoR+YIwBtAgAPAAQJnw1vLQCoAAAAAA==.Dawicker:BAAALgADCgYJDwAAAA==.Daylight:BAAALgAECgYJCQAAAA==.',
De='Dedoria:BAAALgADCgUJBQAAAA==.Defacto:BAAALgADCgMJAwAAAA==.Delat:BAAALgAECgEJAQAAAA==.Delrac:BAABLgAECn8iAAIRAAgJWxE/VQB7AQARAAgJWxE/VQB7AQAAAA==.Demonalsa:BAAALgAECgEJAQABLgAFFAMJCQAaANMIAA==.Denathrius:BAAALgAECgIJAwABLgAFFAQJBwARAAEZAA==.Denero:BAABLgAECn8dAAIJAAkJIx5cGQChAgAJAAkJIx5cGQChAgAAAA==.Departure:BAAALgAECgQJBwABLgAECgcJFwAOAEMcAA==.Derith:BAAALgADCgEJAQAAAA==.',
Df='Dfabness:BAACLgAFFH8HAAIYAAIJGg5sLgCAAAAYAAIJGg5sLgCAAAAuAAQKfyAAAhgACQlKEIwhAJcBABgACQlKEIwhAJcBAAAA.',
Di='Dic:BAAALgADCgIJAgABLgAECgMJAwABAAAAAA==.',
Do='Docbushed:BAAALgAECgQJBAABLgAFFAQJDQAHAN0EAA==.Dotbush:BAACLgAFFH8NAAMHAAQJ3QSUZQDoAAAHAAQJ3QSUZQDoAAAIAAEJhwIyKQA1AAAuAAQKfy8ABAcACAnXFktAAA0CAAcACAniFUtAAA0CAAgAAwmrDIBGAJwAAAYAAgnOEYklAHwAAAAA.Dotspot:BAAALgADCgQJBAABLgAECgMJBwABAAAAAA==.',
Dr='Dracthayr:BAABLgAECn86AAIMAAkJZRM2BgDjAQAMAAkJZRM2BgDjAQAAAA==.Dragonhammer:BAACLgAFFH8LAAIJAAIJGSSKZgDQAAAJAAIJGSSKZgDQAAAuAAQKf1EAAgkACQmAJGoGADYDAAkACQmAJGoGADYDAAAA.Drakanna:BAAALgAECgIJAgAAAA==.Draxela:BAAALgAECgcJDwAAAA==.Dreaming:BAABLgAECn8wAAIbAAkJZiLBBAD7AgAbAAkJZiLBBAD7AgABLgAFFAMJCQAKANEiAA==.Drosidon:BAABLgAECn8UAAIcAAYJnAX27wCzAAAcAAYJnAX27wCzAAAAAA==.Drubo:BAAALgAECgEJAQAAAA==.',
Ea='Earsog:BAAALgADCgEJAQAAAA==.Earthenfist:BAAALgAECgEJAQAAAA==.',
Eb='Ebebebebe:BAAALgAECgEJAQAAAA==.',
Ef='Efbomb:BAAALgADCgcJBwAAAA==.',
Ei='Eitherindel:BAAALgADCgkJCgAAAA==.',
El='Elanore:BAAALgAECgEJAQAAAA==.Ellaini:BAABLgAECn8SAAIdAAgJoAsZLwBcAQAdAAgJoAsZLwBcAQAAAA==.Ellie:BAABLgAFFH8KAAIKAAQJpBuiIgBIAQAKAAQJpBuiIgBIAQAAAA==.Elseb:BAAALgAECgQJBwAAAA==.',
Em='Emberlyn:BAAALgAECgIJAwAAAA==.Emotion:BAAALgADCgYJAQABLgAFFAMJCQAKANEiAA==.',
En='Enchantrêss:BAAALgADCgQJBAABLgAECggJDAABAAAAAA==.',
Er='Erenara:BAAALgAECgQJCwAAAA==.',
Ev='Evic:BAABLgAECn88AAICAAkJcg/RNQC5AQACAAkJcg/RNQC5AQAAAA==.',
Ew='Ewson:BAAALgADCgcJCwAAAA==.',
Ex='Excrubilis:BAAALgAFFAIJBAAAAA==.',
Fa='Faandango:BAAALgAECgUJBQAAAA==.Faeleader:BAABLgAECn8aAAICAAgJVQ2rSQBfAQACAAgJVQ2rSQBfAQAAAA==.Faevelina:BAAALgAECgUJDAABLgAECgkJCgABAAAAAA==.Faytadori:BAAALgADCgEJAQAAAA==.',
Fe='Felgrrl:BAAALgADCgkJLwAAAA==.Felsite:BAAALgAECgkJAQAAAA==.Fester:BAAALgAECgEJAQAAAA==.Feyreh:BAAALgAECgYJBgAAAA==.',
Fi='Fieona:BAAALgADCgYJCwAAAA==.Firethorns:BAAALgAECgQJBgAAAA==.Fistandilias:BAAALgADCgkJCQAAAA==.Fitzbang:BAAALgAECgUJBwAAAA==.',
Fl='Florigrowl:BAAALgAECgMJAwAAAA==.',
Fo='Forever:BAAALgAECgMJBQABLgAFFAMJCQAKANEiAA==.Formortiis:BAAALgADCgEJAQAAAA==.Forrestior:BAABLgAECn8YAAIeAAgJoiShAQBBAwAeAAgJoiShAQBBAwAAAA==.Forsthoof:BAAALgADCgYJBgAAAA==.',
Fr='Fraga:BAAALgAECgYJDgABLgAFFAUJDAAcAJkMAA==.Frailty:BAAALgAECgYJCwAAAA==.Frique:BAABLgAECn8UAAIKAAYJPhtNMgDcAQAKAAYJPhtNMgDcAQAAAA==.Frostfingers:BAAALgAECgQJBgAAAA==.Frostyfang:BAABLgAECn8kAAMQAAgJ/xy8EQCMAQAQAAYJpCC8EQCMAQAUAAQJthNqUQC5AAAAAA==.Frozenyogert:BAAALgAECgQJBAAAAA==.',
Fu='Fufula:BAAALgADCgQJBAAAAA==.Funkbot:BAAALgAECgYJDAAAAA==.Furgilicious:BAAALgAECgEJAQABLgAECgYJDwABAAAAAA==.',
['Fä']='Färshadow:BAAALgAECgEJAQAAAA==.',
Ga='Galbur:BAACLgAFFH8MAAMcAAUJmQxgcgAPAQAcAAQJmQxgcgAPAQAbAAEJAABGVAAAAAAuAAQKfyYAAxwACAmjIVcwADUCABwACAlrH1cwADUCABsACAkUFcwXAJ0BAAAA.Galdrin:BAAALgAECgkJCgAAAA==.Gaspode:BAAALgADCgcJBwAAAA==.Gassann:BAAALgAECggJDgAAAA==.',
Ge='Geers:BAABLgAECn8dAAIfAAkJ2SJsDQAJAwAfAAkJ2SJsDQAJAwAAAA==.Geta:BAAALgAECgQJBwABLgAECgkJIAAEAF0iAA==.Getacast:BAAALgAECgEJAQABLgAECgkJIAAEAF0iAA==.Getademon:BAAALgADCgEJAQABLgAECgkJIAAEAF0iAA==.Getaform:BAAALgAECgEJAQABLgAECgkJIAAEAF0iAA==.Getagrip:BAAALgAECgQJBgABLgAECgkJIAAEAF0iAA==.Getaheal:BAAALgAECgYJBgABLgAECgkJIAAEAF0iAA==.Getalife:BAAALgAECgIJAgABLgAECgkJIAAEAF0iAA==.Getarage:BAABLgAECn8gAAIEAAkJXSIeFACtAgAEAAkJXSIeFACtAgAAAA==.',
Gh='Ghil:BAABLgAECn8vAAMGAAkJqiPlAAAJAwAGAAkJqiPlAAAJAwAHAAQJnxXfvADfAAAAAA==.',
Gi='Gigawatt:BAABLgAECn8qAAMXAAkJYRRiLgB6AQAXAAgJ0RFiLgB6AQAKAAMJ9QnanACBAAAAAA==.Gildersleeve:BAAALgAECgQJCQAAAA==.Gilia:BAAALgADCgkJOAAAAA==.Girthfist:BAABLgAECn8WAAIgAAgJRSMIBQA5AwAgAAgJRSMIBQA5AwABLgAFFAgJGQADAN8dAA==.',
Gl='Glynixtwo:BAAALgAECgMJBQAAAA==.',
Go='Goldiwarlock:BAAALgADCgcJDgAAAA==.Goloron:BAAALgADCgkJDwAAAA==.',
Gr='Graymayn:BAABLgAECn8aAAIeAAkJ8BnFCQB+AgAeAAkJ8BnFCQB+AgAAAA==.Gremel:BAABLgAECn8jAAQWAAcJqR64GwBdAQAWAAUJaxi4GwBdAQAQAAUJsBpdFwBGAQAUAAIJsx90UQC5AAAAAA==.Grimdor:BAAALgAECgUJBwAAAA==.Grimflaps:BAAALgAECgIJBAAAAA==.Grimmist:BAABLgAECn8hAAIZAAcJihjpLgCpAQAZAAcJihjpLgCpAQAAAA==.',
Gu='Guloot:BAABLgAECn8bAAMKAAgJBAYKfwDSAAAKAAgJBAYKfwDSAAAXAAUJtQZifQBlAAAAAA==.Gunboyten:BAAALgAECgIJAgAAAA==.Gunderthirth:BAACLgAFFH8ZAAIDAAgJ3x08AQDnAQADAAgJ3x08AQDnAQAuAAQKfy0AAwMACQmnJKIBAGsDAAMACQmnJKIBAGsDAAQABQmMIucsAJcBAAAA.Gurkin:BAAALgADCgEJAQAAAA==.',
Gw='Gwaeniiha:BAABLgAECn8pAAIJAAgJMA4DfgBnAQAJAAgJMA4DfgBnAQAAAA==.Gward:BAAALgAECgUJBgAAAA==.Gwizz:BAABLgAECn8sAAIfAAkJnBsJLQBfAgAfAAkJnBsJLQBfAgAAAA==.',
Ha='Halibard:BAABLgAFFH8LAAIFAAQJXQmiGgDRAAAFAAQJXQmiGgDRAAAAAA==.Halinka:BAAALgADCgYJBgAAAA==.Handsoap:BAABLgAECn8dAAIOAAgJZw9NIgBSAQAOAAgJZw9NIgBSAQAAAA==.Haquar:BAAALgAECgQJBgAAAA==.Hardhitter:BAABLgAECn8fAAQNAAkJ+hKAFgCeAQANAAgJXhKAFgCeAQADAAcJbAokHwAsAQAEAAIJcwuPkQA/AAAAAA==.',
He='Hehe:BAAALgADCgQJBAAAAA==.Helldog:BAAALgAECgMJAwABLgAECgkJJQAhALYeAA==.Hellumph:BAABLgAECn8lAAIhAAkJth56AgDLAgAhAAkJth56AgDLAgAAAA==.Hermesconrad:BAAALgAECgkJEwAAAA==.Hevensrath:BAABLgAECn85AAIJAAkJdx+VFAC/AgAJAAkJdx+VFAC/AgAAAA==.',
Ho='Hokuden:BAABLgAECn86AAIiAAkJGhmXBwAMAgAiAAkJGhmXBwAMAgAAAA==.Honina:BAAALgADCgIJAgAAAA==.Hornswaggles:BAAALgAECgQJBAAAAA==.Horsebananas:BAABLgAECn8yAAMeAAgJrRsUGgDJAQAeAAcJLRsUGgDJAQAVAAcJ+xkYRACfAQAAAA==.',
Ht='Htari:BAAALgAFFAIJAgAAAA==.',
Hu='Huddington:BAABLgAECn8jAAIjAAkJ1RerAgAQAgAjAAkJ1RerAgAQAgAAAA==.Hussh:BAAALgAECgYJDAABLgAECgkJHgAPAM0WAA==.',
Hy='Hydraness:BAAALgAECgEJAQABLgAECgQJBAABAAAAAA==.',
Ia='Iamcammy:BAAALgAECgYJEAAAAA==.',
Ic='Icedragon:BAAALgAECgEJAQAAAA==.',
Ig='Igknight:BAAALgAECgMJAwABLgAECgkJLAAgALEPAA==.',
Il='Illexi:BAAALgADCgYJBgAAAA==.',
Im='Imariz:BAAALgAECgcJBwAAAA==.Imdarkness:BAAALgAECggJDAAAAA==.Impquisitor:BAAALgAECgYJBwAAAA==.',
In='Indecent:BAABLgAECn8zAAQHAAkJOh02FACnAgAHAAkJOh02FACnAgAIAAYJHBd3FACnAQAGAAMJ3hQLGAC7AAAAAA==.Indeed:BAAALgAECgUJBgAAAA==.Inibble:BAAALgADCgcJBgAAAA==.',
Is='Ishy:BAAALgAECgUJCAAAAA==.',
Ix='Ixelle:BAAALgADCgUJDQABLgAECgYJEQABAAAAAA==.',
Iz='Izomar:BAABLgAECn8gAAIfAAgJahk8SQD5AQAfAAgJahk8SQD5AQAAAA==.',
Ja='Jackieechan:BAAALgAECgYJBgABLgAFFAUJDgALAL8kAA==.Jackiemays:BAACLgAFFH8OAAMLAAUJvyTBDwCwAQALAAQJQCbBDwCwAQAJAAIJsQGsuAA1AAAuAAQKfzEAAwsACAkUJDQNALMCAAsACAkUJDQNALMCAAkACAlgGnY9AC8CAAAA.Jaded:BAAALgAECgUJBQAAAA==.Jaleigha:BAAALgADCgYJBwAAAA==.Jamesin:BAAALgAECgYJCAAAAA==.',
Je='Jedaii:BAAALgAECgYJBgAAAA==.Jeff:BAAALgAECgEJAwAAAA==.Jeses:BAABLgAECn8vAAIJAAkJQhZjPgABAgAJAAkJQhZjPgABAgAAAA==.',
Jo='Jollah:BAAALgAECgUJBgAAAA==.',
Ju='Jutic:BAACLgAFFH8GAAIKAAMJsBibOwDfAAAKAAMJsBibOwDfAAAuAAQKfzoAAgoACQnOIm4HAC8DAAoACQnOIm4HAC8DAAAA.',
Jy='Jyssa:BAAALgADCgEJAQAAAA==.',
['Jö']='Jörmun:BAAALgAFFAIJBAAAAA==.',
Ka='Kaia:BAABLgAECn8lAAISAAkJgA83FwDVAQASAAkJgA83FwDVAQAAAA==.Kaldrich:BAAALgAECgEJAQAAAA==.Kamoto:BAAALgAECgQJBAABLgAECgkJKgAXAGEUAA==.Kanetsu:BAAALgADCgIJAgAAAA==.Kardas:BAABLgAECn8YAAMVAAkJuQeIZABvAQAVAAkJuQeIZABvAQAkAAMJ1AGLfABSAAAAAA==.Kardio:BAACLgAFFH8FAAIYAAQJ6gy5IwC9AAAYAAQJ6gy5IwC9AAAuAAQKfxoAAxgACAn+EK0rAIEBABgACAn+EK0rAIEBABkAAQkBClBnADUAAAAA.Kayj:BAAALgADCgYJBwAAAA==.Kayrina:BAAALgADCgkJCgAAAA==.Kazeer:BAABLgAECn8aAAIJAAgJ7QhhmgA1AQAJAAgJ7QhhmgA1AQAAAA==.',
Kb='Kbilly:BAABLgAECn84AAIKAAkJVyJ5BQBRAwAKAAkJVyJ5BQBRAwAAAA==.',
Ke='Kegger:BAAALgAECgEJAQAAAA==.Keirani:BAAALgAECgEJAQAAAA==.Keylerin:BAACLgAFFH8eAAISAAYJlSOgCgDEAQASAAYJlSOgCgDEAQAuAAQKfyEAAhIACQmAGkgTAH4CABIACQmAGkgTAH4CAAAA.',
Ki='Kibbik:BAACLgAFFH8MAAIdAAUJEgbRHgDlAAAdAAUJEgbRHgDlAAAuAAQKfywAAh0ACQkSFXgbAOIBAB0ACQkSFXgbAOIBAAAA.Kija:BAAALgAECgYJBgAAAA==.Kitsunami:BAAALgAECgcJBgAAAA==.',
Kl='Klepal:BAAALgADCgkJCgAAAA==.Klutchshield:BAAALgAECgEJAQAAAA==.',
Kn='Kneecap:BAAALgAECgUJCQAAAA==.Knottes:BAAALgAECgIJBAAAAA==.',
Ko='Kobe:BAAALgAECgYJEwAAAA==.Koharu:BAAALgADCggJHAAAAA==.Kookykg:BAAALgAECgEJAQAAAA==.',
Kr='Krampus:BAABLgAECn85AAIaAAkJExQACgAOAgAaAAkJExQACgAOAgAAAA==.Kranok:BAAALgAECgYJDgAAAA==.Krim:BAAALgADCgUJBgAAAA==.Krimdevourer:BAAALgADCgYJBgAAAA==.Krimhuntress:BAAALgAECgEJAgAAAA==.',
Ku='Kunac:BAABLgAECn8UAAIEAAgJRxUWIgDaAQAEAAgJRxUWIgDaAQAAAA==.',
Ky='Kynessa:BAAALgAECgYJEQAAAA==.Kyrun:BAABLgAECn8rAAIaAAkJjgymEACbAQAaAAkJjgymEACbAQAAAA==.Kyuutips:BAAALgAECgEJAQAAAA==.',
['Kã']='Kãne:BAACLgAFFH8HAAIlAAIJgwSHVQBnAAAlAAIJgwSHVQBnAAAuAAQKfyQAAyUACQmFEUQpAJQBACUACQmFEUQpAJQBAAwAAgm9Bpo4AFQAAAAA.',
La='Lamoran:BAAALgADCgkJDwAAAA==.Lannes:BAAALgAECgEJAQAAAA==.Lapz:BAAALgAECgkJEQAAAA==.Lavetra:BAAALgAECgMJBAAAAA==.Lazerdinger:BAAALgAECgEJAQAAAA==.',
Le='Legendary:BAACLgAFFH8IAAIPAAIJ0h3dDgCCAAAPAAIJ0h3dDgCCAAAuAAQKfxQAAg8ACQlbIMQDANcCAA8ACQlbIMQDANcCAAAA.Lethran:BAAALgAECgMJAwAAAA==.',
Lh='Lhani:BAABLgAECn8nAAIFAAgJrRNgIQCqAQAFAAgJrRNgIQCqAQAAAA==.',
Li='Liadrin:BAABLgAECn8eAAIPAAkJzRZ0DwDNAQAPAAkJzRZ0DwDNAQAAAA==.Lie:BAABLgAECn8dAAIMAAgJjw+7CQB9AQAMAAgJjw+7CQB9AQAAAA==.Liliana:BAAALgADCgkJNwAAAA==.Lirrasha:BAAALgADCgYJDAAAAA==.',
Ll='Llyrael:BAABLgAECn8eAAMFAAkJ/gqqKAB0AQAFAAkJ/gqqKAB0AQAdAAIJxANqjQAjAAAAAA==.',
Lo='Lolineverdie:BAABLgAECn8aAAMCAAkJ4grsVwAnAQACAAkJ4grsVwAnAQAUAAYJnQKcZwBvAAAAAA==.',
Lu='Luna:BAABLgAECn8iAAMFAAgJEQrzLQCNAQAFAAgJEQrzLQCNAQAdAAgJ1QdPNgA0AQAAAA==.',
Ly='Lyrev:BAAALgAECgYJEwAAAA==.',
['Ló']='Lórien:BAAALgADCgIJAgAAAA==.',
Ma='Macaoidh:BAAALgAECgYJBgAAAA==.Maddeleine:BAABLgAECn8gAAQFAAgJ4hFMIwCbAQAFAAcJNRNMIwCbAQAdAAMJzRDCVwCoAAAmAAQJtApkUQCoAAAAAA==.Magicdemon:BAABLgAECn83AAMOAAkJ2iViCACZAgAOAAkJpyViCACZAgARAAgJnSDUGwBjAgAAAA==.Magichunter:BAAALgAECgEJAQABLgAECgkJNwAOANolAA==.Makall:BAAALgADCgEJAQAAAA==.Makanoa:BAAALgAECgEJAgAAAA==.Malaah:BAABLgAECn9BAAIXAAkJvhWyHADvAQAXAAkJvhWyHADvAQAAAA==.Malafar:BAAALgAFFAIJAwAAAA==.Malatrixx:BAAALgAECgEJAQAAAA==.Maldiriel:BAAALgAECggJCAAAAA==.Mallikus:BAAALgADCgkJCgAAAA==.Manofsecks:BAAALgAECgQJDAAAAA==.Mansuno:BAAALgAECgUJBQAAAA==.Mapachote:BAABLgAECn8nAAIkAAgJ0hkDBwANAgAkAAgJ0hkDBwANAgAAAA==.Marodin:BAAALgADCgkJMgAAAA==.Marthaiden:BAAALgAECgkJDgAAAA==.Maryjaina:BAAALgADCgYJBgAAAA==.Mavastus:BAAALgADCgcJBwAAAA==.Mazozul:BAABLgAECn8vAAMmAAkJghX2FwAGAgAmAAgJrhP2FwAGAgAFAAUJ/BR/PQDtAAAAAA==.',
Me='Meatbaal:BAAALgADCgYJCAAAAA==.Melinaria:BAABLgAECn8oAAMdAAkJMBUvGQD1AQAdAAkJMBUvGQD1AQAmAAEJ6gF1fwAhAAAAAA==.Melisondraa:BAAALgADCgkJCQAAAA==.Meow:BAAALgADCgQJBAAAAA==.Merkala:BAAALgADCgYJCQAAAA==.Metalbot:BAAALgADCgkJCQAAAA==.',
Mi='Miarose:BAAALgAECgUJBgAAAA==.Miggydogg:BAAALgAECgUJCwAAAA==.Mileta:BAABLgAECn8bAAIUAAkJSRdJEQBDAgAUAAkJSRdJEQBDAgAAAA==.Mimic:BAAALgAECgIJAgAAAA==.Minthammer:BAAALgAECgIJBAABLgAFFAIJBAABAAAAAA==.Mirthias:BAAALgAECgMJAwAAAA==.Mistlock:BAAALgAECgQJBAAAAA==.Mistylady:BAAALgAECgIJAgAAAA==.',
Mo='Monki:BAAALgAECgYJDwAAAA==.Moozohar:BAAALgADCgEJAQAAAA==.Morgorra:BAAALgAECgMJBwAAAA==.Morvila:BAAALgAECgMJAwAAAA==.Mote:BAABLgAECn8lAAMdAAkJphCuHADYAQAdAAkJphCuHADYAQAmAAcJUxcDHgDPAQAAAA==.',
Mu='Muertes:BAAALgAECgEJAQAAAA==.Multidollar:BAAALgADCgUJBQABLgAFFAUJCwAVANsSAA==.Muminah:BAAALgAECgMJBgAAAA==.',
['Mô']='Môlly:BAACLgAFFH8NAAIFAAUJQR5jCACsAQAFAAUJQR5jCACsAQAuAAQKfyoAAgUACAmSIpUFAPYCAAUACAmSIpUFAPYCAAAA.',
Na='Narnluz:BAABLgAECn8dAAIFAAgJfBfQFwACAgAFAAgJfBfQFwACAgAAAA==.Nazor:BAABLgAECn8nAAIRAAgJ1xntPADIAQARAAgJ1xntPADIAQAAAA==.',
Ne='Necronic:BAAALgADCgYJCwAAAA==.Necroreign:BAABLgAECn9IAAIOAAkJZB5SBgDHAgAOAAkJZB5SBgDHAgAAAA==.Neith:BAAALgADCgMJAwAAAA==.Nemera:BAAALgADCgYJCAAAAA==.Nervous:BAABLgAFFH8JAAIKAAMJ0SLdKQAkAQAKAAMJ0SLdKQAkAQAAAA==.Nessee:BAAALgAECgYJEgAAAA==.',
Ni='Niall:BAABLgAECn8yAAIQAAkJ3CHHAgDqAgAQAAkJ3CHHAgDqAgAAAA==.Nilithis:BAABLgAECn8rAAMHAAkJeRndKgAoAgAHAAkJCxndKgAoAgAIAAQJGxMqHwCnAAAAAA==.Niú:BAAALgADCgYJBgAAAA==.',
No='Norsehammer:BAABLgAECn8UAAIXAAcJpgnCQwA6AQAXAAcJpgnCQwA6AQABLgAFFAIJBAABAAAAAA==.Nozmua:BAAALgADCgkJDgAAAA==.',
Ny='Nyghtchyld:BAAALgAECgcJEgAAAA==.Nyxlumina:BAAALgAECgIJAgAAAA==.',
['Né']='Néssima:BAABLgAECn8gAAMJAAkJ0RUVZQCbAQAJAAkJZw4VZQCbAQAPAAUJYhuaIwDrAAAAAA==.',
Oa='Oak:BAAALgAECgEJBQAAAA==.Oathfinder:BAAALgAECgcJEAAAAA==.',
Oc='Occurrence:BAABLgAECn8VAAMCAAgJ2gXcfQC2AAACAAcJBwTcfQC2AAAUAAEJZwIgmwAeAAAAAA==.Octalexane:BAAALgAECgUJBgAAAA==.',
On='Onebuttonman:BAAALgADCgYJBgAAAA==.Onimusha:BAAALgAECgMJAwAAAA==.',
Or='Ortalbem:BAACLgAFFH8FAAIfAAIJeBPtkwCXAAAfAAIJeBPtkwCXAAAuAAQKfzoAAh8ACQkXI04QAPQCAB8ACQkXI04QAPQCAAAA.',
Ov='Ovi:BAAALgADCgIJAgAAAA==.',
Pa='Pandariee:BAABLgAECn8VAAIcAAgJYw1rcwB1AQAcAAgJYw1rcwB1AQAAAA==.Pangsh:BAABLgAFFH8FAAIgAAIJYwSISwBkAAAgAAIJYwSISwBkAAAAAA==.Parzval:BAAALgAECgEJAgAAAA==.Paxgor:BAAALgAECgEJAQAAAA==.',
Pe='Pendaemonia:BAABLgAECn82AAIOAAkJuRYJEQAJAgAOAAkJuRYJEQAJAgAAAA==.Penelopie:BAAALgADCgYJBgAAAA==.Percfirdy:BAAALgADCgUJBQAAAA==.',
Ph='Pherix:BAABLgAECn8cAAIdAAcJ1SCWFgANAgAdAAcJ1SCWFgANAgAAAA==.Phiirys:BAAALgAECgEJAQAAAA==.',
Pi='Picaso:BAAALgADCgEJAQAAAA==.Pight:BAAALgAECggJEAABLgAECggJHQAMAI8PAA==.',
Po='Poomacha:BAABLgAECn8pAAIVAAgJRhW4RADHAQAVAAgJRhW4RADHAQAAAA==.',
Pu='Puffthemagic:BAAALgADCgYJCAAAAA==.Punishêr:BAAALgADCgMJAwABLgAECggJDAABAAAAAA==.',
Py='Pyree:BAABLgAECn8kAAMlAAkJgxADKgCPAQAlAAkJ4w8DKgCPAQAMAAcJaAlxGgBvAAAAAA==.Pyxrin:BAAALgAECgcJBwAAAA==.',
['Pø']='Pøë:BAAALgAECgkJEwABLgAFFAMJBgAGANIHAA==.',
Qu='Qu:BAAALgAFFAIJAwABLgAFFAMJBgAQAHsZAQ==.',
Qv='Qveemcorkie:BAAALgAECgEJAQAAAA==.',
['Qí']='Qín:BAAALgADCgUJAwAAAA==.',
Ra='Radagust:BAAALgAECgQJBAAAAA==.Radcat:BAAALgAECgEJBAAAAA==.Raenne:BAAALgAECgMJBQAAAA==.Ragebait:BAAALgADCgIJAgAAAA==.Rainfall:BAAALgAECgEJAgAAAA==.Raistlain:BAAALgAECgYJDwAAAA==.Raitha:BAAALgADCgUJCAAAAA==.Ralli:BAABLgAECn8pAAIRAAgJnRk3MQD2AQARAAgJnRk3MQD2AQAAAA==.Rallsdemon:BAAALgAECgQJBAABLgAECgYJCAABAAAAAA==.Rallsdk:BAAALgAECgYJCAAAAA==.Rallsodins:BAAALgAECgYJBgABLgAECgYJCAABAAAAAA==.Randomguy:BAACLgAFFH8JAAISAAQJ9RmDFABXAQASAAQJ9RmDFABXAQAuAAQKfzcAAhIACQl2JZYCACYDABIACQl2JZYCACYDAAAA.Ranulf:BAAALgAECgQJBgAAAA==.Ratava:BAAALgAECgQJBAAAAA==.Ratboy:BAEALgAECgEJAQABLgAECgkJMgAmABwjAA==.Ratrot:BAABLgAECn8jAAIKAAcJvR5TGwBkAgAKAAcJvR5TGwBkAgAAAA==.Ratsdead:BAAALgAECgEJAQAAAA==.Razenath:BAAALgADCgcJDAAAAA==.',
Re='Reinhardt:BAAALgADCgYJBgAAAA==.Rekrella:BAAALgADCgUJBQAAAA==.Reldarus:BAEBLgAECn8yAAMmAAkJHCOBAgCFAwAmAAkJHCOBAgCFAwAFAAQJ+hr8RAAlAQAAAA==.Rena:BAAALgADCgcJBwAAAA==.Rendia:BAAALgADCgMJAwAAAA==.Renik:BAAALgADCgIJAQAAAA==.Revennek:BAAALgAECgUJCgAAAA==.Reverence:BAABLgAECn8eAAIJAAkJ8A3fWwCwAQAJAAkJ8A3fWwCwAQAAAA==.Revilation:BAABLgAECn8cAAIPAAkJYBObEgCRAQAPAAkJYBObEgCRAQAAAA==.Rezjyk:BAAALgAECgYJCAABLgAECggJMwAJAAQeAA==.Rezzyk:BAABLgAECn8zAAIJAAgJBB5/JQBkAgAJAAgJBB5/JQBkAgAAAA==.',
Rh='Rhonus:BAAALgAECgEJAQAAAA==.Rhyxali:BAABLgAECn8bAAQIAAcJUw39EgAPAQAIAAcJIg39EgAPAQAGAAYJLAfXGQDeAAAHAAQJ5AHK+QBmAAAAAA==.',
Ri='Riis:BAAALgAECgYJDAAAAA==.Riiselock:BAABLgAECn8tAAMHAAgJIR5CNwAvAgAHAAcJyR1CNwAvAgAIAAQJFByMFgDjAAAAAA==.Riiwind:BAAALgADCgQJBAABLgAECgkJAwABAAAAAA==.Riktade:BAAALgADCgYJBgAAAA==.Rilight:BAAALgAECgEJAQABLgAECgkJAwABAAAAAA==.Riptidepod:BAABLgAECn8fAAMKAAgJ7gdTYAArAQAKAAgJ7gdTYAArAQAXAAIJ3gLTtAAcAAAAAA==.',
Ro='Robbiebrews:BAAALgADCgUJBQAAAA==.Robear:BAAALgAECgEJAQAAAA==.Rowin:BAAALgADCgUJBQAAAA==.',
Ry='Rynley:BAABLgAECn8WAAMSAAUJASEKJwDAAQASAAUJASEKJwDAAQAnAAIJWREnGgBwAAAAAA==.',
Sa='Sacredscales:BAABLgAECn8hAAMFAAkJtR5kCwCaAgAFAAcJ3yRkCwCaAgAdAAcJtRSGKgCGAQAAAA==.Sagerremeseb:BAAALgAECgQJBgAAAA==.Sakii:BAABLgAECn8lAAIRAAkJJRIvNwDeAQARAAkJJRIvNwDeAQAAAA==.Salera:BAAALgADCgQJBAAAAA==.Salvion:BAAALgAECgcJAQABLgAECgkJJwARANcZAA==.Samvimes:BAABLgAECn8mAAIJAAkJuQ5TXQCsAQAJAAkJuQ5TXQCsAQAAAA==.Sangreene:BAABLgAECn8dAAIdAAgJRxqFEwBYAgAdAAgJRxqFEwBYAgAAAA==.Sargis:BAACLgAFFH8FAAIJAAMJrRV0VQDxAAAJAAMJrRV0VQDxAAAuAAQKf0IAAwkACQnRItMKAAcDAAkACQnRItMKAAcDAAsACAnHG84ZACsCAAAA.Sarial:BAAALgADCgMJAwAAAA==.',
Sc='Schrödinger:BAAALgAECgYJDwABLgAECggJGAAPAOYYAA==.Sciblasts:BAAALgADCgEJAQABLgAECgYJCgABAAAAAA==.Scott:BAACLgAFFH8nAAIRAAgJxCEcBAC3AgARAAgJxCEcBAC3AgAuAAQKf0YAAhEACQmaJnUAAO4DABEACQmaJnUAAO4DAAAA.Scratchh:BAABLgAECn8dAAIgAAgJlAstNgB0AQAgAAgJlAstNgB0AQAAAA==.',
Se='Searalsa:BAAALgAECgUJBwABLgAFFAMJCQAaANMIAA==.Sentis:BAABLgAECn8eAAIUAAgJJwegQQD4AAAUAAgJJwegQQD4AAAAAA==.',
Sh='Shadowbrooks:BAAALgAECgIJAgAAAA==.Shadowgiver:BAAALgADCgcJDwAAAA==.Shadowsdemon:BAAALgADCgEJAQAAAA==.Shadowsworn:BAAALgAECgEJAQAAAA==.Shagol:BAAALgAECgQJBwAAAA==.Shalriss:BAABLgAECn8mAAIdAAgJAxrwGAD4AQAdAAgJAxrwGAD4AQAAAA==.Shamemoon:BAABLgAECn8eAAIRAAgJQxgaPQDHAQARAAgJQxgaPQDHAQAAAA==.Shamunroe:BAABLgAECn8pAAMKAAkJMAcxWwA7AQAKAAkJMAcxWwA7AQAXAAUJkxKwWgDZAAAAAA==.Shatterhoof:BAABLgAECn8hAAIQAAcJoQsYHgAFAQAQAAcJoQsYHgAFAQAAAA==.Shelle:BAAALgAECgYJCgAAAA==.Shiftys:BAAALgADCgUJCgABLgAFFAIJAgABAAAAAA==.Shingra:BAACLgAFFH8iAAIlAAYJ9BuQFQCbAQAlAAYJ9BuQFQCbAQAuAAQKfygAAiUACQnGHWINAIICACUACQnGHWINAIICAAAA.Shoof:BAAALgADCgUJBQAAAA==.',
Si='Sifû:BAAALgADCgcJDgAAAA==.Sigourney:BAAALgAECgUJBQABLgAECggJMgAeAK0bAA==.Silversho:BAAALgAECgUJBQAAAA==.Silvoid:BAAALgADCgMJAwABLgAECgUJBQABAAAAAA==.Silvren:BAABLgAECn8qAAMEAAgJ5ReXJADKAQAEAAgJ5ReXJADKAQANAAEJvwZoRgArAAAAAA==.Sindarion:BAAALgAECgUJBQABLgAFFAEJAgABAAAAAA==.Sinnerr:BAAALgAECgEJAQAAAA==.Sinz:BAAALgAECgEJBQAAAA==.Siph:BAAALgAECgEJAQAAAA==.',
Sk='Skillidan:BAABLgAECn8nAAICAAkJQhrNEwCkAgACAAkJQhrNEwCkAgAAAA==.',
Sl='Slighttrash:BAABLgAECn8jAAIeAAcJthXnHgCgAQAeAAcJthXnHgCgAQAAAA==.Sloppy:BAAALgADCgkJCgAAAA==.',
Sm='Smacka:BAAALgAECgEJAQAAAA==.Smallcrow:BAACLgAFFH8jAAMYAAgJbR4LAQCOAgAYAAgJbR4LAQCOAgAZAAEJQwtJUgBDAAAuAAQKfxYAAhgABwkuJsQHAP8CABgABwkuJsQHAP8CAAAA.Smøke:BAAALgAECgMJAwAAAA==.',
Sn='Snallygaster:BAAALgADCgYJDAABLgAECgkJIwAWAJ8bAA==.Snowsong:BAAALgAECgEJAQAAAA==.',
Sp='Spamton:BAAALgADCgEJAQAAAA==.Spectrose:BAAALgADCgEJAQAAAA==.Spirit:BAAALgAECgEJAQAAAA==.Spiro:BAAALgAFFAIJAgABLgAFFAMJBgAGANIHAA==.Spøngè:BAAALgADCgMJAwAAAA==.',
St='Starge:BAAALgAFFAEJAQAAAA==.Starre:BAAALgAECgUJBQAAAA==.Steffey:BAABLgAECn8iAAIKAAcJIgxhXAA3AQAKAAcJIgxhXAA3AQAAAA==.Straven:BAABLgAECn8jAAIfAAgJrRQxXQDBAQAfAAgJrRQxXQDBAQAAAA==.Sturgeson:BAACLgAFFH8dAAIDAAYJ3hsUCACYAQADAAYJ3hsUCACYAQAuAAQKfx8AAgMACQlvHQcMAEsCAAMACQlvHQcMAEsCAAAA.',
Su='Sulfato:BAAALgADCgEJAQAAAA==.Sulwen:BAABLgAECn9JAAIFAAkJiRdjFAAnAgAFAAkJiRdjFAAnAgAAAA==.Suzakã:BAAALgAECgcJBwAAAA==.',
Sw='Sweetpotato:BAAALgADCgEJAQAAAA==.Swiftfeet:BAABLgAECn8lAAIVAAkJABRrPQDgAQAVAAkJABRrPQDgAQAAAA==.',
Sy='Syrasia:BAAALgADCgUJBQAAAA==.Syselea:BAAALgADCgEJAQAAAA==.',
['Sö']='Söranin:BAABLgAECn8dAAIZAAYJ5xiCLwCmAQAZAAYJ5xiCLwCmAQAAAA==.',
Ta='Tachichan:BAAALgAECgYJBgAAAA==.Tadum:BAAALgADCgEJAQAAAA==.Taeili:BAABLgAECn8gAAMWAAkJIhXwJQASAQAUAAgJ2BVoNgBiAQAWAAYJKxPwJQASAQAAAA==.Talisse:BAAALgADCgYJBgAAAA==.Tanequil:BAACLgAFFH8IAAICAAMJCgJzUgBwAAACAAMJCgJzUgBwAAAuAAQKfyMAAgIACAmsDNdKAHgBAAIACAmsDNdKAHgBAAAA.Taosha:BAAALgAECgcJCAAAAA==.Targaryian:BAAALgAECgMJAwAAAA==.Tav:BAAALgADCgUJBQAAAA==.Taylea:BAABLgAECn8WAAIfAAcJpA98rQAhAQAfAAcJpA98rQAhAQABLgAECggJJgAJAKEfAA==.',
Te='Techromancer:BAAALgAECgYJCAABLgAECgcJHAAdANUgAA==.Telleria:BAAALgAECgIJAgAAAA==.Tem:BAAALgAECgMJAwAAAA==.Tenumbras:BAAALgAECgYJDAAAAA==.Termonda:BAAALgAECgEJAQAAAA==.Terraclaw:BAAALgADCgUJBwAAAA==.Terrasia:BAAALgADCgYJBgAAAA==.Terrigino:BAAALgAECgUJAwAAAA==.',
Th='Thanatias:BAABLgAECn8ZAAIbAAgJYhUjGgCCAQAbAAgJYhUjGgCCAQAAAA==.Thantasia:BAABLgAECn8WAAIfAAcJogMazQDwAAAfAAcJogMazQDwAAAAAA==.Thauras:BAAALgADCgcJFwAAAA==.Theeslan:BAABLgAECn8aAAIdAAkJ7gIZRQDxAAAdAAkJ7gIZRQDxAAAAAA==.Thokdar:BAAALgAECgUJBQAAAA==.Thom:BAACLgAFFH8LAAIiAAUJihAyDgALAQAiAAUJihAyDgALAQAuAAQKfyoAAyIACAl6JOcAABwDACIACAl6JOcAABwDABwABgmoDjmxACABAAAA.Thør:BAAALgADCgcJDgAAAA==.',
Ti='Tiernay:BAAALgADCgEJAQAAAA==.Tifà:BAAALgAECgUJCAAAAA==.Timothy:BAABLgAECn8bAAIOAAkJ7BjGEAAMAgAOAAkJ7BjGEAAMAgAAAA==.Tinkphooey:BAAALgAECgYJCwAAAA==.Tinton:BAAALgADCgEJAQAAAA==.',
To='Toishi:BAAALgAECgEJAQAAAA==.Tormmok:BAAALgAECgYJDAAAAA==.Toshindo:BAAALgAECgEJAQAAAA==.',
Tr='Traazz:BAAALgAECgkJAgAAAA==.Trashpally:BAAALgAECgEJAgAAAA==.Tremèndor:BAAALgADCgMJAwAAAA==.Trey:BAAALgAECgEJAQAAAA==.Tristra:BAAALgAECgQJBAAAAA==.',
Ts='Tsuruga:BAABLgAECn85AAIgAAkJQA4cIQCXAQAgAAkJQA4cIQCXAQAAAA==.',
Tu='Turkwise:BAABLgAECn83AAMWAAkJVx3pBQCXAgAWAAkJVx3pBQCXAgAQAAQJCBGsHgDuAAAAAA==.',
Ty='Tycondrius:BAAALgAECgEJAQAAAA==.Tyresh:BAAALgAECgEJAQAAAA==.Tyrinor:BAAALgADCgUJBQAAAA==.',
Ul='Ulogasm:BAAALgADCgkJCgAAAA==.',
Us='Usami:BAAALgAECgEJAQAAAA==.',
Ut='Utako:BAAALgADCgUJCgAAAA==.',
Uv='Uvari:BAAALgAECgcJEwAAAA==.',
Va='Vaclar:BAAALgAECgYJBwABLgAFFAUJDAAYAK8hAA==.Valhalaa:BAAALgADCgYJBgAAAA==.Valton:BAACLgAFFH8MAAIYAAUJryHiCQBwAQAYAAUJryHiCQBwAQAuAAQKf0MAAhgACQlXJpAEAAYDABgACQlXJpAEAAYDAAAA.Vanillanice:BAAALgAECgcJDwAAAA==.Varrfife:BAAALgAECgQJBAAAAA==.Vaxaldan:BAABLgAECn85AAIbAAkJLQ5bHABrAQAbAAkJLQ5bHABrAQAAAA==.',
Ve='Velithera:BAAALgADCgMJAwAAAA==.Vellithe:BAABLgAECn8WAAIJAAcJIQrjzQDpAAAJAAcJIQrjzQDpAAAAAA==.Venj:BAAALgAECgUJBgAAAA==.Verhmax:BAAALgADCgYJCwAAAA==.Verton:BAAALgADCgYJBgAAAA==.Vestrae:BAACLgAFFH8JAAMCAAUJFwiAKAATAQACAAUJFwiAKAATAQAUAAEJSQECTwAmAAAuAAQKfyUAAgIACAl+Hm8TAJoCAAIACAl+Hm8TAJoCAAAA.Vex:BAABLgAECn8XAAIHAAgJqhnuOgDqAQAHAAgJqhnuOgDqAQAAAA==.',
Vi='Vianel:BAAALgADCggJCAAAAA==.Vilten:BAAALgAECgQJCwAAAA==.Virus:BAAALgAECgkJCQAAAA==.',
Vo='Vodash:BAABLgAECn8hAAIKAAcJ3RmYLwDpAQAKAAcJ3RmYLwDpAQABLgAECgkJPAACAHIPAA==.Vostok:BAABLgAECn8eAAIHAAgJOBz9RQDEAQAHAAgJOBz9RQDEAQAAAA==.',
Wa='Wage:BAAALgADCgQJBQAAAA==.Warmth:BAAALgADCgIJAwAAAA==.',
We='Weekend:BAAALgADCgkJDwAAAA==.Wetsock:BAAALgAECgYJBwAAAA==.',
Wi='Wikket:BAABLgAECn85AAMUAAkJPRx9DACEAgAUAAkJPRx9DACEAgACAAgJ3AN3cgDUAAAAAA==.',
Wo='Wolvesbayne:BAAALgAECgEJAQAAAA==.',
Wy='Wyelie:BAAALgAECgYJDQAAAA==.Wynono:BAAALgADCgcJBwAAAA==.',
Xd='Xdeadlysinz:BAAALgAECgcJDwAAAA==.',
Xo='Xotha:BAABLgAECn87AAIRAAkJqB4cFACXAgARAAkJqB4cFACXAgAAAA==.',
Xu='Xuen:BAAALgAFFAEJAwAAAA==.',
Xy='Xythera:BAACLgAFFH8HAAIRAAQJARmwVwDTAAARAAQJARmwVwDTAAAuAAQKfx8AAxEACQmKIPYVANMCABEACQmKIPYVANMCACEAAQmwEC4xADIAAAAA.',
Ye='Yeah:BAAALgADCgYJBgABLgAFFAMJBwAJAEwMAA==.',
Yi='Yinosai:BAAALgAECgYJCAAAAA==.',
Yo='Yougot:BAAALgADCgcJCgAAAA==.',
Yu='Yuji:BAABLgAECn8hAAIIAAYJaR3ACgCHAQAIAAYJaR3ACgCHAQAAAA==.Yukì:BAAALgADCgMJAwAAAA==.Yurie:BAAALgAECgIJAgAAAA==.',
Yv='Yvonna:BAAALgADCgEJAQAAAA==.',
Za='Zaega:BAAALgADCgQJBAABLgAECggJJgAJAKEfAA==.Zahlee:BAAALgAECgQJBAAAAA==.Zaldin:BAAALgADCgYJCgAAAA==.Zalirina:BAAALgADCgIJAgAAAA==.Zanka:BAAALgAECgIJAgAAAA==.Zaridruid:BAAALgAECgkJCgAAAA==.Zarisedra:BAACLgAFFH8iAAMLAAYJSRyWCAAWAgALAAYJSRyWCAAWAgAJAAEJXgDaOwA2AAAuAAQKfxgAAwsACQkwF8kpAOMBAAsACAkGGMkpAOMBAAkAAQktBuw9ATUAAAAA.Zarissena:BAAALgAECgYJAwAAAA==.Zarris:BAAALgADCgUJDAAAAA==.',
Ze='Zennith:BAAALgADCgMJAwAAAA==.Zernacho:BAABLgAECn8gAAQFAAkJjBrBHQDJAQAFAAYJJhzBHQDJAQAdAAcJ+hFBLgBvAQAmAAMJTRMqTwCyAAAAAA==.Zerogasm:BAABLgAECn8YAAIVAAkJAhZJLAAgAgAVAAkJAhZJLAAgAgAAAA==.Zerolicious:BAAALgAECgMJAwAAAA==.Zerozaddy:BAAALgAECgUJBgAAAA==.Zevvo:BAABLgAECn8wAAIEAAkJECE5CQDGAgAEAAkJECE5CQDGAgAAAA==.',
Zi='Ziggysundust:BAAALgADCgMJAwAAAA==.',
Zo='Zoraji:BAABLgAECn86AAIgAAkJdhoEDgBOAgAgAAkJdhoEDgBOAgAAAA==.',
Zu='Zuganova:BAABLgAFFH8SAAMmAAUJDQhvIAAqAQAmAAUJ4QdvIAAqAQAFAAEJ8whwFgA8AAAAAA==.Zuggar:BAABLgAECn8fAAIEAAcJVwg2TgAFAQAEAAcJVwg2TgAFAQAAAA==.',
Zy='Zynhammer:BAABLgAECn8oAAMRAAgJgxFhXQCJAQARAAgJgxFhXQCJAQAOAAEJawZZcAAmAAAAAA==.',
['Év']='Évangeline:BAAALgADCgcJBwAAAA==.',
['Ëb']='Ëbony:BAABLgAFFH8JAAIVAAMJGBjBTgD3AAAVAAMJGBjBTgD3AAAAAA==.',
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
