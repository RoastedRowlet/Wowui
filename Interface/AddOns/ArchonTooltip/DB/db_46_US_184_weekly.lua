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

local lookup = {'Monk-Windwalker','Priest-Holy','Monk-Mistweaver','Evoker-Preservation','Evoker-Augmentation','Paladin-Protection','Warrior-Protection','Druid-Feral','DeathKnight-Blood','DemonHunter-Havoc','Unknown-Unknown','DemonHunter-Devourer','Druid-Guardian','Monk-Brewmaster','Mage-Frost','DeathKnight-Unholy','Warrior-Fury','Warrior-Arms','Warlock-Affliction','Rogue-Subtlety','Paladin-Retribution','Paladin-Holy','Hunter-BeastMastery','Hunter-Survival','Druid-Restoration','Priest-Shadow','Shaman-Enhancement','Priest-Discipline','Rogue-Assassination','Rogue-Outlaw','Warlock-Demonology','Warlock-Destruction','Druid-Balance','Shaman-Restoration','DeathKnight-Frost','Evoker-Devastation','Hunter-Marksmanship','Shaman-Elemental','DemonHunter-Vengeance',}
local provider = {region='US',realm='ScarletCrusade',name='US',type='weekly',zone=46,date='2026-07-05',data={Ac='Acefu:BAABLgAECn8ZAAIBAAkJUSK8CAC7AgABAAkJUSK8CAC7AgAAAA==.Acornella:BAABLgAFFH8FAAICAAUJARNDEQBFAQACAAUJARNDEQBFAQABLgAFFAYJCAADAK4GAA==.Acorneo:BAABLgAFFH8IAAIDAAYJrgbVKgAaAQADAAYJrgbVKgAaAQAAAA==.Acornita:BAACLgAFFH8MAAMEAAQJsw1aEQCsAAAEAAMJ5w9aEQCsAAAFAAIJXwLiXQBeAAAuAAQKfyoAAwQACQnlD0YRACgCAAQACQnlD0YRACgCAAUABwlIEgokAJ0BAAEuAAUUBgkIAAMArgYA.',
Ad='Adoreith:BAAALgAECgEJAQAAAA==.',
Ae='Aelana:BAAALgADCgkJCQAAAA==.Aendor:BAAALgAECgQJBAABLgAFFAcJIgAGAKEfAA==.Aeria:BAAALgADCgYJBgAAAA==.Aeriith:BAAALgAECgIJAQAAAA==.Aevastraa:BAAALgAECgQJCAABLgAECgkJWQAHADodAA==.',
Ah='Ahyoka:BAAALgAFFAEJAgAAAA==.',
Ai='Ailanthus:BAABLgAECn8uAAIIAAkJRxmvAAAvAgAIAAkJRxmvAAAvAgAAAA==.',
Ak='Akelen:BAAALgAECgMJAwAAAA==.Akinira:BAECLgAFFH8QAAIJAAQJ5RsjGQAeAQAJAAQJ5RsjGQAeAQAuAAQKfz4AAgkACQmVHj4JAH4CAAkACQmVHj4JAH4CAAAA.',
Al='Aleinadris:BAAALgADCgQJBAAAAA==.Alendy:BAAALgAECgcJBwAAAA==.Aliadris:BAAALgADCgIJAgAAAA==.Alikchi:BAAALgADCgEJAgAAAA==.Alloisaber:BAAALgAECgYJCAAAAA==.Alternis:BAAALgAECgMJAwAAAA==.Alunne:BAAALgAECgEJAQAAAA==.',
An='Andrelsia:BAAALgAECgYJCQAAAA==.Andrilla:BAAALgAECggJEQAAAA==.Ankeseth:BAAALgAECgcJCQAAAA==.',
Ap='Apôllyon:BAACLgAFFH8OAAIKAAMJASRjEwAJAQAKAAMJASRjEwAJAQAuAAQKfy4AAgoACQmeJfAAAL4DAAoACQmeJfAAAL4DAAAA.',
Ar='Aracelis:BAAALgAECgcJBwAAAA==.Aradius:BAAALgAECgEJAgABLgAECgIJBwALAAAAAA==.Archertower:BAAALgADCgUJBQAAAA==.Artemiswynd:BAAALgAECgUJCAAAAA==.Arén:BAABLgAECn8qAAMMAAkJch8qFwCLAgAMAAkJOR0qFwCLAgAKAAcJhx+YGwDkAQAAAA==.',
As='Ashenshugär:BAAALgAECgQJCAAAAA==.Asuri:BAAALgAECgEJAQAAAA==.Aszun:BAAALgAECgEJAQABLgAECgEJAQALAAAAAA==.',
Au='Augment:BAAALgADCgcJCgAAAA==.',
Av='Avadda:BAABLgAECn8gAAINAAcJwhE+JwAcAQANAAcJwhE+JwAcAQABLgAECgkJPQAOAH8RAA==.',
Az='Azmar:BAABLgAECn8/AAIPAAgJFSO3GgC6AgAPAAgJFSO3GgC6AgABLgAFFAMJBwAQACQWAA==.',
Ba='Badffinger:BAAALgADCgYJCQAAAA==.Badtouchbull:BAAALgADCgcJBwAAAA==.Balain:BAAALgAECgUJCgABLgAECgcJHQANANsOAA==.Bastan:BAAALgADCgEJAQAAAA==.Bayorn:BAAALgAECgYJCAAAAA==.',
Be='Bear:BAAALgADCgcJBwAAAA==.Bearmont:BAABLgAECn8nAAIGAAgJFRhKEQCwAQAGAAgJFRhKEQCwAQAAAA==.Bearzerk:BAABLgAECn8pAAIRAAkJdhUWJQDNAQARAAkJdhUWJQDNAQAAAA==.Beastmonk:BAAALgADCgEJAQAAAA==.Benathar:BAABLgAECn8pAAIPAAkJkQ0dZAC2AQAPAAkJkQ0dZAC2AQAAAA==.Bethela:BAAALgAECgEJAQABLgAECgEJAQALAAAAAA==.Beyoond:BAAALgAFFAMJBAAAAA==.',
Bi='Bifrost:BAABLgAFFH8FAAIPAAMJvAU5PQCNAAAPAAMJvAU5PQCNAAAAAA==.Bionico:BAABLgAECn8eAAISAAYJBRdjAgA1AQASAAYJBRdjAgA1AQAAAA==.Birgir:BAAALgAECgUJCQABLgAECggJHwATAKEgAA==.',
Bl='Blackmagék:BAAALgADCgkJCQAAAA==.Bladestormer:BAAALgADCgYJBQAAAA==.Blaston:BAAALgAECgYJBgAAAA==.Blazer:BAABLgAFFH8FAAIMAAMJowibcACoAAAMAAMJowibcACoAAAAAA==.Blightbeard:BAAALgAECgIJAgAAAA==.Bloodrager:BAAALgADCgIJAgAAAA==.Bloodthorn:BAABLgAECn8cAAIUAAgJJgY9MAAfAQAUAAgJJgY9MAAfAQAAAA==.Blortimor:BAAALgADCgcJBwAAAA==.',
Bo='Bombad:BAABLgAECn8UAAQRAAgJchIhLwCTAQARAAgJPhIhLwCTAQAHAAMJNgsuPwB0AAASAAEJdQw8fwAqAAAAAA==.Boogiepop:BAABLgAECn8ZAAMVAAcJZx+LTQDeAQAVAAYJjiGLTQDeAQAWAAcJ0RBNPgB/AQAAAA==.Boomnescient:BAABLgAECn8kAAIXAAcJ7gcRjwAhAQAXAAcJ7gcRjwAhAQAAAA==.Bortt:BAAALgAECgQJBQAAAA==.Bozscaggs:BAABLgAECn9IAAMXAAkJkBN2NAALAgAXAAkJkBN2NAALAgAYAAUJAwOsRACuAAAAAA==.',
Br='Bramis:BAAALgADCgkJHAAAAA==.Brantu:BAAALgADCgQJCAABLgAECgEJAQALAAAAAA==.Braultus:BAABLgAECn81AAIJAAkJfx36CgBgAgAJAAkJfx36CgBgAgAAAA==.Breuddwydwr:BAAALgADCgEJAQAAAA==.Brewmeupbro:BAAALgAECgEJAQABLgAECgkJIwAQAFMcAA==.Brewtality:BAAALgAECgEJAQAAAA==.Breyastrasza:BAAALgAECgQJCQAAAA==.Brood:BAAALgAECgYJDwAAAA==.Bruceleroy:BAAALgAECgEJAQAAAA==.Bruinn:BAAALgAECgQJBAABLgAECgcJHQANANsOAA==.',
Bu='Burstangel:BAAALgAECgYJCAAAAA==.',
By='Byrddh:BAAALgADCgQJBAAAAA==.',
['Bä']='Bäguette:BAAALgAECgEJBAAAAA==.',
Ca='Cadenza:BAAALgAECggJEQAAAA==.Caelthar:BAAALgAECgUJCAAAAA==.Cakemaeker:BAAALgAECgEJAQABLgAECgEJAQALAAAAAA==.Caliopedk:BAACLgAFFH8HAAMJAAIJrRjMOwBHAAAQAAIJrRjjOACqAAAJAAIJqALMOwBHAAAuAAQKfxsAAxAACAlIIWUhALsCABAACAlIIWUhALsCAAkABQlJDjQqAO0AAAAA.Caliseni:BAAALgADCgYJCwAAAA==.Capra:BAAALgAECgcJCwAAAA==.Carillanklip:BAAALgADCgUJBQAAAA==.Caydenza:BAAALgAECgMJAwAAAA==.',
Cd='Cdmickey:BAAALgADCgUJBQAAAA==.',
Ce='Celdiseth:BAAALgAECgEJAQAAAA==.Celestè:BAAALgAECggJEQAAAA==.Celéste:BAAALgAECgkJEAAAAA==.Cerdwin:BAAALgAECggJEQABLgAECgkJPwAZABkXAA==.Ceruledge:BAAALgAFFAMJAwABLgAFFAgJLAAaAOkfAA==.',
Ch='Charferad:BAAALgAECggJDwAAAA==.Chatter:BAAALgADCgMJAwAAAA==.Cheaptrick:BAAALgADCgcJEwAAAA==.Chibeard:BAABLgAECn8nAAIOAAkJtSKeAwAVAwAOAAkJtSKeAwAVAwAAAA==.Chihîro:BAAALgAECgUJCgAAAA==.Chonglin:BAAALgADCgMJAwAAAA==.Chrysopteron:BAAALgAECgEJAQABLgAECgEJAQALAAAAAA==.',
Cl='Clearcast:BAAALgADCgkJCwAAAA==.Clevercrane:BAAALgAFFAIJAgABLgAFFAMJBQAFAFgYAA==.Clubsdh:BAAALgAECgMJBAAAAA==.',
Co='Collosus:BAAALgAFFAEJAQABLgAFFAQJCwARAA8RAA==.Coolbro:BAAALgADCgIJAgABLgADCggJCAALAAAAAA==.Corialis:BAAALgAFFAEJAgAAAA==.Counsel:BAAALgAECgUJBQAAAA==.',
Cr='Criantha:BAAALgADCgIJAgAAAA==.Crom:BAACLgAFFH8HAAIbAAMJqAlYEQCzAAAbAAMJqAlYEQCzAAAuAAQKfzoAAhsACQnqEuoOAMIBABsACQnqEuoOAMIBAAAA.Crosis:BAAALgADCgYJBgAAAA==.Cruelladvoid:BAAALgAECgQJBAAAAA==.Cruush:BAAALgAECgYJBQAAAA==.',
Cu='Culerro:BAAALgAECgYJAwABLgAECgYJBQALAAAAAA==.Cursive:BAAALgADCgUJDQAAAA==.',
Cy='Cygnes:BAABLgAECn8jAAIQAAkJUxwrJgBrAgAQAAkJUxwrJgBrAgAAAA==.',
Da='Daddywarrior:BAAALgADCgUJBgAAAA==.Daeva:BAAALgADCgEJAQAAAA==.Dantey:BAAALgADCgcJFAAAAA==.Daus:BAAALgAFFAEJAQAAAA==.Dazanna:BAABLgAECn87AAMWAAkJyhzrCgDeAgAWAAkJyhzrCgDeAgAGAAUJTAvoNQCJAAAAAA==.Dazre:BAAALgAECgUJBgAAAA==.',
De='Deeminor:BAAALgADCgkJEwAAAA==.Demeisen:BAABLgAECn8ZAAIKAAgJaRiDAwBTAQAKAAgJaRiDAwBTAQAAAA==.Demonizerr:BAAALgADCgUJCAAAAA==.Desktop:BAABLgAECn87AAMcAAkJUBxyCADuAgAcAAkJUBxyCADuAgAaAAYJdREuOgAqAQAAAA==.',
Di='Digon:BAAALgAECgEJAQAAAA==.Diod:BAABLgAECn9BAAIHAAkJHRVNEgDGAQAHAAkJHRVNEgDGAQAAAA==.Divineßovine:BAAALgADCgcJBwAAAA==.',
Do='Dolexin:BAAALgADCgkJCQAAAA==.Doombarker:BAAALgADCgYJBgAAAA==.Doomtheory:BAAALgAECgQJBwAAAA==.Dorammu:BAAALgAECgEJAQAAAA==.',
Dr='Dracovoid:BAAALgADCgYJBwAAAA==.Dracvoker:BAAALgAECgQJCAABLgAECgkJKgAMAHIfAA==.Draegyns:BAAALgAECgIJAgABLgAFFAYJFQAdAA4UAA==.Draehton:BAAALgAECgYJBwABLgAFFAQJCwAYAH4XAA==.Dragyns:BAACLgAFFH8VAAMdAAYJDhQHBQAyAQAUAAUJXRCrGwA9AQAdAAQJbRYHBQAyAQAuAAQKfzEABB0ACQngG4ECAMoCAB0ACQmxGYECAMoCABQABgmMGz8sAJwBAB4AAwmrFFIJANwAAAAA.Dragynseye:BAAALgADCgIJAgABLgAFFAYJFQAdAA4UAA==.Drayper:BAABLgAECn9AAAQCAAkJuSFzAAAUAwACAAkJuSFzAAAUAwAcAAEJZw3AWQAvAAAaAAEJaQUrkwAnAAAAAA==.Drayperbark:BAAALgAECgUJDAAAAA==.Druugal:BAACLgAFFH8PAAIUAAUJGhrgGABLAQAUAAUJGhrgGABLAQAuAAQKfy8AAxQACQlwH0YMANQCABQACQlwH0YMANQCAB0AAQl6C+ofADMAAAAA.',
Du='Dubs:BAABLgAECn81AAQfAAkJShy2QADaAQAfAAcJYBy2QADaAQAgAAIJ7hmMIwCVAAATAAIJ/R48CABcAAAAAA==.Dunbarke:BAABLgAECn8fAAITAAgJoSBwAAA3AgATAAgJoSBwAAA3AgAAAA==.Dustrat:BAAALgADCgIJAgAAAA==.',
['Dê']='Dêadlights:BAAALgAECgEJAQAAAA==.',
Ef='Efishient:BAABLgAECn8eAAIZAAYJWCTdHgBIAgAZAAYJWCTdHgBIAgABLgAFFAYJGQAZAH8TAA==.',
El='Elendrisa:BAAALgAECgYJBwAAAA==.Elisoria:BAAALgAECgMJAwAAAA==.Elliwynd:BAABLgAECn8uAAIZAAkJGRQnIgA3AgAZAAkJGRQnIgA3AgAAAA==.',
Eo='Eoshot:BAAALgAECgUJCAAAAA==.',
Er='Erinnys:BAABLgAECn9HAAMKAAkJdRcPDwA1AgAKAAkJdRcPDwA1AgAMAAYJsgWPlgDvAAAAAA==.Ermoril:BAAALgAECgUJBgAAAA==.Ernesta:BAAALgAECgUJBQAAAA==.Eroksix:BAAALgADCgEJAQAAAA==.',
Eu='Eufemia:BAAALgAECgYJCQAAAA==.',
Ev='Evonnya:BAAALgAECgUJBQAAAA==.',
['Eø']='Eøs:BAAALgAECgEJAQAAAA==.',
Fa='Famine:BAAALgAECgcJDAAAAA==.',
Fe='Feelmebro:BAAALgADCggJCAAAAA==.Felern:BAAALgAECgcJCwABLgAFFAMJBwAQACQWAA==.Feyrun:BAAALgADCgkJEwABLgAECgcJDQALAAAAAA==.Feyrè:BAAALgAECgEJAgAAAA==.',
Fi='Fightswiftjr:BAAALgADCgkJCQAAAA==.Filiapatibul:BAAALgAECgEJAQAAAA==.Finalomega:BAABLgAECn8aAAIJAAgJeRfdGACbAQAJAAgJeRfdGACbAQAAAA==.Finnshot:BAAALgAFFAIJAgAAAA==.Finrod:BAAALgAECgcJCQAAAA==.',
Fl='Flaminfalcon:BAABLgAFFH8GAAIaAAIJQBg7KwClAAAaAAIJQBg7KwClAAABLgAFFAMJBQAFAFgYAA==.Flody:BAAALgAFFAEJAQAAAA==.',
Fo='Foxflame:BAABLgAECn8/AAMZAAkJGReqHwBJAgAZAAkJGReqHwBJAgAhAAgJPhD6KACKAQAAAA==.',
Fr='Franzen:BAAALgAECgQJDgAAAA==.Freakbob:BAAALgADCgYJCQAAAA==.Froglocky:BAABLgAECn9AAAMTAAkJ+RY/BgAcAgATAAkJ+RY/BgAcAgAfAAMJcwRi9ABwAAAAAA==.Fronsac:BAAALgADCgQJBAAAAA==.',
Fu='Fulanita:BAABLgAECn8fAAMhAAcJBxAVNgA+AQAhAAcJBxAVNgA+AQAZAAIJSwr6wABFAAAAAA==.',
Ga='Gallager:BAAALgADCgMJAwAAAA==.Garzok:BAABLgAECn8qAAMTAAkJXwy2CwChAQATAAkJXwy2CwChAQAfAAMJzQHnCAFLAAAAAA==.',
Ge='Genkithered:BAABLgAECn82AAIiAAkJoxz5DQDlAgAiAAkJoxz5DQDlAgAAAA==.',
Gi='Gilaras:BAAALgAECgYJDAAAAA==.Gilernil:BAABLgAECn8UAAIXAAYJeQebrwDlAAAXAAYJeQebrwDlAAAAAA==.',
Gl='Gladtohelp:BAAALgAECgIJAgAAAA==.Gloomy:BAAALgADCgEJAQAAAA==.',
Gn='Gnoquarter:BAAALgADCgIJAgABLgAECgkJGQAQAEUZAA==.',
Go='Gourak:BAAALgAECgYJBwAAAA==.',
Gr='Gravemarks:BAABLgAECn8YAAMeAAgJqBNCCQCXAQAeAAgJqBNCCQCXAQAdAAQJzAncEQDoAAAAAA==.Grimhorn:BAABLgAECn8oAAMhAAkJWArSCgCOAAAhAAgJwArSCgCOAAANAAIJJwQmfAAnAAAAAA==.Grimlie:BAAALgAECgEJAQAAAA==.Grimmrock:BAAALgAECgcJDgAAAA==.Grumblen:BAAALgADCgMJAwAAAA==.',
Gu='Guaritrice:BAABLgAECn8aAAMaAAcJdguGPQAbAQAaAAcJdguGPQAbAQACAAEJYQd3egAfAAAAAA==.Gubb:BAAALgAECgMJAwAAAA==.',
Gw='Gwenylane:BAABLgAECn8sAAIVAAkJSAuSdACFAQAVAAkJSAuSdACFAQAAAA==.Gwindor:BAAALgAECgYJCQAAAA==.Gwyndelyn:BAABLgAECn8xAAIBAAgJ9wtONAAyAQABAAgJ9wtONAAyAQAAAA==.',
Ha='Hatterus:BAABLgAECn9MAAIVAAkJ0RALEAD3AAAVAAkJ0RALEAD3AAAAAA==.',
He='Herculeze:BAABLgAFFH8IAAIWAAMJfRnPEwB1AAAWAAMJfRnPEwB1AAAAAA==.Hessian:BAAALgADCgEJAQAAAA==.Hetairoi:BAAALgAECgIJAgABLgAFFAMJDQABADUfAA==.Hetd:BAAALgAECgEJAwABLgAFFAMJDQABADUfAA==.',
Hi='Hillbroken:BAABLgAECn9QAAIjAAkJqSJaAgDrAgAjAAkJqSJaAgDrAgAAAA==.Himduncan:BAAALgAECgMJBAAAAA==.Hippie:BAAALgADCgMJAwAAAA==.',
Ho='Hohalt:BAAALgAECgEJAgAAAA==.Holycross:BAAALgAECgQJBQAAAA==.Holysmokers:BAAALgAECgYJDAABLgAFFAYJFQAdAA4UAA==.Holysnow:BAAALgADCgkJDAABLgAECgkJFAAXAD8dAA==.Holysoul:BAAALgAECgEJAwAAAA==.',
Hu='Huntertidus:BAAALgAECggJEgABLgAECgkJMAAVAJobAA==.Huntrix:BAAALgAECggJCgAAAA==.',
Hy='Hydan:BAAALgAECgUJBQAAAA==.Hyrlis:BAAALgAECgEJAQAAAA==.',
['Hà']='Hànks:BAABLgAECn8gAAIVAAkJ7g2uZgCiAQAVAAkJ7g2uZgCiAQAAAA==.',
Ia='Iantosarian:BAAALgAECgQJBAAAAA==.',
Ib='Ibíng:BAAALgAECgYJBwAAAA==.',
Ic='Iceatron:BAAALgADCgUJBQAAAA==.',
Im='Imo:BAABLgAECn8vAAMfAAkJ/xFsCQAFAQAfAAkJ+xBsCQAFAQAgAAUJIhJxJgCBAAAAAA==.',
In='Intrepidz:BAAALgAECgEJAgABLgAFFAMJBQAFAFgYAA==.Inèvitable:BAABLgAECn9CAAIQAAkJHh13IwB4AgAQAAkJHh13IwB4AgAAAA==.',
Ir='Ironphant:BAAALgAECgYJBgAAAA==.',
Is='Istara:BAAALgAECgQJBAAAAA==.',
Iv='Ivorin:BAAALgAECgYJCgAAAA==.',
Ja='Jabujabu:BAAALgAECgcJDAABLgAFFAQJDgAMAEEPAA==.Javeech:BAACLgAFFH8HAAIXAAMJkxCxXwDlAAAXAAMJkxCxXwDlAAAuAAQKfygAAxcACQl5GtcnAEACABcACAnQHNcnAEACABgAAQkVCjtiADcAAAAA.',
Je='Jebib:BAAALgAECgYJBgABLgAFFAkJOgAZAMUiAA==.Jeod:BAAALgAECgYJCQAAAA==.',
Ji='Jirachi:BAAALgADCgEJAQAAAA==.',
Jo='Jolty:BAACLgAFFH8aAAIQAAYJUSBOJQDXAQAQAAYJUSBOJQDXAQAuAAQKfykAAxAACQlWIq8MADUDABAACQlWIq8MADUDAAkABAmkFmMyANMAAAAA.Joydivision:BAAALgADCgIJAgAAAA==.',
Ju='Julian:BAAALgAECggJCAABLgAECgkJPwAUACwkAA==.',
['Jð']='Jð:BAAALgAECgQJBAABLgAECgYJJQAMAGAhAA==.',
Ka='Kaboomchickn:BAAALgAECgIJAgABLgAECggJDwALAAAAAA==.Kaiou:BAAALgADCgQJCAAAAA==.Kalmia:BAAALgAECgQJCAAAAA==.Kantor:BAABLgAECn9SAAMCAAkJLhiNFgAcAgACAAkJLhiNFgAcAgAaAAIJvQs7hgAzAAAAAA==.Karboomkin:BAABLgAFFH8GAAMNAAUJQhRcEgDxAAANAAQJQhRcEgDxAAAhAAEJAACNWgAAAAABLgAFFAgJGwAVAN0gAA==.Karlin:BAAALgAECgEJAQABLgAECgEJAQALAAAAAA==.Karnstein:BAABLgAECn8oAAQkAAgJ4BEXDABQAQAkAAYJuxAXDABQAQAFAAYJBxEuSwD/AAAEAAUJgwTuMwDOAAAAAA==.Kasenko:BAAALgAECgIJAgABLgAECgYJIgANAHkYAA==.Kasryna:BAABLgAECn8iAAINAAYJeRgvHgBcAQANAAYJeRgvHgBcAQAAAA==.Kathinja:BAABLgAECn8tAAIXAAkJxAlNWwCTAQAXAAkJxAlNWwCTAQAAAA==.Katiebeary:BAAALgAECgcJCwAAAA==.',
Ke='Kelthera:BAAALgAECgYJBgAAAA==.Kelumbria:BAAALgAECgkJDwAAAA==.Keta:BAAALgADCgYJBgAAAA==.Ketameanie:BAABLgAECn87AAIMAAkJFhhpJQA4AgAMAAkJFhhpJQA4AgAAAA==.',
Ki='Kieran:BAAALgAECgQJCgAAAA==.Kiley:BAAALgAECgkJCAAAAA==.Killerkitten:BAAALgADCgEJAQAAAA==.Kitsunè:BAAALgAECgEJAQAAAA==.',
Km='Kmazing:BAABLgAECn8xAAMBAAkJFg6pJgCBAQABAAkJFg6pJgCBAQADAAYJYhjyBgBgAQAAAA==.',
Kn='Knifèparty:BAABLgAECn85AAIdAAkJkSIEAgDOAgAdAAkJkSIEAgDOAgAAAA==.',
Ko='Konoha:BAABLgAECn8tAAMcAAkJFiE4BgAfAwAcAAkJCCA4BgAfAwACAAMJfiPoQwApAQAAAA==.',
Kr='Krodus:BAAALgAECggJCAABLgAECgkJJgAbAFkaAA==.',
Ku='Kultag:BAABLgAECn8fAAIVAAkJBRYnOwAXAgAVAAkJBRYnOwAXAgAAAA==.',
Ky='Kyaw:BAABLgAECn8WAAQUAAYJbRyAKAC2AQAUAAYJbRyAKAC2AQAdAAIJxRJbFgCTAAAeAAEJPRTmIwA4AAAAAA==.Kynzo:BAABLgAECn9FAAIIAAkJXB59BAC4AgAIAAkJXB59BAC4AgAAAA==.',
La='Laykeezenith:BAACLgAFFH8WAAQlAAYJJh0rBwCrAQAlAAYJmxorBwCrAQAXAAMJ7SJuQQBjAAAYAAEJvQefMwBDAAAuAAQKfyIABCUACQmZIl4VAIcCACUACAnqIl4VAIcCABcACAm9IZY5APgBABgAAgl3EgooAHUAAAAA.Lazuli:BAACLgAFFH8HAAImAAUJnQ9eKwDoAAAmAAUJnQ9eKwDoAAAuAAQKf14AAyYACQk0G6wBABICACYACQk0G6wBABICABsAAQk8BXdFACUAAAAA.',
Le='Lehann:BAABLgAECn8rAAIXAAkJxw+tSwC/AQAXAAkJxw+tSwC/AQAAAA==.',
Li='Lichtech:BAAALgAFFAIJAgABLgAFFAgJIQAFAFEdAA==.Lightsbane:BAABLgAECn8XAAINAAcJehAcJAAwAQANAAcJehAcJAAwAQAAAA==.Lilìana:BAAALgADCgEJAQAAAA==.',
Lo='Lockatron:BAAALgADCgcJDgAAAA==.',
Lu='Luciselda:BAAALgADCgUJBgAAAA==.Lumosnox:BAAALgAECgMJAwAAAA==.Lunariah:BAAALgADCgkJEwAAAA==.Luvtarhugar:BAAALgAECgUJBQAAAA==.',
['Lé']='Léann:BAAALgADCgUJBQAAAA==.',
Ma='Madaran:BAAALgAECggJEQABLgAECgkJJgAbAFkaAA==.Magdalene:BAEALgAECgUJCQABLgAFFAcJGgATAKYWAA==.Marebear:BAAALgADCgIJAgAAAA==.Marenus:BAABLgAECn9PAAIXAAkJQRHRRwDKAQAXAAkJQRHRRwDKAQAAAA==.Masume:BAABLgAECn8YAAIaAAgJOQtFBABEAQAaAAgJOQtFBABEAQAAAA==.Maély:BAAALgAECgEJAwAAAA==.',
Me='Mechadead:BAAALgADCggJCAAAAA==.Medal:BAAALgAECgEJAQAAAA==.Melody:BAAALgAECgYJBgAAAA==.Meowmix:BAAALgADCgcJDAAAAA==.',
Mi='Miantha:BAAALgAECgYJBwAAAA==.Michi:BAABLgAECn82AAMZAAkJgyJwBAB3AwAZAAkJgyJwBAB3AwAIAAYJLBYNGQBHAQAAAA==.Midnights:BAAALgAECggJEAAAAA==.Mightymopo:BAAALgADCgMJAwAAAA==.Mikuki:BAABLgAECn8jAAIXAAkJvCP4EgC6AgAXAAkJvCP4EgC6AgAAAA==.Milkinghands:BAABLgAECn8hAAMDAAkJ1g+KOwCCAQADAAkJ1g+KOwCCAQABAAEJlAI/tgAiAAAAAA==.Minabos:BAAALgAECgQJDAAAAA==.Mizmonk:BAACLgAFFH8gAAIOAAcJnBl3CwDcAQAOAAcJnBl3CwDcAQAuAAQKfyIAAg4ACQnxHqMJAO4CAA4ACQnxHqMJAO4CAAAA.',
Mj='Mjölnir:BAAALgAECgcJCQAAAA==.',
Mo='Montfort:BAAALgADCggJDwAAAA==.Mootality:BAABLgAFFH8HAAIQAAMJJBa+KwDsAAAQAAMJJBa+KwDsAAAAAA==.Moovover:BAAALgAECggJCgAAAA==.Morningcrow:BAAALgAECgYJCgAAAA==.',
Ms='Msmaho:BAAALgAECggJEQAAAA==.',
Mu='Muhdeeps:BAAALgADCgQJBAAAAA==.Murionor:BAAALgADCgEJAQAAAA==.Mushuu:BAAALgAECggJCgAAAA==.',
My='Mykian:BAABLgAECn8pAAMkAAkJAQf1EAD7AAAFAAkJ0QTZQwAaAQAkAAcJ1Qf1EAD7AAAAAA==.Myrwynn:BAAALgAECgMJAwABLgAFFAMJCQAaAKULAA==.Mythlee:BAAALgAECgUJCAAAAA==.Mythundon:BAAALgADCgUJBQAAAA==.',
Na='Nahion:BAAALgAECgYJCQAAAA==.Nashira:BAABLgAECn8oAAIXAAkJvhhKBAD6AQAXAAkJvhhKBAD6AQAAAA==.Nathalas:BAAALgAECgEJAgABLgAECgkJPwAUACwkAA==.Nature:BAAALgAECgUJCwAAAA==.',
Ne='Necrana:BAAALgADCgEJAQAAAA==.Necrobyarg:BAAALgAECgYJDQAAAA==.Nemasus:BAABLgAECn9DAAMZAAkJ5B3HCwADAwAZAAkJ5B3HCwADAwAhAAEJRQzVjgAxAAAAAA==.Nembie:BAAALgAECgUJCQAAAA==.Nethertech:BAABLgAFFH8LAAIMAAUJ0hEqSQANAQAMAAUJ0hEqSQANAQABLgAFFAgJIQAFAFEdAA==.',
Ni='Ninjahh:BAACLgAFFH8UAAIUAAUJMxGeDgDjAAAUAAUJMxGeDgDjAAAuAAQKfygAAhQACAkrFzAZANEBABQACAkrFzAZANEBAAAA.Niobei:BAAALgADCgcJBwABLgAECgkJYQAiAEcZAA==.Nioshei:BAABLgAECn9hAAMiAAkJRxncAgAQAgAiAAkJRxncAgAQAgAmAAEJCQfHuQAjAAAAAA==.Nisara:BAACLgAFFH8MAAIDAAQJvRMqMQDvAAADAAQJvRMqMQDvAAAuAAQKf0UAAwMACQmRH4QKAPECAAMACQmRH4QKAPECAAEACQmmIa4AAKkCAAAA.',
No='Nochmuerta:BAABLgAECn8ZAAIQAAkJRRmAKgBWAgAQAAkJRRmAKgBWAgAAAA==.Nogrid:BAABLgAECn9RAAIGAAkJHBsDBwBxAgAGAAkJHBsDBwBxAgAAAA==.Nossaria:BAAALgAECgIJAgAAAA==.Notmyface:BAAALgAECgcJEwABLgAFFAIJBwARAI8WAA==.',
Nu='Nuorong:BAAALgAECgUJBQABLgAECgkJPwAZABkXAA==.Nuthar:BAABLgAECn9HAAIVAAkJniUwAwBnAwAVAAkJniUwAwBnAwAAAA==.',
Ny='Nyxandra:BAAALgAECgcJCwAAAA==.',
['Né']='Nésta:BAAALgAECgcJDQAAAA==.',
['Nò']='Nòhva:BAAALgAECgQJBAAAAA==.',
Ol='Oldeis:BAAALgAECgEJAQAAAA==.',
Om='Ominousowl:BAABLgAFFH8FAAIFAAMJWBhVOADkAAAFAAMJWBhVOADkAAAAAA==.',
Or='Oregizm:BAAALgAFFAEJAQAAAA==.Orneryosprey:BAAALgAFFAIJAgABLgAFFAMJDQABADUfAA==.',
Ou='Ourobius:BAAALgAECgQJCAAAAA==.',
Pa='Pamburu:BAABLgAECn8jAAQXAAgJ8w2yegBKAQAXAAgJpg2yegBKAQAlAAYJvgUKIQCpAAAYAAIJrQUPKgBgAAAAAA==.Papagrape:BAABLgAECn9TAAQEAAkJ/CHxAQBlAwAEAAkJ/CHxAQBlAwAkAAcJexz0BQD4AQAFAAMJaRaWWgDKAAAAAA==.Parzivàl:BAABLgAECn8mAAIWAAgJehiaEwB1AgAWAAgJehiaEwB1AgAAAA==.Paxa:BAABLgAECn8xAAMCAAgJbxsGFgAiAgACAAgJbxsGFgAiAgAaAAYJTgvrRwDwAAAAAA==.',
Pe='Peacebox:BAAALgADCggJDAABLgAECgkJMQABABYOAA==.Persayis:BAAALgAECggJEQAAAA==.',
Ph='Phoebel:BAAALgAECgEJAQAAAA==.Phoenixbodhi:BAAALgAECgQJBAAAAA==.',
Pi='Pickledeggs:BAAALgAECgcJCAABLgAECgkJJQAPAFwaAA==.',
Po='Podnov:BAACLgAFFH8eAAMlAAYJhiCKCwCpAQAlAAYJhiCKCwCpAQAXAAIJpB09iACNAAAuAAQKfyMAAiUACQlEHcwNANYCACUACQlEHcwNANYCAAAA.Pollyanna:BAAALgADCgEJAQAAAA==.',
Pr='Preyon:BAABLgAECn8dAAINAAcJ2w4zCACqAAANAAcJ2w4zCACqAAAAAA==.',
Py='Pyne:BAAALgADCgEJAQAAAA==.Pyrista:BAAALgAECgkJDAAAAA==.',
Qa='Qang:BAAALgAECggJDgAAAA==.',
Qo='Qotho:BAABLgAECn9IAAIXAAkJYhtjKAA9AgAXAAkJYhtjKAA9AgAAAA==.',
Ra='Raikou:BAAALgAECgUJBQABLgAFFAgJLAAaAOkfAA==.Raistliin:BAAALgAECgYJDgAAAA==.Raithis:BAACLgAFFH8dAAIXAAYJjxgxHgCMAQAXAAYJjxgxHgCMAQAuAAQKfzIAAhcACQlAIsAEAEEDABcACQlAIsAEAEEDAAAA.Raito:BAAALgADCgUJBQAAAA==.Ramhadin:BAEALgAECgMJDQABLgAECgkJOQAaALMfAA==.Ramzert:BAEALgAECgIJAgABLgAECgkJOQAaALMfAA==.Rav:BAAALgADCgMJBgAAAA==.',
Re='Rednaxel:BAABLgAECn9ZAAMUAAkJMyV7AQBeAwAUAAkJ7yR7AQBeAwAdAAUJRx9yCADEAQAAAA==.Redvelvet:BAABLgAECn8vAAMDAAkJgRbVBQCAAQADAAkJgRbVBQCAAQABAAQJ9Ab5WwCgAAAAAA==.Rekoner:BAABLgAECn8mAAIQAAkJRxPwSQDkAQAQAAkJRxPwSQDkAQAAAA==.Resi:BAAALgAECgIJAgAAAA==.Resii:BAAALgAECgEJAgABLgAECgIJAgALAAAAAA==.Reyalanta:BAAALgAECgYJDwABLgAECgkJOQAdAJEiAA==.',
Ri='Ringmistress:BAAALgADCgcJBwAAAA==.Rixaa:BAAALgADCgQJBwABLgAECgkJIwAXAGgcAA==.',
Ro='Rocks:BAAALgAECgYJCAAAAA==.Romam:BAAALgAECgYJCQAAAA==.',
Ru='Rubyknight:BAAALgAECgEJAQAAAA==.',
Ry='Rydran:BAAALgAECgUJCQAAAA==.Rykria:BAAALgAECgQJDAAAAA==.',
Sa='Samsonknight:BAAALgADCgYJBgAAAA==.Sanasat:BAAALgADCgMJAwAAAA==.Sanguinarian:BAABLgAECn8XAAIVAAgJIQ32sAAeAQAVAAgJIQ32sAAeAQAAAA==.Savash:BAAALgAECggJEgAAAA==.',
Sc='Scrubtotem:BAAALgAECgMJAwAAAA==.',
Se='Secksiecutie:BAABLgAECn82AAMjAAkJ7hpKBQBmAgAjAAkJ7hpKBQBmAgAJAAcJvQw8LQDzAAAAAA==.Selanda:BAAALgAECgQJBAAAAA==.Selval:BAAALgAECgQJCwAAAA==.Serinar:BAABLgAFFH8IAAIVAAMJoAODhACrAAAVAAMJoAODhACrAAAAAA==.Serraphem:BAAALgAECgEJAQAAAA==.',
Sh='Shadoe:BAAALgADCgMJAwAAAA==.Shafrog:BAAALgAECgIJAgABLgAECgkJQAATAPkWAA==.Shoshin:BAABLgAECn8aAAMOAAcJ3w0ITADOAAAOAAcJ3w0ITADOAAABAAQJJgxhXQCbAAABLgAECgcJHQANANsOAA==.Shïvana:BAAALgAECgMJDwAAAA==.',
Si='Silversaiyan:BAABLgAECn9LAAMRAAkJwCFoDgCLAgARAAkJwCFoDgCLAgASAAEJXRiEOgBGAAAAAA==.',
Sk='Skaddi:BAAALgAECgEJAQAAAA==.Skullpanda:BAAALgAECggJCAAAAA==.',
Sl='Slade:BAABLgAECn8/AAMUAAkJLCRvAwATAwAUAAkJLCRvAwATAwAdAAMJ+xuUEwDvAAAAAA==.Slap:BAAALgAECgEJAQAAAA==.Slaps:BAAALgADCgkJCQAAAA==.Sliyce:BAAALgAECgIJBwAAAA==.',
Sm='Smóke:BAABLgAECn9RAAIMAAkJKxWnNgDsAQAMAAkJKxWnNgDsAQAAAA==.',
Sn='Sneakyclubs:BAAALgAECgMJAwABLgAECgMJBAALAAAAAA==.Snore:BAAALgADCgQJBgAAAA==.Snowfawn:BAABLgAECn8rAAIXAAkJYheVKQA4AgAXAAkJYheVKQA4AgABLgAECgkJFAAXAD8dAA==.Snowieblaze:BAAALgAECgQJBAABLgAECgkJFAAXAD8dAA==.Snowiefox:BAAALgADCgkJCQABLgAECgkJFAAXAD8dAA==.',
So='Sofedan:BAABLgAECn9RAAIlAAkJuA89DACgAQAlAAkJuA89DACgAQAAAA==.Sorgath:BAAALgAECgUJDAAAAA==.Soriel:BAABLgAECn89AAIOAAkJfxG5AQCQAQAOAAkJfxG5AQCQAQAAAA==.Sorokwa:BAABLgAECn8XAAIQAAkJKgLb+wCxAAAQAAkJKgLb+wCxAAAAAA==.',
Sq='Squeeze:BAAALgADCgYJBQAAAA==.Squids:BAAALgADCgQJBAAAAA==.',
St='Stallon:BAAALgAECgEJAgAAAA==.Stillwater:BAAALgADCgkJCQAAAA==.Strongstork:BAAALgAFFAIJBAABLgAFFAMJDQABADUfAA==.',
Su='Sunsword:BAAALgAECgYJEQAAAA==.Suriden:BAAALgAECgYJBwAAAA==.',
Sw='Swagidan:BAABLgAECn8uAAIKAAgJ4xgAEgBMAgAKAAgJ4xgAEgBMAgAAAA==.Sweatermonk:BAAALgADCgIJAgABLgAECgYJBgALAAAAAA==.Sweaterpally:BAAALgAECgYJBgAAAA==.Swiftera:BAABLgAECn8lAAIWAAkJIxaEKADqAQAWAAkJIxaEKADqAQAAAA==.Swiftlier:BAABLgAECn8vAAIOAAkJtxn8FQD8AQAOAAkJtxn8FQD8AQAAAA==.Swipegirl:BAAALgAECgYJCQAAAA==.',
Sy='Sybelyyia:BAAALgAECgUJBgAAAA==.Sylphrène:BAABLgAECn8yAAIKAAkJIwezKQAwAQAKAAkJIwezKQAwAQAAAA==.Sylriane:BAAALgAECgEJAgAAAA==.',
Ta='Taboo:BAAALgAECgEJAQAAAA==.Taladan:BAAALgAECgQJBQAAAA==.Tallyian:BAAALgAECgEJAwAAAA==.Tandrana:BAAALgAECgQJBwAAAA==.Tankmepapi:BAAALgAECgMJAwAAAA==.Tanwen:BAABLgAECn8UAAQEAAYJ+QcWJgC8AAAEAAYJ+QcWJgC8AAAkAAQJHAMENwBfAAAFAAIJAALnmwAmAAAAAA==.Targdh:BAACLgAFFH8OAAIMAAQJQQ96GwDzAAAMAAQJQQ96GwDzAAAuAAQKf14AAwwACQllHyoRALkCAAwACQllHyoRALkCACcABAmMGNESACUBAAAA.Targquellin:BAAALgAECgcJBwABLgAFFAQJDgAMAEEPAA==.Targypunch:BAAALgADCgcJBwABLgAFFAQJDgAMAEEPAA==.Tatsunoshinn:BAAALgADCgEJAQAAAA==.',
Te='Techniqe:BAACLgAFFH8hAAMFAAgJUR1LCAB1AgAFAAgJUR1LCAB1AgAEAAEJrwEkLQAxAAAuAAQKfzcAAwUACAkkIxsHAAoDAAUACAkkIxsHAAoDACQABgkgIe8SALMBAAAA.Techtides:BAAALgAECgIJAgABLgAFFAgJIQAFAFEdAA==.Temperance:BAAALgADCgEJAQAAAA==.Temptations:BAAALgAECgUJBgAAAA==.Terminus:BAAALgAECggJCwAAAA==.Terrylin:BAAALgAECgYJBwAAAA==.',
Th='Thaliá:BAAALgADCgkJFQAAAA==.Themachinist:BAAALgAECgYJBgAAAA==.Thomag:BAAALgADCgIJAgAAAA==.Thor:BAAALgAECgYJCgAAAA==.',
Ti='Ticebane:BAACLgAFFH8WAAMJAAYJSgr2JQDCAAAJAAUJ4wv2JQDCAAAQAAMJRgMe/gBuAAAuAAQKfyMAAgkACQk0GbALAFgCAAkACQk0GbALAFgCAAAA.Tidusdruo:BAAALgAECgMJAwABLgAECgkJMAAVAJobAA==.Tiduspullo:BAABLgAECn8wAAMVAAkJmhuTRAAWAgAVAAkJdxWTRAAWAgAGAAgJ5BqIAwANAQAAAA==.Tiduswar:BAABLgAECn8pAAMHAAcJJhy/AQCaAQAHAAcJJhy/AQCaAQARAAIJfRI6gwBtAAABLgAECgkJMAAVAJobAA==.Tinafay:BAAALgAECgcJDAAAAA==.Tiramisuu:BAAALgAECgcJDwAAAA==.Titanbeard:BAAALgAECgMJBQAAAA==.Titor:BAABLgAECn9JAAMEAAkJ6BfXAADJAQAEAAkJ6BfXAADJAQAkAAYJgA+hEAABAQAAAA==.Tituspullo:BAAALgAECgcJCgABLgAECgkJMAAVAJobAA==.',
To='Tolduan:BAAALgAECgUJDQAAAA==.Totemik:BAABLgAECn8mAAIbAAkJWRoxAQC2AQAbAAkJWRoxAQC2AQAAAA==.Toughturkey:BAABLgAFFH8NAAMBAAMJNR9dHwDcAAABAAMJNR9dHwDcAAADAAIJnRgIJwBbAAAAAA==.Towen:BAAALgADCgUJBQAAAA==.Toy:BAAALgADCgYJGwAAAA==.',
Tr='Tremorhoof:BAAALgADCgIJAwAAAA==.Tresera:BAAALgADCgEJAQAAAA==.Tricarnetry:BAABLgAECn8wAAMWAAkJZxIiUAD5AAAWAAYJsQkiUAD5AAAVAAkJuBDnEgDZAAAAAA==.Tricarnity:BAAALgADCgYJBgAAAA==.Trufleshufle:BAAALgAECggJEQAAAA==.',
['Tà']='Tàlle:BAAALgAECgMJAwAAAA==.',
Uh='Uhtread:BAAALgADCgYJBQAAAA==.',
Ul='Ulfer:BAAALgAECgUJBQABLgAFFAMJDAAJAMAhAA==.',
Un='Unholyfury:BAAALgADCgYJBgAAAA==.',
Va='Vapor:BAAALgAECgQJBQAAAA==.Vaquinha:BAAALgADCgUJBQAAAA==.Varyel:BAAALgAECgIJAgAAAA==.',
Ve='Velianne:BAAALgADCgUJBQAAAA==.Vellinada:BAAALgADCgMJAwABLgAFFAgJKgACAKUkAA==.Verakis:BAABLgAECn9ZAAIHAAkJOh3GAABfAgAHAAkJOh3GAABfAgAAAA==.Verndarí:BAABLgAECn8ZAAMJAAkJ1Q2RHgBiAQAJAAkJ1Q2RHgBiAQAjAAMJzgU1LgBoAAABLgAECgkJLwAOALcZAA==.Verudora:BAAALgAECgUJBgAAAA==.Vervain:BAAALgAECgUJBQAAAA==.',
Vl='Vladd:BAAALgAFFAEJAQAAAA==.',
Vo='Vonnie:BAAALgADCgkJCQAAAA==.Vortheus:BAAALgAECgkJEwAAAA==.Votollis:BAAALgAECgQJBQAAAA==.',
Wa='Warlanen:BAAALgAECgUJBgAAAA==.Warning:BAAALgADCgUJBQAAAA==.Warpiggies:BAAALgADCgkJCAABLgAFFAQJDgAMAEEPAA==.',
Wi='Widdy:BAAALgAECgcJEAAAAA==.Willbur:BAABLgAECn9JAAIPAAkJVxr1LABlAgAPAAkJVxr1LABlAgAAAA==.Wittledwagon:BAAALgADCgkJCQAAAA==.',
Wu='Wurthwhile:BAAALgAECgYJDgAAAA==.',
Wy='Wylaniris:BAAALgADCgQJBAAAAA==.Wyndywalker:BAABLgAECn82AAIhAAkJqQlANABIAQAhAAkJqQlANABIAQAAAA==.',
Xa='Xaveil:BAAALgADCgEJAQAAAA==.',
Xe='Xenosian:BAAALgAECgkJCQAAAA==.',
Xi='Xinnou:BAAALgAECgEJAgAAAA==.Xinnuo:BAAALgAECgQJBwAAAA==.',
Xy='Xydias:BAAALgAECggJDwAAAA==.Xyra:BAAALgADCgcJBwAAAA==.',
Yo='Yoku:BAAALgAECggJEwAAAA==.Yondadk:BAAALgAECgEJAQAAAA==.',
Yu='Yunxiao:BAAALgAECgEJAQAAAA==.',
Za='Zacian:BAAALgAECgEJAQABLgAFFAgJLAAaAOkfAA==.Zag:BAAALgAECgEJAQABLgAECgkJMAAnALYWAA==.Zalgarian:BAAALgAECgcJDwAAAA==.Zamønk:BAABLgAECn8ZAAMOAAcJFg8WOABqAQAOAAcJFg8WOABqAQABAAIJ+wypmAA2AAAAAA==.Zaphoidvtwo:BAAALgAECgUJCwAAAA==.Zason:BAAALgADCgMJAwAAAA==.Zatari:BAAALgADCgMJAwAAAA==.Zavaen:BAAALgADCgEJAQAAAA==.',
Ze='Zelectie:BAACLgAFFH8GAAINAAQJfwXaIQCVAAANAAQJfwXaIQCVAAAuAAQKfxcAAg0ACAluFzIKAPcBAA0ACAluFzIKAPcBAAEuAAUUBwkSAAkAsxAA.Zelzaikin:BAAALgAECgQJBgAAAA==.Zevon:BAAALgAECgYJCgAAAA==.',
Zi='Ziarra:BAAALgADCgYJBgABLgADCgcJDQALAAAAAA==.Zinazarinara:BAAALgAECgIJAgAAAA==.Zirril:BAAALgADCgcJDwAAAA==.',
Zo='Zombiechick:BAAALgAECgMJBAAAAA==.Zorn:BAAALgAECgMJAwAAAA==.',
['Ån']='Ånimaul:BAAALgAFFAEJAQABLgAFFAgJIQAFAFEdAA==.',
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
