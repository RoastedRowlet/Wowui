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

local lookup = {'Priest-Shadow','Paladin-Retribution','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Unholy','Mage-Frost','DemonHunter-Devourer','Monk-Brewmaster','Evoker-Preservation','Hunter-BeastMastery','Monk-Windwalker','Priest-Holy','Shaman-Restoration','DemonHunter-Havoc','DeathKnight-Blood','Warrior-Fury','Warrior-Protection','Hunter-Survival','Hunter-Marksmanship','Monk-Mistweaver','Druid-Balance','Druid-Restoration','Druid-Guardian','Druid-Feral','Warrior-Arms','Paladin-Protection','Unknown-Unknown','Priest-Discipline','Warlock-Destruction','Warlock-Demonology','Paladin-Holy','Shaman-Elemental','Rogue-Assassination','Warlock-Affliction','Rogue-Subtlety','Rogue-Outlaw','DemonHunter-Vengeance',}
local provider = {region='US',realm='Lightninghoof',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abukuma:BAAALgAECgQJBAAAAA==.',
Ad='Adraina:BAAALgADCgEJAQAAAA==.Adrewid:BAAALgADCgQJBAAAAA==.',
Ae='Aelarya:BAABLgAECn8RAAIBAAgJAQYXQgDpAAABAAgJAQYXQgDpAAAAAA==.Aenstalash:BAABLgAECn8hAAICAAgJPyMPIQB5AgACAAgJPyMPIQB5AgAAAA==.Aephium:BAABLgAECn8UAAMDAAcJuwY8WwC8AAADAAYJJgY8WwC8AAAEAAUJtASDGgBvAAAAAA==.Aesilakaersi:BAAALgAECgYJCgAAAA==.Aeson:BAABLgAECn8kAAIFAAkJiBfpPwD8AQAFAAkJiBfpPwD8AQAAAA==.',
Af='Afflictia:BAAALgADCgYJEAAAAA==.',
Ai='Aironel:BAAALgADCgMJAwAAAA==.',
Al='Alanza:BAAALgAECgUJBQAAAA==.Alaure:BAAALgADCgIJAgAAAA==.Alessia:BAAALgAECgIJAgAAAA==.Alfonsoo:BAAALgADCgEJAQAAAA==.Alida:BAAALgAECgQJBAAAAA==.Alistur:BAABLgAECn8fAAIGAAgJighYkABRAQAGAAgJighYkABRAQAAAA==.',
Am='Amanna:BAAALgAECgMJAwABLgAECggJHgAHAGUjAA==.Amoona:BAAALgAECgYJEgABLgAECggJHgAHAGUjAA==.',
An='Anoriia:BAAALgADCgUJBQAAAA==.',
Ar='Arcnid:BAAALgADCgYJBgAAAA==.Arfas:BAAALgADCgQJBAAAAA==.Arthraz:BAABLgAECn8kAAIIAAkJsxxUCwB3AgAIAAkJsxxUCwB3AgAAAA==.',
As='Astara:BAAALgAECgQJBAAAAA==.Astraa:BAAALgAECgIJAgAAAA==.Astrex:BAABLgAECn8xAAMJAAgJTg6UEgCXAQAJAAgJTg6UEgCXAQADAAEJJwH3ngANAAAAAA==.',
Au='Aunaturale:BAAALgAECgkJAwAAAA==.Aureliá:BAABLgAECn8XAAIKAAcJnQrMggAsAQAKAAcJnQrMggAsAQAAAA==.',
['Aü']='Aütobot:BAABLgAECn8iAAILAAkJMw0WJACFAQALAAkJMw0WJACFAQAAAA==.',
Ba='Badgirl:BAACLgAFFH8MAAIMAAQJgREbFgD6AAAMAAQJgREbFgD6AAAuAAQKfxkAAwwACAm+EyIzACwBAAwABgnBFiIzACwBAAEABgktCtBGAOoAAAAA.Balnar:BAABLgAECn8VAAINAAcJoxV9PgCmAQANAAcJoxV9PgCmAQAAAA==.Balraga:BAABLgAECn8ZAAIOAAgJUQpjKAAlAQAOAAgJUQpjKAAlAQAAAA==.Bayded:BAAALgADCgEJAQAAAA==.',
Be='Bega:BAACLgAFFH8fAAMFAAgJ/Rk0DABWAgAFAAcJ/Rk0DABWAgAPAAEJAABXUQAAAAAuAAQKf0EAAwUACQnoJaQEAFUDAAUACQnoJaQEAFUDAA8ABgkrFzslABUBAAAA.Benton:BAAALgAECgQJCAAAAA==.',
Bi='Bigglimpie:BAAALgAECgYJDQAAAA==.',
Bl='Bloodlustplz:BAABLgAECn8qAAMQAAkJshfrKQCpAQAQAAcJLx7rKQCpAQARAAgJLQ8IGgBdAQAAAA==.',
Bo='Bobster:BAABLgAECn8kAAIGAAkJuxF8WwDFAQAGAAkJuxF8WwDFAQAAAA==.Bonepaw:BAAALgAECgMJBAABLgAECgcJFAANAHwVAA==.Booyea:BAABLgAECn89AAIPAAkJ4RteCgBiAgAPAAkJ4RteCgBiAgAAAA==.',
Br='Brew:BAAALgAECgcJBwAAAA==.Brewwnor:BAAALgAECgcJCwAAAA==.Brickdemkeys:BAABLgAECn8fAAIGAAgJPBqrXgC9AQAGAAgJPBqrXgC9AQAAAA==.Brisfloggnaw:BAAALgAFFAEJAQAAAA==.',
Ca='Caladk:BAAALgADCgUJBQABLgAFFAcJIAASAAgfAA==.Calamuelis:BAACLgAFFH8gAAQSAAcJCB+DCAB4AQATAAcJ7hvWBwCeAQASAAUJTyKDCAB4AQAKAAIJ1RsYZwC3AAAuAAQKfx0ABBMACAnSJLsNANcCABMACAmWJLsNANcCABIABAn5JAIvACsBAAoAAQkIJhHoAGoAAAAA.Caliope:BAABLgAECn8WAAIUAAcJWhVyLQCxAQAUAAcJWhVyLQCxAQAAAA==.Capsasin:BAAALgADCgUJBQAAAA==.Carnage:BAAALgAFFAIJAgAAAA==.Cazlek:BAAALgAECgQJCwAAAA==.',
Ce='Celery:BAAALgADCgQJBwABLgAECgkJJAAIALMcAA==.Celldweller:BAAALgAECgYJCgAAAA==.Cerdred:BAABLgAECn8dAAIVAAUJARDLSQAEAQAVAAUJARDLSQAEAQAAAA==.Ceredis:BAAALgAECgEJAQAAAA==.Cerelus:BAABLgAECn8gAAIGAAkJWA9EUQDiAQAGAAkJWA9EUQDiAQAAAA==.',
Ch='Chaac:BAAALgAECgYJCAABLgAECggJFgAJALITAA==.Chmmr:BAAALgADCgMJAwAAAA==.Chowilawu:BAAALgADCgkJCQAAAA==.Chriswilsonn:BAAALgAECgQJCAAAAA==.Chuca:BAAALgAECgYJBgAAAA==.Chucalu:BAABLgAECn8WAAUWAAgJVh4ANwDLAQAWAAYJUyAANwDLAQAXAAQJCx7wEQBVAQAVAAIJih+cVQCrAAAYAAEJLwbeMgA2AAAAAA==.Chéwtoy:BAAALgAECgEJAQAAAA==.',
Cl='Clax:BAAALgAECgIJBQAAAA==.',
Co='Cobeam:BAAALgAECgUJEQAAAA==.Cowpernicus:BAABLgAECn8iAAIWAAkJ7SB/BgBIAwAWAAkJ7SB/BgBIAwABLgAFFAIJCAANAJMdAA==.',
Cr='Crungleman:BAABLgAECn8YAAIKAAcJuRgaWACPAQAKAAcJuRgaWACPAQAAAA==.',
Ct='Cthuwu:BAAALgAECgQJBAABLgAECggJFgAJALITAA==.',
Cu='Curoi:BAABLgAECn8rAAMYAAkJjxfQBwBGAgAYAAkJjxfQBwBGAgAWAAgJRAozeQDsAAAAAA==.',
['Cã']='Cãrloy:BAACLgAFFH8YAAIQAAQJlBvYFwBFAQAQAAQJlBvYFwBFAQAuAAQKf1IAAxAACQlWIrsHANwCABAACQlWIrsHANwCABkAAgl5H2ksAJEAAAAA.',
['Cê']='Cêlestial:BAABLgAECn8eAAMHAAgJZSMBGgBuAgAHAAgJ9SIBGgBuAgAOAAMJkiEYOgC9AAAAAA==.',
Da='Daedalas:BAABLgAECn8XAAMBAAgJnx8HDgBvAgABAAgJnx8HDgBvAgAMAAIJMAI3ZgA9AAAAAA==.Damonk:BAAALgADCgYJBgABLgAECgkJIAARAOIaAA==.Danevolent:BAABLgAECn8gAAMMAAcJ9yJ9DQCAAgAMAAcJ9yJ9DQCAAgABAAQJEA1EXACYAAABLgAECgkJIAARAOIaAA==.Danzaster:BAAALgADCgQJBAAAAA==.Darkxsoul:BAABLgAECn8dAAIaAAgJNRbQDwC5AQAaAAgJNRbQDwC5AQABLgAECgcJFQANAKMVAA==.Darthknull:BAACLgAFFH8SAAICAAQJBRc0MAA/AQACAAQJBRc0MAA/AQAuAAQKfzEAAgIACQkwHskrAEgCAAIACQkwHskrAEgCAAAA.Darthtalon:BAAALgAECgcJCwABLgAFFAQJEgACAAUXAA==.',
De='Deadeyedicky:BAAALgAECgkJBwAAAA==.Deathmachine:BAAALgADCgUJBQAAAA==.Deathniight:BAAALgAECgUJBAAAAA==.Deathseer:BAAALgAECgcJDgAAAA==.Deathwood:BAAALgADCgUJBgABLgAECgEJAQAbAAAAAA==.Deatthdecay:BAAALgAECggJBAAAAA==.Deitrichx:BAABLgAECn8lAAITAAkJnxnPBgAUAgATAAkJnxnPBgAUAgAAAA==.Delley:BAAALgADCgEJAQAAAA==.Deminestrea:BAABLgAECn8ZAAIPAAYJsQ7aKwDwAAAPAAYJsQ7aKwDwAAAAAA==.Devilscreed:BAAALgAECgEJAQAAAA==.',
Di='Dingleberrys:BAAALgADCgEJAQAAAA==.Dippindots:BAAALgAECgYJCAAAAA==.Disshammy:BAAALgAFFAIJAgABLgAFFAgJIgADANEhAA==.Dittoz:BAAALgADCgUJBAAAAA==.',
Do='Dolfcrittler:BAAALgADCgEJAQAAAA==.Donkform:BAAALgAECgkJEgAAAA==.Donniyii:BAAALgAECgcJBwABLgAECgkJOwAcAJQfAA==.Doomrider:BAAALgADCgYJBgAAAA==.Dottzz:BAABLgAECn8aAAIdAAYJ8B27FQCcAQAdAAYJ8B27FQCcAQAAAA==.',
Dr='Draconith:BAACLgAFFH8SAAIJAAUJYw4hFAA5AQAJAAUJYw4hFAA5AQAuAAQKfzUAAgkACQmSG/UEAMcCAAkACQmSG/UEAMcCAAAA.Dramoo:BAAALgAECgMJAwAAAA==.Draqkmar:BAABLgAECn8aAAIKAAYJVQrdmQD+AAAKAAYJVQrdmQD+AAAAAA==.Dreddwing:BAABLgAECn8WAAMJAAgJshMZEADBAQAJAAcJcBUZEADBAQADAAIJJg+rdABsAAAAAA==.Drunkenoodle:BAAALgADCgYJBgAAAA==.',
Du='Dunsparrow:BAACLgAFFH8IAAINAAIJkx0fTgClAAANAAIJkx0fTgClAAAuAAQKf0YAAg0ACQm2IgsFAFkDAA0ACQm2IgsFAFkDAAAA.Durzul:BAAALgAECgEJAQAAAA==.',
Ei='Eightyone:BAAALgAECggJDwAAAA==.Eindraken:BAACLgAFFH8QAAIJAAUJagMrGgDeAAAJAAUJagMrGgDeAAAuAAQKfzgAAgkACQn7EowMAAQCAAkACQn7EowMAAQCAAAA.Eiroh:BAAALgAECggJDAABLgAECggJHgAaAPERAA==.Eisis:BAABLgAECn8+AAIYAAkJVBDGEgB+AQAYAAkJVBDGEgB+AQAAAA==.',
El='Elanalué:BAAALgAECgYJCAABLgAECgcJFgAUAFoVAA==.',
Er='Erixee:BAAALgAECgUJBgAAAA==.Erroz:BAAALgADCgIJAQAAAA==.',
Es='Eshonäi:BAABLgAECn8aAAIeAAYJtRHEiQAiAQAeAAYJtRHEiQAiAQAAAA==.Espriesso:BAABLgAECn8VAAQcAAgJAQ18LwBUAQAcAAcJ3wt8LwBUAQABAAQJvgSeXwCKAAAMAAIJDAecdABWAAABLgAECgkJLAAIALEPAA==.',
Ev='Evodragker:BAABLgAECn8kAAMDAAkJKxREHwDWAQADAAkJKxREHwDWAQAJAAEJcAkzOQA0AAAAAA==.',
Fe='Feider:BAAALgAECgEJAQAAAA==.Felais:BAAALgAFFAIJAgAAAA==.Feldron:BAAALgAECgcJEwAAAA==.Felkaos:BAAALgADCgEJAQAAAA==.Fellura:BAAALgAECgYJDAAAAA==.Femaledawg:BAAALgADCgcJEAAAAA==.',
Fi='Fingor:BAAALgAECgYJBwAAAA==.',
Fl='Flamecube:BAAALgADCgcJCAAAAA==.Flashx:BAABLgAECn8kAAMfAAgJ3iAFCQDwAgAfAAgJ3iAFCQDwAgACAAEJQQzrhAEvAAAAAA==.',
Fo='Foxxeyineawo:BAAALgADCgcJCAAAAA==.',
Fr='Frevmk:BAAALgAECgEJAgAAAA==.Frofrohunter:BAABLgAECn8sAAMKAAkJaB+kEgCiAgAKAAkJaB+kEgCiAgATAAUJAxLZTgAUAQAAAA==.Frofrolock:BAAALgAECgcJDgAAAA==.Froggie:BAABLgAECn8UAAMNAAcJfBXqTABuAQANAAcJfBXqTABuAQAgAAMJXQ/iaACgAAAAAA==.Froshaman:BAAALgAECgEJAQAAAA==.',
Fu='Fuzywuuzy:BAACLgAFFH8NAAIWAAMJ1BRHNwDLAAAWAAMJ1BRHNwDLAAAuAAQKfyUAAxYACAnUIwkLAAQDABYACAnUIwkLAAQDABUABwk6FtQlAJABAAAA.',
Ga='Gazdorn:BAABLgAECn8qAAIRAAkJeRJGEQDHAQARAAkJeRJGEQDHAQAAAA==.',
Ge='Genebelcher:BAAALgAECgEJAQAAAA==.',
Gh='Ghost:BAABLgAECn8hAAIhAAgJdhpWBQAdAgAhAAgJdhpWBQAdAgAAAA==.',
Gi='Gigof:BAABLgAECn8rAAMVAAkJPxJ7IwCgAQAVAAgJ0RJ7IwCgAQAWAAcJ/AqefQC2AAAAAA==.',
Gl='Glissa:BAABLgAECn8UAAQiAAcJdCWRAQDTAgAiAAcJEiWRAQDTAgAeAAMJhSJYogAUAQAdAAIJjxpcRACkAAAAAA==.',
Go='Gobah:BAABLgAECn8YAAMjAAgJ5hX/FwDOAQAjAAgJ5hX/FwDOAQAkAAUJsQfDFQCpAAAAAA==.',
Gt='Gt:BAAALgAECgMJBQAAAA==.',
Gu='Gulldan:BAABLgAECn8hAAIeAAgJtBfiNAAAAgAeAAgJtBfiNAAAAgAAAA==.',
Gw='Gwyndolin:BAAALgADCgUJBQAAAA==.',
Ha='Habanero:BAAALgAECgQJBgABLgAECgkJJAAIALMcAA==.Hadory:BAABLgAECn8UAAMCAAgJqxVRTQDVAQACAAgJqxVRTQDVAQAfAAQJWhn7SAAOAQAAAA==.Harrowhark:BAABLgAECn8/AAQiAAkJvgmcEABGAQAeAAkJ8QjSXQCBAQAiAAgJuwmcEABGAQAdAAQJyQXnLgBXAAAAAA==.',
He='Hellzzdemon:BAABLgAECn8YAAIOAAgJJw2kIwBHAQAOAAgJJw2kIwBHAQAAAA==.Hendricks:BAAALgAECgQJCgAAAA==.Hexinverter:BAAALgAECgQJCAAAAA==.Hexzard:BAAALgADCgQJBAABLgAECgUJEQAbAAAAAA==.Hezekiiah:BAAALgAECgYJCQAAAA==.',
Ho='Holeecow:BAAALgADCgIJAgABLgAFFAIJCAANAJMdAA==.Holycannoli:BAAALgAECggJDgAAAA==.Horiffic:BAAALgAECgcJEwAAAA==.Horok:BAAALgAECgYJDQAAAA==.Hotwheels:BAAALgAECgMJAwAAAA==.',
Hu='Hubert:BAABLgAECn8WAAIUAAgJwQmETwAUAQAUAAgJwQmETwAUAQAAAA==.Hubertdale:BAAALgAECgMJAwAAAA==.Hulkblood:BAAALgAECgEJAQAAAA==.Hummingbrook:BAAALgAECgcJDAABLgAFFAcJFgAHAPMSAA==.',
Ic='Ichaerus:BAAALgAECgQJBQABLgAECggJFwABAJ8fAA==.Ichtheblack:BAAALgAECgcJCQABLgAECggJFwABAJ8fAA==.Ichtu:BAAALgAECgEJAQABLgAECggJFwABAJ8fAA==.',
Ii='Iilli:BAABLgAECn87AAMcAAkJlB/JBgAIAwAcAAkJlB/JBgAIAwABAAkJnxsVDQB7AgAAAA==.',
In='Inari:BAABLgAECn8WAAIBAAgJvwspMgBKAQABAAgJvwspMgBKAQAAAA==.Inkkubus:BAACLgAFFH8bAAQdAAYJeRftDADBAAAeAAMJQh97YwDuAAAdAAMJXArtDADBAAAiAAIJUxZLGwBTAAAuAAQKfxcABB4ACQmPHk44APMBAB4ABwnZH044APMBAB0AAwnpG2oVAPAAACIAAQkAABEnAFUAAAAA.Instagatorz:BAAALgADCgUJBgAAAA==.',
Iq='Iq:BAAALgAECgEJAQAAAA==.',
Iw='Iwkms:BAACLgAFFH8OAAIYAAQJihYzBwApAQAYAAQJihYzBwApAQAuAAQKfyMAAhgACAliIzMCADEDABgACAliIzMCADEDAAEuAAUUBQkGACQAwhYA.',
Ja='Jade:BAABLgAECn8dAAIIAAYJ9CTgFAD/AQAIAAYJ9CTgFAD/AQAAAA==.Jatheo:BAAALgADCgIJAgAAAA==.',
Je='Jenliz:BAAALgADCgEJAQABLgAECgYJEQAbAAAAAA==.Jeronor:BAAALgAECgIJAgAAAA==.',
Ji='Jimmick:BAABLgAECn8WAAINAAcJfyPqDwDGAgANAAcJfyPqDwDGAgABLgAECggJFAACAKsVAA==.Jisung:BAAALgAECgYJEwAAAA==.',
Jo='Jorad:BAAALgADCgEJAQAAAA==.',
Jt='Jtheman:BAAALgAECgQJBAAAAA==.',
Ju='Junebugg:BAAALgADCgEJAQAAAA==.',
Ka='Kaing:BAAALgAECgYJCwAAAA==.Kaissa:BAAALgAECgEJAQAAAA==.Kalena:BAABLgAECn89AAIGAAkJ5w7XWgDHAQAGAAkJ5w7XWgDHAQAAAA==.Kandikkiss:BAAALgAECgUJBgAAAA==.Kaos:BAABLgAECn8jAAIGAAkJ+hEmWADOAQAGAAkJ+hEmWADOAQAAAA==.Kariatyda:BAABLgAECn8uAAIKAAkJMxgIGwBlAgAKAAkJMxgIGwBlAgAAAA==.Kasai:BAAALgADCgMJAwABLgAECgcJIwACAMIYAA==.Kassandra:BAACLgAFFH8IAAIGAAMJ4BeObwD0AAAGAAMJ4BeObwD0AAAuAAQKfz0AAgYACQnvHCYaALcCAAYACQnvHCYaALcCAAAA.Kay:BAAALgAECgcJCQAAAA==.Kayden:BAABLgAECn8aAAIUAAYJhBh2JACQAQAUAAYJhBh2JACQAQABLgAECggJGwAfAFUcAA==.Kayn:BAAALgAECgIJAgAAAA==.',
Ke='Keelistus:BAAALgAECgQJBAAAAA==.Kelisola:BAAALgADCgEJAQAAAA==.Kelzor:BAAALgAECgEJAQAAAA==.Keruu:BAAALgAECgcJBwAAAA==.',
Kh='Khaylorn:BAAALgAECgMJBgAAAA==.',
Ki='Kiloton:BAABLgAECn8iAAIXAAkJuBGuFwCBAQAXAAkJuBGuFwCBAQAAAA==.Kinari:BAAALgAECggJEgAAAA==.Kitzy:BAABLgAECn8iAAIGAAkJ0gSxlABJAQAGAAkJ0gSxlABJAQAAAA==.',
Kl='Klapso:BAAALgADCgYJDQAAAA==.Klippertdk:BAABLgAECn82AAIFAAkJXhiNJwBbAgAFAAkJXhiNJwBbAgAAAA==.Klugamonk:BAAALgADCgUJBQAAAA==.Klutz:BAABLgAECn8qAAIWAAkJXw90NADAAQAWAAkJXw90NADAAQAAAA==.',
Ko='Korgan:BAAALgAECggJDgAAAA==.Korgriku:BAAALgADCgMJAwAAAA==.',
Kr='Kreznor:BAAALgAECgIJAgAAAA==.',
Ku='Kurzo:BAACLgAFFH8JAAIQAAQJhBdmGQA+AQAQAAQJhBdmGQA+AQAuAAQKfzsAAxAACQnrIg4GAPgCABAACQnrIg4GAPgCABEABQmtEussANoAAAAA.',
Ky='Kylarian:BAABLgAECn8iAAIOAAkJyQZHKAAmAQAOAAkJyQZHKAAmAQAAAA==.Kyntara:BAAALgAECgYJDQAAAA==.Kyronian:BAAALgAECgYJDwAAAA==.',
['Kâ']='Kâsâi:BAABLgAECn8jAAICAAcJwhgJWgC0AQACAAcJwhgJWgC0AQAAAA==.',
La='Lachancea:BAAALgAECgEJAQABLgAECggJFAAeADsZAA==.Lakshmee:BAAALgAECgcJDgAAAA==.',
Le='Ledarm:BAAALgAECggJEwAAAA==.Leigin:BAAALgADCgYJBgAAAA==.Lexxi:BAABLgAECn85AAICAAkJYhNNSgDdAQACAAkJYhNNSgDdAQAAAA==.',
Li='Lightbehunt:BAAALgAECgQJBgAAAA==.Lightfivhapy:BAAALgAECgYJCwAAAA==.Lightsglory:BAAALgADCgMJAwAAAA==.Lilly:BAAALgAECgYJCgAAAA==.Livaless:BAAALgADCgQJBAABLgAECgkJJQAeAFAiAA==.',
Lu='Lucialyn:BAAALgAECgcJDAABLgAECgcJFwAcAOojAA==.',
Ly='Lyllith:BAABLgAECn8cAAIhAAYJjREWDABkAQAhAAYJjREWDABkAQAAAA==.Lysende:BAAALgADCgQJBAAAAA==.',
Ma='Madamenoodle:BAAALgADCgkJCQAAAA==.Magnass:BAAALgADCgYJBgABLgAECgkJIAARAOIaAA==.Magnius:BAAALgADCgEJAQAAAA==.Mal:BAAALgAECggJCAAAAA==.Mastablasta:BAAALgAECgQJCQAAAA==.Maursaline:BAABLgAECn8lAAIWAAkJqgccVwAqAQAWAAkJqgccVwAqAQAAAA==.Mawea:BAAALgAECgUJDAAAAA==.Mawks:BAABLgAECn81AAISAAkJqBiRDABXAgASAAkJqBiRDABXAgAAAA==.',
Mc='Mcstukes:BAAALgAECgQJCAAAAA==.',
Me='Medeas:BAAALgAECgUJCgAAAA==.Meragos:BAAALgAECgMJAwAAAA==.Meteor:BAAALgADCgQJBAAAAA==.',
Mi='Migzeviltwin:BAAALgAECgEJAgAAAA==.Mimicz:BAAALgADCgUJBQAAAA==.Minitry:BAAALgAECgEJAQAAAA==.Mixxon:BAAALgAECgYJDwAAAA==.',
Mo='Moinion:BAAALgADCgQJCAAAAA==.Moldbreather:BAAALgAECgEJAQAAAA==.Moomooimacow:BAAALgAECgQJBAAAAA==.Moomoomonkey:BAABLgAECn8fAAIgAAkJMhcNHAD0AQAgAAkJMhcNHAD0AQAAAA==.Morhgana:BAAALgAECgYJDwAAAA==.',
Mx='Mxmlxxix:BAABLgAECn8jAAMMAAgJygEXSAC2AAAMAAgJygEXSAC2AAABAAIJXwHWZQAtAAAAAA==.',
['Mö']='Mördecai:BAAALgAECgQJBAAAAA==.',
Na='Naija:BAAALgAECgEJAgAAAA==.Nati:BAAALgAECgUJBQAAAA==.',
Ne='Nephele:BAAALgAECgEJAQAAAA==.Neptune:BAAALgAECgQJCAAAAA==.',
Ni='Nikorobin:BAAALgAECgQJBwABLgAFFAcJFgAHAPMSAA==.Nilius:BAAALgADCgcJBwABLgAECggJFwABAJ8fAA==.',
No='Noodles:BAAALgADCgkJDAABLgAECgcJDQAbAAAAAA==.Norgalina:BAAALgADCgUJBQAAAA==.',
Ny='Nymara:BAABLgAECn8eAAIaAAgJ8RG8FQBrAQAaAAgJ8RG8FQBrAQAAAA==.',
['Ní']='Níce:BAAALgAECgIJAwAAAA==.',
['Nü']='Nügs:BAAALgAECggJEwAAAA==.Nüguns:BAAALgAECgcJDQAAAA==.',
Ol='Olei:BAAALgADCgUJBQAAAA==.',
Or='Orlick:BAAALgAECgEJAQAAAA==.Orrok:BAAALgADCgYJBwAAAA==.',
Pa='Painlink:BAAALgAECgUJCQABLgAECgkJKQAQAHkRAA==.Painnkiller:BAACLgAFFH8FAAIKAAMJChGUVgDlAAAKAAMJChGUVgDlAAAuAAQKfzcAAgoACQl+HAYaAH0CAAoACQl+HAYaAH0CAAAA.Papyto:BAAALgADCgYJBwAAAA==.Parsley:BAABLgAECn8mAAMiAAgJmSDXAgCKAgAiAAgJmSDXAgCKAgAeAAMJmxlRvQDKAAABLgAECgkJJAAIALMcAA==.Paxis:BAAALgAECgkJDgAAAA==.',
Pe='Perriwinkle:BAABLgAECn9BAAQXAAkJUxx5FwCDAQAYAAkJXBspCwAQAgAXAAgJoRN5FwCDAQAWAAQJPwyUhACmAAAAAA==.Perseus:BAAALgADCgMJAwAAAA==.',
Ph='Phission:BAAALgADCgEJAQAAAA==.Phobya:BAABLgAECn8lAAIWAAgJbRtBGwBiAgAWAAgJbRtBGwBiAgAAAA==.Phylloxeras:BAABLgAECn9KAAIFAAkJoiVnAgB2AwAFAAkJoiVnAgB2AwAAAA==.',
Pl='Pleasure:BAAALgADCgMJAwAAAA==.Pleggashroom:BAAALgADCgEJAQAAAA==.',
Po='Powders:BAABLgAECn80AAIGAAkJ5Ru9KABxAgAGAAkJ5Ru9KABxAgAAAA==.Powderysham:BAAALgAECgcJCwABLgAECgkJNAAGAOUbAA==.',
Pr='Praystatiôn:BAAALgAECgEJAQABLgAECgcJGwAeAHcfAA==.Proshot:BAABLgAECn8xAAISAAkJOCJ8AgAcAwASAAkJOCJ8AgAcAwAAAA==.',
Pu='Puddles:BAAALgAECgEJAQAAAA==.',
Pz='Pzalmo:BAAALgAECgMJAwABLgAECgkJHwAEAJkUAA==.',
Ra='Raccoon:BAABLgAECn89AAMeAAkJmxH3PgDbAQAeAAkJmxH3PgDbAQAiAAEJaAsoOQA2AAAAAA==.Ralor:BAAALgADCgEJAQAAAA==.Ravenhawk:BAAALgAECgYJEAAAAA==.Razza:BAAALgADCgYJCAAAAA==.',
Re='Remember:BAAALgADCgEJAQAAAA==.Renivatio:BAABLgAECn8jAAIFAAgJEhwyLABHAgAFAAgJEhwyLABHAgAAAA==.',
Rh='Rhyntix:BAAALgADCgEJAQAAAA==.',
Ro='Roronoazoro:BAACLgAFFH8WAAIHAAcJ8xLFHwCaAQAHAAcJ8xLFHwCaAQAuAAQKfyEAAwcACQlIH2ojAH0CAAcACQlIH2ojAH0CACUAAglxEwUmAFQAAAAA.',
Ry='Ryrin:BAABLgAECn8jAAMQAAkJBRAQMQCBAQAQAAkJBRAQMQCBAQAZAAIJ9genZgBEAAAAAA==.Ryrìn:BAAALgADCgEJAQAAAA==.Ryrín:BAAALgAECggJEwAAAA==.',
Sa='Samidrac:BAABLgAECn8UAAIJAAYJsgFALgBrAAAJAAYJsgFALgBrAAAAAA==.Sammidormu:BAABLgAECn8jAAQEAAgJ5RPUCQB7AQAEAAcJABXUCQB7AQADAAcJbAtZNgAgAQAJAAEJ2QEPTgAjAAAAAA==.Sanderwoof:BAAALgAECggJCAAAAA==.Sarzul:BAABLgAECn8VAAMdAAYJ/A8VNADnAAAeAAYJ2gzAmwAiAQAdAAUJThEVNADnAAAAAA==.Satoshie:BAAALgAECggJCQAAAA==.',
Sc='Scerevisiae:BAABLgAECn8UAAMeAAgJOxlVegA/AQAeAAUJwBtVegA/AQAdAAQJxBSjLgABAQAAAA==.',
Se='Sedelis:BAABLgAECn8fAAIfAAkJzwqKLwCRAQAfAAkJzwqKLwCRAQAAAA==.Sefirbrena:BAAALgADCgkJAwAAAA==.Selaya:BAAALgAECgEJAQAAAA==.Semnai:BAABLgAECn80AAIWAAkJexZdGgBqAgAWAAkJexZdGgBqAgAAAA==.Serafín:BAABLgAECn83AAIIAAkJYQx1JQB5AQAIAAkJYQx1JQB5AQAAAA==.Sevilicious:BAAALgADCgQJAwAAAA==.',
Sh='Shaay:BAAALgAECgcJDwAAAA==.Shadowlock:BAAALgAECgEJAgAAAA==.Shadowpyro:BAAALgAECgEJAQAAAA==.Shamwig:BAAALgADCgUJBQAAAA==.Shazzam:BAAALgAECggJDwAAAA==.Shieldwall:BAABLgAECn8qAAIRAAgJWg8eGgBcAQARAAgJWg8eGgBcAQAAAA==.',
Si='Silanah:BAAALgAECgEJAQAAAA==.Silverhâwk:BAAALgADCgEJAQAAAA==.Sinastys:BAABLgAECn8aAAICAAgJ9RC6egBtAQACAAgJ9RC6egBtAQAAAA==.',
So='Solone:BAAALgAECgYJDAAAAA==.Sopidia:BAABLgAECn8kAAMNAAgJSRciOgC5AQANAAcJtBYiOgC5AQAgAAUJHQaVbQCPAAAAAA==.Sorvato:BAABLgAECn8zAAIHAAkJCxmjIABGAgAHAAkJCxmjIABGAgAAAA==.',
Sp='Spoonzz:BAABLgAECn8xAAMLAAkJDSTCBAD/AgALAAkJDSTCBAD/AgAIAAIJKx9ZVgCmAAAAAA==.',
St='Stamavan:BAABLgAECn8kAAIXAAkJzCLDAgD8AgAXAAkJzCLDAgD8AgAAAA==.Starflayer:BAABLgAECn8nAAMHAAkJXxzbIwA1AgAHAAkJbhvbIwA1AgAlAAIJYxr3IAB8AAAAAA==.Steb:BAAALgADCgMJAwAAAA==.Sterjariger:BAAALgAECgYJBgABLgAFFAMJBAAbAAAAAA==.',
Su='Sunari:BAAALgAECgMJBAAAAA==.Supermelon:BAABLgAECn8WAAIhAAcJXBGiDABWAQAhAAcJXBGiDABWAQAAAA==.',
Sw='Swenior:BAAALgADCgEJAQAAAA==.',
Sy='Syarli:BAAALgAECgcJBwAAAA==.Sylvaeelor:BAAALgAFFAIJAwABLgAFFAQJDgAZAG4TAA==.Sylvanaria:BAABLgAECn89AAINAAkJWyb6AADHAwANAAkJWyb6AADHAwAAAA==.Sylvanaris:BAAALgAECgYJEQAAAA==.Systyx:BAABLgAECn8bAAIeAAcJdx/JSgC1AQAeAAcJdx/JSgC1AQAAAA==.',
Ta='Takura:BAAALgAECgcJBwABLgAECgkJCwAbAAAAAA==.Talenel:BAAALgAECgQJBAAAAA==.Talyzien:BAAALgADCgYJBwAAAA==.',
Te='Tealan:BAACLgAFFH8HAAMJAAQJugy1GADyAAAJAAQJugy1GADyAAADAAEJRgIIZAAzAAAuAAQKfzAAAwMACQm0GDISAEgCAAMACQm0GDISAEgCAAkACAmpEukcAJ4BAAAA.Tealyn:BAAALgAECgYJBgAAAA==.Teluz:BAAALgAECgQJCgAAAA==.Tendra:BAAALgAECgYJBQAAAA==.Teronreborn:BAABLgAECn8lAAIFAAkJOiWGFAAAAwAFAAkJOiWGFAAAAwAAAA==.',
Th='Thaneer:BAAALgAECgYJBwAAAA==.Thanos:BAABLgAECn8dAAICAAYJ7Q6KpAA3AQACAAYJ7Q6KpAA3AQAAAA==.Thebadmage:BAAALgAECgcJBAAAAA==.Throstmok:BAACLgAFFH8KAAIPAAQJJxBmHQDpAAAPAAQJJxBmHQDpAAAuAAQKfzcAAg8ACQm3HrAIAIECAA8ACQm3HrAIAIECAAAA.Thràll:BAAALgAECgUJBQAAAA==.Thränton:BAAALgAECgEJAQABLgAECgcJFAAlALwhAA==.Thumbalina:BAAALgAECgYJEQAAAA==.',
To='Totemtuggér:BAAALgADCgIJAgAAAA==.',
Tp='Tpaste:BAAALgADCgcJBwAAAA==.',
Tr='Trampstãmp:BAAALgAECgIJAgAAAA==.Trinitea:BAAALgAECgEJAQAAAA==.Trout:BAAALgADCgYJDAABLgAECgYJCgAbAAAAAA==.Trovikk:BAAALgADCgUJBgAAAA==.',
Tu='Turg:BAAALgAECgMJAwABLgAECgQJBwAbAAAAAA==.Turgress:BAAALgAECgQJBwAAAA==.',
['Tà']='Tàmber:BAAALgADCgYJBwAAAA==.',
Ul='Ulfast:BAABLgAECn8lAAIgAAgJSh7lGAAOAgAgAAgJSh7lGAAOAgAAAA==.',
Va='Valarios:BAAALgAECgYJCgAAAA==.Vannhellsing:BAABLgAECn8mAAIFAAgJCwgklAA2AQAFAAgJCwgklAA2AQAAAA==.Vanyel:BAABLgAECn9JAAIGAAkJ3hWUOgAoAgAGAAkJ3hWUOgAoAgAAAA==.Vaudorka:BAABLgAECn8cAAIEAAkJIx4NAwBpAgAEAAkJIx4NAwBpAgAAAA==.',
Ve='Vecna:BAAALgADCgMJAwABLgAECgYJCAAbAAAAAA==.Veliuz:BAAALgADCgQJBAAAAA==.Velrynth:BAABLgAECn83AAMcAAkJ+BQBEgBJAgAcAAkJVxQBEgBJAgAMAAcJzghySAAXAQAAAA==.Vemal:BAABLgAECn8xAAIKAAkJThlAGACJAgAKAAkJThlAGACJAgAAAA==.',
Vo='Vociferoy:BAACLgAFFH8JAAIKAAMJVhkDTgD5AAAKAAMJVhkDTgD5AAAuAAQKf0MAAgoACQl9IWENAN0CAAoACQl9IWENAN0CAAAA.Voidsteffan:BAABLgAECn8iAAMdAAgJKhhmBgDtAQAdAAgJKhhmBgDtAQAeAAQJjw4iwQDXAAAAAA==.',
Vr='Vryadox:BAAALgAFFAIJAgABLgAFFAQJDwAeAGwdAA==.',
Vv='Vv:BAACLgAFFH86AAIHAAkJJCKkAABRAwAHAAkJJCKkAABRAwAuAAQKfzQAAgcACQm1JucAANoDAAcACQm1JucAANoDAAAA.',
Vz='Vz:BAAALgADCgUJBQAAAA==.',
Wh='Whoppin:BAAALgAECgIJAgAAAA==.',
Wi='Wiglimparms:BAAALgAECgIJAgAAAA==.',
Wr='Wry:BAAALgAECgMJAwAAAA==.',
Wy='Wysselbow:BAAALgADCggJDQAAAA==.',
['Wá']='Wárranpeace:BAAALgADCgMJAwAAAA==.',
Xa='Xalmo:BAAALgADCgUJBQAAAA==.Xalzi:BAAALgADCggJCQABLgAECgcJFAANAHwVAA==.',
Xi='Xingwong:BAABLgAECn86AAIjAAkJJCWQAQBSAwAjAAkJJCWQAQBSAwAAAA==.',
Za='Zannytoes:BAABLgAECn8mAAMUAAkJpRCBLAC2AQAUAAkJpRCBLAC2AQALAAEJLxE6lQAwAAAAAA==.',
Ze='Zead:BAAALgAECgEJAwAAAA==.Zerana:BAACLgAFFH8JAAIdAAQJNQQBCgDnAAAdAAQJNQQBCgDnAAAuAAQKfxUAAh0ACQnlCw8NAF0BAB0ACQnlCw8NAF0BAAAA.Zeriea:BAAALgADCgEJAQAAAA==.Zevtra:BAAALgADCgEJAQAAAA==.',
Zi='Zie:BAABLgAECn9IAAIBAAkJehgLEQBIAgABAAkJehgLEQBIAgAAAA==.Zikren:BAAALgAECgkJCQAAAA==.',
Zs='Zsinj:BAAALgADCgEJAQAAAA==.',
['Ðo']='Ðonkle:BAABLgAECn8TAAIHAAgJmByBKQAYAgAHAAgJmByBKQAYAgAAAA==.',
['Ðr']='Ðrewid:BAAALgADCgEJAQAAAA==.',
['Ñi']='Ñice:BAACLgAFFH8ZAAIQAAYJniNKBQD3AQAQAAYJniNKBQD3AQAuAAQKfxoAAhAACQkrHi0XAC8CABAACQkrHi0XAC8CAAAA.',
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
