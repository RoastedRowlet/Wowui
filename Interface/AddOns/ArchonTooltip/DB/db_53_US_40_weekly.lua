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

local lookup = {'Druid-Restoration','Shaman-Elemental','Druid-Balance','Paladin-Protection','DeathKnight-Unholy','DeathKnight-Frost','Paladin-Retribution','Unknown-Unknown','Priest-Shadow','Mage-Arcane','Paladin-Holy','Mage-Frost','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Shaman-Enhancement','DemonHunter-Havoc','Warlock-Affliction','Warlock-Demonology','Hunter-BeastMastery','DeathKnight-Blood','Monk-Mistweaver','Shaman-Restoration','Warlock-Destruction','Priest-Holy','DemonHunter-Devourer','Warrior-Arms','DemonHunter-Vengeance','Hunter-Survival','Druid-Guardian','Warrior-Protection','Warrior-Fury','Priest-Discipline','Monk-Windwalker','Evoker-Preservation','Hunter-Marksmanship','Druid-Feral','Evoker-Augmentation','Monk-Brewmaster',}
local provider = {region='US',realm='Bloodhoof',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Aberforthd:BAAANQAECgUIDgAAAA==.',
Ac='Aceforlife:BAAANQADCggIEAABNQAECgkJPwABAOUPAA==.Acorn:BAACNQAFFH8GAAICAAIKXxBNEwCOAAACAAIKXxBNEwCOAAA1AAQKfysAAgIACgqzHtYfAA0DAAIACgqzHtYfAA0DAAAA.',
Ad='Aditu:BAABNQAECn8kAAMBAAcK/RWmNQBuAQABAAYKEhSmNQBuAQADAAcKlw7LMQAKAQAAAA==.',
Ae='Aetheris:BAABNQAECn8XAAIEAAgKNhXYLAB2AQAEAAgKNhXYLAB2AQAAAA==.',
Ag='Agasonex:BAAANQADCgUIBAAAAA==.',
Ah='Ahziz:BAABNQAECn8YAAMFAAYKERCbdwA7AQAFAAYKERCbdwA7AQAGAAUKpwcYWQC4AAAAAA==.',
Ai='Airent:BAABNQAECn8WAAMDAAYKRA+IZwAuAQADAAYKRA+IZwAuAQABAAQK7QYLaABlAAAAAA==.',
Al='Alaestel:BAABNQAECn82AAIHAAoK8QwYZgCLAQAHAAoK8QwYZgCLAQAAAA==.Aletheia:BAAANQAECgQIBAAAAA==.Alt:BAAANQAECgIIBAAAAA==.',
An='Ancane:BAAANQADCggICAAAAA==.Andramealoch:BAAANQADCgEIAQAAAA==.Angina:BAAANQADCgUIBwAAAA==.Angrywoogie:BAAANQADCgEIAQABNQAECgQIBwAIAAAAAA==.Annarcis:BAAANQAECgUIDgAAAA==.Antiman:BAAANQAECgMIBgAAAA==.Anäster:BAABNQAECn8hAAIJAAgKdhblJAAJAgAJAAgKdhblJAAJAgAAAA==.',
Ao='Aoiris:BAAANQADCggIEAAAAA==.',
Ap='Aplcyder:BAABNQAECn8oAAIBAAoKqQxzHACBAQABAAoKqQxzHACBAQAAAA==.Apocryphea:BAAANQAECgUICQAAAA==.',
Ar='Arabloom:BAAANQADCgYIBgAAAA==.Arachnid:BAABNQAECn8eAAIKAAkKkxouLABCAgAKAAkKkxouLABCAgAAAA==.Aradalon:BAABNQAECn8oAAILAAkKmyFNDwBRAwALAAkKmyFNDwBRAwAAAA==.Aratyn:BAABNQAECn8fAAIMAAcKFBVpDQDaAQAMAAcKFBVpDQDaAQAAAA==.Arianabelia:BAAANQADCgEIAQAAAA==.',
As='Asanot:BAAANQADCgQIBAAAAA==.Astranacht:BAABNQAECn8xAAIDAAgKYBDpJwBHAQADAAgKYBDpJwBHAQAAAA==.',
Au='Auntjemimma:BAABNQAECn8lAAIHAAkKbBIiiQAUAgAHAAkKbBIiiQAUAgAAAA==.Auriandra:BAAANQAECgQICAAAAA==.',
Ax='Axa:BAAANQADCggIHAAAAA==.',
Ay='Ayroonoo:BAAANQADCgMIAwAAAA==.',
Ba='Babyshoes:BAAANQAECgUICgAAAA==.Backhawk:BAAANQAECgMIBAAAAA==.Backsurgery:BAABNQAECn8jAAQNAAkKNSDNCwDZAgANAAkKNSDNCwDZAgAOAAIKhRaUiACQAAAPAAIKEhKMFgB/AAABNQAFFAUIEwAQAL0gAA==.Baerrn:BAABNQAECn8XAAIRAAYKCwP4aQDRAAARAAYKCwP4aQDRAAAAAA==.Baricia:BAABNQAECn8nAAIKAAoKpQs93QDNAQAKAAoKpQs93QDNAQAAAA==.Barrin:BAABNQAECn8fAAMSAAgKSRjmBwAYAgASAAgKSRjmBwAYAgATAAIKSwCkQQE0AAAAAA==.Bawnchu:BAAANQADCggIFQAAAA==.',
Be='Beardad:BAAANQADCgcICQAAAA==.Bearded:BAAANQAECgcIEgAAAA==.Bearonica:BAEANQAECggICAABNQAFFAQICgALAKwZAA==.Beastmaster:BAABNQAECn8lAAIUAAoK3B3HMgDUAgAUAAoK3B3HMgDUAgAAAA==.Beefcakell:BAAANQADCgQIBAAAAA==.Belthar:BAAANQAECgUIBgAAAA==.Bentlymage:BAACNQAFFH8GAAIKAAIKgxUoJAChAAAKAAIKgxUoJAChAAA1AAQKfy4AAgoACgokH99XANACAAoACgokH99XANACAAAA.',
Bi='Bissafiyah:BAACNQAFFH8bAAIQAAcKQh43AADKAgAQAAcKQh43AADKAgA1AAQKfzwAAhAACgoNJmcAAG4DABAACgoNJmcAAG4DAAAA.Bittertea:BAABNQAECn8YAAIVAAYKHwM1kQDBAAAVAAYKHwM1kQDBAAAAAA==.',
Bl='Blakdeath:BAABNQAECn8fAAIGAAcKrQwQUQBuAQAGAAcKrQwQUQBuAQAAAA==.Blargghh:BAAANQAECgYIBgAAAA==.Bloodgon:BAABNQAECn8bAAMFAAcKYRm0IgBeAQAFAAcKYRm0IgBeAQAVAAIKTA0mtABhAAAAAA==.Bloodpriests:BAAANQAECgYIDgAAAA==.Bluetuesday:BAAANQADCgYIBgAAAA==.',
Bo='Bobthedemon:BAAANQAECgIIAwAAAA==.Bohica:BAAANQAECgQICAAAAA==.Boka:BAAANQADCgMIAgAAAA==.Bonechop:BAAANQADCgIIAgAAAA==.Bowseye:BAAANQAECgIIAgABNQAECgkJJQAHAGwSAA==.Boyakasha:BAABNQAECn8YAAIPAAYKLAn1DwAkAQAPAAYKLAn1DwAkAQAAAA==.',
Br='Brayne:BAAANQAECgUICwAAAA==.Brewsome:BAABNQAECn84AAIWAAoKEyIjBQBQAwAWAAoKEyIjBQBQAwAAAA==.Brighthammer:BAAANQADCgcIDQAAAA==.Bryybryy:BAABNQAECn8sAAIVAAkKwRxzJgCKAgAVAAkKwRxzJgCKAgAAAA==.Bryyguyy:BAAANQADCgIIAgABNQAECgkJLAAVAMEcAA==.',
Bu='Bubleherth:BAAANQADCgcIFwAAAA==.Bullymayes:BAAANQABCgYIBgAAAA==.Bunkiee:BAAANQADCggIFgAAAA==.',
Ca='Calbee:BAAANQADCgYIBwAAAA==.Candorite:BAAANQAECgUJBwABNQAECgcIGgAXANsYAA==.Capcoms:BAAANQAECgUICwABNQAECgkJNAAKAH0eAA==.Capita:BAABNQAECn8sAAIMAAgKORCVEQCNAQAMAAgKORCVEQCNAQAAAA==.Carsinegan:BAABNQAECn8aAAMYAAcK6xFuDwCiAAASAAQKIhC1GQC5AAAYAAUKHBNuDwCiAAAAAA==.Cassica:BAABNQAECn8dAAMJAAkKZxE+MQCZAQAJAAcK4hE+MQCZAQAZAAcKUhIFkQBjAQAAAA==.Catskin:BAAANQADCgYICQAAAA==.Causticminx:BAAANQABCgYIBwAAAA==.',
Ch='Chainlink:BAAANQADCgIIAgAAAA==.Charkle:BAABNQAECn8aAAIUAAUKXQrlAAEDAQAUAAUKXQrlAAEDAQAAAA==.Chillylilly:BAAANQAECggIEAAAAA==.Chummie:BAABNQAECn8oAAQTAAkKPR57XwA5AgATAAgKehx7XwA5AgASAAIKbSK+DgChAAAYAAIK0xXkUACMAAAAAA==.Chuud:BAAANQADCgQIBAAAAA==.',
Ci='Ciandoril:BAAANQAECgQICwAAAA==.Cid:BAAANQADCgQIBAAAAA==.',
Co='Comeanddie:BAAANQADCggIFAABNQADCgMIAwAIAAAAAA==.',
Cr='Crazyeyes:BAAANQAECgQICAABNQAECggIGAADAAIJAA==.Crimsondeath:BAABNQAECn8YAAIVAAYKpxBJdAAlAQAVAAYKpxBJdAAlAQAAAA==.Crylecks:BAAANQAECgYIBgAAAA==.',
Cy='Cyclonian:BAAANQAECggICAABNQAECggIDQAIAAAAAA==.Cylu:BAAANQADCggICwAAAA==.Cyprus:BAABNQAECn8hAAMBAAoKlhPwFwC0AQABAAoKlhPwFwC0AQADAAEKAACctAAuAAAAAA==.',
Da='Daelric:BAAANQAECgEIAQAAAA==.Daender:BAABNQAECn84AAIUAAoKMyI5DgDdAgAUAAoKMyI5DgDdAgAAAA==.Daenor:BAAANQAECgQIBAAAAA==.Daevie:BAABNQAECn8jAAIKAAkKxgVPDwFzAQAKAAkKxgVPDwFzAQAAAA==.Dairydemon:BAABNQAECn8vAAIaAAoKWQM1QQBEAQAaAAoKWQM1QQBEAQAAAA==.Damageus:BAABNQAECn82AAMKAAoKUSP6aQCqAgAKAAkKGiP6aQCqAgAMAAIKfySWMwBsAAAAAA==.Damworg:BAABNQAECn8VAAIbAAcKTxD4eQAiAQAbAAcKTxD4eQAiAQAAAA==.Daniryl:BAEANQAECggIEgABNQAECgkJHgACAH0TAA==.Dar:BAABNQAECn81AAIUAAoKtRIuSgC/AQAUAAoKtRIuSgC/AQAAAA==.Darcside:BAAANQAECgUIEAAAAA==.Daritar:BAEBNQAECn8eAAICAAkKfRNJZAD0AQACAAkKfRNJZAD0AQAAAA==.Darkburtus:BAABNQAECn8gAAIaAAkKvQQOJQD/AAAaAAkKvQQOJQD/AAAAAA==.Darkfeatherr:BAAANQAECgIIBAAAAA==.Darkxwraith:BAABNQAECn8vAAQEAAkKnRnZEQCIAQAEAAgKeRnZEQCIAQALAAEK5hbRuQBGAAAHAAEKCAoFpQE1AAAAAA==.Datsombeech:BAABNQAECn8tAAIbAAkKDwihvQCDAQAbAAkKDwihvQCDAQAAAA==.',
De='Defhammer:BAAANQABCggIGAAAAA==.Deka:BAAANQADCgMIAwAAAA==.Deàdly:BAAANQADCgUJCgAAAA==.',
Dh='Dhaynk:BAABNQAECn9EAAMcAAoKTh3vBADwAQAcAAgKvSDvBADwAQAaAAoKWxJfFwCAAQAAAA==.',
Di='Dianoia:BAAANQAECgQIBgABNQAFFAcIGgAYAH8YAA==.Didamus:BAAANQABCgMIAwAAAA==.Dingleding:BAAANQAECgYICgABNQAECgcIDwAIAAAAAA==.',
Dk='Dkanabiss:BAAANQADCgYIEAAAAA==.Dkinabox:BAAANQADCgYIBwAAAA==.',
Do='Docoo:BAABNQAECn8lAAIVAAkKzSPmFgD2AgAVAAkKzSPmFgD2AgAAAA==.Dogmeat:BAAANQABCgQICAAAAA==.Dominates:BAAANQAECggIDAAAAA==.',
Dr='Dreu:BAAANQADCgUIBwABNQAFFAYIFAAaAEoSAA==.Drewserk:BAABNQAECn8zAAIbAAoKPhSXNwD1AQAbAAoKPhSXNwD1AQAAAA==.Driten:BAABNQAECn80AAIKAAkKfR5rZQCzAgAKAAkKfR5rZQCzAgAAAA==.Drocsid:BAAANQAECggIDgABNQAECgoKOAAHAMIiAA==.Drpiscisphd:BAAANQAECgEIAQABNQAECgoKPAAOAAQjAA==.Drsaltyballz:BAAANQAECgIJAgAAAA==.Drspoon:BAABNQAECn8qAAIVAAoKdBc9KABZAQAVAAoKdBc9KABZAQAAAA==.Drugpala:BAAANQAECgEJAwAAAA==.Drumuss:BAAANQAECgMIBQAAAA==.',
Ds='Dsancho:BAAANQAECgYIDAAAAA==.',
Du='Ducat:BAAANQAECgYICgAAAA==.Dudley:BAAANQAECgMIBAAAAA==.Duffun:BAABNQAECn8gAAIKAAcKqxxgUgC2AQAKAAcKqxxgUgC2AQABNQAECgoKPAAdAOAjAA==.Duffunha:BAABNQAECn88AAIdAAoK4COXAAAhAwAdAAoK4COXAAAhAwAAAA==.',
Dy='Dyre:BAAANQAECgMIBgAAAA==.Dyslexic:BAAANQAECgQICgABNQAFFAUICwAHALMHAA==.Dyspepsia:BAACNQAFFH8LAAIHAAUKswcRGgB9AAAHAAUKswcRGgB9AAA1AAQKfxsAAgcACQo/Fa6FABwCAAcACQo/Fa6FABwCAAAA.',
['Dõ']='Dõngus:BAAANQADCgYIBgABNQAECggIDQAIAAAAAA==.',
Ed='Edelgard:BAAANQAECgEIAgAAAA==.Edie:BAAANQADCggIGwAAAA==.',
Ei='Eirenn:BAAANQAECggICAAAAA==.',
El='Eleaornu:BAABNQAECn8tAAILAAoKsxr8GwBkAgALAAoKsxr8GwBkAgAAAA==.Elimee:BAABNQAECn86AAIKAAoKJyNrHQBiAwAKAAoKJyNrHQBiAwAAAA==.Ellasia:BAAANQABCgMIAwAAAA==.Elvenbane:BAABNQAECn8YAAIDAAYKjAZkSwCYAAADAAYKjAZkSwCYAAAAAA==.',
Em='Emart:BAAANQAECgMIBgAAAA==.',
Er='Erayna:BAABNQAECn8sAAIBAAkKfwzVHQBzAQABAAkKfwzVHQBzAQAAAA==.',
Es='Essence:BAABNQAECn8gAAIKAAoKvRPkNgAXAgAKAAoKvRPkNgAXAgAAAA==.',
Et='Etherious:BAAANQADCgUICwABNQADCggICwAIAAAAAA==.',
Ev='Evelinah:BAAANQAECggICAAAAA==.Evïe:BAAANQAECgEIAgABNQAECgoKOgAKACcjAA==.',
Ex='Explode:BAAANQAECgcIBwABNQAFFAUIBwAXAJ0GAA==.',
Fa='Falconclaw:BAAANQADCggIIQAAAA==.Falkensnoman:BAAANQAECgMIBgAAAA==.Fayedra:BAABNQAECn8hAAIeAAcKCxWcHQCzAQAeAAcKCxWcHQCzAQAAAA==.',
Fe='Feenii:BAABNQAECn81AAIQAAoKfBGaCQAXAgAQAAoKfBGaCQAXAgAAAA==.',
Fi='Figgyandrii:BAAANQAECgQIBAAAAA==.Fizzlelich:BAAANQADCggIKQAAAA==.',
Fo='Foxdeer:BAABNQAECn8bAAITAAcK4AhCjQDVAAATAAcK4AhCjQDVAAAAAA==.Foxxmccloud:BAAANQADCgIJAgABNQAECgoKKwADAKQfAA==.',
Fu='Fungies:BAABNQAECn85AAITAAoKHBTWKwABAgATAAoKHBTWKwABAgAAAA==.Furybest:BAAANQAECgQIBAAAAA==.Furyrage:BAAANQADCgQIBAAAAA==.',
Ga='Gannir:BAAANQAECgEIAQAAAA==.Gano:BAAANQADCgMIAwAAAA==.Gatlokal:BAAANQADCggIAgAAAA==.Gatman:BAAANQADCgYICQAAAA==.',
Gi='Gimiltockel:BAAANQADCgUIBwAAAA==.Giramar:BAABNQAECn8WAAIJAAcK9QuMHgAUAQAJAAcK9QuMHgAUAQAAAA==.',
Go='Gochujang:BAAANQAECgQIBAABNQAFFAIIBgACAF8QAA==.Gojo:BAEANQAECgEIAwAAAA==.Goldeelock:BAAANQADCggIDQAAAA==.Gotchya:BAAANQABCgEIAQAAAA==.Goteem:BAAANQAECgUIBwAAAA==.Gothitelle:BAAANQAECgEIAQAAAA==.',
Gr='Grandad:BAAANQAECgQIBwAAAA==.Grandest:BAAANQADCgQIBAAAAA==.Grantaire:BAAANQADCggIEgAAAA==.Grimmdogg:BAAANQAECgMIAwAAAA==.Grimrox:BAABNQAECn8dAAICAAgK9BEKPQBgAQACAAgK9BEKPQBgAQAAAA==.Grombo:BAAANQAECgQIBgAAAA==.',
Ha='Haanit:BAAANQADCgIIAgAAAA==.Hakela:BAAANQAECgEJAQAAAA==.Hardlyevoker:BAAANQADCgMIAwABNQAECgkJMQALAD8fAA==.',
He='Healingwave:BAAANQADCgYIBgAAAA==.Hearnê:BAAANQADCgIIAQAAAA==.Heavyarm:BAAANQADCgEIAQAAAA==.Heethen:BAAANQAECgUICQAAAA==.Hexbox:BAABNQAECn8bAAMXAAkKohefcAC6AQAXAAgKGRqfcAC6AQACAAcKHg8xhwCSAQAAAA==.',
Hi='Himawari:BAABNQAECn8oAAQfAAgKeRNRDQBiAQAfAAcKeRNRDQBiAQAbAAIKIwdU9QA2AAAgAAEKAABKMwA1AAAAAA==.',
Ho='Hoffmin:BAABNQAECn8yAAMaAAoKORtPDgAEAwAaAAkKYh1PDgAEAwARAAEKGgyckQA3AAAAAA==.Holemeister:BAABNQAECn85AAIHAAoKSyM7MwD/AgAHAAoKSyM7MwD/AgAAAA==.Holyamin:BAAANQAECgMIBgAAAA==.Holymann:BAAANQAECgUICwAAAA==.Holyschnikey:BAABNQAECn8uAAILAAgKnBS5PgCdAQALAAgKnBS5PgCdAQAAAA==.Holyz:BAABNQAECn8jAAILAAgKJyRsDAADAwALAAgKJyRsDAADAwAAAA==.Horgable:BAAANQADCgEIAQAAAA==.Horrorpops:BAAANQAECggICwABNQAECgoKOAAUADMiAA==.',
Hu='Hudfin:BAAANQADCgYIBgAAAA==.Hugginz:BAAANQADCgYIEgAAAA==.Hunzul:BAAANQADCggIDAAAAA==.Hurzal:BAAANQAECgQIBAAAAA==.',
Hy='Hypnototem:BAAANQAECgEIAQAAAA==.',
['Hè']='Hèimdall:BAABNQAECn8fAAIEAAgK8Ah5JADbAAAEAAgK8Ah5JADbAAAAAA==.',
['Hí']='Hílthaen:BAABNQAECn8tAAIZAAkKDh/3LgCsAgAZAAkKDh/3LgCsAgAAAA==.',
Ic='Icehead:BAAANQAECgQIAwAAAA==.Ichigokisu:BAAANQAECggIBAAAAA==.',
Ih='Ihavenobrain:BAAANQABCgIIAgAAAA==.',
Il='Illy:BAABNQAECn8dAAIaAAgKTxCMKgDtAQAaAAgKTxCMKgDtAQAAAA==.',
In='Instantdeath:BAAANQADCgMIAwAAAA==.',
Is='Ishivyounot:BAAANQADCgUICgAAAA==.',
Iv='Ivranda:BAABNQAECn8aAAIXAAcK2xivRACDAQAXAAcK2xivRACDAQAAAA==.',
Ix='Ixio:BAAANQADCgYIBgAAAA==.',
Ja='Jahan:BAACNQAFFH8GAAIZAAIKJB9aGQCyAAAZAAIKJB9aGQCyAAA1AAQKfy8AAxkACgojJLIHAIcDABkACgrOIrIHAIcDACEABwpdHu8EAG0CAAE1AAQKBAgEAAgAAAAA.Jamie:BAABNQAECn8VAAMVAAcKgSSLKQB2AgAVAAYKgSSLKQB2AgAFAAEKAADP4AAzAAABNQAFFAcIDgATAAgjAA==.Jarek:BAAANQABCgQIBAAAAA==.',
Je='Jegra:BAABNQAECn8sAAIiAAoKGh38CQBjAgAiAAoKGh38CQBjAgAAAA==.Jerith:BAABNQAECn8sAAMOAAkKUwxxDQCoAQAOAAkKUwxxDQCoAQANAAYKPwWqNAAVAQAAAA==.Jerryy:BAEANQADCgEIAgABNQAECgEIAwAIAAAAAA==.Jessilyn:BAAANQADCggIFQAAAA==.',
Ji='Jigari:BAAANQADCgcIDgAAAA==.Jinxed:BAAANQAECgMIAwAAAA==.',
Jo='Jord:BAAANQAECgQIBAAAAA==.',
Ju='Jubellina:BAABNQAECn8yAAIWAAoKRg9DHAC/AQAWAAoKRg9DHAC/AQAAAA==.Jubîlee:BAAANQABCgIIAgAAAA==.',
['Jà']='Jàzz:BAAANQADCgcIHwAAAA==.',
Ka='Kaelora:BAAANQADCgYICQAAAA==.Kaerei:BAAANQADCgQIBAAAAA==.Kaleb:BAECNQAFFH8NAAIRAAUKghZFDQA7AQARAAUKghZFDQA7AQA1AAQKfz4AAhEACgoPJOADACsDABEACgoPJOADACsDAAAA.Kalferno:BAAANQAECgUIBwAAAA==.Kalirkaz:BAAANQAECggIDgABNQAECgoKLAAXAPEdAA==.Kayotica:BAAANQAECgMIAwAAAA==.',
Ke='Keensmite:BAAANQAECgEIAQAAAA==.Kendall:BAAANQAECgQIBAABNQAECgkJFgAGAOsLAA==.',
Kh='Khallock:BAAANQAECgUIEAAAAA==.',
Ki='Kiemen:BAABNQAECn8WAAMGAAkK6wtFTACHAQAGAAkK6wtFTACHAQAFAAYK7ApShAAOAQAAAA==.Killko:BAABNQAECn8bAAMGAAgK6RBuRACwAQAGAAgK6RBuRACwAQAFAAIKpQrVyABaAAAAAA==.Kirisen:BAAANQAECgIIAwAAAA==.',
Kn='Knardan:BAABNQAECn8rAAIUAAkKEx8tOQD8AQAUAAkKEx8tOQD8AQAAAA==.',
Ko='Kotanx:BAAANQADCggIEQAAAA==.',
Kr='Kragsloor:BAAANQADCggICwAAAA==.Krickette:BAAANQAECgEIAQABNQAECgkJLAABAH8MAA==.',
Ku='Kuraki:BAABNQAECn8hAAIiAAcKUQt0IQAaAQAiAAcKUQt0IQAaAQAAAA==.',
Ky='Kyriea:BAAANQADCgYIBgAAAA==.',
La='Ladrar:BAAANQAECgEIAQAAAA==.Lanadiel:BAABNQAECn80AAIEAAoKPSHpBQCaAgAEAAoKPSHpBQCaAgAAAA==.Lasalghoul:BAAANQAECggIDgAAAA==.Lassyn:BAAANQAECggICAABNQAECggIDgAIAAAAAA==.',
Le='Legend:BAABNQAECn8VAAIVAAgK2BUzUgCsAQAVAAgK2BUzUgCsAQAAAA==.Len:BAABNQAECn8rAAMXAAkKeBLCWQADAgAXAAkKeBLCWQADAgACAAUKbwx8yAABAQAAAA==.Leoñidas:BAAANQAECgYIDgAAAA==.',
Li='Lian:BAAANQAECgQIBQAAAA==.Lianda:BAAANQAECggICAAAAA==.Lianse:BAAANQADCgYICwAAAA==.Liliara:BAABNQAECn8xAAIUAAoKnxbKJwBCAgAUAAoKnxbKJwBCAgAAAA==.Lillyirl:BAAANQADCgcIBwAAAA==.Lillymae:BAABNQAECn8aAAIaAAkKGSLXDgD+AgAaAAkKGSLXDgD+AgAAAA==.Lillyslight:BAAANQADCgUIBQAAAA==.Lillytae:BAAANQADCgYIBgAAAA==.Lillyvani:BAAANQAECgQIBAAAAA==.Lilmoo:BAABNQAECn8UAAIUAAYKggXDxwCiAAAUAAYKggXDxwCiAAAAAA==.Lilpump:BAAANQAECgQICQABNQAECgoKKgAVAHQXAA==.Lindalinda:BAAANQADCgEIAQAAAA==.Linkhunter:BAAANQAECgUIDQABNQAECgoKNAAhAC0hAA==.Linkmônk:BAAANQADCgcICgABNQAECgoKNAAhAC0hAA==.',
Lo='Lodise:BAABNQAECn8tAAISAAgKNBJCBQCMAQASAAgKNBJCBQCMAQAAAA==.Lorzz:BAABNQAECn8vAAIZAAoK+hx7JADaAgAZAAoK+hx7JADaAgAAAA==.Loveydovey:BAAANQADCgIIAgAAAA==.',
Lu='Lucrio:BAABNQAECn80AAIFAAkKhhWVEwDuAQAFAAkKhhWVEwDuAQAAAA==.Ludlow:BAAANQADCgMIAwABNQAECgoKLAANACkTAA==.Lunalai:BAAANQAECgQIBAAAAA==.Lurim:BAABNQAECn8sAAIeAAoKhB8PBgAzAwAeAAoKhB8PBgAzAwAAAA==.Lushy:BAABNQAECn82AAINAAoKLBRXJQD6AQANAAoKLBRXJQD6AQAAAA==.',
Ly='Lylindara:BAABNQAECn8ZAAIXAAgKJgjDkwBWAQAXAAgKJgjDkwBWAQAAAA==.Lylinette:BAAANQADCggIDwAAAA==.',
['Ló']='Lókï:BAAANQADCgEIAQAAAA==.',
Ma='Madgorilla:BAAANQADCgUIBQAAAA==.Mageofdeath:BAABNQAECn8tAAMMAAkKSBDfBwCoAQAMAAgKAxDfBwCoAQAKAAcKCAqvKQFGAQABNQADCgMIAwAIAAAAAA==.Mageskin:BAAANQAECgMIBwAAAA==.Maladaptive:BAAANQADCgYIDwAAAA==.Manerva:BAAANQADCggIHwAAAA==.Mastorcheef:BAAANQADCgQIBAAAAA==.Maurin:BAAANQAECggICwAAAA==.Maximumhonk:BAABNQAECn8sAAIXAAgKfxl3UAAkAgAXAAgKfxl3UAAkAgAAAA==.Maxonoa:BAAANQADCggJFwAAAA==.Maxximos:BAAANQADCgYICAAAAA==.',
Me='Mekkadaddy:BAABNQAECn8cAAIUAAkKWhNRdgBIAQAUAAkKWhNRdgBIAQAAAA==.Mellow:BAAANQAECgMIAwAAAA==.Mendelia:BAABNQAECn8kAAIEAAcKVBbCJgCoAQAEAAcKVBbCJgCoAQAAAA==.Mercus:BAABNQAECn8hAAMNAAgKyA9aIgC4AQANAAcKVg9aIgC4AQAOAAcKvA43RwCoAQAAAA==.Merllinna:BAAANQABCgIIAQAAAA==.Mervenious:BAABNQAECn8hAAMbAAkKOgl4cQA2AQAbAAkKOgl4cQA2AQAfAAIKrglbPABUAAAAAA==.',
Mi='Mindplague:BAABNQAECn8lAAIJAAYKqRxoJQAEAgAJAAYKqRxoJQAEAgAAAA==.Minipincin:BAAANQAECgQIBQAAAA==.Minmzey:BAAANQAECgQIBgAAAA==.Miroslava:BAAANQAECgUICQAAAA==.Missfire:BAAANQAECgcIEgABNQAECgoKIQABAJYTAA==.',
Mk='Mkaye:BAAANQAECgIIBAAAAA==.',
Mo='Moggle:BAABNQAECn8YAAIKAAYKiAeAzAC1AAAKAAYKiAeAzAC1AAAAAA==.Mondazi:BAABNQAECn85AAMCAAoK2hp+OQCQAgACAAkKQhl+OQCQAgAXAAoK+A7NaADSAQAAAA==.Moonlilly:BAAANQADCgIIAgAAAA==.Morfy:BAAANQABCggIBgAAAA==.Morgzim:BAAANQADCgYJBwAAAA==.Moustaccio:BAAANQAECgEIAgAAAA==.Mozarta:BAAANQABCggIDQAAAA==.',
Ms='Msmanalow:BAAANQAECgEIAQABNQAECgoKIQABAJYTAA==.',
My='Mycen:BAABNQAECn8XAAITAAgKbgw7kQC7AQATAAgKbgw7kQC7AQAAAA==.Myeyesburn:BAAANQAECgMJBAAAAA==.',
['Má']='Málaketh:BAAANQAECgQICQAAAA==.',
Na='Nardena:BAAANQAECgIIAQAAAA==.Narz:BAABNQAECn86AAIUAAoKoQ7oWQCPAQAUAAoKoQ7oWQCPAQAAAA==.Naughtypine:BAAANQADCgYIBgAAAA==.Naylz:BAAANQAECggIAQAAAA==.',
Ne='Necronomikon:BAABNQAECn8ZAAIKAAcK0Q3q9ACiAQAKAAcK0Q3q9ACiAQAAAA==.Nerhzul:BAAANQADCgUIBQAAAA==.Neromoo:BAAANQAECgUIDQABNQAECgoKHgAjALIQAA==.Neruphuyt:BAABNQAECn8YAAIDAAgKAgnkXABdAQADAAgKAgnkXABdAQAAAA==.',
Ni='Niath:BAAANQAECgUIDgAAAA==.Nightheal:BAAANQABCgQIBQABNQAECgkJJQAVAM0jAA==.Nightsniper:BAAANQAECgEIAQABNQAECgkJJQAVAM0jAA==.',
No='Notdinor:BAAANQADCgIIAgAAAA==.Notlilly:BAABNQAECn8oAAIfAAkKoBEbDgBVAQAfAAkKoBEbDgBVAQAAAA==.Notpillows:BAAANQAECgEIAQAAAA==.',
Ny='Nyxelle:BAAANQAECgIIAwAAAA==.',
['Nä']='Närz:BAAANQADCggIBQAAAA==.',
['Nò']='Nòvà:BAAANQAECgQICgAAAA==.',
Oi='Oilfu:BAAANQADCgUIBQABNQAECgoKNgANACwUAA==.',
Ok='Okioni:BAAANQAECgUIBQAAAA==.',
Ol='Olgon:BAACNQAFFH8GAAIUAAIKWQo0GQCLAAAUAAIKWQo0GQCLAAA1AAQKfzgAAhQACgqMEaRWAG4CABQACgqMEaRWAG4CAAAA.',
Op='Oprhawinfury:BAABNQAECn8jAAIFAAkKkQv/MQD+AAAFAAkKkQv/MQD+AAAAAA==.',
Or='Orgodemir:BAABNQAECn8hAAIZAAcKByWTIADtAgAZAAcKByWTIADtAgAAAA==.Orhamin:BAAANQADCgYIDwAAAA==.',
Os='Oshani:BAAANQAECggIDQAAAA==.',
Ou='Outlaw:BAAANQADCgcIBwAAAA==.',
Pa='Pacolyte:BAAANQAECgMIBAAAAA==.Paigor:BAAANQABCgIIAgAAAA==.Palathene:BAABNQAECn8gAAMHAAoKRSD9FgDFAgAHAAoKRSD9FgDFAgAEAAQKnR0wNABCAQAAAA==.Pallystorm:BAAANQAECgYICAAAAA==.Palmike:BAAANQADCgYIBgAAAA==.Pandemonia:BAABNQAECn80AAITAAkKTRG4dQABAgATAAkKTRG4dQABAgAAAA==.Parsie:BAAANQAECgQIBgAAAA==.Pathibas:BAAANQADCggIDQABNQAECgkJNwAgAFEgAA==.Pattycakes:BAABNQAECn8pAAIFAAkKRQ75HACMAQAFAAkKRQ75HACMAQAAAA==.',
Pe='Pericø:BAAANQADCgQIBAAAAA==.',
Ph='Pherocious:BAAANQAECgQIBQAAAA==.',
Pi='Pinktuesday:BAAANQADCggICAAAAA==.Pixeleen:BAACNQAFFH8FAAIUAAQKrATjFQANAQAUAAQKrATjFQANAQA1AAQKfzsAAxQACgpeIrMZAIwCABQACgpeIrMZAIwCACQABQrfCvJMAP4AAAAA.',
Pl='Plexy:BAABNQAECn8gAAMZAAkKYSDbIQDnAgAZAAkKuh/bIQDnAgAhAAcK8hlaCADhAQAAAA==.',
Po='Pokitz:BAABNQAECn8cAAIHAAcKdAWL0ADCAAAHAAcKdAWL0ADCAAAAAA==.',
Pr='Primordinor:BAABNQAECn8vAAICAAgKfxtWNACFAQACAAgKfxtWNACFAQAAAA==.Probnotalive:BAABNQAECn80AAIUAAoKpB0pFwA+AwAUAAoKpB0pFwA+AwAAAA==.Probnoturmom:BAABNQAECn8uAAIZAAkKVR5ZLQCzAgAZAAkKVR5ZLQCzAgAAAA==.',
Qu='Quacko:BAAANQAECgYIBAABNQAECgoKLAAeAIQfAA==.Quietus:BAAANQADCgQIBAAAAA==.',
Ra='Raevyn:BAAANQAECgIIAQAAAA==.Raikai:BAAANQAECgEIAQABNQAECgoKLQALALMaAA==.Rakan:BAABNQAECn86AAMfAAoKbR6FAwCiAgAfAAoKbR6FAwCiAgAbAAUKeQ2M6AAUAQAAAA==.Rallick:BAACNQAFFH8GAAILAAIKhQbLFgB3AAALAAIKhQbLFgB3AAA1AAQKfyoAAgsACgpdFmY3AMABAAsACgpdFmY3AMABAAAA.Ranì:BAABNQAECn82AAMfAAgKohifCgCZAQAfAAgKohifCgCZAQAgAAEKfAd4IwAxAAAAAA==.Rathger:BAAANQADCgUICAAAAA==.Ratmilk:BAAANQAECgcIDAAAAA==.Razkhan:BAAANQADCgcIDQAAAA==.',
Rd='Rdk:BAAANQAECgMIBAAAAA==.',
Re='Redek:BAAANQADCgcICgAAAA==.Reft:BAAANQABCgEIAQAAAA==.Reighna:BAAANQADCggIDQAAAA==.Rendwee:BAABNQAECn86AAIlAAoKFh+lAwCUAgAlAAoKFh+lAwCUAgAAAA==.Reps:BAAANQAECggICgAAAA==.Retiredaggro:BAAANQAECgUIDgAAAA==.Retiredghoul:BAAANQADCgUIBQAAAA==.Retiredlight:BAAANQADCgEIAQAAAA==.Reuel:BAAANQADCgYIBgAAAA==.Rewolf:BAAANQAECgUIEwAAAA==.',
Rh='Rhynar:BAAANQAECggICAAAAA==.',
Ri='Ricflairion:BAABNQAECn8uAAImAAgKtAvlDgBUAQAmAAgKtAvlDgBUAQAAAA==.Rill:BAAANQADCggICwAAAA==.',
Ro='Rodcet:BAABNQAECn84AAIHAAoKwiIjDQAMAwAHAAoKwiIjDQAMAwAAAA==.Roflbubble:BAABNQAECn8tAAMZAAkKshRYYAAAAgAZAAkKshRYYAAAAgAJAAUKdAWqVQC2AAAAAA==.Rognan:BAAANQAECgEIAQAAAA==.Roku:BAAANQAECgcICAAAAA==.Ronkin:BAAANQADCggIHQAAAA==.Rookgue:BAABNQAECn81AAIOAAgKDxHhEgBnAQAOAAgKDxHhEgBnAQAAAA==.Rookoker:BAAANQAECgUIEgAAAA==.Rorygazer:BAABNQAECn8YAAIfAAYKDCIZEAAnAgAfAAYKDCIZEAAnAgAAAA==.Rosmerta:BAAANQADCgYIBwAAAA==.Rossdair:BAAANQAECgUIDAABNQAECgcICwAIAAAAAA==.Rossperot:BAABNQAECn8bAAIFAAcKLh10SgDsAQAFAAcKLh10SgDsAQAAAA==.',
Ry='Ryk:BAAANQAECggIDQAAAA==.',
Sa='Saarin:BAAANQAECgMIAwAAAA==.Saelara:BAAANQAECgQIBQAAAA==.Sairal:BAAANQAECggIEAAAAA==.Saltytuesday:BAAANQADCgYICQAAAA==.Samgee:BAACNQAFFH8VAAIHAAUK4RorCgD2AAAHAAUK4RorCgD2AAA1AAQKfz0AAgcACgrGHwUlAHECAAcACgrGHwUlAHECAAAA.Sanguathene:BAEANQAECgMIAgABNQAECgoKIAAHAEUgAA==.Sawlty:BAABNQAECn8hAAIkAAkK6A0YMADNAQAkAAkK6A0YMADNAQAAAA==.Saynar:BAABNQAECn8wAAMaAAoK4SGiBADhAgAaAAoK4SGiBADhAgAcAAIKRR1VJgCHAAAAAA==.',
Sc='Scattered:BAABNQAECn8jAAMYAAkKeQ0MJwA+AQAYAAYKqQsMJwA+AQATAAYKVQwinAC4AAAAAA==.Schecter:BAABNQAECn8YAAMXAAcKJyOUMQCaAgAXAAcKJyOUMQCaAgACAAEKCxj0KQE/AAAAAA==.Scintila:BAAANQADCgQIBAABNQAECgkJNAATAE0RAA==.Scooti:BAAANQADCggIEAABNQAECgYIDAAIAAAAAA==.',
Se='Seba:BAACNQAFFH8GAAIKAAIKoAqAKQCLAAAKAAIKoAqAKQCLAAA1AAQKf0YAAgoACgpQHc9XANACAAoACgpQHc9XANACAAAA.Sehren:BAAANQADCgcIBgAAAA==.Sehtrak:BAAANQADCggICAAAAA==.Selesne:BAABNQAECn8hAAIPAAcKfAp3BAALAQAPAAcKfAp3BAALAQAAAA==.Seniandrays:BAAANQADCgQIBAAAAA==.Serannia:BAAANQADCgIIAgAAAA==.Seraphicktwo:BAABNQAECn8ZAAMJAAgKRgzpPQA9AQAJAAgKRgzpPQA9AQAZAAEKTgYI/gAvAAAAAA==.',
Sh='Shadowlune:BAAANQABCgIIAgAAAA==.Shadowtrance:BAAANQADCgcIEAABNQAECgkJLwAEAJ0ZAA==.Shaggmz:BAABNQAECn8YAAIgAAYKFg/wFwAgAQAgAAYKFg/wFwAgAQAAAA==.Shawnkin:BAAANQADCgIIAgAAAA==.Shelyn:BAAANQAECgIIBAAAAA==.Shinma:BAABNQAECn8YAAIEAAYKwAVGQwDmAAAEAAYKwAVGQwDmAAAAAA==.Shootermcgee:BAAANQAECgIIAgAAAA==.Showtootsies:BAAANQADCgUJBQAAAA==.Shrubbery:BAAANQAECgQIBwAAAA==.Shymary:BAAANQAECgUIEgAAAA==.',
Si='Siete:BAAANQADCgYJBwAAAA==.Silëx:BAABNQAECn8fAAIMAAcKGBesDgC/AQAMAAcKGBesDgC/AQAAAA==.Sindiz:BAAANQAECgUIDQAAAA==.Siouxiesioux:BAAANQAECgQIBAAAAA==.',
Sk='Skadie:BAAANQAECgIIAgAAAA==.Skoot:BAAANQAECgYIDAAAAA==.',
Sl='Slimjimz:BAAANQADCgUIBQAAAA==.Slugondeez:BAABNQAECn8xAAMLAAkKPx9NJwDMAgALAAkKPx9NJwDMAgAEAAIKUyMyTwCqAAAAAA==.',
Sm='Smitefist:BAAANQAECgEIAQABNQAECggIDQAIAAAAAA==.',
Sn='Snkyturtle:BAABNQAECn81AAIUAAkKdQ2ygQAJAgAUAAkKdQ2ygQAJAgAAAA==.Snoopdogydog:BAAANQABCgQIAwAAAA==.Snuzzle:BAABNQAECn8qAAIeAAkKnhYYFAAjAgAeAAkKnhYYFAAjAgAAAA==.',
So='Sourmash:BAAANQAECgQIBAAAAA==.',
Sp='Spaghet:BAABNQAECn8XAAICAAkK5wxrggCfAQACAAkK5wxrggCfAQAAAA==.Spillthetea:BAAANQADCggICQABNQAECgYIGAAVAB8DAA==.Spittoon:BAAANQADCgEJAQABNQADCggIGgAIAAAAAA==.Sploot:BAABNQAECn8dAAITAAoKeRuMQQCNAgATAAoKeRuMQQCNAgAAAA==.',
Sr='Srasjet:BAAANQAECgMIBgAAAA==.',
Ss='Ssarmandok:BAABNQAECn8VAAIHAAkKsxXAfwBRAQAHAAkKsxXAfwBRAQAAAA==.',
St='Stabytha:BAAANQAECgYIDAAAAA==.Stark:BAAANQABCgQIBAAAAA==.Starlight:BAABNQAECn8cAAMBAAoKxR0hDwDjAgABAAoKxR0hDwDjAgADAAYKThNKcgABAQAAAA==.Stealthed:BAAANQAECgQIDQAAAA==.Stender:BAAANQADCgIIAgABNQAFFAIICQARAH8eAA==.Stonegoddess:BAAANQADCgQIBAAAAA==.Stormcall:BAAANQAECgUIDAAAAA==.Stratusfied:BAAANQADCgIIAgAAAA==.Strongsad:BAAANQADCgcIBwAAAA==.',
Sw='Swiss:BAABNQAECn8aAAICAAcKHw90gACjAQACAAcKHw90gACjAQAAAA==.',
Sy='Syldra:BAAANQABCgIIAgAAAA==.',
['Sá']='Sáëgárón:BAAANQAECgMIBAAAAA==.',
Ta='Taliden:BAAANQAECgMIBwAAAA==.Tankinstine:BAAANQADCgYIBwAAAA==.Taraylda:BAABNQAECn8YAAMJAAYKcxpgKQDdAQAJAAYKcxpgKQDdAQAZAAEK2yEZ8gBOAAAAAA==.Tarz:BAAANQAECgYICwAAAA==.Tazzwolfsong:BAAANQADCgEIAQAAAA==.',
Te='Tecdor:BAAANQADCgYJBgAAAA==.Teronfiggy:BAAANQAECgcIEQAAAA==.',
Tf='Tfirs:BAAANQAECgQJBwAAAA==.',
Th='Thehealczar:BAAANQAECgcIDwABNQAECgkJJQAVAM0jAA==.Theokoles:BAAANQAECggIDQAAAA==.Thesenate:BAAANQADCggIDwABNQAECgoKNQAQAHwRAA==.Thickblòód:BAAANQAECgIIAgAAAA==.Thordurin:BAAANQAECgYIBgAAAA==.Thorly:BAAANQADCgYIDQAAAA==.Thrazi:BAAANQAECgIIBAAAAA==.',
Ti='Tiadalma:BAAANQADCgEIAQAAAA==.Tinn:BAAANQADCggIEAAAAA==.',
To='Toospookie:BAAANQADCgYIDgAAAA==.Totem:BAAANQAECgQIBgAAAA==.',
Tr='Tramplip:BAABNQAECn8XAAIYAAYKbArGDgCoAAAYAAYKbArGDgCoAAAAAA==.Treecloud:BAABNQAECn8uAAMeAAoKNxxCCAD6AgAeAAkKyh1CCAD6AgADAAEKMxGcZgBAAAAAAA==.Treferimore:BAAANQAECgUIEAAAAA==.Trevian:BAABNQAECn8hAAIHAAcKyQ4fjQA3AQAHAAcKyQ4fjQA3AQAAAA==.',
Tu='Tuluxxi:BAABNQAECn83AAMXAAoK4yLlGgAEAwAXAAoK4yLlGgAEAwACAAgK4g49dADEAQAAAA==.Tutter:BAAANQAECgUIBwAAAA==.',
Tw='Twopumpchump:BAABNQAECn8kAAInAAgKzxCqCQA+AQAnAAgKzxCqCQA+AQAAAA==.',
Tz='Tzxdh:BAAANQAECgIIAgABNQAECggIFwAEADYVAA==.Tzxdruid:BAAANQAECgIIAgABNQAECggIFwAEADYVAA==.',
Ug='Uglymancer:BAABNQAECn8kAAITAAkKlxbSLgD0AQATAAkKlxbSLgD0AQAAAA==.',
Uj='Ujimas:BAABNQAECn8eAAICAAYKcRaARQA/AQACAAYKcRaARQA/AQAAAA==.',
Ut='Uthodne:BAAANQAECgEIAQABNQAECgoKLAANACkTAA==.',
Va='Vampireshade:BAABNQAECn8tAAMOAAkKQQvoHQASAQAOAAkKQQvoHQASAQAPAAYK/gMzEgDlAAAAAA==.Vampirevoid:BAAANQADCgUIBQAAAA==.Vampírella:BAAANQADCgIIAgAAAA==.Vanililly:BAABNQAECn8rAAIVAAkK8A1UJQBsAQAVAAkK8A1UJQBsAQAAAA==.Vanimao:BAAANQAECgEIAQAAAA==.Varan:BAAANQAECgUIBwAAAA==.',
Vb='Vbull:BAAANQAECgEIAQAAAA==.',
Ve='Velissari:BAAANQAECgUIDQAAAA==.Venatra:BAAANQADCgYICAAAAA==.Veritus:BAABNQAECn8rAAIRAAkKfB6UFAAOAgARAAkKfB6UFAAOAgAAAA==.',
Vi='Vindict:BAAANQAECgMIBgAAAA==.Violette:BAABNQAECn8fAAIUAAcKIg3sjAAYAQAUAAcKIg3sjAAYAQAAAA==.Vion:BAAANQABCgQIBAAAAA==.',
Vo='Voidlink:BAABNQAECn80AAIhAAoKLSGJAABJAwAhAAoKLSGJAABJAwAAAA==.Voidstriker:BAAANQAECgEIAQAAAA==.',
Wa='Wackyrellek:BAABNQAECn8bAAMOAAoK8RxRCgDgAQAOAAkK8RxRCgDgAQANAAIKVQIZSgBpAAAAAA==.Wakancer:BAABNQAECn8VAAISAAUKQw8KEgAqAQASAAUKQw8KEgAqAQAAAA==.Wakarisma:BAAANQAECgEIAQAAAA==.Wakataclysm:BAAANQAECgQICwAAAA==.Walnut:BAAANQAECgUIBwABNQAFFAIIBgACAF8QAA==.Warchylde:BAAANQADCgQIBgAAAA==.Warolderoy:BAABNQAECn83AAMgAAkKUSAHBQDbAgAgAAkK6x8HBQDbAgAfAAYKkBqAFwC0AQAAAA==.',
We='Weedshaman:BAAANQADCgcJBwAAAA==.Weil:BAAANQAECgQICAAAAA==.',
Wo='Woker:BAAANQAECgYICQABNQAECgoKNQAQAHwRAA==.Woogie:BAAANQAECgQIBwAAAA==.Worthy:BAAANQAECgMIAwAAAA==.',
Wu='Wummie:BAAANQAECgMIAwABNQAECgkJKAATAD0eAA==.',
['Wò']='Wòógie:BAAANQADCgYIBgABNQAECgQIBwAIAAAAAA==.',
Xa='Xader:BAAANQADCggIEAAAAA==.Xanneral:BAEANQAECgUIBgABNQAECgkJKwAGABcZAA==.',
Xe='Xenna:BAAANQAECgUIDgABNQAECgkJJQAHAGwSAA==.Xeq:BAAANQAECgMIAwAAAA==.',
Ye='Yeoman:BAABNQAECn8YAAIgAAcKFhIiEwBvAQAgAAcKFhIiEwBvAQAAAA==.Yewko:BAAANQAECgYIEwAAAA==.',
Yg='Yggdralith:BAAANQAECgcIHAAAAQ==.',
Yi='Yibble:BAAANQAECgUIBQABNQAFFAQICgAbAJgcAA==.',
Yo='Yobagoya:BAAANQAECgEIAQAAAA==.',
Yu='Yunohealme:BAABNQAECn8aAAIGAAcK/Rn6MwAOAgAGAAcK/Rn6MwAOAgAAAA==.Yunosmall:BAAANQADCgMIAwAAAA==.Yunosmart:BAAANQADCgMIBAAAAA==.',
Yz='Yzerman:BAAANQAECgIIAgABNQAECgkJFgAGAOsLAA==.',
['Yö']='Yör:BAAANQADCgEIAQAAAA==.',
Za='Zaen:BAACNQAFFH8GAAITAAIKkA8mGQCWAAATAAIKkA8mGQCWAAA1AAQKfzgAAxMACgrwHJ4kAPICABMACgrwHJ4kAPICABgAAwrUGFJAAMEAAAAA.Zandre:BAABNQAECn8lAAIfAAkK2BemEwDrAQAfAAkK2BemEwDrAQAAAA==.Zarkir:BAACNQAFFH8GAAIVAAIKVyL1DADFAAAVAAIKVyL1DADFAAA1AAQKfy8AAxUACgrvIhINAEgDABUACgrvIhINAEgDAAYAAQrACbWIADcAAAAA.',
Ze='Zelily:BAABNQAECn8wAAIUAAkK8Q2vhAACAgAUAAkK8Q2vhAACAgAAAA==.Zenarri:BAAANQADCgYICgAAAA==.',
Zh='Zharvakko:BAABNQAECn8sAAMXAAoKxhX7OQCyAQAXAAoKxhX7OQCyAQACAAcKrhBlhACaAQABNQAECgoKLAAXAPEdAA==.Zhiana:BAABNQAECn8cAAMMAAgKQxFHDgDHAQAKAAgKOwxj3gDLAQAMAAgK7A1HDgDHAQAAAA==.',
Zo='Zornov:BAAANQADCgcIBwABNQAECgoKLAAeAIQfAA==.',
Zu='Zugzok:BAAANQAECgMIAwAAAA==.Zulrich:BAAANQAECgYICwAAAA==.',
Zv='Zvirae:BAAANQAECgUIBQAAAA==.Zvirax:BAAANQADCggIIgABNQAECgUIBQAIAAAAAA==.',
['Ás']='Ástrid:BAAANQAECgEIAQAAAA==.',
['Ëu']='Ëuni:BAAANQADCgQIBAAAAA==.',
['Ìs']='Ìsaac:BAAANQAECgYJEgAAAA==.',
['Ðo']='Ðolm:BAAANQAECgMIBAAAAA==.',
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
