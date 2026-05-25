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

local lookup = {'Mage-Frost','Shaman-Restoration','Shaman-Elemental','Paladin-Holy','Hunter-BeastMastery','DemonHunter-Devourer','DeathKnight-Blood','Evoker-Augmentation','Evoker-Preservation','Paladin-Protection','Druid-Restoration','Unknown-Unknown','Druid-Guardian','Hunter-Survival','Hunter-Marksmanship','Warrior-Fury','Warrior-Protection','Druid-Balance','Druid-Feral','DeathKnight-Unholy','Paladin-Retribution','Warrior-Arms','Evoker-Devastation','DemonHunter-Havoc','Shaman-Enhancement','Priest-Shadow','Rogue-Subtlety','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','Priest-Holy','Mage-Fire','Warlock-Demonology','Warlock-Destruction','Mage-Arcane','DemonHunter-Vengeance','DeathKnight-Frost','Warlock-Affliction','Rogue-Outlaw','Rogue-Assassination',}
local provider = {region='US',realm='Eonar',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abbazaad:BAAALgAECgQJBQAAAA==.Abreen:BAAALgADCgcJCQAAAA==.Abysseus:BAAALgADCgcJCAAAAA==.',
Ac='Acepriest:BAAALgAECgMJBAAAAA==.Achievement:BAAALgAECgQJBAAAAA==.',
Ad='Adeathfox:BAAALgADCgEJAQAAAA==.Adhoc:BAAALgADCgUJBQAAAA==.Admired:BAABLgAECn8cAAIBAAcJoB4OVwAzAgABAAcJoB4OVwAzAgAAAA==.Adyr:BAACLgAFFH8JAAMCAAQJUhLPKgD/AAACAAQJUhLPKgD/AAADAAIJPgihNQB9AAAuAAQKfyQAAwIACAmUH2wTAHoCAAIACAmUH2wTAHoCAAMABQnlF0pNABMBAAAA.',
Ai='Aidra:BAABLgAECn8jAAIEAAYJ3B0GHQD0AQAEAAYJ3B0GHQD0AQAAAA==.',
Al='Alaira:BAAALgAECgMJAwABLgAECgYJFQABAAYGAA==.Alamora:BAAALgAECgYJEwAAAA==.Alastair:BAAALgAECgcJCAAAAA==.Alathena:BAAALgAECgcJDAAAAA==.Albinoz:BAAALgADCgIJAgAAAA==.Albrect:BAAALgADCgYJEQAAAA==.Aldrich:BAAALgADCgEJAQAAAA==.Alexandrya:BAACLgAFFH8FAAIFAAIJ+galYwCLAAAFAAIJ+galYwCLAAAuAAQKfyoAAgUACAlDGNE2ANcBAAUACAlDGNE2ANcBAAAA.Alicemalkin:BAABLgAECn8XAAIGAAkJHxTyPQD8AQAGAAkJHxTyPQD8AQAAAA==.Alonai:BAAALgAECgYJBgAAAA==.Alphred:BAAALgADCgkJCgAAAA==.Alysse:BAAALgADCgUJBwAAAA==.',
Am='Amarysia:BAAALgAECgYJCQAAAA==.Ameriixs:BAAALgAECgIJAgAAAA==.Amháin:BAAALgAECggJCQAAAA==.Amsip:BAAALgAECgEJAQABLgAECggJIAAHADgOAA==.Amsroeb:BAABLgAECn8gAAIHAAgJOA6XIAAfAQAHAAgJOA6XIAAfAQAAAA==.',
An='Anelavenger:BAACLgAFFH8HAAIIAAMJpw6gMwDFAAAIAAMJpw6gMwDFAAAuAAQKfy0AAwgACQneHMwMAKkCAAgACQneHMwMAKkCAAkAAwlcAS1EAE0AAAAA.Angerwina:BAAALgADCgMJBAAAAA==.Anggar:BAAALgADCgIJAgAAAA==.',
Ao='Aomori:BAAALgAECgcJBwAAAA==.',
Aq='Aqüilés:BAAALgAECgEJAgAAAA==.',
Ar='Arathor:BAABLgAECn8kAAIKAAgJdBtjCAAiAgAKAAgJdBtjCAAiAgAAAA==.Arctorius:BAAALgADCgEJAQAAAA==.Arent:BAABLgAECn89AAILAAkJlxWaIQAYAgALAAkJlxWaIQAYAgAAAA==.Arfy:BAAALgADCgMJAgABLgAECggJEQAMAAAAAA==.Argil:BAAALgADCgEJAQABLgAECgYJIgANAPsQAA==.Argøn:BAABLgAECn82AAQFAAkJVBnQHABPAgAFAAkJVBnQHABPAgAOAAUJ2AgeOwC2AAAPAAEJkAYUkgAoAAAAAA==.Arkanna:BAAALgAECgEJAQAAAA==.Arrise:BAAALgAECgUJBgAAAA==.Artemislives:BAAALgAECgcJDQAAAA==.Arthuaca:BAAALgAECgYJDQAAAA==.',
As='Asharia:BAAALgAECgcJDwAAAA==.Ashog:BAAALgADCgYJCwAAAA==.Assateague:BAABLgAECn8VAAIQAAYJEQSNXQCuAAAQAAYJEQSNXQCuAAAAAA==.Astralie:BAAALgADCggJFAAAAA==.Asuya:BAAALgADCgYJCQAAAA==.',
At='Athylan:BAAALgADCgEJAQABLgAFFAUJFAAEACwcAA==.Atrosity:BAABLgAECn8tAAIRAAkJpiI0AwDpAgARAAkJpiI0AwDpAgAAAA==.',
Au='Aurorabane:BAAALgADCgYJDQAAAA==.',
Av='Avelleah:BAAALgAECgEJBAAAAA==.',
Az='Azulyne:BAAALgADCgIJAgAAAA==.Azuretorrent:BAAALgADCgQJBAAAAA==.',
Ba='Bambella:BAAALgADCgcJBwABLgADCgkJGgAMAAAAAA==.Bananapistol:BAAALgAECgUJBQAAAA==.Barracksbuny:BAAALgAECgEJAgABLgAECgQJBAAMAAAAAA==.Barrathfrogy:BAAALgADCgYJEgAAAA==.',
Be='Bebheishel:BAAALgADCgYJCwAAAA==.Bertelo:BAAALgADCgUJBQAAAA==.',
Bi='Bigstinky:BAAALgAECgYJCAABLgAECgkJNgAFAFQZAA==.Bisao:BAAALgAECgIJAgAAAA==.Biscuít:BAABLgAECn8pAAMSAAkJiA6nJAB3AQASAAkJiA6nJAB3AQATAAEJqAfmRAAmAAAAAA==.',
Bl='Blasuoff:BAAALgAECgQJBAAAAA==.Bloodrains:BAAALgAECgEJAwAAAA==.Bloodyfate:BAAALgADCgUJBQAAAA==.',
Bo='Bonesentinel:BAAALgAECgcJEQABLgAFFAUJDQAUAN0ZAA==.Bonës:BAAALgADCgEJAQAAAA==.Bora:BAAALgAECgQJDgAAAA==.Borzoi:BAABLgAFFH8OAAIVAAQJqx/1GQBrAQAVAAQJqx/1GQBrAQAAAA==.Bourgùîgnon:BAAALgADCgcJCgAAAA==.',
Br='Bragasch:BAAALgADCgkJGQAAAA==.Brakhon:BAAALgAECgEJAQAAAA==.Bruisebrews:BAAALgADCgEJAQAAAA==.',
Bu='Bullplop:BAAALgADCgUJBQAAAA==.Burekbazino:BAAALgADCgcJCQAAAA==.Burningsleet:BAAALgAECgYJBgABLgAFFAcJDwAUAAkZAA==.',
['Bò']='Bò:BAACLgAFFH8GAAISAAMJkQcfKAC6AAASAAMJkQcfKAC6AAAuAAQKfzEAAhIACQmpFw0QADkCABIACQmpFw0QADkCAAAA.',
Ca='Caduceus:BAAALgADCgcJGAAAAA==.Caesus:BAAALgAECgYJEwAAAA==.Cagedancer:BAABLgAECn8eAAMTAAcJFgkaHADuAAATAAcJwAcaHADuAAASAAYJyAaNUADmAAAAAA==.Callio:BAABLgAECn8vAAIFAAkJmxFoNgDZAQAFAAkJmxFoNgDZAQAAAA==.Cantor:BAAALgAECgEJAQAAAA==.Caradd:BAAALgADCgEJAQAAAA==.Catchclause:BAAALgADCgkJFAAAAA==.Cathillex:BAABLgAECn8XAAMQAAgJWhexHQDdAQAQAAgJWhexHQDdAQAWAAEJ1AKkbQAWAAAAAA==.Cavagos:BAACLgAFFH8GAAIXAAQJWAsBBAAfAQAXAAQJWAsBBAAfAQAuAAQKfzYAAhcACQlWIGIBAM0CABcACQlWIGIBAM0CAAAA.Caycay:BAACLgAFFH8VAAIYAAUJdCHVBAB+AQAYAAUJdCHVBAB+AQAuAAQKf0kAAhgACQkZJvEAAL4DABgACQkZJvEAAL4DAAAA.',
Ce='Celebrexi:BAAALgAECgcJBgAAAA==.Celene:BAAALgADCgYJBwAAAA==.Celtic:BAAALgADCgEJAQAAAA==.Cerrulli:BAAALgAECgYJDwAAAA==.',
Ch='Chaosknight:BAABLgAECn8WAAMDAAgJSRJVJgCLAQADAAgJSRJVJgCLAQACAAQJHgxfiwB9AAAAAA==.Chaostrip:BAABLgAECn8yAAIGAAkJJyMVBgATAwAGAAkJJyMVBgATAwABLgAFFAIJBgAGAHcUAA==.Cheddar:BAAALgAECgYJCAAAAA==.Chillbros:BAACLgAFFH8NAAIZAAUJWCGJBABIAQAZAAUJWCGJBABIAQAuAAQKfygAAxkACAmOJPkBADwDABkACAkQJPkBADwDAAMABAmqH+45AGcBAAAA.Chilldh:BAAALgAECgUJBQABLgAFFAUJDQAZAFghAA==.Chillmage:BAAALgADCgcJCgABLgAFFAUJDQAZAFghAA==.Chindi:BAABLgAECn8qAAMQAAkJKxaFGgD1AQAQAAkJKxaFGgD1AQARAAEJiwMURwAxAAAAAA==.Chindrakh:BAAALgAECggJEAABLgAECgkJKgAQACsWAA==.Choiminasue:BAAALgAECgEJAgAAAA==.Chunga:BAABLgAECn8UAAIDAAYJoAPZXADQAAADAAYJoAPZXADQAAAAAA==.Chungers:BAAALgAECgQJBgAAAA==.Churd:BAACLgAFFH8IAAIaAAMJ6Q4dHgDLAAAaAAMJ6Q4dHgDLAAAuAAQKfycAAhoACQnkGOoNAFMCABoACQnkGOoNAFMCAAAA.Churdicus:BAAALgADCgkJEQAAAA==.Chypnotic:BAAALgAECgcJCgAAAA==.Chypper:BAAALgADCgEJAQAAAA==.Chypster:BAABLgAECn8gAAIDAAYJvw1/RwDlAAADAAYJvw1/RwDlAAAAAA==.',
Ci='Ciceroe:BAAALgAFFAIJAwAAAA==.Citadel:BAAALgADCgIJAwAAAA==.',
Cl='Cleft:BAAALgAECgYJDwAAAA==.Clevelandk:BAAALgAECgEJAQAAAA==.',
Co='Coalystra:BAACLgAFFH8GAAIGAAMJ9hRYRwDjAAAGAAMJ9hRYRwDjAAAuAAQKfywAAgYACQnsGsMZAF0CAAYACQnsGsMZAF0CAAAA.Cocopuffs:BAACLgAFFH8HAAISAAIJsBG2FACfAAASAAIJsBG2FACfAAAuAAQKfzUAAhIACQleICMJAAMDABIACQleICMJAAMDAAAA.Colostrom:BAABLgAECn8vAAIKAAkJ1R8bBQB7AgAKAAkJ1R8bBQB7AgAAAA==.Complicatedz:BAAALgAECgUJBQAAAA==.Comul:BAAALgADCgcJBwAAAA==.Coramage:BAABLgAECn8XAAIBAAcJXAa2qgAPAQABAAcJXAa2qgAPAQAAAA==.Corentis:BAAALgADCgYJBgAAAA==.Corliss:BAABLgAECn8XAAIRAAgJkBTkEgCVAQARAAgJkBTkEgCVAQAAAA==.Cornholeo:BAAALgADCgkJCQAAAA==.',
Cp='Cplusmc:BAAALgAECgQJBwAAAA==.',
Cr='Creightizle:BAABLgAECn8eAAIFAAgJfRS/OQDHAQAFAAgJfRS/OQDHAQAAAA==.',
['Cá']='Cátix:BAAALgADCgIJAgAAAA==.',
Da='Daicmerollin:BAAALgAECgYJCwAAAA==.Danhaüsen:BAAALgAECgIJAwAAAA==.Darkbeast:BAAALgAFFAIJAgAAAA==.Darkdeeds:BAAALgADCggJEQAAAA==.Darkpallo:BAABLgAECn8YAAIVAAcJPxPWbwCdAQAVAAcJPxPWbwCdAQABLgAFFAIJAgAMAAAAAA==.Darthtav:BAAALgAECgcJEAABLgAFFAYJEAASADwUAA==.Daten:BAABLgAECn8+AAIVAAkJ/RJ1ZgCzAQAVAAkJ/RJ1ZgCzAQAAAA==.Dazshauran:BAAALgADCgEJAQAAAA==.Daîma:BAAALgADCggJCAAAAA==.',
Db='Dbltap:BAAALgADCgEJAQAAAA==.',
De='Deathbycow:BAABLgAECn8rAAINAAgJlhyVCAAqAgANAAgJlhyVCAAqAgAAAA==.Decayed:BAABLgAECn8YAAIHAAgJ3BQyFwB8AQAHAAgJ3BQyFwB8AQABLgAECgQJBAAMAAAAAA==.Deipally:BAAALgAECgYJBQAAAA==.Demonchalk:BAACLgAFFH8GAAIGAAUJ1xBpNAAgAQAGAAUJ1xBpNAAgAQAuAAQKfxUAAgYABglqIwIxAOIBAAYABglqIwIxAOIBAAEuAAUUBAkRABkAAyYA.Desdeynna:BAAALgADCgEJAQAAAA==.Deseral:BAAALgAECgIJAgAAAA==.Dewbie:BAAALgAECgEJAQAAAA==.',
Di='Diagonalli:BAABLgAECn8bAAIXAAcJQA+5CgBNAQAXAAcJQA+5CgBNAQAAAA==.Dimmadome:BAAALgADCgEJAQAAAA==.Dinojam:BAAALgADCgMJAQAAAA==.Divirian:BAAALgAECgYJDwAAAA==.',
Dj='Djdaemon:BAAALgADCgcJEgAAAA==.Djdrakshadow:BAAALgADCgYJDQAAAA==.Djpaly:BAAALgADCgYJEQAAAA==.Djpriest:BAAALgADCgcJFQAAAA==.Djshadow:BAAALgADCgcJEQAAAA==.Djshadowar:BAAALgADCggJFAAAAA==.Djshadowhunt:BAAALgAECgMJAQAAAA==.Djshadowlock:BAAALgADCgcJDQAAAA==.Djshadowrog:BAAALgADCgcJEgAAAA==.Djshamy:BAAALgADCgUJBwAAAA==.Djshaolin:BAAALgADCgYJFAAAAA==.Djzhadow:BAAALgADCggJFgAAAA==.Djzhadruid:BAAALgADCgYJDwAAAA==.',
Dk='Dkshadow:BAAALgADCgcJDwAAAA==.',
Dm='Dmitrì:BAAALgAECgEJAQAAAA==.',
Do='Dogno:BAAALgAECgEJAgAAAA==.Dontdieplez:BAAALgAECgkJDAAAAA==.',
Dp='Dpm:BAAALgAECgEJAgAAAA==.',
Dr='Dragbuttakis:BAAALgAECgUJCAAAAA==.Drakhadir:BAAALgAECgEJAQAAAA==.Drakmon:BAAALgAECgIJBAAAAA==.Draktând:BAABLgAECn8tAAIbAAgJLBgBEgDzAQAbAAgJLBgBEgDzAQAAAA==.Drippysilk:BAAALgAECgQJCAABLgAECgkJFgAVAB8ZAA==.Drius:BAAALgADCgMJAwAAAA==.Drunkenpanda:BAABLgAECn8hAAMcAAkJMBT7LwBpAQAcAAkJMBT7LwBpAQAdAAcJnQf4SgCsAAAAAA==.Drunknoodle:BAAALgAECgQJCAAAAA==.',
Du='Duhpriest:BAAALgAECgEJAQAAAA==.Duinrane:BAAALgAECgEJAQAAAA==.Duon:BAABLgAECn8WAAQdAAkJ3hTbGgCuAQAdAAgJexbbGgCuAQAcAAIJzwmCYQBJAAAeAAIJkgUfdwBAAAAAAA==.',
Dw='Dwagonfur:BAAALgAECgcJBgAAAA==.',
Ec='Echö:BAACLgAFFH8GAAIYAAMJLg3TEQDXAAAYAAMJLg3TEQDXAAAuAAQKfyEAAhgACAl5GV0NABkCABgACAl5GV0NABkCAAAA.',
Ei='Eiarinos:BAAALgADCgEJAQAAAA==.Eirø:BAAALgADCgkJCQABLgAFFAMJBgAFAO0fAA==.',
El='Elaine:BAAALgAECgkJDgAAAA==.Elberon:BAAALgAECgUJBwAAAA==.Ellspeth:BAAALgAECgkJCQAAAA==.Elmerhomero:BAAALgADCgUJBQAAAA==.Elronnd:BAAALgADCgkJGgAAAA==.Elsebeth:BAAALgADCgcJCAAAAA==.',
Em='Emilie:BAAALgADCgYJBgAAAA==.',
En='Enoch:BAABLgAECn8bAAIVAAYJkBZXfwB7AQAVAAYJkBZXfwB7AQAAAA==.',
Er='Eriam:BAAALgADCgIJAgABLgAECggJIQANACsZAA==.Errane:BAACLgAFFH8YAAILAAUJjyVDBwAtAgALAAUJjyVDBwAtAgAuAAQKfywAAwsACAnJJosEAEYDAAsACAnJJosEAEYDABIAAQnHFVJ4AEQAAAAA.Eruiluvatar:BAAALgAECgYJBgAAAA==.',
Et='Etalia:BAAALgAECgEJAQAAAA==.Etcetera:BAAALgAECgMJAwAAAA==.',
Ex='Exlibris:BAAALgADCgcJDAAAAA==.',
Fa='Fallenangell:BAAALgADCgUJBQAAAA==.Fandiirn:BAAALgADCgYJBgAAAA==.Fastjack:BAABLgAECn8hAAMfAAYJlxUjKABhAQAfAAYJlxUjKABhAQAaAAYJuAU3RQDOAAAAAA==.',
Fi='Fiora:BAAALgADCgYJCwAAAA==.Firbirl:BAAALgAECgIJAgAAAA==.Fistoffury:BAABLgAECn8YAAMeAAcJqBPlMAAhAQAeAAcJqBPlMAAhAQAdAAQJOAkEWgCoAAAAAA==.Fitco:BAAALgADCgYJCwABLgAECgYJDwAMAAAAAA==.Fiènd:BAAALgADCgYJBgAAAA==.',
Fl='Flametar:BAAALgAECgEJAQAAAA==.Floodlust:BAAALgADCgEJAQAAAA==.Floppydisk:BAAALgAECgUJCwAAAA==.',
Fo='Fortiss:BAACLgAFFH8HAAICAAMJ/hZ1MADrAAACAAMJ/hZ1MADrAAAuAAQKfysAAwIACQnWGyYKAOoCAAIACQnWGyYKAOoCAAMABgk/EERFAO8AAAAA.',
Fr='Freelo:BAAALgAECgQJBAAAAA==.Frito:BAAALgAECggJCQAAAA==.Frost:BAAALgAFFAIJAgABLgAFFAcJIwAOAKkVAA==.Frostmon:BAAALgAECgkJEgAAAA==.Frshnvrfrzn:BAAALgAECggJDwAAAA==.Frøzenblight:BAAALgAECgEJAQAAAA==.',
Fu='Fulmo:BAAALgADCgUJBQABLgAECgkJGwAUAKwOAA==.Furbee:BAAALgAECggJEQAAAA==.',
['Fá']='Fáde:BAAALgADCgQJBQABLgAECgMJAwAMAAAAAA==.',
Ga='Gabris:BAAALgADCgYJBgAAAA==.Galeandra:BAABLgAECn8VAAIaAAYJ3gQbRwDFAAAaAAYJ3gQbRwDFAAAAAA==.Garim:BAAALgADCgMJBAABLgAECgYJIQAfAJcVAA==.',
Ge='Geraltofrvia:BAAALgAECgcJDAAAAA==.',
Gg='Gg:BAAALgAFFAEJAgABLgAFFAcJHQAgAGMlAA==.',
Gi='Giantgoose:BAAALgAECgEJAgAAAA==.Gingani:BAAALgADCgcJCQAAAA==.',
Gn='Gnar:BAABLgAECn8eAAIUAAYJFxHXkAAeAQAUAAYJFxHXkAAeAQAAAA==.',
Go='Gowtherdead:BAAALgADCgQJBAAAAA==.Gowtherpunch:BAACLgAFFH8GAAIeAAMJXAXVNACvAAAeAAMJXAXVNACvAAAuAAQKfzEAAh4ACQm5FTQTAPoBAB4ACQm5FTQTAPoBAAAA.',
Gr='Gregzug:BAAALgAECgMJAwAAAA==.Greyjoy:BAAALgADCgYJBQAAAA==.Grimfury:BAAALgAFFAIJBAAAAA==.Grimsy:BAAALgADCgYJBwAAAA==.Grodd:BAAALgADCgUJBQAAAA==.Groqqu:BAAALgAECgQJBAAAAA==.Grumble:BAAALgAECgYJCAAAAA==.Gruxxiron:BAAALgAECgUJBwABLgAECgkJOwAUAIIfAA==.',
Gu='Gulnn:BAABLgAECn8sAAMhAAkJ0RsUGwBnAgAhAAkJ0RsUGwBnAgAiAAIJVhT8VABvAAAAAA==.Gumby:BAAALgADCgYJBgAAAA==.',
Ha='Haelena:BAABLgAECn8ZAAIEAAgJpAlAOgA3AQAEAAgJpAlAOgA3AQAAAA==.Halys:BAAALgADCgUJBQAAAA==.Hamil:BAAALgADCgEJAQAAAA==.Harmoss:BAAALgAECgcJBwAAAA==.Hawk:BAAALgADCgYJBgAAAA==.',
He='Heartsfang:BAAALgADCgUJCAAAAA==.Helfire:BAAALgADCgYJBgABLgAECgMJAwAMAAAAAA==.Hellscreems:BAAALgADCgMJAwAAAA==.Heriotza:BAABLgAECn8bAAIUAAkJrA6VZgB1AQAUAAkJrA6VZgB1AQAAAA==.',
Ia='Iamfubar:BAAALgADCgMJBAAAAA==.',
Ig='Igris:BAAALgAECgcJCgAAAA==.',
Ii='Iimit:BAACLgAFFH8FAAIbAAMJvBYGHAD/AAAbAAMJvBYGHAD/AAAuAAQKfyEAAhsACAmUG7cQAAECABsACAmUG7cQAAECAAAA.',
Il='Illidead:BAACLgAFFH8YAAIBAAYJ6ByyHgCoAQABAAYJ6ByyHgCoAQAuAAQKfyEAAwEACAkLJCs7AIoCAAEACAnJICs7AIoCACMAAQnXHxgXAGEAAAAA.Iluni:BAAALgADCgMJAwAAAA==.',
Im='Implied:BAAALgADCgUJBQAAAA==.',
In='Indexes:BAABLgAECn8UAAMSAAYJkAl6RQDEAAASAAYJlwh6RQDEAAANAAUJGgZRPgBiAAAAAA==.Insrik:BAAALgAECgYJCQAAAA==.Insurance:BAAALgAECggJCAABLgAFFAIJBQAFAPoGAA==.',
Io='Iompróirbáis:BAABLgAECn8bAAIUAAkJ8QbUbwBfAQAUAAkJ8QbUbwBfAQAAAA==.',
Ir='Irdeadohnoz:BAABLgAECn8aAAIBAAcJTAxXmgAqAQABAAcJTAxXmgAqAQAAAA==.',
Is='Ist:BAAALgAECgMJAwAAAA==.',
It='Itchigo:BAABLgAECn8UAAIFAAgJ1A31TgCIAQAFAAgJ1A31TgCIAQAAAA==.',
Iv='Ivern:BAAALgAECgIJAgAAAA==.Ivgorod:BAABLgAECn8hAAMXAAgJVwlNCwBBAQAXAAgJFQlNCwBBAQAIAAgJBAZpPQANAQAAAA==.',
Ja='Jabbadahut:BAAALgAECgcJBQAAAA==.Jambi:BAAALgAECgYJDgAAAA==.Jardani:BAAALgAECgEJAQAAAA==.Jastrae:BAAALgAECgcJDgAAAA==.Jazilyne:BAAALgADCgkJGgAAAA==.',
Je='Jealous:BAAALgADCgUJBQABLgAECgkJIgAGAJ0dAA==.Jenka:BAAALgAECgUJCgAAAA==.',
Ji='Jibbs:BAAALgADCgkJCQAAAA==.',
Jo='Joleya:BAAALgADCgEJAQAAAA==.',
Ju='Junta:BAAALgADCgcJJQAAAA==.Justine:BAAALgADCgUJBQAAAA==.Justtrolling:BAAALgAECgYJDgAAAA==.',
['Jä']='Jäkel:BAAALgADCgUJBQAAAA==.',
Ka='Kalike:BAAALgADCgcJBwAAAA==.Kambative:BAABLgAECn8UAAMLAAcJqxIPQgCZAQALAAcJqxIPQgCZAQASAAIJRxGuXwBlAAABLgAFFAMJBQAJACkKAA==.Kammunion:BAAALgAECgYJBgABLgAFFAMJBQAJACkKAA==.Kamphiyer:BAACLgAFFH8FAAMJAAMJKQrNGgC3AAAJAAMJKQrNGgC3AAAIAAIJtwMSSABnAAAuAAQKfzoABAkACQnqGIYIAEQCAAkACQnqGIYIAEQCAAgACAmIHdcQAD8CABcABAmjDMExAIgAAAAA.Kamsumerage:BAAALgADCgkJEgABLgAFFAMJBQAJACkKAA==.Kandosii:BAAALgADCgUJBQAAAA==.Kantheal:BAABLgAECn8hAAIEAAgJlx4WDACoAgAEAAgJlx4WDACoAgAAAA==.Kaulana:BAAALgADCgcJDAAAAA==.',
Ke='Keirmania:BAAALgAECgEJAQAAAA==.Kekkan:BAAALgADCgcJCgAAAA==.Kellendere:BAAALgAECgYJBgAAAA==.',
Ki='Kiieedk:BAAALgAECgEJAQAAAA==.Kimgoeun:BAAALgADCgYJBgAAAA==.Kio:BAAALgAECgYJCAAAAA==.',
Kl='Klompus:BAAALgADCgQJBAAAAA==.',
Kn='Knùsê:BAAALgADCgUJBgABLgAFFAMJBgAFAO0fAA==.',
Ko='Komorai:BAAALgADCgYJBgAAAA==.',
Kr='Kravex:BAABLgAECn8hAAINAAgJKxl3CwDxAQANAAgJKxl3CwDxAQAAAA==.Krixxa:BAABLgAECn8oAAIfAAkJWCQwAgBtAwAfAAkJWCQwAgBtAwAAAA==.',
Ku='Kuula:BAAALgADCgUJBQAAAA==.',
Ky='Kylana:BAAALgADCgQJBAAAAA==.',
['Kä']='Kären:BAAALgAECgUJEgAAAA==.',
['Ké']='Kélly:BAAALgAECggJCAAAAA==.',
La='Laochnaofa:BAAALgAECgcJDQAAAA==.Larayvia:BAACLgAFFH8FAAIFAAIJqgLoZwB9AAAFAAIJqgLoZwB9AAAuAAQKfx0AAgUACAkrDkc7AMEBAAUACAkrDkc7AMEBAAAA.Laurance:BAAALgADCgYJBgAAAA==.',
Le='Leesala:BAABLgAECn8wAAMCAAkJqRfWGABWAgACAAkJqRfWGABWAgAZAAEJ/gTHMgAnAAAAAA==.Lerazer:BAAALgAECgYJCgAAAA==.',
Lg='Lgidk:BAAALgADCgMJAwABLgAECgkJIgAGAJ0dAA==.',
Li='Lic:BAAALgAECgQJBgAAAA==.Liea:BAAALgAECgMJAgAAAA==.Liliatrix:BAAALgAECgQJBQAAAA==.Lillabet:BAAALgAECgYJEAAAAA==.Lilmatty:BAAALgAECgkJDQABLgAFFAQJCAAcAHAcAA==.Lilsneaky:BAAALgADCggJCAAAAA==.Limpydk:BAAALgADCgUJBQABLgAECgkJFgAVAB8ZAA==.Limpylarva:BAAALgADCgMJAwABLgAECgkJFgAVAB8ZAA==.Limpypal:BAABLgAECn8WAAMVAAkJHxmLLQAoAgAVAAgJ6xuLLQAoAgAKAAIJZARYPABGAAAAAA==.Litter:BAAALgAECgUJBQAAAA==.',
Lo='Logathil:BAAALgAECgYJEAAAAA==.',
Lu='Luchulainn:BAAALgADCgYJBgAAAA==.Lucifero:BAAALgAECggJCgAAAA==.Lucifurwild:BAAALgADCgQJBQAAAA==.Lunaaris:BAABLgAECn8rAAILAAkJBR/3DADWAgALAAkJBR/3DADWAgAAAA==.Lunastre:BAAALgADCgEJAQAAAA==.',
['Lí']='Límpy:BAABLgAECn8aAAIXAAYJ/CJ/CgA0AgAXAAYJ/CJ/CgA0AgABLgAECgkJFgAVAB8ZAA==.Línk:BAAALgAECgYJCgAAAA==.',
['Lî']='Lîkwuid:BAAALgAECggJDwAAAA==.',
Ma='Macallan:BAAALgAECgIJBAAAAA==.Maddrox:BAAALgADCgcJFwAAAA==.Magicmarv:BAAALgADCgIJAQAAAA==.Magnagoth:BAAALgADCgkJDwAAAA==.Magnakilro:BAABLgAECn8dAAIFAAgJDxbIRACnAQAFAAgJDxbIRACnAQAAAA==.Mahnaz:BAAALgADCgEJAQABLgADCgcJCgAMAAAAAA==.Malanath:BAABLgAECn8XAAIIAAgJtBWUIgCkAQAIAAgJtBWUIgCkAQAAAA==.Malditto:BAAALgADCgYJBgAAAA==.Malothas:BAAALgADCgQJBAAAAA==.Mareki:BAAALgADCgYJBwAAAA==.Markdfordeth:BAAALgAECgEJAQAAAA==.Mattingly:BAAALgAECgQJBQAAAA==.Mattyfu:BAACLgAFFH8IAAIcAAQJcByzFABiAQAcAAQJcByzFABiAQAuAAQKfxUAAx0ACAmWFyQdAPEBAB0ACAmWFyQdAPEBABwAAwnJH7ZAABEBAAAA.Mavíel:BAAALgAECgYJDQAAAA==.Maxrogue:BAAALgAECgYJCgABLgAECgYJIgANAPsQAA==.Mazikeen:BAAALgAECgUJBgAAAA==.',
Mc='Mcscoots:BAAALgADCgcJEgAAAA==.',
Me='Meatsupreme:BAABLgAECn8nAAIVAAkJrBDUSgDHAQAVAAkJrBDUSgDHAQAAAA==.Meepin:BAACLgAFFH8UAAIEAAUJLBykCgDFAQAEAAUJLBykCgDFAQAuAAQKfzMAAwQACQnWJAQFABwDAAQACAmmJQQFABwDABUAAwk/Cvj/AIgAAAAA.Meepmorp:BAAALgADCgYJCQAAAA==.Meifeng:BAAALgADCgEJAQAAAA==.Mephala:BAAALgADCgYJBgAAAA==.Mesophistole:BAAALgADCggJCwABLgAECgYJFgAiAJsFAA==.Mesopunchy:BAAALgADCgcJAgABLgAECgYJFgAiAJsFAA==.Mesopyro:BAABLgAECn8WAAIiAAYJmwXuGwCmAAAiAAYJmwXuGwCmAAAAAA==.',
Mi='Mileenä:BAAALgAECgkJDwAAAA==.Minimim:BAAALgADCgMJAwAAAA==.Mistyra:BAAALgAECgkJDwABLgAECgkJKAAfAFgkAA==.Mià:BAAALgADCgEJAQAAAA==.',
Mo='Mod:BAABLgAECn8UAAINAAcJghXbFgBbAQANAAcJghXbFgBbAQAAAA==.Mograiné:BAAALgAECgQJCQAAAA==.Mojodaemon:BAAALgADCgcJCgAAAA==.Mojoy:BAAALgAECgEJAQAAAA==.Monkaw:BAAALgAECgIJAgAAAA==.Monkchalk:BAAALgAECgQJBAABLgAFFAQJEQAZAAMmAA==.Moondevil:BAAALgADCgYJBwAAAA==.Morta:BAEALgAFFAIJAgAAAA==.Mortkavaliro:BAAALgAECgYJDQAAAA==.',
Ms='Mslockness:BAAALgADCgYJEAAAAA==.',
Mu='Mugzy:BAAALgAECgkJBwAAAA==.Multipass:BAABLgAECn8ZAAILAAgJjyBcEACvAgALAAgJjyBcEACvAgAAAA==.Multitool:BAAALgADCgEJAQAAAA==.',
['Mö']='Mörph:BAAALgAECgIJAgAAAA==.',
Na='Nadris:BAAALgADCgcJBwAAAA==.Nanérs:BAAALgAECgcJEQABLgAFFAYJEAASADwUAA==.Narrodus:BAABLgAECn8hAAIkAAgJASUWAgDKAgAkAAgJASUWAgDKAgAAAA==.Nasht:BAABLgAECn8VAAIBAAYJUBYmlwAvAQABAAYJUBYmlwAvAQAAAA==.Nashty:BAAALgADCgYJBgABLgAECgYJFQABAFAWAA==.Nashxi:BAAALgADCgkJEAABLgAECgYJFQABAFAWAA==.Nasu:BAAALgAECgcJAQAAAA==.Nattymoo:BAAALgAECgYJCQABLgAFFAQJCAAcAHAcAA==.',
Ne='Necrô:BAAALgADCgIJAgAAAA==.Nephi:BAAALgAECgEJAQAAAA==.',
Ni='Nightraven:BAAALgADCgkJEAAAAA==.Nightreaper:BAAALgADCgkJGwAAAA==.Nimbus:BAACLgAFFH8WAAIDAAUJ3BqpEQBQAQADAAUJ3BqpEQBQAQAuAAQKf2cAAgMACQmVJYoBAFcDAAMACQmVJYoBAFcDAAEuAAUUCAkWAAgATBYA.Nimike:BAAALgAECgcJDQAAAA==.',
No='Normul:BAAALgAECgcJAwABLgAFFAMJBgAlAKkRAA==.Noshoba:BAAALgAECgEJAQAAAA==.',
Nr='Nrvous:BAAALgADCgkJCQAAAA==.',
Nu='Nugzuul:BAAALgAECgEJAQAAAA==.Nuid:BAAALgAECgkJBgAAAA==.Numbers:BAABLgAECn8UAAMYAAYJHA+0KgDtAAAYAAYJCQ60KgDtAAAGAAYJnApFkADWAAAAAA==.',
Ny='Nyterage:BAAALgAECgIJAgAAAA==.Nytesage:BAACLgAFFH8gAAIgAAYJvSUeAAAwAgAgAAYJvSUeAAAwAgAuAAQKfygAAiAACAkMJj8AAH4DACAACAkMJj8AAH4DAAAA.',
['Nä']='Näners:BAAALgAFFAEJAQABLgAFFAYJEAASADwUAA==.',
['Nì']='Nìghtcat:BAAALgAECgQJBQAAAA==.',
Oo='Ookle:BAABLgAECn8lAAMTAAkJRAgsEgBeAQATAAkJRAgsEgBeAQALAAcJ0wr4YADyAAAAAA==.',
Or='Orchard:BAAALgAFFAQJBAAAAA==.Oresh:BAABLgAECn8jAAIQAAcJ3BFCMgBcAQAQAAcJ3BFCMgBcAQAAAA==.Orgrom:BAAALgAECgkJBwAAAA==.Oryz:BAAALgADCgkJCAAAAA==.',
Os='Osajak:BAAALgADCgIJAgAAAA==.',
Oz='Ozo:BAABLgAECn8ZAAIhAAYJLQzYkQACAQAhAAYJLQzYkQACAQAAAA==.',
Pa='Painavolian:BAABLgAECn9FAAIBAAkJHB9DFwCzAgABAAkJHB9DFwCzAgAAAA==.Palifur:BAAALgAECgkJDwAAAA==.Pandamonium:BAAALgAECgcJEgAAAA==.Panes:BAAALgAECgcJCwAAAA==.Paopu:BAAALgADCgYJBgABLgAECgkJIAAhAPYfAA==.',
Pe='Peeches:BAAALgAECgYJCwAAAA==.Pelonis:BAAALgADCgcJAgAAAA==.Pelor:BAAALgAECgcJCgAAAA==.',
Ph='Pheayre:BAAALgADCgkJDAABLgAECgcJDAAMAAAAAA==.',
Pi='Pisspadpanda:BAACLgAFFH8LAAMhAAQJSRRGWwDhAAAhAAMJNRJGWwDhAAAmAAEJhBokGABNAAAuAAQKfykAAiEACQltIn8RAKkCACEACQltIn8RAKkCAAAA.',
Pl='Plsbnice:BAAALgAECgYJCAABLgAECgkJIgAGAJ0dAA==.',
Po='Poggies:BAACLgAFFH8dAAMgAAcJYyUQAACJAgAgAAcJYyUQAACJAgAjAAEJ3ggYAwBVAAAuAAQKfyEAAyAACAk9JjkAAIIDACAACAk9JjkAAIIDACMAAQkOIP8WAGIAAAAA.Ponmonk:BAAALgAECgEJAQABLgAECgYJFQAaALcfAA==.Pontacos:BAABLgAECn8VAAIaAAYJtx/AIADTAQAaAAYJtx/AIADTAQAAAA==.Porkinator:BAAALgADCgYJCAAAAA==.Powdur:BAAALgADCgEJAQABLgAFFAMJDQAOAMIZAA==.Pozh:BAABLgAECn8UAAIhAAYJlA0HkQA3AQAhAAYJlA0HkQA3AQAAAA==.',
Pr='Praynes:BAACLgAFFH8GAAIfAAMJGQ6NGQC9AAAfAAMJGQ6NGQC9AAAuAAQKfzEAAh8ACQnoGMkSAEoCAB8ACQnoGMkSAEoCAAAA.Precedence:BAAALgADCgEJAQABLgAECgEJAQAMAAAAAA==.Prestocreamÿ:BAAALgADCgEJAQAAAA==.',
Pu='Pummel:BAAALgAECgYJCwAAAA==.Pupperputh:BAAALgADCgkJEgABLgAECgkJIgAGAJ0dAA==.Puppet:BAAALgAECgEJAwAAAA==.',
['Pä']='Päroxysm:BAAALgAECgEJAgABLgAECgYJBgAMAAAAAA==.',
Ra='Rach:BAAALgADCgEJAQAAAA==.Randyrando:BAAALgADCgIJBAAAAA==.Ranoe:BAABLgAECn8iAAIGAAcJCRbzVAClAQAGAAcJCRbzVAClAQAAAA==.Rastrin:BAAALgADCgcJDgAAAA==.Ravyniel:BAAALgADCgEJAQAAAA==.Razji:BAABLgAECn89AAQOAAkJ7iNXAwDuAgAOAAkJ4iJXAwDuAgAPAAcJsSENGABtAgAFAAIJiSbQgQDjAAAAAA==.',
Re='Redrrum:BAAALgAECgcJCgAAAA==.Rekd:BAAALgADCgEJAQAAAA==.Reladiia:BAAALgADCgcJBwAAAA==.Renfro:BAAALgADCgcJBwAAAA==.Restokhan:BAAALgAECgQJBAAAAA==.Revoked:BAAALgADCgEJAQABLgAECgYJDwAMAAAAAA==.Reznick:BAABLgAECn8ZAAIQAAgJ6g5ELwBrAQAQAAgJ6g5ELwBrAQAAAA==.',
Ro='Rocknwolf:BAAALgAECgEJAQAAAA==.Rokd:BAAALgAECgcJDQAAAA==.Rokham:BAAALgADCgEJAQAAAA==.Rosalee:BAAALgADCgEJAQAAAA==.Rovërgalarga:BAAALgADCgMJAwAAAA==.',
Ru='Rudeboy:BAAALgAECgEJAQAAAA==.Ruibaron:BAAALgAECgYJDwAAAA==.',
Ry='Ryhunter:BAAALgADCggJDgAAAA==.',
['Rà']='Ràidèn:BAABLgAECn8rAAIUAAkJfB6OIgBaAgAUAAkJfB6OIgBaAgAAAA==.',
['Rá']='Ráyne:BAAALgAECgUJCgAAAA==.',
Sa='Sadeel:BAABLgAECn8sAAMmAAkJVhopCQCdAQAhAAkJdBKmRQD6AQAmAAcJKB0pCQCdAQAAAA==.Sadewolf:BAABLgAECn8nAAIGAAgJ7x0OIQAxAgAGAAgJ7x0OIQAxAgAAAA==.Sadpanduh:BAAALgAECgYJBgAAAA==.Saltednuts:BAAALgAECgEJAQAAAA==.Samentoni:BAABLgAECn8oAAIEAAkJYxtvDACkAgAEAAkJYxtvDACkAgAAAA==.Samgal:BAABLgAECn8aAAIiAAgJDRj2BQDXAQAiAAgJDRj2BQDXAQAAAA==.Sardothien:BAAALgAECgEJAgAAAA==.Satyra:BAAALgAECgcJEgABLgAECgkJKAAfAFgkAA==.Saurphang:BAACLgAFFH8ZAAMUAAUJohEeGABFAQAUAAQJohEeGABFAQAHAAEJAAD8TAAAAAAuAAQKfyoAAhQACAkLIxIVAP0CABQACAkLIxIVAP0CAAAA.Saye:BAAALgADCgIJAgAAAA==.',
Sc='Scarletpanda:BAAALgADCgQJBgAAAA==.Scourgereap:BAAALgAECgMJAwAAAA==.',
Se='Selinna:BAAALgAECggJEgAAAA==.Senpaichill:BAAALgAECgYJDQAAAA==.Severis:BAAALgADCgIJAgAAAA==.',
Sh='Shadiepope:BAAALgAECgIJAwAAAA==.Shadora:BAABLgAECn8gAAIaAAkJLBNbFwDpAQAaAAkJLBNbFwDpAQAAAA==.Shadowwizard:BAAALgAECgMJAwAAAA==.Shadybrat:BAAALgAECgYJDQABLgAFFAIJBQAFAPoGAA==.Shaggylol:BAAALgADCgcJDQAAAA==.Shaladin:BAAALgAECgcJBgAAAA==.Shamlazy:BAAALgADCgkJHQAAAA==.Shidan:BAAALgAECggJEAABLgAECgkJKwAUAHweAA==.Shiroku:BAAALgAECgkJBgAAAA==.Shockchalk:BAACLgAFFH8RAAIZAAQJAybVAQCaAQAZAAQJAybVAQCaAQAuAAQKfzEAAxkACQnhJf0AACUDABkACQnhJf0AACUDAAMAAglhEYhsAGoAAAAA.Shocknorris:BAAALgAECgQJBwABLgAECgYJDwAMAAAAAA==.Shrooclaw:BAACLgAFFH8GAAILAAIJmQpOSAB5AAALAAIJmQpOSAB5AAAuAAQKfx4AAwsACQnYE0EtAM8BAAsACQnYE0EtAM8BABMAAgkGHQ4zAFUAAAAA.',
Si='Sibbiah:BAAALgAECggJCAAAAA==.Silanre:BAABLgAECn8lAAIBAAcJcRZjYwCbAQABAAcJcRZjYwCbAQAAAA==.',
Sk='Skaðï:BAACLgAFFH8GAAIFAAMJ7R8FMQAeAQAFAAMJ7R8FMQAeAQAuAAQKfzQABA8ACQkOI/cCAIsCAA8ACAnQI/cCAIsCAA4ABAnvGX0nAEEBAAUAAwnpHjqwAKUAAAAA.',
Sm='Smolshrapnel:BAABLgAECn8WAAIOAAcJ0AR4LQAVAQAOAAcJ0AR4LQAVAQAAAA==.',
Sn='Sneakchalk:BAAALgADCgcJCwABLgAFFAQJEQAZAAMmAA==.',
So='Solaraze:BAABLgAECn8qAAQVAAkJXh3HKwAwAgAVAAgJCR7HKwAwAgAEAAIJdBAWZABxAAAKAAEJLQZ+SAAiAAAAAA==.Solinarie:BAAALgADCggJCgAAAA==.Sorefang:BAAALgADCgEJAQAAAA==.Sorrowfang:BAAALgAECgEJAQAAAA==.Sovnightwar:BAAALgAECggJCwABLgAFFAQJCAAGALsbAA==.Soza:BAAALgADCgEJAQAAAA==.',
Sp='Spacespecial:BAAALgAECggJEwAAAA==.Sparklebunny:BAAALgADCgEJAQAAAA==.Spicycurryy:BAABLgAECn83AAQFAAkJMh8/GgBqAgAFAAgJeCA/GgBqAgAOAAcJnRTDHQCQAQAPAAIJJAzGeABeAAABLgAECgkJNwAFADIfAA==.Spicyycurryy:BAAALgAECgUJCAABLgAECgkJNwAFADIfAA==.Spiker:BAAALgAECgEJAQAAAA==.Splittail:BAAALgAECgQJBAAAAA==.',
St='Staggertrip:BAAALgADCgQJBAABLgAFFAIJBgAGAHcUAA==.Strahm:BAABLgAECn8iAAINAAYJ+xAAIwDzAAANAAYJ+xAAIwDzAAAAAA==.Strehm:BAAALgAECgQJBAABLgAECgYJIgANAPsQAA==.Strohmjr:BAAALgADCgMJBAABLgAECgYJIgANAPsQAA==.Strohmy:BAAALgADCgEJAQABLgAECgYJIgANAPsQAA==.Stryhm:BAAALgAECgQJBQABLgAECgYJIgANAPsQAA==.',
Su='Sunju:BAAALgADCgMJAwAAAA==.',
Sy='Syssare:BAABLgAECn8dAAIYAAgJ+iJqBwCQAgAYAAgJ+iJqBwCQAgAAAA==.',
['Sé']='Sétt:BAAALgAECgUJBQAAAA==.',
Ta='Tabbie:BAAALgADCgYJCQAAAA==.Tacpally:BAAALgADCgMJAwAAAA==.Talasam:BAAALgAECgcJDwAAAA==.Talien:BAAALgADCgEJAQAAAA==.Tandsonnara:BAAALgAECgkJDAAAAA==.Tastetickle:BAACLgAFFH8GAAIBAAMJGw70ZwDmAAABAAMJGw70ZwDmAAAuAAQKfzUAAgEACQkvH7AXALECAAEACQkvH7AXALECAAAA.Tazdrin:BAACLgAFFH8GAAInAAMJzAWyBwDEAAAnAAMJzAWyBwDEAAAuAAQKfzIAAicACQkmF2cEABQCACcACQkmF2cEABQCAAAA.',
Te='Telidrus:BAACLgAFFH8VAAIBAAYJAxiDIAChAQABAAYJAxiDIAChAQAuAAQKfywABAEACAn7IGkxAK0CAAEABwlBJGkxAK0CACMABAnMHWMFAFcBACAAAglcEwEOADwAAAAA.Temok:BAAALgADCggJCAAAAA==.Teyrlis:BAAALgAECgUJCAAAAA==.',
Th='Thavryn:BAAALgADCgYJBgAAAA==.Thaz:BAAALgAECgQJBwAAAA==.Thias:BAABLgAECn8cAAIBAAgJQhNCYACjAQABAAgJQhNCYACjAQAAAA==.Thukmonk:BAAALgAECgQJBwAAAA==.Thukwarlock:BAABLgAECn8hAAIhAAcJ7xgoSQDuAQAhAAcJ7xgoSQDuAQAAAA==.Thunderbug:BAAALgADCgEJAQAAAA==.',
To='Todd:BAAALgAECgEJAQAAAA==.Tokain:BAAALgADCgkJEQAAAA==.Topaze:BAAALgAECgUJCAAAAA==.Torironheart:BAAALgADCgcJBwAAAA==.',
Tr='Trance:BAAALgAECgEJAQABLgAECgEJAQAMAAAAAA==.Treehuggera:BAAALgAECgYJCgAAAA==.Tribunal:BAAALgAECgEJAQAAAA==.Trilila:BAAALgADCgYJBgAAAA==.Tripx:BAABLgAECn8WAAMVAAgJQh7+IQBeAgAVAAgJQh7+IQBeAgAKAAEJ2A8CRgAoAAABLgAFFAIJBgAGAHcUAA==.Tronko:BAABLgAECn8lAAMCAAkJHBzcEACeAgACAAkJHBzcEACeAgADAAEJ8BM5hQA1AAAAAA==.Trumpinator:BAAALgADCgYJDAAAAA==.',
Ts='Tsireya:BAAALgAECgUJCgABLgAECgQJDgAMAAAAAA==.',
Tu='Tullip:BAAALgAECgEJAQAAAA==.Turntsnaco:BAACLgAFFH8HAAIbAAIJJBgBJQCkAAAbAAIJJBgBJQCkAAAuAAQKfz0AAxsACAnnIRoJAHACABsACAnnIRoJAHACACgAAQleFScfAEIAAAAA.Tusk:BAAALgAECgcJEQAAAA==.',
Tw='Twigger:BAAALgADCgEJAgAAAA==.Twiztedsoul:BAAALgAECgMJAwAAAA==.Twophorb:BAAALgADCgMJAwAAAA==.',
Ua='Uake:BAAALgADCgYJBgAAAA==.',
Ud='Udgar:BAAALgAECgkJEQAAAA==.',
Un='Unafhaen:BAAALgADCgEJAQAAAA==.Unaverse:BAAALgAECgEJAQAAAA==.',
Us='Usmc:BAAALgADCgYJBgAAAA==.Usmccpl:BAAALgAECgUJDQAAAA==.Usmcsemperfi:BAAALgADCgYJDAAAAA==.',
Va='Valengarde:BAABLgAECn8ZAAIVAAgJqBR7YQCOAQAVAAgJqBR7YQCOAQAAAA==.Vanette:BAAALgAECgIJAgAAAA==.Vannix:BAACLgAFFH8HAAIaAAMJFCKGEwAvAQAaAAMJFCKGEwAvAQAuAAQKfzcAAhoACQmSIyoDAB4DABoACQmSIyoDAB4DAAAA.Vanz:BAAALgADCgIJAgAAAA==.Varnos:BAAALgAECgEJAwAAAA==.',
Ve='Velranis:BAAALgADCgMJAwABLgAECgkJFAAeABoWAA==.Velthas:BAAALgADCggJIQAAAA==.',
Vi='Viollet:BAAALgAECgEJAQAAAA==.Virmethir:BAABLgAECn8ZAAMXAAYJ8gvIEADaAAAXAAYJ+QnIEADaAAAIAAYJVgaLUQC9AAAAAA==.Viruz:BAAALgADCgcJCgAAAA==.',
Vo='Volley:BAAALgADCgEJAQAAAA==.Voltaren:BAAALgAECgcJCAABLgAECgkJKgAVAF4dAA==.',
Vy='Vylaran:BAAALgADCgYJBgAAAA==.Vyndrolan:BAAALgAFFAEJAQAAAA==.Vyroth:BAAALgADCgUJBQAAAA==.',
Wa='Walksonwater:BAAALgADCgEJAQABLgAECggJIQAEAJceAA==.Waq:BAAALgAECgcJDwAAAA==.',
We='Wellamor:BAAALgADCgIJAgAAAA==.',
Wi='Winterbreeze:BAAALgADCgYJBgAAAA==.Wiwi:BAACLgAFFH8GAAMlAAMJqRF9DADmAAAlAAMJqRF9DADmAAAUAAEJcAWJ1QBDAAAuAAQKfzIAAxQACQnGISAPANQCABQACQnGISAPANQCACUAAwm8GwUXANMAAAAA.',
Xa='Xares:BAABLgAECn8xAAIBAAkJrBu/HgCKAgABAAkJrBu/HgCKAgAAAA==.Xash:BAAALgAECgEJAQAAAA==.',
Xe='Xerath:BAAALgADCgcJBwAAAA==.',
Xh='Xhades:BAAALgAECgYJDQAAAA==.',
Ya='Yalda:BAAALgAECgUJDwAAAA==.',
Yf='Yfra:BAAALgAECggJEQAAAA==.',
Yo='Yochangsvegn:BAAALgAECggJEAAAAA==.Yoseph:BAABLgAECn8XAAITAAgJjQ/gEgBUAQATAAgJjQ/gEgBUAQAAAA==.',
Yu='Yungblood:BAAALgAECgUJBwAAAA==.Yurimancer:BAABLgAECn8vAAIaAAgJQBqsEwAOAgAaAAgJQBqsEwAOAgAAAA==.',
Za='Zaen:BAAALgADCgMJAwAAAA==.Zake:BAAALgAECgMJBAAAAA==.Zalileina:BAAALgADCgMJAwAAAA==.Zallith:BAAALgADCgMJAwABLgAECgYJDgAMAAAAAA==.Zappythile:BAABLgAECn8sAAICAAkJfxsVHAA9AgACAAkJfxsVHAA9AgAAAA==.Zarkamental:BAAALgADCgYJCwABLgAFFAMJBQAGAEcCAA==.Zarthos:BAAALgAECgEJAQABLgAECgEJAwAMAAAAAA==.',
Ze='Zect:BAABLgAECn8YAAQmAAYJLB6tCgB+AQAmAAYJOButCgB+AQAhAAUJZRkCkwAAAQAiAAEJFBWsbwA3AAAAAA==.Zelinor:BAAALgADCgcJBwAAAA==.',
Zi='Ziêg:BAAALgADCgcJBwAAAA==.',
Zo='Zoz:BAABLgAECn8WAAIBAAYJbwvgrgAIAQABAAYJbwvgrgAIAQAAAA==.',
Zu='Zulfrik:BAABLgAECn80AAIBAAkJEhfANgAgAgABAAkJEhfANgAgAgAAAA==.Zullard:BAAALgAECgEJAQAAAA==.',
Zy='Zyzy:BAAALgAECgkJEgABLgAECggJHgAGAIcgAA==.',
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
