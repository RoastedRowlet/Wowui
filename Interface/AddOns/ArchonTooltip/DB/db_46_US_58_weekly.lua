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

local lookup = {'Priest-Shadow','Druid-Guardian','Druid-Restoration','Druid-Feral','Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival','Shaman-Elemental','Rogue-Subtlety','Paladin-Retribution','Unknown-Unknown','Mage-Arcane','Mage-Fire','Rogue-Assassination','Priest-Discipline','Priest-Holy','DeathKnight-Frost','DeathKnight-Unholy','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','DeathKnight-Blood',}
local provider = {region='US',realm='Dalvengyr',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abracadabras:BAAALgAECgEJAQAAAA==.',
Ac='Activity:BAACLgAFFH8HAAIBAAYJKA3xFQAvAQABAAYJKA3xFQAvAQAuAAQKfx4AAgEACQnWFjEjAK0BAAEACQnWFjEjAK0BAAAA.',
Ad='Addiegate:BAEALgAECgYJCgABLgAFFAkJOgACAIAmAA==.',
Ae='Aegis:BAAALgAECgQJBwAAAA==.Aerinis:BAACLgAFFH8mAAIDAAcJ3BdzCwAzAgADAAcJ3BdzCwAzAgAuAAQKfyUAAwMACQkHIOUIAAEDAAMACQkHIOUIAAEDAAQAAQm1B0MyADgAAAAA.',
Am='Amazement:BAAALgADCgEJAQAAAA==.',
Ap='Applicated:BAAALgADCgcJDQAAAA==.',
As='Asdzchisi:BAAALgAECgQJBQAAAA==.',
Av='Avoid:BAAALgAECgYJCQAAAA==.',
Be='Beannsidhe:BAAALgAECgMJAwAAAA==.',
Br='Bryan:BAACLgAFFH8JAAQFAAUJhAZ7HwCqAAAFAAUJCAV7HwCqAAAGAAIJCQixGQCgAAAHAAEJ5gAXCAA/AAAuAAQKfxkAAwYACAkqIjQrAAgCAAYABgleHzQrAAgCAAUACAlLHMolAPsBAAAA.',
Bu='Burningman:BAAALgAECgYJBgAAAA==.Buttertooth:BAAALgAECgEJAgAAAA==.',
Ca='Catau:BAAALgAECgYJCwAAAA==.',
Ch='Chocokrispis:BAABLgAECn8dAAIGAAgJRB5YLgAfAgAGAAgJRB5YLgAfAgAAAA==.',
Cl='Classic:BAAALgAECgEJAQAAAA==.',
Cr='Critbender:BAACLgAFFH8MAAIIAAQJvRgVIAAYAQAIAAQJvRgVIAAYAQAuAAQKfx8AAggACQkSHuQPAHMCAAgACQkSHuQPAHMCAAEuAAUUBAkHAAkAdBEA.Critjitters:BAABLgAFFH8HAAIJAAQJdBG+GgA8AQAJAAQJdBG+GgA8AQAAAA==.',
Da='Dashr:BAAALgAECgEJAQAAAA==.Dawn:BAACLgAFFH8lAAIKAAgJah8BAwC9AgAKAAgJah8BAwC9AgAuAAQKfz4AAgoACQnaJb8HAFgDAAoACQnaJb8HAFgDAAAA.',
De='Deeplyrooted:BAAALgADCgUJBQAAAA==.',
Do='Doriloca:BAAALgAECgMJBAAAAA==.Doñatello:BAAALgAECgEJAQAAAA==.',
Du='Duô:BAAALgADCgQJBAAAAA==.',
El='Eloraina:BAAALgAECgYJAgAAAA==.',
Em='Emmaya:BAABLgAECn8ZAAIIAAcJwhH6SQAIAQAIAAcJwhH6SQAIAQAAAA==.Emmét:BAAALgAECgEJAwAAAA==.',
Ev='Everly:BAAALgADCgcJCAABLgAECggJIwAKAAMlAA==.',
Fl='Flaky:BAAALgADCgUJBQAAAA==.Flames:BAAALgAECgQJBAABLgAFFAIJAgALAAAAAA==.Flaykey:BAAALgAECgYJBwAAAA==.',
Gi='Girth:BAABLgAECn8WAAMMAAgJjyDbAgBYAgAMAAcJih/bAgBYAgANAAcJeR99AgAlAgABLgAFFAcJGQAOACEeAA==.',
Ha='Halciyon:BAAALgAECgQJBQAAAA==.Halo:BAACLgAFFH82AAMBAAYJ/hmPDACQAQABAAYJ/hmPDACQAQAPAAEJygE0UQAsAAAuAAQKf2IABAEACAk/IrUQAFMCAAEACAk/IrUQAFMCABAABgmCIdkVACECAA8AAgkaGFRbAIwAAAEuAAUUCAklAAoAah8A.Hansomebeast:BAAALgAECgEJAQAAAA==.',
He='Hellermlady:BAABLgAECn8WAAIRAAYJJgPxKACGAAARAAYJJgPxKACGAAAAAA==.Hettikush:BAAALgAECgQJCAAAAA==.',
Ho='Hoksila:BAAALgAECgUJBgAAAA==.',
Is='Iskar:BAAALgAECgUJBQAAAA==.',
Ka='Kaskade:BAACLgAFFH8YAAIKAAYJ/B6jFwCmAQAKAAYJ/B6jFwCmAQAuAAQKf0AAAgoACQnRJFAIACYDAAoACQnRJFAIACYDAAAA.',
Ke='Keidars:BAAALgADCgcJEQAAAA==.',
Kr='Kryptois:BAAALgAECgEJAQAAAA==.',
Ky='Kyoshirô:BAAALgAECggJEAABLgAFFAUJDwASABMTAA==.',
La='Lakshmi:BAAALgAECgEJAQAAAA==.',
Li='Lights:BAAALgADCgcJHAAAAA==.Linaria:BAABLgAECn8oAAISAAgJTAt2egBsAQASAAgJTAt2egBsAQAAAA==.Lisari:BAAALgADCgEJAQABLgAECgUJEgALAAAAAA==.Lit:BAAALgAECgEJAQAAAA==.',
Lo='Lostdrake:BAACLgAFFH8MAAMTAAMJXx8lGQD7AAATAAMJXx8lGQD7AAAUAAIJ+A51UQB9AAAuAAQKfykAAxMACQmFHo8HAHoCABMACQmFHo8HAHoCABQAAgk+F2yKAEEAAAAA.Lostshock:BAAALgAFFAMJBAAAAA==.',
Lu='Luna:BAACLgAFFH8FAAMTAAIJ0QS5JgBZAAATAAIJ0QS5JgBZAAAUAAIJvAEgXQBZAAAuAAQKfycAAxMACQmFFsQLABkCABMACAkqFsQLABkCABQAAgn6BVSAAFkAAAEuAAUUAwkGAA8AIREA.',
Ma='Maomao:BAAALgAECgQJBQAAAA==.',
Mi='Miregal:BAAALgAECgIJAgAAAA==.',
Mo='Monkladin:BAAALgADCgYJBgAAAA==.',
My='Myro:BAABLgAECn8OAAIVAAYJsh9DOAAUAgAVAAYJsh9DOAAUAgAAAA==.',
Ne='Nekron:BAAALgAECggJCwAAAA==.Nerethil:BAAALgAECgQJBAAAAA==.',
Oi='Oimate:BAAALgAECgYJDwAAAA==.',
Pa='Padanfain:BAABLgAECn8VAAIWAAgJBwkfLAAaAQAWAAgJBwkfLAAaAQAAAA==.Pakal:BAABLgAECn8jAAMOAAkJ4h04CQCuAQAOAAUJ+CI4CQCuAQAJAAgJ9xkCIQCJAQAAAA==.',
Pe='Peacandlove:BAAALgAECgcJCAAAAA==.Pepso:BAACLgAFFH8HAAIQAAQJHxLsGADuAAAQAAQJHxLsGADuAAAuAAQKfx4AAhAACAkeIBsLALICABAACAkeIBsLALICAAAA.',
Po='Polaris:BAABLgAECn8vAAIDAAgJ7yBsDgDiAgADAAgJ7yBsDgDiAgAAAA==.',
Qu='Quake:BAAALgADCgMJAwAAAA==.Quikkshot:BAABLgAECn8rAAMGAAkJ4CCMDgDZAgAGAAkJ4CCMDgDZAgAFAAUJnQ1jUwD+AAAAAA==.',
Ra='Ratribution:BAECLgAFFH8GAAIKAAIJqx7lqgBXAAAKAAIJqx7lqgBXAAAuAAQKfyYAAgoACQk6Iq4PAOYCAAoACQk6Iq4PAOYCAAEuAAUUCAkhAA8AFBsA.Rayzin:BAAALgAECgIJAgAAAA==.',
Sa='Sassap:BAABLgAECn8XAAIWAAYJIRWcJQBHAQAWAAYJIRWcJQBHAQAAAA==.',
Sh='Shockcollar:BAAALgADCgYJBgAAAA==.',
So='Soph:BAAALgAECgIJAgAAAA==.',
Sp='Spicë:BAAALgADCgEJAQABLgAECggJFwAWACEVAA==.Spider:BAAALgAFFAEJAQAAAA==.Spooky:BAAALgAECgEJAQAAAA==.',
Sq='Squid:BAAALgAECgMJAwAAAA==.',
Su='Suny:BAAALgADCgYJBgABLgAECgMJAwALAAAAAA==.Superchill:BAAALgAECgEJAQAAAA==.',
Ta='Taarna:BAAALgADCgcJCQAAAA==.Tacobelle:BAACLgAFFH8RAAMXAAMJCyaXFABHAQAXAAMJCyaXFABHAQAYAAEJ/yB6GABZAAAuAAQKfzIABBcACAm2JukDAH0DABcACAm2JukDAH0DABgABAkhJPkOAGcBABkAAQkAAGhVAG4AAAEuAAUUBgkZABgAFiYA.Tanabata:BAAALgADCgUJCAAAAA==.',
Th='Throatdk:BAACLgAFFH8eAAQSAAgJ/RhPBAC7AQASAAYJBBhPBAC7AQARAAUJXBkkBQCXAQAaAAEJAADbRgAAAAAuAAQKfycAAxEACAlNJrMCANUCABIACAklJDkOACkDABEACAmqJLMCANUCAAAA.',
Ty='Tylamor:BAAALgADCgcJBwAAAA==.',
Um='Umbrakinetic:BAAALgADCgEJAQAAAA==.',
Un='Universe:BAAALgADCgUJBwAAAA==.',
Va='Valdrok:BAAALgAECgUJCQABLgAECgUJEgALAAAAAA==.Valea:BAAALgAECgQJBgAAAA==.Valeri:BAAALgADCgEJAQAAAA==.Valick:BAAALgAECgQJCQABLgAECgUJEgALAAAAAA==.Vall:BAAALgAECgMJBQABLgAECgUJEgALAAAAAA==.Valrin:BAAALgAECgUJBgABLgAECgUJEgALAAAAAA==.',
Ve='Veli:BAAALgAECgMJBAAAAA==.',
Vi='Vince:BAAALgADCgMJAwAAAA==.Vivi:BAAALgAECgIJAgAAAA==.',
Vu='Vulteara:BAAALgAECgUJEgAAAA==.',
Vy='Vyndia:BAAALgADCgMJAwABLgAECgUJEgALAAAAAA==.Vyndie:BAAALgADCgYJBgABLgAECgUJEgALAAAAAA==.',
Wa='Waffulz:BAAALgAECgMJAwAAAA==.Warcobraz:BAAALgAECgEJAQAAAA==.',
Za='Zagreus:BAAALgADCgUJBQAAAA==.Zaqway:BAAALgAECgEJAQAAAA==.',
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
