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

local lookup = {'Mage-Frost','Shaman-Restoration','Shaman-Elemental','Paladin-Holy','Hunter-BeastMastery','DemonHunter-Devourer','DeathKnight-Blood','Evoker-Augmentation','Evoker-Preservation','Paladin-Protection','Druid-Restoration','Unknown-Unknown','Hunter-Survival','Hunter-Marksmanship','Warrior-Protection','Druid-Balance','DeathKnight-Unholy','Paladin-Retribution','Druid-Feral','Evoker-Devastation','DemonHunter-Havoc','Shaman-Enhancement','Warrior-Fury','Priest-Shadow','Druid-Guardian','Rogue-Subtlety','Monk-Mistweaver','Monk-Windwalker','Priest-Holy','Monk-Brewmaster','Warlock-Demonology','Warlock-Destruction','Mage-Arcane','DemonHunter-Vengeance','Mage-Fire','Warlock-Affliction','Rogue-Outlaw','Rogue-Assassination','DeathKnight-Frost',}
local provider = {region='US',realm='Eonar',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abbazaad:BAAALgAECgQJBQAAAA==.Abreen:BAAALgADCgcJCQAAAA==.Abysseus:BAAALgADCgcJCAAAAA==.',
Ac='Acepriest:BAAALgAECgMJBAAAAA==.Achievement:BAAALgAECgQJBAAAAA==.',
Ad='Adeathfox:BAAALgADCgEJAQAAAA==.Admired:BAABLgAECn8aAAIBAAcJoB4OVwAzAgABAAcJoB4OVwAzAgAAAA==.Adyr:BAACLgAFFH8FAAMCAAMJcxi6NgCoAAACAAIJ9R26NgCoAAADAAIJPgiALACFAAAuAAQKfyMAAwIACAmUH2wTAHoCAAIACAmUH2wTAHoCAAMABQnlF0pNABMBAAAA.',
Ai='Aidra:BAABLgAECn8dAAIEAAYJOh3bGADyAQAEAAYJOh3bGADyAQAAAA==.',
Al='Alaira:BAAALgAECgMJAwABLgAECgYJFAABAAYGAA==.Alamora:BAAALgAECgUJDwAAAA==.Alastair:BAAALgAECgcJCAAAAA==.Alathena:BAAALgAECgcJDAAAAA==.Albinoz:BAAALgADCgIJAgAAAA==.Albrect:BAAALgADCgYJEQAAAA==.Aldrich:BAAALgADCgEJAQAAAA==.Alexandrya:BAABLgAECn8qAAIFAAgJThiMMQDEAQAFAAgJThiMMQDEAQAAAA==.Alicemalkin:BAABLgAECn8XAAIGAAkJHxTyPQD8AQAGAAkJHxTyPQD8AQAAAA==.Alphred:BAAALgADCgkJCQAAAA==.Alysse:BAAALgADCgUJBwAAAA==.',
Am='Amarysia:BAAALgAECgYJCQAAAA==.Ameriixs:BAAALgAECgIJAgAAAA==.Amsip:BAAALgAECgEJAQABLgAECggJHAAHAIsNAA==.Amsroeb:BAABLgAECn8cAAIHAAgJiw0VGwArAQAHAAgJiw0VGwArAQAAAA==.',
An='Anelavenger:BAACLgAFFH8HAAIIAAMJpw6/KgDUAAAIAAMJpw6/KgDUAAAuAAQKfy0AAwgACQnbHMwMAKkCAAgACQnbHMwMAKkCAAkAAwlcAS1EAE0AAAAA.Angerwina:BAAALgADCgMJAwAAAA==.Anggar:BAAALgADCgIJAgAAAA==.',
Ao='Aomori:BAAALgAECgcJBwAAAA==.',
Aq='Aqüilés:BAAALgAECgEJAgAAAA==.',
Ar='Arathor:BAABLgAECn8dAAIKAAgJIhlFCgDQAQAKAAgJIhlFCgDQAQAAAA==.Arctorius:BAAALgADCgEJAQAAAA==.Arent:BAABLgAECn80AAILAAkJZRXDHAAXAgALAAkJZRXDHAAXAgAAAA==.Arfy:BAAALgADCgMJAgABLgAECggJEQAMAAAAAA==.Argøn:BAABLgAECn8uAAQFAAkJGhk3IwAHAgAFAAkJGhk3IwAHAgANAAUJ2AhOMgC7AAAOAAEJkAYUkgAoAAAAAA==.Arkanna:BAAALgAECgEJAQAAAA==.Arrise:BAAALgAECgUJBgAAAA==.Artemislives:BAAALgAECgcJCQAAAA==.Arthuaca:BAAALgAECgYJDQAAAA==.',
As='Asharia:BAAALgAECgcJDgAAAA==.Ashog:BAAALgADCgUJBQAAAA==.Assateague:BAAALgAECgUJDgAAAA==.Astralie:BAAALgADCggJDgAAAA==.Asuya:BAAALgADCgYJCQAAAA==.',
At='Athylan:BAAALgADCgEJAQABLgAFFAQJEgAEAFYhAA==.Atrosity:BAABLgAECn8mAAIPAAkJoSLQAgDdAgAPAAkJoSLQAgDdAgAAAA==.',
Au='Aurorabane:BAAALgADCgUJDAAAAA==.',
Av='Avelleah:BAAALgAECgEJBAAAAA==.',
Az='Azulyne:BAAALgADCgIJAgAAAA==.Azuretorrent:BAAALgADCgQJBAAAAA==.',
Ba='Bananapistol:BAAALgAECgUJBQAAAA==.Barracksbuny:BAAALgAECgEJAQABLgAECgQJBAAMAAAAAA==.Barrathfrogy:BAAALgADCgUJEQAAAA==.',
Be='Bebheishel:BAAALgADCgUJCgAAAA==.Bertelo:BAAALgADCgUJBQAAAA==.',
Bi='Bigstinky:BAAALgAECgYJCAAAAA==.Bisao:BAAALgAECgIJAgAAAA==.Biscuít:BAABLgAECn8oAAIQAAkJiA71HgB1AQAQAAkJiA71HgB1AQAAAA==.',
Bl='Blasuoff:BAAALgAECgQJBAAAAA==.Bloodrains:BAAALgAECgEJAwAAAA==.Bloodyfate:BAAALgADCgUJBQAAAA==.',
Bo='Bonesentinel:BAAALgAECgcJEAABLgAFFAQJCwARAAUYAA==.Bonës:BAAALgADCgEJAQAAAA==.Bora:BAAALgAECgQJDgAAAA==.Borzoi:BAABLgAFFH8NAAISAAQJsB/0LwAYAQASAAQJsB/0LwAYAQAAAA==.Bourgùîgnon:BAAALgADCgcJCgAAAA==.',
Br='Bragasch:BAAALgADCgkJGQAAAA==.Brakhon:BAAALgAECgEJAQAAAA==.Bruisebrews:BAAALgADCgEJAQAAAA==.',
Bu='Bullplop:BAAALgADCgUJBQAAAA==.Burekbazino:BAAALgADCgcJCQAAAA==.Burningsleet:BAAALgAECgYJBgAAAA==.',
['Bò']='Bò:BAABLgAECn8vAAIQAAkJEBYVEQACAgAQAAkJEBYVEQACAgAAAA==.',
Ca='Caduceus:BAAALgADCgcJEgAAAA==.Caesus:BAAALgAECgYJEAAAAA==.Cagedancer:BAABLgAECn8cAAMTAAYJiwgBHADDAAAQAAYJyAaNUADmAAATAAYJ7wYBHADDAAAAAA==.Callio:BAABLgAECn8vAAIFAAkJmxETKwDgAQAFAAkJmxETKwDgAQAAAA==.Cantor:BAAALgAECgEJAQAAAA==.Catchclause:BAAALgADCgkJFAAAAA==.Cathillex:BAAALgAECggJEwAAAA==.Cavagos:BAABLgAECn81AAIUAAkJViD3AADdAgAUAAkJViD3AADdAgAAAA==.Caycay:BAACLgAFFH8UAAIVAAUJdCHtAgCIAQAVAAUJdCHtAgCIAQAuAAQKfz4AAhUACQlyJfEAAL4DABUACQlyJfEAAL4DAAAA.',
Ce='Celebrexi:BAAALgAECgcJBgAAAA==.Celene:BAAALgADCgYJBwAAAA==.Cerrulli:BAAALgAECgYJDwAAAA==.',
Ch='Chaosknight:BAAALgAECgcJEwABLgAECggJDgAMAAAAAA==.Chaostrip:BAABLgAECn8rAAIGAAgJkSLqDwCDAgAGAAgJkSLqDwCDAgAAAA==.Chillbros:BAACLgAFFH8MAAIWAAUJWCH5AgBYAQAWAAUJWCH5AgBYAQAuAAQKfygAAxYACAmOJPkBADwDABYACAkQJPkBADwDAAMABAmqH+45AGcBAAAA.Chilldh:BAAALgAECgUJBQABLgAFFAUJDAAWAFghAA==.Chillmage:BAAALgADCgcJCgABLgAFFAUJDAAWAFghAA==.Chindi:BAABLgAECn8pAAMXAAkJKhY9FAAEAgAXAAkJKhY9FAAEAgAPAAEJ0AKpPwAxAAAAAA==.Chindrakh:BAAALgAECggJCAABLgAECgkJKQAXACoWAA==.Choiminasue:BAAALgAECgEJAgAAAA==.Chunga:BAABLgAECn8UAAIDAAYJoAPZXADQAAADAAYJoAPZXADQAAAAAA==.Chungers:BAAALgAECgQJBgAAAA==.Churd:BAACLgAFFH8HAAIYAAMJJAzGGQDLAAAYAAMJJAzGGQDLAAAuAAQKfyUAAhgACAlxGF0TAOUBABgACAlxGF0TAOUBAAAA.Churdicus:BAAALgADCgkJEQAAAA==.Chypnotic:BAAALgAECgcJBAAAAA==.Chypper:BAAALgADCgEJAQAAAA==.Chypster:BAABLgAECn8aAAIDAAYJog0nPQDmAAADAAYJog0nPQDmAAAAAA==.',
Ci='Ciceroe:BAAALgAECgYJDQAAAA==.Citadel:BAAALgADCgIJAwAAAA==.',
Cl='Cleft:BAAALgAECgUJCQAAAA==.',
Co='Coalystra:BAABLgAECn8sAAIGAAkJ6RoKFQBZAgAGAAkJ6RoKFQBZAgAAAA==.Cocopuffs:BAACLgAFFH8HAAIQAAIJsBG2FACfAAAQAAIJsBG2FACfAAAuAAQKfzUAAhAACQleICMJAAMDABAACQleICMJAAMDAAAA.Colostrom:BAABLgAECn8vAAIKAAkJ1R+zAwCFAgAKAAkJ1R+zAwCFAgAAAA==.Complicatedz:BAAALgAECgUJBQAAAA==.Comul:BAAALgADCgcJBwAAAA==.Coramage:BAABLgAECn8XAAIBAAcJWwbymQALAQABAAcJWwbymQALAQAAAA==.Corentis:BAAALgADCgYJBgAAAA==.Corliss:BAABLgAECn8VAAIPAAgJ/hNoEACRAQAPAAgJ/hNoEACRAQAAAA==.',
Cp='Cplusmc:BAAALgAECgQJBwAAAA==.',
Cr='Creightizle:BAABLgAECn8eAAIFAAgJfRS/OQDHAQAFAAgJfRS/OQDHAQAAAA==.',
['Cá']='Cátix:BAAALgADCgIJAgAAAA==.',
Da='Daicmerollin:BAAALgAECgYJCwAAAA==.Danhaüsen:BAAALgAECgIJAwAAAA==.Darkbeast:BAAALgAECgkJEgAAAA==.Darkdeeds:BAAALgADCggJEQAAAA==.Darkpallo:BAABLgAECn8YAAISAAcJPxPWbwCdAQASAAcJPxPWbwCdAQABLgAECgkJEgAMAAAAAA==.Darthtav:BAAALgAECgYJCwABLgAFFAUJCwAQAPwNAA==.Daten:BAABLgAECn83AAISAAkJrBLGXwBnAQASAAkJrBLGXwBnAQAAAA==.Dazshauran:BAAALgADCgEJAQAAAA==.Daîma:BAAALgADCggJCAAAAA==.',
De='Deathbycow:BAABLgAECn8rAAIZAAgJlhzMBgAsAgAZAAgJlhzMBgAsAgAAAA==.Decayed:BAABLgAECn8WAAIHAAcJ5xXWFgBYAQAHAAcJ5xXWFgBYAQABLgAECgQJBAAMAAAAAA==.Demonchalk:BAAALgAFFAEJAQABLgAFFAQJEQAWAAMmAA==.Desdeynna:BAAALgADCgEJAQAAAA==.Dewbie:BAAALgAECgEJAQAAAA==.',
Di='Diagonalli:BAABLgAECn8YAAIUAAcJMA/5CABSAQAUAAcJMA/5CABSAQAAAA==.Dimmadome:BAAALgADCgEJAQAAAA==.Dinojam:BAAALgADCgMJAQAAAA==.Divirian:BAAALgAECgYJDgAAAA==.',
Dj='Djdaemon:BAAALgADCgcJDQAAAA==.Djdrakshadow:BAAALgADCgYJDQAAAA==.Djpaly:BAAALgADCgYJEQAAAA==.Djpriest:BAAALgADCgYJCQAAAA==.Djshadow:BAAALgADCgUJBQAAAA==.Djshadowar:BAAALgADCggJFAAAAA==.Djshadowhunt:BAAALgADCgkJHwAAAA==.Djshadowlock:BAAALgADCgUJBwAAAA==.Djshadowrog:BAAALgADCgYJDgAAAA==.Djshamy:BAAALgADCgQJBAAAAA==.Djshaolin:BAAALgADCgUJDgAAAA==.Djzhadow:BAAALgADCgYJCQAAAA==.Djzhadruid:BAAALgADCgUJCgAAAA==.',
Dk='Dkshadow:BAAALgADCgcJDwAAAA==.',
Dm='Dmitrì:BAAALgAECgEJAQAAAA==.',
Do='Dogno:BAAALgAECgEJAgAAAA==.Dontdieplez:BAAALgAECgkJDAAAAA==.',
Dp='Dpm:BAAALgAECgEJAgAAAA==.',
Dr='Dragbuttakis:BAAALgAECgUJCAAAAA==.Drakhadir:BAAALgADCgYJBwAAAA==.Drakmon:BAAALgAECgIJAwAAAA==.Draktând:BAABLgAECn8mAAIaAAgJKhKPFgCSAQAaAAgJKhKPFgCSAQAAAA==.Drippysilk:BAAALgAECgQJCAABLgAECgYJGgAUAPwiAA==.Drius:BAAALgADCgMJAwAAAA==.Drunkenpanda:BAABLgAECn8hAAMbAAkJLxQ0JgBqAQAbAAkJLxQ0JgBqAQAcAAcJnQdfPgC4AAAAAA==.Drunknoodle:BAAALgAECgQJCAAAAA==.',
Du='Duhpriest:BAAALgAECgEJAQAAAA==.Duinrane:BAAALgAECgEJAQAAAA==.Duon:BAAALgAECggJEwAAAA==.',
Dw='Dwagonfur:BAAALgAECgcJBgAAAA==.',
Ec='Echö:BAABLgAECn8hAAIVAAgJihk/EQCvAQAVAAgJihk/EQCvAQAAAA==.',
Ei='Eiarinos:BAAALgADCgEJAQAAAA==.Eirø:BAAALgADCgkJCQABLgAECgkJNAAOAA4jAA==.',
El='Elaine:BAAALgAECgkJDgAAAA==.Elberon:BAAALgAECgMJAwAAAA==.Elmerhomero:BAAALgADCgUJBQAAAA==.Elronnd:BAAALgADCgkJGgAAAA==.Elsebeth:BAAALgADCgcJCAAAAA==.',
Em='Emilie:BAAALgADCgYJBgAAAA==.',
En='Enoch:BAABLgAECn8bAAISAAYJkBZXfwB7AQASAAYJkBZXfwB7AQAAAA==.',
Er='Eriam:BAAALgADCgIJAgABLgAECggJHQAZAOwXAA==.Errane:BAACLgAFFH8UAAILAAQJRyUZCwC7AQALAAQJRyUZCwC7AQAuAAQKfysAAwsACAnJJosEAEYDAAsACAnJJosEAEYDABAAAQnHFVJ4AEQAAAAA.Eruiluvatar:BAAALgAECgYJBgAAAA==.',
Et='Etalia:BAAALgADCgYJBgAAAA==.Etcetera:BAAALgAECgMJAwAAAA==.',
Fa='Fallenangell:BAAALgADCgUJBQAAAA==.Fandiirn:BAAALgADCgYJBgAAAA==.Fastjack:BAABLgAECn8bAAMdAAYJlxVXIgBoAQAdAAYJlxVXIgBoAQAYAAEJAAD/cQAAAAAAAA==.',
Fi='Fiora:BAAALgADCgYJCwAAAA==.Firbirl:BAAALgAECgIJAgAAAA==.Fistoffury:BAABLgAECn8YAAMeAAcJqBM3KgAnAQAeAAcJqBM3KgAnAQAcAAQJOAkEWgCoAAAAAA==.Fitco:BAAALgADCgYJCwABLgAECgYJDwAMAAAAAA==.Fiènd:BAAALgADCgYJBgAAAA==.',
Fl='Flametar:BAAALgAECgEJAQAAAA==.Floppydisk:BAAALgAECgUJCwAAAA==.',
Fo='Fortiss:BAACLgAFFH8GAAICAAMJLxZ/KADnAAACAAMJLxZ/KADnAAAuAAQKfyMAAwIACQlHCBpGADIBAAIACQlHCBpGADIBAAMABgk/EKs5APYAAAAA.',
Fr='Frito:BAAALgAECggJCQAAAA==.Frost:BAAALgAFFAIJAgABLgAFFAYJHwANAKEVAA==.Frostmon:BAAALgAECggJEAAAAA==.Frshnvrfrzn:BAAALgAECggJDwAAAA==.Frøzenblight:BAAALgAECgEJAQAAAA==.',
Fu='Fulmo:BAAALgADCgUJBQABLgAECgkJGwARAKsOAA==.Furbee:BAAALgAECggJEAAAAA==.',
['Fá']='Fáde:BAAALgADCgQJBQABLgAECgMJAwAMAAAAAA==.',
Ga='Gabris:BAAALgADCgYJBgAAAA==.Galeandra:BAAALgAECgYJDQAAAA==.Garim:BAAALgADCgMJBAABLgAECgYJGwAdAJcVAA==.',
Ge='Geraltofrvia:BAAALgAECgcJDAAAAA==.',
Gi='Giantgoose:BAAALgAECgEJAgAAAA==.Gingani:BAAALgADCgcJCQAAAA==.',
Gn='Gnar:BAAALgAECgUJEwAAAA==.',
Go='Gowtherdead:BAAALgADCgQJBAAAAA==.Gowtherpunch:BAABLgAECn8xAAIeAAkJuBXWDwADAgAeAAkJuBXWDwADAgAAAA==.',
Gr='Gregzug:BAAALgAECgMJAwAAAA==.Greyjoy:BAAALgADCgYJBQAAAA==.Grimfury:BAAALgAFFAIJAgAAAA==.Grimsy:BAAALgADCgYJBwAAAA==.Grodd:BAAALgADCgUJBQAAAA==.Groqqu:BAAALgAECgQJBAAAAA==.Grumble:BAAALgAECgIJAgAAAA==.Gruxxiron:BAAALgAECgUJBwABLgAECgkJMwARADYfAA==.',
Gu='Gulnn:BAABLgAECn8sAAMfAAkJzxsKFAB2AgAfAAkJzxsKFAB2AgAgAAIJVhT8VABvAAAAAA==.Gumby:BAAALgADCgYJBgAAAA==.',
Ha='Haelena:BAAALgAECgcJEwAAAA==.Halys:BAAALgADCgUJBQAAAA==.Hamil:BAAALgADCgEJAQAAAA==.Harmoss:BAAALgAECgcJBwAAAA==.Hawk:BAAALgADCgYJBgAAAA==.',
He='Heartsfang:BAAALgADCgUJCAAAAA==.Helfire:BAAALgADCgYJBgABLgAECgMJAwAMAAAAAA==.Hellscreems:BAAALgADCgMJAwAAAA==.Heriotza:BAABLgAECn8bAAIRAAkJqw5sVwB3AQARAAkJqw5sVwB3AQAAAA==.',
Ia='Iamfubar:BAAALgADCgMJAwAAAA==.',
Ig='Igris:BAAALgAECgcJCgAAAA==.',
Ii='Iimit:BAABLgAECn8gAAIaAAgJkhsQDQAGAgAaAAgJkhsQDQAGAgAAAA==.',
Il='Illidead:BAACLgAFFH8WAAIBAAYJ6ByQEwC7AQABAAYJ6ByQEwC7AQAuAAQKfyEAAwEACAkLJCs7AIoCAAEACAnJICs7AIoCACEAAQnXHxgXAGEAAAAA.Iluni:BAAALgADCgMJAwAAAA==.',
Im='Implied:BAAALgADCgUJBQAAAA==.',
In='Indexes:BAAALgAECgUJDQAAAA==.Insrik:BAAALgAECgEJAwAAAA==.',
Io='Iompróirbáis:BAABLgAECn8aAAIRAAkJYgalYABeAQARAAkJYgalYABeAQAAAA==.',
Ir='Irdeadohnoz:BAABLgAECn8VAAIBAAcJrgtajAAkAQABAAcJrgtajAAkAQAAAA==.',
Is='Ist:BAAALgAECgEJAQAAAA==.',
It='Itchigo:BAAALgAECgcJEgAAAA==.',
Iv='Ivern:BAAALgAECgIJAgAAAA==.Ivgorod:BAABLgAECn8dAAMUAAgJVglTCQBJAQAUAAgJFAlTCQBJAQAIAAYJuAX9RwC1AAAAAA==.',
Ja='Jabbadahut:BAAALgAECgcJBQAAAA==.Jambi:BAAALgAECgYJDgAAAA==.Jardani:BAAALgAECgEJAQAAAA==.Jastrae:BAAALgAECgcJDgAAAA==.Jazilyne:BAAALgADCgkJGgAAAA==.',
Je='Jealous:BAAALgADCgUJBQABLgAECgkJIgAGAJsdAA==.Jenka:BAAALgAECgQJCQAAAA==.',
Ji='Jibbs:BAAALgADCgkJCQAAAA==.',
Jo='Joleya:BAAALgADCgEJAQAAAA==.',
Ju='Junta:BAAALgADCgcJJQAAAA==.Justine:BAAALgADCgUJBQAAAA==.Justtrolling:BAAALgAECgYJDgAAAA==.',
['Jä']='Jäkel:BAAALgADCgUJBQAAAA==.',
Ka='Kalike:BAAALgADCgcJBwAAAA==.Kambative:BAABLgAECn8UAAMLAAcJqxIPQgCZAQALAAcJqxIPQgCZAQAQAAIJRxECUgBrAAAAAA==.Kammunion:BAAALgAECgYJBgABLgAECgcJFAALAKsSAA==.Kamphiyer:BAABLgAECn82AAQJAAkJ6hgCBwBKAgAJAAkJ6hgCBwBKAgAIAAgJiB3fDQA6AgAUAAQJowzBMQCIAAABLgAECgcJFAALAKsSAA==.Kamsumerage:BAAALgADCgkJEgABLgAECgcJFAALAKsSAA==.Kandosii:BAAALgADCgUJBQAAAA==.Kantheal:BAABLgAECn8dAAIEAAgJHh0gDACDAgAEAAgJHh0gDACDAgAAAA==.Kaulana:BAAALgADCgcJDAAAAA==.',
Ke='Keirmania:BAAALgAECgEJAQAAAA==.Kekkan:BAAALgADCgUJAwAAAA==.Kellendere:BAAALgADCgYJCwAAAA==.',
Ki='Kiieedk:BAAALgAECgEJAQAAAA==.Kimgoeun:BAAALgADCgYJBgAAAA==.Kio:BAAALgAECgYJCAAAAA==.',
Kn='Knùsê:BAAALgADCgUJBgABLgAECgkJNAAOAA4jAA==.',
Ko='Komorai:BAAALgADCgYJBgAAAA==.',
Kr='Kravex:BAABLgAECn8dAAIZAAgJ7BdSCgDZAQAZAAgJ7BdSCgDZAQAAAA==.Krixxa:BAABLgAECn8oAAIdAAkJWSR/AQB5AwAdAAkJWSR/AQB5AwAAAA==.',
Ku='Kuula:BAAALgADCgUJBQAAAA==.',
Ky='Kylana:BAAALgADCgQJBAAAAA==.',
['Kä']='Kären:BAAALgAECgUJEgAAAA==.',
['Ké']='Kélly:BAAALgAECggJCAAAAA==.',
La='Laochnaofa:BAAALgAECgYJDAAAAA==.Larayvia:BAABLgAECn8dAAIFAAgJJg5HOwDBAQAFAAgJJg5HOwDBAQAAAA==.Laurance:BAAALgADCgYJBgAAAA==.',
Le='Leesala:BAABLgAECn8wAAMCAAkJqhctEwBfAgACAAkJqhctEwBfAgAWAAEJ/gTBKQAnAAAAAA==.Lerazer:BAAALgAECgYJCQAAAA==.',
Lg='Lgidk:BAAALgADCgMJAwABLgAECgkJIgAGAJsdAA==.',
Li='Lic:BAAALgAECgMJAwAAAA==.Liliatrix:BAAALgAECgQJBQAAAA==.Lillabet:BAAALgAECgUJDAAAAA==.Lilmatty:BAAALgAECgkJDQABLgAECggJFAAcAJYXAA==.Lilsneaky:BAAALgADCggJCAAAAA==.Limpydk:BAAALgADCgUJBQABLgAECgYJGgAUAPwiAA==.Limpylarva:BAAALgADCgMJAwABLgAECgYJGgAUAPwiAA==.Limpypal:BAAALgAECgYJCwABLgAECgYJGgAUAPwiAA==.Litter:BAAALgAECgUJBQAAAA==.',
Lo='Logathil:BAAALgAECgYJEAAAAA==.',
Lu='Luchulainn:BAAALgADCgYJBgAAAA==.Lucifero:BAAALgAECgUJBwAAAA==.Lucifurwild:BAAALgADCgQJBQAAAA==.Lunaaris:BAABLgAECn8rAAILAAkJBR9cCgDYAgALAAkJBR9cCgDYAgAAAA==.Lunastre:BAAALgADCgEJAQAAAA==.',
['Lí']='Límpy:BAABLgAECn8aAAIUAAYJ/CJ/CgA0AgAUAAYJ/CJ/CgA0AgAAAA==.Línk:BAAALgAECgYJCgAAAA==.',
['Lî']='Lîkwuid:BAAALgAECggJDwAAAA==.',
Ma='Macallan:BAAALgAECgEJAwAAAA==.Maddrox:BAAALgADCgcJDwAAAA==.Magicmarv:BAAALgADCgIJAQAAAA==.Magnagoth:BAAALgADCgkJDwAAAA==.Magnakilro:BAABLgAECn8cAAIFAAgJGxSmPgCRAQAFAAgJGxSmPgCRAQAAAA==.Mahnaz:BAAALgADCgEJAQABLgADCgcJCgAMAAAAAA==.Malanath:BAABLgAECn8XAAIIAAgJshVNHQCbAQAIAAgJshVNHQCbAQAAAA==.Malothas:BAAALgADCgQJBAAAAA==.Mareki:BAAALgADCgYJBwAAAA==.Markdfordeth:BAAALgAECgEJAQAAAA==.Mattyfu:BAABLgAECn8UAAMcAAgJlhckHQDxAQAcAAgJlhckHQDxAQAbAAMJHBzEOQDxAAAAAA==.Mavíel:BAAALgAECgYJDQAAAA==.Maxrogue:BAAALgAECgYJCgABLgAECgYJHAAZAFYQAA==.Mazikeen:BAAALgAECgUJBgAAAA==.',
Mc='Mcscoots:BAAALgADCgcJEgAAAA==.',
Me='Meatsupreme:BAABLgAECn8lAAISAAgJ4AyDbwBDAQASAAgJ4AyDbwBDAQAAAA==.Meepin:BAACLgAFFH8SAAIEAAQJViHTDACFAQAEAAQJViHTDACFAQAuAAQKfyoAAwQACQnWJAQFABwDAAQACAmmJQQFABwDABIAAwk/Cj3cAIsAAAAA.Meepmorp:BAAALgADCgIJAgAAAA==.Meifeng:BAAALgADCgEJAQAAAA==.Mephala:BAAALgADCgYJBgAAAA==.Mesophistole:BAAALgADCggJCwABLgAECgUJDwAMAAAAAA==.Mesopyro:BAAALgAECgUJDwAAAA==.',
Mi='Mileenä:BAAALgAECgcJBgAAAA==.Minimim:BAAALgADCgMJAwAAAA==.Mià:BAAALgADCgEJAQAAAA==.',
Mo='Mod:BAAALgAECgcJEwAAAA==.Mograiné:BAAALgAECgQJCQAAAA==.Mojodaemon:BAAALgADCgUJCAAAAA==.Monkaw:BAAALgAECgIJAgAAAA==.Monkchalk:BAAALgAECgQJBAABLgAFFAQJEQAWAAMmAA==.Moondevil:BAAALgADCgYJBwAAAA==.Morta:BAEALgAFFAIJAgAAAA==.Mortkavaliro:BAAALgAECgUJCAAAAA==.',
Ms='Mslockness:BAAALgADCgUJDwAAAA==.',
Mu='Mugzy:BAAALgAECgkJBwAAAA==.Multipass:BAAALgAECgcJEwAAAA==.Multitool:BAAALgADCgEJAQAAAA==.',
['Mö']='Mörph:BAAALgAECgIJAgAAAA==.',
Na='Nadris:BAAALgADCgcJBwAAAA==.Nanérs:BAAALgAECgcJEQABLgAFFAUJCwAQAPwNAA==.Narrodus:BAABLgAECn8dAAIiAAgJGiTOAQC8AgAiAAgJGiTOAQC8AgAAAA==.Nasht:BAABLgAECn8VAAIBAAYJUBaPfwA8AQABAAYJUBaPfwA8AQAAAA==.Nashty:BAAALgADCgYJBgABLgAECgYJFQABAFAWAA==.Nashxi:BAAALgADCgkJEAABLgAECgYJFQABAFAWAA==.Nasu:BAAALgAECgcJAQAAAA==.Nattymoo:BAAALgAECgYJCQABLgAECggJFAAcAJYXAA==.',
Ne='Necrô:BAAALgADCgIJAgAAAA==.Nephi:BAAALgADCgUJBQAAAA==.',
Ni='Nightraven:BAAALgADCgkJCQAAAA==.Nightreaper:BAAALgADCgkJGwAAAA==.Nimbus:BAACLgAFFH8RAAIDAAUJnhkoDwBHAQADAAUJnhkoDwBHAQAuAAQKf0wAAgMACQmNJVIBAFUDAAMACQmNJVIBAFUDAAEuAAUUCAkWAAgATBYA.Nimike:BAAALgAECgcJDQAAAA==.',
No='Normul:BAAALgAECgcJAwABLgAECgkJMgARAMUhAA==.Noshoba:BAAALgAECgEJAQAAAA==.',
Nr='Nrvous:BAAALgADCgkJCQAAAA==.',
Nu='Nugzuul:BAAALgAECgEJAQAAAA==.Numbers:BAABLgAECn8UAAMVAAYJHA+bIgD8AAAVAAYJCQ6bIgD8AAAGAAYJnAoFfQDSAAAAAA==.',
Ny='Nyterage:BAAALgAECgIJAgAAAA==.Nytesage:BAACLgAFFH8cAAIjAAYJvSULAABBAgAjAAYJvSULAABBAgAuAAQKfygAAiMACAkMJj8AAH4DACMACAkMJj8AAH4DAAAA.',
['Nä']='Näners:BAAALgAFFAEJAQABLgAFFAUJCwAQAPwNAA==.',
['Nì']='Nìghtcat:BAAALgAECgQJBAAAAA==.',
Oo='Ookle:BAABLgAECn8hAAMTAAgJZAcREwAmAQATAAgJZAcREwAmAQALAAcJrwi+egDoAAAAAA==.',
Or='Oresh:BAABLgAECn8dAAIXAAcJTxH/KgBaAQAXAAcJTxH/KgBaAQAAAA==.Oryz:BAAALgADCgkJCAAAAA==.',
Os='Osajak:BAAALgADCgIJAgAAAA==.',
Oz='Ozo:BAAALgAECgcJEwAAAA==.',
Pa='Painavolian:BAABLgAECn88AAIBAAkJvR4GGQCKAgABAAkJvR4GGQCKAgAAAA==.Palifur:BAAALgAECgkJDgAAAA==.Pandamonium:BAAALgAECgcJEgAAAA==.Panes:BAAALgAECgcJCwAAAA==.Paopu:BAAALgADCgYJBgABLgAECgkJIAAfAPYfAA==.',
Pe='Peeches:BAAALgAECgYJCwAAAA==.Pelor:BAAALgAECgcJCgAAAA==.',
Ph='Pheayre:BAAALgADCgMJAwABLgAECgcJDAAMAAAAAA==.',
Pi='Pisspadpanda:BAACLgAFFH8HAAMfAAQJHhOVTgDhAAAfAAMJpxCVTgDhAAAkAAEJhBoaEABPAAAuAAQKfykAAh8ACQlrIoMMALcCAB8ACQlrIoMMALcCAAAA.',
Po='Poggies:BAACLgAFFH8bAAIjAAYJ9SUPAAAuAgAjAAYJ9SUPAAAuAgAuAAQKfyEAAyMACAk9JjkAAIIDACMACAk9JjkAAIIDACEAAQkOIP8WAGIAAAAA.Ponmonk:BAAALgAECgEJAQABLgAECgYJFQAYALcfAA==.Pontacos:BAABLgAECn8VAAIYAAYJtx/AIADTAQAYAAYJtx/AIADTAQAAAA==.Porkinator:BAAALgADCgYJCAAAAA==.Powdur:BAAALgADCgEJAQABLgADCgIJAgAMAAAAAA==.Pozh:BAABLgAECn8UAAIfAAYJlA0HkQA3AQAfAAYJlA0HkQA3AQAAAA==.',
Pr='Praynes:BAABLgAECn8xAAIdAAkJ6hjJEgBKAgAdAAkJ6hjJEgBKAgAAAA==.Precedence:BAAALgADCgEJAQABLgAECgEJAQAMAAAAAA==.Prestocreamÿ:BAAALgADCgEJAQAAAA==.',
Pu='Pummel:BAAALgAECgYJBgAAAA==.Pupperputh:BAAALgADCgkJEgABLgAECgkJIgAGAJsdAA==.Puppet:BAAALgAECgEJAgAAAA==.',
['Pä']='Päroxysm:BAAALgAECgEJAgABLgAECgYJBgAMAAAAAA==.',
Ra='Randyrando:BAAALgADCgIJBAAAAA==.Ranoe:BAABLgAECn8ZAAIGAAcJVhXzVAClAQAGAAcJVhXzVAClAQAAAA==.Rastrin:BAAALgADCgYJBwAAAA==.Ravyniel:BAAALgADCgEJAQAAAA==.Razji:BAABLgAECn89AAQNAAkJ7iP3AQAFAwANAAkJ4iL3AQAFAwAOAAcJsSENGABtAgAFAAIJiSbQgQDjAAAAAA==.',
Re='Redrrum:BAAALgAECgcJCgAAAA==.Rekd:BAAALgADCgEJAQAAAA==.Reladiia:BAAALgADCgcJBwAAAA==.Renfro:BAAALgADCgcJBwAAAA==.Restokhan:BAAALgAECgEJAQAAAA==.Revoked:BAAALgADCgEJAQABLgAECgYJDwAMAAAAAA==.Reznick:BAABLgAECn8ZAAIXAAgJ6g6DJwBvAQAXAAgJ6g6DJwBvAQAAAA==.',
Ro='Rocknwolf:BAAALgAECgEJAQAAAA==.Rokd:BAAALgAECgcJDQAAAA==.Rokham:BAAALgADCgEJAQAAAA==.Rosalee:BAAALgADCgEJAQAAAA==.Rovërgalarga:BAAALgADCgMJAwAAAA==.',
Ru='Rudeboy:BAAALgAECgEJAQAAAA==.Ruibaron:BAAALgAECgUJCQAAAA==.',
Ry='Ryhunter:BAAALgADCggJDgAAAA==.',
['Rà']='Ràidèn:BAABLgAECn8mAAIRAAkJ+RwaHABbAgARAAkJ+RwaHABbAgAAAA==.',
['Rá']='Ráyne:BAAALgAECgQJBgAAAA==.',
Sa='Sadeel:BAABLgAECn8sAAMkAAkJVxqLBgCoAQAfAAkJdBKmRQD6AQAkAAcJKh2LBgCoAQAAAA==.Sadewolf:BAABLgAECn8mAAIGAAgJ3h1fGgA0AgAGAAgJ3h1fGgA0AgAAAA==.Sadpanduh:BAAALgADCgkJFQAAAA==.Saltednuts:BAAALgAECgEJAQAAAA==.Samentoni:BAABLgAECn8mAAIEAAgJIBkEFAAjAgAEAAgJIBkEFAAjAgAAAA==.Samgal:BAABLgAECn8XAAIgAAgJ3hZqBQDEAQAgAAgJ3hZqBQDEAQAAAA==.Sardothien:BAAALgAECgEJAgAAAA==.Satyra:BAAALgAECgYJCwABLgAECgkJKAAdAFkkAA==.Saurphang:BAACLgAFFH8UAAMRAAUJohEeGABFAQARAAQJohEeGABFAQAHAAEJAAAkQAAAAAAuAAQKfyoAAhEACAkFIxIVAP0CABEACAkFIxIVAP0CAAAA.Saye:BAAALgADCgIJAgAAAA==.',
Sc='Scarletpanda:BAAALgADCgQJBgAAAA==.Scourgereap:BAAALgAECgMJAwAAAA==.',
Se='Selinna:BAAALgAECggJEgAAAA==.Senpaichill:BAAALgAECgYJDQAAAA==.Severis:BAAALgADCgIJAgAAAA==.',
Sh='Shadiepope:BAAALgAECgEJAQAAAA==.Shadora:BAABLgAECn8gAAIYAAkJLBPYEgDrAQAYAAkJLBPYEgDrAQAAAA==.Shadowwizard:BAAALgAECgMJAwAAAA==.Shadybrat:BAAALgAECgYJDQABLgAECggJKgAFAE4YAA==.Shaggylol:BAAALgADCgcJDQAAAA==.Shamlazy:BAAALgADCgkJHQAAAA==.Shidan:BAAALgAECggJDAABLgAECgkJJgARAPkcAA==.Shiroku:BAAALgAECgkJBgAAAA==.Shockchalk:BAACLgAFFH8RAAIWAAQJAyYJAQCqAQAWAAQJAyYJAQCqAQAuAAQKfzEAAxYACQnhJZEAADgDABYACQnhJZEAADgDAAMAAglhEXJdAG0AAAAA.Shocknorris:BAAALgAECgQJBwABLgAECgYJDwAMAAAAAA==.Shrooclaw:BAACLgAFFH8GAAILAAIJmQqNPgB8AAALAAIJmQqNPgB8AAAuAAQKfxoAAgsACAlkFfAuAJ8BAAsACAlkFfAuAJ8BAAAA.',
Si='Sibbiah:BAAALgAECgcJBgAAAA==.Silanre:BAABLgAECn8eAAIBAAcJtxG/ZQBxAQABAAcJtxG/ZQBxAQAAAA==.',
Sk='Skaðï:BAABLgAECn80AAQOAAkJDiM+AgCeAgAOAAgJ0CM+AgCeAgANAAQJ7hm/IABFAQAFAAMJ6R4XlgCoAAAAAA==.',
Sm='Smolshrapnel:BAAALgAECgcJEAAAAA==.',
Sn='Sneakchalk:BAAALgADCgcJCwABLgAFFAQJEQAWAAMmAA==.',
So='Solaraze:BAABLgAECn8jAAMSAAkJexx4PAAyAgASAAgJBR14PAAyAgAEAAIJdBD2VwB4AAAAAA==.Solinarie:BAAALgADCgIJAgAAAA==.Sorefang:BAAALgADCgEJAQAAAA==.Sorrowfang:BAAALgAECgEJAQAAAA==.Sovnightwar:BAAALgAECggJCwABLgAFFAMJBAAMAAAAAA==.Soza:BAAALgADCgEJAQAAAA==.',
Sp='Spacespecial:BAAALgAECggJDwAAAA==.Sparklebunny:BAAALgADCgEJAQAAAA==.Spicycurryy:BAABLgAECn81AAQFAAkJMh8/GgBqAgAFAAgJeSA/GgBqAgANAAcJHRPCFwCYAQAOAAIJJAzGeABeAAABLgAECgkJNQAFADIfAA==.Spicyycurryy:BAAALgAECgMJAwABLgAECgkJNQAFADIfAA==.Spiker:BAAALgAECgEJAQAAAA==.Splittail:BAAALgAECgQJBAAAAA==.',
St='Strahm:BAABLgAECn8cAAIZAAYJVhCXGwDvAAAZAAYJVhCXGwDvAAAAAA==.Strehm:BAAALgAECgQJAwABLgAECgYJHAAZAFYQAA==.Strohmy:BAAALgADCgEJAQABLgAECgYJHAAZAFYQAA==.Stryhm:BAAALgAECgQJBQABLgAECgYJHAAZAFYQAA==.',
Su='Sunju:BAAALgADCgMJAwAAAA==.',
Sy='Syssare:BAABLgAECn8XAAIVAAcJbCI5DAABAgAVAAcJbCI5DAABAgAAAA==.',
Ta='Tabbie:BAAALgADCgYJCQAAAA==.Tacpally:BAAALgADCgMJAwAAAA==.Talasam:BAAALgAECgYJDQAAAA==.Talien:BAAALgADCgEJAQAAAA==.Tandsonnara:BAAALgAECgkJDAAAAA==.Tastetickle:BAABLgAECn81AAIBAAkJLx/bEQC6AgABAAkJLx/bEQC6AgAAAA==.Tazdrin:BAABLgAECn8yAAIlAAkJJBdRAwAeAgAlAAkJJBdRAwAeAgAAAA==.',
Te='Telidrus:BAACLgAFFH8UAAIBAAUJZxscLgBaAQABAAUJZxscLgBaAQAuAAQKfycABAEACAk1IGkxAK0CAAEABwknI2kxAK0CACEABAm1HbsEAF0BACMAAglcEzkMADwAAAAA.Temok:BAAALgADCgEJAQAAAA==.Teyrlis:BAAALgAECgUJCAAAAA==.',
Th='Thavryn:BAAALgADCgYJBgAAAA==.Thaz:BAAALgAECgQJBwAAAA==.Thias:BAABLgAECn8cAAIBAAgJQxMjUgCkAQABAAgJQxMjUgCkAQAAAA==.Thukmonk:BAAALgAECgQJBwAAAA==.Thukwarlock:BAABLgAECn8hAAIfAAcJ7xgoSQDuAQAfAAcJ7xgoSQDuAQAAAA==.Thunderbug:BAAALgADCgEJAQAAAA==.',
To='Todd:BAAALgAECgEJAQAAAA==.Tokain:BAAALgADCgkJEQAAAA==.Topaze:BAAALgAECgUJCAAAAA==.Torironheart:BAAALgADCgcJBwAAAA==.',
Tr='Trance:BAAALgAECgEJAQABLgAECgEJAQAMAAAAAA==.Treehuggera:BAAALgAECgYJCgAAAA==.Tribunal:BAAALgAECgEJAQAAAA==.Trilila:BAAALgADCgYJBgAAAA==.Tripx:BAAALgAECggJEwABLgAECggJKwAGAJEiAA==.Tronko:BAABLgAECn8lAAMCAAkJHBysDACmAgACAAkJHBysDACmAgADAAEJ8BNGcwA4AAAAAA==.Trumpinator:BAAALgADCgUJCwAAAA==.',
Ts='Tsireya:BAAALgAECgUJBQABLgAECgQJDgAMAAAAAA==.',
Tu='Turntsnaco:BAACLgAFFH8FAAIaAAIJJBgFHwCoAAAaAAIJJBgFHwCoAAAuAAQKfzMAAxoACAnnIbEIAE8CABoACAnnIbEIAE8CACYAAQnHEIcdADoAAAAA.Tusk:BAAALgAECgcJEQAAAA==.',
Tw='Twigger:BAAALgADCgEJAgAAAA==.Twiztedsoul:BAAALgAECgMJAwAAAA==.Twophorb:BAAALgADCgMJAwAAAA==.',
Ua='Uake:BAAALgADCgYJBgAAAA==.',
Ud='Udgar:BAAALgAECgkJEQAAAA==.',
Un='Unafhaen:BAAALgADCgEJAQAAAA==.Unaverse:BAAALgAECgEJAQAAAA==.',
Us='Usmc:BAAALgADCgYJBgAAAA==.Usmccpl:BAAALgAECgUJDQAAAA==.Usmcsemperfi:BAAALgADCgYJDAAAAA==.',
Va='Valengarde:BAABLgAECn8ZAAISAAgJqBQVUQCLAQASAAgJqBQVUQCLAQAAAA==.Vanette:BAAALgAECgIJAgAAAA==.Vannix:BAACLgAFFH8FAAIYAAMJbB8NEgAlAQAYAAMJbB8NEgAlAQAuAAQKfzcAAhgACQmVI60CABUDABgACQmVI60CABUDAAAA.Vanz:BAAALgADCgIJAgAAAA==.Varnos:BAAALgAECgEJAwAAAA==.',
Ve='Velranis:BAAALgADCgMJAwABLgAECggJEgAMAAAAAA==.Velthas:BAAALgADCggJIQAAAA==.',
Vi='Virmethir:BAABLgAECn8XAAMUAAYJ+QlmDgDgAAAUAAYJ+QlmDgDgAAAIAAUJDwMpVQCAAAAAAA==.Viruz:BAAALgADCgcJCgAAAA==.',
Vo='Volley:BAAALgADCgEJAQAAAA==.Voltaren:BAAALgAECgYJBgABLgAECgkJIwASAHscAA==.',
Vy='Vylaran:BAAALgADCgYJBgAAAA==.Vyndrolan:BAAALgAECgYJDgAAAA==.Vyroth:BAAALgADCgUJBQAAAA==.',
Wa='Walksonwater:BAAALgADCgEJAQABLgAECggJHQAEAB4dAA==.Waq:BAAALgAECgYJCQAAAA==.',
We='Wellamor:BAAALgADCgIJAgAAAA==.',
Wi='Winterbreeze:BAAALgADCgYJBgAAAA==.Wiwi:BAABLgAECn8yAAMRAAkJxSEaCwDdAgARAAkJxSEaCwDdAgAnAAMJuxuXEQDbAAAAAA==.',
Xa='Xares:BAABLgAECn8vAAIBAAkJqhr6GgB/AgABAAkJqhr6GgB/AgAAAA==.',
Xe='Xerath:BAAALgADCgcJBwAAAA==.',
Xh='Xhades:BAAALgAECgQJCAAAAA==.',
Ya='Yalda:BAAALgAECgUJDQAAAA==.',
Yf='Yfra:BAAALgAECggJEQAAAA==.',
Yo='Yochangsvegn:BAAALgAECggJEAAAAA==.Yoseph:BAABLgAECn8WAAITAAgJGA9tDwBaAQATAAgJGA9tDwBaAQAAAA==.',
Yu='Yungblood:BAAALgAECgQJBAAAAA==.Yurimancer:BAABLgAECn8pAAIYAAcJXRkCGACzAQAYAAcJXRkCGACzAQAAAA==.',
Za='Zaen:BAAALgADCgMJAwAAAA==.Zake:BAAALgAECgMJBAAAAA==.Zalileina:BAAALgADCgMJAwAAAA==.Zallith:BAAALgADCgMJAwABLgAECgYJDgAMAAAAAA==.Zappythile:BAABLgAECn8nAAICAAgJJBxuHgACAgACAAgJJBxuHgACAgAAAA==.Zarkamental:BAAALgADCgYJCwABLgAFFAMJBQAGAEcCAA==.Zarthos:BAAALgAECgEJAQABLgAECgEJAwAMAAAAAA==.',
Ze='Zect:BAABLgAECn8YAAQkAAYJLB6OBwCLAQAkAAYJOBuOBwCLAQAfAAUJZRkEfQACAQAgAAEJFBWsbwA3AAAAAA==.Zelinor:BAAALgADCgcJBwAAAA==.',
Zi='Ziêg:BAAALgADCgcJBwAAAA==.',
Zo='Zoz:BAAALgAECgUJDwAAAA==.',
Zu='Zulfrik:BAABLgAECn8sAAIBAAkJuxY2NgD+AQABAAkJuxY2NgD+AQAAAA==.Zullard:BAAALgAECgEJAQAAAA==.',
Zy='Zyzy:BAAALgAECgQJCQABLgAECggJHgAGAIYgAA==.',
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
