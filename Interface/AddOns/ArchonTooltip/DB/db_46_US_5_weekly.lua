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

local lookup = {'Unknown-Unknown','Warrior-Fury','Paladin-Retribution','DeathKnight-Unholy','Priest-Holy','Monk-Brewmaster','Paladin-Holy','Druid-Restoration','Mage-Frost','DeathKnight-Blood','Warrior-Protection','Shaman-Enhancement','Shaman-Restoration','Shaman-Elemental','Rogue-Assassination','Rogue-Subtlety','Warlock-Demonology','Warlock-Destruction','Monk-Mistweaver','Paladin-Protection','Priest-Discipline','Hunter-BeastMastery','Hunter-Marksmanship','Evoker-Augmentation','DemonHunter-Devourer','Monk-Windwalker','Evoker-Devastation','Warrior-Arms','Rogue-Outlaw','DemonHunter-Vengeance','Mage-Arcane','Evoker-Preservation','Priest-Shadow','Druid-Feral','Druid-Balance','Hunter-Survival','DemonHunter-Havoc','Warlock-Affliction','Druid-Guardian','DeathKnight-Frost',}
local provider = {region='US',realm='Akama',name='US',type='weekly',zone=46,date='2026-05-23',data={Ac='Accost:BAAALgAECgQJBgAAAA==.Acronica:BAAALgAECgEJAQAAAA==.',
Ad='Adagar:BAAALgAECgYJDgAAAA==.Adesha:BAAALgADCgYJBgAAAA==.',
Ae='Aeloria:BAAALgAECgcJBgAAAA==.Aeratedlol:BAAALgAFFAIJAwABLgAFFAQJBAABAAAAAA==.Aethandor:BAAALgAECgUJDQAAAA==.',
Ak='Akassa:BAABLgAECn8eAAICAAYJqAmETADrAAACAAYJqAmETADrAAAAAA==.Akavaleera:BAAALgAECgQJBwAAAA==.Aknologia:BAAALgADCgYJBgABLgAECgMJAwABAAAAAA==.Akíto:BAAALgAECgMJAwAAAA==.',
Al='Alaric:BAAALgADCgUJBQAAAA==.Alecto:BAABLgAECn8ZAAIDAAkJFAs3agB6AQADAAkJFAs3agB6AQAAAA==.Algo:BAAALgAECgUJBQABLgAECgkJQAAEAO0XAA==.Alune:BAAALgADCgYJDAAAAA==.',
Am='Amalthea:BAAALgADCgcJBwAAAA==.Amarah:BAACLgAFFH8NAAIFAAMJmR/CEAAWAQAFAAMJmR/CEAAWAQAuAAQKf0IAAgUACQk2HokJAKsCAAUACQk2HokJAKsCAAAA.',
An='Andron:BAAALgADCgIJAgAAAA==.Andy:BAAALgADCgcJBwAAAA==.Angryjames:BAAALgADCgYJCgAAAA==.Animehero:BAAALgAECgIJAwABLgAECgkJFQAGAJIcAA==.',
Ap='Applemonster:BAAALgAECggJDwAAAA==.',
Ar='Arboghast:BAAALgAECgUJCAAAAA==.Argadin:BAAALgAFFAMJAwAAAA==.Argdru:BAAALgAECgYJDQABLgAFFAMJAwABAAAAAA==.Arglock:BAAALgADCgIJAgABLgAFFAMJAwABAAAAAA==.Argrekd:BAAALgADCgMJAwABLgAFFAMJAwABAAAAAA==.Aridol:BAAALgADCgUJBAAAAA==.Arigön:BAAALgADCgMJAwAAAA==.Arima:BAAALgAECgIJAwAAAA==.Arknox:BAABLgAECn8cAAMHAAkJIA15JwCoAQAHAAkJIA15JwCoAQADAAEJEAuBbgEtAAAAAA==.Arthaslk:BAAALgAECgcJDwABLgAECgYJFgACAAQaAA==.',
As='Aserus:BAAALgAECgcJCwABLgAFFAYJHgAIAAIeAA==.Ashallel:BAAALgAECgQJBAABLgAFFAYJHgAIAAIeAA==.Ashx:BAAALgADCgIJBAABLgAECgkJIAAJAKoXAA==.Astralock:BAAALgAECgEJAQAAAA==.',
At='Ate:BAABLgAECn8dAAIKAAgJYhc5EADWAQAKAAgJYhc5EADWAQABLgAECgcJLQALALcbAA==.Atlette:BAACLgAFFH8NAAIFAAQJOxwqDgA0AQAFAAQJOxwqDgA0AQAuAAQKfyoAAgUACQluH2MCAEUDAAUACQluH2MCAEUDAAAA.Atrocitusz:BAAALgAECgIJAgAAAA==.Atroxx:BAACLgAFFH8MAAIEAAQJ0w3BHgAjAQAEAAQJ0w3BHgAjAQAuAAQKf0kAAgQACAncI8wQABcDAAQACAncI8wQABcDAAEuAAUUBgklAAwAKxcA.Attman:BAACLgAFFH8MAAINAAUJ/hUfFAB7AQANAAUJ/hUfFAB7AQAuAAQKfx4AAw0ACAkSHIwUAHoCAA0ACAkSHIwUAHoCAA4AAwlFAzyEADoAAAAA.',
Au='Auradawn:BAAALgAECgQJEgAAAA==.',
Ay='Ayaya:BAAALgAECgQJBQABLgAECgYJEQABAAAAAA==.',
Ba='Baetrayer:BAAALgAECgcJCAAAAA==.Bailz:BAAALgADCgMJAwAAAA==.Balimund:BAAALgAECgEJAQAAAA==.Ballerstatus:BAAALgAECgMJAwAAAA==.Ballsofaith:BAAALgADCgkJFAABLgAECgcJLQALALcbAA==.Ballsofire:BAABLgAECn8tAAILAAcJtxukEAC2AQALAAcJtxukEAC2AQAAAA==.Basherz:BAAALgAECgQJBgAAAA==.',
Be='Bearmane:BAAALgAECgYJEAABLgAECggJKgAGAHIlAA==.Beedoc:BAAALgADCgEJAQAAAA==.Behindithu:BAABLgAECn8lAAMPAAgJyhKnBwC0AQAPAAgJyhKnBwC0AQAQAAYJ5wUqOgCqAAAAAA==.Belithel:BAABLgAECn8gAAIJAAkJqhcFdgDmAQAJAAkJqhcFdgDmAQAAAA==.Bencreepin:BAABLgAECn8VAAIKAAYJZxAlJgDzAAAKAAYJZxAlJgDzAAAAAA==.Beniz:BAABLgAECn8YAAMRAAgJmAgCfQAqAQARAAgJAAgCfQAqAQASAAIJBQnHWgBeAAAAAA==.Bernoulli:BAABLgAECn8dAAITAAkJFhl3GAAWAgATAAkJFhl3GAAWAgAAAA==.',
Bi='Bigblunts:BAAALgADCgEJAgAAAA==.Bigcrunch:BAAALgAECggJCQAAAA==.Bignative:BAAALgAECgYJCAAAAA==.Bironic:BAAALgAECgYJDAABLgAECgYJHAAQAGAQAA==.',
Bl='Bloodboo:BAAALgAECgQJBAAAAA==.Bloodyhpally:BAAALgAFFAIJAgABLgAFFAgJJgATAKEfAA==.Bloodymyst:BAABLgAFFH8mAAITAAgJoR8tAQD/AgATAAgJoR8tAQD/AgAAAA==.Blumpy:BAAALgADCggJCAAAAA==.',
Bo='Boethius:BAAALgAECgMJBAABLgAECgcJDwABAAAAAA==.Boopsnoopems:BAABLgAECn8ZAAIUAAYJqhOdGwANAQAUAAYJqhOdGwANAQAAAA==.Borderline:BAAALgADCgYJBgABLgAFFAUJEQAVAB8LAA==.Bounty:BAAALgADCgMJAwAAAA==.',
Br='Briannajade:BAABLgAECn8gAAIJAAgJygguhABSAQAJAAgJygguhABSAQAAAA==.Brisha:BAACLgAFFH8kAAIHAAYJGx+NCADnAQAHAAYJGx+NCADnAQAuAAQKfzMAAwcACQlIJHQAALUDAAcACQlIJHQAALUDABQAAQk8EtVBADQAAAAA.Brodan:BAAALgAECgQJBAAAAA==.Brokenhealz:BAAALgAECgcJDQAAAA==.',
Bs='Bs:BAAALgAECgYJBgABLgAFFAQJBwAEAH8PAA==.',
Bu='Bubble:BAAALgADCgEJAgAAAA==.Bubblehash:BAAALgADCgEJAQAAAA==.Bubbletarded:BAAALgAECgUJBgAAAA==.Bustah:BAABLgAECn8eAAMWAAgJex24DgDFAgAWAAgJex24DgDFAgAXAAYJag3uTwAPAQABLgAFFAQJBwAEAH8PAA==.',
Ca='Cacaco:BAAALgADCgIJAgAAAA==.Cactuscooler:BAAALgADCgcJBwAAAA==.Caffrey:BAABLgAECn8ZAAIIAAkJ1SKyAQCJAwAIAAkJ1SKyAQCJAwAAAA==.Cammi:BAABLgAECn8WAAIHAAYJKRqpJgCuAQAHAAYJKRqpJgCuAQAAAA==.Cammywammy:BAAALgAECgcJEgAAAA==.Candy:BAAALgAECgEJAQAAAA==.Carlyyrae:BAABLgAECn8aAAMNAAkJsxYYIQAbAgANAAkJsxYYIQAbAgAOAAEJxwKymgAgAAAAAA==.Casare:BAABLgAECn8cAAIXAAYJSgmoHACmAAAXAAYJSgmoHACmAAAAAA==.Catjam:BAABLgAFFH8GAAIDAAQJEyDtFgB3AQADAAQJEyDtFgB3AQABLgAFFAgJJwAYAM0iAA==.',
Ce='Celarc:BAAALgAECgYJDwAAAA==.Celithe:BAABLgAECn8cAAIZAAgJuw8yVABmAQAZAAgJuw8yVABmAQABLgAECgkJNAAJANsVAA==.Celyda:BAAALgADCgcJBwAAAA==.',
Ch='Chape:BAACLgAFFH8LAAITAAUJzxDEFwBAAQATAAUJzxDEFwBAAQAuAAQKfyIAAhMACQmTH2QHAPcCABMACQmTH2QHAPcCAAAA.Chapito:BAAALgAECgcJCAAAAA==.Chipmonked:BAABLgAECn81AAQGAAkJGQsoJABrAQAGAAkJfAooJABrAQAaAAYJOwqIPwDVAAATAAUJIwPLUACQAAAAAA==.Chlop:BAABLgAECn8ZAAIEAAgJcBx0HADUAgAEAAgJcBx0HADUAgAAAA==.Chunkers:BAAALgAECgQJBAAAAA==.Chuubar:BAAALgADCgYJCwAAAA==.',
Ci='Cinderzin:BAABLgAECn8zAAMbAAkJmAj4CAB4AQAbAAkJmAj4CAB4AQAYAAEJvwAhjQAHAAAAAA==.',
Cl='Clawhalla:BAAALgAECgcJEQAAAA==.',
Cn='Cnorthover:BAAALgAECgQJBAAAAA==.',
Co='Cobrallig:BAAALgAECggJDAAAAA==.Colexn:BAAALgAECgQJBAAAAA==.Comfyboi:BAAALgAECgcJDQAAAA==.Cong:BAABLgAFFH8FAAIcAAMJRRRCGADYAAAcAAMJRRRCGADYAAABLgAFFAYJFQAZAFAeAA==.Congdh:BAACLgAFFH8VAAIZAAYJUB5OCAChAQAZAAYJUB5OCAChAQAuAAQKfyUAAhkACQkPJKcHAP8CABkACQkPJKcHAP8CAAAA.Conmann:BAAALgAECgYJEgAAAA==.Corg:BAAALgADCgUJBQAAAA==.Cornchipz:BAAALgAECgMJAwAAAA==.Cowmage:BAAALgAECgEJAQAAAA==.',
Cr='Crit:BAAALgADCgcJCAAAAA==.Crossy:BAAALgAECgQJBQAAAA==.Crusade:BAAALgAECgYJDgAAAA==.Cryogenic:BAAALgAECgYJEgAAAA==.Cryptex:BAAALgADCgEJAQAAAA==.',
Cy='Cyrus:BAAALgAECgcJDQAAAA==.',
Cz='Czznkj:BAAALgADCgkJDgAAAA==.',
['Cá']='Cálívént:BAAALgAECggJEwAAAA==.',
Da='Daak:BAAALgAECgEJAQABLgAECgcJKAAGAL0NAA==.Daangalangg:BAAALgAECgIJAwAAAA==.Dabberoni:BAAALgAECgcJAQAAAA==.Dabthorne:BAAALgADCgEJAgAAAA==.Daegra:BAAALgAFFAEJAQAAAA==.Daelin:BAAALgAECgEJAQAAAA==.Dankkush:BAACLgAFFH8IAAIEAAQJaBGxUQApAQAEAAQJaBGxUQApAQAuAAQKfxgAAgQACQmxHg83AAACAAQACQmxHg83AAACAAAA.Darkacedia:BAABLgAECn8jAAMRAAgJLh9bHQCmAgARAAgJLh9bHQCmAgASAAMJyQ9aQwCoAAAAAA==.Darkrubie:BAAALgADCgMJAwAAAA==.Datbish:BAAALgAECgUJCAAAAA==.Dawgis:BAAALgAECgEJAQAAAA==.',
Db='Dbznz:BAAALgADCgYJBwAAAA==.',
De='Deadcell:BAABLgAECn8bAAIEAAcJPSEvLAAsAgAEAAcJPSEvLAAsAgAAAA==.Deadcells:BAABLgAECn8UAAIcAAcJ+h1qDAD5AQAcAAcJ+h1qDAD5AQABLgAECgcJGwAEAD0hAA==.Deadharvest:BAAALgAECgYJBwAAAA==.Deadlift:BAAALgAECgQJCwAAAA==.Dealosed:BAACLgAFFH8MAAMPAAQJ2RCUBQAAAQAPAAMJXRaUBQAAAQAQAAQJ+wkYDwD/AAAuAAQKfzQABA8ACQkvI9kAABADAA8ACQm7ItkAABADABAABwnOIMoRAJECAB0ABgllHpkGALwBAAAA.Decrepit:BAABLgAECn8pAAIEAAkJDBnhHwBnAgAEAAkJDBnhHwBnAgAAAA==.Defect:BAAALgAECgQJBAAAAA==.Defy:BAAALgAECgMJAwAAAA==.Demonclawz:BAABLgAECn8VAAIRAAgJGgw7YABqAQARAAgJGgw7YABqAQAAAA==.Demonscar:BAAALgAECgUJCwAAAA==.Dex:BAAALgAECgEJAQAAAA==.',
Dh='Dhaeverdh:BAAALgADCgIJAgAAAA==.',
Di='Diceydk:BAAALgADCgMJAQABLgAFFAMJCQAeAJsRAQ==.Diddious:BAAALgADCgMJAgAAAA==.Diremane:BAAALgAECgIJAgAAAA==.Disastacast:BAAALgAECgMJAwABLgAECgYJGgAOAGckAA==.Disastasmite:BAAALgADCgEJAQABLgAECgYJGgAOAGckAA==.Dive:BAACLgAFFH8JAAIJAAQJTSCAKACBAQAJAAQJTSCAKACBAQAuAAQKfyMAAwkACQklIuwmANcCAAkACAmOIewmANcCAB8ABQnyHHwLAB8BAAAA.',
Dk='Dkeruu:BAAALgAECgUJCAAAAA==.',
Do='Doinks:BAABLgAECn8VAAIGAAkJkhwxDgCxAgAGAAkJkhwxDgCxAgAAAA==.Dondozo:BAAALgAECgUJCwAAAA==.Doogru:BAABLgAECn8uAAICAAkJDxenEwAwAgACAAkJDxenEwAwAgAAAA==.Doufu:BAAALgAECgQJBAABLgAECgYJDAABAAAAAA==.',
Dr='Dracomaibois:BAAALgAECgYJCgAAAA==.Dragoneggs:BAACLgAFFH8PAAMYAAMJcxlJLQDhAAAYAAMJcxlJLQDhAAAgAAMJqQnxGgC2AAAuAAQKfycAAxgACQnaHuwIAOkCABgACQnaHuwIAOkCACAABwkZE84XAC8BAAAA.Dragonforce:BAAALgAECgYJDAABLgAECgkJEQABAAAAAA==.Draxan:BAAALgADCgcJCAAAAA==.Draxx:BAAALgAECgcJDgAAAA==.Dreammachine:BAABLgAECn8vAAIhAAkJ3CP6AwAGAwAhAAkJ3CP6AwAGAwAAAA==.Driipp:BAAALgAFFAMJBAAAAA==.Drizs:BAAALgADCgEJAQAAAA==.Drjoel:BAAALgADCgYJCAAAAA==.Drunkenutz:BAABLgAECn8XAAMTAAYJYxWWNQAZAQATAAUJxxKWNQAZAQAGAAYJgw4IPADsAAAAAA==.',
Du='Duane:BAAALgADCgEJAQABLgAFFAUJEQAVAB8LAA==.',
Dy='Dyab:BAAALgAECgEJAQAAAA==.',
['Dä']='Dälf:BAABLgAECn8cAAMiAAcJnCFlCwAKAgAiAAYJbiNlCwAKAgAIAAYJLRDfWABIAQABLgAFFAgJHAAYAL0YAA==.',
Ea='Eatinoreos:BAAALgAECgQJAwAAAA==.',
Ec='Echidona:BAABLgAECn8bAAIQAAgJERn8EwB2AgAQAAgJERn8EwB2AgAAAA==.',
Ed='Edirii:BAAALgADCgEJAQAAAA==.',
Ee='Eelsky:BAAALgAECgcJEgAAAA==.',
Ef='Efvoidhunter:BAAALgAECgUJBQAAAA==.',
Ek='Eksi:BAEALgAECgQJBAABLgAFFAUJFAARAIMjAA==.',
El='Elenix:BAABLgAECn8aAAMOAAkJyRy0CAAGAwAOAAkJyRy0CAAGAwANAAMJhA3zgACQAAABLgAFFAMJBgAHABghAA==.Elinras:BAACLgAFFH8LAAIDAAMJygZPVgDSAAADAAMJygZPVgDSAAAuAAQKfx4AAgMACAkeGcw5APsBAAMACAkeGcw5APsBAAAA.Elliott:BAAALgADCgMJBQABLgADCggJDQABAAAAAA==.Elrizon:BAAALgAECgIJAQAAAA==.Elvar:BAAALgAECggJDgABLgAECgQJBQABAAAAAA==.Elwynbria:BAAALgADCgcJBwAAAA==.Elynith:BAAALgAECgIJBAAAAA==.Elynni:BAABLgAECn8dAAIFAAcJ2RUIIADhAQAFAAcJ2RUIIADhAQAAAA==.',
Em='Emmylou:BAAALgAECgEJAwAAAA==.Emotett:BAAALgADCgQJBAAAAA==.Emz:BAACLgAFFH8IAAIdAAMJVR/XBQAAAQAdAAMJVR/XBQAAAQAuAAQKfysAAh0ACAlqIuUAAAwDAB0ACAlqIuUAAAwDAAAA.',
En='Endboss:BAAALgAECgUJBQAAAA==.Endorsi:BAACLgAFFH8LAAIPAAQJxBKmAwBPAQAPAAQJxBKmAwBPAQAuAAQKfxcAAg8ABwmAG6oHALQBAA8ABwmAG6oHALQBAAAA.Enfuega:BAAALgAECgQJDQAAAA==.Eniar:BAACLgAFFH8MAAIHAAUJUAaBGQAjAQAHAAUJUAaBGQAjAQAuAAQKfxkAAwcACAnHFLguAMgBAAcACAnHFLguAMgBAAMABAl0CTDvALIAAAAA.',
Er='Eroninja:BAAALgAECgQJCAABLgAECgkJIAAJAKoXAA==.',
Eu='Eurong:BAACLgAFFH8SAAIjAAUJGhwAEwBIAQAjAAUJGhwAEwBIAQAuAAQKfxsAAiMACAl0H0waADICACMACAl0H0waADICAAAA.',
Ev='Evangelune:BAAALgAECgYJDAAAAA==.',
Ew='Ewright:BAAALgAECgEJAQABLgAECgYJEgABAAAAAA==.',
Ez='Ezynuff:BAABLgAECn8aAAMNAAgJjRPfOQCWAQANAAcJghPfOQCWAQAOAAUJKQiUXgCXAAAAAA==.',
['Eï']='Eïr:BAAALgADCgcJCAAAAA==.',
Fa='Fakie:BAAALgAECgQJBAABLgAECgYJFAARACIfAA==.Fapple:BAAALgAECgcJEwABLgAECggJLQAgAFokAA==.Fatesprocket:BAAALgAECgMJBQAAAA==.Faïry:BAACLgAFFH8RAAMWAAUJ9xgDLQAoAQAWAAUJvBIDLQAoAQAkAAMJTwtBGwDCAAAuAAQKfzEAAxYACQkxHcoRAKoCABYACAmpH8oRAKoCACQABgkUCjYjALYAAAAA.',
Fe='Feardih:BAAALgADCgIJAgAAAA==.Felfrostette:BAAALgAECgEJAQAAAA==.Felheart:BAAALgAECgYJDgAAAA==.Feltnutz:BAAALgADCgQJBQABLgAECgYJFwATAGMVAA==.Felwyrm:BAAALgAECgYJCQABLgAFFAUJEQAVAB8LAA==.Femboi:BAAALgADCgUJBQAAAA==.Fengshui:BAAALgAFFAEJAQAAAA==.Feralle:BAAALgADCgQJBAAAAA==.',
Fl='Flacidmon:BAAALgAECgMJAwAAAA==.Flutterina:BAAALgAECgIJAgAAAA==.Flyjin:BAABLgAECn8dAAMgAAgJEQ5pJABVAQAgAAcJLgxpJABVAQAYAAgJJg5jNAA3AQAAAA==.Flylo:BAAALgADCgMJAwAAAA==.',
Fo='Folandras:BAAALgADCgcJDAABLgAECgcJLQALALcbAA==.Forrestpump:BAAALgADCgMJAwAAAA==.',
Fr='Fries:BAECLgAFFH8HAAIRAAQJpg+QSwAKAQARAAQJpg+QSwAKAQAuAAQKfyQAAxEACAkDJIAPALkCABEACAkDJIAPALkCABIAAQmHGhtgAE8AAAAA.Frozenpyre:BAAALgAECgYJEQAAAA==.',
Fu='Funch:BAACLgAFFH8MAAISAAMJFg+OBwDgAAASAAMJFg+OBwDgAAAuAAQKfzQAAhIACQk8G1kCAHMCABIACQk8G1kCAHMCAAAA.',
['Fè']='Fènrir:BAAALgAECgYJBwABLgAECgYJEgABAAAAAA==.',
Ga='Gabbathegoo:BAABLgAFFH8FAAMRAAQJ2AuIXwDZAAARAAMJwg6IXwDZAAASAAEJHQPgIABAAAAAAA==.Gainzbrew:BAAALgAECgEJAgAAAA==.Gainzz:BAAALgAECgQJBgAAAA==.Galesdeyn:BAABLgAECn8VAAIZAAcJQhfhSgCDAQAZAAcJQhfhSgCDAQAAAA==.Garl:BAAALgAECgUJBQABLgAECgcJFAAJAD4dAA==.Garonnaa:BAABLgAFFH8LAAIKAAQJoAgmGgDZAAAKAAQJoAgmGgDZAAAAAA==.',
Gh='Ghari:BAABLgAECn8oAAIEAAgJpRPVagBrAQAEAAgJpRPVagBrAQAAAA==.',
Gi='Gilrog:BAABLgAECn8XAAIEAAUJLxDtwADRAAAEAAUJLxDtwADRAAAAAA==.Gingerlock:BAAALgAECgUJBgAAAA==.',
Gl='Gladiusmax:BAAALgADCgQJBAAAAA==.Gloryseeker:BAAALgAECgEJAQAAAA==.',
Gn='Gnoblin:BAAALgAECgQJCAAAAA==.Gnz:BAAALgAFFAIJAgAAAA==.Gnzz:BAAALgAECgcJDAAAAA==.',
Go='Gonz:BAAALgADCgcJBwAAAA==.',
Gr='Gravys:BAAALgAECgcJAwAAAA==.Greka:BAABLgAECn8hAAIOAAgJPAwRNAA7AQAOAAgJPAwRNAA7AQAAAA==.Greylooms:BAACLgAFFH8HAAMcAAMJsR/4EwD7AAAcAAMJbR74EwD7AAACAAEJHRhzPABOAAAuAAQKfzIAAxwACQkwIRQCAA4DABwACQkwIRQCAA4DAAIABgmEHekyAOABAAAA.Gruuith:BAAALgADCgEJAQAAAA==.',
Gw='Gwath:BAAALgAECgEJAQAAAA==.',
Gy='Gynaris:BAAALgAECgMJBQAAAA==.',
['Gâ']='Gâinzz:BAAALgADCgQJBAAAAA==.',
Ha='Hakun:BAAALgAECgMJAwAAAA==.Happyfriend:BAACLgAFFH8RAAMVAAUJHwtOFgBkAQAVAAUJHwtOFgBkAQAhAAEJZABIMQA2AAAuAAQKfykABBUACAnTFeocALgBABUACAnTFeocALgBACEABwmiEX8kALQBAAUAAQkPCkFlACkAAAAA.Haruko:BAAALgADCgQJBAAAAA==.',
He='Heemski:BAAALgAECgMJAwAAAA==.Hellbourne:BAAALgADCggJDQAAAA==.Hellbrick:BAAALgADCgMJAwAAAA==.Hermitpurple:BAAALgADCgcJEwAAAA==.Heàl:BAAALgAECgYJEgAAAA==.',
Hi='Hidejames:BAAALgAECggJEwAAAA==.Hidolo:BAAALgADCgUJBQAAAA==.Hims:BAABLgAECn8WAAMZAAYJ4iAYNwAaAgAZAAYJ4iAYNwAaAgAeAAEJtRxSKABFAAABLgAFFAgJJwAYAM0iAA==.',
Ho='Hoguy:BAAALgAECgYJEAAAAA==.Holofox:BAACLgAFFH8fAAIIAAYJzxzNBgA2AgAIAAYJzxzNBgA2AgAuAAQKf0QAAwgACQlFJo4AAN0DAAgACQlFJo4AAN0DACIABQkXDq0gAMcAAAAA.Holycrow:BAAALgAECgMJAwAAAA==.Holytotem:BAAALgADCgEJAQAAAA==.Horman:BAABLgAECn8WAAIaAAYJmwtNRgC7AAAaAAYJmwtNRgC7AAAAAA==.',
Hu='Hunterishard:BAAALgAECggJEAABLgAECgkJEQABAAAAAA==.',
Hy='Hylda:BAAALgAECgMJBgAAAA==.',
['Hï']='Hïru:BAAALgAECgYJCAAAAA==.',
['Hô']='Hôlÿ:BAAALgAECgQJCQABLgAECgYJFwAZAKQYAA==.',
Ic='Iclapu:BAAALgAECgEJAgABLgAECgkJMQAGADAdAA==.',
Ig='Ignia:BAAALgADCgYJBgABLgAECgcJKAAGAL0NAA==.Igosduikanna:BAAALgADCgQJBQAAAA==.',
Ik='Ikerous:BAABLgAECn8bAAMeAAgJ3RkwBwAWAgAeAAgJ3RkwBwAWAgAlAAMJ1AmTVgCNAAAAAA==.',
Il='Ilililililli:BAABLgAECn8cAAMTAAgJ0Rc1JgCBAQATAAgJ0Rc1JgCBAQAaAAIJdgjZawBRAAAAAA==.',
Im='Imadwagon:BAAALgADCgkJCAAAAA==.Imapandairl:BAABLgAECn8VAAIOAAcJrR6CEgCOAgAOAAcJrR6CEgCOAgAAAA==.Imhammered:BAABLgAECn8dAAIHAAgJWQ/3KgCSAQAHAAgJWQ/3KgCSAQAAAA==.Impullse:BAAALgAFFAIJAwAAAA==.',
Ir='Ironpally:BAAALgAECgYJBwAAAA==.Irsty:BAAALgAECgEJAQABLgAFFAMJBgAYAFESAA==.',
It='Ithilwen:BAABLgAECn8mAAIVAAgJ6x4fDQBnAgAVAAgJ6x4fDQBnAgAAAA==.Itiswhatitiz:BAABLgAECn8XAAIWAAYJpBm2UACCAQAWAAYJpBm2UACCAQAAAA==.Itsybityshiv:BAACLgAFFH8HAAIQAAMJLxm3GwACAQAQAAMJLxm3GwACAQAuAAQKfzYAAxAACQmbHaIHAIwCABAACQmbHaIHAIwCAA8AAQmgGPQfADMAAAAA.',
Iw='Iwillpull:BAAALgADCgcJDgAAAA==.',
Iz='Izzlirkkgazp:BAAALgAECgcJDgAAAA==.',
Ja='Jackiefox:BAAALgAECgIJBAAAAA==.Jahq:BAABLgAECn8VAAIZAAYJAyF8NAAnAgAZAAYJAyF8NAAnAgAAAA==.Jambs:BAAALgADCgEJAQAAAA==.Jaysontatum:BAAALgADCgEJAQAAAA==.',
Je='Jeabuss:BAAALgADCgcJBwAAAA==.',
Jh='Jhani:BAABLgAECn8YAAIJAAgJSARUpAAZAQAJAAgJSARUpAAZAQAAAA==.',
Ji='Jixn:BAAALgAECgMJBQAAAA==.',
Jo='Joethemage:BAABLgAECn8wAAIJAAkJASGMEgDSAgAJAAkJASGMEgDSAgAAAA==.Joobles:BAAALgAECgEJAQABLgAECgkJMQAGADAdAA==.Jormojo:BAAALgAECgQJBgAAAA==.Jotwnky:BAABLgAECn8eAAQmAAcJAyC3BQAMAgAmAAUJSSO3BQAMAgASAAQJsxo7IwA+AQARAAMJGB9WuADoAAAAAA==.Jotwnkyy:BAACLgAFFH8JAAIQAAQJAhPgEgBJAQAQAAQJAhPgEgBJAQAuAAQKfysAAhAABwnvG6kYAK0BABAABwnvG6kYAK0BAAEuAAQKBwkeACYAAyAA.',
Ju='Jungol:BAAALgAECgIJAgAAAA==.',
Ka='Kaela:BAAALgAECgEJAQAAAA==.Kaikova:BAAALgADCgcJCgAAAA==.Kaliban:BAAALgAECgEJAQAAAA==.Kaltank:BAAALgAECggJAwAAAA==.Kamin:BAABLgAECn8jAAILAAgJwiHjAwARAwALAAgJwiHjAwARAwAAAA==.Karoka:BAAALgADCgEJAQAAAA==.Kasitos:BAABLgAECn8UAAMRAAgJhxkDYwBiAQARAAgJhxkDYwBiAQASAAEJnxEdbQA6AAAAAA==.Katamaran:BAAALgAFFAEJAQABLgAFFAQJEgAhAFYQAA==.Kaykaypally:BAABLgAECn8fAAIDAAkJbhIKQgDhAQADAAkJbhIKQgDhAQAAAA==.',
Ke='Keis:BAEALgAECgYJBgABLgAFFAUJFAARAIMjAA==.Keledron:BAAALgADCgcJCgAAAA==.Kellan:BAABLgAECn8qAAIDAAcJnBg9cABuAQADAAcJnBg9cABuAQAAAA==.Kelos:BAAALgAECgYJCAABLgAFFAEJAgABAAAAAA==.Keylethel:BAAALgADCgEJAQAAAA==.',
Ki='Kideki:BAABLgAECn8nAAIHAAkJSyJtBwDxAgAHAAkJSyJtBwDxAgAAAA==.Kidori:BAAALgAECgEJAQABLgAECgkJJwAHAEsiAA==.Kilgharra:BAAALgADCggJEQAAAA==.Killakevv:BAAALgADCgcJBwAAAA==.Kinji:BAAALgADCgYJCAABLgAECgkJIAAJAKoXAA==.Kirisute:BAAALgAECgEJAQAAAA==.',
Ko='Kolsch:BAAALgADCgQJBAAAAA==.Koriandar:BAABLgAECn8jAAIJAAgJsQdPhABSAQAJAAgJsQdPhABSAQAAAA==.Koyama:BAAALgADCgcJBwAAAA==.',
Kr='Kristysavage:BAABLgAECn81AAIkAAgJdiD/BwCEAgAkAAgJdiD/BwCEAgAAAA==.Krul:BAAALgADCgkJCgAAAA==.Kruya:BAAALgAECgMJBAABLgAECgYJHAAQAGAQAA==.',
Ku='Kulaesca:BAAALgAECgIJAgAAAA==.',
Ky='Kynar:BAACLgAFFH8ZAAMEAAcJKRxQCgAWAgAEAAYJKRxQCgAWAgAKAAEJAABrEQBnAAAuAAQKfxcAAgQACAkuH60/ADoCAAQACAkuH60/ADoCAAAA.Kyperion:BAAALgAECgYJDQAAAA==.Kyua:BAABLgAECn8UAAIlAAYJBwgLMQDFAAAlAAYJBwgLMQDFAAAAAA==.',
La='Lambshot:BAABLgAECn8bAAMWAAcJ4SAHOADTAQAWAAcJ4SAHOADTAQAXAAEJ/AahjwArAAAAAA==.Lambsy:BAACLgAFFH8oAAQCAAgJ2BbOAgD1AQACAAcJYRjOAgD1AQAcAAEJYAXGLABFAAALAAEJpAj2IgA7AAAuAAQKfx4AAwIACAmrIBARAMgCAAIACAl4HhARAMgCABwAAQnuI0A5AEsAAAAA.Landwhalexxl:BAABLgAECn8XAAIJAAcJ9BGOpACPAQAJAAcJ9BGOpACPAQAAAA==.Laneera:BAAALgAECgQJDgAAAA==.',
Le='Ledronys:BAAALgADCgEJAQAAAA==.Ledsole:BAAALgADCgEJAQAAAA==.Lerat:BAABLgAECn8tAAIbAAgJpyJnAgB8AgAbAAgJpyJnAgB8AgAAAA==.',
Li='Lichkali:BAAALgADCgMJAwAAAA==.Lightofhope:BAAALgAECggJEgAAAA==.Lihandra:BAAALgAECgQJBgAAAA==.Lillipup:BAAALgAECgQJBAAAAA==.Lillyy:BAAALgAECgIJAgABLgAFFAMJBgAJANwSAA==.Lilyy:BAACLgAFFH8GAAIJAAMJ3BLoYgDwAAAJAAMJ3BLoYgDwAAAuAAQKfxcAAgkACQmqGnZzAHUBAAkACQmqGnZzAHUBAAAA.Liria:BAAALgAECgYJDQAAAA==.Lisanalgaib:BAABLgAECn8ZAAIDAAgJlRfzRgDSAQADAAgJlRfzRgDSAQAAAA==.Liulei:BAAALgAECgQJAwAAAA==.Lizzimcguire:BAAALgAECgQJBAAAAA==.',
Lo='Loharfal:BAAALgADCgcJCAAAAA==.Lokî:BAAALgAECgQJBAAAAA==.Loraen:BAABLgAECn8XAAIJAAYJiQvrrAALAQAJAAYJiQvrrAALAQAAAA==.Lorelei:BAAALgAECgEJAQABLgAECgkJJAAcABkbAA==.Lostep:BAAALgAECgEJAQABLgAFFAcJGwANAA4UAA==.Lowkeyjz:BAAALgADCgIJAgAAAA==.',
Lu='Luasa:BAAALgADCgIJAgAAAA==.Lukadoncic:BAAALgAECgYJDQABLgADCgEJAQABAAAAAA==.Lunarmon:BAAALgAECgUJDgAAAA==.Lunchable:BAABLgAECn8eAAIOAAgJnhmJFgBlAgAOAAgJnhmJFgBlAgAAAA==.Luxmalleo:BAAALgADCgkJDwABLgAECgYJHAAQAGAQAA==.',
Ly='Lykho:BAAALgAECgEJAQAAAA==.',
['Lé']='Léblanc:BAABLgAECn8oAAIJAAkJ/x2NNQAlAgAJAAkJ/x2NNQAlAgAAAA==.',
Ma='Madam:BAAALgADCgMJBwAAAA==.Madday:BAAALgADCgcJDAAAAA==.Maelorus:BAAALgADCgkJEQAAAA==.Magicaltoast:BAAALgAECgYJCgAAAA==.Mahli:BAAALgAECgEJAQAAAA==.Makah:BAAALgAECgMJAwAAAA==.Makaroni:BAAALgADCgcJBwAAAA==.Makizenin:BAAALgADCgYJCAAAAA==.Malenia:BAAALgADCgUJBwAAAA==.Malthezar:BAAALgADCgEJAQAAAA==.Manticus:BAAALgADCgYJEAAAAA==.Mari:BAAALgAECgMJBQABLgAFFAMJDQAFAJkfAA==.Matroxx:BAABLgAECn8VAAMaAAcJSRr2KABEAQAaAAQJex72KABEAQATAAcJfBA7MwAnAQABLgAFFAYJJQAMACsXAA==.',
Me='Meat:BAAALgAECgUJBQAAAA==.Meatballz:BAAALgADCgEJAQAAAA==.Meatbeef:BAAALgADCgEJAQAAAA==.Meenoi:BAACLgAFFH8HAAIEAAQJfw+jVgAhAQAEAAQJfw+jVgAhAQAuAAQKfysAAgQACAnQIWYmAKICAAQACAnQIWYmAKICAAAA.Megamaid:BAAALgAECgEJAQAAAA==.Melysia:BAACLgAFFH8eAAIIAAYJAh4MCAAeAgAIAAYJAh4MCAAeAgAuAAQKfzoAAwgACQl0IP8MANQCAAgACQl0IP8MANQCACIAAgmmCes0AE4AAAAA.Metalgear:BAAALgADCgYJDAAAAA==.',
Mi='Miadas:BAAALgAECgIJBAABLgAECgkJKwAiAPobAA==.Midgeyfam:BAAALgAECgIJAgAAAA==.Midgeyzen:BAAALgAECgQJBAAAAA==.Mika:BAAALgAFFAEJAQABLgAFFAMJDQAFAJkfAA==.Mindi:BAAALgAECgMJAwAAAA==.Mizakina:BAAALgADCgYJCwAAAA==.Mizby:BAAALgADCgIJAwABLgADCgMJAwABAAAAAA==.Mizry:BAAALgADCgMJAwAAAA==.',
Mo='Moardotsnow:BAABLgAECn8oAAMRAAkJ4SRKMgD3AQARAAUJ9iRKMgD3AQASAAQJvSRzDgArAQAAAA==.Moby:BAAALgAECgcJEgAAAA==.Moistmender:BAAALgAECgcJDwAAAA==.Moosaki:BAAALgAECgkJCQABLgAECgkJMgAQAIwjAA==.Mortui:BAAALgADCgQJBgABLgAFFAYJJQAMACsXAA==.Mous:BAAALgADCgMJAwAAAA==.',
Mu='Muffasah:BAAALgAECgEJAQAAAA==.Munchkinn:BAAALgADCgYJBgAAAA==.Murbella:BAAALgADCgEJAQABLgAECgYJDgABAAAAAA==.Murridan:BAABLgAECn8nAAIZAAkJoiKUCQA7AwAZAAkJoiKUCQA7AwAAAA==.',
My='Mykaela:BAAALgAECgcJDgAAAA==.Myraela:BAAALgAECgQJBAABLgAECgkJHQAKAEshAA==.',
['Më']='Mëow:BAABLgAECn8YAAInAAcJOgUPNgCFAAAnAAcJOgUPNgCFAAAAAA==.',
Na='Narrath:BAAALgAECgMJBQAAAA==.Nayalaah:BAAALgAECgcJDgAAAA==.',
Ne='Nellybearwl:BAAALgADCgYJBgAAAA==.Nerfherder:BAAALgAECgQJBQAAAA==.Nexes:BAAALgAECgMJBAAAAA==.',
Ni='Nicotinee:BAAALgAECgMJAwAAAA==.Nightbané:BAAALgAECgIJBQAAAA==.Nirina:BAABLgAECn8ZAAIWAAYJ0wdJkgDnAAAWAAYJ0wdJkgDnAAAAAA==.Nixie:BAAALgAECgYJBgAAAA==.',
No='Nojaw:BAAALgADCgcJBwAAAA==.Noraeri:BAAALgAECgYJBgABLgAECgkJIAAJAKoXAA==.Northsouth:BAAALgAECgEJAQAAAA==.Notdicey:BAAALgAFFAIJAgABLgAFFAMJCQAeAJsRAA==.Notstephen:BAAALgAECgUJCQAAAA==.Novo:BAAALgAECgYJCwAAAA==.',
Nu='Nukefury:BAABLgAECn8aAAIOAAYJZyR0GgBAAgAOAAYJZyR0GgBAAgAAAA==.',
Nw='Nwalliance:BAAALgADCgIJAgAAAA==.',
Od='Oddstriker:BAAALgADCgYJAwAAAA==.',
Ol='Oliveoil:BAAALgADCgEJAQAAAA==.',
Om='Omnidh:BAACLgAFFH8TAAIZAAUJNReuLAA1AQAZAAUJNReuLAA1AQAuAAQKfyQAAhkACQliIKwPAAEDABkACQliIKwPAAEDAAAA.Omnihead:BAAALgADCgYJBgAAAA==.',
On='Onepavo:BAAALgAECgEJAQAAAA==.Onlybakshots:BAAALgAECgYJBwAAAA==.',
Op='Oppose:BAAALgAECgYJDAAAAA==.',
Or='Orestes:BAAALgAFFAEJAQAAAA==.Orexion:BAAALgAECgYJCgAAAA==.Ormagöden:BAABLgAECn8oAAIoAAkJMhSMAwBPAgAoAAkJMhSMAwBPAgAAAA==.',
Pa='Palladean:BAABLgAECn8lAAIDAAcJNRPOcABsAQADAAcJNRPOcABsAQAAAA==.Pandemic:BAAALgAECgMJAwAAAA==.Parabow:BAAALgAECgMJAwAAAA==.Parador:BAAALgAECgIJAQABLgAECgMJAwABAAAAAA==.Pastasauce:BAABLgAECn8XAAIDAAcJFwubhwBrAQADAAcJFwubhwBrAQAAAA==.',
Pc='Pcpmlsd:BAAALgADCgkJDAAAAA==.',
Pe='Penelohpe:BAAALgAECgcJCgABLgAECggJIwALAMIhAA==.Penwork:BAAALgAECgcJCAAAAA==.Penz:BAAALgAECgYJCgAAAA==.Perrian:BAAALgADCgMJBAAAAA==.',
Ph='Phamine:BAAALgAECgMJAwAAAA==.Philex:BAEALgAECgYJBwABLgAFFAUJFAARAIMjAA==.Phoon:BAECLgAFFH8UAAIRAAUJgyOnHgCEAQARAAUJgyOnHgCEAQAuAAQKfyEABBEACAmoHkMdAKYCABEACAmoHkMdAKYCABIAAglGGVVJAJIAACYAAQkAAKAqAEoAAAAA.Phøenixbane:BAABLgAECn8ZAAIDAAcJQBxcQADmAQADAAcJQBxcQADmAQAAAA==.',
Pi='Piggy:BAAALgAECgEJAQAAAA==.Pita:BAAALgAECgcJCwAAAA==.Pitaya:BAAALgAECgcJEwAAAA==.',
Pl='Plaguefist:BAAALgAECgkJEQAAAA==.Plata:BAAALgAECgQJBQAAAA==.Plikxy:BAAALgADCgkJCQAAAA==.',
Po='Pocketmage:BAAALgAECgQJBQAAAA==.',
Pr='Premonitions:BAABLgAECn8fAAINAAgJVBRCMgC7AQANAAgJVBRCMgC7AQAAAA==.Premune:BAABLgAECn84AAQHAAkJ6x9cDQCuAgAHAAkJ6x9cDQCuAgAUAAgJ+RC0FABUAQADAAIJOgioGwFjAAAAAA==.Prion:BAACLgAFFH8KAAIZAAMJNwuWUADIAAAZAAMJNwuWUADIAAAuAAQKfxkAAhkACAklFLJEAJcBABkACAklFLJEAJcBAAAA.',
Ps='Psycs:BAAALgAECgYJDgAAAA==.',
Pu='Pulga:BAAALgADCgIJAgAAAA==.Pull:BAAALgADCgcJCQABLgAFFAQJCQAJAE0gAA==.Purplemage:BAAALgAECgkJCgABLgAECgkJEQABAAAAAA==.',
Pw='Pwincess:BAAALgADCgMJAwAAAA==.',
['Pú']='Púre:BAAALgAECgIJAgAAAA==.',
Qu='Quigly:BAAALgAECgYJCgAAAA==.Quìts:BAABLgAECn8mAAMRAAgJSB2FOgAiAgARAAgJrhuFOgAiAgASAAMJzRdrHwCLAAAAAA==.Quíts:BAAALgADCgEJAQABLgAECggJJgARAEgdAA==.',
Ra='Ragingtauren:BAAALgAECgMJBAAAAA==.Rainbowdots:BAAALgAECgcJDgAAAA==.Raine:BAACLgAFFH8bAAINAAcJDhQJBAA4AgANAAcJDhQJBAA4AgAuAAQKfx4AAw0ACAkhHysfACQCAA0ACAkhHysfACQCAA4ABAkKGWlVAPAAAAAA.Raistlain:BAAALgAECgYJCgAAAA==.Raistlin:BAABLgAECn8fAAMlAAkJwRaNEADrAQAlAAkJwRaNEADrAQAZAAEJywOo8AAiAAAAAA==.Ralfio:BAABLgAECn8tAAIgAAgJWiQeAgA+AwAgAAgJWiQeAgA+AwAAAA==.Ralfiosky:BAAALgAECggJDAABLgAECggJLQAgAFokAA==.Ramennoodlez:BAAALgAECgQJBAAAAA==.Rat:BAAALgAFFAIJAgAAAA==.Ratren:BAAALgADCgQJAwAAAA==.Ravalyn:BAAALgADCgkJCgAAAA==.Raynith:BAABLgAECn8rAAQiAAkJ+hukBwArAgAiAAcJIyGkBwArAgAjAAcJTxj1HgCiAQAnAAgJwxEyFgBjAQAAAA==.',
Re='Readycheck:BAABLgAECn8bAAInAAgJyQ8EGgA8AQAnAAgJyQ8EGgA8AQAAAA==.Reckalossi:BAAALgAECgkJAQABLgAFFAMJCwADAMoGAA==.Redcows:BAAALgADCggJFAAAAA==.Redeemed:BAAALgADCgEJAQAAAA==.Reikon:BAABLgAECn8iAAIDAAgJzB1pNQBNAgADAAgJzB1pNQBNAgAAAA==.Remulous:BAABLgAECn8VAAIWAAcJyQgyjAD0AAAWAAcJyQgyjAD0AAAAAA==.Revelaen:BAACLgAFFH8MAAIYAAQJnBPgIAAYAQAYAAQJnBPgIAAYAQAuAAQKfyMAAxgACQlxHQ0JAOcCABgACQlxHQ0JAOcCABsABQlYBowoANwAAAAA.',
Ri='Rick:BAACLgAFFH8ZAAMWAAUJ5iUzCAC4AQAWAAUJ5iUzCAC4AQAXAAEJXBoLJQBUAAAuAAQKfysAAxYACQmkI6QIAPMCABcACAlpI+QJAAUDABYACQlqI6QIAPMCAAAA.Rickers:BAAALgAECgMJAwABLgAFFAUJGQAWAOYlAA==.Rikosan:BAAALgAECgEJAwAAAA==.',
Ro='Roarz:BAAALgADCgkJCQAAAA==.Rollthebones:BAAALgADCgMJAwAAAA==.Roman:BAABLgAECn8hAAMHAAYJayWAEABvAgAHAAYJayWAEABvAgADAAQJnRkyrQAoAQABLgAFFAQJCgAgAKAlAA==.Roust:BAAALgAECgUJBQABLgAFFAQJCQAJAE0gAA==.',
Ru='Runinfear:BAAALgADCgYJBgAAAA==.',
Sa='Saba:BAAALgAECgMJBAAAAA==.Saephora:BAABLgAECn8fAAIJAAgJxQOwtwD6AAAJAAgJxQOwtwD6AAAAAA==.Saerea:BAACLgAFFH8FAAIEAAIJ7B3zlwCeAAAEAAIJ7B3zlwCeAAAuAAQKfyAAAgQACAkuH30zAGkCAAQACAkuH30zAGkCAAAA.Sahhm:BAAALgAFFAMJAwAAAA==.Salali:BAAALgAECgQJBwAAAA==.Samael:BAAALgAECgMJBgABLgAFFAQJCwAPAMQSAA==.Sammel:BAABLgAECn8ZAAMhAAgJ9BhXFABNAgAhAAgJ9BhXFABNAgAVAAEJCRG+YgAyAAAAAA==.Sandmanslim:BAAALgAECgUJBQAAAA==.Sathreina:BAACLgAFFH8GAAIDAAMJvAVTWQDGAAADAAMJvAVTWQDGAAAuAAQKfyoAAgMACQlEFmQ6APkBAAMACQlEFmQ6APkBAAAA.Sawbones:BAAALgADCggJCQAAAA==.',
Sc='Scaries:BAABLgAECn8XAAIGAAkJKRtoEgCAAgAGAAkJKRtoEgCAAgAAAA==.Scootzmcgee:BAAALgAECgUJCgAAAA==.',
Se='Seikura:BAAALgADCgMJAwAAAA==.Sekii:BAEALgAECgQJBAABLgAFFAUJFAARAIMjAA==.Sekimaru:BAACLgAFFH8RAAIQAAUJjxHVFQA4AQAQAAUJjxHVFQA4AQAuAAQKfzQAAxAACQnXGvYHAIUCABAACQnXGvYHAIUCAA8AAQmnBz0jAC8AAAAA.Selok:BAAALgAFFAEJAgAAAA==.',
Sh='Shaddik:BAAALgAECgQJBgABLgAECggJEAABAAAAAA==.Shadowisbad:BAAALgAECgkJEwAAAA==.Shadpriest:BAAALgAECggJEAAAAA==.Shaeledoran:BAACLgAFFH8OAAIEAAUJZBsTMABkAQAEAAUJZBsTMABkAQAuAAQKf0EAAgQACQnJIJoUAKsCAAQACQnJIJoUAKsCAAAA.Shamaneggs:BAAALgAFFAMJBAAAAA==.Shamatroxx:BAACLgAFFH8lAAIMAAYJKxf3AQCUAQAMAAYJKxf3AQCUAQAuAAQKfyoAAgwACQmKHa0EAHwCAAwACQmKHa0EAHwCAAAA.Shampomaster:BAAALgADCgMJAwAAAA==.Sheist:BAAALgAFFAEJAQABLgAFFAQJCQAJAE0gAA==.Shieetz:BAAALgAECgYJEQAAAA==.Shlomie:BAAALgADCggJGgAAAA==.Shlomiel:BAAALgADCgEJAQAAAA==.Shlomieo:BAAALgADCgkJFwAAAA==.Shocknasty:BAAALgAECgEJAQAAAA==.Shorttemper:BAAALgADCgkJDQAAAA==.Shänk:BAABLgAECn8cAAMQAAYJYBCvJwAqAQAQAAYJYBCvJwAqAQAPAAQJVgvYEgDVAAAAAA==.',
Si='Sibirica:BAAALgADCgEJAQAAAA==.Siena:BAAALgAECgYJDAAAAA==.Silith:BAAALgAECgYJCwAAAA==.Silre:BAAALgAECgYJEQAAAA==.Silverfangg:BAAALgADCgkJEQAAAA==.Sinergy:BAABLgAECn8UAAIRAAYJIh8zRAD/AQARAAYJIh8zRAD/AQAAAA==.Siz:BAAALgAECgYJCAAAAA==.',
Sk='Skiddlebutt:BAAALgADCgMJAgAAAA==.Skirmish:BAAALgAECgYJEgAAAA==.Skyray:BAAALgADCgUJBQAAAA==.',
Sl='Slappeepries:BAAALgADCgEJAQABLgAECgkJEQABAAAAAA==.Slappeey:BAAALgAECgkJEQAAAA==.',
Sn='Snapbean:BAAALgADCgEJAQAAAA==.Snarls:BAAALgAECgIJAgABLgAECggJLQAgAFokAA==.Snaxx:BAAALgAECgMJBgABLgAECgcJDQABAAAAAA==.Snorunt:BAAALgAECgYJEAAAAA==.Snuudle:BAACLgAFFH8OAAMEAAMJViBIJgD9AAAEAAMJViBIJgD9AAAoAAEJsBXtGABGAAAuAAQKf00AAwQACQkmJecKAPgCAAQACQlZJOcKAPgCACgACAnPJN8BAM4CAAAA.',
So='Solokills:BAAALgAECgcJDwAAAA==.Soulreaperqt:BAAALgAECgMJAwABLgAECgUJCwABAAAAAA==.Soundtrack:BAAALgADCgEJAQAAAA==.',
Sp='Spaceman:BAAALgAECgQJBwABLgAFFAUJEQAVAB8LAA==.',
Sq='Sqlpal:BAABLgAECn8cAAMZAAcJox60LwA9AgAZAAcJox60LwA9AgAlAAQJOB77PgAAAQAAAA==.Squirrels:BAABLgAECn8oAAMGAAcJvQ0cLwApAQAGAAcJvQ0cLwApAQATAAQJuwXsUgCGAAAAAA==.Squirtstorm:BAABLgAECn8xAAINAAgJyCKVCQDyAgANAAgJyCKVCQDyAgAAAA==.Squirtz:BAAALgADCgUJBAAAAA==.',
Sr='Srgntsnoop:BAAALgADCgUJBQAAAA==.',
St='Stabmywood:BAABLgAECn8yAAMQAAkJjCO8AgANAwAQAAkJjCO8AgANAwAdAAEJNxa1GwA+AAAAAA==.Sthella:BAAALgADCgMJAwABLgAECgUJDQABAAAAAA==.Stompy:BAAALgADCgkJEAABLgAFFAQJEgAhAFYQAA==.Storienn:BAAALgAECggJEgAAAA==.Stormßlessed:BAAALgADCgUJBQAAAA==.Strokemyhorn:BAAALgAECgQJBQAAAA==.',
Su='Subarashii:BAAALgAECgEJAQABLgAECgYJEQABAAAAAA==.Suküna:BAACLgAFFH8LAAIZAAMJPBgMRADuAAAZAAMJPBgMRADuAAAuAAQKfzEAAhkACQkIISkZAL0CABkACQkIISkZAL0CAAAA.Sunglo:BAAALgADCgYJBgAAAA==.Surefire:BAAALgAECgEJAQAAAA==.',
Sw='Swaption:BAACLgAFFH8LAAINAAQJFiUIDgCuAQANAAQJFiUIDgCuAQAuAAQKfyQAAg0ACAnjJCAMAL8CAA0ACAnjJCAMAL8CAAAA.Swolebane:BAAALgADCgUJBQAAAA==.',
Sy='Sybaü:BAAALgAECgYJDAAAAA==.Synchronize:BAABLgAECn8YAAIEAAcJPhSEeQCRAQAEAAcJPhSEeQCRAQAAAA==.Syrelia:BAABLgAECn80AAIJAAkJ2xU/OgAVAgAJAAkJ2xU/OgAVAgAAAA==.',
Ta='Takèda:BAABLgAECn8hAAIkAAgJ3RxjDwAdAgAkAAgJ3RxjDwAdAgAAAA==.Taldain:BAAALgAFFAEJAQAAAA==.Talonstrykz:BAABLgAECn8VAAIQAAgJ0A42IgDnAQAQAAgJ0A42IgDnAQAAAA==.Tankdeesnuts:BAABLgAECn8sAAILAAYJzAiNLgCiAAALAAYJzAiNLgCiAAAAAA==.Tashalle:BAAALgAECgEJAQABLgAECggJJgAVAOseAA==.Tauloe:BAABLgAECn8dAAIOAAcJOAuuPwAEAQAOAAcJOAuuPwAEAQAAAA==.Tayna:BAAALgAECgYJCQAAAA==.',
Te='Teejaydh:BAAALgADCgEJAQAAAA==.Tellamon:BAABLgAECn8aAAIDAAgJrhPSZgCCAQADAAgJrhPSZgCCAQAAAA==.Tetanus:BAAALgAECgQJBwABLgAECgYJEgABAAAAAA==.Teyassha:BAAALgAECgEJAwAAAA==.',
Th='Thomo:BAABLgAECn8cAAMWAAgJAQhTZABOAQAWAAgJowdTZABOAQAkAAYJ2gSgHAAMAQAAAA==.Throatfist:BAAALgAFFAIJBAABLgAFFAYJFQAZAFAeAA==.Throme:BAAALgAECgkJCQAAAA==.Thunk:BAACLgAFFH8JAAIOAAMJPRfdDQAMAQAOAAMJPRfdDQAMAQAuAAQKfyYAAg4ACQmXJfUDAGADAA4ACQmXJfUDAGADAAAA.',
Ti='Timdawg:BAABLgAECn8UAAIJAAgJ9SJ6EwDLAgAJAAgJ9SJ6EwDLAgABLgAECgUJEwABAAAAAA==.',
Tj='Tjkrollsaway:BAAALgAECgIJAgAAAA==.',
To='Todrick:BAAALgAECgEJAQAAAA==.Tomotostein:BAACLgAFFH8JAAIDAAMJCg+YTwDjAAADAAMJCg+YTwDjAAAuAAQKfywAAgMACQkVH6UPAM8CAAMACQkVH6UPAM8CAAAA.Tonobaggins:BAAALgADCggJCAAAAA==.Toothluss:BAAALgADCgMJAgAAAA==.Totemnutz:BAAALgAECgIJAgABLgAECgYJFwATAGMVAA==.',
Tr='Tradrael:BAAALgAECgEJAQAAAA==.Tristîtia:BAAALgAFFAEJAQAAAA==.',
Ts='Tsume:BAABLgAECn8UAAIWAAYJyxgNYgBUAQAWAAYJyxgNYgBUAQAAAA==.',
Tu='Tumlek:BAAALgAECgIJAgAAAA==.Tunobuffpapi:BAAALgAFFAIJAgAAAA==.',
Ty='Tyrinn:BAAALgAECgkJEgAAAA==.Tystian:BAAALgADCgQJBAAAAA==.Tyv:BAABLgAECn8yAAMfAAkJAxZHAgAbAgAfAAkJAxZHAgAbAgAJAAUJjwYd3wC4AAAAAA==.',
Ur='Urä:BAAALgAECgIJAgAAAA==.',
Va='Vainatetosix:BAAALgAECgQJCAAAAA==.Valindra:BAAALgAECgUJCQAAAA==.Vallodon:BAABLgAECn8hAAIJAAkJ6SBhLABKAgAJAAkJ6SBhLABKAgAAAA==.Valyndra:BAAALgAECgYJCAAAAA==.Vanquizsher:BAAALgAECgIJAgAAAA==.Vanwolfy:BAABLgAECn8ZAAILAAgJVAnjHQAcAQALAAgJVAnjHQAcAQAAAA==.',
Ve='Velanthris:BAAALgAECgMJBQABLgAECgYJCAABAAAAAA==.Velectran:BAABLgAECn8qAAIDAAgJJRc2PwDqAQADAAgJJRc2PwDqAQABLgAECgkJNAAJANsVAA==.Velorian:BAAALgAECgIJAgAAAA==.',
Vi='Vilgehkfrúna:BAAALgAECgEJAQAAAA==.Virdreth:BAAALgAECgEJAQAAAA==.Vish:BAAALgAECgUJBgAAAA==.',
Vo='Voidsauce:BAAALgAECgEJAQAAAA==.Vortash:BAAALgAECgQJAgAAAA==.',
Vy='Vynle:BAAALgAECgQJBgAAAA==.Vyrthos:BAAALgADCgkJCQABLgAFFAMJCAAJABMDAA==.',
['Vä']='Vämpira:BAAALgAECgYJCQAAAA==.',
Wa='Warheimer:BAAALgAECgEJAQAAAA==.Warrgodx:BAABLgAECn8WAAMCAAYJBBpgPQAnAQACAAYJBBpgPQAnAQAcAAMJkxJ1NwC1AAAAAA==.Wartroxx:BAAALgAECgUJCAABLgAFFAYJJQAMACsXAA==.',
We='Wengja:BAABLgAECn8gAAQTAAcJryULBwDqAgATAAcJryULBwDqAgAGAAEJ9QSVjgAnAAAaAAEJAACmiQAlAAAAAA==.',
Wh='Wheri:BAAALgADCggJCAABLgAECgkJJAAcABkbAA==.Whoknows:BAAALgAECgYJDgAAAA==.',
Wi='Wiz:BAAALgAECgEJAQAAAA==.',
Wo='Wolfchef:BAAALgAECgYJDAAAAA==.Woodkin:BAAALgAECgUJEQAAAA==.',
Wr='Wrongwookie:BAABLgAECn8iAAIOAAkJxR2mCAAIAwAOAAkJxR2mCAAIAwAAAA==.',
Wy='Wyrmbreaker:BAAALgAECgMJBgAAAA==.',
Xi='Xiak:BAAALgADCgYJBgABLgAECgkJKwAiAPobAA==.',
Ya='Yako:BAAALgAECgIJAgAAAA==.',
Ye='Yereka:BAAALgADCgQJBAAAAA==.',
Yo='Yoomesbonds:BAAALgAFFAEJAQAAAA==.Youtube:BAACLgAFFH8nAAMYAAgJzSJhAQDmAgAYAAgJzSJhAQDmAgAbAAMJayGKAwAlAQAuAAQKfyMAAxsACQkrJVQDAOoCABsABwmsJVQDAOoCABgABwkQIsYgALABAAAA.Yoyohunty:BAAALgAECgEJAgAAAA==.Yozki:BAABLgAECn8cAAIJAAcJ5CAGVAA8AgAJAAcJ5CAGVAA8AgAAAA==.',
Yt='Ytix:BAAALgAECgMJAwAAAA==.',
Yu='Yuji:BAAALgAECgEJAQABLgAFFAMJCQAOAD0XAA==.Yuuki:BAAALgAECgQJBQABLgAFFAQJCwAPAMQSAA==.Yuulia:BAABLgAECn8kAAMcAAkJGRtlCABDAgAcAAkJqhplCABDAgALAAYJeRhvGQCGAQAAAA==.',
Za='Zabada:BAAALgADCgkJHwAAAA==.Zaee:BAAALgAECgIJBQABLgAFFAMJBgANAK0NAA==.Zariee:BAABLgAECn8YAAIlAAcJUwx4JAAZAQAlAAcJUwx4JAAZAQAAAA==.',
Ze='Zemsen:BAACLgAFFH8IAAIJAAMJEwMGMgDgAAAJAAMJEwMGMgDgAAAuAAQKfzAAAwkACQmjGOY8AIQCAAkACQmjGOY8AIQCAB8AAgneBcAZAEoAAAAA.Zentrea:BAAALgAECgIJAgABLgAFFAQJEgAhAFYQAA==.Zenyea:BAAALgAECgQJBAABLgAFFAQJEgAhAFYQAA==.Zetta:BAACLgAFFH8SAAIhAAQJVhBgEwAxAQAhAAQJVhBgEwAxAQAuAAQKfysAAiEACQmbH+sMALUCACEACQmbH+sMALUCAAAA.',
Zo='Zoguk:BAAALgADCgEJAQAAAA==.Zoktavir:BAAALgADCgcJCAAAAA==.Zoltan:BAABLgAECn8VAAIJAAYJnQve2QA9AQAJAAYJnQve2QA9AQAAAA==.Zorin:BAAALgADCgcJDgAAAA==.',
Zy='Zyndrael:BAABLgAECn8lAAIDAAkJtBlgJABSAgADAAkJtBlgJABSAgAAAA==.',
['Zâ']='Zâgs:BAAALgADCgYJCAAAAA==.',
['Êl']='Êlytz:BAAALgAECggJEAAAAA==.',
['ßl']='ßlue:BAACLgAFFH8FAAIGAAQJHxBoHwASAQAGAAQJHxBoHwASAQAuAAQKf0sABAYACAlIH1wPACcCAAYACAlIH1wPACcCABMABgmIGSolALABABoAAQksDIKBADEAAAAA.',
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
