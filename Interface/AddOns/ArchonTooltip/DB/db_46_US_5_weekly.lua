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

local lookup = {'Unknown-Unknown','Warrior-Fury','Paladin-Retribution','Priest-Holy','Monk-Brewmaster','Paladin-Holy','Druid-Restoration','Mage-Frost','DeathKnight-Blood','Warrior-Protection','DeathKnight-Unholy','Shaman-Enhancement','Shaman-Restoration','Shaman-Elemental','Druid-Feral','Druid-Guardian','Rogue-Assassination','Rogue-Subtlety','Warlock-Demonology','Warlock-Destruction','Monk-Mistweaver','Paladin-Protection','Priest-Discipline','Hunter-BeastMastery','Hunter-Marksmanship','Evoker-Augmentation','DemonHunter-Devourer','Monk-Windwalker','Evoker-Devastation','Warrior-Arms','DeathKnight-Frost','Rogue-Outlaw','Mage-Arcane','Evoker-Preservation','Priest-Shadow','Druid-Balance','Hunter-Survival','DemonHunter-Havoc','DemonHunter-Vengeance','Warlock-Affliction',}
local provider = {region='US',realm='Akama',name='US',type='weekly',zone=46,date='2026-06-06',data={Ac='Accost:BAAALgAECgQJBgAAAA==.Acronica:BAAALgAECgEJAwAAAA==.',
Ad='Adagar:BAAALgAECgYJDgAAAA==.Adesha:BAAALgADCgYJBgAAAA==.',
Ae='Aeloria:BAAALgAECgcJBgAAAA==.Aeratedlol:BAAALgAFFAIJAwABLgAFFAQJBAABAAAAAA==.Aethandor:BAAALgAECgUJDQAAAA==.',
Ai='Ainslie:BAAALgADCgEJAQAAAA==.',
Ak='Akassa:BAABLgAECn8eAAICAAYJqAmmVgDoAAACAAYJqAmmVgDoAAAAAA==.Akavaleera:BAAALgAECgQJBwAAAA==.Aknologia:BAAALgADCgYJBgABLgAECgMJAwABAAAAAA==.Akíto:BAAALgAECgcJCQAAAA==.',
Al='Alaric:BAAALgADCgUJBQAAAA==.Alecto:BAABLgAECn8ZAAIDAAkJFAtLgABjAQADAAkJFAtLgABjAQAAAA==.Algo:BAAALgAECgkJEwAAAA==.Alune:BAAALgADCgYJDAAAAA==.',
Am='Amalthea:BAAALgAECgMJAwAAAA==.Amarah:BAACLgAFFH8QAAIEAAMJqyR3EAA3AQAEAAMJqyR3EAA3AQAuAAQKf0MAAgQACQk2Hm4LAKMCAAQACQk2Hm4LAKMCAAAA.',
An='Andron:BAAALgADCgIJAgAAAA==.Andy:BAAALgADCgcJBwAAAA==.Angryjames:BAAALgADCgYJCgAAAA==.Animehero:BAAALgAECgIJAwABLgAECgkJFQAFAJIcAA==.',
Ap='Applemonster:BAAALgAECggJEAAAAA==.',
Ar='Arboghast:BAAALgAECgUJCAAAAA==.Argadin:BAABLgAFFH8FAAIDAAQJ7AN7cwC1AAADAAQJ7AN7cwC1AAAAAA==.Argdru:BAAALgAECgYJDQABLgAFFAQJBQADAOwDAA==.Arglock:BAAALgADCgIJAgABLgAFFAQJBQADAOwDAA==.Argrekd:BAAALgADCgMJAwABLgAFFAQJBQADAOwDAA==.Aridol:BAAALgADCgUJBAAAAA==.Arigön:BAAALgADCgMJAwAAAA==.Arima:BAAALgAECgIJAwAAAA==.Arknox:BAABLgAECn8cAAMGAAkJIA2ALACkAQAGAAkJIA2ALACkAQADAAEJEAtdiwEuAAAAAA==.Arthaslk:BAAALgAECgcJEAABLgAECgcJFwACABYYAA==.',
As='Aserus:BAAALgAECgcJCwABLgAFFAcJIQAHAIAbAA==.Ashallel:BAAALgAECgQJBAABLgAFFAcJIQAHAIAbAA==.Ashx:BAAALgADCgIJBAABLgAECgkJIAAIAKoXAA==.Astralock:BAAALgAECgEJAQAAAA==.',
At='Ate:BAABLgAECn8pAAIJAAgJYRk9EQDsAQAJAAgJYRk9EQDsAQABLgAECgcJLQAKALcbAA==.Atlette:BAACLgAFFH8NAAIEAAQJOxzIEgAcAQAEAAQJOxzIEgAcAQAuAAQKfyoAAgQACQluH2MCAEUDAAQACQluH2MCAEUDAAAA.Atrocitusz:BAAALgAECgIJAgAAAA==.Atroxx:BAACLgAFFH8OAAILAAQJmRDBHgAjAQALAAQJmRDBHgAjAQAuAAQKf1EAAgsACQmZIswQABcDAAsACQmZIswQABcDAAEuAAUUBgkqAAwAkxkA.Attman:BAACLgAFFH8SAAINAAUJ5Rl4FwCOAQANAAUJ5Rl4FwCOAQAuAAQKfx4AAw0ACAkSHDcZAHQCAA0ACAkSHDcZAHQCAA4AAwlFAzyEADoAAAAA.',
Au='Auradawn:BAAALgAECgQJEgAAAA==.',
Ay='Ayaya:BAAALgAECgQJBQABLgAECgYJEQABAAAAAA==.',
Ba='Baetrayer:BAAALgAECgcJCAAAAA==.Bailz:BAAALgADCgMJAwAAAA==.Baldsmon:BAAALgAECgUJBQAAAA==.Balimund:BAAALgAECgEJAQAAAA==.Ballerstatus:BAAALgAECgMJAwAAAA==.Ballsofaith:BAAALgADCgkJFAABLgAECgcJLQAKALcbAA==.Ballsofire:BAABLgAECn8tAAIKAAcJtxvPEwCmAQAKAAcJtxvPEwCmAQAAAA==.Basherz:BAAALgAECgQJBgAAAA==.',
Be='Bearmane:BAABLgAECn8VAAMPAAcJHB/AEACaAQAPAAUJUSPAEACaAQAQAAYJpxjbHABTAQABLgAECgkJMQAFAN8lAA==.Beedoc:BAAALgADCgEJAQAAAA==.Behindithu:BAABLgAECn8oAAMRAAkJGxTcBwDNAQARAAgJgxTcBwDNAQASAAcJywdkNQDvAAAAAA==.Belithel:BAABLgAECn8gAAIIAAkJqhcFdgDmAQAIAAkJqhcFdgDmAQAAAA==.Bencreepin:BAABLgAECn8cAAIJAAcJqRE5IgA2AQAJAAcJqRE5IgA2AQAAAA==.Beniz:BAABLgAECn8fAAMTAAgJFgljhQAqAQATAAgJjAhjhQAqAQAUAAIJBQnHWgBeAAAAAA==.Bernoulli:BAABLgAECn8fAAIVAAkJOhlyHQAZAgAVAAkJOhlyHQAZAgAAAA==.',
Bi='Bigblunts:BAAALgADCgEJAgAAAA==.Bigcrunch:BAAALgAECggJCQAAAA==.Bignative:BAAALgAECgYJCAAAAA==.Bigrockbiter:BAAALgAECgIJAgAAAA==.Bironic:BAAALgAECgYJDAABLgAECgcJIgASAHURAA==.',
Bl='Bloodbones:BAAALgADCgYJBgAAAA==.Bloodboo:BAAALgAECgQJBAAAAA==.Bloodyhpally:BAAALgAFFAIJAgABLgAFFAgJKgAVAKEfAA==.Bloodymyst:BAABLgAFFH8qAAIVAAgJoR8SAwDeAgAVAAgJoR8SAwDeAgAAAA==.Blumpy:BAAALgADCggJCAAAAA==.',
Bo='Boethius:BAAALgAECgMJBQABLgAECgkJEgABAAAAAA==.Boopsnoopems:BAABLgAECn8gAAIWAAcJLhJmGgA4AQAWAAcJLhJmGgA4AQAAAA==.Borderline:BAAALgADCgYJBgABLgAFFAUJGgAXADUPAA==.Bounty:BAAALgAECgkJDQAAAA==.',
Br='Briannajade:BAABLgAECn8gAAIIAAgJyggxlABKAQAIAAgJyggxlABKAQAAAA==.Brisha:BAACLgAFFH8pAAIGAAgJkBtxBAB1AgAGAAgJkBtxBAB1AgAuAAQKfzMAAwYACQlIJHQAALUDAAYACQlIJHQAALUDABYAAQk8EvhKADQAAAAA.Brodan:BAAALgAECgQJBAAAAA==.Brokenhealz:BAAALgAECgcJDQAAAA==.',
Bs='Bs:BAAALgAECgYJBgABLgAFFAQJBwALAH8PAA==.',
Bu='Bubble:BAAALgADCgEJAgAAAA==.Bubblehash:BAAALgADCgEJAQAAAA==.Bubbletarded:BAAALgAECgUJBgAAAA==.Bustah:BAABLgAECn8eAAMYAAgJex24DgDFAgAYAAgJex24DgDFAgAZAAYJag3uTwAPAQABLgAFFAQJBwALAH8PAA==.',
Ca='Cacaco:BAAALgADCgIJAgAAAA==.Cactuscooler:BAAALgADCgcJBwAAAA==.Caffrey:BAABLgAECn8ZAAIHAAkJ1SKyAQCJAwAHAAkJ1SKyAQCJAwAAAA==.Calene:BAACLgAFFH8LAAIRAAQJxBLOBAA1AQARAAQJxBLOBAA1AQAuAAQKfxgAAhEABwk+HGEIAL0BABEABwk+HGEIAL0BAAAA.Cammi:BAABLgAECn8aAAIGAAYJKRq9KwCpAQAGAAYJKRq9KwCpAQAAAA==.Cammywammy:BAABLgAECn8fAAINAAgJehY0JgAbAgANAAgJehY0JgAbAgAAAA==.Candy:BAAALgAECgEJAQAAAA==.Carlyyrae:BAABLgAECn8kAAMNAAkJgBknFQCVAgANAAkJgBknFQCVAgAOAAEJxwJ8sgAfAAAAAA==.Casare:BAABLgAECn8gAAIZAAYJ8Q+JFwDrAAAZAAYJ8Q+JFwDrAAAAAA==.Catjam:BAABLgAFFH8GAAIDAAQJEyCFJQBeAQADAAQJEyCFJQBeAQABLgAFFAgJKgAaAM0iAA==.',
Ce='Celarc:BAAALgAECgYJDwAAAA==.Celithe:BAABLgAECn8cAAIbAAgJuw+8YQBZAQAbAAgJuw+8YQBZAQABLgAECgkJOwAIACgZAA==.Celyda:BAAALgADCgcJBwAAAA==.',
Ch='Chantriss:BAAALgAECgQJBAAAAA==.Chape:BAACLgAFFH8MAAIVAAUJzxBJIgAsAQAVAAUJzxBJIgAsAQAuAAQKfzcABBUACQlDIcEGACgDABUACQlDIcEGACgDAAUABglKGZ0kAH8BABwABAlHGZxAAO8AAAAA.Chapito:BAAALgAECgcJCAAAAA==.Chipmonked:BAABLgAECn8+AAQFAAkJdAzlJAB9AQAFAAkJ1wvlJAB9AQAcAAYJOwrNSQDNAAAVAAUJIwPLUACQAAAAAA==.Chlop:BAABLgAECn8ZAAILAAgJcBx0HADUAgALAAgJcBx0HADUAgAAAA==.Chochalinda:BAAALgAECgEJAgAAAA==.Chunkers:BAAALgAECgQJBAAAAA==.Chuubar:BAAALgADCgYJCwAAAA==.',
Ci='Cinderzin:BAABLgAECn84AAMdAAkJZAkgCgByAQAdAAkJZAkgCgByAQAaAAEJvwCMnwAHAAAAAA==.',
Cl='Clawhalla:BAAALgAECgcJEQAAAA==.',
Cn='Cnorthover:BAAALgAECgQJBAAAAA==.',
Co='Cobrallig:BAAALgAECggJDAAAAA==.Colexn:BAAALgAECgQJBAAAAA==.Comfyboi:BAAALgAECgcJDQAAAA==.Cong:BAABLgAFFH8JAAIeAAQJ/RO7FAAiAQAeAAQJ/RO7FAAiAQABLgAFFAYJFwAbAFAeAA==.Congdh:BAACLgAFFH8XAAIbAAYJUB5OCAChAQAbAAYJUB5OCAChAQAuAAQKfyUAAhsACQkPJNsJAPQCABsACQkPJNsJAPQCAAAA.Conmann:BAAALgAECgYJEgAAAA==.Corg:BAAALgADCgUJBQAAAA==.Cornchipz:BAAALgAECgMJAwAAAA==.Cowmage:BAAALgAECgEJAQAAAA==.',
Cr='Crit:BAAALgADCgcJCAABLgAECgkJHAAGACANAA==.Crossy:BAAALgAECgQJBQAAAA==.Crusade:BAAALgAECgYJDgAAAA==.Cryogenic:BAAALgAECgYJEgAAAA==.Cryptex:BAAALgADCgEJAQAAAA==.',
Cy='Cyrus:BAAALgAECgcJDQAAAA==.',
Cz='Czznkj:BAAALgADCgkJDgAAAA==.',
['Cá']='Cálívént:BAABLgAECn8cAAIUAAkJfQ68CgCHAQAUAAkJfQ68CgCHAQAAAA==.',
Da='Daak:BAAALgAECgEJAQABLgAECggJNAAFACcQAA==.Daangalangg:BAAALgAFFAIJAwAAAA==.Dabberoni:BAAALgAECgcJAQAAAA==.Dabthorne:BAAALgADCgEJAgAAAA==.Daegra:BAABLgAECn8UAAMRAAkJZBrwBQAIAgARAAYJtR3wBQAIAgASAAgJHg6JIgBxAQAAAA==.Daelin:BAAALgAECgEJAQAAAA==.Dankkush:BAACLgAFFH8IAAILAAQJaBGZbwAUAQALAAQJaBGZbwAUAQAuAAQKfxgAAgsACQmxHok/AP0BAAsACQmxHok/AP0BAAAA.Darkacedia:BAABLgAECn8jAAMTAAgJLh9bHQCmAgATAAgJLh9bHQCmAgAUAAMJyQ9aQwCoAAAAAA==.Darkrubie:BAAALgADCgMJAwAAAA==.Datbish:BAAALgAECgUJCAAAAA==.Dawgis:BAAALgAECgEJAQAAAA==.',
Db='Dbznz:BAAALgADCgYJBwAAAA==.',
De='Deadcell:BAABLgAECn8gAAMLAAcJPSGLMwAoAgALAAcJPSGLMwAoAgAfAAUJxiAFDgCEAQAAAA==.Deadcells:BAABLgAECn8UAAIeAAcJ+h0lDwDwAQAeAAcJ+h0lDwDwAQABLgAECgcJIAALAD0hAA==.Deadharvest:BAAALgAECgYJBwAAAA==.Deadlift:BAAALgAFFAIJBAAAAA==.Dealosed:BAACLgAFFH8NAAMRAAUJ2RAnBwDrAAASAAQJ+wkYDwD/AAARAAQJXRYnBwDrAAAuAAQKfzQABBEACQkvI0IBAP8CABEACQm7IkIBAP8CABIABwnOIMoRAJECACAABgllHpEHALoBAAAA.Decrepit:BAABLgAECn8rAAILAAkJDBnlJQBjAgALAAkJDBnlJQBjAgAAAA==.Defect:BAAALgAECgQJBAAAAA==.Defy:BAAALgAECgMJBAAAAA==.Demonclawz:BAABLgAECn8VAAITAAgJGgyLbABeAQATAAgJGgyLbABeAQAAAA==.Demonscar:BAAALgAECgUJCwAAAA==.Deo:BAAALgAECggJCAAAAA==.Dex:BAAALgAECgEJAQAAAA==.',
Dh='Dhaeverdh:BAAALgADCgIJAgAAAA==.',
Di='Diddious:BAAALgADCgMJAgAAAA==.Diremane:BAAALgAECgIJAgAAAA==.Disastacast:BAAALgAECgMJAwABLgAFFAMJBQAfAD4UAA==.Disastasmite:BAAALgADCgEJAQABLgAFFAMJBQAfAD4UAA==.Dive:BAACLgAFFH8JAAIIAAQJTSDpPABpAQAIAAQJTSDpPABpAQAuAAQKfyMAAwgACQklIuwmANcCAAgACAmOIewmANcCACEABQnyHHwLAB8BAAAA.',
Dk='Dkeruu:BAAALgAECgUJCAAAAA==.',
Do='Doinks:BAABLgAECn8VAAIFAAkJkhwxDgCxAgAFAAkJkhwxDgCxAgAAAA==.Dondozo:BAAALgAECgUJCwAAAA==.Doogru:BAABLgAECn8uAAICAAkJDxe3GAAhAgACAAkJDxe3GAAhAgAAAA==.Doogtwo:BAAALgADCgUJBgABLgAECgkJLgACAA8XAA==.Doufu:BAAALgAECgQJBAABLgAECgYJDAABAAAAAA==.',
Dr='Dracomaibois:BAAALgAECgYJCwAAAA==.Dragoneggs:BAACLgAFFH8QAAMaAAMJcxmuOADUAAAaAAMJcxmuOADUAAAiAAMJqQkyIACVAAAuAAQKfycAAxoACQnaHuwIAOkCABoACQnaHuwIAOkCACIABwkZE+YZADABAAAA.Dragonforce:BAAALgAECgYJDAABLgAECgkJEQABAAAAAA==.Draxan:BAAALgADCgcJCAAAAA==.Draxx:BAAALgAECgcJDgAAAA==.Dreammachine:BAABLgAECn8vAAIjAAkJ3CNeBQD7AgAjAAkJ3CNeBQD7AgAAAA==.Driipp:BAAALgAFFAMJBAAAAA==.Drizs:BAAALgADCgEJAQAAAA==.Drjoel:BAAALgADCgYJCAAAAA==.Drunkenutz:BAABLgAECn8jAAMFAAcJ4xfiHgCmAQAFAAcJ4xfiHgCmAQAVAAUJphSWNQAZAQABLgAECggJFAANAIMSAA==.',
Du='Duane:BAAALgADCgEJAQABLgAFFAUJGgAXADUPAA==.',
Dy='Dyab:BAAALgAECgEJAQAAAA==.',
['Dä']='Dälf:BAABLgAECn8cAAMPAAcJnCFlCwAKAgAPAAYJbiNlCwAKAgAHAAYJLRDfWABIAQABLgAFFAkJJQAdADcZAA==.',
Ea='Eatinoreos:BAABLgAECn8UAAIkAAkJ/BunCgCgAgAkAAkJ/BunCgCgAgAAAA==.',
Ec='Echidona:BAABLgAECn8bAAISAAgJERn8EwB2AgASAAgJERn8EwB2AgAAAA==.',
Ed='Edirii:BAAALgADCgEJAQAAAA==.',
Ee='Eelsky:BAAALgAECgcJEgAAAA==.',
Ef='Efvoidhunter:BAAALgAECgUJBQAAAA==.',
Ek='Eksi:BAEALgAECgQJBAABLgAFFAYJFQATAP8jAA==.',
El='Elenix:BAABLgAECn8aAAMOAAkJyRy0CAAGAwAOAAkJyRy0CAAGAwANAAMJhA3zgACQAAABLgAFFAMJBgAGABghAA==.Elinras:BAACLgAFFH8OAAIDAAMJgQzVaQDLAAADAAMJgQzVaQDLAAAuAAQKfyIAAgMACAl4Go44ABUCAAMACAl4Go44ABUCAAAA.Elliott:BAAALgADCgMJBQABLgADCggJDQABAAAAAA==.Elmesia:BAAALgAECggJAQAAAA==.Elonsalt:BAAALgAECgUJCgAAAA==.Eloris:BAAALgAECgcJDwAAAA==.Elrizon:BAAALgAECgUJBQAAAA==.Elvar:BAAALgAECggJDwABLgAECgQJBQABAAAAAA==.Elwynbria:BAAALgADCgcJBwAAAA==.Elynith:BAAALgAECgIJBAAAAA==.Elynni:BAABLgAECn8dAAIEAAcJ2RUIIADhAQAEAAcJ2RUIIADhAQAAAA==.',
Em='Emmylou:BAAALgAECgEJAwAAAA==.Emotett:BAAALgADCgQJBAAAAA==.Emz:BAACLgAFFH8KAAIgAAMJVR9yBwD8AAAgAAMJVR9yBwD8AAAuAAQKfysAAiAACAlqIuUAAAwDACAACAlqIuUAAAwDAAAA.',
En='Endboss:BAAALgAECgUJBQAAAA==.Enfuega:BAAALgAECgQJDQAAAA==.Eniar:BAACLgAFFH8MAAIGAAUJUAb3IAALAQAGAAUJUAb3IAALAQAuAAQKfxwAAwYACAnHFLguAMgBAAYACAnHFLguAMgBAAMABAl0CTDvALIAAAAA.',
Er='Eroninja:BAAALgAECgQJCAABLgAECgkJIAAIAKoXAA==.',
Eu='Eurong:BAACLgAFFH8SAAIkAAUJGhz7GQAzAQAkAAUJGhz7GQAzAQAuAAQKfxsAAiQACAl0H0waADICACQACAl0H0waADICAAAA.',
Ev='Evangelune:BAAALgAECgYJEgAAAA==.',
Ew='Ewright:BAAALgAECgEJAQABLgAECggJFwAjADwfAA==.',
Ez='Ezynuff:BAABLgAECn8kAAMNAAgJZRaMMwDWAQANAAcJwxaMMwDWAQAOAAUJKQjIagCXAAAAAA==.',
['Eï']='Eïr:BAAALgADCgcJCAAAAA==.',
Fa='Fakie:BAAALgAECgQJBAABLgAECgYJFAATACIfAA==.Fapple:BAABLgAECn8cAAMkAAgJwRZwJwCGAQAkAAcJPxVwJwCGAQAHAAQJiQaskgCEAAABLgAECgkJOAAiACkkAA==.Fatesprocket:BAAALgAECgMJBQAAAA==.Faïry:BAACLgAFFH8VAAMYAAUJ9xg6NQA4AQAYAAUJXxY6NQA4AQAlAAMJTwvNIQCtAAAuAAQKfzMAAxgACQkxHcoRAKoCABgACAmpH8oRAKoCACUABgkUCjYjALYAAAAA.',
Fe='Feardih:BAAALgADCgIJAgAAAA==.Felfrostette:BAAALgAECgEJAQAAAA==.Felheart:BAABLgAECn8WAAImAAgJmRLtGQCgAQAmAAgJmRLtGQCgAQAAAA==.Feltnutz:BAAALgADCgQJBQABLgAECggJFAANAIMSAA==.Felwyrm:BAAALgAECgYJCQABLgAFFAUJGgAXADUPAA==.Femboi:BAAALgADCgUJBQAAAA==.Fengshui:BAABLgAFFH8GAAIHAAIJuQ0pUgBxAAAHAAIJuQ0pUgBxAAAAAA==.Feralle:BAAALgADCgQJBAAAAA==.',
Fl='Flacidmon:BAAALgAECgcJCgAAAA==.Flutterina:BAAALgAECgIJAgAAAA==.Flyjin:BAABLgAECn8dAAMiAAgJEQ5pJABVAQAiAAcJLgxpJABVAQAaAAgJJg61OgA1AQAAAA==.Flylo:BAAALgADCgMJAwAAAA==.',
Fo='Folandras:BAAALgADCgcJDAABLgAECgcJLQAKALcbAA==.Forrestpump:BAAALgADCgMJAwAAAA==.',
Fr='Fries:BAECLgAFFH8HAAITAAQJpg/DXAD/AAATAAQJpg/DXAD/AAAuAAQKfyQAAxMACAkDJBQTAK8CABMACAkDJBQTAK8CABQAAQmHGhtgAE8AAAAA.Frozenpyre:BAAALgAECgYJEQAAAA==.',
Fu='Funch:BAACLgAFFH8MAAIUAAMJFg/rCgDYAAAUAAMJFg/rCgDYAAAuAAQKfzQAAhQACQk8GxQDAGUCABQACQk8GxQDAGUCAAAA.',
['Fè']='Fènrir:BAAALgAECgYJCAABLgAECggJFwAjADwfAA==.',
Ga='Gabbathegoo:BAABLgAFFH8HAAMTAAUJ2AukcwDMAAATAAQJwg6kcwDMAAAUAAEJHQNoJwA+AAAAAA==.Gainz:BAAALgAECgEJAgAAAA==.Gainzz:BAAALgAECgQJBgAAAA==.Galesdeyn:BAABLgAECn8VAAIbAAcJQhdVVQB7AQAbAAcJQhdVVQB7AQAAAA==.Garl:BAAALgAECgUJBQABLgAECgcJFAAIAD4dAA==.Garonnaa:BAABLgAFFH8OAAIJAAUJoAgmIgDJAAAJAAUJoAgmIgDJAAAAAA==.',
Gh='Ghari:BAABLgAECn8oAAILAAgJpROceQBnAQALAAgJpROceQBnAQAAAA==.',
Gi='Gilrog:BAABLgAECn8aAAILAAcJFQ0AmAAwAQALAAcJFQ0AmAAwAQAAAA==.Gingerlock:BAAALgAECgUJCgAAAA==.',
Gl='Gladiusmax:BAAALgADCgQJBAAAAA==.Gloryseeker:BAAALgAECgEJAQAAAA==.',
Gn='Gnoblin:BAAALgAECgQJCAAAAA==.Gnzz:BAAALgAECgcJDAAAAA==.',
Go='Gonz:BAAALgADCgcJBwAAAA==.',
Gr='Gravys:BAAALgAECgcJAwAAAA==.Greka:BAABLgAECn84AAIOAAgJjxIhKwCMAQAOAAgJjxIhKwCMAQAAAA==.Greyer:BAAALgAECgUJBgABLgAFFAMJCwAeALsiAA==.Greylooms:BAACLgAFFH8LAAMeAAMJuyLtFgAVAQAeAAMJuyLtFgAVAQACAAEJHRjYSgBHAAAuAAQKfzIAAx4ACQkwIfQCAAADAB4ACQkwIfQCAAADAAIABgmEHekyAOABAAAA.Gruuith:BAAALgADCgEJAQAAAA==.',
Gw='Gwath:BAAALgAECgEJAQAAAA==.',
Gy='Gynaris:BAAALgAECgMJBQAAAA==.',
['Gâ']='Gâinzz:BAAALgADCgQJBAAAAA==.',
Ha='Hakun:BAAALgAECgMJAwAAAA==.Happyfriend:BAACLgAFFH8aAAMXAAUJNQ+ZHABRAQAXAAUJNQ+ZHABRAQAjAAEJZAAfPAAvAAAuAAQKfykABCMACAlQEH8kALQBACMABwmiEX8kALQBABcACAnTFcUhALEBAAQAAQkPCrRwACQAAAAA.Haruko:BAAALgADCgQJBAAAAA==.',
He='Heemski:BAAALgAECgMJAwAAAA==.Hellaholy:BAAALgADCgYJBgAAAA==.Hellbourne:BAAALgADCggJDQAAAA==.Hellbrick:BAAALgADCgMJAwAAAA==.Hermitpurple:BAAALgADCgcJEwABLgAECgkJHAAGACANAA==.Heàl:BAABLgAECn8XAAMjAAgJPB+DDQB2AgAjAAgJPB+DDQB2AgAXAAEJFgfTeQApAAAAAA==.',
Hi='Hidejames:BAABLgAECn8lAAMRAAgJBxaoCAC0AQARAAgJBxaoCAC0AQASAAMJEQaGUABSAAAAAA==.Hidolo:BAAALgADCgUJBQAAAA==.Hims:BAABLgAECn8YAAMbAAYJFiEYNwAaAgAbAAYJFiEYNwAaAgAnAAEJtRxSKABFAAABLgAFFAgJKgAaAM0iAA==.',
Ho='Hoguy:BAAALgAECgYJEAAAAA==.Holofox:BAACLgAFFH8hAAIHAAcJZBoQBgCIAgAHAAcJZBoQBgCIAgAuAAQKf0gAAwcACQlFJq0AAN4DAAcACQlFJq0AAN4DAA8ABQkXDvQnALwAAAAA.Holycrow:BAAALgAECgMJAwAAAA==.Holytotem:BAAALgADCgEJAQAAAA==.Horman:BAABLgAECn8WAAIcAAYJmws0UQC2AAAcAAYJmws0UQC2AAAAAA==.',
Hu='Hunterishard:BAAALgAECggJEAABLgAECgkJEgABAAAAAA==.',
Hy='Hylda:BAAALgAECgMJBgAAAA==.',
['Hï']='Hïru:BAAALgAECgYJCAAAAA==.',
['Hô']='Hôlÿ:BAAALgAECgQJCQABLgAECggJCgABAAAAAA==.',
Ic='Iclapu:BAAALgAECgEJAgABLgAECgkJMQAFADAdAA==.',
Ig='Ignia:BAAALgADCgYJCgABLgAECggJNAAFACcQAA==.Igosduikanna:BAAALgADCgQJBQAAAA==.',
Ik='Ikerous:BAABLgAECn8bAAMnAAgJ3RkwBwAWAgAnAAgJ3RkwBwAWAgAmAAMJ1AmTVgCNAAAAAA==.',
Il='Ilililililli:BAABLgAECn8cAAMVAAgJ0Rc1JgCBAQAVAAgJ0Rc1JgCBAQAcAAIJdggkfABQAAAAAA==.Illumi:BAAALgAECgEJAQAAAA==.',
Im='Imadwagon:BAAALgADCgkJCAAAAA==.Imapandairl:BAABLgAECn8VAAIOAAcJrR6CEgCOAgAOAAcJrR6CEgCOAgAAAA==.Imfubar:BAAALgAECgMJAwAAAA==.Imhammered:BAABLgAECn8pAAIGAAgJ+BL0HwD4AQAGAAgJ+BL0HwD4AQAAAA==.Impullse:BAABLgAFFH8FAAINAAIJ7QQjZwBeAAANAAIJ7QQjZwBeAAAAAA==.',
Ir='Ironpally:BAAALgAECgYJBwAAAA==.Irsty:BAAALgAECgEJAQABLgAFFAYJDAAaAL8XAA==.',
It='Ithilwen:BAABLgAECn8oAAIXAAkJAR0fDQBnAgAXAAkJAR0fDQBnAgAAAA==.Itiswhatitiz:BAABLgAECn8dAAIYAAYJ3Bl9YAB5AQAYAAYJ3Bl9YAB5AQAAAA==.Itsybityshiv:BAACLgAFFH8OAAISAAQJJByLEgBjAQASAAQJJByLEgBjAQAuAAQKfzYAAxIACQmbHeAJAHsCABIACQmbHeAJAHsCABEAAQmgGPQfADMAAAAA.',
Iw='Iwillpull:BAAALgADCgcJDgAAAA==.',
Iz='Izzlirkkgazp:BAAALgAECgcJDgAAAA==.',
Ja='Jackiefox:BAAALgAECgIJBAAAAA==.Jahq:BAABLgAECn8VAAIbAAYJAyF8NAAnAgAbAAYJAyF8NAAnAgAAAA==.Jakarr:BAAALgAECgIJAgAAAA==.Jambs:BAAALgADCgEJAQAAAA==.Jandaelia:BAAALgADCgEJAQAAAA==.Jaysontatum:BAAALgADCgEJAQAAAA==.',
Je='Jeabuss:BAAALgADCgkJFQAAAA==.',
Jh='Jhani:BAABLgAECn8ZAAIIAAkJLwTXmwA9AQAIAAkJLwTXmwA9AQAAAA==.',
Ji='Jixn:BAAALgAECgMJBQAAAA==.',
Jo='Joethemage:BAABLgAECn8wAAIIAAkJASFVFwDHAgAIAAkJASFVFwDHAgAAAA==.Joobles:BAAALgAECgEJAQABLgAECgkJMQAFADAdAA==.Jormojo:BAAALgAECgQJBgAAAA==.Jotwnky:BAABLgAECn8eAAQoAAcJAyC3BQAMAgAoAAUJSSO3BQAMAgAUAAQJsxo7IwA+AQATAAMJGB9WuADoAAAAAA==.Jotwnkyy:BAACLgAFFH8JAAISAAQJAhO4GQA7AQASAAQJAhO4GQA7AQAuAAQKfzIAAhIABwkiIEYTAP4BABIABwkiIEYTAP4BAAEuAAQKBwkeACgAAyAA.',
Ju='Jungol:BAAALgAECgIJAgAAAA==.',
Ka='Kaela:BAAALgAECgEJAQAAAA==.Kaikova:BAAALgADCgcJCgAAAA==.Kaliban:BAAALgAECgQJBAAAAA==.Kaltank:BAAALgAECggJAwAAAA==.Kamin:BAABLgAECn8jAAIKAAgJwiHjAwARAwAKAAgJwiHjAwARAwAAAA==.Karoka:BAAALgADCgEJAQAAAA==.Kasitos:BAABLgAECn8UAAMTAAgJhxlUbwBXAQATAAgJhxlUbwBXAQAUAAEJnxEdbQA6AAAAAA==.Katamaran:BAAALgAFFAEJAQABLgAFFAUJFAAjAJETAA==.Kaykaypally:BAABLgAECn8fAAIDAAkJbhLiUQDIAQADAAkJbhLiUQDIAQAAAA==.',
Ke='Keis:BAEALgAECgYJBgABLgAFFAYJFQATAP8jAA==.Keledron:BAAALgADCgcJCgAAAA==.Kellan:BAABLgAECn8wAAIDAAcJ+hgkaACUAQADAAcJ+hgkaACUAQAAAA==.Kelos:BAAALgAECgYJCAABLgAFFAEJAgABAAAAAA==.Keylethel:BAAALgADCgEJAQAAAA==.',
Ki='Kideki:BAABLgAECn8nAAIGAAkJSyKHCQDoAgAGAAkJSyKHCQDoAgAAAA==.Kidori:BAAALgAECgEJAQABLgAECgkJJwAGAEsiAA==.Kilgharra:BAAALgADCggJEQAAAA==.Killakevv:BAAALgAECgEJAQAAAA==.Kinji:BAAALgADCgYJCAABLgAECgkJIAAIAKoXAA==.Kirisute:BAAALgAECgEJAQAAAA==.',
Ko='Kolsch:BAAALgADCgQJBAAAAA==.Koopa:BAAALgAECgQJBwABLgAECgkJHAAGACANAA==.Koriandar:BAABLgAECn8vAAIIAAgJZQuQggBsAQAIAAgJZQuQggBsAQAAAA==.Koyama:BAAALgADCgcJBwAAAA==.',
Kr='Kristysavage:BAABLgAECn9BAAMlAAgJHCIDBwCrAgAlAAgJHCIDBwCrAgAYAAEJQCKI6wBmAAAAAA==.Krul:BAAALgADCgkJCgAAAA==.Kruya:BAAALgAECgMJBAABLgAECgcJIgASAHURAA==.',
Ku='Kulaesca:BAAALgAECgIJAgAAAA==.',
Ky='Kynar:BAACLgAFFH8hAAMLAAcJDR+cEAAtAgALAAYJDR+cEAAtAgAJAAUJDhE9HADxAAAuAAQKfxcAAgsACAkuH60/ADoCAAsACAkuH60/ADoCAAAA.Kyperion:BAAALgAECgYJDQAAAA==.Kyrieirving:BAAALgAECgEJAQABLgADCgEJAQABAAAAAA==.Kyua:BAABLgAECn8UAAImAAYJBwjQOQC+AAAmAAYJBwjQOQC+AAAAAA==.',
La='Lambshot:BAABLgAECn8bAAMYAAcJ4SAbQwDMAQAYAAcJ4SAbQwDMAQAZAAEJ/AahjwArAAAAAA==.Lambsy:BAACLgAFFH8oAAQCAAgJ2BZ6AgDTAQACAAcJYRh6AgDTAQAeAAEJYAXBOgBDAAAKAAEJpAgtKQA7AAAuAAQKfx4AAwIACAmrIBARAMgCAAIACAl4HhARAMgCAB4AAQnuI0A5AEsAAAAA.Landwhalexxl:BAABLgAECn8XAAIIAAcJ9BGOpACPAQAIAAcJ9BGOpACPAQAAAA==.Laneera:BAAALgAECgQJDgAAAA==.',
Le='Ledronys:BAAALgADCgEJAQAAAA==.Ledsole:BAAALgADCgEJAQAAAA==.Lerat:BAABLgAECn8vAAIdAAkJ+iGeAQDMAgAdAAkJ+iGeAQDMAgAAAA==.',
Li='Lichkali:BAAALgADCgMJAwAAAA==.Liegh:BAAALgAECgEJAQAAAA==.Lightofhope:BAAALgAECggJEgAAAA==.Lihandra:BAAALgAECgYJCgAAAA==.Lillipup:BAAALgAECgQJBAAAAA==.Lillyy:BAAALgAECgIJAgABLgAFFAMJCAAIANwSAA==.Lilyy:BAACLgAFFH8IAAIIAAMJ3BKxdgDjAAAIAAMJ3BKxdgDjAAAuAAQKfycAAggACQmKILINAAcDAAgACQmKILINAAcDAAAA.Liria:BAAALgAECgYJDQAAAA==.Lisanalgaib:BAABLgAECn8ZAAIDAAgJlRc+VADCAQADAAgJlRc+VADCAQAAAA==.Liulei:BAAALgAECgQJAwAAAA==.Livelyjoker:BAAALgADCgMJAgAAAA==.Lizzimcguire:BAAALgAECgQJBAAAAA==.',
Lo='Loharfal:BAAALgADCgcJCAAAAA==.Loksham:BAAALgAECgkJEQAAAA==.Lokî:BAAALgAECgQJBAAAAA==.Loraen:BAABLgAECn8eAAIIAAgJegtVgABwAQAIAAgJegtVgABwAQAAAA==.Lorelei:BAAALgAECgEJAQABLgAECgkJJAAeABkbAA==.Lostep:BAABLgAFFH8IAAIEAAQJKQSyHQC4AAAEAAQJKQSyHQC4AAABLgAFFAcJGwANAA4UAA==.Lowkeyjz:BAAALgADCgIJAgAAAA==.',
Lu='Luasa:BAAALgADCgIJAgAAAA==.Lukadoncic:BAABLgAECn8ZAAMVAAcJaRO1NACKAQAVAAcJaRO1NACKAQAcAAMJ2Q3dcwBcAAABLgADCgEJAQABAAAAAA==.Lunarmon:BAAALgAECgUJDgAAAA==.Lunchable:BAABLgAECn8eAAIOAAgJnhmJFgBlAgAOAAgJnhmJFgBlAgAAAA==.Luxmalleo:BAAALgADCgkJDwABLgAECgcJIgASAHURAA==.',
Ly='Lykho:BAAALgAECgEJAQAAAA==.',
['Lè']='Lèa:BAAALgAECgEJAQABLgAECggJFwAjADwfAA==.',
['Lé']='Léblanc:BAABLgAECn8oAAIIAAkJ/x11PwAYAgAIAAkJ/x11PwAYAgAAAA==.',
Ma='Madam:BAAALgADCgMJBwAAAA==.Madday:BAAALgADCgcJDAAAAA==.Maelorus:BAAALgADCgkJEQAAAA==.Magicaltoast:BAAALgAECgcJEQAAAA==.Mahli:BAAALgAECgEJAQAAAA==.Makah:BAAALgAECgMJAwAAAA==.Makaroni:BAAALgADCgcJBwAAAA==.Makizenin:BAAALgADCgYJCAAAAA==.Malenia:BAAALgADCgUJBwAAAA==.Malthezar:BAAALgADCgEJAQAAAA==.Manticus:BAAALgADCgYJEAAAAA==.Maraud:BAAALgADCgEJAQAAAA==.Mari:BAAALgAECgMJBQABLgAFFAMJEAAEAKskAA==.Matroxx:BAABLgAECn8VAAMcAAcJSRo3LwA/AQAcAAQJex43LwA/AQAVAAcJfBA7MwAnAQABLgAFFAYJKgAMAJMZAA==.',
Me='Meat:BAAALgAECgUJBQAAAA==.Meatballz:BAAALgADCgEJAQAAAA==.Meatbeef:BAAALgADCgEJAQAAAA==.Meenoi:BAACLgAFFH8HAAILAAQJfw97bwAUAQALAAQJfw97bwAUAQAuAAQKfysAAgsACAnQIWYmAKICAAsACAnQIWYmAKICAAAA.Megamaid:BAAALgAECgYJCAAAAA==.Melysia:BAACLgAFFH8hAAIHAAcJgBv6BwBeAgAHAAcJgBv6BwBeAgAuAAQKfzoAAwcACQl0IP8MANQCAAcACQl0IP8MANQCAA8AAgmmCUNCAEgAAAAA.Metalgear:BAAALgADCgYJDAAAAA==.',
Mi='Miadas:BAAALgAFFAEJAQABLgAFFAMJBgAPAJQaAA==.Midgeyfam:BAAALgAECgIJAgAAAA==.Midgeyzen:BAAALgAECgQJBAAAAA==.Mika:BAAALgAFFAEJAQABLgAFFAMJEAAEAKskAA==.Mindi:BAAALgAECgMJAwAAAA==.Mizakina:BAAALgAECgEJAQAAAA==.Mizby:BAAALgADCgIJAwABLgADCgMJAwABAAAAAA==.Mizry:BAAALgADCgMJAwAAAA==.',
Mo='Moardotsnow:BAABLgAECn8oAAMTAAkJ4SS3OQDuAQATAAUJ9iS3OQDuAQAUAAQJvST+EAAnAQAAAA==.Moby:BAABLgAECn8aAAMoAAcJngYPGwDUAAATAAcJ8wTUrgDhAAAoAAYJ7AUPGwDUAAAAAA==.Moistmender:BAAALgAECgkJEgAAAA==.Moonleaf:BAAALgAECgkJAwAAAA==.Moosaki:BAAALgAECgkJCQABLgAECgkJMgASAIwjAA==.Mortui:BAAALgAECgQJBQABLgAFFAYJKgAMAJMZAA==.Mous:BAAALgADCgMJAwAAAA==.',
Mu='Muffasah:BAAALgAECgEJAQAAAA==.Munchkinn:BAAALgADCgYJBgAAAA==.Murbella:BAAALgADCgEJAQABLgAECgcJFQAbABgiAA==.Murridan:BAABLgAECn8pAAIbAAkJoiKUCQA7AwAbAAkJoiKUCQA7AwAAAA==.',
My='Mykaela:BAABLgAECn8YAAMWAAcJsQYwLgCkAAAWAAcJwgUwLgCkAAADAAQJJAKLQQFdAAAAAA==.Myraela:BAAALgAECgYJDQABLgAECgkJIAAJAEshAA==.',
['Më']='Mëow:BAABLgAECn8kAAIQAAgJkAYuNQC+AAAQAAgJkAYuNQC+AAAAAA==.',
Na='Narrath:BAAALgAECgMJBQAAAA==.Nayalaah:BAABLgAECn8YAAIYAAcJiwtYdQBJAQAYAAcJiwtYdQBJAQAAAA==.',
Ne='Nellybearwl:BAAALgADCgYJBgAAAA==.Nerfherder:BAAALgAECgQJBQAAAA==.Nexes:BAAALgAECgUJBwAAAA==.',
Ni='Nicotinee:BAAALgAECgMJAwAAAA==.Nightbané:BAAALgAECgIJBQAAAA==.Nirina:BAABLgAECn8gAAIYAAcJCQctmQAAAQAYAAcJCQctmQAAAQAAAA==.Nixie:BAAALgAECgYJBgAAAA==.',
Nn='Nnuiq:BAAALgAECgEJAQAAAA==.',
No='Nojaw:BAAALgADCgcJBwAAAA==.Noraeri:BAAALgAECgYJBgABLgAECgkJIAAIAKoXAA==.Northsouth:BAAALgAECgEJAQAAAA==.Notdicey:BAAALgAFFAIJAgAAAA==.Notstephen:BAAALgAECgUJCgAAAA==.Novo:BAAALgAECgYJCwAAAA==.',
Nu='Nukefury:BAABLgAECn8nAAMMAAkJTCHzAgDYAgAMAAkJMx7zAgDYAgAOAAYJZyR0GgBAAgABLgAFFAMJBQAfAD4UAA==.',
Od='Oddstriker:BAAALgADCgYJAwAAAA==.',
Oi='Oiflar:BAAALgAECgcJCAABLgAECgkJOAAiACkkAA==.',
Ol='Oliveoil:BAAALgADCgEJAQAAAA==.',
Om='Omnidh:BAACLgAFFH8WAAIbAAYJsBTwJgB0AQAbAAYJsBTwJgB0AQAuAAQKfyQAAhsACQliIKwPAAEDABsACQliIKwPAAEDAAAA.Omnihead:BAAALgADCgYJBgAAAA==.',
On='Onepavo:BAAALgAECgQJBAAAAA==.Onlybakshots:BAAALgAECgYJCAAAAA==.',
Op='Oppose:BAAALgAECgYJEgAAAA==.',
Or='Orestes:BAAALgAFFAEJAQAAAA==.Orexion:BAABLgAECn8VAAMeAAgJuwv0MgDvAAACAAcJ8wmdRgAhAQAeAAYJ8gv0MgDvAAAAAA==.Ormagöden:BAABLgAECn8oAAIfAAkJMhSMAwBPAgAfAAkJMhSMAwBPAgAAAA==.',
Oz='Ozzpoxzo:BAAALgAECgUJBgAAAA==.',
Pa='Palladean:BAABLgAECn8uAAIDAAgJhhU0VADDAQADAAgJhhU0VADDAQAAAA==.Pandemic:BAAALgAECgMJAwAAAA==.Parabow:BAAALgAECgMJAwAAAA==.Parador:BAAALgAECgIJAQABLgAECgMJAwABAAAAAA==.Pastasauce:BAABLgAECn8dAAIDAAcJtg6bhwBrAQADAAcJtg6bhwBrAQAAAA==.',
Pc='Pcpmlsd:BAAALgADCgkJDAAAAA==.',
Pe='Penelohpe:BAAALgAECgcJCgABLgAECggJIwAKAMIhAA==.Penwork:BAAALgAECggJCwAAAA==.Penz:BAABLgAECn8WAAILAAYJpxgxbwB+AQALAAYJpxgxbwB+AQAAAA==.Perrian:BAAALgADCgMJBAAAAA==.Petey:BAAALgADCgEJAgAAAA==.',
Ph='Phamine:BAAALgAECgMJAwAAAA==.Phatt:BAAALgAECgEJAQAAAA==.Philex:BAEALgAECgYJBwABLgAFFAYJFQATAP8jAA==.Phoenixfyre:BAAALgAECgcJBwAAAA==.Phoon:BAECLgAFFH8VAAITAAYJ/yOHFwDbAQATAAYJ/yOHFwDbAQAuAAQKfyEABBMACAmoHkMdAKYCABMACAmoHkMdAKYCABQAAglGGVVJAJIAACgAAQkAAKAqAEoAAAAA.Phøenixbane:BAABLgAECn8hAAIDAAgJxh7vJQBiAgADAAgJxh7vJQBiAgAAAA==.',
Pi='Piggy:BAAALgAECgEJAgAAAA==.Pita:BAAALgAECgcJCwAAAA==.Pitaya:BAAALgAECgcJEwAAAA==.',
Pl='Plaguefist:BAAALgAECgkJEQAAAA==.Plata:BAAALgAECgcJCgAAAA==.Plikxy:BAAALgADCgkJCQAAAA==.Plumsàuce:BAAALgAECgEJAQAAAA==.',
Po='Pocketmage:BAAALgAECgQJBQAAAA==.',
Pr='Praytroxx:BAAALgADCgEJAQABLgAFFAYJKgAMAJMZAA==.Premonitions:BAABLgAECn8fAAINAAgJVBSbOgC3AQANAAgJVBSbOgC3AQAAAA==.Premune:BAABLgAECn84AAQGAAkJ6x9cDQCuAgAGAAkJ6x9cDQCuAgAWAAgJ+RBCGABNAQADAAIJOgioGwFjAAAAAA==.Prion:BAACLgAFFH8KAAIbAAMJNwuQYgC3AAAbAAMJNwuQYgC3AAAuAAQKfxkAAhsACAklFKdPAIsBABsACAklFKdPAIsBAAAA.',
Ps='Psycs:BAAALgAECgYJDgAAAA==.',
Pu='Pulga:BAAALgADCgIJAgAAAA==.Pull:BAAALgADCgcJCQABLgAFFAQJCQAIAE0gAA==.Purplemage:BAAALgAECgkJCgABLgAECgkJEgABAAAAAA==.',
Pw='Pwincess:BAAALgADCgMJAwAAAA==.',
['Pú']='Púre:BAAALgAECgIJAgAAAA==.',
Qu='Quigly:BAAALgAECgYJCgAAAA==.Quìts:BAABLgAECn8mAAMTAAgJSB2FOgAiAgATAAgJrhuFOgAiAgAUAAMJzReEIwCIAAAAAA==.Quíts:BAAALgADCgEJAQABLgAECggJJgATAEgdAA==.',
Ra='Radeøn:BAAALgAECgEJAQAAAA==.Ragingtauren:BAAALgAECgMJBAAAAA==.Rainbowdots:BAAALgAECgcJDgAAAA==.Raine:BAACLgAFFH8bAAINAAcJDhSJAgC9AQANAAcJDhSJAgC9AQAuAAQKfx4AAw0ACAkhHysfACQCAA0ACAkhHysfACQCAA4ABAkKGWlVAPAAAAAA.Raistlain:BAAALgAECgcJEwAAAA==.Raistlin:BAABLgAECn8gAAMmAAkJ7BZ3EwDqAQAmAAkJ7BZ3EwDqAQAbAAEJywOo8AAiAAAAAA==.Ralfio:BAABLgAECn84AAIiAAkJKSQBAQCiAwAiAAkJKSQBAQCiAwAAAA==.Ralfiosky:BAAALgAECggJEQABLgAECgkJOAAiACkkAA==.Ramennoodlez:BAAALgAECgQJBAAAAA==.Rat:BAAALgAFFAIJAgAAAA==.Ratren:BAAALgADCgQJAwAAAA==.Ravalyn:BAAALgADCgkJCgAAAA==.Raynith:BAACLgAFFH8GAAMPAAMJlBrFCgD0AAAPAAMJlBrFCgD0AAAQAAIJnwjKLABRAAAuAAQKfysABA8ACQn6G1sJACECAA8ABwkjIVsJACECACQABwlPGMkjAJ4BABAACAnDEVIcAFgBAAAA.',
Re='Readycheck:BAABLgAECn8hAAMQAAkJGA+FIAA2AQAQAAgJyQ+FIAA2AQAkAAYJ9g5NPQAMAQAAAA==.Reckalossi:BAAALgAECgkJAQABLgAFFAMJDgADAIEMAA==.Redcows:BAAALgAECgUJBQAAAA==.Redeemed:BAAALgADCgEJAQAAAA==.Reikon:BAABLgAECn8iAAIDAAgJzB1pNQBNAgADAAgJzB1pNQBNAgAAAA==.Remulous:BAABLgAECn8VAAIYAAcJyQjJoADwAAAYAAcJyQjJoADwAAAAAA==.Revelaen:BAACLgAFFH8MAAIaAAQJnBNtLAADAQAaAAQJnBNtLAADAQAuAAQKfyMAAxoACQlxHQ0JAOcCABoACQlxHQ0JAOcCAB0ABQlYBowoANwAAAAA.',
Ri='Rick:BAACLgAFFH8iAAMYAAUJAiayEAC1AQAYAAUJAiayEAC1AQAZAAEJXBoLJQBUAAAuAAQKfysAAxgACQmkI3MMAOUCABkACAlpI+QJAAUDABgACQlqI3MMAOUCAAAA.Rickers:BAAALgAECgMJAwABLgAFFAUJIgAYAAImAA==.Rikosan:BAAALgAECgEJAwAAAA==.',
Ro='Roarz:BAAALgADCgkJCQAAAA==.Rollthebones:BAAALgADCgMJAwAAAA==.Roman:BAABLgAECn8hAAMGAAYJayVuEwBqAgAGAAYJayVuEwBqAgADAAQJnRkyrQAoAQABLgAFFAUJDAAiAJglAA==.Roust:BAAALgAECgUJBQABLgAFFAQJCQAIAE0gAA==.',
Ru='Runinfear:BAAALgADCgYJBgAAAA==.',
Sa='Saba:BAAALgAECgMJBAAAAA==.Saephora:BAABLgAECn8wAAIIAAkJpgYlhwBjAQAIAAkJpgYlhwBjAQAAAA==.Saerea:BAACLgAFFH8IAAILAAMJNBnfgwDtAAALAAMJNBnfgwDtAAAuAAQKfyAAAgsACAkuH30zAGkCAAsACAkuH30zAGkCAAAA.Saggypants:BAAALgAECgEJAQAAAA==.Sahhm:BAABLgAFFH8FAAIDAAMJsR36TAAFAQADAAMJsR36TAAFAQAAAA==.Salali:BAAALgAECgQJBwAAAA==.Samael:BAAALgAECgMJBgABLgAFFAQJCwARAMQSAA==.Sammel:BAABLgAECn8ZAAMjAAgJ9BhXFABNAgAjAAgJ9BhXFABNAgAXAAEJCRHxcQAxAAAAAA==.Sandmanslim:BAAALgAECgUJBQAAAA==.Sathreina:BAACLgAFFH8KAAIDAAQJMwo2TQAEAQADAAQJMwo2TQAEAQAuAAQKfyoAAgMACQlEFrJGAOcBAAMACQlEFrJGAOcBAAAA.Satinofhell:BAAALgAECgQJBAAAAA==.Sawbones:BAAALgADCggJCQAAAA==.',
Sc='Scaries:BAABLgAECn8XAAIFAAkJKRtoEgCAAgAFAAkJKRtoEgCAAgAAAA==.Schmeckles:BAAALgAFFAIJAgAAAA==.Scootzmcgee:BAAALgAECgUJCwAAAA==.',
Se='Seikura:BAAALgADCgMJAwAAAA==.Sekii:BAEALgAECgQJBAABLgAFFAYJFQATAP8jAA==.Sekimaru:BAACLgAFFH8VAAISAAUJ+RHgGwAuAQASAAUJ+RHgGwAuAQAuAAQKfzQAAxIACQnXGk0KAHMCABIACQnXGk0KAHMCABEAAQmnBygoAC0AAAAA.Selok:BAAALgAFFAEJAgAAAA==.',
Sh='Shaddik:BAAALgAECgQJBgABLgAECggJEAABAAAAAA==.Shadowisbad:BAAALgAECgkJEwAAAA==.Shadpriest:BAAALgAECggJEAAAAA==.Shaeledoran:BAACLgAFFH8QAAILAAUJZBvoSQBOAQALAAUJZBvoSQBOAQAuAAQKf0EAAgsACQnHII0ZAKUCAAsACQnHII0ZAKUCAAAA.Shamaneggs:BAABLgAFFH8GAAINAAMJKgziUACdAAANAAMJKgziUACdAAAAAA==.Shamatroxx:BAACLgAFFH8qAAIMAAYJkxnEAgCfAQAMAAYJkxnEAgCfAQAuAAQKfzEAAgwACQlyJMsAAE4DAAwACQlyJMsAAE4DAAAA.Shampomaster:BAAALgADCgMJAwAAAA==.Sheist:BAAALgAFFAIJAwABLgAFFAQJCQAIAE0gAA==.Shenzuu:BAAALgAECgQJBQAAAA==.Shieetz:BAAALgAECgYJEQAAAA==.Shlomie:BAAALgADCggJGgAAAA==.Shlomiel:BAAALgADCgEJAQAAAA==.Shlomieo:BAAALgADCgkJFwAAAA==.Shocknasty:BAAALgAECgEJAQAAAA==.Shorttemper:BAAALgADCgkJDQAAAA==.Shänk:BAABLgAECn8iAAMSAAcJdRH+IQB1AQASAAcJdRH+IQB1AQARAAQJVgs1FQDNAAAAAA==.',
Si='Sibirica:BAAALgADCgEJAQAAAA==.Siena:BAABLgAECn8UAAMOAAgJXw6vTAAVAQAOAAYJbAuvTAAVAQANAAgJ4gNScQD4AAAAAA==.Silith:BAAALgAECgYJDAAAAA==.Silre:BAABLgAECn8YAAIUAAcJ7Q8tEQAkAQAUAAcJ7Q8tEQAkAQAAAA==.Silverfangg:BAAALgAECgMJAwAAAA==.Sinergy:BAABLgAECn8UAAITAAYJIh8zRAD/AQATAAYJIh8zRAD/AQAAAA==.Siz:BAAALgAECgYJCAAAAA==.',
Sk='Skiddlebutt:BAAALgADCgMJAgAAAA==.Skirmish:BAABLgAECn8ZAAILAAYJLRRMjwA+AQALAAYJLRRMjwA+AQAAAA==.Skyray:BAAALgADCgUJBQAAAA==.',
Sl='Slappeepries:BAAALgADCgEJAQABLgAECgkJEgABAAAAAA==.Slappeey:BAAALgAECgkJEgAAAA==.',
Sn='Snapbean:BAAALgADCgEJAQAAAA==.Snarls:BAAALgAECgIJAgABLgAECgkJOAAiACkkAA==.Snaxx:BAAALgAECgMJBgABLgAECgcJDQABAAAAAA==.Snorunt:BAAALgAECgYJEAAAAA==.Snuudle:BAACLgAFFH8OAAMLAAMJViBIJgD9AAALAAMJViBIJgD9AAAfAAEJsBU1IgBEAAAuAAQKf00AAwsACQkmJUoOAPECAAsACQlZJEoOAPECAB8ACAnPJKwCAMgCAAAA.',
So='Solokills:BAAALgAECgcJDwAAAA==.Soulreaperqt:BAAALgAECgMJAwABLgAECgUJCwABAAAAAA==.Soundtrack:BAAALgADCgEJAQABLgAECgkJHAAGACANAA==.',
Sp='Spaceman:BAAALgAECgQJBwABLgAFFAUJGgAXADUPAA==.Sproxx:BAAALgAECgEJAgABLgAECgkJEgABAAAAAA==.',
Sq='Sqlpal:BAABLgAECn8cAAMbAAcJox60LwA9AgAbAAcJox60LwA9AgAmAAQJOB77PgAAAQAAAA==.Squirrels:BAABLgAECn80AAMFAAgJJxBDJACBAQAFAAgJJxBDJACBAQAVAAQJuwXsUgCGAAAAAA==.Squirtstorm:BAABLgAECn86AAINAAkJLCCNCAAdAwANAAkJLCCNCAAdAwAAAA==.Squirtz:BAAALgADCgUJBAAAAA==.',
Sr='Srgntsnoop:BAAALgADCgUJBQAAAA==.',
St='Stabmywood:BAABLgAECn8yAAMSAAkJjCOmAwD/AgASAAkJjCOmAwD/AgAgAAEJNxZiIAA+AAAAAA==.Sthella:BAAALgADCgMJAwABLgAECgUJDQABAAAAAA==.Stillcreepin:BAAALgADCgkJCQAAAA==.Stompy:BAAALgADCgkJEAABLgAFFAUJFAAjAJETAA==.Storienn:BAABLgAECn8VAAMDAAkJVhYAVwC8AQADAAgJmBYAVwC8AQAWAAIJ1hXENQB8AAAAAA==.Stormzpaly:BAAALgADCgkJCQAAAA==.Stormßlessed:BAAALgADCgUJBQAAAA==.Strokemyhorn:BAAALgAECgQJBQAAAA==.',
Su='Subarashii:BAAALgAECgEJAQABLgAECgYJEQABAAAAAA==.Suküna:BAACLgAFFH8LAAIbAAMJPBg5VgDYAAAbAAMJPBg5VgDYAAAuAAQKfzMAAhsACQkIIUgZAHMCABsACQkIIUgZAHMCAAAA.Sunglo:BAAALgAECgUJBQAAAA==.Superbean:BAAALgAECgEJAQAAAA==.Surefire:BAAALgAECgEJAQAAAA==.',
Sw='Swaption:BAACLgAFFH8OAAINAAUJDCTfCgD9AQANAAUJDCTfCgD9AQAuAAQKfysAAg0ACAkKJVIKAAQDAA0ACAkKJVIKAAQDAAAA.Swolebane:BAAALgADCgUJBQAAAA==.',
Sy='Sybaü:BAAALgAECgYJDAAAAA==.Synchronize:BAABLgAECn8YAAILAAcJPhSEeQCRAQALAAcJPhSEeQCRAQAAAA==.Syrelia:BAABLgAECn87AAIIAAkJKBmqKABxAgAIAAkJKBmqKABxAgAAAA==.',
Ta='Takèda:BAABLgAECn8lAAIlAAgJByDrDQBGAgAlAAgJByDrDQBGAgAAAA==.Taldain:BAABLgAECn8XAAMQAAgJcRvZEwCnAQAkAAgJ4xlJGQD1AQAQAAcJABnZEwCnAQAAAA==.Talonstrykz:BAABLgAECn8VAAISAAgJ0A42IgDnAQASAAgJ0A42IgDnAQAAAA==.Tankdeesnuts:BAABLgAECn84AAIKAAgJewdKJgDyAAAKAAgJewdKJgDyAAAAAA==.Tashalle:BAAALgAECgEJAQABLgAECgkJKAAXAAEdAA==.Tassarosea:BAAALgAECgMJAwABLgAECgQJBAABAAAAAA==.Tauloe:BAABLgAECn8pAAIOAAcJkQ7gPgAoAQAOAAcJkQ7gPgAoAQAAAA==.Tayna:BAAALgAECgYJCQAAAA==.',
Te='Teejaydh:BAAALgADCgEJAQAAAA==.Tellamon:BAABLgAECn8aAAIDAAgJrhNfegBuAQADAAgJrhNfegBuAQAAAA==.Tetanus:BAAALgAECgQJBwABLgAECgYJEgABAAAAAA==.Teyassha:BAAALgAECgEJBAAAAA==.',
Th='Thomo:BAABLgAECn8dAAMYAAkJ6gdtXACEAQAYAAkJmAdtXACEAQAlAAYJ2gSgHAAMAQAAAA==.Throatfist:BAAALgAFFAIJBAABLgAFFAYJFwAbAFAeAA==.Throme:BAAALgAECgkJEAAAAA==.Thunk:BAACLgAFFH8JAAIOAAMJPRfdDQAMAQAOAAMJPRfdDQAMAQAuAAQKfyYAAg4ACQmXJfUDAGADAA4ACQmXJfUDAGADAAAA.',
Ti='Timdawg:BAACLgAFFH8IAAIIAAQJMB59PQBnAQAIAAQJMB59PQBnAQAuAAQKfxQAAggACAn1IlgYAMECAAgACAn1IlgYAMECAAEuAAQKBQkTAAEAAAAA.',
Tj='Tjkrollsaway:BAAALgAECgIJAgAAAA==.',
To='Todrick:BAAALgAECgEJAQAAAA==.Tomotostein:BAACLgAFFH8KAAIDAAMJCg90aQDLAAADAAMJCg90aQDLAAAuAAQKfzIAAgMACQn8ICYMAPwCAAMACQn8ICYMAPwCAAAA.Tonobaggins:BAAALgADCggJCAAAAA==.Toothluss:BAAALgADCgMJAgAAAA==.Totemnutz:BAABLgAECn8UAAMNAAgJgxK5MwDVAQANAAgJgxK5MwDVAQAOAAUJ5RFPQwAWAQAAAA==.',
Tr='Tradrael:BAAALgAECgEJAQAAAA==.Tristîtia:BAAALgAFFAEJAQAAAA==.Trulu:BAAALgAECgIJAgAAAA==.',
Ts='Tsume:BAABLgAECn8UAAIYAAYJyxisdABKAQAYAAYJyxisdABKAQAAAA==.',
Tu='Tum:BAAALgAECgcJDQABLgAECgcJDQABAAAAAA==.Tumlek:BAAALgAECgIJAgAAAA==.Tunobuffpapi:BAAALgAFFAIJAgAAAA==.',
Ty='Tyrinn:BAAALgAECgkJEgAAAA==.Tystian:BAAALgAECgUJDgAAAA==.Tyv:BAABLgAECn80AAMhAAkJAxbgAgAFAgAhAAkJAxbgAgAFAgAIAAYJKgYn0ADsAAAAAA==.',
Ur='Urä:BAAALgAECgIJAgAAAA==.',
Va='Vainatetosix:BAABLgAECn8VAAILAAgJVwzhiwBEAQALAAgJVwzhiwBEAQAAAA==.Valindra:BAAALgAECgUJCQAAAA==.Vallodon:BAABLgAECn8hAAIIAAkJ6SAaNABBAgAIAAkJ6SAaNABBAgAAAA==.Valyndra:BAAALgAECgYJCAAAAA==.Vanquizsher:BAAALgAECgIJAgAAAA==.Vanwolfy:BAABLgAECn8jAAIKAAkJfw59FgCEAQAKAAkJfw59FgCEAQAAAA==.',
Ve='Velanthris:BAAALgAECgMJBQABLgAECgYJCAABAAAAAA==.Velectran:BAABLgAECn8qAAIDAAgJJRfdTADWAQADAAgJJRfdTADWAQABLgAECgkJOwAIACgZAA==.Velorian:BAAALgAECgIJAgAAAA==.Vesperi:BAAALgAECggJCAABLgAECgkJOwAIACgZAA==.',
Vi='Vilgehkfrúna:BAAALgAECgEJAQAAAA==.Virdreth:BAAALgAECgEJAgAAAA==.Vish:BAAALgAECgUJBgAAAA==.',
Vo='Vortash:BAAALgAECgQJBQAAAA==.',
Vy='Vynle:BAAALgAECgQJBgAAAA==.Vyrthos:BAAALgADCgkJCQABLgAFFAMJCAAIABMDAA==.',
['Vä']='Vämpira:BAAALgAECgYJCwAAAA==.',
Wa='Warheimer:BAAALgAECgMJBAAAAA==.Warrgodx:BAABLgAECn8XAAMCAAcJFhiDOABcAQACAAcJFhiDOABcAQAeAAMJkxLvQQCzAAAAAA==.Wartroxx:BAAALgAECgcJDwABLgAFFAYJKgAMAJMZAA==.',
We='Welcome:BAAALgADCgYJBAAAAA==.Wengja:BAABLgAECn8gAAQVAAcJryULBwDqAgAVAAcJryULBwDqAgAFAAEJ9QSVjgAnAAAcAAEJAACmiQAlAAAAAA==.',
Wh='Wheri:BAAALgADCggJCAABLgAECgkJJAAeABkbAA==.Whoknows:BAABLgAECn8VAAIbAAcJGCLQIQBAAgAbAAcJGCLQIQBAAgAAAA==.',
Wi='Wiz:BAAALgAECgQJBgAAAA==.',
Wo='Wolfchef:BAAALgAECgYJDAAAAA==.Woodkin:BAAALgAECgUJEQAAAA==.',
Wr='Wrongwookie:BAABLgAECn8iAAIOAAkJxR2mCAAIAwAOAAkJxR2mCAAIAwAAAA==.',
Wy='Wyrmbreaker:BAAALgAECgYJCQAAAA==.',
Xi='Xiak:BAAALgAECgEJAQABLgAFFAMJBgAPAJQaAA==.',
Ya='Yako:BAAALgAECgIJAgAAAA==.',
Ye='Yereka:BAAALgADCgQJBAAAAA==.',
Yo='Yoomesbonds:BAAALgAFFAEJAQAAAA==.Youtube:BAACLgAFFH8qAAMaAAgJzSJVAwDHAgAaAAgJzSJVAwDHAgAdAAQJ8CFFBAAnAQAuAAQKfyMAAx0ACQkrJVQDAOoCAB0ABwmsJVQDAOoCABoABwkQIsskAK8BAAAA.Yoyohunty:BAAALgAECgEJAgAAAA==.Yozki:BAABLgAECn8fAAIIAAkJTh1bMQBNAgAIAAkJTh1bMQBNAgAAAA==.',
Yt='Ytix:BAAALgAECgMJAwAAAA==.',
Yu='Yuji:BAAALgAECgEJAQABLgAFFAMJCQAOAD0XAA==.Yuuki:BAAALgAECgQJBQABLgAFFAQJCwARAMQSAA==.Yuulia:BAABLgAECn8kAAMeAAkJGRt3CgA3AgAeAAkJqhp3CgA3AgAKAAYJeRhvGQCGAQAAAA==.',
Yv='Yvonnê:BAAALgADCgEJAQAAAA==.',
Za='Zabada:BAAALgADCgkJHwAAAA==.Zaee:BAAALgAECgMJBgABLgAFFAQJBwANACQLAA==.Zariee:BAABLgAECn8fAAImAAgJTQ35IgBNAQAmAAgJTQ35IgBNAQAAAA==.',
Ze='Zemsen:BAACLgAFFH8IAAIIAAMJEwMGMgDgAAAIAAMJEwMGMgDgAAAuAAQKfzAAAwgACQmjGOY8AIQCAAgACQmjGOY8AIQCACEAAgneBcAZAEoAAAAA.Zentrea:BAAALgAECgIJAgABLgAFFAUJFAAjAJETAA==.Zenyea:BAAALgAECgQJBAABLgAFFAUJFAAjAJETAA==.Zetta:BAACLgAFFH8UAAIjAAUJkROnDAB9AQAjAAUJkROnDAB9AQAuAAQKfysAAiMACQmbH+sMALUCACMACQmbH+sMALUCAAAA.',
Zo='Zoguk:BAAALgADCgEJAQAAAA==.Zoktavir:BAAALgADCgcJCAAAAA==.Zoltan:BAABLgAECn8VAAIIAAYJnQve2QA9AQAIAAYJnQve2QA9AQAAAA==.Zorin:BAAALgADCgcJDgAAAA==.',
Zy='Zyndrael:BAABLgAECn8sAAIDAAkJVR6zGgCaAgADAAkJVR6zGgCaAgAAAA==.',
['Zâ']='Zâgs:BAAALgADCgYJCAAAAA==.',
['Êl']='Êlytz:BAAALgAECggJEAAAAA==.',
['ßl']='ßlue:BAACLgAFFH8GAAIFAAQJehFeJgAGAQAFAAQJehFeJgAGAQAuAAQKf2EABAUACQliIOoFANgCAAUACQliIOoFANgCABUACAnFGsoUAGICABwAAwm+DMFfAI0AAAAA.',
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
