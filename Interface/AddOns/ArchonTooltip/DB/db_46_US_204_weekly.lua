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

local lookup = {'Hunter-BeastMastery','Druid-Restoration','Unknown-Unknown','Warlock-Demonology','Warlock-Destruction','Priest-Shadow','Hunter-Marksmanship','Warrior-Fury','Hunter-Survival','DemonHunter-Devourer','Warrior-Arms','Warrior-Protection','Paladin-Holy','DeathKnight-Unholy','Mage-Frost','Shaman-Restoration','Evoker-Augmentation','Evoker-Devastation','Druid-Balance','Paladin-Retribution','Paladin-Protection','Priest-Holy','Priest-Discipline','Warlock-Affliction','DeathKnight-Blood','Monk-Windwalker','Rogue-Outlaw','Druid-Guardian','Druid-Feral','Monk-Brewmaster','DeathKnight-Frost','Mage-Fire','DemonHunter-Havoc','Monk-Mistweaver','Rogue-Assassination','Rogue-Subtlety','Shaman-Elemental','DemonHunter-Vengeance',}
local provider = {region='US',realm='SteamwheedleCartel',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aalwein:BAABLgAECn8pAAIBAAkJsx+iCwC0AgABAAkJsx+iCwC0AgAAAA==.',
Ae='Aesculapius:BAABLgAECn8eAAICAAgJjBecGwAiAgACAAgJjBecGwAiAgAAAA==.',
Al='Aladia:BAAALgADCgMJAgAAAA==.Aloisious:BAAALgAECgEJAQAAAA==.',
Am='Amarii:BAAALgAECgcJEwAAAA==.Amorash:BAAALgADCgEJAQAAAA==.',
An='Anonymus:BAAALgAFFAEJBAAAAA==.',
Ar='Ardwin:BAAALgADCgEJAQABLgAECgYJEwADAAAAAA==.',
As='Ashgrove:BAAALgAECgUJCAAAAA==.',
Av='Avigar:BAAALgADCgEJAwAAAA==.',
Ba='Bambarrok:BAABLgAECn8XAAIEAAkJSQYtXABNAQAEAAkJSQYtXABNAQAAAA==.Bangan:BAAALgAECgYJBgAAAA==.',
Be='Belakor:BAAALgAECgYJBgAAAA==.Bep:BAAALgAECgYJCwABLgAECgkJGgAFADEVAA==.Bepragosa:BAABLgAECn8aAAIFAAkJMRWkCAA3AgAFAAkJMRWkCAA3AgAAAA==.',
Bi='Binpharteen:BAAALgADCgkJFQAAAA==.',
Bl='Blaque:BAAALgADCgcJBwABLgAECggJFQAGABsMAA==.',
Bo='Bowguytome:BAAALgAECgcJDAABLgAECgkJIQAHAOkmAA==.',
Br='Brimscythe:BAAALgAECgEJAgAAAA==.Brownbelt:BAABLgAECn8pAAIIAAgJzRfcGADaAQAIAAgJzRfcGADaAQAAAA==.Brîn:BAAALgAECgEJAQAAAA==.',
Bu='Buteihunter:BAABLgAECn8kAAQBAAkJCh9aEQCuAgABAAkJCh9aEQCuAgAJAAEJEgfhSwA2AAAHAAEJ7wtFiAA0AAAAAA==.',
Ca='Cadranak:BAABLgAECn8nAAIKAAkJ2BLLVQCiAQAKAAkJ2BLLVQCiAQAAAA==.Caiyenthi:BAABLgAECn8nAAIBAAgJkQ/wQACKAQABAAgJkQ/wQACKAQAAAA==.Calliesue:BAAALgAECgIJAgAAAA==.Camgor:BAAALgADCgEJAQABLgAECgYJEwADAAAAAA==.Carfalis:BAAALgADCggJCQAAAA==.',
Ch='Chelali:BAABLgAECn8XAAQIAAkJ8RVsJQAtAgAIAAgJ/BZsJQAtAgALAAUJ5BD/GwAhAQAMAAEJNAjWPAA8AAAAAA==.Chelly:BAAALgAECgEJAQABLgAECgkJFwAIAPEVAA==.Chicharrone:BAAALgAECgYJEgAAAA==.Chizaru:BAABLgAECn8XAAINAAgJHh1tCgCfAgANAAgJHh1tCgCfAgAAAA==.Chlorophyll:BAAALgADCgEJAQAAAA==.Chyntobelt:BAABLgAECn8dAAIOAAYJPgTftAC+AAAOAAYJPgTftAC+AAABLgAECggJKQAIAM0XAA==.',
Cr='Creep:BAAALgAECgYJEAAAAA==.Cryption:BAAALgAECggJEQAAAA==.',
['Cú']='Cúchulainn:BAAALgAECgYJDQAAAA==.',
Da='Daelyn:BAAALgAECgYJDwAAAA==.Dalhma:BAAALgAECgUJCQAAAA==.Dallma:BAAALgAECgcJCAABLgAECgUJCQADAAAAAQ==.Dane:BAAALgAECgIJAgAAAA==.Dayaris:BAAALgAECgUJCgAAAA==.',
De='Deadbeat:BAAALgAECgUJBgAAAA==.Deafenned:BAABLgAECn8aAAIPAAkJdx6gPQCBAgAPAAkJdx6gPQCBAgABLgAFFAMJBwAKANEOAA==.Deaflynn:BAAALgAECgEJAwABLgAFFAMJBwAKANEOAA==.Deafnight:BAAALgAECgIJBAABLgAFFAMJBwAKANEOAA==.Demonbep:BAAALgADCgQJBAABLgAECgkJGgAFADEVAA==.Demonicpower:BAAALgADCggJCAAAAA==.Derrington:BAABLgAECn8dAAIFAAcJPSA4AwAfAgAFAAcJPSA4AwAfAgAAAA==.Destinyetwo:BAAALgAECgEJAQAAAA==.Dett:BAAALgAECgUJDQAAAA==.',
Di='Diamante:BAACLgAFFH8KAAIQAAQJzxp+FQBIAQAQAAQJzxp+FQBIAQAuAAQKfykAAhAACAmHFxMqALwBABAACAmHFxMqALwBAAAA.',
Dk='Dkvayce:BAAALgADCgYJBgAAAA==.',
Dr='Drakluz:BAAALgADCgEJAQAAAA==.Drakner:BAABLgAECn8qAAMRAAgJKg7fJwBPAQARAAgJKg7fJwBPAQASAAQJBQJMMgCEAAAAAA==.Drellin:BAAALgAECgEJBAAAAA==.Dremu:BAABLgAECn8jAAMTAAgJ1xuTEAAKAgATAAgJ1xuTEAAKAgACAAMJEw9doACJAAAAAA==.',
Du='Duraz:BAABLgAECn8jAAICAAkJQQ4XTQBwAQACAAkJQQ4XTQBwAQAAAA==.',
Dy='Dysraxis:BAAALgADCgEJAQAAAA==.',
Ee='Eerie:BAAALgAECgIJBAAAAA==.',
Eg='Eggar:BAAALgADCgYJEgABLgAECggJHwAOAOsSAA==.',
El='Elahna:BAAALgADCgcJDQAAAA==.Elalia:BAAALgAECgYJEwAAAA==.Elamaun:BAABLgAECn8pAAINAAgJqBVQGwDeAQANAAgJqBVQGwDeAQAAAA==.Elereia:BAAALgAECgEJAQAAAA==.Eltiana:BAAALgAECgUJCAAAAA==.',
En='English:BAABLgAECn8VAAIGAAgJGwySJQBKAQAGAAgJGwySJQBKAQAAAA==.',
Ep='Ephex:BAAALgADCgcJGQAAAA==.Ephyiana:BAAALgADCgcJCAAAAA==.',
Er='Errimys:BAAALgADCgUJBQAAAA==.Ertraz:BAAALgAECgEJAQAAAA==.',
Es='Essense:BAAALgADCgcJBwAAAA==.Esçanor:BAAALgADCgUJBQAAAA==.',
Et='Etania:BAAALgAECgYJCQAAAA==.',
Fa='Faelyna:BAABLgAECn8pAAIJAAgJnA/JFgClAQAJAAgJnA/JFgClAQAAAA==.',
Fe='Felnut:BAAALgADCgEJAQAAAA==.',
Fo='Foix:BAAALgADCgcJDwAAAA==.Forged:BAABLgAECn8rAAIUAAgJ8x8RKQCBAgAUAAgJ8x8RKQCBAgAAAA==.',
Ga='Gaerne:BAAALgADCgEJAQAAAA==.',
Gi='Githyanki:BAAALgADCgkJCQAAAA==.',
Gl='Glabberghoul:BAABLgAECn8oAAIRAAkJQRSzGgCyAQARAAkJQRSzGgCyAQAAAA==.',
Go='Goodhead:BAAALgADCgMJBAAAAA==.',
Gr='Grangmage:BAAALgAECgQJDAAAAA==.Griogair:BAAALgADCgYJEQABLgAECgYJEwADAAAAAA==.',
Ha='Hacelian:BAAALgAECgEJAgAAAA==.Harper:BAAALgADCgcJBwAAAA==.',
He='Heetseeker:BAAALgAECgIJAgABLgAECgkJHAAQAMQgAA==.',
Hn='Hnoa:BAAALgADCgcJDwAAAA==.',
Ho='Hoggins:BAAALgADCgUJBQABLgADCgcJBwADAAAAAA==.Holyverdict:BAABLgAECn8XAAINAAkJUSWdBQASAwANAAkJUSWdBQASAwAAAA==.',
Ic='Icaina:BAABLgAECn8nAAIQAAkJoB8FFAB1AgAQAAkJoB8FFAB1AgAAAA==.',
In='Incinderella:BAAALgADCgEJAQABLgAECgYJDQADAAAAAA==.Interval:BAAALgADCgcJDgABLgAECgkJMQAUAJ4eAA==.',
Is='Islands:BAAALgADCgIJAgAAAA==.',
Ja='Jadani:BAAALgAECgYJEQAAAA==.',
Je='Jeisa:BAABLgAECn8VAAMUAAcJvAwdlQAAAQAUAAYJQA0dlQAAAQAVAAYJIAqVIgCsAAAAAA==.',
Ji='Jimbonereus:BAAALgADCgIJAgAAAA==.',
Jo='Jordyevoker:BAAALgAECggJDQAAAA==.',
Ka='Kalchee:BAAALgADCgIJAgAAAA==.Kallotera:BAABLgAECn8YAAMLAAcJ8gu9HQAUAQALAAcJ8gu9HQAUAQAIAAUJ4QbQcAD1AAAAAA==.Kastoria:BAAALgADCgkJFgAAAA==.Katnipp:BAABLgAECn8kAAIBAAkJPRqZMwDhAQABAAkJPRqZMwDhAQAAAA==.Katnyss:BAAALgAECgYJDQAAAA==.Kaylazune:BAABLgAECn8UAAMWAAcJCAtgMgD4AAAWAAYJpAtgMgD4AAAXAAYJKwjNMQDyAAAAAA==.',
Ke='Keramoon:BAAALgADCgUJBQAAAA==.Keyleth:BAAALgAECgEJAQAAAA==.',
Kh='Khrala:BAABLgAECn8fAAIOAAgJ6xKTTgCRAQAOAAgJ6xKTTgCRAQAAAA==.',
Ki='Kiye:BAACLgAFFH8TAAIBAAUJyBONIAA3AQABAAUJyBONIAA3AQAuAAQKfykAAgEACQnaG3gPAL8CAAEACQnaG3gPAL8CAAAA.',
Ko='Koren:BAAALgADCgMJAgAAAA==.',
Kr='Krenko:BAABLgAECn8VAAIOAAkJfwo0SwCbAQAOAAkJfwo0SwCbAQAAAA==.',
Ku='Kuuro:BAABLgAECn8bAAIQAAcJ4hWoLgCiAQAQAAcJ4hWoLgCiAQAAAA==.',
La='Lanister:BAAALgADCgQJBAAAAA==.Lattymag:BAAALgAECgUJBwAAAA==.Laughystabby:BAAALgAECgQJBAAAAA==.',
Le='Leibniz:BAABLgAECn8XAAIYAAcJzBpWBQDMAQAYAAcJzBpWBQDMAQAAAA==.Leisa:BAABLgAECn8bAAIBAAcJSQ8mUgBUAQABAAcJSQ8mUgBUAQAAAA==.Lelwindae:BAAALgAECgYJBwAAAA==.',
Li='Lifemoon:BAAALgAECgUJBgAAAA==.Lightgiver:BAAALgAECgUJBgAAAA==.Lighthoof:BAABLgAECn8gAAMUAAkJNx84FQDrAgAUAAkJNx84FQDrAgAVAAQJVBsaGwA1AQAAAA==.Lightiuz:BAABLgAECn8eAAMCAAYJBhbqRQCKAQACAAYJBhbqRQCKAQATAAQJZQGccgBXAAAAAA==.Liminara:BAEALgAFFAMJAwABLgAFFAcJFwABAGEYAA==.Linaste:BAAALgAECgQJBAAAAA==.Lirah:BAAALgAECggJCQABLgAFFAUJEwABAMgTAA==.Lividzdk:BAABLgAECn84AAMOAAkJGx/mDgC5AgAOAAkJGx/mDgC5AgAZAAIJOgwIQgA1AAAAAA==.',
Lo='Lonaldo:BAAALgAECgEJAQAAAA==.Lowpop:BAAALgADCgQJBAABLgAECgcJFgAaAJwPAA==.',
Lu='Lulu:BAABLgAFFH8JAAIaAAUJ9SPnAgCnAQAaAAUJ9SPnAgCnAQAAAA==.',
Ly='Lynoia:BAAALgAECgYJCAAAAA==.',
Ma='Malarus:BAAALgADCgEJAQAAAA==.Mandevu:BAAALgAECgUJBwAAAA==.Manknus:BAABLgAECn8mAAIIAAgJqw65JQB9AQAIAAgJqw65JQB9AQAAAA==.Mantequilla:BAABLgAECn8YAAIOAAcJTxzFSQAWAgAOAAcJTxzFSQAWAgAAAA==.Manthrax:BAABLgAECn8hAAIQAAkJLgf9TQBLAQAQAAkJLgf9TQBLAQAAAA==.Marix:BAAALgADCgEJAQAAAA==.',
Me='Megami:BAAALgADCgEJAgAAAA==.',
Mi='Missmolt:BAABLgAECn8cAAIbAAcJpSNeAgBgAgAbAAcJpSNeAgBgAgAAAA==.',
Mo='Molting:BAAALgAECgMJBAAAAA==.',
My='Mykara:BAAALgADCggJCwAAAA==.Mykie:BAAALgAECgYJBgAAAA==.Mylor:BAABLgAECn8oAAMNAAkJIBEKIwCjAQANAAkJIBEKIwCjAQAUAAEJvw/2SAEwAAAAAA==.Myrddral:BAABLgAECn8bAAIZAAcJgCAxDgCnAQAZAAcJgCAxDgCnAQAAAA==.Mystifeyed:BAABLgAECn8iAAMcAAkJGwoeHwDTAAAdAAcJYgmPFgBQAQAcAAgJMAceHwDTAAAAAA==.',
['Mü']='Mürsaat:BAABLgAECn8iAAIUAAgJIxRYRwCpAQAUAAgJIxRYRwCpAQAAAA==.',
Na='Namrekcah:BAAALgADCgcJDgABLgAFFAcJKQAZACIgAA==.Narra:BAAALgAECgIJAgABLgADCgcJBwADAAAAAA==.',
Ne='Nebalicious:BAAALgADCgcJDAABLgAECgYJDQADAAAAAA==.Nekonomiya:BAAALgADCgMJAwAAAA==.',
Ni='Nightlevels:BAABLgAECn85AAMXAAkJ2iNHAQCbAwAXAAkJ2iNHAQCbAwAWAAEJFCL/cgBcAAAAAA==.Nimbledragon:BAAALgADCggJCgAAAA==.',
Nt='Ntayu:BAABLgAECn8cAAIBAAcJFAbkagASAQABAAcJFAbkagASAQAAAA==.',
Ol='Olizia:BAABLgAECn8WAAIOAAcJiBKYdQCaAQAOAAcJiBKYdQCaAQAAAA==.',
On='Onaga:BAAALgAECgcJEAAAAA==.',
Op='Opex:BAABLgAECn8aAAMBAAkJyAyiSACQAQABAAkJyAyiSACQAQAHAAEJUQB9mwATAAAAAA==.Opheliabutts:BAAALgAECgQJBgAAAA==.',
Or='Oril:BAAALgAECgkJEQAAAA==.',
Pa='Paw:BAAALgADCgEJAgAAAA==.',
Pe='Penjei:BAAALgADCgYJBgAAAA==.',
Ph='Philomel:BAACLgAFFH8HAAIKAAMJ0Q4qQwDUAAAKAAMJ0Q4qQwDUAAAuAAQKfxwAAgoACAk/G84rAE8CAAoACAk/G84rAE8CAAAA.',
Pi='Pixamoo:BAAALgADCgUJCAAAAA==.',
Pl='Planeswalker:BAAALgADCgYJBgAAAA==.',
Po='Podnuh:BAAALgADCgIJAgAAAA==.Poxic:BAAALgADCgQJBAAAAA==.',
Pr='Priesthealz:BAAALgAECgcJCAABLgAECgkJLQAeAGYcAA==.Pritt:BAAALgADCgcJDQABLgAECgYJDAADAAAAAA==.',
Qu='Quazu:BAAALgADCgEJAQAAAA==.',
Ra='Radagahst:BAAALgAECgYJDQAAAA==.Rarngorm:BAABLgAECn8bAAIfAAgJ6BW7BwCeAQAfAAgJ6BW7BwCeAQAAAA==.Ravinar:BAABLgAECn8YAAIgAAgJlhI7AwCTAQAgAAgJlhI7AwCTAQAAAA==.',
Re='Reardain:BAAALgAECgYJEAAAAA==.Received:BAAALgAECgIJAgAAAA==.Relia:BAABLgAECn8XAAMGAAkJyQ/IIQDJAQAGAAgJNhDIIQDJAQAXAAEJKAalUwA5AAAAAA==.Remedy:BAAALgADCgcJBwAAAA==.',
Ri='Richardparkr:BAAALgAECgEJAQAAAA==.Riverwind:BAAALgAECgUJCgABLgAECgkJHAAQAMQgAA==.',
Rj='Rj:BAAALgADCgMJAwAAAA==.',
Ro='Romulus:BAAALgAECgcJEAAAAA==.',
Ry='Ryo:BAAALgAECgIJAgAAAA==.',
Sa='Safyra:BAAALgADCgYJCAAAAA==.Sakuf:BAAALgADCgcJBwAAAA==.Salana:BAAALgADCgQJBwAAAA==.Santofrancis:BAAALgAECgYJDgAAAA==.Sarbarola:BAAALgADCgkJBQAAAA==.Save:BAAALgAECgIJBAAAAA==.',
Se='Seraie:BAAALgAECgcJCQAAAA==.',
Sh='Shadethrower:BAABLgAECn8WAAIWAAkJ9hqVCwCXAgAWAAkJ9hqVCwCXAgAAAA==.Shallbedo:BAAALgAECgYJDAABLgAECggJIAASAK0aAA==.Shallvoker:BAABLgAECn8gAAMSAAgJrRrsCgAtAgASAAgJ4BbsCgAtAgARAAQJLxaeOQDyAAAAAA==.Shazammy:BAAALgADCgMJBAAAAA==.Shmalexia:BAAALgAECgIJAgAAAA==.',
Si='Siatraler:BAAALgAECggJDgAAAA==.Sigarette:BAACLgAFFH8pAAIZAAcJIiC2AQAsAgAZAAcJIiC2AQAsAgAuAAQKfzQAAhkACAnXJJkCAEIDABkACAnXJJkCAEIDAAAA.Silverspoon:BAAALgAECgIJAgAAAA==.Sinardi:BAABLgAECn8XAAIhAAYJhQy3NgAsAQAhAAYJhQy3NgAsAQAAAA==.',
Sk='Skoobz:BAAALgAECgEJAQAAAA==.Skubasteve:BAAALgAECgYJDwAAAA==.Skydragon:BAAALgAECgYJBgAAAA==.Skylock:BAABLgAECn8WAAQYAAkJjAx+BgCsAQAYAAkJFAx+BgCsAQAFAAYJkAclFwCzAAAEAAMJOgLv1QBbAAAAAA==.Skymane:BAAALgAECgYJEQAAAA==.',
Sn='Snaggletooth:BAAALgADCgEJAQAAAA==.',
So='Solar:BAAALgAFFAMJAwAAAA==.Sovix:BAAALgADCgIJAgAAAA==.Sovo:BAACLgAFFH8SAAIPAAYJDBmmFAC1AQAPAAYJDBmmFAC1AQAuAAQKfykAAg8ACQlEIpcdAP8CAA8ACQlEIpcdAP8CAAAA.',
Sq='Squshmepure:BAAALgAECgYJAgAAAA==.',
St='Starrin:BAAALgAECgYJEAAAAA==.Steaknquake:BAABLgAECn8pAAIQAAgJriCzCADdAgAQAAgJriCzCADdAgAAAA==.',
Su='Sumdumfun:BAAALgAECgMJAwAAAA==.Sunflower:BAAALgAECgYJDQAAAA==.',
Sv='Svaha:BAAALgAECgIJAgAAAA==.',
Sy='Sybri:BAABLgAECn8WAAMBAAgJ5RgjOQDKAQABAAcJNRojOQDKAQAHAAUJ6wsrWQDhAAAAAA==.Sylvandel:BAABLgAECn8cAAIHAAcJFRPZDAAXAQAHAAcJFRPZDAAXAQAAAA==.',
Ta='Talthis:BAAALgAECgIJAgAAAA==.',
Te='Teagen:BAABLgAECn8sAAICAAkJNgZpSwAbAQACAAkJNgZpSwAbAQAAAA==.',
Th='Thalius:BAABLgAECn8bAAIOAAcJig2PbABEAQAOAAcJig2PbABEAQAAAA==.Thorandaal:BAAALgAECgUJCgAAAA==.',
Ti='Tisbish:BAAALgADCgIJAgAAAA==.',
To='Tome:BAABLgAECn8hAAQHAAkJ6SYDAAAbBAAHAAkJ3CYDAAAbBAAJAAkJwyY5AACCAwABAAEJEyZfsgBqAAAAAA==.Tometv:BAAALgAECgcJBgABLgAECgkJIQAHAOkmAA==.Toomanydeths:BAABLgAECn8yAAMZAAkJpw/rEgBpAQAZAAkJpw/rEgBpAQAOAAEJqAiRIgExAAAAAA==.',
Tr='Trunx:BAAALgAECgQJBQABLgAECgkJHwAiAN4jAA==.',
Ty='Tye:BAAALgAECgYJDwAAAA==.Tyyle:BAAALgADCgYJBgAAAA==.',
['Tá']='Tálos:BAAALgAECgEJBAAAAA==.',
Ul='Uldear:BAAALgADCgYJCwAAAA==.',
Un='Unbuttered:BAAALgAECgIJAwAAAA==.',
Ur='Ursusmanny:BAAALgAECgMJAwAAAA==.',
Va='Vaelthyeth:BAAALgADCgUJBQAAAA==.Vandarin:BAAALgADCgcJGgABLgAECgYJEwADAAAAAA==.Vanthrall:BAAALgAECgQJCgAAAA==.Vayce:BAABLgAECn8yAAMjAAkJ5iG0AQCnAgAjAAgJyCK0AQCnAgAkAAcJRyL/GAA9AgAAAA==.',
Ve='Velysa:BAABLgAECn8gAAMVAAgJcRZuCgDPAQAVAAgJcRZuCgDPAQAUAAIJOgkyHgFgAAAAAA==.',
Vi='Vizago:BAAALgADCgEJAQAAAA==.',
Vo='Vogekth:BAAALgAECgUJCwAAAA==.',
['Vÿ']='Vÿktor:BAAALgADCgYJBgAAAA==.',
Wa='Warseeker:BAABLgAECn8cAAMQAAkJxCAlCADzAgAQAAkJxCAlCADzAgAlAAMJkg5QVQCNAAAAAA==.Watlmonk:BAAALgADCgIJAgAAAA==.',
We='Weatherworn:BAABLgAECn8hAAIQAAYJ6RggMgCPAQAQAAYJ6RggMgCPAQAAAA==.',
Xe='Xemu:BAAALgAECgQJBAAAAA==.Xenferos:BAAALgADCgcJDAABLgAECggJGwAFAN4XAA==.Xerber:BAAALgADCgYJCgABLgAECgYJEwADAAAAAA==.',
Xi='Xiro:BAAALgAECgUJEQAAAA==.',
Yo='Yoril:BAAALgAECgQJBQAAAA==.',
Za='Zagiroth:BAABLgAECn8sAAMKAAkJFSGABwDmAgAKAAkJFSGABwDmAgAmAAEJFhthJwBLAAAAAA==.Zalthanos:BAAALgADCgEJAQAAAA==.Zarack:BAAALgADCgYJBAABLgAECgYJEwADAAAAAA==.',
Ze='Zebraman:BAABLgAECn8VAAICAAgJCxKINACCAQACAAgJCxKINACCAQAAAA==.Zeraida:BAAALgADCgcJDAAAAA==.',
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
