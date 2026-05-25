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

local lookup = {'Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Blood','Mage-Frost','Hunter-BeastMastery','Druid-Restoration','Paladin-Protection','Priest-Holy','DemonHunter-Devourer','Druid-Balance','Druid-Feral','Priest-Shadow','Warrior-Fury','Warrior-Protection','DemonHunter-Vengeance','Hunter-Marksmanship','Hunter-Survival','Mage-Arcane','DemonHunter-Havoc','Monk-Windwalker','Paladin-Retribution','Paladin-Holy','DeathKnight-Frost','Warlock-Destruction','Warrior-Arms','Evoker-Augmentation','Evoker-Devastation','Warlock-Demonology','Shaman-Restoration','Druid-Guardian','Shaman-Elemental','Priest-Discipline','Rogue-Subtlety','Rogue-Assassination','Monk-Mistweaver','Monk-Brewmaster','Rogue-Outlaw','Warlock-Affliction','Evoker-Preservation','Mage-Fire','Shaman-Enhancement',}
local provider = {region='US',realm='Malygos',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aakkulay:BAAALgAECgEJAgABLgAECgUJDQABAAAAAA==.',
Ab='Absofsteels:BAABLgAECn8eAAMCAAYJyBngcgBYAQACAAYJyBngcgBYAQADAAEJ2guAUQAlAAAAAA==.',
Ac='Acaric:BAABLgAECn8sAAIEAAkJLwU8mwAoAQAEAAkJLwU8mwAoAQAAAA==.Ache:BAAALgAFFAMJBAAAAA==.',
Ad='Adriel:BAAALgAECgYJCQAAAA==.Adrielon:BAAALgADCgYJCgAAAA==.Adøra:BAABLgAECn8dAAIFAAkJRBaDIgA2AgAFAAkJRBaDIgA2AgAAAA==.',
Ae='Aelanesh:BAAALgADCggJDQAAAA==.',
Ai='Aircann:BAAALgADCgMJAwAAAA==.Aireola:BAAALgADCgcJBwAAAA==.',
Ak='Akairo:BAAALgAECgcJCwABLgAECgkJGgAGAOYeAA==.Akata:BAAALgAECgYJAgAAAA==.',
Al='Alcaholic:BAAALgAECgEJAQABLgAECgkJMgAHADMgAA==.Alchemist:BAAALgADCgkJGgAAAA==.Alidor:BAAALgAECggJEgAAAA==.Alistair:BAAALgAECgEJAwAAAA==.Allixis:BAAALgADCgMJAwAAAA==.Alluriel:BAAALgAECgQJCgAAAA==.Altharoth:BAAALgAECgQJCwAAAA==.',
Am='Amira:BAACLgAFFH8aAAIIAAUJbCT4AgAHAgAIAAUJbCT4AgAHAgAuAAQKfyUAAggACAmsJWoCAEUDAAgACAmsJWoCAEUDAAAA.Amorillis:BAAALgADCgcJDQAAAA==.Amphitrite:BAAALgADCgEJAQAAAA==.',
An='Anteiku:BAAALgAECgIJAwAAAA==.Anthiva:BAABLgAECn8YAAIJAAgJkhALUABzAQAJAAgJkhALUABzAQAAAA==.',
Ar='Arauial:BAABLgAECn8UAAIIAAgJlx7fCgCSAgAIAAgJlx7fCgCSAgAAAA==.Arcos:BAAALgADCgkJCQAAAA==.Aribella:BAACLgAFFH8LAAIFAAQJeA0WNwAJAQAFAAQJeA0WNwAJAQAuAAQKfykAAgUACAlmGbYgAEECAAUACAlmGbYgAEECAAAA.Arizann:BAABLgAECn8mAAQGAAgJPhzxFgBtAgAGAAgJPhzxFgBtAgAKAAMJ5gyYYwBaAAALAAEJyAs6PQAzAAAAAA==.Arobotpr:BAABLgAECn85AAIMAAkJdRnUDQBUAgAMAAkJdRnUDQBUAgAAAA==.Artpandalay:BAAALgAECgQJBQAAAA==.',
As='Asima:BAAALgAECgQJBQAAAA==.Astaren:BAAALgAECgUJEQAAAA==.Asuran:BAACLgAFFH8GAAINAAMJYRhvJQDnAAANAAMJYRhvJQDnAAAuAAQKfxsAAw4ABwkzJPsIAEQCAA4ABwl6I/sIAEQCAA0ABglbH7ozAFUBAAAA.',
At='Atem:BAAALgAECgQJCwAAAA==.',
Au='Aulinn:BAAALgAECgIJAgAAAA==.Aurelianus:BAAALgAECgcJEwAAAA==.',
Av='Avalanche:BAAALgAECgUJCQAAAA==.',
Ax='Axegrunion:BAAALgADCgEJAQAAAA==.',
Az='Azaris:BAABLgAECn85AAIMAAkJBRlmDwA/AgAMAAkJBRlmDwA/AgAAAA==.',
Ba='Baelrog:BAAALgAECgYJDgAAAA==.Bananaslamma:BAAALgADCgMJBQAAAA==.Bandalar:BAABLgAECn8dAAMJAAkJBBLrRwDUAQAJAAkJBBLrRwDUAQAPAAIJQgrmLAAsAAAAAA==.Baranina:BAACLgAFFH8RAAMFAAYJgCHHBwAnAQAFAAMJ2iHHBwAnAQAQAAQJix6gEgDyAAAuAAQKfygABBAACAnTI4IOAM4CABAACAkgIoIOAM4CAAUABQmOHws2ANYBABEAAwkuIVcbAB8BAAAA.Barricaded:BAAALgAECggJCgAAAA==.Bashems:BAAALgADCgcJCQABLgAECgMJCQABAAAAAA==.Battosi:BAAALgADCgIJAgAAAA==.',
Be='Bealzebuub:BAAALgAECgUJDAAAAA==.Bearpaws:BAAALgADCgQJBAAAAA==.Beastums:BAABLgAECn85AAIRAAkJlxk9DQA3AgARAAkJlxk9DQA3AgAAAA==.Benji:BAEBLgAECn8YAAMEAAgJCxgmYgCeAQAEAAgJCxgmYgCeAQASAAEJeQYuIgAhAAAAAA==.',
Bi='Biggiecat:BAAALgADCgYJBgABLgAECgUJEQABAAAAAA==.Bigload:BAAALgADCgEJAQAAAA==.Bigunc:BAAALgAECgQJBgAAAA==.Bihgnuts:BAAALgAECgQJBgAAAA==.Bittybubble:BAAALgAECgEJAQAAAA==.',
Bl='Blazinitup:BAAALgADCgQJCQAAAA==.Blimey:BAAALgAECggJBgAAAA==.Blindaf:BAABLgAECn8cAAITAAYJvw1PKwDpAAATAAYJvw1PKwDpAAAAAA==.Blindcauze:BAAALgADCgEJAQAAAA==.Blindmonk:BAABLgAECn8aAAIUAAcJqhHZMgAPAQAUAAcJqhHZMgAPAQAAAA==.Blite:BAAALgADCgkJHAAAAA==.Bloodlòck:BAAALgADCgUJCgAAAA==.Bloodmary:BAABLgAECn8eAAMVAAkJZQUtiwA5AQAVAAkJZQUtiwA5AQAWAAQJQAevcgCxAAAAAA==.Bloombriar:BAAALgAECgEJAQAAAA==.Bloöm:BAACLgAFFH8PAAMGAAQJFQvaPwCRAAAGAAMJXgLaPwCRAAAKAAMJtwFiMwB0AAAuAAQKfx0AAwYACAl9D5I5AI0BAAYACAl9D5I5AI0BAAoAAQl/EbBzADcAAAAA.Blueeyearch:BAABLgAECn8UAAMQAAYJzx11EwABAQAFAAUJLCOdYQBVAQAQAAUJoRJ1EwABAQAAAA==.',
Bo='Bo:BAAALgAECgcJBwAAAA==.Bolgan:BAAALgAECgMJCAABLgAECggJIwAUAC8aAA==.Bonedecay:BAAALgAECgEJAwAAAA==.Bonerina:BAAALgAECgEJAQAAAA==.Boomadk:BAACLgAFFH8PAAICAAQJgBd6QwA+AQACAAQJgBd6QwA+AQAuAAQKfyAAAwIACQkPIkUfAMYCAAIACQmZIUUfAMYCABcABwmfH9gCAHsCAAAA.Boomapriest:BAAALgAECgcJCwAAAA==.Boosh:BAAALgAECgIJAgAAAA==.Booshler:BAAALgAECgUJCgAAAA==.Booshlia:BAABLgAECn8XAAIJAAkJDhfxJAAcAgAJAAkJDhfxJAAcAgAAAA==.Booshly:BAAALgAECgUJBQAAAA==.Bootstrapbil:BAAALgADCgkJCgAAAA==.Bowjoemojo:BAAALgADCgIJAgAAAA==.Bowsho:BAAALgAECgQJBQAAAA==.',
Br='Bradburn:BAAALgAECgQJCAAAAA==.Brasserz:BAABLgAECn8WAAIRAAgJrw/BGQCyAQARAAgJrw/BGQCyAQAAAA==.Brewswillis:BAAALgADCgYJBgAAAA==.Brice:BAAALgAECgUJEQAAAA==.Briochebun:BAABLgAECn8fAAIVAAkJSBzkIACnAgAVAAkJSBzkIACnAgAAAA==.',
Bu='Bubblewrap:BAAALgADCggJCAABLgAECgYJGwAGAG4fAA==.Bustin:BAABLgAECn8aAAIVAAgJzh49JQBOAgAVAAgJzh49JQBOAgAAAA==.',
Bw='Bwangifer:BAABLgAECn85AAIPAAkJUxmNBABLAgAPAAkJUxmNBABLAgAAAA==.',
['Bë']='Bëcky:BAAALgAFFAMJAwAAAA==.',
Ca='Caerus:BAAALgADCgYJDAABLgAECggJKwARAAwgAA==.Caitriona:BAAALgADCgMJAwABLgADCgUJBwABAAAAAA==.Cannala:BAAALgADCgkJGAAAAA==.Cargae:BAAALgADCggJDQAAAA==.Cassios:BAABLgAECn8jAAIUAAgJLxrzEQAOAgAUAAgJLxrzEQAOAgAAAA==.',
Ce='Celathel:BAAALgAECgYJDgAAAA==.Cellysia:BAABLgAECn8uAAMIAAkJvwUuLQA+AQAIAAkJvwUuLQA+AQAMAAcJZQJsTQCpAAAAAA==.Celsìus:BAABLgAECn8XAAIEAAYJbhOg1QBEAQAEAAYJbhOg1QBEAQAAAA==.Ceramyth:BAAALgAECgUJDwAAAA==.Ceres:BAABLgAECn85AAIYAAkJYR12AQCrAgAYAAkJYR12AQCrAgAAAA==.Cesara:BAABLgAECn88AAMMAAkJRyMDAwAhAwAMAAkJRyMDAwAhAwAIAAIJYQQkfwAzAAAAAA==.',
Ch='Chaahck:BAAALgAECgMJAwAAAA==.Chal:BAAALgAECgUJBwAAAA==.Chbribs:BAAALgAECgYJEAAAAA==.Chichimounki:BAAALgADCgUJBQAAAA==.Chiptewth:BAAALgADCgEJAQAAAA==.',
Ci='Cinderella:BAABLgAECn8xAAIEAAgJwSPcGACqAgAEAAgJwSPcGACqAgAAAA==.',
Cl='Clumsey:BAAALgADCgEJAQAAAA==.',
Co='Cocoshan:BAAALgAECgcJDgAAAA==.Columbina:BAACLgAFFH8ZAAIJAAYJEREBIABpAQAJAAYJEREBIABpAQAuAAQKfxoAAgkABwmgGbdEAOEBAAkABwmgGbdEAOEBAAAA.Comma:BAABLgAECn8UAAIOAAcJFxKwHABjAQAOAAcJFxKwHABjAQAAAA==.Cooperhowerd:BAAALgADCgkJHAAAAA==.Corn:BAABLgAECn8ZAAIVAAcJ5hXtZgCCAQAVAAcJ5hXtZgCCAQAAAA==.Couremese:BAAALgADCgYJBgAAAA==.',
Cr='Crackmonger:BAACLgAFFH8FAAIZAAMJ7xgeFQDxAAAZAAMJ7xgeFQDxAAAuAAQKfz0AAxkACQmNIqYCAPMCABkACQmNIqYCAPMCAA4AAgk1EIs7AFsAAAAA.Crackundead:BAAALgAECgYJCwAAAA==.Cravens:BAAALgAECgYJCwAAAA==.Craze:BAAALgADCgUJBQAAAA==.',
Cy='Cyphr:BAABLgAECn85AAIGAAkJDB/2BwAeAwAGAAkJDB/2BwAeAwAAAA==.',
['Cë']='Cërbërus:BAAALgAECgQJBQAAAA==.',
Da='Dacs:BAAALgAECgQJEwAAAA==.Daen:BAAALgADCgcJCgAAAA==.Dagadus:BAAALgAECgMJBAAAAA==.Daggergarnet:BAAALgADCgYJBgAAAA==.Dajango:BAAALgAECgYJDQAAAA==.Damerot:BAABLgAECn8VAAMNAAUJ3hDnSgDxAAANAAUJ3hDnSgDxAAAOAAEJngJjTAAjAAAAAA==.Dandity:BAAALgAECgcJCwAAAA==.Dangerous:BAAALgAECgEJAQAAAA==.Dangi:BAAALgADCgMJAwAAAA==.Dansharo:BAAALgAECgYJCAAAAA==.Darnel:BAAALgADCgQJBAAAAA==.',
De='Deadbeard:BAACLgAFFH8KAAICAAQJox5gJQCCAQACAAQJox5gJQCCAQAuAAQKfyQAAgIACAncJYELAPICAAIACAncJYELAPICAAAA.Deathknut:BAAALgADCggJCQAAAA==.Deathmethods:BAAALgAFFAEJAQAAAA==.Deathviix:BAAALgADCgQJBgAAAA==.Dekillerty:BAAALgADCgYJCQAAAA==.Deli:BAAALgAECggJDAAAAA==.Delphina:BAAALgADCgQJAwAAAA==.Demini:BAAALgAECgYJCgAAAA==.Demisê:BAABLgAECn8iAAMCAAkJ9hc+KAA+AgACAAkJFhc+KAA+AgADAAUJhhHdLQC+AAAAAA==.Demonessa:BAAALgAECgcJEQAAAA==.Demonslyer:BAAALgAECggJCAAAAA==.Derbygirl:BAAALgADCgYJBgAAAA==.Dermus:BAAALgADCgEJAQAAAA==.Deserter:BAABLgAECn8jAAMaAAgJjhSOKQB4AQAaAAgJjhSOKQB4AQAbAAYJtQz0HgA3AQAAAA==.Desso:BAABLgAECn8lAAIUAAgJVxXUGQC3AQAUAAgJVxXUGQC3AQAAAA==.Devilskin:BAAALgAECgYJCwAAAA==.',
Di='Dihhdevil:BAAALgAECgIJBAABLgAECgUJCgABAAAAAA==.Dillinger:BAABLgAECn8bAAILAAYJDxdDEwBPAQALAAYJDxdDEwBPAQAAAA==.Dingodgaf:BAABLgAECn8fAAIVAAcJHgaPtwDxAAAVAAcJHgaPtwDxAAAAAA==.',
Do='Doomsdae:BAAALgAECgQJCgAAAA==.Doomstir:BAABLgAECn8hAAIEAAYJJxGtnwAiAQAEAAYJJxGtnwAiAQAAAA==.',
Dr='Dragonmynutz:BAAALgAECgYJBwAAAA==.Draknarok:BAABLgAECn8gAAICAAgJRRq/MgAQAgACAAgJRRq/MgAQAgAAAA==.Dranius:BAACLgAFFH8IAAIEAAQJxQe8VQAZAQAEAAQJxQe8VQAZAQAuAAQKfxcAAgQACAnHEiSJAMABAAQACAnHEiSJAMABAAAA.Drayeda:BAAALgADCgMJAwAAAA==.Dreadlord:BAAALgADCgEJAQAAAA==.Dreamclaw:BAABLgAECn8UAAILAAYJ2ge0IgC5AAALAAYJ2ge0IgC5AAAAAA==.Dredda:BAAALgADCgEJAQAAAA==.Drendar:BAAALgADCgUJBQAAAA==.Drippindots:BAACLgAFFH8GAAIcAAMJ+xEaWwDhAAAcAAMJ+xEaWwDhAAAuAAQKfykAAhwACQmTGpIeAFQCABwACQmTGpIeAFQCAAAA.Driztette:BAABLgAECn8YAAIdAAYJWCLTIAAdAgAdAAYJWCLTIAAdAgAAAA==.Drnewport:BAAALgADCgkJDwAAAA==.Drock:BAAALgADCgIJAgAAAA==.Druidbearpig:BAAALgAECgEJAQABLgAECgkJJgAcANARAA==.Drunkfuq:BAAALgAECgEJAQAAAA==.Drustor:BAAALgAECgYJBgAAAA==.Drystine:BAABLgAECn8mAAITAAgJfx4kDAAtAgATAAgJfx4kDAAtAgAAAA==.',
Du='Dubber:BAAALgADCggJCQAAAA==.',
['Dí']='Dín:BAAALgAECgIJAgAAAA==.',
Ed='Edd:BAAALgADCgYJBgAAAA==.',
Ee='Eedeeweewee:BAAALgADCgkJEwAAAA==.Eevee:BAAALgAECgYJCgAAAA==.',
Ei='Eillaura:BAABLgAECn8lAAIIAAkJLBt7CAC/AgAIAAkJLBt7CAC/AgAAAA==.',
El='Elemag:BAAALgAECgEJAQAAAA==.Elipsis:BAABLgAECn8dAAIIAAkJqRNbLACVAQAIAAkJqRNbLACVAQAAAA==.Ellyn:BAAALgAECgYJBgAAAA==.Elm:BAABLgAECn8uAAQGAAgJIRYhNQCjAQAGAAgJIRYhNQCjAQAKAAgJ4BFIIgCJAQAeAAEJ5BNeLwA4AAAAAA==.Elyas:BAAALgADCgEJAQAAAA==.Elybella:BAACLgAFFH8FAAIFAAMJ7gpuTwC7AAAFAAMJ7gpuTwC7AAAuAAQKfxoAAgUACAlgGAUvAPUBAAUACAlgGAUvAPUBAAAA.Elyenora:BAAALgAECgQJBAABLgAFFAMJBQAFAO4KAA==.Elyssaelyend:BAAALgAECgYJDAABLgAECggJIwAGADYbAA==.',
Em='Emanon:BAAALgAECgQJBQAAAA==.Emberion:BAAALgADCggJCAAAAA==.Emmental:BAABLgAECn8XAAIfAAYJiBIURQDvAAAfAAYJiBIURQDvAAAAAA==.',
En='Endload:BAAALgADCgEJAQAAAA==.Enquea:BAAALgAECgYJEQAAAA==.Enricco:BAAALgAECgYJCwAAAA==.',
Er='Ereko:BAABLgAECn8gAAIFAAgJ4w+DTACPAQAFAAgJ4w+DTACPAQAAAA==.Erythorbic:BAABLgAECn8hAAMcAAgJ8xyEIQBEAgAcAAcJfRyEIQBEAgAYAAMJQyCiLwD8AAAAAA==.',
Es='Estralage:BAAALgAECgUJCgAAAA==.',
Ev='Evictor:BAAALgAECgQJBgABLgAECgkJGAAUAPMYAA==.',
Ex='Exileelfsam:BAABLgAECn8uAAIRAAkJVwsUFwDMAQARAAkJVwsUFwDMAQAAAA==.',
Fa='Fallenrose:BAAALgAECgEJAQAAAA==.Fallensk:BAAALgADCgIJAgAAAA==.Faranth:BAAALgAECgIJAwAAAA==.Fargenstines:BAAALgADCgMJAwAAAA==.Fatass:BAAALgAECgMJAwAAAA==.Fatherrick:BAAALgAECgQJBAAAAA==.Faîle:BAACLgAFFH8hAAMgAAUJpBajEQCgAQAgAAUJpBajEQCgAQAMAAEJ1QHZMAA7AAAuAAQKfyoAAyAACAlEHycIAL0CACAACAlEHycIAL0CAAgABgkhCDNKABABAAAA.',
Fe='Feer:BAAALgAECgUJCwAAAA==.Feldron:BAABLgAECn8cAAMhAAkJZh3ACgDmAgAhAAgJGR7ACgDmAgAiAAEJgxjzHQA9AAAAAA==.Felshatter:BAABLgAECn8SAAIJAAYJcwkilQDMAAAJAAYJcwkilQDMAAAAAA==.Feltigress:BAABLgAECn8wAAILAAkJnCKIAQAOAwALAAkJnCKIAQAOAwAAAA==.Fendag:BAAALgADCgYJEQAAAA==.',
Ff='Ffugher:BAAALgADCgYJDAAAAA==.Ffugme:BAABLgAECn8rAAIHAAgJdBHoEgBsAQAHAAgJdBHoEgBsAQAAAA==.Ffugoff:BAAALgAECgcJBwAAAA==.Ffugtard:BAAALgAECgcJEAAAAA==.Ffugyou:BAAALgADCgQJBAAAAA==.',
Fi='Fingerfister:BAAALgAECgQJBAABLgAECgYJBwABAAAAAA==.Finnian:BAABLgAECn8tAAIWAAkJ+BuZDAChAgAWAAkJ+BuZDAChAgAAAA==.Fio:BAACLgAFFH8KAAIjAAQJ0B6xFABiAQAjAAQJ0B6xFABiAQAuAAQKfyQAAyMACAn3JLMCAFoDACMACAn3JLMCAFoDABQAAQlJG0JwAFEAAAAA.Firiona:BAABLgAECn8XAAMgAAYJ2RTlJAB4AQAgAAYJ2RTlJAB4AQAMAAEJ8wkIcQAxAAAAAA==.',
Fl='Flashferment:BAABLgAECn8ZAAIkAAgJzRfVHgCQAQAkAAgJzRfVHgCQAQAAAA==.Flinn:BAABLgAECn8dAAIeAAkJBh65BACZAgAeAAkJBh65BACZAgAAAA==.Flowers:BAABLgAECn8sAAMJAAgJJR8WGQBiAgAJAAgJJR8WGQBiAgATAAIJexkMPACMAAAAAA==.Fläva:BAAALgAECgUJDAAAAA==.',
Fo='Forkinyou:BAAALgAECgQJBAAAAA==.',
Fr='Fracture:BAAALgADCgYJBgAAAA==.Fresca:BAAALgADCgEJAQAAAA==.Fridgerollin:BAAALgADCggJFgAAAA==.Frifrah:BAAALgAECgMJBAAAAA==.Frosht:BAABLgAECn8wAAIEAAkJBBpVLQBGAgAEAAkJBBpVLQBGAgAAAA==.',
Fu='Furysbubble:BAAALgAECgEJAQAAAA==.Furyswarm:BAAALgAECgkJAQAAAA==.',
['Fö']='Föx:BAAALgADCgEJAQABLgAECgYJDwABAAAAAA==.',
Ga='Gafocalypse:BAAALgAECgcJDAAAAA==.Garddidit:BAAALgADCgUJBQABLgAECggJHQAPAOQbAA==.',
Gl='Glonor:BAAALgAECgQJBgAAAA==.',
Go='Goldberg:BAAALgADCgcJDQAAAA==.Goopmaster:BAAALgADCgUJBQAAAA==.Goovs:BAAALgAECgEJAQAAAA==.',
Gr='Grabmytusk:BAAALgADCgcJBwAAAA==.Gramthyr:BAAALgADCgkJHAAAAA==.Grep:BAAALgAECgIJAgAAAA==.Greygor:BAAALgAECgIJAgAAAA==.Grotok:BAABLgAECn8UAAMCAAgJVwqrfQBCAQACAAgJVwqrfQBCAQAXAAEJAABxFgA3AAAAAA==.',
Gu='Guacamole:BAAALgAECgUJBQAAAA==.Gub:BAAALgAECgMJAwAAAA==.Gumer:BAAALgAECgYJBwAAAA==.Gurgatron:BAAALgAECgcJCAABLgAECgcJFAAOAAIUAA==.',
Ha='Halraku:BAAALgADCgEJAQAAAA==.Halsin:BAAALgADCgQJBAAAAA==.Halygos:BAAALgAECgYJCQAAAA==.Halygosa:BAAALgAECgEJAQAAAA==.Hasklaufien:BAAALgAECgIJBgAAAA==.',
He='Herpecluster:BAAALgAECgcJBgAAAA==.',
Hi='Hinderberg:BAAALgAECgcJBwAAAA==.',
Ho='Holyraz:BAAALgADCgMJAwAAAA==.Holystrikes:BAAALgAECgQJBQAAAA==.',
Hu='Hugulin:BAABLgAECn8ZAAIFAAcJ3QaxbwAZAQAFAAcJ3QaxbwAZAQAAAA==.',
Ic='Icedsoul:BAABLgAECn8YAAIEAAYJNgd8wADrAAAEAAYJNgd8wADrAAAAAA==.Icee:BAAALgADCgcJCgAAAA==.',
Ig='Iggey:BAABLgAECn8wAAIZAAkJjByHBQCNAgAZAAkJjByHBQCNAgAAAA==.',
Ik='Ikkaku:BAAALgAECgEJAQAAAA==.',
Il='Ilandras:BAABLgAECn8rAAIJAAgJbQ78VgBeAQAJAAgJbQ78VgBeAQAAAA==.Illadus:BAABLgAECn8bAAIJAAgJfAbGfgD6AAAJAAgJfAbGfgD6AAAAAA==.Illed:BAAALgADCgcJBwAAAA==.',
In='Indra:BAAALgAECgcJCQAAAA==.Intoxicated:BAABLgAECn8fAAIUAAcJ5AoLNAAJAQAUAAcJ5AoLNAAJAQAAAA==.',
Io='Ione:BAAALgADCgcJBAAAAA==.',
Ir='Iranna:BAACLgAFFH8UAAQlAAYJpx11AQCXAQAlAAUJhht1AQCXAQAiAAQJ0hocAwBfAQAhAAIJiBQVLQBRAAAuAAQKfzEABCIACAmQJT4CAJwCACUACAlwI0YBAN8CACIABwn2ID4CAJwCACEABwkkICwQAAgCAAAA.Irondihh:BAAALgAECgMJAwABLgAECgUJCgABAAAAAA==.',
Iu='Iudi:BAAALgAECgQJBAABLgAECgkJGgAGAOYeAA==.',
Iy='Iyasu:BAAALgADCgQJBAAAAA==.',
Ja='Jachan:BAAALgADCgkJDwAAAA==.Jackblãck:BAAALgAECgQJBQABLgAECgkJKwACAG0gAA==.Janaki:BAABLgAECn8eAAMGAAgJsxmSGgBNAgAGAAgJsxmSGgBNAgAKAAQJghbCRADHAAAAAA==.',
Je='Jestêr:BAAALgAECggJCAABLgAFFAUJIQAgAKQWAA==.',
Jo='Joenutter:BAAALgAECgMJBgAAAA==.Joia:BAAALgADCgQJBAAAAA==.Jonnyquestt:BAABLgAECn9AAAIVAAkJHBS/OgD4AQAVAAkJHBS/OgD4AQAAAA==.',
Ju='Juicie:BAAALgAECgUJCgAAAA==.Junrage:BAAALgADCgMJAwABLgAFFAUJFQANABkeAA==.Junrush:BAAALgAECggJDgABLgAFFAUJFQANABkeAA==.',
['Jè']='Jèstèr:BAAALgAFFAEJAQABLgAFFAUJIQAgAKQWAA==.',
Ka='Kalea:BAAALgAECgIJBwAAAA==.Kalecgo:BAAALgAECgMJAwABLgAECggJFAADAEIaAA==.Kanaezz:BAAALgADCggJCAAAAA==.Kat:BAABLgAECn8YAAMkAAkJZhRgFgDYAQAkAAcJNBpgFgDYAQAjAAcJZgarTwCUAAAAAA==.Katsuko:BAABLgAECn8xAAIDAAkJfhhwDAAWAgADAAkJfhhwDAAWAgAAAA==.Kattnirra:BAABLgAECn8oAAIFAAkJ9g8tMwDmAQAFAAkJ9g8tMwDmAQAAAA==.Katze:BAABLgAECn9HAAIFAAkJ8xhPGQBmAgAFAAkJ8xhPGQBmAgAAAA==.Kaylé:BAAALgAECgYJDAAAAA==.',
Ke='Keannor:BAAALgADCgMJAwAAAA==.Keco:BAAALgADCgcJBwAAAA==.Keepper:BAABLgAECn8oAAIcAAkJ8hAMRgCyAQAcAAkJ8hAMRgCyAQAAAA==.Kelaatun:BAAALgAECgEJAgAAAA==.Kennan:BAAALgADCgIJAgAAAA==.Kenslynn:BAABLgAECn8WAAIIAAgJRRD7KwBFAQAIAAgJRRD7KwBFAQAAAA==.Ketheric:BAAALgAECgMJBgAAAA==.',
Ki='Killahaseo:BAAALgAECgYJBgABLgAECggJIgAaAE0ZAA==.Killmoedee:BAABLgAECn8yAAIHAAkJMyBtAgDiAgAHAAkJMyBtAgDiAgAAAA==.Kitwryn:BAAALgADCgUJBQAAAA==.',
Kk='Kkaell:BAAALgAECgQJCgABLgAECgYJBwABAAAAAA==.',
Kl='Klexios:BAAALgAECgUJEQAAAA==.',
Ko='Koopa:BAAALgAECgQJBQAAAA==.Korbandallas:BAAALgAECgQJBwAAAA==.',
Kr='Kracious:BAAALgAECgQJBAAAAA==.Kraulhoof:BAAALgAECgEJAQABLgAECgYJBwABAAAAAA==.Krispy:BAAALgAECggJDAAAAA==.Krymson:BAAALgAECgYJBwAAAA==.',
Ku='Kui:BAABLgAECn85AAIkAAkJcx3pBgCsAgAkAAkJcx3pBgCsAgAAAA==.Kurtcobrain:BAAALgAECgYJCQAAAA==.',
['Kö']='Köz:BAAALgAECgQJBAAAAA==.',
La='Laetri:BAABLgAECn8jAAIJAAkJ2RT7OQC+AQAJAAkJ2RT7OQC+AQAAAA==.Lasttok:BAABLgAECn8eAAMLAAgJuyDABQBiAgALAAgJAR7ABQBiAgAKAAIJvBM6WgB3AAAAAA==.Laylene:BAAALgAECgcJEAAAAA==.Lazloo:BAABLgAECn8sAAMNAAkJcSVWAQBcAwANAAkJbSVWAQBcAwAZAAcJOhwFEgCtAQAAAA==.Lazymidget:BAABLgAECn8eAAIQAAcJJh1VLQDFAQAQAAcJJh1VLQDFAQAAAA==.',
Le='Leaana:BAAALgADCgUJBQAAAA==.Leftÿ:BAAALgAECgIJAgABLgAECgkJOwARAAoUAA==.Legindkiller:BAAALgADCgkJHAAAAA==.Lenie:BAAALgADCgYJBgABLgAFFAgJIgAGAIofAA==.',
Li='Lightace:BAABLgAECn8ZAAIVAAcJSgdzqgAFAQAVAAcJSgdzqgAFAQAAAA==.Lilyia:BAAALgADCgcJDAAAAA==.Linkkil:BAABLgAECn8XAAIRAAkJVB59BQC2AgARAAkJVB59BQC2AgAAAA==.',
Lo='Loastotem:BAAALgADCgcJBwAAAA==.Lobos:BAABLgAECn8eAAIcAAgJMQfDfQAoAQAcAAgJMQfDfQAoAQAAAA==.Lokni:BAAALgAECgYJBwAAAA==.Lostdraco:BAAALgAECgcJEwAAAA==.Lostdream:BAABLgAECn8YAAMJAAcJVQNbuQCFAAAJAAYJAANbuQCFAAATAAIJKwMFYQAmAAAAAA==.Loun:BAABLgAECn8gAAIkAAgJuBYwFwDPAQAkAAgJuBYwFwDPAQAAAA==.Lowku:BAAALgAECgEJAQAAAA==.Lowrise:BAAALgADCgkJCgAAAA==.',
Lu='Luciellia:BAAALgAECgEJAQAAAA==.Luiss:BAAALgAECgMJAwAAAA==.Luken:BAAALgADCggJFgAAAA==.Luminara:BAAALgADCgcJDAAAAA==.Luminism:BAAALgADCgYJCAABLgAECgYJGQAjAFAgAA==.Luteil:BAAALgADCgMJAwAAAA==.Luvlycruelty:BAAALgADCgUJBwAAAA==.',
Ly='Lyn:BAEBLgAECn88AAIkAAkJPCZ0AAB3AwAkAAkJPCZ0AAB3AwAAAA==.',
Ma='Mackenziiee:BAABLgAECn8yAAIFAAkJ6B1eDgC4AgAFAAkJ6B1eDgC4AgAAAA==.Mackthyra:BAAALgADCgcJBwABLgAECgkJMgAFAOgdAA==.Madglowup:BAABLgAECn8cAAIlAAYJ3iGQBQDjAQAlAAYJ3iGQBQDjAQAAAA==.Magicbunga:BAAALgADCgIJAgAAAA==.Magicwater:BAABLgAECn8gAAIEAAkJhxxUJQBqAgAEAAkJhxxUJQBqAgAAAA==.Magtaki:BAAALgAECgkJCAAAAA==.Magyar:BAAALgAECgUJBQAAAA==.Mainline:BAAALgAECggJCAAAAA==.Maizepriest:BAABLgAECn8sAAIMAAgJzCDrCgB/AgAMAAgJzCDrCgB/AgAAAA==.Mannysaf:BAABLgAECn8dAAINAAgJjg1AMQBhAQANAAgJjg1AMQBhAQAAAA==.Manter:BAAALgADCgIJAgAAAA==.Mariota:BAAALgAECgQJAwABLgAFFAcJEgAEACIYAA==.Marus:BAAALgADCgMJAwAAAA==.',
Me='Mechalia:BAAALgADCgQJBAAAAA==.Meerkat:BAAALgAECgEJAQABLgAECgYJBgABAAAAAA==.Mellowblink:BAABLgAECn8oAAIEAAgJWBZSSgDhAQAEAAgJWBZSSgDhAQAAAA==.Mellowlink:BAABLgAECn8mAAIhAAcJGhvcGACqAQAhAAcJGhvcGACqAQAAAA==.Melorian:BAAALgADCgkJEAAAAA==.Memeñtomori:BAAALgAECggJDQAAAA==.Menara:BAAALgAECgYJDAAAAA==.Metaviix:BAAALgAECgQJBAAAAA==.',
Mi='Micromancer:BAAALgADCgMJAwAAAA==.Midnightmage:BAAALgAECgUJBgAAAA==.Migglet:BAAALgAECgIJAgAAAA==.Milkyboy:BAAALgADCgQJBAAAAA==.Millhi:BAAALgAECgcJBwAAAA==.Mimi:BAACLgAFFH8fAAQQAAkJdyJDAQCJAgAQAAgJpCBDAQCJAgAFAAQJBiXbJQA5AQARAAMJmiO9GgDMAAAuAAQKfzYABBAACQmCJu0DAGUDABAACAkCJu0DAGUDABEABwnIJcAJAGoCAAUABglLJB5OAIoBAAAA.Mintyice:BAAALgAECgcJBgAAAA==.Miramage:BAAALgAECgQJCQABLgAECgkJMgAhAMIXAA==.Miravus:BAABLgAECn8yAAMhAAkJwhfmFQDIAQAhAAkJJhfmFQDIAQAiAAUJSRKgDQAuAQAAAA==.Mirlanda:BAABLgAECn8YAAIiAAYJLAXrEgDUAAAiAAYJLAXrEgDUAAAAAA==.Misttie:BAAALgAECggJEwABLgAECgkJHQAIAKkTAA==.',
Mo='Monkerick:BAAALgAECgYJDAAAAA==.Moonana:BAAALgADCgIJAgAAAA==.Morber:BAAALgAECgQJBQAAAA==.Morphingtime:BAAALgADCgIJAgAAAA==.Mowte:BAAALgADCgkJHAAAAA==.',
Mu='Murkoobi:BAAALgAECgIJAgAAAA==.Mursk:BAAALgAECgMJAwAAAA==.',
My='Myhoovesrhot:BAAALgAECgIJAgAAAA==.Mystrial:BAAALgAECgEJAwAAAA==.Mystáke:BAAALgAFFAEJAQAAAA==.',
['Mä']='Mäble:BAAALgADCgYJBwAAAA==.',
['Mê']='Mêrcy:BAAALgADCgYJBgAAAA==.',
['Mò']='Mòus:BAAALgAECgYJEwAAAA==.',
['Mó']='Mómo:BAAALgAECgcJCQAAAA==.Móus:BAAALgAECgUJCwABLgAECgYJEwABAAAAAA==.',
Na='Narcissus:BAAALgADCggJFgAAAA==.Narivia:BAAALgAECgUJBgABLgAFFAUJIQAgAKQWAA==.Naro:BAAALgAECgcJDAABLgAECggJMQAEAMEjAA==.Nathadon:BAAALgAECgEJAQAAAA==.Nathalin:BAABLgAECn8kAAQeAAcJvBeaIAAEAQAeAAUJtheaIAAEAQAKAAYJMRAiOQD8AAALAAUJIhAyIADeAAAAAA==.Nazari:BAAALgAECgEJAQAAAA==.',
Ne='Necrotis:BAAALgADCgkJHAAAAA==.Nectarion:BAAALgAECgEJAQAAAA==.Neftearii:BAAALgADCgEJAQAAAA==.Nevelia:BAABLgAECn86AAMIAAkJUCQQAQClAwAIAAkJUCQQAQClAwAMAAYJzxoQNwA1AQAAAA==.Neytholy:BAAALgAECgcJDAAAAA==.Nezukô:BAAALgAECgcJCAAAAA==.',
Ni='Nienna:BAAALgAECgIJAgAAAA==.Nikkisan:BAAALgADCgYJBgAAAA==.Nitalan:BAAALgAECgIJAgAAAA==.Nithenseth:BAAALgADCggJDQAAAA==.Nixk:BAAALgAECgYJDwAAAA==.',
No='Noavail:BAAALgADCgMJAwAAAA==.Noixi:BAAALgAECgQJDQAAAA==.Noraldrys:BAAALgADCgcJDQAAAA==.Noralyne:BAAALgAECgYJDAAAAA==.Noras:BAABLgAECn8YAAIUAAkJ8xjIDQBCAgAUAAkJ8xjIDQBCAgAAAA==.Noraxia:BAAALgADCgkJEAAAAA==.Nordicslayer:BAABLgAECn8lAAIZAAgJNBL7FQCDAQAZAAgJNBL7FQCDAQAAAA==.Notagnoblin:BAEBLgAFFH8HAAIDAAQJah3pFAABAQADAAQJah3pFAABAQABLgAFFAQJEAAkAC4mAA==.',
Ny='Nysonia:BAAALgAECgcJBwAAAA==.',
Ob='Obnyxion:BAABLgAECn8mAAIbAAkJGQ40CACOAQAbAAkJGQ40CACOAQAAAA==.',
Oc='Octuroun:BAAALgAECgcJEQAAAA==.',
Od='Oddsoul:BAAALgAECgUJDQAAAA==.',
Og='Ogrelurd:BAABLgAECn8XAAMZAAcJSSCFCQAsAgAZAAcJSSCFCQAsAgANAAQJGxhxUADdAAAAAA==.',
Oh='Ohlordy:BAAALgAECgcJEQAAAA==.',
Ol='Oliveia:BAAALgADCgcJCgAAAA==.',
Om='Omontanha:BAAALgAECgUJCQAAAA==.',
On='Oniryoshi:BAAALgAECgQJBAAAAA==.Onlyzugs:BAAALgADCgEJAgAAAA==.',
Op='Ophelia:BAACLgAFFH8IAAMmAAMJvRD2FgBPAAAcAAIJRxH8fACYAAAmAAEJqg/2FgBPAAAuAAQKfzwABBwACQnZIHwkADMCABwACAlmHHwkADMCACYABgmZIqwIAKcBABgAAQmmCJh0ADAAAAAA.',
Or='Orakwa:BAAALgAECgYJEwAAAA==.',
Ou='Outen:BAAALgAECgcJBwAAAA==.',
Oz='Ozzieliem:BAAALgAECgEJAQAAAA==.',
Pa='Pakleader:BAAALgADCgIJAgAAAA==.Pallinda:BAABLgAECn8sAAMWAAkJBhg0GAAfAgAWAAgJaRc0GAAfAgAVAAkJkRIqRQDXAQAAAA==.Panakananama:BAAALgAECgcJDwAAAA==.Panz:BAABLgAECn8tAAMaAAgJOAofNAA5AQAaAAgJegkfNAA5AQAbAAEJIA6SIAA1AAAAAA==.Papablock:BAAALgADCgMJAwAAAA==.Papagrip:BAAALgAECgUJBQAAAA==.Papalock:BAAALgADCgYJBgABLgAECgUJBQABAAAAAA==.Papiperkins:BAAALgAECgEJAQAAAA==.Pappyoblues:BAAALgAECgcJCAAAAA==.Papster:BAAALgADCgYJBgAAAA==.Parati:BAAALgAECgIJAgAAAA==.Paylot:BAAALgAECgMJBwAAAA==.Pazuzuu:BAAALgAECgEJAQABLgAECgkJJgAcANARAA==.',
Pe='Peachmangogt:BAAALgADCgUJBgAAAA==.Pendulum:BAAALgADCgkJCwAAAA==.Pendulumlaw:BAAALgAECggJDgAAAA==.Pennypacker:BAAALgAECgcJCwAAAA==.Personality:BAAALgADCggJCAAAAA==.Petmycat:BAABLgAECn8WAAMFAAYJcRCidgAjAQAFAAYJcRCidgAjAQAQAAUJVAhHHQChAAAAAA==.',
Ph='Phara:BAABLgAECn8aAAQMAAgJMwvVKQBaAQAMAAgJMwvVKQBaAQAgAAUJZgirNgDwAAAIAAIJlAFvfAA3AAAAAA==.Phenomenon:BAAALgADCgUJBQAAAA==.Phoel:BAAALgADCggJCQAAAA==.Phoopanchu:BAABLgAECn8iAAIjAAkJGRIyIADUAQAjAAkJGRIyIADUAQAAAA==.',
Pi='Pibble:BAAALgADCgMJAwAAAA==.Pinkbuns:BAABLgAECn8lAAIEAAgJnxfcSgDfAQAEAAgJnxfcSgDfAQAAAA==.Pirimus:BAAALgADCgEJAQAAAA==.',
Pn='Pneuma:BAABLgAECn8cAAIPAAYJzSOoBgD5AQAPAAYJzSOoBgD5AQAAAA==.',
Po='Pofella:BAAALgAECgMJAwAAAA==.Pokinsmot:BAAALgADCgYJCwAAAA==.Pollonius:BAAALgADCgIJAgAAAA==.Popsthyr:BAAALgADCgYJBgAAAA==.Popsy:BAABLgAECn8dAAIVAAgJABHvXgCUAQAVAAgJABHvXgCUAQAAAA==.',
Pr='Precarity:BAAALgAECgEJAQAAAA==.Prenton:BAABLgAECn8qAAINAAgJ7iAYDQB3AgANAAgJ7iAYDQB3AgAAAA==.Pretzel:BAAALgADCgUJBQABLgAFFAUJDAACANEjAA==.Prideflag:BAAALgAECgMJAwAAAA==.Primaldead:BAABLgAECn9IAAIcAAgJfBrzJAAxAgAcAAgJfBrzJAAxAgAAAA==.Profundity:BAAALgAECgYJDAAAAA==.',
Pu='Punchmyface:BAAALgADCgUJCAAAAA==.Puny:BAABLgAECn8rAAICAAkJbSBzDgDZAgACAAkJbSBzDgDZAgAAAA==.',
Qe='Qeini:BAABLgAECn8tAAIgAAgJgRluDwBMAgAgAAgJgRluDwBMAgAAAA==.',
Ra='Radrin:BAAALgAECgEJAQAAAA==.Rafoff:BAAALgAECgYJEAAAAA==.Rahll:BAAALgADCgkJHAAAAA==.Rancoramble:BAABLgAECn8XAAIDAAkJDQQbJwDsAAADAAkJDQQbJwDsAAAAAA==.Randis:BAABLgAECn8rAAMCAAgJ6g0xYwB+AQACAAgJ6g0xYwB+AQAXAAYJoQJ3HgCIAAAAAA==.Ranekk:BAAALgAECgEJAQAAAA==.Razglaive:BAAALgADCgYJBgAAAA==.Razhunt:BAAALgAECgUJCgAAAA==.Razonghoul:BAABLgAECn8+AAICAAkJyyHFDgDXAgACAAkJyyHFDgDXAgAAAA==.',
Re='Redheat:BAAALgADCgUJBQAAAA==.Redwyn:BAAALgADCgMJAwAAAA==.Reemonhunter:BAAALgAECgEJAgAAAA==.Regarded:BAAALgADCgcJBwAAAA==.Renge:BAAALgADCgEJAQAAAA==.Rengår:BAAALgAECgUJCwAAAA==.Renx:BAAALgAECgQJBQAAAA==.Reticent:BAAALgAECgYJDwAAAA==.Rexiis:BAABLgAECn8mAAMcAAkJ0BFEOADgAQAcAAkJ0BFEOADgAQAmAAEJAABdNAAzAAAAAA==.Reyth:BAAALgAECgYJDwAAAA==.',
Rh='Rhaul:BAAALgAECgEJAQAAAA==.Rhuby:BAAALgADCgkJDwAAAA==.Rhyl:BAABLgAECn8mAAIhAAcJKyG9EACcAgAhAAcJKyG9EACcAgAAAA==.',
Ri='Rimos:BAAALgAECgEJAQAAAA==.Ripcord:BAAALgADCggJDQAAAA==.Riptîde:BAABLgAECn8yAAIfAAkJXxCcIgCjAQAfAAkJXxCcIgCjAQAAAA==.',
Ro='Rockadin:BAABLgAECn8aAAIVAAYJQBQXmgAgAQAVAAYJQBQXmgAgAQAAAA==.Rodrick:BAAALgAECgIJAgAAAA==.Rosael:BAAALgAECgEJAQAAAA==.Roundhouse:BAAALgAECggJDwAAAA==.',
Ru='Rubbmytotems:BAAALgAECgYJEAAAAA==.Rulen:BAAALgADCgMJCQAAAA==.Ruleti:BAABLgAECn8qAAMFAAgJTRbNNgDXAQAFAAgJTRbNNgDXAQAQAAIJrQn8egBXAAAAAA==.Rumí:BAABLgAECn8gAAIJAAkJUAkFWwBTAQAJAAkJUAkFWwBTAQAAAA==.Russell:BAAALgADCgkJGQAAAA==.Rutgore:BAABLgAECn8vAAIhAAkJbh04CQBuAgAhAAkJbh04CQBuAgAAAA==.',
Rx='Rx:BAAALgAECgUJBQAAAA==.',
Sa='Sabado:BAAALgAECgQJDAAAAA==.Safewerd:BAEALgAECggJEwAAAA==.Saitáma:BAAALgADCgQJBAAAAA==.Samíra:BAAALgAECgMJBAAAAA==.Santapaws:BAAALgAECgMJAwAAAA==.Santrious:BAAALgAECgUJCgAAAA==.Saraceleste:BAAALgAECgEJAQAAAA==.Sarahfi:BAAALgAECgMJBAAAAA==.Saraisabella:BAAALgADCgMJAwAAAA==.Saralanna:BAAALgAECgYJEQAAAA==.Sarasophie:BAAALgADCgUJBQAAAA==.Sarcastrophe:BAAALgADCgMJAwAAAA==.Sarefina:BAAALgAECgcJEwAAAA==.Sathenazarke:BAACLgAFFH8OAAMbAAQJ3xxHAQB/AQAbAAQJ3xxHAQB/AQAnAAMJ0QXUGwCpAAAuAAQKfzUABBsACQnUIfwDACMCABsABwksIPwDACMCACcACAnkGNIRACECABoABwncGqEbAOsBAAEuAAUUBgkUACUApx0A.Saths:BAAALgADCgEJAQABLgAECggJEwABAAAAAA==.',
Sc='Schallue:BAABLgAECn8gAAIoAAgJkAgpBQBLAQAoAAgJkAgpBQBLAQAAAA==.Schism:BAAALgADCgkJJwAAAA==.Scoban:BAACLgAFFH8fAAIWAAYJFiRmBAAzAgAWAAYJFiRmBAAzAgAuAAQKfyoAAhYACAl4IQsOAKgCABYACAl4IQsOAKgCAAAA.Scylla:BAAALgAECgUJDAAAAA==.',
Se='Selithel:BAABLgAECn8XAAITAAgJ4Af2IwAdAQATAAgJ4Af2IwAdAQAAAA==.Seraphnite:BAAALgAECgUJCgABLgAECgQJBAABAAAAAA==.Serioussurv:BAAALgAECgUJCgAAAA==.Setsunachan:BAAALgADCgIJAgABLgAECgkJMQADAH4YAA==.',
Sh='Shadeebear:BAAALgADCgMJAwAAAA==.Shadowmander:BAABLgAECn8WAAQMAAcJtgbSSwCxAAAMAAYJowfSSwCxAAAgAAUJUQWVRwCmAAAIAAEJFgEWbQAaAAAAAA==.Shaeliana:BAAALgAECgQJDgAAAA==.Shalera:BAAALgAECgcJBwAAAA==.Shaohlin:BAAALgAECgUJCAAAAA==.Shaqfu:BAAALgADCgkJHAAAAA==.Shavemybush:BAAALgAECgEJAQAAAA==.Shields:BAAALgAECgkJCQAAAA==.Shiggyloo:BAAALgAECggJAQAAAA==.Shigure:BAABLgAECn8kAAIEAAkJLg1OUgDIAQAEAAkJLg1OUgDIAQAAAA==.Shivers:BAAALgAFFAEJAQAAAA==.Shnow:BAAALgAECgkJEwAAAA==.Sholin:BAABLgAECn8eAAIkAAgJ9h1HDABRAgAkAAgJ9h1HDABRAgAAAA==.Shomea:BAAALgAECgUJEQAAAA==.Shugz:BAAALgADCgkJHAAAAA==.Shumai:BAAALgAECgYJBwAAAA==.',
Si='Sikotick:BAABLgAECn8jAAIGAAgJmh5qEwCPAgAGAAgJmh5qEwCPAgAAAA==.Sikxbetrayer:BAAALgAECgcJDwAAAA==.Siliconista:BAACLgAFFH8IAAIEAAMJgyEyUwAhAQAEAAMJgyEyUwAhAQAuAAQKfzkAAgQACQkRIQ8TAM4CAAQACQkRIQ8TAM4CAAAA.Silverbolt:BAABLgAECn8YAAINAAcJ3Qy+PAAqAQANAAcJ3Qy+PAAqAQAAAA==.Simbelmyne:BAAALgAECgQJCAAAAA==.Sinderone:BAACLgAFFH8aAAIWAAYJuBCPDACqAQAWAAYJuBCPDACqAQAuAAQKf0AAAxYACQl/H/8FABADABYACQl/H/8FABADABUABQn9F9i9AOgAAAAA.',
Sk='Skaaduush:BAAALgAECgYJDAAAAA==.Skypaw:BAAALgAECgEJAwAAAA==.',
Sl='Slavon:BAABLgAECn87AAICAAkJwCBHDgDbAgACAAkJwCBHDgDbAgAAAA==.Sleepylune:BAAALgAECgMJBQAAAA==.Slippie:BAAALgADCgQJAgAAAA==.Sllew:BAABLgAECn8jAAICAAgJ0iFfHAB7AgACAAgJ0iFfHAB7AgAAAA==.Slothfu:BAAALgAECgEJAQAAAA==.Slèw:BAAALgAECgQJBAAAAA==.',
Sm='Smitestuff:BAAALgAECgYJDwAAAA==.Smoulder:BAAALgAECgYJCgAAAA==.',
Sn='Snigles:BAABLgAECn8eAAIiAAgJaBBbCAChAQAiAAgJaBBbCAChAQAAAA==.',
So='Sokrash:BAAALgADCgcJDQAAAA==.Somannita:BAAALgADCgcJBwAAAA==.Souei:BAAALgADCgEJAQABLgAECggJFAACAFcKAA==.Soulgiver:BAAALgAECgMJAwAAAA==.',
Sp='Spartos:BAAALgAECgYJEAAAAA==.Sposi:BAEBLgAECn8sAAIDAAgJaCEWCABvAgADAAgJaCEWCABvAgAAAA==.Spraynpray:BAAALgAECgYJCQAAAA==.',
Sr='Srimrithyu:BAAALgAECgEJAQAAAA==.',
Ss='Sselionn:BAABLgAECn8YAAMdAAYJ6Ar+egCnAAAdAAUJhQX+egCnAAAfAAUJ7AToYQCMAAAAAA==.',
St='Stabathaa:BAAALgAECgUJCQAAAA==.Stomps:BAABLgAECn8aAAINAAgJxxp7GgD2AQANAAgJxxp7GgD2AQAAAA==.',
Su='Subliminal:BAABLgAECn8WAAMhAAgJ8RJCJQDPAQAhAAgJ8RJCJQDPAQAlAAEJswxkHQAyAAAAAA==.Sumbtch:BAAALgAECgQJBAAAAA==.',
Sv='Svartalfar:BAAALgADCgMJAQAAAA==.',
Sy='Syravia:BAABLgAECn8dAAIVAAcJbgUHwQDjAAAVAAcJbgUHwQDjAAAAAA==.',
['Sé']='Séraphyne:BAAALgAECgYJDgAAAA==.',
Ta='Talarin:BAAALgAECgYJDgAAAA==.Tameka:BAAALgAECgQJBgAAAA==.Tardis:BAAALgAECgkJDAAAAA==.Tatersmonk:BAECLgAFFH8QAAIkAAQJLibCBwC7AQAkAAQJLibCBwC7AQAuAAQKfyMAAiQACQnpJLsDAFQDACQACQnpJLsDAFQDAAAA.Tavinrayn:BAAALgAECgcJDgAAAA==.Tazzar:BAABLgAECn85AAIaAAkJYQ+PHQDIAQAaAAkJYQ+PHQDIAQAAAA==.',
Td='Tdjin:BAAALgAECgYJCQAAAA==.',
Te='Teddygraham:BAAALgADCgcJCAAAAA==.Teera:BAAALgADCgEJAQABLgAECggJLgAGACEWAA==.Tekêsh:BAAALgAECgcJEwAAAA==.Telarin:BAABLgAECn8dAAQFAAgJJhkXTQCNAQAFAAcJ9RsXTQCNAQARAAcJCAtdKQAzAQAQAAEJuAOsOgAiAAAAAA==.Tentpoles:BAAALgADCgEJAQAAAA==.',
Th='Thandor:BAAALgAECgUJEQAAAA==.Thebigdawg:BAAALgAFFAMJAwAAAA==.Thehonored:BAAALgADCgcJBwAAAA==.Theladyboy:BAAALgAECgkJDwAAAA==.Thomss:BAAALgADCgQJCAAAAA==.Throhk:BAAALgAECgEJAQAAAA==.Thuliaga:BAAALgAECgIJAgAAAA==.',
Ti='Tiamut:BAAALgAECgMJAwAAAA==.Tieeny:BAAALgAECgEJAQAAAA==.Tigerliley:BAAALgAECgYJCgABLgAECgcJGwAMAEwSAA==.Tinneas:BAAALgADCgEJAQAAAA==.Titlepush:BAAALgAECgYJBgAAAA==.',
To='Tokenhealz:BAAALgAECgQJBAAAAA==.Tomie:BAAALgAECgEJAgAAAA==.Tomás:BAABLgAECn8dAAMdAAgJlxHSPgCBAQAdAAcJUBDSPgCBAQAfAAgJ4AwjMgBGAQAAAA==.Tonyhands:BAAALgADCgMJBgAAAA==.Tonyy:BAACLgAFFH8fAAIDAAUJ+h4RDgBFAQADAAUJ+h4RDgBFAQAuAAQKfzIAAgMACQnCIRUDADEDAAMACQnCIRUDADEDAAAA.Torstai:BAAALgAECgYJEAAAAA==.Totemthis:BAAALgADCgkJCQAAAA==.',
Tr='Trueshöt:BAABLgAECn8XAAMRAAgJlx8FDABIAgARAAgJXR4FDABIAgAQAAQJ1hzaQQBRAQAAAA==.',
Ts='Tserendolgor:BAABLgAECn8pAAQTAAgJCRweDAAtAgATAAgJCRweDAAtAgAJAAMJ9Q97qQCkAAAPAAEJTRUwKQBAAAAAAA==.',
Tu='Tuskfury:BAAALgADCgcJDQAAAA==.',
Tw='Twinight:BAAALgAECgEJAQABLgAECggJHQAfAFcWAA==.Twinsha:BAABLgAECn8dAAMfAAgJVxaFJACXAQAfAAgJVxaFJACXAQAdAAcJJwS1WQAhAQAAAA==.Twín:BAAALgADCgYJCAABLgAECggJHQAfAFcWAA==.',
Ty='Tyranastrasz:BAAALgADCgMJAwAAAA==.Tyrannis:BAAALgAECgIJAgAAAA==.Tyrasong:BAAALgAECgMJBgAAAA==.Tyresious:BAABLgAECn8bAAIVAAgJRyB/HQB2AgAVAAgJRyB/HQB2AgAAAA==.',
['Tà']='Tàric:BAAALgAECgEJAQAAAA==.',
Un='Unauma:BAACLgAFFH8NAAIGAAQJwgggOACyAAAGAAQJwgggOACyAAAuAAQKfxoAAwYACQknHFUSAJoCAAYACQknHFUSAJoCAB4AAgnbIJIsALYAAAEuAAUUBQkKAB0AeRIA.Undeadpanda:BAAALgAECgIJAgABLgAECgUJDQABAAAAAA==.Unholydk:BAAALgAECgYJEgAAAA==.',
Ut='Utherrex:BAAALgADCgMJAwABLgAECgkJJgAcANARAA==.',
Va='Vaa:BAAALgADCgcJEwAAAA==.Vahaghn:BAABLgAECn8wAAIZAAkJNyMXAgAOAwAZAAkJNyMXAgAOAwAAAA==.Valcerus:BAAALgAECgUJEQAAAA==.Valedus:BAABLgAECn8wAAIVAAkJWySpBQAwAwAVAAkJWySpBQAwAwAAAA==.Validrela:BAAALgADCgIJBAAAAA==.Vampirism:BAAALgAECgUJBwABLgAECgYJGQAjAFAgAA==.',
Ve='Veelete:BAAALgADCgkJEwABLgAECggJKAAWAMwbAA==.Veinyhawg:BAAALgAECgYJCQAAAA==.Velissena:BAAALgADCgIJAgABLgAECgkJOgAIAFAkAA==.Vespra:BAABLgAECn8/AAIdAAkJRyClBgAgAwAdAAkJRyClBgAgAwAAAA==.',
Vh='Vhas:BAAALgAECgkJEAAAAA==.Vhem:BAAALgAECgkJAwAAAA==.',
Vi='Viix:BAAALgAECgIJAgABLgAECgYJDAABAAAAAA==.Visage:BAAALgADCgQJBAAAAA==.',
Vo='Voidmommy:BAAALgADCgYJBgAAAA==.Voidweaver:BAAALgAECgUJBgAAAA==.Volcker:BAABLgAECn8rAAIHAAgJ7QcFHgD2AAAHAAgJ7QcFHgD2AAAAAA==.Voltashi:BAABLgAECn8tAAQkAAkJ5xTXEgD+AQAkAAkJ5xTXEgD+AQAjAAQJygnFdQBUAAAUAAEJBAt7gAAwAAAAAA==.Voltuk:BAABLgAECn8UAAQOAAcJAhT1FwBZAQAOAAcJPRP1FwBZAQAZAAQJGhNhNgC6AAANAAEJ7ggEjwAtAAAAAA==.Volus:BAAALgADCgUJBQAAAA==.Vorp:BAAALgADCgYJBgAAAA==.',
Vy='Vyniellas:BAAALgADCgYJBgABLgAECgkJIAAFAJweAA==.',
Wa='Wagyuboi:BAAALgAECgYJDQAAAA==.Wallypaly:BAABLgAECn8nAAMVAAgJDhazcgBoAQAVAAcJVxezcgBoAQAHAAUJ6RYCHQD/AAAAAA==.Walrustusk:BAAALgADCgYJCAAAAA==.Warbourne:BAAALgAECgIJAgAAAA==.Wariius:BAABLgAECn8yAAIWAAgJax1hDQCWAgAWAAgJax1hDQCWAgAAAA==.Warwarb:BAAALgADCgYJCwABLgAECgkJNwAcAA8cAA==.Waterliliy:BAABLgAECn8bAAIMAAcJTBL+MwAgAQAMAAcJTBL+MwAgAQAAAA==.',
Wh='Whatcrap:BAAALgAECgQJBAAAAA==.Whir:BAAALgADCgUJBQAAAA==.',
Wi='Windfurypie:BAAALgAECgkJBQAAAA==.',
Wo='Wolfbayin:BAAALgADCgYJCgAAAA==.Wolfbish:BAABLgAECn8gAAMFAAgJjhUaOQDPAQAFAAgJjhUaOQDPAQAQAAYJkQuLGgC4AAAAAA==.Wongidan:BAAALgAECgIJAgAAAA==.Woofee:BAAALgADCgQJBwAAAA==.Woxy:BAAALgADCgMJAwAAAA==.',
Wt='Wtfwipeitup:BAAALgAECgMJAwAAAA==.',
Xa='Xanather:BAAALgADCgcJBwABLgAECgUJEQABAAAAAA==.Xandrodron:BAAALgADCgUJBQAAAA==.',
Xe='Xelence:BAAALgAECgEJAQABLgAFFAMJBgAcAPsRAA==.Xenhaseo:BAABLgAECn8iAAIaAAgJTRnKGQDoAQAaAAgJTRnKGQDoAQAAAA==.',
Xh='Xhuri:BAAALgAECgIJBwAAAA==.',
Xi='Xilla:BAAALgAECgcJCAAAAA==.',
Xs='Xst:BAAALgADCgEJAQAAAA==.',
['Xë']='Xëna:BAABLgAECn8bAAIGAAYJbh94IgASAgAGAAYJbh94IgASAgAAAA==.',
Yo='Yorllik:BAAALgADCgcJHgAAAA==.Yougotwreckd:BAAALgAFFAEJAQAAAA==.',
Ys='Yserà:BAAALgAECgIJAgAAAA==.',
Yt='Yt:BAABLgAECn8aAAIJAAcJQxdnbAAlAQAJAAcJQxdnbAAlAQAAAA==.',
Za='Zaboomavoid:BAAALgADCgYJDAAAAA==.Zaes:BAABLgAECn8mAAIaAAkJJCGxCQCiAgAaAAkJJCGxCQCiAgAAAA==.Zaiene:BAAALgAECgIJAwABLgAECgYJDAABAAAAAA==.Zal:BAAALgADCggJEgAAAA==.Zarkhan:BAAALgAECgUJDQAAAA==.Zarulyn:BAAALgAECgYJCQAAAA==.Zavadin:BAAALgAECgYJCQAAAA==.',
Ze='Zeffy:BAABLgAECn8UAAMaAAgJ1wzEMABLAQAaAAcJwgzEMABLAQAbAAYJGAsyDwD2AAAAAA==.Zeneras:BAAALgAECgYJCgAAAA==.',
Zh='Zhorvan:BAABLgAECn8fAAMdAAgJMxScQgB2AQAdAAYJOBOcQgB2AQApAAgJrAaoFAAvAQAAAA==.',
Zi='Zigbis:BAAALgADCgYJBgAAAA==.Ziggleton:BAAALgADCgEJAQAAAA==.Zilstar:BAAALgAECgYJCgAAAA==.Zink:BAAALgADCgcJDgAAAA==.',
Zu='Zuginside:BAAALgADCgMJAwAAAA==.',
Zw='Zwolfe:BAAALgADCgQJBgAAAA==.',
Zy='Zya:BAAALgAECgEJAQAAAA==.',
['Âr']='Ârtëmïs:BAABLgAECn8xAAIFAAgJ7g6SVAB3AQAFAAgJ7g6SVAB3AQAAAA==.',
['Äc']='Äcid:BAABLgAECn8sAAIdAAkJ1xtdFgBqAgAdAAkJ1xtdFgBqAgAAAA==.',
['Åp']='Åpollo:BAABLgAFFH8GAAIjAAMJvhTlJADMAAAjAAMJvhTlJADMAAAAAA==.',
['Èa']='Èastçoast:BAAALgADCgcJGQAAAA==.',
['Êl']='Êlydala:BAAALgAECgYJBwAAAA==.',
['Ðð']='Ððå:BAAALgADCgEJAQAAAA==.',
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
