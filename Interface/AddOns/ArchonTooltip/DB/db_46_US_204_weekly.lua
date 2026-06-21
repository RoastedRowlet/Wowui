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
local provider = {region='US',realm='SteamwheedleCartel',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aalwein:BAABLgAECn8rAAIBAAkJsx8EGwCDAgABAAkJsx8EGwCDAgAAAA==.',
Ae='Aesculapius:BAACLgAFFH8KAAICAAMJRwe4TACLAAACAAMJRwe4TACLAAAuAAQKfzMAAgIACQmKGf8UAKICAAIACQmKGf8UAKICAAAA.',
Al='Aladia:BAAALgADCgMJAgAAAA==.Aloisious:BAAALgAECgEJAQAAAA==.',
Am='Amarii:BAABLgAECn8zAAIDAAgJPQ2AAAAJAQADAAgJPQ2AAAAJAQAAAA==.Amorash:BAAALgADCgEJAQAAAA==.',
An='Annabeth:BAAALgAECgYJCwABLgAFFAMJCQAEANAaAA==.Anonymus:BAACLgAFFH8JAAIEAAMJ0BoWLAD5AAAEAAMJ0BoWLAD5AAAuAAQKfxgAAwQACQlKHd8PAD8CAAQACAksHt8PAD8CAAUAAgmiEJuKAEcAAAAA.',
Ar='Ara:BAACLgAFFH8MAAMBAAQJlBEJQQArAQABAAQJlBEJQQArAQAGAAEJiQNbNABBAAAuAAQKfy4AAgEACQmhIHgPANUCAAEACQmhIHgPANUCAAAA.Ardiir:BAAALgAECgEJAgABLgAECgQJDQAHAAAAAA==.Ardwin:BAAALgADCgEJAQABLgAECgYJGQAIAHkIAA==.',
As='Ashgrove:BAAALgAECgUJCAAAAA==.',
Av='Avigar:BAAALgADCgEJAwAAAA==.',
Az='Azzinoth:BAAALgAECgIJAgAAAA==.',
Ba='Bakeneko:BAAALgADCgMJBgAAAA==.Bambarrok:BAABLgAECn8XAAIJAAkJSQbdfQA9AQAJAAkJSQbdfQA9AQAAAA==.Bangan:BAAALgAECgYJEgAAAA==.',
Be='Belakor:BAAALgAECgYJBgAAAA==.Bep:BAAALgAECgYJDAABLgAECgkJGgAIADEVAA==.Bepragosa:BAABLgAECn8aAAIIAAkJMRWkCAA3AgAIAAkJMRWkCAA3AgAAAA==.',
Bi='Binpharteen:BAAALgAECgEJAwAAAA==.',
Bl='Blaque:BAAALgADCgcJBwABLgAECggJFQAKABoMAA==.',
Br='Brimscythe:BAAALgAECgEJAgABLgAECggJIQAFAFwfAA==.Brownbelt:BAABLgAECn9JAAILAAkJVh1pCwCxAgALAAkJVh1pCwCxAgAAAA==.Brîn:BAAALgAECgUJCgAAAA==.',
Bu='Buteihunter:BAACLgAFFH8KAAIBAAMJMhzCUgAEAQABAAMJMhzCUgAEAQAuAAQKfzcABAEACQnLItILAPUCAAEACQnLItILAPUCAAMAAQnvC0WIADQAAAYAAQkSBytnADAAAAAA.',
Ca='Cadranak:BAABLgAECn8wAAIMAAkJ2RKoQwC9AQAMAAkJ2RKoQwC9AQAAAA==.Caiyenthi:BAABLgAECn8nAAIBAAgJkQ+OZAB8AQABAAgJkQ+OZAB8AQAAAA==.Calliesue:BAAALgAECgIJAgAAAA==.Camgor:BAAALgADCgEJAQABLgAECgYJGQAIAHkIAA==.Carfalis:BAAALgADCggJCQAAAA==.',
Ch='Chelali:BAABLgAECn8XAAQLAAkJ8RVsJQAtAgALAAgJ/BZsJQAtAgANAAUJ5BDHLQATAQAOAAEJNAiNUgA0AAAAAA==.Chelly:BAAALgAECgEJAQABLgAECgkJFwALAPEVAA==.Chicharrone:BAAALgAECgYJEgAAAA==.Chihiro:BAAALgADCgMJAwAAAA==.Chizaru:BAACLgAFFH8PAAIPAAQJuRXBIwACAQAPAAQJuRXBIwACAQAuAAQKfyoAAw8ACQlbHpYHABIDAA8ACQlbHpYHABIDABAAAwkyAXdOADUAAAAA.Chlorophyll:BAAALgAECgEJAQAAAA==.Chyntobelt:BAABLgAECn8kAAIRAAcJhAVxyQDxAAARAAcJhAVxyQDxAAABLgAECgkJSQALAFYdAA==.',
Co='Copyright:BAAALgAECgEJAQAAAA==.',
Cr='Creep:BAAALgAECgYJEAAAAA==.Cryption:BAABLgAECn8VAAIBAAgJkhQEOADOAQABAAgJkhQEOADOAQAAAA==.',
['Cú']='Cúchulainn:BAAALgAECgYJDQAAAA==.',
Da='Daelyn:BAABLgAECn8ZAAIBAAgJKA0DigArAQABAAgJKA0DigArAQAAAA==.Dalhma:BAAALgAFFAIJAgAAAA==.Dallma:BAAALgAFFAYJCgABLgAFFAIJAgAHAAAAAQ==.Dallmia:BAAALgAFFAMJAwABLgAFFAIJAgAHAAAAAQ==.Dane:BAAALgAECgIJAgAAAA==.Dayaris:BAABLgAECn8jAAIBAAgJXQq8bABoAQABAAgJXQq8bABoAQAAAA==.',
De='Deadbeat:BAAALgAECgUJBgAAAA==.Deafenned:BAABLgAECn8aAAISAAkJdx6gPQCBAgASAAkJdx6gPQCBAgABLgAFFAMJBwAMANEOAA==.Deaflynn:BAAALgAECgEJAwABLgAFFAMJBwAMANEOAA==.Deafnight:BAAALgAECgIJBAABLgAFFAMJBwAMANEOAA==.Deliquesce:BAAALgADCgMJAwAAAA==.Demonbep:BAAALgADCgQJBAABLgAECgkJGgAIADEVAA==.Demonicpower:BAAALgAECgYJCAAAAA==.Derrington:BAABLgAECn8kAAIIAAcJkSGMBAAzAgAIAAcJkSGMBAAzAgABLgAECggJIQAFAFwfAA==.Destinyetwo:BAAALgAECgEJAQAAAA==.Dett:BAABLgAECn8VAAITAAcJZQiSVgDhAAATAAcJZQiSVgDhAAAAAA==.',
Di='Diamante:BAACLgAFFH8VAAIUAAUJ2hmEHwB3AQAUAAUJ2hmEHwB3AQAuAAQKfyoAAhQACQlBFpwzAOQBABQACQlBFpwzAOQBAAAA.',
Dk='Dkvayce:BAAALgADCgYJBgAAAA==.',
Dr='Dragqueene:BAABLgAFFH8HAAIVAAUJQAQlQQDCAAAVAAUJQAQlQQDCAAAAAA==.Drakluz:BAAALgADCgEJAQAAAA==.Drakner:BAABLgAECn8xAAMVAAgJKw4NNgBYAQAVAAgJKw4NNgBYAQAWAAQJBQJMMgCEAAAAAA==.Drellin:BAAALgAECgEJBAABLgAECggJIQAFAFwfAA==.Dremu:BAABLgAECn83AAMXAAkJZx84CQC/AgAXAAkJZx84CQC/AgACAAMJEw9doACJAAAAAA==.',
Du='Duraz:BAABLgAECn8jAAICAAkJQg4tSgBmAQACAAkJQg4tSgBmAQAAAA==.',
Dy='Dysraxis:BAAALgADCgEJAQAAAA==.',
Ee='Eerie:BAAALgAECgIJBgAAAA==.',
Eg='Eggar:BAAALgAECggJCAABLgAECgkJLgARAEYWAA==.',
El='Elahna:BAAALgADCgcJDQAAAA==.Elalia:BAABLgAECn8ZAAIIAAYJeQjlHgCzAAAIAAYJeQjlHgCzAAAAAA==.Elamaun:BAABLgAECn8/AAMPAAgJ7RoNFABuAgAPAAgJ7RoNFABuAgAYAAMJQgOcWwFWAAAAAA==.Elereia:BAAALgAECgEJAQAAAA==.Eltiana:BAAALgAECgUJCwAAAA==.',
En='Energy:BAAALgADCgQJBwABLgAFFAMJBgARAH4YAA==.English:BAABLgAECn8VAAIKAAgJGgwENwA5AQAKAAgJGgwENwA5AQAAAA==.',
Ep='Ephex:BAAALgADCgcJGQAAAA==.Ephyiana:BAAALgADCgcJCAAAAA==.Epic:BAAALgAECgYJEAAAAA==.',
Er='Errimys:BAAALgADCgUJBQAAAA==.Ertraz:BAAALgAECgEJAgAAAA==.',
Es='Essense:BAAALgADCgcJBwAAAA==.Esçanor:BAAALgADCgUJBQAAAA==.',
Et='Etania:BAAALgAECgYJCQAAAA==.',
Ev='Evhomang:BAABLgAFFH8KAAIVAAQJ+hiLJgA0AQAVAAQJ+hiLJgA0AQAAAA==.',
Fa='Faelyna:BAABLgAECn9CAAIGAAkJyRJtGADeAQAGAAkJyRJtGADeAQAAAA==.Fang:BAAALgADCgEJAQAAAA==.',
Fe='Fearbear:BAAALgAECgUJBgAAAA==.Felnut:BAAALgADCgEJAQAAAA==.',
Fi='Finniel:BAAALgADCgEJAQAAAA==.',
Fl='Flash:BAAALgADCgMJAQAAAA==.',
Fo='Foix:BAAALgADCgcJDwAAAA==.Forged:BAACLgAFFH8IAAIYAAMJxROyawDYAAAYAAMJxROyawDYAAAuAAQKfysAAhgACAnzHxEpAIECABgACAnzHxEpAIECAAAA.',
Ga='Gaerne:BAAALgADCgEJAQAAAA==.',
Gi='Githyanki:BAAALgADCgkJCQAAAA==.',
Gl='Glabberghoul:BAABLgAECn8sAAIVAAkJQhTpIwC9AQAVAAkJQhTpIwC9AQAAAA==.',
Go='Goodhead:BAAALgADCgMJBAAAAA==.',
Gr='Grangladesh:BAAALgAECgEJAgABLgAECgQJDQAHAAAAAA==.Grangmage:BAAALgAECgQJDQAAAA==.Grimvault:BAAALgAECgEJAQABLgAECggJIQAFAFwfAA==.Griogair:BAAALgADCgYJFQABLgAECgYJGQAIAHkIAA==.',
Gu='Gultir:BAAALgAECgcJCQAAAA==.',
Ha='Hacelian:BAAALgAECgEJAwAAAA==.Harper:BAAALgADCgcJBwAAAA==.',
He='Heetseeker:BAAALgAECgQJCAABLgAECgkJHQAUAMQgAA==.',
Hn='Hnoa:BAAALgADCgcJDwAAAA==.',
Ho='Hoggins:BAAALgADCgUJBQABLgADCgcJBwAHAAAAAA==.Holyverdict:BAABLgAECn8XAAIPAAkJUSWdBQASAwAPAAkJUSWdBQASAwAAAA==.',
Ic='Icaina:BAABLgAECn8vAAIUAAkJoB8FFAB1AgAUAAkJoB8FFAB1AgAAAA==.',
In='Incinderella:BAAALgADCgEJAQABLgAECgYJDgAHAAAAAA==.Interval:BAAALgADCgcJDgABLgAECgkJPAAYADsfAA==.',
Is='Islands:BAAALgADCgIJAgAAAA==.',
Ja='Jadani:BAABLgAECn8jAAIIAAgJfBHoDABwAQAIAAgJfBHoDABwAQAAAA==.',
Je='Jeisa:BAABLgAECn8vAAMQAAgJXxFKFgBxAQAQAAgJIRFKFgBxAQAYAAYJQA2v3QDhAAAAAA==.Jelyn:BAAALgAECgYJBgAAAA==.',
Ji='Jimbonereus:BAAALgADCgIJAgAAAA==.Jingshei:BAAALgAECgEJAgABLgAECggJCwAHAAAAAA==.',
Jo='Jordyevoker:BAAALgAECggJDQAAAA==.',
Ju='Juanns:BAAALgAECgYJDwAAAA==.',
Ka='Kalchee:BAAALgADCgIJAgABLgAFFAMJAwAHAAAAAA==.Kallotera:BAABLgAECn82AAMNAAgJHBRGAACzAQANAAgJHBRGAACzAQALAAUJ4QbQcAD1AAAAAA==.Kalthur:BAAALgAECgMJAwAAAA==.Kastoria:BAAALgADCgkJGQAAAA==.Katnipp:BAACLgAFFH8FAAIBAAMJZw1UZADcAAABAAMJZw1UZADcAAAuAAQKfzMAAgEACQmMHX4ZAI0CAAEACQmMHX4ZAI0CAAAA.Katnyss:BAAALgAECgYJDQAAAA==.Kaylazune:BAABLgAECn80AAMZAAgJXAyBLgBnAQAZAAgJAwuBLgBnAQAaAAYJpAuMQgDhAAAAAA==.',
Ke='Kellwynne:BAAALgAECgMJAwAAAA==.Keramoon:BAAALgADCgUJBQAAAA==.Keyleth:BAAALgAECgEJAQAAAA==.',
Kh='Khrala:BAABLgAECn8uAAMRAAkJRhagMgA0AgARAAkJRhagMgA0AgAbAAIJHgxkTQBbAAAAAA==.',
Ki='Kiye:BAACLgAFFH8YAAIBAAcJahOYEQDXAQABAAcJahOYEQDXAQAuAAQKfysAAgEACQlMHHgPAL8CAAEACQlMHHgPAL8CAAAA.',
Ko='Koren:BAAALgADCgMJAgAAAA==.',
Kr='Krenko:BAABLgAECn8VAAIRAAkJgAofbACNAQARAAkJgAofbACNAQAAAA==.',
Ku='Kung:BAABLgAECn8hAAMFAAgJXB9QDACAAgAFAAgJXB9QDACAAgAEAAgJ8BGQAABtAQAAAA==.Kuuro:BAABLgAECn9DAAIUAAgJOxYoAQCZAQAUAAgJOxYoAQCZAQAAAA==.',
La='Lanister:BAAALgADCgQJBAAAAA==.Lattymag:BAAALgAECggJDwAAAA==.Laughystabby:BAAALgAECgkJDQAAAA==.',
Le='Leibniz:BAABLgAECn85AAIcAAgJQyEeAAB0AgAcAAgJQyEeAAB0AgAAAA==.Leisa:BAABLgAECn9CAAIBAAgJ2BgxAQDtAQABAAgJ2BgxAQDtAQAAAA==.Lelwindae:BAAALgAECgYJCQAAAA==.',
Li='Lifemoon:BAABLgAECn8ZAAISAAcJEAr7sAAgAQASAAcJEAr7sAAgAQAAAA==.Lightgiver:BAAALgAECgYJDQAAAA==.Lighthoof:BAABLgAECn8gAAMYAAkJNx84FQDrAgAYAAkJNx84FQDrAgAQAAQJVBsaGwA1AQAAAA==.Lightiuz:BAABLgAECn8eAAMCAAYJBhbqRQCKAQACAAYJBhbqRQCKAQAXAAQJZQGccgBXAAAAAA==.Lilliana:BAAALgADCgIJAgAAAA==.Liminara:BAEBLgAFFH8MAAMQAAUJrRBHAwC4AAAYAAUJiA6sTwAPAQAQAAMJfQtHAwC4AAABLgAFFAcJJwABAF8fAA==.Linaste:BAAALgAECgYJDAAAAA==.Lirah:BAAALgAECggJCQABLgAFFAcJGAABAGoTAA==.Lissandra:BAAALgAECgYJCgAAAA==.Lividcow:BAAALgAECgcJCgAAAA==.Lividzdk:BAABLgAECn9CAAMRAAkJBiFtEADpAgARAAkJBiFtEADpAgAbAAIJOgwCUgBOAAAAAA==.',
Lo='Lonaldo:BAAALgAECgEJAQAAAA==.Lowpop:BAAALgADCgQJBAABLgAECgcJFgAFAJwPAA==.',
Lu='Lulu:BAABLgAFFH8TAAMFAAYJwyIHBAD3AQAFAAYJwyIHBAD3AQAdAAEJ6QFmcQAgAAAAAA==.',
Ly='Lynoia:BAAALgAECggJCwAAAA==.',
Ma='Malarus:BAAALgADCgEJAQAAAA==.Mandevu:BAAALgAECgUJBwAAAA==.Manknus:BAABLgAECn9AAAILAAkJJRVFGgAbAgALAAkJJRVFGgAbAgAAAA==.Mannydemons:BAAALgADCgUJBgAAAA==.Mantequilla:BAABLgAECn8YAAIRAAcJTxzFSQAWAgARAAcJTxzFSQAWAgAAAA==.Manthrax:BAABLgAECn80AAIUAAkJtwmUTAB+AQAUAAkJtwmUTAB+AQAAAA==.Marix:BAAALgADCgEJAQAAAA==.',
Me='Megami:BAAALgADCgEJAgAAAA==.Mexecutioner:BAAALgADCgIJAgABLgAECgkJHAAFAKEKAA==.',
Mi='Missmolt:BAABLgAECn9FAAIeAAkJBSYXAACIAwAeAAkJBSYXAACIAwAAAA==.',
Mo='Mogok:BAAALgADCgYJBgAAAA==.Molting:BAAALgAECgMJBAAAAA==.',
My='Mykie:BAAALgAECgcJDgAAAA==.Mylor:BAABLgAECn87AAMPAAkJlBSiHQAWAgAPAAkJlBSiHQAWAgAYAAEJvw/2SAEwAAAAAA==.Myrddral:BAABLgAECn9CAAIbAAgJOyQ9AACIAgAbAAgJOyQ9AACIAgAAAA==.Mystifeyed:BAABLgAECn8mAAMfAAkJdQpwNADWAAAgAAcJYgmPFgBQAQAfAAgJHQhwNADWAAAAAA==.',
['Mü']='Mürsaat:BAABLgAECn85AAIYAAkJ8BthMAA/AgAYAAkJ8BthMAA/AgAAAA==.',
Na='Namrekcah:BAAALgADCgcJDgABLgAFFAgJOwAbAJYgAA==.Narra:BAAALgAECgQJBQABLgADCgcJBwAHAAAAAA==.',
Ne='Nebalicious:BAAALgADCgcJDAABLgAECgYJDQAHAAAAAA==.Nekonomiya:BAAALgADCgMJAwAAAA==.',
Ni='Nightlevels:BAABLgAECn85AAMZAAkJ2iOqAgCJAwAZAAkJ2iOqAgCJAwAaAAEJFCL/cgBcAAAAAA==.Nimbledragon:BAAALgAECgIJAgAAAA==.',
Nt='Ntayu:BAABLgAECn9EAAIBAAgJyA2AAgBaAQABAAgJyA2AAgBaAQAAAA==.',
Ny='Nyaanya:BAAALgADCgMJAwAAAA==.',
Ol='Olizia:BAABLgAECn8WAAIRAAcJiBKYdQCaAQARAAcJiBKYdQCaAQAAAA==.',
On='Onaga:BAABLgAECn8XAAIYAAcJIwSm8gDHAAAYAAcJIwSm8gDHAAAAAA==.',
Op='Opex:BAACLgAFFH8HAAIBAAMJGQUocQC9AAABAAMJGQUocQC9AAAuAAQKfxoAAwEACQnJDKJIAJABAAEACQnJDKJIAJABAAMAAQlRAH2bABMAAAAA.Opheliabutts:BAAALgAECgQJBgAAAA==.',
Or='Oril:BAAALgAECgkJEQAAAA==.',
Pa='Paw:BAAALgADCgEJAgAAAA==.',
Pe='Penjei:BAAALgADCgYJBgAAAA==.Perkyblade:BAAALgAECggJEwAAAA==.',
Ph='Philomel:BAACLgAFFH8HAAIMAAMJ0Q5ZagC3AAAMAAMJ0Q5ZagC3AAAuAAQKfxwAAgwACAk/G84rAE8CAAwACAk/G84rAE8CAAAA.',
Pi='Piekal:BAAALgAECgcJBwAAAA==.Pixamoo:BAAALgADCgUJCAAAAA==.',
Pl='Planeswalker:BAAALgADCgYJBgAAAA==.',
Po='Podnuh:BAAALgADCgIJAgAAAA==.Poxic:BAAALgAECgUJCQAAAA==.',
Pr='Premu:BAAALgADCgUJBQABLgAECgkJNwAXAGcfAA==.Priesthealz:BAAALgAECgcJDAABLgAECgkJMAAEAIIdAA==.Pritt:BAAALgADCgcJDQABLgAECgcJEAAHAAAAAA==.',
Ps='Psyvival:BAAALgAECgEJAQAAAA==.',
Qu='Quazu:BAAALgAECgcJBwAAAA==.',
Ra='Radagahst:BAAALgAECgcJDwAAAA==.Rarngorm:BAABLgAECn8iAAIhAAgJqhfTCgDOAQAhAAgJqhfTCgDOAQAAAA==.Rasputia:BAAALgADCgYJBgAAAA==.Ravinar:BAABLgAECn8hAAIiAAkJ9ROxAwDaAQAiAAkJ9ROxAwDaAQAAAA==.Raàm:BAAALgAECggJEAAAAA==.',
Re='Reardain:BAAALgAECggJEwAAAA==.Received:BAAALgAECgYJCAAAAA==.Relia:BAABLgAECn8YAAMKAAkJyQ/IIQDJAQAKAAgJNhDIIQDJAQAZAAEJKAaHdwA3AAAAAA==.Remedy:BAAALgADCgcJBwAAAA==.',
Ri='Richardparkr:BAAALgAECgEJAQAAAA==.Rillty:BAAALgAECgYJCwAAAA==.Riverwind:BAAALgAECgUJCgABLgAECgkJHQAUAMQgAA==.',
Rj='Rj:BAAALgADCgMJAwAAAA==.',
Ro='Romulus:BAABLgAECn8tAAICAAgJHBUgLgDtAQACAAgJHBUgLgDtAQAAAA==.',
Ry='Ryo:BAAALgAECgIJAgAAAA==.',
Sa='Safyra:BAAALgADCgYJCAAAAA==.Sakoian:BAAALgAFFAEJAQAAAA==.Sakuf:BAAALgADCgcJBwAAAA==.Salana:BAAALgADCgQJBwAAAA==.Santofrancis:BAABLgAECn8cAAIFAAkJoQp+MQBAAQAFAAkJoQp+MQBAAQAAAA==.Sarbarola:BAAALgAECgQJCAAAAA==.Save:BAAALgAECgIJBAABLgAFFAEJAQAHAAAAAA==.',
Se='Seraie:BAAALgAECgcJCQAAAA==.',
Sh='Shadethrower:BAABLgAECn8WAAIaAAkJ9hqVCwCXAgAaAAkJ9hqVCwCXAgAAAA==.Shallbedo:BAAALgAECgYJDgABLgAFFAMJBgAVAJENAA==.Shallvoker:BAACLgAFFH8GAAMVAAMJkQ3IRgCtAAAVAAMJkQ3IRgCtAAAWAAEJzAM/EAA6AAAuAAQKfycAAxYACAnRGuwKAC0CABYACAkEF+wKAC0CABUABAmLGeBFABMBAAAA.Shane:BAAALgADCgEJAQAAAA==.Shazammy:BAAALgADCgMJBAAAAA==.Shmalexia:BAAALgAECgMJAwAAAA==.',
Si='Siatraler:BAAALgAECgkJEwAAAA==.Sigarette:BAACLgAFFH87AAIbAAgJliBjAwCBAgAbAAgJliBjAwCBAgAuAAQKfzkAAhsACAnXJJkCAEIDABsACAnXJJkCAEIDAAAA.Silverspoon:BAAALgAECgIJAwAAAA==.Sinardi:BAABLgAECn8sAAMjAAgJTBpkFADuAQAjAAgJTBpkFADuAQAkAAUJFws7HgCpAAAAAA==.',
Sk='Skoobz:BAAALgAECgEJAgAAAA==.Skubasteve:BAAALgAECgYJDwAAAA==.Skydragon:BAAALgAECgYJBgAAAA==.Skylock:BAABLgAECn8WAAQcAAkJiwwFDQCMAQAcAAkJFAwFDQCMAQAIAAYJkAcSIACsAAAJAAMJOgJ0FgFSAAAAAA==.Skymane:BAABLgAECn8VAAMKAAYJmw/XNABEAQAKAAYJmw/XNABEAQAaAAEJfgJdhQAsAAAAAA==.',
Sn='Snaggletooth:BAAALgADCgEJAQAAAA==.',
So='Solar:BAAALgAFFAMJAwAAAA==.Soongxiao:BAAALgAECgEJAQAAAA==.Sorce:BAAALgAECgYJBwABLgAFFAUJFQAUANoZAA==.Sovix:BAAALgAECgEJBAAAAA==.Sovo:BAACLgAFFH8ZAAISAAcJbRfdJwDXAQASAAcJbRfdJwDXAQAuAAQKfy4AAhIACQlEIpcdAP8CABIACQlEIpcdAP8CAAAA.',
Sp='Spiritdáncer:BAAALgADCgEJAQAAAA==.',
Sq='Squshmepure:BAAALgAECgcJAwAAAA==.',
St='Starrin:BAAALgAECggJEwAAAA==.Steaknquake:BAABLgAECn9KAAIUAAkJ4CI0BQBgAwAUAAkJ4CI0BQBgAwAAAA==.',
Su='Sumdumfun:BAAALgAECgMJAwAAAA==.Sunflower:BAAALgAECgYJDgAAAA==.',
Sv='Svaha:BAAALgAECgIJAgAAAA==.',
Sy='Sybri:BAABLgAECn8WAAMBAAgJ5RgjOQDKAQABAAcJNRojOQDKAQADAAUJ6wsrWQDhAAAAAA==.Sylvandel:BAABLgAECn88AAIDAAgJpBqUBgApAgADAAgJpBqUBgApAgAAAA==.Sylvrshado:BAAALgAECgIJAgAAAA==.',
Ta='Taberna:BAAALgAECgMJAwAAAA==.Talthis:BAAALgAECgIJAgAAAA==.',
Te='Teagen:BAABLgAECn81AAMCAAkJggj5VQA4AQACAAkJggj5VQA4AQAXAAIJUgt5dwBXAAAAAA==.',
Th='Thalius:BAABLgAECn9CAAIRAAgJJhQXAQDFAQARAAgJJhQXAQDFAQAAAA==.Thorandaal:BAABLgAECn8jAAMYAAgJJQpumwA/AQAYAAgJJQpumwA/AQAPAAYJAgrvTgD+AAAAAA==.Thunderbuddy:BAAALgADCgEJAQAAAA==.',
Ti='Tisbish:BAAALgADCgIJAgAAAA==.',
To='Tome:BAABLgAECn8hAAQDAAkJ6SYDAAAbBAADAAkJ3CYDAAAbBAAGAAkJxCbjAABpAwABAAEJEyZA/ABjAAAAAA==.Tometv:BAAALgAECgcJBgABLgAECgkJIQADAOkmAA==.Toomanydeths:BAABLgAECn8+AAMbAAkJsQ/WHQBpAQAbAAkJsQ/WHQBpAQARAAYJ3QypvgAAAQAAAA==.',
Tr='Trunx:BAAALgAECgQJBQABLgAECgkJHwAdAN4jAA==.',
Ty='Tye:BAAALgAECgcJEQAAAA==.Tyyle:BAAALgADCgYJBgAAAA==.',
['Tá']='Tálos:BAAALgAECgEJBAAAAA==.',
Ul='Uldear:BAAALgADCgYJCwAAAA==.',
Un='Unbuttered:BAAALgAECgIJBAAAAA==.Uninvite:BAAALgAECgQJBAAAAA==.Untz:BAAALgADCgYJBgAAAA==.',
Ur='Ursusmanny:BAAALgAECgcJCwAAAA==.',
Va='Vaelthyeth:BAAALgADCgUJBQAAAA==.Valkyrie:BAAALgAECgYJBgABLgAECgkJMAAEAIIdAA==.Vandarin:BAAALgADCgcJGgABLgAECgYJGQAIAHkIAA==.Vanthrall:BAAALgAECgQJCgAAAA==.Vayce:BAABLgAECn8yAAMlAAkJ5iEkAwCKAgAlAAgJyCIkAwCKAgAmAAcJRyL/GAA9AgAAAA==.',
Ve='Velysa:BAABLgAECn9BAAMQAAkJQxdfCgAlAgAQAAkJQxdfCgAlAgAYAAIJOgkyHgFgAAAAAA==.Veniea:BAAALgADCgEJAQABLgAECggJCwAHAAAAAA==.',
Vi='Vizago:BAAALgADCgEJAQAAAA==.',
Vo='Vogekth:BAAALgAECgUJCwAAAA==.',
['Vÿ']='Vÿktor:BAAALgADCgYJBgAAAA==.',
Wa='Warseeker:BAABLgAECn8dAAMUAAkJxCAlCADzAgAUAAkJxCAlCADzAgATAAQJ1w7LYwC6AAAAAA==.Watlmonk:BAAALgADCgIJAgAAAA==.',
We='Weatherworn:BAABLgAECn8/AAMUAAgJnxflJwAgAgAUAAgJnxflJwAgAgATAAEJEAbwuwAhAAAAAA==.',
Wi='Wirhlanir:BAAALgADCgkJCQAAAA==.',
Xe='Xemu:BAAALgAECgQJBAAAAA==.Xenferos:BAAALgADCgcJDAABLgAFFAIJBQAcANoIAA==.Xerber:BAAALgADCgYJDQABLgAECgYJGQAIAHkIAA==.',
Xi='Xiro:BAAALgAECgUJEwAAAA==.',
Yo='Yoril:BAAALgAECgcJDgAAAA==.',
Za='Zagihex:BAAALgAECgcJBwAAAA==.Zagiroth:BAABLgAECn8sAAMMAAkJFiGoDQDYAgAMAAkJFiGoDQDYAgAkAAEJFhthJwBLAAAAAA==.Zalthanos:BAAALgADCgEJAQAAAA==.Zarack:BAAALgADCgYJBAABLgAECgYJGQAIAHkIAA==.',
Ze='Zebraman:BAABLgAECn8VAAICAAgJDBKVQgCGAQACAAgJDBKVQgCGAQAAAA==.Zeraida:BAAALgADCgcJEgAAAA==.',
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
