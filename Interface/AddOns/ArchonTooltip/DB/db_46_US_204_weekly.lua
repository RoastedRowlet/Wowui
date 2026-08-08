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

local lookup = {'Hunter-BeastMastery','Druid-Restoration','Hunter-Marksmanship','Monk-Brewmaster','Monk-Windwalker','Hunter-Survival','Mage-Frost','Warlock-Destruction','Warlock-Demonology','Priest-Shadow','Warrior-Fury','DemonHunter-Devourer','Warrior-Arms','Warrior-Protection','Paladin-Holy','Paladin-Protection','DeathKnight-Unholy','Unknown-Unknown','Shaman-Elemental','Shaman-Restoration','Rogue-Subtlety','Evoker-Augmentation','Evoker-Devastation','Druid-Balance','Paladin-Retribution','DeathKnight-Blood','Priest-Discipline','Priest-Holy','Mage-Arcane','Warlock-Affliction','Monk-Mistweaver','Rogue-Outlaw','Druid-Guardian','Druid-Feral','DeathKnight-Frost','Mage-Fire','Shaman-Enhancement','DemonHunter-Havoc','DemonHunter-Vengeance','Rogue-Assassination',}
local provider = {region='US',realm='SteamwheedleCartel',name='US',type='weekly',zone=46,date='2026-08-04',data={Aa='Aalwein:BAABLgAECn8sAAIBAAkJsx8EGwCDAgABAAkJsx8EGwCDAgAAAA==.',
Ae='Aesculapius:BAACLgAFFH8QAAICAAUJzAYmFADYAAACAAUJzAYmFADYAAAuAAQKfzcAAgIACQm3Gf8UAKICAAIACQm3Gf8UAKICAAAA.',
Al='Aladia:BAAALgADCgMJAgAAAA==.Alfrus:BAAALgAECgYJBgAAAA==.Aloisious:BAAALgAECgEJAQAAAA==.Alutoh:BAAALgAFFAEJAQAAAA==.',
Am='Amarii:BAABLgAECn8/AAIDAAkJjRCcAQCpAQADAAkJjRCcAQCpAQAAAA==.Amorash:BAAALgADCgEJAQAAAA==.',
An='Angora:BAAALgADCgIJAgAAAA==.Annabeth:BAAALgAECgYJCwABLgAFFAMJCQAEANAaAA==.Anonymus:BAACLgAFFH8JAAIEAAMJ0BoMLAD5AAAEAAMJ0BoMLAD5AAAuAAQKfxgAAwQACQlKHd8PAD8CAAQACAksHt8PAD8CAAUAAgmiEJmKAEcAAAAA.',
Ar='Ara:BAACLgAFFH8MAAMBAAQJlBEGQQArAQABAAQJlBEGQQArAQAGAAEJiQNeNABBAAAuAAQKfy4AAgEACQmhIHYPANUCAAEACQmhIHYPANUCAAAA.Ardiir:BAAALgAECgMJBgABLgAECgUJFwAHAA8VAA==.Ardwin:BAAALgADCgEJAQABLgAECgYJGQAIAHkIAA==.',
As='Ashgrove:BAAALgAECgUJCAAAAA==.Asteryn:BAAALgADCggJCwAAAA==.',
Av='Avigar:BAAALgADCgEJAwAAAA==.',
Az='Azzinoth:BAAALgAECgIJAgAAAA==.',
Ba='Bakeneko:BAAALgADCgMJBgAAAA==.Bambarrok:BAABLgAECn8XAAIJAAkJSQbgfQA9AQAJAAkJSQbgfQA9AQAAAA==.Bangan:BAAALgAFFAIJAgAAAA==.',
Be='Belakor:BAAALgAECgYJBgAAAA==.Bep:BAAALgAECgYJDAABLgAECgkJGgAIADEVAA==.Bepragosa:BAABLgAECn8aAAIIAAkJMRWkCAA3AgAIAAkJMRWkCAA3AgAAAA==.',
Bi='Binpharteen:BAAALgAECgYJCQAAAA==.',
Bl='Blaque:BAAALgADCgcJBwABLgAECggJFQAKABoMAA==.Blindfaith:BAAALgAECgYJBgAAAA==.',
Br='Brimscythe:BAAALgAECgEJAgABLgAECgkJMAAFAOofAA==.Brownbelt:BAACLgAFFH8RAAILAAQJKg8XEgALAQALAAQJKg8XEgALAQAuAAQKf1YAAgsACQlPHmECAFQCAAsACQlPHmECAFQCAAAA.Brîn:BAAALgAECgYJEQAAAA==.',
Bu='Buteihunter:BAACLgAFFH8OAAMBAAMJrxzCUgAEAQABAAMJMhzCUgAEAQAGAAIJrhKbEACWAAAuAAQKfzcABAEACQnLIs8LAPUCAAEACQnLIs8LAPUCAAMAAQnvC0WIADQAAAYAAQkSByxnADAAAAAA.',
['Bà']='Bàhamut:BAAALgAECgUJBQAAAA==.',
Ca='Cadranak:BAABLgAECn8wAAIMAAkJ2RKsQwC9AQAMAAkJ2RKsQwC9AQAAAA==.Caiyenthi:BAABLgAECn8nAAIBAAgJkQ+JZAB8AQABAAgJkQ+JZAB8AQAAAA==.Calliesue:BAAALgAECgIJAgAAAA==.Camgor:BAAALgADCgEJAQABLgAECgYJGQAIAHkIAA==.Carfalis:BAAALgADCggJCQAAAA==.',
Ch='Chelali:BAABLgAECn8XAAQLAAkJ8RVsJQAtAgALAAgJ/BZsJQAtAgANAAUJ5BDILQATAQAOAAEJNAiRUgA0AAAAAA==.Chelly:BAAALgAECgEJAQABLgAECgkJFwALAPEVAA==.Chicharrone:BAAALgAECgYJEgAAAA==.Chihiro:BAAALgADCgYJCAAAAA==.Chizaru:BAACLgAFFH8UAAIPAAQJrhu8IwACAQAPAAQJrhu8IwACAQAuAAQKfzUAAw8ACQmgH5YHABIDAA8ACQmgH5YHABIDABAAAwkyAXdOADUAAAAA.Chlorophyll:BAAALgAECgMJAwAAAA==.Chyntobelt:BAABLgAECn8kAAIRAAcJhAV5yQDxAAARAAcJhAV5yQDxAAABLgAFFAQJEQALACoPAA==.',
Cl='Cleopawtra:BAAALgADCgEJAQAAAA==.',
Co='Copyright:BAAALgAECgEJAQAAAA==.',
Cr='Creep:BAAALgAECgYJEAAAAA==.Cryption:BAABLgAECn8VAAIBAAgJkhQEOADOAQABAAgJkhQEOADOAQAAAA==.',
Cs='Cs:BAAALgAECgEJAQAAAA==.',
['Cú']='Cúchulainn:BAAALgAECgYJDQAAAA==.',
Da='Daelyn:BAABLgAECn8ZAAIBAAgJJw0AigArAQABAAgJJw0AigArAQAAAA==.Dalhma:BAAALgAFFAIJAgAAAA==.Dallma:BAAALgAFFAgJDAABLgAFFAIJAgASAAAAAQ==.Dallmia:BAAALgAFFAMJAwABLgAFFAIJAgASAAAAAQ==.Dane:BAAALgAECgIJAgAAAA==.Danilaria:BAAALgAECgMJAwAAAA==.Dayaris:BAABLgAECn8jAAIBAAgJXQq4bABoAQABAAgJXQq4bABoAQAAAA==.',
De='Deadbeat:BAAALgAECgUJBgAAAA==.Deadfronty:BAAALgAECgYJBgAAAA==.Deafenned:BAABLgAECn8aAAIHAAkJdx6gPQCBAgAHAAkJdx6gPQCBAgABLgAFFAMJBwAMANEOAA==.Deaflynn:BAAALgAECgEJAwABLgAFFAMJBwAMANEOAA==.Deafnight:BAAALgAECgIJBAABLgAFFAMJBwAMANEOAA==.Deathgrip:BAAALgAECgUJBQAAAA==.Deliquesce:BAAALgADCggJCgAAAA==.Demonbep:BAAALgADCgQJBAABLgAECgkJGgAIADEVAA==.Demonicpower:BAAALgAECgYJCAAAAA==.Derrington:BAABLgAECn8kAAIIAAcJkSGMBAAzAgAIAAcJkSGMBAAzAgABLgAECgkJMAAFAOofAA==.Destinyetwo:BAAALgAECgEJAQAAAA==.Dett:BAABLgAECn8VAAITAAcJZQiWVgDhAAATAAcJZQiWVgDhAAAAAA==.',
Di='Diamante:BAACLgAFFH8ZAAIUAAYJ0RdsHwB3AQAUAAYJ0RdsHwB3AQAuAAQKfyoAAhQACQlBFp4zAOQBABQACQlBFp4zAOQBAAAA.',
Dk='Dkvayce:BAAALgADCgYJBgAAAA==.',
Do='Dos:BAAALgAECgQJBAABLgAFFAQJEQAVAEENAA==.',
Dr='Dragqueene:BAABLgAFFH8KAAIWAAUJQwUrQQDCAAAWAAUJQwUrQQDCAAAAAA==.Drakluz:BAAALgADCgEJAQAAAA==.Drakner:BAABLgAECn8xAAMWAAgJKw4PNgBYAQAWAAgJKw4PNgBYAQAXAAQJBQJMMgCEAAAAAA==.Drellin:BAAALgAECgEJBAABLgAECgkJMAAFAOofAA==.Dremu:BAABLgAECn9AAAMYAAkJUiH9AAAGAwAYAAkJUiH9AAAGAwACAAMJEw9doACJAAAAAA==.',
Du='Duraz:BAABLgAECn8jAAICAAkJQg4oSgBmAQACAAkJQg4oSgBmAQAAAA==.',
Dy='Dysraxis:BAAALgADCgEJAQAAAA==.',
['Dï']='Dïnhö:BAAALgAECgEJAQAAAA==.',
Ee='Eerie:BAAALgAECgIJBgAAAA==.',
Eg='Eggar:BAAALgAECggJCQABLgAECgkJMgARAA8YAA==.',
El='Elahna:BAAALgADCgcJDQAAAA==.Elalia:BAABLgAECn8ZAAIIAAYJeQjnHgCzAAAIAAYJeQjnHgCzAAAAAA==.Elamaun:BAABLgAECn9KAAMPAAgJCR0qAwAGAgAPAAgJCR0qAwAGAgAZAAMJQgOiWwFWAAAAAA==.Elereia:BAAALgAECgEJAQAAAA==.Eltiana:BAAALgAECgUJCwAAAA==.',
En='Energy:BAAALgADCgQJBwABLgAFFAMJCAARAH8fAA==.English:BAABLgAECn8VAAIKAAgJGgwINwA5AQAKAAgJGgwINwA5AQAAAA==.',
Ep='Ephex:BAAALgADCgcJGQAAAA==.Ephyiana:BAAALgADCgcJCAAAAA==.Epic:BAACLgAFFH8IAAMRAAUJsw4WMgAHAQARAAQJsw4WMgAHAQAaAAEJAADiOwAAAAAuAAQKfxQAAhEACAkgEDAdAMYAABEACAkgEDAdAMYAAAAA.',
Er='Errimys:BAAALgADCgUJBQAAAA==.Ertraz:BAAALgAECgEJAgAAAA==.',
Es='Essense:BAAALgADCgcJBwAAAA==.Esçanor:BAAALgADCgUJBQAAAA==.',
Et='Etania:BAAALgAECgYJCQAAAA==.',
Ev='Evhomang:BAABLgAFFH8KAAIWAAQJ+hiCJgA0AQAWAAQJ+hiCJgA0AQAAAA==.',
Fa='Faelyna:BAACLgAFFH8HAAIGAAIJTQj6EQCJAAAGAAIJTQj6EQCJAAAuAAQKf04AAgYACQn/EscCAJwBAAYACQn/EscCAJwBAAAA.Fang:BAAALgADCgEJAQAAAA==.',
Fe='Fearbear:BAAALgAECgUJBgAAAA==.Fearcode:BAAALgAFFAEJAQAAAA==.Felnut:BAAALgADCgEJAQAAAA==.Fevercat:BAAALgADCgEJAQAAAA==.',
Fi='Finniel:BAAALgADCgEJAQAAAA==.',
Fl='Flash:BAAALgADCgMJAQAAAA==.',
Fo='Foix:BAAALgADCgcJDwAAAA==.Fonkymonky:BAAALgAECgEJAQAAAA==.Forged:BAACLgAFFH8LAAIZAAQJxRNkRQCPAAAZAAQJxRNkRQCPAAAuAAQKfysAAhkACAnzHxEpAIECABkACAnzHxEpAIECAAAA.',
Fu='Fufufu:BAAALgADCgMJAQABLgAFFAYJGQAUANEXAA==.',
Ga='Gaerne:BAAALgADCgEJAQAAAA==.Galandrick:BAAALgADCgEJAQAAAA==.',
Gi='Githyanki:BAAALgADCgkJCQAAAA==.',
Gl='Glabberghoul:BAABLgAECn8sAAIWAAkJQhTsIwC9AQAWAAkJQhTsIwC9AQAAAA==.',
Go='Goobagoo:BAAALgADCgQJBAAAAA==.Goodhead:BAAALgADCgMJBAAAAA==.',
Gr='Grangladesh:BAAALgAECgEJAwABLgAECgUJFwAHAA8VAA==.Grangmage:BAABLgAECn8XAAIHAAUJDxVfHgDiAAAHAAUJDxVfHgDiAAAAAA==.Grangshammy:BAAALgAECgEJAgABLgAECgUJFwAHAA8VAA==.Grimvault:BAAALgAECgEJAQABLgAECgkJMAAFAOofAA==.Griogair:BAAALgADCgYJFQABLgAECgYJGQAIAHkIAA==.',
Gu='Gultir:BAAALgAECgcJCQAAAA==.',
Gy='Gypsyrose:BAAALgAECgEJAQAAAA==.',
Ha='Hacelian:BAAALgAECgEJAwAAAA==.Harper:BAAALgADCgcJBwAAAA==.',
He='Heetseeker:BAAALgAECgQJCAABLgAECgkJHQAUAMQgAA==.',
Hn='Hnoa:BAAALgADCgcJDwAAAA==.',
Ho='Hoggins:BAAALgADCgUJBQABLgADCgcJBwASAAAAAA==.Holyverdict:BAABLgAECn8XAAIPAAkJUSWdBQASAwAPAAkJUSWdBQASAwAAAA==.',
Ic='Icaina:BAABLgAECn8vAAIUAAkJoB8FFAB1AgAUAAkJoB8FFAB1AgAAAA==.',
In='Incinderella:BAAALgADCgEJAQABLgAECgYJDwASAAAAAA==.Interval:BAAALgADCgcJDgABLgAECgkJPAAZADsfAA==.',
Is='Isengard:BAAALgADCgEJAQAAAA==.Islands:BAAALgADCgIJAgAAAA==.',
Iv='Ivymyst:BAAALgAECgQJBAAAAA==.',
Ja='Jadani:BAABLgAECn8kAAIIAAkJYRLoDABwAQAIAAkJYRLoDABwAQAAAA==.Jadefire:BAAALgAECgUJBQAAAA==.',
Je='Jeisa:BAABLgAECn89AAMZAAkJuxW1CQDEAQAZAAgJ3hW1CQDEAQAQAAkJmRFKFgBxAQAAAA==.Jelyn:BAAALgAECgYJBgAAAA==.',
Jh='Jhedu:BAAALgAFFAEJAQAAAA==.',
Ji='Jimbonereus:BAAALgADCgIJAgAAAA==.Jingshei:BAAALgAECgEJAgABLgAECggJCwASAAAAAA==.',
Jo='Jordyevoker:BAAALgAECggJDQAAAA==.Jorkanji:BAAALgADCgIJAgAAAA==.',
Ju='Juanns:BAACLgAFFH8GAAIBAAIJ3BSkSACTAAABAAIJ3BSkSACTAAAuAAQKfxQABAEACAkdEY0eAOEAAAEACAkdEY0eAOEAAAYAAQmaCe8TADAAAAMAAQnWCDMPACAAAAAA.',
Ka='Kalchee:BAAALgADCgIJAgABLgAFFAMJCAAaAEEWAA==.Kallotera:BAABLgAECn8+AAMNAAkJexVkAQAeAgANAAkJexVkAQAeAgALAAUJ4QbQcAD1AAAAAA==.Kalthur:BAAALgAECgMJAwAAAA==.Karune:BAAALgAECgIJAgAAAA==.Kastoria:BAAALgAECgUJBQAAAA==.Katnipp:BAACLgAFFH8LAAIBAAMJFA+lNQDNAAABAAMJFA+lNQDNAAAuAAQKfzQAAgEACQmMHX0ZAI0CAAEACQmMHX0ZAI0CAAAA.Katnyss:BAAALgAECgYJDQAAAA==.Kaylazune:BAABLgAECn9CAAMbAAkJwgtICwAbAQAbAAkJjwpICwAbAQAcAAYJpAuQQgDhAAAAAA==.',
Ke='Kellwynne:BAAALgAECgMJAwAAAA==.Keramoon:BAAALgADCgUJBQAAAA==.Keyleth:BAAALgAECgEJAQAAAA==.',
Kh='Kharybdis:BAAALgAECgMJAwAAAA==.Khrala:BAABLgAECn8yAAMRAAkJDxiiMgA0AgARAAkJDxiiMgA0AgAaAAIJHgxkTQBbAAAAAA==.',
Ki='Kiye:BAACLgAFFH8aAAIBAAcJKRaUEQDXAQABAAcJKRaUEQDXAQAuAAQKfysAAgEACQlMHHgPAL8CAAEACQlMHHgPAL8CAAAA.',
Ko='Koren:BAAALgADCgMJAgAAAA==.',
Kr='Krenko:BAABLgAECn8VAAIRAAkJgAofbACNAQARAAkJgAofbACNAQAAAA==.',
Ku='Kung:BAABLgAECn8wAAMFAAkJ6h+PAQBnAgAFAAkJ6h+PAQBnAgAEAAgJ+xHJAwBOAQAAAA==.Kuuro:BAABLgAECn9WAAIUAAkJGBebBAAyAgAUAAkJGBebBAAyAgAAAA==.',
La='Lanister:BAAALgADCgQJBAAAAA==.Lattymag:BAABLgAECn8cAAIdAAkJ7QRIBQDEAAAdAAkJ7QRIBQDEAAAAAA==.Laughystabby:BAAALgAECgkJDQAAAA==.',
Le='Leibniz:BAABLgAECn9JAAIeAAkJriFKAAD8AgAeAAkJriFKAAD8AgAAAA==.Leisa:BAABLgAECn9VAAIBAAkJTBt0BQBOAgABAAkJTBt0BQBOAgAAAA==.Lekenzie:BAAALgAECgUJBQAAAA==.Lelwindae:BAAALgAECgYJCQAAAA==.',
Li='Lifemoon:BAABLgAECn8gAAIHAAgJTQ6RGgD9AAAHAAgJTQ6RGgD9AAAAAA==.Lightgiver:BAAALgAECgYJDQAAAA==.Lighthoof:BAABLgAECn8gAAMZAAkJNx84FQDrAgAZAAkJNx84FQDrAgAQAAQJVBsaGwA1AQAAAA==.Lightiuz:BAABLgAECn8eAAMCAAYJBhbqRQCKAQACAAYJBhbqRQCKAQAYAAQJZQGccgBXAAAAAA==.Lildangerus:BAAALgAECgMJAwAAAA==.Lilliana:BAAALgADCgIJAgAAAA==.Liminara:BAEBLgAFFH8PAAMQAAUJKBVHAwC4AAAZAAUJKBWfTwAPAQAQAAMJfQtHAwC4AAABLgAFFAgJOAABANUbAA==.Linaste:BAAALgAECgYJDAAAAA==.Lipsip:BAAALgAFFAYJAQAAAA==.Lirah:BAAALgAECggJCQABLgAFFAcJGgABACkWAA==.Lissandra:BAAALgAECgYJCgAAAA==.Lividcow:BAAALgAECgcJCgAAAA==.Lividzdk:BAABLgAECn9CAAMRAAkJBiFvEADpAgARAAkJBiFvEADpAgAaAAIJOgwDUgBOAAAAAA==.',
Lo='Lonaldo:BAAALgAECgEJAQAAAA==.Lowpop:BAAALgADCgQJBAABLgAECgcJFgAFAJwPAA==.',
Lu='Lulu:BAABLgAFFH8bAAMFAAgJ9h+xAQAxAgAFAAgJ9h+xAQAxAgAfAAEJ6QFfcQAgAAABLgAFFAkJSQARAEglAA==.',
Ly='Lynoia:BAAALgAECggJCwAAAA==.',
Ma='Malarus:BAAALgADCgEJAQAAAA==.Mandevu:BAAALgAECgUJBwAAAA==.Manknus:BAACLgAFFH8NAAILAAMJthIHGQDVAAALAAMJthIHGQDVAAAuAAQKf00AAgsACQkRF+MCAB8CAAsACQkRF+MCAB8CAAAA.Mannydemons:BAAALgADCgUJBgAAAA==.Mantequilla:BAABLgAECn8YAAIRAAcJTxzFSQAWAgARAAcJTxzFSQAWAgAAAA==.Manthrax:BAACLgAFFH8KAAIUAAMJOQgQNQByAAAUAAMJOQgQNQByAAAuAAQKfzgAAhQACQmZCphMAH4BABQACQmZCphMAH4BAAAA.Maridos:BAAALgAECgQJBAABLgAFFAMJCgAPADsOAA==.Marix:BAAALgADCgEJAQAAAA==.',
Me='Megami:BAAALgADCgEJAgAAAA==.Mexecutioner:BAAALgAECgQJBAABLgAFFAMJCgAFAHsFAA==.',
Mi='Missmolt:BAABLgAECn9YAAIgAAkJkCYXAACIAwAgAAkJkCYXAACIAwAAAA==.',
Mo='Mogok:BAABLgAFFH8KAAIQAAMJWRa4BQDNAAAQAAMJWRa4BQDNAAAAAA==.Molting:BAAALgAECgMJBAAAAA==.',
Mu='Murray:BAAALgADCgQJBAAAAA==.',
My='Mykie:BAAALgAECgcJDgAAAA==.Mylor:BAACLgAFFH8KAAIPAAMJOw6BGACOAAAPAAMJOw6BGACOAAAuAAQKfzsAAw8ACQmUFKAdABYCAA8ACQmUFKAdABYCABkAAQm/D/ZIATAAAAAA.Myrddral:BAABLgAECn9VAAIaAAkJMiTWAAAGAwAaAAkJMiTWAAAGAwAAAA==.Mystifeyed:BAABLgAECn8mAAMhAAkJdQpyNADWAAAiAAcJYgmPFgBQAQAhAAgJHQhyNADWAAAAAA==.',
['Mü']='Mürsaat:BAACLgAFFH8GAAIZAAIJfhGkRwCIAAAZAAIJfhGkRwCIAAAuAAQKfzwAAhkACQm+HF8wAD8CABkACQm+HF8wAD8CAAAA.',
Na='Namrekcah:BAAALgADCgcJDgABLgAFFAkJRwAaAKMhAA==.Narra:BAAALgAECgQJBQABLgADCgcJBwASAAAAAA==.',
Ne='Nebalicious:BAAALgADCgcJDAABLgAECgkJFgAEABgJAA==.Necrodotus:BAAALgADCgIJAgAAAA==.Nekonomiya:BAAALgADCgMJAwAAAA==.',
Ni='Nightlevels:BAABLgAECn85AAMbAAkJ2iOpAgCJAwAbAAkJ2iOpAgCJAwAcAAEJFCL/cgBcAAAAAA==.Nimbledragon:BAAALgAECgIJAgAAAA==.',
Nt='Ntayu:BAABLgAECn9WAAIBAAkJbQ/ACwCmAQABAAkJbQ/ACwCmAQAAAA==.',
Ny='Nyaanya:BAAALgADCgMJAwAAAA==.',
Ol='Olizia:BAABLgAECn8WAAIRAAcJiBKYdQCaAQARAAcJiBKYdQCaAQAAAA==.',
On='Onaga:BAABLgAECn8XAAIZAAcJIwSq8gDHAAAZAAcJIwSq8gDHAAAAAA==.',
Op='Opex:BAACLgAFFH8HAAIBAAMJGQUlcQC9AAABAAMJGQUlcQC9AAAuAAQKfxoAAwEACQnJDKJIAJABAAEACQnJDKJIAJABAAMAAQlRAH2bABMAAAAA.Opheliabutts:BAAALgAECgQJBgAAAA==.',
Or='Oril:BAAALgAECgkJEQAAAA==.',
Ot='Otura:BAAALgAECgEJAQAAAA==.',
Pa='Panndorah:BAAALgAECgEJAQAAAA==.Paw:BAAALgADCgEJAgAAAA==.',
Pe='Penjei:BAAALgADCgYJBgAAAA==.Perkulator:BAAALgAECgEJAQABLgAECgQJAwASAAAAAA==.Perkyblade:BAABLgAECn8ZAAMLAAkJfg04DgDeAAALAAkJfg04DgDeAAAOAAEJPQPCFgAdAAAAAA==.',
Ph='Philomel:BAACLgAFFH8HAAIMAAMJ0Q5OagC3AAAMAAMJ0Q5OagC3AAAuAAQKfxwAAgwACAk/G84rAE8CAAwACAk/G84rAE8CAAAA.',
Pi='Piekal:BAAALgAECgcJBwAAAA==.Pixamoo:BAAALgADCgUJCAAAAA==.',
Pl='Planeswalker:BAAALgADCgYJBgAAAA==.',
Po='Podnuh:BAAALgADCgIJAgAAAA==.Poxic:BAAALgAECgcJCwAAAA==.',
Pr='Premu:BAAALgADCggJDQABLgAECgkJQAAYAFIhAA==.Priesthealz:BAAALgAECgcJDAABLgAECgkJMAAEAIIdAA==.Primalbooty:BAAALgAFFAEJAQAAAA==.Pritt:BAAALgADCgcJDQABLgAECgcJEAASAAAAAA==.',
Ps='Psyvival:BAAALgAECgEJAQAAAA==.',
Qu='Quazu:BAAALgAECgcJBwAAAA==.',
Ra='Radagahst:BAAALgAECgcJDwAAAA==.Rarngorm:BAABLgAECn8iAAIjAAgJqhfUCgDOAQAjAAgJqhfUCgDOAQAAAA==.Rasputia:BAAALgADCgYJBgAAAA==.Ravinar:BAACLgAFFH8GAAIkAAIJaAzTBABrAAAkAAIJaAzTBABrAAAuAAQKfyQAAiQACQm1FLEDANoBACQACQm1FLEDANoBAAAA.Razzle:BAABLgAFFH8GAAIJAAMJLweqOQCqAAAJAAMJLweqOQCqAAAAAA==.Raàm:BAABLgAECn8bAAMTAAkJZgbzEAC4AAATAAkJZgbzEAC4AAAlAAEJ6QKVGwAYAAAAAA==.',
Re='Reardain:BAAALgAECggJEwAAAA==.Received:BAAALgAECgYJCAAAAA==.Relia:BAABLgAECn8YAAMKAAkJyQ/IIQDJAQAKAAgJNhDIIQDJAQAbAAEJKAaJdwA3AAAAAA==.Remedy:BAAALgADCgcJBwAAAA==.Retbull:BAAALgAECgUJBwAAAA==.Retributei:BAAALgAFFAIJAgAAAA==.',
Ri='Richardparkr:BAAALgAECgEJAQAAAA==.Rillty:BAAALgAECggJEgAAAA==.Riverwind:BAAALgAECgUJCgABLgAECgkJHQAUAMQgAA==.',
Rj='Rj:BAAALgADCgMJAwAAAA==.',
Ro='Romulus:BAABLgAECn83AAICAAkJBBceLgDtAQACAAkJBBceLgDtAQAAAA==.',
Ry='Ryo:BAAALgAECgIJAgAAAA==.',
Sa='Safyra:BAAALgADCgYJCAAAAA==.Sakoian:BAAALgAFFAEJAQAAAA==.Sakuf:BAAALgADCgcJBwAAAA==.Salana:BAAALgADCgQJBwAAAA==.Santofrancis:BAACLgAFFH8KAAIFAAMJewXdEwCIAAAFAAMJewXdEwCIAAAuAAQKfxwAAgUACQmhCn0xAEABAAUACQmhCn0xAEABAAAA.Sarbarola:BAAALgAECgYJEgAAAA==.Save:BAAALgAECgIJBAABLgAFFAEJAQASAAAAAA==.',
Se='Seraid:BAAALgAECgMJAwAAAA==.Seraie:BAAALgAECgcJCQAAAA==.',
Sh='Shadethrower:BAABLgAECn8WAAIcAAkJ9hqVCwCXAgAcAAkJ9hqVCwCXAgAAAA==.Shallbedo:BAAALgAECgYJDwABLgAFFAMJBgAWAJENAA==.Shallvoker:BAACLgAFFH8GAAMWAAMJkQ3TRgCtAAAWAAMJkQ3TRgCtAAAXAAEJzAM9EAA6AAAuAAQKfycAAxcACAnRGuwKAC0CABcACAkEF+wKAC0CABYABAmLGeJFABMBAAAA.Shane:BAAALgADCgEJAQAAAA==.Shazammy:BAAALgADCgMJBAAAAA==.Shmalexia:BAAALgAECgMJAwAAAA==.',
Si='Siatraler:BAAALgAECgkJEwAAAA==.Sigarette:BAACLgAFFH9HAAIaAAkJoyGKAQDCAgAaAAkJoyGKAQDCAgAuAAQKfzsAAhoACAlJJZkCAEIDABoACAlJJZkCAEIDAAAA.Silverspoon:BAAALgAECgMJBAAAAA==.Sinardi:BAABLgAECn9KAAMmAAkJ1xzeAQCEAgAmAAkJ1xzeAQCEAgAnAAUJFws8HgCpAAAAAA==.',
Sk='Skoobz:BAAALgAECgEJAgAAAA==.Skubasteve:BAAALgAECgYJDwAAAA==.Skydragon:BAAALgAECgYJBgAAAA==.Skylock:BAABLgAECn8WAAQeAAkJiwwFDQCMAQAeAAkJFAwFDQCMAQAIAAYJkAcUIACsAAAJAAMJOgJ2FgFSAAAAAA==.Skymane:BAABLgAECn8VAAMKAAYJmw/XNABEAQAKAAYJmw/XNABEAQAcAAEJfgJdhQAsAAAAAA==.',
Sn='Snaggletooth:BAAALgADCgEJAQAAAA==.',
So='Solar:BAAALgAFFAMJAwAAAA==.Soongxiao:BAAALgAECgEJAQAAAA==.Sorce:BAAALgAECgYJEAABLgAFFAYJGQAUANEXAA==.Sovix:BAAALgAECgcJCgAAAA==.Sovo:BAACLgAFFH8jAAIHAAkJyxUJDwAWAgAHAAkJyxUJDwAWAgAuAAQKfzEAAgcACQlEIpcdAP8CAAcACQlEIpcdAP8CAAAA.',
Sp='Spiritdáncer:BAAALgADCgEJAQAAAA==.Sprick:BAAALgAECgEJAQAAAA==.',
Sq='Squshmepure:BAAALgAECgcJAwAAAA==.',
St='Starrin:BAAALgAECggJEwAAAA==.Steaknquake:BAACLgAFFH8HAAIUAAIJ2RcMNwBsAAAUAAIJ2RcMNwBsAAAuAAQKf1UAAhQACQk5IzMFAGADABQACQk5IzMFAGADAAAA.',
Su='Sumdumfun:BAAALgAECgMJAwAAAA==.Sunflower:BAAALgAECgYJDwAAAA==.',
Sv='Svaha:BAAALgAECgIJAgAAAA==.',
Sy='Sybri:BAABLgAECn8WAAMBAAgJ5RgjOQDKAQABAAcJNRojOQDKAQADAAUJ6wsrWQDhAAAAAA==.Sylvandel:BAABLgAECn9PAAIDAAkJXxyxAAB5AgADAAkJXxyxAAB5AgAAAA==.Sylvrshado:BAAALgAECgIJAgAAAA==.',
Ta='Taberna:BAAALgAECgMJAwAAAA==.Talanthar:BAAALgAECgUJBQABLgAECgkJMAAFAOofAA==.Talarrond:BAAALgAECgUJBQAAAA==.Talthis:BAAALgAECgIJAgAAAA==.',
Te='Teagen:BAABLgAECn81AAMCAAkJggj1VQA4AQACAAkJggj1VQA4AQAYAAIJUgt6dwBXAAAAAA==.',
Th='Thalius:BAABLgAECn9QAAIRAAkJKhSjBgD1AQARAAkJKhSjBgD1AQAAAA==.Thorandaal:BAABLgAECn8jAAMZAAgJJQpsmwA/AQAZAAgJJQpsmwA/AQAPAAYJAgrwTgD+AAAAAA==.Thral:BAAALgAFFAIJAgAAAA==.Thunderbuddy:BAAALgADCgEJAQAAAA==.',
Ti='Tisbish:BAAALgADCgIJAgAAAA==.',
To='Tome:BAABLgAECn8hAAQDAAkJ6SYDAAAbBAADAAkJ3CYDAAAbBAAGAAkJxCbjAABpAwABAAEJEyZD/ABjAAAAAA==.Toomanydeths:BAABLgAECn8+AAMaAAkJsQ/WHQBpAQAaAAkJsQ/WHQBpAQARAAYJ3QywvgAAAQAAAA==.',
Tr='Trickledeath:BAAALgADCgMJAwAAAA==.Trunx:BAAALgAECgQJBQABLgAECgkJHwAfAN4jAA==.',
Tw='Twerkdat:BAAALgAECgMJAwAAAA==.',
Ty='Tye:BAAALgAECgcJEQAAAA==.Tyyle:BAAALgADCgYJBgAAAA==.',
['Tá']='Tálos:BAAALgAECgEJBAAAAA==.',
Ud='Udaz:BAAALgAECgMJAwAAAA==.',
Ul='Uldear:BAAALgADCgYJCwAAAA==.',
Un='Unbuttered:BAAALgAECgIJBAAAAA==.Uninvite:BAAALgAECgQJBAAAAA==.Untz:BAAALgAECgEJAgAAAA==.',
Ur='Ursusmanny:BAAALgAECgcJDAAAAA==.',
Va='Vaelthyeth:BAAALgADCgUJBQAAAA==.Valkyrie:BAAALgAECgYJBgABLgAECgkJMAAEAIIdAA==.Vandarin:BAAALgADCgcJGgABLgAECgYJGQAIAHkIAA==.Vanthrall:BAAALgAECgUJDAAAAA==.Vayce:BAABLgAECn8yAAMoAAkJ5iEkAwCKAgAoAAgJyCIkAwCKAgAVAAcJRyL/GAA9AgAAAA==.',
Ve='Velysa:BAACLgAFFH8HAAIQAAIJCAlgDwA/AAAQAAIJCAlgDwA/AAAuAAQKf00AAxAACQn6Fy8DAKIBABAACQn6Fy8DAKIBABkAAwkvCjIeAWAAAAAA.Veniea:BAAALgADCgEJAQABLgAECggJCwASAAAAAA==.',
Vi='Vilterion:BAAALgAECgEJAQAAAA==.Vizago:BAAALgADCgEJAQAAAA==.',
Vo='Vogekth:BAAALgAECgUJCwAAAA==.',
['Vÿ']='Vÿktor:BAAALgAECgcJEAAAAA==.',
Wa='Warseeker:BAABLgAECn8dAAMUAAkJxCAlCADzAgAUAAkJxCAlCADzAgATAAQJ1w7QYwC6AAAAAA==.Watlmonk:BAAALgADCgIJAgAAAA==.',
We='Weatherworn:BAABLgAECn9FAAMUAAkJthboJwAgAgAUAAkJthboJwAgAgATAAEJwwr3LQAiAAAAAA==.',
Wi='Wirhlanir:BAAALgADCgkJCQAAAA==.',
Wr='Wrathsong:BAAALgAECgEJAQAAAA==.',
Xe='Xemu:BAAALgAECgQJBAAAAA==.Xenferos:BAAALgADCgcJDAABLgAFFAMJDAAeAEkHAA==.Xerber:BAAALgADCgYJDQABLgAECgYJGQAIAHkIAA==.',
Xi='Xiro:BAAALgAECgUJEwAAAA==.',
Yo='Yoril:BAAALgAECgcJDgAAAA==.',
Za='Zagihex:BAAALgAECgcJBwAAAA==.Zagiroth:BAABLgAECn8sAAMMAAkJFiGnDQDYAgAMAAkJFiGnDQDYAgAnAAEJFhthJwBLAAAAAA==.Zalthanos:BAAALgADCgEJAQAAAA==.Zarack:BAAALgADCgYJBAABLgAECgYJGQAIAHkIAA==.',
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
