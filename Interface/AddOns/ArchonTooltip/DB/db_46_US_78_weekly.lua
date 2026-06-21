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

local lookup = {'Rogue-Subtlety','Priest-Holy','Priest-Discipline','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','DemonHunter-Havoc','Paladin-Holy','Druid-Feral','Druid-Balance','Druid-Restoration','DeathKnight-Unholy','DeathKnight-Blood','DemonHunter-Vengeance','Mage-Frost','Unknown-Unknown','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Hunter-BeastMastery','Mage-Arcane','Shaman-Restoration','Shaman-Enhancement','Paladin-Retribution','Rogue-Assassination','Warrior-Protection','Evoker-Devastation','DemonHunter-Devourer','Priest-Shadow','Paladin-Protection','Shaman-Elemental','Evoker-Augmentation','Evoker-Preservation','Druid-Guardian','Mage-Fire','DeathKnight-Frost','Warrior-Fury','Rogue-Outlaw','Warrior-Arms','Hunter-Survival',}
local provider = {region='US',realm='Dreadmaul',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abbathdoom:BAABLgAECn8ZAAIBAAkJvwzoHwCWAQABAAkJvwzoHwCWAQAAAA==.Abyss:BAAALgAECgEJAQAAAA==.',
Ae='Aedaris:BAABLgAECn9XAAMCAAkJPCCHEABjAgACAAcJDiGHEABjAgADAAYJHhk4KwB8AQAAAA==.Ael:BAAALgAECgEJAQAAAA==.Aethalides:BAAALgAECgYJDwAAAA==.',
Al='Alandrias:BAAALgAECgkJAQAAAA==.Alf:BAAALgAECgEJAQAAAA==.Alithial:BAAALgAECgEJAgAAAA==.Aloremirin:BAAALgADCgUJBQAAAA==.Altaria:BAABLgAFFH8mAAQEAAgJiSI3AAAIAgAEAAgJiSI3AAAIAgAFAAUJKR3mHgA1AQAGAAEJZwnaXwBBAAABLgAFFAkJPQAHAJclAA==.Alvv:BAAALgADCgMJBQAAAA==.Alvz:BAAALgADCgMJAwAAAA==.',
Am='Ametrigos:BAAALgAECgEJAwABLgAECgkJJAAIAAggAA==.',
An='Anouke:BAAALgADCgIJAgAAAA==.Anserion:BAAALgADCgMJAwAAAA==.Anvious:BAAALgAECgcJDAAAAA==.',
Aq='Aquilea:BAABLgAECn8fAAMJAAkJJBJKDgDRAQAJAAkJJBJKDgDRAQAKAAEJhgaGmwAmAAAAAA==.',
Ar='Arcfuldodger:BAAALgAECgEJAgAAAA==.Artais:BAABLgAECn8gAAILAAgJ1Rx8FgCCAgALAAgJ1Rx8FgCCAgAAAA==.Artzlayer:BAACLgAFFH8JAAIMAAMJrxtDlADkAAAMAAMJrxtDlADkAAAuAAQKfzAAAwwACQlXI0oPAPICAAwACQlXI0oPAPICAA0AAQkAAFlwAAAAAAAA.Aríes:BAABLgAECn9RAAMHAAkJ3xqpDABbAgAHAAkJ3xqpDABbAgAOAAEJGAm4NgAsAAAAAA==.',
As='Ashbourne:BAAALgADCgcJCwAAAA==.',
Au='Autumnnight:BAAALgAECgEJBAAAAA==.',
Aw='Aw:BAAALgAECgYJEQABLgAFFAgJIwAPAHkYAA==.Awry:BAECLgAFFH8PAAIMAAUJ2hbsBwD5AAAMAAUJ2hbsBwD5AAAuAAQKfzIAAgwACQkcIsoMAAYDAAwACQkcIsoMAAYDAAAA.Awuuga:BAAALgAECgEJAQABLgAECgYJEgAQAAAAAA==.Aww:BAACLgAFFH8jAAIPAAgJeRjyAwCFAQAPAAgJeRjyAwCFAQAuAAQKfyAAAg8ACAljGwV/ANMBAA8ACAljGwV/ANMBAAAA.',
Az='Azamalaza:BAABLgAECn8nAAIRAAgJbyIUBgA4AgARAAgJbyIUBgA4AgAAAA==.Azmo:BAACLgAFFH8UAAQSAAYJ7hOCMwB5AQASAAYJAhKCMwB5AQATAAMJDRbxDADQAAAUAAEJ6xMDIQBPAAAuAAQKfyYAAxMACAkvIcECANYCABMACAmJHcECANYCABIABgk9HL1gAKcBAAAA.Azulon:BAAALgADCgUJBQABLgAECggJGgADAOkZAA==.Azyrt:BAAALgAECgQJBAABLgAECggJIAALANUcAA==.',
Ba='Badds:BAABLgAECn8UAAIIAAkJgRZOFABsAgAIAAkJgRZOFABsAgAAAA==.Ballona:BAAALgADCgUJBQAAAA==.Baløø:BAAALgAECgEJAQAAAA==.Barad:BAAALgAECgEJBAAAAA==.Batrick:BAAALgADCgcJBwAAAA==.Baulric:BAAALgAECgEJAQAAAA==.Bawls:BAABLgAFFH8HAAMFAAIJ7ga3TQBrAAAFAAIJ7ga3TQBrAAAEAAEJrAMWSQAuAAAAAA==.',
Be='Beastroll:BAABLgAECn8XAAIVAAcJChWrXgCKAQAVAAcJChWrXgCKAQAAAA==.Beefrod:BAAALgADCgEJAQAAAA==.Beenis:BAAALgADCgUJBQAAAA==.Belerick:BAABLgAFFH8JAAIKAAMJnQqfDwDoAAAKAAMJnQqfDwDoAAAAAA==.Belphine:BAAALgAECgYJCAAAAA==.',
Bi='Bicksmage:BAACLgAFFH8QAAIPAAQJXhGVZQAYAQAPAAQJXhGVZQAYAQAuAAQKfxYAAw8ACAnyFyFqAKcBAA8ACAnyFyFqAKcBABYAAQmLBysgAC8AAAAA.Bigdaddylock:BAACLgAFFH8ZAAQSAAcJBx3MKQCgAQASAAYJOBvMKQCgAQAUAAEJ+CMwFQBpAAATAAEJGBw4HABaAAAuAAQKfyUAAxMACQnoJE4IAD4CABIACAkzI6IuAFICABMABgm1Ik4IAD4CAAAA.Biluman:BAAALgAECgQJBAAAAA==.Biodeath:BAAALgADCgUJBQAAAA==.Biopally:BAAALgADCgYJDQAAAA==.Biorogue:BAAALgADCgYJDAAAAA==.Bishope:BAABLgAECn8aAAIDAAgJ6Rk0EABuAgADAAgJ6Rk0EABuAgAAAA==.',
Bl='Bllizard:BAAALgAECgEJAQAAAA==.Bloodache:BAAALgADCgcJDgABLgAECgUJGQAMAA4SAA==.Bluecar:BAAALgAECgYJCAAAAA==.',
Bo='Bohica:BAAALgAECgIJBQAAAA==.Bombdiggity:BAABLgAECn8+AAIDAAkJZh08BwAIAwADAAkJZh08BwAIAwAAAA==.Bonnierot:BAAALgAECgUJCgAAAA==.Boyscout:BAAALgAECgEJAQABLgAECggJCwAQAAAAAA==.',
Br='Brecciana:BAAALgADCgUJBQAAAA==.Brewjitsu:BAABLgAECn9IAAIFAAkJkR1xCQCbAgAFAAkJkR1xCQCbAgAAAA==.Brick:BAACLgAFFH8JAAMFAAMJeSGfJQATAQAFAAMJeSGfJQATAQAGAAEJ9BXpYQA8AAAuAAQKfx8AAgUABwl6HuQaAC0CAAUABwl6HuQaAC0CAAEuAAUUCAknABIAyBsA.Brongakill:BAAALgADCgYJBgAAAA==.Bräinfreeze:BAAALgAECgkJBwAAAA==.',
Bu='Buffy:BAAALgAECgEJAgAAAA==.Bumble:BAAALgADCgYJBgABLgAFFAgJJwACADkbAA==.Bundalock:BAAALgADCgYJEQAAAA==.',
Ca='Cakebringer:BAAALgAECgcJEgAAAA==.Caroshi:BAACLgAFFH8MAAIPAAQJawRRdgDvAAAPAAQJawRRdgDvAAAuAAQKfygAAg8ACQmzDXRkALUBAA8ACQmzDXRkALUBAAAA.',
Ce='Cell:BAAALgAECgUJCAABLgAECgkJIAAVAOMUAA==.Ceridwen:BAAALgADCgEJAQAAAA==.',
Ch='Chaingun:BAAALgAECggJEQAAAA==.Charlotte:BAAALgAECgMJDAAAAA==.Cheto:BAABLgAFFH8HAAIMAAIJzhP92QCIAAAMAAIJzhP92QCIAAABLgAFFAcJEwAXAM0XAA==.Chosen:BAAALgAECgEJAQAAAA==.Chud:BAAALgAECgUJBQABLgAFFAYJGQAYAHgjAA==.',
Ci='Cig:BAABLgAECn8YAAIZAAgJ/xB1hABmAQAZAAgJ/xB1hABmAQAAAA==.',
Cl='Clankychan:BAACLgAFFH8LAAIFAAMJTA0ZPAC2AAAFAAMJTA0ZPAC2AAAuAAQKfxgAAgUABwkMFe08AAgBAAUABwkMFe08AAgBAAAA.Cloneofmagic:BAAALgADCgcJBwAAAA==.',
Co='Combustanut:BAAALgAECgUJEAAAAA==.Comillmouth:BAABLgAECn8ZAAIDAAgJbxFmKQCIAQADAAgJbxFmKQCIAQAAAA==.Comillthroat:BAAALgAECgkJEQAAAA==.Cornflakez:BAAALgADCgMJAwAAAA==.Cos:BAABLgAECn82AAMBAAkJbxGuFwDdAQABAAkJbxGuFwDdAQAaAAMJOAXFFgCKAAAAAA==.',
Cr='Crocks:BAAALgAECgIJAgAAAA==.Crozier:BAAALgAECgIJBgAAAA==.Crusher:BAAALgAECgUJBgABLgAFFAcJEwAXAM0XAA==.Cryptum:BAAALgAECgkJBAAAAA==.Cryten:BAAALgAECgIJAgAAAA==.',
Cu='Cub:BAAALgAECgEJAgAAAA==.Cultiran:BAAALgAECgQJBAABLgAFFAYJGQAYAHgjAA==.Curby:BAAALgAECgcJBwABLgAECgkJTgAbAJ4eAA==.',
['Cä']='Cäin:BAAALgAECgQJCAAAAA==.',
Da='Dabufart:BAAALgADCgEJAQAAAA==.Daerus:BAAALgAECgYJBQAAAA==.Dagwood:BAAALgAECgEJAQAAAA==.Damge:BAAALgAECgUJCgAAAA==.Damnnyou:BAAALgAECgcJCAABLgAECgkJIwAcAK0ZAA==.Danky:BAAALgAECgMJAwAAAA==.Danteh:BAABLgAFFH8IAAIdAAMJ3wdabwCrAAAdAAMJ3wdabwCrAAAAAA==.Darahug:BAAALgAECgYJBgAAAA==.Daraina:BAAALgADCgEJAQABLgADCgEJAQAQAAAAAA==.Darktalanus:BAAALgADCgQJBAAAAA==.Darrkton:BAAALgADCgEJAQAAAA==.Dathil:BAAALgAECgYJCQAAAA==.Davmonhunter:BAAALgADCgQJBAAAAA==.Davoodooman:BAAALgAECgYJCAABLgAFFAQJGAASAKMcAA==.',
De='Deadiemurphy:BAAALgADCgYJCQAAAA==.Deathshunter:BAABLgAECn8jAAMVAAkJwCMFEwC6AgAVAAgJWSUFEwC6AgARAAYJ+hkjOgB5AQABLgAFFAgJIQAMAIEiAA==.Deaththorn:BAAALgADCgEJAQAAAA==.Debsi:BAABLgAECn8kAAIbAAkJyA7EFgCOAQAbAAkJyA7EFgCOAQAAAA==.Declined:BAAALgAECgEJAQAAAA==.Deeper:BAABLgAFFH8NAAIXAAMJ3QetXwCMAAAXAAMJ3QetXwCMAAAAAA==.Deepest:BAABLgAFFH8HAAIaAAQJ0g9eBQAqAQAaAAQJ0g9eBQAqAQAAAA==.Deloraine:BAACLgAFFH8uAAIeAAcJjiSYAwBgAgAeAAcJjiSYAwBgAgAuAAQKfycAAh4ACQkAIs0FAPYCAB4ACQkAIs0FAPYCAAAA.Demonbick:BAAALgADCgMJAwAAAA==.Demonicfaith:BAABLgAECn82AAMHAAcJbxqFFwAMAgAHAAYJTx6FFwAMAgAdAAcJlQzbgAAoAQAAAA==.Denman:BAABLgAECn8YAAMZAAcJjBnRdgCNAQAZAAcJjBnRdgCNAQAfAAEJmAAmUAAKAAAAAA==.Dezarian:BAAALgAECggJCAAAAA==.',
Di='Dirtyfista:BAAALgAECgYJCgAAAA==.Dirtyfux:BAACLgAFFH8KAAIDAAMJ5RK7MgDCAAADAAMJ5RK7MgDCAAAuAAQKfxUAAwMABglsHJgrAHoBAAMABglsHJgrAHoBAAIAAQkZDweDAC4AAAAA.Dirtysham:BAACLgAFFH8PAAIXAAQJcRqkLwAjAQAXAAQJcRqkLwAjAQAuAAQKfzAAAxcACQm3H/0MALUCABcACAl1If0MALUCACAABAmHCutnAK8AAAAA.Discipline:BAAALgADCgcJBwAAAA==.Disckin:BAAALgAECgEJAwAAAA==.Diseasemode:BAAALgAECgEJAgAAAA==.Divinechill:BAAALgAECgEJAQAAAA==.',
Dn='Dnb:BAAALgADCgEJAQABLgAFFAgJIwAPAHkYAA==.Dnk:BAAALgADCgMJAwAAAA==.',
Do='Dom:BAAALgADCgcJCQAAAA==.Donki:BAAALgAECgkJDAAAAA==.Doodtanky:BAAALgADCgEJAQAAAA==.Doomvedas:BAAALgAECgYJCgAAAA==.',
Dr='Dracaena:BAABLgAECn8jAAQcAAkJrRnuBgDZAQAhAAgJkBT/GwDoAQAcAAgJtBfuBgDZAQAiAAUJQwizMQDiAAAAAA==.Draco:BAAALgAECgMJAwAAAA==.Dreadknìght:BAAALgAFFAUJBAAAAA==.Drekavach:BAAALgADCgcJEwAAAA==.Droidbick:BAAALgAFFAIJBAAAAA==.',
['Dâ']='Dâftmonk:BAAALgAECgQJBgABLgAECgkJDAAQAAAAAA==.',
Ee='Eevo:BAAALgAECgMJAwABLgAECggJFAAGAJEIAA==.',
El='Elaha:BAAALgAECgcJCQAAAA==.Elexann:BAAALgAECgkJAQAAAA==.Elibaba:BAABLgAFFH8GAAIPAAIJMh+elACqAAAPAAIJMh+elACqAAABLgAFFAIJCgAMAOAZAA==.Elideady:BAABLgAFFH8KAAIMAAIJ4Bm0DwCQAAAMAAIJ4Bm0DwCQAAAAAA==.Elinaa:BAAALgAECgIJAgAAAA==.Elindyl:BAAALgADCgEJAQAAAA==.Elisaxy:BAAALgAECgEJAgAAAA==.Elleth:BAAALgADCgMJAwAAAA==.Elvishcheese:BAAALgAECgMJBgAAAA==.',
Em='Emojis:BAAALgAECgUJCgAAAA==.Emopapa:BAAALgAFFAEJAQABLgAFFAIJBAAQAAAAAA==.',
En='Endlessdh:BAACLgAFFH8IAAIHAAMJCiIKBwDIAAAHAAMJCiIKBwDIAAAuAAQKfx4AAgcABwkyJJUJAMgCAAcABwkyJJUJAMgCAAAA.',
Er='Eraserhead:BAAALgAECgYJEwABLgAFFAYJGQAYAHgjAA==.Eripaladin:BAAALgAECgUJBwAAAA==.Erissaria:BAAALgADCgEJAQAAAA==.Erwinnara:BAAALgAECgEJAgAAAA==.',
Ev='Evening:BAAALgAECggJCQAAAA==.Everbuddha:BAAALgAECgQJBgAAAA==.',
Ew='Ewa:BAAALgAECgMJBAAAAA==.Eww:BAABLgAECn8XAAIdAAcJyw90dAA4AQAdAAcJyw90dAA4AQAAAA==.',
Ez='Ezelia:BAACLgAFFH8SAAMZAAUJExmFOAA8AQAZAAUJExmFOAA8AQAIAAIJgghePQBrAAAuAAQKfxoAAxkACQl+FmxIAO0BABkACQl+FmxIAO0BAAgAAQlGCVeVADUAAAEuAAUUCAk1AAIA9B4A.',
Fa='Faelune:BAABLgAECn8fAAIPAAkJ6wpHbQCgAQAPAAkJ6wpHbQCgAQAAAA==.Faldir:BAAALgADCgYJBAABLgAFFAUJHQAdACwgAA==.',
Fe='Ferndru:BAACLgAFFH8JAAMJAAMJMg7gAADfAAAJAAMJMg7gAADfAAAjAAIJMQdJMgBVAAAuAAQKfy4AAwkACQkBGdkIADwCAAkACAnYG9kIADwCACMABwlNEi8BAAwBAAAA.',
Fi='Fisticuffs:BAACLgAFFH8TAAIGAAYJdRDnHwBvAQAGAAYJdRDnHwBvAQAuAAQKfykAAgYACAmEHdsPAKcCAAYACAmEHdsPAKcCAAAA.',
Fl='Flameshock:BAAALgAFFAIJBAAAAA==.Flowki:BAAALgADCgcJCwAAAA==.',
Fo='Forcespark:BAAALgAECgEJAQAAAA==.',
Fr='Fraserker:BAAALgAECgEJAQAAAA==.Frostradamus:BAAALgADCgkJCgAAAA==.',
Fu='Fullmoonride:BAAALgAECgUJDwAAAA==.Fumbll:BAAALgAECgkJCQAAAA==.Funkymajik:BAABLgAECn8fAAQDAAkJlg+UHgDaAQADAAkJlg+UHgDaAQACAAIJiAaJdQBTAAAeAAEJtQtOYgA0AAAAAA==.Furiosa:BAAALgADCgkJDgAAAA==.Furrballz:BAAALgAECgEJAQAAAA==.',
Ga='Gallywox:BAAALgADCgMJAwAAAA==.Ganin:BAABLgAECn8bAAIIAAYJUBU0QgBvAQAIAAYJUBU0QgBvAQAAAA==.Gankinyou:BAAALgADCgEJAQAAAA==.Gargish:BAAALgAECgkJCQABLgAFFAEJAQAQAAAAAA==.Garielyn:BAAALgADCgEJAQAAAA==.Garugala:BAACLgAFFH8OAAIZAAMJCRX9bADWAAAZAAMJCRX9bADWAAAuAAQKfysAAhkACQklGKk0AC4CABkACQklGKk0AC4CAAAA.',
Gb='Gbosch:BAAALgAECgYJCQAAAA==.',
Gd='Gdaycøb:BAAALgADCgYJBwAAAA==.',
Ge='Gengár:BAAALgAECgMJBgABLgAFFAEJAQAQAAAAAA==.',
Gh='Ghalorin:BAABLgAECn8eAAIVAAcJMhp9PQDrAQAVAAcJMhp9PQDrAQAAAA==.Ghiroza:BAABLgAECn9UAAQTAAkJWR7fCAAzAgASAAkJ3B1OJQBJAgATAAgJihbfCAAzAgAUAAQJIxnKEwAzAQAAAA==.',
Gi='Giga:BAAALgAECgEJAQABLgAECgkJVAATAFkeAA==.Gigaevoker:BAABLgAECn8kAAIiAAgJcRa4DAAIAgAiAAgJcRa4DAAIAgAAAA==.Gigapaladin:BAAALgADCgQJBAAAAA==.Gingarthas:BAABLgAECn8iAAIMAAkJPh01KwCMAgAMAAkJPh01KwCMAgAAAA==.',
Gl='Glowingtoe:BAAALgAECgMJBQAAAA==.',
Go='Gobgob:BAAALgAECgMJAwAAAA==.Gogmazios:BAAALgADCgcJBwAAAA==.',
Gr='Gravytate:BAABLgAECn9XAAIgAAkJfA8YLwCFAQAgAAkJfA8YLwCFAQAAAA==.Griinn:BAABLgAECn8hAAIjAAkJow9JHQBjAQAjAAkJow9JHQBjAQAAAA==.Grimefiend:BAAALgAFFAIJAwAAAA==.Grimescene:BAAALgAECgIJAgABLgAFFAIJAwAQAAAAAA==.Grimreapêr:BAAALgAECgEJBQAAAA==.Grow:BAAALgAFFAEJAwAAAA==.',
Gu='Guldannyboy:BAABLgAECn80AAMTAAkJSw3lDQBeAQATAAkJygzlDQBeAQASAAkJFwfHdQBOAQAAAA==.Gumbö:BAAALgAECgcJCQABLgAECggJIAALANUcAA==.Gutted:BAAALgADCgIJAgAAAA==.',
Ha='Haides:BAAALgAECgUJBgAAAA==.Hammer:BAAALgAECgIJAgABLgAECgkJDAAQAAAAAA==.Hanokano:BAAALgAECggJDQABLgAFFAQJGAASAKMcAA==.Hantore:BAAALgADCgMJAwAAAA==.Harmony:BAAALgAECgEJAQAAAA==.Harry:BAACLgAFFH8IAAIYAAMJohfWDgDTAAAYAAMJohfWDgDTAAAuAAQKfycAAxgACQljJOUBAD8DABgACQljJOUBAD8DABcABwnEGuMgABoCAAAA.',
He='Heartdh:BAABLgAECn8VAAMdAAgJkhLIUwCLAQAdAAgJkhLIUwCLAQAHAAIJrxOGWwByAAAAAA==.Heisenbergg:BAAALgADCgIJAgAAAA==.Hellza:BAAALgAECgMJAwAAAA==.Hen:BAAALgAECgUJBQABLgAECgYJFQANABAVAA==.Herpyprotect:BAAALgAFFAIJAwAAAA==.Herrion:BAACLgAFFH8nAAQSAAgJyBv8FgAIAgASAAcJjBv8FgAIAgATAAEJKx3xGwBbAAAUAAEJyB/XGgBXAAAuAAQKfy4AAxIACQn/IvkcAKgCABIACAn/IvkcAKgCABMABAmcJNMUAKQBAAAA.',
Hh='Hh:BAAALgAECgEJAQAAAA==.',
Ho='Holytanky:BAAALgAECgcJCgAAAA==.Hotspur:BAABLgAECn84AAILAAgJaxDUOADDAQALAAgJaxDUOADDAQAAAA==.',
Hu='Hukani:BAAALgAECgEJAwABLgAECggJFgACALEIAA==.Hunner:BAAALgAECgIJAgABLgAECggJFAAGAJEIAA==.Huskar:BAABLgAECn8gAAIVAAkJ4xQeMAAcAgAVAAkJ4xQeMAAcAgAAAA==.',
Hy='Hypoxi:BAAALgADCgYJCQAAAA==.',
Ig='Ignis:BAABLgAECn8cAAIkAAkJmR3mAQBmAgAkAAkJmR3mAQBmAgAAAA==.Ignitor:BAAALgADCgEJAQAAAA==.',
Ik='Ikari:BAABLgAECn9YAAITAAkJyhpdBQCBAgATAAkJyhpdBQCBAgAAAA==.',
Il='Illadoss:BAAALgADCgIJAgAAAA==.',
Im='Imntprepared:BAAALgAFFAEJAQAAAA==.',
In='Incarnate:BAAALgAECgEJAgAAAA==.Incubis:BAAALgADCgIJAgAAAA==.Infectîon:BAAALgAECgYJBwAAAA==.Inferlock:BAAALgAECgMJAwAAAA==.Infernyos:BAAALgAECgUJBQAAAA==.Infernyoz:BAAALgADCggJCQAAAA==.',
Ir='Irithel:BAAALgAECgcJBQAAAA==.',
Is='Isohexene:BAAALgADCgYJBgAAAA==.',
It='Itchygrowth:BAAALgAFFAEJAQAAAA==.',
Iu='Iucifer:BAAALgAECgEJAgAAAA==.',
Iv='Ivygambina:BAAALgADCgYJBgAAAA==.Ivysore:BAAALgAECgUJBwAAAA==.',
Ja='Jasha:BAAALgADCgcJCwAAAA==.Jayvarmani:BAAALgAECgMJAwAAAA==.Jayy:BAABLgAECn8bAAIMAAkJBRCKTAANAgAMAAkJBRCKTAANAgAAAA==.',
Je='Jennatalia:BAAALgAECggJEgABLgAFFAEJAQAQAAAAAA==.',
Ji='Jinkazamaz:BAAALgAFFAIJBAAAAA==.',
Jo='Joelsdruid:BAABLgAFFH8gAAIjAAYJlhvuBQCcAQAjAAYJlhvuBQCcAQAAAA==.Joelvoker:BAAALgAFFAIJAgABLgAFFAYJIAAjAJYbAA==.Joexotic:BAAALgAECgIJBwAAAA==.Jongwang:BAAALgAECgQJBwAAAA==.',
Ju='Jubjub:BAAALgAECgEJAgAAAA==.',
Ka='Kaaru:BAACLgAFFH8JAAIDAAQJ4gruKgD5AAADAAQJ4gruKgD5AAAuAAQKfyUAAwMACQmME5YYAA8CAAMACQl6EpYYAA8CAAIABQkTEoZIABcBAAAA.Kaelom:BAAALgAECgQJBQAAAA==.Kahai:BAAALgAECgIJAgAAAA==.Kaiforst:BAAALgAECgQJBAABLgAECgkJOQAZAOEaAA==.Kaihavocz:BAAALgAECgEJAwAAAA==.Kairon:BAABLgAECn85AAIZAAkJ4RrlLABNAgAZAAkJ4RrlLABNAgAAAA==.Kalysae:BAAALgADCgEJAQAAAA==.Kania:BAAALgAECgIJAgABLgAECgkJMQAXAMQiAA==.Katarinabluu:BAAALgAECgYJBgAAAA==.Kazakhthundr:BAAALgADCgYJBgAAAA==.',
Ke='Keeanuleaves:BAAALgADCgYJBwAAAA==.Keeanuweaves:BAAALgADCgEJAQAAAA==.Keeze:BAACLgAFFH8QAAIPAAQJbQkgcAABAQAPAAQJbQkgcAABAQAuAAQKfxgAAg8ACQkaEyBYANUBAA8ACQkaEyBYANUBAAAA.',
Ki='Kickstarter:BAAALgAECgYJEgAAAA==.Kiel:BAAALgAECgEJAQAAAA==.Kikiz:BAAALgAECgUJDQAAAA==.Kill:BAAALgAFFAIJAgAAAA==.Killania:BAAALgADCgMJAwAAAA==.Kiwichaos:BAACLgAFFH8KAAIHAAQJnQkHHwCoAAAHAAQJnQkHHwCoAAAuAAQKfy4AAgcACQlbG6QMAJcCAAcACQlbG6QMAJcCAAAA.',
Kn='Knox:BAAALgAECgUJCgAAAA==.Knull:BAAALgAECgIJBQAAAA==.',
Ko='Korner:BAAALgAECgIJAgAAAA==.',
Kr='Krazzul:BAAALgAECgQJBAAAAA==.Krellis:BAACLgAFFH8HAAIEAAMJjBlIAgDDAAAEAAMJjBlIAgDDAAAuAAQKfxoAAwQACQm9Fz0QAEkCAAQACQm9Fz0QAEkCAAYABgm1EDwxADMBAAAA.Kritikall:BAAALgADCgUJBQAAAA==.',
Ku='Kurö:BAAALgAECgEJAQAAAA==.',
Kv='Kvôthe:BAABLgAECn8dAAMMAAkJPgyVawCOAQAMAAkJCguVawCOAQAlAAMJzQe7KgB/AAAAAA==.',
Ky='Kynnareth:BAAALgAFFAIJBAABLgAFFAYJFQAIAIoPAA==.Kynralol:BAABLgAECn9eAAIPAAkJqyKwDAAUAwAPAAkJqyKwDAAUAwAAAA==.Kyujín:BAAALgAECgIJAgAAAA==.Kyunsun:BAAALgAECgYJCAAAAA==.',
['Ká']='Káiser:BAAALgAECggJEQAAAA==.',
La='Laenosh:BAABLgAECn8ZAAIMAAUJDhLj1wDeAAAMAAUJDhLj1wDeAAAAAA==.Lagalot:BAAALgAECgEJAQAAAA==.Laomoo:BAAALgAECgcJDgAAAA==.Laz:BAAALgADCgMJBQAAAA==.',
Le='Learning:BAABLgAECn8XAAIgAAcJEh9LGwA4AgAgAAcJEh9LGwA4AgAAAA==.Legham:BAAALgADCgkJDgAAAA==.Legolazz:BAABLgAECn8yAAMVAAkJ4B7SGgCEAgAVAAkJ4B7SGgCEAgARAAMJCBTjKQBuAAAAAA==.Lemins:BAAALgAECgMJAwAAAA==.Lemondruid:BAAALgAECgIJAgAAAA==.Lemonmelon:BAAALgAECgYJEwAAAA==.Lenatheplug:BAACLgAFFH8eAAMBAAgJ2RYMAwDMAQABAAcJWRoMAwDMAQAaAAIJjQnKBQBgAAAuAAQKfyIAAwEACAmUJEQKAO0CAAEACAnbI0QKAO0CABoABwlAIt4DAIACAAAA.Lerust:BAAALgADCgcJBwAAAA==.',
Li='Liadrine:BAACLgAFFH8FAAIZAAQJdAz9VAAGAQAZAAQJdAz9VAAGAQAuAAQKfzAAAhkACQnjF5RJAOkBABkACQnjF5RJAOkBAAAA.Linus:BAAALgAECgYJBgABLgAFFAgJJwASAMgbAA==.Littleriver:BAABLgAECn8ZAAIVAAgJ2hirNgDUAQAVAAgJ2hirNgDUAQAAAA==.',
Ll='Llewser:BAABLgAECn8aAAMPAAgJwhWqUADqAQAPAAgJwhWqUADqAQAkAAEJqgSAFQAqAAAAAA==.',
Lo='Loathe:BAAALgAFFAEJAQAAAA==.Loistiah:BAABLgAFFH8IAAIMAAMJZhm+mADdAAAMAAMJZhm+mADdAAAAAA==.Lothaof:BAABLgAECn8sAAIZAAkJ6RKYXAC5AQAZAAkJ6RKYXAC5AQAAAA==.Louisvuitton:BAAALgAECgUJDwAAAA==.',
Lp='Lpayn:BAAALgADCgEJAQAAAA==.',
Lu='Lugroth:BAABLgAFFH8FAAMjAAMJWhYNGADFAAAjAAMJWhYNGADFAAALAAEJIxGMcAA2AAABLgAFFAgJJwASAMgbAA==.Lunana:BAAALgAECgcJEgAAAA==.',
Ly='Lychiee:BAAALgAECgcJEQAAAA==.',
['Lì']='Lìnkinbark:BAAALgAECgMJAwAAAA==.',
Ma='Madara:BAAALgAECgEJAgAAAA==.Magesorry:BAAALgADCgUJBQAAAA==.Magicmon:BAAALgADCgkJGgAAAA==.Maize:BAABLgAECn8iAAMDAAgJMBtzEwBFAgADAAgJMBtzEwBFAgACAAMJhgvTZwCOAAAAAA==.Makima:BAABLgAFFH8FAAIKAAUJmQ4PLgDPAAAKAAUJmQ4PLgDPAAABLgAFFAYJGQAGAEYYAA==.Malikai:BAAALgADCgcJDAAAAA==.Malxsvoker:BAAALgAFFAIJAgABLgAFFAYJEAAgANsPAA==.Marcymonk:BAAALgADCgEJAQAAAA==.Marcyon:BAABLgAECn8bAAIdAAcJDAlCoADiAAAdAAcJDAlCoADiAAAAAA==.Marywinston:BAAALgAFFAEJAQABLgAFFAIJBgANAFMUAA==.',
Mc='Mchèalz:BAABLgAECn8VAAQDAAgJRAhKPQAYAQADAAgJRAhKPQAYAQACAAQJxAFFaQCIAAAeAAIJOwF0ZgAsAAAAAA==.',
Me='Melodysseý:BAAALgAECgUJBQAAAA==.Melonlemonza:BAAALgADCgQJBAAAAA==.Mentok:BAAALgAECgYJCwAAAA==.Merchei:BAAALgAECgUJBgAAAA==.Meruen:BAACLgAFFH8IAAIdAAQJlBO3RwARAQAdAAQJlBO3RwARAQAuAAQKfzoAAx0ACQniG3EYAIMCAB0ACQniG3EYAIMCAA4AAwm2ApIrAFQAAAAA.',
Mi='Mik:BAAALgAECgcJBwABLgAFFAUJHQAdACwgAA==.Miralisa:BAAALgAFFAIJAgAAAA==.Miss:BAAALgAECgMJAwAAAA==.Mistie:BAAALgAECgEJAQABLgAECgkJIwALAGwXAA==.Mitymorphin:BAAALgADCgEJAQAAAA==.',
Mo='Mobility:BAAALgAFFAEJAQAAAA==.Moistpole:BAAALgADCgQJBAAAAA==.Momock:BAAALgAECgQJBAAAAA==.Mongk:BAABLgAECn8UAAIGAAgJkQibNQAZAQAGAAgJkQibNQAZAQAAAA==.Monkagè:BAAALgAECgQJBAAAAA==.Monscustodes:BAABLgAECn8kAAIPAAkJWA/aYQC8AQAPAAkJWA/aYQC8AQAAAA==.Monstersauce:BAAALgAFFAIJBAAAAA==.Mookin:BAAALgAFFAEJAQAAAA==.Moospoon:BAABLgAECn9HAAIZAAkJ+xYpPgANAgAZAAkJ+xYpPgANAgAAAA==.Mooudini:BAAALgAECgMJAwAAAA==.Moounka:BAABLgAECn9MAAIFAAkJsRWMEwAUAgAFAAkJsRWMEwAUAgAAAA==.Morphio:BAACLgAFFH8FAAIVAAMJSRncVwD2AAAVAAMJSRncVwD2AAAuAAQKf0sAAxUACQkvJVwDAFsDABUACQkvJVwDAFsDABEABQkLE5pMAB8BAAAA.Mostakrakish:BAAALgADCgEJAQAAAA==.',
Mu='Muddles:BAABLgAECn9EAAIFAAkJUBjoEQAoAgAFAAkJUBjoEQAoAgAAAA==.Murius:BAACLgAFFH8KAAIMAAMJkQSxuwCxAAAMAAMJkQSxuwCxAAAuAAQKfzIAAgwACQlEF/A2ACMCAAwACQlEF/A2ACMCAAAA.',
My='Mysterio:BAAALgAFFAEJBAAAAA==.',
Na='Naendria:BAAALgAECgMJBAAAAA==.Naga:BAAALgAECgIJAgAAAA==.Nahaza:BAAALgAECgEJAgAAAA==.',
Ne='Nelena:BAAALgAECgIJAgAAAA==.',
Ni='Nickdoom:BAAALgAECgUJEwAAAA==.Nigella:BAABLgAECn8WAAMCAAgJsQjOOwAGAQACAAgJsQjOOwAGAQADAAEJ6wF/iQAgAAAAAA==.Nikola:BAACLgAFFH8GAAMLAAIJzw/aUgB5AAALAAIJzw/aUgB5AAAKAAEJ3QdKUQA0AAAuAAQKfyoABAsACQmjFWc3AMoBAAsACQmjFWc3AMoBACMABQk4Ft8VABQBAAoABAl9D39UANQAAAAA.Nimro:BAACLgAFFH8bAAIbAAcJqRWUCACsAQAbAAcJqRWUCACsAQAuAAQKfygAAhsACQmPH6ADABsDABsACQmPH6ADABsDAAAA.Niub:BAABLgAECn8qAAImAAkJ9hOrIADrAQAmAAkJ9hOrIADrAQAAAA==.',
No='Nofate:BAAALgADCgEJAQAAAA==.Noirebringer:BAAALgAFFAEJAQAAAA==.Nongbonnie:BAAALgAECgIJAgAAAA==.Nongkiwi:BAAALgAECggJCwAAAA==.',
Nt='Ntrldrake:BAAALgADCgEJAgABLgAECgkJJAAPAFgPAA==.',
Nu='Nueng:BAAALgADCgEJAQAAAA==.Nuferax:BAABLgAECn8fAAIOAAkJXyH6AQDzAgAOAAkJXyH6AQDzAgAAAA==.Nuiiwarx:BAAALgAECgEJAwAAAA==.Nulledhacz:BAAALgAECgUJAwAAAA==.Numbrethree:BAACLgAFFH8TAAIGAAQJ/hENNADcAAAGAAQJ/hENNADcAAAuAAQKf0wAAwYACQnFG4YOALcCAAYACQnFG4YOALcCAAQAAglDBm+1ACIAAAAA.',
Ob='Obbi:BAACLgAFFH8cAAIaAAQJ0yaDAQDNAQAaAAQJ0yaDAQDNAQAuAAQKfxoAAxoACQkpIFIBAAMDABoACQkpIFIBAAMDACcAAQk/JJUcAGcAAAAA.',
Oh='Ohaither:BAAALgAECgQJBAAAAA==.',
Oi='Oirth:BAAALgADCgIJAgAAAA==.',
Ok='Okiji:BAAALgAECgkJEwAAAA==.',
Om='Ominae:BAAALgADCgEJAQAAAA==.',
Or='Orinocco:BAAALgAECgEJAwAAAA==.Orobas:BAAALgAECgkJEwAAAA==.',
Pa='Pakaww:BAAALgAECgIJAwAAAA==.Palimathrus:BAAALgAECgUJCAAAAA==.Palliative:BAABLgAECn9IAAMIAAkJQCLZBgAeAwAIAAkJQCLZBgAeAwAZAAQJLwVzGwGZAAAAAA==.Pallidnim:BAABLgAFFH8JAAINAAUJuBGRHwDrAAANAAUJuBGRHwDrAAAAAA==.Papager:BAABLgAFFH8IAAISAAMJvAYkhwC3AAASAAMJvAYkhwC3AAAAAA==.',
Pe='Pea:BAAALgAECgcJEAAAAA==.Perish:BAAALgAECggJDQABLgAECgkJRAAFAFAYAA==.',
Ph='Phatmonk:BAACLgAFFH8cAAMEAAUJkiaaBQDBAQAEAAUJkiaaBQDBAQAGAAIJyATJWABQAAAuAAQKf0cAAwQACQmxJn4AAIYDAAQACQmxJn4AAIYDAAYABwntIJ4RAJICAAAA.Phatrogue:BAABLgAFFH8JAAIBAAMJjB3tIwAFAQABAAMJjB3tIwAFAQABLgAFFAUJHAAEAJImAA==.',
Pi='Piewpiew:BAAALgADCgcJCgAAAA==.Pix:BAACLgAFFH8cAAMeAAcJZR3XAgDHAQAeAAcJZR3XAgDHAQADAAUJvQwjIQBHAQAuAAQKfzYAAh4ACQk5JTcCAEoDAB4ACQk5JTcCAEoDAAAA.',
Pl='Pleasuremax:BAACLgAFFH8LAAIVAAQJ4RUvMQBNAQAVAAQJ4RUvMQBNAQAuAAQKfxoAAhUACAksFWtGAM4BABUACAksFWtGAM4BAAAA.Plex:BAABLgAECn8/AAIJAAkJRRpYBwBlAgAJAAkJRRpYBwBlAgAAAA==.',
Po='Poofyfeesh:BAAALgAFFAEJAgAAAA==.Poogie:BAAALgADCgYJBgABLgAECgMJBQAQAAAAAA==.Popshot:BAABLgAECn8eAAIRAAYJ5xIiRQBBAQARAAYJ5xIiRQBBAQAAAA==.Portalhouse:BAAALgAECgEJAQAAAA==.',
Pr='Praxis:BAACLgAFFH8PAAIbAAQJ3RIUAgDWAAAbAAQJ3RIUAgDWAAAuAAQKfzQAAxsACAmeGAwVAKIBABsACAnsFwwVAKIBACgABglRFwQgAF4BAAAA.Preast:BAAALgAECgcJBwABLgAECggJFAAGAJEIAA==.Procist:BAABLgAECn8ZAAMCAAkJBxd8EABjAgACAAkJBxd8EABjAgAeAAEJpQd+kQApAAABLgAECgkJMQAXAMQiAA==.',
Py='Pyrusdk:BAABLgAECn8ZAAIMAAkJgQ6LYACoAQAMAAkJgQ6LYACoAQAAAA==.Pyrusdruid:BAABLgAECn8WAAILAAkJJwIlnQB2AAALAAkJJwIlnQB2AAAAAA==.',
Qo='Qop:BAAALgAFFAEJAgAAAA==.',
Qu='Quesarah:BAAALgADCgEJAQABLgAECgQJBAAQAAAAAA==.',
Qw='Qweffor:BAAALgAECgUJBQABLgAFFAIJBQAMAPcOAA==.',
Ra='Rainbowkelly:BAAALgAECgQJBAAAAA==.Raisha:BAAALgADCgEJAQAAAA==.Raìn:BAACLgAFFH8HAAIMAAMJmAxzrQDGAAAMAAMJmAxzrQDGAAAuAAQKfxQAAgwACAnYFcRRAM4BAAwACAnYFcRRAM4BAAAA.',
Re='Recruitqt:BAACLgAFFH8FAAMZAAIJDg1NkgCOAAAZAAIJDg1NkgCOAAAIAAEJ+Af8SQA1AAAuAAQKfx8AAwgABQm0Gg86AJEBAAgABQm0Gg86AJEBABkABAkTETfXAOkAAAAA.Reiayanami:BAABLgAECn8fAAIPAAgJfA+3gQB0AQAPAAgJfA+3gQB0AQAAAA==.',
Ri='Ripandtear:BAABLgAECn8gAAMLAAkJZRdqKQAIAgALAAkJZRdqKQAIAgAJAAEJFQZ6NgAsAAAAAA==.',
Ro='Roguewan:BAAALgAFFAIJAgAAAA==.Rolâyne:BAAALgADCgkJDgAAAA==.Roninn:BAACLgAFFH8RAAILAAQJ5RlkJQAwAQALAAQJ5RlkJQAwAQAuAAQKfzQAAgsACQlVIawFAF0DAAsACQlVIawFAF0DAAAA.Ronlock:BAABLgAECn8VAAMSAAYJ8xD9nQAdAQASAAUJ8xD9nQAdAQATAAEJAAABagA+AAABLgAECgcJNgAHAG8aAA==.Royaltits:BAAALgADCgIJAgAAAA==.',
Rs='Rsi:BAAALgAECgQJBAAAAA==.',
Ry='Rynaea:BAAALgAECggJDwAAAA==.',
['Rï']='Rïmuru:BAAALgADCgcJCwAAAA==.',
['Rô']='Rôlayne:BAABLgAECn8ZAAImAAgJdQu9QwA2AQAmAAgJdQu9QwA2AQAAAA==.',
Sa='Sadakos:BAAALgAFFAMJBAAAAA==.Salvare:BAABLgAECn8lAAMaAAkJhhhwAwCVAgAaAAkJfRhwAwCVAgAnAAIJRRClGwBvAAAAAA==.Sappy:BAAALgAECgQJBAAAAA==.Sarielsiá:BAAALgAFFAEJAQAAAA==.Sauron:BAAALgADCgEJAQABLgAFFAQJFAASAPYUAA==.',
Sb='Sbf:BAABLgAFFH8ZAAIhAAcJ4RbqEQDtAQAhAAcJ4RbqEQDtAQABLgAFFAkJRAAdAG4jAA==.',
Sc='Scalamander:BAAALgAECgcJAgAAAA==.Sciohunter:BAABLgAFFH8FAAIHAAIJIAyoJQB5AAAHAAIJIAyoJQB5AAAAAA==.Scioscioz:BAACLgAFFH8OAAILAAQJ0BDrLwDyAAALAAQJ0BDrLwDyAAAuAAQKfyAAAwsABwnOFOI7ALUBAAsABwnOFOI7ALUBAAoAAglnEAJsAHAAAAAA.Scwisgar:BAAALgAECgkJDQAAAA==.',
Se='Sedge:BAAALgAFFAIJBAAAAA==.Sephire:BAABLgAECn8eAAIZAAkJPARqzAD4AAAZAAkJPARqzAD4AAAAAA==.Sermazule:BAAALgADCgcJEQAAAA==.Sewerface:BAABLgAECn8VAAMNAAYJEBWaHgBTAQANAAYJEBWaHgBTAQAMAAMJLAScAQF2AAAAAA==.',
Sh='Shadonir:BAAALgAECgQJBAAAAA==.Shadowind:BAACLgAFFH8mAAIVAAUJKh9eBgDzAAAVAAUJKh9eBgDzAAAuAAQKfy8AAxEACQmGHn4dADsCABEACAlEGX4dADsCABUABQlkHUthAIQBAAAA.Shadowz:BAAALgAECgEJAgAAAA==.Shaft:BAAALgAECgEJAQAAAA==.Shallotte:BAABLgAECn8YAAMUAAgJdRDoCwB7AQAUAAcJABLoCwB7AQASAAcJogholwAOAQAAAA==.Shambulance:BAAALgAECgUJCAAAAA==.Shammalxs:BAABLgAFFH8QAAIgAAYJ2w82GgBJAQAgAAYJ2w82GgBJAQAAAA==.Shamoc:BAABLgAECn8xAAMXAAkJxCLABgBEAwAXAAkJxCLABgBEAwAgAAYJohESSQAjAQAAAA==.Shampooing:BAACLgAFFH8MAAIgAAQJPg3LLQDcAAAgAAQJPg3LLQDcAAAuAAQKfygAAiAACQk3F78XACYCACAACQk3F78XACYCAAAA.Shampski:BAAALgAECgYJCwABLgAECggJFAAGAJEIAA==.Sharpknife:BAABLgAFFH8UAAMpAAQJJR+ZCACIAQApAAQJJR+ZCACIAQAVAAMJRhH1ZwDVAAAAAA==.Shaz:BAAALgADCgQJBAAAAA==.Shivd:BAAALgAECgIJAgAAAA==.Shorpus:BAABLgAECn8kAAQgAAkJPx0pGAAiAgAYAAYJNx8hCgAwAgAgAAkJmRgpGAAiAgAXAAcJCwj6XQATAQAAAA==.',
Si='Sicckbrew:BAABLgAECn8hAAIEAAkJaiH+CQDYAgAEAAkJaiH+CQDYAgABLgAFFAQJCAAjABcNAA==.Sickin:BAABLgAFFH8IAAIjAAQJFw1/GgC3AAAjAAQJFw1/GgC3AAAAAA==.Sinniestro:BAAALgAECgEJAgAAAA==.',
Sk='Skizzyy:BAAALgAECgMJAwABLgAECgcJEAAQAAAAAA==.Skwigelf:BAAALgAECgQJCAAAAA==.',
Sl='Slayedurmrs:BAAALgAECgQJBQAAAA==.Slok:BAAALgAECgEJAQAAAA==.Slowpoke:BAABLgAFFH8sAAIKAAUJwRvECABXAQAKAAUJwRvECABXAQABLgAFFAYJGQAGAEYYAA==.',
Sm='Smacedh:BAABLgAECn8XAAIdAAkJzRKUYgB6AQAdAAkJzRKUYgB6AQAAAA==.Smesher:BAABLgAECn8qAAIZAAkJ1BGkUQDUAQAZAAkJ1BGkUQDUAQAAAA==.',
Sn='Sneakyfella:BAAALgAFFAEJAgAAAA==.',
So='Solidus:BAABLgAFFH8GAAIZAAQJmhSqSwAWAQAZAAQJmhSqSwAWAQAAAA==.Sorgaath:BAAALgADCgcJBwABLgAECgQJBAAQAAAAAA==.',
Sp='Spaklehooves:BAAALgADCgYJBgAAAA==.Spicoli:BAAALgADCgEJAQAAAA==.Spiral:BAAALgAECgQJBwAAAA==.Spoonfed:BAAALgAECgQJCwAAAA==.',
Sq='Squiish:BAACLgAFFH8YAAMKAAgJ/hiECwDjAQAKAAcJ/ReECwDjAQALAAUJkAXJLAACAQAuAAQKfxoAAgoABwmoJfALANkCAAoABwmoJfALANkCAAAA.',
St='Stavrophore:BAAALgAECgEJBQAAAA==.Stickydruid:BAAALgAECgIJBgABLgAECgkJTgAeALohAA==.Stickyholes:BAAALgAECgIJAgABLgAECgkJTgAeALohAA==.Stickymonk:BAAALgAECgEJBAABLgAECgkJTgAeALohAA==.Stickypriest:BAABLgAECn9OAAMeAAkJuiHECADCAgAeAAkJuiHECADCAgACAAEJExiTeQBCAAAAAA==.Stipe:BAAALgADCgUJCAAAAA==.Stove:BAAALgADCgcJCwAAAA==.Strawhats:BAACLgAFFH87AAIPAAgJ+hsgAwBMAgAPAAgJ+hsgAwBMAgAuAAQKf0IAAg8ACQkyJWcCANgDAA8ACQkyJWcCANgDAAEuAAUUCQlEAB0AbiMA.Streamliner:BAABLgAECn8/AAMBAAkJJBu0CwBpAgABAAkJJBu0CwBpAgAnAAMJ1gdKCwCNAAAAAA==.Stuunks:BAAALgAECgYJCwAAAA==.',
Su='Surv:BAACLgAFFH8QAAMRAAcJ6xSqDgB1AQARAAYJhg6qDgB1AQApAAQJyBjyEgAyAQAuAAQKfx8AAxEABwmVIDsKAMwBABEABgn+HzsKAMwBACkABwk6Gy8bAMQBAAAA.Sustangelia:BAABLgAECn8bAAMMAAkJbxh6UAAAAgAMAAkJbxh6UAAAAgAlAAEJBw/1NQBFAAAAAA==.',
Sw='Swordkiller:BAAALgAECgcJBgAAAA==.',
Sx='Sxy:BAAALgAECgYJBwABLgAECgkJPwAJAEUaAA==.',
Sy='Sy:BAABLgAFFH8MAAIZAAUJ9gxzBAAKAQAZAAUJ9gxzBAAKAQAAAA==.Synthesis:BAABLgAECn8hAAILAAgJoyVbBgBSAwALAAgJoyVbBgBSAwAAAA==.',
Ta='Tae:BAAALgADCgUJBQAAAA==.Taichee:BAAALgADCgUJBQAAAA==.Talas:BAAALgAECgQJBQAAAA==.Talletalanot:BAACLgAFFH8JAAIiAAMJWgnsIgCKAAAiAAMJWgnsIgCKAAAuAAQKfy4AAiIACQkbIMsFALMCACIACQkbIMsFALMCAAAA.Tandryan:BAAALgAECgQJBwAAAA==.Tanukiji:BAABLgAECn8nAAICAAkJFhwFDwB4AgACAAkJFhwFDwB4AgAAAA==.',
Td='Tdh:BAAALgADCgMJAwAAAA==.Tdk:BAABLgAECn8WAAMMAAgJqhR9vwD+AAAMAAcJzhV9vwD+AAANAAEJ0Q2UWgA4AAAAAA==.',
Te='Tee:BAAALgADCgUJBQAAAA==.Terry:BAAALgAECgcJBwAAAA==.Tesarion:BAACLgAFFH8FAAIMAAIJ9w7J5gCBAAAMAAIJ9w7J5gCBAAAuAAQKfxYAAgwACAkdGHZaALcBAAwACAkdGHZaALcBAAAA.Testalatesta:BAABLgAECn9KAAMIAAkJBSUYAQC5AwAIAAkJBSUYAQC5AwAZAAEJmwgGtgEnAAAAAA==.Testaltesta:BAABLgAECn8XAAIGAAkJ/R9nBgA+AwAGAAkJ/R9nBgA+AwABLgAECgkJSgAIAAUlAA==.',
Th='Tharien:BAAALgADCgIJAgAAAA==.Thovir:BAAALgADCgEJAQAAAA==.',
Ti='Tiberian:BAAALgADCgIJAgAAAA==.Tinyvolt:BAAALgAECgkJDAAAAA==.',
Tm='Tmonk:BAAALgAECgkJDgAAAA==.',
To='Toinahun:BAAALgAECgQJBAAAAA==.Tookersoul:BAAALgAECgEJAQAAAA==.Totemea:BAAALgAECgYJDgAAAA==.Totems:BAACLgAFFH8TAAIXAAcJzRetCQAvAgAXAAcJzRetCQAvAgAuAAQKfxUAAhcACAkuG+AfAFECABcACAkuG+AfAFECAAAA.Totemteabag:BAAALgAECgEJAQAAAA==.Totemîxx:BAABLgAECn8wAAMgAAkJnxn/EwBLAgAgAAkJnxn/EwBLAgAXAAQJYQ23fgCYAAAAAA==.Touchhy:BAAALgAECgEJAQAAAA==.',
Tr='Trainz:BAAALgADCgcJBwAAAA==.Traktorbeam:BAAALgADCgQJBAAAAA==.Trass:BAACLgAFFH8YAAMSAAQJoxwWPgBVAQASAAQJoxwWPgBVAQATAAEJnBC2JgBHAAAuAAQKf0EAAxIACQndIO8XAJQCABIACQndIO8XAJQCABMAAwkqERxEAKUAAAAA.Trays:BAAALgADCgEJAQAAAA==.Trisse:BAABLgAECn8nAAIdAAgJog+oXAByAQAdAAgJog+oXAByAQAAAA==.',
Tu='Tuzz:BAACLgAFFH8OAAIlAAMJgxUVFQDiAAAlAAMJgxUVFQDiAAAuAAQKfysAAiUACQljIWIBAO4CACUACQljIWIBAO4CAAAA.',
Tw='Twongle:BAAALgADCgIJAgABLgAECggJGgAPAMIVAA==.',
Ty='Tyden:BAAALgAECgYJEAAAAA==.Tyrmac:BAAALgAECgUJBgAAAA==.',
Va='Vael:BAAALgAECgYJCgAAAA==.Valerie:BAAALgAECgUJBwAAAA==.Valkyrra:BAAALgAECgQJBAAAAA==.Vallyssa:BAAALgAECgIJAwAAAA==.Varaestia:BAAALgAECgQJBAAAAA==.Varg:BAAALgADCgEJAQABLgADCgEJAQAQAAAAAA==.Vargmk:BAAALgADCgEJAQAAAA==.Vargps:BAAALgADCgEJAQAAAA==.',
Ve='Velithara:BAAALgAECgcJBwAAAA==.Venestra:BAAALgAFFAMJBAAAAA==.Verdict:BAACLgAFFH8JAAIZAAQJzBtgOQA5AQAZAAQJzBtgOQA5AQAuAAQKfxgAAhkACAloHlsgAKoCABkACAloHlsgAKoCAAAA.Vermeil:BAAALgAECgMJAwAAAA==.Vermillion:BAACLgAFFH8aAAIZAAcJoRnTDwDyAQAZAAcJoRnTDwDyAQAuAAQKfyIAAhkACQnuIOgRANkCABkACQnuIOgRANkCAAAA.Verzik:BAAALgAECgkJDgAAAA==.',
Vi='Vib:BAAALgAECgEJAQAAAA==.Viegas:BAACLgAFFH8FAAIVAAIJnRKpIwBZAAAVAAIJnRKpIwBZAAAuAAQKfxsAAhUABwkjHK4gAEECABUABwkjHK4gAEECAAAA.Vincent:BAABLgAECn8hAAIPAAYJsB6ZfgDUAQAPAAYJsB6ZfgDUAQAAAA==.Vinijr:BAAALgAECgEJAgAAAA==.Vivamax:BAAALgAECgEJAQAAAA==.Vizsla:BAACLgAFFH8QAAIMAAUJaw1beQARAQAMAAUJaw1beQARAQAuAAQKfxUAAgwABwn7EZCiACgBAAwABwn7EZCiACgBAAAA.',
Vo='Voidthotnimz:BAEALgADCgcJBgAAAQ==.Volthic:BAAALgAECgQJBAAAAA==.Voltormu:BAAALgAECgMJBgAAAA==.Vore:BAABLgAECn8fAAIdAAkJeBVCOADlAQAdAAkJeBVCOADlAQAAAA==.',
Vr='Vrag:BAACLgAFFH8TAAIMAAQJJA84BgAdAQAMAAQJJA84BgAdAQAuAAQKf0AAAgwACQloGI8mAGkCAAwACQloGI8mAGkCAAAA.',
['Vè']='Vè:BAABLgAECn8bAAQNAAkJQBEiHAB6AQANAAkJBQ8iHAB6AQAMAAcJ/BDSfwBkAQAlAAEJ5AR4QgAiAAAAAA==.',
['Vê']='Vêê:BAAALgAECgQJBgABLgAECgkJGwANAEARAA==.',
Wa='Wantondots:BAAALgAECgEJAgAAAA==.Warslaw:BAACLgAFFH8cAAINAAYJISLUCgDQAQANAAYJISLUCgDQAQAuAAQKfyAAAg0ACQlVI18FAOsCAA0ACQlVI18FAOsCAAAA.Warth:BAAALgADCgEJAQAAAA==.Waterwater:BAAALgAECgYJCgAAAA==.Waterwaterz:BAACLgAFFH8UAAIPAAQJcRmyKgAKAQAPAAQJcRmyKgAKAQAuAAQKfzkAAg8ACAnVHOQ0AJ8CAA8ACAnVHOQ0AJ8CAAAA.',
Wc='Wchin:BAABLgAECn8aAAIWAAgJ0yB6AQCKAgAWAAgJ0yB6AQCKAgAAAA==.Wchinz:BAABLgAECn8WAAIeAAkJbiCPDgCaAgAeAAkJbiCPDgCaAgAAAA==.',
We='Wedlock:BAAALgAECgMJBAAAAA==.Welcumshot:BAABLgAFFH8OAAIpAAMJsRWrHQDlAAApAAMJsRWrHQDlAAAAAA==.Wenkar:BAAALgAECgUJDQABLgAECgkJVAATAFkeAA==.',
Wh='Whaka:BAAALgAECgIJAgABLgAFFAYJEQAiAFEKAA==.',
Wi='Wid:BAAALgAECgkJBQAAAA==.Windsabre:BAAALgADCgIJAgAAAA==.Wingz:BAAALgAFFAEJAgAAAA==.',
Wo='Woman:BAAALgAECgEJAgAAAA==.Woregeonnick:BAABLgAECn8fAAISAAcJVxEhZwCWAQASAAcJVxEhZwCWAQAAAA==.Woshiren:BAAALgAECgYJBgAAAA==.Wozzie:BAAALgADCggJCAAAAA==.',
Wr='Wrane:BAAALgAECgQJBAAAAA==.',
Wy='Wyvern:BAAALgAECgcJEAAAAA==.',
['Wä']='Wärrior:BAAALgADCgMJAwAAAA==.',
Xa='Xanadu:BAAALgADCgIJAgAAAA==.',
Xd='Xd:BAAALgAFFAEJAQAAAA==.',
Xe='Xerxexy:BAAALgAECgQJCwAAAA==.',
Xi='Xiaodingdang:BAAALgAFFAMJAwAAAA==.Xiera:BAABLgAECn8dAAIPAAkJTRDiUgDkAQAPAAkJTRDiUgDkAQAAAA==.',
Ya='Yaminosaishi:BAAALgAECgYJBwAAAA==.Yaoyôrozu:BAAALgADCgkJFAAAAA==.Yasuô:BAAALgADCgMJAwAAAA==.Yatelega:BAAALgADCgIJAgABLgAECgcJHwASAFcRAA==.Yazdorzarn:BAAALgAECgcJDAAAAA==.',
Yo='Yozzan:BAAALgAECgIJAgAAAA==.Yozzao:BAAALgAECgQJDAAAAA==.',
Yu='Yueli:BAAALgAFFAEJAQABLgAFFAgJGAAKAP4YAA==.',
Za='Zaaniz:BAABLgAECn8lAAQZAAkJ8BtvHwCvAgAZAAkJ8BtvHwCvAgAIAAQJgwnoXQC+AAAfAAIJ+Q11QABdAAAAAA==.',
Ze='Zenestra:BAAALgAECgkJAQABLgAFFAMJBAAQAAAAAA==.Zenshui:BAAALgAECgYJCQAAAA==.Zephyruss:BAAALgADCgEJAQAAAA==.Zervis:BAAALgAECgIJAgAAAA==.Zeyra:BAAALgAECgYJDAAAAA==.',
Zi='Zinako:BAAALgAECgIJAwAAAA==.',
Zo='Zocalo:BAAALgAECgUJBQAAAA==.',
['Èa']='Èasymode:BAAALgADCgEJAQAAAA==.',
['Ód']='Ódyssey:BAABLgAECn8ZAAIYAAgJCRIlEQChAQAYAAgJCRIlEQChAQAAAA==.',
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
