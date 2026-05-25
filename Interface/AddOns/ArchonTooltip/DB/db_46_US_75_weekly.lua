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

local lookup = {'Hunter-Marksmanship','Druid-Feral','Druid-Balance','Unknown-Unknown','Shaman-Elemental','Evoker-Augmentation','Monk-Mistweaver','Mage-Frost','DemonHunter-Devourer','DemonHunter-Havoc','Shaman-Enhancement','Hunter-BeastMastery','Druid-Restoration','Druid-Guardian','Paladin-Retribution','Warlock-Demonology','DeathKnight-Blood','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','Paladin-Protection','Warrior-Protection','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Destruction','Mage-Arcane','Monk-Windwalker','Warrior-Fury','Warrior-Arms','Evoker-Preservation','Priest-Holy','Warlock-Affliction','Shaman-Restoration','Evoker-Devastation','Priest-Discipline','Hunter-Survival','Monk-Brewmaster','DemonHunter-Vengeance',}
local provider = {region='US',realm="Drak'thul",name='US',type='weekly',zone=46,date='2026-05-23',data={Ad='Ador:BAAALgADCgMJAwAAAA==.',
Ae='Aeladrel:BAAALgADCggJCAAAAA==.',
Ak='Akirie:BAABLgAECn8aAAIBAAYJDxcDEQAlAQABAAYJDxcDEQAlAQAAAA==.Akumu:BAABLgAECn8eAAMCAAkJrRtVBQC5AgACAAkJrRtVBQC5AgADAAEJAACMkQAAAAABLgAFFAMJAwAEAAAAAA==.Akumua:BAAALgAECgQJBAABLgAFFAMJAwAEAAAAAA==.',
Al='Alangi:BAABLgAECn8ZAAIFAAcJjgwTPwAHAQAFAAcJjgwTPwAHAQABLgAECgkJQAAGAE4hAA==.Albinah:BAABLgAECn8dAAIHAAcJAB2YFwAeAgAHAAcJAB2YFwAeAgAAAA==.Albsli:BAAALgADCgIJAgAAAA==.Albsygos:BAAALgADCgQJBAAAAA==.Albz:BAAALgADCgkJHAAAAA==.Albzap:BAAALgADCgMJAwAAAA==.Albzley:BAAALgAECgcJCwAAAA==.Albzu:BAAALgAECgUJBQAAAA==.Aldien:BAABLgAECn8YAAIIAAYJ4AZbwQDqAAAIAAYJ4AZbwQDqAAAAAA==.Aliphar:BAAALgADCgEJAQAAAA==.Allaria:BAAALgADCgIJAgAAAA==.',
Ao='Aoe:BAACLgAFFH8QAAIJAAQJWxK4LwArAQAJAAQJWxK4LwArAQAuAAQKfxwAAgkACQnrGmwUAIMCAAkACQnrGmwUAIMCAAEuAAUUBgkKAAoASQ8A.',
Ar='Arienna:BAAALgAECgMJAwAAAA==.Arteñ:BAAALgAECgUJCQAAAA==.',
As='Ashrak:BAABLgAECn8jAAILAAcJARPxDwB3AQALAAcJARPxDwB3AQAAAA==.',
Av='Averroes:BAABLgAECn86AAIMAAkJ0BeKGwBXAgAMAAkJ0BeKGwBXAgAAAA==.',
Aw='Awa:BAABLgAECn8XAAIGAAYJ9QsCSADhAAAGAAYJ9QsCSADhAAABLgAFFAYJCgAKAEkPAA==.Awee:BAACLgAFFH8KAAIKAAYJSQ+QBwBPAQAKAAYJSQ+QBwBPAQAuAAQKf0cAAgoACQkJInQDAPcCAAoACQkJInQDAPcCAAAA.Awi:BAAALgADCgUJBQABLgAFFAYJCgAKAEkPAA==.Awo:BAACLgAFFH8IAAMNAAQJfRjjGABaAQANAAQJfRjjGABaAQAOAAEJxwNnKAArAAAuAAQKfzYABA0ACAlmJa8EAFgDAA0ACAlmJa8EAFgDAA4ACAkxHi8HAE8CAAIABgmIFkIUAG4BAAAA.Awoo:BAAALgAECgYJBwABLgAFFAQJCAANAH0YAA==.',
Ay='Aylen:BAABLgAECn8eAAIPAAkJ6A4gVgCpAQAPAAkJ6A4gVgCpAQAAAA==.',
Ba='Babsvilla:BAAALgAECgUJCwAAAA==.Badmagi:BAAALgAECgEJAQAAAA==.Bahldrahg:BAAALgAECgMJAwAAAA==.Baki:BAACLgAFFH8LAAIGAAQJ3xdtHAAuAQAGAAQJ3xdtHAAuAQAuAAQKfxkAAgYACQmsJEACAFADAAYACQmsJEACAFADAAAA.Banegrim:BAABLgAECn8tAAIQAAgJAw4aXgBvAQAQAAgJAw4aXgBvAQAAAA==.Barnbirt:BAAALgAECgEJAQAAAA==.Barron:BAAALgAECgIJAgAAAA==.Barronthee:BAAALgAECgIJAgAAAA==.Battlecat:BAABLgAECn8ZAAIIAAgJkBKDWwCvAQAIAAgJkBKDWwCvAQAAAA==.',
Be='Beelzebubx:BAAALgAECgQJBAABLgAFFAMJAwAEAAAAAA==.Belysiuh:BAAALgAECgMJAwAAAA==.',
Bl='Blackdaisydr:BAAALgADCgcJDQABLgAECgYJCwAEAAAAAA==.Blindwalker:BAABLgAECn8hAAIRAAkJeQ2tIQAWAQARAAkJeQ2tIQAWAQAAAA==.Blissfuleigh:BAAALgAECgIJAwAAAA==.Bloodbarron:BAAALgAECgYJCgAAAA==.',
Bo='Boldius:BAAALgADCgQJBAABLgAECgUJBQAEAAAAAA==.Bookchin:BAAALgADCgEJAQAAAA==.',
Br='Bragdand:BAEALgADCgkJHAAAAA==.Braistlin:BAAALgADCgIJAgABLgAECgUJBQAEAAAAAA==.Bred:BAAALgADCgcJBwAAAA==.Brewfest:BAAALgADCgMJBgAAAA==.Briarthorn:BAAALgAECgYJBgAAAA==.Brielan:BAABLgAECn8UAAMSAAYJohYVLACeAQASAAYJohYVLACeAQATAAEJtwYkIAAyAAAAAA==.',
Bu='Bubblegump:BAAALgAECgIJAgAAAA==.',
Ca='Cadillacbob:BAAALgAECgIJAwAAAA==.Calon:BAAALgAECgQJBQAAAA==.Cantseedizz:BAAALgADCgMJAwAAAA==.Castigate:BAACLgAFFH8dAAIUAAYJSyE0BADzAQAUAAYJSyE0BADzAQAuAAQKfysAAhQACAk7IUIKAN4CABQACAk7IUIKAN4CAAAA.',
Ce='Cederek:BAAALgADCgIJAgAAAA==.Ceresarian:BAAALgADCgMJAwAAAA==.',
Ch='Chancho:BAAALgAECgYJCQABLgAECgkJNQAOAA4RAA==.Cheesekitten:BAAALgADCgEJAQABLgAECgkJQQAPAMImAA==.Cheesemonk:BAAALgADCgkJMQABLgAECgkJQQAPAMImAA==.Cheesepally:BAABLgAECn9BAAIPAAkJwiarAACOAwAPAAkJwiarAACOAwAAAA==.Cheesewhelp:BAAALgADCgcJBwAAAA==.Chikoung:BAAALgADCgUJBQAAAA==.Chudmourne:BAAALgAECgUJBQAAAA==.',
Cl='Cloud:BAABLgAECn8cAAMVAAkJUSK3AgDVAgAVAAgJFCS3AgDVAgAPAAIJfhVoBgF+AAAAAA==.',
Co='Coderictond:BAAALgADCgQJBgAAAA==.Cogpally:BAAALgADCggJCAAAAA==.',
Cr='Crysa:BAAALgADCgYJBgAAAA==.',
Cy='Cygnus:BAABLgAECn8nAAMSAAcJYxPaHACFAQASAAcJYxPaHACFAQATAAUJfwbsEQDhAAAAAA==.Cylla:BAABLgAECn8YAAIMAAcJBCMmHQBNAgAMAAcJBCMmHQBNAgABLgAFFAQJEQAVAOseAA==.',
Da='Daddywarbuks:BAAALgAECgUJBgAAAA==.Dagin:BAABLgAECn8oAAIPAAkJtBv0GwB/AgAPAAkJtBv0GwB/AgAAAA==.Dalarenaric:BAAALgADCgcJDAAAAA==.Dalt:BAAALgAFFAEJAQAAAA==.Daltonator:BAAALgADCgMJAwAAAA==.Dantemore:BAABLgAECn8aAAICAAcJlxcaDgCfAQACAAcJlxcaDgCfAQAAAA==.Daorcy:BAAALgADCggJDgAAAA==.Dartherd:BAABLgAECn8kAAIWAAcJiRhKEwCQAQAWAAcJiRhKEwCQAQAAAA==.Dawnotheholy:BAABLgAECn9BAAMXAAkJuQ3nJgCsAQAXAAkJuQ3nJgCsAQAPAAcJJBAslgAnAQAAAA==.',
De='Deathstar:BAACLgAFFH8kAAMYAAYJPh+nDgDxAQAYAAUJPh+nDgDxAQARAAEJAABTPgAAAAAuAAQKfy8AAxgACQkSJLEIABADABgACQkSJLEIABADABkAAwl+DQISAHEAAAAA.Demonbunz:BAAALgADCgUJBwAAAA==.Derregar:BAABLgAECn8cAAMQAAcJFx4sRgCxAQAQAAcJpx0sRgCxAQAaAAIJ0RL1SACTAAAAAA==.Dezamius:BAAALgADCgkJCQABLgAECgkJQAAGAE4hAA==.',
Di='Dibella:BAAALgADCgYJAwAAAA==.Dirtydrago:BAAALgADCgUJBgABLgAECgUJBQAEAAAAAA==.Dirtymon:BAAALgADCgMJAwABLgAECgUJBQAEAAAAAA==.',
Dk='Dkfatality:BAACLgAFFH8NAAMZAAMJsR/eCgABAQAZAAMJsR/eCgABAQAYAAEJow5XVABPAAAuAAQKfywAAxkACQmSIxIBABkDABkACQmSIxIBABkDABgABgl/IQ5dANsBAAAA.',
Dl='Dlord:BAAALgADCgYJCAAAAA==.',
Do='Dock:BAAALgAECgQJCQAAAA==.Dominhoes:BAABLgAECn8XAAIIAAYJlhZ5ggBWAQAIAAYJlhZ5ggBWAQAAAA==.Dondon:BAAALgADCgcJCQAAAA==.Doontless:BAAALgAECgYJEQAAAA==.Doyouknow:BAAALgAECgMJAwAAAA==.',
Dr='Draig:BAABLgAECn8UAAMIAAcJuAkkowAbAQAIAAcJuggkowAbAQAbAAIJWwe+GQBKAAAAAA==.Dratini:BAAALgADCggJBwABLgAECggJFwAcAEgZAA==.Drozigg:BAAALgADCgYJCQAAAA==.',
Du='Duckfury:BAABLgAECn8YAAIdAAcJgAy6OAA+AQAdAAcJgAy6OAA+AQAAAA==.Duckmourne:BAAALgADCgEJAQAAAA==.Dummy:BAAALgADCgYJBgAAAA==.Dunzoboom:BAAALgADCgcJCwAAAA==.Dunzö:BAAALgADCgYJBgAAAA==.',
Eb='Ebonhèart:BAABLgAECn8ZAAMeAAgJygt2HQBCAQAeAAgJygt2HQBCAQAdAAEJwwUBqgA0AAAAAA==.',
Ec='Ecliptic:BAAALgAECgQJDQAAAA==.',
Eg='Eggle:BAAALgADCgIJAgAAAA==.',
Ei='Eisenheim:BAAALgADCgIJAgAAAA==.',
El='Electronvolt:BAABLgAECn8ZAAIfAAgJrBVqCwD+AQAfAAgJrBVqCwD+AQAAAA==.Eleidie:BAAALgADCgEJAQAAAA==.Elia:BAAALgAECgEJAQAAAA==.',
Ev='Evilyne:BAAALgADCgUJBwAAAA==.',
Ex='Exíled:BAAALgAECgEJAQAAAA==.',
Fa='Fallenlegion:BAAALgADCgcJBwAAAA==.Fartwizard:BAAALgAECgMJBQAAAA==.',
Fe='Felskerri:BAAALgADCgYJBgAAAA==.Fenus:BAAALgADCgIJAgAAAA==.',
Fi='Firebelly:BAAALgAECgMJAwAAAA==.Firerage:BAAALgADCgcJDwABLgAECgIJAwAEAAAAAA==.',
Fl='Flacidmonkey:BAAALgAECgcJDwAAAA==.Flufflenuzs:BAAALgAECgEJAQAAAA==.',
Fo='Fors:BAAALgAECgQJBAAAAA==.Forsäken:BAABLgAECn8VAAIIAAYJoRW0pwCKAQAIAAYJoRW0pwCKAQAAAA==.Forumangel:BAAALgADCgYJCQAAAA==.',
Fr='Freya:BAAALgADCgUJBQAAAA==.Fria:BAAALgAECgcJCAAAAA==.Frombehind:BAAALgAECgcJEgABLgAFFAYJHgAYAD4eAA==.',
Fu='Fubu:BAAALgAECgIJAgAAAA==.',
Ga='Gabenson:BAAALgADCgQJBAAAAA==.',
Gl='Glizzylatte:BAAALgADCgYJBgABLgAECgYJCwAEAAAAAA==.Gloomy:BAABLgAECn8iAAIgAAcJmyEJDAB+AgAgAAcJmyEJDAB+AgAAAA==.',
Gr='Grandizzle:BAAALgAECgYJDQAAAA==.Grandore:BAAALgAECgEJAQAAAA==.',
Gu='Gumbi:BAAALgAECgIJAgAAAA==.Gumgum:BAACLgAFFH8NAAIhAAQJliWaAAC7AQAhAAQJliWaAAC7AQAuAAQKfzYAAiEACAlYJg0BAP8CACEACAlYJg0BAP8CAAAA.Guruprime:BAAALgADCgYJCAAAAA==.',
Gw='Gwalla:BAAALgADCgkJEAABLgAECgMJBQAEAAAAAA==.',
Ha='Hagniy:BAABLgAECn9LAAIXAAgJfh/GCwCsAgAXAAgJfh/GCwCsAgAAAA==.Hakunamatata:BAAALgADCgUJBQAAAA==.Halten:BAAALgAECgkJBwAAAA==.Happyboy:BAABLgAECn8eAAQNAAYJjh/aIQAWAgANAAYJjh/aIQAWAgAOAAYJ+Bv6EQCRAQACAAEJoBMlOgA8AAABLgAFFAQJCAANAH0YAA==.Hardrockcafe:BAAALgADCgYJAwAAAA==.Harfu:BAAALgAECgIJAgAAAA==.Hartzdrell:BAAALgADCgcJDAAAAA==.',
He='Healmedaddy:BAAALgADCgEJAQAAAA==.Helbrandt:BAAALgAECgMJAwAAAA==.Heldarram:BAAALgAECgkJEQAAAA==.Hemaroid:BAAALgADCgcJBwAAAA==.Heolt:BAEALgADCgUJBQABLgADCgkJHAAEAAAAAA==.Hestia:BAAALgAECgUJBgAAAA==.Hexra:BAACLgAFFH8NAAIfAAQJriARDgB+AQAfAAQJriARDgB+AQAuAAQKfx4AAh8ACQnIISQFAPoCAB8ACQnIISQFAPoCAAAA.Heyzus:BAAALgAECgYJCQAAAA==.',
Ho='Honnok:BAAALgAECgQJBAAAAA==.Hoofweaver:BAAALgAECgUJBQAAAA==.Hornyhead:BAAALgAECgQJDQAAAA==.Howard:BAAALgADCgIJAgAAAA==.',
Hr='Hrizul:BAABLgAECn8mAAMVAAkJ9hm2CgDyAQAVAAgJmxy2CgDyAQAPAAcJ3Q5zfQBTAQAAAA==.',
Ib='Iblameheals:BAAALgADCgMJBAAAAA==.',
Ic='Icebarron:BAAALgAECgYJDAAAAA==.',
Il='Il:BAABLgAECn8iAAIQAAkJtx4tIACXAgAQAAkJtx4tIACXAgAAAA==.Illisharr:BAAALgADCggJEQAAAA==.Iloveleaf:BAAALgADCgEJAQAAAA==.Ilusive:BAABLgAECn8cAAIFAAgJrhEyLABoAQAFAAgJrhEyLABoAQAAAA==.',
Ir='Irazlynaa:BAAALgADCgUJDgAAAA==.Irielyn:BAAALgADCgcJBwAAAA==.Ironblight:BAAALgAECgEJAQAAAA==.Irrah:BAAALgAECgYJDwAAAA==.',
Is='Ishal:BAAALgADCgEJAQAAAA==.',
Ja='Jabar:BAAALgADCgEJAQAAAA==.Jagz:BAABLgAECn84AAMiAAkJdx3qFgBeAgAiAAgJghzqFgBeAgAFAAgJKR0fFAAdAgAAAA==.',
Jh='Jharael:BAAALgADCgUJBwAAAA==.',
Ji='Jia:BAAALgAECgEJAgAAAA==.',
Jo='Jonsi:BAAALgADCgUJBQABLgAECggJFwAcAEgZAA==.',
Ju='Junö:BAAALgAECgEJAQAAAA==.Jursh:BAAALgADCgQJBAAAAA==.',
Ka='Kaelen:BAAALgAECgYJDgAAAA==.Kaley:BAAALgADCgIJAgAAAA==.Katamine:BAABLgAECn8yAAIDAAgJaBpPFwDoAQADAAgJaBpPFwDoAQAAAA==.Katoz:BAABLgAECn8XAAMYAAgJFx5iNAAKAgAYAAgJFx5iNAAKAgAZAAIJTRYvEgBuAAAAAA==.Kawas:BAAALgAECgYJCQAAAA==.',
Ke='Keydron:BAAALgADCggJDwAAAA==.',
Kh='Khài:BAAALgAECgQJBQAAAA==.',
Ki='Kickit:BAAALgADCgQJBAAAAA==.Kilemall:BAAALgAECggJAgAAAA==.Killnall:BAABLgAECn8eAAIPAAYJMAeGxgDbAAAPAAYJMAeGxgDbAAAAAA==.Kiyohime:BAAALgAECgIJAgAAAA==.',
Kj='Kjadmina:BAAALgADCgUJBAAAAA==.',
Kl='Kladon:BAABLgAECn8gAAIBAAkJJxpABwDwAQABAAkJJxpABwDwAQAAAA==.Klozkoth:BAAALgAECgYJBgAAAA==.',
Ko='Konantheduck:BAAALgADCgMJAwABLgAECgcJGAAdAIAMAA==.',
Kr='Krystarin:BAABLgAECn8oAAINAAgJpRfwHgArAgANAAgJpRfwHgArAgAAAA==.Kryx:BAAALgADCgkJEAAAAA==.Kráytos:BAAALgAECgUJCAAAAA==.',
Ky='Kynria:BAAALgAECgIJAwAAAA==.',
La='Lallaure:BAAALgADCgQJBAAAAA==.Lambic:BAAALgAECgQJBAAAAA==.Lanma:BAABLgAECn8XAAIcAAgJSBlBEQBvAgAcAAgJSBlBEQBvAgAAAA==.Larpgodx:BAAALgAECgIJAwAAAA==.Lastoran:BAAALgAECgMJBQAAAA==.Lateralus:BAABLgAECn8+AAIjAAkJkCDvAAD9AgAjAAkJkCDvAAD9AgAAAA==.Launcelot:BAABLgAECn8dAAMdAAcJSCKUHwBUAgAdAAYJ+yKUHwBUAgAeAAQJRB9CHQBEAQAAAA==.Laurasecord:BAAALgADCgQJBAAAAA==.Lazymage:BAAALgAECgcJDAAAAA==.',
Le='Leanbeef:BAAALgAECgYJBgAAAA==.Lerath:BAAALgAECgMJAwAAAA==.Leshy:BAAALgADCgYJBgAAAA==.',
Li='Lights:BAACLgAFFH8LAAIUAAMJ1CHZFwAHAQAUAAMJ1CHZFwAHAQAuAAQKfz8AAxQACQnuJWEBAFwDABQACQnuJWEBAFwDACQABQmTIEkZANoBAAEuAAUUBAkLAAYA3xcA.Littlezo:BAACLgAFFH8MAAIlAAQJnRYWDABMAQAlAAQJnRYWDABMAQAuAAQKfy0AAiUACQl0Jc8AAFwDACUACQl0Jc8AAFwDAAAA.',
Lo='Lotus:BAABLgAECn8tAAQcAAkJfxaSEgAGAgAcAAkJNBaSEgAGAgAmAAUJHhX2KgBBAQAHAAYJ5wz3OAAFAQAAAA==.',
Lt='Ltrnck:BAAALgADCgIJAgAAAA==.',
Lu='Lu:BAAALgADCgEJAQAAAA==.Luckbound:BAAALgAECgEJAQABLgAFFAQJCAANAH0YAA==.Luthonys:BAAALgADCgEJAQAAAA==.',
Ma='Magond:BAAALgAECgIJAgAAAA==.Makoha:BAABLgAECn81AAMOAAkJDhFJEgCOAQAOAAkJDhFJEgCOAQACAAEJwA4IPAA2AAAAAA==.Makpriest:BAAALgAECgYJBwAAAA==.Malakaii:BAABLgAECn8cAAMLAAgJexEYDAAEAgALAAgJQREYDAAEAgAFAAYJrhLKQgA+AQAAAA==.Malrec:BAAALgAECgEJAQAAAA==.Mariahh:BAAALgADCgEJAQAAAA==.Masherkillu:BAACLgAFFH8GAAIFAAQJTgmnHwD8AAAFAAQJTgmnHwD8AAAuAAQKfyMAAgUACAnrGZ8WAAUCAAUACAnrGZ8WAAUCAAAA.Masherpally:BAABLgAECn8cAAMPAAgJyBrhLAArAgAPAAgJyBrhLAArAgAVAAIJ9wdpRwAlAAAAAA==.Maxdeath:BAABLgAECn8bAAIIAAkJpQ5OgADQAQAIAAkJpQ5OgADQAQAAAA==.Maztajake:BAABLgAECn8VAAIDAAcJ1h2gFwDkAQADAAcJ1h2gFwDkAQAAAA==.Mazyjake:BAAALgAECgIJAgABLgAECgcJFQADANYdAA==.Mazzyjake:BAAALgAECgQJBAABLgAECgcJFQADANYdAA==.',
Me='Medorh:BAAALgADCgYJBgAAAA==.Melchizedic:BAAALgAECgMJBAAAAA==.Merily:BAAALgADCgQJBAAAAA==.',
Mi='Mikeytott:BAAALgADCgQJBQAAAA==.Minnie:BAAALgAECgEJAQABLgAECgkJIQAGAPUZAA==.',
Mo='Mohgmoment:BAAALgADCgYJBgAAAA==.Moonfare:BAAALgADCgEJAgAAAA==.Mordacity:BAEBLgAECn8kAAInAAcJ2wdvFADeAAAnAAcJ2wdvFADeAAAAAA==.',
Mu='Muris:BAAALgAECgQJBAAAAA==.',
['Mä']='Määt:BAAALgADCgIJAgAAAA==.',
Na='Nardo:BAAALgAECgEJAQAAAA==.',
Ne='Necro:BAAALgAECgMJBQAAAA==.Necroknight:BAAALgAECgQJBgAAAA==.Necrot:BAAALgAECgEJAQAAAA==.Necrotheholy:BAAALgAECgQJDQAAAA==.',
Ng='Nghtíy:BAABLgAECn8aAAIYAAYJQBN0nQAIAQAYAAYJQBN0nQAIAQAAAA==.',
Ni='Nixa:BAAALgADCgUJBQAAAA==.',
No='Nocturnüs:BAABLgAECn8nAAIUAAkJlhHvGQDRAQAUAAkJlhHvGQDRAQAAAA==.Noh:BAAALgAECgIJAgAAAA==.Nordikmage:BAABLgAECn8aAAMIAAcJhxG9eABqAQAIAAcJhxG9eABqAQAbAAEJPwVSIAAuAAAAAA==.Nort:BAAALgADCgEJAgAAAA==.Nov:BAAALgADCgMJAwAAAA==.',
Oh='Ohtheirone:BAAALgADCgYJBgAAAA==.Ohtheironey:BAAALgADCgUJBQAAAA==.Ohtheironie:BAAALgADCgYJBgAAAA==.',
On='Ondereth:BAAALgAECgYJDAAAAA==.Onthehouse:BAAALgAECgYJDgAAAA==.',
Or='Orid:BAAALgADCgcJBwAAAA==.Orvannan:BAAALgADCgQJCAAAAA==.',
Pa='Pacho:BAAALgADCgUJBQAAAA==.Palimorea:BAEALgADCgcJEAABLgADCgkJHAAEAAAAAA==.',
Pi='Piercey:BAACLgAFFH8IAAIWAAUJ1BKdCgBHAQAWAAUJ1BKdCgBHAQAuAAQKfykAAxYACAntHr4KAGUCABYACAntHr4KAGUCAB4AAQl0DIphAC8AAAEuAAUUBAkIAA0AfRgA.Pinkylove:BAABLgAECn8eAAINAAgJ8iBODADcAgANAAgJ8iBODADcAgAAAA==.',
Pr='Proera:BAAALgAECgcJBwAAAA==.Promathia:BAACLgAFFH8RAAMVAAQJ6x50BAAeAQAPAAQJCxxKIQBRAQAVAAMJ9iB0BAAeAQAuAAQKf00ABA8ACQnLJmAAAJcDAA8ACQnLJmAAAJcDABcABAkXCCVuAMIAABUAAQkDJU4zAGcAAAAA.Pross:BAAALgAECgQJCQABLgAECgkJKAAPALQbAA==.',
Pu='Puff:BAAALgAECggJDQAAAA==.',
Ra='Raenori:BAAALgADCgYJBgAAAA==.Ragnarolk:BAAALgAECgIJAgAAAA==.Raiyuden:BAAALgAECgEJAQAAAA==.Randydaytona:BAAALgAECgYJCwAAAA==.Rangërdangër:BAACLgAFFH8NAAIMAAUJrwYLOQACAQAMAAUJrwYLOQACAQAuAAQKfxYAAgwACQkQFQo1ANoBAAwACQkQFQo1ANoBAAAA.Rat:BAABLgAECn8jAAIUAAkJSSBzBABOAwAUAAkJSSBzBABOAwAAAA==.',
Re='Rectumus:BAAALgADCgUJCQAAAA==.Redrouges:BAABLgAECn8hAAISAAgJjiCICAB6AgASAAgJjiCICAB6AgAAAA==.Redwood:BAAALgAECgMJBQAAAA==.Renvskadoosh:BAAALgADCgkJGQABLgAECgcJHgAiAF0JAA==.Revhero:BAAALgAECgEJAQAAAA==.Rexpanda:BAABLgAECn8YAAIHAAYJ1R2CGgDmAQAHAAYJ1R2CGgDmAQAAAA==.',
Ro='Roguetheholy:BAAALgAECgkJBQAAAA==.Ross:BAEALgADCgEJAQABLgAFFAUJEwAdAA8lAA==.Rotawnda:BAAALgAECgQJBAAAAA==.Rotlord:BAAALgAECgYJCgAAAA==.',
Ru='Ruckus:BAAALgAECgUJBwABLgAECgYJEAAEAAAAAA==.Rumble:BAAALgAECgEJAQAAAA==.Rumrootbeer:BAAALgADCgIJAQAAAA==.',
['Rë']='Rëkz:BAAALgAECgMJAwAAAA==.',
Sa='Sanelle:BAAALgADCgkJCQABLgAECgkJKwAkABQgAA==.Sapoude:BAAALgAECgcJBgAAAA==.Sarang:BAAALgADCgcJBwAAAA==.Sarrsaras:BAAALgAECgEJAQABLgAECgQJCAAEAAAAAA==.',
Se='Seaursus:BAAALgAECgMJCAAAAA==.Seerblade:BAAALgADCgcJCgABLgAECgYJCwAEAAAAAA==.Sekaiju:BAAALgAECgQJBgAAAA==.Selakin:BAAALgADCgIJAgAAAA==.',
Sh='Shadowbann:BAAALgAECgMJBQAAAA==.Shadowrunner:BAAALgADCgYJCAAAAA==.Shammydavis:BAAALgADCgEJAQAAAA==.Shamwich:BAAALgAECgkJEgAAAA==.Shandroz:BAAALgAECgUJBQAAAA==.Shaori:BAAALgADCgMJBAAAAA==.Shortzo:BAAALgAECgcJCwABLgAFFAQJDAAlAJ0WAA==.Shrkbait:BAAALgAECgUJCgAAAA==.',
Sk='Skeezicks:BAAALgADCgUJBQAAAA==.Skidoosh:BAAALgAECgEJAwAAAA==.Skullcleaver:BAAALgADCgcJFAAAAA==.',
Sl='Slycc:BAAALgAECgMJAwAAAA==.',
Sm='Smackerr:BAAALgADCgUJBgAAAA==.',
Sn='Sneakay:BAABLgAFFH8GAAIaAAMJqQW0CQC+AAAaAAMJqQW0CQC+AAAAAA==.Sneakybiter:BAAALgADCgcJDQAAAA==.',
So='Solei:BAAALgAECgUJBQAAAA==.Southernguy:BAAALgAECgMJBAAAAA==.',
Sp='Spazzies:BAAALgAECgcJDQAAAA==.',
Sq='Squigglybutt:BAABLgAECn8eAAMgAAcJfxbWGgDLAQAgAAcJfxbWGgDLAQAkAAEJGQQHbAAmAAAAAA==.',
St='Statstick:BAAALgAFFAEJAQABLgAFFAYJCgAKAEkPAA==.Steelwing:BAAALgAFFAMJAwAAAA==.Stormbeards:BAAALgADCgYJBgAAAA==.Stoutkeg:BAAALgADCgQJAwAAAA==.Strixmonk:BAEALgAFFAEJAQABLgAFFAUJGQAYAM4cAA==.Strrawberry:BAAALgADCgIJAgAAAA==.Stêven:BAAALgAECggJCAAAAA==.Störmî:BAAALgAECgEJAQAAAA==.',
Su='Sungchaluka:BAAALgAECgMJBAAAAA==.',
['Sá']='Sásu:BAAALgADCgkJFQAAAA==.',
Ta='Talsomething:BAAALgAFFAEJAgAAAA==.Talsumthing:BAABLgAFFH8JAAIXAAUJqwTaGgAXAQAXAAUJqwTaGgAXAQAAAA==.Tars:BAAALgAECgYJBgAAAA==.Tats:BAABLgAECn8iAAIPAAcJIx3YQgDfAQAPAAcJIx3YQgDfAQAAAA==.Tatsumâ:BAAALgADCgcJBwAAAA==.',
Te='Terraxic:BAAALgAECgYJDAAAAA==.Terthaith:BAABLgAECn8YAAIQAAkJKwyDTACeAQAQAAkJKwyDTACeAQAAAA==.Tezguin:BAAALgADCgYJDQAAAA==.',
Th='Theedemon:BAAALgAECgQJBAAAAA==.Theironie:BAAALgADCgYJBgAAAA==.Theparttimer:BAAALgADCgEJAQAAAA==.Thiccpie:BAAALgAECgYJCwAAAA==.Throdwran:BAAALgAECgYJDAABLgAECgkJKAAPALQbAA==.',
Ti='Timba:BAAALgAECgYJCAAAAA==.Tisaka:BAABLgAECn8aAAISAAYJAxmZJQDMAQASAAYJAxmZJQDMAQAAAA==.',
Tl='Tlovexx:BAAALgAFFAEJAQAAAA==.',
To='Tolya:BAAALgADCgEJAQAAAA==.Toohbooh:BAAALgAECgMJBgAAAA==.Totem:BAAALgAECgcJDAAAAA==.',
Tr='Tranqx:BAACLgAFFH8PAAMYAAQJcyMqUgApAQAYAAMJGSQqUgApAQAZAAMJ+CCKCgAIAQAuAAQKfzkAAxkACQnoJgEBACEDABgACAm1JlUIAFwDABkACAmnJgEBACEDAAAA.Treevlo:BAAALgADCgEJAQAAAA==.Treva:BAABLgAECn8hAAQGAAkJ9Rn3GgDdAQAGAAkJ9Rn3GgDdAQAjAAQJtAYrLgCoAAAfAAEJZQPfSgAsAAAAAA==.Trizz:BAAALgAECgYJBgAAAA==.Troctzul:BAAALgADCgEJAwAAAA==.',
Ts='Tsuchiya:BAAALgAECgYJCwAAAA==.',
Tu='Tuts:BAAALgADCgYJDAAAAA==.',
Ty='Tythos:BAAALgADCgUJCQAAAA==.',
Up='Uproar:BAACLgAFFH8FAAIZAAIJIRT5EgCNAAAZAAIJIRT5EgCNAAAuAAQKfy4AAhkACQlDJdEAADEDABkACQlDJdEAADEDAAAA.',
Va='Vaelira:BAAALgADCgkJCQAAAA==.Vahlfi:BAACLgAFFH8EAAIJAAIJCRwRXACeAAAJAAIJCRwRXACeAAAuAAQKfxwABAkACQljJDALANYCAAkACQljJDALANYCAAoAAQm6Ij9EAGUAACcAAgkTEfkqADIAAAEuAAUUBQkUABMA7iUA.Valemon:BAAALgAFFAIJAwAAAA==.Valeskogr:BAABLgAECn8dAAQMAAkJAg4ETQCOAQAMAAgJZw4ETQCOAQAlAAcJjQjeFAB6AQABAAgJmAN0UAAMAQAAAA==.Valffi:BAAALgAFFAEJAQABLgAFFAUJFAATAO4lAA==.Varoth:BAAALgAECgEJAQAAAA==.Varus:BAAALgAECgYJCQAAAA==.',
Ve='Velisá:BAAALgAECgIJAgAAAA==.Vengefulmilk:BAAALgAECgMJBgAAAA==.Venture:BAAALgADCgkJIgAAAA==.Vergo:BAAALgADCgEJAQAAAA==.Vescovo:BAABLgAECn8rAAQkAAkJFCDIBAAhAwAkAAkJFCDIBAAhAwAUAAUJ0RW+NwAOAQAgAAEJrh+jdABWAAAAAA==.',
Vi='Virde:BAAALgADCgMJAwAAAA==.',
Vl='Vll:BAABLgAECn8fAAIKAAgJ0iI0BQDDAgAKAAgJ0iI0BQDDAgABLgAECgkJJgAMALUbAA==.',
Vo='Volkihar:BAAALgAECgUJBQAAAA==.Vordt:BAAALgAECgIJBgAAAA==.',
Wa='Wardaorm:BAABLgAECn8XAAIdAAYJhgeDXACxAAAdAAYJhgeDXACxAAABLgAECgkJKAAPALQbAA==.Warkinz:BAAALgADCgQJBQAAAA==.Warlin:BAAALgAECgEJAQAAAA==.',
Wi='Willohh:BAAALgAECgQJBAAAAA==.Winden:BAABLgAECn8WAAILAAYJhhtrEgBOAQALAAYJhhtrEgBOAQAAAA==.Wingback:BAAALgAECgcJBQAAAA==.Wiz:BAAALgAECgYJDgAAAA==.',
Wp='Wphoenix:BAAALgAECgQJBAAAAA==.',
Wr='Wrizz:BAAALgADCgQJBAAAAA==.',
Wt='Wtfsteve:BAAALgADCgUJBQABLgAECggJFwAcAEgZAA==.',
Xa='Xadrai:BAAALgAECgYJCwAAAA==.',
Xe='Xeplin:BAAALgAECgUJCQAAAA==.',
Xh='Xhenshini:BAABLgAECn9AAAMGAAkJTiG3BAAEAwAGAAkJHCG3BAAEAwAjAAgJqhoxCQBOAgAAAA==.',
Xk='Xkrin:BAAALgAECgEJAQAAAA==.',
Ye='Yeonguo:BAAALgAECgYJDgAAAA==.',
Yu='Yums:BAAALgADCgcJCAAAAA==.',
Za='Zalethe:BAAALgAECgMJAwAAAA==.Zalliel:BAAALgADCggJCAAAAA==.Zalman:BAAALgAECgMJBQAAAA==.Zaphíel:BAAALgADCgcJBwABLgAECgkJGAAQACsMAA==.Zaran:BAAALgAECgYJCAAAAA==.',
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
