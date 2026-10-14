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

local lookup = {'Evoker-Augmentation','Evoker-Devastation','Druid-Restoration','DemonHunter-Vengeance','Hunter-BeastMastery','Warrior-Arms','Mage-Arcane','Monk-Windwalker','Hunter-Marksmanship','Shaman-Restoration','Shaman-Elemental','Unknown-Unknown','Warrior-Protection','DeathKnight-Unholy','DeathKnight-Frost','Priest-Holy','Priest-Shadow','Paladin-Retribution','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Blood','Hunter-Survival','Druid-Guardian','Warlock-Affliction','Warlock-Destruction','Warlock-Demonology','Monk-Brewmaster','Evoker-Preservation','Rogue-Outlaw','Paladin-Protection','Druid-Balance','DemonHunter-Devourer','Paladin-Holy','Mage-Frost','DemonHunter-Havoc','Shaman-Enhancement','Priest-Discipline','Warrior-Fury','Mage-Fire',}
local provider = {region='US',realm='Darkspear',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abssorath:BAAANQADCgYIBgAAAA==.',
Ae='Aerouant:BAABNQAECn8pAAMBAAkKeReMBgBWAgABAAkKeReMBgBWAgACAAQKnw8LKADtAAAAAA==.',
Ai='Aidix:BAAANQADCggIFQAAAA==.Aimassist:BAAANQAECgQIBAAAAA==.',
Al='Alaliix:BAAANQADCgEIAQAAAA==.Alcyone:BAABNQAECn8rAAIDAAkKARwzDwDfAgADAAkKARwzDwDfAgAAAA==.Allophone:BAAANQADCgIIAgAAAA==.Almightyhunt:BAAANQADCgMIAwAAAA==.Altimys:BAAANQADCgIIAgAAAA==.Alwaysbroke:BAAANQAECgQIBAAAAA==.',
An='Andycat:BAAANQAECgEIAQAAAA==.Annarchy:BAAANQADCgQIBAAAAA==.Antakata:BAAANQADCgcIBwAAAA==.Antapathy:BAABNQAECn8rAAIEAAkKQBatCQBEAgAEAAkKQBatCQBEAgAAAA==.Anthross:BAABNQAECn8gAAIFAAgKmA9vhAD/AQAFAAgKmA9vhAD/AQAAAA==.',
Ap='Apollovon:BAABNQAECn8hAAIGAAgKcCHILAAHAwAGAAgKcCHILAAHAwAAAA==.Applebees:BAAANQAECgEIAQAAAA==.',
Ar='Arcanemage:BAAANQADCgYIBwAAAA==.Arcanenug:BAAANQADCgQJBAAAAA==.Arcbnonez:BAAANQAECgQIBAAAAA==.Arguxx:BAAANQAECgYIBgABNQAECgkJJgAHAPgUAA==.Armiggy:BAABNQAECn8sAAIIAAkKlBMrHQBJAgAIAAkKlBMrHQBJAgAAAA==.Aro:BAACNQAFFH8SAAMJAAYKTSHBCQCjAQAJAAUKLSDBCQCjAQAFAAIK4hveHwCwAAA1AAQKfyUAAwkACQoSJbAgAEYCAAkABwrwIrAgAEYCAAUABgpkH1uXANUBAAAA.Arrowraen:BAABNQAECn8oAAIFAAkK/SMCBwCkAwAFAAkK/SMCBwCkAwAAAA==.',
As='Asavera:BAAANQAECgIIAgAAAA==.Asd:BAAANQADCgQIBAAAAA==.Asecond:BAAANQADCgYJBgAAAA==.Asträl:BAAANQADCgYIBgAAAA==.',
Au='Audomere:BAABNQAECn8iAAMKAAkK2gm1dACpAQAKAAkK2gm1dACpAQALAAIKlgHsKAE8AAAAAA==.Auurwarr:BAAANQAECgUIBQAAAA==.',
Av='Avawrath:BAAANQAECggIDQAAAA==.Avraellia:BAAANQADCgYIBQAAAA==.',
Az='Azkaellon:BAAANQADCgQIBAABNQAECgkJIAAEAMwTAA==.',
Ba='Bagool:BAAANQADCgYIBgAAAA==.Ballstench:BAAANQADCgIIAgAAAA==.Barbåtos:BAAANQADCggIFwAAAA==.Baskthyr:BAAANQADCgQIBAAAAA==.Bathory:BAAANQADCgYIBgAAAA==.',
Be='Bearboi:BAAANQAECgcIEwABNQADCgUIBQAMAAAAAA==.Bearbomblolz:BAAANQADCgQIBQABNQAECgUIDgAMAAAAAA==.Bearmanakin:BAAANQADCgYICQAAAA==.Bearypotter:BAAANQADCgQICAAAAA==.Beastbane:BAAANQAECggICQAAAA==.Beastly:BAAANQAECgUICQAAAA==.Beastmandes:BAAANQADCggIFAAAAA==.Bejeezus:BAABNQAECn8sAAMGAAkKmBmYRAC5AgAGAAkKmBmYRAC5AgANAAgKVhSlFQDKAQAAAA==.Bel:BAAANQABCgYIDAAAAA==.Bellion:BAABNQAECn9AAAMOAAgKoBd0QQATAgAOAAgKoBd0QQATAgAPAAYK8Q23VwBFAQAAAA==.Berijar:BAAANQADCgYIBgABNQAECgIIAgAMAAAAAA==.Bewslee:BAAANQAECgEIAwAAAA==.Bexx:BAAANQADCggJGQAAAA==.',
Bi='Biblehumping:BAABNQAECn8sAAMQAAgKYRlmSQBGAgAQAAgKYRlmSQBGAgARAAYKEQlnQQAhAQAAAA==.Bietk:BAAANQADCgQIBwABNQAECgcIDQAMAAAAAA==.Bigbonks:BAAANQAECgQIBgAAAA==.Bigoldpumper:BAAANQAECgEIAQAAAA==.',
Bl='Blackplague:BAAANQADCgQIBQAAAA==.Bleaknight:BAAANQADCgUIBQAAAA==.Blessedbuns:BAAANQAECggICwAAAA==.Blueshamoo:BAAANQAECgEJAQAAAA==.Blãezer:BAAANQADCggIEAAAAA==.',
Bo='Bonex:BAAANQAECgEIAgAAAA==.Boomshroom:BAAANQAECgMIBAABNQAECgkJJwAIANgcAA==.Bootsie:BAAANQADCggICAAAAA==.',
Br='Brewtoe:BAAANQAECgYICgAAAA==.Brisketz:BAAANQADCgUIAQAAAA==.Bruegard:BAAANQADCgIIAgAAAA==.Bruneau:BAAANQABCgUIBQAAAA==.',
Bs='Bshoutbot:BAAANQADCgUIBQABNQAFFAcIFAAJAPoaAA==.',
Bu='Bubblemehard:BAABNQAECn8cAAISAAgKMhhReQA1AgASAAgKMhhReQA1AgAAAA==.',
By='Byahnbreath:BAABNQAECn8XAAIPAAkKRBbZIgB1AgAPAAkKRBbZIgB1AgAAAA==.',
Ca='Cakeiko:BAAANQAECgQIBQAAAA==.Cannabinoide:BAAANQAECgIIAgAAAA==.Cannatonic:BAAANQAECgEIAQAAAA==.Casmiralda:BAAANQABCgUIBQAAAA==.Castielx:BAABNQAECn8ZAAITAAcKthL8PwDHAQATAAcKthL8PwDHAQAAAA==.Catnips:BAAANQAECgQIBgABNQAECggILAAQAGEZAA==.',
Ce='Celestraza:BAAANQADCggIFgAAAA==.Celirra:BAABNQAECn8qAAIOAAkKfCFVDwA7AwAOAAkKfCFVDwA7AwAAAA==.Cennerus:BAAANQADCgIIAwAAAA==.',
Ch='Chaosreign:BAAANQADCggICwAAAA==.Cheekybaby:BAABNQAECn8hAAIGAAgKFQtOrACpAQAGAAgKFQtOrACpAQAAAA==.Cherrypoplol:BAAANQADCgUIDAAAAA==.Chocopaati:BAABNQAECn8VAAMTAAgK5hpfNgD5AQATAAcK5hpfNgD5AQAUAAEKAAD3TQBDAAAAAA==.Chokma:BAABNQAECn8VAAILAAcKDxUzZQDtAQALAAcKDxUzZQDtAQAAAA==.Chunkyfists:BAAANQADCgMIAwAAAA==.Chëeks:BAAANQADCgUIBQAAAA==.Chìefponbury:BAAANQAECgYIDAAAAA==.',
Ci='Cinnaa:BAAANQAECgUICQAAAA==.',
Cl='Clawdog:BAAANQADCgIIAgABNQAECgIIBAAMAAAAAQ==.Clawwz:BAAANQAECgEIAQAAAA==.Cleisthenes:BAAANQAECgEIAQAAAA==.Clors:BAABNQAECn8cAAIDAAcKRRz0HgAyAgADAAcKRRz0HgAyAgAAAA==.',
Co='Conflux:BAAANQADCggIFAAAAA==.',
Cr='Crager:BAAANQAECgUIBQAAAA==.Crawlah:BAAANQADCggIDgAAAA==.Crazegideon:BAAANQABCgIIAgAAAA==.Crazespawnz:BAAANQABCgIIAgAAAA==.Cruelbeam:BAAANQADCgQIBAAAAA==.',
Cu='Curzondax:BAAANQAECggIEQAAAA==.',
Cy='Cyberfairy:BAAANQAECgEJAQAAAA==.Cyphinx:BAAANQAECgUIBQAAAA==.',
['Câ']='Câraxes:BAAANQAECgEIAQAAAA==.',
['Cä']='Cät:BAAANQAECgEIAQAAAA==.',
Da='Dahelzforyou:BAAANQADCgcICAAAAA==.Dalìnar:BAAANQAECgUICgAAAA==.Damadafacker:BAABNQAECn8WAAIGAAkK3hZvZwBWAgAGAAkK3hZvZwBWAgAAAA==.Darkclôud:BAAANQAECgQIBAAAAA==.Darkkatriden:BAAANQADCgYIBgABNQAECgYIEgAMAAAAAA==.Darklia:BAAANQAECgYIEgAAAA==.Darthjae:BAABNQAECn8+AAMVAAgK0hlVQQD1AQAVAAgK0hlVQQD1AQAPAAEKAACGugAfAAAAAA==.Darthmikkey:BAAANQADCgYIBgAAAA==.Darthrakk:BAABNQAECn8mAAIWAAgKCR3NAwDCAgAWAAgKCR3NAwDCAgAAAA==.Davina:BAAANQADCgcIBwABNQAFFAMIBgASAAMOAA==.Daykwan:BAAANQAECggIEwAAAA==.Daïn:BAAANQAECgYICgAAAA==.',
De='Deadestmoonb:BAAANQADCgIIBAAAAA==.Deathalimon:BAABNQAECn8pAAQOAAgKUBkgUgDHAQAOAAcKqxMgUgDHAQAVAAcKqxf+UQCqAQAPAAEKTBDhqQA0AAABNQAECgkJIAAKAO4QAA==.Degion:BAAANQADCgEIAQAAAA==.Deltonn:BAAANQADCgUIBQAAAA==.Demonarian:BAAANQAECgYICAABNQAECgkJIAAKAO4QAA==.Demonpotato:BAAANQADCggJCAAAAA==.Denardath:BAAANQADCgUIBQAAAA==.Denerrollin:BAAANQADCgIIAgAAAA==.Depthcharge:BAAANQAECgYIEQAAAA==.Deroc:BAABNQAECn8XAAISAAgKkQZx3QBaAQASAAgKkQZx3QBaAQAAAA==.Deáthtáxi:BAAANQAECggICAAAAA==.',
Di='Digweeds:BAAANQAECgUIBgAAAA==.Dinfarmer:BAAANQADCgcIDAAAAA==.Dirtycheese:BAAANQAECgUICwAAAA==.',
Dj='Djgha:BAAANQAECgIIBAAAAA==.',
Dm='Dmptrukdonna:BAAANQADCgEIAQAAAA==.',
Do='Dogfärts:BAAANQAECgEIAQAAAA==.Dorunter:BAABNQAECn8mAAMJAAcKaBTCMgC0AQAJAAcKYBLCMgC0AQAFAAEK6RltQQFUAAAAAA==.Dottíe:BAAANQAECgUIBwAAAA==.Doubledosage:BAAANQAECgYIEwAAAA==.',
Dr='Dragonbnonez:BAAANQAECgQIBAAAAA==.Dragonforge:BAAANQADCgYIDQAAAA==.Drakujin:BAAANQADCgMIBQAAAA==.Drboomboom:BAAANQAECggIDAAAAA==.Drdoitall:BAAANQAECgYICwAAAA==.Dreadnpain:BAAANQADCgEIAQAAAA==.Dreynick:BAAANQADCgQIBAAAAA==.Dripfarming:BAAANQAECgMIAwABNQAFFAcIEwAPAMEfAA==.Drnastea:BAAANQADCgYIBgAAAA==.Drstorm:BAAANQADCgYICwAAAA==.',
Du='Duuid:BAABNQAECn8VAAIXAAYKxA89LAAxAQAXAAYKxA89LAAxAQAAAA==.',
Ed='Edaladalrian:BAAANQADCgUIBQAAAA==.',
El='Ella:BAAANQADCgIIAgAAAA==.Elysiá:BAAANQADCggICAAAAA==.',
En='Enhydra:BAAANQADCggICwAAAA==.Enough:BAAANQADCgcIDAAAAA==.',
Eq='Eqv:BAACNQAFFH8LAAQYAAQKMxf6BACaAAAZAAIKDhTgDACgAAAYAAIKfR36BACaAAAaAAEK6AGhRgA7AAA1AAQKfyEAAxgACQppJKIDALcCABgABwo/JaIDALcCABkAAgpQIgtBAL4AAAAA.',
Er='Erayr:BAAANQAECgUIBQAAAA==.Ericolson:BAABNQAECn8gAAIGAAcKRxIpnADRAQAGAAcKRxIpnADRAQAAAA==.Erze:BAAANQAECgUICQAAAA==.Erôman:BAAANQADCgQIBAAAAA==.',
Ev='Evosolz:BAEANQAECgEIAgABNQAECgUIBgAMAAAAAA==.Evé:BAAANQAECgMIAwABNQAECgkJJwAIANgcAA==.',
Ez='Ezzartkal:BAAANQAECgEIAQAAAA==.',
Fa='Faeloria:BAAANQADCgMIAwAAAA==.Farmerdragon:BAAANQADCggIDgAAAA==.Favabean:BAAANQADCgUIBQABNQAECggIPgAVANIZAA==.',
Fe='Feathring:BAAANQADCgYIBgABNQAECgkJJgAbAFUhAA==.Fefra:BAAANQADCgQIBAAAAA==.Felicious:BAAANQAECggIEQAAAA==.Fengshui:BAAANQADCggIGwAAAA==.Feralco:BAAANQAECgQIBAAAAA==.Fertra:BAAANQADCgYIBgAAAA==.',
Fh='Fhedrah:BAAANQADCgEIAgAAAA==.',
Fi='Fixiation:BAAANQAECgEIAQAAAA==.Fiz:BAAANQADCgYIBgAAAA==.',
Fl='Flashdance:BAAANQADCggIDwAAAA==.Fleepo:BAAANQAECgIIAwABNQAECggIDgAMAAAAAA==.Fleshnbones:BAAANQADCgEIAQAAAA==.Flourie:BAABNQAECn8rAAMcAAkKBQ0rHQD4AQAcAAkKBQ0rHQD4AQACAAEKAAAwPgAvAAAAAA==.Flyhawk:BAAANQADCgUIFAAAAA==.Flöör:BAAANQADCgUIBQAAAA==.',
Fu='Fullmetal:BAAANQAECgQIBAAAAA==.Funkadelfic:BAAANQAECgUIBwAAAA==.',
['Fé']='Fénrír:BAAANQADCggIDwABNQAECggIIQALAIsiAA==.',
['Fò']='Fòxxy:BAAANQAECgEJAQAAAA==.',
Ga='Galadri:BAABNQAECn8ZAAMKAAgK/Bu8QABbAgAKAAgK/Bu8QABbAgALAAUKCxCWwAAMAQAAAA==.Garu:BAAANQADCgIIAgAAAA==.',
Ge='Geared:BAAANQAECgcIEAAAAA==.Geartryx:BAAANQADCggIDQAAAA==.Geodood:BAAANQAECgUIBQAAAA==.',
Gh='Ghoshshadow:BAAANQADCgYIEAAAAA==.Ghostinz:BAAANQAECgQIBgAAAA==.',
Gi='Gimpripper:BAAANQAECgYIBgAAAA==.Giztron:BAAANQADCgYIDgAAAA==.',
Gl='Glitterp:BAAANQADCgQIBAABNQAECggJIAAVAGcaAA==.Globalcold:BAABNQAECn8bAAIGAAgKLBrfcgA4AgAGAAgKLBrfcgA4AgAAAA==.Globb:BAABNQAECn8wAAIGAAgKVxTUlQDhAQAGAAgKVxTUlQDhAQAAAA==.Globius:BAABNQAECn8nAAISAAkKGBzDSAC3AgASAAkKGBzDSAC3AgAAAA==.Gloriouscole:BAAANQAECgUIDQAAAA==.Glower:BAAANQADCgEIAQAAAA==.',
Go='Gooly:BAAANQADCgIIAgAAAA==.Goombit:BAAANQADCgEIAQAAAA==.',
Gr='Greekorc:BAAANQABCgYJBwAAAA==.Greenyheals:BAAANQADCgUIBQAAAA==.Grimby:BAAANQAECgIIAQAAAA==.Grimdisney:BAAANQADCggIDgAAAA==.Groceries:BAAANQADCgMIAwAAAA==.Gromol:BAAANQADCggIHwAAAA==.Grumby:BAAANQAECgEIAgAAAA==.',
Gu='Guifu:BAAANQADCgIIAgAAAA==.',
Gw='Gwendolÿn:BAAANQAECgQIBAAAAA==.',
['Gê']='Gêralt:BAAANQADCgQIBAAAAA==.',
Ha='Hacknhaf:BAAANQADCgYIDAAAAA==.Hakubar:BAAANQAECgQIBgAAAA==.Hatebrêêd:BAAANQADCgQIBQAAAA==.',
He='Healman:BAAANQADCgcIGQAAAA==.Healsatute:BAAANQADCgMIAwAAAA==.Healylady:BAAANQADCgcIDAAAAA==.Heiden:BAAANQADCgYJBgAAAA==.Hel:BAAANQADCggIGQAAAA==.Hellyas:BAAANQAECgQICAAAAA==.Herbs:BAAANQAECgEIAQABNQAECgkJLwAdAMgXAA==.Herenorthere:BAABNQAECn8rAAMRAAkK8Rq+GgByAgARAAcKVx2+GgByAgAQAAYKCxjDcwC8AQABNQAFFAQIBwAZAN8TAA==.Hermippe:BAAANQAECgMIAwAAAA==.Hexstraits:BAACNQAFFH8GAAIVAAIKRBOcHwCIAAAVAAIKRBOcHwCIAAA1AAQKfyQAAhUACQqHIuAPAC0DABUACQqHIuAPAC0DAAAA.',
Hi='Hia:BAACNQAFFH8RAAIVAAUKqR5fCgCtAQAVAAUKqR5fCgCtAQA1AAQKfzAAAhUACQq3IPYKAFsDABUACQq3IPYKAFsDAAAA.Highriskbr:BAAANQAECggICAAAAA==.Hitlist:BAAANQADCgUJBQAAAA==.',
Ho='Holycow:BAAANQAECgIIAwAAAA==.Holyfits:BAAANQADCgEIAQAAAA==.Hondacervix:BAAANQAECgYIBgAAAA==.Hondaimpala:BAAANQAECgQIBgABNQAECggIPgAVANIZAA==.Hoofmaster:BAAANQABCgIIAgAAAA==.Howardyou:BAAANQADCgEIAgAAAA==.',
Hu='Huffy:BAAANQAECggICQABNQAECgkJIAAGAKIfAA==.Huffyy:BAABNQAECn8gAAIGAAkKoh+pJwAZAwAGAAkKoh+pJwAZAwAAAA==.Huhdean:BAABNQAECn8hAAMPAAgKDCSDGwCrAgAPAAcKsiODGwCrAgAOAAQKzyEphAALAQAAAA==.Hulxamus:BAAANQAECgYICgAAAA==.Hunterramen:BAAANQADCgEJAQAAAA==.Hunterz:BAAANQAECgQJCQAAAA==.',
['Hé']='Héåthcliff:BAABNQAECn85AAMeAAkK0yPHBABnAwAeAAkKyyLHBABnAwASAAgK/BtsRADEAgAAAA==.',
Ic='Icyblaze:BAAANQAECggIEAAAAA==.',
Id='Idareu:BAABNQAECn8WAAIfAAgKbwSWhgC0AAAfAAgKbwSWhgC0AAAAAA==.',
If='Ifstar:BAAANQAECgMIBAAAAA==.',
Il='Illumi:BAAANQADCgQIBwABNQAECgUICQAMAAAAAA==.',
Im='Immigrant:BAAANQADCggICAAAAA==.',
In='Indominus:BAAANQADCgIIAgAAAA==.',
Ir='Ires:BAAANQADCgUIBQAAAA==.',
Is='Ishadow:BAAANQAECgUIBgAAAA==.Issalis:BAAANQADCgYIBgAAAA==.',
It='Itheusvalles:BAAANQADCggIEgAAAA==.Itsjerry:BAAANQADCgYICQAAAA==.',
Iw='Iwillcrushyo:BAAANQAECgYIBwAAAA==.',
Ja='Jaimerrek:BAAANQAECgQIBwAAAA==.Jainalynn:BAAANQADCgYIEwAAAA==.Jalenbrunson:BAAANQADCgEIAQAAAA==.Jazira:BAABNQAECn8hAAMDAAgKagl5RwDyAAADAAcKrAZ5RwDyAAAfAAUKngPFhgCzAAAAAA==.',
Jd='Jdarkside:BAAANQAECgUICgAAAA==.',
Je='Jebediahmoon:BAAANQADCggICAABNQAECggIPgAVANIZAA==.Jeremmiah:BAAANQADCgcIEQAAAA==.',
Jh='Jhacobo:BAABNQAECn8hAAIfAAgKuxloMQBUAgAfAAgKuxloMQBUAgAAAA==.',
Jo='Jojupobu:BAAANQADCggICAAAAA==.Jorkinit:BAABNQAECn8WAAIHAAcKQxGB3QDKAQAHAAcKQxGB3QDKAQAAAA==.',
Jr='Jragon:BAABNQAECn8gAAIaAAgKbQrnlACtAQAaAAgKbQrnlACtAQAAAA==.',
Ju='Judis:BAAANQABCgYICwAAAA==.Juicedh:BAAANQADCgUIBQAAAA==.Juicy:BAABNQAECn8YAAIHAAkKwRk0ZQC0AgAHAAkKwRk0ZQC0AgAAAA==.Junipur:BAAANQAECgMICQAAAA==.',
Jx='Jxxy:BAACNQAFFH8LAAMFAAQKYRt1FAAXAQAFAAMKYRt1FAAXAQAJAAIKjxCqGwCPAAA1AAQKfxkAAwUACQrRHvrPAFwBAAUACAp0IfrPAFwBAAkAAgqJGUlhAJ8AAAE1AAUUBAoLAAUAYRsA.',
['Jú']='Júnjúnwälä:BAABNQAECn8cAAIDAAcKsCXFDQDxAgADAAcKsCXFDQDxAgAAAA==.',
Ka='Kalories:BAAANQAECgUICAAAAA==.Kalvoid:BAAANQAECgQIBAABNQAECgUICAAMAAAAAA==.Kandance:BAAANQAECgYICwABNQAFFAIIAwAMAAAAAA==.Karlmagnus:BAAANQADCgcIBwAAAA==.',
Ke='Kelvintwo:BAAANQADCgQIAwAAAA==.',
Ki='Kimbopable:BAAANQAECgUIBQABNQAECggIPgAVANIZAA==.Kittyÿ:BAAANQAECgYICwAAAA==.',
Kn='Knurl:BAAANQADCgMIAwAAAA==.',
Ko='Korak:BAAANQADCgUIBQABNQADCgYIBgAMAAAAAA==.Korgh:BAAANQAECgEIAQAAAA==.Kosari:BAAANQADCgEIAQABNQAECgUIBAAMAAAAAA==.',
Kr='Krystall:BAABNQAECn8fAAIYAAkKEA64BwAbAgAYAAkKEA64BwAbAgAAAA==.',
Ku='Kuarahy:BAAANQAECgcIEAAAAA==.Kunfugrip:BAABNQAECn8nAAIIAAkK2BytEgDDAgAIAAkK2BytEgDDAgAAAA==.Kurizmuh:BAAANQADCgUIBwAAAA==.',
['Kà']='Kàl:BAAANQADCgYJBwABNQAECgUICAAMAAAAAA==.',
['Kã']='Kãl:BAAANQADCgYIBgABNQAECgUICAAMAAAAAA==.',
['Kì']='Kìngknìghts:BAAANQAECgMIBgAAAA==.',
La='Lanthos:BAABNQAECn80AAIgAAkKohylCwAiAwAgAAkKohylCwAiAwAAAA==.Lapulapu:BAAANQADCgYIBgAAAA==.Larthal:BAAANQAECgQIBAAAAA==.Latinpapi:BAABNQAECn8jAAMSAAkKIxRgcgBGAgASAAkKIxRgcgBGAgAeAAEKAAA0aABAAAAAAA==.',
Le='Leemiez:BAAANQADCgUICgAAAA==.Leyära:BAAANQAECgIIBAAAAA==.',
Li='Lielys:BAAANQAECgIIAgABNQAECgQIDwAMAAAAAA==.Lilina:BAABNQAECn8dAAIEAAcKtBmaCwAQAgAEAAcKtBmaCwAQAgAAAA==.Liljaejae:BAAANQADCgEIAQAAAA==.',
Lm='Lmn:BAAANQADCgUIBwAAAA==.',
Lo='Lonweh:BAAANQAECgMIBAAAAA==.Lousmage:BAAANQADCgUIBQAAAA==.Loza:BAAANQADCgUICwABNQAECgYIDwAMAAAAAA==.',
Lu='Lucith:BAABNQAECn8rAAIPAAkKeCINBgB/AwAPAAkKeCINBgB/AwAAAA==.Luckie:BAAANQABCgQIBwABNQAFFAUIDgAhAA8RAA==.Lulafairy:BAAANQAECgEJAQAAAA==.Lumador:BAAANQAECgQIBwABNQAECgcIHwARAIQUAA==.Lunatick:BAABNQAECn8eAAQPAAcKVRJLUQBlAQAPAAcK3g1LUQBlAQAVAAMKzRt5hgDgAAAOAAUK6wN1pQCqAAAAAA==.Lunawa:BAACNQAFFH8IAAIHAAUKSx0RGQCsAQAHAAUKSx0RGQCsAQA1AAQKf0IAAwcACQodJosEANUDAAcACQodJosEANUDACIAAwpLEassAJQAAAAA.Lustbót:BAABNQAECn8bAAIHAAkKGwd+5QC7AQAHAAkKGwd+5QC7AQAAAA==.Luvnrdjr:BAAANQADCgYIBgAAAA==.',
Ly='Lynnai:BAAANQAECgUIBAAAAA==.Lynxmi:BAAANQADCgEIAQAAAA==.Lyse:BAACNQAFFH8PAAIjAAUK8CDOBgDQAQAjAAUK8CDOBgDQAQA1AAQKfyoAAiMACQrDJagFAJkDACMACQrDJagFAJkDAAAA.',
['Lê']='Lêvak:BAAANQADCgIIAgAAAA==.',
['Lí']='Líllith:BAAANQADCgYJBgAAAA==.',
['Lô']='Lôuku:BAABNQAECn8rAAIaAAgKqBvpQQCJAgAaAAgKqBvpQQCJAgAAAA==.',
Ma='Maahn:BAAANQADCgcICAAAAA==.Macalob:BAAANQAECgQIBgAAAA==.Madallar:BAAANQAECgYIEgAAAA==.Magdagni:BAABNQAECn8UAAIkAAYKfROeHACVAQAkAAYKfROeHACVAQAAAA==.Mageji:BAACNQAFFH8LAAIHAAQK8iA/HwCGAQAHAAQK8iA/HwCGAQA1AAQKfzUAAgcACQqFI94VAHwDAAcACQqFI94VAHwDAAE1AAMKBggGAAwAAAAA.Magepies:BAAANQAECgQIBgABNQAECgQICAAMAAAAAA==.Magicfurry:BAAANQAECgUICgABNQAECggILAAQAGEZAA==.Mainveinz:BAABNQAFFH8FAAIVAAUKsgCAHACqAAAVAAUKsgCAHACqAAAAAA==.Malicelx:BAAANQAECgIIAgABNQAECgkJJgAHAPgUAA==.Mallgoth:BAABNQAECn8VAAIFAAYK9gVd9wAPAQAFAAYK9gVd9wAPAQAAAA==.Manohar:BAABNQAECn8qAAMKAAkKsxyXKgC2AgAKAAkKsxyXKgC2AgALAAcKzw4OgQCeAQAAAA==.Mardtard:BAAANQAECgcIEAABNQAECgUIBgAMAAAAAA==.Marximilian:BAAANQAECgMIAwAAAA==.',
Mc='Mcflurryz:BAAANQADCgUIBQAAAA==.Mcgrubert:BAAANQAECgIJAgABNQAFFAUIBQAJAGUOAA==.',
Me='Mechachad:BAAANQAECgMIAwAAAA==.Medlock:BAAANQADCgYICQAAAA==.Medmasters:BAAANQABCgIIAgAAAA==.Megamango:BAAANQADCggICAABNQAECgkJKwAiAO4kAA==.Mehiel:BAAANQAECgcIDQAAAA==.Meive:BAAANQADCgMIAwAAAA==.Meraxes:BAAANQAECgEIAQAAAA==.Merdune:BAAANQADCgEIAQAAAA==.Merkén:BAAANQAECgYIBgAAAA==.Metaloclypse:BAAANQADCgcIDgAAAA==.Meteas:BAAANQAECgQIBAAAAA==.Mezaryn:BAAANQAECggIEgABNQAECgkJKwADAMgHAA==.Mezgrim:BAAANQAECggIAgABNQAECgkJKwADAMgHAA==.Mezzoo:BAABNQAECn8rAAIDAAkKyActRwD0AAADAAkKyActRwD0AAAAAA==.',
Mi='Midger:BAAANQADCgQIBAAAAA==.Millic:BAABNQAECn8hAAMlAAgKYxYbBgAyAgAlAAgKYxYbBgAyAgARAAEKYQdndQA5AAAAAA==.Millish:BAAANQADCgQIBAAAAA==.Minax:BAAANQAECgMIBAAAAA==.Missionsena:BAAANQAECgEJAQAAAA==.Mitzrael:BAAANQADCgQIBQAAAA==.',
Mo='Moozx:BAAANQAECgEIAQAAAA==.Morgannâ:BAAANQAECgIIAwAAAA==.Mosfeat:BAAANQADCggICAABNQAECggIEAAMAAAAAA==.',
Mu='Muckdile:BAAANQAECgQIBAAAAA==.Muckstab:BAAANQAFFAEIAQAAAA==.Mux:BAAANQADCggIDQAAAA==.',
Na='Narayeda:BAAANQAECgcIEwAAAA==.Nasuadia:BAAANQADCggIIQABNQAECgkJJgAPALIeAA==.',
Ne='Necromansorz:BAAANQAECggICAAAAA==.Nekkash:BAAANQAECgYICgAAAA==.Neredir:BAAANQADCgYIBgAAAA==.Netoraresan:BAAANQAECggIAQAAAA==.Newwt:BAAANQADCgQIBAAAAA==.Neytiri:BAAANQABCgQJBQAAAA==.Nezelle:BAAANQAECgYIEgABNQAECgkJLwAdAMgXAA==.',
No='Nomaa:BAAANQADCgQIBAAAAA==.Noris:BAAANQAECgcICAAAAA==.Norros:BAAANQAECgIIBAAAAA==.Novacaine:BAAANQADCgcIBwAAAA==.',
Nu='Nuvi:BAAANQAECgQICAAAAA==.Nuvostaph:BAAANQAECggIEwAAAA==.',
Od='Odecias:BAAANQADCgUICQAAAA==.',
Og='Ogbrew:BAAANQADCgcIEAAAAA==.',
Oh='Ohiyaa:BAAANQADCgQIBAAAAA==.',
Or='Orcboken:BAAANQAECgMIBAAAAA==.Orezn:BAAANQAECgQICgAAAA==.',
Pa='Pabby:BAAANQABCgIIBAAAAA==.Painting:BAAANQAECgEIAQABNQAECgcIGAAjAGQgAA==.Pallypusher:BAAANQADCgQICAAAAA==.Papiace:BAAANQAECgYIDgAAAA==.Pato:BAAANQAECgcIEgAAAA==.',
Ph='Phatnips:BAABNQAECn8qAAMaAAkKWg9QZAApAgAaAAkKWg9QZAApAgAZAAEKxgPdgwAmAAAAAA==.',
Pi='Piesniper:BAAANQABCgIIAgABNQADCgYIDAAMAAAAAA==.Pigeon:BAAANQADCgUIBgAAAA==.',
Pn='Pnuts:BAACNQAFFH8LAAIRAAQKxwxGCwA1AQARAAQKxwxGCwA1AQA1AAQKfy8AAhEACQpFHWYRAOMCABEACQpFHWYRAOMCAAAA.',
Po='Popedragon:BAAANQAECgEIAgAAAA==.Poshh:BAAANQADCgQIBAAAAA==.',
Pr='Prayihealu:BAAANQADCgYIBwAAAA==.Pres:BAAANQADCgIIAgAAAA==.Prisonmike:BAAANQAECgcIEwAAAA==.Promisa:BAAANQAECggICAAAAA==.Promise:BAAANQAECggIBAAAAA==.Prophets:BAAANQADCgMIBQAAAA==.Pryome:BAABNQAECn8YAAIHAAgKmQoh3ADMAQAHAAgKmQoh3ADMAQABNQAECgkJIAAKAO4QAA==.',
Pu='Puddiñ:BAAANQADCgMIAwAAAA==.Puffindaboof:BAAANQAECgIIAgAAAA==.Punkz:BAAANQADCgYICAABNQAECggIGQAKAPwbAA==.Punpal:BAAANQADCgYIBgAAAA==.Pushmaa:BAAANQAECgYJCwAAAA==.',
Py='Pyromortis:BAAANQAECgYIEAABNQAECggILAAQAGEZAA==.Pytorch:BAABNQAECn9EAAIHAAgKZx0RcwCXAgAHAAgKZx0RcwCXAgAAAA==.',
['Pø']='Pø:BAAANQAECgQIBAAAAA==.',
Qu='Queelex:BAAANQAECgcIDAABNQAECggIGQAKAPwbAA==.Quigzz:BAABNQAECn8pAAIUAAkKqx9LBgAbAwAUAAkKqx9LBgAbAwAAAA==.Quinnie:BAAANQAECgYIDgABNQAFFAIIAwAMAAAAAA==.',
Ra='Raganarok:BAAANQAECgIIAgAAAA==.Rahja:BAAANQAECgYICQAAAA==.Ramss:BAAANQAECggIEAAAAA==.Ranch:BAAANQADCgUIBQAAAA==.',
Re='Realtrendy:BAAANQADCggICAABNQAECggIHQAZAFsSAA==.Redranse:BAAANQADCgQIBAAAAA==.Reebs:BAAANQAECggICQAAAA==.Resa:BAAANQAECgIIAwAAAA==.Restomania:BAAANQADCgMIAwAAAA==.',
Ri='Ricasti:BAAANQAECgYICwAAAA==.',
Ro='Robinsonic:BAAANQAECgcIEQAAAA==.Rokenn:BAAANQADCggICAAAAA==.Rosabetsy:BAAANQADCgIIAgAAAA==.Rosetastoned:BAAANQADCgIJAgAAAA==.',
Ru='Rukiè:BAAANQAFFAEIAQAAAA==.Runmyrkr:BAAANQAECgcIEgAAAA==.',
['Rô']='Rôbert:BAAANQAECgUIBwAAAA==.',
Sa='Saberyn:BAAANQAECgcIDAAAAA==.Sacredsassy:BAAANQAECgMIAwAAAA==.Saenya:BAABNQAECn8YAAIRAAcK7RUsKgDTAQARAAcK7RUsKgDTAQAAAA==.Sageofwampa:BAAANQADCgEIAQAAAA==.Sahra:BAAANQADCggICAAAAA==.Sassynova:BAAANQADCgYICQAAAA==.',
Sc='Schvitz:BAAANQAECgYIDwAAAA==.Scopeftis:BAABNQAECn8WAAIOAAkK7hwvJQCoAgAOAAkK7hwvJQCoAgAAAA==.',
Se='Seano:BAAANQAECgMIAwAAAA==.Seberology:BAABNQAECn8oAAIhAAkKEBJ9SQA/AgAhAAkKEBJ9SQA/AgAAAA==.Segagamecube:BAAANQADCgMIAwAAAA==.Sepatown:BAAANQADCggICAAAAA==.Sephi:BAAANQADCgQIBAAAAA==.Sergal:BAAANQADCggICAABNQAECgMICQAMAAAAAA==.',
Sh='Shaco:BAAANQAECgMIAwAAAA==.Shamanpizza:BAAANQADCgMIAwAAAA==.Shamjam:BAAANQAECgQICQABNQAECgkJJgAHAPgUAA==.Shamownage:BAABNQAECn8gAAMKAAkK7hCDWgD9AQAKAAkK7hCDWgD9AQALAAcKvRHDfwChAQAAAA==.Shankyews:BAAANQADCgQJBAAAAA==.Sheev:BAAANQADCgEIAQAAAA==.Shepling:BAACNQAFFH8KAAIVAAUKMg0tEwAgAQAVAAUKMg0tEwAgAQA1AAQKfxQAAhUACAp7FU1GAN0BABUACAp7FU1GAN0BAAAA.Shifterella:BAAANQAECgMIBAAAAA==.Shifu:BAACNQAFFH8FAAIIAAIKaxPLDgCZAAAIAAIKaxPLDgCZAAA1AAQKfxsAAwgACQqMHo4aAGYCAAgABwoJIo4aAGYCABsABwqEFR8VAI8BAAAA.Shivàh:BAACNQAFFH8PAAMOAAUKOBrHBwCbAQAOAAUKOBrHBwCbAQAPAAMKexI8EADTAAA1AAQKfyAAAw8ACQrjIYwgAIQCAA8ACQrbIYwgAIQCAA4AAwqkIVCCABEBAAAA.Shneezleberg:BAABNQAECn8hAAMGAAkKKx3VNgDlAgAGAAkKKx3VNgDlAgAmAAQKvgpdIwCVAAAAAA==.',
Si='Sildormi:BAAANQAECgEIAQAAAA==.Sithrage:BAAANQADCgQIBAAAAA==.Sizzlinghots:BAAANQAECgYICwAAAA==.',
Sk='Skateboardp:BAAANQADCgYIBgAAAA==.Skiddlywinks:BAAANQADCgYIFAABNQAECgUIDgAMAAAAAA==.Sko:BAABNQAECn8fAAIGAAkKPRm5VQCHAgAGAAkKPRm5VQCHAgAAAA==.Skár:BAAANQADCggICwAAAA==.',
Sl='Sladak:BAAANQAECgIIAgAAAA==.Slimjimm:BAAANQAECgUIBQABNQAECgcIBgAMAAAAAA==.',
Sn='Snackdad:BAAANQADCgMIBAAAAA==.Sneakyky:BAAANQADCgcIEAAAAA==.Sneakymoomoo:BAAANQADCgYJBgABNQAECggILAAQAGEZAA==.Snipagooly:BAAANQADCgcIBwAAAA==.Snowyrain:BAAANQAECgUICgAAAA==.',
So='Sojourner:BAAANQAECgcIEQAAAA==.Solanum:BAAANQADCgQIBAABNQAECgQIBAAMAAAAAA==.Solkar:BAAANQADCgcJCwAAAA==.Solo:BAABNQAECn8kAAISAAkKWhMJbABWAgASAAkKWhMJbABWAgAAAA==.Soupsandwich:BAAANQAECgMIBAAAAA==.Sourless:BAAANQAECgEIAQAAAA==.',
St='Stagg:BAABNQAECn8mAAIHAAkK+BTcmQBMAgAHAAkK+BTcmQBMAgAAAA==.Stankazz:BAAANQABCgQIBAAAAA==.Stankytotems:BAAANQADCgcIEQAAAA==.Stinkcheese:BAAANQAECgEIAQAAAA==.Stkk:BAAANQAECggICAAAAA==.Stonedkritz:BAAANQABCgMIAwAAAA==.',
Su='Sunarii:BAAANQAECgcIEAAAAA==.Sunroof:BAAANQADCgMIBgAAAA==.Superbroke:BAAANQABCgIIAgAAAA==.Superpoor:BAAANQABCgEIAQAAAA==.',
Sw='Swagalito:BAAANQADCgUIBgAAAA==.',
['Sà']='Sàviorself:BAAANQAECgIIAwAAAA==.',
['Sý']='Sýlvanàs:BAAANQADCgMIAwAAAA==.',
Ta='Taelian:BAAANQADCgYICQAAAA==.Talanath:BAABNQAECn8dAAIcAAkK1gYcJQCUAQAcAAkK1gYcJQCUAQAAAA==.Taldor:BAAANQABCgMIAwAAAA==.Talwayn:BAAANQADCgUIBQABNQAECgUIDgAMAAAAAA==.Tanarran:BAAANQADCgUIBQAAAA==.Tatooth:BAAANQADCgQIBAAAAA==.Tazoo:BAAANQAECgYIEwAAAA==.',
Te='Teamfluffer:BAAANQADCgUICQAAAA==.Tee:BAAANQADCgcIDQAAAA==.Tehzuurmx:BAAANQABCgIIAgAAAA==.Telps:BAAANQADCgIIAgAAAA==.Teranosouth:BAAANQABCgMIAwAAAA==.Teruulos:BAAANQAECgQIBwAAAA==.',
Th='Thabeast:BAAANQAECgEIAQAAAA==.Thadeouss:BAABNQAECn8mAAIQAAkKEhz/MwCVAgAQAAkKEhz/MwCVAgAAAA==.Thadiusx:BAAANQABCgIIAgAAAA==.Tharon:BAABNQAECn8aAAIFAAgKKBd3ZABKAgAFAAgKKBd3ZABKAgAAAA==.Thebigboom:BAABNQAECn8uAAIXAAkKNhwkCgDMAgAXAAkKNhwkCgDMAgAAAA==.Thecarter:BAAANQAECgIIAgAAAA==.Thoomahawk:BAAANQADCgIIAgAAAA==.Threnody:BAAANQAECgYIEQAAAA==.',
Ti='Tichalock:BAAANQADCgIIAgABNQAECgEIAQAMAAAAAA==.Tichemort:BAAANQADCgcICwAAAA==.Tigerchimon:BAAANQADCgUIBQABNQAECgkJIAAKAO4QAA==.Tinglem:BAAANQADCgYICwAAAA==.',
To='Tobiramaa:BAAANQABCgQIBAAAAA==.Toeclipper:BAAANQADCgYIBgAAAA==.Tolivold:BAAANQAECgQICAAAAA==.Tomeoz:BAAANQAECgEIAQAAAA==.Toxicsocks:BAACNQAFFH8FAAMnAAMK9QOkAACIAAAnAAIK6ASkAACIAAAHAAIK5AMpTwCBAAA1AAQKfy4AAycACQq8HOgAAAoDACcACQq8HOgAAAoDAAcAAwqyDHGMAacAAAAA.',
Tr='Trapscallion:BAAANQAECgQIEAAAAA==.Trashcaster:BAAANQADCgcIDAAAAA==.Treeknight:BAABNQAECn8fAAIOAAgKOBR9SADxAQAOAAgKOBR9SADxAQAAAA==.Treelimbs:BAAANQAECgYICgAAAA==.Tridity:BAAANQAECgYIDwAAAA==.Trollolollz:BAAANQAECgIIAwAAAA==.',
Ts='Tsuuna:BAABNQAECn8mAAMGAAkKlBmnQADFAgAGAAkKlBmnQADFAgANAAEKAACaPQBIAAAAAA==.',
Tu='Turtleqt:BAAANQABCgEIAQAAAA==.',
Ty='Tylanar:BAAANQADCgYIBgABNQAECgIIBAAMAAAAAA==.Tylandon:BAAANQAECgUICQAAAA==.Tyralthas:BAAANQADCgQIAwAAAA==.',
['Tê']='Tênaciousv:BAAANQAECgIJAwAAAA==.',
['Të']='Tëhzoo:BAAANQABCgIIAgAAAA==.',
['Tì']='Tìnnitus:BAAANQABCgMIBAAAAA==.',
Ug='Uglyboyryan:BAAANQAECgMIAwAAAA==.',
Un='Unavaluable:BAAANQADCggIDwAAAA==.Ungodlyy:BAAANQAECgQICQAAAA==.Untöuchable:BAABNQAECn8vAAMSAAkKsSDGKQAdAwASAAkKsSDGKQAdAwAhAAEK4gG6MgEhAAAAAA==.',
Ur='Urskrog:BAAANQADCggIEwAAAA==.',
Va='Vanthelos:BAAANQADCgQIBAAAAA==.',
Ve='Velachlan:BAAANQAECgUIDwAAAA==.Verdtual:BAAANQADCgMIAwAAAA==.Veredelyse:BAABNQAECn8vAAQdAAkKyBeTBwA3AgAdAAgKbRmTBwA3AgAUAAUKThKlLABYAQATAAMK9RJNewC7AAAAAA==.Verxl:BAAANQAECgUIEgAAAA==.',
Vi='Vihn:BAAANQADCgYIBgAAAA==.',
Vo='Voidnyou:BAAANQADCgQJCAAAAA==.Volumes:BAAANQAECgUIBwAAAA==.Volund:BAABNQAECn8nAAIkAAgKkwcSGwCuAQAkAAgKkwcSGwCuAQAAAA==.',
Vy='Vynsong:BAABNQAECn8YAAIhAAgKHiDsIADoAgAhAAgKHiDsIADoAgAAAA==.Vyz:BAAANQADCgQIBAABNQAECgQIBAAMAAAAAA==.',
Wa='Warwalkerz:BAAANQADCggIFgAAAA==.Watermalorne:BAAANQAECgMIAwAAAA==.',
We='Weemies:BAAANQAECgUIBgAAAA==.Wetmonk:BAAANQAECgcIDQAAAA==.',
Wh='Whoyerdaddy:BAAANQAECgIIAgAAAA==.Whywhybecuz:BAAANQADCgQIBAAAAA==.',
Wi='Wickedal:BAAANQADCgIIAgAAAA==.Winndfurry:BAAANQADCgMIAwAAAA==.Winnototem:BAABNQAECn8rAAMKAAkKWRNxWgD9AQAKAAkKWRNxWgD9AQALAAUKMBREqQA9AQAAAA==.Wisakedjak:BAAANQADCggIGwAAAA==.',
Wo='Wombatman:BAAANQAECgQICQAAAA==.Wong:BAAANQAECgUIBgAAAA==.',
Wu='Wutpuddle:BAAANQADCggIAQAAAA==.',
Xi='Xiaoshui:BAAANQADCgYIBgAAAA==.',
Xu='Xugos:BAABNQAECn8aAAIaAAkKKRRsZAApAgAaAAkKKRRsZAApAgAAAA==.',
Ya='Yatagarasu:BAAANQAECggIAgAAAA==.',
Ye='Yenafer:BAAANQABCgYIBwAAAA==.',
Yo='Yochill:BAAANQAECgIIAgABNQAECgUICQAMAAAAAA==.Yolokin:BAAANQADCgcIGAAAAA==.Yooper:BAAANQADCgcIBgAAAA==.Yota:BAAANQAECgEIAQAAAA==.',
Yr='Yrgg:BAAANQAECgYICwAAAA==.',
Yt='Ytgamezoned:BAAANQADCgQIBAAAAA==.',
Za='Zadanthra:BAAANQAECgUIDgAAAA==.Zapadin:BAABNQAECn8hAAISAAgKYBa4fwAlAgASAAgKYBa4fwAlAgAAAA==.Zaphodè:BAAANQAECgQIBAAAAA==.',
Ze='Zephian:BAAANQAECgMIAwAAAA==.Zephsham:BAAANQADCgYIDAAAAA==.Zerokool:BAAANQABCgMIAwAAAA==.',
Zi='Zimone:BAAANQADCgMIAwAAAA==.',
Zo='Zoerik:BAABNQAECn8gAAQlAAgKAAuJCwCFAQAlAAgKAAuJCwCFAQAQAAYK2wOLrwACAQARAAUKNgW+UADKAAAAAA==.Zotoperen:BAABNQAECn8mAAMbAAkKVSFaAwBdAwAbAAkKVSFaAwBdAwAIAAMKFhHCUQClAAAAAA==.',
Zy='Zylergy:BAAANQAECgYIEgAAAA==.',
['Zì']='Zìfu:BAAANQADCggICQAAAA==.',
['Àv']='Àvicant:BAAANQAECgUJBwABNQAFFAQICAAFAFMiAA==.',
['Än']='Ändo:BAAANQAECgQIDAAAAA==.',
['Äy']='Äy:BAAANQABCgEIAQAAAA==.',
['Çy']='Çyrin:BAABNQAECn8oAAMhAAkKGBIoSQBAAgAhAAkKGBIoSQBAAgASAAEK5QgSoQEzAAAAAA==.',
['Çø']='Çørpsë:BAAANQABCgIJAgAAAA==.',
['Ëu']='Ëuphoria:BAAANQADCgQIBAAAAA==.',
['Ün']='Üna:BAAANQADCggICAAAAA==.',
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
