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

local lookup = {'DeathKnight-Unholy','Monk-Brewmaster','DeathKnight-Blood','Hunter-Survival','Paladin-Retribution','Druid-Restoration','Shaman-Restoration','DemonHunter-Devourer','Mage-Frost','Monk-Windwalker','Monk-Mistweaver','Warlock-Demonology','Warlock-Destruction','Warrior-Fury','Druid-Guardian','Rogue-Subtlety','Priest-Holy','Priest-Discipline','Priest-Shadow','Hunter-Marksmanship','Unknown-Unknown','Druid-Balance','Shaman-Elemental','Evoker-Preservation','Evoker-Augmentation','Warrior-Arms','Hunter-BeastMastery',}
local provider = {region='US',realm='Balnazzar',name='US',type='weekly',zone=46,date='2026-05-16',data={Ad='Adrianmonk:BAAALgAECgYJDgAAAA==.',
Ak='Aktuu:BAAALgADCgQJBAAAAA==.',
An='Andeys:BAAALgAECgYJCgAAAA==.Angelius:BAAALgAECgYJCAABLgAECgkJLgABAJYfAA==.',
Ar='Arasaka:BAAALgAECgIJAgABLgAECgkJHQACAJkTAA==.',
Ba='Baggigy:BAABLgAECn8ZAAMBAAYJ1Bz0bABBAQABAAYJ1Bz0bABBAQADAAQJQAQQNQBwAAAAAA==.Balance:BAAALgAFFAIJAwAAAA==.',
Be='Bentpanda:BAABLgAECn8WAAIEAAgJ5BUYEwDIAQAEAAgJ5BUYEwDIAQAAAA==.',
Bh='Bhain:BAABLgAFFH8GAAIFAAMJgxDGPQDyAAAFAAMJgxDGPQDyAAAAAA==.',
Bi='Bigcocko:BAACLgAFFH8bAAIGAAYJqx19BAA1AgAGAAYJqx19BAA1AgAuAAQKfysAAgYACQmGJYkCAHIDAAYACQmGJYkCAHIDAAAA.Birchwood:BAAALgAECgYJBgAAAA==.',
Bl='Blarrg:BAAALgAFFAEJAQABLgAECgYJGQABANQcAA==.Blocks:BAAALgADCgEJAgAAAA==.',
Bo='Boneriffik:BAAALgAECgUJDQAAAA==.Bossfury:BAAALgAECgYJCQAAAA==.',
Br='Brogh:BAAALgAECgYJEQAAAA==.',
Bu='Buffallo:BAABLgAECn8WAAIHAAkJ/AwuOQCdAQAHAAkJ/AwuOQCdAQAAAA==.',
Ca='Camouflage:BAABLgAECn8+AAIEAAkJpyQUAQA1AwAEAAkJpyQUAQA1AwAAAA==.Caneangel:BAAALgAFFAIJAgAAAA==.',
Ch='Charvhug:BAAALgAFFAEJAQABLgAFFAIJBQAFAAcVAA==.Chilyn:BAAALgADCgUJBgAAAA==.',
Co='Coldnbloodÿ:BAABLgAECn8cAAIIAAYJEw4YeADdAAAIAAYJEw4YeADdAAAAAA==.Corrupthell:BAAALgAECgYJCwAAAA==.Cowi:BAAALgAECgQJBwAAAA==.',
Cr='Crispaw:BAAALgAECgYJCwAAAA==.Crispo:BAAALgAECgYJDQAAAA==.',
Da='Dadbod:BAAALgAECgcJEQAAAA==.Dadsmemory:BAAALgAECgEJAQAAAA==.Darylbaryl:BAABLgAECn8YAAIJAAgJRxopXAAlAgAJAAgJRxopXAAlAgAAAA==.Daswassap:BAAALgAECgUJBQAAAA==.',
De='Def:BAAALgAECgEJAQAAAA==.Del:BAAALgAECgQJBgAAAA==.',
Dk='Dkdogg:BAAALgAECgEJAQAAAA==.',
Dr='Dragonfist:BAABLgAECn8dAAQCAAkJmRMYMACVAQACAAcJexMYMACVAQAKAAUJOhb6OwAsAQALAAEJ2xfxYgBEAAAAAA==.Driver:BAECLgAFFH8KAAIMAAQJ0AwOMwApAQAMAAQJ0AwOMwApAQAuAAQKfzUAAwwACAniHvMZALkCAAwACAniHvMZALkCAA0ABgniGNEUAKQBAAAA.',
['Dä']='Däenerys:BAAALgAECgcJBwAAAA==.',
Es='Esuna:BAAALgAECgMJBAAAAA==.',
Ew='Ewwf:BAAALgAECgMJBQABLgAFFAYJEQAIAMYhAA==.',
Ex='Exemplio:BAABLgAECn8lAAICAAkJlyTwAQAiAwACAAkJlyTwAQAiAwAAAA==.',
Fa='Fairyboy:BAAALgADCgYJDAAAAA==.',
Fe='Feel:BAAALgADCgQJBAAAAA==.Felbeast:BAAALgAECgEJAQABLgAECgkJHQACAJkTAA==.Felfirehell:BAAALgADCgMJBgAAAA==.',
Fi='Fininho:BAAALgADCgEJAQAAAA==.',
Fl='Flame:BAAALgAECgUJBQAAAA==.',
Fr='Frosty:BAABLgAECn8UAAIJAAcJzw3UqACIAQAJAAcJzw3UqACIAQAAAA==.Frybeam:BAAALgAECgEJAQAAAA==.',
Gi='Gilfoyle:BAAALgAECgEJAgAAAA==.Giovahni:BAABLgAECn8xAAIIAAgJ1h8OFABhAgAIAAgJ1h8OFABhAgAAAA==.',
Gl='Glaivemstake:BAAALgADCgYJDwAAAA==.',
Go='Goat:BAAALgADCgUJCAABLgAECgkJHQACAJkTAA==.',
Gr='Gristlecharm:BAABLgAECn8UAAIJAAcJsAVXyABYAQAJAAcJsAVXyABYAQAAAA==.',
Gw='Gwevon:BAAALgAECgMJAwAAAA==.',
Ha='Hateeho:BAABLgAECn8aAAIOAAgJ6hIsKgBfAQAOAAgJ6hIsKgBfAQAAAA==.Haxxen:BAAALgAECgQJBAAAAA==.',
Ho='Holylight:BAAALgAECgMJBQAAAA==.',
Ja='Jahblestraza:BAAALgAECgEJAgAAAA==.Janaria:BAAALgAECgYJDQAAAA==.Jandlion:BAAALgADCgYJBgAAAA==.Jaysix:BAAALgAECgUJBQAAAA==.',
Je='Jedah:BAAALgAECgEJAgAAAA==.Jessiescool:BAABLgAECn8aAAIFAAYJNQ7SlwBOAQAFAAYJNQ7SlwBOAQAAAA==.',
Ji='Jinxnyx:BAABLgAECn8YAAIPAAkJMw4wEAB1AQAPAAkJMw4wEAB1AQAAAA==.',
Jo='Johnnydeman:BAAALgADCgUJBQAAAA==.Jordanpoole:BAAALgAECgQJCgAAAA==.Joyluka:BAAALgAFFAMJBAAAAA==.',
Ka='Kalvin:BAABLgAECn8YAAIQAAcJJwyxIQAoAQAQAAcJJwyxIQAoAQAAAA==.Kanari:BAABLgAECn8UAAQRAAYJjhTvKgAoAQARAAYJjhTvKgAoAQASAAEJIwVpXQAoAAATAAMJxQDpawAZAAAAAA==.',
Ki='Killerkid:BAAALgADCgUJBwAAAA==.Kitaravana:BAAALgAECgEJAgAAAA==.',
La='Lagoles:BAABLgAECn8wAAMEAAkJgSEkAwDYAgAEAAkJ2iAkAwDYAgAUAAgJfR+aEwCYAgAAAA==.Lance:BAAALgAECgUJBQAAAA==.Landis:BAAALgAECgUJDAAAAA==.',
Le='Leaf:BAAALgAECgIJAwABLgAECgkJPgAEAKckAA==.Leoben:BAAALgAECgEJAgAAAA==.',
Li='Liltracey:BAAALgAECgUJCgABLgAFFAIJAwAVAAAAAA==.Listeriah:BAAALgADCgUJBgAAAA==.',
Lo='Lockbounty:BAAALgAECgEJAQAAAA==.',
Ma='Mambrú:BAAALgAECgMJAwABLgAECgkJGAAPADMOAA==.',
Mi='Miggles:BAACLgAFFH8NAAIGAAMJKhF+KgDMAAAGAAMJKhF+KgDMAAAuAAQKfykAAwYACQnGH3AOAKMCAAYACQnGH3AOAKMCABYAAglmDk1sAG8AAAAA.',
Mk='Mk:BAEBLgAECn83AAMKAAgJayMfBgAfAwAKAAgJayMfBgAfAwACAAUJpglMRQCtAAAAAA==.',
Mo='Monzo:BAABLgAECn8jAAMBAAgJ2iEEGQDmAgABAAgJ2iEEGQDmAgADAAIJ1A+SPQBcAAABLgAFFAIJAwAVAAAAAA==.Morvayne:BAABLgAECn8vAAIJAAkJSRzpHgBoAgAJAAkJSRzpHgBoAgABLgAECgkJMAAEAIEhAA==.',
My='Myneemo:BAAALgAECgQJAwAAAA==.Myro:BAAALgAECgUJCAAAAA==.',
No='Nomoneydown:BAAALgAECgEJAgAAAA==.Nosam:BAABLgAECn8XAAIMAAcJixAzZQA2AQAMAAcJixAzZQA2AQAAAA==.',
Nt='Nthegreat:BAAALgAECgUJBQAAAA==.',
Nw='Nwf:BAABLgAECn8WAAIOAAYJ5RgIPQCwAQAOAAYJ5RgIPQCwAQAAAA==.',
['Nè']='Nèbula:BAAALgAECgYJCAAAAA==.',
Or='Ornatas:BAACLgAFFH8HAAIXAAMJDR9yGQAIAQAXAAMJDR9yGQAIAQAuAAQKfxgAAhcACAnDHJYVAG8CABcACAnDHJYVAG8CAAAA.',
Pa='Pandamonium:BAABLgAECn8cAAQLAAcJkxT8KwBWAQALAAcJkxT8KwBWAQACAAQJ+AMpWABqAAAKAAEJOAmBfAApAAAAAA==.',
Pe='Perdyblues:BAAALgAECggJEAAAAA==.',
Po='Pom:BAAALgAECgEJAwAAAA==.',
Ps='Psymie:BAAALgAECgEJAQAAAA==.',
Qi='Qiana:BAAALgAECgQJBAABLgAECgkJIQARAL4bAA==.',
Qu='Quickstabbin:BAABLgAECn8bAAIKAAgJCAxsMAD2AAAKAAgJCAxsMAD2AAAAAA==.',
Ra='Rainootra:BAAALgADCgIJAgAAAA==.',
Re='Rebirthn:BAAALgAECgcJCQAAAA==.Redronz:BAAALgADCgUJCAABLgAECgkJHQACAJkTAA==.',
Ri='Riffroot:BAAALgADCgEJAQAAAA==.Ritheran:BAAALgAECgMJAwABLgAECgkJHQACAJkTAA==.',
Ro='Rocny:BAAALgAECgEJAQAAAA==.',
Sa='Saerus:BAAALgAECggJEQAAAA==.',
Sc='Scylla:BAACLgAFFH8SAAIYAAcJvx0uAQBCAgAYAAcJvx0uAQBCAgAuAAQKfywAAxgACQkAJh8AAOUDABgACQkAJh8AAOUDABkAAQmlDkVeAEIAAAEuAAQKBgkPABUAAAAA.',
Se='Sephiroth:BAABLgAECn8VAAIFAAkJDhSIQgAdAgAFAAkJDhSIQgAdAgAAAA==.',
Si='Silentbobb:BAAALgADCgcJBwAAAA==.',
Sn='Snow:BAAALgAECgQJBQABLgAECgkJPgAEAKckAA==.',
So='Soothe:BAAALgAECgYJCwAAAA==.',
Sw='Swaggasaurus:BAABLgAECn8aAAIFAAYJ7iHqPQDEAQAFAAYJ7iHqPQDEAQAAAA==.',
Sy='Sylarien:BAAALgAECgYJCgAAAA==.Syriena:BAAALgADCggJAwAAAA==.',
Ta='Tadok:BAAALgADCgUJBQAAAA==.Talset:BAACLgAFFH8HAAIOAAIJXhKDLACTAAAOAAIJXhKDLACTAAAuAAQKfxcAAg4ACAkOHWUeAKwBAA4ACAkOHWUeAKwBAAAA.',
Te='Tengoo:BAAALgAECgQJBAAAAA==.',
Th='Thewaitress:BAABLgAFFH8FAAIFAAIJBxUiUwCnAAAFAAIJBxUiUwCnAAAAAA==.Thylight:BAAALgADCgIJAgAAAA==.',
To='Tooperdy:BAAALgADCgIJAgAAAA==.',
Tr='Trappe:BAAALgADCgcJBwAAAA==.',
Tu='Tusker:BAAALgAECgcJDQAAAA==.',
Tw='Twostunz:BAAALgADCgcJDAAAAA==.',
Ur='Ursalvation:BAAALgADCgUJBQAAAA==.',
Va='Vad:BAAALgAECgEJAgAAAA==.',
Ve='Veew:BAABLgAECn8XAAMOAAgJ8RGROgC8AQAOAAgJOhGROgC8AQAaAAUJshEKGwAZAQAAAA==.',
Vy='Vynaca:BAAALgAECgEJAgAAAA==.',
Wa='Warpedshadow:BAAALgAECggJCwAAAA==.',
Wh='Whitegoddess:BAABLgAECn8gAAIbAAgJTQzaSABuAQAbAAgJTQzaSABuAQAAAA==.',
Wo='Wontan:BAAALgAECgcJCAAAAA==.',
Wu='Wukong:BAAALgAECgQJBAAAAA==.',
Xa='Xania:BAAALgAECgEJAgAAAA==.',
Yu='Yungmage:BAABLgAECn8aAAIJAAcJNxmQggDMAQAJAAcJNxmQggDMAQAAAA==.',
Za='Zaifu:BAAALgAECgEJAgAAAA==.',
Zi='Ziggy:BAABLgAECn8ZAAIJAAkJABhSRQBoAgAJAAkJABhSRQBoAgAAAA==.',
['Èl']='Èlfman:BAAALgAECgUJDwAAAA==.',
['Øm']='Ømega:BAAALgAECgEJAQAAAA==.',
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
