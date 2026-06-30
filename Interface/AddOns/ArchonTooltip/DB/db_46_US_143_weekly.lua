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

local lookup = {'Priest-Shadow','Paladin-Retribution','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Unholy','Mage-Frost','DemonHunter-Havoc','Monk-Brewmaster','Warlock-Affliction','Evoker-Preservation','Hunter-BeastMastery','Monk-Windwalker','Priest-Holy','Shaman-Restoration','Paladin-Protection','DeathKnight-Blood','Warrior-Fury','Warrior-Protection','Hunter-Marksmanship','Hunter-Survival','Monk-Mistweaver','Druid-Balance','Druid-Restoration','Druid-Guardian','Druid-Feral','Warrior-Arms','DemonHunter-Devourer','Unknown-Unknown','Priest-Discipline','Warlock-Destruction','Rogue-Subtlety','Warlock-Demonology','Paladin-Holy','Shaman-Elemental','Rogue-Assassination','Rogue-Outlaw','Shaman-Enhancement','DemonHunter-Vengeance',}
local provider = {region='US',realm='Lightninghoof',name='US',type='weekly',zone=46,date='2026-06-27',data={Ab='Abukuma:BAAALgAECgQJBAAAAA==.',
Ac='Aceieus:BAAALgAECgkJAwAAAA==.',
Ad='Adraina:BAAALgADCgEJAQAAAA==.Adrewid:BAAALgADCgQJBAAAAA==.',
Ae='Aelarya:BAABLgAECn8RAAIBAAgJAQYXQgDpAAABAAgJAQYXQgDpAAAAAA==.Aenstalash:BAABLgAECn8hAAICAAgJPyNHJAB0AgACAAgJPyNHJAB0AgAAAA==.Aephium:BAABLgAECn8VAAMDAAcJuwZkYQC2AAADAAYJJgZkYQC2AAAEAAUJtAQVHABsAAAAAA==.Aesilakaersi:BAAALgAECgYJCgAAAA==.Aeson:BAABLgAECn8kAAIFAAkJiBeVRQDyAQAFAAkJiBeVRQDyAQAAAA==.',
Af='Afflictia:BAAALgADCgYJEAAAAA==.',
Ai='Aironel:BAAALgADCgMJAwAAAA==.',
Al='Alanza:BAAALgAFFAEJAQAAAA==.Alaure:BAAALgADCgIJAgAAAA==.Alessia:BAAALgAECgIJAgAAAA==.Alfonsoo:BAAALgADCgEJAQAAAA==.Alida:BAAALgAECgQJBAAAAA==.Alistur:BAABLgAECn8mAAIGAAgJygvcCgADAQAGAAgJygvcCgADAQAAAA==.',
Am='Amanna:BAAALgAECgMJAwABLgAECgkJLwAHAP8lAA==.Amoona:BAAALgAECgYJEgABLgAECgkJLwAHAP8lAA==.',
An='Anoriia:BAAALgADCgUJBQAAAA==.',
Ar='Arcnid:BAAALgADCgYJBgAAAA==.Arfas:BAAALgADCgQJBAAAAA==.Arthraz:BAABLgAECn8kAAIIAAkJsxwHDAB1AgAIAAkJsxwHDAB1AgABLgAECgkJKgAJAAAiAA==.',
As='Astara:BAAALgAECgQJBAAAAA==.Astraa:BAAALgAECgIJAgAAAA==.Astrex:BAABLgAECn9MAAQKAAkJehhJAAB5AgAKAAkJehhJAAB5AgAEAAEJjAdeBAAdAAADAAEJJwHTqAAMAAAAAA==.',
Au='Aunaturale:BAAALgAECgkJAwAAAA==.Aurali:BAAALgAECgEJAQAAAA==.Aureliá:BAABLgAECn8XAAILAAcJnQrCjAAlAQALAAcJnQrCjAAlAQAAAA==.',
['Aü']='Aütobot:BAABLgAECn8iAAIMAAkJMw20JgCAAQAMAAkJMw20JgCAAQAAAA==.',
Ba='Badgirl:BAACLgAFFH8MAAINAAQJgREoGQDyAAANAAQJgREoGQDyAAAuAAQKfxkAAw0ACAm+E9w1ACoBAA0ABgnBFtw1ACoBAAEABgktCuFLAOAAAAAA.Balnar:BAABLgAECn8gAAIOAAcJEBffBABMAQAOAAcJEBffBABMAQABLgAECggJHwAPANsWAA==.Balraga:BAABLgAECn8ZAAIHAAgJUQrjKwAhAQAHAAgJUQrjKwAhAQAAAA==.Bargrivyek:BAAALgAECgYJCQAAAA==.Bayded:BAAALgADCgEJAQAAAA==.',
Be='Beastboyy:BAAALgAECgUJBQAAAA==.Bega:BAACLgAFFH8rAAMFAAgJ9hpNDQB0AgAFAAgJ9hpNDQB0AgAQAAEJAABPUwAAAAAuAAQKf0EAAwUACQnoJXoFAE8DAAUACQnoJXoFAE8DABAABgkrFzslABUBAAAA.Benton:BAAALgAECgQJCAAAAA==.',
Bi='Bigglimpie:BAAALgAECgYJDQAAAA==.',
Bl='Bloodlustplz:BAABLgAECn8qAAMRAAkJshdCLACjAQARAAcJLx5CLACjAQASAAgJLQ/NGwBYAQAAAA==.',
Bo='Bobster:BAABLgAECn8kAAIGAAkJuxHlYQC7AQAGAAkJuxHlYQC7AQAAAA==.Bonepaw:BAAALgAECgMJBAABLgAECgcJFAAOAHwVAA==.Booyea:BAACLgAFFH8IAAIQAAMJAReSCQDDAAAQAAMJAReSCQDDAAAuAAQKfz4AAhAACQklHBMLAF8CABAACQklHBMLAF8CAAAA.',
Br='Brew:BAAALgAECgcJCwAAAA==.Brewwnor:BAAALgAECggJDAAAAA==.Brickdemkeys:BAABLgAECn8fAAIGAAgJPBr/YwC2AQAGAAgJPBr/YwC2AQAAAA==.Brisfloggnaw:BAAALgAFFAEJAQAAAA==.',
Ca='Caladk:BAAALgADCgUJBQABLgAFFAcJIQATAD8fAA==.Calamuelis:BAACLgAFFH8hAAQTAAcJPx/WBwCeAQATAAcJ7hvWBwCeAQAUAAUJTyLyCgBvAQALAAIJehymKgBuAAAuAAQKfx0ABBMACAnSJLsNANcCABMACAmWJLsNANcCABQABAn5JIowACYBAAsAAQkIJhv2AGkAAAAA.Caliope:BAABLgAECn8iAAMVAAkJdRWfJQD3AQAVAAkJdRWfJQD3AQAMAAQJpQnnBAC3AAAAAA==.Capsasin:BAAALgADCgUJBQAAAA==.Carnage:BAAALgAFFAIJAgAAAA==.Cazlek:BAAALgAECgQJCwAAAA==.',
Ce='Celery:BAAALgAECgQJBAABLgAECgkJKgAJAAAiAA==.Celldweller:BAAALgAECgYJCgAAAA==.Cerdred:BAABLgAECn8dAAIWAAUJARDLSQAEAQAWAAUJARDLSQAEAQAAAA==.Ceredis:BAAALgAECgEJAQAAAA==.Cerelus:BAABLgAECn8gAAIGAAkJWA9oVQDdAQAGAAkJWA9oVQDdAQAAAA==.',
Ch='Chaac:BAAALgAECgYJDAABLgAECggJFgAKALITAA==.Chmmr:BAAALgADCgMJAwAAAA==.Chowilawu:BAAALgADCgkJCQAAAA==.Chriswilsonn:BAAALgAECgQJCAAAAA==.Chuca:BAAALgAECgYJBgAAAA==.Chucalu:BAABLgAECn8WAAUXAAgJVh4ANwDLAQAXAAYJUyAANwDLAQAYAAQJCx7wEQBVAQAWAAIJih8+WgCqAAAZAAEJLwbeMgA2AAAAAA==.Chéwtoy:BAAALgAECgIJBAAAAA==.',
Cl='Clax:BAAALgAECgIJBQAAAA==.',
Co='Cobeam:BAAALgAECgUJEQAAAA==.Cowpernicus:BAABLgAECn8iAAIXAAkJ7SAJBwBHAwAXAAkJ7SAJBwBHAwABLgAFFAMJDQAOAB4bAA==.',
Cr='Crungleman:BAABLgAECn8YAAILAAcJuRi1XwCIAQALAAcJuRi1XwCIAQAAAA==.',
Ct='Cthuwu:BAAALgAECgQJBAABLgAECggJFgAKALITAA==.',
Cu='Curoi:BAABLgAECn8rAAMZAAkJjxeECABEAgAZAAkJjxeECABEAgAXAAgJRAozeQDsAAAAAA==.',
['Cã']='Cãrloy:BAACLgAFFH8eAAIRAAQJlBv2GwBBAQARAAQJlBv2GwBBAQAuAAQKf1sAAxEACQl+IhwHAOwCABEACQl+IhwHAOwCABoAAgkpIexEALUAAAAA.',
['Cê']='Cêlestial:BAABLgAECn8vAAMHAAkJ/yVwAAAVAwAHAAkJyiVwAAAVAwAbAAgJ9SLmGwBtAgAAAA==.',
Da='Daedalas:BAABLgAECn8aAAMBAAkJJx/uDgBqAgABAAkJJx/uDgBqAgANAAIJMAKAawA8AAAAAA==.Daedtoo:BAAALgAECgQJBAABLgAECgkJGgABACcfAA==.Damonk:BAAALgADCgYJBgABLgAECgkJIAASAOIaAA==.Danevolent:BAABLgAECn8gAAMNAAcJ9yJ9DQCAAgANAAcJ9yJ9DQCAAgABAAQJEA0/YACYAAABLgAECgkJIAASAOIaAA==.Danzaster:BAAALgADCgQJBAAAAA==.Darkxsoul:BAABLgAECn8fAAIPAAgJ2xbBEAC4AQAPAAgJ2xbBEAC4AQAAAA==.Darthknull:BAACLgAFFH8SAAICAAQJBRe8OAA7AQACAAQJBRe8OAA7AQAuAAQKfzwAAgIACQnQIXAYALECAAIACQnQIXAYALECAAAA.Darthtalon:BAAALgAECgkJDgABLgAFFAQJEgACAAUXAA==.',
De='Deadeyedicky:BAAALgAECgkJBwAAAA==.Deathmachine:BAAALgADCgUJBQAAAA==.Deathniight:BAAALgAECgUJBAAAAA==.Deathseer:BAAALgAECgcJDgAAAA==.Deathwood:BAAALgADCgUJBgABLgAECgEJAQAcAAAAAA==.Deatthdecay:BAAALgAECggJBAAAAA==.Deitrichx:BAABLgAECn8pAAITAAkJnxmVBgApAgATAAkJnxmVBgApAgAAAA==.Delley:BAAALgADCgEJAQAAAA==.Deminestra:BAAALgAECgQJBAAAAA==.Deminestrea:BAABLgAECn8aAAIQAAYJchCgKgADAQAQAAYJchCgKgADAQAAAA==.Demonswhere:BAAALgADCgQJBAAAAA==.Devilscreed:BAAALgAECgEJAQAAAA==.',
Di='Dingleberrys:BAAALgADCgEJAQAAAA==.Dippindots:BAAALgAECgYJCAAAAA==.Disshammy:BAAALgAFFAIJAgABLgAFFAgJIgADANEhAA==.Dittoz:BAAALgADCgUJBAAAAA==.',
Do='Dolfcritler:BAAALgAECgQJBQAAAA==.Dolfcrittler:BAAALgADCgEJAQAAAA==.Donkform:BAAALgAECgkJEgAAAA==.Donniyii:BAAALgAECgcJBwABLgAECgkJOwAdAJQfAA==.Doomrider:BAAALgADCgYJBgAAAA==.Dottzz:BAABLgAECn8aAAIeAAYJ8B27FQCcAQAeAAYJ8B27FQCcAQAAAA==.',
Dr='Draconith:BAACLgAFFH8cAAIKAAUJChKtBQDdAAAKAAUJChKtBQDdAAAuAAQKfzcAAgoACQmSG00FAMMCAAoACQmSG00FAMMCAAAA.Dramoo:BAAALgAECgMJAwAAAA==.Draqkmar:BAABLgAECn8fAAILAAYJTwviEwCYAAALAAYJTwviEwCYAAAAAA==.Dreddwing:BAABLgAECn8WAAMKAAgJshOaEADCAQAKAAcJcBWaEADCAQADAAIJJg8iewBrAAAAAA==.Dredfox:BAAALgAECgIJAgABLgAECgkJRwAWAPURAA==.Drunkenoodle:BAAALgADCgYJBgAAAA==.',
Du='Dunsparrow:BAACLgAFFH8NAAIOAAMJHhsQQADkAAAOAAMJHhsQQADkAAAuAAQKf0cAAg4ACQnfIkgFAF8DAA4ACQnfIkgFAF8DAAAA.Durzul:BAAALgAECgEJAQAAAA==.',
Ei='Eightyone:BAAALgAECggJDwAAAA==.Eindraken:BAACLgAFFH8WAAIKAAUJwwaVGwDeAAAKAAUJwwaVGwDeAAAuAAQKfzkAAgoACQn7EjENAP4BAAoACQn7EjENAP4BAAAA.Eiroh:BAABLgAECn8UAAIIAAkJkhtMDwBHAgAIAAkJkhtMDwBHAgAAAA==.Eisis:BAABLgAECn8/AAIZAAkJVBCVFAB6AQAZAAkJVBCVFAB6AQAAAA==.',
El='Elanalué:BAAALgAECgYJEAABLgAECgkJIgAVAHUVAA==.',
En='Enamel:BAAALgAECgMJAwABLgAFFAMJCAAfAM4RAA==.',
Er='Erixee:BAAALgAECgUJBgAAAA==.Erroz:BAAALgADCgIJAQAAAA==.',
Es='Eshonäi:BAABLgAECn8aAAIgAAYJtRHRjgAdAQAgAAYJtRHRjgAdAQAAAA==.Espriesso:BAABLgAECn8VAAQdAAgJAQ1uMwBKAQAdAAcJ3wtuMwBKAQABAAQJvgSDZQCGAAANAAIJDAecdABWAAABLgAECgkJLAAIALEPAA==.',
Ev='Everbark:BAAALgADCgEJAQAAAA==.Evodragker:BAABLgAECn8kAAMDAAkJKxR2IQDOAQADAAkJKxR2IQDOAQAKAAEJcAkEPAAzAAAAAA==.',
Fe='Feider:BAAALgAECgEJAQAAAA==.Felais:BAABLgAFFH8GAAIXAAQJpwfTPQC4AAAXAAQJpwfTPQC4AAAAAA==.Feldron:BAAALgAECgcJEwAAAA==.Felkaos:BAAALgADCgEJAQAAAA==.Fellura:BAAALgAECgYJDAAAAA==.Femaledawg:BAAALgADCgcJEAAAAA==.',
Fi='Fingor:BAAALgAECgYJBwAAAA==.',
Fl='Flamecube:BAAALgAECgEJAgAAAA==.Flashx:BAABLgAECn8kAAMhAAgJ3iDsCQDtAgAhAAgJ3iDsCQDtAgACAAEJQQzbmQEvAAAAAA==.',
Fo='Foxxeyineawo:BAAALgADCgcJCAAAAA==.',
Fr='Frevmk:BAAALgAECgEJAgAAAA==.Frofrohunter:BAABLgAECn8sAAMLAAkJaB+kEgCiAgALAAkJaB+kEgCiAgATAAUJAxLZTgAUAQAAAA==.Frofrolock:BAAALgAECgcJDgAAAA==.Froggie:BAABLgAECn8UAAMOAAcJfBWfUQBsAQAOAAcJfBWfUQBsAQAiAAMJXQ/iaACgAAAAAA==.Froshaman:BAAALgAECgEJAQAAAA==.',
Fu='Fuzywuuzy:BAACLgAFFH8NAAIXAAMJ1BR0OwDAAAAXAAMJ1BR0OwDAAAAuAAQKfyUAAxcACAnUI+ELAAIDABcACAnUI+ELAAIDABYABwk6Fv4nAJABAAAA.',
Ga='Gazdorn:BAABLgAECn8qAAISAAkJeRJ8EgDDAQASAAkJeRJ8EgDDAQAAAA==.',
Ge='Genebelcher:BAAALgAECgEJAQAAAA==.',
Gh='Ghost:BAABLgAECn8kAAIjAAkJOhyiBQAbAgAjAAkJOhyiBQAbAgAAAA==.',
Gi='Gigof:BAABLgAECn8rAAMWAAkJPxJ7JQCgAQAWAAgJ0RJ7JQCgAQAXAAcJ/AqZggC0AAAAAA==.',
Gl='Glissa:BAABLgAECn8UAAQJAAcJdCWRAQDTAgAJAAcJEiWRAQDTAgAgAAMJhSJYogAUAQAeAAIJjxpcRACkAAAAAA==.',
Go='Gobah:BAABLgAECn8YAAMfAAgJ5hXRGQDLAQAfAAgJ5hXRGQDLAQAkAAUJsQctFwCmAAAAAA==.',
Gt='Gt:BAAALgAECgQJCwAAAA==.',
Gu='Gulldan:BAABLgAECn8iAAIgAAgJXxjCNgD+AQAgAAgJXxjCNgD+AQAAAA==.',
Gw='Gwyndolin:BAAALgADCgUJBQAAAA==.',
Ha='Habanero:BAAALgAECgQJBgABLgAECgkJKgAJAAAiAA==.Hadory:BAABLgAECn8YAAMCAAkJDhg0UgDSAQACAAkJDhg0UgDSAQAhAAQJWhm6SwAMAQAAAA==.Harrowhark:BAABLgAECn9BAAQJAAkJUwo9EgBEAQAgAAkJhgnSYAB+AQAJAAgJuwk9EgBEAQAeAAQJyQVDMgBVAAAAAA==.',
He='Hellzzdemon:BAABLgAECn8hAAIHAAkJLw+lIQBrAQAHAAkJLw+lIQBrAQAAAA==.Hendricks:BAAALgAECgQJCgAAAA==.Hexinverter:BAAALgAECgQJCQAAAA==.Hexzard:BAAALgADCgQJBAABLgAECgUJEQAcAAAAAA==.Hezekiiah:BAAALgAECgYJDQAAAA==.',
Ho='Holeecow:BAAALgADCgIJAgABLgAFFAMJDQAOAB4bAA==.Holycannoli:BAAALgAECgkJDwAAAA==.Horiffic:BAAALgAECgcJEwAAAA==.Horok:BAAALgAECgYJDQAAAA==.Hotsforthots:BAAALgAECgUJBQAAAA==.Hotwheels:BAAALgAECgMJAwAAAA==.',
Hu='Hubert:BAABLgAECn8WAAIVAAgJwQkYVwAVAQAVAAgJwQkYVwAVAQAAAA==.Hubertdale:BAAALgAECgMJAwAAAA==.Hulkblood:BAAALgAECgEJAQAAAA==.Hummingbrook:BAAALgAECgcJDAABLgAFFAgJHAAbAFYSAA==.',
Hy='Hypandia:BAAALgAFFAEJAQABLgAFFAMJDQAOAB4bAA==.',
Ic='Ichaerus:BAAALgAECgQJBQABLgAECgkJGgABACcfAA==.Ichtheblack:BAAALgAECgcJCQABLgAECgkJGgABACcfAA==.Ichtu:BAAALgAECgEJAQABLgAECgkJGgABACcfAA==.',
Ii='Iilli:BAABLgAECn87AAMdAAkJlB9fBwAGAwAdAAkJlB9fBwAGAwABAAkJnxvzDQB2AgAAAA==.',
In='Inari:BAABLgAECn8XAAIBAAkJSgt5LAByAQABAAkJSgt5LAByAQAAAA==.Inkkubus:BAACLgAFFH8dAAQeAAcJNRblDgC8AAAgAAQJaRs/bQDoAAAeAAMJXArlDgC8AAAJAAIJUxYYHwBSAAAuAAQKfxcABCAACQmPHuU6AO8BACAABwnZH+U6AO8BAB4AAwnpG74WAO4AAAkAAQkAABEnAFUAAAAA.Instagatorz:BAAALgADCgUJBgAAAA==.',
Iq='Iq:BAAALgAECgEJAQAAAA==.',
Ir='Ironfur:BAAALgAECgUJBQABLgAFFAYJFAAhAHARAA==.',
Iw='Iwkms:BAACLgAFFH8OAAIZAAQJihaWCAAhAQAZAAQJihaWCAAhAQAuAAQKfyMAAhkACAliIzMCADEDABkACAliIzMCADEDAAEuAAUUBQkGACQAwhYA.',
Ja='Jade:BAABLgAECn8dAAIIAAYJ9CTwFQD9AQAIAAYJ9CTwFQD9AQAAAA==.Jatheo:BAAALgADCgIJAgAAAA==.',
Je='Jenliz:BAAALgADCgEJAQABLgAECgYJEQAcAAAAAA==.Jeronor:BAAALgAECgIJAgAAAA==.',
Ji='Jimmick:BAABLgAECn8WAAIOAAcJfyNXEQDEAgAOAAcJfyNXEQDEAgABLgAECgkJGAACAA4YAA==.Jisung:BAABLgAECn8UAAMlAAYJkQLCKwCbAAAlAAYJkQLCKwCbAAAiAAIJHAE9xgARAAAAAA==.',
Jo='Jorad:BAAALgADCgEJAQAAAA==.',
Jt='Jtheman:BAAALgAECgQJBAAAAA==.',
Ju='Junebugg:BAAALgADCgEJAQAAAA==.',
Ka='Kaing:BAAALgAECgYJCwAAAA==.Kaissa:BAAALgAECgEJAQAAAA==.Kalena:BAACLgAFFH8IAAIGAAMJVgMdLQCRAAAGAAMJVgMdLQCRAAAuAAQKfz4AAgYACQnnDhliALsBAAYACQnnDhliALsBAAAA.Kalöna:BAAALgADCgEJAQAAAA==.Kandikkiss:BAAALgAECgUJDQAAAA==.Kaos:BAABLgAECn8jAAIGAAkJ+hFeXgDEAQAGAAkJ+hFeXgDEAQAAAA==.Kariatyda:BAABLgAECn8uAAILAAkJMxgIGwBlAgALAAkJMxgIGwBlAgAAAA==.Kasai:BAAALgADCgMJAwABLgAECgkJLwACAEAaAA==.Kassandra:BAACLgAFFH8PAAIGAAMJ2R5/HwDaAAAGAAMJ2R5/HwDaAAAuAAQKfz4AAgYACQnvHJkcALECAAYACQnvHJkcALECAAAA.Kay:BAAALgAECgcJCQAAAA==.Kayden:BAABLgAECn8aAAIVAAYJhBh2JACQAQAVAAYJhBh2JACQAQABLgAECggJGwAhAFUcAA==.Kayn:BAAALgAECgIJAgAAAA==.',
Ke='Keelistus:BAAALgAECgQJBAAAAA==.Kekio:BAAALgAECgcJDAAAAA==.Kelisola:BAAALgADCgEJAQAAAA==.Kelzor:BAAALgAECgEJAQAAAA==.Keruu:BAAALgAECgcJBwAAAA==.',
Kh='Khaylorn:BAAALgAECgMJBgAAAA==.Kháòs:BAAALgAECgUJCgAAAA==.',
Ki='Kiloton:BAABLgAECn8sAAIYAAkJqBRyEwC+AQAYAAkJqBRyEwC+AQAAAA==.Kinari:BAABLgAECn8ZAAQhAAkJlBaLAQDPAQAhAAkJlBaLAQDPAQAPAAEJfwEmWgAbAAACAAEJKQKxzwEZAAAAAA==.Kitzy:BAABLgAECn8lAAIGAAkJeQf7nABAAQAGAAkJeQf7nABAAQAAAA==.',
Kl='Klapso:BAAALgADCgYJDQAAAA==.Klippertdk:BAACLgAFFH8FAAIFAAMJMw6IJgDKAAAFAAMJMw6IJgDKAAAuAAQKfzkAAgUACQkCGRorAFQCAAUACQkCGRorAFQCAAAA.Klugamonk:BAAALgADCgUJBQAAAA==.Klutz:BAABLgAECn8qAAIXAAkJXw86NgDAAQAXAAkJXw86NgDAAQAAAA==.',
Ko='Korgan:BAAALgAECggJDwAAAA==.Korgriku:BAAALgADCgMJAwAAAA==.',
Kr='Kreznor:BAAALgAECgIJAgAAAA==.',
Ku='Kurzo:BAACLgAFFH8NAAIRAAQJCx+LEACBAQARAAQJCx+LEACBAQAuAAQKfzsAAxEACQnrIuIGAPACABEACQnrIuIGAPACABIABQmtEussANoAAAAA.',
Ky='Kylarian:BAABLgAECn8iAAIHAAkJyQatKwAjAQAHAAkJyQatKwAjAQAAAA==.Kyntara:BAAALgAECgYJDQAAAA==.Kyronian:BAAALgAECgYJDwAAAA==.',
['Kâ']='Kâsâi:BAABLgAECn8vAAICAAkJQBrQAgDzAQACAAkJQBrQAgDzAQAAAA==.',
La='Lachancea:BAAALgAECgEJAQABLgAECggJFQAgADsZAA==.Lakshmee:BAAALgAECgcJDgAAAA==.',
Le='Ledarm:BAAALgAECggJEwAAAA==.Leigin:BAAALgADCgYJBgAAAA==.Lexxi:BAACLgAFFH8HAAICAAMJvg1RHAC6AAACAAMJvg1RHAC6AAAuAAQKfzoAAgIACQlCFdNDAPsBAAIACQlCFdNDAPsBAAAA.',
Li='Lifewing:BAAALgAECgUJDAAAAA==.Lightbehunt:BAAALgAECgQJBgAAAA==.Lightfivhapy:BAAALgAECgcJEgAAAA==.Lightsglory:BAAALgADCgMJAwAAAA==.Lilly:BAAALgAECgYJCgAAAA==.Livaless:BAAALgADCgQJBAABLgAECgkJJQAgAFAiAA==.',
Lu='Lucialyn:BAAALgAECgcJDAAAAA==.',
Ly='Lyllith:BAABLgAECn8cAAIjAAYJjREWDABkAQAjAAYJjREWDABkAQAAAA==.Lysende:BAAALgADCgQJBAAAAA==.',
Ma='Madamenoodle:BAAALgADCgkJCQAAAA==.Magnass:BAAALgADCgYJBgABLgAECgkJIAASAOIaAA==.Magnius:BAAALgADCgEJAQAAAA==.Mahoa:BAAALgAECgEJAQAAAA==.Mal:BAAALgAECggJCAAAAA==.Mastablasta:BAAALgAECgQJCQAAAA==.Maursaline:BAABLgAECn8lAAIXAAkJqge7WgAnAQAXAAkJqge7WgAnAQAAAA==.Mawea:BAAALgAECgUJDAAAAA==.Mawks:BAACLgAFFH8JAAIUAAIJlRKlCACcAAAUAAIJlRKlCACcAAAuAAQKfz8AAhQACQktG6MLAGcCABQACQktG6MLAGcCAAAA.',
Mc='Mcstukes:BAAALgAECgQJCAAAAA==.',
Me='Medeas:BAAALgAECgUJCgAAAA==.Meragos:BAAALgAECgMJAwAAAA==.Meteor:BAAALgADCgQJBAAAAA==.',
Mi='Migzeviltwin:BAAALgAECgEJAgAAAA==.Mimicz:BAAALgADCgUJBQAAAA==.Minitry:BAAALgAECgEJAgAAAA==.Mixon:BAAALgAECgEJAgAAAA==.Mixxon:BAAALgAECgYJDwAAAA==.',
Mo='Moinion:BAAALgADCgQJCAAAAA==.Moldbreather:BAAALgAECgEJAQAAAA==.Moomooimacow:BAAALgAECgQJBAAAAA==.Moomoomonkey:BAABLgAECn8fAAIiAAkJMhfiHQDzAQAiAAkJMhfiHQDzAQAAAA==.Morhgana:BAAALgAECgYJDwAAAA==.',
Ms='Mstea:BAAALgAECgEJAQAAAA==.',
Mx='Mxmlxxix:BAABLgAECn8jAAMNAAgJygGXSwC1AAANAAgJygGXSwC1AAABAAIJXwHWZQAtAAAAAA==.',
My='Mylosh:BAAALgAECgQJBAABLgAECgkJGAACAA4YAA==.',
['Mö']='Mördecai:BAAALgAECgQJBAAAAA==.',
Na='Naija:BAAALgAECgEJAgAAAA==.Nati:BAAALgAECgUJBQAAAA==.',
Ne='Nephele:BAAALgAECgEJAgAAAA==.Neptune:BAAALgAECgQJCAAAAA==.Newport:BAAALgAECgMJBAABLgAFFAMJCAAfAM4RAA==.',
Ni='Nikorobin:BAAALgAECgQJBwABLgAFFAgJHAAbAFYSAA==.Nilius:BAAALgAECgEJAQABLgAECgkJGgABACcfAA==.',
No='Noodles:BAAALgADCgkJDAABLgAECggJIgAbAH0WAA==.Norgalina:BAAALgADCgUJBQAAAA==.',
Ny='Nymara:BAABLgAECn8eAAIPAAgJ8RH+FgBpAQAPAAgJ8RH+FgBpAQABLgAECgkJFAAIAJIbAA==.',
['Ní']='Níce:BAAALgAECgIJAwAAAA==.',
['Nü']='Nügs:BAAALgAECggJEwAAAA==.Nüguns:BAAALgAECgcJEQAAAA==.',
Od='Odyssey:BAAALgAECgUJBQABLgAFFAMJCAAfAM4RAA==.',
Ol='Olei:BAAALgADCgUJBQAAAA==.',
Or='Orlick:BAAALgAECgEJAQAAAA==.Orrok:BAAALgADCgYJBwAAAA==.',
Pa='Painlink:BAAALgAECgUJCQABLgAECgkJKQARAHkRAA==.Painnkiller:BAACLgAFFH8LAAILAAMJCBmCGADeAAALAAMJCBmCGADeAAAuAAQKfzgAAgsACQnKHUkYAJUCAAsACQnKHUkYAJUCAAAA.Papyto:BAAALgADCgYJBwAAAA==.Parsley:BAABLgAECn8qAAMJAAkJACLCAAAhAwAJAAkJACLCAAAhAwAgAAMJmxmGwwDGAAAAAA==.Paxis:BAAALgAECgkJDgAAAA==.',
Pe='Perriwinkle:BAACLgAFFH8HAAIZAAMJtwxrAwC3AAAZAAMJtwxrAwC3AAAuAAQKf08ABBkACQkPH78DANECABkACQkPH78DANECABgACQnvEXoDAP4AABcABAk/DC2KAKMAAAAA.Perseus:BAAALgADCgMJAwAAAA==.',
Ph='Phission:BAAALgADCgEJAQAAAA==.Phobya:BAABLgAECn8nAAIXAAgJNBzWHABfAgAXAAgJNBzWHABfAgAAAA==.Phylloxeras:BAABLgAECn9LAAIFAAkJ5SXxAgBwAwAFAAkJ5SXxAgBwAwAAAA==.',
Pl='Pleasure:BAAALgADCgMJAwAAAA==.Pleggashroom:BAAALgADCgEJAQAAAA==.',
Po='Powder:BAAALgAECgMJAwAAAA==.Powders:BAABLgAECn81AAIGAAkJsRywKwBrAgAGAAkJsRywKwBrAgAAAA==.Powderysham:BAAALgAECgcJCwABLgAECgkJNQAGALEcAA==.',
Pr='Praystatiôn:BAAALgAECgEJAQABLgAECgcJGwAgAHcfAA==.Proshot:BAACLgAFFH8HAAIUAAMJXhjfGwDyAAAUAAMJXhjfGwDyAAAuAAQKfzIAAhQACQk4It0CABQDABQACQk4It0CABQDAAAA.',
Pu='Puddles:BAAALgAECgEJAQAAAA==.',
Pz='Pzalmo:BAAALgAECgMJAwABLgAECgkJHwAEAJkUAA==.',
Ra='Raccoon:BAACLgAFFH8IAAIgAAMJVwa9HwCrAAAgAAMJVwa9HwCrAAAuAAQKfz4AAyAACQmbEVxCANUBACAACQmbEVxCANUBAAkAAQloCxU+ADYAAAAA.Rahala:BAAALgAECgUJBQAAAA==.Ralor:BAAALgADCgEJAQAAAA==.Ravenhawk:BAAALgAECgYJEAAAAA==.Razza:BAAALgADCgYJCAAAAA==.',
Re='Remember:BAAALgADCgEJAQAAAA==.Renivatio:BAABLgAECn8qAAIFAAkJcRteAwC3AQAFAAkJcRteAwC3AQAAAA==.',
Rh='Rhyntix:BAAALgADCgEJAQAAAA==.',
Ro='Ronstådt:BAAALgADCgEJAQAAAA==.Roronoazoro:BAACLgAFFH8cAAIbAAgJVhJyFgD9AQAbAAgJVhJyFgD9AQAuAAQKfyEAAxsACQlIH2ojAH0CABsACQlIH2ojAH0CACYAAglxEwUmAFQAAAAA.',
Ry='Ryrin:BAABLgAECn8mAAMRAAkJBRAQNQB1AQARAAkJBRAQNQB1AQAaAAQJMgpzBQCAAAAAAA==.Ryrìn:BAAALgADCgEJAQAAAA==.Ryrín:BAAALgAECggJEwAAAA==.',
['Rë']='Rëggië:BAAALgAECgIJAgAAAA==.',
Sa='Samidrac:BAABLgAECn8aAAIKAAcJjQIeAwB3AAAKAAcJjQIeAwB3AAAAAA==.Sammidormu:BAABLgAECn8jAAQEAAgJ5RNoCgB5AQAEAAcJABVoCgB5AQADAAcJbAtZNgAgAQAKAAEJ2QEPTgAjAAAAAA==.Sanderwoof:BAAALgAECggJCAAAAA==.Saret:BAAALgADCgMJAwAAAA==.Sarzul:BAABLgAECn8VAAMeAAYJ/A8VNADnAAAgAAYJ2gzAmwAiAQAeAAUJThEVNADnAAAAAA==.Satoshie:BAAALgAECggJCQAAAA==.Sayang:BAAALgAECgMJAwABLgAECgkJOAAXABsfAA==.',
Sc='Scerevisiae:BAABLgAECn8VAAMgAAgJOxm9fQA9AQAgAAUJwBu9fQA9AQAeAAQJxBSjLgABAQAAAA==.',
Se='Sedelis:BAABLgAECn8fAAIhAAkJzwr+MQCOAQAhAAkJzwr+MQCOAQAAAA==.Sefirbrena:BAAALgADCgkJAwAAAA==.Selaya:BAAALgAECgEJAQAAAA==.Semnai:BAABLgAECn8+AAIXAAkJ+Bb/GwBnAgAXAAkJ+Bb/GwBnAgAAAA==.Serafín:BAACLgAFFH8HAAIIAAMJ/wSTDQCHAAAIAAMJ/wSTDQCHAAAuAAQKfzgAAggACQmkDisiAJcBAAgACQmkDisiAJcBAAAA.Sevilicious:BAAALgADCgQJAwAAAA==.',
Sh='Shaay:BAAALgAFFAIJAgAAAA==.Shadowlock:BAAALgAECgEJAgAAAA==.Shadownutt:BAAALgAECgUJBQAAAA==.Shadowpyro:BAAALgAECgEJAQAAAA==.Shamwig:BAAALgADCgUJBQAAAA==.Shazzam:BAAALgAECggJEAAAAA==.Shieldwall:BAABLgAECn8qAAISAAgJWg/tGwBXAQASAAgJWg/tGwBXAQAAAA==.',
Si='Silanah:BAAALgAECgEJAQABLgAFFAMJDQAOAB4bAA==.Silverhâwk:BAAALgADCgEJAQAAAA==.Sinastys:BAABLgAECn8aAAICAAgJ9RCWgQBsAQACAAgJ9RCWgQBsAQAAAA==.',
Sn='Snoots:BAAALgADCgEJAQAAAA==.',
So='Solone:BAABLgAECn8UAAIbAAYJ6w4tlAD4AAAbAAYJ6w4tlAD4AAAAAA==.Somavra:BAAALgAECgMJBgAAAA==.Sopidia:BAABLgAECn8lAAMOAAkJ+RV0PQC5AQAOAAgJTBV0PQC5AQAiAAUJHQatdACOAAAAAA==.Sorvato:BAABLgAECn85AAIbAAkJNRlRIgBIAgAbAAkJNRlRIgBIAgAAAA==.',
Sp='Spiritholy:BAAALgAECgkJBQAAAA==.Spoonzz:BAABLgAECn8xAAMMAAkJDSRlBQD7AgAMAAkJDSRlBQD7AgAIAAIJKx9TWQCkAAAAAA==.',
St='Stamavan:BAABLgAECn8kAAIYAAkJzCIjAwD6AgAYAAkJzCIjAwD6AgAAAA==.Starflayer:BAABLgAECn8nAAMbAAkJXxziJQA2AgAbAAkJbhviJQA2AgAmAAIJYxr3IAB8AAAAAA==.Steb:BAAALgADCgMJAwAAAA==.Sterjariger:BAAALgAECgYJBgABLgAFFAQJBwAJADULAA==.',
Su='Sunari:BAAALgAECgMJBgAAAA==.Supermelon:BAABLgAECn8WAAIjAAcJXBFKDQBVAQAjAAcJXBFKDQBVAQAAAA==.',
Sw='Swenior:BAAALgAECgEJAQAAAA==.',
Sy='Syarli:BAAALgAECgcJBwAAAA==.Sylvaeelor:BAAALgAFFAIJAwABLgAFFAQJDgAaAG4TAA==.Sylvanaria:BAACLgAFFH8IAAIOAAMJsyXrCQAcAQAOAAMJsyXrCQAcAQAuAAQKfz4AAg4ACQlbJjoBAMMDAA4ACQlbJjoBAMMDAAAA.Sylvanaris:BAAALgAECgYJEQAAAA==.Systyx:BAABLgAECn8bAAIgAAcJdx/1TAC0AQAgAAcJdx/1TAC0AQAAAA==.',
Ta='Takura:BAAALgAECgkJBwABLgAECgkJDQAcAAAAAA==.Talenel:BAAALgAECgQJBAAAAA==.Talyzien:BAAALgADCgYJBwAAAA==.',
Te='Tealan:BAACLgAFFH8HAAMKAAQJugzLGgDpAAAKAAQJugzLGgDpAAADAAEJRgLpawAvAAAuAAQKfzAAAwMACQm0GBwTAEYCAAMACQm0GBwTAEYCAAoACAmpEukcAJ4BAAAA.Tealyn:BAAALgAECgYJBgAAAA==.Teluz:BAAALgAECgQJCgAAAA==.Tendra:BAAALgAECgYJBQAAAA==.Teronreborn:BAABLgAECn8lAAIFAAkJOiWGFAAAAwAFAAkJOiWGFAAAAwAAAA==.',
Th='Thaneer:BAAALgAECgYJBwAAAA==.Thanos:BAABLgAECn8dAAICAAYJ7Q6KpAA3AQACAAYJ7Q6KpAA3AQAAAA==.Thebadmage:BAAALgAECgcJBAAAAA==.Throstmok:BAACLgAFFH8OAAIQAAQJUhCkIQDcAAAQAAQJUhCkIQDcAAAuAAQKfzcAAhAACQm3Hq8JAHgCABAACQm3Hq8JAHgCAAAA.Thràll:BAAALgAECgUJBQAAAA==.Thränton:BAAALgAECgEJAQABLgAECgcJFAAmALwhAA==.Thumbalina:BAAALgAECgYJEQAAAA==.',
To='Tongra:BAAALgADCgQJBAABLgAECgkJIAAGAFgPAA==.Totemtuggér:BAAALgADCgIJAgAAAA==.',
Tp='Tpaste:BAAALgADCgcJBwAAAA==.',
Tr='Trampstãmp:BAAALgAECgIJAgAAAA==.Trinitea:BAAALgAECgEJAgAAAA==.Trout:BAAALgADCgYJDAABLgAECgYJCgAcAAAAAA==.Trovikk:BAAALgADCgUJBgAAAA==.',
Tu='Turg:BAAALgAECgMJAwABLgAECgQJBwAcAAAAAA==.Turgo:BAAALgAECgEJAQABLgAECgQJBwAcAAAAAA==.Turgress:BAAALgAECgQJBwAAAA==.',
['Tà']='Tàmber:BAAALgADCgYJBwAAAA==.',
Ul='Ulfast:BAACLgAFFH8GAAIiAAMJ5xGwEQCNAAAiAAMJ5xGwEQCNAAAuAAQKfyUAAiIACAlKHrcaAAsCACIACAlKHrcaAAsCAAAA.',
Va='Valarios:BAAALgAECgYJCgAAAA==.Vannhellsing:BAABLgAECn8nAAIFAAgJJggwnwAtAQAFAAgJJggwnwAtAQAAAA==.Vanyel:BAABLgAECn9XAAIGAAkJMBklBQCGAQAGAAkJMBklBQCGAQAAAA==.Vaudorka:BAABLgAECn8cAAIEAAkJIx5RAwBnAgAEAAkJIx5RAwBnAgAAAA==.',
Ve='Vecna:BAAALgADCgMJAwABLgAECgYJCAAcAAAAAA==.Veliuz:BAAALgADCgQJBAAAAA==.Velrynth:BAABLgAECn84AAMdAAkJ+BSAEwBFAgAdAAkJVxSAEwBFAgANAAcJzghySAAXAQAAAA==.Vemal:BAABLgAECn8yAAILAAkJThk9GwCCAgALAAkJThk9GwCCAgAAAA==.',
Vo='Vociferoy:BAACLgAFFH8QAAILAAMJWhoIFwDpAAALAAMJWhoIFwDpAAAuAAQKf0QAAgsACQl9IUQPANYCAAsACQl9IUQPANYCAAAA.Voidsteffan:BAABLgAECn89AAMeAAkJ3xpEAABLAgAeAAkJ3xpEAABLAgAgAAQJjw4iwQDXAAAAAA==.',
Vr='Vryadox:BAAALgAFFAIJAgABLgAFFAQJDwAgAGwdAA==.',
Vv='Vv:BAACLgAFFH9QAAIbAAkJfSYLAAB/AwAbAAkJfSYLAAB/AwAuAAQKfzUAAhsACQm1JucAANoDABsACQm1JucAANoDAAAA.',
Vz='Vz:BAAALgADCgUJBQAAAA==.',
Wh='Whoppin:BAAALgAECgIJAgAAAA==.',
Wi='Wiglimparms:BAAALgAECgIJAgAAAA==.',
Wr='Wry:BAAALgAECgMJAwAAAA==.',
Wy='Wysselbow:BAAALgADCggJDQAAAA==.',
['Wá']='Wárranpeace:BAAALgADCgMJAwAAAA==.',
Xa='Xalmo:BAAALgAECgEJAQABLgAECgkJHwAEAJkUAA==.Xalzi:BAAALgADCggJCQABLgAECgcJFAAOAHwVAA==.',
Xi='Xingwong:BAABLgAECn88AAIfAAkJFSbXAQBNAwAfAAkJFSbXAQBNAwAAAA==.',
Za='Zannytoes:BAABLgAECn8mAAMVAAkJpRA9MAC6AQAVAAkJpRA9MAC6AQAMAAEJLxFSnwAwAAAAAA==.',
Ze='Zead:BAAALgAECgEJBQAAAA==.Zerana:BAACLgAFFH8NAAIeAAQJmAT+CgDrAAAeAAQJmAT+CgDrAAAuAAQKfxUAAh4ACQnlC1wOAFcBAB4ACQnlC1wOAFcBAAAA.Zeriea:BAAALgADCgEJAQAAAA==.Zevtra:BAAALgADCgEJAQAAAA==.',
Zi='Zie:BAABLgAECn9ZAAIBAAkJiBuEAQC2AQABAAkJiBuEAQC2AQAAAA==.Zikren:BAAALgAECgkJCQAAAA==.',
Zo='Zoumbadouwow:BAAALgAECgEJAQABLgAECgkJOwAdAJQfAA==.',
Zs='Zsinj:BAAALgADCgEJAQAAAA==.',
['Ðo']='Ðonkle:BAABLgAECn8TAAIbAAgJmByzKwAZAgAbAAgJmByzKwAZAgAAAA==.',
['Ðr']='Ðrewid:BAAALgADCgEJAQAAAA==.',
['Ñi']='Ñice:BAACLgAFFH8ZAAIRAAYJniOoBwDqAQARAAYJniOoBwDqAQAuAAQKfxoAAhEACQkrHugYACcCABEACQkrHugYACcCAAAA.',
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
