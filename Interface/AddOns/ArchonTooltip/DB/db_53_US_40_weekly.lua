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

local lookup = {'Druid-Restoration','Shaman-Elemental','Druid-Balance','Paladin-Protection','Paladin-Retribution','Unknown-Unknown','Priest-Shadow','Paladin-Holy','Mage-Frost','Shaman-Enhancement','Mage-Arcane','Warlock-Affliction','Warlock-Demonology','Hunter-BeastMastery','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Monk-Mistweaver','Priest-Holy','Warlock-Destruction','DemonHunter-Devourer','Warrior-Arms','DemonHunter-Vengeance','Rogue-Assassination','Hunter-Survival','Druid-Guardian','Shaman-Restoration','Warrior-Protection','Warrior-Fury','DemonHunter-Havoc','Priest-Discipline','Monk-Windwalker','Rogue-Subtlety','Hunter-Marksmanship','Druid-Feral','Evoker-Augmentation','Rogue-Outlaw',}
local provider = {region='US',realm='Bloodhoof',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Aberforthd:BAAANQAECgQICQAAAA==.',
Ac='Aceforlife:BAAANQADCggIEAABNQAECgYIIwABAC0IAA==.Acorn:BAABNQAECn8lAAICAAkKJR9oHwAMAwACAAkKJR9oHwAMAwAAAA==.',
Ad='Aditu:BAABNQAECn8aAAMBAAYKEhQJNQBuAQABAAYKEhQJNQBuAQADAAYKgg1kYABJAQAAAA==.',
Ae='Aetheris:BAABNQAECn8UAAIEAAcKlhNDLAB3AQAEAAcKlhNDLAB3AQAAAA==.',
Ag='Agasonex:BAAANQADCgUIBAAAAA==.',
Ah='Ahziz:BAAANQAECgUIDgAAAA==.',
Ai='Airent:BAAANQAECgUICgAAAA==.',
Al='Alaestel:BAABNQAECn8nAAIFAAkKvAzunwDcAQAFAAkKvAzunwDcAQAAAA==.Aletheia:BAAANQAECgQIBAAAAA==.Alt:BAAANQAECgIIBAAAAA==.',
An='Ancane:BAAANQADCggICAAAAA==.Angina:BAAANQADCgUIBwAAAA==.Angrywoogie:BAAANQADCgEIAQABNQAECgQIBwAGAAAAAA==.Annarcis:BAAANQAECgUIBwAAAA==.Antiman:BAAANQAECgMIBgAAAA==.Anäster:BAABNQAECn8hAAIHAAgKdhaKJAAJAgAHAAgKdhaKJAAJAgAAAA==.',
Ao='Aoiris:BAAANQADCggICAAAAA==.',
Ap='Aplcyder:BAABNQAECn8eAAIBAAkKuAgwMQCNAQABAAkKuAgwMQCNAQAAAA==.Apocryphea:BAAANQAECgQIBAAAAA==.',
Ar='Arachnid:BAAANQAECgQIDQAAAA==.Aradalon:BAABNQAECn8oAAIIAAkKmyEdDwBRAwAIAAkKmyEdDwBRAwAAAA==.Aratyn:BAABNQAECn8YAAIJAAcKshRADQDbAQAJAAcKshRADQDbAQAAAA==.',
As='Astranacht:BAABNQAECn8oAAIDAAgKTQ+UQgDoAQADAAgKTQ+UQgDoAQAAAA==.',
Au='Auntjemimma:BAABNQAECn8bAAIFAAgKQhKehgAVAgAFAAgKQhKehgAVAgAAAA==.Auriandra:BAAANQAECgQIBAAAAA==.',
Ax='Axa:BAAANQADCggIDAAAAA==.',
Ba='Babyshoes:BAAANQAECgIIAgAAAA==.Backhawk:BAAANQAECgQIBAAAAA==.Backsurgery:BAAANQAECgcIEwABNQAFFAUICgAKAB4WAA==.Baerrn:BAAANQAECgYIEQAAAA==.Baricia:BAABNQAECn8jAAILAAgKvwwc2wDOAQALAAgKvwwc2wDOAQAAAA==.Barrin:BAABNQAECn8bAAMMAAcKLBrQBwAYAgAMAAcKLBrQBwAYAgANAAIKSwDdPQE0AAAAAA==.Bawnchu:BAAANQADCgYIEwAAAA==.',
Be='Beardad:BAAANQADCgcIBwAAAA==.Bearded:BAAANQAECgYIBgAAAA==.Beastmaster:BAABNQAECn8aAAIOAAkKcRyxMQDVAgAOAAkKcRyxMQDVAgAAAA==.Beefcakell:BAAANQADCgMIBAAAAA==.Belthar:BAAANQAECgUIBQAAAA==.Bentlymage:BAABNQAECn8lAAILAAkKsxx7VQDVAgALAAkKsxx7VQDVAgAAAA==.',
Bi='Bissafiyah:BAACNQAFFH8bAAIKAAcKQh4zAADNAgAKAAcKQh4zAADNAgA1AAQKfywAAgoACQrCJfIEAD8DAAoACQrCJfIEAD8DAAAA.Bittertea:BAAANQAECgUIDgAAAA==.',
Bl='Blakdeath:BAABNQAECn8ZAAIPAAcKlwyMTwBuAQAPAAcKlwyMTwBuAQAAAA==.Blargghh:BAAANQAECgYIBgAAAA==.Bloodgon:BAABNQAECn8UAAMQAAYKqhcEWgCkAQAQAAYKqhcEWgCkAQARAAIKTA2hsgBhAAAAAA==.Bloodpriests:BAAANQAECgYIBgAAAA==.',
Bo='Bobthedemon:BAAANQAECgIIAwAAAA==.Bohica:BAAANQAECgQIBAAAAA==.Boka:BAAANQADCgMIAgAAAA==.Bonechop:BAAANQADCgIIAgAAAA==.Bowseye:BAAANQADCggICAABNQAECggIGwAFAEISAA==.Boyakasha:BAAANQAECgUICgAAAA==.',
Br='Brayne:BAAANQAECgUIBwAAAA==.Brewsome:BAABNQAECn8pAAISAAkKOCENBQBRAwASAAkKOCENBQBRAwAAAA==.Brighthammer:BAAANQADCgcIDQAAAA==.Bryybryy:BAABNQAECn8lAAIRAAgKLR0EJgCKAgARAAgKLR0EJgCKAgAAAA==.Bryyguyy:BAAANQADCgIIAgABNQAECggIJQARAC0dAA==.',
Bu='Bubleherth:BAAANQADCgcIFwAAAA==.Bullymayes:BAAANQABCgYIBgAAAA==.Bunkiee:BAAANQADCggIFgAAAA==.',
Ca='Calbee:BAAANQADCgYIBQAAAA==.Candorite:BAAANQAECgUJBwABNQAECgcIEwAGAAAAAA==.Capcoms:BAAANQAECgQICwABNQAECggIKQALAJUeAA==.Capita:BAABNQAECn8eAAIJAAcKaw9iEQCNAQAJAAcKaw9iEQCNAQAAAA==.Carsinegan:BAAANQAECgQICgAAAA==.Cassica:BAABNQAECn8cAAMHAAgKDRLFMACZAQAHAAcK4hHFMACZAQATAAYKeBN3jwBjAQAAAA==.Catskin:BAAANQADCgYICQAAAA==.Causticminx:BAAANQABCgYIBwAAAA==.',
Ch='Chainlink:BAAANQADCgIIAgAAAA==.Charkle:BAAANQAECgUIDgAAAA==.Chillylilly:BAAANQAECggIEAAAAA==.Chummie:BAABNQAECn8fAAQNAAgKoB7wXQA6AgANAAcKohzwXQA6AgAMAAIKbSLRFwDMAAAUAAIK0xViUACMAAAAAA==.Chuud:BAAANQADCgQIBAAAAA==.',
Ci='Ciandoril:BAAANQAECgQICQAAAA==.Cid:BAAANQADCgQIBAAAAA==.',
Co='Comeanddie:BAAANQADCggIFAABNQADCgMIAwAGAAAAAA==.',
Cr='Crazyeyes:BAAANQAECgQICAABNQAECgcIFwADAGIJAA==.Crimsondeath:BAAANQAECgUICgAAAA==.Crylecks:BAAANQAECgYIBgAAAA==.',
Cy='Cyclonian:BAAANQAECggICAABNQAECggIDQAGAAAAAA==.Cylu:BAAANQADCggICwAAAA==.Cyprus:BAAANQAECgcICwABNQAECgcIDAAGAAAAAA==.',
Da='Daelric:BAAANQADCgIIAgAAAA==.Daender:BAABNQAECn8pAAIOAAkK/yB8GgAtAwAOAAkK/yB8GgAtAwAAAA==.Daenor:BAAANQADCgQIBAAAAA==.Daevie:BAABNQAECn8dAAILAAgKZQXPDAF0AQALAAgKZQXPDAF0AQAAAA==.Dairydemon:BAABNQAECn8nAAIVAAkKTwNsQABEAQAVAAkKTwNsQABEAQAAAA==.Damageus:BAABNQAECn8sAAMLAAgKciFgaQCrAgALAAcKxSBgaQCrAgAJAAEK1iTxMgBsAAAAAA==.Damworg:BAAANQAECgUICgAAAA==.Daniryl:BAEANQAECgcICAABNQAECggIGgACACwTAA==.Dar:BAABNQAECn8mAAIOAAgKORQccgAqAgAOAAgKORQccgAqAgAAAA==.Darcside:BAAANQAECgUICQAAAA==.Daritar:BAEBNQAECn8aAAICAAgKLBP3YgD0AQACAAgKLBP3YgD0AQAAAA==.Darkburtus:BAABNQAECn8YAAIVAAYKAAX1SQABAQAVAAYKAAX1SQABAQAAAA==.Darkfeatherr:BAAANQAECgIIBAAAAA==.Darkxwraith:BAABNQAECn8iAAMEAAcKLBicJAC4AQAEAAYKthucJAC4AQAFAAEKCArnngE1AAAAAA==.Datsombeech:BAABNQAECn8jAAIWAAgKRAiHuwCDAQAWAAgKRAiHuwCDAQAAAA==.',
De='Defhammer:BAAANQABCggIFgAAAA==.Deàdly:BAAANQADCgUJCgAAAA==.',
Dh='Dhaynk:BAABNQAECn8sAAMXAAkKiRoxCQBWAgAXAAcKgx8xCQBWAgAVAAkKfA8UKAAAAgAAAA==.',
Di='Dianoia:BAAANQAECgQIBgABNQAFFAUIEwAUANsbAA==.Didamus:BAAANQABCgMIAwAAAA==.Dingleding:BAAANQAECgQIBAAAAA==.',
Dk='Dkanabiss:BAAANQADCgYIEAAAAA==.Dkinabox:BAAANQADCgYIBwAAAA==.',
Do='Docoo:BAABNQAECn8gAAIRAAgKpCSNFgD2AgARAAgKpCSNFgD2AgAAAA==.Dogmeat:BAAANQABCgQICAAAAA==.Dominates:BAAANQAECgQIBAAAAA==.',
Dr='Dreu:BAAANQADCgUIBwABNQAFFAUIDwAVAI8WAA==.Drewserk:BAABNQAECn8jAAIWAAkK3hKDgQAUAgAWAAkK3hKDgQAUAgAAAA==.Driten:BAABNQAECn8pAAILAAgKlR6gZAC1AgALAAgKlR6gZAC1AgAAAA==.Drocsid:BAAANQAECggICwABNQAECgkJKQAFABshAA==.Drpiscisphd:BAAANQAECgEIAQABNQAECgkJLwAYABwiAA==.Drsaltyballz:BAAANQAECgIJAgAAAA==.Drspoon:BAABNQAECn8hAAIRAAkKShRDPgAFAgARAAkKShRDPgAFAgAAAA==.Drugpala:BAAANQAECgEJAwAAAA==.Drumuss:BAAANQAECgMIBQAAAA==.',
Ds='Dsancho:BAAANQAECgYIDAAAAA==.',
Du='Ducat:BAAANQADCgQIBAAAAA==.Dudley:BAAANQAECgMIBAAAAA==.Duffun:BAABNQAECn8YAAILAAcKZBpmmQBNAgALAAcKZBpmmQBNAgABNQAECggIKQAZACMlAA==.Duffunha:BAABNQAECn8pAAIZAAgKIyUZAQB3AwAZAAgKIyUZAQB3AwAAAA==.',
Dy='Dyre:BAAANQAECgMIBgAAAA==.Dyslexic:BAAANQAECgQICgABNQAFFAIICAAFAK4KAA==.Dyspepsia:BAACNQAFFH8IAAIFAAIKrgqSJwCCAAAFAAIKrgqSJwCCAAA1AAQKfxsAAgUACQo/FamDABwCAAUACQo/FamDABwCAAAA.',
['Dõ']='Dõngus:BAAANQADCgYIBgABNQAECggIDQAGAAAAAA==.',
Ed='Edelgard:BAAANQAECgEIAgAAAA==.Edie:BAAANQADCgcIGgAAAA==.',
Ei='Eirenn:BAAANQAECggICAAAAA==.',
El='Eleaornu:BAABNQAECn8hAAIIAAgKkBxuLACzAgAIAAgKkBxuLACzAgAAAA==.Elimee:BAABNQAECn82AAILAAkK8iPEHABkAwALAAkK8iPEHABkAwAAAA==.Ellasia:BAAANQABCgMIAwAAAA==.Elvenbane:BAAANQAECgUIDgAAAA==.',
Em='Emart:BAAANQAECgMIBgAAAA==.',
Er='Erayna:BAABNQAECn8gAAIBAAgKDg1TLwCcAQABAAgKDg1TLwCcAQAAAA==.',
Es='Essence:BAAANQAECggIEAAAAA==.',
Et='Etherious:BAAANQADCgUICwABNQADCggICwAGAAAAAA==.',
Ev='Evelinah:BAAANQAECggICAAAAA==.',
Fa='Falconclaw:BAAANQADCggIIQAAAA==.Falkensnoman:BAAANQAECgMIBgAAAA==.Fayedra:BAABNQAECn8aAAIaAAcKWRQJHQCzAQAaAAcKWRQJHQCzAQAAAA==.',
Fe='Feenii:BAABNQAECn8hAAIKAAgKLAm5GADWAQAKAAgKLAm5GADWAQAAAA==.',
Fi='Fizzlelich:BAAANQADCggIJgAAAA==.',
Fo='Foxdeer:BAAANQAECgUIDwAAAA==.Foxxmccloud:BAAANQADCgIJAgABNQAECgkJIwADAD0cAA==.',
Fu='Fungies:BAABNQAECn8qAAINAAkKHhT4WgBCAgANAAkKHhT4WgBCAgAAAA==.Furybest:BAAANQAECgQIBAAAAA==.Furyrage:BAAANQADCgQIBAAAAA==.',
Ga='Gannir:BAAANQAECgEIAQAAAA==.Gatman:BAAANQADCgYICQAAAA==.',
Gi='Gimiltockel:BAAANQADCgMIAwAAAA==.Giramar:BAAANQAECgYIDAAAAA==.',
Go='Gochujang:BAAANQAECgQIBAABNQAECgkJJQACACUfAA==.Gojo:BAEANQAECgEIAwAAAA==.Goldeelock:BAAANQADCggIDQAAAA==.Gotchya:BAAANQABCgEIAQAAAA==.Goteem:BAAANQAECgUIBwAAAA==.Gothitelle:BAAANQADCgIIAgAAAA==.',
Gr='Grandad:BAAANQAECgMIAwAAAA==.Grandest:BAAANQADCgQIBAAAAA==.Grantaire:BAAANQADCggIEgAAAA==.Grimmdogg:BAAANQAECgMIAwAAAA==.Grimrox:BAAANQAECgcIEwAAAA==.Grombo:BAAANQAECgIIAgAAAA==.',
Ha='Haanit:BAAANQADCgIIAgAAAA==.Hakela:BAAANQAECgEJAQAAAA==.Hardlyevoker:BAAANQADCgMIAwABNQAECggIKwAIAL4eAA==.',
He='Healingwave:BAAANQADCgYIBgAAAA==.Hearnê:BAAANQADCgEIAQAAAA==.Heavyarm:BAAANQADCgEIAQAAAA==.Heethen:BAAANQAECgUICQAAAA==.Hexbox:BAABNQAECn8YAAMbAAgKwBRFbwC6AQAbAAcKJhdFbwC6AQACAAcKHg9bhQCTAQAAAA==.',
Hi='Himawari:BAABNQAECn8bAAMcAAgKvA94HQBmAQAcAAcKvA94HQBmAQAdAAEKAACWMgA1AAAAAA==.',
Ho='Hoffmin:BAABNQAECn8pAAMVAAkK+R0DDgAFAwAVAAgK8yADDgAFAwAeAAEKGgx6jwA3AAAAAA==.Holemeister:BAABNQAECn8qAAIFAAgKgSMnMgAAAwAFAAgKgSMnMgAAAwAAAA==.Holyamin:BAAANQAECgMIBgAAAA==.Holymann:BAAANQAECgQIBwAAAA==.Holyschnikey:BAABNQAECn8gAAIIAAcKzxWmZgDhAQAIAAcKzxWmZgDhAQAAAA==.Holyz:BAABNQAECn8aAAIIAAcKYST0IQDjAgAIAAcKYST0IQDjAgAAAA==.Horgable:BAAANQADCgEIAQAAAA==.Horrorpops:BAAANQAECgIIAgABNQAECgkJKQAOAP8gAA==.',
Hu='Hugginz:BAAANQADCgYIEgAAAA==.Hunzul:BAAANQADCgQIBAAAAA==.',
Hy='Hypnototem:BAAANQAECgEIAQAAAA==.',
['Hè']='Hèimdall:BAAANQAECgUIEgAAAA==.',
['Hí']='Hílthaen:BAABNQAECn8jAAITAAgKtx0yLgCtAgATAAgKtx0yLgCtAgAAAA==.',
Ic='Icehead:BAAANQAECgQIAwAAAA==.Ichigokisu:BAAANQADCgQIBAAAAA==.',
Ih='Ihavenobrain:BAAANQABCgIIAgAAAA==.',
Il='Illy:BAABNQAECn8dAAIVAAgKTxAUKgDtAQAVAAgKTxAUKgDtAQAAAA==.',
In='Instantdeath:BAAANQADCgMIAwAAAA==.',
Is='Ishivyounot:BAAANQADCgUICgAAAA==.',
Iv='Ivranda:BAAANQAECgcIEwAAAA==.',
Ix='Ixio:BAAANQADCgYIBgAAAA==.',
Ja='Jahan:BAABNQAECn8pAAMTAAkKUiR8BwCHAwATAAkK1yJ8BwCHAwAfAAcKXR7dBABtAgABNQAECgQIBAAGAAAAAA==.Jamie:BAABNQAECn8VAAMRAAcKgSQJKQB3AgARAAYKgSQJKQB3AgAQAAEKAABN3gAzAAABNQAFFAcIDgANAAgjAA==.Jarek:BAAANQABCgQIBAAAAA==.',
Je='Jegra:BAABNQAECn8gAAIgAAcKqx/8GQBtAgAgAAcKqx/8GQBtAgAAAA==.Jerith:BAABNQAECn8jAAMYAAgK3QwSQwC3AQAYAAgK3QwSQwC3AQAhAAYKPwUMNAAVAQAAAA==.Jerryy:BAEANQADCgEIAgABNQAECgEIAwAGAAAAAA==.Jessilyn:BAAANQADCgYIEwAAAA==.',
Ji='Jigari:BAAANQADCgcIDgAAAA==.Jinxed:BAAANQAECgMIAwAAAA==.',
Jo='Jord:BAAANQAECgQIBAAAAA==.',
Ju='Jubellina:BAABNQAECn8sAAISAAgKTRH5GwC/AQASAAgKTRH5GwC/AQAAAA==.Jubîlee:BAAANQABCgIIAgAAAA==.',
['Jà']='Jàzz:BAAANQADCgYIHAAAAA==.',
Ka='Kaelora:BAAANQADCgYICQAAAA==.Kaerei:BAAANQADCgQJBAAAAA==.Kaleb:BAECNQAFFH8KAAIeAAQKShb3DAA7AQAeAAQKShb3DAA7AQA1AAQKfy8AAh4ACQo9I5wGAIsDAB4ACQo9I5wGAIsDAAAA.Kalferno:BAAANQAECgIIAgAAAA==.Kayotica:BAAANQADCgcIEgAAAA==.',
Ke='Kendall:BAAANQAECgQIBAABNQAECgYIDgAGAAAAAA==.',
Kh='Khallock:BAAANQAECgQICwAAAA==.',
Ki='Kiemen:BAAANQAECgYIDgAAAA==.Killko:BAABNQAECn8bAAMPAAgK6RA1QwCwAQAPAAgK6RA1QwCwAQAQAAIKpQq+xgBaAAAAAA==.Kirisen:BAAANQAECgIIAwAAAA==.',
Kn='Knardan:BAABNQAECn8fAAIOAAcKOh4kVgBtAgAOAAcKOh4kVgBtAgAAAA==.',
Ko='Kotanx:BAAANQADCggIEQAAAA==.',
Kr='Kragsloor:BAAANQADCggICwAAAA==.',
Ku='Kuraki:BAABNQAECn8aAAIgAAcKIAuENwBTAQAgAAcKIAuENwBTAQAAAA==.',
Ky='Kyriea:BAAANQADCgYIBgAAAA==.',
La='Ladrar:BAAANQAECgEIAQAAAA==.Lanadiel:BAABNQAECn8mAAIEAAgKvCJBCgD1AgAEAAgKvCJBCgD1AgAAAA==.Lasalghoul:BAAANQAECgYICwAAAA==.Lassyn:BAAANQADCgMIAwABNQAECgYICwAGAAAAAA==.',
Le='Legend:BAAANQAFFAEIAgAAAA==.Len:BAABNQAECn8rAAMbAAkKeBLAWAADAgAbAAkKeBLAWAADAgACAAUKbwz2xQACAQAAAA==.Leoñidas:BAAANQAECgUICwAAAA==.',
Li='Lian:BAAANQAECgQIBQAAAA==.Lianda:BAAANQAECggICAAAAA==.Lianse:BAAANQADCgYICwAAAA==.Liliara:BAABNQAECn8iAAIOAAkK4hVjRQCaAgAOAAkK4hVjRQCaAgAAAA==.Lillyirl:BAAANQADCgcIBwAAAA==.Lillymae:BAAANQAECgcIDgAAAA==.Lillyslight:BAAANQADCgUIBQAAAA==.Lillytae:BAAANQADCgYIBgAAAA==.Lillyvani:BAAANQADCgcIBwAAAA==.Lilmoo:BAAANQAECgQICgAAAA==.Lilpump:BAAANQAECgQICQABNQAECgkJIQARAEoUAA==.Lindalinda:BAAANQADCgEIAQAAAA==.Linkhunter:BAAANQAECgUIBQABNQAECggIJQAfAA8iAA==.Linkmônk:BAAANQADCgcICgABNQAECggIJQAfAA8iAA==.',
Lo='Lodise:BAABNQAECn8fAAIMAAcKNhIuCgDVAQAMAAcKNhIuCgDVAQAAAA==.Lorzz:BAABNQAECn8sAAITAAkKrx3PIwDbAgATAAkKrx3PIwDbAgAAAA==.Loveydovey:BAAANQADCgIIAgAAAA==.',
Lu='Lucrio:BAABNQAECn8nAAIQAAgKNhTxTQDZAQAQAAgKNhTxTQDZAQAAAA==.Ludlow:BAAANQADCgMIAwABNQAECggIIgAYALMRAA==.Lunalai:BAAANQAECgQIBAAAAA==.Lurim:BAABNQAECn8jAAIaAAkKzB/+BQAyAwAaAAkKzB/+BQAyAwAAAA==.Lushy:BAABNQAECn8hAAIhAAgK9A+HFQA1AgAhAAgK9A+HFQA1AgAAAA==.',
Ly='Lylindara:BAABNQAECn8ZAAIbAAgKJghQkgBWAQAbAAgKJghQkgBWAQAAAA==.Lylinette:BAAANQADCggIDwAAAA==.',
Ma='Madgorilla:BAAANQADCgUIBQAAAA==.Mageofdeath:BAABNQAECn8gAAILAAYKhAk4JwFGAQALAAYKhAk4JwFGAQABNQADCgMIAwAGAAAAAA==.Mageskin:BAAANQAECgMIBwAAAA==.Maladaptive:BAAANQADCgYIDwAAAA==.Manerva:BAAANQADCgYIFwAAAA==.Mastorcheef:BAAANQADCgEIAQAAAA==.Maurin:BAAANQAECgMIAwAAAA==.Maximumhonk:BAABNQAECn8eAAIbAAcKJhxnTwAkAgAbAAcKJhxnTwAkAgAAAA==.Maxonoa:BAAANQADCggJFwAAAA==.Maxximos:BAAANQADCgYICAAAAA==.',
Me='Mekkadaddy:BAAANQAECgYIEwAAAA==.Mellow:BAAANQAECgMIAwAAAA==.Mendelia:BAABNQAECn8aAAIEAAYKQhcyJgCpAQAEAAYKQhcyJgCpAQAAAA==.Mercus:BAABNQAECn8eAAMhAAgKyA/5IQC4AQAhAAcKVg/5IQC4AQAYAAcKvA74RQCoAQAAAA==.Merllinna:BAAANQABCgIIAQAAAA==.Mervenious:BAAANQAECgQIDAAAAA==.',
Mi='Mindplague:BAABNQAECn8eAAIHAAYKvhoHJQAEAgAHAAYKvhoHJQAEAgAAAA==.Minipincin:BAAANQAECgMIAgAAAA==.Minmzey:BAAANQAECgIJAgAAAA==.Miroslava:BAAANQADCgEIAQAAAA==.Missfire:BAAANQAECgcIDAAAAA==.',
Mo='Moggle:BAAANQAECgUIDgAAAA==.Mondazi:BAABNQAECn8qAAMCAAkK/hyHOACRAgACAAgKhxuHOACRAgAbAAkKlA6lZwDSAQAAAA==.Moonlilly:BAAANQADCgIIAgAAAA==.Morfy:BAAANQABCggIBgAAAA==.Morgzim:BAAANQADCgYJBwAAAA==.Moustaccio:BAAANQAECgEIAgAAAA==.Mozarta:BAAANQABCggIDQAAAA==.',
Ms='Msmanalow:BAAANQAECgEIAQABNQAECgcIDAAGAAAAAA==.',
My='Mycen:BAABNQAECn8XAAINAAgKbgwbjwC8AQANAAgKbgwbjwC8AQAAAA==.Myeyesburn:BAAANQAECgMJBAAAAA==.',
['Má']='Málaketh:BAAANQAECgUIBQAAAA==.',
Na='Nardena:BAAANQAECgEIAQAAAA==.Narz:BAABNQAECn8rAAIOAAgKkArahQD8AQAOAAgKkArahQD8AQAAAA==.Naughtypine:BAAANQADCgYIBgAAAA==.Naylz:BAAANQAECggIAQAAAA==.',
Ne='Necronomikon:BAAANQAECgcIEAAAAA==.Nerhzul:BAAANQADCgUIBQAAAA==.Neromoo:BAAANQAECgUIDQABNQAECggIEwAGAAAAAA==.Neruphuyt:BAABNQAECn8XAAIDAAcKYgkIXABdAQADAAcKYgkIXABdAQAAAA==.',
Ni='Niath:BAAANQAECgQIBQAAAA==.Nightheal:BAAANQABCgQIBQABNQAECggIIAARAKQkAA==.Nightsniper:BAAANQAECgEIAQABNQAECggIIAARAKQkAA==.',
No='Notdinor:BAAANQADCgIIAgAAAA==.Notlilly:BAABNQAECn8dAAIcAAgKthLeFADWAQAcAAgKthLeFADWAQAAAA==.Notpillows:BAAANQADCggIFAAAAA==.',
Ny='Nyxelle:BAAANQAECgIIAwAAAA==.',
['Nä']='Närz:BAAANQADCggIBQAAAA==.',
['Nò']='Nòvà:BAAANQAECgMIBQAAAA==.',
Oi='Oilfu:BAAANQADCgUIBQABNQAECggIIQAhAPQPAA==.',
Ok='Okioni:BAAANQAECgUIBQAAAA==.',
Ol='Olgon:BAABNQAECn8rAAIOAAkKuBAnVQBvAgAOAAkKuBAnVQBvAgAAAA==.',
Op='Oprhawinfury:BAABNQAECn8bAAIQAAcK9wtyawBhAQAQAAcK9wtyawBhAQAAAA==.',
Or='Orgodemir:BAABNQAECn8aAAITAAcKByUCIADtAgATAAcKByUCIADtAgAAAA==.Orhamin:BAAANQADCgYIDwAAAA==.',
Os='Oshani:BAAANQAECgQIBAAAAA==.',
Ou='Outlaw:BAAANQADCgcIBwAAAA==.',
Pa='Pacolyte:BAAANQAECgMIBAAAAA==.Paigor:BAAANQABCgIIAgAAAA==.Palathene:BAAANQAECggIEQAAAA==.Pallystorm:BAAANQAECgUIBQAAAA==.Palmike:BAAANQADCgYIBgAAAA==.Pandemonia:BAABNQAECn8tAAINAAgK8xLdcwABAgANAAgK8xLdcwABAgAAAA==.Parsie:BAAANQAECgIIAgAAAA==.Pathibas:BAAANQADCggIDQABNQAECggIKQAdAOcfAA==.Pattycakes:BAABNQAECn8eAAIQAAgKBg56XACaAQAQAAgKBg56XACaAQAAAA==.',
Ph='Pherocious:BAAANQAECgMIBAAAAA==.',
Pi='Pinktuesday:BAAANQADCggICAAAAA==.Pixeleen:BAACNQAFFH8FAAIOAAQKrARXFQANAQAOAAQKrARXFQANAQA1AAQKfy0AAw4ACQoDI/klAP4CAA4ACQoDI/klAP4CACIABQrfCiRMAP4AAAAA.',
Pl='Plexy:BAABNQAECn8gAAMTAAkKYSAtIQDoAgATAAkKuh8tIQDoAgAfAAcK8hlJCADgAQAAAA==.',
Po='Pokitz:BAAANQAECgUIDgAAAA==.',
Pr='Primordinor:BAABNQAECn8hAAICAAcK3RrMVwAZAgACAAcK3RrMVwAZAgAAAA==.Probnotalive:BAABNQAECn8jAAIOAAkKIh7AFgA+AwAOAAkKIh7AFgA+AwAAAA==.Probnoturmom:BAABNQAECn8kAAITAAgKXxyhLACzAgATAAgKXxyhLACzAgAAAA==.',
Qu='Quacko:BAAANQABCgIIAgABNQAECgkJIwAaAMwfAA==.',
Ra='Raevyn:BAAANQAECgEIAQAAAA==.Raikai:BAAANQADCgMIAwABNQAECggIIQAIAJAcAA==.Rakan:BAABNQAECn8rAAMcAAkKDB2VBwDdAgAcAAkKDB2VBwDdAgAWAAUKeQ325QAUAQAAAA==.Rallick:BAABNQAECn8hAAIIAAkKSRFAUwAeAgAIAAkKSRFAUwAeAgAAAA==.Ranì:BAABNQAECn8lAAIcAAgK4xQSFgDEAQAcAAgK4xQSFgDEAQAAAA==.Rathger:BAAANQADCgUICAAAAA==.Ratmilk:BAAANQAECgcIDAAAAA==.Razkhan:BAAANQADCgcIDQAAAA==.',
Rd='Rdk:BAAANQAECgMIBAAAAA==.',
Re='Redek:BAAANQADCgcICgAAAA==.Reighna:BAAANQADCggIDQAAAA==.Rendwee:BAABNQAECn8pAAIjAAgK5h7jBwDaAgAjAAgK5h7jBwDaAgAAAA==.Reps:BAAANQAECgYIBgAAAA==.Retiredaggro:BAAANQAECgUIDgAAAA==.Retiredghoul:BAAANQADCgUIBQAAAA==.Retiredlight:BAAANQADCgEIAQAAAA==.Reuel:BAAANQADCgYIBgAAAA==.Rewolf:BAAANQAECgUIDQAAAA==.',
Rh='Rhaella:BAAANQABCgMIAwAAAA==.Rhynar:BAAANQAECggICAAAAA==.',
Ri='Ricflairion:BAABNQAECn8gAAIkAAcKjQvBDgBUAQAkAAcKjQvBDgBUAQAAAA==.Rill:BAAANQADCggICwAAAA==.',
Ro='Rodcet:BAABNQAECn8pAAIFAAkKGyHsHQBKAwAFAAkKGyHsHQBKAwAAAA==.Roflbubble:BAABNQAECn8jAAMTAAgK9BQiXwAAAgATAAgK9BQiXwAAAgAHAAUKdAWtVAC2AAAAAA==.Rognan:BAAANQADCgMIAwAAAA==.Roku:BAAANQADCgcIGQAAAA==.Ronkin:BAAANQADCgYIFwAAAA==.Rookgue:BAABNQAECn8oAAIYAAcKGRImQADGAQAYAAcKGRImQADGAQAAAA==.Rookoker:BAAANQAECgUIDgAAAA==.Rorygazer:BAAANQAECgUIDgAAAA==.Rosmerta:BAAANQADCgYIBwAAAA==.Rossa:BAAANQABCgIIAgAAAA==.Rossdair:BAAANQAECgQICgAAAA==.Rossperot:BAABNQAECn8bAAIQAAcKLh2jSQDsAQAQAAcKLh2jSQDsAQAAAA==.',
Ry='Ryk:BAAANQAECgIIAgAAAA==.',
Sa='Saarin:BAAANQADCggIDAAAAA==.Saelara:BAAANQAECgUIBQAAAA==.Sairal:BAAANQAECgcIDwAAAA==.Saltytuesday:BAAANQADCgYICQAAAA==.Samgee:BAACNQAFFH8MAAIFAAQKpw91EAA+AQAFAAQKpw91EAA+AQA1AAQKfzEAAgUACQqXH9wyAP4CAAUACQqXH9wyAP4CAAAA.Sawlty:BAABNQAECn8eAAIiAAgKrw6iLwDNAQAiAAgKrw6iLwDNAQAAAA==.Saynar:BAABNQAECn8hAAMVAAgK1R9iEwDMAgAVAAgKyR9iEwDMAgAXAAIKRR3OJQCHAAAAAA==.',
Sc='Scattered:BAABNQAECn8eAAMUAAgKmQzcJgA+AQAUAAYKqQvcJgA+AQANAAUKMgr04wD8AAAAAA==.Schecter:BAABNQAECn8YAAMbAAcKJyP0MACaAgAbAAcKJyP0MACaAgACAAEKCxjIJQE/AAAAAA==.Scintila:BAAANQADCgQIBAABNQAECggILQANAPMSAA==.Scooti:BAAANQADCggIEAABNQAECgYICgAGAAAAAA==.',
Se='Seba:BAABNQAECn84AAILAAkK6xxDVQDWAgALAAkK6xxDVQDWAgAAAA==.Sehren:BAAANQADCgcIBgAAAA==.Sehtrak:BAAANQADCggICAAAAA==.Selesne:BAABNQAECn8aAAIlAAcK/wkADgBcAQAlAAcK/wkADgBcAQAAAA==.Seniandrays:BAAANQADCgQIBAAAAA==.Serannia:BAAANQADCgIIAgAAAA==.Seraphicktwo:BAABNQAECn8XAAMHAAYKDQ1WPQA9AQAHAAYKDQ1WPQA9AQATAAEKTgZt+gAvAAAAAA==.',
Sh='Shadowlune:BAAANQABCgIIAgAAAA==.Shadowtrance:BAAANQADCgYIBgABNQAECgcIIgAEACwYAA==.Shaggmz:BAAANQAECgUICgAAAA==.Shelyn:BAAANQADCgEIAQAAAA==.Shinma:BAAANQAECgUICgAAAA==.Shootermcgee:BAAANQAECgIIAgAAAA==.Showtootsies:BAAANQADCgUJBQAAAA==.Shrubbery:BAAANQAECgQIBwAAAA==.Shymary:BAAANQAECgUICgAAAA==.',
Si='Siete:BAAANQADCgYJBwAAAA==.Silëx:BAAANQAECgYIEgAAAA==.Sindiz:BAAANQAECgQICAAAAA==.Siouxiesioux:BAAANQAECgQIBAAAAA==.',
Sk='Skadie:BAAANQADCgcIEQAAAA==.Skoot:BAAANQAECgYICgAAAA==.',
Sl='Slimjimz:BAAANQADCgQIBAAAAA==.Slugondeez:BAABNQAECn8rAAMIAAgKvh7jJgDMAgAIAAgKvh7jJgDMAgAEAAIKUyMqTgCrAAAAAA==.',
Sm='Smitefist:BAAANQAECgEIAQABNQAECggIDQAGAAAAAA==.',
Sn='Snkyturtle:BAABNQAECn8rAAIOAAgKDw7ffwAKAgAOAAgKDw7ffwAKAgAAAA==.Snoopdogydog:BAAANQABCgQIAwAAAA==.Snuzzle:BAABNQAECn8gAAIaAAgK7Ri6EwAiAgAaAAgK7Ri6EwAiAgAAAA==.',
So='Sourmash:BAAANQAECgQIBAAAAA==.',
Sp='Spaghet:BAAANQAECgcIEAAAAA==.Spillthetea:BAAANQADCggICQABNQAECgUIDgAGAAAAAA==.Spittoon:BAAANQADCgEJAQABNQADCgcIFAAGAAAAAA==.Sploot:BAABNQAECn8YAAINAAkK/Rg3QACOAgANAAkK/Rg3QACOAgAAAA==.',
Sr='Srasjet:BAAANQAECgMIBgAAAA==.',
Ss='Ssarmandok:BAAANQAECgYICgAAAA==.',
St='Stabytha:BAAANQAECgYICQAAAA==.Stark:BAAANQABCgQIBAAAAA==.Starlight:BAAANQAECggIEwAAAA==.Stealthed:BAAANQAECgQIBgAAAA==.Stender:BAAANQADCgIIAgABNQAFFAIIBwAeAH8eAA==.Stonegoddess:BAAANQADCgQIBAAAAA==.Stormcall:BAAANQAECgIIBAAAAA==.Stratusfied:BAAANQADCgIIAgAAAA==.Strongsad:BAAANQADCgcIBwAAAA==.',
Sw='Swiss:BAABNQAECn8aAAICAAcKHw+/fgCkAQACAAcKHw+/fgCkAQAAAA==.',
Sy='Syldra:BAAANQABCgIIAgAAAA==.',
['Sá']='Sáëgárón:BAAANQAECgMIBAAAAA==.',
Ta='Taliden:BAAANQAECgMIBQAAAA==.Tankinstine:BAAANQADCgYIBwAAAA==.Taraylda:BAAANQAECgUIDgAAAA==.Tazzwolfsong:BAAANQADCgEIAQAAAA==.',
Te='Tecdor:BAAANQADCgYJBgAAAA==.Teronfiggy:BAAANQAECgYIDAAAAA==.',
Tf='Tfirs:BAAANQAECgQJBwABNQAFFAEIAQAGAAAAAA==.',
Th='Thehealczar:BAAANQAECgcIDwABNQAECggIIAARAKQkAA==.Theokoles:BAAANQAECggIDQAAAA==.Thesenate:BAAANQADCggIDwABNQAECggIIQAKACwJAA==.Thickblòód:BAAANQADCgEIAQAAAA==.Thorly:BAAANQADCgYIDQAAAA==.',
Ti='Tiadalma:BAAANQADCgEIAQAAAA==.Tinn:BAAANQADCggIEAAAAA==.',
To='Toospookie:BAAANQADCgYIDgAAAA==.Totem:BAAANQAECgQIBQAAAA==.',
Tr='Tramplip:BAAANQAECgQIDwAAAA==.Treecloud:BAABNQAECn8kAAIaAAgKMyElCAD5AgAaAAgKMyElCAD5AgAAAA==.Treferimore:BAAANQAECgQICAAAAA==.Trevian:BAABNQAECn8aAAIFAAcKhQ7VwgCQAQAFAAcKhQ7VwgCQAQAAAA==.',
Tu='Tuluxxi:BAABNQAECn8pAAMbAAgK5iF3GgAEAwAbAAgK5iF3GgAEAwACAAgKfQ6gcgDFAQAAAA==.Tutter:BAAANQAECgUIBwAAAA==.',
Tw='Twopumpchump:BAAANQAECgYIEwAAAA==.',
Tz='Tzxdh:BAAANQAECgIIAgABNQAECgcIFAAEAJYTAA==.Tzxdruid:BAAANQAECgEIAQABNQAECgcIFAAEAJYTAA==.',
Ug='Uglymancer:BAABNQAECn8aAAINAAcK1RTqgADfAQANAAcK1RTqgADfAQAAAA==.',
Uj='Ujimas:BAABNQAECn8XAAICAAUKBhPXqQA8AQACAAUKBhPXqQA8AQAAAA==.',
Ut='Uthodne:BAAANQAECgEIAQABNQAECggIIgAYALMRAA==.',
Va='Vampireshade:BAABNQAECn8jAAMYAAgKRAvoOwDcAQAYAAgKRAvoOwDcAQAlAAYK/gMVEgDlAAAAAA==.Vampirevoid:BAAANQADCgUIBQAAAA==.Vanililly:BAABNQAECn8gAAIRAAgKZwwrVAChAQARAAgKZwwrVAChAQAAAA==.Vanimao:BAAANQAECgEIAQAAAA==.Varan:BAAANQAECgEIAQAAAA==.',
Vb='Vbull:BAAANQAECgEIAQAAAA==.',
Ve='Velissari:BAAANQAECgMIBgAAAA==.Venatra:BAAANQADCgYICAAAAA==.Veritus:BAABNQAECn8gAAIeAAgK9x58HACyAgAeAAgK9x58HACyAgAAAA==.',
Vi='Vindict:BAAANQAECgMIBgAAAA==.Violette:BAAANQAECgQIDwAAAA==.Vion:BAAANQABCgQIBAAAAA==.',
Vo='Voidlink:BAABNQAECn8lAAIfAAgKDyLpAQAYAwAfAAgKDyLpAQAYAwAAAA==.Voidstriker:BAAANQAECgEIAQAAAA==.',
Wa='Wackyrellek:BAAANQAECgcIEQAAAA==.Wakancer:BAAANQAECgQIEQAAAA==.Wakarisma:BAAANQAECgEIAQAAAA==.Wakataclysm:BAAANQAECgQICwAAAA==.Walnut:BAAANQAECgQIBAABNQAECgkJJQACACUfAA==.Warchylde:BAAANQADCgQIBgAAAA==.Warolderoy:BAABNQAECn8pAAMdAAgK5x/0BADcAgAdAAgKcB/0BADcAgAcAAYKkBouFwC1AQAAAA==.',
We='Weedshaman:BAAANQADCgcJBwAAAA==.',
Wo='Woker:BAAANQADCggIEQABNQAECggIIQAKACwJAA==.Woogie:BAAANQAECgQIBwAAAA==.Worthy:BAAANQADCgQIBAAAAA==.',
Wu='Wummie:BAAANQAECgMIAwABNQAECggIHwANAKAeAA==.',
['Wò']='Wòógie:BAAANQADCgYIBgABNQAECgQIBwAGAAAAAA==.',
Xa='Xader:BAAANQADCggIEAAAAA==.',
Xe='Xenna:BAAANQAECgUICgABNQAECggIGwAFAEISAA==.Xeq:BAAANQAECgMIAwAAAA==.',
Xi='Xiata:BAAANQADCggICAAAAA==.',
Ye='Yeoman:BAAANQAECgYIEQAAAA==.Yewko:BAAANQAECgYIEwAAAA==.',
Yg='Yggdralith:BAAANQAECgcIGgAAAQ==.',
Yu='Yunohealme:BAABNQAECn8aAAIPAAcK/RngMgAPAgAPAAcK/RngMgAPAgAAAA==.Yunosmall:BAAANQADCgMIAwAAAA==.Yunosmart:BAAANQADCgMIBAAAAA==.',
['Yö']='Yör:BAAANQADCgEIAQAAAA==.',
Za='Zaen:BAABNQAECn8uAAMNAAkKwR2oIwDzAgANAAkKwR2oIwDzAgAUAAMK1BjwPwDBAAAAAA==.Zandre:BAABNQAECn8gAAIcAAgKExdvEwDrAQAcAAgKExdvEwDrAQAAAA==.Zarkir:BAABNQAECn8oAAIRAAkK0SLcDABJAwARAAkK0SLcDABJAwAAAA==.',
Ze='Zelily:BAABNQAECn8jAAIOAAgKPQzOggADAgAOAAgKPQzOggADAgAAAA==.Zenarri:BAAANQADCgYICgAAAA==.',
Zh='Zharvakko:BAABNQAECn8fAAMbAAcKMxZGcgCxAQAbAAcKMxZGcgCxAQACAAcKrhCvggCaAQABNQAECggIHgAbAJIeAA==.Zhiana:BAABNQAECn8cAAMJAAgKQxEmDgDIAQALAAgKOwwi3ADMAQAJAAgK7A0mDgDIAQAAAA==.',
Zo='Zornov:BAAANQADCgcIBwABNQAECgkJIwAaAMwfAA==.',
Zu='Zulrich:BAAANQAECgYICwAAAA==.',
Zv='Zvirae:BAAANQADCggICAAAAA==.Zvirax:BAAANQADCgYIHAABNQADCggICAAGAAAAAA==.',
['Ás']='Ástrid:BAAANQAECgEIAQAAAA==.',
['Ëu']='Ëuni:BAAANQADCgQIBAAAAA==.',
['Ìs']='Ìsaac:BAAANQAECgYJEgAAAA==.',
['Ðo']='Ðolm:BAAANQAECgQIBAAAAA==.',
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
