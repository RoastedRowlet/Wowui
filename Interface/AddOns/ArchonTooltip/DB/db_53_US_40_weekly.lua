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

local lookup = {'Unknown-Unknown','Druid-Restoration','Shaman-Elemental','Druid-Balance','Mage-Arcane','Paladin-Protection','Paladin-Retribution','DeathKnight-Unholy','DeathKnight-Frost','Hunter-BeastMastery','Warlock-Demonology','Priest-Shadow','Paladin-Holy','Mage-Frost','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Shaman-Enhancement','DemonHunter-Havoc','Warlock-Affliction','Evoker-Preservation','DeathKnight-Blood','Monk-Mistweaver','Shaman-Restoration','Warlock-Destruction','Priest-Holy','DemonHunter-Devourer','Warrior-Arms','Druid-Feral','DemonHunter-Vengeance','Hunter-Survival','Druid-Guardian','Warrior-Protection','Warrior-Fury','Priest-Discipline','Monk-Windwalker','Hunter-Marksmanship','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster',}
local provider = {region='US',realm='Bloodhoof',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Aberforthd:BAAANQAECgUIDgABNQAECgYIBgABAAAAAA==.',
Ac='Aceforlife:BAAANQADCggIEAABNQAECgoKVgACAL8SAA==.Acorn:BAACNQAFFH8GAAIDAAIKXxCpGwCLAAADAAIKXxCpGwCLAAA1AAQKfy0AAgMACgqzHtYfAA0DAAMACgqzHtYfAA0DAAAA.',
Ad='Aditu:BAABNQAECn8nAAMCAAkKIRSmNQBuAQACAAYKEhSmNQBuAQAEAAkKQgyTNwBCAQAAAA==.',
Ae='Aessone:BAAANQAECgUIBQABNQAFFAIIBwAFAKAKAA==.Aetheris:BAABNQAECn8ZAAMGAAgKfxXYLAB2AQAGAAgKNhXYLAB2AQAHAAEK9iDVWAFhAAAAAA==.',
Ag='Agasonex:BAAANQADCgUIBAAAAA==.',
Ah='Ahziz:BAABNQAECn8YAAMIAAYKERCbdwA7AQAIAAYKERCbdwA7AQAJAAUKpwcseACxAAAAAA==.',
Ai='Airent:BAABNQAECn8gAAMCAAYKdRDTMwA6AQACAAYKdRDTMwA6AQAEAAYKRA+3TwDNAAAAAA==.',
Aj='Aja:BAAANQAECggICAABNQAFFAUICgAKABIPAA==.',
Al='Alaestel:BAABNQAECn9BAAIHAAoKRQ0ojwCZAQAHAAoKRQ0ojwCZAQAAAA==.Aletheia:BAAANQAECgQIBAAAAA==.Alt:BAAANQAECgIIBAAAAA==.',
An='Ancane:BAAANQADCggICAAAAA==.Andramealoch:BAAANQADCgEIAQAAAA==.Angina:BAAANQADCgUIBwAAAA==.Angrywoogie:BAAANQADCgEIAQABNQAECgQIBwABAAAAAA==.Annarcis:BAABNQAECn8dAAILAAYKngoKtADXAAALAAYKngoKtADXAAAAAA==.Antiman:BAAANQAECgQICAAAAA==.Anäster:BAABNQAECn8hAAIMAAgKdhblJAAJAgAMAAgKdhblJAAJAgAAAA==.',
Ao='Aoiris:BAAANQADCggIEAAAAA==.',
Ap='Aplcyder:BAABNQAECn8zAAMCAAoK5wyDJwCXAQACAAoK5wyDJwCXAQAEAAQKFwQybQBqAAAAAA==.Apocryphea:BAAANQAECggIEAAAAA==.',
Ar='Arabloom:BAAANQAECgUIBQAAAA==.Arachnid:BAABNQAECn8uAAIFAAkKLBzrLwB1AgAFAAkKLBzrLwB1AgAAAA==.Aradalon:BAABNQAECn8oAAINAAkKmyFNDwBRAwANAAkKmyFNDwBRAwAAAA==.Aratyn:BAABNQAECn8jAAIOAAgKWxRpDQDaAQAOAAgKWxRpDQDaAQAAAA==.Arianabelia:BAAANQADCgEIAQAAAA==.',
As='Asanot:BAAANQADCgQIBAAAAA==.Astranacht:BAABNQAECn87AAIEAAoKjw57KAClAQAEAAoKjw57KAClAQAAAA==.',
At='Atheneimeris:BAEANQAECgUIBgAAAA==.',
Au='Auntjemimma:BAABNQAECn8qAAIHAAkKQBMiiQAUAgAHAAkKQBMiiQAUAgAAAA==.Auriandra:BAAANQAECgQICAAAAA==.',
Ax='Axa:BAAANQADCggIHAAAAA==.',
Ay='Ayroonoo:BAAANQADCgQIBQAAAA==.',
Ba='Babyshoes:BAAANQAECgYIDQAAAA==.Backhawk:BAAANQAECgQIBAAAAA==.Backsurgery:BAABNQAECn8jAAQPAAkKNSAoEQDlAgAPAAkKNSAoEQDlAgAQAAIKhRaUiACQAAARAAIKEhKMFgB/AAABNQAFFAYIGAASAJ0jAA==.Baerrn:BAABNQAECn8XAAITAAYKCwP4aQDRAAATAAYKCwP4aQDRAAAAAA==.Baricia:BAABNQAECn8rAAIFAAoKpQvGogBMAQAFAAoKpQvGogBMAQAAAA==.Barrin:BAABNQAECn8tAAMUAAoK3xbmBwAYAgAUAAoK3xbmBwAYAgALAAIKSwCkQQE0AAAAAA==.Bawnchu:BAAANQADCggIGAAAAA==.',
Be='Beardad:BAAANQADCgcICQAAAA==.Bearded:BAABNQAECn8dAAIVAAoKYw8aDwAEAgAVAAoKYw8aDwAEAgAAAA==.Bearonica:BAEANQAFFAQIBAABNQAFFAQICgANAKwZAA==.Beastmaster:BAABNQAECn8yAAIKAAoKPh9xLgB6AgAKAAoKPh9xLgB6AgAAAA==.Beefcakell:BAAANQADCgMIBAAAAA==.Belthar:BAAANQAECgUIBgAAAA==.Bentlymage:BAACNQAFFH8HAAIFAAIKohcHMgCbAAAFAAIKohcHMgCbAAA1AAQKfzoAAgUACgqqIOopAIwCAAUACgqqIOopAIwCAAAA.',
Bi='Bissafiyah:BAACNQAFFH8dAAISAAgKjhw3AADKAgASAAgKjhw3AADKAgA1AAQKf0cAAhIACgptJsUAAHEDABIACgptJsUAAHEDAAAA.Bittertea:BAABNQAECn8YAAIWAAYKHwM1kQDBAAAWAAYKHwM1kQDBAAAAAA==.',
Bl='Blakdeath:BAABNQAECn8jAAIJAAgKLAwQUQBuAQAJAAgKLAwQUQBuAQAAAA==.Blargghh:BAAANQAECgYIBgAAAA==.Bloodgon:BAABNQAECn8bAAMIAAcKYRmVMgBIAQAIAAcKYRmVMgBIAQAWAAIKTA0mtABhAAAAAA==.Bloodvoid:BAAANQAECggICAAAAA==.Bluetuesday:BAAANQADCgYIBgAAAA==.',
Bo='Bobthedemon:BAAANQAECgYICQAAAA==.Bohica:BAAANQAECgQICAAAAA==.Boka:BAAANQADCgMIAgAAAA==.Bonechop:BAAANQADCgIIAgAAAA==.Bowseye:BAAANQAECgIIAgABNQAECgkJKgAHAEATAA==.Boyakasha:BAABNQAECn8iAAIRAAYKWgn1DwAkAQARAAYKWgn1DwAkAQAAAA==.',
Br='Brayne:BAAANQAECgYIDQAAAA==.Brewsome:BAABNQAECn9GAAIXAAoKEyIjBQBQAwAXAAoKEyIjBQBQAwAAAA==.Bricktamland:BAAANQAECgQIBAAAAA==.Brighthammer:BAAANQADCgcIDQAAAA==.Bryybryy:BAABNQAECn85AAIWAAkKEx6lHQABAgAWAAkKEx6lHQABAgAAAA==.Bryyguyy:BAAANQADCgIIAgABNQAECgkJOQAWABMeAA==.Bryythyr:BAAANQAECgUIBQABNQAECgkJOQAWABMeAA==.',
Bu='Bubleherth:BAAANQADCgcIFwAAAA==.Bullymayes:BAAANQABCgYIBgAAAA==.Bunkiee:BAAANQADCggIFgAAAA==.',
Ca='Calbee:BAAANQADCgYIBwAAAA==.Candorite:BAAANQAECgUJBwABNQAECggIHgAYAJoYAA==.Capcoms:BAAANQAECgUICwABNQAECgkJQAAFALsfAA==.Capita:BAABNQAECn80AAIOAAoKJg95DAC1AQAOAAoKJg95DAC1AQAAAA==.Carsinegan:BAABNQAECn8mAAMZAAcK6xEiFQCnAAAUAAQKIhC1GQC5AAAZAAUKHBMiFQCnAAAAAA==.Cassica:BAABNQAECn8dAAMMAAkKZxE+MQCZAQAMAAcK4hE+MQCZAQAaAAcKUhIFkQBjAQAAAA==.Catskin:BAAANQADCgYICQAAAA==.Causticminx:BAAANQABCgYIBwAAAA==.',
Ch='Chainlink:BAAANQADCgIIAgAAAA==.Charkle:BAABNQAECn8kAAIKAAYKFAvE1QDrAAAKAAYKFAvE1QDrAAAAAA==.Chillylilly:BAAANQAECggIEAAAAA==.Chummie:BAABNQAECn8oAAQLAAkKPR57XwA5AgALAAgKehx7XwA5AgAUAAIKbSIOGADMAAAZAAIK0xXkUACMAAAAAA==.Chuud:BAAANQAECgEIAQAAAA==.Cháotic:BAAANQADCgQIBAAAAA==.',
Ci='Ciandoril:BAAANQAECgYIEQABNQAECgkJNgAOAIsRAA==.Cid:BAAANQADCgQIBAAAAA==.',
Co='Comeanddie:BAAANQADCggIFAABNQADCgMIAwABAAAAAA==.',
Cr='Crazyeyes:BAAANQAECgYIEwABNQAECggIHQAEAAIJAA==.Crimsondeath:BAABNQAECn8iAAIWAAYKpxBJdAAlAQAWAAYKpxBJdAAlAQAAAA==.Crylecks:BAAANQAECgYIBgAAAA==.',
Cy='Cyclonian:BAAANQAECggICAABNQAECggIDwABAAAAAA==.Cylu:BAAANQADCggICwAAAA==.Cyprus:BAABNQAECn8pAAMCAAoKzhZHFgBSAgACAAoKzhZHFgBSAgAEAAEKAACctAAuAAAAAA==.',
Da='Daelric:BAAANQAECgEIAQAAAA==.Daender:BAABNQAECn8/AAIKAAoKhyL0GgAtAwAKAAoKhyL0GgAtAwAAAA==.Daenor:BAAANQAECgQIBAAAAA==.Daevie:BAABNQAECn8pAAIFAAoK0wdZsAAxAQAFAAoK0wdZsAAxAQAAAA==.Dairydemon:BAABNQAECn8+AAIbAAoKrAM1QQBEAQAbAAoKrAM1QQBEAQAAAA==.Damageus:BAACNQAFFH8GAAMOAAMK0R0CCwBgAAAFAAIKcBxiLQCtAAAOAAEKkyACCwBgAAA1AAQKfz4AAwUACgpcJPppAKoCAAUACQpLJPppAKoCAA4AAgp/JJYzAGwAAAAA.Damworg:BAABNQAECn8YAAIcAAcKuhJrnwAqAQAcAAcKuhJrnwAqAQAAAA==.Daniryl:BAEBNQAECn8lAAQEAAkKpBnfEwBwAgAEAAkKpBnfEwBwAgAdAAcKnw8gGQArAQACAAMKJAZ7XABvAAABNQAECgkJHgADAH0TAA==.Dar:BAABNQAECn9HAAIKAAoKThU2QgA9AgAKAAoKThU2QgA9AgAAAA==.Darcside:BAABNQAECn8eAAIMAAYKIg+IOgBTAQAMAAYKIg+IOgBTAQAAAA==.Daritar:BAEBNQAECn8eAAIDAAkKfRNJZAD0AQADAAkKfRNJZAD0AQAAAA==.Darkburtus:BAABNQAECn8sAAIbAAoKiAYtJgBTAQAbAAoKiAYtJgBTAQAAAA==.Darkfeatherr:BAAANQAECgIIBAAAAA==.Darkxwraith:BAABNQAECn9BAAQGAAoKHxp6DQBBAgAGAAoKHxp6DQBBAgANAAEK5ha54QBDAAAHAAEKCAoFpQE1AAAAAA==.Datsombeech:BAABNQAECn85AAIcAAkKggklhQBlAQAcAAkKggklhQBlAQAAAA==.',
De='Defhammer:BAAANQABCggIGAAAAA==.Deka:BAAANQADCgMIAwAAAA==.Deàdly:BAAANQADCgUJCgAAAA==.',
Dh='Dhaynk:BAABNQAECn9QAAMeAAoKsh/vAwCdAgAeAAoKlB/vAwCdAgAbAAoKABSHKAAAAgAAAA==.',
Di='Dianoia:BAAANQAECgQIBgABNQAFFAcIGwAZAH8YAA==.Didamus:BAAANQABCgMIAwAAAA==.Dingleding:BAAANQAECggIDAAAAA==.',
Dk='Dkanabiss:BAAANQADCgYIEAAAAA==.Dkinabox:BAAANQADCgYIBwAAAA==.',
Do='Docoo:BAABNQAECn8pAAIWAAoKRCPmFgD2AgAWAAoKRCPmFgD2AgAAAA==.Dogmeat:BAAANQABCgQICAAAAA==.Dominates:BAAANQAECggIDAAAAA==.',
Dr='Drasilia:BAAANQADCggICAAAAA==.Dreu:BAAANQADCgUIBwABNQAFFAcIFwAbAOMUAA==.Drewserk:BAABNQAECn85AAIcAAoKHhV3UAD6AQAcAAoKHhV3UAD6AQAAAA==.Driten:BAABNQAECn9AAAIFAAkKux9KQwA1AgAFAAkKux9KQwA1AgAAAA==.Drocsid:BAAANQAECggIDwABNQAECgoKPAAHAMQjAA==.Drpiscisphd:BAAANQAECgEIAQABNQAECgoKQQAQAAQjAA==.Drsaltyballz:BAAANQAECgIIAgAAAA==.Drspoon:BAABNQAECn8uAAIWAAoKfRjUPgAFAgAWAAoKfRjUPgAFAgAAAA==.Drugpala:BAAANQAECgEJAwAAAA==.Drumuss:BAAANQAECgMIBQAAAA==.',
Ds='Dsancho:BAAANQAECgYIDAAAAA==.',
Du='Ducat:BAAANQAECgYICgAAAA==.Dudley:BAAANQAECgMIBAAAAA==.Duffun:BAABNQAECn8oAAIFAAgKERstVgABAgAFAAgKERstVgABAgABNQAECgoKSwAfABslAA==.Duffunha:BAABNQAECn9LAAMfAAoKGyWwAABHAwAfAAoKGyWwAABHAwAKAAUKhSD4YADsAQAAAA==.Durto:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.',
Dy='Dyre:BAAANQAECgQICAAAAA==.Dyslexic:BAAANQAECgUIDAABNQAFFAUICwAHALMHAA==.Dyspepsia:BAACNQAFFH8LAAIHAAUKswdjJQB3AAAHAAUKswdjJQB3AAA1AAQKfyQAAgcACgq+EzF5AMcBAAcACgq+EzF5AMcBAAAA.',
['Dõ']='Dõngus:BAAANQADCgYIBgABNQAECggIDwABAAAAAA==.',
Ed='Edelgard:BAAANQAECgEIAgAAAA==.Edie:BAAANQAECgEIAQAAAA==.',
Ei='Eirenn:BAAANQAECggICAAAAA==.',
El='Eleaornu:BAABNQAECn80AAMNAAoKsxr4LACzAgANAAoKsxr4LACzAgAHAAcKIQZ4+ADgAAAAAA==.Elimee:BAABNQAECn89AAIFAAoKDiRrHQBiAwAFAAoKDiRrHQBiAwAAAA==.Ellasia:BAAANQABCgMIAwAAAA==.Elvenbane:BAABNQAECn8YAAIEAAYKjAboegDgAAAEAAYKjAboegDgAAAAAA==.',
Em='Emart:BAAANQAECgQICAAAAA==.',
Er='Erayna:BAABNQAECn8wAAICAAoKQAyBJwCXAQACAAoKQAyBJwCXAQAAAA==.',
Es='Essence:BAABNQAECn8uAAIFAAoKuRdpOABZAgAFAAoKuRdpOABZAgAAAA==.',
Et='Etherious:BAAANQADCgUICwABNQADCggICwABAAAAAA==.',
Ev='Evelinah:BAAANQAECggIEAAAAA==.Evïe:BAAANQAECgEIBAABNQAECgoKPQAFAA4kAA==.',
Ex='Explode:BAAANQAECggICwABNQAFFAYICAAYAIoGAA==.',
Fa='Falconclaw:BAAANQADCggIIQAAAA==.Falkensnoman:BAAANQAECgQICAAAAA==.Fayedra:BAABNQAECn8lAAIgAAgKRhScHQCzAQAgAAgKRhScHQCzAQAAAA==.',
Fe='Feenii:BAABNQAECn9AAAISAAoKIxOIDgAZAgASAAoKIxOIDgAZAgAAAA==.',
Fi='Figgyandrii:BAAANQAECgYIBgAAAA==.Fizzlelich:BAAANQADCggINAAAAA==.',
Fo='Foxdeer:BAABNQAECn8bAAILAAcK4AhR2AAZAQALAAcK4AhR2AAZAQAAAA==.Foxmachina:BAAANQAECgYIBQAAAA==.Foxxmccloud:BAAANQADCgIJAgABNQAECgoKLAAEAKQfAA==.',
Fu='Fungies:BAABNQAECn9HAAMLAAoK1BeBPAARAgALAAoKhhWBPAARAgAUAAQKphazDwAkAQAAAA==.Furybest:BAAANQAECgcICQAAAA==.',
Ga='Gannir:BAAANQAECgEIAQAAAA==.Gano:BAAANQADCgQIBwAAAA==.Gatlokal:BAAANQADCggIAgAAAA==.Gatman:BAAANQADCgYICQAAAA==.',
Gi='Gimiltockel:BAAANQADCgUIBwAAAA==.Giramar:BAABNQAECn8YAAIMAAgKpwr+JwAtAQAMAAgKpwr+JwAtAQAAAA==.',
Go='Gochujang:BAAANQAECgQIBAABNQAFFAIIBgADAF8QAA==.Gojo:BAEANQAECgEIAwAAAA==.Goldeelock:BAAANQADCggIDQAAAA==.Gotchya:BAAANQABCgEIAQAAAA==.Goteem:BAAANQAECgUIBwAAAA==.Gothitelle:BAAANQAECgEIAQAAAA==.',
Gr='Grandad:BAAANQAECgQIDwAAAA==.Grandest:BAAANQADCgQIBAAAAA==.Grantaire:BAAANQADCggIEgAAAA==.Grimmdogg:BAAANQAECgMIAwAAAA==.Grimrox:BAABNQAECn8mAAIDAAkKMhKxSgCUAQADAAkKMhKxSgCUAQAAAA==.Grombo:BAAANQAECgQICAAAAA==.',
Gu='Guano:BAAANQAECgMIAwAAAA==.',
Ha='Haanit:BAAANQADCgIIAgAAAA==.Hakela:BAAANQAECgEIAQAAAA==.Hardlyevoker:BAAANQADCgMIAwABNQAECgkJOQANAHohAA==.',
He='Healingwave:BAAANQADCgYIBgAAAA==.Hearnê:BAAANQADCgIIAQAAAA==.Heavyarm:BAAANQADCgEIAQAAAA==.Heethen:BAAANQAECgUICQAAAA==.Hexbox:BAABNQAECn8bAAMYAAkKohefcAC6AQAYAAgKGRqfcAC6AQADAAcKHg8xhwCSAQAAAA==.',
Hi='Himawari:BAABNQAECn8sAAQhAAkKHxMSEQCPAQAhAAgKHxMSEQCPAQAiAAEKAABKMwA1AAAcAAIKIwdRIAE1AAAAAA==.',
Ho='Hoffmin:BAABNQAECn83AAMbAAoKdx5PDgAEAwAbAAkKFyFPDgAEAwATAAEKGgyckQA3AAAAAA==.Holemeister:BAACNQAFFH8GAAIHAAMKcBbTEADtAAAHAAMKcBbTEADtAAA1AAQKf0EAAgcACgoBJDszAP8CAAcACgoBJDszAP8CAAAA.Holyamin:BAAANQAECgQICAAAAA==.Holymann:BAABNQAECn8UAAIMAAYKzwtuMQDqAAAMAAYKzwtuMQDqAAAAAA==.Holyschnikey:BAABNQAECn81AAINAAkKWxPaUgC3AQANAAkKWxPaUgC3AQAAAA==.Holyz:BAABNQAECn8sAAINAAkKBSRhCQB/AwANAAkKBSRhCQB/AwAAAA==.Horgable:BAAANQADCgEIAQAAAA==.Horrorpops:BAABNQAECn8dAAILAAoKZxRXOgAZAgALAAoKZxRXOgAZAgABNQAECgoKPwAKAIciAA==.',
Hu='Hudfin:BAAANQAECgQIBAAAAA==.Hugginz:BAAANQADCgYIEgAAAA==.Hunzul:BAAANQADCggIDAAAAA==.Hurzal:BAAANQAECgUIBAAAAA==.',
Hy='Hypnototem:BAAANQAECgEIAQAAAA==.',
['Hè']='Hèimdall:BAABNQAECn8mAAIGAAgK7QnPLQD1AAAGAAgK7QnPLQD1AAAAAA==.',
['Hí']='Hílthaen:BAABNQAECn8wAAIaAAkKDh/3LgCsAgAaAAkKDh/3LgCsAgAAAA==.',
Ic='Icehead:BAAANQAECgQIAwAAAA==.Ichigokisu:BAAANQAECggIBAAAAA==.',
Ih='Ihavenobrain:BAAANQABCgIIAgAAAA==.',
Il='Illy:BAABNQAECn8dAAIbAAgKTxCMKgDtAQAbAAgKTxCMKgDtAQAAAA==.',
In='Instantdeath:BAAANQADCgMIAwAAAA==.Invali:BAAANQAECgEIAQAAAA==.',
Is='Ishivyounot:BAAANQADCgUICgAAAA==.',
Iv='Ivranda:BAABNQAECn8eAAIYAAgKmhhDRgDjAQAYAAgKmhhDRgDjAQAAAA==.',
Ix='Ixio:BAAANQADCgYIBgAAAA==.',
Ja='Jahan:BAACNQAFFH8HAAIaAAIKJB+cJACnAAAaAAIKJB+cJACnAAA1AAQKf0IAAxoACgpbJLIHAIcDABoACgoGI7IHAIcDACMABwpdHu8EAG0CAAE1AAQKBAgEAAEAAAAA.Jamie:BAABNQAECn8VAAMWAAcKgSSLKQB2AgAWAAYKgSSLKQB2AgAIAAEKAADP4AAzAAABNQAFFAgIEAALAPEiAA==.Jarek:BAAANQABCgQIBAAAAA==.',
Je='Jegra:BAABNQAECn8sAAIkAAoKGh2wDwBNAgAkAAoKGh2wDwBNAgAAAA==.Jerith:BAABNQAECn8sAAMQAAkKUwyqEwCLAQAQAAkKUwyqEwCLAQAPAAYKPwWqNAAVAQAAAA==.Jerryy:BAEANQADCgEIAgABNQAECgEIAwABAAAAAA==.Jessilyn:BAAANQADCggIGAAAAA==.',
Ji='Jigari:BAAANQADCgcIDgAAAA==.Jinxed:BAAANQAECgMIAwAAAA==.',
Jo='Jord:BAAANQAECgQIBAAAAA==.',
Ju='Jubellina:BAABNQAECn83AAIXAAoKmw9DHAC/AQAXAAoKmw9DHAC/AQAAAA==.Jubîlee:BAAANQABCgIIAgAAAA==.',
['Jà']='Jàzz:BAAANQADCggIJgAAAA==.',
Ka='Kaelora:BAAANQADCgYICQAAAA==.Kaerei:BAAANQADCgQIBAAAAA==.Kaleb:BAECNQAFFH8NAAITAAUKghZFDQA7AQATAAUKghZFDQA7AQA1AAQKf1IAAhMACgrAJMMDAE0DABMACgrAJMMDAE0DAAAA.Kalferno:BAAANQAECgUIDwAAAA==.Kalirkaz:BAACNQAFFH8FAAICAAQKKghVCwDnAAACAAQKKghVCwDnAAA1AAQKfx4AAgIACgqwENgcAAECAAIACgqwENgcAAECAAE1AAQKCgoxABgA8R0A.Kayotica:BAAANQAECgUICwAAAA==.',
Ke='Keensmite:BAAANQAECgQIBAAAAA==.Kendall:BAAANQAECgQIBAABNQAECgoKJAAJABETAA==.',
Kh='Khallock:BAABNQAECn8bAAIUAAoK8gvFCQCcAQAUAAoK8gvFCQCcAQAAAA==.',
Ki='Kiemen:BAABNQAECn8kAAMJAAoKERNGJwAKAgAJAAoKERNGJwAKAgAIAAYK7ApShAAOAQAAAA==.Killko:BAABNQAECn8bAAMJAAgK6RBuRACwAQAJAAgK6RBuRACwAQAIAAIKpQrVyABaAAAAAA==.Kirisen:BAAANQAECgIIAwAAAA==.',
Kn='Knardan:BAABNQAECn8yAAIKAAkK/x+OVwBsAgAKAAkK/x+OVwBsAgAAAA==.',
Ko='Kotanx:BAAANQADCggIEQAAAA==.',
Kr='Kragsloor:BAAANQADCggICwAAAA==.Krickette:BAAANQAECgQIBAABNQAECgoKMAACAEAMAA==.',
Ku='Kuraki:BAABNQAECn8lAAIkAAgKRQzMIwBkAQAkAAgKRQzMIwBkAQAAAA==.',
Ky='Kyriea:BAAANQADCgYIBgAAAA==.',
La='Ladrar:BAAANQAECgIIAwAAAA==.Lanadiel:BAABNQAECn86AAIGAAoKzyFlCgD0AgAGAAoKzyFlCgD0AgAAAA==.Lasalghoul:BAAANQAECggIDgAAAA==.Lassyn:BAAANQAECggICAABNQAECggIDgABAAAAAA==.',
Le='Legend:BAABNQAECn8VAAIWAAgK2BUzUgCsAQAWAAgK2BUzUgCsAQAAAA==.Len:BAABNQAECn8yAAMYAAoK3xPCWQADAgAYAAkKzhLCWQADAgADAAcKQQx8yAABAQAAAA==.Leoñidas:BAAANQAECgYIDgAAAA==.',
Li='Lian:BAAANQAECgQIBQAAAA==.Lianda:BAAANQAECggICAAAAA==.Lianse:BAAANQADCgYICwAAAA==.Liliara:BAABNQAECn8/AAIKAAoKJRniMgBqAgAKAAoKJRniMgBqAgAAAA==.Lillyirl:BAAANQAECgEIAQAAAA==.Lillymae:BAABNQAECn8aAAIbAAkKGSLXDgD+AgAbAAkKGSLXDgD+AgAAAA==.Lillyslight:BAAANQAECgQIBAAAAA==.Lillytae:BAAANQADCgYIBgAAAA==.Lillyvani:BAAANQAECgQIBAAAAA==.Lilmoo:BAABNQAECn8UAAIKAAYKggVBCQH0AAAKAAYKggVBCQH0AAAAAA==.Lilpump:BAAANQAECgQICQABNQAECgoKLgAWAH0YAA==.Lindalinda:BAAANQADCgEIAQAAAA==.Linkhunter:BAAANQAECgUIDQABNQAECgoKQAAjALwhAA==.Linkmônk:BAAANQADCgcICgABNQAECgoKQAAjALwhAA==.',
Lo='Lodise:BAABNQAECn81AAIUAAoKpxFHBwDgAQAUAAoKpxFHBwDgAQAAAA==.Lorzz:BAABNQAECn9CAAIaAAoKaR17JADaAgAaAAoKaR17JADaAgAAAA==.Loveydovey:BAAANQADCgIIAgAAAA==.',
Lu='Lucrio:BAABNQAECn87AAIIAAoKyhYkFgAsAgAIAAoKyhYkFgAsAgAAAA==.Ludlow:BAAANQADCgMIAwABNQAECgoKLwAQAO0TAA==.Lunalai:BAAANQAECgQIBAAAAA==.Lurim:BAABNQAECn8xAAIgAAoKKSAPBgAzAwAgAAoKKSAPBgAzAwAAAA==.Lushy:BAABNQAECn9GAAIPAAoKIhcZKgBGAgAPAAoKIhcZKgBGAgAAAA==.',
Ly='Lylindara:BAABNQAECn8ZAAIYAAgKJgjDkwBWAQAYAAgKJgjDkwBWAQAAAA==.Lylinette:BAAANQADCggIDwAAAA==.',
['Ló']='Lókï:BAAANQADCgEIAQAAAA==.',
Ma='Madgorilla:BAAANQADCgUIBQAAAA==.Mageofdeath:BAABNQAECn8/AAMOAAoKqxPLCAAIAgAOAAkKqxPLCAAIAgAFAAgKqAqvKQFGAQABNQADCgMIAwABAAAAAA==.Mageskin:BAAANQAECgQICQAAAA==.Maladaptive:BAAANQADCgYIDwAAAA==.Manerva:BAAANQADCggIJgAAAA==.Mastorcheef:BAAANQADCgQIBAAAAA==.Mattsdruid:BAAANQAECgMIBAAAAA==.Maurin:BAAANQAECggIDgAAAA==.Maximumhonk:BAABNQAECn80AAIYAAoKxBeNPQAJAgAYAAoKxBeNPQAJAgAAAA==.Maxonoa:BAAANQADCggJFwAAAA==.Maxximos:BAAANQAECgIIAgAAAA==.',
Me='Mekkadaddy:BAABNQAECn8mAAIKAAkK7RN9kAB5AQAKAAkK7RN9kAB5AQAAAA==.Mellow:BAAANQAECgMIAwAAAA==.Mendelia:BAABNQAECn8nAAIGAAkKtRM8HwBfAQAGAAkKtRM8HwBfAQAAAA==.Mercus:BAABNQAECn8jAAMPAAgKyA9aIgC4AQAPAAcKVg9aIgC4AQAQAAcKvA43RwCoAQAAAA==.Merllinna:BAAANQABCgIIAQAAAA==.Mervenious:BAABNQAECn8vAAMcAAoKTQr8fwByAQAcAAoKIQr8fwByAQAhAAUKvgr2JgCvAAAAAA==.',
Mi='Mindplague:BAABNQAECn8yAAIMAAcKChpoJQAEAgAMAAcKChpoJQAEAgAAAA==.Minipincin:BAAANQAECgUIBQAAAA==.Minmzey:BAAANQAECgQIBgAAAA==.Miroslava:BAAANQAECgUICQAAAA==.Missfire:BAABNQAECn8XAAIKAAgKwg/KjwB6AQAKAAgKwg/KjwB6AQABNQAECgoKKQACAM4WAA==.',
Mk='Mkaye:BAAANQAECgIIBAAAAA==.',
Mo='Moggle:BAABNQAECn8YAAIFAAYKiAcNOwEqAQAFAAYKiAcNOwEqAQAAAA==.Mondazi:BAABNQAECn9GAAMDAAoKrB3uGACWAgADAAoKrB3uGACWAgAYAAoK+A7NaADSAQAAAA==.Moonlilly:BAAANQADCgIIAgAAAA==.Morfy:BAAANQABCggIBgAAAA==.Morgzim:BAAANQADCgYJBwAAAA==.Moustaccio:BAAANQAECgEIAgAAAA==.Mozarta:BAAANQABCggIDQAAAA==.',
Ms='Msmanalow:BAAANQAECgEIAQABNQAECgoKKQACAM4WAA==.',
My='Mycen:BAABNQAECn8XAAILAAgKbgw7kQC7AQALAAgKbgw7kQC7AQAAAA==.Myeyesburn:BAAANQAECgMJBAAAAA==.',
['Má']='Málaketh:BAAANQAECggIDwAAAA==.',
Na='Nardena:BAAANQAECgIIAQAAAA==.Narz:BAABNQAECn9JAAIKAAoKTxInRQA1AgAKAAoKTxInRQA1AgAAAA==.Naughtypine:BAAANQADCgYIBgAAAA==.Naylz:BAAANQAECggIAQAAAA==.',
Nd='Ndiz:BAAANQAECgUIBAAAAA==.',
Ne='Necronomikon:BAABNQAECn8fAAIFAAgKxgzq9ACiAQAFAAgKxgzq9ACiAQAAAA==.Nemasis:BAAANQADCggICAABNQAECgoKQAAKAHYOAA==.Nerhzul:BAAANQADCgUIBQAAAA==.Neromoo:BAAANQAECgUIDQABNQAECgoKKQAVAPsSAA==.Neruphuyt:BAABNQAECn8dAAIEAAgKAgnkXABdAQAEAAgKAgnkXABdAQAAAA==.',
Ni='Niath:BAAANQAECgUIDgAAAA==.Nightheal:BAAANQABCgQIBQABNQAECgoKKQAWAEQjAA==.Nightsniper:BAAANQAECgEIAQABNQAECgoKKQAWAEQjAA==.',
No='Notdinor:BAAANQADCgIIAgAAAA==.Notlilly:BAABNQAECn8oAAIhAAkKoBEeFQDVAQAhAAkKoBEeFQDVAQAAAA==.Notpillows:BAAANQAECgEIAQAAAA==.',
Ny='Nyxelle:BAAANQAECgIIAwAAAA==.',
['Nä']='Närz:BAAANQADCggIBQAAAA==.',
['Nò']='Nòvà:BAAANQAECgcIEAAAAA==.',
Oi='Oilfu:BAAANQADCgUIBQABNQAECgoKRgAPACIXAA==.',
Ok='Okioni:BAAANQAECgUIBQAAAA==.',
Ol='Olgon:BAACNQAFFH8JAAIKAAIKmAxFIQCRAAAKAAIKmAxFIQCRAAA1AAQKf00AAgoACgqHGsonAJICAAoACgqHGsonAJICAAAA.',
Op='Oprhawinfury:BAABNQAECn8jAAIIAAkKkQt3bABhAQAIAAkKkQt3bABhAQAAAA==.',
Or='Orgodemir:BAABNQAECn8lAAIaAAgKliVNGAADAwAaAAgKliVNGAADAwAAAA==.Orhamin:BAAANQADCgYIDwAAAA==.',
Os='Oshani:BAAANQAECggIEAAAAA==.',
Ou='Outlaw:BAAANQADCgcIBwAAAA==.',
Pa='Pacolyte:BAAANQAECgQIBgAAAA==.Paigor:BAAANQABCgIIAgAAAA==.Palathene:BAABNQAECn8vAAMHAAoKxyB2IwDJAgAHAAoKxyB2IwDJAgAGAAQKnR0wNABCAQAAAA==.Pallystorm:BAAANQAECgYICAABNQAECgkJFgAUAK4HAA==.Palmike:BAAANQADCgYIBgAAAA==.Pandemonia:BAABNQAECn87AAILAAkKYxK4dQABAgALAAkKYxK4dQABAgAAAA==.Parsie:BAAANQAECgYIEQAAAA==.Pathibas:BAAANQADCggIDQABNQAECgoKOwAiAJYgAA==.Pattycakes:BAABNQAECn8pAAIIAAkKRQ77KgB6AQAIAAkKRQ77KgB6AQAAAA==.',
Pe='Pericø:BAAANQADCgQIBAAAAA==.',
Ph='Pherocious:BAAANQAECgQIBQAAAA==.',
Pi='Pinktuesday:BAAANQADCggICAAAAA==.Pixeleen:BAACNQAFFH8KAAIKAAUKEg/ACQA8AQAKAAUKEg/ACQA8AQA1AAQKfzwAAwoACgpeIswmAPwCAAoACgpeIswmAPwCACUABQrfCvJMAP4AAAAA.',
Pl='Plexy:BAABNQAECn8gAAMaAAkKYSDbIQDnAgAaAAkKuh/bIQDnAgAjAAcK8hlaCADhAQAAAA==.',
Po='Pokitz:BAABNQAECn8nAAIHAAkKHwc8xQA0AQAHAAkKHwc8xQA0AQAAAA==.',
Pr='Primordinor:BAABNQAECn82AAIDAAkKgx2kKwAbAgADAAkKgx2kKwAbAgAAAA==.Probnotalive:BAABNQAECn8+AAIKAAoK/x0pFwA+AwAKAAoK/x0pFwA+AwAAAA==.Probnoturmom:BAABNQAECn80AAIaAAkKVR5ZLQCzAgAaAAkKVR5ZLQCzAgAAAA==.',
Pu='Puab:BAAANQAECgYIBAABNQAECgoKPAAHAMQjAA==.',
Qu='Quacko:BAAANQAECgUICQABNQAECgoKMQAgACkgAA==.Quietus:BAAANQADCgcICwAAAA==.',
Ra='Raevyn:BAAANQAECgIIAQAAAA==.Raikai:BAAANQAECgEIAwABNQAECgoKNAANALMaAA==.Rakan:BAABNQAECn9IAAMhAAoKcR+vBADKAgAhAAoKcR+vBADKAgAcAAUKeQ2M6AAUAQAAAA==.Rallick:BAACNQAFFH8HAAINAAIKhQalHgB3AAANAAIKhQalHgB3AAA1AAQKfz0AAg0ACgovGH0iAJ0CAA0ACgovGH0iAJ0CAAAA.Ranì:BAABNQAECn86AAMhAAoKxxbMCwDxAQAhAAoKxxbMCwDxAQAiAAEKfAfoMgAvAAAAAA==.Rathger:BAAANQADCgUICAAAAA==.Ratmilk:BAAANQAECgcIDAAAAA==.Razkhan:BAAANQADCgcIDQAAAA==.',
Rd='Rdk:BAAANQAECgMIBAAAAA==.',
Re='Redek:BAAANQADCgcICgAAAA==.Reft:BAAANQABCgEIAQAAAA==.Reighna:BAAANQADCggIDQAAAA==.Rendcurse:BAAANQADCgEIAQAAAA==.Rendwee:BAABNQAECn9FAAIdAAoKeSHwBADBAgAdAAoKeSHwBADBAgAAAA==.Reps:BAAANQAECggICgAAAA==.Retiredaggro:BAAANQAECgUIDgAAAA==.Retiredghoul:BAAANQADCgUIBQAAAA==.Retiredlight:BAAANQADCgEIAQAAAA==.Rewolf:BAAANQAECgUIEwAAAA==.',
Rh='Rhynar:BAAANQAECggICAAAAA==.',
Ri='Ricflairion:BAABNQAECn82AAImAAoK9gqaCQBnAQAmAAoK9gqaCQBnAQAAAA==.Rill:BAAANQADCggICwAAAA==.',
Ro='Rodcet:BAABNQAECn88AAIHAAoKxCNNGQD1AgAHAAoKxCNNGQD1AgAAAA==.Roflbubble:BAABNQAECn85AAMaAAkKshQsWADFAQAaAAkKshQsWADFAQAMAAUKdAWqVQC2AAAAAA==.Rognan:BAAANQAECgQIBAAAAA==.Roku:BAAANQAECgcICAAAAA==.Ronkin:BAAANQADCggIJAAAAA==.Rookgue:BAABNQAECn9GAAIQAAoKRBNUCwANAgAQAAoKRBNUCwANAgAAAA==.Rookoker:BAABNQAECn8ZAAInAAcKCQXQFgC6AAAnAAcKCQXQFgC6AAAAAA==.Rorygazer:BAABNQAECn8YAAIhAAYKDCIZEAAnAgAhAAYKDCIZEAAnAgAAAA==.Rosmerta:BAAANQAECgIIAQAAAA==.Rossa:BAAANQABCgIIAgAAAA==.Rossdair:BAAANQAECgQIDAABNQAECgcIDgABAAAAAA==.Rossperot:BAABNQAECn8bAAIIAAcKLh10SgDsAQAIAAcKLh10SgDsAQAAAA==.',
Ry='Ryk:BAABNQAECn8VAAIQAAoKTBoqBwB7AgAQAAoKTBoqBwB7AgAAAA==.',
Sa='Saarin:BAAANQAECgQIAwAAAA==.Saelara:BAAANQAECgQIBQAAAA==.Sairal:BAAANQAECggIEAAAAA==.Saltytuesday:BAAANQADCgYICQAAAA==.Samgee:BAACNQAFFH8ZAAIHAAUK4RoCEQA+AQAHAAUK4RoCEQA+AQA1AAQKf0AAAgcACgrFIPQzAP0CAAcACgrFIPQzAP0CAAAA.Sanguathene:BAEANQAECgQIAwABNQAECgUIBgABAAAAAA==.Sawlty:BAABNQAECn8kAAIlAAoKxwwYMADNAQAlAAoKxwwYMADNAQAAAA==.Saynar:BAABNQAECn84AAMbAAoKuyJwCADHAgAbAAoKuyJwCADHAgAeAAIKRR1VJgCHAAAAAA==.',
Sc='Scattered:BAABNQAECn8pAAMZAAoKqw4MJwA+AQAZAAYKqQsMJwA+AQALAAcKeQ51pwDzAAAAAA==.Schecter:BAABNQAECn8YAAMYAAcKJyOUMQCaAgAYAAcKJyOUMQCaAgADAAEKCxj0KQE/AAAAAA==.Scintila:BAAANQADCgQIBAABNQAECgkJOwALAGMSAA==.Scooti:BAAANQADCggIEAABNQAECgYIDAABAAAAAA==.',
Se='Seba:BAACNQAFFH8HAAIFAAIKoAqAOACCAAAFAAIKoAqAOACCAAA1AAQKf1oAAgUACgoYH2UnAJYCAAUACgoYH2UnAJYCAAAA.Sehren:BAAANQADCgcIBgAAAA==.Sehtrak:BAAANQADCggICAAAAA==.Selesne:BAABNQAECn8lAAIRAAgKiQuWBABIAQARAAgKiQuWBABIAQAAAA==.Seniandrays:BAAANQADCgQIBAAAAA==.Serannia:BAAANQADCgIIAgAAAA==.Seraphicktwo:BAABNQAECn8aAAMMAAgKRgzpPQA9AQAMAAgKRgzpPQA9AQAaAAEKTgYI/gAvAAAAAA==.',
Sh='Shadowtrance:BAAANQAECgEIAQABNQAECgoKQQAGAB8aAA==.Shaggmz:BAABNQAECn8hAAIiAAYKoxDwFwAgAQAiAAYKoxDwFwAgAQAAAA==.Shawnkin:BAAANQADCgIIAgAAAA==.Shelyn:BAAANQAECgcICAAAAA==.Shinma:BAABNQAECn8iAAIGAAYKZAZGQwDmAAAGAAYKZAZGQwDmAAAAAA==.Shootermcgee:BAAANQAECgIIAgAAAA==.Showtootsies:BAAANQADCgUJBQAAAA==.Shrubbery:BAAANQAECgQIBwAAAA==.Shymary:BAABNQAECn8iAAMjAAYKVROMCwDLAAAaAAYKVRNDdQBjAQAjAAYKCgeMCwDLAAAAAA==.',
Si='Siete:BAAANQADCgYJBwAAAA==.Silëx:BAABNQAECn8iAAIOAAkKNRWsDgC/AQAOAAkKNRWsDgC/AQAAAA==.Sindiz:BAAANQAECgYIDgAAAA==.Sioc:BAAANQAECgMIAwAAAA==.Siouxiesioux:BAAANQAECgQIBgAAAA==.',
Sk='Skadie:BAAANQAECgYICQAAAA==.Skoot:BAAANQAECgYIDAAAAA==.',
Sl='Slimjimz:BAAANQADCgUIBQAAAA==.Slugondeez:BAABNQAECn85AAMNAAkKeiFNJwDMAgANAAkKeiFNJwDMAgAGAAIKUyMyTwCqAAAAAA==.',
Sm='Smitefist:BAAANQAECgIIAQABNQAECggIDwABAAAAAA==.',
Sn='Snkyturtle:BAABNQAECn9AAAIKAAoKdg6ygQAJAgAKAAoKdg6ygQAJAgAAAA==.Snoopdogydog:BAAANQABCgcIBgAAAA==.Snuzzle:BAABNQAECn8vAAIgAAkKJBkYFAAjAgAgAAkKJBkYFAAjAgAAAA==.',
So='Sourmash:BAAANQAECgQIBAAAAA==.',
Sp='Spaghet:BAABNQAECn8bAAIDAAkKHQ1rggCfAQADAAkKHQ1rggCfAQAAAA==.Spillthetea:BAAANQADCggICQABNQAECgYIGAAWAB8DAA==.Spittoon:BAAANQADCgEJAQABNQADCggIIAABAAAAAA==.Sploot:BAABNQAECn8hAAILAAoKhRyMQQCNAgALAAoKhRyMQQCNAgAAAA==.',
Sr='Srasjet:BAAANQAECgQICAAAAA==.',
Ss='Ssarmandok:BAABNQAECn8bAAIHAAoKQBfAkQCUAQAHAAoKQBfAkQCUAQAAAA==.',
St='Stabytha:BAAANQAECggIDQAAAA==.Stark:BAAANQABCgQIBAAAAA==.Starlight:BAABNQAECn8kAAMCAAoKxR0hDwDjAgACAAoKxR0hDwDjAgAEAAYKzxTUVQC2AAAAAA==.Stealthed:BAABNQAECn8VAAIgAAUKuRBwRwCNAAAgAAUKuRBwRwCNAAAAAA==.Stender:BAAANQADCgIIAgABNQAFFAIICQATAH8eAA==.Stonegoddess:BAAANQADCgQIBAAAAA==.Stormcall:BAABNQAECn8aAAIYAAYKmR1sXACNAQAYAAYKmR1sXACNAQAAAA==.Stratusfied:BAAANQADCgIIAgAAAA==.Strongsad:BAAANQAECgIIAwAAAA==.',
Sw='Swiss:BAABNQAECn8eAAIDAAgKoA50gACjAQADAAgKoA50gACjAQAAAA==.',
Sy='Syldra:BAAANQABCgIIAgAAAA==.',
['Sá']='Sáëgárón:BAAANQAECgMIBAAAAA==.',
Ta='Taliden:BAAANQAECgQICwAAAA==.Tankinstine:BAAANQADCgYIBwAAAA==.Tanksmalls:BAAANQADCgQIBAAAAA==.Taraylda:BAABNQAECn8eAAMMAAkK5RhTFwDZAQAMAAkK5RhTFwDZAQAaAAEK2yEZ8gBOAAAAAA==.Tarz:BAAANQAECgYIDgAAAA==.Tazzwolfsong:BAAANQADCgEIAQAAAA==.',
Te='Tecdor:BAAANQADCgYJBgAAAA==.Teronfiggy:BAABNQAECn8ZAAIJAAkKRQdUXwApAQAJAAkKRQdUXwApAQAAAA==.',
Tf='Tfirs:BAAANQAECgUIBwABNQABCgUIAwABAAAAAA==.',
Th='Thehealczar:BAAANQAECgcIDwABNQAECgoKKQAWAEQjAA==.Theokoles:BAAANQAECggIDwAAAA==.Thesenate:BAAANQADCggIDwABNQAECgoKQAASACMTAA==.Thickblòód:BAABNQAECn8WAAIHAAoK5A/sdwDKAQAHAAoK5A/sdwDKAQAAAA==.Thordurin:BAAANQAECgYIBgAAAA==.Thorly:BAAANQADCgYIDQAAAA==.Thrazi:BAAANQAECgMICAAAAA==.',
Ti='Tiadalma:BAAANQAECgIIAgAAAA==.Tinn:BAAANQADCggIEAAAAA==.',
To='Toospookie:BAAANQADCgYIDgAAAA==.Totem:BAAANQAECgQIBgAAAA==.',
Tr='Tramplip:BAABNQAECn8jAAIZAAkK4Q3DBgBaAQAZAAkK4Q3DBgBaAQAAAA==.Treecloud:BAABNQAECn86AAMgAAoKMyGMBwDDAgAgAAoKMyGMBwDDAgAEAAEKMxH7fwA6AAAAAA==.Treferimore:BAABNQAECn8eAAIKAAYK8g+ByAAGAQAKAAYK8g+ByAAGAQAAAA==.Trevian:BAABNQAECn8lAAIHAAgKFA9IpgBrAQAHAAgKFA9IpgBrAQAAAA==.',
Tu='Tulimyrsky:BAAANQADCgUIBQAAAA==.Tuluxxi:BAABNQAECn8/AAMYAAoK4yLlGgAEAwAYAAoK4yLlGgAEAwADAAgK4g49dADEAQAAAA==.Tutter:BAAANQAECgUICwAAAA==.',
Tw='Twopumpchump:BAABNQAECn8sAAIoAAoKVBCsCQCYAQAoAAoKVBCsCQCYAQAAAA==.',
Tz='Tzxdh:BAAANQAECgIIAgABNQAECggIGQAGAH8VAA==.Tzxdruid:BAAANQAECgIIAgABNQAECggIGQAGAH8VAA==.',
Ug='Uglymancer:BAABNQAECn8qAAILAAoKnBZmOAAfAgALAAoKnBZmOAAfAgAAAA==.',
Uj='Ujimas:BAABNQAECn8eAAIDAAYKcRYjagAxAQADAAYKcRYjagAxAQAAAA==.',
Ut='Uthodne:BAAANQAECgEIAQABNQAECgoKLwAQAO0TAA==.',
Va='Vampireshade:BAABNQAECn84AAMQAAkKmA3pGQBNAQAQAAkKmA3pGQBNAQARAAYK/gMzEgDlAAAAAA==.Vampirevoid:BAAANQAECgcIBQAAAA==.Vampírella:BAAANQADCgIIAgAAAA==.Vanililly:BAABNQAECn8rAAIWAAkK8A2+NgBcAQAWAAkK8A2+NgBcAQAAAA==.Vanimao:BAAANQAECgEIAQAAAA==.Varan:BAAANQAECgUIBwAAAA==.',
Vb='Vbull:BAAANQAECgEIAQAAAA==.',
Ve='Velissari:BAABNQAECn8WAAITAAYKXA5fTQDaAAATAAYKXA5fTQDaAAAAAA==.Venatra:BAAANQADCgYICAAAAA==.Veritus:BAABNQAECn8rAAITAAkKfB4AHQCxAgATAAkKfB4AHQCxAgAAAA==.',
Vi='Vindict:BAAANQAECgQICAAAAA==.Violette:BAABNQAECn8uAAIKAAkKbw5fdQC4AQAKAAkKbw5fdQC4AQAAAA==.Vion:BAAANQABCgQIBAAAAA==.',
Vo='Voidlink:BAABNQAECn9AAAMjAAoKvCH2AABOAwAjAAoKvCH2AABOAwAMAAcKeBILHgCGAQAAAA==.Voidstriker:BAAANQAECgEIAQAAAA==.Vovim:BAAANQAECgIIAgAAAA==.',
Wa='Wackyrellek:BAABNQAECn8sAAMQAAoKdh0hDwDIAQAQAAkKdh0hDwDIAQAPAAkKQxCYSQC/AQAAAA==.Wakancer:BAABNQAECn8VAAIUAAUKQw8KEgAqAQAUAAUKQw8KEgAqAQAAAA==.Wakarisma:BAAANQAECgEIAQAAAA==.Wakataclysm:BAAANQAECgUICwAAAA==.Walnut:BAABNQAECn8XAAIgAAoKYyDvBQDsAgAgAAoKYyDvBQDsAgABNQAFFAIIBgADAF8QAA==.Warchylde:BAAANQADCgQIBgAAAA==.Warolderoy:BAABNQAECn87AAMiAAoKliAHBQDbAgAiAAoKPSAHBQDbAgAhAAYKShyAFwC0AQAAAA==.',
We='Weedshaman:BAAANQADCgcJBwAAAA==.Weil:BAAANQAECgYICQAAAA==.',
Wi='Willowsprout:BAAANQABCgMIBAAAAA==.',
Wo='Woker:BAAANQAECgYICQABNQAECgoKQAASACMTAA==.Woogie:BAAANQAECgQIBwAAAA==.Worthy:BAAANQAECgMIAwAAAA==.Woyer:BAAANQADCgEIAQAAAA==.',
Wu='Wummie:BAAANQAECgMIAwABNQAECgkJKAALAD0eAA==.',
['Wò']='Wòógie:BAAANQADCgYIBgABNQAECgQIBwABAAAAAA==.',
Xa='Xader:BAAANQADCggIEAAAAA==.Xanneral:BAEANQAECgUIBgABNQAECgoKNwAJADMaAA==.',
Xe='Xenna:BAAANQAECgYIDgABNQAECgkJKgAHAEATAA==.Xeq:BAAANQAECgMIAwAAAA==.',
Ye='Yeoman:BAABNQAECn8cAAIiAAkKcBEkEQBNAQAiAAkKcBEkEQBNAQAAAA==.Yewko:BAAANQAECgYIEwAAAA==.',
Yg='Yggdralith:BAAANQAECggIJgAAAQ==.',
Yi='Yibble:BAAANQAECgUIBQABNQAFFAQIDgAcANkeAA==.',
Yo='Yobagoya:BAAANQAECgEIAQAAAA==.',
Yu='Yukionne:BAAANQAECgIIAQAAAA==.Yunohealme:BAABNQAECn8aAAIJAAcK/Rn6MwAOAgAJAAcK/Rn6MwAOAgAAAA==.Yunosmall:BAAANQADCgMIAwAAAA==.Yunosmart:BAAANQADCgMIBAAAAA==.',
Yz='Yzerman:BAAANQAECgIIAgABNQAECgoKJAAJABETAA==.',
['Yö']='Yör:BAAANQADCgEIAQAAAA==.',
Za='Zaen:BAACNQAFFH8JAAMLAAIKOBKnJACTAAALAAIKkA+nJACTAAAZAAEKsA3xEgBFAAA1AAQKf0sAAxkACgrDITUGAGoBAAsACgpHIZ4kAPICABkABgoPHzUGAGoBAAAA.Zanapheia:BAAANQADCgIIAgABNQAECgoKQAAKAHYOAA==.Zandre:BAABNQAECn8pAAIhAAoKyBimEwDrAQAhAAoKyBimEwDrAQAAAA==.Zarkir:BAACNQAFFH8HAAIWAAIKVyK9EwC+AAAWAAIKVyK9EwC+AAA1AAQKfzMAAxYACgpEIxINAEgDABYACgpEIxINAEgDAAkAAQrACTeqADcAAAAA.',
Ze='Zelily:BAABNQAECn83AAIKAAoKxQ2vhAACAgAKAAoKxQ2vhAACAgAAAA==.Zenarri:BAAANQADCgYICgAAAA==.Zepha:BAAANQABCgEIAQAAAA==.',
Zh='Zharvakko:BAABNQAECn81AAMYAAoKmBc5RwDfAQAYAAoKmBc5RwDfAQADAAcKrhBlhACaAQABNQAECgoKMQAYAPEdAA==.Zhiana:BAABNQAECn8cAAMOAAgKQxFHDgDHAQAFAAgKOwxj3gDLAQAOAAgK7A1HDgDHAQAAAA==.',
Zu='Zugzok:BAAANQAECgMIAwAAAA==.Zulrich:BAAANQAECgYICwAAAA==.',
Zv='Zvirae:BAAANQAECgUIBQAAAA==.Zvirax:BAAANQADCggIKQABNQAECgUIBQABAAAAAA==.',
['Ás']='Ástrid:BAAANQAECgEIAQAAAA==.',
['Ëu']='Ëuni:BAAANQADCgQIBAAAAA==.',
['Ìs']='Ìsaac:BAAANQAECgYJEgAAAA==.',
['Ðo']='Ðolm:BAAANQAECgQIBgAAAA==.',
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
