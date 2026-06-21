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

local lookup = {'Hunter-Marksmanship','Druid-Feral','Druid-Balance','Unknown-Unknown','Shaman-Elemental','Evoker-Augmentation','Monk-Mistweaver','Priest-Discipline','Mage-Frost','DemonHunter-Devourer','DemonHunter-Havoc','Shaman-Enhancement','Hunter-BeastMastery','Druid-Guardian','Druid-Restoration','Warrior-Protection','Paladin-Retribution','Warrior-Arms','Warlock-Demonology','DeathKnight-Blood','Priest-Holy','Priest-Shadow','Monk-Windwalker','Monk-Brewmaster','Paladin-Protection','Rogue-Subtlety','Rogue-Assassination','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Destruction','Mage-Arcane','Warrior-Fury','Evoker-Preservation','Warlock-Affliction','Shaman-Restoration','Evoker-Devastation','Hunter-Survival','DemonHunter-Vengeance',}
local provider = {region='US',realm="Drak'thul",name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aalluntic:BAAALgAECgYJBgAAAA==.',
Ad='Ador:BAAALgAECgUJBQAAAA==.',
Ae='Aeladrel:BAAALgADCggJCAAAAA==.',
Ak='Akirie:BAABLgAECn8aAAIBAAYJDxeRFAAZAQABAAYJDxeRFAAZAQAAAA==.Akumu:BAABLgAECn8eAAMCAAkJrRtVBQC5AgACAAkJrRtVBQC5AgADAAEJAACEsAAAAAABLgAFFAMJAwAEAAAAAA==.Akumua:BAAALgAECgQJBAABLgAFFAMJAwAEAAAAAA==.',
Al='Alangi:BAABLgAECn8ZAAIFAAcJjgxoTQAAAQAFAAcJjgxoTQAAAQABLgAFFAUJDgAGAKYMAA==.Albinah:BAABLgAECn8dAAIHAAcJAB2bHwAeAgAHAAcJAB2bHwAeAgAAAA==.Albsli:BAAALgADCgIJAgAAAA==.Albsygos:BAAALgADCgQJBAAAAA==.Albz:BAAALgADCgkJHAAAAA==.Albzap:BAAALgADCgMJAwAAAA==.Albzley:BAABLgAECn8nAAIIAAkJfBloDQCXAgAIAAkJfBloDQCXAgAAAA==.Albzu:BAAALgAECgUJBQAAAA==.Aldien:BAABLgAECn8YAAIJAAYJ4AbP3gDcAAAJAAYJ4AbP3gDcAAAAAA==.Aliphar:BAAALgADCgEJAQAAAA==.Allaria:BAAALgAECgYJBgAAAA==.',
Ao='Aoe:BAACLgAFFH8XAAIKAAUJQhQLRQAYAQAKAAUJQhQLRQAYAQAuAAQKfyMAAgoACQlAHkgQAMACAAoACQlAHkgQAMACAAEuAAUUBgkTAAsA6hoA.',
Ar='Arcanism:BAAALgAECgYJCwAAAA==.Arienna:BAAALgAECgMJAwAAAA==.Arteñ:BAAALgAECgUJCQAAAA==.',
As='Ashrak:BAABLgAECn8jAAIMAAcJARMQFQBtAQAMAAcJARMQFQBtAQAAAA==.',
At='Attitudyjudy:BAAALgAECgYJBgAAAA==.',
Av='Averroes:BAACLgAFFH8GAAINAAMJ6AmZaQDSAAANAAMJ6AmZaQDSAAAuAAQKf0MAAg0ACQkaGlMeAHACAA0ACQkaGlMeAHACAAAA.',
Aw='Awee:BAACLgAFFH8TAAILAAYJ6hrKBADKAQALAAYJ6hrKBADKAQAuAAQKf0sAAgsACQkwJMIDABcDAAsACQkwJMIDABcDAAAA.Awi:BAAALgADCgUJBQABLgAFFAYJEwALAOoaAA==.Awo:BAACLgAFFH8SAAMOAAUJTCMXBgCaAQAOAAUJTCMXBgCaAQAPAAQJvR4PHAB6AQAuAAQKfzgABA8ACAlmJUMGAFMDAA8ACAlmJUMGAFMDAA4ACAklHzEJAFgCAAIABgmIFkIUAG4BAAEuAAUUCAkSABAAVxQA.Awoo:BAAALgAECgYJBwABLgAFFAgJEgAQAFcUAA==.',
Ay='Aylen:BAABLgAECn8eAAIRAAkJ6A5hcQCLAQARAAkJ6A5hcQCLAQAAAA==.',
Ba='Babsvilla:BAABLgAECn8UAAISAAYJKgPeXQBnAAASAAYJKgPeXQBnAAAAAA==.Badmagi:BAAALgAECgEJAQAAAA==.Bahldrahg:BAAALgAECgMJAwAAAA==.Baki:BAACLgAFFH8VAAIGAAUJMxyjIwBFAQAGAAUJMxyjIwBFAQAuAAQKfxwAAgYACQn+JKwCAE4DAAYACQn+JKwCAE4DAAAA.Banegrim:BAABLgAECn9HAAITAAkJzxJCVACfAQATAAkJzxJCVACfAQAAAA==.Bankisa:BAAALgAECgUJBQAAAA==.Barnbirt:BAAALgAECgEJAQAAAA==.Barron:BAAALgAECgIJAgAAAA==.Barronthee:BAAALgAECgIJAgAAAA==.Battlecat:BAABLgAECn8cAAIJAAgJjhI5bwCcAQAJAAgJjhI5bwCcAQAAAA==.',
Be='Beelzebubx:BAAALgAECgQJBAABLgAFFAMJAwAEAAAAAA==.Belysiuh:BAAALgAECgMJAwAAAA==.',
Bl='Blackdaisydr:BAAALgADCgcJDQABLgAECgYJCwAEAAAAAA==.Blindwalker:BAABLgAECn8hAAIUAAkJeQ2zKQAJAQAUAAkJeQ2zKQAJAQAAAA==.Blissfuleigh:BAAALgAECgIJAwAAAA==.Bloodbarron:BAAALgAECgYJCgAAAA==.',
Bo='Boldius:BAAALgADCgQJBAABLgAECgUJBQAEAAAAAA==.Bookchin:BAAALgADCgEJAQAAAA==.Bootylust:BAAALgADCgYJBgABLgAECgcJNwAVAJEfAA==.',
Br='Bragdand:BAEALgAECgYJCgAAAA==.Braistlin:BAAALgADCgIJAgABLgAECgUJBQAEAAAAAA==.Bred:BAAALgADCgcJBwAAAA==.Brewfest:BAAALgADCgMJBgAAAA==.Briarthorn:BAAALgAECgYJBgAAAA==.',
Bu='Bubblegump:BAAALgAECgIJAgAAAA==.Bulin:BAAALgADCgQJBAAAAA==.',
['Bü']='Büdwèiserr:BAAALgAECgQJDQAAAA==.',
Ca='Cadillacbob:BAAALgAECgIJAwAAAA==.Calon:BAAALgAECgQJBQAAAA==.Cantseedizz:BAAALgADCgMJAwAAAA==.Castigate:BAACLgAFFH8eAAIWAAYJJiIyCADpAQAWAAYJJiIyCADpAQAuAAQKfy4AAhYACQmHIrIIAMMCABYACQmHIrIIAMMCAAAA.',
Ce='Cederek:BAAALgADCgIJAgAAAA==.Ceresarian:BAAALgADCgMJAwAAAA==.',
Ch='Chancho:BAAALgAECgYJEAABLgAECgkJPgAOAA4RAA==.Cheesekitten:BAAALgADCgEJAQABLgAFFAMJCgARABIkAA==.Cheesemonk:BAABLgAECn8aAAMXAAkJ+SN0AgBFAwAXAAkJ+SN0AgBFAwAYAAcJGSKKDgBRAgABLgAFFAMJCgARABIkAA==.Cheesepally:BAACLgAFFH8KAAIRAAMJEiR/OQA5AQARAAMJEiR/OQA5AQAuAAQKf0EAAhEACQnCJqsBAH4DABEACQnCJqsBAH4DAAAA.Cheesewhelp:BAAALgADCgcJBwAAAA==.Chikoung:BAAALgADCgUJBQAAAA==.Chudmourne:BAAALgAECgUJBQABLgAECgkJLQAXAH8WAA==.',
Cl='Cloud:BAABLgAECn8oAAMZAAkJbCPEAQApAwAZAAkJbCPEAQApAwARAAIJfhUMNwF2AAAAAA==.',
Co='Coderictond:BAAALgADCgQJBgAAAA==.Cogpally:BAAALgADCggJCAAAAA==.',
Cr='Crysa:BAAALgADCgYJBgAAAA==.',
Cy='Cyanide:BAAALgADCgkJCQAAAA==.Cygnus:BAABLgAECn8yAAMaAAgJkRSXGQDNAQAaAAgJkRSXGQDNAQAbAAUJfwYrFQDYAAAAAA==.Cylla:BAABLgAECn8fAAINAAcJGiREHgBwAgANAAcJGiREHgBwAgABLgAFFAUJIwARAPEfAA==.',
Da='Daddywarbuks:BAAALgAECgUJBgAAAA==.Dagin:BAABLgAECn8uAAIRAAkJ1Bx/IgB8AgARAAkJ1Bx/IgB8AgAAAA==.Dalarenaric:BAAALgADCgcJDAAAAA==.Dalt:BAAALgAFFAEJAQAAAA==.Daltonator:BAAALgADCgMJAwAAAA==.Dantemore:BAABLgAECn8aAAICAAcJlxdMEgCXAQACAAcJlxdMEgCXAQAAAA==.Daorcy:BAAALgADCggJDgAAAA==.Dartherd:BAABLgAECn9AAAIQAAkJhhzwBgCYAgAQAAkJhhzwBgCYAgAAAA==.Dawnotheholy:BAABLgAECn9PAAQcAAkJCROsAACmAQAcAAkJCROsAACmAQARAAcJJBCoswAaAQAZAAQJABAhKwDCAAAAAA==.',
De='Deathbyone:BAAALgAECgcJBwAAAA==.Deathstar:BAACLgAFFH8sAAQdAAgJoxv6FgAnAgAdAAYJ7x36FgAnAgAeAAUJTBarBQCYAQAUAAEJAADTTwAAAAAuAAQKfy8AAx0ACQkSJK4NAP8CAB0ACQkSJK4NAP8CAB4AAwl+DQISAHEAAAAA.Deliverhealz:BAAALgAECgYJBgAAAA==.Demonbunz:BAAALgADCgUJBwAAAA==.Derregar:BAABLgAECn8cAAMTAAcJFx7dUgCjAQATAAcJpx3dUgCjAQAfAAIJ0RL1SACTAAAAAA==.Dezamius:BAAALgAECggJDwABLgAFFAUJDgAGAKYMAA==.',
Di='Dibella:BAAALgADCgYJAwAAAA==.Dirtydrago:BAAALgADCgUJBgABLgAECgUJBQAEAAAAAA==.Dirtymon:BAAALgADCgMJAwABLgAECgUJBQAEAAAAAA==.',
Dk='Dkfatality:BAACLgAFFH8NAAMeAAMJsR8fFADsAAAeAAMJsR8fFADsAAAdAAEJow5XVABPAAAuAAQKfy8AAx4ACQmSI+wBAAgDAB4ACQmSI+wBAAgDAB0ABgl/IQ5dANsBAAAA.',
Dl='Dlord:BAAALgADCgYJCAAAAA==.',
Do='Dock:BAAALgAECgQJCQAAAA==.Dominbros:BAAALgAECgQJBAABLgAECgYJFwAJAJYWAA==.Dominhoes:BAABLgAECn8XAAIJAAYJlhYclgBMAQAJAAYJlhYclgBMAQAAAA==.Dondon:BAAALgAECgQJBQAAAA==.Doontless:BAAALgAECgYJEQAAAA==.Doyouknow:BAAALgAECgMJAwAAAA==.',
Dr='Draig:BAABLgAECn8VAAMJAAcJ2Qm8vQANAQAJAAcJ2wi8vQANAQAgAAIJWwe+GQBKAAAAAA==.Dratini:BAAALgADCggJBwABLgAECggJFwAXAEgZAA==.Drozigg:BAAALgADCgYJCQAAAA==.',
Du='Duckfury:BAABLgAECn8gAAIhAAgJ8RD0LgCUAQAhAAgJ8RD0LgCUAQABLgAECgkJDAAEAAAAAA==.Duckmourne:BAAALgAECgkJDAAAAA==.Dummy:BAAALgADCgYJBgAAAA==.Dunzoboom:BAAALgADCgcJCwAAAA==.Dunzö:BAAALgADCgYJBgAAAA==.',
['Dë']='Dëad:BAAALgAECgQJBgAAAA==.',
Eb='Ebonhèart:BAABLgAECn8ZAAMSAAgJygsvKAAtAQASAAgJygsvKAAtAQAhAAEJwwUBqgA0AAAAAA==.',
Ec='Echoez:BAABLgAECn8UAAIHAAYJVxfVNwCTAQAHAAYJVxfVNwCTAQABLgAFFAQJEgAKAMYNAA==.Ecliptic:BAAALgAECgQJDQAAAA==.',
Eg='Eggle:BAAALgADCgIJAgAAAA==.',
Ei='Eisenheim:BAAALgADCgIJAgAAAA==.',
El='Electronvolt:BAABLgAECn8ZAAIiAAgJrBVzDQD5AQAiAAgJrBVzDQD5AQAAAA==.Eleidie:BAAALgADCgEJAQAAAA==.Elia:BAAALgAECgEJAQAAAA==.',
Ev='Evilyne:BAAALgADCgUJBwAAAA==.',
Ex='Exíled:BAAALgAECgEJAQAAAA==.',
Fa='Falilesta:BAAALgAECgEJAgAAAA==.Fallenlegion:BAAALgADCgcJBwAAAA==.Fartwizard:BAAALgAECgMJBQAAAA==.',
Fe='Felskerri:BAAALgADCgYJBgAAAA==.Fenus:BAAALgADCgIJAgAAAA==.',
Fi='Firebelly:BAAALgAECgMJAwAAAA==.Firerage:BAAALgADCgcJDwABLgAECgMJBgAEAAAAAA==.',
Fl='Flacidmonkey:BAAALgAECgcJDwAAAA==.Flufflenuzs:BAAALgAECgEJAQAAAA==.',
Fo='Fors:BAAALgAECgQJBAAAAA==.Forsäken:BAABLgAECn8VAAIJAAYJoRW0pwCKAQAJAAYJoRW0pwCKAQAAAA==.Forumangel:BAAALgADCgYJCQAAAA==.',
Fr='Freya:BAAALgADCgUJBQAAAA==.Fria:BAAALgAECgcJCAAAAA==.Frombehind:BAAALgAECgcJEgABLgAFFAgJJQAdAIEZAA==.',
Fu='Fubu:BAAALgAECgIJAgAAAA==.',
Ga='Gabenson:BAAALgADCgQJBAAAAA==.',
Ge='Geegnome:BAAALgAECgEJAQAAAA==.',
Gl='Glizzylatte:BAAALgADCgYJBgABLgAECgYJCwAEAAAAAA==.Gloomy:BAABLgAECn8+AAIVAAkJwx5wCADkAgAVAAkJwx5wCADkAgAAAA==.',
Gr='Grandbear:BAAALgAFFAEJAwAAAA==.Grandizzle:BAABLgAECn8XAAIKAAgJVA8KXgBvAQAKAAgJVA8KXgBvAQAAAA==.Grandore:BAAALgAECgEJAwAAAA==.',
Gu='Gumbi:BAAALgAECgIJAgAAAA==.Gumgum:BAACLgAFFH8XAAMjAAQJliXzAQCgAQAjAAQJliXzAQCgAQAfAAEJ4CFyGQBiAAAuAAQKfzYAAiMACAlYJg0BAP8CACMACAlYJg0BAP8CAAAA.Guruprime:BAAALgADCgYJCAAAAA==.',
Gw='Gwalla:BAAALgADCgkJFwABLgAECgMJBQAEAAAAAA==.',
Ha='Hagniy:BAABLgAECn9dAAIcAAkJ8x5wCQD0AgAcAAkJ8x5wCQD0AgAAAA==.Hakunamatata:BAAALgADCgUJBQAAAA==.Halten:BAAALgAECgkJBwAAAA==.Happyboy:BAABLgAECn8fAAQPAAYJjh+IJwAUAgAPAAYJjh+IJwAUAgAOAAYJ+BufGACLAQACAAEJ0BxiRABSAAABLgAFFAgJEgAQAFcUAA==.Hardrockcafe:BAAALgADCgYJAwAAAA==.Harfu:BAAALgAECgIJAgAAAA==.Hartzdrell:BAAALgADCgcJDAAAAA==.Hashirama:BAABLgAFFH8LAAICAAUJXiFMAABQAQACAAUJXiFMAABQAQABLgAFFAUJFQAGADMcAA==.',
He='Healmedaddy:BAAALgADCgEJAQAAAA==.Helbrandt:BAAALgAECgMJAwAAAA==.Heldarram:BAAALgAECgkJEQAAAA==.Hemaroid:BAAALgADCgcJBwAAAA==.Heolt:BAEALgADCgUJBQABLgAECgYJCgAEAAAAAA==.Hestia:BAAALgAECgUJBgAAAA==.Hexra:BAACLgAFFH8WAAIiAAUJzB9rDQDJAQAiAAUJzB9rDQDJAQAuAAQKfx4AAiIACQnIISQFAPoCACIACQnIISQFAPoCAAAA.Heyzus:BAAALgAECgYJCQAAAA==.',
Ho='Honnok:BAAALgAECgQJBAAAAA==.Hoofweaver:BAAALgAECgUJBQAAAA==.Hornyhead:BAAALgAECgQJDQAAAA==.Howard:BAAALgADCgIJAgAAAA==.',
Hr='Hrizul:BAABLgAECn80AAMZAAkJtB+SBQCWAgAZAAgJGiGSBQCWAgARAAcJRRFlnQA8AQAAAA==.',
Ib='Iblameheals:BAAALgADCgMJBAAAAA==.',
Ic='Icebarron:BAAALgAECgYJDQAAAA==.',
Il='Il:BAABLgAECn8iAAITAAkJtx4tIACXAgATAAkJtx4tIACXAgAAAA==.Illisharr:BAAALgADCggJEQAAAA==.Iloveleaf:BAAALgADCgEJAQAAAA==.Ilusive:BAABLgAECn8cAAIFAAgJrhEvNwBcAQAFAAgJrhEvNwBcAQAAAA==.',
Ir='Irazlynaa:BAAALgADCgUJDgAAAA==.Irielyn:BAAALgAECgUJBQAAAA==.Ironblight:BAAALgAECgEJAQAAAA==.Irrah:BAAALgAECgYJDwAAAA==.',
Is='Ishal:BAAALgADCgEJAQAAAA==.',
Ja='Jabar:BAAALgADCgEJAQAAAA==.Jagz:BAABLgAECn87AAMkAAkJ7B3qFgBeAgAkAAgJBR3qFgBeAgAFAAgJ4h3zFwAkAgAAAA==.',
Jh='Jharael:BAAALgADCgUJBwAAAA==.',
Ji='Jia:BAAALgAECgEJAgAAAA==.',
Jo='Jonsi:BAAALgADCgUJBQABLgAECggJFwAXAEgZAA==.',
Ju='Junö:BAAALgAECgEJAQAAAA==.Jursh:BAAALgADCgQJBAAAAA==.',
Ka='Kaelen:BAABLgAECn8YAAINAAgJ/BlGPQDsAQANAAgJ/BlGPQDsAQAAAA==.Kaley:BAAALgADCgIJAgAAAA==.Kasuo:BAAALgAECgEJAQAAAA==.Katamine:BAABLgAECn9AAAIDAAkJfBwcDQCGAgADAAkJfBwcDQCGAgAAAA==.Katoz:BAABLgAECn8aAAMdAAgJHx7NOQAYAgAdAAgJHx7NOQAYAgAeAAIJTRYvEgBuAAAAAA==.Kawas:BAAALgAECgYJCQAAAA==.',
Ke='Keydron:BAAALgADCggJDwAAAA==.',
Kh='Khài:BAAALgAECgQJBQAAAA==.',
Ki='Kickit:BAAALgADCgQJBAAAAA==.Kilemall:BAAALgAECgkJAgAAAA==.Killnall:BAABLgAECn8qAAIRAAcJNwikxAACAQARAAcJNwikxAACAQAAAA==.Kiyohime:BAAALgAECgIJAgAAAA==.',
Kj='Kjadmina:BAAALgADCgUJBAAAAA==.',
Kl='Kladon:BAABLgAECn8gAAIBAAkJJxpyCQDfAQABAAkJJxpyCQDfAQAAAA==.Klozkoth:BAAALgAECgYJBgAAAA==.',
Ko='Konantheduck:BAAALgADCgMJAwABLgAECgkJDAAEAAAAAA==.',
Kr='Krystarin:BAABLgAECn8xAAIPAAkJIRduGwBqAgAPAAkJIRduGwBqAgAAAA==.Kryx:BAAALgADCgkJEAAAAA==.Kráytos:BAAALgAECgcJCgAAAA==.',
Ky='Kynria:BAAALgAECgIJAwAAAA==.',
La='Lallaure:BAAALgADCgQJBAAAAA==.Lambic:BAAALgAECgQJBAAAAA==.Lanma:BAABLgAECn8XAAIXAAgJSBlBEQBvAgAXAAgJSBlBEQBvAgAAAA==.Larpgodx:BAAALgAECgIJAwAAAA==.Lastoran:BAAALgAECgMJBQAAAA==.Lateralus:BAABLgAECn9HAAIlAAkJWiEoAQD+AgAlAAkJWiEoAQD+AgAAAA==.Launcelot:BAABLgAECn8dAAMhAAcJSCKUHwBUAgAhAAYJ+yKUHwBUAgASAAQJRB8FJgA4AQAAAA==.Laurasecord:BAAALgADCgQJBAAAAA==.Lazymage:BAAALgAECgcJDAAAAA==.',
Le='Leanbeef:BAAALgAECgYJBgAAAA==.Lerath:BAAALgAECggJDQAAAA==.Leshy:BAAALgADCgYJBgAAAA==.',
Li='Liferips:BAAALgAECgUJBQAAAA==.Lights:BAACLgAFFH8LAAIWAAMJ1CHLIADuAAAWAAMJ1CHLIADuAAAuAAQKfz8AAxYACQnuJToCAEoDABYACQnuJToCAEoDAAgABQmTIHwfANIBAAEuAAUUBQkVAAYAMxwA.Littlezo:BAACLgAFFH8WAAImAAUJcB7WCgBwAQAmAAUJcB7WCgBwAQAuAAQKfy0AAiYACQl0JYoBAEkDACYACQl0JYoBAEkDAAAA.',
Lo='Lockßulbtwo:BAAALgAECgEJAgAAAA==.Lotus:BAABLgAECn8tAAQXAAkJfxZcFwD5AQAXAAkJNBZcFwD5AQAYAAUJHhVeMQA8AQAHAAYJ5wz3OAAFAQAAAA==.',
Lt='Ltrnck:BAAALgADCgIJAgAAAA==.',
Lu='Lu:BAAALgADCgEJAQAAAA==.Luckbound:BAAALgAECgEJAQABLgAFFAgJEgAQAFcUAA==.Luthonys:BAAALgADCgEJAQAAAA==.',
Ma='Magond:BAAALgAECgIJAgAAAA==.Maiko:BAAALgADCgMJAwAAAA==.Makoha:BAABLgAECn8+AAMOAAkJDhF4GQCDAQAOAAkJDhF4GQCDAQACAAIJ7gtiVAAwAAAAAA==.Makpriest:BAABLgAECn8UAAIWAAYJ5g8NQQALAQAWAAYJ5g8NQQALAQAAAA==.Malakaii:BAABLgAECn8eAAMMAAkJ3hIYDAAEAgAMAAkJrBIYDAAEAgAFAAYJrhLKQgA+AQAAAA==.Margaes:BAAALgADCgEJAgAAAA==.Mariahh:BAAALgADCgEJAQAAAA==.Masherevo:BAAALgAFFAQJBAABLgAFFAQJDQAFAMMRAA==.Masherkillu:BAACLgAFFH8NAAIFAAQJwxH2IwAJAQAFAAQJwxH2IwAJAQAuAAQKfywAAgUACQllGFEVAD4CAAUACQllGFEVAD4CAAAA.Masherpally:BAACLgAFFH8NAAMRAAMJvwvPBgDTAAARAAMJvwvPBgDTAAAZAAEJPgXDGQAuAAAuAAQKfzQAAxEACQnjHqMSANMCABEACQnjHqMSANMCABkAAwlVFSUCAHsAAAEuAAUUBAkNAAUAwxEA.Maxdeath:BAABLgAECn8bAAIJAAkJpQ5OgADQAQAJAAkJpQ5OgADQAQAAAA==.Maztajake:BAABLgAECn8WAAIDAAgJvR6rEQBMAgADAAgJvR6rEQBMAgAAAA==.Mazyjake:BAAALgAECgcJCQABLgAECggJFgADAL0eAA==.Mazzyjake:BAAALgAECgUJBQABLgAECggJFgADAL0eAA==.',
Me='Meadowlark:BAAALgAECgcJDQABLgAFFAQJEAAPAKUYAA==.Medorh:BAAALgADCgYJBgAAAA==.Melchizedic:BAAALgAECgUJEgAAAA==.Merily:BAAALgADCgQJBAAAAA==.',
Mi='Mikeytott:BAAALgADCgQJBQABLgAECgMJAwAEAAAAAA==.Minnie:BAAALgAECgEJAQABLgAECgkJIQAGAPUZAA==.',
Mo='Mohgmoment:BAAALgADCgYJBgAAAA==.Moonfare:BAAALgADCgEJAgAAAA==.Mordacity:BAEBLgAECn9AAAInAAkJFwjZEQAwAQAnAAkJFwjZEQAwAQAAAA==.',
Mu='Muris:BAAALgAECgQJBAAAAA==.',
['Mä']='Määt:BAAALgADCgIJAgAAAA==.',
Na='Nardo:BAAALgAECgEJAQAAAA==.',
Ne='Necrot:BAAALgAECgEJAQAAAA==.',
Ng='Nghtíy:BAABLgAECn8aAAIdAAYJQBOwvAACAQAdAAYJQBOwvAACAQAAAA==.',
Ni='Nixa:BAAALgADCgUJBQAAAA==.',
No='Nocturnüs:BAABLgAECn8vAAIWAAkJuhKnGgDwAQAWAAkJuhKnGgDwAQAAAA==.Noh:BAAALgAECgQJBQAAAA==.Nordikmage:BAABLgAECn8jAAMJAAkJAhRzQAAbAgAJAAkJAhRzQAAbAgAgAAEJPwVSIAAuAAAAAA==.Nort:BAAALgADCgEJAgAAAA==.Nov:BAAALgADCgMJAwAAAA==.',
['Nê']='Nêcrömane:BAAALgAECgUJCAAAAA==.',
['Në']='Nëssa:BAAALgAECgIJAgABLgAECgYJCgAEAAAAAA==.',
Oh='Ohtheirone:BAAALgADCgYJBgAAAA==.Ohtheironey:BAAALgADCgUJBQAAAA==.Ohtheironie:BAAALgADCgYJBgAAAA==.',
On='Ondereth:BAAALgAECgYJDgAAAA==.Onthehouse:BAAALgAECgYJDgAAAA==.',
Or='Orid:BAAALgADCgcJBwAAAA==.Orvannan:BAAALgADCgQJCAAAAA==.',
Pa='Pacho:BAAALgADCgUJBQAAAA==.Palimorea:BAEALgAECgMJAwABLgAECgYJCgAEAAAAAA==.Pallypower:BAAALgAECgYJBgAAAA==.',
Pi='Piercey:BAACLgAFFH8SAAMQAAgJVxRjBwDLAQAQAAgJVxRjBwDLAQASAAEJOhDBPwBLAAAuAAQKfysAAxAACAntHr4KAGUCABAACAntHr4KAGUCABIAAQn4H0ViAF0AAAAA.Pinkylove:BAABLgAECn8eAAIPAAgJ8iBODADcAgAPAAgJ8iBODADcAgAAAA==.',
Pr='Proera:BAAALgAECgcJCQAAAA==.Promathia:BAACLgAFFH8jAAQRAAUJ8R9RAgBZAQARAAUJ8R9RAgBZAQAZAAMJ9iAPBwAMAQAcAAUJnAzZKADeAAAuAAQKf1YABBEACQnOJuUAAI0DABEACQnOJuUAAI0DABwABAkXCCVuAMIAABkAAQkDJYA9AGcAAAAA.Pross:BAAALgAECgUJDAABLgAECgkJLgARANQcAA==.',
Ps='Psychopath:BAABLgAECn8aAAMaAAYJohYVLACeAQAaAAYJohYVLACeAQAbAAEJtwYkIAAyAAAAAA==.',
Pu='Puff:BAAALgAECggJDQAAAA==.',
Qu='Quicksotaka:BAAALgADCgcJBgAAAA==.',
Ra='Raenori:BAAALgADCgYJBgAAAA==.Ragnarolk:BAAALgAECgIJAgAAAA==.Rahveyn:BAAALgAECgIJAgAAAA==.Raiyuden:BAAALgAECgEJAQAAAA==.Randydaytona:BAAALgAECgYJCwAAAA==.Rangërdangër:BAACLgAFFH8PAAINAAUJzgYSVwD4AAANAAUJzgYSVwD4AAAuAAQKfxgAAg0ACQmTGQo1ANoBAA0ACQmTGQo1ANoBAAAA.Rat:BAABLgAECn8jAAIWAAkJSSBzBABOAwAWAAkJSSBzBABOAwAAAA==.',
Re='Rectumus:BAAALgADCggJEwAAAA==.Redrouges:BAACLgAFFH8IAAIaAAMJ3xOtJAD+AAAaAAMJ3xOtJAD+AAAuAAQKfykAAhoACQkNIVIEAPgCABoACQkNIVIEAPgCAAAA.Redwood:BAAALgAECgQJBgAAAA==.Renvskadoosh:BAAALgADCgkJGQABLgAECgcJHgAkAF0JAA==.Revhero:BAAALgAECgEJAQAAAA==.Rexpanda:BAABLgAECn8YAAIHAAYJ1R2CGgDmAQAHAAYJ1R2CGgDmAQAAAA==.',
Ro='Roguetheholy:BAAALgAECgkJBQAAAA==.Ross:BAEALgADCgEJAQABLgAFFAYJFAAHAAsmAA==.Rotawnda:BAAALgAECgYJBwAAAA==.Rotlord:BAAALgAECgYJCgAAAA==.',
Ru='Ruckus:BAAALgAECgYJCwAAAA==.Rumble:BAAALgAECgEJAQAAAA==.Rumrootbeer:BAAALgADCgIJAQAAAA==.',
Ry='Rynn:BAAALgAECgYJBwAAAA==.',
['Rë']='Rëkz:BAAALgAECgMJAwAAAA==.',
['Rì']='Rìppér:BAAALgAECgEJAQABLgAFFAUJFgAiAMwfAA==.',
Sa='Sanelle:BAAALgADCgkJCQABLgAECgkJKwAIABQgAA==.Sapoude:BAAALgAECgcJBwAAAA==.Sarang:BAAALgAECgEJAwAAAA==.Sarrsaras:BAAALgAECgYJCQABLgAECgcJGAATANQbAA==.Sathia:BAAALgADCgYJBgABLgAECgkJLgARANQcAA==.',
Sc='Scale:BAAALgAECgQJBAAAAA==.',
Se='Seaursus:BAAALgAECgMJCAAAAA==.Seerblade:BAAALgADCgcJCgABLgAECgYJCwAEAAAAAA==.Sekaiju:BAAALgAECgQJBgAAAA==.Selakin:BAAALgADCgIJAgAAAA==.',
Sh='Shadowbann:BAAALgAECgcJDAAAAA==.Shadowrunner:BAAALgAECgEJAQAAAA==.Shammydavis:BAAALgADCgEJAQAAAA==.Shamwich:BAAALgAECgkJEgAAAA==.Shandroz:BAAALgAECgUJBQAAAA==.Shaori:BAAALgADCgMJBAAAAA==.Shortzo:BAAALgAECgcJCwABLgAFFAUJFgAmAHAeAA==.Shrkbait:BAAALgAECgUJCgAAAA==.',
Si='Sikozu:BAAALgAECgIJAwAAAA==.',
Sk='Skeezicks:BAAALgADCgUJBQAAAA==.Skidoosh:BAAALgAECgEJAwAAAA==.Skullcleaver:BAAALgADCgcJFAAAAA==.',
Sl='Slycc:BAAALgAECgMJAwAAAA==.',
Sm='Smackerr:BAAALgADCgUJBgAAAA==.Smexybeasty:BAAALgAECgYJBgABLgAECggJFgADAL0eAA==.',
Sn='Sneakay:BAABLgAFFH8GAAIfAAMJqQV6EACwAAAfAAMJqQV6EACwAAAAAA==.Sneakybiter:BAAALgADCgcJDQAAAA==.',
So='Solei:BAAALgAECgUJBQAAAA==.Southernguy:BAAALgAECgMJBAAAAA==.',
Sp='Spazzies:BAAALgAECgcJEQAAAA==.',
Sq='Squigglybutt:BAABLgAECn83AAMVAAcJkR8RDwB3AgAVAAcJkR8RDwB3AgAIAAUJJxe/MABaAQAAAA==.',
St='Steelwing:BAAALgAFFAMJAwAAAA==.Stormbeards:BAAALgADCgYJBgAAAA==.Stoutkeg:BAAALgADCgQJAwAAAA==.Strixmonk:BAEALgAFFAIJAwABLgAFFAYJGgAdAC4eAA==.Strrawberry:BAAALgADCgIJAgAAAA==.Stêven:BAAALgAECggJCAAAAA==.Störmî:BAAALgAECgYJBwAAAA==.',
Su='Sungchaluka:BAAALgAECgUJEgAAAA==.',
Sy='Sylvath:BAAALgAECgEJAgAAAA==.Syntt:BAAALgAECgEJAQAAAA==.',
['Sá']='Sásu:BAAALgADCgkJFQAAAA==.',
Ta='Talsomething:BAAALgAFFAEJAgAAAA==.Talsumthing:BAABLgAFFH8JAAIcAAUJqwS2JgDsAAAcAAUJqwS2JgDsAAAAAA==.Tars:BAAALgAECgYJBgAAAA==.Tats:BAABLgAECn8lAAIRAAkJ+xtsNAAvAgARAAkJ+xtsNAAvAgAAAA==.Tatsumâ:BAABLgAECn8ZAAIOAAYJlxUaIwA3AQAOAAYJlxUaIwA3AQAAAA==.',
Te='Terraxic:BAAALgAECgYJDAAAAA==.Terthaith:BAABLgAECn8YAAITAAkJKwwoXgCFAQATAAkJKwwoXgCFAQAAAA==.Tezguin:BAAALgADCgYJDQAAAA==.',
Th='Theedemon:BAAALgAECgQJBAAAAA==.Theironie:BAAALgADCgYJBgAAAA==.Theparttimer:BAAALgADCgEJAQAAAA==.Thiccpie:BAAALgAECgYJCwAAAA==.Throdwran:BAAALgAECgYJDAABLgAECgkJLgARANQcAA==.',
Ti='Timba:BAAALgAECgYJCAAAAA==.Tisaka:BAABLgAECn8aAAIaAAYJAxmZJQDMAQAaAAYJAxmZJQDMAQAAAA==.',
Tl='Tlovexx:BAAALgAFFAEJAQAAAA==.',
To='Tolya:BAAALgAECgEJAQAAAA==.Toohbooh:BAAALgAECgMJBgAAAA==.Totem:BAAALgAECgcJDAAAAA==.',
Tr='Tranqx:BAACLgAFFH8XAAMdAAQJWSaNKQDDAQAdAAQJWSaNKQDDAQAeAAMJiCLuDwAYAQAuAAQKfzkAAx4ACQnpJq4BABYDAB0ACAm1JlUIAFwDAB4ACAmnJq4BABYDAAAA.Treevlo:BAAALgADCgEJAQAAAA==.Treva:BAABLgAECn8hAAQGAAkJ9RmTIADVAQAGAAkJ9RmTIADVAQAlAAQJtAYrLgCoAAAiAAEJZQPfSgAsAAAAAA==.Trizz:BAAALgAFFAEJAQAAAA==.Troctzul:BAAALgADCgEJAwAAAA==.Trollmachine:BAAALgAECgcJDAABLgAECggJFgADAL0eAA==.',
Ts='Tsuchiya:BAABLgAECn8UAAIKAAgJ5wa1jwABAQAKAAgJ5wa1jwABAQAAAA==.',
Tu='Tuts:BAAALgADCgYJDAAAAA==.',
Ty='Tythos:BAAALgADCgYJCwAAAA==.',
Up='Uproar:BAACLgAFFH8MAAIeAAUJOx2iCQBWAQAeAAUJOx2iCQBWAQAuAAQKfy4AAh4ACQlDJYYBACADAB4ACQlDJYYBACADAAAA.',
Va='Vaelira:BAAALgADCgkJCQAAAA==.Vahlfi:BAACLgAFFH8HAAIKAAMJviC2bgCtAAAKAAMJviC2bgCtAAAuAAQKfxwABAoACQljJFIPAMkCAAoACQljJFIPAMkCAAsAAQm6IvBWAGEAACcAAgkTEUc1ADAAAAEuAAUUBwkdABsA/SMA.Valedormu:BAAALgAFFAIJAwAAAA==.Valeskogr:BAABLgAECn8dAAQNAAkJAg59YQCDAQANAAgJZw59YQCDAQAmAAcJjQjeFAB6AQABAAgJmAN0UAAMAQAAAA==.Valffi:BAAALgAFFAEJAQABLgAFFAcJHQAbAP0jAA==.Varoth:BAAALgAECgEJAQAAAA==.Varus:BAAALgAECgYJCQAAAA==.',
Ve='Velisá:BAAALgAECgIJAgAAAA==.Vengefulmilk:BAAALgAECgUJDgAAAA==.Venture:BAAALgADCgkJIgAAAA==.Vergo:BAAALgADCgEJAQAAAA==.Vescovo:BAABLgAECn8rAAQIAAkJFCCPBgAWAwAIAAkJFCCPBgAWAwAWAAUJ0RXRQgAEAQAVAAEJrh+jdABWAAAAAA==.',
Vi='Virde:BAAALgADCgMJAwAAAA==.',
Vl='Vll:BAABLgAECn8iAAILAAgJ7iKwBwC1AgALAAgJ7iKwBwC1AgABLgAECgkJJwANALUbAA==.',
Vo='Volkihar:BAAALgAFFAIJAwAAAA==.Vordt:BAAALgAECgIJBwAAAA==.',
Wa='Wardaorm:BAABLgAECn8fAAIhAAYJDg79TQAPAQAhAAYJDg79TQAPAQABLgAECgkJLgARANQcAA==.Warkinz:BAAALgADCgQJBQAAAA==.Warlin:BAAALgAECgEJAQAAAA==.',
We='Welordron:BAAALgADCgEJAQAAAA==.',
Wi='Willohh:BAAALgAECgQJBAAAAA==.Winden:BAABLgAECn8WAAIMAAYJhhtNGABGAQAMAAYJhhtNGABGAQAAAA==.Wingback:BAAALgAECgkJBQAAAA==.Wiz:BAAALgAECgYJDgAAAA==.',
Wp='Wphoenix:BAAALgAECgQJBAAAAA==.',
Wr='Wrizz:BAAALgADCgYJCAAAAA==.',
Wt='Wtfsteve:BAAALgADCgUJBQABLgAECggJFwAXAEgZAA==.',
Xa='Xadrai:BAAALgAECgYJCwAAAA==.',
Xe='Xeplin:BAAALgAECgUJCQAAAA==.',
Xh='Xhenshini:BAACLgAFFH8OAAMGAAUJpgzeAwD5AAAGAAUJpgzeAwD5AAAlAAEJtwbMCgBPAAAuAAQKf0IAAwYACQlOIf4FAPwCAAYACQkcIf4FAPwCACUACAmqGjEJAE4CAAAA.',
Xk='Xkrin:BAAALgAECgEJAQAAAA==.',
Ye='Yeonguo:BAAALgAECgYJDgAAAA==.',
Yu='Yums:BAAALgAECgEJAgAAAA==.',
Za='Zalethe:BAAALgAECgMJAwAAAA==.Zalliel:BAAALgADCggJCAAAAA==.Zalman:BAAALgAECgMJBQAAAA==.Zaphíel:BAAALgADCgcJBwABLgAECgkJGAATACsMAA==.Zaran:BAABLgAECn8XAAIRAAgJWhK5dACEAQARAAgJWhK5dACEAQAAAA==.',
Ze='Zeninnaoya:BAABLgAECn8fAAMSAAkJuSD6AABaAwASAAkJ3B36AABaAwAhAAcJISaFDgDgAgAAAA==.',
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
