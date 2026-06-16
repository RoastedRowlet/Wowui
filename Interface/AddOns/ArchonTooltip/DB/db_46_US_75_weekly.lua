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

local lookup = {'Hunter-Marksmanship','Druid-Feral','Druid-Balance','Unknown-Unknown','Shaman-Elemental','Evoker-Augmentation','Monk-Mistweaver','Priest-Discipline','Mage-Frost','DemonHunter-Devourer','DemonHunter-Havoc','Shaman-Enhancement','Hunter-BeastMastery','Druid-Guardian','Druid-Restoration','Warrior-Protection','Paladin-Retribution','Warlock-Demonology','DeathKnight-Blood','Priest-Holy','Priest-Shadow','Monk-Windwalker','Monk-Brewmaster','Paladin-Protection','Rogue-Subtlety','Rogue-Assassination','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Destruction','Mage-Arcane','Warrior-Fury','Warrior-Arms','Evoker-Preservation','Warlock-Affliction','Shaman-Restoration','Evoker-Devastation','Hunter-Survival','DemonHunter-Vengeance',}
local provider = {region='US',realm="Drak'thul",name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aalluntic:BAAALgAECgYJBgAAAA==.',
Ad='Ador:BAAALgAECgUJBQAAAA==.',
Ae='Aeladrel:BAAALgADCggJCAAAAA==.',
Ak='Akirie:BAABLgAECn8aAAIBAAYJDxcxFAAaAQABAAYJDxcxFAAaAQAAAA==.Akumu:BAABLgAECn8eAAMCAAkJrRtVBQC5AgACAAkJrRtVBQC5AgADAAEJAAAxrQAAAAABLgAFFAMJAwAEAAAAAA==.Akumua:BAAALgAECgQJBAABLgAFFAMJAwAEAAAAAA==.',
Al='Alangi:BAABLgAECn8ZAAIFAAcJjgzkSwABAQAFAAcJjgzkSwABAQABLgAFFAUJCQAGAGAKAA==.Albinah:BAABLgAECn8dAAIHAAcJAB3RHgAeAgAHAAcJAB3RHgAeAgAAAA==.Albsli:BAAALgADCgIJAgAAAA==.Albsygos:BAAALgADCgQJBAAAAA==.Albz:BAAALgADCgkJHAAAAA==.Albzap:BAAALgADCgMJAwAAAA==.Albzley:BAABLgAECn8kAAIIAAkJ6RgiDQCZAgAIAAkJ6RgiDQCZAgAAAA==.Albzu:BAAALgAECgUJBQAAAA==.Aldien:BAABLgAECn8YAAIJAAYJ4AYj3ADcAAAJAAYJ4AYj3ADcAAAAAA==.Aliphar:BAAALgADCgEJAQAAAA==.Allaria:BAAALgAECgYJBgAAAA==.',
Ao='Aoe:BAACLgAFFH8VAAIKAAQJIBOUQwAWAQAKAAQJIBOUQwAWAQAuAAQKfyMAAgoACQlAHv8PAMACAAoACQlAHv8PAMACAAEuAAUUBgkTAAsA6hoA.',
Ar='Arcanism:BAAALgAECgYJCwAAAA==.Arienna:BAAALgAECgMJAwAAAA==.Arteñ:BAAALgAECgUJCQAAAA==.',
As='Ashrak:BAABLgAECn8jAAIMAAcJAROlFABuAQAMAAcJAROlFABuAQAAAA==.',
At='Attitudyjudy:BAAALgAECgUJBQAAAA==.',
Av='Averroes:BAABLgAECn9DAAINAAkJGhprHQBxAgANAAkJGhprHQBxAgAAAA==.',
Aw='Awee:BAACLgAFFH8TAAILAAYJ6ho3BADSAQALAAYJ6ho3BADSAQAuAAQKf0sAAgsACQkwJJUDABkDAAsACQkwJJUDABkDAAAA.Awi:BAAALgADCgUJBQABLgAFFAYJEwALAOoaAA==.Awo:BAACLgAFFH8RAAMOAAQJTCOgBQCdAQAOAAQJTCOgBQCdAQAPAAQJvR4BGwB6AQAuAAQKfzgABA8ACAlmJRcGAFQDAA8ACAlmJRcGAFQDAA4ACAklH/4IAFgCAAIABgmIFkIUAG4BAAEuAAUUCAkRABAAVxQA.Awoo:BAAALgAECgYJBwABLgAFFAgJEQAQAFcUAA==.',
Ay='Aylen:BAABLgAECn8eAAIRAAkJ6A62bgCOAQARAAkJ6A62bgCOAQAAAA==.',
Ba='Babsvilla:BAAALgAECgYJEwAAAA==.Badmagi:BAAALgAECgEJAQAAAA==.Bahldrahg:BAAALgAECgMJAwAAAA==.Baki:BAACLgAFFH8UAAIGAAUJMxwIIgBJAQAGAAUJMxwIIgBJAQAuAAQKfxwAAgYACQn+JKICAE8DAAYACQn+JKICAE8DAAAA.Banegrim:BAABLgAECn9FAAISAAgJDBJKUgCkAQASAAgJDBJKUgCkAQAAAA==.Bankisa:BAAALgAECgUJBQAAAA==.Barnbirt:BAAALgAECgEJAQAAAA==.Barron:BAAALgAECgIJAgAAAA==.Barronthee:BAAALgAECgIJAgAAAA==.Battlecat:BAABLgAECn8aAAIJAAgJjhJzbQCcAQAJAAgJjhJzbQCcAQAAAA==.',
Be='Beelzebubx:BAAALgAECgQJBAABLgAFFAMJAwAEAAAAAA==.Belysiuh:BAAALgAECgMJAwAAAA==.',
Bl='Blackdaisydr:BAAALgADCgcJDQABLgAECgYJCwAEAAAAAA==.Blindwalker:BAABLgAECn8hAAITAAkJeQ3KKAAMAQATAAkJeQ3KKAAMAQAAAA==.Blissfuleigh:BAAALgAECgIJAwAAAA==.Bloodbarron:BAAALgAECgYJCgAAAA==.',
Bo='Boldius:BAAALgADCgQJBAABLgAECgUJBQAEAAAAAA==.Bookchin:BAAALgADCgEJAQAAAA==.Bootylust:BAAALgADCgYJBgABLgAECgcJNgAUAJEfAA==.',
Br='Bragdand:BAEALgAECgYJBQAAAA==.Braistlin:BAAALgADCgIJAgABLgAECgUJBQAEAAAAAA==.Bred:BAAALgADCgcJBwAAAA==.Brewfest:BAAALgADCgMJBgAAAA==.Briarthorn:BAAALgAECgYJBgAAAA==.',
Bu='Bubblegump:BAAALgAECgIJAgAAAA==.Bulin:BAAALgADCgQJBAAAAA==.',
['Bü']='Büdwèiserr:BAAALgAECgQJDQAAAA==.',
Ca='Cadillacbob:BAAALgAECgIJAwAAAA==.Calon:BAAALgAECgQJBQAAAA==.Cantseedizz:BAAALgADCgMJAwAAAA==.Castigate:BAACLgAFFH8eAAIVAAYJJiKZBwDtAQAVAAYJJiKZBwDtAQAuAAQKfy4AAhUACQmHIosIAMYCABUACQmHIosIAMYCAAAA.',
Ce='Cederek:BAAALgADCgIJAgAAAA==.Ceresarian:BAAALgADCgMJAwAAAA==.',
Ch='Chancho:BAAALgAECgYJCgABLgAECgkJPQAOAA4RAA==.Cheesekitten:BAAALgADCgEJAQABLgAFFAIJBwARAJolAA==.Cheesemonk:BAABLgAECn8aAAMWAAkJ+SNWAgBHAwAWAAkJ+SNWAgBHAwAXAAcJGSJVDgBSAgABLgAFFAIJBwARAJolAA==.Cheesepally:BAACLgAFFH8HAAIRAAIJmiXAaADXAAARAAIJmiXAaADXAAAuAAQKf0EAAhEACQnCJnoBAIADABEACQnCJnoBAIADAAAA.Cheesewhelp:BAAALgADCgcJBwAAAA==.Chikoung:BAAALgADCgUJBQAAAA==.Chudmourne:BAAALgAECgUJBQAAAA==.',
Cl='Cloud:BAABLgAECn8oAAMYAAkJbCOvAQApAwAYAAkJbCOvAQApAwARAAIJfhVLMgF2AAAAAA==.',
Co='Coderictond:BAAALgADCgQJBgAAAA==.Cogpally:BAAALgADCggJCAAAAA==.',
Cr='Crysa:BAAALgADCgYJBgAAAA==.',
Cy='Cyanide:BAAALgADCgkJCQAAAA==.Cygnus:BAABLgAECn8yAAMZAAgJkRQxGQDNAQAZAAgJkRQxGQDNAQAaAAUJfwbmFADYAAAAAA==.Cylla:BAABLgAECn8fAAINAAcJGiRTHQBxAgANAAcJGiRTHQBxAgABLgAFFAUJHgARAPEfAA==.',
Da='Daddywarbuks:BAAALgAECgUJBgAAAA==.Dagin:BAABLgAECn8uAAIRAAkJ1BzVIQB9AgARAAkJ1BzVIQB9AgAAAA==.Dalarenaric:BAAALgADCgcJDAAAAA==.Dalt:BAAALgAFFAEJAQAAAA==.Daltonator:BAAALgADCgMJAwAAAA==.Dantemore:BAABLgAECn8aAAICAAcJlxfnEQCWAQACAAcJlxfnEQCWAQAAAA==.Daorcy:BAAALgADCggJDgAAAA==.Dartherd:BAABLgAECn89AAIQAAkJhhzIBgCaAgAQAAkJhhzIBgCaAgAAAA==.Dawnotheholy:BAABLgAECn9JAAQbAAkJYw46KgC6AQAbAAkJYw46KgC6AQARAAcJJBBKsQAaAQAYAAQJABCFKgDCAAAAAA==.',
De='Deathbyone:BAAALgADCgkJAwAAAA==.Deathstar:BAACLgAFFH8sAAQcAAgJoxt+FAAoAgAcAAYJ7x1+FAAoAgAdAAUJTBYSBQCZAQATAAEJAAD6TAAAAAAuAAQKfy8AAxwACQkSJEcNAAEDABwACQkSJEcNAAEDAB0AAwl+DQISAHEAAAAA.Deliverhealz:BAAALgAECgUJBQAAAA==.Demonbunz:BAAALgADCgUJBwAAAA==.Derregar:BAABLgAECn8cAAMSAAcJFx4MUQCnAQASAAcJpx0MUQCnAQAeAAIJ0RL1SACTAAAAAA==.Dezamius:BAAALgAECgcJBwABLgAFFAUJCQAGAGAKAA==.',
Di='Dibella:BAAALgADCgYJAwAAAA==.Dirtydrago:BAAALgADCgUJBgABLgAECgUJBQAEAAAAAA==.Dirtymon:BAAALgADCgMJAwABLgAECgUJBQAEAAAAAA==.',
Dk='Dkfatality:BAACLgAFFH8NAAMdAAMJsR/+EgDtAAAdAAMJsR/+EgDtAAAcAAEJow5XVABPAAAuAAQKfy8AAx0ACQmSI9UBAAsDAB0ACQmSI9UBAAsDABwABgl/IQ5dANsBAAAA.',
Dl='Dlord:BAAALgADCgYJCAAAAA==.',
Do='Dock:BAAALgAECgQJCQAAAA==.Dominbros:BAAALgAECgQJBAABLgAECgYJFwAJAJYWAA==.Dominhoes:BAABLgAECn8XAAIJAAYJlhYzlABMAQAJAAYJlhYzlABMAQAAAA==.Dondon:BAAALgAECgQJBAAAAA==.Doontless:BAAALgAECgYJEQAAAA==.Doyouknow:BAAALgAECgMJAwAAAA==.',
Dr='Draig:BAABLgAECn8UAAMJAAcJuAkuuwANAQAJAAcJugguuwANAQAfAAIJWwe+GQBKAAAAAA==.Dratini:BAAALgADCggJBwABLgAECggJFwAWAEgZAA==.Drozigg:BAAALgADCgYJCQAAAA==.',
Du='Duckfury:BAABLgAECn8gAAIgAAgJ8RBeLgCWAQAgAAgJ8RBeLgCWAQAAAA==.Duckmourne:BAAALgAECggJCQABLgAECggJIAAgAPEQAA==.Dummy:BAAALgADCgYJBgAAAA==.Dunzoboom:BAAALgADCgcJCwAAAA==.Dunzö:BAAALgADCgYJBgAAAA==.',
['Dë']='Dëad:BAAALgAECgQJBgAAAA==.',
Eb='Ebonhèart:BAABLgAECn8ZAAMhAAgJygspJwAuAQAhAAgJygspJwAuAQAgAAEJwwUBqgA0AAAAAA==.',
Ec='Echoez:BAABLgAECn8UAAIHAAYJVxdyNgCTAQAHAAYJVxdyNgCTAQABLgAFFAQJEgAKAMYNAA==.Ecliptic:BAAALgAECgQJDQAAAA==.',
Eg='Eggle:BAAALgADCgIJAgAAAA==.',
Ei='Eisenheim:BAAALgADCgIJAgAAAA==.',
El='Electronvolt:BAABLgAECn8ZAAIiAAgJrBVKDQD4AQAiAAgJrBVKDQD4AQAAAA==.Eleidie:BAAALgADCgEJAQAAAA==.Elia:BAAALgAECgEJAQAAAA==.',
Ev='Evilyne:BAAALgADCgUJBwAAAA==.',
Ex='Exíled:BAAALgAECgEJAQAAAA==.',
Fa='Falilesta:BAAALgAECgEJAgAAAA==.Fallenlegion:BAAALgADCgcJBwAAAA==.Fartwizard:BAAALgAECgMJBQAAAA==.',
Fe='Felskerri:BAAALgADCgYJBgAAAA==.Fenus:BAAALgADCgIJAgAAAA==.',
Fi='Firebelly:BAAALgAECgMJAwAAAA==.Firerage:BAAALgADCgcJDwABLgAECgMJBgAEAAAAAA==.',
Fl='Flacidmonkey:BAAALgAECgcJDwAAAA==.Flufflenuzs:BAAALgAECgEJAQAAAA==.',
Fo='Fors:BAAALgAECgQJBAAAAA==.Forsäken:BAABLgAECn8VAAIJAAYJoRW0pwCKAQAJAAYJoRW0pwCKAQAAAA==.Forumangel:BAAALgADCgYJCQAAAA==.',
Fr='Freya:BAAALgADCgUJBQAAAA==.Fria:BAAALgAECgcJCAAAAA==.Frombehind:BAAALgAECgcJEgABLgAFFAgJIgAcAK4YAA==.',
Fu='Fubu:BAAALgAECgIJAgAAAA==.',
Ga='Gabenson:BAAALgADCgQJBAAAAA==.',
Ge='Geegnome:BAAALgAECgEJAQAAAA==.',
Gl='Glizzylatte:BAAALgADCgYJBgABLgAECgYJCwAEAAAAAA==.Gloomy:BAABLgAECn87AAIUAAkJhx5DCADlAgAUAAkJhx5DCADlAgAAAA==.',
Gr='Grandbear:BAAALgAFFAEJAQAAAA==.Grandizzle:BAABLgAECn8XAAIKAAgJVA/RXABuAQAKAAgJVA/RXABuAQAAAA==.Grandore:BAAALgAECgEJAwAAAA==.',
Gu='Gumbi:BAAALgAECgIJAgAAAA==.Gumgum:BAACLgAFFH8WAAMjAAQJliXDAQCiAQAjAAQJliXDAQCiAQAeAAEJ4CGQGABkAAAuAAQKfzYAAiMACAlYJg0BAP8CACMACAlYJg0BAP8CAAAA.Guruprime:BAAALgADCgYJCAAAAA==.',
Gw='Gwalla:BAAALgADCgkJFwABLgAECgMJBQAEAAAAAA==.',
Ha='Hagniy:BAABLgAECn9dAAIbAAkJ8x4/CQD1AgAbAAkJ8x4/CQD1AgAAAA==.Hakunamatata:BAAALgADCgUJBQAAAA==.Halten:BAAALgAECgkJBwAAAA==.Happyboy:BAABLgAECn8fAAQPAAYJjh8gJwAUAgAPAAYJjh8gJwAUAgAOAAYJ+Bv0FwCLAQACAAEJ0BxwQgBSAAABLgAFFAgJEQAQAFcUAA==.Hardrockcafe:BAAALgADCgYJAwAAAA==.Harfu:BAAALgAECgIJAgAAAA==.Hartzdrell:BAAALgADCgcJDAAAAA==.Hashirama:BAABLgAFFH8GAAICAAIJOCNDDgDQAAACAAIJOCNDDgDQAAABLgAFFAUJFAAGADMcAA==.',
He='Healmedaddy:BAAALgADCgEJAQAAAA==.Helbrandt:BAAALgAECgMJAwAAAA==.Heldarram:BAAALgAECgkJEQAAAA==.Hemaroid:BAAALgADCgcJBwAAAA==.Heolt:BAEALgADCgUJBQABLgAECgYJBQAEAAAAAA==.Hestia:BAAALgAECgUJBgAAAA==.Hexra:BAACLgAFFH8VAAIiAAUJzB/qDADKAQAiAAUJzB/qDADKAQAuAAQKfx4AAiIACQnIISQFAPoCACIACQnIISQFAPoCAAAA.Heyzus:BAAALgAECgYJCQAAAA==.',
Ho='Honnok:BAAALgAECgQJBAAAAA==.Hoofweaver:BAAALgAECgUJBQAAAA==.Hornyhead:BAAALgAECgQJDQAAAA==.Howard:BAAALgADCgIJAgAAAA==.',
Hr='Hrizul:BAABLgAECn8zAAMYAAkJ5R1sBQCXAgAYAAgJGiFsBQCXAgARAAcJ3Q77mQA+AQAAAA==.',
Ib='Iblameheals:BAAALgADCgMJBAAAAA==.',
Ic='Icebarron:BAAALgAECgYJDQAAAA==.',
Il='Il:BAABLgAECn8iAAISAAkJtx4tIACXAgASAAkJtx4tIACXAgAAAA==.Illisharr:BAAALgADCggJEQAAAA==.Iloveleaf:BAAALgADCgEJAQAAAA==.Ilusive:BAABLgAECn8cAAIFAAgJrhFeNgBcAQAFAAgJrhFeNgBcAQAAAA==.',
Ir='Irazlynaa:BAAALgADCgUJDgAAAA==.Irielyn:BAAALgAECgUJBQAAAA==.Ironblight:BAAALgAECgEJAQAAAA==.Irrah:BAAALgAECgYJDwAAAA==.',
Is='Ishal:BAAALgADCgEJAQAAAA==.',
Ja='Jabar:BAAALgADCgEJAQAAAA==.Jagz:BAABLgAECn87AAMkAAkJ7B3qFgBeAgAkAAgJBR3qFgBeAgAFAAgJ4h2YFwAlAgAAAA==.',
Jh='Jharael:BAAALgADCgUJBwAAAA==.',
Ji='Jia:BAAALgAECgEJAgAAAA==.',
Jo='Jonsi:BAAALgADCgUJBQABLgAECggJFwAWAEgZAA==.',
Ju='Junö:BAAALgAECgEJAQAAAA==.Jursh:BAAALgADCgQJBAAAAA==.',
Ka='Kaelen:BAABLgAECn8XAAINAAcJ3Ru2OwDtAQANAAcJ3Ru2OwDtAQAAAA==.Kaley:BAAALgADCgIJAgAAAA==.Kasuo:BAAALgAECgEJAQAAAA==.Katamine:BAABLgAECn8+AAIDAAgJiB0lEgBDAgADAAgJiB0lEgBDAgAAAA==.Katoz:BAABLgAECn8aAAMcAAgJHx7wOAAZAgAcAAgJHx7wOAAZAgAdAAIJTRYvEgBuAAAAAA==.Kawas:BAAALgAECgYJCQAAAA==.',
Ke='Keydron:BAAALgADCggJDwAAAA==.',
Kh='Khài:BAAALgAECgQJBQAAAA==.',
Ki='Kickit:BAAALgADCgQJBAAAAA==.Kilemall:BAAALgAECgkJAgAAAA==.Killnall:BAABLgAECn8qAAIRAAcJNwjkwAAEAQARAAcJNwjkwAAEAQAAAA==.Kiyohime:BAAALgAECgIJAgAAAA==.',
Kj='Kjadmina:BAAALgADCgUJBAAAAA==.',
Kl='Kladon:BAABLgAECn8gAAIBAAkJJxo9CQDfAQABAAkJJxo9CQDfAQAAAA==.Klozkoth:BAAALgAECgYJBgAAAA==.',
Ko='Konantheduck:BAAALgADCgMJAwABLgAECggJIAAgAPEQAA==.',
Kr='Krystarin:BAABLgAECn8xAAIPAAkJIRfwGgBrAgAPAAkJIRfwGgBrAgAAAA==.Kryx:BAAALgADCgkJEAAAAA==.Kráytos:BAAALgAECgYJCQAAAA==.',
Ky='Kynria:BAAALgAECgIJAwAAAA==.',
La='Lallaure:BAAALgADCgQJBAAAAA==.Lambic:BAAALgAECgQJBAAAAA==.Lanma:BAABLgAECn8XAAIWAAgJSBlBEQBvAgAWAAgJSBlBEQBvAgAAAA==.Larpgodx:BAAALgAECgIJAwAAAA==.Lastoran:BAAALgAECgMJBQAAAA==.Lateralus:BAABLgAECn9HAAIlAAkJWiEgAQD/AgAlAAkJWiEgAQD/AgAAAA==.Launcelot:BAABLgAECn8dAAMgAAcJSCKUHwBUAgAgAAYJ+yKUHwBUAgAhAAQJRB86JQA5AQAAAA==.Laurasecord:BAAALgADCgQJBAAAAA==.Lazymage:BAAALgAECgcJDAAAAA==.',
Le='Leanbeef:BAAALgAECgYJBgAAAA==.Lerath:BAAALgAECggJDQAAAA==.Leshy:BAAALgADCgYJBgAAAA==.',
Li='Liferips:BAAALgAECgUJBQAAAA==.Lights:BAACLgAFFH8LAAIVAAMJ1CGfHwDvAAAVAAMJ1CGfHwDvAAAuAAQKfz8AAxUACQnuJSUCAE4DABUACQnuJSUCAE4DAAgABQmTIN8eANQBAAEuAAUUBQkUAAYAMxwA.Littlezo:BAACLgAFFH8WAAImAAUJcB4yCgBzAQAmAAUJcB4yCgBzAQAuAAQKfy0AAiYACQl0JXIBAEwDACYACQl0JXIBAEwDAAAA.',
Lo='Lockßulbtwo:BAAALgAECgEJAgAAAA==.Lotus:BAABLgAECn8tAAQWAAkJfxb0FgD6AQAWAAkJNBb0FgD6AQAXAAUJHhXUMAA8AQAHAAYJ5wz3OAAFAQAAAA==.',
Lt='Ltrnck:BAAALgADCgIJAgAAAA==.',
Lu='Lu:BAAALgADCgEJAQAAAA==.Luckbound:BAAALgAECgEJAQABLgAFFAgJEQAQAFcUAA==.Luthonys:BAAALgADCgEJAQAAAA==.',
Ma='Magond:BAAALgAECgIJAgAAAA==.Maiko:BAAALgADCgMJAwAAAA==.Makoha:BAABLgAECn89AAMOAAkJDhHfGACCAQAOAAkJDhHfGACCAQACAAEJwA7BUQAwAAAAAA==.Makpriest:BAAALgAECgYJEgAAAA==.Malakaii:BAABLgAECn8cAAMMAAgJexEYDAAEAgAMAAgJQREYDAAEAgAFAAYJrhLKQgA+AQAAAA==.Margaes:BAAALgADCgEJAgAAAA==.Mariahh:BAAALgADCgEJAQAAAA==.Masherevo:BAAALgAFFAQJBAABLgAFFAQJDAAFAMMRAA==.Masherkillu:BAACLgAFFH8MAAIFAAQJwxFhIgALAQAFAAQJwxFhIgALAQAuAAQKfygAAgUACQllGCgVADwCAAUACQllGCgVADwCAAAA.Masherpally:BAACLgAFFH8KAAMRAAMJMQkIdgDCAAARAAMJMQkIdgDCAAAYAAEJPgXNGAAvAAAuAAQKfykAAxEACQkZHB4YALACABEACQkZHB4YALACABgAAwktDjo+AGEAAAEuAAUUBAkMAAUAwxEA.Maxdeath:BAABLgAECn8bAAIJAAkJpQ5OgADQAQAJAAkJpQ5OgADQAQAAAA==.Maztajake:BAABLgAECn8WAAIDAAgJvR5dEQBNAgADAAgJvR5dEQBNAgAAAA==.Mazyjake:BAAALgAECgcJCQABLgAECggJFgADAL0eAA==.Mazzyjake:BAAALgAECgUJBQABLgAECggJFgADAL0eAA==.',
Me='Meadowlark:BAAALgAECgYJBgABLgAFFAQJDQAPAKQXAA==.Medorh:BAAALgADCgYJBgAAAA==.Melchizedic:BAAALgAECgQJDwAAAA==.Merily:BAAALgADCgQJBAAAAA==.',
Mi='Mikeytott:BAAALgADCgQJBQAAAA==.Minnie:BAAALgAECgEJAQABLgAECgkJIQAGAPUZAA==.',
Mo='Mohgmoment:BAAALgADCgYJBgAAAA==.Moonfare:BAAALgADCgEJAgAAAA==.Mordacity:BAEBLgAECn89AAInAAkJtQeQEQAwAQAnAAkJtQeQEQAwAQAAAA==.',
Mu='Muris:BAAALgAECgQJBAAAAA==.',
['Mä']='Määt:BAAALgADCgIJAgAAAA==.',
Na='Nardo:BAAALgAECgEJAQAAAA==.',
Ne='Necrot:BAAALgAECgEJAQAAAA==.',
Ng='Nghtíy:BAABLgAECn8aAAIcAAYJQBP4uAAEAQAcAAYJQBP4uAAEAQAAAA==.',
Ni='Nixa:BAAALgADCgUJBQAAAA==.',
No='Nocturnüs:BAABLgAECn8vAAIVAAkJuhKSGQD4AQAVAAkJuhKSGQD4AQAAAA==.Noh:BAAALgAECgIJAgAAAA==.Nordikmage:BAABLgAECn8jAAMJAAkJAhRaPwAcAgAJAAkJAhRaPwAcAgAfAAEJPwVSIAAuAAAAAA==.Nort:BAAALgADCgEJAgAAAA==.Nov:BAAALgADCgMJAwAAAA==.',
['Nê']='Nêcrömane:BAAALgAECgUJCAAAAA==.',
['Në']='Nëssa:BAAALgAECgIJAgABLgAECgYJCgAEAAAAAA==.',
Oh='Ohtheirone:BAAALgADCgYJBgAAAA==.Ohtheironey:BAAALgADCgUJBQAAAA==.Ohtheironie:BAAALgADCgYJBgAAAA==.',
On='Ondereth:BAAALgAECgYJDgAAAA==.Onthehouse:BAAALgAECgYJDgAAAA==.',
Or='Orid:BAAALgADCgcJBwAAAA==.Orvannan:BAAALgADCgQJCAAAAA==.',
Pa='Pacho:BAAALgADCgUJBQAAAA==.Palimorea:BAEALgADCggJFwABLgAECgYJBQAEAAAAAA==.Pallypower:BAAALgAECgYJBgAAAA==.',
Pi='Piercey:BAACLgAFFH8RAAMQAAgJVxTfBgDNAQAQAAgJVxTfBgDNAQAhAAEJOhBNPQBLAAAuAAQKfysAAxAACAntHr4KAGUCABAACAntHr4KAGUCACEAAQn4H/lfAF0AAAAA.Pinkylove:BAABLgAECn8eAAIPAAgJ8iBODADcAgAPAAgJ8iBODADcAgAAAA==.',
Pr='Proera:BAAALgAECgcJCQAAAA==.Promathia:BAACLgAFFH8eAAQRAAUJ8R8gIgB4AQARAAUJ8R8gIgB4AQAYAAMJ9iDPBgANAQAbAAQJ3AzzJwDeAAAuAAQKf08ABBEACQnLJvwAAIoDABEACQnLJvwAAIoDABsABAkXCCVuAMIAABgAAQkDJaY8AGcAAAAA.Pross:BAAALgAECgUJDAABLgAECgkJLgARANQcAA==.',
Ps='Psychopath:BAABLgAECn8aAAMZAAYJohYVLACeAQAZAAYJohYVLACeAQAaAAEJtwYkIAAyAAAAAA==.',
Pu='Puff:BAAALgAECggJDQAAAA==.',
Qu='Quicksotaka:BAAALgADCgcJBgAAAA==.',
Ra='Raenori:BAAALgADCgYJBgAAAA==.Ragnarolk:BAAALgAECgIJAgAAAA==.Rahveyn:BAAALgAECgIJAgAAAA==.Raiyuden:BAAALgAECgEJAQAAAA==.Randydaytona:BAAALgAECgYJCwAAAA==.Rangërdangër:BAACLgAFFH8PAAINAAUJzgaEUwD4AAANAAUJzgaEUwD4AAAuAAQKfxgAAg0ACQmTGQo1ANoBAA0ACQmTGQo1ANoBAAAA.Rat:BAABLgAECn8jAAIVAAkJSSBzBABOAwAVAAkJSSBzBABOAwAAAA==.',
Re='Rectumus:BAAALgADCggJEwAAAA==.Redrouges:BAACLgAFFH8HAAIZAAMJ3xNZIwABAQAZAAMJ3xNZIwABAQAuAAQKfykAAhkACQkNIT0EAPkCABkACQkNIT0EAPkCAAAA.Redwood:BAAALgAECgMJBQAAAA==.Renvskadoosh:BAAALgADCgkJGQABLgAECgcJHgAkAF0JAA==.Revhero:BAAALgAECgEJAQAAAA==.Rexpanda:BAABLgAECn8YAAIHAAYJ1R2CGgDmAQAHAAYJ1R2CGgDmAQAAAA==.',
Ro='Roguetheholy:BAAALgAECgkJBQAAAA==.Ross:BAEALgADCgEJAQABLgAFFAYJFAAHAAsmAA==.Rotawnda:BAAALgAECgYJBwAAAA==.Rotlord:BAAALgAECgYJCgAAAA==.',
Ru='Ruckus:BAAALgAECgYJCwAAAA==.Rumble:BAAALgAECgEJAQAAAA==.Rumrootbeer:BAAALgADCgIJAQAAAA==.',
Ry='Rynn:BAAALgADCgIJAgAAAA==.',
['Rë']='Rëkz:BAAALgAECgMJAwAAAA==.',
['Rì']='Rìppér:BAAALgAECgEJAQABLgAFFAUJFQAiAMwfAA==.',
Sa='Sanelle:BAAALgADCgkJCQABLgAECgkJKwAIABQgAA==.Sapoude:BAAALgAECgcJBwAAAA==.Sarang:BAAALgADCgcJBwAAAA==.Sarrsaras:BAAALgAECgYJCAABLgAECgcJGAASANQbAA==.',
Sc='Scale:BAAALgAECgQJBAAAAA==.',
Se='Seaursus:BAAALgAECgMJCAAAAA==.Seerblade:BAAALgADCgcJCgABLgAECgYJCwAEAAAAAA==.Sekaiju:BAAALgAECgQJBgAAAA==.Selakin:BAAALgADCgIJAgAAAA==.',
Sh='Shadowbann:BAAALgAECgYJCwAAAA==.Shadowrunner:BAAALgAECgEJAQAAAA==.Shammydavis:BAAALgADCgEJAQAAAA==.Shamwich:BAAALgAECgkJEgAAAA==.Shandroz:BAAALgAECgUJBQAAAA==.Shaori:BAAALgADCgMJBAAAAA==.Shortzo:BAAALgAECgcJCwABLgAFFAUJFgAmAHAeAA==.Shrkbait:BAAALgAECgUJCgAAAA==.',
Si='Sikozu:BAAALgAECgIJAwAAAA==.',
Sk='Skeezicks:BAAALgADCgUJBQAAAA==.Skidoosh:BAAALgAECgEJAwAAAA==.Skullcleaver:BAAALgADCgcJFAAAAA==.',
Sl='Slycc:BAAALgAECgMJAwAAAA==.',
Sm='Smackerr:BAAALgADCgUJBgAAAA==.',
Sn='Sneakay:BAABLgAFFH8GAAIeAAMJqQVrDwC2AAAeAAMJqQVrDwC2AAAAAA==.Sneakybiter:BAAALgADCgcJDQAAAA==.',
So='Solei:BAAALgAECgUJBQAAAA==.Southernguy:BAAALgAECgMJBAAAAA==.',
Sp='Spazzies:BAAALgAECgcJEQAAAA==.',
Sq='Squigglybutt:BAABLgAECn82AAMUAAcJkR/NDgB4AgAUAAcJkR/NDgB4AgAIAAUJ3xYDMABcAQAAAA==.',
St='Steelwing:BAAALgAFFAMJAwAAAA==.Stormbeards:BAAALgADCgYJBgAAAA==.Stoutkeg:BAAALgADCgQJAwAAAA==.Strixmonk:BAEALgAFFAIJAwABLgAFFAYJGgAcAC4eAA==.Strrawberry:BAAALgADCgIJAgAAAA==.Stêven:BAAALgAECggJCAAAAA==.Störmî:BAAALgAECgYJBwAAAA==.',
Su='Sungchaluka:BAAALgAECgQJDwAAAA==.',
Sy='Sylvath:BAAALgAECgEJAgAAAA==.',
['Sá']='Sásu:BAAALgADCgkJFQAAAA==.',
Ta='Talsomething:BAAALgAFFAEJAgAAAA==.Talsumthing:BAABLgAFFH8JAAIbAAUJqwTLJQDsAAAbAAUJqwTLJQDsAAAAAA==.Tars:BAAALgAECgYJBgAAAA==.Tats:BAABLgAECn8kAAIRAAgJMB13MwAwAgARAAgJMB13MwAwAgAAAA==.Tatsumâ:BAABLgAECn8YAAIOAAYJlxVYIgA3AQAOAAYJlxVYIgA3AQAAAA==.',
Te='Terraxic:BAAALgAECgYJDAAAAA==.Terthaith:BAABLgAECn8YAAISAAkJKwwoXACJAQASAAkJKwwoXACJAQAAAA==.Tezguin:BAAALgADCgYJDQAAAA==.',
Th='Theedemon:BAAALgAECgQJBAAAAA==.Theironie:BAAALgADCgYJBgAAAA==.Theparttimer:BAAALgADCgEJAQAAAA==.Thiccpie:BAAALgAECgYJCwAAAA==.Throdwran:BAAALgAECgYJDAABLgAECgkJLgARANQcAA==.',
Ti='Timba:BAAALgAECgYJCAAAAA==.Tisaka:BAABLgAECn8aAAIZAAYJAxmZJQDMAQAZAAYJAxmZJQDMAQAAAA==.',
Tl='Tlovexx:BAAALgAFFAEJAQAAAA==.',
To='Tolya:BAAALgAECgEJAQAAAA==.Toohbooh:BAAALgAECgMJBgAAAA==.Totem:BAAALgAECgcJDAAAAA==.',
Tr='Tranqx:BAACLgAFFH8XAAMcAAQJWSYvJgDGAQAcAAQJWSYvJgDGAQAdAAMJiCL0DgAaAQAuAAQKfzkAAx0ACQnpJpwBABoDABwACAm1JlUIAFwDAB0ACAmnJpwBABoDAAAA.Treevlo:BAAALgADCgEJAQAAAA==.Treva:BAABLgAECn8hAAQGAAkJ9RnbHwDYAQAGAAkJ9RnbHwDYAQAlAAQJtAYrLgCoAAAiAAEJZQPfSgAsAAAAAA==.Trizz:BAAALgAFFAEJAQAAAA==.Troctzul:BAAALgADCgEJAwAAAA==.Trollmachine:BAAALgAECgcJDAABLgAECggJFgADAL0eAA==.',
Ts='Tsuchiya:BAAALgAECggJEwAAAA==.',
Tu='Tuts:BAAALgADCgYJDAAAAA==.',
Ty='Tythos:BAAALgADCgYJCwAAAA==.',
Up='Uproar:BAACLgAFFH8LAAIdAAUJOx3UCABYAQAdAAUJOx3UCABYAQAuAAQKfy4AAh0ACQlDJXMBACMDAB0ACQlDJXMBACMDAAAA.',
Va='Vaelira:BAAALgADCgkJCQAAAA==.Vahlfi:BAACLgAFFH8GAAIKAAMJviBOawCuAAAKAAMJviBOawCuAAAuAAQKfxwABAoACQljJAoPAMkCAAoACQljJAoPAMkCAAsAAQm6IhtVAGEAACcAAgkTEU80ADAAAAEuAAUUBgkZABoAoSUA.Valemon:BAAALgAFFAIJAwAAAA==.Valeskogr:BAABLgAECn8dAAQNAAkJAg6iXwCDAQANAAgJZw6iXwCDAQAmAAcJjQjeFAB6AQABAAgJmAN0UAAMAQAAAA==.Valffi:BAAALgAFFAEJAQABLgAFFAYJGQAaAKElAA==.Varoth:BAAALgAECgEJAQAAAA==.Varus:BAAALgAECgYJCQAAAA==.',
Ve='Velisá:BAAALgAECgIJAgAAAA==.Vengefulmilk:BAAALgAECgUJDgAAAA==.Venture:BAAALgADCgkJIgAAAA==.Vergo:BAAALgADCgEJAQAAAA==.Vescovo:BAABLgAECn8rAAQIAAkJFCBcBgAZAwAIAAkJFCBcBgAZAwAVAAUJ0RXMQQAGAQAUAAEJrh+jdABWAAAAAA==.',
Vi='Virde:BAAALgADCgMJAwAAAA==.',
Vl='Vll:BAABLgAECn8iAAILAAgJ7iJ4BwC3AgALAAgJ7iJ4BwC3AgABLgAECgkJJwANALUbAA==.',
Vo='Volkihar:BAAALgAFFAIJAwAAAA==.Vordt:BAAALgAECgIJBwAAAA==.',
Wa='Wardaorm:BAABLgAECn8fAAIgAAYJDg5BTAAUAQAgAAYJDg5BTAAUAQABLgAECgkJLgARANQcAA==.Warkinz:BAAALgADCgQJBQAAAA==.Warlin:BAAALgAECgEJAQAAAA==.',
We='Welordron:BAAALgADCgEJAQAAAA==.',
Wi='Willohh:BAAALgAECgQJBAAAAA==.Winden:BAABLgAECn8WAAIMAAYJhhvAFwBHAQAMAAYJhhvAFwBHAQAAAA==.Wingback:BAAALgAECgkJBQAAAA==.Wiz:BAAALgAECgYJDgAAAA==.',
Wp='Wphoenix:BAAALgAECgQJBAAAAA==.',
Wr='Wrizz:BAAALgADCgYJCAAAAA==.',
Wt='Wtfsteve:BAAALgADCgUJBQABLgAECggJFwAWAEgZAA==.',
Xa='Xadrai:BAAALgAECgYJCwAAAA==.',
Xe='Xeplin:BAAALgAECgUJCQAAAA==.',
Xh='Xhenshini:BAACLgAFFH8JAAMGAAUJYAp9PADSAAAGAAUJYAp9PADSAAAlAAEJtwbMCgBPAAAuAAQKf0IAAwYACQlOIeYFAPwCAAYACQkcIeYFAPwCACUACAmqGjEJAE4CAAAA.',
Xk='Xkrin:BAAALgAECgEJAQAAAA==.',
Ye='Yeonguo:BAAALgAECgYJDgAAAA==.',
Yu='Yums:BAAALgADCgcJCwAAAA==.',
Za='Zalethe:BAAALgAECgMJAwAAAA==.Zalliel:BAAALgADCggJCAAAAA==.Zalman:BAAALgAECgMJBQAAAA==.Zaphíel:BAAALgADCgcJBwABLgAECgkJGAASACsMAA==.Zaran:BAABLgAECn8UAAIRAAgJOhACcwCFAQARAAgJOhACcwCFAQAAAA==.',
Ze='Zeninnaoya:BAABLgAECn8fAAMhAAkJuSD6AABaAwAhAAkJ3B36AABaAwAgAAcJISaFDgDgAgAAAA==.',
['Âu']='Âura:BAAALgADCgEJAQAAAA==.',
['Är']='Ärc:BAAALgADCgMJAwAAAA==.',
['Ës']='Ësme:BAAALgADCgkJCwAAAA==.',
['Óð']='Óðin:BAAALgAECgMJAwAAAA==.',
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
