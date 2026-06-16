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

local lookup = {'Priest-Shadow','Paladin-Retribution','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Unholy','Mage-Frost','DemonHunter-Devourer','Monk-Brewmaster','Evoker-Preservation','Hunter-BeastMastery','Monk-Windwalker','Priest-Holy','Shaman-Restoration','Paladin-Protection','DemonHunter-Havoc','DeathKnight-Blood','Warrior-Fury','Warrior-Protection','Hunter-Marksmanship','Hunter-Survival','Monk-Mistweaver','Druid-Balance','Druid-Restoration','Druid-Guardian','Druid-Feral','Warrior-Arms','Unknown-Unknown','Priest-Discipline','Warlock-Destruction','Warlock-Demonology','Paladin-Holy','Shaman-Elemental','Rogue-Assassination','Warlock-Affliction','Rogue-Subtlety','Rogue-Outlaw','Shaman-Enhancement','DemonHunter-Vengeance',}
local provider = {region='US',realm='Lightninghoof',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abukuma:BAAALgAECgQJBAAAAA==.',
Ad='Adraina:BAAALgADCgEJAQAAAA==.Adrewid:BAAALgADCgQJBAAAAA==.',
Ae='Aelarya:BAABLgAECn8RAAIBAAgJAQYXQgDpAAABAAgJAQYXQgDpAAAAAA==.Aenstalash:BAABLgAECn8hAAICAAgJPyOGIwB1AgACAAgJPyOGIwB1AgAAAA==.Aephium:BAABLgAECn8UAAMDAAcJuwbjXgC5AAADAAYJJgbjXgC5AAAEAAUJtASkGwBsAAAAAA==.Aesilakaersi:BAAALgAECgYJCgAAAA==.Aeson:BAABLgAECn8kAAIFAAkJiBftQwD0AQAFAAkJiBftQwD0AQAAAA==.',
Af='Afflictia:BAAALgADCgYJEAAAAA==.',
Ai='Aironel:BAAALgADCgMJAwAAAA==.',
Al='Alanza:BAAALgAECgYJBgAAAA==.Alaure:BAAALgADCgIJAgAAAA==.Alessia:BAAALgAECgIJAgAAAA==.Alfonsoo:BAAALgADCgEJAQAAAA==.Alida:BAAALgAECgQJBAAAAA==.Alistur:BAABLgAECn8fAAIGAAgJighplgBIAQAGAAgJighplgBIAQAAAA==.',
Am='Amanna:BAAALgAECgMJAwABLgAECggJHgAHAGUjAA==.Amoona:BAAALgAECgYJEgABLgAECggJHgAHAGUjAA==.',
An='Anoriia:BAAALgADCgUJBQAAAA==.',
Ar='Arcnid:BAAALgADCgYJBgAAAA==.Arfas:BAAALgADCgQJBAAAAA==.Arthraz:BAABLgAECn8kAAIIAAkJsxzcCwB1AgAIAAkJsxzcCwB1AgAAAA==.',
As='Astara:BAAALgAECgQJBAAAAA==.Astraa:BAAALgAECgIJAgAAAA==.Astrex:BAABLgAECn85AAMJAAgJng9tEgCeAQAJAAgJng9tEgCeAQADAAEJJwGSpQANAAAAAA==.',
Au='Aunaturale:BAAALgAECgkJAwAAAA==.Aureliá:BAABLgAECn8XAAIKAAcJnQoWigAlAQAKAAcJnQoWigAlAQAAAA==.',
['Aü']='Aütobot:BAABLgAECn8iAAILAAkJMw0VJgCBAQALAAkJMw0VJgCBAQAAAA==.',
Ba='Badgirl:BAACLgAFFH8MAAIMAAQJgRFMGAD0AAAMAAQJgRFMGAD0AAAuAAQKfxkAAwwACAm+E+o0ACoBAAwABgnBFuo0ACoBAAEABgktChBKAOQAAAAA.Balnar:BAABLgAECn8VAAINAAcJoxX2QAClAQANAAcJoxX2QAClAQABLgAECggJHgAOADUWAA==.Balraga:BAABLgAECn8ZAAIPAAgJUQqZKgAkAQAPAAgJUQqZKgAkAQAAAA==.Bargrivyek:BAAALgADCgMJAwAAAA==.Bayded:BAAALgADCgEJAQAAAA==.',
Be='Beastboyy:BAAALgAECgUJBQAAAA==.Bega:BAACLgAFFH8oAAMFAAgJ9hqCCwB1AgAFAAcJ9hqCCwB1AgAQAAEJAABnUAAAAAAuAAQKf0EAAwUACQnoJTQFAFADAAUACQnoJTQFAFADABAABgkrFzslABUBAAAA.Benton:BAAALgAECgQJCAAAAA==.',
Bi='Bigglimpie:BAAALgAECgYJDQAAAA==.',
Bl='Bloodlustplz:BAABLgAECn8qAAMRAAkJshd9KwCmAQARAAcJLx59KwCmAQASAAgJLQ9dGwBZAQAAAA==.',
Bo='Bobster:BAABLgAECn8kAAIGAAkJuxFXYAC8AQAGAAkJuxFXYAC8AQAAAA==.Bonepaw:BAAALgAECgMJBAABLgAECgcJFAANAHwVAA==.Booyea:BAACLgAFFH8FAAIQAAMJAReFIgDVAAAQAAMJAReFIgDVAAAuAAQKfz4AAhAACQklHLYKAGMCABAACQklHLYKAGMCAAAA.',
Br='Brew:BAAALgAECgcJBwAAAA==.Brewwnor:BAAALgAECgcJCwAAAA==.Brickdemkeys:BAABLgAECn8fAAIGAAgJPBq5YgC2AQAGAAgJPBq5YgC2AQAAAA==.Brisfloggnaw:BAAALgAFFAEJAQAAAA==.',
Ca='Caladk:BAAALgADCgUJBQABLgAFFAcJIAATAAgfAA==.Calamuelis:BAACLgAFFH8gAAQTAAcJCB/WBwCeAQATAAcJ7hvWBwCeAQAUAAUJTyJfCgBxAQAKAAIJ1RuFcQCvAAAuAAQKfx0ABBMACAnSJLsNANcCABMACAmWJLsNANcCABQABAn5JD8wACgBAAoAAQkIJhfxAGoAAAAA.Caliope:BAABLgAECn8cAAIVAAgJfhXXJAD2AQAVAAgJfhXXJAD2AQAAAA==.Capsasin:BAAALgADCgUJBQAAAA==.Carnage:BAAALgAFFAIJAgAAAA==.Cazlek:BAAALgAECgQJCwAAAA==.',
Ce='Celery:BAAALgAECgMJAwABLgAECgkJJAAIALMcAA==.Celldweller:BAAALgAECgYJCgAAAA==.Cerdred:BAABLgAECn8dAAIWAAUJARDLSQAEAQAWAAUJARDLSQAEAQAAAA==.Ceredis:BAAALgAECgEJAQAAAA==.Cerelus:BAABLgAECn8gAAIGAAkJWA8BVADdAQAGAAkJWA8BVADdAQAAAA==.',
Ch='Chaac:BAAALgAECgYJCAABLgAECggJFgAJALITAA==.Chmmr:BAAALgADCgMJAwAAAA==.Chowilawu:BAAALgADCgkJCQAAAA==.Chriswilsonn:BAAALgAECgQJCAAAAA==.Chuca:BAAALgAECgYJBgAAAA==.Chucalu:BAABLgAECn8WAAUXAAgJVh4ANwDLAQAXAAYJUyAANwDLAQAYAAQJCx7wEQBVAQAWAAIJih/MWACqAAAZAAEJLwbeMgA2AAAAAA==.Chéwtoy:BAAALgAECgIJAgAAAA==.',
Cl='Clax:BAAALgAECgIJBQAAAA==.',
Co='Cobeam:BAAALgAECgUJEQAAAA==.Cowpernicus:BAABLgAECn8iAAIXAAkJ7SDbBgBIAwAXAAkJ7SDbBgBIAwABLgAFFAMJCgANAB4bAA==.',
Cr='Crungleman:BAABLgAECn8YAAIKAAcJuRiOXQCJAQAKAAcJuRiOXQCJAQAAAA==.',
Ct='Cthuwu:BAAALgAECgQJBAABLgAECggJFgAJALITAA==.',
Cu='Curoi:BAABLgAECn8rAAMZAAkJjxdaCABDAgAZAAkJjxdaCABDAgAXAAgJRAozeQDsAAAAAA==.',
['Cã']='Cãrloy:BAACLgAFFH8ZAAIRAAQJlBvGGgBCAQARAAQJlBvGGgBCAQAuAAQKf1cAAxEACQlWIugGAO8CABEACQlWIugGAO8CABoAAgkpIXtDALYAAAAA.',
['Cê']='Cêlestial:BAABLgAECn8eAAMHAAgJZSNTGwBtAgAHAAgJ9SJTGwBtAgAPAAMJkiFIPQC9AAAAAA==.',
Da='Daedalas:BAABLgAECn8XAAMBAAgJnx/HDgBrAgABAAgJnx/HDgBrAgAMAAIJMALWaQA8AAAAAA==.Damonk:BAAALgADCgYJBgABLgAECgkJIAASAOIaAA==.Danevolent:BAABLgAECn8gAAMMAAcJ9yJ9DQCAAgAMAAcJ9yJ9DQCAAgABAAQJEA0LXwCYAAABLgAECgkJIAASAOIaAA==.Danzaster:BAAALgADCgQJBAAAAA==.Darkxsoul:BAABLgAECn8eAAIOAAgJNRZ8EAC4AQAOAAgJNRZ8EAC4AQAAAA==.Darthknull:BAACLgAFFH8SAAICAAQJBRf0NQA8AQACAAQJBRf0NQA8AQAuAAQKfzYAAgIACQmjIZIYAK0CAAIACQmjIZIYAK0CAAAA.Darthtalon:BAAALgAECgcJCwABLgAFFAQJEgACAAUXAA==.',
De='Deadeyedicky:BAAALgAECgkJBwAAAA==.Deathmachine:BAAALgADCgUJBQAAAA==.Deathniight:BAAALgAECgUJBAAAAA==.Deathseer:BAAALgAECgcJDgAAAA==.Deathwood:BAAALgADCgUJBgABLgAECgEJAQAbAAAAAA==.Deatthdecay:BAAALgAECggJBAAAAA==.Deitrichx:BAABLgAECn8lAAITAAkJnxlPBwAPAgATAAkJnxlPBwAPAgAAAA==.Delley:BAAALgADCgEJAQAAAA==.Deminestrea:BAABLgAECn8aAAIQAAYJchD4KQAFAQAQAAYJchD4KQAFAQAAAA==.Demonswhere:BAAALgADCgMJAwAAAA==.Devilscreed:BAAALgAECgEJAQAAAA==.',
Di='Dingleberrys:BAAALgADCgEJAQAAAA==.Dippindots:BAAALgAECgYJCAAAAA==.Disshammy:BAAALgAFFAIJAgABLgAFFAgJIgADANEhAA==.Dittoz:BAAALgADCgUJBAAAAA==.',
Do='Dolfcritler:BAAALgAECgQJBAAAAA==.Dolfcrittler:BAAALgADCgEJAQAAAA==.Donkform:BAAALgAECgkJEgAAAA==.Donniyii:BAAALgAECgcJBwABLgAECgkJOwAcAJQfAA==.Doomrider:BAAALgADCgYJBgAAAA==.Dottzz:BAABLgAECn8aAAIdAAYJ8B27FQCcAQAdAAYJ8B27FQCcAQAAAA==.',
Dr='Draconith:BAACLgAFFH8XAAIJAAUJZxGuFABAAQAJAAUJZxGuFABAAQAuAAQKfzUAAgkACQmSGzMFAMMCAAkACQmSGzMFAMMCAAAA.Dramoo:BAAALgAECgMJAwAAAA==.Draqkmar:BAABLgAECn8bAAIKAAYJVQpEoQD5AAAKAAYJVQpEoQD5AAAAAA==.Dreddwing:BAABLgAECn8WAAMJAAgJshNnEADCAQAJAAcJcBVnEADCAQADAAIJJg/qeABsAAAAAA==.Dredfox:BAAALgAECgIJAgABLgAECgkJRgAWAPURAA==.Drunkenoodle:BAAALgADCgYJBgAAAA==.',
Du='Dunsparrow:BAACLgAFFH8KAAINAAMJHhvMPQDmAAANAAMJHhvMPQDmAAAuAAQKf0YAAg0ACQm2IogFAFcDAA0ACQm2IogFAFcDAAAA.Durzul:BAAALgAECgEJAQAAAA==.',
Ei='Eightyone:BAAALgAECggJDwAAAA==.Eindraken:BAACLgAFFH8TAAIJAAUJ5QT+GgDeAAAJAAUJ5QT+GgDeAAAuAAQKfzkAAgkACQn7EgkNAP4BAAkACQn7EgkNAP4BAAAA.Eiroh:BAAALgAECggJDAABLgAECggJHgAOAPERAA==.Eisis:BAABLgAECn8/AAIZAAkJVBAsFAB5AQAZAAkJVBAsFAB5AQAAAA==.',
El='Elanalué:BAAALgAECgYJEAABLgAECggJHAAVAH4VAA==.',
Er='Erixee:BAAALgAECgUJBgAAAA==.Erroz:BAAALgADCgIJAQAAAA==.',
Es='Eshonäi:BAABLgAECn8aAAIeAAYJtRE7jAAhAQAeAAYJtRE7jAAhAQAAAA==.Espriesso:BAABLgAECn8VAAQcAAgJAQ3eMQBRAQAcAAcJ3wveMQBRAQABAAQJvgTEYwCHAAAMAAIJDAecdABWAAABLgAECgkJLAAIALEPAA==.',
Ev='Evodragker:BAABLgAECn8kAAMDAAkJKxSyIADSAQADAAkJKxSyIADSAQAJAAEJcAk4OwAzAAAAAA==.',
Fe='Feider:BAAALgAECgEJAQAAAA==.Felais:BAABLgAFFH8GAAIXAAQJpwdjPAC4AAAXAAQJpwdjPAC4AAAAAA==.Feldron:BAAALgAECgcJEwAAAA==.Felkaos:BAAALgADCgEJAQAAAA==.Fellura:BAAALgAECgYJDAAAAA==.Femaledawg:BAAALgADCgcJEAAAAA==.',
Fi='Fingor:BAAALgAECgYJBwAAAA==.',
Fl='Flamecube:BAAALgADCgcJCAAAAA==.Flashx:BAABLgAECn8kAAMfAAgJ3iC3CQDuAgAfAAgJ3iC3CQDuAgACAAEJQQwxkwEvAAAAAA==.',
Fo='Foxxeyineawo:BAAALgADCgcJCAAAAA==.',
Fr='Frevmk:BAAALgAECgEJAgAAAA==.Frofrohunter:BAABLgAECn8sAAMKAAkJaB+kEgCiAgAKAAkJaB+kEgCiAgATAAUJAxLZTgAUAQAAAA==.Frofrolock:BAAALgAECgcJDgAAAA==.Froggie:BAABLgAECn8UAAMNAAcJfBVOUABsAQANAAcJfBVOUABsAQAgAAMJXQ/iaACgAAAAAA==.Froshaman:BAAALgAECgEJAQAAAA==.',
Fu='Fuzywuuzy:BAACLgAFFH8NAAIXAAMJ1BT4OQDBAAAXAAMJ1BT4OQDBAAAuAAQKfyUAAxcACAnUI6MLAAIDABcACAnUI6MLAAIDABYABwk6FnknAJABAAAA.',
Ga='Gazdorn:BAABLgAECn8qAAISAAkJeRIyEgDEAQASAAkJeRIyEgDEAQAAAA==.',
Ge='Genebelcher:BAAALgAECgEJAQAAAA==.',
Gh='Ghost:BAABLgAECn8hAAIhAAgJdhqNBQAbAgAhAAgJdhqNBQAbAgAAAA==.',
Gi='Gigof:BAABLgAECn8rAAMWAAkJPxL8JACfAQAWAAgJ0RL8JACfAQAXAAcJ/ArkgAC1AAAAAA==.',
Gl='Glissa:BAABLgAECn8UAAQiAAcJdCWRAQDTAgAiAAcJEiWRAQDTAgAeAAMJhSJYogAUAQAdAAIJjxpcRACkAAAAAA==.',
Go='Gobah:BAABLgAECn8YAAMjAAgJ5hVEGQDMAQAjAAgJ5hVEGQDMAQAkAAUJsQesFgCpAAAAAA==.',
Gt='Gt:BAAALgAECgMJBQAAAA==.',
Gu='Gulldan:BAABLgAECn8iAAIeAAgJXxgZNgD/AQAeAAgJXxgZNgD/AQAAAA==.',
Gw='Gwyndolin:BAAALgADCgUJBQAAAA==.',
Ha='Habanero:BAAALgAECgQJBgABLgAECgkJJAAIALMcAA==.Hadory:BAABLgAECn8UAAMCAAgJqxUYUQDTAQACAAgJqxUYUQDTAQAfAAQJWhkASwANAQAAAA==.Harrowhark:BAABLgAECn9BAAQiAAkJUwq8EQBFAQAeAAkJhgnLXgCCAQAiAAgJuwm8EQBFAQAdAAQJyQVEMQBWAAAAAA==.',
He='Hellzzdemon:BAABLgAECn8bAAIPAAgJExCSIABvAQAPAAgJExCSIABvAQAAAA==.Hendricks:BAAALgAECgQJCgAAAA==.Hexinverter:BAAALgAECgQJCQAAAA==.Hexzard:BAAALgADCgQJBAABLgAECgUJEQAbAAAAAA==.Hezekiiah:BAAALgAECgYJDQAAAA==.',
Ho='Holeecow:BAAALgADCgIJAgABLgAFFAMJCgANAB4bAA==.Holycannoli:BAAALgAECggJDgAAAA==.Horiffic:BAAALgAECgcJEwAAAA==.Horok:BAAALgAECgYJDQAAAA==.Hotsforthots:BAAALgAECgUJBQAAAA==.Hotwheels:BAAALgAECgMJAwAAAA==.',
Hu='Hubert:BAABLgAECn8WAAIVAAgJwQm9VAAUAQAVAAgJwQm9VAAUAQAAAA==.Hubertdale:BAAALgAECgMJAwAAAA==.Hulkblood:BAAALgAECgEJAQAAAA==.Hummingbrook:BAAALgAECgcJDAABLgAFFAgJGwAHAFYSAA==.',
Hy='Hypandia:BAAALgAECggJDAAAAA==.',
Ic='Ichaerus:BAAALgAECgQJBQABLgAECggJFwABAJ8fAA==.Ichtheblack:BAAALgAECgcJCQABLgAECggJFwABAJ8fAA==.Ichtu:BAAALgAECgEJAQABLgAECggJFwABAJ8fAA==.',
Ii='Iilli:BAABLgAECn87AAMcAAkJlB8rBwAIAwAcAAkJlB8rBwAIAwABAAkJnxvCDQB4AgAAAA==.',
In='Inari:BAABLgAECn8XAAIBAAkJSgvrKgB6AQABAAkJSgvrKgB6AQAAAA==.Inkkubus:BAACLgAFFH8bAAQdAAYJeRdZDgC+AAAeAAMJQh+LagDpAAAdAAMJXApZDgC+AAAiAAIJUxYMHgBSAAAuAAQKfxcABB4ACQmPHi86APEBAB4ABwnZHy86APEBAB0AAwnpG0cWAO8AACIAAQkAABEnAFUAAAAA.Instagatorz:BAAALgADCgUJBgAAAA==.',
Iq='Iq:BAAALgAECgEJAQAAAA==.',
Iw='Iwkms:BAACLgAFFH8OAAIZAAQJihY7CAAhAQAZAAQJihY7CAAhAQAuAAQKfyMAAhkACAliIzMCADEDABkACAliIzMCADEDAAEuAAUUBQkGACQAwhYA.',
Ja='Jade:BAABLgAECn8dAAIIAAYJ9CSmFQD9AQAIAAYJ9CSmFQD9AQAAAA==.Jatheo:BAAALgADCgIJAgAAAA==.',
Je='Jenliz:BAAALgADCgEJAQABLgAECgYJEQAbAAAAAA==.Jeronor:BAAALgAECgIJAgAAAA==.',
Ji='Jimmick:BAABLgAECn8WAAINAAcJfyPoEADEAgANAAcJfyPoEADEAgABLgAECggJFAACAKsVAA==.Jisung:BAABLgAECn8UAAMlAAYJkQKDKgCcAAAlAAYJkQKDKgCcAAAgAAIJHAEJwgARAAAAAA==.',
Jo='Jorad:BAAALgADCgEJAQAAAA==.',
Jt='Jtheman:BAAALgAECgQJBAAAAA==.',
Ju='Junebugg:BAAALgADCgEJAQAAAA==.',
Ka='Kaing:BAAALgAECgYJCwAAAA==.Kaissa:BAAALgAECgEJAQAAAA==.Kalena:BAACLgAFFH8FAAIGAAMJMwPIkQCxAAAGAAMJMwPIkQCxAAAuAAQKfz4AAgYACQnnDoNgALwBAAYACQnnDoNgALwBAAAA.Kandikkiss:BAAALgAECgUJCwAAAA==.Kaos:BAABLgAECn8jAAIGAAkJ+hHVXADFAQAGAAkJ+hHVXADFAQAAAA==.Kariatyda:BAABLgAECn8uAAIKAAkJMxgIGwBlAgAKAAkJMxgIGwBlAgAAAA==.Kasai:BAAALgADCgMJAwABLgAECggJJQACAKcVAA==.Kassandra:BAACLgAFFH8MAAIGAAMJ2R6KZwAdAQAGAAMJ2R6KZwAdAQAuAAQKfz4AAgYACQnvHPUbALECAAYACQnvHPUbALECAAAA.Kay:BAAALgAECgcJCQAAAA==.Kayden:BAABLgAECn8aAAIVAAYJhBh2JACQAQAVAAYJhBh2JACQAQABLgAECggJGwAfAFUcAA==.Kayn:BAAALgAECgIJAgAAAA==.',
Ke='Keelistus:BAAALgAECgQJBAAAAA==.Kekio:BAAALgAECgUJBQAAAA==.Kelisola:BAAALgADCgEJAQAAAA==.Kelzor:BAAALgAECgEJAQAAAA==.Keruu:BAAALgAECgcJBwAAAA==.',
Kh='Khaylorn:BAAALgAECgMJBgAAAA==.',
Ki='Kiloton:BAABLgAECn8oAAIYAAkJrRP5EgC+AQAYAAkJrRP5EgC+AQAAAA==.Kinari:BAAALgAECggJEgAAAA==.Kitzy:BAABLgAECn8iAAIGAAkJ0gS5mgBBAQAGAAkJ0gS5mgBBAQAAAA==.',
Kl='Klapso:BAAALgADCgYJDQAAAA==.Klippertdk:BAABLgAECn83AAIFAAkJXhg7KgBVAgAFAAkJXhg7KgBVAgAAAA==.Klugamonk:BAAALgADCgUJBQAAAA==.Klutz:BAABLgAECn8qAAIXAAkJXw/NNQDAAQAXAAkJXw/NNQDAAQAAAA==.',
Ko='Korgan:BAAALgAECggJDgAAAA==.Korgriku:BAAALgADCgMJAwAAAA==.',
Kr='Kreznor:BAAALgAECgIJAgAAAA==.',
Ku='Kurzo:BAACLgAFFH8NAAIRAAQJCx+IDwCDAQARAAQJCx+IDwCDAQAuAAQKfzsAAxEACQnrIrYGAPMCABEACQnrIrYGAPMCABIABQmtEussANoAAAAA.',
Ky='Kylarian:BAABLgAECn8iAAIPAAkJyQZzKgAlAQAPAAkJyQZzKgAlAQAAAA==.Kyntara:BAAALgAECgYJDQAAAA==.Kyronian:BAAALgAECgYJDwAAAA==.',
['Kâ']='Kâsâi:BAABLgAECn8lAAICAAgJpxVHWADBAQACAAgJpxVHWADBAQAAAA==.',
La='Lachancea:BAAALgAECgEJAQABLgAECggJFQAeADsZAA==.Lakshmee:BAAALgAECgcJDgAAAA==.',
Le='Ledarm:BAAALgAECggJEwAAAA==.Leigin:BAAALgADCgYJBgAAAA==.Lexxi:BAABLgAECn86AAICAAkJQhW6QgD8AQACAAkJQhW6QgD8AQAAAA==.',
Li='Lifewing:BAAALgAECgQJCgAAAA==.Lightbehunt:BAAALgAECgQJBgAAAA==.Lightfivhapy:BAAALgAECgcJEQAAAA==.Lightsglory:BAAALgADCgMJAwAAAA==.Lilly:BAAALgAECgYJCgAAAA==.Livaless:BAAALgADCgQJBAABLgAECgkJJQAeAFAiAA==.',
Lu='Lucialyn:BAAALgAECgcJDAABLgAECgcJFwAcAOojAA==.',
Ly='Lyllith:BAABLgAECn8cAAIhAAYJjREWDABkAQAhAAYJjREWDABkAQAAAA==.Lysende:BAAALgADCgQJBAAAAA==.',
Ma='Madamenoodle:BAAALgADCgkJCQAAAA==.Magnass:BAAALgADCgYJBgABLgAECgkJIAASAOIaAA==.Magnius:BAAALgADCgEJAQAAAA==.Mal:BAAALgAECggJCAAAAA==.Mastablasta:BAAALgAECgQJCQAAAA==.Maursaline:BAABLgAECn8lAAIXAAkJqgesWQAoAQAXAAkJqgesWQAoAQAAAA==.Mawea:BAAALgAECgUJDAAAAA==.Mawks:BAACLgAFFH8FAAIUAAIJlRJwJQChAAAUAAIJlRJwJQChAAAuAAQKfzYAAhQACQmoGDcNAFMCABQACQmoGDcNAFMCAAAA.',
Mc='Mcstukes:BAAALgAECgQJCAAAAA==.',
Me='Medeas:BAAALgAECgUJCgAAAA==.Meragos:BAAALgAECgMJAwAAAA==.Meteor:BAAALgADCgQJBAAAAA==.',
Mi='Migzeviltwin:BAAALgAECgEJAgAAAA==.Mimicz:BAAALgADCgUJBQAAAA==.Minitry:BAAALgAECgEJAgAAAA==.Mixxon:BAAALgAECgYJDwAAAA==.',
Mo='Moinion:BAAALgADCgQJCAAAAA==.Moldbreather:BAAALgAECgEJAQAAAA==.Moomooimacow:BAAALgAECgQJBAAAAA==.Moomoomonkey:BAABLgAECn8fAAIgAAkJMhd1HQDzAQAgAAkJMhd1HQDzAQAAAA==.Morhgana:BAAALgAECgYJDwAAAA==.',
Mx='Mxmlxxix:BAABLgAECn8jAAMMAAgJygGESgC1AAAMAAgJygGESgC1AAABAAIJXwHWZQAtAAAAAA==.',
['Mö']='Mördecai:BAAALgAECgQJBAAAAA==.',
Na='Naija:BAAALgAECgEJAgAAAA==.Nati:BAAALgAECgUJBQAAAA==.',
Ne='Nephele:BAAALgAECgEJAQAAAA==.Neptune:BAAALgAECgQJCAAAAA==.Newport:BAAALgAECgMJAwABLgAECgcJIwAjAMsXAA==.',
Ni='Nikorobin:BAAALgAECgQJBwABLgAFFAgJGwAHAFYSAA==.Nilius:BAAALgADCgcJBwABLgAECggJFwABAJ8fAA==.',
No='Noodles:BAAALgADCgkJDAABLgAECgcJDQAbAAAAAA==.Norgalina:BAAALgADCgUJBQAAAA==.',
Ny='Nymara:BAABLgAECn8eAAIOAAgJ8RG0FgBpAQAOAAgJ8RG0FgBpAQAAAA==.',
['Ní']='Níce:BAAALgAECgIJAwAAAA==.',
['Nü']='Nügs:BAAALgAECggJEwAAAA==.Nüguns:BAAALgAECgcJEQAAAA==.',
Ol='Olei:BAAALgADCgUJBQAAAA==.',
Or='Orlick:BAAALgAECgEJAQAAAA==.Orrok:BAAALgADCgYJBwAAAA==.',
Pa='Painlink:BAAALgAECgUJCQABLgAECgkJKQARAHkRAA==.Painnkiller:BAACLgAFFH8IAAIKAAMJCBn1VAD1AAAKAAMJCBn1VAD1AAAuAAQKfzgAAgoACQnKHXQXAJYCAAoACQnKHXQXAJYCAAAA.Papyto:BAAALgADCgYJBwAAAA==.Parsley:BAABLgAECn8mAAMiAAgJmSAqAwCHAgAiAAgJmSAqAwCHAgAeAAMJmxlYwQDJAAABLgAECgkJJAAIALMcAA==.Paxis:BAAALgAECgkJDgAAAA==.',
Pe='Perriwinkle:BAABLgAECn9HAAQZAAkJDx+3AwDQAgAZAAkJDx+3AwDQAgAYAAgJoRPkGACCAQAXAAQJPwxAiACkAAAAAA==.Perseus:BAAALgADCgMJAwAAAA==.',
Ph='Phission:BAAALgADCgEJAQAAAA==.Phobya:BAABLgAECn8lAAIXAAgJbRtQHABhAgAXAAgJbRtQHABhAgAAAA==.Phylloxeras:BAABLgAECn9KAAIFAAkJoiW9AgByAwAFAAkJoiW9AgByAwAAAA==.',
Pl='Pleasure:BAAALgADCgMJAwAAAA==.Pleggashroom:BAAALgADCgEJAQAAAA==.',
Po='Powders:BAABLgAECn80AAIGAAkJ5Rv4KgBrAgAGAAkJ5Rv4KgBrAgAAAA==.Powderysham:BAAALgAECgcJCwABLgAECgkJNAAGAOUbAA==.',
Pr='Praystatiôn:BAAALgAECgEJAQABLgAECgcJGwAeAHcfAA==.Proshot:BAACLgAFFH8FAAIUAAMJuxcIGwDzAAAUAAMJuxcIGwDzAAAuAAQKfzIAAhQACQk4IsMCABcDABQACQk4IsMCABcDAAAA.',
Pu='Puddles:BAAALgAECgEJAQAAAA==.',
Pz='Pzalmo:BAAALgAECgMJAwABLgAECgkJHwAEAJkUAA==.',
Ra='Raccoon:BAACLgAFFH8FAAIeAAMJEAQVjACmAAAeAAMJEAQVjACmAAAuAAQKfz4AAx4ACQmbEbVBANYBAB4ACQmbEbVBANYBACIAAQloC5I8ADYAAAAA.Ralor:BAAALgADCgEJAQAAAA==.Ravenhawk:BAAALgAECgYJEAAAAA==.Razza:BAAALgADCgYJCAAAAA==.',
Re='Remember:BAAALgADCgEJAQAAAA==.Renivatio:BAABLgAECn8jAAIFAAgJEhyVLgBCAgAFAAgJEhyVLgBCAgAAAA==.',
Rh='Rhyntix:BAAALgADCgEJAQAAAA==.',
Ro='Roronoazoro:BAACLgAFFH8bAAIHAAgJVhJ/FAABAgAHAAgJVhJ/FAABAgAuAAQKfyEAAwcACQlIH2ojAH0CAAcACQlIH2ojAH0CACYAAglxEwUmAFQAAAAA.',
Ry='Ryrin:BAABLgAECn8jAAMRAAkJBRB2MwB8AQARAAkJBRB2MwB8AQAaAAIJ9gfWawBEAAAAAA==.Ryrìn:BAAALgADCgEJAQAAAA==.Ryrín:BAAALgAECggJEwAAAA==.',
Sa='Samidrac:BAABLgAECn8UAAIJAAYJsgHZLwBpAAAJAAYJsgHZLwBpAAAAAA==.Sammidormu:BAABLgAECn8jAAQEAAgJ5RNICgB4AQAEAAcJABVICgB4AQADAAcJbAtZNgAgAQAJAAEJ2QEPTgAjAAAAAA==.Sanderwoof:BAAALgAECggJCAAAAA==.Saret:BAAALgADCgMJAwAAAA==.Sarzul:BAABLgAECn8VAAMdAAYJ/A8VNADnAAAeAAYJ2gzAmwAiAQAdAAUJThEVNADnAAAAAA==.Satoshie:BAAALgAECggJCQAAAA==.',
Sc='Scerevisiae:BAABLgAECn8VAAMeAAgJOxk/fQA+AQAeAAUJwBs/fQA+AQAdAAQJxBSjLgABAQAAAA==.',
Se='Sedelis:BAABLgAECn8fAAIfAAkJzwoUMQCRAQAfAAkJzwoUMQCRAQAAAA==.Sefirbrena:BAAALgADCgkJAwAAAA==.Selaya:BAAALgAECgEJAQAAAA==.Semnai:BAABLgAECn88AAIXAAkJexZvGwBoAgAXAAkJexZvGwBoAgAAAA==.Serafín:BAABLgAECn84AAIIAAkJpA7DIQCXAQAIAAkJpA7DIQCXAQAAAA==.Sevilicious:BAAALgADCgQJAwAAAA==.',
Sh='Shaay:BAAALgAECgcJDwAAAA==.Shadowlock:BAAALgAECgEJAgAAAA==.Shadowpyro:BAAALgAECgEJAQAAAA==.Shamwig:BAAALgADCgUJBQAAAA==.Shazzam:BAAALgAECggJDwAAAA==.Shieldwall:BAABLgAECn8qAAISAAgJWg+DGwBYAQASAAgJWg+DGwBYAQAAAA==.',
Si='Silanah:BAAALgAECgEJAQABLgAFFAMJCgANAB4bAA==.Silverhâwk:BAAALgADCgEJAQAAAA==.Sinastys:BAABLgAECn8aAAICAAgJ9RDvfwBsAQACAAgJ9RDvfwBsAQAAAA==.',
So='Solone:BAAALgAECgYJEgAAAA==.Sopidia:BAABLgAECn8kAAMNAAgJSRd4PAC4AQANAAcJtBZ4PAC4AQAgAAUJHQZWcgCPAAAAAA==.Sorvato:BAABLgAECn80AAIHAAkJCxngIQBHAgAHAAkJCxngIQBHAgAAAA==.',
Sp='Spoonzz:BAABLgAECn8xAAMLAAkJDSQ+BQD8AgALAAkJDSQ+BQD8AgAIAAIJKx9ZWAClAAAAAA==.',
St='Stamavan:BAABLgAECn8kAAIYAAkJzCIFAwD6AgAYAAkJzCIFAwD6AgAAAA==.Starflayer:BAABLgAECn8nAAMHAAkJXxxTJQA1AgAHAAkJbhtTJQA1AgAmAAIJYxr3IAB8AAAAAA==.Steb:BAAALgADCgMJAwAAAA==.Sterjariger:BAAALgAECgYJBgABLgAFFAMJBwAKABUMAA==.',
Su='Sunari:BAAALgAECgMJBgAAAA==.Supermelon:BAABLgAECn8WAAIhAAcJXBEnDQBVAQAhAAcJXBEnDQBVAQAAAA==.',
Sw='Swenior:BAAALgADCgEJAQAAAA==.',
Sy='Syarli:BAAALgAECgcJBwAAAA==.Sylvaeelor:BAAALgAFFAIJAwABLgAFFAQJDgAaAG4TAA==.Sylvanaria:BAACLgAFFH8FAAINAAMJsyUxJwBCAQANAAMJsyUxJwBCAQAuAAQKfz4AAg0ACQlbJigBAMQDAA0ACQlbJigBAMQDAAAA.Sylvanaris:BAAALgAECgYJEQAAAA==.Systyx:BAABLgAECn8bAAIeAAcJdx9pTAC0AQAeAAcJdx9pTAC0AQAAAA==.',
Ta='Takura:BAAALgAECgkJBwABLgAECgkJCwAbAAAAAA==.Talenel:BAAALgAECgQJBAAAAA==.Talyzien:BAAALgADCgYJBwAAAA==.',
Te='Tealan:BAACLgAFFH8HAAMJAAQJugwrGgDpAAAJAAQJugwrGgDpAAADAAEJRgKZZwAyAAAuAAQKfzAAAwMACQm0GOASAEcCAAMACQm0GOASAEcCAAkACAmpEukcAJ4BAAAA.Tealyn:BAAALgAECgYJBgAAAA==.Teluz:BAAALgAECgQJCgAAAA==.Tendra:BAAALgAECgYJBQAAAA==.Teronreborn:BAABLgAECn8lAAIFAAkJOiWGFAAAAwAFAAkJOiWGFAAAAwAAAA==.',
Th='Thaneer:BAAALgAECgYJBwAAAA==.Thanos:BAABLgAECn8dAAICAAYJ7Q6KpAA3AQACAAYJ7Q6KpAA3AQAAAA==.Thebadmage:BAAALgAECgcJBAAAAA==.Throstmok:BAACLgAFFH8OAAIQAAQJUhADIADkAAAQAAQJUhADIADkAAAuAAQKfzcAAhAACQm3HmYJAHsCABAACQm3HmYJAHsCAAAA.Thràll:BAAALgAECgUJBQAAAA==.Thränton:BAAALgAECgEJAQABLgAECgcJFAAmALwhAA==.Thumbalina:BAAALgAECgYJEQAAAA==.',
To='Totemtuggér:BAAALgADCgIJAgAAAA==.',
Tp='Tpaste:BAAALgADCgcJBwAAAA==.',
Tr='Trampstãmp:BAAALgAECgIJAgAAAA==.Trinitea:BAAALgAECgEJAQAAAA==.Trout:BAAALgADCgYJDAABLgAECgYJCgAbAAAAAA==.Trovikk:BAAALgADCgUJBgAAAA==.',
Tu='Turg:BAAALgAECgMJAwABLgAECgQJBwAbAAAAAA==.Turgo:BAAALgAECgEJAQABLgAECgQJBwAbAAAAAA==.Turgress:BAAALgAECgQJBwAAAA==.',
['Tà']='Tàmber:BAAALgADCgYJBwAAAA==.',
Ul='Ulfast:BAABLgAECn8lAAIgAAgJSh5IGgAMAgAgAAgJSh5IGgAMAgAAAA==.',
Va='Valarios:BAAALgAECgYJCgAAAA==.Vannhellsing:BAABLgAECn8nAAIFAAgJJgi/mwAwAQAFAAgJJgi/mwAwAQAAAA==.Vanyel:BAABLgAECn9RAAIGAAkJbBaOOgAsAgAGAAkJbBaOOgAsAgAAAA==.Vaudorka:BAABLgAECn8cAAIEAAkJIx4+AwBmAgAEAAkJIx4+AwBmAgAAAA==.',
Ve='Vecna:BAAALgADCgMJAwABLgAECgYJCAAbAAAAAA==.Veliuz:BAAALgADCgQJBAAAAA==.Velrynth:BAABLgAECn84AAMcAAkJ+BQLEwBGAgAcAAkJVxQLEwBGAgAMAAcJzghySAAXAQAAAA==.Vemal:BAABLgAECn8yAAIKAAkJThlMGgCDAgAKAAkJThlMGgCDAgAAAA==.',
Vo='Vociferoy:BAACLgAFFH8MAAIKAAMJWhoAVAD3AAAKAAMJWhoAVAD3AAAuAAQKf0QAAgoACQl9Ia4OANgCAAoACQl9Ia4OANgCAAAA.Voidsteffan:BAABLgAECn8qAAMdAAgJhhoABQAiAgAdAAgJhhoABQAiAgAeAAQJjw4iwQDXAAAAAA==.',
Vr='Vryadox:BAAALgAFFAIJAgABLgAFFAQJDwAeAGwdAA==.',
Vv='Vv:BAACLgAFFH8/AAIHAAkJByVwAABwAwAHAAkJByVwAABwAwAuAAQKfzUAAgcACQm1JucAANoDAAcACQm1JucAANoDAAAA.',
Vz='Vz:BAAALgADCgUJBQAAAA==.',
Wh='Whoppin:BAAALgAECgIJAgAAAA==.',
Wi='Wiglimparms:BAAALgAECgIJAgAAAA==.',
Wr='Wry:BAAALgAECgMJAwAAAA==.',
Wy='Wysselbow:BAAALgADCggJDQAAAA==.',
['Wá']='Wárranpeace:BAAALgADCgMJAwAAAA==.',
Xa='Xalmo:BAAALgADCgUJBQAAAA==.Xalzi:BAAALgADCggJCQABLgAECgcJFAANAHwVAA==.',
Xi='Xingwong:BAABLgAECn86AAIjAAkJJCXHAQBOAwAjAAkJJCXHAQBOAwAAAA==.',
Za='Zannytoes:BAABLgAECn8mAAMVAAkJpRAmLwC4AQAVAAkJpRAmLwC4AQALAAEJLxE9nAAwAAAAAA==.',
Ze='Zead:BAAALgAECgEJBAAAAA==.Zerana:BAACLgAFFH8NAAIdAAQJmARhCgDwAAAdAAQJmARhCgDwAAAuAAQKfxUAAh0ACQnlCwAOAFgBAB0ACQnlCwAOAFgBAAAA.Zeriea:BAAALgADCgEJAQAAAA==.Zevtra:BAAALgADCgEJAQAAAA==.',
Zi='Zie:BAABLgAECn9PAAIBAAkJwxhGEQBNAgABAAkJwxhGEQBNAgAAAA==.Zikren:BAAALgAECgkJCQAAAA==.',
Zs='Zsinj:BAAALgADCgEJAQAAAA==.',
['Ðo']='Ðonkle:BAABLgAECn8TAAIHAAgJmBwjKwAZAgAHAAgJmBwjKwAZAgAAAA==.',
['Ðr']='Ðrewid:BAAALgADCgEJAQAAAA==.',
['Ñi']='Ñice:BAACLgAFFH8ZAAIRAAYJniMMBwDsAQARAAYJniMMBwDsAQAuAAQKfxoAAhEACQkrHoAYACkCABEACQkrHoAYACkCAAAA.',
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
