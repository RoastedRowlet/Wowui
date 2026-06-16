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

local lookup = {'Monk-Windwalker','Priest-Holy','Monk-Mistweaver','Evoker-Preservation','Evoker-Augmentation','Druid-Feral','DeathKnight-Blood','DemonHunter-Havoc','Unknown-Unknown','DemonHunter-Devourer','Druid-Guardian','Monk-Brewmaster','Mage-Frost','Paladin-Protection','Warrior-Fury','Warrior-Arms','Warlock-Affliction','Rogue-Subtlety','Warrior-Protection','Hunter-BeastMastery','Hunter-Survival','DeathKnight-Unholy','Druid-Restoration','Shaman-Enhancement','Paladin-Holy','Priest-Discipline','Priest-Shadow','Rogue-Assassination','Rogue-Outlaw','Warlock-Demonology','Warlock-Destruction','Druid-Balance','Shaman-Restoration','Paladin-Retribution','DeathKnight-Frost','Evoker-Devastation','Hunter-Marksmanship','Shaman-Elemental','DemonHunter-Vengeance',}
local provider = {region='US',realm='ScarletCrusade',name='US',type='weekly',zone=46,date='2026-06-13',data={Ac='Acefu:BAABLgAECn8WAAIBAAgJeSKECAC8AgABAAgJeSKECAC8AgAAAA==.Acornella:BAABLgAFFH8FAAICAAUJAROZEABGAQACAAUJAROZEABGAQABLgAFFAYJBwADAK4GAA==.Acorneo:BAABLgAFFH8HAAIDAAYJrgacKAAbAQADAAYJrgacKAAbAQAAAA==.Acornita:BAACLgAFFH8MAAMEAAQJsw1aEQCsAAAEAAMJ5w9aEQCsAAAFAAIJXwKtWgBjAAAuAAQKfyoAAwQACQnlD0YRACgCAAQACQnlD0YRACgCAAUABwlIEgokAJ0BAAEuAAUUBgkHAAMArgYA.',
Ad='Adoreith:BAAALgAECgEJAQAAAA==.',
Ae='Aelana:BAAALgADCgkJCQAAAA==.Aeria:BAAALgADCgYJBgAAAA==.Aeriith:BAAALgAECgEJAQAAAA==.',
Ah='Ahyoka:BAAALgAFFAEJAgAAAA==.',
Ai='Ailanthus:BAABLgAECn8kAAIGAAgJgxIuEgCSAQAGAAgJgxIuEgCSAQAAAA==.',
Ak='Akinira:BAECLgAFFH8QAAIHAAQJ5RsoGAAhAQAHAAQJ5RsoGAAhAQAuAAQKfz4AAgcACQmVHgEJAIICAAcACQmVHgEJAIICAAAA.',
Al='Aleinadris:BAAALgADCgQJBAAAAA==.Alendy:BAAALgAECgYJBgAAAA==.Alikchi:BAAALgADCgEJAgAAAA==.Alloisaber:BAAALgAECgYJCAAAAA==.Alternis:BAAALgAECgMJAwAAAA==.Alunne:BAAALgAECgEJAQAAAA==.',
An='Andrelsia:BAAALgAECgYJCQAAAA==.Andrilla:BAAALgAECgcJEAAAAA==.Ankeseth:BAAALgAECgcJCAAAAA==.',
Ap='Apôllyon:BAACLgAFFH8OAAIIAAMJASS6EgALAQAIAAMJASS6EgALAQAuAAQKfy4AAggACQmeJfAAAL4DAAgACQmeJfAAAL4DAAAA.',
Ar='Aracelis:BAAALgAECgcJBwAAAA==.Aradius:BAAALgAECgEJAgABLgAECgIJBgAJAAAAAA==.Archertower:BAAALgADCgUJBQAAAA==.Artemiswynd:BAAALgAECgUJCAAAAA==.Arén:BAABLgAECn8pAAMKAAkJch/bFgCLAgAKAAkJMB3bFgCLAgAIAAcJhx+YGwDkAQAAAA==.',
As='Ashenshugär:BAAALgAECgQJCAAAAA==.Aszun:BAAALgAECgEJAQAAAA==.',
Av='Avadda:BAABLgAECn8YAAILAAcJthE8EgBPAQALAAcJthE8EgBPAQABLgAECgkJMwAMABwRAA==.',
Az='Azmar:BAABLgAECn83AAINAAgJpSIXGgC7AgANAAgJpSIXGgC7AgAAAA==.',
Ba='Badffinger:BAAALgADCgYJCQAAAA==.Badtouchbull:BAAALgADCgcJBwAAAA==.Balain:BAAALgAECgUJCQABLgAECgcJGgAMAN8NAA==.Bayorn:BAAALgAECgYJBwAAAA==.',
Be='Bear:BAAALgADCgcJBwAAAA==.Bearmont:BAABLgAECn8mAAIOAAcJ/RkAEQCwAQAOAAcJ/RkAEQCwAQAAAA==.Bearzerk:BAABLgAECn8mAAIPAAkJCBRkJADRAQAPAAkJCBRkJADRAQAAAA==.Beastmonk:BAAALgADCgEJAQAAAA==.Benathar:BAABLgAECn8oAAINAAkJJw2CYgC3AQANAAkJJw2CYgC3AQAAAA==.',
Bi='Bifrost:BAAALgAECgcJCwAAAA==.Bionico:BAABLgAECn8YAAIQAAYJpxN/KQAjAQAQAAYJpxN/KQAjAQAAAA==.Birgir:BAAALgAECgUJCAABLgAECgcJGAARAHIgAA==.',
Bl='Blackmagék:BAAALgADCgkJCQAAAA==.Bladestormer:BAAALgADCgYJBQAAAA==.Blazer:BAABLgAFFH8FAAIKAAMJowi3bQCoAAAKAAMJowi3bQCoAAAAAA==.Blightbeard:BAAALgAECgEJAQAAAA==.Bloodrager:BAAALgADCgIJAgAAAA==.Bloodthorn:BAABLgAECn8cAAISAAgJJgZ+LwAfAQASAAgJJgZ+LwAfAQAAAA==.Blortimor:BAAALgADCgcJBwAAAA==.',
Bo='Bombad:BAABLgAECn8UAAQPAAgJchJpLgCWAQAPAAgJPhJpLgCWAQATAAMJNgsxPgB0AAAQAAEJdQzwegAsAAAAAA==.Boomnescient:BAABLgAECn8dAAIUAAcJhAfnjwAaAQAUAAcJhAfnjwAaAQAAAA==.Bortt:BAAALgAECgQJBQAAAA==.Bozscaggs:BAABLgAECn9IAAMUAAkJkBMkMwALAgAUAAkJkBMkMwALAgAVAAUJAwPuQwCvAAAAAA==.',
Br='Bramis:BAAALgADCgkJHAAAAA==.Brantu:BAAALgADCgQJCAABLgAECgEJAQAJAAAAAA==.Braultus:BAABLgAECn8yAAIHAAkJfx26CgBjAgAHAAkJfx26CgBjAgAAAA==.Breuddwydwr:BAAALgADCgEJAQAAAA==.Brewmeupbro:BAAALgAECgEJAQABLgAECgkJIgAWAFMcAA==.Breyastrasza:BAAALgAECgQJBAAAAA==.Brood:BAAALgAECgYJCwAAAA==.Bruceleroy:BAAALgAECgEJAQAAAA==.Bruinn:BAAALgAECgQJBAABLgAECgcJGgAMAN8NAA==.',
Bu='Burstangel:BAAALgAECgYJCAAAAA==.',
By='Byrddh:BAAALgADCgQJBAAAAA==.',
['Bä']='Bäguette:BAAALgADCgEJAgAAAA==.',
Ca='Cadenza:BAAALgAECgcJEAAAAA==.Caelthar:BAAALgAECgUJCAAAAA==.Caliopedk:BAACLgAFFH8HAAMHAAIJrRiEOQBLAAAWAAIJrRjjOACqAAAHAAIJqAKEOQBLAAAuAAQKfxsAAxYACAlIIWUhALsCABYACAlIIWUhALsCAAcABQlJDjQqAO0AAAAA.Caliseni:BAAALgADCgYJCwAAAA==.Capra:BAAALgAECgYJCAAAAA==.Carillanklip:BAAALgADCgUJBQAAAA==.Caydenza:BAAALgAECgMJAwAAAA==.',
Cd='Cdmickey:BAAALgADCgUJBQAAAA==.',
Ce='Celestè:BAAALgAECggJEQAAAA==.Celéste:BAAALgAECgkJEAAAAA==.Cerdwin:BAAALgAECggJEQABLgAECgkJPgAXABkXAA==.',
Ch='Charferad:BAAALgAECgcJDgAAAA==.Chatter:BAAALgADCgMJAwAAAA==.Cheaptrick:BAAALgADCgcJEwAAAA==.Chibeard:BAABLgAECn8nAAIMAAkJtSKGAwAWAwAMAAkJtSKGAwAWAwAAAA==.Chihîro:BAAALgAECgUJBQAAAA==.Chonglin:BAAALgADCgMJAwAAAA==.Chrysopteron:BAAALgAECgEJAQABLgAECgEJAQAJAAAAAA==.',
Cl='Clearcast:BAAALgADCgkJCQAAAA==.Clevercrane:BAAALgAFFAIJAgABLgAFFAMJBQAFAFgYAA==.Clubsdh:BAAALgAECgMJBAAAAA==.',
Co='Collosus:BAAALgAFFAEJAQABLgAFFAMJCAAPALoTAA==.Coolbro:BAAALgADCgIJAgABLgADCggJCAAJAAAAAA==.Corialis:BAAALgAFFAEJAQAAAA==.Counsel:BAAALgAECgUJBQAAAA==.',
Cr='Criantha:BAAALgADCgIJAgAAAA==.Crom:BAACLgAFFH8FAAIYAAIJpQVUFQB9AAAYAAIJpQVUFQB9AAAuAAQKfzUAAhgACQniD5oOAMMBABgACQniD5oOAMMBAAAA.Crosis:BAAALgADCgYJBgAAAA==.Cruelladvoid:BAAALgAECgQJBAAAAA==.Cruush:BAAALgAECgYJBQAAAA==.',
Cu='Culerro:BAAALgAECgYJAwABLgAECgYJBQAJAAAAAA==.Cursive:BAAALgADCgUJDQAAAA==.',
Cy='Cygnes:BAABLgAECn8iAAIWAAkJUxyYJQBsAgAWAAkJUxyYJQBsAgAAAA==.',
Da='Daddywarrior:BAAALgADCgUJBgAAAA==.Daeva:BAAALgADCgEJAQAAAA==.Dantey:BAAALgADCgcJFAAAAA==.Daus:BAAALgAFFAEJAQAAAA==.Dazanna:BAABLgAECn82AAMZAAkJPxy3CgDfAgAZAAkJPxy3CgDfAgAOAAUJTAsZNQCJAAAAAA==.Dazre:BAAALgAECgUJBgAAAA==.',
De='Deeminor:BAAALgADCgkJEwAAAA==.Demeisen:BAAALgAECgcJDAAAAA==.Desktop:BAABLgAECn87AAMaAAkJUBw8CADwAgAaAAkJUBw8CADwAgAbAAYJdREzOQAsAQAAAA==.',
Di='Digon:BAAALgAECgEJAQAAAA==.Diod:BAABLgAECn9AAAITAAkJHRUEEgDGAQATAAkJHRUEEgDGAQAAAA==.Divineßovine:BAAALgADCgcJBwAAAA==.',
Do='Doombarker:BAAALgADCgYJBgAAAA==.Doomtheory:BAAALgAECgMJAwAAAA==.Dorammu:BAAALgAECgEJAQAAAA==.',
Dr='Dracovoid:BAAALgADCgYJBwAAAA==.Dracvoker:BAAALgAECgQJCAABLgAECgkJKQAKAHIfAA==.Draegyns:BAAALgAECgIJAgABLgAFFAYJFAAcAJgTAA==.Draehton:BAAALgAECgYJBwABLgAFFAQJCwAVAH4XAA==.Dragyns:BAACLgAFFH8UAAMcAAYJmBPhBAA3AQASAAUJyQ+BGgA+AQAcAAQJbRbhBAA3AQAuAAQKfzEABBwACQngG4ECAMoCABwACQmxGYECAMoCABIABgmMGz8sAJwBAB0AAwmrFFIJANwAAAAA.Dragynseye:BAAALgADCgIJAgABLgAFFAYJFAAcAJgTAA==.Drayper:BAABLgAECn81AAQCAAkJNiFhAwBYAwACAAkJNiFhAwBYAwAaAAEJZw3AWQAvAAAbAAEJaQVvkAAnAAAAAA==.Drayperbark:BAAALgAECgUJBQAAAA==.Druugal:BAACLgAFFH8OAAISAAQJGhriFwBLAQASAAQJGhriFwBLAQAuAAQKfy8AAxIACQlwH0YMANQCABIACQlwH0YMANQCABwAAQl6C+ofADMAAAAA.',
Du='Dubs:BAABLgAECn8wAAQeAAkJ6hr2PwDcAQAeAAYJwBr2PwDcAQAfAAIJ7hnSIgCVAAARAAIJwxt2KgBKAAAAAA==.Dunbarke:BAABLgAECn8YAAIRAAcJciBYCADeAQARAAcJciBYCADeAQAAAA==.Dustrat:BAAALgADCgIJAgAAAA==.',
Ef='Efishient:BAABLgAECn8eAAIXAAYJWCTdHgBIAgAXAAYJWCTdHgBIAgABLgAFFAYJGQAXAH8TAA==.',
El='Elendrisa:BAAALgAECgIJAgAAAA==.Elisoria:BAAALgAECgMJAwAAAA==.Elliwynd:BAABLgAECn8uAAIXAAkJGRSkIQA4AgAXAAkJGRSkIQA4AgAAAA==.',
Eo='Eoshot:BAAALgAECgUJCAAAAA==.',
Er='Erinnys:BAABLgAECn9BAAMIAAkJ5hYYDwAxAgAIAAkJ5hYYDwAxAgAKAAYJsgWPlgDvAAAAAA==.Ermoril:BAAALgAECgUJBgAAAA==.Ernesta:BAAALgADCgcJCAAAAA==.Eroksix:BAAALgADCgEJAQAAAA==.',
Eu='Eufemia:BAAALgAECgYJCQAAAA==.',
Ev='Evonnya:BAAALgAECgUJBQAAAA==.',
['Eø']='Eøs:BAAALgAECgEJAQAAAA==.',
Fa='Famine:BAAALgAECgcJDAAAAA==.',
Fe='Feelmebro:BAAALgADCggJCAAAAA==.Felern:BAAALgAECgcJCwABLgAECggJNwANAKUiAA==.Feyrun:BAAALgADCgkJEwABLgAECgcJDQAJAAAAAA==.Feyrè:BAAALgAECgEJAgAAAA==.',
Fi='Fightswiftjr:BAAALgADCgYJBgAAAA==.Finalomega:BAABLgAECn8YAAIHAAYJLBhTHwBYAQAHAAYJLBhTHwBYAQAAAA==.Finnshot:BAAALgAECgcJBwAAAA==.Finrod:BAAALgAECgYJBgAAAA==.',
Fl='Flaminfalcon:BAABLgAFFH8FAAIbAAIJQBjZKQCmAAAbAAIJQBjZKQCmAAABLgAFFAMJBQAFAFgYAA==.Flody:BAAALgAFFAEJAQAAAA==.',
Fo='Foxflame:BAABLgAECn8+AAMXAAkJGRdiHwBIAgAXAAkJGRdiHwBIAgAgAAgJPhDYJwCNAQAAAA==.',
Fr='Franzen:BAAALgAECgQJCQAAAA==.Freakbob:BAAALgADCgYJCQAAAA==.Froglocky:BAABLgAECn8/AAMRAAkJ+RYXBgAdAgARAAkJ+RYXBgAdAgAeAAMJcwRi9ABwAAAAAA==.Fronsac:BAAALgADCgQJBAAAAA==.',
Fu='Fulanita:BAABLgAECn8fAAMgAAcJBxBXNQA9AQAgAAcJBxBXNQA9AQAXAAIJSwolvwBEAAAAAA==.',
Ga='Gallager:BAAALgADCgMJAwAAAA==.Garzok:BAABLgAECn8qAAMRAAkJXwxVCwCjAQARAAkJXwxVCwCjAQAeAAMJzQHnCAFLAAAAAA==.',
Ge='Genkithered:BAABLgAECn81AAIhAAkJoxycDQDmAgAhAAkJoxycDQDmAgAAAA==.',
Gi='Gilaras:BAAALgAECgYJCAAAAA==.Gilernil:BAAALgAECgYJEwAAAA==.',
Gl='Gladtohelp:BAAALgAECgIJAgAAAA==.',
Gn='Gnoquarter:BAAALgADCgIJAgAAAA==.',
Go='Gourak:BAAALgAECgYJBgAAAA==.',
Gr='Gravemarks:BAABLgAECn8YAAMdAAgJqBMDCQCbAQAdAAgJqBMDCQCbAQAcAAQJzAncEQDoAAAAAA==.Grimhorn:BAABLgAECn8jAAMgAAcJsAcWUwC9AAAgAAYJDAgWUwC9AAALAAIJWQNJeAAnAAAAAA==.Grimlie:BAAALgAECgEJAQAAAA==.Grimmrock:BAAALgAECgcJDgAAAA==.Grumblen:BAAALgADCgMJAwAAAA==.',
Gu='Guaritrice:BAABLgAECn8aAAMbAAcJdgv1OwAfAQAbAAcJdgv1OwAfAQACAAEJYQedeAAfAAAAAA==.Gubb:BAAALgAECgMJAwAAAA==.',
Gw='Gwenylane:BAABLgAECn8sAAIiAAkJSAvjcQCHAQAiAAkJSAvjcQCHAQAAAA==.Gwindor:BAAALgAECgYJCQAAAA==.Gwyndelyn:BAABLgAECn8xAAIBAAgJ9wtuMwAzAQABAAgJ9wtuMwAzAQAAAA==.',
Ha='Hatterus:BAABLgAECn9FAAIiAAkJTw4vYgCqAQAiAAkJTw4vYgCqAQAAAA==.',
He='Herculeze:BAABLgAFFH8GAAIZAAIJ7xqINACYAAAZAAIJ7xqINACYAAAAAA==.Hessian:BAAALgADCgEJAQAAAA==.Hetairoi:BAAALgAECgIJAgABLgAFFAMJCwABAP0iAA==.Hetd:BAAALgAECgEJAwABLgAFFAMJCwABAP0iAA==.',
Hi='Hillbroken:BAABLgAECn9QAAIjAAkJqSI7AgDuAgAjAAkJqSI7AgDuAgAAAA==.',
Ho='Hohalt:BAAALgAECgEJAgAAAA==.Holycross:BAAALgAECgIJAgAAAA==.Holysmokers:BAAALgAECgYJDAABLgAFFAYJFAAcAJgTAA==.Holysnow:BAAALgADCgkJDAABLgAFFAIJBAAJAAAAAA==.Holysoul:BAAALgAECgEJAwAAAA==.',
Hu='Huntertidus:BAAALgAECggJDQABLgAECgkJKgAiAJobAA==.Huntrix:BAAALgAECgcJCQAAAA==.',
Hy='Hydan:BAAALgADCgIJAgAAAA==.',
['Hà']='Hànks:BAABLgAECn8gAAIiAAkJ7g0lZAClAQAiAAkJ7g0lZAClAQAAAA==.',
Ib='Ibíng:BAAALgAECgYJBwAAAA==.',
Ic='Iceatron:BAAALgADCgUJBQAAAA==.',
Im='Imo:BAABLgAECn8qAAMeAAkJIRGGUgCjAQAeAAkJyQ6GUgCjAQAfAAUJIhLCJQCBAAAAAA==.',
In='Intrepidz:BAAALgAECgEJAgABLgAFFAMJBQAFAFgYAA==.Inèvitable:BAABLgAECn9CAAIWAAkJHh3rIgB4AgAWAAkJHh3rIgB4AgAAAA==.',
Ir='Ironphant:BAAALgAECgYJBgAAAA==.',
Is='Istara:BAAALgAECgQJBAAAAA==.',
Iv='Ivorin:BAAALgAECgYJCgAAAA==.',
Ja='Jabujabu:BAAALgAECgcJBwABLgAFFAMJBgAKAKMRAA==.Javeech:BAABLgAECn8nAAMUAAkJzhkjKwAtAgAUAAgJDRwjKwAtAgAVAAEJFQrgYAA3AAAAAA==.',
Je='Jebib:BAAALgAECgYJBgABLgAFFAkJKgAXAOkdAA==.Jeod:BAAALgAECgYJCQAAAA==.',
Jo='Jolty:BAACLgAFFH8ZAAIWAAYJUSCKIgDYAQAWAAYJUSCKIgDYAQAuAAQKfykAAxYACQlWIq8MADUDABYACQlWIq8MADUDAAcABAmkFsQxANMAAAAA.Joydivision:BAAALgADCgIJAgAAAA==.',
Ju='Julian:BAAALgAECggJCAABLgAECgkJPwASACwkAA==.',
['Jð']='Jð:BAAALgAECgQJBAABLgAECgYJJQAKAGAhAA==.',
Ka='Kaboomchickn:BAAALgAECgIJAgABLgAECgcJDgAJAAAAAA==.Kaiou:BAAALgADCgQJCAAAAA==.Kantor:BAABLgAECn9RAAMCAAkJLhgvFgAdAgACAAkJLhgvFgAdAgAbAAIJvQvAgwAzAAAAAA==.Karboomkin:BAABLgAFFH8GAAMLAAUJQhRnEQDzAAALAAQJQhRnEQDzAAAgAAEJAACsVwAAAAABLgAFFAgJGwAiAN0gAA==.Karnstein:BAABLgAECn8oAAQkAAgJ4BHtCwBQAQAkAAYJuxDtCwBQAQAFAAYJBxHxSQAAAQAEAAUJgwTuMwDOAAAAAA==.Kasenko:BAAALgAECgIJAgABLgAECgYJHQALAMIXAA==.Kasryna:BAABLgAECn8dAAILAAYJwhf4HgBQAQALAAYJwhf4HgBQAQAAAA==.Kathinja:BAABLgAECn8oAAIUAAkJCQmNWQCTAQAUAAkJCQmNWQCTAQAAAA==.Katiebeary:BAAALgAECgcJCwAAAA==.',
Ke='Kelthera:BAAALgAECgYJBgAAAA==.Kelumbria:BAAALgAECggJDgAAAA==.Keta:BAAALgADCgYJBgAAAA==.Ketameanie:BAABLgAECn85AAIKAAkJQBfiJAA4AgAKAAkJQBfiJAA4AgAAAA==.',
Ki='Kieran:BAAALgAECgQJCgAAAA==.Killerkitten:BAAALgADCgEJAQAAAA==.Kitsunè:BAAALgAECgEJAQAAAA==.',
Km='Kmazing:BAABLgAECn8rAAMBAAkJFg4MJgCBAQABAAkJFg4MJgCBAQADAAMJIRBeewCiAAAAAA==.',
Kn='Knifèparty:BAABLgAECn85AAIcAAkJkSL8AQDOAgAcAAkJkSL8AQDOAgAAAA==.',
Ko='Konoha:BAABLgAECn8sAAMaAAkJzyAJBgAhAwAaAAkJwh8JBgAhAwACAAMJfiPoQwApAQAAAA==.',
Ku='Kultag:BAABLgAECn8fAAIiAAkJBRZAOgAXAgAiAAkJBRZAOgAXAgAAAA==.',
Ky='Kyaw:BAABLgAECn8WAAQSAAYJbRyAKAC2AQASAAYJbRyAKAC2AQAcAAIJxRJbFgCTAAAdAAEJPRS5IgA6AAAAAA==.Kynzo:BAABLgAECn9FAAIGAAkJXB5tBAC3AgAGAAkJXB5tBAC3AgAAAA==.',
La='Laykeezenith:BAACLgAFFH8UAAQlAAYJJh0rBwCrAQAlAAYJmxorBwCrAQAUAAMJ7SKOIABfAAAVAAEJvQdrMgBDAAAuAAQKfx8ABCUACQmZIl4VAIcCACUACAnqIl4VAIcCABQACAm9IUU4APgBABUAAgl3EgooAHUAAAAA.Lazuli:BAACLgAFFH8FAAImAAUJpQ3ZKQDoAAAmAAUJpQ3ZKQDoAAAuAAQKf1EAAyYACQnDFV4bAAMCACYACQnDFV4bAAMCABgAAQk8BW9DACUAAAAA.',
Le='Lehann:BAABLgAECn8rAAIUAAkJxw8VSgC/AQAUAAkJxw8VSgC/AQAAAA==.',
Li='Lichtech:BAAALgAFFAIJAgABLgAFFAgJIQAFAFEdAA==.Lightsbane:BAAALgAECgcJEgAAAA==.',
Lu='Luciselda:BAAALgADCgUJBgAAAA==.Lumosnox:BAAALgADCgMJAwAAAA==.Lunariah:BAAALgADCgkJEwAAAA==.Luvtarhugar:BAAALgADCgMJAwAAAA==.',
['Lé']='Léann:BAAALgADCgUJBQAAAA==.',
Ma='Madaran:BAAALgAECgcJEAABLgAECgkJHgAYAHobAA==.Magdalene:BAEALgAECgUJCQABLgAFFAQJDgARAK4SAA==.Marebear:BAAALgADCgEJAQAAAA==.Marenus:BAABLgAECn9PAAIUAAkJQRFLRgDKAQAUAAkJQRFLRgDKAQAAAA==.Masume:BAAALgAECgcJEAAAAA==.Maély:BAAALgAECgEJAgAAAA==.',
Me='Mechadead:BAAALgADCggJCAAAAA==.Medal:BAAALgAECgEJAQAAAA==.Melody:BAAALgAECgYJBgAAAA==.Meowmix:BAAALgADCgcJDAAAAA==.',
Mi='Miantha:BAAALgAECgYJBwAAAA==.Michi:BAABLgAECn82AAMXAAkJgyJJBAB3AwAXAAkJgyJJBAB3AwAGAAYJLBaCGABGAQAAAA==.Midnights:BAAALgAECggJEAAAAA==.Mightymopo:BAAALgADCgMJAwAAAA==.Mikuki:BAABLgAECn8jAAIUAAkJvCNLEgC7AgAUAAkJvCNLEgC7AgAAAA==.Milkinghands:BAABLgAECn8hAAMDAAkJ1g84OgCBAQADAAkJ1g84OgCBAQABAAEJlALrsgAiAAAAAA==.Minabos:BAAALgAECgQJBwAAAA==.Mizmonk:BAACLgAFFH8bAAIMAAcJnBmICgDdAQAMAAcJnBmICgDdAQAuAAQKfyIAAgwACQnxHqMJAO4CAAwACQnxHqMJAO4CAAAA.',
Mj='Mjölnir:BAAALgAECgEJAQAAAA==.',
Mo='Montfort:BAAALgADCggJDwAAAA==.Mootality:BAAALgAECgIJBgABLgAECggJNwANAKUiAA==.Moovover:BAAALgAECggJCgAAAA==.Morningcrow:BAAALgAECgYJCgAAAA==.',
Ms='Msmaho:BAAALgAECgcJEAAAAA==.',
Mu='Muhdeeps:BAAALgADCgQJBAAAAA==.Murionor:BAAALgADCgEJAQAAAA==.Mushuu:BAAALgAECgYJBgAAAA==.',
My='Mykian:BAABLgAECn8pAAMkAAkJAQevEAD7AAAFAAkJ0QRwQgAcAQAkAAcJ1QevEAD7AAAAAA==.Myrwynn:BAAALgAECgMJAwABLgAECgkJPwAbAO0ZAA==.Mythlee:BAAALgAECgUJCAAAAA==.Mythundon:BAAALgADCgUJBQAAAA==.',
Na='Nahion:BAAALgAECgYJCQAAAA==.Nashira:BAABLgAECn8gAAIUAAkJVBMlPQDnAQAUAAkJVBMlPQDnAQAAAA==.Nathalas:BAAALgAECgEJAgABLgAECgkJPwASACwkAA==.Nature:BAAALgAECgUJCwAAAA==.',
Ne='Necrana:BAAALgADCgEJAQAAAA==.Necrobyarg:BAAALgAECgYJDQAAAA==.Nemasus:BAABLgAECn9CAAMXAAkJxB2TCwADAwAXAAkJxB2TCwADAwAgAAEJRQxAjAAxAAAAAA==.Nembie:BAAALgAECgQJBAAAAA==.Nethertech:BAABLgAFFH8HAAIKAAQJ0hEARwANAQAKAAQJ0hEARwANAQABLgAFFAgJIQAFAFEdAA==.',
Ni='Ninjahh:BAACLgAFFH8PAAISAAUJCQzDIQAPAQASAAUJCQzDIQAPAQAuAAQKfycAAhIACAnxFccYANEBABIACAnxFccYANEBAAAA.Niobei:BAAALgADCgcJBwABLgAECgkJTwAhACkZAA==.Nioshei:BAABLgAECn9PAAMhAAkJKRkkFACnAgAhAAkJKRkkFACnAgAmAAEJCQcHtgAjAAAAAA==.Nisara:BAACLgAFFH8MAAIDAAQJvRP0LgDuAAADAAQJvRP0LgDuAAAuAAQKfzgAAwMACQmRH0oKAPACAAMACQmRH0oKAPACAAEACAlsH5YMAHcCAAAA.',
No='Nochmuerta:BAABLgAECn8ZAAIWAAkJRRnyKQBXAgAWAAkJRRnyKQBXAgAAAA==.Nogrid:BAABLgAECn9RAAIOAAkJHBvbBgByAgAOAAkJHBvbBgByAgAAAA==.Nossaria:BAAALgAECgIJAgAAAA==.Notmyface:BAAALgAECgcJEwABLgAFFAIJBQAPAGAVAA==.',
Nu='Nuorong:BAAALgAECgUJBQABLgAECgkJPgAXABkXAA==.Nuthar:BAABLgAECn9CAAIiAAkJniX7AgBoAwAiAAkJniX7AgBoAwAAAA==.',
Ny='Nyxandra:BAAALgAECgYJCgAAAA==.',
['Né']='Nésta:BAAALgAECgcJDQAAAA==.',
['Nò']='Nòhva:BAAALgAECgQJBAAAAA==.',
Ol='Oldeis:BAAALgAECgEJAQAAAA==.',
Om='Ominousowl:BAABLgAFFH8FAAIFAAMJWBhwNgDpAAAFAAMJWBhwNgDpAAAAAA==.',
Or='Oregizm:BAAALgAFFAEJAQAAAA==.Orneryosprey:BAAALgAFFAEJAQABLgAFFAMJCwABAP0iAA==.',
Ou='Ourobius:BAAALgAECgMJAwAAAA==.',
Pa='Pamburu:BAABLgAECn8jAAQUAAgJ8w1beABKAQAUAAgJpg1beABKAQAlAAYJvgWDIACpAAAVAAIJrQUPKgBgAAAAAA==.Papagrape:BAABLgAECn9LAAQEAAkJxSBHAgBPAwAEAAkJxSBHAgBPAwAkAAcJNhzYBQD4AQAFAAMJaRY0WQDKAAAAAA==.Parzivàl:BAABLgAECn8mAAIZAAgJehiaEwB1AgAZAAgJehiaEwB1AgAAAA==.Paxa:BAABLgAECn8sAAMCAAgJbxumFQAjAgACAAgJbxumFQAjAgAbAAYJTguQRgDyAAAAAA==.',
Pe='Peacebox:BAAALgADCggJDAABLgAECgkJKwABABYOAA==.Persayis:BAAALgAECgcJEAAAAA==.',
Ph='Phoebel:BAAALgADCgkJEgABLgAECgEJAQAJAAAAAA==.Phoenixbodhi:BAAALgAECgQJBAAAAA==.',
Pi='Pickledeggs:BAAALgAECgIJAgABLgAECgkJJAANAIgYAA==.',
Po='Podnov:BAACLgAFFH8cAAMlAAYJhiAMCwCwAQAlAAYJhiAMCwCwAQAUAAIJpB36ggCNAAAuAAQKfyMAAiUACQlEHcwNANYCACUACQlEHcwNANYCAAAA.Pollyanna:BAAALgADCgEJAQAAAA==.',
Pr='Preyon:BAABLgAECn8YAAILAAYJdg89MADkAAALAAYJdg89MADkAAABLgAECgcJGgAMAN8NAA==.',
Py='Pyne:BAAALgADCgEJAQAAAA==.Pyrista:BAAALgAECgkJDAAAAA==.',
Qa='Qang:BAAALgAECgcJDQAAAA==.',
Qo='Qotho:BAABLgAECn9IAAIUAAkJYhtdJwA+AgAUAAkJYhtdJwA+AgAAAA==.',
Ra='Raikou:BAAALgAECgUJBQABLgAFFAYJIQAbAH8iAA==.Raistliin:BAAALgAECgYJDgAAAA==.Raithis:BAACLgAFFH8ZAAIUAAYJjxjuGwCMAQAUAAYJjxjuGwCMAQAuAAQKfzIAAhQACQlAIsAEAEEDABQACQlAIsAEAEEDAAAA.Raito:BAAALgADCgUJBQAAAA==.Ramhadin:BAEALgAECgMJCgABLgAECggJNAAbAO0eAA==.Ramzert:BAEALgAECgIJAgABLgAECggJNAAbAO0eAA==.Rav:BAAALgADCgMJAwAAAA==.',
Re='Rednaxel:BAABLgAECn9PAAMSAAkJMiVqAQBfAwASAAkJ7iRqAQBfAwAcAAUJRx9YCADEAQAAAA==.Redvelvet:BAABLgAECn8nAAMDAAkJqBWpHAAtAgADAAkJqBWpHAAtAgABAAQJ9Ab5WwCgAAAAAA==.Rekoner:BAABLgAECn8mAAIWAAkJRxMkSADnAQAWAAkJRxMkSADnAQAAAA==.Resi:BAAALgAECgIJAgAAAA==.Resii:BAAALgAECgEJAgABLgAECgIJAgAJAAAAAA==.Retarganator:BAACLgAFFH8GAAIKAAMJoxFpYADIAAAKAAMJoxFpYADIAAAuAAQKf1gAAwoACQm5HrkRALICAAoACQmDHrkRALICACcABAmMGNESACUBAAAA.',
Ri='Ringmistress:BAAALgADCgcJBwAAAA==.Rixaa:BAAALgADCgQJBQABLgAECgkJIwAUAGgcAA==.',
Ro='Rocks:BAAALgAECgYJCAAAAA==.Romam:BAAALgAECgYJCQAAAA==.',
Ru='Rubyknight:BAAALgAECgEJAQAAAA==.',
Ry='Rydran:BAAALgAECgUJCQAAAA==.Rykria:BAAALgAECgQJBwAAAA==.',
Sa='Samsonknight:BAAALgADCgYJBgAAAA==.Sanasat:BAAALgADCgMJAwAAAA==.Sanguinarian:BAABLgAECn8XAAIiAAgJIQ1VrgAfAQAiAAgJIQ1VrgAfAQAAAA==.Savash:BAAALgAECggJEgAAAA==.',
Sc='Scrubtotem:BAAALgAECgMJAwAAAA==.',
Se='Secksiecutie:BAABLgAECn82AAMjAAkJ7hoaBQBqAgAjAAkJ7hoaBQBqAgAHAAcJvQxjLAD1AAAAAA==.Selanda:BAAALgAECgQJBAAAAA==.Selval:BAAALgAECgMJAwAAAA==.Serinar:BAABLgAFFH8IAAIiAAMJoAM8gACrAAAiAAMJoAM8gACrAAAAAA==.Serraphem:BAAALgADCgkJEgAAAA==.',
Sh='Shafrog:BAAALgAECgIJAgABLgAECgkJPwARAPkWAA==.Shoshin:BAABLgAECn8aAAMMAAcJ3w1KSwDOAAAMAAcJ3w1KSwDOAAABAAQJJgxhXQCbAAAAAA==.Shïvana:BAAALgAECgMJDwAAAA==.',
Si='Silversaiyan:BAABLgAECn9KAAMPAAgJsyEQDgCNAgAPAAgJsyEQDgCNAgAQAAEJXRiEOgBGAAAAAA==.',
Sk='Skullpanda:BAAALgAECggJCAAAAA==.',
Sl='Slade:BAABLgAECn8/AAMSAAkJLCRSAwAUAwASAAkJLCRSAwAUAwAcAAMJ+xtjEwDvAAAAAA==.Slap:BAAALgAECgEJAQAAAA==.Sliyce:BAAALgAECgIJBgAAAA==.',
Sm='Smóke:BAABLgAECn9RAAIKAAkJKxUTNgDrAQAKAAkJKxUTNgDrAQAAAA==.',
Sn='Snore:BAAALgADCgQJBgAAAA==.Snowfawn:BAABLgAECn8pAAIUAAkJJhaPKAA5AgAUAAkJJhaPKAA5AgABLgAFFAIJBAAJAAAAAA==.',
So='Sofedan:BAABLgAECn9RAAIlAAkJuA8GDACgAQAlAAkJuA8GDACgAQAAAA==.Sorgath:BAAALgAECgMJBQAAAA==.Soriel:BAABLgAECn8zAAIMAAkJHBGAGwDGAQAMAAkJHBGAGwDGAQAAAA==.Sorokwa:BAABLgAECn8XAAIWAAkJKgIL+ACyAAAWAAkJKgIL+ACyAAAAAA==.',
Sq='Squeeze:BAAALgADCgYJBQAAAA==.Squids:BAAALgADCgQJBAAAAA==.',
St='Stallon:BAAALgAECgEJAgAAAA==.Strongstork:BAAALgAFFAIJAwABLgAFFAMJCwABAP0iAA==.',
Su='Sunsword:BAAALgAECgYJEQAAAA==.Suriden:BAAALgAECgYJBwAAAA==.',
Sw='Swagidan:BAABLgAECn8sAAIIAAgJoxgAEgBMAgAIAAgJoxgAEgBMAgAAAA==.Sweatermonk:BAAALgADCgIJAgABLgAECgYJBgAJAAAAAA==.Sweaterpally:BAAALgAECgYJBgAAAA==.Swiftera:BAABLgAECn8lAAIZAAkJIxaEKADqAQAZAAkJIxaEKADqAQAAAA==.Swiftlier:BAABLgAECn8vAAIMAAkJtxmzFQD9AQAMAAkJtxmzFQD9AQAAAA==.Swipegirl:BAAALgAECgYJCQAAAA==.',
Sy='Sybelyyia:BAAALgAECgUJBgAAAA==.Sylphrène:BAABLgAECn8yAAIIAAkJIwdrKAAzAQAIAAkJIwdrKAAzAQAAAA==.Sylriane:BAAALgAECgEJAgAAAA==.',
Ta='Taladan:BAAALgAECgQJBQAAAA==.Tallyian:BAAALgAECgEJAQAAAA==.Tandrana:BAAALgAECgMJBAAAAA==.Tankmepapi:BAAALgAECgMJAwAAAA==.Tanwen:BAABLgAECn8UAAQEAAYJ+QebJQC8AAAEAAYJ+QebJQC8AAAkAAQJHAMENwBfAAAFAAIJAAIgmQAmAAAAAA==.Targquellin:BAAALgAECgcJBwABLgAFFAMJBgAKAKMRAA==.Targypunch:BAAALgADCgcJBwABLgAFFAMJBgAKAKMRAA==.Tatsunoshinn:BAAALgADCgEJAQAAAA==.',
Te='Techniqe:BAACLgAFFH8hAAMFAAgJUR2KBwB4AgAFAAgJUR2KBwB4AgAEAAEJrwEOLAAxAAAuAAQKfzcAAwUACAkkIxsHAAoDAAUACAkkIxsHAAoDACQABgkgIe8SALMBAAAA.Techtides:BAAALgADCgUJBQABLgAFFAgJIQAFAFEdAA==.Temperance:BAAALgADCgEJAQAAAA==.Temptations:BAAALgAECgUJBgAAAA==.Terminus:BAAALgAECggJCwAAAA==.Terrylin:BAAALgAECgYJBwAAAA==.',
Th='Thaliá:BAAALgADCgkJFQAAAA==.Themachinist:BAAALgAECgYJBgAAAA==.Thomag:BAAALgADCgIJAgAAAA==.Thor:BAAALgAECgMJAwAAAA==.',
Ti='Ticebane:BAACLgAFFH8UAAMHAAUJsgpiJADJAAAHAAUJcApiJADJAAAWAAIJeQOt9wBuAAAuAAQKfyMAAgcACQk0GbALAFgCAAcACQk0GbALAFgCAAAA.Tiduspullo:BAABLgAECn8qAAMiAAkJmhuTRAAWAgAiAAkJdxWTRAAWAgAOAAUJoRo+GQBNAQAAAA==.Tiduswar:BAABLgAECn8fAAMTAAcJ2BpSFgCqAQATAAcJ2BpSFgCqAQAPAAIJfRJegABxAAABLgAECgkJKgAiAJobAA==.Tinafay:BAAALgAECgcJDAAAAA==.Tiramisuu:BAAALgAECgcJCQAAAA==.Titanbeard:BAAALgAECgMJBQAAAA==.Titor:BAABLgAECn81AAMEAAgJKRrpCABZAgAEAAgJKRrpCABZAgAkAAYJmw5aEAABAQAAAA==.Tituspullo:BAAALgAECgcJCgABLgAECgkJKgAiAJobAA==.',
To='Tolduan:BAAALgAECgUJDQAAAA==.Totemik:BAABLgAECn8eAAIYAAgJehs7CAA+AgAYAAgJehs7CAA+AgAAAA==.Toughturkey:BAABLgAFFH8LAAMBAAMJ/SJTHgDcAAABAAIJkyVTHgDcAAADAAIJqxKTSgBuAAAAAA==.Towen:BAAALgADCgUJBQAAAA==.Toy:BAAALgADCgYJGwAAAA==.',
Tr='Tremorhoof:BAAALgADCgIJAwAAAA==.Tresera:BAAALgADCgEJAQAAAA==.Tricarnetry:BAABLgAECn8lAAMiAAgJVA2NeQB5AQAiAAgJVA2NeQB5AQAZAAYJsQn1TgD7AAAAAA==.Trufleshufle:BAAALgAECggJEQAAAA==.',
['Tà']='Tàlle:BAAALgAECgMJAwAAAA==.',
Uh='Uhtread:BAAALgADCgYJBQAAAA==.',
Ul='Ulfer:BAAALgAECgUJBQABLgAFFAMJCQAHAHUeAA==.',
Un='Unholyfury:BAAALgADCgYJBgAAAA==.',
Va='Vapor:BAAALgAECgQJBQAAAA==.Vaquinha:BAAALgADCgUJBQAAAA==.Varyel:BAAALgAECgIJAgAAAA==.',
Ve='Velianne:BAAALgADCgUJBQAAAA==.Vellinada:BAAALgADCgMJAwABLgAFFAYJHwACAB0lAA==.Verakis:BAABLgAECn9PAAITAAkJtBr4BwB7AgATAAkJtBr4BwB7AgAAAA==.Verndarí:BAABLgAECn8ZAAMHAAkJ1Q3eHQBlAQAHAAkJ1Q3eHQBlAQAjAAMJzgXSLABpAAABLgAECgkJLwAMALcZAA==.Verudora:BAAALgAECgUJBgAAAA==.Vervain:BAAALgAECgUJBQAAAA==.',
Vo='Vonnie:BAAALgADCgkJCQAAAA==.Vortheus:BAAALgAECgkJEwAAAA==.Votollis:BAAALgAECgQJBQAAAA==.',
Wa='Warlanen:BAAALgAECgUJBgAAAA==.Warning:BAAALgADCgUJBQAAAA==.Warpiggies:BAAALgADCgkJCAAAAA==.',
Wi='Widdy:BAAALgAECgcJEAAAAA==.Willbur:BAABLgAECn9JAAINAAkJVxodLABnAgANAAkJVxodLABnAgAAAA==.Wittledwagon:BAAALgADCgkJCQAAAA==.',
Wu='Wurthwhile:BAAALgAECgYJDgAAAA==.',
Wy='Wylaniris:BAAALgADCgQJBAAAAA==.Wyndywalker:BAABLgAECn81AAIgAAkJqQksMwBJAQAgAAkJqQksMwBJAQAAAA==.',
Xa='Xaveil:BAAALgADCgEJAQAAAA==.',
Xe='Xenosian:BAAALgAECgkJCQAAAA==.',
Xi='Xinnou:BAAALgAECgEJAQAAAA==.Xinnuo:BAAALgAECgQJBwAAAA==.',
Xy='Xydias:BAAALgAECggJDwAAAA==.Xyra:BAAALgADCgcJBwAAAA==.',
Yo='Yoku:BAAALgAECggJEwAAAA==.Yondadk:BAAALgAECgEJAQAAAA==.',
Yu='Yunxiao:BAAALgAECgEJAQAAAA==.',
Za='Zacian:BAAALgAECgEJAQABLgAFFAYJIQAbAH8iAA==.Zag:BAAALgAECgEJAQABLgAECgkJMAAnALYWAA==.Zalgarian:BAAALgAECgYJDgAAAA==.Zamønk:BAABLgAECn8ZAAMMAAcJFg8WOABqAQAMAAcJFg8WOABqAQABAAIJ+wywlQA2AAAAAA==.Zaphoidvtwo:BAAALgAECgUJCwAAAA==.Zason:BAAALgADCgMJAwAAAA==.Zatari:BAAALgADCgMJAwAAAA==.Zavaen:BAAALgADCgEJAQAAAA==.',
Ze='Zelectie:BAACLgAFFH8GAAILAAQJfwVHHwCcAAALAAQJfwVHHwCcAAAuAAQKfxcAAgsACAluFzIKAPcBAAsACAluFzIKAPcBAAEuAAUUBwkSAAcAsxAA.Zelzaikin:BAAALgAECgQJBgAAAA==.Zevon:BAAALgAECgYJCgAAAA==.',
Zi='Ziarra:BAAALgADCgYJBgABLgADCgcJDQAJAAAAAA==.Zinazarinara:BAAALgAECgIJAgAAAA==.Zirril:BAAALgADCgcJDwAAAA==.',
Zo='Zombiechick:BAAALgAECgMJBAAAAA==.Zorn:BAAALgAECgMJAwAAAA==.',
['ßr']='ßrigitte:BAAALgADCgkJEQAAAA==.',
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
