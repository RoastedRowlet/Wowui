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

local lookup = {'Hunter-Marksmanship','Druid-Feral','Druid-Balance','Unknown-Unknown','Shaman-Elemental','Evoker-Devastation','Monk-Mistweaver','Priest-Discipline','Mage-Frost','DemonHunter-Devourer','DemonHunter-Havoc','Shaman-Enhancement','Hunter-BeastMastery','Druid-Guardian','Druid-Restoration','Warrior-Protection','Paladin-Retribution','Warrior-Arms','Evoker-Augmentation','Warlock-Demonology','Warlock-Affliction','DeathKnight-Blood','Priest-Holy','Priest-Shadow','Monk-Brewmaster','Monk-Windwalker','Paladin-Protection','Rogue-Subtlety','Rogue-Assassination','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Destruction','Mage-Arcane','Warrior-Fury','Evoker-Preservation','Rogue-Outlaw','Shaman-Restoration','Hunter-Survival','DemonHunter-Vengeance',}
local provider = {region='US',realm="Drak'thul",name='US',type='weekly',zone=46,date='2026-07-05',data={Aa='Aalluntic:BAAALgAECgYJBgAAAA==.',
Ad='Ador:BAAALgAECgUJBQAAAA==.',
Ae='Aeladrel:BAAALgADCggJCAAAAA==.',
Ak='Akirie:BAABLgAECn8aAAIBAAYJDxeRFAAZAQABAAYJDxeRFAAZAQAAAA==.Akumu:BAABLgAECn8eAAMCAAkJrRtVBQC5AgACAAkJrRtVBQC5AgADAAEJAACMsAAAAAABLgAFFAMJAwAEAAAAAA==.Akumua:BAAALgAECgQJBAABLgAFFAMJAwAEAAAAAA==.',
Al='Alangi:BAABLgAECn8ZAAIFAAcJjgxrTQAAAQAFAAcJjgxrTQAAAQABLgAFFAUJEgAGAPoNAA==.Albinah:BAABLgAECn8dAAIHAAcJAB2aHwAeAgAHAAcJAB2aHwAeAgAAAA==.Albsli:BAAALgADCgIJAgAAAA==.Albsygos:BAAALgADCgQJBAAAAA==.Albz:BAAALgADCgkJHAAAAA==.Albzap:BAAALgADCgMJAwAAAA==.Albzley:BAABLgAECn8pAAIIAAkJXBlnDQCXAgAIAAkJXBlnDQCXAgAAAA==.Albzu:BAAALgAECgUJBQAAAA==.Aldien:BAABLgAECn8YAAIJAAYJ4AbT3gDcAAAJAAYJ4AbT3gDcAAAAAA==.Aliphar:BAAALgADCgEJAQAAAA==.Allaria:BAAALgAECgYJBgAAAA==.',
Ao='Aoe:BAACLgAFFH8bAAIKAAUJ9xT8RAAYAQAKAAUJ9xT8RAAYAQAuAAQKfyMAAgoACQlAHkcQAMACAAoACQlAHkcQAMACAAEuAAUUBgkUAAsA6hoA.',
Ar='Arcanism:BAAALgAECgYJCwAAAA==.Arealaz:BAAALgAECgkJBgAAAA==.Arienna:BAAALgAECgMJAwAAAA==.Arteñ:BAAALgAECgUJCQAAAA==.',
As='Ashrak:BAABLgAECn8jAAIMAAcJARMQFQBtAQAMAAcJARMQFQBtAQAAAA==.',
At='Attitudyjudy:BAAALgAECgYJBgAAAA==.',
Au='Augment:BAEALgADCgMJAwABLgAECgcJEwAEAAAAAA==.',
Av='Averroes:BAACLgAFFH8GAAINAAMJ6AmaaQDSAAANAAMJ6AmaaQDSAAAuAAQKf0MAAg0ACQkaGlIeAHACAA0ACQkaGlIeAHACAAAA.',
Aw='Awee:BAACLgAFFH8UAAILAAYJ6hrKBADKAQALAAYJ6hrKBADKAQAuAAQKf0sAAgsACQkwJMADABcDAAsACQkwJMADABcDAAAA.Awi:BAAALgADCgUJBQABLgAFFAYJFAALAOoaAA==.Awo:BAACLgAFFH8SAAMOAAUJTCMXBgCaAQAOAAUJTCMXBgCaAQAPAAQJvR4KHAB6AQAuAAQKfzgABA8ACAlmJUMGAFMDAA8ACAlmJUMGAFMDAA4ACAklHzEJAFgCAAIABgmIFkIUAG4BAAEuAAUUCAkSABAAVxQA.Awoo:BAAALgAECgYJBwABLgAFFAgJEgAQAFcUAA==.',
Ay='Aylen:BAABLgAECn8eAAIRAAkJ6A5hcQCLAQARAAkJ6A5hcQCLAQAAAA==.',
Ba='Babsvilla:BAABLgAECn8aAAISAAYJ5APcXQBnAAASAAYJ5APcXQBnAAAAAA==.Badmagi:BAAALgAECgEJAQAAAA==.Bahldrahg:BAAALgAECgMJAwAAAA==.Baki:BAACLgAFFH8VAAITAAUJMxycIwBFAQATAAUJMxycIwBFAQAuAAQKfxwAAhMACQn+JKsCAE4DABMACQn+JKsCAE4DAAAA.Banegrim:BAABLgAECn9PAAMUAAkJihMzCgD3AAAUAAkJihMzCgD3AAAVAAQJ2xGuBACxAAAAAA==.Bankisa:BAAALgAECgYJEAAAAA==.Banktulo:BAAALgAECgQJBgAAAA==.Barnbirt:BAAALgAECgEJAQAAAA==.Barron:BAAALgAECgIJAgAAAA==.Barronthee:BAAALgAECgIJAgAAAA==.Battlecat:BAABLgAECn8cAAIJAAgJjhI6bwCcAQAJAAgJjhI6bwCcAQAAAA==.',
Be='Beelzebubx:BAAALgAECgQJBAABLgAFFAMJAwAEAAAAAA==.Belysiuh:BAAALgAECgMJAwAAAA==.',
Bl='Blackdaisydr:BAAALgADCgcJDQABLgAECgYJCwAEAAAAAA==.Blindwalker:BAABLgAECn8hAAIWAAkJeQ23KQAJAQAWAAkJeQ23KQAJAQAAAA==.Blissfuleigh:BAAALgAECgIJAwAAAA==.Bloodbarron:BAAALgAECgYJCgAAAA==.',
Bo='Boldius:BAAALgADCgQJBAABLgAECgUJBQAEAAAAAA==.Bookchin:BAAALgADCgEJAQAAAA==.Bootylust:BAAALgADCgYJBgABLgAECgcJPAAXABEgAA==.',
Br='Bragdand:BAEALgAECgcJEwAAAA==.Braistlin:BAAALgADCgIJAgABLgAECgUJBQAEAAAAAA==.Bred:BAAALgADCgcJBwAAAA==.Brewfest:BAAALgADCgMJBgAAAA==.Briarthorn:BAAALgAECgYJBgAAAA==.',
Bu='Bubblegump:BAAALgAECgIJAgAAAA==.Bulin:BAAALgADCgQJBAAAAA==.',
['Bü']='Büdwèiserr:BAAALgAECgQJDQAAAA==.',
Ca='Cadillacbob:BAAALgAECgIJAwAAAA==.Calon:BAAALgAECgQJBQAAAA==.Cantseedizz:BAAALgADCgMJAwAAAA==.Castigate:BAACLgAFFH8fAAMYAAcJ+BwzCADpAQAYAAYJJiIzCADpAQAXAAEJKiOnDwBqAAAuAAQKfy4AAhgACQmHIrIIAMMCABgACQmHIrIIAMMCAAAA.',
Ce='Cederek:BAAALgADCgIJAgAAAA==.Ceresarian:BAAALgADCgMJAwAAAA==.',
Ch='Chancho:BAABLgAECn8VAAIZAAYJIAlCBgCSAAAZAAYJIAlCBgCSAAABLgAECgkJQQAOAA4RAA==.Cheesekitten:BAAALgADCgEJAQABLgAFFAMJCgARABIkAA==.Cheesemonk:BAABLgAECn8aAAMaAAkJ+SN0AgBFAwAaAAkJ+SN0AgBFAwAZAAcJGSKLDgBRAgABLgAFFAMJCgARABIkAA==.Cheesepally:BAACLgAFFH8KAAIRAAMJEiRvOQA5AQARAAMJEiRvOQA5AQAuAAQKf0EAAhEACQnCJqsBAH4DABEACQnCJqsBAH4DAAAA.Cheesewhelp:BAAALgADCgcJBwAAAA==.Chikoung:BAAALgADCgUJBQAAAA==.Chudmourne:BAAALgAECgUJBgABLgAECgkJLQAaAH8WAA==.',
Cl='Cloud:BAABLgAECn8oAAMbAAkJbCPEAQApAwAbAAkJbCPEAQApAwARAAIJfhUWNwF2AAAAAA==.',
Co='Coderictond:BAAALgADCgQJBgAAAA==.Cogpally:BAAALgADCggJCAAAAA==.',
Cr='Crysa:BAAALgADCgYJBgAAAA==.',
Cy='Cyanide:BAAALgADCgkJCQAAAA==.Cygnus:BAABLgAECn80AAMcAAgJfBWZGQDNAQAcAAgJfBWZGQDNAQAdAAUJfwYrFQDYAAAAAA==.Cylla:BAABLgAECn8fAAINAAcJGiRDHgBwAgANAAcJGiRDHgBwAgABLgAFFAUJJwARAPEfAA==.',
Da='Daddywarbuks:BAAALgAECgUJBgAAAA==.Dagin:BAABLgAECn8uAAIRAAkJ1Bx+IgB8AgARAAkJ1Bx+IgB8AgAAAA==.Dalarenaric:BAAALgADCgcJDAAAAA==.Dalt:BAAALgAFFAEJAQAAAA==.Daltonator:BAAALgADCgMJAwAAAA==.Dantemore:BAABLgAECn8aAAICAAcJlxdOEgCWAQACAAcJlxdOEgCWAQAAAA==.Daorcy:BAAALgADCggJDgAAAA==.Dartherd:BAABLgAECn9HAAIQAAkJhhwLAQARAgAQAAkJhhwLAQARAgAAAA==.Dawnotheholy:BAABLgAECn9PAAQeAAkJCRMQAwCKAQAeAAkJCRMQAwCKAQARAAcJJBCmswAaAQAbAAQJABAgKwDCAAAAAA==.',
De='Deathbyone:BAAALgAECgkJCwAAAA==.Deathstar:BAACLgAFFH8sAAQfAAgJoxvnFgAnAgAfAAYJ7x3nFgAnAgAgAAUJTBanBQCZAQAWAAEJAADRTwAAAAAuAAQKfy8AAx8ACQkSJK8NAP8CAB8ACQkSJK8NAP8CACAAAwl+DQISAHEAAAAA.Deliverhealz:BAAALgAECgYJBgAAAA==.Demonbunz:BAAALgADCgUJBwAAAA==.Derregar:BAABLgAECn8cAAMUAAcJFx7eUgCjAQAUAAcJpx3eUgCjAQAhAAIJ0RL1SACTAAAAAA==.Dezamius:BAABLgAECn8VAAMLAAgJLRJyBAAkAQALAAgJLRJyBAAkAQAKAAYJCQQKzACZAAABLgAFFAUJEgAGAPoNAA==.',
Di='Dibella:BAAALgADCgYJAwAAAA==.Dingwang:BAAALgADCgUJBQAAAA==.Dirtydrago:BAAALgADCgUJBgABLgAECgUJBQAEAAAAAA==.Dirtymon:BAAALgADCgMJAwABLgAECgUJBQAEAAAAAA==.',
Dk='Dkfatality:BAACLgAFFH8NAAMgAAMJsR8fFADsAAAgAAMJsR8fFADsAAAfAAEJow5XVABPAAAuAAQKfy8AAyAACQmSI+wBAAgDACAACQmSI+wBAAgDAB8ABgl/IQ5dANsBAAAA.',
Dl='Dlord:BAAALgADCgYJCAAAAA==.',
Do='Dock:BAAALgAECgQJCQAAAA==.Dockin:BAAALgAECgUJBQAAAA==.Dominbros:BAAALgAECgYJCgABLgAECgYJFwAJAJYWAA==.Dominhoes:BAABLgAECn8XAAIJAAYJlhYglgBMAQAJAAYJlhYglgBMAQAAAA==.Dondon:BAAALgAECgQJBgAAAA==.Doontless:BAAALgAECgYJEQAAAA==.Doyouknow:BAAALgAECgMJAwAAAA==.',
Dr='Draig:BAABLgAECn8VAAMJAAcJ2QnDvQANAQAJAAcJ2wjDvQANAQAiAAIJWwe+GQBKAAAAAA==.Dratini:BAAALgADCggJBwABLgAECggJFwAaAEgZAA==.Drozigg:BAAALgADCgYJCQAAAA==.',
Du='Duckfury:BAABLgAECn8gAAIjAAgJ8RD1LgCUAQAjAAgJ8RD1LgCUAQABLgAECgkJEwAEAAAAAA==.Duckmourne:BAAALgAECgkJEwAAAA==.Dummy:BAAALgADCgYJBgAAAA==.Dunzoboom:BAAALgADCgcJCwAAAA==.Dunzö:BAAALgADCgYJBgAAAA==.',
['Dë']='Dëad:BAAALgAECgQJBgAAAA==.',
['Dö']='Döom:BAAALgAECgIJAgAAAA==.',
Eb='Ebonhèart:BAABLgAECn8ZAAMSAAgJygswKAAtAQASAAgJygswKAAtAQAjAAEJwwUBqgA0AAAAAA==.',
Ec='Echoez:BAACLgAFFH8KAAMHAAQJkRGrHACcAAAHAAMJIQ+rHACcAAAaAAMJPgUKDgCAAAAuAAQKfxQAAgcABglXF9g3AJMBAAcABglXF9g3AJMBAAAA.Ecliptic:BAAALgAECgQJDQAAAA==.',
Eg='Eggle:BAAALgADCgIJAgAAAA==.',
Ei='Eisenheim:BAAALgADCgIJAgAAAA==.',
El='Electronvolt:BAABLgAECn8ZAAIkAAgJrBVzDQD5AQAkAAgJrBVzDQD5AQAAAA==.Eleidie:BAAALgADCgEJAQAAAA==.Elia:BAAALgAECgEJAQAAAA==.',
Ev='Evilyne:BAAALgADCgUJBwAAAA==.',
Ex='Exíled:BAAALgAECgEJAQAAAA==.',
Fa='Falilesta:BAAALgAECgYJCAAAAA==.Fallenlegion:BAAALgADCgcJBwAAAA==.Fartwizard:BAAALgAECgMJBQABLgAECgcJBwAEAAAAAA==.',
Fe='Felskerri:BAAALgADCgYJBgAAAA==.Fenus:BAAALgADCgIJAgAAAA==.',
Fi='Firebelly:BAAALgAECgMJAwAAAA==.Firerage:BAAALgADCgcJDwABLgAECgMJBgAEAAAAAA==.',
Fl='Flacidmonkey:BAAALgAECgcJDwAAAA==.Flufflenuzs:BAAALgAECgEJAQAAAA==.',
Fo='Fors:BAAALgAECgQJBAAAAA==.Forsäken:BAABLgAECn8VAAIJAAYJoRW0pwCKAQAJAAYJoRW0pwCKAQAAAA==.Forthecross:BAAALgADCgEJAQAAAA==.Forumangel:BAAALgADCgYJCQAAAA==.',
Fr='Freya:BAAALgADCgUJBQAAAA==.Fria:BAAALgAECgcJCAAAAA==.Frombehìnd:BAABLgAFFH8HAAIlAAMJlA96AgDdAAAlAAMJlA96AgDdAAAAAA==.',
Fu='Fubu:BAAALgAECgIJAwAAAA==.',
Ga='Gabenson:BAAALgADCgQJBAAAAA==.',
Ge='Geegnome:BAAALgAECgEJAQAAAA==.',
Gl='Glizzylatte:BAAALgADCgYJBgABLgAECgYJCwAEAAAAAA==.Gloomy:BAABLgAECn9FAAIXAAkJsB4KAQBzAgAXAAkJsB4KAQBzAgAAAA==.',
Gr='Grandbear:BAAALgAFFAEJAwAAAA==.Grandizzle:BAABLgAECn8XAAIKAAgJVA8JXgBvAQAKAAgJVA8JXgBvAQAAAA==.Grandore:BAAALgAECgEJAwAAAA==.',
Gu='Gumbi:BAAALgAECgIJAgAAAA==.Gumgum:BAACLgAFFH8YAAMVAAQJliXzAQCgAQAVAAQJliXzAQCgAQAhAAEJ4CFqGQBiAAAuAAQKfzYAAhUACAlYJg0BAP8CABUACAlYJg0BAP8CAAAA.Guruprime:BAAALgADCgYJCAAAAA==.',
Gw='Gwalla:BAAALgAECgcJBwAAAA==.',
Ha='Hagniy:BAABLgAECn9dAAIeAAkJ8x5wCQD0AgAeAAkJ8x5wCQD0AgAAAA==.Hakunamatata:BAAALgADCgUJBQAAAA==.Halten:BAAALgAECgkJBwAAAA==.Happyboy:BAABLgAECn8fAAQPAAYJjh+GJwAUAgAPAAYJjh+GJwAUAgAOAAYJ+BufGACLAQACAAEJ0BxhRABSAAABLgAFFAgJEgAQAFcUAA==.Hardrockcafe:BAAALgADCgYJAwAAAA==.Harfu:BAAALgAECgIJAgAAAA==.Hartzdrell:BAAALgADCgcJDAAAAA==.Hashirama:BAABLgAFFH8PAAICAAUJXiEvAQB0AQACAAUJXiEvAQB0AQABLgAFFAUJFQATADMcAA==.',
He='Healmedaddy:BAAALgADCgEJAQAAAA==.Helbrandt:BAAALgAECgMJAwAAAA==.Heldarram:BAAALgAECgkJEQAAAA==.Hemaroid:BAAALgADCgcJBwAAAA==.Heolt:BAEALgADCgYJBwABLgAECgcJEwAEAAAAAA==.Hestia:BAAALgAECgUJBgAAAA==.Hexra:BAACLgAFFH8WAAIkAAUJzB9hDQDJAQAkAAUJzB9hDQDJAQAuAAQKfx4AAiQACQnIISQFAPoCACQACQnIISQFAPoCAAAA.Heyzus:BAAALgAECgYJCQAAAA==.',
Ho='Holyparse:BAAALgAECgEJAQAAAA==.Honnok:BAAALgAECgQJBAAAAA==.Hoofweaver:BAAALgAECgUJBQAAAA==.Hornyhead:BAAALgAECgQJDQAAAA==.Howard:BAAALgADCgIJAgAAAA==.',
Hr='Hrizul:BAABLgAECn80AAMbAAkJrx+SBQCWAgAbAAgJGiGSBQCWAgARAAcJPxFknQA8AQAAAA==.',
Ib='Iblameheals:BAAALgADCgMJBAAAAA==.',
Ic='Icebarron:BAAALgAECgYJDQAAAA==.',
Il='Il:BAABLgAECn8iAAIUAAkJtx4tIACXAgAUAAkJtx4tIACXAgAAAA==.Ilissa:BAAALgAECgQJBQAAAA==.Illisharr:BAAALgADCggJEQAAAA==.Iloveleaf:BAAALgADCgEJAQAAAA==.Ilusive:BAABLgAECn8cAAIFAAgJrhExNwBcAQAFAAgJrhExNwBcAQAAAA==.',
Ir='Irazlynaa:BAAALgADCgUJDgAAAA==.Irielyn:BAAALgAECgUJBQAAAA==.Ironblight:BAAALgAECgEJAQAAAA==.Irrah:BAAALgAECgYJDwAAAA==.',
Is='Ishal:BAAALgADCgEJAQAAAA==.',
Ja='Jabar:BAAALgADCgEJAQAAAA==.Jagz:BAABLgAECn87AAMmAAkJ7B3qFgBeAgAmAAgJBR3qFgBeAgAFAAgJ4h3xFwAkAgAAAA==.',
Jh='Jharael:BAAALgADCgUJBwAAAA==.',
Ji='Jia:BAAALgAECgEJAgAAAA==.',
Jo='Jonsi:BAAALgADCgUJBQABLgAECggJFwAaAEgZAA==.',
Ju='Junö:BAAALgAECgEJAQAAAA==.Jursh:BAAALgADCgQJBAAAAA==.',
Ka='Kaelen:BAABLgAECn8YAAINAAgJ/BlEPQDsAQANAAgJ/BlEPQDsAQAAAA==.Kaley:BAAALgADCgIJAgAAAA==.Kasuo:BAAALgAECgEJAQAAAA==.Katamine:BAABLgAECn9FAAIDAAkJ8RwdDQCGAgADAAkJ8RwdDQCGAgAAAA==.Katoz:BAABLgAECn8aAAMfAAgJHx7POQAYAgAfAAgJHx7POQAYAgAgAAIJTRYvEgBuAAAAAA==.Kawas:BAAALgAECgYJCQAAAA==.',
Ke='Ketamine:BAAALgADCgYJBgABLgAECgYJFwAJAJYWAA==.Keydron:BAAALgADCggJDwAAAA==.',
Kh='Khài:BAAALgAECgQJBQAAAA==.',
Ki='Kickit:BAAALgADCgQJBAAAAA==.Kilemall:BAAALgAECgkJAgAAAA==.Killnall:BAABLgAECn8rAAIRAAgJkwinxAACAQARAAgJkwinxAACAQAAAA==.Kiyohime:BAAALgAECgIJAgAAAA==.',
Kj='Kjadmina:BAAALgADCgUJBAAAAA==.',
Kl='Kladon:BAABLgAECn8gAAIBAAkJJxpyCQDfAQABAAkJJxpyCQDfAQAAAA==.Klozkoth:BAAALgAECgYJBgAAAA==.',
Ko='Konantheduck:BAAALgADCgMJAwABLgAECgkJEwAEAAAAAA==.',
Kr='Krystarin:BAABLgAECn8xAAIPAAkJIRdtGwBqAgAPAAkJIRdtGwBqAgAAAA==.Kryx:BAAALgADCgkJEAAAAA==.Kráytos:BAAALgAECgcJCgAAAA==.',
Kw='Kwan:BAAALgAECgYJBgABLgAECgcJCgAEAAAAAA==.',
Ky='Kynria:BAAALgAECgIJAwAAAA==.',
La='Lallaure:BAAALgADCgQJBAAAAA==.Lambic:BAAALgAECgQJBAAAAA==.Lanma:BAABLgAECn8XAAIaAAgJSBlBEQBvAgAaAAgJSBlBEQBvAgAAAA==.Larpgodx:BAAALgAECgIJAwAAAA==.Lastoran:BAAALgAECgMJBQAAAA==.Lateralus:BAABLgAECn9HAAIGAAkJWiEoAQD+AgAGAAkJWiEoAQD+AgAAAA==.Launcelot:BAABLgAECn8dAAMjAAcJSCKUHwBUAgAjAAYJ+yKUHwBUAgASAAQJRB8FJgA4AQAAAA==.Laurasecord:BAAALgADCgQJBAAAAA==.Lazymage:BAAALgAECgcJDAAAAA==.',
Le='Leanbeef:BAAALgAECgYJBgAAAA==.Lerath:BAAALgAECggJDgAAAA==.Leshy:BAAALgADCgYJBgAAAA==.',
Li='Liferips:BAAALgAECgUJBQAAAA==.Lights:BAACLgAFFH8LAAIYAAMJ1CHJIADuAAAYAAMJ1CHJIADuAAAuAAQKfz8AAxgACQnuJTkCAEoDABgACQnuJTkCAEoDAAgABQmTIH4fANIBAAEuAAUUBQkVABMAMxwA.Littlezo:BAACLgAFFH8WAAInAAUJcB7YCgBwAQAnAAUJcB7YCgBwAQAuAAQKfy0AAicACQl0JYoBAEkDACcACQl0JYoBAEkDAAAA.',
Lo='Lockßulbtwo:BAAALgAECgEJAgAAAA==.Lotus:BAABLgAECn8tAAQaAAkJfxZcFwD5AQAaAAkJNBZcFwD5AQAZAAUJHhVhMQA8AQAHAAYJ5wz3OAAFAQAAAA==.',
Lt='Ltrnck:BAAALgADCgIJAgAAAA==.',
Lu='Lu:BAAALgADCgEJAQAAAA==.Luckbound:BAAALgAECgEJAQABLgAFFAgJEgAQAFcUAA==.Luthonys:BAAALgADCgEJAQAAAA==.',
Ma='Magond:BAAALgAECgIJAgAAAA==.Maiko:BAAALgADCgMJAwAAAA==.Makoha:BAABLgAECn9BAAMOAAkJDhF4GQCDAQAOAAkJDhF4GQCDAQACAAIJ7gtjVAAwAAAAAA==.Makpriest:BAABLgAECn8UAAIYAAYJ5g8SQQALAQAYAAYJ5g8SQQALAQAAAA==.Makwarrior:BAAALgAECgUJBgAAAA==.Malakaii:BAABLgAECn8eAAMMAAkJ4BIYDAAEAgAMAAkJrRIYDAAEAgAFAAYJrhLKQgA+AQAAAA==.Margaes:BAAALgADCgEJAgAAAA==.Mariahh:BAAALgADCgEJAQAAAA==.Masherevo:BAAALgAFFAQJBAABLgAFFAQJEAAFAMMRAA==.Masherkillu:BAACLgAFFH8QAAIFAAQJwxHIDwDcAAAFAAQJwxHIDwDcAAAuAAQKfy4AAgUACQl6GE8VAD4CAAUACQl6GE8VAD4CAAAA.Masherpally:BAACLgAFFH8OAAMRAAMJogy/JADEAAARAAMJogy/JADEAAAbAAEJPgXEGQAuAAAuAAQKfz0AAxEACQnKH/cBAKoCABEACQnKH/cBAKoCABsAAwlVFWwHAH8AAAEuAAUUBAkQAAUAwxEA.Maxdeath:BAABLgAECn8bAAIJAAkJpQ5OgADQAQAJAAkJpQ5OgADQAQAAAA==.Maxopjack:BAAALgAECgEJAgAAAA==.Maztajake:BAABLgAECn8aAAIDAAkJJB+sEQBMAgADAAkJJB+sEQBMAgAAAA==.Mazyjake:BAAALgAECgcJCQABLgAECgkJGgADACQfAA==.Mazzyjake:BAAALgAECgUJBQABLgAECgkJGgADACQfAA==.',
Me='Meadowlark:BAAALgAECgcJDQABLgAFFAQJFwAPAD0aAA==.Medorh:BAAALgADCgYJBgAAAA==.Melchizedic:BAAALgAECgUJEgAAAA==.Merily:BAAALgADCgQJBAAAAA==.',
Mi='Mikeytott:BAAALgADCgQJBQABLgAECgMJAwAEAAAAAA==.Minnie:BAAALgAECgEJAQABLgAECgkJIQATAPUZAA==.',
Mo='Mohgmoment:BAAALgADCgYJBgAAAA==.Moonfare:BAAALgAECgUJBQAAAA==.Mordacity:BAEBLgAECn9HAAIoAAkJJQnCAQAxAQAoAAkJJQnCAQAxAQAAAA==.',
Mu='Muris:BAAALgAECgQJBAAAAA==.',
['Mä']='Määt:BAAALgADCgIJAgAAAA==.',
Na='Nardo:BAAALgAECgEJAQAAAA==.',
Ne='Necrot:BAAALgAECgEJAQAAAA==.Nelaras:BAAALgADCgYJBgAAAA==.',
Ng='Nghtíy:BAABLgAECn8aAAIfAAYJQBO1vAACAQAfAAYJQBO1vAACAQAAAA==.',
Ni='Nidus:BAAALgAECgEJAQAAAA==.Nixa:BAAALgADCgUJBQAAAA==.',
No='Noahstewie:BAAALgADCgcJBwAAAA==.Nocturnüs:BAABLgAECn8vAAIYAAkJuhKnGgDwAQAYAAkJuhKnGgDwAQAAAA==.Noh:BAAALgAECgQJBQAAAA==.Nordikmage:BAABLgAECn8jAAMJAAkJAhRxQAAbAgAJAAkJAhRxQAAbAgAiAAEJPwVSIAAuAAAAAA==.Nort:BAAALgADCgEJAgAAAA==.',
['Nê']='Nêcrömane:BAAALgAECgUJCAAAAA==.',
['Në']='Nëssa:BAAALgAECgIJAgABLgAECgYJCgAEAAAAAA==.',
Oh='Ohtheirone:BAAALgADCgYJBgAAAA==.Ohtheironey:BAAALgADCgUJBQAAAA==.Ohtheironie:BAAALgADCgYJBgAAAA==.',
On='Ondereth:BAAALgAECggJEAAAAA==.Onthehouse:BAAALgAFFAIJAgAAAA==.',
Oo='Oohkillem:BAAALgAECgMJAwAAAA==.',
Or='Orid:BAAALgADCgcJBwAAAA==.Orvannan:BAAALgADCgQJCAAAAA==.',
Pa='Pacho:BAAALgADCgUJBQAAAA==.Palimorea:BAEALgAECgQJBAABLgAECgcJEwAEAAAAAA==.Pallypower:BAAALgAECgYJBgAAAA==.',
Pi='Piercey:BAACLgAFFH8SAAMQAAgJVxRfBwDLAQAQAAgJVxRfBwDLAQASAAEJOhC+PwBLAAAuAAQKfysAAxAACAntHr4KAGUCABAACAntHr4KAGUCABIAAQn4H0ViAF0AAAAA.Pinkylove:BAABLgAECn8kAAIPAAgJ8iBODADcAgAPAAgJ8iBODADcAgAAAA==.',
Pr='Proera:BAAALgAECgcJCQAAAA==.Promathia:BAACLgAFFH8nAAQRAAUJ8R+CDQBKAQARAAUJ8R+CDQBKAQAbAAMJ9iAPBwAMAQAeAAUJnAzWKADeAAAuAAQKf1wABBEACQnOJuUAAI0DABEACQnOJuUAAI0DAB4ABAkXCCVuAMIAABsAAQkDJYA9AGcAAAAA.Pross:BAAALgAECgUJDAABLgAECgkJLgARANQcAA==.',
Ps='Psychopath:BAABLgAECn8aAAMcAAYJohYVLACeAQAcAAYJohYVLACeAQAdAAEJtwYkIAAyAAAAAA==.',
Pu='Puff:BAAALgAECggJDQAAAA==.',
Qu='Quicksotaka:BAAALgADCgcJBgAAAA==.',
Ra='Raenori:BAAALgADCgYJBgAAAA==.Ragnarolk:BAAALgAECgIJAgAAAA==.Rahveyn:BAAALgAECgIJAgAAAA==.Raiyuden:BAAALgAECgEJAQAAAA==.Randydaytona:BAAALgAECgYJCwAAAA==.Rangërdangër:BAACLgAFFH8PAAINAAUJzgYTVwD4AAANAAUJzgYTVwD4AAAuAAQKfxgAAg0ACQmTGQo1ANoBAA0ACQmTGQo1ANoBAAAA.Rat:BAABLgAECn8jAAIYAAkJSSBzBABOAwAYAAkJSSBzBABOAwAAAA==.',
Re='Rectumus:BAAALgADCggJEwAAAA==.Redrouges:BAACLgAFFH8LAAIcAAQJDxYPDQD1AAAcAAQJDxYPDQD1AAAuAAQKfykAAhwACQkNIVIEAPgCABwACQkNIVIEAPgCAAAA.Redwood:BAAALgAECgUJBwAAAA==.Renvskadoosh:BAAALgADCgkJGQABLgAECgcJHgAmAF0JAA==.Revhero:BAAALgAECgQJBAAAAA==.Rexpanda:BAABLgAECn8YAAIHAAYJ1R2CGgDmAQAHAAYJ1R2CGgDmAQAAAA==.',
Ro='Roguetheholy:BAAALgAECgkJBQAAAA==.Ross:BAEALgADCgEJAQABLgAFFAcJFQAHAB0mAA==.Rotawnda:BAAALgAECgYJBwAAAA==.Rotlord:BAAALgAECgYJCgAAAA==.',
Ru='Ruckus:BAAALgAECgYJDAAAAA==.Rumble:BAAALgAECgEJAQAAAA==.Rumrootbeer:BAAALgADCgIJAQAAAA==.',
Ry='Rynn:BAAALgAECgYJDAAAAA==.',
['Rë']='Rëkz:BAAALgAECgMJAwAAAA==.',
['Rì']='Rìppér:BAAALgAECgEJAQABLgAFFAUJFgAkAMwfAA==.',
Sa='Sanelle:BAAALgADCgkJCQABLgAECgkJLAAIABQgAA==.Sapoude:BAAALgAECgcJBwAAAA==.Sarang:BAAALgAECgYJCQAAAA==.Sarrsaras:BAAALgAECgYJCQABLgAECgcJGAAUANQbAA==.Sathia:BAAALgADCgYJBgABLgAECgkJLgARANQcAA==.',
Sc='Scale:BAAALgAECgQJBAAAAA==.',
Se='Seaursus:BAAALgAECgMJCAAAAA==.Seerblade:BAAALgADCgcJCgABLgAECgYJCwAEAAAAAA==.Sekaiju:BAAALgAECgQJBgAAAA==.Selakin:BAAALgADCgIJAgAAAA==.',
Sh='Shadowbann:BAAALgAECgkJEgAAAA==.Shadowrunner:BAAALgAECgEJAQAAAA==.Shammydavis:BAAALgADCgEJAQAAAA==.Shamwich:BAAALgAECgkJEgAAAA==.Shandroz:BAAALgAECgUJBQAAAA==.Shaori:BAAALgADCgMJBAAAAA==.Shortzo:BAAALgAECgcJCwABLgAFFAUJFgAnAHAeAA==.Shrkbait:BAAALgAECgUJCgAAAA==.',
Si='Sikozu:BAAALgAECgIJAwAAAA==.',
Sk='Skeezicks:BAAALgADCgUJBQAAAA==.Skidoosh:BAAALgAECgEJAwAAAA==.Skullcleaver:BAAALgADCgcJFAAAAA==.',
Sl='Slycc:BAAALgAECgMJAwAAAA==.',
Sm='Smackerr:BAAALgADCgUJBgAAAA==.Smexybeasty:BAAALgAECgYJBgABLgAECgkJGgADACQfAA==.',
Sn='Sneakay:BAABLgAFFH8GAAIhAAMJqQV0EACwAAAhAAMJqQV0EACwAAAAAA==.Sneakybiter:BAAALgADCgcJDQAAAA==.',
So='Solei:BAAALgAECgUJBQAAAA==.Southernguy:BAAALgAECgMJBAAAAA==.',
Sp='Spazzies:BAAALgAECgcJEQAAAA==.',
Sq='Squigglybutt:BAABLgAECn88AAMXAAcJESBCAgDUAQAXAAcJESBCAgDUAQAIAAUJJxfCMABaAQAAAA==.',
St='Steelwing:BAAALgAFFAMJAwAAAA==.Stormbeards:BAAALgADCgYJBgAAAA==.Stoutkeg:BAAALgADCgQJAwAAAA==.Strakhov:BAAALgAECgEJAgAAAA==.Strixmonk:BAEALgAFFAIJAwABLgAFFAYJGgAfAC4eAA==.Strrawberry:BAAALgADCgIJAgAAAA==.Stêven:BAAALgAECggJCAAAAA==.Störmî:BAAALgAECgYJBwAAAA==.',
Su='Sunfist:BAAALgADCgkJDAAAAA==.Sungchaluka:BAAALgAECgUJEgAAAA==.',
Sy='Sylvath:BAAALgAECgEJAwAAAA==.Syntt:BAAALgAECgEJAQAAAA==.',
['Sá']='Sásu:BAAALgADCgkJFQAAAA==.',
Ta='Talsomething:BAAALgAFFAEJAgAAAA==.Talsumthing:BAABLgAFFH8JAAIeAAUJqwSzJgDsAAAeAAUJqwSzJgDsAAAAAA==.Talyn:BAAALgAECgEJAQAAAA==.Tars:BAAALgAECgYJBgAAAA==.Tats:BAABLgAECn8lAAIRAAkJ+htsNAAvAgARAAkJ+htsNAAvAgAAAA==.Tatsumâ:BAABLgAECn8eAAIOAAYJlxV2BgDTAAAOAAYJlxV2BgDTAAABLgAECgkJJQARAPobAA==.',
Te='Tefloncon:BAAALgAECgIJAgAAAA==.Terraxic:BAAALgAECgYJDAAAAA==.Terthaith:BAABLgAECn8YAAIUAAkJKwwmXgCFAQAUAAkJKwwmXgCFAQAAAA==.Tezguin:BAAALgADCgYJDQAAAA==.',
Th='Theedemon:BAAALgAECgQJBAAAAA==.Theironie:BAAALgADCgYJBgAAAA==.Theparttimer:BAAALgADCgEJAQAAAA==.Thiccpie:BAAALgAECgYJCwAAAA==.Throdwran:BAAALgAECgYJDAABLgAECgkJLgARANQcAA==.',
Ti='Timba:BAAALgAECgYJCAAAAA==.Tisaka:BAABLgAECn8aAAIcAAYJAxmZJQDMAQAcAAYJAxmZJQDMAQAAAA==.',
Tl='Tlovexx:BAAALgAFFAEJAQAAAA==.',
To='Tolya:BAAALgAECgEJAQAAAA==.Toohbooh:BAAALgAECgMJBgAAAA==.Totem:BAAALgAECgcJDAAAAA==.',
Tr='Tranqx:BAACLgAFFH8XAAMfAAQJWSZ6KQDDAQAfAAQJWSZ6KQDDAQAgAAMJiCLwDwAYAQAuAAQKfzkAAyAACQnpJq4BABYDAB8ACAm1JlUIAFwDACAACAmnJq4BABYDAAAA.Treevlo:BAAALgADCgEJAQAAAA==.Treva:BAABLgAECn8hAAQTAAkJ9RmSIADVAQATAAkJ9RmSIADVAQAGAAQJtAYrLgCoAAAkAAEJZQPfSgAsAAAAAA==.Trizz:BAAALgAFFAEJAQAAAA==.Troctzul:BAAALgADCgEJAwAAAA==.Trollmachine:BAAALgAECgcJDAABLgAECgkJGgADACQfAA==.',
Ts='Tsuchiya:BAABLgAECn8ZAAIKAAgJRggiEgCkAAAKAAgJRggiEgCkAAAAAA==.',
Tu='Tuts:BAAALgADCgYJDAAAAA==.',
Ty='Tythos:BAAALgADCgYJCwAAAA==.',
Up='Uproar:BAACLgAFFH8MAAIgAAUJOx2eCQBWAQAgAAUJOx2eCQBWAQAuAAQKfy4AAiAACQlDJYYBACADACAACQlDJYYBACADAAAA.',
Va='Vaelira:BAAALgADCgkJCQAAAA==.Vahlfi:BAACLgAFFH8IAAIKAAMJviCobgCtAAAKAAMJviCobgCtAAAuAAQKfxwABAoACQljJFAPAMkCAAoACQljJFAPAMkCAAsAAQm6IvFWAGEAACgAAgkTEUo1ADAAAAEuAAUUCAkjAB0ABCMA.Valedormu:BAAALgAFFAIJAwAAAA==.Valeskogr:BAABLgAECn8dAAQNAAkJAg54YQCDAQANAAgJZw54YQCDAQAnAAcJjQjeFAB6AQABAAgJmAN0UAAMAQAAAA==.Valffi:BAAALgAFFAEJAQABLgAFFAgJIwAdAAQjAA==.Varoth:BAAALgAECgEJAQAAAA==.Varus:BAAALgAECgYJCQAAAA==.',
Ve='Velisá:BAAALgAECgIJAgAAAA==.Vengefulmilk:BAAALgAECgUJDgAAAA==.Venture:BAAALgADCgkJIgAAAA==.Vergo:BAAALgADCgEJAQAAAA==.Vescovo:BAABLgAECn8sAAQIAAkJFCCPBgAWAwAIAAkJFCCPBgAWAwAYAAUJ0RXXQgAEAQAXAAEJrh+jdABWAAAAAA==.',
Vi='Virde:BAAALgADCgMJAwAAAA==.',
Vl='Vll:BAABLgAECn8iAAILAAgJ7iKwBwC1AgALAAgJ7iKwBwC1AgAAAA==.',
Vo='Volkihar:BAAALgAFFAIJAwAAAA==.Vordt:BAAALgAECgIJBwAAAA==.',
Wa='Wardaorm:BAABLgAECn8fAAIjAAYJDg4ATgAPAQAjAAYJDg4ATgAPAQABLgAECgkJLgARANQcAA==.Warkinz:BAAALgADCgQJBQAAAA==.Warlin:BAAALgAECgEJAQAAAA==.',
We='Welordron:BAAALgADCgEJAQAAAA==.',
Wi='Willohh:BAAALgAECgQJBAAAAA==.Winden:BAABLgAECn8WAAIMAAYJhhtNGABGAQAMAAYJhhtNGABGAQAAAA==.Wingback:BAAALgAECgkJBQAAAA==.Wiz:BAABLgAECn8WAAIJAAYJfAtXFgDAAAAJAAYJfAtXFgDAAAAAAA==.',
Wp='Wphoenix:BAAALgAECgQJBAAAAA==.',
Wr='Wrizz:BAAALgADCgYJCAAAAA==.',
Wt='Wtfsteve:BAAALgADCgUJBQABLgAECggJFwAaAEgZAA==.',
Xa='Xadrai:BAAALgAECgYJCwAAAA==.',
Xe='Xeplin:BAAALgAECgUJCQAAAA==.',
Xh='Xhenshini:BAACLgAFFH8SAAMGAAUJ+g3uAQDaAAATAAUJpgwxEgDmAAAGAAQJ4gfuAQDaAAAuAAQKf0IAAxMACQlOIf0FAPwCABMACQkcIf0FAPwCAAYACAmqGjEJAE4CAAAA.',
Xk='Xkrin:BAAALgAECgEJAQAAAA==.',
Xn='Xnon:BAAALgADCgMJAwAAAA==.',
Ye='Yeonguo:BAAALgAECgYJDgAAAA==.',
Yu='Yums:BAAALgAECgEJAgAAAA==.',
Za='Zalethe:BAAALgAECgMJAwAAAA==.Zalliel:BAAALgADCggJCAAAAA==.Zalman:BAAALgAECgMJBQAAAA==.Zaphíel:BAAALgADCgcJBwABLgAECgkJGAAUACsMAA==.Zaran:BAABLgAECn8XAAIRAAgJWhK2dACEAQARAAgJWhK2dACEAQAAAA==.',
Ze='Zeninnaoya:BAABLgAECn8fAAMSAAkJuSD6AABaAwASAAkJ3B36AABaAwAjAAcJISaFDgDgAgAAAA==.',
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
