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

local lookup = {'Priest-Shadow','Paladin-Retribution','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Unholy','Mage-Frost','DemonHunter-Devourer','Monk-Brewmaster','Evoker-Preservation','Hunter-BeastMastery','Monk-Windwalker','Priest-Holy','Paladin-Protection','DemonHunter-Havoc','DeathKnight-Blood','Warrior-Fury','Warrior-Protection','Shaman-Restoration','Hunter-Survival','Hunter-Marksmanship','Druid-Balance','Unknown-Unknown','Druid-Restoration','Druid-Guardian','Druid-Feral','Warrior-Arms','Priest-Discipline','Warlock-Destruction','Warlock-Demonology','Paladin-Holy','Shaman-Elemental','Rogue-Assassination','Warlock-Affliction','Rogue-Subtlety','Rogue-Outlaw','Monk-Mistweaver','DemonHunter-Vengeance',}
local provider = {region='US',realm='Lightninghoof',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abukuma:BAAALgAECgIJAgAAAA==.',
Ad='Adraina:BAAALgADCgEJAQAAAA==.Adrewid:BAAALgADCgQJBAAAAA==.',
Ae='Aelarya:BAABLgAECn8RAAIBAAgJAQYXQgDpAAABAAgJAQYXQgDpAAAAAA==.Aenstalash:BAABLgAECn8cAAICAAgJPyOlHQB1AgACAAgJPyOlHQB1AgAAAA==.Aephium:BAABLgAECn8UAAMDAAcJuwYIUQC/AAADAAYJJgYIUQC/AAAEAAUJtASbFwB0AAAAAA==.Aesilakaersi:BAAALgAECgYJCgAAAA==.Aeson:BAABLgAECn8kAAIFAAkJiBcVNwAAAgAFAAkJiBcVNwAAAgAAAA==.',
Af='Afflictia:BAAALgADCgYJEAAAAA==.',
Ai='Aironel:BAAALgADCgMJAwAAAA==.',
Al='Alaure:BAAALgADCgIJAgAAAA==.Alessia:BAAALgAECgIJAgAAAA==.Alida:BAAALgAECgQJBAAAAA==.Alistur:BAABLgAECn8UAAIGAAgJpQbzkgA3AQAGAAgJpQbzkgA3AQAAAA==.',
Am='Amanna:BAAALgAECgMJAwABLgAECggJHQAHAPUiAA==.Amoona:BAAALgAECgYJEgABLgAECggJHQAHAPUiAA==.',
An='Anoriia:BAAALgADCgUJBQAAAA==.',
Ar='Arfas:BAAALgADCgQJBAAAAA==.Arthraz:BAABLgAECn8kAAIIAAkJsxyICQB+AgAIAAkJsxyICQB+AgAAAA==.',
As='Astraa:BAAALgAECgIJAgAAAA==.Astrex:BAABLgAECn8gAAIJAAYJ8hBHFgBEAQAJAAYJ8hBHFgBEAQAAAA==.',
Au='Aunaturale:BAAALgAECgkJAwAAAA==.Aureliá:BAABLgAECn8XAAIKAAcJnQrDcgAsAQAKAAcJnQrDcgAsAQAAAA==.',
['Aü']='Aütobot:BAABLgAECn8iAAILAAkJMw36HQCVAQALAAkJMw36HQCVAQAAAA==.',
Ba='Badgirl:BAACLgAFFH8HAAIMAAMJowuTGwCuAAAMAAMJowuTGwCuAAAuAAQKfxkAAwwACAm+E0QuADUBAAwABgnBFkQuADUBAAEABgktCq89APAAAAAA.Balnar:BAAALgAECgUJDgABLgAECgcJGwANADkUAA==.Balraga:BAABLgAECn8ZAAIOAAgJUQqQIQAwAQAOAAgJUQqQIQAwAQAAAA==.Bayded:BAAALgADCgEJAQAAAA==.',
Be='Bega:BAACLgAFFH8ZAAMFAAcJJBmYEQDaAQAFAAYJJBmYEQDaAQAPAAEJAAD+QAAAAAAuAAQKf0EAAwUACQnoJRUDAF4DAAUACQnoJRUDAF4DAA8ABgkrFzslABUBAAAA.Benton:BAAALgAECgQJBwAAAA==.',
Bi='Bigglimpie:BAAALgAECgYJDQAAAA==.',
Bl='Bloodlustplz:BAABLgAECn8qAAMQAAkJshcLIwC2AQAQAAcJLx4LIwC2AQARAAgJLQ8QFgBtAQAAAA==.',
Bo='Bobster:BAABLgAECn8kAAIGAAkJuxG0TwDQAQAGAAkJuxG0TwDQAQAAAA==.Bonepaw:BAAALgAECgEJAQABLgAECgcJFAASAHwVAA==.Booyea:BAABLgAECn81AAIPAAkJ/hnXCgA0AgAPAAkJ/hnXCgA0AgAAAA==.',
Br='Brewwnor:BAAALgAECgYJCQAAAA==.Brickdemkeys:BAABLgAECn8fAAIGAAgJPBo1UwDGAQAGAAgJPBo1UwDGAQAAAA==.Brisfloggnaw:BAAALgAFFAEJAQAAAA==.',
Ca='Caladk:BAAALgADCgUJBQABLgAFFAYJGgATANIjAA==.Calamuelis:BAACLgAFFH8aAAQTAAYJ0iMUBQCOAQAUAAYJjSDWBwCeAQATAAUJTyIUBQCOAQAKAAEJYx9ydABKAAAuAAQKfx0ABBQACAnSJLsNANcCABQACAmWJLsNANcCABMABAn5JNkpADABAAoAAQkIJpnLAGsAAAAA.Caliope:BAAALgAECgcJDgAAAA==.Capsasin:BAAALgADCgUJBQAAAA==.Carnage:BAAALgAECgkJBwAAAA==.Cazlek:BAAALgAECgQJCwAAAA==.',
Ce='Celery:BAAALgADCgQJBwABLgAECgkJJAAIALMcAA==.Celldweller:BAAALgAECgYJCgAAAA==.Cerdred:BAABLgAECn8dAAIVAAUJARDLSQAEAQAVAAUJARDLSQAEAQAAAA==.Cerelus:BAABLgAECn8eAAIGAAgJPRDyXQCoAQAGAAgJPRDyXQCoAQAAAA==.',
Ch='Chaac:BAAALgAECgYJBgABLgAECgcJDQAWAAAAAA==.Chmmr:BAAALgADCgMJAwAAAA==.Chowilawu:BAAALgADCgkJCQAAAA==.Chriswilsonn:BAAALgAECgQJCAAAAA==.Chuca:BAAALgAECgYJBgAAAA==.Chucalu:BAABLgAECn8WAAUXAAgJVh4ANwDLAQAXAAYJUyAANwDLAQAYAAQJCx7wEQBVAQAVAAIJih/NSwCsAAAZAAEJLwbeMgA2AAAAAA==.',
Cl='Clax:BAAALgAECgIJBQAAAA==.',
Co='Cobeam:BAAALgAECgQJDAAAAA==.Cowpernicus:BAABLgAECn8hAAIXAAgJdiF0CgD2AgAXAAgJdiF0CgD2AgABLgAECgkJRgASALYiAA==.',
Cr='Crungleman:BAABLgAECn8VAAIKAAYJiRu+PwCwAQAKAAYJiRu+PwCwAQAAAA==.',
Ct='Cthuwu:BAAALgAECgQJBAABLgAECgcJDQAWAAAAAA==.',
Cu='Curoi:BAABLgAECn8nAAMZAAkJwBH9CQDtAQAZAAkJwBH9CQDtAQAXAAgJRAozeQDsAAAAAA==.',
['Cã']='Cãrloy:BAACLgAFFH8QAAIQAAQJjBhNFwAxAQAQAAQJjBhNFwAxAQAuAAQKf0gAAxAACQkWIbEJABMDABAACQkWIbEJABMDABoAAgl5H2ksAJEAAAAA.',
['Cê']='Cêlestial:BAABLgAECn8dAAMHAAgJ9SIoFgB1AgAHAAgJ9SIoFgB1AgAOAAIJfBz5SwBNAAAAAA==.',
Da='Daedalas:BAABLgAECn8WAAMBAAgJnx9TCwB5AgABAAgJnx9TCwB5AgAMAAIJMAKDXABAAAAAAA==.Damonk:BAAALgADCgYJBgABLgAECggJHwARAFgbAA==.Danevolent:BAABLgAECn8gAAMMAAcJ9yJ9DQCAAgAMAAcJ9yJ9DQCAAgABAAQJEA0RUACdAAABLgAECggJHwARAFgbAA==.Danzaster:BAAALgADCgQJBAAAAA==.Darkxsoul:BAABLgAECn8bAAINAAcJORRLFABaAQANAAcJORRLFABaAQAAAA==.Darthknull:BAACLgAFFH8NAAICAAQJEQyTNgAgAQACAAQJEQyTNgAgAQAuAAQKfzAAAgIACQmpHMkqADQCAAIACQmpHMkqADQCAAAA.',
De='Deadeyedicky:BAAALgAECgkJBwAAAA==.Deathmachine:BAAALgADCgUJBQAAAA==.Deathseer:BAAALgAECgcJDgAAAA==.Deathwood:BAAALgADCgUJBQABLgAECgEJAQAWAAAAAA==.Deatthdecay:BAAALgAECggJBAAAAA==.Deitrichx:BAABLgAECn8lAAIUAAkJnxmJBQAjAgAUAAkJnxmJBQAjAgAAAA==.Delley:BAAALgADCgEJAQAAAA==.Deminestrea:BAABLgAECn8VAAIPAAYJsguAKwDMAAAPAAYJsguAKwDMAAAAAA==.Devilscreed:BAAALgAECgEJAQAAAA==.',
Di='Dippindots:BAAALgAECgYJCAAAAA==.Disshammy:BAAALgAFFAIJAgABLgAFFAcJIQADABMjAA==.Dittoz:BAAALgADCgUJBAAAAA==.',
Do='Dolfcrittler:BAAALgADCgEJAQAAAA==.Donkform:BAAALgAECgkJEgAAAA==.Donniyii:BAAALgADCgcJBwABLgAECgkJNwAbAJQfAA==.Doomrider:BAAALgADCgYJBgAAAA==.Dottzz:BAABLgAECn8aAAIcAAYJ8B2JDABIAQAcAAYJ8B2JDABIAQAAAA==.',
Dr='Draconith:BAACLgAFFH8JAAIJAAMJeRAVGQDOAAAJAAMJeRAVGQDOAAAuAAQKfy0AAgkACQnfF2QHAGICAAkACQnfF2QHAGICAAAA.Dramoo:BAAALgAECgMJAwAAAA==.Draqkmar:BAABLgAECn8VAAIKAAYJHgqqjgDvAAAKAAYJHgqqjgDvAAAAAA==.Dreddwing:BAAALgAECgcJDQAAAA==.',
Du='Dunsparrow:BAABLgAECn9GAAISAAkJtiJ4AwBhAwASAAkJtiJ4AwBhAwAAAA==.Durzul:BAAALgAECgEJAQAAAA==.',
Ei='Eightyone:BAAALgAECggJDwAAAA==.Eindraken:BAABLgAECn8wAAIJAAkJiBInCwADAgAJAAkJiBInCwADAgAAAA==.Eisis:BAABLgAECn82AAIZAAkJLBACDwCPAQAZAAkJLBACDwCPAQAAAA==.',
El='Elanalué:BAAALgAECgEJAgABLgAECgcJDgAWAAAAAA==.',
Er='Erixee:BAAALgAECgUJBgAAAA==.Erroz:BAAALgADCgIJAQAAAA==.',
Es='Eshonäi:BAABLgAECn8aAAIdAAYJtREwfQApAQAdAAYJtREwfQApAQAAAA==.Espriesso:BAAALgAECgYJDQABLgAECgkJJAAIANgNAA==.',
Ev='Evodragker:BAABLgAECn8kAAMDAAkJKxRAGwDbAQADAAkJKxRAGwDbAQAJAAEJcAkoNAA0AAAAAA==.',
Fe='Felais:BAAALgAECgEJAgAAAA==.Feldron:BAAALgAECgcJEwAAAA==.Felkaos:BAAALgADCgEJAQAAAA==.Fellura:BAAALgAECgYJDAAAAA==.Femaledawg:BAAALgADCgcJEAAAAA==.',
Fi='Fingor:BAAALgAECgYJBwAAAA==.',
Fl='Flamecube:BAAALgADCgcJCAAAAA==.Flashx:BAABLgAECn8XAAMeAAYJ6CAaGAAgAgAeAAYJ6CAaGAAgAgACAAEJQQy1WgE0AAAAAA==.',
Fo='Foxxeyineawo:BAAALgADCgcJCAAAAA==.',
Fr='Frevmk:BAAALgAECgEJAgAAAA==.Frofrohunter:BAABLgAECn8sAAMKAAkJaB+kEgCiAgAKAAkJaB+kEgCiAgAUAAUJAxLZTgAUAQAAAA==.Frofrolock:BAAALgAECgcJDgAAAA==.Froggie:BAABLgAECn8UAAMSAAcJfBUuQgByAQASAAcJfBUuQgByAQAfAAMJXQ/iaACgAAAAAA==.Froshaman:BAAALgADCgkJCQAAAA==.',
Fu='Fuzywuuzy:BAACLgAFFH8JAAIXAAMJ1BRpLgDYAAAXAAMJ1BRpLgDYAAAuAAQKfx8AAxcACAnUI0gJAAcDABcACAnUI0gJAAcDABUAAwkXE6taAHUAAAAA.',
Ga='Gazdorn:BAABLgAECn8qAAIRAAkJeRIjDgDeAQARAAkJeRIjDgDeAQAAAA==.',
Ge='Genebelcher:BAAALgAECgEJAQAAAA==.',
Gh='Ghost:BAABLgAECn8hAAIgAAgJdhpMBAAqAgAgAAgJdhpMBAAqAgAAAA==.',
Gi='Gigof:BAABLgAECn8rAAMVAAkJPxLFHgCjAQAVAAgJ0RLFHgCjAQAXAAcJ/ApHdAC4AAAAAA==.',
Gl='Glissa:BAABLgAECn8UAAQhAAcJdCWRAQDTAgAhAAcJEiWRAQDTAgAdAAMJhSJYogAUAQAcAAIJjxpcRACkAAAAAA==.',
Go='Gobah:BAABLgAECn8YAAMiAAgJ5hUcFADcAQAiAAgJ5hUcFADcAQAjAAUJsQfhEgCqAAAAAA==.',
Gt='Gt:BAAALgAECgMJBQAAAA==.',
Gu='Gulldan:BAABLgAECn8gAAIdAAgJtBd5LQALAgAdAAgJtBd5LQALAgAAAA==.',
Gw='Gwyndolin:BAAALgADCgUJBQAAAA==.',
Ha='Habanero:BAAALgAECgIJAwABLgAECgkJJAAIALMcAA==.Hadory:BAAALgAECgUJCAABLgAECgcJFgASAH8jAA==.Harrowhark:BAABLgAECn8nAAMhAAgJuwkCDQBVAQAhAAgJuwkCDQBVAQAcAAQJyQWnKABcAAAAAA==.',
He='Hellzzdemon:BAABLgAECn8WAAIOAAcJFg0KJAAcAQAOAAcJFg0KJAAcAQAAAA==.Hendricks:BAAALgAECgQJCgAAAA==.Hexinverter:BAAALgAECgQJBQAAAA==.Hexzard:BAAALgADCgQJBAABLgAECgQJDAAWAAAAAA==.Hezekiiah:BAAALgAECgYJCQAAAA==.',
Ho='Holeecow:BAAALgADCgIJAgABLgAECgkJRgASALYiAA==.Holycannoli:BAAALgAECgcJCwAAAA==.Horiffic:BAAALgAECgcJEgAAAA==.Horok:BAAALgAECgYJDAAAAA==.Hotwheels:BAAALgAECgMJAwAAAA==.',
Hu='Hubert:BAABLgAECn8WAAIkAAgJwQnEPwAWAQAkAAgJwQnEPwAWAQAAAA==.Hubertdale:BAAALgAECgMJAwAAAA==.Hulkblood:BAAALgAECgEJAQAAAA==.Hummingbrook:BAAALgAECgcJDAABLgAFFAYJFAAHAAoVAA==.',
Ic='Ichaerus:BAAALgAECgQJBQABLgAECggJFgABAJ8fAA==.Ichtu:BAAALgAECgEJAQABLgAECggJFgABAJ8fAA==.',
Ii='Iilli:BAABLgAECn83AAMbAAkJlB9eBQASAwAbAAkJlB9eBQASAwABAAgJJBkCFQAAAgAAAA==.',
In='Inari:BAABLgAECn8VAAIBAAcJTAzyMgAmAQABAAcJTAzyMgAmAQAAAA==.Inkkubus:BAACLgAFFH8UAAQcAAUJDx3YDgCVAAAdAAMJQh/vTwD/AAAcAAIJ+g7YDgCVAAAhAAIJww2lGABMAAAuAAQKfxUABBwABwlpHZsSAPIAAB0ABQnFHil6AC8BABwAAwnpG5sSAPIAACEAAQkAABEnAFUAAAAA.Instagatorz:BAAALgADCgUJBgAAAA==.',
Iq='Iq:BAAALgAECgEJAQAAAA==.',
Iw='Iwkms:BAACLgAFFH8OAAIZAAQJihamBABIAQAZAAQJihamBABIAQAuAAQKfyMAAhkACAliIzMCADEDABkACAliIzMCADEDAAEuAAUUBQkGACMAwhYA.',
Ja='Jade:BAABLgAECn8dAAIIAAYJ9CRsEgADAgAIAAYJ9CRsEgADAgAAAA==.Jatheo:BAAALgADCgIJAgAAAA==.',
Je='Jenliz:BAAALgADCgEJAQABLgAECgYJEQAWAAAAAA==.Jeronor:BAAALgAECgIJAgAAAA==.',
Ji='Jimmick:BAABLgAECn8WAAISAAcJfyPkDADIAgASAAcJfyPkDADIAgAAAA==.Jisung:BAAALgAECgYJEQAAAA==.',
Jo='Jorad:BAAALgADCgEJAQAAAA==.',
Jt='Jtheman:BAAALgAECgQJBAAAAA==.',
Ju='Junebugg:BAAALgADCgEJAQAAAA==.',
Ka='Kaing:BAAALgAECgYJCwAAAA==.Kaissa:BAAALgAECgEJAQAAAA==.Kalena:BAABLgAECn81AAIGAAkJpg07VQDAAQAGAAkJpg07VQDAAQAAAA==.Kandikkiss:BAAALgAECgEJAQAAAA==.Kaos:BAABLgAECn8jAAIGAAkJ+hGwTADZAQAGAAkJ+hGwTADZAQAAAA==.Kariatyda:BAABLgAECn8uAAIKAAkJMxgIGwBlAgAKAAkJMxgIGwBlAgAAAA==.Kasai:BAAALgADCgMJAwABLgAECgYJGAACAIsXAA==.Kassandra:BAACLgAFFH8HAAIGAAMJbhUnYAD2AAAGAAMJbhUnYAD2AAAuAAQKfzUAAgYACQneGrAhAHsCAAYACQneGrAhAHsCAAAA.Kay:BAAALgAECgcJCQAAAA==.Kayden:BAABLgAECn8aAAIkAAYJhBh2JACQAQAkAAYJhBh2JACQAQABLgAECggJGQAeAFUcAA==.Kayn:BAAALgAECgIJAgAAAA==.',
Ke='Keelistus:BAAALgAECgQJBAAAAA==.Kelisola:BAAALgADCgEJAQAAAA==.Kelzor:BAAALgAECgEJAQAAAA==.Keruu:BAAALgAECgcJBwAAAA==.',
Kh='Khaylorn:BAAALgAECgMJBgAAAA==.',
Ki='Kiloton:BAABLgAECn8fAAIYAAgJ5xFZFwBWAQAYAAgJ5xFZFwBWAQAAAA==.Kinari:BAAALgAECgYJBgAAAA==.Kitzy:BAABLgAECn8iAAIGAAkJ0gTYhABRAQAGAAkJ0gTYhABRAQAAAA==.',
Kl='Klapso:BAAALgADCgYJDQAAAA==.Klippertdk:BAABLgAECn8oAAIFAAkJUBa0MQAUAgAFAAkJUBa0MQAUAgAAAA==.Klugamonk:BAAALgADCgUJBQAAAA==.Klutz:BAABLgAECn8qAAIXAAkJXw8CLwDFAQAXAAkJXw8CLwDFAQAAAA==.',
Ko='Korgan:BAAALgAECgIJAgAAAA==.Korgriku:BAAALgADCgMJAwAAAA==.',
Kr='Kreznor:BAAALgAECgIJAgAAAA==.',
Ku='Kurzo:BAABLgAECn83AAMQAAkJDCIkBgDjAgAQAAkJDCIkBgDjAgARAAUJrRLrLADaAAAAAA==.',
Ky='Kylarian:BAABLgAECn8iAAIOAAkJyQasIQAwAQAOAAkJyQasIQAwAQAAAA==.Kyntara:BAAALgAECgYJDQAAAA==.Kyronian:BAAALgAECgYJDwAAAA==.',
['Kâ']='Kâsâi:BAABLgAECn8YAAICAAYJixc+dQBjAQACAAYJixc+dQBjAQAAAA==.',
La='Lakshmee:BAAALgAECgcJDgAAAA==.',
Le='Ledarm:BAAALgAECggJEwAAAA==.Leigin:BAAALgADCgYJBgAAAA==.Lexxi:BAABLgAECn8yAAICAAkJlBJJQADnAQACAAkJlBJJQADnAQAAAA==.',
Li='Lightbehunt:BAAALgAECgQJBgAAAA==.Lightfivhapy:BAAALgAECgUJBQAAAA==.Lightsglory:BAAALgADCgMJAwAAAA==.Lilly:BAAALgAECgYJBgAAAA==.Livaless:BAAALgADCgQJBAABLgAECgkJJAAdACwiAA==.',
Lu='Lucialyn:BAAALgAECgcJDAABLgAECgcJFwAbAOojAA==.',
Ly='Lyllith:BAABLgAECn8cAAIgAAYJjREWDABkAQAgAAYJjREWDABkAQAAAA==.Lysende:BAAALgADCgQJBAAAAA==.',
Ma='Madamenoodle:BAAALgADCgkJCQAAAA==.Magnass:BAAALgADCgYJBgABLgAECggJHwARAFgbAA==.Magnius:BAAALgADCgEJAQAAAA==.Mal:BAAALgAECggJCAAAAA==.Mastablasta:BAAALgAECgQJCQAAAA==.Maursaline:BAABLgAECn8lAAIXAAkJqgcTTwAvAQAXAAkJqgcTTwAvAQAAAA==.Mawea:BAAALgAECgUJCAAAAA==.Mawks:BAABLgAECn8eAAITAAgJaBdVCgA3AgATAAgJaBdVCgA3AgAAAA==.',
Mc='Mcstukes:BAAALgAECgQJCAAAAA==.',
Me='Medeas:BAAALgAECgUJCgAAAA==.Meragos:BAAALgAECgMJAwAAAA==.Meteor:BAAALgADCgQJBAAAAA==.',
Mi='Migzeviltwin:BAAALgADCgEJAQAAAA==.Mimicz:BAAALgADCgUJBQAAAA==.Minitry:BAAALgAECgEJAQAAAA==.Mixxon:BAAALgAECgYJDgAAAA==.',
Mo='Moinion:BAAALgADCgQJCAAAAA==.Moldbreather:BAAALgAECgEJAQAAAA==.Moomooimacow:BAAALgAECgQJBAAAAA==.Moomoomonkey:BAABLgAECn8fAAIfAAkJMhe4FwD7AQAfAAkJMhe4FwD7AQAAAA==.Morhgana:BAAALgAECgYJDwAAAA==.',
Mx='Mxmlxxix:BAABLgAECn8jAAMMAAgJygEsQADHAAAMAAgJygEsQADHAAABAAIJXwHWZQAtAAAAAA==.',
['Mö']='Mördecai:BAAALgAECgQJBAAAAA==.',
Na='Naija:BAAALgAECgEJAgAAAA==.Nati:BAAALgAECgUJBQAAAA==.',
Ne='Nephele:BAAALgAECgEJAQAAAA==.Neptune:BAAALgAECgQJCAAAAA==.',
Ni='Nikorobin:BAAALgAECgQJBwABLgAFFAYJFAAHAAoVAA==.Nilius:BAAALgADCgcJBwABLgAECggJFgABAJ8fAA==.',
No='Noodles:BAAALgADCgkJDAABLgAECgcJHQAHAL4WAA==.Norgalina:BAAALgADCgUJBQAAAA==.',
Ny='Nymara:BAABLgAECn8eAAINAAgJ8RFyEgBzAQANAAgJ8RFyEgBzAQAAAA==.',
['Ní']='Níce:BAAALgAECgIJAwAAAA==.',
['Nü']='Nügs:BAAALgAECggJEwAAAA==.',
Ol='Olei:BAAALgADCgUJBQAAAA==.',
Or='Orlick:BAAALgAECgEJAQAAAA==.Orrok:BAAALgADCgYJBwAAAA==.',
Pa='Painlink:BAAALgAECgUJCQABLgAECgkJJQAQAMEQAA==.Painnkiller:BAABLgAECn8yAAIKAAkJfhxSFgB5AgAKAAkJfhxSFgB5AgAAAA==.Papyto:BAAALgADCgYJBwAAAA==.Parsley:BAABLgAECn8XAAMhAAYJxh5ICQCbAQAhAAYJxh5ICQCbAQAdAAMJmxl8rADSAAABLgAECgkJJAAIALMcAA==.Paxis:BAAALgAECgkJDgAAAA==.',
Pe='Perriwinkle:BAABLgAECn8xAAQZAAgJNhopCwAQAgAZAAgJ0xcpCwAQAgAYAAgJuRK9FAByAQAXAAQJPwwmewCnAAAAAA==.Perseus:BAAALgADCgMJAwAAAA==.',
Ph='Phission:BAAALgADCgEJAQAAAA==.Phobya:BAABLgAECn8ZAAIXAAgJwhmMHQA2AgAXAAgJwhmMHQA2AgAAAA==.Phylloxeras:BAABLgAECn84AAIFAAkJUyRYBQA6AwAFAAkJUyRYBQA6AwAAAA==.',
Pl='Pleasure:BAAALgADCgMJAwAAAA==.Pleggashroom:BAAALgADCgEJAQAAAA==.',
Po='Powders:BAABLgAECn80AAIGAAkJ5RvvIQB6AgAGAAkJ5RvvIQB6AgAAAA==.Powderysham:BAAALgAECgcJCgABLgAECgkJNAAGAOUbAA==.',
Pr='Praystatiôn:BAAALgAECgEJAQABLgAECgcJGwAdAHcfAA==.Proshot:BAABLgAECn8rAAITAAkJFyH4AgD6AgATAAkJFyH4AgD6AgAAAA==.',
Pu='Puddles:BAAALgAECgEJAQAAAA==.',
Pz='Pzalmo:BAAALgAECgMJAwABLgAECgkJHwAEAJkUAA==.',
Ra='Raccoon:BAABLgAECn81AAIdAAkJkA1+RQCzAQAdAAkJkA1+RQCzAQAAAA==.Ravenhawk:BAAALgAECgYJDwAAAA==.Razza:BAAALgADCgYJCAAAAA==.',
Re='Remember:BAAALgADCgEJAQAAAA==.Renivatio:BAABLgAECn8XAAIFAAgJYRnnLAAoAgAFAAgJYRnnLAAoAgAAAA==.',
Rh='Rhyntix:BAAALgADCgEJAQAAAA==.',
Ro='Roronoazoro:BAACLgAFFH8UAAIHAAYJChVuIABnAQAHAAYJChVuIABnAQAuAAQKfyEAAwcACQlIH2ojAH0CAAcACQlIH2ojAH0CACUAAglxEwUmAFQAAAAA.',
Ry='Ryrin:BAABLgAECn8iAAMQAAkJBRAwKgCJAQAQAAkJBRAwKgCJAQAaAAIJtgbtVQBGAAAAAA==.Ryrín:BAAALgAECgYJCgAAAA==.',
Sa='Samidrac:BAAALgAECgYJEgAAAA==.Sammidormu:BAABLgAECn8jAAQEAAgJ5ROOCACDAQAEAAcJABWOCACDAQADAAcJbAtZNgAgAQAJAAEJ2QEPTgAjAAAAAA==.Sanderwoof:BAAALgAECggJCAAAAA==.Sarzul:BAABLgAECn8VAAMcAAYJ/A8VNADnAAAdAAYJ2gzAmwAiAQAcAAUJThEVNADnAAAAAA==.Satoshie:BAAALgAECggJCQAAAA==.',
Sc='Scerevisiae:BAAALgAECgcJEgAAAA==.',
Se='Sedelis:BAABLgAECn8fAAIeAAkJzwpQKgCVAQAeAAkJzwpQKgCVAQAAAA==.Sefirbrena:BAAALgADCgkJAwAAAA==.Selaya:BAAALgAECgEJAQAAAA==.Semnai:BAABLgAECn8qAAIXAAgJhxXEJQD9AQAXAAgJhxXEJQD9AQAAAA==.Serafín:BAABLgAECn8vAAIIAAkJNQvAIwBuAQAIAAkJNQvAIwBuAQAAAA==.Sevilicious:BAAALgADCgQJAwAAAA==.',
Sh='Shaay:BAAALgAECgYJDgAAAA==.Shadowlock:BAAALgAECgEJAgAAAA==.Shadowpyro:BAAALgAECgEJAQAAAA==.Shamwig:BAAALgADCgUJBQAAAA==.Shazzam:BAAALgAECgYJDwAAAA==.Shieldwall:BAABLgAECn8iAAIRAAgJughXIAAGAQARAAgJughXIAAGAQAAAA==.',
Si='Silanah:BAAALgAECgEJAQAAAA==.Silverhâwk:BAAALgADCgEJAQAAAA==.Sinastys:BAABLgAECn8aAAICAAgJ9RBxZgCDAQACAAgJ9RBxZgCDAQAAAA==.',
So='Solone:BAAALgAECgYJBgAAAA==.Sopidia:BAABLgAECn8kAAMSAAgJSRf8MQC8AQASAAcJtBb8MQC8AQAfAAUJHQbqXwCSAAAAAA==.Sorvato:BAABLgAECn8pAAIHAAgJtBexLwDoAQAHAAgJtBexLwDoAQAAAA==.',
Sp='Spoonzz:BAABLgAECn8xAAMLAAkJDSSEAwANAwALAAkJDSSEAwANAwAIAAIJKx9ATwCoAAAAAA==.',
St='Stamavan:BAABLgAECn8kAAIYAAkJzCIHAgACAwAYAAkJzCIHAgACAwAAAA==.Starflayer:BAABLgAECn8nAAMHAAkJXxxIHwA8AgAHAAkJbhtIHwA8AgAlAAIJYxr3IAB8AAAAAA==.Sterjariger:BAAALgAECgYJBgABLgAFFAEJAQAWAAAAAA==.',
Su='Sunari:BAAALgAECgMJBAAAAA==.Supermelon:BAABLgAECn8WAAIgAAcJXBH7CgBjAQAgAAcJXBH7CgBjAQAAAA==.',
Sw='Swenior:BAAALgADCgEJAQAAAA==.',
Sy='Sylvaeelor:BAAALgAECgcJCgABLgAFFAQJDgAaAG4TAA==.Sylvanaria:BAABLgAECn81AAISAAkJWyaQAADMAwASAAkJWyaQAADMAwAAAA==.Sylvanaris:BAAALgAECgYJEQAAAA==.Systyx:BAABLgAECn8bAAIdAAcJdx/pQQC+AQAdAAcJdx/pQQC+AQAAAA==.',
Ta='Takura:BAAALgAECgcJBwABLgAECgkJCwAWAAAAAA==.Talenel:BAAALgAECgQJBAAAAA==.Talyzien:BAAALgADCgYJBwAAAA==.',
Te='Tealan:BAABLgAECn8wAAMDAAkJtBi3DwBNAgADAAkJtBi3DwBNAgAJAAgJqRLpHACeAQAAAA==.Tealyn:BAAALgAECgIJAQAAAA==.Teluz:BAAALgAECgQJCgAAAA==.Tendra:BAAALgAECgYJBQAAAA==.Teronreborn:BAABLgAECn8lAAIFAAkJOiWGFAAAAwAFAAkJOiWGFAAAAwAAAA==.',
Th='Thaneer:BAAALgAECgYJBwAAAA==.Thanos:BAABLgAECn8dAAICAAYJ7Q6KpAA3AQACAAYJ7Q6KpAA3AQAAAA==.Thebadmage:BAAALgAECgcJBAAAAA==.Throstmok:BAABLgAECn83AAIPAAkJtx7JBgCOAgAPAAkJtx7JBgCOAgAAAA==.Thràll:BAAALgAECgUJBQAAAA==.Thränton:BAAALgAECgEJAQABLgAECgcJFAAlALwhAA==.Thumbalina:BAAALgAECgYJEQAAAA==.',
To='Totemtuggér:BAAALgADCgIJAgAAAA==.',
Tp='Tpaste:BAAALgADCgcJBwAAAA==.',
Tr='Trampstãmp:BAAALgAECgIJAgAAAA==.Trout:BAAALgADCgYJDAABLgAECgYJCgAWAAAAAA==.Trovikk:BAAALgADCgUJBgAAAA==.',
Tu='Turg:BAAALgAECgMJAwABLgAECgQJBwAWAAAAAA==.Turgress:BAAALgAECgQJBwAAAA==.',
['Tà']='Tàmber:BAAALgADCgYJBwAAAA==.',
Ul='Ulfast:BAABLgAECn8kAAIfAAgJAB6oFgAFAgAfAAgJAB6oFgAFAgAAAA==.',
Va='Valarios:BAAALgAECgYJCgAAAA==.Vannhellsing:BAABLgAECn8mAAIFAAgJCwjXggA4AQAFAAgJCwjXggA4AQAAAA==.Vanyel:BAABLgAECn9AAAIGAAkJfxRlPAANAgAGAAkJfxRlPAANAgAAAA==.Vaudorka:BAABLgAECn8cAAIEAAkJIx5vAgB6AgAEAAkJIx5vAgB6AgAAAA==.',
Ve='Vecna:BAAALgADCgMJAwABLgAECgYJCAAWAAAAAA==.Veliuz:BAAALgADCgQJBAAAAA==.Velrynth:BAABLgAECn8vAAMbAAkJtBK6EQAtAgAbAAkJhxG6EQAtAgAMAAcJzghySAAXAQAAAA==.Vemal:BAABLgAECn8sAAIKAAkJ1RaZHQBKAgAKAAkJ1RaZHQBKAgAAAA==.',
Vo='Vociferoy:BAABLgAECn87AAIKAAkJfSEECwDZAgAKAAkJfSEECwDZAgAAAA==.Voidsteffan:BAABLgAECn8ZAAMcAAYJthgECwBjAQAcAAYJthgECwBjAQAdAAQJjw4iwQDXAAAAAA==.',
Vr='Vryadox:BAAALgAFFAIJAgABLgAFFAQJDAAdAIYZAA==.',
Vv='Vv:BAACLgAFFH8zAAIHAAgJwiScAAATAwAHAAgJwiScAAATAwAuAAQKfzAAAgcACQm1JucAANoDAAcACQm1JucAANoDAAAA.',
Vz='Vz:BAAALgADCgUJBQAAAA==.',
Wh='Whoppin:BAAALgAECgIJAgAAAA==.',
Wi='Wiglimparms:BAAALgAECgIJAgAAAA==.',
Wr='Wry:BAAALgAECgMJAwAAAA==.',
Wy='Wysselbow:BAAALgADCggJDQAAAA==.',
Xa='Xalmo:BAAALgADCgUJBQAAAA==.Xalzi:BAAALgADCggJCQABLgAECgcJFAASAHwVAA==.',
Xi='Xingwong:BAABLgAECn82AAIiAAgJnCVhAwD3AgAiAAgJnCVhAwD3AgAAAA==.',
Za='Zannytoes:BAABLgAECn8mAAMkAAkJpRAcJAC4AQAkAAkJpRAcJAC4AQALAAEJLxESgQAyAAAAAA==.',
Ze='Zead:BAAALgAECgEJAwAAAA==.Zerana:BAABLgAECn8VAAIcAAkJ5Qu2CgBoAQAcAAkJ5Qu2CgBoAQAAAA==.Zeriea:BAAALgADCgEJAQAAAA==.Zevtra:BAAALgADCgEJAQAAAA==.',
Zi='Zie:BAABLgAECn8/AAIBAAkJ9RbhEQAhAgABAAkJ9RbhEQAhAgAAAA==.Zikren:BAAALgAECgkJCQAAAA==.',
Zs='Zsinj:BAAALgADCgEJAQAAAA==.',
['Ðo']='Ðonkle:BAABLgAECn8TAAIHAAgJmBz0IwAiAgAHAAgJmBz0IwAiAgAAAA==.',
['Ðr']='Ðrewid:BAAALgADCgEJAQAAAA==.',
['Ñi']='Ñice:BAACLgAFFH8TAAIQAAUJwCP5BgCdAQAQAAUJwCP5BgCdAQAuAAQKfxgAAhAACQkrHn8UACgCABAACQkrHn8UACgCAAAA.',
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
