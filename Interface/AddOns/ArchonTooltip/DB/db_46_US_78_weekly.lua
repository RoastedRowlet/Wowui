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

local lookup = {'Rogue-Subtlety','Priest-Holy','Priest-Discipline','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Paladin-Holy','Druid-Feral','Druid-Balance','Druid-Restoration','DeathKnight-Unholy','DeathKnight-Blood','DemonHunter-Havoc','DemonHunter-Vengeance','Mage-Frost','Unknown-Unknown','Hunter-Marksmanship','Warlock-Destruction','Warlock-Demonology','Hunter-BeastMastery','Mage-Arcane','Shaman-Restoration','Shaman-Enhancement','Paladin-Retribution','Rogue-Assassination','Warrior-Protection','Evoker-Devastation','DemonHunter-Devourer','Priest-Shadow','Paladin-Protection','Shaman-Elemental','Evoker-Augmentation','Evoker-Preservation','Druid-Guardian','Warlock-Affliction','Mage-Fire','DeathKnight-Frost','Warrior-Fury','Rogue-Outlaw','Hunter-Survival',}
local provider = {region='US',realm='Dreadmaul',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abbathdoom:BAABLgAECn8UAAIBAAgJJgn1KQAsAQABAAgJJgn1KQAsAQAAAA==.',
Ae='Aedaris:BAABLgAECn9XAAMCAAkJPCBBDgBqAgACAAcJDiFBDgBqAgADAAYJHhmWJgB3AQAAAA==.Ael:BAAALgAECgEJAQAAAA==.Aethalides:BAAALgAECgYJDwAAAA==.',
Al='Alandrias:BAAALgAECgkJAQAAAA==.Alf:BAAALgAECgEJAQAAAA==.Aloremirin:BAAALgADCgUJBQAAAA==.Altaria:BAABLgAFFH8VAAQEAAYJDxhiGABAAQAEAAUJKR1iGABAAQAFAAQJ7xUxEgAZAQAGAAEJ2gcBSQBCAAAAAA==.Alvv:BAAALgADCgMJBQAAAA==.Alvz:BAAALgADCgMJAwAAAA==.',
Am='Ametrigos:BAAALgAECgEJAgABLgAECgkJJAAHAAggAA==.',
An='Anouke:BAAALgADCgIJAgAAAA==.Anserion:BAAALgADCgMJAwAAAA==.Anvious:BAAALgAECgcJDAAAAA==.',
Aq='Aquilea:BAABLgAECn8aAAMIAAgJLRCrEgBtAQAIAAgJLRCrEgBtAQAJAAEJhgZxiwAmAAAAAA==.',
Ar='Arcfuldodger:BAAALgAECgEJAgAAAA==.Artais:BAABLgAECn8gAAIKAAgJ1Rx8FgCCAgAKAAgJ1Rx8FgCCAgAAAA==.Artzlayer:BAACLgAFFH8IAAILAAMJrxvTdwDuAAALAAMJrxvTdwDuAAAuAAQKfzAAAwsACQlXI2sMAPkCAAsACQlXI2sMAPkCAAwAAQkAAPZjAAAAAAAA.Aríes:BAABLgAECn9RAAMNAAkJ3xp/CgBkAgANAAkJ3xp/CgBkAgAOAAEJGAlcMAAsAAAAAA==.',
As='Ashbourne:BAAALgADCgcJCwAAAA==.',
Aw='Aw:BAAALgAECgYJEQABLgAFFAcJGAAPALcWAA==.Awry:BAEBLgAECn8yAAILAAkJHCL5CQAQAwALAAkJHCL5CQAQAwAAAA==.Awuuga:BAAALgAECgEJAQABLgAECgYJEgAQAAAAAA==.Aww:BAACLgAFFH8YAAIPAAcJtxZzFQACAgAPAAcJtxZzFQACAgAuAAQKfyAAAg8ACAljGwV/ANMBAA8ACAljGwV/ANMBAAAA.',
Az='Azamalaza:BAABLgAECn8nAAIRAAgJbyIyBQBBAgARAAgJbyIyBQBBAgAAAA==.Azmo:BAACLgAFFH8JAAMSAAMJ5hhYCQDcAAASAAMJDRZYCQDcAAATAAMJBgwNOQCiAAAuAAQKfyUAAxIACAkvIcECANYCABIACAmJHcECANYCABMABQk9HL1gAKcBAAAA.Azulon:BAAALgADCgUJBQABLgAECggJGgADAOkZAA==.Azyrt:BAAALgAECgQJBAABLgAECggJIAAKANUcAA==.',
Ba='Badds:BAABLgAECn8UAAIHAAkJgRauEQByAgAHAAkJgRauEQByAgAAAA==.Ballona:BAAALgADCgUJBQAAAA==.Barad:BAAALgAECgEJAwAAAA==.Batrick:BAAALgADCgcJBwAAAA==.Baulric:BAAALgAECgEJAQAAAA==.Bawls:BAAALgAFFAIJBAAAAA==.',
Be='Beastroll:BAABLgAECn8VAAIUAAcJ9xGjWwB5AQAUAAcJ9xGjWwB5AQAAAA==.Beefrod:BAAALgADCgEJAQAAAA==.Beenis:BAAALgADCgUJBQABLgAFFAQJBgALAEANAA==.Belerick:BAABLgAFFH8JAAIJAAMJnQqfDwDoAAAJAAMJnQqfDwDoAAAAAA==.Belphine:BAAALgAECgYJCAAAAA==.',
Bi='Bicksmage:BAACLgAFFH8OAAIPAAQJXhFHVgAmAQAPAAQJXhFHVgAmAQAuAAQKfxMAAw8ACAnyFyNgAKcBAA8ACAnyFyNgAKcBABUAAQmLBysgAC8AAAAA.Bigdaddylock:BAACLgAFFH8SAAMTAAcJohihIwCHAQATAAYJ8RehIwCHAQASAAEJGBw6FgBgAAAuAAQKfyUAAxIACQnoJE4IAD4CABMACAkzI6IuAFICABIABgm1Ik4IAD4CAAAA.Biluman:BAAALgAECgQJBAAAAA==.Biodeath:BAAALgADCgUJBQAAAA==.Biopally:BAAALgADCgYJDQAAAA==.Biorogue:BAAALgADCgYJDAAAAA==.Bishope:BAABLgAECn8aAAIDAAgJ6RnpDQBxAgADAAgJ6RnpDQBxAgAAAA==.',
Bl='Bllizard:BAAALgAECgEJAQAAAA==.Bloodache:BAAALgADCgcJDgABLgAECgUJGQALAA4SAA==.Bluecar:BAAALgAECgYJCAAAAA==.',
Bo='Bohica:BAAALgAECgIJBQAAAA==.Bombdiggity:BAABLgAECn80AAIDAAgJgx7OCgClAgADAAgJgx7OCgClAgAAAA==.Bonnierot:BAAALgAECgUJCgAAAA==.Boypally:BAAALgAECggJCgAAAA==.',
Br='Brecciana:BAAALgADCgUJBQAAAA==.Brewjitsu:BAABLgAECn9IAAIEAAkJkR0gCACgAgAEAAkJkR0gCACgAgAAAA==.Brick:BAACLgAFFH8JAAMEAAMJeSFzHgAfAQAEAAMJeSFzHgAfAQAGAAEJ9BVSSgA9AAAuAAQKfx8AAgQABwl6HuQaAC0CAAQABwl6HuQaAC0CAAEuAAUUCAkkABMAyBsA.Brongakill:BAAALgADCgYJBgAAAA==.Bräinfreeze:BAAALgAECgkJBwAAAA==.',
Bu='Buffy:BAAALgAECgEJAgAAAA==.Bumble:BAAALgADCgYJBgABLgAFFAgJIgACADkbAA==.Bundalock:BAAALgADCgYJEQAAAA==.',
Ca='Cakebringer:BAAALgAECgcJEgAAAA==.Caroshi:BAACLgAFFH8IAAIPAAMJOQQYfgDBAAAPAAMJOQQYfgDBAAAuAAQKfygAAg8ACQmzDWpbALMBAA8ACQmzDWpbALMBAAAA.',
Ce='Cell:BAAALgAECgUJCAABLgAECgkJIAAUAOMUAA==.Ceridwen:BAAALgADCgEJAQAAAA==.',
Ch='Charlotte:BAAALgAECgMJDAAAAA==.Cheto:BAABLgAFFH8FAAILAAIJzhMhsQCSAAALAAIJzhMhsQCSAAABLgAFFAYJEQAWAEkZAA==.Chosen:BAAALgADCgEJAQAAAA==.Chud:BAAALgAECgUJBQABLgAFFAYJGQAXAHgjAA==.',
Ci='Cig:BAABLgAECn8YAAIYAAgJ/xBRdABrAQAYAAgJ/xBRdABrAQAAAA==.',
Cl='Clankychan:BAACLgAFFH8LAAIEAAMJTA3NNAC/AAAEAAMJTA3NNAC/AAAuAAQKfxgAAgQABwkMFe03AAwBAAQABwkMFe03AAwBAAAA.Cloneofmagic:BAAALgADCgcJBwAAAA==.',
Co='Combustanut:BAAALgAECgUJEAAAAA==.Comillmouth:BAABLgAECn8ZAAIDAAgJbxGZJACHAQADAAgJbxGZJACHAQAAAA==.Comillthroat:BAAALgAECgkJEQAAAA==.Cos:BAABLgAECn82AAMBAAkJbxFyFADlAQABAAkJbxFyFADlAQAZAAMJOAXFFgCKAAAAAA==.',
Cr='Crozier:BAAALgAECgIJBgAAAA==.Crusher:BAAALgAECgUJBQABLgAFFAYJEQAWAEkZAA==.Cryptum:BAAALgAECgkJBAAAAA==.Cryten:BAAALgAECgIJAgAAAA==.',
Cu='Curby:BAAALgAECgcJBwABLgAECgkJTgAaAJ4eAA==.',
['Cä']='Cäin:BAAALgAECgQJCAAAAA==.',
Da='Dabufart:BAAALgADCgEJAQAAAA==.Daerus:BAAALgAECgYJBQAAAA==.Dagwood:BAAALgAECgEJAQAAAA==.Damge:BAAALgAECgUJCgAAAA==.Damnnyou:BAAALgAECgcJCAABLgAECgkJIwAbAK0ZAA==.Danky:BAAALgAECgMJAwAAAA==.Danteh:BAABLgAFFH8GAAIcAAMJ3wffXAC3AAAcAAMJ3wffXAC3AAAAAA==.Darahug:BAAALgAECgYJBgAAAA==.Daraina:BAAALgADCgEJAQABLgADCgEJAQAQAAAAAA==.Darktalanus:BAAALgADCgQJBAAAAA==.Darrkton:BAAALgADCgEJAQAAAA==.Dathil:BAAALgAECgYJCQAAAA==.Davmonhunter:BAAALgADCgQJBAAAAA==.Davoodooman:BAAALgAECgIJAgABLgAFFAMJDwATACAbAA==.',
De='Deadiemurphy:BAAALgADCgYJCQAAAA==.Deathshunter:BAABLgAECn8iAAMUAAkJwCPDDgDHAgAUAAgJWSXDDgDHAgARAAYJ+hkjOgB5AQABLgAFFAYJHAALAOEhAA==.Deaththorn:BAAALgADCgEJAQAAAA==.Debsi:BAABLgAECn8fAAIaAAkJVQ2AFQCFAQAaAAkJVQ2AFQCFAQAAAA==.Deeper:BAABLgAFFH8HAAIWAAMJ3QfsSwCkAAAWAAMJ3QfsSwCkAAAAAA==.Deepest:BAABLgAFFH8HAAIZAAQJ0g9TBAA2AQAZAAQJ0g9TBAA2AQAAAA==.Deloraine:BAACLgAFFH8nAAIdAAcJjiSbAQB7AgAdAAcJjiSbAQB7AgAuAAQKfycAAh0ACQkAInwEAPkCAB0ACQkAInwEAPkCAAAA.Demonicfaith:BAABLgAECn82AAMNAAcJbxqFFwAMAgANAAYJTx6FFwAMAgAcAAcJlQzbgAAoAQAAAA==.Denman:BAABLgAECn8YAAMYAAcJjBnRdgCNAQAYAAcJjBnRdgCNAQAeAAEJmAAmUAAKAAAAAA==.Dezarian:BAAALgAECggJCAAAAA==.',
Di='Dirtyfux:BAACLgAFFH8KAAIDAAMJ5RLeKADMAAADAAMJ5RLeKADMAAAuAAQKfxUAAwMABglsHJMmAHcBAAMABglsHJMmAHcBAAIAAQkZDweDAC4AAAAA.Dirtysham:BAACLgAFFH8PAAIWAAQJcRqSJAAwAQAWAAQJcRqSJAAwAQAuAAQKfzAAAxYACQm3H/0MALUCABYACAl1If0MALUCAB8ABAmHCt9cALIAAAAA.Discipline:BAAALgADCgcJBwAAAA==.Disckin:BAAALgAECgEJAgAAAA==.Diseasemode:BAAALgAECgEJAQAAAA==.Divinechill:BAAALgADCgQJBQAAAA==.',
Dn='Dnb:BAAALgADCgEJAQABLgAFFAcJGAAPALcWAA==.Dnk:BAAALgADCgMJAwAAAA==.',
Do='Dom:BAAALgADCgcJCQAAAA==.Donki:BAAALgAECgkJDAAAAA==.Doodtanky:BAAALgADCgEJAQAAAA==.Doomvedas:BAAALgAECgYJCgAAAA==.',
Dr='Dracaena:BAABLgAECn8jAAQbAAkJrRkYBgDgAQAgAAgJkBT/GwDoAQAbAAgJtBcYBgDgAQAhAAUJQwizMQDiAAAAAA==.Draco:BAAALgAECgMJAwAAAA==.Dreadknìght:BAAALgAFFAQJAgAAAA==.Drekavach:BAAALgADCgcJEwAAAA==.Droidbick:BAAALgAFFAIJAwAAAA==.',
['Dâ']='Dâftmonk:BAAALgAECgQJBgABLgAECgkJDAAQAAAAAA==.',
Ee='Eevo:BAAALgAECgMJAwABLgAECggJFAAGAJEIAA==.',
El='Elaha:BAAALgAECgcJCQAAAA==.Elexann:BAAALgAECgkJAQAAAA==.Elibaba:BAAALgAFFAIJBAAAAA==.Elideady:BAAALgAFFAIJBAABLgAFFAIJBAAQAAAAAA==.Elinaa:BAAALgAECgIJAgAAAA==.Elindyl:BAAALgADCgEJAQAAAA==.Elleth:BAAALgADCgIJAgAAAA==.Elvishcheese:BAAALgAECgMJBgAAAA==.',
Em='Emojis:BAAALgAECgUJCQAAAA==.',
En='Endlessdh:BAACLgAFFH8IAAINAAMJCiIKBwDIAAANAAMJCiIKBwDIAAAuAAQKfx4AAg0ABwkyJJUJAMgCAA0ABwkyJJUJAMgCAAAA.',
Er='Eraserhead:BAAALgAECgYJEwABLgAFFAYJGQAXAHgjAA==.Eripaladin:BAAALgAECgIJAgAAAA==.Erissaria:BAAALgADCgEJAQAAAA==.',
Ev='Evening:BAAALgAECgMJBAAAAA==.Everbuddha:BAAALgAECgQJBgAAAA==.',
Ew='Ewa:BAAALgAECgMJBAAAAA==.Eww:BAABLgAECn8XAAIcAAcJyw/MaQA3AQAcAAcJyw/MaQA3AQAAAA==.',
Ez='Ezelia:BAACLgAFFH8JAAMYAAQJFRZfKwA/AQAYAAQJFRZfKwA/AQAHAAEJXwRTRQAyAAAuAAQKfxoAAxgACQl+FgxBAOsBABgACQl+FgxBAOsBAAcAAQlGCVeVADUAAAEuAAUUBwkvAAIAWBkA.',
Fa='Faelune:BAABLgAECn8aAAIPAAgJGwjBkwA2AQAPAAgJGwjBkwA2AQAAAA==.Faldir:BAAALgADCgYJBAABLgAFFAQJDgAcAJoYAA==.',
Fe='Ferndru:BAABLgAECn8iAAMIAAkJVhfFCQAHAgAIAAgJ4hjFCQAHAgAiAAcJahDeIwAMAQAAAA==.',
Fi='Fish:BAAALgAECgEJAgABLgAFFAQJCAAhAJ0XAA==.Fisticuffs:BAACLgAFFH8SAAIGAAYJdRBXFQCBAQAGAAYJdRBXFQCBAQAuAAQKfyIAAgYACAl3GAgbABkCAAYACAl3GAgbABkCAAAA.',
Fl='Flameshock:BAAALgAFFAIJBAAAAA==.Flowki:BAAALgADCgcJCwAAAA==.',
Fo='Forcespark:BAAALgAECgEJAQAAAA==.',
Fr='Fraserker:BAAALgAECgEJAQAAAA==.Frostradamus:BAAALgADCgkJCgAAAA==.',
Fu='Fullmoonride:BAAALgAECgUJCgAAAA==.Fumbll:BAAALgAECgkJCQAAAA==.Funkymajik:BAABLgAECn8aAAQDAAgJLg73JACEAQADAAgJLg73JACEAQACAAIJiAaJdQBTAAAdAAEJtQtOYgA0AAAAAA==.Furiosa:BAAALgADCgkJDgAAAA==.',
Ga='Gallywox:BAAALgADCgMJAwAAAA==.Ganin:BAABLgAECn8bAAIHAAYJUBU0QgBvAQAHAAYJUBU0QgBvAQAAAA==.Gankinyou:BAAALgADCgEJAQAAAA==.Garielyn:BAAALgADCgEJAQAAAA==.Garugala:BAACLgAFFH8MAAIYAAMJCRXlVADjAAAYAAMJCRXlVADjAAAuAAQKfysAAhgACQklGDctADMCABgACQklGDctADMCAAAA.',
Gd='Gdaycøb:BAAALgADCgYJBwAAAA==.',
Ge='Gengár:BAAALgAECgMJBgABLgAECggJEgAQAAAAAA==.Getfisted:BAAALgAECgYJBgAAAA==.',
Gh='Ghalorin:BAAALgAECgcJEQAAAA==.Ghiroza:BAABLgAECn9RAAQSAAkJ4R3fCAAzAgATAAkJ3B2RIABVAgASAAgJihbfCAAzAgAjAAMJkhZpHQCGAAAAAA==.',
Gi='Gigaevoker:BAABLgAECn8kAAIhAAgJcRawCwALAgAhAAgJcRawCwALAgAAAA==.Gigapaladin:BAAALgADCgQJBAAAAA==.Gingarthas:BAABLgAECn8iAAILAAkJPh0PMwAeAgALAAkJPh0PMwAeAgAAAA==.',
Gl='Glowingtoe:BAAALgAECgMJBQAAAA==.',
Go='Gogmazios:BAAALgADCgcJBwAAAA==.',
Gr='Gravytate:BAABLgAECn9XAAIfAAkJfA9VKQCLAQAfAAkJfA9VKQCLAQAAAA==.Griinn:BAABLgAECn8eAAIiAAkJSg5JGgBXAQAiAAkJSg5JGgBXAQAAAA==.Grimefiend:BAAALgAFFAIJAwAAAA==.Grimescene:BAAALgAECgIJAgAAAA==.Grimreapêr:BAAALgAECgEJAwAAAA==.Grow:BAAALgAFFAEJAQAAAA==.',
Gu='Guldannyboy:BAABLgAECn80AAMSAAkJSw2nCwBnAQASAAkJygynCwBnAQATAAkJFwdvaQBeAQAAAA==.Gumbö:BAAALgAECgcJCQABLgAECggJIAAKANUcAA==.',
Ha='Haides:BAAALgAECgIJAwAAAA==.Hammer:BAAALgAECgIJAgABLgAECgkJDAAQAAAAAA==.Hanokano:BAAALgAECgUJBQAAAA==.Hantore:BAAALgADCgMJAwAAAA==.Harmony:BAAALgAECgEJAQAAAA==.Harry:BAACLgAFFH8IAAIXAAMJohdoCgDoAAAXAAMJohdoCgDoAAAuAAQKfycAAxcACQljJOUBAD8DABcACQljJOUBAD8DABYABwnEGuMgABoCAAAA.',
He='Heartdh:BAABLgAECn8VAAMcAAgJkhL5SwCKAQAcAAgJkhL5SwCKAQANAAIJrxOGWwByAAAAAA==.Heisenbergg:BAAALgADCgIJAgAAAA==.Hellza:BAAALgAECgMJAwAAAA==.Hen:BAAALgAECgUJBQABLgAECgYJFQAMABAVAA==.Herpyprotect:BAAALgAFFAIJAwAAAA==.Herrion:BAACLgAFFH8kAAQTAAgJyBtICgAgAgATAAcJjBtICgAgAgASAAEJKx0KFgBgAAAjAAEJyB9KEwBbAAAuAAQKfy4AAxMACQn/IvkcAKgCABMACAn/IvkcAKgCABIABAmcJNMUAKQBAAAA.',
Hh='Hh:BAAALgAECgEJAQAAAA==.',
Ho='Holytanky:BAAALgAECgIJAgAAAA==.Hotspur:BAABLgAECn84AAIKAAgJaxDUOADDAQAKAAgJaxDUOADDAQAAAA==.',
Hu='Hukani:BAAALgAECgEJAwABLgAECggJFgACALEIAA==.Hunner:BAAALgAECgIJAgABLgAECggJFAAGAJEIAA==.Huskar:BAABLgAECn8gAAIUAAkJ4xRMJwAsAgAUAAkJ4xRMJwAsAgAAAA==.',
Hy='Hypoxi:BAAALgADCgYJCQAAAA==.',
Ig='Ignis:BAABLgAECn8cAAIkAAkJmR1fAQCDAgAkAAkJmR1fAQCDAgAAAA==.Ignitor:BAAALgADCgEJAQAAAA==.',
Ik='Ikari:BAABLgAECn9XAAISAAkJyhpdBQCBAgASAAkJyhpdBQCBAgAAAA==.',
Il='Illadoss:BAAALgADCgIJAgAAAA==.',
Im='Imntprepared:BAAALgAECgkJCQAAAA==.',
In='Incarnate:BAAALgAECgEJAgAAAA==.Incubis:BAAALgADCgIJAgAAAA==.Infectîon:BAAALgADCgYJBgAAAA==.Inferlock:BAAALgAECgMJAwAAAA==.Infernyos:BAAALgADCgcJCAAAAA==.Infernyoz:BAAALgADCggJCQAAAA==.',
Ir='Irithel:BAAALgAECgcJBQAAAA==.',
Is='Isohexene:BAAALgADCgYJBgAAAA==.',
It='Itchygrowth:BAAALgAFFAEJAQAAAA==.',
Iv='Ivygambina:BAAALgADCgYJBgAAAA==.Ivysore:BAAALgAECgUJBwAAAA==.',
Ja='Jasha:BAAALgADCgcJCwAAAA==.Jayy:BAABLgAECn8bAAILAAkJBRCKTAANAgALAAkJBRCKTAANAgAAAA==.',
Je='Jennatalia:BAAALgAECggJEgAAAA==.',
Ji='Jinkazamaz:BAAALgAFFAIJBAAAAA==.',
Jo='Joelsdruid:BAABLgAFFH8UAAIiAAUJXhwpBwBRAQAiAAUJXhwpBwBRAQAAAA==.Joelvoker:BAAALgAFFAIJAgABLgAFFAUJFAAiAF4cAA==.Joexotic:BAAALgAECgIJBwAAAA==.Jongwang:BAAALgAECgQJBwAAAA==.',
Ju='Jubjub:BAAALgAECgEJAgAAAA==.',
Ka='Kaaru:BAABLgAECn8lAAMDAAkJjBOPFAAYAgADAAkJehKPFAAYAgACAAUJExKGSAAXAQAAAA==.Kaiforst:BAAALgAECgQJBAABLgAECgkJNQAYADcZAA==.Kaihavocz:BAAALgAECgEJAwAAAA==.Kairon:BAABLgAECn81AAIYAAkJNxnMLAA1AgAYAAkJNxnMLAA1AgAAAA==.Kalysae:BAAALgADCgEJAQAAAA==.Katarinabluu:BAAALgAECgYJBgAAAA==.Kazakhthundr:BAAALgADCgYJBgAAAA==.',
Ke='Keeanuleaves:BAAALgADCgYJBwAAAA==.Keeanuweaves:BAAALgADCgEJAQAAAA==.Keeze:BAACLgAFFH8QAAIPAAQJbQnaXgATAQAPAAQJbQnaXgATAQAuAAQKfxgAAg8ACQkaE6BNANsBAA8ACQkaE6BNANsBAAAA.',
Ki='Kickstarter:BAAALgAECgYJEgAAAA==.Kiel:BAAALgAECgEJAQAAAA==.Kikiz:BAAALgADCgcJBwAAAA==.Killania:BAAALgADCgMJAwAAAA==.Kiwichaos:BAACLgAFFH8KAAINAAQJnQlfFwCuAAANAAQJnQlfFwCuAAAuAAQKfy4AAg0ACQlbG6QMAJcCAA0ACQlbG6QMAJcCAAAA.',
Kl='Klckyourass:BAAALgADCgYJCwAAAA==.',
Kn='Knox:BAAALgAECgUJCgAAAA==.',
Ko='Korner:BAAALgAECgIJAgAAAA==.',
Kr='Krazzul:BAAALgADCgYJBgAAAA==.Krellis:BAABLgAECn8XAAMFAAkJzxGkGgDDAQAFAAkJzxGkGgDDAQAGAAYJtRA8MQAzAQAAAA==.Kritikall:BAAALgADCgUJBQAAAA==.',
Ku='Kurö:BAAALgAECgEJAQAAAA==.',
Kv='Kvôthe:BAABLgAECn8YAAMLAAgJuAqHjgA0AQALAAgJtwiHjgA0AQAlAAMJzQeIJABwAAAAAA==.',
Ky='Kynnareth:BAAALgAFFAIJBAABLgAFFAYJDgADAHMLAA==.Kynralol:BAABLgAECn9BAAIPAAkJ5h/CDwDpAgAPAAkJ5h/CDwDpAgAAAA==.Kyunsun:BAAALgAECgMJAgAAAA==.',
['Ká']='Káiser:BAAALgAECggJEQAAAA==.',
La='Laenosh:BAABLgAECn8ZAAILAAUJDhJEwQDkAAALAAUJDhJEwQDkAAAAAA==.Lagalot:BAAALgAECgEJAQAAAA==.Laomoo:BAAALgAECgcJDgAAAA==.Laz:BAAALgADCgMJBQAAAA==.',
Le='Learning:BAABLgAECn8XAAIfAAcJEh9LGwA4AgAfAAcJEh9LGwA4AgAAAA==.Legham:BAAALgADCgkJDgAAAA==.Legolazz:BAABLgAECn8yAAMUAAkJ4B7OFQCOAgAUAAkJ4B7OFQCOAgARAAMJCBT7JQBvAAAAAA==.Lemins:BAAALgAECgMJAwAAAA==.Lemondruid:BAAALgAECgIJAgAAAA==.Lemonmelon:BAAALgAECgYJEwAAAA==.Lenatheplug:BAACLgAFFH8YAAMBAAYJIxoMAwDMAQABAAUJNSAMAwDMAQAZAAIJjQnKBQBgAAAuAAQKfyIAAwEACAmUJEQKAO0CAAEACAnbI0QKAO0CABkABwlAIt4DAIACAAAA.Lerust:BAAALgADCgcJBwAAAA==.',
Li='Liadrine:BAACLgAFFH8FAAIYAAQJdAxUPwAWAQAYAAQJdAxUPwAWAQAuAAQKfzAAAhgACQnjFxVAAO4BABgACQnjFxVAAO4BAAAA.Linus:BAAALgAECgYJBgABLgAFFAgJJAATAMgbAA==.Littleriver:BAABLgAECn8UAAIUAAgJvhirNgDUAQAUAAgJvhirNgDUAQAAAA==.',
Ll='Llewser:BAABLgAECn8aAAMPAAgJwhUGSADsAQAPAAgJwhUGSADsAQAkAAEJqgQBEgAqAAAAAA==.',
Lo='Loathe:BAAALgAECgEJAgAAAA==.Loistiah:BAABLgAFFH8IAAILAAMJZhlbewDnAAALAAMJZhlbewDnAAAAAA==.Lothaof:BAABLgAECn8sAAIYAAkJ6RLwUwC1AQAYAAkJ6RLwUwC1AQAAAA==.Louisvuitton:BAAALgAECgUJDwAAAA==.',
Lp='Lpayn:BAAALgADCgEJAQAAAA==.',
Lu='Lugroth:BAAALgAFFAMJAwABLgAFFAgJJAATAMgbAA==.Lunana:BAAALgAECgcJEgAAAA==.',
Ly='Lychiee:BAAALgAECgcJEQAAAA==.',
['Lì']='Lìnkinbark:BAAALgAECgMJAwAAAA==.',
Ma='Madara:BAAALgAECgEJAgAAAA==.Magesorry:BAAALgADCgUJBQAAAA==.Magicmon:BAAALgADCgkJDgAAAA==.Maize:BAABLgAECn8iAAMDAAgJMBvHEABGAgADAAgJMBvHEABGAgACAAMJhgvTZwCOAAAAAA==.Makima:BAABLgAFFH8FAAIJAAUJmQ7qJQDUAAAJAAUJmQ7qJQDUAAABLgAFFAUJLAAJAMEbAA==.Malikai:BAAALgADCgcJDAAAAA==.Marcymonk:BAAALgADCgEJAQAAAA==.Marcyon:BAABLgAECn8ZAAIcAAYJqAlkpgC3AAAcAAYJqAlkpgC3AAAAAA==.Marywinston:BAAALgAFFAEJAQABLgAFFAIJBgAMAFMUAA==.',
Mc='Mchèalz:BAABLgAECn8VAAQDAAgJRAidNgATAQADAAgJRAidNgATAQACAAQJxAFFaQCIAAAdAAIJOwF0ZgAsAAAAAA==.',
Me='Melonlemonza:BAAALgADCgQJBAAAAA==.Mentok:BAAALgAECgYJCwAAAA==.Merchei:BAAALgAECgUJBgAAAA==.Meruen:BAACLgAFFH8HAAIcAAQJ9w8iPQAUAQAcAAQJ9w8iPQAUAQAuAAQKfyoAAhwACQknG0cXAHYCABwACQknG0cXAHYCAAAA.',
Mi='Miss:BAAALgAECgEJAQAAAA==.Mistie:BAAALgAECgEJAQABLgAECggJEQAQAAAAAA==.Mitymorphin:BAAALgADCgEJAQAAAA==.',
Mo='Mobility:BAAALgAFFAEJAQAAAA==.Moistpole:BAAALgADCgQJBAAAAA==.Momock:BAAALgAECgQJBAAAAA==.Mongk:BAABLgAECn8UAAIGAAgJkQibNQAZAQAGAAgJkQibNQAZAQAAAA==.Monscustodes:BAABLgAECn8kAAIPAAkJVw8mWgC3AQAPAAkJVw8mWgC3AQAAAA==.Monstersauce:BAAALgAFFAIJBAAAAA==.Mookin:BAAALgAECgcJCAAAAA==.Moospoon:BAABLgAECn8zAAIYAAgJKRQIaQCDAQAYAAgJKRQIaQCDAQAAAA==.Mooudini:BAAALgAECgMJAwAAAA==.Moounka:BAABLgAECn9FAAIEAAkJcxPbFQDrAQAEAAkJcxPbFQDrAQAAAA==.Morphio:BAABLgAECn9LAAMUAAkJLyUqAgBnAwAUAAkJLyUqAgBnAwARAAUJCxOaTAAfAQAAAA==.Mostakrakish:BAAALgADCgEJAQAAAA==.',
Mu='Muddles:BAABLgAECn9EAAIEAAkJUBjhDwAuAgAEAAkJUBjhDwAuAgAAAA==.Murius:BAACLgAFFH8JAAILAAMJkQSdmQC5AAALAAMJkQSdmQC5AAAuAAQKfzIAAgsACQlEF2IwACkCAAsACQlEF2IwACkCAAAA.',
My='Mysterio:BAAALgAFFAEJAwAAAA==.',
Na='Naendria:BAAALgAECgMJBAAAAA==.Naga:BAAALgAECgIJAgAAAA==.Nahaza:BAAALgAECgEJAgAAAA==.',
Ne='Nelena:BAAALgADCgEJAQAAAA==.',
Ni='Nickdoom:BAAALgAECgUJEwAAAA==.Nigella:BAABLgAECn8WAAMCAAgJsQiyNQAUAQACAAgJsQiyNQAUAQADAAEJ6wErdwAhAAAAAA==.Nikola:BAABLgAECn8oAAQKAAkJoxVnNwDKAQAKAAkJoxVnNwDKAQAiAAUJOBbfFQAUAQAJAAQJfQ9/VADUAAAAAA==.Nimro:BAACLgAFFH8XAAIaAAYJdxXBCAB7AQAaAAYJdxXBCAB7AQAuAAQKfygAAhoACQmPH6ADABsDABoACQmPH6ADABsDAAAA.Niub:BAABLgAECn8nAAImAAgJ/BHrLQCGAQAmAAgJ/BHrLQCGAQAAAA==.',
No='Nofate:BAAALgADCgEJAQAAAA==.Noirebringer:BAAALgAFFAEJAQAAAA==.Nongbonnie:BAAALgAECgIJAgAAAA==.',
Nt='Ntrldrake:BAAALgADCgEJAgABLgAECgkJJAAPAFcPAA==.',
Nu='Nueng:BAAALgADCgEJAQAAAA==.Nuferax:BAABLgAECn8aAAIOAAgJGiFrAwCPAgAOAAgJGiFrAwCPAgAAAA==.Nuiiwarx:BAAALgADCgEJAQAAAA==.Nulledhacz:BAAALgADCgEJAQAAAA==.Numbrethree:BAACLgAFFH8TAAIGAAQJ/hESJgDqAAAGAAQJ/hESJgDqAAAuAAQKf0MAAgYACAmcGAAdAAoCAAYACAmcGAAdAAoCAAAA.',
Ob='Obbi:BAACLgAFFH8UAAIZAAQJSiYVAQDKAQAZAAQJSiYVAQDKAQAuAAQKfxoAAxkACQkpIA0BAAgDABkACQkpIA0BAAgDACcAAQk/JHAZAGgAAAAA.',
Oh='Ohaither:BAAALgAECgQJBAAAAA==.',
Oi='Oirth:BAAALgADCgIJAgAAAA==.',
Ok='Okiji:BAAALgAECgkJEwAAAA==.',
Or='Orinocco:BAAALgAECgEJAwAAAA==.Orobas:BAAALgAECgkJCwAAAA==.',
Pa='Pakaww:BAAALgAECgIJAwAAAA==.Palimathrus:BAAALgAECgUJCAAAAA==.Palliative:BAABLgAECn9FAAMHAAkJMSKvBQAjAwAHAAkJMSKvBQAjAwAYAAQJLwXjAQGVAAAAAA==.Pallidnim:BAABLgAFFH8HAAIMAAQJgRG+IAC7AAAMAAQJgRG+IAC7AAAAAA==.Papager:BAAALgAFFAIJAgAAAA==.',
Pe='Pea:BAAALgAECgcJEAAAAA==.Perish:BAAALgAECggJDQABLgAECgkJRAAEAFAYAA==.',
Ph='Phatmonk:BAACLgAFFH8XAAIFAAUJkiaEAwDMAQAFAAUJkiaEAwDMAQAuAAQKfzcAAwUACQn4JHACADoDAAUACQn4JHACADoDAAYABwlzIJIXADcCAAAA.Phatrogue:BAABLgAFFH8HAAIBAAMJjB3mHQAJAQABAAMJjB3mHQAJAQABLgAFFAUJFwAFAJImAA==.',
Pi='Piewpiew:BAAALgADCgcJCgAAAA==.Pix:BAACLgAFFH8cAAMdAAcJZR3XAgDHAQAdAAcJZR3XAgDHAQADAAUJvQyQGQBaAQAuAAQKfzYAAh0ACQk5JcABAEsDAB0ACQk5JcABAEsDAAAA.',
Pl='Pleasuremax:BAABLgAECn8aAAIUAAgJLBXXOwDZAQAUAAgJLBXXOwDZAQAAAA==.Plex:BAABLgAECn8/AAIIAAkJRRoeBgBoAgAIAAkJRRoeBgBoAgAAAA==.',
Po='Poofyfeesh:BAAALgAFFAEJAQAAAA==.Poogie:BAAALgADCgYJBgABLgAECgMJBQAQAAAAAA==.Popshot:BAABLgAECn8eAAIRAAYJ5xIiRQBBAQARAAYJ5xIiRQBBAQAAAA==.Portalhouse:BAAALgAECgEJAQAAAA==.',
Pr='Praxis:BAACLgAFFH8KAAIaAAMJWRL4FwDBAAAaAAMJWRL4FwDBAAAuAAQKfyMAAhoACAmKEI4VAIQBABoACAmKEI4VAIQBAAAA.Preast:BAAALgAECgcJBwABLgAECggJFAAGAJEIAA==.Procist:BAAALgAECgkJEAABLgAECgkJMQAWAMQiAA==.',
Py='Pyrusdk:BAABLgAECn8ZAAILAAkJgQ4hVQCyAQALAAkJgQ4hVQCyAQAAAA==.Pyrusdruid:BAABLgAECn8WAAIKAAkJJwLLkwB4AAAKAAkJJwLLkwB4AAAAAA==.',
Qo='Qop:BAAALgAFFAEJAQAAAA==.',
Qu='Quesarah:BAAALgADCgEJAQABLgAECgQJBAAQAAAAAA==.',
Qw='Qweffor:BAAALgAECgUJBQABLgAECggJFgALAB0YAA==.',
Ra='Rainbowkelly:BAAALgAECgQJBAAAAA==.Raìn:BAACLgAFFH8GAAILAAIJOQ+kvACLAAALAAIJOQ+kvACLAAAuAAQKfxQAAgsACAnYFdNJANIBAAsACAnYFdNJANIBAAAA.',
Re='Reapy:BAACLgAFFH8MAAILAAMJ+g6JiADWAAALAAMJ+g6JiADWAAAuAAQKfxQAAgsABwlbEKumAAwBAAsABwlbEKumAAwBAAAA.Recruitqt:BAABLgAECn8cAAMHAAUJtBoPOgCRAQAHAAUJtBoPOgCRAQAYAAEJURgvTQFHAAAAAA==.Reiayanami:BAABLgAECn8fAAIPAAgJfA9QeABtAQAPAAgJfA9QeABtAQAAAA==.',
Ri='Ripandtear:BAABLgAECn8bAAMKAAkJzBYTJwAEAgAKAAkJzBYTJwAEAgAIAAEJFQZ6NgAsAAAAAA==.',
Ro='Roguewan:BAAALgAFFAIJAgAAAA==.Rolâyne:BAAALgADCgkJDgAAAA==.Roninn:BAACLgAFFH8GAAIKAAIJihcpQwCXAAAKAAIJihcpQwCXAAAuAAQKfzQAAgoACQlVIdIEAF8DAAoACQlVIdIEAF8DAAAA.Ronlock:BAABLgAECn8VAAMTAAYJ8xD9nQAdAQATAAUJ8xD9nQAdAQASAAEJAAABagA+AAABLgAECgcJNgANAG8aAA==.Royaltits:BAAALgADCgIJAgAAAA==.',
Rs='Rsi:BAAALgAECgQJBAAAAA==.',
Ry='Rynaea:BAAALgAECgUJBgAAAA==.',
['Rï']='Rïmuru:BAAALgADCgcJCwAAAA==.',
['Rô']='Rôlayne:BAABLgAECn8ZAAImAAgJdQuQOwBCAQAmAAgJdQuQOwBCAQAAAA==.',
Sa='Sadakos:BAAALgAFFAMJAwAAAA==.Salvare:BAABLgAECn8lAAMZAAkJhhhwAwCVAgAZAAkJfRhwAwCVAgAnAAIJRRCiGABxAAAAAA==.Sappy:BAAALgAECgQJBAAAAA==.Sauron:BAAALgADCgEJAQABLgAFFAQJEQATACgUAA==.',
Sb='Sbf:BAABLgAFFH8ZAAIgAAcJ4RYrCgAUAgAgAAcJ4RYrCgAUAgABLgAFFAgJOQAPADQaAA==.',
Sc='Scalamander:BAAALgAECgcJAgAAAA==.Sciohunter:BAABLgAFFH8FAAINAAIJIAw9HACAAAANAAIJIAw9HACAAAAAAA==.Scioscioz:BAACLgAFFH8MAAIKAAQJ0BCNJwAMAQAKAAQJ0BCNJwAMAQAuAAQKfyAAAwoABwnOFOI7ALUBAAoABwnOFOI7ALUBAAkAAglnEAJsAHAAAAAA.Scwisgar:BAAALgAECgkJDQAAAA==.',
Se='Sedge:BAAALgAFFAIJBAAAAA==.Sephire:BAABLgAECn8eAAIYAAkJPASluAD2AAAYAAkJPASluAD2AAAAAA==.Sermazule:BAAALgADCgcJEQAAAA==.Sewerface:BAABLgAECn8VAAMMAAYJEBWaHgBTAQAMAAYJEBWaHgBTAQALAAMJLAScAQF2AAAAAA==.',
Sh='Shadonir:BAAALgAECgQJBAAAAA==.Shadowind:BAACLgAFFH8aAAIUAAUJKh91HQBkAQAUAAUJKh91HQBkAQAuAAQKfy8AAxEACQmGHn4dADsCABEACAlEGX4dADsCABQABQlkHU1VAIsBAAAA.Shaft:BAAALgAECgEJAQAAAA==.Shallotte:BAABLgAECn8YAAMjAAgJdRDoCwB7AQAjAAcJABLoCwB7AQATAAcJoggyiwAaAQAAAA==.Shammalxs:BAABLgAFFH8GAAIfAAUJSQS/HgAKAQAfAAUJSQS/HgAKAQAAAA==.Shamoc:BAABLgAECn8xAAMWAAkJxCJIBQBKAwAWAAkJxCJIBQBKAwAfAAYJohESSQAjAQAAAA==.Shampooing:BAACLgAFFH8IAAIfAAMJLhC/KwDDAAAfAAMJLhC/KwDDAAAuAAQKfygAAh8ACQk3F1cUAC8CAB8ACQk3F1cUAC8CAAAA.Sharpknife:BAABLgAFFH8NAAMUAAMJhRYQUQDeAAAUAAMJRhEQUQDeAAAoAAIJ3Rs3HwC1AAAAAA==.Shaz:BAAALgADCgQJBAAAAA==.Shivd:BAAALgAECgIJAgAAAA==.Shorpus:BAABLgAECn8cAAQfAAkJ9h5GJACsAQAXAAYJNx8hCgAwAgAfAAcJixpGJACsAQAWAAcJCwj6XQATAQAAAA==.',
Si='Sicckbrew:BAABLgAECn8hAAIFAAkJaiH+CQDYAgAFAAkJaiH+CQDYAgABLgAFFAQJCAAiABcNAA==.Sickin:BAABLgAFFH8IAAIiAAQJFw2KEQDOAAAiAAQJFw2KEQDOAAAAAA==.Sinniestro:BAAALgAECgEJAgAAAA==.',
Sk='Skizzyy:BAAALgAECgMJAwABLgAECgcJEAAQAAAAAA==.',
Sl='Slayedurmrs:BAAALgAECgQJBQAAAA==.Slok:BAAALgAECgEJAQAAAA==.Slowpoke:BAABLgAFFH8sAAIJAAUJwRvECABXAQAJAAUJwRvECABXAQAAAA==.',
Sm='Smacedh:BAABLgAECn8WAAIcAAkJChKUYgB6AQAcAAkJChKUYgB6AQAAAA==.Smesher:BAAALgAECgcJEwAAAA==.',
Sn='Sneakyfella:BAAALgAFFAEJAQAAAA==.',
So='Solidus:BAABLgAFFH8GAAIYAAQJmhSlOAAjAQAYAAQJmhSlOAAjAQAAAA==.Sorgaath:BAAALgADCgcJBwAAAA==.',
Sp='Spaklehooves:BAAALgADCgYJBgAAAA==.Spicoli:BAAALgADCgEJAQAAAA==.Spiral:BAAALgAECgQJBwAAAA==.Spoonfed:BAAALgAECgQJCwAAAA==.',
Sq='Squiish:BAACLgAFFH8YAAMJAAgJ/hjyBQAAAgAJAAcJ/RfyBQAAAgAKAAUJkAXfIwAhAQAuAAQKfxoAAgkABwmoJfALANkCAAkABwmoJfALANkCAAAA.',
St='Stavrophore:BAAALgAECgEJBQAAAA==.Stickydruid:BAAALgAECgIJBgABLgAECgkJTgAdALohAA==.Stickyholes:BAAALgAECgIJAgABLgAECgkJTgAdALohAA==.Stickymonk:BAAALgAECgEJBAABLgAECgkJTgAdALohAA==.Stickypriest:BAABLgAECn9OAAMdAAkJuiFLBwDCAgAdAAkJuiFLBwDCAgACAAEJExiTeQBCAAAAAA==.Stipe:BAAALgADCgUJCAAAAA==.Stove:BAAALgADCgcJCwAAAA==.Strawhats:BAACLgAFFH85AAIPAAgJNBogAwBMAgAPAAgJNBogAwBMAgAuAAQKf0IAAg8ACQkyJWcCANgDAA8ACQkyJWcCANgDAAAA.Streamliner:BAABLgAECn8/AAMBAAkJJBvNCQBxAgABAAkJJBvNCQBxAgAnAAMJ1gdKCwCNAAAAAA==.Stuunks:BAAALgAECgYJCwAAAA==.',
Su='Surv:BAACLgAFFH8JAAIoAAQJyBiVDgBGAQAoAAQJyBiVDgBGAQAuAAQKfxwAAxEABwk/IHsJAMcBACgABwk6G04YANABABEABglXH3sJAMcBAAAA.Sustangelia:BAABLgAECn8bAAMLAAkJbxh6UAAAAgALAAkJbxh6UAAAAgAlAAEJBw8rKwBIAAAAAA==.',
Sw='Swordkiller:BAAALgAECgcJBgAAAA==.',
Sx='Sxy:BAAALgAECgYJBwABLgAECgkJPwAIAEUaAA==.',
Sy='Sy:BAAALgAECgcJEAAAAA==.Synthesis:BAABLgAECn8hAAIKAAgJoyVkBQBWAwAKAAgJoyVkBQBWAwAAAA==.',
Ta='Tae:BAAALgADCgUJBQAAAA==.Taichee:BAAALgADCgUJBQAAAA==.Talas:BAAALgAECgQJBQAAAA==.Talletalanot:BAACLgAFFH8JAAIhAAMJWgnGHQCqAAAhAAMJWgnGHQCqAAAuAAQKfy4AAiEACQkbIEAFALQCACEACQkbIEAFALQCAAAA.Tandryan:BAAALgAECgQJBwAAAA==.Tanukiji:BAABLgAECn8nAAICAAkJFhyoDACDAgACAAkJFhyoDACDAgAAAA==.',
Td='Tdh:BAAALgADCgMJAwAAAA==.Tdk:BAABLgAECn8WAAMLAAgJqhSHqgAGAQALAAcJzhWHqgAGAQAMAAEJ0Q3ZUAA6AAAAAA==.',
Te='Tee:BAAALgADCgUJBQAAAA==.Terry:BAAALgAECgEJAQAAAA==.Tesarion:BAABLgAECn8WAAILAAgJHRgYUQC9AQALAAgJHRgYUQC9AQAAAA==.Testalatesta:BAABLgAECn9KAAMHAAkJBSW6AAC/AwAHAAkJBSW6AAC/AwAYAAEJmwipiQEpAAAAAA==.',
Th='Tharien:BAAALgADCgIJAgAAAA==.Thovir:BAAALgADCgEJAQAAAA==.',
Ti='Tiberian:BAAALgADCgIJAgAAAA==.Tinyvolt:BAAALgAECggJCwAAAA==.',
Tm='Tmonk:BAAALgAECgkJDgAAAA==.',
To='Toinahun:BAAALgAECgQJBAAAAA==.Tookersoul:BAAALgAECgEJAQAAAA==.Totemea:BAAALgAECgYJCQAAAA==.Totems:BAACLgAFFH8RAAIWAAYJSRn7DADSAQAWAAYJSRn7DADSAQAuAAQKfxUAAhYACAkuG6QbAFQCABYACAkuG6QbAFQCAAAA.Totemteabag:BAAALgAECgEJAQAAAA==.Totemîxx:BAABLgAECn8wAAMfAAkJnxnvEABVAgAfAAkJnxnvEABVAgAWAAQJYQ23fgCYAAAAAA==.Touchhy:BAAALgAECgEJAQAAAA==.',
Tr='Trainz:BAAALgADCgcJBwAAAA==.Trass:BAACLgAFFH8PAAMTAAMJIBtUVwACAQATAAMJIBtUVwACAQASAAEJERBSIABLAAAuAAQKf0AAAxMACQndIHoUAJ8CABMACQndIHoUAJ8CABIAAwkqERxEAKUAAAAA.Trays:BAAALgADCgEJAQAAAA==.Trisse:BAABLgAECn8nAAIcAAgJog8BWwBeAQAcAAgJog8BWwBeAQAAAA==.',
Tu='Tuzz:BAACLgAFFH8IAAIlAAMJWxXvDgDnAAAlAAMJWxXvDgDnAAAuAAQKfysAAiUACQljIWIBAO4CACUACQljIWIBAO4CAAAA.',
Tw='Twongle:BAAALgADCgIJAgABLgAECggJGgAPAMIVAA==.',
Ty='Tyden:BAAALgAECgYJEAAAAA==.Tyrmac:BAAALgAECgUJBgAAAA==.',
Va='Vael:BAAALgAECgYJCgAAAA==.Valerie:BAAALgAECgUJBwAAAA==.Valkyrra:BAAALgAECgQJBAAAAA==.Varaestia:BAAALgAECgQJBAAAAA==.Varg:BAAALgADCgEJAQABLgADCgEJAQAQAAAAAA==.Vargmk:BAAALgADCgEJAQAAAA==.Vargps:BAAALgADCgEJAQAAAA==.',
Ve='Velithara:BAAALgAECgcJBwAAAA==.Venestra:BAAALgAFFAMJAwAAAA==.Verdict:BAACLgAFFH8JAAIYAAQJzBs2KABJAQAYAAQJzBs2KABJAQAuAAQKfxgAAhgACAloHlsgAKoCABgACAloHlsgAKoCAAAA.Vermeil:BAAALgAECgMJAwAAAA==.Vermillion:BAACLgAFFH8XAAIYAAYJpxqYIABhAQAYAAYJpxqYIABhAQAuAAQKfyIAAhgACQnuID8OAN0CABgACQnuID8OAN0CAAAA.',
Vi='Vib:BAAALgAECgEJAQAAAA==.Viegas:BAACLgAFFH8FAAIUAAIJnRLWcACMAAAUAAIJnRLWcACMAAAuAAQKfxsAAhQABwkjHK4gAEECABQABwkjHK4gAEECAAAA.Vincent:BAABLgAECn8hAAIPAAYJsB6ZfgDUAQAPAAYJsB6ZfgDUAQAAAA==.Vinijr:BAAALgAECgEJAgAAAA==.Vivamax:BAAALgAECgEJAQAAAA==.',
Vo='Voidthotnimz:BAAALgADCgcJBgABLgAFFAUJFAAgAEILAA==.Volthic:BAAALgAECgQJBAAAAA==.Voltormu:BAAALgAECgMJBgAAAA==.Vore:BAABLgAECn8fAAIcAAkJeBWlMgDlAQAcAAkJeBWlMgDlAQAAAA==.',
Vr='Vrag:BAACLgAFFH8IAAILAAMJ8wP31QBxAAALAAMJ8wP31QBxAAAuAAQKfzQAAgsACQmQF5g1ABUCAAsACQmQF5g1ABUCAAAA.',
['Vè']='Vè:BAABLgAECn8bAAQMAAkJQBFUGACFAQAMAAkJBQ9UGACFAQALAAcJ/BCvcgBqAQAlAAEJ5ASXOQARAAAAAA==.',
['Vê']='Vêê:BAAALgAECgQJBgABLgAECgkJGwAMAEARAA==.',
Wa='Warslaw:BAACLgAFFH8XAAIMAAUJ6yI0CwCJAQAMAAUJ6yI0CwCJAQAuAAQKfyAAAgwACQlVI18FAOsCAAwACQlVI18FAOsCAAAA.Warth:BAAALgADCgEJAQAAAA==.Waterwater:BAAALgAECgYJCgAAAA==.Waterwaterz:BAACLgAFFH8SAAIPAAQJcRkYTAA3AQAPAAQJcRkYTAA3AQAuAAQKfzkAAg8ACAnVHOQ0AJ8CAA8ACAnVHOQ0AJ8CAAAA.',
Wc='Wchin:BAABLgAECn8aAAIVAAgJ0yA4AQCTAgAVAAgJ0yA4AQCTAgAAAA==.Wchinz:BAABLgAECn8WAAIdAAkJbiCPDgCaAgAdAAkJbiCPDgCaAgAAAA==.',
We='Wedlock:BAAALgADCgIJAgAAAA==.Welcumshot:BAABLgAFFH8LAAIoAAMJ3RE2GgDrAAAoAAMJ3RE2GgDrAAAAAA==.Wenkar:BAAALgAECgUJDAABLgAECgkJUQASAOEdAA==.',
Wh='Whaka:BAAALgAECgIJAgABLgAFFAUJDgAhADUMAA==.',
Wi='Wid:BAAALgAECgkJBQAAAA==.Windsabre:BAAALgADCgIJAgAAAA==.Wingz:BAAALgAFFAEJAgAAAA==.',
Wo='Woregeonnick:BAABLgAECn8fAAITAAcJVxEhZwCWAQATAAcJVxEhZwCWAQAAAA==.Woshiren:BAAALgAECgYJBgAAAA==.Wozzie:BAAALgADCggJCAAAAA==.',
Wy='Wyvern:BAAALgAECgcJEAAAAA==.',
['Wä']='Wärrior:BAAALgADCgMJAwAAAA==.',
Xa='Xanadu:BAAALgADCgIJAgAAAA==.',
Xd='Xd:BAAALgAFFAEJAQAAAA==.',
Xe='Xerxexy:BAAALgAECgQJCwAAAA==.',
Xi='Xiaodingdang:BAAALgAECgQJBAAAAA==.Xiera:BAABLgAECn8YAAIPAAgJbAn/jABCAQAPAAgJbAn/jABCAQAAAA==.',
Ya='Yaminosaishi:BAAALgAECgYJBwAAAA==.Yaoyôrozu:BAAALgADCgkJFAAAAA==.Yasuô:BAAALgADCgMJAwAAAA==.Yatelega:BAAALgADCgIJAgABLgAECgcJHwATAFcRAA==.Yazdorzarn:BAAALgAECgcJDAAAAA==.',
Yo='Yozzao:BAAALgAECgQJDAAAAA==.',
Yu='Yueli:BAAALgAFFAEJAQABLgAFFAgJGAAJAP4YAA==.',
Za='Zaaniz:BAABLgAECn8lAAQYAAkJ8BtvHwCvAgAYAAkJ8BtvHwCvAgAHAAQJgwk5VwDAAAAeAAIJ+Q0wOQBgAAAAAA==.',
Ze='Zenestra:BAAALgAECgkJAQABLgAFFAMJAwAQAAAAAA==.Zenshui:BAAALgAECgYJCQAAAA==.Zephyruss:BAAALgADCgEJAQAAAA==.Zervis:BAAALgAECgIJAgAAAA==.Zeyra:BAAALgAECgYJDAAAAA==.',
Zi='Zinako:BAAALgAECgEJAQAAAA==.',
Zo='Zocalo:BAAALgAECgUJBQAAAA==.',
['Èa']='Èasymode:BAAALgADCgEJAQAAAA==.',
['Ód']='Ódyssey:BAABLgAECn8ZAAIXAAgJCRKPDgCqAQAXAAgJCRKPDgCqAQAAAA==.',
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
