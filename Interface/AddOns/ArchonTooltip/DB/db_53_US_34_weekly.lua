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

local lookup = {'Paladin-Retribution','Shaman-Restoration','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Elemental','Rogue-Assassination','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','DeathKnight-Blood','Warrior-Arms','Paladin-Protection','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Unknown-Unknown','Mage-Arcane','Priest-Holy','DemonHunter-Havoc','DemonHunter-Devourer','Monk-Windwalker','Priest-Shadow','Rogue-Outlaw','Rogue-Subtlety','Mage-Frost','DeathKnight-Frost','Druid-Guardian','Druid-Restoration','Druid-Feral','Shaman-Enhancement','DeathKnight-Unholy','Monk-Mistweaver','Monk-Brewmaster','Warrior-Fury','Warrior-Protection','Priest-Discipline','DemonHunter-Vengeance','Paladin-Holy','Druid-Balance',}
local provider = {region='US',realm='BlackwaterRaiders',name='US',type='weekly',zone=53,date='2026-11-17',data={Ae='Aelarion:BAAANQADCgQIBAAAAA==.',
Al='Alba:BAACNQAFFH8JAAIBAAQK1hM8FgDYAAABAAQK1hM8FgDYAAA1AAQKf0MAAgEACgpHIKwfAEUDAAEACgpHIKwfAEUDAAAA.',
Am='Amádeus:BAAANQAECgEIAQABNQAECgoKJgACAM8eAA==.',
An='Andezard:BAABNQAECn8wAAMDAAoKgxPwUAArAgADAAoKgxPwUAArAgAEAAEK+wgSYwA4AAAAAA==.Angelys:BAAANQADCgYJCQAAAA==.',
Ap='Aphrobitey:BAAANQAECgQIBgABNQAECgoKOQAFAFEOAA==.',
As='Ashynn:BAAANQAECgIIAgAAAA==.Astrit:BAAANQADCggIEAAAAA==.',
At='Athenaowl:BAAANQAECgUICQAAAA==.',
Ay='Ayanoriko:BAACNQAFFH8IAAIGAAUKHg9PBwDWAAAGAAUKHg9PBwDWAAA1AAQKfz0AAgYACgq3IwwJAEgDAAYACgq3IwwJAEgDAAAA.Ayasumi:BAAANQAECggICQAAAA==.',
Az='Azonia:BAAANQADCgYJEQAAAA==.',
Ba='Babaganoosh:BAAANQAECgIIAgAAAA==.Babynick:BAABNQAECn8aAAMEAAkK7g00GgCyAQADAAgKvw2EegDHAQAEAAkKNws0GgCyAQAAAA==.Bacca:BAAANQADCgcIBwAAAA==.Baleme:BAAANQADCgYJEgAAAA==.',
Be='Beans:BAACNQAFFH8LAAQHAAQKSB7eBAC3AAAIAAMK6hwCHwD9AAAHAAIK0B/eBAC3AAAJAAEKARZzGwBPAAA1AAQKf04ABAgACgraJGsGAD0DAAgACgqiJGsGAD0DAAcABwrzIiYFADMCAAkABwr1GlsSAOIBAAE1AAUUBwgVAAoAfB4A.',
Bi='Bigsharder:BAAANQAECgMIBgABNQAFFAoKOwALAJccAA==.Bigstones:BAACNQAFFH8HAAILAAQK0wFMMQBYAAALAAQK0wFMMQBYAAA1AAQKfzUAAgsACgqjDRCeANEBAAsACgqjDRCeANEBAAAA.',
Bl='Blacksavior:BAABNQAECn8jAAMMAAoKpBdKFABiAgAMAAoKpBdKFABiAgABAAEKKAzSoAEwAAAAAA==.Blindbone:BAAANQADCggICAABNQAECgoKOAAFALoeAA==.Bloodnightz:BAAANQAECgIIAgAAAA==.Blucifer:BAAANQADCgUICAAAAA==.Bluehydra:BAAANQAECgYIBQAAAA==.Bluepocalyps:BAAANQADCggIHAAAAA==.',
Bo='Bobbydigital:BAABNQAECn8+AAIKAAoKZhQQIQDyAQAKAAoKZhQQIQDyAQAAAA==.Bolas:BAABNQAECn8WAAQNAAkKkgzdGgCVAAAOAAYKrQlxLgCqAAANAAQKtgXdGgCVAAAPAAIKpgG4TQA4AAAAAA==.Bopchop:BAAANQAECgcICQABNQAECggIEwAQAAAAAA==.Bowookie:BAAANQAECggICAAAAA==.',
Br='Bracynn:BAAANQAECgYIDAAAAA==.',
Bu='Buddapalm:BAAANQAECgEIAQAAAA==.',
Ca='Caimark:BAAANQADCggIEAAAAA==.Carí:BAAANQADCgcIBwAAAA==.',
Ce='Cealia:BAABNQAECn9GAAIRAAoKpBOdWQAIAgARAAoKpBOdWQAIAgAAAA==.Cephalo:BAAANQADCggIEwAAAA==.',
Ch='Chakuneeai:BAAANQAECgUICQAAAA==.Chancleta:BAAANQAECgUIBAAAAA==.Christae:BAABNQAECn8dAAISAAgKrxdKRwAaAgASAAgKrxdKRwAaAgAAAA==.Chronuwu:BAAANQADCgYIBgAAAA==.',
Cl='Clydè:BAAANQADCgYICwAAAA==.Cláncey:BAABNQAECn8mAAICAAoKzx5KHgDyAgACAAoKzx5KHgDyAgAAAA==.',
Co='Cocytus:BAAANQABCgIIAgABNQAECgoKUgAIAHsiAA==.Compromised:BAABNQAECn9AAAMTAAoK/B+jDwCzAgATAAoK/B+jDwCzAgAUAAYKqxDoOQB2AQAAAA==.Connalious:BAAANQAECgEIAQAAAA==.',
Cr='Crwth:BAABNQAECn8WAAIBAAUKUAHjdwFkAAABAAUKUAHjdwFkAAAAAA==.',
Cu='Curendae:BAABNQAECn8tAAIDAAkKkRTucgDaAQADAAkKkRTucgDaAQAAAA==.Curst:BAAANQADCgQIBAAAAA==.Cuzom:BAAANQADCgQICgAAAA==.',
Da='Dabaldzombie:BAAANQABCgIIAgABNQAFFAQIDgATACMSAA==.Danika:BAAANQAECgEIAQABNQAECgoKLwAVALghAA==.Darthknight:BAAANQADCgIIAwAAAA==.Dawk:BAAANQAECgUIDgAAAA==.Daxzazi:BAAANQAECgcIDgAAAA==.',
De='Decillian:BAABNQAECn8VAAMSAAkKURiNZADyAQASAAgKYBmNZADyAQAWAAEKAADecQBDAAAAAA==.Dern:BAABNQAECn8eAAICAAoKBhaTLgBoAgACAAoKBhaTLgBoAgAAAA==.Desolit:BAABNQAECn8uAAIUAAoKcB+lDACIAgAUAAoKcB+lDACIAgAAAA==.Dextur:BAAANQADCgUIBQAAAA==.',
Di='Dice:BAACNQAFFH8KAAIXAAYKVxFYAAA1AQAXAAYKVxFYAAA1AQA1AAQKfy8AAxcACgqIGqwBAGkCABcACgqIGqwBAGkCABgABQqBD9u6AHcAAAAA.',
Do='Docvader:BAAANQAECgUIBgAAAA==.',
Dr='Drunkenhealz:BAABNQAECn8XAAISAAcKhQ4SqwAVAQASAAcKhQ4SqwAVAQAAAA==.Drunks:BAAANQAECgIJAgAAAA==.Drvargas:BAAANQAECgQIBAAAAA==.',
Du='Duldar:BAAANQAECgEIAQAAAA==.',
Ec='Eccehomito:BAAANQAECgQIBAAAAA==.',
El='Elmo:BAABNQAECn8mAAIRAAkKXw7KhwCYAQARAAkKXw7KhwCYAQAAAA==.',
Em='Emryssa:BAAANQADCgUIBgAAAA==.',
Er='Erosis:BAACNQAFFH8IAAIRAAUK5RrKJADlAAARAAUK5RrKJADlAAA1AAQKfzsAAxEACgoMJnILAKgDABEACgoMJnILAKgDABkAAQoCEE1LAC8AAAAA.Eryx:BAAANQAECgQIBAAAAA==.',
Es='Esidh:BAAANQAECgcIBAABNQAECgoKHwAaACkKAA==.Esidk:BAABNQAECn8fAAIaAAoKKQrpSQBxAQAaAAoKKQrpSQBxAQAAAA==.Esimage:BAAANQAECgMIAwABNQAECgoKHwAaACkKAA==.',
Ex='Exboyfriend:BAAANQAECggIDgAAAA==.Exgirlfriend:BAAANQADCggIDAABNQAECgQIBAAQAAAAAA==.',
Ez='Ezaratren:BAAANQAECgUIBQABNQAECgoKHgASALkVAA==.Ezrin:BAAANQAECgQIBwAAAA==.',
Fe='Fear:BAABNQAECn82AAMIAAoKeyASEQDoAgAIAAoKeyASEQDoAgAJAAEKTBr0cAA+AAAAAA==.Felysria:BAAANQADCgYIBgAAAA==.',
Fr='Frequency:BAEANQAECgUIBwABNQAECgUICwAQAAAAAA==.',
Ga='Gakopozy:BAAANQAECgIIAwAAAA==.',
Gl='Glex:BAAANQAECgEIAQAAAA==.',
Gr='Grauggy:BAAANQAECgYIBgAAAA==.Grimlokke:BAAANQAECgEIAQABNQAECgoKHgASALkVAA==.Grïmyst:BAAANQAECggICAABNQAECgoKHgASALkVAA==.',
Gu='Gurten:BAAANQADCgMIAwABNQAECggIIAAXANELAA==.',
['Gé']='Géne:BAAANQAECgUIBgABNQAECgoKJgACAM8eAA==.',
Ha='Harbard:BAAANQAECgQICAAAAA==.Havrin:BAABNQAECn9UAAQbAAoKBRolEABeAgAbAAkKiBklEABeAgAcAAgKwAy6MABrAQAdAAUKWhazHgAQAQAAAA==.',
He='Headhûnter:BAABNQAECn8ZAAIeAAkKzgUtHQBKAQAeAAkKzgUtHQBKAQAAAA==.Headshots:BAAANQADCgQIBAABNQAFFAQICQABANYTAA==.Heizenburg:BAAANQADCgIIAgAAAA==.Hevenly:BAAANQADCgYIBgAAAA==.Hew:BAAANQAECgQIBQABNQAFFAYICgAXAFcRAA==.',
Hi='Hitomi:BAAANQADCgQIBAAAAA==.',
Ho='Honk:BAAANQAECgMJBQAAAA==.Hoogaplop:BAACNQAFFH8VAAQKAAcKfB77DwBVAQAKAAQKwB77DwBVAQAfAAQKwyBODwAWAQAaAAMKzBtsDgDlAAA1AAQKf0UABAoACQq8JgsJAHEDAAoACAqpJgsJAHEDAB8ACApVI44aAO0CABoABgoRJP4sADgCAAAA.',
Hu='Huamulan:BAABNQAECn8qAAIBAAoKxwQJCgEOAQABAAoKxwQJCgEOAQAAAA==.',
Ib='Ibchilling:BAABNQAECn8lAAIRAAoKExXixgD3AQARAAoKExXixgD3AQAAAA==.Ibcleaving:BAAANQADCggIDgAAAA==.',
Ic='Icarrus:BAABNQAECn9DAAMgAAoKRSEgBABoAwAgAAoKRSEgBABoAwAVAAEKAABdcwAmAAABNQAECgUIBwAQAAAAAA==.Iccarus:BAABNQAECn8pAAMCAAkK/x9FDgBPAwACAAkK/x9FDgBPAwAFAAEKAACCMgE2AAABNQAECgUIBwAQAAAAAA==.Icebone:BAAANQAECgYIBgABNQAECgoKOAAFALoeAA==.',
Ig='Ignis:BAAANQAECgUIBwAAAA==.',
Is='Iseldra:BAAANQAECgIIAQAAAA==.',
It='Itslifestyle:BAAANQADCggJDAAAAA==.',
Ja='Jackbfistn:BAABNQAECn8dAAIVAAoKsBWJFQATAgAVAAoKsBWJFQATAgABNQAECgoKOAAFALoeAA==.Jaskim:BAABNQAECn80AAIaAAoKkwYMWAA1AQAaAAoKkwYMWAA1AQAAAA==.Jaszy:BAAANQADCgMIAwABNQAECgoKNAAaAJMGAA==.',
Jo='Johanne:BAAANQADCgcIDQAAAA==.Jordomon:BAAANQAECgUICAAAAA==.',
Ka='Kaffee:BAAANQAECggICQAAAA==.Kahtonah:BAAANQABCgIIBAAAAA==.Kaltaan:BAACNQAFFH8GAAISAAYKQRn4CwDuAQASAAYKQRn4CwDuAQA1AAQKfzsAAxIACgq/JLcIAH4DABIACgq/JLcIAH4DABYABgovGHwrACoBAAAA.Karasan:BAAANQADCgQIBgAAAA==.Karenas:BAABNQAECn8hAAIRAAkKEhnphwBvAgARAAkKEhnphwBvAgAAAA==.Katbeans:BAABNQAECn9CAAMhAAoKByFpAwCyAgAhAAkKoiJpAwCyAgAVAAQKUBXpRgCMAAAAAA==.Katclaw:BAAANQAECgcIBgAAAA==.Kathrynne:BAABNQAECn8iAAIDAAkKaAjBmgB/AQADAAkKaAjBmgB/AQAAAA==.Katpaws:BAAANQADCgYIBgAAAA==.Katpuffs:BAAANQADCgEIAQAAAA==.Katscratch:BAAANQADCgIIAgABNQAECgoKSAAcAEAgAA==.Kaykoh:BAABNQAECn8kAAMfAAoK1CKnBwCHAwAfAAoK1CKnBwCHAwAKAAIKoB9HqQB+AAAAAA==.',
Ke='Kelicemoon:BAABNQAECn85AAMIAAoKCQwnXQC9AQAIAAoKCQwnXQC9AQAJAAMKXAGvawBJAAAAAA==.Kesta:BAAANQADCgIIAgAAAA==.',
Kh='Khaliope:BAAANQADCgQJBAAAAA==.Khatara:BAAANQADCgMIAwABNQAECgUIDgAQAAAAAA==.',
Ki='Kiara:BAAANQAECgEIAQAAAA==.',
Kl='Kloner:BAAANQAECgEIAgAAAA==.',
Ko='Kopiroll:BAAANQAECgEIAQAAAA==.',
Kr='Krecia:BAAANQADCggIHQAAAA==.',
['Kû']='Kûrr:BAAANQAECgMIBQABNQAECgoKJgACAM8eAA==.',
La='Ladielayne:BAAANQABCgUIBQAAAA==.Lahrnaon:BAAANQADCgYICAAAAA==.Laxeron:BAABNQAECn8kAAIiAAgKHiIpCQAQAgAiAAgKHiIpCQAQAgAAAA==.',
Le='Leotherassy:BAAANQAECgUIBQAAAA==.',
Lo='Lodehavoc:BAAANQADCggILQAAAA==.Longboneman:BAAANQAECgUIDAABNQAECgoKOAAFALoeAA==.',
Lu='Lusariah:BAAANQADCgYICQAAAA==.',
Ly='Lyat:BAABNQAECn9TAAIBAAoK3x8+JgDIAgABAAoK3x8+JgDIAgAAAA==.Lynthirae:BAABNQAECn83AAIGAAoK+xaODAADAgAGAAoK+xaODAADAgAAAA==.',
Ma='Madpearl:BAABNQAECn85AAIFAAoKUQ6CQwDGAQAFAAoKUQ6CQwDGAQAAAA==.Mal:BAAANQADCgEIAQABNQAECgcIBwAQAAAAAA==.',
Mc='Mcbodhran:BAABNQAECn8iAAIBAAkK+AfayABEAQABAAkK+AfayABEAQAAAA==.Mcfeast:BAABNQAECn8hAAIWAAgKnBgvHABjAgAWAAgKnBgvHABjAgAAAA==.',
Me='Medra:BAABNQAECn8mAAMLAAgKfQaIswASAQALAAgKfQaIswASAQAjAAIKAwM0QQA6AAAAAA==.Melidoria:BAAANQAECgUICQABNQAECgoKWQAOAPAWAA==.Meowdi:BAAANQADCggIKgAAAA==.',
Mi='Milou:BAABNQAECn8XAAMZAAgKYA/TEgB7AQARAAgKLw2U4ADHAQAZAAcKxw3TEgB7AQABNQAECgoKHgASALkVAA==.Minibone:BAABNQAECn8yAAILAAoKoxokNwBjAgALAAoKoxokNwBjAgABNQAECgoKOAAFALoeAA==.Mixr:BAAANQADCgEIAQAAAA==.Mizery:BAAANQAECgUIBQAAAA==.',
Mo='Moishe:BAAANQABCgQIBgAAAA==.Momobelfas:BAAANQAECgIIAQAAAA==.Monana:BAAANQADCgcIJAAAAA==.Moonwolf:BAAANQAECgcIEAAAAA==.',
Mu='Mummrak:BAAANQAECgcIDgAAAA==.',
My='Mysticwood:BAABNQAECn84AAIFAAoKuh5BIQAFAwAFAAoKuh5BIQAFAwAAAA==.',
Na='Nadjá:BAABNQAECn8yAAITAAoKeBjQGQBGAgATAAoKeBjQGQBGAgABNQAFFAQICQABANYTAA==.Naevys:BAAANQAECggIBgAAAA==.Nanija:BAAANQADCggIMAAAAA==.Narushi:BAAANQAECgUIBQAAAA==.Nathen:BAAANQADCgUIBQAAAA==.',
Ne='Nezrin:BAABNQAECn8dAAMCAAoKEBKZXQD2AQACAAoKEBKZXQD2AQAFAAMKuwdFvgCNAAAAAA==.',
Ni='Nightcat:BAABNQAECn9IAAIcAAoKQCBSBgB/AwAcAAoKQCBSBgB/AwAAAA==.Nitebäne:BAAANQAECgMIAQAAAA==.Nitestorm:BAABNQAECn8bAAIFAAoKJxoKSwBKAgAFAAoKJxoKSwBKAgAAAA==.Nixstyn:BAAANQABCgUIBwAAAA==.',
No='Nobonesjones:BAAANQAECgMIBAAAAA==.Noraelissa:BAABNQAECn8WAAIDAAkKmhnJfADBAQADAAkKmhnJfADBAQAAAA==.',
Og='Ogwarshock:BAACNQAFFH8GAAMJAAMK9hlmBgCTAAAJAAIK4xxmBgCTAAAIAAEKHRRMOABJAAA1AAQKfzQABAkACgrJI4YNACACAAkABQoYJoYNACACAAgABwoSHaOCAN8BAAcAAQp8H+knAEoAAAAA.',
Ol='Oliiver:BAABNQAECn9OAAIDAAoKXyBkJQCpAgADAAoKXyBkJQCpAgAAAA==.Olrun:BAAANQADCgEIAQAAAA==.',
Om='Omni:BAABNQAECn8eAAQSAAoKuRVaYQD9AQASAAoKuRVaYQD9AQAWAAEKyQWLZgAwAAAkAAEKfAYCLgApAAAAAA==.',
Or='Orbeez:BAAANQAECgIIAwAAAA==.Orcgasams:BAAANQADCgYIBwAAAA==.',
Ox='Oxidatia:BAAANQAECgEIAQAAAA==.',
Pa='Pallyofdoom:BAAANQAECgYIBAAAAA==.Panaceus:BAABNQAECn8/AAIPAAoKBR/KCgD3AgAPAAoKBR/KCgD3AgAAAA==.Patron:BAAANQADCgUIBQAAAA==.',
Pe='Perpetrator:BAAANQABCgIIAgABNQAECgYIEAAQAAAAAA==.',
Ph='Phrequency:BAEANQAECgUICwAAAA==.',
Pl='Plazmaglaive:BAABNQAECn8hAAMUAAoKLRIsGgDcAQAUAAkKLRIsGgDcAQATAAIKKAU9iQBTAAAAAA==.',
Po='Poalo:BAAANQAECgEIAQAAAA==.Poisonóus:BAABNQAECn8WAAIKAAgKDxoMRwDdAQAKAAgKDxoMRwDdAQAAAA==.Polywóg:BAAANQAECgIIAgAAAA==.Polyxo:BAABNQAECn8fAAIBAAgKnwvEvwBUAQABAAgKnwvEvwBUAQAAAA==.Pon:BAAANQABCgIIAgAAAA==.',
Pr='Pricker:BAAANQAECgUIBQABNQAECgoKOAAFALoeAA==.Prépared:BAACNQAFFH8OAAITAAQKIxJGEgDQAAATAAQKIxJGEgDQAAA1AAQKfyUAAyUACQoHGyEQAEQBABMACAqHGiczABICACUABwoqFiEQAEQBAAAA.',
Py='Pyrelic:BAAANQADCgYIBgAAAA==.',
Qa='Qayllera:BAAANQAECgUICgAAAA==.',
Qu='Quixotic:BAAANQADCgQIBwAAAA==.',
Ra='Radicchio:BAAANQADCgcIHwAAAA==.Radkeem:BAABNQAECn8tAAIKAAoKVh/1DwChAgAKAAoKVh/1DwChAgAAAA==.Ragnar:BAAANQADCgEIAQAAAA==.Rakeem:BAAANQAECgUIBQABNQAECgoKLQAKAFYfAA==.Ravenstone:BAAANQADCgcIDAAAAA==.Raya:BAACNQAFFH8FAAIgAAMKmhZcBwDqAAAgAAMKmhZcBwDqAAA1AAQKfx0AAyAABQqGIKoWAJUBACAABQqGIKoWAJUBABUAAgrPFgFXAI4AAAE1AAQKCQkXABYAIhwA.',
Re='Reluanne:BAAANQADCggICAAAAA==.Remorsa:BAAANQADCgcIDQAAAA==.Reshath:BAAANQADCgEIAQAAAA==.Reznor:BAABNQAECn80AAMmAAoKcxQCRABVAgAmAAoKcxQCRABVAgABAAQKKgpGPAHAAAAAAA==.',
Ro='Roejawb:BAABNQAECn8aAAIFAAcKoAYRsQAxAQAFAAcKoAYRsQAxAQAAAA==.Roeshamboe:BAAANQADCgYIBgAAAA==.Rosealia:BAAANQAECgUIBwAAAA==.',
Ry='Ryder:BAAANQAECgUIBQABNQADCgEIAQAQAAAAAA==.',
Sa='Sableanne:BAAANQAECgQICAAAAA==.Sacon:BAAANQADCgYIDQABNQAECgcIBwAQAAAAAA==.Sahmeah:BAAANQADCgUIBwAAAA==.Saintzan:BAABNQAECn82AAMmAAoKSRsSNwA/AgAmAAoKSRsSNwA/AgAMAAIKlRJrVwCCAAAAAA==.Salorll:BAAANQAECgYIEAAAAA==.Savia:BAAANQAECgQIBAAAAA==.',
Sc='Schmoogus:BAAANQADCgcJBQAAAA==.Schmoop:BAABNQAECn8mAAMWAAkKXCGtCQBFAwAWAAkKXCGtCQBFAwASAAUKShV3kgBfAQABNQAFFAcIFQAKAHweAA==.',
Se='Sellari:BAAANQAECggICAAAAA==.Senza:BAABNQAECn8ZAAIBAAcKwgadCgHZAAABAAcKwgadCgHZAAAAAA==.Senzyri:BAABNQAECn9BAAMDAAoK5w/OWAAZAgADAAoK5w/OWAAZAgAEAAIKiQU0VABZAAAAAA==.',
Sh='Shadyscales:BAACNQAFFH8IAAIXAAMKaQwEAgDjAAAXAAMKaQwEAgDjAAA1AAQKfy8AAhcACQprF3kGAGcCABcACQprF3kGAGcCAAAA.Shenro:BAABNQAECn8mAAIBAAoKQAtyrAB2AQABAAoKQAtyrAB2AQAAAA==.Shierà:BAAANQADCgcIBwABNQAECgYICwAQAAAAAA==.',
Si='Simic:BAABNQAECn8XAAIfAAkK/wcNOQA0AQAfAAkK/wcNOQA0AQAAAA==.Sinnori:BAAANQABCggICwAAAA==.',
Sm='Smiddy:BAABNQAECn8dAAMKAAoKoBLROQAfAgAKAAoKoBLROQAfAgAaAAQKUhUJcwDUAAAAAA==.',
So='Sorle:BAAANQADCgMIAwABNQAECggIJgALAH0GAA==.Souldrains:BAAANQADCggIJgAAAA==.Soyjak:BAABNQAECn8rAAMSAAoKohI1VQDnAQASAAoKohI1VQDnAQAWAAUKdgXtSgB/AAAAAA==.',
Sp='Spin:BAAANQAECgEIAgAAAA==.Spinner:BAAANQADCgMIAwAAAA==.Spudpal:BAAANQADCggICAABNQAFFAYIBgASAEEZAA==.',
St='Stonymahoney:BAAANQAECgcIDAAAAA==.Strongarmkin:BAABNQAECn8fAAILAAgK4xFxbwC0AQALAAgK4xFxbwC0AQAAAA==.',
Su='Suraisu:BAABNQAECn9OAAMiAAoKbSRNAQBCAwAiAAoKbSRNAQBCAwALAAIK8A10MAFzAAAAAA==.',
Sv='Sveela:BAABNQAECn9GAAIbAAoK6SRaAgCoAwAbAAoK6SRaAgCoAwAAAA==.Sveelaa:BAABNQAECn8yAAIDAAkKpCE2DwBpAwADAAkKpCE2DwBpAwABNQAECgoKRgAbAOkkAA==.Sveella:BAAANQAECgYIEAABNQAECgoKRgAbAOkkAA==.',
Sy='Syda:BAAANQAECgUIBwABNQAECggICQAQAAAAAA==.Syleinthus:BAAANQADCgQIBAAAAA==.',
Ta='Tacocat:BAABNQAECn8/AAMSAAoKUB1UMwCbAgASAAoKUB1UMwCbAgAWAAEKAAD4fQAAAAAAAA==.',
Te='Temlock:BAABNQAECn85AAIIAAoKxRRMPwAYAgAIAAoKxRRMPwAYAgAAAA==.Temtank:BAAANQAECgYICgABNQAECgoKOQAIAMUUAA==.',
Th='Thechiefster:BAAANQAECgQIBgAAAA==.Theidor:BAAANQADCgEIAQAAAA==.',
To='Toes:BAABNQAECn8ZAAMYAAkKphqiOAAZAgAYAAgKkBeiOAAZAgAGAAcKzxk5HQA8AQAAAA==.',
Tr='Traiya:BAAANQADCgEIAQAAAA==.Tralyn:BAAANQABCgQIBAAAAA==.Trukarak:BAABNQAECn8vAAIBAAkKtBAIkQCqAQABAAkKtBAIkQCqAQAAAA==.Trusturheals:BAAANQAECgcIEQAAAA==.',
['Tê']='Têss:BAAANQAECgQIBAAAAA==.',
Um='Umarg:BAAANQADCgMIAwAAAA==.',
Ur='Uraha:BAAANQAECgMIBQAAAA==.',
Va='Valor:BAAANQAECgMIBQAAAA==.',
['Và']='Vàlor:BAABNQAECn8lAAMKAAoKxQjxOwBRAQAKAAoKxQjxOwBRAQAfAAEKgAJEAQEWAAAAAA==.',
Wa='Wagons:BAAANQAECgcJBgAAAA==.Warfangg:BAAANQADCgMIAwAAAA==.',
Wi='Wildama:BAABNQAECn8qAAIcAAkK4g+4JQDFAQAcAAkK4g+4JQDFAQAAAA==.Windle:BAAANQADCggIGgAAAA==.Windseer:BAAANQADCgYICwABNQAFFAQICQABANYTAA==.',
Wu='Wumbo:BAAANQAECgUICAAAAA==.',
Xa='Xarríøn:BAAANQAECgQIBAABNQAFFAQIDQABAF0SAA==.',
Xh='Xhadowz:BAABNQAECn8aAAInAAoKEwc/YQBKAQAnAAoKEwc/YQBKAQAAAA==.',
Xi='Xiao:BAABNQAECn9NAAMgAAoKthXjDABcAgAgAAoKthXjDABcAgAVAAcKSQh3SQDYAAAAAA==.Xibi:BAAANQAECgMIAwAAAA==.Xingferat:BAAANQAECgUIBQAAAA==.',
['Xâ']='Xârriøn:BAAANQAECgQIBAABNQAFFAQIDQABAF0SAA==.',
Ya='Yahargul:BAABNQAECn8tAAIWAAcKWg7UOQBYAQAWAAcKWg7UOQBYAQAAAA==.',
Yo='Yogafarts:BAAANQADCgYIBgAAAA==.',
Za='Zanatilli:BAAANQADCggIJQAAAA==.Zaradin:BAAANQAECgQIBAABNQAECgUIDgAQAAAAAA==.Zariest:BAAANQADCgIIAgABNQAECgUIDgAQAAAAAA==.',
Ze='Zeik:BAABNQAECn9PAAIMAAoK7yGJBwDUAgAMAAoK7yGJBwDUAgAAAA==.Zellspell:BAAANQADCggICQABNQAFFAUIEwAFAGcdAA==.Zerase:BAAANQADCgEIAQAAAA==.Zerkchum:BAAANQADCgQIBAAAAA==.',
Zu='Zurone:BAAANQAECgMIAgAAAA==.',
['Àl']='Àlcàrà:BAAANQAECgYICwAAAA==.',
['Æv']='Ævølütîøn:BAAANQAECgUICwAAAA==.',
['Ÿa']='Ÿamar:BAAANQAECgQIBQAAAA==.',
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
