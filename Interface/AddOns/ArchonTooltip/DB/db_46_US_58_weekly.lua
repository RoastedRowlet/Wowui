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

local lookup = {'Priest-Shadow','Druid-Guardian','Druid-Restoration','Druid-Feral','Unknown-Unknown','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival','Warlock-Demonology','Shaman-Elemental','Rogue-Subtlety','Paladin-Retribution','Mage-Arcane','Mage-Fire','Evoker-Augmentation','Paladin-Holy','Priest-Discipline','Priest-Holy','Paladin-Protection','Evoker-Preservation','DemonHunter-Devourer','Monk-Mistweaver','DemonHunter-Havoc','Rogue-Assassination','Warrior-Fury','Warlock-Destruction','Warlock-Affliction','Shaman-Restoration','Shaman-Enhancement',}
local provider = {region='US',realm='Dalvengyr',name='US',type='weekly',zone=46,date='2026-08-18',data={Ab='Abracadabras:BAAALgAECgEJAQAAAA==.',
Ac='Activity:BAACLgAFFH8LAAIBAAYJIRELFwAsAQABAAYJIRELFwAsAQAuAAQKfx4AAgEACQnWFoEYAB4CAAEACQnWFoEYAB4CAAAA.',
Ad='Addiegate:BAEALgAECgYJCgABLgAFFAkJRgACAK0mAA==.',
Ae='Aegis:BAAALgAECgQJBwAAAA==.Aerinis:BAACLgAFFH9ZAAMDAAkJkxrEAQDwAgADAAkJkxrEAQDwAgAEAAMJuhgvBQDwAAAuAAQKfyoAAwMACQnPIuUIAAEDAAMACQnPIuUIAAEDAAQAAwngEhYQAFYAAAAA.',
Ai='Airmail:BAAALgAECgkJBAAAAA==.',
Am='Amazement:BAAALgADCgEJAQAAAA==.',
An='Anirn:BAAALgAECgEJAQABLgAFFAEJAQAFAAAAAA==.',
Ap='Applicated:BAAALgADCgcJDQAAAA==.',
As='Asdzchisi:BAAALgAECgQJBgAAAA==.',
Av='Avoid:BAAALgAECgYJCQAAAA==.',
Be='Beannsidhe:BAAALgAECgMJAwAAAA==.Beast:BAACLgAFFH8rAAQGAAgJ5h1EBADBAQAGAAYJwB5EBADBAQAHAAYJJh2MKgC+AQAIAAEJAADvUQAAAAAuAAQKfygAAwcACAloI5AYAOgCAAcACAloI5AYAOgCAAYAAgkxJZAHANwAAAAA.',
Br='Bryan:BAACLgAFFH8JAAQJAAUJhAZ5IACoAAAJAAUJCAV5IACoAAAKAAIJCQixGQCgAAALAAEJ5gAXCAA/AAAuAAQKfxkAAwoACAkqIjQrAAgCAAoABgleHzQrAAgCAAkACAlLHMolAPsBAAAA.',
Bu='Burningman:BAAALgAECgYJBgAAAA==.Buttertooth:BAABLgAECn8aAAIMAAYJJxKhEgDlAAAMAAYJJxKhEgDlAAAAAA==.',
Ca='Catau:BAAALgAECgYJCwAAAA==.',
Ch='Chocokrispis:BAABLgAECn8dAAIKAAgJRB6kLwAeAgAKAAgJRB6kLwAeAgAAAA==.',
Cl='Classic:BAAALgAECgEJAQAAAA==.',
Cr='Critbender:BAACLgAFFH8MAAINAAQJvRiSIQAWAQANAAQJvRiSIQAWAQAuAAQKfx8AAg0ACQkSHi4QAHICAA0ACQkSHi4QAHICAAEuAAUUBAkQAA4A+hcA.Critjitters:BAACLgAFFH8QAAIOAAQJ+hdFEgD0AAAOAAQJ+hdFEgD0AAAuAAQKfxYAAg4ACAk4IVgIAKECAA4ACAk4IVgIAKECAAAA.',
Da='Dashr:BAAALgAECgEJAgAAAA==.Dawn:BAACLgAFFH84AAIPAAkJ2R92AwC6AgAPAAkJ2R92AwC6AgAuAAQKfz4AAg8ACQnaJb8HAFgDAA8ACQnaJb8HAFgDAAAA.',
De='Deeplyrooted:BAAALgADCgUJBQAAAA==.',
Do='Doriloca:BAAALgAECgMJBAAAAA==.Doñatello:BAAALgAECgEJAQAAAA==.',
Du='Duô:BAAALgADCgQJBAAAAA==.',
El='Eloraina:BAAALgAECgYJAgAAAA==.',
Em='Emmaya:BAABLgAECn8ZAAINAAcJwRFhSwAHAQANAAcJwRFhSwAHAQAAAA==.Emmét:BAAALgAECgEJBAAAAA==.',
Ev='Everly:BAAALgAECgEJAwABLgAFFAMJDgAPAGAiAA==.',
Fl='Flaky:BAAALgADCgUJBQAAAA==.Flames:BAAALgAECgYJDgABLgAFFAIJAgAFAAAAAA==.Flaykey:BAABLgAECn8vAAIBAAcJRBDkCQAnAQABAAcJRBDkCQAnAQAAAA==.',
Gi='Girth:BAABLgAECn8WAAMQAAgJjyDbAgBYAgAQAAcJih/bAgBYAgARAAcJeR99AgAlAgABLgAFFAgJCAASAIoUAA==.Gixy:BAAALgAECgMJAwAAAA==.',
Gl='Glinda:BAABLgAECn8eAAITAAkJrhlQAQDHAgATAAkJrhlQAQDHAgAAAA==.',
Ha='Halciyon:BAAALgAECgQJBQAAAA==.Halo:BAACLgAFFH8+AAMBAAYJ/hk8DQCOAQABAAYJ/hk8DQCOAQAUAAEJygHyUwArAAAuAAQKf2IABAEACAk/IvQQAFECAAEACAk/IvQQAFECABUABgmCITUWACACABQAAgkaGABdAIsAAAEuAAUUCQk4AA8A2R8A.Hansomebeast:BAAALgAECgEJAQAAAA==.',
He='Hellermlady:BAABLgAECn8eAAIGAAcJkgTzJwCUAAAGAAcJkgTzJwCUAAAAAA==.Hettikush:BAABLgAECn8bAAIPAAYJ1RPQFgAnAQAPAAYJ1RPQFgAnAQAAAA==.',
Ho='Hoksila:BAAALgAECgUJBgAAAA==.',
Is='Iskar:BAAALgAECgYJDQAAAA==.',
Ka='Kaskade:BAACLgAFFH8iAAIPAAcJyh7IGQCkAQAPAAcJyh7IGQCkAQAuAAQKf0sAAw8ACQn3JHMHADIDAA8ACQnRJHMHADIDABYABwn8HvkBABgCAAAA.',
Ke='Keidars:BAAALgADCgcJEQAAAA==.',
Kr='Kryptois:BAAALgAECgEJAQAAAA==.',
Ky='Kyoshirô:BAAALgAECggJEAABLgAFFAkJHAAHAGwYAA==.',
['Kì']='Kìngundéád:BAAALgAFFAIJAgAAAA==.',
La='Lakshmi:BAAALgAECgEJAQAAAA==.',
Li='Lights:BAAALgADCgcJHAAAAA==.Linaria:BAABLgAECn8rAAIHAAkJCQ36fABpAQAHAAkJCQ36fABpAQAAAA==.Lisari:BAAALgAECgEJAQABLgAFFAEJAQAFAAAAAA==.Lit:BAAALgAECgEJAQAAAA==.',
Lo='Lolan:BAAALgAECgQJBAABLgAFFAEJAQAFAAAAAA==.Lostdrake:BAACLgAFFH8MAAMXAAMJXx/AGQD6AAAXAAMJXx/AGQD6AAASAAIJ+A4MVAB5AAAuAAQKfykAAxcACQmFHq8HAHoCABcACQmFHq8HAHoCABIAAgk+Fz2NAEEAAAAA.Lostshock:BAAALgAFFAMJBAAAAA==.',
Lu='Luna:BAACLgAFFH8NAAMXAAQJ+xUCDwCtAAAXAAMJiRQCDwCtAAASAAQJEgNsJgCOAAAuAAQKfysAAxcACQndF+cLABkCABcACQndF+cLABkCABIAAwlgCJKCAFkAAAAA.',
Ma='Mac:BAABLgAFFH8JAAISAAQJEwTAIwCbAAASAAQJEwTAIwCbAAAAAA==.Manimekhala:BAAALgAECgQJBQAAAA==.Maomao:BAAALgAECgQJBQAAAA==.Maybedevour:BAABLgAFFH8GAAIYAAUJJgVCNgCdAAAYAAUJJgVCNgCdAAAAAA==.',
Mi='Mintyoonji:BAABLgAFFH8HAAIZAAQJLw8vHQDbAAAZAAQJLw8vHQDbAAAAAA==.Miregal:BAAALgAECgIJAgAAAA==.',
Mo='Monkladin:BAAALgADCgkJKAAAAA==.',
My='Myro:BAABLgAECn8OAAIYAAYJsh9DOAAUAgAYAAYJsh9DOAAUAgAAAA==.',
Ne='Nekron:BAAALgAECggJDQAAAA==.Nerethil:BAAALgAECgQJBAAAAA==.',
Ni='Nighte:BAAALgAECgEJAQAAAA==.',
Od='Odysseus:BAAALgAECgkJBwAAAQ==.',
Oi='Oimate:BAAALgAECgYJDwAAAA==.',
Pa='Padanfain:BAABLgAECn8YAAIaAAkJjwlsJQBOAQAaAAkJjwlsJQBOAQAAAA==.Pakal:BAABLgAECn8jAAMbAAkJ4h04CQCuAQAbAAUJ+CI4CQCuAQAOAAgJ9xm8IQCIAQAAAA==.',
Pe='Peacandlove:BAAALgAECgcJCAAAAA==.Pepso:BAACLgAFFH8HAAIVAAQJHxLOGQDsAAAVAAQJHxLOGQDsAAAuAAQKfx4AAhUACAkeIFQLALECABUACAkeIFQLALECAAAA.',
Po='Polaris:BAABLgAECn8vAAIDAAgJ7yCkDgDhAgADAAgJ7yCkDgDhAgAAAA==.',
Qu='Quake:BAAALgADCgMJAwAAAA==.Quikkshot:BAABLgAECn8sAAMKAAkJKiEmDwDXAgAKAAkJKiEmDwDXAgAJAAUJnQ1jUwD+AAAAAA==.',
Ra='Ratribution:BAECLgAFFH8GAAIPAAIJqx61sABWAAAPAAIJqx61sABWAAAuAAQKfyYAAg8ACQk6IkEQAOQCAA8ACQk6IkEQAOQCAAEuAAUUCQkoABQAHRoA.Rayzin:BAAALgAECgIJAgAAAA==.',
Ru='Ruckus:BAAALgAFFAIJAgABLgAFFAcJHgAcAM8fAA==.',
Sa='Sassap:BAABLgAECn8gAAIaAAkJ8hetAgAzAgAaAAkJ8hetAgAzAgAAAA==.',
Se='Sensaisoapp:BAAALgAECgEJAQAAAA==.',
Sh='Shockcollar:BAAALgADCgYJBgAAAA==.',
Sl='Slìmed:BAAALgADCgEJAQAAAA==.',
So='Soph:BAAALgAECgIJAgAAAA==.',
Sp='Spicë:BAAALgADCgEJAQABLgAECgkJIAAaAPIXAA==.Spider:BAAALgAFFAEJAgAAAA==.Spooky:BAAALgAECgEJAQAAAA==.',
Sq='Squid:BAAALgAECgMJAwAAAA==.',
Su='Suny:BAAALgADCgYJBgABLgAECgMJAwAFAAAAAA==.Superchill:BAAALgAECgEJAQAAAA==.Supra:BAAALgAFFAEJAQAAAA==.',
Ta='Taarna:BAAALgADCgcJCQAAAA==.Tacobelle:BAACLgAFFH8SAAQMAAMJCyaXFABHAQAMAAMJCyaXFABHAQAdAAEJRSN1GABqAAAeAAEJ/yCcGQBYAAAuAAQKfzIABAwACAm2JukDAH0DAAwACAm2JukDAH0DAB4ABAkhJGEPAGYBAB0AAQkAAGhVAG4AAAEuAAUUBwkfAB4ATiUA.Tanabata:BAAALgADCgUJCAAAAA==.',
Te='Teôtl:BAAALgADCgEJAQAAAA==.',
Th='Throatdk:BAACLgAFFH8hAAQHAAkJgBlPBAC7AQAHAAYJBBhPBAC7AQAGAAcJaRfOBQCVAQAIAAEJAABiSQAAAAAuAAQKfycAAwYACAlNJswCANICAAcACAklJDkOACkDAAYACAmqJMwCANICAAAA.',
Ty='Tylamor:BAAALgADCgcJCAAAAA==.',
Um='Umbrakinetic:BAAALgADCgEJAQAAAA==.',
Un='Universe:BAAALgADCgUJBwAAAA==.',
Va='Valdrok:BAAALgAFFAEJAQAAAA==.Valea:BAAALgAECgYJCAAAAA==.Valeri:BAAALgADCgEJAQAAAA==.Valick:BAAALgAFFAIJAgABLgAFFAEJAQAFAAAAAA==.Vall:BAAALgAECgMJBQABLgAFFAEJAQAFAAAAAA==.Valrin:BAAALgAECgUJBgABLgAFFAEJAQAFAAAAAA==.Valrina:BAAALgAFFAEJAQABLgAFFAEJAQAFAAAAAA==.',
Ve='Veli:BAAALgAECgMJBAAAAA==.',
Vi='Vince:BAAALgADCgMJAwAAAA==.Vivi:BAAALgAECgIJBwAAAA==.',
Vu='Vulteara:BAABLgAECn8UAAMfAAcJQhnzTQB5AQAfAAUJ5hvzTQB5AQAgAAIJfRmUEwBKAAABLgAFFAEJAQAFAAAAAA==.',
Vy='Vyndia:BAAALgAECgIJAgABLgAFFAEJAQAFAAAAAA==.Vyndie:BAAALgAECgEJAQABLgAFFAEJAQAFAAAAAA==.',
Wa='Waffulz:BAAALgAECgMJAwAAAA==.Warcobraz:BAAALgAECgEJAQAAAA==.Washikie:BAAALgADCgQJAwAAAA==.Waterlotus:BAAALgAECgEJAQAAAA==.',
Za='Zagreus:BAAALgADCgUJBQAAAA==.Zaqway:BAAALgAECgEJAQAAAA==.',
Ze='Zenadora:BAAALgAFFAEJAQABLgAFFAcJIwADAAAKAA==.',
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
