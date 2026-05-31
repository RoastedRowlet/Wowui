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

local lookup = {'Hunter-Marksmanship','Druid-Feral','Druid-Balance','Unknown-Unknown','Shaman-Elemental','Evoker-Augmentation','Monk-Mistweaver','Mage-Frost','DemonHunter-Devourer','DemonHunter-Havoc','Shaman-Enhancement','Hunter-BeastMastery','Druid-Restoration','Druid-Guardian','Paladin-Retribution','Warlock-Demonology','DeathKnight-Blood','Priest-Shadow','Paladin-Protection','Rogue-Subtlety','Rogue-Assassination','Warrior-Protection','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Destruction','Mage-Arcane','Monk-Windwalker','Warrior-Fury','Warrior-Arms','Evoker-Preservation','Priest-Holy','Warlock-Affliction','Shaman-Restoration','Evoker-Devastation','Priest-Discipline','Hunter-Survival','Monk-Brewmaster','DemonHunter-Vengeance',}
local provider = {region='US',realm="Drak'thul",name='US',type='weekly',zone=46,date='2026-05-30',data={Ad='Ador:BAAALgAECgUJBQAAAA==.',
Ae='Aeladrel:BAAALgADCggJCAAAAA==.',
Ak='Akirie:BAABLgAECn8aAAIBAAYJDxcxEgAjAQABAAYJDxcxEgAjAQAAAA==.Akumu:BAABLgAECn8eAAMCAAkJrRtVBQC5AgACAAkJrRtVBQC5AgADAAEJAADCnQAAAAABLgAFFAMJAwAEAAAAAA==.Akumua:BAAALgAECgQJBAABLgAFFAMJAwAEAAAAAA==.',
Al='Alangi:BAABLgAECn8ZAAIFAAcJjgwsRAAHAQAFAAcJjgwsRAAHAQABLgAFFAQJCAAGAGAKAA==.Albinah:BAABLgAECn8dAAIHAAcJAB2GGgAdAgAHAAcJAB2GGgAdAgAAAA==.Albsli:BAAALgADCgIJAgAAAA==.Albsygos:BAAALgADCgQJBAAAAA==.Albz:BAAALgADCgkJHAAAAA==.Albzap:BAAALgADCgMJAwAAAA==.Albzley:BAAALgAECggJEwAAAA==.Albzu:BAAALgAECgUJBQAAAA==.Aldien:BAABLgAECn8YAAIIAAYJ4AYr0wDNAAAIAAYJ4AYr0wDNAAAAAA==.Aliphar:BAAALgADCgEJAQAAAA==.Allaria:BAAALgADCgIJAgAAAA==.',
Ao='Aoe:BAACLgAFFH8SAAIJAAQJWxIOOAAhAQAJAAQJWxIOOAAhAQAuAAQKfyMAAgkACQlAHiMOAL8CAAkACQlAHiMOAL8CAAEuAAUUBgkLAAoASQ8A.',
Ar='Arcanism:BAAALgAECgEJAQAAAA==.Arienna:BAAALgAECgMJAwAAAA==.Arteñ:BAAALgAECgUJCQAAAA==.',
As='Ashrak:BAABLgAECn8jAAILAAcJARP4EQB1AQALAAcJARP4EQB1AQAAAA==.',
Av='Averroes:BAABLgAECn9DAAIMAAkJGhqQGAB8AgAMAAkJGhqQGAB8AgAAAA==.',
Aw='Awee:BAACLgAFFH8LAAIKAAYJSQ8ECgA7AQAKAAYJSQ8ECgA7AQAuAAQKf0oAAgoACQm1I9sCABgDAAoACQm1I9sCABgDAAAA.Awi:BAAALgADCgUJBQABLgAFFAYJCwAKAEkPAA==.Awo:BAACLgAFFH8IAAMNAAQJfRgmHQBQAQANAAQJfRgmHQBQAQAOAAEJxwM2MwAoAAAuAAQKfzYABA0ACAlmJUgFAFcDAA0ACAlmJUgFAFcDAA4ACAkxHlYIAEwCAAIABgmIFkIUAG4BAAAA.Awoo:BAAALgAECgYJBwABLgAFFAQJCAANAH0YAA==.',
Ay='Aylen:BAABLgAECn8eAAIPAAkJ6A6gZgCIAQAPAAkJ6A6gZgCIAQAAAA==.',
Ba='Babsvilla:BAAALgAECgUJDgAAAA==.Badmagi:BAAALgAECgEJAQAAAA==.Bahldrahg:BAAALgAECgMJAwAAAA==.Baki:BAACLgAFFH8PAAIGAAQJoBkTHwAyAQAGAAQJoBkTHwAyAQAuAAQKfxsAAgYACQn+JDoCAEoDAAYACQn+JDoCAEoDAAAA.Banegrim:BAABLgAECn8xAAIQAAgJAw6eZABqAQAQAAgJAw6eZABqAQAAAA==.Barnbirt:BAAALgAECgEJAQAAAA==.Barron:BAAALgAECgIJAgAAAA==.Barronthee:BAAALgAECgIJAgAAAA==.Battlecat:BAABLgAECn8aAAIIAAgJjhK2YgCgAQAIAAgJjhK2YgCgAQAAAA==.',
Be='Beelzebubx:BAAALgAECgQJBAABLgAFFAMJAwAEAAAAAA==.Belysiuh:BAAALgAECgMJAwAAAA==.',
Bl='Blackdaisydr:BAAALgADCgcJDQABLgAECgYJCwAEAAAAAA==.Blindwalker:BAABLgAECn8hAAIRAAkJeQ2TJAAUAQARAAkJeQ2TJAAUAQAAAA==.Blissfuleigh:BAAALgAECgIJAwAAAA==.Bloodbarron:BAAALgAECgYJCgAAAA==.',
Bo='Boldius:BAAALgADCgQJBAABLgAECgUJBQAEAAAAAA==.Bookchin:BAAALgADCgEJAQAAAA==.',
Br='Bragdand:BAEALgAECgQJAQAAAA==.Braistlin:BAAALgADCgIJAgABLgAECgUJBQAEAAAAAA==.Bred:BAAALgADCgcJBwAAAA==.Brewfest:BAAALgADCgMJBgAAAA==.Briarthorn:BAAALgAECgYJBgAAAA==.',
Bu='Bubblegump:BAAALgAECgIJAgAAAA==.Bulin:BAAALgADCgQJBAAAAA==.',
Ca='Cadillacbob:BAAALgAECgIJAwAAAA==.Calon:BAAALgAECgQJBQAAAA==.Cantseedizz:BAAALgADCgMJAwAAAA==.Castigate:BAACLgAFFH8dAAISAAYJSyH0BQDgAQASAAYJSyH0BQDgAQAuAAQKfy0AAhIACQmHIi8HAMUCABIACQmHIi8HAMUCAAAA.',
Ce='Cederek:BAAALgADCgIJAgAAAA==.Ceresarian:BAAALgADCgMJAwAAAA==.',
Ch='Chancho:BAAALgAECgYJCgABLgAECgkJNwAOAA4RAA==.Cheesekitten:BAAALgADCgEJAQABLgAECgkJQQAPAMImAA==.Cheesemonk:BAAALgAECgkJCQABLgAECgkJQQAPAMImAA==.Cheesepally:BAABLgAECn9BAAIPAAkJwib1AACCAwAPAAkJwib1AACCAwAAAA==.Cheesewhelp:BAAALgADCgcJBwAAAA==.Chikoung:BAAALgADCgUJBQAAAA==.Chudmourne:BAAALgAECgUJBQAAAA==.',
Cl='Cloud:BAABLgAECn8lAAMTAAkJLCN2AQAoAwATAAkJLCN2AQAoAwAPAAIJfhUsFgF6AAAAAA==.',
Co='Coderictond:BAAALgADCgQJBgAAAA==.Cogpally:BAAALgADCggJCAAAAA==.',
Cr='Crysa:BAAALgADCgYJBgAAAA==.',
Cy='Cygnus:BAABLgAECn8uAAMUAAgJnBMaGADBAQAUAAgJnBMaGADBAQAVAAUJfwY2EwDeAAAAAA==.Cylla:BAABLgAECn8fAAIMAAcJGiTgGAB6AgAMAAcJGiTgGAB6AgABLgAFFAQJFQATAOseAA==.',
Da='Daddywarbuks:BAAALgAECgUJBgAAAA==.Dagin:BAABLgAECn8tAAIPAAkJ1ByDHACCAgAPAAkJ1ByDHACCAgAAAA==.Dalarenaric:BAAALgADCgcJDAAAAA==.Dalt:BAAALgAFFAEJAQAAAA==.Daltonator:BAAALgADCgMJAwAAAA==.Dantemore:BAABLgAECn8aAAICAAcJlxeeDwCZAQACAAcJlxeeDwCZAQAAAA==.Daorcy:BAAALgADCggJDgAAAA==.Dartherd:BAABLgAECn8sAAIWAAgJXRgpEADNAQAWAAgJXRgpEADNAQAAAA==.Dawnotheholy:BAABLgAECn9BAAMXAAkJuQ2iKQCrAQAXAAkJuQ2iKQCrAQAPAAcJJBCopQATAQAAAA==.',
De='Deathstar:BAACLgAFFH8lAAMYAAcJ7x1SCgA/AgAYAAYJ7x1SCgA/AgARAAEJAADXRgAAAAAuAAQKfy8AAxgACQkSJKUKAAoDABgACQkSJKUKAAoDABkAAwl+DQISAHEAAAAA.Demonbunz:BAAALgADCgUJBwAAAA==.Derregar:BAABLgAECn8cAAMQAAcJFx5rSwCtAQAQAAcJpx1rSwCtAQAaAAIJ0RL1SACTAAAAAA==.Dezamius:BAAALgAECgcJBwABLgAFFAQJCAAGAGAKAA==.',
Di='Dibella:BAAALgADCgYJAwAAAA==.Dirtydrago:BAAALgADCgUJBgABLgAECgUJBQAEAAAAAA==.Dirtymon:BAAALgADCgMJAwABLgAECgUJBQAEAAAAAA==.',
Dk='Dkfatality:BAACLgAFFH8NAAMZAAMJsR+qDQD7AAAZAAMJsR+qDQD7AAAYAAEJow5XVABPAAAuAAQKfy8AAxkACQmSI1EBAA4DABkACQmSI1EBAA4DABgABgl/IQ5dANsBAAAA.',
Dl='Dlord:BAAALgADCgYJCAAAAA==.',
Do='Dock:BAAALgAECgQJCQAAAA==.Dominbros:BAAALgAECgQJBAABLgAECgYJFwAIAJYWAA==.Dominhoes:BAABLgAECn8XAAIIAAYJlhaOiABLAQAIAAYJlhaOiABLAQAAAA==.Dondon:BAAALgADCgcJCQAAAA==.Doontless:BAAALgAECgYJEQAAAA==.Doyouknow:BAAALgAECgMJAwAAAA==.',
Dr='Draig:BAABLgAECn8UAAMIAAcJuAmusgABAQAIAAcJugiusgABAQAbAAIJWwe+GQBKAAAAAA==.Dratini:BAAALgADCggJBwABLgAECggJFwAcAEgZAA==.Drozigg:BAAALgADCgYJCQAAAA==.',
Du='Duckfury:BAABLgAECn8gAAIdAAgJ8RCuKQCdAQAdAAgJ8RCuKQCdAQAAAA==.Duckmourne:BAAALgAECgEJAQAAAA==.Dummy:BAAALgADCgYJBgAAAA==.Dunzoboom:BAAALgADCgcJCwAAAA==.Dunzö:BAAALgADCgYJBgAAAA==.',
['Dë']='Dëad:BAAALgAECgQJBgAAAA==.',
Eb='Ebonhèart:BAABLgAECn8ZAAMeAAgJygs/IgA3AQAeAAgJygs/IgA3AQAdAAEJwwUBqgA0AAAAAA==.',
Ec='Echoez:BAAALgAECgYJBwABLgAFFAQJEQAJAMYNAA==.Ecliptic:BAAALgAECgQJDQAAAA==.',
Eg='Eggle:BAAALgADCgIJAgAAAA==.',
Ei='Eisenheim:BAAALgADCgIJAgAAAA==.',
El='Electronvolt:BAABLgAECn8ZAAIfAAgJrBVIDAD/AQAfAAgJrBVIDAD/AQAAAA==.Eleidie:BAAALgADCgEJAQAAAA==.Elia:BAAALgAECgEJAQAAAA==.',
Ev='Evilyne:BAAALgADCgUJBwAAAA==.',
Ex='Exíled:BAAALgAECgEJAQAAAA==.',
Fa='Falilesta:BAAALgAECgEJAQAAAA==.Fallenlegion:BAAALgADCgcJBwAAAA==.Fartwizard:BAAALgAECgMJBQAAAA==.',
Fe='Felskerri:BAAALgADCgYJBgAAAA==.Fenus:BAAALgADCgIJAgAAAA==.',
Fi='Firebelly:BAAALgAECgMJAwAAAA==.Firerage:BAAALgADCgcJDwABLgAECgIJAwAEAAAAAA==.',
Fl='Flacidmonkey:BAAALgAECgcJDwAAAA==.Flufflenuzs:BAAALgAECgEJAQAAAA==.',
Fo='Fors:BAAALgAECgQJBAAAAA==.Forsäken:BAABLgAECn8VAAIIAAYJoRW0pwCKAQAIAAYJoRW0pwCKAQAAAA==.Forumangel:BAAALgADCgYJCQAAAA==.',
Fr='Freya:BAAALgADCgUJBQAAAA==.Fria:BAAALgAECgcJCAAAAA==.Frombehind:BAAALgAECgcJEgABLgAFFAYJHgAYAD4eAA==.',
Fu='Fubu:BAAALgAECgIJAgAAAA==.',
Ga='Gabenson:BAAALgADCgQJBAAAAA==.',
Gl='Glizzylatte:BAAALgADCgYJBgABLgAECgYJCwAEAAAAAA==.Gloomy:BAABLgAECn8qAAIgAAgJcSBYCQC9AgAgAAgJcSBYCQC9AgAAAA==.',
Gr='Grandizzle:BAABLgAECn8UAAIJAAgJVA+AUwBzAQAJAAgJVA+AUwBzAQAAAA==.Grandore:BAAALgAECgEJAwAAAA==.',
Gu='Gumbi:BAAALgAECgIJAgAAAA==.Gumgum:BAACLgAFFH8RAAMhAAQJliUIAQCvAQAhAAQJliUIAQCvAQAaAAEJzCF8FABlAAAuAAQKfzYAAiEACAlYJg0BAP8CACEACAlYJg0BAP8CAAAA.Guruprime:BAAALgADCgYJCAAAAA==.',
Gw='Gwalla:BAAALgADCgkJFwABLgAECgMJBQAEAAAAAA==.',
Ha='Hagniy:BAABLgAECn9UAAIXAAkJ8x4yCAD0AgAXAAkJ8x4yCAD0AgAAAA==.Hakunamatata:BAAALgADCgUJBQAAAA==.Halten:BAAALgAECgkJBwAAAA==.Happyboy:BAABLgAECn8eAAQNAAYJjh9WJAAWAgANAAYJjh9WJAAWAgAOAAYJ+BuRFACOAQACAAEJoBOjQQA6AAABLgAFFAQJCAANAH0YAA==.Hardrockcafe:BAAALgADCgYJAwAAAA==.Harfu:BAAALgAECgIJAgAAAA==.Hartzdrell:BAAALgADCgcJDAAAAA==.Hashirama:BAAALgAECgEJAQABLgAFFAQJDwAGAKAZAA==.',
He='Healmedaddy:BAAALgADCgEJAQAAAA==.Helbrandt:BAAALgAECgMJAwAAAA==.Heldarram:BAAALgAECgkJEQAAAA==.Hemaroid:BAAALgADCgcJBwAAAA==.Heolt:BAEALgADCgUJBQABLgAECgQJAQAEAAAAAA==.Hestia:BAAALgAECgUJBgAAAA==.Hexra:BAACLgAFFH8SAAIfAAUJyB9+CgDUAQAfAAUJyB9+CgDUAQAuAAQKfx4AAh8ACQnIISQFAPoCAB8ACQnIISQFAPoCAAAA.Heyzus:BAAALgAECgYJCQAAAA==.',
Ho='Honnok:BAAALgAECgQJBAAAAA==.Hoofweaver:BAAALgAECgUJBQAAAA==.Hornyhead:BAAALgAECgQJDQAAAA==.Howard:BAAALgADCgIJAgAAAA==.',
Hr='Hrizul:BAABLgAECn8zAAMTAAkJ5R2LBACdAgATAAgJGiGLBACdAgAPAAcJ3Q6nigBAAQAAAA==.',
Ib='Iblameheals:BAAALgADCgMJBAAAAA==.',
Ic='Icebarron:BAAALgAECgYJDQAAAA==.',
Il='Il:BAABLgAECn8iAAIQAAkJtx4tIACXAgAQAAkJtx4tIACXAgAAAA==.Illisharr:BAAALgADCggJEQAAAA==.Iloveleaf:BAAALgADCgEJAQAAAA==.Ilusive:BAABLgAECn8cAAIFAAgJrhFVMABkAQAFAAgJrhFVMABkAQAAAA==.',
Ir='Irazlynaa:BAAALgADCgUJDgAAAA==.Irielyn:BAAALgAECgUJBQAAAA==.Ironblight:BAAALgAECgEJAQAAAA==.Irrah:BAAALgAECgYJDwAAAA==.',
Is='Ishal:BAAALgADCgEJAQAAAA==.',
Ja='Jabar:BAAALgADCgEJAQAAAA==.Jagz:BAABLgAECn87AAMiAAkJ7B3qFgBeAgAiAAgJBR3qFgBeAgAFAAgJ4h22FAArAgAAAA==.',
Jh='Jharael:BAAALgADCgUJBwAAAA==.',
Ji='Jia:BAAALgAECgEJAgAAAA==.',
Jo='Jonsi:BAAALgADCgUJBQABLgAECggJFwAcAEgZAA==.',
Ju='Junö:BAAALgAECgEJAQAAAA==.Jursh:BAAALgADCgQJBAAAAA==.',
Ka='Kaelen:BAAALgAECgcJEAAAAA==.Kaley:BAAALgADCgIJAgAAAA==.Kasuo:BAAALgADCgYJAwAAAA==.Katamine:BAABLgAECn8zAAIDAAgJdxtOFwD9AQADAAgJdxtOFwD9AQAAAA==.Katoz:BAABLgAECn8aAAMYAAgJHx4pMwAeAgAYAAgJHx4pMwAeAgAZAAIJTRYvEgBuAAAAAA==.Kawas:BAAALgAECgYJCQAAAA==.',
Ke='Keydron:BAAALgADCggJDwAAAA==.',
Kh='Khài:BAAALgAECgQJBQAAAA==.',
Ki='Kickit:BAAALgADCgQJBAAAAA==.Kilemall:BAAALgAECgkJAgAAAA==.Killnall:BAABLgAECn8jAAIPAAYJnQen1QDMAAAPAAYJnQen1QDMAAAAAA==.Kiyohime:BAAALgAECgIJAgAAAA==.',
Kj='Kjadmina:BAAALgADCgUJBAAAAA==.',
Kl='Kladon:BAABLgAECn8gAAIBAAkJJxoMCADrAQABAAkJJxoMCADrAQAAAA==.Klozkoth:BAAALgAECgYJBgAAAA==.',
Ko='Konantheduck:BAAALgADCgMJAwABLgAECggJIAAdAPEQAA==.',
Kr='Krystarin:BAABLgAECn8sAAINAAgJpRcvIQArAgANAAgJpRcvIQArAgAAAA==.Kryx:BAAALgADCgkJEAAAAA==.Kráytos:BAAALgAECgUJCAAAAA==.',
Ky='Kynria:BAAALgAECgIJAwAAAA==.',
La='Lallaure:BAAALgADCgQJBAAAAA==.Lambic:BAAALgAECgQJBAAAAA==.Lanma:BAABLgAECn8XAAIcAAgJSBlBEQBvAgAcAAgJSBlBEQBvAgAAAA==.Larpgodx:BAAALgAECgIJAwAAAA==.Lastoran:BAAALgAECgMJBQAAAA==.Lateralus:BAABLgAECn9HAAIjAAkJWiH0AAAGAwAjAAkJWiH0AAAGAwAAAA==.Launcelot:BAABLgAECn8dAAMdAAcJSCKUHwBUAgAdAAYJ+yKUHwBUAgAeAAQJRB/FIAA/AQAAAA==.Laurasecord:BAAALgADCgQJBAAAAA==.Lazymage:BAAALgAECgcJDAAAAA==.',
Le='Leanbeef:BAAALgAECgYJBgAAAA==.Lerath:BAAALgAECggJDAAAAA==.Leshy:BAAALgADCgYJBgAAAA==.',
Li='Lights:BAACLgAFFH8LAAISAAMJ1CHgGgD8AAASAAMJ1CHgGgD8AAAuAAQKfz8AAxIACQnuJbABAEwDABIACQnuJbABAEwDACQABQmTIJgbANABAAEuAAUUBAkPAAYAoBkA.Littlezo:BAACLgAFFH8NAAIlAAQJnRaGDgBGAQAlAAQJnRaGDgBGAQAuAAQKfy0AAiUACQl0JQcBAFQDACUACQl0JQcBAFQDAAAA.',
Lo='Lotus:BAABLgAECn8tAAQcAAkJfxaKFAAAAgAcAAkJNBaKFAAAAgAmAAUJHhWhLQA+AQAHAAYJ5wz3OAAFAQAAAA==.',
Lt='Ltrnck:BAAALgADCgIJAgAAAA==.',
Lu='Lu:BAAALgADCgEJAQAAAA==.Luckbound:BAAALgAECgEJAQABLgAFFAQJCAANAH0YAA==.Luthonys:BAAALgADCgEJAQAAAA==.',
Ma='Magond:BAAALgAECgIJAgAAAA==.Makoha:BAABLgAECn83AAMOAAkJDhH3FACKAQAOAAkJDhH3FACKAQACAAEJwA7bRQAwAAAAAA==.Makpriest:BAAALgAECgYJDgAAAA==.Malakaii:BAABLgAECn8cAAMLAAgJexEYDAAEAgALAAgJQREYDAAEAgAFAAYJrhLKQgA+AQAAAA==.Margaes:BAAALgADCgEJAgAAAA==.Mariahh:BAAALgADCgEJAQAAAA==.Masherkillu:BAACLgAFFH8KAAIFAAQJgg3OIAAAAQAFAAQJgg3OIAAAAQAuAAQKfycAAgUACQkkGAUTAD0CAAUACQkkGAUTAD0CAAAA.Masherpally:BAACLgAFFH8HAAMPAAMJ3wZgZADEAAAPAAMJ3wZgZADEAAATAAEJPgUsFQAyAAAuAAQKfyQAAw8ACQkNG64YAJgCAA8ACQkNG64YAJgCABMAAwktDt04AGEAAAEuAAUUBAkKAAUAgg0A.Maxdeath:BAABLgAECn8bAAIIAAkJpQ5OgADQAQAIAAkJpQ5OgADQAQAAAA==.Maztajake:BAABLgAECn8VAAIDAAcJ1h3oGQDjAQADAAcJ1h3oGQDjAQAAAA==.Mazyjake:BAAALgAECgcJCQABLgAECgcJFQADANYdAA==.Mazzyjake:BAAALgAECgQJBAABLgAECgcJFQADANYdAA==.',
Me='Medorh:BAAALgADCgYJBgAAAA==.Melchizedic:BAAALgAECgMJBwAAAA==.Merily:BAAALgADCgQJBAAAAA==.',
Mi='Mikeytott:BAAALgADCgQJBQAAAA==.Minnie:BAAALgAECgEJAQABLgAECgkJIQAGAPUZAA==.',
Mo='Mohgmoment:BAAALgADCgYJBgAAAA==.Moonfare:BAAALgADCgEJAgAAAA==.Mordacity:BAEBLgAECn8sAAInAAgJ+QbSEwD4AAAnAAgJ+QbSEwD4AAAAAA==.',
Mu='Muris:BAAALgAECgQJBAAAAA==.',
['Mä']='Määt:BAAALgADCgIJAgAAAA==.',
Na='Nardo:BAAALgAECgEJAQAAAA==.',
Ne='Necromaine:BAAALgAECgQJDQAAAA==.Necrot:BAAALgAECgEJAQAAAA==.',
Ng='Nghtíy:BAABLgAECn8aAAIYAAYJQBMPqQAIAQAYAAYJQBMPqQAIAQAAAA==.',
Ni='Nixa:BAAALgADCgUJBQAAAA==.',
No='Nocturnüs:BAABLgAECn8oAAISAAkJlhF2HADEAQASAAkJlhF2HADEAQAAAA==.Noh:BAAALgAECgIJAgAAAA==.Nordikmage:BAABLgAECn8aAAMIAAcJhxH2hQBQAQAIAAcJhxH2hQBQAQAbAAEJPwVSIAAuAAAAAA==.Nort:BAAALgADCgEJAgAAAA==.Nov:BAAALgADCgMJAwAAAA==.',
['Nê']='Nêcrömane:BAAALgAECgUJCAAAAA==.',
Oh='Ohtheirone:BAAALgADCgYJBgAAAA==.Ohtheironey:BAAALgADCgUJBQAAAA==.Ohtheironie:BAAALgADCgYJBgAAAA==.',
On='Ondereth:BAAALgAECgYJDgAAAA==.Onthehouse:BAAALgAECgYJDgAAAA==.',
Or='Orid:BAAALgADCgcJBwAAAA==.Orvannan:BAAALgADCgQJCAAAAA==.',
Pa='Pacho:BAAALgADCgUJBQAAAA==.Palimorea:BAEALgADCggJFwABLgAECgQJAQAEAAAAAA==.',
Pi='Piercey:BAACLgAFFH8LAAIWAAYJWBF2CQBwAQAWAAYJWBF2CQBwAQAuAAQKfyoAAxYACAntHr4KAGUCABYACAntHr4KAGUCAB4AAQmeFTRhAEEAAAEuAAUUBAkIAA0AfRgA.Pinkylove:BAABLgAECn8eAAINAAgJ8iBODADcAgANAAgJ8iBODADcAgAAAA==.',
Pr='Proera:BAAALgAECgcJCQAAAA==.Promathia:BAACLgAFFH8VAAMTAAQJ6x6HBQAXAQAPAAQJCxzXKgBBAQATAAMJ9iCHBQAXAQAuAAQKf08ABA8ACQnLJp4AAIwDAA8ACQnLJp4AAIwDABcABAkXCCVuAMIAABMAAQkDJV43AGcAAAAA.Pross:BAAALgAECgQJCQABLgAECgkJLQAPANQcAA==.',
Ps='Psychopath:BAABLgAECn8aAAMUAAYJohYVLACeAQAUAAYJohYVLACeAQAVAAEJtwYkIAAyAAAAAA==.',
Pu='Puff:BAAALgAECggJDQAAAA==.',
Ra='Raenori:BAAALgADCgYJBgAAAA==.Ragnarolk:BAAALgAECgIJAgAAAA==.Raiyuden:BAAALgAECgEJAQAAAA==.Randydaytona:BAAALgAECgYJCwAAAA==.Rangërdangër:BAACLgAFFH8OAAIMAAUJrwZQQwABAQAMAAUJrwZQQwABAQAuAAQKfxYAAgwACQkQFQo1ANoBAAwACQkQFQo1ANoBAAAA.Rat:BAABLgAECn8jAAISAAkJSSBzBABOAwASAAkJSSBzBABOAwAAAA==.',
Re='Rectumus:BAAALgADCgcJEQAAAA==.Redrouges:BAACLgAFFH8FAAIUAAIJcRajKACmAAAUAAIJcRajKACmAAAuAAQKfycAAhQACAnyIAAIAJECABQACAnyIAAIAJECAAAA.Redwood:BAAALgAECgMJBQAAAA==.Renvskadoosh:BAAALgADCgkJGQABLgAECgcJHgAiAF0JAA==.Revhero:BAAALgAECgEJAQAAAA==.Rexpanda:BAABLgAECn8YAAIHAAYJ1R2CGgDmAQAHAAYJ1R2CGgDmAQAAAA==.',
Ro='Roguetheholy:BAAALgAECgkJBQAAAA==.Ross:BAEALgADCgEJAQABLgAFFAUJFAAdAA8lAA==.Rotawnda:BAAALgAECgYJBwAAAA==.Rotlord:BAAALgAECgYJCgAAAA==.',
Ru='Ruckus:BAAALgAECgYJCwAAAA==.Rumble:BAAALgAECgEJAQAAAA==.Rumrootbeer:BAAALgADCgIJAQAAAA==.',
['Rë']='Rëkz:BAAALgAECgMJAwAAAA==.',
['Rì']='Rìppér:BAAALgAECgEJAQABLgAFFAUJEgAfAMgfAA==.',
Sa='Sanelle:BAAALgADCgkJCQABLgAECgkJKwAkABQgAA==.Sapoude:BAAALgAECgcJBwAAAA==.Sarang:BAAALgADCgcJBwAAAA==.Sarrsaras:BAAALgAECgEJAQABLgAECgcJEAAEAAAAAA==.',
Se='Seaursus:BAAALgAECgMJCAAAAA==.Seerblade:BAAALgADCgcJCgABLgAECgYJCwAEAAAAAA==.Sekaiju:BAAALgAECgQJBgAAAA==.Selakin:BAAALgADCgIJAgAAAA==.',
Sh='Shadowbann:BAAALgAECgMJBQAAAA==.Shadowrunner:BAAALgAECgEJAQAAAA==.Shammydavis:BAAALgADCgEJAQAAAA==.Shamwich:BAAALgAECgkJEgAAAA==.Shandroz:BAAALgAECgUJBQAAAA==.Shaori:BAAALgADCgMJBAAAAA==.Shortzo:BAAALgAECgcJCwABLgAFFAQJDQAlAJ0WAA==.Shrkbait:BAAALgAECgUJCgAAAA==.',
Si='Sikozu:BAAALgAECgIJAgAAAA==.',
Sk='Skeezicks:BAAALgADCgUJBQAAAA==.Skidoosh:BAAALgAECgEJAwAAAA==.Skullcleaver:BAAALgADCgcJFAAAAA==.',
Sl='Slycc:BAAALgAECgMJAwAAAA==.',
Sm='Smackerr:BAAALgADCgUJBgAAAA==.',
Sn='Sneakay:BAABLgAFFH8GAAIaAAMJqQUcDAC5AAAaAAMJqQUcDAC5AAAAAA==.Sneakybiter:BAAALgADCgcJDQAAAA==.',
So='Solei:BAAALgAECgUJBQAAAA==.Southernguy:BAAALgAECgMJBAAAAA==.',
Sp='Spazzies:BAAALgAECgcJDQAAAA==.',
Sq='Squigglybutt:BAABLgAECn8qAAMgAAcJkR/qDAB/AgAgAAcJkR/qDAB/AgAkAAUJ3xYKKwBZAQAAAA==.',
St='Steelwing:BAAALgAFFAMJAwAAAA==.Stormbeards:BAAALgADCgYJBgAAAA==.Stoutkeg:BAAALgADCgQJAwAAAA==.Strixmonk:BAEALgAFFAIJAwABLgAFFAYJGgAYAC4eAA==.Strrawberry:BAAALgADCgIJAgAAAA==.Stêven:BAAALgAECggJCAAAAA==.Störmî:BAAALgAECgEJAQAAAA==.',
Su='Sungchaluka:BAAALgAECgMJBwAAAA==.',
['Sá']='Sásu:BAAALgADCgkJFQAAAA==.',
Ta='Talsomething:BAAALgAFFAEJAgAAAA==.Talsumthing:BAABLgAFFH8JAAIXAAUJqwQIHwAOAQAXAAUJqwQIHwAOAQAAAA==.Tars:BAAALgAECgYJBgAAAA==.Tats:BAABLgAECn8kAAIPAAgJMB3lLAA0AgAPAAgJMB3lLAA0AgAAAA==.Tatsumâ:BAAALgAECgYJDAAAAA==.',
Te='Terraxic:BAAALgAECgYJDAAAAA==.Terthaith:BAABLgAECn8YAAIQAAkJKwzuUgCXAQAQAAkJKwzuUgCXAQAAAA==.Tezguin:BAAALgADCgYJDQAAAA==.',
Th='Theedemon:BAAALgAECgQJBAAAAA==.Theironie:BAAALgADCgYJBgAAAA==.Theparttimer:BAAALgADCgEJAQAAAA==.Thiccpie:BAAALgAECgYJCwAAAA==.Throdwran:BAAALgAECgYJDAABLgAECgkJLQAPANQcAA==.',
Ti='Timba:BAAALgAECgYJCAAAAA==.Tisaka:BAABLgAECn8aAAIUAAYJAxmZJQDMAQAUAAYJAxmZJQDMAQAAAA==.',
Tl='Tlovexx:BAAALgAFFAEJAQAAAA==.',
To='Tolya:BAAALgADCgEJAQAAAA==.Toohbooh:BAAALgAECgMJBgAAAA==.Totem:BAAALgAECgcJDAAAAA==.',
Tr='Tranqx:BAACLgAFFH8TAAMZAAQJnyQYCgAqAQAZAAMJiCIYCgAqAQAYAAMJGSTUXQAgAQAuAAQKfzkAAxkACQnoJjYBABYDABgACAm1JlUIAFwDABkACAmnJjYBABYDAAAA.Treevlo:BAAALgADCgEJAQAAAA==.Treva:BAABLgAECn8hAAQGAAkJ9RkQHQDUAQAGAAkJ9RkQHQDUAQAjAAQJtAYrLgCoAAAfAAEJZQPfSgAsAAAAAA==.Trizz:BAAALgAFFAEJAQAAAA==.Troctzul:BAAALgADCgEJAwAAAA==.Trollmachine:BAAALgAECgEJAQABLgAECgcJFQADANYdAA==.',
Ts='Tsuchiya:BAAALgAECgYJCwAAAA==.',
Tu='Tuts:BAAALgADCgYJDAAAAA==.',
Ty='Tythos:BAAALgADCgYJCwAAAA==.',
Up='Uproar:BAACLgAFFH8GAAIZAAMJhA1OFQCaAAAZAAMJhA1OFQCaAAAuAAQKfy4AAhkACQlDJQMBACQDABkACQlDJQMBACQDAAAA.',
Va='Vaelira:BAAALgADCgkJCQAAAA==.Vahlfi:BAACLgAFFH8EAAIJAAIJCRy6ZgCUAAAJAAIJCRy6ZgCUAAAuAAQKfxwABAkACQljJMgMAM4CAAkACQljJMgMAM4CAAoAAQm6IrZKAGQAACcAAgkTESAvADAAAAEuAAUUBQkUABUA7iUA.Valemon:BAAALgAFFAIJAwAAAA==.Valeskogr:BAABLgAECn8dAAQMAAkJAg5YVACNAQAMAAgJZw5YVACNAQAlAAcJjQjeFAB6AQABAAgJmAN0UAAMAQAAAA==.Valffi:BAAALgAFFAEJAQABLgAFFAUJFAAVAO4lAA==.Varoth:BAAALgAECgEJAQAAAA==.Varus:BAAALgAECgYJCQAAAA==.',
Ve='Velisá:BAAALgAECgIJAgAAAA==.Vengefulmilk:BAAALgAECgUJDQAAAA==.Venture:BAAALgADCgkJIgAAAA==.Vergo:BAAALgADCgEJAQAAAA==.Vescovo:BAABLgAECn8rAAQkAAkJFCB6BQAWAwAkAAkJFCB6BQAWAwASAAUJ0RVdOwABAQAgAAEJrh+jdABWAAAAAA==.',
Vi='Virde:BAAALgADCgMJAwAAAA==.',
Vl='Vll:BAABLgAECn8hAAIKAAgJ7iL2BQDBAgAKAAgJ7iL2BQDBAgAAAA==.',
Vo='Volkihar:BAAALgAFFAIJAwAAAA==.Vordt:BAAALgAECgIJBwAAAA==.',
Wa='Wardaorm:BAABLgAECn8fAAIdAAYJDg4pXgDBAAAdAAYJDg4pXgDBAAABLgAECgkJLQAPANQcAA==.Warkinz:BAAALgADCgQJBQAAAA==.Warlin:BAAALgAECgEJAQAAAA==.',
Wi='Willohh:BAAALgAECgQJBAAAAA==.Winden:BAABLgAECn8WAAILAAYJhhvgFABLAQALAAYJhhvgFABLAQAAAA==.Wingback:BAAALgAECgcJBQAAAA==.Wiz:BAAALgAECgYJDgAAAA==.',
Wp='Wphoenix:BAAALgAECgQJBAAAAA==.',
Wr='Wrizz:BAAALgADCgYJCAAAAA==.',
Wt='Wtfsteve:BAAALgADCgUJBQABLgAECggJFwAcAEgZAA==.',
Xa='Xadrai:BAAALgAECgYJCwAAAA==.',
Xe='Xeplin:BAAALgAECgUJCQAAAA==.',
Xh='Xhenshini:BAACLgAFFH8IAAMGAAQJYAqjMQDhAAAGAAQJYAqjMQDhAAAjAAEJtwbMCgBPAAAuAAQKf0IAAwYACQlOIT0FAPYCAAYACQkcIT0FAPYCACMACAmqGjEJAE4CAAAA.',
Xk='Xkrin:BAAALgAECgEJAQAAAA==.',
Ye='Yeonguo:BAAALgAECgYJDgAAAA==.',
Yu='Yums:BAAALgADCgcJCwAAAA==.',
Za='Zalethe:BAAALgAECgMJAwAAAA==.Zalliel:BAAALgADCggJCAAAAA==.Zalman:BAAALgAECgMJBQAAAA==.Zaphíel:BAAALgADCgcJBwABLgAECgkJGAAQACsMAA==.Zaran:BAAALgAFFAEJAQAAAA==.',
Ze='Zeninnaoya:BAABLgAECn8fAAMeAAkJuSD6AABaAwAeAAkJ3B36AABaAwAdAAcJISaFDgDgAgAAAA==.',
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
