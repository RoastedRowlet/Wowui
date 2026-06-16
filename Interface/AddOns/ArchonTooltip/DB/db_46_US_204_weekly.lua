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
local provider = {region='US',realm='SteamwheedleCartel',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aalwein:BAABLgAECn8pAAIBAAkJsx8UGgCEAgABAAkJsx8UGgCEAgAAAA==.',
Ae='Aesculapius:BAACLgAFFH8KAAICAAMJRwf/SgCLAAACAAMJRwf/SgCLAAAuAAQKfzMAAgIACQmKGbMUAKICAAIACQmKGbMUAKICAAAA.',
Al='Aladia:BAAALgADCgMJAgAAAA==.Aloisious:BAAALgAECgEJAQAAAA==.',
Am='Amarii:BAABLgAECn8rAAIDAAgJpArdEgAsAQADAAgJpArdEgAsAQAAAA==.Amorash:BAAALgADCgEJAQAAAA==.',
An='Annabeth:BAAALgAECgYJCwABLgAFFAMJCQAEANAaAA==.Anonymus:BAACLgAFFH8JAAIEAAMJ0BoFKwD5AAAEAAMJ0BoFKwD5AAAuAAQKfxgAAwQACQlKHaQPAEACAAQACAksHqQPAEACAAUAAgmiEBuIAEcAAAAA.',
Ar='Ara:BAACLgAFFH8MAAMBAAQJlBFxPQAsAQABAAQJlBFxPQAsAQAGAAEJiQMjMwBBAAAuAAQKfy4AAgEACQmhIOsOANYCAAEACQmhIOsOANYCAAAA.Ardiir:BAAALgAECgEJAgABLgAECgQJDQAHAAAAAA==.Ardwin:BAAALgADCgEJAQABLgAECgYJGQAIAHkIAA==.',
As='Ashgrove:BAAALgAECgUJCAAAAA==.',
Av='Avigar:BAAALgADCgEJAwAAAA==.',
Az='Azzinoth:BAAALgAECgIJAgAAAA==.',
Ba='Bambarrok:BAABLgAECn8XAAIJAAkJSQbkewBAAQAJAAkJSQbkewBAAQAAAA==.Bangan:BAAALgAECgYJEgAAAA==.',
Be='Belakor:BAAALgAECgYJBgAAAA==.Bep:BAAALgAECgYJDAABLgAECgkJGgAIADEVAA==.Bepragosa:BAABLgAECn8aAAIIAAkJMRWkCAA3AgAIAAkJMRWkCAA3AgAAAA==.',
Bi='Binpharteen:BAAALgADCgkJGgAAAA==.',
Bl='Blaque:BAAALgADCgcJBwABLgAECggJFQAKABoMAA==.',
Br='Brimscythe:BAAALgAECgEJAgABLgAECggJFwAFABAfAA==.Brownbelt:BAABLgAECn9GAAILAAkJGx0nCwCzAgALAAkJGx0nCwCzAgAAAA==.Brîn:BAAALgAECgUJCQAAAA==.',
Bu='Buteihunter:BAACLgAFFH8KAAIBAAMJMhwCTwAFAQABAAMJMhwCTwAFAQAuAAQKfzcABAEACQnLIlYLAPYCAAEACQnLIlYLAPYCAAMAAQnvC0WIADQAAAYAAQkSB6dlADAAAAAA.',
Ca='Cadranak:BAABLgAECn8wAAIMAAkJ2RLbQgC8AQAMAAkJ2RLbQgC8AQAAAA==.Caiyenthi:BAABLgAECn8nAAIBAAgJkQ+cYgB8AQABAAgJkQ+cYgB8AQAAAA==.Calliesue:BAAALgAECgIJAgAAAA==.Camgor:BAAALgADCgEJAQABLgAECgYJGQAIAHkIAA==.Carfalis:BAAALgADCggJCQAAAA==.',
Ch='Chelali:BAABLgAECn8XAAQLAAkJ8RVsJQAtAgALAAgJ/BZsJQAtAgANAAUJ5BDeLAATAQAOAAEJNAgqUQA0AAAAAA==.Chelly:BAAALgAECgEJAQABLgAECgkJFwALAPEVAA==.Chicharrone:BAAALgAECgYJEgAAAA==.Chizaru:BAACLgAFFH8MAAIPAAQJuRXDIgADAQAPAAQJuRXDIgADAQAuAAQKfyUAAw8ACQlbHmkHABQDAA8ACQlbHmkHABQDABAAAwkyAURNADUAAAAA.Chlorophyll:BAAALgADCgQJBQAAAA==.Chyntobelt:BAABLgAECn8kAAIRAAcJhAVExQD0AAARAAcJhAVExQD0AAABLgAECgkJRgALABsdAA==.',
Co='Copyright:BAAALgAECgEJAQAAAA==.',
Cr='Creep:BAAALgAECgYJEAAAAA==.Cryption:BAABLgAECn8VAAIBAAgJkhQEOADOAQABAAgJkhQEOADOAQAAAA==.',
['Cú']='Cúchulainn:BAAALgAECgYJDQAAAA==.',
Da='Daelyn:BAABLgAECn8YAAIBAAcJvw0mhwArAQABAAcJvw0mhwArAQAAAA==.Dalhma:BAAALgAFFAIJAgAAAA==.Dallma:BAAALgAFFAYJCgABLgAFFAIJAgAHAAAAAQ==.Dallmia:BAAALgAFFAMJAwABLgAFFAIJAgAHAAAAAQ==.Dane:BAAALgAECgIJAgAAAA==.Dayaris:BAABLgAECn8dAAIBAAgJ5AjKbwBcAQABAAgJ5AjKbwBcAQAAAA==.',
De='Deadbeat:BAAALgAECgUJBgAAAA==.Deafenned:BAABLgAECn8aAAISAAkJdx6gPQCBAgASAAkJdx6gPQCBAgABLgAFFAMJBwAMANEOAA==.Deaflynn:BAAALgAECgEJAwABLgAFFAMJBwAMANEOAA==.Deafnight:BAAALgAECgIJBAABLgAFFAMJBwAMANEOAA==.Demonbep:BAAALgADCgQJBAABLgAECgkJGgAIADEVAA==.Demonicpower:BAAALgAECgYJBgAAAA==.Derrington:BAABLgAECn8kAAIIAAcJkSFdBAA1AgAIAAcJkSFdBAA1AgABLgAECggJFwAFABAfAA==.Destinyetwo:BAAALgAECgEJAQAAAA==.Dett:BAABLgAECn8VAAITAAcJZQj9VADhAAATAAcJZQj9VADhAAAAAA==.',
Di='Diamante:BAACLgAFFH8UAAIUAAQJZRvkKwArAQAUAAQJZRvkKwArAQAuAAQKfyoAAhQACQlBFsUyAOQBABQACQlBFsUyAOQBAAAA.',
Dk='Dkvayce:BAAALgADCgYJBgAAAA==.',
Dr='Dragqueene:BAABLgAFFH8GAAIVAAQJQATaPgDHAAAVAAQJQATaPgDHAAAAAA==.Drakluz:BAAALgADCgEJAQAAAA==.Drakner:BAABLgAECn8xAAMVAAgJKw4GNQBbAQAVAAgJKw4GNQBbAQAWAAQJBQJMMgCEAAAAAA==.Drellin:BAAALgAECgEJBAABLgAECggJFwAFABAfAA==.Dremu:BAABLgAECn8zAAMXAAkJ/R4TCQDAAgAXAAkJ/R4TCQDAAgACAAMJEw9doACJAAAAAA==.',
Du='Duraz:BAABLgAECn8jAAICAAkJQg5hSQBmAQACAAkJQg5hSQBmAQAAAA==.',
Dy='Dysraxis:BAAALgADCgEJAQAAAA==.',
Ee='Eerie:BAAALgAECgIJBgAAAA==.',
Eg='Eggar:BAAALgAECggJCAABLgAECgkJLgARAEYWAA==.',
El='Elahna:BAAALgADCgcJDQAAAA==.Elalia:BAABLgAECn8ZAAIIAAYJeQhBHgCzAAAIAAYJeQhBHgCzAAAAAA==.Elamaun:BAABLgAECn8/AAMPAAgJ7Rq5EwBwAgAPAAgJ7Rq5EwBwAgAYAAMJQgOeUwFYAAAAAA==.Elereia:BAAALgAECgEJAQAAAA==.Eltiana:BAAALgAECgUJCwAAAA==.',
En='Energy:BAAALgADCgQJBwABLgAFFAMJBQARAN4XAA==.English:BAABLgAECn8VAAIKAAgJGgy6NQA+AQAKAAgJGgy6NQA+AQAAAA==.',
Ep='Ephex:BAAALgADCgcJGQAAAA==.Ephyiana:BAAALgADCgcJCAAAAA==.Epic:BAAALgAECgYJEAAAAA==.',
Er='Errimys:BAAALgADCgUJBQAAAA==.Ertraz:BAAALgAECgEJAgAAAA==.',
Es='Essense:BAAALgADCgcJBwAAAA==.Esçanor:BAAALgADCgUJBQAAAA==.',
Et='Etania:BAAALgAECgYJCQAAAA==.',
Ev='Evhomang:BAABLgAFFH8HAAIVAAQJ6hAKMQD7AAAVAAQJ6hAKMQD7AAAAAA==.',
Fa='Faelyna:BAABLgAECn8/AAIGAAgJ4BT8FwDiAQAGAAgJ4BT8FwDiAQAAAA==.Fang:BAAALgADCgEJAQAAAA==.',
Fe='Fearbear:BAAALgAECgUJBgAAAA==.Felnut:BAAALgADCgEJAQAAAA==.',
Fi='Finniel:BAAALgADCgEJAQAAAA==.',
Fl='Flash:BAAALgADCgMJAQAAAA==.',
Fo='Foix:BAAALgADCgcJDwAAAA==.Forged:BAACLgAFFH8IAAIYAAMJxROpZwDZAAAYAAMJxROpZwDZAAAuAAQKfysAAhgACAnzHxEpAIECABgACAnzHxEpAIECAAAA.',
Ga='Gaerne:BAAALgADCgEJAQAAAA==.',
Gi='Githyanki:BAAALgADCgkJCQAAAA==.',
Gl='Glabberghoul:BAABLgAECn8sAAIVAAkJQhRxIwC+AQAVAAkJQhRxIwC+AQAAAA==.',
Go='Goodhead:BAAALgADCgMJBAAAAA==.',
Gr='Grangladesh:BAAALgAECgEJAgABLgAECgQJDQAHAAAAAA==.Grangmage:BAAALgAECgQJDQAAAA==.Grimvault:BAAALgAECgEJAQABLgAECggJFwAFABAfAA==.Griogair:BAAALgADCgYJFQABLgAECgYJGQAIAHkIAA==.',
Gu='Gultir:BAAALgAECgcJCQAAAA==.',
Ha='Hacelian:BAAALgAECgEJAwAAAA==.Harper:BAAALgADCgcJBwAAAA==.',
He='Heetseeker:BAAALgAECgQJCAABLgAECgkJHQAUAMQgAA==.',
Hn='Hnoa:BAAALgADCgcJDwAAAA==.',
Ho='Hoggins:BAAALgADCgUJBQABLgADCgcJBwAHAAAAAA==.Holyverdict:BAABLgAECn8XAAIPAAkJUSWdBQASAwAPAAkJUSWdBQASAwAAAA==.',
Ic='Icaina:BAABLgAECn8vAAIUAAkJoB8FFAB1AgAUAAkJoB8FFAB1AgAAAA==.',
In='Incinderella:BAAALgADCgEJAQABLgAECgYJDgAHAAAAAA==.Interval:BAAALgADCgcJDgABLgAECgkJPAAYADsfAA==.',
Is='Islands:BAAALgADCgIJAgAAAA==.',
Ja='Jadani:BAABLgAECn8jAAIIAAgJfBGUDABxAQAIAAgJfBGUDABxAQAAAA==.',
Je='Jeisa:BAABLgAECn8tAAMQAAgJQxFhFgBtAQAQAAgJkhBhFgBtAQAYAAYJQA0B2QDkAAAAAA==.Jelyn:BAAALgAECgYJBgAAAA==.',
Ji='Jimbonereus:BAAALgADCgIJAgAAAA==.Jingshei:BAAALgAECgEJAgABLgAECgcJCgAHAAAAAA==.',
Jo='Jordyevoker:BAAALgAECggJDQAAAA==.',
Ju='Juanns:BAAALgAECgYJDgAAAA==.',
Ka='Kalchee:BAAALgADCgIJAgABLgAFFAMJAwAHAAAAAA==.Kallotera:BAABLgAECn8tAAMNAAgJgw5UIABYAQANAAgJgw5UIABYAQALAAUJ4QbQcAD1AAAAAA==.Kastoria:BAAALgADCgkJGQAAAA==.Katnipp:BAACLgAFFH8FAAIBAAMJZw0qYADcAAABAAMJZw0qYADcAAAuAAQKfzMAAgEACQmMHZAYAI4CAAEACQmMHZAYAI4CAAAA.Katnyss:BAAALgAECgYJDQAAAA==.Kaylazune:BAABLgAECn8zAAMZAAgJXAzlLABvAQAZAAgJAwvlLABvAQAaAAYJpAugQQDhAAAAAA==.',
Ke='Kellwynne:BAAALgAECgMJAwAAAA==.Keramoon:BAAALgADCgUJBQAAAA==.Keyleth:BAAALgAECgEJAQAAAA==.',
Kh='Khrala:BAABLgAECn8uAAMRAAkJRha9MQA1AgARAAkJRha9MQA1AgAbAAIJHgxmTABcAAAAAA==.',
Ki='Kiye:BAACLgAFFH8XAAIBAAYJARWbHgCBAQABAAYJARWbHgCBAQAuAAQKfykAAgEACQnaG3gPAL8CAAEACQnaG3gPAL8CAAAA.',
Ko='Koren:BAAALgADCgMJAgAAAA==.',
Kr='Krenko:BAABLgAECn8VAAIRAAkJgAq+aQCQAQARAAkJgAq+aQCQAQAAAA==.',
Ku='Kung:BAABLgAECn8XAAMFAAgJEB92DAB6AgAFAAgJEB92DAB6AgAEAAYJBQ25QgDsAAAAAA==.Kuuro:BAABLgAECn86AAIUAAgJNxaNMgDlAQAUAAgJNxaNMgDlAQAAAA==.',
La='Lanister:BAAALgADCgQJBAAAAA==.Lattymag:BAAALgAECgcJDgAAAA==.Laughystabby:BAAALgAECgkJDQAAAA==.',
Le='Leibniz:BAABLgAECn8wAAIcAAgJCyCFAwB6AgAcAAgJCyCFAwB6AgAAAA==.Leisa:BAABLgAECn85AAIBAAgJAxiKMwAKAgABAAgJAxiKMwAKAgAAAA==.Lelwindae:BAAALgAECgYJCQAAAA==.',
Li='Lifemoon:BAABLgAECn8ZAAISAAcJEArwrgAgAQASAAcJEArwrgAgAQAAAA==.Lightgiver:BAAALgAECgYJDQAAAA==.Lighthoof:BAABLgAECn8gAAMYAAkJNx84FQDrAgAYAAkJNx84FQDrAgAQAAQJVBsaGwA1AQAAAA==.Lightiuz:BAABLgAECn8eAAMCAAYJBhbqRQCKAQACAAYJBhbqRQCKAQAXAAQJZQGccgBXAAAAAA==.Liminara:BAEBLgAFFH8MAAMQAAUJrRBHAwC4AAAYAAUJiA6sTAAQAQAQAAMJfQtHAwC4AAABLgAFFAcJIQABAOwcAA==.Linaste:BAAALgAECgYJDAAAAA==.Lirah:BAAALgAECggJCQABLgAFFAYJFwABAAEVAA==.Lissandra:BAAALgAECgEJAQAAAA==.Lividcow:BAAALgAECgYJBgAAAA==.Lividzdk:BAABLgAECn9CAAMRAAkJBiEJEADqAgARAAkJBiEJEADqAgAbAAIJOgzFUABPAAAAAA==.',
Lo='Lonaldo:BAAALgAECgEJAQAAAA==.Lowpop:BAAALgADCgQJBAABLgAECgcJFgAFAJwPAA==.',
Lu='Lulu:BAABLgAFFH8SAAMFAAYJwyKpAwD6AQAFAAYJwyKpAwD6AQAdAAEJ6QEXbAAhAAAAAA==.',
Ly='Lynoia:BAAALgAECgcJCgAAAA==.',
Ma='Malarus:BAAALgADCgEJAQAAAA==.Mandevu:BAAALgAECgUJBwAAAA==.Manknus:BAABLgAECn88AAILAAkJJRXLGQAdAgALAAkJJRXLGQAdAgAAAA==.Mannydemons:BAAALgADCgUJBgAAAA==.Mantequilla:BAABLgAECn8YAAIRAAcJTxzFSQAWAgARAAcJTxzFSQAWAgAAAA==.Manthrax:BAABLgAECn80AAIUAAkJtwlfSwB+AQAUAAkJtwlfSwB+AQAAAA==.Marix:BAAALgADCgEJAQAAAA==.',
Me='Megami:BAAALgADCgEJAgAAAA==.Mexecutioner:BAAALgADCgIJAgABLgAECgkJHAAFAKEKAA==.',
Mi='Missmolt:BAABLgAECn87AAIeAAgJmybDAAAlAwAeAAgJmybDAAAlAwAAAA==.',
Mo='Molting:BAAALgAECgMJBAAAAA==.',
My='Mykie:BAAALgAECgcJDgAAAA==.Mylor:BAABLgAECn87AAMPAAkJlBTxHAAZAgAPAAkJlBTxHAAZAgAYAAEJvw/2SAEwAAAAAA==.Myrddral:BAABLgAECn85AAIbAAgJ9COqBQDMAgAbAAgJ9COqBQDMAgAAAA==.Mystifeyed:BAABLgAECn8mAAMfAAkJdQoVMwDWAAAgAAcJYgmPFgBQAQAfAAgJHQgVMwDWAAAAAA==.',
['Mü']='Mürsaat:BAABLgAECn82AAIYAAgJpxxiLwBAAgAYAAgJpxxiLwBAAgAAAA==.',
Na='Namrekcah:BAAALgADCgcJDgABLgAFFAgJNgAbAJYgAA==.Narra:BAAALgAECgQJBQABLgADCgcJBwAHAAAAAA==.',
Ne='Nebalicious:BAAALgADCgcJDAABLgAECgYJDQAHAAAAAA==.Nekonomiya:BAAALgADCgMJAwAAAA==.',
Ni='Nightlevels:BAABLgAECn85AAMZAAkJ2iORAgCMAwAZAAkJ2iORAgCMAwAaAAEJFCL/cgBcAAAAAA==.Nimbledragon:BAAALgAECgIJAgAAAA==.',
Nt='Ntayu:BAABLgAECn87AAIBAAgJWw3BXACLAQABAAgJWw3BXACLAQAAAA==.',
Ol='Olizia:BAABLgAECn8WAAIRAAcJiBKYdQCaAQARAAcJiBKYdQCaAQAAAA==.',
On='Onaga:BAABLgAECn8XAAIYAAcJIwQ07gDJAAAYAAcJIwQ07gDJAAAAAA==.',
Op='Opex:BAACLgAFFH8HAAIBAAMJGQWgbAC9AAABAAMJGQWgbAC9AAAuAAQKfxoAAwEACQnJDKJIAJABAAEACQnJDKJIAJABAAMAAQlRAH2bABMAAAAA.Opheliabutts:BAAALgAECgQJBgAAAA==.',
Or='Oril:BAAALgAECgkJEQAAAA==.',
Pa='Paw:BAAALgADCgEJAgAAAA==.',
Pe='Penjei:BAAALgADCgYJBgAAAA==.Perkyblade:BAAALgAECggJEwAAAA==.',
Ph='Philomel:BAACLgAFFH8HAAIMAAMJ0Q6AZwC3AAAMAAMJ0Q6AZwC3AAAuAAQKfxwAAgwACAk/G84rAE8CAAwACAk/G84rAE8CAAAA.',
Pi='Piekal:BAAALgAECgcJBwAAAA==.Pixamoo:BAAALgADCgUJCAAAAA==.',
Pl='Planeswalker:BAAALgADCgYJBgAAAA==.',
Po='Podnuh:BAAALgADCgIJAgAAAA==.Poxic:BAAALgAECgQJBAAAAA==.',
Pr='Priesthealz:BAAALgAECgcJDAABLgAECgkJMAAEAIIdAA==.Pritt:BAAALgADCgcJDQABLgAECgcJEAAHAAAAAA==.',
Ps='Psyvival:BAAALgAECgEJAQAAAA==.',
Qu='Quazu:BAAALgAECgcJBwAAAA==.',
Ra='Radagahst:BAAALgAECgcJDwAAAA==.Rarngorm:BAABLgAECn8iAAIhAAgJqheACgDSAQAhAAgJqheACgDSAQAAAA==.Ravinar:BAABLgAECn8eAAIiAAkJAxOTAwDaAQAiAAkJAxOTAwDaAQAAAA==.Raàm:BAAALgAECggJEAAAAA==.',
Re='Reardain:BAAALgAECgcJEgAAAA==.Received:BAAALgAECgYJCAAAAA==.Relia:BAABLgAECn8YAAMKAAkJyQ/IIQDJAQAKAAgJNhDIIQDJAQAZAAEJKAb7dAA3AAAAAA==.Remedy:BAAALgADCgcJBwAAAA==.',
Ri='Richardparkr:BAAALgAECgEJAQAAAA==.Rillty:BAAALgAECgQJBgAAAA==.Riverwind:BAAALgAECgUJCgABLgAECgkJHQAUAMQgAA==.',
Rj='Rj:BAAALgADCgMJAwAAAA==.',
Ro='Romulus:BAABLgAECn8sAAICAAgJ4xTALgDnAQACAAgJ4xTALgDnAQAAAA==.',
Ry='Ryo:BAAALgAECgIJAgAAAA==.',
Sa='Safyra:BAAALgADCgYJCAAAAA==.Sakoian:BAAALgAFFAEJAQAAAA==.Sakuf:BAAALgADCgcJBwAAAA==.Salana:BAAALgADCgQJBwAAAA==.Santofrancis:BAABLgAECn8cAAIFAAkJoQp0MABCAQAFAAkJoQp0MABCAQAAAA==.Sarbarola:BAAALgAECgMJBAAAAA==.Save:BAAALgAECgIJBAABLgAFFAEJAQAHAAAAAA==.',
Se='Seraie:BAAALgAECgcJCQAAAA==.',
Sh='Shadethrower:BAABLgAECn8WAAIaAAkJ9hqVCwCXAgAaAAkJ9hqVCwCXAgAAAA==.Shallbedo:BAAALgAECgYJDQABLgAFFAMJBgAVAJENAA==.Shallvoker:BAACLgAFFH8GAAMVAAMJkQ18RACxAAAVAAMJkQ18RACxAAAWAAEJzAPNDwA6AAAuAAQKfyYAAxYACAnRGuwKAC0CABYACAkEF+wKAC0CABUABAmLGcpEABMBAAAA.Shazammy:BAAALgADCgMJBAAAAA==.Shmalexia:BAAALgAECgMJAwAAAA==.',
Si='Siatraler:BAAALgAECgkJEgAAAA==.Sigarette:BAACLgAFFH82AAIbAAgJliAAAwCHAgAbAAgJliAAAwCHAgAuAAQKfzkAAhsACAnXJJkCAEIDABsACAnXJJkCAEIDAAAA.Silverspoon:BAAALgAECgIJAwAAAA==.Sinardi:BAABLgAECn8qAAMjAAcJKRwHFADvAQAjAAcJKRwHFADvAQAkAAQJmg2gIgCEAAAAAA==.',
Sk='Skoobz:BAAALgAECgEJAgAAAA==.Skubasteve:BAAALgAECgYJDwAAAA==.Skydragon:BAAALgAECgYJBgAAAA==.Skylock:BAABLgAECn8WAAQcAAkJiwySDACOAQAcAAkJFAySDACOAQAIAAYJkAeAHwCsAAAJAAMJOgJqEQFUAAAAAA==.Skymane:BAABLgAECn8VAAMKAAYJmw/XNABEAQAKAAYJmw/XNABEAQAaAAEJfgJdhQAsAAAAAA==.',
Sn='Snaggletooth:BAAALgADCgEJAQAAAA==.',
So='Solar:BAAALgAFFAMJAwAAAA==.Sorce:BAAALgAECgYJBwABLgAFFAQJFAAUAGUbAA==.Sovix:BAAALgAECgEJBAAAAA==.Sovo:BAACLgAFFH8YAAISAAcJbRdlJADpAQASAAcJbRdlJADpAQAuAAQKfysAAhIACQlEIpcdAP8CABIACQlEIpcdAP8CAAAA.',
Sp='Spiritdáncer:BAAALgADCgEJAQAAAA==.',
Sq='Squshmepure:BAAALgAECgYJAgAAAA==.',
St='Starrin:BAAALgAECgcJEgAAAA==.Steaknquake:BAABLgAECn9HAAIUAAkJjSEBBQBhAwAUAAkJjSEBBQBhAwAAAA==.',
Su='Sumdumfun:BAAALgAECgMJAwAAAA==.Sunflower:BAAALgAECgYJDgAAAA==.',
Sv='Svaha:BAAALgAECgIJAgAAAA==.',
Sy='Sybri:BAABLgAECn8WAAMBAAgJ5RgjOQDKAQABAAcJNRojOQDKAQADAAUJ6wsrWQDhAAAAAA==.Sylvandel:BAABLgAECn87AAIDAAgJMxqHBgAmAgADAAgJMxqHBgAmAgAAAA==.Sylvrshado:BAAALgAECgIJAgAAAA==.',
Ta='Taberna:BAAALgAECgMJAwAAAA==.Talthis:BAAALgAECgIJAgAAAA==.',
Te='Teagen:BAABLgAECn81AAMCAAkJgggEVQA5AQACAAkJgggEVQA5AQAXAAIJUgt7dQBXAAAAAA==.',
Th='Thalius:BAABLgAECn86AAIRAAgJBBJjXQCtAQARAAgJBBJjXQCtAQAAAA==.Thorandaal:BAABLgAECn8dAAMYAAgJVQgzogAxAQAYAAgJVQgzogAxAQAPAAYJvAiKUQDwAAAAAA==.Thunderbuddy:BAAALgADCgEJAQAAAA==.',
Ti='Tisbish:BAAALgADCgIJAgAAAA==.',
To='Tome:BAABLgAECn8hAAQDAAkJ6SYDAAAbBAADAAkJ3CYDAAAbBAAGAAkJxCbTAABsAwABAAEJEybn9gBjAAAAAA==.Tometv:BAAALgAECgcJBgABLgAECgkJIQADAOkmAA==.Toomanydeths:BAABLgAECn8+AAMbAAkJsQ9HHQBrAQAbAAkJsQ9HHQBrAQARAAYJ3QzhugACAQAAAA==.',
Tr='Trunx:BAAALgAECgQJBQABLgAECgkJHwAdAN4jAA==.',
Ty='Tye:BAAALgAECgcJEQAAAA==.Tyyle:BAAALgADCgYJBgAAAA==.',
['Tá']='Tálos:BAAALgAECgEJBAAAAA==.',
Ul='Uldear:BAAALgADCgYJCwAAAA==.',
Un='Unbuttered:BAAALgAECgIJBAAAAA==.Uninvite:BAAALgAECgQJBAAAAA==.',
Ur='Ursusmanny:BAAALgAECgcJCwAAAA==.',
Va='Vaelthyeth:BAAALgADCgUJBQAAAA==.Valkyrie:BAAALgAECgYJBgABLgAECgkJMAAEAIIdAA==.Vandarin:BAAALgADCgcJGgABLgAECgYJGQAIAHkIAA==.Vanthrall:BAAALgAECgQJCgAAAA==.Vayce:BAABLgAECn8yAAMlAAkJ5iEXAwCKAgAlAAgJyCIXAwCKAgAmAAcJRyL/GAA9AgAAAA==.',
Ve='Velysa:BAABLgAECn8+AAMQAAkJQxcxCgAlAgAQAAkJQxcxCgAlAgAYAAIJOgkyHgFgAAAAAA==.Veniea:BAAALgADCgEJAQABLgAECgcJCgAHAAAAAA==.',
Vi='Vizago:BAAALgADCgEJAQAAAA==.',
Vo='Vogekth:BAAALgAECgUJCwAAAA==.',
['Vÿ']='Vÿktor:BAAALgADCgYJBgAAAA==.',
Wa='Warseeker:BAABLgAECn8dAAMUAAkJxCAlCADzAgAUAAkJxCAlCADzAgATAAQJ1w5JYgC6AAAAAA==.Watlmonk:BAAALgADCgIJAgAAAA==.',
We='Weatherworn:BAABLgAECn89AAMUAAgJnxcZJwAgAgAUAAgJnxcZJwAgAgATAAEJEAYquAAhAAAAAA==.',
Wi='Wirhlanir:BAAALgADCgkJCQAAAA==.',
Xe='Xemu:BAAALgAECgQJBAAAAA==.Xenferos:BAAALgADCgcJDAAAAA==.Xerber:BAAALgADCgYJDQABLgAECgYJGQAIAHkIAA==.',
Xi='Xiro:BAAALgAECgUJEwAAAA==.',
Yo='Yoril:BAAALgAECgcJDgAAAA==.',
Za='Zagihex:BAAALgAECgcJBwAAAA==.Zagiroth:BAABLgAECn8sAAMMAAkJFiFkDQDYAgAMAAkJFiFkDQDYAgAkAAEJFhthJwBLAAAAAA==.Zalthanos:BAAALgADCgEJAQAAAA==.Zarack:BAAALgADCgYJBAABLgAECgYJGQAIAHkIAA==.',
Ze='Zebraman:BAABLgAECn8VAAICAAgJDBIRQgCGAQACAAgJDBIRQgCGAQAAAA==.Zeraida:BAAALgADCgcJDAAAAA==.',
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
