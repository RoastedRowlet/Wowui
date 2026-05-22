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

local lookup = {'Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Blood','Mage-Frost','Hunter-BeastMastery','Druid-Restoration','Paladin-Protection','Priest-Holy','DemonHunter-Devourer','Druid-Balance','Druid-Feral','Priest-Shadow','Warrior-Protection','Warrior-Fury','DemonHunter-Vengeance','Hunter-Marksmanship','Hunter-Survival','Mage-Arcane','DemonHunter-Havoc','Monk-Windwalker','Paladin-Retribution','Paladin-Holy','DeathKnight-Frost','Warlock-Destruction','Warrior-Arms','Evoker-Augmentation','Evoker-Devastation','Warlock-Demonology','Shaman-Restoration','Druid-Guardian','Shaman-Elemental','Priest-Discipline','Rogue-Subtlety','Rogue-Assassination','Monk-Mistweaver','Monk-Brewmaster','Rogue-Outlaw','Warlock-Affliction','Evoker-Preservation','Mage-Fire','Shaman-Enhancement',}
local provider = {region='US',realm='Malygos',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aakkulay:BAAALgAECgEJAgABLgAECgUJCgABAAAAAA==.',
Ab='Absofsteels:BAABLgAECn8YAAMCAAYJshfqdAAwAQACAAYJshfqdAAwAQADAAEJ2guARwAnAAAAAA==.',
Ac='Acaric:BAABLgAECn8qAAIEAAkJLwX7hwAsAQAEAAkJLwX7hwAsAQAAAA==.Ache:BAAALgAFFAMJBAAAAA==.',
Ad='Adriel:BAAALgAECgYJCQAAAA==.Adrielon:BAAALgADCgYJCgAAAA==.Adøra:BAABLgAECn8dAAIFAAkJRBaDIgA2AgAFAAkJRBaDIgA2AgAAAA==.',
Ae='Aelanesh:BAAALgADCggJDQAAAA==.',
Ai='Aircann:BAAALgADCgMJAwAAAA==.Aireola:BAAALgADCgcJBwAAAA==.',
Ak='Akairo:BAAALgAECgcJCwABLgAECgkJGAAGAN0dAA==.Akata:BAAALgAECgYJAgAAAA==.',
Al='Alcaholic:BAAALgAECgEJAQABLgAECggJIgAHAIUfAA==.Alchemist:BAAALgADCgkJGgAAAA==.Alidor:BAAALgAECgMJBAAAAA==.Alistair:BAAALgAECgEJAwAAAA==.Allixis:BAAALgADCgMJAwAAAA==.Alluriel:BAAALgAECgQJCgAAAA==.Altharoth:BAAALgAECgQJCwAAAA==.',
Am='Amira:BAACLgAFFH8VAAIIAAUJ7CMaAgABAgAIAAUJ7CMaAgABAgAuAAQKfyUAAggACAmsJWoCAEUDAAgACAmsJWoCAEUDAAAA.Amorillis:BAAALgADCgcJDQAAAA==.Amphitrite:BAAALgADCgEJAQAAAA==.',
An='Anteiku:BAAALgAECgIJAwAAAA==.Anthiva:BAABLgAECn8TAAIJAAgJ+A08TQBOAQAJAAgJ+A08TQBOAQAAAA==.',
Ar='Arauial:BAAALgAECgcJEQAAAA==.Arcos:BAAALgADCgkJCQAAAA==.Aribella:BAACLgAFFH8IAAIFAAMJLhHiOADjAAAFAAMJLhHiOADjAAAuAAQKfykAAgUACAlmGbYgAEECAAUACAlmGbYgAEECAAAA.Arizann:BAABLgAECn8kAAQGAAcJ+x29FwBBAgAGAAcJ+x29FwBBAgAKAAMJ5gyCVQBgAAALAAEJyAuJMgAzAAAAAA==.Arobotpr:BAABLgAECn8nAAIMAAgJ3xkfEgDzAQAMAAgJ3xkfEgDzAQAAAA==.Artpandalay:BAAALgAECgQJBQAAAA==.',
As='Asima:BAAALgAECgEJAQAAAA==.Astaren:BAAALgAECgUJDgAAAA==.Asuran:BAABLgAECn8bAAMNAAcJMyQDBwBPAgANAAcJeSMDBwBPAgAOAAYJWx/BKQBiAQAAAA==.',
At='Atem:BAAALgAECgQJBwAAAA==.',
Au='Aulinn:BAAALgAECgEJAQAAAA==.Aurelianus:BAAALgAECgcJEwAAAA==.',
Av='Avalanche:BAAALgAECgUJCQAAAA==.',
Az='Azaris:BAABLgAECn80AAIMAAkJ2RgoDQAyAgAMAAkJ2RgoDQAyAgAAAA==.',
Ba='Baelrog:BAAALgAECgUJDAAAAA==.Bananaslamma:BAAALgADCgMJBQAAAA==.Bandalar:BAABLgAECn8dAAMJAAkJBBLrRwDUAQAJAAkJBBLrRwDUAQAPAAIJQgrcJgAsAAAAAA==.Baranina:BAACLgAFFH8OAAMFAAUJtiDHBwAnAQAFAAMJViHHBwAnAQAQAAMJQxxHFwCMAAAuAAQKfygABBAACAnTI4IOAM4CABAACAkdIoIOAM4CAAUABQmOHws2ANYBABEAAwkuIVcbAB8BAAAA.Barricaded:BAAALgAECgYJCAAAAA==.Bashems:BAAALgADCgcJCQABLgAECgMJCQABAAAAAA==.Battosi:BAAALgADCgIJAgAAAA==.',
Be='Bealzebuub:BAAALgAECgMJAwAAAA==.Bearpaws:BAAALgADCgQJBAAAAA==.Beastums:BAABLgAECn8nAAIRAAgJMhsxEADrAQARAAgJMhsxEADrAQAAAA==.Benji:BAEBLgAECn8VAAMEAAYJfBucnAAHAQAEAAYJfBucnAAHAQASAAEJeQYuIgAhAAAAAA==.',
Bi='Biggiecat:BAAALgADCgYJBgABLgAECgUJDgABAAAAAA==.Bigload:BAAALgADCgEJAQAAAA==.Bigunc:BAAALgAECgQJBgAAAA==.Bihgnuts:BAAALgAECgQJBgAAAA==.Bittybubble:BAAALgAECgEJAQAAAA==.',
Bl='Blazinitup:BAAALgADCgQJCQAAAA==.Blimey:BAAALgAECggJBgAAAA==.Blindaf:BAABLgAECn8WAAITAAYJCw3nIwDxAAATAAYJCw3nIwDxAAAAAA==.Blindcauze:BAAALgADCgEJAQAAAA==.Blindmonk:BAABLgAECn8aAAIUAAcJqhGxKQAbAQAUAAcJqhGxKQAbAQAAAA==.Blite:BAAALgADCgkJHAAAAA==.Bloodlòck:BAAALgADCgUJCgAAAA==.Bloodmary:BAABLgAECn8eAAMVAAkJZAU5dQA4AQAVAAkJZAU5dQA4AQAWAAQJQAevcgCxAAAAAA==.Bloombriar:BAAALgAECgEJAQAAAA==.Bloöm:BAACLgAFFH8OAAMGAAQJxgoGOACOAAAGAAMJ9QEGOACOAAAKAAMJtwFyKwB3AAAuAAQKfxsAAgYACAl8DzoyAI0BAAYACAl8DzoyAI0BAAAA.Blueeyearch:BAABLgAECn8UAAMQAAYJzx3eEAAGAQAFAAUJLCM8SwBmAQAQAAUJoRLeEAAGAQAAAA==.',
Bo='Bolgan:BAAALgAECgMJCAAAAA==.Bonedecay:BAAALgAECgEJAgAAAA==.Boomadk:BAACLgAFFH8OAAICAAQJXxWZOgBBAQACAAQJXxWZOgBBAQAuAAQKfx4AAwIACAlgIkUfAMYCAAIACAnZIUUfAMYCABcABwmfH9gCAHsCAAAA.Boomapriest:BAAALgAECgcJCQAAAA==.Boosh:BAAALgAECgIJAgAAAA==.Booshler:BAAALgAECgUJCgAAAA==.Booshlia:BAAALgAECgkJDgAAAA==.Booshly:BAAALgAECgUJBQAAAA==.Bootstrapbil:BAAALgADCgkJCgAAAA==.Bowjoemojo:BAAALgADCgIJAgAAAA==.Bowsho:BAAALgAECgQJBQAAAA==.',
Br='Bradburn:BAAALgAECgQJCAAAAA==.Brasserz:BAAALgAECgcJEQAAAA==.Brewswillis:BAAALgADCgYJBgAAAA==.Brice:BAAALgAECgUJDgAAAA==.Briochebun:BAABLgAECn8dAAIVAAkJsxvkIACnAgAVAAkJsxvkIACnAgAAAA==.',
Bu='Bustin:BAABLgAECn8aAAIVAAgJzR5hHABZAgAVAAgJzR5hHABZAgAAAA==.',
Bw='Bwangifer:BAABLgAECn8nAAIPAAgJSxm/BgDNAQAPAAgJSxm/BgDNAQAAAA==.',
['Bë']='Bëcky:BAAALgAFFAMJAwAAAA==.',
Ca='Caerus:BAAALgADCgYJDAABLgAECggJKQARANUfAA==.Caitriona:BAAALgADCgMJAwABLgADCgUJBwABAAAAAA==.Cannala:BAAALgADCgkJGAAAAA==.Cargae:BAAALgADCggJDQAAAA==.Cassios:BAABLgAECn8iAAIUAAgJUhkGEAD6AQAUAAgJUhkGEAD6AQAAAA==.',
Ce='Celathel:BAAALgAECgUJDAAAAA==.Cellysia:BAABLgAECn8eAAMIAAgJTQUYLwAMAQAIAAgJTQUYLwAMAQAMAAcJZQLDQgCqAAAAAA==.Celsìus:BAABLgAECn8XAAIEAAYJbhOg1QBEAQAEAAYJbhOg1QBEAQAAAA==.Ceramyth:BAAALgAECgQJDAAAAA==.Ceres:BAABLgAECn8nAAIYAAgJFRoFBAD7AQAYAAgJFRoFBAD7AQAAAA==.Cesara:BAABLgAECn8zAAMMAAkJlCDpBQC6AgAMAAkJlCDpBQC6AgAIAAEJ8gckfwAzAAAAAA==.',
Ch='Chaahck:BAAALgAECgMJAwAAAA==.Chal:BAAALgAECgUJBwAAAA==.Chbribs:BAAALgAECgUJDgAAAA==.Chichimounki:BAAALgADCgUJBQAAAA==.Chiptewth:BAAALgADCgEJAQAAAA==.',
Ci='Cinderella:BAABLgAECn8vAAIEAAgJRCGfGACNAgAEAAgJRCGfGACNAgAAAA==.',
Cl='Clumsey:BAAALgADCgEJAQAAAA==.',
Co='Cocoshan:BAAALgAECgcJDgAAAA==.Columbina:BAACLgAFFH8UAAIJAAUJwA86FAAwAQAJAAUJwA86FAAwAQAuAAQKfxoAAgkABwmgGbdEAOEBAAkABwmgGbdEAOEBAAAA.Comma:BAABLgAECn8UAAINAAcJFxKwHABjAQANAAcJFxKwHABjAQAAAA==.Cooperhowerd:BAAALgADCgkJHAAAAA==.Corn:BAABLgAECn8ZAAIVAAcJ5hVLUgCIAQAVAAcJ5hVLUgCIAQAAAA==.Couremese:BAAALgADCgYJBgAAAA==.',
Cr='Crackmonger:BAABLgAECn82AAMZAAkJbSIUAgDpAgAZAAkJbSIUAgDpAgANAAIJNRAWNABgAAAAAA==.Crackundead:BAAALgAECgQJBAAAAA==.Cravens:BAAALgAECgUJBQAAAA==.Craze:BAAALgADCgUJBQAAAA==.',
Cy='Cyphr:BAABLgAECn8nAAIGAAgJZB+yDQCrAgAGAAgJZB+yDQCrAgAAAA==.',
['Cë']='Cërbërus:BAAALgAECgQJBQAAAA==.',
Da='Dacs:BAAALgAECgQJEAAAAA==.Daen:BAAALgADCgcJCgAAAA==.Dagadus:BAAALgADCgYJCwAAAA==.Daggergarnet:BAAALgADCgYJBgAAAA==.Dajango:BAAALgAECgYJDQAAAA==.Damerot:BAAALgAFFAIJAgAAAA==.Dandity:BAAALgAECgcJCwAAAA==.Dangerous:BAAALgAECgEJAQAAAA==.Dangi:BAAALgADCgMJAwAAAA==.Dansharo:BAAALgAECgQJBgAAAA==.Darnel:BAAALgADCgQJBAAAAA==.',
De='Deadbeard:BAACLgAFFH8GAAICAAIJ7CK9eAC1AAACAAIJ7CK9eAC1AAAuAAQKfx8AAgIACAlQJX0KAOMCAAIACAlQJX0KAOMCAAAA.Deathknut:BAAALgADCggJCQAAAA==.Deathmethods:BAAALgAECgYJCgAAAA==.Deathviix:BAAALgADCgQJBgAAAA==.Dekillerty:BAAALgADCgYJCQAAAA==.Deli:BAAALgAECggJCwAAAA==.Delphina:BAAALgADCgQJAwAAAA==.Demini:BAAALgAECgQJBAAAAA==.Demisê:BAABLgAECn8ZAAMCAAgJexXyXwDTAQACAAgJexTyXwDTAQADAAUJhhEXJwDGAAAAAA==.Demonessa:BAAALgAECgcJEQAAAA==.Dermus:BAAALgADCgEJAQAAAA==.Deserter:BAABLgAECn8XAAMaAAcJkBFyKgA9AQAaAAcJVBFyKgA9AQAbAAYJtQz0HgA3AQAAAA==.Desso:BAABLgAECn8jAAIUAAcJ2RZ+GwCCAQAUAAcJ2RZ+GwCCAQAAAA==.Devilskin:BAAALgAECgQJBgAAAA==.',
Di='Dihhdevil:BAAALgAECgIJBAAAAA==.Dillinger:BAABLgAECn8bAAILAAYJDxf1DwBRAQALAAYJDxf1DwBRAQAAAA==.Dingodgaf:BAABLgAECn8cAAIVAAcJQQXzngDtAAAVAAcJQQXzngDtAAAAAA==.',
Do='Doomsdae:BAAALgAECgQJCgAAAA==.Doomstir:BAABLgAECn8dAAIEAAYJJxE8iQAqAQAEAAYJJxE8iQAqAQAAAA==.',
Dr='Dragonmynutz:BAAALgAECgYJBwAAAA==.Draknarok:BAABLgAECn8ZAAICAAgJohmQLwD6AQACAAgJohmQLwD6AQAAAA==.Dranius:BAACLgAFFH8GAAIEAAMJcgVKYgDZAAAEAAMJcgVKYgDZAAAuAAQKfxcAAgQACAnHEiSJAMABAAQACAnHEiSJAMABAAAA.Drayeda:BAAALgADCgMJAwAAAA==.Dreadlord:BAAALgADCgEJAQAAAA==.Dreamclaw:BAAALgAECgYJCwAAAA==.Dredda:BAAALgADCgEJAQAAAA==.Drendar:BAAALgADCgUJBQAAAA==.Drippindots:BAABLgAECn8mAAIcAAgJBhv5JgADAgAcAAgJBhv5JgADAgAAAA==.Driztette:BAABLgAECn8VAAIdAAYJCiLpGgAdAgAdAAYJCiLpGgAdAgAAAA==.Drnewport:BAAALgADCgkJDwAAAA==.Drock:BAAALgADCgIJAgAAAA==.Druidbearpig:BAAALgAECgEJAQABLgAECggJHgAcAGgSAA==.Drunkfuq:BAAALgAECgEJAQAAAA==.Drustor:BAAALgAECgYJBgAAAA==.Drystine:BAABLgAECn8mAAITAAgJgB50CQA3AgATAAgJgB50CQA3AgAAAA==.',
Du='Dubber:BAAALgADCggJCQAAAA==.',
['Dí']='Dín:BAAALgAECgEJAQAAAA==.',
Ed='Edd:BAAALgADCgYJBgAAAA==.',
Ee='Eedeeweewee:BAAALgADCgkJEwAAAA==.Eevee:BAAALgAECgYJCgAAAA==.',
Ei='Eillaura:BAABLgAECn8cAAIIAAkJcRLXEwDvAQAIAAkJcRLXEwDvAQAAAA==.',
El='Elipsis:BAABLgAECn8dAAIIAAkJqhNbLACVAQAIAAkJqhNbLACVAQAAAA==.Ellyn:BAAALgAECgYJBgAAAA==.Elm:BAABLgAECn8qAAQGAAgJIBaILgCiAQAGAAgJIBaILgCiAQAKAAcJVhFyJQBEAQAeAAEJ5BNeLwA4AAAAAA==.Elyas:BAAALgADCgEJAQAAAA==.Elybella:BAABLgAECn8aAAIFAAgJYBgFLwD1AQAFAAgJYBgFLwD1AQAAAA==.Elyssaelyend:BAAALgAECgYJCgABLgAECggJGwAGALwaAA==.',
Em='Emanon:BAAALgAECgQJBQAAAA==.Emmental:BAABLgAECn8XAAIfAAYJiBJdOQD4AAAfAAYJiBJdOQD4AAAAAA==.',
En='Endload:BAAALgADCgEJAQAAAA==.Enquea:BAAALgAECgYJEQAAAA==.Enricco:BAAALgAECgYJCwAAAA==.',
Er='Ereko:BAABLgAECn8fAAIFAAgJpg2KRgB1AQAFAAgJpg2KRgB1AQAAAA==.Erythorbic:BAABLgAECn8hAAMcAAgJ8RzeGQBOAgAcAAcJexzeGQBOAgAYAAMJQyCiLwD8AAAAAA==.',
Es='Estralage:BAAALgAECgUJCgAAAA==.',
Ev='Evictor:BAAALgAECgQJBQABLgAECggJDwABAAAAAA==.',
Ex='Exileelfsam:BAABLgAECn8oAAIRAAkJVwuLEgDOAQARAAkJVwuLEgDOAQAAAA==.',
Fa='Fallenrose:BAAALgAECgEJAQAAAA==.Fallensk:BAAALgADCgIJAgAAAA==.Faranth:BAAALgAECgIJAwAAAA==.Fargenstines:BAAALgADCgMJAwAAAA==.Fatass:BAAALgADCgUJBgAAAA==.Fatherrick:BAAALgAECgQJBAAAAA==.Faîle:BAACLgAFFH8cAAMgAAUJGxZPDQCjAQAgAAUJGxZPDQCjAQAMAAEJ1QG4KQA8AAAuAAQKfyoAAyAACAlEHycIAL0CACAACAlEHycIAL0CAAgABgkhCDNKABABAAAA.',
Fe='Feer:BAAALgAECgQJCAAAAA==.Feldron:BAABLgAECn8cAAMhAAkJZh3ACgDmAgAhAAgJGR7ACgDmAgAiAAEJgxjzHQA9AAAAAA==.Felshatter:BAAALgAECgYJEwAAAA==.Feltigress:BAABLgAECn8vAAILAAkJmyIRAQAZAwALAAkJmyIRAQAZAwAAAA==.Fendag:BAAALgADCgYJCAAAAA==.',
Ff='Ffugme:BAABLgAECn8eAAIHAAgJxwu5GQD3AAAHAAgJxwu5GQD3AAAAAA==.Ffugoff:BAAALgADCggJCAAAAA==.Ffugtard:BAAALgAECgcJEAAAAA==.Ffugyou:BAAALgADCgQJBAAAAA==.',
Fi='Fingerfister:BAAALgAECgQJBAABLgAECgYJBwABAAAAAA==.Finnian:BAABLgAECn8kAAIWAAgJOx6iDQBvAgAWAAgJOx6iDQBvAgAAAA==.Fio:BAACLgAFFH8GAAIjAAMJUh1GGAADAQAjAAMJUh1GGAADAQAuAAQKfyMAAyMACAn3JLMCAFoDACMACAn3JLMCAFoDABQAAQlJG0JwAFEAAAAA.Firiona:BAAALgAECgYJEAAAAA==.',
Fl='Flashferment:BAABLgAECn8ZAAIkAAgJzRfeGQCaAQAkAAgJzRfeGQCaAQAAAA==.Flinn:BAABLgAECn8dAAIeAAkJBx6lAwCaAgAeAAkJBx6lAwCaAgAAAA==.Flowers:BAABLgAECn8sAAMJAAgJJB9qEwBnAgAJAAgJJB9qEwBnAgATAAIJexkNMwCRAAAAAA==.Fläva:BAAALgAECgUJDAAAAA==.',
Fo='Forkinyou:BAAALgAECgQJBAAAAA==.',
Fr='Fracture:BAAALgADCgEJAQAAAA==.Fresca:BAAALgADCgEJAQAAAA==.Fridgerollin:BAAALgADCggJFgAAAA==.Frifrah:BAAALgAECgMJBAAAAA==.Frosht:BAABLgAECn8vAAIEAAkJBBqeIwBPAgAEAAkJBBqeIwBPAgAAAA==.',
Fu='Furysbubble:BAAALgAECgEJAQAAAA==.',
['Fö']='Föx:BAAALgADCgEJAQABLgAECgYJDwABAAAAAA==.',
Ga='Gafocalypse:BAAALgAECgUJBwAAAA==.Garddidit:BAAALgADCgUJBQABLgAECggJHAAPAOMbAA==.',
Gl='Glonor:BAAALgAECgQJBgAAAA==.',
Go='Goldberg:BAAALgADCgcJDQAAAA==.Goopmaster:BAAALgADCgUJBQAAAA==.Goovs:BAAALgAECgEJAQAAAA==.',
Gr='Grabmytusk:BAAALgADCgcJBwAAAA==.Gramthyr:BAAALgADCgkJHAAAAA==.Grep:BAAALgAECgIJAgAAAA==.Grotok:BAABLgAECn8UAAMCAAgJVwreagBGAQACAAgJVwreagBGAQAXAAEJAABxFgA3AAAAAA==.',
Gu='Guacamole:BAAALgAECgUJBQAAAA==.Gub:BAAALgAECgMJAwAAAA==.Gumer:BAAALgAECgYJBwAAAA==.Gurgatron:BAAALgAECgcJBwAAAA==.',
Ha='Halraku:BAAALgADCgEJAQAAAA==.Halsin:BAAALgADCgQJBAAAAA==.Halygos:BAAALgAECgYJCQAAAA==.Halygosa:BAAALgAECgEJAQAAAA==.Hasklaufien:BAAALgAECgIJBQAAAA==.',
He='Herpecluster:BAAALgAECgcJBgAAAA==.',
Hi='Hinderberg:BAAALgADCgMJAwAAAA==.',
Ho='Holyraz:BAAALgADCgMJAwAAAA==.Holystrikes:BAAALgADCgYJCwAAAA==.',
Hu='Hugulin:BAABLgAECn8YAAIFAAcJ3Qb2eQDrAAAFAAcJ3Qb2eQDrAAAAAA==.',
Ic='Icedsoul:BAAALgAECgYJEgAAAA==.Icee:BAAALgADCgcJCgAAAA==.',
Ig='Iggey:BAABLgAECn8vAAIZAAkJixwvBACPAgAZAAkJixwvBACPAgAAAA==.',
Ik='Ikkaku:BAAALgAECgEJAQAAAA==.',
Il='Ilandras:BAABLgAECn8lAAIJAAcJOg9QWwAkAQAJAAcJOg9QWwAkAQAAAA==.Illadus:BAABLgAECn8VAAIJAAgJmAVZcQDsAAAJAAgJmAVZcQDsAAAAAA==.Illed:BAAALgADCgcJBwAAAA==.',
In='Indra:BAAALgAECgYJCAAAAA==.Intoxicated:BAABLgAECn8ZAAIUAAYJRwrmNADfAAAUAAYJRwrmNADfAAAAAA==.',
Io='Ione:BAAALgADCgcJBAAAAA==.',
Ir='Iranna:BAACLgAFFH8SAAQiAAUJuxxQAgBkAQAiAAQJ0hpQAgBkAQAlAAQJERosAwA/AQAhAAIJiBRnJgBVAAAuAAQKfzEABCIACAmQJb0BAKUCACUACAlwI0YBAN8CACIABwn2IL0BAKUCACEABwkkIDELACUCAAAA.Irondihh:BAAALgAECgMJAwAAAA==.',
Iu='Iudi:BAAALgAECgQJBAABLgAECgkJGAAGAN0dAA==.',
Iy='Iyasu:BAAALgADCgQJBAAAAA==.',
Ja='Jachan:BAAALgADCgkJDwAAAA==.Jackblãck:BAAALgAECgQJBQABLgAECggJHQACAGAeAA==.Janaki:BAABLgAECn8XAAMGAAgJ7Rd1GQAyAgAGAAgJ7Rd1GQAyAgAKAAIJLQhkbgApAAAAAA==.',
Je='Jestêr:BAAALgAECgYJBgABLgAFFAUJHAAgABsWAA==.',
Jo='Joenutter:BAAALgAECgMJBgAAAA==.Joia:BAAALgADCgQJBAAAAA==.Jonnyquestt:BAABLgAECn8zAAIVAAkJ5BOmNADmAQAVAAkJ5BOmNADmAQAAAA==.',
Ju='Juicie:BAAALgAECgUJCgAAAA==.Junrage:BAAALgADCgMJAwABLgAFFAUJFQAOABkeAA==.Junrush:BAAALgAECggJDgABLgAFFAUJFQAOABkeAA==.',
['Jè']='Jèstèr:BAAALgADCgkJCQABLgAFFAUJHAAgABsWAA==.',
Ka='Kalea:BAAALgAECgIJBwAAAA==.Kalecgo:BAAALgAECgMJAwABLgAECgcJEwABAAAAAA==.Kanaezz:BAAALgADCggJCAAAAA==.Kat:BAAALgAECggJEwAAAA==.Katsuko:BAABLgAECn8oAAIDAAgJIRmBDQDbAQADAAgJIRmBDQDbAQAAAA==.Kattnirra:BAABLgAECn8aAAIFAAgJdgy/VgBEAQAFAAgJdgy/VgBEAQAAAA==.Katze:BAABLgAECn8+AAIFAAkJJxU9JQD8AQAFAAkJJxU9JQD8AQAAAA==.Kaylé:BAAALgAECgQJBQAAAA==.',
Ke='Keannor:BAAALgADCgMJAwAAAA==.Keco:BAAALgADCgcJBwAAAA==.Keepper:BAABLgAECn8oAAIcAAkJ8RDyOwCsAQAcAAkJ8RDyOwCsAQAAAA==.Kelaatun:BAAALgAECgEJAgAAAA==.Kennan:BAAALgADCgIJAgAAAA==.Kenslynn:BAABLgAECn8WAAIIAAgJRRDPJQBOAQAIAAgJRRDPJQBOAQAAAA==.Ketheric:BAAALgAECgMJAwAAAA==.',
Ki='Killahaseo:BAAALgADCgkJDgABLgAECgcJIQAaAAUZAA==.Killmoedee:BAABLgAECn8iAAIHAAgJhR/vBABeAgAHAAgJhR/vBABeAgAAAA==.Kitwryn:BAAALgADCgUJBQAAAA==.',
Kk='Kkaell:BAAALgAECgQJCgABLgAECgYJBwABAAAAAA==.',
Kl='Klexios:BAAALgAECgUJDgAAAA==.',
Ko='Koopa:BAAALgAECgQJBQAAAA==.Korbandallas:BAAALgAECgMJBAAAAA==.',
Kr='Kracious:BAAALgAECgQJBAAAAA==.Kraulhoof:BAAALgAECgEJAQABLgAECgYJBwABAAAAAA==.Krispy:BAAALgAECgcJBwAAAA==.Krymson:BAAALgAECgYJBwAAAA==.',
Ku='Kui:BAABLgAECn8nAAIkAAgJfxryDwACAgAkAAgJfxryDwACAgAAAA==.Kurtcobrain:BAAALgAECgYJCQAAAA==.',
['Kö']='Köz:BAAALgADCgkJDAAAAA==.',
La='Laetri:BAABLgAECn8jAAIJAAkJ2BRBMAC7AQAJAAkJ2BRBMAC7AQAAAA==.Lasttok:BAABLgAECn8ZAAMLAAcJTCK8BwD5AQALAAYJXiO8BwD5AQAKAAIJvBO8TgB4AAAAAA==.Laylene:BAAALgAECgYJDgAAAA==.Lazloo:BAABLgAECn8jAAMOAAgJUyVMBQDSAgAOAAgJFiVMBQDSAgAZAAcJOhx9DQC6AQAAAA==.Lazymidget:BAABLgAECn8eAAIQAAcJFR1VLQDFAQAQAAcJFR1VLQDFAQAAAA==.',
Le='Leaana:BAAALgADCgUJBQAAAA==.Leftÿ:BAAALgAECgIJAgABLgAECgkJOwARAAoUAA==.Legindkiller:BAAALgADCgkJHAAAAA==.Lenie:BAAALgADCgYJBgABLgAFFAcJHAAGABYfAA==.',
Li='Lightace:BAABLgAECn8VAAIVAAYJBAhDowDlAAAVAAYJBAhDowDlAAAAAA==.Lilyia:BAAALgADCgcJDAAAAA==.Linkkil:BAABLgAECn8WAAIRAAgJpSC4BgB+AgARAAgJpSC4BgB+AgAAAA==.',
Lo='Loastotem:BAAALgADCgcJBwAAAA==.Lobos:BAABLgAECn8bAAIcAAgJBQfZcAAcAQAcAAgJBQfZcAAcAQAAAA==.Lokni:BAAALgAECgYJBwAAAA==.Lostdraco:BAAALgAECgcJEwAAAA==.Lostdream:BAAALgAECgcJEwAAAA==.Loun:BAABLgAECn8eAAIkAAYJbRmeIABkAQAkAAYJbRmeIABkAQAAAA==.Lowku:BAAALgAECgEJAQAAAA==.Lowrise:BAAALgADCgkJCgAAAA==.',
Lu='Luciellia:BAAALgAECgEJAQAAAA==.Luiss:BAAALgAECgMJAwAAAA==.Luken:BAAALgADCggJFgAAAA==.Luminara:BAAALgADCgcJDAAAAA==.Luminism:BAAALgADCgYJCAABLgAECgYJFQAjAL4fAA==.Luvlycruelty:BAAALgADCgUJBwAAAA==.',
Ly='Lyn:BAEBLgAECn8zAAIkAAkJICZtAABzAwAkAAkJICZtAABzAwAAAA==.',
Ma='Mackenziiee:BAABLgAECn8pAAIFAAkJKxu/GQA/AgAFAAkJKxu/GQA/AgAAAA==.Mackthyra:BAAALgADCgcJBwAAAA==.Madglowup:BAAALgAECgYJDAAAAA==.Magicbunga:BAAALgADCgIJAgAAAA==.Magicwater:BAABLgAECn8gAAIEAAkJhhwLHgBtAgAEAAkJhhwLHgBtAgAAAA==.Magtaki:BAAALgAECgkJBwAAAA==.Magyar:BAAALgAECgUJBQAAAA==.Maizepriest:BAABLgAECn8lAAIMAAcJziEpDQAyAgAMAAcJziEpDQAyAgAAAA==.Mannysaf:BAABLgAECn8dAAIOAAgJjg21KQBiAQAOAAgJjg21KQBiAQAAAA==.Manter:BAAALgADCgIJAgAAAA==.Mariota:BAAALgAECgQJAwABLgAFFAYJEQAEADAaAA==.Marus:BAAALgADCgMJAwAAAA==.',
Me='Mechalia:BAAALgADCgQJBAAAAA==.Mellowblink:BAABLgAECn8hAAIEAAgJ2BMIVgCYAQAEAAgJ2BMIVgCYAQAAAA==.Mellowlink:BAABLgAECn8mAAIhAAcJGhtgEgC/AQAhAAcJGhtgEgC/AQAAAA==.Melorian:BAAALgADCgkJEAAAAA==.Memeñtomori:BAAALgAECgYJCAAAAA==.Menara:BAAALgAECgYJCwAAAA==.Metaviix:BAAALgAECgQJBAAAAA==.',
Mi='Micromancer:BAAALgADCgMJAwAAAA==.Midnightmage:BAAALgAECgUJBgAAAA==.Migglet:BAAALgAECgIJAgAAAA==.Milkyboy:BAAALgADCgQJBAAAAA==.Millhi:BAAALgAECgcJBwAAAA==.Mimi:BAACLgAFFH8eAAQQAAgJJiJDAQCJAgAQAAgJpCBDAQCJAgAFAAMJMiXCOwDYAAARAAMJmiOeFgDQAAAuAAQKfzYABBAACQmCJu0DAGUDABAACAkCJu0DAGUDABEABwnGJSMHAHYCAAUABglKJFU9AJYBAAAA.Mintyice:BAAALgAECgcJBgAAAA==.Miramage:BAAALgAECgQJCQABLgAECgkJMgAhAMAXAA==.Miravus:BAABLgAECn8yAAMhAAkJwBfaEQDGAQAhAAkJJRfaEQDGAQAiAAUJSRJqCwA2AQAAAA==.Mirlanda:BAABLgAECn8VAAIiAAYJDgW6EADVAAAiAAYJDgW6EADVAAAAAA==.Misttie:BAAALgAECggJEwABLgAECgkJHQAIAKoTAA==.',
Mo='Monkerick:BAAALgAECgUJCgAAAA==.Moonana:BAAALgADCgIJAgAAAA==.Morber:BAAALgAECgEJAQAAAA==.Morphingtime:BAAALgADCgIJAgAAAA==.Mowte:BAAALgADCgkJHAAAAA==.',
Mu='Murkoobi:BAAALgAECgIJAgAAAA==.Mursk:BAAALgAECgIJAgAAAA==.',
My='Myhoovesrhot:BAAALgAECgIJAgAAAA==.Mystrial:BAAALgAECgEJAgAAAA==.Mystáke:BAAALgAECgkJEQAAAA==.',
['Mä']='Mäble:BAAALgADCgYJBwAAAA==.',
['Mê']='Mêrcy:BAAALgADCgYJBgAAAA==.',
['Mò']='Mòus:BAAALgAECgYJEwAAAA==.',
['Mó']='Mómo:BAAALgAECgQJBAAAAA==.Móus:BAAALgAECgUJCwABLgAECgYJEwABAAAAAA==.',
Na='Narcissus:BAAALgADCggJFgAAAA==.Narivia:BAAALgAECgUJBgABLgAFFAUJHAAgABsWAA==.Naro:BAAALgAECgYJBgABLgAECggJLwAEAEQhAA==.Nathadon:BAAALgAECgEJAQAAAA==.Nathalin:BAABLgAECn8cAAMeAAYJkBc8GQAHAQAeAAUJthc8GQAHAQALAAUJqg4yIADeAAAAAA==.',
Ne='Necrotis:BAAALgADCgkJHAAAAA==.Nectarion:BAAALgAECgEJAQAAAA==.Neftearii:BAAALgADCgEJAQAAAA==.Nevelia:BAABLgAECn8xAAMIAAgJFybJAQBoAwAIAAgJFybJAQBoAwAMAAUJwxoQNwA1AQAAAA==.Neytholy:BAAALgAECgcJDAAAAA==.Nezukô:BAAALgAECgcJCAAAAA==.',
Ni='Nienna:BAAALgAECgIJAgAAAA==.Nitalan:BAAALgAECgIJAgAAAA==.Nithenseth:BAAALgADCggJDQAAAA==.Nixk:BAAALgAECgYJDwAAAA==.',
No='Noavail:BAAALgADCgMJAwAAAA==.Noixi:BAAALgAECgMJCwAAAA==.Noraldrys:BAAALgADCgcJDQAAAA==.Noralyne:BAAALgAECgUJCwAAAA==.Noras:BAAALgAECggJDwAAAA==.Noraxia:BAAALgADCgkJEAAAAA==.Nordicslayer:BAABLgAECn8kAAIZAAgJNRJOEQCHAQAZAAgJNRJOEQCHAQAAAA==.Notagnoblin:BAEALgAFFAMJAwABLgAFFAQJDwAkAC4mAA==.',
Ny='Nysonia:BAAALgAECgcJBwAAAA==.',
Ob='Obnyxion:BAABLgAECn8mAAIbAAkJGQ68BgCVAQAbAAkJGQ68BgCVAQAAAA==.',
Oc='Octuroun:BAAALgAECgcJDgAAAA==.',
Od='Oddsoul:BAAALgAECgQJCgAAAA==.',
Og='Ogrelurd:BAAALgAECgcJEQAAAA==.',
Oh='Ohlordy:BAAALgAECgcJCgAAAA==.',
Ol='Oliveia:BAAALgADCgcJCgAAAA==.',
Om='Omontanha:BAAALgAECgUJBwAAAA==.',
On='Oniryoshi:BAAALgAECgQJBAAAAA==.Onlyzugs:BAAALgADCgEJAgAAAA==.',
Op='Ophelia:BAABLgAECn8zAAQmAAgJpiINBgC2AQAcAAcJwh3TLQDiAQAmAAYJmSINBgC2AQAYAAEJpgiYdAAwAAAAAA==.',
Or='Orakwa:BAAALgAECgYJEwAAAA==.',
Ou='Outen:BAAALgAECgcJBwAAAA==.',
Oz='Ozzieliem:BAAALgAECgEJAQAAAA==.',
Pa='Pakleader:BAAALgADCgIJAgAAAA==.Pallinda:BAABLgAECn8cAAMVAAgJvhMjhgBuAQAVAAgJvhMjhgBuAQAWAAYJkw+zNwAdAQAAAA==.Panakananama:BAAALgAECgcJDgAAAA==.Panz:BAABLgAECn8eAAMaAAcJ8QkPOQDyAAAaAAcJ3QgPOQDyAAAbAAEJIA7WHAA1AAAAAA==.Papablock:BAAALgADCgMJAwAAAA==.Papalock:BAAALgADCgYJBgAAAA==.Papiperkins:BAAALgAECgEJAQAAAA==.Pappyoblues:BAAALgAECgYJBgAAAA==.Papster:BAAALgADCgYJBgAAAA==.Parati:BAAALgAECgIJAgAAAA==.Paylot:BAAALgAECgIJAgAAAA==.',
Pe='Peachmangogt:BAAALgADCgUJBgAAAA==.Pendulum:BAAALgADCgkJCwAAAA==.Pendulumlaw:BAAALgAECgYJCAAAAA==.Pennypacker:BAAALgAECgcJCwAAAA==.Personality:BAAALgADCggJCAAAAA==.Petmycat:BAAALgAECgYJEwAAAA==.',
Ph='Phara:BAABLgAECn8ZAAQMAAgJcAo8JQBKAQAMAAgJcAo8JQBKAQAgAAUJZgirNgDwAAAIAAIJlAFvfAA3AAAAAA==.Phenomenon:BAAALgADCgUJBQAAAA==.Phoel:BAAALgADCggJCQAAAA==.Phoopanchu:BAABLgAECn8cAAIjAAgJthFXJQBwAQAjAAgJthFXJQBwAQAAAA==.',
Pi='Pibble:BAAALgADCgMJAwAAAA==.Pinkbuns:BAABLgAECn8jAAIEAAcJ7xjZTwCqAQAEAAcJ7xjZTwCqAQAAAA==.Pirimus:BAAALgADCgEJAQAAAA==.',
Pn='Pneuma:BAABLgAECn8bAAIPAAYJ9SK7BQDvAQAPAAYJ9SK7BQDvAQAAAA==.',
Po='Pofella:BAAALgAECgMJAwAAAA==.Pokinsmot:BAAALgADCgYJCwAAAA==.Pollonius:BAAALgADCgIJAgAAAA==.Popsy:BAABLgAECn8WAAIVAAgJ2AoQhgAXAQAVAAgJ2AoQhgAXAQAAAA==.',
Pr='Precarity:BAAALgAECgEJAQAAAA==.Prenton:BAABLgAECn8pAAIOAAgJOR8sCgB7AgAOAAgJOR8sCgB7AgAAAA==.Pretzel:BAAALgADCgUJBQABLgAFFAQJBwACAK0aAA==.Prideflag:BAAALgAECgMJAwAAAA==.Primaldead:BAABLgAECn85AAIcAAgJlxI4PACrAQAcAAgJlxI4PACrAQAAAA==.Profundity:BAAALgAECgYJDAAAAA==.',
Pu='Punchmyface:BAAALgADCgUJCAAAAA==.Puny:BAABLgAECn8dAAICAAgJYB4GJgAkAgACAAgJYB4GJgAkAgAAAA==.',
Qe='Qeini:BAABLgAECn8tAAIgAAgJgRkqDABWAgAgAAgJgRkqDABWAgAAAA==.',
Ra='Radrin:BAAALgADCgkJGQAAAA==.Rafoff:BAAALgAECgUJDgAAAA==.Rahll:BAAALgADCgkJHAAAAA==.Rancoramble:BAABLgAECn8XAAIDAAkJDAQyIAD8AAADAAkJDAQyIAD8AAAAAA==.Randis:BAABLgAECn8pAAMCAAgJBwzdWwBrAQACAAgJBwzdWwBrAQAXAAYJoQI6FwCQAAAAAA==.Ranekk:BAAALgAECgEJAQAAAA==.Razglaive:BAAALgADCgYJBgAAAA==.Razhunt:BAAALgAECgUJCgAAAA==.Razonghoul:BAABLgAECn83AAICAAkJcCGWCwDYAgACAAkJcCGWCwDYAgAAAA==.',
Re='Redheat:BAAALgADCgUJBQAAAA==.Redwyn:BAAALgADCgMJAwAAAA==.Reemonhunter:BAAALgAECgEJAgAAAA==.Regarded:BAAALgADCgcJBwAAAA==.Renge:BAAALgADCgEJAQAAAA==.Rengår:BAAALgAECgUJCwAAAA==.Renx:BAAALgAECgQJBQAAAA==.Reticent:BAAALgAECgUJCgAAAA==.Rexiis:BAABLgAECn8eAAMcAAgJaBK6RACOAQAcAAgJaBK6RACOAQAmAAEJAABdNAAzAAAAAA==.Reyth:BAAALgAECgUJDQAAAA==.',
Rh='Rhaul:BAAALgAECgEJAQAAAA==.Rhuby:BAAALgADCgkJDwAAAA==.Rhyl:BAABLgAECn8fAAIhAAcJOiC9EACcAgAhAAcJOiC9EACcAgAAAA==.',
Ri='Rimos:BAAALgADCgUJBQAAAA==.Ripcord:BAAALgADCggJDQAAAA==.Riptîde:BAABLgAECn8iAAIfAAgJnA08KwBBAQAfAAgJnA08KwBBAQAAAA==.',
Ro='Rockadin:BAABLgAECn8aAAIVAAYJQBRefQAoAQAVAAYJQBRefQAoAQAAAA==.Rosael:BAAALgADCgYJDAAAAA==.Roundhouse:BAAALgAECgcJCAAAAA==.',
Ru='Rubbmytotems:BAAALgAECgYJDwAAAA==.Rulen:BAAALgADCgMJCQAAAA==.Ruleti:BAABLgAECn8lAAMFAAgJhhUiMQDFAQAFAAgJhhUiMQDFAQAQAAIJrQn8egBXAAAAAA==.Rumí:BAABLgAECn8gAAIJAAkJUAnNTwBGAQAJAAkJUAnNTwBGAQAAAA==.Russell:BAAALgADCgkJGQAAAA==.Rutgore:BAABLgAECn8sAAIhAAkJbR2EBgCBAgAhAAkJbR2EBgCBAgAAAA==.',
Rx='Rx:BAAALgAECgUJBQAAAA==.',
Sa='Sabado:BAAALgAECgQJDAAAAA==.Safewerd:BAEALgAECggJEgAAAA==.Saitáma:BAAALgADCgQJBAAAAA==.Samíra:BAAALgAECgMJBAAAAA==.Santapaws:BAAALgAECgMJAwAAAA==.Santrious:BAAALgAECgUJCgAAAA==.Sarahfi:BAAALgAECgMJBAAAAA==.Saraisabella:BAAALgADCgMJAwAAAA==.Saralanna:BAAALgAECgUJBwAAAA==.Sarasophie:BAAALgADCgUJBQAAAA==.Sarcastrophe:BAAALgADCgMJAwAAAA==.Sarefina:BAAALgAECgcJEwAAAA==.Sathenazarke:BAACLgAFFH8HAAMnAAMJ0QWiGACpAAAnAAMJ0QWiGACpAAAbAAIJ3QuBBgCWAAAuAAQKfzAABCcACQnCGNIRACECACcACAnkGNIRACECABsABwmeH68DABICABoABwncGqEbAOsBAAEuAAUUBQkSACIAuxwA.Saths:BAAALgADCgEJAQABLgAECggJEwABAAAAAA==.',
Sc='Schallue:BAABLgAECn8gAAIoAAgJkAh7BABHAQAoAAgJkAh7BABHAQAAAA==.Schism:BAAALgADCgkJJAAAAA==.Scoban:BAACLgAFFH8eAAIWAAYJFiSuAgBIAgAWAAYJFiSuAgBIAgAuAAQKfyoAAhYACAl4IQsOAKgCABYACAl4IQsOAKgCAAAA.Scylla:BAAALgAECgUJDAAAAA==.',
Se='Selithel:BAABLgAECn8XAAITAAgJ3gfYHQAjAQATAAgJ3gfYHQAjAQAAAA==.Serioussurv:BAAALgAECgUJBwAAAA==.Setsunachan:BAAALgADCgIJAgABLgAECggJKAADACEZAA==.',
Sh='Shadeebear:BAAALgADCgMJAwAAAA==.Shadowmander:BAABLgAECn8WAAQMAAcJtgYmQQCyAAAMAAYJowcmQQCyAAAgAAUJUQX8PACpAAAIAAEJFgEsYwAaAAAAAA==.Shaeliana:BAAALgAECgQJDgAAAA==.Shalera:BAAALgAECgcJBwAAAA==.Shaohlin:BAAALgAECgQJBAAAAA==.Shaqfu:BAAALgADCgkJHAAAAA==.Shavemybush:BAAALgAECgEJAQAAAA==.Shiggyloo:BAAALgAECggJAQAAAA==.Shigure:BAABLgAECn8bAAIEAAgJnQl6dgBNAQAEAAgJnQl6dgBNAQAAAA==.Shivers:BAAALgAECgUJCAAAAA==.Shnow:BAAALgAECgkJEwAAAA==.Sholin:BAABLgAECn8ZAAIkAAcJ7BkeFwCzAQAkAAcJ7BkeFwCzAQAAAA==.Shomea:BAAALgAECgUJDgAAAA==.Shugz:BAAALgADCgkJHAAAAA==.Shumai:BAAALgAECgUJBQAAAA==.',
Si='Sikotick:BAABLgAECn8fAAIGAAgJmR4sEACOAgAGAAgJmR4sEACOAgAAAA==.Sikxbetrayer:BAAALgAECgcJDwAAAA==.Siliconista:BAABLgAECn8zAAIEAAkJzyClEADDAgAEAAkJzyClEADDAgAAAA==.Silverbolt:BAABLgAECn8YAAIOAAcJ3QzKMwArAQAOAAcJ3QzKMwArAQAAAA==.Simbelmyne:BAAALgAECgQJBAAAAA==.Sinderone:BAACLgAFFH8XAAIWAAYJohBnCADHAQAWAAYJohBnCADHAQAuAAQKf0AAAxYACQl/Hz8EAB0DABYACQl/Hz8EAB0DABUABQn9F4abAPMAAAAA.',
Sk='Skaaduush:BAAALgAECgYJDAAAAA==.Skypaw:BAAALgAECgEJAwAAAA==.',
Sl='Slavon:BAABLgAECn8sAAICAAkJFB3ZHQDOAgACAAkJFB3ZHQDOAgAAAA==.Sleepylune:BAAALgAECgMJBQAAAA==.Slippie:BAAALgADCgQJAgAAAA==.Sllew:BAABLgAECn8iAAICAAgJ0CGeFACLAgACAAgJ0CGeFACLAgAAAA==.Slothfu:BAAALgAECgEJAQAAAA==.Slèw:BAAALgAECgQJBAAAAA==.',
Sm='Smitestuff:BAAALgAECgYJDwAAAA==.Smoulder:BAAALgAECgYJBwAAAA==.',
Sn='Snaka:BAAALgAECgEJAQAAAA==.Snigles:BAABLgAECn8ZAAIiAAcJRhHmCABuAQAiAAcJRhHmCABuAQAAAA==.',
So='Sokrash:BAAALgADCgcJDQAAAA==.Somannita:BAAALgADCgcJBwAAAA==.Souei:BAAALgADCgEJAQABLgAECggJFAACAFcKAA==.Soulgiver:BAAALgAECgMJAwAAAA==.',
Sp='Spartos:BAAALgAECgQJCAAAAA==.Sposi:BAEBLgAECn8lAAIDAAcJ0iGACQArAgADAAcJ0iGACQArAgAAAA==.Spraynpray:BAAALgAECgYJCQAAAA==.',
Sr='Srimrithyu:BAAALgAECgEJAQAAAA==.',
Ss='Sselionn:BAAALgAECgUJEAAAAA==.',
St='Stabathaa:BAAALgAECgUJCQAAAA==.Stomps:BAABLgAECn8VAAIOAAgJxRq8EwAJAgAOAAgJxRq8EwAJAgAAAA==.',
Su='Subliminal:BAABLgAECn8WAAMhAAgJ7xJCJQDPAQAhAAgJ7xJCJQDPAQAlAAEJswzuGAAyAAAAAA==.',
Sv='Svartalfar:BAAALgADCgMJAQAAAA==.',
Sy='Syravia:BAABLgAECn8YAAIVAAcJbQWIpgDgAAAVAAcJbQWIpgDgAAAAAA==.',
['Sé']='Séraphyne:BAAALgAECgUJDAAAAA==.',
Ta='Talarin:BAAALgAECgYJDgAAAA==.Tameka:BAAALgAECgQJBgAAAA==.Tardis:BAAALgAECgkJBQAAAA==.Tatersmonk:BAECLgAFFH8PAAIkAAQJLiYJBQDCAQAkAAQJLiYJBQDCAQAuAAQKfyMAAiQACQnpJLsDAFQDACQACQnpJLsDAFQDAAAA.Tavinrayn:BAAALgAECgcJCwAAAA==.Tazzar:BAABLgAECn8nAAIaAAgJJghCMAAdAQAaAAgJJghCMAAdAQAAAA==.',
Td='Tdjin:BAAALgAECgYJCQAAAA==.',
Te='Teddygraham:BAAALgADCgcJCAAAAA==.Teera:BAAALgADCgEJAQABLgAECggJKgAGACAWAA==.Tekêsh:BAAALgAECgcJEwAAAA==.Telarin:BAABLgAECn8cAAQFAAgJfxhpPQCVAQAFAAcJ9RtpPQCVAQARAAYJlQs8KQABAQAQAAEJuAOjMwAmAAAAAA==.Tentpoles:BAAALgADCgEJAQAAAA==.',
Th='Thandor:BAAALgAECgUJDgAAAA==.Thehonored:BAAALgADCgcJBwAAAA==.Theladyboy:BAAALgAECgkJDwAAAA==.Thomss:BAAALgADCgQJCAAAAA==.Throhk:BAAALgADCgYJCgAAAA==.Thuliaga:BAAALgAECgIJAgAAAA==.',
Ti='Tiamut:BAAALgAECgMJAwAAAA==.Tieeny:BAAALgAECgEJAQAAAA==.Tigerliley:BAAALgAECgYJBwABLgAECgcJGQAMAMMRAA==.Tinneas:BAAALgADCgEJAQAAAA==.Titlepush:BAAALgAECgYJBgAAAA==.',
To='Tokenhealz:BAAALgAECgQJBAAAAA==.Tomie:BAAALgAECgEJAQAAAA==.Tomás:BAABLgAECn8YAAMdAAcJUBAQNACEAQAdAAcJUBAQNACEAQAfAAYJMw5mOgDzAAAAAA==.Tonyhands:BAAALgADCgMJBgAAAA==.Tonyy:BAACLgAFFH8aAAIDAAUJ+h4mCgBRAQADAAUJ+h4mCgBRAQAuAAQKfzIAAgMACQnCIRUDADEDAAMACQnCIRUDADEDAAAA.Torstai:BAAALgAECgUJDgAAAA==.Totemthis:BAAALgADCgkJCQAAAA==.',
Tr='Trueshöt:BAAALgAECggJEwAAAA==.',
Ts='Tserendolgor:BAABLgAECn8hAAQTAAgJeRqoDgDWAQATAAgJeRqoDgDWAQAPAAEJTRUwKQBAAAAJAAEJ9AHb8QAZAAAAAA==.',
Tu='Tuskfury:BAAALgADCgcJDQAAAA==.',
Tw='Twinight:BAAALgAECgEJAQABLgAECggJHQAfAFYWAA==.Twinsha:BAABLgAECn8dAAMfAAgJVhY2HQCiAQAfAAgJVhY2HQCiAQAdAAcJJwS1WQAhAQAAAA==.Twín:BAAALgADCgYJCAABLgAECggJHQAfAFYWAA==.',
Ty='Tyranastrasz:BAAALgADCgMJAwAAAA==.Tyrasong:BAAALgAECgMJBQAAAA==.Tyresious:BAABLgAECn8WAAIVAAcJ2x8xKQAUAgAVAAcJ2x8xKQAUAgAAAA==.',
['Tà']='Tàric:BAAALgAECgEJAQAAAA==.',
Un='Unauma:BAACLgAFFH8NAAIGAAQJwgi+IgD4AAAGAAQJwgi+IgD4AAAuAAQKfxkAAwYACAknHjAUAGMCAAYACAknHjAUAGMCAB4AAgnbIKEiALcAAAAA.Undeadpanda:BAAALgAECgIJAgABLgAECgUJCgABAAAAAA==.Unholydk:BAAALgAECgYJDgAAAA==.',
Va='Vaa:BAAALgADCgcJEwAAAA==.Vahaghn:BAABLgAECn8tAAIZAAkJNyPxAQDvAgAZAAkJNyPxAQDvAgAAAA==.Valcerus:BAAALgAECgUJDgAAAA==.Valedus:BAABLgAECn8vAAIVAAkJWySbAwA8AwAVAAkJWySbAwA8AwAAAA==.Validrela:BAAALgADCgIJAgAAAA==.Vampirism:BAAALgAECgUJBwABLgAECgYJFQAjAL4fAA==.',
Ve='Veelete:BAAALgADCgkJEwABLgAECgcJIQAWAKcdAA==.Veinyhawg:BAAALgAECgYJCQAAAA==.Velissena:BAAALgADCgIJAgABLgAECggJMQAIABcmAA==.Vespra:BAABLgAECn8/AAIdAAkJRyB/BAAoAwAdAAkJRyB/BAAoAwAAAA==.',
Vh='Vhas:BAAALgAECgkJDwAAAA==.Vhem:BAAALgAECgkJAwAAAA==.',
Vi='Viix:BAAALgAECgIJAgABLgAECgYJDAABAAAAAA==.Visage:BAAALgADCgQJBAAAAA==.',
Vo='Voidmommy:BAAALgADCgYJBgAAAA==.Voidweaver:BAAALgAECgUJBgAAAA==.Volcker:BAABLgAECn8pAAIHAAgJfwd1GwDlAAAHAAgJfwd1GwDlAAAAAA==.Voltashi:BAABLgAECn8kAAQkAAgJmBTxGQCZAQAkAAgJmBTxGQCZAQAjAAQJygk/YABSAAAUAAEJBAt7gAAwAAAAAA==.Voltuk:BAAALgAECgcJBwABLgAECgcJBwABAAAAAA==.Volus:BAAALgADCgUJBQAAAA==.Vorp:BAAALgADCgYJBgAAAA==.',
Vy='Vyniellas:BAAALgADCgYJBgABLgAECgkJGQAFAPQbAA==.',
Wa='Wagyuboi:BAAALgAECgYJCwAAAA==.Wallypaly:BAABLgAECn8nAAMVAAgJDhZwWgB0AQAVAAcJVxdwWgB0AQAHAAUJ6RbqGAD/AAAAAA==.Walrustusk:BAAALgADCgYJCAAAAA==.Warbourne:BAAALgAECgIJAgAAAA==.Wariius:BAABLgAECn8qAAIWAAcJFR4qEABOAgAWAAcJFR4qEABOAgAAAA==.Warwarb:BAAALgADCgYJCwABLgAECgYJCQABAAAAAA==.Waterliliy:BAABLgAECn8ZAAIMAAcJwxHMLgBrAQAMAAcJwxHMLgBrAQAAAA==.',
Wh='Whir:BAAALgADCgUJBQAAAA==.',
Wi='Windfurypie:BAAALgAECgkJBQAAAA==.',
Wo='Wolfbayin:BAAALgADCgYJCgAAAA==.Wolfbish:BAABLgAECn8fAAMFAAgJjhXyKwDcAQAFAAgJjhXyKwDcAQAQAAYJkQtQFwC6AAAAAA==.Wongidan:BAAALgAECgIJAgAAAA==.Woofee:BAAALgADCgQJBwAAAA==.Woxy:BAAALgADCgMJAwAAAA==.',
Wt='Wtfwipeitup:BAAALgAECgMJAwAAAA==.',
Xa='Xanather:BAAALgADCgcJBwABLgAECgUJDgABAAAAAA==.Xandrodron:BAAALgADCgUJBQAAAA==.',
Xe='Xelence:BAAALgADCgQJBAABLgAECggJJgAcAAYbAA==.Xenhaseo:BAABLgAECn8hAAIaAAcJBRkjHQCcAQAaAAcJBRkjHQCcAQAAAA==.',
Xh='Xhuri:BAAALgAECgIJBwAAAA==.',
Xi='Xilla:BAAALgAECgcJCAAAAA==.',
Xs='Xst:BAAALgADCgEJAQAAAA==.',
['Xë']='Xëna:BAABLgAECn8VAAIGAAYJhR2YIgDvAQAGAAYJhR2YIgDvAQAAAA==.',
Yo='Yorllik:BAAALgADCgcJGgAAAA==.Yougotwreckd:BAAALgAECgYJCgAAAA==.',
Ys='Yserà:BAAALgAECgIJAgAAAA==.',
Yt='Yt:BAABLgAECn8aAAIJAAcJQhf6XwAYAQAJAAcJQhf6XwAYAQAAAA==.',
Za='Zaboomavoid:BAAALgADCgYJDAAAAA==.Zaes:BAABLgAECn8mAAIaAAkJJCHvBwCbAgAaAAkJJCHvBwCbAgAAAA==.Zaiene:BAAALgAECgIJAwABLgAECgYJCwABAAAAAA==.Zal:BAAALgADCggJEgAAAA==.Zarkhan:BAAALgAECgUJCgAAAA==.Zarulyn:BAAALgAECgYJCQAAAA==.Zavadin:BAAALgAECgYJCQAAAA==.',
Ze='Zeffy:BAAALgAECgcJDwAAAA==.Zeneras:BAAALgAECgYJCgAAAA==.',
Zh='Zhorvan:BAABLgAECn8fAAMdAAgJMxScQgB2AQAdAAYJOBOcQgB2AQApAAgJqgaTEAAyAQAAAA==.',
Zi='Zigbis:BAAALgADCgYJBgAAAA==.Ziggleton:BAAALgADCgEJAQAAAA==.Zilstar:BAAALgAECgYJCAAAAA==.Zink:BAAALgADCgcJDgAAAA==.',
Zu='Zuginside:BAAALgADCgMJAwAAAA==.',
Zw='Zwolfe:BAAALgADCgQJBgAAAA==.',
Zy='Zya:BAAALgAECgEJAQAAAA==.',
['Âr']='Ârtëmïs:BAABLgAECn8rAAIFAAgJ7g51RgB1AQAFAAgJ7g51RgB1AQAAAA==.',
['Äc']='Äcid:BAABLgAECn8sAAIdAAkJ1xtTEQByAgAdAAkJ1xtTEQByAgAAAA==.',
['Åp']='Åpollo:BAAALgAFFAMJAwAAAA==.',
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
