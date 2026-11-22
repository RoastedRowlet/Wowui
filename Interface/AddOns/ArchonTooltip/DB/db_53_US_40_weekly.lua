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

local lookup = {'Hunter-BeastMastery','Druid-Restoration','Shaman-Elemental','Druid-Balance','Mage-Arcane','Paladin-Protection','Paladin-Retribution','DeathKnight-Unholy','DeathKnight-Frost','Unknown-Unknown','Warlock-Demonology','Priest-Shadow','Paladin-Holy','Mage-Frost','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Shaman-Enhancement','DemonHunter-Havoc','Warlock-Affliction','Evoker-Preservation','Druid-Guardian','DeathKnight-Blood','Priest-Holy','Monk-Mistweaver','Shaman-Restoration','Warlock-Destruction','Warrior-Arms','DemonHunter-Devourer','Druid-Feral','DemonHunter-Vengeance','Hunter-Survival','Warrior-Protection','Warrior-Fury','Priest-Discipline','Monk-Windwalker','Hunter-Marksmanship','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster',}
local provider = {region='US',realm='Bloodhoof',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Aberforthd:BAABNQAECn8YAAIBAAgKLgs6ogBvAQABAAgKLgs6ogBvAQAAAA==.',
Ac='Aceforlife:BAAANQADCggIEAABNQAECgoKYAACAJcUAA==.Acorn:BAACNQAFFH8GAAIDAAIKXxBTHgCKAAADAAIKXxBTHgCKAAA1AAQKfy0AAgMACgqzHtYfAA0DAAMACgqzHtYfAA0DAAAA.',
Ad='Aditu:BAABNQAECn8pAAMCAAoKbxSmNQBuAQACAAgKNBKmNQBuAQAEAAkKQgyWOwBBAQAAAA==.',
Ae='Aessone:BAAANQAECgUIBQABNQAFFAIIBwAFAKAKAA==.Aetheris:BAABNQAECn8ZAAMGAAgKfxXYLAB2AQAGAAgKNhXYLAB2AQAHAAEK9iCkaQFfAAAAAA==.',
Ag='Agasonex:BAAANQADCgUIBAAAAA==.',
Ah='Ahziz:BAABNQAECn8ZAAMIAAYKERCbdwA7AQAIAAYKERCbdwA7AQAJAAYKpwdUfwCxAAAAAA==.',
Ai='Airent:BAABNQAECn8jAAMCAAcKhhF9NwA8AQACAAYK5xB9NwA8AQAEAAcKLQ7BRwAEAQAAAA==.',
Aj='Aja:BAAANQAECggICAABNQAFFAUIDwABAG8UAA==.',
Al='Alaestel:BAABNQAECn9CAAIHAAoKRQ1knACUAQAHAAoKRQ1knACUAQAAAA==.Aletheia:BAAANQAECgQIBAAAAA==.Alt:BAAANQAECgIIBAAAAA==.',
An='Ancane:BAAANQADCggICAAAAA==.Andramealoch:BAAANQADCgEIAQAAAA==.Angina:BAAANQADCgUIBwAAAA==.Angrywoogie:BAAANQADCgEIAQABNQAECgQIBwAKAAAAAA==.Annarcis:BAABNQAECn8jAAILAAcKPwtYnwAZAQALAAcKPwtYnwAZAQAAAA==.Antiman:BAAANQAECgQICAAAAA==.Anäster:BAABNQAECn8hAAIMAAgKdhblJAAJAgAMAAgKdhblJAAJAgAAAA==.',
Ao='Aoiris:BAAANQADCggIEAAAAA==.',
Ap='Aplcyder:BAABNQAECn8zAAMCAAoK5wxSKwCVAQACAAoK5wxSKwCVAQAEAAQKFwSscgBpAAAAAA==.Apocryphea:BAAANQAECggIEAAAAA==.',
Ar='Arabloom:BAAANQAECgUIBQAAAA==.Arachnid:BAABNQAECn8wAAIFAAkKTR3kLgCFAgAFAAkKTR3kLgCFAgAAAA==.Aradalon:BAABNQAECn8oAAINAAkKmyFNDwBRAwANAAkKmyFNDwBRAwAAAA==.Aratyn:BAABNQAECn8jAAIOAAgKWxRpDQDaAQAOAAgKWxRpDQDaAQAAAA==.Arianabelia:BAAANQADCgEIAQAAAA==.',
As='Asanot:BAAANQADCgQIBAAAAA==.Astranacht:BAABNQAECn87AAIEAAoKjw6dKwClAQAEAAoKjw6dKwClAQAAAA==.',
At='Atheneimeris:BAEANQAECgUIBgAAAA==.',
Au='Auntjemimma:BAABNQAECn8qAAIHAAkKQBMiiQAUAgAHAAkKQBMiiQAUAgAAAA==.Auriandra:BAAANQAECgQICAAAAA==.',
Ax='Axa:BAAANQADCggIHAAAAA==.',
Ay='Ayroonoo:BAAANQADCgQIBQAAAA==.',
Ba='Babyshoes:BAAANQAECgYIEwAAAA==.Backhawk:BAAANQAECgQIBAAAAA==.Backsurgery:BAABNQAECn8jAAQPAAkKNSCbEgDjAgAPAAkKNSCbEgDjAgAQAAIKhRaUiACQAAARAAIKEhKMFgB/AAABNQAFFAYIGAASAJ0jAA==.Baerrn:BAABNQAECn8ZAAITAAgKeAP4aQDRAAATAAgKeAP4aQDRAAAAAA==.Baricia:BAABNQAECn8rAAIFAAoKpQs93QDNAQAFAAoKpQs93QDNAQAAAA==.Barrin:BAABNQAECn8uAAMUAAoKcRfmBwAYAgAUAAoKcRfmBwAYAgALAAIKSwCkQQE0AAAAAA==.Bawnchu:BAAANQADCggIGAAAAA==.',
Be='Beardad:BAAANQADCgcICQAAAA==.Bearded:BAABNQAECn8dAAIVAAoKYw9DEAADAgAVAAoKYw9DEAADAgAAAA==.Bearonica:BAEBNQAECn8XAAMCAAoKNRmODQDwAgACAAoKNRmODQDwAgAWAAEKIAIEiQAHAAABNQAFFAQICgANAKwZAA==.Beastmaster:BAACNQAFFH8HAAIBAAMKJxEHFADtAAABAAMKJxEHFADtAAA1AAQKfzQAAgEACgo+H8cyANQCAAEACgo+H8cyANQCAAAA.Beefcakell:BAAANQADCgMIBAAAAA==.Belthar:BAAANQAECgUIBgAAAA==.Bentlymage:BAACNQAFFH8HAAIFAAIKohcINwCXAAAFAAIKohcINwCXAAA1AAQKfzoAAgUACgqqIMUuAIUCAAUACgqqIMUuAIUCAAAA.',
Bi='Bissafiyah:BAACNQAFFH8dAAISAAgKjhw3AADKAgASAAgKjhw3AADKAgA1AAQKf0cAAhIACgptJvIAAGwDABIACgptJvIAAGwDAAAA.Bittertea:BAABNQAECn8ZAAIXAAYKHwM1kQDBAAAXAAYKHwM1kQDBAAAAAA==.',
Bl='Blakdeath:BAABNQAECn8jAAIJAAgKLAwQUQBuAQAJAAgKLAwQUQBuAQAAAA==.Blargghh:BAAANQAECgYIBgAAAA==.Bloodgon:BAABNQAECn8bAAMIAAcKYRkUNgBFAQAIAAcKYRkUNgBFAQAXAAIKTA0mtABhAAAAAA==.Bloodpriests:BAABNQAECn8UAAMYAAoKvgFoswDLAAAYAAkKzAFoswDLAAAMAAIKtQUDbAAjAAAAAA==.Bloodvoid:BAAANQAECggICAAAAA==.Bluetuesday:BAAANQADCgYIBgAAAA==.',
Bo='Bobthedemon:BAAANQAECgYIDwAAAA==.Bohica:BAAANQAECgQICAAAAA==.Boka:BAAANQADCgMIAgAAAA==.Bonechop:BAAANQADCgIIAgAAAA==.Bowseye:BAAANQAECgIIAgABNQAECgkJKgAHAEATAA==.Boyakasha:BAABNQAECn8oAAIRAAcKOQlwBgDoAAARAAcKOQlwBgDoAAAAAA==.',
Br='Brayne:BAAANQAECgYIDQAAAA==.Brewsome:BAABNQAECn9GAAIZAAoKEyIjBQBQAwAZAAoKEyIjBQBQAwAAAA==.Bricktamland:BAAANQAECgQIBAAAAA==.Brighthammer:BAAANQADCgcIDQAAAA==.Bryybryy:BAABNQAECn86AAIXAAoKDx0dGQA7AgAXAAoKDx0dGQA7AgAAAA==.Bryyguyy:BAAANQADCgIIAgABNQAECgoKOgAXAA8dAA==.Bryythyr:BAAANQAECgUIBQABNQAECgoKOgAXAA8dAA==.',
Bu='Bubleherth:BAAANQADCgcIFwAAAA==.Bullymayes:BAAANQABCgYIBgAAAA==.Bunkiee:BAAANQADCggIFgAAAA==.',
Ca='Calbee:BAAANQADCgYIBwAAAA==.Candorite:BAAANQAECgUIBwABNQAECggIHgAaAJoYAA==.Candra:BAAANQADCgEIAQAAAA==.Capcoms:BAAANQAECgUICwABNQAECgkJQAAFALsfAA==.Capita:BAABNQAECn80AAIOAAoKJg8lDgCzAQAOAAoKJg8lDgCzAQAAAA==.Carsinegan:BAABNQAECn8mAAMbAAcK6xElFwClAAAUAAQKIhC1GQC5AAAbAAUKHBMlFwClAAAAAA==.Cassica:BAABNQAECn8dAAMMAAkKZxE+MQCZAQAMAAcK4hE+MQCZAQAYAAcKUhIFkQBjAQAAAA==.Catskin:BAAANQADCgYICQAAAA==.Causticminx:BAAANQABCgYIBwAAAA==.',
Ch='Chainlink:BAAANQADCgIIAgAAAA==.Charkle:BAABNQAECn8lAAIBAAYKFAsp4wDqAAABAAYKFAsp4wDqAAAAAA==.Chillylilly:BAAANQAECggIEAAAAA==.Chopsuoy:BAAANQADCgEIAQAAAA==.Chummie:BAABNQAECn8oAAQLAAkKPR57XwA5AgALAAgKehx7XwA5AgAUAAIKbSIOGADMAAAbAAIK0xXkUACMAAAAAA==.Chuud:BAAANQAECgQIAwAAAA==.Cháotic:BAAANQADCgQIBAAAAA==.',
Ci='Ciandoril:BAABNQAECn8eAAMEAAkKUhVXLQCZAQAEAAkKUhVXLQCZAQAWAAIK1QSZfgAcAAAAAA==.Cid:BAAANQADCgQIBAAAAA==.',
Co='Comeanddie:BAAANQADCggIFAABNQADCgMIAwAKAAAAAA==.',
Cr='Crazyeyes:BAABNQAECn8cAAIcAAkKBAW8tAAPAQAcAAkKBAW8tAAPAQAAAA==.Crimsondeath:BAABNQAECn8oAAIXAAcKvA//TgABAQAXAAcKvA//TgABAQAAAA==.Crylecks:BAAANQAECgYIBgAAAA==.',
Cy='Cyclonian:BAAANQAECggICAABNQAECggIDwAKAAAAAA==.Cylu:BAAANQADCggICwAAAA==.Cyprus:BAABNQAECn8pAAMCAAoKzhagGABQAgACAAoKzhagGABQAgAEAAEKAACctAAuAAAAAA==.',
Da='Daelric:BAAANQAECgEIAQAAAA==.Daender:BAABNQAECn8/AAIBAAoKhyL0GgAtAwABAAoKhyL0GgAtAwAAAA==.Daenor:BAAANQAECgQIBAAAAA==.Daevie:BAABNQAECn8pAAIFAAoK0wcxugAxAQAFAAoK0wcxugAxAQAAAA==.Dairydemon:BAABNQAECn8+AAIdAAoKrAM1QQBEAQAdAAoKrAM1QQBEAQAAAA==.Damageus:BAACNQAFFH8GAAMOAAMK0R2mDABeAAAFAAIKcBxPMwCkAAAOAAEKkyCmDABeAAA1AAQKfz4AAwUACgpcJPppAKoCAAUACQpLJPppAKoCAA4AAgp/JJYzAGwAAAAA.Damworg:BAABNQAECn8aAAIcAAcKuhLqqAApAQAcAAcKuhLqqAApAQAAAA==.Daniryl:BAEBNQAECn8lAAQEAAkKpBllFQBtAgAEAAkKpBllFQBtAgAeAAcKnw8SHAArAQACAAMKJAYrYgBuAAABNQAECgkJHgADAH0TAA==.Dar:BAABNQAECn9HAAIBAAoKThUQSwA5AgABAAoKThUQSwA5AgAAAA==.Darcside:BAABNQAECn8jAAIMAAcKaQ6TLQAaAQAMAAcKaQ6TLQAaAQAAAA==.Daritar:BAEBNQAECn8eAAIDAAkKfRNJZAD0AQADAAkKfRNJZAD0AQAAAA==.Darkburtus:BAABNQAECn8yAAIdAAoKDQcdJgBqAQAdAAoKDQcdJgBqAQAAAA==.Darkfeatherr:BAAANQAECgIIBAAAAA==.Darkxwraith:BAABNQAECn9HAAQGAAoKHxrnDgA7AgAGAAoKHxrnDgA7AgANAAEK5hYg6wBDAAAHAAEKCAoFpQE1AAAAAA==.Datsombeech:BAABNQAECn86AAIcAAoKngmdfACRAQAcAAoKngmdfACRAQAAAA==.',
De='Defhammer:BAAANQABCggIGAAAAA==.Deka:BAAANQADCgMIAwAAAA==.Deàdly:BAAANQADCgUJCgAAAA==.',
Dh='Dhaynk:BAABNQAECn9QAAMfAAoKsh9MBACcAgAfAAoKlB9MBACcAgAdAAoKABSHKAAAAgAAAA==.',
Di='Dianoia:BAAANQAECgQIBgABNQAFFAcIGwAbAH8YAA==.Didamus:BAAANQABCgMIAwAAAA==.Dingleding:BAAANQAECggIDAAAAA==.',
Dk='Dkanabiss:BAAANQADCgYIEAAAAA==.Dkinabox:BAAANQADCgYIBwAAAA==.',
Do='Docoo:BAABNQAECn8pAAIXAAoKRCPmFgD2AgAXAAoKRCPmFgD2AgAAAA==.Dogmeat:BAAANQABCgQICAAAAA==.Dominates:BAAANQAECggIDAAAAA==.',
Dr='Drasilia:BAAANQADCggIDgAAAA==.Dreu:BAAANQADCgUIBwABNQAFFAcIFwAdAOMUAA==.Drewserk:BAABNQAECn85AAIcAAoKHhVlWAD1AQAcAAoKHhVlWAD1AQAAAA==.Driten:BAABNQAECn9AAAIFAAkKux9/SgAvAgAFAAkKux9/SgAvAgAAAA==.Drocsid:BAAANQAECggIDwABNQAECgoKPAAHAMQjAA==.Drpiscisphd:BAAANQAECgEIAQABNQAECgoKRAAQAAQjAA==.Drsaltyballz:BAAANQAECgIIAgAAAA==.Drspoon:BAABNQAECn8uAAIXAAoKfRjUPgAFAgAXAAoKfRjUPgAFAgAAAA==.Drugpala:BAAANQAECgEJAwAAAA==.Drumuss:BAAANQAECgMIBQAAAA==.',
Ds='Dsancho:BAAANQAECgYIDAAAAA==.',
Du='Ducat:BAAANQAECgcICgAAAA==.Dudley:BAAANQAECgMIBAAAAA==.Duffun:BAABNQAECn8oAAIFAAgKERuiXQD+AQAFAAgKERuiXQD+AQABNQAECgoKTgAgABslAA==.Duffunha:BAABNQAECn9OAAMgAAoKGyXDAABCAwAgAAoKGyXDAABCAwABAAYKKCFWQABVAgAAAA==.Durto:BAAANQADCgEIAQABNQAECgIIAgAKAAAAAA==.',
Dy='Dyre:BAAANQAECgQICAAAAA==.Dyslexic:BAAANQAECgUIDAABNQAFFAUICwAHALMHAA==.Dyspepsia:BAACNQAFFH8LAAIHAAUKswcZKQB1AAAHAAUKswcZKQB1AAA1AAQKfyQAAgcACgq+E66FABwCAAcACgq+E66FABwCAAAA.',
['Dõ']='Dõngus:BAAANQADCgYIBgABNQAECggIDwAKAAAAAA==.',
Ed='Edelgard:BAAANQAECgEIAgAAAA==.Edie:BAAANQAECgEIAQAAAA==.',
Ei='Eirenn:BAAANQAECggICAAAAA==.',
El='Eleaornu:BAABNQAECn84AAMNAAoKsxr4LACzAgANAAoKsxr4LACzAgAHAAcKaQcx/gDsAAAAAA==.Elimee:BAABNQAECn89AAIFAAoKDiRrHQBiAwAFAAoKDiRrHQBiAwAAAA==.Ellasia:BAAANQABCgMIAwAAAA==.Elvenbane:BAABNQAECn8ZAAIEAAYKjAboegDgAAAEAAYKjAboegDgAAAAAA==.',
Em='Emart:BAAANQAECgQICAAAAA==.',
Er='Erayna:BAABNQAECn8wAAICAAoKQAw6KwCVAQACAAoKQAw6KwCVAQAAAA==.',
Es='Essence:BAABNQAECn8uAAIFAAoKuRccPgBUAgAFAAoKuRccPgBUAgAAAA==.',
Et='Etherious:BAAANQADCgUICwABNQADCggICwAKAAAAAA==.',
Ev='Evelinah:BAAANQAECggIEAAAAA==.Evïe:BAAANQAECgEIBAABNQAECgoKPQAFAA4kAA==.',
Ex='Explode:BAAANQAECggICwABNQAECgMIAQAKAAAAAA==.',
Fa='Falconclaw:BAAANQADCggIIQAAAA==.Falconwing:BAAANQADCgEIAQAAAA==.Falkensnoman:BAAANQAECgQICAAAAA==.Fayedra:BAABNQAECn8lAAIWAAgKRhScHQCzAQAWAAgKRhScHQCzAQAAAA==.',
Fe='Feenii:BAABNQAECn9AAAISAAoKIxPoDwAXAgASAAoKIxPoDwAXAgAAAA==.',
Fi='Figgyandrii:BAAANQAECgYIBgAAAA==.Fizzlelich:BAAANQADCggIOQAAAA==.',
Fo='Foxdeer:BAABNQAECn8hAAILAAgKOwi+rQD5AAALAAgKOwi+rQD5AAAAAA==.Foxmachina:BAAANQAECgYIBQAAAA==.Foxxmccloud:BAAANQADCgIJAgABNQAECgoKLAAEAKQfAA==.',
Fu='Fungies:BAABNQAECn9HAAMLAAoK1Be0QgANAgALAAoKhhW0QgANAgAUAAQKphatEQAcAQAAAA==.Furybest:BAAANQAECgcICQAAAA==.Furyrage:BAAANQADCgQIBAAAAA==.Fuzzyclawz:BAAANQABCgcIDAABNQAECgoKOAANALMaAA==.',
Ga='Gannir:BAAANQAECgEIAQAAAA==.Gano:BAAANQADCgQIBwAAAA==.Gatlokal:BAAANQADCggIAgAAAA==.Gatman:BAAANQADCgYICQAAAA==.',
Gi='Gimiltockel:BAAANQADCgUIBwAAAA==.Giramar:BAABNQAECn8aAAIMAAkKPAvkIgBvAQAMAAkKPAvkIgBvAQAAAA==.',
Go='Gochujang:BAAANQAECgQIBAABNQAFFAIIBgADAF8QAA==.Gojo:BAEANQAECgEIAwAAAA==.Goldeelock:BAAANQADCggIDQAAAA==.Gotchya:BAAANQABCgEIAQAAAA==.Goteem:BAAANQAECgUIBwAAAA==.Gothitelle:BAAANQAECgEIAQAAAA==.',
Gr='Grandad:BAAANQAECgQIDwAAAA==.Grandest:BAAANQADCgQIBAAAAA==.Grantaire:BAAANQADCggIEgAAAA==.Grimmdogg:BAAANQAECgMIAwAAAA==.Grimrox:BAABNQAECn8mAAIDAAkKMhKvUQCTAQADAAkKMhKvUQCTAQAAAA==.Grombo:BAAANQAECgQICAAAAA==.',
Gu='Guano:BAAANQAECgMIAwAAAA==.',
Ha='Haanit:BAAANQADCgIIAgAAAA==.Hakela:BAAANQAECgEIAQAAAA==.Hardlyevoker:BAAANQADCgMIAwABNQAECgkJOQANAHohAA==.',
He='Healingwave:BAAANQADCgYIBgAAAA==.Hearnê:BAAANQADCgIIAQAAAA==.Heavyarm:BAAANQADCgEIAQAAAA==.Heethen:BAAANQAECgUICQAAAA==.Hexbox:BAABNQAECn8bAAMaAAkKohefcAC6AQAaAAgKGRqfcAC6AQADAAcKHg8xhwCSAQAAAA==.',
Hi='Himawari:BAABNQAECn8sAAQhAAkKHxMaEwCLAQAhAAgKHxMaEwCLAQAiAAEKAABKMwA1AAAcAAIKIwc7KwE1AAAAAA==.',
Ho='Hoffmin:BAABNQAECn83AAMdAAoKdx5PDgAEAwAdAAkKFyFPDgAEAwATAAEKGgyckQA3AAAAAA==.Holemeister:BAACNQAFFH8GAAIHAAMKcBaQEwDpAAAHAAMKcBaQEwDpAAA1AAQKf0EAAgcACgoBJDszAP8CAAcACgoBJDszAP8CAAAA.Holyamin:BAAANQAECgQICAAAAA==.Holymann:BAABNQAECn8UAAIMAAYKzwsdNQDqAAAMAAYKzwsdNQDqAAAAAA==.Holyschnikey:BAABNQAECn81AAINAAkKWxOTZwDhAQANAAkKWxOTZwDhAQAAAA==.Holyz:BAABNQAECn8sAAINAAkKBSTJCgB3AwANAAkKBSTJCgB3AwAAAA==.Horgable:BAAANQADCgEIAQAAAA==.Horrorpops:BAABNQAECn8gAAILAAoKahSDQAAUAgALAAoKahSDQAAUAgABNQAECgoKPwABAIciAA==.',
Hu='Hudfin:BAAANQAECgQIBAAAAA==.Hugginz:BAAANQADCgYIEgAAAA==.Hunzul:BAAANQADCggIDAAAAA==.Hurzal:BAAANQAECgUIBAAAAA==.',
Hy='Hypnototem:BAAANQAECgEIAQAAAA==.',
['Hè']='Hèimdall:BAABNQAECn8mAAIGAAgK7QlsMQD0AAAGAAgK7QlsMQD0AAAAAA==.',
['Hí']='Hílthaen:BAABNQAECn82AAIYAAoK3x7QIgDNAgAYAAoK3x7QIgDNAgAAAA==.',
Ic='Icehead:BAAANQAECgQIAwAAAA==.Ichigokisu:BAAANQAECggIBAAAAA==.',
Ih='Ihavenobrain:BAAANQABCgIIAgAAAA==.',
Il='Illy:BAABNQAECn8dAAIdAAgKTxCMKgDtAQAdAAgKTxCMKgDtAQAAAA==.',
In='Instantdeath:BAAANQADCgMIAwAAAA==.Invali:BAAANQAECgEIAQAAAA==.',
Is='Ishivyounot:BAAANQADCgUICgAAAA==.',
Iv='Ivranda:BAABNQAECn8eAAIaAAgKmhjcTADfAQAaAAgKmhjcTADfAQAAAA==.',
Ix='Ixio:BAAANQADCgYIBgAAAA==.',
Ja='Jahan:BAACNQAFFH8HAAIYAAIKJB9UKACkAAAYAAIKJB9UKACkAAA1AAQKf0IAAxgACgpbJLIHAIcDABgACgoGI7IHAIcDACMABwpdHu8EAG0CAAE1AAQKBAgEAAoAAAAA.Jamie:BAABNQAECn8VAAMXAAcKgSSLKQB2AgAXAAYKgSSLKQB2AgAIAAEKAADP4AAzAAABNQAFFAgIEAALAPEiAA==.Jarek:BAAANQABCgQIBAAAAA==.',
Je='Jegra:BAABNQAECn8sAAIkAAoKGh0pEQBLAgAkAAoKGh0pEQBLAgAAAA==.Jerith:BAABNQAECn8sAAMQAAkKUwwDFQCHAQAQAAkKUwwDFQCHAQAPAAYKPwWqNAAVAQAAAA==.Jerryy:BAEANQADCgEIAgABNQAECgEIAwAKAAAAAA==.Jessilyn:BAAANQADCggIGAAAAA==.',
Ji='Jigari:BAAANQADCgcIDgAAAA==.Jinxed:BAAANQAECgMIAwAAAA==.',
Jo='Jord:BAAANQAECgQIBAAAAA==.',
Ju='Jubellina:BAABNQAECn83AAIZAAoKmw9DHAC/AQAZAAoKmw9DHAC/AQAAAA==.Jubîlee:BAAANQABCgIIAgAAAA==.',
['Jà']='Jàzz:BAAANQADCggIJgAAAA==.',
Ka='Kaelora:BAAANQADCgYICQAAAA==.Kaerei:BAAANQADCgQIBAAAAA==.Kaleb:BAECNQAFFH8SAAITAAUK3RpHDAAFAQATAAUK3RpHDAAFAQA1AAQKf1IAAhMACgrAJEMEAEkDABMACgrAJEMEAEkDAAAA.Kalferno:BAABNQAECn8bAAIFAAcKZQ+BsABEAQAFAAcKZQ+BsABEAQAAAA==.Kalirkaz:BAACNQAFFH8FAAICAAQKKgitDADnAAACAAQKKgitDADnAAA1AAQKfyEAAgIACgrUEm8aADkCAAIACgrUEm8aADkCAAE1AAQKCgo7ABoA8R0A.Kayotica:BAAANQAECgUIDQAAAA==.',
Ke='Keensmite:BAAANQAECgMIBQAAAA==.Kendall:BAAANQAECgQIBAABNQAECgoKJAAJABETAA==.',
Kh='Khallock:BAABNQAECn8bAAIUAAoK8gsPCwCWAQAUAAoK8gsPCwCWAQAAAA==.',
Ki='Kiemen:BAABNQAECn8kAAMJAAoKERPCKwADAgAJAAoKERPCKwADAgAIAAYK7ApShAAOAQAAAA==.Killko:BAABNQAECn8bAAMJAAgK6RBuRACwAQAJAAgK6RBuRACwAQAIAAIKpQrVyABaAAAAAA==.Kirisen:BAAANQAECgIIAwAAAA==.',
Kn='Knardan:BAABNQAECn8yAAIBAAkK/x+OVwBsAgABAAkK/x+OVwBsAgAAAA==.',
Ko='Kotanx:BAAANQADCggIEQAAAA==.',
Kr='Kragsloor:BAAANQADCggICwAAAA==.Krickette:BAAANQAECgQIBAABNQAECgoKMAACAEAMAA==.',
Ku='Kuraki:BAABNQAECn8lAAIkAAgKRQytJgBkAQAkAAgKRQytJgBkAQAAAA==.',
Ky='Kyriea:BAAANQADCgYIBgAAAA==.',
La='Ladrar:BAAANQAECgIIAwAAAA==.Laidiemonk:BAAANQADCggICAABNQAECgoKQgABAHYOAA==.Lanadiel:BAABNQAECn86AAIGAAoKzyFlCgD0AgAGAAoKzyFlCgD0AgAAAA==.Lasalghoul:BAAANQAECggIDgAAAA==.Lassyn:BAAANQAECggICQABNQAECggIDgAKAAAAAA==.',
Le='Legend:BAAANQAECgMIAQAAAA==.Len:BAABNQAECn8yAAMaAAoK3xPCWQADAgAaAAkKzhLCWQADAgADAAcKQQx8yAABAQAAAA==.Leoñidas:BAAANQAECgYIDgAAAA==.',
Li='Lian:BAAANQAECgQIBQAAAA==.Lianda:BAAANQAECggICAAAAA==.Lianse:BAAANQADCgYICwAAAA==.Liliara:BAABNQAECn8/AAIBAAoKJRn8OQBmAgABAAoKJRn8OQBmAgAAAA==.Lillyirl:BAAANQAECgEIAQAAAA==.Lillymae:BAABNQAECn8aAAIdAAkKGSLXDgD+AgAdAAkKGSLXDgD+AgAAAA==.Lillyslight:BAAANQAECgQIBAAAAA==.Lillytae:BAAANQADCgYIBgAAAA==.Lillyvani:BAAANQAECgQIBAAAAA==.Lilmoo:BAABNQAECn8VAAIBAAYKggVBCQH0AAABAAYKggVBCQH0AAAAAA==.Lilpump:BAAANQAECgQICQABNQAECgoKLgAXAH0YAA==.Lindalinda:BAAANQADCgEIAQAAAA==.Linkhunter:BAAANQAECgUIDQABNQAECgoKQAAjALwhAA==.Linkmônk:BAAANQADCgcICgABNQAECgoKQAAjALwhAA==.',
Lo='Lodise:BAABNQAECn81AAIUAAoKpxE1CADaAQAUAAoKpxE1CADaAQAAAA==.Lorzz:BAABNQAECn9CAAIYAAoKaR17JADaAgAYAAoKaR17JADaAgAAAA==.Loveydovey:BAAANQADCgIIAgAAAA==.',
Lu='Lucrio:BAABNQAECn87AAIIAAoKyhYKGAAqAgAIAAoKyhYKGAAqAgAAAA==.Ludlow:BAAANQADCgMIAwABNQAECgoKMwAQANwUAA==.Lunalai:BAAANQAECgQIBAAAAA==.Lurim:BAABNQAECn8yAAIWAAoKKSAPBgAzAwAWAAoKKSAPBgAzAwAAAA==.Lushy:BAABNQAECn9OAAIPAAoKjhdgKwBSAgAPAAoKjhdgKwBSAgAAAA==.',
Ly='Lylindara:BAABNQAECn8ZAAIaAAgKJgjDkwBWAQAaAAgKJgjDkwBWAQAAAA==.Lylinette:BAAANQADCggIDwAAAA==.Lyrazel:BAAANQABCgIIAgABNQAECgoKFgAaABEfAA==.',
['Ló']='Lókï:BAAANQADCgEIAQAAAA==.',
Ma='Madgorilla:BAAANQADCgUIBQAAAA==.Mageofdeath:BAABNQAECn9FAAMOAAoKqxMKCgAEAgAOAAkKqxMKCgAEAgAFAAkKDAsuwwAgAQABNQADCgMIAwAKAAAAAA==.Mageskin:BAAANQAECgQICQAAAA==.Maladaptive:BAAANQADCgYIDwAAAA==.Manerva:BAAANQADCggIJgAAAA==.Mastorcheef:BAAANQADCgQIBAAAAA==.Mattsdruid:BAAANQAECgMIBAAAAA==.Maurin:BAABNQAECn8UAAQEAAoK2g2lPQA1AQAEAAoKhAalPQA1AQAWAAUK9RPJNAD5AAAeAAMKIAVWMwB6AAAAAA==.Maximumhonk:BAABNQAECn80AAIaAAoKxBdKRAACAgAaAAoKxBdKRAACAgAAAA==.Maxonoa:BAAANQADCggIFwAAAA==.Maxximos:BAAANQAECgIIAgAAAA==.',
Me='Mekkadaddy:BAABNQAECn8mAAIBAAkK7RNRnwB1AQABAAkK7RNRnwB1AQAAAA==.Mellow:BAAANQAECgMIAwAAAA==.Mendelia:BAABNQAECn8pAAIGAAoKghOSGwCVAQAGAAoKghOSGwCVAQAAAA==.Mercus:BAABNQAECn8jAAMPAAgKyA9aIgC4AQAPAAcKVg9aIgC4AQAQAAcKvA43RwCoAQAAAA==.Merllinna:BAAANQABCgIIAQAAAA==.Mervenious:BAABNQAECn8xAAMcAAoKTQoChQB7AQAcAAoKIQoChQB7AQAhAAUKvgoJKgCuAAAAAA==.',
Mi='Mindplague:BAABNQAECn84AAIMAAcK4xpoJQAEAgAMAAcK4xpoJQAEAgAAAA==.Minipincin:BAAANQAECgUIBQAAAA==.Minmzey:BAAANQAECgQIBgAAAA==.Miroslava:BAAANQAECgUICQAAAA==.Missfire:BAABNQAECn8XAAIBAAgKwg90ogDBAQABAAgKwg90ogDBAQABNQAECgoKKQACAM4WAA==.',
Mk='Mkaye:BAAANQAECgIIBAAAAA==.',
Mo='Moggle:BAABNQAECn8YAAIFAAYKiAcNOwEqAQAFAAYKiAcNOwEqAQAAAA==.Mondazi:BAABNQAECn9GAAMDAAoKrB2wGwCRAgADAAoKrB2wGwCRAgAaAAoK+A7NaADSAQAAAA==.Moonlilly:BAAANQADCgIIAgAAAA==.Morfy:BAAANQABCggIBgAAAA==.Morgzim:BAAANQADCgYJBwAAAA==.Moustaccio:BAAANQAECgEIAgAAAA==.Mozarta:BAAANQABCggIDQAAAA==.',
Ms='Msmanalow:BAAANQAECgEIAQABNQAECgoKKQACAM4WAA==.',
My='Mycen:BAABNQAECn8XAAILAAgKbgw7kQC7AQALAAgKbgw7kQC7AQAAAA==.Myeyesburn:BAAANQAECgMJBAAAAA==.',
['Má']='Málaketh:BAAANQAECgcIEAAAAA==.',
Na='Nardena:BAAANQAECgIIAQAAAA==.Narz:BAABNQAECn9OAAIBAAoK0hKmSwA4AgABAAoK0hKmSwA4AgAAAA==.Naughtypine:BAAANQADCgYIBgAAAA==.Naylz:BAAANQAECggIAQAAAA==.',
Nd='Ndiz:BAAANQAECgUIBAAAAA==.',
Ne='Necronomikon:BAABNQAECn8jAAIFAAgK2QxDqABTAQAFAAgK2QxDqABTAQAAAA==.Nemasis:BAAANQADCggICAABNQAECgoKQgABAHYOAA==.Nerhzul:BAAANQADCgUIBQAAAA==.Neromoo:BAAANQAECgUIDQABNQAECgoKLQAVAPsSAA==.Neruphuyt:BAABNQAECn8dAAIEAAgKAgnkXABdAQAEAAgKAgnkXABdAQABNQAECgkJHAAcAAQFAA==.',
Ni='Niath:BAAANQAECgUIDgAAAA==.Nightheal:BAAANQABCgQIBQABNQAECgoKKQAXAEQjAA==.Nightsniper:BAAANQAECgEIAQABNQAECgoKKQAXAEQjAA==.',
No='Notdinor:BAAANQADCgIIAgAAAA==.Notlilly:BAABNQAECn8oAAIhAAkKoBEeFQDVAQAhAAkKoBEeFQDVAQAAAA==.Notpillows:BAAANQAECgEIAQAAAA==.',
Ny='Nyxelle:BAAANQAECgIIAwAAAA==.',
['Nä']='Närz:BAAANQADCggIBQAAAA==.',
['Nò']='Nòvà:BAAANQAECgYIEQAAAA==.',
Oi='Oilfu:BAAANQADCgUIBQABNQAECgoKTgAPAI4XAA==.',
Ok='Okioni:BAAANQAECgUIBQAAAA==.',
Ol='Olgon:BAACNQAFFH8MAAIBAAMKRBNWEwDxAAABAAMKRBNWEwDxAAA1AAQKf04AAgEACgq9Gp4sAI8CAAEACgq9Gp4sAI8CAAAA.',
Op='Oprhawinfury:BAABNQAECn8jAAIIAAkKkQt3bABhAQAIAAkKkQt3bABhAQAAAA==.',
Or='Orgodemir:BAABNQAECn8lAAIYAAgKliULHAD5AgAYAAgKliULHAD5AgAAAA==.Orhamin:BAAANQADCgYIDwAAAA==.',
Os='Oshani:BAABNQAECn8WAAMaAAoKER8pDwBEAwAaAAoKER8pDwBEAwADAAIKEAd9NQE0AAAAAA==.',
Ou='Outlaw:BAAANQADCgcIBwAAAA==.',
Pa='Pacolyte:BAAANQAECgQIBgAAAA==.Paigor:BAAANQABCgIIAgAAAA==.Palathene:BAABNQAECn8yAAMHAAoKxyAlKQC9AgAHAAoKxyAlKQC9AgAGAAQKnR0wNABCAQAAAA==.Pallystorm:BAAANQAECgYICAABNQAECgoKHwAbANgIAA==.Palmike:BAAANQADCgYIBgAAAA==.Pandemonia:BAABNQAECn87AAILAAkKYxK4dQABAgALAAkKYxK4dQABAgAAAA==.Parsie:BAAANQAECgYIEQAAAA==.Pathibas:BAAANQADCggIDQABNQAECgoKOwAiAJYgAA==.Pattycakes:BAABNQAECn8pAAIIAAkKRQ4rLgB5AQAIAAkKRQ4rLgB5AQAAAA==.',
Pe='Pericø:BAAANQADCgQIBAAAAA==.',
Ph='Pherocious:BAAANQAECgQIBQAAAA==.',
Pi='Pinktuesday:BAAANQADCggICAAAAA==.Pixeleen:BAACNQAFFH8PAAIBAAUKbxQFCgBPAQABAAUKbxQFCgBPAQA1AAQKfzwAAwEACgpeIswmAPwCAAEACgpeIswmAPwCACUABQrfCvJMAP4AAAAA.',
Pl='Plexy:BAABNQAECn8gAAMYAAkKYSDbIQDnAgAYAAkKuh/bIQDnAgAjAAcK8hlaCADhAQAAAA==.',
Po='Pokitz:BAABNQAECn8uAAIHAAoKDAhprAB2AQAHAAoKDAhprAB2AQAAAA==.Powerwordehh:BAAANQAECgEIAQABNQAECgkJHgAEAFIVAA==.',
Pr='Primordinor:BAABNQAECn82AAIDAAkKgx2TMAAWAgADAAkKgx2TMAAWAgAAAA==.Probnotalive:BAABNQAECn9DAAIBAAoK/x0pFwA+AwABAAoK/x0pFwA+AwAAAA==.Probnoturmom:BAABNQAECn80AAIYAAkKVR5ZLQCzAgAYAAkKVR5ZLQCzAgAAAA==.',
Pu='Puab:BAAANQAECgYIBAABNQAECgoKPAAHAMQjAA==.',
Qu='Quacko:BAAANQAECgUICQABNQAECgoKMgAWACkgAA==.Quietus:BAAANQADCggIEwAAAA==.',
Ra='Raevyn:BAAANQAECgEIAQAAAA==.Raikai:BAAANQAECgIIBQABNQAECgoKOAANALMaAA==.Rakan:BAABNQAECn9IAAMhAAoKcR9EBQDEAgAhAAoKcR9EBQDEAgAcAAUKeQ2M6AAUAQAAAA==.Rallick:BAACNQAFFH8HAAINAAIKhQYoIQB1AAANAAIKhQYoIQB1AAA1AAQKfz0AAg0ACgovGDUmAJYCAA0ACgovGDUmAJYCAAAA.Ranì:BAABNQAECn86AAMhAAoKxxYpDQDtAQAhAAoKxxYpDQDtAQAiAAEKfAc1NwAvAAAAAA==.Rathger:BAAANQADCgUICAAAAA==.Ratmilk:BAAANQAECgcIDAAAAA==.Razkhan:BAAANQADCgcIDQAAAA==.',
Rd='Rdk:BAAANQAECgMIBAAAAA==.',
Re='Redek:BAAANQADCgcICgAAAA==.Reft:BAAANQABCgEIAQAAAA==.Reighna:BAAANQADCggIDQAAAA==.Rendcurse:BAAANQADCgEIAQAAAA==.Rendeath:BAAANQADCgEIAQAAAA==.Rendwee:BAABNQAECn9FAAIeAAoKeSGQBQC8AgAeAAoKeSGQBQC8AgAAAA==.Reps:BAAANQAECggICgAAAA==.Retiredaggro:BAAANQAECgUIDgAAAA==.Retiredghoul:BAAANQADCgUIBQAAAA==.Retiredlight:BAAANQADCgEIAQAAAA==.Rewolf:BAABNQAECn8YAAMaAAYKCB4xYACYAQAaAAYKCB4xYACYAQADAAEKAAA5HwEAAAAAAA==.',
Rh='Rheemus:BAAANQAECggICAABNQAECgoKPwABAIciAA==.Rhynar:BAAANQAECggICAAAAA==.',
Ri='Ricflairion:BAABNQAECn82AAImAAoK9gpTCgBkAQAmAAoK9gpTCgBkAQAAAA==.Rill:BAAANQADCggICwAAAA==.',
Ro='Rodcet:BAABNQAECn88AAIHAAoKxCOdHgBJAwAHAAoKxCOdHgBJAwAAAA==.Roflbubble:BAABNQAECn8/AAMYAAoKfxRXSAAXAgAYAAoKfxRXSAAXAgAMAAUKdAWqVQC2AAAAAA==.Rognan:BAAANQAECgYICgAAAA==.Roku:BAAANQAECgcICQAAAA==.Ronkin:BAAANQADCggIJAAAAA==.Rookgue:BAABNQAECn9QAAIQAAoKkxMGDAAOAgAQAAoKkxMGDAAOAgAAAA==.Rookoker:BAABNQAECn8cAAInAAkKMAW1FQDbAAAnAAkKMAW1FQDbAAAAAA==.Rorygazer:BAABNQAECn8ZAAIhAAYKDCIZEAAnAgAhAAYKDCIZEAAnAgAAAA==.Rosmerta:BAAANQAECgIIAwAAAA==.Rossa:BAAANQABCgIIAgAAAA==.Rossdair:BAAANQAECgQIDAABNQAECgcIDgAKAAAAAA==.Rossperot:BAABNQAECn8bAAIIAAcKLh10SgDsAQAIAAcKLh10SgDsAQAAAA==.',
Ry='Ryk:BAABNQAECn8VAAIQAAoKTBrRBwB3AgAQAAoKTBrRBwB3AgAAAA==.',
Sa='Saarin:BAAANQAECgQIAwAAAA==.Saelara:BAAANQAECgQIBQAAAA==.Sairal:BAAANQAECggIEAAAAA==.Saltytuesday:BAAANQADCgYICQAAAA==.Samgee:BAACNQAFFH8ZAAIHAAUK4RoCEQA+AQAHAAUK4RoCEQA+AQA1AAQKf0EAAgcACgrFIPQzAP0CAAcACgrFIPQzAP0CAAAA.Sanguathene:BAEANQAECgQIAwABNQAECgUIBgAKAAAAAA==.Sawlty:BAABNQAECn8kAAIlAAoKxwwYMADNAQAlAAoKxwwYMADNAQAAAA==.Saynar:BAABNQAECn84AAMdAAoKuyKLCQC9AgAdAAoKuyKLCQC9AgAfAAIKRR1VJgCHAAAAAA==.',
Sc='Scattered:BAABNQAECn8pAAMbAAoKqw4MJwA+AQAbAAYKqQsMJwA+AQALAAcKeQ7MsQDwAAAAAA==.Schecter:BAABNQAECn8YAAMaAAcKJyOUMQCaAgAaAAcKJyOUMQCaAgADAAEKCxj0KQE/AAAAAA==.Scintila:BAAANQADCgQIBAABNQAECgkJOwALAGMSAA==.Scooti:BAAANQADCggIEAABNQAECgYIDAAKAAAAAA==.',
Se='Seba:BAACNQAFFH8HAAIFAAIKoAqiPQB+AAAFAAIKoAqiPQB+AAA1AAQKf10AAgUACgoYH/ErAI8CAAUACgoYH/ErAI8CAAAA.Sehren:BAAANQADCgcIBgAAAA==.Sehtrak:BAAANQADCggICAAAAA==.Selesne:BAABNQAECn8lAAIRAAgKiQvIBABIAQARAAgKiQvIBABIAQAAAA==.Seniandrays:BAAANQADCgQIBAAAAA==.Serannia:BAAANQADCgIIAgAAAA==.Seraphicktwo:BAABNQAECn8bAAMMAAkKpQvpPQA9AQAMAAkKpQvpPQA9AQAYAAEKTgYI/gAvAAAAAA==.',
Sh='Shadowtrance:BAAANQAECgEIAQABNQAECgoKRwAGAB8aAA==.Shaggmz:BAABNQAECn8nAAIiAAcKQQ9yFwALAQAiAAcKQQ9yFwALAQAAAA==.Shawnkin:BAAANQADCgIIAgAAAA==.Shelyn:BAAANQAECgUICAAAAA==.Shinma:BAABNQAECn8oAAIGAAcKVgeEOADMAAAGAAcKVgeEOADMAAAAAA==.Shootermcgee:BAAANQAECgIIAgAAAA==.Showtootsies:BAAANQADCgUIBQAAAA==.Shrubbery:BAAANQAECgQIBwAAAA==.Shymary:BAABNQAECn8oAAMYAAcKChZlYAC/AQAYAAcKChZlYAC/AQAjAAYKCgfCDADBAAAAAA==.',
Si='Siete:BAAANQADCgYJBwAAAA==.Silëx:BAABNQAECn8kAAIOAAoKuhXqCgDzAQAOAAoKuhXqCgDzAQAAAA==.Sindiz:BAAANQAECgYIDgAAAA==.Sioc:BAAANQAECgMIAwAAAA==.Siouxiesioux:BAAANQAECgUIBgAAAA==.',
Sk='Skadie:BAAANQAECgUIEAAAAA==.Skoot:BAAANQAECgYIDAAAAA==.',
Sl='Slimjimz:BAAANQADCgUIBQAAAA==.Slugondeez:BAABNQAECn85AAMNAAkKeiFNJwDMAgANAAkKeiFNJwDMAgAGAAIKUyMyTwCqAAAAAA==.',
Sm='Smitefist:BAAANQAECgIIAQABNQAECggIDwAKAAAAAA==.',
Sn='Snkyturtle:BAABNQAECn9CAAIBAAoKdg7CbADoAQABAAoKdg7CbADoAQAAAA==.Snoopdogydog:BAAANQABCgcIBgAAAA==.Snuzzle:BAABNQAECn8wAAIWAAoKGxgYFAAjAgAWAAoKGxgYFAAjAgAAAA==.',
So='Soupshammich:BAAANQAECgUIBQAAAA==.Sourmash:BAAANQAECgQIBAAAAA==.',
Sp='Spaghet:BAABNQAECn8bAAIDAAkKHQ1rggCfAQADAAkKHQ1rggCfAQAAAA==.Spillthetea:BAAANQADCggICQABNQAECgYIGQAXAB8DAA==.Spittoon:BAAANQADCgEJAQABNQADCggIIAAKAAAAAA==.Sploot:BAABNQAECn8hAAILAAoKhRyMQQCNAgALAAoKhRyMQQCNAgAAAA==.',
Sr='Srasjet:BAAANQAECgQICAAAAA==.',
Ss='Ssarmandok:BAABNQAECn8bAAIHAAoKQBdloACNAQAHAAoKQBdloACNAQAAAA==.',
St='Stabytha:BAAANQAECggIDgAAAA==.Stark:BAAANQABCgQIBAAAAA==.Starlight:BAABNQAECn8qAAMCAAoKjB4hDwDjAgACAAoKjB4hDwDjAgAEAAYKzxS3WgC2AAAAAA==.Stars:BAAANQABCgIIAgAAAA==.Stealthed:BAABNQAECn8WAAIWAAUKuRAXQAC6AAAWAAUKuRAXQAC6AAAAAA==.Stender:BAAANQADCgIIAgABNQAFFAIICQATAH8eAA==.Stonegoddess:BAAANQADCgQIBAAAAA==.Stormcall:BAABNQAECn8gAAIaAAcKtB+IQQAOAgAaAAcKtB+IQQAOAgAAAA==.Stratusfied:BAAANQADCgIIAgAAAA==.Strongsad:BAAANQAECgIIAwAAAA==.',
Sw='Swiss:BAABNQAECn8eAAIDAAgKoA50gACjAQADAAgKoA50gACjAQAAAA==.',
Sy='Syldra:BAAANQABCgIIAgAAAA==.',
['Sá']='Sáëgárón:BAAANQAECgMIBAAAAA==.',
Ta='Taliden:BAAANQAECgQICwAAAA==.Tankinstine:BAAANQADCgYIBwAAAA==.Tanksmalls:BAAANQADCgQIBAAAAA==.Taraylda:BAABNQAECn8iAAMMAAkKBxzLEwAgAgAMAAkKBxzLEwAgAgAYAAEK2yEZ8gBOAAAAAA==.Tarz:BAAANQAECgYIDgAAAA==.Tazzwolfsong:BAAANQADCgEIAQAAAA==.',
Te='Tecdor:BAAANQADCgYIBgAAAA==.Teronfiggy:BAABNQAECn8aAAIJAAoKugdUXwApAQAJAAoKugdUXwApAQAAAA==.',
Tf='Tfirs:BAAANQAECgUIBwABNQAECgUIBQAKAAAAAA==.',
Th='Thehealczar:BAAANQAECgcIDwABNQAECgoKKQAXAEQjAA==.Theokoles:BAAANQAECggIDwAAAA==.Thesenate:BAAANQADCggIDwABNQAECgoKQAASACMTAA==.Thickblòód:BAABNQAECn8WAAIHAAoK5A8AhQDCAQAHAAoK5A8AhQDCAQAAAA==.Thordurin:BAAANQAECgYIBgAAAA==.Thorly:BAAANQADCgYIDQAAAA==.Thrazi:BAAANQAECgMICAAAAA==.',
Ti='Tiadalma:BAAANQAECgIIAgAAAA==.Tinn:BAAANQADCggIEAAAAA==.',
To='Toospookie:BAAANQADCgYIDgAAAA==.Totem:BAAANQAECgQIBgAAAA==.',
Tr='Tramplip:BAABNQAECn8sAAIbAAkKGA6LBwBZAQAbAAkKGA6LBwBZAQAAAA==.Treecloud:BAABNQAECn86AAMWAAoKMyFZCAC/AgAWAAoKMyFZCAC/AgAEAAEKMxHohQA6AAAAAA==.Treferimore:BAABNQAECn8kAAIBAAcKqQ6+tgBEAQABAAcKqQ6+tgBEAQAAAA==.Trevian:BAABNQAECn8lAAIHAAgKFA+/tABnAQAHAAgKFA+/tABnAQAAAA==.',
Tu='Tuesday:BAAANQADCgYIBgAAAA==.Tulimyrsky:BAAANQADCgUIBQAAAA==.Tuluxxi:BAABNQAECn8/AAMaAAoK4yLlGgAEAwAaAAoK4yLlGgAEAwADAAgK4g49dADEAQAAAA==.Tutter:BAAANQAECgUICwAAAA==.',
Tw='Twopumpchump:BAABNQAECn8sAAIoAAoKVBCDCgCYAQAoAAoKVBCDCgCYAQAAAA==.',
Tz='Tzxdh:BAAANQAECgIIAgABNQAECggIGQAGAH8VAA==.Tzxdruid:BAAANQAECgIIAgABNQAECggIGQAGAH8VAA==.',
Ug='Uglymancer:BAABNQAECn8qAAILAAoKnBaLPgAbAgALAAoKnBaLPgAbAgAAAA==.',
Uj='Ujimas:BAABNQAECn8gAAIDAAcKmBUgYQBjAQADAAcKmBUgYQBjAQAAAA==.',
Ut='Uthodne:BAAANQAECgEIAQABNQAECgoKMwAQANwUAA==.',
Va='Vampireshade:BAABNQAECn8+AAMQAAoKVg8CEwCfAQAQAAoKVg8CEwCfAQARAAYK/gMzEgDlAAAAAA==.Vampirevoid:BAAANQAECgcIBQAAAA==.Vampírella:BAAANQADCgIIAgAAAA==.Vanililly:BAABNQAECn8rAAIXAAkK8A37OgBWAQAXAAkK8A37OgBWAQAAAA==.Vanimao:BAAANQAECgEIAQAAAA==.Varan:BAAANQAECgUIBwAAAA==.',
Vb='Vbull:BAAANQAECgEIAQAAAA==.',
Ve='Velissari:BAABNQAECn8cAAITAAcKig7BRgAUAQATAAcKig7BRgAUAQAAAA==.Venatra:BAAANQADCgYICAAAAA==.Veritus:BAABNQAECn8rAAITAAkKfB4AHQCxAgATAAkKfB4AHQCxAgAAAA==.',
Vi='Vindict:BAAANQAECgQICAAAAA==.Violette:BAABNQAECn85AAIBAAoKaxPqSQA8AgABAAoKaxPqSQA8AgAAAA==.Vion:BAAANQABCgQIBAAAAA==.',
Vo='Voidlink:BAABNQAECn9AAAMjAAoKvCELAQBLAwAjAAoKvCELAQBLAwAMAAcKeBJ/IACGAQAAAA==.Voidstriker:BAAANQAECgEIAQAAAA==.Vovim:BAAANQAECgIIAwAAAA==.',
Wa='Wackyrellek:BAABNQAECn8wAAMQAAoKdh0rEADFAQAPAAkKfRHNSwDSAQAQAAkKdh0rEADFAQAAAA==.Wakancer:BAABNQAECn8VAAIUAAUKQw8KEgAqAQAUAAUKQw8KEgAqAQAAAA==.Wakarisma:BAAANQAECgEIAQAAAA==.Wakataclysm:BAAANQAECgUICwAAAA==.Walnut:BAABNQAECn8XAAIWAAoKYyCHBgDqAgAWAAoKYyCHBgDqAgABNQAFFAIIBgADAF8QAA==.Warchylde:BAAANQADCgQIBgAAAA==.Warolderoy:BAABNQAECn87AAMiAAoKliAHBQDbAgAiAAoKPSAHBQDbAgAhAAYKShyAFwC0AQAAAA==.',
We='Weedshaman:BAAANQADCgcJBwAAAA==.Weil:BAAANQAECgYICQAAAA==.',
Wi='Willowsprout:BAAANQABCgMIBAAAAA==.',
Wo='Woker:BAAANQAECgYICQABNQAECgoKQAASACMTAA==.Woogie:BAAANQAECgQIBwAAAA==.Worthy:BAAANQAECgMIAwAAAA==.Woyer:BAAANQADCgEIAQAAAA==.',
Wu='Wummie:BAAANQAECgMIAwABNQAECgkJKAALAD0eAA==.',
['Wò']='Wòógie:BAAANQADCgYIBgABNQAECgQIBwAKAAAAAA==.',
Xa='Xader:BAAANQADCggIEAAAAA==.Xanneral:BAEANQAECgYIEQABNQAECgoKNwAJADMaAA==.',
Xe='Xenna:BAAANQAECgUIDgABNQAECgkJKgAHAEATAA==.Xeq:BAAANQAECgMIAwAAAA==.',
Xi='Xiata:BAAANQAECggIBwAAAA==.',
Ye='Yeoman:BAABNQAECn8eAAIiAAoKTBLhDgCQAQAiAAoKTBLhDgCQAQAAAA==.Yewko:BAAANQAECgYIEwAAAA==.',
Yg='Yggdralith:BAAANQAECggIJgAAAQ==.',
Yi='Yibble:BAAANQAECgUIBQABNQAFFAQIDgAcANkeAA==.',
Yo='Yobagoya:BAAANQAECgEIAQAAAA==.',
Yu='Yukionne:BAAANQAECgIIAQAAAA==.Yunohealme:BAABNQAECn8aAAIJAAcK/Rn6MwAOAgAJAAcK/Rn6MwAOAgAAAA==.Yunosmall:BAAANQADCgMIAwAAAA==.Yunosmart:BAAANQADCgMIBAAAAA==.',
Yz='Yzerman:BAAANQAECgIIAgABNQAECgoKJAAJABETAA==.',
['Yö']='Yör:BAAANQADCgEIAQAAAA==.',
Za='Zaen:BAACNQAFFH8JAAMLAAIKOBKsKACQAAALAAIKkA+sKACQAAAbAAEKsA1BFABEAAA1AAQKf04AAxsACgrDIQIHAGgBAAsACgpHIZ4kAPICABsABgoPHwIHAGgBAAAA.Zanapheia:BAAANQADCgIIAgABNQAECgoKQgABAHYOAA==.Zandre:BAABNQAECn8pAAIhAAoKyBimEwDrAQAhAAoKyBimEwDrAQAAAA==.Zarkir:BAACNQAFFH8HAAIXAAIKVyKZFgC5AAAXAAIKVyKZFgC5AAA1AAQKfzMAAxcACgpEIxINAEgDABcACgpEIxINAEgDAAkAAQrACQazADcAAAAA.',
Ze='Zelily:BAABNQAECn8+AAIBAAoK3A2vhAACAgABAAoK3A2vhAACAgAAAA==.Zenarri:BAAANQADCgYICgAAAA==.Zepha:BAAANQABCgEIAQAAAA==.',
Zh='Zharvakko:BAABNQAECn81AAMaAAoKmBc1TgDaAQAaAAoKmBc1TgDaAQADAAcKrhBlhACaAQABNQAECgoKOwAaAPEdAA==.Zhiana:BAABNQAECn8cAAMOAAgKQxFHDgDHAQAFAAgKOwxj3gDLAQAOAAgK7A1HDgDHAQAAAA==.',
Zu='Zugzok:BAAANQAECgMIAwAAAA==.Zulrich:BAAANQAECgYICwAAAA==.',
Zv='Zvirae:BAAANQAECgUIBQAAAA==.Zvirax:BAAANQADCggIKQABNQAECgUIBQAKAAAAAA==.',
['Ás']='Ástrid:BAAANQAECgEIAQAAAA==.',
['Ëu']='Ëuni:BAAANQADCgQIBAAAAA==.',
['Ìs']='Ìsaac:BAAANQAECgYJEgAAAA==.',
['Ðo']='Ðolm:BAAANQAECgMIBgAAAA==.',
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
