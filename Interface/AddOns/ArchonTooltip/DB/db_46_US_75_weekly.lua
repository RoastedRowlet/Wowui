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

local lookup = {'Hunter-Marksmanship','Druid-Feral','Druid-Balance','Unknown-Unknown','Shaman-Elemental','Evoker-Augmentation','Monk-Mistweaver','Priest-Discipline','Mage-Frost','DemonHunter-Devourer','DemonHunter-Havoc','Shaman-Enhancement','Hunter-BeastMastery','Druid-Restoration','Druid-Guardian','Paladin-Retribution','Warlock-Demonology','DeathKnight-Blood','Priest-Shadow','Paladin-Protection','Rogue-Subtlety','Rogue-Assassination','Warrior-Protection','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Destruction','Mage-Arcane','Monk-Windwalker','Warrior-Fury','Warrior-Arms','Evoker-Preservation','Priest-Holy','Warlock-Affliction','Shaman-Restoration','Evoker-Devastation','Hunter-Survival','Monk-Brewmaster','DemonHunter-Vengeance',}
local provider = {region='US',realm="Drak'thul",name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aalluntic:BAAALgAECgYJBgAAAA==.',
Ad='Ador:BAAALgAECgUJBQAAAA==.',
Ae='Aeladrel:BAAALgADCggJCAAAAA==.',
Ak='Akirie:BAABLgAECn8aAAIBAAYJDxdhEwAcAQABAAYJDxdhEwAcAQAAAA==.Akumu:BAABLgAECn8eAAMCAAkJrRtVBQC5AgACAAkJrRtVBQC5AgADAAEJAABjpgAAAAABLgAFFAMJAwAEAAAAAA==.Akumua:BAAALgAECgQJBAABLgAFFAMJAwAEAAAAAA==.',
Al='Alangi:BAABLgAECn8ZAAIFAAcJjgy3SAABAQAFAAcJjgy3SAABAQABLgAFFAUJCQAGAGAKAA==.Albinah:BAABLgAECn8dAAIHAAcJAB35HAAdAgAHAAcJAB35HAAdAgAAAA==.Albsli:BAAALgADCgIJAgAAAA==.Albsygos:BAAALgADCgQJBAAAAA==.Albz:BAAALgADCgkJHAAAAA==.Albzap:BAAALgADCgMJAwAAAA==.Albzley:BAABLgAECn8bAAIIAAgJhRhsEgBEAgAIAAgJhRhsEgBEAgAAAA==.Albzu:BAAALgAECgUJBQAAAA==.Aldien:BAABLgAECn8YAAIJAAYJ4Abh1ADkAAAJAAYJ4Abh1ADkAAAAAA==.Aliphar:BAAALgADCgEJAQAAAA==.Allaria:BAAALgADCgIJAgAAAA==.',
Ao='Aoe:BAACLgAFFH8TAAIKAAQJmxJGPwAZAQAKAAQJmxJGPwAZAQAuAAQKfyMAAgoACQlAHjIPAMACAAoACQlAHjIPAMACAAEuAAUUBgkNAAsAjhMA.',
Ar='Arcanism:BAAALgAECgQJBQAAAA==.Arienna:BAAALgAECgMJAwAAAA==.Arteñ:BAAALgAECgUJCQAAAA==.',
As='Ashrak:BAABLgAECn8jAAIMAAcJARNMEwB0AQAMAAcJARNMEwB0AQAAAA==.',
Av='Averroes:BAABLgAECn9DAAINAAkJGhpMGwB2AgANAAkJGhpMGwB2AgAAAA==.',
Aw='Awee:BAACLgAFFH8NAAILAAYJjhNECABnAQALAAYJjhNECABnAQAuAAQKf0sAAgsACQkwJCQDAB0DAAsACQkwJCQDAB0DAAAA.Awi:BAAALgADCgUJBQABLgAFFAYJDQALAI4TAA==.Awo:BAACLgAFFH8LAAMOAAQJMx6LGQB/AQAOAAQJMx6LGQB/AQAPAAEJxwP5OwAiAAAuAAQKfzgABA4ACAlmJb0FAFUDAA4ACAlmJb0FAFUDAA8ACAklH2YIAFkCAAIABgmIFkIUAG4BAAAA.Awoo:BAAALgAECgYJBwABLgAFFAQJCwAOADMeAA==.',
Ay='Aylen:BAABLgAECn8eAAIQAAkJ6A46agCPAQAQAAkJ6A46agCPAQAAAA==.',
Ba='Babsvilla:BAAALgAECgYJEQAAAA==.Badmagi:BAAALgAECgEJAQAAAA==.Bahldrahg:BAAALgAECgMJAwAAAA==.Baki:BAACLgAFFH8QAAIGAAUJoBkgJAAqAQAGAAUJoBkgJAAqAQAuAAQKfxsAAgYACQn+JH4CAFEDAAYACQn+JH4CAFEDAAAA.Banegrim:BAABLgAECn84AAIRAAgJPw+tXwB9AQARAAgJPw+tXwB9AQAAAA==.Barnbirt:BAAALgAECgEJAQAAAA==.Barron:BAAALgAECgIJAgAAAA==.Barronthee:BAAALgAECgIJAgAAAA==.Battlecat:BAABLgAECn8aAAIJAAgJjhKcaACkAQAJAAgJjhKcaACkAQAAAA==.',
Be='Beelzebubx:BAAALgAECgQJBAABLgAFFAMJAwAEAAAAAA==.Belysiuh:BAAALgAECgMJAwAAAA==.',
Bl='Blackdaisydr:BAAALgADCgcJDQABLgAECgYJCwAEAAAAAA==.Blindwalker:BAABLgAECn8hAAISAAkJeQ2pJgATAQASAAkJeQ2pJgATAQAAAA==.Blissfuleigh:BAAALgAECgIJAwAAAA==.Bloodbarron:BAAALgAECgYJCgAAAA==.',
Bo='Boldius:BAAALgADCgQJBAABLgAECgUJBQAEAAAAAA==.Bookchin:BAAALgADCgEJAQAAAA==.',
Br='Bragdand:BAEALgAECgQJAQAAAA==.Braistlin:BAAALgADCgIJAgABLgAECgUJBQAEAAAAAA==.Bred:BAAALgADCgcJBwAAAA==.Brewfest:BAAALgADCgMJBgAAAA==.Briarthorn:BAAALgAECgYJBgAAAA==.',
Bu='Bubblegump:BAAALgAECgIJAgAAAA==.Bulin:BAAALgADCgQJBAAAAA==.',
Ca='Cadillacbob:BAAALgAECgIJAwAAAA==.Calon:BAAALgAECgQJBQAAAA==.Cantseedizz:BAAALgADCgMJAwAAAA==.Castigate:BAACLgAFFH8eAAITAAYJJiJ9BgDxAQATAAYJJiJ9BgDxAQAuAAQKfy0AAhMACQmHIhQIAMkCABMACQmHIhQIAMkCAAAA.',
Ce='Cederek:BAAALgADCgIJAgAAAA==.Ceresarian:BAAALgADCgMJAwAAAA==.',
Ch='Chancho:BAAALgAECgYJCgABLgAECgkJNwAPAA4RAA==.Cheesekitten:BAAALgADCgEJAQABLgAFFAIJBgAQAJolAA==.Cheesemonk:BAAALgAECgkJEQABLgAFFAIJBgAQAJolAA==.Cheesepally:BAACLgAFFH8GAAIQAAIJmiW3XwDbAAAQAAIJmiW3XwDbAAAuAAQKf0EAAhAACQnCJj8BAIMDABAACQnCJj8BAIMDAAAA.Cheesewhelp:BAAALgADCgcJBwAAAA==.Chikoung:BAAALgADCgUJBQAAAA==.Chudmourne:BAAALgAECgUJBQAAAA==.',
Cl='Cloud:BAABLgAECn8oAAMUAAkJbCN7AQAsAwAUAAkJbCN7AQAsAwAQAAIJfhUIJwF4AAAAAA==.',
Co='Coderictond:BAAALgADCgQJBgAAAA==.Cogpally:BAAALgADCggJCAAAAA==.',
Cr='Crysa:BAAALgADCgYJBgAAAA==.',
Cy='Cygnus:BAABLgAECn8xAAMVAAgJkRTtFwDOAQAVAAgJkRTtFwDOAQAWAAUJfwYmFADZAAAAAA==.Cylla:BAABLgAECn8fAAINAAcJGiRWGwB1AgANAAcJGiRWGwB1AgABLgAFFAUJGgAUAOseAA==.',
Da='Daddywarbuks:BAAALgAECgUJBgAAAA==.Dagin:BAABLgAECn8uAAIQAAkJ1ByEHwCAAgAQAAkJ1ByEHwCAAgAAAA==.Dalarenaric:BAAALgADCgcJDAAAAA==.Dalt:BAAALgAFFAEJAQAAAA==.Daltonator:BAAALgADCgMJAwAAAA==.Dantemore:BAABLgAECn8aAAICAAcJlxfuEACXAQACAAcJlxfuEACXAQAAAA==.Daorcy:BAAALgADCggJDgAAAA==.Dartherd:BAABLgAECn80AAIXAAgJDhlGDwDmAQAXAAgJDhlGDwDmAQAAAA==.Dawnotheholy:BAABLgAECn9BAAMYAAkJuQ3LKwCoAQAYAAkJuQ3LKwCoAQAQAAcJJBDmqgAbAQAAAA==.',
De='Deathstar:BAACLgAFFH8rAAQZAAcJ7x1uDwA4AgAZAAYJ7x1uDwA4AgAaAAQJZxjoCABFAQASAAEJAACHRwAAAAAuAAQKfy8AAxkACQkSJO8LAAcDABkACQkSJO8LAAcDABoAAwl+DQISAHEAAAAA.Demonbunz:BAAALgADCgUJBwAAAA==.Derregar:BAABLgAECn8cAAMRAAcJFx5YTwCoAQARAAcJpx1YTwCoAQAbAAIJ0RL1SACTAAAAAA==.Dezamius:BAAALgAECgcJBwABLgAFFAUJCQAGAGAKAA==.',
Di='Dibella:BAAALgADCgYJAwAAAA==.Dirtydrago:BAAALgADCgUJBgABLgAECgUJBQAEAAAAAA==.Dirtymon:BAAALgADCgMJAwABLgAECgUJBQAEAAAAAA==.',
Dk='Dkfatality:BAACLgAFFH8NAAMaAAMJsR9gEADwAAAaAAMJsR9gEADwAAAZAAEJow5XVABPAAAuAAQKfy8AAxoACQmSI5sBABADABoACQmSI5sBABADABkABgl/IQ5dANsBAAAA.',
Dl='Dlord:BAAALgADCgYJCAAAAA==.',
Do='Dock:BAAALgAECgQJCQAAAA==.Dominbros:BAAALgAECgQJBAABLgAECgYJFwAJAJYWAA==.Dominhoes:BAABLgAECn8XAAIJAAYJlhYykQBQAQAJAAYJlhYykQBQAQAAAA==.Dondon:BAAALgAECgQJBAAAAA==.Doontless:BAAALgAECgYJEQAAAA==.Doyouknow:BAAALgAECgMJAwAAAA==.',
Dr='Draig:BAABLgAECn8UAAMJAAcJuAkBtQAVAQAJAAcJuggBtQAVAQAcAAIJWwe+GQBKAAAAAA==.Dratini:BAAALgADCggJBwABLgAECggJFwAdAEgZAA==.Drozigg:BAAALgADCgYJCQAAAA==.',
Du='Duckfury:BAABLgAECn8gAAIeAAgJ8RAmLACcAQAeAAgJ8RAmLACcAQAAAA==.Duckmourne:BAAALgAECggJCQABLgAECggJIAAeAPEQAA==.Dummy:BAAALgADCgYJBgAAAA==.Dunzoboom:BAAALgADCgcJCwAAAA==.Dunzö:BAAALgADCgYJBgAAAA==.',
['Dë']='Dëad:BAAALgAECgQJBgAAAA==.',
Eb='Ebonhèart:BAABLgAECn8ZAAMfAAgJygsfJQA0AQAfAAgJygsfJQA0AQAeAAEJwwUBqgA0AAAAAA==.',
Ec='Echoez:BAAALgAECgYJDgABLgAFFAQJEgAKAMYNAA==.Ecliptic:BAAALgAECgQJDQAAAA==.',
Eg='Eggle:BAAALgADCgIJAgAAAA==.',
Ei='Eisenheim:BAAALgADCgIJAgAAAA==.',
El='Electronvolt:BAABLgAECn8ZAAIgAAgJrBW5DAAAAgAgAAgJrBW5DAAAAgAAAA==.Eleidie:BAAALgADCgEJAQAAAA==.Elia:BAAALgAECgEJAQAAAA==.',
Ev='Evilyne:BAAALgADCgUJBwAAAA==.',
Ex='Exíled:BAAALgAECgEJAQAAAA==.',
Fa='Falilesta:BAAALgAECgEJAQAAAA==.Fallenlegion:BAAALgADCgcJBwAAAA==.Fartwizard:BAAALgAECgMJBQAAAA==.',
Fe='Felskerri:BAAALgADCgYJBgAAAA==.Fenus:BAAALgADCgIJAgAAAA==.',
Fi='Firebelly:BAAALgAECgMJAwAAAA==.Firerage:BAAALgADCgcJDwABLgAECgIJBAAEAAAAAA==.',
Fl='Flacidmonkey:BAAALgAECgcJDwAAAA==.Flufflenuzs:BAAALgAECgEJAQAAAA==.',
Fo='Fors:BAAALgAECgQJBAAAAA==.Forsäken:BAABLgAECn8VAAIJAAYJoRW0pwCKAQAJAAYJoRW0pwCKAQAAAA==.Forumangel:BAAALgADCgYJCQAAAA==.',
Fr='Freya:BAAALgADCgUJBQAAAA==.Fria:BAAALgAECgcJCAAAAA==.Frombehind:BAAALgAECgcJEgABLgAFFAcJIAAZANQbAA==.',
Fu='Fubu:BAAALgAECgIJAgAAAA==.',
Ga='Gabenson:BAAALgADCgQJBAAAAA==.',
Gl='Glizzylatte:BAAALgADCgYJBgABLgAECgYJCwAEAAAAAA==.Gloomy:BAABLgAECn8yAAIhAAgJcSBECgC1AgAhAAgJcSBECgC1AgAAAA==.',
Gr='Grandizzle:BAABLgAECn8UAAIKAAgJVA/XWQBuAQAKAAgJVA/XWQBuAQAAAA==.Grandore:BAAALgAECgEJAwAAAA==.',
Gu='Gumbi:BAAALgAECgIJAgAAAA==.Gumgum:BAACLgAFFH8VAAMiAAQJliVgAQCrAQAiAAQJliVgAQCrAQAbAAEJ4CGgFgBnAAAuAAQKfzYAAiIACAlYJg0BAP8CACIACAlYJg0BAP8CAAAA.Guruprime:BAAALgADCgYJCAAAAA==.',
Gw='Gwalla:BAAALgADCgkJFwABLgAECgMJBQAEAAAAAA==.',
Ha='Hagniy:BAABLgAECn9aAAIYAAkJ8x6WCAD3AgAYAAkJ8x6WCAD3AgAAAA==.Hakunamatata:BAAALgADCgUJBQAAAA==.Halten:BAAALgAECgkJBwAAAA==.Happyboy:BAABLgAECn8fAAQOAAYJjh8XJgAUAgAOAAYJjh8XJgAUAgAPAAYJ+Bt6FgCMAQACAAEJ0BxVPgBSAAABLgAFFAQJCwAOADMeAA==.Hardrockcafe:BAAALgADCgYJAwAAAA==.Harfu:BAAALgAECgIJAgAAAA==.Hartzdrell:BAAALgADCgcJDAAAAA==.Hashirama:BAAALgAFFAIJBAABLgAFFAUJEAAGAKAZAA==.',
He='Healmedaddy:BAAALgADCgEJAQAAAA==.Helbrandt:BAAALgAECgMJAwAAAA==.Heldarram:BAAALgAECgkJEQAAAA==.Hemaroid:BAAALgADCgcJBwAAAA==.Heolt:BAEALgADCgUJBQABLgAECgQJAQAEAAAAAA==.Hestia:BAAALgAECgUJBgAAAA==.Hexra:BAACLgAFFH8SAAIgAAUJyB/2CwDJAQAgAAUJyB/2CwDJAQAuAAQKfx4AAiAACQnIISQFAPoCACAACQnIISQFAPoCAAAA.Heyzus:BAAALgAECgYJCQAAAA==.',
Ho='Honnok:BAAALgAECgQJBAAAAA==.Hoofweaver:BAAALgAECgUJBQAAAA==.Hornyhead:BAAALgAECgQJDQAAAA==.Howard:BAAALgADCgIJAgAAAA==.',
Hr='Hrizul:BAABLgAECn8zAAMUAAkJ5R0JBQCZAgAUAAgJGiEJBQCZAgAQAAcJ3Q51lAA/AQAAAA==.',
Ib='Iblameheals:BAAALgADCgMJBAAAAA==.',
Ic='Icebarron:BAAALgAECgYJDQAAAA==.',
Il='Il:BAABLgAECn8iAAIRAAkJtx4tIACXAgARAAkJtx4tIACXAgAAAA==.Illisharr:BAAALgADCggJEQAAAA==.Iloveleaf:BAAALgADCgEJAQAAAA==.Ilusive:BAABLgAECn8cAAIFAAgJrhECNABdAQAFAAgJrhECNABdAQAAAA==.',
Ir='Irazlynaa:BAAALgADCgUJDgAAAA==.Irielyn:BAAALgAECgUJBQAAAA==.Ironblight:BAAALgAECgEJAQAAAA==.Irrah:BAAALgAECgYJDwAAAA==.',
Is='Ishal:BAAALgADCgEJAQAAAA==.',
Ja='Jabar:BAAALgADCgEJAQAAAA==.Jagz:BAABLgAECn87AAMjAAkJ7B3qFgBeAgAjAAgJBR3qFgBeAgAFAAgJ4h1bFgAmAgAAAA==.',
Jh='Jharael:BAAALgADCgUJBwAAAA==.',
Ji='Jia:BAAALgAECgEJAgAAAA==.',
Jo='Jonsi:BAAALgADCgUJBQABLgAECggJFwAdAEgZAA==.',
Ju='Junö:BAAALgAECgEJAQAAAA==.Jursh:BAAALgADCgQJBAAAAA==.',
Ka='Kaelen:BAAALgAECgcJEgAAAA==.Kaley:BAAALgADCgIJAgAAAA==.Kasuo:BAAALgAECgEJAQAAAA==.Katamine:BAABLgAECn87AAIDAAgJiB05EQBEAgADAAgJiB05EQBEAgAAAA==.Katoz:BAABLgAECn8aAAMZAAgJHx7ANgAcAgAZAAgJHx7ANgAcAgAaAAIJTRYvEgBuAAAAAA==.Kawas:BAAALgAECgYJCQAAAA==.',
Ke='Keydron:BAAALgADCggJDwAAAA==.',
Kh='Khài:BAAALgAECgQJBQAAAA==.',
Ki='Kickit:BAAALgADCgQJBAAAAA==.Kilemall:BAAALgAECgkJAgAAAA==.Killnall:BAABLgAECn8pAAIQAAYJBAjM2gDXAAAQAAYJBAjM2gDXAAAAAA==.Kiyohime:BAAALgAECgIJAgAAAA==.',
Kj='Kjadmina:BAAALgADCgUJBAAAAA==.',
Kl='Kladon:BAABLgAECn8gAAIBAAkJJxrKCADiAQABAAkJJxrKCADiAQAAAA==.Klozkoth:BAAALgAECgYJBgAAAA==.',
Ko='Konantheduck:BAAALgADCgMJAwABLgAECggJIAAeAPEQAA==.',
Kr='Krystarin:BAABLgAECn8wAAIOAAgJ/hdnIQAzAgAOAAgJ/hdnIQAzAgAAAA==.Kryx:BAAALgADCgkJEAAAAA==.Kráytos:BAAALgAECgYJCQAAAA==.',
Ky='Kynria:BAAALgAECgIJAwAAAA==.',
La='Lallaure:BAAALgADCgQJBAAAAA==.Lambic:BAAALgAECgQJBAAAAA==.Lanma:BAABLgAECn8XAAIdAAgJSBlBEQBvAgAdAAgJSBlBEQBvAgAAAA==.Larpgodx:BAAALgAECgIJAwAAAA==.Lastoran:BAAALgAECgMJBQAAAA==.Lateralus:BAABLgAECn9HAAIkAAkJWiENAQACAwAkAAkJWiENAQACAwAAAA==.Launcelot:BAABLgAECn8dAAMeAAcJSCKUHwBUAgAeAAYJ+yKUHwBUAgAfAAQJRB9pIwA9AQAAAA==.Laurasecord:BAAALgADCgQJBAAAAA==.Lazymage:BAAALgAECgcJDAAAAA==.',
Le='Leanbeef:BAAALgAECgYJBgAAAA==.Lerath:BAAALgAECggJDQAAAA==.Leshy:BAAALgADCgYJBgAAAA==.',
Li='Lights:BAACLgAFFH8LAAITAAMJ1CEkHQD0AAATAAMJ1CEkHQD0AAAuAAQKfz8AAxMACQnuJQACAFMDABMACQnuJQACAFMDAAgABQmTIGgdANQBAAEuAAUUBQkQAAYAoBkA.Littlezo:BAACLgAFFH8SAAIlAAUJvBjnDgA/AQAlAAUJvBjnDgA/AQAuAAQKfy0AAiUACQl0JUYBAFADACUACQl0JUYBAFADAAAA.',
Lo='Lockßulbtwo:BAAALgAECgEJAgAAAA==.Lotus:BAABLgAECn8tAAQdAAkJfxb6FQD7AQAdAAkJNBb6FQD7AQAmAAUJHhWPLwA+AQAHAAYJ5wz3OAAFAQAAAA==.',
Lt='Ltrnck:BAAALgADCgIJAgAAAA==.',
Lu='Lu:BAAALgADCgEJAQAAAA==.Luckbound:BAAALgAECgEJAQABLgAFFAQJCwAOADMeAA==.Luthonys:BAAALgADCgEJAQAAAA==.',
Ma='Magond:BAAALgAECgIJAgAAAA==.Maiko:BAAALgADCgMJAwAAAA==.Makoha:BAABLgAECn83AAMPAAkJDhFpFwCDAQAPAAkJDhFpFwCDAQACAAEJwA6STAAwAAAAAA==.Makpriest:BAAALgAECgYJDgAAAA==.Malakaii:BAABLgAECn8cAAMMAAgJexEYDAAEAgAMAAgJQREYDAAEAgAFAAYJrhLKQgA+AQAAAA==.Margaes:BAAALgADCgEJAgAAAA==.Mariahh:BAAALgADCgEJAQAAAA==.Masherevo:BAAALgAECgMJAwABLgAFFAQJCwAFAMMRAA==.Masherkillu:BAACLgAFFH8LAAIFAAQJwxGwHwATAQAFAAQJwxGwHwATAQAuAAQKfycAAgUACQkkGKIUADcCAAUACQkkGKIUADcCAAAA.Masherpally:BAACLgAFFH8HAAMQAAMJ3wbfcAC8AAAQAAMJ3wbfcAC8AAAUAAEJPgXfFwAvAAAuAAQKfyQAAxAACQkNGyobAJcCABAACQkNGyobAJcCABQAAwktDt07AGEAAAEuAAUUBAkLAAUAwxEA.Maxdeath:BAABLgAECn8bAAIJAAkJpQ5OgADQAQAJAAkJpQ5OgADQAQAAAA==.Maztajake:BAABLgAECn8VAAIDAAcJ1h1TGwDiAQADAAcJ1h1TGwDiAQAAAA==.Mazyjake:BAAALgAECgcJCQABLgAECgcJFQADANYdAA==.Mazzyjake:BAAALgAECgUJBQABLgAECgcJFQADANYdAA==.',
Me='Medorh:BAAALgADCgYJBgAAAA==.Melchizedic:BAAALgAECgQJCwAAAA==.Merily:BAAALgADCgQJBAAAAA==.',
Mi='Mikeytott:BAAALgADCgQJBQAAAA==.Minnie:BAAALgAECgEJAQABLgAECgkJIQAGAPUZAA==.',
Mo='Mohgmoment:BAAALgADCgYJBgAAAA==.Moonfare:BAAALgADCgEJAgAAAA==.Mordacity:BAEBLgAECn80AAInAAgJ3gc4FAAAAQAnAAgJ3gc4FAAAAQAAAA==.',
Mu='Muris:BAAALgAECgQJBAAAAA==.',
['Mä']='Määt:BAAALgADCgIJAgAAAA==.',
Na='Nardo:BAAALgAECgEJAQAAAA==.',
Ne='Necromaine:BAAALgAECgQJDQAAAA==.Necrot:BAAALgAECgEJAQAAAA==.',
Ng='Nghtíy:BAABLgAECn8aAAIZAAYJQBO0sQAIAQAZAAYJQBO0sQAIAQAAAA==.',
Ni='Nixa:BAAALgADCgUJBQAAAA==.',
No='Nocturnüs:BAABLgAECn8vAAITAAkJuhI2GAD+AQATAAkJuhI2GAD+AQAAAA==.Noh:BAAALgAECgIJAgAAAA==.Nordikmage:BAABLgAECn8aAAMJAAcJhxE1iABgAQAJAAcJhxE1iABgAQAcAAEJPwVSIAAuAAAAAA==.Nort:BAAALgADCgEJAgAAAA==.Nov:BAAALgADCgMJAwAAAA==.',
['Nê']='Nêcrömane:BAAALgAECgUJCAAAAA==.',
['Në']='Nëssa:BAAALgAECgIJAgABLgAECgYJCgAEAAAAAA==.',
Oh='Ohtheirone:BAAALgADCgYJBgAAAA==.Ohtheironey:BAAALgADCgUJBQAAAA==.Ohtheironie:BAAALgADCgYJBgAAAA==.',
On='Ondereth:BAAALgAECgYJDgAAAA==.Onthehouse:BAAALgAECgYJDgAAAA==.',
Or='Orid:BAAALgADCgcJBwAAAA==.Orvannan:BAAALgADCgQJCAAAAA==.',
Pa='Pacho:BAAALgADCgUJBQAAAA==.Palimorea:BAEALgADCggJFwABLgAECgQJAQAEAAAAAA==.',
Pi='Piercey:BAACLgAFFH8PAAMXAAcJVxItBwCsAQAXAAcJVxItBwCsAQAfAAEJOhAeOABMAAAuAAQKfysAAxcACAntHr4KAGUCABcACAntHr4KAGUCAB8AAQn4H8lbAF0AAAEuAAUUBAkLAA4AMx4A.Pinkylove:BAABLgAECn8eAAIOAAgJ8iBODADcAgAOAAgJ8iBODADcAgAAAA==.',
Pr='Proera:BAAALgAECgcJCQAAAA==.Promathia:BAACLgAFFH8aAAQUAAUJ6x4uBgASAQAQAAUJCxwFNAA1AQAUAAMJ9iAuBgASAQAYAAQJ3AzeJADuAAAuAAQKf08ABBAACQnLJt0AAIwDABAACQnLJt0AAIwDABgABAkXCCVuAMIAABQAAQkDJVE6AGcAAAAA.Pross:BAAALgAECgQJCQABLgAECgkJLgAQANQcAA==.',
Ps='Psychopath:BAABLgAECn8aAAMVAAYJohYVLACeAQAVAAYJohYVLACeAQAWAAEJtwYkIAAyAAAAAA==.',
Pu='Puff:BAAALgAECggJDQAAAA==.',
Qu='Quicksotaka:BAAALgADCgcJBgAAAA==.',
Ra='Raenori:BAAALgADCgYJBgAAAA==.Ragnarolk:BAAALgAECgIJAgAAAA==.Raiyuden:BAAALgAECgEJAQAAAA==.Randydaytona:BAAALgAECgYJCwAAAA==.Rangërdangër:BAACLgAFFH8PAAINAAUJzgYUSwABAQANAAUJzgYUSwABAQAuAAQKfxgAAg0ACQmTGQo1ANoBAA0ACQmTGQo1ANoBAAAA.Rat:BAABLgAECn8jAAITAAkJSSBzBABOAwATAAkJSSBzBABOAwAAAA==.',
Re='Rectumus:BAAALgADCggJEwAAAA==.Redrouges:BAACLgAFFH8GAAIVAAIJTBtsKgC5AAAVAAIJTBtsKgC5AAAuAAQKfykAAhUACQkNIcoDAPwCABUACQkNIcoDAPwCAAAA.Redwood:BAAALgAECgMJBQAAAA==.Renvskadoosh:BAAALgADCgkJGQABLgAECgcJHgAjAF0JAA==.Revhero:BAAALgAECgEJAQAAAA==.Rexpanda:BAABLgAECn8YAAIHAAYJ1R2CGgDmAQAHAAYJ1R2CGgDmAQAAAA==.',
Ro='Roguetheholy:BAAALgAECgkJBQAAAA==.Ross:BAEALgADCgEJAQABLgAFFAYJEwAHAAsmAA==.Rotawnda:BAAALgAECgYJBwAAAA==.Rotlord:BAAALgAECgYJCgAAAA==.',
Ru='Ruckus:BAAALgAECgYJCwAAAA==.Rumble:BAAALgAECgEJAQAAAA==.Rumrootbeer:BAAALgADCgIJAQAAAA==.',
['Rë']='Rëkz:BAAALgAECgMJAwAAAA==.',
['Rì']='Rìppér:BAAALgAECgEJAQABLgAFFAUJEgAgAMgfAA==.',
Sa='Sanelle:BAAALgADCgkJCQABLgAECgkJKwAIABQgAA==.Sapoude:BAAALgAECgcJBwAAAA==.Sarang:BAAALgADCgcJBwAAAA==.Sarrsaras:BAAALgAECgYJCAABLgAECgcJFgARAGcbAA==.',
Se='Seaursus:BAAALgAECgMJCAAAAA==.Seerblade:BAAALgADCgcJCgABLgAECgYJCwAEAAAAAA==.Sekaiju:BAAALgAECgQJBgAAAA==.Selakin:BAAALgADCgIJAgAAAA==.',
Sh='Shadowbann:BAAALgAECgMJBQAAAA==.Shadowrunner:BAAALgAECgEJAQAAAA==.Shammydavis:BAAALgADCgEJAQAAAA==.Shamwich:BAAALgAECgkJEgAAAA==.Shandroz:BAAALgAECgUJBQAAAA==.Shaori:BAAALgADCgMJBAAAAA==.Shortzo:BAAALgAECgcJCwABLgAFFAUJEgAlALwYAA==.Shrkbait:BAAALgAECgUJCgAAAA==.',
Si='Sikozu:BAAALgAECgIJAgAAAA==.',
Sk='Skeezicks:BAAALgADCgUJBQAAAA==.Skidoosh:BAAALgAECgEJAwAAAA==.Skullcleaver:BAAALgADCgcJFAAAAA==.',
Sl='Slycc:BAAALgAECgMJAwAAAA==.',
Sm='Smackerr:BAAALgADCgUJBgAAAA==.',
Sn='Sneakay:BAABLgAFFH8GAAIbAAMJqQURDgC3AAAbAAMJqQURDgC3AAAAAA==.Sneakybiter:BAAALgADCgcJDQAAAA==.',
So='Solei:BAAALgAECgUJBQAAAA==.Southernguy:BAAALgAECgMJBAAAAA==.',
Sp='Spazzies:BAAALgAECgcJEAAAAA==.',
Sq='Squigglybutt:BAABLgAECn8qAAMhAAcJkR/rDQB6AgAhAAcJkR/rDQB6AgAIAAUJ3xbeLQBeAQAAAA==.',
St='Steelwing:BAAALgAFFAMJAwAAAA==.Stormbeards:BAAALgADCgYJBgAAAA==.Stoutkeg:BAAALgADCgQJAwAAAA==.Strixmonk:BAEALgAFFAIJAwABLgAFFAYJGgAZAC4eAA==.Strrawberry:BAAALgADCgIJAgAAAA==.Stêven:BAAALgAECggJCAAAAA==.Störmî:BAAALgAECgYJBwAAAA==.',
Su='Sungchaluka:BAAALgAECgQJCwAAAA==.',
['Sá']='Sásu:BAAALgADCgkJFQAAAA==.',
Ta='Talsomething:BAAALgAFFAEJAgAAAA==.Talsumthing:BAABLgAFFH8JAAIYAAUJqwRaIgAAAQAYAAUJqwRaIgAAAQAAAA==.Tars:BAAALgAECgYJBgAAAA==.Tats:BAABLgAECn8kAAIQAAgJMB2vMAAzAgAQAAgJMB2vMAAzAgAAAA==.Tatsumâ:BAAALgAECgYJDAAAAA==.',
Te='Terraxic:BAAALgAECgYJDAAAAA==.Terthaith:BAABLgAECn8YAAIRAAkJKwzhVwCQAQARAAkJKwzhVwCQAQAAAA==.Tezguin:BAAALgADCgYJDQAAAA==.',
Th='Theedemon:BAAALgAECgQJBAAAAA==.Theironie:BAAALgADCgYJBgAAAA==.Theparttimer:BAAALgADCgEJAQAAAA==.Thiccpie:BAAALgAECgYJCwAAAA==.Throdwran:BAAALgAECgYJDAABLgAECgkJLgAQANQcAA==.',
Ti='Timba:BAAALgAECgYJCAAAAA==.Tisaka:BAABLgAECn8aAAIVAAYJAxmZJQDMAQAVAAYJAxmZJQDMAQAAAA==.',
Tl='Tlovexx:BAAALgAFFAEJAQAAAA==.',
To='Toohbooh:BAAALgAECgMJBgAAAA==.Totem:BAAALgAECgcJDAAAAA==.',
Tr='Tranqx:BAACLgAFFH8TAAMaAAQJnyR+DAAeAQAaAAMJiCJ+DAAeAQAZAAMJGSS9agAbAQAuAAQKfzkAAxoACQnpJmsBAB0DABkACAm1JlUIAFwDABoACAmnJmsBAB0DAAAA.Treevlo:BAAALgADCgEJAQAAAA==.Treva:BAABLgAECn8hAAQGAAkJ9Rn0FAA3AgAGAAkJ9Rn0FAA3AgAkAAQJtAYrLgCoAAAgAAEJZQPfSgAsAAAAAA==.Trizz:BAAALgAFFAEJAQAAAA==.Troctzul:BAAALgADCgEJAwAAAA==.Trollmachine:BAAALgAECgcJDAABLgAECgcJFQADANYdAA==.',
Ts='Tsuchiya:BAAALgAECggJDgAAAA==.',
Tu='Tuts:BAAALgADCgYJDAAAAA==.',
Ty='Tythos:BAAALgADCgYJCwAAAA==.',
Up='Uproar:BAACLgAFFH8LAAIaAAUJOx0BBwBfAQAaAAUJOx0BBwBfAQAuAAQKfy4AAhoACQlDJUIBACgDABoACQlDJUIBACgDAAAA.',
Va='Vaelira:BAAALgADCgkJCQAAAA==.Vahlfi:BAACLgAFFH8EAAIKAAIJCRyOcACMAAAKAAIJCRyOcACMAAAuAAQKfxwABAoACQljJD4OAMkCAAoACQljJD4OAMkCAAsAAQm6IkpQAGIAACcAAgkTEeExADAAAAEuAAUUBQkUABYA7iUA.Valemon:BAAALgAFFAIJAwAAAA==.Valeskogr:BAABLgAECn8dAAQNAAkJAg5EWgCJAQANAAgJZw5EWgCJAQAlAAcJjQjeFAB6AQABAAgJmAN0UAAMAQAAAA==.Valffi:BAAALgAFFAEJAQABLgAFFAUJFAAWAO4lAA==.Varoth:BAAALgAECgEJAQAAAA==.Varus:BAAALgAECgYJCQAAAA==.',
Ve='Velisá:BAAALgAECgIJAgAAAA==.Vengefulmilk:BAAALgAECgUJDgAAAA==.Venture:BAAALgADCgkJIgAAAA==.Vergo:BAAALgADCgEJAQAAAA==.Vescovo:BAABLgAECn8rAAQIAAkJFCAMBgAZAwAIAAkJFCAMBgAZAwATAAUJ0RXwPwAIAQAhAAEJrh+jdABWAAAAAA==.',
Vi='Virde:BAAALgADCgMJAwAAAA==.',
Vl='Vll:BAABLgAECn8iAAILAAgJ7iLhBgC6AgALAAgJ7iLhBgC6AgABLgAECgkJJwANALUbAA==.',
Vo='Volkihar:BAAALgAFFAIJAwAAAA==.Vordt:BAAALgAECgIJBwAAAA==.',
Wa='Wardaorm:BAABLgAECn8fAAIeAAYJDg65SQAVAQAeAAYJDg65SQAVAQABLgAECgkJLgAQANQcAA==.Warkinz:BAAALgADCgQJBQAAAA==.Warlin:BAAALgAECgEJAQAAAA==.',
Wi='Willohh:BAAALgAECgQJBAAAAA==.Winden:BAABLgAECn8WAAIMAAYJhht2FgBKAQAMAAYJhht2FgBKAQAAAA==.Wingback:BAAALgAECgcJBQAAAA==.Wiz:BAAALgAECgYJDgAAAA==.',
Wp='Wphoenix:BAAALgAECgQJBAAAAA==.',
Wr='Wrizz:BAAALgADCgYJCAAAAA==.',
Wt='Wtfsteve:BAAALgADCgUJBQABLgAECggJFwAdAEgZAA==.',
Xa='Xadrai:BAAALgAECgYJCwAAAA==.',
Xe='Xeplin:BAAALgAECgUJCQAAAA==.',
Xh='Xhenshini:BAACLgAFFH8JAAMGAAUJYAqgNwDaAAAGAAUJYAqgNwDaAAAkAAEJtwbMCgBPAAAuAAQKf0IAAwYACQlOIaMFAP4CAAYACQkcIaMFAP4CACQACAmqGjEJAE4CAAAA.',
Xk='Xkrin:BAAALgAECgEJAQAAAA==.',
Ye='Yeonguo:BAAALgAECgYJDgAAAA==.',
Yu='Yums:BAAALgADCgcJCwAAAA==.',
Za='Zalethe:BAAALgAECgMJAwAAAA==.Zalliel:BAAALgADCggJCAAAAA==.Zalman:BAAALgAECgMJBQAAAA==.Zaphíel:BAAALgADCgcJBwABLgAECgkJGAARACsMAA==.Zaran:BAABLgAECn8UAAIQAAgJOhD3bQCHAQAQAAgJOhD3bQCHAQAAAA==.',
Ze='Zeninnaoya:BAABLgAECn8fAAMfAAkJuSD6AABaAwAfAAkJ3B36AABaAwAeAAcJISaFDgDgAgAAAA==.',
['Âu']='Âura:BAAALgADCgEJAQAAAA==.',
['Är']='Ärc:BAAALgADCgMJAwAAAA==.',
['Ës']='Ësme:BAAALgADCgkJCwAAAA==.',
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
