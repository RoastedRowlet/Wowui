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

local lookup = {'Rogue-Subtlety','Priest-Holy','Priest-Discipline','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Paladin-Holy','Druid-Feral','Druid-Balance','Druid-Restoration','DeathKnight-Unholy','DeathKnight-Blood','DemonHunter-Havoc','DemonHunter-Vengeance','Mage-Frost','Unknown-Unknown','Hunter-Marksmanship','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Hunter-BeastMastery','Mage-Arcane','Shaman-Restoration','Shaman-Enhancement','Paladin-Retribution','Rogue-Assassination','Warrior-Protection','Evoker-Devastation','DemonHunter-Devourer','Priest-Shadow','Paladin-Protection','Shaman-Elemental','Evoker-Augmentation','Evoker-Preservation','Druid-Guardian','Mage-Fire','DeathKnight-Frost','Warrior-Fury','Rogue-Outlaw','Warrior-Arms','Hunter-Survival',}
local provider = {region='US',realm='Dreadmaul',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abbathdoom:BAABLgAECn8WAAIBAAgJ4AlMKwAvAQABAAgJ4AlMKwAvAQAAAA==.',
Ae='Aedaris:BAABLgAECn9XAAMCAAkJPCBEDwBlAgACAAcJDiFEDwBlAgADAAYJHhmAKACAAQAAAA==.Ael:BAAALgAECgEJAQAAAA==.Aethalides:BAAALgAECgYJDwAAAA==.',
Al='Alandrias:BAAALgAECgkJAQAAAA==.Alf:BAAALgAECgEJAQAAAA==.Aloremirin:BAAALgADCgUJBQAAAA==.Altaria:BAABLgAFFH8fAAQEAAYJuRwjBwCVAQAEAAUJ3yIjBwCVAQAFAAUJKR1MGwA7AQAGAAEJZAmRUwA/AAAAAA==.Alvv:BAAALgADCgMJBQAAAA==.Alvz:BAAALgADCgMJAwAAAA==.',
Am='Ametrigos:BAAALgAECgEJAgABLgAECgkJJAAHAAggAA==.',
An='Anouke:BAAALgADCgIJAgAAAA==.Anserion:BAAALgADCgMJAwAAAA==.Anvious:BAAALgAECgcJDAAAAA==.',
Aq='Aquilea:BAABLgAECn8fAAMIAAkJJBINDQDVAQAIAAkJJBINDQDVAQAJAAEJhgY8kwAmAAAAAA==.',
Ar='Arcfuldodger:BAAALgAECgEJAgAAAA==.Artais:BAABLgAECn8gAAIKAAgJ1Rx8FgCCAgAKAAgJ1Rx8FgCCAgAAAA==.Artzlayer:BAACLgAFFH8IAAILAAMJrxvahADrAAALAAMJrxvahADrAAAuAAQKfzAAAwsACQlXI7wNAPYCAAsACQlXI7wNAPYCAAwAAQkAAKJpAAAAAAAA.Aríes:BAABLgAECn9RAAMNAAkJ3xqQCwBeAgANAAkJ3xqQCwBeAgAOAAEJGAk7MwAsAAAAAA==.',
As='Ashbourne:BAAALgADCgcJCwAAAA==.',
Aw='Aw:BAAALgAECgYJEQABLgAFFAcJGQAPALcWAA==.Awry:BAECLgAFFH8IAAILAAQJrxMjWgAzAQALAAQJrxMjWgAzAQAuAAQKfzIAAgsACQkcIi8LAA0DAAsACQkcIi8LAA0DAAAA.Awuuga:BAAALgAECgEJAQABLgAECgYJEgAQAAAAAA==.Aww:BAACLgAFFH8ZAAIPAAcJtxbJGwD9AQAPAAcJtxbJGwD9AQAuAAQKfyAAAg8ACAljGwV/ANMBAA8ACAljGwV/ANMBAAAA.',
Az='Azamalaza:BAABLgAECn8nAAIRAAgJbyKOBQA9AgARAAgJbyKOBQA9AgAAAA==.Azmo:BAACLgAFFH8NAAQSAAUJVRbaCgDZAAASAAMJDRbaCgDZAAATAAUJrQxxcADSAAAUAAEJ6xNUHQBRAAAuAAQKfyYAAxIACAkvIcECANYCABIACAmJHcECANYCABMABgk9HL1gAKcBAAAA.Azulon:BAAALgADCgUJBQABLgAECggJGgADAOkZAA==.Azyrt:BAAALgAECgQJBAABLgAECggJIAAKANUcAA==.',
Ba='Badds:BAABLgAECn8UAAIHAAkJgRYfEwBuAgAHAAkJgRYfEwBuAgAAAA==.Ballona:BAAALgADCgUJBQAAAA==.Baløø:BAAALgAECgEJAQAAAA==.Barad:BAAALgAECgEJBAAAAA==.Batrick:BAAALgADCgcJBwAAAA==.Baulric:BAAALgAECgEJAQAAAA==.Bawls:BAABLgAFFH8GAAIFAAIJ7gaWSQBsAAAFAAIJ7gaWSQBsAAAAAA==.',
Be='Beastroll:BAABLgAECn8XAAIVAAcJChWuVwCQAQAVAAcJChWuVwCQAQAAAA==.Beefrod:BAAALgADCgEJAQAAAA==.Beenis:BAAALgADCgUJBQAAAA==.Belerick:BAABLgAFFH8JAAIJAAMJnQqfDwDoAAAJAAMJnQqfDwDoAAAAAA==.Belphine:BAAALgAECgYJCAAAAA==.',
Bi='Bicksmage:BAACLgAFFH8PAAIPAAQJXhEOXAAnAQAPAAQJXhEOXAAnAQAuAAQKfxQAAw8ACAnyF9NlAKsBAA8ACAnyF9NlAKsBABYAAQmLBysgAC8AAAAA.Bigdaddylock:BAACLgAFFH8XAAQTAAcJxRp3KgB/AQATAAYJgxh3KgB/AQAUAAEJ+CP7EQBrAAASAAEJGBxNGQBbAAAuAAQKfyUAAxIACQnoJE4IAD4CABMACAkzI6IuAFICABIABgm1Ik4IAD4CAAAA.Biluman:BAAALgAECgQJBAAAAA==.Biodeath:BAAALgADCgUJBQAAAA==.Biopally:BAAALgADCgYJDQAAAA==.Biorogue:BAAALgADCgYJDAAAAA==.Bishope:BAABLgAECn8aAAIDAAgJ6RkUDwByAgADAAgJ6RkUDwByAgAAAA==.',
Bl='Bllizard:BAAALgAECgEJAQAAAA==.Bloodache:BAAALgADCgcJDgABLgAECgUJGQALAA4SAA==.Bluecar:BAAALgAECgYJCAAAAA==.',
Bo='Bohica:BAAALgAECgIJBQAAAA==.Bombdiggity:BAABLgAECn84AAIDAAgJ0B6kCwCoAgADAAgJ0B6kCwCoAgAAAA==.Bonnierot:BAAALgAECgUJCgAAAA==.',
Br='Brecciana:BAAALgADCgUJBQAAAA==.Brewjitsu:BAABLgAECn9IAAIFAAkJkR3GCACeAgAFAAkJkR3GCACeAgAAAA==.Brick:BAACLgAFFH8JAAMFAAMJeSHbIQAZAQAFAAMJeSHbIQAZAQAGAAEJ9BWzVAA8AAAuAAQKfx8AAgUABwl6HuQaAC0CAAUABwl6HuQaAC0CAAEuAAUUCAknABMAyBsA.Brongakill:BAAALgADCgYJBgAAAA==.Bräinfreeze:BAAALgAECgkJBwAAAA==.',
Bu='Buffy:BAAALgAECgEJAgAAAA==.Bumble:BAAALgADCgYJBgABLgAFFAgJJwACADkbAA==.Bundalock:BAAALgADCgYJEQAAAA==.',
Ca='Cakebringer:BAAALgAECgcJEgAAAA==.Caroshi:BAACLgAFFH8MAAIPAAQJawQObQD8AAAPAAQJawQObQD8AAAuAAQKfygAAg8ACQmzDUxdAMEBAA8ACQmzDUxdAMEBAAAA.',
Ce='Cell:BAAALgAECgUJCAABLgAECgkJIAAVAOMUAA==.Ceridwen:BAAALgADCgEJAQAAAA==.',
Ch='Charlotte:BAAALgAECgMJDAAAAA==.Cheto:BAABLgAFFH8GAAILAAIJzhOJwgCRAAALAAIJzhOJwgCRAAABLgAFFAYJEQAXAEkZAA==.Chosen:BAAALgADCgEJAQAAAA==.Chud:BAAALgAECgUJBQABLgAFFAYJGQAYAHgjAA==.',
Ci='Cig:BAABLgAECn8YAAIZAAgJ/xD+fABpAQAZAAgJ/xD+fABpAQAAAA==.',
Cl='Clankychan:BAACLgAFFH8LAAIFAAMJTA1SOAC5AAAFAAMJTA1SOAC5AAAuAAQKfxgAAgUABwkMFUc6AAsBAAUABwkMFUc6AAsBAAAA.Cloneofmagic:BAAALgADCgcJBwAAAA==.',
Co='Combustanut:BAAALgAECgUJEAAAAA==.Comillmouth:BAABLgAECn8ZAAIDAAgJbxEAJgCTAQADAAgJbxEAJgCTAQAAAA==.Comillthroat:BAAALgAECgkJEQAAAA==.Cos:BAABLgAECn82AAMBAAkJbxEiFgDfAQABAAkJbxEiFgDfAQAaAAMJOAXFFgCKAAAAAA==.',
Cr='Crozier:BAAALgAECgIJBgAAAA==.Crusher:BAAALgAECgUJBQABLgAFFAYJEQAXAEkZAA==.Cryptum:BAAALgAECgkJBAAAAA==.Cryten:BAAALgAECgIJAgAAAA==.',
Cu='Curby:BAAALgAECgcJBwABLgAECgkJTgAbAJ4eAA==.',
['Cä']='Cäin:BAAALgAECgQJCAAAAA==.',
Da='Dabufart:BAAALgADCgEJAQAAAA==.Daerus:BAAALgAECgYJBQAAAA==.Dagwood:BAAALgAECgEJAQAAAA==.Damge:BAAALgAECgUJCgAAAA==.Damnnyou:BAAALgAECgcJCAABLgAECgkJIwAcAK0ZAA==.Danky:BAAALgAECgMJAwAAAA==.Danteh:BAABLgAFFH8IAAIdAAMJ3wd2ZQCvAAAdAAMJ3wd2ZQCvAAAAAA==.Darahug:BAAALgAECgYJBgAAAA==.Daraina:BAAALgADCgEJAQABLgADCgEJAQAQAAAAAA==.Darktalanus:BAAALgADCgQJBAAAAA==.Darrkton:BAAALgADCgEJAQAAAA==.Dathil:BAAALgAECgYJCQAAAA==.Davmonhunter:BAAALgADCgQJBAAAAA==.Davoodooman:BAAALgAECgYJCAABLgAFFAQJEwATAJoWAA==.',
De='Deadiemurphy:BAAALgADCgYJCQAAAA==.Deathshunter:BAABLgAECn8iAAMVAAkJwCO0EADBAgAVAAgJWSW0EADBAgARAAYJ+hkjOgB5AQABLgAFFAYJHQALAGUiAA==.Deaththorn:BAAALgADCgEJAQAAAA==.Debsi:BAABLgAECn8kAAIbAAkJyA5BFQCTAQAbAAkJyA5BFQCTAQAAAA==.Declined:BAAALgAECgEJAQAAAA==.Deeper:BAABLgAFFH8NAAIXAAMJ3QdxVgCPAAAXAAMJ3QdxVgCPAAAAAA==.Deepest:BAABLgAFFH8HAAIaAAQJ0g/LBAA1AQAaAAQJ0g/LBAA1AQAAAA==.Deloraine:BAACLgAFFH8oAAIeAAcJjiR5AgBrAgAeAAcJjiR5AgBrAgAuAAQKfycAAh4ACQkAIgEFAAIDAB4ACQkAIgEFAAIDAAAA.Demonicfaith:BAABLgAECn82AAMNAAcJbxqFFwAMAgANAAYJTx6FFwAMAgAdAAcJlQzbgAAoAQAAAA==.Denman:BAABLgAECn8YAAMZAAcJjBnRdgCNAQAZAAcJjBnRdgCNAQAfAAEJmAAmUAAKAAAAAA==.Dezarian:BAAALgAECggJCAAAAA==.',
Di='Dirtyfista:BAAALgAECgYJBwAAAA==.Dirtyfux:BAACLgAFFH8KAAIDAAMJ5RJ3LQDEAAADAAMJ5RJ3LQDEAAAuAAQKfxUAAwMABglsHDIpAHwBAAMABglsHDIpAHwBAAIAAQkZDweDAC4AAAAA.Dirtysham:BAACLgAFFH8PAAIXAAQJcRoTKQAoAQAXAAQJcRoTKQAoAQAuAAQKfzAAAxcACQm3H/0MALUCABcACAl1If0MALUCACAABAmHCtJhAK8AAAAA.Discipline:BAAALgADCgcJBwAAAA==.Disckin:BAAALgAECgEJAwAAAA==.Diseasemode:BAAALgAECgEJAQAAAA==.Divinechill:BAAALgAECgEJAQAAAA==.',
Dn='Dnb:BAAALgADCgEJAQABLgAFFAcJGQAPALcWAA==.Dnk:BAAALgADCgMJAwAAAA==.',
Do='Dom:BAAALgADCgcJCQAAAA==.Donki:BAAALgAECgkJDAAAAA==.Doodtanky:BAAALgADCgEJAQAAAA==.Doomvedas:BAAALgAECgYJCgAAAA==.',
Dr='Dracaena:BAABLgAECn8jAAQcAAkJrRl1BgDbAQAhAAgJkBT/GwDoAQAcAAgJtBd1BgDbAQAiAAUJQwizMQDiAAAAAA==.Draco:BAAALgAECgMJAwAAAA==.Dreadknìght:BAAALgAFFAQJAgAAAA==.Drekavach:BAAALgADCgcJEwAAAA==.Droidbick:BAAALgAFFAIJAwAAAA==.',
['Dâ']='Dâftmonk:BAAALgAECgQJBgABLgAECgkJDAAQAAAAAA==.',
Ee='Eevo:BAAALgAECgMJAwABLgAECggJFAAGAJEIAA==.',
El='Elaha:BAAALgAECgcJCQAAAA==.Elexann:BAAALgAECgkJAQAAAA==.Elibaba:BAABLgAFFH8GAAIPAAIJMh/2iQC0AAAPAAIJMh/2iQC0AAAAAA==.Elideady:BAABLgAFFH8GAAILAAIJ7hZvvACWAAALAAIJ7hZvvACWAAABLgAFFAIJBgAPADIfAA==.Elinaa:BAAALgAECgIJAgAAAA==.Elindyl:BAAALgADCgEJAQAAAA==.Elleth:BAAALgADCgIJAgAAAA==.Elvishcheese:BAAALgAECgMJBgAAAA==.',
Em='Emojis:BAAALgAECgUJCQAAAA==.',
En='Endlessdh:BAACLgAFFH8IAAINAAMJCiIKBwDIAAANAAMJCiIKBwDIAAAuAAQKfx4AAg0ABwkyJJUJAMgCAA0ABwkyJJUJAMgCAAAA.',
Er='Eraserhead:BAAALgAECgYJEwABLgAFFAYJGQAYAHgjAA==.Eripaladin:BAAALgAECgIJAgAAAA==.Erissaria:BAAALgADCgEJAQAAAA==.',
Ev='Evening:BAAALgAECggJCQAAAA==.Everbuddha:BAAALgAECgQJBgAAAA==.',
Ew='Ewa:BAAALgAECgMJBAAAAA==.Eww:BAABLgAECn8XAAIdAAcJyw8CbwA4AQAdAAcJyw8CbwA4AQAAAA==.',
Ez='Ezelia:BAACLgAFFH8NAAMZAAQJqxZzMQA7AQAZAAQJqxZzMQA7AQAHAAIJgggxOAB1AAAuAAQKfxoAAxkACQl+Ft5CAPMBABkACQl+Ft5CAPMBAAcAAQlGCVeVADUAAAEuAAUUCAkwAAIA2BkA.',
Fa='Faelune:BAABLgAECn8fAAIPAAkJ6wp0ZgCpAQAPAAkJ6wp0ZgCpAQAAAA==.Faldir:BAAALgADCgYJBAABLgAFFAUJEwAdAEEZAA==.',
Fe='Ferndru:BAABLgAECn8lAAMIAAkJARmgCgAGAgAIAAgJ2BugCgAGAgAjAAcJahCsIQAtAQAAAA==.',
Fi='Fish:BAAALgAECgEJAgABLgAFFAQJCAAiAJ0XAA==.Fisticuffs:BAACLgAFFH8TAAIGAAYJdRDgGQB4AQAGAAYJdRDgGQB4AQAuAAQKfyIAAgYACAl3GKUdABcCAAYACAl3GKUdABcCAAAA.',
Fl='Flameshock:BAAALgAFFAIJBAAAAA==.Flowki:BAAALgADCgcJCwAAAA==.',
Fo='Forcespark:BAAALgAECgEJAQAAAA==.',
Fr='Fraserker:BAAALgAECgEJAQAAAA==.Frostradamus:BAAALgADCgkJCgAAAA==.',
Fu='Fullmoonride:BAAALgAECgUJDgAAAA==.Fumbll:BAAALgAECgkJCQAAAA==.Funkymajik:BAABLgAECn8fAAQDAAkJlg/kGwDhAQADAAkJlg/kGwDhAQACAAIJiAaJdQBTAAAeAAEJtQtOYgA0AAAAAA==.Furiosa:BAAALgADCgkJDgAAAA==.Furrballz:BAAALgAECgEJAQAAAA==.',
Ga='Gallywox:BAAALgADCgMJAwAAAA==.Ganin:BAABLgAECn8bAAIHAAYJUBU0QgBvAQAHAAYJUBU0QgBvAQAAAA==.Gankinyou:BAAALgADCgEJAQAAAA==.Garielyn:BAAALgADCgEJAQAAAA==.Garugala:BAACLgAFFH8OAAIZAAMJCRVfYADaAAAZAAMJCRVfYADaAAAuAAQKfysAAhkACQklGNMwADICABkACQklGNMwADICAAAA.',
Gd='Gdaycøb:BAAALgADCgYJBwAAAA==.',
Ge='Gengár:BAAALgAECgMJBgABLgAFFAEJAQAQAAAAAA==.',
Gh='Ghalorin:BAABLgAECn8VAAIVAAYJLg/mgAAwAQAVAAYJLg/mgAAwAQAAAA==.Ghiroza:BAABLgAECn9RAAQSAAkJ4R3fCAAzAgATAAkJ3B3NIgBQAgASAAgJihbfCAAzAgAUAAMJkhZpHQCGAAAAAA==.',
Gi='Gigaevoker:BAABLgAECn8kAAIiAAgJcRYvDAALAgAiAAgJcRYvDAALAgAAAA==.Gigapaladin:BAAALgADCgQJBAAAAA==.Gingarthas:BAABLgAECn8iAAILAAkJPh1hNgAdAgALAAkJPh1hNgAdAgAAAA==.',
Gl='Glowingtoe:BAAALgAECgMJBQAAAA==.',
Go='Gogmazios:BAAALgADCgcJBwAAAA==.',
Gr='Gravytate:BAABLgAECn9XAAIgAAkJfA8fLACGAQAgAAkJfA8fLACGAQAAAA==.Griinn:BAABLgAECn8eAAIjAAkJSg5JHQBPAQAjAAkJSg5JHQBPAQAAAA==.Grimefiend:BAAALgAFFAIJAwAAAA==.Grimescene:BAAALgAECgIJAgAAAA==.Grimreapêr:BAAALgAECgEJBAAAAA==.Grow:BAAALgAFFAEJAgAAAA==.',
Gu='Guldannyboy:BAABLgAECn80AAMSAAkJSw2YDABkAQASAAkJygyYDABkAQATAAkJFweAbgBZAQAAAA==.Gumbö:BAAALgAECgcJCQABLgAECggJIAAKANUcAA==.',
Ha='Haides:BAAALgAECgQJBQAAAA==.Hammer:BAAALgAECgIJAgABLgAECgkJDAAQAAAAAA==.Hanokano:BAAALgAECgUJBQAAAA==.Hantore:BAAALgADCgMJAwAAAA==.Harmony:BAAALgAECgEJAQAAAA==.Harry:BAACLgAFFH8IAAIYAAMJohdkDADgAAAYAAMJohdkDADgAAAuAAQKfycAAxgACQljJOUBAD8DABgACQljJOUBAD8DABcABwnEGuMgABoCAAAA.',
He='Heartdh:BAABLgAECn8VAAMdAAgJkhLgTwCKAQAdAAgJkhLgTwCKAQANAAIJrxOGWwByAAAAAA==.Heisenbergg:BAAALgADCgIJAgAAAA==.Hellza:BAAALgAECgMJAwAAAA==.Hen:BAAALgAECgUJBQABLgAECgYJFQAMABAVAA==.Herpyprotect:BAAALgAFFAIJAwAAAA==.Herrion:BAACLgAFFH8nAAQTAAgJyBsGEAAQAgATAAcJjBsGEAAQAgASAAEJKx0OGQBcAAAUAAEJyB8IFwBZAAAuAAQKfy4AAxMACQn/IvkcAKgCABMACAn/IvkcAKgCABIABAmcJNMUAKQBAAAA.',
Hh='Hh:BAAALgAECgEJAQAAAA==.',
Ho='Holytanky:BAAALgAECgUJBwAAAA==.Hotspur:BAABLgAECn84AAIKAAgJaxDUOADDAQAKAAgJaxDUOADDAQAAAA==.',
Hu='Hukani:BAAALgAECgEJAwABLgAECggJFgACALEIAA==.Hunner:BAAALgAECgIJAgABLgAECggJFAAGAJEIAA==.Huskar:BAABLgAECn8gAAIVAAkJ4xR5KwAkAgAVAAkJ4xR5KwAkAgAAAA==.',
Hy='Hypoxi:BAAALgADCgYJCQAAAA==.',
Ig='Ignis:BAABLgAECn8cAAIkAAkJmR2uAQBsAgAkAAkJmR2uAQBsAgAAAA==.Ignitor:BAAALgADCgEJAQAAAA==.',
Ik='Ikari:BAABLgAECn9YAAISAAkJyhpdBQCBAgASAAkJyhpdBQCBAgAAAA==.',
Il='Illadoss:BAAALgADCgIJAgAAAA==.',
Im='Imntprepared:BAAALgAFFAEJAQAAAA==.',
In='Incarnate:BAAALgAECgEJAgAAAA==.Incubis:BAAALgADCgIJAgAAAA==.Infectîon:BAAALgADCgYJBgAAAA==.Inferlock:BAAALgAECgMJAwAAAA==.Infernyos:BAAALgAECgUJBQAAAA==.Infernyoz:BAAALgADCggJCQAAAA==.',
Ir='Irithel:BAAALgAECgcJBQAAAA==.',
Is='Isohexene:BAAALgADCgYJBgAAAA==.',
It='Itchygrowth:BAAALgAFFAEJAQAAAA==.',
Iv='Ivygambina:BAAALgADCgYJBgAAAA==.Ivysore:BAAALgAECgUJBwAAAA==.',
Ja='Jasha:BAAALgADCgcJCwAAAA==.Jayvarmani:BAAALgAECgMJAwAAAA==.Jayy:BAABLgAECn8bAAILAAkJBRCKTAANAgALAAkJBRCKTAANAgAAAA==.',
Je='Jennatalia:BAAALgAECggJEgABLgAFFAEJAQAQAAAAAA==.',
Ji='Jinkazamaz:BAAALgAFFAIJBAAAAA==.',
Jo='Joelsdruid:BAABLgAFFH8YAAIjAAUJvx3hBwBdAQAjAAUJvx3hBwBdAQAAAA==.Joelvoker:BAAALgAFFAIJAgABLgAFFAUJGAAjAL8dAA==.Joexotic:BAAALgAECgIJBwAAAA==.Jongwang:BAAALgAECgQJBwAAAA==.',
Ju='Jubjub:BAAALgAECgEJAgAAAA==.',
Ka='Kaaru:BAACLgAFFH8FAAIDAAMJMQVDNQCVAAADAAMJMQVDNQCVAAAuAAQKfyUAAwMACQmME1kWABcCAAMACQl6ElkWABcCAAIABQkTEoZIABcBAAAA.Kahai:BAAALgAECgIJAgAAAA==.Kaiforst:BAAALgAECgQJBAABLgAECgkJNwAZAOEaAA==.Kaihavocz:BAAALgAECgEJAwAAAA==.Kairon:BAABLgAECn83AAIZAAkJ4RqZKQBRAgAZAAkJ4RqZKQBRAgAAAA==.Kalysae:BAAALgADCgEJAQAAAA==.Kania:BAAALgAECgIJAgABLgAECgkJMQAXAMQiAA==.Katarinabluu:BAAALgAECgYJBgAAAA==.Kazakhthundr:BAAALgADCgYJBgAAAA==.',
Ke='Keeanuleaves:BAAALgADCgYJBwAAAA==.Keeanuweaves:BAAALgADCgEJAQAAAA==.Keeze:BAACLgAFFH8QAAIPAAQJbQkGZwAPAQAPAAQJbQkGZwAPAQAuAAQKfxgAAg8ACQkaE1tSAN8BAA8ACQkaE1tSAN8BAAAA.',
Ki='Kickstarter:BAAALgAECgYJEgAAAA==.Kiel:BAAALgAECgEJAQAAAA==.Kikiz:BAAALgAECgUJBQAAAA==.Killania:BAAALgADCgMJAwAAAA==.Kiwichaos:BAACLgAFFH8KAAINAAQJnQnoGgCoAAANAAQJnQnoGgCoAAAuAAQKfy4AAg0ACQlbG6QMAJcCAA0ACQlbG6QMAJcCAAAA.',
Kn='Knox:BAAALgAECgUJCgAAAA==.Knull:BAAALgAECgIJAgAAAA==.',
Ko='Korner:BAAALgAECgIJAgAAAA==.',
Kr='Krazzul:BAAALgAECgQJBAAAAA==.Krellis:BAABLgAECn8aAAMEAAkJvRfTHAC7AQAEAAkJvRfTHAC7AQAGAAYJtRA8MQAzAQAAAA==.Kritikall:BAAALgADCgUJBQAAAA==.',
Ku='Kurö:BAAALgAECgEJAQAAAA==.',
Kv='Kvôthe:BAABLgAECn8dAAMLAAkJPgxMYwCZAQALAAkJCgtMYwCZAQAlAAMJzQfYJgCDAAAAAA==.',
Ky='Kynnareth:BAAALgAFFAIJBAABLgAFFAYJEAAHAJgNAA==.Kynralol:BAABLgAECn9LAAIPAAkJTiHgEADwAgAPAAkJTiHgEADwAgAAAA==.Kyunsun:BAAALgAECgYJCAAAAA==.',
['Ká']='Káiser:BAAALgAECggJEQAAAA==.',
La='Laenosh:BAABLgAECn8ZAAILAAUJDhJcywDkAAALAAUJDhJcywDkAAAAAA==.Lagalot:BAAALgAECgEJAQAAAA==.Laomoo:BAAALgAECgcJDgAAAA==.Laz:BAAALgADCgMJBQAAAA==.',
Le='Learning:BAABLgAECn8XAAIgAAcJEh9LGwA4AgAgAAcJEh9LGwA4AgAAAA==.Legham:BAAALgADCgkJDgAAAA==.Legolazz:BAABLgAECn8yAAMVAAkJ4B4qGACKAgAVAAkJ4B4qGACKAgARAAMJCBSsJwBuAAAAAA==.Lemins:BAAALgAECgMJAwAAAA==.Lemondruid:BAAALgAECgIJAgAAAA==.Lemonmelon:BAAALgAECgYJEwAAAA==.Lenatheplug:BAACLgAFFH8aAAMBAAcJ5BcMAwDMAQABAAYJTRwMAwDMAQAaAAIJjQnKBQBgAAAuAAQKfyIAAwEACAmUJEQKAO0CAAEACAnbI0QKAO0CABoABwlAIt4DAIACAAAA.Lerust:BAAALgADCgcJBwAAAA==.',
Li='Liadrine:BAACLgAFFH8FAAIZAAQJdAyJSQALAQAZAAQJdAyJSQALAQAuAAQKfzAAAhkACQnjF6REAO0BABkACQnjF6REAO0BAAAA.Lickyourass:BAAALgADCgYJCwAAAA==.Linus:BAAALgAECgYJBgABLgAFFAgJJwATAMgbAA==.Littleriver:BAABLgAECn8WAAIVAAgJvhirNgDUAQAVAAgJvhirNgDUAQAAAA==.',
Ll='Llewser:BAABLgAECn8aAAMPAAgJwhWdTADvAQAPAAgJwhWdTADvAQAkAAEJqgS/EwAqAAAAAA==.',
Lo='Loathe:BAAALgAECgEJAgAAAA==.Loistiah:BAABLgAFFH8IAAILAAMJZhlLiADmAAALAAMJZhlLiADmAAAAAA==.Lothaof:BAABLgAECn8sAAIZAAkJ6RIdVgC+AQAZAAkJ6RIdVgC+AQAAAA==.Louisvuitton:BAAALgAECgUJDwAAAA==.',
Lp='Lpayn:BAAALgADCgEJAQAAAA==.',
Lu='Lugroth:BAABLgAFFH8FAAMjAAMJWhaxFADIAAAjAAMJWhaxFADIAAAKAAEJIxGXZwA7AAABLgAFFAgJJwATAMgbAA==.Lunana:BAAALgAECgcJEgAAAA==.',
Ly='Lychiee:BAAALgAECgcJEQAAAA==.',
['Lì']='Lìnkinbark:BAAALgAECgMJAwAAAA==.',
Ma='Madara:BAAALgAECgEJAgAAAA==.Magesorry:BAAALgADCgUJBQAAAA==.Magicmon:BAAALgADCgkJFwAAAA==.Maize:BAABLgAECn8iAAMDAAgJMBsoEgBHAgADAAgJMBsoEgBHAgACAAMJhgvTZwCOAAAAAA==.Makima:BAABLgAFFH8FAAIJAAUJmQ7LKQDRAAAJAAUJmQ7LKQDRAAABLgAFFAUJLAAJAMEbAA==.Malikai:BAAALgADCgcJDAAAAA==.Malxsvoker:BAAALgAFFAIJAgABLgAFFAYJCwAgAOMLAA==.Marcymonk:BAAALgADCgEJAQAAAA==.Marcyon:BAABLgAECn8ZAAIdAAYJqAkSqgDDAAAdAAYJqAkSqgDDAAAAAA==.Marywinston:BAAALgAFFAEJAQABLgAFFAIJBgAMAFMUAA==.',
Mc='Mchèalz:BAABLgAECn8VAAQDAAgJRAhqOAAiAQADAAgJRAhqOAAiAQACAAQJxAFFaQCIAAAeAAIJOwF0ZgAsAAAAAA==.',
Me='Melodysseý:BAAALgAECgUJBQAAAA==.Melonlemonza:BAAALgADCgQJBAAAAA==.Mentok:BAAALgAECgYJCwAAAA==.Merchei:BAAALgAECgUJBgAAAA==.Meruen:BAACLgAFFH8IAAIdAAQJlBPFPgAaAQAdAAQJlBPFPgAaAQAuAAQKfzUAAx0ACQniGwAXAIICAB0ACQniGwAXAIICAA4AAwm2AuEoAFQAAAAA.',
Mi='Miss:BAAALgAECgMJAwAAAA==.Mistie:BAAALgAECgEJAQABLgAECgkJFwAKAFATAA==.Mitymorphin:BAAALgADCgEJAQAAAA==.',
Mo='Mobility:BAAALgAFFAEJAQAAAA==.Moistpole:BAAALgADCgQJBAAAAA==.Momock:BAAALgAECgQJBAAAAA==.Mongk:BAABLgAECn8UAAIGAAgJkQibNQAZAQAGAAgJkQibNQAZAQAAAA==.Monscustodes:BAABLgAECn8kAAIPAAkJWA8AWwDHAQAPAAkJWA8AWwDHAQAAAA==.Monstersauce:BAAALgAFFAIJBAAAAA==.Mookin:BAAALgAFFAEJAQAAAA==.Moospoon:BAABLgAECn89AAIZAAgJTBWeWgCzAQAZAAgJTBWeWgCzAQAAAA==.Mooudini:BAAALgAECgMJAwAAAA==.Moounka:BAABLgAECn9GAAIFAAkJcxPwFgDqAQAFAAkJcxPwFgDqAQAAAA==.Morphio:BAACLgAFFH8FAAIVAAMJSRmZSwD/AAAVAAMJSRmZSwD/AAAuAAQKf0sAAxUACQkvJaQCAGIDABUACQkvJaQCAGIDABEABQkLE5pMAB8BAAAA.Mostakrakish:BAAALgADCgEJAQAAAA==.',
Mu='Muddles:BAABLgAECn9EAAIFAAkJUBjXEAArAgAFAAkJUBjXEAArAgAAAA==.Murius:BAACLgAFFH8JAAILAAMJkQSKqAC4AAALAAMJkQSKqAC4AAAuAAQKfzIAAgsACQlEF8QzACcCAAsACQlEF8QzACcCAAAA.',
My='Mysterio:BAAALgAFFAEJBAAAAA==.',
Na='Naendria:BAAALgAECgMJBAAAAA==.Naga:BAAALgAECgIJAgAAAA==.Nahaza:BAAALgAECgEJAgAAAA==.',
Ne='Nelena:BAAALgADCgEJAQAAAA==.',
Ni='Nickdoom:BAAALgAECgUJEwAAAA==.Nigella:BAABLgAECn8WAAMCAAgJsQgEOQAHAQACAAgJsQgEOQAHAQADAAEJ6wGUfwAgAAAAAA==.Nikola:BAACLgAFFH8FAAIKAAIJzw/BTQB9AAAKAAIJzw/BTQB9AAAuAAQKfygABAoACQmjFWc3AMoBAAoACQmjFWc3AMoBACMABQk4Ft8VABQBAAkABAl9D39UANQAAAAA.Nimro:BAACLgAFFH8bAAIbAAcJqRV+BgC8AQAbAAcJqRV+BgC8AQAuAAQKfygAAhsACQmPH6ADABsDABsACQmPH6ADABsDAAAA.Niub:BAABLgAECn8pAAImAAkJwRPOHgDyAQAmAAkJwRPOHgDyAQAAAA==.',
No='Nofate:BAAALgADCgEJAQAAAA==.Noirebringer:BAAALgAFFAEJAQAAAA==.Nongbonnie:BAAALgAECgIJAgAAAA==.Nongkiwi:BAAALgAECggJCwAAAA==.',
Nt='Ntrldrake:BAAALgADCgEJAgABLgAECgkJJAAPAFgPAA==.',
Nu='Nueng:BAAALgADCgEJAQAAAA==.Nuferax:BAABLgAECn8fAAIOAAkJXyHIAQD1AgAOAAkJXyHIAQD1AgAAAA==.Nuiiwarx:BAAALgAECgEJAQAAAA==.Nulledhacz:BAAALgAECgUJAwAAAA==.Numbrethree:BAACLgAFFH8TAAIGAAQJ/hFjLADjAAAGAAQJ/hFjLADjAAAuAAQKf0MAAgYACAmcGIwfAAoCAAYACAmcGIwfAAoCAAAA.',
Ob='Obbi:BAACLgAFFH8YAAIaAAQJziZGAQDPAQAaAAQJziZGAQDPAQAuAAQKfxoAAxoACQkpIC4BAAUDABoACQkpIC4BAAUDACcAAQk/JPsaAGcAAAAA.',
Oh='Ohaither:BAAALgAECgQJBAAAAA==.',
Oi='Oirth:BAAALgADCgIJAgAAAA==.',
Ok='Okiji:BAAALgAECgkJEwAAAA==.',
Or='Orinocco:BAAALgAECgEJAwAAAA==.Orobas:BAAALgAECgkJCwAAAA==.',
Pa='Pakaww:BAAALgAECgIJAwAAAA==.Palimathrus:BAAALgAECgUJCAAAAA==.Palliative:BAABLgAECn9FAAMHAAkJMSJMBgAfAwAHAAkJMSJMBgAfAwAZAAQJLwUVDgGZAAAAAA==.Pallidnim:BAABLgAFFH8JAAIMAAUJuBF9GwD2AAAMAAUJuBF9GwD2AAAAAA==.Papager:BAABLgAFFH8HAAITAAMJvAYRfQC6AAATAAMJvAYRfQC6AAAAAA==.',
Pe='Pea:BAAALgAECgcJEAAAAA==.Perish:BAAALgAECggJDQABLgAECgkJRAAFAFAYAA==.',
Ph='Phatmonk:BAACLgAFFH8bAAMEAAUJkiZ9BADIAQAEAAUJkiZ9BADIAQAGAAIJyASYTQBRAAAuAAQKf0cAAwQACQmxJl8AAIoDAAQACQmxJl8AAIoDAAYABwntIAAQAJICAAAA.Phatrogue:BAABLgAFFH8JAAIBAAMJjB0ZIAANAQABAAMJjB0ZIAANAQABLgAFFAUJGwAEAJImAA==.',
Pi='Piewpiew:BAAALgADCgcJCgAAAA==.Pix:BAACLgAFFH8cAAMeAAcJZR3XAgDHAQAeAAcJZR3XAgDHAQADAAUJvQzZHABOAQAuAAQKfzYAAh4ACQk5JQMCAFIDAB4ACQk5JQMCAFIDAAAA.',
Pl='Pleasuremax:BAACLgAFFH8HAAIVAAQJWQyVQgAaAQAVAAQJWQyVQgAaAQAuAAQKfxoAAhUACAksFcdAANQBABUACAksFcdAANQBAAAA.Plex:BAABLgAECn8/AAIIAAkJRRrABgBmAgAIAAkJRRrABgBmAgAAAA==.',
Po='Poofyfeesh:BAAALgAFFAEJAgAAAA==.Poogie:BAAALgADCgYJBgABLgAECgMJBQAQAAAAAA==.Popshot:BAABLgAECn8eAAIRAAYJ5xIiRQBBAQARAAYJ5xIiRQBBAQAAAA==.Portalhouse:BAAALgAECgEJAQAAAA==.',
Pr='Praxis:BAACLgAFFH8LAAIbAAMJWRJaGwCtAAAbAAMJWRJaGwCtAAAuAAQKfy0AAxsACAkAFOgWAH8BABsACAmKEOgWAH8BACgABQlNFwAAAAAAAAAA.Preast:BAAALgAECgcJBwABLgAECggJFAAGAJEIAA==.Procist:BAABLgAECn8YAAMCAAkJBxcvDwBmAgACAAkJBxcvDwBmAgAeAAEJpQf5iAApAAABLgAECgkJMQAXAMQiAA==.',
Py='Pyrusdk:BAABLgAECn8ZAAILAAkJgQ6UWQCyAQALAAkJgQ6UWQCyAQAAAA==.Pyrusdruid:BAABLgAECn8WAAIKAAkJJwKTmAB2AAAKAAkJJwKTmAB2AAAAAA==.',
Qo='Qop:BAAALgAFFAEJAgAAAA==.',
Qu='Quesarah:BAAALgADCgEJAQABLgAECgQJBAAQAAAAAA==.',
Qw='Qweffor:BAAALgAECgUJBQABLgAFFAIJBQALAPcOAA==.',
Ra='Rainbowkelly:BAAALgAECgQJBAAAAA==.Raìn:BAACLgAFFH8HAAILAAMJmAyDmwDOAAALAAMJmAyDmwDOAAAuAAQKfxQAAgsACAnYFVNOANEBAAsACAnYFVNOANEBAAAA.',
Re='Recruitqt:BAABLgAECn8fAAMHAAUJtBoPOgCRAQAHAAUJtBoPOgCRAQAZAAQJExEDzQDqAAAAAA==.Reiayanami:BAABLgAECn8fAAIPAAgJfA/HeQB+AQAPAAgJfA/HeQB+AQAAAA==.',
Ri='Ripandtear:BAABLgAECn8gAAMKAAkJZReIJwAKAgAKAAkJZReIJwAKAgAIAAEJFQZ6NgAsAAAAAA==.',
Ro='Roguewan:BAAALgAFFAIJAgAAAA==.Rolâyne:BAAALgADCgkJDgAAAA==.Roninn:BAACLgAFFH8JAAIKAAMJpBVyNgDPAAAKAAMJpBVyNgDPAAAuAAQKfzQAAgoACQlVISYFAF4DAAoACQlVISYFAF4DAAAA.Ronlock:BAABLgAECn8VAAMTAAYJ8xD9nQAdAQATAAUJ8xD9nQAdAQASAAEJAAABagA+AAABLgAECgcJNgANAG8aAA==.Royaltits:BAAALgADCgIJAgAAAA==.',
Rs='Rsi:BAAALgAECgQJBAAAAA==.',
Ry='Rynaea:BAAALgAECgUJBgAAAA==.',
['Rï']='Rïmuru:BAAALgADCgcJCwAAAA==.',
['Rô']='Rôlayne:BAABLgAECn8ZAAImAAgJdQuuPgBCAQAmAAgJdQuuPgBCAQAAAA==.',
Sa='Sadakos:BAAALgAFFAMJBAAAAA==.Salvare:BAABLgAECn8lAAMaAAkJhhhwAwCVAgAaAAkJfRhwAwCVAgAnAAIJRRAfGgBwAAAAAA==.Sappy:BAAALgAECgQJBAAAAA==.Sarielsiá:BAAALgAFFAEJAQAAAA==.Sauron:BAAALgADCgEJAQABLgAFFAMJCAAoAKgWAA==.',
Sb='Sbf:BAABLgAFFH8ZAAIhAAcJ4RaZDQAAAgAhAAcJ4RaZDQAAAgABLgAFFAgJOwAPAPobAA==.',
Sc='Scalamander:BAAALgAECgcJAgAAAA==.Sciohunter:BAABLgAFFH8FAAINAAIJIAzJIAB5AAANAAIJIAzJIAB5AAAAAA==.Scioscioz:BAACLgAFFH8OAAIKAAQJ0BBvKwACAQAKAAQJ0BBvKwACAQAuAAQKfyAAAwoABwnOFOI7ALUBAAoABwnOFOI7ALUBAAkAAglnEAJsAHAAAAAA.Scwisgar:BAAALgAECgkJDQAAAA==.',
Se='Sedge:BAAALgAFFAIJBAAAAA==.Sephire:BAABLgAECn8eAAIZAAkJPARdwAD7AAAZAAkJPARdwAD7AAAAAA==.Sermazule:BAAALgADCgcJEQAAAA==.Sewerface:BAABLgAECn8VAAMMAAYJEBWaHgBTAQAMAAYJEBWaHgBTAQALAAMJLAScAQF2AAAAAA==.',
Sh='Shadonir:BAAALgAECgQJBAAAAA==.Shadowind:BAACLgAFFH8fAAIVAAUJKh8FJQBeAQAVAAUJKh8FJQBeAQAuAAQKfy8AAxEACQmGHn4dADsCABEACAlEGX4dADsCABUABQlkHWVaAIkBAAAA.Shaft:BAAALgAECgEJAQAAAA==.Shallotte:BAABLgAECn8YAAMUAAgJdRDoCwB7AQAUAAcJABLoCwB7AQATAAcJogh9kQAUAQAAAA==.Shambulance:BAAALgAECgMJAwAAAA==.Shammalxs:BAABLgAFFH8LAAIgAAYJ4wvxGAA9AQAgAAYJ4wvxGAA9AQAAAA==.Shamoc:BAABLgAECn8xAAMXAAkJxCL/BQBHAwAXAAkJxCL/BQBHAwAgAAYJohESSQAjAQAAAA==.Shampooing:BAACLgAFFH8MAAIgAAQJPg1GKADrAAAgAAQJPg1GKADrAAAuAAQKfygAAiAACQk3FwoWACkCACAACQk3FwoWACkCAAAA.Shampski:BAAALgAECgQJBAABLgAECggJFAAGAJEIAA==.Sharpknife:BAABLgAFFH8QAAMpAAQJCx2hDwA7AQApAAMJyCKhDwA7AQAVAAMJRhFDWwDaAAAAAA==.Shaz:BAAALgADCgQJBAAAAA==.Shivd:BAAALgAECgIJAgAAAA==.Shorpus:BAABLgAECn8hAAQgAAkJPx2QFgAkAgAYAAYJNx8hCgAwAgAgAAkJWhiQFgAkAgAXAAcJCwj6XQATAQAAAA==.',
Si='Sicckbrew:BAABLgAECn8hAAIEAAkJaiH+CQDYAgAEAAkJaiH+CQDYAgABLgAFFAQJCAAjABcNAA==.Sickin:BAABLgAFFH8IAAIjAAQJFw2AFQDCAAAjAAQJFw2AFQDCAAAAAA==.Sinniestro:BAAALgAECgEJAgAAAA==.',
Sk='Skizzyy:BAAALgAECgMJAwABLgAECgcJEAAQAAAAAA==.Skwigelf:BAAALgAECgQJBAAAAA==.',
Sl='Slayedurmrs:BAAALgAECgQJBQAAAA==.Slok:BAAALgAECgEJAQAAAA==.Slowpoke:BAABLgAFFH8sAAIJAAUJwRvNFwBEAQAJAAUJwRvNFwBEAQAAAA==.',
Sm='Smacedh:BAABLgAECn8XAAIdAAkJzRKUYgB6AQAdAAkJzRKUYgB6AQAAAA==.Smesher:BAABLgAECn8cAAIZAAkJGQrPdwBzAQAZAAkJGQrPdwBzAQAAAA==.',
Sn='Sneakyfella:BAAALgAFFAEJAgAAAA==.',
So='Solidus:BAABLgAFFH8GAAIZAAQJmhTKQQAaAQAZAAQJmhTKQQAaAQAAAA==.Sorgaath:BAAALgADCgcJBwAAAA==.',
Sp='Spaklehooves:BAAALgADCgYJBgAAAA==.Spicoli:BAAALgADCgEJAQAAAA==.Spiral:BAAALgAECgQJBwAAAA==.Spoonfed:BAAALgAECgQJCwAAAA==.',
Sq='Squiish:BAACLgAFFH8YAAMJAAgJ/hhVCADzAQAJAAcJ/RdVCADzAQAKAAUJkAWkJwAYAQAuAAQKfxoAAgkABwmoJfALANkCAAkABwmoJfALANkCAAAA.',
St='Stavrophore:BAAALgAECgEJBQAAAA==.Stickydruid:BAAALgAECgIJBgABLgAECgkJTgAeALohAA==.Stickyholes:BAAALgAECgIJAgABLgAECgkJTgAeALohAA==.Stickymonk:BAAALgAECgEJBAABLgAECgkJTgAeALohAA==.Stickypriest:BAABLgAECn9OAAMeAAkJuiEZCADJAgAeAAkJuiEZCADJAgACAAEJExiTeQBCAAAAAA==.Stipe:BAAALgADCgUJCAAAAA==.Stove:BAAALgADCgcJCwAAAA==.Strawhats:BAACLgAFFH87AAIPAAgJ+hsgAwBMAgAPAAgJ+hsgAwBMAgAuAAQKf0IAAg8ACQkyJWcCANgDAA8ACQkyJWcCANgDAAAA.Streamliner:BAABLgAECn8/AAMBAAkJJBu8CgBsAgABAAkJJBu8CgBsAgAnAAMJ1gdKCwCNAAAAAA==.Stuunks:BAAALgAECgYJCwAAAA==.',
Su='Surv:BAACLgAFFH8LAAMpAAUJ8hRREAA2AQApAAQJyBhREAA2AQARAAIJUwRqIQCHAAAuAAQKfx8AAxEABwmVIJcJAM8BABEABgn+H5cJAM8BACkABwk6G7UZAMwBAAAA.Sustangelia:BAABLgAECn8bAAMLAAkJbxh6UAAAAgALAAkJbxh6UAAAAgAlAAEJBw/KMABGAAAAAA==.',
Sw='Swordkiller:BAAALgAECgcJBgAAAA==.',
Sx='Sxy:BAAALgAECgYJBwABLgAECgkJPwAIAEUaAA==.',
Sy='Sy:BAAALgAFFAIJAgAAAA==.Synthesis:BAABLgAECn8hAAIKAAgJoyXOBQBUAwAKAAgJoyXOBQBUAwAAAA==.',
Ta='Tae:BAAALgADCgUJBQAAAA==.Taichee:BAAALgADCgUJBQAAAA==.Talas:BAAALgAECgQJBQAAAA==.Talletalanot:BAACLgAFFH8JAAIiAAMJWglwIACSAAAiAAMJWglwIACSAAAuAAQKfy4AAiIACQkbIIgFALUCACIACQkbIIgFALUCAAAA.Tandryan:BAAALgAECgQJBwAAAA==.Tanukiji:BAABLgAECn8nAAICAAkJFhzRDQB8AgACAAkJFhzRDQB8AgAAAA==.',
Td='Tdh:BAAALgADCgMJAwAAAA==.Tdk:BAABLgAECn8WAAMLAAgJqhQ6swAGAQALAAcJzhU6swAGAQAMAAEJ0Q0mVQA6AAAAAA==.',
Te='Tee:BAAALgADCgUJBQAAAA==.Terry:BAAALgAECgcJBwAAAA==.Tesarion:BAACLgAFFH8FAAILAAIJ9w40zwCJAAALAAIJ9w40zwCJAAAuAAQKfxYAAgsACAkdGMhVALwBAAsACAkdGMhVALwBAAAA.Testalatesta:BAABLgAECn9KAAMHAAkJBSXsAAC8AwAHAAkJBSXsAAC8AwAZAAEJmwhkmgEpAAAAAA==.Testaltesta:BAAALgAECgkJEQABLgAECgkJSgAHAAUlAA==.',
Th='Tharien:BAAALgADCgIJAgAAAA==.Thovir:BAAALgADCgEJAQAAAA==.',
Ti='Tiberian:BAAALgADCgIJAgAAAA==.Tinyvolt:BAAALgAECggJCwAAAA==.',
Tm='Tmonk:BAAALgAECgkJDgAAAA==.',
To='Toinahun:BAAALgAECgQJBAAAAA==.Tookersoul:BAAALgAECgEJAQAAAA==.Totemea:BAAALgAECgYJDgAAAA==.Totems:BAACLgAFFH8RAAIXAAYJSRkqEQC9AQAXAAYJSRkqEQC9AQAuAAQKfxUAAhcACAkuG9MdAFICABcACAkuG9MdAFICAAAA.Totemteabag:BAAALgAECgEJAQAAAA==.Totemîxx:BAABLgAECn8wAAMgAAkJnxl7EgBPAgAgAAkJnxl7EgBPAgAXAAQJYQ23fgCYAAAAAA==.Touchhy:BAAALgAECgEJAQAAAA==.',
Tr='Trainz:BAAALgADCgcJBwAAAA==.Trass:BAACLgAFFH8TAAMTAAQJmhZNQAA7AQATAAQJmhZNQAA7AQASAAEJERAWJABIAAAuAAQKf0EAAxMACQndIEMWAJkCABMACQndIEMWAJkCABIAAwkqERxEAKUAAAAA.Trays:BAAALgADCgEJAQAAAA==.Trisse:BAABLgAECn8nAAIdAAgJog+KWAByAQAdAAgJog+KWAByAQAAAA==.',
Tu='Tuzz:BAACLgAFFH8LAAIlAAMJehXYEQDeAAAlAAMJehXYEQDeAAAuAAQKfysAAiUACQljIWIBAO4CACUACQljIWIBAO4CAAAA.',
Tw='Twongle:BAAALgADCgIJAgABLgAECggJGgAPAMIVAA==.',
Ty='Tyden:BAAALgAECgYJEAAAAA==.Tyrmac:BAAALgAECgUJBgAAAA==.',
Va='Vael:BAAALgAECgYJCgAAAA==.Valerie:BAAALgAECgUJBwAAAA==.Valkyrra:BAAALgAECgQJBAAAAA==.Varaestia:BAAALgAECgQJBAAAAA==.Varg:BAAALgADCgEJAQABLgADCgEJAQAQAAAAAA==.Vargmk:BAAALgADCgEJAQAAAA==.Vargps:BAAALgADCgEJAQAAAA==.',
Ve='Velithara:BAAALgAECgcJBwAAAA==.Venestra:BAAALgAFFAMJBAAAAA==.Verdict:BAACLgAFFH8JAAIZAAQJzBsOMAA/AQAZAAQJzBsOMAA/AQAuAAQKfxgAAhkACAloHlsgAKoCABkACAloHlsgAKoCAAAA.Vermeil:BAAALgAECgMJAwAAAA==.Vermillion:BAACLgAFFH8ZAAIZAAYJpxoeFACnAQAZAAYJpxoeFACnAQAuAAQKfyIAAhkACQnuIAgQANwCABkACQnuIAgQANwCAAAA.Verzik:BAAALgAECgIJBAAAAA==.',
Vi='Vib:BAAALgAECgEJAQAAAA==.Viegas:BAACLgAFFH8FAAIVAAIJnRKpIwBZAAAVAAIJnRKpIwBZAAAuAAQKfxsAAhUABwkjHK4gAEECABUABwkjHK4gAEECAAAA.Vincent:BAABLgAECn8hAAIPAAYJsB6ZfgDUAQAPAAYJsB6ZfgDUAQAAAA==.Vinijr:BAAALgAECgEJAgAAAA==.Vivamax:BAAALgAECgEJAQAAAA==.Vizsla:BAACLgAFFH8MAAILAAMJ+g6FlgDUAAALAAMJ+g6FlgDUAAAuAAQKfxQAAgsABwlbEKerABEBAAsABwlbEKerABEBAAAA.',
Vo='Voidthotnimz:BAAALgADCgcJBgABLgAFFAUJFAAhAEILAA==.Volthic:BAAALgAECgQJBAAAAA==.Voltormu:BAAALgAECgMJBgAAAA==.Vore:BAABLgAECn8fAAIdAAkJeBWuNQDjAQAdAAkJeBWuNQDjAQAAAA==.',
Vr='Vrag:BAACLgAFFH8MAAILAAMJYApnnADNAAALAAMJYApnnADNAAAuAAQKfzcAAgsACQloGJEnAFsCAAsACQloGJEnAFsCAAAA.',
['Vè']='Vè:BAABLgAECn8bAAQMAAkJQBEDGgCEAQAMAAkJBQ8DGgCEAQALAAcJ/BC2eABqAQAlAAEJ5ATqOwAkAAAAAA==.',
['Vê']='Vêê:BAAALgAECgQJBgABLgAECgkJGwAMAEARAA==.',
Wa='Warslaw:BAACLgAFFH8bAAIMAAUJ6yILDgCAAQAMAAUJ6yILDgCAAQAuAAQKfyAAAgwACQlVI18FAOsCAAwACQlVI18FAOsCAAAA.Warth:BAAALgADCgEJAQAAAA==.Waterwater:BAAALgAECgYJCgAAAA==.Waterwaterz:BAACLgAFFH8UAAIPAAQJcRnRVAAzAQAPAAQJcRnRVAAzAQAuAAQKfzkAAg8ACAnVHOQ0AJ8CAA8ACAnVHOQ0AJ8CAAAA.',
Wc='Wchin:BAABLgAECn8aAAIWAAgJ0yBVAQCOAgAWAAgJ0yBVAQCOAgAAAA==.Wchinz:BAABLgAECn8WAAIeAAkJbiCPDgCaAgAeAAkJbiCPDgCaAgAAAA==.',
We='Wedlock:BAAALgAECgMJBAAAAA==.Welcumshot:BAABLgAFFH8OAAIpAAMJsRXZGgDmAAApAAMJsRXZGgDmAAAAAA==.Wenkar:BAAALgAECgUJDAABLgAECgkJUQASAOEdAA==.',
Wh='Whaka:BAAALgAECgIJAgABLgAFFAUJDgAiADUMAA==.',
Wi='Wid:BAAALgAECgkJBQAAAA==.Windsabre:BAAALgADCgIJAgAAAA==.Wingz:BAAALgAFFAEJAgAAAA==.',
Wo='Woregeonnick:BAABLgAECn8fAAITAAcJVxEhZwCWAQATAAcJVxEhZwCWAQAAAA==.Woshiren:BAAALgAECgYJBgAAAA==.Wozzie:BAAALgADCggJCAAAAA==.',
Wr='Wrane:BAAALgAECgEJAQAAAA==.',
Wy='Wyvern:BAAALgAECgcJEAAAAA==.',
['Wä']='Wärrior:BAAALgADCgMJAwAAAA==.',
Xa='Xanadu:BAAALgADCgIJAgAAAA==.',
Xd='Xd:BAAALgAFFAEJAQAAAA==.',
Xe='Xerxexy:BAAALgAECgQJCwAAAA==.',
Xi='Xiaodingdang:BAAALgAECgQJBAAAAA==.Xiera:BAABLgAECn8dAAIPAAkJTRDsTADuAQAPAAkJTRDsTADuAQAAAA==.',
Ya='Yaminosaishi:BAAALgAECgYJBwAAAA==.Yaoyôrozu:BAAALgADCgkJFAAAAA==.Yasuô:BAAALgADCgMJAwAAAA==.Yatelega:BAAALgADCgIJAgABLgAECgcJHwATAFcRAA==.Yazdorzarn:BAAALgAECgcJDAAAAA==.',
Yo='Yozzan:BAAALgAECgIJAgAAAA==.Yozzao:BAAALgAECgQJDAAAAA==.',
Yu='Yueli:BAAALgAFFAEJAQABLgAFFAgJGAAJAP4YAA==.',
Za='Zaaniz:BAABLgAECn8lAAQZAAkJ8BtvHwCvAgAZAAkJ8BtvHwCvAgAHAAQJgwndWgC+AAAfAAIJ+Q03PQBdAAAAAA==.',
Ze='Zenestra:BAAALgAECgkJAQABLgAFFAMJBAAQAAAAAA==.Zenshui:BAAALgAECgYJCQAAAA==.Zephyruss:BAAALgADCgEJAQAAAA==.Zervis:BAAALgAECgIJAgAAAA==.Zeyra:BAAALgAECgYJDAAAAA==.',
Zi='Zinako:BAAALgAECgEJAQAAAA==.',
Zo='Zocalo:BAAALgAECgUJBQAAAA==.',
['Èa']='Èasymode:BAAALgADCgEJAQAAAA==.',
['Ód']='Ódyssey:BAABLgAECn8ZAAIYAAgJCRLgDwCmAQAYAAgJCRLgDwCmAQAAAA==.',
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
