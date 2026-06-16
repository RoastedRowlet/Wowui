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

local lookup = {'Mage-Frost','Shaman-Restoration','Shaman-Elemental','Paladin-Holy','Priest-Holy','Priest-Shadow','Hunter-BeastMastery','DemonHunter-Devourer','DeathKnight-Blood','Evoker-Augmentation','Evoker-Preservation','Paladin-Protection','Druid-Restoration','Unknown-Unknown','Druid-Guardian','Hunter-Survival','Hunter-Marksmanship','Warrior-Fury','Warrior-Protection','Druid-Balance','Druid-Feral','DeathKnight-Unholy','Paladin-Retribution','Warrior-Arms','Evoker-Devastation','DemonHunter-Havoc','Shaman-Enhancement','Rogue-Subtlety','DeathKnight-Frost','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','Mage-Fire','Warlock-Demonology','Warlock-Destruction','Mage-Arcane','DemonHunter-Vengeance','Warlock-Affliction','Rogue-Outlaw','Rogue-Assassination',}
local provider = {region='US',realm='Eonar',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abbazaad:BAAALgAECgQJBQAAAA==.Abreen:BAAALgADCgcJCQAAAA==.Abysseus:BAAALgADCgcJCAAAAA==.',
Ac='Acepriest:BAAALgAECgQJCAAAAA==.Achievement:BAAALgAECgQJBAAAAA==.',
Ad='Adeathfox:BAAALgADCgEJAQAAAA==.Adhoc:BAAALgADCgUJBQAAAA==.Admired:BAABLgAECn8cAAIBAAcJoB4OVwAzAgABAAcJoB4OVwAzAgAAAA==.Adyr:BAACLgAFFH8KAAMCAAQJUhINQADeAAACAAQJUhINQADeAAADAAMJIwcCOgChAAAuAAQKfyQAAwIACAmUH2wTAHoCAAIACAmUH2wTAHoCAAMABQnlF0pNABMBAAAA.',
Ai='Aidra:BAABLgAECn8pAAIEAAgJ6hl9FQBeAgAEAAgJ6hl9FQBeAgAAAA==.',
Al='Alaira:BAAALgAECgMJAwABLgAECggJHwABAF8IAA==.Alamora:BAABLgAECn8cAAMFAAcJzwc+QADoAAAFAAcJzwc+QADoAAAGAAYJDwQcWgCpAAAAAA==.Alastair:BAAALgAECgcJCAAAAA==.Alathena:BAAALgAECgcJDAAAAA==.Albinoz:BAAALgADCgIJAgAAAA==.Albrect:BAAALgADCgYJFgAAAA==.Aldrich:BAAALgADCgEJAQAAAA==.Alexandrya:BAACLgAFFH8KAAIHAAMJewjKZgDOAAAHAAMJewjKZgDOAAAuAAQKfy0AAgcACAlDGOZGAMgBAAcACAlDGOZGAMgBAAAA.Alicemalkin:BAABLgAECn8XAAIIAAkJHxTyPQD8AQAIAAkJHxTyPQD8AQAAAA==.Alonai:BAAALgAECgYJBgAAAA==.Alphred:BAAALgAECgEJAgAAAA==.Alunira:BAAALgADCgIJAgAAAA==.Alysse:BAAALgADCgUJBwAAAA==.',
Am='Amarysia:BAAALgAECgYJDQAAAA==.Ameriixs:BAAALgAECgIJAgAAAA==.Amháin:BAAALgAECggJDQAAAA==.Amsip:BAAALgAECgEJAQABLgAECgkJJAAJABYPAA==.Amsroeb:BAABLgAECn8kAAIJAAkJFg8OHwBaAQAJAAkJFg8OHwBaAQAAAA==.',
An='Anelavenger:BAACLgAFFH8HAAIKAAMJpw6IRQCuAAAKAAMJpw6IRQCuAAAuAAQKfy0AAwoACQneHMwMAKkCAAoACQneHMwMAKkCAAsAAwlcAS1EAE0AAAAA.Angerwina:BAAALgADCgUJCQAAAA==.Anggar:BAAALgADCgIJAgAAAA==.',
Ao='Aomori:BAAALgAECgcJBwAAAA==.',
Aq='Aquini:BAAALgAFFAIJAgAAAA==.Aqüilés:BAAALgAECgEJAgAAAA==.',
Ar='Arathor:BAABLgAECn8nAAIMAAkJbRwzBgCCAgAMAAkJbRwzBgCCAgAAAA==.Arctorius:BAAALgADCgEJAQAAAA==.Arent:BAABLgAECn9EAAINAAkJ+xVEIwAtAgANAAkJ+xVEIwAtAgAAAA==.Arfy:BAAALgADCgMJAgABLgAECggJEQAOAAAAAA==.Argil:BAAALgAECgEJAQABLgAECggJKAAPAMgTAA==.Argøn:BAABLgAECn88AAQHAAkJMxsaHQByAgAHAAkJMxsaHQByAgAQAAUJ2AiPQwCxAAARAAEJkAYUkgAoAAAAAA==.Arkanna:BAAALgAECgEJAQAAAA==.Arrise:BAAALgAECgUJBwAAAA==.Artemislives:BAAALgAECgcJEQAAAA==.Arthuaca:BAAALgAECgYJDQAAAA==.',
As='Asharia:BAABLgAECn8QAAIIAAcJjRHaZgBVAQAIAAcJjRHaZgBVAQAAAA==.Ashog:BAAALgADCgYJCwAAAA==.Assateague:BAABLgAECn8eAAISAAcJewV5WQDoAAASAAcJewV5WQDoAAAAAA==.Astelossa:BAAALgAECgEJAQAAAA==.Astralie:BAAALgADCggJFAAAAA==.Asuya:BAAALgADCgYJCQAAAA==.',
At='Athereos:BAAALgADCgYJBQAAAA==.Athylan:BAAALgADCgEJAQABLgAFFAYJFwAEAIgcAA==.Atrosity:BAABLgAECn8tAAITAAkJpiIQBQDKAgATAAkJpiIQBQDKAgAAAA==.',
Au='Aurorabane:BAAALgADCgYJEAAAAA==.',
Av='Avelleah:BAAALgAECgEJBAAAAA==.',
Az='Azulyne:BAAALgADCgIJAgAAAA==.Azuretorrent:BAAALgADCgQJBAAAAA==.',
Ba='Bananapistol:BAAALgAECgUJBQAAAA==.Barracksbuny:BAAALgAECgUJBgABLgAECgUJBgAOAAAAAA==.Barrathfrogy:BAAALgADCgYJFQAAAA==.Barthal:BAAALgAECgEJAQAAAA==.',
Be='Bebheishel:BAAALgADCgYJCwAAAA==.Bellatrix:BAAALgAECgMJAwABLgAECgQJDgAOAAAAAA==.Bertelo:BAAALgADCgUJBQAAAA==.',
Bi='Bigstinky:BAAALgAECgYJDAABLgAECgkJPAAHADMbAA==.Bilywitchdoc:BAAALgAFFAIJAwABLgAECgkJQwAQANckAA==.Bisao:BAAALgAECgIJAgAAAA==.Biscuít:BAABLgAECn8pAAMUAAkJiA5xLABwAQAUAAkJiA5xLABwAQAVAAEJqAfbXAAiAAAAAA==.',
Bl='Blasuoff:BAAALgAECgQJBAAAAA==.Bloodrains:BAAALgAECgEJAwAAAA==.Bloodyfate:BAAALgADCgUJBQAAAA==.',
Bo='Bonesentinel:BAABLgAECn8YAAIHAAcJNSKpIwBRAgAHAAcJNSKpIwBRAgABLgAFFAUJDQAWAN0ZAA==.Bonës:BAAALgADCgEJAQAAAA==.Bora:BAAALgAECgQJDgAAAA==.Borzoi:BAABLgAFFH8SAAIXAAQJhSMfHQCMAQAXAAQJhSMfHQCMAQAAAA==.Bourgùîgnon:BAAALgADCgcJCgAAAA==.',
Br='Bragasch:BAAALgADCgkJGQAAAA==.Brakhon:BAAALgAECgEJAgAAAA==.Bruisebrews:BAAALgADCgEJAQAAAA==.',
Bu='Bullplop:BAAALgADCgUJBQAAAA==.Burekbazino:BAAALgADCgcJCQAAAA==.Burningsleet:BAAALgAECgYJBgABLgAFFAgJEAAWAI8WAA==.',
['Bò']='Bò:BAACLgAFFH8OAAIUAAUJ0wegKgDdAAAUAAUJ0wegKgDdAAAuAAQKfzEAAhQACQmpF1QUAC4CABQACQmpF1QUAC4CAAAA.',
Ca='Caduceus:BAAALgADCgcJGAAAAA==.Caesus:BAABLgAECn8cAAIGAAcJFxenJACjAQAGAAcJFxenJACjAQAAAA==.Cagedancer:BAABLgAECn8iAAQVAAgJQwtQHAAjAQAVAAgJHQpQHAAjAQAUAAYJyAaNUADmAAANAAEJFAMg+gAYAAAAAA==.Callio:BAACLgAFFH8HAAIHAAQJ7QSCUwD4AAAHAAQJ7QSCUwD4AAAuAAQKfy8AAgcACQmbEbFFAMwBAAcACQmbEbFFAMwBAAAA.Cantor:BAAALgAECgEJAQAAAA==.Caradd:BAAALgAECgcJCwAAAA==.Catchclause:BAAALgADCgkJFAAAAA==.Cathillex:BAABLgAECn8aAAMSAAkJTxeBGQAgAgASAAkJTxeBGQAgAgAYAAEJ1AJ4iQAVAAAAAA==.Cattlesdaddy:BAAALgADCgEJAQABLgAECggJKAAPAMgTAA==.Cavagos:BAACLgAFFH8KAAIZAAQJKBDvBAAZAQAZAAQJKBDvBAAZAQAuAAQKfzYAAhkACQlWIPQBALcCABkACQlWIPQBALcCAAAA.Caycay:BAACLgAFFH8ZAAIaAAYJISJsBADJAQAaAAYJISJsBADJAQAuAAQKf1EAAhoACQnAJlwAAJADABoACQnAJlwAAJADAAAA.Cayleq:BAAALgAECgUJBAABLgAFFAYJGQAaACEiAA==.',
Ce='Celebrexi:BAAALgAECgcJBgAAAA==.Celene:BAAALgADCgYJBwAAAA==.Celtic:BAAALgADCgEJAQAAAA==.Cerrulli:BAAALgAECgYJDwAAAA==.',
Ch='Chaosknight:BAABLgAECn8XAAMDAAgJSRLILgCCAQADAAgJSRLILgCCAQACAAUJUAp/mwCUAAAAAA==.Chaostrip:BAACLgAFFH8GAAIIAAUJmRagPwAiAQAIAAUJmRagPwAiAQAuAAQKfzIAAggACQknI30IAAgDAAgACQknI30IAAgDAAAA.Chariso:BAAALgAECgEJAQAAAA==.Cheddar:BAAALgAFFAEJAQAAAA==.Chillbros:BAACLgAFFH8RAAIbAAYJ1B3PAwCPAQAbAAYJ1B3PAwCPAQAuAAQKfywAAxsACQkTJFQCAPcCABsACQkTJFQCAPcCAAMABAmqH+45AGcBAAAA.Chilldh:BAAALgAECgUJBQABLgAFFAYJEQAbANQdAA==.Chillmage:BAAALgADCgcJCgABLgAFFAYJEQAbANQdAA==.Chindi:BAABLgAECn8xAAMSAAkJ7xeSIQDjAQASAAkJKxaSIQDjAQATAAcJUBKlGwBWAQAAAA==.Chindrakh:BAAALgAECggJEAABLgAECgkJMQASAO8XAA==.Choiminasue:BAAALgAECgEJAgAAAA==.Chunga:BAABLgAECn8UAAIDAAYJoAPZXADQAAADAAYJoAPZXADQAAAAAA==.Chungers:BAAALgAECgQJBgAAAA==.Churd:BAACLgAFFH8PAAIGAAMJhhVVIgDaAAAGAAMJhhVVIgDaAAAuAAQKfykAAgYACQnkGL0RAEgCAAYACQnkGL0RAEgCAAAA.Churdicus:BAAALgADCgkJEQAAAA==.Chypnotic:BAAALgAECgcJCwAAAA==.Chypper:BAAALgADCgEJAQAAAA==.Chypster:BAABLgAECn8jAAIDAAgJMg5OPABAAQADAAgJMg5OPABAAQAAAA==.',
Ci='Ciceroe:BAABLgAFFH8PAAIcAAQJNhIHGgBAAQAcAAQJNhIHGgBAAQAAAA==.Citadel:BAAALgADCgIJAwAAAA==.',
Cl='Cleft:BAABLgAECn8UAAIXAAYJAxAAvgAIAQAXAAYJAxAAvgAIAQAAAA==.Clevelandk:BAAALgAECgUJCQAAAA==.Clowwnshoes:BAAALgAECgEJAgAAAA==.',
Co='Coalystra:BAACLgAFFH8TAAIIAAUJKxwHMgBUAQAIAAUJKxwHMgBUAQAuAAQKfywAAggACQnsGsUgAE0CAAgACQnsGsUgAE0CAAAA.Cocopuffs:BAACLgAFFH8HAAIUAAIJsBG2FACfAAAUAAIJsBG2FACfAAAuAAQKfzUAAhQACQleICMJAAMDABQACQleICMJAAMDAAAA.Colostrom:BAACLgAFFH8QAAIMAAUJDByPBABBAQAMAAUJDByPBABBAQAuAAQKfy8AAgwACQnVH98GAHECAAwACQnVH98GAHECAAAA.Complicatedz:BAAALgAECgUJBQAAAA==.Comul:BAAALgADCgcJBwAAAA==.Coramage:BAABLgAECn8aAAIBAAkJjwaHhABrAQABAAkJjwaHhABrAQAAAA==.Corentis:BAAALgADCgYJBgAAAA==.Corliss:BAABLgAECn8fAAITAAkJLhakDwDqAQATAAkJLhakDwDqAQAAAA==.Cornholeo:BAAALgADCgkJCQAAAA==.',
Cp='Cplusmc:BAAALgAECgQJBwAAAA==.',
Cr='Creightizle:BAABLgAECn8eAAIHAAgJfRS/OQDHAQAHAAgJfRS/OQDHAQAAAA==.',
['Cá']='Cátix:BAAALgADCgMJAwAAAA==.',
Da='Daicmerollin:BAAALgAECgYJCwAAAA==.Danhaüsen:BAAALgAECgIJAwAAAA==.Darkbeast:BAABLgAFFH8JAAIHAAQJOQ8TQgAjAQAHAAQJOQ8TQgAjAQAAAA==.Darkdeeds:BAAALgADCggJEQAAAA==.Darkpallo:BAABLgAECn8YAAIXAAcJPxPWbwCdAQAXAAcJPxPWbwCdAQABLgAFFAQJCQAHADkPAA==.Darthtav:BAABLgAFFH8IAAIdAAYJGw8XCABiAQAdAAYJGw8XCABiAQABLgAFFAcJEgAUAIERAA==.Daten:BAABLgAECn9LAAIXAAkJzRX9awCUAQAXAAkJzRX9awCUAQAAAA==.Dazshauran:BAAALgADCggJCAAAAA==.Daîma:BAAALgADCggJCAAAAA==.',
Db='Dbltap:BAAALgADCgEJAQAAAA==.',
De='Deathbycow:BAABLgAECn8rAAIPAAgJlhzCCwAiAgAPAAgJlhzCCwAiAgAAAA==.Debra:BAAALgADCgUJBQAAAA==.Decayed:BAABLgAECn8fAAIJAAkJvBnKCwBOAgAJAAkJvBnKCwBOAgABLgAECgUJBgAOAAAAAA==.Deipally:BAAALgAECgYJBQAAAA==.Demonchalk:BAACLgAFFH8HAAIIAAUJohMXQQAdAQAIAAUJohMXQQAdAQAuAAQKfxwAAggABglqI5o1AOwBAAgABglqI5o1AOwBAAEuAAUUBgkcABsADSYA.Desdeynna:BAAALgADCgEJAQAAAA==.Deseral:BAAALgAECgIJAgAAAA==.Dewbie:BAAALgAECgEJAQAAAA==.',
Di='Diagonalli:BAABLgAECn8fAAIZAAkJNA/iBwC1AQAZAAkJNA/iBwC1AQAAAA==.Dimmadome:BAAALgADCgEJAQAAAA==.Dinojam:BAAALgADCgMJAQAAAA==.Divirian:BAAALgAECgYJDwAAAA==.',
Dj='Djdaemon:BAAALgAECgYJCwAAAA==.Djdrakshadow:BAAALgAECgQJBwAAAA==.Djpaly:BAAALgAECgYJBwAAAA==.Djpriest:BAAALgAECgQJCAAAAA==.Djshadow:BAAALgAECgYJDwAAAA==.Djshadowar:BAAALgAECgUJCQAAAA==.Djshadowhunt:BAAALgAECgYJCgAAAA==.Djshadowlock:BAAALgAECgYJDAAAAA==.Djshadowrog:BAAALgAECgYJEAAAAA==.Djshamy:BAAALgAECgMJAwAAAA==.Djshaolin:BAAALgAECgUJDwAAAA==.Djzhadow:BAAALgAECgYJDwAAAA==.Djzhadruid:BAAALgAECgQJCQAAAA==.',
Dk='Dkshadow:BAAALgAECgQJBAAAAA==.',
Dm='Dmitrì:BAAALgAECgEJAQAAAA==.',
Do='Dogno:BAAALgAECgEJAgAAAA==.Dontdieplez:BAAALgAECgkJDAAAAA==.Doofuss:BAAALgADCgIJAgAAAA==.',
Dp='Dpm:BAAALgAECgEJAgAAAA==.',
Dr='Dragbuttakis:BAAALgAECgUJCAAAAA==.Drakhadir:BAAALgAECgQJBwAAAA==.Drakmon:BAAALgAECgIJBQAAAA==.Draktând:BAABLgAECn8vAAIcAAgJVhl7FAD7AQAcAAgJVhl7FAD7AQAAAA==.Drippysilk:BAAALgAECgQJCAABLgAECgkJJAAXAE4fAA==.Drius:BAAALgADCgMJAwAAAA==.Drunkenpanda:BAACLgAFFH8FAAMeAAMJxANZLgCFAAAeAAMJxANZLgCFAAAfAAEJqglUZQArAAAuAAQKfyUAAx8ACQn0FKYiAAMCAB8ACQn0FKYiAAMCAB4ABwnWCA5NAMwAAAAA.Drunknoodle:BAAALgAECgQJCAAAAA==.',
Du='Duhpriest:BAAALgAECgEJAQAAAA==.Duinrane:BAAALgAECgEJAQAAAA==.Duon:BAABLgAECn8WAAQeAAkJ3hTdIACkAQAeAAgJexbdIACkAQAfAAIJzwmCYQBJAAAgAAIJkgXOhABAAAAAAA==.',
Dw='Dwagonfur:BAAALgAECgcJBgAAAA==.',
Ec='Echö:BAACLgAFFH8TAAIaAAUJqRNkDwAlAQAaAAUJqRNkDwAlAQAuAAQKfyEAAhoACAl5GdcRAAsCABoACAl5GdcRAAsCAAAA.',
Ei='Eiarinos:BAAALgADCgEJAQAAAA==.Eirø:BAAALgADCgkJCQABLgAFFAUJEwAHAIkhAA==.',
El='Elaine:BAAALgAFFAMJAwAAAA==.Elberon:BAAALgAECgUJEgAAAA==.Ellspeth:BAAALgAECgkJCQAAAA==.Elmerhomero:BAAALgADCgUJBQAAAA==.Elronnd:BAAALgAECgMJAwAAAA==.Elsebeth:BAAALgADCgcJCAAAAA==.',
Em='Emilie:BAAALgADCgYJBgAAAA==.',
En='Enoch:BAABLgAECn8bAAIXAAYJkBZXfwB7AQAXAAYJkBZXfwB7AQAAAA==.',
Er='Eriam:BAAALgAECgMJAwABLgAECgkJJAAPAE4ZAA==.Errane:BAACLgAFFH8ZAAINAAYJ5SF3CABnAgANAAYJ5SF3CABnAgAuAAQKfywAAw0ACAnJJosEAEYDAA0ACAnJJosEAEYDABQAAQnHFVJ4AEQAAAAA.Eruiluvatar:BAAALgAECgYJCAAAAA==.',
Et='Etalia:BAAALgAECgEJAgAAAA==.Etcetera:BAAALgAECgMJBAAAAA==.',
Ev='Eveliel:BAAALgAECgEJAQAAAA==.',
Ex='Exlibris:BAAALgADCgcJDAAAAA==.',
Fa='Fallenangell:BAAALgADCgUJBQAAAA==.Fandiirn:BAAALgADCgYJBgAAAA==.Fastjack:BAABLgAECn8nAAMFAAgJUxP3LgBRAQAFAAYJlxX3LgBRAQAGAAgJWwcCPAAfAQAAAA==.',
Fe='Felseeker:BAAALgADCgkJCQAAAA==.',
Fi='Fiora:BAAALgADCgYJCwAAAA==.Firbirl:BAAALgAECgIJAgAAAA==.Fistoffury:BAABLgAECn8ZAAMgAAcJqBOQNwAcAQAgAAcJqBOQNwAcAQAeAAQJOAkEWgCoAAAAAA==.Fitco:BAAALgADCgYJCwABLgAECgYJDwAOAAAAAA==.Fiènd:BAAALgADCgYJBgAAAA==.',
Fl='Flametar:BAAALgAECgEJAQAAAA==.Floodlust:BAAALgADCgEJAQAAAA==.Floppydisk:BAAALgAECgUJDgAAAA==.',
Fo='Fortiss:BAACLgAFFH8KAAICAAMJ/hbMQgDVAAACAAMJ/hbMQgDVAAAuAAQKfysAAwIACQnWG+UNAOMCAAIACQnWG+UNAOMCAAMABgk/EIVRAO0AAAAA.',
Fr='Freelo:BAAALgAECgQJCQAAAA==.Frito:BAAALgAECggJCQAAAA==.Frost:BAAALgAFFAIJAgABLgAFFAgJJAAQACwWAA==.Frostmon:BAABLgAECn8cAAIWAAkJLxcgLQBJAgAWAAkJLxcgLQBJAgAAAA==.Frshnvrfrzn:BAAALgAECggJDwAAAA==.Frøzenblight:BAAALgAECgEJAQAAAA==.',
Fu='Fulmo:BAAALgADCgUJBQABLgAFFAQJCAAWAJsEAA==.Furbee:BAAALgAECggJEQAAAA==.Furn:BAAALgAECgkJAQAAAA==.',
['Fá']='Fáde:BAAALgADCgQJBQABLgAECgcJDAAOAAAAAA==.',
Ga='Gabris:BAAALgADCgYJBgAAAA==.Galeandra:BAABLgAECn8gAAIGAAkJZQeIMwBJAQAGAAkJZQeIMwBJAQAAAA==.Gallo:BAAALgADCggJDQAAAA==.Garim:BAAALgADCgMJBAABLgAECggJJwAFAFMTAA==.',
Ge='Geraltofrvia:BAAALgAECgkJDgAAAA==.',
Gg='Gg:BAAALgAFFAIJBAABLgAFFAgJIAAhAEIkAA==.',
Gi='Giantgoose:BAAALgAECgEJAgAAAA==.Gingani:BAAALgADCgcJDAAAAA==.',
Gn='Gnar:BAABLgAECn8rAAIWAAcJ5hPZbwCCAQAWAAcJ5hPZbwCCAQAAAA==.',
Go='Gowtherdead:BAAALgADCgQJBAAAAA==.Gowtherpunch:BAACLgAFFH8TAAIgAAUJOgfdLwDlAAAgAAUJOgfdLwDlAAAuAAQKfzEAAiAACQm5FcgWAPEBACAACQm5FcgWAPEBAAAA.',
Gr='Gregzug:BAAALgAECgMJAwAAAA==.Grendel:BAAALgAECgUJBAABLgAFFAQJCAAWAJsEAA==.Greyjoy:BAAALgADCgYJBQAAAA==.Grimfury:BAAALgAFFAIJBAAAAA==.Grimsy:BAAALgADCgYJBwAAAA==.Grodd:BAAALgADCgUJBQAAAA==.Groqqu:BAAALgAECgQJBAAAAA==.Grumble:BAAALgAECgYJCAAAAA==.Gruxxiron:BAAALgAECgYJDQABLgAECgkJOwAWAIIfAA==.',
Gu='Gulnn:BAABLgAECn8zAAMiAAkJJh1aFgCcAgAiAAkJJh1aFgCcAgAjAAIJVhT8VABvAAAAAA==.Gumby:BAAALgADCgYJBgAAAA==.',
Ha='Haelena:BAABLgAECn8nAAMEAAgJPhDwLQCjAQAEAAgJPhDwLQCjAQAMAAEJYwM3WAAcAAAAAA==.Halys:BAAALgADCgUJBQAAAA==.Hamil:BAAALgADCgEJAQAAAA==.Harmoss:BAAALgAECgcJBwABLgAFFAQJBgAiAOEJAA==.Hawk:BAAALgADCgYJBgAAAA==.',
He='Heartsfang:BAAALgADCgUJCAAAAA==.Helfire:BAAALgADCgYJBgABLgAECgcJDAAOAAAAAA==.Hellscreems:BAAALgADCgMJAwAAAA==.Heriotza:BAACLgAFFH8IAAIWAAQJmwQCiwDwAAAWAAQJmwQCiwDwAAAuAAQKfxwAAhYACQmsDst6AGsBABYACQmsDst6AGsBAAAA.Herminard:BAAALgADCgIJAgABLgAECgcJDAAOAAAAAA==.',
Hx='Hxvenlyx:BAAALgADCgUJDgAAAA==.',
Ia='Iamfubar:BAAALgADCgMJBAAAAA==.',
Id='Idotyoudie:BAAALgADCgIJAgABLgADCgkJCQAOAAAAAA==.',
Ig='Igris:BAAALgAECgcJCgAAAA==.',
Ii='Iimit:BAACLgAFFH8QAAIcAAQJshnPFQBXAQAcAAQJshnPFQBXAQAuAAQKfyQAAhwACQmOG4oMAFoCABwACQmOG4oMAFoCAAAA.',
Il='Illidead:BAACLgAFFH8YAAIBAAYJ6BwTNgCTAQABAAYJ6BwTNgCTAQAuAAQKfyMAAwEACQnfI5k0AEQCAAEACQlWIJk0AEQCACQAAQlSJeEPAG4AAAAA.Iluni:BAAALgADCgMJAwAAAA==.',
Im='Implied:BAAALgADCgUJBQAAAA==.',
In='Indexes:BAABLgAECn8cAAMUAAcJPQ6BOgAkAQAUAAcJbg2BOgAkAQAPAAUJGgZXVABfAAAAAA==.Insrik:BAAALgAECgcJEAAAAA==.Insurance:BAAALgAECggJCAABLgAFFAMJCgAHAHsIAA==.',
Io='Iompróirbáis:BAABLgAECn8hAAIWAAkJ7QdUewBqAQAWAAkJ7QdUewBqAQAAAA==.',
Ir='Irdeadohnoz:BAABLgAECn8aAAIBAAcJTAzPswAYAQABAAcJTAzPswAYAQAAAA==.',
Is='Ist:BAAALgAECgQJBAAAAA==.',
It='Itchigo:BAABLgAECn8UAAIHAAgJ1A3vYgB7AQAHAAgJ1A3vYgB7AQAAAA==.',
Iv='Ivern:BAAALgAECgIJAgAAAA==.Ivgorod:BAABLgAECn8kAAMZAAkJ1gi5CwBVAQAZAAkJnAi5CwBVAQAKAAgJBAaWSgD+AAAAAA==.',
Ja='Jabbadahut:BAAALgAECgcJBQAAAA==.Jambi:BAAALgAECgYJDgAAAA==.Jardani:BAAALgAECgEJAQAAAA==.Jarhead:BAAALgADCgcJBwAAAA==.Jastrae:BAAALgAECgcJDgAAAA==.Jaziani:BAAALgADCgcJBwABLgAECgQJBwAOAAAAAA==.Jazilyne:BAAALgAECgQJBwAAAA==.',
Je='Jealous:BAAALgADCgUJBQABLgAECgkJIgAIAJ0dAA==.Jenka:BAAALgAECgUJCgAAAA==.',
Ji='Jibbs:BAAALgADCgkJCQAAAA==.',
Jo='Joleya:BAAALgADCgEJAQAAAA==.',
Ju='Junta:BAAALgADCgcJJQAAAA==.Justine:BAAALgADCgUJBQAAAA==.Justtrolling:BAAALgAECgYJDgAAAA==.',
['Jä']='Jäkel:BAAALgADCgUJBQAAAA==.',
Ka='Kalike:BAAALgADCgcJBwAAAA==.Kambative:BAABLgAECn8XAAMNAAcJqxIPQgCZAQANAAcJqxIPQgCZAQAUAAMJGBZBUQDEAAABLgAFFAUJDgAZAGcQAA==.Kambustable:BAAALgAECgQJAwABLgAFFAUJDgAZAGcQAA==.Kammunion:BAAALgAECgYJEAABLgAFFAUJDgAZAGcQAA==.Kampelis:BAAALgADCgcJBwABLgAECgcJGgABAEwMAA==.Kamphiyer:BAACLgAFFH8OAAQZAAUJZxCpCQCLAAAKAAMJ6xDtQQC6AAALAAMJKQqvIQCPAAAZAAMJ0gypCQCLAAAuAAQKfzoABAsACQnqGB8KAD4CAAsACQnqGB8KAD4CAAoACAmIHU0UADgCABkABAmjDMExAIgAAAAA.Kamsumerage:BAAALgADCgkJEgABLgAFFAUJDgAZAGcQAA==.Kandosii:BAAALgADCgUJBQAAAA==.Kantheal:BAABLgAECn8lAAIEAAkJbR40CQD2AgAEAAkJbR40CQD2AgAAAA==.Kaulana:BAAALgADCgcJDAAAAA==.',
Ke='Keirmania:BAAALgAECgEJAQAAAA==.Kekkan:BAAALgADCgcJCgAAAA==.Kellendere:BAAALgAECgYJCwAAAA==.',
Ki='Kiagas:BAAALgAECgcJBwABLgAFFAQJEgANAF4RAA==.Kiieedk:BAAALgAECgEJAQAAAA==.Kimgoeun:BAAALgADCgYJBgAAAA==.Kio:BAAALgAECgYJCAAAAA==.',
Kl='Klompus:BAAALgADCgQJBAAAAA==.',
Kn='Knùsê:BAAALgADCgUJBgABLgAFFAUJEwAHAIkhAA==.',
Ko='Komorai:BAAALgADCgYJBgAAAA==.',
Kr='Kravex:BAABLgAECn8kAAIPAAkJThl/CgA5AgAPAAkJThl/CgA5AgAAAA==.Krixxa:BAABLgAECn8oAAIFAAkJWCRZAwBZAwAFAAkJWCRZAwBZAwAAAA==.',
Ku='Kuula:BAAALgAECgEJAQAAAA==.',
Ky='Kylana:BAAALgADCgQJBAABLgAECgkJHgANABUMAA==.',
['Kä']='Kären:BAAALgAECgUJEgAAAA==.',
['Ké']='Kélly:BAAALgAECggJCAAAAA==.',
La='Laochnaofa:BAAALgAECgcJDgAAAA==.Larayvia:BAACLgAFFH8MAAIHAAUJZwKoagDDAAAHAAUJZwKoagDDAAAuAAQKfx0AAgcACAkrDkc7AMEBAAcACAkrDkc7AMEBAAAA.Laurance:BAAALgADCgYJBgAAAA==.',
Le='Leakygasket:BAAALgAECgYJBwAAAA==.Leesala:BAACLgAFFH8MAAICAAUJKR6WFAC1AQACAAUJKR6WFAC1AQAuAAQKfzAAAwIACQmpF4EfAE8CAAIACQmpF4EfAE8CABsAAQn+BH1CACcAAAAA.Lelora:BAAALgAECgEJAQAAAA==.Lerazer:BAAALgAECgYJCgAAAA==.',
Lg='Lgidk:BAAALgADCgMJAwABLgAECgkJIgAIAJ0dAA==.',
Li='Lic:BAAALgAFFAEJAQAAAA==.Liea:BAAALgAECgMJBAAAAA==.Lilbash:BAAALgAECgEJAwAAAA==.Liliatrix:BAAALgAECgQJBgAAAA==.Lillabet:BAABLgAECn8YAAIBAAcJnwx3ngA6AQABAAcJnwx3ngA6AQAAAA==.Lilmatty:BAAALgAECgkJDQABLgAFFAUJCwAfAAYdAA==.Lilsneaky:BAAALgADCggJCAAAAA==.Limpydk:BAAALgADCgUJBQABLgAECgkJJAAXAE4fAA==.Limpylarva:BAAALgADCgMJAwABLgAECgkJJAAXAE4fAA==.Limpypal:BAABLgAECn8kAAMXAAkJTh/eEADdAgAXAAkJTh/eEADdAgAMAAIJZATNRwBEAAAAAA==.Litter:BAAALgAECgUJBQAAAA==.',
Lo='Lockém:BAAALgADCgIJAgAAAA==.Logathil:BAAALgAECgYJEAAAAA==.Loremipsum:BAAALgADCgYJCQAAAA==.',
Lu='Luchulainn:BAAALgADCgYJBgAAAA==.Lucifero:BAAALgAECggJCgAAAA==.Lucifurwild:BAAALgADCgQJBQAAAA==.Lunaaris:BAABLgAECn8rAAINAAkJBR/QDwDSAgANAAkJBR/QDwDSAgAAAA==.Lunastre:BAAALgADCgEJAQAAAA==.',
['Lí']='Límpy:BAABLgAECn8aAAIZAAYJ/CJ/CgA0AgAZAAYJ/CJ/CgA0AgABLgAECgkJJAAXAE4fAA==.Línk:BAAALgAECgYJCgAAAA==.',
['Lî']='Lîkwuid:BAAALgAECggJDwAAAA==.',
Ma='Macallan:BAAALgAECgIJBAAAAA==.Macsheesh:BAAALgADCgEJAQABLgAECggJHQASAAEOAA==.Maddrox:BAAALgAECgYJBwAAAA==.Magicmarv:BAAALgADCgIJAQAAAA==.Magnagoth:BAAALgADCgkJDwAAAA==.Magnakilro:BAABLgAECn8fAAIHAAkJRxdpOgDxAQAHAAkJRxdpOgDxAQAAAA==.Mahnaz:BAAALgADCgEJAQABLgADCgcJCgAOAAAAAA==.Mahuta:BAAALgAECgEJAQAAAA==.Malacove:BAAALgADCgIJAgABLgAECggJFwAKALQVAA==.Malanath:BAABLgAECn8XAAIKAAgJtBXAKACdAQAKAAgJtBXAKACdAQAAAA==.Malditto:BAAALgADCgYJBgAAAA==.Maleficus:BAAALgADCgkJFgABLgAECgYJEgAOAAAAAA==.Malothas:BAAALgADCgQJBAAAAA==.Mareki:BAAALgADCgYJBwAAAA==.Markdfordeth:BAAALgAECgEJAQAAAA==.Mattingly:BAAALgAECgQJBQAAAA==.Mattyfu:BAACLgAFFH8LAAMfAAUJBh0JGACqAQAfAAUJBh0JGACqAQAeAAEJIBlZOwBKAAAuAAQKfxcAAx4ACQl7GCQdAPEBAB4ACAmWFyQdAPEBAB8ABQmhHuouALoBAAAA.Mavíel:BAAALgAECgYJDQAAAA==.Maxrogue:BAAALgAECgYJCwABLgAECggJKAAPAMgTAA==.Mazikeen:BAAALgAECgUJBgAAAA==.',
Mc='Mcscoots:BAAALgADCgcJEgABLgAFFAQJEAAcALIZAA==.',
Me='Meatsupreme:BAACLgAFFH8KAAIXAAMJyQz1cQDJAAAXAAMJyQz1cQDJAAAuAAQKfykAAhcACQm4EYZcALYBABcACQm4EYZcALYBAAAA.Meepin:BAACLgAFFH8XAAIEAAYJiBzJCgD9AQAEAAYJiBzJCgD9AQAuAAQKfzcAAwQACQkLJAQFABwDAAQACQkLJAQFABwDABcAAwk/Cq4pAYIAAAAA.Meepmorp:BAAALgAECgUJBQABLgAFFAQJEAAcALIZAA==.Meifeng:BAAALgADCgEJAQAAAA==.Melithara:BAAALgAECgQJBAAAAA==.Mephala:BAAALgADCgYJBgAAAA==.Merdoc:BAAALgAECgMJAwAAAA==.Mesophistole:BAAALgADCggJCwABLgAECgcJHgAjAKMFAA==.Mesopunchy:BAAALgAECgEJAQABLgAECgcJHgAjAKMFAA==.Mesopyro:BAABLgAECn8eAAIjAAcJowV/HgCyAAAjAAcJowV/HgCyAAAAAA==.',
Mi='Mileenä:BAABLgAECn8VAAMJAAkJDxTpFADFAQAJAAkJUBPpFADFAQAWAAYJ0wrlwwD2AAAAAA==.Minimim:BAAALgADCgMJAwAAAA==.Mistyra:BAABLgAECn8WAAIfAAkJ+B0FCQAHAwAfAAkJ+B0FCQAHAwABLgAECgkJKAAFAFgkAA==.Mià:BAAALgADCgEJAQAAAA==.',
Mo='Mod:BAABLgAECn8UAAIPAAcJghWJHgBTAQAPAAcJghWJHgBTAQAAAA==.Mograiné:BAAALgAECgQJCQAAAA==.Mojodaemon:BAAALgAECgEJAQAAAA==.Mojoy:BAAALgAECgQJBQAAAA==.Monkaw:BAAALgAECgIJAgAAAA==.Monkchalk:BAAALgAECgQJBQABLgAFFAYJHAAbAA0mAA==.Moondevil:BAAALgAECgEJAQAAAA==.Morta:BAEALgAFFAMJAwAAAA==.Mortkavaliro:BAABLgAECn8ZAAMWAAgJKgf0ngArAQAWAAgJXwb0ngArAQAJAAcJ2AYfNgC7AAAAAA==.',
Ms='Mslockness:BAAALgADCgYJEwAAAA==.',
Mu='Mugzy:BAAALgAECgkJBwAAAA==.Multipass:BAABLgAECn8eAAINAAgJqiE2DgDkAgANAAgJqiE2DgDkAgAAAA==.Multitool:BAAALgADCgEJAQAAAA==.Murder:BAAALgAECgQJCAABLgAFFAYJDAAIAPcdAA==.',
['Mö']='Mörph:BAAALgAECgIJAgAAAA==.',
Na='Nadris:BAAALgADCgcJBwAAAA==.Nanérs:BAAALgAECgcJEQABLgAFFAcJEgAUAIERAA==.Narrodus:BAABLgAECn8kAAIlAAkJPSUTAQA0AwAlAAkJPSUTAQA0AwAAAA==.Nasht:BAABLgAECn8VAAIBAAYJUBbFrAAjAQABAAYJUBbFrAAjAQAAAA==.Nashty:BAAALgADCgYJBgABLgAECgYJFQABAFAWAA==.Nashxi:BAAALgADCgkJEAABLgAECgYJFQABAFAWAA==.Nasu:BAAALgAECgcJAQAAAA==.Nattymoo:BAAALgAECgYJCQABLgAFFAUJCwAfAAYdAA==.',
Ne='Necrô:BAAALgADCgIJAgAAAA==.Nephi:BAAALgAECgEJAgAAAA==.',
Ni='Nightraven:BAAALgADCgkJFgAAAA==.Nightreaper:BAAALgADCgkJGwAAAA==.Nimbus:BAACLgAFFH8jAAIDAAUJKCOZEgCDAQADAAUJKCOZEgCDAQAuAAQKf3AAAgMACQkPJigBAHEDAAMACQkPJigBAHEDAAEuAAUUCAkoAAoA8hsA.Nimike:BAAALgAECgcJDQAAAA==.',
No='Nodens:BAAALgAECgQJBwAAAA==.Noobslapper:BAAALgAECgEJAgAAAA==.Norilin:BAAALgADCgUJBQAAAA==.Normul:BAAALgAECgcJAwABLgAFFAUJEgAdAPoXAA==.Noshoba:BAAALgAECgEJAgAAAA==.',
Nr='Nrvous:BAAALgADCgkJCQAAAA==.',
Nu='Nugzuul:BAAALgAECgEJAQAAAA==.Nuid:BAAALgAECgkJBgAAAA==.Numbers:BAABLgAECn8aAAMaAAcJTRAhMAACAQAIAAcJUguOjAADAQAaAAYJ9hAhMAACAQAAAA==.',
Ny='Nyterage:BAAALgAECgIJAgAAAA==.Nytesage:BAACLgAFFH8kAAIhAAcJIyNFAABsAgAhAAcJIyNFAABsAgAuAAQKfygAAiEACAkMJj8AAH4DACEACAkMJj8AAH4DAAAA.',
['Nä']='Näners:BAAALgAFFAEJAQABLgAFFAcJEgAUAIERAA==.',
['Nì']='Nìghtcat:BAAALgAECgQJBwAAAA==.',
Ok='Okama:BAAALgAECgIJAgAAAA==.',
Oo='Ookle:BAABLgAECn8nAAMVAAkJVwrLFQBmAQAVAAkJVwrLFQBmAQANAAcJ0wruagDxAAAAAA==.',
Or='Orchard:BAABLgAFFH8NAAIeAAUJihXjFAARAQAeAAUJihXjFAARAQAAAA==.Oresh:BAABLgAECn8nAAISAAcJfRKROQBfAQASAAcJfRKROQBfAQAAAA==.Orgrom:BAAALgAECgkJDwAAAA==.Oryz:BAAALgADCgkJCAAAAA==.',
Os='Osajak:BAAALgADCgIJAgAAAA==.',
Oz='Ozo:BAABLgAECn8dAAMiAAcJ/Q2qjgAdAQAiAAcJeAuqjgAdAQAmAAIJZBDoKQBvAAAAAA==.',
Pa='Painavolian:BAABLgAECn9LAAIBAAkJzCAAFQDZAgABAAkJzCAAFQDZAgAAAA==.Palifur:BAAALgAECgkJDwAAAA==.Pandamonium:BAAALgAECgcJEgAAAA==.Panes:BAAALgAECgcJCwAAAA==.Paopu:BAAALgADCgYJBgABLgAECgkJIAAiAPYfAA==.',
Pe='Peeches:BAAALgAECgYJCwAAAA==.Pelonis:BAAALgADCgcJAgAAAA==.Pelor:BAAALgAECgcJEQAAAA==.',
Ph='Pheayre:BAAALgADCgkJDAABLgAECgcJDAAOAAAAAA==.',
Pi='Pisspadpanda:BAACLgAFFH8PAAMiAAQJIxc5RwA1AQAiAAQJIxc5RwA1AQAmAAEJhBpIJQBJAAAuAAQKfykAAiIACQltIk0TAOICACIACQltIk0TAOICAAAA.',
Pl='Plsbnice:BAAALgAECgYJCAABLgAECgkJIgAIAJ0dAA==.',
Po='Poggies:BAACLgAFFH8gAAMhAAgJQiQ4AACjAgAhAAgJQiQ4AACjAgAkAAEJ3ghjBQBRAAAuAAQKfyEAAyEACAk9JjkAAIIDACEACAk9JjkAAIIDACQAAQkOIP8WAGIAAAAA.Pollypocket:BAAALgAECgEJAQAAAA==.Ponmonk:BAAALgAECgEJAQABLgAECgYJFQAGALcfAA==.Pontacos:BAABLgAECn8VAAIGAAYJtx/AIADTAQAGAAYJtx/AIADTAQAAAA==.Porkinator:BAAALgADCgYJCAAAAA==.Powdur:BAAALgADCgEJAQABLgAFFAMJDQAQAMIZAA==.Pozh:BAABLgAECn8UAAIiAAYJlA0HkQA3AQAiAAYJlA0HkQA3AQAAAA==.',
Pr='Praynes:BAACLgAFFH8TAAIFAAUJ0AsZFQATAQAFAAUJ0AsZFQATAQAuAAQKfzEAAgUACQnoGMkSAEoCAAUACQnoGMkSAEoCAAAA.Precedence:BAAALgADCgEJAQABLgAECgEJAQAOAAAAAA==.Prestocreamÿ:BAAALgADCgEJAQAAAA==.Priestresh:BAAALgADCgYJBgABLgAECgcJJwASAH0SAA==.',
Pu='Pummel:BAAALgAECgYJCwAAAA==.Pupperputh:BAAALgADCgkJEgABLgAECgkJIgAIAJ0dAA==.Puppet:BAAALgAECgEJAwAAAA==.',
['Pä']='Päroxysm:BAAALgAECgEJAgABLgAECgYJBgAOAAAAAA==.',
Qu='Quígon:BAAALgAECgIJAwABLgAECgcJBQAOAAAAAA==.',
Ra='Rach:BAAALgAECgEJAQAAAA==.Randyrando:BAAALgADCgIJBAAAAA==.Ranoe:BAABLgAECn8jAAIIAAcJCRZmbgBDAQAIAAcJCRZmbgBDAQABLgAFFAQJEAAcALIZAA==.Rastrin:BAAALgADCgcJDgAAAA==.Ravyniel:BAAALgAECgIJAgAAAA==.Razji:BAABLgAECn9DAAQQAAkJ1yQMAgAyAwAQAAkJPiQMAgAyAwARAAcJsSENGABtAgAHAAIJiSbQgQDjAAAAAA==.',
Re='Redrrum:BAAALgAECgcJCgAAAA==.Rekd:BAAALgADCgEJAQAAAA==.Reladiia:BAAALgAECgEJAQAAAA==.Renfro:BAAALgADCgcJBwAAAA==.Restokhan:BAAALgAFFAEJAQAAAA==.Revoked:BAAALgADCgEJAQABLgAECgYJDwAOAAAAAA==.Reznick:BAABLgAECn8ZAAISAAgJ6g4QOQBhAQASAAgJ6g4QOQBhAQAAAA==.',
Ri='Riete:BAAALgADCgkJCQAAAA==.',
Ro='Rocknwolf:BAAALgAECgEJAQAAAA==.Rokd:BAAALgAECgcJDQAAAA==.Rokham:BAAALgADCgEJAQAAAA==.Rosalee:BAAALgAECgQJAQAAAA==.Roscoelock:BAAALgAECgUJBQAAAA==.Rovërgalarga:BAAALgADCgMJAwAAAA==.',
Ru='Rudeboy:BAAALgAECgEJAQAAAA==.Ruibaron:BAABLgAECn8bAAIBAAYJaRetkwBNAQABAAYJaRetkwBNAQAAAA==.',
Ry='Ryhunter:BAAALgADCggJDgAAAA==.',
['Rà']='Ràidèn:BAABLgAECn8yAAIWAAkJKSCUGQCrAgAWAAkJKSCUGQCrAgAAAA==.',
['Rá']='Ráyne:BAAALgAECgYJEQAAAA==.',
Sa='Sadeel:BAABLgAECn8sAAMmAAkJVhrTDACKAQAiAAkJdBKmRQD6AQAmAAcJKB3TDACKAQAAAA==.Sadewolf:BAACLgAFFH8HAAIIAAMJchAtYgDEAAAIAAMJchAtYgDEAAAuAAQKfykAAggACQnrG7QcAGUCAAgACQnrG7QcAGUCAAAA.Sadpanduh:BAABLgAECn8UAAIgAAgJagU8PwD7AAAgAAgJagU8PwD7AAAAAA==.Saltednuts:BAAALgAECgEJAQAAAA==.Samentoni:BAACLgAFFH8KAAIEAAMJTRanLQC+AAAEAAMJTRanLQC+AAAuAAQKfy8AAgQACQkYHMwMAMECAAQACQkYHMwMAMECAAAA.Samgal:BAABLgAECn8bAAIjAAkJtBgOBQAhAgAjAAkJtBgOBQAhAgAAAA==.Sardothien:BAAALgAECgEJAgAAAA==.Satyra:BAAALgAECgcJEgABLgAECgkJKAAFAFgkAA==.Saurphang:BAACLgAFFH8bAAMWAAUJdBUeGABFAQAWAAQJdBUeGABFAQAJAAEJAACJZgAAAAAuAAQKfywAAhYACQlOIhIVAP0CABYACQlOIhIVAP0CAAAA.Saye:BAAALgADCgIJAgAAAA==.',
Sc='Scarletpanda:BAAALgADCgQJBgAAAA==.Scourgereap:BAAALgAECgcJDAAAAA==.',
Se='Selinna:BAAALgAECggJEgAAAA==.Semperfi:BAAALgADCgYJBgAAAA==.Senpaichill:BAAALgAECgYJDQAAAA==.Severis:BAAALgADCgIJAgAAAA==.',
Sg='Sgtmajdaly:BAAALgADCgMJAwAAAA==.',
Sh='Shadiepope:BAAALgAECgIJAwAAAA==.Shadora:BAABLgAECn8gAAIGAAkJLBPMHADdAQAGAAkJLBPMHADdAQAAAA==.Shadowsaja:BAAALgAECgcJBwAAAA==.Shadowwizard:BAAALgAECgMJAwAAAA==.Shadybrat:BAAALgAECgYJDQABLgAFFAMJCgAHAHsIAA==.Shaggylol:BAAALgADCgcJDQAAAA==.Shaladin:BAAALgAECgcJBgAAAA==.Shamlazy:BAAALgADCgkJHQAAAA==.Shennka:BAAALgAECgEJAgAAAA==.Shidan:BAAALgAECggJEAABLgAECgkJMgAWACkgAA==.Shiroku:BAAALgAECgkJBgAAAA==.Shockchalk:BAACLgAFFH8cAAIbAAYJDSZyAQACAgAbAAYJDSZyAQACAgAuAAQKfzYAAxsACQnhJewAAEcDABsACQnhJewAAEcDAAMAAglhEe6AAGoAAAAA.Shocknorris:BAAALgAECgQJBwABLgAECgYJDwAOAAAAAA==.Shrooclaw:BAACLgAFFH8SAAMNAAQJXhFuLwDtAAANAAQJXhFuLwDtAAAVAAEJvAnJHgA5AAAuAAQKfx4AAw0ACQnYE1gzAM4BAA0ACQnYE1gzAM4BABUAAgkGHXpBAFQAAAAA.',
Si='Sibbiah:BAAALgAECggJCAAAAA==.Silanre:BAABLgAECn83AAIBAAgJrBcuTgDuAQABAAgJrBcuTgDuAQAAAA==.',
Sk='Skaðï:BAACLgAFFH8TAAMHAAUJiSFJIQB3AQAHAAQJ2CBJIQB3AQARAAUJ2BsOEABcAQAuAAQKfzQABBEACQkOI/QDAHwCABEACAnQI/QDAHwCABAABAnvGSIuADYBAAcAAwnpHsLSAJ4AAAAA.',
Sl='Slizzard:BAAALgADCgQJBAABLgAFFAUJEgAdAPoXAA==.',
Sm='Smolshrapnel:BAABLgAECn8WAAIQAAcJ0ARyNAANAQAQAAcJ0ARyNAANAQAAAA==.',
Sn='Sneakchalk:BAAALgADCgcJCwABLgAFFAYJHAAbAA0mAA==.',
So='Solaraze:BAABLgAECn8vAAQXAAkJXh2CMQA4AgAXAAgJCR6CMQA4AgAEAAIJdBAXcQBuAAAMAAEJLQbFVQAiAAAAAA==.Solinarie:BAAALgADCggJCgAAAA==.Sorefang:BAAALgADCgEJAQAAAA==.Sorrowfang:BAAALgAECgEJAQAAAA==.Soulfkr:BAAALgAECgQJBAAAAA==.Sovnightwar:BAAALgAECggJDwABLgAFFAYJDAAIAPcdAA==.Soza:BAAALgADCgEJAQAAAA==.',
Sp='Spacespecial:BAAALgAECggJEwAAAA==.Sparklebunny:BAAALgADCgEJAQAAAA==.Spicycurryy:BAABLgAECn8+AAQHAAkJuB8/GgBqAgAHAAgJeCA/GgBqAgAQAAgJvxcpFQD7AQARAAIJJAzGeABeAAABLgAECgkJPgAHALgfAA==.Spicyycurryy:BAAALgAECgUJCwABLgAECgkJPgAHALgfAA==.Spiker:BAAALgAECgEJAQAAAA==.',
St='Staggertrip:BAAALgADCgQJBAABLgAFFAUJBgAIAJkWAA==.Strahm:BAABLgAECn8oAAIPAAgJyBMQGACKAQAPAAgJyBMQGACKAQAAAA==.Strehm:BAAALgAECgQJBwABLgAECggJKAAPAMgTAA==.Strohmjr:BAAALgAECgMJAwABLgAECggJKAAPAMgTAA==.Strohmy:BAAALgADCgEJAQABLgAECggJKAAPAMgTAA==.Stryhm:BAAALgAECgQJCAABLgAECggJKAAPAMgTAA==.',
Su='Sunju:BAAALgADCgMJAwAAAA==.',
Sy='Sylvexa:BAAALgAECgEJBAAAAA==.Syns:BAAALgAECgcJDQAAAA==.Syssare:BAABLgAECn8uAAIaAAkJQiSDAgA5AwAaAAkJQiSDAgA5AwAAAA==.',
['Sé']='Sétt:BAAALgAECgUJBQAAAA==.',
Ta='Tabbie:BAAALgADCgYJCQAAAA==.Tacpally:BAAALgAECgYJBwAAAA==.Talasam:BAAALgAECgkJEgAAAA==.Talien:BAAALgADCgEJAQAAAA==.Tandsonnara:BAAALgAECgkJDAAAAA==.Tastetickle:BAACLgAFFH8PAAIBAAUJbhBXXQAwAQABAAUJbhBXXQAwAQAuAAQKfzUAAgEACQkvH9keAKICAAEACQkvH9keAKICAAAA.Tavv:BAAALgAFFAIJAwABLgAFFAcJEgAUAIERAA==.Tazdrin:BAACLgAFFH8TAAInAAUJVAsnBwARAQAnAAUJVAsnBwARAQAuAAQKfzIAAicACQkmF2UFAA8CACcACQkmF2UFAA8CAAAA.',
Te='Tears:BAAALgAECgcJDAABLgAFFAQJEAAcALIZAA==.Telidrus:BAACLgAFFH8WAAIBAAcJlxkEIwDwAQABAAcJlxkEIwDwAQAuAAQKfzEABAEACAl/JGkxAK0CAAEABwlBJGkxAK0CACQABAm3JNgEAJoBACEAAglcE8ISADkAAAAA.Temok:BAAALgADCggJCAAAAA==.Teyrlis:BAAALgAECgUJCAAAAA==.',
Th='Thavryn:BAAALgADCgYJBgAAAA==.Thaz:BAAALgAECgQJBwAAAA==.Thepoacher:BAAALgAECgUJBgAAAA==.Thias:BAABLgAECn8nAAIBAAkJOBXtOwAoAgABAAkJOBXtOwAoAgAAAA==.Thukmonk:BAAALgAECgYJCwAAAA==.Thukwarlock:BAABLgAECn8hAAIiAAcJ7xgoSQDuAQAiAAcJ7xgoSQDuAQAAAA==.Thunderbug:BAAALgADCgEJAQAAAA==.Thunderhorse:BAAALgADCgUJBQAAAA==.',
To='Todd:BAAALgAECgEJAQAAAA==.Tokain:BAAALgAECgQJBwAAAA==.Topaze:BAAALgAECgUJCAAAAA==.Torironheart:BAAALgADCgcJBwAAAA==.',
Tr='Trance:BAAALgAECgEJAQABLgAECgEJAQAOAAAAAA==.Treehuggera:BAAALgAECgYJCgAAAA==.Tribunal:BAAALgAECgEJAQAAAA==.Trilila:BAAALgADCgYJBgAAAA==.Tripx:BAABLgAECn8cAAMXAAkJbiPnBwAqAwAXAAkJbiPnBwAqAwAMAAEJ2A8CRgAoAAABLgAFFAUJBgAIAJkWAA==.Tronko:BAABLgAECn8lAAMCAAkJHBwbFgCWAgACAAkJHBwbFgCWAgADAAEJ8BP4oAA0AAAAAA==.Trumpinator:BAAALgADCgYJDAAAAA==.',
Ts='Tsireya:BAAALgAECgUJCgABLgAECgQJDgAOAAAAAA==.',
Tu='Tullip:BAAALgAECgEJAQAAAA==.Turntsnaco:BAACLgAFFH8JAAIcAAIJZBruLgClAAAcAAIJZBruLgClAAAuAAQKf0UAAxwACAnnIWMLAGsCABwACAnnIWMLAGsCACgAAQmYFrgjAEUAAAAA.Tusk:BAAALgAECgcJEQAAAA==.',
Tw='Twigger:BAAALgAECgEJAwAAAA==.Twiztedsoul:BAAALgAECggJCwAAAA==.Twophorb:BAAALgADCgMJAwAAAA==.',
Ua='Uake:BAAALgADCgYJBgAAAA==.',
Ud='Udgar:BAAALgAECgkJEQAAAA==.',
Un='Unafhaen:BAAALgADCgEJAQAAAA==.Unaverse:BAAALgAECgEJAQAAAA==.',
Us='Usmc:BAAALgADCgYJBgAAAA==.Usmccpl:BAABLgAECn8XAAIaAAgJbgzZJQBFAQAaAAgJbgzZJQBFAQAAAA==.Usmcsemperfi:BAAALgAECgQJBAAAAA==.',
Va='Valengarde:BAACLgAFFH8JAAIXAAMJAA4hcADMAAAXAAMJAA4hcADMAAAuAAQKfxsAAhcACQmYFh1MAOABABcACQmYFh1MAOABAAAA.Vanette:BAAALgAECgIJAgAAAA==.Vangoon:BAAALgAECgQJBgABLgAFFAEJAQAOAAAAAA==.Vannix:BAACLgAFFH8PAAIGAAUJuSGFDQCDAQAGAAUJuSGFDQCDAQAuAAQKfzcAAgYACQmSI5cEABADAAYACQmSI5cEABADAAAA.Vanz:BAAALgADCgIJAgABLgAFFAEJAQAOAAAAAA==.Varnos:BAAALgAECgEJAwAAAA==.',
Ve='Velranis:BAAALgADCgMJAwABLgAECgkJFAAgABoWAA==.Velthas:BAAALgADCggJIQAAAA==.',
Vi='Viollet:BAAALgAECgQJBgAAAA==.Virmethir:BAABLgAECn8kAAMZAAgJvhPGBwC4AQAZAAgJaxPGBwC4AQAKAAYJVgasYQCxAAAAAA==.Viruz:BAAALgAECgYJCwAAAA==.',
Vo='Volley:BAAALgADCgEJAQAAAA==.Voltaren:BAAALgAECgcJDAABLgAECgkJLwAXAF4dAA==.',
Vy='Vylaran:BAAALgADCgYJBgAAAA==.Vyndrolan:BAAALgAFFAEJAQAAAA==.Vyroth:BAAALgADCgUJBQAAAA==.',
Wa='Walksonwater:BAAALgADCgEJAQABLgAECgkJJQAEAG0eAA==.Waq:BAAALgAECgcJDwAAAA==.',
We='Wellamor:BAAALgADCgIJAgAAAA==.',
Wh='Whilton:BAAALgAECgEJAQAAAA==.Whtmg:BAAALgADCgkJEAABLgAECgcJDAAOAAAAAA==.',
Wi='Winterbreeze:BAAALgADCgYJBgAAAA==.Wiwi:BAACLgAFFH8SAAMdAAUJ+hfhCwA1AQAdAAQJdxXhCwA1AQAWAAIJPBH2DQE+AAAuAAQKfzIAAxYACQnGIbYUAMkCABYACQnGIbYUAMkCAB0AAwm8G5EfAMwAAAAA.',
Wo='Worgruka:BAAALgAECgEJAQAAAA==.',
Xa='Xares:BAACLgAFFH8LAAIBAAQJvhWhVQA8AQABAAQJvhWhVQA8AQAuAAQKfzUAAgEACQmsG0AlAIQCAAEACQmsG0AlAIQCAAEuAAUUBAkQABwAshkA.Xash:BAAALgAECgEJAQAAAA==.',
Xe='Xerath:BAAALgADCgcJBwAAAA==.',
Xh='Xhades:BAAALgAECgYJDgABLgAFFAQJEAAcALIZAA==.',
Ya='Yalda:BAABLgAECn8cAAIbAAYJbh3YDwCwAQAbAAYJbh3YDwCwAQAAAA==.',
Yf='Yfra:BAAALgAECggJEQAAAA==.',
Yo='Yochangsvegn:BAAALgAECggJEAAAAA==.Yoseph:BAABLgAECn8XAAIVAAgJjQ/GGABEAQAVAAgJjQ/GGABEAQAAAA==.',
Yu='Yungblood:BAAALgAECgUJEgAAAA==.Yurimancer:BAABLgAECn80AAIGAAkJ1RgcEQBPAgAGAAkJ1RgcEQBPAgAAAA==.',
Za='Zaen:BAAALgADCgMJAwAAAA==.Zake:BAAALgAECgMJBAAAAA==.Zalileina:BAAALgADCgMJAwAAAA==.Zallith:BAAALgADCgMJAwABLgAECgYJDgAOAAAAAA==.Zappythile:BAABLgAECn8sAAICAAkJfxsjIwA4AgACAAkJfxsjIwA4AgAAAA==.Zarkamental:BAAALgADCgYJCwABLgAFFAMJBQAIAEcCAA==.Zarthos:BAAALgAECgEJAQABLgAECgEJAwAOAAAAAA==.',
Ze='Zect:BAABLgAECn8YAAQmAAYJLB50DgBwAQAmAAYJOBt0DgBwAQAiAAUJZRnOpwDyAAAjAAEJFBWsbwA3AAAAAA==.Zekk:BAAALgADCgcJBwAAAA==.Zelinor:BAAALgADCgcJBwAAAA==.',
Zi='Ziêg:BAAALgADCgcJBwAAAA==.',
Zo='Zoz:BAABLgAECn8fAAIBAAcJtRB4kgBQAQABAAcJtRB4kgBQAQAAAA==.',
Zu='Zulfrik:BAABLgAECn83AAIBAAkJNhk3OQAxAgABAAkJNhk3OQAxAgAAAA==.Zullard:BAAALgAECgEJAQAAAA==.',
Zy='Zyzy:BAACLgAFFH8JAAIDAAcJLhqFCAAaAgADAAcJLhqFCAAaAgAuAAQKfyAAAgMACQkZIpYEABUDAAMACQkZIpYEABUDAAAA.',
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
