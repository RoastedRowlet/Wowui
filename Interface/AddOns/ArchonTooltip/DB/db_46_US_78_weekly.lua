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

local lookup = {'Rogue-Subtlety','Priest-Holy','Priest-Discipline','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Paladin-Holy','Druid-Feral','Druid-Balance','Druid-Restoration','DeathKnight-Unholy','DeathKnight-Blood','DemonHunter-Havoc','DemonHunter-Vengeance','Mage-Frost','Unknown-Unknown','Hunter-Marksmanship','Warlock-Destruction','Warlock-Demonology','Hunter-BeastMastery','Shaman-Restoration','Shaman-Enhancement','Paladin-Retribution','Rogue-Assassination','Warrior-Protection','Evoker-Devastation','Priest-Shadow','DemonHunter-Devourer','Paladin-Protection','Shaman-Elemental','Evoker-Augmentation','Evoker-Preservation','Druid-Guardian','Warlock-Affliction','Mage-Fire','DeathKnight-Frost','Warrior-Fury','Rogue-Outlaw','Hunter-Survival','Mage-Arcane',}
local provider = {region='US',realm='Dreadmaul',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abbathdoom:BAABLgAECn8UAAIBAAgJJgmRJgAyAQABAAgJJgmRJgAyAQAAAA==.',
Ae='Aedaris:BAABLgAECn9XAAMCAAkJPCDMDABxAgACAAcJDiHMDABxAgADAAYJHhkyIwCFAQAAAA==.Ael:BAAALgAECgEJAQAAAA==.Aethalides:BAAALgAECgYJDwAAAA==.',
Al='Alandrias:BAAALgAECgkJAQAAAA==.Aloremirin:BAAALgADCgUJBQAAAA==.Altaria:BAABLgAFFH8VAAQEAAYJDxhdFABJAQAEAAUJKR1dFABJAQAFAAQJ7xVADwAfAQAGAAEJ2gcHPQBEAAAAAA==.Alvv:BAAALgADCgMJBQAAAA==.Alvz:BAAALgADCgMJAwAAAA==.',
Am='Ametrigos:BAAALgAECgEJAQABLgAECggJIgAHAB4iAA==.',
An='Anouke:BAAALgADCgIJAgAAAA==.Anserion:BAAALgADCgMJAwAAAA==.Anvious:BAAALgAECgcJDAAAAA==.',
Aq='Aquilea:BAABLgAECn8ZAAMIAAgJLRBSEAB7AQAIAAgJLRBSEAB7AQAJAAEJhgZIgQAmAAAAAA==.',
Ar='Arcfuldodger:BAAALgAECgEJAgAAAA==.Artais:BAABLgAECn8gAAIKAAgJ1Rx8FgCCAgAKAAgJ1Rx8FgCCAgAAAA==.Artzlayer:BAACLgAFFH8IAAILAAMJrxvYaQD2AAALAAMJrxvYaQD2AAAuAAQKfzAAAwsACQlXI4QKAPwCAAsACQlXI4QKAPwCAAwAAQkAAFZcAAAAAAAA.Aríes:BAABLgAECn9RAAMNAAkJ3xoqCQBrAgANAAkJ3xoqCQBrAgAOAAEJGAnkLAAsAAAAAA==.',
As='Ashbourne:BAAALgADCgcJCwAAAA==.',
Aw='Aw:BAAALgAECgYJEQABLgAFFAYJFgAPAFwVAA==.Awry:BAEBLgAECn8rAAILAAgJYx9sJwBBAgALAAgJYx9sJwBBAgAAAA==.Awuuga:BAAALgAECgEJAQABLgAECgYJEgAQAAAAAA==.Aww:BAACLgAFFH8WAAIPAAYJXBXYIQCbAQAPAAYJXBXYIQCbAQAuAAQKfxwAAg8ACAkmFwV/ANMBAA8ACAkmFwV/ANMBAAAA.',
Az='Azamalaza:BAABLgAECn8nAAIRAAgJbyKdBABHAgARAAgJbyKdBABHAgAAAA==.Azmo:BAACLgAFFH8JAAMSAAMJ5hiEBwDhAAASAAMJDRaEBwDhAAATAAMJBgwNOQCiAAAuAAQKfyUAAxIACAkvIcECANYCABIACAmJHcECANYCABMABQk9HL1gAKcBAAAA.Azulon:BAAALgADCgUJBQABLgAECggJGgADAOkZAA==.Azyrt:BAAALgAECgQJBAABLgAECggJIAAKANUcAA==.',
Ba='Badds:BAAALgAECggJDwAAAA==.Ballona:BAAALgADCgUJBQAAAA==.Barad:BAAALgAECgEJAwAAAA==.Batrick:BAAALgADCgcJBwAAAA==.Baulric:BAAALgAECgEJAQAAAA==.Bawls:BAAALgAFFAIJAwAAAA==.',
Be='Beastroll:BAAALgAECgYJEgAAAA==.Beefrod:BAAALgADCgEJAQAAAA==.Beenis:BAAALgADCgUJBQABLgAFFAIJAgAQAAAAAA==.Belerick:BAABLgAFFH8JAAIJAAMJnQqfDwDoAAAJAAMJnQqfDwDoAAAAAA==.Belphine:BAAALgAECgYJCAAAAA==.',
Bi='Bicksmage:BAABLgAFFH8KAAIPAAMJMBTsZADsAAAPAAMJMBTsZADsAAAAAA==.Bigdaddylock:BAACLgAFFH8SAAMTAAcJohgoGwCSAQATAAYJ8RcoGwCSAQASAAEJGBwxEwBgAAAuAAQKfyUAAxIACQnoJE4IAD4CABMACAkzI6IuAFICABIABgm1Ik4IAD4CAAAA.Biluman:BAAALgAECgQJBAAAAA==.Biodeath:BAAALgADCgUJBQAAAA==.Biopally:BAAALgADCgYJDQAAAA==.Biorogue:BAAALgADCgYJDAAAAA==.Bishope:BAABLgAECn8aAAIDAAgJ6RlpDAB7AgADAAgJ6RlpDAB7AgAAAA==.',
Bl='Bllizard:BAAALgAECgEJAQAAAA==.Bloodache:BAAALgADCgcJDgABLgAECgUJFwALAA4SAA==.Bluecar:BAAALgAECgYJCAAAAA==.',
Bo='Bohica:BAAALgAECgIJBQAAAA==.Bombdiggity:BAABLgAECn8vAAIDAAcJjx0pDwBQAgADAAcJjx0pDwBQAgAAAA==.Bonnierot:BAAALgAECgUJCgAAAA==.Boypally:BAAALgAECggJCQAAAA==.',
Br='Brecciana:BAAALgADCgUJBQAAAA==.Brewjitsu:BAABLgAECn9IAAIEAAkJkR0yBwCmAgAEAAkJkR0yBwCmAgAAAA==.Brick:BAACLgAFFH8JAAMEAAMJeSFhGgAnAQAEAAMJeSFhGgAnAQAGAAEJ9BWcPQBCAAAuAAQKfx8AAgQABwl6HuQaAC0CAAQABwl6HuQaAC0CAAEuAAUUBwkfABMAGB4A.Brongakill:BAAALgADCgYJBgAAAA==.Bräinfreeze:BAAALgAECgkJBwAAAA==.',
Bu='Buffy:BAAALgAECgEJAgAAAA==.Bumble:BAAALgADCgYJBgABLgAFFAgJIgACADkbAA==.Bundalock:BAAALgADCgYJEQAAAA==.',
Ca='Cakebringer:BAAALgAECgcJEgAAAA==.Carbos:BAAALgAFFAEJAQAAAA==.Caroshi:BAABLgAECn8lAAIPAAgJjw4oawCIAQAPAAgJjw4oawCIAQAAAA==.',
Ce='Cell:BAAALgAECgUJCAABLgAECggJGQAUABYVAA==.Ceridwen:BAAALgADCgEJAQAAAA==.',
Ch='Charlotte:BAAALgAECgMJCwAAAA==.Cheto:BAAALgAFFAIJAgABLgAFFAUJEAAVAMwbAA==.Chosen:BAAALgADCgEJAQAAAA==.Chud:BAAALgAECgUJBQABLgAFFAYJGQAWAHgjAA==.',
Ci='Cig:BAABLgAECn8YAAIXAAgJ/xDKZgCCAQAXAAgJ/xDKZgCCAQAAAA==.',
Cl='Clankychan:BAACLgAFFH8LAAIEAAMJTA0HMADIAAAEAAMJTA0HMADIAAAuAAQKfxgAAgQABwkMFW00ABABAAQABwkMFW00ABABAAAA.Cloneofmagic:BAAALgADCgcJBwAAAA==.',
Co='Combustanut:BAAALgAECgUJEAAAAA==.Comillmouth:BAABLgAECn8ZAAIDAAgJbxE1IACdAQADAAgJbxE1IACdAQAAAA==.Comillthroat:BAAALgAECgkJEQAAAA==.Cos:BAABLgAECn82AAMBAAkJbxE/EgDwAQABAAkJbxE/EgDwAQAYAAMJOAXFFgCKAAAAAA==.',
Cr='Crozier:BAAALgAECgIJAwAAAA==.Cryptum:BAAALgAECgkJBAAAAA==.Cryten:BAAALgAECgIJAgAAAA==.',
Cu='Curby:BAAALgAECgcJBwABLgAECgkJTgAZAJ4eAA==.',
['Cä']='Cäin:BAAALgAECgQJCAAAAA==.',
Da='Dabufart:BAAALgADCgEJAQAAAA==.Daerus:BAAALgAECgYJBQAAAA==.Damge:BAAALgAECgUJCgAAAA==.Damnnyou:BAAALgAECgcJBwABLgAECgkJIwAaAK0ZAA==.Danky:BAAALgAECgMJAwAAAA==.Danteh:BAAALgAFFAEJAwAAAA==.Darahug:BAAALgAECgYJBgAAAA==.Daraina:BAAALgADCgEJAQABLgADCgEJAQAQAAAAAA==.Darktalanus:BAAALgADCgQJBAAAAA==.Darrkton:BAAALgADCgEJAQAAAA==.Dathil:BAAALgAECgYJCQAAAA==.Davmonhunter:BAAALgADCgQJBAAAAA==.Davoodooman:BAAALgAECgIJAgAAAA==.',
De='Deadiemurphy:BAAALgADCgYJCQAAAA==.Deathshunter:BAABLgAECn8iAAMUAAkJwCMKDADOAgAUAAgJWSUKDADOAgARAAYJ+hkjOgB5AQABLgAFFAYJFgALAOEhAA==.Deaththorn:BAAALgADCgEJAQAAAA==.Debsi:BAABLgAECn8bAAIZAAkJ/gxiFACDAQAZAAkJ/gxiFACDAQAAAA==.Deeper:BAAALgAFFAIJBAAAAA==.Deepest:BAAALgAFFAIJAgAAAA==.Deloraine:BAACLgAFFH8lAAIbAAYJWSW9AgAlAgAbAAYJWSW9AgAlAgAuAAQKfycAAhsACQkAItgDAAgDABsACQkAItgDAAgDAAAA.Demonicfaith:BAABLgAECn82AAMNAAcJbxqFFwAMAgANAAYJTx6FFwAMAgAcAAcJlQzbgAAoAQAAAA==.Denman:BAABLgAECn8YAAMXAAcJjBnRdgCNAQAXAAcJjBnRdgCNAQAdAAEJmAAmUAAKAAAAAA==.Dezarian:BAAALgAECggJCAAAAA==.',
Di='Dirtyfux:BAACLgAFFH8JAAIDAAMJ5RJeIwDhAAADAAMJ5RJeIwDhAAAuAAQKfxUAAwMABglsHJ8jAIEBAAMABglsHJ8jAIEBAAIAAQkZDweDAC4AAAAA.Dirtysham:BAACLgAFFH8MAAIVAAQJcRqlHgA3AQAVAAQJcRqlHgA3AQAuAAQKfzAAAxUACQm3H/0MALUCABUACAl1If0MALUCAB4ABAmHCidWALIAAAAA.Discipline:BAAALgADCgcJBwAAAA==.Disckin:BAAALgAECgEJAQAAAA==.Diseasemode:BAAALgAECgEJAQAAAA==.Divinechill:BAAALgADCgQJBQAAAA==.',
Dn='Dnb:BAAALgADCgEJAQABLgAFFAYJFgAPAFwVAA==.Dnk:BAAALgADCgMJAwAAAA==.',
Do='Dom:BAAALgADCgcJCQAAAA==.Donki:BAAALgAECgkJDAAAAA==.Doodtanky:BAAALgADCgEJAQAAAA==.Doomvedas:BAAALgAECgYJCgAAAA==.',
Dr='Dracaena:BAABLgAECn8jAAQaAAkJrRmDBQDlAQAfAAgJkBT/GwDoAQAaAAgJtBeDBQDlAQAgAAUJQwizMQDiAAAAAA==.Draco:BAAALgAECgMJAwAAAA==.Dreadknìght:BAAALgAFFAQJAgAAAA==.Drekavach:BAAALgADCgcJEwAAAA==.Droidbick:BAAALgAFFAIJAgAAAA==.',
['Dâ']='Dâftmonk:BAAALgAECgQJBgABLgAECggJCgAQAAAAAA==.',
Ee='Eevo:BAAALgAECgMJAwABLgAECggJFAAGAJEIAA==.',
El='Elaha:BAAALgAECgcJCQAAAA==.Elexann:BAAALgAECgkJAQAAAA==.Elibaba:BAAALgAECgkJDgABLgAFFAIJAgAQAAAAAA==.Elideady:BAAALgAFFAIJAgAAAA==.Elinaa:BAAALgAECgIJAgAAAA==.Elindyl:BAAALgADCgEJAQAAAA==.Elleth:BAAALgADCgIJAgAAAA==.Elvishcheese:BAAALgAECgMJBgAAAA==.',
Em='Emojis:BAAALgAECgUJCQAAAA==.',
En='Endlessdh:BAACLgAFFH8IAAINAAMJCiIKBwDIAAANAAMJCiIKBwDIAAAuAAQKfxwAAg0ABwkyJJUJAMgCAA0ABwkyJJUJAMgCAAAA.',
Er='Eraserhead:BAAALgAECgYJEwABLgAFFAYJGQAWAHgjAA==.Erissaria:BAAALgADCgEJAQAAAA==.',
Ev='Evening:BAAALgAECgMJBAAAAA==.Everbuddha:BAAALgAECgQJBgAAAA==.',
Ew='Ewa:BAAALgAECgMJBAAAAA==.Eww:BAABLgAECn8XAAIcAAcJyw+HYgA+AQAcAAcJyw+HYgA+AQAAAA==.',
Ez='Ezelia:BAACLgAFFH8FAAIXAAMJ0BK5SwDrAAAXAAMJ0BK5SwDrAAAuAAQKfxoAAxcACQl+Frg1AAkCABcACQl+Frg1AAkCAAcAAQlGCVeVADUAAAEuAAUUBwkvAAIAWBkA.',
Fa='Faelune:BAABLgAECn8ZAAIPAAgJmwfHhwBMAQAPAAgJmwfHhwBMAQAAAA==.Faldir:BAAALgADCgYJBAABLgAFFAQJCgAcAL8WAA==.',
Fe='Ferndru:BAABLgAECn8UAAIhAAYJzA4qJwDWAAAhAAYJzA4qJwDWAAAAAA==.',
Fi='Fish:BAAALgAECgEJAgABLgAFFAQJCAAgAJ0XAA==.Fisticuffs:BAACLgAFFH8SAAIGAAYJdRDbEACPAQAGAAYJdRDbEACPAQAuAAQKfyIAAgYACAl3GPsXABsCAAYACAl3GPsXABsCAAAA.',
Fl='Flameshock:BAAALgAFFAIJBAAAAA==.Flowki:BAAALgADCgYJBQAAAA==.',
Fo='Forcespark:BAAALgAECgEJAQAAAA==.',
Fr='Fraserker:BAAALgAECgEJAQAAAA==.Frostradamus:BAAALgADCgkJCgAAAA==.',
Fu='Fullmoonride:BAAALgAECgUJCQAAAA==.Fumbll:BAAALgAECgkJCQAAAA==.Funkymajik:BAABLgAECn8ZAAQDAAgJmA0XIQCWAQADAAgJmA0XIQCWAQACAAIJiAaJdQBTAAAbAAEJtQtOYgA0AAAAAA==.Furiosa:BAAALgADCgkJDgAAAA==.',
Ga='Gallywox:BAAALgADCgMJAwAAAA==.Ganin:BAABLgAECn8bAAIHAAYJUBU0QgBvAQAHAAYJUBU0QgBvAQAAAA==.Gankinyou:BAAALgADCgEJAQAAAA==.Garielyn:BAAALgADCgEJAQAAAA==.Garugala:BAACLgAFFH8KAAIXAAMJHxRDSQDwAAAXAAMJHxRDSQDwAAAuAAQKfysAAhcACQklGAAnAEYCABcACQklGAAnAEYCAAAA.',
Gd='Gdaycøb:BAAALgADCgYJBwAAAA==.',
Ge='Gengár:BAAALgAECgMJBgABLgAECggJEgAQAAAAAA==.',
Gh='Ghalorin:BAAALgAECgMJDAAAAA==.Ghiroza:BAABLgAECn9RAAQSAAkJ4R3fCAAzAgATAAkJ3B0fHQBcAgASAAgJihbfCAAzAgAiAAMJkhZpHQCGAAAAAA==.',
Gi='Gigaevoker:BAABLgAECn8kAAIgAAgJcRbQCgALAgAgAAgJcRbQCgALAgAAAA==.Gigapaladin:BAAALgADCgQJBAAAAA==.Gingarthas:BAABLgAECn8iAAILAAkJPh08LgAjAgALAAkJPh08LgAjAgAAAA==.',
Gl='Glowingtoe:BAAALgAECgMJBQAAAA==.',
Go='Gogmazios:BAAALgADCgcJBwAAAA==.',
Gr='Gravytate:BAABLgAECn9XAAIeAAkJfA/lJQCNAQAeAAkJfA/lJQCNAQAAAA==.Griinn:BAABLgAECn8dAAIhAAkJSg7nFgBbAQAhAAkJSg7nFgBbAQAAAA==.Grimefiend:BAAALgAFFAIJAgAAAA==.Grimescene:BAAALgAECgIJAgAAAA==.Grimreapêr:BAAALgAECgEJAgAAAA==.',
Gu='Guldannyboy:BAABLgAECn80AAMSAAkJSw1sCgBuAQASAAkJygxsCgBuAQATAAkJFwcVYgBlAQAAAA==.Gumbö:BAAALgAECgcJCQABLgAECggJIAAKANUcAA==.',
Ha='Haides:BAAALgAECgIJAgAAAA==.Hammer:BAAALgAECgIJAgABLgAECggJCgAQAAAAAA==.Hantore:BAAALgADCgMJAwAAAA==.Harmony:BAAALgAECgEJAQAAAA==.Harry:BAACLgAFFH8GAAIWAAMJohc6CADwAAAWAAMJohc6CADwAAAuAAQKfycAAxYACQljJOUBAD8DABYACQljJOUBAD8DABUABwnEGuMgABoCAAAA.',
He='Heartdh:BAABLgAECn8VAAMcAAgJkhIkRQCVAQAcAAgJkhIkRQCVAQANAAIJrxOGWwByAAAAAA==.Heisenbergg:BAAALgADCgIJAgAAAA==.Hellza:BAAALgAECgMJAwAAAA==.Hen:BAAALgAECgUJBQABLgAECgYJFQAMABAVAA==.Herpyprotect:BAAALgAFFAIJAwAAAA==.Herrion:BAACLgAFFH8fAAQTAAcJGB7kDQDbAQATAAYJSB7kDQDbAQAiAAEJyB9GDgBgAAASAAEJKx0BEwBgAAAuAAQKfy4AAxMACQn/IvkcAKgCABMACAn/IvkcAKgCABIABAmcJNMUAKQBAAAA.',
Hh='Hh:BAAALgAECgEJAQAAAA==.',
Ho='Holytanky:BAAALgAECgIJAgAAAA==.Hotspur:BAABLgAECn84AAIKAAgJaxDUOADDAQAKAAgJaxDUOADDAQAAAA==.',
Hu='Hukani:BAAALgAECgEJAwABLgAECggJFgACALEIAA==.Hunner:BAAALgAECgIJAgABLgAECggJFAAGAJEIAA==.Huskar:BAABLgAECn8ZAAIUAAgJFhXFMgDoAQAUAAgJFhXFMgDoAQAAAA==.',
Hy='Hypoxi:BAAALgADCgYJCQAAAA==.',
Ig='Ignis:BAABLgAECn8cAAIjAAkJmR0cAQCQAgAjAAkJmR0cAQCQAgAAAA==.Ignitor:BAAALgADCgEJAQAAAA==.',
Ik='Ikari:BAABLgAECn9VAAISAAkJyhr4AgBOAgASAAkJyhr4AgBOAgAAAA==.',
Il='Illadoss:BAAALgADCgIJAgAAAA==.',
Im='Imntprepared:BAAALgAECgkJCQAAAA==.',
In='Incarnate:BAAALgAECgEJAgAAAA==.Incubis:BAAALgADCgIJAgAAAA==.Infectîon:BAAALgADCgYJBgAAAA==.Inferlock:BAAALgADCgUJBAAAAA==.Infernyos:BAAALgADCgEJAQAAAA==.Infernyoz:BAAALgADCggJCQAAAA==.',
Ir='Irithel:BAAALgAECgcJBQAAAA==.',
Is='Isohexene:BAAALgADCgYJBgAAAA==.',
It='Itchygrowth:BAAALgAFFAEJAQAAAA==.',
Iv='Ivygambina:BAAALgADCgYJBgAAAA==.Ivysore:BAAALgAECgUJBwAAAA==.',
Ja='Jasha:BAAALgADCgcJCwAAAA==.Jayy:BAABLgAECn8bAAILAAkJBRCKTAANAgALAAkJBRCKTAANAgAAAA==.',
Je='Jennatalia:BAAALgAECggJEgAAAA==.',
Ji='Jinkazamaz:BAAALgAFFAIJBAAAAA==.',
Jo='Joelsdruid:BAABLgAFFH8PAAIhAAQJxhvFBQBSAQAhAAQJxhvFBQBSAQAAAA==.Joelvoker:BAAALgAFFAIJAgABLgAFFAQJDwAhAMYbAA==.Joexotic:BAAALgAECgIJBwAAAA==.Jongwang:BAAALgAECgQJBwAAAA==.',
Ju='Jubjub:BAAALgAECgEJAgAAAA==.',
Ka='Kaaru:BAABLgAECn8lAAMDAAkJjBO0EgAhAgADAAkJehK0EgAhAgACAAUJExKGSAAXAQAAAA==.Kaiforst:BAAALgAECgQJBAABLgAECgkJNAAXAJEXAA==.Kaihavocz:BAAALgAECgEJAgAAAA==.Kairon:BAABLgAECn80AAIXAAkJkRd2LwAhAgAXAAkJkRd2LwAhAgAAAA==.Kalysae:BAAALgADCgEJAQAAAA==.Katarinabluu:BAAALgAECgYJBgAAAA==.Kazakhthundr:BAAALgADCgYJBgAAAA==.',
Ke='Keeanuleaves:BAAALgADCgYJBwAAAA==.Keeanuweaves:BAAALgADCgEJAQAAAA==.Keeze:BAACLgAFFH8NAAIPAAQJYQi6VgAWAQAPAAQJYQi6VgAWAQAuAAQKfxgAAg8ACQkaE4pHAOkBAA8ACQkaE4pHAOkBAAAA.',
Ki='Kickstarter:BAAALgAECgYJEgAAAA==.Kiel:BAAALgAECgEJAQAAAA==.Killania:BAAALgADCgMJAwAAAA==.Kiwichaos:BAACLgAFFH8KAAINAAQJnQmfEwC8AAANAAQJnQmfEwC8AAAuAAQKfy4AAg0ACQlbGzMKAFUCAA0ACQlbGzMKAFUCAAAA.',
Kl='Klckyourass:BAAALgADCgYJCwAAAA==.',
Kn='Knox:BAAALgAECgUJBwAAAA==.',
Ko='Korner:BAAALgAECgIJAgAAAA==.',
Kr='Krazzul:BAAALgADCgYJBgAAAA==.Krellis:BAABLgAECn8WAAMFAAgJBxBuIwBsAQAFAAgJBxBuIwBsAQAGAAYJtRA8MQAzAQAAAA==.Kritikall:BAAALgADCgUJBQAAAA==.',
Ku='Kurö:BAAALgAECgEJAQAAAA==.',
Kv='Kvôthe:BAABLgAECn8XAAMLAAgJjgoRhQA0AQALAAgJjAgRhQA0AQAkAAMJzQf0HgCDAAAAAA==.',
Ky='Kynnareth:BAAALgAFFAIJBAABLgAFFAYJDgADAHMLAA==.Kynralol:BAABLgAECn85AAIPAAgJKCEtKQBZAgAPAAgJKCEtKQBZAgAAAA==.',
['Ká']='Káiser:BAAALgAECggJEQAAAA==.',
La='Laenosh:BAABLgAECn8XAAILAAUJDhKcswDlAAALAAUJDhKcswDlAAAAAA==.Laomoo:BAAALgAECgcJDgAAAA==.',
Le='Learning:BAABLgAECn8XAAIeAAcJEh9LGwA4AgAeAAcJEh9LGwA4AgAAAA==.Legham:BAAALgADCgkJDgAAAA==.Legolazz:BAABLgAECn8yAAMUAAkJ4B6aEQCbAgAUAAkJ4B6aEQCbAgARAAMJCBS1IwBvAAAAAA==.Lemins:BAAALgAECgMJAwAAAA==.Lemondruid:BAAALgAECgIJAgAAAA==.Lemonmelon:BAAALgAECgYJEwAAAA==.Lenatheplug:BAACLgAFFH8YAAMBAAYJIxoMAwDMAQABAAUJNSAMAwDMAQAYAAIJjQnKBQBgAAAuAAQKfyIAAwEACAmUJEQKAO0CAAEACAnbI0QKAO0CABgABwlAIt4DAIACAAAA.Lerust:BAAALgADCgcJBwAAAA==.',
Li='Liadrine:BAABLgAECn8wAAIXAAkJ4xffNwACAgAXAAkJ4xffNwACAgAAAA==.Linus:BAAALgAECgYJBgABLgAFFAcJHwATABgeAA==.Littleriver:BAAALgAECgcJEQAAAA==.',
Ll='Llewser:BAABLgAECn8ZAAMPAAcJHxeSXACsAQAPAAcJHxeSXACsAQAjAAEJqgSMDwAwAAAAAA==.',
Lo='Loathe:BAAALgAECgEJAgAAAA==.Loistiah:BAABLgAFFH8IAAILAAMJZhkcagD1AAALAAMJZhkcagD1AAAAAA==.Lothaof:BAABLgAECn8sAAIXAAkJ6RKWRwDQAQAXAAkJ6RKWRwDQAQAAAA==.Louisvuitton:BAAALgAECgUJDwAAAA==.',
Lp='Lpayn:BAAALgADCgEJAQAAAA==.',
Lu='Lugroth:BAAALgAECgEJAgABLgAFFAcJHwATABgeAA==.Lunana:BAAALgAECgcJEgAAAA==.',
Ly='Lychiee:BAAALgAECgcJEQAAAA==.',
['Lì']='Lìnkinbark:BAAALgAECgMJAwAAAA==.',
Ma='Madara:BAAALgAECgEJAgAAAA==.Magesorry:BAAALgADCgUJBQAAAA==.Magicmon:BAAALgADCgUJBQAAAA==.Maize:BAABLgAECn8iAAMDAAgJMBsYDwBRAgADAAgJMBsYDwBRAgACAAMJhgvTZwCOAAAAAA==.Makima:BAABLgAFFH8FAAIJAAUJmQ4iIQDsAAAJAAUJmQ4iIQDsAAABLgAFFAUJIgAJAN4aAA==.Malikai:BAAALgADCgcJDAAAAA==.Marcymonk:BAAALgADCgEJAQAAAA==.Marcyon:BAABLgAECn8ZAAIcAAYJqAkXmQDEAAAcAAYJqAkXmQDEAAAAAA==.Marywinston:BAAALgAFFAEJAQABLgAFFAIJBgAMAFMUAA==.',
Mc='Mchèalz:BAABLgAECn8VAAQDAAgJRAjpLwAwAQADAAgJRAjpLwAwAQACAAQJxAFFaQCIAAAbAAIJOwF0ZgAsAAAAAA==.',
Me='Melonlemonza:BAAALgADCgQJBAAAAA==.Mentok:BAAALgAECgYJCwAAAA==.Merchei:BAAALgAECgUJBgAAAA==.Meruen:BAABLgAECn8mAAIcAAgJJhzyHwA3AgAcAAgJJhzyHwA3AgAAAA==.',
Mi='Miss:BAAALgAECgEJAQAAAA==.Mistie:BAAALgAECgEJAQABLgAECgUJBQAQAAAAAA==.Mitymorphin:BAAALgADCgEJAQAAAA==.',
Mo='Mobility:BAAALgAFFAEJAQAAAA==.Moistpole:BAAALgADCgQJBAAAAA==.Momock:BAAALgAECgQJBAAAAA==.Mongk:BAABLgAECn8UAAIGAAgJkQibNQAZAQAGAAgJkQibNQAZAQAAAA==.Monscustodes:BAABLgAECn8hAAIPAAkJ0Qz/WwCtAQAPAAkJ0Qz/WwCtAQAAAA==.Monstersauce:BAAALgAFFAIJAgAAAA==.Mookin:BAAALgAECgcJCAAAAA==.Moospoon:BAABLgAECn8rAAIXAAgJURD8YgCLAQAXAAgJURD8YgCLAQAAAA==.Mooudini:BAAALgAECgMJAwAAAA==.Moounka:BAABLgAECn9BAAIEAAgJOxUoGgC1AQAEAAgJOxUoGgC1AQAAAA==.Morphio:BAABLgAECn9BAAMUAAkJviM4BQAgAwAUAAkJviM4BQAgAwARAAUJCxOaTAAfAQAAAA==.Mostakrakish:BAAALgADCgEJAQAAAA==.',
Mu='Muddles:BAABLgAECn9EAAIEAAkJUBiJDgAzAgAEAAkJUBiJDgAzAgAAAA==.Murius:BAACLgAFFH8JAAILAAMJkQRYhwDDAAALAAMJkQRYhwDDAAAuAAQKfzIAAgsACQlEF+orAC0CAAsACQlEF+orAC0CAAAA.',
My='Mysterio:BAAALgAFFAEJAgAAAA==.',
Na='Naendria:BAAALgAECgMJBAAAAA==.Naga:BAAALgAECgIJAgAAAA==.Nahaza:BAAALgAECgEJAgAAAA==.',
Ne='Nelena:BAAALgADCgEJAQAAAA==.',
Ni='Nickdoom:BAAALgAECgUJEwAAAA==.Nigella:BAABLgAECn8WAAMCAAgJsQjUMQAeAQACAAgJsQjUMQAeAQADAAEJ6wFHbgAhAAAAAA==.Nikola:BAABLgAECn8nAAQKAAgJAxdnNwDKAQAKAAgJAxdnNwDKAQAhAAUJOBbfFQAUAQAJAAQJfQ9/VADUAAAAAA==.Nimro:BAACLgAFFH8XAAIZAAYJdxVpBgCRAQAZAAYJdxVpBgCRAQAuAAQKfygAAhkACQmPH6ADABsDABkACQmPH6ADABsDAAAA.Niub:BAABLgAECn8lAAIlAAgJ/BG0KQCMAQAlAAgJ/BG0KQCMAQAAAA==.',
No='Nofate:BAAALgADCgEJAQAAAA==.Noirebringer:BAAALgAFFAEJAQAAAA==.',
Nt='Ntrldrake:BAAALgADCgEJAgABLgAECgkJIQAPANEMAA==.',
Nu='Nuferax:BAABLgAECn8ZAAIOAAgJGiH+AgCUAgAOAAgJGiH+AgCUAgAAAA==.Nulledhacz:BAAALgADCgEJAQAAAA==.Numbrethree:BAACLgAFFH8TAAIGAAQJ/hHCHgD9AAAGAAQJ/hHCHgD9AAAuAAQKf0MAAgYACAmcGBMaAAgCAAYACAmcGBMaAAgCAAAA.',
Ob='Obbi:BAACLgAFFH8QAAIYAAQJVyVJAwBaAQAYAAQJVyVJAwBaAQAuAAQKfxkAAhgACQknIIsBAMsCABgACQknIIsBAMsCAAAA.',
Oh='Ohaither:BAAALgAECgQJBAAAAA==.',
Oi='Oirth:BAAALgADCgIJAgAAAA==.',
Ok='Okiji:BAAALgAECgkJEwAAAA==.',
Or='Orinocco:BAAALgAECgEJAwAAAA==.Orobas:BAAALgAECgcJCQAAAA==.',
Pa='Pakaww:BAAALgAECgIJAwAAAA==.Palimathrus:BAAALgAECgUJCAAAAA==.Palliative:BAABLgAECn9BAAMHAAgJDyKbCgC+AgAHAAgJDyKbCgC+AgAXAAQJLwXC7AClAAAAAA==.Pallidnim:BAAALgAFFAEJAwAAAA==.Papager:BAAALgAECgEJAwAAAA==.',
Pe='Pea:BAAALgAECgcJEAAAAA==.Perish:BAAALgAECggJDQABLgAECgkJRAAEAFAYAA==.',
Ph='Phatmonk:BAACLgAFFH8QAAIFAAQJsyVvAwC1AQAFAAQJsyVvAwC1AQAuAAQKfy8AAwUACQn4JBkCAD4DAAUACQn4JBkCAD4DAAYABgk8IBA6ADEBAAAA.Phatrogue:BAAALgAFFAMJBAABLgAFFAQJEAAFALMlAA==.',
Pi='Piewpiew:BAAALgADCgcJCgAAAA==.Pix:BAACLgAFFH8cAAMbAAcJZR3HBQDHAQAbAAcJZR3HBQDHAQADAAUJvQyTFQBuAQAuAAQKfzYAAhsACQk5JW8BAFoDABsACQk5JW8BAFoDAAAA.',
Pl='Pleasuremax:BAABLgAECn8aAAIUAAgJLBXsNADfAQAUAAgJLBXsNADfAQAAAA==.Plex:BAABLgAECn8/AAIIAAkJRRpGBQB0AgAIAAkJRRpGBQB0AgAAAA==.',
Po='Poogie:BAAALgADCgYJBgABLgAECgMJBQAQAAAAAA==.Popshot:BAABLgAECn8eAAIRAAYJ5xIiRQBBAQARAAYJ5xIiRQBBAQAAAA==.Portalhouse:BAAALgAECgEJAQAAAA==.',
Pr='Praxis:BAACLgAFFH8JAAIZAAMJ2gnKGACnAAAZAAMJ2gnKGACnAAAuAAQKfx0AAhkACAniDXsXAF0BABkACAniDXsXAF0BAAAA.Preast:BAAALgAECgcJBwABLgAECggJFAAGAJEIAA==.Procist:BAAALgAECgkJDAABLgAECgkJMQAVAMQiAA==.',
Py='Pyrusdk:BAABLgAECn8ZAAILAAkJgQ5eTgC0AQALAAkJgQ5eTgC0AQAAAA==.Pyrusdruid:BAAALgAECgkJEAAAAA==.',
Qo='Qop:BAAALgAECgkJBgAAAA==.',
Qu='Quesarah:BAAALgADCgEJAQABLgAECgQJBAAQAAAAAA==.',
Qw='Qweffor:BAAALgAECgUJBQABLgAECggJFgALAB0YAA==.',
Ra='Rainbowkelly:BAAALgAECgQJBAAAAA==.Raìn:BAACLgAFFH8GAAILAAIJOQ/cpQCTAAALAAIJOQ/cpQCTAAAuAAQKfxQAAgsACAnYFahDANUBAAsACAnYFahDANUBAAAA.',
Re='Reapy:BAABLgAFFH8IAAILAAMJpQs0fgDXAAALAAMJpQs0fgDXAAAAAA==.Recruitqt:BAABLgAECn8YAAMHAAUJxhkPOgCRAQAHAAUJxhkPOgCRAQAXAAEJ1gZCbgEtAAAAAA==.Reiayanami:BAABLgAECn8fAAIPAAgJfA/OawCHAQAPAAgJfA/OawCHAQAAAA==.',
Ri='Ripandtear:BAABLgAECn8XAAMKAAkJzBZwJgD5AQAKAAkJzBZwJgD5AQAIAAEJFQZ6NgAsAAAAAA==.',
Ro='Roguewan:BAAALgAFFAIJAgAAAA==.Rolâyne:BAAALgADCgkJDgAAAA==.Roninn:BAABLgAECn8rAAIKAAkJVSFEBABgAwAKAAkJVSFEBABgAwAAAA==.Ronlock:BAABLgAECn8VAAMTAAYJ8xD9nQAdAQATAAUJ8xD9nQAdAQASAAEJAAABagA+AAABLgAECgcJNgANAG8aAA==.Royaltits:BAAALgADCgIJAgAAAA==.',
Rs='Rsi:BAAALgAECgQJBAAAAA==.',
Ry='Rynaea:BAAALgAECgUJBgAAAA==.',
['Rï']='Rïmuru:BAAALgADCgcJCwAAAA==.',
['Rô']='Rôlayne:BAABLgAECn8ZAAIlAAgJdQvaNgBGAQAlAAgJdQvaNgBGAQAAAA==.',
Sa='Salvare:BAABLgAECn8lAAMYAAkJhhhwAwCVAgAYAAkJfRhwAwCVAgAmAAIJRRCiFgBxAAAAAA==.Sappy:BAAALgAECgQJBAAAAA==.Sauron:BAAALgADCgEJAQABLgAFFAQJDAATACgUAA==.',
Sb='Sbf:BAABLgAFFH8VAAIfAAcJZA+ADQCyAQAfAAcJZA+ADQCyAQABLgAFFAcJNwAPACccAA==.',
Sc='Scalamander:BAAALgAECgcJAgAAAA==.Sciohunter:BAABLgAFFH8FAAINAAIJIAxcGACIAAANAAIJIAxcGACIAAAAAA==.Scioscioz:BAACLgAFFH8JAAIKAAMJfBRELQDeAAAKAAMJfBRELQDeAAAuAAQKfyAAAwoABwnOFOI7ALUBAAoABwnOFOI7ALUBAAkAAglnEAJsAHAAAAAA.Scwisgar:BAAALgAECgkJDQAAAA==.',
Se='Sedge:BAAALgAFFAIJAwAAAA==.Sephire:BAABLgAECn8eAAIXAAkJPASvpgALAQAXAAkJPASvpgALAQAAAA==.Sermazule:BAAALgADCgcJEQAAAA==.Sewerface:BAABLgAECn8VAAMMAAYJEBWaHgBTAQAMAAYJEBWaHgBTAQALAAMJLAScAQF2AAAAAA==.',
Sh='Shadonir:BAAALgAECgQJBAAAAA==.Shadowind:BAACLgAFFH8UAAIUAAQJux5IFwBjAQAUAAQJux5IFwBjAQAuAAQKfy8AAxEACQmGHn4dADsCABEACAlEGX4dADsCABQABQlkHdNMAI4BAAAA.Shaft:BAAALgAECgEJAQAAAA==.Shallotte:BAABLgAECn8YAAMiAAgJdRDoCwB7AQAiAAcJABLoCwB7AQATAAcJoghcgwAdAQAAAA==.Shammalxs:BAABLgAFFH8GAAIeAAUJSQTtGAAgAQAeAAUJSQTtGAAgAQAAAA==.Shamoc:BAABLgAECn8xAAMVAAkJxCI9BABPAwAVAAkJxCI9BABPAwAeAAYJohESSQAjAQAAAA==.Shampooing:BAABLgAECn8lAAIeAAgJ2RgOHADUAQAeAAgJ2RgOHADUAQAAAA==.Sharpknife:BAABLgAFFH8LAAIUAAMJRhERRQDfAAAUAAMJRhERRQDfAAAAAA==.Shaz:BAAALgADCgQJBAAAAA==.Shivd:BAAALgAECgEJAQAAAA==.Shorpus:BAABLgAECn8bAAQeAAkJ9h4TIQCuAQAWAAYJNx8hCgAwAgAeAAcJixoTIQCuAQAVAAcJCwj6XQATAQAAAA==.',
Si='Sicckbrew:BAABLgAECn8hAAIFAAkJaiH+CQDYAgAFAAkJaiH+CQDYAgABLgAFFAMJBQAhAGkLAA==.Sickin:BAABLgAFFH8FAAIhAAMJaQskFACbAAAhAAMJaQskFACbAAAAAA==.Sinniestro:BAAALgAECgEJAgAAAA==.',
Sk='Skizzyy:BAAALgAECgMJAwABLgAECgcJEAAQAAAAAA==.',
Sl='Slayedurmrs:BAAALgAECgQJBQAAAA==.Slok:BAAALgAECgEJAQAAAA==.Slowpoke:BAABLgAFFH8iAAIJAAUJ3hrECABXAQAJAAUJ3hrECABXAQAAAA==.',
Sm='Smacedh:BAABLgAECn8WAAIcAAkJChKUYgB6AQAcAAkJChKUYgB6AQAAAA==.Smesher:BAAALgAECgYJCwAAAA==.',
Sn='Sneakyfella:BAAALgAECgkJCgAAAA==.',
So='Solidus:BAABLgAFFH8GAAIXAAQJmhQuLgAzAQAXAAQJmhQuLgAzAQAAAA==.Sorgaath:BAAALgADCgcJBwAAAA==.',
Sp='Spaklehooves:BAAALgADCgYJBgAAAA==.Spicoli:BAAALgADCgEJAQAAAA==.Spiral:BAAALgAECgQJBwAAAA==.Spoonfed:BAAALgAECgQJCwAAAA==.',
Sq='Squiish:BAACLgAFFH8YAAMJAAgJ/hjaAwAZAgAJAAcJ/RfaAwAZAgAKAAUJkAUUHwArAQAuAAQKfxoAAgkABwmoJfALANkCAAkABwmoJfALANkCAAAA.',
St='Stavrophore:BAAALgAECgEJAwAAAA==.Stickydruid:BAAALgAECgIJBgABLgAECgkJTgAbALohAA==.Stickyholes:BAAALgAECgIJAgABLgAECgkJTgAbALohAA==.Stickymonk:BAAALgAECgEJAwABLgAECgkJTgAbALohAA==.Stickypriest:BAABLgAECn9OAAMbAAkJuiEwBgDTAgAbAAkJuiEwBgDTAgACAAEJExiTeQBCAAAAAA==.Stipe:BAAALgADCgUJCAAAAA==.Stove:BAAALgADCgcJCwAAAA==.Strawhats:BAACLgAFFH83AAIPAAcJJxwgAwBMAgAPAAcJJxwgAwBMAgAuAAQKf0IAAg8ACQkyJWcCANgDAA8ACQkyJWcCANgDAAAA.Streamliner:BAABLgAECn8/AAMBAAkJJBtHCAB/AgABAAkJJBtHCAB/AgAmAAMJ1gdKCwCNAAAAAA==.Stuunks:BAAALgAECgYJCwAAAA==.',
Su='Surv:BAACLgAFFH8JAAInAAQJyBgrDABMAQAnAAQJyBgrDABMAQAuAAQKfxsAAxEABwlBICIJAL0BACcABwk6GwYWANYBABEABglfHyIJAL0BAAAA.Sustangelia:BAABLgAECn8bAAMLAAkJbxh6UAAAAgALAAkJbxh6UAAAAgAkAAEJBw9WJgBJAAAAAA==.',
Sw='Swordkiller:BAAALgAECgcJBgAAAA==.',
Sx='Sxy:BAAALgAECgYJBwABLgAECgkJPwAIAEUaAA==.',
Sy='Sy:BAAALgAECgcJEAAAAA==.Synthesis:BAABLgAECn8hAAIKAAgJoyXDBABXAwAKAAgJoyXDBABXAwAAAA==.',
Ta='Tae:BAAALgADCgUJBQAAAA==.Taichee:BAAALgADCgUJBQAAAA==.Talas:BAAALgAECgEJAgAAAA==.Talletalanot:BAACLgAFFH8HAAIgAAMJ1wgpGwCyAAAgAAMJ1wgpGwCyAAAuAAQKfy4AAiAACQkbIMwEALYCACAACQkbIMwEALYCAAAA.Tandryan:BAAALgAECgQJBwAAAA==.Tanukiji:BAABLgAECn8nAAICAAkJFhw0CwCMAgACAAkJFhw0CwCMAgAAAA==.',
Td='Tdh:BAAALgADCgMJAwAAAA==.Tdk:BAABLgAECn8WAAMLAAgJqhTongAGAQALAAcJzhXongAGAQAMAAEJ0Q2cSgA6AAAAAA==.',
Te='Tee:BAAALgADCgUJBQAAAA==.Tesarion:BAABLgAECn8WAAILAAgJHRipSgC/AQALAAgJHRipSgC/AQAAAA==.Testalatesta:BAABLgAECn9AAAMHAAkJ+ySpAAC+AwAHAAkJ+ySpAAC+AwAXAAEJmwhPaQEvAAAAAA==.',
Th='Tharien:BAAALgADCgIJAgAAAA==.Thovir:BAAALgADCgEJAQAAAA==.',
Ti='Tiberian:BAAALgADCgIJAgAAAA==.Tinyvolt:BAAALgAECggJCwAAAA==.',
Tm='Tmonk:BAAALgAECgkJDgAAAA==.',
To='Toinahun:BAAALgAECgQJBAAAAA==.Tookersoul:BAAALgAECgEJAQAAAA==.Totemea:BAAALgAECgYJBgAAAA==.Totems:BAACLgAFFH8QAAIVAAUJzBuCEQCPAQAVAAUJzBuCEQCPAQAuAAQKfxUAAhUACAkuG8kYAFcCABUACAkuG8kYAFcCAAAA.Totemîxx:BAABLgAECn8wAAMeAAkJnxkWDwBZAgAeAAkJnxkWDwBZAgAVAAQJYQ23fgCYAAAAAA==.Touchhy:BAAALgAECgEJAQAAAA==.',
Tr='Trainz:BAAALgADCgcJBwAAAA==.Trass:BAACLgAFFH8MAAMTAAMJkhFiXwDZAAATAAMJLQ9iXwDZAAASAAEJERCQHABMAAAuAAQKfz4AAxMACQndIBQSAKUCABMACQndIBQSAKUCABIAAwkqERxEAKUAAAAA.Trays:BAAALgADCgEJAQAAAA==.Trisse:BAABLgAECn8bAAIcAAgJhw5VVABmAQAcAAgJhw5VVABmAQAAAA==.',
Tu='Tuzz:BAACLgAFFH8FAAIkAAIJjBa4EACiAAAkAAIJjBa4EACiAAAuAAQKfykAAiQACQnrIGIBAO4CACQACQnrIGIBAO4CAAAA.',
Tw='Twongle:BAAALgADCgIJAgABLgAECgcJGQAPAB8XAA==.',
Ty='Tyden:BAAALgAECgYJEAAAAA==.Tyrmac:BAAALgAECgMJBAAAAA==.',
Va='Vael:BAAALgAECgYJCgAAAA==.Valerie:BAAALgAECgUJBwAAAA==.Valkyrra:BAAALgAECgQJBAAAAA==.Varaestia:BAAALgAECgQJBAAAAA==.Varg:BAAALgADCgEJAQABLgADCgEJAQAQAAAAAA==.Vargmk:BAAALgADCgEJAQAAAA==.Vargps:BAAALgADCgEJAQAAAA==.',
Ve='Velithara:BAAALgAECgcJBwAAAA==.Venestra:BAAALgAECgcJCwABLgAECgkJAQAQAAAAAA==.Verdict:BAACLgAFFH8JAAIXAAQJzBsVHwBYAQAXAAQJzBsVHwBYAQAuAAQKfxgAAhcACAloHlsgAKoCABcACAloHlsgAKoCAAAA.Vermeil:BAAALgAECgMJAwAAAA==.Vermillion:BAACLgAFFH8VAAIXAAUJJR34GABvAQAXAAUJJR34GABvAQAuAAQKfyIAAhcACQnuIIQLAO8CABcACQnuIIQLAO8CAAAA.',
Vi='Vib:BAAALgAECgEJAQAAAA==.Viegas:BAACLgAFFH8FAAIUAAIJnRJxYgCOAAAUAAIJnRJxYgCOAAAuAAQKfxsAAhQABwkjHK4gAEECABQABwkjHK4gAEECAAAA.Vincent:BAABLgAECn8hAAIPAAYJsB6ZfgDUAQAPAAYJsB6ZfgDUAQAAAA==.Vinijr:BAAALgAECgEJAgAAAA==.Vivamax:BAAALgAECgEJAQAAAA==.',
Vo='Voidthotnimz:BAAALgADCgcJBgABLgAFFAQJEwAfAEILAA==.Volthic:BAAALgAECgQJBAAAAA==.Voltormu:BAAALgAECgMJBgAAAA==.Vore:BAABLgAECn8fAAIcAAkJeBVvLgDuAQAcAAkJeBVvLgDuAQAAAA==.',
Vr='Vrag:BAACLgAFFH8FAAILAAEJ3QG93AA5AAALAAEJ3QG93AA5AAAuAAQKfyYAAgsABwlRDMeBADoBAAsABwlRDMeBADoBAAAA.',
['Vè']='Vè:BAABLgAECn8XAAMMAAkJ4g80FgCIAQAMAAkJBQ80FgCIAQALAAcJKg98dABVAQAAAA==.',
['Vê']='Vêê:BAAALgAECgQJBAABLgAECgkJFwAMAOIPAA==.',
Wa='Warslaw:BAACLgAFFH8SAAIMAAUJeR9YCwBrAQAMAAUJeR9YCwBrAQAuAAQKfyAAAgwACQlVI18FAOsCAAwACQlVI18FAOsCAAAA.Warth:BAAALgADCgEJAQAAAA==.Waterwater:BAAALgAECgYJCgAAAA==.Waterwaterz:BAACLgAFFH8PAAIPAAMJ0xyyKgAKAQAPAAMJ0xyyKgAKAQAuAAQKfzkAAg8ACAnVHOQ0AJ8CAA8ACAnVHOQ0AJ8CAAAA.',
Wc='Wchin:BAABLgAECn8YAAIoAAgJcyARAQCXAgAoAAgJcyARAQCXAgAAAA==.Wchinz:BAABLgAECn8WAAIbAAkJbiCPDgCaAgAbAAkJbiCPDgCaAgAAAA==.',
We='Wedlock:BAAALgADCgIJAgAAAA==.Welcumshot:BAABLgAFFH8KAAInAAMJZRAFGADoAAAnAAMJZRAFGADoAAAAAA==.Wenkar:BAAALgAECgUJDAABLgAECgkJUQASAOEdAA==.',
Wi='Windsabre:BAAALgADCgIJAgAAAA==.Wingz:BAAALgAFFAEJAgAAAA==.',
Wo='Woregeonnick:BAABLgAECn8fAAITAAcJVxEhZwCWAQATAAcJVxEhZwCWAQAAAA==.Woshiren:BAAALgAECgYJBgAAAA==.',
Wy='Wyvern:BAAALgAECgcJEAAAAA==.',
['Wä']='Wärrior:BAAALgADCgMJAwAAAA==.',
Xa='Xanadu:BAAALgADCgIJAgAAAA==.',
Xd='Xd:BAAALgAFFAEJAQAAAA==.',
Xe='Xerxexy:BAAALgAECgQJCwAAAA==.',
Xi='Xiaodingdang:BAAALgAECgQJBAAAAA==.Xiera:BAABLgAECn8XAAIPAAcJWwnXmAAsAQAPAAcJWwnXmAAsAQAAAA==.',
Ya='Yaminosaishi:BAAALgAECgYJBwAAAA==.Yaoyôrozu:BAAALgADCgkJFAAAAA==.Yasuô:BAAALgADCgMJAwAAAA==.Yatelega:BAAALgADCgIJAgABLgAECgcJHwATAFcRAA==.Yazdorzarn:BAAALgAECgcJDAAAAA==.',
Yo='Yozzao:BAAALgAECgQJCAAAAA==.',
Yu='Yueli:BAAALgAFFAEJAQABLgAFFAgJGAAJAP4YAA==.',
Za='Zaaniz:BAABLgAECn8lAAQXAAkJ8BtvHwCvAgAXAAkJ8BtvHwCvAgAHAAQJgwmIUgDBAAAdAAIJ+Q29NABhAAAAAA==.',
Ze='Zenestra:BAAALgAECgkJAQAAAA==.Zenshui:BAAALgAECgYJCQAAAA==.Zephyruss:BAAALgADCgEJAQAAAA==.Zervis:BAAALgAECgIJAgAAAA==.Zeyra:BAAALgAECgYJDAAAAA==.',
Zi='Zinako:BAAALgAECgEJAQAAAA==.',
Zo='Zocalo:BAAALgAECgUJBQAAAA==.',
['Èa']='Èasymode:BAAALgADCgEJAQAAAA==.',
['Ód']='Ódyssey:BAABLgAECn8ZAAIWAAgJCRL8DACrAQAWAAgJCRL8DACrAQAAAA==.',
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
