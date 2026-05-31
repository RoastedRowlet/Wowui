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

local lookup = {'Hunter-BeastMastery','Druid-Restoration','Hunter-Marksmanship','Monk-Brewmaster','Monk-Windwalker','Hunter-Survival','Warlock-Destruction','Warlock-Demonology','Priest-Shadow','Warrior-Fury','DemonHunter-Devourer','Warrior-Arms','Warrior-Protection','Paladin-Holy','Paladin-Protection','DeathKnight-Unholy','Unknown-Unknown','Mage-Frost','Shaman-Elemental','Shaman-Restoration','Evoker-Augmentation','Evoker-Devastation','Druid-Balance','Paladin-Retribution','Priest-Discipline','Priest-Holy','DeathKnight-Blood','Warlock-Affliction','Monk-Mistweaver','Rogue-Outlaw','Druid-Guardian','Druid-Feral','DeathKnight-Frost','Mage-Fire','DemonHunter-Havoc','DemonHunter-Vengeance','Rogue-Assassination','Rogue-Subtlety',}
local provider = {region='US',realm='SteamwheedleCartel',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aalwein:BAABLgAECn8pAAIBAAkJsx9SFQCSAgABAAkJsx9SFQCSAgAAAA==.',
Ae='Aesculapius:BAABLgAECn8pAAICAAkJ1BaSGgBeAgACAAkJ1BaSGgBeAgAAAA==.',
Al='Aladia:BAAALgADCgMJAgAAAA==.Aloisious:BAAALgAECgEJAQAAAA==.',
Am='Amarii:BAABLgAECn8gAAIDAAcJ4AlyFQD4AAADAAcJ4AlyFQD4AAAAAA==.Amorash:BAAALgADCgEJAQAAAA==.',
An='Annabeth:BAAALgAECgUJBQABLgAFFAIJBgAEANsVAA==.Anonymus:BAACLgAFFH8GAAIEAAIJ2xU4PQCTAAAEAAIJ2xU4PQCTAAAuAAQKfxgAAwQACQlKHRMOAEQCAAQACAksHhMOAEQCAAUAAgmiEJV7AEcAAAAA.',
Ar='Ara:BAACLgAFFH8GAAMBAAMJqROCSgDtAAABAAMJqROCSgDtAAAGAAEJiQOnLgBDAAAuAAQKfy4AAgEACQmhIAMMAOACAAEACQmhIAMMAOACAAAA.Ardwin:BAAALgADCgEJAQABLgAECgYJGQAHAHkIAA==.',
As='Ashgrove:BAAALgAECgUJCAAAAA==.',
Av='Avigar:BAAALgADCgEJAwAAAA==.',
Ba='Bambarrok:BAABLgAECn8XAAIIAAkJSQafcQBMAQAIAAkJSQafcQBMAQAAAA==.Bangan:BAAALgAECgYJDQAAAA==.',
Be='Belakor:BAAALgAECgYJBgAAAA==.Bep:BAAALgAECgYJDAABLgAECgkJGgAHADEVAA==.Bepragosa:BAABLgAECn8aAAIHAAkJMRWkCAA3AgAHAAkJMRWkCAA3AgAAAA==.',
Bi='Binpharteen:BAAALgADCgkJGQAAAA==.',
Bl='Blaque:BAAALgADCgcJBwABLgAECggJFQAJABoMAA==.',
Br='Brimscythe:BAAALgAECgEJAgABLgAECgcJJAAHAJEhAA==.Brownbelt:BAABLgAECn86AAIKAAgJARwKFAA9AgAKAAgJARwKFAA9AgAAAA==.Brîn:BAAALgAECgMJBAAAAA==.',
Bu='Buteihunter:BAABLgAECn8yAAQBAAkJFyJgCgDwAgABAAkJFyJgCgDwAgADAAEJ7wtFiAA0AAAGAAEJEgdNXgAyAAAAAA==.',
Ca='Cadranak:BAABLgAECn8wAAILAAkJ2RI4OwDDAQALAAkJ2RI4OwDDAQAAAA==.Caiyenthi:BAABLgAECn8nAAIBAAgJkQ+WVgCHAQABAAgJkQ+WVgCHAQAAAA==.Calliesue:BAAALgAECgIJAgAAAA==.Camgor:BAAALgADCgEJAQABLgAECgYJGQAHAHkIAA==.Carfalis:BAAALgADCggJCQAAAA==.',
Ch='Chelali:BAABLgAECn8XAAQKAAkJ8RVsJQAtAgAKAAgJ/BZsJQAtAgAMAAUJ5BC5JwAYAQANAAEJNAjBSQA4AAAAAA==.Chelly:BAAALgAECgEJAQABLgAECgkJFwAKAPEVAA==.Chicharrone:BAAALgAECgYJEgAAAA==.Chizaru:BAABLgAECn8lAAMOAAkJWx40BgAaAwAOAAkJWx40BgAaAwAPAAMJMgHMRgA2AAAAAA==.Chlorophyll:BAAALgADCgQJBQAAAA==.Chyntobelt:BAABLgAECn8jAAIQAAYJiwVi0QDOAAAQAAYJiwVi0QDOAAABLgAECggJOgAKAAEcAA==.',
Co='Copyright:BAAALgAECgEJAQAAAA==.',
Cr='Creep:BAAALgAECgYJEAAAAA==.Cryption:BAABLgAECn8VAAIBAAgJkhQEOADOAQABAAgJkhQEOADOAQAAAA==.',
['Cú']='Cúchulainn:BAAALgAECgYJDQAAAA==.',
Da='Daelyn:BAABLgAECn8VAAIBAAcJ2QxxgwAfAQABAAcJ2QxxgwAfAQAAAA==.Dalhma:BAAALgAFFAEJAQAAAA==.Dallma:BAAALgAFFAMJBQABLgAFFAEJAQARAAAAAQ==.Dallmia:BAAALgAFFAMJAwABLgAFFAEJAQARAAAAAQ==.Dane:BAAALgAECgIJAgAAAA==.Dayaris:BAAALgAECgUJDwAAAA==.',
De='Deadbeat:BAAALgAECgUJBgAAAA==.Deafenned:BAABLgAECn8aAAISAAkJdx6gPQCBAgASAAkJdx6gPQCBAgABLgAFFAMJBwALANEOAA==.Deaflynn:BAAALgAECgEJAwABLgAFFAMJBwALANEOAA==.Deafnight:BAAALgAECgIJBAABLgAFFAMJBwALANEOAA==.Demonbep:BAAALgADCgQJBAABLgAECgkJGgAHADEVAA==.Demonicpower:BAAALgADCggJCAAAAA==.Derrington:BAABLgAECn8kAAIHAAcJkSGuAwA7AgAHAAcJkSGuAwA7AgAAAA==.Destinyetwo:BAAALgAECgEJAQAAAA==.Dett:BAABLgAECn8VAAITAAcJZQhyTADnAAATAAcJZQhyTADnAAAAAA==.',
Di='Diamante:BAACLgAFFH8QAAIUAAQJZRvVIgA4AQAUAAQJZRvVIgA4AQAuAAQKfyoAAhQACQlBFlYtAOgBABQACQlBFlYtAOgBAAAA.',
Dk='Dkvayce:BAAALgADCgYJBgAAAA==.',
Dr='Dragqueene:BAAALgAFFAEJAgAAAA==.Drakluz:BAAALgADCgEJAQAAAA==.Drakner:BAABLgAECn8xAAMVAAgJKw7xLwBaAQAVAAgJKw7xLwBaAQAWAAQJBQJMMgCEAAAAAA==.Drellin:BAAALgAECgEJBAABLgAECgcJJAAHAJEhAA==.Dremu:BAABLgAECn8pAAMXAAkJdx0FCgCeAgAXAAkJdx0FCgCeAgACAAMJEw9doACJAAAAAA==.',
Du='Duraz:BAABLgAECn8jAAICAAkJQg4xRABsAQACAAkJQg4xRABsAQAAAA==.',
Dy='Dysraxis:BAAALgADCgEJAQAAAA==.',
Ee='Eerie:BAAALgAECgIJBgAAAA==.',
Eg='Eggar:BAAALgADCgYJEgABLgAECggJJQAQABMTAA==.',
El='Elahna:BAAALgADCgcJDQAAAA==.Elalia:BAABLgAECn8ZAAIHAAYJeQjbGgC6AAAHAAYJeQjbGgC6AAAAAA==.Elamaun:BAABLgAECn86AAIOAAgJphnVEgBlAgAOAAgJphnVEgBlAgAAAA==.Elereia:BAAALgAECgEJAQAAAA==.Eltiana:BAAALgAECgUJCwAAAA==.',
En='English:BAABLgAECn8VAAIJAAgJGgw0MAA7AQAJAAgJGgw0MAA7AQAAAA==.',
Ep='Ephex:BAAALgADCgcJGQAAAA==.Ephyiana:BAAALgADCgcJCAAAAA==.Epic:BAAALgAECgUJBgAAAA==.',
Er='Errimys:BAAALgADCgUJBQAAAA==.Ertraz:BAAALgAECgEJAgAAAA==.',
Es='Essense:BAAALgADCgcJBwAAAA==.Esçanor:BAAALgADCgUJBQAAAA==.',
Et='Etania:BAAALgAECgYJCQAAAA==.',
Fa='Faelyna:BAABLgAECn86AAIGAAgJtxN+FgDiAQAGAAgJtxN+FgDiAQAAAA==.',
Fe='Felnut:BAAALgADCgEJAQAAAA==.',
Fi='Finniel:BAAALgADCgEJAQAAAA==.',
Fl='Flash:BAAALgADCgMJAQAAAA==.',
Fo='Foix:BAAALgADCgcJDwAAAA==.Forged:BAACLgAFFH8IAAIYAAMJxRMzVQDiAAAYAAMJxRMzVQDiAAAuAAQKfysAAhgACAnzHxEpAIECABgACAnzHxEpAIECAAAA.',
Ga='Gaerne:BAAALgADCgEJAQAAAA==.',
Gi='Githyanki:BAAALgADCgkJCQAAAA==.',
Gl='Glabberghoul:BAABLgAECn8sAAIVAAkJQhQXIAC9AQAVAAkJQhQXIAC9AQAAAA==.',
Go='Goodhead:BAAALgADCgMJBAAAAA==.',
Gr='Grangmage:BAAALgAECgQJDQAAAA==.Grimvault:BAAALgAECgEJAQABLgAECgcJJAAHAJEhAA==.Griogair:BAAALgADCgYJFQABLgAECgYJGQAHAHkIAA==.',
Gu='Gultir:BAAALgAECgYJCAAAAA==.',
Ha='Hacelian:BAAALgAECgEJAwAAAA==.Harper:BAAALgADCgcJBwAAAA==.',
He='Heetseeker:BAAALgAECgQJCAABLgAECgkJHQAUAMQgAA==.',
Hn='Hnoa:BAAALgADCgcJDwAAAA==.',
Ho='Hoggins:BAAALgADCgUJBQABLgADCgcJBwARAAAAAA==.Holyverdict:BAABLgAECn8XAAIOAAkJUSWdBQASAwAOAAkJUSWdBQASAwAAAA==.',
Ic='Icaina:BAABLgAECn8vAAIUAAkJoB8FFAB1AgAUAAkJoB8FFAB1AgAAAA==.',
In='Incinderella:BAAALgADCgEJAQABLgAECgYJDQARAAAAAA==.Interval:BAAALgADCgcJDgABLgAECgkJOgAYADsfAA==.',
Is='Islands:BAAALgADCgIJAgAAAA==.',
Ja='Jadani:BAABLgAECn8cAAIHAAcJ1g/kEAAbAQAHAAcJ1g/kEAAbAQAAAA==.',
Je='Jeisa:BAABLgAECn8cAAMPAAcJLg+wIQDrAAAPAAYJiQ+wIQDrAAAYAAYJQA1uyQDdAAAAAA==.Jelyn:BAAALgAECgEJAQAAAA==.',
Ji='Jimbonereus:BAAALgADCgIJAgAAAA==.Jingshei:BAAALgAECgEJAQABLgAECgcJCgARAAAAAA==.',
Jo='Jordyevoker:BAAALgAECggJDQAAAA==.',
Ju='Juanns:BAAALgAECgYJDQAAAA==.',
Ka='Kalchee:BAAALgADCgIJAgAAAA==.Kallotera:BAABLgAECn8gAAMMAAcJ/QwMKAAXAQAMAAcJ/QwMKAAXAQAKAAUJ4QbQcAD1AAAAAA==.Kastoria:BAAALgADCgkJFgAAAA==.Katnipp:BAABLgAECn8uAAIBAAkJChxTGwBsAgABAAkJChxTGwBsAgAAAA==.Katnyss:BAAALgAECgYJDQAAAA==.Kaylazune:BAABLgAECn8iAAMZAAcJeA2fLgBBAQAZAAcJxAufLgBBAQAaAAYJpAt0PADrAAAAAA==.',
Ke='Kellwynne:BAAALgAECgMJAwAAAA==.Keramoon:BAAALgADCgUJBQAAAA==.Keyleth:BAAALgAECgEJAQAAAA==.',
Kh='Khrala:BAABLgAECn8lAAMQAAgJExNKXgCaAQAQAAgJExNKXgCaAQAbAAIJHgxHRQBeAAAAAA==.',
Ki='Kiye:BAACLgAFFH8TAAIBAAUJyBMKNwAmAQABAAUJyBMKNwAmAQAuAAQKfykAAgEACQnaG3gPAL8CAAEACQnaG3gPAL8CAAAA.',
Ko='Koren:BAAALgADCgMJAgAAAA==.',
Kr='Krenko:BAABLgAECn8VAAIQAAkJgArIXwCWAQAQAAkJgArIXwCWAQAAAA==.',
Ku='Kung:BAAALgAECgYJBgABLgAECgcJJAAHAJEhAA==.Kuuro:BAABLgAECn8pAAIUAAcJjRbIOgCnAQAUAAcJjRbIOgCnAQAAAA==.',
La='Lanister:BAAALgADCgQJBAAAAA==.Lattymag:BAAALgAECgUJBwAAAA==.Laughystabby:BAAALgAECgkJDQAAAA==.',
Le='Leibniz:BAABLgAECn8lAAIcAAcJ2B4CBgABAgAcAAcJ2B4CBgABAgAAAA==.Leisa:BAABLgAECn8oAAIBAAcJ7BE8WwB6AQABAAcJ7BE8WwB6AQAAAA==.Lelwindae:BAAALgAECgYJCQAAAA==.',
Li='Lifemoon:BAAALgAECgcJDwAAAA==.Lightgiver:BAAALgAECgYJDQAAAA==.Lighthoof:BAABLgAECn8gAAMYAAkJNx84FQDrAgAYAAkJNx84FQDrAgAPAAQJVBsaGwA1AQAAAA==.Lightiuz:BAABLgAECn8eAAMCAAYJBhbqRQCKAQACAAYJBhbqRQCKAQAXAAQJZQGccgBXAAAAAA==.Liminara:BAEBLgAFFH8IAAMPAAUJrRBHAwC4AAAYAAUJiA57PAAbAQAPAAMJfQtHAwC4AAABLgAFFAcJGwABAPkZAA==.Linaste:BAAALgAECgQJBAAAAA==.Lirah:BAAALgAECggJCQABLgAFFAUJEwABAMgTAA==.Lividzdk:BAABLgAECn9BAAMQAAkJBiE4DQDxAgAQAAkJBiE4DQDxAgAbAAIJOgwFSQBSAAAAAA==.',
Lo='Lonaldo:BAAALgAECgEJAQAAAA==.Lowpop:BAAALgADCgQJBAABLgAECgcJFgAFAJwPAA==.',
Lu='Lulu:BAABLgAFFH8OAAMFAAUJTCR2BQCgAQAFAAUJTCR2BQCgAQAdAAEJ6QFvVgAjAAAAAA==.',
Ly='Lynoia:BAAALgAECgcJCgAAAA==.',
Ma='Malarus:BAAALgADCgEJAQAAAA==.Mandevu:BAAALgAECgUJBwAAAA==.Manknus:BAABLgAECn8yAAIKAAkJjREyHgDpAQAKAAkJjREyHgDpAQAAAA==.Mannydemons:BAAALgADCgUJBgAAAA==.Mantequilla:BAABLgAECn8YAAIQAAcJTxzFSQAWAgAQAAcJTxzFSQAWAgAAAA==.Manthrax:BAABLgAECn8vAAIUAAkJtwk7RACAAQAUAAkJtwk7RACAAQAAAA==.Marix:BAAALgADCgEJAQAAAA==.',
Me='Megami:BAAALgADCgEJAgAAAA==.',
Mi='Missmolt:BAABLgAECn8qAAIeAAcJmSUTAgCaAgAeAAcJmSUTAgCaAgAAAA==.',
Mo='Molting:BAAALgAECgMJBAAAAA==.',
My='Mykara:BAAALgADCggJDAAAAA==.Mykie:BAAALgAECgcJDAAAAA==.Mylor:BAABLgAECn82AAMOAAkJThTtGgAWAgAOAAkJThTtGgAWAgAYAAEJvw/2SAEwAAAAAA==.Myrddral:BAABLgAECn8oAAIbAAcJ5CKPCgBRAgAbAAcJ5CKPCgBRAgAAAA==.Mystifeyed:BAABLgAECn8mAAMfAAkJdQpgKwDcAAAgAAcJYgmPFgBQAQAfAAgJHQhgKwDcAAAAAA==.',
['Mü']='Mürsaat:BAABLgAECn8qAAIYAAgJsBgUPgD1AQAYAAgJsBgUPgD1AQAAAA==.',
Na='Namrekcah:BAAALgADCgcJDgABLgAFFAgJNgAbAJYgAA==.Narra:BAAALgAECgQJBQABLgADCgcJBwARAAAAAA==.',
Ne='Nebalicious:BAAALgADCgcJDAABLgAECgYJDQARAAAAAA==.Nekonomiya:BAAALgADCgMJAwAAAA==.',
Ni='Nightlevels:BAABLgAECn85AAMZAAkJ2iMTAgCJAwAZAAkJ2iMTAgCJAwAaAAEJFCL/cgBcAAAAAA==.Nimbledragon:BAAALgADCggJCgAAAA==.',
Nt='Ntayu:BAABLgAECn8qAAIBAAcJNgmRewAvAQABAAcJNgmRewAvAQAAAA==.',
Ol='Olizia:BAABLgAECn8WAAIQAAcJiBKYdQCaAQAQAAcJiBKYdQCaAQAAAA==.',
On='Onaga:BAABLgAECn8XAAIYAAcJIwTB2wDEAAAYAAcJIwTB2wDEAAAAAA==.',
Op='Opex:BAACLgAFFH8HAAIBAAMJGQW/WADGAAABAAMJGQW/WADGAAAuAAQKfxoAAwEACQnJDKJIAJABAAEACQnJDKJIAJABAAMAAQlRAH2bABMAAAAA.Opheliabutts:BAAALgAECgQJBgAAAA==.',
Or='Oril:BAAALgAECgkJEQAAAA==.',
Pa='Paw:BAAALgADCgEJAgAAAA==.',
Pe='Penjei:BAAALgADCgYJBgAAAA==.Perkyblade:BAAALgAECgcJCAAAAA==.',
Ph='Philomel:BAACLgAFFH8HAAILAAMJ0Q6GWADEAAALAAMJ0Q6GWADEAAAuAAQKfxwAAgsACAk/G84rAE8CAAsACAk/G84rAE8CAAAA.',
Pi='Piekal:BAAALgAECgcJBwAAAA==.Pixamoo:BAAALgADCgUJCAAAAA==.',
Pl='Planeswalker:BAAALgADCgYJBgAAAA==.',
Po='Podnuh:BAAALgADCgIJAgAAAA==.Poxic:BAAALgADCgQJBAAAAA==.',
Pr='Priesthealz:BAAALgAECgcJDAABLgAECgkJLgAEAKEcAA==.Pritt:BAAALgADCgcJDQABLgAECgcJDwARAAAAAA==.',
Qu='Quazu:BAAALgAECgcJBwAAAA==.',
Ra='Radagahst:BAAALgAECgcJDwAAAA==.Rarngorm:BAABLgAECn8iAAIhAAgJqhe0CADRAQAhAAgJqhe0CADRAQAAAA==.Ravinar:BAABLgAECn8dAAIiAAgJHxTUAwCuAQAiAAgJHxTUAwCuAQAAAA==.Raàm:BAAALgAECgYJBgAAAA==.',
Re='Reardain:BAAALgAECgcJEgAAAA==.Received:BAAALgAECgIJAgAAAA==.Relia:BAABLgAECn8YAAMJAAkJyQ/IIQDJAQAJAAgJNhDIIQDJAQAZAAEJKAZyZwA5AAAAAA==.Remedy:BAAALgADCgcJBwAAAA==.',
Ri='Richardparkr:BAAALgAECgEJAQAAAA==.Rillty:BAAALgAECgIJAgAAAA==.Riverwind:BAAALgAECgUJCgABLgAECgkJHQAUAMQgAA==.',
Rj='Rj:BAAALgADCgMJAwAAAA==.',
Ro='Romulus:BAABLgAECn8dAAICAAcJRRIwQQB6AQACAAcJRRIwQQB6AQAAAA==.',
Ry='Ryo:BAAALgAECgIJAgAAAA==.',
Sa='Safyra:BAAALgADCgYJCAAAAA==.Sakoian:BAAALgAECgEJAQAAAA==.Sakuf:BAAALgADCgcJBwAAAA==.Salana:BAAALgADCgQJBwAAAA==.Santofrancis:BAABLgAECn8cAAIFAAkJoQpIKgBPAQAFAAkJoQpIKgBPAQAAAA==.Sarbarola:BAAALgADCgkJDgAAAA==.Save:BAAALgAECgIJBAABLgAFFAEJAQARAAAAAA==.',
Se='Seraie:BAAALgAECgcJCQAAAA==.',
Sh='Shadethrower:BAABLgAECn8WAAIaAAkJ9hqVCwCXAgAaAAkJ9hqVCwCXAgAAAA==.Shallbedo:BAAALgAECgYJDQABLgAECggJIwAWANEaAA==.Shallvoker:BAABLgAECn8jAAMWAAgJ0RrsCgAtAgAWAAgJBBfsCgAtAgAVAAQJLxZtSQDhAAAAAA==.Shazammy:BAAALgADCgMJBAAAAA==.Shmalexia:BAAALgAECgMJAwAAAA==.',
Si='Siatraler:BAAALgAECgkJEQAAAA==.Sigarette:BAACLgAFFH82AAIbAAgJliBYAQCcAgAbAAgJliBYAQCcAgAuAAQKfzkAAhsACAnXJJkCAEIDABsACAnXJJkCAEIDAAAA.Silverspoon:BAAALgAECgIJAwAAAA==.Sinardi:BAABLgAECn8oAAMjAAYJdR2zFgCxAQAjAAYJdR2zFgCxAQAkAAQJmg0HHwCHAAAAAA==.',
Sk='Skoobz:BAAALgAECgEJAgAAAA==.Skubasteve:BAAALgAECgYJDwAAAA==.Skydragon:BAAALgAECgYJBgAAAA==.Skylock:BAABLgAECn8WAAQcAAkJiwyECgCWAQAcAAkJFAyECgCWAQAHAAYJkAe3HACtAAAIAAMJOgIe/gBYAAAAAA==.Skymane:BAABLgAECn8VAAMJAAYJmw/XNABEAQAJAAYJmw/XNABEAQAaAAEJfgJdhQAsAAAAAA==.',
Sn='Snaggletooth:BAAALgADCgEJAQAAAA==.',
So='Solar:BAAALgAFFAMJAwAAAA==.Sovix:BAAALgAECgEJAwAAAA==.Sovo:BAACLgAFFH8XAAISAAcJbReVGADwAQASAAcJbReVGADwAQAuAAQKfyoAAhIACQlEIpcdAP8CABIACQlEIpcdAP8CAAAA.',
Sp='Spiritdáncer:BAAALgADCgEJAQAAAA==.',
Sq='Squshmepure:BAAALgAECgYJAgAAAA==.',
St='Starrin:BAAALgAECgcJEgAAAA==.Steaknquake:BAABLgAECn86AAIUAAgJWyH4CgDyAgAUAAgJWyH4CgDyAgAAAA==.',
Su='Sumdumfun:BAAALgAECgMJAwAAAA==.Sunflower:BAAALgAECgYJDQAAAA==.',
Sv='Svaha:BAAALgAECgIJAgAAAA==.',
Sy='Sybri:BAABLgAECn8WAAMBAAgJ5RgjOQDKAQABAAcJNRojOQDKAQADAAUJ6wsrWQDhAAAAAA==.Sylvandel:BAABLgAECn8qAAIDAAcJehQ5DgBhAQADAAcJehQ5DgBhAQAAAA==.Sylvrshado:BAAALgAECgIJAgAAAA==.',
Ta='Taberna:BAAALgAECgMJAwAAAA==.Talthis:BAAALgAECgIJAgAAAA==.',
Te='Teagen:BAABLgAECn81AAMCAAkJgggaTwA/AQACAAkJgggaTwA/AQAXAAIJUgsvbABXAAAAAA==.',
Th='Thalius:BAABLgAECn8pAAIQAAcJ/Q6+fgBRAQAQAAcJ/Q6+fgBRAQAAAA==.Thorandaal:BAAALgAECgUJDwAAAA==.Thunderbuddy:BAAALgADCgEJAQAAAA==.',
Ti='Tisbish:BAAALgADCgIJAgAAAA==.',
To='Tome:BAABLgAECn8hAAQDAAkJ6SYDAAAbBAADAAkJ3CYDAAAbBAAGAAkJxCaOAAB0AwABAAEJEyY94ABkAAAAAA==.Tometv:BAAALgAECgcJBgABLgAECgkJIQADAOkmAA==.Toomanydeths:BAABLgAECn84AAMbAAkJsQ8BGgBzAQAbAAkJsQ8BGgBzAQAQAAUJvQrEtQD1AAAAAA==.',
Tr='Trunx:BAAALgAECgQJBQABLgAECgkJHwAdAN4jAA==.',
Ty='Tye:BAAALgAECgcJEQAAAA==.Tyyle:BAAALgADCgYJBgAAAA==.',
['Tá']='Tálos:BAAALgAECgEJBAAAAA==.',
Ul='Uldear:BAAALgADCgYJCwAAAA==.',
Un='Unbuttered:BAAALgAECgIJBAAAAA==.',
Ur='Ursusmanny:BAAALgAECgcJCwAAAA==.',
Va='Vaelthyeth:BAAALgADCgUJBQAAAA==.Valkyrie:BAAALgAECgYJBgABLgAECgkJLgAEAKEcAA==.Vandarin:BAAALgADCgcJGgABLgAECgYJGQAHAHkIAA==.Vanthrall:BAAALgAECgQJCgAAAA==.Vayce:BAABLgAECn8yAAMlAAkJ5iGjAgCRAgAlAAgJyCKjAgCRAgAmAAcJRyL/GAA9AgAAAA==.',
Ve='Velysa:BAABLgAECn8xAAMPAAgJ9hiBCwD2AQAPAAgJ9hiBCwD2AQAYAAIJOgkyHgFgAAAAAA==.',
Vi='Vizago:BAAALgADCgEJAQAAAA==.',
Vo='Vogekth:BAAALgAECgUJCwAAAA==.',
['Vÿ']='Vÿktor:BAAALgADCgYJBgAAAA==.',
Wa='Warseeker:BAABLgAECn8dAAMUAAkJxCAlCADzAgAUAAkJxCAlCADzAgATAAQJ1w7UWQC6AAAAAA==.Watlmonk:BAAALgADCgIJAgAAAA==.',
We='Weatherworn:BAABLgAECn8vAAIUAAcJrhhiLADtAQAUAAcJrhhiLADtAQAAAA==.',
Xe='Xemu:BAAALgAECgQJBAAAAA==.Xenferos:BAAALgADCgcJDAABLgAECgkJJwAHACQZAA==.Xerber:BAAALgADCgYJDQABLgAECgYJGQAHAHkIAA==.',
Xi='Xiro:BAAALgAECgUJEwAAAA==.',
Yo='Yoril:BAAALgAECgcJDgAAAA==.',
Za='Zagihex:BAAALgAECgcJBwAAAA==.Zagiroth:BAABLgAECn8sAAMLAAkJFiGuCwDZAgALAAkJFiGuCwDZAgAkAAEJFhthJwBLAAAAAA==.Zalthanos:BAAALgADCgEJAQAAAA==.Zarack:BAAALgADCgYJBAABLgAECgYJGQAHAHkIAA==.',
Ze='Zebraman:BAABLgAECn8VAAICAAgJDBJ3PgCGAQACAAgJDBJ3PgCGAQAAAA==.Zeraida:BAAALgADCgcJDAAAAA==.',
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
