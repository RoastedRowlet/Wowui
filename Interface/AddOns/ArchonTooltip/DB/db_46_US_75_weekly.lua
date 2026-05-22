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

local lookup = {'Hunter-Marksmanship','Druid-Feral','Druid-Balance','Evoker-Augmentation','Monk-Mistweaver','DemonHunter-Devourer','DemonHunter-Havoc','Shaman-Enhancement','Hunter-BeastMastery','Druid-Restoration','Druid-Guardian','Paladin-Retribution','Priest-Shadow','Warlock-Demonology','Unknown-Unknown','DeathKnight-Blood','Rogue-Subtlety','Rogue-Assassination','Paladin-Protection','Warrior-Protection','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Destruction','Monk-Windwalker','Warrior-Arms','Warrior-Fury','Evoker-Preservation','Mage-Frost','Priest-Holy','Warlock-Affliction','Shaman-Elemental','Shaman-Restoration','Evoker-Devastation','Hunter-Survival','Monk-Brewmaster','DemonHunter-Vengeance','Mage-Arcane','Priest-Discipline',}
local provider = {region='US',realm="Drak'thul",name='US',type='weekly',zone=46,date='2026-05-16',data={Ad='Ador:BAAALgADCgMJAwAAAA==.',
Ae='Aeladrel:BAAALgADCggJCAAAAA==.',
Ak='Akirie:BAABLgAECn8aAAIBAAYJDxdaDgAuAQABAAYJDxdaDgAuAQAAAA==.Akumu:BAABLgAECn8eAAMCAAkJrRtVBQC5AgACAAkJrRtVBQC5AgADAAEJAAAkfwAAAAAAAA==.Akumua:BAAALgAECgQJBAABLgAECgkJHgACAK0bAA==.',
Al='Alangi:BAAALgAECgcJEwABLgAECgkJNwAEAIMfAA==.Albinah:BAABLgAECn8dAAIFAAcJAB1WEgAgAgAFAAcJAB1WEgAgAgAAAA==.Albsli:BAAALgADCgIJAgAAAA==.Albsygos:BAAALgADCgQJBAAAAA==.Albz:BAAALgADCgkJHAAAAA==.Albzap:BAAALgADCgMJAwAAAA==.Albzu:BAAALgAECgUJBQAAAA==.Aldien:BAAALgAECgYJEgAAAA==.Aliphar:BAAALgADCgEJAQAAAA==.',
Ao='Aoe:BAACLgAFFH8KAAIGAAMJchFQQADcAAAGAAMJchFQQADcAAAuAAQKfxwAAgYACQnrGp8PAIYCAAYACQnrGp8PAIYCAAEuAAUUBgkJAAcASQ8A.',
Ar='Arienna:BAAALgAECgMJAwAAAA==.Arteñ:BAAALgAECgUJCQAAAA==.',
As='Ashrak:BAABLgAECn8dAAIIAAcJAA20EQAgAQAIAAcJAA20EQAgAQAAAA==.',
Av='Averroes:BAABLgAECn8wAAIJAAgJ6hb+KADqAQAJAAgJ6hb+KADqAQAAAA==.',
Aw='Awa:BAAALgAECgYJEgABLgAFFAYJCQAHAEkPAA==.Awee:BAACLgAFFH8JAAIHAAYJSQ/2BABdAQAHAAYJSQ/2BABdAQAuAAQKfzwAAgcACAnZItgIANUCAAcACAnZItgIANUCAAAA.Awi:BAAALgADCgUJBQABLgAFFAYJCQAHAEkPAA==.Awo:BAACLgAFFH8HAAIKAAQJfRjzEwBdAQAKAAQJfRjzEwBdAQAuAAQKfzEABAoACAlmJagDAFoDAAoACAlmJagDAFoDAAIABgmIFkIUAG4BAAsACAmGHf8SAE0BAAAA.Awoo:BAAALgAECgYJBwABLgAFFAQJBwAKAH0YAA==.',
Ay='Aylen:BAABLgAECn8eAAIMAAkJ5w5iSACkAQAMAAkJ5w5iSACkAQAAAA==.',
Ba='Babsvilla:BAAALgAECgMJBAAAAA==.Badmagi:BAAALgAECgEJAQAAAA==.Bahldrahg:BAAALgAECgMJAwAAAA==.Baki:BAABLgAFFH8HAAIEAAMJhg9VLQDHAAAEAAMJhg9VLQDHAAABLgAFFAMJCwANANQhAA==.Banegrim:BAABLgAECn8oAAIOAAgJdg0/VgBbAQAOAAgJdg0/VgBbAQAAAA==.Barnbirt:BAAALgAECgEJAQAAAA==.Barron:BAAALgAECgIJAgAAAA==.Barronthee:BAAALgAECgIJAgAAAA==.Battlecat:BAAALgAECggJDwAAAA==.',
Be='Beelzebubx:BAAALgAECgQJBAABLgAECgkJHgACAK0bAA==.Belysiuh:BAAALgAECgMJAwAAAA==.',
Bl='Blackdaisydr:BAAALgADCgcJDQABLgAECgYJCwAPAAAAAA==.Blindwalker:BAABLgAECn8hAAIQAAkJeQ2xGwAlAQAQAAkJeQ2xGwAlAQAAAA==.Blissfuleigh:BAAALgAECgIJAwAAAA==.Bloodbarron:BAAALgAECgYJCgAAAA==.',
Bo='Boldius:BAAALgADCgQJBAABLgAECgQJBAAPAAAAAA==.Bookchin:BAAALgADCgEJAQAAAA==.',
Br='Bragdand:BAEALgADCgkJHAAAAA==.Braistlin:BAAALgADCgIJAgABLgAECgQJBAAPAAAAAA==.Bred:BAAALgADCgcJBwAAAA==.Brewfest:BAAALgADCgMJBgAAAA==.Briarthorn:BAAALgAECgYJBgAAAA==.Brielan:BAAALgAECgYJEQAAAA==.',
Bu='Bubblegump:BAAALgAECgIJAgAAAA==.',
Ca='Cadillacbob:BAAALgAECgIJAwAAAA==.Calon:BAAALgAECgQJBQAAAA==.Cantseedizz:BAAALgADCgMJAwAAAA==.Castigate:BAACLgAFFH8XAAINAAUJLCGdBgCWAQANAAUJLCGdBgCWAQAuAAQKfysAAg0ACAk0IUIKAN4CAA0ACAk0IUIKAN4CAAAA.',
Ce='Cederek:BAAALgADCgIJAgAAAA==.Ceresarian:BAAALgADCgMJAwAAAA==.',
Ch='Chancho:BAAALgAECgUJBQABLgAECggJLQALAEISAA==.Cheesekitten:BAAALgADCgEJAQABLgAECggJNwAMALMmAA==.Cheesemonk:BAAALgADCgkJKAABLgAECggJNwAMALMmAA==.Cheesepally:BAABLgAECn83AAIMAAgJsyavBgAJAwAMAAgJsyavBgAJAwAAAA==.Cheesewhelp:BAAALgADCgcJBwAAAA==.Chikoung:BAAALgADCgUJBQAAAA==.',
Cl='Cloud:BAAALgAECgkJEgAAAA==.',
Co='Coderictond:BAAALgADCgQJBgAAAA==.Cogpally:BAAALgADCggJCAAAAA==.',
Cr='Crysa:BAAALgADCgYJBgAAAA==.',
Cy='Cygnus:BAABLgAECn8gAAMRAAcJcQ+HGgBoAQARAAcJcQ+HGgBoAQASAAUJfwZ4DwDnAAAAAA==.Cylla:BAAALgAECgcJEwABLgAFFAMJDQATAPYgAA==.',
Da='Daddywarbuks:BAAALgAECgUJBgAAAA==.Dagin:BAABLgAECn8kAAIMAAgJZB0XHwBJAgAMAAgJZB0XHwBJAgAAAA==.Dalarenaric:BAAALgADCgcJDAAAAA==.Dalt:BAAALgAFFAEJAQAAAA==.Daltonator:BAAALgADCgMJAwAAAA==.Dantemore:BAABLgAECn8aAAICAAcJlxd9CwCjAQACAAcJlxd9CwCjAQAAAA==.Daorcy:BAAALgADCggJDgAAAA==.Dartherd:BAABLgAECn8dAAIUAAcJiRjIDwCdAQAUAAcJiRjIDwCdAQAAAA==.Dawnotheholy:BAABLgAECn84AAMVAAgJnw0gKQB2AQAVAAgJnw0gKQB2AQAMAAcJIxA9gwAdAQAAAA==.',
De='Deathstar:BAACLgAFFH8eAAMWAAYJxxsbDADbAQAWAAUJxxsbDADbAQAQAAEJAACzMwAAAAAuAAQKfy4AAxYACQlCIxkJAPICABYACQlCIxkJAPICABcAAwl+DQISAHEAAAAA.Demonbunz:BAAALgADCgUJBwAAAA==.Derregar:BAABLgAECn8cAAMOAAcJFx4MOAC5AQAOAAcJpx0MOAC5AQAYAAIJ0RL1SACTAAAAAA==.',
Di='Dibella:BAAALgADCgYJAwAAAA==.Dirtydrago:BAAALgADCgUJBgABLgAECgQJBAAPAAAAAA==.Dirtymon:BAAALgADCgMJAwABLgAECgQJBAAPAAAAAA==.',
Dk='Dkfatality:BAACLgAFFH8KAAMXAAMJcR05BwABAQAXAAMJcR05BwABAQAWAAEJow5XVABPAAAuAAQKfywAAxcACQmSI6MAACoDABcACQmSI6MAACoDABYABgl/IQ5dANsBAAAA.',
Dl='Dlord:BAAALgADCgYJCAAAAA==.',
Do='Dock:BAAALgAECgQJCQAAAA==.Dominhoes:BAAALgAECgYJEQAAAA==.Dondon:BAAALgADCgcJBwAAAA==.Doontless:BAAALgAECgYJEQAAAA==.',
Dr='Draig:BAAALgAECgcJEwAAAA==.Dratini:BAAALgADCggJBwABLgAECggJFwAZAEgZAA==.Drozigg:BAAALgADCgYJCQAAAA==.',
Du='Duckfury:BAAALgAECgcJEQAAAA==.Dummy:BAAALgADCgYJBgAAAA==.Dunzoboom:BAAALgADCgcJCwAAAA==.Dunzö:BAAALgADCgYJBgAAAA==.',
Eb='Ebonhèart:BAABLgAECn8VAAMaAAcJAwvVGAAwAQAaAAcJAwvVGAAwAQAbAAEJwwUBqgA0AAAAAA==.',
Ec='Ecliptic:BAAALgAECgQJDQAAAA==.',
Eg='Eggle:BAAALgADCgIJAgAAAA==.',
Ei='Eisenheim:BAAALgADCgIJAgAAAA==.',
El='Electronvolt:BAABLgAECn8ZAAIcAAgJrRWWCQADAgAcAAgJrRWWCQADAgAAAA==.Eleidie:BAAALgADCgEJAQAAAA==.Elia:BAAALgAECgEJAQAAAA==.',
Ev='Evilyne:BAAALgADCgUJBwAAAA==.',
Ex='Exíled:BAAALgAECgEJAQAAAA==.',
Fa='Fallenlegion:BAAALgADCgcJBwAAAA==.Fartwizard:BAAALgAECgMJBQAAAA==.',
Fe='Felskerri:BAAALgADCgYJBgAAAA==.Fenus:BAAALgADCgIJAgAAAA==.',
Fi='Firebelly:BAAALgAECgMJAwAAAA==.Firerage:BAAALgADCgcJDwABLgAECgEJAgAPAAAAAA==.',
Fl='Flacidmonkey:BAAALgAECgcJDwAAAA==.Flufflenuzs:BAAALgAECgEJAQAAAA==.',
Fo='Fors:BAAALgAECgQJBAAAAA==.Forsäken:BAABLgAECn8VAAIdAAYJoRW0pwCKAQAdAAYJoRW0pwCKAQAAAA==.Forumangel:BAAALgADCgYJCQAAAA==.',
Fr='Freya:BAAALgADCgUJBQAAAA==.Frombehind:BAAALgAECgYJDwABLgAFFAUJHAAWAE0eAA==.',
Fu='Fubu:BAAALgAECgIJAgAAAA==.',
Ga='Gabenson:BAAALgADCgQJBAAAAA==.',
Gl='Glizzylatte:BAAALgADCgYJBgABLgAECgYJCwAPAAAAAA==.Gloomy:BAABLgAECn8bAAIeAAcJryBICgB3AgAeAAcJryBICgB3AgAAAA==.',
Gr='Grandizzle:BAAALgAECgYJCAAAAA==.',
Gu='Gumbi:BAAALgAECgIJAgAAAA==.Gumgum:BAACLgAFFH8JAAIfAAMJryZoAQBYAQAfAAMJryZoAQBYAQAuAAQKfzMAAh8ACAlIJs8AAM4CAB8ACAlIJs8AAM4CAAAA.Guruprime:BAAALgADCgMJBAAAAA==.',
Gw='Gwalla:BAAALgADCgkJEAABLgAECgMJBQAPAAAAAA==.',
Ha='Hagniy:BAABLgAECn9DAAIVAAgJFx+RCgCaAgAVAAgJFx+RCgCaAgAAAA==.Hakunamatata:BAAALgADCgUJBQAAAA==.Halten:BAAALgAECgkJBwAAAA==.Happyboy:BAABLgAECn8VAAQKAAYJjh+yHAAYAgAKAAYJjh+yHAAYAgALAAYJghC+HgDTAAACAAEJoBP8LwA8AAABLgAFFAQJBwAKAH0YAA==.Hardrockcafe:BAAALgADCgYJAwAAAA==.Harfu:BAAALgAECgIJAgAAAA==.Hartzdrell:BAAALgADCgcJDAAAAA==.',
He='Healmedaddy:BAAALgADCgEJAQAAAA==.Helbrandt:BAAALgAECgMJAwAAAA==.Heldarram:BAAALgAECgkJEQAAAA==.Hemaroid:BAAALgADCgcJBwAAAA==.Heolt:BAEALgADCgUJBQABLgADCgkJHAAPAAAAAA==.Hestia:BAAALgAECgUJBgAAAA==.Hexra:BAACLgAFFH8JAAIcAAMJaB9EEgAPAQAcAAMJaB9EEgAPAQAuAAQKfxwAAhwACAkgIiQFAPoCABwACAkgIiQFAPoCAAAA.Heyzus:BAAALgAECgYJCAAAAA==.',
Ho='Honnok:BAAALgAECgQJBAAAAA==.Hoofweaver:BAAALgAECgUJBQAAAA==.Hornyhead:BAAALgAECgQJDQAAAA==.Howard:BAAALgADCgIJAgAAAA==.',
Hr='Hrizul:BAABLgAECn8eAAMTAAgJIhwlCQDnAQATAAgJIhwlCQDnAQAMAAIJNQuN8wBoAAAAAA==.',
Ib='Iblameheals:BAAALgADCgMJBAAAAA==.',
Ic='Icebarron:BAAALgAECgYJDAAAAA==.',
Il='Il:BAABLgAECn8iAAIOAAkJtx4tIACXAgAOAAkJtx4tIACXAgAAAA==.Illisharr:BAAALgADCggJEQAAAA==.Ilusive:BAABLgAECn8cAAIgAAgJrRGsJABsAQAgAAgJrRGsJABsAQAAAA==.',
Ir='Irazlynaa:BAAALgADCgUJDgAAAA==.Irielyn:BAAALgADCgcJBwAAAA==.Ironblight:BAAALgAECgEJAQAAAA==.Irrah:BAAALgAECgYJDwAAAA==.',
Is='Ishal:BAAALgADCgEJAQAAAA==.',
Ja='Jabar:BAAALgADCgEJAQAAAA==.Jagz:BAABLgAECn83AAMhAAkJdx3qFgBeAgAhAAgJghzqFgBeAgAgAAgJPBwtGADOAQAAAA==.',
Jh='Jharael:BAAALgADCgUJBwAAAA==.',
Ji='Jia:BAAALgAECgEJAgAAAA==.',
Jo='Jonsi:BAAALgADCgUJBQABLgAECggJFwAZAEgZAA==.',
Ju='Junö:BAAALgADCgcJEgAAAA==.Jursh:BAAALgADCgQJBAAAAA==.',
Ka='Kaelen:BAAALgAECgYJCgAAAA==.Kaley:BAAALgADCgIJAgAAAA==.Katamine:BAABLgAECn8tAAIDAAgJohmiFADXAQADAAgJohmiFADXAQAAAA==.Katoz:BAABLgAECn8VAAMWAAcJSh3CQwCwAQAWAAcJSh3CQwCwAQAXAAIJTRYvEgBuAAAAAA==.Kawas:BAAALgAECgYJCQAAAA==.',
Ke='Keydron:BAAALgADCggJDwAAAA==.',
Kh='Khài:BAAALgAECgQJBQAAAA==.',
Ki='Kickit:BAAALgADCgQJBAAAAA==.Kilemall:BAAALgAECggJAgAAAA==.Killnall:BAABLgAECn8YAAIMAAYJMAfupgDfAAAMAAYJMAfupgDfAAAAAA==.Kiyohime:BAAALgAECgIJAgAAAA==.',
Kj='Kjadmina:BAAALgADCgUJBAAAAA==.',
Kl='Kladon:BAABLgAECn8gAAIBAAkJJxrmBQD5AQABAAkJJxrmBQD5AQAAAA==.Klozkoth:BAAALgAECgYJBgAAAA==.',
Ko='Konantheduck:BAAALgADCgMJAwABLgAECgcJEQAPAAAAAA==.',
Kr='Krystarin:BAABLgAECn8iAAIKAAgJaBYGHQAVAgAKAAgJaBYGHQAVAgAAAA==.Kryx:BAAALgADCgkJEAAAAA==.Kráytos:BAAALgAECgQJBwAAAA==.',
Ky='Kynria:BAAALgAECgIJAwAAAA==.',
La='Lallaure:BAAALgADCgQJBAAAAA==.Lambic:BAAALgAECgQJBAAAAA==.Lanma:BAABLgAECn8XAAIZAAgJSBlBEQBvAgAZAAgJSBlBEQBvAgAAAA==.Larpgodx:BAAALgAECgIJAwAAAA==.Lastoran:BAAALgAECgMJBQAAAA==.Lateralus:BAABLgAECn81AAIiAAkJkCC6AAAAAwAiAAkJkCC6AAAAAwAAAA==.Launcelot:BAABLgAECn8dAAMbAAcJSCKUHwBUAgAbAAYJ+yKUHwBUAgAaAAQJRB+FFgBLAQAAAA==.Laurasecord:BAAALgADCgQJBAAAAA==.Lazymage:BAAALgAECgUJBgAAAA==.',
Le='Leanbeef:BAAALgAECgYJBgAAAA==.Leshy:BAAALgADCgYJBgAAAA==.',
Li='Lights:BAACLgAFFH8LAAINAAMJ1CEQEwAYAQANAAMJ1CEQEwAYAQAuAAQKfzoAAg0ACQntJfgAAGIDAA0ACQntJfgAAGIDAAAA.Littlezo:BAACLgAFFH8IAAIjAAMJBRJZEwD3AAAjAAMJBRJZEwD3AAAuAAQKfyQAAiMACQkuJbwAAFADACMACQkuJbwAAFADAAAA.',
Lo='Lotus:BAABLgAECn8jAAQZAAgJGBdiFADGAQAZAAgJwxZiFADGAQAFAAYJ5wz3OAAFAQAkAAIJqR0TSACjAAAAAA==.',
Lt='Ltrnck:BAAALgADCgIJAgAAAA==.',
Lu='Lu:BAAALgADCgEJAQAAAA==.Luckbound:BAAALgAECgEJAQABLgAFFAQJBwAKAH0YAA==.Luthonys:BAAALgADCgEJAQAAAA==.',
Ma='Magond:BAAALgAECgIJAgAAAA==.Makoha:BAABLgAECn8tAAMLAAgJQhI+EQBkAQALAAgJQhI+EQBkAQACAAEJwA6OMQA2AAAAAA==.Makpriest:BAAALgAECgEJAQAAAA==.Malakaii:BAABLgAECn8cAAMIAAgJexEYDAAEAgAIAAgJQREYDAAEAgAgAAYJrhLKQgA+AQAAAA==.Mariahh:BAAALgADCgEJAQAAAA==.Masherkillu:BAABLgAECn8dAAIgAAgJFRSiHQCfAQAgAAgJFRSiHQCfAQAAAA==.Masherpally:BAAALgAECggJEQAAAA==.Maxdeath:BAABLgAECn8ZAAIdAAgJYBBOgADQAQAdAAgJYBBOgADQAQAAAA==.Maztajake:BAABLgAECn8UAAIDAAcJ1h3KEgDsAQADAAcJ1h3KEgDsAQAAAA==.Mazzyjake:BAAALgAECgQJBAABLgAECgcJFAADANYdAA==.',
Me='Medorh:BAAALgADCgYJBgAAAA==.Melchizedic:BAAALgAECgMJBAAAAA==.Merily:BAAALgADCgQJBAAAAA==.',
Mi='Mikeytott:BAAALgADCgQJBQAAAA==.Minnie:BAAALgAECgEJAQABLgAECgkJIQAEAPUZAA==.',
Mo='Mohgmoment:BAAALgADCgYJBgAAAA==.Moonfare:BAAALgADCgEJAgAAAA==.Mordacity:BAEBLgAECn8dAAIlAAcJnAYXEgDXAAAlAAcJnAYXEgDXAAAAAA==.',
Mu='Muris:BAAALgAECgQJBAAAAA==.',
['Mä']='Määt:BAAALgADCgIJAgAAAA==.',
Na='Nardo:BAAALgAECgEJAQAAAA==.',
Ne='Necro:BAAALgAECgIJAgAAAA==.Necroknight:BAAALgAECgEJAQAAAA==.Necrotheholy:BAAALgAECgQJDQAAAA==.',
Ng='Nghtíy:BAABLgAECn8aAAIWAAYJQBOHggAVAQAWAAYJQBOHggAVAQAAAA==.',
Ni='Nixa:BAAALgADCgUJBQAAAA==.',
No='Nocturnüs:BAABLgAECn8hAAINAAkJtw9CGQCoAQANAAkJtw9CGQCoAQAAAA==.Noh:BAAALgAECgEJAQAAAA==.Nordikmage:BAABLgAECn8aAAMdAAcJhxErZAB1AQAdAAcJhxErZAB1AQAmAAEJPwVSIAAuAAAAAA==.Nort:BAAALgADCgEJAgAAAA==.Nov:BAAALgADCgMJAwAAAA==.',
Oh='Ohtheironey:BAAALgADCgUJBQAAAA==.',
On='Ondereth:BAAALgAECgUJCgAAAA==.Onthehouse:BAAALgAECgYJDgAAAA==.',
Or='Orid:BAAALgADCgcJBwAAAA==.Orvannan:BAAALgADCgQJCAAAAA==.',
Pa='Pacho:BAAALgADCgUJBQAAAA==.Palimorea:BAEALgADCgcJEAABLgADCgkJHAAPAAAAAA==.',
Pi='Piercey:BAACLgAFFH8GAAIUAAMJjxgVEADlAAAUAAMJjxgVEADlAAAuAAQKfyMAAhQACAmHHr4KAGUCABQACAmHHr4KAGUCAAEuAAUUBAkHAAoAfRgA.Pinkylove:BAABLgAECn8eAAIKAAgJ8iBODADcAgAKAAgJ8iBODADcAgAAAA==.',
Pr='Proera:BAAALgAECgcJBwAAAA==.Promathia:BAACLgAFFH8NAAMTAAMJ9iBYAwAlAQATAAMJ9iBYAwAlAQAMAAMJkxpmOQD7AAAuAAQKf0QABAwACQmIJsAAAIADAAwACQmIJsAAAIADABUABAkXCCVuAMIAABMAAQkDJbosAGgAAAAA.Pross:BAAALgAECgQJCQABLgAECggJJAAMAGQdAA==.',
Pu='Puff:BAAALgAECggJDQAAAA==.',
Ra='Raenori:BAAALgADCgYJBgAAAA==.Ragnarolk:BAAALgAECgIJAgAAAA==.Raiyuden:BAAALgAECgEJAQAAAA==.Randydaytona:BAAALgAECgYJCwAAAA==.Rangërdangër:BAACLgAFFH8MAAIJAAUJrwbcKgARAQAJAAUJrwbcKgARAQAuAAQKfxYAAgkACQkQFQo1ANoBAAkACQkQFQo1ANoBAAAA.Rat:BAABLgAECn8jAAINAAkJSSBzBABOAwANAAkJSSBzBABOAwAAAA==.',
Re='Rectumus:BAAALgADCgUJCQAAAA==.Redrouges:BAABLgAECn8hAAIRAAgJjyC1BQCTAgARAAgJjyC1BQCTAgAAAA==.Redwood:BAAALgAECgMJBQAAAA==.Renvskadoosh:BAAALgADCgkJGQAAAA==.Revhero:BAAALgAECgEJAQAAAA==.Rexpanda:BAABLgAECn8YAAIFAAYJ1R2CGgDmAQAFAAYJ1R2CGgDmAQAAAA==.',
Ro='Roguetheholy:BAAALgAECgkJBQAAAA==.Ross:BAEALgADCgEJAQABLgAFFAUJCgAFAHwjAA==.Rotlord:BAAALgAECgYJCgAAAA==.',
Ru='Ruckus:BAAALgAECgUJBQABLgAECgYJEAAPAAAAAA==.Rumble:BAAALgAECgEJAQAAAA==.Rumrootbeer:BAAALgADCgIJAQAAAA==.',
['Rë']='Rëkz:BAAALgAECgMJAwAAAA==.',
Sa='Sanelle:BAAALgADCgkJCQABLgAECgkJJQAnABUgAA==.Sapoude:BAAALgAECgYJBQAAAA==.Sarang:BAAALgADCgYJBgAAAA==.',
Se='Seaursus:BAAALgAECgMJCAAAAA==.Seerblade:BAAALgADCgcJCgABLgAECgYJCwAPAAAAAA==.Sekaiju:BAAALgAECgQJBgAAAA==.Selakin:BAAALgADCgIJAgAAAA==.',
Sh='Shadowbann:BAAALgAECgMJAwAAAA==.Shadowrunner:BAAALgADCgYJCAAAAA==.Shamwich:BAAALgAECgkJEgAAAA==.Shandroz:BAAALgAECgQJBAAAAA==.Shaori:BAAALgADCgMJBAAAAA==.Shortzo:BAAALgAECgcJBwABLgAFFAMJCAAjAAUSAA==.Shrkbait:BAAALgAECgUJCQAAAA==.',
Sk='Skeezicks:BAAALgADCgUJBQAAAA==.Skidoosh:BAAALgAECgEJAwAAAA==.Skullcleaver:BAAALgADCgcJFAAAAA==.',
Sl='Slycc:BAAALgAECgMJAwAAAA==.',
Sm='Smackerr:BAAALgADCgUJBgAAAA==.',
Sn='Sneakay:BAAALgAFFAIJBAAAAA==.Sneakybiter:BAAALgADCgcJDQAAAA==.',
So='Solei:BAAALgAECgUJBQAAAA==.Southernguy:BAAALgAECgMJBAAAAA==.',
Sp='Spazzies:BAAALgAECgUJCAAAAA==.',
Sq='Squigglybutt:BAABLgAECn8ZAAMeAAcJyBXnFwDFAQAeAAcJyBXnFwDFAQAnAAEJGQQIXgAmAAAAAA==.',
St='Statstick:BAAALgAECgIJAwABLgAFFAYJCQAHAEkPAA==.Steelwing:BAAALgAECgkJDgABLgAECgkJHgACAK0bAA==.Stormbeards:BAAALgADCgYJBgAAAA==.Stoutkeg:BAAALgADCgQJAwAAAA==.Strixmonk:BAEALgAFFAEJAQABLgAFFAUJGAAWAI8bAA==.Strrawberry:BAAALgADCgIJAgAAAA==.Stêven:BAAALgAECggJCAAAAA==.Störmî:BAAALgAECgEJAQAAAA==.',
Su='Sungchaluka:BAAALgAECgMJBAAAAA==.',
['Sá']='Sásu:BAAALgADCgkJEQAAAA==.',
Ta='Talsomething:BAAALgAFFAEJAgAAAA==.Talsumthing:BAABLgAFFH8JAAIVAAUJqwQzFQAtAQAVAAUJqwQzFQAtAQAAAA==.Tars:BAAALgAECgYJBgAAAA==.Tats:BAABLgAECn8cAAIMAAcJ2xrQPQDEAQAMAAcJ2xrQPQDEAQAAAA==.',
Te='Terraxic:BAAALgAECgYJDAAAAA==.Terthaith:BAABLgAECn8YAAIOAAkJKwzPQQCYAQAOAAkJKwzPQQCYAQAAAA==.Tezguin:BAAALgADCgYJDQAAAA==.',
Th='Theedemon:BAAALgAECgQJBAAAAA==.Theironie:BAAALgADCgYJBgAAAA==.Theparttimer:BAAALgADCgEJAQAAAA==.Thiccpie:BAAALgAECgYJCwAAAA==.Throdwran:BAAALgAECgMJBQABLgAECggJJAAMAGQdAA==.',
Ti='Timba:BAAALgAECgYJCAAAAA==.Tisaka:BAABLgAECn8aAAIRAAYJAxmZJQDMAQARAAYJAxmZJQDMAQAAAA==.',
Tl='Tlovexx:BAAALgAFFAEJAQAAAA==.',
To='Tolya:BAAALgADCgEJAQAAAA==.Toohbooh:BAAALgAECgMJBgAAAA==.Totem:BAAALgAECgcJDAAAAA==.',
Tr='Tranqx:BAACLgAFFH8LAAMWAAMJuyQ7QQA2AQAWAAMJGSQ7QQA2AQAXAAIJpyF3CgC1AAAuAAQKfzAAAxYACQm6JlUIAFwDABYACAmuJlUIAFwDABcABgl+JoQDADsCAAAA.Treevlo:BAAALgADCgEJAQAAAA==.Treva:BAABLgAECn8hAAQEAAkJ9RkNFQDmAQAEAAkJ9RkNFQDmAQAiAAQJtAYrLgCoAAAcAAEJZQPfSgAsAAAAAA==.Trizz:BAAALgAECgQJBAAAAA==.Troctzul:BAAALgADCgEJAwAAAA==.',
Ts='Tsuchiya:BAAALgAECgYJBgAAAA==.',
Tu='Tuts:BAAALgADCgYJDAAAAA==.',
Up='Uproar:BAABLgAECn8hAAIXAAkJBCXNAAAUAwAXAAkJBCXNAAAUAwAAAA==.',
Va='Vaelira:BAAALgADCgkJCQAAAA==.Vahlfi:BAACLgAFFH8EAAIGAAIJCRwnTwCiAAAGAAIJCRwnTwCiAAAuAAQKfxgAAwYACAnfI2ITAOUCAAYACAnfI2ITAOUCACUAAgkTEd8kADMAAAEuAAUUBQkUABIA7iUA.Valemon:BAAALgAFFAIJAwAAAA==.Valeskogr:BAABLgAECn8dAAQJAAkJ/w3CPQCUAQAJAAgJYw7CPQCUAQAjAAcJjQjeFAB6AQABAAgJmAN0UAAMAQAAAA==.Valffi:BAAALgAFFAEJAQABLgAFFAUJFAASAO4lAA==.Varoth:BAAALgAECgEJAQAAAA==.Varus:BAAALgAECgYJCQAAAA==.',
Ve='Vengefulmilk:BAAALgAECgMJAwAAAA==.Venture:BAAALgADCgkJIgAAAA==.Vergo:BAAALgADCgEJAQAAAA==.Vescovo:BAABLgAECn8lAAMnAAkJFSCAAwAqAwAnAAkJFSCAAwAqAwAeAAEJrh+jdABWAAAAAA==.',
Vi='Virde:BAAALgADCgMJAwAAAA==.',
Vl='Vll:BAABLgAECn8VAAIHAAgJXyDPBQCSAgAHAAgJXyDPBQCSAgAAAA==.',
Vo='Volkihar:BAAALgADCgMJAwAAAA==.Vordt:BAAALgAECgIJBQAAAA==.',
Wa='Wardaorm:BAABLgAECn8UAAIbAAYJhgdGTwC2AAAbAAYJhgdGTwC2AAABLgAECggJJAAMAGQdAA==.Warkinz:BAAALgADCgQJBQAAAA==.Warlin:BAAALgAECgEJAQAAAA==.',
Wi='Willohh:BAAALgAECgQJBAAAAA==.Winden:BAABLgAECn8WAAIIAAYJhhs/DgBaAQAIAAYJhhs/DgBaAQAAAA==.Wingback:BAAALgAECgYJBQAAAA==.Wiz:BAAALgAECgQJBAAAAA==.',
Wp='Wphoenix:BAAALgAECgQJBAAAAA==.',
Wr='Wrizz:BAAALgADCgQJBAAAAA==.',
Wt='Wtfsteve:BAAALgADCgUJBQABLgAECggJFwAZAEgZAA==.',
Xa='Xadrai:BAAALgAECgYJCwAAAA==.',
Xe='Xeplin:BAAALgAECgUJCQAAAA==.',
Xh='Xhenshini:BAABLgAECn83AAMEAAkJgx+EBgC6AgAEAAkJ9R6EBgC6AgAiAAgJqhoxCQBOAgAAAA==.',
Ye='Yeonguo:BAAALgAECgYJDgAAAA==.',
Yu='Yums:BAAALgADCgcJBwAAAA==.',
Za='Zalethe:BAAALgAECgMJAwAAAA==.Zalliel:BAAALgADCggJCAAAAA==.Zalman:BAAALgAECgMJAwAAAA==.Zaphíel:BAAALgADCgcJBwABLgAECgkJGAAOACsMAA==.Zaran:BAAALgADCgYJBgAAAA==.',
Ze='Zeninnaoya:BAABLgAECn8fAAMaAAkJuSD6AABaAwAaAAkJ3B36AABaAwAbAAcJISaFDgDgAgAAAA==.',
['Âu']='Âura:BAAALgADCgEJAQAAAA==.',
['Ës']='Ësme:BAAALgADCgcJAgAAAA==.',
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
