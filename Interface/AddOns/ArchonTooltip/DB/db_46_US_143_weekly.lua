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

local lookup = {'Priest-Shadow','Paladin-Retribution','Paladin-Holy','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Unholy','Mage-Frost','DemonHunter-Havoc','Warrior-Fury','Monk-Brewmaster','Warlock-Affliction','Evoker-Preservation','Hunter-BeastMastery','Monk-Windwalker','Priest-Holy','Shaman-Restoration','Paladin-Protection','DeathKnight-Blood','Warrior-Protection','Hunter-Survival','Hunter-Marksmanship','Monk-Mistweaver','Druid-Balance','Druid-Restoration','Druid-Guardian','Druid-Feral','Warrior-Arms','DemonHunter-Devourer','Unknown-Unknown','Priest-Discipline','Warlock-Destruction','Rogue-Subtlety','Warlock-Demonology','Shaman-Elemental','Rogue-Assassination','Rogue-Outlaw','Shaman-Enhancement','DemonHunter-Vengeance',}
local provider = {region='US',realm='Lightninghoof',name='US',type='weekly',zone=46,date='2026-07-12',data={Ab='Abukuma:BAAALgAECgQJBAAAAA==.',
Ac='Aceieus:BAAALgAECgkJAwAAAA==.',
Ad='Adraina:BAAALgADCgEJAQAAAA==.Adrewid:BAAALgADCgQJBAAAAA==.',
Ae='Aelarya:BAABLgAECn8RAAIBAAgJAQYXQgDpAAABAAgJAQYXQgDpAAAAAA==.Aenstalash:BAACLgAFFH8IAAMCAAMJURj8IgDgAAACAAMJURj8IgDgAAADAAIJAge6GQBfAAAuAAQKfyEAAgIACAk/I0ckAHQCAAIACAk/I0ckAHQCAAAA.Aephium:BAABLgAECn8VAAMEAAcJuwZkYQC2AAAEAAYJJgZkYQC2AAAFAAUJtAQVHABsAAAAAA==.Aesilakaersi:BAAALgAECgYJCgAAAA==.Aeson:BAABLgAECn8kAAIGAAkJiBeVRQDyAQAGAAkJiBeVRQDyAQAAAA==.',
Af='Afflictia:BAAALgADCgYJEAAAAA==.',
Ai='Aironel:BAAALgADCgMJAwAAAA==.',
Al='Alanza:BAAALgAFFAIJAgAAAA==.Alaure:BAAALgADCgIJAgAAAA==.Alessia:BAAALgAECgIJAgAAAA==.Alfonsoo:BAAALgADCgEJAQAAAA==.Alida:BAAALgAECgQJBAAAAA==.Alistur:BAABLgAECn8mAAIHAAgJygsDFAD0AAAHAAgJygsDFAD0AAAAAA==.',
Am='Amanna:BAAALgAFFAEJAQABLgAECgkJOQAIADsmAA==.Amoona:BAAALgAECgYJEgABLgAECgkJOQAIADsmAA==.',
An='Anaila:BAAALgAECgMJAwABLgAFFAQJDgAJAAsfAA==.Anoriia:BAAALgADCgUJBQAAAA==.',
Ar='Arcnid:BAAALgADCgYJBgAAAA==.Arfas:BAAALgADCgQJBAAAAA==.Arthraz:BAABLgAECn8kAAIKAAkJsxwHDAB1AgAKAAkJsxwHDAB1AgABLgAECgkJKgALAAAiAA==.',
As='Astara:BAAALgAECgQJBAAAAA==.Astraa:BAAALgAECgIJAgAAAA==.Astrex:BAACLgAFFH8GAAIMAAIJrQ8QDwByAAAMAAIJrQ8QDwByAAAuAAQKf1UABAwACQl0GHYAAH8CAAwACQl0GHYAAH8CAAQABwkrA9ULAIYAAAUAAgm8BUkGADcAAAAA.',
Au='Aunaturale:BAAALgAECgkJAwAAAA==.Aurali:BAAALgAECgEJAQAAAA==.Aureliá:BAABLgAECn8ZAAINAAcJvArCjAAlAQANAAcJvArCjAAlAQAAAA==.',
['Aü']='Aütobot:BAABLgAECn8iAAIOAAkJMw20JgCAAQAOAAkJMw20JgCAAQAAAA==.',
Ba='Badgirl:BAACLgAFFH8MAAIPAAQJgREoGQDyAAAPAAQJgREoGQDyAAAuAAQKfxkAAw8ACAm+E9w1ACoBAA8ABgnBFtw1ACoBAAEABgktCuFLAOAAAAAA.Balnar:BAABLgAECn8gAAIQAAcJEBc0CQBKAQAQAAcJEBc0CQBKAQABLgAECggJIAARANsWAA==.Balraga:BAABLgAECn8ZAAIIAAgJUQrjKwAhAQAIAAgJUQrjKwAhAQAAAA==.Bargrivyek:BAAALgAECgYJCQAAAA==.Bayded:BAAALgADCgEJAQAAAA==.',
Be='Beastboyy:BAAALgAECgUJBQAAAA==.Bega:BAACLgAFFH8uAAMGAAgJ9hpNDQB0AgAGAAgJ9hpNDQB0AgASAAEJAABPUwAAAAAuAAQKf0EAAwYACQnoJXoFAE8DAAYACQnoJXoFAE8DABIABgkrFzslABUBAAAA.Benton:BAAALgAECgQJCAAAAA==.',
Bi='Bigglimpie:BAAALgAECgYJDQAAAA==.',
Bl='Bloodchiefsr:BAAALgAECgEJAQAAAA==.Bloodlustplz:BAABLgAECn8qAAMJAAkJshdCLACjAQAJAAcJLx5CLACjAQATAAgJLQ/NGwBYAQAAAA==.',
Bo='Bobster:BAABLgAECn8kAAIHAAkJuxHlYQC7AQAHAAkJuxHlYQC7AQAAAA==.Bonepaw:BAAALgAECgMJBQABLgAECgcJFAAQAHwVAA==.Booyea:BAACLgAFFH8OAAISAAMJNRjoDgDJAAASAAMJNRjoDgDJAAAuAAQKfz4AAhIACQklHBMLAF8CABIACQklHBMLAF8CAAAA.',
Br='Brew:BAAALgAECgcJCwAAAA==.Brewwnor:BAAALgAECgkJEAAAAA==.Brickdemkeys:BAABLgAECn8fAAIHAAgJPBr/YwC2AQAHAAgJPBr/YwC2AQAAAA==.Brisfloggnaw:BAAALgAFFAEJAQAAAA==.',
Ca='Caladk:BAAALgADCgUJBQABLgAFFAgJJAAUAP8iAA==.Calamuelis:BAACLgAFFH8kAAQUAAgJ/yJIBABEAQAVAAcJ7hvWBwCeAQAUAAcJ2SFIBABEAQANAAIJehyGRwBpAAAuAAQKfx0ABBUACAnSJLsNANcCABUACAmWJLsNANcCABQABAn5JIowACYBAA0AAQkIJhv2AGkAAAAA.Caliope:BAABLgAECn8pAAMWAAkJcxWfJQD3AQAWAAkJcxWfJQD3AQAOAAQJwwrKCAC1AAAAAA==.Capsasin:BAAALgADCgUJBQAAAA==.Carnage:BAAALgAFFAIJAgAAAA==.Cazlek:BAAALgAECgQJCwAAAA==.',
Ce='Celery:BAAALgAECgQJBAABLgAECgkJKgALAAAiAA==.Celldweller:BAAALgAECgYJCgAAAA==.Cerdred:BAABLgAECn8dAAIXAAUJARDLSQAEAQAXAAUJARDLSQAEAQAAAA==.Ceredis:BAAALgAECgEJAQAAAA==.Cerelus:BAABLgAECn8gAAIHAAkJWA9oVQDdAQAHAAkJWA9oVQDdAQAAAA==.',
Ch='Chaac:BAAALgAECggJEAABLgAECggJFgAMALITAA==.Chmmr:BAAALgADCgMJAwAAAA==.Chowilawu:BAAALgADCgkJCQAAAA==.Chriswilsonn:BAAALgAECgQJCAAAAA==.Chuca:BAAALgAECgYJBgAAAA==.Chucalu:BAABLgAECn8WAAUYAAgJVh4ANwDLAQAYAAYJUyAANwDLAQAZAAQJCx7wEQBVAQAXAAIJih8+WgCqAAAaAAEJLwbeMgA2AAAAAA==.Chéwtoy:BAAALgAECgIJBAAAAA==.',
Cl='Clax:BAAALgAECgIJBQAAAA==.',
Co='Cobeam:BAAALgAECgYJEwAAAA==.Cowpernicus:BAABLgAECn8iAAIYAAkJ7SAJBwBHAwAYAAkJ7SAJBwBHAwABLgAFFAQJEQAQAKIWAA==.',
Cr='Crungleman:BAABLgAECn8YAAINAAcJuRi1XwCIAQANAAcJuRi1XwCIAQAAAA==.',
Ct='Cthuwu:BAAALgAECgQJBAABLgAECggJFgAMALITAA==.',
Cu='Curoi:BAABLgAECn8rAAMaAAkJjxeECABEAgAaAAkJjxeECABEAgAYAAgJRAozeQDsAAAAAA==.',
['Cã']='Cãrloy:BAACLgAFFH8kAAIJAAQJlBv2GwBBAQAJAAQJlBv2GwBBAQAuAAQKf1sAAwkACQlWIhwHAOwCAAkACQlWIhwHAOwCABsAAgkpIexEALUAAAAA.',
['Cê']='Cêlestial:BAABLgAECn85AAMIAAkJOyYiAACIAwAIAAkJMCYiAACIAwAcAAgJ9SLmGwBtAgAAAA==.',
Da='Daedalas:BAABLgAECn8cAAMBAAkJJh/uDgBqAgABAAkJJh/uDgBqAgAPAAIJMAKAawA8AAAAAA==.Daedtoo:BAAALgAECgUJBQABLgAECgkJHAABACYfAA==.Damonk:BAAALgADCgYJBgABLgAECgkJIAATAOIaAA==.Danevolent:BAABLgAECn8gAAMPAAcJ9yJ9DQCAAgAPAAcJ9yJ9DQCAAgABAAQJEA0/YACYAAABLgAECgkJIAATAOIaAA==.Danzaster:BAAALgADCgQJBAAAAA==.Darkxsoul:BAABLgAECn8gAAIRAAgJ2xbBEAC4AQARAAgJ2xbBEAC4AQAAAA==.Darthknull:BAACLgAFFH8SAAICAAQJBRe8OAA7AQACAAQJBRe8OAA7AQAuAAQKfz0AAgIACQnxIXAYALECAAIACQnxIXAYALECAAAA.Darthtalon:BAAALgAECgkJDgABLgAFFAQJEgACAAUXAA==.',
De='Deadeyedicky:BAAALgAECgkJBwAAAA==.Deathmachine:BAAALgADCgUJBQAAAA==.Deathniight:BAAALgAECgUJBAAAAA==.Deathseer:BAAALgAECgcJDgAAAA==.Deathwood:BAAALgADCgUJBgABLgAECgEJAQAdAAAAAA==.Deatthdecay:BAAALgAECggJBAAAAA==.Deitrichx:BAABLgAECn8pAAIVAAkJnxmVBgApAgAVAAkJnxmVBgApAgAAAA==.Delley:BAAALgADCgEJAQAAAA==.Deminestra:BAAALgAECgQJBAAAAA==.Deminestrea:BAABLgAECn8aAAISAAYJchCgKgADAQASAAYJchCgKgADAQAAAA==.Demonswhere:BAAALgADCgQJBAAAAA==.Devilscreed:BAAALgAECgEJAQAAAA==.',
Di='Dingleberrys:BAAALgADCgEJAQAAAA==.Dippindots:BAAALgAECgYJCAAAAA==.Disshammy:BAAALgAFFAIJAgABLgAFFAgJIgAEANEhAA==.Dittoz:BAAALgADCgUJBAAAAA==.',
Do='Dolfcritler:BAAALgAECgQJBQAAAA==.Dolfcrittler:BAAALgADCgEJAQAAAA==.Donkform:BAAALgAECgkJEgAAAA==.Donniyii:BAAALgAECgcJBwABLgAECgkJOwAeAJQfAA==.Doomrider:BAAALgADCgYJBgAAAA==.Dottzz:BAABLgAECn8aAAIfAAYJ8B27FQCcAQAfAAYJ8B27FQCcAQAAAA==.',
Dr='Draconith:BAACLgAFFH8hAAIMAAUJChL5BwAOAQAMAAUJChL5BwAOAQAuAAQKfzcAAgwACQmSG00FAMMCAAwACQmSG00FAMMCAAAA.Dramoo:BAAALgAECgMJAwAAAA==.Draqkmar:BAABLgAECn8fAAINAAYJTwulIwCJAAANAAYJTwulIwCJAAAAAA==.Dreddwing:BAABLgAECn8WAAMMAAgJshOaEADCAQAMAAcJcBWaEADCAQAEAAIJJg8iewBrAAAAAA==.Dredfox:BAAALgAECgIJAgABLgAECgkJRwAXAPURAA==.Drunkenoodle:BAAALgADCgYJBgAAAA==.',
Du='Dunsparrow:BAACLgAFFH8RAAIQAAQJohZvIgCmAAAQAAQJohZvIgCmAAAuAAQKf0cAAhAACQnfIkgFAF8DABAACQnfIkgFAF8DAAAA.Durzul:BAAALgAECgEJAQAAAA==.',
Ei='Eightyone:BAAALgAECggJDwAAAA==.Eindraken:BAACLgAFFH8aAAIMAAUJLAmbDACdAAAMAAUJLAmbDACdAAAuAAQKfzkAAgwACQn7EjENAP4BAAwACQn7EjENAP4BAAAA.Eiroh:BAABLgAECn8YAAIKAAkJghxLAQD6AQAKAAkJghxLAQD6AQAAAA==.Eisis:BAACLgAFFH8HAAIaAAMJhgsmBgCsAAAaAAMJhgsmBgCsAAAuAAQKfz8AAhoACQlUEJUUAHoBABoACQlUEJUUAHoBAAAA.',
El='Elanalué:BAABLgAECn8VAAIBAAYJ/Q1zDQCcAAABAAYJ/Q1zDQCcAAABLgAECgkJKQAWAHMVAA==.',
Em='Emmie:BAAALgADCgQJBAAAAA==.',
En='Enamel:BAAALgAECgMJAwABLgAFFAMJCgAgAM4RAA==.',
Er='Erixee:BAAALgAECgUJBgAAAA==.Erroz:BAAALgADCgIJAQAAAA==.',
Es='Eshonäi:BAABLgAECn8aAAIhAAYJtRHRjgAdAQAhAAYJtRHRjgAdAQAAAA==.Espriesso:BAABLgAECn8VAAQeAAgJAQ1uMwBKAQAeAAcJ3wtuMwBKAQABAAQJvgSDZQCGAAAPAAIJDAecdABWAAABLgAFFAIJAwAdAAAAAA==.',
Ev='Everbark:BAAALgADCgEJAQAAAA==.Evodragker:BAABLgAECn8kAAMEAAkJKxR2IQDOAQAEAAkJKxR2IQDOAQAMAAEJcAkEPAAzAAAAAA==.',
Fe='Feider:BAAALgAECgEJAQAAAA==.Felais:BAABLgAFFH8KAAIYAAQJJgnTPQC4AAAYAAQJJgnTPQC4AAAAAA==.Feldron:BAAALgAECgcJEwAAAA==.Felkaos:BAAALgADCgEJAQAAAA==.Fellura:BAAALgAECgYJDAAAAA==.Femaledawg:BAAALgADCgcJEAAAAA==.',
Fi='Fingor:BAAALgAECgYJBwAAAA==.Fivepal:BAAALgAECgcJEgAAAA==.',
Fl='Flamecube:BAAALgAECgEJAwAAAA==.Flashx:BAABLgAECn8kAAMDAAgJ3iDsCQDtAgADAAgJ3iDsCQDtAgACAAEJQQzbmQEvAAAAAA==.',
Fo='Foxxeyineawo:BAAALgADCgcJCAAAAA==.',
Fr='Frevmk:BAAALgAECgEJAgAAAA==.Frofrohunter:BAABLgAECn8sAAMNAAkJaB+kEgCiAgANAAkJaB+kEgCiAgAVAAUJAxLZTgAUAQAAAA==.Frofrolock:BAAALgAECgcJDgAAAA==.Froggie:BAABLgAECn8UAAMQAAcJfBWfUQBsAQAQAAcJfBWfUQBsAQAiAAMJXQ/iaACgAAAAAA==.Froshaman:BAAALgAECgEJAQAAAA==.',
Fu='Fuzywuuzy:BAACLgAFFH8PAAMYAAMJ1BR0OwDAAAAYAAMJ1BR0OwDAAAAXAAEJYxAGJAA4AAAuAAQKfyUAAxgACAnUI+ELAAIDABgACAnUI+ELAAIDABcABwk6Fv4nAJABAAAA.',
Ga='Gazdorn:BAABLgAECn8qAAITAAkJeRJ8EgDDAQATAAkJeRJ8EgDDAQAAAA==.',
Ge='Genebelcher:BAAALgAECgEJAQAAAA==.',
Gh='Ghost:BAABLgAECn8kAAIjAAkJOhyiBQAbAgAjAAkJOhyiBQAbAgAAAA==.',
Gi='Gigof:BAABLgAECn8rAAMXAAkJPxJ7JQCgAQAXAAgJ0RJ7JQCgAQAYAAcJ/AqZggC0AAAAAA==.',
Gl='Glissa:BAABLgAECn8UAAQLAAcJdCWRAQDTAgALAAcJEiWRAQDTAgAhAAMJhSJYogAUAQAfAAIJjxpcRACkAAAAAA==.',
Go='Gobah:BAABLgAECn8YAAMgAAgJ5hXRGQDLAQAgAAgJ5hXRGQDLAQAkAAUJsQctFwCmAAAAAA==.',
Gt='Gt:BAAALgAFFAIJAgAAAA==.',
Gu='Gulldan:BAABLgAECn8iAAIhAAgJXxjCNgD+AQAhAAgJXxjCNgD+AQAAAA==.',
Gw='Gwyndolin:BAAALgADCgUJBQAAAA==.',
Ha='Habanero:BAAALgAECgQJBgABLgAECgkJKgALAAAiAA==.Hadory:BAABLgAECn8YAAMCAAkJDBg0UgDSAQACAAkJDBg0UgDSAQADAAQJWhm6SwAMAQAAAA==.Harrowhark:BAABLgAECn9BAAQLAAkJUwo9EgBEAQAhAAkJhgnSYAB+AQALAAgJuwk9EgBEAQAfAAQJyQVDMgBVAAAAAA==.',
He='Hellzzdemon:BAABLgAECn8oAAIIAAkJ3hCjAwB+AQAIAAkJ3hCjAwB+AQAAAA==.Hendricks:BAAALgAECgQJCgAAAA==.Hexinverter:BAAALgAECgQJCQAAAA==.Hexzard:BAAALgADCgQJBAABLgAECgYJEwAdAAAAAA==.Hezekiiah:BAAALgAECgYJDQAAAA==.',
Ho='Holeecow:BAAALgADCgIJAgABLgAFFAQJEQAQAKIWAA==.Holycannoli:BAABLgAECn8VAAICAAkJ0BlDBwCwAQACAAkJ0BlDBwCwAQAAAA==.Horiffic:BAAALgAFFAMJAwAAAA==.Horok:BAAALgAECgYJDQAAAA==.Hotsforthots:BAAALgAECgUJBQAAAA==.Hotwheels:BAAALgAECgMJAwAAAA==.',
Hu='Hubert:BAABLgAECn8WAAIWAAgJwQkYVwAVAQAWAAgJwQkYVwAVAQAAAA==.Hubertdale:BAAALgAECgMJAwAAAA==.Hulkblood:BAAALgAECgEJAQAAAA==.Hummingbrook:BAAALgAECgcJDAABLgAFFAgJHAAcAFYSAA==.',
Hy='Hypandia:BAAALgAFFAEJAQABLgAFFAQJEQAQAKIWAA==.',
Ic='Ichaerus:BAAALgAECgQJBQABLgAECgkJHAABACYfAA==.Ichtheblack:BAAALgAECgcJCgABLgAECgkJHAABACYfAA==.Ichtu:BAAALgAECgEJAQABLgAECgkJHAABACYfAA==.',
Ii='Iilli:BAABLgAECn87AAMeAAkJlB9fBwAGAwAeAAkJlB9fBwAGAwABAAkJnxvzDQB2AgAAAA==.',
In='Inagard:BAAALgAECgQJBAAAAA==.Inari:BAABLgAECn8XAAIBAAkJSgt5LAByAQABAAkJSgt5LAByAQAAAA==.Inkkubus:BAACLgAFFH8eAAQfAAcJthXlDgC8AAAhAAQJqxo/bQDoAAAfAAMJXArlDgC8AAALAAIJUxYYHwBSAAAuAAQKfxcABCEACQmPHuU6AO8BACEABwnZH+U6AO8BAB8AAwnpG74WAO4AAAsAAQkAABEnAFUAAAAA.Instagatorz:BAAALgADCgUJBgAAAA==.',
Iq='Iq:BAAALgAECgEJAQAAAA==.',
Ir='Ironfur:BAAALgAECgUJBQABLgAFFAYJFAADAHARAA==.',
Iw='Iwkms:BAACLgAFFH8OAAIaAAQJihaWCAAhAQAaAAQJihaWCAAhAQAuAAQKfyMAAhoACAliIzMCADEDABoACAliIzMCADEDAAEuAAUUBQkGACQAwhYA.',
Ja='Jade:BAABLgAECn8dAAIKAAYJ9CTwFQD9AQAKAAYJ9CTwFQD9AQAAAA==.Jatheo:BAAALgADCgIJAgAAAA==.',
Je='Jenliz:BAAALgADCgEJAQABLgAECgYJEQAdAAAAAA==.Jeronor:BAAALgAECgIJAgAAAA==.',
Ji='Jigtide:BAAALgAECgEJAQAAAA==.Jimmick:BAABLgAECn8WAAIQAAcJfyNXEQDEAgAQAAcJfyNXEQDEAgABLgAECgkJGAACAAwYAA==.Jisung:BAABLgAECn8UAAMlAAYJkQLCKwCbAAAlAAYJkQLCKwCbAAAiAAIJHAE9xgARAAAAAA==.',
Jo='Jorad:BAAALgADCgEJAQAAAA==.',
Jt='Jtheman:BAAALgAECgQJBAAAAA==.',
Ju='Junebugg:BAAALgADCgEJAQAAAA==.',
Ka='Kaing:BAAALgAECgYJCwAAAA==.Kaissa:BAAALgAECgEJAQAAAA==.Kalena:BAACLgAFFH8LAAIHAAMJJgUuOwCwAAAHAAMJJgUuOwCwAAAuAAQKfz4AAgcACQnnDhliALsBAAcACQnnDhliALsBAAAA.Kalöna:BAAALgADCgEJAQAAAA==.Kandikkiss:BAAALgAECgUJDQAAAA==.Kaos:BAABLgAECn8jAAIHAAkJ+hFeXgDEAQAHAAkJ+hFeXgDEAQAAAA==.Kariatyda:BAABLgAECn8uAAINAAkJMxgIGwBlAgANAAkJMxgIGwBlAgAAAA==.Kasai:BAAALgADCgMJAwABLgAECgkJNwACAGgaAA==.Kassandra:BAACLgAFFH8VAAIHAAMJ2R4PKgD3AAAHAAMJ2R4PKgD3AAAuAAQKfz4AAgcACQnvHJkcALECAAcACQnvHJkcALECAAAA.Kay:BAAALgAECgcJCQAAAA==.Kayden:BAABLgAECn8aAAIWAAYJhBh2JACQAQAWAAYJhBh2JACQAQABLgAECggJGwADAFUcAA==.Kayn:BAAALgAECgIJAgAAAA==.',
Ke='Keelistus:BAAALgAECgQJBAAAAA==.Kekio:BAAALgAECgcJDAAAAA==.Kelisola:BAAALgADCgEJAQAAAA==.Kelzor:BAAALgAECgEJAQAAAA==.Keruu:BAAALgAECgcJBwAAAA==.',
Kh='Khaylorn:BAAALgAECgMJBgAAAA==.Kháòs:BAAALgAECgUJCgAAAA==.',
Ki='Kiloton:BAABLgAECn8uAAIZAAkJpRRyEwC+AQAZAAkJpRRyEwC+AQAAAA==.Kinari:BAABLgAECn8dAAQDAAkJbBh3AQBKAgADAAkJbBh3AQBKAgACAAEJkg0ISQAwAAARAAEJfwEmWgAbAAAAAA==.Kitzy:BAABLgAECn8sAAIHAAkJKwz1EAATAQAHAAkJKwz1EAATAQAAAA==.',
Kl='Klapso:BAAALgADCgYJDQAAAA==.Klippertdk:BAACLgAFFH8LAAIGAAMJBBFyOADaAAAGAAMJBBFyOADaAAAuAAQKfzkAAgYACQkrGRorAFQCAAYACQkrGRorAFQCAAAA.Klugamonk:BAAALgADCgUJBQAAAA==.Klutz:BAABLgAECn8qAAIYAAkJXw86NgDAAQAYAAkJXw86NgDAAQAAAA==.',
Ko='Kodiwa:BAAALgAECgYJBgAAAA==.Korgan:BAAALgAECggJDwAAAA==.Korgriku:BAAALgADCgMJAwAAAA==.',
Kr='Kreznor:BAAALgAECgIJAgAAAA==.',
Ku='Kurzo:BAACLgAFFH8OAAIJAAQJCx+LEACBAQAJAAQJCx+LEACBAQAuAAQKfzsAAwkACQnrIuIGAPACAAkACQnrIuIGAPACABMABQmtEussANoAAAAA.',
Ky='Kylarian:BAABLgAECn8iAAIIAAkJyQatKwAjAQAIAAkJyQatKwAjAQAAAA==.Kyntara:BAAALgAECgYJDQAAAA==.Kyronian:BAABLgAECn8UAAIHAAYJQQYcIQCWAAAHAAYJQQYcIQCWAAAAAA==.',
['Kâ']='Kâsâi:BAABLgAECn83AAICAAkJaBqJAwBYAgACAAkJaBqJAwBYAgAAAA==.',
La='Lachancea:BAAALgAECgEJAQABLgAECggJFgAhAAEaAA==.Lakshmee:BAAALgAECgcJDgAAAA==.',
Le='Ledarm:BAAALgAECggJEwAAAA==.Leigin:BAAALgADCgYJBgAAAA==.Lexxi:BAACLgAFFH8NAAICAAMJNA7TLAC+AAACAAMJNA7TLAC+AAAuAAQKfzoAAgIACQlCFdNDAPsBAAIACQlCFdNDAPsBAAAA.',
Li='Lifewing:BAAALgAECgUJDAAAAA==.Lightbehunt:BAAALgAECgQJBgAAAA==.Lightsglory:BAAALgADCgMJAwAAAA==.Lilly:BAAALgAECgYJCgAAAA==.Livaless:BAAALgADCgQJBAABLgAECgkJJgAhAFAiAA==.',
Lu='Lucialyn:BAAALgAECgcJDAABLgAECgcJFwAeAOojAA==.',
Ly='Lyllith:BAABLgAECn8cAAIjAAYJjREWDABkAQAjAAYJjREWDABkAQAAAA==.Lysende:BAAALgADCgQJBAAAAA==.',
Ma='Madamenoodle:BAAALgADCgkJCQAAAA==.Magnass:BAAALgADCgYJBgABLgAECgkJIAATAOIaAA==.Magnius:BAAALgADCgEJAQAAAA==.Mahidevran:BAAALgAECgQJBAABLgAECgkJKQAWAHMVAA==.Mahoa:BAAALgAECgEJAQAAAA==.Mal:BAAALgAECggJCAAAAA==.Mastablasta:BAAALgAECgQJCQAAAA==.Maursaline:BAABLgAECn8lAAIYAAkJqge7WgAnAQAYAAkJqge7WgAnAQAAAA==.Mawea:BAAALgAECgUJDAAAAA==.Mawks:BAACLgAFFH8LAAIUAAIJlRLdDQCXAAAUAAIJlRLdDQCXAAAuAAQKf0EAAhQACQktG6MLAGcCABQACQktG6MLAGcCAAAA.',
Mc='Mcstukes:BAAALgAECgQJCAAAAA==.',
Me='Medeas:BAAALgAECgUJCgAAAA==.Meragos:BAAALgAECgMJAwAAAA==.Meteor:BAAALgADCgQJBAAAAA==.',
Mi='Migz:BAAALgADCgEJAQAAAA==.Migzeviltwin:BAAALgAECgEJAgAAAA==.Mimicz:BAAALgADCgUJBQAAAA==.Minitry:BAAALgAECgEJAwAAAA==.Mixon:BAAALgAECgEJBAAAAA==.Mixxon:BAAALgAECgYJDwAAAA==.',
Mo='Moinion:BAAALgADCgQJCAAAAA==.Moldbreather:BAAALgAECgEJAQAAAA==.Moomooimacow:BAAALgAECgQJBAAAAA==.Moomoomonkey:BAABLgAECn8fAAIiAAkJMhfiHQDzAQAiAAkJMhfiHQDzAQAAAA==.Morhgana:BAAALgAECgYJDwAAAA==.',
Ms='Mstea:BAAALgAECgEJAQAAAA==.',
Mx='Mxmlxxix:BAABLgAECn8jAAMPAAgJygGXSwC1AAAPAAgJygGXSwC1AAABAAIJXwHWZQAtAAAAAA==.',
My='Mylosh:BAAALgAECgQJBAABLgAECgkJGAACAAwYAA==.',
['Mö']='Mördecai:BAAALgAECgQJBAAAAA==.',
Na='Naija:BAAALgAECgEJAgAAAA==.Nati:BAAALgAECgUJBQAAAA==.',
Ne='Nephele:BAAALgAECgEJAgAAAA==.Neptune:BAAALgAECgQJCAAAAA==.Newport:BAAALgAECgMJBAABLgAFFAMJCgAgAM4RAA==.',
Ni='Nikorobin:BAAALgAECgQJBwABLgAFFAgJHAAcAFYSAA==.Nilius:BAAALgAECgEJAQABLgAECgkJHAABACYfAA==.',
No='Noodles:BAAALgAECgcJCgABLgAECggJIgAcAH0WAA==.Norgalina:BAAALgADCgUJBQAAAA==.',
Ny='Nymara:BAABLgAECn8eAAIRAAgJ8RH+FgBpAQARAAgJ8RH+FgBpAQABLgAECgkJGAAKAIIcAA==.',
['Ní']='Níce:BAAALgAECgIJAwAAAA==.',
['Nü']='Nügs:BAABLgAECn8VAAIQAAgJeQvAfgDkAAAQAAgJeQvAfgDkAAAAAA==.Nüguns:BAAALgAECgcJEQAAAA==.',
Od='Odyssey:BAAALgAECgUJBQABLgAFFAMJCgAgAM4RAA==.',
Ol='Olei:BAAALgADCgUJBQAAAA==.',
Or='Orlick:BAAALgAECgEJAQAAAA==.Orrok:BAAALgADCgYJBwAAAA==.',
Pa='Painlink:BAAALgAECgUJCQABLgAECgkJKQAJAHkRAA==.Painnkiller:BAACLgAFFH8UAAINAAMJCBneJQDpAAANAAMJCBneJQDpAAAuAAQKfzgAAg0ACQnKHUkYAJUCAA0ACQnKHUkYAJUCAAAA.Papyto:BAAALgADCgYJBwAAAA==.Parsley:BAABLgAECn8qAAMLAAkJACLCAAAhAwALAAkJACLCAAAhAwAhAAMJmxmGwwDGAAAAAA==.Paxis:BAAALgAECgkJDgAAAA==.',
Pe='Perriwinkle:BAACLgAFFH8JAAIaAAMJDhCeBQC6AAAaAAMJDhCeBQC6AAAuAAQKf1MABBoACQkPH78DANECABoACQkPH78DANECABkACQkjE7YCAJgBABgABAk/DC2KAKMAAAAA.Perseus:BAAALgADCgMJAwAAAA==.',
Ph='Phission:BAAALgADCgEJAQAAAA==.Phobya:BAABLgAECn8nAAIYAAgJNBzWHABfAgAYAAgJNBzWHABfAgAAAA==.Phylloxeras:BAABLgAECn9OAAIGAAkJESbxAgBwAwAGAAkJESbxAgBwAwAAAA==.',
Pl='Pleasure:BAAALgADCgMJAwAAAA==.Pleggashroom:BAAALgADCgEJAQAAAA==.',
Po='Powder:BAAALgAECgMJAwAAAA==.Powders:BAABLgAECn81AAIHAAkJsRywKwBrAgAHAAkJsRywKwBrAgAAAA==.Powderysham:BAAALgAECgcJCwABLgAECgkJNQAHALEcAA==.',
Pr='Praystatiôn:BAAALgAECgEJAQABLgAECgcJGwAhAHcfAA==.Proshot:BAACLgAFFH8LAAIUAAMJtBv5BwD2AAAUAAMJtBv5BwD2AAAuAAQKfzMAAhQACQlYI90CABQDABQACQlYI90CABQDAAAA.',
Pu='Puddles:BAAALgAECgQJBAAAAA==.',
Pz='Pzalmo:BAAALgAECgUJBwABLgAECgkJHwAFAJkUAA==.',
Ra='Raccoon:BAACLgAFFH8LAAIhAAMJVwagMgCoAAAhAAMJVwagMgCoAAAuAAQKfz4AAyEACQmbEVxCANUBACEACQmbEVxCANUBAAsAAQloCxU+ADYAAAAA.Rahala:BAAALgAECgUJBQAAAA==.Ralor:BAAALgADCgEJAQAAAA==.Ravenhawk:BAAALgAECgYJEAAAAA==.Razza:BAAALgADCgYJCAAAAA==.',
Re='Remember:BAAALgADCgEJAQAAAA==.Renivatio:BAABLgAECn8uAAIGAAkJcBurAwAtAgAGAAkJcBurAwAtAgAAAA==.',
Rh='Rhyntix:BAAALgADCgEJAQAAAA==.',
Ro='Ronstådt:BAAALgADCgEJAQAAAA==.Roronoazoro:BAACLgAFFH8cAAIcAAgJVhJyFgD9AQAcAAgJVhJyFgD9AQAuAAQKfyEAAxwACQlIH2ojAH0CABwACQlIH2ojAH0CACYAAglxEwUmAFQAAAAA.',
Ry='Ryrin:BAABLgAECn8mAAMJAAkJBRAQNQB1AQAJAAkJBRAQNQB1AQAbAAQJMgpACQB+AAAAAA==.Ryrìn:BAAALgADCgEJAQAAAA==.Ryrín:BAAALgAECggJEwAAAA==.',
['Rë']='Rëggië:BAAALgAECgIJAwAAAA==.',
Sa='Samidrac:BAABLgAECn8eAAIMAAgJBANEBQCRAAAMAAgJBANEBQCRAAAAAA==.Sammidormu:BAABLgAECn8jAAQFAAgJ5RNoCgB5AQAFAAcJABVoCgB5AQAEAAcJbAtZNgAgAQAMAAEJ2QEPTgAjAAAAAA==.Sanderwoof:BAAALgAECggJCAAAAA==.Saret:BAAALgADCgMJAwAAAA==.Sarzul:BAABLgAECn8VAAMfAAYJ/A8VNADnAAAhAAYJ2gzAmwAiAQAfAAUJThEVNADnAAAAAA==.Satoshie:BAAALgAECggJCQAAAA==.Sayang:BAAALgAECgMJAwABLgAECgkJOAAYABsfAA==.',
Sc='Scerevisiae:BAABLgAECn8WAAMhAAgJARq9fQA9AQAhAAUJGx29fQA9AQAfAAQJxBSjLgABAQAAAA==.',
Se='Sedelis:BAABLgAECn8fAAIDAAkJzwr+MQCOAQADAAkJzwr+MQCOAQAAAA==.Sefirbrena:BAAALgADCgkJAwAAAA==.Selaya:BAAALgAECgEJAQAAAA==.Semnai:BAABLgAECn8+AAIYAAkJ+Bb/GwBnAgAYAAkJ+Bb/GwBnAgAAAA==.Serafín:BAACLgAFFH8OAAIKAAMJMge+EQChAAAKAAMJMge+EQChAAAuAAQKfzgAAgoACQmkDisiAJcBAAoACQmkDisiAJcBAAAA.Sevilicious:BAAALgADCgQJAwAAAA==.',
Sh='Shaay:BAAALgAFFAIJAgAAAA==.Shadowlock:BAAALgAECgEJAgAAAA==.Shadownutt:BAAALgAECgUJBQAAAA==.Shadowpyro:BAAALgAECgEJAQAAAA==.Shamwig:BAAALgADCgUJBQAAAA==.Shazzam:BAAALgAECggJEAAAAA==.Shieldwall:BAABLgAECn8qAAITAAgJWg/tGwBXAQATAAgJWg/tGwBXAQAAAA==.',
Si='Silanah:BAAALgAECgEJAQABLgAFFAQJEQAQAKIWAA==.Silbeb:BAAALgAECggJDQABLgAFFAQJHgANAP0fAA==.Silverhâwk:BAAALgADCgEJAQAAAA==.Sinastys:BAABLgAECn8aAAICAAgJ9RCWgQBsAQACAAgJ9RCWgQBsAQAAAA==.',
Sn='Snoots:BAAALgADCgEJAQAAAA==.',
So='Solone:BAABLgAECn8UAAIcAAYJ6w4tlAD4AAAcAAYJ6w4tlAD4AAAAAA==.Somavra:BAAALgAECgMJBgAAAA==.Sopidia:BAABLgAECn8lAAMQAAkJ+RV0PQC5AQAQAAgJTBV0PQC5AQAiAAUJHQatdACOAAAAAA==.Sorvato:BAABLgAECn85AAIcAAkJNRlRIgBIAgAcAAkJNRlRIgBIAgAAAA==.',
Sp='Spiritholy:BAAALgAECgkJBgAAAA==.Spoonzz:BAABLgAECn8xAAMOAAkJDSRlBQD7AgAOAAkJDSRlBQD7AgAKAAIJKx9TWQCkAAAAAA==.',
St='Stamavan:BAABLgAECn8kAAIZAAkJzCIjAwD6AgAZAAkJzCIjAwD6AgAAAA==.Starflayer:BAABLgAECn8nAAMcAAkJXxziJQA2AgAcAAkJbhviJQA2AgAmAAIJYxr3IAB8AAAAAA==.Steb:BAAALgADCgMJAwAAAA==.Sterjariger:BAAALgAECgYJBgABLgAFFAQJDQALAGwQAA==.',
Su='Sunari:BAAALgAECgMJBgAAAA==.Supermelon:BAABLgAECn8WAAIjAAcJXBFKDQBVAQAjAAcJXBFKDQBVAQAAAA==.',
Sw='Swenior:BAAALgAECgEJAQAAAA==.',
Sy='Syarli:BAAALgAECggJDAAAAA==.Sylvaeelor:BAAALgAFFAIJAwABLgAFFAQJDgAbAG4TAA==.Sylvanaria:BAACLgAFFH8OAAIQAAMJ0CUlDwAyAQAQAAMJ0CUlDwAyAQAuAAQKfz4AAhAACQlbJjoBAMMDABAACQlbJjoBAMMDAAAA.Sylvanaris:BAAALgAECgYJEQAAAA==.Systyx:BAABLgAECn8bAAIhAAcJdx/1TAC0AQAhAAcJdx/1TAC0AQAAAA==.',
Ta='Takura:BAAALgAECgkJBwABLgAECgkJDQAdAAAAAA==.Talenel:BAAALgAECgQJBAAAAA==.Talyzien:BAAALgADCgYJBwAAAA==.',
Te='Tealan:BAACLgAFFH8HAAMMAAQJugzLGgDpAAAMAAQJugzLGgDpAAAEAAEJRgLpawAvAAAuAAQKfzAAAwQACQm0GBwTAEYCAAQACQm0GBwTAEYCAAwACAmpEukcAJ4BAAAA.Tealyn:BAAALgAECgYJBwAAAA==.Teatree:BAAALgADCgUJBQAAAA==.Teluz:BAAALgAECgQJCgAAAA==.Tendra:BAAALgAECgYJBQAAAA==.Teronreborn:BAACLgAFFH8IAAIGAAMJHBoyKwAFAQAGAAMJHBoyKwAFAQAuAAQKfyUAAgYACQk6JYYUAAADAAYACQk6JYYUAAADAAAA.',
Th='Thaneer:BAAALgAECgYJBwAAAA==.Thanos:BAABLgAECn8dAAICAAYJ7Q6KpAA3AQACAAYJ7Q6KpAA3AQAAAA==.Thebadmage:BAAALgAECgcJBAAAAA==.Throstmok:BAACLgAFFH8SAAISAAQJTROkIQDcAAASAAQJTROkIQDcAAAuAAQKfzcAAhIACQm3Hq8JAHgCABIACQm3Hq8JAHgCAAAA.Thràll:BAAALgAECgUJBQAAAA==.Thränton:BAAALgAECgEJAQABLgAECgcJFAAmALwhAA==.Thumbalina:BAAALgAECgYJEQAAAA==.',
Ti='Tiantu:BAAALgAECgIJAgAAAA==.',
To='Tongra:BAAALgADCgQJBAABLgAECgkJIAAHAFgPAA==.Totemtuggér:BAAALgADCgIJAgAAAA==.',
Tp='Tpaste:BAAALgADCgcJBwAAAA==.',
Tr='Trampstãmp:BAAALgAECgIJAgAAAA==.Trinitea:BAAALgAECgYJCgAAAA==.Trout:BAAALgADCgYJDAABLgAECgYJCgAdAAAAAA==.Trovikk:BAAALgADCgUJBgAAAA==.',
Tu='Turg:BAAALgAECgMJAwABLgAECgQJBwAdAAAAAA==.Turgo:BAAALgAECgEJAQABLgAECgQJBwAdAAAAAA==.Turgress:BAAALgAECgQJBwAAAA==.',
['Tà']='Tàmber:BAAALgADCgYJBwAAAA==.',
Ub='Ubaubajuana:BAAALgADCgcJCgAAAA==.',
Ul='Ulfast:BAACLgAFFH8JAAIiAAMJRRR8FwC3AAAiAAMJRRR8FwC3AAAuAAQKfyUAAiIACAlKHrcaAAsCACIACAlKHrcaAAsCAAAA.',
Va='Valarios:BAAALgAECgYJCgAAAA==.Vannhellsing:BAABLgAECn8nAAIGAAgJJggwnwAtAQAGAAgJJggwnwAtAQAAAA==.Vanyel:BAABLgAECn9YAAIHAAkJBRqbBgC9AQAHAAkJBRqbBgC9AQAAAA==.Vaudorka:BAABLgAECn8cAAIFAAkJIx5RAwBnAgAFAAkJIx5RAwBnAgAAAA==.',
Ve='Vecna:BAAALgADCgMJAwABLgAECgYJCAAdAAAAAA==.Veliuz:BAAALgADCgQJBAAAAA==.Velrynth:BAABLgAECn84AAMeAAkJ+BSAEwBFAgAeAAkJVxSAEwBFAgAPAAcJzghySAAXAQAAAA==.Vemal:BAABLgAECn8yAAINAAkJThk9GwCCAgANAAkJThk9GwCCAgAAAA==.',
Vi='Vicieus:BAAALgAECgYJBgAAAA==.',
Vo='Vociferoy:BAACLgAFFH8YAAINAAMJ1R1WHQASAQANAAMJ1R1WHQASAQAuAAQKf0QAAg0ACQl9IUQPANYCAA0ACQl9IUQPANYCAAAA.Voidsteffan:BAACLgAFFH8GAAIfAAIJeAnJBwCAAAAfAAIJeAnJBwCAAAAuAAQKf0UAAx8ACQloG38AAFsCAB8ACQloG38AAFsCACEABAmPDiLBANcAAAAA.',
Vr='Vryadox:BAAALgAFFAIJAgABLgAFFAQJDwAhAGwdAA==.',
Vv='Vv:BAACLgAFFH9iAAIcAAkJsiYNAACVAwAcAAkJsiYNAACVAwAuAAQKfzUAAhwACQm1JucAANoDABwACQm1JucAANoDAAAA.',
Vz='Vz:BAAALgADCgUJBQAAAA==.',
Wh='Whoppin:BAAALgAECgIJAgAAAA==.',
Wi='Wiglimparms:BAAALgAECgIJAgAAAA==.',
Wr='Wry:BAAALgAECgMJAwAAAA==.',
Wy='Wysselbow:BAAALgADCggJDQAAAA==.',
['Wá']='Wárranpeace:BAAALgADCgMJAwAAAA==.',
Xa='Xalmo:BAAALgAECgEJAQABLgAECgkJHwAFAJkUAA==.Xalzi:BAAALgADCggJCQABLgAECgcJFAAQAHwVAA==.',
Xi='Xingwong:BAABLgAECn89AAIgAAkJ5yXXAQBNAwAgAAkJ5yXXAQBNAwAAAA==.',
Za='Zannytoes:BAABLgAECn8mAAMWAAkJpRA9MAC6AQAWAAkJpRA9MAC6AQAOAAEJLxFSnwAwAAAAAA==.',
Ze='Zead:BAAALgAECgEJBgAAAA==.Zerana:BAACLgAFFH8OAAIfAAQJmAT+CgDrAAAfAAQJmAT+CgDrAAAuAAQKfxgAAh8ACQlRD1wOAFcBAB8ACQlRD1wOAFcBAAAA.Zeriea:BAAALgADCgEJAQAAAA==.Zevtra:BAAALgADCgEJAQAAAA==.',
Zi='Zie:BAABLgAECn9aAAIBAAkJ8RswAgD0AQABAAkJ8RswAgD0AQAAAA==.Zikren:BAAALgAECgkJCQAAAA==.',
Zo='Zoumbadouwow:BAAALgAFFAEJAgABLgAECgkJOwAeAJQfAA==.',
Zs='Zsinj:BAAALgADCgEJAQAAAA==.',
['Ðo']='Ðonkle:BAABLgAECn8TAAIcAAgJmByzKwAZAgAcAAgJmByzKwAZAgAAAA==.',
['Ðr']='Ðrewid:BAAALgADCgEJAQAAAA==.',
['Ñi']='Ñice:BAACLgAFFH8bAAIJAAgJrSOoBwDqAQAJAAgJrSOoBwDqAQAuAAQKfxoAAgkACQkrHugYACcCAAkACQkrHugYACcCAAAA.',
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
