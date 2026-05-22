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

local lookup = {'Unknown-Unknown','Warrior-Fury','Paladin-Retribution','Priest-Holy','Monk-Brewmaster','Paladin-Holy','Druid-Restoration','Mage-Frost','DeathKnight-Blood','Warrior-Protection','DeathKnight-Unholy','Shaman-Enhancement','Shaman-Restoration','Shaman-Elemental','Rogue-Assassination','Rogue-Subtlety','Warlock-Demonology','Warlock-Destruction','Monk-Mistweaver','Paladin-Protection','Priest-Discipline','Hunter-BeastMastery','Hunter-Marksmanship','Evoker-Augmentation','Monk-Windwalker','Evoker-Devastation','DemonHunter-Devourer','Rogue-Outlaw','DemonHunter-Vengeance','Mage-Arcane','Evoker-Preservation','Priest-Shadow','Druid-Feral','Druid-Balance','Hunter-Survival','Warrior-Arms','DemonHunter-Havoc','Warlock-Affliction','DeathKnight-Frost','Druid-Guardian',}
local provider = {region='US',realm='Akama',name='US',type='weekly',zone=46,date='2026-05-16',data={Ac='Accost:BAAALgAECgQJBQAAAA==.',
Ad='Adagar:BAAALgAECgYJCwAAAA==.Adesha:BAAALgADCgYJBgAAAA==.',
Ae='Aeloria:BAAALgAECgcJBgAAAA==.Aeratedlol:BAAALgAFFAIJAwABLgAFFAQJBAABAAAAAA==.Aethandor:BAAALgAECgUJDAAAAA==.',
Ak='Akassa:BAABLgAECn8ZAAICAAYJfwm/QQDrAAACAAYJfwm/QQDrAAAAAA==.Akavaleera:BAAALgAECgQJBgAAAA==.Aknologia:BAAALgADCgYJBgABLgAECgMJAwABAAAAAA==.Akíto:BAAALgAECgEJAQAAAA==.',
Al='Alaric:BAAALgADCgUJBQAAAA==.Alecto:BAABLgAECn8ZAAIDAAkJFAsnWQB3AQADAAkJFAsnWQB3AQAAAA==.Algo:BAAALgADCgkJCQAAAA==.Alune:BAAALgADCgYJDAAAAA==.',
Am='Amarah:BAACLgAFFH8HAAIEAAMJsRD3FADEAAAEAAMJsRD3FADEAAAuAAQKfzsAAgQACQnKHEYJAIsCAAQACQnKHEYJAIsCAAAA.',
An='Andron:BAAALgADCgIJAgAAAA==.Andy:BAAALgADCgcJBwAAAA==.Angryjames:BAAALgADCgYJCgAAAA==.Animehero:BAAALgAECgIJAwABLgAECgkJFQAFAJIcAA==.',
Ap='Applemonster:BAAALgAECggJDwAAAA==.',
Ar='Arboghast:BAAALgAECgUJCAAAAA==.Argdru:BAAALgAECgYJDQAAAA==.Arglock:BAAALgADCgIJAgABLgAECgYJDQABAAAAAA==.Argrekd:BAAALgADCgMJAwABLgAECgYJDQABAAAAAA==.Aridol:BAAALgADCgUJBAAAAA==.Arigön:BAAALgADCgMJAwAAAA==.Arima:BAAALgAECgEJAQAAAA==.Arknox:BAABLgAECn8bAAIGAAkJIA0VIQCvAQAGAAkJIA0VIQCvAQAAAA==.Arthaslk:BAAALgAECgcJCAABLgAECgYJEwABAAAAAA==.',
As='Aserus:BAAALgAECgcJCwABLgAFFAUJGAAHAGUeAA==.Ashallel:BAAALgAECgQJBAABLgAFFAUJGAAHAGUeAA==.Ashx:BAAALgADCgIJBAABLgAECgkJIAAIAKoXAA==.Astralock:BAAALgAECgEJAQAAAA==.',
At='Ate:BAABLgAECn8UAAIJAAgJig8vFwBUAQAJAAgJig8vFwBUAQABLgAECgcJJwAKALQbAA==.Atlette:BAACLgAFFH8NAAIEAAQJOxwUCwA5AQAEAAQJOxwUCwA5AQAuAAQKfyoAAgQACQluH2MCAEUDAAQACQluH2MCAEUDAAAA.Atrocitusz:BAAALgAECgIJAgAAAA==.Atroxx:BAACLgAFFH8MAAILAAQJ0w3BHgAjAQALAAQJ0w3BHgAjAQAuAAQKf0UAAgsACAnaI8wQABcDAAsACAnaI8wQABcDAAEuAAUUBgkkAAwAKxcA.Attman:BAACLgAFFH8KAAINAAQJ6RQ+GgAqAQANAAQJ6RQ+GgAqAQAuAAQKfx4AAw0ACAkSHNMPAIICAA0ACAkSHNMPAIICAA4AAwlFAzyEADoAAAAA.',
Au='Auradawn:BAAALgAECgQJEgAAAA==.',
Ay='Ayaya:BAAALgAECgEJAgABLgAECgYJEQABAAAAAA==.',
Ba='Baetrayer:BAAALgAECgcJCAAAAA==.Bailz:BAAALgADCgMJAwAAAA==.Balimund:BAAALgAECgEJAQAAAA==.Ballerstatus:BAAALgAECgMJAwAAAA==.Ballsofaith:BAAALgADCgkJFAABLgAECgcJJwAKALQbAA==.Ballsofire:BAABLgAECn8nAAIKAAcJtBuxDQC/AQAKAAcJtBuxDQC/AQAAAA==.Basherz:BAAALgAECgQJBgAAAA==.',
Be='Bearmane:BAAALgAECgYJDAAAAA==.Beedoc:BAAALgADCgEJAQAAAA==.Behindithu:BAABLgAECn8dAAMPAAcJ+w8WCwA8AQAPAAYJmRIWCwA8AQAQAAYJ5wWsMQCwAAAAAA==.Belithel:BAABLgAECn8gAAIIAAkJqhd5WgCNAQAIAAkJqhd5WgCNAQAAAA==.Bencreepin:BAABLgAECn8UAAIJAAYJ9Q/qIAD2AAAJAAYJ9Q/qIAD2AAAAAA==.Beniz:BAABLgAECn8WAAMRAAcJ9QjifwD8AAARAAcJRAjifwD8AAASAAIJBQnHWgBeAAAAAA==.Bernoulli:BAABLgAECn8cAAITAAgJDRvHFwDlAQATAAgJDRvHFwDlAQAAAA==.',
Bi='Bigblunts:BAAALgADCgEJAgAAAA==.Bigcrunch:BAAALgAECggJCQAAAA==.Bignative:BAAALgAECgYJCAAAAA==.Bironic:BAAALgAECgUJBwABLgAECgYJFAAPANsKAA==.',
Bl='Bloodboo:BAAALgAECgQJBAAAAA==.Bloodyhpally:BAAALgAFFAIJAgABLgAFFAgJJgATAKIfAA==.Bloodymyst:BAABLgAFFH8mAAITAAgJoh+MAAAcAwATAAgJoh+MAAAcAwAAAA==.Blumpy:BAAALgADCggJCAAAAA==.',
Bo='Boethius:BAAALgAECgEJAQABLgAECgYJCwABAAAAAA==.Boopsnoopems:BAABLgAECn8ZAAIUAAYJqhPyFgAVAQAUAAYJqhPyFgAVAQAAAA==.Borderline:BAAALgADCgYJBgABLgAFFAQJDAAVADoMAA==.',
Br='Briannajade:BAABLgAECn8eAAIIAAgJsAgIhwAuAQAIAAgJsAgIhwAuAQAAAA==.Brisha:BAACLgAFFH8eAAIGAAYJGx9ZBQABAgAGAAYJGx9ZBQABAgAuAAQKfzMAAwYACQlIJHQAALUDAAYACQlIJHQAALUDABQAAQk8Egs5ADYAAAAA.Brodan:BAAALgAECgQJBAAAAA==.Brokenhealz:BAAALgAECgQJBgAAAA==.',
Bs='Bs:BAAALgAECgYJBgABLgAFFAQJBwALAH8PAA==.',
Bu='Bubble:BAAALgADCgEJAgAAAA==.Bubblehash:BAAALgADCgEJAQAAAA==.Bubbletarded:BAAALgAECgUJBgAAAA==.Bustah:BAABLgAECn8eAAMWAAgJex24DgDFAgAWAAgJex24DgDFAgAXAAYJag3uTwAPAQABLgAFFAQJBwALAH8PAA==.',
Ca='Cacaco:BAAALgADCgIJAgAAAA==.Cactuscooler:BAAALgADCgcJBwAAAA==.Caffrey:BAABLgAECn8ZAAIHAAkJ1SKyAQCJAwAHAAkJ1SKyAQCJAwAAAA==.Cammi:BAAALgAECgYJDwAAAA==.Cammywammy:BAAALgAECgcJCAAAAA==.Casare:BAABLgAECn8bAAIXAAYJLAmAGQClAAAXAAYJLAmAGQClAAAAAA==.Catjam:BAAALgAFFAIJAgABLgAFFAgJJwAYAM0iAA==.',
Ce='Celarc:BAAALgAECgYJDwAAAA==.Celithe:BAAALgAECgcJDwABLgAECgkJLQAIACcVAA==.Celyda:BAAALgADCgcJBwAAAA==.',
Ch='Chapito:BAAALgAECgcJCAAAAA==.Chipmonked:BAABLgAECn8sAAQFAAkJnwrHIABjAQAFAAkJtgnHIABjAQAZAAYJOwpiNwDUAAATAAUJIwPLUACQAAAAAA==.Chlop:BAABLgAECn8ZAAILAAgJcBx0HADUAgALAAgJcBx0HADUAgAAAA==.Chunkers:BAAALgAECgQJBAAAAA==.Chuubar:BAAALgADCgYJCwAAAA==.',
Ci='Cinderzin:BAABLgAECn8vAAIaAAkJmAiQBwB8AQAaAAkJmAiQBwB8AQAAAA==.',
Cl='Clawhalla:BAAALgAECgYJCgAAAA==.',
Cn='Cnorthover:BAAALgAECgQJBAAAAA==.',
Co='Cobrallig:BAAALgAECggJDAAAAA==.Colexn:BAAALgAECgQJBAAAAA==.Comfyboi:BAAALgAECgYJDAAAAA==.Cong:BAAALgAFFAIJAgABLgAFFAYJFQAbAFAeAA==.Congdh:BAACLgAFFH8VAAIbAAYJUB5EDADBAQAbAAYJUB5EDADBAQAuAAQKfyUAAhsACQkZJN4FAP4CABsACQkZJN4FAP4CAAAA.Conmann:BAAALgAECgYJEQAAAA==.Corg:BAAALgADCgUJBQAAAA==.Cornchipz:BAAALgAECgMJAwAAAA==.Cowmage:BAAALgAECgEJAQAAAA==.',
Cr='Crit:BAAALgADCgcJCAAAAA==.Crossy:BAAALgAECgQJBQAAAA==.Cryogenic:BAAALgAECgYJEQAAAA==.Cryptex:BAAALgADCgEJAQAAAA==.',
Cy='Cyrus:BAAALgADCgQJBAAAAA==.',
Cz='Czznkj:BAAALgADCgkJDgAAAA==.',
['Cá']='Cálívént:BAAALgAECgQJAwAAAA==.',
Da='Daak:BAAALgADCgkJGQABLgAECgcJIgAFAFsKAA==.Dabberoni:BAAALgAECgcJAQAAAA==.Dabthorne:BAAALgADCgEJAgAAAA==.Daegra:BAAALgAECgkJCgAAAA==.Daelin:BAAALgAECgEJAQAAAA==.Dankkush:BAACLgAFFH8IAAILAAQJaBE/PgA7AQALAAQJaBE/PgA7AQAuAAQKfxgAAgsACQmtHm8sAAcCAAsACQmtHm8sAAcCAAAA.Darkacedia:BAABLgAECn8jAAMRAAgJJh9bHQCmAgARAAgJJh9bHQCmAgASAAMJyQ9aQwCoAAAAAA==.Darkrubie:BAAALgADCgMJAwAAAA==.Datbish:BAAALgAECgUJBQAAAA==.Dawgis:BAAALgAECgEJAQAAAA==.',
Db='Dbznz:BAAALgADCgYJBwAAAA==.',
De='Deadcell:BAABLgAECn8UAAILAAcJNCEXKQAVAgALAAcJNCEXKQAVAgAAAA==.Deadcells:BAAALgAECgQJCQABLgAECgcJFAALADQhAA==.Deadharvest:BAAALgAECgYJBwAAAA==.Deadlift:BAAALgAECgQJCgAAAA==.Dealosed:BAACLgAFFH8LAAMPAAQJ2RCuBAAAAQAPAAMJXRauBAAAAQAQAAQJ+wkYDwD/AAAuAAQKfzQABA8ACQkxI58AACADAA8ACQm8Ip8AACADABAABwnOIMoRAJECABwABgllHkMFAMQBAAAA.Decrepit:BAABLgAECn8cAAILAAgJqhr6LQAAAgALAAgJqhr6LQAAAgAAAA==.Defect:BAAALgAECgQJBAAAAA==.Demonclawz:BAABLgAECn8VAAIRAAgJGgztUwBhAQARAAgJGgztUwBhAQAAAA==.Demonscar:BAAALgAECgUJCwAAAA==.Dex:BAAALgAECgEJAQAAAA==.',
Dh='Dhaeverdh:BAAALgADCgIJAgAAAA==.',
Di='Diddious:BAAALgADCgMJAgAAAA==.Diremane:BAAALgAECgIJAgAAAA==.Disastacast:BAAALgAECgMJAwABLgAECgcJFAAdAPkVAA==.Disastasmite:BAAALgADCgEJAQABLgAECgcJFAAdAPkVAA==.Dive:BAACLgAFFH8JAAIIAAQJTSDJGwCTAQAIAAQJTSDJGwCTAQAuAAQKfyMAAwgACQkPIuwmANcCAAgACAmOIewmANcCAB4ABQmeHHwLAB8BAAAA.',
Dk='Dkeruu:BAAALgAECgUJCAAAAA==.',
Do='Doinks:BAABLgAECn8VAAIFAAkJkhwxDgCxAgAFAAkJkhwxDgCxAgAAAA==.Dondozo:BAAALgAECgUJCwAAAA==.Doogru:BAABLgAECn8uAAICAAkJrReMDgBDAgACAAkJrReMDgBDAgAAAA==.Doufu:BAAALgAECgQJBAABLgAECgYJDAABAAAAAA==.',
Dr='Dracomaibois:BAAALgAECgYJCgAAAA==.Dragoneggs:BAACLgAFFH8MAAMYAAMJcxmuJQDtAAAYAAMJcxmuJQDtAAAfAAMJqQnYFwC2AAAuAAQKfycAAxgACQnaHuwIAOkCABgACQnaHuwIAOkCAB8ABwkZE9AUADIBAAAA.Dragonforce:BAAALgAECgYJDAABLgAECgkJEQABAAAAAA==.Draxan:BAAALgADCgcJCAAAAA==.Draxx:BAAALgAECgcJDgAAAA==.Dreammachine:BAABLgAECn8vAAIgAAkJ1COxAgAUAwAgAAkJ1COxAgAUAwAAAA==.Driipp:BAAALgAFFAMJAwAAAA==.Drizs:BAAALgADCgEJAQAAAA==.Drjoel:BAAALgADCgYJCAAAAA==.Drunkenutz:BAABLgAECn8UAAMTAAYJYxWWNQAZAQATAAUJxxKWNQAZAQAFAAYJqQ2BNgDnAAAAAA==.',
Du='Duane:BAAALgADCgEJAQABLgAFFAQJDAAVADoMAA==.',
Dy='Dyab:BAAALgAECgEJAQAAAA==.',
['Dä']='Dälf:BAABLgAECn8cAAMhAAcJnCFlCwAKAgAhAAYJbiNlCwAKAgAHAAYJLRDfWABIAQABLgAFFAgJHAAYAL0YAA==.',
Ec='Echidona:BAABLgAECn8bAAIQAAgJERn8EwB2AgAQAAgJERn8EwB2AgAAAA==.',
Ed='Edirii:BAAALgADCgEJAQAAAA==.',
Ee='Eelsky:BAAALgAECgcJEgAAAA==.',
Ef='Efvoidhunter:BAAALgAECgUJBQAAAA==.',
Ek='Eksi:BAEALgAECgQJBAABLgAFFAUJFAARAIMjAA==.',
El='Elenix:BAABLgAECn8aAAMOAAkJyRy0CAAGAwAOAAkJyRy0CAAGAwANAAMJhA3zgACQAAABLgAFFAMJBgAGABghAA==.Elinras:BAACLgAFFH8IAAIDAAMJ0wXMRgDVAAADAAMJ0wXMRgDVAAAuAAQKfxoAAgMACAn3FaJKAJ4BAAMACAn3FaJKAJ4BAAAA.Elliott:BAAALgADCgMJBQABLgADCggJDQABAAAAAA==.Elrizon:BAAALgAECgIJAQAAAA==.Elvar:BAAALgAECgcJDAABLgAECgQJBQABAAAAAA==.Elynith:BAAALgAECgIJBAAAAA==.Elynni:BAABLgAECn8dAAIEAAcJ2RUIIADhAQAEAAcJ2RUIIADhAQAAAA==.',
Em='Emmylou:BAAALgAECgEJAwAAAA==.Emotett:BAAALgADCgQJBAAAAA==.Emz:BAACLgAFFH8HAAIcAAMJVRquBAADAQAcAAMJVRquBAADAQAuAAQKfyQAAhwACAlQIuUAAAwDABwACAlQIuUAAAwDAAAA.',
En='Endboss:BAAALgAECgUJBQAAAA==.Endorsi:BAACLgAFFH8KAAIPAAQJxBLlAgBQAQAPAAQJxBLlAgBQAQAuAAQKfxUAAg8ABgmAGwwGAMEBAA8ABgmAGwwGAMEBAAAA.Enfuega:BAAALgAECgQJCwAAAA==.Eniar:BAACLgAFFH8MAAIGAAUJUAYeFAA3AQAGAAUJUAYeFAA3AQAuAAQKfxkAAwYACAnHFLguAMgBAAYACAnHFLguAMgBAAMABAl0CTDvALIAAAAA.',
Er='Eroninja:BAAALgAECgQJCAABLgAECgkJIAAIAKoXAA==.',
Eu='Eurong:BAACLgAFFH8NAAIiAAQJyhi8EwAsAQAiAAQJyhi8EwAsAQAuAAQKfxsAAiIACAl0H0waADICACIACAl0H0waADICAAAA.',
Ev='Evangelune:BAAALgAECgYJDAAAAA==.',
Ew='Ewright:BAAALgAECgEJAQABLgAECgYJDAABAAAAAA==.',
Ez='Ezynuff:BAABLgAECn8WAAMNAAYJ2RTUOgBiAQANAAYJ2RTUOgBiAQAOAAQJzQgxWgB6AAAAAA==.',
['Eï']='Eïr:BAAALgADCgcJCAAAAA==.',
Fa='Fakie:BAAALgAECgQJBAABLgAECgYJFAARACIfAA==.Fapple:BAAALgAECgcJEgABLgAECggJJwAfAGQjAA==.Fatesprocket:BAAALgAECgMJBQAAAA==.Faïry:BAACLgAFFH8MAAMWAAQJqxfQLwD9AAAWAAQJABHQLwD9AAAjAAMJTwvaFgDJAAAuAAQKfy0AAxYACQniG8oRAKoCABYACAkrHsoRAKoCACMABgkUCjYjALYAAAAA.',
Fe='Feardih:BAAALgADCgIJAgAAAA==.Felfrostette:BAAALgAECgEJAQAAAA==.Felheart:BAAALgAECgYJCAAAAA==.Feltnutz:BAAALgADCgQJBQABLgAECgYJFAATAGMVAA==.Felwyrm:BAAALgAECgYJCAABLgAFFAQJDAAVADoMAA==.Femboi:BAAALgADCgUJBQAAAA==.Fengshui:BAAALgAECgMJCQAAAA==.Feralle:BAAALgADCgQJBAAAAA==.',
Fl='Flacidmon:BAAALgAECgMJAwAAAA==.Flutterina:BAAALgAECgIJAgAAAA==.Flyjin:BAABLgAECn8dAAMfAAgJEQ5pJABVAQAfAAcJLgxpJABVAQAYAAgJJg64LQArAQAAAA==.Flylo:BAAALgADCgMJAwAAAA==.',
Fo='Folandras:BAAALgADCgcJDAABLgAECgcJJwAKALQbAA==.Forrestpump:BAAALgADCgMJAwAAAA==.',
Fr='Fries:BAECLgAFFH8HAAIRAAQJpg+7PQAQAQARAAQJpg+7PQAQAQAuAAQKfyQAAxEACAkCJI4LAMECABEACAkCJI4LAMECABIAAQmHGhtgAE8AAAAA.Frozenpyre:BAAALgAECgYJEQAAAA==.',
Fu='Funch:BAACLgAFFH8JAAISAAMJEA4DBgDkAAASAAMJEA4DBgDkAAAuAAQKfzIAAhIACAnAHMgCADUCABIACAnAHMgCADUCAAAA.',
['Fè']='Fènrir:BAAALgAECgEJAQABLgAECgYJDAABAAAAAA==.',
Ga='Gabbathegoo:BAAALgAFFAQJBAAAAA==.Gainzbrew:BAAALgAECgEJAgAAAA==.Gainzz:BAAALgAECgQJBgAAAA==.Galesdeyn:BAAALgAFFAEJAQAAAA==.Garl:BAAALgAECgUJBQABLgAECgcJFAAIAD4dAA==.Garonnaa:BAABLgAFFH8HAAIJAAMJqQe3GgClAAAJAAMJqQe3GgClAAAAAA==.',
Gh='Ghari:BAABLgAECn8kAAILAAgJvxN0VQB8AQALAAgJvxN0VQB8AQAAAA==.',
Gi='Gilrog:BAABLgAECn8WAAILAAUJLxAfpADZAAALAAUJLxAfpADZAAAAAA==.Gingerlock:BAAALgAECgUJBgAAAA==.',
Gl='Gladiusmax:BAAALgADCgQJBAAAAA==.',
Gn='Gnoblin:BAAALgAECgQJCAAAAA==.Gnz:BAAALgAECgUJBgAAAA==.Gnzz:BAAALgAECgcJDAAAAA==.',
Go='Gonz:BAAALgADCgcJBwAAAA==.',
Gr='Gravys:BAAALgAECgcJAwAAAA==.Greka:BAAALgAECgYJEgAAAA==.Greylooms:BAABLgAECn8nAAMkAAkJrx/WAgDCAgAkAAkJrx/WAgDCAgACAAYJhB3pMgDgAQAAAA==.Gruuith:BAAALgADCgEJAQAAAA==.',
Gw='Gwath:BAAALgAECgEJAQAAAA==.',
Gy='Gynaris:BAAALgAECgMJBQAAAA==.',
['Gâ']='Gâinzz:BAAALgADCgQJBAAAAA==.',
Ha='Hakun:BAAALgAECgMJAwAAAA==.Happyfriend:BAACLgAFFH8MAAMVAAQJOgzxGAAaAQAVAAQJOgzxGAAaAQAgAAEJZAAXKgA4AAAuAAQKfygAAxUACAnTFZcXAL4BABUACAnTFZcXAL4BACAABwmiEX8kALQBAAAA.Haruko:BAAALgADCgQJBAAAAA==.',
He='Heemski:BAAALgAECgMJAwAAAA==.Hellbourne:BAAALgADCggJDQAAAA==.Hellbrick:BAAALgADCgMJAwAAAA==.Hermitpurple:BAAALgADCgcJEwAAAA==.Heàl:BAAALgAECgYJDAAAAA==.',
Hi='Hidejames:BAAALgAECgYJCgAAAA==.Hims:BAAALgAECgYJEwABLgAFFAgJJwAYAM0iAA==.',
Ho='Hoguy:BAAALgAECgYJEAAAAA==.Holofox:BAACLgAFFH8cAAIHAAYJcRxjBAA4AgAHAAYJcRxjBAA4AgAuAAQKfzYAAwcACAkwJiADAGgDAAcACAkwJiADAGgDACEAAQkpBvY4ACcAAAAA.Holycrow:BAAALgAECgMJAwAAAA==.Holytotem:BAAALgADCgEJAQAAAA==.Horman:BAABLgAECn8WAAIZAAYJmwuQOgDHAAAZAAYJmwuQOgDHAAAAAA==.',
Hu='Hunterishard:BAAALgAECggJEAABLgAECgkJCgABAAAAAA==.',
Hy='Hylda:BAAALgAECgMJBgAAAA==.',
['Hï']='Hïru:BAAALgAECgYJCAAAAA==.',
['Hô']='Hôlÿ:BAAALgAECgQJCQABLgAECgYJEgABAAAAAA==.',
Ic='Iclapu:BAAALgAECgEJAgAAAA==.',
Ig='Igosduikanna:BAAALgADCgQJBQAAAA==.',
Ik='Ikerous:BAABLgAECn8bAAMdAAgJwRkwBwAWAgAdAAgJwRkwBwAWAgAlAAMJ1AmTVgCNAAAAAA==.',
Il='Ilililililli:BAABLgAECn8cAAMTAAgJ0Rc1JgCBAQATAAgJ0Rc1JgCBAQAZAAIJdghzWgBZAAAAAA==.',
Im='Imadwagon:BAAALgADCgkJCAAAAA==.Imapandairl:BAABLgAECn8VAAIOAAcJrR6CEgCOAgAOAAcJrR6CEgCOAgAAAA==.Imhammered:BAABLgAECn8dAAIGAAgJWQ/JJACUAQAGAAgJWQ/JJACUAQAAAA==.Impullse:BAAALgAFFAIJAwAAAA==.',
Ir='Ironpally:BAAALgAECgYJBwAAAA==.Irsty:BAAALgAECgEJAQABLgAECgYJDQABAAAAAA==.',
It='Ithilwen:BAABLgAECn8kAAIVAAgJ7B4fDQBnAgAVAAgJ7B4fDQBnAgAAAA==.Itiswhatitiz:BAAALgAECgYJEQAAAA==.Itsybityshiv:BAABLgAECn8vAAMQAAkJ4hr/CABKAgAQAAkJ4hr/CABKAgAPAAEJoBj0HwAzAAAAAA==.',
Iw='Iwillpull:BAAALgADCgcJDgAAAA==.',
Iz='Izzlirkkgazp:BAAALgAECgcJDgAAAA==.',
Ja='Jackiefox:BAAALgAECgIJAwAAAA==.Jahq:BAABLgAECn8VAAIbAAYJAyF8NAAnAgAbAAYJAyF8NAAnAgAAAA==.Jambs:BAAALgADCgEJAQAAAA==.Jaysontatum:BAAALgADCgEJAQAAAA==.',
Je='Jeabuss:BAAALgADCgcJBwAAAA==.',
Jh='Jhani:BAABLgAECn8XAAIIAAcJqgTgpQD3AAAIAAcJqgTgpQD3AAAAAA==.',
Ji='Jinu:BAAALgAECgYJDgAAAA==.Jixn:BAAALgAECgMJBQAAAA==.',
Jo='Joethemage:BAABLgAECn8wAAIIAAkJASHHDADiAgAIAAkJASHHDADiAgAAAA==.Jormojo:BAAALgAECgQJBQAAAA==.Jotwnky:BAABLgAECn8eAAQmAAcJAyC3BQAMAgAmAAUJSSO3BQAMAgASAAQJsxo7IwA+AQARAAMJGB9WuADoAAAAAA==.Jotwnkyy:BAACLgAFFH8FAAIQAAMJXg7rGQDtAAAQAAMJXg7rGQDtAAAuAAQKfycAAhAABwnvGxYSAMMBABAABwnvGxYSAMMBAAEuAAQKBwkeACYAAyAA.',
Ju='Jungol:BAAALgAECgIJAgAAAA==.',
Ka='Kaela:BAAALgAECgEJAQAAAA==.Kaikova:BAAALgADCgcJCgAAAA==.Kaliban:BAAALgADCgYJCQAAAA==.Kaltank:BAAALgAECggJAwAAAA==.Kamin:BAABLgAECn8jAAIKAAgJwiHjAwARAwAKAAgJwiHjAwARAwAAAA==.Karoka:BAAALgADCgEJAQAAAA==.Kasitos:BAAALgAFFAMJAwAAAA==.Katamaran:BAAALgAECgUJBQABLgAFFAQJEQAgAM0PAA==.Kaykaypally:BAABLgAECn8dAAIDAAkJbhIANwDdAQADAAkJbhIANwDdAQAAAA==.',
Ke='Keis:BAEALgAECgYJBgABLgAFFAUJFAARAIMjAA==.Keledron:BAAALgADCgcJCgAAAA==.Kellan:BAABLgAECn8qAAIDAAcJmxi6WQB1AQADAAcJmxi6WQB1AQAAAA==.Kelos:BAAALgAECgYJCAABLgAFFAEJAgABAAAAAA==.Kenwith:BAAALgADCgYJBgAAAA==.Keylethel:BAAALgADCgEJAQAAAA==.',
Ki='Kideki:BAABLgAECn8nAAIGAAkJSyI6BQABAwAGAAkJSyI6BQABAwAAAA==.Kidori:BAAALgAECgEJAQABLgAECgkJJwAGAEsiAA==.Kilgharra:BAAALgADCggJEQAAAA==.Killakevv:BAAALgADCgcJBwAAAA==.Kinji:BAAALgADCgYJCAABLgAECgkJIAAIAKoXAA==.Kirisute:BAAALgAECgEJAQAAAA==.',
Ko='Kolsch:BAAALgADCgQJBAAAAA==.Koriandar:BAABLgAECn8bAAIIAAgJ1wNTmAAOAQAIAAgJ1wNTmAAOAQAAAA==.Koyama:BAAALgADCgcJBwAAAA==.',
Kr='Kristysavage:BAABLgAECn8tAAIjAAgJJB/LCQBDAgAjAAgJJB/LCQBDAgAAAA==.Krul:BAAALgADCgkJCgAAAA==.Kruya:BAAALgAECgMJBAABLgAECgYJFAAPANsKAA==.',
Ku='Kulaesca:BAAALgAECgIJAgAAAA==.',
Ky='Kynar:BAACLgAFFH8ZAAMLAAcJKBwyBQAtAgALAAYJKBwyBQAtAgAJAAEJAABrEQBnAAAuAAQKfxcAAgsACAkuH60/ADoCAAsACAkuH60/ADoCAAAA.Kyperion:BAAALgAECgYJDQAAAA==.Kyua:BAABLgAECn8UAAIlAAYJBwhHKADSAAAlAAYJBwhHKADSAAAAAA==.',
La='Lambshot:BAABLgAECn8bAAMWAAcJEyH8KgDhAQAWAAcJEyH8KgDhAQAXAAEJ/AahjwArAAAAAA==.Lambsy:BAACLgAFFH8oAAQCAAgJ2RZAAQAIAgACAAcJYhhAAQAIAgAkAAEJYAXXIgBIAAAKAAEJpAguHQBHAAAuAAQKfx4AAwIACAmrIBARAMgCAAIACAl4HhARAMgCACQAAQnuI0A5AEsAAAAA.Landwhalexxl:BAABLgAECn8XAAIIAAcJ9BGOpACPAQAIAAcJ9BGOpACPAQAAAA==.Laneera:BAAALgAECgQJDAAAAA==.',
Le='Ledronys:BAAALgADCgEJAQAAAA==.Ledsole:BAAALgADCgEJAQAAAA==.Lerat:BAABLgAECn8sAAIaAAgJqSLIAQCNAgAaAAgJqSLIAQCNAgAAAA==.',
Li='Lichkali:BAAALgADCgMJAwAAAA==.Lightofhope:BAAALgAECggJEgAAAA==.Lihandra:BAAALgAECgQJBQAAAA==.Lillipup:BAAALgAECgQJBAAAAA==.Lillyy:BAAALgAECgIJAgABLgAECggJFgAIAMgaAA==.Lilyy:BAABLgAECn8WAAIIAAgJyBpJkgCuAQAIAAgJyBpJkgCuAQAAAA==.Liria:BAAALgAECgYJDQAAAA==.Lisanalgaib:BAABLgAECn8ZAAIDAAgJlRfNNwDaAQADAAgJlRfNNwDaAQAAAA==.Liulei:BAAALgAECgQJAwAAAA==.Lizzimcguire:BAAALgAECgQJBAAAAA==.',
Lo='Loharfal:BAAALgADCgEJAQAAAA==.Lokî:BAAALgAECgQJBAAAAA==.Loraen:BAAALgAECgYJEQAAAA==.Lorelei:BAAALgAECgEJAQABLgAECgkJJAAkABgbAA==.Lostep:BAAALgAECgEJAQABLgAFFAcJGwANAA8UAA==.Lowkeyjz:BAAALgADCgIJAgAAAA==.',
Lu='Luasa:BAAALgADCgIJAgAAAA==.Lukadoncic:BAAALgAECgYJDAABLgADCgEJAQABAAAAAA==.Lunarmon:BAAALgAECgQJCgAAAA==.Lunchable:BAABLgAECn8eAAIOAAgJnhmJFgBlAgAOAAgJnhmJFgBlAgAAAA==.Luxmalleo:BAAALgADCgkJDwABLgAECgYJFAAPANsKAA==.',
Ly='Lykho:BAAALgAECgEJAQAAAA==.',
['Lé']='Léblanc:BAABLgAECn8mAAIIAAgJEx1yRQBnAgAIAAgJEx1yRQBnAgAAAA==.',
Ma='Madam:BAAALgADCgMJBwAAAA==.Madday:BAAALgADCgcJDAAAAA==.Maelorus:BAAALgADCgkJEQAAAA==.Magicaltoast:BAAALgAECgIJAgABLgAECgYJEAABAAAAAA==.Mahli:BAAALgAECgEJAQAAAA==.Makah:BAAALgAECgMJAwAAAA==.Makaroni:BAAALgADCgcJBwAAAA==.Makizenin:BAAALgADCgYJCAAAAA==.Malenia:BAAALgADCgUJBwAAAA==.Malthezar:BAAALgADCgEJAQAAAA==.Manticus:BAAALgADCgYJEAAAAA==.Mari:BAAALgAECgMJBQABLgAFFAMJBwAEALEQAA==.Matroxx:BAABLgAECn8VAAMZAAcJRRpfIQBQAQAZAAQJex5fIQBQAQATAAcJfBA7MwAnAQABLgAFFAYJJAAMACsXAA==.',
Me='Meat:BAAALgAECgUJBQAAAA==.Meatballz:BAAALgADCgEJAQAAAA==.Meatbeef:BAAALgADCgEJAQAAAA==.Meenoi:BAACLgAFFH8HAAILAAQJfw+oQwAxAQALAAQJfw+oQwAxAQAuAAQKfysAAgsACAnPIS4kAC0CAAsACAnPIS4kAC0CAAAA.Melysia:BAACLgAFFH8YAAIHAAUJZR4hCgDJAQAHAAUJZR4hCgDJAQAuAAQKfzoAAwcACQl0IP8MANQCAAcACQl0IP8MANQCACEAAgmmCecrAE4AAAAA.Metalgear:BAAALgADCgYJDAAAAA==.',
Mi='Miadas:BAAALgAECgIJBAABLgAECgkJJwAhAAkbAA==.Midgeyfam:BAAALgAECgIJAgAAAA==.Midgeyzen:BAAALgAECgQJBAAAAA==.Mika:BAAALgAECgYJBgABLgAFFAMJBwAEALEQAA==.Mindi:BAAALgAECgMJAwAAAA==.Mizakina:BAAALgADCgYJCwAAAA==.Mizby:BAAALgADCgIJAwABLgADCgMJAwABAAAAAA==.Mizry:BAAALgADCgMJAwAAAA==.',
Mo='Moardotsnow:BAABLgAECn8oAAMRAAkJ4SSPJwABAgARAAUJ9iSPJwABAgASAAQJviQ6DAAsAQAAAA==.Moby:BAAALgAECgUJDQAAAA==.Moistmender:BAAALgAECgYJCwAAAA==.Monktyson:BAACLgAFFH8KAAITAAUJzxD/EABTAQATAAUJzxD/EABTAQAuAAQKfxQAAhMABwn5HxkPAEkCABMABwn5HxkPAEkCAAAA.Moosaki:BAAALgAECgkJCQABLgAECgkJLAAQAMIhAA==.Mortui:BAAALgADCgQJBgABLgAFFAYJJAAMACsXAA==.Mous:BAAALgADCgMJAwAAAA==.',
Mu='Muffasah:BAAALgAECgEJAQAAAA==.Munchkinn:BAAALgADCgYJBgAAAA==.Murbella:BAAALgADCgEJAQABLgAECgYJDgABAAAAAA==.Murridan:BAABLgAECn8gAAIbAAkJxiGUCQA7AwAbAAkJxiGUCQA7AwAAAA==.',
My='Mykaela:BAAALgAECgQJBAAAAA==.Myraela:BAAALgAECgQJBAABLgAECggJGQAJACMgAA==.',
['Më']='Mëow:BAAALgAECgYJEQAAAA==.',
Na='Narrath:BAAALgAECgMJBQAAAA==.Nayalaah:BAAALgAECgQJBAAAAA==.',
Ne='Nellybearwl:BAAALgADCgYJBgAAAA==.Nerfherder:BAAALgAECgQJBAAAAA==.Nexes:BAAALgADCgcJEgAAAA==.',
Ni='Nicotinee:BAAALgAECgMJAwAAAA==.Nightbané:BAAALgAECgIJAwAAAA==.Nirina:BAABLgAECn8ZAAIWAAYJ0wcUewDoAAAWAAYJ0wcUewDoAAAAAA==.Nixie:BAAALgAECgYJBgAAAA==.',
No='Nojaw:BAAALgADCgcJBwAAAA==.Noraeri:BAAALgAECgYJBgABLgAECgkJIAAIAKoXAA==.Notdicey:BAAALgAECgIJAwABLgAFFAMJCQAdAJsRAA==.Notstephen:BAAALgAECgEJAQAAAA==.Novo:BAAALgAECgYJCwAAAA==.',
Nu='Nukefury:BAABLgAECn8aAAIOAAYJZyR0GgBAAgAOAAYJZyR0GgBAAgABLgAECgcJFAAdAPkVAA==.',
Nw='Nwalliance:BAAALgADCgIJAgAAAA==.',
Od='Oddstriker:BAAALgADCgYJAwAAAA==.',
Ol='Oliveoil:BAAALgADCgEJAQAAAA==.',
Om='Omnidh:BAACLgAFFH8TAAIbAAUJNRfAIgA+AQAbAAUJNRfAIgA+AQAuAAQKfyQAAhsACQlQIKwPAAEDABsACQlQIKwPAAEDAAAA.Omnihead:BAAALgADCgYJBgAAAA==.',
On='Onepavo:BAAALgAECgEJAQAAAA==.Onlybakshots:BAAALgAECgYJBgAAAA==.',
Op='Oppose:BAAALgAECgYJDAAAAA==.',
Or='Orestes:BAAALgAFFAEJAQAAAA==.Orexion:BAAALgAECgQJBAAAAA==.Ormagöden:BAABLgAECn8oAAInAAkJMRSMAwBPAgAnAAkJMRSMAwBPAgAAAA==.',
Oz='Ozzpoxzo:BAAALgADCgcJDgAAAA==.',
Pa='Palladean:BAABLgAECn8eAAIDAAcJnBGiZQBZAQADAAcJnBGiZQBZAQAAAA==.Pandemic:BAAALgAECgMJAwAAAA==.Parabow:BAAALgAECgMJAwAAAA==.Parador:BAAALgAECgIJAQABLgAECgMJAwABAAAAAA==.Pastasauce:BAABLgAECn8VAAIDAAcJFwubhwBrAQADAAcJFwubhwBrAQAAAA==.',
Pc='Pcpmlsd:BAAALgADCgkJDAAAAA==.',
Pe='Penelohpe:BAAALgAECgcJCgABLgAECggJIwAKAMIhAA==.Penwork:BAAALgAECgcJBwAAAA==.Penz:BAAALgAECgYJBgAAAA==.Perrian:BAAALgADCgMJBAAAAA==.',
Ph='Phamine:BAAALgAECgMJAwAAAA==.Philex:BAEALgAECgYJBwABLgAFFAUJFAARAIMjAA==.Phoon:BAECLgAFFH8UAAIRAAUJgyOWEgCVAQARAAUJgyOWEgCVAQAuAAQKfyEABBEACAmqHkMdAKYCABEACAmqHkMdAKYCABIAAglGGVVJAJIAACYAAQkAAKAqAEoAAAAA.Phøenixbane:BAABLgAECn8YAAIDAAcJNhsFOQDWAQADAAcJNhsFOQDWAQAAAA==.',
Pi='Pita:BAAALgAECgcJCwAAAA==.Pitaya:BAAALgAECgcJEwAAAA==.',
Pl='Plaguefist:BAAALgAECgkJEQAAAA==.Plata:BAAALgAECgQJBQAAAA==.Plikxy:BAAALgADCgkJCQAAAA==.',
Po='Pocketmage:BAAALgAECgQJBQAAAA==.',
Pr='Premonitions:BAABLgAECn8fAAINAAgJVBQLKQDAAQANAAgJVBQLKQDAAQAAAA==.Premune:BAABLgAECn84AAQGAAkJ6x/oCQCmAgAGAAkJ6x/oCQCmAgAUAAgJ+RBsEQBVAQADAAIJOgioGwFjAAAAAA==.Prion:BAACLgAFFH8IAAIbAAMJNwtbRADPAAAbAAMJNwtbRADPAAAuAAQKfxQAAhsACAkkFBc8AIoBABsACAkkFBc8AIoBAAAA.',
Ps='Psycs:BAAALgAECgYJDgAAAA==.',
Pu='Pulga:BAAALgADCgIJAgAAAA==.Pull:BAAALgADCgcJCQABLgAFFAQJCQAIAE0gAA==.Purplemage:BAAALgAECgkJCgAAAA==.',
Pw='Pwincess:BAAALgADCgMJAwAAAA==.',
['Pú']='Púre:BAAALgAECgIJAgAAAA==.',
Qu='Quigly:BAAALgAECgYJCgAAAA==.Quìts:BAABLgAECn8mAAMRAAgJRB1CMADYAQARAAgJqhtCMADYAQASAAMJzRdTGwCQAAAAAA==.Quíts:BAAALgADCgEJAQABLgAECggJJgARAEQdAA==.',
Ra='Ragingtauren:BAAALgAECgEJAQAAAA==.Rainbowdots:BAAALgAECgcJDgAAAA==.Raine:BAACLgAFFH8bAAINAAcJDxQrAgBGAgANAAcJDxQrAgBGAgAuAAQKfxsAAw0ACAkWHysfACQCAA0ACAkWHysfACQCAA4ABAkKGWlVAPAAAAAA.Raistlain:BAAALgAECgQJBAAAAA==.Raistlin:BAABLgAECn8fAAMlAAkJwRbtDAD0AQAlAAkJwRbtDAD0AQAbAAEJywOo8AAiAAAAAA==.Ralfio:BAABLgAECn8nAAIfAAgJZCM0AgAYAwAfAAgJZCM0AgAYAwAAAA==.Ralfiosky:BAAALgAECgcJCAABLgAECggJJwAfAGQjAA==.Ramennoodlez:BAAALgADCggJDgAAAA==.Rat:BAAALgAFFAIJAgAAAA==.Ratren:BAAALgADCgQJAwAAAA==.Ravalyn:BAAALgADCgkJCgAAAA==.Raynith:BAABLgAECn8nAAQhAAkJCRu5CgAaAgAhAAcJ4h+5CgAaAgAiAAcJTxhIGgCeAQAoAAgJwxHIEABqAQAAAA==.',
Re='Readycheck:BAABLgAECn8aAAIoAAgJyw8CFQA0AQAoAAgJyw8CFQA0AQAAAA==.Reckalossi:BAAALgAECgkJAQABLgAFFAMJCAADANMFAA==.Redcows:BAAALgADCggJFAAAAA==.Redeemed:BAAALgADCgEJAQAAAA==.Reikon:BAABLgAECn8iAAIDAAgJzB2SMAD2AQADAAgJzB2SMAD2AQAAAA==.Remulous:BAABLgAECn8VAAIWAAcJyQiSdQD2AAAWAAcJyQiSdQD2AAAAAA==.Revelaen:BAACLgAFFH8KAAIYAAQJBxJOGwAlAQAYAAQJBxJOGwAlAQAuAAQKfyMAAxgACQlxHQ0JAOcCABgACQlxHQ0JAOcCABoABQlYBowoANwAAAAA.',
Ri='Rick:BAACLgAFFH8UAAMWAAUJ3CP9BgCgAQAWAAUJ3CP9BgCgAQAXAAEJXBoLJQBUAAAuAAQKfykAAxcACAnQI+QJAAUDABcACAlpI+QJAAUDABYACAm+H2ETAG0CAAAA.Rickers:BAAALgAECgMJAwABLgAFFAUJFAAWANwjAA==.',
Ro='Roarz:BAAALgADCgkJCQAAAA==.Rollthebones:BAAALgADCgMJAwAAAA==.Roman:BAABLgAECn8eAAMGAAYJayUSDQB2AgAGAAYJayUSDQB2AgADAAQJnRkyrQAoAQABLgAFFAQJCgAfAKAlAA==.Roust:BAAALgAECgUJBQABLgAFFAQJCQAIAE0gAA==.',
Ru='Runinfear:BAAALgADCgYJBgAAAA==.',
Sa='Saba:BAAALgAECgMJBAAAAA==.Saephora:BAABLgAECn8XAAIIAAcJtQP0yQC3AAAIAAcJtQP0yQC3AAAAAA==.Saerea:BAACLgAFFH8FAAILAAIJKh4ZfwCoAAALAAIJKh4ZfwCoAAAuAAQKfyUAAgsACAn+H4YhADwCAAsACAn+H4YhADwCAAAA.Sahhm:BAAALgAECgQJEAAAAA==.Salali:BAAALgAECgQJBwAAAA==.Samael:BAAALgAECgMJBgABLgAFFAQJCgAPAMQSAA==.Sammel:BAABLgAECn8ZAAMgAAgJ9BhXFABNAgAgAAgJ9BhXFABNAgAVAAEJCRGqVQAyAAAAAA==.Sandmanslim:BAAALgAECgUJBQAAAA==.Sathreina:BAABLgAECn8oAAIDAAkJRBbZKwAJAgADAAkJRBbZKwAJAgAAAA==.Sawbones:BAAALgADCggJCQAAAA==.',
Sc='Scaries:BAABLgAECn8XAAIFAAkJKRtoEgCAAgAFAAkJKRtoEgCAAgAAAA==.Scootzmcgee:BAAALgAECgUJCgAAAA==.',
Se='Sekii:BAEALgAECgQJBAABLgAFFAUJFAARAIMjAA==.Sekimaru:BAACLgAFFH8MAAIQAAQJjxHKEABBAQAQAAQJjxHKEABBAQAuAAQKfzIAAxAACQnXGl4GAIQCABAACQnXGl4GAIQCAA8AAQmnB3sgAC8AAAAA.Selok:BAAALgAFFAEJAgAAAA==.',
Sh='Shaddik:BAAALgAECgQJBgABLgAECggJEAABAAAAAA==.Shadowisbad:BAAALgAECgkJEwAAAA==.Shadpriest:BAAALgAECggJEAAAAA==.Shaeledoran:BAACLgAFFH8JAAILAAQJJQ+JRQAtAQALAAQJJQ+JRQAtAQAuAAQKfzgAAgsACQnWH+wcANICAAsACQnWH+wcANICAAAA.Shamaneggs:BAAALgAECgMJAwAAAA==.Shamatroxx:BAACLgAFFH8kAAIMAAYJKxcrAQCkAQAMAAYJKxcrAQCkAQAuAAQKfyoAAgwACQmIHRcDAJMCAAwACQmIHRcDAJMCAAAA.Shampomaster:BAAALgADCgMJAwAAAA==.Shieetz:BAAALgAECgYJEQAAAA==.Shlomie:BAAALgADCggJGgAAAA==.Shlomiel:BAAALgADCgEJAQAAAA==.Shlomieo:BAAALgADCgkJFwAAAA==.Shocknasty:BAAALgAECgEJAQAAAA==.Shorttemper:BAAALgADCgkJDQAAAA==.Shänk:BAABLgAECn8UAAMPAAYJ2wowEQDNAAAPAAQJiQkwEQDNAAAQAAQJ0AqmUQCeAAAAAA==.',
Si='Sibirica:BAAALgADCgEJAQAAAA==.Siena:BAAALgAECgYJDAAAAA==.Silith:BAAALgAECgQJBQAAAA==.Silre:BAAALgAECgYJEAAAAA==.Silverfangg:BAAALgADCgkJEQAAAA==.Sinergy:BAABLgAECn8UAAIRAAYJIh8zRAD/AQARAAYJIh8zRAD/AQAAAA==.Siz:BAAALgAECgYJCAAAAA==.',
Sk='Skiddlebutt:BAAALgADCgMJAgAAAA==.Skirmish:BAAALgAECgQJBwAAAA==.Skyray:BAAALgADCgUJBQAAAA==.',
Sl='Slappeepries:BAAALgADCgEJAQABLgAECgkJCgABAAAAAA==.Slappeey:BAAALgAECggJCgABLgAECgkJCgABAAAAAA==.',
Sn='Snapbean:BAAALgADCgEJAQAAAA==.Snarls:BAAALgAECgIJAgABLgAECggJJwAfAGQjAA==.Snaxx:BAAALgAECgMJBgABLgAECgYJDAABAAAAAA==.Snorunt:BAAALgAECgYJEAAAAA==.Snuudle:BAACLgAFFH8OAAMLAAMJViBIJgD9AAALAAMJViBIJgD9AAAnAAEJsBXpDwBPAAAuAAQKf00AAwsACQklJaoHAAQDAAsACQlZJKoHAAQDACcACAnOJDwBAN8CAAAA.',
So='Solokills:BAAALgAECgcJDwAAAA==.Soulreaperqt:BAAALgAECgMJAwABLgAECgUJCwABAAAAAA==.Soundtrack:BAAALgADCgEJAQAAAA==.',
Sp='Spaceman:BAAALgAECgQJBwABLgAFFAQJDAAVADoMAA==.',
Sq='Sqlpal:BAABLgAECn8cAAMbAAcJox60LwA9AgAbAAcJox60LwA9AgAlAAQJOB77PgAAAQAAAA==.Squirrels:BAABLgAECn8iAAMFAAcJWwoJLwANAQAFAAcJWwoJLwANAQATAAQJuwXsUgCGAAAAAA==.Squirtstorm:BAABLgAECn8pAAINAAgJTiEOCADnAgANAAgJTiEOCADnAgAAAA==.Squirtz:BAAALgADCgUJBAAAAA==.',
Sr='Srgntsnoop:BAAALgADCgUJBQAAAA==.',
St='Stabmywood:BAABLgAECn8sAAMQAAkJwiGDBQCYAgAQAAkJwiGDBQCYAgAcAAEJNxYvFwA+AAAAAA==.Sthella:BAAALgADCgMJAwABLgAECgUJDQABAAAAAA==.Stompy:BAAALgADCgkJEAABLgAFFAQJEQAgAM0PAA==.Storienn:BAAALgAECggJEQAAAA==.Stormßlessed:BAAALgADCgUJBQAAAA==.Strokemyhorn:BAAALgAECgQJBQAAAA==.',
Su='Subarashii:BAAALgAECgEJAQABLgAECgYJEQABAAAAAA==.Suküna:BAACLgAFFH8JAAIbAAMJthZMPADpAAAbAAMJthZMPADpAAAuAAQKfzAAAhsACQkQISkZAL0CABsACQkQISkZAL0CAAAA.Sunglo:BAAALgADCgYJBgAAAA==.Surefire:BAAALgAECgEJAQAAAA==.',
Sw='Swaption:BAACLgAFFH8HAAINAAMJgyWxFQBGAQANAAMJgyWxFQBGAQAuAAQKfyQAAg0ACAnjJCAMAL8CAA0ACAnjJCAMAL8CAAAA.Swolebane:BAAALgADCgUJBQAAAA==.',
Sy='Sybaü:BAAALgAECgYJDAAAAA==.Synchronize:BAABLgAECn8YAAILAAcJPRSEeQCRAQALAAcJPRSEeQCRAQAAAA==.Syrelia:BAABLgAECn8tAAIIAAkJJxVINQACAgAIAAkJJxVINQACAgAAAA==.',
Ta='Takèda:BAABLgAECn8ZAAIjAAYJdhyIEQCrAQAjAAYJdhyIEQCrAQAAAA==.Taldain:BAAALgAECgYJCwAAAA==.Talonstrykz:BAAALgAECggJEQAAAA==.Tankdeesnuts:BAABLgAECn8sAAIKAAYJzAhNKACoAAAKAAYJzAhNKACoAAAAAA==.Tashalle:BAAALgAECgEJAQABLgAECggJJAAVAOweAA==.Tauloe:BAABLgAECn8WAAIOAAYJvQlmQwDNAAAOAAYJvQlmQwDNAAAAAA==.Tayna:BAAALgAECgYJBgAAAA==.',
Te='Teejaydh:BAAALgADCgEJAQAAAA==.Tellamon:BAABLgAECn8aAAIDAAgJrhPMVACCAQADAAgJrhPMVACCAQAAAA==.Tetanus:BAAALgAECgQJBwABLgAECgYJEQABAAAAAA==.Teyassha:BAAALgAECgEJAwAAAA==.',
Th='Thomo:BAABLgAECn8bAAMWAAgJ8wY4WQA9AQAWAAgJlQY4WQA9AQAjAAYJ2gSgHAAMAQAAAA==.Throatfist:BAAALgAFFAIJBAABLgAFFAYJFQAbAFAeAA==.Throme:BAAALgADCgEJAQAAAA==.Thunk:BAACLgAFFH8JAAIOAAMJPRfdDQAMAQAOAAMJPRfdDQAMAQAuAAQKfyYAAg4ACQmXJfUDAGADAA4ACQmXJfUDAGADAAAA.',
Ti='Timdawg:BAAALgAECgYJDQABLgAECgUJEwABAAAAAA==.',
Tj='Tjkrollsaway:BAAALgAECgIJAgAAAA==.',
To='Tomotostein:BAACLgAFFH8HAAIDAAMJPgx2QgDmAAADAAMJPgx2QgDmAAAuAAQKfywAAgMACQlBH3YKAN8CAAMACQlBH3YKAN8CAAAA.Tonobaggins:BAAALgADCggJCAAAAA==.Toothluss:BAAALgADCgMJAgAAAA==.Totemnutz:BAAALgAECgEJAQABLgAECgYJFAATAGMVAA==.',
Tr='Tradrael:BAAALgAECgEJAQAAAA==.Tristîtia:BAAALgAFFAEJAQAAAA==.',
Ts='Tsume:BAABLgAECn8UAAIWAAYJzhgUTABjAQAWAAYJzhgUTABjAQAAAA==.',
Tu='Tumlek:BAAALgAECgIJAgAAAA==.Tunobuffpapi:BAAALgAFFAIJAgAAAA==.',
Ty='Tyrinn:BAAALgAECggJDwAAAA==.Tyv:BAABLgAECn8xAAMeAAkJBBa/AQAxAgAeAAkJBBa/AQAxAgAIAAUJjQbazQCwAAAAAA==.',
Ur='Urä:BAAALgAECgIJAgAAAA==.',
Va='Vainatetosix:BAAALgAECgQJCAAAAA==.Valindra:BAAALgAECgUJCQAAAA==.Vallodon:BAABLgAECn8hAAIIAAkJ6SArIwBSAgAIAAkJ6SArIwBSAgAAAA==.Valyndra:BAAALgAECgYJCAAAAA==.Vanquizsher:BAAALgAECgIJAgAAAA==.Vanwolfy:BAABLgAECn8WAAIKAAcJlQncHgDtAAAKAAcJlQncHgDtAAAAAA==.',
Ve='Velanthris:BAAALgAECgMJBQABLgAECgYJCAABAAAAAA==.Velectran:BAABLgAECn8eAAIDAAcJiBKYaABTAQADAAcJiBKYaABTAQABLgAECgkJLQAIACcVAA==.',
Vi='Vilgehkfrúna:BAAALgAECgEJAQAAAA==.Virdreth:BAAALgAECgEJAQAAAA==.Vish:BAAALgAECgUJBgAAAA==.',
Vo='Voidsauce:BAAALgAECgEJAQAAAA==.Vortash:BAAALgADCgcJCAAAAA==.',
Vy='Vynle:BAAALgAECgQJBgAAAA==.Vyrthos:BAAALgADCgkJCQABLgAFFAMJCAAIABMDAA==.',
['Vä']='Vämpira:BAAALgAECgYJCQAAAA==.',
Wa='Warheimer:BAAALgAECgEJAQAAAA==.Warrgodx:BAAALgAECgYJEwAAAA==.Wartroxx:BAAALgAECgQJBAABLgAFFAYJJAAMACsXAA==.',
We='Wengja:BAABLgAECn8gAAQTAAcJryULBwDqAgATAAcJryULBwDqAgAFAAEJ9QSVjgAnAAAZAAEJAACmiQAlAAAAAA==.',
Wh='Wheri:BAAALgADCggJCAABLgAECgkJJAAkABgbAA==.Whoknows:BAAALgAECgYJDgAAAA==.',
Wo='Wolfchef:BAAALgAECgYJDAAAAA==.Woodkin:BAAALgAECgUJEQAAAA==.',
Wr='Wrongwookie:BAABLgAECn8iAAIOAAkJxR2mCAAIAwAOAAkJxR2mCAAIAwAAAA==.',
Wy='Wyrmbreaker:BAAALgAECgMJBgAAAA==.',
Xi='Xiak:BAAALgADCgYJBgABLgAECgkJJwAhAAkbAA==.',
Ya='Yako:BAAALgAECgIJAgAAAA==.',
Ye='Yereka:BAAALgADCgQJBAAAAA==.',
Yi='Yinshai:BAABLgAECn8XAAMNAAgJnhf+IQDrAQANAAgJnhf+IQDrAQAOAAEJxwJshwAgAAAAAA==.',
Yo='Yoomesbonds:BAAALgAFFAEJAQAAAA==.Youtube:BAACLgAFFH8nAAMYAAgJzSKjAAD2AgAYAAgJzSKjAAD2AgAaAAMJayGKAwAlAQAuAAQKfyIAAxoACQkrJVQDAOoCABoABwmsJVQDAOoCABgABwkIIo4oAEgBAAAA.Yoyohunty:BAAALgAECgEJAgAAAA==.Yozki:BAABLgAECn8cAAIIAAcJ5CDWQADYAQAIAAcJ5CDWQADYAQAAAA==.',
Yu='Yuuki:BAAALgAECgQJBQABLgAFFAQJCgAPAMQSAA==.Yuulia:BAABLgAECn8kAAMkAAkJGBslBgBQAgAkAAkJqRolBgBQAgAKAAYJeRhvGQCGAQAAAA==.',
Za='Zabada:BAAALgADCgkJHwAAAA==.Zaee:BAAALgAECgIJBAABLgAFFAMJBQANACcMAA==.Zariee:BAAALgAECgcJEgAAAA==.',
Ze='Zemsen:BAACLgAFFH8IAAIIAAMJEwMGMgDgAAAIAAMJEwMGMgDgAAAuAAQKfzAAAwgACQmgGOY8AIQCAAgACQmgGOY8AIQCAB4AAgneBcAZAEoAAAAA.Zenyea:BAAALgAECgQJBAABLgAFFAQJEQAgAM0PAA==.Zetta:BAACLgAFFH8RAAIgAAQJzQ+VDwA8AQAgAAQJzQ+VDwA8AQAuAAQKfysAAiAACQmbH+sMALUCACAACQmbH+sMALUCAAAA.',
Zo='Zoktavir:BAAALgADCgEJAQAAAA==.Zoltan:BAABLgAECn8VAAIIAAYJnQve2QA9AQAIAAYJnQve2QA9AQAAAA==.Zorin:BAAALgADCgcJDgAAAA==.',
Zy='Zyndrael:BAABLgAECn8jAAIDAAgJQRs9KAAYAgADAAgJQRs9KAAYAgAAAA==.',
['Zâ']='Zâgs:BAAALgADCgYJCAAAAA==.',
['Êl']='Êlytz:BAAALgAECggJEAAAAA==.',
['ßl']='ßlue:BAACLgAFFH8FAAIFAAQJHxCLGQAXAQAFAAQJHxCLGQAXAQAuAAQKf0kABAUACAlHH8AMACwCAAUACAlHH8AMACwCABMABAnsG54tADcBABkAAQksDG1uADQAAAAA.',
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
