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

local lookup = {'Hunter-Marksmanship','Druid-Feral','Druid-Balance','Unknown-Unknown','Shaman-Elemental','Evoker-Devastation','Monk-Mistweaver','Priest-Discipline','Mage-Frost','Shaman-Enhancement','Hunter-BeastMastery','DemonHunter-Havoc','Druid-Guardian','Druid-Restoration','Warrior-Protection','Paladin-Retribution','Warrior-Arms','Evoker-Augmentation','Warlock-Demonology','Warlock-Affliction','DeathKnight-Blood','Priest-Holy','Priest-Shadow','Monk-Brewmaster','Monk-Windwalker','Paladin-Protection','Rogue-Subtlety','Rogue-Assassination','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Destruction','DemonHunter-Devourer','Mage-Arcane','Warrior-Fury','Evoker-Preservation','Rogue-Outlaw','Shaman-Restoration','Hunter-Survival','DemonHunter-Vengeance',}
local provider = {region='US',realm="Drak'thul",name='US',type='weekly',zone=46,date='2026-08-18',data={Aa='Aalluntic:BAAALgAECgYJBgAAAA==.',
Ad='Ador:BAAALgAECgUJBQAAAA==.',
Ae='Aeladrel:BAAALgADCggJCAAAAA==.Aelaria:BAAALgAECggJEwAAAA==.',
Ak='Akirie:BAABLgAECn8aAAIBAAYJDxeRFAAZAQABAAYJDxeRFAAZAQAAAA==.Akumu:BAABLgAECn8eAAMCAAkJrRtVBQC5AgACAAkJrRtVBQC5AgADAAEJAACMsAAAAAABLgAFFAMJAwAEAAAAAA==.Akumua:BAAALgAECgQJBAABLgAFFAMJAwAEAAAAAA==.',
Al='Alangi:BAABLgAECn8ZAAIFAAcJjgxrTQAAAQAFAAcJjgxrTQAAAQABLgAFFAUJEwAGAPoNAA==.Albinah:BAABLgAECn8dAAIHAAcJAB2aHwAeAgAHAAcJAB2aHwAeAgAAAA==.Albsli:BAAALgADCgIJAgAAAA==.Albsygos:BAAALgADCgQJBAAAAA==.Albz:BAAALgADCgkJHAAAAA==.Albzap:BAAALgADCgMJAwAAAA==.Albzley:BAABLgAECn8pAAIIAAkJXBlnDQCXAgAIAAkJXBlnDQCXAgAAAA==.Albzu:BAAALgAECgUJBQAAAA==.Aldien:BAABLgAECn8YAAIJAAYJ4AbT3gDcAAAJAAYJ4AbT3gDcAAAAAA==.Aliphar:BAAALgADCgEJAQAAAA==.Alunntic:BAAALgAECgQJBAAAAA==.',
An='Andylock:BAAALgAECgEJAQAAAA==.',
Ar='Arcanism:BAAALgAECgYJCwAAAA==.Arealaz:BAAALgAECgkJBgAAAA==.Arienna:BAAALgAECgMJAwAAAA==.Arteñ:BAAALgAECgUJCQAAAA==.',
As='Ashrak:BAABLgAECn8jAAIKAAcJARMQFQBtAQAKAAcJARMQFQBtAQAAAA==.',
At='Attitudyjudy:BAAALgAECgYJBgAAAA==.',
Au='Augment:BAEALgADCgYJCAABLgAECgcJFgALALEMAA==.',
Av='Averroes:BAACLgAFFH8GAAILAAMJ6AmaaQDSAAALAAMJ6AmaaQDSAAAuAAQKf0MAAgsACQkaGlIeAHACAAsACQkaGlIeAHACAAAA.',
Aw='Awi:BAAALgADCgUJBQABLgAFFAYJFAAMAOoaAA==.Awo:BAACLgAFFH8SAAMNAAUJTCMXBgCaAQANAAUJTCMXBgCaAQAOAAQJvR4KHAB6AQAuAAQKfzgABA4ACAlmJUMGAFMDAA4ACAlmJUMGAFMDAA0ACAklHzEJAFgCAAIABgmIFkIUAG4BAAEuAAUUCQkXAA8AOhMA.Awoo:BAAALgAECgYJBwABLgAFFAkJFwAPADoTAA==.',
Ay='Aylen:BAABLgAECn8eAAIQAAkJ6A5hcQCLAQAQAAkJ6A5hcQCLAQAAAA==.',
Ba='Babsvilla:BAABLgAECn8aAAIRAAYJ5APcXQBnAAARAAYJ5APcXQBnAAAAAA==.Badmagi:BAAALgAECgEJAQAAAA==.Bahldrahg:BAAALgAECgMJAwAAAA==.Baki:BAACLgAFFH8VAAISAAUJMxycIwBFAQASAAUJMxycIwBFAQAuAAQKfxwAAhIACQn+JKsCAE4DABIACQn+JKsCAE4DAAAA.Banegrim:BAABLgAECn9TAAMTAAkJPBSgDAA2AQATAAkJPBSgDAA2AQAUAAQJ2xHqCACmAAAAAA==.Bankisa:BAAALgAECgYJEgAAAA==.Banktulo:BAAALgAECgQJCAAAAA==.Barnbirt:BAAALgAECgEJAQAAAA==.Barron:BAAALgAECgIJAgAAAA==.Barronthee:BAAALgAECgIJAgAAAA==.Battlecat:BAABLgAECn8cAAIJAAgJjhI6bwCcAQAJAAgJjhI6bwCcAQAAAA==.',
Be='Beelzebubx:BAAALgAECgQJBAABLgAFFAMJAwAEAAAAAA==.Belysiuh:BAAALgAECgMJAwAAAA==.',
Bl='Blackdaisydr:BAAALgADCgcJDQABLgAECgYJCwAEAAAAAA==.Blindwalker:BAABLgAECn8hAAIVAAkJeQ23KQAJAQAVAAkJeQ23KQAJAQAAAA==.Blissfuleigh:BAAALgAECgIJAwAAAA==.Bloodbarron:BAAALgAECgYJCgAAAA==.',
Bo='Bookchin:BAAALgADCgEJAQAAAA==.Bootylust:BAAALgADCgYJBgABLgAECgkJSQAWAKIeAA==.',
Br='Bragdand:BAEBLgAECn8WAAILAAcJsQygGAAeAQALAAcJsQygGAAeAQAAAA==.Braistlin:BAAALgADCgIJAgABLgAECgUJBQAEAAAAAA==.Bred:BAAALgADCgcJBwAAAA==.Brewfest:BAAALgADCgMJBgAAAA==.Briarthorn:BAAALgAECgYJBgAAAA==.',
Bu='Bubblegump:BAAALgAECgIJAgAAAA==.Builder:BAEALgADCgQJBAABLgAECgcJFgALALEMAA==.Bulin:BAAALgADCgQJBAAAAA==.Burrick:BAEALgADCgYJDAABLgAECgcJFgALALEMAA==.',
['Bü']='Büdwèiserr:BAAALgAECgQJDgAAAA==.',
Ca='Cadillacbob:BAAALgAECgIJAwAAAA==.Calon:BAAALgAECgQJBQAAAA==.Cantseedizz:BAAALgADCgMJAwAAAA==.Castigate:BAACLgAFFH8gAAMXAAgJvBwzCADpAQAXAAcJAyEzCADpAQAWAAEJKiNbGABcAAAuAAQKfy4AAhcACQmHIrIIAMMCABcACQmHIrIIAMMCAAAA.',
Ce='Cederek:BAAALgADCgIJAgAAAA==.Ceresarian:BAAALgADCgMJAwAAAA==.',
Ch='Chancho:BAABLgAECn8ZAAIYAAYJaQzyCAClAAAYAAYJaQzyCAClAAABLgAFFAMJCAANAOAFAA==.Charoite:BAAALgAECgUJBwAAAA==.Cheesekitten:BAAALgADCgEJAQABLgAFFAMJCgAQABIkAA==.Cheesemonk:BAABLgAECn8aAAMZAAkJ+SN0AgBFAwAZAAkJ+SN0AgBFAwAYAAcJGSKLDgBRAgABLgAFFAMJCgAQABIkAA==.Cheesepally:BAACLgAFFH8KAAIQAAMJEiRvOQA5AQAQAAMJEiRvOQA5AQAuAAQKf0EAAhAACQnCJqsBAH4DABAACQnCJqsBAH4DAAAA.Cheesewhelp:BAAALgADCgcJBwAAAA==.Chikoung:BAAALgADCgUJBQAAAA==.Chudmourne:BAAALgAECgUJBgABLgAECgkJLQAZAH8WAA==.',
Cl='Cloud:BAABLgAECn8oAAMaAAkJbCPEAQApAwAaAAkJbCPEAQApAwAQAAIJfhUWNwF2AAAAAA==.',
Co='Coderictond:BAAALgADCgQJBgAAAA==.Cogpally:BAAALgADCggJCAAAAA==.',
Cr='Crysa:BAAALgADCgYJBgAAAA==.',
Cy='Cyanide:BAAALgADCgkJCQAAAA==.Cygnus:BAABLgAECn88AAMbAAkJbhYJAwDKAQAbAAkJbhYJAwDKAQAcAAUJfwYrFQDYAAAAAA==.Cylla:BAABLgAECn8fAAILAAcJGiRDHgBwAgALAAcJGiRDHgBwAgABLgAFFAgJKAAQAPEfAA==.',
Da='Daddywarbuks:BAAALgAECgUJBgAAAA==.Dagin:BAABLgAECn8uAAIQAAkJ1Bx+IgB8AgAQAAkJ1Bx+IgB8AgAAAA==.Dalarenaric:BAAALgADCgcJDAAAAA==.Dalt:BAABLgAECn8VAAMQAAcJhCP9JwBjAgAQAAcJhCP9JwBjAgAdAAMJxxfaDQDPAAAAAA==.Daltonator:BAAALgADCgMJAwAAAA==.Dantemore:BAABLgAECn8aAAICAAcJlxdOEgCWAQACAAcJlxdOEgCWAQAAAA==.Daorcy:BAAALgADCggJDgAAAA==.Dartherd:BAABLgAECn9HAAIPAAkJhhzvBgCYAgAPAAkJhhzvBgCYAgAAAA==.Dawnotheholy:BAABLgAECn9PAAQdAAkJCRMsBgCOAQAdAAkJCRMsBgCOAQAQAAcJJBCmswAaAQAaAAQJABAgKwDCAAAAAA==.',
De='Deathbyone:BAAALgAECgkJDwAAAA==.Deathstar:BAACLgAFFH8uAAQeAAkJCRnnFgAnAgAeAAcJohrnFgAnAgAfAAUJTBanBQCZAQAVAAEJAADRTwAAAAAuAAQKfy8AAx4ACQkSJK8NAP8CAB4ACQkSJK8NAP8CAB8AAwl+DQISAHEAAAAA.Deathtodizz:BAAALgAFFAEJAQAAAA==.Degesina:BAAALgADCgMJAwAAAA==.Deliverhealz:BAAALgAECgcJDQAAAA==.Demonbunz:BAAALgADCgUJBwAAAA==.Derregar:BAABLgAECn8cAAMTAAcJFx7eUgCjAQATAAcJpx3eUgCjAQAgAAIJ0RL1SACTAAAAAA==.Dezamius:BAABLgAECn8VAAMMAAgJLRKECAApAQAMAAgJLRKECAApAQAhAAYJCQQKzACZAAABLgAFFAUJEwAGAPoNAA==.',
Di='Dibella:BAAALgADCgYJAwAAAA==.Dingwang:BAAALgAECgMJAwAAAA==.Dirtydrago:BAAALgADCgUJBgABLgAECgUJBQAEAAAAAA==.Dirtymon:BAAALgADCgMJAwABLgAECgUJBQAEAAAAAA==.',
Dk='Dkfatality:BAACLgAFFH8NAAMfAAMJsR8fFADsAAAfAAMJsR8fFADsAAAeAAEJow5XVABPAAAuAAQKfy8AAx8ACQmSI+wBAAgDAB8ACQmSI+wBAAgDAB4ABgl/IQ5dANsBAAAA.',
Dl='Dlord:BAAALgADCgYJCAAAAA==.',
Do='Dock:BAAALgAECgQJCQAAAA==.Dockin:BAAALgAECgUJBQAAAA==.Dominbros:BAAALgAECgYJCgABLgAECgkJGgAJAHoUAA==.Dominhoes:BAABLgAECn8aAAIJAAkJehQglgBMAQAJAAkJehQglgBMAQAAAA==.Dondon:BAAALgAECgQJBgAAAA==.Doontless:BAAALgAECgYJEQAAAA==.Doyouknow:BAAALgAECgMJAwAAAA==.',
Dr='Draig:BAABLgAECn8WAAMJAAcJ2QnDvQANAQAJAAcJ2wjDvQANAQAiAAIJWwe+GQBKAAAAAA==.Dratini:BAAALgADCggJBwABLgAECggJFwAZAEgZAA==.Drozigg:BAAALgADCgYJCQAAAA==.',
Du='Duckfury:BAABLgAECn8gAAIjAAgJ8RD1LgCUAQAjAAgJ8RD1LgCUAQABLgAECgkJEwAEAAAAAA==.Duckmourne:BAAALgAECgkJEwAAAA==.Dummy:BAAALgADCgYJBgAAAA==.Dunzoboom:BAAALgADCgcJCwAAAA==.Dunzö:BAAALgAECgEJAQAAAA==.',
['Dë']='Dëad:BAAALgAECgQJBgAAAA==.',
['Dö']='Döom:BAAALgAECgIJAgAAAA==.',
Eb='Ebonhèart:BAABLgAECn8ZAAMRAAgJygswKAAtAQARAAgJygswKAAtAQAjAAEJwwUBqgA0AAAAAA==.',
Ec='Echoez:BAACLgAFFH8MAAMHAAUJBwvdHADdAAAHAAUJBwvdHADdAAAZAAMJPgUdFgB5AAAuAAQKfxQAAgcABglXF9g3AJMBAAcABglXF9g3AJMBAAAA.Ecliptic:BAAALgAECgQJDQAAAA==.',
Eg='Eggle:BAAALgADCgIJAgAAAA==.',
Ei='Eisenheim:BAAALgADCgIJAgAAAA==.',
El='Electronvolt:BAABLgAECn8ZAAIkAAgJrBVzDQD5AQAkAAgJrBVzDQD5AQAAAA==.Eleidie:BAAALgADCgEJAQAAAA==.Elia:BAAALgAECgEJAQAAAA==.',
Et='Ettle:BAAALgAECgEJAQAAAA==.',
Ev='Evilyne:BAAALgADCgUJBwAAAA==.',
Ex='Exíled:BAAALgAECgEJAQAAAA==.',
Fa='Falilesta:BAAALgAECggJCwAAAA==.Fallenlegion:BAAALgADCgcJBwAAAA==.Fartwizard:BAAALgAECgMJBQABLgAECgcJBwAEAAAAAA==.',
Fe='Felskerri:BAAALgADCgYJBgAAAA==.Fenus:BAAALgADCgIJAgAAAA==.',
Fi='Firebelly:BAAALgAECgMJAwAAAA==.Firerage:BAAALgADCgcJDwABLgAECggJFQANAIMLAA==.',
Fl='Flacidmonkey:BAAALgAECgcJDwAAAA==.Flufflenuzs:BAAALgAECgEJAQAAAA==.',
Fo='Fors:BAAALgAECgQJBAAAAA==.Forsäken:BAABLgAECn8VAAIJAAYJoRW0pwCKAQAJAAYJoRW0pwCKAQAAAA==.Forthecross:BAAALgADCgEJAQAAAA==.Forumangel:BAAALgADCgYJCQAAAA==.',
Fr='Freya:BAAALgADCgUJBQAAAA==.Fria:BAAALgAECgcJCAAAAA==.Frombehìnd:BAABLgAFFH8JAAIlAAMJlA/kAwDOAAAlAAMJlA/kAwDOAAAAAA==.Frostee:BAAALgADCgIJAgAAAA==.',
Fu='Fubu:BAAALgAECgIJBQAAAA==.',
Ga='Gabenson:BAAALgADCgQJBAAAAA==.',
Ge='Geegnome:BAAALgAECgEJAQAAAA==.',
Gl='Glizzylatte:BAAALgADCgYJBgABLgAECgYJCwAEAAAAAA==.Gloomy:BAABLgAECn9FAAIWAAkJsB5EAgBpAgAWAAkJsB5EAgBpAgAAAA==.',
Gr='Grandbear:BAAALgAFFAEJAwAAAA==.Grandizzle:BAABLgAECn8XAAIhAAgJVA8JXgBvAQAhAAgJVA8JXgBvAQAAAA==.Grandore:BAAALgAECgEJAwAAAA==.',
Gu='Gumbi:BAAALgAECgIJAgAAAA==.Gumgum:BAACLgAFFH8YAAMUAAQJliXzAQCgAQAUAAQJliXzAQCgAQAgAAEJ4CFqGQBiAAAuAAQKfzYAAhQACAlYJg0BAP8CABQACAlYJg0BAP8CAAAA.Guruprime:BAAALgADCgYJCAAAAA==.',
Gw='Gwalla:BAAALgAECgcJBwAAAA==.',
Ha='Hagniy:BAABLgAECn9dAAIdAAkJ8x5wCQD0AgAdAAkJ8x5wCQD0AgAAAA==.Hakunamatata:BAAALgADCgUJBQAAAA==.Halten:BAAALgAECgkJBwAAAA==.Happyboy:BAABLgAECn8fAAQOAAYJjh+GJwAUAgAOAAYJjh+GJwAUAgANAAYJ+BufGACLAQACAAEJ0BxhRABSAAABLgAFFAkJFwAPADoTAA==.Hardrockcafe:BAAALgADCgYJAwAAAA==.Harfu:BAAALgAECgIJAgAAAA==.Hartzdrell:BAAALgADCgcJDAAAAA==.Hashirama:BAABLgAFFH8QAAICAAUJXiEDAwBHAQACAAUJXiEDAwBHAQABLgAFFAUJFQASADMcAA==.',
He='Healmedaddy:BAAALgADCgEJAQAAAA==.Helbrandt:BAAALgAECgMJAwAAAA==.Heldarram:BAAALgAECgkJEQAAAA==.Hemaroid:BAAALgADCgcJBwAAAA==.Heolt:BAEALgADCgYJCAABLgAECgcJFgALALEMAA==.Hestia:BAAALgAECgUJBgAAAA==.Hexra:BAACLgAFFH8YAAIkAAcJuxxhDQDJAQAkAAcJuxxhDQDJAQAuAAQKfx4AAiQACQnIISQFAPoCACQACQnIISQFAPoCAAAA.Heyzus:BAAALgAECgYJCQAAAA==.',
Ho='Holyparse:BAAALgAECgEJAQAAAA==.Honnok:BAAALgAECgQJBAAAAA==.Hoofweaver:BAAALgAECgUJBQAAAA==.Hornyhead:BAAALgAECgQJDQAAAA==.Howard:BAAALgADCgIJAgAAAA==.',
Hr='Hrizul:BAABLgAECn80AAMaAAkJrx+SBQCWAgAaAAgJGiGSBQCWAgAQAAcJPxFknQA8AQAAAA==.',
Ib='Iblameheals:BAAALgADCgMJBAAAAA==.',
Ic='Icebarron:BAAALgAECgYJDQAAAA==.',
Il='Il:BAABLgAECn8iAAITAAkJtx4tIACXAgATAAkJtx4tIACXAgAAAA==.Ilissa:BAAALgAECgQJBQAAAA==.Illisharr:BAAALgADCggJEQAAAA==.Iloveleaf:BAAALgADCgEJAQAAAA==.Ilusive:BAABLgAECn8cAAIFAAgJrhExNwBcAQAFAAgJrhExNwBcAQAAAA==.',
Ir='Irazlynaa:BAAALgADCgUJDgAAAA==.Irielyn:BAAALgAECgUJBQAAAA==.Ironblight:BAAALgAECgEJAQAAAA==.Irrah:BAAALgAECgYJDwAAAA==.',
Is='Ishal:BAAALgADCgEJAQAAAA==.',
Ja='Jabar:BAAALgADCgEJAQAAAA==.Jagz:BAABLgAECn87AAMmAAkJ7B3qFgBeAgAmAAgJBR3qFgBeAgAFAAgJ4h3xFwAkAgAAAA==.',
Jh='Jharael:BAAALgADCgUJBwAAAA==.',
Ji='Jia:BAAALgAECgEJAgAAAA==.',
Jo='Jonsi:BAAALgADCgUJBQABLgAECggJFwAZAEgZAA==.',
Ju='Junö:BAAALgAECgEJAQAAAA==.Jursh:BAAALgADCgQJBAAAAA==.',
Ka='Kaelen:BAABLgAECn8ZAAMLAAgJ/BlEPQDsAQALAAgJ/BlEPQDsAQAnAAEJBhl/EABIAAAAAA==.Kaley:BAAALgADCgIJAgAAAA==.Kasuo:BAAALgAECgEJAQAAAA==.Katamine:BAABLgAECn9FAAIDAAkJ8RwdDQCGAgADAAkJ8RwdDQCGAgAAAA==.Katoz:BAABLgAECn8aAAMeAAgJHx7POQAYAgAeAAgJHx7POQAYAgAfAAIJTRYvEgBuAAAAAA==.Kawas:BAAALgAECgYJCQAAAA==.',
Ke='Ketamine:BAAALgAECgcJBwABLgAECgkJGgAJAHoUAA==.Keydron:BAAALgADCggJDwAAAA==.',
Kh='Khài:BAAALgAECgQJBQAAAA==.',
Ki='Kickit:BAAALgADCgQJBAAAAA==.Kilemall:BAAALgAECgkJAgAAAA==.Killnall:BAABLgAECn8sAAIQAAkJCwmnxAACAQAQAAkJCwmnxAACAQAAAA==.Kiyohime:BAAALgAECgIJAgAAAA==.',
Kj='Kjadmina:BAAALgADCgUJBAAAAA==.',
Kl='Kladon:BAABLgAECn8gAAIBAAkJJxpyCQDfAQABAAkJJxpyCQDfAQAAAA==.Klozkoth:BAAALgAECgYJBgAAAA==.',
Ko='Koinaya:BAAALgAECgMJAwAAAA==.Konantheduck:BAAALgADCgMJAwABLgAECgkJEwAEAAAAAA==.',
Kr='Krystarin:BAABLgAECn84AAIOAAkJURhtGwBqAgAOAAkJURhtGwBqAgAAAA==.Kryx:BAAALgADCgkJEAAAAA==.Kráytos:BAAALgAECgcJCgAAAA==.',
Kw='Kwan:BAAALgAECgcJBwAAAA==.',
Ky='Kynria:BAAALgAECgIJAwAAAA==.',
La='Lallaure:BAAALgADCgQJBAAAAA==.Lambic:BAAALgAECgQJBAAAAA==.Lanma:BAABLgAECn8XAAIZAAgJSBlBEQBvAgAZAAgJSBlBEQBvAgAAAA==.Larpgodx:BAAALgAECgIJAwAAAA==.Lastoran:BAAALgAECgMJBQAAAA==.Lateralus:BAABLgAECn9HAAIGAAkJWiEoAQD+AgAGAAkJWiEoAQD+AgAAAA==.Launcelot:BAABLgAECn8dAAMjAAcJSCKUHwBUAgAjAAYJ+yKUHwBUAgARAAQJRB8FJgA4AQAAAA==.Laurasecord:BAAALgADCgQJBAAAAA==.Lazymage:BAAALgAECgcJDAAAAA==.',
Le='Leanbeef:BAAALgAECgYJBgAAAA==.Lerath:BAAALgAECggJDgAAAA==.Leshy:BAAALgADCgYJBgAAAA==.',
Li='Liferips:BAAALgAECgUJBQAAAA==.Lights:BAACLgAFFH8LAAIXAAMJ1CHJIADuAAAXAAMJ1CHJIADuAAAuAAQKfz8AAxcACQnuJTkCAEoDABcACQnuJTkCAEoDAAgABQmTIH4fANIBAAEuAAUUBQkVABIAMxwA.Lightßulb:BAAALgAECgEJAQAAAA==.Littlezo:BAACLgAFFH8WAAInAAUJcB7YCgBwAQAnAAUJcB7YCgBwAQAuAAQKfy0AAicACQl0JYoBAEkDACcACQl0JYoBAEkDAAAA.',
Lo='Lockßulbtwo:BAAALgAECgEJAgAAAA==.Lotus:BAABLgAECn8tAAQZAAkJfxZcFwD5AQAZAAkJNBZcFwD5AQAYAAUJHhVhMQA8AQAHAAYJ5wz3OAAFAQAAAA==.',
Lt='Ltrnck:BAAALgADCgIJAgAAAA==.',
Lu='Lu:BAAALgADCgEJAQAAAA==.Luckbound:BAAALgAECgEJAQABLgAFFAkJFwAPADoTAA==.Luthonys:BAAALgADCgEJAQAAAA==.',
Ma='Magond:BAAALgAECgIJAgAAAA==.Maiko:BAAALgADCgMJAwAAAA==.Makhunter:BAAALgAECgQJBQAAAA==.Makoha:BAACLgAFFH8IAAINAAMJ4AWAGwBhAAANAAMJ4AWAGwBhAAAuAAQKf0wAAw0ACQnFEhcGAEoBAA0ACQnFEhcGAEoBAAIAAgnuC2NUADAAAAAA.Makpriest:BAABLgAECn8bAAIXAAYJqRbwCgASAQAXAAYJqRbwCgASAQAAAA==.Makwarrior:BAAALgAECgUJCwAAAA==.Malakaii:BAABLgAECn8eAAMKAAkJ4BIYDAAEAgAKAAkJrRIYDAAEAgAFAAYJrhLKQgA+AQAAAA==.Margaes:BAAALgADCgYJBwAAAA==.Mariahh:BAAALgADCgEJAQAAAA==.Masherkillu:BAACLgAFFH8eAAIFAAUJExaVEQAdAQAFAAUJExaVEQAdAQAuAAQKfzMAAgUACQkbHE8VAD4CAAUACQkbHE8VAD4CAAAA.Mashermonkk:BAAALgAECgEJAQABLgAFFAUJHgAFABMWAA==.Masherpally:BAACLgAFFH8TAAMQAAMJXw2GOgCwAAAQAAMJogyGOgCwAAAaAAIJYwwBDQBXAAAuAAQKf0UAAxAACQnWH88DALECABAACQnWH88DALECABoABQn9F/UGAA0BAAEuAAUUBQkeAAUAExYA.Maxdeath:BAABLgAECn8bAAIJAAkJpQ5OgADQAQAJAAkJpQ5OgADQAQAAAA==.Maxopjack:BAAALgAECgEJAgAAAA==.Mayheim:BAAALgADCgUJBQAAAA==.Maztajake:BAABLgAECn8aAAIDAAkJJB+sEQBMAgADAAkJJB+sEQBMAgAAAA==.Mazyjake:BAAALgAECgcJCQABLgAECgkJGgADACQfAA==.Mazzyjake:BAAALgAECgUJBQABLgAECgkJGgADACQfAA==.',
Me='Meadowlark:BAAALgAECgcJDQABLgAFFAQJGAAOAD0aAA==.Medorh:BAAALgADCgYJBgAAAA==.Melchizedic:BAABLgAECn8WAAIaAAUJJRPvCgCyAAAaAAUJJRPvCgCyAAAAAA==.Merily:BAAALgADCgQJBAAAAA==.',
Mi='Mikeytott:BAAALgADCgQJBQABLgAECgMJAwAEAAAAAA==.Minnie:BAAALgAECgEJAQABLgAECgkJIQASAPUZAA==.',
Mo='Mohgmoment:BAAALgADCgYJBgAAAA==.Moonfare:BAAALgAECgUJBQAAAA==.Mordacity:BAABLgAECn9HAAIoAAkJJQk2AwA5AQAoAAkJJQk2AwA5AQAAAA==.',
Mu='Muris:BAAALgAECgQJBAAAAA==.',
['Mä']='Määt:BAAALgADCgIJAgAAAA==.',
Na='Nardo:BAAALgAECgEJAQAAAA==.',
Ne='Necrot:BAAALgAECgEJAQAAAA==.Nelaras:BAAALgADCgYJBgAAAA==.Neàrro:BAAALgADCgkJCQAAAA==.',
Ng='Nghtíy:BAABLgAECn8aAAIeAAYJQBO1vAACAQAeAAYJQBO1vAACAQAAAA==.',
Ni='Nidus:BAAALgAECgEJAwAAAA==.Nixa:BAAALgADCgUJBQAAAA==.',
No='Noahstewie:BAAALgADCgcJBwAAAA==.Nocturnüs:BAABLgAECn8vAAIXAAkJuhKnGgDwAQAXAAkJuhKnGgDwAQAAAA==.Noh:BAAALgAECgQJBQAAAA==.Nordikmage:BAABLgAECn8jAAMJAAkJAhRxQAAbAgAJAAkJAhRxQAAbAgAiAAEJPwVSIAAuAAAAAA==.Nort:BAAALgADCgEJAgAAAA==.Nosrednaxx:BAAALgAECgEJAQAAAA==.',
['Nê']='Nêcrömane:BAAALgAECgUJCgAAAA==.',
['Në']='Nëssa:BAAALgAECgIJAgABLgAECgYJCwAEAAAAAA==.',
Oh='Ohtheirone:BAAALgADCgYJBgAAAA==.Ohtheironey:BAAALgADCgUJBQAAAA==.Ohtheironie:BAAALgADCgYJBgAAAA==.',
On='Ondereth:BAAALgAECgkJEQAAAA==.Onthehouse:BAAALgAFFAIJAwAAAA==.',
Oo='Oohkillem:BAAALgAECgMJAwAAAA==.',
Or='Orid:BAAALgADCgcJBwAAAA==.Orvannan:BAAALgADCgQJCAAAAA==.',
Pa='Pacho:BAAALgADCgUJBQABLgAFFAYJDAAbALoXAA==.Palimorea:BAEALgAECgQJBAABLgAECgcJFgALALEMAA==.Pallypower:BAAALgAECgYJBgAAAA==.',
Pi='Piercey:BAACLgAFFH8XAAMPAAkJOhNfBwDLAQAPAAkJOhNfBwDLAQARAAEJOhC+PwBLAAAuAAQKfysAAw8ACAntHr4KAGUCAA8ACAntHr4KAGUCABEAAQn4H0ViAF0AAAAA.Pinkylove:BAABLgAECn8mAAMOAAkJ3SBODADcAgAOAAgJ8iBODADcAgADAAIJnx0IEgCtAAAAAA==.',
Pr='Priestyßulb:BAAALgAECgEJAQAAAA==.Proera:BAAALgAECgcJCQAAAA==.Promathia:BAACLgAFFH8oAAQQAAUJ8R+hJAB2AQAQAAUJ8R+hJAB2AQAaAAMJ9iAPBwAMAQAdAAUJnAzWKADeAAAuAAQKf14ABBAACQnOJuUAAI0DABAACQnOJuUAAI0DAB0ABAkXCCVuAMIAABoAAQkDJYA9AGcAAAAA.Pross:BAAALgAECgUJDQABLgAECgkJLgAQANQcAA==.',
Ps='Psychopath:BAABLgAECn8aAAMbAAYJohYVLACeAQAbAAYJohYVLACeAQAcAAEJtwYkIAAyAAAAAA==.',
Pu='Puff:BAAALgAECggJDQAAAA==.',
Qu='Quicksotaka:BAAALgADCgcJBgAAAA==.Quintus:BAAALgAECgEJAQAAAA==.',
Ra='Raenori:BAAALgADCgYJBgAAAA==.Ragnarolk:BAAALgAECgIJAgAAAA==.Rahveyn:BAAALgAECgIJAgAAAA==.Raiyuden:BAAALgAECgEJAQAAAA==.Randydaytona:BAAALgAECgYJCwAAAA==.Rangërdangër:BAACLgAFFH8PAAILAAUJzgYTVwD4AAALAAUJzgYTVwD4AAAuAAQKfxgAAgsACQmTGQo1ANoBAAsACQmTGQo1ANoBAAAA.Rat:BAABLgAECn8jAAIXAAkJSSBzBABOAwAXAAkJSSBzBABOAwAAAA==.',
Re='Rectumus:BAAALgADCggJEwAAAA==.Redrouges:BAACLgAFFH8MAAIbAAUJuhcaDQA2AQAbAAUJuhcaDQA2AQAuAAQKfykAAhsACQkNIVIEAPgCABsACQkNIVIEAPgCAAAA.Redwood:BAAALgAECgUJBwAAAA==.Renvskadoosh:BAAALgADCgkJGQABLgAECgcJHgAmAF0JAA==.Revhero:BAAALgAECgQJBAAAAA==.Rexpanda:BAABLgAECn8YAAIHAAYJ1R2CGgDmAQAHAAYJ1R2CGgDmAQAAAA==.',
Ro='Rockchucker:BAAALgAECgUJBQAAAA==.Roguetheholy:BAAALgAECgkJBQAAAA==.Ross:BAEALgADCgEJAQABLgAFFAcJFQAHAAomAA==.Rotawnda:BAAALgAECgYJBwAAAA==.Rotlord:BAAALgAECgYJCgAAAA==.',
Ru='Ruckus:BAAALgAECgYJDQAAAA==.Rumble:BAAALgAECgEJAQAAAA==.Rumrootbeer:BAAALgADCgIJAQAAAA==.',
Ry='Rynn:BAAALgAECgYJDAAAAA==.',
['Rë']='Rëkz:BAAALgAECgMJAwAAAA==.',
['Rì']='Rìppér:BAAALgAECgEJAQABLgAFFAcJGAAkALscAA==.',
Sa='Samot:BAAALgADCgUJBQAAAA==.Sanelle:BAAALgADCgkJCQABLgAECgkJPQAIAEIhAA==.Sapoude:BAAALgAECgcJBwAAAA==.Sarang:BAAALgAECgYJDQAAAA==.Sarrsaras:BAAALgAECgYJCQABLgAECgcJGAATANQbAA==.Sathia:BAAALgADCgYJBgABLgAECgkJLgAQANQcAA==.',
Sc='Scale:BAAALgAECgQJBAAAAA==.',
Se='Seaursus:BAAALgAECgMJCAAAAA==.Seerblade:BAAALgADCgcJCgABLgAECgYJCwAEAAAAAA==.Sekaiju:BAAALgAECgQJBgAAAA==.Selakin:BAAALgADCgIJAgAAAA==.',
Sg='Sgtstutters:BAABLgAFFH8IAAMjAAMJZRNzFgDqAAAjAAMJZRNzFgDqAAAPAAEJ/gWAIgAhAAAAAA==.',
Sh='Shadesearth:BAAALgADCgQJBAAAAA==.Shadowbann:BAAALgAECgkJEwAAAA==.Shadowrunner:BAAALgAECgEJAQAAAA==.Shadybot:BAACLgAFFH8UAAIMAAYJ6hrKBADKAQAMAAYJ6hrKBADKAQAuAAQKf0sAAgwACQkwJMADABcDAAwACQkwJMADABcDAAAA.Shadyowo:BAACLgAFFH8bAAIhAAUJ9xT8RAAYAQAhAAUJ9xT8RAAYAQAuAAQKfyMAAiEACQlAHkcQAMACACEACQlAHkcQAMACAAAA.Shammydavis:BAAALgADCgEJAQAAAA==.Shamwich:BAAALgAECgkJEgAAAA==.Shandroz:BAAALgAECgUJBQAAAA==.Shaori:BAAALgADCgMJBAAAAA==.Shortzo:BAAALgAECgkJDQABLgAFFAUJFgAnAHAeAA==.Shrkbait:BAAALgAECgUJCgAAAA==.',
Si='Sikozu:BAAALgAECgIJAwAAAA==.',
Sk='Skeezicks:BAAALgAECgIJAgAAAA==.Skidoosh:BAAALgAECgEJAwAAAA==.Skullcleaver:BAAALgADCgcJFAAAAA==.',
Sl='Slycc:BAAALgAECgMJAwAAAA==.',
Sm='Smackerr:BAAALgADCgUJBgAAAA==.Smexybeasty:BAAALgAECgYJBgABLgAECgkJGgADACQfAA==.',
Sn='Sneakay:BAABLgAFFH8GAAIgAAMJqQV0EACwAAAgAAMJqQV0EACwAAAAAA==.Sneakybiter:BAAALgADCgcJDQAAAA==.',
So='Solei:BAAALgAECgUJBQAAAA==.Southernguy:BAAALgAECgMJBAAAAA==.',
Sp='Spazzies:BAAALgAECggJEgAAAA==.',
Sq='Squigglybutt:BAABLgAECn9JAAMWAAkJoh4iAgB6AgAWAAkJShwiAgB6AgAIAAgJ7hVtCgA5AQAAAA==.Squishysam:BAAALgAECgIJAgAAAA==.',
St='Steelwing:BAAALgAFFAMJAwAAAA==.Stormbeards:BAAALgADCgYJBgAAAA==.Stoutkeg:BAAALgADCgQJAwAAAA==.Strakhov:BAAALgAECgEJAgAAAA==.Strixmonk:BAEALgAFFAIJAwABLgAFFAkJMwAeAPojAA==.Strrawberry:BAAALgADCgIJAgAAAA==.Stêven:BAAALgAECggJCAAAAA==.Störmî:BAAALgAECgYJBwAAAA==.',
Su='Sunfist:BAABLgAECn8YAAIQAAkJdRhEBgA9AgAQAAkJdRhEBgA9AgAAAA==.Sungchaluka:BAABLgAECn8YAAMgAAUJUwbrLABkAAAgAAQJLwjrLABkAAAUAAUJRwMYDQBiAAAAAA==.',
Sy='Sylvath:BAAALgAECgEJAwAAAA==.Syntt:BAAALgAECgEJAQAAAA==.',
['Sá']='Sásu:BAAALgADCgkJFQAAAA==.',
Ta='Talsomething:BAAALgAFFAEJAgAAAA==.Talsumthing:BAABLgAFFH8OAAMdAAUJqwSzJgDsAAAdAAUJqwSzJgDsAAAQAAUJNwt8JwDsAAAAAA==.Talyn:BAAALgAECgEJAQAAAA==.Tars:BAAALgAECgYJBgAAAA==.Tats:BAABLgAECn8lAAIQAAkJ+htsNAAvAgAQAAkJ+htsNAAvAgABLgAECgkJKwANAG8SAA==.Tatsumâ:BAABLgAECn8rAAINAAkJbxKdBAB/AQANAAkJbxKdBAB/AQAAAA==.',
Te='Tefloncon:BAAALgAECgMJBAAAAA==.Terraxic:BAAALgAECgYJDAAAAA==.Terthaith:BAABLgAECn8YAAITAAkJKwwmXgCFAQATAAkJKwwmXgCFAQAAAA==.Tezguin:BAAALgADCgYJDQAAAA==.',
Th='Theedemon:BAAALgAECgQJBAAAAA==.Theironie:BAAALgADCgYJBgAAAA==.Theparttimer:BAAALgADCgEJAQAAAA==.Thiccpie:BAAALgAECgYJCwAAAA==.Throdwran:BAAALgAECgYJDAABLgAECgkJLgAQANQcAA==.',
Ti='Timba:BAAALgAECgYJCAAAAA==.Tisaka:BAABLgAECn8aAAIbAAYJAxmZJQDMAQAbAAYJAxmZJQDMAQAAAA==.',
Tl='Tlovexx:BAAALgAFFAEJAQAAAA==.',
To='Tolya:BAAALgAECgIJAgAAAA==.Toohbooh:BAAALgAECgMJBgAAAA==.Totem:BAAALgAECggJDAAAAA==.',
Tr='Tranqx:BAACLgAFFH8XAAMeAAQJWSZ6KQDDAQAeAAQJWSZ6KQDDAQAfAAMJiCLwDwAYAQAuAAQKfzkAAx8ACQnpJq4BABYDAB4ACAm1JlUIAFwDAB8ACAmnJq4BABYDAAAA.Treevlo:BAAALgADCgEJAQAAAA==.Trender:BAAALgADCgcJBwAAAA==.Treva:BAABLgAECn8hAAQSAAkJ9RmSIADVAQASAAkJ9RmSIADVAQAGAAQJtAYrLgCoAAAkAAEJZQPfSgAsAAAAAA==.Trizz:BAABLgAFFH8HAAIMAAQJcRTjCAAlAQAMAAQJcRTjCAAlAQAAAA==.Troctzul:BAAALgADCgEJAwAAAA==.Trollmachine:BAAALgAECgcJDAABLgAECgkJGgADACQfAA==.',
Ts='Tsuchiya:BAABLgAECn8kAAIhAAgJMA4tEAANAQAhAAgJMA4tEAANAQAAAA==.',
Tu='Tuts:BAAALgADCgYJDAAAAA==.',
Ty='Tythos:BAAALgADCgYJCwAAAA==.',
Up='Uproar:BAACLgAFFH8MAAIfAAUJOx2eCQBWAQAfAAUJOx2eCQBWAQAuAAQKfy4AAh8ACQlDJYYBACADAB8ACQlDJYYBACADAAAA.',
Va='Vaelira:BAAALgADCgkJCQAAAA==.Vahlfi:BAACLgAFFH8JAAIhAAMJviCobgCtAAAhAAMJviCobgCtAAAuAAQKfxwABCEACQljJFAPAMkCACEACQljJFAPAMkCAAwAAQm6IvFWAGEAACgAAgkTEUo1ADAAAAEuAAUUCQkwABsA1CMA.Valedormu:BAAALgAFFAIJAwAAAA==.Valefury:BAAALgAECggJCAAAAA==.Valemon:BAAALgAFFAEJAQAAAA==.Valeskog:BAAALgAECgkJCQAAAA==.Valeskogr:BAABLgAECn8dAAQLAAkJAg54YQCDAQALAAgJZw54YQCDAQAnAAcJjQjeFAB6AQABAAgJmAN0UAAMAQAAAA==.Valffi:BAAALgAFFAEJAQABLgAFFAkJMAAbANQjAA==.Varoth:BAAALgAECgEJAQAAAA==.Varus:BAAALgAECgYJCQAAAA==.',
Ve='Velisá:BAAALgAECgIJAgAAAA==.Vengefulmilk:BAAALgAECgUJDgABLgAECgYJBwAEAAAAAA==.Venture:BAAALgADCgkJIgAAAA==.Vergo:BAAALgADCgEJAQAAAA==.Vescovo:BAABLgAECn89AAQIAAkJQiE+AQAGAwAIAAkJQiE+AQAGAwAXAAUJ0RXXQgAEAQAWAAEJrh+jdABWAAAAAA==.',
Vi='Virde:BAAALgADCgMJAwAAAA==.',
Vl='Vll:BAABLgAECn8iAAIMAAgJ7iKwBwC1AgAMAAgJ7iKwBwC1AgAAAA==.',
Vo='Volkihar:BAAALgAFFAIJAwAAAA==.Vordt:BAAALgAECgIJBwAAAA==.',
Wa='Wardaorm:BAABLgAECn8fAAIjAAYJDg4ATgAPAQAjAAYJDg4ATgAPAQABLgAECgkJLgAQANQcAA==.Warkinz:BAAALgADCgQJBQAAAA==.Warlin:BAAALgAECgEJAQAAAA==.',
We='Welordron:BAAALgADCgEJAQAAAA==.',
Wi='Willohh:BAAALgAECgQJBAAAAA==.Winden:BAABLgAECn8WAAIKAAYJhhtNGABGAQAKAAYJhhtNGABGAQAAAA==.Wingback:BAAALgAECgkJBQAAAA==.Wiz:BAABLgAECn8WAAIJAAYJfAuyKQCwAAAJAAYJfAuyKQCwAAAAAA==.',
Wp='Wphoenix:BAAALgAECgQJBAAAAA==.',
Wr='Wrizz:BAAALgADCgYJCAAAAA==.',
Wt='Wtfsteve:BAAALgADCgUJBQABLgAECggJFwAZAEgZAA==.',
Xa='Xadrai:BAAALgAECgYJCwAAAA==.',
Xe='Xeplin:BAAALgAECgUJCQAAAA==.',
Xh='Xhenshini:BAACLgAFFH8TAAMGAAUJ+g30AwC/AAAGAAQJ4gf0AwC/AAASAAUJpgwYHgC8AAAuAAQKf0IAAxIACQlOIf0FAPwCABIACQkcIf0FAPwCAAYACAmqGjEJAE4CAAAA.',
Xk='Xkrin:BAAALgAECgEJAQAAAA==.',
Xn='Xnon:BAAALgADCgMJAwAAAA==.',
Ye='Yeonguo:BAAALgAECgYJDgAAAA==.',
Yu='Yums:BAAALgAECgEJAgAAAA==.',
Za='Zahlia:BAAALgAECgQJBQAAAA==.Zalethe:BAAALgAECgMJAwAAAA==.Zalliel:BAAALgADCggJCAAAAA==.Zalman:BAAALgAECgMJBQAAAA==.Zaphíel:BAAALgADCgcJBwABLgAECgkJGAATACsMAA==.Zaran:BAABLgAECn8XAAIQAAgJWhK2dACEAQAQAAgJWhK2dACEAQAAAA==.',
Ze='Zeninnaoya:BAABLgAECn8fAAMRAAkJuSD6AABaAwARAAkJ3B36AABaAwAjAAcJISaFDgDgAgAAAA==.',
['Zê']='Zêdd:BAAALgADCgYJBgABLgAFFAUJCwAkAGoLAA==.',
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
