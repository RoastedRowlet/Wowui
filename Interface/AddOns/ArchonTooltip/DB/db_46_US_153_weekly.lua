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

local lookup = {'Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Blood','Mage-Frost','Hunter-BeastMastery','Druid-Restoration','Paladin-Protection','Priest-Holy','DemonHunter-Devourer','Druid-Balance','Druid-Feral','Priest-Shadow','Evoker-Preservation','Warrior-Fury','Warrior-Protection','DemonHunter-Vengeance','Hunter-Marksmanship','Hunter-Survival','Mage-Arcane','DemonHunter-Havoc','Monk-Windwalker','Paladin-Retribution','Paladin-Holy','DeathKnight-Frost','Warlock-Destruction','Warrior-Arms','Evoker-Augmentation','Evoker-Devastation','Warlock-Demonology','Shaman-Restoration','Rogue-Subtlety','Druid-Guardian','Shaman-Elemental','Priest-Discipline','Rogue-Assassination','Monk-Mistweaver','Monk-Brewmaster','Rogue-Outlaw','Warlock-Affliction','Mage-Fire','Shaman-Enhancement',}
local provider = {region='US',realm='Malygos',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aakkulay:BAAALgAECgEJAgABLgAECgUJEgABAAAAAA==.',
Ab='Absofsteels:BAABLgAECn8kAAMCAAYJyBmQegBZAQACAAYJyBmQegBZAQADAAEJ2gt1WAAlAAAAAA==.',
Ac='Acaric:BAABLgAECn81AAIEAAkJIwcteQBrAQAEAAkJIwcteQBrAQAAAA==.Ache:BAAALgAFFAMJBAAAAA==.',
Ad='Adriel:BAAALgAECgYJCQAAAA==.Adrielon:BAAALgADCgYJCgAAAA==.Adøra:BAABLgAECn8dAAIFAAkJRBaDIgA2AgAFAAkJRBaDIgA2AgAAAA==.',
Ae='Aelanesh:BAAALgADCggJDQAAAA==.',
Ai='Aircann:BAAALgADCgMJAwAAAA==.Aireola:BAAALgADCgcJBwAAAA==.',
Ak='Akairo:BAAALgAECgcJCwABLgAECgkJGgAGAOYeAA==.Akata:BAAALgAECgYJAgAAAA==.',
Al='Alcaholic:BAAALgAECgEJAQABLgAECgkJOAAHAKAgAA==.Alchemist:BAAALgADCgkJIAAAAA==.Alidor:BAAALgAECggJEgAAAA==.Alistair:BAAALgAECgEJAwAAAA==.Allixis:BAAALgADCgMJAwAAAA==.Alluriel:BAAALgAECgQJCwAAAA==.Alrianda:BAAALgAECgIJAgAAAA==.Altharoth:BAAALgAECgQJCwAAAA==.',
Am='Amira:BAACLgAFFH8aAAIIAAUJbCQ2BAD4AQAIAAUJbCQ2BAD4AQAuAAQKfyUAAggACAmsJWoCAEUDAAgACAmsJWoCAEUDAAAA.Amorillis:BAAALgADCgcJDQAAAA==.Amphitrite:BAAALgADCgEJAQAAAA==.',
An='Anteiku:BAAALgAECgIJAwAAAA==.Anthiva:BAABLgAECn8aAAIJAAkJHxBUQgCqAQAJAAkJHxBUQgCqAQAAAA==.',
Ar='Arauial:BAABLgAECn8VAAIIAAgJlx5dDACJAgAIAAgJlx5dDACJAgAAAA==.Arcos:BAAALgADCgkJCQAAAA==.Aribella:BAACLgAFFH8LAAIFAAQJeA0nQQAIAQAFAAQJeA0nQQAIAQAuAAQKfykAAgUACAlmGbYgAEECAAUACAlmGbYgAEECAAAA.Arizann:BAABLgAECn8yAAQGAAgJWh0DFgCFAgAGAAgJWh0DFgCFAgAKAAMJ5gzJagBaAAALAAEJyAsgRwAtAAAAAA==.Arobotpr:BAABLgAECn8/AAIMAAkJdRnuDgBOAgAMAAkJdRnuDgBOAgAAAA==.Arrenn:BAAALgADCggJCAAAAA==.Artpandalay:BAAALgAECgQJBQAAAA==.',
As='Asima:BAAALgAECgQJBgAAAA==.Astaren:BAABLgAECn8WAAINAAUJ2x7RDwC7AQANAAUJ2x7RDwC7AQAAAA==.Asuran:BAACLgAFFH8JAAIOAAQJtBrZEwBPAQAOAAQJtBrZEwBPAQAuAAQKfx0AAw8ACAnXIxgKADsCAA8ABwl6IxgKADsCAA4ABwlmIBQfAOIBAAAA.',
At='Atem:BAAALgAECgUJDwAAAA==.',
Au='Aulinn:BAAALgAECgIJAgAAAA==.Aurelianus:BAAALgAECgcJEwAAAA==.',
Av='Avalanche:BAAALgAECgUJCQAAAA==.',
Ax='Axefury:BAAALgADCgYJBgAAAA==.Axegrunion:BAAALgADCgEJAQAAAA==.',
Az='Azaris:BAABLgAECn8+AAIMAAkJzRwBDAB2AgAMAAkJzRwBDAB2AgAAAA==.',
Ba='Baelrog:BAAALgAECgYJDwAAAA==.Bananaslamma:BAAALgADCgMJBQAAAA==.Bandalar:BAABLgAECn8dAAMJAAkJBBLrRwDUAQAJAAkJBBLrRwDUAQAQAAIJQgpfMAAsAAAAAA==.Baranina:BAACLgAFFH8SAAMFAAYJgCHHBwAnAQAFAAMJ2iHHBwAnAQARAAQJix4SFgDcAAAuAAQKfysABBEACAnTI4IOAM4CABEACAkgIoIOAM4CAAUABQmOHws2ANYBABIABgnGIBMkAG0BAAAA.Barricaded:BAAALgAECggJDAAAAA==.Bashems:BAAALgADCgcJCQABLgAECgMJCQABAAAAAA==.Battosi:BAAALgADCgIJAgAAAA==.',
Be='Bealzebuub:BAAALgAECgUJDQAAAA==.Bearpaws:BAAALgADCgQJBAAAAA==.Beastums:BAABLgAECn8/AAISAAkJxRkPDABWAgASAAkJxRkPDABWAgAAAA==.Benji:BAABLgAECn8YAAMEAAgJCxhzbgCEAQAEAAgJCxhzbgCEAQATAAEJeQYuIgAhAAAAAA==.',
Bi='Biggiecat:BAAALgADCgYJBgABLgAECgUJFgAEAHMZAA==.Bigload:BAAALgADCgEJAQAAAA==.Bigunc:BAAALgAECgQJBgAAAA==.Bihgnuts:BAAALgAECgQJBgAAAA==.Bittybubble:BAAALgAECgEJAQAAAA==.',
Bl='Blazinitup:BAAALgADCgQJCQAAAA==.Blimey:BAAALgAECggJBgAAAA==.Blindaf:BAABLgAECn8iAAIUAAYJvBZeIABQAQAUAAYJvBZeIABQAQAAAA==.Blindcauze:BAAALgADCgEJAQAAAA==.Blindmonk:BAABLgAECn8aAAIVAAcJqhEINwAPAQAVAAcJqhEINwAPAQAAAA==.Blite:BAAALgADCgkJIgAAAA==.Bloodlòck:BAAALgADCgUJCgAAAA==.Bloodmary:BAABLgAECn8kAAMWAAkJ3wV+lgAsAQAWAAkJ3wV+lgAsAQAXAAQJQAevcgCxAAAAAA==.Bloombriar:BAAALgAECgEJAQAAAA==.Bloöm:BAACLgAFFH8RAAMGAAQJUQwTRACTAAAGAAMJAwQTRACTAAAKAAMJtwEjOABrAAAuAAQKfx0AAwYACAl9DxI9AIwBAAYACAl9DxI9AIwBAAoAAQl/EZ58ADcAAAAA.Blueeyearch:BAABLgAECn8UAAMRAAYJzx3aFAD/AAAFAAUJLCPQTgB8AQARAAUJoRLaFAD/AAAAAA==.Bluetish:BAAALgAECgQJBAAAAA==.',
Bo='Bo:BAAALgAECggJCAAAAA==.Bolgan:BAAALgAECgMJCAABLgAECggJJQAVALgaAA==.Bonedecay:BAAALgAECgEJBQAAAA==.Bonerina:BAAALgAECgYJCgAAAA==.Boomadk:BAACLgAFFH8QAAICAAQJgBeTTgA2AQACAAQJgBeTTgA2AQAuAAQKfyAAAwIACQkPIkUfAMYCAAIACQmZIUUfAMYCABgABwmfH9gCAHsCAAAA.Boomapriest:BAAALgAECgcJCwAAAA==.Boosh:BAAALgAECgIJAgAAAA==.Booshler:BAAALgAECgUJCgAAAA==.Booshlia:BAABLgAECn8XAAIJAAkJDhcjKAAVAgAJAAkJDhcjKAAVAgAAAA==.Booshly:BAAALgAECgUJBQAAAA==.Bootstrapbil:BAAALgAECgUJBQAAAA==.Bowjoemojo:BAAALgADCgIJAgAAAA==.Bowsho:BAAALgAECgQJBQAAAA==.',
Br='Bradburn:BAAALgAECgQJCAAAAA==.Brasserz:BAABLgAECn8YAAISAAgJ+RC5GgC5AQASAAgJ+RC5GgC5AQAAAA==.Brewswillis:BAAALgADCgYJBgAAAA==.Brice:BAABLgAECn8UAAIXAAUJ9R6VLQCSAQAXAAUJ9R6VLQCSAQAAAA==.Briochebun:BAABLgAECn8fAAIWAAkJSBzkIACnAgAWAAkJSBzkIACnAgAAAA==.',
Bu='Bubblewrap:BAAALgADCggJDgABLgAECgYJIQAGAG4fAA==.Bustin:BAABLgAECn8aAAIWAAgJzh6lKgA+AgAWAAgJzh6lKgA+AgAAAA==.',
Bw='Bwangifer:BAABLgAECn8/AAIQAAkJKxpyBABeAgAQAAkJKxpyBABeAgAAAA==.',
['Bë']='Bëcky:BAAALgAFFAMJAwAAAA==.',
Ca='Caerus:BAAALgAECgEJAQABLgAECgkJLwASAE8gAA==.Caitriona:BAAALgADCgMJAwABLgAECgcJBwABAAAAAA==.Cannala:BAAALgADCgkJHgAAAA==.Cargae:BAAALgADCggJEwAAAA==.Cassios:BAABLgAECn8lAAIVAAgJuBrkEQAeAgAVAAgJuBrkEQAeAgAAAA==.',
Ce='Celathel:BAAALgAECgYJDwAAAA==.Cellysia:BAABLgAECn80AAMIAAkJpwmSKABtAQAIAAkJpwmSKABtAQAMAAcJZQKgVQCRAAAAAA==.Celsìus:BAABLgAECn8XAAIEAAYJbhOg1QBEAQAEAAYJbhOg1QBEAQAAAA==.Ceramyth:BAAALgAECgUJEAAAAA==.Ceres:BAABLgAECn8/AAIZAAkJdR2uAQCuAgAZAAkJdR2uAQCuAgAAAA==.Cesara:BAACLgAFFH8HAAMMAAMJFhS+HQDfAAAMAAMJFhS+HQDfAAAIAAMJ6A+2HACvAAAuAAQKfzwAAwwACQlHI5ADABIDAAwACQlHI5ADABIDAAgAAglhBCR/ADMAAAAA.',
Ch='Chaahck:BAAALgAECgMJAwAAAA==.Chal:BAAALgAECgUJBwAAAA==.Chbribs:BAAALgAECgYJEQAAAA==.Chichimounki:BAAALgADCgUJBQAAAA==.Chiptewth:BAAALgADCgEJAQAAAA==.',
Ci='Cinderella:BAABLgAECn8zAAIEAAkJLSRQCgATAwAEAAkJLSRQCgATAwAAAA==.',
Cl='Clumsey:BAAALgADCgEJAQAAAA==.',
Co='Cocoshan:BAAALgAECgcJDgAAAA==.Columbina:BAACLgAFFH8eAAIJAAYJMRSnHwCEAQAJAAYJMRSnHwCEAQAuAAQKfxoAAgkABwmgGbdEAOEBAAkABwmgGbdEAOEBAAAA.Comma:BAABLgAECn8UAAIPAAcJFxKwHABjAQAPAAcJFxKwHABjAQAAAA==.Cooperhowerd:BAAALgADCgkJIgAAAA==.Corn:BAABLgAECn8ZAAIWAAcJ5hWHcwBtAQAWAAcJ5hWHcwBtAQAAAA==.Couremese:BAAALgADCgYJBgAAAA==.',
Cr='Crackmonger:BAACLgAFFH8FAAIaAAMJ7xiyGgDoAAAaAAMJ7xiyGgDoAAAuAAQKfz0AAxoACQmNIkADAOoCABoACQmNIkADAOoCAA8AAgk1ED9AAFgAAAAA.Crackundead:BAAALgAECgYJDQAAAA==.Cravens:BAAALgAECgYJCwAAAA==.Craze:BAAALgADCgUJBQAAAA==.',
Cy='Cyphr:BAABLgAECn8/AAIGAAkJWx8ACAApAwAGAAkJWx8ACAApAwAAAA==.',
['Cë']='Cërbërus:BAAALgAECgQJBQAAAA==.',
Da='Dacs:BAAALgAECgQJEwAAAA==.Daen:BAAALgADCgcJCgAAAA==.Dagadus:BAAALgAECgQJCQAAAA==.Daggergarnet:BAAALgADCgYJBgAAAA==.Dajango:BAAALgAECgYJDQAAAA==.Damerot:BAABLgAECn8VAAMOAAUJ3hBkUQDsAAAOAAUJ3hBkUQDsAAAPAAEJngJAUgAhAAAAAA==.Dandity:BAAALgAECgcJDAAAAA==.Dangerous:BAAALgAECgEJAgAAAA==.Dangi:BAAALgADCgMJAwAAAA==.Dansharo:BAAALgAECgYJCAAAAA==.Darnel:BAAALgADCgQJBAAAAA==.',
De='Deadbeard:BAACLgAFFH8KAAICAAQJox67LwB4AQACAAQJox67LwB4AQAuAAQKfyYAAgIACAncJXoNAO8CAAIACAncJXoNAO8CAAAA.Deathknut:BAAALgADCggJCQAAAA==.Deathmethods:BAAALgAFFAEJAQAAAA==.Deathviix:BAAALgADCgQJBgAAAA==.Dekillerty:BAAALgADCgYJCQAAAA==.Deli:BAAALgAECggJEwAAAA==.Delphina:BAAALgADCgYJCQAAAA==.Demini:BAAALgAECgcJEAAAAA==.Demisê:BAACLgAFFH8HAAMDAAMJCAxHJACfAAACAAMJyQZIlwC/AAADAAMJCgtHJACfAAAuAAQKfyIAAwIACQn2F30sADoCAAIACQkWF30sADoCAAMABQmGEeExALwAAAAA.Demonessa:BAAALgAECgcJEQAAAA==.Demonslyer:BAAALgAECggJDwAAAA==.Derbygirl:BAAALgADCgYJBgAAAA==.Dermus:BAAALgADCgEJAQAAAA==.Deserter:BAABLgAECn8jAAMbAAgJkhRtIAC6AQAbAAgJkhRtIAC6AQAcAAYJtQz0HgA3AQAAAA==.Desso:BAABLgAECn8tAAIVAAgJLRnkFAD8AQAVAAgJLRnkFAD8AQAAAA==.Devilskin:BAAALgAECgYJCwAAAA==.',
Di='Dihhdevil:BAAALgAECgIJBAABLgAECgUJCgABAAAAAA==.Dillinger:BAABLgAECn8mAAILAAgJUhRRDgCtAQALAAgJUhRRDgCtAQAAAA==.Dingodgaf:BAABLgAECn8jAAIWAAcJDweewQDoAAAWAAcJDweewQDoAAAAAA==.',
Do='Doomsdae:BAAALgAECgQJCgAAAA==.Doomstir:BAABLgAECn8pAAIEAAYJKxesfABkAQAEAAYJKxesfABkAQAAAA==.',
Dr='Draemora:BAAALgADCgQJBAAAAA==.Dragonmynutz:BAAALgAECgYJBwAAAA==.Dragonshammy:BAAALgAECgYJBgAAAA==.Draknarok:BAABLgAECn8gAAICAAgJRRpBOAALAgACAAgJRRpBOAALAgAAAA==.Dranius:BAACLgAFFH8MAAIEAAQJGQmMXAAZAQAEAAQJGQmMXAAZAQAuAAQKfxcAAgQACAnHEiSJAMABAAQACAnHEiSJAMABAAAA.Drayeda:BAAALgADCgMJAwAAAA==.Dreadlord:BAAALgADCgEJAQAAAA==.Dreamclaw:BAABLgAECn8cAAILAAYJuQyiHwDkAAALAAYJuQyiHwDkAAAAAA==.Dredda:BAAALgADCgEJAQAAAA==.Drendar:BAAALgADCgUJBQAAAA==.Drippindots:BAACLgAFFH8IAAIdAAMJ+xEiZQDgAAAdAAMJ+xEiZQDgAAAuAAQKfykAAh0ACQmTGs0hAE4CAB0ACQmTGs0hAE4CAAAA.Driztette:BAABLgAECn8YAAIeAAYJWCJxJAAaAgAeAAYJWCJxJAAaAgAAAA==.Drnewport:BAAALgADCgkJDwAAAA==.Drock:BAAALgADCgIJAgAAAA==.Druidbearpig:BAAALgAECgYJBwABLgAECgkJJgAdANARAA==.Drunkfuq:BAAALgAECgEJAQAAAA==.Drustor:BAAALgAECgYJBgABLgAECgkJOAAfAEceAA==.Drystine:BAABLgAECn8qAAIUAAkJqh3YCQBvAgAUAAkJqh3YCQBvAgAAAA==.',
Du='Dubber:BAAALgADCggJCQAAAA==.Dugtig:BAAALgAECgcJCgAAAA==.',
['Dí']='Dín:BAAALgAECgIJAgAAAA==.',
Ed='Edd:BAAALgADCgYJBgAAAA==.',
Ee='Eedeeweewee:BAAALgADCgkJGQAAAA==.Eevee:BAAALgAECgYJCgAAAA==.',
Ei='Eillaura:BAACLgAFFH8HAAIIAAMJARr3FgDkAAAIAAMJARr3FgDkAAAuAAQKfyUAAggACQksG84JALYCAAgACQksG84JALYCAAAA.',
El='Elemag:BAAALgAECgEJAQAAAA==.Eleredra:BAAALgADCgcJBwABLgAECggJHAAMAIMSAA==.Elipsis:BAABLgAECn8dAAIIAAkJqRNbLACVAQAIAAkJqRNbLACVAQAAAA==.Ellessae:BAAALgADCgQJBQAAAA==.Ellyn:BAAALgAECgYJBgAAAA==.Elm:BAABLgAECn8zAAQKAAkJwxJxHQDDAQAKAAkJHBFxHQDDAQAGAAgJIRbiNwClAQAgAAEJ5BNeLwA4AAAAAA==.Elyas:BAAALgADCgEJAQAAAA==.Elybella:BAACLgAFFH8FAAIFAAMJ7gr8WwC6AAAFAAMJ7gr8WwC6AAAuAAQKfxoAAgUACAlgGAUvAPUBAAUACAlgGAUvAPUBAAAA.Elycia:BAAALgAECgYJBgABLgAFFAMJBQAFAO4KAA==.Elyenora:BAAALgAECgQJBAABLgAFFAMJBQAFAO4KAA==.Elyssaelyend:BAAALgAECgYJDAABLgAECggJKgAGADYbAA==.',
Em='Emanon:BAAALgAECgQJBQAAAA==.Emberion:BAAALgADCggJDgAAAA==.Emmental:BAABLgAECn8iAAIhAAgJ3RAtNQBKAQAhAAgJ3RAtNQBKAQAAAA==.',
En='Endload:BAAALgADCgEJAQAAAA==.Enquea:BAAALgAECgYJEgAAAA==.Enricco:BAABLgAECn8ZAAIhAAYJmwJPaQCMAAAhAAYJmwJPaQCMAAAAAA==.',
Er='Eramortis:BAAALgADCgYJBgAAAA==.Ereko:BAABLgAECn8lAAIFAAkJOBACOwDcAQAFAAkJOBACOwDcAQAAAA==.Erythorbic:BAABLgAECn8hAAMdAAgJ8xz2JAA+AgAdAAcJfRz2JAA+AgAZAAMJQyCiLwD8AAAAAA==.',
Es='Estralage:BAAALgAECgUJCgAAAA==.',
Ev='Evictor:BAAALgAECgUJCgABLgAECgkJGAAVAPMYAA==.',
Ex='Exileelfsam:BAABLgAECn8vAAISAAkJVwsXGQDIAQASAAkJVwsXGQDIAQAAAA==.',
Fa='Fallenrose:BAAALgAECgEJAQAAAA==.Fallensk:BAAALgADCgIJAgAAAA==.Faranth:BAAALgAECgIJAwAAAA==.Fargenstines:BAAALgADCgMJAwAAAA==.Fatass:BAAALgAECgMJAwAAAA==.Fatherrick:BAAALgAECgQJBAAAAA==.Faîle:BAACLgAFFH8jAAMiAAYJMBZpDwDhAQAiAAYJMBZpDwDhAQAMAAEJ1QE9NgA3AAAuAAQKfyoAAyIACAlEHycIAL0CACIACAlEHycIAL0CAAgABgkhCDNKABABAAAA.',
Fe='Feer:BAAALgAECgUJCwAAAA==.Feldron:BAABLgAECn8cAAMfAAkJZh3ACgDmAgAfAAgJGR7ACgDmAgAjAAEJgxjzHQA9AAAAAA==.Felshatter:BAABLgAECn8dAAIJAAgJvwvoZgA+AQAJAAgJvwvoZgA+AQAAAA==.Feltigress:BAABLgAECn8wAAILAAkJnCLrAQADAwALAAkJnCLrAQADAwAAAA==.Fendag:BAAALgAECgQJBAAAAA==.',
Ff='Ffugher:BAAALgAECgcJCwAAAA==.Ffuglee:BAAALgAECgMJAwAAAA==.Ffugme:BAABLgAECn8uAAIHAAgJzhLjEgCBAQAHAAgJzhLjEgCBAQAAAA==.Ffugnutz:BAAALgADCgQJBAAAAA==.Ffugoff:BAAALgAECgcJBwAAAA==.Ffugtard:BAAALgAECgcJEgAAAA==.Ffugyou:BAAALgADCgQJBAAAAA==.',
Fi='Fingerfister:BAAALgAECgQJBAABLgAECgYJBwABAAAAAA==.Finnian:BAABLgAECn8zAAIXAAkJdh4iBwAHAwAXAAkJdh4iBwAHAwAAAA==.Fio:BAACLgAFFH8OAAIkAAQJdSJSFACMAQAkAAQJdSJSFACMAQAuAAQKfyQAAyQACAn3JLMCAFoDACQACAn3JLMCAFoDABUAAQlJG0JwAFEAAAAA.Firiona:BAABLgAECn8aAAMiAAYJmxYdIwCSAQAiAAYJmxYdIwCSAQAMAAEJ8wmEeQAxAAAAAA==.Fistfuloftok:BAAALgAECgIJAgABLgAECggJHgALALsgAA==.',
Fl='Flashferment:BAABLgAECn8ZAAIlAAgJzRdKIQCMAQAlAAgJzRdKIQCMAQAAAA==.Flinn:BAABLgAECn8dAAIgAAkJBh52BQCVAgAgAAkJBh52BQCVAgAAAA==.Flowers:BAABLgAECn8yAAMJAAgJWiFNEgCcAgAJAAgJWiFNEgCcAgAUAAQJVRxPLgDtAAAAAA==.Fläva:BAAALgAECgUJDAAAAA==.',
Fo='Forkinyou:BAAALgAECgQJBAAAAA==.',
Fr='Fracture:BAAALgADCgYJBgAAAA==.Fresca:BAAALgADCgEJAQAAAA==.Fridgerollin:BAAALgADCggJFgAAAA==.Frifrah:BAAALgAECgMJBAAAAA==.Frosht:BAABLgAECn8wAAIEAAkJBBoJMgA5AgAEAAkJBBoJMgA5AgAAAA==.',
Fu='Furiousdemon:BAAALgADCgEJAQAAAA==.Furysbubble:BAAALgAECgEJAQAAAA==.Furyswarm:BAAALgAECgkJAQAAAA==.',
['Fö']='Föx:BAAALgADCgEJAQABLgAECgYJDwABAAAAAA==.',
Ga='Gafocalypse:BAAALgAECgcJDgAAAA==.Garddidit:BAAALgADCgUJBQABLgAECggJHQAQAOQbAA==.',
Ge='Gernaj:BAAALgAECgEJAQAAAA==.',
Gl='Glonor:BAAALgAECgQJBgAAAA==.',
Go='Goldberg:BAAALgADCgcJDQAAAA==.Goopmaster:BAAALgADCgUJBQAAAA==.Goovs:BAAALgAECgQJBQAAAA==.',
Gr='Grabmytusk:BAAALgADCgcJBwAAAA==.Gramthyr:BAAALgADCgkJIgAAAA==.Grep:BAAALgAECgMJAwAAAA==.Greygor:BAAALgAECgIJAgAAAA==.Grotok:BAABLgAECn8UAAMCAAgJVwr0hwA/AQACAAgJVwr0hwA/AQAYAAEJAABxFgA3AAAAAA==.',
Gu='Guacamole:BAAALgAECgUJBQAAAA==.Gub:BAAALgAECgMJAwAAAA==.Gumer:BAAALgAECgYJBwAAAA==.Gurgatron:BAAALgAECgcJCAABLgAECggJHAAPAAQXAA==.',
Ha='Halraku:BAAALgADCgEJAQAAAA==.Halsin:BAAALgADCgQJBAAAAA==.Halygos:BAAALgAECgYJCQAAAA==.Halygosa:BAAALgAECgEJAQAAAA==.Hasklaufien:BAAALgAECgIJBgAAAA==.',
He='Herpecluster:BAAALgAECgcJBgAAAA==.',
Hi='Hinderberg:BAAALgAECggJCAAAAA==.',
Ho='Holyraz:BAAALgADCgMJAwAAAA==.Holystrikes:BAAALgAECgUJBwAAAA==.',
Hu='Hugulin:BAABLgAECn8hAAIFAAkJ3QX6gAAkAQAFAAkJ3QX6gAAkAQAAAA==.',
Ic='Icedsoul:BAABLgAECn8bAAIEAAYJEwgOywDZAAAEAAYJEwgOywDZAAAAAA==.Icee:BAAALgADCgcJCgAAAA==.',
Ig='Iggey:BAABLgAECn8wAAIaAAkJjByjBgB9AgAaAAkJjByjBgB9AgAAAA==.',
Ik='Ikkaku:BAAALgAECgEJAQAAAA==.',
Il='Ilandras:BAABLgAECn8yAAIJAAgJAxEcTwCBAQAJAAgJAxEcTwCBAQAAAA==.Illadus:BAABLgAECn8eAAIJAAkJRgeXZwA9AQAJAAkJRgeXZwA9AQAAAA==.Illed:BAAALgADCgcJBwAAAA==.',
In='Indra:BAAALgAECgcJCQAAAA==.Intoxicated:BAABLgAECn8gAAIVAAgJCgziLABAAQAVAAgJCgziLABAAQAAAA==.',
Io='Ione:BAAALgADCgcJBwAAAA==.',
Ir='Iranna:BAACLgAFFH8VAAQmAAYJpx0KAgCFAQAmAAUJhhsKAgCFAQAjAAQJ0hpAAwBWAQAfAAIJiBT2MgBMAAAuAAQKfzIABCMACAmQJZ0CAJMCACYACAlwI0YBAN8CACMABwn2IJ0CAJMCAB8ABwkkIPoRAAECAAAA.Irondihh:BAAALgAECgMJAwABLgAECgUJCgABAAAAAA==.',
Iu='Iudi:BAAALgAECgQJBAABLgAECgkJGgAGAOYeAA==.',
Iy='Iyasu:BAAALgADCgQJBAAAAA==.',
Ja='Jachan:BAAALgADCgkJDwAAAA==.Jackblãck:BAAALgAECgQJBQABLgAECgkJKwACAG0gAA==.Janaki:BAABLgAECn8eAAMGAAgJsxmlHABNAgAGAAgJsxmlHABNAgAKAAQJghYOSgDHAAAAAA==.',
Je='Jestêr:BAAALgAFFAEJAQABLgAFFAYJIwAiADAWAA==.',
Jo='Joenutter:BAAALgAECgMJBgAAAA==.Joia:BAAALgADCgQJBAAAAA==.Jonnyquestt:BAABLgAECn9GAAIWAAkJGxYYRADiAQAWAAkJGxYYRADiAQAAAA==.',
Ju='Juicie:BAAALgAECgUJCgAAAA==.Junrage:BAAALgADCgMJAwABLgAFFAUJFQAOABkeAA==.Junrush:BAAALgAECggJDgABLgAFFAUJFQAOABkeAA==.',
['Jè']='Jèstèr:BAABLgAFFH8FAAIeAAMJ0AyaRAC6AAAeAAMJ0AyaRAC6AAABLgAFFAYJIwAiADAWAA==.',
Ka='Kalea:BAAALgAECgIJBwAAAA==.Kalecgo:BAAALgAECgMJAwABLgAECggJFAADAEIaAA==.Kalietha:BAAALgAECgEJAQAAAA==.Kanaezz:BAAALgADCggJCAAAAA==.Kat:BAABLgAECn8YAAMlAAkJZhRSGADTAQAlAAcJNBpSGADTAQAkAAcJZgarTwCUAAAAAA==.Katsuko:BAABLgAECn8zAAIDAAkJyRivDQAUAgADAAkJyRivDQAUAgAAAA==.Kattnirra:BAABLgAECn8uAAIFAAkJSREEMwD6AQAFAAkJSREEMwD6AQAAAA==.Katze:BAABLgAECn9LAAIFAAkJ8xiZHABkAgAFAAkJ8xiZHABkAgAAAA==.Kaylé:BAAALgAECgYJDQAAAA==.',
Ke='Keannor:BAAALgADCgMJAwAAAA==.Keco:BAAALgADCgcJBwAAAA==.Keepper:BAABLgAECn8oAAIdAAkJ8hB2TACqAQAdAAkJ8hB2TACqAQAAAA==.Kelaatun:BAAALgAECgEJAgAAAA==.Kennan:BAAALgADCgIJAgAAAA==.Kenslynn:BAABLgAECn8WAAIIAAgJRRDtLgA/AQAIAAgJRRDtLgA/AQAAAA==.Ketheric:BAAALgAFFAIJAgABLgAFFAQJDAAeAEYZAA==.',
Ki='Killahaseo:BAAALgAECgYJBgABLgAECggJKQAbAE0ZAA==.Killmoedee:BAABLgAECn84AAIHAAkJoCCnAgDrAgAHAAkJoCCnAgDrAgAAAA==.Kitwryn:BAAALgADCgUJBQAAAA==.',
Kk='Kkaell:BAAALgAECgQJCgABLgAECgYJBwABAAAAAA==.',
Kl='Klexios:BAABLgAECn8WAAIPAAUJqQOSOwBrAAAPAAUJqQOSOwBrAAAAAA==.',
Ko='Koopa:BAAALgAECgQJBQAAAA==.Korbandallas:BAAALgAECgQJCQAAAA==.Kozzmo:BAAALgAECgEJAQAAAA==.',
Kr='Kracious:BAAALgAECgQJBAAAAA==.Kraulhoof:BAAALgAECgEJAgABLgAECgYJBwABAAAAAA==.Krispy:BAAALgAECggJDgAAAA==.Krymson:BAAALgAECgYJBwAAAA==.',
Ku='Kui:BAABLgAECn8/AAIlAAkJwB8HBQDlAgAlAAkJwB8HBQDlAgAAAA==.Kurtcobrain:BAAALgAECgYJCQAAAA==.',
['Kö']='Köz:BAAALgAECgUJBQAAAA==.',
La='Laetri:BAABLgAECn8jAAIJAAkJ2RQWPwC1AQAJAAkJ2RQWPwC1AQAAAA==.Lailiia:BAAALgADCgkJCQABLgAECgkJOgAIAFAkAA==.Lasttok:BAABLgAECn8eAAMLAAgJuyCPBgBaAgALAAgJAR6PBgBaAgAKAAIJvBO3YAB3AAAAAA==.Laylene:BAAALgAECgcJEAAAAA==.Lazloo:BAABLgAECn8yAAMOAAkJcSXLAQBVAwAOAAkJbSXLAQBVAwAaAAcJOhwbFACnAQAAAA==.Lazymidget:BAABLgAECn8eAAIRAAcJJh1VLQDFAQARAAcJJh1VLQDFAQAAAA==.',
Le='Leaana:BAAALgADCgUJBQAAAA==.Leftÿ:BAAALgAECgIJAgABLgAECgkJOwASAAoUAA==.Legindkiller:BAAALgADCgkJIgAAAA==.Lenie:BAAALgADCgYJBgABLgAFFAgJIwAGAIofAA==.',
Li='Lightace:BAABLgAECn8ZAAIWAAcJSgeUvgDtAAAWAAcJSgeUvgDtAAAAAA==.Lilgeezus:BAAALgADCgEJAQAAAA==.Lilyia:BAAALgADCgcJDAAAAA==.Linkkil:BAABLgAECn8cAAISAAkJASFLBADfAgASAAkJASFLBADfAgAAAA==.',
Lo='Loastotem:BAAALgADCgcJBwAAAA==.Lobos:BAABLgAECn8eAAIdAAgJMQdphgAjAQAdAAgJMQdphgAjAQAAAA==.Lokni:BAAALgAECgYJBwAAAA==.Lostdraco:BAABLgAECn8XAAIcAAcJpgQ3EgDTAAAcAAcJpgQ3EgDTAAAAAA==.Lostdream:BAABLgAECn8dAAMJAAcJfANsxACAAAAJAAYJLwNsxACAAAAUAAIJKwPDawAkAAAAAA==.Loun:BAABLgAECn8rAAIlAAgJuBY6GQDLAQAlAAgJuBY6GQDLAQAAAA==.Lowku:BAAALgAECgEJAQAAAA==.Lowrise:BAAALgADCgkJCgAAAA==.',
Lu='Luciellia:BAAALgAECgEJAQAAAA==.Luiss:BAAALgAECgMJAwAAAA==.Luken:BAAALgADCggJFgAAAA==.Luminara:BAAALgADCgcJDAAAAA==.Luminism:BAAALgADCgYJCAABLgAECggJHAAkAEYeAA==.Luteil:BAAALgADCgMJAwAAAA==.Luvlycruelty:BAAALgAECgcJBwAAAA==.',
Ly='Lyn:BAECLgAFFH8IAAIlAAQJkiScCgCyAQAlAAQJkiScCgCyAQAuAAQKf0QAAiUACQmZJjoAAIgDACUACQmZJjoAAIgDAAAA.',
Ma='Mackenziiee:BAACLgAFFH8HAAIFAAMJfw+FTQDmAAAFAAMJfw+FTQDmAAAuAAQKfzIAAgUACQnoHQkRALMCAAUACQnoHQkRALMCAAAA.Mackthyra:BAAALgADCgcJBwABLgAFFAMJBwAFAH8PAA==.Madglowup:BAABLgAECn8fAAImAAYJtiK4BQDwAQAmAAYJtiK4BQDwAQAAAA==.Magicbunga:BAAALgADCgIJAgAAAA==.Magicwater:BAABLgAECn8gAAIEAAkJhxxxKQBeAgAEAAkJhxxxKQBeAgAAAA==.Magtaki:BAAALgAECgkJCAAAAA==.Magyar:BAAALgAECgUJBQAAAA==.Mainline:BAAALgAECggJDwAAAA==.Maizepriest:BAABLgAECn8zAAIMAAgJ2CHDCQCXAgAMAAgJ2CHDCQCXAgAAAA==.Maliaa:BAAALgADCgYJBgAAAA==.Mannysaf:BAABLgAECn8jAAIOAAgJrA75MAB0AQAOAAgJrA75MAB0AQAAAA==.Manter:BAAALgADCgIJAgAAAA==.Mariota:BAAALgAECgQJAwABLgAFFAcJEgAEACIYAA==.Marus:BAAALgADCgMJAwAAAA==.',
Me='Mechalia:BAAALgADCgQJBAAAAA==.Meerkat:BAAALgAECgEJAQABLgAECgYJBgABAAAAAA==.Mellowblink:BAABLgAECn8oAAIEAAgJWBa1TwDVAQAEAAgJWBa1TwDVAQAAAA==.Mellowlink:BAABLgAECn8nAAIfAAcJcBvQGgCoAQAfAAcJcBvQGgCoAQAAAA==.Melorian:BAAALgADCgkJEAAAAA==.Memeñtomori:BAAALgAECggJDwAAAA==.Menara:BAAALgAECgYJEAAAAA==.Metaviix:BAAALgAECgQJBAAAAA==.',
Mi='Micromancer:BAAALgADCgMJAwAAAA==.Midnightmage:BAAALgAECgUJBgAAAA==.Migglet:BAAALgAECgQJBgAAAA==.Milkyboy:BAAALgADCgQJBAAAAA==.Millhi:BAAALgAECgcJBwAAAA==.Mimi:BAACLgAFFH8tAAQFAAkJpyWyAADaAgAFAAgJ7COyAADaAgARAAgJHCNDAQCJAgASAAMJmiP2HQDKAAAuAAQKfzYABBEACQmCJu0DAGUDABEACAkCJu0DAGUDABIABwnIJfMKAGUCAAUABglLJHVXAIUBAAAA.Mintyice:BAAALgAECgcJBgAAAA==.Miramage:BAAALgAECgQJCQABLgAECgkJMgAfAMIXAA==.Miravus:BAABLgAECn8yAAMfAAkJwhelGAC8AQAfAAkJJhelGAC8AQAjAAUJSRKDDgArAQAAAA==.Mirlanda:BAABLgAECn8YAAIjAAYJLAVDFADQAAAjAAYJLAVDFADQAAAAAA==.Misttie:BAAALgAECggJEwABLgAECgkJHQAIAKkTAA==.',
Mo='Monkerick:BAAALgAECgYJDAAAAA==.Moonana:BAAALgADCgIJAgAAAA==.Morber:BAAALgAECgQJBQAAAA==.Morphingtime:BAAALgADCgIJAgAAAA==.Mowte:BAAALgADCgkJIgAAAA==.',
Mu='Murkoobi:BAAALgAECgMJBQAAAA==.Mursk:BAAALgAECgMJAwAAAA==.',
My='Myhoovesrhot:BAAALgAECgIJAgAAAA==.Mystrial:BAAALgAECgEJAwAAAA==.Mystáke:BAAALgAFFAEJAgAAAA==.',
['Mä']='Mäble:BAAALgAECgEJAQAAAA==.',
['Mê']='Mêrcy:BAAALgADCgYJBgAAAA==.',
['Mò']='Mòus:BAAALgAECgYJEwABLgAFFAMJCQAFADMPAA==.',
['Mó']='Mómo:BAAALgAECgcJCgAAAA==.Móus:BAAALgAECgUJDQABLgAFFAMJCQAFADMPAA==.',
Na='Narcissus:BAAALgAECgYJBgAAAA==.Narivia:BAAALgAECgUJBgABLgAFFAYJIwAiADAWAA==.Naro:BAAALgAECgcJDAABLgAECgkJMwAEAC0kAA==.Nathadon:BAAALgAECgEJAQAAAA==.Nathalin:BAABLgAECn8yAAQKAAgJ2RamKQBqAQAKAAcJrROmKQBqAQAgAAUJ1BeJJAAHAQALAAUJIhAyIADeAAAAAA==.Nazari:BAAALgAECgEJAQAAAA==.',
Ne='Necrotis:BAAALgADCgkJIgAAAA==.Nectarion:BAAALgAECgEJAQAAAA==.Neftearii:BAAALgADCgEJAQAAAA==.Nevelia:BAABLgAECn86AAMIAAkJUCRiAQCfAwAIAAkJUCRiAQCfAwAMAAYJzxqsRQDRAAAAAA==.Neytholy:BAAALgAECgcJDAAAAA==.Nezukô:BAAALgAECgcJCAAAAA==.',
Ni='Nienna:BAAALgAECgIJAgAAAA==.Nikkisan:BAAALgADCgYJBgAAAA==.Nitalan:BAAALgAECgIJAgAAAA==.Nithenseth:BAAALgADCggJDQAAAA==.Nixk:BAAALgAECgYJDwAAAA==.',
No='Noavail:BAAALgADCgMJAwAAAA==.Noixi:BAAALgAECgUJEgAAAA==.Noraldrys:BAAALgADCgcJDQAAAA==.Noralyne:BAAALgAECgYJDAAAAA==.Noras:BAABLgAECn8YAAIVAAkJ8xiGDwA7AgAVAAkJ8xiGDwA7AgAAAA==.Noraxia:BAAALgADCgkJEAAAAA==.Nordicslayer:BAABLgAECn8qAAIaAAgJNBKJGAB/AQAaAAgJNBKJGAB/AQAAAA==.Notagnoblin:BAEBLgAFFH8LAAIDAAQJfSHwEwAgAQADAAQJfSHwEwAgAQABLgAFFAQJEQAlAC4mAA==.',
Ny='Nysonia:BAAALgAECgcJBwAAAA==.',
Ob='Obnyxion:BAABLgAECn8mAAIcAAkJGQ48CQCCAQAcAAkJGQ48CQCCAQAAAA==.',
Oc='Octuroun:BAAALgAECgcJEQAAAA==.',
Od='Oddsoul:BAAALgAECgUJDQAAAA==.',
Og='Ogrelurd:BAABLgAECn8XAAMaAAcJSSCXCgAnAgAaAAcJSSCXCgAnAgAOAAQJGxjxVgDZAAAAAA==.',
Oh='Ohlordy:BAAALgAECgcJEQAAAA==.',
Ol='Oliveia:BAAALgADCgcJCgAAAA==.',
Om='Omontanha:BAAALgAECgUJCgAAAA==.',
On='Oniryoshi:BAAALgAECgQJBAAAAA==.Onlyzugs:BAAALgADCgEJAgAAAA==.',
Op='Ophelia:BAACLgAFFH8JAAMnAAMJvRB7HABPAAAdAAIJRxGEiQCWAAAnAAEJqg97HABPAAAuAAQKf0AABB0ACQnZILInADACAB0ACAlmHLInADACACcABgmZIpgJAKgBABkAAQmmCJh0ADAAAAAA.',
Or='Orakwa:BAAALgAECgYJEwAAAA==.',
Ou='Outen:BAAALgAECgcJBwAAAA==.',
Oz='Ozzieliem:BAAALgAECgEJAQAAAA==.',
Pa='Pakleader:BAAALgADCgIJAgAAAA==.Palalamadi:BAAALgADCgMJAwAAAA==.Pallinda:BAABLgAECn8sAAMXAAkJBhhjGgAbAgAXAAgJaRdjGgAbAgAWAAkJkRIJTwDCAQAAAA==.Panakananama:BAAALgAECgcJDwAAAA==.Panz:BAABLgAECn8wAAMbAAgJSwv1NQA3AQAbAAgJSwv1NQA3AQAcAAEJIA7yIgA0AAAAAA==.Papablock:BAAALgADCgMJAwAAAA==.Papagrip:BAAALgAFFAIJAgABLgAFFAMJAwABAAAAAA==.Papalock:BAAALgAFFAMJAwAAAA==.Papiperkins:BAAALgAECgEJAQAAAA==.Pappyoblues:BAAALgAECgcJCAAAAA==.Papster:BAAALgADCgYJBgAAAA==.Parati:BAAALgAECgIJAgAAAA==.Paylot:BAAALgAECgMJCAAAAA==.Pazuzuu:BAAALgAECgIJAgABLgAECgkJJgAdANARAA==.',
Pe='Peachmangogt:BAAALgADCgUJBgAAAA==.Pendulum:BAAALgADCgkJCwAAAA==.Pendulumlaw:BAABLgAECn8UAAMaAAkJNhstBgCJAgAaAAkJHRstBgCJAgAOAAIJHhJ5cwB5AAAAAA==.Pennypacker:BAAALgAECgcJDQAAAA==.Personality:BAAALgADCggJCAAAAA==.Petmycat:BAABLgAECn8WAAMFAAYJcRAXgQAjAQAFAAYJcRAXgQAjAQARAAUJVAheHwCfAAAAAA==.',
Ph='Phara:BAABLgAECn8cAAQMAAkJcwvaJACDAQAMAAkJcwvaJACDAQAiAAUJZgirNgDwAAAIAAIJlAFvfAA3AAAAAA==.Phenomenon:BAAALgADCgUJBQAAAA==.Phoel:BAAALgADCgkJDwAAAA==.Phoopalychu:BAAALgAECgUJBQABLgAECgkJJAAkAKcSAA==.Phoopanchu:BAABLgAECn8kAAIkAAkJpxJpIwDaAQAkAAkJpxJpIwDaAQAAAA==.',
Pi='Pibble:BAAALgADCgMJAwAAAA==.Pinkbuns:BAABLgAECn8wAAIEAAgJaxgJSgDmAQAEAAgJaxgJSgDmAQAAAA==.Pirimus:BAAALgADCgEJAQAAAA==.',
Pn='Pneuma:BAABLgAECn8kAAIQAAgJ1CKkAgC5AgAQAAgJ1CKkAgC5AgAAAA==.',
Po='Pofella:BAAALgAECgMJAwAAAA==.Pokinsmot:BAAALgADCgYJCwAAAA==.Pollonius:BAAALgADCgIJAgAAAA==.Popsthyr:BAAALgADCgYJBgAAAA==.Popsy:BAABLgAECn8hAAIWAAgJBRFPagCAAQAWAAgJBRFPagCAAQAAAA==.',
Pr='Precarity:BAAALgAECgEJAQAAAA==.Prenton:BAABLgAECn8tAAIOAAkJph7mCQCyAgAOAAkJph7mCQCyAgAAAA==.Pretzel:BAAALgADCgUJBQABLgAFFAUJEQACAMskAA==.Prideflag:BAAALgAECgMJAwAAAA==.Primaldead:BAACLgAFFH8FAAIdAAIJYwRmogBiAAAdAAIJYwRmogBiAAAuAAQKf1EAAh0ACAl8Gm0oACwCAB0ACAl8Gm0oACwCAAAA.Pristin:BAAALgAECgIJAwAAAA==.Profundity:BAAALgAECgcJEAAAAA==.',
Pu='Punchmyface:BAAALgADCgUJCAAAAA==.Puny:BAABLgAECn8rAAICAAkJbSA0EQDSAgACAAkJbSA0EQDSAgAAAA==.',
Qe='Qeini:BAABLgAECn8zAAIiAAgJuxlSEABMAgAiAAgJuxlSEABMAgAAAA==.',
Ra='Radrin:BAAALgAECgQJBQAAAA==.Rafoff:BAAALgAECgYJEQAAAA==.Rahll:BAAALgADCgkJIgAAAA==.Rancoramble:BAABLgAECn8XAAIDAAkJDQRgKgDsAAADAAkJDQRgKgDsAAAAAA==.Randis:BAABLgAECn8wAAMCAAkJdg3nTwDAAQACAAkJdg3nTwDAAQAYAAYJoQJkIwB5AAAAAA==.Ranekk:BAAALgAECgEJAQAAAA==.Razglaive:BAAALgADCgYJBgAAAA==.Razhunt:BAAALgAECgUJCgAAAA==.Razonghoul:BAABLgAECn9DAAICAAkJvCICCwAGAwACAAkJvCICCwAGAwAAAA==.',
Re='Redheat:BAAALgADCgUJBQAAAA==.Redwyn:BAAALgADCgMJAwAAAA==.Reemonhunter:BAAALgAECgEJAgAAAA==.Regarded:BAAALgADCgcJBwAAAA==.Renge:BAAALgADCgEJAQAAAA==.Rengår:BAAALgAECgYJEgAAAA==.Renx:BAAALgAECgQJBQAAAA==.Reticent:BAABLgAECn8UAAIFAAYJMSXWKgAbAgAFAAYJMSXWKgAbAgAAAA==.Rexiis:BAABLgAECn8mAAMdAAkJ0BE8PQDaAQAdAAkJ0BE8PQDaAQAnAAEJAABdNAAzAAAAAA==.Reyth:BAAALgAECgYJEAAAAA==.',
Rh='Rhaul:BAAALgAECgEJAQAAAA==.Rhuby:BAAALgADCgkJDwAAAA==.Rhyl:BAABLgAECn8mAAIfAAcJKyG9EACcAgAfAAcJKyG9EACcAgAAAA==.',
Ri='Rimos:BAAALgAECgEJAQAAAA==.Ripcord:BAAALgADCggJDQAAAA==.Riptîde:BAABLgAECn84AAIhAAkJtBOeGwDrAQAhAAkJtBOeGwDrAQAAAA==.',
Ro='Rockadin:BAABLgAECn8bAAIWAAYJQBRIpwAQAQAWAAYJQBRIpwAQAQAAAA==.Rodrick:BAAALgAECgIJAgAAAA==.Roostor:BAAALgADCgYJBgAAAA==.Rosael:BAAALgAECgEJAQAAAA==.Roundhouse:BAABLgAECn8WAAIlAAgJMBYPGQDMAQAlAAgJMBYPGQDMAQAAAA==.',
Ru='Rubbmytotems:BAAALgAECgYJEAAAAA==.Rulen:BAAALgADCgMJCQAAAA==.Ruleti:BAABLgAECn8rAAMFAAkJ3xa1KAAlAgAFAAkJ3xa1KAAlAgARAAIJrQn8egBXAAAAAA==.Rumí:BAABLgAECn8hAAIJAAkJYAniZQBBAQAJAAkJYAniZQBBAQAAAA==.Russell:BAAALgADCgkJHwAAAA==.Rutgore:BAABLgAECn84AAIfAAkJRx7NBgCpAgAfAAkJRx7NBgCpAgAAAA==.',
Rx='Rx:BAAALgAECgUJBQAAAA==.',
Sa='Sabado:BAAALgAECgQJDQAAAA==.Safewerd:BAEBLgAECn8YAAMkAAgJGRLHPwA7AQAkAAgJGRLHPwA7AQAVAAMJNgd7dgBPAAAAAA==.Saitáma:BAAALgADCgQJBAAAAA==.Samíra:BAAALgAECgMJBAAAAA==.Santapaws:BAAALgAECgMJAwAAAA==.Santrious:BAAALgAECgUJCgAAAA==.Saraceleste:BAAALgAECgEJAQAAAA==.Sarahfi:BAAALgAECgQJCAAAAA==.Saraisabella:BAAALgADCgMJAwAAAA==.Saralanna:BAABLgAECn8aAAIdAAgJyQ57WgCDAQAdAAgJyQ57WgCDAQAAAA==.Sarasophie:BAAALgADCgUJBQAAAA==.Sarcastrophe:BAAALgADCgMJAwAAAA==.Sarefina:BAAALgAECgcJEwAAAA==.Sathenazarke:BAACLgAFFH8UAAMcAAUJNSTMAACvAQAcAAUJNSTMAACvAQANAAMJ0QWJHgCgAAAuAAQKfzYABBwACQlgIv0DADACABwABwnoIP0DADACAA0ACAnkGNIRACECABsABwncGqEbAOsBAAEuAAUUBgkVACYApx0A.Saths:BAAALgADCgEJAQABLgAECggJEwABAAAAAA==.',
Sc='Schallue:BAABLgAECn8gAAIoAAgJkAgCBgA4AQAoAAgJkAgCBgA4AQAAAA==.Schism:BAAALgAECgEJAQAAAA==.Scoban:BAACLgAFFH8mAAIXAAcJryPHAgCLAgAXAAcJryPHAgCLAgAuAAQKfyoAAhcACAl4IQsOAKgCABcACAl4IQsOAKgCAAAA.Scylla:BAAALgAECgUJDAAAAA==.',
Se='Seaworld:BAAALgAECgYJCAAAAA==.Selithel:BAABLgAECn8XAAIUAAgJ4AfHJwAXAQAUAAgJ4AfHJwAXAQAAAA==.Seraphnite:BAAALgAECgYJEQABLgAECgQJBAABAAAAAA==.Serioussurv:BAAALgAECgUJCgAAAA==.Setsunachan:BAAALgADCgIJAgABLgAECgkJMwADAMkYAA==.',
Sh='Shadeebear:BAAALgADCgMJAwAAAA==.Shadowmander:BAABLgAECn8WAAQiAAcJMwUMTQCeAAAiAAUJUQUMTQCeAAAMAAYJowfoVACUAAAIAAEJFgFocwAaAAAAAA==.Shaeliana:BAAALgAECgQJDgAAAA==.Shalera:BAAALgAECgcJBwAAAA==.Shaohlin:BAAALgAECgUJDQAAAA==.Shaqfu:BAAALgADCgkJIAAAAA==.Shavemybush:BAAALgAECgEJAQAAAA==.Shields:BAAALgAECgkJCQAAAA==.Shiggyloo:BAAALgAECggJAQAAAA==.Shigure:BAABLgAECn8qAAIEAAkJWw3NWwCyAQAEAAkJWw3NWwCyAQAAAA==.Shivers:BAAALgAFFAEJAQAAAA==.Shnow:BAAALgAECgkJEwAAAA==.Sholin:BAABLgAECn8gAAIlAAgJ9h1fDQBNAgAlAAgJ9h1fDQBNAgAAAA==.Shomea:BAABLgAECn8WAAMDAAUJmQmNOgCPAAADAAUJtQiNOgCPAAACAAMJ9QYmBgGCAAAAAA==.Shugz:BAAALgADCgkJIgAAAA==.Shumai:BAAALgAECgYJCAAAAA==.',
Si='Sikotick:BAABLgAECn8jAAIGAAgJmh4AFQCOAgAGAAgJmh4AFQCOAgAAAA==.Sikxbetrayer:BAAALgAECgcJDwAAAA==.Siliconista:BAACLgAFFH8LAAIEAAMJgyG1XQAWAQAEAAMJgyG1XQAWAQAuAAQKfzkAAgQACQkRITYWAL8CAAQACQkRITYWAL8CAAAA.Silverbolt:BAABLgAECn8aAAIOAAgJ2gsnOABRAQAOAAgJ2gsnOABRAQAAAA==.Simbelmyne:BAAALgAECgQJCAAAAA==.Sinderone:BAACLgAFFH8dAAMXAAcJdBFcCAAIAgAXAAcJdBFcCAAIAgAWAAEJ8QazoAA/AAAuAAQKf0AAAxcACQl/H+YGAAwDABcACQl/H+YGAAwDABYABQn9F+PDAOUAAAAA.',
Sk='Skaaduush:BAAALgAECgYJDAAAAA==.Skyne:BAAALgAECgEJAQAAAA==.Skypaw:BAAALgAECgEJAwAAAA==.',
Sl='Slavon:BAABLgAECn87AAICAAkJwCBtEADXAgACAAkJwCBtEADXAgAAAA==.Sleepylune:BAAALgAECgMJBQAAAA==.Slippie:BAAALgADCgQJAgAAAA==.Sllew:BAABLgAECn8sAAICAAkJASIFDQDzAgACAAkJASIFDQDzAgAAAA==.Slothfu:BAAALgAECgEJAQAAAA==.Slèw:BAAALgAECgQJBAAAAA==.',
Sm='Smitestuff:BAAALgAECgYJDwAAAA==.Smokymcpot:BAAALgADCgMJAwAAAA==.Smoulder:BAAALgAECgYJCgAAAA==.',
Sn='Snigles:BAABLgAECn8gAAIjAAgJaBBFCQCZAQAjAAgJaBBFCQCZAQAAAA==.',
So='Sokrash:BAAALgADCgcJDQAAAA==.Somannita:BAAALgADCgcJBwAAAA==.Souei:BAAALgADCgEJAQABLgAECggJFAACAFcKAA==.Soulfinder:BAAALgADCgMJAwAAAA==.Soulgiver:BAAALgAECgMJAwAAAA==.',
Sp='Spartos:BAAALgAECgYJEAAAAA==.Sposi:BAEBLgAECn8tAAIDAAgJaCFhCQBoAgADAAgJaCFhCQBoAgAAAA==.Spraynpray:BAAALgAECgYJCQAAAA==.',
Sr='Srimrithyu:BAAALgAECgEJAQAAAA==.',
Ss='Sselionn:BAABLgAECn8dAAMeAAYJpQuejQCXAAAeAAUJaAaejQCXAAAhAAUJ7ARKaQCMAAAAAA==.',
St='Stabathaa:BAAALgAECgUJCQAAAA==.Stomps:BAABLgAECn8cAAIOAAkJBx3eDwBnAgAOAAkJBx3eDwBnAgAAAA==.',
Su='Subliminal:BAABLgAECn8XAAMfAAkJChGkIAB1AQAfAAkJChGkIAB1AQAmAAEJsww0IAAyAAAAAA==.Sumbtch:BAAALgAECgUJBgAAAA==.',
Sv='Svartalfar:BAAALgADCgMJAQAAAA==.',
Sy='Syravia:BAABLgAECn8fAAIWAAcJbgVb0wDQAAAWAAcJbgVb0wDQAAAAAA==.',
['Sé']='Séraphyne:BAAALgAECgYJDgAAAA==.',
Ta='Talarin:BAAALgAECgYJDgAAAA==.Tameka:BAAALgAECgQJBgAAAA==.Tardis:BAAALgAECgkJEAAAAA==.Tatersmonk:BAECLgAFFH8RAAIlAAQJLiZeCgC0AQAlAAQJLiZeCgC0AQAuAAQKfyMAAiUACQnpJLsDAFQDACUACQnpJLsDAFQDAAAA.Taterthot:BAAALgADCgcJBwAAAA==.Tavinrayn:BAAALgAECggJEAAAAA==.Tazzar:BAABLgAECn8/AAIbAAkJoQ+lHwDBAQAbAAkJoQ+lHwDBAQAAAA==.',
Td='Tdjin:BAAALgAECgYJCQAAAA==.',
Te='Teddygraham:BAAALgADCgcJCAAAAA==.Teera:BAAALgADCgEJAQABLgAECgkJMwAKAMMSAA==.Tekêsh:BAABLgAECn8aAAMHAAcJvSNRBwBRAgAHAAcJvSNRBwBRAgAWAAYJKxVGmwAkAQAAAA==.Telarin:BAABLgAECn8eAAQFAAkJmRnCVACMAQAFAAcJ9RvCVACMAQASAAgJkA3iIACHAQARAAEJuAMXPgAiAAAAAA==.Tentpoles:BAAALgADCgEJAQAAAA==.',
Th='Thandor:BAAALgAECgUJEQAAAA==.Thebigdawg:BAABLgAFFH8FAAIkAAMJzBGlLwCtAAAkAAMJzBGlLwCtAAAAAA==.Thedeadangel:BAAALgADCgEJAQAAAA==.Thehonored:BAAALgADCgcJBwAAAA==.Theladyboy:BAAALgAECgkJDwAAAA==.Thomss:BAAALgADCgQJCAAAAA==.Throhk:BAAALgAECgEJAQAAAA==.Thuliaga:BAAALgAECgIJAgAAAA==.',
Ti='Tiamut:BAAALgAECgMJAwAAAA==.Tieeny:BAAALgAECgEJAQAAAA==.Tigerliley:BAAALgAECgYJEQABLgAECggJHAAMAIMSAA==.Tinneas:BAAALgADCgEJAgAAAA==.Titlepush:BAAALgAECgYJBgAAAA==.',
To='Tokenhealz:BAAALgAECgQJBAAAAA==.Tomie:BAAALgAECgIJAwAAAA==.Tomás:BAABLgAECn8fAAMeAAgJVBB4NwC3AQAeAAgJVBB4NwC3AQAhAAgJ4AxxNgBEAQAAAA==.Tonyhands:BAAALgADCgMJBgAAAA==.Tonyy:BAACLgAFFH8gAAIDAAYJsRyQCwCDAQADAAYJsRyQCwCDAQAuAAQKfzIAAgMACQnCIRUDADEDAAMACQnCIRUDADEDAAAA.Torstai:BAAALgAECgYJEQAAAA==.Totemthis:BAAALgADCgkJCQAAAA==.',
Tr='Trueshöt:BAABLgAECn8ZAAMSAAgJlx9kDQBDAgASAAgJXR5kDQBDAgARAAQJ1hzaQQBRAQAAAA==.',
Ts='Tserendolgor:BAABLgAECn8rAAQUAAgJCRzbDQAnAgAUAAgJCRzbDQAnAgAJAAMJ9Q/VsACjAAAQAAEJTRUwKQBAAAAAAA==.',
Tu='Tuskfury:BAAALgADCgcJDQAAAA==.',
Tw='Twinight:BAAALgAECgEJAQABLgAECggJHQAhAFcWAA==.Twinsha:BAABLgAECn8dAAMhAAgJVxbCJwCVAQAhAAgJVxbCJwCVAQAeAAcJJwS1WQAhAQAAAA==.Twín:BAAALgADCgYJCAABLgAECggJHQAhAFcWAA==.',
Ty='Tyranastrasz:BAAALgADCgMJAwAAAA==.Tyrannis:BAAALgAECgIJAgAAAA==.Tyrasong:BAAALgAECgMJBgAAAA==.Tyresious:BAABLgAECn8dAAIWAAgJwyAYHwB1AgAWAAgJwyAYHwB1AgAAAA==.',
['Tà']='Tàric:BAAALgAECgQJBQAAAA==.',
Un='Unauma:BAACLgAFFH8NAAIGAAQJwghXPACvAAAGAAQJwghXPACvAAAuAAQKfyAAAwYACQknHAMUAJcCAAYACQknHAMUAJcCACAABwmWHmILAAwCAAEuAAUUBQkKAB4AeRIA.Undeadpanda:BAAALgAECgIJAgABLgAECgUJEgABAAAAAA==.Unholydk:BAABLgAECn8UAAIJAAYJORX9ZQBBAQAJAAYJORX9ZQBBAQAAAA==.',
Ut='Utherrex:BAAALgAECgcJBwABLgAECgkJJgAdANARAA==.',
Va='Vaa:BAAALgAECgYJBgAAAA==.Vahaghn:BAACLgAFFH8HAAIaAAMJWSELEgAiAQAaAAMJWSELEgAiAQAuAAQKfzAAAhoACQk3IxcCAA4DABoACQk3IxcCAA4DAAAA.Valcerus:BAABLgAECn8WAAIEAAUJcxn0nAAlAQAEAAUJcxn0nAAlAQAAAA==.Valedus:BAABLgAECn8yAAIWAAkJWyQnBwAhAwAWAAkJWyQnBwAhAwAAAA==.Valhallæ:BAAALgAECgMJAwAAAA==.Validrela:BAAALgADCgIJBAAAAA==.Vampirism:BAAALgAECgUJBwABLgAECggJHAAkAEYeAA==.',
Ve='Veelete:BAAALgADCgkJEwABLgAECggJKAAXAMwbAA==.Veinyhawg:BAAALgAECgYJCQAAAA==.Velissena:BAAALgADCgIJAgABLgAECgkJOgAIAFAkAA==.Verguillas:BAAALgAECgIJAgAAAA==.Vespra:BAABLgAECn9EAAIeAAkJRyD/BwAdAwAeAAkJRyD/BwAdAwAAAA==.',
Vh='Vhas:BAAALgAECgkJEQAAAA==.Vhem:BAAALgAECgkJBwAAAA==.',
Vi='Viix:BAAALgAECgIJAgABLgAECgYJDAABAAAAAA==.Visage:BAAALgADCgQJBAAAAA==.',
Vo='Voidmommy:BAAALgADCgYJBgAAAA==.Voidweaver:BAAALgAECgUJBgAAAA==.Volcker:BAABLgAECn8wAAIHAAkJEwiUGwAhAQAHAAkJEwiUGwAhAQAAAA==.Voldamar:BAAALgAECgUJBQAAAA==.Voltashi:BAABLgAECn8wAAQlAAkJ5xSIFAD5AQAlAAkJ5xSIFAD5AQAVAAQJSBE9TgC1AAAkAAQJygkghgBVAAAAAA==.Voltuk:BAABLgAECn8cAAQPAAgJBBfbEgCnAQAPAAcJUBjbEgCnAQAOAAUJGxQNSAAOAQAaAAQJGhNzPAC4AAAAAA==.Volus:BAAALgADCgUJBQAAAA==.Vorp:BAAALgADCgYJBgAAAA==.',
Vy='Vyniellas:BAAALgADCgYJBgABLgAECgkJJQAFAKgeAA==.',
Wa='Wagyuboi:BAAALgAECgcJDwAAAA==.Wallypaly:BAABLgAECn8nAAMWAAgJDhaEfgBXAQAWAAcJVxeEfgBXAQAHAAUJ6RaXHwD9AAAAAA==.Walrustusk:BAAALgADCgYJCAAAAA==.Warbourne:BAAALgAECgIJAgAAAA==.Wariius:BAABLgAECn85AAIXAAgJFSAgCgDUAgAXAAgJFSAgCgDUAgAAAA==.Warwarb:BAAALgADCgYJCwABLgAECgkJNwAdAA8cAA==.Waterliliy:BAABLgAECn8cAAIMAAgJgxLNLABQAQAMAAgJgxLNLABQAQAAAA==.',
We='Weaveraz:BAAALgAECgIJAgAAAA==.',
Wh='Whatcrap:BAAALgAECgQJBAAAAA==.Whir:BAAALgADCgUJBQAAAA==.',
Wi='Windfurypie:BAAALgAECgkJBQAAAA==.',
Wo='Wolfbayin:BAAALgADCgYJCgAAAA==.Wolfbish:BAABLgAECn8mAAMFAAkJoBmeHABkAgAFAAkJoBmeHABkAgARAAYJkQtxHAC2AAAAAA==.Wongidan:BAAALgAECgIJAgAAAA==.Woofee:BAAALgADCgQJBwAAAA==.Woxy:BAAALgADCgMJAwAAAA==.',
Wt='Wtfwipeitup:BAAALgAECgMJAwAAAA==.',
Xa='Xanather:BAAALgADCgcJBwABLgAECgUJFgAEAHMZAA==.Xandrodron:BAAALgADCgUJBQAAAA==.',
Xe='Xelence:BAAALgAECgEJAgABLgAFFAMJCAAdAPsRAA==.Xenhaseo:BAABLgAECn8pAAIbAAgJTRmUGwDhAQAbAAgJTRmUGwDhAQAAAA==.',
Xh='Xhuri:BAAALgAECgIJBwAAAA==.',
Xi='Xilla:BAAALgAECgcJCAAAAA==.',
Xs='Xst:BAAALgADCgEJAQAAAA==.',
['Xë']='Xëna:BAABLgAECn8hAAIGAAYJbh/jJAASAgAGAAYJbh/jJAASAgAAAA==.',
Yo='Yorllik:BAAALgADCgcJIQAAAA==.Yougotwreckd:BAAALgAFFAMJAwAAAA==.',
Ys='Yserà:BAAALgAECgIJAgAAAA==.',
Yt='Yt:BAABLgAECn8bAAIJAAgJQBY/YgBLAQAJAAgJQBY/YgBLAQAAAA==.',
Za='Zaboomavoid:BAAALgADCgYJDAAAAA==.Zaes:BAABLgAECn8mAAIbAAkJJCGACgCXAgAbAAkJJCGACgCXAgAAAA==.Zaiene:BAAALgAECgIJAwABLgAECgYJEAABAAAAAA==.Zal:BAAALgADCggJEgAAAA==.Zarkhan:BAAALgAECgUJEgAAAA==.Zarulyn:BAAALgAECggJEQAAAA==.Zavadin:BAAALgAECgYJCQAAAA==.',
Ze='Zeffy:BAABLgAECn8WAAMcAAgJyg2DDQAkAQAbAAcJwgyzMwBDAQAcAAcJ5AqDDQAkAQAAAA==.Zeneras:BAAALgAECgYJCgAAAA==.',
Zh='Zhorvan:BAABLgAECn8oAAMeAAkJGBFXNwC3AQAeAAkJGBFXNwC3AQApAAgJrAYdFwAvAQAAAA==.',
Zi='Zigbis:BAAALgADCgYJBgAAAA==.Ziggleton:BAAALgADCgEJAQAAAA==.Zilstar:BAAALgAECgYJCgAAAA==.Zink:BAAALgADCgcJDgAAAA==.',
Zu='Zuginside:BAAALgADCgMJAwAAAA==.',
Zw='Zwolfe:BAAALgADCgQJBgAAAA==.',
Zy='Zya:BAAALgAECgEJAQAAAA==.',
['Âr']='Ârtëmïs:BAABLgAECn81AAIFAAgJ7g6CWwB6AQAFAAgJ7g6CWwB6AQAAAA==.',
['Äc']='Äcid:BAABLgAECn8sAAIeAAkJ1xspGQBnAgAeAAkJ1xspGQBnAgAAAA==.',
['Åp']='Åpollo:BAABLgAFFH8GAAIkAAMJvhR9LADBAAAkAAMJvhR9LADBAAAAAA==.',
['Èa']='Èastçoast:BAAALgADCgcJGQAAAA==.',
['Êl']='Êlydala:BAAALgAECgYJBwAAAA==.',
['Ðe']='Ðeja:BAAALgAECgMJBgAAAA==.',
['Ðè']='Ðèath:BAAALgAECgEJAQAAAA==.',
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
