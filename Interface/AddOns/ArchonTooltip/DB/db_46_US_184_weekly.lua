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

local lookup = {'Monk-Windwalker','Priest-Holy','Monk-Mistweaver','Evoker-Preservation','Evoker-Augmentation','Warrior-Protection','Druid-Feral','DeathKnight-Blood','DemonHunter-Havoc','Unknown-Unknown','DemonHunter-Devourer','Druid-Guardian','Monk-Brewmaster','Mage-Frost','Paladin-Protection','Warrior-Fury','Warrior-Arms','Warlock-Affliction','Rogue-Subtlety','Hunter-BeastMastery','Hunter-Survival','DeathKnight-Unholy','Druid-Restoration','Shaman-Enhancement','Paladin-Holy','Priest-Discipline','Priest-Shadow','Rogue-Assassination','Rogue-Outlaw','Warlock-Demonology','Warlock-Destruction','Druid-Balance','Shaman-Restoration','Paladin-Retribution','DeathKnight-Frost','Evoker-Devastation','Hunter-Marksmanship','Shaman-Elemental','DemonHunter-Vengeance',}
local provider = {region='US',realm='ScarletCrusade',name='US',type='weekly',zone=46,date='2026-06-20',data={Ac='Acefu:BAABLgAECn8XAAIBAAgJeSK8CAC7AgABAAgJeSK8CAC7AgAAAA==.Acornella:BAABLgAFFH8FAAICAAUJARNFEQBFAQACAAUJARNFEQBFAQABLgAFFAYJCAADAK4GAA==.Acorneo:BAABLgAFFH8IAAIDAAYJrgbSKgAaAQADAAYJrgbSKgAaAQAAAA==.Acornita:BAACLgAFFH8MAAMEAAQJsw1aEQCsAAAEAAMJ5w9aEQCsAAAFAAIJXwLdXQBeAAAuAAQKfyoAAwQACQnlD0YRACgCAAQACQnlD0YRACgCAAUABwlIEgokAJ0BAAEuAAUUBgkIAAMArgYA.',
Ad='Adoreith:BAAALgAECgEJAQAAAA==.',
Ae='Aelana:BAAALgADCgkJCQAAAA==.Aeria:BAAALgADCgYJBgAAAA==.Aeriith:BAAALgAECgEJAQAAAA==.Aevastraa:BAAALgAECgQJBAABLgAECgkJWAAGAAUdAA==.',
Ah='Ahyoka:BAAALgAFFAEJAgAAAA==.',
Ai='Ailanthus:BAABLgAECn8tAAIHAAkJ/Rc7AADgAQAHAAkJ/Rc7AADgAQAAAA==.',
Ak='Akinira:BAECLgAFFH8QAAIIAAQJ5RsqGQAeAQAIAAQJ5RsqGQAeAQAuAAQKfz4AAggACQmVHkAJAH4CAAgACQmVHkAJAH4CAAAA.',
Al='Aleinadris:BAAALgADCgQJBAAAAA==.Alendy:BAAALgAECgYJBgAAAA==.Alikchi:BAAALgADCgEJAgAAAA==.Alloisaber:BAAALgAECgYJCAAAAA==.Alternis:BAAALgAECgMJAwAAAA==.Alunne:BAAALgAECgEJAQAAAA==.',
An='Andrelsia:BAAALgAECgYJCQAAAA==.Andrilla:BAAALgAECgcJEAAAAA==.Ankeseth:BAAALgAECgcJCAAAAA==.',
Ap='Apôllyon:BAACLgAFFH8OAAIJAAMJASRjEwAJAQAJAAMJASRjEwAJAQAuAAQKfy4AAgkACQmeJfAAAL4DAAkACQmeJfAAAL4DAAAA.',
Ar='Aracelis:BAAALgAECgcJBwAAAA==.Aradius:BAAALgAECgEJAgABLgAECgIJBgAKAAAAAA==.Archertower:BAAALgADCgUJBQAAAA==.Artemiswynd:BAAALgAECgUJCAAAAA==.Arén:BAABLgAECn8qAAMLAAkJch8sFwCLAgALAAkJOR0sFwCLAgAJAAcJhx+YGwDkAQAAAA==.',
As='Ashenshugär:BAAALgAECgQJCAAAAA==.Asuri:BAAALgAECgEJAQAAAA==.Aszun:BAAALgAECgEJAQAAAA==.',
Au='Augment:BAAALgADCgQJBAAAAA==.',
Av='Avadda:BAABLgAECn8cAAIMAAcJwhFBJwAcAQAMAAcJwhFBJwAcAQABLgAECgkJPAANAG0RAA==.',
Az='Azmar:BAABLgAECn85AAIOAAgJ3SK5GgC6AgAOAAgJ3SK5GgC6AgABLgAFFAIJBAAKAAAAAA==.',
Ba='Badffinger:BAAALgADCgYJCQAAAA==.Badtouchbull:BAAALgADCgcJBwAAAA==.Balain:BAAALgAECgUJCgABLgAECgcJGwAMANsOAA==.Bayorn:BAAALgAECgYJBwAAAA==.',
Be='Bear:BAAALgADCgcJBwAAAA==.Bearmont:BAABLgAECn8nAAIPAAgJFRhKEQCwAQAPAAgJFRhKEQCwAQAAAA==.Bearzerk:BAABLgAECn8mAAIQAAkJCBQUJQDNAQAQAAkJCBQUJQDNAQAAAA==.Beastmonk:BAAALgADCgEJAQAAAA==.Benathar:BAABLgAECn8pAAIOAAkJkQ0cZAC2AQAOAAkJkQ0cZAC2AQAAAA==.Bethela:BAAALgAECgEJAQABLgAECgEJAQAKAAAAAA==.Beyoond:BAAALgAFFAMJAwAAAA==.',
Bi='Bifrost:BAAALgAFFAIJAgAAAA==.Bionico:BAABLgAECn8cAAIRAAYJOhbaAAD4AAARAAYJOhbaAAD4AAAAAA==.Birgir:BAAALgAECgUJCQABLgAECgcJGAASAHIgAA==.',
Bl='Blackmagék:BAAALgADCgkJCQAAAA==.Bladestormer:BAAALgADCgYJBQAAAA==.Blaston:BAAALgAECgQJBAAAAA==.Blazer:BAABLgAFFH8FAAILAAMJowincACoAAALAAMJowincACoAAAAAA==.Blightbeard:BAAALgAECgIJAgAAAA==.Bloodrager:BAAALgADCgIJAgAAAA==.Bloodthorn:BAABLgAECn8cAAITAAgJJgY7MAAfAQATAAgJJgY7MAAfAQAAAA==.Blortimor:BAAALgADCgcJBwAAAA==.',
Bo='Bombad:BAABLgAECn8UAAQQAAgJchIgLwCTAQAQAAgJPhIgLwCTAQAGAAMJNgstPwB0AAARAAEJdQw/fwAqAAAAAA==.Boomnescient:BAABLgAECn8kAAIUAAcJ7gcRjwAhAQAUAAcJ7gcRjwAhAQAAAA==.Bortt:BAAALgAECgQJBQAAAA==.Bozscaggs:BAABLgAECn9IAAMUAAkJkBN3NAALAgAUAAkJkBN3NAALAgAVAAUJAwOrRACuAAAAAA==.',
Br='Bramis:BAAALgADCgkJHAAAAA==.Brantu:BAAALgADCgQJCAABLgAECgEJAQAKAAAAAA==.Braultus:BAABLgAECn8zAAIIAAkJfx38CgBgAgAIAAkJfx38CgBgAgAAAA==.Breuddwydwr:BAAALgADCgEJAQAAAA==.Brewmeupbro:BAAALgAECgEJAQABLgAECgkJIwAWAFMcAA==.Breyastrasza:BAAALgAECgQJBwAAAA==.Brood:BAAALgAECgYJCwAAAA==.Bruceleroy:BAAALgAECgEJAQAAAA==.Bruinn:BAAALgAECgQJBAABLgAECgcJGwAMANsOAA==.',
Bu='Burstangel:BAAALgAECgYJCAAAAA==.',
By='Byrddh:BAAALgADCgQJBAAAAA==.',
['Bä']='Bäguette:BAAALgAECgEJAgAAAA==.',
Ca='Cadenza:BAAALgAECgcJEAAAAA==.Caelthar:BAAALgAECgUJCAAAAA==.Caliopedk:BAACLgAFFH8HAAMIAAIJrRjOOwBHAAAWAAIJrRjjOACqAAAIAAIJqALOOwBHAAAuAAQKfxsAAxYACAlIIWUhALsCABYACAlIIWUhALsCAAgABQlJDjQqAO0AAAAA.Caliseni:BAAALgADCgYJCwAAAA==.Capra:BAAALgAECgYJCAAAAA==.Carillanklip:BAAALgADCgUJBQAAAA==.Caydenza:BAAALgAECgMJAwAAAA==.',
Cd='Cdmickey:BAAALgADCgUJBQAAAA==.',
Ce='Celestè:BAAALgAECggJEQAAAA==.Celéste:BAAALgAECgkJEAAAAA==.Cerdwin:BAAALgAECggJEQABLgAECgkJPgAXABkXAA==.',
Ch='Charferad:BAAALgAECgcJDgAAAA==.Chatter:BAAALgADCgMJAwAAAA==.Cheaptrick:BAAALgADCgcJEwAAAA==.Chibeard:BAABLgAECn8nAAINAAkJtSKeAwAVAwANAAkJtSKeAwAVAwAAAA==.Chihîro:BAAALgAECgUJCgAAAA==.Chonglin:BAAALgADCgMJAwAAAA==.Chrysopteron:BAAALgAECgEJAQABLgAECgEJAQAKAAAAAA==.',
Cl='Clearcast:BAAALgADCgkJCwAAAA==.Clevercrane:BAAALgAFFAIJAgABLgAFFAMJBQAFAFgYAA==.Clubsdh:BAAALgAECgMJBAAAAA==.',
Co='Collosus:BAAALgAFFAEJAQABLgAFFAQJCwAQAA8RAA==.Coolbro:BAAALgADCgIJAgABLgADCggJCAAKAAAAAA==.Corialis:BAAALgAFFAEJAQAAAA==.Counsel:BAAALgAECgUJBQAAAA==.',
Cr='Criantha:BAAALgADCgIJAgAAAA==.Crom:BAACLgAFFH8GAAIYAAMJ5AVZEQCzAAAYAAMJ5AVZEQCzAAAuAAQKfzcAAhgACQkWEesOAMIBABgACQkWEesOAMIBAAAA.Crosis:BAAALgADCgYJBgAAAA==.Cruelladvoid:BAAALgAECgQJBAAAAA==.Cruush:BAAALgAECgYJBQAAAA==.',
Cu='Culerro:BAAALgAECgYJAwABLgAECgYJBQAKAAAAAA==.Cursive:BAAALgADCgUJDQAAAA==.',
Cy='Cygnes:BAABLgAECn8jAAIWAAkJUxwrJgBrAgAWAAkJUxwrJgBrAgAAAA==.',
Da='Daddywarrior:BAAALgADCgUJBgAAAA==.Daeva:BAAALgADCgEJAQAAAA==.Dantey:BAAALgADCgcJFAAAAA==.Daus:BAAALgAFFAEJAQAAAA==.Dazanna:BAABLgAECn82AAMZAAkJPxzrCgDeAgAZAAkJPxzrCgDeAgAPAAUJTAvoNQCJAAAAAA==.Dazre:BAAALgAECgUJBgAAAA==.',
De='Deeminor:BAAALgADCgkJEwAAAA==.Demeisen:BAAALgAECggJEQAAAA==.Demonizerr:BAAALgADCgUJCAAAAA==.Desktop:BAABLgAECn87AAMaAAkJUBxyCADuAgAaAAkJUBxyCADuAgAbAAYJdREqOgAqAQAAAA==.',
Di='Digon:BAAALgAECgEJAQAAAA==.Diod:BAABLgAECn9BAAIGAAkJHRVOEgDGAQAGAAkJHRVOEgDGAQAAAA==.Divineßovine:BAAALgADCgcJBwAAAA==.',
Do='Dolexin:BAAALgADCgkJCQAAAA==.Doombarker:BAAALgADCgYJBgAAAA==.Doomtheory:BAAALgAECgMJAwAAAA==.Dorammu:BAAALgAECgEJAQAAAA==.',
Dr='Dracovoid:BAAALgADCgYJBwAAAA==.Dracvoker:BAAALgAECgQJCAABLgAECgkJKgALAHIfAA==.Draegyns:BAAALgAECgIJAgABLgAFFAYJFQAcAA4UAA==.Draehton:BAAALgAECgYJBwABLgAFFAQJCwAVAH4XAA==.Dragyns:BAACLgAFFH8VAAMcAAYJDhQHBQAyAQATAAUJXRCwGwA9AQAcAAQJbRYHBQAyAQAuAAQKfzEABBwACQngG4ECAMoCABwACQmxGYECAMoCABMABgmMGz8sAJwBAB0AAwmrFFIJANwAAAAA.Dragynseye:BAAALgADCgIJAgABLgAFFAYJFQAcAA4UAA==.Drayper:BAABLgAECn8+AAQCAAkJuSEdAADjAgACAAkJuSEdAADjAgAaAAEJZw3AWQAvAAAbAAEJaQUkkwAnAAAAAA==.Drayperbark:BAAALgAECgUJCQAAAA==.Druugal:BAACLgAFFH8PAAITAAUJGhrlGABLAQATAAUJGhrlGABLAQAuAAQKfy8AAxMACQlwH0YMANQCABMACQlwH0YMANQCABwAAQl6C+ofADMAAAAA.',
Du='Dubs:BAABLgAECn8wAAQeAAkJ6hq1QADaAQAeAAYJwBq1QADaAQAfAAIJ7hmLIwCVAAASAAIJwxt2KgBKAAAAAA==.Dunbarke:BAABLgAECn8YAAISAAcJciCXCADeAQASAAcJciCXCADeAQAAAA==.Dustrat:BAAALgADCgIJAgAAAA==.',
['Dê']='Dêadlights:BAAALgAECgEJAQAAAA==.',
Ef='Efishient:BAABLgAECn8eAAIXAAYJWCTdHgBIAgAXAAYJWCTdHgBIAgABLgAFFAYJGQAXAH8TAA==.',
El='Elendrisa:BAAALgAECgYJBwAAAA==.Elisoria:BAAALgAECgMJAwAAAA==.Elliwynd:BAABLgAECn8uAAIXAAkJGRQoIgA3AgAXAAkJGRQoIgA3AgAAAA==.',
Eo='Eoshot:BAAALgAECgUJCAAAAA==.',
Er='Erinnys:BAABLgAECn9CAAMJAAkJdRcRDwA1AgAJAAkJdRcRDwA1AgALAAYJsgWPlgDvAAAAAA==.Ermoril:BAAALgAECgUJBgAAAA==.Ernesta:BAAALgADCgcJCAAAAA==.Eroksix:BAAALgADCgEJAQAAAA==.',
Eu='Eufemia:BAAALgAECgYJCQAAAA==.',
Ev='Evonnya:BAAALgAECgUJBQAAAA==.',
['Eø']='Eøs:BAAALgAECgEJAQAAAA==.',
Fa='Famine:BAAALgAECgcJDAAAAA==.',
Fe='Feelmebro:BAAALgADCggJCAAAAA==.Felern:BAAALgAECgcJCwABLgAFFAIJBAAKAAAAAA==.Feyrun:BAAALgADCgkJEwABLgAECgcJDQAKAAAAAA==.Feyrè:BAAALgAECgEJAgAAAA==.',
Fi='Fightswiftjr:BAAALgADCgkJCQAAAA==.Finalomega:BAABLgAECn8ZAAIIAAcJKxjbGACbAQAIAAcJKxjbGACbAQAAAA==.Finnshot:BAAALgAFFAIJAgAAAA==.Finrod:BAAALgAECgcJBwAAAA==.',
Fl='Flaminfalcon:BAABLgAFFH8FAAIbAAIJQBg5KwClAAAbAAIJQBg5KwClAAABLgAFFAMJBQAFAFgYAA==.Flody:BAAALgAFFAEJAQAAAA==.',
Fo='Foxflame:BAABLgAECn8+AAMXAAkJGResHwBJAgAXAAkJGResHwBJAgAgAAgJPhD3KACKAQAAAA==.',
Fr='Franzen:BAAALgAECgQJDAAAAA==.Freakbob:BAAALgADCgYJCQAAAA==.Froglocky:BAABLgAECn9AAAMSAAkJ+RY/BgAcAgASAAkJ+RY/BgAcAgAeAAMJcwRi9ABwAAAAAA==.Fronsac:BAAALgADCgQJBAAAAA==.',
Fu='Fulanita:BAABLgAECn8fAAMgAAcJBxASNgA+AQAgAAcJBxASNgA+AQAXAAIJSwr8wABFAAAAAA==.',
Ga='Gallager:BAAALgADCgMJAwAAAA==.Garzok:BAABLgAECn8qAAMSAAkJXwy1CwChAQASAAkJXwy1CwChAQAeAAMJzQHnCAFLAAAAAA==.',
Ge='Genkithered:BAABLgAECn82AAIhAAkJoxz5DQDlAgAhAAkJoxz5DQDlAgAAAA==.',
Gi='Gilaras:BAAALgAECgYJDAAAAA==.Gilernil:BAABLgAECn8UAAIUAAYJeQeVrwDlAAAUAAYJeQeVrwDlAAAAAA==.',
Gl='Gladtohelp:BAAALgAECgIJAgAAAA==.',
Gn='Gnoquarter:BAAALgADCgIJAgAAAA==.',
Go='Gourak:BAAALgAECgYJBwAAAA==.',
Gr='Gravemarks:BAABLgAECn8YAAMdAAgJqBNCCQCXAQAdAAgJqBNCCQCXAQAcAAQJzAncEQDoAAAAAA==.Grimhorn:BAABLgAECn8jAAMgAAcJsAd1VAC9AAAgAAYJDAh1VAC9AAAMAAIJWQMkfAAnAAAAAA==.Grimlie:BAAALgAECgEJAQAAAA==.Grimmrock:BAAALgAECgcJDgAAAA==.Grumblen:BAAALgADCgMJAwAAAA==.',
Gu='Guaritrice:BAABLgAECn8aAAMbAAcJdguAPQAbAQAbAAcJdguAPQAbAQACAAEJYQdwegAfAAAAAA==.Gubb:BAAALgAECgMJAwAAAA==.',
Gw='Gwenylane:BAABLgAECn8sAAIiAAkJSAuVdACFAQAiAAkJSAuVdACFAQAAAA==.Gwindor:BAAALgAECgYJCQAAAA==.Gwyndelyn:BAABLgAECn8xAAIBAAgJ9wtNNAAyAQABAAgJ9wtNNAAyAQAAAA==.',
Ha='Hatterus:BAABLgAECn9GAAIiAAkJ5A6rZACmAQAiAAkJ5A6rZACmAQAAAA==.',
He='Herculeze:BAABLgAFFH8GAAIZAAIJ7xrWNQCXAAAZAAIJ7xrWNQCXAAAAAA==.Hessian:BAAALgADCgEJAQAAAA==.Hetairoi:BAAALgAECgIJAgABLgAFFAMJCwABAP0iAA==.Hetd:BAAALgAECgEJAwABLgAFFAMJCwABAP0iAA==.',
Hi='Hillbroken:BAABLgAECn9QAAIjAAkJqSJaAgDrAgAjAAkJqSJaAgDrAgAAAA==.Hippie:BAAALgADCgMJAwAAAA==.',
Ho='Hohalt:BAAALgAECgEJAgAAAA==.Holycross:BAAALgAECgIJAgAAAA==.Holysmokers:BAAALgAECgYJDAABLgAFFAYJFQAcAA4UAA==.Holysnow:BAAALgADCgkJDAABLgAFFAIJBAAKAAAAAA==.Holysoul:BAAALgAECgEJAwAAAA==.',
Hu='Huntertidus:BAAALgAECggJDQABLgAECgkJLAAiAJobAA==.Huntrix:BAAALgAECgcJCQAAAA==.',
Hy='Hydan:BAAALgADCgIJAgAAAA==.Hyrlis:BAAALgAECgEJAQAAAA==.',
['Hà']='Hànks:BAABLgAECn8gAAIiAAkJ7g2vZgCiAQAiAAkJ7g2vZgCiAQAAAA==.',
Ib='Ibíng:BAAALgAECgYJBwAAAA==.',
Ic='Iceatron:BAAALgADCgUJBQAAAA==.',
Im='Imo:BAABLgAECn8qAAMeAAkJIRF8VACfAQAeAAkJyQ58VACfAQAfAAUJIhJvJgCBAAAAAA==.',
In='Intrepidz:BAAALgAECgEJAgABLgAFFAMJBQAFAFgYAA==.Inèvitable:BAABLgAECn9CAAIWAAkJHh13IwB4AgAWAAkJHh13IwB4AgAAAA==.',
Ir='Ironphant:BAAALgAECgYJBgAAAA==.',
Is='Istara:BAAALgAECgQJBAAAAA==.',
Iv='Ivorin:BAAALgAECgYJCgAAAA==.',
Ja='Jabujabu:BAAALgAECgcJDAABLgAFFAMJBwALAKMRAA==.Javeech:BAACLgAFFH8FAAIUAAMJbhCyXwDlAAAUAAMJbhCyXwDlAAAuAAQKfygAAxQACQl5GtgnAEACABQACAnQHNgnAEACABUAAQkVCjtiADcAAAAA.',
Je='Jebib:BAAALgAECgYJBgABLgAFFAkJMwAXAGAfAA==.Jeod:BAAALgAECgYJCQAAAA==.',
Jo='Jolty:BAACLgAFFH8aAAIWAAYJUSBiJQDXAQAWAAYJUSBiJQDXAQAuAAQKfykAAxYACQlWIq8MADUDABYACQlWIq8MADUDAAgABAmkFmIyANMAAAAA.Joydivision:BAAALgADCgIJAgAAAA==.',
Ju='Julian:BAAALgAECggJCAABLgAECgkJPwATACwkAA==.',
['Jð']='Jð:BAAALgAECgQJBAABLgAECgYJJQALAGAhAA==.',
Ka='Kaboomchickn:BAAALgAECgIJAgABLgAECgcJDgAKAAAAAA==.Kaiou:BAAALgADCgQJCAAAAA==.Kalmia:BAAALgAECgQJBAAAAA==.Kantor:BAABLgAECn9RAAMCAAkJLhiLFgAcAgACAAkJLhiLFgAcAgAbAAIJvQszhgAzAAAAAA==.Karboomkin:BAABLgAFFH8GAAMMAAUJQhRbEgDxAAAMAAQJQhRbEgDxAAAgAAEJAACSWgAAAAABLgAFFAgJGwAiAN0gAA==.Karnstein:BAABLgAECn8oAAQkAAgJ4BEXDABQAQAkAAYJuxAXDABQAQAFAAYJBxEsSwD/AAAEAAUJgwTuMwDOAAAAAA==.Kasenko:BAAALgAECgIJAgABLgAECgYJIgAMAHkYAA==.Kasryna:BAABLgAECn8iAAIMAAYJeRgvHgBcAQAMAAYJeRgvHgBcAQAAAA==.Kathinja:BAABLgAECn8oAAIUAAkJCQlPWwCTAQAUAAkJCQlPWwCTAQAAAA==.Katiebeary:BAAALgAECgcJCwAAAA==.',
Ke='Kelthera:BAAALgAECgYJBgAAAA==.Kelumbria:BAAALgAECgkJDwAAAA==.Keta:BAAALgADCgYJBgAAAA==.Ketameanie:BAABLgAECn85AAILAAkJQBdsJQA4AgALAAkJQBdsJQA4AgAAAA==.',
Ki='Kieran:BAAALgAECgQJCgAAAA==.Kiley:BAAALgAECgkJCAAAAA==.Killerkitten:BAAALgADCgEJAQAAAA==.Kitsunè:BAAALgAECgEJAQAAAA==.',
Km='Kmazing:BAABLgAECn8rAAMBAAkJFg6oJgCBAQABAAkJFg6oJgCBAQADAAMJIRA0fwCiAAAAAA==.',
Kn='Knifèparty:BAABLgAECn85AAIcAAkJkSIEAgDOAgAcAAkJkSIEAgDOAgAAAA==.',
Ko='Konoha:BAABLgAECn8sAAMaAAkJzyA4BgAfAwAaAAkJwh84BgAfAwACAAMJfiPoQwApAQAAAA==.',
Ku='Kultag:BAABLgAECn8fAAIiAAkJBRYpOwAXAgAiAAkJBRYpOwAXAgAAAA==.',
Ky='Kyaw:BAABLgAECn8WAAQTAAYJbRyAKAC2AQATAAYJbRyAKAC2AQAcAAIJxRJbFgCTAAAdAAEJPRTnIwA4AAAAAA==.Kynzo:BAABLgAECn9FAAIHAAkJXB58BAC4AgAHAAkJXB58BAC4AgAAAA==.',
La='Laykeezenith:BAACLgAFFH8UAAQlAAYJJh0rBwCrAQAlAAYJmxorBwCrAQAUAAMJ7SKOIABfAAAVAAEJvQecMwBDAAAuAAQKfx8ABCUACQmZIl4VAIcCACUACAnqIl4VAIcCABQACAm9IZs5APgBABUAAgl3EgooAHUAAAAA.Lazuli:BAACLgAFFH8GAAImAAUJpQ1dKwDoAAAmAAUJpQ1dKwDoAAAuAAQKf1cAAyYACQkjFgYBAF4BACYACQkjFgYBAF4BABgAAQk8BXZFACUAAAAA.',
Le='Lehann:BAABLgAECn8rAAIUAAkJxw+tSwC/AQAUAAkJxw+tSwC/AQAAAA==.',
Li='Lichtech:BAAALgAFFAIJAgABLgAFFAgJIQAFAFEdAA==.Lightsbane:BAAALgAECgcJEgAAAA==.',
Lo='Lockatron:BAAALgADCgYJBgAAAA==.',
Lu='Luciselda:BAAALgADCgUJBgAAAA==.Lumosnox:BAAALgAECgMJAwAAAA==.Lunariah:BAAALgADCgkJEwAAAA==.Luvtarhugar:BAAALgAECgUJBQAAAA==.',
['Lé']='Léann:BAAALgADCgUJBQAAAA==.',
Ma='Madaran:BAAALgAECgcJEAABLgAECgkJIAAYAEgaAA==.Magdalene:BAEALgAECgUJCQABLgAFFAcJFAASAPISAA==.Marebear:BAAALgADCgEJAQAAAA==.Marenus:BAABLgAECn9PAAIUAAkJQRHQRwDKAQAUAAkJQRHQRwDKAQAAAA==.Masume:BAAALgAECggJEgAAAA==.Maély:BAAALgAECgEJAgAAAA==.',
Me='Mechadead:BAAALgADCggJCAAAAA==.Medal:BAAALgAECgEJAQAAAA==.Melody:BAAALgAECgYJBgAAAA==.Meowmix:BAAALgADCgcJDAAAAA==.',
Mi='Miantha:BAAALgAECgYJBwAAAA==.Michi:BAABLgAECn82AAMXAAkJgyJwBAB3AwAXAAkJgyJwBAB3AwAHAAYJLBYLGQBHAQAAAA==.Midnights:BAAALgAECggJEAAAAA==.Mightymopo:BAAALgADCgMJAwAAAA==.Mikuki:BAABLgAECn8jAAIUAAkJvCP6EgC6AgAUAAkJvCP6EgC6AgAAAA==.Milkinghands:BAABLgAECn8hAAMDAAkJ1g+HOwCCAQADAAkJ1g+HOwCCAQABAAEJlAI9tgAiAAAAAA==.Minabos:BAAALgAECgQJCQAAAA==.Mizmonk:BAACLgAFFH8gAAINAAcJnBmJCwDcAQANAAcJnBmJCwDcAQAuAAQKfyIAAg0ACQnxHqMJAO4CAA0ACQnxHqMJAO4CAAAA.',
Mj='Mjölnir:BAAALgAECgcJCAAAAA==.',
Mo='Montfort:BAAALgADCggJDwAAAA==.Mootality:BAAALgAFFAIJBAAAAA==.Moovover:BAAALgAECggJCgAAAA==.Morningcrow:BAAALgAECgYJCgAAAA==.',
Ms='Msmaho:BAAALgAECgcJEAAAAA==.',
Mu='Muhdeeps:BAAALgADCgQJBAAAAA==.Murionor:BAAALgADCgEJAQAAAA==.Mushuu:BAAALgAECgYJBgAAAA==.',
My='Mykian:BAABLgAECn8pAAMkAAkJAQf1EAD7AAAFAAkJ0QTXQwAaAQAkAAcJ1Qf1EAD7AAAAAA==.Myrwynn:BAAALgAECgMJAwABLgAFFAMJBQAbAFYKAA==.Mythlee:BAAALgAECgUJCAAAAA==.Mythundon:BAAALgADCgUJBQAAAA==.',
Na='Nahion:BAAALgAECgYJCQAAAA==.Nashira:BAABLgAECn8oAAIUAAkJkhj5AAAOAgAUAAkJkhj5AAAOAgAAAA==.Nathalas:BAAALgAECgEJAgABLgAECgkJPwATACwkAA==.Nature:BAAALgAECgUJCwAAAA==.',
Ne='Necrana:BAAALgADCgEJAQAAAA==.Necrobyarg:BAAALgAECgYJDQAAAA==.Nemasus:BAABLgAECn9DAAMXAAkJ5B3HCwADAwAXAAkJ5B3HCwADAwAgAAEJRQzTjgAxAAAAAA==.Nembie:BAAALgAECgUJCQAAAA==.Nethertech:BAABLgAFFH8LAAILAAUJ0hE4SQANAQALAAUJ0hE4SQANAQABLgAFFAgJIQAFAFEdAA==.',
Ni='Ninjahh:BAACLgAFFH8TAAITAAUJCQyEBQCcAAATAAUJCQyEBQCcAAAuAAQKfygAAhMACAkrFy4ZANEBABMACAkrFy4ZANEBAAAA.Niobei:BAAALgADCgcJBwABLgAECgkJXAAhAEcZAA==.Nioshei:BAABLgAECn9cAAMhAAkJRxnVAADSAQAhAAkJRxnVAADSAQAmAAEJCQfDuQAjAAAAAA==.Nisara:BAACLgAFFH8MAAIDAAQJvRMkMQDvAAADAAQJvRMkMQDvAAAuAAQKf0UAAwMACQmRH4YKAPECAAMACQmRH4YKAPECAAEACQnAISYAALsCAAAA.',
No='Nochmuerta:BAABLgAECn8ZAAIWAAkJRRl+KgBWAgAWAAkJRRl+KgBWAgAAAA==.Nogrid:BAABLgAECn9RAAIPAAkJHBsDBwBxAgAPAAkJHBsDBwBxAgAAAA==.Nossaria:BAAALgAECgIJAgAAAA==.Notmyface:BAAALgAECgcJEwABLgAFFAIJBgAQAGAVAA==.',
Nu='Nuorong:BAAALgAECgUJBQABLgAECgkJPgAXABkXAA==.Nuthar:BAABLgAECn9CAAIiAAkJniUwAwBnAwAiAAkJniUwAwBnAwAAAA==.',
Ny='Nyxandra:BAAALgAECgYJCgAAAA==.',
['Né']='Nésta:BAAALgAECgcJDQAAAA==.',
['Nò']='Nòhva:BAAALgAECgQJBAAAAA==.',
Ol='Oldeis:BAAALgAECgEJAQAAAA==.',
Om='Ominousowl:BAABLgAFFH8FAAIFAAMJWBhYOADkAAAFAAMJWBhYOADkAAAAAA==.',
Or='Oregizm:BAAALgAFFAEJAQAAAA==.Orneryosprey:BAAALgAFFAEJAQABLgAFFAMJCwABAP0iAA==.',
Ou='Ourobius:BAAALgAECgQJBgAAAA==.',
Pa='Pamburu:BAABLgAECn8jAAQUAAgJ8w2zegBKAQAUAAgJpg2zegBKAQAlAAYJvgUKIQCpAAAVAAIJrQUPKgBgAAAAAA==.Papagrape:BAABLgAECn9SAAQEAAkJwiHxAQBlAwAEAAkJwiHxAQBlAwAkAAcJexz0BQD4AQAFAAMJaRaWWgDKAAAAAA==.Parzivàl:BAABLgAECn8mAAIZAAgJehiaEwB1AgAZAAgJehiaEwB1AgAAAA==.Paxa:BAABLgAECn8sAAMCAAgJbxsGFgAiAgACAAgJbxsGFgAiAgAbAAYJTgvnRwDwAAAAAA==.',
Pe='Peacebox:BAAALgADCggJDAABLgAECgkJKwABABYOAA==.Persayis:BAAALgAECgcJEAAAAA==.',
Ph='Phoebel:BAAALgADCgkJEgABLgAECgEJAQAKAAAAAA==.Phoenixbodhi:BAAALgAECgQJBAAAAA==.',
Pi='Pickledeggs:BAAALgAECgcJCAABLgAECgkJJQAOAFwaAA==.',
Po='Podnov:BAACLgAFFH8dAAMlAAYJhiCiCwCpAQAlAAYJhiCiCwCpAQAUAAIJpB09iACNAAAuAAQKfyMAAiUACQlEHcwNANYCACUACQlEHcwNANYCAAAA.Pollyanna:BAAALgADCgEJAQAAAA==.',
Pr='Preyon:BAABLgAECn8bAAIMAAcJ2w7JAgB6AAAMAAcJ2w7JAgB6AAAAAA==.',
Py='Pyne:BAAALgADCgEJAQAAAA==.Pyrista:BAAALgAECgkJDAAAAA==.',
Qa='Qang:BAAALgAECgcJDQAAAA==.',
Qo='Qotho:BAABLgAECn9IAAIUAAkJYhtjKAA9AgAUAAkJYhtjKAA9AgAAAA==.',
Ra='Raikou:BAAALgAECgUJBQABLgAFFAYJJwAbAJQiAA==.Raistliin:BAAALgAECgYJDgAAAA==.Raithis:BAACLgAFFH8dAAIUAAYJjxgzHgCMAQAUAAYJjxgzHgCMAQAuAAQKfzIAAhQACQlAIsAEAEEDABQACQlAIsAEAEEDAAAA.Raito:BAAALgADCgUJBQAAAA==.Ramhadin:BAEALgAECgMJCgABLgAECggJNwAbALYfAA==.Ramzert:BAEALgAECgIJAgABLgAECggJNwAbALYfAA==.Rav:BAAALgADCgMJAwAAAA==.',
Re='Rednaxel:BAABLgAECn9YAAMTAAkJMyV7AQBeAwATAAkJ7yR7AQBeAwAcAAUJRx9xCADEAQAAAA==.Redvelvet:BAABLgAECn8vAAMDAAkJhRY1AQCLAQADAAkJhRY1AQCLAQABAAQJ9Ab5WwCgAAAAAA==.Rekoner:BAABLgAECn8mAAIWAAkJRxPrSQDkAQAWAAkJRxPrSQDkAQAAAA==.Resi:BAAALgAECgIJAgAAAA==.Resii:BAAALgAECgEJAgABLgAECgIJAgAKAAAAAA==.Retarganator:BAACLgAFFH8HAAILAAMJoxEaYwDIAAALAAMJoxEaYwDIAAAuAAQKf1kAAwsACQnNHi0RALkCAAsACQnNHi0RALkCACcABAmMGNESACUBAAAA.',
Ri='Ringmistress:BAAALgADCgcJBwAAAA==.Rixaa:BAAALgADCgQJBQABLgAECgkJIwAUAGgcAA==.',
Ro='Rocks:BAAALgAECgYJCAAAAA==.Romam:BAAALgAECgYJCQAAAA==.',
Ru='Rubyknight:BAAALgAECgEJAQAAAA==.',
Ry='Rydran:BAAALgAECgUJCQAAAA==.Rykria:BAAALgAECgQJCgAAAA==.',
Sa='Samsonknight:BAAALgADCgYJBgAAAA==.Sanasat:BAAALgADCgMJAwAAAA==.Sanguinarian:BAABLgAECn8XAAIiAAgJIQ32sAAeAQAiAAgJIQ32sAAeAQAAAA==.Savash:BAAALgAECggJEgAAAA==.',
Sc='Scrubtotem:BAAALgAECgMJAwAAAA==.',
Se='Secksiecutie:BAABLgAECn82AAMjAAkJ7hpJBQBmAgAjAAkJ7hpJBQBmAgAIAAcJvQw5LQDzAAAAAA==.Selanda:BAAALgAECgQJBAAAAA==.Selval:BAAALgAECgQJBwAAAA==.Serinar:BAABLgAFFH8IAAIiAAMJoAOMhACrAAAiAAMJoAOMhACrAAAAAA==.Serraphem:BAAALgADCgkJGgAAAA==.',
Sh='Shafrog:BAAALgAECgIJAgABLgAECgkJQAASAPkWAA==.Shoshin:BAABLgAECn8aAAMNAAcJ3w0ITADOAAANAAcJ3w0ITADOAAABAAQJJgxhXQCbAAABLgAECgcJGwAMANsOAA==.Shïvana:BAAALgAECgMJDwAAAA==.',
Si='Silversaiyan:BAABLgAECn9KAAMQAAgJsyFoDgCLAgAQAAgJsyFoDgCLAgARAAEJXRiEOgBGAAAAAA==.',
Sk='Skullpanda:BAAALgAECggJCAAAAA==.',
Sl='Slade:BAABLgAECn8/AAMTAAkJLCRvAwATAwATAAkJLCRvAwATAwAcAAMJ+xuUEwDvAAAAAA==.Slap:BAAALgAECgEJAQAAAA==.Slaps:BAAALgADCgkJCQAAAA==.Sliyce:BAAALgAECgIJBgAAAA==.',
Sm='Smóke:BAABLgAECn9RAAILAAkJKxWpNgDsAQALAAkJKxWpNgDsAQAAAA==.',
Sn='Snore:BAAALgADCgQJBgAAAA==.Snowfawn:BAABLgAECn8qAAIUAAkJJhaWKQA4AgAUAAkJJhaWKQA4AgABLgAFFAIJBAAKAAAAAA==.Snowieblaze:BAAALgAECgQJBAABLgAFFAIJBAAKAAAAAA==.',
So='Sofedan:BAABLgAECn9RAAIlAAkJuA87DACgAQAlAAkJuA87DACgAQAAAA==.Sorgath:BAAALgAECgMJBQAAAA==.Soriel:BAABLgAECn88AAINAAkJbRGJAAB5AQANAAkJbRGJAAB5AQAAAA==.Sorokwa:BAABLgAECn8XAAIWAAkJKgLP+wCxAAAWAAkJKgLP+wCxAAAAAA==.',
Sq='Squeeze:BAAALgADCgYJBQAAAA==.Squids:BAAALgADCgQJBAAAAA==.',
St='Stallon:BAAALgAECgEJAgAAAA==.Stillwater:BAAALgADCgkJCQAAAA==.Strongstork:BAAALgAFFAIJBAABLgAFFAMJCwABAP0iAA==.',
Su='Sunsword:BAAALgAECgYJEQAAAA==.Suriden:BAAALgAECgYJBwAAAA==.',
Sw='Swagidan:BAABLgAECn8sAAIJAAgJoxgAEgBMAgAJAAgJoxgAEgBMAgAAAA==.Sweatermonk:BAAALgADCgIJAgABLgAECgYJBgAKAAAAAA==.Sweaterpally:BAAALgAECgYJBgAAAA==.Swiftera:BAABLgAECn8lAAIZAAkJIxaEKADqAQAZAAkJIxaEKADqAQAAAA==.Swiftlier:BAABLgAECn8vAAINAAkJtxn6FQD8AQANAAkJtxn6FQD8AQAAAA==.Swipegirl:BAAALgAECgYJCQAAAA==.',
Sy='Sybelyyia:BAAALgAECgUJBgAAAA==.Sylphrène:BAABLgAECn8yAAIJAAkJIweuKQAwAQAJAAkJIweuKQAwAQAAAA==.Sylriane:BAAALgAECgEJAgAAAA==.',
Ta='Taladan:BAAALgAECgQJBQAAAA==.Tallyian:BAAALgAECgEJAwAAAA==.Tandrana:BAAALgAECgQJBQAAAA==.Tankmepapi:BAAALgAECgMJAwAAAA==.Tanwen:BAABLgAECn8UAAQEAAYJ+QcWJgC8AAAEAAYJ+QcWJgC8AAAkAAQJHAMENwBfAAAFAAIJAALlmwAmAAAAAA==.Targquellin:BAAALgAECgcJBwABLgAFFAMJBwALAKMRAA==.Targypunch:BAAALgADCgcJBwABLgAFFAMJBwALAKMRAA==.Tatsunoshinn:BAAALgADCgEJAQAAAA==.',
Te='Techniqe:BAACLgAFFH8hAAMFAAgJUR1UCABzAgAFAAgJUR1UCABzAgAEAAEJrwEkLQAxAAAuAAQKfzcAAwUACAkkIxsHAAoDAAUACAkkIxsHAAoDACQABgkgIe8SALMBAAAA.Techtides:BAAALgAECgIJAgABLgAFFAgJIQAFAFEdAA==.Temperance:BAAALgADCgEJAQAAAA==.Temptations:BAAALgAECgUJBgAAAA==.Terminus:BAAALgAECggJCwAAAA==.Terrylin:BAAALgAECgYJBwAAAA==.',
Th='Thaliá:BAAALgADCgkJFQAAAA==.Themachinist:BAAALgAECgYJBgAAAA==.Thomag:BAAALgADCgIJAgAAAA==.Thor:BAAALgAECgUJBgAAAA==.',
Ti='Ticebane:BAACLgAFFH8VAAMIAAYJIQn6JQDCAAAIAAUJcAr6JQDCAAAWAAMJRgMmIQBCAAAuAAQKfyMAAggACQk0GbALAFgCAAgACQk0GbALAFgCAAAA.Tiduspullo:BAABLgAECn8sAAMiAAkJmhuTRAAWAgAiAAkJdxWTRAAWAgAPAAYJExuZGQBMAQAAAA==.Tiduswar:BAABLgAECn8fAAMGAAcJ2BpSFgCqAQAGAAcJ2BpSFgCqAQAQAAIJfRI3gwBtAAABLgAECgkJLAAiAJobAA==.Tinafay:BAAALgAECgcJDAAAAA==.Tiramisuu:BAAALgAECgcJDwAAAA==.Titanbeard:BAAALgAECgMJBQAAAA==.Titor:BAABLgAECn8+AAMEAAgJKRpKAACGAQAEAAgJKRpKAACGAQAkAAYJmw6hEAABAQAAAA==.Tituspullo:BAAALgAECgcJCgABLgAECgkJLAAiAJobAA==.',
To='Tolduan:BAAALgAECgUJDQAAAA==.Totemik:BAABLgAECn8gAAIYAAkJSBpwCAA9AgAYAAkJSBpwCAA9AgAAAA==.Toughturkey:BAABLgAFFH8LAAMBAAMJ/SJbHwDcAAABAAIJkyVbHwDcAAADAAIJqxIGTgBuAAAAAA==.Towen:BAAALgADCgUJBQAAAA==.Toy:BAAALgADCgYJGwAAAA==.',
Tr='Tremorhoof:BAAALgADCgIJAwAAAA==.Tresera:BAAALgADCgEJAQAAAA==.Tricarnetry:BAABLgAECn8lAAMiAAgJVA0sfAB2AQAiAAgJVA0sfAB2AQAZAAYJsQkhUAD5AAAAAA==.Trufleshufle:BAAALgAECggJEQAAAA==.',
['Tà']='Tàlle:BAAALgAECgMJAwAAAA==.',
Uh='Uhtread:BAAALgADCgYJBQAAAA==.',
Ul='Ulfer:BAAALgAECgUJBQABLgAFFAMJCQAIAHUeAA==.',
Un='Unholyfury:BAAALgADCgYJBgAAAA==.',
Va='Vapor:BAAALgAECgQJBQAAAA==.Vaquinha:BAAALgADCgUJBQAAAA==.Varyel:BAAALgAECgIJAgAAAA==.',
Ve='Velianne:BAAALgADCgUJBQAAAA==.Vellinada:BAAALgADCgMJAwABLgAFFAcJIAACAEglAA==.Verakis:BAABLgAECn9YAAIGAAkJBR1BAAArAgAGAAkJBR1BAAArAgAAAA==.Verndarí:BAABLgAECn8ZAAMIAAkJ1Q2QHgBiAQAIAAkJ1Q2QHgBiAQAjAAMJzgU2LgBoAAABLgAECgkJLwANALcZAA==.Verudora:BAAALgAECgUJBgAAAA==.Vervain:BAAALgAECgUJBQAAAA==.',
Vo='Vonnie:BAAALgADCgkJCQAAAA==.Vortheus:BAAALgAECgkJEwAAAA==.Votollis:BAAALgAECgQJBQAAAA==.',
Wa='Warlanen:BAAALgAECgUJBgAAAA==.Warning:BAAALgADCgUJBQAAAA==.Warpiggies:BAAALgADCgkJCAABLgAFFAMJBwALAKMRAA==.',
Wi='Widdy:BAAALgAECgcJEAAAAA==.Willbur:BAABLgAECn9JAAIOAAkJVxr5LABlAgAOAAkJVxr5LABlAgAAAA==.Wittledwagon:BAAALgADCgkJCQAAAA==.',
Wu='Wurthwhile:BAAALgAECgYJDgAAAA==.',
Wy='Wylaniris:BAAALgADCgQJBAAAAA==.Wyndywalker:BAABLgAECn82AAIgAAkJqQk9NABIAQAgAAkJqQk9NABIAQAAAA==.',
Xa='Xaveil:BAAALgADCgEJAQAAAA==.',
Xe='Xenosian:BAAALgAECgkJCQAAAA==.',
Xi='Xinnou:BAAALgAECgEJAQAAAA==.Xinnuo:BAAALgAECgQJBwAAAA==.',
Xy='Xydias:BAAALgAECggJDwAAAA==.Xyra:BAAALgADCgcJBwAAAA==.',
Yo='Yoku:BAAALgAECggJEwAAAA==.Yondadk:BAAALgAECgEJAQAAAA==.',
Yu='Yunxiao:BAAALgAECgEJAQAAAA==.',
Za='Zacian:BAAALgAECgEJAQABLgAFFAYJJwAbAJQiAA==.Zag:BAAALgAECgEJAQABLgAECgkJMAAnALYWAA==.Zalgarian:BAAALgAECgYJDgAAAA==.Zamønk:BAABLgAECn8ZAAMNAAcJFg8WOABqAQANAAcJFg8WOABqAQABAAIJ+wypmAA2AAAAAA==.Zaphoidvtwo:BAAALgAECgUJCwAAAA==.Zason:BAAALgADCgMJAwAAAA==.Zatari:BAAALgADCgMJAwAAAA==.Zavaen:BAAALgADCgEJAQAAAA==.',
Ze='Zelectie:BAACLgAFFH8GAAIMAAQJfwXYIQCVAAAMAAQJfwXYIQCVAAAuAAQKfxcAAgwACAluFzIKAPcBAAwACAluFzIKAPcBAAEuAAUUBwkSAAgAsxAA.Zelzaikin:BAAALgAECgQJBgAAAA==.Zevon:BAAALgAECgYJCgAAAA==.',
Zi='Ziarra:BAAALgADCgYJBgABLgADCgcJDQAKAAAAAA==.Zinazarinara:BAAALgAECgIJAgAAAA==.Zirril:BAAALgADCgcJDwAAAA==.',
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
