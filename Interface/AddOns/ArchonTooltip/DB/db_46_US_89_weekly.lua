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

local lookup = {'Mage-Frost','Shaman-Restoration','Shaman-Elemental','Paladin-Holy','Hunter-BeastMastery','DemonHunter-Devourer','DeathKnight-Blood','Evoker-Augmentation','Evoker-Preservation','Paladin-Protection','Druid-Restoration','Unknown-Unknown','Druid-Guardian','Hunter-Survival','Hunter-Marksmanship','Warrior-Fury','Warrior-Protection','Druid-Balance','Druid-Feral','DeathKnight-Unholy','Paladin-Retribution','Priest-Shadow','Warrior-Arms','Evoker-Devastation','DemonHunter-Havoc','Shaman-Enhancement','Rogue-Subtlety','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','Priest-Holy','Mage-Fire','Warlock-Demonology','Warlock-Destruction','Mage-Arcane','DemonHunter-Vengeance','DeathKnight-Frost','Warlock-Affliction','Rogue-Outlaw','Rogue-Assassination',}
local provider = {region='US',realm='Eonar',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abbazaad:BAAALgAECgQJBQAAAA==.Abreen:BAAALgADCgcJCQAAAA==.Abysseus:BAAALgADCgcJCAAAAA==.',
Ac='Acepriest:BAAALgAECgQJCAAAAA==.Achievement:BAAALgAECgQJBAAAAA==.',
Ad='Adeathfox:BAAALgADCgEJAQAAAA==.Adhoc:BAAALgADCgUJBQAAAA==.Admired:BAABLgAECn8cAAIBAAcJoB4OVwAzAgABAAcJoB4OVwAzAgAAAA==.Adyr:BAACLgAFFH8KAAMCAAQJUhJtMwD0AAACAAQJUhJtMwD0AAADAAMJIwcOMQCqAAAuAAQKfyQAAwIACAmUH2wTAHoCAAIACAmUH2wTAHoCAAMABQnlF0pNABMBAAAA.',
Ai='Aidra:BAABLgAECn8lAAIEAAgJWxlnFABVAgAEAAgJWxlnFABVAgAAAA==.',
Al='Alaira:BAAALgAECgMJAwABLgAECgYJGQABAO8IAA==.Alamora:BAAALgAECgYJEwAAAA==.Alastair:BAAALgAECgcJCAAAAA==.Alathena:BAAALgAECgcJDAAAAA==.Albinoz:BAAALgADCgIJAgAAAA==.Albrect:BAAALgADCgYJEQAAAA==.Aldrich:BAAALgADCgEJAQAAAA==.Alexandrya:BAACLgAFFH8FAAIFAAIJ+gYHcgCKAAAFAAIJ+gYHcgCKAAAuAAQKfyoAAgUACAlDGI08ANYBAAUACAlDGI08ANYBAAAA.Alicemalkin:BAABLgAECn8XAAIGAAkJHxTyPQD8AQAGAAkJHxTyPQD8AQAAAA==.Alonai:BAAALgAECgYJBgAAAA==.Alphred:BAAALgADCgkJCgAAAA==.Alysse:BAAALgADCgUJBwAAAA==.',
Am='Amarysia:BAAALgAECgYJDQAAAA==.Ameriixs:BAAALgAECgIJAgAAAA==.Amháin:BAAALgAECggJDQAAAA==.Amsip:BAAALgAECgEJAQABLgAECgkJIwAHAKwOAA==.Amsroeb:BAABLgAECn8jAAIHAAkJrA5YHABcAQAHAAkJrA5YHABcAQAAAA==.',
An='Anelavenger:BAACLgAFFH8HAAIIAAMJpw7GOgC6AAAIAAMJpw7GOgC6AAAuAAQKfy0AAwgACQneHMwMAKkCAAgACQneHMwMAKkCAAkAAwlcAS1EAE0AAAAA.Angerwina:BAAALgADCgMJBAAAAA==.Anggar:BAAALgADCgIJAgAAAA==.',
Ao='Aomori:BAAALgAECgcJBwAAAA==.',
Aq='Aqüilés:BAAALgAECgEJAgAAAA==.',
Ar='Arathor:BAABLgAECn8nAAIKAAkJbRw3BQCJAgAKAAkJbRw3BQCJAgAAAA==.Arctorius:BAAALgADCgEJAQAAAA==.Arent:BAABLgAECn9EAAILAAkJ+xWpIAAvAgALAAkJ+xWpIAAvAgAAAA==.Arfy:BAAALgADCgMJAgABLgAECggJEQAMAAAAAA==.Argil:BAAALgAECgEJAQABLgAECggJJAANAMsQAA==.Argøn:BAABLgAECn88AAQFAAkJMxsnGAB/AgAFAAkJMxsnGAB/AgAOAAUJ2AjMPgC2AAAPAAEJkAYUkgAoAAAAAA==.Arkanna:BAAALgAECgEJAQAAAA==.Arrise:BAAALgAECgUJBgAAAA==.Artemislives:BAAALgAECgcJEQAAAA==.Arthuaca:BAAALgAECgYJDQAAAA==.',
As='Asharia:BAAALgAECgcJDwAAAA==.Ashog:BAAALgADCgYJCwAAAA==.Assateague:BAABLgAECn8VAAIQAAYJEQRXZACsAAAQAAYJEQRXZACsAAAAAA==.Astelossa:BAAALgADCgMJAwAAAA==.Astralie:BAAALgADCggJFAAAAA==.Asuya:BAAALgADCgYJCQAAAA==.',
At='Athereos:BAAALgADCgYJBQAAAA==.Athylan:BAAALgADCgEJAQABLgAFFAUJFQAEACwcAA==.Atrosity:BAABLgAECn8tAAIRAAkJpiLzAwDbAgARAAkJpiLzAwDbAgAAAA==.',
Au='Aurorabane:BAAALgADCgYJEAAAAA==.',
Av='Avelleah:BAAALgAECgEJBAAAAA==.',
Az='Azulyne:BAAALgADCgIJAgAAAA==.Azuretorrent:BAAALgADCgQJBAAAAA==.',
Ba='Bananapistol:BAAALgAECgUJBQAAAA==.Barracksbuny:BAAALgAECgUJBgABLgAECgUJBQAMAAAAAA==.Barrathfrogy:BAAALgADCgYJFQAAAA==.',
Be='Bebheishel:BAAALgADCgYJCwAAAA==.Bertelo:BAAALgADCgUJBQAAAA==.',
Bi='Bigstinky:BAAALgAECgYJDAABLgAECgkJPAAFADMbAA==.Bilywitchdoc:BAAALgAFFAIJAwABLgAECgkJQwAOANckAA==.Bisao:BAAALgAECgIJAgAAAA==.Biscuít:BAABLgAECn8pAAMSAAkJiA75JwB1AQASAAkJiA75JwB1AQATAAEJqAemTgAjAAAAAA==.',
Bl='Blasuoff:BAAALgAECgQJBAAAAA==.Bloodrains:BAAALgAECgEJAwAAAA==.Bloodyfate:BAAALgADCgUJBQAAAA==.',
Bo='Bonesentinel:BAABLgAECn8YAAIFAAcJNSIjHgBbAgAFAAcJNSIjHgBbAgABLgAFFAUJDQAUAN0ZAA==.Bonës:BAAALgADCgEJAQAAAA==.Bora:BAAALgAECgQJDgAAAA==.Borzoi:BAABLgAFFH8QAAIVAAQJZSHgGAB9AQAVAAQJZSHgGAB9AQAAAA==.Bourgùîgnon:BAAALgADCgcJCgAAAA==.',
Br='Bragasch:BAAALgADCgkJGQAAAA==.Brakhon:BAAALgAECgEJAQAAAA==.Bruisebrews:BAAALgADCgEJAQAAAA==.',
Bu='Bullplop:BAAALgADCgUJBQAAAA==.Burekbazino:BAAALgADCgcJCQAAAA==.Burningsleet:BAAALgAECgYJBgABLgAFFAgJEAAUAI8WAA==.',
['Bò']='Bò:BAACLgAFFH8KAAISAAQJ0wc+JADgAAASAAQJ0wc+JADgAAAuAAQKfzEAAhIACQmpF9kRADUCABIACQmpF9kRADUCAAAA.',
Ca='Caduceus:BAAALgADCgcJGAAAAA==.Caesus:BAABLgAECn8cAAIWAAcJFxcnIQCeAQAWAAcJFxcnIQCeAQAAAA==.Cagedancer:BAABLgAECn8hAAMTAAgJQwsHGAAsAQATAAgJHQoHGAAsAQASAAYJyAaNUADmAAAAAA==.Callio:BAACLgAFFH8HAAIFAAQJ7QRqQgAEAQAFAAQJ7QRqQgAEAQAuAAQKfy8AAgUACQmbEd07ANkBAAUACQmbEd07ANkBAAAA.Cantor:BAAALgAECgEJAQAAAA==.Caradd:BAAALgAECgcJBwAAAA==.Catchclause:BAAALgADCgkJFAAAAA==.Cathillex:BAABLgAECn8aAAMQAAkJTxdmFgAnAgAQAAkJTxdmFgAnAgAXAAEJ1AJgeQAWAAAAAA==.Cavagos:BAACLgAFFH8KAAIYAAQJKBDfAwA1AQAYAAQJKBDfAwA1AQAuAAQKfzYAAhgACQlWIK8BAL4CABgACQlWIK8BAL4CAAAA.Caycay:BAACLgAFFH8XAAIZAAYJDSJYAgDbAQAZAAYJDSJYAgDbAQAuAAQKf08AAhkACQkiJvEAAL4DABkACQkiJvEAAL4DAAAA.',
Ce='Celebrexi:BAAALgAECgcJBgAAAA==.Celene:BAAALgADCgYJBwAAAA==.Celtic:BAAALgADCgEJAQAAAA==.Cerrulli:BAAALgAECgYJDwAAAA==.',
Ch='Chaosknight:BAABLgAECn8WAAMDAAgJSRLAKQCJAQADAAgJSRLAKQCJAQACAAQJHgxplgB9AAAAAA==.Chaostrip:BAABLgAECn8yAAIGAAkJJyMlBwAKAwAGAAkJJyMlBwAKAwABLgAFFAIJBgAGAHcUAA==.Chariso:BAAALgAECgEJAQAAAA==.Cheddar:BAAALgAECgYJCQAAAA==.Chillbros:BAACLgAFFH8OAAIaAAUJdiFWBQBMAQAaAAUJdiFWBQBMAQAuAAQKfywAAxoACQkTJOABAAADABoACQkTJOABAAADAAMABAmqH+45AGcBAAAA.Chilldh:BAAALgAECgUJBQABLgAFFAUJDgAaAHYhAA==.Chillmage:BAAALgADCgcJCgABLgAFFAUJDgAaAHYhAA==.Chindi:BAABLgAECn8xAAMQAAkJ7xfvHQDrAQAQAAkJKxbvHQDrAQARAAcJUBJ8GABiAQAAAA==.Chindrakh:BAAALgAECggJEAABLgAECgkJMQAQAO8XAA==.Choiminasue:BAAALgAECgEJAgAAAA==.Chunga:BAABLgAECn8UAAIDAAYJoAPZXADQAAADAAYJoAPZXADQAAAAAA==.Chungers:BAAALgAECgQJBgAAAA==.Churd:BAACLgAFFH8LAAIWAAMJkxIvHgDcAAAWAAMJkxIvHgDcAAAuAAQKfykAAhYACQnkGJwPAEUCABYACQnkGJwPAEUCAAAA.Churdicus:BAAALgADCgkJEQAAAA==.Chypnotic:BAAALgAECgcJCwAAAA==.Chypper:BAAALgADCgEJAQAAAA==.Chypster:BAABLgAECn8hAAIDAAcJcw4OPwAcAQADAAcJcw4OPwAcAQAAAA==.',
Ci='Ciceroe:BAABLgAFFH8FAAIbAAMJiw9dIgDoAAAbAAMJiw9dIgDoAAAAAA==.Citadel:BAAALgADCgIJAwAAAA==.',
Cl='Cleft:BAABLgAECn8UAAIVAAYJCxDirAAIAQAVAAYJCxDirAAIAQAAAA==.Clevelandk:BAAALgAECgIJAgAAAA==.Clowwnshoes:BAAALgAECgEJAgAAAA==.',
Co='Coalystra:BAACLgAFFH8KAAIGAAQJuBgdLABKAQAGAAQJuBgdLABKAQAuAAQKfywAAgYACQnsGv8cAFICAAYACQnsGv8cAFICAAAA.Cocopuffs:BAACLgAFFH8HAAISAAIJsBG2FACfAAASAAIJsBG2FACfAAAuAAQKfzUAAhIACQleICMJAAMDABIACQleICMJAAMDAAAA.Colostrom:BAACLgAFFH8HAAIKAAQJNRltBAAzAQAKAAQJNRltBAAzAQAuAAQKfy8AAgoACQnVH9gFAHcCAAoACQnVH9gFAHcCAAAA.Complicatedz:BAAALgAECgUJBQAAAA==.Comul:BAAALgADCgcJBwAAAA==.Coramage:BAABLgAECn8aAAIBAAkJjwZAfwBeAQABAAkJjwZAfwBeAQAAAA==.Corentis:BAAALgADCgYJBgAAAA==.Corliss:BAABLgAECn8YAAIRAAgJkBQdFQCJAQARAAgJkBQdFQCJAQAAAA==.Cornholeo:BAAALgADCgkJCQAAAA==.',
Cp='Cplusmc:BAAALgAECgQJBwAAAA==.',
Cr='Creightizle:BAABLgAECn8eAAIFAAgJfRS/OQDHAQAFAAgJfRS/OQDHAQAAAA==.',
['Cá']='Cátix:BAAALgADCgMJAwAAAA==.',
Da='Daicmerollin:BAAALgAECgYJCwAAAA==.Danhaüsen:BAAALgAECgIJAwAAAA==.Darkbeast:BAABLgAFFH8FAAIFAAMJXRF6TADoAAAFAAMJXRF6TADoAAAAAA==.Darkdeeds:BAAALgADCggJEQAAAA==.Darkpallo:BAABLgAECn8YAAIVAAcJPxPWbwCdAQAVAAcJPxPWbwCdAQABLgAFFAMJBQAFAF0RAA==.Darthtav:BAAALgAFFAEJAgABLgAFFAYJEAASADwUAA==.Daten:BAABLgAECn8+AAIVAAkJ/RJ1ZgCzAQAVAAkJ/RJ1ZgCzAQAAAA==.Dazshauran:BAAALgADCgEJAQAAAA==.Daîma:BAAALgADCggJCAAAAA==.',
Db='Dbltap:BAAALgADCgEJAQAAAA==.',
De='Deathbycow:BAABLgAECn8rAAINAAgJlhz8CQAnAgANAAgJlhz8CQAnAgAAAA==.Debra:BAAALgADCgUJBQAAAA==.Decayed:BAABLgAECn8ZAAIHAAgJjRdWFQCnAQAHAAgJjRdWFQCnAQABLgAECgUJBQAMAAAAAA==.Deipally:BAAALgAECgYJBQAAAA==.Demonchalk:BAACLgAFFH8GAAIGAAUJ1xD7PAAVAQAGAAUJ1xD7PAAVAQAuAAQKfxYAAgYABglqI6A0AN0BAAYABglqI6A0AN0BAAEuAAUUBQkWABoAAyYA.Desdeynna:BAAALgADCgEJAQAAAA==.Deseral:BAAALgAECgIJAgAAAA==.Dewbie:BAAALgAECgEJAQAAAA==.',
Di='Diagonalli:BAABLgAECn8eAAIYAAkJNA/qBgDCAQAYAAkJNA/qBgDCAQAAAA==.Dimmadome:BAAALgADCgEJAQAAAA==.Dinojam:BAAALgADCgMJAQAAAA==.Divirian:BAAALgAECgYJDwAAAA==.',
Dj='Djdaemon:BAAALgADCgcJEgAAAA==.Djdrakshadow:BAAALgADCggJFAAAAA==.Djpaly:BAAALgADCgcJGAAAAA==.Djpriest:BAAALgAECgMJAwAAAA==.Djshadow:BAAALgAECgUJBQAAAA==.Djshadowar:BAAALgADCggJGgAAAA==.Djshadowhunt:BAAALgAECgMJAQAAAA==.Djshadowlock:BAAALgAECgMJAwAAAA==.Djshadowrog:BAAALgAECgYJBgAAAA==.Djshamy:BAAALgADCggJDwAAAA==.Djshaolin:BAAALgAECgQJBAAAAA==.Djzhadow:BAAALgAECgQJBQAAAA==.Djzhadruid:BAAALgADCgcJFQAAAA==.',
Dk='Dkshadow:BAAALgADCgcJDwAAAA==.',
Dm='Dmitrì:BAAALgAECgEJAQAAAA==.',
Do='Dogno:BAAALgAECgEJAgAAAA==.Dontdieplez:BAAALgAECgkJDAAAAA==.',
Dp='Dpm:BAAALgAECgEJAgAAAA==.',
Dr='Dragbuttakis:BAAALgAECgUJCAAAAA==.Drakhadir:BAAALgAECgQJBAAAAA==.Drakmon:BAAALgAECgIJBQAAAA==.Draktând:BAABLgAECn8uAAIbAAgJLBgnFADoAQAbAAgJLBgnFADoAQAAAA==.Drippysilk:BAAALgAECgQJCAABLgAECgkJJAAVAE4fAA==.Drius:BAAALgADCgMJAwAAAA==.Drunkenpanda:BAABLgAECn8lAAMcAAkJ9BTqHQADAgAcAAkJ9BTqHQADAgAdAAcJ1gjnRADUAAAAAA==.Drunknoodle:BAAALgAECgQJCAAAAA==.',
Du='Duhpriest:BAAALgAECgEJAQAAAA==.Duinrane:BAAALgAECgEJAQAAAA==.Duon:BAABLgAECn8WAAQdAAkJ3hTdHQCoAQAdAAgJexbdHQCoAQAcAAIJzwmCYQBJAAAeAAIJkgUHfQBAAAAAAA==.',
Dw='Dwagonfur:BAAALgAECgcJBgAAAA==.',
Ec='Echö:BAACLgAFFH8KAAIZAAQJBg41EAD/AAAZAAQJBg41EAD/AAAuAAQKfyEAAhkACAl5GTUPABMCABkACAl5GTUPABMCAAAA.',
Ei='Eiarinos:BAAALgADCgEJAQAAAA==.Eirø:BAAALgADCgkJCQABLgAFFAQJCgAFAPUfAA==.',
El='Elaine:BAAALgAECgkJDgAAAA==.Elberon:BAAALgAECgUJCwAAAA==.Ellspeth:BAAALgAECgkJCQAAAA==.Elmerhomero:BAAALgADCgUJBQAAAA==.Elronnd:BAAALgAECgMJAwAAAA==.Elsebeth:BAAALgADCgcJCAAAAA==.',
Em='Emilie:BAAALgADCgYJBgAAAA==.',
En='Enoch:BAABLgAECn8bAAIVAAYJkBZXfwB7AQAVAAYJkBZXfwB7AQAAAA==.',
Er='Eriam:BAAALgADCgIJAgABLgAECgkJIgANAE4ZAA==.Errane:BAACLgAFFH8YAAILAAUJjyV6CQAoAgALAAUJjyV6CQAoAgAuAAQKfywAAwsACAnJJosEAEYDAAsACAnJJosEAEYDABIAAQnHFVJ4AEQAAAAA.Eruiluvatar:BAAALgAECgYJCAAAAA==.',
Et='Etalia:BAAALgAECgEJAQAAAA==.Etcetera:BAAALgAECgMJAwAAAA==.',
Ev='Eveliel:BAAALgAECgEJAQAAAA==.',
Ex='Exlibris:BAAALgADCgcJDAAAAA==.',
Fa='Fallenangell:BAAALgADCgUJBQAAAA==.Fandiirn:BAAALgADCgYJBgAAAA==.Fastjack:BAABLgAECn8jAAMfAAgJ3RIYKwBaAQAfAAYJlxUYKwBaAQAWAAgJ0QZOOQALAQAAAA==.',
Fe='Felseeker:BAAALgADCgkJCQABLgAECgkJNQABAAQXAA==.',
Fi='Fiora:BAAALgADCgYJCwAAAA==.Firbirl:BAAALgAECgIJAgAAAA==.Fistoffury:BAABLgAECn8ZAAMeAAcJqBMtNAAdAQAeAAcJqBMtNAAdAQAdAAQJOAkEWgCoAAAAAA==.Fitco:BAAALgADCgYJCwABLgAECgYJDwAMAAAAAA==.Fiènd:BAAALgADCgYJBgAAAA==.',
Fl='Flametar:BAAALgAECgEJAQAAAA==.Floodlust:BAAALgADCgEJAQAAAA==.Floppydisk:BAAALgAECgUJDgAAAA==.',
Fo='Fortiss:BAACLgAFFH8KAAICAAMJ/hb4NwDlAAACAAMJ/hb4NwDlAAAuAAQKfysAAwIACQnWG8QLAOcCAAIACQnWG8QLAOcCAAMABgk/EKVKAO4AAAAA.',
Fr='Freelo:BAAALgAECgQJBQAAAA==.Frito:BAAALgAECggJCQAAAA==.Frost:BAAALgAFFAIJAgABLgAFFAcJIwAOAKkVAA==.Frostmon:BAABLgAECn8UAAIUAAkJuAs0XQCcAQAUAAkJuAs0XQCcAQAAAA==.Frshnvrfrzn:BAAALgAECggJDwAAAA==.Frøzenblight:BAAALgAECgEJAQAAAA==.',
Fu='Fulmo:BAAALgADCgUJBQABLgAECgkJGwAUAKwOAA==.Furbee:BAAALgAECggJEQAAAA==.Furn:BAAALgAECgkJAQAAAA==.',
['Fá']='Fáde:BAAALgADCgQJBQABLgAECgMJAwAMAAAAAA==.',
Ga='Gabris:BAAALgADCgYJBgAAAA==.Galeandra:BAABLgAECn8aAAIWAAcJ9QZ9QADpAAAWAAcJ9QZ9QADpAAAAAA==.Gallo:BAAALgADCgcJBwAAAA==.Garim:BAAALgADCgMJBAABLgAECggJIwAfAN0SAA==.',
Ge='Geraltofrvia:BAAALgAECgkJDgAAAA==.',
Gg='Gg:BAAALgAFFAIJAwABLgAFFAcJHgAgAGMlAA==.',
Gi='Giantgoose:BAAALgAECgEJAgAAAA==.Gingani:BAAALgADCgcJDAAAAA==.',
Gn='Gnar:BAABLgAECn8lAAIUAAYJdxLmkgAsAQAUAAYJdxLmkgAsAQAAAA==.',
Go='Gowtherdead:BAAALgADCgQJBAAAAA==.Gowtherpunch:BAACLgAFFH8KAAIeAAQJ2wUaLADlAAAeAAQJ2wUaLADlAAAuAAQKfzEAAh4ACQm5FQEVAPQBAB4ACQm5FQEVAPQBAAAA.',
Gr='Gregzug:BAAALgAECgMJAwAAAA==.Greyjoy:BAAALgADCgYJBQAAAA==.Grimfury:BAAALgAFFAIJBAAAAA==.Grimsy:BAAALgADCgYJBwAAAA==.Grodd:BAAALgADCgUJBQAAAA==.Groqqu:BAAALgAECgQJBAAAAA==.Grumble:BAAALgAECgYJCAAAAA==.Gruxxiron:BAAALgAECgUJBwABLgAECgkJOwAUAIIfAA==.',
Gu='Gulnn:BAABLgAECn8zAAMhAAkJJh2UEwCkAgAhAAkJJh2UEwCkAgAiAAIJVhT8VABvAAAAAA==.Gumby:BAAALgADCgYJBgAAAA==.',
Ha='Haelena:BAABLgAECn8eAAIEAAgJ6wuoNgBdAQAEAAgJ6wuoNgBdAQAAAA==.Halys:BAAALgADCgUJBQAAAA==.Hamil:BAAALgADCgEJAQAAAA==.Harmoss:BAAALgAECgcJBwAAAA==.Hawk:BAAALgADCgYJBgAAAA==.',
He='Heartsfang:BAAALgADCgUJCAAAAA==.Helfire:BAAALgADCgYJBgABLgAECgMJAwAMAAAAAA==.Hellscreems:BAAALgADCgMJAwAAAA==.Heriotza:BAABLgAECn8bAAIUAAkJrA4NbwByAQAUAAkJrA4NbwByAQAAAA==.',
Hx='Hxvenlyx:BAAALgADCgUJDgAAAA==.',
Ia='Iamfubar:BAAALgADCgMJBAAAAA==.',
Ig='Igris:BAAALgAECgcJCgAAAA==.',
Ii='Iimit:BAACLgAFFH8IAAIbAAMJxRYLIAD3AAAbAAMJxRYLIAD3AAAuAAQKfyIAAhsACAl6HBESAAACABsACAl6HBESAAACAAAA.',
Il='Illidead:BAACLgAFFH8YAAIBAAYJ6By3JwCbAQABAAYJ6By3JwCbAQAuAAQKfyIAAwEACAnTJCs7AIoCAAEACAnJICs7AIoCACMAAQmyJdgNAG8AAAAA.Iluni:BAAALgADCgMJAwAAAA==.',
Im='Implied:BAAALgADCgUJBQAAAA==.',
In='Indexes:BAABLgAECn8UAAMSAAYJkAm6SgDEAAASAAYJlwi6SgDEAAANAAUJGgYiSABgAAAAAA==.Insrik:BAAALgAECgcJEAAAAA==.Insurance:BAAALgAECggJCAABLgAFFAIJBQAFAPoGAA==.',
Io='Iompróirbáis:BAABLgAECn8hAAIUAAkJ7QfDbwBxAQAUAAkJ7QfDbwBxAQAAAA==.',
Ir='Irdeadohnoz:BAABLgAECn8aAAIBAAcJTAzKpgAVAQABAAcJTAzKpgAVAQAAAA==.',
Is='Ist:BAAALgAECgMJAwAAAA==.',
It='Itchigo:BAABLgAECn8UAAIFAAgJ1A3OVgCGAQAFAAgJ1A3OVgCGAQAAAA==.',
Iv='Ivern:BAAALgAECgIJAgAAAA==.Ivgorod:BAABLgAECn8kAAMYAAkJ1gh1CgBiAQAYAAkJnAh1CgBiAQAIAAgJBAbPRgDsAAAAAA==.',
Ja='Jabbadahut:BAAALgAECgcJBQAAAA==.Jambi:BAAALgAECgYJDgAAAA==.Jardani:BAAALgAECgEJAQAAAA==.Jarhead:BAAALgADCgUJBQAAAA==.Jastrae:BAAALgAECgcJDgAAAA==.Jaziani:BAAALgADCgcJBwABLgAECgMJAwAMAAAAAA==.Jazilyne:BAAALgAECgMJAwAAAA==.',
Je='Jealous:BAAALgADCgUJBQABLgAECgkJIgAGAJ0dAA==.Jenka:BAAALgAECgUJCgAAAA==.',
Ji='Jibbs:BAAALgADCgkJCQAAAA==.',
Jo='Joleya:BAAALgADCgEJAQAAAA==.',
Ju='Junta:BAAALgADCgcJJQAAAA==.Justine:BAAALgADCgUJBQAAAA==.Justtrolling:BAAALgAECgYJDgAAAA==.',
['Jä']='Jäkel:BAAALgADCgUJBQAAAA==.',
Ka='Kalike:BAAALgADCgcJBwAAAA==.Kambative:BAABLgAECn8XAAMLAAcJqxIPQgCZAQALAAcJqxIPQgCZAQASAAMJGBa5ZgBkAAABLgAFFAMJBQAJACkKAA==.Kammunion:BAAALgAECgYJDQABLgAFFAMJBQAJACkKAA==.Kamphiyer:BAACLgAFFH8FAAMJAAMJKQpjHQCvAAAJAAMJKQpjHQCvAAAIAAIJtwOUUABiAAAuAAQKfzoABAkACQnqGH0JAD0CAAkACQnqGH0JAD0CAAgACAmIHWkSADQCABgABAmjDMExAIgAAAAA.Kamsumerage:BAAALgADCgkJEgABLgAFFAMJBQAJACkKAA==.Kandosii:BAAALgADCgUJBQAAAA==.Kantheal:BAABLgAECn8kAAIEAAkJbR7SBwD7AgAEAAkJbR7SBwD7AgAAAA==.Kaulana:BAAALgADCgcJDAAAAA==.',
Ke='Keirmania:BAAALgAECgEJAQAAAA==.Kekkan:BAAALgADCgcJCgAAAA==.Kellendere:BAAALgAECgYJBgAAAA==.',
Ki='Kiieedk:BAAALgAECgEJAQAAAA==.Kimgoeun:BAAALgADCgYJBgAAAA==.Kio:BAAALgAECgYJCAAAAA==.',
Kl='Klompus:BAAALgADCgQJBAAAAA==.',
Kn='Knùsê:BAAALgADCgUJBgABLgAFFAQJCgAFAPUfAA==.',
Ko='Komorai:BAAALgADCgYJBgAAAA==.',
Kr='Kravex:BAABLgAECn8iAAINAAkJThn2CAA8AgANAAkJThn2CAA8AgAAAA==.Krixxa:BAABLgAECn8oAAIfAAkJWCS2AgBkAwAfAAkJWCS2AgBkAwAAAA==.',
Ku='Kuula:BAAALgAECgEJAQAAAA==.',
Ky='Kylana:BAAALgADCgQJBAABLgAECggJHQALANAMAA==.',
['Kä']='Kären:BAAALgAECgUJEgAAAA==.',
['Ké']='Kélly:BAAALgAECggJCAAAAA==.',
La='Laochnaofa:BAAALgAECgcJDQAAAA==.Larayvia:BAACLgAFFH8IAAIFAAMJ3QIsXQC1AAAFAAMJ3QIsXQC1AAAuAAQKfx0AAgUACAkrDkc7AMEBAAUACAkrDkc7AMEBAAAA.Laurance:BAAALgADCgYJBgAAAA==.',
Le='Leakygasket:BAAALgAECgYJBwAAAA==.Leesala:BAABLgAECn8wAAMCAAkJqRe8GwBTAgACAAkJqRe8GwBTAgAaAAEJ/gQGOgAnAAAAAA==.Lelora:BAAALgAECgEJAQAAAA==.Lerazer:BAAALgAECgYJCgAAAA==.',
Lg='Lgidk:BAAALgADCgMJAwABLgAECgkJIgAGAJ0dAA==.',
Li='Lic:BAAALgAECgUJBwAAAA==.Liea:BAAALgAECgMJBAAAAA==.Lilbash:BAAALgAECgEJAQAAAA==.Liliatrix:BAAALgAECgQJBQAAAA==.Lillabet:BAAALgAECgYJEAAAAA==.Lilmatty:BAAALgAECgkJDQABLgAFFAUJCQAcAFkZAA==.Lilsneaky:BAAALgADCggJCAAAAA==.Limpydk:BAAALgADCgUJBQABLgAECgkJJAAVAE4fAA==.Limpylarva:BAAALgADCgMJAwABLgAECgkJJAAVAE4fAA==.Limpypal:BAABLgAECn8kAAMVAAkJTh+7DQDiAgAVAAkJTh+7DQDiAgAKAAIJZAQ9QQBGAAAAAA==.Litter:BAAALgAECgUJBQAAAA==.',
Lo='Logathil:BAAALgAECgYJEAAAAA==.',
Lu='Luchulainn:BAAALgADCgYJBgAAAA==.Lucifero:BAAALgAECggJCgAAAA==.Lucifurwild:BAAALgADCgQJBQAAAA==.Lunaaris:BAABLgAECn8rAAILAAkJBR8yDgDVAgALAAkJBR8yDgDVAgAAAA==.Lunastre:BAAALgADCgEJAQAAAA==.',
['Lí']='Límpy:BAABLgAECn8aAAIYAAYJ/CJ/CgA0AgAYAAYJ/CJ/CgA0AgABLgAECgkJJAAVAE4fAA==.Línk:BAAALgAECgYJCgAAAA==.',
['Lî']='Lîkwuid:BAAALgAECggJDwAAAA==.',
Ma='Macallan:BAAALgAECgIJBAAAAA==.Maddrox:BAAALgADCgcJGAAAAA==.Magicmarv:BAAALgADCgIJAQAAAA==.Magnagoth:BAAALgADCgkJDwAAAA==.Magnakilro:BAABLgAECn8fAAIFAAkJRxcwMQAAAgAFAAkJRxcwMQAAAgAAAA==.Mahnaz:BAAALgADCgEJAQABLgADCgcJCgAMAAAAAA==.Mahuta:BAAALgAECgEJAQAAAA==.Malanath:BAABLgAECn8XAAIIAAgJtBX4JACbAQAIAAgJtBX4JACbAQAAAA==.Malditto:BAAALgADCgYJBgAAAA==.Maleficus:BAAALgADCgkJEQABLgAECgYJCQAMAAAAAA==.Malothas:BAAALgADCgQJBAAAAA==.Mareki:BAAALgADCgYJBwAAAA==.Markdfordeth:BAAALgAECgEJAQAAAA==.Mattingly:BAAALgAECgQJBQAAAA==.Mattyfu:BAACLgAFFH8JAAIcAAUJWRn1EgCbAQAcAAUJWRn1EgCbAQAuAAQKfxUAAx0ACAmWFyQdAPEBAB0ACAmWFyQdAPEBABwAAwnJH25JABEBAAAA.Mavíel:BAAALgAECgYJDQAAAA==.Maxrogue:BAAALgAECgYJCwABLgAECggJJAANAMsQAA==.Mazikeen:BAAALgAECgUJBgAAAA==.',
Mc='Mcscoots:BAAALgADCgcJEgAAAA==.',
Me='Meatsupreme:BAACLgAFFH8GAAIVAAMJtAeRYwDGAAAVAAMJtAeRYwDGAAAuAAQKfykAAhUACQm4EThVALIBABUACQm4EThVALIBAAAA.Meepin:BAACLgAFFH8VAAIEAAUJLBxeDQC9AQAEAAUJLBxeDQC9AQAuAAQKfzcAAwQACQkLJAQFABwDAAQACQkLJAQFABwDABUAAwk/CoMPAYMAAAAA.Meepmorp:BAAALgADCgcJDgAAAA==.Meifeng:BAAALgADCgEJAQAAAA==.Melithara:BAAALgAECgQJBAAAAA==.Mephala:BAAALgADCgYJBgAAAA==.Merdoc:BAAALgAECgEJAQAAAA==.Mesophistole:BAAALgADCggJCwABLgAECgYJFgAiAJsFAA==.Mesopunchy:BAAALgADCgcJAgABLgAECgYJFgAiAJsFAA==.Mesopyro:BAABLgAECn8WAAIiAAYJmwV3HgCgAAAiAAYJmwV3HgCgAAAAAA==.',
Mi='Mileenä:BAAALgAECgkJDwAAAA==.Minimim:BAAALgADCgMJAwAAAA==.Mistyra:BAABLgAECn8WAAIcAAkJ+B2cBwAIAwAcAAkJ+B2cBwAIAwABLgAECgkJKAAfAFgkAA==.Mià:BAAALgADCgEJAQAAAA==.',
Mo='Mod:BAABLgAECn8UAAINAAcJghVBGgBXAQANAAcJghVBGgBXAQAAAA==.Mograiné:BAAALgAECgQJCQAAAA==.Mojodaemon:BAAALgADCgcJCgAAAA==.Mojoy:BAAALgAECgEJAQAAAA==.Monkaw:BAAALgAECgIJAgAAAA==.Monkchalk:BAAALgAECgQJBAABLgAFFAUJFgAaAAMmAA==.Moondevil:BAAALgAECgEJAQAAAA==.Morta:BAEALgAFFAIJAgAAAA==.Mortkavaliro:BAAALgAECgYJDgAAAA==.',
Ms='Mslockness:BAAALgADCgYJEwAAAA==.',
Mu='Mugzy:BAAALgAECgkJBwAAAA==.Multipass:BAABLgAECn8ZAAILAAgJjyDHEQCuAgALAAgJjyDHEQCuAgAAAA==.Multitool:BAAALgADCgEJAQAAAA==.',
['Mö']='Mörph:BAAALgAECgIJAgAAAA==.',
Na='Nadris:BAAALgADCgcJBwAAAA==.Nanérs:BAAALgAECgcJEQABLgAFFAYJEAASADwUAA==.Narrodus:BAABLgAECn8kAAIkAAkJPSXHAAA7AwAkAAkJPSXHAAA7AwAAAA==.Nasht:BAABLgAECn8VAAIBAAYJUBaOnAAmAQABAAYJUBaOnAAmAQAAAA==.Nashty:BAAALgADCgYJBgABLgAECgYJFQABAFAWAA==.Nashxi:BAAALgADCgkJEAABLgAECgYJFQABAFAWAA==.Nasu:BAAALgAECgcJAQAAAA==.Nattymoo:BAAALgAECgYJCQABLgAFFAUJCQAcAFkZAA==.',
Ne='Necrô:BAAALgADCgIJAgAAAA==.Nephi:BAAALgAECgEJAgAAAA==.',
Ni='Nightraven:BAAALgADCgkJEAAAAA==.Nightreaper:BAAALgADCgkJGwAAAA==.Nimbus:BAACLgAFFH8eAAIDAAUJKCPuDACXAQADAAUJKCPuDACXAQAuAAQKf3AAAgMACQkPJuEAAHcDAAMACQkPJuEAAHcDAAEuAAUUCAkeAAgA8hsA.Nimike:BAAALgAECgcJDQAAAA==.',
No='Normul:BAAALgAECgcJAwABLgAFFAQJCQAlAFURAA==.Noshoba:BAAALgAECgEJAgAAAA==.',
Nr='Nrvous:BAAALgADCgkJCQAAAA==.',
Nu='Nugzuul:BAAALgAECgEJAQAAAA==.Nuid:BAAALgAECgkJBgAAAA==.Numbers:BAABLgAECn8UAAMZAAYJHA/7LgDpAAAZAAYJCQ77LgDpAAAGAAYJnArJnADJAAAAAA==.',
Ny='Nyterage:BAAALgAECgIJAgAAAA==.Nytesage:BAACLgAFFH8iAAIgAAYJQiYuAAAoAgAgAAYJQiYuAAAoAgAuAAQKfygAAiAACAkMJj8AAH4DACAACAkMJj8AAH4DAAAA.',
['Nä']='Näners:BAAALgAFFAEJAQABLgAFFAYJEAASADwUAA==.',
['Nì']='Nìghtcat:BAAALgAECgQJBwAAAA==.',
Oo='Ookle:BAABLgAECn8nAAMTAAkJVwqLEgBvAQATAAkJVwqLEgBvAQALAAcJ0wqHZQDyAAAAAA==.',
Or='Orchard:BAABLgAFFH8JAAIdAAUJ8BHsEwAOAQAdAAUJ8BHsEwAOAQAAAA==.Oresh:BAABLgAECn8nAAIQAAcJfRIjNABkAQAQAAcJfRIjNABkAQAAAA==.Orgrom:BAAALgAECgkJBwAAAA==.Oryz:BAAALgADCgkJCAAAAA==.',
Os='Osajak:BAAALgADCgIJAgAAAA==.',
Oz='Ozo:BAABLgAECn8ZAAIhAAYJLQzQmgD+AAAhAAYJLQzQmgD+AAAAAA==.',
Pa='Painavolian:BAABLgAECn9LAAIBAAkJzCDZEQDbAgABAAkJzCDZEQDbAgAAAA==.Palifur:BAAALgAECgkJDwAAAA==.Pandamonium:BAAALgAECgcJEgAAAA==.Panes:BAAALgAECgcJCwAAAA==.Paopu:BAAALgADCgYJBgABLgAECgkJIAAhAPYfAA==.',
Pe='Peeches:BAAALgAECgYJCwAAAA==.Pelonis:BAAALgADCgcJAgAAAA==.Pelor:BAAALgAECgcJDwAAAA==.',
Ph='Pheayre:BAAALgADCgkJDAABLgAECgcJDAAMAAAAAA==.',
Pi='Pisspadpanda:BAACLgAFFH8PAAMhAAQJIxeUOABEAQAhAAQJIxeUOABEAQAmAAEJhBrCHQBNAAAuAAQKfykAAiEACQltIuMTAKICACEACQltIuMTAKICAAAA.',
Pl='Plsbnice:BAAALgAECgYJCAABLgAECgkJIgAGAJ0dAA==.',
Po='Poggies:BAACLgAFFH8eAAMgAAcJYyUjAABiAgAgAAcJYyUjAABiAgAjAAEJ3gjgAwBRAAAuAAQKfyEAAyAACAk9JjkAAIIDACAACAk9JjkAAIIDACMAAQkOIP8WAGIAAAAA.Pollypocket:BAAALgAECgEJAQAAAA==.Ponmonk:BAAALgAECgEJAQABLgAECgYJFQAWALcfAA==.Pontacos:BAABLgAECn8VAAIWAAYJtx/AIADTAQAWAAYJtx/AIADTAQAAAA==.Porkinator:BAAALgADCgYJCAAAAA==.Powdur:BAAALgADCgEJAQABLgAFFAMJDQAOAMIZAA==.Pozh:BAABLgAECn8UAAIhAAYJlA0HkQA3AQAhAAYJlA0HkQA3AQAAAA==.',
Pr='Praynes:BAACLgAFFH8KAAIfAAQJbg1SFgDqAAAfAAQJbg1SFgDqAAAuAAQKfzEAAh8ACQnoGMkSAEoCAB8ACQnoGMkSAEoCAAAA.Precedence:BAAALgADCgEJAQABLgAECgEJAQAMAAAAAA==.Prestocreamÿ:BAAALgADCgEJAQAAAA==.',
Pu='Pummel:BAAALgAECgYJCwAAAA==.Pupperputh:BAAALgADCgkJEgABLgAECgkJIgAGAJ0dAA==.Puppet:BAAALgAECgEJAwAAAA==.',
['Pä']='Päroxysm:BAAALgAECgEJAgABLgAECgYJBgAMAAAAAA==.',
Qu='Quígon:BAAALgAECgIJAwABLgAECgcJBQAMAAAAAA==.',
Ra='Rach:BAAALgADCgYJBgAAAA==.Randyrando:BAAALgADCgIJBAAAAA==.Ranoe:BAABLgAECn8jAAIGAAcJCRbzVAClAQAGAAcJCRbzVAClAQAAAA==.Rastrin:BAAALgADCgcJDgAAAA==.Ravyniel:BAAALgAECgEJAQAAAA==.Razji:BAABLgAECn9DAAQOAAkJ1yR9AQA8AwAOAAkJPiR9AQA8AwAPAAcJsSENGABtAgAFAAIJiSbQgQDjAAAAAA==.',
Re='Redrrum:BAAALgAECgcJCgAAAA==.Rekd:BAAALgADCgEJAQAAAA==.Reladiia:BAAALgAECgEJAQAAAA==.Renfro:BAAALgADCgcJBwAAAA==.Restokhan:BAAALgAFFAEJAQAAAA==.Revoked:BAAALgADCgEJAQABLgAECgYJDwAMAAAAAA==.Reznick:BAABLgAECn8ZAAIQAAgJ6g6YMwBnAQAQAAgJ6g6YMwBnAQAAAA==.',
Ro='Rocknwolf:BAAALgAECgEJAQAAAA==.Rokd:BAAALgAECgcJDQAAAA==.Rokham:BAAALgADCgEJAQAAAA==.Rosalee:BAAALgADCgEJAQAAAA==.Rovërgalarga:BAAALgADCgMJAwAAAA==.',
Ru='Rudeboy:BAAALgAECgEJAQAAAA==.Ruibaron:BAABLgAECn8VAAIBAAYJDxcniABMAQABAAYJDxcniABMAQAAAA==.',
Ry='Ryhunter:BAAALgADCggJDgAAAA==.',
['Rà']='Ràidèn:BAABLgAECn8yAAIUAAkJKSCcFQCyAgAUAAkJKSCcFQCyAgAAAA==.',
['Rá']='Ráyne:BAAALgAECgUJCgAAAA==.',
Sa='Sadeel:BAABLgAECn8sAAMmAAkJVhrqCgCPAQAhAAkJdBKmRQD6AQAmAAcJKB3qCgCPAQAAAA==.Sadewolf:BAABLgAECn8pAAIGAAkJ6xt/GQBoAgAGAAkJ6xt/GQBoAgAAAA==.Sadpanduh:BAAALgAECgYJCwAAAA==.Saltednuts:BAAALgAECgEJAQAAAA==.Samentoni:BAACLgAFFH8GAAIEAAMJ8RSEKQDEAAAEAAMJ8RSEKQDEAAAuAAQKfyoAAgQACQljG/gNAJ8CAAQACQljG/gNAJ8CAAAA.Samgal:BAABLgAECn8bAAIiAAkJtBgzBAAoAgAiAAkJtBgzBAAoAgAAAA==.Sardothien:BAAALgAECgEJAgAAAA==.Satyra:BAAALgAECgcJEgABLgAECgkJKAAfAFgkAA==.Saurphang:BAACLgAFFH8aAAMUAAUJChUeGABFAQAUAAQJChUeGABFAQAHAAEJAAAsVwAAAAAuAAQKfywAAhQACQlOIhIVAP0CABQACQlOIhIVAP0CAAAA.Saye:BAAALgADCgIJAgAAAA==.',
Sc='Scarletpanda:BAAALgADCgQJBgAAAA==.Scourgereap:BAAALgAECgMJAwAAAA==.',
Se='Selinna:BAAALgAECggJEgAAAA==.Senpaichill:BAAALgAECgYJDQAAAA==.Severis:BAAALgADCgIJAgAAAA==.',
Sg='Sgtmajdaly:BAAALgADCgMJAwAAAA==.',
Sh='Shadiepope:BAAALgAECgIJAwAAAA==.Shadora:BAABLgAECn8gAAIWAAkJLBOeGQDcAQAWAAkJLBOeGQDcAQAAAA==.Shadowwizard:BAAALgAECgMJAwAAAA==.Shadybrat:BAAALgAECgYJDQABLgAFFAIJBQAFAPoGAA==.Shaggylol:BAAALgADCgcJDQAAAA==.Shaladin:BAAALgAECgcJBgAAAA==.Shamlazy:BAAALgADCgkJHQAAAA==.Shidan:BAAALgAECggJEAABLgAECgkJMgAUACkgAA==.Shiroku:BAAALgAECgkJBgAAAA==.Shockchalk:BAACLgAFFH8WAAIaAAUJAyanAgCSAQAaAAUJAyanAgCSAQAuAAQKfzYAAxoACQnhJakAAE8DABoACQnhJakAAE8DAAMAAglhETl1AGoAAAAA.Shocknorris:BAAALgAECgQJBwABLgAECgYJDwAMAAAAAA==.Shrooclaw:BAACLgAFFH8LAAILAAMJsxD9NgDBAAALAAMJsxD9NgDBAAAuAAQKfx4AAwsACQnYE0IwAM4BAAsACQnYE0IwAM4BABMAAgkGHZs4AFQAAAAA.',
Si='Sibbiah:BAAALgAECggJCAAAAA==.Silanre:BAABLgAECn8rAAIBAAcJcRZKaQCQAQABAAcJcRZKaQCQAQAAAA==.',
Sk='Skaðï:BAACLgAFFH8KAAIFAAQJ9R+ZGAB2AQAFAAQJ9R+ZGAB2AQAuAAQKfzQABA8ACQkOI2UDAIUCAA8ACAnQI2UDAIUCAA4ABAnvGXUqAD4BAAUAAwnpHs6+AKQAAAAA.',
Sl='Slizzard:BAAALgADCgQJBAABLgAFFAQJCQAlAFURAA==.',
Sm='Smolshrapnel:BAABLgAECn8WAAIOAAcJ0ATBMAATAQAOAAcJ0ATBMAATAQAAAA==.',
Sn='Sneakchalk:BAAALgADCgcJCwABLgAFFAUJFgAaAAMmAA==.',
So='Solaraze:BAABLgAECn8qAAQVAAkJXh0NMgAfAgAVAAgJCR4NMgAfAgAEAAIJdBCkaQBwAAAKAAEJLQZeTgAiAAAAAA==.Solinarie:BAAALgADCggJCgAAAA==.Sorefang:BAAALgADCgEJAQAAAA==.Sorrowfang:BAAALgAECgEJAQAAAA==.Sovnightwar:BAAALgAECggJDwABLgAFFAUJCgAGACAcAA==.Soza:BAAALgADCgEJAQAAAA==.',
Sp='Spacespecial:BAAALgAECggJEwAAAA==.Sparklebunny:BAAALgADCgEJAQAAAA==.Spicycurryy:BAABLgAECn8+AAQFAAkJuB8/GgBqAgAFAAgJeCA/GgBqAgAOAAgJvxe0EgAGAgAPAAIJJAzGeABeAAABLgAECgkJPgAFALgfAA==.Spicyycurryy:BAAALgAECgUJCQABLgAECgkJPgAFALgfAA==.Spiker:BAAALgAECgEJAQAAAA==.Splittail:BAAALgAECgUJBQAAAA==.',
St='Staggertrip:BAAALgADCgQJBAABLgAFFAIJBgAGAHcUAA==.Strahm:BAABLgAECn8kAAINAAgJyxD2GgBQAQANAAgJyxD2GgBQAQAAAA==.Strehm:BAAALgAECgQJBQABLgAECggJJAANAMsQAA==.Strohmjr:BAAALgADCgMJBQABLgAECggJJAANAMsQAA==.Strohmy:BAAALgADCgEJAQABLgAECggJJAANAMsQAA==.Stryhm:BAAALgAECgQJBgABLgAECggJJAANAMsQAA==.',
Su='Sunju:BAAALgADCgMJAwAAAA==.',
Sy='Sylvexa:BAAALgAECgEJAQAAAA==.Syns:BAAALgAECgUJBQAAAA==.Syssare:BAABLgAECn8mAAIZAAgJwCOCBgC0AgAZAAgJwCOCBgC0AgAAAA==.',
['Sé']='Sétt:BAAALgAECgUJBQAAAA==.',
Ta='Tabbie:BAAALgADCgYJCQAAAA==.Tacpally:BAAALgADCgMJAwAAAA==.Talasam:BAAALgAECggJEAAAAA==.Talien:BAAALgADCgEJAQAAAA==.Tandsonnara:BAAALgAECgkJDAAAAA==.Tastetickle:BAACLgAFFH8GAAIBAAMJGw6IcwDbAAABAAMJGw6IcwDbAAAuAAQKfzUAAgEACQkvH64aAKQCAAEACQkvH64aAKQCAAAA.Tavv:BAAALgAFFAIJAgABLgAFFAYJEAASADwUAA==.Tazdrin:BAACLgAFFH8KAAInAAQJnwd9BgAAAQAnAAQJnwd9BgAAAQAuAAQKfzIAAicACQkmFwAFAA0CACcACQkmFwAFAA0CAAAA.',
Te='Telidrus:BAACLgAFFH8VAAIBAAYJAxhtKgCRAQABAAYJAxhtKgCRAQAuAAQKfywABAEACAn7IGkxAK0CAAEABwlBJGkxAK0CACMABAnMHe4FAFABACAAAglcE8MPADsAAAAA.Temok:BAAALgADCggJCAAAAA==.Teyrlis:BAAALgAECgUJCAAAAA==.',
Th='Thavryn:BAAALgADCgYJBgAAAA==.Thaz:BAAALgAECgQJBwAAAA==.Thias:BAABLgAECn8cAAIBAAgJQhMHaQCRAQABAAgJQhMHaQCRAQAAAA==.Thukmonk:BAAALgAECgQJBwAAAA==.Thukwarlock:BAABLgAECn8hAAIhAAcJ7xgoSQDuAQAhAAcJ7xgoSQDuAQAAAA==.Thunderbug:BAAALgADCgEJAQAAAA==.Thunderhorse:BAAALgADCgUJBQAAAA==.',
To='Todd:BAAALgAECgEJAQAAAA==.Tokain:BAAALgAECgMJAwAAAA==.Topaze:BAAALgAECgUJCAAAAA==.Torironheart:BAAALgADCgcJBwAAAA==.',
Tr='Trance:BAAALgAECgEJAQABLgAECgEJAQAMAAAAAA==.Treehuggera:BAAALgAECgYJCgAAAA==.Tribunal:BAAALgAECgEJAQAAAA==.Trilila:BAAALgADCgYJBgAAAA==.Tripx:BAABLgAECn8cAAMVAAkJbiP5BQAxAwAVAAkJbiP5BQAxAwAKAAEJ2A8CRgAoAAABLgAFFAIJBgAGAHcUAA==.Tronko:BAABLgAECn8lAAMCAAkJHBwlEwCaAgACAAkJHBwlEwCaAgADAAEJ8BOmkAA1AAAAAA==.Trumpinator:BAAALgADCgYJDAAAAA==.',
Ts='Tsireya:BAAALgAECgUJCgABLgAECgQJDgAMAAAAAA==.',
Tu='Tullip:BAAALgAECgEJAQAAAA==.Turntsnaco:BAACLgAFFH8HAAIbAAIJJBiaKQCgAAAbAAIJJBiaKQCgAAAuAAQKfz0AAxsACAnnIXAKAGcCABsACAnnIXAKAGcCACgAAQleFXMhAEEAAAAA.Tusk:BAAALgAECgcJEQAAAA==.',
Tw='Twigger:BAAALgAECgEJAQAAAA==.Twiztedsoul:BAAALgAECgMJAwAAAA==.Twophorb:BAAALgADCgMJAwAAAA==.',
Ua='Uake:BAAALgADCgYJBgAAAA==.',
Ud='Udgar:BAAALgAECgkJEQAAAA==.',
Un='Unafhaen:BAAALgADCgEJAQAAAA==.Unaverse:BAAALgAECgEJAQAAAA==.',
Us='Usmc:BAAALgADCgYJBgAAAA==.Usmccpl:BAAALgAECgYJDQAAAA==.Usmcsemperfi:BAAALgAECgQJBAAAAA==.',
Va='Valengarde:BAACLgAFFH8FAAIVAAMJcw1LXADWAAAVAAMJcw1LXADWAAAuAAQKfxsAAhUACQmYFrhEAOABABUACQmYFrhEAOABAAAA.Vanette:BAAALgAECgIJAgAAAA==.Vangoon:BAAALgADCgIJAgAAAA==.Vannix:BAACLgAFFH8HAAIWAAMJFCLtFQAjAQAWAAMJFCLtFQAjAQAuAAQKfzcAAhYACQmSI8kDAA0DABYACQmSI8kDAA0DAAAA.Vanz:BAAALgADCgIJAgAAAA==.Varnos:BAAALgAECgEJAwAAAA==.',
Ve='Velranis:BAAALgADCgMJAwABLgAECgkJFAAeABoWAA==.Velthas:BAAALgADCggJIQAAAA==.',
Vi='Viollet:BAAALgAECgIJAgAAAA==.Virmethir:BAABLgAECn8gAAMYAAcJQhGbCgBfAQAYAAcJ4hCbCgBfAQAIAAYJVgbyXACcAAAAAA==.Viruz:BAAALgAECgYJBgAAAA==.',
Vo='Volley:BAAALgADCgEJAQAAAA==.Voltaren:BAAALgAECgcJCAABLgAECgkJKgAVAF4dAA==.',
Vy='Vylaran:BAAALgADCgYJBgAAAA==.Vyndrolan:BAAALgAFFAEJAQAAAA==.Vyroth:BAAALgADCgUJBQAAAA==.',
Wa='Walksonwater:BAAALgADCgEJAQABLgAECgkJJAAEAG0eAA==.Waq:BAAALgAECgcJDwAAAA==.',
We='Wellamor:BAAALgADCgIJAgAAAA==.',
Wi='Winterbreeze:BAAALgADCgYJBgAAAA==.Wiwi:BAACLgAFFH8JAAMlAAQJVREmCwAdAQAlAAQJgA4mCwAdAQAUAAEJPBFT5gBEAAAuAAQKfzIAAxQACQnGIWcRANACABQACQnGIWcRANACACUAAwm8G68ZANAAAAAA.',
Xa='Xares:BAACLgAFFH8GAAIBAAMJuRtaYwAEAQABAAMJuRtaYwAEAQAuAAQKfzUAAgEACQmsG7kgAIYCAAEACQmsG7kgAIYCAAAA.Xash:BAAALgAECgEJAQAAAA==.',
Xe='Xerath:BAAALgADCgcJBwAAAA==.',
Xh='Xhades:BAAALgAECgYJDgAAAA==.',
Ya='Yalda:BAAALgAECgYJEQAAAA==.',
Yf='Yfra:BAAALgAECggJEQAAAA==.',
Yo='Yochangsvegn:BAAALgAECggJEAAAAA==.Yoseph:BAABLgAECn8XAAITAAgJjQ9LFQBJAQATAAgJjQ9LFQBJAQAAAA==.',
Yu='Yungblood:BAAALgAECgUJBwAAAA==.Yurimancer:BAABLgAECn8xAAIWAAgJvRrNFAAKAgAWAAgJvRrNFAAKAgAAAA==.',
Za='Zaen:BAAALgADCgMJAwAAAA==.Zake:BAAALgAECgMJBAAAAA==.Zalileina:BAAALgADCgMJAwAAAA==.Zallith:BAAALgADCgMJAwABLgAECgYJDgAMAAAAAA==.Zappythile:BAABLgAECn8sAAICAAkJfxtfHwA6AgACAAkJfxtfHwA6AgAAAA==.Zarkamental:BAAALgADCgYJCwABLgAFFAMJBQAGAEcCAA==.Zarthos:BAAALgAECgEJAQABLgAECgEJAwAMAAAAAA==.',
Ze='Zect:BAABLgAECn8YAAQmAAYJLB4tDAB2AQAmAAYJOBstDAB2AQAhAAUJZRnAnAD6AAAiAAEJFBWsbwA3AAAAAA==.Zelinor:BAAALgADCgcJBwAAAA==.',
Zi='Ziêg:BAAALgADCgcJBwAAAA==.',
Zo='Zoz:BAABLgAECn8WAAIBAAYJbwtrvQDvAAABAAYJbwtrvQDvAAAAAA==.',
Zu='Zulfrik:BAABLgAECn83AAIBAAkJNhlJMgA4AgABAAkJNhlJMgA4AgAAAA==.Zullard:BAAALgAECgEJAQAAAA==.',
Zy='Zyzy:BAABLgAECn8ZAAIDAAkJIiH2BAACAwADAAkJIiH2BAACAwAAAA==.',
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
