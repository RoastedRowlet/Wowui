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

local lookup = {'Mage-Frost','Shaman-Restoration','Shaman-Elemental','Paladin-Holy','Priest-Holy','Priest-Shadow','Hunter-BeastMastery','DemonHunter-Devourer','DeathKnight-Blood','Evoker-Augmentation','Evoker-Preservation','Druid-Feral','Druid-Balance','Paladin-Protection','Druid-Restoration','Unknown-Unknown','Druid-Guardian','Hunter-Survival','Hunter-Marksmanship','Warrior-Fury','Warrior-Protection','DeathKnight-Unholy','Paladin-Retribution','Warrior-Arms','Evoker-Devastation','DemonHunter-Havoc','Shaman-Enhancement','Rogue-Subtlety','DeathKnight-Frost','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','Mage-Fire','Warlock-Demonology','Warlock-Destruction','Mage-Arcane','DemonHunter-Vengeance','Warlock-Affliction','Rogue-Outlaw','Rogue-Assassination',}
local provider = {region='US',realm='Eonar',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abbazaad:BAAALgAECgQJBQAAAA==.Abreen:BAAALgADCgcJCQAAAA==.Abysseus:BAAALgADCgcJCAAAAA==.',
Ac='Acepriest:BAAALgAECgQJCAAAAA==.Achievement:BAAALgAECgQJBAAAAA==.',
Ad='Adeathfox:BAAALgADCgEJAQAAAA==.Adhoc:BAAALgADCgUJBQAAAA==.Admired:BAABLgAECn8cAAIBAAcJoB4OVwAzAgABAAcJoB4OVwAzAgAAAA==.Adyr:BAACLgAFFH8KAAMCAAQJUhI6QgDdAAACAAQJUhI6QgDdAAADAAMJIwcVPACgAAAuAAQKfyUAAwIACAmcIMwWAJMCAAIACAmcIMwWAJMCAAMABQnlF0pNABMBAAAA.',
Ai='Aidra:BAABLgAECn8sAAIEAAgJ6hngFQBdAgAEAAgJ6hngFQBdAgAAAA==.',
Al='Alaira:BAAALgAECgMJAwABLgAECggJIgABABoJAA==.Alamora:BAABLgAECn8cAAMFAAcJzwczQQDoAAAFAAcJzwczQQDoAAAGAAYJDwTDWwCnAAAAAA==.Alastair:BAAALgAECgcJCAAAAA==.Alathena:BAAALgAECgcJDAAAAA==.Albinoz:BAAALgADCgIJAgAAAA==.Albrect:BAAALgADCgYJFgAAAA==.Aldrich:BAAALgADCgEJAQAAAA==.Alexandrya:BAACLgAFFH8KAAIHAAMJewgaawDOAAAHAAMJewgaawDOAAAuAAQKfy4AAgcACQlPF+wyABECAAcACQlPF+wyABECAAAA.Alicemalkin:BAABLgAECn8XAAIIAAkJHxTyPQD8AQAIAAkJHxTyPQD8AQAAAA==.Alonai:BAAALgAECgYJBgAAAA==.Alphred:BAAALgAECgEJAgAAAA==.Alunira:BAAALgADCgIJAgAAAA==.Alysse:BAAALgADCgUJBwAAAA==.',
Am='Amarysia:BAAALgAECgYJDQAAAA==.Ameriixs:BAAALgAECgIJAgAAAA==.Amháin:BAAALgAECggJDQAAAA==.Amsip:BAAALgAECgEJAQABLgAECgkJJAAJABYPAA==.Amsroeb:BAABLgAECn8kAAIJAAkJFg+lHwBXAQAJAAkJFg+lHwBXAQAAAA==.',
An='Anelavenger:BAACLgAFFH8HAAIKAAMJpw7ZRwCqAAAKAAMJpw7ZRwCqAAAuAAQKfy0AAwoACQneHMwMAKkCAAoACQneHMwMAKkCAAsAAwlcAS1EAE0AAAAA.Angerwina:BAAALgADCgUJCQAAAA==.Anggar:BAAALgADCgIJAgAAAA==.',
Ao='Aomori:BAAALgAECgcJBwAAAA==.',
Aq='Aquini:BAABLgAFFH8IAAMMAAMJfAcUAQC7AAAMAAMJ2wYUAQC7AAANAAIJ3AWwRQBgAAAAAA==.Aqüilés:BAAALgAECgEJAwAAAA==.',
Ar='Arathor:BAABLgAECn8nAAIOAAkJbRxeBgCBAgAOAAkJbRxeBgCBAgAAAA==.Arctorius:BAAALgADCgEJAQAAAA==.Arent:BAABLgAECn9EAAIPAAkJ+xXSIwAsAgAPAAkJ+xXSIwAsAgAAAA==.Arfy:BAAALgADCgMJAgABLgAECggJEQAQAAAAAA==.Argil:BAAALgAECgEJAQABLgAECggJKAARAMgTAA==.Argøn:BAABLgAECn88AAQHAAkJMxsNHgBxAgAHAAkJMxsNHgBxAgASAAUJ2AhDRACwAAATAAEJkAYUkgAoAAAAAA==.Arkanna:BAAALgAECgEJAQAAAA==.Arrise:BAAALgAECgUJBwAAAA==.Artemislives:BAAALgAECgcJEQAAAA==.Arthuaca:BAAALgAECgYJDQAAAA==.',
As='Asharia:BAABLgAECn8QAAIIAAcJjRFeaABVAQAIAAcJjRFeaABVAQAAAA==.Ashog:BAAALgADCgYJCwAAAA==.Assateague:BAABLgAECn8eAAIUAAcJewVjWwDkAAAUAAcJewVjWwDkAAAAAA==.Astelossa:BAAALgAECgEJAQAAAA==.Astralie:BAAALgADCggJFAAAAA==.Asuya:BAAALgADCgYJCQAAAA==.',
At='Athereos:BAAALgADCgYJBQAAAA==.Athylan:BAAALgADCgEJAQABLgAFFAYJFwAEAIgcAA==.Atrosity:BAABLgAECn8tAAIVAAkJpiI0BQDIAgAVAAkJpiI0BQDIAgAAAA==.',
Au='Aurorabane:BAAALgADCgYJEAAAAA==.',
Av='Avelleah:BAAALgAECgEJBAAAAA==.',
Az='Azulyne:BAAALgADCgIJAgAAAA==.Azuretorrent:BAAALgADCgQJBAAAAA==.',
Ba='Bananapistol:BAAALgAECgUJBQAAAA==.Barracksbuny:BAAALgAECgUJBgABLgAECgUJBwAQAAAAAA==.Barrathfrogy:BAAALgADCgYJFQAAAA==.Barthal:BAAALgAECgEJAQAAAA==.',
Be='Bebheishel:BAAALgADCgYJCwAAAA==.Bellatrix:BAAALgAECgMJAwABLgAECgQJDgAQAAAAAA==.Bertelo:BAAALgADCgUJBQAAAA==.',
Bi='Bigstinky:BAAALgAECgYJDAABLgAECgkJPAAHADMbAA==.Bilywitchdoc:BAAALgAFFAIJAwABLgAECgkJQwASANckAA==.Bisao:BAAALgAECgIJAgAAAA==.Biscuít:BAABLgAECn8pAAMNAAkJiA6LLQBtAQANAAkJiA6LLQBtAQAMAAEJqAfVXwAiAAAAAA==.',
Bl='Blasuoff:BAAALgAECgQJBAAAAA==.Bloodrains:BAAALgAECgEJAwAAAA==.Bloodyfate:BAAALgADCgUJBQAAAA==.',
Bo='Bonesentinel:BAABLgAECn8YAAIHAAcJNSLCJABQAgAHAAcJNSLCJABQAgABLgAFFAUJDQAWAN0ZAA==.Bonës:BAAALgADCgEJAQAAAA==.Bora:BAAALgAECgQJDgAAAA==.Borzoi:BAABLgAFFH8VAAIXAAQJhSOdHwCJAQAXAAQJhSOdHwCJAQAAAA==.Bourgùîgnon:BAAALgADCgcJCgAAAA==.',
Br='Bragasch:BAAALgADCgkJGQAAAA==.Brakhon:BAAALgAECgEJAgAAAA==.Bruisebrews:BAAALgADCgEJAQAAAA==.',
Bu='Bullplop:BAAALgADCgUJBQAAAA==.Burekbazino:BAAALgADCgcJCQAAAA==.Burningsleet:BAAALgAECgYJBgABLgAFFAgJEAAWAI8WAA==.',
['Bò']='Bò:BAACLgAFFH8TAAINAAUJ0wcjBAC1AAANAAUJ0wcjBAC1AAAuAAQKfzEAAg0ACQmpF+IUACoCAA0ACQmpF+IUACoCAAAA.',
Ca='Caduceus:BAAALgADCgcJGAAAAA==.Caesus:BAABLgAECn8cAAIGAAcJFxclJQChAQAGAAcJFxclJQChAQAAAA==.Cagedancer:BAABLgAECn8iAAQMAAgJQwv7HAAjAQAMAAgJHQr7HAAjAQANAAYJyAaNUADmAAAPAAEJFAPY/AAYAAAAAA==.Callio:BAACLgAFFH8HAAIHAAQJ7QQPVwD4AAAHAAQJ7QQPVwD4AAAuAAQKfy8AAgcACQmbET5HAMwBAAcACQmbET5HAMwBAAAA.Cantor:BAAALgAECgEJAQAAAA==.Caradd:BAAALgAECgcJCwAAAA==.Catchclause:BAAALgADCgkJFAAAAA==.Cathillex:BAABLgAECn8aAAMUAAkJTxcWGgAdAgAUAAkJTxcWGgAdAgAYAAEJ1AKqjAAVAAAAAA==.Cattlesdaddy:BAAALgAECgEJAQABLgAECggJKAARAMgTAA==.Cavagos:BAACLgAFFH8KAAIZAAQJKBAPBQAZAQAZAAQJKBAPBQAZAQAuAAQKfzYAAhkACQlWIAQCALcCABkACQlWIAQCALcCAAAA.Caycay:BAACLgAFFH8bAAIaAAYJISIBBQDCAQAaAAYJISIBBQDCAQAuAAQKf1IAAhoACQnAJmcAAI4DABoACQnAJmcAAI4DAAAA.Cayleq:BAAALgAECgUJBAABLgAFFAYJGwAaACEiAA==.',
Ce='Celebrexi:BAAALgAECgcJBgAAAA==.Celene:BAAALgADCgYJBwAAAA==.Celtic:BAAALgADCgEJAQAAAA==.Cerrulli:BAAALgAECgYJDwAAAA==.',
Ch='Chaosknight:BAABLgAECn8YAAMDAAgJSRKzLwCBAQADAAgJSRKzLwCBAQACAAUJUAofngCUAAAAAA==.Chaostrip:BAACLgAFFH8GAAIIAAUJmRYdQgAhAQAIAAUJmRYdQgAhAQAuAAQKfzIAAggACQknI7gIAAgDAAgACQknI7gIAAgDAAAA.Chariso:BAAALgAECgEJAQAAAA==.Cheddar:BAAALgAFFAEJAQAAAA==.Chillbros:BAACLgAFFH8RAAIbAAYJ1B0oBACKAQAbAAYJ1B0oBACKAQAuAAQKfywAAxsACQkTJGsCAPYCABsACQkTJGsCAPYCAAMABAmqH+45AGcBAAAA.Chilldh:BAAALgAECgUJBQABLgAFFAYJEQAbANQdAA==.Chillmage:BAAALgADCgcJCgABLgAFFAYJEQAbANQdAA==.Chindi:BAABLgAECn8xAAMUAAkJ7xebIgDeAQAUAAkJKxabIgDeAQAVAAcJUBIfHABWAQAAAA==.Chindrakh:BAAALgAECggJEAABLgAECgkJMQAUAO8XAA==.Choiminasue:BAAALgAECgEJAgAAAA==.Chunga:BAABLgAECn8UAAIDAAYJoAPZXADQAAADAAYJoAPZXADQAAAAAA==.Chungers:BAAALgAECgQJBgAAAA==.Churd:BAACLgAFFH8PAAIGAAMJhhVpIwDaAAAGAAMJhhVpIwDaAAAuAAQKfykAAgYACQnkGFYSAEECAAYACQnkGFYSAEECAAAA.Churdicus:BAAALgADCgkJEQAAAA==.Chypnotic:BAAALgAECggJDAAAAA==.Chypper:BAAALgADCgEJAQAAAA==.Chypster:BAABLgAECn8kAAIDAAgJMg5JPQBAAQADAAgJMg5JPQBAAQAAAA==.',
Ci='Ciceroe:BAABLgAFFH8QAAIcAAQJNhIzGwA/AQAcAAQJNhIzGwA/AQAAAA==.Citadel:BAAALgADCgIJAwAAAA==.',
Cl='Cleft:BAABLgAECn8cAAIXAAgJDxKhAQCRAQAXAAgJDxKhAQCRAQAAAA==.Clevelandk:BAAALgAECgUJCQAAAA==.Clowwnshoes:BAAALgAECgEJAgAAAA==.',
Co='Coalystra:BAACLgAFFH8YAAIIAAUJKxx+BAAyAQAIAAUJKxx+BAAyAQAuAAQKfywAAggACQnsGkYhAE4CAAgACQnsGkYhAE4CAAAA.Cocopuffs:BAACLgAFFH8HAAINAAIJsBG2FACfAAANAAIJsBG2FACfAAAuAAQKfzUAAg0ACQleICMJAAMDAA0ACQleICMJAAMDAAAA.Colostrom:BAACLgAFFH8VAAIOAAUJdBxXAAAkAQAOAAUJdBxXAAAkAQAuAAQKfy8AAg4ACQnVHwgHAHECAA4ACQnVHwgHAHECAAAA.Complicatedz:BAAALgAECgUJBQAAAA==.Comul:BAAALgADCgcJBwAAAA==.Coramage:BAABLgAECn8aAAIBAAkJjwaChgBqAQABAAkJjwaChgBqAQAAAA==.Corentis:BAAALgADCgYJBgAAAA==.Corliss:BAABLgAECn8hAAIVAAkJfxbzDwDpAQAVAAkJfxbzDwDpAQAAAA==.Cornholeo:BAAALgADCgkJCQAAAA==.',
Cp='Cplusmc:BAAALgAECgQJBwAAAA==.',
Cr='Creightizle:BAABLgAECn8eAAIHAAgJfRS/OQDHAQAHAAgJfRS/OQDHAQAAAA==.',
Cu='Cuddaloft:BAAALgAECgQJBAAAAA==.',
['Cá']='Cátix:BAAALgADCgMJAwAAAA==.',
Da='Daicmerollin:BAAALgAECgYJCwAAAA==.Danhaüsen:BAAALgAECgIJAwAAAA==.Darkbeast:BAABLgAFFH8JAAIHAAQJOQ8xRQAjAQAHAAQJOQ8xRQAjAQAAAA==.Darkdeeds:BAAALgADCggJEQAAAA==.Darkpallo:BAABLgAECn8YAAIXAAcJPxPWbwCdAQAXAAcJPxPWbwCdAQABLgAFFAQJCQAHADkPAA==.Darthtav:BAABLgAFFH8IAAIdAAYJGw/VCABgAQAdAAYJGw/VCABgAQABLgAFFAcJEgANAIERAA==.Daten:BAABLgAECn9LAAIXAAkJzRWcbQCTAQAXAAkJzRWcbQCTAQAAAA==.Dazshauran:BAAALgADCggJCAAAAA==.Daîma:BAAALgADCggJCAAAAA==.',
Db='Dbltap:BAAALgADCgEJAQAAAA==.',
De='Deathbycow:BAABLgAECn8rAAIRAAgJlhz7CwAiAgARAAgJlhz7CwAiAgAAAA==.Debra:BAAALgADCgUJBQAAAA==.Decayed:BAABLgAECn8lAAIJAAkJfhsbDABLAgAJAAkJfhsbDABLAgABLgAECgUJBwAQAAAAAA==.Deipally:BAAALgAECgYJBQAAAA==.Demonchalk:BAACLgAFFH8IAAIIAAUJohOiQwAcAQAIAAUJohOiQwAcAQAuAAQKfx0AAggABglqI281APABAAgABglqI281APABAAEuAAUUBgkcABsADSYA.Desdeynna:BAAALgADCgEJAQAAAA==.Deseral:BAAALgAECgIJAgAAAA==.Dewbie:BAAALgAECgEJAQAAAA==.',
Di='Diagonalli:BAABLgAECn8fAAIZAAkJNA8ACAC1AQAZAAkJNA8ACAC1AQAAAA==.Dimmadome:BAAALgADCgEJAQAAAA==.Dinojam:BAAALgADCgMJAQAAAA==.Divirian:BAAALgAECgYJDwAAAA==.',
Dj='Djdaemon:BAAALgAECgYJCwAAAA==.Djdrakshadow:BAAALgAECgQJCAAAAA==.Djpaly:BAAALgAECgYJCgAAAA==.Djpriest:BAAALgAECgUJDQAAAA==.Djshadow:BAABLgAECn8VAAIBAAYJzQO/BgCtAAABAAYJzQO/BgCtAAAAAA==.Djshadowar:BAAALgAECgUJDQAAAA==.Djshadowhunt:BAAALgAECgYJCgAAAA==.Djshadowlock:BAAALgAECgYJDwAAAA==.Djshadowrog:BAAALgAECgYJEAAAAA==.Djshamy:BAAALgAECgYJCQAAAA==.Djshaolin:BAAALgAECgUJDwAAAA==.Djzhadow:BAAALgAECgYJEwAAAA==.Djzhadruid:BAAALgAECgQJCwAAAA==.',
Dk='Dkshadow:BAAALgAECgQJBwAAAA==.',
Dm='Dmitrì:BAAALgAECgEJAQAAAA==.',
Do='Dogno:BAAALgAECgEJAgAAAA==.Dontdieplez:BAAALgAECgkJDAAAAA==.Doofuss:BAAALgADCgIJAgAAAA==.',
Dp='Dpm:BAAALgAECgEJAgAAAA==.',
Dr='Dragbuttakis:BAAALgAECgUJCAAAAA==.Drakhadir:BAAALgAECgQJCwAAAA==.Drakmon:BAAALgAECgIJBQAAAA==.Draktând:BAABLgAECn8vAAIcAAgJVhnQFAD7AQAcAAgJVhnQFAD7AQAAAA==.Drewski:BAAALgAECggJCAAAAA==.Drippysilk:BAAALgAECgQJCAABLgAECgkJJAAXAE4fAA==.Drius:BAAALgADCgMJAwAAAA==.Drunkenpanda:BAACLgAFFH8FAAMeAAMJxAPhLwCFAAAeAAMJxAPhLwCFAAAfAAEJqgmTaQArAAAuAAQKfyUAAx8ACQn0FHYjAAQCAB8ACQn0FHYjAAQCAB4ABwnWCNNOAMoAAAAA.Drunknoodle:BAAALgAECgQJCAAAAA==.',
Du='Duhpriest:BAAALgAECgEJAQAAAA==.Duinrane:BAAALgAECgEJAQAAAA==.Duon:BAABLgAECn8WAAQeAAkJ3hSxIQCiAQAeAAgJexaxIQCiAQAfAAIJzwmCYQBJAAAgAAIJkgU4hgBAAAAAAA==.',
Dw='Dwagonfur:BAAALgAECgcJBgAAAA==.',
Ec='Echö:BAACLgAFFH8YAAIaAAUJqRN/AQDzAAAaAAUJqRN/AQDzAAAuAAQKfyEAAhoACAl5GT8SAAkCABoACAl5GT8SAAkCAAAA.',
Ei='Eiarinos:BAAALgADCgEJAQAAAA==.Eirø:BAAALgADCgkJCQABLgAFFAUJGAAHAIkhAA==.',
El='Elaine:BAAALgAFFAMJAwAAAA==.Elberon:BAAALgAECgUJEgABLgAECgYJDAAQAAAAAA==.Ellspeth:BAAALgAECgkJCgAAAA==.Elmerhomero:BAAALgADCgUJBQAAAA==.Elronnd:BAAALgAECgUJBwAAAA==.Elsebeth:BAAALgADCgcJCAAAAA==.',
Em='Emilie:BAAALgADCgYJBgAAAA==.',
En='Enoch:BAABLgAECn8bAAIXAAYJkBZXfwB7AQAXAAYJkBZXfwB7AQAAAA==.',
Er='Eriam:BAAALgAECgMJAwABLgAECgkJJAARAE4ZAA==.Errane:BAACLgAFFH8bAAIPAAcJ/CFACQBkAgAPAAcJ/CFACQBkAgAuAAQKfy0AAw8ACAnJJosEAEYDAA8ACAnJJosEAEYDAA0AAQnHFVJ4AEQAAAAA.Eruiluvatar:BAAALgAECgYJCAAAAA==.',
Et='Etalia:BAAALgAECgIJBAAAAA==.Etcetera:BAAALgAECgMJBAAAAA==.',
Ev='Eveliel:BAAALgAECgEJAQAAAA==.',
Ex='Exlibris:BAAALgADCgcJDAAAAA==.',
Fa='Fallenangell:BAAALgADCgUJBQAAAA==.Fandiirn:BAAALgADCgYJBgAAAA==.Fastjack:BAABLgAECn8oAAMFAAkJVBPCLwBRAQAFAAYJlxXCLwBRAQAGAAkJTgd3PQAbAQAAAA==.',
Fe='Felseeker:BAAALgADCgkJCQABLgAECgkJRgABAI4ZAA==.',
Fi='Fiora:BAAALgADCgYJCwAAAA==.Firbirl:BAAALgAECgIJAgAAAA==.Fistoffury:BAABLgAECn8ZAAMgAAcJqBMHOAAcAQAgAAcJqBMHOAAcAQAeAAQJOAkEWgCoAAAAAA==.Fitco:BAAALgADCgYJCwABLgAECgYJDwAQAAAAAA==.Fiènd:BAAALgADCgYJBgAAAA==.',
Fl='Flametar:BAAALgAECgEJAQAAAA==.Floodlust:BAAALgADCgEJAQAAAA==.Floppydisk:BAAALgAECgUJDgAAAA==.',
Fo='Fortiss:BAACLgAFFH8KAAICAAMJ/hYkRQDVAAACAAMJ/hYkRQDVAAAuAAQKfysAAwIACQnWG0gOAOICAAIACQnWG0gOAOICAAMABgk/EBNTAO0AAAAA.',
Fr='Freelo:BAAALgAECgQJCQAAAA==.Frito:BAAALgAECggJCQAAAA==.Frost:BAAALgAFFAIJAgABLgAFFAgJJAASACwWAA==.Frostmon:BAABLgAECn8cAAIWAAkJLxcBLgBHAgAWAAkJLxcBLgBHAgAAAA==.Frshnvrfrzn:BAAALgAECggJDwAAAA==.Frøzenblight:BAAALgAECgEJAQAAAA==.',
Fu='Fulmo:BAAALgADCgUJBQABLgAFFAQJCAAWAJsEAA==.Furbee:BAAALgAECggJEQAAAA==.Furn:BAAALgAECgkJAQAAAA==.',
['Fá']='Fáde:BAAALgADCgQJBQABLgAECgcJDQAQAAAAAA==.',
Ga='Gabris:BAAALgADCgYJBgAAAA==.Galeandra:BAABLgAECn8hAAIGAAkJZQcwNQBDAQAGAAkJZQcwNQBDAQAAAA==.Gallo:BAAALgADCggJDQAAAA==.Garim:BAAALgADCgMJBAABLgAECgkJKAAFAFQTAA==.',
Ge='Geraltofrvia:BAAALgAECgkJDgAAAA==.',
Gg='Gg:BAAALgAFFAIJBAABLgAFFAgJIQAhAEIkAA==.',
Gi='Giantgoose:BAAALgAECgEJAgAAAA==.',
Gn='Gnar:BAABLgAECn8tAAIWAAgJ+RK0WgC2AQAWAAgJ+RK0WgC2AQAAAA==.',
Go='Gowtherdead:BAAALgADCgQJBAAAAA==.Gowtherpunch:BAACLgAFFH8YAAIgAAUJOge6AgDZAAAgAAUJOge6AgDZAAAuAAQKfzEAAiAACQm5FQkXAPEBACAACQm5FQkXAPEBAAAA.',
Gr='Gregzug:BAAALgAECgMJAwAAAA==.Grendel:BAAALgAECgUJBAABLgAFFAQJCAAWAJsEAA==.Greyjoy:BAAALgADCgYJBQAAAA==.Grimfury:BAAALgAFFAIJBAAAAA==.Grimsy:BAAALgADCgYJBwAAAA==.Grodd:BAAALgADCgUJBQAAAA==.Groqqu:BAAALgAECgQJBAAAAA==.Grumble:BAAALgAECgYJCAAAAA==.Gruxxiron:BAAALgAECgYJDwABLgAECgkJOwAWAIIfAA==.',
Gu='Gulnn:BAABLgAECn8zAAMiAAkJJh3lFgCbAgAiAAkJJh3lFgCbAgAjAAIJVhT8VABvAAAAAA==.Gumby:BAAALgADCgYJBgAAAA==.',
Ha='Haelena:BAABLgAECn8pAAMEAAgJPhBwLgCjAQAEAAgJPhBwLgCjAQAOAAEJYwOWWQAcAAAAAA==.Halys:BAAALgADCgUJBQAAAA==.Hamil:BAAALgADCgEJAQAAAA==.Harmoss:BAAALgAECgcJBwABLgAFFAQJBgAiAOEJAA==.Hawk:BAAALgADCgYJBgAAAA==.',
He='Heartsfang:BAAALgADCgUJCAAAAA==.Helfire:BAAALgADCgYJBgABLgAECgcJDQAQAAAAAA==.Hellscreems:BAAALgADCgMJAwAAAA==.Heriotza:BAACLgAFFH8IAAIWAAQJmwQtjwDsAAAWAAQJmwQtjwDsAAAuAAQKfxwAAhYACQmsDox9AGgBABYACQmsDox9AGgBAAAA.Herminard:BAAALgADCgIJAgABLgAECgcJDAAQAAAAAA==.',
Hx='Hxvenlyx:BAAALgADCgUJDgAAAA==.',
Ia='Iamfubar:BAAALgADCgMJBAAAAA==.',
Id='Idotyoudie:BAAALgADCgIJAgABLgAECgkJRgABAI4ZAA==.',
Ig='Igris:BAAALgAECgcJCgAAAA==.',
Ii='Iimit:BAACLgAFFH8SAAIcAAUJshn9FgBWAQAcAAUJshn9FgBWAQAuAAQKfyQAAhwACQmOG94MAFgCABwACQmOG94MAFgCAAAA.',
Il='Illidead:BAACLgAFFH8YAAIBAAYJ6ByYOgCBAQABAAYJ6ByYOgCBAQAuAAQKfyMAAwEACQnfI6c1AEICAAEACQlWIKc1AEICACQAAQlSJWYQAG0AAAAA.Iluni:BAAALgADCgMJAwAAAA==.',
Im='Implied:BAAALgADCgUJBQAAAA==.',
In='Indexes:BAABLgAECn8cAAMNAAcJPQ5ROwAkAQANAAcJbg1ROwAkAQARAAUJGgbJVgBfAAAAAA==.Insrik:BAAALgAECgcJEAAAAA==.Insurance:BAAALgAECggJCAABLgAFFAMJCgAHAHsIAA==.',
Io='Iompróirbáis:BAABLgAECn8hAAIWAAkJ7QcEfgBnAQAWAAkJ7QcEfgBnAQAAAA==.',
Ir='Irdeadohnoz:BAABLgAECn8aAAIBAAcJTAzxtQAYAQABAAcJTAzxtQAYAQAAAA==.',
Is='Ist:BAAALgAECgQJBAAAAA==.',
It='Itchigo:BAABLgAECn8UAAIHAAgJ1A3mZAB7AQAHAAgJ1A3mZAB7AQAAAA==.',
Iv='Ivern:BAAALgAECgIJAgAAAA==.Ivgorod:BAABLgAECn8kAAMZAAkJ1gjhCwBVAQAZAAkJnAjhCwBVAQAKAAgJBAZ2TAD7AAAAAA==.',
Ja='Jabbadahut:BAAALgAECgcJBQAAAA==.Jambi:BAAALgAECgYJDgAAAA==.Jardani:BAAALgAECgEJAQAAAA==.Jarhead:BAAALgADCgcJBwAAAA==.Jastrae:BAAALgAECgcJDgAAAA==.Jaziani:BAAALgADCgcJBwABLgAECgYJDAAQAAAAAA==.Jazilyne:BAAALgAECgYJDAAAAA==.',
Je='Jealous:BAAALgADCgUJBQABLgAECgkJIgAIAJ0dAA==.Jenka:BAAALgAECgUJCgAAAA==.',
Ji='Jibbs:BAAALgADCgkJCQAAAA==.',
Jo='Joleya:BAAALgADCgEJAQAAAA==.',
Ju='Junta:BAAALgADCgcJJQAAAA==.Justine:BAAALgADCgUJBQAAAA==.Justtrolling:BAAALgAECgYJDgAAAA==.',
['Jä']='Jäkel:BAAALgADCgUJBQAAAA==.',
Ka='Kalike:BAAALgADCgcJBwAAAA==.Kambative:BAABLgAECn8XAAMPAAcJqxIPQgCZAQAPAAcJqxIPQgCZAQANAAMJGBaLUgDEAAABLgAFFAUJDgAZAGcQAA==.Kambustable:BAAALgAECgQJAwABLgAFFAUJDgAZAGcQAA==.Kamchi:BAABLgAFFH8FAAIfAAUJWgyDAwAeAQAfAAUJWgyDAwAeAQABLgAFFAUJDgAZAGcQAA==.Kammunion:BAAALgAECgYJEAABLgAFFAUJDgAZAGcQAA==.Kampelis:BAAALgAECgEJAQABLgAECgcJGgABAEwMAA==.Kamphiyer:BAACLgAFFH8OAAQZAAUJZxDlCQCLAAAKAAMJ6xAqRAC2AAALAAMJKQp6IgCPAAAZAAMJ0gzlCQCLAAAuAAQKfzoABAsACQnqGEMKAD4CAAsACQnqGEMKAD4CAAoACAmIHZIUADcCABkABAmjDMExAIgAAAAA.Kamsumerage:BAAALgADCgkJEgABLgAFFAUJDgAZAGcQAA==.Kandosii:BAAALgADCgUJBQAAAA==.Kantheal:BAABLgAECn8lAAIEAAkJbR5qCQD0AgAEAAkJbR5qCQD0AgAAAA==.Kaulana:BAAALgADCgcJDAAAAA==.',
Ke='Keirmania:BAAALgAECgEJAQAAAA==.Kekkan:BAAALgADCgcJCgAAAA==.Kellendere:BAAALgAECgYJCwAAAA==.',
Ki='Kiagas:BAAALgAECgcJBwABLgAFFAQJEgAPAF4RAA==.Kiieedk:BAAALgAECgEJAQAAAA==.Kimgoeun:BAAALgADCgYJBgAAAA==.Kio:BAAALgAECgYJCAAAAA==.',
Kl='Klompus:BAAALgADCgQJBAAAAA==.',
Kn='Knùsê:BAAALgADCgUJBgABLgAFFAUJGAAHAIkhAA==.',
Ko='Komorai:BAAALgADCgYJBgAAAA==.',
Kr='Kravex:BAABLgAECn8kAAIRAAkJThmyCgA5AgARAAkJThmyCgA5AgAAAA==.Krixxa:BAABLgAECn8oAAIFAAkJWCRvAwBYAwAFAAkJWCRvAwBYAwAAAA==.',
Ku='Kuula:BAAALgAECgEJAQAAAA==.',
Ky='Kylana:BAAALgADCgQJBAABLgAECgkJIgAPABUMAA==.',
['Kä']='Kären:BAAALgAECgUJEgAAAA==.',
['Ké']='Kélly:BAAALgAECggJCAAAAA==.',
La='Laayna:BAAALgAECgEJAQAAAA==.Laochnaofa:BAAALgAECgcJDgAAAA==.Larayvia:BAACLgAFFH8NAAIHAAUJZwIWbwDDAAAHAAUJZwIWbwDDAAAuAAQKfx0AAgcACAkrDkc7AMEBAAcACAkrDkc7AMEBAAAA.Laurance:BAAALgADCgYJBgAAAA==.',
Le='Leakygasket:BAAALgAECgYJBwAAAA==.Leesala:BAACLgAFFH8RAAICAAUJgx9IAQChAQACAAUJgx9IAQChAQAuAAQKfzAAAwIACQmpFyEgAE8CAAIACQmpFyEgAE8CABsAAQn+BHtEACcAAAAA.Lelora:BAAALgAECgEJAQAAAA==.Lerazer:BAAALgAECgYJCgAAAA==.',
Lg='Lgidk:BAAALgADCgMJAwABLgAECgkJIgAIAJ0dAA==.',
Li='Lic:BAABLgAECn8aAAIHAAkJ2xLmAQCWAQAHAAkJ2xLmAQCWAQAAAA==.Liea:BAAALgAECgMJBAAAAA==.Lilbash:BAAALgAECgEJBAAAAA==.Liliatrix:BAAALgAECgQJBgAAAA==.Lillabet:BAABLgAECn8YAAIBAAcJnwxQoAA6AQABAAcJnwxQoAA6AQAAAA==.Lilmatty:BAAALgAECgkJDQABLgAFFAYJDAAfAI4dAA==.Lilsneaky:BAAALgADCggJCAAAAA==.Limpydk:BAAALgADCgUJBQABLgAECgkJJAAXAE4fAA==.Limpylarva:BAAALgADCgMJAwABLgAECgkJJAAXAE4fAA==.Limpypal:BAABLgAECn8kAAMXAAkJTh9mEQDcAgAXAAkJTh9mEQDcAgAOAAIJZATqSABEAAAAAA==.Litter:BAAALgAECgUJBQAAAA==.',
Lo='Lockém:BAAALgADCgIJAgAAAA==.Logathil:BAAALgAECgYJEAAAAA==.Loremipsum:BAAALgADCgYJCQAAAA==.',
Lu='Luchulainn:BAAALgADCgYJBgAAAA==.Lucifero:BAAALgAECggJCgAAAA==.Lucifurwild:BAAALgADCgQJBQAAAA==.Lunaaris:BAABLgAECn8rAAIPAAkJBR8tEADRAgAPAAkJBR8tEADRAgAAAA==.Lunastre:BAAALgADCgEJAQAAAA==.',
['Lí']='Límpy:BAABLgAECn8aAAIZAAYJ/CJ/CgA0AgAZAAYJ/CJ/CgA0AgABLgAECgkJJAAXAE4fAA==.Línk:BAAALgAECgYJCgAAAA==.',
['Lî']='Lîkwuid:BAAALgAECggJDwAAAA==.',
Ma='Macallan:BAAALgAECgIJBAAAAA==.Macsheesh:BAAALgADCgEJAQABLgAECggJHQAUAAEOAA==.Madbros:BAAALgAFFAMJAwABLgAFFAYJEQAbANQdAA==.Maddrox:BAAALgAECgYJCAAAAA==.Magicmarv:BAAALgADCgIJAQAAAA==.Magnagoth:BAAALgADCgkJDwAAAA==.Magnakilro:BAABLgAECn8fAAIHAAkJRxe4OwDxAQAHAAkJRxe4OwDxAQAAAA==.Mahnaz:BAAALgADCgEJAQABLgADCgcJCgAQAAAAAA==.Mahuta:BAAALgAECgEJAQAAAA==.Maisy:BAAALgAECgcJBwAAAA==.Malacove:BAAALgADCgIJBAABLgAECggJFwAKALQVAA==.Malanath:BAABLgAECn8XAAIKAAgJtBVKKQCcAQAKAAgJtBVKKQCcAQAAAA==.Malditto:BAAALgADCgYJBgAAAA==.Maleficus:BAAALgADCgkJFwABLgAECgYJFwAFACcMAA==.Malothas:BAAALgADCgQJBAAAAA==.Mareki:BAAALgADCgYJBwAAAA==.Markdfordeth:BAAALgAECgEJAQAAAA==.Mattingly:BAAALgAECgQJBQAAAA==.Mattyfu:BAACLgAFFH8MAAMfAAYJjh2rEAAKAgAfAAYJjh2rEAAKAgAeAAEJIBlJPQBJAAAuAAQKfxcAAx4ACQl7GCQdAPEBAB4ACAmWFyQdAPEBAB8ABQmhHiYwALoBAAAA.Mavíel:BAAALgAECgYJDQAAAA==.Maxrogue:BAAALgAECgYJDQABLgAECggJKAARAMgTAA==.Mazikeen:BAAALgAECgUJBgAAAA==.',
Mc='Mcscoots:BAAALgADCgcJEgABLgAFFAUJEgAcALIZAA==.',
Me='Meatsupreme:BAACLgAFFH8KAAIXAAMJyQzCdQDJAAAXAAMJyQzCdQDJAAAuAAQKfykAAhcACQm4EeReALMBABcACQm4EeReALMBAAAA.Meepin:BAACLgAFFH8XAAIEAAYJiByvCwD7AQAEAAYJiByvCwD7AQAuAAQKfzcAAwQACQkLJAQFABwDAAQACQkLJAQFABwDABcAAwk/ChIuAYIAAAAA.Meepmorp:BAAALgAECgUJBQABLgAFFAUJEgAcALIZAA==.Meifeng:BAAALgADCgEJAQAAAA==.Melithara:BAAALgAECgQJBAAAAA==.Mephala:BAAALgADCgYJBgAAAA==.Merdoc:BAAALgAECgMJAwAAAA==.Mesopewpew:BAAALgADCgMJAwABLgAECgcJHgAjAKMFAA==.Mesophistole:BAAALgADCggJCwABLgAECgcJHgAjAKMFAA==.Mesopunchy:BAAALgAECgEJAQABLgAECgcJHgAjAKMFAA==.Mesopyro:BAABLgAECn8eAAIjAAcJowUfHwCxAAAjAAcJowUfHwCxAAAAAA==.',
Mi='Mileenä:BAABLgAECn8WAAMJAAkJEhVdFQDCAQAJAAkJUxRdFQDCAQAWAAYJ0wqXxwD0AAAAAA==.Minimim:BAAALgADCgMJAwAAAA==.Mistyra:BAABLgAECn8WAAIfAAkJ+B09CQAHAwAfAAkJ+B09CQAHAwABLgAECgkJKAAFAFgkAA==.Mià:BAAALgADCgEJAQAAAA==.',
Mo='Mod:BAABLgAECn8UAAIRAAcJghU8HwBTAQARAAcJghU8HwBTAQAAAA==.Mograiné:BAAALgAECgQJCQAAAA==.Mojodaemon:BAAALgAECgEJAQAAAA==.Mojoy:BAAALgAECgQJBgAAAA==.Monkaw:BAAALgAECgIJAgAAAA==.Monkchalk:BAAALgAECgQJBQABLgAFFAYJHAAbAA0mAA==.Moondevil:BAAALgAECgEJAQAAAA==.Morta:BAEALgAFFAMJAwAAAA==.Mortkavaliro:BAABLgAECn8bAAMWAAgJtQgomQA3AQAWAAgJ9gcomQA3AQAJAAcJ2AZoNwC3AAAAAA==.',
Ms='Mslockness:BAAALgADCgYJEwAAAA==.',
Mu='Mugzy:BAAALgAECgkJBwAAAA==.Multipass:BAABLgAECn8gAAIPAAgJqiFxDgDkAgAPAAgJqiFxDgDkAgAAAA==.Multitool:BAAALgADCgEJAQAAAA==.Murder:BAAALgAECgQJCAABLgAFFAYJDAAIAPcdAA==.',
['Mö']='Mörph:BAAALgAECgIJAgAAAA==.',
Na='Nadris:BAAALgADCgcJBwAAAA==.Nanérs:BAAALgAECgcJEQABLgAFFAcJEgANAIERAA==.Narrodus:BAABLgAECn8kAAIlAAkJPSUaAQAzAwAlAAkJPSUaAQAzAwAAAA==.Nasht:BAABLgAECn8WAAIBAAYJUBa5rgAjAQABAAYJUBa5rgAjAQAAAA==.Nashty:BAAALgADCgYJBgABLgAECgYJFgABAFAWAA==.Nashxi:BAAALgADCgkJEAABLgAECgYJFgABAFAWAA==.Nasu:BAAALgAECgcJAQAAAA==.Nattymoo:BAAALgAECgYJCQABLgAFFAYJDAAfAI4dAA==.',
Ne='Necrô:BAAALgADCgIJAgAAAA==.Nephi:BAAALgAECgEJAgAAAA==.',
Ni='Nightraven:BAAALgADCgkJFgAAAA==.Nightreaper:BAAALgADCgkJGwAAAA==.Nimbus:BAACLgAFFH8jAAIDAAUJKCP9EwCAAQADAAUJKCP9EwCAAQAuAAQKf3AAAgMACQkPJkIBAHADAAMACQkPJkIBAHADAAEuAAUUCQkvAAoAUxoA.Nimike:BAAALgAECgcJDQAAAA==.',
No='Nodens:BAAALgAECgQJBwAAAA==.Noobslapper:BAAALgAECgEJAgAAAA==.Norilin:BAAALgAECgMJBQAAAA==.Normul:BAAALgAECgcJAwABLgAFFAUJFwAdAPoXAA==.Noshoba:BAAALgAECgEJAgAAAA==.',
Nr='Nrvous:BAAALgADCgkJCQAAAA==.',
Nu='Nugzuul:BAAALgAECgEJAQAAAA==.Nuid:BAAALgAECgkJBgAAAA==.Numbers:BAABLgAECn8aAAMaAAcJTRAmMQABAQAIAAcJUguQjgADAQAaAAYJ9hAmMQABAQAAAA==.',
Ny='Nyterage:BAAALgAECgIJAgAAAA==.Nytesage:BAACLgAFFH8lAAIhAAgJLB5QAABqAgAhAAgJLB5QAABqAgAuAAQKfyoAAiEACQkJJj8AAH4DACEACQkJJj8AAH4DAAAA.',
['Nä']='Näners:BAAALgAFFAEJAQABLgAFFAcJEgANAIERAA==.',
['Nì']='Nìghtcat:BAAALgAECgUJDAAAAA==.',
Ok='Okama:BAAALgAFFAEJAgAAAA==.',
Oo='Ookle:BAABLgAECn8nAAMMAAkJVwoyFgBnAQAMAAkJVwoyFgBnAQAPAAcJ0wolbADwAAAAAA==.',
Or='Orchard:BAABLgAFFH8NAAIeAAUJihWrFQARAQAeAAUJihWrFQARAQAAAA==.Oresh:BAABLgAECn8sAAIUAAcJhBOuAQAJAQAUAAcJhBOuAQAJAQAAAA==.Orgrom:BAAALgAECgkJDwAAAA==.Oryz:BAAALgADCgkJCAAAAA==.',
Os='Osajak:BAAALgADCgIJAgAAAA==.',
Oz='Ozo:BAABLgAECn8eAAMiAAgJrg4TkQAZAQAiAAcJeAsTkQAZAQAmAAMJNBH7KgBvAAAAAA==.',
Pa='Painavolian:BAABLgAECn9LAAIBAAkJzCCLFQDYAgABAAkJzCCLFQDYAgAAAA==.Palifur:BAAALgAECgkJDwAAAA==.Pandamonium:BAAALgAECgcJEgAAAA==.Panes:BAAALgAECgcJCwAAAA==.Paopu:BAAALgADCgYJBgABLgAECgkJIAAiAPYfAA==.',
Pe='Peeches:BAAALgAECgYJDAAAAA==.Pelonis:BAAALgADCgcJAgAAAA==.Pelor:BAAALgAECgcJEQAAAA==.',
Ph='Pheayre:BAAALgADCgkJDAABLgAECgcJDAAQAAAAAA==.',
Pi='Pisspadpanda:BAACLgAFFH8PAAMiAAQJIxcuSgAzAQAiAAQJIxcuSgAzAQAmAAEJhBpNJgBJAAAuAAQKfykAAiIACQltIk0TAOICACIACQltIk0TAOICAAAA.',
Pl='Plsbnice:BAAALgAECgYJCAABLgAECgkJIgAIAJ0dAA==.',
Po='Poggies:BAACLgAFFH8hAAMhAAgJQiQ8AAChAgAhAAgJQiQ8AAChAgAkAAEJ3gjGBQBRAAAuAAQKfyEAAyEACAk9JjkAAIIDACEACAk9JjkAAIIDACQAAQkOIP8WAGIAAAAA.Pollypocket:BAAALgAECgEJAQAAAA==.Ponmonk:BAAALgAECgEJAQABLgAECgYJFQAGALcfAA==.Pontacos:BAABLgAECn8VAAIGAAYJtx/AIADTAQAGAAYJtx/AIADTAQAAAA==.Porkinator:BAAALgADCgYJCAAAAA==.Powdur:BAAALgADCgEJAQABLgAFFAMJDQASAMIZAA==.Pozh:BAABLgAECn8UAAIiAAYJlA0HkQA3AQAiAAYJlA0HkQA3AQAAAA==.',
Pr='Praynes:BAACLgAFFH8YAAIFAAUJ/hPsAAA2AQAFAAUJ/hPsAAA2AQAuAAQKfzEAAgUACQnoGMkSAEoCAAUACQnoGMkSAEoCAAAA.Precedence:BAAALgADCgEJAQABLgAECgEJAQAQAAAAAA==.Prestocreamÿ:BAAALgADCgEJAQAAAA==.Priestresh:BAAALgADCgYJBgABLgAECgcJLAAUAIQTAA==.',
Pu='Pummel:BAAALgAECgYJCwAAAA==.Pupperputh:BAAALgADCgkJEgABLgAECgkJIgAIAJ0dAA==.Puppet:BAAALgAECgEJAwAAAA==.',
['Pä']='Päroxysm:BAAALgAECgEJAgABLgAECgYJBgAQAAAAAA==.',
Qu='Quígon:BAAALgAECgIJAwABLgAECgcJBQAQAAAAAA==.',
Ra='Rach:BAAALgAECgEJAQAAAA==.Randyrando:BAAALgADCgIJBAAAAA==.Ranoe:BAABLgAECn8jAAIIAAcJCRbdbwBDAQAIAAcJCRbdbwBDAQABLgAFFAUJEgAcALIZAA==.Rastrin:BAAALgADCgcJDgAAAA==.Ravyniel:BAAALgAECgIJAgAAAA==.Razji:BAABLgAECn9DAAQSAAkJ1yQrAgAwAwASAAkJPiQrAgAwAwATAAcJsSENGABtAgAHAAIJiSbQgQDjAAAAAA==.',
Re='Redrrum:BAAALgAECgcJCgAAAA==.Rekd:BAAALgADCgEJAQAAAA==.Reladiia:BAAALgAECgEJAQAAAA==.Renfro:BAAALgADCgcJBwAAAA==.Restokhan:BAAALgAFFAEJAQAAAA==.Revoked:BAAALgADCgEJAQABLgAECgYJDwAQAAAAAA==.Reznick:BAABLgAECn8ZAAIUAAgJ6g7uOgBaAQAUAAgJ6g7uOgBaAQAAAA==.',
Ri='Riete:BAAALgADCgkJCQAAAA==.',
Ro='Rocknwolf:BAAALgAECgEJAQAAAA==.Rokd:BAAALgAECgcJDQAAAA==.Rokham:BAAALgADCgEJAQAAAA==.Rosalee:BAAALgAECgQJAQAAAA==.Roscoelock:BAAALgAECgUJBQAAAA==.Rovërgalarga:BAAALgADCgMJAwAAAA==.',
Ru='Rudeboy:BAAALgAECgEJAQAAAA==.Ruibaron:BAABLgAECn8cAAIBAAYJaReDlQBNAQABAAYJaReDlQBNAQAAAA==.',
Ry='Ryhunter:BAAALgADCggJDgAAAA==.',
['Rà']='Ràidèn:BAABLgAECn8yAAIWAAkJKSARGgCqAgAWAAkJKSARGgCqAgAAAA==.',
['Rá']='Ráyne:BAAALgAECgYJEQAAAA==.',
Sa='Sadeel:BAABLgAECn8sAAMmAAkJVho8DQCIAQAiAAkJdBKmRQD6AQAmAAcJKB08DQCIAQAAAA==.Sadewolf:BAACLgAFFH8HAAIIAAMJchDtZADEAAAIAAMJchDtZADEAAAuAAQKfykAAggACQnrGysdAGUCAAgACQnrGysdAGUCAAAA.Sadpanduh:BAABLgAECn8WAAIgAAgJagXcPwD7AAAgAAgJagXcPwD7AAAAAA==.Saltednuts:BAAALgAECgEJAQAAAA==.Samentoni:BAACLgAFFH8KAAIEAAMJTRbHLgC+AAAEAAMJTRbHLgC+AAAuAAQKfy8AAgQACQkYHAYNAMACAAQACQkYHAYNAMACAAAA.Samgal:BAABLgAECn8bAAIjAAkJtBg8BQAgAgAjAAkJtBg8BQAgAgAAAA==.Sardothien:BAAALgAECgEJAgAAAA==.Satyra:BAAALgAECgcJEgABLgAECgkJKAAFAFgkAA==.Saurphang:BAACLgAFFH8bAAMWAAUJdBUeGABFAQAWAAQJdBUeGABFAQAJAAEJAAAAagAAAAAuAAQKfywAAhYACQlOIhIVAP0CABYACQlOIhIVAP0CAAAA.Saye:BAAALgADCgIJAgAAAA==.',
Sc='Scarletpanda:BAAALgADCgQJBgAAAA==.Scourgereap:BAAALgAECgcJDQAAAA==.',
Se='Selinna:BAAALgAECggJEgAAAA==.Semperfi:BAAALgADCgYJBgAAAA==.Senpaichill:BAAALgAECgYJDQAAAA==.Severis:BAAALgADCgIJAgAAAA==.',
Sg='Sgtmajdaly:BAAALgADCgMJAwAAAA==.',
Sh='Shadiepope:BAAALgAECgIJAwAAAA==.Shadora:BAABLgAECn8gAAIGAAkJLBMDHgDVAQAGAAkJLBMDHgDVAQAAAA==.Shadowsaja:BAAALgAECgcJBwAAAA==.Shadowwizard:BAAALgAECgMJAwAAAA==.Shadybrat:BAAALgAECgYJDQABLgAFFAMJCgAHAHsIAA==.Shaggylol:BAAALgADCgcJDQAAAA==.Shaladin:BAAALgAECgcJBgAAAA==.Shamlazy:BAAALgADCgkJHQAAAA==.Shennka:BAAALgAECgEJAgAAAA==.Shidan:BAAALgAECggJEAABLgAECgkJMgAWACkgAA==.Shiroku:BAAALgAECgkJBgAAAA==.Shockchalk:BAACLgAFFH8cAAIbAAYJDSabAQD/AQAbAAYJDSabAQD/AQAuAAQKfzYAAxsACQnhJfUAAEYDABsACQnhJfUAAEYDAAMAAglhESeDAGoAAAAA.Shocknorris:BAAALgAECgQJBwABLgAECgYJDwAQAAAAAA==.Shrooclaw:BAACLgAFFH8SAAMPAAQJXhHZMADtAAAPAAQJXhHZMADtAAAMAAEJvAlHIAA5AAAuAAQKfx4AAw8ACQnYE7wzAM4BAA8ACQnYE7wzAM4BAAwAAgkGHVZDAFUAAAAA.',
Si='Sibbiah:BAAALgAECggJCAAAAA==.Silanre:BAABLgAECn8+AAIBAAgJoBl2AQCvAQABAAgJoBl2AQCvAQAAAA==.',
Sk='Skaðï:BAACLgAFFH8YAAMHAAUJiSFwJAB0AQAHAAQJ2CBwJAB0AQATAAUJaCC2EABXAQAuAAQKfzQABBMACQkOIxMEAHsCABMACAnQIxMEAHsCABIABAnvGUouADQBAAcAAwnpHgDXAJ4AAAAA.',
Sl='Slizzard:BAAALgADCgQJBAABLgAFFAUJFwAdAPoXAA==.',
Sm='Smolshrapnel:BAABLgAECn8WAAISAAcJ0AQkNQAKAQASAAcJ0AQkNQAKAQAAAA==.',
Sn='Sneakchalk:BAAALgADCgcJCwABLgAFFAYJHAAbAA0mAA==.',
So='Solaraze:BAABLgAECn8vAAQXAAkJXh1yMgA3AgAXAAgJCR5yMgA3AgAEAAIJdBBGcgBuAAAOAAEJLQYeVwAiAAAAAA==.Solinarie:BAAALgADCggJCgAAAA==.Sorefang:BAAALgADCgEJAQAAAA==.Sorrowfang:BAAALgAECgEJAQAAAA==.Soulfkr:BAAALgAECgQJBAAAAA==.Sovnightwar:BAAALgAECggJEwABLgAFFAYJDAAIAPcdAA==.Soza:BAAALgADCgEJAQAAAA==.',
Sp='Spacespecial:BAAALgAECggJEwAAAA==.Sparklebunny:BAAALgADCgEJAQAAAA==.Spicycurryy:BAABLgAECn8+AAQHAAkJuB8/GgBqAgAHAAgJeCA/GgBqAgASAAgJvxeSFQD3AQATAAIJJAzGeABeAAABLgAECgkJPgAHALgfAA==.Spicyycurryy:BAAALgAECgUJCwABLgAECgkJPgAHALgfAA==.Spiker:BAAALgAECgEJAQAAAA==.',
St='Staggertrip:BAAALgADCgQJBAABLgAFFAUJBgAIAJkWAA==.Strahm:BAABLgAECn8oAAIRAAgJyBO2GACKAQARAAgJyBO2GACKAQAAAA==.Strehm:BAAALgAECgQJBwABLgAECggJKAARAMgTAA==.Strohmjr:BAAALgAECgMJAwABLgAECggJKAARAMgTAA==.Strohmy:BAAALgADCgEJAQABLgAECggJKAARAMgTAA==.Stryhm:BAAALgAECgUJEQABLgAECggJKAARAMgTAA==.',
Su='Sunju:BAAALgADCgMJAwAAAA==.Surai:BAAALgAFFAEJAQABLgAFFAcJFQAcAJcWAA==.',
Sy='Sylvexa:BAAALgAECgEJBAAAAA==.Syns:BAAALgAECgcJEwAAAA==.Syssare:BAABLgAECn8yAAIaAAkJdSR9AgA+AwAaAAkJdSR9AgA+AwAAAA==.',
['Sé']='Sétt:BAAALgAECgUJCAAAAA==.',
Ta='Tabbie:BAAALgADCgYJCQAAAA==.Tacpally:BAAALgAECgYJBwAAAA==.Talasam:BAAALgAECgkJEwAAAA==.Talien:BAAALgADCgEJAQAAAA==.Tandsonnara:BAAALgAECgkJDAAAAA==.Tastetickle:BAACLgAFFH8UAAIBAAUJ2RFoBQBDAQABAAUJ2RFoBQBDAQAuAAQKfzUAAgEACQkvH7EfAKACAAEACQkvH7EfAKACAAAA.Tavv:BAAALgAFFAIJAwABLgAFFAcJEgANAIERAA==.Tazdrin:BAACLgAFFH8YAAInAAUJiQ2OAADOAAAnAAUJiQ2OAADOAAAuAAQKfzIAAicACQkmF3UFAA8CACcACQkmF3UFAA8CAAAA.',
Te='Tears:BAAALgAECgcJDAABLgAFFAUJEgAcALIZAA==.Telidrus:BAACLgAFFH8aAAMBAAcJvRnHJQDiAQABAAcJvRnHJQDiAQAkAAEJ7wJ0CAAhAAAuAAQKfzEABAEACAl/JGkxAK0CAAEABwlBJGkxAK0CACQABAm3JPAEAJoBACEAAglcE2oTADkAAAAA.Temok:BAAALgADCggJCAAAAA==.Teyrlis:BAAALgAECgUJCAAAAA==.',
Th='Thavryn:BAAALgADCgYJBgAAAA==.Thaz:BAAALgAECgQJBwAAAA==.Thepoacher:BAAALgAECgUJBwAAAA==.Thias:BAABLgAECn8nAAIBAAkJOBX/PAAnAgABAAkJOBX/PAAnAgAAAA==.Thukmonk:BAAALgAECgYJCwAAAA==.Thukwarlock:BAABLgAECn8hAAIiAAcJ7xgoSQDuAQAiAAcJ7xgoSQDuAQAAAA==.Thunderbug:BAAALgADCgEJAQAAAA==.Thunderhorse:BAAALgADCgUJBQAAAA==.',
To='Todd:BAAALgAECgEJAQAAAA==.Tokain:BAAALgAECgYJDAAAAA==.Topaze:BAAALgAECgUJCAAAAA==.Torironheart:BAAALgADCgcJBwAAAA==.',
Tr='Trance:BAAALgAECgEJAQABLgAECgEJAQAQAAAAAA==.Treehuggera:BAAALgAECgYJCgAAAA==.Tribunal:BAAALgAECgEJAQAAAA==.Trilila:BAAALgADCgYJBgAAAA==.Tripx:BAABLgAECn8cAAMXAAkJbiNICAApAwAXAAkJbiNICAApAwAOAAEJ2A8CRgAoAAABLgAFFAUJBgAIAJkWAA==.Tronko:BAABLgAECn8lAAMCAAkJHByPFgCWAgACAAkJHByPFgCWAgADAAEJ8BNCpAA0AAAAAA==.Trumpinator:BAAALgADCgYJDAAAAA==.',
Ts='Tsireya:BAAALgAECgUJCwABLgAECgQJDgAQAAAAAA==.',
Tu='Tullip:BAAALgAECgEJAgAAAA==.Turntsnaco:BAACLgAFFH8JAAIcAAIJZBpRMAClAAAcAAIJZBpRMAClAAAuAAQKf0YAAxwACAnnIZgLAGoCABwACAnnIZgLAGoCACgAAQmYFkUkAEUAAAAA.Tusk:BAAALgAECgcJEQAAAA==.',
Tw='Twigger:BAAALgAECgEJAwAAAA==.Twiztedsoul:BAAALgAECggJCwAAAA==.Twophorb:BAAALgADCgMJAwAAAA==.',
Ua='Uake:BAAALgADCgYJBgAAAA==.',
Ud='Udgar:BAAALgAECgkJEQAAAA==.',
Un='Unafhaen:BAAALgADCgEJAQAAAA==.Unaverse:BAAALgAECgEJAQAAAA==.',
Us='Usmc:BAAALgADCgYJBgAAAA==.Usmccpl:BAABLgAECn8YAAIaAAkJ+gt4IQBtAQAaAAkJ+gt4IQBtAQAAAA==.Usmcsemperfi:BAAALgAECgQJBAAAAA==.',
Va='Valengarde:BAACLgAFFH8JAAIXAAMJAA7ycwDMAAAXAAMJAA7ycwDMAAAuAAQKfxsAAhcACQmYFi9NAN8BABcACQmYFi9NAN8BAAAA.Vanette:BAAALgAECgIJAgAAAA==.Vangoon:BAAALgAECgQJBgABLgAFFAEJAQAQAAAAAA==.Vannix:BAACLgAFFH8UAAIGAAUJuSFBAQBYAQAGAAUJuSFBAQBYAQAuAAQKfzcAAgYACQmSI7AEAA0DAAYACQmSI7AEAA0DAAAA.Vanz:BAAALgADCgIJAgABLgAFFAEJAQAQAAAAAA==.Varnos:BAAALgAECgEJAwAAAA==.',
Ve='Velranis:BAAALgADCgMJAwABLgAECgkJFAAgABoWAA==.Velthas:BAAALgADCggJIQAAAA==.',
Vi='Viollet:BAAALgAECgQJBwAAAA==.Virmethir:BAABLgAECn8lAAMZAAgJvhPiBwC4AQAZAAgJaxPiBwC4AQAKAAYJVgZCYwCxAAAAAA==.Viruz:BAAALgAECgYJCwAAAA==.',
Vo='Volley:BAAALgADCgEJAQAAAA==.Voltaren:BAAALgAECgcJDAABLgAECgkJLwAXAF4dAA==.',
Vy='Vylaran:BAAALgADCgYJBgAAAA==.Vyndrolan:BAAALgAFFAEJAQAAAA==.Vyroth:BAAALgADCgUJBQAAAA==.',
Wa='Walksonwater:BAAALgADCgEJAQABLgAECgkJJQAEAG0eAA==.Waq:BAAALgAFFAIJAgAAAA==.',
We='Wellamor:BAAALgADCgIJAgAAAA==.',
Wh='Whilton:BAAALgAECgcJBwAAAA==.Whtmg:BAAALgADCgkJEAABLgAECgcJDAAQAAAAAA==.',
Wi='Winterbreeze:BAAALgADCgYJBgAAAA==.Wiwi:BAACLgAFFH8XAAMdAAUJ+hfCDAA0AQAdAAQJvBbCDAA0AQAWAAMJYRGsGQBTAAAuAAQKfzIAAxYACQnGIVkVAMcCABYACQnGIVkVAMcCAB0AAwm8GyUgAMwAAAAA.',
Wo='Worgruka:BAAALgAECgEJAQAAAA==.',
Xa='Xares:BAACLgAFFH8LAAIBAAQJvhWmVQAxAQABAAQJvhWmVQAxAQAuAAQKfzUAAgEACQmsG+4lAIQCAAEACQmsG+4lAIQCAAEuAAUUBQkSABwAshkA.Xash:BAAALgAECgEJAQAAAA==.',
Xe='Xerath:BAAALgADCgcJBwAAAA==.',
Xh='Xhades:BAAALgAECgYJDgABLgAFFAUJEgAcALIZAA==.',
Ya='Yalda:BAABLgAECn8dAAIbAAYJbh0tEACvAQAbAAYJbh0tEACvAQAAAA==.',
Yf='Yfra:BAAALgAECggJEQAAAA==.',
Yo='Yochangsvegn:BAAALgAECggJEAAAAA==.Yoseph:BAABLgAECn8XAAIMAAgJjQ82GQBFAQAMAAgJjQ82GQBFAQAAAA==.',
Yu='Yungblood:BAAALgAECgUJEgAAAA==.Yurimancer:BAABLgAECn80AAIGAAkJ1Ri7EQBIAgAGAAkJ1Ri7EQBIAgAAAA==.',
Za='Zaen:BAAALgADCgMJAwAAAA==.Zake:BAAALgAECgMJBAAAAA==.Zalileina:BAAALgADCgMJAwAAAA==.Zallith:BAAALgADCgMJAwABLgAECgYJDgAQAAAAAA==.Zappythile:BAABLgAECn8sAAICAAkJfxvJIwA4AgACAAkJfxvJIwA4AgAAAA==.Zarkamental:BAAALgADCgYJCwABLgAFFAMJBQAIAEcCAA==.Zarthos:BAAALgAECgEJAQABLgAECgEJAwAQAAAAAA==.',
Ze='Zect:BAABLgAECn8YAAQmAAYJLB7UDgBvAQAmAAYJOBvUDgBvAQAiAAUJZRleqADxAAAjAAEJFBWsbwA3AAAAAA==.Zekk:BAAALgADCgcJBwAAAA==.Zelinor:BAAALgADCgcJBwAAAA==.',
Zi='Ziêg:BAAALgADCgcJBwAAAA==.',
Zo='Zoz:BAABLgAECn8fAAIBAAcJtRBYlABQAQABAAcJtRBYlABQAQAAAA==.',
Zu='Zulfrik:BAABLgAECn83AAIBAAkJNhlEOgAwAgABAAkJNhlEOgAwAgAAAA==.Zullard:BAAALgAECgEJAQAAAA==.',
Zy='Zyzy:BAACLgAFFH8LAAIDAAcJLhppCQAYAgADAAcJLhppCQAYAgAuAAQKfyAAAgMACQkZIsMEABQDAAMACQkZIsMEABQDAAAA.',
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
