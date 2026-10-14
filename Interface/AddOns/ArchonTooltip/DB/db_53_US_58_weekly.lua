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

local lookup = {'Priest-Shadow','Druid-Guardian','Druid-Restoration','Warrior-Fury','DemonHunter-Devourer','Rogue-Assassination','Rogue-Subtlety','Paladin-Retribution','Priest-Holy','Paladin-Protection','Unknown-Unknown','Evoker-Preservation','Evoker-Augmentation','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Monk-Mistweaver',}
local provider = {region='US',realm='Dalvengyr',name='US',type='weekly',zone=53,date='2026-10-13',data={Ac='Activity:BAABNQAECn8oAAIBAAkKfh2pEwDHAgABAAkKfh2pEwDHAgAAAA==.',
Ad='Addiegate:BAEANQADCgQIBAABNQAFFAcIGQACAIYhAA==.',
Ae='Aerinis:BAACNQAFFH8YAAIDAAcKCQm+AwD8AQADAAcKCQm+AwD8AQA1AAQKfywAAgMACQp+HncQANACAAMACQp+HncQANACAAAA.',
Ar='Arcade:BAAANQADCgYIBgAAAA==.Arius:BAAANQADCgQIBQAAAA==.',
Au='Audrey:BAAANQAECgIIAgAAAA==.',
Bl='Blux:BAAANQAECgYIDQAAAA==.',
Br='Bradley:BAAANQAECgIIAgAAAA==.Brewzach:BAAANQAECgIIAgABNQAFFAYIDAAEAJIVAA==.',
Bu='Buttertooth:BAAANQADCgQIDQAAAA==.Buzzy:BAAANQADCgYIBgAAAA==.',
Ce='Ceniza:BAAANQADCgMIAwAAAA==.',
Ch='Chakkra:BAAANQADCgMIAwABNQAECgkJFgAFAHwcAA==.Chickyjockie:BAAANQAFFAIIBAAAAA==.',
Cr='Critjitters:BAACNQAFFH8EAAIGAAIK6SEPEgC9AAAGAAIK6SEPEgC9AAA1AAQKfy0AAwcACQqnJJYFACwDAAcACApII5YFACwDAAYABwovI40ZAKwCAAAA.',
Cy='Cynical:BAAANQAECgcIDgAAAA==.',
Da='Dawn:BAACNQAFFH8MAAIIAAYKkx3WBAARAgAIAAYKkx3WBAARAgA1AAQKf0cAAggACQqdJmEDAOEDAAgACQqdJmEDAOEDAAAA.',
De='Demerest:BAAANQADCgQIBAAAAA==.',
Do='Doriloca:BAAANQAECgcIDgAAAA==.',
Ed='Edrik:BAAANQAECgEJAQAAAA==.',
Ei='Eion:BAAANQADCgQIBAAAAA==.',
El='Eloraina:BAAANQADCgYICgAAAA==.',
Fi='Fireraider:BAAANQADCgYIBgAAAA==.',
Fl='Flaykey:BAAANQADCgcIHgAAAA==.',
Gl='Glaube:BAAANQADCgUICQAAAA==.Glinda:BAAANQAECgYIEgAAAA==.',
Gr='Greg:BAAANQADCgMJAwAAAA==.',
Ha='Halo:BAACNQAFFH8NAAMBAAUKzgslDAAeAQABAAQKzgslDAAeAQAJAAEKYgAsOgA0AAA1AAQKf1MAAgEACQqBIXMHAGIDAAEACQqBIXMHAGIDAAE1AAUUBggMAAgAkx0A.',
He='Healthstone:BAAANQADCgUIBQAAAA==.Hettikush:BAAANQADCgcIGQAAAA==.',
Hu='Humpherdoo:BAAANQAECggICAAAAA==.',
Is='Iskar:BAAANQADCgMIBAAAAA==.',
Ju='Jubei:BAAANQADCgQIBAAAAA==.',
Ka='Kaskade:BAABNQAECn85AAMIAAkK3iQAHgBKAwAIAAkKNyMAHgBKAwAKAAUKoyHVIADaAQAAAA==.',
Ki='Killertom:BAAANQABCggICAAAAA==.',
Le='Leatherface:BAAANQADCgcIBwAAAA==.',
Li='Linaria:BAAANQAECgUIEwAAAA==.Lisari:BAAANQAECgMIBgABNQAECgUICgALAAAAAA==.Lite:BAAANQADCgQIBAAAAA==.',
Lo='Lolan:BAAANQAECgUICgAAAA==.Lovetoshank:BAAANQADCgYIBgABNQAECgUICwALAAAAAA==.',
Lu='Ludacrits:BAAANQADCgcIBwABNQAECgQICAALAAAAAA==.Luna:BAABNQAECn8aAAMMAAkKGQ5lHAACAgAMAAkKGQ5lHAACAgANAAEKhAvyJAAvAAABNQAECgkJGwAJAPYbAA==.',
Ma='Manimekhala:BAAANQAECgUIBgAAAA==.',
Mi='Mintyoonji:BAAANQAECgUIBgAAAA==.',
Mo='Monkladin:BAAANQAECgIIAgAAAA==.Monkwilde:BAAANQADCgYIFAAAAA==.',
Ne='Nekron:BAAANQADCgEIAQAAAA==.Nerethil:BAAANQADCggICAAAAA==.',
Oa='Oath:BAAANQADCgcIGgABNQAFFAYIDAAIAJMdAA==.',
Od='Odysseus:BAAANQAECggICgAAAQ==.',
Pa='Padihari:BAAANQADCgcIBwAAAA==.Pakal:BAABNQAECn8XAAIGAAgKcB4UFwC/AgAGAAgKcB4UFwC/AgAAAA==.Patmcgroin:BAAANQAECgUIBgABNQAECgkJOQAIAN4kAA==.',
Pe='Peacandlove:BAAANQAECgUIBQAAAA==.',
Qu='Quikkshot:BAAANQAECgcIEgAAAA==.',
Ra='Ragemane:BAAANQADCgQIBAAAAA==.Ranbo:BAAANQADCgIIAgAAAA==.',
Sh='Shozo:BAAANQADCgIIAgAAAA==.',
So='Sophdh:BAAANQAECgEIAgAAAA==.',
Su='Supra:BAAANQADCgYIBgABNQAECgkJOQAIAN4kAA==.',
Ta='Taarna:BAAANQAECgMIAwAAAA==.Tacobelle:BAABNQAECn8ZAAQOAAgKByH5LQDLAgAOAAgKcx75LQDLAgAPAAIKBg3OXgBnAAAQAAEK2yHkIgBkAAAAAA==.Talrayia:BAAANQAECgYIBQABNQADCgcIGAALAAAAAA==.',
Tr='Trivkeran:BAAANQADCgYIBgAAAA==.',
Va='Valea:BAAANQADCgMIAwAAAA==.Valick:BAAANQAECgQIDwABNQAECgUICgALAAAAAA==.',
Vu='Vulteara:BAAANQADCgYIBgABNQAECgUICgALAAAAAA==.',
Vy='Vyndie:BAAANQADCgIJAgABNQAECgUICgALAAAAAA==.',
Wa='Waffulz:BAAANQAECgQICAAAAA==.Washikie:BAAANQAECgcIEwAAAA==.',
Ya='Yaksha:BAAANQAECgEIAQAAAA==.',
Ze='Zenadora:BAABNQAECn8VAAIRAAgKBRFtHAC5AQARAAgKBRFtHAC5AQAAAA==.',
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
