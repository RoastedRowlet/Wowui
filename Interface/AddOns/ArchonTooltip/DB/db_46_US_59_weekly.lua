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

local lookup = {'Druid-Restoration','Mage-Frost','Hunter-BeastMastery','Unknown-Unknown','Paladin-Retribution','Druid-Balance','Warrior-Protection','Warrior-Fury','Monk-Mistweaver','Warrior-Arms','Shaman-Elemental','Shaman-Restoration','Paladin-Holy','Paladin-Protection','Priest-Discipline','Priest-Shadow','Shaman-Enhancement','Warlock-Destruction','Warlock-Demonology','Monk-Brewmaster','Hunter-Survival','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Rogue-Assassination','Rogue-Subtlety','Druid-Feral','Priest-Holy','DemonHunter-Devourer','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Havoc','Hunter-Marksmanship','Mage-Arcane','Warlock-Affliction','DemonHunter-Vengeance','Druid-Guardian',}
local provider = {region='US',realm='DarkIron',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aanx:BAAALgAECgYJEwAAAA==.',
Ab='Abadon:BAAALgAECgQJBgABLgAECgkJGQABAMQaAA==.Abdorei:BAABLgAECn8hAAICAAgJhhXESAC+AQACAAgJhhXESAC+AQAAAA==.Absorboat:BAAALgADCgYJCAAAAA==.',
Ac='Accilatem:BAABLgAECn8UAAIDAAcJJR0nHgBRAgADAAcJJR0nHgBRAgABLgAECgkJGQACAHQRAA==.Accilatim:BAABLgAECn8ZAAICAAkJdBGeOQDxAQACAAkJdBGeOQDxAQAAAA==.',
Ad='Adonsina:BAAALgAECgEJAQABLgAECgkJCwAEAAAAAA==.',
Ag='Agrromagnet:BAABLgAECn8oAAIFAAkJahgmMgDwAQAFAAkJahgmMgDwAQAAAA==.',
Ai='Aiba:BAABLgAECn8ZAAIGAAgJ1hcNFADeAQAGAAgJ1hcNFADeAQAAAA==.',
Ak='Akcloud:BAABLgAFFH8FAAMHAAMJZBXvEgC/AAAHAAMJtBDvEgC/AAAIAAEJ2yPTHQBoAAAAAA==.',
Al='Alaeris:BAACLgAFFH8FAAIJAAIJuhhWJACVAAAJAAIJuhhWJACVAAAuAAQKfyAAAgkACAlPH9wJAJkCAAkACAlPH9wJAJkCAAAA.Albetabeef:BAACLgAFFH8JAAMKAAQJGxSECQA5AQAKAAQJGxSECQA5AQAIAAIJJgZQHACUAAAuAAQKfxgAAwoACAkAIQ8GAFICAAgABwk2ICAWAJwCAAoABwmkIg8GAFICAAAA.Alexei:BAAALgAECgkJAQAAAA==.Aleyeah:BAAALgAECgIJBAABLgAECggJLAALADcfAA==.Allhopeisded:BAABLgAECn8VAAIMAAYJ3w7NVQD1AAAMAAYJ3w7NVQD1AAAAAA==.Alurelor:BAAALgAECgcJBAAAAA==.',
Am='Amarah:BAAALgADCgYJBgAAAA==.Amelaista:BAABLgAECn8sAAIMAAgJ9wuiPgBRAQAMAAgJ9wuiPgBRAQAAAA==.',
An='Anddi:BAAALgAECgEJAwAAAA==.Andii:BAABLgAECn8YAAQNAAgJyBfFLwBKAQANAAcJ0BbFLwBKAQAFAAIJtgf4SQEvAAAOAAEJAAA4RwAAAAAAAA==.Andy:BAACLgAFFH8FAAIPAAMJHgoCIADPAAAPAAMJHgoCIADPAAAuAAQKfxQAAw8ACAkoH8AGAMcCAA8ACAkoH8AGAMcCABAAAQkXB5tmAC0AAAAA.Angusbeef:BAAALgADCgQJBAAAAA==.',
Ao='Aoibhoker:BAAALgAECgQJBAABLgAECgkJLQARADkhAA==.',
Ar='Arclo:BAAALgADCgYJBgAAAA==.Arden:BAAALgAECgQJBAABLgAECgYJFwASANsWAA==.Ardeno:BAABLgAECn8XAAMSAAYJ2xarIwA7AQASAAYJbwyrIwA7AQATAAUJ2xZ5dQASAQAAAA==.Ardon:BAABLgAECn8oAAMMAAkJzhjyDwCAAgAMAAkJzhjyDwCAAgALAAUJvhsbMQCaAQAAAA==.Armis:BAAALgADCgUJBQAAAA==.',
As='Asteruis:BAABLgAECn8kAAIDAAkJDh5gFgBXAgADAAkJDh5gFgBXAgAAAA==.',
Av='Avenayra:BAAALgAECgIJAwAAAA==.',
Ba='Baddhealer:BAAALgADCgUJBQAAAA==.Badfurion:BAAALgADCggJCgAAAA==.Balthamel:BAAALgAECgYJDAAAAA==.Bananafang:BAAALgAECgQJBgAAAA==.Bananashoes:BAAALgAECgMJAgAAAA==.Bangerz:BAACLgAFFH8oAAINAAcJExEIBgDyAQANAAcJExEIBgDyAQAuAAQKfzUAAw0ACQl1H7MIAOMCAA0ACQl1H7MIAOMCAAUAAQm4AedYASYAAAAA.Barkendremix:BAABLgAECn8oAAIUAAkJhRZODwAJAgAUAAkJhRZODwAJAgAAAA==.Bathsheber:BAAALgAECgIJAgABLgAFFAYJEwACADwhAA==.',
Be='Beanieweenie:BAAALgADCgEJAQAAAA==.Beerez:BAAALgADCgcJDQAAAA==.Belroy:BAABLgAECn8YAAIVAAYJpw1eJgAXAQAVAAYJpw1eJgAXAQAAAA==.',
Bj='Bjorum:BAACLgAFFH8GAAIRAAMJsR2WBQAKAQARAAMJsR2WBQAKAQAuAAQKfyAAAxEACAkpIrkEAMkCABEACAkpIrkEAMkCAAsAAQnhCLaQACcAAAAA.',
Bo='Bodytwodafa:BAACLgAFFH8HAAIWAAMJqxBpBADwAAAWAAMJqxBpBADwAAAuAAQKfyAABBYACAntIBgGAJUCABYACAkhHhgGAJUCABcABgn4GMUMALwBABgABwlsGKIfAIoBAAAA.Bournemaad:BAAALgADCgMJAwAAAA==.Boyafu:BAAALgAECgEJAQAAAA==.',
Br='Brucecampbel:BAAALgAECgMJCQAAAA==.',
Bu='Bubbleyou:BAAALgAECgYJDwAAAA==.Burnek:BAAALgAECgIJAgABLgAECgUJDgAEAAAAAA==.',
Ca='Cantarella:BAABLgAECn8ZAAMZAAgJWgOEEQDHAAAaAAgJFwPMKgDkAAAZAAcJ2AKEEQDHAAAAAA==.Carlyle:BAABLgAECn8cAAMFAAgJlRbdbwCdAQAFAAgJlRbdbwCdAQANAAEJPR28ZgBJAAAAAA==.Catdaddy:BAAALgADCgYJBwAAAA==.',
Ch='Checkmybio:BAAALgAECgQJBQAAAA==.Cheesecake:BAAALgADCgUJBQAAAA==.Chromehound:BAAALgADCgQJBAAAAA==.Chumdungler:BAAALgAECgMJAwAAAA==.',
Ci='Cindervis:BAAALgADCgYJBgAAAA==.',
Cl='Clonk:BAAALgAECgUJBQAAAA==.',
Co='Collossuss:BAAALgAECgYJEgAAAA==.Convik:BAAALgAECgcJBwAAAA==.',
Cr='Cregga:BAAALgADCgEJAQAAAA==.Crimsonagony:BAAALgADCgUJBQAAAA==.Crosshairs:BAAALgADCgMJAwAAAA==.',
Cu='Cuddles:BAAALgADCgUJBQAAAA==.Curacao:BAABLgAECn8YAAIIAAcJAhT9KABmAQAIAAcJAhT9KABmAQAAAA==.',
Cy='Cynnari:BAAALgAECgYJDQAAAA==.',
Da='Dabtime:BAABLgAECn8gAAIFAAcJHxbacgCWAQAFAAcJHxbacgCWAQAAAA==.Darkstarr:BAAALgADCgUJBgAAAA==.',
De='Deathknightm:BAAALgAECgIJAgABLgAECgkJHAAHAHQVAA==.Dekaar:BAABLgAECn8aAAIbAAYJuwkMGQDfAAAbAAYJuwkMGQDfAAAAAA==.Demonknight:BAAALgAECgEJAQAAAA==.Deracine:BAAALgAECgcJCgAAAA==.Desdemonica:BAAALgAECgYJDwAAAA==.',
Di='Diegoknight:BAAALgADCgEJAgAAAA==.Diggle:BAAALgADCggJCAAAAA==.Dilvdrood:BAAALgADCgUJBQAAAA==.Dilvish:BAAALgAECgYJEgAAAA==.',
Do='Doctrwho:BAAALgADCgIJAgAAAA==.Dohaeris:BAABLgAECn8yAAIcAAkJ9xN1EwD0AQAcAAkJ9xN1EwD0AQAAAA==.Domain:BAABLgAECn8eAAIdAAgJThi2KgDVAQAdAAgJThi2KgDVAQAAAA==.Donfalprun:BAABLgAECn8eAAIFAAkJ3yJiBgANAwAFAAkJ3yJiBgANAwAAAA==.Doomstout:BAAALgAECgkJEAAAAA==.',
Dr='Draconus:BAABLgAECn8sAAMeAAkJxRLqEgCLAQAeAAkJiA7qEgCLAQAfAAQJcRs/qQDQAAAAAA==.Dralas:BAAALgAECgEJAwAAAA==.',
Du='Duro:BAAALgAECgYJDAABLgAECgYJDAAEAAAAAA==.Durto:BAAALgADCgMJAwABLgAECgQJCAAEAAAAAA==.Duskshade:BAAALgADCggJDwAAAA==.',
['Dü']='Düsk:BAAALgAECgEJAQAAAA==.',
El='Elij:BAABLgAECn8fAAITAAgJiR4EFAB2AgATAAgJiR4EFAB2AgAAAA==.Elunaire:BAABLgAECn8ZAAIBAAkJxBqSHQBRAgABAAkJxBqSHQBRAgAAAA==.',
Em='Emelec:BAAALgAECgIJAgAAAA==.Emeraldwish:BAACLgAFFH8HAAIBAAMJHCPfGgAmAQABAAMJHCPfGgAmAQAuAAQKfxwAAgEACAmlI2sGACUDAAEACAmlI2sGACUDAAAA.',
Er='Erthnite:BAAALgAECgQJBAAAAA==.',
Ev='Evinco:BAABLgAECn8VAAISAAgJGw91JAA3AQASAAgJGw91JAA3AQAAAA==.Evy:BAAALgAECgEJAgAAAA==.',
Ex='Executie:BAACLgAFFH8UAAMKAAYJLRGbBQB3AQAKAAYJAxGbBQB3AQAIAAMJGQzSEgDvAAAuAAQKfyIAAwoACQnCG3gGAGQCAAoACQmOGngGAGQCAAgABglLHFw1ANQBAAAA.',
Fa='Falin:BAAALgAECgEJAQAAAA==.',
Fe='Fey:BAABLgAECn8iAAITAAkJ5BMQMQDVAQATAAkJ5BMQMQDVAQAAAA==.',
Fi='Fieryember:BAAALgAECgQJBQABLgAECgUJDgAEAAAAAA==.Fistvendor:BAAALgAECgkJEAAAAA==.',
Fl='Flasheals:BAABLgAECn8oAAINAAgJBxIFJACaAQANAAgJBxIFJACaAQAAAA==.Flatpak:BAAALgADCgEJAgAAAA==.Flobglop:BAAALgAECgEJAQAAAA==.Fluffybum:BAAALgADCgEJAQAAAA==.',
Fo='Foxtrot:BAABLgAECn8ZAAIDAAgJGxYxKQDpAQADAAgJGxYxKQDpAQAAAA==.',
Fr='Frostine:BAABLgAECn8VAAICAAcJ7gZC1QBEAQACAAcJ7gZC1QBEAQAAAA==.Frostwave:BAABLgAECn8uAAMgAAgJJB+cBAAKAgAgAAgJEx2cBAAKAgAeAAgJYxDwFwBLAQAAAA==.Frostythot:BAAALgADCgIJAgAAAA==.',
Fu='Fujiyama:BAABLgAECn8sAAILAAgJNx84DABXAgALAAgJNx84DABXAgAAAA==.Furryweasal:BAAALgADCgEJAQAAAA==.',
Ga='Garrex:BAAALgADCgUJBQABLgAECggJFQADAMUWAA==.Garréosh:BAAALgAECgUJCgABLgAFFAIJCAAFAGwVAA==.',
Ge='Geodude:BAAALgADCgYJBwAAAA==.',
Gi='Gibborim:BAAALgAECgYJCwAAAA==.Gigilomann:BAAALgAECgIJAgAAAA==.',
Gl='Glenndanzig:BAAALgADCgYJBgAAAA==.',
Go='Goldenshield:BAAALgAECgMJCQAAAA==.Golteb:BAAALgAECgQJBAAAAA==.Gonecrazy:BAAALgADCgMJAwAAAA==.Gorthan:BAAALgADCgQJBgAAAA==.',
Gr='Grabandgank:BAAALgADCgYJBgAAAA==.',
Gu='Guaresux:BAEALgADCgEJAQABLgAECggJEgAEAAAAAA==.Gurnisson:BAAALgADCgUJBQAAAA==.Gusto:BAABLgAECn8uAAQYAAkJ6AsgIgB3AQAYAAkJXQsgIgB3AQAXAAgJegPzFwAHAQAWAAcJwQeNDwDMAAAAAA==.',
Ha='Hadouken:BAAALgAECgkJCwAAAA==.Halppme:BAAALgADCgcJBwAAAA==.Hammerfall:BAAALgAECgQJBAAAAA==.Handsome:BAAALgAECgcJBwAAAA==.',
He='Headshotte:BAAALgAECgYJDAAAAA==.Heatindabs:BAABLgAECn8gAAIBAAkJpQ6AOQBoAQABAAkJpQ6AOQBoAQAAAA==.Hexed:BAAALgAECgQJBgAAAA==.',
Hi='Hinael:BAAALgAECgEJAQAAAA==.',
Ho='Holyknight:BAAALgAECgYJCQAAAA==.Holymama:BAABLgAECn8gAAMQAAgJch2rDwARAgAQAAcJbCCrDwARAgAPAAIJIxOVRAB3AAAAAA==.',
Hu='Hunkwai:BAAALgAFFAIJAgAAAA==.',
Ib='Ibok:BAAALgAECgYJCgAAAA==.',
Ic='Ickma:BAABLgAECn8wAAIfAAgJfR7YLgD8AQAfAAgJfR7YLgD8AQAAAA==.',
Id='Iddou:BAAALgAECgMJBAAAAA==.',
Ik='Ikona:BAAALgADCggJDgAAAA==.',
Im='Impgobrr:BAAALgAECgEJAQAAAA==.Imu:BAAALgADCggJDQAAAA==.',
In='Incubus:BAAALgADCgEJAgAAAA==.Infari:BAAALgAECgQJBAAAAA==.',
Ir='Irdeldran:BAAALgAECgEJAQAAAA==.',
Ja='Jabjek:BAAALgADCgYJCAAAAA==.Jamaz:BAAALgAECgQJBAAAAA==.Jamwich:BAAALgADCgYJBgAAAA==.Jasonmoloa:BAAALgAECgYJDgAAAA==.',
Je='Jerazia:BAAALgAECgYJBAAAAA==.',
Jo='Johanx:BAAALgADCgMJAwAAAA==.Jordananon:BAAALgADCgIJAgAAAA==.Jordanian:BAAALgAECgMJAwAAAA==.',
['Jî']='Jînxy:BAAALgAECgEJAgAAAA==.',
Ka='Kaollanna:BAABLgAECn8jAAICAAkJDhYdRgDGAQACAAkJDhYdRgDGAQAAAA==.Karik:BAAALgAECgMJAwAAAA==.Kaven:BAAALgADCgIJAgAAAA==.',
Ke='Kehma:BAAALgAECgEJAQAAAA==.Kelisa:BAABLgAECn8nAAIFAAkJPh1NFACNAgAFAAkJPh1NFACNAgAAAA==.Ketchuptits:BAAALgADCgYJBgAAAA==.',
Ki='Kimjunggheal:BAAALgAECgMJBgAAAA==.Kinkster:BAAALgAECgYJCwABLgAECgYJDQAEAAAAAA==.Kiwidin:BAABLgAECn8aAAINAAgJABbmJgDzAQANAAgJABbmJgDzAQAAAA==.',
Kr='Krinxy:BAABLgAECn8VAAIBAAUJFhqSWwA/AQABAAUJFhqSWwA/AQAAAA==.',
Ks='Kschwev:BAAALgADCgYJBgAAAA==.',
Ku='Kuratcha:BAAALgAECgUJCgABLgAECgUJDgAEAAAAAA==.',
Ky='Kylee:BAAALgAECgkJAQAAAA==.Kyý:BAAALgAECgYJDwAAAA==.',
['Kí']='Kíng:BAAALgAECgUJBwABLgAECgUJDgAEAAAAAA==.',
Le='Ledgerfeign:BAABLgAECn8bAAITAAkJtwlWTAB3AQATAAkJtwlWTAB3AQAAAA==.',
Li='Liadan:BAAALgAECgYJCwAAAA==.Lighteye:BAABLgAECn8wAAIBAAgJURfDGwAfAgABAAgJURfDGwAfAgAAAA==.Lilmudatruka:BAAALgADCgEJAQABLgAECgYJFQAMAN8OAA==.',
Lo='Longestibrow:BAAALgAECgMJBQAAAA==.',
Lu='Luminescence:BAAALgADCgQJBgAAAA==.Lunarqt:BAAALgAECgEJAQAAAA==.Lunchy:BAAALgAECgYJCQAAAA==.',
Ly='Lyllow:BAABLgAECn8UAAIXAAYJDhN2FAA4AQAXAAYJDhN2FAA4AQAAAA==.',
['Lø']='Løurent:BAAALgADCgQJBAAAAA==.',
Ma='Magicdorf:BAABLgAECn8oAAICAAgJ7iD6HgBoAgACAAgJ7iD6HgBoAgAAAA==.Malphasia:BAAALgADCgYJBgAAAA==.Manhitrogue:BAAALgAECgQJBAAAAA==.Massivebicep:BAAALgAECgIJAgAAAA==.Mavras:BAAALgADCgEJAQAAAA==.Maxso:BAAALgAECgkJAQAAAA==.',
Mc='Mcsleuth:BAAALgAECgQJBgAAAA==.',
Me='Megarayquaza:BAACLgAFFH8FAAIdAAMJ9AOKSwCxAAAdAAMJ9AOKSwCxAAAuAAQKfx8AAyEACAkpEmseAMwBACEACAnIC2seAMwBAB0ACAkzERBGAGUBAAAA.',
Mi='Mikeyouk:BAAALgADCgYJBgAAAA==.Misties:BAAALgAECgEJAQAAAA==.',
Mo='Moargoth:BAAALgADCgUJEAAAAA==.Mooneater:BAAALgAECgYJCAAAAA==.Mordorl:BAAALgADCgcJBwAAAA==.',
Mt='Mtt:BAAALgADCgkJDgAAAA==.',
Mx='Mxx:BAABLgAECn8UAAQDAAUJjR29TQCAAQADAAUJVB29TQCAAQAVAAMJMxSdOgB/AAAiAAEJzAMGlgAjAAAAAA==.',
My='Mylianne:BAABLgAECn8aAAIGAAcJYxwmEwDoAQAGAAcJYxwmEwDoAQAAAA==.Mynameiscole:BAACLgAFFH8IAAIhAAQJgh98AQCSAQAhAAQJgh98AQCSAQAuAAQKfyIAAiEACAmZJq4BAIoDACEACAmZJq4BAIoDAAAA.Myrolan:BAABLgAECn8sAAIhAAkJCCQlAQBCAwAhAAkJCCQlAQBCAwAAAA==.Myrtru:BAAALgADCgkJHwAAAA==.',
['Mí']='Míyagi:BAAALgAECgYJBgAAAA==.',
Na='Naturallight:BAAALgADCgUJCAAAAA==.',
Ne='Neechka:BAAALgADCgUJBQAAAA==.Neosan:BAAALgADCgYJBgABLgAFFAMJCgAGAOciAA==.Nevyn:BAABLgAECn8dAAIjAAcJJxKgBABiAQAjAAcJJxKgBABiAQAAAA==.Newface:BAAALgADCgEJAgAAAA==.Newmoo:BAAALgAECgEJAQAAAA==.',
Ni='Nightsage:BAAALgAECgQJBAAAAA==.Niji:BAAALgAECgIJBAABLgAECggJGQAGANYXAA==.Nininhp:BAAALgAECgQJBQABLgAECgYJEAAEAAAAAA==.Nithari:BAABLgAECn8uAAICAAgJJSGWGQCHAgACAAgJJSGWGQCHAgAAAA==.',
No='Nobel:BAAALgADCgEJAQAAAA==.Nomanai:BAAALgADCgkJAwAAAA==.Nosst:BAAALgAECgMJBQAAAA==.Nost:BAAALgADCgcJBwAAAA==.Nostu:BAABLgAECn8hAAMPAAkJsBbqDQA4AgAPAAkJsBbqDQA4AgAQAAEJbhDyXQA4AAAAAA==.Now:BAACLgAFFH8HAAIFAAMJEhw7MwAOAQAFAAMJEhw7MwAOAQAuAAQKfx8AAwUACAkQIOAtAGsCAAUACAlPHuAtAGsCAA4ABgmIFysTAD4BAAAA.',
Nu='Nukum:BAAALgAECgYJEAAAAA==.',
Oh='Ohpa:BAABLgAECn8WAAMTAAgJzBBjQwCSAQATAAgJzBBjQwCSAQAkAAIJUQkCJwAxAAAAAA==.Ohrly:BAAALgAECgEJAQAAAA==.',
Oj='Ojikan:BAABLgAECn8WAAIbAAgJvSKkAwD2AgAbAAgJvSKkAwD2AgAAAA==.',
Pa='Papamush:BAAALgAECgMJBQAAAA==.Pathogenn:BAAALgAECgYJDwAAAA==.',
Pe='Pepecry:BAAALgAECgUJDgAAAA==.',
Ph='Phoblade:BAABLgAECn8ZAAIfAAgJFhUyQAC8AQAfAAgJFhUyQAC8AQAAAA==.Phokk:BAAALgAECgcJBwAAAA==.',
Pi='Pirotess:BAAALgAECgYJDgAAAA==.',
Po='Ponylion:BAAALgAECgYJCwABLgAECgcJEQAEAAAAAA==.Pooshka:BAABLgAECn8dAAILAAkJSCJiCgDvAgALAAkJSCJiCgDvAgAAAA==.Popz:BAAALgAECgEJAQAAAA==.',
Pr='Preorcthego:BAACLgAFFH8TAAIVAAQJwiaaAQDLAQAVAAQJwiaaAQDLAQAuAAQKfykAAxUACAlqJpcAAIsDABUACAlqJpcAAIsDACIAAQm/JHV7AFUAAAEuAAUUBQkQAB8ASyEA.Presibro:BAAALgAECgYJDQAAAA==.Presiric:BAAALgAECgMJAwAAAA==.Presisarian:BAAALgAECgUJDgAAAA==.',
Pu='Puck:BAAALgAECgYJDQAAAA==.Puppye:BAACLgAFFH8GAAIDAAMJ2RbaMQD3AAADAAMJ2RbaMQD3AAAuAAQKfxUAAgMACAlNG+kkAP4BAAMACAlNG+kkAP4BAAAA.',
Ra='Ranouu:BAABLgAECn8VAAICAAYJIBW8nACcAQACAAYJIBW8nACcAQAAAA==.Ratatatatt:BAAALgADCgQJBQAAAA==.',
Re='Reaoibher:BAAALgADCgMJAwABLgAECgkJLQARADkhAA==.Recision:BAABLgAECn8wAAIlAAgJviI6AgCdAgAlAAgJviI6AgCdAgAAAA==.Reeash:BAABLgAECn8XAAMMAAkJABc8FwA8AgAMAAkJABc8FwA8AgALAAMJyAsIWACBAAAAAA==.Reeatar:BAAALgAECgYJEwABLgAECgkJFwAMAAAXAA==.Relindor:BAAALgADCgYJBgABLgAFFAQJCAAfAJwSAA==.Revelle:BAAALgAECgkJCwAAAA==.',
Rh='Rheizen:BAABLgAECn8fAAIHAAYJeA+GIADgAAAHAAYJeA+GIADgAAAAAA==.',
Ro='Ron:BAAALgADCgQJBAAAAA==.Ropopo:BAABLgAECn8bAAIPAAgJtxkEEAAYAgAPAAgJtxkEEAAYAgABLgAFFAMJBgADANkWAA==.',
Ru='Runcat:BAABLgAECn8XAAMdAAgJQB58GABBAgAdAAgJQB58GABBAgAlAAQJ1QYdGQCHAAAAAA==.',
['Rö']='Röyksopp:BAAALgAECggJEQAAAA==.',
Sa='Sabo:BAAALgADCgQJBQAAAA==.Sakona:BAAALgADCgEJAQAAAA==.Samarah:BAAALgAECgQJAQAAAA==.Sandewor:BAAALgAECgYJDgABLgAECgYJFQAVAPwMAA==.Sanfrancisco:BAAALgAECgIJAwABLgAECgIJAgAEAAAAAA==.Sarafyn:BAABLgAECn8uAAIcAAgJnBb1FQDYAQAcAAgJnBb1FQDYAQAAAA==.Sauceguzzler:BAAALgAECgYJBgAAAA==.Savath:BAAALgADCgYJBgAAAA==.',
Se='Selenagomes:BAAALgAECgEJAQABLgAFFAQJCAAhAIIfAA==.Selenor:BAAALgAECgQJBwAAAA==.Seragaki:BAABLgAECn8aAAIPAAcJsRt0EAASAgAPAAcJsRt0EAASAgAAAA==.Seraphinna:BAAALgADCgEJAQAAAA==.',
Si='Siegrorc:BAABLgAECn8oAAIHAAgJrQ7DFgA8AQAHAAgJrQ7DFgA8AQAAAA==.Sillidari:BAAALgADCgQJBwAAAA==.Sionshope:BAAALgAECgUJCQAAAA==.',
Sk='Skragar:BAAALgAECgEJAgAAAA==.',
Sl='Slayerhunt:BAABLgAECn8VAAQVAAYJ/AzgIwArAQAVAAYJ2wvgIwArAQADAAQJywvegQDiAAAiAAIJqQwGeABgAAAAAA==.Slayertin:BAAALgAECgYJBwABLgAECgYJFQAVAPwMAA==.',
Sn='Snibdru:BAAALgAECgcJBgAAAA==.Snkrsotoole:BAABLgAECn8XAAILAAYJgw4ePwDeAAALAAYJgw4ePwDeAAAAAA==.',
So='Soobz:BAAALgADCgYJBgAAAA==.Sorian:BAAALgAECgQJBAAAAA==.Soulkings:BAAALgADCggJDwAAAA==.Soupies:BAAALgAECgEJAQAAAA==.Soxa:BAAALgADCgIJAgAAAA==.',
Sp='Spiikee:BAAALgADCgQJBAAAAA==.Sprays:BAAALgAECgQJBAAAAA==.',
Sr='Sry:BAAALgAECgQJBAAAAA==.',
St='Steady:BAAALgAFFAEJAQAAAA==.Stonehand:BAABLgAECn8kAAIQAAkJVxJwFADaAQAQAAkJVxJwFADaAQAAAA==.Stormsurge:BAAALgAECgMJAwAAAA==.Stownt:BAAALgADCgMJAwAAAA==.Stravas:BAAALgAECgcJBwAAAA==.Strongbow:BAAALgADCggJEQAAAA==.',
Su='Subudai:BAAALgAECgkJEAAAAA==.Sugarboi:BAABLgAECn8oAAImAAkJ2ggCGgD/AAAmAAkJ2ggCGgD/AAAAAA==.Sugasuga:BAAALgAECgcJCwAAAA==.Sunnymuffins:BAAALgADCgYJBQAAAA==.',
Sv='Sveetka:BAAALgAECgMJBAAAAA==.',
Sx='Sxytrev:BAAALgAECgQJCQAAAA==.',
Ta='Tabi:BAAALgADCgQJBgAAAA==.Tacoy:BAABLgAECn8bAAIIAAgJxRYvHwCmAQAIAAgJxRYvHwCmAQAAAA==.Tagsy:BAABLgAECn8VAAIDAAgJxRZdOQDJAQADAAgJxRZdOQDJAQAAAA==.Tay:BAAALgAECgYJBQAAAA==.Tayna:BAAALgADCgYJBgAAAA==.',
Tb='Tbizkut:BAABLgAECn8wAAISAAgJjw8jCgBQAQASAAgJjw8jCgBQAQAAAA==.',
Th='Then:BAABLgAECn8iAAICAAcJSBnfUACnAQACAAcJSBnfUACnAQAAAA==.Threetimez:BAAALgAECgYJDAAAAA==.Thumbmage:BAAALgAECgIJAgABLgAECgkJOAALAKclAA==.',
Ti='Timemaster:BAABLgAECn8ZAAMhAAYJyBdgGQBNAQAhAAYJyBdgGQBNAQAdAAIJnQMT1wBCAAAAAA==.Timepacifist:BAAALgAECgQJBAAAAA==.',
To='Tokido:BAAALgAFFAEJAQAAAA==.Tongpakfu:BAAALgAECgMJEQAAAA==.Topflight:BAAALgAECgcJEgAAAA==.',
Tr='Triggered:BAABLgAECn8bAAMFAAgJVBeZUQDsAQAFAAgJVBeZUQDsAQANAAEJ0AqlngAqAAAAAA==.Troiikâ:BAABLgAECn80AAQOAAkJpRQEEADFAQAOAAkJpRQEEADFAQAFAAcJNgcGjAANAQANAAUJ8QImVACKAAAAAA==.Troikâ:BAAALgADCgYJBwAAAA==.Trroikâ:BAABLgAECn8hAAIHAAgJuw8OGAAuAQAHAAgJuw8OGAAuAQAAAA==.',
Tt='Tteeffinn:BAAALgADCgYJBgAAAA==.Ttevinn:BAAALgAECgMJBAABLgAECgQJBAAEAAAAAA==.Ttevoker:BAAALgAECgQJBAAAAA==.',
Tu='Tulvie:BAAALgADCgQJCAAAAA==.Tupacaroni:BAAALgAECgMJAwAAAA==.',
Ty='Tycone:BAAALgAECgcJCgAAAA==.',
Ul='Uldirtydruid:BAABLgAECn8eAAIBAAgJehuXEgB0AgABAAgJehuXEgB0AgAAAA==.',
Ur='Urukdrak:BAABLgAECn8kAAMVAAkJJw3bFAC0AQAVAAkJkAnbFAC0AQAiAAgJhw3iMwCcAQAAAA==.',
Uw='Uwantwar:BAAALgAECgUJCAAAAA==.',
Va='Valanquishy:BAAALgADCgEJAgAAAA==.',
Ve='Velaryon:BAAALgAECgQJBAAAAA==.',
Vh='Vhagar:BAAALgAECgIJAwAAAA==.',
Vi='Vidich:BAAALgAECgQJBwAAAA==.Viralus:BAAALgADCgEJAQAAAA==.',
Vo='Vodka:BAAALgAECgEJAgAAAA==.Voiddastard:BAAALgADCgkJFwAAAA==.Voidlight:BAAALgADCgcJBwAAAA==.Volcazzic:BAAALgADCgIJAgAAAA==.',
Vy='Vynnara:BAAALgADCgMJAQAAAA==.',
Wa='Wakkaba:BAAALgADCgYJBgAAAA==.Wanaatlarboy:BAABLgAECn8UAAMQAAYJSBLiKwAhAQAQAAYJSBLiKwAhAQAPAAEJ7gH4XgAiAAAAAA==.Waywyrd:BAAALgADCgMJAwAAAA==.',
Wh='Whack:BAAALgADCgcJCAAAAA==.',
Wi='Willowëd:BAAALgAECgkJAQAAAA==.',
Wu='Wunderbar:BAABLgAECn8eAAIMAAYJKxspNACDAQAMAAYJKxspNACDAQAAAA==.Wunderburger:BAAALgAECgYJEQAAAA==.Wunderground:BAAALgAECgQJCAAAAA==.',
Xa='Xannada:BAABLgAECn8pAAIFAAgJiAnddwAyAQAFAAgJiAnddwAyAQAAAA==.',
Ya='Yaoli:BAAALgAECgMJBAAAAA==.',
Ye='Yea:BAAALgADCgcJCwAAAA==.',
Yo='Yodadogownz:BAABLgAECn8MAAIQAAYJZwyrOQDXAAAQAAYJZwyrOQDXAAAAAA==.Yoh:BAACLgAFFH8HAAIfAAMJIQb3bgDVAAAfAAMJIQb3bgDVAAAuAAQKfxwAAh8ACAlKHYMrAAsCAB8ACAlKHYMrAAsCAAAA.Yourenotron:BAAALgADCgYJBgAAAA==.',
Yu='Yungdro:BAAALgAECgEJAQAAAA==.',
Za='Zarutobi:BAAALgAECgYJEgABLgAECggJGQAGANYXAA==.',
Zo='Zob:BAAALgADCgQJBAAAAA==.',
Zu='Zui:BAABLgAECn8lAAIUAAkJ7hExFADQAQAUAAkJ7hExFADQAQAAAA==.',
['Zù']='Zùg:BAAALgADCgIJAQAAAA==.',
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
