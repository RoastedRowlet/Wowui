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

local lookup = {'Unknown-Unknown','Priest-Shadow','Paladin-Retribution','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Unholy','Mage-Frost','DemonHunter-Devourer','Monk-Brewmaster','Warlock-Affliction','Evoker-Preservation','Hunter-BeastMastery','Monk-Windwalker','Priest-Holy','Shaman-Restoration','Paladin-Protection','DemonHunter-Havoc','DeathKnight-Blood','Warrior-Fury','Warrior-Protection','Hunter-Marksmanship','Hunter-Survival','Monk-Mistweaver','Druid-Balance','Druid-Restoration','Druid-Guardian','Druid-Feral','Warrior-Arms','Priest-Discipline','Warlock-Destruction','Rogue-Subtlety','Warlock-Demonology','Paladin-Holy','Shaman-Elemental','Rogue-Assassination','Rogue-Outlaw','Shaman-Enhancement','DemonHunter-Vengeance',}
local provider = {region='US',realm='Lightninghoof',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abukuma:BAAALgAECgQJBAAAAA==.',
Ac='Aceieus:BAAALgAECgkJAQABLgAECgEJAQABAAAAAA==.',
Ad='Adraina:BAAALgADCgEJAQAAAA==.Adrewid:BAAALgADCgQJBAAAAA==.',
Ae='Aelarya:BAABLgAECn8RAAICAAgJAQYXQgDpAAACAAgJAQYXQgDpAAAAAA==.Aenstalash:BAABLgAECn8hAAIDAAgJPyNIJAB0AgADAAgJPyNIJAB0AgAAAA==.Aephium:BAABLgAECn8UAAMEAAcJuwZjYQC2AAAEAAYJJgZjYQC2AAAFAAUJtAQVHABsAAAAAA==.Aesilakaersi:BAAALgAECgYJCgAAAA==.Aeson:BAABLgAECn8kAAIGAAkJiBeRRQDyAQAGAAkJiBeRRQDyAQAAAA==.',
Af='Afflictia:BAAALgADCgYJEAAAAA==.',
Ai='Aironel:BAAALgADCgMJAwAAAA==.',
Al='Alanza:BAAALgAECgYJBwAAAA==.Alaure:BAAALgADCgIJAgAAAA==.Alessia:BAAALgAECgIJAgAAAA==.Alfonsoo:BAAALgADCgEJAQAAAA==.Alida:BAAALgAECgQJBAAAAA==.Alistur:BAABLgAECn8kAAIHAAgJMwv3AwACAQAHAAgJMwv3AwACAQAAAA==.',
Am='Amanna:BAAALgAECgMJAwABLgAECggJHwAIAM4jAA==.Amoona:BAAALgAECgYJEgABLgAECggJHwAIAM4jAA==.',
An='Anoriia:BAAALgADCgUJBQAAAA==.',
Ar='Arcnid:BAAALgADCgYJBgAAAA==.Arfas:BAAALgADCgQJBAAAAA==.Arthraz:BAABLgAECn8kAAIJAAkJsxwGDAB1AgAJAAkJsxwGDAB1AgABLgAECgkJKgAKAAAiAA==.',
As='Astara:BAAALgAECgQJBAAAAA==.Astraa:BAAALgAECgIJAgAAAA==.Astrex:BAABLgAECn9DAAQLAAkJuA9QAAB4AQALAAkJuA9QAAB4AQAFAAEJjAftAQAhAAAEAAEJJwHSqAAMAAAAAA==.',
Au='Aunaturale:BAAALgAECgkJAwAAAA==.Aurali:BAAALgAECgEJAQAAAA==.Aureliá:BAABLgAECn8XAAIMAAcJnQrDjAAlAQAMAAcJnQrDjAAlAQAAAA==.',
['Aü']='Aütobot:BAABLgAECn8iAAINAAkJMw2zJgCAAQANAAkJMw2zJgCAAQAAAA==.',
Ba='Badgirl:BAACLgAFFH8MAAIOAAQJgREnGQDyAAAOAAQJgREnGQDyAAAuAAQKfxkAAw4ACAm+E9c1ACoBAA4ABgnBFtc1ACoBAAIABgktCtxLAOAAAAAA.Balnar:BAABLgAECn8bAAIPAAcJ3hWBAgAFAQAPAAcJ3hWBAgAFAQABLgAECggJHgAQADUWAA==.Balraga:BAABLgAECn8ZAAIRAAgJUQrgKwAhAQARAAgJUQrgKwAhAQAAAA==.Bargrivyek:BAAALgAECgUJBwAAAA==.Bayded:BAAALgADCgEJAQAAAA==.',
Be='Beastboyy:BAAALgAECgUJBQAAAA==.Bega:BAACLgAFFH8rAAMGAAgJ9hpYDQB0AgAGAAgJ9hpYDQB0AgASAAEJAABRUwAAAAAuAAQKf0EAAwYACQnoJXoFAE8DAAYACQnoJXoFAE8DABIABgkrFzslABUBAAAA.Benton:BAAALgAECgQJCAAAAA==.',
Bi='Bigglimpie:BAAALgAECgYJDQAAAA==.',
Bl='Bloodlustplz:BAABLgAECn8qAAMTAAkJshdALACjAQATAAcJLx5ALACjAQAUAAgJLQ/NGwBYAQAAAA==.',
Bo='Bobster:BAABLgAECn8kAAIHAAkJuxHkYQC7AQAHAAkJuxHkYQC7AQAAAA==.Bonepaw:BAAALgAECgMJBAABLgAECgcJFAAPAHwVAA==.Booyea:BAACLgAFFH8IAAISAAMJARcyAwDFAAASAAMJARcyAwDFAAAuAAQKfz4AAhIACQklHBQLAF8CABIACQklHBQLAF8CAAAA.',
Br='Brew:BAAALgAECgcJCwAAAA==.Brewwnor:BAAALgAECgcJCwAAAA==.Brickdemkeys:BAABLgAECn8fAAIHAAgJPBr/YwC2AQAHAAgJPBr/YwC2AQAAAA==.Brisfloggnaw:BAAALgAFFAEJAQAAAA==.',
Ca='Caladk:BAAALgADCgUJBQABLgAFFAcJIQAVAD8fAA==.Calamuelis:BAACLgAFFH8hAAQVAAcJPx/WBwCeAQAVAAcJ7hvWBwCeAQAWAAUJTyLwCgBvAQAMAAIJehxTDABwAAAuAAQKfx0ABBUACAnSJLsNANcCABUACAmWJLsNANcCABYABAn5JIcwACYBAAwAAQkIJhX2AGkAAAAA.Caliope:BAABLgAECn8gAAMXAAgJfhWdJQD3AQAXAAgJfhWdJQD3AQANAAMJgwk+AgCTAAAAAA==.Capsasin:BAAALgADCgUJBQAAAA==.Carnage:BAAALgAFFAIJAgAAAA==.Cazlek:BAAALgAECgQJCwAAAA==.',
Ce='Celery:BAAALgAECgMJAwABLgAECgkJKgAKAAAiAA==.Celldweller:BAAALgAECgYJCgAAAA==.Cerdred:BAABLgAECn8dAAIYAAUJARDLSQAEAQAYAAUJARDLSQAEAQAAAA==.Ceredis:BAAALgAECgEJAQAAAA==.Cerelus:BAABLgAECn8gAAIHAAkJWA9pVQDdAQAHAAkJWA9pVQDdAQAAAA==.',
Ch='Chaac:BAAALgAECgYJDAABLgAECggJFgALALITAA==.Chmmr:BAAALgADCgMJAwAAAA==.Chowilawu:BAAALgADCgkJCQAAAA==.Chriswilsonn:BAAALgAECgQJCAAAAA==.Chuca:BAAALgAECgYJBgAAAA==.Chucalu:BAABLgAECn8WAAUZAAgJVh4ANwDLAQAZAAYJUyAANwDLAQAaAAQJCx7wEQBVAQAYAAIJih86WgCqAAAbAAEJLwbeMgA2AAAAAA==.Chéwtoy:BAAALgAECgIJBAAAAA==.',
Cl='Clax:BAAALgAECgIJBQAAAA==.',
Co='Cobeam:BAAALgAECgUJEQAAAA==.Cowpernicus:BAABLgAECn8iAAIZAAkJ7SAJBwBHAwAZAAkJ7SAJBwBHAwABLgAFFAMJDAAPAB4bAA==.',
Cr='Crungleman:BAABLgAECn8YAAIMAAcJuRi4XwCIAQAMAAcJuRi4XwCIAQAAAA==.',
Ct='Cthuwu:BAAALgAECgQJBAABLgAECggJFgALALITAA==.',
Cu='Curoi:BAABLgAECn8rAAMbAAkJjxeDCABEAgAbAAkJjxeDCABEAgAZAAgJRAozeQDsAAAAAA==.',
['Cã']='Cãrloy:BAACLgAFFH8cAAITAAQJlBudAwDeAAATAAQJlBudAwDeAAAuAAQKf1oAAxMACQlWIhsHAOwCABMACQlWIhsHAOwCABwAAgkpIelEALYAAAAA.',
['Cê']='Cêlestial:BAABLgAECn8fAAMIAAgJziPoGwBtAgAIAAgJ9SLoGwBtAgARAAQJBSPJAgBvAAAAAA==.',
Da='Daedalas:BAABLgAECn8YAAMCAAgJnx/uDgBqAgACAAgJnx/uDgBqAgAOAAIJMAJ8awA8AAAAAA==.Daedtoo:BAAALgAECgQJBAABLgAECggJGAACAJ8fAA==.Damonk:BAAALgADCgYJBgABLgAECgkJIAAUAOIaAA==.Danevolent:BAABLgAECn8gAAMOAAcJ9yJ9DQCAAgAOAAcJ9yJ9DQCAAgACAAQJEA01YACYAAABLgAECgkJIAAUAOIaAA==.Danzaster:BAAALgADCgQJBAAAAA==.Darkxsoul:BAABLgAECn8eAAIQAAgJNRbBEAC4AQAQAAgJNRbBEAC4AQAAAA==.Darthknull:BAACLgAFFH8SAAIDAAQJBRfKOAA7AQADAAQJBRfKOAA7AQAuAAQKfzsAAgMACQnQIXAYALECAAMACQnQIXAYALECAAAA.Darthtalon:BAAALgAECgkJDgABLgAFFAQJEgADAAUXAA==.',
De='Deadeyedicky:BAAALgAECgkJBwAAAA==.Deathmachine:BAAALgADCgUJBQAAAA==.Deathniight:BAAALgAECgUJBAAAAA==.Deathseer:BAAALgAECgcJDgAAAA==.Deathwood:BAAALgADCgUJBgABLgAECgEJAQABAAAAAA==.Deatthdecay:BAAALgAECggJBAAAAA==.Deitrichx:BAABLgAECn8pAAIVAAkJnxmVBgApAgAVAAkJnxmVBgApAgAAAA==.Delley:BAAALgADCgEJAQAAAA==.Deminestrea:BAABLgAECn8aAAISAAYJchCcKgADAQASAAYJchCcKgADAQAAAA==.Demonswhere:BAAALgADCgQJBAAAAA==.Devilscreed:BAAALgAECgEJAQAAAA==.',
Di='Dingleberrys:BAAALgADCgEJAQAAAA==.Dippindots:BAAALgAECgYJCAAAAA==.Disshammy:BAAALgAFFAIJAgABLgAFFAgJIgAEANEhAA==.Dittoz:BAAALgADCgUJBAAAAA==.',
Do='Dolfcritler:BAAALgAECgQJBQAAAA==.Dolfcrittler:BAAALgADCgEJAQAAAA==.Donkform:BAAALgAECgkJEgAAAA==.Donniyii:BAAALgAECgcJBwABLgAECgkJOwAdAJQfAA==.Doomrider:BAAALgADCgYJBgAAAA==.Dottzz:BAABLgAECn8aAAIeAAYJ8B27FQCcAQAeAAYJ8B27FQCcAQAAAA==.',
Dr='Draconith:BAACLgAFFH8YAAILAAUJZxFJFQBAAQALAAUJZxFJFQBAAQAuAAQKfzcAAgsACQmSG00FAMMCAAsACQmSG00FAMMCAAAA.Dramoo:BAAALgAECgMJAwAAAA==.Draqkmar:BAABLgAECn8bAAIMAAYJVQpYpAD5AAAMAAYJVQpYpAD5AAAAAA==.Dreddwing:BAABLgAECn8WAAMLAAgJshObEADCAQALAAcJcBWbEADCAQAEAAIJJg8hewBrAAAAAA==.Dredfox:BAAALgAECgIJAgABLgAECgkJRwAYAPURAA==.Drunkenoodle:BAAALgADCgYJBgAAAA==.',
Du='Dunsparrow:BAACLgAFFH8MAAIPAAMJHhsOQADkAAAPAAMJHhsOQADkAAAuAAQKf0cAAg8ACQnfIkkFAF8DAA8ACQnfIkkFAF8DAAAA.Durzul:BAAALgAECgEJAQAAAA==.',
Ei='Eightyone:BAAALgAECggJDwAAAA==.Eindraken:BAACLgAFFH8WAAILAAUJwwa1AgCIAAALAAUJwwa1AgCIAAAuAAQKfzkAAgsACQn7EjINAP4BAAsACQn7EjINAP4BAAAA.Eiroh:BAAALgAECggJEQABLgAECggJHgAQAPERAA==.Eisis:BAABLgAECn8/AAIbAAkJVBCSFAB6AQAbAAkJVBCSFAB6AQAAAA==.',
El='Elanalué:BAAALgAECgYJEAABLgAECggJIAAXAH4VAA==.',
En='Enamel:BAAALgAECgMJAwABLgAFFAIJBgAfAI8RAA==.',
Er='Erixee:BAAALgAECgUJBgAAAA==.Erroz:BAAALgADCgIJAQAAAA==.',
Es='Eshonäi:BAABLgAECn8aAAIgAAYJtRHMjgAdAQAgAAYJtRHMjgAdAQAAAA==.Espriesso:BAABLgAECn8VAAQdAAgJAQ1sMwBKAQAdAAcJ3wtsMwBKAQACAAQJvgR4ZQCGAAAOAAIJDAecdABWAAABLgAECgkJLAAJALEPAA==.',
Ev='Everbark:BAAALgADCgEJAQAAAA==.Evodragker:BAABLgAECn8kAAMEAAkJKxR1IQDOAQAEAAkJKxR1IQDOAQALAAEJcAkFPAAzAAAAAA==.',
Fe='Feider:BAAALgAECgEJAQAAAA==.Felais:BAABLgAFFH8GAAIZAAQJpwfZPQC4AAAZAAQJpwfZPQC4AAAAAA==.Feldron:BAAALgAECgcJEwAAAA==.Felkaos:BAAALgADCgEJAQAAAA==.Fellura:BAAALgAECgYJDAAAAA==.Femaledawg:BAAALgADCgcJEAAAAA==.',
Fi='Fingor:BAAALgAECgYJBwAAAA==.',
Fl='Flamecube:BAAALgAECgEJAQAAAA==.Flashx:BAABLgAECn8kAAMhAAgJ3iDsCQDtAgAhAAgJ3iDsCQDtAgADAAEJQQzYmQEvAAAAAA==.',
Fo='Foxxeyineawo:BAAALgADCgcJCAAAAA==.',
Fr='Frevmk:BAAALgAECgEJAgAAAA==.Frofrohunter:BAABLgAECn8sAAMMAAkJaB+kEgCiAgAMAAkJaB+kEgCiAgAVAAUJAxLZTgAUAQAAAA==.Frofrolock:BAAALgAECgcJDgAAAA==.Froggie:BAABLgAECn8UAAMPAAcJfBWaUQBsAQAPAAcJfBWaUQBsAQAiAAMJXQ/iaACgAAAAAA==.Froshaman:BAAALgAECgEJAQAAAA==.',
Fu='Fuzywuuzy:BAACLgAFFH8NAAIZAAMJ1BR6OwDAAAAZAAMJ1BR6OwDAAAAuAAQKfyUAAxkACAnUI+ELAAIDABkACAnUI+ELAAIDABgABwk6FvsnAJABAAAA.',
Ga='Gazdorn:BAABLgAECn8qAAIUAAkJeRJ9EgDDAQAUAAkJeRJ9EgDDAQAAAA==.',
Ge='Genebelcher:BAAALgAECgEJAQAAAA==.',
Gh='Ghost:BAABLgAECn8hAAIjAAgJdhqiBQAbAgAjAAgJdhqiBQAbAgAAAA==.',
Gi='Gigof:BAABLgAECn8rAAMYAAkJPxJ4JQCgAQAYAAgJ0RJ4JQCgAQAZAAcJ/AqcggC0AAAAAA==.',
Gl='Glissa:BAABLgAECn8UAAQKAAcJdCWRAQDTAgAKAAcJEiWRAQDTAgAgAAMJhSJYogAUAQAeAAIJjxpcRACkAAAAAA==.',
Go='Gobah:BAABLgAECn8YAAMfAAgJ5hXOGQDLAQAfAAgJ5hXOGQDLAQAkAAUJsQctFwCmAAAAAA==.',
Gt='Gt:BAAALgAECgQJCwAAAA==.',
Gu='Gulldan:BAABLgAECn8iAAIgAAgJXxjANgD+AQAgAAgJXxjANgD+AQAAAA==.',
Gw='Gwyndolin:BAAALgADCgUJBQAAAA==.',
Ha='Habanero:BAAALgAECgQJBgABLgAECgkJKgAKAAAiAA==.Hadory:BAABLgAECn8VAAMDAAgJqxU3UgDSAQADAAgJqxU3UgDSAQAhAAQJWhm4SwAMAQAAAA==.Harrowhark:BAABLgAECn9BAAQKAAkJUwo/EgBEAQAgAAkJhgnTYAB+AQAKAAgJuwk/EgBEAQAeAAQJyQVCMgBVAAAAAA==.',
He='Hellzzdemon:BAABLgAECn8fAAIRAAgJtRDRAQC1AAARAAgJtRDRAQC1AAAAAA==.Hendricks:BAAALgAECgQJCgAAAA==.Hexinverter:BAAALgAECgQJCQAAAA==.Hexzard:BAAALgADCgQJBAABLgAECgUJEQABAAAAAA==.Hezekiiah:BAAALgAECgYJDQAAAA==.',
Ho='Holeecow:BAAALgADCgIJAgABLgAFFAMJDAAPAB4bAA==.Holycannoli:BAAALgAECggJDgAAAA==.Horiffic:BAAALgAECgcJEwAAAA==.Horok:BAAALgAECgYJDQAAAA==.Hotsforthots:BAAALgAECgUJBQAAAA==.Hotwheels:BAAALgAECgMJAwAAAA==.',
Hu='Hubert:BAABLgAECn8WAAIXAAgJwQkVVwAVAQAXAAgJwQkVVwAVAQAAAA==.Hubertdale:BAAALgAECgMJAwAAAA==.Hulkblood:BAAALgAECgEJAQAAAA==.Hummingbrook:BAAALgAECgcJDAABLgAFFAgJHAAIAFYSAA==.',
Hy='Hypandia:BAAALgAECggJDAABLgAFFAMJDAAPAB4bAA==.',
Ic='Ichaerus:BAAALgAECgQJBQABLgAECggJGAACAJ8fAA==.Ichtheblack:BAAALgAECgcJCQABLgAECggJGAACAJ8fAA==.Ichtu:BAAALgAECgEJAQABLgAECggJGAACAJ8fAA==.',
Ii='Iilli:BAABLgAECn87AAMdAAkJlB9gBwAGAwAdAAkJlB9gBwAGAwACAAkJnxv1DQB2AgAAAA==.',
In='Inari:BAABLgAECn8XAAICAAkJSgt3LAByAQACAAkJSgt3LAByAQAAAA==.Inkkubus:BAACLgAFFH8cAAQeAAYJeRfoDgC8AAAgAAMJQh9XbQDoAAAeAAMJXAroDgC8AAAKAAIJUxYYHwBSAAAuAAQKfxcABCAACQmPHuM6AO8BACAABwnZH+M6AO8BAB4AAwnpG7wWAO4AAAoAAQkAABEnAFUAAAAA.Instagatorz:BAAALgADCgUJBgAAAA==.',
Iq='Iq:BAAALgAECgEJAQAAAA==.',
Iw='Iwkms:BAACLgAFFH8OAAIbAAQJihaXCAAhAQAbAAQJihaXCAAhAQAuAAQKfyMAAhsACAliIzMCADEDABsACAliIzMCADEDAAEuAAUUBQkGACQAwhYA.',
Ja='Jade:BAABLgAECn8dAAIJAAYJ9CTvFQD9AQAJAAYJ9CTvFQD9AQAAAA==.Jatheo:BAAALgADCgIJAgAAAA==.',
Je='Jenliz:BAAALgADCgEJAQABLgAECgYJEQABAAAAAA==.Jeronor:BAAALgAECgIJAgAAAA==.',
Ji='Jimmick:BAABLgAECn8WAAIPAAcJfyNXEQDEAgAPAAcJfyNXEQDEAgABLgAECggJFQADAKsVAA==.Jisung:BAABLgAECn8UAAMlAAYJkQLBKwCbAAAlAAYJkQLBKwCbAAAiAAIJHAE7xgARAAAAAA==.',
Jo='Jorad:BAAALgADCgEJAQAAAA==.',
Jt='Jtheman:BAAALgAECgQJBAAAAA==.',
Ju='Junebugg:BAAALgADCgEJAQAAAA==.',
Ka='Kaing:BAAALgAECgYJCwAAAA==.Kaissa:BAAALgAECgEJAQAAAA==.Kalena:BAACLgAFFH8IAAIHAAMJVgPSDQCbAAAHAAMJVgPSDQCbAAAuAAQKfz4AAgcACQnnDhliALsBAAcACQnnDhliALsBAAAA.Kandikkiss:BAAALgAECgUJCwAAAA==.Kaos:BAABLgAECn8jAAIHAAkJ+hFdXgDEAQAHAAkJ+hFdXgDEAQAAAA==.Kariatyda:BAABLgAECn8uAAIMAAkJMxgIGwBlAgAMAAkJMxgIGwBlAgAAAA==.Kasai:BAAALgADCgMJAwABLgAECgkJKAADAL4XAA==.Kassandra:BAACLgAFFH8PAAIHAAMJ2R4LCQDqAAAHAAMJ2R4LCQDqAAAuAAQKfz4AAgcACQnvHJscALECAAcACQnvHJscALECAAAA.Kay:BAAALgAECgcJCQAAAA==.Kayden:BAABLgAECn8aAAIXAAYJhBh2JACQAQAXAAYJhBh2JACQAQABLgAECggJGwAhAFUcAA==.Kayn:BAAALgAECgIJAgAAAA==.',
Ke='Keelistus:BAAALgAECgQJBAAAAA==.Kekio:BAAALgAECgUJBQAAAA==.Kelisola:BAAALgADCgEJAQAAAA==.Kelzor:BAAALgAECgEJAQAAAA==.Keruu:BAAALgAECgcJBwAAAA==.',
Kh='Khaylorn:BAAALgAECgMJBgAAAA==.Kháòs:BAAALgAECgUJBQAAAA==.',
Ki='Kiloton:BAABLgAECn8oAAIaAAkJrRNxEwC+AQAaAAkJrRNxEwC+AQAAAA==.Kinari:BAABLgAECn8XAAQhAAgJOxi0AACeAQAhAAgJOxi0AACeAQAQAAEJfwEmWgAbAAADAAEJKQKuzwEZAAAAAA==.Kitzy:BAABLgAECn8lAAIHAAkJeQf5nABAAQAHAAkJeQf5nABAAQAAAA==.',
Kl='Klapso:BAAALgADCgYJDQAAAA==.Klippertdk:BAACLgAFFH8FAAIGAAMJMw7jCgDNAAAGAAMJMw7jCgDNAAAuAAQKfzcAAgYACQleGBkrAFQCAAYACQleGBkrAFQCAAAA.Klugamonk:BAAALgADCgUJBQAAAA==.Klutz:BAABLgAECn8qAAIZAAkJXw88NgDAAQAZAAkJXw88NgDAAQAAAA==.',
Ko='Korgan:BAAALgAECggJDwAAAA==.Korgriku:BAAALgADCgMJAwAAAA==.',
Kr='Kreznor:BAAALgAECgIJAgAAAA==.',
Ku='Kurzo:BAACLgAFFH8NAAITAAQJCx+ZEACBAQATAAQJCx+ZEACBAQAuAAQKfzsAAxMACQnrIuEGAPACABMACQnrIuEGAPACABQABQmtEussANoAAAAA.',
Ky='Kylarian:BAABLgAECn8iAAIRAAkJyQapKwAjAQARAAkJyQapKwAjAQAAAA==.Kyntara:BAAALgAECgYJDQAAAA==.Kyronian:BAAALgAECgYJDwAAAA==.',
['Kâ']='Kâsâi:BAABLgAECn8oAAIDAAkJvhfCWQC/AQADAAkJvhfCWQC/AQAAAA==.',
La='Lachancea:BAAALgAECgEJAQABLgAECggJFQAgADsZAA==.Lakshmee:BAAALgAECgcJDgAAAA==.',
Le='Ledarm:BAAALgAECggJEwAAAA==.Leigin:BAAALgADCgYJBgAAAA==.Lexxi:BAACLgAFFH8HAAIDAAMJvg2gBwDCAAADAAMJvg2gBwDCAAAuAAQKfzoAAgMACQlCFdVDAPsBAAMACQlCFdVDAPsBAAAA.',
Li='Lifewing:BAAALgAECgQJCwAAAA==.Lightbehunt:BAAALgAECgQJBgAAAA==.Lightfivhapy:BAAALgAECgcJEQAAAA==.Lightsglory:BAAALgADCgMJAwAAAA==.Lilly:BAAALgAECgYJCgAAAA==.Livaless:BAAALgADCgQJBAABLgAECgkJJQAgAFAiAA==.',
Lu='Lucialyn:BAAALgAECgcJDAAAAA==.',
Ly='Lyllith:BAABLgAECn8cAAIjAAYJjREWDABkAQAjAAYJjREWDABkAQAAAA==.Lysende:BAAALgADCgQJBAAAAA==.',
Ma='Madamenoodle:BAAALgADCgkJCQAAAA==.Magnass:BAAALgADCgYJBgABLgAECgkJIAAUAOIaAA==.Magnius:BAAALgADCgEJAQAAAA==.Mal:BAAALgAECggJCAAAAA==.Mastablasta:BAAALgAECgQJCQAAAA==.Maursaline:BAABLgAECn8lAAIZAAkJqge+WgAnAQAZAAkJqge+WgAnAQAAAA==.Mawea:BAAALgAECgUJDAAAAA==.Mawks:BAACLgAFFH8FAAIWAAIJlRI5JgChAAAWAAIJlRI5JgChAAAuAAQKfzsAAhYACQmkGaYLAGcCABYACQmkGaYLAGcCAAAA.',
Mc='Mcstukes:BAAALgAECgQJCAAAAA==.',
Me='Medeas:BAAALgAECgUJCgAAAA==.Meragos:BAAALgAECgMJAwAAAA==.Meteor:BAAALgADCgQJBAAAAA==.',
Mi='Migzeviltwin:BAAALgAECgEJAgAAAA==.Mimicz:BAAALgADCgUJBQAAAA==.Minitry:BAAALgAECgEJAgAAAA==.Mixxon:BAAALgAECgYJDwAAAA==.',
Mo='Moinion:BAAALgADCgQJCAAAAA==.Moldbreather:BAAALgAECgEJAQAAAA==.Moomooimacow:BAAALgAECgQJBAAAAA==.Moomoomonkey:BAABLgAECn8fAAIiAAkJMhfkHQDzAQAiAAkJMhfkHQDzAQAAAA==.Morhgana:BAAALgAECgYJDwAAAA==.',
Mx='Mxmlxxix:BAABLgAECn8jAAMOAAgJygGRSwC1AAAOAAgJygGRSwC1AAACAAIJXwHWZQAtAAAAAA==.',
My='Mylosh:BAAALgAECgQJBAABLgAECggJFQADAKsVAA==.',
['Mö']='Mördecai:BAAALgAECgQJBAAAAA==.',
Na='Naija:BAAALgAECgEJAgAAAA==.Nati:BAAALgAECgUJBQAAAA==.',
Ne='Nephele:BAAALgAECgEJAgAAAA==.Neptune:BAAALgAECgQJCAAAAA==.Newport:BAAALgAECgMJAwABLgAFFAIJBgAfAI8RAA==.',
Ni='Nikorobin:BAAALgAECgQJBwABLgAFFAgJHAAIAFYSAA==.Nilius:BAAALgADCgcJBwABLgAECggJGAACAJ8fAA==.',
No='Noodles:BAAALgADCgkJDAABLgAECggJIQAIAH0WAA==.Norgalina:BAAALgADCgUJBQAAAA==.',
Ny='Nymara:BAABLgAECn8eAAIQAAgJ8RH+FgBpAQAQAAgJ8RH+FgBpAQAAAA==.',
['Ní']='Níce:BAAALgAECgIJAwAAAA==.',
['Nü']='Nügs:BAAALgAECggJEwAAAA==.Nüguns:BAAALgAECgcJEQAAAA==.',
Ol='Olei:BAAALgADCgUJBQAAAA==.',
Or='Orlick:BAAALgAECgEJAQAAAA==.Orrok:BAAALgADCgYJBwAAAA==.',
Pa='Painlink:BAAALgAECgUJCQABLgAECgkJKQATAHkRAA==.Painnkiller:BAACLgAFFH8LAAIMAAMJCBnFBgDnAAAMAAMJCBnFBgDnAAAuAAQKfzgAAgwACQnKHUsYAJUCAAwACQnKHUsYAJUCAAAA.Papyto:BAAALgADCgYJBwAAAA==.Parsley:BAABLgAECn8qAAMKAAkJACLCAAAhAwAKAAkJACLCAAAhAwAgAAMJmxmHwwDHAAAAAA==.Paxis:BAAALgAECgkJDgAAAA==.',
Pe='Perriwinkle:BAACLgAFFH8HAAIbAAMJtwwRAQC8AAAbAAMJtwwRAQC8AAAuAAQKf0wABBsACQkPH78DANECABsACQkPH78DANECABoACAmjE30BAN0AABkABAk/DCyKAKMAAAAA.Perseus:BAAALgADCgMJAwAAAA==.',
Ph='Phission:BAAALgADCgEJAQAAAA==.Phobya:BAABLgAECn8nAAIZAAgJNBzYHABfAgAZAAgJNBzYHABfAgAAAA==.Phylloxeras:BAABLgAECn9LAAIGAAkJ5SXxAgBwAwAGAAkJ5SXxAgBwAwAAAA==.',
Pl='Pleasure:BAAALgADCgMJAwAAAA==.Pleggashroom:BAAALgADCgEJAQAAAA==.',
Po='Powders:BAABLgAECn80AAIHAAkJ5RuzKwBrAgAHAAkJ5RuzKwBrAgAAAA==.Powderysham:BAAALgAECgcJCwABLgAECgkJNAAHAOUbAA==.',
Pr='Praystatiôn:BAAALgAECgEJAQABLgAECgcJGwAgAHcfAA==.Proshot:BAACLgAFFH8GAAIWAAMJIRjfGwDyAAAWAAMJIRjfGwDyAAAuAAQKfzIAAhYACQk4It4CABQDABYACQk4It4CABQDAAAA.',
Pu='Puddles:BAAALgAECgEJAQAAAA==.',
Pz='Pzalmo:BAAALgAECgMJAwABLgAECgkJHwAFAJkUAA==.',
Ra='Raccoon:BAACLgAFFH8IAAIgAAMJVwZXCQCyAAAgAAMJVwZXCQCyAAAuAAQKfz4AAyAACQmbEVtCANUBACAACQmbEVtCANUBAAoAAQloCxY+ADYAAAAA.Ralor:BAAALgADCgEJAQAAAA==.Ravenhawk:BAAALgAECgYJEAAAAA==.Razza:BAAALgADCgYJCAAAAA==.',
Re='Remember:BAAALgADCgEJAQAAAA==.Renivatio:BAABLgAECn8nAAIGAAgJEhySLwBBAgAGAAgJEhySLwBBAgAAAA==.',
Rh='Rhyntix:BAAALgADCgEJAQAAAA==.',
Ro='Roronoazoro:BAACLgAFFH8cAAIIAAgJVhKDFgD9AQAIAAgJVhKDFgD9AQAuAAQKfyEAAwgACQlIH2ojAH0CAAgACQlIH2ojAH0CACYAAglxEwUmAFQAAAAA.',
Ry='Ryrin:BAABLgAECn8jAAMTAAkJBRAONQB1AQATAAkJBRAONQB1AQAcAAIJ9gdqbgBEAAAAAA==.Ryrìn:BAAALgADCgEJAQAAAA==.Ryrín:BAAALgAECggJEwAAAA==.',
Sa='Samidrac:BAABLgAECn8YAAILAAYJxAJCAQBoAAALAAYJxAJCAQBoAAAAAA==.Sammidormu:BAABLgAECn8jAAQFAAgJ5RNoCgB5AQAFAAcJABVoCgB5AQAEAAcJbAtZNgAgAQALAAEJ2QEPTgAjAAAAAA==.Sanderwoof:BAAALgAECggJCAAAAA==.Saret:BAAALgADCgMJAwAAAA==.Sarzul:BAABLgAECn8VAAMeAAYJ/A8VNADnAAAgAAYJ2gzAmwAiAQAeAAUJThEVNADnAAAAAA==.Satoshie:BAAALgAECggJCQAAAA==.',
Sc='Scerevisiae:BAABLgAECn8VAAMgAAgJOxm6fQA9AQAgAAUJwBu6fQA9AQAeAAQJxBSjLgABAQAAAA==.',
Se='Sedelis:BAABLgAECn8fAAIhAAkJzwr+MQCOAQAhAAkJzwr+MQCOAQAAAA==.Sefirbrena:BAAALgADCgkJAwAAAA==.Selaya:BAAALgAECgEJAQAAAA==.Semnai:BAABLgAECn89AAIZAAkJexYBHABnAgAZAAkJexYBHABnAgAAAA==.Serafín:BAACLgAFFH8HAAIJAAMJ/wQyBACTAAAJAAMJ/wQyBACTAAAuAAQKfzgAAgkACQmkDikiAJcBAAkACQmkDikiAJcBAAAA.Sevilicious:BAAALgADCgQJAwAAAA==.',
Sh='Shaay:BAAALgAECgcJDwAAAA==.Shadowlock:BAAALgAECgEJAgAAAA==.Shadownutt:BAAALgAECgUJBQAAAA==.Shadowpyro:BAAALgAECgEJAQAAAA==.Shamwig:BAAALgADCgUJBQAAAA==.Shazzam:BAAALgAECggJDwAAAA==.Shieldwall:BAABLgAECn8qAAIUAAgJWg/tGwBXAQAUAAgJWg/tGwBXAQAAAA==.',
Si='Silanah:BAAALgAECgEJAQABLgAFFAMJDAAPAB4bAA==.Silverhâwk:BAAALgADCgEJAQAAAA==.Sinastys:BAABLgAECn8aAAIDAAgJ9RCXgQBsAQADAAgJ9RCXgQBsAQAAAA==.',
So='Solone:BAAALgAECgYJEgAAAA==.Sopidia:BAABLgAECn8lAAMPAAkJ+RVxPQC5AQAPAAgJTBVxPQC5AQAiAAUJHQardACOAAAAAA==.Sorvato:BAABLgAECn80AAIIAAkJCxlUIgBIAgAIAAkJCxlUIgBIAgAAAA==.',
Sp='Spiritholy:BAAALgAECgkJAwAAAA==.Spoonzz:BAABLgAECn8xAAMNAAkJDSRlBQD7AgANAAkJDSRlBQD7AgAJAAIJKx9SWQCkAAAAAA==.',
St='Stamavan:BAABLgAECn8kAAIaAAkJzCIjAwD6AgAaAAkJzCIjAwD6AgAAAA==.Starflayer:BAABLgAECn8nAAMIAAkJXxzkJQA2AgAIAAkJbhvkJQA2AgAmAAIJYxr3IAB8AAAAAA==.Steb:BAAALgADCgMJAwAAAA==.Sterjariger:BAAALgAECgYJBgABLgAFFAMJBwAMABUMAA==.',
Su='Sunari:BAAALgAECgMJBgAAAA==.Supermelon:BAABLgAECn8WAAIjAAcJXBFLDQBVAQAjAAcJXBFLDQBVAQAAAA==.',
Sw='Swenior:BAAALgAECgEJAQAAAA==.',
Sy='Syarli:BAAALgAECgcJBwAAAA==.Sylvaeelor:BAAALgAFFAIJAwABLgAFFAQJDgAcAG4TAA==.Sylvanaria:BAACLgAFFH8IAAIPAAMJsyXcAgAlAQAPAAMJsyXcAgAlAQAuAAQKfz4AAg8ACQlbJjoBAMMDAA8ACQlbJjoBAMMDAAAA.Sylvanaris:BAAALgAECgYJEQAAAA==.Systyx:BAABLgAECn8bAAIgAAcJdx/0TAC0AQAgAAcJdx/0TAC0AQAAAA==.',
Ta='Takura:BAAALgAECgkJBwABLgAECgkJDQABAAAAAA==.Talenel:BAAALgAECgQJBAAAAA==.Talyzien:BAAALgADCgYJBwAAAA==.',
Te='Tealan:BAACLgAFFH8HAAMLAAQJugzOGgDpAAALAAQJugzOGgDpAAAEAAEJRgLqawAvAAAuAAQKfzAAAwQACQm0GB4TAEYCAAQACQm0GB4TAEYCAAsACAmpEukcAJ4BAAAA.Tealyn:BAAALgAECgYJBgAAAA==.Teluz:BAAALgAECgQJCgAAAA==.Tendra:BAAALgAECgYJBQAAAA==.Teronreborn:BAABLgAECn8lAAIGAAkJOiWGFAAAAwAGAAkJOiWGFAAAAwAAAA==.',
Th='Thaneer:BAAALgAECgYJBwAAAA==.Thanos:BAABLgAECn8dAAIDAAYJ7Q6KpAA3AQADAAYJ7Q6KpAA3AQAAAA==.Thebadmage:BAAALgAECgcJBAAAAA==.Throstmok:BAACLgAFFH8OAAISAAQJUhCpIQDcAAASAAQJUhCpIQDcAAAuAAQKfzcAAhIACQm3HrAJAHgCABIACQm3HrAJAHgCAAAA.Thràll:BAAALgAECgUJBQAAAA==.Thränton:BAAALgAECgEJAQABLgAECgcJFAAmALwhAA==.Thumbalina:BAAALgAECgYJEQAAAA==.',
To='Totemtuggér:BAAALgADCgIJAgAAAA==.',
Tp='Tpaste:BAAALgADCgcJBwAAAA==.',
Tr='Trampstãmp:BAAALgAECgIJAgAAAA==.Trinitea:BAAALgAECgEJAgAAAA==.Trout:BAAALgADCgYJDAABLgAECgYJCgABAAAAAA==.Trovikk:BAAALgADCgUJBgAAAA==.',
Tu='Turg:BAAALgAECgMJAwABLgAECgQJBwABAAAAAA==.Turgo:BAAALgAECgEJAQABLgAECgQJBwABAAAAAA==.Turgress:BAAALgAECgQJBwAAAA==.',
['Tà']='Tàmber:BAAALgADCgYJBwAAAA==.',
Ul='Ulfast:BAACLgAFFH8GAAIiAAMJ5xGsBQCRAAAiAAMJ5xGsBQCRAAAuAAQKfyUAAiIACAlKHrkaAAsCACIACAlKHrkaAAsCAAAA.',
Va='Valarios:BAAALgAECgYJCgAAAA==.Vannhellsing:BAABLgAECn8nAAIGAAgJJggvnwAtAQAGAAgJJggvnwAtAQAAAA==.Vanyel:BAABLgAECn9XAAIHAAkJMBm9AQCPAQAHAAkJMBm9AQCPAQAAAA==.Vaudorka:BAABLgAECn8cAAIFAAkJIx5RAwBnAgAFAAkJIx5RAwBnAgAAAA==.',
Ve='Vecna:BAAALgADCgMJAwABLgAECgYJCAABAAAAAA==.Veliuz:BAAALgADCgQJBAAAAA==.Velrynth:BAABLgAECn84AAMdAAkJ+BR/EwBFAgAdAAkJVxR/EwBFAgAOAAcJzghySAAXAQAAAA==.Vemal:BAABLgAECn8yAAIMAAkJThk+GwCCAgAMAAkJThk+GwCCAgAAAA==.',
Vo='Vociferoy:BAACLgAFFH8PAAIMAAMJWhpoBgDyAAAMAAMJWhpoBgDyAAAuAAQKf0QAAgwACQl9IUUPANYCAAwACQl9IUUPANYCAAAA.Voidsteffan:BAABLgAECn80AAMeAAkJkhoaAAAzAgAeAAkJkhoaAAAzAgAgAAQJjw4iwQDXAAAAAA==.',
Vr='Vryadox:BAAALgAFFAIJAgABLgAFFAQJDwAgAGwdAA==.',
Vv='Vv:BAACLgAFFH9HAAIIAAkJKCaFAABsAwAIAAkJKCaFAABsAwAuAAQKfzUAAggACQm1JucAANoDAAgACQm1JucAANoDAAAA.',
Vz='Vz:BAAALgADCgUJBQAAAA==.',
Wh='Whoppin:BAAALgAECgIJAgAAAA==.',
Wi='Wiglimparms:BAAALgAECgIJAgAAAA==.',
Wr='Wry:BAAALgAECgMJAwAAAA==.',
Wy='Wysselbow:BAAALgADCggJDQAAAA==.',
['Wá']='Wárranpeace:BAAALgADCgMJAwAAAA==.',
Xa='Xalmo:BAAALgAECgEJAQABLgAECgkJHwAFAJkUAA==.Xalzi:BAAALgADCggJCQABLgAECgcJFAAPAHwVAA==.',
Xi='Xingwong:BAABLgAECn88AAIfAAkJFSbXAQBNAwAfAAkJFSbXAQBNAwAAAA==.',
Za='Zannytoes:BAABLgAECn8mAAMXAAkJpRA3MAC6AQAXAAkJpRA3MAC6AQANAAEJLxFRnwAwAAAAAA==.',
Ze='Zead:BAAALgAECgEJBQAAAA==.Zerana:BAACLgAFFH8NAAIeAAQJmAQBCwDrAAAeAAQJmAQBCwDrAAAuAAQKfxUAAh4ACQnlC1wOAFcBAB4ACQnlC1wOAFcBAAAA.Zeriea:BAAALgADCgEJAQAAAA==.Zevtra:BAAALgADCgEJAQAAAA==.',
Zi='Zie:BAABLgAECn9VAAICAAkJlBquAACPAQACAAkJlBquAACPAQAAAA==.Zikren:BAAALgAECgkJCQAAAA==.',
Zs='Zsinj:BAAALgADCgEJAQAAAA==.',
['Ðo']='Ðonkle:BAABLgAECn8TAAIIAAgJmBy4KwAZAgAIAAgJmBy4KwAZAgAAAA==.',
['Ðr']='Ðrewid:BAAALgADCgEJAQAAAA==.',
['Ñi']='Ñice:BAACLgAFFH8ZAAITAAYJniO0BwDqAQATAAYJniO0BwDqAQAuAAQKfxoAAhMACQkrHugYACcCABMACQkrHugYACcCAAAA.',
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
