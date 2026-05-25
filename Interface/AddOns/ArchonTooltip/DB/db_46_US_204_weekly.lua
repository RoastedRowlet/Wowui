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

local lookup = {'Hunter-BeastMastery','Druid-Restoration','Hunter-Marksmanship','Monk-Brewmaster','Monk-Windwalker','Warlock-Destruction','Warlock-Demonology','Priest-Shadow','Warrior-Fury','Hunter-Survival','DemonHunter-Devourer','Warrior-Arms','Warrior-Protection','Paladin-Holy','DeathKnight-Unholy','Unknown-Unknown','Mage-Frost','Shaman-Elemental','Shaman-Restoration','Evoker-Augmentation','Evoker-Devastation','Druid-Balance','Paladin-Retribution','Paladin-Protection','Priest-Discipline','Priest-Holy','Warlock-Affliction','DeathKnight-Blood','Monk-Mistweaver','Rogue-Outlaw','Druid-Guardian','Druid-Feral','DeathKnight-Frost','Mage-Fire','DemonHunter-Havoc','DemonHunter-Vengeance','Rogue-Assassination','Rogue-Subtlety',}
local provider = {region='US',realm='SteamwheedleCartel',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aalwein:BAABLgAECn8pAAIBAAkJsx+UEQCbAgABAAkJsx+UEQCbAgAAAA==.',
Ae='Aesculapius:BAABLgAECn8hAAICAAkJ1BZmGABgAgACAAkJ1BZmGABgAgAAAA==.',
Al='Aladia:BAAALgADCgMJAgAAAA==.Aloisious:BAAALgAECgEJAQAAAA==.',
Am='Amarii:BAABLgAECn8aAAIDAAcJZgmAFAD0AAADAAcJZgmAFAD0AAAAAA==.Amorash:BAAALgADCgEJAQAAAA==.',
An='Anonymus:BAACLgAFFH8GAAIEAAIJ2xWyOACXAAAEAAIJ2xWyOACXAAAuAAQKfxgAAwQACQlKHeYMAEgCAAQACAksHuYMAEgCAAUAAgmiEPNuAEwAAAAA.',
Ar='Ara:BAABLgAECn8oAAIBAAkJoSCVCwDTAgABAAkJoSCVCwDTAgAAAA==.Ardwin:BAAALgADCgEJAQABLgAECgYJFwAGAGwHAA==.',
As='Ashgrove:BAAALgAECgUJCAAAAA==.',
Av='Avigar:BAAALgADCgEJAwAAAA==.',
Ba='Bambarrok:BAABLgAECn8XAAIHAAkJSQbpaQBSAQAHAAkJSQbpaQBSAQAAAA==.Bangan:BAAALgAECgYJBwAAAA==.',
Be='Belakor:BAAALgAECgYJBgAAAA==.Bep:BAAALgAECgYJDAABLgAECgkJGgAGADEVAA==.Bepragosa:BAABLgAECn8aAAIGAAkJMRWkCAA3AgAGAAkJMRWkCAA3AgAAAA==.',
Bi='Binpharteen:BAAALgADCgkJGAAAAA==.',
Bl='Blaque:BAAALgADCgcJBwABLgAECggJFQAIABoMAA==.',
Br='Brimscythe:BAAALgAECgEJAgAAAA==.Brownbelt:BAABLgAECn8yAAIJAAgJYBtKFwAQAgAJAAgJYBtKFwAQAgAAAA==.Brîn:BAAALgAECgEJAgAAAA==.',
Bu='Buteihunter:BAABLgAECn8tAAQBAAkJhyANEQCgAgABAAkJhyANEQCgAgADAAEJ7wtFiAA0AAAKAAEJEgcpWAAyAAAAAA==.',
Ca='Cadranak:BAABLgAECn8wAAILAAkJ2RLPNQDOAQALAAkJ2RLPNQDOAQAAAA==.Caiyenthi:BAABLgAECn8nAAIBAAgJkQ/5TgCHAQABAAgJkQ/5TgCHAQAAAA==.Calliesue:BAAALgAECgIJAgAAAA==.Camgor:BAAALgADCgEJAQABLgAECgYJFwAGAGwHAA==.Carfalis:BAAALgADCggJCQAAAA==.',
Ch='Chelali:BAABLgAECn8XAAQJAAkJ8RVsJQAtAgAJAAgJ/BZsJQAtAgAMAAUJ5BA4IgAlAQANAAEJNAisRAA5AAAAAA==.Chelly:BAAALgAECgEJAQABLgAECgkJFwAJAPEVAA==.Chicharrone:BAAALgAECgYJEgAAAA==.Chizaru:BAABLgAECn8gAAIOAAkJWx5dBQAeAwAOAAkJWx5dBQAeAwAAAA==.Chlorophyll:BAAALgADCgQJBQAAAA==.Chyntobelt:BAABLgAECn8jAAIPAAYJiwXewgDOAAAPAAYJiwXewgDOAAABLgAECggJMgAJAGAbAA==.',
Cr='Creep:BAAALgAECgYJEAAAAA==.Cryption:BAABLgAECn8VAAIBAAgJkhQEOADOAQABAAgJkhQEOADOAQAAAA==.',
['Cú']='Cúchulainn:BAAALgAECgYJDQAAAA==.',
Da='Daelyn:BAABLgAECn8UAAIBAAYJag+yeQAdAQABAAYJag+yeQAdAQAAAA==.Dalhma:BAAALgAECgUJCQAAAA==.Dallma:BAAALgAFFAMJAwABLgAECgUJCQAQAAAAAQ==.Dane:BAAALgAECgIJAgAAAA==.Dayaris:BAAALgAECgUJDwAAAA==.',
De='Deadbeat:BAAALgAECgUJBgAAAA==.Deafenned:BAABLgAECn8aAAIRAAkJdx6gPQCBAgARAAkJdx6gPQCBAgABLgAFFAMJBwALANEOAA==.Deaflynn:BAAALgAECgEJAwABLgAFFAMJBwALANEOAA==.Deafnight:BAAALgAECgIJBAABLgAFFAMJBwALANEOAA==.Demonbep:BAAALgADCgQJBAABLgAECgkJGgAGADEVAA==.Demonicpower:BAAALgADCggJCAAAAA==.Derrington:BAABLgAECn8kAAIGAAcJkSE0AwBCAgAGAAcJkSE0AwBCAgAAAA==.Destinyetwo:BAAALgAECgEJAQAAAA==.Dett:BAABLgAECn8UAAISAAYJsAk/UwC8AAASAAYJsAk/UwC8AAAAAA==.',
Di='Diamante:BAACLgAFFH8PAAITAAQJzxp/HQA9AQATAAQJzxp/HQA9AQAuAAQKfyoAAhMACQlBFjcpAOoBABMACQlBFjcpAOoBAAAA.',
Dk='Dkvayce:BAAALgADCgYJBgAAAA==.',
Dr='Dragqueene:BAAALgAFFAEJAQAAAA==.Drakluz:BAAALgADCgEJAQAAAA==.Drakner:BAABLgAECn8xAAMUAAgJKw6aLABkAQAUAAgJKw6aLABkAQAVAAQJBQJMMgCEAAAAAA==.Drellin:BAAALgAECgEJBAAAAA==.Dremu:BAABLgAECn8lAAMWAAgJ9hy8EAAwAgAWAAgJ9hy8EAAwAgACAAMJEw9doACJAAAAAA==.',
Du='Duraz:BAABLgAECn8jAAICAAkJQg5VQABtAQACAAkJQg5VQABtAQAAAA==.',
Dy='Dysraxis:BAAALgADCgEJAQAAAA==.',
Ee='Eerie:BAAALgAECgIJBAAAAA==.',
Eg='Eggar:BAAALgADCgYJEgABLgAECggJHwAPAO0SAA==.',
El='Elahna:BAAALgADCgcJDQAAAA==.Elalia:BAABLgAECn8XAAIGAAYJbAfBGQC2AAAGAAYJbAfBGQC2AAAAAA==.Elamaun:BAABLgAECn8yAAIOAAgJqBUPIQDVAQAOAAgJqBUPIQDVAQAAAA==.Elereia:BAAALgAECgEJAQAAAA==.Eltiana:BAAALgAECgUJCwAAAA==.',
En='English:BAABLgAECn8VAAIIAAgJGgxGKwBRAQAIAAgJGgxGKwBRAQAAAA==.',
Ep='Ephex:BAAALgADCgcJGQAAAA==.Ephyiana:BAAALgADCgcJCAAAAA==.',
Er='Errimys:BAAALgADCgUJBQAAAA==.Ertraz:BAAALgAECgEJAgAAAA==.',
Es='Essense:BAAALgADCgcJBwAAAA==.Esçanor:BAAALgADCgUJBQAAAA==.',
Et='Etania:BAAALgAECgYJCQAAAA==.',
Fa='Faelyna:BAABLgAECn8yAAIKAAgJghE2GADAAQAKAAgJghE2GADAAQAAAA==.',
Fe='Felnut:BAAALgADCgEJAQAAAA==.',
Fo='Foix:BAAALgADCgcJDwAAAA==.Forged:BAACLgAFFH8GAAIXAAIJvRl7XwCvAAAXAAIJvRl7XwCvAAAuAAQKfysAAhcACAnzHxEpAIECABcACAnzHxEpAIECAAAA.',
Ga='Gaerne:BAAALgADCgEJAQAAAA==.',
Gi='Githyanki:BAAALgADCgkJCQAAAA==.',
Gl='Glabberghoul:BAABLgAECn8sAAIUAAkJQhStHQDHAQAUAAkJQhStHQDHAQAAAA==.',
Go='Goodhead:BAAALgADCgMJBAAAAA==.',
Gr='Grangmage:BAAALgAECgQJDQAAAA==.Griogair:BAAALgADCgYJFQABLgAECgYJFwAGAGwHAA==.',
Ha='Hacelian:BAAALgAECgEJAwAAAA==.Harper:BAAALgADCgcJBwAAAA==.',
He='Heetseeker:BAAALgAECgQJCAABLgAECgkJHQATAMQgAA==.',
Hn='Hnoa:BAAALgADCgcJDwAAAA==.',
Ho='Hoggins:BAAALgADCgUJBQABLgADCgcJBwAQAAAAAA==.Holyverdict:BAABLgAECn8XAAIOAAkJUSWdBQASAwAOAAkJUSWdBQASAwAAAA==.',
Ic='Icaina:BAABLgAECn8vAAITAAkJoB8FFAB1AgATAAkJoB8FFAB1AgAAAA==.',
In='Incinderella:BAAALgADCgEJAQABLgAECgYJDQAQAAAAAA==.Interval:BAAALgADCgcJDgABLgAECgkJOgAXADsfAA==.',
Is='Islands:BAAALgADCgIJAgAAAA==.',
Ja='Jadani:BAABLgAECn8WAAIGAAcJ1g8gDwAhAQAGAAcJ1g8gDwAhAQAAAA==.',
Je='Jeisa:BAABLgAECn8cAAMYAAcJLg/8HgDsAAAXAAYJQA15sgD5AAAYAAYJiQ/8HgDsAAAAAA==.',
Ji='Jimbonereus:BAAALgADCgIJAgAAAA==.',
Jo='Jordyevoker:BAAALgAECggJDQAAAA==.',
Ju='Juanns:BAAALgAECgYJDAAAAA==.',
Ka='Kalchee:BAAALgADCgIJAgAAAA==.Kallotera:BAABLgAECn8fAAMMAAcJUAz+IwAZAQAMAAcJUAz+IwAZAQAJAAUJ4QbQcAD1AAAAAA==.Kastoria:BAAALgADCgkJFgAAAA==.Katnipp:BAABLgAECn8pAAIBAAkJyRqzGQBjAgABAAkJyRqzGQBjAgAAAA==.Katnyss:BAAALgAECgYJDQAAAA==.Kaylazune:BAABLgAECn8bAAMZAAcJ/AtnLQA+AQAZAAcJgQlnLQA+AQAaAAYJpAuGOAD0AAAAAA==.',
Ke='Keramoon:BAAALgADCgUJBQAAAA==.Keyleth:BAAALgAECgEJAQAAAA==.',
Kh='Khrala:BAABLgAECn8fAAIPAAgJ7RI+XgCKAQAPAAgJ7RI+XgCKAQAAAA==.',
Ki='Kiye:BAACLgAFFH8TAAIBAAUJyBOGLQAnAQABAAUJyBOGLQAnAQAuAAQKfykAAgEACQnaG3gPAL8CAAEACQnaG3gPAL8CAAAA.',
Ko='Koren:BAAALgADCgMJAgAAAA==.',
Kr='Krenko:BAABLgAECn8VAAIPAAkJgApzWACZAQAPAAkJgApzWACZAQAAAA==.',
Ku='Kuuro:BAABLgAECn8iAAITAAcJchbCNQCpAQATAAcJchbCNQCpAQAAAA==.',
La='Lanister:BAAALgADCgQJBAAAAA==.Lattymag:BAAALgAECgUJBwAAAA==.Laughystabby:BAAALgAECgQJBAAAAA==.',
Le='Leibniz:BAABLgAECn8eAAIbAAcJoh7TBQD0AQAbAAcJoh7TBQD0AQAAAA==.Leisa:BAABLgAECn8hAAIBAAcJzA/zWgBmAQABAAcJzA/zWgBmAQAAAA==.Lelwindae:BAAALgAECgYJCAAAAA==.',
Li='Lifemoon:BAAALgAECgcJDgAAAA==.Lightgiver:BAAALgAECgYJCgAAAA==.Lighthoof:BAABLgAECn8gAAMXAAkJNx84FQDrAgAXAAkJNx84FQDrAgAYAAQJVBsaGwA1AQAAAA==.Lightiuz:BAABLgAECn8eAAMCAAYJBhbqRQCKAQACAAYJBhbqRQCKAQAWAAQJZQGccgBXAAAAAA==.Liminara:BAEALgAFFAMJAwABLgAFFAcJGwABAPkZAA==.Linaste:BAAALgAECgQJBAAAAA==.Lirah:BAAALgAECggJCQABLgAFFAUJEwABAMgTAA==.Lividzdk:BAABLgAECn9BAAMPAAkJBiEnCwD2AgAPAAkJBiEnCwD2AgAcAAIJOgw+QwBTAAAAAA==.',
Lo='Lonaldo:BAAALgAECgEJAQAAAA==.Lowpop:BAAALgADCgQJBAABLgAECgcJFgAFAJwPAA==.',
Lu='Lulu:BAABLgAFFH8OAAMFAAUJTCQPBACmAQAFAAUJTCQPBACmAQAdAAEJ6QEgRwArAAAAAA==.',
Ly='Lynoia:BAAALgAECgYJCAAAAA==.',
Ma='Malarus:BAAALgADCgEJAQAAAA==.Mandevu:BAAALgAECgUJBwAAAA==.Manknus:BAABLgAECn8tAAIJAAgJ7BEnJQCoAQAJAAgJ7BEnJQCoAQAAAA==.Mantequilla:BAABLgAECn8YAAIPAAcJTxzFSQAWAgAPAAcJTxzFSQAWAgAAAA==.Manthrax:BAABLgAECn8qAAITAAkJJQkjQQB3AQATAAkJJQkjQQB3AQAAAA==.Marix:BAAALgADCgEJAQAAAA==.',
Me='Megami:BAAALgADCgEJAgAAAA==.',
Mi='Missmolt:BAABLgAECn8jAAIeAAcJWSRUAgB+AgAeAAcJWSRUAgB+AgAAAA==.',
Mo='Molting:BAAALgAECgMJBAAAAA==.',
My='Mykara:BAAALgADCggJDAAAAA==.Mykie:BAAALgAECgcJCwAAAA==.Mylor:BAABLgAECn8xAAMOAAkJQhO6GwD/AQAOAAkJQhO6GwD/AQAXAAEJvw/2SAEwAAAAAA==.Myrddral:BAABLgAECn8hAAIcAAcJsCK2CQBMAgAcAAcJsCK2CQBMAgAAAA==.Mystifeyed:BAABLgAECn8mAAMfAAkJdQrfJQDfAAAgAAcJYgmPFgBQAQAfAAgJHQjfJQDfAAAAAA==.',
['Mü']='Mürsaat:BAABLgAECn8iAAIXAAgJIxR/VwCmAQAXAAgJIxR/VwCmAQAAAA==.',
Na='Namrekcah:BAAALgADCgcJDgABLgAFFAgJMQAcAJYgAA==.Narra:BAAALgAECgQJBQABLgADCgcJBwAQAAAAAA==.',
Ne='Nebalicious:BAAALgADCgcJDAABLgAECgYJDQAQAAAAAA==.Nekonomiya:BAAALgADCgMJAwAAAA==.',
Ni='Nightlevels:BAABLgAECn85AAMZAAkJ2iPMAQCUAwAZAAkJ2iPMAQCUAwAaAAEJFCL/cgBcAAAAAA==.Nimbledragon:BAAALgADCggJCgAAAA==.',
Nt='Ntayu:BAABLgAECn8jAAIBAAcJQwZiewAZAQABAAcJQwZiewAZAQAAAA==.',
Ol='Olizia:BAABLgAECn8WAAIPAAcJiBKYdQCaAQAPAAcJiBKYdQCaAQAAAA==.',
On='Onaga:BAABLgAECn8WAAIXAAcJvwND0gDKAAAXAAcJvwND0gDKAAAAAA==.',
Op='Opex:BAACLgAFFH8FAAIBAAIJHAO4aAB4AAABAAIJHAO4aAB4AAAuAAQKfxoAAwEACQnJDKJIAJABAAEACQnJDKJIAJABAAMAAQlRAH2bABMAAAAA.Opheliabutts:BAAALgAECgQJBgAAAA==.',
Or='Oril:BAAALgAECgkJEQAAAA==.',
Pa='Paw:BAAALgADCgEJAgAAAA==.',
Pe='Penjei:BAAALgADCgYJBgAAAA==.Perkyblade:BAAALgAECgcJCAAAAA==.',
Ph='Philomel:BAACLgAFFH8HAAILAAMJ0Q7pTgDNAAALAAMJ0Q7pTgDNAAAuAAQKfxwAAgsACAk/G84rAE8CAAsACAk/G84rAE8CAAAA.',
Pi='Piekal:BAAALgAECgcJBwAAAA==.Pixamoo:BAAALgADCgUJCAAAAA==.',
Pl='Planeswalker:BAAALgADCgYJBgAAAA==.',
Po='Podnuh:BAAALgADCgIJAgAAAA==.Poxic:BAAALgADCgQJBAAAAA==.',
Pr='Priesthealz:BAAALgAECgcJDAABLgAECgkJLgAEAKEcAA==.Pritt:BAAALgADCgcJDQABLgAECgcJDwAQAAAAAA==.',
Qu='Quazu:BAAALgAECgcJBwAAAA==.',
Ra='Radagahst:BAAALgAECgYJDQAAAA==.Rarngorm:BAABLgAECn8cAAIhAAgJ6RXxCgCGAQAhAAgJ6RXxCgCGAQAAAA==.Ravinar:BAABLgAECn8YAAIiAAgJlhLKAwCYAQAiAAgJlhLKAwCYAQAAAA==.Raàm:BAAALgADCgEJAQAAAA==.',
Re='Reardain:BAAALgAECgYJEAAAAA==.Received:BAAALgAECgIJAgAAAA==.Relia:BAABLgAECn8YAAMIAAkJyQ/IIQDJAQAIAAgJNhDIIQDJAQAZAAEJKAYJYAA5AAAAAA==.Remedy:BAAALgADCgcJBwAAAA==.',
Ri='Richardparkr:BAAALgAECgEJAQAAAA==.Rillty:BAAALgAECgIJAgAAAA==.Riverwind:BAAALgAECgUJCgABLgAECgkJHQATAMQgAA==.',
Rj='Rj:BAAALgADCgMJAwAAAA==.',
Ro='Romulus:BAABLgAECn8WAAICAAcJxg/ORgBRAQACAAcJxg/ORgBRAQAAAA==.',
Ry='Ryo:BAAALgAECgIJAgAAAA==.',
Sa='Safyra:BAAALgADCgYJCAAAAA==.Sakoian:BAAALgAECgEJAQAAAA==.Sakuf:BAAALgADCgcJBwAAAA==.Salana:BAAALgADCgQJBwAAAA==.Santofrancis:BAABLgAECn8XAAIFAAkJpwlHLwAhAQAFAAkJpwlHLwAhAQAAAA==.Sarbarola:BAAALgADCgkJBQAAAA==.Save:BAAALgAECgIJBAABLgAECggJIAAaAIgfAA==.',
Se='Seraie:BAAALgAECgcJCQAAAA==.',
Sh='Shadethrower:BAABLgAECn8WAAIaAAkJ9hqVCwCXAgAaAAkJ9hqVCwCXAgAAAA==.Shallbedo:BAAALgAECgYJDQABLgAECggJIwAVANEaAA==.Shallvoker:BAABLgAECn8jAAMVAAgJ0RrsCgAtAgAVAAgJBBfsCgAtAgAUAAQJLxZdRADwAAAAAA==.Shazammy:BAAALgADCgMJBAAAAA==.Shmalexia:BAAALgAECgIJAgAAAA==.',
Si='Siatraler:BAAALgAECggJDgAAAA==.Sigarette:BAACLgAFFH8xAAIcAAgJliDnAAChAgAcAAgJliDnAAChAgAuAAQKfzkAAhwACAnXJJkCAEIDABwACAnXJJkCAEIDAAAA.Silverspoon:BAAALgAECgIJAgAAAA==.Sinardi:BAABLgAECn8hAAMjAAYJBhXzHwA9AQAjAAYJHxTzHwA9AQAkAAMJSw6ZIQBhAAAAAA==.',
Sk='Skoobz:BAAALgAECgEJAgAAAA==.Skubasteve:BAAALgAECgYJDwAAAA==.Skydragon:BAAALgAECgYJBgAAAA==.Skylock:BAABLgAECn8WAAQbAAkJiwzoCACjAQAbAAkJFAzoCACjAQAGAAYJkAdMGgCyAAAHAAMJOgKh7wBaAAAAAA==.Skymane:BAABLgAECn8VAAMIAAYJmw/XNABEAQAIAAYJmw/XNABEAQAaAAEJfgJdhQAsAAAAAA==.',
Sn='Snaggletooth:BAAALgADCgEJAQAAAA==.',
So='Solar:BAAALgAFFAMJAwAAAA==.Sovix:BAAALgAECgEJAQAAAA==.Sovo:BAACLgAFFH8VAAIRAAYJoRm9HQCsAQARAAYJoRm9HQCsAQAuAAQKfyoAAhEACQlEIpcdAP8CABEACQlEIpcdAP8CAAAA.',
Sq='Squshmepure:BAAALgAECgYJAgAAAA==.',
St='Starrin:BAAALgAECgYJEAAAAA==.Steaknquake:BAABLgAECn8yAAITAAgJriD0CwDUAgATAAgJriD0CwDUAgAAAA==.',
Su='Sumdumfun:BAAALgAECgMJAwAAAA==.Sunflower:BAAALgAECgYJDQAAAA==.',
Sv='Svaha:BAAALgAECgIJAgAAAA==.',
Sy='Sybri:BAABLgAECn8WAAMBAAgJ5RgjOQDKAQABAAcJNRojOQDKAQADAAUJ6wsrWQDhAAAAAA==.Sylvandel:BAABLgAECn8jAAIDAAcJ0RPzDQBVAQADAAcJ0RPzDQBVAQAAAA==.',
Ta='Talthis:BAAALgAECgIJAgAAAA==.',
Te='Teagen:BAABLgAECn8zAAICAAkJggjDSgBBAQACAAkJggjDSgBBAQAAAA==.',
Th='Thalius:BAABLgAECn8iAAIPAAcJug5RdgBRAQAPAAcJug5RdgBRAQAAAA==.Thorandaal:BAAALgAECgUJDwAAAA==.Thunderbuddy:BAAALgADCgEJAQAAAA==.',
Ti='Tisbish:BAAALgADCgIJAgAAAA==.',
To='Tome:BAABLgAECn8hAAQDAAkJ6SYDAAAbBAADAAkJ3CYDAAAbBAAKAAkJxCZnAAB6AwABAAEJEyaYzgBmAAAAAA==.Tometv:BAAALgAECgcJBgABLgAECgkJIQADAOkmAA==.Toomanydeths:BAABLgAECn84AAMcAAkJsQ+9FwB2AQAcAAkJsQ+9FwB2AQAPAAUJvQpOqQD1AAAAAA==.',
Tr='Trunx:BAAALgAECgQJBQABLgAECgkJHwAdAN4jAA==.',
Ty='Tye:BAAALgAECgYJDwAAAA==.Tyyle:BAAALgADCgYJBgAAAA==.',
['Tá']='Tálos:BAAALgAECgEJBAAAAA==.',
Ul='Uldear:BAAALgADCgYJCwAAAA==.',
Un='Unbuttered:BAAALgAECgIJBAAAAA==.',
Ur='Ursusmanny:BAAALgAECgYJCQAAAA==.',
Va='Vaelthyeth:BAAALgADCgUJBQAAAA==.Valkyrie:BAAALgAECgYJBgABLgAECgkJLgAEAKEcAA==.Vandarin:BAAALgADCgcJGgABLgAECgYJFwAGAGwHAA==.Vanthrall:BAAALgAECgQJCgAAAA==.Vayce:BAABLgAECn8yAAMlAAkJ5iFHAgCZAgAlAAgJyCJHAgCZAgAmAAcJRyL/GAA9AgAAAA==.',
Ve='Velysa:BAABLgAECn8pAAMYAAgJyxjBCgDxAQAYAAgJyxjBCgDxAQAXAAIJOgkyHgFgAAAAAA==.',
Vi='Vizago:BAAALgADCgEJAQAAAA==.',
Vo='Vogekth:BAAALgAECgUJCwAAAA==.',
['Vÿ']='Vÿktor:BAAALgADCgYJBgAAAA==.',
Wa='Warseeker:BAABLgAECn8dAAMTAAkJxCAlCADzAgATAAkJxCAlCADzAgASAAQJ1w5tUwC7AAAAAA==.Watlmonk:BAAALgADCgIJAgAAAA==.',
We='Weatherworn:BAABLgAECn8nAAITAAYJTxvgMgC4AQATAAYJTxvgMgC4AQAAAA==.',
Xe='Xemu:BAAALgAECgQJBAAAAA==.Xenferos:BAAALgADCgcJDAABLgAECggJHQAGAAQYAA==.Xerber:BAAALgADCgYJCgABLgAECgYJFwAGAGwHAA==.',
Xi='Xiro:BAAALgAECgUJEQAAAA==.',
Yo='Yoril:BAAALgAECgcJDgAAAA==.',
Za='Zagihex:BAAALgAECgcJBwAAAA==.Zagiroth:BAABLgAECn8sAAMLAAkJFiEcCgDiAgALAAkJFiEcCgDiAgAkAAEJFhthJwBLAAAAAA==.Zalthanos:BAAALgADCgEJAQAAAA==.Zarack:BAAALgADCgYJBAABLgAECgYJFwAGAGwHAA==.',
Ze='Zebraman:BAABLgAECn8VAAICAAgJDBJJOwCFAQACAAgJDBJJOwCFAQAAAA==.Zeraida:BAAALgADCgcJDAAAAA==.',
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
