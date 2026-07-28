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

local lookup = {'Priest-Shadow','Paladin-Retribution','Paladin-Holy','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Unholy','Mage-Frost','DemonHunter-Havoc','Warrior-Fury','Monk-Brewmaster','Warlock-Affliction','Warlock-Destruction','Evoker-Preservation','Hunter-BeastMastery','Monk-Windwalker','Priest-Holy','Shaman-Restoration','Paladin-Protection','DeathKnight-Blood','Warrior-Protection','Hunter-Survival','Hunter-Marksmanship','Monk-Mistweaver','Druid-Balance','Druid-Restoration','Druid-Guardian','Druid-Feral','Warrior-Arms','DemonHunter-Devourer','Unknown-Unknown','Rogue-Subtlety','Warlock-Demonology','Priest-Discipline','Shaman-Elemental','Rogue-Assassination','Rogue-Outlaw','Shaman-Enhancement','DemonHunter-Vengeance',}
local provider = {region='US',realm='Lightninghoof',name='US',type='weekly',zone=46,date='2026-07-28',data={Ab='Abukuma:BAAALgAECgQJBAAAAA==.',
Ac='Aceieus:BAAALgAECgkJAwAAAA==.',
Ad='Adraina:BAAALgADCgEJAQAAAA==.Adrewid:BAAALgADCgQJBAAAAA==.',
Ae='Aelarya:BAABLgAECn8RAAIBAAgJAQYXQgDpAAABAAgJAQYXQgDpAAAAAA==.Aenstalash:BAACLgAFFH8IAAMCAAMJURhoLADUAAACAAMJURhoLADUAAADAAIJAgeqHgBVAAAuAAQKfyEAAgIACAk/I0ckAHQCAAIACAk/I0ckAHQCAAAA.Aephium:BAABLgAECn8VAAMEAAcJuwZkYQC2AAAEAAYJJgZkYQC2AAAFAAUJtAQVHABsAAAAAA==.Aesilakaersi:BAAALgAECgYJCgAAAA==.Aeson:BAABLgAECn8kAAIGAAkJiBeVRQDyAQAGAAkJiBeVRQDyAQAAAA==.',
Af='Afflictia:BAAALgADCgYJEAAAAA==.',
Ai='Aironel:BAAALgADCgMJAwAAAA==.',
Al='Alanza:BAAALgAFFAIJAgAAAA==.Alaure:BAAALgAECgIJAgAAAA==.Alessia:BAAALgAECgIJAgAAAA==.Alfonsoo:BAAALgADCgEJAQAAAA==.Alida:BAAALgAECgQJBAAAAA==.Alistur:BAABLgAECn8mAAIHAAgJyguwGgDtAAAHAAgJyguwGgDtAAAAAA==.',
Am='Amoona:BAAALgAECgYJEgABLgAFFAIJBgAIAA8jAA==.',
An='Anaila:BAAALgAECgMJAwABLgAFFAUJFgAJAD8hAA==.Anoriia:BAAALgADCgUJBQAAAA==.',
Ar='Arcnid:BAAALgADCgYJBgAAAA==.Arcomedes:BAAALgAECgEJAQAAAA==.Arfas:BAAALgADCgQJBAAAAA==.Arthraz:BAABLgAECn8kAAIKAAkJsxwHDAB1AgAKAAkJsxwHDAB1AgABLgAECgkJKgALAAAiAA==.',
As='Astara:BAABLgAFFH8FAAIEAAQJYgOkKAB3AAAEAAQJYgOkKAB3AAABLgAFFAQJEQAMALUHAA==.Astraa:BAAALgAECgIJAgAAAA==.Astrex:BAACLgAFFH8KAAINAAIJ1w9IEgBxAAANAAIJ1w9IEgBxAAAuAAQKf1gABA0ACQmZGKcAAIcCAA0ACQmZGKcAAIcCAAQABwkrA44OAIEAAAUAAgm8BU8IADcAAAAA.',
Au='Aunaturale:BAAALgAECgkJAwAAAA==.Aurali:BAAALgAECgEJAQAAAA==.Aureliá:BAABLgAECn8ZAAIOAAcJvArCjAAlAQAOAAcJvArCjAAlAQAAAA==.',
['Aü']='Aütobot:BAABLgAECn8jAAIPAAkJjQ20JgCAAQAPAAkJjQ20JgCAAQAAAA==.',
Ba='Badgirl:BAACLgAFFH8MAAIQAAQJgREoGQDyAAAQAAQJgREoGQDyAAAuAAQKfxkAAxAACAm+E9w1ACoBABAABgnBFtw1ACoBAAEABgktCuFLAOAAAAAA.Balnar:BAABLgAECn8gAAIRAAcJEBdzDABFAQARAAcJEBdzDABFAQABLgAECggJJQASAP8YAA==.Balraga:BAABLgAECn8ZAAIIAAgJUQrjKwAhAQAIAAgJUQrjKwAhAQAAAA==.Bargrivyek:BAAALgAECgYJCQAAAA==.Bayded:BAAALgADCgEJAQAAAA==.',
Be='Beastboyy:BAAALgAECgUJBQAAAA==.Bega:BAACLgAFFH8uAAMGAAgJ9hpNDQB0AgAGAAgJ9hpNDQB0AgATAAEJAABPUwAAAAAuAAQKf0EAAwYACQnoJXoFAE8DAAYACQnoJXoFAE8DABMABgkrFzslABUBAAAA.Benton:BAAALgAECgQJCAAAAA==.',
Bi='Bigglimpie:BAAALgAECgYJDQAAAA==.',
Bl='Blanc:BAAALgADCgEJAQAAAA==.Bloodchiefsr:BAAALgAECgEJAQAAAA==.Bloodlustplz:BAABLgAECn8qAAMJAAkJshdCLACjAQAJAAcJLx5CLACjAQAUAAgJLQ/NGwBYAQAAAA==.',
Bo='Bobster:BAABLgAECn8kAAIHAAkJuxHlYQC7AQAHAAkJuxHlYQC7AQAAAA==.Bonepaw:BAAALgAECgMJBQABLgAECgcJFAARAHwVAA==.Booyea:BAACLgAFFH8RAAITAAMJIxnBEQDIAAATAAMJIxnBEQDIAAAuAAQKfz4AAhMACQklHBMLAF8CABMACQklHBMLAF8CAAAA.',
Br='Brew:BAAALgAECgcJCwAAAA==.Brewwnor:BAAALgAECgkJEAAAAA==.Brickdemkeys:BAABLgAECn8fAAIHAAgJPBr/YwC2AQAHAAgJPBr/YwC2AQAAAA==.Brisfloggnaw:BAAALgAFFAEJAQAAAA==.',
Ca='Caladk:BAAALgADCgUJBQABLgAFFAkJNQAVABkkAA==.Calamuelis:BAACLgAFFH81AAQVAAkJGSSlAACBAgAVAAcJMSOlAACBAgAWAAcJ7hvWBwCeAQAOAAUJTxvMEgB+AQAuAAQKfx0ABBYACAnSJLsNANcCABYACAmWJLsNANcCABUABAn5JIowACYBAA4AAQkIJhv2AGkAAAAA.Caliope:BAABLgAECn8qAAMXAAkJcxWfJQD3AQAXAAkJcxWfJQD3AQAPAAQJwwr+CgC3AAAAAA==.Capsasin:BAAALgADCgUJBQAAAA==.Carnage:BAAALgAFFAIJAgAAAA==.Cazlek:BAAALgAECgQJCwAAAA==.',
Ce='Celeith:BAAALgAECgEJAgAAAA==.Celery:BAAALgAECgQJBAABLgAECgkJKgALAAAiAA==.Celldweller:BAAALgAECgYJCgAAAA==.Cerdred:BAABLgAECn8dAAIYAAUJARDLSQAEAQAYAAUJARDLSQAEAQAAAA==.Ceredis:BAAALgAECgEJAQAAAA==.Cerelus:BAABLgAECn8gAAIHAAkJWA9oVQDdAQAHAAkJWA9oVQDdAQAAAA==.',
Ch='Chaac:BAAALgAECggJEAABLgAECggJFgANALITAA==.Chivana:BAAALgADCgMJAwAAAA==.Chmmr:BAAALgADCgMJAwAAAA==.Chowilawu:BAAALgADCgkJCQAAAA==.Chriswilsonn:BAAALgAECgQJCAAAAA==.Chuca:BAAALgAECgYJBgAAAA==.Chucalu:BAABLgAECn8WAAUZAAgJVh4ANwDLAQAZAAYJUyAANwDLAQAaAAQJCx7wEQBVAQAYAAIJih8+WgCqAAAbAAEJLwbeMgA2AAAAAA==.Chéwtoy:BAAALgAECgIJBAAAAA==.',
Cl='Clax:BAAALgAECgIJBQAAAA==.',
Co='Cobeam:BAAALgAECgYJEwAAAA==.Cowpernicus:BAABLgAECn8iAAIZAAkJ7SAJBwBHAwAZAAkJ7SAJBwBHAwABLgAFFAQJEQARAKIWAA==.',
Cr='Crungleman:BAABLgAECn8YAAIOAAcJuRi1XwCIAQAOAAcJuRi1XwCIAQAAAA==.',
Ct='Cthuwu:BAAALgAECgQJBAABLgAECggJFgANALITAA==.',
Cu='Curoi:BAABLgAECn8rAAMbAAkJjxeECABEAgAbAAkJjxeECABEAgAZAAgJRAozeQDsAAAAAA==.',
['Cã']='Cãrloy:BAACLgAFFH8pAAIJAAQJlBv2GwBBAQAJAAQJlBv2GwBBAQAuAAQKf1wAAwkACQmUIhwHAOwCAAkACQmUIhwHAOwCABwAAgkpIexEALUAAAAA.',
['Cê']='Cêlestial:BAACLgAFFH8GAAMIAAIJDyMuDgDAAAAIAAIJEiIuDgDAAAAdAAIJRCFgcACpAAAuAAQKfzoAAwgACQk7JkEAAH0DAAgACQkwJkEAAH0DAB0ACAn1IuYbAG0CAAAA.',
Da='Daedalas:BAABLgAECn8cAAMBAAkJJh/uDgBqAgABAAkJJh/uDgBqAgAQAAIJMAKAawA8AAAAAA==.Daedtoo:BAAALgAECgUJBQABLgAECgkJHAABACYfAA==.Damonk:BAAALgADCgYJBgABLgAECgkJIAAUAOIaAA==.Danevolent:BAABLgAECn8gAAMQAAcJ9yJ9DQCAAgAQAAcJ9yJ9DQCAAgABAAQJEA0/YACYAAABLgAECgkJIAAUAOIaAA==.Danzaster:BAAALgADCgQJBAAAAA==.Darkxsoul:BAABLgAECn8lAAISAAgJ/xiaAgC7AQASAAgJ/xiaAgC7AQAAAA==.Darthknull:BAACLgAFFH8SAAICAAQJBRe8OAA7AQACAAQJBRe8OAA7AQAuAAQKfz0AAgIACQnxIXAYALECAAIACQnxIXAYALECAAAA.Darthtalon:BAAALgAECgkJDgABLgAFFAQJEgACAAUXAA==.',
De='Deadeyedicky:BAAALgAECgkJBwAAAA==.Deathmachine:BAAALgADCgUJBQAAAA==.Deathniight:BAAALgAECgUJBAAAAA==.Deathseer:BAAALgAECgcJDgAAAA==.Deathwood:BAAALgADCgUJBgABLgAECgEJAQAeAAAAAA==.Deatthdecay:BAAALgAECggJBAAAAA==.Deitrichx:BAABLgAECn8pAAIWAAkJnxmVBgApAgAWAAkJnxmVBgApAgAAAA==.Delley:BAAALgADCgEJAQAAAA==.Deminestra:BAAALgAECgQJBAAAAA==.Deminestrea:BAABLgAECn8bAAITAAYJ/hGgKgADAQATAAYJ/hGgKgADAQAAAA==.Demonswhere:BAAALgADCgQJBAAAAA==.Devilscreed:BAAALgAECgEJAQAAAA==.',
Di='Dingleberrys:BAAALgADCgEJAQAAAA==.Dippindots:BAAALgAECgYJCAAAAA==.Disshammy:BAAALgAFFAIJAgABLgAFFAgJIgAEANEhAA==.Dittoz:BAAALgADCgUJBAAAAA==.',
Do='Dolfcritler:BAAALgAECgQJBQAAAA==.Dolfcrittler:BAAALgADCgEJAQAAAA==.Donkform:BAAALgAECgkJEgAAAA==.Donniyii:BAAALgAECgcJCAABLgAFFAEJAgAeAAAAAA==.Doomrider:BAAALgADCgYJBgAAAA==.Dottzz:BAABLgAECn8aAAIMAAYJ8B27FQCcAQAMAAYJ8B27FQCcAQAAAA==.',
Dr='Draconith:BAACLgAFFH8jAAINAAYJqA9TCAA/AQANAAYJqA9TCAA/AQAuAAQKfzcAAg0ACQmSG00FAMMCAA0ACQmSG00FAMMCAAAA.Dramoo:BAAALgAECgMJAwAAAA==.Draqkmar:BAABLgAECn8gAAIOAAYJCQzQIQDAAAAOAAYJCQzQIQDAAAAAAA==.Dreddwing:BAABLgAECn8WAAMNAAgJshOaEADCAQANAAcJcBWaEADCAQAEAAIJJg8iewBrAAAAAA==.Dredfox:BAAALgAECgIJAgABLgAECgkJSwAYAHAUAA==.Drunkenoodle:BAAALgADCgYJBgAAAA==.',
Du='Dunsparrow:BAACLgAFFH8RAAIRAAQJohYQQADkAAARAAQJohYQQADkAAAuAAQKf0cAAhEACQnfIkgFAF8DABEACQnfIkgFAF8DAAAA.Durgruk:BAAALgAECgEJAQABLgAFFAYJIwANAKgPAA==.Durzul:BAAALgAECgEJAQAAAA==.',
Ei='Eightyone:BAAALgAECggJDwAAAA==.Eindraken:BAACLgAFFH8cAAINAAUJCwozDwCeAAANAAUJCwozDwCeAAAuAAQKfzkAAg0ACQn7EjENAP4BAA0ACQn7EjENAP4BAAAA.Eiroh:BAABLgAECn8YAAIKAAkJghzOAQDrAQAKAAkJghzOAQDrAQAAAA==.Eisis:BAACLgAFFH8KAAIbAAMJFwylBwCpAAAbAAMJFwylBwCpAAAuAAQKfz8AAhsACQlUEJUUAHoBABsACQlUEJUUAHoBAAAA.',
El='Elanalué:BAABLgAECn8VAAIBAAYJ/Q2mEgCPAAABAAYJ/Q2mEgCPAAABLgAECgkJKgAXAHMVAA==.',
Em='Emmie:BAAALgADCgQJBAAAAA==.',
En='Enamel:BAAALgAECgMJAwABLgAFFAMJCwAfAM4RAA==.',
Er='Erixee:BAAALgAECgUJBgAAAA==.Erroz:BAAALgADCgIJAQAAAA==.',
Es='Eshonäi:BAABLgAECn8aAAIgAAYJtRHRjgAdAQAgAAYJtRHRjgAdAQAAAA==.Espriesso:BAABLgAECn8VAAQhAAgJAQ1uMwBKAQAhAAcJ3wtuMwBKAQABAAQJvgSDZQCGAAAQAAIJDAecdABWAAABLgAFFAIJAwAeAAAAAA==.',
Ev='Everbark:BAAALgADCgEJAQAAAA==.Evodragker:BAABLgAECn8kAAMEAAkJKxR2IQDOAQAEAAkJKxR2IQDOAQANAAEJcAkEPAAzAAAAAA==.',
Fe='Feider:BAAALgAECgEJAQAAAA==.Felais:BAABLgAFFH8RAAIZAAUJlBATDwAfAQAZAAUJlBATDwAfAQAAAA==.Feldron:BAAALgAECgcJEwAAAA==.Felkaos:BAAALgADCgEJAQAAAA==.Fellura:BAAALgAECgYJDAAAAA==.Femaledawg:BAAALgADCgcJEAAAAA==.',
Fi='Fingor:BAAALgAECgYJBwAAAA==.Fivepal:BAAALgAECgcJEwAAAA==.',
Fl='Flamecube:BAAALgAECgEJAwAAAA==.Flashx:BAABLgAECn8kAAMDAAgJ3iDsCQDtAgADAAgJ3iDsCQDtAgACAAEJQQzbmQEvAAAAAA==.',
Fo='Foxxeyineawo:BAAALgADCgcJCAAAAA==.',
Fr='Frevmk:BAAALgAECgEJAgAAAA==.Frofrohunter:BAABLgAECn8sAAMOAAkJaB+kEgCiAgAOAAkJaB+kEgCiAgAWAAUJAxLZTgAUAQAAAA==.Frofrolock:BAAALgAECgcJDgAAAA==.Froggie:BAABLgAECn8UAAMRAAcJfBWfUQBsAQARAAcJfBWfUQBsAQAiAAMJXQ/iaACgAAAAAA==.Froshaman:BAAALgAECgEJAQAAAA==.',
Fu='Fuzywuuzy:BAACLgAFFH8SAAMZAAMJ6xxGEQD2AAAZAAMJ6xxGEQD2AAAYAAEJYxA5KwA3AAAuAAQKfyUAAxkACAnUI+ELAAIDABkACAnUI+ELAAIDABgABwk6Fv4nAJABAAAA.',
Ga='Gazdorn:BAABLgAECn8qAAIUAAkJeRJ8EgDDAQAUAAkJeRJ8EgDDAQAAAA==.',
Ge='Genebelcher:BAAALgAECgEJAQAAAA==.',
Gh='Ghost:BAABLgAECn8kAAIjAAkJOhyiBQAbAgAjAAkJOhyiBQAbAgAAAA==.',
Gi='Gigof:BAABLgAECn8rAAMYAAkJPxJ7JQCgAQAYAAgJ0RJ7JQCgAQAZAAcJ/AqZggC0AAAAAA==.',
Gl='Glissa:BAABLgAECn8UAAQLAAcJdCWRAQDTAgALAAcJEiWRAQDTAgAgAAMJhSJYogAUAQAMAAIJjxpcRACkAAAAAA==.',
Go='Gobah:BAABLgAECn8YAAMfAAgJ5hXRGQDLAQAfAAgJ5hXRGQDLAQAkAAUJsQctFwCmAAAAAA==.',
Gt='Gt:BAAALgAFFAMJBAAAAA==.',
Gu='Gulldan:BAABLgAECn8iAAIgAAgJXxjCNgD+AQAgAAgJXxjCNgD+AQAAAA==.',
Gw='Gwyndolin:BAAALgADCgUJBQAAAA==.',
Ha='Habanero:BAAALgAECgQJBgABLgAECgkJKgALAAAiAA==.Hadory:BAABLgAECn8YAAMCAAkJDBg0UgDSAQACAAkJDBg0UgDSAQADAAQJWhm6SwAMAQAAAA==.Harrowhark:BAABLgAECn9BAAQLAAkJUwo9EgBEAQAgAAkJhgnSYAB+AQALAAgJuwk9EgBEAQAMAAQJyQVDMgBVAAAAAA==.',
He='Hellzzdemon:BAABLgAECn8pAAIIAAkJFxPZAwCwAQAIAAkJFxPZAwCwAQAAAA==.Hendricks:BAAALgAECgQJCgAAAA==.Hexinverter:BAAALgAECgQJCQAAAA==.Hexzard:BAAALgADCgQJBAABLgAECgYJEwAeAAAAAA==.Hezekiiah:BAAALgAECgYJDQAAAA==.',
Ho='Holeecow:BAAALgADCgIJAgABLgAFFAQJEQARAKIWAA==.Holycannoli:BAABLgAECn8VAAICAAkJ0BkHCgCqAQACAAkJ0BkHCgCqAQAAAA==.Horiffic:BAAALgAFFAMJAwAAAA==.Horok:BAAALgAECgYJDQAAAA==.Hotsforthots:BAAALgAECgUJBQAAAA==.Hottea:BAAALgAECgEJAgAAAA==.Hotwheels:BAAALgAECgMJAwAAAA==.',
Hu='Hubert:BAABLgAECn8WAAIXAAgJwQkYVwAVAQAXAAgJwQkYVwAVAQAAAA==.Hubertdale:BAAALgAECgMJAwAAAA==.Hulkblood:BAAALgAECgEJAQAAAA==.Hummingbrook:BAAALgAECgcJDAABLgAFFAgJHAAdAFYSAA==.',
Hy='Hypandia:BAAALgAFFAEJAQABLgAFFAQJEQARAKIWAA==.',
Ic='Ichaerus:BAAALgAECgQJBQABLgAECgkJHAABACYfAA==.Ichtheblack:BAAALgAECgcJCgABLgAECgkJHAABACYfAA==.Ichtu:BAAALgAECgEJAQABLgAECgkJHAABACYfAA==.',
Ii='Iilli:BAABLgAECn88AAMhAAkJlB9fBwAGAwAhAAkJlB9fBwAGAwABAAkJnxvzDQB2AgABLgAFFAEJAgAeAAAAAA==.',
In='Inagard:BAAALgAECgQJBAAAAA==.Inari:BAABLgAECn8XAAIBAAkJSgt5LAByAQABAAkJSgt5LAByAQAAAA==.Inkkubus:BAACLgAFFH8jAAQgAAgJOhPgGABQAQAgAAYJPhbgGABQAQAMAAMJPwzlDgC8AAALAAIJUxYYHwBSAAAuAAQKfxcABCAACQmPHuU6AO8BACAABwnZH+U6AO8BAAwAAwnpG74WAO4AAAsAAQkAABEnAFUAAAAA.Instagatorz:BAAALgADCgUJBgAAAA==.',
Iq='Iq:BAAALgAECgEJAQAAAA==.',
Ir='Ironfur:BAAALgAECgUJBQABLgAFFAYJFQADAHARAA==.',
Iw='Iwkms:BAACLgAFFH8OAAIbAAQJihaWCAAhAQAbAAQJihaWCAAhAQAuAAQKfyMAAhsACAliIzMCADEDABsACAliIzMCADEDAAEuAAUUBQkGACQAwhYA.',
Ja='Jade:BAABLgAECn8dAAIKAAYJ9CTwFQD9AQAKAAYJ9CTwFQD9AQAAAA==.Jatheo:BAAALgADCgIJAgAAAA==.',
Je='Jenliz:BAAALgADCgEJAQABLgAECgYJEQAeAAAAAA==.Jeronor:BAAALgAECgIJAgAAAA==.',
Ji='Jigtide:BAAALgAECgEJAQAAAA==.Jimmick:BAABLgAECn8WAAIRAAcJfyNXEQDEAgARAAcJfyNXEQDEAgABLgAECgkJGAACAAwYAA==.Jisung:BAABLgAECn8UAAMlAAYJkQLCKwCbAAAlAAYJkQLCKwCbAAAiAAIJHAE9xgARAAAAAA==.',
Jo='Jorad:BAAALgADCgEJAQAAAA==.',
Jt='Jtheman:BAAALgAECgQJBAAAAA==.',
Ju='Junebugg:BAAALgADCgEJAQAAAA==.',
Ka='Kaing:BAAALgAECgYJCwAAAA==.Kaissa:BAAALgAECgEJAQAAAA==.Kalena:BAACLgAFFH8OAAIHAAMJkAVPRACuAAAHAAMJkAVPRACuAAAuAAQKfz4AAgcACQnnDhliALsBAAcACQnnDhliALsBAAAA.Kalöna:BAAALgADCgEJAQAAAA==.Kandikkiss:BAAALgAECgUJDQAAAA==.Kaos:BAABLgAECn8jAAIHAAkJ+hFeXgDEAQAHAAkJ+hFeXgDEAQAAAA==.Kariatyda:BAABLgAECn8uAAIOAAkJMxgIGwBlAgAOAAkJMxgIGwBlAgAAAA==.Kasai:BAAALgADCgMJAwABLgAECgkJPwACAJYaAA==.Kassandra:BAACLgAFFH8WAAIHAAMJ2R7aMwDsAAAHAAMJ2R7aMwDsAAAuAAQKfz4AAgcACQnvHJkcALECAAcACQnvHJkcALECAAAA.Kay:BAAALgAECgcJCQAAAA==.Kayden:BAABLgAECn8aAAIXAAYJhBh2JACQAQAXAAYJhBh2JACQAQABLgAECggJGwADAFUcAA==.Kayn:BAAALgAECgIJAgAAAA==.',
Ke='Keelistus:BAAALgAECgQJBAAAAA==.Kekio:BAAALgAECgcJDAAAAA==.Kelisola:BAAALgADCgEJAQAAAA==.Kelzor:BAAALgAECgEJAQAAAA==.Keruu:BAAALgAECgcJBwAAAA==.',
Kh='Khaylorn:BAAALgAECgMJBgAAAA==.Kháòs:BAAALgAECgUJCgAAAA==.',
Ki='Kiloton:BAABLgAECn80AAIaAAkJ6BRCBAB2AQAaAAkJ6BRCBAB2AQAAAA==.Kinari:BAABLgAECn8dAAQDAAkJbBgDAgBRAgADAAkJbBgDAgBRAgACAAEJkg35WQAwAAASAAEJfwEmWgAbAAAAAA==.Kitzy:BAABLgAECn8sAAIHAAkJKwz3FQATAQAHAAkJKwz3FQATAQAAAA==.',
Kl='Klapso:BAAALgADCgYJDQAAAA==.Klippertdk:BAACLgAFFH8QAAIGAAMJSxf9OgDkAAAGAAMJSxf9OgDkAAAuAAQKfzoAAgYACQkrGRorAFQCAAYACQkrGRorAFQCAAAA.Klugamonk:BAAALgADCgUJBQAAAA==.Klutz:BAABLgAECn8qAAIZAAkJXw86NgDAAQAZAAkJXw86NgDAAQAAAA==.',
Ko='Kodiwa:BAAALgAECgYJBgAAAA==.Korgan:BAAALgAECggJDwAAAA==.Korgriku:BAAALgADCgMJAwAAAA==.',
Kr='Kreznor:BAAALgAECgIJAgAAAA==.',
Ku='Kurzo:BAACLgAFFH8WAAIJAAUJPyGLEACBAQAJAAUJPyGLEACBAQAuAAQKfzsAAwkACQnrIuIGAPACAAkACQnrIuIGAPACABQABQmtEussANoAAAAA.',
Ky='Kylarian:BAABLgAECn8iAAIIAAkJyQatKwAjAQAIAAkJyQatKwAjAQAAAA==.Kyntara:BAAALgAECgYJDQAAAA==.Kyronian:BAABLgAECn8bAAIHAAcJjQguGwDpAAAHAAcJjQguGwDpAAAAAA==.',
['Kâ']='Kâsâi:BAABLgAECn8/AAICAAkJlhrNBABUAgACAAkJlhrNBABUAgAAAA==.',
['Kã']='Kãsãi:BAAALgAECgYJBgABLgAECgkJPwACAJYaAA==.',
La='Lachancea:BAAALgAECgEJAQABLgAECgkJFwAgAKIaAA==.Lakshmee:BAAALgAECgcJDgAAAA==.',
Le='Ledarm:BAAALgAECggJEwAAAA==.Leigin:BAAALgADCgYJBgAAAA==.Lexxi:BAACLgAFFH8QAAICAAMJbxGoMgDCAAACAAMJbxGoMgDCAAAuAAQKfzoAAgIACQlCFdNDAPsBAAIACQlCFdNDAPsBAAAA.',
Li='Lifewing:BAAALgAECgUJDAAAAA==.Lightbehunt:BAAALgAECgQJBgAAAA==.Lightsglory:BAAALgADCgMJAwAAAA==.Lilly:BAAALgAECgYJCgAAAA==.Livaless:BAAALgADCgQJBAABLgAECgkJJgAgAFAiAA==.',
Lu='Lucialyn:BAAALgAECgcJDAABLgAECgcJFwAhAOojAA==.Lucifur:BAAALgAECgEJAQABLgAECgkJLgATAOsWAA==.',
Ly='Lyllith:BAABLgAECn8cAAIjAAYJjREWDABkAQAjAAYJjREWDABkAQAAAA==.Lysende:BAAALgADCgQJBAAAAA==.',
Ma='Madamenoodle:BAAALgADCgkJCQAAAA==.Magnass:BAAALgADCgYJBgABLgAECgkJIAAUAOIaAA==.Magnius:BAAALgADCgEJAQAAAA==.Mahidevran:BAAALgAECgQJBQABLgAECgkJKgAXAHMVAA==.Mahoa:BAAALgAECgEJAQAAAA==.Mal:BAAALgAECggJCAAAAA==.Mastablasta:BAAALgAECgQJCQAAAA==.Maursaline:BAABLgAECn8lAAIZAAkJqge7WgAnAQAZAAkJqge7WgAnAQAAAA==.Mawea:BAAALgAECgUJDAAAAA==.Mawks:BAACLgAFFH8OAAMVAAMJrA+VDwCaAAAVAAIJ0BOVDwCaAAAOAAEJZAdgdgA9AAAuAAQKf0EAAhUACQktG6MLAGcCABUACQktG6MLAGcCAAAA.',
Mc='Mcstukes:BAAALgAECgQJCAAAAA==.',
Me='Medeas:BAAALgAECgUJCgAAAA==.Meragos:BAAALgAECgMJAwAAAA==.Meteor:BAAALgADCgQJBAAAAA==.',
Mi='Migz:BAAALgADCgEJAQAAAA==.Migzeviltwin:BAAALgAECgIJAwAAAA==.Mimicz:BAAALgADCgUJBQAAAA==.Minitry:BAAALgAECgEJAwAAAA==.Mixon:BAAALgAECgEJBAAAAA==.Mixxon:BAAALgAECgYJDwAAAA==.',
Mo='Moinion:BAAALgADCgQJCAAAAA==.Moisten:BAAALgAECgIJAgAAAA==.Moldbreather:BAAALgAECgEJAQAAAA==.Moomooimacow:BAAALgAECgQJBAAAAA==.Moomoomonkey:BAABLgAECn8fAAIiAAkJMhfiHQDzAQAiAAkJMhfiHQDzAQAAAA==.Morhgana:BAAALgAECgYJDwAAAA==.',
Ms='Mstea:BAAALgAECgEJAQAAAA==.',
Mx='Mxmlxxix:BAABLgAECn8jAAMQAAgJygGXSwC1AAAQAAgJygGXSwC1AAABAAIJXwHWZQAtAAAAAA==.',
My='Mylosh:BAAALgAECgQJBAABLgAECgkJGAACAAwYAA==.',
['Mö']='Mördecai:BAAALgAECgQJBAAAAA==.',
Na='Naija:BAAALgAECgEJAgAAAA==.Nati:BAAALgAECgUJBQAAAA==.',
Ne='Nephele:BAAALgAECgEJAgAAAA==.Neptune:BAAALgAECgQJCAAAAA==.Neremian:BAAALgAECgEJAQAAAA==.Newport:BAAALgAECgMJBAABLgAFFAMJCwAfAM4RAA==.',
Ni='Nikorobin:BAAALgAECgQJBwABLgAFFAgJHAAdAFYSAA==.Nilius:BAAALgAECgEJAQABLgAECgkJHAABACYfAA==.',
No='Noodles:BAAALgAECgcJCgABLgAECggJIgAdAH0WAA==.Norgalina:BAAALgADCgUJBQAAAA==.',
Ny='Nymara:BAABLgAECn8eAAISAAgJ8RH+FgBpAQASAAgJ8RH+FgBpAQABLgAECgkJGAAKAIIcAA==.',
['Ní']='Níce:BAAALgAECgIJAwAAAA==.',
['Nü']='Nügs:BAABLgAECn8VAAIRAAgJeQvAfgDkAAARAAgJeQvAfgDkAAAAAA==.Nüguns:BAABLgAECn8VAAITAAcJbwxOLQDzAAATAAcJbwxOLQDzAAAAAA==.',
Oc='Occan:BAAALgAECgUJBQAAAA==.',
Od='Odyssey:BAAALgAECgUJBQABLgAFFAMJCwAfAM4RAA==.',
Ol='Olei:BAAALgADCgUJBQAAAA==.',
On='Ontos:BAAALgAECgMJAwAAAA==.',
Or='Orlick:BAAALgAECgEJAQAAAA==.Orrok:BAAALgADCgYJBwAAAA==.',
Pa='Painlink:BAAALgAECgUJCQABLgAECgkJKQAJAHkRAA==.Painnkiller:BAACLgAFFH8XAAIOAAMJCBlmLADnAAAOAAMJCBlmLADnAAAuAAQKfzgAAg4ACQnKHUkYAJUCAA4ACQnKHUkYAJUCAAAA.Papyto:BAAALgADCgYJBwAAAA==.Parsley:BAABLgAECn8qAAMLAAkJACLCAAAhAwALAAkJACLCAAAhAwAgAAMJmxmGwwDGAAAAAA==.Paxis:BAAALgAECgkJDgAAAA==.',
Pe='Perriwinkle:BAACLgAFFH8JAAIbAAMJDhA1BwC0AAAbAAMJDhA1BwC0AAAuAAQKf1sABBsACQkPH78DANECABsACQkPH78DANECABoACQkxFowCANkBABkABAk/DC2KAKMAAAAA.Perseus:BAAALgADCgMJAwAAAA==.',
Ph='Phission:BAAALgADCgEJAQAAAA==.Phobya:BAABLgAECn8nAAIZAAgJNBzWHABfAgAZAAgJNBzWHABfAgAAAA==.Phylloxeras:BAABLgAECn9OAAIGAAkJESbxAgBwAwAGAAkJESbxAgBwAwAAAA==.',
Pl='Pleasure:BAAALgADCgMJAwAAAA==.Pleggashroom:BAAALgADCgEJAQAAAA==.',
Po='Powder:BAAALgAECgMJAwAAAA==.Powders:BAABLgAECn81AAIHAAkJsRywKwBrAgAHAAkJsRywKwBrAgAAAA==.Powderysham:BAAALgAECgcJCwABLgAECgkJNQAHALEcAA==.',
Pr='Praystatiôn:BAAALgAECgEJAQABLgAECgcJGwAgAHcfAA==.Proshot:BAACLgAFFH8OAAIVAAMJqRxrCAAGAQAVAAMJqRxrCAAGAQAuAAQKfzMAAhUACQlYI90CABQDABUACQlYI90CABQDAAAA.',
Pu='Puddles:BAAALgAECgQJBAAAAA==.',
Pz='Pzalmo:BAAALgAECgUJBwABLgAECgkJHwAFAJkUAA==.',
Ra='Raccoon:BAACLgAFFH8OAAIgAAMJVwbEOQCjAAAgAAMJVwbEOQCjAAAuAAQKfz4AAyAACQmbEVxCANUBACAACQmbEVxCANUBAAsAAQloCxU+ADYAAAAA.Rahala:BAAALgAECgUJBQAAAA==.Ralor:BAAALgADCgEJAQAAAA==.Ravenhawk:BAAALgAECgYJEAAAAA==.Razza:BAAALgADCgYJCAAAAA==.',
Re='Remember:BAAALgADCgEJAQAAAA==.Renivatio:BAABLgAECn8uAAIGAAkJcBv3BAAlAgAGAAkJcBv3BAAlAgAAAA==.',
Rh='Rhyntix:BAAALgADCgEJAQAAAA==.',
Ri='Rivet:BAAALgAECgcJBwABLgAFFAQJJQAOAEsgAA==.',
Ro='Ronstådt:BAAALgADCgEJAQAAAA==.Roronoazoro:BAACLgAFFH8cAAIdAAgJVhJyFgD9AQAdAAgJVhJyFgD9AQAuAAQKfyEAAx0ACQlIH2ojAH0CAB0ACQlIH2ojAH0CACYAAglxEwUmAFQAAAAA.',
Ry='Ryrin:BAABLgAECn8mAAMJAAkJBRAQNQB1AQAJAAkJBRAQNQB1AQAcAAQJMgqbDAB4AAAAAA==.Ryrìn:BAAALgADCgEJAQAAAA==.Ryrín:BAAALgAECggJEwAAAA==.',
['Rë']='Rëggië:BAAALgAECgIJAwAAAA==.',
Sa='Samidrac:BAABLgAECn8eAAINAAgJBAObBgCdAAANAAgJBAObBgCdAAAAAA==.Sammidormu:BAABLgAECn8jAAQFAAgJ5RNoCgB5AQAFAAcJABVoCgB5AQAEAAcJbAtZNgAgAQANAAEJ2QEPTgAjAAAAAA==.Sanderwoof:BAAALgAECggJCAAAAA==.Saret:BAAALgADCgMJAwAAAA==.Sarzul:BAABLgAECn8VAAMMAAYJ/A8VNADnAAAgAAYJ2gzAmwAiAQAMAAUJThEVNADnAAAAAA==.Satoshie:BAAALgAECggJCQAAAA==.Sayang:BAAALgAECgMJAwABLgAECgkJOAAZABsfAA==.',
Sc='Scerevisiae:BAABLgAECn8XAAMgAAkJohqPFAC9AAAMAAQJxBSjLgABAQAgAAYJfh2PFAC9AAAAAA==.',
Se='Sedelis:BAABLgAECn8fAAIDAAkJzwr+MQCOAQADAAkJzwr+MQCOAQAAAA==.Sefirbrena:BAAALgADCgkJAwAAAA==.Selaya:BAAALgAECgEJAQAAAA==.Semnai:BAABLgAECn8+AAIZAAkJ+Bb/GwBnAgAZAAkJ+Bb/GwBnAgAAAA==.Serafín:BAACLgAFFH8RAAIKAAMJ+wfyEwCgAAAKAAMJ+wfyEwCgAAAuAAQKfzgAAgoACQmkDisiAJcBAAoACQmkDisiAJcBAAAA.Sevilicious:BAAALgADCgQJAwAAAA==.',
Sh='Shaay:BAAALgAFFAIJAgAAAA==.Shadowlock:BAAALgAECgEJAgAAAA==.Shadownutt:BAAALgAECgUJBQAAAA==.Shadowpyro:BAAALgAECgEJAQAAAA==.Shamwig:BAAALgADCgUJBQAAAA==.Shazzam:BAAALgAECggJEAAAAA==.Shiana:BAAALgADCgkJCQAAAA==.Shieldwall:BAABLgAECn8qAAIUAAgJWg/tGwBXAQAUAAgJWg/tGwBXAQAAAA==.',
Si='Silanah:BAAALgAECgEJAQABLgAFFAQJEQARAKIWAA==.Silbeb:BAAALgAECggJEwABLgAFFAQJJQAOAEsgAA==.Silverhâwk:BAAALgADCgEJAQAAAA==.Sinastys:BAABLgAECn8aAAICAAgJ9RCWgQBsAQACAAgJ9RCWgQBsAQAAAA==.',
Sn='Snoots:BAAALgADCgEJAQAAAA==.',
So='Solone:BAABLgAECn8UAAIdAAYJ6w4tlAD4AAAdAAYJ6w4tlAD4AAAAAA==.Somavra:BAAALgAECgMJBgAAAA==.Sopidia:BAABLgAECn8lAAMRAAkJ+RV0PQC5AQARAAgJTBV0PQC5AQAiAAUJHQatdACOAAAAAA==.Sorvato:BAABLgAECn85AAIdAAkJNRlRIgBIAgAdAAkJNRlRIgBIAgAAAA==.',
Sp='Spiritholy:BAAALgAECgkJBgAAAA==.Spoonzz:BAABLgAECn8xAAMPAAkJDSRlBQD7AgAPAAkJDSRlBQD7AgAKAAIJKx9TWQCkAAAAAA==.',
St='Stamavan:BAABLgAECn8kAAIaAAkJzCIjAwD6AgAaAAkJzCIjAwD6AgAAAA==.Starflayer:BAABLgAECn8nAAMdAAkJXxziJQA2AgAdAAkJbhviJQA2AgAmAAIJYxr3IAB8AAAAAA==.Steb:BAAALgADCgMJAwAAAA==.Sterjariger:BAAALgAECgYJBgABLgAFFAUJBQARAAMOAA==.',
Su='Sunari:BAAALgAECgMJBgAAAA==.Supermelon:BAABLgAECn8WAAIjAAcJXBFKDQBVAQAjAAcJXBFKDQBVAQAAAA==.',
Sy='Syarli:BAAALgAECggJDAAAAA==.Sylvaeelor:BAAALgAFFAIJAwABLgAFFAQJDgAcAG4TAA==.Sylvanaria:BAACLgAFFH8RAAIRAAMJ0CV6EwApAQARAAMJ0CV6EwApAQAuAAQKfz4AAhEACQlbJjoBAMMDABEACQlbJjoBAMMDAAAA.Sylvanaris:BAAALgAECgYJEQAAAA==.Systyx:BAABLgAECn8bAAIgAAcJdx/1TAC0AQAgAAcJdx/1TAC0AQAAAA==.',
Ta='Talenel:BAAALgAECgQJBAAAAA==.Talyzien:BAAALgADCgYJBwAAAA==.',
Te='Tealan:BAACLgAFFH8HAAMNAAQJugzLGgDpAAANAAQJugzLGgDpAAAEAAEJRgLpawAvAAAuAAQKfzAAAwQACQm0GBwTAEYCAAQACQm0GBwTAEYCAA0ACAmpEukcAJ4BAAAA.Tealani:BAAALgAECgMJBgAAAA==.Tealyn:BAAALgAECgYJDgAAAA==.Teatree:BAAALgADCgYJBgAAAA==.Teluz:BAAALgAECgQJCgAAAA==.Tendra:BAAALgAECgYJBQAAAA==.Teronreborn:BAACLgAFFH8LAAIGAAMJpBrbNQD0AAAGAAMJpBrbNQD0AAAuAAQKfyUAAgYACQk6JYYUAAADAAYACQk6JYYUAAADAAAA.',
Th='Thaneer:BAAALgAECgYJBwAAAA==.Thanos:BAABLgAECn8dAAICAAYJ7Q6KpAA3AQACAAYJ7Q6KpAA3AQAAAA==.Thebadmage:BAAALgAECgcJBAAAAA==.Throstmok:BAACLgAFFH8aAAITAAUJCBVlDgD2AAATAAUJCBVlDgD2AAAuAAQKfzcAAhMACQm3Hq8JAHgCABMACQm3Hq8JAHgCAAAA.Thràll:BAAALgAECgUJBQAAAA==.Thränton:BAAALgAECgEJAQABLgAECgcJFAAmALwhAA==.Thumbalina:BAAALgAECgYJEQAAAA==.',
Ti='Tiantu:BAAALgAECgIJAgAAAA==.',
To='Tongra:BAAALgAECgEJAQABLgAECgkJIAAHAFgPAA==.Totemtuggér:BAAALgADCgIJAgAAAA==.',
Tp='Tpaste:BAAALgADCgcJBwAAAA==.',
Tr='Trampstãmp:BAAALgAECgIJAgAAAA==.Trinitea:BAAALgAECgYJCwAAAA==.Trout:BAAALgADCgYJDAABLgAECgYJCgAeAAAAAA==.Trovikk:BAAALgADCgUJBgAAAA==.',
Tu='Turg:BAAALgAECgMJAwABLgAECgQJBwAeAAAAAA==.Turgo:BAAALgAECgEJAQABLgAECgQJBwAeAAAAAA==.Turgress:BAAALgAECgQJBwAAAA==.',
['Tà']='Tàmber:BAAALgADCgYJBwAAAA==.',
Ub='Ubaubajuana:BAAALgAECgYJDAAAAA==.',
Ul='Ulfast:BAACLgAFFH8MAAIiAAMJMBbCGwCzAAAiAAMJMBbCGwCzAAAuAAQKfyUAAiIACAlKHrcaAAsCACIACAlKHrcaAAsCAAAA.',
Va='Valarios:BAAALgAECgYJCgAAAA==.Vannhellsing:BAABLgAECn8zAAIGAAkJcA6BCQCQAQAGAAkJcA6BCQCQAQAAAA==.Vanyel:BAABLgAECn9YAAIHAAkJBRpDCQC3AQAHAAkJBRpDCQC3AQAAAA==.Vaudorka:BAABLgAECn8cAAIFAAkJIx5RAwBnAgAFAAkJIx5RAwBnAgAAAA==.',
Ve='Vecna:BAAALgADCgMJAwABLgAECgYJCAAeAAAAAA==.Veliuz:BAAALgADCgQJBAAAAA==.Velrynth:BAABLgAECn84AAMhAAkJ+BSAEwBFAgAhAAkJVxSAEwBFAgAQAAcJzghySAAXAQAAAA==.Vemal:BAABLgAECn8yAAIOAAkJThk9GwCCAgAOAAkJThk9GwCCAgAAAA==.',
Vi='Vicieus:BAAALgAECgYJDgAAAA==.',
Vo='Vociferoy:BAACLgAFFH8fAAIOAAMJNCF8HgAoAQAOAAMJNCF8HgAoAQAuAAQKf0QAAg4ACQl9IUQPANYCAA4ACQl9IUQPANYCAAAA.Voidsteffan:BAACLgAFFH8GAAIMAAIJeAnyCQB4AAAMAAIJeAnyCQB4AAAuAAQKf0UAAwwACQloG6wAAGICAAwACQloG6wAAGICACAABAmPDiLBANcAAAAA.',
Vr='Vryadox:BAAALgAFFAIJAgABLgAFFAQJDwAgAGwdAA==.',
Vv='Vv:BAACLgAFFH9zAAIdAAkJ3yYUAACWAwAdAAkJ3yYUAACWAwAuAAQKfzUAAh0ACQm1JucAANoDAB0ACQm1JucAANoDAAAA.',
Vz='Vz:BAAALgADCgUJBQAAAA==.',
Wh='Whoppin:BAAALgAECgIJAgAAAA==.',
Wi='Wiglimparms:BAAALgAECgIJAgAAAA==.',
Wr='Wry:BAAALgAECgMJAwAAAA==.',
Wy='Wysselbow:BAAALgADCggJDQAAAA==.',
['Wá']='Wárranpeace:BAAALgADCgMJAwAAAA==.',
Xa='Xalmo:BAAALgAECgEJAQABLgAECgkJHwAFAJkUAA==.Xalzi:BAAALgADCggJCQABLgAECgcJFAARAHwVAA==.',
Xi='Xingwong:BAABLgAECn89AAIfAAkJ5yXXAQBNAwAfAAkJ5yXXAQBNAwAAAA==.',
Za='Zannytoes:BAABLgAECn8mAAMXAAkJpRA9MAC6AQAXAAkJpRA9MAC6AQAPAAEJLxFSnwAwAAAAAA==.',
Ze='Zead:BAAALgAECgEJBwAAAA==.Zerana:BAACLgAFFH8RAAIMAAQJtQf+CgDrAAAMAAQJtQf+CgDrAAAuAAQKfxgAAgwACQlRD1wOAFcBAAwACQlRD1wOAFcBAAAA.Zeriea:BAAALgADCgEJAQAAAA==.Zevtra:BAAALgADCgEJAQAAAA==.',
Zi='Zie:BAABLgAECn9aAAIBAAkJ8RstAwDpAQABAAkJ8RstAwDpAQAAAA==.Zikren:BAAALgAECgkJCQAAAA==.',
Zo='Zoumbadouwow:BAAALgAFFAEJAgAAAA==.',
Zs='Zsinj:BAAALgADCgEJAQAAAA==.',
['Çe']='Çelestial:BAAALgAFFAEJAQABLgAFFAIJBgAIAA8jAA==.',
['Ðo']='Ðonkle:BAABLgAECn8TAAIdAAgJmByzKwAZAgAdAAgJmByzKwAZAgAAAA==.',
['Ðr']='Ðrewid:BAAALgADCgEJAQAAAA==.',
['Ñi']='Ñice:BAACLgAFFH8dAAIJAAgJrSOoBwDqAQAJAAgJrSOoBwDqAQAuAAQKfxoAAgkACQkrHugYACcCAAkACQkrHugYACcCAAAA.',
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
