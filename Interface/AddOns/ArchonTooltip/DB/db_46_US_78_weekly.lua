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

local lookup = {'Rogue-Subtlety','Priest-Holy','Priest-Discipline','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','DemonHunter-Havoc','Paladin-Holy','Druid-Feral','Druid-Balance','Druid-Restoration','DeathKnight-Unholy','DeathKnight-Blood','DemonHunter-Vengeance','Mage-Frost','Unknown-Unknown','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Hunter-BeastMastery','Mage-Arcane','Hunter-Survival','Shaman-Restoration','Shaman-Enhancement','Paladin-Retribution','Rogue-Assassination','Warrior-Protection','Evoker-Devastation','DemonHunter-Devourer','Priest-Shadow','Paladin-Protection','Shaman-Elemental','Evoker-Augmentation','Evoker-Preservation','Druid-Guardian','Mage-Fire','DeathKnight-Frost','Warrior-Fury','Rogue-Outlaw','Warrior-Arms',}
local provider = {region='US',realm='Dreadmaul',name='US',type='weekly',zone=46,date='2026-07-05',data={Ab='Abbathdoom:BAABLgAECn8bAAIBAAkJlQ7pHwCWAQABAAkJlQ7pHwCWAQAAAA==.Abyss:BAAALgAECgEJAQAAAA==.',
Ae='Aedaris:BAABLgAECn9XAAMCAAkJPCCIEABjAgACAAcJDiGIEABjAgADAAYJHhk6KwB8AQAAAA==.Ael:BAAALgAECgEJAQAAAA==.Aethalides:BAAALgAECgYJDwAAAA==.',
Al='Alandrias:BAAALgAECgkJAQAAAA==.Alf:BAAALgAECgEJAQAAAA==.Alithial:BAAALgAECgEJAgAAAA==.Aloremirin:BAAALgADCgUJBQAAAA==.Altaria:BAABLgAFFH8mAAQEAAgJgSInAQABAgAEAAgJgSInAQABAgAFAAUJKR3eHgA1AQAGAAEJZwnXXwBBAAABLgAFFAkJTAAHAK4lAA==.Alvv:BAAALgADCgMJBQAAAA==.Alvz:BAAALgADCgMJAwAAAA==.',
Am='Ametrigos:BAAALgAECgEJAwABLgAECgkJJAAIAAggAA==.',
An='Anouke:BAAALgADCgIJAgAAAA==.Anserion:BAAALgADCgMJAwAAAA==.Anvious:BAAALgAECgcJDAAAAA==.',
Aq='Aquilea:BAABLgAECn8fAAMJAAkJJBJLDgDRAQAJAAkJJBJLDgDRAQAKAAEJhgaLmwAmAAAAAA==.',
Ar='Arcfuldodger:BAAALgAECgEJAgAAAA==.Artais:BAABLgAECn8gAAILAAgJ1Rx8FgCCAgALAAgJ1Rx8FgCCAgAAAA==.Artzlayer:BAACLgAFFH8JAAIMAAMJrxs/lADkAAAMAAMJrxs/lADkAAAuAAQKfzAAAwwACQlXI0wPAPICAAwACQlXI0wPAPICAA0AAQkAAFpwAAAAAAAA.Aríes:BAABLgAECn9RAAMHAAkJ3xqoDABbAgAHAAkJ3xqoDABbAgAOAAEJGAm7NgAsAAAAAA==.',
As='Ashbourne:BAAALgADCgcJCwAAAA==.',
Au='Autumnnight:BAAALgAECgEJBQAAAA==.',
Aw='Aw:BAAALgAECgYJEQABLgAFFAgJIwAPAHkYAA==.Awry:BAECLgAFFH8XAAIMAAUJYBkMGQBKAQAMAAUJYBkMGQBKAQAuAAQKfzcAAgwACQlkIssMAAYDAAwACQlkIssMAAYDAAAA.Awuuga:BAAALgAECgEJAQABLgAECgYJEgAQAAAAAA==.Aww:BAACLgAFFH8jAAIPAAgJeRiwHgAKAgAPAAgJeRiwHgAKAgAuAAQKfyAAAg8ACAljGwV/ANMBAA8ACAljGwV/ANMBAAAA.',
Az='Azamalaza:BAABLgAECn8nAAIRAAgJbyIUBgA4AgARAAgJbyIUBgA4AgAAAA==.Azmo:BAACLgAFFH8UAAQSAAYJ7hNeMwB5AQASAAYJAhJeMwB5AQATAAMJDRbtDADQAAAUAAEJ6xMEIQBPAAAuAAQKfyYAAxMACAkvIcECANYCABMACAmJHcECANYCABIABgk9HL1gAKcBAAAA.Azulon:BAAALgADCgUJBQABLgAECggJGgADAOkZAA==.Azyrt:BAAALgAECgQJBAABLgAECggJIAALANUcAA==.',
Ba='Badds:BAABLgAECn8UAAIIAAkJgRZNFABsAgAIAAkJgRZNFABsAgAAAA==.Ballona:BAAALgADCgUJBQAAAA==.Baløø:BAAALgAECgEJAQAAAA==.Barad:BAAALgAECgEJBAAAAA==.Batrick:BAAALgADCgcJBwAAAA==.Baulric:BAAALgAECgEJAQAAAA==.Bawls:BAABLgAFFH8HAAMFAAIJ7gauTQBrAAAFAAIJ7gauTQBrAAAEAAEJrAMWSQAuAAAAAA==.',
Be='Beastroll:BAABLgAECn8ZAAIVAAcJChWpXgCKAQAVAAcJChWpXgCKAQAAAA==.Beefrod:BAAALgADCgEJAQAAAA==.Beenis:BAAALgADCgUJBQABLgAFFAQJEQAMADEcAA==.Belerick:BAABLgAFFH8JAAIKAAMJnQqfDwDoAAAKAAMJnQqfDwDoAAAAAA==.Belphine:BAAALgAECgYJCAAAAA==.',
Bi='Bicksmage:BAACLgAFFH8SAAMPAAQJfRF4ZQAYAQAPAAQJXhF4ZQAYAQAWAAEJ9RaPAwBFAAAuAAQKfxYAAw8ACAnyFyFqAKcBAA8ACAnyFyFqAKcBABYAAQmLBysgAC8AAAAA.Bigdaddylock:BAACLgAFFH8bAAQSAAcJBx2kKQCgAQASAAYJOBukKQCgAQAUAAIJ+CMyFQBpAAATAAEJGBwwHABaAAAuAAQKfyUAAxMACQnoJE4IAD4CABIACAkzI6IuAFICABMABgm1Ik4IAD4CAAAA.Biluman:BAAALgAECgQJBAAAAA==.Biodeath:BAAALgADCgUJBQAAAA==.Biopally:BAAALgADCgYJDQAAAA==.Biorogue:BAAALgADCgYJDAAAAA==.Bishope:BAABLgAECn8aAAIDAAgJ6Rk0EABuAgADAAgJ6Rk0EABuAgAAAA==.',
Bl='Bllizard:BAAALgAECgEJAQAAAA==.Bloodache:BAAALgADCgcJDgABLgAECgUJGQAMAA4SAA==.Bluecar:BAAALgAECgYJCAAAAA==.',
Bo='Bohica:BAAALgAECgIJBQAAAA==.Bombdiggity:BAABLgAECn9AAAIDAAkJZh07BwAIAwADAAkJZh07BwAIAwAAAA==.Bonnierot:BAAALgAECgUJCgAAAA==.Boyscout:BAAALgAECgEJAQABLgAECggJCwAQAAAAAA==.',
Br='Brecciana:BAAALgADCgUJBQAAAA==.Brewjitsu:BAABLgAECn9IAAIFAAkJkR1xCQCbAgAFAAkJkR1xCQCbAgAAAA==.Brick:BAACLgAFFH8JAAMFAAMJeSGVJQATAQAFAAMJeSGVJQATAQAGAAEJ9BXlYQA8AAAuAAQKfx8AAgUABwl6HuQaAC0CAAUABwl6HuQaAC0CAAEuAAUUCAknABIAyBsA.Brongakill:BAAALgADCgYJBgAAAA==.Bräinfreeze:BAAALgAECgkJBwAAAA==.',
Bu='Buffy:BAAALgAECgEJAgAAAA==.Bumble:BAAALgADCgYJBgABLgAFFAkJKAACAFcbAA==.Bundalock:BAAALgADCgYJEQAAAA==.',
Ca='Cakebringer:BAAALgAECgcJEwAAAA==.Caroshi:BAACLgAFFH8MAAIPAAQJawQzdgDvAAAPAAQJawQzdgDvAAAuAAQKfygAAg8ACQmzDXZkALUBAA8ACQmzDXZkALUBAAAA.',
Ce='Cell:BAAALgAECgUJCAABLgAECgkJIAAVAOMUAA==.Ceridwen:BAAALgADCgEJAQAAAA==.',
Ch='Chaingun:BAABLgAECn8VAAIXAAkJ8RAmAQD/AQAXAAkJ8RAmAQD/AQAAAA==.Charlotte:BAAALgAECgMJDAAAAA==.Cheto:BAABLgAFFH8HAAIMAAIJzhP32QCIAAAMAAIJzhP32QCIAAABLgAFFAgJFAAYANcXAA==.Chosen:BAAALgAECgEJAQAAAA==.Chud:BAAALgAECgUJBQABLgAFFAYJGQAZAHgjAA==.',
Ci='Cig:BAABLgAECn8YAAIaAAgJ/xB1hABmAQAaAAgJ/xB1hABmAQAAAA==.',
Cl='Clankychan:BAACLgAFFH8LAAIFAAMJTA0PPAC2AAAFAAMJTA0PPAC2AAAuAAQKfxgAAgUABwkMFe88AAgBAAUABwkMFe88AAgBAAAA.Cloneofmagic:BAAALgADCgcJBwAAAA==.',
Co='Combustanut:BAAALgAECgUJEAAAAA==.Comillmouth:BAABLgAECn8ZAAIDAAgJbxFnKQCIAQADAAgJbxFnKQCIAQAAAA==.Comillthroat:BAAALgAECgkJEQAAAA==.Cornflakez:BAAALgADCgMJAwAAAA==.Cos:BAABLgAECn82AAMBAAkJbxGuFwDdAQABAAkJbxGuFwDdAQAbAAMJOAXFFgCKAAAAAA==.',
Cr='Crocks:BAAALgAECgIJAgAAAA==.Crozier:BAAALgAECgIJBgAAAA==.Crusher:BAAALgAECgUJBgABLgAFFAgJFAAYANcXAA==.Cryptum:BAAALgAECgkJBAAAAA==.Cryten:BAAALgAECgIJAgAAAA==.',
Cu='Cub:BAAALgAECgEJAwAAAA==.Cultiran:BAAALgAECgQJBAABLgAFFAYJGQAZAHgjAA==.Curby:BAAALgAECgcJBwABLgAECgkJTgAcAJ4eAA==.',
['Cä']='Cäin:BAAALgAECgQJCAAAAA==.',
Da='Dabufart:BAAALgADCgEJAQAAAA==.Daerus:BAAALgAECgYJBQAAAA==.Dagwood:BAAALgAECgEJAQAAAA==.Damge:BAAALgAECgUJCgAAAA==.Damnnyou:BAAALgAECgcJCAABLgAECgkJIwAdAK0ZAA==.Danky:BAAALgAECgMJAwAAAA==.Danteh:BAABLgAFFH8IAAIeAAMJ3wdNbwCrAAAeAAMJ3wdNbwCrAAAAAA==.Darahug:BAAALgAECgYJBgAAAA==.Daraina:BAAALgADCgEJAQABLgADCgEJAQAQAAAAAA==.Darktalanus:BAAALgADCgQJBAAAAA==.Darrkton:BAAALgADCgEJAQAAAA==.Dathil:BAAALgAECgYJCQAAAA==.Davmonhunter:BAAALgADCgQJBAAAAA==.Davoodooman:BAAALgAECgYJCAABLgAFFAQJGgASAKMcAA==.',
De='Deadiemurphy:BAAALgADCgYJCQAAAA==.Deathshunter:BAABLgAECn8qAAMVAAkJXiWwAgBfAgAVAAkJXiWwAgBfAgARAAYJ+hkjOgB5AQABLgAFFAgJIQAMAIEiAA==.Deaththorn:BAAALgADCgEJAQAAAA==.Debsi:BAABLgAECn8nAAIcAAkJ+w7CFgCOAQAcAAkJ+w7CFgCOAQAAAA==.Declined:BAAALgAECgEJAQAAAA==.Deeper:BAABLgAFFH8NAAIYAAMJ3QewXwCMAAAYAAMJ3QewXwCMAAAAAA==.Deepest:BAABLgAFFH8HAAIbAAQJ0g9eBQAqAQAbAAQJ0g9eBQAqAQAAAA==.Deloraine:BAACLgAFFH8uAAIfAAcJjiSXAwBgAgAfAAcJjiSXAwBgAgAuAAQKfycAAh8ACQkAIs0FAPYCAB8ACQkAIs0FAPYCAAAA.Demonbick:BAAALgADCgMJAwAAAA==.Demonicfaith:BAABLgAECn82AAMHAAcJbxqFFwAMAgAHAAYJTx6FFwAMAgAeAAcJlQzbgAAoAQAAAA==.Denman:BAABLgAECn8YAAMaAAcJjBnRdgCNAQAaAAcJjBnRdgCNAQAgAAEJmAAmUAAKAAAAAA==.Dezarian:BAAALgAECggJCAAAAA==.',
Di='Dirtyfista:BAAALgAECgYJCgAAAA==.Dirtyfux:BAACLgAFFH8KAAIDAAMJ5RK2MgDCAAADAAMJ5RK2MgDCAAAuAAQKfxUAAwMABglsHJkrAHoBAAMABglsHJkrAHoBAAIAAQkZDweDAC4AAAAA.Dirtysham:BAACLgAFFH8PAAIYAAQJcRqpLwAjAQAYAAQJcRqpLwAjAQAuAAQKfzAAAxgACQm3H/0MALUCABgACAl1If0MALUCACEABAmHCuxnAK8AAAAA.Discipline:BAAALgADCgcJBwAAAA==.Disckin:BAAALgAECgEJBAAAAA==.Diseasemode:BAAALgAECgEJAgAAAA==.Divinechill:BAAALgAECgEJAQAAAA==.',
Dn='Dnb:BAAALgADCgEJAQABLgAFFAgJIwAPAHkYAA==.Dnk:BAAALgADCgMJAwAAAA==.',
Do='Dom:BAAALgADCgcJCQAAAA==.Donki:BAAALgAECgkJDAAAAA==.Doodtanky:BAAALgADCgEJAQAAAA==.Doomvedas:BAAALgAECgYJCgAAAA==.',
Dr='Dracaena:BAABLgAECn8jAAQdAAkJrRnuBgDZAQAiAAgJkBT/GwDoAQAdAAgJtBfuBgDZAQAjAAUJQwizMQDiAAAAAA==.Draco:BAAALgAECgMJAwAAAA==.Dreadknìght:BAAALgAFFAUJBAAAAA==.Drekavach:BAAALgADCgcJEwAAAA==.Droidbick:BAABLgAFFH8GAAILAAIJyApAXwBdAAALAAIJyApAXwBdAAAAAA==.Drtwnkletits:BAAALgAECgMJAwAAAA==.',
['Dâ']='Dâftmonk:BAAALgAECgQJBgABLgAECgkJDAAQAAAAAA==.',
Ee='Eevo:BAAALgAECgMJAwABLgAECggJFAAGAJEIAA==.',
El='Elaha:BAAALgAECgcJCQAAAA==.Elexann:BAAALgAECgkJAQAAAA==.Elibaba:BAABLgAFFH8GAAIPAAIJMh+HlACqAAAPAAIJMh+HlACqAAABLgAFFAIJDAAMAJ4aAA==.Elideady:BAABLgAFFH8MAAIMAAIJnhqEQwCiAAAMAAIJnhqEQwCiAAAAAA==.Elinaa:BAAALgAECgIJAgAAAA==.Elindyl:BAAALgADCgEJAQAAAA==.Elisaxy:BAAALgAECgEJAgAAAA==.Elleth:BAAALgADCgMJAwAAAA==.Elvishcheese:BAAALgAECgMJBgAAAA==.',
Em='Emojis:BAAALgAECgUJCgAAAA==.Emopapa:BAAALgAFFAEJAQABLgAFFAIJBAAQAAAAAA==.',
En='Endlessdh:BAACLgAFFH8IAAIHAAMJCiIKBwDIAAAHAAMJCiIKBwDIAAAuAAQKfx4AAgcABwkyJJUJAMgCAAcABwkyJJUJAMgCAAAA.',
Er='Eraserhead:BAAALgAECgYJEwABLgAFFAYJGQAZAHgjAA==.Eripaladin:BAAALgAECgUJBwAAAA==.Erissaria:BAAALgADCgEJAQAAAA==.Erwinnara:BAAALgAECgIJBAAAAA==.',
Ev='Evening:BAAALgAECggJCQAAAA==.Everbuddha:BAAALgAECgQJBgAAAA==.',
Ew='Ewa:BAAALgAECgMJBAAAAA==.Eww:BAABLgAECn8XAAIeAAcJyw9zdAA4AQAeAAcJyw9zdAA4AQAAAA==.',
Ez='Ezelia:BAACLgAFFH8cAAMaAAUJRBmoFAARAQAaAAUJRBmoFAARAQAIAAIJgghcPQBrAAAuAAQKfxoAAxoACQl+FmpIAO0BABoACQl+FmpIAO0BAAgAAQlGCVeVADUAAAEuAAUUCQk7AAIAfiEA.',
Fa='Faelune:BAABLgAECn8fAAIPAAkJ6wpHbQCgAQAPAAkJ6wpHbQCgAQAAAA==.Faldir:BAAALgADCgYJBAABLgAFFAYJIgAeANAfAA==.',
Fe='Ferndale:BAAALgAECgUJCgAAAA==.Ferndru:BAACLgAFFH8OAAMJAAQJQg3kAgD+AAAJAAQJQg3kAgD+AAAkAAIJMQdJMgBVAAAuAAQKfzEAAwkACQkBGdoIADwCAAkACAnYG9oIADwCACQABwlIFHADAEkBAAAA.',
Fi='Fisticuffs:BAACLgAFFH8VAAIGAAYJKhPsHwBvAQAGAAYJKhPsHwBvAQAuAAQKfysAAgYACQm4HNcPAKgCAAYACQm4HNcPAKgCAAAA.',
Fl='Flameshock:BAAALgAFFAIJBAAAAA==.Flowki:BAAALgADCgcJCwAAAA==.',
Fo='Forcespark:BAAALgAECgEJAQAAAA==.',
Fr='Fraserker:BAAALgAECgEJAQAAAA==.Frostradamus:BAAALgADCgkJCgAAAA==.',
Fu='Fullmoonride:BAABLgAECn8VAAIKAAYJrQZZCgCWAAAKAAYJrQZZCgCWAAAAAA==.Fumbll:BAAALgAECgkJCQAAAA==.Funkymajik:BAABLgAECn8fAAQDAAkJlg+WHgDaAQADAAkJlg+WHgDaAQACAAIJiAaJdQBTAAAfAAEJtQtOYgA0AAAAAA==.Furiosa:BAAALgADCgkJDgAAAA==.Furrballz:BAAALgAECgEJAQAAAA==.',
Ga='Gallywox:BAAALgADCgMJAwAAAA==.Ganin:BAABLgAECn8bAAIIAAYJUBU0QgBvAQAIAAYJUBU0QgBvAQAAAA==.Gankinyou:BAAALgADCgEJAQAAAA==.Gargish:BAAALgAECgkJCQABLgAFFAEJAQAQAAAAAA==.Garielyn:BAAALgADCgEJAQAAAA==.Garugala:BAACLgAFFH8OAAIaAAMJCRXybADWAAAaAAMJCRXybADWAAAuAAQKfysAAhoACQklGKc0AC4CABoACQklGKc0AC4CAAAA.',
Gb='Gbosch:BAAALgAECgYJCQAAAA==.',
Gd='Gdaycøb:BAAALgADCgYJBwAAAA==.',
Ge='Gengár:BAAALgAECgMJBgABLgAFFAEJAQAQAAAAAA==.',
Gh='Ghalorin:BAABLgAECn8gAAIVAAgJaRh8PQDrAQAVAAgJaRh8PQDrAQAAAA==.Ghiroza:BAABLgAECn9UAAQTAAkJWR7fCAAzAgASAAkJ3B1PJQBJAgATAAgJihbfCAAzAgAUAAQJIxnJEwAzAQAAAA==.',
Gi='Giga:BAAALgAECgEJAQABLgAECgkJVAATAFkeAA==.Gigaevoker:BAABLgAECn8kAAIjAAgJcRa4DAAIAgAjAAgJcRa4DAAIAgAAAA==.Gigapaladin:BAAALgADCgQJBAAAAA==.Gingarthas:BAABLgAECn8iAAIMAAkJPh01KwCMAgAMAAkJPh01KwCMAgAAAA==.',
Gl='Glowingtoe:BAAALgAECgMJBQAAAA==.',
Go='Gobgob:BAAALgAECgMJAwAAAA==.Gogmazios:BAAALgADCgcJBwAAAA==.',
Gr='Gravytate:BAABLgAECn9XAAIhAAkJfA8bLwCFAQAhAAkJfA8bLwCFAQAAAA==.Griinn:BAABLgAECn8hAAIkAAkJow9IHQBjAQAkAAkJow9IHQBjAQAAAA==.Grimefiend:BAAALgAFFAIJBAAAAA==.Grimescene:BAAALgAECgIJAgABLgAFFAIJBAAQAAAAAA==.Grimreapêr:BAAALgAECgEJBQAAAA==.Grow:BAAALgAFFAEJAwAAAA==.',
Gu='Guldannyboy:BAABLgAECn80AAMTAAkJSw3lDQBeAQATAAkJygzlDQBeAQASAAkJFwfJdQBOAQAAAA==.Gumbö:BAAALgAECgcJCQABLgAECggJIAALANUcAA==.Gutted:BAAALgADCgIJAgAAAA==.',
Ha='Haides:BAAALgAECgUJBwAAAA==.Hammer:BAAALgAECgIJAgABLgAECgkJDAAQAAAAAA==.Hanokano:BAAALgAECggJDQABLgAFFAQJGgASAKMcAA==.Hantore:BAAALgADCgMJAwAAAA==.Harmony:BAAALgAECgEJAQAAAA==.Harry:BAACLgAFFH8IAAIZAAMJohfUDgDTAAAZAAMJohfUDgDTAAAuAAQKfycAAxkACQljJOUBAD8DABkACQljJOUBAD8DABgABwnEGuMgABoCAAAA.',
He='Heartdh:BAABLgAECn8VAAMeAAgJkhLHUwCLAQAeAAgJkhLHUwCLAQAHAAIJrxOGWwByAAAAAA==.Heisenbergg:BAAALgADCgIJAgAAAA==.Hellza:BAAALgAECgMJAwAAAA==.Hen:BAAALgAECgUJBQABLgAECgYJFQANABAVAA==.Herpyprotect:BAAALgAFFAIJAwAAAA==.Herrion:BAACLgAFFH8nAAQSAAgJyBvmFgAIAgASAAcJjBvmFgAIAgATAAEJKx3pGwBbAAAUAAEJyB/ZGgBXAAAuAAQKfy4AAxIACQn/IvkcAKgCABIACAn/IvkcAKgCABMABAmcJNMUAKQBAAAA.',
Hh='Hh:BAAALgAECgEJAQAAAA==.',
Hi='Hippy:BAAALgAFFAEJAQABLgAFFAcJEAAiAFQSAA==.',
Ho='Hobbitxp:BAAALgAECgEJAwAAAA==.Holyisdrunk:BAAALgAECgEJAQAAAA==.Holytanky:BAAALgAECgcJCgAAAA==.Hotspur:BAABLgAECn84AAILAAgJaxDUOADDAQALAAgJaxDUOADDAQAAAA==.',
Hu='Hukani:BAAALgAECgEJAwABLgAECggJFgACALEIAA==.Hunner:BAAALgAECgIJAgABLgAECggJFAAGAJEIAA==.Huskar:BAABLgAECn8gAAIVAAkJ4xQdMAAcAgAVAAkJ4xQdMAAcAgAAAA==.',
Hy='Hypoxi:BAAALgADCgYJCQAAAA==.',
Ig='Ignis:BAABLgAECn8cAAIlAAkJmR3lAQBmAgAlAAkJmR3lAQBmAgAAAA==.Ignitor:BAAALgADCgEJAQAAAA==.',
Ik='Ikari:BAABLgAECn9YAAITAAkJyhpdBQCBAgATAAkJyhpdBQCBAgAAAA==.',
Il='Illadoss:BAAALgADCgIJAgAAAA==.',
Im='Imntprepared:BAAALgAFFAEJAgAAAA==.',
In='Incarnate:BAAALgAECgEJAgAAAA==.Incubis:BAAALgADCgIJAgAAAA==.Infectîon:BAABLgAECn8hAAQSAAkJmxeGAwDKAQASAAgJ7hCGAwDKAQATAAgJWBi5GQDWAAAUAAIJ5QqvPAA5AAAAAA==.Inferlock:BAAALgAECgMJAwAAAA==.Infernyos:BAAALgAECgYJBgAAAA==.Infernyoz:BAAALgADCggJCQAAAA==.Iniquity:BAAALgAECgEJAgAAAA==.',
Ir='Irithel:BAAALgAECgcJBQAAAA==.',
Is='Isohexene:BAAALgADCgYJBgAAAA==.',
It='Itchygrowth:BAAALgAFFAEJAQAAAA==.',
Iu='Iucifer:BAAALgAECgEJAgAAAA==.',
Iv='Ivygambina:BAAALgADCgYJBgAAAA==.Ivysore:BAAALgAECgUJBwAAAA==.',
Ja='Jasha:BAAALgADCgcJCwAAAA==.Jayvarmani:BAAALgAECgMJAwAAAA==.Jayy:BAABLgAECn8bAAIMAAkJBRCKTAANAgAMAAkJBRCKTAANAgAAAA==.',
Je='Jennatalia:BAAALgAECggJEgABLgAFFAEJAQAQAAAAAA==.',
Ji='Jinkazamaz:BAAALgAFFAIJBAAAAA==.',
Jo='Joelsdruid:BAABLgAFFH8gAAIkAAYJlhvsBQCcAQAkAAYJlhvsBQCcAQAAAA==.Joelvoker:BAAALgAFFAIJAgABLgAFFAYJIAAkAJYbAA==.Joexotic:BAAALgAECgIJBwAAAA==.Jongwang:BAAALgAECgQJBwAAAA==.',
Ju='Jubjub:BAAALgAECgEJAgAAAA==.',
Ka='Kaaru:BAACLgAFFH8KAAIDAAQJVQvqKgD5AAADAAQJVQvqKgD5AAAuAAQKfycAAwMACQnPF5cYAA8CAAMACQm8FpcYAA8CAAIABQkTEoZIABcBAAAA.Kaelom:BAAALgAECgQJBgAAAA==.Kahai:BAAALgAECgIJAwAAAA==.Kaiforst:BAAALgAECgQJBQABLgAECgkJOQAaAOEaAA==.Kaihavocz:BAAALgAECgEJAwAAAA==.Kairon:BAABLgAECn85AAIaAAkJ4RrjLABNAgAaAAkJ4RrjLABNAgAAAA==.Kalysae:BAAALgADCgEJAQAAAA==.Kania:BAAALgAECgIJAgABLgAECgkJMQAYAMQiAA==.Katarinabluu:BAAALgAECgYJBgAAAA==.Kazakhthundr:BAAALgADCgYJBgAAAA==.',
Ke='Keeanuleaves:BAAALgADCgYJBwAAAA==.Keeanuweaves:BAAALgADCgEJAQAAAA==.Keeze:BAACLgAFFH8QAAIPAAQJbQkCcAABAQAPAAQJbQkCcAABAQAuAAQKfxgAAg8ACQkaEx9YANUBAA8ACQkaEx9YANUBAAAA.',
Ki='Kickstarter:BAAALgAECgYJEgAAAA==.Kiel:BAAALgAECgEJAQAAAA==.Kikiz:BAAALgAECgYJDgAAAA==.Kill:BAAALgAFFAIJAgAAAA==.Killania:BAAALgADCgMJAwAAAA==.Kiwichaos:BAACLgAFFH8PAAMeAAUJKwuHIQDKAAAeAAUJxweHIQDKAAAHAAQJnQkLHwCoAAAuAAQKfy8AAwcACQlbG6QMAJcCAAcACQlbG6QMAJcCAB4AAQkAAAAAAAAAAAAA.',
Kn='Knox:BAAALgAECgUJCgAAAA==.Knull:BAAALgAECgIJBgAAAA==.',
Ko='Korner:BAAALgAECgIJAgAAAA==.',
Kr='Krazzul:BAAALgAECgQJBAAAAA==.Krellis:BAACLgAFFH8KAAIEAAQJzBfIBAAhAQAEAAQJzBfIBAAhAQAuAAQKfxsAAwQACQljGj4QAEkCAAQACQljGj4QAEkCAAYABgm1EDwxADMBAAAA.Kritikall:BAAALgADCgUJBQAAAA==.',
Ku='Kurozuka:BAAALgAECgQJBAAAAA==.Kurö:BAAALgAECgEJAQAAAA==.Kuura:BAAALgAECgEJAQABLgAFFAQJCgADAFULAA==.',
Kv='Kvôthe:BAABLgAECn8dAAMMAAkJPgyWawCOAQAMAAkJCguWawCOAQAmAAMJzQe7KgB/AAAAAA==.',
Ky='Kynnareth:BAAALgAFFAIJBAABLgAFFAYJFQAIAIoPAA==.Kynralol:BAABLgAECn9tAAIPAAkJyiKNAQD3AgAPAAkJyiKNAQD3AgAAAA==.Kyujín:BAAALgAECgIJAgAAAA==.Kyunsun:BAAALgAECgYJCAAAAA==.',
['Ká']='Káiser:BAAALgAECggJEQAAAA==.',
La='Laenosh:BAABLgAECn8ZAAIMAAUJDhLw1wDeAAAMAAUJDhLw1wDeAAAAAA==.Lagalot:BAAALgAECgEJAQAAAA==.Laomoo:BAAALgAECgcJDgAAAA==.Lasciel:BAAALgAECgEJAQAAAA==.Laz:BAAALgADCgMJBQAAAA==.',
Le='Learning:BAABLgAECn8XAAIhAAcJEh9LGwA4AgAhAAcJEh9LGwA4AgAAAA==.Legham:BAAALgADCgkJDgAAAA==.Legolazz:BAABLgAECn8yAAMVAAkJ4B7RGgCEAgAVAAkJ4B7RGgCEAgARAAMJCBTiKQBuAAAAAA==.Lemins:BAAALgAECgMJAwAAAA==.Lemondruid:BAAALgAECgIJAgAAAA==.Lemonmelon:BAAALgAECgYJEwAAAA==.Lenatheplug:BAACLgAFFH8gAAMBAAgJjxcMAwDMAQABAAcJLRsMAwDMAQAbAAIJjQnKBQBgAAAuAAQKfyIAAwEACAmUJEQKAO0CAAEACAnbI0QKAO0CABsABwlAIt4DAIACAAAA.Lerust:BAAALgADCgcJBwAAAA==.',
Li='Liadrine:BAACLgAFFH8FAAIaAAQJdAzwVAAGAQAaAAQJdAzwVAAGAQAuAAQKfzAAAhoACQnjF5NJAOkBABoACQnjF5NJAOkBAAAA.Lind:BAAALgAECgYJBgABLgAFFAMJBgAXAPgXAA==.Linus:BAAALgAECgYJBgABLgAFFAgJJwASAMgbAA==.Littleriver:BAABLgAECn8ZAAIVAAgJ2hirNgDUAQAVAAgJ2hirNgDUAQAAAA==.',
Ll='Llewser:BAABLgAECn8aAAMPAAgJwhWpUADqAQAPAAgJwhWpUADqAQAlAAEJqgSBFQAqAAAAAA==.',
Lo='Loathe:BAAALgAFFAEJAQAAAA==.Loc:BAAALgAECgcJCwABLgAECggJFAAGAJEIAA==.Loistiah:BAABLgAFFH8IAAIMAAMJZhm9mADdAAAMAAMJZhm9mADdAAAAAA==.Lothaof:BAABLgAECn8sAAIaAAkJ6RKXXAC5AQAaAAkJ6RKXXAC5AQAAAA==.Louisvuitton:BAAALgAECgUJDwAAAA==.',
Lp='Lpayn:BAAALgADCgEJAQAAAA==.',
Lu='Lugroth:BAABLgAFFH8FAAMkAAMJWhYPGADFAAAkAAMJWhYPGADFAAALAAEJIxGJcAA2AAABLgAFFAgJJwASAMgbAA==.Lunae:BAAALgADCgIJAgAAAA==.Lunana:BAAALgAECgcJEgAAAA==.',
Ly='Lychiee:BAAALgAECgcJEQAAAA==.',
['Lì']='Lìnkinbark:BAAALgAECgMJAwAAAA==.',
Ma='Madara:BAAALgAECgEJAgAAAA==.Magesorry:BAAALgADCgUJBQAAAA==.Maggot:BAAALgAECgQJBQAAAA==.Magicmon:BAAALgAECgQJBAAAAA==.Maize:BAABLgAECn8iAAMDAAgJMBt0EwBFAgADAAgJMBt0EwBFAgACAAMJhgvTZwCOAAAAAA==.Makima:BAABLgAFFH8FAAIKAAUJmQ4KLgDPAAAKAAUJmQ4KLgDPAAABLgAFFAYJGQAGAEYYAA==.Malikai:BAAALgADCgcJDAAAAA==.Malxsvoker:BAAALgAFFAIJAgABLgAFFAgJGwAhADUSAA==.Marcymonk:BAAALgADCgEJAQAAAA==.Marcyon:BAABLgAECn8bAAIeAAcJDAlCoADiAAAeAAcJDAlCoADiAAAAAA==.Marywinston:BAAALgAFFAEJAQABLgAFFAIJBgANAFMUAA==.Maybeadragon:BAAALgAECgUJBQAAAA==.',
Mc='Mchèalz:BAABLgAECn8VAAQDAAgJRAhJPQAYAQADAAgJRAhJPQAYAQACAAQJxAFFaQCIAAAfAAIJOwF0ZgAsAAAAAA==.',
Me='Melodysseý:BAAALgAECgUJBQAAAA==.Melonlemonza:BAAALgADCgQJBAAAAA==.Mentok:BAAALgAECgYJCwAAAA==.Merchei:BAAALgAECgUJBgAAAA==.Meruen:BAACLgAFFH8IAAIeAAQJlBOpRwARAQAeAAQJlBOpRwARAQAuAAQKfzoAAx4ACQniG28YAIMCAB4ACQniG28YAIMCAA4AAwm2ApYrAFQAAAAA.',
Mi='Miidorii:BAAALgAECgEJAQABLgAECgUJCQAQAAAAAA==.Mik:BAAALgAECgcJBwABLgAFFAYJIgAeANAfAA==.Miralisa:BAABLgAFFH8HAAIaAAIJ2AVOOAB2AAAaAAIJ2AVOOAB2AAAAAA==.Miss:BAAALgAECgMJAwAAAA==.Mistie:BAAALgAECgEJAQABLgAFFAMJBQALAAoYAA==.Mitymorphin:BAAALgADCgEJAQAAAA==.',
Mo='Mobility:BAAALgAFFAEJAQAAAA==.Moistpole:BAAALgADCgQJBAAAAA==.Momock:BAAALgAECgQJBAAAAA==.Mongk:BAABLgAECn8UAAIGAAgJkQibNQAZAQAGAAgJkQibNQAZAQAAAA==.Monkagè:BAAALgAECgQJBAAAAA==.Monscustodes:BAABLgAECn8kAAIPAAkJWA/aYQC8AQAPAAkJWA/aYQC8AQAAAA==.Monstersauce:BAAALgAFFAIJBAAAAA==.Mookin:BAAALgAFFAEJAQAAAA==.Moospoon:BAABLgAECn9OAAIaAAkJ/BgrBAD0AQAaAAkJ/BgrBAD0AQAAAA==.Mooudini:BAAALgAECgMJAwAAAA==.Moounka:BAABLgAECn9MAAIFAAkJsRWNEwAUAgAFAAkJsRWNEwAUAgAAAA==.Morphio:BAACLgAFFH8HAAIVAAMJSRnvLgCtAAAVAAMJSRnvLgCtAAAuAAQKf0sAAxUACQkvJVsDAFsDABUACQkvJVsDAFsDABEABQkLE5pMAB8BAAAA.Mostakrakish:BAAALgADCgEJAQAAAA==.',
Mu='Muddles:BAABLgAECn9EAAIFAAkJUBjrEQAoAgAFAAkJUBjrEQAoAgAAAA==.Murius:BAACLgAFFH8KAAIMAAMJkQSruwCxAAAMAAMJkQSruwCxAAAuAAQKfzIAAgwACQlEF/E2ACMCAAwACQlEF/E2ACMCAAAA.',
My='Mysterio:BAAALgAFFAEJBAAAAA==.',
Na='Naendria:BAAALgAECgMJBAAAAA==.Naga:BAAALgAECgIJAgAAAA==.Nahaza:BAAALgAECgEJAgAAAA==.Naidos:BAAALgAECgEJAQAAAA==.',
Ne='Nelena:BAAALgAECgIJAgAAAA==.',
Ni='Nickdoom:BAAALgAFFAEJAQAAAA==.Nigella:BAABLgAECn8WAAMCAAgJsQjSOwAGAQACAAgJsQjSOwAGAQADAAEJ6wF/iQAgAAAAAA==.Nikola:BAACLgAFFH8HAAQLAAIJzw/XUgB5AAALAAIJzw/XUgB5AAAKAAEJ3QdGUQA0AAAkAAEJaAOQKAAkAAAuAAQKfyoABAsACQmjFWc3AMoBAAsACQmjFWc3AMoBACQABQk4Ft8VABQBAAoABAl9D39UANQAAAAA.Nimro:BAACLgAFFH8cAAIcAAcJqRWQCACsAQAcAAcJqRWQCACsAQAuAAQKfygAAhwACQmPH6ADABsDABwACQmPH6ADABsDAAAA.Nirela:BAAALgAECgEJAQAAAA==.Niub:BAABLgAECn8rAAInAAkJ9hOrIADrAQAnAAkJ9hOrIADrAQAAAA==.',
No='Nofate:BAAALgADCgEJAQAAAA==.Noirebringer:BAAALgAFFAEJAQAAAA==.Nongbonnie:BAAALgAECgIJAgAAAA==.Nongkiwi:BAAALgAECggJCwAAAA==.',
Nt='Ntrldrake:BAAALgADCgEJAgABLgAECgkJJAAPAFgPAA==.',
Nu='Nueng:BAAALgAECgEJAgAAAA==.Nuferax:BAABLgAECn8fAAIOAAkJXyH6AQDzAgAOAAkJXyH6AQDzAgAAAA==.Nuiiwarx:BAAALgAECgEJBQAAAA==.Nulledhacz:BAAALgAECgUJAwAAAA==.Numbrethree:BAACLgAFFH8ZAAIGAAUJ8xW1DQBDAQAGAAUJ8xW1DQBDAQAuAAQKf0wAAwYACQnFG4IOALcCAAYACQnFG4IOALcCAAQAAglDBnG1ACIAAAAA.',
Ob='Obbi:BAACLgAFFH8eAAIbAAQJ0yaDAQDNAQAbAAQJ0yaDAQDNAQAuAAQKfxoAAxsACQkpIFIBAAMDABsACQkpIFIBAAMDACgAAQk/JJQcAGcAAAAA.',
Oh='Ohaither:BAAALgAECgQJBAAAAA==.',
Oi='Oirth:BAAALgADCgIJAgAAAA==.',
Ok='Okiji:BAAALgAECgkJEwAAAA==.',
Om='Ominae:BAAALgAECgEJAQAAAA==.Ominaeohm:BAAALgAECgEJAQAAAA==.',
Or='Orinocco:BAAALgAECgEJAwAAAA==.Orobas:BAABLgAFFH8IAAIgAAQJQg6ZBACeAAAgAAQJQg6ZBACeAAAAAA==.',
Pa='Pakaww:BAAALgAECgIJAwAAAA==.Palimathrus:BAAALgAECgUJCAAAAA==.Palliative:BAABLgAECn9IAAMIAAkJQCLYBgAeAwAIAAkJQCLYBgAeAwAaAAQJLwV6GwGZAAAAAA==.Pallidnim:BAABLgAFFH8MAAINAAUJjRKNHwDrAAANAAUJjRKNHwDrAAAAAA==.Papager:BAABLgAFFH8IAAISAAMJvAYThwC3AAASAAMJvAYThwC3AAAAAA==.',
Pe='Pea:BAAALgAECgcJEAAAAA==.Perish:BAAALgAECggJDQABLgAECgkJRAAFAFAYAA==.',
Ph='Phatmonk:BAACLgAFFH8hAAMEAAcJyySbBQDBAQAEAAcJyySbBQDBAQAGAAIJyATKWABQAAAuAAQKf0cAAwQACQmxJn4AAIYDAAQACQmxJn4AAIYDAAYABwntIJ0RAJICAAAA.Phatrogue:BAABLgAFFH8KAAIBAAMJjB3pIwAFAQABAAMJjB3pIwAFAQABLgAFFAcJIQAEAMskAA==.',
Pi='Piewpiew:BAAALgADCgcJCgAAAA==.Pitcrewboys:BAAALgAECgEJAQAAAA==.Pix:BAACLgAFFH8cAAMfAAcJZR3XAgDHAQAfAAcJZR3XAgDHAQADAAUJvQwYIQBHAQAuAAQKfzYAAh8ACQk5JTYCAEoDAB8ACQk5JTYCAEoDAAAA.',
Pl='Pleasuremax:BAACLgAFFH8NAAIVAAQJ4RUtMQBNAQAVAAQJ4RUtMQBNAQAuAAQKfxoAAhUACAksFW1GAM4BABUACAksFW1GAM4BAAAA.Plex:BAABLgAECn8/AAIJAAkJRRpaBwBlAgAJAAkJRRpaBwBlAgAAAA==.',
Po='Poofyfeesh:BAAALgAFFAIJAwAAAA==.Poogie:BAAALgADCgYJBgABLgAECgMJBQAQAAAAAA==.Popshot:BAABLgAECn8eAAIRAAYJ5xIiRQBBAQARAAYJ5xIiRQBBAQAAAA==.Portalhouse:BAAALgAECgEJAQAAAA==.',
Pr='Praxis:BAACLgAFFH8VAAMcAAQJqBWnCQDJAAAcAAQJqBWnCQDJAAAnAAIJMAJMIgBUAAAuAAQKfzYAAxwACQmWGQoVAKIBABwACQn6GAoVAKIBACkABglRFwQgAF4BAAAA.Preast:BAAALgAECgcJBwABLgAECggJFAAGAJEIAA==.Procist:BAABLgAECn8ZAAMCAAkJBxd8EABjAgACAAkJBxd8EABjAgAfAAEJpQeFkQApAAABLgAECgkJMQAYAMQiAA==.',
Py='Pyrusdk:BAABLgAECn8ZAAIMAAkJgQ6NYACoAQAMAAkJgQ6NYACoAQAAAA==.Pyrusdruid:BAABLgAECn8WAAILAAkJJwIlnQB2AAALAAkJJwIlnQB2AAAAAA==.',
Qo='Qop:BAAALgAFFAEJAgAAAA==.',
Qu='Quesarah:BAAALgADCgEJAQABLgAECgQJBAAQAAAAAA==.',
Qw='Qweffor:BAAALgAECgUJBQABLgAFFAIJBQAMAPcOAA==.',
Ra='Rainbowkelly:BAAALgAECgQJBAAAAA==.Raisha:BAAALgADCgEJAQAAAA==.Raìn:BAACLgAFFH8HAAIMAAMJmAxsrQDGAAAMAAMJmAxsrQDGAAAuAAQKfxQAAgwACAnYFcpRAM4BAAwACAnYFcpRAM4BAAAA.',
Re='Recruitqt:BAACLgAFFH8JAAMaAAIJDg1JkgCOAAAaAAIJDg1JkgCOAAAIAAIJbBDuEwBzAAAuAAQKfyAAAwgABQlNGw86AJEBAAgABQlNGw86AJEBABoABAkTETjXAOkAAAAA.References:BAAALgAECgIJAgAAAA==.Reiayanami:BAABLgAECn8fAAIPAAgJfA+3gQB0AQAPAAgJfA+3gQB0AQAAAA==.',
Ri='Ripandtear:BAABLgAECn8gAAMLAAkJZRdoKQAIAgALAAkJZRdoKQAIAgAJAAEJFQZ6NgAsAAAAAA==.',
Ro='Roguewan:BAAALgAFFAIJAgAAAA==.Rolâyne:BAAALgADCgkJDgAAAA==.Roninn:BAACLgAFFH8UAAILAAQJ5RldJQAwAQALAAQJ5RldJQAwAQAuAAQKfzQAAgsACQlVIawFAF0DAAsACQlVIawFAF0DAAAA.Ronlock:BAABLgAECn8VAAMSAAYJ8xD9nQAdAQASAAUJ8xD9nQAdAQATAAEJAAABagA+AAABLgAECgcJNgAHAG8aAA==.Royaltits:BAAALgADCgIJAgAAAA==.',
Rs='Rsi:BAAALgAECgQJBAAAAA==.',
Ry='Rynaea:BAAALgAECgkJEQAAAA==.',
['Rï']='Rïmuru:BAAALgADCgcJCwAAAA==.',
['Rô']='Rôlayne:BAABLgAECn8ZAAInAAgJdQu+QwA2AQAnAAgJdQu+QwA2AQAAAA==.',
['Rö']='Rölayne:BAAALgAECggJBwAAAA==.',
Sa='Sadakos:BAAALgAFFAMJBAAAAA==.Salvare:BAABLgAECn8lAAMbAAkJhhhwAwCVAgAbAAkJfRhwAwCVAgAoAAIJRRCkGwBvAAAAAA==.Sappy:BAAALgAECgQJBAAAAA==.Sarielsiá:BAAALgAFFAEJAQAAAA==.Sauron:BAAALgADCgEJAQABLgAFFAQJFAASAPYUAA==.',
Sb='Sbf:BAABLgAFFH8ZAAIiAAcJ4RbvEQDtAQAiAAcJ4RbvEQDtAQABLgAFFAkJVQAeALMjAA==.',
Sc='Scalamander:BAAALgAECgcJAgAAAA==.Sciohunter:BAABLgAFFH8FAAIHAAIJIAysJQB5AAAHAAIJIAysJQB5AAAAAA==.Scioscioz:BAACLgAFFH8OAAILAAQJ0BDkLwDyAAALAAQJ0BDkLwDyAAAuAAQKfyAAAwsABwnOFOI7ALUBAAsABwnOFOI7ALUBAAoAAglnEAJsAHAAAAAA.Scwisgar:BAAALgAECgkJDQAAAA==.',
Se='Sedge:BAAALgAFFAIJBAAAAA==.Sephire:BAABLgAECn8eAAIaAAkJPARszAD4AAAaAAkJPARszAD4AAAAAA==.Sermazule:BAAALgADCgcJEQAAAA==.Sewerface:BAABLgAECn8VAAMNAAYJEBWaHgBTAQANAAYJEBWaHgBTAQAMAAMJLAScAQF2AAAAAA==.',
Sh='Shadonir:BAAALgAECgQJBAAAAA==.Shadowind:BAACLgAFFH8rAAIVAAUJKh+GEwA7AQAVAAUJKh+GEwA7AQAuAAQKfy8AAxEACQmGHn4dADsCABEACAlEGX4dADsCABUABQlkHUVhAIQBAAAA.Shadowz:BAAALgAECgEJAgAAAA==.Shaft:BAAALgAECgEJAQAAAA==.Shallotte:BAABLgAECn8YAAMUAAgJdRDoCwB7AQAUAAcJABLoCwB7AQASAAcJoghrlwAOAQAAAA==.Shambulance:BAAALgAECgUJCQAAAA==.Shammalxs:BAABLgAFFH8bAAIhAAgJNRImAwA0AgAhAAgJNRImAwA0AgAAAA==.Shamoc:BAABLgAECn8xAAMYAAkJxCK+BgBEAwAYAAkJxCK+BgBEAwAhAAYJohESSQAjAQAAAA==.Shampooing:BAACLgAFFH8MAAIhAAQJPg3KLQDcAAAhAAQJPg3KLQDcAAAuAAQKfygAAiEACQk3F74XACYCACEACQk3F74XACYCAAAA.Shampski:BAAALgAECgYJCwABLgAECggJFAAGAJEIAA==.Sharpknife:BAABLgAFFH8XAAMXAAUJHB2bCACIAQAXAAUJHB2bCACIAQAVAAMJRhH2ZwDVAAAAAA==.Shaz:BAAALgADCgQJBAAAAA==.Shivd:BAAALgAECgIJAgAAAA==.Shorpus:BAABLgAECn8nAAQhAAkJPx0oGAAiAgAZAAYJNx8hCgAwAgAhAAkJmRgoGAAiAgAYAAgJ3gn6XQATAQAAAA==.',
Si='Sicckbrew:BAABLgAECn8hAAIEAAkJaiH+CQDYAgAEAAkJaiH+CQDYAgABLgAFFAQJCAAkABcNAA==.Sickin:BAABLgAFFH8IAAIkAAQJFw1+GgC3AAAkAAQJFw1+GgC3AAAAAA==.Sinniestro:BAAALgAECgEJAgAAAA==.',
Sk='Skizzyy:BAAALgAECgMJAwABLgAECgcJEAAQAAAAAA==.Skwigelf:BAAALgAECgQJCwAAAA==.',
Sl='Slag:BAAALgAECgEJAQAAAA==.Slayedurmrs:BAAALgAECgQJBQAAAA==.Slok:BAAALgAECgEJAQAAAA==.Slowpoke:BAABLgAFFH8sAAIKAAUJwRvECABXAQAKAAUJwRvECABXAQABLgAFFAYJGQAGAEYYAA==.',
Sm='Smacedh:BAABLgAECn8XAAIeAAkJzRKUYgB6AQAeAAkJzRKUYgB6AQAAAA==.Smesher:BAACLgAFFH8HAAIaAAMJ8gUSLwCZAAAaAAMJ8gUSLwCZAAAuAAQKfywAAhoACQkqE4ULADIBABoACQkqE4ULADIBAAAA.',
Sn='Sneakyfella:BAAALgAFFAEJAgAAAA==.',
So='Solidus:BAABLgAFFH8GAAIaAAQJmhScSwAWAQAaAAQJmhScSwAWAQAAAA==.Sorgaath:BAAALgADCgcJBwABLgAECgQJBAAQAAAAAA==.',
Sp='Spaklehooves:BAAALgADCgYJBgAAAA==.Spicoli:BAAALgADCgEJAQAAAA==.Spiral:BAAALgAECgQJBwAAAA==.Spoonfed:BAAALgAECgQJCwAAAA==.',
Sq='Squiish:BAACLgAFFH8YAAMKAAgJ/hh3CwDjAQAKAAcJ/Rd3CwDjAQALAAUJkAXCLAACAQAuAAQKfxoAAgoABwmoJfALANkCAAoABwmoJfALANkCAAAA.',
St='Stavrophore:BAAALgAECgEJBQAAAA==.Stgeorge:BAAALgAFFAMJAwAAAA==.Stickydruid:BAAALgAECgIJBgABLgAECgkJTgAfALohAA==.Stickyholes:BAAALgAECgIJAgABLgAECgkJTgAfALohAA==.Stickymonk:BAAALgAECgEJBAABLgAECgkJTgAfALohAA==.Stickypriest:BAABLgAECn9OAAMfAAkJuiHDCADCAgAfAAkJuiHDCADCAgACAAEJExiTeQBCAAAAAA==.Stipe:BAAALgADCgUJCAAAAA==.Stove:BAAALgADCgcJCwAAAA==.Strawhats:BAACLgAFFH87AAIPAAgJ+hsgAwBMAgAPAAgJ+hsgAwBMAgAuAAQKf0IAAg8ACQkyJWcCANgDAA8ACQkyJWcCANgDAAEuAAUUCQlVAB4AsyMA.Streamliner:BAABLgAECn8/AAMBAAkJJBu3CwBpAgABAAkJJBu3CwBpAgAoAAMJ1gdKCwCNAAAAAA==.Stuunks:BAAALgAECgYJCwAAAA==.',
Su='Surv:BAACLgAFFH8QAAMRAAcJ6xSZDgB1AQARAAYJhg6ZDgB1AQAXAAQJyBjzEgAyAQAuAAQKfx8AAxEABwmVIDsKAMwBABEABgn+HzsKAMwBABcABwk6Gy4bAMQBAAAA.Sustangelia:BAABLgAECn8bAAMMAAkJbxh6UAAAAgAMAAkJbxh6UAAAAgAmAAEJBw/1NQBFAAAAAA==.',
Sw='Swiperight:BAAALgAECgEJAQAAAA==.Swordkiller:BAAALgAECgcJBgAAAA==.',
Sx='Sxy:BAAALgAECgYJBwABLgAECgkJPwAJAEUaAA==.',
Sy='Sy:BAABLgAFFH8SAAIaAAYJxw+VDABTAQAaAAYJxw+VDABTAQAAAA==.Synthesis:BAABLgAECn8hAAILAAgJoyVbBgBSAwALAAgJoyVbBgBSAwAAAA==.',
Ta='Tae:BAAALgADCgUJBQAAAA==.Taichee:BAAALgADCgUJBQAAAA==.Talas:BAAALgAECgQJBQAAAA==.Talletalanot:BAACLgAFFH8JAAIjAAMJWgnrIgCKAAAjAAMJWgnrIgCKAAAuAAQKfy4AAiMACQkbIMsFALMCACMACQkbIMsFALMCAAAA.Tandryan:BAAALgAECgQJBwAAAA==.Tanukiji:BAABLgAECn8nAAICAAkJFhwFDwB4AgACAAkJFhwFDwB4AgAAAA==.',
Td='Tdh:BAAALgADCgMJAwAAAA==.Tdk:BAABLgAECn8WAAMMAAgJqhSEvwD+AAAMAAcJzhWEvwD+AAANAAEJ0Q2SWgA4AAAAAA==.',
Te='Tee:BAAALgADCgUJBQAAAA==.Terry:BAAALgAECgcJBwAAAA==.Tesarion:BAACLgAFFH8FAAIMAAIJ9w7H5gCBAAAMAAIJ9w7H5gCBAAAuAAQKfxYAAgwACAkdGHlaALcBAAwACAkdGHlaALcBAAAA.Testalatesta:BAABLgAECn9KAAMIAAkJBSUXAQC5AwAIAAkJBSUXAQC5AwAaAAEJmwgItgEnAAAAAA==.Testaltesta:BAACLgAFFH8HAAIGAAMJbh0CEwD0AAAGAAMJbh0CEwD0AAAuAAQKfxwAAgYACQlEIWUGAD4DAAYACQlEIWUGAD4DAAEuAAQKCQlKAAgABSUA.',
Th='Tharien:BAAALgADCgIJAgAAAA==.Thouforsaken:BAAALgAFFAMJAwABLgAECgUJBQAQAAAAAA==.Thovir:BAAALgADCgEJAQAAAA==.',
Ti='Tiberian:BAAALgADCgIJAgAAAA==.Tinyvolt:BAAALgAECgkJDAAAAA==.',
Tm='Tmonk:BAAALgAECgkJDgAAAA==.',
To='Toinahun:BAAALgAECgQJBAAAAA==.Tookersoul:BAAALgAECgEJAQAAAA==.Totemea:BAAALgAECgYJDgAAAA==.Totems:BAACLgAFFH8UAAIYAAgJ1xepCQAvAgAYAAgJ1xepCQAvAgAuAAQKfxUAAhgACAkuG+EfAFECABgACAkuG+EfAFECAAAA.Totemteabag:BAAALgAECgEJAQAAAA==.Totemîxx:BAABLgAECn8wAAMhAAkJnxn/EwBLAgAhAAkJnxn/EwBLAgAYAAQJYQ23fgCYAAAAAA==.Touchhy:BAAALgAECgEJAQAAAA==.',
Tr='Trainz:BAAALgADCgcJBwAAAA==.Traktorbeam:BAAALgAECgQJBQAAAA==.Trass:BAACLgAFFH8aAAMSAAQJoxz1PQBVAQASAAQJoxz1PQBVAQATAAEJnBCyJgBHAAAuAAQKf0EAAxIACQndIO4XAJQCABIACQndIO4XAJQCABMAAwkqERxEAKUAAAAA.Trays:BAAALgADCgEJAQAAAA==.Trev:BAAALgAECgMJBAAAAA==.Trisse:BAABLgAECn8nAAIeAAgJog+nXAByAQAeAAgJog+nXAByAQAAAA==.',
Tu='Tuzz:BAACLgAFFH8QAAImAAMJgxUWFQDiAAAmAAMJgxUWFQDiAAAuAAQKfysAAiYACQljIWIBAO4CACYACQljIWIBAO4CAAAA.',
Tw='Twongle:BAAALgADCgIJAgABLgAECggJGgAPAMIVAA==.',
Ty='Tyden:BAAALgAECgYJEAAAAA==.Tyrmac:BAAALgAECgUJBgAAAA==.',
Va='Vael:BAAALgAECgYJCgAAAA==.Vaelyn:BAAALgAECgEJAQAAAA==.Valerie:BAAALgAECgUJBwAAAA==.Valkyrra:BAAALgAECgQJBAAAAA==.Vallyssa:BAAALgAECgIJAwAAAA==.Varaestia:BAAALgAECgQJBAAAAA==.Varg:BAAALgADCgEJAQABLgADCgEJAQAQAAAAAA==.Vargmk:BAAALgADCgEJAQAAAA==.Vargps:BAAALgADCgEJAQAAAA==.',
Ve='Velithara:BAAALgAECgcJBwAAAA==.Venestra:BAABLgAFFH8GAAIXAAMJ+BdkCgCxAAAXAAMJ+BdkCgCxAAAAAA==.Verdict:BAACLgAFFH8JAAIaAAQJzBtQOQA5AQAaAAQJzBtQOQA5AQAuAAQKfxgAAhoACAloHlsgAKoCABoACAloHlsgAKoCAAAA.Vermeil:BAAALgAECgQJBwAAAA==.Vermillion:BAACLgAFFH8dAAIaAAcJoRnCDwDyAQAaAAcJoRnCDwDyAQAuAAQKfyIAAhoACQnuIOgRANkCABoACQnuIOgRANkCAAAA.Verzik:BAABLgAECn8XAAMIAAkJixnyAABxAgAIAAkJixnyAABxAgAaAAIJnRsFLQBWAAAAAA==.',
Vi='Vib:BAAALgAECgEJAQAAAA==.Viegas:BAACLgAFFH8FAAIVAAIJnRKpIwBZAAAVAAIJnRKpIwBZAAAuAAQKfxsAAhUABwkjHK4gAEECABUABwkjHK4gAEECAAAA.Vincent:BAABLgAECn8hAAIPAAYJsB6ZfgDUAQAPAAYJsB6ZfgDUAQAAAA==.Vinijr:BAAALgAECgEJAgAAAA==.Vivamax:BAAALgAECgEJAQAAAA==.Vizsla:BAACLgAFFH8SAAIMAAUJaw1WeQARAQAMAAUJaw1WeQARAQAuAAQKfxUAAgwABwn7EZSiACgBAAwABwn7EZSiACgBAAAA.',
Vo='Voidthotnimz:BAEALgADCgcJBgAAAQ==.Volthic:BAAALgAECgQJBAAAAA==.Voltormu:BAAALgAECgMJBgAAAA==.Vore:BAABLgAECn8fAAIeAAkJeBVFOADlAQAeAAkJeBVFOADlAQAAAA==.',
Vr='Vrag:BAACLgAFFH8TAAIMAAQJJA+NIgATAQAMAAQJJA+NIgATAQAuAAQKf0EAAgwACQloGI8mAGkCAAwACQloGI8mAGkCAAAA.',
['Vè']='Vè:BAABLgAECn8bAAQNAAkJQBElHAB6AQANAAkJBQ8lHAB6AQAMAAcJ/BDVfwBkAQAmAAEJ5AR4QgAiAAAAAA==.',
['Vê']='Vêê:BAAALgAECgQJBgABLgAECgkJGwANAEARAA==.',
Wa='Wantondots:BAAALgAECgEJAgAAAA==.Warslaw:BAACLgAFFH8cAAINAAYJISLICgDQAQANAAYJISLICgDQAQAuAAQKfyAAAg0ACQlVI18FAOsCAA0ACQlVI18FAOsCAAAA.Warth:BAAALgADCgEJAQAAAA==.Waterwater:BAAALgAECgYJCgAAAA==.Waterwaterz:BAACLgAFFH8UAAIPAAQJcRmyKgAKAQAPAAQJcRmyKgAKAQAuAAQKfzkAAg8ACAnVHOQ0AJ8CAA8ACAnVHOQ0AJ8CAAAA.',
Wc='Wchin:BAABLgAECn8aAAIWAAgJ0yB6AQCKAgAWAAgJ0yB6AQCKAgAAAA==.Wchinz:BAABLgAECn8WAAIfAAkJbiCPDgCaAgAfAAkJbiCPDgCaAgAAAA==.',
We='Wedlock:BAAALgAECgMJBAAAAA==.Welcumshot:BAABLgAFFH8PAAIXAAMJsRWrHQDlAAAXAAMJsRWrHQDlAAAAAA==.Wenkar:BAAALgAECgUJDQABLgAECgkJVAATAFkeAA==.',
Wh='Whaka:BAAALgAECgIJAgABLgAFFAYJEwAjAFEKAA==.',
Wi='Wid:BAAALgAECgkJBQAAAA==.Windsabre:BAAALgADCgIJAgAAAA==.Wingz:BAAALgAFFAEJAgAAAA==.',
Wo='Woman:BAAALgAECgEJAgAAAA==.Woregeonnick:BAABLgAECn8fAAISAAcJVxEhZwCWAQASAAcJVxEhZwCWAQAAAA==.Woshiren:BAAALgAECgYJBgAAAA==.Wozzie:BAAALgADCggJCAAAAA==.',
Wr='Wrane:BAAALgAECgUJBgAAAA==.',
Wy='Wyvern:BAAALgAECgcJEAAAAA==.',
['Wä']='Wärrior:BAAALgADCgMJAwAAAA==.',
Xa='Xanadu:BAAALgADCgIJAgAAAA==.',
Xd='Xd:BAAALgAFFAEJAQAAAA==.',
Xe='Xerxexy:BAAALgAECgQJCwAAAA==.',
Xi='Xiaodingdang:BAAALgAFFAMJAwAAAA==.Xiera:BAABLgAECn8dAAIPAAkJTRDhUgDkAQAPAAkJTRDhUgDkAQAAAA==.',
Ya='Yaminosaishi:BAAALgAECgYJBwAAAA==.Yaoyôrozu:BAAALgADCgkJFAAAAA==.Yasuô:BAAALgADCgMJAwAAAA==.Yatelega:BAAALgADCgIJAgABLgAECgcJHwASAFcRAA==.Yazdorzarn:BAAALgAECgcJDAAAAA==.',
Yo='Yozzan:BAAALgAECgIJAgAAAA==.Yozzao:BAAALgAECgQJDAAAAA==.',
Yu='Yueli:BAAALgAFFAEJAQABLgAFFAgJGAAKAP4YAA==.',
Za='Zaaniz:BAABLgAECn8lAAQaAAkJ8BtvHwCvAgAaAAkJ8BtvHwCvAgAIAAQJgwnoXQC+AAAgAAIJ+Q12QABdAAAAAA==.',
Ze='Zenestra:BAAALgAECgkJAQABLgAFFAMJBgAXAPgXAA==.Zenshui:BAAALgAECgYJCQAAAA==.Zephyruss:BAAALgADCgEJAQAAAA==.Zervis:BAAALgAECgIJAgAAAA==.Zeyra:BAAALgAECgYJDAAAAA==.',
Zi='Zinako:BAAALgAECgIJBAAAAA==.',
Zo='Zocalo:BAAALgAECgUJBQAAAA==.',
['Èa']='Èasymode:BAAALgADCgEJAQAAAA==.',
['Ód']='Ódyssey:BAABLgAECn8aAAIZAAgJjRIkEQChAQAZAAgJjRIkEQChAQAAAA==.',
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
