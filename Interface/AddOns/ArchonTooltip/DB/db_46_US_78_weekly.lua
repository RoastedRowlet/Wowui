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
local provider = {region='US',realm='Dreadmaul',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abbathdoom:BAABLgAECn8YAAIBAAgJTw21JwBUAQABAAgJTw21JwBUAQAAAA==.Abyss:BAAALgAECgEJAQAAAA==.',
Ae='Aedaris:BAABLgAECn9XAAMCAAkJPCA5EABjAgACAAcJDiE5EABjAgADAAYJHhl/KgB/AQAAAA==.Ael:BAAALgAECgEJAQAAAA==.Aethalides:BAAALgAECgYJDwAAAA==.',
Al='Alandrias:BAAALgAECgkJAQAAAA==.Alf:BAAALgAECgEJAQAAAA==.Alithial:BAAALgAECgEJAQAAAA==.Aloremirin:BAAALgADCgUJBQAAAA==.Altaria:BAABLgAFFH8gAAQEAAcJRxzNAwD1AQAEAAYJHCHNAwD1AQAFAAUJKR3CHQA2AQAGAAEJZwl4WwBBAAAAAA==.Alvv:BAAALgADCgMJBQAAAA==.Alvz:BAAALgADCgMJAwAAAA==.',
Am='Ametrigos:BAAALgAECgEJAwABLgAECgkJJAAHAAggAA==.',
An='Anouke:BAAALgADCgIJAgAAAA==.Anserion:BAAALgADCgMJAwAAAA==.Anvious:BAAALgAECgcJDAAAAA==.',
Aq='Aquilea:BAABLgAECn8fAAMIAAkJJBIKDgDQAQAIAAkJJBIKDgDQAQAJAAEJhgbEmAAmAAAAAA==.',
Ar='Arcfuldodger:BAAALgAECgEJAgAAAA==.Artais:BAABLgAECn8gAAIKAAgJ1Rx8FgCCAgAKAAgJ1Rx8FgCCAgAAAA==.Artzlayer:BAACLgAFFH8IAAILAAMJrxszjwDoAAALAAMJrxszjwDoAAAuAAQKfzAAAwsACQlXI+cOAPMCAAsACQlXI+cOAPMCAAwAAQkAAGFuAAAAAAAA.Aríes:BAABLgAECn9RAAMNAAkJ3xpoDABcAgANAAkJ3xpoDABcAgAOAAEJGAm1NQAsAAAAAA==.',
As='Ashbourne:BAAALgADCgcJCwAAAA==.',
Au='Autumnnight:BAAALgAECgEJAwAAAA==.',
Aw='Aw:BAAALgAECgYJEQABLgAFFAcJHQAPAMQZAA==.Awry:BAECLgAFFH8LAAILAAQJ2hYdXgA1AQALAAQJ2hYdXgA1AQAuAAQKfzIAAgsACQkcIlQMAAkDAAsACQkcIlQMAAkDAAAA.Awuuga:BAAALgAECgEJAQABLgAECgYJEgAQAAAAAA==.Aww:BAACLgAFFH8dAAIPAAcJxBlnGwAaAgAPAAcJxBlnGwAaAgAuAAQKfyAAAg8ACAljGwV/ANMBAA8ACAljGwV/ANMBAAAA.',
Az='Azamalaza:BAABLgAECn8nAAIRAAgJbyLpBQA6AgARAAgJbyLpBQA6AgAAAA==.Azmo:BAACLgAFFH8PAAQSAAYJChIXDADYAAATAAYJUAr3XAAJAQASAAMJDRYXDADYAAAUAAEJ6xP0HwBPAAAuAAQKfyYAAxIACAkvIcECANYCABIACAmJHcECANYCABMABgk9HL1gAKcBAAAA.Azulon:BAAALgADCgUJBQABLgAECggJGgADAOkZAA==.Azyrt:BAAALgAECgQJBAABLgAECggJIAAKANUcAA==.',
Ba='Badds:BAABLgAECn8UAAIHAAkJgRb9EwBtAgAHAAkJgRb9EwBtAgAAAA==.Ballona:BAAALgADCgUJBQAAAA==.Baløø:BAAALgAECgEJAQAAAA==.Barad:BAAALgAECgEJBAAAAA==.Batrick:BAAALgADCgcJBwAAAA==.Baulric:BAAALgAECgEJAQAAAA==.Bawls:BAABLgAFFH8HAAMFAAIJ7gZuTABrAAAFAAIJ7gZuTABrAAAEAAEJrAPgRgAuAAAAAA==.',
Be='Beastroll:BAABLgAECn8XAAIVAAcJChWjXACLAQAVAAcJChWjXACLAQAAAA==.Beefrod:BAAALgADCgEJAQAAAA==.Beenis:BAAALgADCgUJBQABLgAFFAQJDgALADEcAA==.Belerick:BAABLgAFFH8JAAIJAAMJnQqfDwDoAAAJAAMJnQqfDwDoAAAAAA==.Belphine:BAAALgAECgYJCAAAAA==.',
Bi='Bicksmage:BAACLgAFFH8PAAIPAAQJXhGaYgAnAQAPAAQJXhGaYgAnAQAuAAQKfxQAAw8ACAnyF4loAKgBAA8ACAnyF4loAKgBABYAAQmLBysgAC8AAAAA.Bigdaddylock:BAACLgAFFH8XAAQTAAcJxRpEMAB8AQATAAYJgxhEMAB8AQAUAAEJ+CNKFABpAAASAAEJGBxdGwBaAAAuAAQKfyUAAxIACQnoJE4IAD4CABMACAkzI6IuAFICABIABgm1Ik4IAD4CAAAA.Biluman:BAAALgAECgQJBAAAAA==.Biodeath:BAAALgADCgUJBQAAAA==.Biopally:BAAALgADCgYJDQAAAA==.Biorogue:BAAALgADCgYJDAAAAA==.Bishope:BAABLgAECn8aAAIDAAgJ6RndDwBwAgADAAgJ6RndDwBwAgAAAA==.',
Bl='Bllizard:BAAALgAECgEJAQAAAA==.Bloodache:BAAALgADCgcJDgABLgAECgUJGQALAA4SAA==.Bluecar:BAAALgAECgYJCAAAAA==.',
Bo='Bohica:BAAALgAECgIJBQAAAA==.Bombdiggity:BAABLgAECn8+AAIDAAkJZh0HBwALAwADAAkJZh0HBwALAwAAAA==.Bonnierot:BAAALgAECgUJCgAAAA==.',
Br='Brecciana:BAAALgADCgUJBQAAAA==.Brewjitsu:BAABLgAECn9IAAIFAAkJkR1FCQCcAgAFAAkJkR1FCQCcAgAAAA==.Brick:BAACLgAFFH8JAAMFAAMJeSFTJAAUAQAFAAMJeSFTJAAUAQAGAAEJ9BVaXQA8AAAuAAQKfx8AAgUABwl6HuQaAC0CAAUABwl6HuQaAC0CAAEuAAUUCAknABMAyBsA.Brongakill:BAAALgADCgYJBgAAAA==.Bräinfreeze:BAAALgAECgkJBwAAAA==.',
Bu='Buffy:BAAALgAECgEJAgAAAA==.Bumble:BAAALgADCgYJBgABLgAFFAgJJwACADkbAA==.Bundalock:BAAALgADCgYJEQAAAA==.',
Ca='Cakebringer:BAAALgAECgcJEgAAAA==.Caroshi:BAACLgAFFH8MAAIPAAQJawSVcwD8AAAPAAQJawSVcwD8AAAuAAQKfygAAg8ACQmzDediALYBAA8ACQmzDediALYBAAAA.',
Ce='Cell:BAAALgAECgUJCAABLgAECgkJIAAVAOMUAA==.Ceridwen:BAAALgADCgEJAQAAAA==.',
Ch='Charlotte:BAAALgAECgMJDAAAAA==.Cheto:BAABLgAFFH8HAAILAAIJzhMN0wCMAAALAAIJzhMN0wCMAAABLgAFFAcJEwAXAM0XAA==.Chosen:BAAALgAECgEJAQAAAA==.Chud:BAAALgAECgUJBQABLgAFFAYJGQAYAHgjAA==.',
Ci='Cig:BAABLgAECn8YAAIZAAgJ/xC8ggBnAQAZAAgJ/xC8ggBnAQAAAA==.',
Cl='Clankychan:BAACLgAFFH8LAAIFAAMJTA3sOgC2AAAFAAMJTA3sOgC2AAAuAAQKfxgAAgUABwkMFVE8AAgBAAUABwkMFVE8AAgBAAAA.Cloneofmagic:BAAALgADCgcJBwAAAA==.',
Co='Combustanut:BAAALgAECgUJEAAAAA==.Comillmouth:BAABLgAECn8ZAAIDAAgJbxH0JwCQAQADAAgJbxH0JwCQAQAAAA==.Comillthroat:BAAALgAECgkJEQAAAA==.Cornflakez:BAAALgADCgMJAwAAAA==.Cos:BAABLgAECn82AAMBAAkJbxEZFwDfAQABAAkJbxEZFwDfAQAaAAMJOAXFFgCKAAAAAA==.',
Cr='Crocks:BAAALgAECgIJAgAAAA==.Crozier:BAAALgAECgIJBgAAAA==.Crusher:BAAALgAECgUJBgABLgAFFAcJEwAXAM0XAA==.Cryptum:BAAALgAECgkJBAAAAA==.Cryten:BAAALgAECgIJAgAAAA==.',
Cu='Cub:BAAALgAECgEJAQAAAA==.Cultiran:BAAALgAECgQJBAABLgAFFAYJGQAYAHgjAA==.Curby:BAAALgAECgcJBwABLgAECgkJTgAbAJ4eAA==.',
['Cä']='Cäin:BAAALgAECgQJCAAAAA==.',
Da='Dabufart:BAAALgADCgEJAQAAAA==.Daerus:BAAALgAECgYJBQAAAA==.Dagwood:BAAALgAECgEJAQAAAA==.Damge:BAAALgAECgUJCgAAAA==.Damnnyou:BAAALgAECgcJCAABLgAECgkJIwAcAK0ZAA==.Danky:BAAALgAECgMJAwAAAA==.Danteh:BAABLgAFFH8IAAIdAAMJ3wd0bACrAAAdAAMJ3wd0bACrAAAAAA==.Darahug:BAAALgAECgYJBgAAAA==.Daraina:BAAALgADCgEJAQABLgADCgEJAQAQAAAAAA==.Darktalanus:BAAALgADCgQJBAAAAA==.Darrkton:BAAALgADCgEJAQAAAA==.Dathil:BAAALgAECgYJCQAAAA==.Davmonhunter:BAAALgADCgQJBAAAAA==.Davoodooman:BAAALgAECgYJCAABLgAFFAQJFwATAKMcAA==.',
De='Deadiemurphy:BAAALgADCgYJCQAAAA==.Deathshunter:BAABLgAECn8iAAMVAAkJwCNKEgC7AgAVAAgJWSVKEgC7AgARAAYJ+hkjOgB5AQABLgAFFAcJHwALAKYiAA==.Deaththorn:BAAALgADCgEJAQAAAA==.Debsi:BAABLgAECn8kAAIbAAkJyA5uFgCOAQAbAAkJyA5uFgCOAQAAAA==.Declined:BAAALgAECgEJAQAAAA==.Deeper:BAABLgAFFH8NAAIXAAMJ3QfzXACMAAAXAAMJ3QfzXACMAAAAAA==.Deepest:BAABLgAFFH8HAAIaAAQJ0g82BQAvAQAaAAQJ0g82BQAvAQAAAA==.Deloraine:BAACLgAFFH8uAAIeAAcJjiQjAwBkAgAeAAcJjiQjAwBkAgAuAAQKfycAAh4ACQkAInUFAP0CAB4ACQkAInUFAP0CAAAA.Demonicfaith:BAABLgAECn82AAMNAAcJbxqFFwAMAgANAAYJTx6FFwAMAgAdAAcJlQzbgAAoAQAAAA==.Denman:BAABLgAECn8YAAMZAAcJjBnRdgCNAQAZAAcJjBnRdgCNAQAfAAEJmAAmUAAKAAAAAA==.Dezarian:BAAALgAECggJCAAAAA==.',
Di='Dirtyfista:BAAALgAECgYJCgAAAA==.Dirtyfux:BAACLgAFFH8KAAIDAAMJ5RIRMQDDAAADAAMJ5RIRMQDDAAAuAAQKfxUAAwMABglsHPQqAHwBAAMABglsHPQqAHwBAAIAAQkZDweDAC4AAAAA.Dirtysham:BAACLgAFFH8PAAIXAAQJcRqVLQAkAQAXAAQJcRqVLQAkAQAuAAQKfzAAAxcACQm3H/0MALUCABcACAl1If0MALUCACAABAmHClNmAK8AAAAA.Discipline:BAAALgADCgcJBwAAAA==.Disckin:BAAALgAECgEJAwAAAA==.Diseasemode:BAAALgAECgEJAQAAAA==.Divinechill:BAAALgAECgEJAQAAAA==.',
Dn='Dnb:BAAALgADCgEJAQABLgAFFAcJHQAPAMQZAA==.Dnk:BAAALgADCgMJAwAAAA==.',
Do='Dom:BAAALgADCgcJCQAAAA==.Donki:BAAALgAECgkJDAAAAA==.Doodtanky:BAAALgADCgEJAQAAAA==.Doomvedas:BAAALgAECgYJCgAAAA==.',
Dr='Dracaena:BAABLgAECn8jAAQcAAkJrRnVBgDZAQAhAAgJkBT/GwDoAQAcAAgJtBfVBgDZAQAiAAUJQwizMQDiAAAAAA==.Draco:BAAALgAECgMJAwAAAA==.Dreadknìght:BAAALgAFFAUJBAAAAA==.Drekavach:BAAALgADCgcJEwAAAA==.Droidbick:BAAALgAFFAIJAwAAAA==.',
['Dâ']='Dâftmonk:BAAALgAECgQJBgABLgAECgkJDAAQAAAAAA==.',
Ee='Eevo:BAAALgAECgMJAwABLgAECggJFAAGAJEIAA==.',
El='Elaha:BAAALgAECgcJCQAAAA==.Elexann:BAAALgAECgkJAQAAAA==.Elibaba:BAABLgAFFH8GAAIPAAIJMh8CkgCwAAAPAAIJMh8CkgCwAAABLgAFFAIJCAALAOAZAA==.Elideady:BAABLgAFFH8IAAILAAIJ4BnowQCfAAALAAIJ4BnowQCfAAAAAA==.Elinaa:BAAALgAECgIJAgAAAA==.Elindyl:BAAALgADCgEJAQAAAA==.Elisaxy:BAAALgAECgEJAgAAAA==.Elleth:BAAALgADCgMJAwAAAA==.Elvishcheese:BAAALgAECgMJBgAAAA==.',
Em='Emojis:BAAALgAECgUJCgAAAA==.',
En='Endlessdh:BAACLgAFFH8IAAINAAMJCiIKBwDIAAANAAMJCiIKBwDIAAAuAAQKfx4AAg0ABwkyJJUJAMgCAA0ABwkyJJUJAMgCAAAA.',
Er='Eraserhead:BAAALgAECgYJEwABLgAFFAYJGQAYAHgjAA==.Eripaladin:BAAALgAECgUJBwAAAA==.Erissaria:BAAALgADCgEJAQAAAA==.Erwinnara:BAAALgAECgEJAQAAAA==.',
Ev='Evening:BAAALgAECggJCQAAAA==.Everbuddha:BAAALgAECgQJBgAAAA==.',
Ew='Ewa:BAAALgAECgMJBAAAAA==.Eww:BAABLgAECn8XAAIdAAcJyw/ScgA4AQAdAAcJyw/ScgA4AQAAAA==.',
Ez='Ezelia:BAACLgAFFH8SAAMZAAUJExmwNQA8AQAZAAUJExmwNQA8AQAHAAIJgggAPABrAAAuAAQKfxoAAxkACQl+FqBGAPABABkACQl+FqBGAPABAAcAAQlGCVeVADUAAAEuAAUUCAkwAAIA2BkA.',
Fa='Faelune:BAABLgAECn8fAAIPAAkJ6wqkawChAQAPAAkJ6wqkawChAQAAAA==.Faldir:BAAALgADCgYJBAABLgAFFAUJGAAdAKAfAA==.',
Fe='Ferndru:BAACLgAFFH8GAAMIAAIJEw4KFACIAAAIAAIJEw4KFACIAAAjAAIJMQcHMABXAAAuAAQKfykAAwgACQkBGbMIADsCAAgACAnYG7MIADsCACMABwkeEQIiADkBAAAA.',
Fi='Fish:BAAALgAECgEJAgABLgAFFAUJDQAhADgZAA==.Fisticuffs:BAACLgAFFH8TAAIGAAYJdRAeHgBwAQAGAAYJdRAeHgBwAQAuAAQKfyMAAgYACAl3GHQfABkCAAYACAl3GHQfABkCAAAA.',
Fl='Flameshock:BAAALgAFFAIJBAAAAA==.Flowki:BAAALgADCgcJCwAAAA==.',
Fo='Forcespark:BAAALgAECgEJAQAAAA==.',
Fr='Fraserker:BAAALgAECgEJAQAAAA==.Frostradamus:BAAALgADCgkJCgAAAA==.',
Fu='Fullmoonride:BAAALgAECgUJDwAAAA==.Fumbll:BAAALgAECgkJCQAAAA==.Funkymajik:BAABLgAECn8fAAQDAAkJlg9qHQDgAQADAAkJlg9qHQDgAQACAAIJiAaJdQBTAAAeAAEJtQtOYgA0AAAAAA==.Furiosa:BAAALgADCgkJDgAAAA==.Furrballz:BAAALgAECgEJAQAAAA==.',
Ga='Gallywox:BAAALgADCgMJAwAAAA==.Ganin:BAABLgAECn8bAAIHAAYJUBU0QgBvAQAHAAYJUBU0QgBvAQAAAA==.Gankinyou:BAAALgADCgEJAQAAAA==.Gargish:BAAALgAECgkJCQABLgAFFAEJAQAQAAAAAA==.Garielyn:BAAALgADCgEJAQAAAA==.Garugala:BAACLgAFFH8OAAIZAAMJCRVSaQDWAAAZAAMJCRVSaQDWAAAuAAQKfysAAhkACQklGMYzAC8CABkACQklGMYzAC8CAAAA.',
Gd='Gdaycøb:BAAALgADCgYJBwAAAA==.',
Ge='Gengár:BAAALgAECgMJBgABLgAFFAEJAQAQAAAAAA==.',
Gh='Ghalorin:BAABLgAECn8dAAIVAAcJMhrnOwDsAQAVAAcJMhrnOwDsAQAAAA==.Ghiroza:BAABLgAECn9RAAQSAAkJ4R3fCAAzAgATAAkJ3B3CJABKAgASAAgJihbfCAAzAgAUAAMJkhZpHQCGAAAAAA==.',
Gi='Gigaevoker:BAABLgAECn8kAAIiAAgJcRaUDAAHAgAiAAgJcRaUDAAHAgAAAA==.Gigapaladin:BAAALgADCgQJBAAAAA==.Gingarthas:BAABLgAECn8iAAILAAkJPh01KwCMAgALAAkJPh01KwCMAgAAAA==.',
Gl='Glowingtoe:BAAALgAECgMJBQAAAA==.',
Go='Gogmazios:BAAALgADCgcJBwAAAA==.',
Gr='Gravytate:BAABLgAECn9XAAIgAAkJfA8cLgCGAQAgAAkJfA8cLgCGAQAAAA==.Griinn:BAABLgAECn8eAAIjAAkJSg4nHwBOAQAjAAkJSg4nHwBOAQAAAA==.Grimefiend:BAAALgAFFAIJAwAAAA==.Grimescene:BAAALgAECgIJAgABLgAFFAIJAwAQAAAAAA==.Grimreapêr:BAAALgAECgEJBQAAAA==.Grow:BAAALgAFFAEJAwAAAA==.',
Gu='Guldannyboy:BAABLgAECn80AAMSAAkJSw2YDQBfAQASAAkJygyYDQBfAQATAAkJFwemcwBSAQAAAA==.Gumbö:BAAALgAECgcJCQABLgAECggJIAAKANUcAA==.Gutted:BAAALgADCgIJAgAAAA==.',
Ha='Haides:BAAALgAECgQJBQAAAA==.Hammer:BAAALgAECgIJAgABLgAECgkJDAAQAAAAAA==.Hanokano:BAAALgAECgUJBQAAAA==.Hantore:BAAALgADCgMJAwAAAA==.Harmony:BAAALgAECgEJAQAAAA==.Harry:BAACLgAFFH8IAAIYAAMJohccDgDZAAAYAAMJohccDgDZAAAuAAQKfycAAxgACQljJOUBAD8DABgACQljJOUBAD8DABcABwnEGuMgABoCAAAA.',
He='Heartdh:BAABLgAECn8VAAMdAAgJkhK2UgCKAQAdAAgJkhK2UgCKAQANAAIJrxOGWwByAAAAAA==.Heisenbergg:BAAALgADCgIJAgAAAA==.Hellza:BAAALgAECgMJAwAAAA==.Hen:BAAALgAECgUJBQABLgAECgYJFQAMABAVAA==.Herpyprotect:BAAALgAFFAIJAwAAAA==.Herrion:BAACLgAFFH8nAAQTAAgJyBuRFAAJAgATAAcJjBuRFAAJAgASAAEJKx0UGwBbAAAUAAEJyB/IGQBXAAAuAAQKfy4AAxMACQn/IvkcAKgCABMACAn/IvkcAKgCABIABAmcJNMUAKQBAAAA.',
Hh='Hh:BAAALgAECgEJAQAAAA==.',
Ho='Holytanky:BAAALgAECgcJCgAAAA==.Hotspur:BAABLgAECn84AAIKAAgJaxDUOADDAQAKAAgJaxDUOADDAQAAAA==.',
Hu='Hukani:BAAALgAECgEJAwABLgAECggJFgACALEIAA==.Hunner:BAAALgAECgIJAgABLgAECggJFAAGAJEIAA==.Huskar:BAABLgAECn8gAAIVAAkJ4xTeLgAdAgAVAAkJ4xTeLgAdAgAAAA==.',
Hy='Hypoxi:BAAALgADCgYJCQAAAA==.',
Ig='Ignis:BAABLgAECn8cAAIkAAkJmR3ZAQBmAgAkAAkJmR3ZAQBmAgAAAA==.Ignitor:BAAALgADCgEJAQAAAA==.',
Ik='Ikari:BAABLgAECn9YAAISAAkJyhpdBQCBAgASAAkJyhpdBQCBAgAAAA==.',
Il='Illadoss:BAAALgADCgIJAgAAAA==.',
Im='Imntprepared:BAAALgAFFAEJAQAAAA==.',
In='Incarnate:BAAALgAECgEJAgAAAA==.Incubis:BAAALgADCgIJAgAAAA==.Infectîon:BAAALgAECgEJAgAAAA==.Inferlock:BAAALgAECgMJAwAAAA==.Infernyos:BAAALgAECgUJBQAAAA==.Infernyoz:BAAALgADCggJCQAAAA==.',
Ir='Irithel:BAAALgAECgcJBQAAAA==.',
Is='Isohexene:BAAALgADCgYJBgAAAA==.',
It='Itchygrowth:BAAALgAFFAEJAQAAAA==.',
Iu='Iucifer:BAAALgAECgEJAQAAAA==.',
Iv='Ivygambina:BAAALgADCgYJBgAAAA==.Ivysore:BAAALgAECgUJBwAAAA==.',
Ja='Jasha:BAAALgADCgcJCwAAAA==.Jayvarmani:BAAALgAECgMJAwAAAA==.Jayy:BAABLgAECn8bAAILAAkJBRCKTAANAgALAAkJBRCKTAANAgAAAA==.',
Je='Jennatalia:BAAALgAECggJEgABLgAFFAEJAQAQAAAAAA==.',
Ji='Jinkazamaz:BAAALgAFFAIJBAAAAA==.',
Jo='Joelsdruid:BAABLgAFFH8bAAIjAAUJvx0BCQBaAQAjAAUJvx0BCQBaAQAAAA==.Joelvoker:BAAALgAFFAIJAgABLgAFFAUJGwAjAL8dAA==.Joexotic:BAAALgAECgIJBwAAAA==.Jongwang:BAAALgAECgQJBwAAAA==.',
Ju='Jubjub:BAAALgAECgEJAgAAAA==.',
Ka='Kaaru:BAACLgAFFH8JAAIDAAQJ4gqFKQD6AAADAAQJ4gqFKQD6AAAuAAQKfyUAAwMACQmME6MXABUCAAMACQl6EqMXABUCAAIABQkTEoZIABcBAAAA.Kaelom:BAAALgAECgQJBQAAAA==.Kahai:BAAALgAECgIJAgAAAA==.Kaiforst:BAAALgAECgQJBAABLgAECgkJNwAZAOEaAA==.Kaihavocz:BAAALgAECgEJAwAAAA==.Kairon:BAABLgAECn83AAIZAAkJ4RoTLABOAgAZAAkJ4RoTLABOAgAAAA==.Kalysae:BAAALgADCgEJAQAAAA==.Kania:BAAALgAECgIJAgABLgAECgkJMQAXAMQiAA==.Katarinabluu:BAAALgAECgYJBgAAAA==.Kazakhthundr:BAAALgADCgYJBgAAAA==.',
Ke='Keeanuleaves:BAAALgADCgYJBwAAAA==.Keeanuweaves:BAAALgADCgEJAQAAAA==.Keeze:BAACLgAFFH8QAAIPAAQJbQlUbQAPAQAPAAQJbQlUbQAPAQAuAAQKfxgAAg8ACQkaE8BWANUBAA8ACQkaE8BWANUBAAAA.',
Ki='Kickstarter:BAAALgAECgYJEgAAAA==.Kiel:BAAALgAECgEJAQAAAA==.Kikiz:BAAALgAECgUJCAAAAA==.Killania:BAAALgADCgMJAwAAAA==.Kiwichaos:BAACLgAFFH8KAAINAAQJnQnGHQCoAAANAAQJnQnGHQCoAAAuAAQKfy4AAg0ACQlbG6QMAJcCAA0ACQlbG6QMAJcCAAAA.',
Kn='Knox:BAAALgAECgUJCgAAAA==.Knull:BAAALgAECgIJAwAAAA==.',
Ko='Korner:BAAALgAECgIJAgAAAA==.',
Kr='Krazzul:BAAALgAECgQJBAAAAA==.Krellis:BAABLgAECn8aAAMEAAkJvRf5DwBJAgAEAAkJvRf5DwBJAgAGAAYJtRA8MQAzAQAAAA==.Kritikall:BAAALgADCgUJBQAAAA==.',
Ku='Kurö:BAAALgAECgEJAQAAAA==.',
Kv='Kvôthe:BAABLgAECn8dAAMLAAkJPgzvaACRAQALAAkJCgvvaACRAQAlAAMJzQeRKQCBAAAAAA==.',
Ky='Kynnareth:BAAALgAFFAIJBAABLgAFFAYJFAAHAIoPAA==.Kynralol:BAABLgAECn9UAAIPAAkJxCHDDAARAwAPAAkJxCHDDAARAwAAAA==.Kyujín:BAAALgAECgIJAgAAAA==.Kyunsun:BAAALgAECgYJCAAAAA==.',
['Ká']='Káiser:BAAALgAECggJEQAAAA==.',
La='Laenosh:BAABLgAECn8ZAAILAAUJDhLL0wDgAAALAAUJDhLL0wDgAAAAAA==.Lagalot:BAAALgAECgEJAQAAAA==.Laomoo:BAAALgAECgcJDgAAAA==.Laz:BAAALgADCgMJBQAAAA==.',
Le='Learning:BAABLgAECn8XAAIgAAcJEh9LGwA4AgAgAAcJEh9LGwA4AgAAAA==.Legham:BAAALgADCgkJDgAAAA==.Legolazz:BAABLgAECn8yAAMVAAkJ4B7vGQCFAgAVAAkJ4B7vGQCFAgARAAMJCBQ9KQBuAAAAAA==.Lemins:BAAALgAECgMJAwAAAA==.Lemondruid:BAAALgAECgIJAgAAAA==.Lemonmelon:BAAALgAECgYJEwAAAA==.Lenatheplug:BAACLgAFFH8aAAMBAAcJ5BcMAwDMAQABAAYJTRwMAwDMAQAaAAIJjQnKBQBgAAAuAAQKfyIAAwEACAmUJEQKAO0CAAEACAnbI0QKAO0CABoABwlAIt4DAIACAAAA.Lerust:BAAALgADCgcJBwAAAA==.',
Li='Liadrine:BAACLgAFFH8FAAIZAAQJdAycUQAHAQAZAAQJdAycUQAHAQAuAAQKfzAAAhkACQnjF31IAOoBABkACQnjF31IAOoBAAAA.Lickyourass:BAAALgADCgYJCwAAAA==.Linus:BAAALgAECgYJBgABLgAFFAgJJwATAMgbAA==.Littleriver:BAABLgAECn8XAAIVAAgJ2hirNgDUAQAVAAgJ2hirNgDUAQAAAA==.',
Ll='Llewser:BAABLgAECn8aAAMPAAgJwhU8TwDrAQAPAAgJwhU8TwDrAQAkAAEJqgTTFAAqAAAAAA==.',
Lo='Loathe:BAAALgAFFAEJAQAAAA==.Loistiah:BAABLgAFFH8IAAILAAMJZhkQlADhAAALAAMJZhkQlADhAAAAAA==.Lothaof:BAABLgAECn8sAAIZAAkJ6RIgWgC8AQAZAAkJ6RIgWgC8AQAAAA==.Louisvuitton:BAAALgAECgUJDwAAAA==.',
Lp='Lpayn:BAAALgADCgEJAQAAAA==.',
Lu='Lugroth:BAABLgAFFH8FAAMjAAMJWhZCFwDGAAAjAAMJWhZCFwDGAAAKAAEJIxE1bgA2AAABLgAFFAgJJwATAMgbAA==.Lunana:BAAALgAECgcJEgAAAA==.',
Ly='Lychiee:BAAALgAECgcJEQAAAA==.',
['Lì']='Lìnkinbark:BAAALgAECgMJAwAAAA==.',
Ma='Madara:BAAALgAECgEJAgAAAA==.Magesorry:BAAALgADCgUJBQAAAA==.Magicmon:BAAALgADCgkJGgAAAA==.Maize:BAABLgAECn8iAAMDAAgJMBsAEwBHAgADAAgJMBsAEwBHAgACAAMJhgvTZwCOAAAAAA==.Makima:BAABLgAFFH8FAAIJAAUJmQ63LADQAAAJAAUJmQ63LADQAAABLgAFFAYJEwAGACoTAA==.Malikai:BAAALgADCgcJDAAAAA==.Malxsvoker:BAAALgAFFAIJAgABLgAFFAYJCwAgAOMLAA==.Marcymonk:BAAALgADCgEJAQAAAA==.Marcyon:BAABLgAECn8aAAIdAAYJqAnmrwDDAAAdAAYJqAnmrwDDAAAAAA==.Marywinston:BAAALgAFFAEJAQABLgAFFAIJBgAMAFMUAA==.',
Mc='Mchèalz:BAABLgAECn8VAAQDAAgJRAhvOwAgAQADAAgJRAhvOwAgAQACAAQJxAFFaQCIAAAeAAIJOwF0ZgAsAAAAAA==.',
Me='Melodysseý:BAAALgAECgUJBQAAAA==.Melonlemonza:BAAALgADCgQJBAAAAA==.Mentok:BAAALgAECgYJCwAAAA==.Merchei:BAAALgAECgUJBgAAAA==.Meruen:BAACLgAFFH8IAAIdAAQJlBNZRQARAQAdAAQJlBNZRQARAQAuAAQKfzoAAx0ACQniGxUYAIICAB0ACQniGxUYAIICAA4AAwm2AtkqAFQAAAAA.',
Mi='Mik:BAAALgAECgcJBwABLgAFFAUJGAAdAKAfAA==.Miralisa:BAAALgAFFAIJAgAAAA==.Miss:BAAALgAECgMJAwAAAA==.Mistie:BAAALgAECgEJAQABLgAECgkJIAAKAFsVAA==.Mitymorphin:BAAALgADCgEJAQAAAA==.',
Mo='Mobility:BAAALgAFFAEJAQAAAA==.Moistpole:BAAALgADCgQJBAAAAA==.Momock:BAAALgAECgQJBAAAAA==.Mongk:BAABLgAECn8UAAIGAAgJkQibNQAZAQAGAAgJkQibNQAZAQAAAA==.Monscustodes:BAABLgAECn8kAAIPAAkJWA9YYAC8AQAPAAkJWA9YYAC8AQAAAA==.Monstersauce:BAAALgAFFAIJBAAAAA==.Mookin:BAAALgAFFAEJAQAAAA==.Moospoon:BAABLgAECn8/AAIZAAgJTRUGVwDEAQAZAAgJTRUGVwDEAQAAAA==.Mooudini:BAAALgAECgMJAwAAAA==.Moounka:BAABLgAECn9GAAIFAAkJcxOvFwDoAQAFAAkJcxOvFwDoAQAAAA==.Morphio:BAACLgAFFH8FAAIVAAMJSRnhUwD4AAAVAAMJSRnhUwD4AAAuAAQKf0sAAxUACQkvJSYDAF0DABUACQkvJSYDAF0DABEABQkLE5pMAB8BAAAA.Mostakrakish:BAAALgADCgEJAQAAAA==.',
Mu='Muddles:BAABLgAECn9EAAIFAAkJUBilEQApAgAFAAkJUBilEQApAgAAAA==.Murius:BAACLgAFFH8JAAILAAMJkQT4tQC0AAALAAMJkQT4tQC0AAAuAAQKfzIAAgsACQlEFwc2ACQCAAsACQlEFwc2ACQCAAAA.',
My='Mysterio:BAAALgAFFAEJBAAAAA==.',
Na='Naendria:BAAALgAECgMJBAAAAA==.Naga:BAAALgAECgIJAgAAAA==.Nahaza:BAAALgAECgEJAgAAAA==.',
Ne='Nelena:BAAALgADCgEJAQAAAA==.',
Ni='Nickdoom:BAAALgAECgUJEwAAAA==.Nigella:BAABLgAECn8WAAMCAAgJsQjzOgAGAQACAAgJsQjzOgAGAQADAAEJ6wF1hgAgAAAAAA==.Nikola:BAACLgAFFH8GAAMKAAIJzw/qUAB5AAAKAAIJzw/qUAB5AAAJAAEJ3QfCTgA1AAAuAAQKfykABAoACQmjFWc3AMoBAAoACQmjFWc3AMoBACMABQk4Ft8VABQBAAkABAl9D39UANQAAAAA.Nimro:BAACLgAFFH8bAAIbAAcJqRUGCACuAQAbAAcJqRUGCACuAQAuAAQKfygAAhsACQmPH6ADABsDABsACQmPH6ADABsDAAAA.Niub:BAABLgAECn8pAAImAAkJwRMKIADuAQAmAAkJwRMKIADuAQAAAA==.',
No='Nofate:BAAALgADCgEJAQAAAA==.Noirebringer:BAAALgAFFAEJAQAAAA==.Nongbonnie:BAAALgAECgIJAgAAAA==.Nongkiwi:BAAALgAECggJCwAAAA==.',
Nt='Ntrldrake:BAAALgADCgEJAgABLgAECgkJJAAPAFgPAA==.',
Nu='Nueng:BAAALgADCgEJAQAAAA==.Nuferax:BAABLgAECn8fAAIOAAkJXyHxAQD0AgAOAAkJXyHxAQD0AgAAAA==.Nuiiwarx:BAAALgAECgEJAgAAAA==.Nulledhacz:BAAALgAECgUJAwAAAA==.Numbrethree:BAACLgAFFH8TAAIGAAQJ/hGVMQDdAAAGAAQJ/hGVMQDdAAAuAAQKf0wAAwYACQnFGz0OALYCAAYACQnFGz0OALYCAAQAAglDBimyACIAAAAA.',
Ob='Obbi:BAACLgAFFH8cAAIaAAQJ0yZ6AQDPAQAaAAQJ0yZ6AQDPAQAuAAQKfxoAAxoACQkpIE0BAAMDABoACQkpIE0BAAMDACcAAQk/JB4cAGcAAAAA.',
Oh='Ohaither:BAAALgAECgQJBAAAAA==.',
Oi='Oirth:BAAALgADCgIJAgAAAA==.',
Ok='Okiji:BAAALgAECgkJEwAAAA==.',
Or='Orinocco:BAAALgAECgEJAwAAAA==.Orobas:BAAALgAECgkJEwAAAA==.',
Pa='Pacquiaø:BAAALgAECgYJCQAAAA==.Pakaww:BAAALgAECgIJAwAAAA==.Palimathrus:BAAALgAECgUJCAAAAA==.Palliative:BAABLgAECn9FAAMHAAkJMSLLBgAdAwAHAAkJMSLLBgAdAwAZAAQJLwWcFwGZAAAAAA==.Pallidnim:BAABLgAFFH8JAAIMAAUJuBFSHgDvAAAMAAUJuBFSHgDvAAAAAA==.Papager:BAABLgAFFH8HAAITAAMJvAY6hAC3AAATAAMJvAY6hAC3AAAAAA==.',
Pe='Pea:BAAALgAECgcJEAAAAA==.Perish:BAAALgAECggJDQABLgAECgkJRAAFAFAYAA==.',
Ph='Phatmonk:BAACLgAFFH8cAAMEAAUJkiY0BQDCAQAEAAUJkiY0BQDCAQAGAAIJyASHVABRAAAuAAQKf0cAAwQACQmxJncAAIgDAAQACQmxJncAAIgDAAYABwntICURAJICAAAA.Phatrogue:BAABLgAFFH8JAAIBAAMJjB24IgAGAQABAAMJjB24IgAGAQABLgAFFAUJHAAEAJImAA==.',
Pi='Piewpiew:BAAALgADCgcJCgAAAA==.Pix:BAACLgAFFH8cAAMeAAcJZR3XAgDHAQAeAAcJZR3XAgDHAQADAAUJvQykHwBLAQAuAAQKfzYAAh4ACQk5JSgCAE0DAB4ACQk5JSgCAE0DAAAA.',
Pl='Pleasuremax:BAACLgAFFH8LAAIVAAQJ4RWeLQBPAQAVAAQJ4RWeLQBPAQAuAAQKfxoAAhUACAksFa5EAM8BABUACAksFa5EAM8BAAAA.Plex:BAABLgAECn8/AAIIAAkJRRo5BwBkAgAIAAkJRRo5BwBkAgAAAA==.',
Po='Poofyfeesh:BAAALgAFFAEJAgAAAA==.Poogie:BAAALgADCgYJBgABLgAECgMJBQAQAAAAAA==.Popshot:BAABLgAECn8eAAIRAAYJ5xIiRQBBAQARAAYJ5xIiRQBBAQAAAA==.Portalhouse:BAAALgAECgEJAQAAAA==.',
Pr='Praxis:BAACLgAFFH8MAAIbAAMJWRL6HQCgAAAbAAMJWRL6HQCgAAAuAAQKfzIAAygACAlzFmgfAF4BABsACAn+EiEYAHsBACgABglRF2gfAF4BAAAA.Preast:BAAALgAECgcJBwABLgAECggJFAAGAJEIAA==.Procist:BAABLgAECn8YAAMCAAkJBxcsEABkAgACAAkJBxcsEABkAgAeAAEJpQfNjgApAAABLgAECgkJMQAXAMQiAA==.',
Py='Pyrusdk:BAABLgAECn8ZAAILAAkJgQ5oXgCrAQALAAkJgQ5oXgCrAQAAAA==.Pyrusdruid:BAABLgAECn8WAAIKAAkJJwLRmwB2AAAKAAkJJwLRmwB2AAAAAA==.',
Qo='Qop:BAAALgAFFAEJAgAAAA==.',
Qu='Quesarah:BAAALgADCgEJAQABLgAECgQJBAAQAAAAAA==.',
Qw='Qweffor:BAAALgAECgUJBQABLgAFFAIJBQALAPcOAA==.',
Ra='Rainbowkelly:BAAALgAECgQJBAAAAA==.Raisha:BAAALgADCgEJAQAAAA==.Raìn:BAACLgAFFH8HAAILAAMJmAwRqADJAAALAAMJmAwRqADJAAAuAAQKfxQAAgsACAnYFdRQAM4BAAsACAnYFdRQAM4BAAAA.',
Re='Recruitqt:BAACLgAFFH8FAAMZAAIJDg2hjQCOAAAZAAIJDg2hjQCOAAAHAAEJ+AdnSAA1AAAuAAQKfx8AAwcABQm0Gg86AJEBAAcABQm0Gg86AJEBABkABAkTEcnUAOkAAAAA.Reiayanami:BAABLgAECn8fAAIPAAgJfA++fwB1AQAPAAgJfA++fwB1AQAAAA==.',
Ri='Ripandtear:BAABLgAECn8gAAMKAAkJZRfVKAAJAgAKAAkJZRfVKAAJAgAIAAEJFQZ6NgAsAAAAAA==.',
Ro='Roguewan:BAAALgAFFAIJAgAAAA==.Rolâyne:BAAALgADCgkJDgAAAA==.Roninn:BAACLgAFFH8QAAIKAAQJ5Rk/JAAxAQAKAAQJ5Rk/JAAxAQAuAAQKfzQAAgoACQlVIYAFAF0DAAoACQlVIYAFAF0DAAAA.Ronlock:BAABLgAECn8VAAMTAAYJ8xD9nQAdAQATAAUJ8xD9nQAdAQASAAEJAAABagA+AAABLgAECgcJNgANAG8aAA==.Royaltits:BAAALgADCgIJAgAAAA==.',
Rs='Rsi:BAAALgAECgQJBAAAAA==.',
Ry='Rynaea:BAAALgAECggJDgAAAA==.',
['Rï']='Rïmuru:BAAALgADCgcJCwAAAA==.',
['Rô']='Rôlayne:BAABLgAECn8ZAAImAAgJdQuzQQA9AQAmAAgJdQuzQQA9AQAAAA==.',
Sa='Sadakos:BAAALgAFFAMJBAAAAA==.Salvare:BAABLgAECn8lAAMaAAkJhhhwAwCVAgAaAAkJfRhwAwCVAgAnAAIJRRArGwBwAAAAAA==.Sappy:BAAALgAECgQJBAAAAA==.Sarielsiá:BAAALgAFFAEJAQAAAA==.Sauron:BAAALgADCgEJAQABLgAFFAQJFAATAPYUAA==.',
Sb='Sbf:BAABLgAFFH8ZAAIhAAcJ4RalEADxAQAhAAcJ4RalEADxAQABLgAFFAkJNwAdAG4jAA==.',
Sc='Scalamander:BAAALgAECgcJAgAAAA==.Sciohunter:BAABLgAFFH8FAAINAAIJIAwTJAB5AAANAAIJIAwTJAB5AAAAAA==.Scioscioz:BAACLgAFFH8OAAIKAAQJ0BB9LgDyAAAKAAQJ0BB9LgDyAAAuAAQKfyAAAwoABwnOFOI7ALUBAAoABwnOFOI7ALUBAAkAAglnEAJsAHAAAAAA.Scwisgar:BAAALgAECgkJDQAAAA==.',
Se='Sedge:BAAALgAFFAIJBAAAAA==.Sephire:BAABLgAECn8eAAIZAAkJPARbyAD6AAAZAAkJPARbyAD6AAAAAA==.Sermazule:BAAALgADCgcJEQAAAA==.Sewerface:BAABLgAECn8VAAMMAAYJEBWaHgBTAQAMAAYJEBWaHgBTAQALAAMJLAScAQF2AAAAAA==.',
Sh='Shadonir:BAAALgAECgQJBAAAAA==.Shadowind:BAACLgAFFH8jAAIVAAUJKh8qLQBQAQAVAAUJKh8qLQBQAQAuAAQKfy8AAxEACQmGHn4dADsCABEACAlEGX4dADsCABUABQlkHSlfAIUBAAAA.Shaft:BAAALgAECgEJAQAAAA==.Shallotte:BAABLgAECn8YAAMUAAgJdRDoCwB7AQAUAAcJABLoCwB7AQATAAcJoghBlQARAQAAAA==.Shambulance:BAAALgAECgQJAwAAAA==.Shammalxs:BAABLgAFFH8LAAIgAAYJ4wtnHQAqAQAgAAYJ4wtnHQAqAQAAAA==.Shamoc:BAABLgAECn8xAAMXAAkJxCKPBgBFAwAXAAkJxCKPBgBFAwAgAAYJohESSQAjAQAAAA==.Shampooing:BAACLgAFFH8MAAIgAAQJPg0NLADdAAAgAAQJPg0NLADdAAAuAAQKfygAAiAACQk3F0UXACgCACAACQk3F0UXACgCAAAA.Shampski:BAAALgAECgYJCwABLgAECggJFAAGAJEIAA==.Sharpknife:BAABLgAFFH8UAAMpAAQJJR8rCACJAQApAAQJJR8rCACJAQAVAAMJRhGzYwDVAAAAAA==.Shaz:BAAALgADCgQJBAAAAA==.Shivd:BAAALgAECgIJAgAAAA==.Shorpus:BAABLgAECn8hAAQgAAkJPx3OFwAjAgAYAAYJNx8hCgAwAgAgAAkJWhjOFwAjAgAXAAcJCwj6XQATAQAAAA==.',
Si='Sicckbrew:BAABLgAECn8hAAIEAAkJaiH+CQDYAgAEAAkJaiH+CQDYAgABLgAFFAQJCAAjABcNAA==.Sickin:BAABLgAFFH8IAAIjAAQJFw2vGAC+AAAjAAQJFw2vGAC+AAAAAA==.Sinniestro:BAAALgAECgEJAgAAAA==.',
Sk='Skizzyy:BAAALgAECgMJAwABLgAECgcJEAAQAAAAAA==.Skwigelf:BAAALgAECgQJCAAAAA==.',
Sl='Slayedurmrs:BAAALgAECgQJBQAAAA==.Slok:BAAALgAECgEJAQAAAA==.Slowpoke:BAABLgAFFH8sAAIJAAUJwRvECABXAQAJAAUJwRvECABXAQABLgAFFAYJEwAGACoTAA==.',
Sm='Smacedh:BAABLgAECn8XAAIdAAkJzRKUYgB6AQAdAAkJzRKUYgB6AQAAAA==.Smesher:BAABLgAECn8kAAIZAAkJZBCRUADUAQAZAAkJZBCRUADUAQAAAA==.',
Sn='Sneakyfella:BAAALgAFFAEJAgAAAA==.',
So='Solidus:BAABLgAFFH8GAAIZAAQJmhS2SAAWAQAZAAQJmhS2SAAWAQAAAA==.Sorgaath:BAAALgADCgcJBwAAAA==.',
Sp='Spaklehooves:BAAALgADCgYJBgAAAA==.Spicoli:BAAALgADCgEJAQAAAA==.Spiral:BAAALgAECgQJBwAAAA==.Spoonfed:BAAALgAECgQJCwAAAA==.',
Sq='Squiish:BAACLgAFFH8YAAMJAAgJ/hh7CgDnAQAJAAcJ/Rd7CgDnAQAKAAUJkAVTKwAEAQAuAAQKfxoAAgkABwmoJfALANkCAAkABwmoJfALANkCAAAA.',
St='Stavrophore:BAAALgAECgEJBQAAAA==.Stickydruid:BAAALgAECgIJBgABLgAECgkJTgAeALohAA==.Stickyholes:BAAALgAECgIJAgABLgAECgkJTgAeALohAA==.Stickymonk:BAAALgAECgEJBAABLgAECgkJTgAeALohAA==.Stickypriest:BAABLgAECn9OAAMeAAkJuiGdCADEAgAeAAkJuiGdCADEAgACAAEJExiTeQBCAAAAAA==.Stipe:BAAALgADCgUJCAAAAA==.Stove:BAAALgADCgcJCwAAAA==.Strawhats:BAACLgAFFH87AAIPAAgJ+hsgAwBMAgAPAAgJ+hsgAwBMAgAuAAQKf0IAAg8ACQkyJWcCANgDAA8ACQkyJWcCANgDAAEuAAUUCQk3AB0AbiMA.Streamliner:BAABLgAECn8/AAMBAAkJJBtlCwBrAgABAAkJJBtlCwBrAgAnAAMJ1gdKCwCNAAAAAA==.Stuunks:BAAALgAECgYJCwAAAA==.',
Su='Surv:BAACLgAFFH8MAAMpAAYJmhNYEgAzAQApAAQJyBhYEgAzAQARAAMJLweUGgDYAAAuAAQKfx8AAxEABwmVIAEKAM0BABEABgn+HwEKAM0BACkABwk6G60aAMkBAAAA.Sustangelia:BAABLgAECn8bAAMLAAkJbxh6UAAAAgALAAkJbxh6UAAAAgAlAAEJBw+ANABFAAAAAA==.',
Sw='Swordkiller:BAAALgAECgcJBgAAAA==.',
Sx='Sxy:BAAALgAECgYJBwABLgAECgkJPwAIAEUaAA==.',
Sy='Sy:BAABLgAFFH8HAAIZAAUJAQl3WwDyAAAZAAUJAQl3WwDyAAAAAA==.Synthesis:BAABLgAECn8hAAIKAAgJoyUsBgBSAwAKAAgJoyUsBgBSAwAAAA==.',
Ta='Tae:BAAALgADCgUJBQAAAA==.Taichee:BAAALgADCgUJBQAAAA==.Talas:BAAALgAECgQJBQAAAA==.Talletalanot:BAACLgAFFH8JAAIiAAMJWgkhIgCKAAAiAAMJWgkhIgCKAAAuAAQKfy4AAiIACQkbILMFALMCACIACQkbILMFALMCAAAA.Tandryan:BAAALgAECgQJBwAAAA==.Tanukiji:BAABLgAECn8nAAICAAkJFhzADgB5AgACAAkJFhzADgB5AgAAAA==.',
Td='Tdh:BAAALgADCgMJAwAAAA==.Tdk:BAABLgAECn8WAAMLAAgJqhQguwABAQALAAcJzhUguwABAQAMAAEJ0Q38WAA5AAAAAA==.',
Te='Tee:BAAALgADCgUJBQAAAA==.Terry:BAAALgAECgcJBwAAAA==.Tesarion:BAACLgAFFH8FAAILAAIJ9w683wCEAAALAAIJ9w683wCEAAAuAAQKfxYAAgsACAkdGPhYALkBAAsACAkdGPhYALkBAAAA.Testalatesta:BAABLgAECn9KAAMHAAkJBSULAQC6AwAHAAkJBSULAQC6AwAZAAEJmwgBrwEnAAAAAA==.Testaltesta:BAABLgAECn8XAAIGAAkJ/R9CBgA9AwAGAAkJ/R9CBgA9AwABLgAECgkJSgAHAAUlAA==.',
Th='Tharien:BAAALgADCgIJAgAAAA==.Thovir:BAAALgADCgEJAQAAAA==.',
Ti='Tiberian:BAAALgADCgIJAgAAAA==.Tinyvolt:BAAALgAECgkJDAAAAA==.',
Tm='Tmonk:BAAALgAECgkJDgAAAA==.',
To='Toinahun:BAAALgAECgQJBAAAAA==.Tookersoul:BAAALgAECgEJAQAAAA==.Totemea:BAAALgAECgYJDgAAAA==.Totems:BAACLgAFFH8TAAIXAAcJzRewCAAwAgAXAAcJzRewCAAwAgAuAAQKfxUAAhcACAkuGz4fAFECABcACAkuGz4fAFECAAAA.Totemteabag:BAAALgAECgEJAQAAAA==.Totemîxx:BAABLgAECn8wAAMgAAkJnxmVEwBNAgAgAAkJnxmVEwBNAgAXAAQJYQ23fgCYAAAAAA==.Touchhy:BAAALgAECgEJAQAAAA==.',
Tr='Trainz:BAAALgADCgcJBwAAAA==.Traktorbeam:BAAALgADCgQJBAAAAA==.Trass:BAACLgAFFH8XAAMTAAQJoxw7OwBXAQATAAQJoxw7OwBXAQASAAEJnBB3JQBJAAAuAAQKf0EAAxMACQndIGAXAJYCABMACQndIGAXAJYCABIAAwkqERxEAKUAAAAA.Trays:BAAALgADCgEJAQAAAA==.Trisse:BAABLgAECn8nAAIdAAgJog9rWwByAQAdAAgJog9rWwByAQAAAA==.',
Tu='Tuzz:BAACLgAFFH8NAAIlAAMJgxUEFADiAAAlAAMJgxUEFADiAAAuAAQKfysAAiUACQljIWIBAO4CACUACQljIWIBAO4CAAAA.',
Tw='Twongle:BAAALgADCgIJAgABLgAECggJGgAPAMIVAA==.',
Ty='Tyden:BAAALgAECgYJEAAAAA==.Tyrmac:BAAALgAECgUJBgAAAA==.',
Va='Vael:BAAALgAECgYJCgAAAA==.Valerie:BAAALgAECgUJBwAAAA==.Valkyrra:BAAALgAECgQJBAAAAA==.Vallyssa:BAAALgAECgEJAgAAAA==.Varaestia:BAAALgAECgQJBAAAAA==.Varg:BAAALgADCgEJAQABLgADCgEJAQAQAAAAAA==.Vargmk:BAAALgADCgEJAQAAAA==.Vargps:BAAALgADCgEJAQAAAA==.',
Ve='Velithara:BAAALgAECgcJBwAAAA==.Venestra:BAAALgAFFAMJBAAAAA==.Verdict:BAACLgAFFH8JAAIZAAQJzBtpNgA7AQAZAAQJzBtpNgA7AQAuAAQKfxgAAhkACAloHlsgAKoCABkACAloHlsgAKoCAAAA.Vermeil:BAAALgAECgMJAwAAAA==.Vermillion:BAACLgAFFH8aAAIZAAcJoBkWGQCeAQAZAAcJoBkWGQCeAQAuAAQKfyIAAhkACQnuIGQRANoCABkACQnuIGQRANoCAAAA.Verzik:BAAALgAECgMJBgAAAA==.',
Vi='Vib:BAAALgAECgEJAQAAAA==.Viegas:BAACLgAFFH8FAAIVAAIJnRKpIwBZAAAVAAIJnRKpIwBZAAAuAAQKfxsAAhUABwkjHK4gAEECABUABwkjHK4gAEECAAAA.Vincent:BAABLgAECn8hAAIPAAYJsB6ZfgDUAQAPAAYJsB6ZfgDUAQAAAA==.Vinijr:BAAALgAECgEJAgAAAA==.Vivamax:BAAALgAECgEJAQAAAA==.Vizsla:BAACLgAFFH8PAAILAAQJaw0idQAVAQALAAQJaw0idQAVAQAuAAQKfxUAAgsABwn7EWugACkBAAsABwn7EWugACkBAAAA.',
Vo='Voidthotnimz:BAAALgADCgcJBgABLgAFFAUJFAAhAEILAA==.Volthic:BAAALgAECgQJBAAAAA==.Voltormu:BAAALgAECgMJBgAAAA==.Vore:BAABLgAECn8fAAIdAAkJeBWeNwDkAQAdAAkJeBWeNwDkAQAAAA==.',
Vr='Vrag:BAACLgAFFH8OAAILAAMJYAohqQDIAAALAAMJYAohqQDIAAAuAAQKfzsAAgsACQloGM4lAGoCAAsACQloGM4lAGoCAAAA.',
['Vè']='Vè:BAABLgAECn8bAAQMAAkJQBGkGwB8AQAMAAkJBQ+kGwB8AQALAAcJ/BDIfQBlAQAlAAEJ5ASSQAAiAAAAAA==.',
['Vê']='Vêê:BAAALgAECgQJBgABLgAECgkJGwAMAEARAA==.',
Wa='Warslaw:BAACLgAFFH8cAAIMAAYJISILCgDVAQAMAAYJISILCgDVAQAuAAQKfyAAAgwACQlVI18FAOsCAAwACQlVI18FAOsCAAAA.Warth:BAAALgADCgEJAQAAAA==.Waterwater:BAAALgAECgYJCgAAAA==.Waterwaterz:BAACLgAFFH8UAAIPAAQJcRlyWwAzAQAPAAQJcRlyWwAzAQAuAAQKfzkAAg8ACAnVHOQ0AJ8CAA8ACAnVHOQ0AJ8CAAAA.',
Wc='Wchin:BAABLgAECn8aAAIWAAgJ0yBzAQCLAgAWAAgJ0yBzAQCLAgAAAA==.Wchinz:BAABLgAECn8WAAIeAAkJbiCPDgCaAgAeAAkJbiCPDgCaAgAAAA==.',
We='Wedlock:BAAALgAECgMJBAAAAA==.Welcumshot:BAABLgAFFH8OAAIpAAMJsRXuHADlAAApAAMJsRXuHADlAAAAAA==.Wenkar:BAAALgAECgUJDQABLgAECgkJUQASAOEdAA==.',
Wh='Whaka:BAAALgAECgIJAgABLgAFFAUJDwAiADUMAA==.',
Wi='Wid:BAAALgAECgkJBQAAAA==.Windsabre:BAAALgADCgIJAgAAAA==.Wingz:BAAALgAFFAEJAgAAAA==.',
Wo='Woregeonnick:BAABLgAECn8fAAITAAcJVxEhZwCWAQATAAcJVxEhZwCWAQAAAA==.Woshiren:BAAALgAECgYJBgAAAA==.Wozzie:BAAALgADCggJCAAAAA==.',
Wr='Wrane:BAAALgAECgEJAQAAAA==.',
Wy='Wyvern:BAAALgAECgcJEAAAAA==.',
['Wä']='Wärrior:BAAALgADCgMJAwAAAA==.',
Xa='Xanadu:BAAALgADCgIJAgAAAA==.',
Xd='Xd:BAAALgAFFAEJAQAAAA==.',
Xe='Xerxexy:BAAALgAECgQJCwAAAA==.',
Xi='Xiaodingdang:BAAALgAECgQJBAAAAA==.Xiera:BAABLgAECn8dAAIPAAkJTRB9UQDlAQAPAAkJTRB9UQDlAQAAAA==.',
Ya='Yaminosaishi:BAAALgAECgYJBwAAAA==.Yaoyôrozu:BAAALgADCgkJFAAAAA==.Yasuô:BAAALgADCgMJAwAAAA==.Yatelega:BAAALgADCgIJAgABLgAECgcJHwATAFcRAA==.Yazdorzarn:BAAALgAECgcJDAAAAA==.',
Yo='Yozzan:BAAALgAECgIJAgAAAA==.Yozzao:BAAALgAECgQJDAAAAA==.',
Yu='Yueli:BAAALgAFFAEJAQABLgAFFAgJGAAJAP4YAA==.',
Za='Zaaniz:BAABLgAECn8lAAQZAAkJ8BtvHwCvAgAZAAkJ8BtvHwCvAgAHAAQJgwkgXQC+AAAfAAIJ+Q2WPwBdAAAAAA==.',
Ze='Zenestra:BAAALgAECgkJAQABLgAFFAMJBAAQAAAAAA==.Zenshui:BAAALgAECgYJCQAAAA==.Zephyruss:BAAALgADCgEJAQAAAA==.Zervis:BAAALgAECgIJAgAAAA==.Zeyra:BAAALgAECgYJDAAAAA==.',
Zi='Zinako:BAAALgAECgEJAgAAAA==.',
Zo='Zocalo:BAAALgAECgUJBQAAAA==.',
['Èa']='Èasymode:BAAALgADCgEJAQAAAA==.',
['Ód']='Ódyssey:BAABLgAECn8ZAAIYAAgJCRK9EACiAQAYAAgJCRK9EACiAQAAAA==.',
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
