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

local lookup = {'Priest-Shadow','Paladin-Retribution','Paladin-Holy','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Unholy','Unknown-Unknown','Mage-Frost','DemonHunter-Havoc','Warrior-Fury','Monk-Brewmaster','Warlock-Affliction','Warlock-Destruction','Evoker-Preservation','Hunter-BeastMastery','Monk-Windwalker','Priest-Holy','Shaman-Restoration','Paladin-Protection','DeathKnight-Blood','Warrior-Protection','Hunter-Survival','Hunter-Marksmanship','Monk-Mistweaver','Druid-Balance','Druid-Restoration','Druid-Guardian','Druid-Feral','Warrior-Arms','DemonHunter-Devourer','Priest-Discipline','Rogue-Subtlety','Warlock-Demonology','Shaman-Elemental','Rogue-Assassination','Rogue-Outlaw','Shaman-Enhancement','DemonHunter-Vengeance','DeathKnight-Frost',}
local provider = {region='US',realm='Lightninghoof',name='US',type='weekly',zone=46,date='2026-08-04',data={Ab='Abukuma:BAAALgAECgQJBAAAAA==.',
Ac='Aceieus:BAAALgAECgkJAwAAAA==.',
Ad='Adraina:BAAALgADCgEJAQAAAA==.Adrewid:BAAALgADCgQJBAAAAA==.',
Ae='Aelarya:BAABLgAECn8RAAIBAAgJAQYXQgDpAAABAAgJAQYXQgDpAAAAAA==.Aenstalash:BAACLgAFFH8JAAMCAAQJxRbmHQAWAQACAAQJxRbmHQAWAQADAAIJAgfYHwBVAAAuAAQKfyEAAgIACAk/I0ckAHQCAAIACAk/I0ckAHQCAAAA.Aephium:BAABLgAECn8VAAMEAAcJuwZkYQC2AAAEAAYJJgZkYQC2AAAFAAUJtAQVHABsAAAAAA==.Aesilakaersi:BAAALgAECgYJCgAAAA==.Aeson:BAABLgAECn8kAAIGAAkJiBeVRQDyAQAGAAkJiBeVRQDyAQAAAA==.',
Af='Afflictia:BAAALgADCgYJEAAAAA==.',
Ai='Aironel:BAAALgADCgMJAwAAAA==.',
Al='Alanza:BAAALgAFFAIJAgAAAA==.Alaure:BAAALgAECgIJAgAAAA==.Alessia:BAAALgAECgIJAgAAAA==.Alfonso:BAAALgAECgEJAQAAAA==.Alfonsoo:BAAALgADCgEJAQABLgAECgEJAQAHAAAAAA==.Alida:BAAALgAECgQJBAAAAA==.Alistur:BAABLgAECn8mAAIIAAgJygvLHADtAAAIAAgJygvLHADtAAAAAA==.',
Am='Amoona:BAAALgAECgYJEgABLgAFFAIJBgAJAA8jAA==.',
An='Anaila:BAAALgAECgMJAwABLgAFFAYJFwAKACEcAA==.Anoriia:BAAALgADCgUJBQAAAA==.',
Ar='Arcnid:BAAALgADCgYJBgAAAA==.Arcomedes:BAAALgAECgEJAQAAAA==.Arfas:BAAALgADCgQJBAAAAA==.Arthraz:BAABLgAECn8kAAILAAkJsxwHDAB1AgALAAkJsxwHDAB1AgABLgAECgkJKgAMAAAiAA==.',
As='Astara:BAABLgAFFH8GAAIEAAUJIwT4IACkAAAEAAUJIwT4IACkAAABLgAFFAQJEQANALUHAA==.Astraa:BAAALgAECgIJAgAAAA==.Astrex:BAACLgAFFH8KAAIOAAIJ1w8GEwBwAAAOAAIJ1w8GEwBwAAAuAAQKf1gABA4ACQmZGLwAAIgCAA4ACQmZGLwAAIgCAAQABwkrA2gPAIAAAAUAAgm8BRMJADUAAAAA.',
Au='Aunaturale:BAAALgAECgkJAwAAAA==.Aurali:BAAALgAECgEJAQAAAA==.Aureliá:BAABLgAECn8ZAAIPAAcJvArCjAAlAQAPAAcJvArCjAAlAQAAAA==.',
['Aü']='Aütobot:BAABLgAECn8jAAIQAAkJjQ20JgCAAQAQAAkJjQ20JgCAAQAAAA==.',
Ba='Badgirl:BAACLgAFFH8MAAIRAAQJgREoGQDyAAARAAQJgREoGQDyAAAuAAQKfxkAAxEACAm+E9w1ACoBABEABgnBFtw1ACoBAAEABgktCuFLAOAAAAAA.Balnar:BAABLgAECn8gAAISAAcJEBdtDQBHAQASAAcJEBdtDQBHAQABLgAECggJJQATAP8YAA==.Balraga:BAABLgAECn8ZAAIJAAgJUQrjKwAhAQAJAAgJUQrjKwAhAQAAAA==.Bargrivyek:BAAALgAECgYJCQAAAA==.Bayded:BAAALgADCgEJAQAAAA==.',
Be='Beastboyy:BAAALgAECgUJBQAAAA==.Bega:BAACLgAFFH8uAAMGAAgJ9hpNDQB0AgAGAAgJ9hpNDQB0AgAUAAEJAABPUwAAAAAuAAQKf0EAAwYACQnoJXoFAE8DAAYACQnoJXoFAE8DABQABgkrFzslABUBAAAA.Benton:BAAALgAECgQJCAAAAA==.',
Bi='Bigglimpie:BAAALgAECgYJDQAAAA==.',
Bl='Blanc:BAAALgAECgYJBgAAAA==.Bloodchiefsr:BAAALgAECgEJAQAAAA==.Bloodlustplz:BAABLgAECn8qAAMKAAkJshdCLACjAQAKAAcJLx5CLACjAQAVAAgJLQ/NGwBYAQAAAA==.',
Bo='Bobster:BAABLgAECn8kAAIIAAkJuxHlYQC7AQAIAAkJuxHlYQC7AQAAAA==.Bonepaw:BAAALgAECgMJBQABLgAECgcJFAASAHwVAA==.Booyea:BAACLgAFFH8UAAIUAAQJ4hTWDgD8AAAUAAQJ4hTWDgD8AAAuAAQKfz4AAhQACQklHBMLAF8CABQACQklHBMLAF8CAAAA.',
Br='Brew:BAAALgAECgcJCwAAAA==.Brewwnor:BAAALgAECgkJEAAAAA==.Brickdemkeys:BAABLgAECn8fAAIIAAgJPBr/YwC2AQAIAAgJPBr/YwC2AQAAAA==.Brisfloggnaw:BAAALgAFFAEJAQAAAA==.',
Ca='Caladk:BAAALgADCgUJBQABLgAFFAkJOgAWABkkAA==.Calamuelis:BAACLgAFFH86AAQWAAkJGSS/AAB4AgAWAAcJMSO/AAB4AgAXAAcJ7hvWBwCeAQAPAAUJURxtFAB5AQAuAAQKfx0ABBcACAnSJLsNANcCABcACAmWJLsNANcCABYABAn5JIowACYBAA8AAQkIJhv2AGkAAAAA.Caliope:BAABLgAECn8qAAMYAAkJcxWfJQD3AQAYAAkJcxWfJQD3AQAQAAQJwwrFCwC3AAAAAA==.Capsasin:BAAALgADCgUJBQAAAA==.Carnage:BAAALgAFFAIJAwAAAA==.Cazlek:BAAALgAECgQJCwAAAA==.',
Ce='Celeith:BAAALgAECgEJAwAAAA==.Celery:BAAALgAECgQJBAABLgAECgkJKgAMAAAiAA==.Celldweller:BAAALgAECgYJCgAAAA==.Cerdred:BAABLgAECn8dAAIZAAUJARDLSQAEAQAZAAUJARDLSQAEAQAAAA==.Ceredis:BAAALgAECgEJAQAAAA==.Cerelus:BAABLgAECn8gAAIIAAkJWA9oVQDdAQAIAAkJWA9oVQDdAQAAAA==.',
Ch='Chaac:BAAALgAECggJEAABLgAECggJFgAOALITAA==.Chivana:BAAALgADCgMJAwAAAA==.Chmmr:BAAALgADCgMJAwAAAA==.Chowilawu:BAAALgADCgkJCQAAAA==.Chriswilsonn:BAAALgAECgQJCAAAAA==.Chuca:BAAALgAECgYJBgAAAA==.Chucalu:BAABLgAECn8WAAUaAAgJVh4ANwDLAQAaAAYJUyAANwDLAQAbAAQJCx7wEQBVAQAZAAIJih8+WgCqAAAcAAEJLwbeMgA2AAAAAA==.Chéwtoy:BAAALgAECgIJBAAAAA==.',
Cl='Clax:BAAALgAECgIJBQAAAA==.',
Co='Cobeam:BAAALgAECgYJEwAAAA==.Cohete:BAAALgADCgIJAgAAAA==.Cowpernicus:BAABLgAECn8iAAIaAAkJ7SAJBwBHAwAaAAkJ7SAJBwBHAwABLgAFFAQJEQASAKIWAA==.',
Cr='Crungleman:BAABLgAECn8YAAIPAAcJuRi1XwCIAQAPAAcJuRi1XwCIAQAAAA==.',
Ct='Cthuwu:BAAALgAECgQJBAABLgAECggJFgAOALITAA==.',
Cu='Curoi:BAABLgAECn8rAAMcAAkJjxeECABEAgAcAAkJjxeECABEAgAaAAgJRAozeQDsAAAAAA==.',
['Cã']='Cãrloy:BAACLgAFFH8sAAIKAAQJiBzdDABBAQAKAAQJiBzdDABBAQAuAAQKf1wAAwoACQmUIhwHAOwCAAoACQmUIhwHAOwCAB0AAgkpIexEALUAAAAA.',
['Cê']='Cêlestial:BAACLgAFFH8GAAMJAAIJDyPfDgC/AAAJAAIJEiLfDgC/AAAeAAIJRCFgcACpAAAuAAQKfzoAAwkACQk7JkoAAHoDAAkACQkwJkoAAHoDAB4ACAn1IuYbAG0CAAAA.',
Da='Daedalas:BAABLgAECn8cAAMBAAkJJh/uDgBqAgABAAkJJh/uDgBqAgARAAIJMAKAawA8AAAAAA==.Daedtoo:BAAALgAECgUJBQABLgAECgkJHAABACYfAA==.Damonk:BAAALgADCgYJBgABLgAECgkJIAAVAOIaAA==.Danevolent:BAABLgAECn8gAAMRAAcJ9yJ9DQCAAgARAAcJ9yJ9DQCAAgABAAQJEA0/YACYAAABLgAECgkJIAAVAOIaAA==.Danzaster:BAAALgADCgQJBAAAAA==.Darkxsoul:BAABLgAECn8lAAITAAgJ/xjlAgC4AQATAAgJ/xjlAgC4AQAAAA==.Darthgrogu:BAAALgAECgcJBwABLgAFFAQJEgACAAUXAA==.Darthknull:BAACLgAFFH8SAAICAAQJBRe8OAA7AQACAAQJBRe8OAA7AQAuAAQKfz4AAgIACQmQInAYALECAAIACQmQInAYALECAAAA.Darthreven:BAAALgADCgIJAgABLgAFFAQJEgACAAUXAA==.Darthtalon:BAAALgAECgkJDwABLgAFFAQJEgACAAUXAA==.',
De='Deadeyedicky:BAAALgAECgkJBwAAAA==.Deathmachine:BAAALgADCgUJBQAAAA==.Deathniight:BAAALgAECgUJBAAAAA==.Deathseer:BAAALgAECgcJDgAAAA==.Deathwood:BAAALgADCgYJCQABLgAECgEJAQAHAAAAAA==.Deatthdecay:BAAALgAECggJBAAAAA==.Deitrichx:BAABLgAECn8pAAIXAAkJnxmVBgApAgAXAAkJnxmVBgApAgAAAA==.Delley:BAAALgADCgEJAQAAAA==.Deminestra:BAAALgAECgQJBAAAAA==.Deminestrea:BAABLgAECn8bAAIUAAYJ/hGgKgADAQAUAAYJ/hGgKgADAQAAAA==.Demonswhere:BAAALgADCgQJBAAAAA==.Devilscreed:BAAALgAECgEJAQAAAA==.',
Di='Dingleberrys:BAAALgADCgEJAQAAAA==.Dippindots:BAAALgAECgYJCAAAAA==.Disshammy:BAAALgAFFAIJAgABLgAFFAgJIgAEANEhAA==.Dittoz:BAAALgADCgUJBAAAAA==.',
Do='Dolfcritler:BAAALgAECgQJBQAAAA==.Dolfcrittler:BAAALgADCgEJAQAAAA==.Donkform:BAAALgAECgkJEgAAAA==.Donniyii:BAAALgAECgcJCQABLgAECgkJPAAfAJQfAA==.Doomrider:BAAALgADCgYJBgAAAA==.Dottzz:BAABLgAECn8aAAINAAYJ8B27FQCcAQANAAYJ8B27FQCcAQAAAA==.',
Dr='Draconith:BAACLgAFFH8jAAIOAAYJqA/qCAA1AQAOAAYJqA/qCAA1AQAuAAQKfzcAAg4ACQmSG00FAMMCAA4ACQmSG00FAMMCAAAA.Dramoo:BAAALgAECgMJAwAAAA==.Draqkmar:BAABLgAECn8gAAIPAAYJCQxwJAC/AAAPAAYJCQxwJAC/AAAAAA==.Dreddwing:BAABLgAECn8WAAMOAAgJshOaEADCAQAOAAcJcBWaEADCAQAEAAIJJg8iewBrAAAAAA==.Dredfox:BAAALgAECgIJAgABLgAECgkJSwAZAHAUAA==.Drunkenoodle:BAAALgADCgYJBgAAAA==.',
Du='Dunsparrow:BAACLgAFFH8RAAISAAQJohYQQADkAAASAAQJohYQQADkAAAuAAQKf0cAAhIACQnfIkgFAF8DABIACQnfIkgFAF8DAAAA.Durgruk:BAAALgAECgEJAQABLgAFFAYJIwAOAKgPAA==.Durzul:BAAALgAECgEJAQAAAA==.',
Ei='Eightyone:BAAALgAECggJDwAAAA==.Eindraken:BAACLgAFFH8cAAIOAAUJCwqlDwCcAAAOAAUJCwqlDwCcAAAuAAQKfzkAAg4ACQn7EjENAP4BAA4ACQn7EjENAP4BAAAA.Eiroh:BAABLgAECn8YAAILAAkJghz2AQDpAQALAAkJghz2AQDpAQAAAA==.Eisis:BAACLgAFFH8KAAIcAAMJFwwRCACnAAAcAAMJFwwRCACnAAAuAAQKfz8AAhwACQlUEJUUAHoBABwACQlUEJUUAHoBAAAA.',
El='Elanalué:BAABLgAECn8VAAIBAAYJ/Q1fFACOAAABAAYJ/Q1fFACOAAABLgAECgkJKgAYAHMVAA==.',
Em='Emmie:BAAALgADCgQJBAAAAA==.',
En='Enamel:BAAALgAECgMJAwABLgAFFAMJCwAgAM4RAA==.',
Er='Erixee:BAAALgAECgUJBgAAAA==.Erroz:BAAALgADCgIJAQAAAA==.',
Es='Eshonäi:BAABLgAECn8aAAIhAAYJtRHRjgAdAQAhAAYJtRHRjgAdAQAAAA==.Espriesso:BAABLgAECn8VAAQfAAgJAQ1uMwBKAQAfAAcJ3wtuMwBKAQABAAQJvgSDZQCGAAARAAIJDAecdABWAAABLgAFFAIJAwAHAAAAAA==.',
Ev='Everbark:BAAALgADCgEJAQAAAA==.Evodragker:BAABLgAECn8kAAMEAAkJKxR2IQDOAQAEAAkJKxR2IQDOAQAOAAEJcAkEPAAzAAAAAA==.',
Fe='Feider:BAAALgAECgEJAQAAAA==.Felais:BAABLgAFFH8SAAIaAAYJTQ+bDABgAQAaAAYJTQ+bDABgAQAAAA==.Feldron:BAAALgAECgcJEwAAAA==.Felkaos:BAAALgADCgEJAQAAAA==.Fellura:BAAALgAECgYJDAAAAA==.Femaledawg:BAAALgADCgcJEAAAAA==.Femmefatale:BAAALgAFFAEJAQAAAA==.',
Fi='Fingor:BAAALgAECgYJBwAAAA==.Fivepal:BAAALgAECgcJEwAAAA==.',
Fl='Flamecube:BAAALgAECgEJAwAAAA==.Flashx:BAABLgAECn8kAAMDAAgJ3iDsCQDtAgADAAgJ3iDsCQDtAgACAAEJQQzbmQEvAAAAAA==.',
Fo='Foxxeyineawo:BAAALgADCgcJCAAAAA==.',
Fr='Frevmk:BAAALgAECgEJAgAAAA==.Frofrohunter:BAABLgAECn8sAAMPAAkJaB+kEgCiAgAPAAkJaB+kEgCiAgAXAAUJAxLZTgAUAQAAAA==.Frofrolock:BAAALgAECgcJDgAAAA==.Froggie:BAABLgAECn8UAAMSAAcJfBWfUQBsAQASAAcJfBWfUQBsAQAiAAMJXQ/iaACgAAAAAA==.Froshaman:BAAALgAECgEJAQAAAA==.',
Fu='Fuzywuuzy:BAACLgAFFH8VAAMaAAQJvRdIDwAoAQAaAAQJvRdIDwAoAQAZAAEJYxBgLQA3AAAuAAQKfyUAAxoACAnUI+ELAAIDABoACAnUI+ELAAIDABkABwk6Fv4nAJABAAAA.',
Ga='Gazdorn:BAABLgAECn8qAAIVAAkJeRJ8EgDDAQAVAAkJeRJ8EgDDAQAAAA==.',
Ge='Genebelcher:BAAALgAECgEJAQAAAA==.',
Gh='Ghost:BAABLgAECn8kAAIjAAkJOhyiBQAbAgAjAAkJOhyiBQAbAgAAAA==.',
Gi='Gigof:BAABLgAECn8rAAMZAAkJPxJ7JQCgAQAZAAgJ0RJ7JQCgAQAaAAcJ/AqZggC0AAAAAA==.',
Gl='Glissa:BAABLgAECn8UAAQMAAcJdCWRAQDTAgAMAAcJEiWRAQDTAgAhAAMJhSJYogAUAQANAAIJjxpcRACkAAAAAA==.',
Go='Gobah:BAABLgAECn8YAAMgAAgJ5hXRGQDLAQAgAAgJ5hXRGQDLAQAkAAUJsQctFwCmAAAAAA==.',
Gt='Gt:BAAALgAFFAMJBAAAAA==.',
Gu='Gulldan:BAABLgAECn8iAAIhAAgJXxjCNgD+AQAhAAgJXxjCNgD+AQAAAA==.',
Gw='Gwyndolin:BAAALgADCgUJBQAAAA==.',
Ha='Habanero:BAAALgAECgQJBgABLgAECgkJKgAMAAAiAA==.Hadory:BAABLgAECn8YAAMCAAkJDBg0UgDSAQACAAkJDBg0UgDSAQADAAQJWhm6SwAMAQAAAA==.Harrowhark:BAABLgAECn9BAAQMAAkJUwo9EgBEAQAhAAkJhgnSYAB+AQAMAAgJuwk9EgBEAQANAAQJyQVDMgBVAAAAAA==.',
He='Hellzzdemon:BAABLgAECn8pAAIJAAkJFxMsBACzAQAJAAkJFxMsBACzAQAAAA==.Hendricks:BAAALgAECgQJCgAAAA==.Hexinverter:BAAALgAECgQJCQAAAA==.Hexzard:BAAALgADCgQJBAABLgAECgYJEwAHAAAAAA==.Hezekiiah:BAAALgAECgYJDQAAAA==.',
Ho='Holeecow:BAAALgADCgIJAgABLgAFFAQJEQASAKIWAA==.Holycannoli:BAABLgAECn8VAAICAAkJ0Bn4CgCqAQACAAkJ0Bn4CgCqAQAAAA==.Horiffic:BAAALgAFFAMJAwAAAA==.Horok:BAAALgAECgYJDQAAAA==.Hotsforthots:BAAALgAECgUJBQAAAA==.Hottea:BAAALgAECgEJAwAAAA==.Hotwheels:BAAALgAECgMJAwAAAA==.',
Hu='Hubert:BAABLgAECn8WAAIYAAgJwQkYVwAVAQAYAAgJwQkYVwAVAQAAAA==.Hubertdale:BAAALgAECgMJAwAAAA==.Hulkblood:BAAALgAECgEJAQAAAA==.Hummingbrook:BAAALgAECgcJDAABLgAFFAkJHQAeAH8SAA==.',
Hy='Hypandia:BAAALgAFFAEJAQABLgAFFAQJEQASAKIWAA==.',
Ic='Ichaerus:BAAALgAECgQJBQABLgAECgkJHAABACYfAA==.Ichtheblack:BAAALgAECgcJCgABLgAECgkJHAABACYfAA==.Ichtu:BAAALgAECgEJAQABLgAECgkJHAABACYfAA==.',
Ii='Iilli:BAABLgAECn88AAMfAAkJlB9fBwAGAwAfAAkJlB9fBwAGAwABAAkJnxvzDQB2AgAAAA==.',
In='Inagard:BAAALgAECgQJBAAAAA==.Inari:BAABLgAECn8XAAIBAAkJSgt5LAByAQABAAkJSgt5LAByAQAAAA==.Inkkubus:BAACLgAFFH8kAAQhAAgJgxXFEgChAQAhAAcJgxXFEgChAQANAAMJPwzlDgC8AAAMAAIJUxYYHwBSAAAuAAQKfxcABCEACQmPHuU6AO8BACEABwnZH+U6AO8BAA0AAwnpG74WAO4AAAwAAQkAABEnAFUAAAAA.Instagatorz:BAAALgADCgUJBgAAAA==.',
Iq='Iq:BAAALgAECgEJAQAAAA==.',
Ir='Ironfur:BAAALgAECgUJBQABLgAFFAYJGAADAHARAA==.',
Iw='Iwkms:BAACLgAFFH8OAAIcAAQJihaWCAAhAQAcAAQJihaWCAAhAQAuAAQKfyMAAhwACAliIzMCADEDABwACAliIzMCADEDAAEuAAUUBQkGACQAwhYA.',
Ja='Jade:BAABLgAECn8dAAILAAYJ9CTwFQD9AQALAAYJ9CTwFQD9AQAAAA==.Jatheo:BAAALgADCgIJAgAAAA==.',
Je='Jenliz:BAAALgADCgEJAQABLgAECgYJEQAHAAAAAA==.Jeronor:BAAALgAECgIJAgAAAA==.',
Ji='Jigtide:BAAALgAECgEJAQAAAA==.Jimmick:BAABLgAECn8WAAISAAcJfyNXEQDEAgASAAcJfyNXEQDEAgABLgAECgkJGAACAAwYAA==.Jisung:BAABLgAECn8UAAMlAAYJkQLCKwCbAAAlAAYJkQLCKwCbAAAiAAIJHAE9xgARAAAAAA==.',
Jo='Jorad:BAAALgADCgEJAQAAAA==.',
Jt='Jtheman:BAAALgAECgQJBAAAAA==.',
Ju='Junebugg:BAAALgADCgEJAQAAAA==.',
Ka='Kaing:BAAALgAECgYJCwAAAA==.Kaissa:BAAALgAECgEJAQAAAA==.Kalena:BAACLgAFFH8OAAIIAAMJkAWnRgCuAAAIAAMJkAWnRgCuAAAuAAQKfz4AAggACQnnDhliALsBAAgACQnnDhliALsBAAAA.Kalöna:BAAALgADCgEJAQAAAA==.Kandikkiss:BAAALgAECgUJDQAAAA==.Kaos:BAABLgAECn8jAAIIAAkJ+hFeXgDEAQAIAAkJ+hFeXgDEAQAAAA==.Kariatyda:BAABLgAECn8uAAIPAAkJMxgIGwBlAgAPAAkJMxgIGwBlAgAAAA==.Kasai:BAAALgADCgMJAwABLgAECgkJPwACAJYaAA==.Kassandra:BAACLgAFFH8ZAAIIAAQJvhrKJgA5AQAIAAQJvhrKJgA5AQAuAAQKfz4AAggACQnvHJkcALECAAgACQnvHJkcALECAAAA.Kay:BAAALgAECgcJCQAAAA==.Kayden:BAABLgAECn8aAAIYAAYJhBh2JACQAQAYAAYJhBh2JACQAQABLgAECggJGwADAFUcAA==.Kayn:BAAALgAECgIJAgAAAA==.',
Ke='Keelistus:BAAALgAECgQJBAAAAA==.Kekio:BAAALgAECgcJDAAAAA==.Keleloth:BAAALgADCgEJAQAAAA==.Kelisola:BAAALgADCgEJAQAAAA==.Kelzor:BAAALgAECgEJAQAAAA==.Keruu:BAAALgAECgcJBwAAAA==.',
Kh='Khaylorn:BAAALgAECgMJBgAAAA==.Kháòs:BAAALgAECgUJCgAAAA==.',
Ki='Kiloton:BAABLgAECn80AAIbAAkJ6BSYBAB1AQAbAAkJ6BSYBAB1AQAAAA==.Kinari:BAABLgAECn8dAAQDAAkJbBg2AgBUAgADAAkJbBg2AgBUAgACAAEJkg1yYgAsAAATAAEJfwEmWgAbAAAAAA==.Kitzy:BAABLgAECn8sAAIIAAkJKwyqFwATAQAIAAkJKwyqFwATAQAAAA==.',
Kl='Klapso:BAAALgADCgYJDQAAAA==.Klippertdk:BAACLgAFFH8TAAIGAAQJ0xd+JwAzAQAGAAQJ0xd+JwAzAQAuAAQKfzoAAgYACQkrGRorAFQCAAYACQkrGRorAFQCAAAA.Klugamonk:BAAALgADCgUJBQAAAA==.Klutz:BAABLgAECn8qAAIaAAkJXw86NgDAAQAaAAkJXw86NgDAAQAAAA==.',
Ko='Kodiwa:BAAALgAECgYJBgAAAA==.Korgan:BAAALgAECggJDwAAAA==.Korgriku:BAAALgADCgMJAwAAAA==.',
Kr='Kreznor:BAAALgAECgIJAgAAAA==.',
Ku='Kurzo:BAACLgAFFH8XAAIKAAYJIRwOCQCDAQAKAAYJIRwOCQCDAQAuAAQKfzsAAwoACQnrIuIGAPACAAoACQnrIuIGAPACABUABQmtEussANoAAAAA.',
Ky='Kylarian:BAABLgAECn8iAAIJAAkJyQatKwAjAQAJAAkJyQatKwAjAQAAAA==.Kyntara:BAAALgAECgYJDQAAAA==.Kyronian:BAABLgAECn8cAAIIAAcJywj+HADsAAAIAAcJywj+HADsAAAAAA==.',
['Kâ']='Kâsâi:BAABLgAECn8/AAICAAkJlhpRBQBRAgACAAkJlhpRBQBRAgAAAA==.',
['Kã']='Kãsãi:BAAALgAECgYJBgABLgAECgkJPwACAJYaAA==.',
La='Lachancea:BAAALgAECgEJAQABLgAECgkJFwAhAKIaAA==.Lakshmee:BAAALgAECgcJDgAAAA==.',
Le='Ledarm:BAAALgAECggJEwAAAA==.Leigin:BAAALgADCgYJBgAAAA==.Lexxi:BAACLgAFFH8TAAICAAQJBxIBIQAIAQACAAQJBxIBIQAIAQAuAAQKfzoAAgIACQlCFdNDAPsBAAIACQlCFdNDAPsBAAAA.',
Li='Lifewing:BAAALgAECgUJDAAAAA==.Lightbehunt:BAAALgAECgQJBgAAAA==.Lightsglory:BAAALgADCgMJAwAAAA==.Lilly:BAAALgAECgYJCgAAAA==.Livaless:BAAALgADCgQJBAABLgAECgkJJgAhAFAiAA==.',
Lu='Lucialyn:BAAALgAECgcJDAABLgAECgcJFwAfAOojAA==.Lucifur:BAAALgAECgMJAwABLgAECgkJLgAUAOsWAA==.',
Ly='Lyllith:BAABLgAECn8cAAIjAAYJjREWDABkAQAjAAYJjREWDABkAQAAAA==.Lysende:BAAALgADCgQJBAAAAA==.',
Ma='Madamenoodle:BAAALgADCgkJCQAAAA==.Magnass:BAAALgADCgYJBgABLgAECgkJIAAVAOIaAA==.Magnius:BAAALgADCgEJAQAAAA==.Mahidevran:BAAALgAECgQJBwABLgAECgkJKgAYAHMVAA==.Mahoa:BAAALgAECgEJAQAAAA==.Mal:BAAALgAECggJCAAAAA==.Mastablasta:BAAALgAECgQJCQAAAA==.Maursaline:BAABLgAECn8lAAIaAAkJqge7WgAnAQAaAAkJqge7WgAnAQAAAA==.Mawea:BAAALgAECgUJDAAAAA==.Mawks:BAACLgAFFH8OAAMWAAMJrA81EACaAAAWAAIJ0BM1EACaAAAPAAEJZAcdegA9AAAuAAQKf0IAAhYACQktG6MLAGcCABYACQktG6MLAGcCAAAA.',
Mc='Mcstukes:BAAALgAECgQJCAAAAA==.',
Me='Medeas:BAAALgAECgUJCgAAAA==.Meragos:BAAALgAECgMJAwAAAA==.Meteor:BAAALgADCgQJBAAAAA==.',
Mi='Migz:BAAALgADCgEJAQAAAA==.Migzeviltwin:BAAALgAECgIJAwAAAA==.Mimicz:BAAALgADCgUJBQAAAA==.Minitry:BAAALgAECgEJAwAAAA==.Mixon:BAAALgAECgEJBAAAAA==.Mixxon:BAAALgAECgYJDwAAAA==.',
Mo='Moinion:BAAALgADCgQJCAAAAA==.Moisten:BAAALgAECgIJAgAAAA==.Moldbreather:BAAALgAECgEJAQAAAA==.Moomooimacow:BAAALgAECgQJBAAAAA==.Moomoomonkey:BAABLgAECn8fAAIiAAkJMhfiHQDzAQAiAAkJMhfiHQDzAQAAAA==.Morhgana:BAAALgAECgYJDwAAAA==.',
Ms='Mstea:BAAALgAECgEJAgAAAA==.',
Mx='Mxmlxxix:BAABLgAECn8jAAMRAAgJygGXSwC1AAARAAgJygGXSwC1AAABAAIJXwHWZQAtAAAAAA==.',
My='Mylosh:BAAALgAECgQJBAABLgAECgkJGAACAAwYAA==.',
['Mö']='Mördecai:BAAALgAECgQJBAAAAA==.',
Na='Naija:BAAALgAECgEJAgAAAA==.Nati:BAAALgAECgUJBQAAAA==.',
Ne='Nephele:BAAALgAECgEJAgAAAA==.Neptune:BAAALgAECgQJCAAAAA==.Neremian:BAAALgAECgEJAQAAAA==.Newport:BAAALgAECgMJBAABLgAFFAMJCwAgAM4RAA==.',
Ni='Nikorobin:BAAALgAECgQJBwABLgAFFAkJHQAeAH8SAA==.Nilius:BAAALgAECgEJAQABLgAECgkJHAABACYfAA==.',
No='Noodles:BAAALgAECgcJCwABLgAECggJIgAeAH0WAA==.Norgalina:BAAALgADCgUJBQAAAA==.',
Ny='Nymara:BAABLgAECn8eAAITAAgJ8RH+FgBpAQATAAgJ8RH+FgBpAQABLgAECgkJGAALAIIcAA==.',
['Ní']='Níce:BAAALgAECgIJAwAAAA==.',
['Nü']='Nügs:BAABLgAECn8VAAISAAgJeQvAfgDkAAASAAgJeQvAfgDkAAAAAA==.Nüguns:BAABLgAECn8VAAIUAAcJbwxOLQDzAAAUAAcJbwxOLQDzAAAAAA==.',
Oc='Occan:BAAALgAECgUJBQAAAA==.',
Od='Odyssey:BAAALgAECgUJBQABLgAFFAMJCwAgAM4RAA==.',
Ol='Olei:BAAALgADCgUJBQAAAA==.',
On='Ontos:BAAALgAECgMJAwAAAA==.',
Or='Orlick:BAAALgAECgEJAQAAAA==.Orrok:BAAALgADCgYJBwAAAA==.',
Pa='Painlink:BAAALgAECgUJCQABLgAECgkJKQAKAHkRAA==.Painnkiller:BAACLgAFFH8aAAIPAAQJ6hnMGABSAQAPAAQJ6hnMGABSAQAuAAQKfzgAAg8ACQnKHUkYAJUCAA8ACQnKHUkYAJUCAAAA.Papyto:BAAALgADCgYJBwAAAA==.Parsley:BAABLgAECn8qAAMMAAkJACLCAAAhAwAMAAkJACLCAAAhAwAhAAMJmxmGwwDGAAAAAA==.Paxis:BAAALgAECgkJDgAAAA==.',
Pe='Perriwinkle:BAACLgAFFH8JAAIcAAMJDhCbBwCxAAAcAAMJDhCbBwCxAAAuAAQKf1sABBwACQkPH78DANECABwACQkPH78DANECABsACQkxFrsCANgBABoABAk/DC2KAKMAAAAA.Perseus:BAAALgADCgMJAwAAAA==.',
Ph='Phission:BAAALgADCgEJAQAAAA==.Phobya:BAABLgAECn8nAAIaAAgJNBzWHABfAgAaAAgJNBzWHABfAgAAAA==.Phucau:BAAALgAECgEJAQAAAA==.Phylloxeras:BAABLgAECn9OAAIGAAkJESbxAgBwAwAGAAkJESbxAgBwAwAAAA==.',
Pl='Pleasure:BAAALgADCgMJAwAAAA==.Pleggashroom:BAAALgADCgEJAQAAAA==.',
Po='Powder:BAAALgAECgMJAwAAAA==.Powders:BAABLgAECn81AAIIAAkJsRywKwBrAgAIAAkJsRywKwBrAgAAAA==.Powderysham:BAAALgAECgcJCwABLgAECgkJNQAIALEcAA==.',
Pr='Praystatiôn:BAAALgAECgEJAQABLgAECgcJGwAhAHcfAA==.Proshot:BAACLgAFFH8SAAIWAAQJoBzkAwB7AQAWAAQJoBzkAwB7AQAuAAQKfzQAAhYACQlYI90CABQDABYACQlYI90CABQDAAAA.',
Pu='Puddles:BAAALgAECgQJBAAAAA==.',
Pz='Pzalmo:BAAALgAECgUJBwABLgAECgkJHwAFAJkUAA==.',
Ra='Raccoon:BAACLgAFFH8OAAIhAAMJVwbxOwCjAAAhAAMJVwbxOwCjAAAuAAQKfz4AAyEACQmbEVxCANUBACEACQmbEVxCANUBAAwAAQloCxU+ADYAAAAA.Rahala:BAAALgAECgUJBQAAAA==.Ralor:BAAALgADCgEJAQAAAA==.Ravenhawk:BAAALgAECgYJEAAAAA==.Razza:BAAALgADCgYJCAAAAA==.',
Re='Remember:BAAALgADCgEJAQAAAA==.Renivatio:BAABLgAECn8uAAIGAAkJcBtzBQAjAgAGAAkJcBtzBQAjAgAAAA==.',
Rh='Rhyntix:BAAALgADCgEJAQAAAA==.',
Ri='Rivet:BAAALgAECgcJDQABLgAFFAUJJgAPAEsgAA==.',
Ro='Ronstådt:BAAALgADCgEJAQAAAA==.Roronoazoro:BAACLgAFFH8dAAIeAAkJfxJyFgD9AQAeAAkJfxJyFgD9AQAuAAQKfyEAAx4ACQlIH2ojAH0CAB4ACQlIH2ojAH0CACYAAglxEwUmAFQAAAAA.',
Ry='Ryrin:BAABLgAECn8mAAMKAAkJBRAQNQB1AQAKAAkJBRAQNQB1AQAdAAQJMgobDgB5AAAAAA==.Ryrìn:BAAALgADCgEJAQAAAA==.Ryrín:BAAALgAECggJEwAAAA==.',
['Rë']='Rëggië:BAAALgAECgIJAwAAAA==.',
Sa='Samidrac:BAABLgAECn8eAAIOAAgJBANUBwCdAAAOAAgJBANUBwCdAAAAAA==.Sammidormu:BAABLgAECn8jAAQFAAgJ5RNoCgB5AQAFAAcJABVoCgB5AQAEAAcJbAtZNgAgAQAOAAEJ2QEPTgAjAAAAAA==.Sanderwoof:BAAALgAECggJCAAAAA==.Saret:BAAALgADCgMJAwAAAA==.Sarzul:BAABLgAECn8VAAMNAAYJ/A8VNADnAAAhAAYJ2gzAmwAiAQANAAUJThEVNADnAAAAAA==.Satoshie:BAAALgAECggJCQAAAA==.Sayang:BAAALgAECgMJAwABLgAECgkJOAAaABsfAA==.',
Sc='Scerevisiae:BAABLgAECn8XAAMhAAkJohoOFgC8AAANAAQJxBSjLgABAQAhAAYJfh0OFgC8AAAAAA==.',
Se='Sedelis:BAABLgAECn8fAAIDAAkJzwr+MQCOAQADAAkJzwr+MQCOAQAAAA==.Sefirbrena:BAAALgADCgkJAwAAAA==.Selaya:BAAALgAECgEJAQAAAA==.Semnai:BAABLgAECn8+AAIaAAkJ+Bb/GwBnAgAaAAkJ+Bb/GwBnAgAAAA==.Serafín:BAACLgAFFH8UAAILAAQJHgcXEQDEAAALAAQJHgcXEQDEAAAuAAQKfzgAAgsACQmkDisiAJcBAAsACQmkDisiAJcBAAAA.Sevilicious:BAAALgADCgQJAwAAAA==.',
Sh='Shaay:BAAALgAFFAIJAgAAAA==.Shadowlock:BAAALgAECgEJAgAAAA==.Shadownutt:BAAALgAECgUJBQAAAA==.Shadowpyro:BAAALgAECgEJAQAAAA==.Shamwig:BAAALgADCgUJBQAAAA==.Shazzam:BAAALgAECggJEAAAAA==.Shiana:BAAALgADCgkJCQAAAA==.Shieldwall:BAABLgAECn8qAAIVAAgJWg/tGwBXAQAVAAgJWg/tGwBXAQAAAA==.',
Si='Silanah:BAAALgAECgEJAQABLgAFFAQJEQASAKIWAA==.Silbeb:BAAALgAECggJEwABLgAFFAUJJgAPAEsgAA==.Silverhâwk:BAAALgADCgEJAQAAAA==.Sinastys:BAABLgAECn8aAAICAAgJ9RCWgQBsAQACAAgJ9RCWgQBsAQAAAA==.',
Sn='Snoots:BAAALgADCgEJAQAAAA==.',
So='Solone:BAABLgAECn8UAAIeAAYJ6w4tlAD4AAAeAAYJ6w4tlAD4AAAAAA==.Somavra:BAAALgAECgMJBgAAAA==.Sopidia:BAABLgAECn8lAAMSAAkJ+RV0PQC5AQASAAgJTBV0PQC5AQAiAAUJHQatdACOAAAAAA==.Sorvato:BAABLgAECn85AAIeAAkJNRlRIgBIAgAeAAkJNRlRIgBIAgAAAA==.',
Sp='Spiritholy:BAAALgAECgkJBgAAAA==.Spoonzz:BAABLgAECn8xAAMQAAkJDSRlBQD7AgAQAAkJDSRlBQD7AgALAAIJKx9TWQCkAAAAAA==.',
St='Stamavan:BAABLgAECn8kAAIbAAkJzCIjAwD6AgAbAAkJzCIjAwD6AgAAAA==.Starflayer:BAABLgAECn8nAAMeAAkJXxziJQA2AgAeAAkJbhviJQA2AgAmAAIJYxr3IAB8AAAAAA==.Steb:BAAALgADCgMJAwAAAA==.Sterjariger:BAAALgAECgYJBgABLgAFFAUJBQASAAMOAA==.',
Su='Sunari:BAAALgAECgMJBgAAAA==.Supermelon:BAABLgAECn8WAAIjAAcJXBFKDQBVAQAjAAcJXBFKDQBVAQAAAA==.',
Sy='Syarli:BAAALgAECggJDAAAAA==.Sylvaeelor:BAAALgAFFAIJAwABLgAFFAQJDgAdAG4TAA==.Sylvanaria:BAACLgAFFH8UAAISAAQJWSOADQB4AQASAAQJWSOADQB4AQAuAAQKfz4AAhIACQlbJjoBAMMDABIACQlbJjoBAMMDAAAA.Sylvanaris:BAAALgAECgYJEQAAAA==.Systyx:BAABLgAECn8bAAIhAAcJdx/1TAC0AQAhAAcJdx/1TAC0AQAAAA==.',
Ta='Talenel:BAAALgAECgQJBAAAAA==.Talyzien:BAAALgADCgYJBwAAAA==.',
Te='Tealan:BAACLgAFFH8HAAMOAAQJugzLGgDpAAAOAAQJugzLGgDpAAAEAAEJRgLpawAvAAAuAAQKfzAAAwQACQm0GBwTAEYCAAQACQm0GBwTAEYCAA4ACAmpEukcAJ4BAAAA.Tealani:BAAALgAECgMJBgAAAA==.Tealyn:BAAALgAECgYJDgAAAA==.Teatree:BAAALgADCgYJBgAAAA==.Teluz:BAAALgAECgQJCgAAAA==.Tendra:BAAALgAECgYJBQAAAA==.Teronreborn:BAACLgAFFH8MAAMGAAMJpBpbOADyAAAGAAMJpBpbOADyAAAnAAEJiRTjGgBJAAAuAAQKfyUAAgYACQk6JYYUAAADAAYACQk6JYYUAAADAAAA.Tezara:BAAALgADCgEJAQAAAA==.',
Th='Thaneer:BAAALgAECgYJBwAAAA==.Thanos:BAABLgAECn8dAAICAAYJ7Q6KpAA3AQACAAYJ7Q6KpAA3AQAAAA==.Thebadmage:BAAALgAECgcJBAAAAA==.Throstmok:BAACLgAFFH8bAAIUAAYJJRKIDAAlAQAUAAYJJRKIDAAlAQAuAAQKfzcAAhQACQm3Hq8JAHgCABQACQm3Hq8JAHgCAAAA.Thràll:BAAALgAECgUJBQAAAA==.Thränton:BAAALgAECgEJAQABLgAECgcJFAAmALwhAA==.Thumbalina:BAAALgAECgYJEQAAAA==.',
Ti='Tiantu:BAAALgAECgIJAgAAAA==.',
To='Tongra:BAAALgAECgEJAQABLgAECgkJIAAIAFgPAA==.Totemtuggér:BAAALgADCgIJAgAAAA==.',
Tp='Tpaste:BAAALgADCgcJBwAAAA==.',
Tr='Trampstãmp:BAAALgAECgIJAgAAAA==.Trinitea:BAAALgAECgYJCwAAAA==.Trout:BAAALgADCgYJDAABLgAECgYJCgAHAAAAAA==.Trovikk:BAAALgADCgUJBgAAAA==.',
Tu='Turg:BAAALgAECgMJAwABLgAECgQJBwAHAAAAAA==.Turgo:BAAALgAECgEJAQABLgAECgQJBwAHAAAAAA==.Turgress:BAAALgAECgQJBwAAAA==.',
['Tà']='Tàmber:BAAALgADCgYJBwAAAA==.',
Ub='Ubaubajuana:BAAALgAECgYJDQAAAA==.',
Ul='Ulfast:BAACLgAFFH8PAAIiAAQJsxSZFAD0AAAiAAQJsxSZFAD0AAAuAAQKfyUAAiIACAlKHrcaAAsCACIACAlKHrcaAAsCAAAA.',
Va='Valarios:BAAALgAECgYJCgAAAA==.Vannhellsing:BAABLgAECn83AAIGAAkJhxHGBwDMAQAGAAkJhxHGBwDMAQAAAA==.Vanyel:BAABLgAECn9YAAIIAAkJBRoqCgC2AQAIAAkJBRoqCgC2AQAAAA==.Vaudorka:BAABLgAECn8cAAIFAAkJIx5RAwBnAgAFAAkJIx5RAwBnAgAAAA==.',
Ve='Vecna:BAAALgADCgMJAwABLgAECgYJCAAHAAAAAA==.Veliuz:BAAALgADCgQJBAAAAA==.Velrynth:BAABLgAECn84AAMfAAkJ+BSAEwBFAgAfAAkJVxSAEwBFAgARAAcJzghySAAXAQAAAA==.Vemal:BAABLgAECn8yAAIPAAkJThk9GwCCAgAPAAkJThk9GwCCAgAAAA==.',
Vi='Vicieus:BAAALgAECgYJDgAAAA==.',
Vo='Vociferoy:BAACLgAFFH8iAAIPAAQJsRpbFgBmAQAPAAQJsRpbFgBmAQAuAAQKf0QAAg8ACQl9IUQPANYCAA8ACQl9IUQPANYCAAAA.Voidsteffan:BAACLgAFFH8GAAINAAIJeAloCgB4AAANAAIJeAloCgB4AAAuAAQKf0UAAw0ACQloG70AAGMCAA0ACQloG70AAGMCACEABAmPDiLBANcAAAAA.',
Vr='Vryadox:BAAALgAFFAIJAgABLgAFFAQJEAAhAGwdAA==.',
Vv='Vv:BAACLgAFFH91AAIeAAkJ3yYjAACRAwAeAAkJ3yYjAACRAwAuAAQKfzUAAh4ACQm1JucAANoDAB4ACQm1JucAANoDAAAA.',
Vz='Vz:BAAALgADCgUJBQAAAA==.',
Wh='Whoppin:BAAALgAECgIJAgAAAA==.',
Wi='Wiglimparms:BAAALgAECgIJAgAAAA==.',
Wr='Wry:BAAALgAECgMJAwAAAA==.',
Wy='Wysselbow:BAAALgADCggJDQAAAA==.',
['Wá']='Wárranpeace:BAAALgADCgMJAwAAAA==.',
Xa='Xalmo:BAAALgAECgEJAQABLgAECgkJHwAFAJkUAA==.Xalzi:BAAALgADCggJCQABLgAECgcJFAASAHwVAA==.',
Xi='Xingwong:BAABLgAECn89AAIgAAkJ5yXXAQBNAwAgAAkJ5yXXAQBNAwAAAA==.',
Za='Zannytoes:BAABLgAECn8mAAMYAAkJpRA9MAC6AQAYAAkJpRA9MAC6AQAQAAEJLxFSnwAwAAAAAA==.',
Ze='Zead:BAAALgAECgEJBwAAAA==.Zerana:BAACLgAFFH8RAAINAAQJtQf+CgDrAAANAAQJtQf+CgDrAAAuAAQKfxgAAg0ACQlRD1wOAFcBAA0ACQlRD1wOAFcBAAAA.Zeriea:BAAALgADCgEJAQAAAA==.Zevtra:BAAALgADCgEJAQAAAA==.',
Zi='Zie:BAABLgAECn9aAAIBAAkJ8RuFAwDnAQABAAkJ8RuFAwDnAQAAAA==.Zikren:BAAALgAECgkJCQAAAA==.',
Zo='Zoumbadouwow:BAAALgAFFAEJAgABLgAECgkJPAAfAJQfAA==.',
Zs='Zsinj:BAAALgADCgEJAQAAAA==.',
['Çe']='Çelestial:BAAALgAFFAEJAQABLgAFFAIJBgAJAA8jAA==.',
['Ðo']='Ðonkle:BAABLgAECn8TAAIeAAgJmByzKwAZAgAeAAgJmByzKwAZAgAAAA==.',
['Ðr']='Ðrewid:BAAALgADCgEJAQAAAA==.',
['Ñi']='Ñice:BAACLgAFFH8dAAIKAAgJrSOoBwDqAQAKAAgJrSOoBwDqAQAuAAQKfxoAAgoACQkrHugYACcCAAoACQkrHugYACcCAAAA.',
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
