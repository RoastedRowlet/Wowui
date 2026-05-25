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

local lookup = {'Priest-Shadow','Druid-Guardian','Druid-Restoration','Druid-Feral','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','Shaman-Elemental','Paladin-Retribution','Mage-Arcane','Mage-Fire','Rogue-Subtlety','Priest-Holy','Priest-Discipline','DeathKnight-Unholy','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Devourer','Rogue-Assassination','Unknown-Unknown','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','DeathKnight-Frost','DeathKnight-Blood',}
local provider = {region='US',realm='Dalvengyr',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abracadabras:BAAALgAECgEJAQAAAA==.',
Ac='Activity:BAABLgAECn8dAAIBAAkJ1hbuHAC3AQABAAkJ1hbuHAC3AQAAAA==.',
Ad='Addiegate:BAEALgAECgYJCgABLgAFFAkJJgACAKUiAA==.',
Ae='Aegis:BAAALgAECgQJBwAAAA==.Aerinis:BAACLgAFFH8cAAIDAAcJ3hQnBwAvAgADAAcJ3hQnBwAvAgAuAAQKfyUAAwMACQkHIOUIAAEDAAMACQkHIOUIAAEDAAQAAQm1B0MyADgAAAAA.',
Am='Amazement:BAAALgADCgEJAQAAAA==.',
Ap='Applicated:BAAALgADCgcJDQAAAA==.',
As='Asdzchisi:BAAALgAECgIJAgAAAA==.',
Av='Avoid:BAAALgAECgYJCQAAAA==.',
Be='Beannsidhe:BAAALgAECgEJAQAAAA==.',
Br='Bryan:BAACLgAFFH8IAAQFAAQJOQexGQCgAAAFAAIJCQixGQCgAAAGAAQJXgVmHQBvAAAHAAEJ5gAXCAA/AAAuAAQKfxkAAwUACAkqIjQrAAgCAAUABgleHzQrAAgCAAYACAlLHMolAPsBAAAA.',
Bu='Burningman:BAAALgAECgYJBgAAAA==.Buttertooth:BAAALgADCgEJAgAAAA==.',
Ca='Catau:BAAALgAECgYJCwAAAA==.',
Ch='Chocokrispis:BAABLgAECn8dAAIFAAgJRB5HIQA2AgAFAAgJRB5HIQA2AgAAAA==.',
Cl='Classic:BAAALgAECgEJAQAAAA==.',
Cr='Critbender:BAACLgAFFH8IAAIIAAMJiBVAJADbAAAIAAMJiBVAJADbAAAuAAQKfx8AAggACQkSHjoMAHwCAAgACQkSHjoMAHwCAAAA.',
Da='Dawn:BAACLgAFFH8bAAIJAAcJrh14AwBIAgAJAAcJrh14AwBIAgAuAAQKfzwAAgkACQm2I78HAFgDAAkACQm2I78HAFgDAAAA.',
De='Deeplyrooted:BAAALgADCgUJBQAAAA==.',
Do='Doriloca:BAAALgAECgMJBAAAAA==.',
Du='Duô:BAAALgADCgQJBAAAAA==.',
El='Eloraina:BAAALgAECgYJAgAAAA==.',
Em='Emmaya:BAABLgAECn8ZAAIIAAcJwhGbPQAOAQAIAAcJwhGbPQAOAQAAAA==.Emmét:BAAALgAECgEJAwAAAA==.',
Fl='Flaykey:BAAALgAECgEJAQAAAA==.',
Gi='Girth:BAABLgAECn8WAAMKAAgJjyDbAgBYAgAKAAcJih/bAgBYAgALAAcJeR99AgAlAgABLgAFFAYJEAAMAP8UAA==.',
Ha='Halciyon:BAAALgAECgEJAQAAAA==.Halo:BAACLgAFFH8mAAIBAAUJ6h1GDABmAQABAAUJ6h1GDABmAQAuAAQKf1YABA0ACAk7H3kRADACAA0ABgmCIXkRADACAAEACAn0IDsSAB0CAA4AAgkaGCJMAI0AAAEuAAUUBwkbAAkArh0A.Hansomebeast:BAAALgAECgEJAQAAAA==.',
He='Hellermlady:BAAALgAECgUJDQAAAA==.Hettikush:BAAALgAECgEJAwAAAA==.',
Ho='Hoksila:BAAALgAECgEJAQAAAA==.',
Ka='Kaskade:BAACLgAFFH8SAAIJAAUJ3R7XHABfAQAJAAUJ3R7XHABfAQAuAAQKfzwAAgkACQnRJBYFADkDAAkACQnRJBYFADkDAAAA.',
Ke='Keidars:BAAALgADCgcJEQAAAA==.',
Kr='Kryptois:BAAALgAECgEJAQAAAA==.',
Ky='Kyoshirô:BAAALgAECggJDwABLgAFFAQJDAAPAEUWAA==.',
La='Lakshmi:BAAALgAECgEJAQAAAA==.',
Li='Lights:BAAALgADCgcJHAAAAA==.Linaria:BAABLgAECn8fAAIPAAcJoQo+jwAhAQAPAAcJoQo+jwAhAQAAAA==.Lit:BAAALgAECgEJAQAAAA==.',
Lo='Lostdrake:BAACLgAFFH8JAAMQAAMJXx8MFQAMAQAQAAMJXx8MFQAMAQARAAIJ+A4MQACGAAAuAAQKfykAAxAACQmFHncGAHoCABAACQmFHncGAHoCABEAAgk+F/Z1AEMAAAAA.Lostshock:BAAALgAFFAEJAgAAAA==.',
Lu='Luna:BAABLgAECn8eAAMQAAgJmhLfEgB3AQAQAAgJmhLfEgB3AQARAAEJnwSzhQAlAAAAAA==.',
Ma='Maomao:BAAALgAECgQJBQAAAA==.',
My='Myro:BAABLgAECn8OAAISAAYJsh9DOAAUAgASAAYJsh9DOAAUAgAAAA==.',
Ne='Nekron:BAAALgADCgQJBAAAAA==.Nerethil:BAAALgAECgQJBAAAAA==.',
Oi='Oimate:BAAALgAECgYJDwAAAA==.',
Pa='Padanfain:BAAALgAECgYJEAAAAA==.Pakal:BAABLgAECn8jAAMTAAkJ4h04CQCuAQATAAUJ+CI4CQCuAQAMAAgJ9xnQGgCYAQAAAA==.',
Pe='Peacandlove:BAAALgAECgcJCAAAAA==.Pepso:BAACLgAFFH8HAAINAAQJHxK1EQANAQANAAQJHxK1EQANAQAuAAQKfx4AAg0ACAkeIBkIAMcCAA0ACAkeIBkIAMcCAAAA.Perfect:BAAALgADCgYJBgABLgABCgMJBAAUAAAAAA==.',
Po='Polaris:BAABLgAECn8vAAIDAAgJ7yCwCwDmAgADAAgJ7yCwCwDmAgAAAA==.',
Qu='Quake:BAAALgADCgMJAwAAAA==.Quikkshot:BAABLgAECn8rAAMFAAkJ4CDgCADxAgAFAAkJ4CDgCADxAgAGAAUJnQ1jUwD+AAAAAA==.',
Ra='Ratribution:BAECLgAFFH8FAAIJAAIJbxcAggBSAAAJAAIJbxcAggBSAAAuAAQKfyYAAgkACQk6IkYKAPsCAAkACQk6IkYKAPsCAAEuAAUUBwkWAA4AtxwA.',
Sa='Sassap:BAAALgAECggJDwAAAA==.',
So='Soph:BAAALgAECgIJAgAAAA==.',
Sp='Spicë:BAAALgADCgEJAQABLgAECggJDwAUAAAAAA==.Spooky:BAAALgAECgEJAQAAAA==.',
Sq='Squid:BAAALgAECgMJAwAAAA==.',
Su='Suny:BAAALgADCgYJBgABLgAECgMJAwAUAAAAAA==.Superchill:BAAALgADCgEJAQAAAA==.',
Ta='Taarna:BAAALgADCgcJCQAAAA==.Tacobelle:BAACLgAFFH8QAAMVAAMJCyaXFABHAQAVAAMJCyaXFABHAQAWAAEJ/yBsDQBkAAAuAAQKfzIABBUACAm2JukDAH0DABUACAm2JukDAH0DABYABAkhJFALAHIBABcAAQkAAGhVAG4AAAEuAAUUBQkWABYALSYA.Tanabata:BAAALgADCgUJCAAAAA==.',
Th='Throatdk:BAACLgAFFH8eAAQPAAgJ/RhPBAC7AQAYAAUJXBlhAQDDAQAPAAYJBBhPBAC7AQAZAAEJAADyNAAAAAAuAAQKfycAAxgACAlNJqABAN8CAA8ACAklJDkOACkDABgACAmqJKABAN8CAAAA.',
Um='Umbrakinetic:BAAALgADCgEJAQAAAA==.',
Un='Universe:BAAALgADCgUJBwAAAA==.',
Va='Valdrok:BAAALgAECgUJCQABLgAECgUJEgAUAAAAAA==.Valea:BAAALgADCgUJBQAAAA==.Valeri:BAAALgADCgEJAQAAAA==.Vall:BAAALgAECgMJBQABLgAECgUJEgAUAAAAAA==.Valrin:BAAALgAECgUJBgABLgAECgUJEgAUAAAAAA==.',
Ve='Veli:BAAALgAECgMJBAAAAA==.',
Vi='Vince:BAAALgADCgMJAwAAAA==.',
Vu='Vulteara:BAAALgAECgUJEgAAAA==.',
Vy='Vyndia:BAAALgADCgMJAwABLgAECgUJEgAUAAAAAA==.Vyndie:BAAALgADCgYJBgABLgAECgUJEgAUAAAAAA==.',
Wa='Waffulz:BAAALgAECgMJAwAAAA==.Warcobraz:BAAALgADCgEJAQAAAA==.',
Za='Zagreus:BAAALgADCgUJBQAAAA==.',
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
