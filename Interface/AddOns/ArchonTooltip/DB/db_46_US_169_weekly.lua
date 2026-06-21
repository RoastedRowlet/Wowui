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

local lookup = {'DemonHunter-Havoc','Paladin-Retribution','Mage-Frost','Paladin-Holy','Priest-Discipline','Priest-Holy','Warrior-Fury','Hunter-Survival','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Vengeance','Druid-Balance','Warlock-Demonology','Unknown-Unknown','Warlock-Destruction','Monk-Mistweaver','Monk-Brewmaster','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Blood','Hunter-BeastMastery','Paladin-Protection','Priest-Shadow','Warlock-Affliction','Shaman-Restoration','Warrior-Arms','Warrior-Protection','Druid-Restoration','Druid-Feral','Shaman-Elemental','Hunter-Marksmanship','Rogue-Subtlety','DeathKnight-Frost','DemonHunter-Devourer','Druid-Guardian','Rogue-Assassination','Shaman-Enhancement','Mage-Fire','Mage-Arcane',}
local provider = {region='US',realm='Nordrassil',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aairidari:BAABLgAECn9BAAIBAAkJXhIQFgDaAQABAAkJXhIQFgDaAQAAAA==.Aatrox:BAAALgAECgUJBQABLgAECgkJLgACACogAA==.',
Ab='Abruna:BAAALgAECgcJEwABLgAFFAgJHwADAAwXAA==.Abruno:BAACLgAFFH8fAAIDAAgJDBc9AwCuAQADAAgJDBc9AwCuAQAuAAQKfzAAAgMACQmDIgkQAEgDAAMACQmDIgkQAEgDAAAA.Abruto:BAAALgADCgYJBgABLgAFFAgJHwADAAwXAA==.',
Ad='Adrasteia:BAAALgADCgQJAQABLgAFFAQJEwADAEoUAA==.Adrians:BAABLgAECn8qAAIDAAkJuxbVPwAdAgADAAkJuxbVPwAdAgAAAA==.Adunea:BAAALgAECggJDQAAAA==.',
Ae='Aeown:BAABLgAECn82AAMCAAgJVw5/hQBkAQACAAgJVw5/hQBkAQAEAAcJpQnySgAQAQABLgAECgkJRAAFAFgVAA==.Aerdis:BAAALgAECgYJEQABLgAECgkJFgAGAIIRAA==.',
Ag='Aggerwator:BAAALgAECgEJAwABLgAECggJHAAHACciAA==.',
Ah='Ahsóká:BAAALgAECgQJBQAAAA==.',
Ak='Akames:BAAALgAFFAIJAgABLgAFFAYJEQAIAMcdAA==.',
Al='Alahrî:BAACLgAFFH8GAAIJAAMJ2QWVIwCEAAAJAAMJ2QWVIwCEAAAuAAQKfzoABAkACQnzEOoWAOEBAAkACQnzEOoWAOEBAAoABgn+DAYOACsBAAsABwnqCntEABgBAAAA.Alandira:BAAALgAECgcJCAAAAA==.Alandrìas:BAACLgAFFH8OAAIMAAQJzQnPAACfAAAMAAQJzQnPAACfAAAuAAQKfy0AAgwACQmcFA8JAN4BAAwACQmcFA8JAN4BAAAA.Allydari:BAAALgAECgEJAQAAAA==.Aloiss:BAAALgADCgUJCAAAAA==.Alphael:BAAALgADCgYJBgAAAA==.Alror:BAABLgAECn8oAAINAAkJsB3WBQA9AwANAAkJsB3WBQA9AwAAAA==.Altera:BAABLgAECn87AAIJAAkJRBZ0CQBQAgAJAAkJRBZ0CQBQAgAAAA==.',
Am='Amelya:BAABLgAECn8VAAIDAAcJ2gpsyQD7AAADAAcJ2gpsyQD7AAAAAA==.Amethystia:BAAALgADCgYJBgAAAA==.Amirandis:BAAALgAECgYJDAAAAA==.Amuri:BAABLgAECn8eAAICAAgJkhA5cwCHAQACAAgJkhA5cwCHAQAAAA==.',
An='Andelarenn:BAAALgAECgkJCQAAAA==.Andere:BAAALgAECggJDAAAAA==.Androonatorz:BAACLgAFFH8aAAIEAAcJjRnCEAC0AQAEAAcJjRnCEAC0AQAuAAQKfy0AAwQACQkDJV8CAIcDAAQACQkDJV8CAIcDAAIABAn+ETi+AAoBAAAA.Angelø:BAAALgAECgEJAQAAAA==.Antagony:BAABLgAECn8UAAIOAAcJtgxohwArAQAOAAcJtgxohwArAQAAAA==.Antheavari:BAAALgADCgYJBgAAAA==.',
Ar='Ardell:BAEALgAECgYJBgABLgAECgcJAQAPAAAAAA==.Ardemus:BAABLgAECn8XAAMQAAYJIBIBGQDaAAAQAAYJIBIBGQDaAAAOAAEJYAAYNAEWAAAAAA==.Arkena:BAAALgAECgIJAgAAAA==.Arkenai:BAAALgADCgcJDQAAAA==.Arveiturace:BAABLgAECn8bAAILAAUJqwQhAwBqAAALAAUJqwQhAwBqAAAAAA==.',
As='Ashborrn:BAAALgAECgcJEgAAAA==.Ashtar:BAABLgAECn8dAAIHAAkJJxgSFwA2AgAHAAkJJxgSFwA2AgAAAA==.Ashtomouth:BAAALgAECgYJEQAAAA==.Astorath:BAAALgADCgEJAgAAAA==.Asukajo:BAAALgAECgMJAwAAAA==.',
Au='Aura:BAAALgAECgYJCgABLgAECgkJIgARAJEWAA==.',
Av='Averyi:BAAALgAECgIJAgAAAA==.',
Aw='Awake:BAAALgAECgEJAgAAAA==.Awaken:BAABLgAECn8dAAIDAAgJaiKqGwC1AgADAAgJaiKqGwC1AgAAAA==.Awoomonk:BAABLgAECn8VAAQSAAYJnyJEFwDvAQASAAYJYyJEFwDvAQATAAUJ9xmpJwB7AQARAAEJSBKbtwA3AAAAAA==.',
Ax='Axhure:BAAALgAECgEJAQAAAA==.',
Az='Azorei:BAAALgADCgIJAgAAAA==.',
Ba='Baconegg:BAACLgAFFH8aAAMUAAYJgBZNQwBuAQAUAAUJgBZNQwBuAQAVAAEJAACfYQAAAAAuAAQKfyEAAhQACAlFIWEVAPsCABQACAlFIWEVAPsCAAAA.Balddrex:BAAALgAECgQJBAAAAA==.Balefire:BAACLgAFFH8HAAIOAAQJQBKiUwAfAQAOAAQJQBKiUwAfAQAuAAQKfywAAw4ACQmRHZocAHkCAA4ACQmRHZocAHkCABAAAgntGMU5AEEAAAAA.Bamboom:BAAALgADCgQJBAAAAA==.Barma:BAAALgADCgcJBwAAAA==.Barraki:BAAALgAECgMJAwABLgAECgkJLgAWAO8PAA==.Basili:BAAALgADCgUJBwAAAA==.',
Bd='Bd:BAAALgAECgEJAwAAAA==.',
Be='Beeper:BAAALgAECgYJBgAAAA==.Beldanner:BAAALgADCgkJDAAAAA==.Beltirra:BAAALgAECggJEgAAAA==.Benan:BAAALgADCgUJBQAAAA==.Bengalnug:BAAALgADCgQJBAAAAA==.',
Bi='Bigwill:BAABLgAECn9BAAIDAAkJxSF8EwDlAgADAAkJxSF8EwDlAgAAAA==.',
Bl='Blackfeet:BAAALgAECgYJBwAAAA==.Blango:BAAALgAECgMJAwAAAA==.Blargy:BAACLgAFFH8LAAINAAQJ1BJtAwDQAAANAAQJ1BJtAwDQAAAuAAQKf0QAAg0ACQk+Hg0JAMICAA0ACQk+Hg0JAMICAAAA.Blex:BAAALgADCggJCAAAAA==.Bloodshed:BAAALgAECgYJCgAAAA==.Bluewaffles:BAAALgAECgMJBQABLgAECgUJCgAPAAAAAA==.',
Bo='Borealzombie:BAAALgAECgYJCQABLgAECgkJJgAXAN8cAA==.Boudicah:BAAALgADCgEJAQAAAA==.',
Br='Braicel:BAACLgAFFH8hAAIYAAgJmB3UBQAgAgAYAAgJmB3UBQAgAgAuAAQKfzIAAhgACQnkJHUDACoDABgACQnkJHUDACoDAAAA.Breedableram:BAAALgADCgYJBgABLgAECgkJHwAZAFwZAA==.Brimara:BAAALgAFFAIJAwAAAA==.Brunomirror:BAAALgAECgkJDwABLgAFFAgJHwADAAwXAA==.Brythorn:BAAALgADCgEJAQAAAA==.',
Bu='Bubbleosevên:BAAALgADCgkJCQABLgAECggJFwAWAKscAA==.Bucketojoy:BAAALgAECgIJAgABLgAECgkJPQABALgSAA==.Bunsen:BAAALgAECgEJAQABLgAFFAQJEQAaAEcdAA==.',
['Bì']='Bìgred:BAAALgADCgEJAQAAAA==.',
Ca='Cacadookie:BAAALgAECgEJAQAAAA==.Calegorm:BAAALgADCgYJCwAAAA==.Caliburne:BAABLgAECn8jAAQbAAgJnyCwBwB7AgAbAAgJjSCwBwB7AgAcAAcJTx2wEwC0AQAHAAYJGw+dUQBiAQAAAA==.Caliypso:BAAALgAECgYJCQAAAA==.Cambro:BAABLgAECn8WAAMCAAYJehnygAB4AQACAAYJTRnygAB4AQAXAAEJpgRBSQAgAAAAAA==.Candie:BAAALgAECgEJAwAAAA==.Candierain:BAAALgAECgEJAgAAAA==.Canoe:BAABLgAECn8qAAQNAAgJYhd9KwCmAQANAAcJBBV9KwCmAQAdAAcJkRdETQBaAQAeAAIJ+gANOwAYAAAAAA==.Captinsano:BAAALgAECgIJAQABLgAECggJHAAUALsPAA==.Capz:BAACLgAFFH81AAMbAAgJOiEpAABHAgAbAAgJxSApAABHAgAHAAUJqCJVBwB3AQAuAAQKfyYAAxsACQnRIzwDANsCABsACAkCJTwDANsCAAcACQktHq4PANUCAAAA.Carcaradon:BAAALgAECgEJAwAAAA==.Carta:BAAALgAECgUJDAAAAA==.Cassius:BAAALgAECgEJAgAAAA==.Caulfield:BAAALgAECgEJAQAAAA==.',
Cc='Ccstarscream:BAAALgAECggJCwAAAA==.',
Cd='Cdlam:BAAALgAECgQJBAAAAA==.',
Ce='Ceez:BAAALgAECggJDwAAAA==.Ceezinator:BAAALgAECgQJBAAAAA==.Cefteldore:BAAALgADCgcJBwAAAA==.Celebrïmbor:BAAALgAECgMJAgAAAA==.',
Ch='Chair:BAAALgAECggJEQABLgAFFAQJEwADAEoUAA==.Chiyori:BAAALgADCgIJAQAAAA==.Chokehold:BAAALgADCgMJAwAAAA==.Chopperr:BAAALgAECgYJCQABLgAFFAEJAQAPAAAAAA==.Chèn:BAAALgAECgYJCwAAAA==.',
Ci='Cindrella:BAACLgAFFH8TAAIDAAQJShRVCQDjAAADAAQJShRVCQDjAAAuAAQKfz4AAgMACQnDII0PAP4CAAMACQnDII0PAP4CAAAA.Circa:BAAALgADCgIJAgAAAA==.',
Cl='Clani:BAAALgADCgIJAgAAAA==.Clayre:BAACLgAFFH8TAAIQAAcJGBCoAgC+AQAQAAcJGBCoAgC+AQAuAAQKf0gAAhAACQlhJWIAAFADABAACQlhJWIAAFADAAAA.Clow:BAABLgAECn8cAAMHAAgJJyLMGgB1AgAHAAcJqiPMGgB1AgAbAAMJaB72KgCcAAAAAA==.',
Co='Comparabull:BAAALgADCgcJEQABLgAECggJHwADADUOAA==.Coolcrush:BAABLgAECn8+AAMTAAkJyiXEAQBZAwATAAkJTyXEAQBZAwASAAkJuSFWAwAdAwAAAA==.Corgnelius:BAAALgAECgEJAQAAAA==.Corven:BAACLgAFFH8dAAIOAAgJmBSEHADlAQAOAAgJmBSEHADlAQAuAAQKf04AAw4ACQlPI4gFADcDAA4ACQlPI4gFADcDABkAAQkAALk0ADIAAAAA.Corvenicus:BAAALgAECgMJAwABLgAFFAgJHQAOAJgUAA==.',
Cr='Crashbash:BAAALgADCgMJAwAAAA==.Crenty:BAAALgAECgIJBAABLgAECgkJJgARAB0YAA==.Crosis:BAAALgAECgYJDgAAAA==.Crossfaded:BAAALgAECgkJEgAAAA==.Cryovox:BAAALgAECgUJBQAAAA==.Crôwley:BAAALgAECgQJCQAAAA==.',
Cu='Cumazzing:BAACLgAFFH8hAAICAAgJ/CJgAgDeAgACAAgJ/CJgAgDeAgAuAAQKfyoAAgIACQmJJrYCAK4DAAIACQmJJrYCAK4DAAAA.',
Da='Dadrin:BAAALgADCgkJQQAAAA==.Daedyxes:BAABLgAECn9JAAIVAAkJBxxpAAADAgAVAAkJBxxpAAADAgAAAA==.Daerodos:BAAALgAECgUJCgAAAA==.Daiskei:BAAALgAECgcJDAAAAA==.Dangerr:BAAALgADCgcJBwAAAA==.Daní:BAAALgAECgQJBQAAAA==.Darfretail:BAABLgAECn8rAAIHAAkJhR5GCQDOAgAHAAkJhR5GCQDOAgAAAA==.Dargrum:BAAALgAECgYJBgAAAA==.Darkdemon:BAAALgAECgMJAwAAAA==.Darkmagi:BAAALgAECgMJBAAAAA==.Dasherdeez:BAAALgAECgQJCwAAAA==.Daygath:BAACLgAFFH8HAAIfAAIJmApoRwBwAAAfAAIJmApoRwBwAAAuAAQKfzEAAh8ACQlvFe4bAAICAB8ACQlvFe4bAAICAAAA.',
De='Deadlyiris:BAACLgAFFH8GAAIbAAMJag+qAwCUAAAbAAMJag+qAwCUAAAuAAQKfy8AAxsACQnfIt4CABIDABsACQnfIt4CABIDAAcABgkfEJlKAHsBAAEuAAUUBAkRABoARx0A.Deatharin:BAAALgAECgYJDQAAAA==.Decompose:BAAALgAECgEJAwAAAA==.Demonbulio:BAABLgAECn81AAIBAAkJFBbLEAAcAgABAAkJFBbLEAAcAgAAAA==.Demonisthicc:BAAALgAECgMJBQABLgAECgkJHwAZAFwZAA==.Demonlorrd:BAAALgAECgIJAgABLgAECgQJEAAPAAAAAA==.Demonskitten:BAABLgAECn8fAAIZAAkJXBlQBAA8AgAZAAkJXBlQBAA8AgAAAA==.Demonslayeer:BAAALgAECgEJAQAAAA==.Descendantt:BAAALgAECgEJAQAAAA==.Devilbullet:BAAALgADCgIJAwAAAA==.Devlyne:BAAALgADCgMJAwAAAA==.',
Di='Ding:BAAALgAECgYJEAAAAA==.Direwolf:BAAALgAECgQJBQAAAA==.Dirtyearl:BAABLgAECn84AAICAAkJtxRMXAC5AQACAAkJtxRMXAC5AQAAAA==.Dithehealer:BAABLgAECn8kAAMXAAkJYCB3AwDcAgAXAAkJYCB3AwDcAgACAAEJmQdyTAEuAAAAAA==.Divain:BAAALgADCgEJAQAAAA==.Divinecandie:BAAALgAECgEJAQAAAA==.',
Dk='Dkdi:BAABLgAECn8ZAAIVAAkJBSAiBQDaAgAVAAkJBSAiBQDaAgAAAA==.',
Do='Doalina:BAAALgADCgQJBgAAAA==.Domidia:BAABLgAECn8gAAIDAAYJQR6ZcQDwAQADAAYJQR6ZcQDwAQAAAA==.Donkeyshot:BAAALgAECgQJCgABLgAECgkJMgAgABUYAA==.Doogie:BAAALgAECgEJBgAAAA==.Dortak:BAAALgADCgQJBAABLgAECgUJDwAPAAAAAA==.',
Dr='Dracon:BAAALgADCgkJCQAAAA==.Draconfel:BAAALgAECgYJCQAAAA==.Draglone:BAAALgADCgMJAwABLgAECgYJBgAPAAAAAA==.Dragømir:BAAALgAECgEJAQABLgAFFAUJCAALAMkCAA==.Dranåk:BAAALgAECgQJBAAAAA==.Drbadtouch:BAAALgAECgEJAQAAAA==.Dreamfyres:BAACLgAFFH8YAAMKAAcJQRvpAQB9AQAKAAUJBCHpAQB9AQALAAUJ6Bn5IQBRAQAuAAQKfysAAwoACQkmJQcBAF0DAAoACAmKJQcBAF0DAAsACQkqJGIDADoDAAAA.Drenamai:BAABLgAECn8hAAIWAAkJMBMzPADvAQAWAAkJMBMzPADvAQAAAA==.Drewetta:BAABLgAECn8/AAINAAkJfBTIAAB5AQANAAkJfBTIAAB5AQAAAA==.Drmombo:BAAALgAECgQJAwAAAA==.',
Du='Duhmptruhk:BAAALgAECgYJCwABLgAECgcJBwAPAAAAAA==.Durbana:BAAALgAECgUJCgAAAA==.Duskariel:BAAALgADCgMJBAAAAA==.Duskfire:BAAALgAECgEJAQAAAA==.',
Dy='Dyson:BAAALgAECgcJEgAAAA==.',
['Dé']='Démonicblood:BAAALgAECgYJEwAAAA==.',
Ed='Edrocz:BAEALgAECgcJAQAAAA==.',
Eh='Ehmehzing:BAACLgAFFH8gAAICAAUJ0iaQFADGAQACAAUJ0iaQFADGAQAuAAQKfzoAAgIACQkGJq4BAMgDAAIACQkGJq4BAMgDAAEuAAUUCAkhAAIA/CIA.',
Ek='Ekhart:BAAALgAECgEJAQAAAA==.',
El='Elandin:BAAALgAECggJDwAAAA==.Elghtyelght:BAAALgAECgUJBwAAAA==.Eliicia:BAACLgAFFH8TAAIhAAcJ2AvIAgAGAQAhAAcJ2AvIAgAGAQAuAAQKfxYAAiEACQmBDSEmAMgBACEACQmBDSEmAMgBAAAA.Elvwyr:BAAALgAECggJDAAAAA==.',
Em='Embarrassed:BAAALgADCggJFwAAAA==.Emmetcullen:BAACLgAFFH8SAAMfAAcJyBmfAQBtAQAfAAYJXRmfAQBtAQAaAAEJ9whnewBIAAAuAAQKfyAAAx8ACAkkHtkTAIACAB8ACAkkHtkTAIACABoABAk3Cat1ALoAAAAA.Emmy:BAABLgAECn8UAAIGAAYJxyAuKgCiAQAGAAYJxyAuKgCiAQAAAA==.Emogothbabe:BAAALgAECgUJBwABLgAFFAEJAQAPAAAAAA==.Emryss:BAAALgAECgIJAgAAAA==.',
En='Endo:BAABLgAFFH8LAAMUAAYJ1hsuBQA3AQAUAAUJBiAuBQA3AQAiAAMJCBSKAgCrAAABLgAFFAYJFwABAPMeAA==.Endorush:BAACLgAFFH8XAAQBAAYJ8x70AQB7AQABAAQJqB30AQB7AQAjAAYJDRYpMQBhAQAMAAEJECe3AwB2AAAuAAQKfz8AAwEACQl9JXMAAOgDAAEACQl8JXMAAOgDACMACQm1IucFACwDAAAA.Eneldenes:BAAALgAFFAIJBAAAAA==.Enjoyer:BAAALgAECggJEgABLgAECgkJGgANABcPAA==.',
Er='Ereitherla:BAABLgAECn89AAIWAAkJiA94WQCYAQAWAAkJiA94WQCYAQAAAA==.',
Es='Eshaia:BAAALgADCgQJBAAAAA==.Espressð:BAAALgAFFAEJAQAAAA==.',
Ev='Evanthe:BAAALgADCgEJAgAAAA==.',
Ex='Excalibear:BAABLgAECn8vAAIEAAkJPRaSJQDbAQAEAAkJPRaSJQDbAQABLgAFFAYJFgADAMocAA==.',
Ey='Eydis:BAAALgADCgkJIAAAAA==.Eyepisspeas:BAAALgADCgEJAQAAAA==.',
Ez='Ezra:BAAALgADCgkJFwAAAA==.',
Fa='Faithchill:BAAALgAECgMJAwAAAA==.Farc:BAAALgAECgUJBgAAAA==.Fatherjeff:BAAALgADCgkJDQAAAA==.Fayith:BAAALgADCgEJAQAAAA==.',
Fe='Feironor:BAAALgAECggJCwAAAA==.Feldown:BAAALgAECgYJBwAAAA==.Felryno:BAAALgADCgQJBAAAAA==.Feyrre:BAAALgAECgMJAwAAAA==.',
Fi='Fircey:BAAALgAECgEJAQABLgAFFAIJAwAPAAAAAA==.Fistbroz:BAABLgAECn8eAAMkAAkJ8xVHEgDMAQAkAAkJFBRHEgDMAQAeAAcJDxUcFAB/AQABLgAFFAgJIgASAFgPAA==.',
Fl='Flawpeacok:BAABLgAECn8cAAIUAAkJPxjsRwDqAQAUAAkJPxjsRwDqAQAAAA==.Fleredil:BAABLgAECn9IAAMYAAkJqSGwBQD4AgAYAAkJqSGwBQD4AgAGAAgJzRrAEQBSAgAAAA==.Flingernle:BAAALgAECgEJAwAAAA==.Floista:BAAALgAECggJDQAAAA==.Floistas:BAABLgAFFH8LAAIWAAMJWBPWXwDlAAAWAAMJWBPWXwDlAAAAAA==.',
Fo='Forepray:BAAALgAFFAEJAQABLgAFFAgJHgAHABQVAA==.Forger:BAABLgAECn81AAIcAAkJTBj/DAAaAgAcAAkJTBj/DAAaAgAAAA==.Forsakey:BAAALgAECgUJCQABLgAFFAYJEAAdAPAYAA==.Foxfireii:BAAALgADCgMJAwAAAA==.',
Fr='Freshdk:BAACLgAFFH8UAAQUAAUJaiSeRABrAQAUAAQJaiSeRABrAQAiAAQJLhe+EAAQAQAVAAEJAABbYAAAAAAuAAQKfzYABBQACQkFJHAMADcDABQACQkDJHAMADcDACIACAlhIbkHABkCABUAAQljDnVBAEYAAAAA.Freÿa:BAAALgADCgYJBgABLgAFFAEJBQAOANwaAA==.Frostgash:BAAALgADCgcJDAAAAA==.Frostitution:BAAALgAECgEJAQAAAA==.Frostycheeks:BAACLgAFFH8ZAAMUAAUJbBvIBABGAQAUAAQJbBvIBABGAQAVAAUJLASVKgCkAAAuAAQKfzUAAhQACAkKIy4gAIgCABQACAkKIy4gAIgCAAAA.Frostywaffle:BAAALgAECgEJAQAAAA==.',
Fu='Fubuki:BAAALgADCgEJAQAAAA==.Fudgetracks:BAAALgADCgYJBgAAAA==.Futaccine:BAABLgAECn8oAAQjAAgJ0CJ1HwBYAgAjAAgJlyJ1HwBYAgAMAAIJqiPiKABgAAABAAIJTxj5ZgA/AAAAAA==.Future:BAAALgAECgYJDwABLgAFFAMJCAAZACwbAA==.Fuzzycat:BAAALgADCgEJAQAAAA==.',
Ga='Gaav:BAAALgAECgUJBwABLgAECggJHAAHACciAA==.Gaerlan:BAAALgAECgUJDQAAAA==.Galvquodiyu:BAAALgAECgcJCQAAAA==.Garlic:BAAALgADCgEJAQAAAA==.',
Ge='Geekbarr:BAAALgAECgQJBgABLgAFFAEJAQAPAAAAAA==.',
Gh='Ghettox:BAAALgAECgYJCAAAAA==.Ghostblades:BAACLgAFFH8aAAMUAAcJDxkxNQCVAQAUAAcJDxkxNQCVAQAiAAEJAACBLwAAAAAuAAQKfysAAxQACQmBIYYXALkCABQACQmBIYYXALkCACIAAQnbHDcWADgAAAAA.Ghostdk:BAAALgAECgEJAgAAAA==.Ghostsham:BAAALgADCgMJAwAAAA==.Ghuleh:BAAALgAECgEJAQAAAA==.',
Gi='Gilffy:BAAALgADCgkJCgAAAA==.Gizik:BAAALgAECgIJBgABLgAFFAcJGgAYALAaAA==.',
Gl='Gloomybear:BAAALgADCgUJBQAAAA==.',
Go='Golgotterath:BAABLgAFFH8IAAIaAAYJ9AuYIgBlAQAaAAYJ9AuYIgBlAQABLgAFFAYJFgADAMocAA==.Gorm:BAAALgAECgQJBAABLgAFFAIJBQAUAJwXAA==.',
Gr='Gratata:BAAALgAECgMJBQABLgAECgkJJgARAB0YAA==.Grimzero:BAAALgADCgMJAwAAAA==.Grinnee:BAABLgAECn8bAAMlAAkJ4w4oCADMAQAlAAkJMQ4oCADMAQAhAAQJ7Q7lOADtAAABLgAECgkJTAACADoiAA==.Grinny:BAABLgAECn9MAAMCAAkJOiK8CQAaAwACAAkJOiK8CQAaAwAEAAIJowMyjQBKAAAAAA==.Grobthar:BAAALgADCgYJBgAAAA==.',
Gu='Gunna:BAAALgAECgIJAgABLgAFFAMJCAAZACwbAA==.',
Ha='Hadariel:BAAALgAECgcJCQAAAA==.Haldane:BAABLgAECn8qAAICAAkJ8gx1dgCBAQACAAkJ8gx1dgCBAQABLgAFFAQJEQAaAEcdAA==.Havochunter:BAABLgAECn8XAAIWAAcJqxx+OgD1AQAWAAcJqxx+OgD1AQAAAA==.',
He='Heidegger:BAAALgAECgQJCQAAAA==.Helenkeller:BAAALgAECgIJAgAAAA==.Henderson:BAAALgADCgQJBAAAAA==.Heraois:BAABLgAECn8yAAIgAAkJFRh3BgAsAgAgAAkJFRh3BgAsAgAAAA==.Heriod:BAAALgAECgEJAgAAAA==.Hexy:BAAALgAECgUJCAAAAA==.',
Hi='Highblood:BAAALgAECgUJBgAAAA==.',
Ho='Holytës:BAAALgAECgUJBQAAAA==.Holywráth:BAABLgAECn8WAAICAAcJlwwzBwCbAAACAAcJlwwzBwCbAAAAAA==.Horndoggie:BAAALgAECgYJBgAAAA==.Hotea:BAAALgAECgUJCgAAAA==.',
Hp='Hpsnotdps:BAAALgAECgcJEwAAAA==.',
Hu='Hucklebeary:BAAALgADCgYJBgAAAA==.Huell:BAABLgAECn8UAAMhAAgJthRrGgDFAQAhAAgJthRrGgDFAQAlAAEJ2REaJgA7AAAAAA==.Hunterdh:BAABLgAECn8yAAIWAAkJfgl3XQCOAQAWAAkJfgl3XQCOAQAAAA==.',
Hy='Hynesh:BAAALgAECgYJCwAAAA==.Hynixx:BAACLgAFFH8eAAIHAAgJFBXyAACUAQAHAAgJFBXyAACUAQAuAAQKfzAAAgcACQkIIRMMAKgCAAcACQkIIRMMAKgCAAAA.',
Ic='Icecandie:BAAALgAECgYJEgAAAA==.',
Il='Illidope:BAAALgAECgcJDAABLgAFFAcJGAAKAEEbAA==.Ilostthegame:BAAALgADCgIJAgABLgAECgkJRAAFAFgVAA==.',
Im='Imistmypants:BAABLgAECn8mAAIRAAkJHRjwEwB8AgARAAkJHRjwEwB8AgAAAA==.',
In='Infinitevoid:BAAALgADCgUJDAAAAA==.Innervatez:BAABLgAFFH8YAAIdAAgJ4hxVBADZAgAdAAgJ4hxVBADZAgAAAA==.Inspectda:BAABLgAECn8VAAIOAAgJgwcadgBxAQAOAAgJgwcadgBxAQAAAA==.',
Io='Ionúin:BAAALgAECgQJBAAAAA==.',
Is='Issel:BAAALgAECgYJCwAAAA==.',
Iy='Iyaasu:BAABLgAECn8cAAIJAAgJJBt9CwAiAgAJAAgJJBt9CwAiAgAAAA==.Iyahliea:BAAALgAECgIJAgAAAA==.',
Ja='Jaeger:BAAALgAECggJEAAAAA==.Jaekir:BAABLgAECn81AAIDAAkJORY3RAAPAgADAAkJORY3RAAPAgAAAA==.Jakey:BAAALgAECgYJDAAAAA==.Jakfrost:BAABLgAECn9HAAIDAAkJOiV9AAC/AgADAAkJOiV9AAC/AgAAAA==.Jarten:BAABLgAECn83AAIiAAkJqiKDAQAhAwAiAAkJqiKDAQAhAwAAAA==.Jaylebate:BAABLgAECn9FAAMUAAkJaiJrAACmAgAUAAkJzCFrAACmAgAVAAgJQB47DQA3AgAAAA==.',
Je='Jerrenn:BAABLgAECn8eAAMCAAkJqBjVQAAEAgACAAgJ3hfVQAAEAgAEAAIJLwlkeQBaAAAAAA==.Jesseatamer:BAABLgAECn86AAIWAAkJmibIAACSAwAWAAkJmibIAACSAwAAAA==.',
Jo='Jolt:BAAALgADCgEJAQAAAA==.Jortak:BAAALgAECggJEwABLgAECgkJRQAUAGoiAA==.Jouska:BAAALgAECgYJCwABLgAECgcJBwAPAAAAAA==.',
Ju='Judge:BAAALgAECgEJAgAAAA==.Julesx:BAAALgAFFAEJAQAAAA==.Justar:BAAALgADCgMJBQAAAA==.',
['Jë']='Jësus:BAAALgAECgcJCAAAAA==.',
Ka='Kaera:BAAALgAECgYJDgAAAA==.Kakamora:BAABLgAECn8UAAMgAAgJGhldEABVAQAWAAgJbBZYVQCkAQAgAAcJ/BNdEABVAQABLgAFFAMJBAAPAAAAAA==.Kakushin:BAAALgAECgEJAQAAAA==.Kaldór:BAAALgADCgIJAgAAAA==.Kalmek:BAABLgAECn8UAAIUAAkJVBbkRgDuAQAUAAkJVBbkRgDuAQAAAA==.Karen:BAAALgAECgUJDQABLgAECgkJOAACALcUAA==.Karne:BAAALgADCgEJAQAAAA==.Karold:BAAALgADCgUJBgAAAA==.Kartian:BAAALgAECgEJBAAAAA==.Karyana:BAAALgAFFAMJAwAAAA==.Kastia:BAAALgAECgUJDAAAAA==.Katrynwel:BAABLgAECn8fAAIDAAgJNQ7ofQB8AQADAAgJNQ7ofQB8AQAAAA==.Katsumi:BAAALgADCgkJRQAAAA==.Kaylestia:BAAALgAECgkJCQAAAA==.Kaylinne:BAAALgAECgEJAQAAAA==.',
Ke='Keení:BAAALgADCgkJCQAAAA==.Kellenah:BAAALgADCgkJFwAAAA==.Kettama:BAAALgAECgEJAQABLgAFFAEJAQAPAAAAAA==.',
Kh='Khainen:BAAALgAECgQJBAAAAA==.Khaliana:BAAALgADCgEJAQAAAA==.Khold:BAABLgAECn8VAAMUAAgJIhdyUQDPAQAUAAcJkRlyUQDPAQAiAAcJTQbUHQDeAAAAAA==.',
Ki='Killalltoday:BAABLgAECn8/AAMaAAkJPhC2SQCIAQAaAAgJMxG2SQCIAQAmAAgJNg5SEwCDAQAAAA==.Killersmile:BAAALgADCgkJCQAAAA==.Kilon:BAAALgAFFAEJAQAAAA==.Kirkk:BAAALgAECgYJEgAAAA==.Kivareous:BAAALgAFFAIJAwAAAA==.Kixarea:BAAALgADCgkJDQABLgAFFAIJAwAPAAAAAA==.',
Kn='Kneesweak:BAAALgAECgQJBgAAAA==.Knexx:BAABLgAECn8ZAAIVAAgJsxZWFQDCAQAVAAgJsxZWFQDCAQAAAA==.Knixx:BAACLgAFFH8aAAMYAAYJwg8EAQCHAQAYAAUJtg8EAQCHAQAFAAUJeAiuMADPAAAuAAQKf0YABBgACQmlGkIMAIwCABgACQmlGkIMAIwCAAYABwk6GGQbAAECAAUABgldEMYtADABAAAA.Knotty:BAAALgADCgYJDQAAAA==.',
Ko='Kotalyst:BAABLgAECn8dAAISAAkJUxH/JgB4AQASAAkJUxH/JgB4AQAAAA==.Kotastrophe:BAAALgAECgcJBwAAAA==.Koveras:BAAALgADCgkJCwAAAA==.Koyaanis:BAABLgAECn8rAAIRAAkJmhhSFQBvAgARAAkJmhhSFQBvAgAAAA==.Koyya:BAAALgAFFAIJAwAAAA==.',
Ku='Kufoo:BAABLgAECn8/AAMHAAkJeCaxAQBjAwAHAAkJoSWxAQBjAwAcAAgJ1CWDBADcAgAAAA==.Kuma:BAAALgAECgUJCQABLgAFFAMJCAAZACwbAA==.Kuraikage:BAAALgADCgEJAQAAAA==.Kurao:BAAALgAECgMJAwAAAA==.Kurukai:BAAALgADCgUJBgAAAA==.',
Ky='Kynlerrine:BAABLgAECn8gAAIMAAkJkxcbBgA4AgAMAAkJkxcbBgA4AgAAAA==.Kyokushin:BAAALgAECgMJAwAAAA==.Kyzo:BAAALgAECgYJBgAAAA==.',
['Ké']='Kéndra:BAAALgAECgMJAwAAAA==.',
La='Ladiable:BAAALgAECgYJCQABLgAFFAYJGgAWAEggAA==.Laggyboi:BAAALgAECgYJCAAAAA==.Lansseax:BAAALgAECgcJEwAAAA==.Laraelin:BAAALgADCgYJBgAAAA==.Lascerette:BAAALgAECgYJCgAAAA==.Law:BAAALgADCgcJEQAAAA==.Layez:BAAALgAECgEJAQABLgAFFAIJAwAPAAAAAA==.',
Le='Leguan:BAAALgADCgkJDQAAAA==.Leo:BAAALgAECgEJAQAAAA==.Lethe:BAAALgAECgcJCAABLgAFFAcJEwAhANgLAA==.',
Li='Likestoflash:BAEALgAECgYJEAABLgAECgkJMAAWAAAbAA==.Lilgeeked:BAAALgADCgcJDAAAAA==.Liliannarose:BAAALgADCgEJAQABLgAECgIJBAAPAAAAAA==.Lilyröse:BAAALgAECgIJBAAAAA==.',
Lo='Locklove:BAAALgADCgkJCQAAAA==.Lohal:BAACLgAFFH8FAAIOAAMJngsoBwDRAAAOAAMJngsoBwDRAAAuAAQKfzoAAg4ACQkVG/EoADgCAA4ACQkVG/EoADgCAAAA.Lohmi:BAAALgAECgYJDAAAAA==.Lolalashay:BAAALgAECgMJBwAAAA==.Lorilock:BAAALgADCgUJBQAAAA==.Loudawn:BAACLgAFFH8MAAINAAQJ6gLpBACDAAANAAQJ6gLpBACDAAAuAAQKfywAAg0ACQkIC0EsAHYBAA0ACQkIC0EsAHYBAAAA.',
Lu='Luania:BAAALgAECgUJEAAAAA==.Lupo:BAAALgAECgEJAQAAAA==.Lurtz:BAABLgAECn8YAAIWAAYJ4BY8bwBiAQAWAAYJ4BY8bwBiAQAAAA==.Lusucio:BAAALgAFFAIJAwAAAA==.',
Ly='Lyberrath:BAAALgAECgIJAwAAAA==.Lyeth:BAAALgAECgMJBAAAAA==.Lyna:BAAALgADCgcJBwAAAA==.Lyzzardkng:BAAALgAECgcJDQAAAA==.',
['Lé']='Lélouch:BAAALgAECgYJBgABLgAFFAcJEgAfAMgZAA==.',
Ma='Maango:BAAALgAECgkJCAAAAA==.Magerthat:BAAALgADCgYJBwAAAA==.Magicaltickl:BAABLgAECn9HAAMDAAkJtxoxKQB2AgADAAkJtxoxKQB2AgAnAAMJ/ggeCwCIAAAAAA==.Magiki:BAAALgAECgQJCAAAAA==.Malkala:BAAALgAECgUJCAAAAA==.Malonormu:BAAALgADCgQJBAAAAA==.Mamadeezy:BAAALgAECgIJAwAAAA==.Manical:BAAALgAECgcJEwAAAA==.Mashiach:BAAALgADCgcJBwABLgAFFAUJFgAUAI8WAA==.Maxgoon:BAABLgAECn8WAAIOAAcJwgzVcwB2AQAOAAcJwgzVcwB2AQAAAA==.',
Mc='Mcfist:BAAALgAECgUJBQABLgAECggJDwAPAAAAAA==.',
Me='Megumin:BAABLgAECn8cAAQDAAgJdhNEZgCxAQADAAgJ7hJEZgCxAQAnAAMJeA/nDACZAAAoAAIJ3xNtGgBEAAABLgAECgkJLgACACogAA==.Mellisandria:BAAALgAECgcJEQAAAA==.Melodious:BAAALgADCgYJCQAAAA==.Merek:BAABLgAECn81AAISAAkJmCOMAgA0AwASAAkJmCOMAgA0AwAAAA==.Merriska:BAACLgAFFH8GAAMEAAIJxyC5NwCOAAAEAAIJxyC5NwCOAAACAAEJHRG7uABFAAAuAAQKfxsAAwIACQk1IqElAJACAAIACAlWI6ElAJACAAQACAm7IJsTAHUCAAEuAAUUBgkWABEAciQA.',
Mi='Miashadow:BAAALgADCgcJDQAAAA==.Mikeysmom:BAAALgAECggJEAABLgAECgkJBgAPAAAAAA==.Mirigosa:BAAALgAECggJCAABLgAFFAQJEwADAEoUAA==.Misseslovett:BAAALgAECgcJDAAAAA==.Missmeow:BAAALgADCgYJBgAAAA==.Mistyd:BAACLgAFFH8jAAIkAAgJEheBAACNAQAkAAgJEheBAACNAQAuAAQKfz0AAiQACQnPHGAHAIACACQACQnPHGAHAIACAAAA.Mithras:BAAALgAECgEJAgAAAA==.',
Mo='Monkar:BAAALgADCgMJAwAAAA==.Monkdiluffy:BAAALgADCgUJBQAAAA==.Moocifer:BAAALgAECgIJAgAAAA==.Moonstriker:BAACLgAFFH8MAAMEAAQJpyNdEwCUAQAEAAQJpyNdEwCUAQACAAMJYxd0BQDxAAAuAAQKfzMAAwQACQk2JrIBAGgDAAQACQk2JrIBAGgDAAIAAQlhGbZzAUUAAAAA.Morgause:BAABLgAECn8XAAIOAAkJyQg2AwDNAAAOAAkJyQg2AwDNAAAAAA==.Morijinn:BAAALgAECgQJBQAAAA==.Morllan:BAAALgAECgEJAgAAAA==.Mortyxp:BAAALgADCgIJAgAAAA==.',
Mu='Muirdin:BAABLgAECn8hAAIWAAgJtRJ6WwCTAQAWAAgJtRJ6WwCTAQAAAA==.',
Mv='Mvp:BAAALgADCgYJBgAAAA==.',
['Má']='Máelyss:BAAALgAECgQJBgAAAA==.',
['Må']='Mångix:BAAALgAECgIJAgAAAA==.',
['Mé']='Mélusine:BAABLgAECn8fAAMbAAkJYCJ/CgBCAgAbAAkJbCF/CgBCAgAHAAUJNRtqTAB0AQAAAA==.',
['Mï']='Mïsterlovett:BAAALgAECgUJBQABLgAFFAEJBQAOANwaAA==.',
Na='Naanomage:BAAALgAECgYJEwAAAA==.Nacht:BAAALgADCgEJAQABLgAFFAYJEQAIAMcdAA==.Nagakabouros:BAAALgADCgEJAQAAAA==.Nagato:BAAALgADCgcJBwAAAA==.Naksami:BAAALgAECgIJAgAAAA==.',
Ne='Necrotoxin:BAACLgAFFH8FAAIOAAEJ3BqGvABRAAAOAAEJ3BqGvABRAAAuAAQKf0QAAw4ACQmhJKMDAFcDAA4ACAmhJKMDAFcDABAAAQkAAPZcAFgAAAAA.Nemoralia:BAAALgAECggJEgAAAA==.Nezuuko:BAAALgADCgQJBAAAAA==.',
Ni='Nibble:BAAALgADCgQJBAAAAA==.Nightsever:BAABLgAECn8YAAMjAAkJrxzhIQCGAgAjAAkJOhrhIQCGAgABAAUJBCGyJgCLAQAAAA==.Nirath:BAABLgAECn8+AAIKAAkJtw2ACACoAQAKAAkJtw2ACACoAQAAAA==.',
No='Noiire:BAAALgAFFAIJAwABLgAFFAcJEwAhANgLAA==.Nopal:BAAALgAECgMJAwAAAA==.Nopriest:BAACLgAFFH8XAAIYAAYJ9CHsAwBUAgAYAAYJ9CHsAwBUAgAuAAQKfzUAAhgACQnzJW0BAGcDABgACQnzJW0BAGcDAAAA.Notixx:BAAALgADCgQJBAAAAA==.Notprepared:BAABLgAECn89AAMBAAkJuBLpFgDPAQABAAkJuBLpFgDPAQAjAAMJcAQlBgFEAAAAAA==.Nottisdemon:BAAALgAECgcJDQAAAA==.',
Nu='Nuggy:BAABLgAECn8eAAMRAAkJCBIBOwCFAQARAAgJmQ8BOwCFAQATAAQJSxHSQgD0AAAAAA==.Nullfox:BAAALgADCgUJBQABLgAFFAYJGwAhAHwfAA==.',
Oa='Oakly:BAACLgAFFH8JAAIdAAMJNxO8PwCxAAAdAAMJNxO8PwCxAAAuAAQKfy4AAh0ACAk0HpwTAK4CAB0ACAk0HpwTAK4CAAAA.',
Ob='Obsidian:BAAALgAECggJEAABLgAFFAQJDAAEAKcjAA==.',
On='Onaroll:BAABLgAFFH8GAAIRAAMJrgd3SACDAAARAAMJrgd3SACDAAABLgAFFAgJHAAdAJYWAA==.Onehotelf:BAAALgAECgcJEwAAAA==.',
Oo='Ooyagoddess:BAABLgAECn8ZAAIGAAYJWxV/KwBtAQAGAAYJWxV/KwBtAQAAAA==.',
Or='Orenthil:BAAALgAECgEJAQABLgAFFAMJCQACAOseAA==.',
Ot='Otoah:BAAALgAECgYJBgABLgAFFAYJFgAWALYeAA==.',
Oy='Oya:BAAALgADCgIJAgAAAA==.',
Pa='Pacamonk:BAABLgAECn8gAAITAAYJ2SKhHADKAQATAAYJ2SKhHADKAQAAAA==.Pacifer:BAAALgAECgEJAQAAAA==.Pamanda:BAAALgAFFAIJAgABLgAFFAcJGAAKAEEbAA==.Pann:BAAALgAECgEJAQABLgAECgYJEwAPAAAAAA==.Papatiny:BAAALgAECgYJBgAAAA==.Pauon:BAAALgADCgcJBwAAAA==.Pawpatine:BAABLgAECn87AAIfAAkJ4xkXGwAIAgAfAAkJ4xkXGwAIAgAAAA==.Pawsa:BAABLgAECn9DAAMSAAgJfx81CwCBAgASAAgJfx81CwCBAgATAAgJFhqtFQALAgABLgAFFAEJAQAPAAAAAA==.Pawsome:BAAALgAECgUJCQABLgAECgkJOwAfAOMZAA==.Pawthetic:BAACLgAFFH8cAAIdAAgJlhbbAADnAQAdAAgJlhbbAADnAQAuAAQKfy8AAx0ACQkDITwDAGEDAB0ACQkDITwDAGEDAA0ACQmRGlsPAGkCAAAA.',
Pe='Peelforheals:BAACLgAFFH8KAAIFAAIJLRAlPgCBAAAFAAIJLRAlPgCBAAAuAAQKfywAAxgACAm+GvkgAL4BABgABwmhGfkgAL4BAAUABwm7FRocALUBAAAA.Penguindemic:BAABLgAECn8sAAIOAAkJaiYbAgBxAwAOAAkJaiYbAgBxAwAAAA==.Pentimus:BAAALgADCgYJCAABLgAECgkJJgARAB0YAA==.Pep:BAABLgAECn8fAAMTAAkJ1x30DAB1AgATAAkJ1x30DAB1AgARAAEJUwMRcwAgAAAAAA==.Pephunt:BAAALgAECgEJAQAAAA==.Pepperoni:BAAALgAECgcJCAAAAA==.Petruccius:BAACLgAFFH8MAAINAAUJ1hSjIAAaAQANAAUJ1hSjIAAaAQAuAAQKfy4AAg0ACQmFH1EHAOECAA0ACQmFH1EHAOECAAAA.Pewpewlepew:BAAALgAECggJEgAAAA==.',
Ph='Phaedesana:BAAALgADCgkJCQABLgAECgkJKQAjANcUAA==.Phaeku:BAABLgAECn8pAAIjAAkJ1xRNMwD4AQAjAAkJ1xRNMwD4AQAAAA==.Phòenix:BAAALgADCgkJCQAAAA==.',
Pi='Pinksparklez:BAAALgAECgEJAQABLgAECgQJBQAPAAAAAA==.',
Pl='Plaguedr:BAAALgAECgEJAQAAAA==.',
Po='Ponfarr:BAAALgAECgUJBQAAAA==.Poochita:BAAALgADCgEJAQAAAA==.Poppop:BAAALgADCgMJAwAAAA==.Porbles:BAAALgADCgcJBwAAAA==.Porklamb:BAAALgAECgYJEAABLgAECgkJPgATAMolAA==.Powermonk:BAAALgAECgQJBwAAAA==.',
Pr='Prayre:BAAALgADCgkJFQAAAA==.Prey:BAAALgAECgUJDQAAAA==.Prospa:BAAALgAECgQJBwABLgAFFAEJAQAPAAAAAA==.Prumper:BAACLgAFFH8IAAIDAAQJMglgkAC3AAADAAQJMglgkAC3AAAuAAQKf0MAAgMACQmcIG4nAH0CAAMACQmcIG4nAH0CAAAA.',
Py='Pyric:BAAALgAECgEJBAAAAA==.',
Qu='Quesoblanco:BAAALgAECgkJCgAAAA==.',
Qy='Qybxboogiedk:BAAALgAECgYJCwAAAA==.Qybxboogiemo:BAAALgAECgEJAgAAAA==.Qybxboogietk:BAAALgAECgIJAgAAAA==.',
Ra='Rabid:BAAALgAECgEJAwAAAA==.Raghallov:BAAALgAECgMJAwAAAA==.Ragingstorm:BAAALgADCgIJAwAAAA==.Rakshash:BAAALgAECgIJAgAAAA==.Ramzey:BAABLgAECn8wAAIUAAkJPx1PIACIAgAUAAkJPx1PIACIAgAAAA==.Ravokkc:BAAALgADCgMJAwAAAA==.Rawnis:BAAALgAECgEJAQAAAA==.Raylëigh:BAAALgADCgYJBgAAAA==.',
Re='Redbearon:BAAALgAECgkJEwAAAA==.Redroger:BAAALgADCgQJBQAAAA==.Refractrix:BAAALgAECgQJBAAAAA==.Regena:BAABLgAECn9EAAQFAAkJWBUQHwDVAQAFAAkJqg0QHwDVAQAGAAkJUhSZIQC1AQAYAAcJ3AijQgAFAQAAAA==.Relyssa:BAAALgAECgcJDgAAAA==.Remorse:BAACLgAFFH8ZAAIcAAgJLBi4CACpAQAcAAgJLBi4CACpAQAuAAQKf0sAAhwACQnxIogCABwDABwACQnxIogCABwDAAAA.Required:BAAALgAFFAMJAwABLgAFFAgJKAAjAOoaAA==.Retro:BAABLgAECn8mAAIfAAcJ8Qn3UAD0AAAfAAcJ8Qn3UAD0AAAAAA==.',
Rh='Rhysara:BAAALgAECgEJAQAAAA==.',
Ri='Rikatree:BAABLgAECn8tAAMdAAkJ+x2LDQDuAgAdAAkJ+x2LDQDuAgANAAkJoxdiFAAwAgABLgAFFAIJAwAPAAAAAA==.Rim:BAABLgAECn9EAAIaAAkJfB5YCwADAwAaAAkJfB5YCwADAwAAAA==.Rinaren:BAAALgADCgcJCAAAAA==.Risque:BAACLgAFFH8QAAIDAAQJKhdQWAAtAQADAAQJKhdQWAAtAQAuAAQKfyoAAgMACQlIIXcfAKECAAMACQlIIXcfAKECAAAA.',
Ro='Ronard:BAACLgAFFH8HAAIUAAIJthsB0wCOAAAUAAIJthsB0wCOAAAuAAQKf0kAAhQACQkQJksEAF4DABQACQkQJksEAF4DAAAA.Ronfar:BAACLgAFFH8WAAImAAYJxxT6BQBfAQAmAAYJxxT6BQBfAQAuAAQKf0wAAiYACQkLJU0BAC0DACYACQkLJU0BAC0DAAAA.Rook:BAAALgAECggJCAAAAA==.',
Ru='Rukidingme:BAAALgAECgYJEgAAAA==.Rumonkingme:BAAALgADCgUJBwAAAA==.Runehammer:BAAALgADCgMJAwAAAA==.Rustyglass:BAAALgAECgEJAQAAAA==.Ruttisðir:BAAALgAECgYJBgAAAA==.',
Rw='Rw:BAAALgAECgEJAQAAAA==.',
Ry='Ryhorn:BAABLgAECn8wAAICAAkJbQ3VYgCqAQACAAkJbQ3VYgCqAQAAAA==.Ryno:BAAALgAECgUJBgAAAA==.Ryomensukuna:BAAALgAECgMJAwAAAA==.Ryujin:BAABLgAECn8XAAICAAgJMgpxnwA4AQACAAgJMgpxnwA4AQAAAA==.',
Sa='Sadcraig:BAAALgADCgYJBgAAAA==.Salo:BAAALgAECgUJCQAAAA==.Sanazenet:BAAALgAECgQJBAAAAA==.Saronas:BAAALgADCgkJEAABLgAECgkJNwAiAKoiAA==.',
Sc='Schrutes:BAAALgADCgEJAQAAAA==.Scootypuffsr:BAAALgAECgYJDgAAAA==.Scootyshooty:BAAALgADCgYJBgAAAA==.Scrap:BAABLgAECn8XAAITAAcJVBRCLAB+AQATAAcJVBRCLAB+AQAAAA==.Scubasuiit:BAABLgAECn8dAAQdAAgJdhy3JQAiAgAdAAcJ1By3JQAiAgANAAYJ+R6FHwADAgAkAAEJGQaYNQAfAAAAAA==.Scubowsuit:BAAALgAECgYJCQAAAA==.',
Se='Sedria:BAAALgADCgQJBAAAAA==.Segarth:BAAALgAFFAEJAQAAAA==.Selen:BAABLgAECn9CAAMEAAkJmiGcBgAjAwAEAAkJmiGcBgAjAwACAAIJExNzBwCVAAAAAA==.Seleste:BAAALgADCgYJCAAAAA==.Semballin:BAAALgAECgEJAwAAAA==.Semdogg:BAAALgAECgEJAQABLgAECgkJNwABAKQhAA==.Semtex:BAAALgAECgEJAQAAAA==.Seråphiel:BAABLgAECn8pAAIWAAgJXAivfwA/AQAWAAgJXAivfwA/AQAAAA==.Seswatha:BAACLgAFFH8WAAIDAAYJyhyhKwDEAQADAAYJyhyhKwDEAQAuAAQKfzoAAgMACQklJX8FAFcDAAMACQklJX8FAFcDAAAA.',
Sh='Shadowbaron:BAAALgAECgQJDgAAAA==.Shadowsnek:BAAALgAECgEJAQAAAA==.Shakras:BAAALgADCgEJAQABLgAECgkJRAAFAFgVAA==.Shaltear:BAAALgAECgYJCAAAAA==.Shamandroo:BAACLgAFFH8HAAIaAAUJhCM0AQCrAQAaAAUJhCM0AQCrAQAuAAQKfxwAAxoACQlaIhwLAAYDABoACQlaIhwLAAYDAB8ABQnXGOhTAOoAAAEuAAUUBwkaAAQAjRkA.Shamdi:BAAALgADCgYJBgAAAA==.Shawti:BAAALgADCgcJCAAAAA==.Shenzu:BAAALgAECgYJDgAAAA==.Shmongus:BAABLgAECn8aAAINAAkJFw9PJQChAQANAAkJFw9PJQChAQAAAA==.Shocktop:BAABLgAECn8fAAImAAkJrSJiAQAoAwAmAAkJrSJiAQAoAwAAAA==.Shortfuse:BAAALgAECgEJAQABLgAECgUJDAAPAAAAAA==.Shortserkit:BAAALgAECgYJBgAAAA==.Shz:BAAALgAECgEJAQABLgAECgQJCAAPAAAAAA==.Shådowfire:BAAALgAECgcJBwAAAA==.Shìft:BAACLgAFFH8MAAIdAAQJCgy/BACYAAAdAAQJCgy/BACYAAAuAAQKfzMAAh0ACQlXGS4VAKACAB0ACQlXGS4VAKACAAAA.',
Si='Siercy:BAAALgADCgMJBQAAAA==.Sightofhand:BAAALgAECgEJAQAAAA==.Sillynanny:BAAALgAECgUJCQAAAA==.Simplysauced:BAAALgAECgQJCwABLgAECgkJKAANALAdAA==.',
Sk='Skuùuß:BAAALgADCgQJBAAAAA==.Skylér:BAAALgADCgkJCQAAAA==.',
Sl='Slighted:BAABLgAECn8dAAQBAAUJ2xqdKAA3AQABAAUJ2xqdKAA3AQAMAAMJPRf+GgDEAAAjAAIJKA3dyABmAAABLgAECgkJGgAWAP4YAA==.Sliizzy:BAAALgADCgYJCQAAAA==.Slimydruid:BAABLgAECn8fAAIkAAgJJCOLBgCUAgAkAAgJJCOLBgCUAgAAAA==.Slizz:BAAALgADCgYJCwAAAA==.Slizzard:BAAALgADCgYJDAAAAA==.Slow:BAABLgAECn8vAAQoAAgJ1SWfAgBmAgADAAgJaiF+LQC8AgAoAAgJUyOfAgBmAgAnAAQJcx/jBgA9AQABLgAFFAMJCAAZACwbAA==.',
Sm='Smaltownlock:BAAALgADCgMJAwAAAA==.Smo:BAAALgADCgYJBgAAAA==.Smokinontech:BAAALgAECgEJAQABLgAFFAEJAQAPAAAAAA==.Smokze:BAAALgAECgYJCgAAAA==.Smug:BAABLgAECn8UAAIbAAkJCgssIABdAQAbAAkJCgssIABdAQAAAA==.Smugs:BAABLgAFFH8HAAIgAAQJ+g99FgAMAQAgAAQJ+g99FgAMAQAAAA==.Smugxl:BAABLgAECn8YAAIgAAkJJBylAwCPAgAgAAkJJBylAwCPAgAAAA==.',
So='Solid:BAAALgAECgEJAQAAAA==.Sonicberger:BAAALgADCgQJBAABLgAECgkJKQAUADUcAA==.Sonicbergger:BAAALgAECgYJCAABLgAECgkJKQAUADUcAA==.Soniclavv:BAAALgAECgcJCAAAAA==.Sonicpoe:BAAALgADCgkJDAABLgAECgkJKQAUADUcAA==.Sonícberger:BAABLgAECn8pAAMUAAkJNRzbLABMAgAUAAkJNRzbLABMAgAVAAQJTw+yOACxAAAAAA==.Soulcaliber:BAAALgAECgEJAgAAAA==.',
Sp='Spoontangle:BAAALgAECgEJAQAAAA==.',
Sq='Squee:BAAALgAFFAIJAwABLgAFFAYJFgARAHIkAA==.',
St='Stain:BAAALgAECgUJEwAAAA==.Stealth:BAAALgAECggJDgABLgAFFAIJAwAPAAAAAA==.Stepdragon:BAAALgADCgYJBgAAAA==.Stillheart:BAAALgAECgkJAQAAAA==.Stith:BAAALgADCgYJCAAAAA==.Stkinbck:BAABLgAECn8+AAIhAAkJNhDyIQCGAQAhAAkJNhDyIQCGAQAAAA==.Stonehenge:BAACLgAFFH8RAAIaAAQJRx0xJwBLAQAaAAQJRx0xJwBLAQAuAAQKfyIAAhoACQmzISsQANACABoACQmzISsQANACAAAA.Stonepalm:BAAALgADCgkJLAAAAA==.Stratan:BAABLgAECn8bAAMXAAYJjAs5KwDBAAACAAYJ4wck6ADUAAAXAAYJZAo5KwDBAAAAAA==.',
Su='Subbzero:BAAALgADCgcJEgAAAA==.Suffer:BAACLgAFFH8IAAMZAAMJLBtLDgChAAAOAAMJExkhcgDdAAAZAAIJzRtLDgChAAAuAAQKfxoABA4ACAmsI4EUAKoCAA4ACAmQI4EUAKoCABkAAwnOI+gdANAAABAAAgn0GJFjAEcAAAAA.Sukuna:BAAALgAECgYJCQAAAA==.Sundermere:BAAALgAECgEJAgABLgAECgEJBAAPAAAAAA==.Sunlight:BAAALgAECgQJBAAAAA==.Supercat:BAAALgAECgQJBwAAAA==.Surai:BAAALgADCgUJBQAAAA==.Surf:BAABLgAECn8fAAICAAgJACLTIwCZAgACAAgJACLTIwCZAgAAAA==.',
Sw='Swanky:BAAALgAECggJCwAAAA==.Swankydranky:BAACLgAFFH8iAAQSAAgJWA9KAQBtAQASAAYJMA9KAQBtAQATAAUJLA14EQAxAQARAAIJ0wB9cAAiAAAuAAQKfzkAAxIACQk3HTUSACQCABMACAliHXkTAFUCABIACQmDGTUSACQCAAAA.',
Sy='Sylvia:BAAALgAECgUJCQAAAA==.Symphania:BAAALgAECgYJCwAAAA==.Synzen:BAAALgAECgQJBAAAAA==.',
['Sä']='Sätansangel:BAAALgAECgQJBQAAAA==.',
Ta='Tabbz:BAABLgAECn8sAAMfAAkJvRnFGQATAgAfAAkJvRnFGQATAgAaAAEJBQerpQAqAAAAAA==.Tahl:BAAALgADCgMJAwAAAA==.Taiils:BAAALgADCgQJBAAAAA==.Tallael:BAABLgAFFH8HAAImAAMJzQ8ADwDRAAAmAAMJzQ8ADwDRAAAAAA==.Tallyhochick:BAACLgAFFH8MAAIWAAQJkAOYCwB7AAAWAAQJkAOYCwB7AAAuAAQKfy8AAhYACQlcDDBPALUBABYACQlcDDBPALUBAAAA.Taman:BAABLgAECn8iAAMaAAcJbRvJJwAhAgAaAAcJbRvJJwAhAgAfAAcJOBamKADPAQAAAA==.Tasana:BAAALgADCgYJBgAAAA==.Taylerswift:BAAALgAECgQJBwAAAA==.',
Te='Telarri:BAABLgAECn8ZAAISAAkJUAvgMAA/AQASAAkJUAvgMAA/AQAAAA==.Telean:BAAALgAFFAEJAQAAAA==.Telkon:BAAALgAECggJCwAAAA==.Tellesto:BAABLgAECn8wAAMIAAkJpBwjEwAOAgAIAAkJqxojEwAOAgAWAAMJNRfZ3gCQAAAAAA==.Tetabitanam:BAAALgAECgMJAwABLgAECgkJPwANAHwUAA==.',
Th='Thadox:BAAALgADCgIJAgAAAA==.Thatdh:BAAALgADCgQJBAAAAA==.Thebestname:BAAALgAECgIJBAAAAA==.Thebigonion:BAABLgAECn8fAAIfAAYJ6A1IUwDsAAAfAAYJ6A1IUwDsAAAAAA==.',
Ti='Tibberino:BAAALgAECggJDwAAAA==.Ticklantical:BAAALgAECggJDgABLgAECgkJRwADALcaAA==.Tinydeath:BAAALgAECgcJBwABLgAECgkJKwAWADMhAA==.Tinydh:BAAALgADCgYJBgAAAA==.Tinyfu:BAABLgAECn8sAAMSAAkJLBxgEwAWAgASAAkJ3BtgEwAWAgATAAUJghroKABzAQAAAA==.Tinymonk:BAAALgADCgIJAgABLgAECgkJKwAWADMhAA==.Tinyriggo:BAAALgADCgYJBgAAAA==.Tinyshift:BAAALgAECgYJBgAAAA==.Tinytamer:BAABLgAECn8rAAMWAAkJMyEFDwDDAgAWAAkJECAFDwDDAgAIAAQJtxCdOgDpAAAAAA==.',
To='Toko:BAACLgAFFH8dAAIWAAcJKCAsAgB9AQAWAAcJKCAsAgB9AQAuAAQKfykAAxYACQkjIuIIAAUDABYACQkjIuIIAAUDACAAAQmjChKMAC8AAAAA.Tomblord:BAABLgAECn8vAAMiAAkJlhp5CAAGAgAiAAkJlhp5CAAGAgAVAAMJGAqPQABLAAAAAA==.Toogga:BAAALgAECgQJBQAAAA==.Tourma:BAAALgAFFAEJBAAAAA==.',
Tr='Trapattack:BAAALgAECgQJBwAAAA==.Treeheals:BAAALgAECgIJAgAAAA==.Tristaine:BAAALgADCgYJBgABLgAECggJDwAPAAAAAA==.Truepatriot:BAACLgAFFH8JAAIEAAMJbxmOLwC5AAAEAAMJbxmOLwC5AAAuAAQKfycAAwQACAmoExMyALcBAAQACAmoExMyALcBABcABQnpEt0pAMoAAAAA.Truexlord:BAABLgAECn8WAAIUAAcJewzBpgAiAQAUAAcJewzBpgAiAQAAAA==.Truthes:BAAALgAFFAIJAwAAAA==.Truthez:BAAALgADCgMJBgABLgAFFAIJAwAPAAAAAA==.Truths:BAAALgAECgcJDgABLgAFFAIJAwAPAAAAAA==.Truthsx:BAABLgAECn8nAAMZAAgJGiAHBgAhAgAZAAgJph8HBgAhAgAOAAUJchoohgAtAQABLgAFFAIJAwAPAAAAAA==.Truthz:BAAALgADCgYJBgABLgAFFAIJAwAPAAAAAA==.',
Tw='Twin:BAAALgAECgIJAgAAAA==.',
Ty='Tyg:BAAALgAECgUJCAAAAA==.Tygerhealz:BAAALgAECgIJAgAAAA==.Tylaatape:BAAALgAFFAMJBAAAAA==.Tyraell:BAABLgAECn8sAAMEAAkJkR2BDgCtAgAEAAkJkR2BDgCtAgACAAQJnwdM7QC1AAAAAA==.Tyrelan:BAAALgADCgMJAwAAAA==.',
['Tõ']='Tõko:BAACLgAFFH8FAAIVAAMJdxkiLgCOAAAVAAMJdxkiLgCOAAAuAAQKfxsAAhUACQlEH10FAOsCABUACQlEH10FAOsCAAEuAAUUBwkdABYAKCAA.',
Ud='Udor:BAABLgAECn8aAAIWAAgJLgyfbABoAQAWAAgJLgyfbABoAQAAAA==.',
Um='Umbrae:BAACLgAFFH8HAAMGAAMJSApNAwBrAAAGAAIJ0A5NAwBrAAAYAAEJpQDiQwAMAAAuAAQKfz0AAwYACQlGHxkQAGgCAAYACAnNHhkQAGgCABgAAQnjB+CCADgAAAAA.',
Up='Upies:BAABLgAECn8VAAILAAgJ6gKyXgC+AAALAAgJ6gKyXgC+AAAAAA==.',
Us='Usgasdanelv:BAAALgAECgUJCwAAAA==.',
Uz='Uzala:BAABLgAECn8iAAIOAAgJug6ZfABAAQAOAAgJug6ZfABAAQAAAA==.',
Va='Vahder:BAAALgAECgEJAQAAAA==.Valzanaya:BAAALgADCgYJBgAAAA==.Vanasmine:BAAALgAECgQJCgAAAA==.Vanleiden:BAAALgAECgQJBwAAAA==.Varael:BAAALgADCgIJAgAAAA==.Varielqt:BAAALgAECgMJAwAAAA==.Varilla:BAACLgAFFH8FAAIOAAMJjwg3jQCrAAAOAAMJjwg3jQCrAAAuAAQKfyMAAw4ACQnGGp8fAGcCAA4ACQnGGp8fAGcCABAAAQn0HlMxAFgAAAAA.Vazro:BAAALgAECgcJCAAAAA==.',
Ve='Veera:BAABLgAECn83AAIfAAkJ6xXSGwADAgAfAAkJ6xXSGwADAgAAAA==.Velkas:BAAALgAECgEJAQAAAA==.Velyris:BAAALgAECgMJAwAAAA==.Vendyr:BAABLgAECn8aAAQZAAgJlCLxBwDOAQAOAAcJQx41LQBZAgAZAAYJsxnxBwDOAQAQAAIJ8AscYABPAAAAAA==.Veyra:BAAALgAECgUJBgAAAA==.',
Vi='Vikadii:BAAALgADCgIJAgAAAA==.Viperjaxx:BAAALgADCgEJAQABLgAECgQJBwAPAAAAAA==.Vizan:BAAALgAECgMJAwABLgAFFAIJAwAPAAAAAA==.',
Vo='Voidbloom:BAAALgADCgYJBgAAAA==.Voidvoid:BAAALgAECggJDgAAAA==.Voodruid:BAAALgADCggJCgAAAA==.Vorgol:BAABLgAECn8qAAIbAAkJbRkqDgAIAgAbAAkJbRkqDgAIAgAAAA==.Voìd:BAAALgAECgQJBQAAAA==.',
Vy='Vyeria:BAABLgAECn8nAAICAAcJ0hXiZAC3AQACAAcJ0hXiZAC3AQAAAA==.Vyleera:BAAALgADCgEJAgAAAA==.Vynloran:BAACLgAFFH8OAAICAAQJlA2wVAAGAQACAAQJlA2wVAAGAQAuAAQKfyIAAgIACAmbHq0jAJoCAAIACAmbHq0jAJoCAAAA.',
We='Weeooeeooeeo:BAAALgAECggJCgABLgAECgkJPQABALgSAA==.Wellby:BAAALgAECgUJCgAAAA==.Westerin:BAABLgAECn84AAIQAAkJMhzZAgB+AgAQAAkJMhzZAgB+AgAAAA==.',
Wh='Whatapal:BAAALgAECgQJBAAAAA==.',
Wi='Wildchild:BAAALgADCgMJBgAAAA==.Wildwest:BAAALgADCgkJEAAAAA==.Wimateeka:BAABLgAECn8eAAQXAAcJzh2QDwDMAQAXAAcJzh2QDwDMAQAEAAUJxRIPYQD4AAACAAQJlw2Y3QDRAAABLgAECgkJEwAPAAAAAA==.Wimatreeka:BAAALgAECgkJEwAAAA==.Wimaugmenta:BAAALgAECgYJBgABLgAECgkJEwAPAAAAAA==.Windfury:BAAALgAECgYJEgABLgAFFAMJCAAZACwbAA==.Windigo:BAACLgAFFH8FAAIiAAMJ3gVzGgC2AAAiAAMJ3gVzGgC2AAAuAAQKfx0ABCIABgn8FJAYABABACIABQldFpAYABABABUABgnEEYInAAIBABQAAwlyCL0eAYYAAAAA.Winginit:BAABLgAECn8WAAMLAAkJUBlCDwByAgALAAkJUBlCDwByAgAJAAcJTAnnIgDXAAABLgAFFAgJHAAdAJYWAA==.',
Wo='Wolfswarlock:BAAALgADCgMJAwAAAA==.Wooqles:BAAALgAECgYJCAAAAA==.Wootangz:BAAALgAECgEJAQABLgAECgQJCAAPAAAAAA==.Worthyreaper:BAAALgAECgEJAQAAAA==.',
Wr='Wrastelas:BAAALgAECgQJCAAAAA==.',
Wu='Wurkim:BAAALgAECgEJAQABLgAECgQJCAAPAAAAAA==.',
Wy='Wylder:BAAALgAECgQJBAABLgAECgkJEgAPAAAAAA==.',
Xa='Xaltorian:BAAALgADCgQJBAAAAA==.Xanto:BAAALgAFFAEJAQABLgAFFAcJLQADAFUeAA==.Xantus:BAAALgAECgQJBwAAAA==.',
Xe='Xenôn:BAAALgAECgYJBgAAAA==.',
Xi='Xiaoláng:BAAALgAECgYJCwAAAA==.Xiraxes:BAAALgAECgEJAgAAAA==.',
Ya='Yachak:BAAALgADCggJDwABLgAECgkJOAACALcUAA==.',
Ye='Yespaladin:BAAALgAFFAEJAQABLgAFFAYJFwAYAPQhAA==.',
Yi='Yiddosh:BAAALgAECgMJDAAAAA==.',
Yo='Yogí:BAACLgAFFH8VAAIaAAYJ/BzzDgD1AQAaAAYJ/BzzDgD1AQAuAAQKfx4AAxoACAk6I94FABQDABoACAk6I94FABQDACYABAkJDLgqAKMAAAAA.Yonamee:BAAALgADCgYJDAAAAA==.Yozomoto:BAAALgAECgkJDQAAAA==.',
Yu='Yumsumwum:BAABLgAFFH8WAAMRAAYJciRqCQByAgARAAYJciRqCQByAgATAAMJdBsyIADXAAAAAA==.',
Za='Zacian:BAAALgADCgMJAwAAAA==.Zalandria:BAABLgAECn8vAAMcAAkJ2RQdEADmAQAcAAkJOBQdEADmAQAHAAIJuhBsgQBzAAAAAA==.Zanalia:BAAALgAECggJDwAAAA==.Zarelasong:BAAALgADCgUJBQAAAA==.',
Ze='Zeeko:BAAALgAECgUJCAAAAA==.Zeffie:BAAALgAECgQJBwAAAA==.Zelxari:BAABLgAECn8tAAIOAAkJ3g1pTwCtAQAOAAkJ3g1pTwCtAQAAAA==.Zenithaunter:BAAALgAECgEJAQAAAA==.Zenkuh:BAAALgAECgYJDgAAAA==.Zensho:BAAALgAECgYJCQAAAA==.Zeplenith:BAAALgAECgIJAwAAAA==.',
Zi='Zipsion:BAABLgAECn8iAAIWAAkJ/iCRGwCAAgAWAAkJ/iCRGwCAAgAAAA==.Zithen:BAACLgAFFH8TAAMLAAQJNQ60BADbAAALAAQJNQ60BADbAAAJAAEJ0QFsMAAlAAAuAAQKfyEABAsACQmPGIojAKEBAAsACQkPGIojAKEBAAoAAgnIF5IhAEgAAAkAAQncEgQCADkAAAAA.Zivver:BAABLgAECn8tAAIcAAkJYSJbBQDDAgAcAAkJYSJbBQDDAgAAAA==.',
Zo='Zorazig:BAAALgADCgIJAgAAAA==.',
Zx='Zxcycxz:BAAALgAECggJDgAAAA==.',
['År']='Årikard:BAABLgAECn8aAAIEAAgJUR/OGQA4AgAEAAgJUR/OGQA4AgAAAA==.',
['Çh']='Çharmy:BAAALgAECggJCAAAAA==.',
['Çi']='Çinderella:BAAALgADCgYJBgAAAA==.',
['Éd']='Édelgard:BAABLgAECn8ZAAMCAAcJYBVPiABfAQACAAcJNRJPiABfAQAXAAUJ1BeVIQAIAQAAAA==.',
['Üt']='Üther:BAABLgAECn8uAAMCAAkJKiCxIwB2AgACAAkJHCCxIwB2AgAXAAIJKBzSMQCeAAAAAA==.',
['ßu']='ßubbleøseven:BAABLgAFFH8JAAICAAIJZyBbfAC9AAACAAIJZyBbfAC9AAAAAA==.',
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
