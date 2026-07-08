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

local lookup = {'Priest-Shadow','Paladin-Retribution','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Unholy','Mage-Frost','DemonHunter-Havoc','Warrior-Fury','Monk-Brewmaster','Warlock-Affliction','Evoker-Preservation','Hunter-BeastMastery','Monk-Windwalker','Priest-Holy','Shaman-Restoration','Paladin-Protection','DeathKnight-Blood','Warrior-Protection','Hunter-Marksmanship','Hunter-Survival','Monk-Mistweaver','Druid-Balance','Druid-Restoration','Druid-Guardian','Druid-Feral','Warrior-Arms','DemonHunter-Devourer','Unknown-Unknown','Priest-Discipline','Warlock-Destruction','Rogue-Subtlety','Warlock-Demonology','Paladin-Holy','Shaman-Elemental','Rogue-Assassination','Rogue-Outlaw','Shaman-Enhancement','DemonHunter-Vengeance',}
local provider = {region='US',realm='Lightninghoof',name='US',type='weekly',zone=46,date='2026-07-05',data={Ab='Abukuma:BAAALgAECgQJBAAAAA==.',
Ac='Aceieus:BAAALgAECgkJAwAAAA==.',
Ad='Adraina:BAAALgADCgEJAQAAAA==.Adrewid:BAAALgADCgQJBAAAAA==.',
Ae='Aelarya:BAABLgAECn8RAAIBAAgJAQYXQgDpAAABAAgJAQYXQgDpAAAAAA==.Aenstalash:BAACLgAFFH8FAAICAAMJURhUHQDhAAACAAMJURhUHQDhAAAuAAQKfyEAAgIACAk/I0ckAHQCAAIACAk/I0ckAHQCAAAA.Aephium:BAABLgAECn8VAAMDAAcJuwZkYQC2AAADAAYJJgZkYQC2AAAEAAUJtAQVHABsAAAAAA==.Aesilakaersi:BAAALgAECgYJCgAAAA==.Aeson:BAABLgAECn8kAAIFAAkJiBeVRQDyAQAFAAkJiBeVRQDyAQAAAA==.',
Af='Afflictia:BAAALgADCgYJEAAAAA==.',
Ai='Aironel:BAAALgADCgMJAwAAAA==.',
Al='Alanza:BAAALgAFFAIJAgAAAA==.Alaure:BAAALgADCgIJAgAAAA==.Alessia:BAAALgAECgIJAgAAAA==.Alfonsoo:BAAALgADCgEJAQAAAA==.Alida:BAAALgAECgQJBAAAAA==.Alistur:BAABLgAECn8mAAIGAAgJygvlDwD9AAAGAAgJygvlDwD9AAAAAA==.',
Am='Amanna:BAAALgAECgMJAwABLgAECgkJOQAHADsmAA==.Amoona:BAAALgAECgYJEgABLgAECgkJOQAHADsmAA==.',
An='Anaila:BAAALgAECgMJAwABLgAFFAQJDQAIAAsfAA==.Anoriia:BAAALgADCgUJBQAAAA==.',
Ar='Arcnid:BAAALgADCgYJBgAAAA==.Arfas:BAAALgADCgQJBAAAAA==.Arthraz:BAABLgAECn8kAAIJAAkJsxwHDAB1AgAJAAkJsxwHDAB1AgABLgAECgkJKgAKAAAiAA==.',
As='Astara:BAAALgAECgQJBAAAAA==.Astraa:BAAALgAECgIJAgAAAA==.Astrex:BAABLgAECn9VAAQLAAkJdBhjAAB3AgALAAkJdBhjAAB3AgADAAcJKwOuCQCNAAAEAAIJvAUhBQA3AAAAAA==.',
Au='Aunaturale:BAAALgAECgkJAwAAAA==.Aurali:BAAALgAECgEJAQAAAA==.Aureliá:BAABLgAECn8ZAAIMAAcJvArCjAAlAQAMAAcJvArCjAAlAQAAAA==.',
['Aü']='Aütobot:BAABLgAECn8iAAINAAkJMw20JgCAAQANAAkJMw20JgCAAQAAAA==.',
Ba='Badgirl:BAACLgAFFH8MAAIOAAQJgREoGQDyAAAOAAQJgREoGQDyAAAuAAQKfxkAAw4ACAm+E9w1ACoBAA4ABgnBFtw1ACoBAAEABgktCuFLAOAAAAAA.Balnar:BAABLgAECn8gAAIPAAcJEBdXBwBHAQAPAAcJEBdXBwBHAQABLgAECggJIAAQANsWAA==.Balraga:BAABLgAECn8ZAAIHAAgJUQrjKwAhAQAHAAgJUQrjKwAhAQAAAA==.Bargrivyek:BAAALgAECgYJCQAAAA==.Bayded:BAAALgADCgEJAQAAAA==.',
Be='Beastboyy:BAAALgAECgUJBQAAAA==.Bega:BAACLgAFFH8uAAMFAAgJ9hpNDQB0AgAFAAgJ9hpNDQB0AgARAAEJAABPUwAAAAAuAAQKf0EAAwUACQnoJXoFAE8DAAUACQnoJXoFAE8DABEABgkrFzslABUBAAAA.Benton:BAAALgAECgQJCAAAAA==.',
Bi='Bigglimpie:BAAALgAECgYJDQAAAA==.',
Bl='Bloodlustplz:BAABLgAECn8qAAMIAAkJshdCLACjAQAIAAcJLx5CLACjAQASAAgJLQ/NGwBYAQAAAA==.',
Bo='Bobster:BAABLgAECn8kAAIGAAkJuxHlYQC7AQAGAAkJuxHlYQC7AQAAAA==.Bonepaw:BAAALgAECgMJBQABLgAECgcJFAAPAHwVAA==.Booyea:BAACLgAFFH8LAAIRAAMJAReHDQC+AAARAAMJAReHDQC+AAAuAAQKfz4AAhEACQklHBMLAF8CABEACQklHBMLAF8CAAAA.',
Br='Brew:BAAALgAECgcJCwAAAA==.Brewwnor:BAAALgAECgkJEAAAAA==.Brickdemkeys:BAABLgAECn8fAAIGAAgJPBr/YwC2AQAGAAgJPBr/YwC2AQAAAA==.Brisfloggnaw:BAAALgAFFAEJAQAAAA==.',
Ca='Caladk:BAAALgADCgUJBQABLgAFFAgJIwATAFMeAA==.Calamuelis:BAACLgAFFH8jAAQTAAgJUx7WBwCeAQATAAcJ7hvWBwCeAQAUAAYJHSHyCgBvAQAMAAIJehzYPABrAAAuAAQKfx0ABBMACAnSJLsNANcCABMACAmWJLsNANcCABQABAn5JIowACYBAAwAAQkIJhv2AGkAAAAA.Caliope:BAABLgAECn8pAAMVAAkJcxWfJQD3AQAVAAkJcxWfJQD3AQANAAQJwwoxBwC4AAAAAA==.Capsasin:BAAALgADCgUJBQAAAA==.Carnage:BAAALgAFFAIJAgAAAA==.Cazlek:BAAALgAECgQJCwAAAA==.',
Ce='Celery:BAAALgAECgQJBAABLgAECgkJKgAKAAAiAA==.Celldweller:BAAALgAECgYJCgAAAA==.Cerdred:BAABLgAECn8dAAIWAAUJARDLSQAEAQAWAAUJARDLSQAEAQAAAA==.Ceredis:BAAALgAECgEJAQAAAA==.Cerelus:BAABLgAECn8gAAIGAAkJWA9oVQDdAQAGAAkJWA9oVQDdAQAAAA==.',
Ch='Chaac:BAAALgAECggJEAABLgAECggJFgALALITAA==.Chmmr:BAAALgADCgMJAwAAAA==.Chowilawu:BAAALgADCgkJCQAAAA==.Chriswilsonn:BAAALgAECgQJCAAAAA==.Chuca:BAAALgAECgYJBgAAAA==.Chucalu:BAABLgAECn8WAAUXAAgJVh4ANwDLAQAXAAYJUyAANwDLAQAYAAQJCx7wEQBVAQAWAAIJih8+WgCqAAAZAAEJLwbeMgA2AAAAAA==.Chéwtoy:BAAALgAECgIJBAAAAA==.',
Cl='Clax:BAAALgAECgIJBQAAAA==.',
Co='Cobeam:BAAALgAECgYJEwAAAA==.Cowpernicus:BAABLgAECn8iAAIXAAkJ7SAJBwBHAwAXAAkJ7SAJBwBHAwABLgAFFAQJEAAPAKIWAA==.',
Cr='Crungleman:BAABLgAECn8YAAIMAAcJuRi1XwCIAQAMAAcJuRi1XwCIAQAAAA==.',
Ct='Cthuwu:BAAALgAECgQJBAABLgAECggJFgALALITAA==.',
Cu='Curoi:BAABLgAECn8rAAMZAAkJjxeECABEAgAZAAkJjxeECABEAgAXAAgJRAozeQDsAAAAAA==.',
['Cã']='Cãrloy:BAACLgAFFH8hAAIIAAQJlBv2GwBBAQAIAAQJlBv2GwBBAQAuAAQKf1sAAwgACQlWIhwHAOwCAAgACQlWIhwHAOwCABoAAgkpIexEALUAAAAA.',
['Cê']='Cêlestial:BAABLgAECn85AAMHAAkJOyYaAACLAwAHAAkJMCYaAACLAwAbAAgJ9SLmGwBtAgAAAA==.',
Da='Daedalas:BAABLgAECn8cAAMBAAkJJh/uDgBqAgABAAkJJh/uDgBqAgAOAAIJMAKAawA8AAAAAA==.Daedtoo:BAAALgAECgUJBQABLgAECgkJHAABACYfAA==.Damonk:BAAALgADCgYJBgABLgAECgkJIAASAOIaAA==.Danevolent:BAABLgAECn8gAAMOAAcJ9yJ9DQCAAgAOAAcJ9yJ9DQCAAgABAAQJEA0/YACYAAABLgAECgkJIAASAOIaAA==.Danzaster:BAAALgADCgQJBAAAAA==.Darkxsoul:BAABLgAECn8gAAIQAAgJ2xbBEAC4AQAQAAgJ2xbBEAC4AQAAAA==.Darthknull:BAACLgAFFH8SAAICAAQJBRe8OAA7AQACAAQJBRe8OAA7AQAuAAQKfzwAAgIACQnQIXAYALECAAIACQnQIXAYALECAAAA.Darthtalon:BAAALgAECgkJDgABLgAFFAQJEgACAAUXAA==.',
De='Deadeyedicky:BAAALgAECgkJBwAAAA==.Deathmachine:BAAALgADCgUJBQAAAA==.Deathniight:BAAALgAECgUJBAAAAA==.Deathseer:BAAALgAECgcJDgAAAA==.Deathwood:BAAALgADCgUJBgABLgAECgEJAQAcAAAAAA==.Deatthdecay:BAAALgAECggJBAAAAA==.Deitrichx:BAABLgAECn8pAAITAAkJnxmVBgApAgATAAkJnxmVBgApAgAAAA==.Delley:BAAALgADCgEJAQAAAA==.Deminestra:BAAALgAECgQJBAAAAA==.Deminestrea:BAABLgAECn8aAAIRAAYJchCgKgADAQARAAYJchCgKgADAQAAAA==.Demonswhere:BAAALgADCgQJBAAAAA==.Devilscreed:BAAALgAECgEJAQAAAA==.',
Di='Dingleberrys:BAAALgADCgEJAQAAAA==.Dippindots:BAAALgAECgYJCAAAAA==.Disshammy:BAAALgAFFAIJAgABLgAFFAgJIgADANEhAA==.Dittoz:BAAALgADCgUJBAAAAA==.',
Do='Dolfcritler:BAAALgAECgQJBQAAAA==.Dolfcrittler:BAAALgADCgEJAQAAAA==.Donkform:BAAALgAECgkJEgAAAA==.Donniyii:BAAALgAECgcJBwABLgAECgkJOwAdAJQfAA==.Doomrider:BAAALgADCgYJBgAAAA==.Dottzz:BAABLgAECn8aAAIeAAYJ8B27FQCcAQAeAAYJ8B27FQCcAQAAAA==.',
Dr='Draconith:BAACLgAFFH8cAAILAAUJChIICADbAAALAAUJChIICADbAAAuAAQKfzcAAgsACQmSG00FAMMCAAsACQmSG00FAMMCAAAA.Dramoo:BAAALgAECgMJAwAAAA==.Draqkmar:BAABLgAECn8fAAIMAAYJTwvCHQCKAAAMAAYJTwvCHQCKAAAAAA==.Dreddwing:BAABLgAECn8WAAMLAAgJshOaEADCAQALAAcJcBWaEADCAQADAAIJJg8iewBrAAAAAA==.Dredfox:BAAALgAECgIJAgABLgAECgkJRwAWAPURAA==.Drunkenoodle:BAAALgADCgYJBgAAAA==.',
Du='Dunsparrow:BAACLgAFFH8QAAIPAAQJohaFHwCeAAAPAAQJohaFHwCeAAAuAAQKf0cAAg8ACQnfIkgFAF8DAA8ACQnfIkgFAF8DAAAA.Durzul:BAAALgAECgEJAQAAAA==.',
Ei='Eightyone:BAAALgAECggJDwAAAA==.Eindraken:BAACLgAFFH8ZAAILAAUJLAneCgCeAAALAAUJLAneCgCeAAAuAAQKfzkAAgsACQn7EjENAP4BAAsACQn7EjENAP4BAAAA.Eiroh:BAABLgAECn8YAAIJAAkJghz9AAALAgAJAAkJghz9AAALAgAAAA==.Eisis:BAACLgAFFH8HAAIZAAMJhgvZBAC2AAAZAAMJhgvZBAC2AAAuAAQKfz8AAhkACQlUEJUUAHoBABkACQlUEJUUAHoBAAAA.',
El='Elanalué:BAABLgAECn8VAAIBAAYJ/Q3HCgCjAAABAAYJ/Q3HCgCjAAABLgAECgkJKQAVAHMVAA==.',
En='Enamel:BAAALgAECgMJAwABLgAFFAMJCQAfAM4RAA==.',
Er='Erixee:BAAALgAECgUJBgAAAA==.Erroz:BAAALgADCgIJAQAAAA==.',
Es='Eshonäi:BAABLgAECn8aAAIgAAYJtRHRjgAdAQAgAAYJtRHRjgAdAQAAAA==.Espriesso:BAABLgAECn8VAAQdAAgJAQ1uMwBKAQAdAAcJ3wtuMwBKAQABAAQJvgSDZQCGAAAOAAIJDAecdABWAAABLgAFFAIJAwAcAAAAAA==.',
Ev='Everbark:BAAALgADCgEJAQAAAA==.Evodragker:BAABLgAECn8kAAMDAAkJKxR2IQDOAQADAAkJKxR2IQDOAQALAAEJcAkEPAAzAAAAAA==.',
Fe='Feider:BAAALgAECgEJAQAAAA==.Felais:BAABLgAFFH8JAAIXAAQJJgnTPQC4AAAXAAQJJgnTPQC4AAAAAA==.Feldron:BAAALgAECgcJEwAAAA==.Felkaos:BAAALgADCgEJAQAAAA==.Fellura:BAAALgAECgYJDAAAAA==.Femaledawg:BAAALgADCgcJEAAAAA==.',
Fi='Fingor:BAAALgAECgYJBwAAAA==.Fivepal:BAAALgAECgcJEgAAAA==.',
Fl='Flamecube:BAAALgAECgEJAwAAAA==.Flashx:BAABLgAECn8kAAMhAAgJ3iDsCQDtAgAhAAgJ3iDsCQDtAgACAAEJQQzbmQEvAAAAAA==.',
Fo='Foxxeyineawo:BAAALgADCgcJCAAAAA==.',
Fr='Frevmk:BAAALgAECgEJAgAAAA==.Frofrohunter:BAABLgAECn8sAAMMAAkJaB+kEgCiAgAMAAkJaB+kEgCiAgATAAUJAxLZTgAUAQAAAA==.Frofrolock:BAAALgAECgcJDgAAAA==.Froggie:BAABLgAECn8UAAMPAAcJfBWfUQBsAQAPAAcJfBWfUQBsAQAiAAMJXQ/iaACgAAAAAA==.Froshaman:BAAALgAECgEJAQAAAA==.',
Fu='Fuzywuuzy:BAACLgAFFH8OAAIXAAMJ1BR0OwDAAAAXAAMJ1BR0OwDAAAAuAAQKfyUAAxcACAnUI+ELAAIDABcACAnUI+ELAAIDABYABwk6Fv4nAJABAAAA.',
Ga='Gazdorn:BAABLgAECn8qAAISAAkJeRJ8EgDDAQASAAkJeRJ8EgDDAQAAAA==.',
Ge='Genebelcher:BAAALgAECgEJAQAAAA==.',
Gh='Ghost:BAABLgAECn8kAAIjAAkJOhyiBQAbAgAjAAkJOhyiBQAbAgAAAA==.',
Gi='Gigof:BAABLgAECn8rAAMWAAkJPxJ7JQCgAQAWAAgJ0RJ7JQCgAQAXAAcJ/AqZggC0AAAAAA==.',
Gl='Glissa:BAABLgAECn8UAAQKAAcJdCWRAQDTAgAKAAcJEiWRAQDTAgAgAAMJhSJYogAUAQAeAAIJjxpcRACkAAAAAA==.',
Go='Gobah:BAABLgAECn8YAAMfAAgJ5hXRGQDLAQAfAAgJ5hXRGQDLAQAkAAUJsQctFwCmAAAAAA==.',
Gt='Gt:BAAALgAFFAEJAQAAAA==.',
Gu='Gulldan:BAABLgAECn8iAAIgAAgJXxjCNgD+AQAgAAgJXxjCNgD+AQAAAA==.',
Gw='Gwyndolin:BAAALgADCgUJBQAAAA==.',
Ha='Habanero:BAAALgAECgQJBgABLgAECgkJKgAKAAAiAA==.Hadory:BAABLgAECn8YAAMCAAkJDBg0UgDSAQACAAkJDBg0UgDSAQAhAAQJWhm6SwAMAQAAAA==.Harrowhark:BAABLgAECn9BAAQKAAkJUwo9EgBEAQAgAAkJhgnSYAB+AQAKAAgJuwk9EgBEAQAeAAQJyQVDMgBVAAAAAA==.',
He='Hellzzdemon:BAABLgAECn8oAAIHAAkJ3hAIAwB2AQAHAAkJ3hAIAwB2AQAAAA==.Hendricks:BAAALgAECgQJCgAAAA==.Hexinverter:BAAALgAECgQJCQAAAA==.Hexzard:BAAALgADCgQJBAABLgAECgYJEwAcAAAAAA==.Hezekiiah:BAAALgAECgYJDQAAAA==.',
Ho='Holeecow:BAAALgADCgIJAgABLgAFFAQJEAAPAKIWAA==.Holycannoli:BAABLgAECn8VAAICAAkJ0BmsBQC0AQACAAkJ0BmsBQC0AQAAAA==.Horiffic:BAAALgAFFAMJAwAAAA==.Horok:BAAALgAECgYJDQAAAA==.Hotsforthots:BAAALgAECgUJBQAAAA==.Hotwheels:BAAALgAECgMJAwAAAA==.',
Hu='Hubert:BAABLgAECn8WAAIVAAgJwQkYVwAVAQAVAAgJwQkYVwAVAQAAAA==.Hubertdale:BAAALgAECgMJAwAAAA==.Hulkblood:BAAALgAECgEJAQAAAA==.Hummingbrook:BAAALgAECgcJDAABLgAFFAgJHAAbAFYSAA==.',
Hy='Hypandia:BAAALgAFFAEJAQABLgAFFAQJEAAPAKIWAA==.',
Ic='Ichaerus:BAAALgAECgQJBQABLgAECgkJHAABACYfAA==.Ichtheblack:BAAALgAECgcJCgABLgAECgkJHAABACYfAA==.Ichtu:BAAALgAECgEJAQABLgAECgkJHAABACYfAA==.',
Ii='Iilli:BAABLgAECn87AAMdAAkJlB9fBwAGAwAdAAkJlB9fBwAGAwABAAkJnxvzDQB2AgAAAA==.',
In='Inagard:BAAALgAECgQJBAAAAA==.Inari:BAABLgAECn8XAAIBAAkJSgt5LAByAQABAAkJSgt5LAByAQAAAA==.Inkkubus:BAACLgAFFH8dAAQeAAcJthXlDgC8AAAgAAQJqxo/bQDoAAAeAAMJXArlDgC8AAAKAAIJUxYYHwBSAAAuAAQKfxcABCAACQmPHuU6AO8BACAABwnZH+U6AO8BAB4AAwnpG74WAO4AAAoAAQkAABEnAFUAAAAA.Instagatorz:BAAALgADCgUJBgAAAA==.',
Iq='Iq:BAAALgAECgEJAQAAAA==.',
Ir='Ironfur:BAAALgAECgUJBQABLgAFFAYJFAAhAHARAA==.',
Iw='Iwkms:BAACLgAFFH8OAAIZAAQJihaWCAAhAQAZAAQJihaWCAAhAQAuAAQKfyMAAhkACAliIzMCADEDABkACAliIzMCADEDAAEuAAUUBQkGACQAwhYA.',
Ja='Jade:BAABLgAECn8dAAIJAAYJ9CTwFQD9AQAJAAYJ9CTwFQD9AQAAAA==.Jatheo:BAAALgADCgIJAgAAAA==.',
Je='Jenliz:BAAALgADCgEJAQABLgAECgYJEQAcAAAAAA==.Jeronor:BAAALgAECgIJAgAAAA==.',
Ji='Jigtide:BAAALgAECgEJAQAAAA==.Jimmick:BAABLgAECn8WAAIPAAcJfyNXEQDEAgAPAAcJfyNXEQDEAgABLgAECgkJGAACAAwYAA==.Jisung:BAABLgAECn8UAAMlAAYJkQLCKwCbAAAlAAYJkQLCKwCbAAAiAAIJHAE9xgARAAAAAA==.',
Jo='Jorad:BAAALgADCgEJAQAAAA==.',
Jt='Jtheman:BAAALgAECgQJBAAAAA==.',
Ju='Junebugg:BAAALgADCgEJAQAAAA==.',
Ka='Kaing:BAAALgAECgYJCwAAAA==.Kaissa:BAAALgAECgEJAQAAAA==.Kalena:BAACLgAFFH8IAAIGAAMJVgMmPQCOAAAGAAMJVgMmPQCOAAAuAAQKfz4AAgYACQnnDhliALsBAAYACQnnDhliALsBAAAA.Kalöna:BAAALgADCgEJAQAAAA==.Kandikkiss:BAAALgAECgUJDQAAAA==.Kaos:BAABLgAECn8jAAIGAAkJ+hFeXgDEAQAGAAkJ+hFeXgDEAQAAAA==.Kariatyda:BAABLgAECn8uAAIMAAkJMxgIGwBlAgAMAAkJMxgIGwBlAgAAAA==.Kasai:BAAALgADCgMJAwABLgAECgkJLwACABwaAA==.Kassandra:BAACLgAFFH8SAAIGAAMJ2R7hIwD9AAAGAAMJ2R7hIwD9AAAuAAQKfz4AAgYACQnvHJkcALECAAYACQnvHJkcALECAAAA.Kay:BAAALgAECgcJCQAAAA==.Kayden:BAABLgAECn8aAAIVAAYJhBh2JACQAQAVAAYJhBh2JACQAQABLgAECggJGwAhAFUcAA==.Kayn:BAAALgAECgIJAgAAAA==.',
Ke='Keelistus:BAAALgAECgQJBAAAAA==.Kekio:BAAALgAECgcJDAAAAA==.Kelisola:BAAALgADCgEJAQAAAA==.Kelzor:BAAALgAECgEJAQAAAA==.Keruu:BAAALgAECgcJBwAAAA==.',
Kh='Khaylorn:BAAALgAECgMJBgAAAA==.Kháòs:BAAALgAECgUJCgAAAA==.',
Ki='Kiloton:BAABLgAECn8sAAIYAAkJmxRyEwC+AQAYAAkJmxRyEwC+AQAAAA==.Kinari:BAABLgAECn8dAAQhAAkJbBgvAQBHAgAhAAkJbBgvAQBHAgACAAEJkg26PQAxAAAQAAEJfwEmWgAbAAAAAA==.Kitzy:BAABLgAECn8sAAIGAAkJKwycDQAZAQAGAAkJKwycDQAZAQAAAA==.',
Kl='Klapso:BAAALgADCgYJDQAAAA==.Klippertdk:BAACLgAFFH8IAAIFAAMJgBBoMwDSAAAFAAMJgBBoMwDSAAAuAAQKfzkAAgUACQkrGRorAFQCAAUACQkrGRorAFQCAAAA.Klugamonk:BAAALgADCgUJBQAAAA==.Klutz:BAABLgAECn8qAAIXAAkJXw86NgDAAQAXAAkJXw86NgDAAQAAAA==.',
Ko='Kodiwa:BAAALgAECgYJBgAAAA==.Korgan:BAAALgAECggJDwAAAA==.Korgriku:BAAALgADCgMJAwAAAA==.',
Kr='Kreznor:BAAALgAECgIJAgAAAA==.',
Ku='Kurzo:BAACLgAFFH8NAAIIAAQJCx+LEACBAQAIAAQJCx+LEACBAQAuAAQKfzsAAwgACQnrIuIGAPACAAgACQnrIuIGAPACABIABQmtEussANoAAAAA.',
Ky='Kylarian:BAABLgAECn8iAAIHAAkJyQatKwAjAQAHAAkJyQatKwAjAQAAAA==.Kyntara:BAAALgAECgYJDQAAAA==.Kyronian:BAAALgAECgYJDwAAAA==.',
['Kâ']='Kâsâi:BAABLgAECn8vAAICAAkJHBpdBADqAQACAAkJHBpdBADqAQAAAA==.',
La='Lachancea:BAAALgAECgEJAQABLgAECggJFgAgAAEaAA==.Lakshmee:BAAALgAECgcJDgAAAA==.',
Le='Ledarm:BAAALgAECggJEwAAAA==.Leigin:BAAALgADCgYJBgAAAA==.Lexxi:BAACLgAFFH8KAAICAAMJvg1mKAC2AAACAAMJvg1mKAC2AAAuAAQKfzoAAgIACQlCFdNDAPsBAAIACQlCFdNDAPsBAAAA.',
Li='Lifewing:BAAALgAECgUJDAAAAA==.Lightbehunt:BAAALgAECgQJBgAAAA==.Lightsglory:BAAALgADCgMJAwAAAA==.Lilly:BAAALgAECgYJCgAAAA==.Livaless:BAAALgADCgQJBAABLgAECgkJJgAgAFAiAA==.',
Lu='Lucialyn:BAAALgAECgcJDAABLgAECgcJFwAdAOojAA==.',
Ly='Lyllith:BAABLgAECn8cAAIjAAYJjREWDABkAQAjAAYJjREWDABkAQAAAA==.Lysende:BAAALgADCgQJBAAAAA==.',
Ma='Madamenoodle:BAAALgADCgkJCQAAAA==.Magnass:BAAALgADCgYJBgABLgAECgkJIAASAOIaAA==.Magnius:BAAALgADCgEJAQAAAA==.Mahoa:BAAALgAECgEJAQAAAA==.Mal:BAAALgAECggJCAAAAA==.Mastablasta:BAAALgAECgQJCQAAAA==.Maursaline:BAABLgAECn8lAAIXAAkJqge7WgAnAQAXAAkJqge7WgAnAQAAAA==.Mawea:BAAALgAECgUJDAAAAA==.Mawks:BAACLgAFFH8JAAIUAAIJlRJeDACXAAAUAAIJlRJeDACXAAAuAAQKf0EAAhQACQktG6MLAGcCABQACQktG6MLAGcCAAAA.',
Mc='Mcstukes:BAAALgAECgQJCAAAAA==.',
Me='Medeas:BAAALgAECgUJCgAAAA==.Meragos:BAAALgAECgMJAwAAAA==.Meteor:BAAALgADCgQJBAAAAA==.',
Mi='Migz:BAAALgADCgEJAQAAAA==.Migzeviltwin:BAAALgAECgEJAgAAAA==.Mimicz:BAAALgADCgUJBQAAAA==.Minitry:BAAALgAECgEJAwAAAA==.Mixon:BAAALgAECgEJBAAAAA==.Mixxon:BAAALgAECgYJDwAAAA==.',
Mo='Moinion:BAAALgADCgQJCAAAAA==.Moldbreather:BAAALgAECgEJAQAAAA==.Moomooimacow:BAAALgAECgQJBAAAAA==.Moomoomonkey:BAABLgAECn8fAAIiAAkJMhfiHQDzAQAiAAkJMhfiHQDzAQAAAA==.Morhgana:BAAALgAECgYJDwAAAA==.',
Ms='Mstea:BAAALgAECgEJAQAAAA==.',
Mx='Mxmlxxix:BAABLgAECn8jAAMOAAgJygGXSwC1AAAOAAgJygGXSwC1AAABAAIJXwHWZQAtAAAAAA==.',
My='Mylosh:BAAALgAECgQJBAABLgAECgkJGAACAAwYAA==.',
['Mö']='Mördecai:BAAALgAECgQJBAAAAA==.',
Na='Naija:BAAALgAECgEJAgAAAA==.Nati:BAAALgAECgUJBQAAAA==.',
Ne='Nephele:BAAALgAECgEJAgAAAA==.Neptune:BAAALgAECgQJCAAAAA==.Newport:BAAALgAECgMJBAABLgAFFAMJCQAfAM4RAA==.',
Ni='Nikorobin:BAAALgAECgQJBwABLgAFFAgJHAAbAFYSAA==.Nilius:BAAALgAECgEJAQABLgAECgkJHAABACYfAA==.',
No='Noodles:BAAALgAECgUJBQABLgAECggJIgAbAH0WAA==.Norgalina:BAAALgADCgUJBQAAAA==.',
Ny='Nymara:BAABLgAECn8eAAIQAAgJ8RH+FgBpAQAQAAgJ8RH+FgBpAQABLgAECgkJGAAJAIIcAA==.',
['Ní']='Níce:BAAALgAECgIJAwAAAA==.',
['Nü']='Nügs:BAAALgAECggJEwAAAA==.Nüguns:BAAALgAECgcJEQAAAA==.',
Od='Odyssey:BAAALgAECgUJBQABLgAFFAMJCQAfAM4RAA==.',
Ol='Olei:BAAALgADCgUJBQAAAA==.',
Or='Orlick:BAAALgAECgEJAQAAAA==.Orrok:BAAALgADCgYJBwAAAA==.',
Pa='Painlink:BAAALgAECgUJCQABLgAECgkJKQAIAHkRAA==.Painnkiller:BAACLgAFFH8RAAIMAAMJCBnjIQDnAAAMAAMJCBnjIQDnAAAuAAQKfzgAAgwACQnKHUkYAJUCAAwACQnKHUkYAJUCAAAA.Papyto:BAAALgADCgYJBwAAAA==.Parsley:BAABLgAECn8qAAMKAAkJACLCAAAhAwAKAAkJACLCAAAhAwAgAAMJmxmGwwDGAAAAAA==.Paxis:BAAALgAECgkJDgAAAA==.',
Pe='Perriwinkle:BAACLgAFFH8IAAIZAAMJDhDUBAC2AAAZAAMJDhDUBAC2AAAuAAQKf1MABBkACQkPH78DANECABkACQkPH78DANECABgACQkjEzcCAJgBABcABAk/DC2KAKMAAAAA.Perseus:BAAALgADCgMJAwAAAA==.',
Ph='Phission:BAAALgADCgEJAQAAAA==.Phobya:BAABLgAECn8nAAIXAAgJNBzWHABfAgAXAAgJNBzWHABfAgAAAA==.Phylloxeras:BAABLgAECn9NAAIFAAkJESbxAgBwAwAFAAkJESbxAgBwAwAAAA==.',
Pl='Pleasure:BAAALgADCgMJAwAAAA==.Pleggashroom:BAAALgADCgEJAQAAAA==.',
Po='Powder:BAAALgAECgMJAwAAAA==.Powders:BAABLgAECn81AAIGAAkJsRywKwBrAgAGAAkJsRywKwBrAgAAAA==.Powderysham:BAAALgAECgcJCwABLgAECgkJNQAGALEcAA==.',
Pr='Praystatiôn:BAAALgAECgEJAQABLgAECgcJGwAgAHcfAA==.Proshot:BAACLgAFFH8IAAIUAAMJtBvfGwDyAAAUAAMJtBvfGwDyAAAuAAQKfzIAAhQACQk4It0CABQDABQACQk4It0CABQDAAAA.',
Pu='Puddles:BAAALgAECgEJAQAAAA==.',
Pz='Pzalmo:BAAALgAECgMJAwABLgAECgkJHwAEAJkUAA==.',
Ra='Raccoon:BAACLgAFFH8LAAIgAAMJVwY+KwCuAAAgAAMJVwY+KwCuAAAuAAQKfz4AAyAACQmbEVxCANUBACAACQmbEVxCANUBAAoAAQloCxU+ADYAAAAA.Rahala:BAAALgAECgUJBQAAAA==.Ralor:BAAALgADCgEJAQAAAA==.Ravenhawk:BAAALgAECgYJEAAAAA==.Razza:BAAALgADCgYJCAAAAA==.',
Re='Remember:BAAALgADCgEJAQAAAA==.Renivatio:BAABLgAECn8uAAIFAAkJcBsLAwAwAgAFAAkJcBsLAwAwAgAAAA==.',
Rh='Rhyntix:BAAALgADCgEJAQAAAA==.',
Ro='Ronstådt:BAAALgADCgEJAQAAAA==.Roronoazoro:BAACLgAFFH8cAAIbAAgJVhJyFgD9AQAbAAgJVhJyFgD9AQAuAAQKfyEAAxsACQlIH2ojAH0CABsACQlIH2ojAH0CACYAAglxEwUmAFQAAAAA.',
Ry='Ryrin:BAABLgAECn8mAAMIAAkJBRAQNQB1AQAIAAkJBRAQNQB1AQAaAAQJMgq7BwB/AAAAAA==.Ryrìn:BAAALgADCgEJAQAAAA==.Ryrín:BAAALgAECggJEwAAAA==.',
['Rë']='Rëggië:BAAALgAECgIJAwAAAA==.',
Sa='Samidrac:BAABLgAECn8eAAILAAgJBAMvBACRAAALAAgJBAMvBACRAAAAAA==.Sammidormu:BAABLgAECn8jAAQEAAgJ5RNoCgB5AQAEAAcJABVoCgB5AQADAAcJbAtZNgAgAQALAAEJ2QEPTgAjAAAAAA==.Sanderwoof:BAAALgAECggJCAAAAA==.Saret:BAAALgADCgMJAwAAAA==.Sarzul:BAABLgAECn8VAAMeAAYJ/A8VNADnAAAgAAYJ2gzAmwAiAQAeAAUJThEVNADnAAAAAA==.Satoshie:BAAALgAECggJCQAAAA==.Sayang:BAAALgAECgMJAwABLgAECgkJOAAXABsfAA==.',
Sc='Scerevisiae:BAABLgAECn8WAAMgAAgJARq9fQA9AQAgAAUJGx29fQA9AQAeAAQJxBSjLgABAQAAAA==.',
Se='Sedelis:BAABLgAECn8fAAIhAAkJzwr+MQCOAQAhAAkJzwr+MQCOAQAAAA==.Sefirbrena:BAAALgADCgkJAwAAAA==.Selaya:BAAALgAECgEJAQAAAA==.Semnai:BAABLgAECn8+AAIXAAkJ+Bb/GwBnAgAXAAkJ+Bb/GwBnAgAAAA==.Serafín:BAACLgAFFH8LAAIJAAMJagX8DwCjAAAJAAMJagX8DwCjAAAuAAQKfzgAAgkACQmkDisiAJcBAAkACQmkDisiAJcBAAAA.Sevilicious:BAAALgADCgQJAwAAAA==.',
Sh='Shaay:BAAALgAFFAIJAgAAAA==.Shadowlock:BAAALgAECgEJAgAAAA==.Shadownutt:BAAALgAECgUJBQAAAA==.Shadowpyro:BAAALgAECgEJAQAAAA==.Shamwig:BAAALgADCgUJBQAAAA==.Shazzam:BAAALgAECggJEAAAAA==.Shieldwall:BAABLgAECn8qAAISAAgJWg/tGwBXAQASAAgJWg/tGwBXAQAAAA==.',
Si='Silanah:BAAALgAECgEJAQABLgAFFAQJEAAPAKIWAA==.Silbeb:BAAALgAECgcJBwABLgAFFAQJGgAMAP0fAA==.Silverhâwk:BAAALgADCgEJAQAAAA==.Sinastys:BAABLgAECn8aAAICAAgJ9RCWgQBsAQACAAgJ9RCWgQBsAQAAAA==.',
Sn='Snoots:BAAALgADCgEJAQAAAA==.',
So='Solone:BAABLgAECn8UAAIbAAYJ6w4tlAD4AAAbAAYJ6w4tlAD4AAAAAA==.Somavra:BAAALgAECgMJBgAAAA==.Sopidia:BAABLgAECn8lAAMPAAkJ+RV0PQC5AQAPAAgJTBV0PQC5AQAiAAUJHQatdACOAAAAAA==.Sorvato:BAABLgAECn85AAIbAAkJNRlRIgBIAgAbAAkJNRlRIgBIAgAAAA==.',
Sp='Spiritholy:BAAALgAECgkJBgAAAA==.Spoonzz:BAABLgAECn8xAAMNAAkJDSRlBQD7AgANAAkJDSRlBQD7AgAJAAIJKx9TWQCkAAAAAA==.',
St='Stamavan:BAABLgAECn8kAAIYAAkJzCIjAwD6AgAYAAkJzCIjAwD6AgAAAA==.Starflayer:BAABLgAECn8nAAMbAAkJXxziJQA2AgAbAAkJbhviJQA2AgAmAAIJYxr3IAB8AAAAAA==.Steb:BAAALgADCgMJAwAAAA==.Sterjariger:BAAALgAECgYJBgABLgAFFAQJCgAKALEOAA==.',
Su='Sunari:BAAALgAECgMJBgAAAA==.Supermelon:BAABLgAECn8WAAIjAAcJXBFKDQBVAQAjAAcJXBFKDQBVAQAAAA==.',
Sw='Swenior:BAAALgAECgEJAQAAAA==.',
Sy='Syarli:BAAALgAECggJDAAAAA==.Sylvaeelor:BAAALgAFFAIJAwABLgAFFAQJDgAaAG4TAA==.Sylvanaria:BAACLgAFFH8LAAIPAAMJ0CWkDAA3AQAPAAMJ0CWkDAA3AQAuAAQKfz4AAg8ACQlbJjoBAMMDAA8ACQlbJjoBAMMDAAAA.Sylvanaris:BAAALgAECgYJEQAAAA==.Systyx:BAABLgAECn8bAAIgAAcJdx/1TAC0AQAgAAcJdx/1TAC0AQAAAA==.',
Ta='Takura:BAAALgAECgkJBwABLgAECgkJDQAcAAAAAA==.Talenel:BAAALgAECgQJBAAAAA==.Talyzien:BAAALgADCgYJBwAAAA==.',
Te='Tealan:BAACLgAFFH8HAAMLAAQJugzLGgDpAAALAAQJugzLGgDpAAADAAEJRgLpawAvAAAuAAQKfzAAAwMACQm0GBwTAEYCAAMACQm0GBwTAEYCAAsACAmpEukcAJ4BAAAA.Tealyn:BAAALgAECgYJBgAAAA==.Teluz:BAAALgAECgQJCgAAAA==.Tendra:BAAALgAECgYJBQAAAA==.Teronreborn:BAABLgAECn8lAAIFAAkJOiWGFAAAAwAFAAkJOiWGFAAAAwAAAA==.',
Th='Thaneer:BAAALgAECgYJBwAAAA==.Thanos:BAABLgAECn8dAAICAAYJ7Q6KpAA3AQACAAYJ7Q6KpAA3AQAAAA==.Thebadmage:BAAALgAECgcJBAAAAA==.Throstmok:BAACLgAFFH8RAAIRAAQJTROkIQDcAAARAAQJTROkIQDcAAAuAAQKfzcAAhEACQm3Hq8JAHgCABEACQm3Hq8JAHgCAAAA.Thràll:BAAALgAECgUJBQAAAA==.Thränton:BAAALgAECgEJAQABLgAECgcJFAAmALwhAA==.Thumbalina:BAAALgAECgYJEQAAAA==.',
Ti='Tiantu:BAAALgAECgIJAgAAAA==.',
To='Tongra:BAAALgADCgQJBAABLgAECgkJIAAGAFgPAA==.Totemtuggér:BAAALgADCgIJAgAAAA==.',
Tp='Tpaste:BAAALgADCgcJBwAAAA==.',
Tr='Trampstãmp:BAAALgAECgIJAgAAAA==.Trinitea:BAAALgAECgYJBwAAAA==.Trout:BAAALgADCgYJDAABLgAECgYJCgAcAAAAAA==.Trovikk:BAAALgADCgUJBgAAAA==.',
Tu='Turg:BAAALgAECgMJAwABLgAECgQJBwAcAAAAAA==.Turgo:BAAALgAECgEJAQABLgAECgQJBwAcAAAAAA==.Turgress:BAAALgAECgQJBwAAAA==.',
['Tà']='Tàmber:BAAALgADCgYJBwAAAA==.',
Ul='Ulfast:BAACLgAFFH8JAAIiAAMJRRSaEwC6AAAiAAMJRRSaEwC6AAAuAAQKfyUAAiIACAlKHrcaAAsCACIACAlKHrcaAAsCAAAA.',
Va='Valarios:BAAALgAECgYJCgAAAA==.Vannhellsing:BAABLgAECn8nAAIFAAgJJggwnwAtAQAFAAgJJggwnwAtAQAAAA==.Vanyel:BAABLgAECn9YAAIGAAkJBRpFBQDDAQAGAAkJBRpFBQDDAQAAAA==.Vaudorka:BAABLgAECn8cAAIEAAkJIx5RAwBnAgAEAAkJIx5RAwBnAgAAAA==.',
Ve='Vecna:BAAALgADCgMJAwABLgAECgYJCAAcAAAAAA==.Veliuz:BAAALgADCgQJBAAAAA==.Velrynth:BAABLgAECn84AAMdAAkJ+BSAEwBFAgAdAAkJVxSAEwBFAgAOAAcJzghySAAXAQAAAA==.Vemal:BAABLgAECn8yAAIMAAkJThk9GwCCAgAMAAkJThk9GwCCAgAAAA==.',
Vo='Vociferoy:BAACLgAFFH8VAAIMAAMJxhp7HQD7AAAMAAMJxhp7HQD7AAAuAAQKf0QAAgwACQl9IUQPANYCAAwACQl9IUQPANYCAAAA.Voidsteffan:BAABLgAECn9FAAMeAAkJaBtmAABYAgAeAAkJaBtmAABYAgAgAAQJjw4iwQDXAAAAAA==.',
Vr='Vryadox:BAAALgAFFAIJAgABLgAFFAQJDwAgAGwdAA==.',
Vv='Vv:BAACLgAFFH9ZAAIbAAkJsiYHAACaAwAbAAkJsiYHAACaAwAuAAQKfzUAAhsACQm1JucAANoDABsACQm1JucAANoDAAAA.',
Vz='Vz:BAAALgADCgUJBQAAAA==.',
Wh='Whoppin:BAAALgAECgIJAgAAAA==.',
Wi='Wiglimparms:BAAALgAECgIJAgAAAA==.',
Wr='Wry:BAAALgAECgMJAwAAAA==.',
Wy='Wysselbow:BAAALgADCggJDQAAAA==.',
['Wá']='Wárranpeace:BAAALgADCgMJAwAAAA==.',
Xa='Xalmo:BAAALgAECgEJAQABLgAECgkJHwAEAJkUAA==.Xalzi:BAAALgADCggJCQABLgAECgcJFAAPAHwVAA==.',
Xi='Xingwong:BAABLgAECn89AAIfAAkJ5yXXAQBNAwAfAAkJ5yXXAQBNAwAAAA==.',
Za='Zannytoes:BAABLgAECn8mAAMVAAkJpRA9MAC6AQAVAAkJpRA9MAC6AQANAAEJLxFSnwAwAAAAAA==.',
Ze='Zead:BAAALgAECgEJBQAAAA==.Zerana:BAACLgAFFH8NAAIeAAQJmAT+CgDrAAAeAAQJmAT+CgDrAAAuAAQKfxgAAh4ACQlRD1wOAFcBAB4ACQlRD1wOAFcBAAAA.Zeriea:BAAALgADCgEJAQAAAA==.Zevtra:BAAALgADCgEJAQAAAA==.',
Zi='Zie:BAABLgAECn9aAAIBAAkJ8RuuAQD6AQABAAkJ8RuuAQD6AQAAAA==.Zikren:BAAALgAECgkJCQAAAA==.',
Zo='Zoumbadouwow:BAAALgAFFAEJAQABLgAECgkJOwAdAJQfAA==.',
Zs='Zsinj:BAAALgADCgEJAQAAAA==.',
['Ðo']='Ðonkle:BAABLgAECn8TAAIbAAgJmByzKwAZAgAbAAgJmByzKwAZAgAAAA==.',
['Ðr']='Ðrewid:BAAALgADCgEJAQAAAA==.',
['Ñi']='Ñice:BAACLgAFFH8aAAIIAAcJVSOoBwDqAQAIAAcJVSOoBwDqAQAuAAQKfxoAAggACQkrHugYACcCAAgACQkrHugYACcCAAAA.',
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
