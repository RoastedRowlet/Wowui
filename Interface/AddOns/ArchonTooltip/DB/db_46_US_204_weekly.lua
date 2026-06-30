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

local lookup = {'Hunter-BeastMastery','Druid-Restoration','Hunter-Marksmanship','Monk-Brewmaster','Monk-Windwalker','Hunter-Survival','Unknown-Unknown','Warlock-Destruction','Warlock-Demonology','Priest-Shadow','Warrior-Fury','DemonHunter-Devourer','Warrior-Arms','Warrior-Protection','Paladin-Holy','Paladin-Protection','DeathKnight-Unholy','Mage-Frost','Shaman-Elemental','Shaman-Restoration','Evoker-Augmentation','Evoker-Devastation','Druid-Balance','Paladin-Retribution','Priest-Discipline','Priest-Holy','DeathKnight-Blood','Warlock-Affliction','Monk-Mistweaver','Rogue-Outlaw','Druid-Guardian','Druid-Feral','DeathKnight-Frost','Mage-Fire','DemonHunter-Havoc','DemonHunter-Vengeance','Rogue-Assassination','Rogue-Subtlety',}
local provider = {region='US',realm='SteamwheedleCartel',name='US',type='weekly',zone=46,date='2026-06-27',data={Aa='Aalwein:BAABLgAECn8rAAIBAAkJsx8EGwCDAgABAAkJsx8EGwCDAgAAAA==.',
Ae='Aesculapius:BAACLgAFFH8LAAICAAMJRwexTACLAAACAAMJRwexTACLAAAuAAQKfzMAAgIACQmKGf8UAKICAAIACQmKGf8UAKICAAAA.',
Al='Aladia:BAAALgADCgMJAgAAAA==.Aloisious:BAAALgAECgEJAQAAAA==.',
Am='Amarii:BAABLgAECn82AAIDAAkJtQ2sAACEAQADAAkJtQ2sAACEAQAAAA==.Amorash:BAAALgADCgEJAQAAAA==.',
An='Annabeth:BAAALgAECgYJCwABLgAFFAMJCQAEANAaAA==.Anonymus:BAACLgAFFH8JAAIEAAMJ0BoMLAD5AAAEAAMJ0BoMLAD5AAAuAAQKfxgAAwQACQlKHd8PAD8CAAQACAksHt8PAD8CAAUAAgmiEJmKAEcAAAAA.',
Ar='Ara:BAACLgAFFH8MAAMBAAQJlBEGQQArAQABAAQJlBEGQQArAQAGAAEJiQNeNABBAAAuAAQKfy4AAgEACQmhIHYPANUCAAEACQmhIHYPANUCAAAA.Ardiir:BAAALgAECgEJAgABLgAECgQJDQAHAAAAAA==.Ardwin:BAAALgADCgEJAQABLgAECgYJGQAIAHkIAA==.',
As='Ashgrove:BAAALgAECgUJCAAAAA==.',
Av='Avigar:BAAALgADCgEJAwAAAA==.',
Az='Azzinoth:BAAALgAECgIJAgAAAA==.',
Ba='Bakeneko:BAAALgADCgMJBgAAAA==.Bambarrok:BAABLgAECn8XAAIJAAkJSQbgfQA9AQAJAAkJSQbgfQA9AQAAAA==.Bangan:BAAALgAFFAIJAgAAAA==.',
Be='Belakor:BAAALgAECgYJBgAAAA==.Bep:BAAALgAECgYJDAABLgAECgkJGgAIADEVAA==.Bepragosa:BAABLgAECn8aAAIIAAkJMRWkCAA3AgAIAAkJMRWkCAA3AgAAAA==.',
Bi='Binpharteen:BAAALgAECgEJAwAAAA==.',
Bl='Blaque:BAAALgADCgcJBwABLgAECggJFQAKABoMAA==.Blindfaith:BAAALgADCgEJAQAAAA==.',
Br='Brimscythe:BAAALgAECgEJAgABLgAECgkJJAAFAIcfAA==.Brownbelt:BAACLgAFFH8HAAILAAIJIAivFABxAAALAAIJIAivFABxAAAuAAQKf0oAAgsACQlWHWsLALECAAsACQlWHWsLALECAAAA.Brîn:BAAALgAECgUJCgAAAA==.',
Bu='Buteihunter:BAACLgAFFH8NAAMGAAMJrxzqBwCoAAABAAMJMhzCUgAEAQAGAAIJrhLqBwCoAAAuAAQKfzcABAEACQnLIs8LAPUCAAEACQnLIs8LAPUCAAMAAQnvC0WIADQAAAYAAQkSByxnADAAAAAA.',
Ca='Cadranak:BAABLgAECn8wAAIMAAkJ2RKsQwC9AQAMAAkJ2RKsQwC9AQAAAA==.Caiyenthi:BAABLgAECn8nAAIBAAgJkQ+JZAB8AQABAAgJkQ+JZAB8AQAAAA==.Calliesue:BAAALgAECgIJAgAAAA==.Camgor:BAAALgADCgEJAQABLgAECgYJGQAIAHkIAA==.Carfalis:BAAALgADCggJCQAAAA==.',
Ch='Chelali:BAABLgAECn8XAAQLAAkJ8RVsJQAtAgALAAgJ/BZsJQAtAgANAAUJ5BDILQATAQAOAAEJNAiRUgA0AAAAAA==.Chelly:BAAALgAECgEJAQABLgAECgkJFwALAPEVAA==.Chicharrone:BAAALgAECgYJEgAAAA==.Chihiro:BAAALgADCgYJCAAAAA==.Chizaru:BAACLgAFFH8PAAIPAAQJuRW8IwACAQAPAAQJuRW8IwACAQAuAAQKfyoAAw8ACQlbHpYHABIDAA8ACQlbHpYHABIDABAAAwkyAXdOADUAAAAA.Chlorophyll:BAAALgAECgEJAQAAAA==.Chyntobelt:BAABLgAECn8kAAIRAAcJhAV5yQDxAAARAAcJhAV5yQDxAAABLgAFFAIJBwALACAIAA==.',
Cl='Cleopawtra:BAAALgADCgEJAQAAAA==.',
Co='Copyright:BAAALgAECgEJAQAAAA==.',
Cr='Creep:BAAALgAECgYJEAAAAA==.Cryption:BAABLgAECn8VAAIBAAgJkhQEOADOAQABAAgJkhQEOADOAQAAAA==.',
['Cú']='Cúchulainn:BAAALgAECgYJDQAAAA==.',
Da='Daelyn:BAABLgAECn8ZAAIBAAgJKA0AigArAQABAAgJKA0AigArAQAAAA==.Dalhma:BAAALgAFFAIJAgAAAA==.Dallma:BAAALgAFFAcJCwABLgAFFAIJAgAHAAAAAQ==.Dallmia:BAAALgAFFAMJAwABLgAFFAIJAgAHAAAAAQ==.Dane:BAAALgAECgIJAgAAAA==.Dayaris:BAABLgAECn8jAAIBAAgJXQq4bABoAQABAAgJXQq4bABoAQAAAA==.',
De='Deadbeat:BAAALgAECgUJBgAAAA==.Deafenned:BAABLgAECn8aAAISAAkJdx6gPQCBAgASAAkJdx6gPQCBAgABLgAFFAMJBwAMANEOAA==.Deaflynn:BAAALgAECgEJAwABLgAFFAMJBwAMANEOAA==.Deafnight:BAAALgAECgIJBAABLgAFFAMJBwAMANEOAA==.Deliquesce:BAAALgADCgMJAwAAAA==.Demonbep:BAAALgADCgQJBAABLgAECgkJGgAIADEVAA==.Demonicpower:BAAALgAECgYJCAAAAA==.Derrington:BAABLgAECn8kAAIIAAcJkSGMBAAzAgAIAAcJkSGMBAAzAgABLgAECgkJJAAFAIcfAA==.Destinyetwo:BAAALgAECgEJAQAAAA==.Dett:BAABLgAECn8VAAITAAcJZQiWVgDhAAATAAcJZQiWVgDhAAAAAA==.',
Di='Diamante:BAACLgAFFH8WAAIUAAUJ2hlsHwB3AQAUAAUJ2hlsHwB3AQAuAAQKfyoAAhQACQlBFp4zAOQBABQACQlBFp4zAOQBAAAA.',
Dk='Dkvayce:BAAALgADCgYJBgAAAA==.',
Dr='Dragqueene:BAABLgAFFH8KAAIVAAUJQwXyEgCuAAAVAAUJQwXyEgCuAAAAAA==.Drakluz:BAAALgADCgEJAQAAAA==.Drakner:BAABLgAECn8xAAMVAAgJKw4PNgBYAQAVAAgJKw4PNgBYAQAWAAQJBQJMMgCEAAAAAA==.Drellin:BAAALgAECgEJBAABLgAECgkJJAAFAIcfAA==.Dremu:BAABLgAECn83AAMXAAkJZx84CQC/AgAXAAkJZx84CQC/AgACAAMJEw9doACJAAAAAA==.',
Du='Duraz:BAABLgAECn8jAAICAAkJQg4oSgBmAQACAAkJQg4oSgBmAQAAAA==.',
Dy='Dysraxis:BAAALgADCgEJAQAAAA==.',
Ee='Eerie:BAAALgAECgIJBgAAAA==.',
Eg='Eggar:BAAALgAECggJCQABLgAECgkJMgARAA8YAA==.',
El='Elahna:BAAALgADCgcJDQAAAA==.Elalia:BAABLgAECn8ZAAIIAAYJeQjnHgCzAAAIAAYJeQjnHgCzAAAAAA==.Elamaun:BAABLgAECn9AAAMPAAgJ7RoMFABuAgAPAAgJ7RoMFABuAgAYAAMJQgOiWwFWAAAAAA==.Elereia:BAAALgAECgEJAQAAAA==.Eltiana:BAAALgAECgUJCwAAAA==.',
En='Energy:BAAALgADCgQJBwABLgAFFAMJBwARAH8fAA==.English:BAABLgAECn8VAAIKAAgJGgwINwA5AQAKAAgJGgwINwA5AQAAAA==.',
Ep='Ephex:BAAALgADCgcJGQAAAA==.Ephyiana:BAAALgADCgcJCAAAAA==.Epic:BAAALgAECgYJEQAAAA==.',
Er='Errimys:BAAALgADCgUJBQAAAA==.Ertraz:BAAALgAECgEJAgAAAA==.',
Es='Essense:BAAALgADCgcJBwAAAA==.Esçanor:BAAALgADCgUJBQAAAA==.',
Et='Etania:BAAALgAECgYJCQAAAA==.',
Ev='Evhomang:BAABLgAFFH8KAAIVAAQJ+hiCJgA0AQAVAAQJ+hiCJgA0AQAAAA==.',
Fa='Faelyna:BAABLgAECn9DAAIGAAkJyRJqGADeAQAGAAkJyRJqGADeAQAAAA==.Fang:BAAALgADCgEJAQAAAA==.',
Fe='Fearbear:BAAALgAECgUJBgAAAA==.Felnut:BAAALgADCgEJAQAAAA==.',
Fi='Finniel:BAAALgADCgEJAQAAAA==.',
Fl='Flash:BAAALgADCgMJAQAAAA==.',
Fo='Foix:BAAALgADCgcJDwAAAA==.Fonkymonky:BAAALgAECgEJAQAAAA==.Forged:BAACLgAFFH8JAAIYAAQJxROpawDYAAAYAAQJxROpawDYAAAuAAQKfysAAhgACAnzHxEpAIECABgACAnzHxEpAIECAAAA.',
Ga='Gaerne:BAAALgADCgEJAQAAAA==.Galandrick:BAAALgADCgEJAQAAAA==.',
Gi='Githyanki:BAAALgADCgkJCQAAAA==.',
Gl='Glabberghoul:BAABLgAECn8sAAIVAAkJQhTsIwC9AQAVAAkJQhTsIwC9AQAAAA==.',
Go='Goobagoo:BAAALgADCgQJBAAAAA==.Goodhead:BAAALgADCgMJBAAAAA==.',
Gr='Grangladesh:BAAALgAECgEJAgABLgAECgQJDQAHAAAAAA==.Grangmage:BAAALgAECgQJDQAAAA==.Grimvault:BAAALgAECgEJAQABLgAECgkJJAAFAIcfAA==.Griogair:BAAALgADCgYJFQABLgAECgYJGQAIAHkIAA==.',
Gu='Gultir:BAAALgAECgcJCQAAAA==.',
Ha='Hacelian:BAAALgAECgEJAwAAAA==.Harper:BAAALgADCgcJBwAAAA==.',
He='Heetseeker:BAAALgAECgQJCAABLgAECgkJHQAUAMQgAA==.',
Hn='Hnoa:BAAALgADCgcJDwAAAA==.',
Ho='Hoggins:BAAALgADCgUJBQABLgADCgcJBwAHAAAAAA==.Holyverdict:BAABLgAECn8XAAIPAAkJUSWdBQASAwAPAAkJUSWdBQASAwAAAA==.',
Ic='Icaina:BAABLgAECn8vAAIUAAkJoB8FFAB1AgAUAAkJoB8FFAB1AgAAAA==.',
In='Incinderella:BAAALgADCgEJAQABLgAECgYJDgAHAAAAAA==.Interval:BAAALgADCgcJDgABLgAECgkJPAAYADsfAA==.',
Is='Isengard:BAAALgADCgEJAQAAAA==.Islands:BAAALgADCgIJAgAAAA==.',
Iv='Ivymyst:BAAALgADCgkJCQAAAA==.',
Ja='Jadani:BAABLgAECn8jAAIIAAgJfBHoDABwAQAIAAgJfBHoDABwAQAAAA==.',
Je='Jeisa:BAABLgAECn8yAAMQAAkJ0hFKFgBxAQAQAAkJnRFKFgBxAQAYAAYJQA2y3QDhAAAAAA==.Jelyn:BAAALgAECgYJBgAAAA==.',
Ji='Jimbonereus:BAAALgADCgIJAgAAAA==.Jingshei:BAAALgAECgEJAgABLgAECggJCwAHAAAAAA==.',
Jo='Jordyevoker:BAAALgAECggJDQAAAA==.',
Ju='Juanns:BAAALgAFFAIJAgAAAA==.',
Ka='Kalchee:BAAALgADCgIJAgABLgAFFAMJCAARAEEWAA==.Kallotera:BAABLgAECn85AAMNAAkJAxWQAAAJAgANAAkJAxWQAAAJAgALAAUJ4QbQcAD1AAAAAA==.Kalthur:BAAALgAECgMJAwAAAA==.Kastoria:BAAALgADCgkJGQAAAA==.Katnipp:BAACLgAFFH8IAAIBAAMJFA9YGQDZAAABAAMJFA9YGQDZAAAuAAQKfzMAAgEACQmMHX0ZAI0CAAEACQmMHX0ZAI0CAAAA.Katnyss:BAAALgAECgYJDQAAAA==.Kaylazune:BAABLgAECn83AAMZAAkJwAuCLgBnAQAZAAkJjQqCLgBnAQAaAAYJpAuQQgDhAAAAAA==.',
Ke='Kellwynne:BAAALgAECgMJAwAAAA==.Keramoon:BAAALgADCgUJBQAAAA==.Keyleth:BAAALgAECgEJAQAAAA==.',
Kh='Kharybdis:BAAALgAECgMJAwAAAA==.Khrala:BAABLgAECn8yAAMRAAkJDxiiMgA0AgARAAkJDxiiMgA0AgAbAAIJHgxkTQBbAAAAAA==.',
Ki='Kiye:BAACLgAFFH8YAAIBAAcJahOUEQDXAQABAAcJahOUEQDXAQAuAAQKfysAAgEACQlMHHgPAL8CAAEACQlMHHgPAL8CAAAA.',
Ko='Koren:BAAALgADCgMJAgAAAA==.',
Kr='Krenko:BAABLgAECn8VAAIRAAkJgAofbACNAQARAAkJgAofbACNAQAAAA==.',
Ku='Kung:BAABLgAECn8kAAMFAAkJhx9QDACAAgAFAAkJhx9QDACAAgAEAAgJ8BFuAQBxAQAAAA==.Kuuro:BAABLgAECn9GAAIUAAkJZxSsAgDHAQAUAAkJZxSsAgDHAQAAAA==.',
La='Lanister:BAAALgADCgQJBAAAAA==.Lattymag:BAAALgAECggJDwAAAA==.Laughystabby:BAAALgAECgkJDQAAAA==.',
Le='Leibniz:BAABLgAECn88AAIcAAkJhCEbAADdAgAcAAkJhCEbAADdAgAAAA==.Leisa:BAABLgAECn9FAAIBAAkJGhopAgBFAgABAAkJGhopAgBFAgAAAA==.Lelwindae:BAAALgAECgYJCQAAAA==.',
Li='Lifemoon:BAABLgAECn8fAAISAAcJfA5ADQDdAAASAAcJfA5ADQDdAAAAAA==.Lightgiver:BAAALgAECgYJDQAAAA==.Lighthoof:BAABLgAECn8gAAMYAAkJNx84FQDrAgAYAAkJNx84FQDrAgAQAAQJVBsaGwA1AQAAAA==.Lightiuz:BAABLgAECn8eAAMCAAYJBhbqRQCKAQACAAYJBhbqRQCKAQAXAAQJZQGccgBXAAAAAA==.Lildangerus:BAAALgAECgMJAwAAAA==.Lilliana:BAAALgADCgIJAgAAAA==.Liminara:BAEBLgAFFH8OAAMQAAUJpBJHAwC4AAAYAAUJfxCfTwAPAQAQAAMJfQtHAwC4AAABLgAFFAcJLAABAF8fAA==.Linaste:BAAALgAECgYJDAAAAA==.Lipsip:BAAALgAFFAEJAQAAAA==.Lirah:BAAALgAECggJCQABLgAFFAcJGAABAGoTAA==.Lissandra:BAAALgAECgYJCgAAAA==.Lividcow:BAAALgAECgcJCgAAAA==.Lividzdk:BAABLgAECn9CAAMRAAkJBiFvEADpAgARAAkJBiFvEADpAgAbAAIJOgwDUgBOAAAAAA==.',
Lo='Lonaldo:BAAALgAECgEJAQAAAA==.Lowpop:BAAALgADCgQJBAABLgAECgcJFgAFAJwPAA==.',
Lu='Lulu:BAABLgAFFH8YAAMFAAgJKhx6AAA5AgAFAAgJKhx6AAA5AgAdAAEJ6QFfcQAgAAABLgAFFAkJSQARAEglAA==.',
Ly='Lynoia:BAAALgAECggJCwAAAA==.',
Ma='Malarus:BAAALgADCgEJAQAAAA==.Mandevu:BAAALgAECgUJBwAAAA==.Manknus:BAABLgAECn9AAAILAAkJJRVGGgAbAgALAAkJJRVGGgAbAgAAAA==.Mannydemons:BAAALgADCgUJBgAAAA==.Mantequilla:BAABLgAECn8YAAIRAAcJTxzFSQAWAgARAAcJTxzFSQAWAgAAAA==.Manthrax:BAACLgAFFH8HAAIUAAMJOQgtGQCIAAAUAAMJOQgtGQCIAAAuAAQKfzQAAhQACQm3CZhMAH4BABQACQm3CZhMAH4BAAAA.Marix:BAAALgADCgEJAQAAAA==.',
Me='Megami:BAAALgADCgEJAgAAAA==.Mexecutioner:BAAALgADCgIJAgABLgAFFAMJBwAFAHsFAA==.',
Mi='Missmolt:BAABLgAECn9IAAIeAAkJeyYXAACIAwAeAAkJeyYXAACIAwAAAA==.',
Mo='Mogok:BAAALgAECgIJAgAAAA==.Molting:BAAALgAECgMJBAAAAA==.',
My='Mykie:BAAALgAECgcJDgAAAA==.Mylor:BAACLgAFFH8HAAIPAAMJLQ5eDQCMAAAPAAMJLQ5eDQCMAAAuAAQKfzsAAw8ACQmUFKAdABYCAA8ACQmUFKAdABYCABgAAQm/D/ZIATAAAAAA.Myrddral:BAABLgAECn9FAAIbAAkJ6yNeAADwAgAbAAkJ6yNeAADwAgAAAA==.Mystifeyed:BAABLgAECn8mAAMfAAkJdQpyNADWAAAgAAcJYgmPFgBQAQAfAAgJHQhyNADWAAAAAA==.',
['Mü']='Mürsaat:BAABLgAECn85AAIYAAkJ8BtfMAA/AgAYAAkJ8BtfMAA/AgAAAA==.',
Na='Namrekcah:BAAALgADCgcJDgABLgAFFAgJPAAbAJYgAA==.Narra:BAAALgAECgQJBQABLgADCgcJBwAHAAAAAA==.',
Ne='Nebalicious:BAAALgADCgcJDAABLgAECgYJDQAHAAAAAA==.Nekonomiya:BAAALgADCgMJAwAAAA==.',
Ni='Nightlevels:BAABLgAECn85AAMZAAkJ2iOpAgCJAwAZAAkJ2iOpAgCJAwAaAAEJFCL/cgBcAAAAAA==.Nimbledragon:BAAALgAECgIJAgAAAA==.',
Nt='Ntayu:BAABLgAECn9HAAIBAAkJYQ2TBACkAQABAAkJYQ2TBACkAQAAAA==.',
Ny='Nyaanya:BAAALgADCgMJAwAAAA==.',
Ol='Olizia:BAABLgAECn8WAAIRAAcJiBKYdQCaAQARAAcJiBKYdQCaAQAAAA==.',
On='Onaga:BAABLgAECn8XAAIYAAcJIwSq8gDHAAAYAAcJIwSq8gDHAAAAAA==.',
Op='Opex:BAACLgAFFH8HAAIBAAMJGQUlcQC9AAABAAMJGQUlcQC9AAAuAAQKfxoAAwEACQnJDKJIAJABAAEACQnJDKJIAJABAAMAAQlRAH2bABMAAAAA.Opheliabutts:BAAALgAECgQJBgAAAA==.',
Or='Oril:BAAALgAECgkJEQAAAA==.',
Pa='Paw:BAAALgADCgEJAgAAAA==.',
Pe='Penjei:BAAALgADCgYJBgAAAA==.Perkyblade:BAABLgAECn8VAAILAAgJ9Q0GPQBSAQALAAgJ9Q0GPQBSAQAAAA==.',
Ph='Philomel:BAACLgAFFH8HAAIMAAMJ0Q5OagC3AAAMAAMJ0Q5OagC3AAAuAAQKfxwAAgwACAk/G84rAE8CAAwACAk/G84rAE8CAAAA.',
Pi='Piekal:BAAALgAECgcJBwAAAA==.Pixamoo:BAAALgADCgUJCAAAAA==.',
Pl='Planeswalker:BAAALgADCgYJBgAAAA==.',
Po='Podnuh:BAAALgADCgIJAgAAAA==.Poxic:BAAALgAECgUJCQAAAA==.',
Pr='Premu:BAAALgADCggJDQABLgAECgkJNwAXAGcfAA==.Priesthealz:BAAALgAECgcJDAABLgAECgkJMAAEAIIdAA==.Pritt:BAAALgADCgcJDQABLgAECgcJEAAHAAAAAA==.',
Ps='Psyvival:BAAALgAECgEJAQAAAA==.',
Qu='Quazu:BAAALgAECgcJBwAAAA==.',
Ra='Radagahst:BAAALgAECgcJDwAAAA==.Rarngorm:BAABLgAECn8iAAIhAAgJqhfUCgDOAQAhAAgJqhfUCgDOAQAAAA==.Rasputia:BAAALgADCgYJBgAAAA==.Ravinar:BAABLgAECn8iAAIiAAkJARSxAwDaAQAiAAkJARSxAwDaAQAAAA==.Raàm:BAAALgAECgkJEwAAAA==.',
Re='Reardain:BAAALgAECggJEwAAAA==.Received:BAAALgAECgYJCAAAAA==.Relia:BAABLgAECn8YAAMKAAkJyQ/IIQDJAQAKAAgJNhDIIQDJAQAZAAEJKAaJdwA3AAAAAA==.Remedy:BAAALgADCgcJBwAAAA==.',
Ri='Richardparkr:BAAALgAECgEJAQAAAA==.Rillty:BAAALgAECggJEAAAAA==.Riverwind:BAAALgAECgUJCgABLgAECgkJHQAUAMQgAA==.',
Rj='Rj:BAAALgADCgMJAwAAAA==.',
Ro='Romulus:BAABLgAECn8wAAICAAkJGRUeLgDtAQACAAkJGRUeLgDtAQAAAA==.',
Ry='Ryo:BAAALgAECgIJAgAAAA==.',
Sa='Safyra:BAAALgADCgYJCAAAAA==.Sakoian:BAAALgAFFAEJAQAAAA==.Sakuf:BAAALgADCgcJBwAAAA==.Salana:BAAALgADCgQJBwAAAA==.Santofrancis:BAACLgAFFH8HAAIFAAMJewXxCACUAAAFAAMJewXxCACUAAAuAAQKfxwAAgUACQmhCn0xAEABAAUACQmhCn0xAEABAAAA.Sarbarola:BAAALgAECgQJCwAAAA==.Save:BAAALgAECgIJBAABLgAFFAEJAQAHAAAAAA==.',
Se='Seraie:BAAALgAECgcJCQAAAA==.',
Sh='Shadethrower:BAABLgAECn8WAAIaAAkJ9hqVCwCXAgAaAAkJ9hqVCwCXAgAAAA==.Shallbedo:BAAALgAECgYJDgABLgAFFAMJBgAVAJENAA==.Shallvoker:BAACLgAFFH8GAAMVAAMJkQ3TRgCtAAAVAAMJkQ3TRgCtAAAWAAEJzAM9EAA6AAAuAAQKfycAAxYACAnRGuwKAC0CABYACAkEF+wKAC0CABUABAmLGeJFABMBAAAA.Shane:BAAALgADCgEJAQAAAA==.Shazammy:BAAALgADCgMJBAAAAA==.Shmalexia:BAAALgAECgMJAwAAAA==.',
Si='Siatraler:BAAALgAECgkJEwAAAA==.Sigarette:BAACLgAFFH88AAIbAAgJliBdAwCBAgAbAAgJliBdAwCBAgAuAAQKfzkAAhsACAnXJJkCAEIDABsACAnXJJkCAEIDAAAA.Silverspoon:BAAALgAECgMJBAAAAA==.Sinardi:BAABLgAECn81AAMjAAkJ3xi1AQCTAQAjAAkJ3xi1AQCTAQAkAAUJFws8HgCpAAAAAA==.',
Sk='Skoobz:BAAALgAECgEJAgAAAA==.Skubasteve:BAAALgAECgYJDwAAAA==.Skydragon:BAAALgAECgYJBgAAAA==.Skylock:BAABLgAECn8WAAQcAAkJiwwFDQCMAQAcAAkJFAwFDQCMAQAIAAYJkAcUIACsAAAJAAMJOgJ2FgFSAAAAAA==.Skymane:BAABLgAECn8VAAMKAAYJmw/XNABEAQAKAAYJmw/XNABEAQAaAAEJfgJdhQAsAAAAAA==.',
Sn='Snaggletooth:BAAALgADCgEJAQAAAA==.',
So='Solar:BAAALgAFFAMJAwAAAA==.Soongxiao:BAAALgAECgEJAQAAAA==.Sorce:BAAALgAECgYJCQABLgAFFAUJFgAUANoZAA==.Sovix:BAAALgAECgEJBAAAAA==.Sovo:BAACLgAFFH8ZAAISAAcJbRfFJwDXAQASAAcJbRfFJwDXAQAuAAQKfzEAAhIACQlEIpcdAP8CABIACQlEIpcdAP8CAAAA.',
Sp='Spiritdáncer:BAAALgADCgEJAQAAAA==.',
Sq='Squshmepure:BAAALgAECgcJAwAAAA==.',
St='Starrin:BAAALgAECggJEwAAAA==.Steaknquake:BAABLgAECn9KAAIUAAkJ4CIzBQBgAwAUAAkJ4CIzBQBgAwAAAA==.',
Su='Sumdumfun:BAAALgAECgMJAwAAAA==.Sunflower:BAAALgAECgYJDgAAAA==.',
Sv='Svaha:BAAALgAECgIJAgAAAA==.',
Sy='Sybri:BAABLgAECn8WAAMBAAgJ5RgjOQDKAQABAAcJNRojOQDKAQADAAUJ6wsrWQDhAAAAAA==.Sylvandel:BAABLgAECn8/AAIDAAkJZxuUBgApAgADAAkJZxuUBgApAgAAAA==.Sylvrshado:BAAALgAECgIJAgAAAA==.',
Ta='Taberna:BAAALgAECgMJAwAAAA==.Talthis:BAAALgAECgIJAgAAAA==.',
Te='Teagen:BAABLgAECn81AAMCAAkJggj1VQA4AQACAAkJggj1VQA4AQAXAAIJUgt6dwBXAAAAAA==.',
Th='Thalius:BAABLgAECn9DAAIRAAkJNBONAgAGAgARAAkJNBONAgAGAgAAAA==.Thorandaal:BAABLgAECn8jAAMYAAgJJQpsmwA/AQAYAAgJJQpsmwA/AQAPAAYJAgrwTgD+AAAAAA==.Thunderbuddy:BAAALgADCgEJAQAAAA==.',
Ti='Tisbish:BAAALgADCgIJAgAAAA==.',
To='Tome:BAABLgAECn8hAAQDAAkJ6SYDAAAbBAADAAkJ3CYDAAAbBAAGAAkJxCbjAABpAwABAAEJEyZD/ABjAAAAAA==.Tometv:BAAALgAECgcJBgABLgAECgkJIQADAOkmAA==.Toomanydeths:BAABLgAECn8+AAMbAAkJsQ/WHQBpAQAbAAkJsQ/WHQBpAQARAAYJ3QywvgAAAQAAAA==.',
Tr='Trunx:BAAALgAECgQJBQABLgAECgkJHwAdAN4jAA==.',
Ty='Tye:BAAALgAECgcJEQAAAA==.Tyyle:BAAALgADCgYJBgAAAA==.',
['Tá']='Tálos:BAAALgAECgEJBAAAAA==.',
Ul='Uldear:BAAALgADCgYJCwAAAA==.',
Un='Unbuttered:BAAALgAECgIJBAAAAA==.Uninvite:BAAALgAECgQJBAAAAA==.Untz:BAAALgAECgEJAQAAAA==.',
Ur='Ursusmanny:BAAALgAECgcJCwAAAA==.',
Va='Vaelthyeth:BAAALgADCgUJBQAAAA==.Valkyrie:BAAALgAECgYJBgABLgAECgkJMAAEAIIdAA==.Vandarin:BAAALgADCgcJGgABLgAECgYJGQAIAHkIAA==.Vanthrall:BAAALgAECgQJCgAAAA==.Vayce:BAABLgAECn8yAAMlAAkJ5iEkAwCKAgAlAAgJyCIkAwCKAgAmAAcJRyL/GAA9AgAAAA==.',
Ve='Velysa:BAACLgAFFH8FAAIQAAEJygt6GQAwAAAQAAEJygt6GQAwAAAuAAQKf0IAAxAACQlDF18KACUCABAACQlDF18KACUCABgAAgk6CTIeAWAAAAAA.Veniea:BAAALgADCgEJAQABLgAECggJCwAHAAAAAA==.',
Vi='Vizago:BAAALgADCgEJAQAAAA==.',
Vo='Vogekth:BAAALgAECgUJCwAAAA==.',
['Vÿ']='Vÿktor:BAAALgAECgQJBAAAAA==.',
Wa='Warseeker:BAABLgAECn8dAAMUAAkJxCAlCADzAgAUAAkJxCAlCADzAgATAAQJ1w7QYwC6AAAAAA==.Watlmonk:BAAALgADCgIJAgAAAA==.',
We='Weatherworn:BAABLgAECn9FAAMUAAkJuxboJwAgAgAUAAkJuxboJwAgAgATAAEJwwrcEwAoAAAAAA==.',
Wi='Wirhlanir:BAAALgADCgkJCQAAAA==.',
Xe='Xemu:BAAALgAECgQJBAAAAA==.Xenferos:BAAALgADCgcJDAABLgAFFAIJCQAcANoIAA==.Xerber:BAAALgADCgYJDQABLgAECgYJGQAIAHkIAA==.',
Xi='Xiro:BAAALgAECgUJEwAAAA==.',
Yo='Yoril:BAAALgAECgcJDgAAAA==.',
Za='Zagihex:BAAALgAECgcJBwAAAA==.Zagiroth:BAABLgAECn8sAAMMAAkJFiGnDQDYAgAMAAkJFiGnDQDYAgAkAAEJFhthJwBLAAAAAA==.Zalthanos:BAAALgADCgEJAQAAAA==.Zarack:BAAALgADCgYJBAABLgAECgYJGQAIAHkIAA==.',
Ze='Zebraman:BAABLgAECn8VAAICAAgJDBKSQgCGAQACAAgJDBKSQgCGAQAAAA==.Zeraida:BAAALgADCgcJEgAAAA==.',
['Zê']='Zêth:BAAALgADCgEJAQAAAA==.',
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
