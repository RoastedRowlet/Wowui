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

local lookup = {'DemonHunter-Havoc','Paladin-Retribution','Mage-Frost','Paladin-Holy','Priest-Discipline','Priest-Holy','Hunter-BeastMastery','Warrior-Fury','Hunter-Survival','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Vengeance','Druid-Balance','Warlock-Demonology','Unknown-Unknown','Warlock-Destruction','DeathKnight-Frost','Monk-Mistweaver','Monk-Brewmaster','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Blood','Paladin-Protection','Priest-Shadow','Warlock-Affliction','Shaman-Restoration','Warrior-Arms','Warrior-Protection','Druid-Restoration','Druid-Feral','Shaman-Elemental','Hunter-Marksmanship','Rogue-Subtlety','DemonHunter-Devourer','Druid-Guardian','Rogue-Assassination','Shaman-Enhancement','Mage-Fire','Mage-Arcane',}
local provider = {region='US',realm='Nordrassil',name='US',type='weekly',zone=46,date='2026-07-05',data={Aa='Aairidari:BAABLgAECn9JAAIBAAkJUhQ9AgC1AQABAAkJUhQ9AgC1AQAAAA==.Aatrox:BAAALgAECgUJBQABLgAECgkJLgACACogAA==.',
Ab='Abruna:BAAALgAECgcJEwABLgAFFAgJHwADAAwXAA==.Abruno:BAACLgAFFH8fAAIDAAgJDBeqEgCEAQADAAgJDBeqEgCEAQAuAAQKfzAAAgMACQmDIgkQAEgDAAMACQmDIgkQAEgDAAAA.Abruto:BAAALgADCgYJBgABLgAFFAgJHwADAAwXAA==.',
Ad='Adrasteia:BAAALgADCgQJAQABLgAFFAQJFwADAPoXAA==.Adrians:BAABLgAECn8qAAIDAAkJuxbTPwAdAgADAAkJuxbTPwAdAgAAAA==.Adunea:BAAALgAECggJDQAAAA==.',
Ae='Aeown:BAABLgAECn82AAMCAAgJVw6AhQBkAQACAAgJVw6AhQBkAQAEAAcJpQnySgAQAQABLgAECgkJTAAFAFgVAA==.Aerdis:BAAALgAECgYJEQABLgAECgkJFgAGAIIRAA==.Aery:BAAALgAFFAEJAwABLgAFFAcJGQAHADEfAA==.',
Ag='Aggerwator:BAAALgAECgEJAwABLgAECggJHQAIACciAA==.',
Ah='Ahsóká:BAAALgAECgQJBQAAAA==.',
Ak='Akames:BAAALgAFFAIJAgABLgAFFAcJEwAJAKIeAA==.Akkani:BAAALgAECgEJAQAAAA==.',
Al='Alahrî:BAACLgAFFH8GAAIKAAMJ2QWTIwCEAAAKAAMJ2QWTIwCEAAAuAAQKfzoABAoACQnzEOoWAOEBAAoACQnzEOoWAOEBAAsABgn+DAcOACsBAAwABwnqCn1EABgBAAAA.Alandira:BAAALgAECgcJCAAAAA==.Alandrìas:BAACLgAFFH8SAAINAAQJFA4GAwDEAAANAAQJFA4GAwDEAAAuAAQKfy0AAg0ACQmcFA4JAN4BAA0ACQmcFA4JAN4BAAAA.Allydari:BAAALgAECgEJAQAAAA==.Aloiss:BAAALgADCgUJCAAAAA==.Alphael:BAAALgADCgYJBgAAAA==.Alror:BAABLgAECn8oAAIOAAkJsB3WBQA9AwAOAAkJsB3WBQA9AwAAAA==.Altera:BAABLgAECn8+AAIKAAkJahd0CQBQAgAKAAkJahd0CQBQAgAAAA==.',
Am='Amelya:BAABLgAECn8VAAIDAAcJ2gpyyQD7AAADAAcJ2gpyyQD7AAAAAA==.Amethystia:BAAALgADCgYJBgAAAA==.Amirandis:BAAALgAECgYJDAAAAA==.Amuri:BAABLgAECn8eAAICAAgJkhA4cwCHAQACAAgJkhA4cwCHAQAAAA==.',
An='Andelarenn:BAAALgAECgkJCQAAAA==.Andere:BAAALgAECggJDAAAAA==.Androonatorz:BAACLgAFFH8aAAIEAAcJjRmzEAC0AQAEAAcJjRmzEAC0AQAuAAQKfy0AAwQACQkDJV4CAIcDAAQACQkDJV4CAIcDAAIABAn+ETi+AAoBAAAA.Angelø:BAAALgAECgEJAQAAAA==.Antagony:BAABLgAECn8UAAIPAAcJtgxshwArAQAPAAcJtgxshwArAQAAAA==.Antheavari:BAAALgADCgYJBgAAAA==.',
Ar='Ardell:BAEALgAECgYJBgABLgAECgcJAQAQAAAAAA==.Ardemus:BAABLgAECn8XAAMRAAYJIBIFGQDaAAARAAYJIBIFGQDaAAAPAAEJYAAYNAEWAAABLgAFFAIJBwASALgEAA==.Arkena:BAAALgAECgIJAgAAAA==.Arkenai:BAAALgADCgcJDQAAAA==.Arveiturace:BAABLgAECn8hAAIMAAYJuAWgCAChAAAMAAYJuAWgCAChAAAAAA==.',
As='Ashborrn:BAAALgAFFAEJAgAAAA==.Ashtar:BAABLgAECn8eAAIIAAkJpBgSFwA2AgAIAAkJpBgSFwA2AgAAAA==.Ashtomouth:BAAALgAECgYJEQAAAA==.Astorath:BAAALgADCgEJAgAAAA==.Asukajo:BAAALgAECgMJAwAAAA==.',
Au='Aura:BAAALgAECgYJCgABLgAECgkJIgATAJEWAA==.',
Av='Averyi:BAAALgAECgIJAgAAAA==.',
Aw='Awake:BAAALgAECgEJAgAAAA==.Awaken:BAABLgAECn8dAAIDAAgJaiKoGwC2AgADAAgJaiKoGwC2AgAAAA==.Awoomonk:BAABLgAECn8VAAQUAAYJnyJFFwDvAQAUAAYJYyJFFwDvAQAVAAUJ9xmpJwB7AQATAAEJSBKdtwA3AAAAAA==.',
Ax='Axhure:BAAALgAECgEJAQAAAA==.',
Az='Azorei:BAAALgADCgIJAgAAAA==.',
Ba='Baconegg:BAACLgAFFH8aAAMWAAYJgBZIQwBuAQAWAAUJgBZIQwBuAQAXAAEJAACdYQAAAAAuAAQKfyEAAhYACAlFIWEVAPsCABYACAlFIWEVAPsCAAAA.Baelzharon:BAAALgAECgMJAwAAAA==.Balddrex:BAAALgAECgQJBAAAAA==.Balefire:BAACLgAFFH8IAAIPAAQJQBKGUwAfAQAPAAQJQBKGUwAfAQAuAAQKfywAAw8ACQmRHZscAHkCAA8ACQmRHZscAHkCABEAAgntGMY5AEEAAAAA.Bamboom:BAAALgADCgQJBAAAAA==.Barma:BAAALgADCgcJBwAAAA==.Barraki:BAAALgAECgQJBQABLgAECgkJLwAHAO8PAA==.Basili:BAAALgADCgUJBwAAAA==.',
Bd='Bd:BAAALgAECgEJAwAAAA==.',
Be='Bedown:BAAALgAECgMJAwABLgAECgUJCQAQAAAAAA==.Beeper:BAAALgAECgYJBgAAAA==.Beldanner:BAAALgADCgkJDAAAAA==.Beltirra:BAAALgAECggJEwAAAA==.Benan:BAAALgADCgUJBQAAAA==.Bengalnug:BAAALgADCgQJBAAAAA==.',
Bh='Bhangbros:BAAALgAFFAEJAQAAAA==.',
Bi='Bigwill:BAABLgAECn9BAAIDAAkJxSF4EwDlAgADAAkJxSF4EwDlAgAAAA==.',
Bl='Blackfeet:BAAALgAECgYJBwAAAA==.Blango:BAAALgAECgMJAwAAAA==.Blargy:BAACLgAFFH8PAAIOAAQJLhOOIQAUAQAOAAQJLhOOIQAUAQAuAAQKf0QAAg4ACQk+Hg0JAMICAA4ACQk+Hg0JAMICAAAA.Blex:BAAALgADCggJCAAAAA==.Bloodshed:BAAALgAECgYJDAAAAA==.Bluewaffles:BAAALgAECgQJBgABLgAECgYJDwAQAAAAAA==.',
Bo='Borealzombie:BAAALgAECgYJCgABLgAECgkJJgAYAN8cAA==.Boudicah:BAAALgADCgEJAQAAAA==.',
Br='Braicel:BAACLgAFFH8hAAIZAAgJmB3SBQAgAgAZAAgJmB3SBQAgAgAuAAQKfzIAAhkACQnkJHQDACoDABkACQnkJHQDACoDAAAA.Breedableram:BAAALgADCgYJBgABLgAECgkJHwAaAFwZAA==.Brimara:BAAALgAFFAIJAwAAAA==.Brothaagamor:BAAALgAECgEJAQAAAA==.Brunomirror:BAAALgAECgkJDwABLgAFFAgJHwADAAwXAA==.Brythorn:BAAALgADCgEJAQAAAA==.',
Bu='Bubbleosevên:BAAALgADCgkJDgABLgAECggJGAAHAKIfAA==.Bucketojoy:BAAALgAECgIJAgABLgAECgkJPQABALgSAA==.Bunsen:BAAALgAECgEJAQABLgAFFAQJFgAbAHsdAA==.',
['Bì']='Bìgred:BAAALgADCgEJAQAAAA==.',
Ca='Cacadookie:BAAALgAECgEJAQAAAA==.Calegorm:BAAALgADCgYJCwAAAA==.Caliburne:BAABLgAECn8jAAQcAAgJnyCwBwB7AgAcAAgJjSCwBwB7AgAdAAcJTx2uEwC0AQAIAAYJGw+dUQBiAQAAAA==.Caliypso:BAAALgAECgYJCQAAAA==.Cambro:BAABLgAECn8WAAMCAAYJehnygAB4AQACAAYJTRnygAB4AQAYAAEJpgRBSQAgAAAAAA==.Candie:BAAALgAECgEJAwAAAA==.Candierain:BAAALgAECgEJAgAAAA==.Canoe:BAABLgAECn8qAAQOAAgJYhd9KwCmAQAOAAcJBBV9KwCmAQAeAAcJkRdCTQBaAQAfAAIJ+gANOwAYAAAAAA==.Captinsano:BAAALgAECgIJAQABLgAECggJHAAWALsPAA==.Capz:BAACLgAFFH8+AAMcAAkJgCMpAABHAgAcAAkJGiMpAABHAgAIAAUJqCJVBwB3AQAuAAQKfyYAAxwACQnRIzwDANsCABwACAkCJTwDANsCAAgACQktHq4PANUCAAAA.Carcaradon:BAAALgAECgEJAwAAAA==.Carta:BAAALgAECgUJDAAAAA==.Case:BAAALgAECgEJAgAAAA==.Cassius:BAAALgAECgEJAgAAAA==.Caulfield:BAAALgAECgEJAQAAAA==.',
Cc='Ccstarscream:BAAALgAECggJCwAAAA==.',
Cd='Cdlam:BAAALgAECgQJBAAAAA==.',
Ce='Ceez:BAAALgAECggJDwAAAA==.Ceezinator:BAAALgAECgQJBAAAAA==.Cefteldore:BAAALgADCgcJBwAAAA==.Celebrïmbor:BAAALgAECgMJAgAAAA==.',
Ch='Chair:BAAALgAECggJEQABLgAFFAQJFwADAPoXAA==.Chiyori:BAAALgADCgIJAQAAAA==.Chokehold:BAAALgADCgMJAwAAAA==.Chopperr:BAAALgAECgYJCQABLgAFFAIJAgAQAAAAAA==.Chèn:BAAALgAECgYJCwAAAA==.',
Ci='Cindrella:BAACLgAFFH8XAAIDAAQJ+hdyJAD6AAADAAQJ+hdyJAD6AAAuAAQKfz4AAgMACQnDIIkPAP4CAAMACQnDIIkPAP4CAAAA.Circa:BAAALgADCgIJAgAAAA==.',
Cl='Clani:BAAALgADCgIJAgAAAA==.Clayre:BAACLgAFFH8TAAIRAAcJGBCnAgC+AQARAAcJGBCnAgC+AQAuAAQKf0gAAhEACQlhJWIAAFADABEACQlhJWIAAFADAAAA.Clow:BAABLgAECn8dAAMIAAgJJyLMGgB1AgAIAAcJqiPMGgB1AgAcAAMJaB72KgCcAAAAAA==.',
Co='Comparabull:BAAALgADCgcJEQABLgAECgkJIQADALMPAA==.Coolcrush:BAABLgAECn8+AAMVAAkJyiXEAQBZAwAVAAkJTyXEAQBZAwAUAAkJuSFWAwAdAwAAAA==.Corven:BAACLgAFFH8dAAIPAAgJmBRmHADlAQAPAAgJmBRmHADlAQAuAAQKf04AAw8ACQlPI4gFADcDAA8ACQlPI4gFADcDABoAAQkAALk0ADIAAAAA.Corvenicus:BAAALgAECgMJAwABLgAFFAgJHQAPAJgUAA==.',
Cr='Crashbash:BAAALgADCgMJAwAAAA==.Crenty:BAAALgAECgIJBAABLgAECgkJJgATAB0YAA==.Crosis:BAAALgAECgYJDgAAAA==.Crossfaded:BAAALgAECgkJEgAAAA==.Cryovox:BAAALgAECgUJBQAAAA==.Crôwley:BAAALgAECgQJCQAAAA==.',
Cu='Cumazzing:BAACLgAFFH8hAAICAAgJ/CJeAgDeAgACAAgJ/CJeAgDeAgAuAAQKfyoAAgIACQmJJrYCAK4DAAIACQmJJrYCAK4DAAAA.',
Da='Daalletra:BAEALgAECgYJBgABLgAECgcJAQAQAAAAAA==.Dadrin:BAAALgADCgkJQQAAAA==.Daedyxes:BAABLgAECn9PAAIXAAkJBxxWAQAgAgAXAAkJBxxWAQAgAgAAAA==.Daerodos:BAAALgAECgUJCgAAAA==.Daiskei:BAAALgAECgcJDAAAAA==.Dangerr:BAAALgADCgcJBwAAAA==.Daní:BAAALgAECgQJBQAAAA==.Darfretail:BAABLgAECn8rAAIIAAkJhR5JCQDNAgAIAAkJhR5JCQDNAgAAAA==.Dargrum:BAAALgAECgYJBgAAAA==.Darkdemon:BAAALgAECgMJAwAAAA==.Darkmagi:BAAALgAECgMJBAAAAA==.Dasherdeez:BAAALgAECgQJCwAAAA==.Daygath:BAACLgAFFH8HAAIgAAIJmApkRwBwAAAgAAIJmApkRwBwAAAuAAQKfzEAAiAACQlvFe0bAAICACAACQlvFe0bAAICAAAA.',
De='Deadlyiris:BAACLgAFFH8LAAMcAAMJCBDUCgDMAAAcAAMJ/Q/UCgDMAAAIAAEJoREyJgBKAAAuAAQKfy8AAxwACQnfIt4CABIDABwACQnfIt4CABIDAAgABgkfEJlKAHsBAAEuAAUUBAkWABsAex0A.Deadshot:BAAALgAECgEJAQAAAA==.Deatharin:BAAALgAECgYJDQAAAA==.Decompose:BAAALgAECgEJAwAAAA==.Demonbulio:BAABLgAECn84AAIBAAkJFBbJEAAcAgABAAkJFBbJEAAcAgAAAA==.Demonisthicc:BAAALgAECgMJBQABLgAECgkJHwAaAFwZAA==.Demonlorrd:BAAALgAECgIJAgABLgAECgQJEAAQAAAAAA==.Demonskitten:BAABLgAECn8fAAIaAAkJXBlQBAA8AgAaAAkJXBlQBAA8AgAAAA==.Demonslayeer:BAAALgAECgEJAQAAAA==.Descendantt:BAAALgAECgEJAQAAAA==.Devilbullet:BAAALgADCgIJAwAAAA==.Devlyne:BAAALgADCgMJAwAAAA==.',
Di='Ding:BAAALgAECgYJEAAAAA==.Direwolf:BAAALgAECgQJBQAAAA==.Dirtyearl:BAABLgAECn84AAICAAkJtxRLXAC5AQACAAkJtxRLXAC5AQAAAA==.Dithehealer:BAABLgAECn8kAAMYAAkJYCB3AwDcAgAYAAkJYCB3AwDcAgACAAEJmQdyTAEuAAAAAA==.Divain:BAAALgADCgEJAQAAAA==.Divinecandie:BAAALgAECgEJAQAAAA==.',
Dk='Dkdi:BAABLgAECn8ZAAIXAAkJBSAfBQDaAgAXAAkJBSAfBQDaAgAAAA==.',
Do='Doalina:BAAALgADCgQJBgAAAA==.Domidia:BAABLgAECn8gAAIDAAYJQR6ZcQDwAQADAAYJQR6ZcQDwAQAAAA==.Donkeyshot:BAAALgAECgQJCgABLgAECgkJMwAhABUYAA==.Doogie:BAAALgAECgEJCAAAAA==.Dortak:BAAALgADCgQJBAABLgAECgUJDwAQAAAAAA==.',
Dr='Dracon:BAAALgADCgkJCQAAAA==.Draconfel:BAAALgAECgYJCQAAAA==.Draglone:BAAALgADCgMJAwABLgAECgYJBgAQAAAAAA==.Dragonlife:BAAALgADCgIJAgAAAA==.Dragømir:BAAALgAFFAIJAgABLgAFFAUJCAAMAMkCAA==.Dranåk:BAAALgAECgQJBAAAAA==.Drbadtouch:BAAALgAECgEJAQAAAA==.Dreamfyres:BAACLgAFFH8YAAMLAAcJQRvpAQB9AQALAAUJBCHpAQB9AQAMAAUJ6BmxIQBSAQAuAAQKfysAAwsACQkmJQcBAF0DAAsACAmKJQcBAF0DAAwACQkqJGIDADoDAAAA.Drenamai:BAABLgAECn8hAAIHAAkJMBMxPADvAQAHAAkJMBMxPADvAQAAAA==.Drewetta:BAABLgAECn9AAAIOAAkJjBSPAwBgAQAOAAkJjBSPAwBgAQAAAA==.Drmombo:BAAALgAECgQJAwAAAA==.',
Du='Duhmptruhk:BAAALgAECgYJCwABLgAECgcJBwAQAAAAAA==.Durbana:BAAALgAECgUJCgAAAA==.Duskariel:BAAALgADCgMJBAAAAA==.Duskfire:BAAALgAECgEJAQAAAA==.',
Dy='Dyson:BAAALgAECgcJEgAAAA==.',
['Dé']='Démonicblood:BAABLgAECn8UAAMSAAYJqBckEgBWAQASAAYJcBYkEgBWAQAXAAIJ9xQ/WAA+AAAAAA==.',
Ed='Edrocz:BAEALgAECgcJAQAAAA==.',
Eh='Ehmehzing:BAACLgAFFH8gAAICAAUJ0iaCFADGAQACAAUJ0iaCFADGAQAuAAQKfzoAAgIACQkGJq4BAMgDAAIACQkGJq4BAMgDAAEuAAUUCAkhAAIA/CIA.',
Ek='Ekhart:BAAALgAECgEJAQAAAA==.',
El='Elandin:BAAALgAECggJDwAAAA==.Elghtyelght:BAAALgAECgUJBwAAAA==.Eliicia:BAACLgAFFH8TAAIiAAcJ2AuxEQCCAQAiAAcJ2AuxEQCCAQAuAAQKfxYAAiIACQmBDSEmAMgBACIACQmBDSEmAMgBAAAA.Elvwyr:BAAALgAECggJDAAAAA==.',
Em='Embarrassed:BAAALgADCggJFwAAAA==.Emmetcullen:BAACLgAFFH8SAAMgAAcJyBl3CABXAQAgAAYJXRl3CABXAQAbAAEJ9whmewBIAAAuAAQKfyAAAyAACAkkHtkTAIACACAACAkkHtkTAIACABsABAk3Cat1ALoAAAAA.Emmy:BAABLgAECn8UAAIGAAYJxyAuKgCiAQAGAAYJxyAuKgCiAQAAAA==.Emogothbabe:BAAALgAFFAIJAgABLgAFFAIJAgAQAAAAAA==.Emryss:BAAALgAECgIJAgAAAA==.',
En='Endo:BAABLgAFFH8LAAMWAAYJ1humHQAtAQAWAAUJBiCmHQAtAQASAAMJCBTHCwCfAAABLgAFFAYJFwABAPMeAA==.Endorush:BAACLgAFFH8XAAQBAAYJ8x70AQB7AQABAAQJqB30AQB7AQAjAAYJDRYbMQBhAQANAAEJECe3AwB2AAAuAAQKfz8AAwEACQl9JXMAAOgDAAEACQl8JXMAAOgDACMACQm1IuYFACwDAAAA.Eneldenes:BAABLgAFFH8FAAMkAAIJ3B7cLwBdAAAkAAEJDyHcLwBdAAAeAAEJfgLnfQAkAAAAAA==.Enjoyer:BAAALgAECggJEgABLgAECgkJGgAOABcPAA==.',
Er='Ereitherla:BAABLgAECn89AAIHAAkJhg93WQCYAQAHAAkJhg93WQCYAQAAAA==.',
Es='Eshaia:BAAALgADCgQJBAAAAA==.Espressð:BAAALgAFFAIJAgAAAA==.',
Ev='Evanthe:BAAALgADCgEJAgAAAA==.',
Ex='Excalibear:BAABLgAECn8vAAIEAAkJPRaSJQDbAQAEAAkJPRaSJQDbAQABLgAFFAYJFgADAMocAA==.',
Ey='Eydis:BAAALgADCgkJIAAAAA==.Eyepisspeas:BAAALgADCgEJAQAAAA==.',
Ez='Ezra:BAAALgADCgkJFwAAAA==.',
Fa='Faithchill:BAAALgAECgMJAwAAAA==.Farc:BAAALgAECgUJBgAAAA==.Fatherjeff:BAAALgADCgkJDQAAAA==.Fayith:BAAALgADCgEJAQAAAA==.',
Fe='Feironor:BAAALgAECggJCwAAAA==.Feldown:BAAALgAECgYJBwAAAA==.Felryno:BAAALgADCgQJBAAAAA==.Fenrys:BAAALgADCgIJAgAAAA==.Feyrre:BAAALgAECgMJAwAAAA==.',
Fi='Fircey:BAAALgAECgEJAQABLgAECgkJFQAWAKwcAA==.Fistbroz:BAABLgAECn8eAAMkAAkJ8xVHEgDMAQAkAAkJFBRHEgDMAQAfAAcJDxUeFAB/AQABLgAFFAgJIgAUAFgPAA==.',
Fl='Flawpeacok:BAABLgAECn8cAAIWAAkJPxjvRwDqAQAWAAkJPxjvRwDqAQAAAA==.Fleredil:BAABLgAECn9IAAMZAAkJqSGwBQD4AgAZAAkJqSGwBQD4AgAGAAgJzRrAEQBSAgAAAA==.Flingernle:BAAALgAECgEJAwAAAA==.Floista:BAAALgAECggJDQAAAA==.Floistas:BAABLgAFFH8LAAIHAAMJWBPVXwDlAAAHAAMJWBPVXwDlAAAAAA==.',
Fo='Forepray:BAAALgAFFAEJAQABLgAFFAgJHgAIABQVAA==.Forger:BAABLgAECn81AAIdAAkJTBj+DAAaAgAdAAkJTBj+DAAaAgAAAA==.Forsakey:BAAALgAECgUJDgABLgAFFAYJEQAeAB8ZAA==.Foxfireii:BAAALgADCgMJAwAAAA==.',
Fr='Freshdk:BAACLgAFFH8UAAQWAAUJaiSaRABrAQAWAAQJaiSaRABrAQASAAQJLhe/EAAQAQAXAAEJAABZYAAAAAAuAAQKfzYABBYACQkFJHAMADcDABYACQkDJHAMADcDABIACAlhIbkHABkCABcAAQljDnVBAEYAAAAA.Freÿa:BAAALgADCgYJBgABLgAFFAEJBQAPANwaAA==.Frostgash:BAAALgADCgcJDAAAAA==.Frostitution:BAAALgAECgEJAQAAAA==.Frostycheeks:BAACLgAFFH8hAAMWAAUJbBtGGwA7AQAWAAQJbBtGGwA7AQAXAAUJ7gmxDgCvAAAuAAQKfz4AAhYACAloIy0gAIgCABYACAloIy0gAIgCAAAA.Frostywaffle:BAAALgAECgEJAQAAAA==.',
Fu='Fubuki:BAAALgADCgEJAQAAAA==.Fudgetracks:BAAALgADCgYJBgAAAA==.Futaccine:BAABLgAECn8oAAQjAAgJ0CJzHwBYAgAjAAgJlyJzHwBYAgANAAIJqiPkKABgAAABAAIJTxj8ZgA/AAAAAA==.Future:BAAALgAECgYJDwABLgAFFAMJCAAaACwbAA==.Fuzzycat:BAAALgADCgEJAQAAAA==.',
Ga='Gaav:BAAALgAECgUJBwABLgAECggJHQAIACciAA==.Gaerlan:BAAALgAECgUJDQAAAA==.Galvquodiyu:BAAALgAECgcJCQAAAA==.Garlic:BAAALgADCgEJAQAAAA==.',
Ge='Geekbarr:BAAALgAECgQJBgABLgAFFAIJAgAQAAAAAA==.',
Gh='Ghettox:BAAALgAECgYJCQAAAA==.Ghostblades:BAACLgAFFH8aAAMWAAcJDxkiNQCVAQAWAAcJDxkiNQCVAQASAAEJAAB/LwAAAAAuAAQKfysAAxYACQmBIYYXALkCABYACQmBIYYXALkCABIAAQnbHDcWADgAAAAA.Ghostdk:BAAALgAECgEJAgAAAA==.Ghostsham:BAAALgADCgMJAwAAAA==.Ghuleh:BAAALgAECgEJAgAAAA==.',
Gi='Gilffy:BAAALgADCgkJCgAAAA==.Gizik:BAAALgAECgIJBwABLgAFFAkJIgAZAMwXAA==.',
Gl='Gloomybear:BAAALgADCgUJBQAAAA==.',
Go='Golgotterath:BAABLgAFFH8IAAIbAAYJ9AubIgBlAQAbAAYJ9AubIgBlAQABLgAFFAYJFgADAMocAA==.Gorm:BAAALgAECgQJBAABLgAFFAIJBwAWAMggAA==.',
Gr='Gratata:BAAALgAECgMJBQABLgAECgkJJgATAB0YAA==.Grimzero:BAAALgADCgMJAwAAAA==.Grinnee:BAABLgAECn8bAAMlAAkJ4w4oCADMAQAlAAkJMQ4oCADMAQAiAAQJ7Q7oOADtAAABLgAECgkJTAACADoiAA==.Grinny:BAABLgAECn9MAAMCAAkJOiK+CQAaAwACAAkJOiK+CQAaAwAEAAIJowMyjQBKAAAAAA==.Grobthar:BAAALgADCgYJBgAAAA==.',
Gu='Gunna:BAAALgAECgIJAgABLgAFFAMJCAAaACwbAA==.',
Ha='Hadariel:BAAALgAECgcJCQAAAA==.Halbruck:BAAALgAFFAEJAQAAAA==.Haldane:BAABLgAECn8qAAICAAkJ8gxydgCBAQACAAkJ8gxydgCBAQABLgAFFAQJFgAbAHsdAA==.Havochunter:BAABLgAECn8YAAIHAAcJoh9+OgD1AQAHAAcJoh9+OgD1AQAAAA==.',
He='Heidegger:BAAALgAECgQJCQAAAA==.Helenkeller:BAAALgAECgIJAgAAAA==.Henderson:BAAALgADCgQJBAAAAA==.Heraois:BAABLgAECn8zAAIhAAkJFRh3BgAsAgAhAAkJFRh3BgAsAgAAAA==.Heriod:BAAALgAECgYJCQAAAA==.Hexy:BAAALgAECgUJCAAAAA==.',
Hi='Highblood:BAAALgAECgUJBgAAAA==.',
Ho='Holytës:BAAALgAECgUJCgAAAA==.Holywráth:BAABLgAECn8XAAICAAcJlwziGQClAAACAAcJlwziGQClAAAAAA==.Horndoggie:BAAALgAECgYJBgAAAA==.Hotea:BAAALgAECgUJCgAAAA==.',
Hp='Hpsnotdps:BAAALgAECgcJEwAAAA==.',
Hu='Hucklebeary:BAAALgADCgYJBgAAAA==.Huell:BAABLgAECn8VAAMiAAgJthRsGgDFAQAiAAgJthRsGgDFAQAlAAEJ2REbJgA7AAAAAA==.Hunterdh:BAABLgAECn82AAIHAAkJKQzAEQDvAAAHAAkJKQzAEQDvAAAAAA==.',
Hy='Hynesh:BAAALgAECgYJCwAAAA==.Hynixx:BAACLgAFFH8eAAIIAAgJFBXQCADSAQAIAAgJFBXQCADSAQAuAAQKfzAAAggACQkIIRQMAKgCAAgACQkIIRQMAKgCAAAA.',
Ic='Icecandie:BAAALgAECgYJEgAAAA==.',
Il='Illidope:BAAALgAECgcJDAABLgAFFAcJGAALAEEbAA==.Ilostthegame:BAAALgADCgIJAgABLgAECgkJTAAFAFgVAA==.',
Im='Imistmypants:BAABLgAECn8mAAITAAkJHRjuEwB8AgATAAkJHRjuEwB8AgAAAA==.',
In='Infinitevoid:BAAALgADCgUJDAAAAA==.Innervatez:BAABLgAFFH8YAAIeAAgJ4hxUBADZAgAeAAgJ4hxUBADZAgAAAA==.Inspectda:BAABLgAECn8VAAIPAAgJgwcadgBxAQAPAAgJgwcadgBxAQAAAA==.',
Io='Ionúin:BAAALgAECgQJBAAAAA==.',
Is='Issel:BAAALgAECgYJCwAAAA==.',
Iy='Iyaasu:BAABLgAECn8cAAIKAAgJJBt9CwAiAgAKAAgJJBt9CwAiAgAAAA==.Iyahliea:BAAALgAECgIJAgAAAA==.',
Ja='Jaeger:BAAALgAECggJEAAAAA==.Jaekir:BAABLgAECn84AAIDAAkJORY0RAAPAgADAAkJORY0RAAPAgAAAA==.Jakbandit:BAAALgADCgEJAQAAAA==.Jakey:BAAALgAECgYJDAAAAA==.Jakfrost:BAABLgAECn9HAAIDAAkJHSVnCgAmAwADAAkJHSVnCgAmAwAAAA==.Jaquio:BAAALgAECgEJAQAAAA==.Jarten:BAABLgAECn83AAISAAkJqiKDAQAhAwASAAkJqiKDAQAhAwAAAA==.Jaylebate:BAABLgAECn9OAAMWAAkJaiJMAgCCAgAXAAkJCB7qAACJAgAWAAkJzCFMAgCCAgAAAA==.',
Je='Jerrenn:BAABLgAECn8eAAMCAAkJqBjUQAAEAgACAAgJ3hfUQAAEAgAEAAIJLwlfeQBaAAAAAA==.Jesseatamer:BAACLgAFFH8HAAIHAAMJ/iF4JgDQAAAHAAMJ/iF4JgDQAAAuAAQKfzoAAgcACQmaJscAAJIDAAcACQmaJscAAJIDAAAA.',
Jo='Jolt:BAAALgADCgEJAQAAAA==.Jortak:BAAALgAECggJEwABLgAECgkJTgAWAGoiAA==.Jouska:BAAALgAECgYJCwABLgAECgcJBwAQAAAAAA==.',
Ju='Judge:BAAALgAECgEJAgAAAA==.Julesx:BAAALgAFFAEJAQAAAA==.Justar:BAAALgADCgMJBQAAAA==.',
['Jë']='Jësus:BAAALgAECgcJDgAAAA==.',
Ka='Kaera:BAAALgAECgYJDgAAAA==.Kakamora:BAABLgAECn8UAAMhAAgJGhleEABVAQAHAAgJbBZWVQCkAQAhAAcJ/BNeEABVAQABLgAFFAMJBQAgAG0LAA==.Kakushin:BAAALgAECgEJAQAAAA==.Kaldór:BAAALgADCgIJAgAAAA==.Kalmek:BAABLgAECn8UAAIWAAkJVBboRgDuAQAWAAkJVBboRgDuAQAAAA==.Karen:BAAALgAECgUJDQABLgAECgkJOAACALcUAA==.Karne:BAAALgADCgEJAQAAAA==.Karold:BAAALgADCgUJBgAAAA==.Kartian:BAAALgAECgEJBAAAAA==.Karyana:BAAALgAFFAMJAwAAAA==.Kastia:BAABLgAECn8WAAIDAAYJlxCUEQDrAAADAAYJlxCUEQDrAAAAAA==.Katrynwel:BAABLgAECn8hAAIDAAkJsw/nfQB8AQADAAkJsw/nfQB8AQAAAA==.Katsumi:BAAALgAECgIJAgAAAA==.Kaylestia:BAAALgAECgkJCQAAAA==.Kaylinne:BAAALgAECgEJAQAAAA==.',
Ke='Keení:BAAALgADCgkJCQAAAA==.Kellenah:BAAALgADCgkJIgAAAA==.Kettama:BAAALgAECgEJAQABLgAFFAIJAgAQAAAAAA==.',
Kh='Khainen:BAAALgAECgQJBAAAAA==.Khaliana:BAAALgADCgEJAQAAAA==.Khold:BAABLgAECn8VAAMWAAgJIhd3UQDPAQAWAAcJkRl3UQDPAQASAAcJTQbTHQDeAAAAAA==.',
Ki='Killalltoday:BAABLgAECn9CAAMbAAkJPxK7SQCIAQAbAAkJPxK7SQCIAQAmAAgJNg5SEwCDAQAAAA==.Killersmile:BAAALgADCgkJCQAAAA==.Kilon:BAAALgAFFAEJAQAAAA==.Kirkk:BAABLgAECn8WAAIEAAYJIhc+MACZAQAEAAYJIhc+MACZAQAAAA==.Kivareous:BAAALgAFFAIJAwAAAA==.Kixarea:BAAALgADCgkJDQABLgAFFAIJAwAQAAAAAA==.',
Kn='Kneesweak:BAAALgAECgQJBgAAAA==.Knexx:BAABLgAECn8ZAAIXAAgJsxZXFQDCAQAXAAgJsxZXFQDCAQAAAA==.Knixx:BAACLgAFFH8aAAMZAAYJwg/SBAB5AQAZAAUJtg/SBAB5AQAFAAUJeAiqMADPAAAuAAQKf0YABBkACQmlGkAMAIwCABkACQmlGkAMAIwCAAYABwk6GGQbAAECAAUABgldEMYtADABAAAA.Knotty:BAAALgADCgYJDQAAAA==.Knuppelus:BAAALgADCgIJAgAAAA==.',
Ko='Kotalyst:BAABLgAECn8dAAIUAAkJUxEBJwB4AQAUAAkJUxEBJwB4AQAAAA==.Kotastrophe:BAAALgAECgcJBwAAAA==.Koveras:BAAALgADCgkJCwAAAA==.Koyaanis:BAABLgAECn8rAAITAAkJmhhRFQBvAgATAAkJmhhRFQBvAgAAAA==.Koyya:BAAALgAFFAIJBAAAAA==.',
Ku='Kufoo:BAABLgAECn9CAAMIAAkJeCaxAQBjAwAIAAkJoSWxAQBjAwAdAAkJ0SWBBADcAgAAAA==.Kuma:BAAALgAECgUJCQABLgAFFAMJCAAaACwbAA==.Kuraikage:BAAALgADCgEJAQAAAA==.Kurao:BAAALgAECgMJAwAAAA==.Kurukai:BAAALgADCgUJBgAAAA==.',
Ky='Kynlerrine:BAABLgAECn8gAAINAAkJkxccBgA4AgANAAkJkxccBgA4AgAAAA==.Kyokushin:BAAALgAECgMJAwAAAA==.Kyzo:BAAALgAECgkJDwAAAA==.',
['Ké']='Kéndra:BAAALgAECgMJAwAAAA==.',
La='Ladiable:BAAALgAECgYJDAABLgAFFAYJHQAHAA0hAA==.Laggyboi:BAAALgAECgYJCAAAAA==.Lansseax:BAABLgAECn8aAAMZAAkJ7BDcAgCNAQAZAAkJ7BDcAgCNAQAFAAIJVwWQbgBOAAAAAA==.Laraelin:BAAALgADCgYJBgAAAA==.Lascerette:BAAALgAECgYJCgAAAA==.Law:BAAALgADCgcJEQAAAA==.Layez:BAAALgAECgEJAQABLgAECgkJFQAWAKwcAA==.',
Le='Leguan:BAAALgADCgkJDQAAAA==.Leo:BAAALgAFFAEJAQAAAA==.Lethe:BAAALgAECgcJCAABLgAFFAcJEwAiANgLAA==.',
Li='Likestoflash:BAEALgAECgYJEAABLgAECgkJMAAHAAAbAA==.Lilgeeked:BAAALgADCgcJDAAAAA==.Liliannarose:BAAALgADCgEJAQABLgAECgIJBAAQAAAAAA==.Lilyröse:BAAALgAECgIJBAAAAA==.',
Lo='Locklove:BAAALgADCgkJCQAAAA==.Lohal:BAACLgAFFH8FAAIPAAMJnguNJADEAAAPAAMJnguNJADEAAAuAAQKfzoAAg8ACQkVG/EoADgCAA8ACQkVG/EoADgCAAAA.Lohmi:BAAALgAECgYJDAAAAA==.Lolalashay:BAAALgAECgMJBwAAAA==.Lorilock:BAAALgADCgUJBQAAAA==.Loudawn:BAACLgAFFH8MAAIOAAQJ6gJnFQB4AAAOAAQJ6gJnFQB4AAAuAAQKfywAAg4ACQkIC0IsAHYBAA4ACQkIC0IsAHYBAAAA.',
Lu='Luania:BAABLgAECn8aAAIHAAYJ3hMtDwAOAQAHAAYJ3hMtDwAOAQAAAA==.Lufselda:BAAALgAECgEJAQAAAA==.Lupo:BAAALgAECgEJAQAAAA==.Lurtz:BAABLgAECn8YAAIHAAYJ4BY3bwBiAQAHAAYJ4BY3bwBiAQAAAA==.Lusucio:BAAALgAFFAIJAwAAAA==.',
Ly='Lyberrath:BAAALgAECgIJAwAAAA==.Lyeth:BAAALgAECgMJBAAAAA==.Lyna:BAAALgADCgcJBwAAAA==.Lyzzardkng:BAAALgAECgcJEAAAAA==.',
['Lé']='Lélouch:BAAALgAECgYJBgABLgAFFAcJEgAgAMgZAA==.',
Ma='Maango:BAAALgAECgkJCAAAAA==.Maemu:BAAALgAECgEJAQAAAA==.Magerthat:BAAALgADCgYJBwAAAA==.Magicaltickl:BAABLgAECn9QAAMDAAkJnh7tAQDHAgADAAkJnh7tAQDHAgAnAAMJ/ggeCwCIAAAAAA==.Magiki:BAAALgAECgQJCAAAAA==.Makeawish:BAAALgAFFAEJAQABLgAFFAMJBQAWADoDAA==.Malkala:BAAALgAECgUJCQAAAA==.Malonormu:BAAALgADCgQJBAAAAA==.Mamadeezy:BAAALgAECgcJCQAAAA==.Manical:BAAALgAECgcJEwAAAA==.Mashiach:BAAALgADCgcJBwABLgAFFAUJFgAWAI8WAA==.Maxgoon:BAABLgAECn8WAAIPAAcJwgzVcwB2AQAPAAcJwgzVcwB2AQAAAA==.',
Mc='Mcfist:BAAALgAECgUJBQABLgAECggJEAAQAAAAAA==.',
Me='Megumin:BAABLgAECn8cAAQDAAgJdhNFZgCxAQADAAgJ7hJFZgCxAQAnAAMJeA/pDACZAAAoAAIJ3xNtGgBEAAABLgAECgkJLgACACogAA==.Mellisandria:BAAALgAECgcJEQAAAA==.Melodious:BAAALgADCgYJCQAAAA==.Merek:BAABLgAECn81AAIUAAkJmCOMAgA0AwAUAAkJmCOMAgA0AwAAAA==.Merriska:BAACLgAFFH8GAAMEAAIJxyC5NwCOAAAEAAIJxyC5NwCOAAACAAEJHRG2uABFAAAuAAQKfxsAAwIACQk1IqElAJACAAIACAlWI6ElAJACAAQACAm7IJsTAHUCAAEuAAUUBwkYABMAyiIA.',
Mi='Miashadow:BAAALgADCgcJDQAAAA==.Miessa:BAAALgAECgEJAQAAAA==.Mikeysmom:BAAALgAECggJEAABLgAECgkJBgAQAAAAAA==.Mirigosa:BAAALgAECggJCAABLgAFFAQJFwADAPoXAA==.Misseslovett:BAAALgAECgcJDAAAAA==.Missmeow:BAAALgADCgYJBgAAAA==.Mistyd:BAACLgAFFH8qAAIkAAgJWhhRAQD5AQAkAAgJWhhRAQD5AQAuAAQKfz0AAiQACQnPHGAHAIACACQACQnPHGAHAIACAAAA.Mithras:BAAALgAECgEJAgAAAA==.',
Mo='Monkar:BAAALgADCgMJAwAAAA==.Monkdiluffy:BAAALgADCgUJBQAAAA==.Moocifer:BAAALgAECgIJAgAAAA==.Moonstriker:BAACLgAFFH8PAAMEAAQJriPHBwA+AQAEAAQJriPHBwA+AQACAAMJYxcgHQDjAAAuAAQKfzMAAwQACQk2JrIBAGgDAAQACQk2JrIBAGgDAAIAAQlhGbpzAUUAAAAA.Morgause:BAABLgAECn8aAAIPAAkJqwnPCAASAQAPAAkJqwnPCAASAQAAAA==.Morijinn:BAAALgAECgQJBQAAAA==.Morllan:BAAALgAECgEJAgAAAA==.Mortyxp:BAAALgADCgIJAgAAAA==.',
Mu='Muirdin:BAABLgAECn8kAAIHAAkJvhF4WwCTAQAHAAkJvhF4WwCTAQAAAA==.',
Mv='Mvp:BAAALgADCgYJBgAAAA==.',
['Má']='Máelyss:BAAALgAECgQJBgAAAA==.',
['Må']='Mångix:BAAALgAECgIJAgAAAA==.',
['Mé']='Mélusine:BAABLgAECn8fAAMcAAkJYCJ9CgBCAgAcAAkJbCF9CgBCAgAIAAUJNRtqTAB0AQAAAA==.',
['Mï']='Mïsterlovett:BAAALgAECgUJBQABLgAFFAEJBQAPANwaAA==.',
Na='Naanomage:BAABLgAECn8UAAIDAAcJBA8EuQAUAQADAAcJBA8EuQAUAQAAAA==.Nacht:BAAALgADCgEJAQABLgAFFAcJEwAJAKIeAA==.Nagakabouros:BAAALgADCgEJAQAAAA==.Nagato:BAAALgADCgcJBwAAAA==.Naksami:BAAALgAECgIJAgAAAA==.',
Ne='Necrotoxin:BAACLgAFFH8FAAIPAAEJ3Bp9vABRAAAPAAEJ3Bp9vABRAAAuAAQKf0QAAw8ACQmhJKMDAFcDAA8ACAmhJKMDAFcDABEAAQkAAPZcAFgAAAAA.Nemoralia:BAAALgAECggJEgAAAA==.Nezuuko:BAAALgADCgUJBwAAAA==.',
Ni='Nibble:BAAALgADCgQJBAAAAA==.Nightsever:BAABLgAECn8YAAMjAAkJrxzhIQCGAgAjAAkJOhrhIQCGAgABAAUJBCGyJgCLAQAAAA==.Nirath:BAABLgAECn9BAAILAAkJ3w2ACACoAQALAAkJ3w2ACACoAQAAAA==.Nitemelduser:BAAALgAECgEJAQAAAA==.Nixilis:BAAALgADCgUJBQAAAA==.',
No='Noiire:BAAALgAFFAIJAwABLgAFFAcJEwAiANgLAA==.Nopal:BAAALgAECgMJAwAAAA==.Nopriest:BAACLgAFFH8XAAIZAAYJ9CHrAwBUAgAZAAYJ9CHrAwBUAgAuAAQKfzUAAhkACQnzJWwBAGcDABkACQnzJWwBAGcDAAAA.Notixx:BAAALgADCgQJBAAAAA==.Notprepared:BAABLgAECn89AAMBAAkJuBLoFgDPAQABAAkJuBLoFgDPAQAjAAMJcAQqBgFEAAAAAA==.Nottisdemon:BAAALgAECgcJDQAAAA==.',
Nu='Nuggy:BAABLgAECn8jAAMTAAkJZRNzCQAkAQATAAgJIRFzCQAkAQAVAAQJSxHUQgD0AAAAAA==.Nullfox:BAAALgADCgUJBQABLgAFFAYJHAAiAHwfAA==.',
Oa='Oakly:BAACLgAFFH8JAAIeAAMJNxO1PwCxAAAeAAMJNxO1PwCxAAAuAAQKfy4AAh4ACAk0HpwTAK4CAB4ACAk0HpwTAK4CAAAA.',
Ob='Obsidian:BAAALgAECggJEAABLgAFFAQJDwAEAK4jAA==.',
On='Onaroll:BAABLgAFFH8GAAITAAMJrgd7SACDAAATAAMJrgd7SACDAAABLgAFFAgJHAAeAJYWAA==.Onehotelf:BAAALgAECgcJEwAAAA==.',
Oo='Ooyagoddess:BAABLgAECn8ZAAIGAAYJWxWDKwBtAQAGAAYJWxWDKwBtAQAAAA==.',
Or='Orenthil:BAAALgAECgEJAQABLgAFFAMJCQACAOseAA==.',
Ot='Otoah:BAAALgAECgYJBgABLgAFFAYJFgAHALYeAA==.',
Oy='Oya:BAAALgADCgIJAgAAAA==.',
Pa='Pacamonk:BAABLgAECn8gAAIVAAYJ2SKhHADKAQAVAAYJ2SKhHADKAQAAAA==.Pacifer:BAAALgAECgEJAQAAAA==.Pamanda:BAAALgAFFAIJAgABLgAFFAcJGAALAEEbAA==.Pann:BAAALgAECgEJAQABLgAECgcJFAAUABYSAA==.Papatiny:BAAALgAECgYJBgAAAA==.Pauon:BAAALgADCgcJBwAAAA==.Pawpatine:BAABLgAECn87AAIgAAkJ6RkVGwAIAgAgAAkJ6RkVGwAIAgAAAA==.Pawsa:BAABLgAECn9EAAMUAAgJUCA2CwCBAgAUAAgJUCA2CwCBAgAVAAgJFhqtFQALAgABLgAFFAIJAgAQAAAAAA==.Pawsome:BAAALgAECgUJCgABLgAECgkJOwAgAOkZAA==.Pawthetic:BAACLgAFFH8cAAIeAAgJlhbKBADaAQAeAAgJlhbKBADaAQAuAAQKfy8AAx4ACQkDITwDAGEDAB4ACQkDITwDAGEDAA4ACQmRGl0PAGkCAAAA.',
Pe='Peelforheals:BAACLgAFFH8KAAIFAAIJLRAgPgCBAAAFAAIJLRAgPgCBAAAuAAQKfywAAxkACAm+GvogAL4BABkABwmhGfogAL4BAAUABwm7FRocALUBAAAA.Penguindemic:BAABLgAECn8sAAIPAAkJaiYbAgBxAwAPAAkJaiYbAgBxAwAAAA==.Pentimus:BAAALgADCgYJCAABLgAECgkJJgATAB0YAA==.Pep:BAABLgAECn8fAAMVAAkJ1x30DAB1AgAVAAkJ1x30DAB1AgATAAEJUwMRcwAgAAAAAA==.Pephunt:BAAALgAECgEJAQAAAA==.Pepperoni:BAAALgAECgcJCAAAAA==.Petruccius:BAACLgAFFH8QAAIOAAUJjRULCwAIAQAOAAUJjRULCwAIAQAuAAQKfzEAAg4ACQmFH1EHAOECAA4ACQmFH1EHAOECAAAA.Pewpewlepew:BAAALgAFFAIJAgAAAA==.',
Ph='Phaedesana:BAAALgADCgkJCQABLgAECgkJKgAjAIoVAA==.Phaeku:BAABLgAECn8qAAIjAAkJihVLMwD4AQAjAAkJihVLMwD4AQAAAA==.Phòenix:BAAALgADCgkJCQAAAA==.',
Pi='Pinksparklez:BAAALgAECgEJAQABLgAECgQJBQAQAAAAAA==.',
Pl='Plaguedr:BAAALgAECgEJAQAAAA==.',
Po='Ponfarr:BAAALgAECgUJBQAAAA==.Poochita:BAAALgADCgEJAQAAAA==.Poppop:BAAALgADCgMJAwAAAA==.Porbles:BAAALgADCgcJBwAAAA==.Porklamb:BAAALgAECgYJEAABLgAECgkJPgAVAMolAA==.Powermonk:BAAALgAECgQJBwAAAA==.',
Pr='Prayre:BAAALgADCgkJFQAAAA==.Prey:BAAALgAECgUJEgAAAA==.Prospa:BAAALgAECgQJCAABLgAFFAIJAgAQAAAAAA==.Prumper:BAACLgAFFH8IAAIDAAQJMglIkAC3AAADAAQJMglIkAC3AAAuAAQKf0MAAgMACQmaIGsnAH0CAAMACQmaIGsnAH0CAAAA.',
Pu='Purah:BAAALgAFFAEJAgAAAA==.',
Py='Pyric:BAAALgAECgEJBAAAAA==.',
Qu='Quesoblanco:BAAALgAECgkJCgAAAA==.',
Qy='Qybxboogiedk:BAAALgAECgYJDAAAAA==.Qybxboogiemo:BAAALgAECgEJAgAAAA==.Qybxboogietk:BAAALgAECgIJAgAAAA==.',
Ra='Rabid:BAAALgAECgEJBAAAAA==.Raghallov:BAAALgAECgMJAwAAAA==.Ragingstorm:BAAALgADCgIJAwAAAA==.Rakshash:BAAALgAECgIJAgAAAA==.Ramzey:BAABLgAECn8wAAIWAAkJPx1OIACIAgAWAAkJPx1OIACIAgAAAA==.Ravokkc:BAAALgADCgUJBgAAAA==.Rawnis:BAAALgAECgEJAQAAAA==.Raylëigh:BAAALgADCgYJBgAAAA==.',
Re='Reaperan:BAAALgADCgEJAQAAAA==.Redbearon:BAAALgAECgkJEwAAAA==.Redroger:BAAALgADCgQJBQAAAA==.Refractrix:BAAALgAECgUJCQAAAA==.Regena:BAABLgAECn9MAAQFAAkJWBUSHwDVAQAFAAkJcw4SHwDVAQAGAAkJUhScIQC2AQAZAAcJdwwACADTAAAAAA==.Relyssa:BAAALgAECgcJDgAAAA==.Remorse:BAACLgAFFH8ZAAIdAAgJLBizCACpAQAdAAgJLBizCACpAQAuAAQKf0sAAh0ACQnxIogCABwDAB0ACQnxIogCABwDAAAA.Required:BAAALgAFFAMJAwABLgAFFAkJLgAjAPsZAA==.Retro:BAABLgAECn8oAAIgAAcJ8wr7UAD0AAAgAAcJ8wr7UAD0AAAAAA==.',
Rh='Rhysara:BAAALgAECgEJAQAAAA==.',
Ri='Rikatree:BAABLgAECn8tAAMeAAkJ+x2LDQDuAgAeAAkJ+x2LDQDuAgAOAAkJoxdjFAAwAgABLgAFFAIJAwAQAAAAAA==.Rim:BAABLgAECn9EAAIbAAkJfB5WCwADAwAbAAkJfB5WCwADAwAAAA==.Rinaren:BAAALgADCgcJCAAAAA==.Risque:BAACLgAFFH8QAAIDAAQJKhc1WAAtAQADAAQJKhc1WAAtAQAuAAQKfyoAAgMACQlIIXUfAKECAAMACQlIIXUfAKECAAAA.',
Ro='Ronard:BAACLgAFFH8HAAIWAAIJthv70gCOAAAWAAIJthv70gCOAAAuAAQKf0kAAhYACQkQJksEAF4DABYACQkQJksEAF4DAAAA.Ronfar:BAACLgAFFH8YAAImAAcJPRT4BQBfAQAmAAcJPRT4BQBfAQAuAAQKf04AAiYACQkLJU0BAC0DACYACQkLJU0BAC0DAAAA.Rook:BAAALgAECggJEAAAAA==.Rootwalker:BAAALgAECgEJAQAAAA==.',
Ru='Rukidingme:BAAALgAECgYJEgAAAA==.Rumonkingme:BAAALgADCgUJBwAAAA==.Runehammer:BAAALgADCgMJAwAAAA==.Rustyglass:BAAALgAECgEJAQAAAA==.Ruttisðir:BAAALgAECgYJBgAAAA==.',
Rw='Rw:BAAALgAECgEJAQAAAA==.',
Ry='Ryhorn:BAABLgAECn8wAAICAAkJbQ3SYgCqAQACAAkJbQ3SYgCqAQAAAA==.Ryno:BAAALgAECgUJBgAAAA==.Ryomensukuna:BAAALgAECgMJAwAAAA==.Ryujin:BAABLgAECn8XAAICAAgJMgpxnwA4AQACAAgJMgpxnwA4AQAAAA==.',
Sa='Sacrifice:BAAALgADCgQJBAAAAA==.Sadcraig:BAAALgADCgYJBgAAAA==.Salo:BAAALgAECgUJCQAAAA==.Sanazenet:BAAALgAECgQJBAAAAA==.Sango:BAAALgADCgMJAwAAAA==.Saronas:BAAALgADCgkJEAABLgAECgkJNwASAKoiAA==.',
Sc='Schrutes:BAAALgADCgEJAQAAAA==.Scootypuffsr:BAAALgAECgYJDgAAAA==.Scootyshooty:BAAALgADCgYJBgAAAA==.Scrap:BAABLgAECn8XAAIVAAcJVBRCLAB+AQAVAAcJVBRCLAB+AQAAAA==.Scubasuiit:BAABLgAECn8dAAQeAAgJdhy3JQAiAgAeAAcJ1By3JQAiAgAOAAYJ+R6FHwADAgAkAAEJGQaYNQAfAAAAAA==.Scubowsuit:BAAALgAECgYJCQAAAA==.',
Se='Sedria:BAAALgADCgQJBAAAAA==.Segarth:BAAALgAFFAEJAgAAAA==.Selen:BAABLgAECn9EAAMEAAkJmiGbBgAjAwAEAAkJmiGbBgAjAwACAAIJDhN7HQCNAAAAAA==.Seleste:BAAALgADCgYJCAAAAA==.Semballin:BAAALgAECgEJAwAAAA==.Semdogg:BAAALgAECgEJAQABLgAECgkJNwABAKQhAA==.Semtex:BAAALgAECgEJAQAAAA==.Seråphiel:BAABLgAECn8pAAIHAAgJXAisfwA/AQAHAAgJXAisfwA/AQAAAA==.Seswatha:BAACLgAFFH8WAAIDAAYJyhyHKwDEAQADAAYJyhyHKwDEAQAuAAQKfzwAAgMACQklJX8FAFcDAAMACQklJX8FAFcDAAAA.',
Sh='Shadowbaron:BAABLgAECn8XAAIZAAgJUxNLAgCzAQAZAAgJUxNLAgCzAQAAAA==.Shadowsnek:BAAALgAECgEJAQAAAA==.Shakras:BAAALgADCgEJAQABLgAECgkJTAAFAFgVAA==.Shaltear:BAAALgAECgYJCAAAAA==.Shamandroo:BAACLgAFFH8HAAIbAAUJhCPKBgCcAQAbAAUJhCPKBgCcAQAuAAQKfxwAAxsACQlaIhoLAAYDABsACQlaIhoLAAYDACAABQnXGOtTAOoAAAEuAAUUBwkaAAQAjRkA.Shamdi:BAAALgADCgYJBgAAAA==.Shawti:BAAALgADCgcJCAAAAA==.Shawtyy:BAAALgADCgEJAQAAAA==.Shenzu:BAAALgAECgYJDgAAAA==.Shmongus:BAABLgAECn8aAAIOAAkJFw9SJQChAQAOAAkJFw9SJQChAQAAAA==.Shocktop:BAABLgAECn8fAAImAAkJrSJiAQAoAwAmAAkJrSJiAQAoAwAAAA==.Shortfuse:BAAALgAECgEJAQABLgAECgUJDAAQAAAAAA==.Shortserkit:BAAALgAECgYJBgAAAA==.Shz:BAAALgAECgEJAQABLgAECgQJCAAQAAAAAA==.Shådowfire:BAAALgAECggJCAAAAA==.Shìft:BAACLgAFFH8SAAIeAAQJLQyUDwDDAAAeAAQJLQyUDwDDAAAuAAQKfzMAAh4ACQlXGS4VAKACAB4ACQlXGS4VAKACAAAA.',
Si='Siercy:BAAALgADCgMJBQAAAA==.Sightofhand:BAAALgAECgEJAQAAAA==.Sillynanny:BAAALgAECgUJCQAAAA==.Simplysauced:BAAALgAECgQJCwABLgAECgkJKAAOALAdAA==.',
Sk='Skuùuß:BAAALgADCgQJBAAAAA==.Skycaller:BAAALgAECgIJAgAAAA==.Skylér:BAAALgADCgkJCQAAAA==.',
Sl='Slighted:BAABLgAECn8jAAQBAAYJVBs3BAAuAQABAAYJVBs3BAAuAQANAAMJPRf+GgDEAAAjAAIJKA3dyABmAAABLgAECgkJHAAHAMUZAA==.Sliizzy:BAAALgADCgYJCQAAAA==.Slimydruid:BAABLgAECn8fAAIkAAgJJCOLBgCUAgAkAAgJJCOLBgCUAgAAAA==.Slizz:BAAALgADCgYJCwAAAA==.Slizzard:BAAALgADCgYJDAAAAA==.Slow:BAABLgAECn8vAAQoAAgJ1SWfAgBmAgADAAgJaiF+LQC8AgAoAAgJUyOfAgBmAgAnAAQJcx/kBgA9AQABLgAFFAMJCAAaACwbAA==.',
Sm='Smaltownlock:BAAALgADCgMJAwAAAA==.Smo:BAAALgADCgYJBgAAAA==.Smokinontech:BAAALgAECgEJAwABLgAFFAIJAgAQAAAAAA==.Smokze:BAAALgAECgYJCgAAAA==.Smug:BAABLgAECn8UAAIcAAkJCgssIABdAQAcAAkJCgssIABdAQAAAA==.Smugs:BAABLgAFFH8KAAIhAAQJ+g+FBwDWAAAhAAQJ+g+FBwDWAAAAAA==.Smugxl:BAABLgAECn8YAAIhAAkJJBylAwCPAgAhAAkJJBylAwCPAgAAAA==.',
Sn='Snowtard:BAAALgAECgEJAQAAAA==.',
So='Solid:BAAALgAECgQJBQAAAA==.Sonicberger:BAAALgADCgQJBAABLgAECgkJKQAWADUcAA==.Sonicbergger:BAAALgAECgYJCAABLgAECgkJKQAWADUcAA==.Soniclavv:BAAALgAECgcJCAAAAA==.Sonicpoe:BAAALgADCgkJDAABLgAECgkJKQAWADUcAA==.Sonícberger:BAABLgAECn8pAAMWAAkJNRzcLABMAgAWAAkJNRzcLABMAgAXAAQJTw+0OACxAAAAAA==.Soulcaliber:BAAALgAECgEJAgAAAA==.Soulleader:BAAALgADCgYJBgAAAA==.',
Sp='Spoontangle:BAAALgAECgEJAQAAAA==.',
Sq='Squee:BAAALgAFFAIJAwABLgAFFAcJGAATAMoiAA==.',
St='Stain:BAAALgAECgUJEwAAAA==.Stealth:BAAALgAECggJDgABLgAECgkJFQAWAKwcAA==.Stepdragon:BAAALgADCgYJBgAAAA==.Stillheart:BAAALgAECgkJAQAAAA==.Stith:BAAALgADCgYJCAAAAA==.Stkinbck:BAABLgAECn8+AAIiAAkJNhDyIQCGAQAiAAkJNhDyIQCGAQAAAA==.Stonehenge:BAACLgAFFH8WAAMbAAQJex02JwBLAQAbAAQJex02JwBLAQAgAAIJ9gwPGgB9AAAuAAQKfyIAAhsACQmzISsQANACABsACQmzISsQANACAAAA.Stonepalm:BAAALgAECgQJBAAAAA==.Stratan:BAABLgAECn8cAAMYAAcJcgs4KwDBAAACAAcJZQgo6ADUAAAYAAYJZAo4KwDBAAAAAA==.',
Su='Subbzero:BAAALgADCgcJFwAAAA==.Suffer:BAACLgAFFH8IAAMaAAMJLBtLDgChAAAPAAMJExkIcgDdAAAaAAIJzRtLDgChAAAuAAQKfxoABA8ACAmsI4AUAKoCAA8ACAmQI4AUAKoCABoAAwnOI+gdANAAABEAAgn0GJFjAEcAAAAA.Sukuna:BAAALgAECgYJCQAAAA==.Sundermere:BAAALgAECgEJAgABLgAECgEJBAAQAAAAAA==.Sunlight:BAAALgAECgQJBQAAAA==.Supercat:BAAALgAECgQJBwAAAA==.Surai:BAAALgADCgUJBQAAAA==.Surf:BAABLgAECn8gAAICAAgJACLTIwCZAgACAAgJACLTIwCZAgAAAA==.',
Sw='Swanky:BAAALgAECggJCwAAAA==.Swankydranky:BAACLgAFFH8iAAQUAAgJWA+LBgBQAQAUAAYJMA+LBgBQAQAVAAUJLA15EQAxAQATAAIJ0wB1cAAiAAAuAAQKfzkAAxQACQk3HTYSACQCABUACAliHXkTAFUCABQACQmDGTYSACQCAAAA.',
Sy='Sylvia:BAAALgAECgUJCQAAAA==.Symphania:BAAALgAECgYJCwAAAA==.Synzen:BAAALgAECgQJBAAAAA==.',
['Sä']='Sätansangel:BAAALgAECgQJBQAAAA==.',
Ta='Tabbz:BAABLgAECn8sAAMgAAkJvRnFGQATAgAgAAkJvRnFGQATAgAbAAEJBQerpQAqAAAAAA==.Tahl:BAAALgADCgMJAwAAAA==.Taiils:BAAALgADCgQJBAAAAA==.Tallael:BAABLgAFFH8JAAImAAMJfxJ/CACCAAAmAAMJfxJ/CACCAAAAAA==.Tallyhochick:BAACLgAFFH8OAAIHAAQJkAMUXwDmAAAHAAQJkAMUXwDmAAAuAAQKfy8AAgcACQlcDDFPALUBAAcACQlcDDFPALUBAAAA.Tam:BAAALgAECgYJBgABLgAECgcJIwAbAG0bAA==.Taman:BAABLgAECn8jAAMbAAcJbRvLJwAhAgAbAAcJbRvLJwAhAgAgAAcJOBamKADPAQAAAA==.Tasana:BAAALgADCgYJBgAAAA==.Taylerswift:BAAALgAECgQJBwAAAA==.',
Te='Telarri:BAABLgAECn8ZAAIUAAkJUQvgMAA/AQAUAAkJUQvgMAA/AQAAAA==.Telean:BAAALgAFFAEJAQAAAA==.Telkon:BAAALgAECggJDAAAAA==.Tellesto:BAABLgAECn8wAAMJAAkJpBwhEwAOAgAJAAkJqxohEwAOAgAHAAMJNRfi3gCQAAAAAA==.Tetabitanam:BAAALgAECgMJAwABLgAECgkJQAAOAIwUAA==.',
Th='Thadox:BAAALgADCgIJAgAAAA==.Thatdh:BAAALgADCgQJBAAAAA==.Thebestname:BAAALgAECgIJBQAAAA==.Thebigonion:BAABLgAECn8jAAIgAAYJMQ9MUwDsAAAgAAYJMQ9MUwDsAAAAAA==.',
Ti='Tibberino:BAAALgAECggJDwAAAA==.Ticklantical:BAAALgAECggJDgABLgAECgkJUAADAJ4eAA==.Tinydeath:BAAALgAECgcJBwABLgAECgkJKwAHADMhAA==.Tinydh:BAAALgADCgYJBgAAAA==.Tinyfu:BAABLgAECn8sAAMUAAkJLBxhEwAWAgAUAAkJ3BthEwAWAgAVAAUJghrpKABzAQAAAA==.Tinymonk:BAAALgADCgIJAgABLgAECgkJKwAHADMhAA==.Tinyriggo:BAAALgADCgYJBgAAAA==.Tinyshift:BAAALgAECgYJBgAAAA==.Tinytamer:BAABLgAECn8rAAMHAAkJMyEFDwDDAgAHAAkJECAFDwDDAgAJAAQJtxCgOgDpAAAAAA==.',
To='Toko:BAACLgAFFH8dAAIHAAcJKCAsAgB9AQAHAAcJKCAsAgB9AQAuAAQKfykAAwcACQkjIuIIAAUDAAcACQkjIuIIAAUDACEAAQmjChKMAC8AAAAA.Tomblord:BAABLgAECn8vAAMSAAkJlhp5CAAGAgASAAkJlhp5CAAGAgAXAAMJGAqPQABLAAAAAA==.Toogga:BAAALgAECgQJBQAAAA==.Tourma:BAAALgAFFAEJBAAAAA==.',
Tr='Trapattack:BAAALgAECgQJBwAAAA==.Treeheals:BAAALgAECgIJAgAAAA==.Tristaine:BAAALgADCgYJBgABLgAECggJEAAQAAAAAA==.Truepatriot:BAACLgAFFH8JAAIEAAMJbxmOLwC5AAAEAAMJbxmOLwC5AAAuAAQKfycAAwQACAmoExMyALcBAAQACAmoExMyALcBABgABQnpEt0pAMoAAAAA.Truexlord:BAABLgAECn8WAAIWAAcJegzHpgAiAQAWAAcJewzHpgAiAQAAAA==.Truthes:BAABLgAECn8VAAIWAAkJrBwYIQCEAgAWAAkJrBwYIQCEAgAAAA==.Truthez:BAAALgADCgMJBgABLgAECgkJFQAWAKwcAA==.Truthful:BAAALgAECgEJAQABLgAECgkJFQAWAKwcAA==.Truths:BAAALgAECgcJDgABLgAECgkJFQAWAKwcAA==.Truthsx:BAABLgAECn8nAAMaAAgJGiAHBgAhAgAaAAgJph8HBgAhAgAPAAUJchothgAtAQABLgAECgkJFQAWAKwcAA==.Truthz:BAAALgADCgYJBgABLgAECgkJFQAWAKwcAA==.',
Tw='Twin:BAAALgAECgIJAgAAAA==.',
Ty='Tyg:BAAALgAECgYJEAAAAA==.Tygerhealz:BAAALgAECgIJAgAAAA==.Tylaatape:BAABLgAFFH8FAAIWAAMJOgMTvACxAAAWAAMJOgMTvACxAAAAAA==.Tyraell:BAABLgAECn8sAAMEAAkJkR2CDgCtAgAEAAkJkR2CDgCtAgACAAQJnwdM7QC1AAAAAA==.Tyrelan:BAAALgADCgMJAwAAAA==.',
['Tõ']='Tõko:BAACLgAFFH8FAAIXAAMJdxkZLgCOAAAXAAMJdxkZLgCOAAAuAAQKfxsAAhcACQlEH10FAOsCABcACQlEH10FAOsCAAEuAAUUBwkdAAcAKCAA.',
Ud='Uddermadness:BAAALgADCgQJBAAAAA==.Udor:BAABLgAECn8aAAIHAAgJLgyZbABoAQAHAAgJLgyZbABoAQAAAA==.',
Um='Umbrae:BAACLgAFFH8NAAMGAAQJ2RCrCADcAAAGAAQJ2RCrCADcAAAZAAEJpQDnQwAMAAAuAAQKfz0AAwYACQlGHxkQAGgCAAYACAnNHhkQAGgCABkAAQnjB+eCADgAAAAA.',
Up='Upies:BAABLgAECn8VAAIMAAgJ6gKyXgC+AAAMAAgJ6gKyXgC+AAAAAA==.',
Us='Usgasdanelv:BAAALgAECgUJCwAAAA==.',
Uz='Uzala:BAABLgAECn8lAAIPAAgJug6bfAA/AQAPAAgJug6bfAA/AQAAAA==.',
Va='Vahder:BAAALgAECgEJAQAAAA==.Valzanaya:BAAALgADCgYJBgAAAA==.Vanasmine:BAAALgAECgQJCgAAAA==.Vanleiden:BAAALgAECgQJBwAAAA==.Varael:BAAALgADCgIJAgAAAA==.Varielqt:BAAALgAECgMJAwAAAA==.Varilla:BAACLgAFFH8FAAIPAAMJjwgkjQCrAAAPAAMJjwgkjQCrAAAuAAQKfyMAAw8ACQnGGp8fAGcCAA8ACQnGGp8fAGcCABEAAQn0HlUxAFgAAAAA.Vazro:BAAALgAFFAMJBAAAAA==.',
Ve='Veera:BAABLgAECn83AAIgAAkJ6xXRGwADAgAgAAkJ6xXRGwADAgAAAA==.Velkas:BAAALgAECgEJAQAAAA==.Velyris:BAAALgAECgMJAwAAAA==.Vendyr:BAABLgAECn8aAAQaAAgJlCLxBwDOAQAPAAcJQx41LQBZAgAaAAYJsxnxBwDOAQARAAIJ8AscYABPAAAAAA==.Veyra:BAAALgAECgUJBgAAAA==.',
Vi='Vikadii:BAAALgADCgIJAgAAAA==.Vindictina:BAAALgADCgEJAQAAAA==.Viperjaxx:BAAALgADCgEJAQABLgAECgQJBwAQAAAAAA==.Vizan:BAAALgAECgMJAwABLgAECgkJFQAWAKwcAA==.',
Vo='Voidbloom:BAAALgADCgYJBgAAAA==.Voidvoid:BAAALgAECggJDgABLgAFFAMJBwAWAP8YAA==.Voodruid:BAAALgADCggJCgAAAA==.Vorgol:BAABLgAECn8qAAIcAAkJbRkoDgAIAgAcAAkJbRkoDgAIAgAAAA==.Vortexin:BAAALgADCgEJAQAAAA==.Voìd:BAAALgAECgQJBQAAAA==.',
Vy='Vyeria:BAABLgAECn8nAAICAAcJ0hXiZAC3AQACAAcJ0hXiZAC3AQAAAA==.Vyleera:BAAALgADCgEJAgAAAA==.Vynloran:BAACLgAFFH8OAAICAAQJlA2jVAAGAQACAAQJlA2jVAAGAQAuAAQKfyIAAgIACAmbHq0jAJoCAAIACAmbHq0jAJoCAAAA.',
We='Weeooeeooeeo:BAAALgAECggJCgABLgAECgkJPQABALgSAA==.Wellby:BAAALgAECgYJDwAAAA==.Westerin:BAABLgAECn84AAIRAAkJMhzZAgB+AgARAAkJMhzZAgB+AgAAAA==.',
Wh='Whatapal:BAAALgAECgQJBAAAAA==.',
Wi='Wildchild:BAAALgADCgMJBgAAAA==.Wildwest:BAAALgADCgkJEAAAAA==.Wimateeka:BAABLgAECn8eAAQYAAcJzh2QDwDMAQAYAAcJzh2QDwDMAQAEAAUJxRIPYQD4AAACAAQJlw2Y3QDRAAABLgAECgkJEwAQAAAAAA==.Wimatreeka:BAAALgAECgkJEwAAAA==.Wimaugmenta:BAAALgAECgYJBgABLgAECgkJEwAQAAAAAA==.Windfury:BAAALgAECgYJEwABLgAFFAMJCAAaACwbAA==.Windigo:BAACLgAFFH8FAAISAAMJ3gVxGgC2AAASAAMJ3gVxGgC2AAAuAAQKfyAABBIABglcFcEDANMAABcABgnEEYInAAIBABIABQnUFsEDANMAABYAAwlyCMkeAYYAAAAA.Winginit:BAABLgAECn8WAAMMAAkJUBlADwByAgAMAAkJUBlADwByAgAKAAcJTAnnIgDXAAABLgAFFAgJHAAeAJYWAA==.',
Wo='Wolfswarlock:BAAALgADCgMJAwAAAA==.Wooqles:BAAALgAFFAEJAQAAAA==.Wootangz:BAAALgAECgEJAQABLgAECgQJCAAQAAAAAA==.Worthyreaper:BAAALgAECgEJAQAAAA==.',
Wr='Wrastelas:BAAALgAECgQJCAAAAA==.',
Wu='Wurkim:BAAALgAECgEJAQABLgAECgQJCAAQAAAAAA==.',
Wy='Wylder:BAAALgAECgQJBAABLgAFFAYJHwAWAMYbAA==.',
Xa='Xaltorian:BAAALgADCgQJBAAAAA==.Xanto:BAABLgAFFH8FAAIHAAQJQw4CFQAwAQAHAAQJQw4CFQAwAQABLgAFFAkJNgADAJsZAA==.Xantus:BAAALgAECgQJBwAAAA==.',
Xe='Xenôn:BAAALgAECgYJBgAAAA==.',
Xi='Xiaoláng:BAAALgAECgYJCwAAAA==.Xiraxes:BAAALgAECgEJAgAAAA==.',
Xo='Xolotl:BAAALgADCgIJAgAAAA==.',
Ya='Yachak:BAAALgADCggJDwABLgAECgkJOAACALcUAA==.',
Ye='Yespaladin:BAAALgAFFAEJAQABLgAFFAYJFwAZAPQhAA==.',
Yi='Yiddosh:BAAALgAECgMJDAAAAA==.',
Yo='Yogí:BAACLgAFFH8WAAIbAAYJ/BzpDgD2AQAbAAYJ/BzpDgD2AQAuAAQKfx4AAxsACAk6I94FABQDABsACAk6I94FABQDACYABAkJDLkqAKMAAAAA.Yonamee:BAAALgADCgYJDAAAAA==.Yozomoto:BAAALgAECgkJDQAAAA==.',
Yu='Yumsumwum:BAABLgAFFH8YAAMTAAcJyiJmCQByAgATAAcJyiJmCQByAgAVAAMJdBszIADXAAAAAA==.',
Za='Zacian:BAAALgADCgMJAwAAAA==.Zalandria:BAABLgAECn8xAAMdAAkJKhUcEADmAQAdAAkJtBQcEADmAQAIAAIJuhBugQBzAAAAAA==.Zanalia:BAAALgAECggJEAAAAA==.Zarelasong:BAAALgADCgUJBQAAAA==.',
Ze='Zeeko:BAAALgAECgUJCAAAAA==.Zeffie:BAAALgAECgQJBwAAAA==.Zelxari:BAABLgAECn8tAAIPAAkJ3g1oTwCtAQAPAAkJ3g1oTwCtAQAAAA==.Zenithaunter:BAAALgAECgEJAQAAAA==.Zenkuh:BAABLgAECn8ZAAIgAAYJviJVAwCFAQAgAAYJviJVAwCFAQABLgAFFAUJEAADAPEUAA==.Zensho:BAAALgAECgYJCQAAAA==.Zeplenith:BAAALgAECgIJAwAAAA==.',
Zi='Zipsion:BAABLgAECn8iAAIHAAkJ/iCQGwCAAgAHAAkJ/iCQGwCAAgAAAA==.Zithen:BAACLgAFFH8UAAMMAAUJNQ4tFQDLAAAMAAUJNQ4tFQDLAAAKAAEJ0QFsMAAlAAAuAAQKfyEABAwACQmPGIojAKEBAAwACQkPGIojAKEBAAsAAgnIF5IhAEgAAAoAAQncEooHADUAAAAA.Zivver:BAABLgAECn8tAAIdAAkJYSJZBQDDAgAdAAkJYSJZBQDDAgAAAA==.',
Zo='Zorazig:BAAALgADCgIJAgAAAA==.',
Zx='Zxcycxz:BAAALgAECggJDgAAAA==.',
['Zé']='Zéná:BAAALgAECgMJAwAAAA==.',
['År']='Årikard:BAABLgAECn8aAAIEAAgJUR/MGQA4AgAEAAgJUR/MGQA4AgAAAA==.',
['Çh']='Çharmy:BAAALgAECggJCAAAAA==.',
['Çi']='Çinderella:BAAALgADCgYJBgAAAA==.',
['Éd']='Édelgard:BAABLgAECn8ZAAMCAAcJYBVPiABfAQACAAcJNRJPiABfAQAYAAUJ1BeWIQAIAQAAAA==.',
['Üt']='Üther:BAABLgAECn8uAAMCAAkJKiCxIwB2AgACAAkJHCCxIwB2AgAYAAIJKBzTMQCeAAAAAA==.',
['ßu']='ßubbleøseven:BAABLgAFFH8JAAICAAIJZyBTfAC9AAACAAIJZyBTfAC9AAAAAA==.',
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
