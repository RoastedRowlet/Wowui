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

local lookup = {'Hunter-BeastMastery','Paladin-Retribution','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Warlock-Demonology','Priest-Shadow','Warrior-Fury','Unknown-Unknown','DeathKnight-Blood','Warlock-Affliction','Warlock-Destruction','Mage-Frost','Shaman-Enhancement','Priest-Holy','Monk-Windwalker','Monk-Brewmaster','DemonHunter-Havoc','Druid-Guardian','Druid-Balance','Monk-Mistweaver','Rogue-Outlaw','DeathKnight-Unholy','Paladin-Holy','Mage-Arcane','DeathKnight-Frost','Druid-Feral','Hunter-Survival','Priest-Discipline','DemonHunter-Devourer','Druid-Restoration','DemonHunter-Vengeance','Warrior-Protection','Warrior-Arms','Evoker-Preservation','Evoker-Augmentation','Paladin-Protection',}
local provider = {region='US',realm='BlackwaterRaiders',name='US',type='weekly',zone=46,date='2026-05-30',data={Ad='Adamonious:BAAALgAECgYJCwABLgAECgkJFgABAA8WAA==.Adaware:BAAALgAECgUJBgAAAA==.Addieeboy:BAAALgADCgEJAQAAAA==.Adellea:BAAALgAECgYJBwAAAA==.',
Ai='Aisha:BAAALgAECgEJAgAAAA==.',
Al='Alba:BAABLgAECn8qAAICAAgJCh1OMQAiAgACAAgJCh1OMQAiAgABLgAFFAQJDQABACEZAA==.Aletta:BAAALgAECgYJBwAAAA==.Allast:BAAALgADCgYJDQAAAA==.',
An='Andezard:BAABLgAECn81AAMBAAkJNxenJQA0AgABAAkJNxenJQA0AgADAAIJTAkhLQBTAAAAAA==.Angelys:BAAALgAECgcJEAAAAA==.',
Ap='Aphrobitey:BAAALgAECgIJAgAAAA==.',
Aq='Aquâ:BAAALgADCgkJDwAAAA==.',
Ar='Arathas:BAAALgADCgcJDAAAAA==.Arianes:BAAALgAECgcJDgABLgAECgkJKwACAKQkAA==.Arrowin:BAAALgADCgYJBgAAAA==.Arturias:BAABLgAECn8aAAICAAgJdxKBZACNAQACAAgJdxKBZACNAQAAAA==.',
At='Athenaowl:BAAALgAECggJDwAAAA==.',
Au='Autofocus:BAABLgAECn8eAAIBAAgJPBqINgDsAQABAAgJPBqINgDsAQAAAA==.',
Aw='Aweyna:BAAALgAECgkJEgAAAA==.Awisha:BAAALgADCgUJBQAAAA==.',
Ay='Ayanoriko:BAACLgAFFH8NAAIEAAQJjBNEBAA4AQAEAAQJjBNEBAA4AQAuAAQKfyoAAgQACAmMH/ADAHwCAAQACAmMH/ADAHwCAAAA.Ayasumi:BAAALgAECgIJAgAAAA==.',
Ba='Babaganoosh:BAAALgAECgQJCgAAAA==.Baoyue:BAAALgAECggJCwABLgAFFAUJDgAFAOcYAA==.Barracuda:BAAALgAECgYJBgAAAA==.',
Be='Beans:BAABLgAFFH8FAAIGAAMJCxG4ZwDbAAAGAAMJCxG4ZwDbAAABLgAFFAYJCQAHAJofAA==.Benmonk:BAAALgAECgMJAwAAAA==.',
Bi='Bifur:BAAALgADCgkJDwAAAA==.Bigstones:BAACLgAFFH8IAAIIAAMJRQTqMwCxAAAIAAMJRQTqMwCxAAAuAAQKfyMAAggACAnsDnkzAGcBAAgACAnsDnkzAGcBAAAA.',
Bl='Blacksavior:BAAALgAECgQJBAAAAA==.Blindbone:BAAALgAECgcJCQABLgAECggJEwAJAAAAAA==.Bluehydra:BAAALgADCgcJCAAAAA==.',
Bo='Bobbydigital:BAABLgAECn84AAIKAAkJghtBCQBrAgAKAAkJghtBCQBrAgAAAA==.Bohd:BAAALgADCgIJAgAAAA==.Bolas:BAAALgAECgEJAQAAAA==.Boneski:BAAALgAECgUJEAAAAA==.Booger:BAAALgAECgQJBAAAAA==.',
Br='Bracynn:BAABLgAECn8gAAIKAAcJ5wecMADDAAAKAAcJ5wecMADDAAAAAA==.Brixx:BAAALgAECgMJAwAAAA==.Brudiclad:BAABLgAECn8sAAQLAAkJNBRvCADCAQALAAkJphJvCADCAQAGAAYJaQvNmQD/AAAMAAIJzxH2UQB4AAAAAA==.',
Bu='Budfight:BAAALgADCgkJDgAAAA==.Burnt:BAAALgAECgQJBAAAAA==.Butterfinger:BAAALgADCgQJBwAAAA==.Buxxor:BAAALgAECgcJBwAAAA==.',
Ca='Caimark:BAABLgAECn8uAAINAAgJzgO5vADxAAANAAgJzgO5vADxAAAAAA==.Calahan:BAACLgAFFH8HAAICAAMJgBnaUgDnAAACAAMJgBnaUgDnAAAuAAQKfx4AAgIACAmxGmw0AFACAAIACAmxGmw0AFACAAAA.',
Ch='Chakuneeai:BAAALgADCgYJBgAAAA==.Chancleta:BAAALgAECgYJCQAAAA==.Cherub:BAAALgADCgIJAgAAAA==.Chikostix:BAABLgAECn8mAAIOAAcJ6gicGAAcAQAOAAcJ6gicGAAcAQAAAA==.Christae:BAABLgAECn8nAAIPAAkJNRlxDgBnAgAPAAkJNRlxDgBnAgAAAA==.',
Cl='Clementînê:BAAALgAECgIJAgAAAA==.Clemêntine:BAAALgAECgYJDAAAAA==.Clydè:BAABLgAECn9SAAMQAAkJ6RaHFABJAgAQAAgJbheHFABJAgARAAkJrhKeGQDHAQAAAA==.Cláncey:BAAALgAFFAEJAQAAAA==.',
Co='Coachhazzard:BAAALgAECgQJCwAAAA==.Cocytus:BAAALgADCgIJAgABLgAFFAIJBwAGADkaAA==.Colinferal:BAAALgAFFAEJAgAAAA==.Combatant:BAAALgADCgYJDAAAAA==.Compromise:BAAALgAECgYJCAAAAA==.Compromised:BAABLgAECn8vAAISAAkJ3hsLCQB/AgASAAkJ3hsLCQB/AgAAAA==.Connalious:BAAALgAECgEJAQAAAA==.Conquests:BAAALgAECgIJAgAAAA==.Corelack:BAACLgAFFH8KAAITAAMJdRWGEgDHAAATAAMJdRWGEgDHAAAuAAQKfxcAAxMACQm9DRcfAC4BABMACQmZDRcfAC4BABQABQmpBV9ZAJAAAAAA.',
Cr='Crwth:BAAALgAECgUJBQAAAA==.',
Ct='Ctrlaltmagic:BAAALgAECgEJAgAAAA==.',
Cu='Cupis:BAAALgAECgQJBAAAAA==.Curendae:BAABLgAECn8vAAIBAAkJwRdpJQA1AgABAAkJwRdpJQA1AgAAAA==.',
Da='Dabaldzombie:BAACLgAFFH8TAAINAAUJoxr6UQAuAQANAAUJoxr6UQAuAQAuAAQKfxgAAg0ACQktGDxMAFICAA0ACQktGDxMAFICAAAA.Danamy:BAAALgADCggJDQAAAA==.Daxzazi:BAABLgAECn8cAAMQAAcJ9gOjTQC3AAAQAAcJ9gOjTQC3AAAVAAUJrARleQByAAAAAA==.',
De='Deadlee:BAAALgADCgEJAQAAAA==.Deadmanwlkin:BAAALgADCgIJAgAAAA==.Defias:BAAALgADCggJCAAAAA==.Delicious:BAEALgAFFAIJAgABLgAFFAYJGgANAO4SAA==.Despair:BAAALgADCggJDgABLgAFFAQJDQABACEZAA==.',
Di='Dice:BAACLgAFFH8QAAIWAAUJAB7NAgBnAQAWAAUJAB7NAgBnAQAuAAQKfywAAxYACQnjIeEAAAIDABYACQnjIeEAAAIDAAUAAQmeFPROAEYAAAAA.Disturbd:BAACLgAFFH8OAAMXAAUJ5ApPagAKAQAXAAQJ5ApPagAKAQAKAAEJAAAdTwAAAAAuAAQKfxgAAxcACQn9DHdUALMBABcACQn9DHdUALMBAAoABAmJAMY9AFsAAAAA.Disturbian:BAAALgAFFAIJAwABLgAFFAUJDgAXAOQKAA==.Dixierecht:BAABLgAECn8gAAIYAAgJbhsjFQBNAgAYAAgJbhsjFQBNAgAAAA==.',
Do='Docvader:BAAALgAECgEJAQAAAA==.Dodrop:BAAALgADCgYJBwAAAA==.',
Dr='Drunkenhealz:BAAALgAECgUJEAAAAA==.Drvargas:BAAALgAECgQJCgAAAA==.',
['Då']='Dårth:BAAALgAECgEJAQAAAA==.',
['Dè']='Dèrty:BAAALgAECgIJAgAAAA==.',
El='Elenestern:BAEBLgAECn8qAAINAAkJxhAARwDvAQANAAkJxhAARwDvAQAAAA==.Elmo:BAABLgAECn8oAAMNAAkJHhZaNQArAgANAAkJ0BVaNQArAgAZAAEJwxWpEQA/AAAAAA==.',
Em='Emryssa:BAAALgAECgMJDAAAAA==.',
Er='Erosis:BAACLgAFFH8NAAINAAQJ/xsYOABiAQANAAQJ/xsYOABiAQAuAAQKfyMAAg0ACAkjIwIvALYCAA0ACAkjIwIvALYCAAAA.',
Es='Esia:BAAALgADCgkJCQAAAA==.',
Ev='Evarg:BAAALgADCgUJBgAAAA==.',
Ez='Ezaratren:BAAALgAECgUJCgABLgAFFAMJCgATAHUVAA==.',
Fa='Fakêr:BAAALgADCgEJAQAAAA==.',
Fe='Fear:BAACLgAFFH8FAAIGAAMJMxu+HQANAQAGAAMJMxu+HQANAQAuAAQKfygAAwYACAmDIOgrAF8CAAYACAmDIOgrAF8CAAwABQkbFk4bAHIBAAAA.Felcatalyist:BAABLgAECn8gAAMXAAkJABgcYwDKAQAXAAkJtBUcYwDKAQAKAAgJXA3aIwAZAQAAAA==.Felisaty:BAAALgAECgEJAQAAAA==.Fellisaty:BAABLgAECn8WAAIYAAgJfQ+mLQCSAQAYAAgJfQ+mLQCSAQAAAA==.Felysria:BAAALgAECgQJAgAAAA==.',
Fi='Fistitresk:BAAALgADCgQJBAABLgAECgcJEwAJAAAAAA==.Fistofwayne:BAABLgAECn8cAAIRAAgJMBDqJABzAQARAAgJMBDqJABzAQABLgAFFAUJFAAaABAgAA==.',
Fr='Frizzalot:BAAALgAECgEJAwAAAA==.Frizzer:BAAALgAECgMJAwAAAA==.',
Ga='Gakopozy:BAAALgAECgYJDwAAAA==.Gambrinos:BAAALgADCgMJAwAAAA==.Gander:BAAALgADCgEJAQABLgAECgEJAQAJAAAAAA==.Gandermon:BAAALgAECgEJAQAAAA==.',
Ge='Geg:BAABLgAFFH8FAAIXAAMJvBEhJwD7AAAXAAMJvBEhJwD7AAAAAA==.',
Gl='Glorrex:BAAALgADCgYJBgAAAA==.',
Go='Gongsho:BAAALgAECgQJBAAAAA==.',
Gr='Grapez:BAAALgAFFAIJAgABLgAFFAYJHgAaAKceAA==.Grïmyst:BAAALgAECgEJAQABLgAFFAMJCgATAHUVAA==.',
Gu='Guldán:BAAALgAECgYJEQAAAA==.',
Gw='Gwydre:BAACLgAFFH8TAAIKAAQJaCDnDQBhAQAKAAQJaCDnDQBhAQAuAAQKfxUAAgoACAnqHvYNAC4CAAoACAnqHvYNAC4CAAAA.',
Ha='Havran:BAAALgAECgQJBAABLgAECgkJQwATABYXAA==.Havrin:BAABLgAECn9DAAMTAAkJFhfvDQDhAQATAAkJFhfvDQDhAQAbAAEJQhLgMQA7AAAAAA==.',
He='Headshots:BAACLgAFFH8NAAIBAAQJIRmlKwA/AQABAAQJIRmlKwA/AQAuAAQKfy4AAgEACQmVH10UAJMCAAEACQmVH10UAJMCAAAA.Heartsong:BAAALgAECgEJAQAAAA==.Hexatar:BAAALgAECgQJBAAAAA==.',
Hk='Hkia:BAAALgAECggJCQAAAA==.',
Ho='Hoardkiller:BAAALgAECgQJAwABLgAFFAQJDwAcANQNAA==.Holmie:BAAALgADCgkJCgAAAA==.Honk:BAAALgAFFAIJAwAAAA==.Hoofsoflove:BAAALgADCgQJBAAAAA==.Hoogaplop:BAACLgAFFH8ZAAMXAAUJkybCIgCgAQAXAAUJkybCIgCgAQAKAAUJqB+uDQBkAQAuAAQKfzsAAxcACQkcJAMUAAMDABcACQlWIQMUAAMDAAoACAmPIm8GAKgCAAEuAAUUBgkJAAcAmh8A.',
Hu='Huamulan:BAABLgAECn8+AAICAAkJ0gaIigBAAQACAAkJ0gaIigBAAQAAAA==.',
Ib='Ibc:BAAALgADCgcJDQABLgAFFAIJAgAJAAAAAA==.Ibchilling:BAABLgAECn8pAAINAAgJxBrERwDtAQANAAgJxBrERwDtAQABLgAFFAIJAgAJAAAAAA==.Ibcorrupted:BAAALgAFFAIJAgAAAA==.',
Ic='Icarrus:BAACLgAFFH8PAAIVAAQJJRG5JQDsAAAVAAQJJRG5JQDsAAAuAAQKfywAAxUACQnkHDgWAEUCABUACQnkHDgWAEUCABAABAmQE5pRAKsAAAEuAAUUBAkGABcAPQkA.Icarus:BAAALgADCgEJAQABLgAFFAQJBgAXAD0JAA==.Iccarus:BAAALgAECgUJBQABLgAFFAQJBgAXAD0JAA==.Icebone:BAAALgAECgcJCgABLgAECggJEwAJAAAAAA==.',
Ig='Ignis:BAACLgAFFH8GAAIXAAQJPQnBawAIAQAXAAQJPQnBawAIAQAuAAQKfxYAAxcABgl5Gxp3AGABABcABgnzGRp3AGABABoAAQkRFvMsAEEAAAAA.',
Il='Illioch:BAAALgAECgEJAQAAAA==.',
Im='Imaway:BAAALgAECgEJAQAAAA==.',
In='Inesh:BAAALgADCgEJAQAAAA==.',
Ir='Irrizia:BAAALgADCgkJCgAAAA==.',
Is='Iseldra:BAAALgADCggJDgAAAA==.',
['Iç']='Içyhot:BAAALgAECgEJBAABLgAECgcJEwAJAAAAAA==.',
Ja='Jackbfistn:BAAALgAECggJEwAAAA==.Jaskim:BAABLgAECn8dAAMXAAkJzAxQVgCuAQAXAAkJzAxQVgCuAQAaAAIJ2AU7MAAzAAAAAA==.',
Je='Jeses:BAAALgAECgUJCAABLgAECgkJLwACAEIWAA==.',
Jo='Jolty:BAAALgAECgEJAQABLgAFFAUJFAAXAAUiAA==.Jooni:BAAALgADCggJDwAAAA==.Jordomon:BAABLgAECn8bAAMUAAcJWwYZSADPAAAUAAcJTwYZSADPAAAbAAMJ8gb+NABgAAAAAA==.',
Jy='Jyundiel:BAAALgADCgYJBgABLgADCgYJBgAJAAAAAA==.',
['Jú']='Júliët:BAAALgAECgIJAgAAAA==.',
Ka='Kaazaama:BAAALgADCgYJBgAAAA==.Kahtonah:BAAALgADCgMJAwAAAA==.Kalessin:BAAALgADCgkJDgAAAA==.Kaltaan:BAABLgAECn8sAAQdAAkJxiFVBQAbAwAdAAkJxiFVBQAbAwAPAAQJUh8jPABKAQAHAAEJ4R1JZgBXAAAAAA==.Karasan:BAABLgAECn8jAAIBAAkJ0BfoKAAkAgABAAkJ0BfoKAAkAgAAAA==.Karenas:BAABLgAECn8lAAMNAAgJoSGvGgCkAgANAAgJoSGvGgCkAgAZAAIJ4QqZFgBmAAAAAA==.Karr:BAABLgAECn8XAAICAAgJNAfFpQATAQACAAgJNAfFpQATAQAAAA==.Kataraara:BAACLgAFFH8HAAIRAAQJRiDrEQBsAQARAAQJRiDrEQBsAQAuAAQKfxcAAhEACAntJN4EADwDABEACAntJN4EADwDAAEuAAUUBgkWAAoABCYA.Katbeans:BAABLgAECn8pAAQVAAkJeRs/DAC2AgAVAAkJeRs/DAC2AgARAAUJIQ6RYgC4AAAQAAEJJhaLgwA8AAAAAA==.Kathrynne:BAAALgAECgUJCQAAAA==.Katrielle:BAAALgAECgUJBQAAAA==.',
Ke='Kelicemoon:BAABLgAECn8oAAMGAAkJZgoFWACJAQAGAAkJSQkFWACJAQAMAAcJIQcaLABZAAAAAA==.Kemono:BAAALgADCgYJBgAAAA==.',
Kh='Khaliope:BAABLgAECn82AAIeAAkJpQ01bAAxAQAeAAkJpQ01bAAxAQAAAA==.',
Ki='Kiryu:BAAALgAECgUJBQAAAA==.',
Ko='Korzari:BAAALgADCgEJAQAAAA==.Koven:BAAALgADCgcJCQAAAA==.',
Kr='Krogers:BAAALgAECgQJCQABLgAECgYJBwAJAAAAAA==.',
Ku='Kumojo:BAAALgAECgkJAgAAAA==.',
Ky='Kyndlearya:BAAALgADCgEJAQAAAA==.',
['Kû']='Kûrr:BAAALgAECgEJAQABLgAFFAEJAQAJAAAAAA==.',
La='Lahrnaon:BAAALgAFFAIJAgAAAA==.Laxeron:BAABLgAECn8iAAIIAAkJQCTxAwAZAwAIAAkJQCTxAwAZAwAAAA==.',
Le='Leotherassy:BAAALgAECgQJBwAAAA==.Leychron:BAAALgAECgEJAQAAAA==.',
Li='Lightsworn:BAAALgAECgEJAQAAAA==.Lilin:BAAALgAECgYJBwAAAA==.',
Lo='Lotiel:BAAALgAECgMJCQABLgAFFAQJEwAfAIQWAA==.',
Lu='Lucrecia:BAABLgAECn8WAAMeAAYJbB0oUgCuAQAeAAUJ2iEoUgCuAQAgAAEJswudLAAuAAAAAA==.',
Ly='Lymara:BAAALgADCgcJCAAAAA==.Lynthirae:BAAALgADCgcJDAAAAA==.',
['Lø']='Lørðzêdd:BAAALgAECgQJEgAAAA==.',
Ma='Madmabel:BAAALgADCgQJBAAAAA==.Mahkaidook:BAAALgADCgYJBgAAAA==.Mal:BAAALgADCgkJCQABLgAECggJGgAgABIgAA==.Manyace:BAAALgAECgQJBgAAAA==.',
Mc='Mcbodhran:BAABLgAECn8gAAICAAkJDA/SbAB7AQACAAkJDA/SbAB7AQAAAA==.Mcfeast:BAABLgAECn8ZAAIHAAgJ+A/aJgB1AQAHAAgJ+A/aJgB1AQAAAA==.',
Me='Medra:BAABLgAECn8sAAQIAAkJJRQVHwDiAQAIAAkJJRQVHwDiAQAhAAQJEgPYOgBuAAAiAAEJ2ATodgAfAAAAAA==.Meowdi:BAAALgADCgkJDgAAAA==.Merogoth:BAAALgADCgUJBwAAAA==.Mestrois:BAABLgAECn81AAINAAgJRAfcmAAtAQANAAgJRAfcmAAtAQAAAA==.',
Mi='Minibone:BAAALgAECgMJAwABLgAECggJEwAJAAAAAA==.Mixr:BAAALgADCgQJAwAAAA==.',
Mo='Monana:BAAALgADCgkJBQAAAA==.Morar:BAAALgAECgUJDAAAAA==.Morul:BAAALgAECgQJBAAAAA==.',
Ms='Msprettÿp:BAAALgADCgIJAgAAAA==.',
Mu='Murimlinn:BAAALgADCgMJAwAAAA==.Mustafa:BAAALgAECgUJCAAAAA==.',
Na='Nanija:BAAALgADCgkJDgAAAA==.Narushi:BAAALgAECgQJBAAAAA==.',
Ne='Nezrin:BAAALgADCgQJBwAAAA==.',
Ni='Nightcat:BAAALgAECgQJBQAAAA==.Nitebäne:BAAALgADCggJCAAAAA==.Nitesbane:BAAALgADCgYJBgABLgAECggJFwACAKAgAA==.Nitesbåne:BAAALgADCgcJBwAAAA==.Niteshiftah:BAAALgADCgcJBwAAAA==.Nitestorm:BAAALgAECgQJBAAAAA==.Nivaniraa:BAAALgAECgEJAgAAAA==.Nixie:BAABLgAECn8uAAMfAAkJEgb4WgAUAQAfAAkJEgb4WgAUAQAUAAkJ8gThPAAAAQAAAA==.',
No='Nobonesjones:BAACLgAFFH8LAAISAAUJlQacBgDfAAASAAUJlQacBgDfAAAuAAQKfxsAAhIACQlPFjMeAM4BABIACQlPFjMeAM4BAAAA.',
Og='Oguricap:BAAALgADCgcJBwAAAA==.Ogwarshock:BAACLgAFFH8NAAMGAAQJeBqyQwAtAQAGAAQJzxWyQwAtAQAMAAEJChvqHgBOAAAuAAQKfyIAAwYACAkeIxYyAAMCAAYABgmwIhYyAAMCAAwABQm9HzkaAHsBAAAA.',
Ok='Okkotsu:BAAALgAECgIJAwAAAA==.',
Ol='Oliiver:BAABLgAECn8uAAIBAAkJdSDWCQD1AgABAAkJdSDWCQD1AgAAAA==.',
Om='Omni:BAAALgADCgIJAgABLgAFFAMJCgATAHUVAA==.Omnivore:BAAALgADCgcJCAAAAA==.Omën:BAAALgAECgQJBAABLgAECgQJCAAJAAAAAA==.',
On='Oniichan:BAAALgAECgQJBQAAAA==.',
Or='Orbeez:BAABLgAECn8oAAIeAAkJNyB6EgCbAgAeAAkJNyB6EgCbAgAAAA==.',
Pa='Pack:BAAALgAECgcJAQAAAA==.Panaceus:BAABLgAECn86AAIjAAkJ1yKcAQBxAwAjAAkJ1yKcAQBxAwAAAA==.Paragon:BAAALgADCgkJDQABLgAFFAMJDgAXAFYgAA==.Patron:BAAALgADCgIJAwAAAA==.',
Pe='Pepe:BAAALgAECgEJAQAAAA==.Perennial:BAAALgAECgYJCQAAAA==.Perpetrator:BAAALgAECgEJAgAAAA==.',
Ph='Phreeq:BAEALgAECgYJDgABLgAECggJJwAYAPcRAA==.Phrequency:BAEBLgAECn8nAAMYAAgJ9xFcJADNAQAYAAgJ9xFcJADNAQACAAYJNxXvkAA1AQAAAA==.',
Pi='Piety:BAAALgADCgIJAgAAAA==.Pig:BAAALgAECgEJAQABLgAFFAYJCQAHAJofAA==.',
Pl='Playingwow:BAAALgAECgcJEgAAAA==.Plazmafury:BAAALgAFFAIJAgAAAA==.Plumsham:BAAALgADCgQJBAAAAA==.',
Po='Poisonóus:BAACLgAFFH8NAAIKAAQJrBgXEwAoAQAKAAQJrBgXEwAoAQAuAAQKfzAAAgoACAmEHlwMACwCAAoACAmEHlwMACwCAAAA.',
Pr='Profang:BAAALgAECgQJBAAAAA==.',
Py='Pyrelic:BAABLgAFFH8UAAIQAAUJgRo9DgA4AQAQAAUJgRo9DgA4AQAAAA==.Pyroela:BAAALgAECgUJCgABLgAFFAQJEwAKAGggAA==.',
['Pö']='Pöncho:BAAALgAECgEJAQAAAA==.',
Qa='Qayllera:BAAALgAECgQJBwAAAA==.',
Qe='Qelcie:BAAALgAECgQJBQAAAA==.',
Qu='Quizet:BAAALgADCgYJCAAAAA==.',
Ra='Radicchio:BAAALgADCgkJBQAAAA==.Radkeem:BAABLgAECn8YAAIKAAkJiB10BwCQAgAKAAkJiB10BwCQAgAAAA==.Raf:BAAALgAECgYJBwAAAA==.Raizo:BAAALgAECgEJAgAAAA==.Rakeem:BAAALgAECgcJEAABLgAECgkJGAAKAIgdAA==.Ralivan:BAAALgADCgEJAQAAAA==.Ravenhawk:BAAALgADCgQJCAAAAA==.Razorknight:BAAALgAECgEJAQAAAA==.',
Re='Redtoxin:BAAALgADCgkJDwAAAA==.Reilley:BAACLgAFFH8WAAIXAAUJAxrYSABAAQAXAAUJAxrYSABAAQAuAAQKfysAAhcACAmaIXwcAIkCABcACAmaIXwcAIkCAAAA.Reilleÿ:BAAALgAECgQJBAABLgAFFAUJFgAXAAMaAA==.Reko:BAAALgAECgYJBgAAAA==.Remorsa:BAAALgAECgYJEAAAAA==.Renni:BAABLgAECn8sAAIGAAkJxBbtJwAuAgAGAAkJxBbtJwAuAgAAAA==.Reshath:BAAALgADCgEJAQAAAA==.Reznor:BAABLgAECn8kAAIYAAkJLBbDJwDtAQAYAAkJLBbDJwDtAQAAAA==.',
Ri='Rinela:BAAALgADCgcJBwAAAA==.Riselle:BAAALgAECgQJBAAAAA==.',
Ro='Rosealia:BAABLgAECn8XAAIBAAcJ/QVljwAGAQABAAcJ/QVljwAGAQAAAA==.',
Ru='Runeight:BAAALgADCgIJAQAAAA==.',
Ry='Ryder:BAAALgAECgIJBAAAAA==.',
['Ró']='Rómëo:BAACLgAFFH8OAAIFAAUJ5xiBEgBVAQAFAAUJ5xiBEgBVAQAuAAQKf04AAgUACQl3In8CACMDAAUACQl3In8CACMDAAAA.',
Sa='Sabbatical:BAAALgADCgEJAQAAAA==.Sacon:BAAALgADCgcJBwABLgAECggJGgAgABIgAA==.Saintzan:BAAALgAECgkJEQAAAA==.Salivan:BAAALgAECgUJCgAAAA==.San:BAAALgAECgYJDwAAAA==.Sanketsu:BAAALgADCgYJCwABLgAECgkJKwACAFYUAA==.Sathariel:BAAALgAECgIJAgAAAA==.',
Sc='Scalyboyos:BAABLgAECn8kAAMjAAkJggv4FgBNAQAjAAgJcQv4FgBNAQAkAAEJxwf5gAA5AAAAAA==.Schmoop:BAACLgAFFH8JAAIHAAYJmh+zBgDQAQAHAAYJmh+zBgDQAQAuAAQKfy4ABAcACAnyI/YHALYCAAcACAnyI/YHALYCAA8ABgmLGp8rAFYBAB0AAQnxEGNWADQAAAAA.',
Se='Seldaria:BAAALgAECgYJEAAAAA==.Senza:BAABLgAECn8hAAICAAcJZQpxrAAIAQACAAcJZQpxrAAIAQAAAA==.Senzyri:BAABLgAECn8mAAIBAAkJLxMINAD2AQABAAkJLxMINAD2AQAAAA==.Sephirath:BAAALgAECgIJAgAAAA==.Serote:BAAALgADCgcJBwAAAA==.Setmabone:BAAALgADCgkJCQABLgAECggJEwAJAAAAAA==.Sevilo:BAAALgADCgkJCwABLgAECgIJAgAJAAAAAA==.',
Sh='Shamagoth:BAAALgADCgEJAQAAAA==.Shambhala:BAAALgAECgYJDAAAAA==.Shoes:BAAALgAECgUJBwAAAA==.',
Si='Simic:BAABLgAECn8vAAIKAAkJzQ9GGACGAQAKAAkJzQ9GGACGAQAAAA==.',
Sk='Skre:BAAALgAECgYJBgAAAA==.',
Sm='Smokeace:BAAALgAECgEJAQAAAA==.',
Sn='Snowthistle:BAABLgAECn8WAAIUAAcJQgWDSwDBAAAUAAcJQgWDSwDBAAAAAA==.',
So='Sorle:BAAALgADCgYJCQABLgAECgkJLAAIACUUAA==.Soulnãris:BAAALgAECgcJCQAAAA==.',
Sp='Spin:BAABLgAFFH8HAAMQAAIJwhefJwCLAAAQAAIJIRSfJwCLAAARAAEJIBehTQBFAAAAAA==.Spudpal:BAAALgADCgEJAQABLgAECgkJLAAdAMYhAA==.Spyro:BAAALgADCgUJBQAAAA==.',
Sq='Squirley:BAAALgAECgQJCAAAAA==.',
St='Starge:BAAALgAECgYJBgAAAA==.Stargefall:BAAALgAECgMJAwAAAA==.Static:BAAALgAECgYJBgAAAA==.Stonymahoney:BAABLgAECn88AAICAAkJjxpDIwBgAgACAAkJjxpDIwBgAgAAAA==.',
Su='Sudokoo:BAAALgADCgMJAwAAAA==.Sumorna:BAAALgAECgEJAQAAAA==.Suraisu:BAABLgAECn81AAIIAAkJPyRAAgBFAwAIAAkJPyRAAgBFAwAAAA==.Suê:BAAALgADCgEJAQABLgADCgQJBAAJAAAAAA==.',
Sv='Sveela:BAACLgAFFH8QAAITAAQJpiJmBACUAQATAAQJpiJmBACUAQAuAAQKfyQAAhMACQlrIsEDAMoCABMACQlrIsEDAMoCAAAA.Sveelaa:BAABLgAECn8lAAIBAAgJax+CGAB8AgABAAgJax+CGAB8AgABLgAFFAQJEAATAKYiAA==.Sveella:BAAALgAECgcJBwABLgAFFAQJEAATAKYiAA==.',
Sw='Swampjimmy:BAAALgAECgYJCAAAAA==.',
Sy='Sylrin:BAAALgADCgcJCgAAAA==.Synap:BAAALgADCgEJAQAAAA==.',
Ta='Tabchan:BAAALgAECgYJBwAAAA==.Tacocat:BAABLgAECn89AAMPAAkJmR5nBwDkAgAPAAkJmR5nBwDkAgAHAAEJNAVpggAnAAAAAA==.Talras:BAAALgAECgMJAwAAAA==.',
Te='Temlock:BAABLgAECn8wAAIGAAgJPRosMQBIAgAGAAgJPRosMQBIAgAAAA==.Tempest:BAAALgAECgUJBQABLgAFFAMJDgAXAFYgAA==.Temtank:BAABLgAECn82AAIKAAkJJCKPAwD2AgAKAAkJJCKPAwD2AgABLgAECggJMAAGAD0aAA==.',
Tr='Trak:BAABLgAECn8ZAAIkAAgJOQ2qOQAlAQAkAAgJOQ2qOQAlAQAAAA==.Trukarak:BAABLgAECn8rAAICAAkJVhS5QQDpAQACAAkJVhS5QQDpAQAAAA==.',
Tu='Tuvaquitamuu:BAAALgAECgEJAQAAAA==.',
Va='Vaeegoldiir:BAAALgAECgEJAQAAAA==.Vaelithria:BAAALgAECgcJCAABLgAFFAUJDgAFAOcYAA==.Valenti:BAABLgAECn8jAAMlAAgJaw9wFgBTAQAlAAgJaw9wFgBTAQACAAEJ0AZOkgElAAAAAA==.Valor:BAABLgAECn8kAAICAAcJhiFURwDYAQACAAcJhiFURwDYAQAAAA==.Vanity:BAAALgADCgMJAwAAAA==.',
Ve='Veliann:BAAALgAECgEJAQAAAA==.Vellatrix:BAAALgAECgQJBgAAAA==.Velynesti:BAAALgAECgQJBAAAAA==.',
Vi='Vipershot:BAAALgADCggJDwAAAA==.',
Wa='Warlode:BAAALgADCgkJDgAAAA==.',
We='Weewoo:BAAALgADCgcJCwAAAA==.',
Wi='Wildama:BAABLgAECn8jAAIfAAkJnA/ZNQCvAQAfAAkJnA/ZNQCvAQAAAA==.Wildtail:BAAALgAECgYJCQAAAA==.',
Wr='Wrenwillow:BAAALgAECgIJAgAAAA==.',
Wu='Wumbo:BAAALgADCgEJAQAAAA==.',
Xa='Xarríøn:BAAALgADCgYJBgABLgAFFAMJCAACAB0ZAA==.',
Xh='Xhadowz:BAAALgAECgEJAgAAAA==.',
Xi='Xiao:BAABLgAECn8uAAMVAAkJuReyFABTAgAVAAkJuReyFABTAgAQAAQJoAqRTwCxAAAAAA==.',
Xy='Xylaini:BAAALgAECgQJBAABLgAFFAEJAQAJAAAAAA==.',
Ya='Yahargul:BAABLgAECn8iAAIHAAgJkg0FLABVAQAHAAgJkg0FLABVAQAAAA==.',
Yo='Yogafarts:BAAALgAECgYJCAAAAA==.',
Za='Zanatilli:BAAALgADCgkJCQAAAA==.Zaterok:BAAALgAECgMJAwABLgAECgkJKwACAFYUAA==.',
Ze='Zeik:BAABLgAECn8zAAMlAAkJVB6qAwC9AgAlAAkJVB6qAwC9AgACAAMJngp1MwFbAAAAAA==.Zephyrgosa:BAAALgADCgcJDgAAAA==.Zerase:BAAALgADCgkJDgAAAA==.',
Zu='Zucco:BAAALgAECgkJDgAAAA==.Zuufungo:BAAALgAECgUJBQABLgAECgkJLAAdAMYhAA==.',
['Zí']='Zíx:BAABLgAECn8oAAIhAAkJThLbFACMAQAhAAkJThLbFACMAQAAAA==.',
['Àl']='Àlcàrà:BAABLgAECn8YAAMKAAcJCg/XIwAZAQAKAAcJCg/XIwAZAQAXAAEJDgptIQEzAAAAAA==.',
['Ål']='Åldaren:BAAALgADCgQJBAAAAA==.',
['Ÿa']='Ÿamar:BAAALgADCgMJAwAAAA==.',
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
