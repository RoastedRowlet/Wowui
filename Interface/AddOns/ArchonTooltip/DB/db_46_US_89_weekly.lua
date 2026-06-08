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

local lookup = {'Mage-Frost','Shaman-Restoration','Shaman-Elemental','Paladin-Holy','Priest-Holy','Priest-Shadow','Hunter-BeastMastery','DemonHunter-Devourer','DeathKnight-Blood','Evoker-Augmentation','Evoker-Preservation','Unknown-Unknown','Paladin-Protection','Druid-Restoration','Druid-Guardian','Hunter-Survival','Hunter-Marksmanship','Warrior-Fury','Warrior-Protection','Druid-Balance','Druid-Feral','DeathKnight-Unholy','Paladin-Retribution','Warrior-Arms','Evoker-Devastation','DemonHunter-Havoc','Shaman-Enhancement','Rogue-Subtlety','DeathKnight-Frost','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','Mage-Fire','Warlock-Demonology','Warlock-Destruction','Mage-Arcane','DemonHunter-Vengeance','Warlock-Affliction','Rogue-Outlaw','Rogue-Assassination',}
local provider = {region='US',realm='Eonar',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abbazaad:BAAALgAECgQJBQAAAA==.Abreen:BAAALgADCgcJCQAAAA==.Abysseus:BAAALgADCgcJCAAAAA==.',
Ac='Acepriest:BAAALgAECgQJCAAAAA==.Achievement:BAAALgAECgQJBAAAAA==.',
Ad='Adeathfox:BAAALgADCgEJAQAAAA==.Adhoc:BAAALgADCgUJBQAAAA==.Admired:BAABLgAECn8cAAIBAAcJoB4OVwAzAgABAAcJoB4OVwAzAgAAAA==.Adyr:BAACLgAFFH8KAAMCAAQJUhIOOgDkAAACAAQJUhIOOgDkAAADAAMJIwdJNgCmAAAuAAQKfyQAAwIACAmUH2wTAHoCAAIACAmUH2wTAHoCAAMABQnlF0pNABMBAAAA.',
Ai='Aidra:BAABLgAECn8nAAIEAAgJWxnaFQBTAgAEAAgJWxnaFQBTAgAAAA==.',
Al='Alaira:BAAALgAECgMJAwABLgAECgcJHgABAIAIAA==.Alamora:BAABLgAECn8XAAMFAAYJTggAQgDVAAAFAAYJTggAQgDVAAAGAAYJDwQ8VgCuAAAAAA==.Alastair:BAAALgAECgcJCAAAAA==.Alathena:BAAALgAECgcJDAAAAA==.Albinoz:BAAALgADCgIJAgAAAA==.Albrect:BAAALgADCgYJEQAAAA==.Aldrich:BAAALgADCgEJAQAAAA==.Alexandrya:BAACLgAFFH8HAAIHAAIJqQfjfACLAAAHAAIJqQfjfACLAAAuAAQKfyoAAgcACAlDGA9CANABAAcACAlDGA9CANABAAAA.Alicemalkin:BAABLgAECn8XAAIIAAkJHxTyPQD8AQAIAAkJHxTyPQD8AQAAAA==.Alonai:BAAALgAECgYJBgAAAA==.Alphred:BAAALgAECgEJAQAAAA==.Alysse:BAAALgADCgUJBwAAAA==.',
Am='Amarysia:BAAALgAECgYJDQAAAA==.Ameriixs:BAAALgAECgIJAgAAAA==.Amháin:BAAALgAECggJDQAAAA==.Amsip:BAAALgAECgEJAQABLgAECgkJJAAJABYPAA==.Amsroeb:BAABLgAECn8kAAIJAAkJFg9QHQBjAQAJAAkJFg9QHQBjAQAAAA==.',
An='Anelavenger:BAACLgAFFH8HAAIKAAMJpw6cQAC1AAAKAAMJpw6cQAC1AAAuAAQKfy0AAwoACQneHMwMAKkCAAoACQneHMwMAKkCAAsAAwlcAS1EAE0AAAAA.Angerwina:BAAALgADCgUJCQAAAA==.Anggar:BAAALgADCgIJAgAAAA==.',
Ao='Aomori:BAAALgAECgcJBwAAAA==.',
Aq='Aquini:BAAALgAFFAEJAQABLgAFFAIJAgAMAAAAAA==.Aqüilés:BAAALgAECgEJAgAAAA==.',
Ar='Arathor:BAABLgAECn8nAAINAAkJbRy8BQCFAgANAAkJbRy8BQCFAgAAAA==.Arctorius:BAAALgADCgEJAQAAAA==.Arent:BAABLgAECn9EAAIOAAkJ+xUlIgAuAgAOAAkJ+xUlIgAuAgAAAA==.Arfy:BAAALgADCgMJAgABLgAECggJEQAMAAAAAA==.Argil:BAAALgAECgEJAQABLgAECggJJgAPAE8SAA==.Argøn:BAABLgAECn88AAQHAAkJMxu5GgB5AgAHAAkJMxu5GgB5AgAQAAUJ2AhHQQC1AAARAAEJkAYUkgAoAAAAAA==.Arkanna:BAAALgAECgEJAQAAAA==.Arrise:BAAALgAECgUJBwAAAA==.Artemislives:BAAALgAECgcJEQAAAA==.Arthuaca:BAAALgAECgYJDQAAAA==.',
As='Asharia:BAABLgAECn8QAAIIAAcJjRGXYwBUAQAIAAcJjRGXYwBUAQAAAA==.Ashog:BAAALgADCgYJCwAAAA==.Assateague:BAABLgAECn8ZAAISAAYJyAQrZQC5AAASAAYJyAQrZQC5AAAAAA==.Astelossa:BAAALgAECgEJAQAAAA==.Astralie:BAAALgADCggJFAAAAA==.Asuya:BAAALgADCgYJCQAAAA==.',
At='Athereos:BAAALgADCgYJBQAAAA==.Athylan:BAAALgADCgEJAQABLgAFFAYJFwAEAIgcAA==.Atrosity:BAABLgAECn8tAAITAAkJpiKWBADQAgATAAkJpiKWBADQAgAAAA==.',
Au='Aurorabane:BAAALgADCgYJEAAAAA==.',
Av='Avelleah:BAAALgAECgEJBAAAAA==.',
Az='Azulyne:BAAALgADCgIJAgAAAA==.Azuretorrent:BAAALgADCgQJBAAAAA==.',
Ba='Bananapistol:BAAALgAECgUJBQAAAA==.Barracksbuny:BAAALgAECgUJBgABLgAECgUJBQAMAAAAAA==.Barrathfrogy:BAAALgADCgYJFQAAAA==.',
Be='Bebheishel:BAAALgADCgYJCwAAAA==.Bellatrix:BAAALgAECgMJAwABLgAECgQJDgAMAAAAAA==.Bertelo:BAAALgADCgUJBQAAAA==.',
Bi='Bigstinky:BAAALgAECgYJDAABLgAECgkJPAAHADMbAA==.Bilywitchdoc:BAAALgAFFAIJAwABLgAECgkJQwAQANckAA==.Bisao:BAAALgAECgIJAgAAAA==.Biscuít:BAABLgAECn8pAAMUAAkJiA61KgBxAQAUAAkJiA61KgBxAQAVAAEJqAelVgAiAAAAAA==.',
Bl='Blasuoff:BAAALgAECgQJBAAAAA==.Bloodrains:BAAALgAECgEJAwAAAA==.Bloodyfate:BAAALgADCgUJBQAAAA==.',
Bo='Bonesentinel:BAABLgAECn8YAAIHAAcJNSI9IQBWAgAHAAcJNSI9IQBWAgABLgAFFAUJDQAWAN0ZAA==.Bonës:BAAALgADCgEJAQAAAA==.Bora:BAAALgAECgQJDgAAAA==.Borzoi:BAABLgAFFH8QAAIXAAQJOyHrHwByAQAXAAQJOyHrHwByAQAAAA==.Bourgùîgnon:BAAALgADCgcJCgAAAA==.',
Br='Bragasch:BAAALgADCgkJGQAAAA==.Brakhon:BAAALgAECgEJAgAAAA==.Bruisebrews:BAAALgADCgEJAQAAAA==.',
Bu='Bullplop:BAAALgADCgUJBQAAAA==.Burekbazino:BAAALgADCgcJCQAAAA==.Burningsleet:BAAALgAECgYJBgABLgAFFAgJEAAWAI8WAA==.',
['Bò']='Bò:BAACLgAFFH8MAAIUAAQJ0wfRJwDfAAAUAAQJ0wfRJwDfAAAuAAQKfzEAAhQACQmpF08TAC8CABQACQmpF08TAC8CAAAA.',
Ca='Caduceus:BAAALgADCgcJGAAAAA==.Caesus:BAABLgAECn8cAAIGAAcJFxdkIwClAQAGAAcJFxdkIwClAQAAAA==.Cagedancer:BAABLgAECn8iAAQVAAgJQwsdGgAqAQAVAAgJHQodGgAqAQAUAAYJyAaNUADmAAAOAAEJFAMQ9AAYAAAAAA==.Callio:BAACLgAFFH8HAAIHAAQJ7QQbSwABAQAHAAQJ7QQbSwABAQAuAAQKfy8AAgcACQmbEexAANQBAAcACQmbEexAANQBAAAA.Cantor:BAAALgAECgEJAQAAAA==.Caradd:BAAALgAECgcJCwAAAA==.Catchclause:BAAALgADCgkJFAAAAA==.Cathillex:BAABLgAECn8aAAMSAAkJTxdHGAAlAgASAAkJTxdHGAAlAgAYAAEJ1AJSggAWAAAAAA==.Cavagos:BAACLgAFFH8KAAIZAAQJKBB0BAAjAQAZAAQJKBB0BAAjAQAuAAQKfzYAAhkACQlWINUBALoCABkACQlWINUBALoCAAAA.Caycay:BAACLgAFFH8YAAIaAAYJGCJ0AwDPAQAaAAYJGCJ0AwDPAQAuAAQKf1EAAhoACQnAJkgAAJIDABoACQnAJkgAAJIDAAAA.Cayleq:BAAALgAECgMJAgABLgAFFAYJGAAaABgiAA==.',
Ce='Celebrexi:BAAALgAECgcJBgAAAA==.Celene:BAAALgADCgYJBwAAAA==.Celtic:BAAALgADCgEJAQAAAA==.Cerrulli:BAAALgAECgYJDwAAAA==.',
Ch='Chaosknight:BAABLgAECn8XAAMDAAgJSRK4LACDAQADAAgJSRK4LACDAQACAAUJUAoZlQCWAAAAAA==.Chaostrip:BAACLgAFFH8GAAIIAAUJmRYbOgAoAQAIAAUJmRYbOgAoAQAuAAQKfzIAAggACQknI+YHAAkDAAgACQknI+YHAAkDAAAA.Chariso:BAAALgAECgEJAQAAAA==.Cheddar:BAAALgAECgYJCQAAAA==.Chillbros:BAACLgAFFH8QAAIbAAYJ1B0RAwCWAQAbAAYJ1B0RAwCWAQAuAAQKfywAAxsACQkTJB4CAPsCABsACQkTJB4CAPsCAAMABAmqH+45AGcBAAAA.Chilldh:BAAALgAECgUJBQABLgAFFAYJEAAbANQdAA==.Chillmage:BAAALgADCgcJCgABLgAFFAYJEAAbANQdAA==.Chindi:BAABLgAECn8xAAMSAAkJ7xflHwDqAQASAAkJKxblHwDqAQATAAcJUBJiGgBZAQAAAA==.Chindrakh:BAAALgAECggJEAABLgAECgkJMQASAO8XAA==.Choiminasue:BAAALgAECgEJAgAAAA==.Chunga:BAABLgAECn8UAAIDAAYJoAPZXADQAAADAAYJoAPZXADQAAAAAA==.Chungers:BAAALgAECgQJBgAAAA==.Churd:BAACLgAFFH8NAAIGAAMJQhUMIADbAAAGAAMJQhUMIADbAAAuAAQKfykAAgYACQnkGN8QAEsCAAYACQnkGN8QAEsCAAAA.Churdicus:BAAALgADCgkJEQAAAA==.Chypnotic:BAAALgAECgcJCwAAAA==.Chypper:BAAALgADCgEJAQAAAA==.Chypster:BAABLgAECn8jAAIDAAgJMg7JOQBAAQADAAgJMg7JOQBAAQAAAA==.',
Ci='Ciceroe:BAABLgAFFH8KAAIcAAMJ1hORIwDyAAAcAAMJ1hORIwDyAAAAAA==.Citadel:BAAALgADCgIJAwAAAA==.',
Cl='Cleft:BAABLgAECn8UAAIXAAYJAxA+twAIAQAXAAYJAxA+twAIAQAAAA==.Clevelandk:BAAALgAECgQJBQAAAA==.Clowwnshoes:BAAALgAECgEJAgAAAA==.',
Co='Coalystra:BAACLgAFFH8OAAIIAAQJNhkPMwBBAQAIAAQJNhkPMwBBAQAuAAQKfywAAggACQnsGmcfAE0CAAgACQnsGmcfAE0CAAAA.Cocopuffs:BAACLgAFFH8HAAIUAAIJsBG2FACfAAAUAAIJsBG2FACfAAAuAAQKfzUAAhQACQleICMJAAMDABQACQleICMJAAMDAAAA.Colostrom:BAACLgAFFH8LAAINAAQJDBwSBABHAQANAAQJDBwSBABHAQAuAAQKfy8AAg0ACQnVH2YGAHQCAA0ACQnVH2YGAHQCAAAA.Complicatedz:BAAALgAECgUJBQAAAA==.Comul:BAAALgADCgcJBwAAAA==.Coramage:BAABLgAECn8aAAIBAAkJjwZlfgB0AQABAAkJjwZlfgB0AQAAAA==.Corentis:BAAALgADCgYJBgAAAA==.Corliss:BAABLgAECn8aAAITAAkJwhUXEADbAQATAAkJwhUXEADbAQAAAA==.Cornholeo:BAAALgADCgkJCQAAAA==.',
Cp='Cplusmc:BAAALgAECgQJBwAAAA==.',
Cr='Creightizle:BAABLgAECn8eAAIHAAgJfRS/OQDHAQAHAAgJfRS/OQDHAQAAAA==.',
['Cá']='Cátix:BAAALgADCgMJAwAAAA==.',
Da='Daicmerollin:BAAALgAECgYJCwAAAA==.Danhaüsen:BAAALgAECgIJAwAAAA==.Darkbeast:BAABLgAFFH8JAAIHAAQJOQ92OgAtAQAHAAQJOQ92OgAtAQAAAA==.Darkdeeds:BAAALgADCggJEQAAAA==.Darkpallo:BAABLgAECn8YAAIXAAcJPxPWbwCdAQAXAAcJPxPWbwCdAQABLgAFFAQJCQAHADkPAA==.Darthtav:BAABLgAFFH8IAAIdAAYJGw++BgBjAQAdAAYJGw++BgBjAQAAAA==.Daten:BAABLgAECn9FAAIXAAkJ5BSHcACCAQAXAAkJ5BSHcACCAQAAAA==.Dazshauran:BAAALgADCggJCAAAAA==.Daîma:BAAALgADCggJCAAAAA==.',
Db='Dbltap:BAAALgADCgEJAQAAAA==.',
De='Deathbycow:BAABLgAECn8rAAIPAAgJlhztCgAjAgAPAAgJlhztCgAjAgAAAA==.Debra:BAAALgADCgUJBQAAAA==.Decayed:BAABLgAECn8eAAIJAAgJ4xqXDgAVAgAJAAgJ4xqXDgAVAgABLgAECgUJBQAMAAAAAA==.Deipally:BAAALgAECgYJBQAAAA==.Demonchalk:BAACLgAFFH8GAAIIAAUJ1xCVRAAMAQAIAAUJ1xCVRAAMAQAuAAQKfxYAAggABglqI902AN8BAAgABglqI902AN8BAAEuAAUUBQkbABsAAyYA.Desdeynna:BAAALgADCgEJAQAAAA==.Deseral:BAAALgAECgIJAgAAAA==.Dewbie:BAAALgAECgEJAQAAAA==.',
Di='Diagonalli:BAABLgAECn8fAAIZAAkJNA99BwC3AQAZAAkJNA99BwC3AQAAAA==.Dimmadome:BAAALgADCgEJAQAAAA==.Dinojam:BAAALgADCgMJAQAAAA==.Divirian:BAAALgAECgYJDwAAAA==.',
Dj='Djdaemon:BAAALgAECgYJBwAAAA==.Djdrakshadow:BAAALgAECgQJBwAAAA==.Djpaly:BAAALgAECgYJBwAAAA==.Djpriest:BAAALgAECgMJAwAAAA==.Djshadow:BAAALgAECgUJBQAAAA==.Djshadowar:BAAALgAECgUJCQAAAA==.Djshadowhunt:BAAALgAECgYJCQAAAA==.Djshadowlock:BAAALgAECgMJAwAAAA==.Djshadowrog:BAAALgAECgYJCgAAAA==.Djshamy:BAAALgAECgMJAwAAAA==.Djshaolin:BAAALgAECgUJCgAAAA==.Djzhadow:BAAALgAECgQJBQAAAA==.Djzhadruid:BAAALgADCgcJFQAAAA==.',
Dk='Dkshadow:BAAALgAECgQJBAAAAA==.',
Dm='Dmitrì:BAAALgAECgEJAQAAAA==.',
Do='Dogno:BAAALgAECgEJAgAAAA==.Dontdieplez:BAAALgAECgkJDAAAAA==.',
Dp='Dpm:BAAALgAECgEJAgAAAA==.',
Dr='Dragbuttakis:BAAALgAECgUJCAAAAA==.Drakhadir:BAAALgAECgQJBAAAAA==.Drakmon:BAAALgAECgIJBQAAAA==.Draktând:BAABLgAECn8vAAIcAAgJVhljEwD9AQAcAAgJVhljEwD9AQAAAA==.Drippysilk:BAAALgAECgQJCAABLgAECgkJJAAXAE4fAA==.Drius:BAAALgADCgMJAwAAAA==.Drunkenpanda:BAACLgAFFH8FAAMeAAMJxAPNKgCPAAAeAAMJxAPNKgCPAAAfAAEJqgnFWAAwAAAuAAQKfyUAAx8ACQn0FLEgAAMCAB8ACQn0FLEgAAMCAB4ABwnWCCRKAMwAAAAA.Drunknoodle:BAAALgAECgQJCAAAAA==.',
Du='Duhpriest:BAAALgAECgEJAQAAAA==.Duinrane:BAAALgAECgEJAQAAAA==.Duon:BAABLgAECn8WAAQeAAkJ3hSXHwCkAQAeAAgJexaXHwCkAQAfAAIJzwmCYQBJAAAgAAIJkgWvgQBAAAAAAA==.',
Dw='Dwagonfur:BAAALgAECgcJBgAAAA==.',
Ec='Echö:BAACLgAFFH8OAAIaAAQJXxEgEAAQAQAaAAQJXxEgEAAQAQAuAAQKfyEAAhoACAl5GbEQAA0CABoACAl5GbEQAA0CAAAA.',
Ei='Eiarinos:BAAALgADCgEJAQAAAA==.Eirø:BAAALgADCgkJCQABLgAFFAQJDgAHANggAA==.',
El='Elaine:BAAALgAFFAIJAgAAAA==.Elberon:BAAALgAECgUJDwAAAA==.Ellspeth:BAAALgAECgkJCQAAAA==.Elmerhomero:BAAALgADCgUJBQAAAA==.Elronnd:BAAALgAECgMJAwAAAA==.Elsebeth:BAAALgADCgcJCAAAAA==.',
Em='Emilie:BAAALgADCgYJBgAAAA==.',
En='Enoch:BAABLgAECn8bAAIXAAYJkBZXfwB7AQAXAAYJkBZXfwB7AQAAAA==.',
Er='Eriam:BAAALgAECgMJAwABLgAECgkJJAAPAE4ZAA==.Errane:BAACLgAFFH8ZAAIOAAYJ5SERBwBwAgAOAAYJ5SERBwBwAgAuAAQKfywAAw4ACAnJJosEAEYDAA4ACAnJJosEAEYDABQAAQnHFVJ4AEQAAAAA.Eruiluvatar:BAAALgAECgYJCAAAAA==.',
Et='Etalia:BAAALgAECgEJAgAAAA==.Etcetera:BAAALgAECgMJBAAAAA==.',
Ev='Eveliel:BAAALgAECgEJAQAAAA==.',
Ex='Exlibris:BAAALgADCgcJDAAAAA==.',
Fa='Fallenangell:BAAALgADCgUJBQAAAA==.Fandiirn:BAAALgADCgYJBgAAAA==.Fastjack:BAABLgAECn8lAAMFAAgJUxNPLQBTAQAFAAYJlxVPLQBTAQAGAAgJEwcbOQAmAQAAAA==.',
Fe='Felseeker:BAAALgADCgkJCQABLgAECgkJPgABACgYAA==.',
Fi='Fiora:BAAALgADCgYJCwAAAA==.Firbirl:BAAALgAECgIJAgAAAA==.Fistoffury:BAABLgAECn8ZAAMgAAcJqBNMNgAdAQAgAAcJqBNMNgAdAQAeAAQJOAkEWgCoAAAAAA==.Fitco:BAAALgADCgYJCwABLgAECgYJDwAMAAAAAA==.Fiènd:BAAALgADCgYJBgAAAA==.',
Fl='Flametar:BAAALgAECgEJAQAAAA==.Floodlust:BAAALgADCgEJAQAAAA==.Floppydisk:BAAALgAECgUJDgAAAA==.',
Fo='Fortiss:BAACLgAFFH8KAAICAAMJ/hauPQDZAAACAAMJ/hauPQDZAAAuAAQKfysAAwIACQnWGwENAOQCAAIACQnWGwENAOQCAAMABgk/EAdOAO4AAAAA.',
Fr='Freelo:BAAALgAECgQJCAAAAA==.Frito:BAAALgAECggJCQAAAA==.Frost:BAAALgAFFAIJAgABLgAFFAgJJAAQACwWAA==.Frostmon:BAABLgAECn8aAAIWAAkJnhQjMAA2AgAWAAkJnhQjMAA2AgAAAA==.Frshnvrfrzn:BAAALgAECggJDwAAAA==.Frøzenblight:BAAALgAECgEJAQAAAA==.',
Fu='Fulmo:BAAALgADCgUJBQABLgAFFAQJBgAWAL4DAA==.Furbee:BAAALgAECggJEQAAAA==.Furn:BAAALgAECgkJAQAAAA==.',
['Fá']='Fáde:BAAALgADCgQJBQABLgAECgUJBgAMAAAAAA==.',
Ga='Gabris:BAAALgADCgYJBgAAAA==.Galeandra:BAABLgAECn8gAAIGAAkJZQdfMABUAQAGAAkJZQdfMABUAQAAAA==.Gallo:BAAALgADCggJDQAAAA==.Garim:BAAALgADCgMJBAABLgAECggJJQAFAFMTAA==.',
Ge='Geraltofrvia:BAAALgAECgkJDgAAAA==.',
Gg='Gg:BAAALgAFFAIJBAABLgAFFAgJIAAhAEIkAA==.',
Gi='Giantgoose:BAAALgAECgEJAgAAAA==.Gingani:BAAALgADCgcJDAAAAA==.',
Gn='Gnar:BAABLgAECn8mAAIWAAcJXRIJdwBtAQAWAAcJXRIJdwBtAQAAAA==.',
Go='Gowtherdead:BAAALgADCgQJBAAAAA==.Gowtherpunch:BAACLgAFFH8OAAIgAAQJOgeJLQDoAAAgAAQJOgeJLQDoAAAuAAQKfzEAAiAACQm5FQQWAPMBACAACQm5FQQWAPMBAAAA.',
Gr='Gregzug:BAAALgAECgMJAwAAAA==.Grendel:BAAALgAECgUJBAABLgAFFAQJBgAWAL4DAA==.Greyjoy:BAAALgADCgYJBQAAAA==.Grimfury:BAAALgAFFAIJBAAAAA==.Grimsy:BAAALgADCgYJBwAAAA==.Grodd:BAAALgADCgUJBQAAAA==.Groqqu:BAAALgAECgQJBAAAAA==.Grumble:BAAALgAECgYJCAAAAA==.Gruxxiron:BAAALgAECgUJBwABLgAECgkJOwAWAIIfAA==.',
Gu='Gulnn:BAABLgAECn8zAAMiAAkJJh0yFQCgAgAiAAkJJh0yFQCgAgAjAAIJVhT8VABvAAAAAA==.Gumby:BAAALgADCgYJBgAAAA==.',
Ha='Haelena:BAABLgAECn8jAAIEAAgJPhB1LACkAQAEAAgJPhB1LACkAQAAAA==.Halys:BAAALgADCgUJBQAAAA==.Hamil:BAAALgADCgEJAQAAAA==.Harmoss:BAAALgAECgcJBwAAAA==.Hawk:BAAALgADCgYJBgAAAA==.',
He='Heartsfang:BAAALgADCgUJCAAAAA==.Helfire:BAAALgADCgYJBgABLgAECgUJBgAMAAAAAA==.Hellscreems:BAAALgADCgMJAwAAAA==.Heriotza:BAACLgAFFH8GAAIWAAQJvgMSggDwAAAWAAQJvgMSggDwAAAuAAQKfxwAAhYACQmsDqd0AHIBABYACQmsDqd0AHIBAAAA.',
Hx='Hxvenlyx:BAAALgADCgUJDgAAAA==.',
Ia='Iamfubar:BAAALgADCgMJBAAAAA==.',
Ig='Igris:BAAALgAECgcJCgAAAA==.',
Ii='Iimit:BAACLgAFFH8MAAIcAAQJoBdMFQBSAQAcAAQJoBdMFQBSAQAuAAQKfyMAAhwACQl9GrINAEECABwACQl9GrINAEECAAAA.',
Il='Illidead:BAACLgAFFH8YAAIBAAYJ6ByOLwCWAQABAAYJ6ByOLwCWAQAuAAQKfyMAAwEACQnfI6UyAEcCAAEACQlWIKUyAEcCACQAAQlSJdYOAG4AAAAA.Iluni:BAAALgADCgMJAwAAAA==.',
Im='Implied:BAAALgADCgUJBQAAAA==.',
In='Indexes:BAABLgAECn8XAAMUAAYJ4gttSQDXAAAUAAYJ6AptSQDXAAAPAAUJGgbuTgBfAAAAAA==.Insrik:BAAALgAECgcJEAAAAA==.Insurance:BAAALgAECggJCAABLgAFFAIJBwAHAKkHAA==.',
Io='Iompróirbáis:BAABLgAECn8hAAIWAAkJ7QdQdQBxAQAWAAkJ7QdQdQBxAQAAAA==.',
Ir='Irdeadohnoz:BAABLgAECn8aAAIBAAcJTAxlrAAiAQABAAcJTAxlrAAiAQAAAA==.',
Is='Ist:BAAALgAECgQJBAAAAA==.',
It='Itchigo:BAABLgAECn8UAAIHAAgJ1A0cXQCCAQAHAAgJ1A0cXQCCAQAAAA==.',
Iv='Ivern:BAAALgAECgIJAgAAAA==.Ivgorod:BAABLgAECn8kAAMZAAkJ1ggfCwBaAQAZAAkJnAgfCwBaAQAKAAgJBAaYRwABAQAAAA==.',
Ja='Jabbadahut:BAAALgAECgcJBQAAAA==.Jambi:BAAALgAECgYJDgAAAA==.Jardani:BAAALgAECgEJAQAAAA==.Jarhead:BAAALgADCgUJBQAAAA==.Jastrae:BAAALgAECgcJDgAAAA==.Jaziani:BAAALgADCgcJBwABLgAECgMJAwAMAAAAAA==.Jazilyne:BAAALgAECgMJAwAAAA==.',
Je='Jealous:BAAALgADCgUJBQABLgAECgkJIgAIAJ0dAA==.Jenka:BAAALgAECgUJCgAAAA==.',
Ji='Jibbs:BAAALgADCgkJCQAAAA==.',
Jo='Joleya:BAAALgADCgEJAQAAAA==.',
Ju='Junta:BAAALgADCgcJJQAAAA==.Justine:BAAALgADCgUJBQAAAA==.Justtrolling:BAAALgAECgYJDgAAAA==.',
['Jä']='Jäkel:BAAALgADCgUJBQAAAA==.',
Ka='Kalike:BAAALgADCgcJBwAAAA==.Kambative:BAABLgAECn8XAAMOAAcJqxIPQgCZAQAOAAcJqxIPQgCZAQAUAAMJGBZOTgDEAAABLgAFFAQJCQALACoRAA==.Kammunion:BAAALgAECgYJDgABLgAFFAQJCQALACoRAA==.Kamphiyer:BAACLgAFFH8JAAQLAAQJKhHjHwCYAAALAAMJKQrjHwCYAAAZAAIJzQz4CACOAAAKAAIJbAUIVQBpAAAuAAQKfzoABAsACQnqGOcJAD4CAAsACQnqGOcJAD4CAAoACAmIHYsTADoCABkABAmjDMExAIgAAAAA.Kamsumerage:BAAALgADCgkJEgABLgAFFAQJCQALACoRAA==.Kandosii:BAAALgADCgUJBQAAAA==.Kantheal:BAABLgAECn8lAAIEAAkJbR6OCAD4AgAEAAkJbR6OCAD4AgAAAA==.Kaulana:BAAALgADCgcJDAAAAA==.',
Ke='Keirmania:BAAALgAECgEJAQAAAA==.Kekkan:BAAALgADCgcJCgAAAA==.Kellendere:BAAALgAECgYJCwAAAA==.',
Ki='Kiagas:BAAALgAECgcJBwABLgAFFAMJDQAOALMQAA==.Kiieedk:BAAALgAECgEJAQAAAA==.Kimgoeun:BAAALgADCgYJBgAAAA==.Kio:BAAALgAECgYJCAAAAA==.',
Kl='Klompus:BAAALgADCgQJBAAAAA==.',
Kn='Knùsê:BAAALgADCgUJBgABLgAFFAQJDgAHANggAA==.',
Ko='Komorai:BAAALgADCgYJBgAAAA==.',
Kr='Kravex:BAABLgAECn8kAAIPAAkJThm/CQA6AgAPAAkJThm/CQA6AgAAAA==.Krixxa:BAABLgAECn8oAAIFAAkJWCQSAwBcAwAFAAkJWCQSAwBcAwAAAA==.',
Ku='Kuula:BAAALgAECgEJAQAAAA==.',
Ky='Kylana:BAAALgADCgQJBAABLgAECggJHQAOANAMAA==.',
['Kä']='Kären:BAAALgAECgUJEgAAAA==.',
['Ké']='Kélly:BAAALgAECggJCAAAAA==.',
La='Laochnaofa:BAAALgAECgcJDgAAAA==.Larayvia:BAACLgAFFH8IAAIHAAMJ3QKAaACyAAAHAAMJ3QKAaACyAAAuAAQKfx0AAgcACAkrDkc7AMEBAAcACAkrDkc7AMEBAAAA.Laurance:BAAALgADCgYJBgAAAA==.',
Le='Leakygasket:BAAALgAECgYJBwAAAA==.Leesala:BAACLgAFFH8HAAICAAQJBRwNIwBFAQACAAQJBRwNIwBFAQAuAAQKfzAAAwIACQmpF+sdAFECAAIACQmpF+sdAFECABsAAQn+BGg/ACcAAAAA.Lelora:BAAALgAECgEJAQAAAA==.Lerazer:BAAALgAECgYJCgAAAA==.',
Lg='Lgidk:BAAALgADCgMJAwABLgAECgkJIgAIAJ0dAA==.',
Li='Lic:BAAALgAECgcJDgAAAA==.Liea:BAAALgAECgMJBAAAAA==.Lilbash:BAAALgAECgEJAwAAAA==.Liliatrix:BAAALgAECgQJBgAAAA==.Lillabet:BAAALgAECgYJEwAAAA==.Lilmatty:BAAALgAECgkJDQABLgAFFAUJCgAfAFkZAA==.Lilsneaky:BAAALgADCggJCAAAAA==.Limpydk:BAAALgADCgUJBQABLgAECgkJJAAXAE4fAA==.Limpylarva:BAAALgADCgMJAwABLgAECgkJJAAXAE4fAA==.Limpypal:BAABLgAECn8kAAMXAAkJTh+ADwDgAgAXAAkJTh+ADwDgAgANAAIJZASrRABGAAAAAA==.Litter:BAAALgAECgUJBQAAAA==.',
Lo='Lockém:BAAALgADCgIJAgAAAA==.Logathil:BAAALgAECgYJEAAAAA==.Loremipsum:BAAALgADCgYJBgAAAA==.',
Lu='Luchulainn:BAAALgADCgYJBgAAAA==.Lucifero:BAAALgAECggJCgAAAA==.Lucifurwild:BAAALgADCgQJBQAAAA==.Lunaaris:BAABLgAECn8rAAIOAAkJBR8KDwDUAgAOAAkJBR8KDwDUAgAAAA==.Lunastre:BAAALgADCgEJAQAAAA==.',
['Lí']='Límpy:BAABLgAECn8aAAIZAAYJ/CJ/CgA0AgAZAAYJ/CJ/CgA0AgABLgAECgkJJAAXAE4fAA==.Línk:BAAALgAECgYJCgAAAA==.',
['Lî']='Lîkwuid:BAAALgAECggJDwAAAA==.',
Ma='Macallan:BAAALgAECgIJBAAAAA==.Maddrox:BAAALgAECgYJBwAAAA==.Magicmarv:BAAALgADCgIJAQAAAA==.Magnagoth:BAAALgADCgkJDwAAAA==.Magnakilro:BAABLgAECn8fAAIHAAkJRxcQNgD5AQAHAAkJRxcQNgD5AQAAAA==.Mahnaz:BAAALgADCgEJAQABLgADCgcJCgAMAAAAAA==.Mahuta:BAAALgAECgEJAQAAAA==.Malanath:BAABLgAECn8XAAIKAAgJtBVUJwCfAQAKAAgJtBVUJwCfAQAAAA==.Malditto:BAAALgADCgYJBgAAAA==.Maleficus:BAAALgADCgkJFgABLgAECgYJDQAMAAAAAA==.Malothas:BAAALgADCgQJBAAAAA==.Mareki:BAAALgADCgYJBwAAAA==.Markdfordeth:BAAALgAECgEJAQAAAA==.Mattingly:BAAALgAECgQJBQAAAA==.Mattyfu:BAACLgAFFH8KAAMfAAUJWRkKFwCVAQAfAAUJWRkKFwCVAQAeAAEJIBlMNwBLAAAuAAQKfxcAAx4ACQl7GCQdAPEBAB4ACAmWFyQdAPEBAB8ABQmhHhAsALkBAAAA.Mavíel:BAAALgAECgYJDQAAAA==.Maxrogue:BAAALgAECgYJCwABLgAECggJJgAPAE8SAA==.Mazikeen:BAAALgAECgUJBgAAAA==.',
Mc='Mcscoots:BAAALgADCgcJEgAAAA==.',
Me='Meatsupreme:BAACLgAFFH8IAAIXAAMJyQwdaQDMAAAXAAMJyQwdaQDMAAAuAAQKfykAAhcACQm4EaJYALgBABcACQm4EaJYALgBAAAA.Meepin:BAACLgAFFH8XAAIEAAYJiBw4CQAMAgAEAAYJiBw4CQAMAgAuAAQKfzcAAwQACQkLJAQFABwDAAQACQkLJAQFABwDABcAAwk/CqYfAYIAAAAA.Meepmorp:BAAALgAECgUJBQAAAA==.Meifeng:BAAALgADCgEJAQAAAA==.Melithara:BAAALgAECgQJBAAAAA==.Mephala:BAAALgADCgYJBgAAAA==.Merdoc:BAAALgAECgEJAQAAAA==.Mesophistole:BAAALgADCggJCwABLgAECgYJGQAjALYFAA==.Mesopunchy:BAAALgAECgEJAQABLgAECgYJGQAjALYFAA==.Mesopyro:BAABLgAECn8ZAAIjAAYJtgUiIACgAAAjAAYJtgUiIACgAAAAAA==.',
Mi='Mileenä:BAABLgAECn8UAAMJAAkJUBOyEwDLAQAJAAkJUBOyEwDLAQAWAAUJHwrH3QDMAAAAAA==.Minimim:BAAALgADCgMJAwAAAA==.Mistyra:BAABLgAECn8WAAIfAAkJ+B1jCAAHAwAfAAkJ+B1jCAAHAwABLgAECgkJKAAFAFgkAA==.Mià:BAAALgADCgEJAQAAAA==.',
Mo='Mod:BAABLgAECn8UAAIPAAcJghXIHABUAQAPAAcJghXIHABUAQAAAA==.Mograiné:BAAALgAECgQJCQAAAA==.Mojodaemon:BAAALgADCgcJCgAAAA==.Mojoy:BAAALgAECgQJBQAAAA==.Monkaw:BAAALgAECgIJAgAAAA==.Monkchalk:BAAALgAECgQJBAABLgAFFAUJGwAbAAMmAA==.Moondevil:BAAALgAECgEJAQAAAA==.Morta:BAEALgAFFAIJAgAAAA==.Mortkavaliro:BAABLgAECn8VAAMJAAgJFQfkMwC/AAAWAAYJwQXE1wDUAAAJAAcJ2AbkMwC/AAAAAA==.',
Ms='Mslockness:BAAALgADCgYJEwAAAA==.',
Mu='Mugzy:BAAALgAECgkJBwAAAA==.Multipass:BAABLgAECn8aAAIOAAgJbCH1EADBAgAOAAgJbCH1EADBAgAAAA==.Multitool:BAAALgADCgEJAQAAAA==.',
['Mö']='Mörph:BAAALgAECgIJAgAAAA==.',
Na='Nadris:BAAALgADCgcJBwAAAA==.Nanérs:BAAALgAECgcJEQABLgAFFAYJCAAdABsPAA==.Narrodus:BAABLgAECn8kAAIlAAkJPSX0AAA1AwAlAAkJPSX0AAA1AwAAAA==.Nasht:BAABLgAECn8VAAIBAAYJUBZYpwAqAQABAAYJUBZYpwAqAQAAAA==.Nashty:BAAALgADCgYJBgABLgAECgYJFQABAFAWAA==.Nashxi:BAAALgADCgkJEAABLgAECgYJFQABAFAWAA==.Nasu:BAAALgAECgcJAQAAAA==.Nattymoo:BAAALgAECgYJCQABLgAFFAUJCgAfAFkZAA==.',
Ne='Necrô:BAAALgADCgIJAgAAAA==.Nephi:BAAALgAECgEJAgAAAA==.',
Ni='Nightraven:BAAALgADCgkJFgAAAA==.Nightreaper:BAAALgADCgkJGwAAAA==.Nimbus:BAACLgAFFH8eAAIDAAUJKCMYEACNAQADAAUJKCMYEACNAQAuAAQKf3AAAgMACQkPJgQBAHIDAAMACQkPJgQBAHIDAAEuAAUUCAkiAAoA8hsA.Nimike:BAAALgAECgcJDQAAAA==.',
No='Nodens:BAAALgAECgMJAwAAAA==.Noobslapper:BAAALgAECgEJAgAAAA==.Norilin:BAAALgADCgUJBQAAAA==.Normul:BAAALgAECgcJAwABLgAFFAQJDQAdAPoXAA==.Noshoba:BAAALgAECgEJAgAAAA==.',
Nr='Nrvous:BAAALgADCgkJCQAAAA==.',
Nu='Nugzuul:BAAALgAECgEJAQAAAA==.Nuid:BAAALgAECgkJBgAAAA==.Numbers:BAABLgAECn8WAAMaAAcJew/1LwD0AAAIAAcJAguFiQD/AAAaAAYJ+Q/1LwD0AAAAAA==.',
Ny='Nyterage:BAAALgAECgIJAgAAAA==.Nytesage:BAACLgAFFH8kAAIhAAcJIyMtAAB+AgAhAAcJIyMtAAB+AgAuAAQKfygAAiEACAkMJj8AAH4DACEACAkMJj8AAH4DAAAA.',
['Nä']='Näners:BAAALgAFFAEJAQABLgAFFAYJCAAdABsPAA==.',
['Nì']='Nìghtcat:BAAALgAECgQJBwAAAA==.',
Oo='Ookle:BAABLgAECn8nAAMVAAkJVwozFABtAQAVAAkJVwozFABtAQAOAAcJ0wo4aADyAAAAAA==.',
Or='Orchard:BAABLgAFFH8NAAIeAAUJihVdEgAhAQAeAAUJihVdEgAhAQAAAA==.Oresh:BAABLgAECn8nAAISAAcJfRLnNgBkAQASAAcJfRLnNgBkAQAAAA==.Orgrom:BAAALgAECgkJDAAAAA==.Oryz:BAAALgADCgkJCAAAAA==.',
Os='Osajak:BAAALgADCgIJAgAAAA==.',
Oz='Ozo:BAABLgAECn8bAAIiAAcJeAt+iAAkAQAiAAcJeAt+iAAkAQAAAA==.',
Pa='Painavolian:BAABLgAECn9LAAIBAAkJzCCaEwDeAgABAAkJzCCaEwDeAgAAAA==.Palifur:BAAALgAECgkJDwAAAA==.Pandamonium:BAAALgAECgcJEgAAAA==.Panes:BAAALgAECgcJCwAAAA==.Paopu:BAAALgADCgYJBgABLgAECgkJIAAiAPYfAA==.',
Pe='Peeches:BAAALgAECgYJCwAAAA==.Pelonis:BAAALgADCgcJAgAAAA==.Pelor:BAAALgAECgcJDwAAAA==.',
Ph='Pheayre:BAAALgADCgkJDAABLgAECgcJDAAMAAAAAA==.',
Pi='Pisspadpanda:BAACLgAFFH8PAAMiAAQJIxfCPwA8AQAiAAQJIxfCPwA8AQAmAAEJhBp5IgBLAAAuAAQKfykAAiIACQltIoYVAJ4CACIACQltIoYVAJ4CAAAA.',
Pl='Plsbnice:BAAALgAECgYJCAABLgAECgkJIgAIAJ0dAA==.',
Po='Poggies:BAACLgAFFH8gAAMhAAgJQiQkAAC6AgAhAAgJQiQkAAC6AgAkAAEJ3gilBABRAAAuAAQKfyEAAyEACAk9JjkAAIIDACEACAk9JjkAAIIDACQAAQkOIP8WAGIAAAAA.Pollypocket:BAAALgAECgEJAQAAAA==.Ponmonk:BAAALgAECgEJAQABLgAECgYJFQAGALcfAA==.Pontacos:BAABLgAECn8VAAIGAAYJtx/AIADTAQAGAAYJtx/AIADTAQAAAA==.Porkinator:BAAALgADCgYJCAAAAA==.Powdur:BAAALgADCgEJAQABLgAFFAMJDQAQAMIZAA==.Pozh:BAABLgAECn8UAAIiAAYJlA0HkQA3AQAiAAYJlA0HkQA3AQAAAA==.',
Pr='Praynes:BAACLgAFFH8OAAIFAAQJfA2DGQDaAAAFAAQJfA2DGQDaAAAuAAQKfzEAAgUACQnoGMkSAEoCAAUACQnoGMkSAEoCAAAA.Precedence:BAAALgADCgEJAQABLgAECgEJAQAMAAAAAA==.Prestocreamÿ:BAAALgADCgEJAQAAAA==.Priestresh:BAAALgADCgYJBgABLgAECgcJJwASAH0SAA==.',
Pu='Pummel:BAAALgAECgYJCwAAAA==.Pupperputh:BAAALgADCgkJEgABLgAECgkJIgAIAJ0dAA==.Puppet:BAAALgAECgEJAwAAAA==.',
['Pä']='Päroxysm:BAAALgAECgEJAgABLgAECgYJBgAMAAAAAA==.',
Qu='Quígon:BAAALgAECgIJAwABLgAECgcJBQAMAAAAAA==.',
Ra='Rach:BAAALgAECgEJAQAAAA==.Randyrando:BAAALgADCgIJBAAAAA==.Ranoe:BAABLgAECn8jAAIIAAcJCRbzVAClAQAIAAcJCRbzVAClAQAAAA==.Rastrin:BAAALgADCgcJDgAAAA==.Ravyniel:BAAALgAECgEJAQAAAA==.Razji:BAABLgAECn9DAAQQAAkJ1yTTAQA3AwAQAAkJPiTTAQA3AwARAAcJsSENGABtAgAHAAIJiSbQgQDjAAAAAA==.',
Re='Redrrum:BAAALgAECgcJCgAAAA==.Rekd:BAAALgADCgEJAQAAAA==.Reladiia:BAAALgAECgEJAQAAAA==.Renfro:BAAALgADCgcJBwAAAA==.Restokhan:BAAALgAFFAEJAQAAAA==.Revoked:BAAALgADCgEJAQABLgAECgYJDwAMAAAAAA==.Reznick:BAABLgAECn8ZAAISAAgJ6g5BNgBnAQASAAgJ6g5BNgBnAQAAAA==.',
Ro='Rocknwolf:BAAALgAECgEJAQAAAA==.Rokd:BAAALgAECgcJDQAAAA==.Rokham:BAAALgADCgEJAQAAAA==.Rosalee:BAAALgAECgQJAQAAAA==.Rovërgalarga:BAAALgADCgMJAwAAAA==.',
Ru='Rudeboy:BAAALgAECgEJAQAAAA==.Ruibaron:BAABLgAECn8VAAIBAAYJDxcSkQBQAQABAAYJDxcSkQBQAQAAAA==.',
Ry='Ryhunter:BAAALgADCggJDgAAAA==.',
['Rà']='Ràidèn:BAABLgAECn8yAAIWAAkJKSDsFwCvAgAWAAkJKSDsFwCvAgAAAA==.',
['Rá']='Ráyne:BAAALgAECgYJDgAAAA==.',
Sa='Sadeel:BAABLgAECn8sAAMmAAkJVhrtCwCMAQAiAAkJdBKmRQD6AQAmAAcJKB3tCwCMAQAAAA==.Sadewolf:BAACLgAFFH8FAAIIAAMJLA7AXgDBAAAIAAMJLA7AXgDBAAAuAAQKfykAAggACQnrG5QbAGUCAAgACQnrG5QbAGUCAAAA.Sadpanduh:BAAALgAECgYJEAAAAA==.Saltednuts:BAAALgAECgEJAQAAAA==.Samentoni:BAACLgAFFH8IAAIEAAMJTRbkKgDHAAAEAAMJTRbkKgDHAAAuAAQKfyoAAgQACQljGwQPAJwCAAQACQljGwQPAJwCAAAA.Samgal:BAABLgAECn8bAAIjAAkJtBiwBAAkAgAjAAkJtBiwBAAkAgAAAA==.Sardothien:BAAALgAECgEJAgAAAA==.Satyra:BAAALgAECgcJEgABLgAECgkJKAAFAFgkAA==.Saurphang:BAACLgAFFH8bAAMWAAUJdBUeGABFAQAWAAQJdBUeGABFAQAJAAEJAACmXwAAAAAuAAQKfywAAhYACQlOIhIVAP0CABYACQlOIhIVAP0CAAAA.Saye:BAAALgADCgIJAgAAAA==.',
Sc='Scarletpanda:BAAALgADCgQJBgAAAA==.Scourgereap:BAAALgAECgUJBgAAAA==.',
Se='Selinna:BAAALgAECggJEgAAAA==.Semperfi:BAAALgADCgYJBgAAAA==.Senpaichill:BAAALgAECgYJDQAAAA==.Severis:BAAALgADCgIJAgAAAA==.',
Sg='Sgtmajdaly:BAAALgADCgMJAwAAAA==.',
Sh='Shadiepope:BAAALgAECgIJAwAAAA==.Shadora:BAABLgAECn8gAAIGAAkJLBN/GwDiAQAGAAkJLBN/GwDiAQAAAA==.Shadowsaja:BAAALgAECgcJBwAAAA==.Shadowwizard:BAAALgAECgMJAwAAAA==.Shadybrat:BAAALgAECgYJDQABLgAFFAIJBwAHAKkHAA==.Shaggylol:BAAALgADCgcJDQAAAA==.Shaladin:BAAALgAECgcJBgAAAA==.Shamlazy:BAAALgADCgkJHQAAAA==.Shennka:BAAALgAECgEJAgAAAA==.Shidan:BAAALgAECggJEAABLgAECgkJMgAWACkgAA==.Shiroku:BAAALgAECgkJBgAAAA==.Shockchalk:BAACLgAFFH8bAAIbAAUJAyYXAwCVAQAbAAUJAyYXAwCVAQAuAAQKfzYAAxsACQnhJc4AAEwDABsACQnhJc4AAEwDAAMAAglhEWB7AGoAAAAA.Shocknorris:BAAALgAECgQJBwABLgAECgYJDwAMAAAAAA==.Shrooclaw:BAACLgAFFH8NAAIOAAMJsxBsOwC6AAAOAAMJsxBsOwC6AAAuAAQKfx4AAw4ACQnYEwUyAM0BAA4ACQnYEwUyAM0BABUAAgkGHaE9AFQAAAAA.',
Si='Sibbiah:BAAALgAECggJCAAAAA==.Silanre:BAABLgAECn8yAAIBAAgJDBftTgDpAQABAAgJDBftTgDpAQAAAA==.',
Sk='Skaðï:BAACLgAFFH8OAAMHAAQJ2CCcGwB/AQAHAAQJ2CCcGwB/AQARAAEJPRJvMQBFAAAuAAQKfzQABBEACQkOI64DAH8CABEACAnQI64DAH8CABAABAnvGc0sADkBAAcAAwnpHrLJAKIAAAAA.',
Sl='Slizzard:BAAALgADCgQJBAABLgAFFAQJDQAdAPoXAA==.',
Sm='Smolshrapnel:BAABLgAECn8WAAIQAAcJ0ATOMgASAQAQAAcJ0ATOMgASAQAAAA==.',
Sn='Sneakchalk:BAAALgADCgcJCwABLgAFFAUJGwAbAAMmAA==.',
So='Solaraze:BAABLgAECn8vAAQXAAkJXh3ULgA6AgAXAAgJCR7ULgA6AgAEAAIJdBApbgBuAAANAAEJLQaGUgAiAAAAAA==.Solinarie:BAAALgADCggJCgAAAA==.Sorefang:BAAALgADCgEJAQAAAA==.Sorrowfang:BAAALgAECgEJAQAAAA==.Soulfkr:BAAALgAECgQJBAAAAA==.Sovnightwar:BAAALgAECggJDwABLgAFFAUJCwAIACAcAA==.Soza:BAAALgADCgEJAQAAAA==.',
Sp='Spacespecial:BAAALgAECggJEwAAAA==.Sparklebunny:BAAALgADCgEJAQAAAA==.Spicycurryy:BAABLgAECn8+AAQHAAkJuB8/GgBqAgAHAAgJeCA/GgBqAgAQAAgJvxcSFAACAgARAAIJJAzGeABeAAABLgAECgkJPgAHALgfAA==.Spicyycurryy:BAAALgAECgUJCwABLgAECgkJPgAHALgfAA==.Spiker:BAAALgAECgEJAQAAAA==.Splittail:BAAALgAECgUJBQAAAA==.',
St='Staggertrip:BAAALgADCgQJBAABLgAFFAUJBgAIAJkWAA==.Strahm:BAABLgAECn8mAAIPAAgJTxIjGgBrAQAPAAgJTxIjGgBrAQAAAA==.Strehm:BAAALgAECgQJBgABLgAECggJJgAPAE8SAA==.Strohmjr:BAAALgAECgMJAwABLgAECggJJgAPAE8SAA==.Strohmy:BAAALgADCgEJAQABLgAECggJJgAPAE8SAA==.Stryhm:BAAALgAECgQJBwABLgAECggJJgAPAE8SAA==.',
Su='Sunju:BAAALgADCgMJAwAAAA==.',
Sy='Sylvexa:BAAALgAECgEJAgAAAA==.Syns:BAAALgAECgYJCgAAAA==.Syssare:BAABLgAECn8pAAIaAAkJAyQCAwAgAwAaAAkJAyQCAwAgAwAAAA==.',
['Sé']='Sétt:BAAALgAECgUJBQAAAA==.',
Ta='Tabbie:BAAALgADCgYJCQAAAA==.Tacpally:BAAALgAECgYJBwAAAA==.Talasam:BAAALgAECgkJEQAAAA==.Talien:BAAALgADCgEJAQAAAA==.Tandsonnara:BAAALgAECgkJDAAAAA==.Tastetickle:BAACLgAFFH8KAAIBAAQJDg9KWwApAQABAAQJDg9KWwApAQAuAAQKfzUAAgEACQkvHxMdAKcCAAEACQkvHxMdAKcCAAAA.Tavv:BAAALgAFFAIJAwABLgAFFAYJCAAdABsPAA==.Tazdrin:BAACLgAFFH8OAAInAAQJXgn0BgAKAQAnAAQJXgn0BgAKAQAuAAQKfzIAAicACQkmF0QFAA0CACcACQkmF0QFAA0CAAAA.',
Te='Tears:BAAALgAECgUJBQAAAA==.Telidrus:BAACLgAFFH8WAAIBAAcJlxl8HQDzAQABAAcJlxl8HQDzAQAuAAQKfy8ABAEACAn7IGkxAK0CAAEABwlBJGkxAK0CACQABAnMHV4GAE0BACEAAglcE3IRADkAAAAA.Temok:BAAALgADCggJCAAAAA==.Teyrlis:BAAALgAECgUJCAAAAA==.',
Th='Thavryn:BAAALgADCgYJBgAAAA==.Thaz:BAAALgAECgQJBwAAAA==.Thias:BAABLgAECn8kAAIBAAgJfRYMTwDoAQABAAgJfRYMTwDoAQAAAA==.Thukmonk:BAAALgAECgQJBwAAAA==.Thukwarlock:BAABLgAECn8hAAIiAAcJ7xgoSQDuAQAiAAcJ7xgoSQDuAQAAAA==.Thunderbug:BAAALgADCgEJAQAAAA==.Thunderhorse:BAAALgADCgUJBQAAAA==.',
To='Todd:BAAALgAECgEJAQAAAA==.Tokain:BAAALgAECgMJAwAAAA==.Topaze:BAAALgAECgUJCAAAAA==.Torironheart:BAAALgADCgcJBwAAAA==.',
Tr='Trance:BAAALgAECgEJAQABLgAECgEJAQAMAAAAAA==.Treehuggera:BAAALgAECgYJCgAAAA==.Tribunal:BAAALgAECgEJAQAAAA==.Trilila:BAAALgADCgYJBgAAAA==.Tripx:BAABLgAECn8cAAMXAAkJbiMRBwAuAwAXAAkJbiMRBwAuAwANAAEJ2A8CRgAoAAABLgAFFAUJBgAIAJkWAA==.Tronko:BAABLgAECn8lAAMCAAkJHBz9FACXAgACAAkJHBz9FACXAgADAAEJ8BNvmQA0AAAAAA==.Trumpinator:BAAALgADCgYJDAAAAA==.',
Ts='Tsireya:BAAALgAECgUJCgABLgAECgQJDgAMAAAAAA==.',
Tu='Tullip:BAAALgAECgEJAQAAAA==.Turntsnaco:BAACLgAFFH8JAAIcAAIJZBrYKwCoAAAcAAIJZBrYKwCoAAAuAAQKf0QAAxwACAnnIaUKAG4CABwACAnnIaUKAG4CACgAAQmYFnMiAEQAAAAA.Tusk:BAAALgAECgcJEQAAAA==.',
Tw='Twigger:BAAALgAECgEJAQAAAA==.Twiztedsoul:BAAALgAECggJCwAAAA==.Twophorb:BAAALgADCgMJAwAAAA==.',
Ua='Uake:BAAALgADCgYJBgAAAA==.',
Ud='Udgar:BAAALgAECgkJEQAAAA==.',
Un='Unafhaen:BAAALgADCgEJAQAAAA==.Unaverse:BAAALgAECgEJAQAAAA==.',
Us='Usmc:BAAALgADCgYJBgAAAA==.Usmccpl:BAAALgAECgcJEQAAAA==.Usmcsemperfi:BAAALgAECgQJBAAAAA==.',
Va='Valengarde:BAACLgAFFH8HAAIXAAMJcw1VaADNAAAXAAMJcw1VaADNAAAuAAQKfxsAAhcACQmYFqBIAOIBABcACQmYFqBIAOIBAAAA.Vanette:BAAALgAECgIJAgAAAA==.Vangoon:BAAALgAECgQJBAABLgAECgYJCQAMAAAAAA==.Vannix:BAACLgAFFH8KAAIGAAQJuCDFDQBwAQAGAAQJuCDFDQBwAQAuAAQKfzcAAgYACQmSIzYEABQDAAYACQmSIzYEABQDAAAA.Vanz:BAAALgADCgIJAgABLgAECgYJCQAMAAAAAA==.Varnos:BAAALgAECgEJAwAAAA==.',
Ve='Velranis:BAAALgADCgMJAwABLgAECgkJFAAgABoWAA==.Velthas:BAAALgADCggJIQAAAA==.',
Vi='Viollet:BAAALgAECgQJBgAAAA==.Virmethir:BAABLgAECn8iAAMZAAgJeBJOCACiAQAZAAgJJRJOCACiAQAKAAYJVgY2XgCzAAAAAA==.Viruz:BAAALgAECgYJCgAAAA==.',
Vo='Volley:BAAALgADCgEJAQAAAA==.Voltaren:BAAALgAECgcJDAABLgAECgkJLwAXAF4dAA==.',
Vy='Vylaran:BAAALgADCgYJBgAAAA==.Vyndrolan:BAAALgAFFAEJAQAAAA==.Vyroth:BAAALgADCgUJBQAAAA==.',
Wa='Walksonwater:BAAALgADCgEJAQABLgAECgkJJQAEAG0eAA==.Waq:BAAALgAECgcJDwAAAA==.',
We='Wellamor:BAAALgADCgIJAgAAAA==.',
Wh='Whtmg:BAAALgADCgkJCAABLgAECgcJDAAMAAAAAA==.',
Wi='Winterbreeze:BAAALgADCgYJBgAAAA==.Wiwi:BAACLgAFFH8NAAMdAAQJ+hf0CQA4AQAdAAQJdxX0CQA4AQAWAAEJPBHG+gBDAAAuAAQKfzIAAxYACQnGITQTAM0CABYACQnGITQTAM0CAB0AAwm8G5gdAM4AAAAA.',
Xa='Xares:BAACLgAFFH8JAAIBAAQJsRV7TgA9AQABAAQJsRV7TgA9AQAuAAQKfzUAAgEACQmsG14jAIoCAAEACQmsG14jAIoCAAAA.Xash:BAAALgAECgEJAQAAAA==.',
Xe='Xerath:BAAALgADCgcJBwAAAA==.',
Xh='Xhades:BAAALgAECgYJDgAAAA==.',
Ya='Yalda:BAABLgAECn8WAAIbAAYJXR0ODwCzAQAbAAYJXR0ODwCzAQAAAA==.',
Yf='Yfra:BAAALgAECggJEQAAAA==.',
Yo='Yochangsvegn:BAAALgAECggJEAAAAA==.Yoseph:BAABLgAECn8XAAIVAAgJjQ8OFwBIAQAVAAgJjQ8OFwBIAQAAAA==.',
Yu='Yungblood:BAAALgAECgUJEgAAAA==.Yurimancer:BAABLgAECn8zAAIGAAgJvRoYFgASAgAGAAgJvRoYFgASAgAAAA==.',
Za='Zaen:BAAALgADCgMJAwAAAA==.Zake:BAAALgAECgMJBAAAAA==.Zalileina:BAAALgADCgMJAwAAAA==.Zallith:BAAALgADCgMJAwABLgAECgYJDgAMAAAAAA==.Zappythile:BAABLgAECn8sAAICAAkJfxuaIQA4AgACAAkJfxuaIQA4AgAAAA==.Zarkamental:BAAALgADCgYJCwABLgAFFAMJBQAIAEcCAA==.Zarthos:BAAALgAECgEJAQABLgAECgEJAwAMAAAAAA==.',
Ze='Zect:BAABLgAECn8YAAQmAAYJLB5zDQBxAQAmAAYJOBtzDQBxAQAiAAUJZRnVogD1AAAjAAEJFBWsbwA3AAAAAA==.Zekk:BAAALgADCgcJBwAAAA==.Zelinor:BAAALgADCgcJBwAAAA==.',
Zi='Ziêg:BAAALgADCgcJBwAAAA==.',
Zo='Zoz:BAABLgAECn8aAAIBAAYJ+g4CswAZAQABAAYJ+g4CswAZAQAAAA==.',
Zu='Zulfrik:BAABLgAECn83AAIBAAkJNhnJNQA7AgABAAkJNhnJNQA7AgAAAA==.Zullard:BAAALgAECgEJAQAAAA==.',
Zy='Zyzy:BAABLgAECn8fAAIDAAkJGSIyBAAXAwADAAkJGSIyBAAXAwABLgAFFAQJBgAGAPMQAA==.',
['Zõ']='Zõke:BAAALgADCgEJAQAAAA==.',
['Òd']='Òdb:BAAALgADCgEJAQAAAA==.',
['ße']='ßeef:BAAALgADCgcJBwAAAA==.',
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
