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

local lookup = {'Priest-Holy','Priest-Discipline','Monk-Brewmaster','Monk-Windwalker','Druid-Restoration','DeathKnight-Unholy','DeathKnight-Blood','DemonHunter-Havoc','DemonHunter-Vengeance','Mage-Frost','Unknown-Unknown','Hunter-Marksmanship','Warlock-Destruction','Warlock-Demonology','Druid-Balance','Monk-Mistweaver','Shaman-Restoration','Shaman-Enhancement','Paladin-Retribution','Rogue-Subtlety','Rogue-Assassination','Warrior-Protection','Evoker-Devastation','Hunter-BeastMastery','Priest-Shadow','DemonHunter-Devourer','Paladin-Protection','Shaman-Elemental','Evoker-Augmentation','Evoker-Preservation','Paladin-Holy','Warlock-Affliction','Druid-Guardian','Mage-Fire','Warrior-Fury','Druid-Feral','Rogue-Outlaw','Hunter-Survival','DeathKnight-Frost','Mage-Arcane',}
local provider = {region='US',realm='Dreadmaul',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abbathdoom:BAAALgAECggJDQAAAA==.',
Ae='Aedaris:BAABLgAECn9XAAMBAAkJPCAzCgB5AgABAAcJDyEzCgB5AgACAAYJHhneHACLAQAAAA==.Ael:BAAALgAECgEJAQAAAA==.Aethalides:BAAALgAECgYJDwAAAA==.',
Al='Alandrias:BAAALgAECgkJAQAAAA==.Aloremirin:BAAALgADCgUJBQAAAA==.Altaria:BAABLgAFFH8QAAMDAAUJGhsHEABNAQADAAUJGhsHEABNAQAEAAQJ7xVVCwAqAQAAAA==.Alvv:BAAALgADCgMJBQAAAA==.Alvz:BAAALgADCgMJAwAAAA==.',
Am='Ametrigos:BAAALgAECgEJAQAAAA==.',
An='Anouke:BAAALgADCgIJAgAAAA==.Anserion:BAAALgADCgMJAwAAAA==.Anvious:BAAALgAECgcJDAAAAA==.',
Aq='Aquilea:BAAALgAECggJEwAAAA==.',
Ar='Arcfuldodger:BAAALgAECgEJAQAAAA==.Artais:BAABLgAECn8gAAIFAAgJ1Rx8FgCCAgAFAAgJ1Rx8FgCCAgAAAA==.Artzlayer:BAACLgAFFH8GAAIGAAMJrxvRVAAGAQAGAAMJrxvRVAAGAQAuAAQKfy0AAwYACQmZIlkLANsCAAYACQmZIlkLANsCAAcAAQkAALVQAAAAAAAA.Aríes:BAABLgAECn9MAAMIAAgJoRwWCgApAgAIAAgJoRwWCgApAgAJAAEJGAnbJgAsAAAAAA==.',
As='Ashbourne:BAAALgADCgcJCwAAAA==.',
Aw='Aw:BAAALgAECgYJEQABLgAFFAYJFQAKAFwVAA==.Awry:BAEBLgAECn8qAAIGAAgJYx9rHgBNAgAGAAgJYx9rHgBNAgAAAA==.Awuuga:BAAALgAECgEJAQABLgAECgYJEgALAAAAAA==.Aww:BAACLgAFFH8VAAIKAAYJXBXXFgCrAQAKAAYJXBXXFgCrAQAuAAQKfxwAAgoACAkmFwV/ANMBAAoACAkmFwV/ANMBAAAA.',
Az='Azamalaza:BAABLgAECn8nAAIMAAgJbyJyAwBYAgAMAAgJbyJyAwBYAgAAAA==.Azmo:BAACLgAFFH8GAAMNAAMJkxLOEQBcAAAOAAMJBgwNOQCiAAANAAEJaxzOEQBcAAAuAAQKfyUAAw0ACAkvIcECANYCAA0ACAmJHcECANYCAA4ABQk9HL1gAKcBAAAA.Azulon:BAAALgADCgUJBQABLgAECgcJGQACAAAcAA==.Azyrt:BAAALgAECgQJBAABLgAECggJIAAFANUcAA==.',
Ba='Badds:BAAALgAECgcJBwAAAA==.Ballona:BAAALgADCgUJBQAAAA==.Barad:BAAALgAECgEJAgAAAA==.Batrick:BAAALgADCgcJBwAAAA==.Baulric:BAAALgAECgEJAQAAAA==.Bawls:BAAALgAECgYJBgAAAA==.',
Be='Beastroll:BAAALgAECgYJBwAAAA==.Beefrod:BAAALgADCgEJAQAAAA==.Beenis:BAAALgADCgUJBQAAAA==.Belerick:BAABLgAFFH8JAAIPAAMJnQqfDwDoAAAPAAMJnQqfDwDoAAAAAA==.Belphine:BAAALgAECgYJCAAAAA==.',
Bi='Bicksmage:BAABLgAFFH8KAAIKAAMJMBQgVQD6AAAKAAMJMBQgVQD6AAAAAA==.Bigdaddylock:BAACLgAFFH8QAAIOAAYJ8RcVEgCYAQAOAAYJ8RcVEgCYAQAuAAQKfyUAAw0ACQnoJE4IAD4CAA0ABgm1Ik4IAD4CAA4ACAkzI5EnAAECAAAA.Biluman:BAAALgAECgQJBAAAAA==.Biodeath:BAAALgADCgUJBQAAAA==.Biopally:BAAALgADCgYJDQAAAA==.Biorogue:BAAALgADCgYJDAAAAA==.Bishope:BAABLgAECn8ZAAICAAcJABw9DQBDAgACAAcJABw9DQBDAgAAAA==.',
Bl='Bllizard:BAAALgAECgEJAQAAAA==.Bloodache:BAAALgADCgcJCAABLgAECgUJFAAGAA4SAA==.Bluecar:BAAALgAECgYJCAAAAA==.',
Bo='Bohica:BAAALgAECgIJBQAAAA==.Bombdiggity:BAABLgAECn8oAAICAAYJjh/hEAAMAgACAAYJjh/hEAAMAgAAAA==.Bonnierot:BAAALgAECgUJCgAAAA==.Boypally:BAAALgAECggJCQAAAA==.',
Br='Brecciana:BAAALgADCgUJBQAAAA==.Brewjitsu:BAABLgAECn9CAAIDAAgJiRrqDwACAgADAAgJiRrqDwACAgAAAA==.Brick:BAACLgAFFH8GAAMDAAMJzR05HgAEAQADAAMJzR05HgAEAQAQAAEJ9BVsLwBJAAAuAAQKfx8AAgMABwl3HuQaAC0CAAMABwl3HuQaAC0CAAEuAAUUBgkZAA4A/R0A.Brongakill:BAAALgADCgYJBgAAAA==.',
Bu='Buffy:BAAALgAECgEJAQAAAA==.Bumble:BAAALgADCgYJBgABLgAFFAcJGwABAJcbAA==.Bundalock:BAAALgADCgYJEQAAAA==.',
Ca='Cakebringer:BAAALgAECgcJEgAAAA==.Carbos:BAAALgAECgkJBQAAAA==.Caroshi:BAABLgAECn8jAAIKAAgJvw1lXgCDAQAKAAgJvw1lXgCDAQAAAA==.',
Ce='Cell:BAAALgAECgUJCAABLgAECggJDQALAAAAAA==.Ceridwen:BAAALgADCgEJAQAAAA==.',
Ch='Charlotte:BAAALgAECgMJBwAAAA==.Cheto:BAAALgAFFAIJAgABLgAFFAUJEAARAMwbAA==.Chud:BAAALgAECgUJBQABLgAFFAUJEwASANYjAA==.',
Ci='Cig:BAABLgAECn8YAAITAAgJ/hCPWAB4AQATAAgJ/hCPWAB4AQAAAA==.',
Cl='Clankychan:BAACLgAFFH8JAAIDAAMJTA3aKQDLAAADAAMJTA3aKQDLAAAuAAQKfxcAAgMABwnZEg4yAP0AAAMABwnZEg4yAP0AAAAA.Cloneofmagic:BAAALgADCgcJBwAAAA==.',
Co='Combustanut:BAAALgAECgUJDQAAAA==.Comillmouth:BAABLgAECn8ZAAICAAgJbxFlGgCjAQACAAgJbxFlGgCjAQAAAA==.Comillthroat:BAAALgAECgkJEQAAAA==.Cos:BAABLgAECn82AAMUAAkJbxG2DgDvAQAUAAkJbxG2DgDvAQAVAAMJOAXFFgCKAAAAAA==.',
Cr='Crozier:BAAALgAECgEJAgAAAA==.Cryptum:BAAALgAECgkJBAAAAA==.Cryten:BAAALgAECgIJAgAAAA==.',
Cu='Curby:BAAALgAECgIJAgABLgAECgkJTgAWAJMeAA==.',
['Cä']='Cäin:BAAALgAECgQJCAAAAA==.',
Da='Dabufart:BAAALgADCgEJAQAAAA==.Daerus:BAAALgAECgYJBQAAAA==.Damge:BAAALgAECgUJCgAAAA==.Damnnyou:BAAALgAECgcJBwABLgAECgkJIwAXAK0ZAA==.Danky:BAAALgAECgMJAwAAAA==.Danteh:BAAALgAFFAEJAgAAAA==.Darahug:BAAALgAECgYJBgAAAA==.Daraina:BAAALgADCgEJAQABLgADCgEJAQALAAAAAA==.Darktalanus:BAAALgADCgQJBAAAAA==.Darrkton:BAAALgADCgEJAQAAAA==.Dathil:BAAALgAECgYJCQAAAA==.Davmonhunter:BAAALgADCgQJBAAAAA==.',
De='Deadiemurphy:BAAALgADCgYJCQAAAA==.Deathshunter:BAABLgAECn8hAAMYAAkJwCPVBwDhAgAYAAgJWSXVBwDhAgAMAAYJ+hkjOgB5AQABLgAFFAYJEAAGACUfAA==.Deaththorn:BAAALgADCgEJAQAAAA==.Debsi:BAABLgAECn8ZAAIWAAgJSg6oFABYAQAWAAgJSg6oFABYAQAAAA==.Deeper:BAAALgAFFAIJAgAAAA==.Deepest:BAAALgAFFAIJAgAAAA==.Deloraine:BAACLgAFFH8gAAIZAAYJ7iHYAgD2AQAZAAYJ7iHYAgD2AQAuAAQKfyAAAhkACQmhH+EKAFcCABkACQmhH+EKAFcCAAAA.Demonicfaith:BAABLgAECn82AAMIAAcJbxqFFwAMAgAIAAYJTx6FFwAMAgAaAAcJlQzbgAAoAQAAAA==.Denman:BAABLgAECn8YAAMTAAcJjBm5bABJAQATAAcJjBm5bABJAQAbAAEJmAAmUAAKAAAAAA==.Dezarian:BAAALgAECggJCAAAAA==.',
Di='Dirtyfux:BAACLgAFFH8HAAICAAMJ5RJ1HQDjAAACAAMJ5RJ1HQDjAAAuAAQKfxUAAwIABglsHHodAIUBAAIABglsHHodAIUBAAEAAQkZDweDAC4AAAAA.Dirtysham:BAACLgAFFH8IAAIRAAMJjh1DIwD/AAARAAMJjh1DIwD/AAAuAAQKfy8AAxEACQm3H/0MALUCABEACAl1If0MALUCABwABAmHCsZJALUAAAAA.Discipline:BAAALgADCgcJBwAAAA==.Disckin:BAAALgADCgUJBgAAAA==.Divinechill:BAAALgADCgQJBAAAAA==.',
Dn='Dnb:BAAALgADCgEJAQABLgAFFAYJFQAKAFwVAA==.Dnk:BAAALgADCgMJAwAAAA==.',
Do='Dom:BAAALgADCgcJCQAAAA==.Donki:BAAALgAECgkJDAAAAA==.Doomvedas:BAAALgAECgYJCgAAAA==.',
Dr='Dracaena:BAABLgAECn8jAAQXAAkJrRk/BAD4AQAXAAgJtBc/BAD4AQAdAAgJkBT/GwDoAQAeAAUJQwizMQDiAAAAAA==.Draco:BAAALgAECgMJAwAAAA==.Dreadknìght:BAAALgAFFAMJAgAAAA==.Drekavach:BAAALgADCgcJEwAAAA==.Droidbick:BAAALgAECgYJBwAAAA==.',
['Dâ']='Dâftmonk:BAAALgAECgEJAwABLgAECggJCgALAAAAAA==.',
Ee='Eevo:BAAALgAECgMJAwABLgAECggJFAAQAJEIAA==.',
El='Elaha:BAAALgAECgcJCQAAAA==.Elexann:BAAALgAECgkJAQAAAA==.Elibaba:BAAALgAECgkJDQAAAA==.Elideady:BAAALgAECggJBQABLgAECgkJDQALAAAAAA==.Elindyl:BAAALgADCgEJAQAAAA==.Elleth:BAAALgADCgIJAgAAAA==.Elvishcheese:BAAALgAECgMJBgAAAA==.',
Em='Emojis:BAAALgAECgUJCQAAAA==.',
En='Endlessdh:BAACLgAFFH8IAAIIAAMJCiIKBwDIAAAIAAMJCiIKBwDIAAAuAAQKfxwAAggABwkyJJUJAMgCAAgABwkyJJUJAMgCAAAA.',
Er='Eraserhead:BAAALgAECgYJEwABLgAFFAUJEwASANYjAA==.Erissaria:BAAALgADCgEJAQAAAA==.',
Ev='Evening:BAAALgAECgMJBAAAAA==.Everbuddha:BAAALgAECgQJBgAAAA==.',
Ew='Ewa:BAAALgAECgMJBAAAAA==.Eww:BAABLgAECn8WAAIaAAcJyQ8vVQA1AQAaAAcJyQ8vVQA1AQAAAA==.',
Ez='Ezelia:BAABLgAECn8aAAMTAAkJfhYbKQAUAgATAAkJfhYbKQAUAgAfAAEJRglXlQA1AAABLgAFFAcJLwABAG8ZAA==.',
Fa='Faelune:BAAALgAECggJEwAAAA==.Faldir:BAAALgADCgYJBAABLgAFFAMJBgAaACwVAA==.',
Fe='Ferndru:BAAALgAECgYJDwAAAA==.',
Fi='Fish:BAAALgAECgEJAgABLgAECggJHgAdADQhAA==.Fisticuffs:BAACLgAFFH8OAAIQAAUJPQ5oEgBCAQAQAAUJPQ5oEgBCAQAuAAQKfyIAAhAACAl3GM8SABsCABAACAl3GM8SABsCAAAA.',
Fl='Flameshock:BAAALgAFFAEJAQAAAA==.Flowki:BAAALgADCgYJBQAAAA==.',
Fo='Forcespark:BAAALgAECgEJAQAAAA==.',
Fr='Frostradamus:BAAALgADCgkJCgAAAA==.',
Fu='Fullmoonride:BAAALgAECgQJBQAAAA==.Fumbll:BAAALgAECgkJCQAAAA==.Funkymajik:BAAALgAECggJEwAAAA==.Furiosa:BAAALgADCgkJDgAAAA==.',
Ga='Gallywox:BAAALgADCgMJAwAAAA==.Ganin:BAABLgAECn8bAAIfAAYJUBXSMQA+AQAfAAYJUBXSMQA+AQAAAA==.Gankinyou:BAAALgADCgEJAQAAAA==.Garielyn:BAAALgADCgEJAQAAAA==.Garugala:BAACLgAFFH8FAAITAAMJWgopRADgAAATAAMJWgopRADgAAAuAAQKfysAAhMACQklGAcdAFUCABMACQklGAcdAFUCAAAA.',
Gd='Gdaycøb:BAAALgADCgYJBwAAAA==.',
Ge='Gengár:BAAALgAECgMJBgABLgAECggJDAALAAAAAA==.',
Gh='Ghalorin:BAAALgAECgMJCgAAAA==.Ghiroza:BAABLgAECn9RAAQNAAkJ2h3fCAAzAgAOAAkJ1R2yFQBqAgANAAgJihbfCAAzAgAgAAMJkhZpHQCGAAAAAA==.',
Gi='Gigaevoker:BAABLgAECn8kAAIeAAgJcRYECQARAgAeAAgJcRYECQARAgAAAA==.Gigapaladin:BAAALgADCgQJBAAAAA==.Gingarthas:BAABLgAECn8iAAIGAAkJPh0aJQApAgAGAAkJPh0aJQApAgAAAA==.',
Gl='Glowingtoe:BAAALgAECgMJBQAAAA==.',
Go='Gogmazios:BAAALgADCgcJBwAAAA==.',
Gr='Gravytate:BAABLgAECn9WAAIcAAkJfA8JHwCVAQAcAAkJfA8JHwCVAQAAAA==.Griinn:BAABLgAECn8VAAIhAAgJkw0jFwADAQAhAAgJkw0jFwADAQAAAA==.Grimescene:BAAALgAECgIJAgAAAA==.Grimreapêr:BAAALgADCgEJAQAAAA==.',
Gu='Guldannyboy:BAABLgAECn8rAAMNAAkJhglJHgBeAQAOAAkJFwf4UwBhAQANAAgJkwlJHgBeAQAAAA==.Gumbö:BAAALgAECgYJCAABLgAECggJIAAFANUcAA==.',
Ha='Haides:BAAALgAECgEJAQAAAA==.Hammer:BAAALgAECgIJAgABLgAECggJCgALAAAAAA==.Hantore:BAAALgADCgMJAwAAAA==.Harry:BAABLgAECn8nAAMSAAkJYyTlAQA/AwASAAkJYyTlAQA/AwARAAcJxBrjIAAaAgAAAA==.',
He='Heartdh:BAABLgAECn8VAAMaAAgJkRKlPACIAQAaAAgJkRKlPACIAQAIAAIJrxOGWwByAAAAAA==.Heisenbergg:BAAALgADCgIJAgAAAA==.Hellza:BAAALgAECgMJAwAAAA==.Hen:BAAALgAECgUJBQABLgAECgYJFQAHABAVAA==.Herpyprotect:BAAALgAFFAIJAgAAAA==.Herrion:BAACLgAFFH8ZAAIOAAYJ/R0mCQDVAQAOAAYJ/R0mCQDVAQAuAAQKfy4AAw4ACQn9IvkcAKgCAA4ACAn9IvkcAKgCAA0ABAmcJNMUAKQBAAAA.',
Hh='Hh:BAAALgAECgEJAQAAAA==.',
Ho='Hotspur:BAABLgAECn84AAIFAAgJaxDUOADDAQAFAAgJaxDUOADDAQAAAA==.',
Hu='Hukani:BAAALgAECgEJAgABLgAECggJFgABALEIAA==.Hunner:BAAALgAECgIJAgABLgAECggJFAAQAJEIAA==.Huskar:BAAALgAECggJDQAAAA==.',
Hy='Hypoxi:BAAALgADCgYJCQAAAA==.',
Ig='Ignis:BAABLgAECn8cAAIiAAkJmh3HAACXAgAiAAkJmh3HAACXAgAAAA==.Ignitor:BAAALgADCgEJAQAAAA==.',
Ik='Ikari:BAABLgAECn9OAAINAAkJxBpCAgBWAgANAAkJxBpCAgBWAgAAAA==.',
Il='Illadoss:BAAALgADCgIJAgAAAA==.',
Im='Imntprepared:BAAALgAECgkJCQAAAA==.',
In='Incarnate:BAAALgAECgEJAgAAAA==.Incubis:BAAALgADCgIJAgAAAA==.Infectîon:BAAALgADCgYJBgAAAA==.Inferlock:BAAALgADCgUJBAAAAA==.Infernyoz:BAAALgADCggJCQAAAA==.',
Ir='Irithel:BAAALgAECgcJBQAAAA==.',
It='Itchygrowth:BAAALgAFFAEJAQAAAA==.',
Iv='Ivygambina:BAAALgADCgYJBgAAAA==.Ivysore:BAAALgAECgUJBwAAAA==.',
Ja='Jasha:BAAALgADCgcJCwAAAA==.Jayy:BAABLgAECn8bAAIGAAkJBRCKTAANAgAGAAkJBRCKTAANAgAAAA==.',
Je='Jennatalia:BAAALgAECggJDAAAAA==.',
Ji='Jinkazamaz:BAAALgAFFAIJAgAAAA==.',
Jo='Joelsdruid:BAABLgAFFH8LAAIhAAQJURojBABJAQAhAAQJURojBABJAQAAAA==.Joelvoker:BAAALgAFFAIJAgABLgAFFAQJCwAhAFEaAA==.Joexotic:BAAALgAECgIJBgAAAA==.Jongwang:BAAALgAECgQJBwAAAA==.',
Ju='Jubjub:BAAALgAECgEJAgAAAA==.',
Ka='Kaaru:BAABLgAECn8jAAMCAAkJjBPDDgAqAgACAAkJehLDDgAqAgABAAUJExKGSAAXAQAAAA==.Kaiforst:BAAALgAECgQJBAABLgAECgkJNAATAJEXAA==.Kaihavocz:BAAALgAECgEJAQAAAA==.Kairon:BAABLgAECn80AAITAAkJkRcmJgAiAgATAAkJkRcmJgAiAgAAAA==.Kalysae:BAAALgADCgEJAQAAAA==.Katarinabluu:BAAALgAECgYJBgAAAA==.Kazakhthundr:BAAALgADCgYJBgAAAA==.',
Ke='Keeanuleaves:BAAALgADCgYJBwAAAA==.Keeanuweaves:BAAALgADCgEJAQAAAA==.Keeze:BAACLgAFFH8KAAIKAAQJTgQnTAAUAQAKAAQJTgQnTAAUAQAuAAQKfxYAAgoACAlEE35TAKABAAoACAlEE35TAKABAAAA.',
Ki='Kickstarter:BAAALgAECgYJEgAAAA==.Kiel:BAAALgAECgEJAQAAAA==.Killania:BAAALgADCgMJAwAAAA==.Kiwichaos:BAACLgAFFH8KAAIIAAQJnQmhDwDGAAAIAAQJnQmhDwDGAAAuAAQKfygAAggACQlcG6EHAGQCAAgACQlcG6EHAGQCAAAA.',
Kl='Klckyourass:BAAALgADCgYJCwAAAA==.',
Kn='Knox:BAAALgAECgIJAgAAAA==.',
Ko='Korner:BAAALgAECgIJAgAAAA==.',
Kr='Krazzul:BAAALgADCgYJBgAAAA==.Krellis:BAABLgAECn8WAAMEAAgJBxDTHQBtAQAEAAgJBxDTHQBtAQAQAAYJtRA8MQAzAQAAAA==.Kritikall:BAAALgADCgUJBQAAAA==.',
Ku='Kurö:BAAALgAECgEJAQAAAA==.',
Kv='Kvôthe:BAAALgAECggJEQAAAA==.',
Ky='Kynnareth:BAAALgAFFAIJBAABLgAFFAYJDgACAHMLAA==.Kynralol:BAABLgAECn8pAAIKAAgJ5x7pIQBYAgAKAAgJ5x7pIQBYAgAAAA==.',
['Ká']='Káiser:BAAALgAECggJEQAAAA==.',
La='Laenosh:BAABLgAECn8UAAIGAAUJDhLolgDvAAAGAAUJDhLolgDvAAAAAA==.Laomoo:BAAALgAECgcJDgAAAA==.',
Le='Learning:BAABLgAECn8XAAIcAAcJER9LGwA4AgAcAAcJER9LGwA4AgAAAA==.Legham:BAAALgADCgkJDgAAAA==.Legolazz:BAABLgAECn8yAAMYAAkJ4B5zCwC2AgAYAAkJ4B5zCwC2AgAMAAMJCBRxHwByAAAAAA==.Lemins:BAAALgAECgMJAwAAAA==.Lemondruid:BAAALgAECgIJAgAAAA==.Lemonmelon:BAAALgAECgYJEwAAAA==.Lenatheplug:BAACLgAFFH8WAAMUAAUJFSAMAwDMAQAUAAUJFSAMAwDMAQAVAAEJQRHKBQBgAAAuAAQKfyIAAxQACAmUJEQKAO0CABQACAnbI0QKAO0CABUABwlAIt4DAIACAAAA.Lerust:BAAALgADCgcJBwAAAA==.',
Li='Liadrine:BAABLgAECn8uAAITAAgJDhkDPgDEAQATAAgJDhkDPgDEAQAAAA==.Linus:BAAALgAECgYJBgABLgAFFAYJGQAOAP0dAA==.Littleriver:BAAALgAECgcJEQAAAA==.',
Ll='Llewser:BAAALgAECgUJEAAAAA==.',
Lo='Loathe:BAAALgAECgEJAgAAAA==.Loistiah:BAAALgAFFAMJBAAAAA==.Lothaof:BAABLgAECn8sAAITAAkJ6hJcOgDRAQATAAkJ6hJcOgDRAQAAAA==.Louisvuitton:BAAALgAECgUJDwAAAA==.',
Lp='Lpayn:BAAALgADCgEJAQAAAA==.',
Lu='Lugroth:BAAALgAECgEJAgABLgAFFAYJGQAOAP0dAA==.Lunana:BAAALgAECgcJEgAAAA==.',
Ly='Lychiee:BAAALgAECgcJEQAAAA==.',
['Lì']='Lìnkinbark:BAAALgAECgMJAwAAAA==.',
Ma='Madara:BAAALgAECgEJAQAAAA==.Magesorry:BAAALgADCgUJBQAAAA==.Magicmon:BAAALgADCgUJBQAAAA==.Maize:BAABLgAECn8iAAMCAAgJLxvjCwBaAgACAAgJLxvjCwBaAgABAAMJhgvTZwCOAAAAAA==.Makima:BAABLgAFFH8FAAIPAAUJmQ77GgD3AAAPAAUJmQ77GgD3AAABLgAFFAUJEwAPALwYAA==.Malikai:BAAALgADCgcJDAAAAA==.Marcyon:BAABLgAECn8TAAIaAAYJfAmdiwAMAQAaAAYJfAmdiwAMAQAAAA==.',
Mc='Mchèalz:BAABLgAECn8VAAQCAAgJRAiFJwA1AQACAAgJRAiFJwA1AQABAAQJxAFFaQCIAAAZAAIJOwF0ZgAsAAAAAA==.',
Me='Melonlemonza:BAAALgADCgQJBAAAAA==.Mentok:BAAALgAECgYJCwAAAA==.Merchei:BAAALgAECgUJBgAAAA==.Meruen:BAABLgAECn8fAAIaAAgJphniIQAEAgAaAAgJphniIQAEAgAAAA==.',
Mi='Mistie:BAAALgAECgEJAQAAAA==.Mitymorphin:BAAALgADCgEJAQAAAA==.',
Mo='Mobility:BAAALgADCgYJBgAAAA==.Moistpole:BAAALgADCgQJBAAAAA==.Momock:BAAALgAECgQJBAAAAA==.Mongk:BAABLgAECn8UAAIQAAgJkQibNQAZAQAQAAgJkQibNQAZAQAAAA==.Monscustodes:BAABLgAECn8eAAIKAAgJog2rZwBtAQAKAAgJog2rZwBtAQAAAA==.Mookin:BAAALgAECgcJCAAAAA==.Moospoon:BAABLgAECn8ZAAITAAgJmA1xYQBjAQATAAgJmA1xYQBjAQAAAA==.Moounka:BAABLgAECn8yAAIDAAgJ5g8dIABoAQADAAgJ5g8dIABoAQAAAA==.Morphio:BAABLgAECn84AAMYAAkJFSL5BgDtAgAYAAkJFSL5BgDtAgAMAAUJCxOaTAAfAQAAAA==.Mostakrakish:BAAALgADCgEJAQAAAA==.',
Mu='Muddles:BAABLgAECn8+AAIDAAgJRRdFFgC6AQADAAgJRRdFFgC6AQAAAA==.Murius:BAABLgAECn8yAAIGAAkJRBeLIgA2AgAGAAkJRBeLIgA2AgAAAA==.',
My='Mysterio:BAAALgAECgYJDgAAAA==.',
Na='Naendria:BAAALgAECgMJBAAAAA==.Naga:BAAALgAECgIJAgAAAA==.Nahaza:BAAALgAECgEJAgAAAA==.',
Ne='Nelena:BAAALgADCgEJAQAAAA==.',
Ni='Nickdoom:BAAALgAECgUJDwAAAA==.Nigella:BAABLgAECn8WAAMBAAgJsQhzKwAlAQABAAgJsQhzKwAlAQACAAEJ6wH3XwAhAAAAAA==.Nikola:BAABLgAECn8nAAQFAAgJAxdnNwDKAQAFAAgJAxdnNwDKAQAhAAUJOBbfFQAUAQAPAAQJfQ9/VADUAAAAAA==.Nimro:BAACLgAFFH8VAAIWAAUJZhbnBgBkAQAWAAUJZhbnBgBkAQAuAAQKfygAAhYACQmPH6ADABsDABYACQmPH6ADABsDAAAA.Niub:BAABLgAECn8iAAIjAAcJMRE3LgBIAQAjAAcJMRE3LgBIAQAAAA==.',
No='Nofate:BAAALgADCgEJAQAAAA==.Noirebringer:BAAALgAFFAEJAQAAAA==.',
Nt='Ntrldrake:BAAALgADCgEJAgABLgAECggJHgAKAKINAA==.',
Nu='Nuferax:BAAALgAECggJEwAAAA==.Nulledhacz:BAAALgADCgEJAQAAAA==.Numbrethree:BAACLgAFFH8TAAIQAAQJ/hESFwANAQAQAAQJ/hESFwANAQAuAAQKf0MAAhAACAmcGLEUAAUCABAACAmcGLEUAAUCAAAA.',
Ob='Obbi:BAACLgAFFH8LAAIVAAMJNCLjAwAiAQAVAAMJNCLjAwAiAQAuAAQKfxYAAhUACAk3IkQBAM0CABUACAk3IkQBAM0CAAAA.',
Oh='Ohaither:BAAALgAECgQJBAAAAA==.',
Oi='Oirth:BAAALgADCgIJAgAAAA==.',
Ok='Okiji:BAAALgAECgkJEwAAAA==.',
Or='Orinocco:BAAALgAECgEJAwAAAA==.Orobas:BAAALgAECgEJAgAAAA==.',
Pa='Pakaww:BAAALgAECgIJAwAAAA==.Palimathrus:BAAALgAECgUJCAAAAA==.Palliative:BAABLgAECn8yAAMfAAgJDSFECQCxAgAfAAgJDSFECQCxAgATAAQJlQQD1gCWAAAAAA==.Pallidnim:BAAALgAFFAEJAwAAAA==.',
Pe='Pea:BAAALgAECgcJEAAAAA==.Perish:BAAALgAECgIJAwABLgAECggJPgADAEUXAA==.',
Ph='Phatmonk:BAACLgAFFH8OAAIEAAQJpiUwAgC7AQAEAAQJpiUwAgC7AQAuAAQKfyIAAgQACQn4JF0BAEkDAAQACQn4JF0BAEkDAAAA.Phatrogue:BAAALgAECgYJCgABLgAFFAQJDgAEAKYlAA==.',
Pi='Piewpiew:BAAALgADCgcJCgAAAA==.Pix:BAACLgAFFH8UAAMZAAYJKR3XAgDHAQAZAAYJKR3XAgDHAQACAAUJvQw6EQBwAQAuAAQKfzYAAhkACQk5JQwBAF8DABkACQk5JQwBAF8DAAAA.',
Pl='Pleasuremax:BAAALgAECgcJEgAAAA==.Plex:BAABLgAECn8+AAIkAAkJRRoBBAB4AgAkAAkJRRoBBAB4AgAAAA==.',
Po='Poogie:BAAALgADCgYJBgABLgAECgMJBQALAAAAAA==.Popshot:BAABLgAECn8eAAIMAAYJ5xIiRQBBAQAMAAYJ5xIiRQBBAQAAAA==.Portalhouse:BAAALgAECgEJAQAAAA==.',
Pr='Praxis:BAACLgAFFH8JAAIWAAMJ2gm4FACqAAAWAAMJ2gm4FACqAAAuAAQKfxgAAhYACAmLCXUdAFoBABYACAmLCXUdAFoBAAAA.Preast:BAAALgADCgMJAwABLgAECggJFAAQAJEIAA==.Procist:BAAALgAECgkJCgABLgAECgkJMQARAMMiAA==.',
Py='Pyrusdk:BAABLgAECn8ZAAIGAAkJeg4QQQC5AQAGAAkJeg4QQQC5AQAAAA==.Pyrusdruid:BAAALgAECgkJEAAAAA==.',
Qo='Qop:BAAALgAECgkJBgAAAA==.',
Qu='Quesarah:BAAALgADCgEJAQABLgAECgQJBAALAAAAAA==.',
Qw='Qweffor:BAAALgAECgUJBQABLgAECggJFgAGAB0YAA==.',
Ra='Rainbowkelly:BAAALgAECgQJBAAAAA==.Raìn:BAABLgAECn8UAAIGAAgJ2BWENADmAQAGAAgJ2BWENADmAQAAAA==.',
Re='Reapy:BAABLgAFFH8FAAIGAAMJ4gmTawDeAAAGAAMJ4gmTawDeAAAAAA==.Recruitqt:BAABLgAECn8UAAIfAAUJxhkPOgCRAQAfAAUJxhkPOgCRAQAAAA==.Reiayanami:BAABLgAECn8fAAIKAAgJew/1XQCEAQAKAAgJew/1XQCEAQAAAA==.',
Ri='Ripandtear:BAABLgAECn8VAAMFAAgJNhY7MACYAQAFAAgJNhY7MACYAQAkAAEJFQZ6NgAsAAAAAA==.',
Ro='Roguewan:BAAALgAFFAEJAQAAAA==.Rolâyne:BAAALgADCgUJBQAAAA==.Roninn:BAABLgAECn8bAAIFAAgJrx1vDgCjAgAFAAgJrx1vDgCjAgAAAA==.Ronlock:BAABLgAECn8VAAMOAAYJ8xD9nQAdAQAOAAUJ8xD9nQAdAQANAAEJAAABagA+AAABLgAECgcJNgAIAG8aAA==.Royaltits:BAAALgADCgIJAgAAAA==.',
Rs='Rsi:BAAALgAECgQJBAAAAA==.',
Ry='Rynaea:BAAALgAECgEJAQAAAA==.',
['Rï']='Rïmuru:BAAALgADCgcJCwAAAA==.',
['Rô']='Rôlayne:BAAALgAECgcJEgAAAA==.',
Sa='Salvare:BAABLgAECn8lAAMVAAkJhhhwAwCVAgAVAAkJfRhwAwCVAgAlAAIJRRCdEgBzAAAAAA==.Sappy:BAAALgAECgQJBAAAAA==.Sauron:BAAALgADCgEJAQABLgAFFAQJCwAOADQUAA==.',
Sb='Sbf:BAABLgAFFH8VAAIdAAcJZA8CCQDLAQAdAAcJZA8CCQDLAQABLgAFFAcJNQAKANAbAA==.',
Sc='Scalamander:BAAALgAECgcJAgAAAA==.Sciohunter:BAABLgAFFH8FAAIIAAIJIAyhEwCSAAAIAAIJIAyhEwCSAAAAAA==.Scioscioz:BAACLgAFFH8GAAIFAAMJPA2tLADDAAAFAAMJPA2tLADDAAAuAAQKfyAAAwUABwnPFOI7ALUBAAUABwnPFOI7ALUBAA8AAglnEAJsAHAAAAAA.Scwisgar:BAAALgAECggJDAAAAA==.',
Se='Sedge:BAAALgAFFAIJAwAAAA==.Sephire:BAABLgAECn8eAAITAAkJOwQSjgAKAQATAAkJOwQSjgAKAQAAAA==.Sermazule:BAAALgADCgcJEQAAAA==.Sewerface:BAABLgAECn8VAAMHAAYJEBWaHgBTAQAHAAYJEBWaHgBTAQAGAAMJLAScAQF2AAAAAA==.',
Sh='Shadonir:BAAALgAECgQJBAAAAA==.Shadowind:BAACLgAFFH8QAAIYAAQJFxsjEgBhAQAYAAQJFxsjEgBhAQAuAAQKfy8AAwwACQl5Hm8JAJEBABgABQlkHb08AJgBAAwACAk2GW8JAJEBAAAA.Shaft:BAAALgAECgEJAQAAAA==.Shallotte:BAABLgAECn8YAAMgAAgJcxDoCwB7AQAgAAcJABLoCwB7AQAOAAcJoAgTdAAVAQAAAA==.Shammalxs:BAABLgAFFH8GAAIcAAUJSQTjEwAoAQAcAAUJSQTjEwAoAQAAAA==.Shamoc:BAABLgAECn8xAAMRAAkJwyLIAgBYAwARAAkJwyLIAgBYAwAcAAYJohESSQAjAQAAAA==.Shampooing:BAABLgAECn8jAAIcAAgJyhX3GADHAQAcAAgJyhX3GADHAQAAAA==.Sharpknife:BAABLgAFFH8GAAIYAAMJaA9cOgDdAAAYAAMJaA9cOgDdAAAAAA==.Shaz:BAAALgADCgQJBAAAAA==.Shivd:BAAALgAECgEJAQAAAA==.Shorpus:BAABLgAECn8ZAAQSAAgJqyAhCgAwAgASAAYJNx8hCgAwAgAcAAYJDRxuIgB8AQARAAcJCwj6XQATAQAAAA==.',
Si='Sicckbrew:BAABLgAECn8hAAIEAAkJaiH+CQDYAgAEAAkJaiH+CQDYAgABLgAFFAMJAwALAAAAAA==.Sickin:BAAALgAFFAMJAwAAAA==.Sinniestro:BAAALgAECgEJAgAAAA==.',
Sk='Skizzyy:BAAALgAECgMJAwABLgAECgcJEAALAAAAAA==.',
Sl='Slayedurmrs:BAAALgAECgQJBQAAAA==.Slowpoke:BAABLgAFFH8TAAIPAAUJvBgxEABBAQAPAAUJvBgxEABBAQAAAA==.',
Sm='Smacedh:BAABLgAECn8UAAIaAAgJhBOUYgB6AQAaAAgJhBOUYgB6AQAAAA==.Smesher:BAAALgAECgIJAwAAAA==.',
Sn='Sneakyfella:BAAALgAECgkJCgAAAA==.',
So='Solidus:BAABLgAFFH8GAAITAAQJmhR3IQBDAQATAAQJmhR3IQBDAQAAAA==.Sorgaath:BAAALgADCgcJBwAAAA==.',
Sp='Spaklehooves:BAAALgADCgYJBgAAAA==.Spicoli:BAAALgADCgEJAQAAAA==.Spiral:BAAALgAECgQJBwAAAA==.Spoonfed:BAAALgAECgQJCwAAAA==.',
Sq='Squiish:BAACLgAFFH8SAAMPAAYJ9RkSCgBIAQAPAAUJsBgSCgBIAQAFAAQJhwVjJADtAAAuAAQKfxoAAg8ABwmoJfALANkCAA8ABwmoJfALANkCAAAA.',
Ss='Ss:BAAALgAECgEJAwAAAA==.',
St='Stavrophore:BAAALgAECgEJAwAAAA==.Stickydruid:BAAALgAECgIJBQABLgAECgkJTQAZALYhAA==.Stickyholes:BAAALgAECgIJAgABLgAECgkJTQAZALYhAA==.Stickymonk:BAAALgAECgEJAgABLgAECgkJTQAZALYhAA==.Stickypriest:BAABLgAECn9NAAMZAAkJtiFEBADjAgAZAAkJtiFEBADjAgABAAEJExiTeQBCAAAAAA==.Stipe:BAAALgADCgUJCAAAAA==.Stove:BAAALgADCgcJCwAAAA==.Strawhats:BAACLgAFFH81AAIKAAcJ0BsgAwBMAgAKAAcJ0BsgAwBMAgAuAAQKf0IAAgoACQkyJWcCANgDAAoACQkyJWcCANgDAAAA.Streamliner:BAABLgAECn82AAMUAAkJchryBgB1AgAUAAkJchryBgB1AgAlAAMJ1gdKCwCNAAAAAA==.Stuunks:BAAALgAECgYJCwAAAA==.',
Su='Surv:BAABLgAFFH8JAAImAAQJyBifCABbAQAmAAQJyBifCABbAQAAAA==.Sustangelia:BAABLgAECn8bAAMGAAkJbhh6UAAAAgAGAAkJbhh6UAAAAgAnAAEJBw82HgBJAAAAAA==.',
Sw='Swordkiller:BAAALgAECgcJBgAAAA==.',
Sx='Sxy:BAAALgAECgMJAwABLgAECgkJPgAkAEUaAA==.',
Sy='Sy:BAAALgAECgcJEAAAAA==.Synthesis:BAABLgAECn8hAAIFAAgJoyW1AwBZAwAFAAgJoyW1AwBZAwAAAA==.',
Ta='Tae:BAAALgADCgUJBQAAAA==.Taichee:BAAALgADCgUJBQAAAA==.Talas:BAAALgADCgIJAgAAAA==.Talletalanot:BAABLgAECn8uAAIeAAkJHCDUAwC8AgAeAAkJHCDUAwC8AgAAAA==.Tandryan:BAAALgAECgQJBwAAAA==.Tanukiji:BAABLgAECn8nAAIBAAkJFxx1CACbAgABAAkJFxx1CACbAgAAAA==.',
Td='Tdh:BAAALgADCgMJAwAAAA==.Tdk:BAABLgAECn8WAAMGAAgJqRSXiwAEAQAGAAcJzRWXiwAEAQAHAAEJ0Q3SQQA6AAAAAA==.',
Te='Tee:BAAALgADCgUJBQAAAA==.Tesarion:BAABLgAECn8WAAIGAAgJHRihPQDFAQAGAAgJHRihPQDFAQAAAA==.Testalatesta:BAABLgAECn86AAMfAAgJ7iRvAgBVAwAfAAgJ7iRvAgBVAwATAAEJmwiCQAEvAAAAAA==.',
Th='Tharien:BAAALgADCgIJAgAAAA==.Thovir:BAAALgADCgEJAQAAAA==.',
Ti='Tiberian:BAAALgADCgIJAgAAAA==.Tinyvolt:BAAALgAECgcJCQAAAA==.',
Tm='Tmonk:BAAALgAECgkJDgAAAA==.',
To='Toinahun:BAAALgAECgQJBAAAAA==.Totemea:BAAALgAECgYJBgAAAA==.Totems:BAABLgAFFH8QAAIRAAUJzBvLCwCaAQARAAUJzBvLCwCaAQAAAA==.Totemîxx:BAABLgAECn8wAAMcAAkJnxlGCwBlAgAcAAkJnxlGCwBlAgARAAQJYQ23fgCYAAAAAA==.Touchhy:BAAALgAECgEJAQAAAA==.',
Tr='Trainz:BAAALgADCgcJBwAAAA==.Trass:BAACLgAFFH8GAAIOAAMJvwyQVgDQAAAOAAMJvwyQVgDQAAAuAAQKfz0AAw4ACQndILINAKwCAA4ACQndILINAKwCAA0AAwkuERxEAKUAAAAA.Trays:BAAALgADCgEJAQAAAA==.Trisse:BAABLgAECn8UAAIaAAYJPA6EbQD1AAAaAAYJPA6EbQD1AAAAAA==.',
Tu='Tuzz:BAABLgAECn8nAAInAAkJ6yBiAQDuAgAnAAkJ6yBiAQDuAgAAAA==.',
Ty='Tyden:BAAALgAECgYJEAAAAA==.',
Va='Vael:BAAALgAECgYJCgAAAA==.Valerie:BAAALgAECgQJBAAAAA==.Valkyrra:BAAALgAECgQJBAAAAA==.Varaestia:BAAALgAECgQJBAAAAA==.Varg:BAAALgADCgEJAQABLgADCgEJAQALAAAAAA==.Vargmk:BAAALgADCgEJAQAAAA==.Vargps:BAAALgADCgEJAQAAAA==.',
Ve='Velithara:BAAALgAECgcJBwAAAA==.Venestra:BAAALgADCgQJBAABLgAECgkJAQALAAAAAA==.Verdict:BAACLgAFFH8JAAITAAQJzBs1FQBoAQATAAQJzBs1FQBoAQAuAAQKfxgAAhMACAloHlsgAKoCABMACAloHlsgAKoCAAAA.Vermeil:BAAALgAECgMJAwAAAA==.Vermillion:BAACLgAFFH8VAAITAAUJJR0tEAB/AQATAAUJJR0tEAB/AQAuAAQKfyIAAhMACQnuIP0HAPgCABMACQnuIP0HAPgCAAAA.',
Vi='Vib:BAAALgAECgEJAQAAAA==.Viegas:BAACLgAFFH8FAAIYAAIJnRKNUQCSAAAYAAIJnRKNUQCSAAAuAAQKfxsAAhgABwkjHK4gAEECABgABwkjHK4gAEECAAAA.Vincent:BAABLgAECn8hAAIKAAYJsB6ZfgDUAQAKAAYJsB6ZfgDUAQAAAA==.Vinijr:BAAALgAECgEJAgAAAA==.Vivamax:BAAALgAECgEJAQAAAA==.',
Vo='Volthic:BAAALgAECgQJBAAAAA==.Voltormu:BAAALgAECgMJBgAAAA==.Vore:BAABLgAECn8YAAIaAAkJjRNeLADNAQAaAAkJjRNeLADNAQAAAA==.',
Vr='Vrag:BAABLgAECn8hAAIGAAcJMQrqegAkAQAGAAcJMQrqegAkAQAAAA==.',
['Vè']='Vè:BAABLgAECn8XAAMHAAkJ4w+AEQCeAQAHAAkJBQ+AEQCeAQAGAAcJKw+FYgBZAQAAAA==.',
Wa='Warslaw:BAACLgAFFH8NAAIHAAQJ0h5jCABrAQAHAAQJ0h5jCABrAQAuAAQKfx8AAgcACQkOIl8FAOsCAAcACQkOIl8FAOsCAAAA.Warth:BAAALgADCgEJAQAAAA==.Waterwater:BAAALgAECgYJCgAAAA==.Waterwaterz:BAACLgAFFH8MAAIKAAMJ3BuyKgAKAQAKAAMJ3BuyKgAKAQAuAAQKfzkAAgoACAnVHOQ0AJ8CAAoACAnVHOQ0AJ8CAAAA.',
Wc='Wchin:BAABLgAECn8XAAIoAAgJzB/jAACZAgAoAAgJzB/jAACZAgAAAA==.Wchinz:BAABLgAECn8WAAIZAAkJbCCPDgCaAgAZAAkJbCCPDgCaAgAAAA==.',
We='Wedlock:BAAALgADCgIJAgAAAA==.Welcumshot:BAABLgAFFH8FAAImAAMJZRDEEwD0AAAmAAMJZRDEEwD0AAAAAA==.Wenkar:BAAALgAECgQJBwABLgAECgkJUQANANodAA==.',
Wi='Windsabre:BAAALgADCgIJAgAAAA==.Wingz:BAAALgAECgYJBwAAAA==.',
Wo='Woregeonnick:BAABLgAECn8fAAIOAAcJVxEhZwCWAQAOAAcJVxEhZwCWAQAAAA==.Woshiren:BAAALgAECgUJBQAAAA==.',
Wy='Wyvern:BAAALgAECgQJCQAAAA==.',
['Wä']='Wärrior:BAAALgADCgMJAwAAAA==.',
Xa='Xanadu:BAAALgADCgIJAgAAAA==.',
Xe='Xerxexy:BAAALgAECgQJCwAAAA==.',
Xi='Xiaodingdang:BAAALgAECgQJBAAAAA==.Xiera:BAAALgAECgcJEQAAAA==.',
Ya='Yaminosaishi:BAAALgAECgYJBwAAAA==.Yaoyôrozu:BAAALgADCgkJFAAAAA==.Yasuô:BAAALgADCgMJAwAAAA==.Yatelega:BAAALgADCgIJAgABLgAECgcJHwAOAFcRAA==.Yazdorzarn:BAAALgAECgcJDAAAAA==.',
Yo='Yozzao:BAAALgAECgIJAwAAAA==.',
Za='Zaaniz:BAABLgAECn8lAAQTAAkJ8BtvHwCvAgATAAkJ8BtvHwCvAgAfAAQJggkcSADFAAAbAAIJ/Q3jLwBaAAAAAA==.',
Ze='Zenestra:BAAALgAECgkJAQAAAA==.Zenshui:BAAALgAECgYJCQAAAA==.Zephyruss:BAAALgADCgEJAQAAAA==.Zervis:BAAALgAECgIJAgAAAA==.Zeyra:BAAALgAECgYJDAAAAA==.',
Zi='Zinako:BAAALgAECgEJAQAAAA==.',
Zo='Zocalo:BAAALgAECgUJBQAAAA==.',
['Èa']='Èasymode:BAAALgADCgEJAQAAAA==.',
['Ód']='Ódyssey:BAABLgAECn8UAAISAAgJPxCoCwCPAQASAAgJPxCoCwCPAQAAAA==.',
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
