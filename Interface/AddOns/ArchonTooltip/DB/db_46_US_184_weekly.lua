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

local lookup = {'Monk-Windwalker','Priest-Holy','Monk-Mistweaver','Evoker-Preservation','Evoker-Augmentation','Paladin-Protection','Warrior-Protection','Druid-Feral','DeathKnight-Blood','DemonHunter-Havoc','Unknown-Unknown','DemonHunter-Devourer','Paladin-Retribution','Druid-Guardian','Monk-Brewmaster','Mage-Frost','DeathKnight-Unholy','Warrior-Fury','Warrior-Arms','Warlock-Affliction','Rogue-Subtlety','Paladin-Holy','Hunter-BeastMastery','Hunter-Survival','Druid-Restoration','Priest-Shadow','Shaman-Elemental','Shaman-Enhancement','Priest-Discipline','DemonHunter-Vengeance','Rogue-Assassination','Rogue-Outlaw','Warlock-Demonology','Warlock-Destruction','Druid-Balance','Shaman-Restoration','DeathKnight-Frost','Evoker-Devastation','Hunter-Marksmanship',}
local provider = {region='US',realm='ScarletCrusade',name='US',type='weekly',zone=46,date='2026-08-18',data={Ac='Acefu:BAABLgAECn8ZAAIBAAkJUSK8CAC7AgABAAkJUSK8CAC7AgAAAA==.Acornella:BAABLgAFFH8FAAICAAUJARNDEQBFAQACAAUJARNDEQBFAQABLgAFFAYJCAADAK4GAA==.Acorneo:BAABLgAFFH8IAAIDAAYJrgbVKgAaAQADAAYJrgbVKgAaAQAAAA==.Acornita:BAACLgAFFH8MAAMEAAQJsw1aEQCsAAAEAAMJ5w9aEQCsAAAFAAIJXwLiXQBeAAAuAAQKfyoAAwQACQnlD0YRACgCAAQACQnlD0YRACgCAAUABwlIEgokAJ0BAAEuAAUUBgkIAAMArgYA.',
Ad='Adoreith:BAAALgAECgEJAQAAAA==.',
Ae='Aelana:BAAALgADCgkJCQAAAA==.Aendor:BAAALgAECgQJBAABLgAFFAgJKgAGAKsgAA==.Aerea:BAAALgAECgEJAgAAAA==.Aeria:BAAALgADCgYJBgAAAA==.Aeriith:BAAALgAECgMJAQAAAA==.Aevastraa:BAABLgAECn8WAAIGAAgJFxhzAgDuAQAGAAgJFxhzAgDuAQABLgAECgkJXQAHAJQdAA==.',
Ah='Ahyoka:BAAALgAFFAEJAgAAAA==.',
Ai='Ailanthus:BAABLgAECn9AAAIIAAkJbBz4AACEAgAIAAkJbBz4AACEAgAAAA==.',
Ak='Akelen:BAAALgAECgMJAwAAAA==.Akinira:BAECLgAFFH8QAAIJAAQJ5RsjGQAeAQAJAAQJ5RsjGQAeAQAuAAQKfz4AAgkACQmVHj4JAH4CAAkACQmVHj4JAH4CAAAA.',
Al='Aleinadris:BAAALgADCgQJBAAAAA==.Alendy:BAAALgAECggJCAAAAA==.Aliadris:BAAALgADCgIJAgAAAA==.Alikchi:BAAALgADCgEJAgAAAA==.Alloisaber:BAAALgAECgYJCAAAAA==.Alternis:BAAALgAECgMJAwAAAA==.Alunne:BAAALgAECgEJAQAAAA==.',
An='Andrelsia:BAAALgAECgYJCQAAAA==.Andrilla:BAAALgAECgkJEgAAAA==.Ankeseth:BAAALgAECgcJCgAAAA==.',
Ap='Apôllyon:BAACLgAFFH8OAAIKAAMJASRjEwAJAQAKAAMJASRjEwAJAQAuAAQKfy4AAgoACQmeJfAAAL4DAAoACQmeJfAAAL4DAAAA.',
Ar='Aracelis:BAAALgAECgcJCAAAAA==.Aradius:BAAALgAECgEJAgABLgAECgIJBwALAAAAAA==.Archertower:BAAALgADCgUJBQAAAA==.Artemiswynd:BAAALgAECgUJCAAAAA==.Arén:BAABLgAECn8qAAMMAAkJch8qFwCLAgAMAAkJOR0qFwCLAgAKAAcJhx+YGwDkAQAAAA==.',
As='Ashenshugär:BAAALgAECgQJCQAAAA==.Asuri:BAAALgAECgEJAQAAAA==.Aszian:BAAALgADCgUJBQAAAA==.Aszun:BAAALgAECgEJAQABLgAECgIJAwALAAAAAA==.',
At='Atractiva:BAAALgAECgEJAQAAAA==.',
Au='Augment:BAAALgADCgcJCgABLgAFFAMJBQANAEEOAA==.Aurthon:BAAALgADCgMJAwAAAA==.',
Av='Avadda:BAABLgAECn8gAAIOAAcJwhE+JwAcAQAOAAcJwhE+JwAcAQABLgAECgkJTwAPAAwVAA==.',
Az='Azmar:BAABLgAECn9AAAIQAAgJFSO3GgC6AgAQAAgJFSO3GgC6AgABLgAFFAMJBwARACQWAA==.',
Ba='Badffinger:BAAALgADCgYJCQAAAA==.Badtouchbull:BAAALgADCgcJBwAAAA==.Balain:BAAALgAECgUJCgABLgAECgcJHQAOANsOAA==.Bastan:BAAALgADCgEJAQAAAA==.Bayorn:BAAALgAECgYJCAAAAA==.',
Be='Bear:BAAALgADCgcJBwAAAA==.Beardchi:BAAALgAECgEJAQAAAA==.Bearmont:BAABLgAECn8nAAIGAAgJFRhKEQCwAQAGAAgJFRhKEQCwAQAAAA==.Bearzerk:BAABLgAECn8pAAISAAkJdhUWJQDNAQASAAkJdhUWJQDNAQAAAA==.Beastmonk:BAAALgADCgEJAQAAAA==.Benathar:BAABLgAECn8pAAIQAAkJkQ0dZAC2AQAQAAkJkQ0dZAC2AQAAAA==.Bethela:BAAALgAECgIJAwAAAA==.Beyoond:BAABLgAFFH8GAAIDAAMJuwXHNQBTAAADAAMJuwXHNQBTAAAAAA==.',
Bi='Bifrostt:BAABLgAFFH8IAAIQAAMJ5wdcRQC1AAAQAAMJ5wdcRQC1AAAAAA==.Bio:BAAALgAECgEJAQAAAA==.Bionico:BAABLgAECn8eAAITAAYJBRcVBQA3AQATAAYJBRcVBQA3AQAAAA==.Birgir:BAAALgAECgUJCwABLgAECgkJIgAUADcgAA==.',
Bl='Blackmagék:BAAALgADCgkJCQAAAA==.Bladestormer:BAAALgADCgYJBQABLgAFFAMJBQANAEEOAA==.Blaston:BAAALgAECgYJBgAAAA==.Blazer:BAABLgAFFH8HAAMKAAMJoAmCFwBnAAAMAAMJowibcACoAAAKAAIJoAiCFwBnAAAAAA==.Blightbeard:BAAALgAECgIJAgAAAA==.Bloodrager:BAAALgADCgIJAgAAAA==.Bloodthorn:BAABLgAECn8cAAIVAAgJJgY9MAAfAQAVAAgJJgY9MAAfAQAAAA==.Blortimor:BAAALgADCgcJBwAAAA==.',
Bo='Bombad:BAABLgAECn8UAAQSAAgJchIhLwCTAQASAAgJPhIhLwCTAQAHAAMJNgsuPwB0AAATAAEJdQw8fwAqAAAAAA==.Boogiepop:BAABLgAECn8ZAAMNAAcJZx+LTQDeAQANAAYJjiGLTQDeAQAWAAcJ0RBNPgB/AQAAAA==.Boomnescient:BAABLgAECn8kAAIXAAcJ7gcRjwAhAQAXAAcJ7gcRjwAhAQAAAA==.Bortt:BAAALgAECgUJBgAAAA==.Bozscaggs:BAABLgAECn9IAAMXAAkJkBN2NAALAgAXAAkJkBN2NAALAgAYAAUJAwOsRACuAAAAAA==.',
Br='Bramis:BAAALgADCgkJHAAAAA==.Brancher:BAAALgADCgEJAQABLgAFFAMJBQANAEEOAA==.Brantu:BAAALgADCgQJCAABLgAECgEJAgALAAAAAA==.Bratte:BAAALgADCgUJCwAAAA==.Brattishm:BAAALgADCgQJBAAAAA==.Braultus:BAABLgAECn82AAIJAAkJfx36CgBgAgAJAAkJfx36CgBgAgAAAA==.Breuddwydwr:BAAALgADCgEJAQAAAA==.Brewmeupbro:BAAALgAECgEJAQABLgAECgkJIwARAFMcAA==.Brewtality:BAAALgAFFAEJAgAAAA==.Breyastrasza:BAAALgAECgYJDwAAAA==.Brood:BAAALgAECgYJDwAAAA==.Bruceleroy:BAAALgAECgEJAQAAAA==.Bruinn:BAAALgAECgQJBAABLgAECgcJHQAOANsOAA==.',
Bu='Burstangel:BAAALgAECgYJCAAAAA==.',
By='Byrddh:BAAALgADCgQJBAAAAA==.',
['Bä']='Bäguette:BAAALgAECgEJBQAAAA==.',
Ca='Cadenza:BAAALgAECgkJEgAAAA==.Caelthar:BAAALgAECgUJCAAAAA==.Cakemaeker:BAAALgAECgEJBAABLgAECgIJAwALAAAAAA==.Caliopedk:BAACLgAFFH8HAAMJAAIJrRjMOwBHAAARAAIJrRjjOACqAAAJAAIJqALMOwBHAAAuAAQKfxsAAxEACAlIIWUhALsCABEACAlIIWUhALsCAAkABQlJDjQqAO0AAAAA.Caliseni:BAAALgADCgYJCwAAAA==.Capra:BAAALgAECgcJCwAAAA==.Carillanklip:BAAALgADCgUJBQAAAA==.Caydenza:BAAALgAECgMJAwAAAA==.',
Cd='Cdmickey:BAAALgADCgUJBQAAAA==.',
Ce='Celdiseth:BAAALgAECgEJAgAAAA==.Celestè:BAAALgAECggJEQAAAA==.Celéste:BAAALgAECgkJEAAAAA==.Cerdwin:BAAALgAECggJEQABLgAECgkJPwAZABkXAA==.Ceruledge:BAAALgAFFAMJAwABLgAFFAkJNAAaABEfAA==.',
Ch='Charferad:BAAALgAECggJDwAAAA==.Chatter:BAAALgADCgMJAwAAAA==.Cheaptrick:BAAALgADCgcJEwAAAA==.Chibeard:BAABLgAECn8nAAIPAAkJtSKeAwAVAwAPAAkJtSKeAwAVAwAAAA==.Chihîro:BAABLgAECn8WAAIbAAYJqBGwCwAOAQAbAAYJqBGwCwAOAQAAAA==.Chonglin:BAAALgADCgQJBAAAAA==.Chrysopteron:BAAALgAECgEJAQABLgAECgEJAQALAAAAAA==.',
Cl='Clearcast:BAAALgADCgkJCwAAAA==.Clevercrane:BAAALgAFFAIJAgABLgAFFAMJBQAFAFgYAA==.Clubsdh:BAAALgAECgMJBAAAAA==.',
Co='Collosus:BAAALgAFFAEJAQABLgAFFAQJCwASAA8RAA==.Coolbro:BAAALgAECgEJAQABLgAECgMJAwALAAAAAA==.Corialis:BAAALgAFFAEJAgAAAA==.Counsel:BAAALgAECgUJBQAAAA==.',
Cr='Criantha:BAAALgADCgIJAgAAAA==.Crom:BAACLgAFFH8HAAIcAAMJqAlYEQCzAAAcAAMJqAlYEQCzAAAuAAQKf0QAAhwACQl7FpABABcCABwACQl7FpABABcCAAAA.Crosis:BAAALgAECgEJAQAAAA==.Cruelladvoid:BAAALgAECgQJBAAAAA==.Cruush:BAAALgAECgYJBQAAAA==.',
Cu='Culerro:BAAALgAECgYJAwABLgAECgYJBQALAAAAAA==.Cursive:BAAALgADCgUJDQAAAA==.',
Cy='Cygnes:BAABLgAECn8jAAIRAAkJUxwrJgBrAgARAAkJUxwrJgBrAgAAAA==.',
Da='Daddywarrior:BAAALgADCgUJBgAAAA==.Daeva:BAAALgADCgEJAQAAAA==.Dandarred:BAAALgAECgEJAQAAAA==.Dantey:BAAALgADCgcJFAABLgAFFAMJBQANAEEOAA==.Dashwydd:BAAALgAECgQJBAABLgAFFAIJBwAdALUQAA==.Daus:BAAALgAFFAEJAQAAAA==.Dawne:BAAALgAECgEJAQAAAA==.Dazanna:BAABLgAECn88AAMWAAkJyhzrCgDeAgAWAAkJyhzrCgDeAgAGAAUJTAvoNQCJAAAAAA==.Dazre:BAAALgAECgUJBgAAAA==.',
De='Deeminor:BAAALgADCgkJEwAAAA==.Delanina:BAAALgAECgMJAwABLgAFFAMJBQANAOIJAA==.Demeisen:BAABLgAECn8hAAMKAAkJERoQAwASAgAKAAkJERoQAwASAgAeAAEJuQ3NDgAqAAAAAA==.Demonizerr:BAAALgADCgUJCAABLgAFFAMJBQANAEEOAA==.Desktop:BAABLgAECn87AAMdAAkJUBxyCADuAgAdAAkJUBxyCADuAgAaAAYJdREuOgAqAQAAAA==.',
Di='Digon:BAAALgAECgEJAQAAAA==.Diksensei:BAAALgADCgUJBQAAAA==.Diod:BAABLgAECn9BAAIHAAkJHRVNEgDGAQAHAAkJHRVNEgDGAQAAAA==.Divineßovine:BAAALgADCgcJBwAAAA==.',
Do='Dolexin:BAAALgADCgkJCQAAAA==.Doombarker:BAAALgAECgEJAQAAAA==.Doomtheory:BAAALgAECgQJBwAAAA==.Dorammu:BAAALgAECgEJAQAAAA==.',
Dr='Dracovoid:BAAALgADCgYJBwAAAA==.Dracvoker:BAAALgAECgQJCAABLgAECgkJKgAMAHIfAA==.Draegyns:BAAALgAECgIJAgABLgAFFAYJFQAfAA4UAA==.Draehton:BAAALgAECgYJBwABLgAFFAQJEAAYAGEeAA==.Dragyns:BAACLgAFFH8VAAMfAAYJDhQHBQAyAQAVAAUJXRCrGwA9AQAfAAQJbRYHBQAyAQAuAAQKfzEABB8ACQngG4ECAMoCAB8ACQmxGYECAMoCABUABgmMGz8sAJwBACAAAwmrFFIJANwAAAAA.Dragynseye:BAAALgADCgIJAgABLgAFFAYJFQAfAA4UAA==.Drayper:BAABLgAECn9SAAQCAAkJiCKWAABdAwACAAkJiCKWAABdAwAdAAEJZw3AWQAvAAAaAAIJ4Al0KgAsAAAAAA==.Drayperbark:BAAALgAECgUJDAAAAA==.Druugal:BAACLgAFFH8PAAIVAAUJGhrgGABLAQAVAAUJGhrgGABLAQAuAAQKfy8AAxUACQlwH0YMANQCABUACQlwH0YMANQCAB8AAQl6C+ofADMAAAAA.',
Du='Dubs:BAABLgAECn82AAQhAAkJShy2QADaAQAhAAcJYBy2QADaAQAiAAIJ7hmMIwCVAAAUAAIJ/R5nDgBZAAAAAA==.Dunbarke:BAABLgAECn8iAAMUAAkJNyATAQAsAgAUAAgJoSATAQAsAgAhAAIJiRspGgCnAAAAAA==.Dustrat:BAAALgADCgIJAgAAAA==.',
['Dê']='Dêadlights:BAAALgAECgEJAQAAAA==.',
Ef='Efishient:BAABLgAECn8eAAIZAAYJWCTdHgBIAgAZAAYJWCTdHgBIAgABLgAFFAYJGQAZAH8TAA==.',
El='Elendrisa:BAAALgAFFAEJAgAAAA==.Elisoria:BAAALgAECgMJAwAAAA==.Ellayssa:BAAALgAECgQJBAAAAA==.Elliwynd:BAABLgAECn8vAAIZAAkJGRQnIgA3AgAZAAkJGRQnIgA3AgAAAA==.',
Eo='Eoshot:BAAALgAECgUJCAAAAA==.',
Er='Erinnys:BAABLgAECn9TAAMKAAkJqxjhAgAiAgAKAAkJqxjhAgAiAgAMAAYJsgWPlgDvAAAAAA==.Ermoril:BAAALgAECgUJBgAAAA==.Ernesta:BAAALgAECggJCQAAAA==.Eroksix:BAAALgADCgEJAQAAAA==.',
Es='Esoteria:BAAALgADCgEJAQAAAA==.',
Eu='Eufemia:BAAALgAECgYJCQAAAA==.',
Ev='Evonnya:BAAALgAECggJCAAAAA==.',
['Eø']='Eøs:BAAALgAECgEJAQAAAA==.',
Fa='Famine:BAAALgAECgcJDAAAAA==.',
Fe='Feelmebro:BAAALgADCggJCAABLgAECgMJAwALAAAAAA==.Felern:BAAALgAECgcJCwABLgAFFAMJBwARACQWAA==.Feyrun:BAAALgADCgkJEwABLgAECgcJDQALAAAAAA==.Feyrè:BAAALgAECgEJAgAAAA==.',
Fi='Fightswiftjr:BAAALgAECgkJCwAAAA==.Filiapatibul:BAAALgAECgEJAQAAAA==.Finalomega:BAABLgAECn8cAAIJAAgJNxndGACbAQAJAAgJNxndGACbAQAAAA==.Finnshot:BAAALgAFFAIJAgAAAA==.Finrod:BAAALgAECggJCgAAAA==.',
Fl='Flaminfalcon:BAABLgAFFH8GAAIaAAIJQBg7KwClAAAaAAIJQBg7KwClAAABLgAFFAMJBQAFAFgYAA==.Flody:BAAALgAFFAEJAQAAAA==.',
Fo='Forbiddin:BAAALgAECgEJAQAAAA==.Foxflame:BAABLgAECn8/AAMZAAkJGReqHwBJAgAZAAkJGReqHwBJAgAjAAgJPhD6KACKAQAAAA==.',
Fr='Franzen:BAABLgAECn8UAAMdAAYJPxUfRQDzAAAdAAQJRRQfRQDzAAAaAAYJbQ+lDgDVAAAAAA==.Freakbob:BAAALgADCgYJCQAAAA==.Froglocky:BAABLgAECn9AAAMUAAkJ+RY/BgAcAgAUAAkJ+RY/BgAcAgAhAAMJcwRi9ABwAAAAAA==.Fronsac:BAAALgADCgQJBAAAAA==.',
Fu='Fulanita:BAABLgAECn8fAAMjAAcJBxAVNgA+AQAjAAcJBxAVNgA+AQAZAAIJSwr6wABFAAAAAA==.',
Ga='Gallager:BAAALgADCgMJAwAAAA==.Garzok:BAABLgAECn8qAAMUAAkJXwy2CwChAQAUAAkJXwy2CwChAQAhAAMJzQHnCAFLAAAAAA==.',
Ge='Genkithered:BAABLgAECn82AAIkAAkJoxz5DQDlAgAkAAkJoxz5DQDlAgAAAA==.',
Gi='Gilaras:BAAALgAECgYJDAAAAA==.Gilernil:BAABLgAECn8UAAIXAAYJeQebrwDlAAAXAAYJeQebrwDlAAAAAA==.',
Gl='Gladtohelp:BAAALgAECgIJAgAAAA==.Gloomy:BAAALgADCgEJAQAAAA==.',
Gn='Gnoquarter:BAAALgADCgIJAgABLgAFFAQJBQAXAOAHAA==.',
Go='Gourak:BAAALgAECgYJEQAAAA==.',
Gr='Gravemarks:BAABLgAECn8YAAMgAAgJqBNCCQCXAQAgAAgJqBNCCQCXAQAfAAQJzAncEQDoAAAAAA==.Grimhorn:BAABLgAECn8qAAMjAAkJbQouFQCLAAAjAAgJ2AouFQCLAAAOAAIJJwQmfAAnAAAAAA==.Grimlie:BAAALgAECgEJAQABLgAECgEJAgALAAAAAA==.Grimmrock:BAAALgAECgcJDgAAAA==.Grumblen:BAAALgADCgMJAwAAAA==.',
Gu='Guaritrice:BAABLgAECn8aAAMaAAcJdguGPQAbAQAaAAcJdguGPQAbAQACAAEJYQd3egAfAAAAAA==.Gubb:BAAALgAECgMJAwAAAA==.',
Gw='Gwenylane:BAABLgAECn8sAAINAAkJSAuSdACFAQANAAkJSAuSdACFAQAAAA==.Gwindor:BAAALgAECgYJCQAAAA==.Gwyndelyn:BAABLgAECn8xAAIBAAgJ9wtONAAyAQABAAgJ9wtONAAyAQAAAA==.',
['Gö']='Gödwyn:BAAALgAECgYJEgABLgAECggJNgARAPggAA==.',
Ha='Hale:BAAALgAECgEJAgAAAA==.Halfsack:BAAALgAECgMJAwAAAA==.Hatterus:BAABLgAECn9NAAINAAkJ0RCrZACmAQANAAkJ0RCrZACmAQAAAA==.',
He='Herculeze:BAABLgAFFH8PAAIWAAQJMxq7DAA7AQAWAAQJMxq7DAA7AQAAAA==.Hessian:BAAALgADCgEJAQAAAA==.Hetairoi:BAAALgAECgIJAgABLgAFFAMJDQABADUfAA==.Hetd:BAAALgAECgEJAwABLgAFFAMJDQABADUfAA==.',
Hi='Hillbroken:BAABLgAECn9QAAIlAAkJqSJaAgDrAgAlAAkJqSJaAgDrAgAAAA==.Himduncan:BAAALgAECgMJBAAAAA==.Hippie:BAAALgADCgMJAwAAAA==.',
Ho='Hohalt:BAAALgAECgEJAgAAAA==.Holycross:BAAALgAECgUJBgAAAA==.Holysmokers:BAAALgAECgYJDAABLgAFFAYJFQAfAA4UAA==.Holysnow:BAAALgADCgkJDAABLgAECgkJOAAWAG4aAA==.Holysoul:BAAALgAECgEJAwAAAA==.',
Hu='Huntercreepy:BAAALgADCgYJBgAAAA==.Huntertidus:BAAALgAECggJEgABLgAFFAMJBQANAOIJAA==.Huntrix:BAAALgAECgkJCwAAAA==.',
Hy='Hydan:BAAALgAECgUJBQAAAA==.Hyrlis:BAAALgAECgUJBQAAAA==.',
['Hà']='Hànks:BAABLgAECn8gAAINAAkJ7g2uZgCiAQANAAkJ7g2uZgCiAQAAAA==.',
Ia='Iantosarian:BAAALgAECgQJBAAAAA==.',
Ib='Ibíng:BAAALgAECgYJBwAAAA==.',
Ic='Iceatron:BAAALgADCgUJBQABLgAFFAMJBQANAEEOAA==.',
Im='Imo:BAABLgAECn8vAAMhAAkJ/xGCEAD/AAAhAAkJ+xCCEAD/AAAiAAUJIhJxJgCBAAAAAA==.',
In='Intrepidz:BAAALgAECgEJAgABLgAFFAMJBQAFAFgYAA==.Inèvitable:BAABLgAECn9CAAIRAAkJHh13IwB4AgARAAkJHh13IwB4AgAAAA==.',
Ir='Ironphant:BAAALgAECgYJBgAAAA==.',
Is='Istara:BAAALgAECgQJBAAAAA==.',
Iv='Ivorin:BAAALgAECgYJCgAAAA==.',
Ix='Ixissa:BAAALgAECgEJAQAAAA==.',
Ja='Jabujabu:BAAALgAECgcJDAABLgAFFAQJEwAMAFwPAA==.Javeech:BAACLgAFFH8HAAIXAAMJkxCxXwDlAAAXAAMJkxCxXwDlAAAuAAQKfygAAxcACQl5GtcnAEACABcACAnQHNcnAEACABgAAQkVCjtiADcAAAAA.',
Je='Jebib:BAAALgAECgYJBgABLgAFFAkJSgAZAKQmAA==.Jennza:BAAALgAECgkJCQAAAA==.Jeod:BAAALgAECgYJCQAAAA==.',
Ji='Jirachi:BAAALgADCgEJAQAAAA==.',
Jo='Jolty:BAACLgAFFH8aAAIRAAYJUSBOJQDXAQARAAYJUSBOJQDXAQAuAAQKfykAAxEACQlWIq8MADUDABEACQlWIq8MADUDAAkABAmkFmMyANMAAAAA.Joydivision:BAAALgADCgIJAgAAAA==.',
Ju='Julian:BAAALgAECggJCAABLgAECgkJPwAVACwkAA==.',
['Jð']='Jð:BAAALgAECgQJBAABLgAECgYJJQAMAGAhAA==.',
Ka='Kaathe:BAAALgAECgYJBgAAAA==.Kaboomchickn:BAAALgAECgIJAgABLgAECggJDwALAAAAAA==.Kaiou:BAAALgADCgQJCAAAAA==.Kalmia:BAAALgAECgQJCAAAAA==.Kantor:BAABLgAECn9TAAMCAAkJLhiNFgAcAgACAAkJLhiNFgAcAgAaAAIJvQs7hgAzAAAAAA==.Karboomkin:BAABLgAFFH8GAAMOAAUJQhRcEgDxAAAOAAQJQhRcEgDxAAAjAAEJAACNWgAAAAABLgAFFAkJHAANANAgAA==.Karlin:BAAALgAECgEJAgABLgAECgEJAgALAAAAAA==.Karnstein:BAABLgAECn8oAAQmAAgJ4BEXDABQAQAmAAYJuxAXDABQAQAFAAYJBxEuSwD/AAAEAAUJgwTuMwDOAAAAAA==.Kasenko:BAAALgAECgUJBQABLgAECggJKgAOAEccAA==.Kasryna:BAABLgAECn8qAAIOAAgJRxzRAgDgAQAOAAgJRxzRAgDgAQAAAA==.Kathinja:BAABLgAECn8uAAIXAAkJ2QlNWwCTAQAXAAkJ2QlNWwCTAQAAAA==.Katiebeary:BAAALgAECgcJCwAAAA==.',
Ke='Kelthera:BAAALgAECgYJBgAAAA==.Kelumbria:BAAALgAECgkJDwAAAA==.Keta:BAAALgADCgYJBgAAAA==.Ketameanie:BAABLgAECn87AAIMAAkJFhhpJQA4AgAMAAkJFhhpJQA4AgAAAA==.',
Ki='Kieran:BAAALgAECgQJCgAAAA==.Kiley:BAAALgAECgkJCAAAAA==.Killerkitten:BAAALgADCgEJAQAAAA==.Kiniokin:BAAALgAECgYJBgABLgAECgkJbQAkAJkbAA==.Kitsunè:BAAALgAECgEJAQAAAA==.',
Km='Kmazing:BAABLgAECn8yAAMBAAkJjg6pJgCBAQABAAkJjg6pJgCBAQADAAYJYhiLDABbAQAAAA==.',
Kn='Knifèparty:BAABLgAECn85AAIfAAkJkSIEAgDOAgAfAAkJkSIEAgDOAgAAAA==.Knikku:BAABLgAFFH8KAAIKAAYJ0hqVBACoAQAKAAYJ0hqVBACoAQAAAA==.',
Ko='Konoha:BAABLgAECn8uAAMdAAkJSCE4BgAfAwAdAAkJOiA4BgAfAwACAAMJfiPoQwApAQAAAA==.',
Kr='Krodus:BAAALgAECggJCAABLgAECgkJJgAcAFkaAA==.',
Ku='Kultag:BAABLgAECn8gAAINAAkJBRYnOwAXAgANAAkJBRYnOwAXAgAAAA==.',
Ky='Kyaw:BAABLgAECn8WAAQVAAYJbRyAKAC2AQAVAAYJbRyAKAC2AQAfAAIJxRJbFgCTAAAgAAEJPRTmIwA4AAAAAA==.Kynzo:BAABLgAECn9FAAIIAAkJXB59BAC4AgAIAAkJXB59BAC4AgAAAA==.',
La='Laykeezenith:BAACLgAFFH8WAAQnAAYJJh0rBwCrAQAnAAYJmxorBwCrAQAXAAMJ7SKOIABfAAAYAAEJvQefMwBDAAAuAAQKfyIABCcACQmZIl4VAIcCACcACAnqIl4VAIcCABcACAm9IZY5APgBABgAAgl3EgooAHUAAAAA.Lazuli:BAACLgAFFH8IAAIbAAUJnQ9eKwDoAAAbAAUJnQ9eKwDoAAAuAAQKf14AAxsACQk0G7EDAAkCABsACQk0G7EDAAkCABwAAQk8BXdFACUAAAAA.',
Le='Lehann:BAABLgAECn8rAAIXAAkJxw+tSwC/AQAXAAkJxw+tSwC/AQAAAA==.Lehhan:BAAALgADCgEJAgAAAA==.',
Li='Lichtech:BAABLgAFFH8GAAIRAAQJfxudIABiAQARAAQJfxudIABiAQABLgAFFAkJIgAFAAIcAA==.Lightsbane:BAABLgAECn8XAAIOAAcJehAcJAAwAQAOAAcJehAcJAAwAQAAAA==.Lilìana:BAAALgADCgEJAQAAAA==.',
Lo='Lockatron:BAAALgADCgcJDgABLgAFFAMJBQANAEEOAA==.',
Lu='Luciselda:BAAALgADCgUJBgAAAA==.Lumosnox:BAAALgAECgMJAwAAAA==.Lunariah:BAAALgADCgkJEwAAAA==.Luvtarhugar:BAAALgAECgcJBwAAAA==.',
['Lé']='Léann:BAAALgADCgUJBQAAAA==.',
Ma='Madaran:BAAALgAECggJEQABLgAECgkJJgAcAFkaAA==.Magdalene:BAEALgAECgUJCQABLgAFFAcJIAAUABEZAA==.Marebear:BAAALgADCgQJBAAAAA==.Marenus:BAABLgAECn9PAAIXAAkJQRHRRwDKAQAXAAkJQRHRRwDKAQAAAA==.Marten:BAAALgADCgUJBQAAAA==.Masume:BAABLgAECn8gAAMaAAgJJQzjCQAnAQAaAAgJJQzjCQAnAQACAAQJxwP3FwBSAAAAAA==.Mazama:BAABLgAFFH8MAAIbAAcJqA+9DAB0AQAbAAcJqA+9DAB0AQABLgAFFAkJOQANAG8eAA==.Maély:BAAALgAECgEJBAAAAA==.',
Me='Mechadead:BAAALgADCgkJCQABLgAFFAMJBQANAEEOAA==.Medal:BAAALgAECgEJAQAAAA==.Megaopto:BAAALgAECgEJAQAAAA==.Melody:BAAALgAECgYJBgAAAA==.Meowmix:BAAALgADCgcJDAAAAA==.',
Mi='Miantha:BAAALgAECgYJBwAAAA==.Michi:BAABLgAECn82AAMZAAkJgyJwBAB3AwAZAAkJgyJwBAB3AwAIAAYJLBYNGQBHAQAAAA==.Midnights:BAAALgAECggJEAAAAA==.Mightymopo:BAAALgADCgMJAwAAAA==.Mikuki:BAABLgAECn8jAAIXAAkJvCP4EgC6AgAXAAkJvCP4EgC6AgAAAA==.Milkinghands:BAABLgAECn8hAAMDAAkJ1g+KOwCCAQADAAkJ1g+KOwCCAQABAAEJlAI/tgAiAAAAAA==.Minabos:BAAALgAECgQJDwAAAA==.Mizmonk:BAACLgAFFH8jAAIPAAgJLhmqBADlAQAPAAgJLhmqBADlAQAuAAQKfyIAAg8ACQnxHqMJAO4CAA8ACQnxHqMJAO4CAAAA.',
Mj='Mjölnir:BAAALgAECgkJDgAAAA==.',
Mo='Montfort:BAAALgADCggJDwAAAA==.Mootality:BAABLgAFFH8HAAIRAAMJJBbnRADSAAARAAMJJBbnRADSAAAAAA==.Moovover:BAAALgAECggJCgAAAA==.Morningcrow:BAAALgAECgYJCgAAAA==.',
Ms='Msmaho:BAAALgAECgkJEgAAAA==.',
Mu='Muhdeeps:BAAALgADCgQJBAAAAA==.Murionor:BAAALgADCgEJAQAAAA==.Mushuu:BAAALgAECggJCgAAAA==.',
My='Mykian:BAABLgAECn8pAAMmAAkJAQf1EAD7AAAFAAkJ0QTZQwAaAQAmAAcJ1Qf1EAD7AAAAAA==.Myrwynn:BAAALgAECgMJAwABLgAFFAMJDAAaAH4PAA==.Mythlee:BAAALgAECgUJCAAAAA==.Mythundon:BAAALgADCgUJBQAAAA==.',
Na='Nahion:BAAALgAECgYJCQAAAA==.Nashira:BAABLgAECn8oAAIXAAkJvhi5CQDhAQAXAAkJvhi5CQDhAQAAAA==.Nathalas:BAAALgAECgEJAgABLgAECgkJPwAVACwkAA==.Nature:BAAALgAECgUJCwAAAA==.',
Ne='Necrana:BAAALgADCgEJAQAAAA==.Necrobyarg:BAAALgAECgYJDQAAAA==.Nemasus:BAABLgAECn9DAAMZAAkJ5B3HCwADAwAZAAkJ5B3HCwADAwAjAAEJRQzVjgAxAAAAAA==.Nembie:BAAALgAECgcJCwAAAA==.Nethertech:BAABLgAFFH8LAAIMAAUJ0hEqSQANAQAMAAUJ0hEqSQANAQABLgAFFAkJIgAFAAIcAA==.',
Ni='Ninjahh:BAACLgAFFH8VAAIVAAUJMxGTFgDLAAAVAAUJMxGTFgDLAAAuAAQKfygAAhUACAkrFzAZANEBABUACAkrFzAZANEBAAAA.Niobei:BAAALgADCgcJBwABLgAECgkJbQAkAJkbAA==.Nioshei:BAABLgAECn9tAAMkAAkJmRvlAgChAgAkAAkJmRvlAgChAgAbAAEJCQfHuQAjAAAAAA==.Nisara:BAACLgAFFH8RAAMDAAQJvRMqMQDvAAADAAQJvRMqMQDvAAABAAMJDxLzDgDFAAAuAAQKf1cAAwEACQmVIr4AABIDAAEACQmVIr4AABIDAAMACQmRH4QKAPECAAAA.Nitrex:BAAALgAECgEJAgAAAA==.',
No='Nochmuerta:BAABLgAECn8ZAAIRAAkJRRmAKgBWAgARAAkJRRmAKgBWAgABLgAFFAQJBQAXAOAHAA==.Nogrid:BAABLgAECn9RAAIGAAkJHBsDBwBxAgAGAAkJHBsDBwBxAgAAAA==.Nossaria:BAAALgAECgIJAgAAAA==.Notmyface:BAAALgAECgcJEwABLgAFFAQJCgASAL4eAA==.',
Nu='Nuorong:BAAALgAECgUJBQABLgAECgkJPwAZABkXAA==.Nuthar:BAABLgAECn9HAAINAAkJniUwAwBnAwANAAkJniUwAwBnAwAAAA==.',
Ny='Nyxandra:BAAALgAECgcJCwAAAA==.',
['Né']='Nésta:BAAALgAECgcJDQAAAA==.',
['Nò']='Nòhva:BAAALgAECgQJBAAAAA==.',
Ol='Oldeis:BAAALgAECgEJAQAAAA==.',
Om='Ominousowl:BAABLgAFFH8FAAIFAAMJWBhVOADkAAAFAAMJWBhVOADkAAAAAA==.',
On='Onil:BAAALgAECgQJBAAAAA==.',
Or='Oregizm:BAAALgAFFAEJAQAAAA==.Orneryosprey:BAAALgAFFAIJAgABLgAFFAMJDQABADUfAA==.',
Ou='Ourobius:BAAALgAECgUJDQAAAA==.',
Pa='Pamburu:BAABLgAECn8jAAQXAAgJ8w2yegBKAQAXAAgJpg2yegBKAQAnAAYJvgUKIQCpAAAYAAIJrQUPKgBgAAAAAA==.Papagrape:BAABLgAECn9lAAQEAAkJ/CHxAQBlAwAEAAkJ/CHxAQBlAwAmAAkJfB5tAAC2AgAFAAMJaRaWWgDKAAAAAA==.Parzivàl:BAABLgAECn8mAAIWAAgJehiaEwB1AgAWAAgJehiaEwB1AgAAAA==.Paxa:BAABLgAECn8xAAMCAAgJbxsGFgAiAgACAAgJbxsGFgAiAgAaAAYJTgvrRwDwAAAAAA==.',
Pe='Peacebox:BAAALgADCggJDAABLgAECgkJMgABAI4OAA==.Peekabu:BAAALgADCgEJAQABLgAFFAMJBQANAEEOAA==.Persayis:BAAALgAECgkJEgAAAA==.',
Ph='Phoebel:BAAALgAECgEJAgABLgAECgIJAwALAAAAAA==.Phoenixbodhi:BAAALgAECgQJBAAAAA==.',
Pi='Pickledeggs:BAAALgAECgcJCAABLgAECgkJJQAQAFwaAA==.Pixxy:BAAALgADCgYJBgABLgAECgMJDwALAAAAAA==.',
Po='Podnov:BAACLgAFFH8eAAMnAAYJhiCKCwCpAQAnAAYJhiCKCwCpAQAXAAIJpB09iACNAAAuAAQKfyMAAicACQlEHcwNANYCACcACQlEHcwNANYCAAAA.Pollyanna:BAAALgADCgEJAQAAAA==.',
Pr='Preyon:BAABLgAECn8dAAIOAAcJ2w4eDgCiAAAOAAcJ2w4eDgCiAAAAAA==.',
Py='Pyne:BAAALgADCgEJAQAAAA==.Pyrista:BAAALgAECgkJDAAAAA==.',
Qa='Qang:BAAALgAECgkJDwAAAA==.',
Qo='Qotho:BAABLgAECn9IAAIXAAkJYhtjKAA9AgAXAAkJYhtjKAA9AgAAAA==.',
Ra='Raikou:BAAALgAECgUJBQABLgAFFAkJNAAaABEfAA==.Raistliin:BAAALgAECgYJDgAAAA==.Raithis:BAACLgAFFH8gAAIXAAgJQhwmDQDcAQAXAAgJQhwmDQDcAQAuAAQKfzIAAhcACQlAIsAEAEEDABcACQlAIsAEAEEDAAAA.Raito:BAAALgADCgUJBQAAAA==.Ramhadin:BAEALgAECgMJDwABLgAECgkJOgAaALMfAA==.Ramzert:BAEALgAECgUJBQABLgAECgkJOgAaALMfAA==.Ratim:BAAALgAFFAIJAgABLgAFFAMJBwARACQWAA==.Rav:BAAALgADCgMJBgAAAA==.',
Re='Rednaxel:BAABLgAECn9oAAMVAAkJxiVQAABlAwAVAAkJhCVQAABlAwAfAAUJax9yCADEAQAAAA==.Redvelvet:BAABLgAECn8vAAMDAAkJgRY8HQAuAgADAAkJgRY8HQAuAgABAAQJ9Ab5WwCgAAAAAA==.Rekoner:BAABLgAECn8mAAIRAAkJRxPwSQDkAQARAAkJRxPwSQDkAQAAAA==.Resi:BAAALgAECgIJAgAAAA==.Resii:BAAALgAECgEJAgABLgAECgIJAgALAAAAAA==.Reyalanta:BAAALgAECgYJDwABLgAECgkJOQAfAJEiAA==.',
Ri='Ringmistress:BAAALgADCgcJBwAAAA==.Rixaa:BAAALgADCgQJBwABLgAECgkJIwAXAGgcAA==.',
Ro='Rocks:BAAALgAECgYJCAAAAA==.Romam:BAAALgAECgYJCQAAAA==.',
Ru='Rubyknight:BAAALgAECgEJAQAAAA==.',
Ry='Rydran:BAAALgAECgUJCQAAAA==.Rykria:BAAALgAECgUJEQAAAA==.',
Sa='Saggi:BAAALgAECgIJAgAAAA==.Samsonknight:BAAALgADCgYJBgAAAA==.Sanasat:BAAALgADCgMJAwAAAA==.Sanguinarian:BAABLgAECn8XAAINAAgJIQ32sAAeAQANAAgJIQ32sAAeAQAAAA==.Savash:BAAALgAECggJEgAAAA==.',
Sc='Scrubtotem:BAAALgAECgMJAwAAAA==.',
Se='Secksiecutie:BAABLgAECn82AAMlAAkJ7hpKBQBmAgAlAAkJ7hpKBQBmAgAJAAcJvQw8LQDzAAAAAA==.Selanda:BAAALgAECgQJBAAAAA==.Selma:BAAALgAECgEJAgAAAA==.Selval:BAAALgAECgQJCwAAAA==.Serinar:BAABLgAFFH8IAAINAAMJoAODhACrAAANAAMJoAODhACrAAAAAA==.Serraphem:BAAALgAECgEJAQAAAA==.',
Sh='Shadoe:BAAALgADCgMJAwABLgAFFAMJBQANAEEOAA==.Shafrog:BAAALgAECgIJAgABLgAECgkJQAAUAPkWAA==.Shoshin:BAABLgAECn8aAAMPAAcJ3w0ITADOAAAPAAcJ3w0ITADOAAABAAQJJgxhXQCbAAABLgAECgcJHQAOANsOAA==.Shïvana:BAAALgAECgMJDwAAAA==.',
Si='Siako:BAAALgADCgEJAQAAAA==.Silversaiyan:BAABLgAECn9NAAMSAAkJwCFoDgCLAgASAAkJwCFoDgCLAgATAAEJXRiEOgBGAAAAAA==.',
Sk='Skaddi:BAAALgAECgEJAwAAAA==.Skullpanda:BAAALgAECggJCAAAAA==.',
Sl='Slade:BAABLgAECn8/AAMVAAkJLCRvAwATAwAVAAkJLCRvAwATAwAfAAMJ+xuUEwDvAAAAAA==.Slap:BAAALgAECgEJAQAAAA==.Slaps:BAAALgADCgkJCQAAAA==.Sliyce:BAAALgAECgIJBwAAAA==.',
Sm='Smóke:BAABLgAECn9RAAIMAAkJKxWnNgDsAQAMAAkJKxWnNgDsAQAAAA==.',
Sn='Sneakyclubs:BAAALgAECgMJAwABLgAECgMJBAALAAAAAA==.Snore:BAAALgADCgQJBgAAAA==.Snowfawn:BAABLgAECn8rAAIXAAkJYheVKQA4AgAXAAkJYheVKQA4AgABLgAECgkJOAAWAG4aAA==.Snowieblaze:BAAALgAECgQJBAABLgAECgkJOAAWAG4aAA==.Snowiefox:BAAALgADCgkJCQABLgAECgkJOAAWAG4aAA==.',
So='Sofedan:BAABLgAECn9RAAInAAkJuA89DACgAQAnAAkJuA89DACgAQAAAA==.Solreaver:BAAALgAECgEJAQAAAA==.Sorgath:BAAALgAECgUJDQAAAA==.Soriel:BAABLgAECn9PAAIPAAkJDBXoAQACAgAPAAkJDBXoAQACAgAAAA==.Sorokwa:BAABLgAECn8XAAIRAAkJKgLb+wCxAAARAAkJKgLb+wCxAAAAAA==.',
Sq='Squeeze:BAAALgAECgMJBgAAAA==.Squids:BAAALgADCgQJBAAAAA==.',
St='Stallon:BAAALgAECgEJAgAAAA==.Stillwater:BAAALgADCgkJCQAAAA==.Strongstork:BAAALgAFFAIJBAABLgAFFAMJDQABADUfAA==.',
Su='Sunsword:BAAALgAECgYJEQAAAA==.Suriden:BAAALgAECgYJBwAAAA==.',
Sw='Swagidan:BAACLgAFFH8HAAIKAAMJAQpzFACEAAAKAAMJAQpzFACEAAAuAAQKfy8AAgoACAnjGAASAEwCAAoACAnjGAASAEwCAAAA.Sweatermonk:BAAALgADCgIJAgABLgAECgYJBgALAAAAAA==.Sweaterpally:BAAALgAECgYJBgAAAA==.Swiftera:BAABLgAECn8lAAIWAAkJIxaEKADqAQAWAAkJIxaEKADqAQAAAA==.Swiftlier:BAABLgAECn8vAAIPAAkJtxn8FQD8AQAPAAkJtxn8FQD8AQAAAA==.Swipegirl:BAAALgAECgYJCQAAAA==.',
Sy='Sybelyyia:BAAALgAECgUJBgAAAA==.Sylphrène:BAABLgAECn8yAAIKAAkJIwezKQAwAQAKAAkJIwezKQAwAQAAAA==.Sylriane:BAAALgAECgEJAgAAAA==.',
Ta='Taboo:BAAALgAECgEJAgAAAA==.Taladan:BAAALgAECgQJBQAAAA==.Taleth:BAAALgAECgMJBAAAAA==.Tallyian:BAAALgAECgEJAwAAAA==.Tandrana:BAAALgAECgUJCQAAAA==.Tankmepapi:BAAALgAECgMJAwAAAA==.Tanwen:BAABLgAECn8UAAQEAAYJ+QcWJgC8AAAEAAYJ+QcWJgC8AAAmAAQJHAMENwBfAAAFAAIJAALnmwAmAAAAAA==.Targdh:BAACLgAFFH8TAAIMAAQJXA+RKADdAAAMAAQJXA+RKADdAAAuAAQKf2AAAwwACQnoHyoRALkCAAwACQnoHyoRALkCAB4ABAmMGNESACUBAAAA.Targish:BAAALgAECggJCAABLgAFFAQJEwAMAFwPAA==.Targquellin:BAAALgAECgcJBwABLgAFFAQJEwAMAFwPAA==.Targypunch:BAAALgADCgcJBwABLgAFFAQJEwAMAFwPAA==.Tatsunoshinn:BAAALgADCgEJAQAAAA==.',
Te='Techniqe:BAACLgAFFH8iAAMFAAkJAhxLCAB1AgAFAAkJAhxLCAB1AgAEAAEJrwEkLQAxAAAuAAQKfzcAAwUACAkkIxsHAAoDAAUACAkkIxsHAAoDACYABgkgIe8SALMBAAAA.Techtides:BAAALgAECgIJAgABLgAFFAkJIgAFAAIcAA==.Temperance:BAAALgADCgEJAQAAAA==.Temptations:BAAALgAECgUJBgAAAA==.Terminus:BAAALgAECggJCwAAAA==.Terrylin:BAAALgAECgYJBwAAAA==.',
Th='Thaliá:BAAALgADCgkJFQAAAA==.Themachinist:BAAALgAECgYJBgAAAA==.Thomag:BAAALgADCgIJAgAAAA==.Thor:BAAALgAECgYJCgAAAA==.',
Ti='Ticebane:BAACLgAFFH8WAAMJAAYJSgr2JQDCAAAJAAUJ4wv2JQDCAAARAAMJRgMe/gBuAAAuAAQKfyMAAgkACQk0GbALAFgCAAkACQk0GbALAFgCAAAA.Tichus:BAAALgAECgMJAwAAAA==.Tidusdruo:BAABLgAECn8VAAIOAAcJxxvqAgDZAQAOAAcJxxvqAgDZAQABLgAFFAMJBQANAOIJAA==.Tiduspullo:BAACLgAFFH8FAAINAAMJ4gktjgCVAAANAAMJ4gktjgCVAAAuAAQKfzAAAw0ACQmaG5NEABYCAA0ACQl3FZNEABYCAAYACAnkGhsHAAgBAAAA.Tiduswar:BAABLgAECn8pAAMHAAcJJhzhAwCJAQAHAAcJJhzhAwCJAQASAAIJfRI6gwBtAAABLgAFFAMJBQANAOIJAA==.Tinafay:BAAALgAECgcJDAAAAA==.Tiramisuu:BAAALgAECggJEAAAAA==.Titanbeard:BAAALgAECgMJBQAAAA==.Titor:BAABLgAECn9MAAMEAAkJNBmzAQDnAQAEAAkJNBmzAQDnAQAmAAYJgA+hEAABAQAAAA==.Tituspullo:BAAALgAECgcJEAABLgAFFAMJBQANAOIJAA==.',
To='Tolduan:BAAALgAECgUJDQAAAA==.Totemik:BAABLgAECn8mAAIcAAkJWRqkAgCvAQAcAAkJWRqkAgCvAQAAAA==.Toughturkey:BAABLgAFFH8NAAMBAAMJNR9dHwDcAAABAAMJNR9dHwDcAAADAAIJnRggNABYAAAAAA==.Towen:BAAALgADCgUJBQAAAA==.Toy:BAAALgADCgYJGwABLgAECgMJDwALAAAAAA==.',
Tr='Tremorhoof:BAAALgADCgIJAwAAAA==.Tresera:BAAALgADCgEJAQAAAA==.Tricarnetry:BAACLgAFFH8FAAINAAMJQQ68MwDCAAANAAMJQQ68MwDCAAAuAAQKfzUAAw0ACQlLF5cLAK8BAA0ACQlLF5cLAK8BABYABgmxCSJQAPkAAAAA.Tricarnity:BAAALgAECgYJCgABLgAFFAMJBQANAEEOAA==.Troublee:BAAALgAECgMJAwAAAA==.Trufleshufle:BAAALgAECggJEQAAAA==.',
['Tà']='Tàlle:BAAALgAECgMJAwAAAA==.',
Uh='Uhtread:BAAALgADCgYJBQAAAA==.',
Ul='Ulfer:BAAALgAECgUJBQABLgAFFAQJDQAJAMAhAA==.',
Un='Unholyfury:BAAALgADCgYJBgAAAA==.',
Va='Vapor:BAAALgAECgQJBQAAAA==.Vaquinha:BAAALgADCgUJBQAAAA==.Varyel:BAAALgAECgIJAgAAAA==.',
Ve='Velianne:BAAALgADCgUJBQAAAA==.Vellinada:BAAALgADCgMJAwABLgAFFAkJNQACAMojAA==.Verakis:BAABLgAECn9dAAIHAAkJlB3IAQBQAgAHAAkJlB3IAQBQAgAAAA==.Verndarí:BAABLgAECn8ZAAMJAAkJ1Q2RHgBiAQAJAAkJ1Q2RHgBiAQAlAAMJzgU1LgBoAAABLgAECgkJLwAPALcZAA==.Verudora:BAAALgAECgYJBwAAAA==.Vervain:BAAALgAECgUJBQAAAA==.',
Vo='Vonnie:BAAALgADCgkJCQAAAA==.Vortheus:BAAALgAECgkJEwAAAA==.Votollis:BAAALgAECgQJBQAAAA==.',
Wa='Warlanen:BAAALgAECgUJBgAAAA==.Warning:BAAALgADCgUJBQAAAA==.Warpiggies:BAAALgADCgkJCAABLgAFFAQJEwAMAFwPAA==.',
Wi='Widdy:BAAALgAECgcJEAAAAA==.Willbur:BAABLgAECn9JAAIQAAkJVxr1LABlAgAQAAkJVxr1LABlAgAAAA==.Wittledwagon:BAAALgADCgkJCQAAAA==.',
Wu='Wurthwhile:BAAALgAECgYJDgAAAA==.',
Wy='Wylaniris:BAAALgADCgQJBAAAAA==.Wyndywalker:BAABLgAECn82AAIjAAkJqQlANABIAQAjAAkJqQlANABIAQAAAA==.',
Xa='Xaveil:BAAALgADCgEJAQAAAA==.',
Xe='Xenosian:BAAALgAECgkJCQAAAA==.',
Xi='Xinnou:BAAALgAECgEJAgAAAA==.Xinnuo:BAAALgAECgQJBwAAAA==.',
Xy='Xydias:BAAALgAECggJDwAAAA==.Xyra:BAAALgADCgcJBwAAAA==.',
['Xë']='Xërxës:BAAALgAECgEJAQAAAA==.',
Ye='Yemozun:BAAALgAECgMJAwAAAA==.',
Yo='Yoku:BAAALgAECggJEwAAAA==.Yondadk:BAAALgAECgEJAQAAAA==.',
Yu='Yuming:BAAALgAECgYJBgAAAA==.Yunxiao:BAAALgAECgEJAQAAAA==.',
Za='Zacian:BAAALgAECgEJAQABLgAFFAkJNAAaABEfAA==.Zag:BAAALgAECgEJAQABLgAECgkJNAAeAAsaAA==.Zalgarian:BAAALgAECggJEAAAAA==.Zamønk:BAABLgAECn8ZAAMPAAcJFg8WOABqAQAPAAcJFg8WOABqAQABAAIJ+wypmAA2AAAAAA==.Zaphoidvtwo:BAAALgAECgUJCwAAAA==.Zason:BAAALgADCgMJAwAAAA==.Zatari:BAAALgADCgMJAwAAAA==.Zavaen:BAAALgADCgEJAQAAAA==.',
Ze='Zelectie:BAACLgAFFH8GAAIOAAQJfwXaIQCVAAAOAAQJfwXaIQCVAAAuAAQKfxcAAg4ACAluFzIKAPcBAA4ACAluFzIKAPcBAAEuAAUUCAkTAAkAnw4A.Zelzaikin:BAAALgAECgQJBgAAAA==.Zevon:BAAALgAECgYJCgAAAA==.',
Zi='Ziarra:BAAALgADCgYJBgABLgADCgcJDQALAAAAAA==.Zimzy:BAAALgAECgkJCQAAAA==.Zinazarinara:BAAALgAECgIJAgAAAA==.Zirril:BAAALgADCgcJDwAAAA==.',
Zo='Zok:BAAALgAECgYJBgAAAA==.Zombiechick:BAAALgAECgcJDwAAAA==.Zorn:BAAALgAECgMJAwAAAA==.',
['Zä']='Zädä:BAAALgAECgEJAQAAAA==.',
['Äp']='Äpollymi:BAAALgADCgYJBgAAAA==.',
['Ån']='Ånimaul:BAAALgAFFAEJAQABLgAFFAkJIgAFAAIcAA==.',
['ßr']='ßrigitte:BAAALgADCgkJEQAAAA==.ßrownßag:BAAALgAECgEJAQAAAA==.',
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
