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

local lookup = {'Unknown-Unknown','Druid-Restoration','Shaman-Elemental','Druid-Balance','Paladin-Protection','DeathKnight-Unholy','DeathKnight-Frost','Hunter-BeastMastery','Paladin-Retribution','Warlock-Demonology','Priest-Shadow','Mage-Arcane','Paladin-Holy','Mage-Frost','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Shaman-Enhancement','DemonHunter-Havoc','Warlock-Affliction','Evoker-Preservation','DeathKnight-Blood','Monk-Mistweaver','Shaman-Restoration','Warlock-Destruction','Priest-Holy','DemonHunter-Devourer','Warrior-Arms','Druid-Feral','DemonHunter-Vengeance','Hunter-Survival','Druid-Guardian','Warrior-Protection','Warrior-Fury','Priest-Discipline','Monk-Windwalker','Hunter-Marksmanship','Evoker-Augmentation','Monk-Brewmaster',}
local provider = {region='US',realm='Bloodhoof',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Aberforthd:BAAANQAECgUIDgABNQAECgYIBgABAAAAAA==.',
Ac='Aceforlife:BAAANQADCggIEAABNQAECgkJSQACAFkSAA==.Acorn:BAACNQAFFH8GAAIDAAIKXxBHGACNAAADAAIKXxBHGACNAAA1AAQKfy0AAgMACgqzHtYfAA0DAAMACgqzHtYfAA0DAAAA.',
Ad='Aditu:BAABNQAECn8mAAMCAAgKfxOmNQBuAQACAAYKEhSmNQBuAQAEAAgKcgzWOwAKAQAAAA==.',
Ae='Aetheris:BAABNQAECn8YAAIFAAgKNhXYLAB2AQAFAAgKNhXYLAB2AQAAAA==.',
Ag='Agasonex:BAAANQADCgUIBAAAAA==.',
Ah='Ahziz:BAABNQAECn8YAAMGAAYKERCbdwA7AQAGAAYKERCbdwA7AQAHAAUKpwe6bACxAAAAAA==.',
Ai='Airent:BAABNQAECn8aAAMEAAYKRA+aSADOAAAEAAYKRA+aSADOAAACAAQK7QYLaABlAAAAAA==.',
Aj='Aja:BAAANQAECggICgABNQAFFAQIBQAIAKwEAA==.',
Ak='Akatosh:BAAANQAECgEIAgAAAA==.',
Al='Alaestel:BAABNQAECn8/AAIJAAoKRQ03fgCQAQAJAAoKRQ03fgCQAQAAAA==.Aletheia:BAAANQAECgQIBAAAAA==.Alt:BAAANQAECgIIBAAAAA==.',
An='Ancane:BAAANQADCggICAAAAA==.Andramealoch:BAAANQADCgEIAQAAAA==.Angina:BAAANQADCgUIBwAAAA==.Angrywoogie:BAAANQADCgEIAQABNQAECgQIBwABAAAAAA==.Annarcis:BAABNQAECn8YAAIKAAYKngodpADYAAAKAAYKngodpADYAAAAAA==.Antiman:BAAANQAECgQICAAAAA==.Anäster:BAABNQAECn8hAAILAAgKdhblJAAJAgALAAgKdhblJAAJAgAAAA==.',
Ao='Aoiris:BAAANQADCggIEAAAAA==.',
Ap='Aplcyder:BAABNQAECn8uAAMCAAoKqQyqJgBwAQACAAoKqQyqJgBwAQAEAAQKFwROZQBrAAAAAA==.Apocryphea:BAAANQAECgYIEQAAAA==.',
Ar='Arabloom:BAAANQADCgYIBgAAAA==.Arachnid:BAABNQAECn8oAAIMAAkKlhuQMQBcAgAMAAkKlhuQMQBcAgAAAA==.Aradalon:BAABNQAECn8oAAINAAkKmyFNDwBRAwANAAkKmyFNDwBRAwAAAA==.Aratyn:BAABNQAECn8fAAIOAAcKFBVpDQDaAQAOAAcKFBVpDQDaAQAAAA==.Arianabelia:BAAANQADCgEIAQAAAA==.',
As='Asanot:BAAANQADCgQIBAAAAA==.Astranacht:BAABNQAECn87AAIEAAoKjw71IwCmAQAEAAoKjw71IwCmAQAAAA==.',
Au='Auntjemimma:BAABNQAECn8qAAIJAAkKQBMiiQAUAgAJAAkKQBMiiQAUAgAAAA==.Auriandra:BAAANQAECgQICAAAAA==.',
Ax='Axa:BAAANQADCggIHAAAAA==.',
Ay='Ayroonoo:BAAANQADCgMIAwAAAA==.',
Ba='Babyshoes:BAAANQAECgYIEAAAAA==.Backhawk:BAAANQAECgQIBAAAAA==.Backsurgery:BAABNQAECn8jAAQPAAkKNSA/DwDiAgAPAAkKNSA/DwDiAgAQAAIKhRaUiACQAAARAAIKEhKMFgB/AAABNQAFFAYIGAASAJ0jAA==.Baerrn:BAABNQAECn8XAAITAAYKCwP4aQDRAAATAAYKCwP4aQDRAAAAAA==.Baricia:BAABNQAECn8rAAIMAAoKpQsflQBOAQAMAAoKpQsflQBOAQAAAA==.Barrin:BAABNQAECn8qAAMUAAkKGhfmBwAYAgAUAAkKGhfmBwAYAgAKAAIKSwCkQQE0AAAAAA==.Bawnchu:BAAANQADCggIGAAAAA==.',
Be='Beardad:BAAANQADCgcICQAAAA==.Bearded:BAABNQAECn8cAAIVAAkKgRD6DgDdAQAVAAkKgRD6DgDdAQAAAA==.Bearonica:BAEANQAECggIDgABNQAFFAQICgANAKwZAA==.Beastmaster:BAABNQAECn8rAAIIAAoKOh7HMgDUAgAIAAoKOh7HMgDUAgAAAA==.Beefcakell:BAAANQADCgMIBAAAAA==.Belthar:BAAANQAECgUIBwAAAA==.Bentlymage:BAACNQAFFH8HAAIMAAIKohfrKwCfAAAMAAIKohfrKwCfAAA1AAQKfzEAAgwACgokH99XANACAAwACgokH99XANACAAAA.',
Bi='Bissafiyah:BAACNQAFFH8bAAISAAcKQh43AADKAgASAAcKQh43AADKAgA1AAQKf0YAAhIACgptJoQAAHgDABIACgptJoQAAHgDAAAA.Bittertea:BAABNQAECn8YAAIWAAYKHwM1kQDBAAAWAAYKHwM1kQDBAAAAAA==.',
Bl='Blakdeath:BAABNQAECn8fAAIHAAcKrQwQUQBuAQAHAAcKrQwQUQBuAQAAAA==.Blargghh:BAAANQAECgYIBgAAAA==.Bloodgon:BAABNQAECn8bAAMGAAcKYRnzLABOAQAGAAcKYRnzLABOAQAWAAIKTA0mtABhAAAAAA==.Bloodpriests:BAAANQAECgcIDgAAAA==.Bluetuesday:BAAANQADCgYIBgAAAA==.',
Bo='Bobthedemon:BAAANQAECgIIAwAAAA==.Bohica:BAAANQAECgQICAAAAA==.Boka:BAAANQADCgMIAgAAAA==.Bonechop:BAAANQADCgIIAgAAAA==.Bowseye:BAAANQAECgIIAgABNQAECgkJKgAJAEATAA==.Boyakasha:BAABNQAECn8cAAIRAAYKPQn1DwAkAQARAAYKPQn1DwAkAQAAAA==.',
Br='Brayne:BAAANQAECgUIDQAAAA==.Brewsome:BAABNQAECn9BAAIXAAoKEyIjBQBQAwAXAAoKEyIjBQBQAwAAAA==.Brighthammer:BAAANQADCgcIDQAAAA==.Bryybryy:BAABNQAECn82AAIWAAkKbB3+GwDzAQAWAAkKbB3+GwDzAQAAAA==.Bryyguyy:BAAANQADCgIIAgABNQAECgkJNgAWAGwdAA==.Bryythyr:BAAANQADCgQIBAABNQAECgkJNgAWAGwdAA==.',
Bu='Bubleherth:BAAANQADCgcIFwAAAA==.Bullymayes:BAAANQAECgEIAQAAAA==.Bunkiee:BAAANQADCggIFgAAAA==.',
Ca='Calbee:BAAANQADCgYIBwAAAA==.Candorite:BAAANQAECgUJBwABNQAECgcIGgAYANsYAA==.Candra:BAAANQAECgEIAwAAAA==.Capcoms:BAAANQAECgUIDAABNQAECgkJPQAMAH0eAA==.Capita:BAABNQAECn8zAAIOAAkKww+XDACGAQAOAAkKww+XDACGAQAAAA==.Carsinegan:BAABNQAECn8gAAMZAAcK6xFwEgCrAAAUAAQKIhC1GQC5AAAZAAUKHBNwEgCrAAAAAA==.Cassica:BAABNQAECn8dAAMLAAkKZxE+MQCZAQALAAcK4hE+MQCZAQAaAAcKUhIFkQBjAQAAAA==.Catskin:BAAANQADCgYICQAAAA==.Causticminx:BAAANQABCgYIBwAAAA==.',
Ch='Chainlink:BAAANQADCgIIAgAAAA==.Charkle:BAABNQAECn8cAAIIAAYKCQnlAAEDAQAIAAYKCQnlAAEDAQAAAA==.Chillylilly:BAAANQAECggIEAAAAA==.Chummie:BAABNQAECn8oAAQKAAkKPR57XwA5AgAKAAgKehx7XwA5AgAUAAIKbSIOGADMAAAZAAIK0xXkUACMAAAAAA==.Chuud:BAAANQADCgQIBAAAAA==.',
Ci='Ciandoril:BAAANQAECgYIEAABNQAECgkJNgAOAJIRAA==.Cid:BAAANQADCgQIBAAAAA==.',
Co='Comeanddie:BAAANQADCggIFAABNQADCgMIAwABAAAAAA==.',
Cr='Crazyeyes:BAAANQAECgYIDgABNQAECggIHQAEAAIJAA==.Crimsondeath:BAABNQAECn8cAAIWAAYKpxBJdAAlAQAWAAYKpxBJdAAlAQAAAA==.Crylecks:BAAANQAECgYIBgAAAA==.',
Cy='Cyclonian:BAAANQAECggICAABNQAECggIDwABAAAAAA==.Cylu:BAAANQADCggICwAAAA==.Cyprus:BAABNQAECn8lAAMCAAoK5BRiHADTAQACAAoK5BRiHADTAQAEAAEKAACctAAuAAAAAA==.',
Da='Daelric:BAAANQAECgEIAQAAAA==.Daender:BAABNQAECn8+AAIIAAoKhyK2FADXAgAIAAoKhyK2FADXAgAAAA==.Daenor:BAAANQAECgQIBAAAAA==.Daevie:BAABNQAECn8oAAIMAAoK0wdkogAzAQAMAAoK0wdkogAzAQAAAA==.Dairydemon:BAABNQAECn83AAIbAAoKhQM1QQBEAQAbAAoKhQM1QQBEAQAAAA==.Damageus:BAABNQAECn86AAMMAAoKoCP6aQCqAgAMAAkKcyP6aQCqAgAOAAIKfySWMwBsAAAAAA==.Damworg:BAABNQAECn8WAAIcAAcKuhIWkAAqAQAcAAcKuhIWkAAqAQAAAA==.Daniryl:BAEBNQAECn8cAAQEAAkKUxWHFwAjAgAEAAkKRxWHFwAjAgAdAAcKnw8uFQAuAQACAAMKJAYPVQBrAAABNQAECgkJHgADAH0TAA==.Dar:BAABNQAECn8+AAIIAAoKiBMHXADLAQAIAAoKiBMHXADLAQAAAA==.Darcside:BAABNQAECn8YAAILAAYK8g6IOgBTAQALAAYK8g6IOgBTAQAAAA==.Daritar:BAEBNQAECn8eAAIDAAkKfRNJZAD0AQADAAkKfRNJZAD0AQAAAA==.Darkburtus:BAABNQAECn8jAAIbAAoKgwUhJwAnAQAbAAoKgwUhJwAnAQAAAA==.Darkfeatherr:BAAANQAECgIIBAAAAA==.Darkxwraith:BAABNQAECn84AAQFAAoKGBkPDQAoAgAFAAoKGBkPDQAoAgANAAEK5hbJ0wBDAAAJAAEKCAoFpQE1AAAAAA==.Datsombeech:BAABNQAECn82AAIcAAkK0QhZfQBXAQAcAAkK0QhZfQBXAQAAAA==.',
De='Defhammer:BAAANQABCggIGAAAAA==.Deka:BAAANQADCgMIAwAAAA==.Deàdly:BAAANQADCgUJCgAAAA==.',
Dh='Dhaynk:BAABNQAECn9PAAMeAAoKih+2BABUAgAeAAkKFyC2BABUAgAbAAoKABSWHACMAQAAAA==.',
Di='Dianoia:BAAANQAECgQIBwABNQAFFAcIGwAZAH8YAA==.Didamus:BAAANQABCgMIAwAAAA==.Dingleding:BAAANQAECggIEAAAAA==.',
Dk='Dkanabiss:BAAANQADCgYIEAAAAA==.Dkinabox:BAAANQADCgYIBwAAAA==.',
Do='Docoo:BAABNQAECn8oAAIWAAkKzSPmFgD2AgAWAAkKzSPmFgD2AgAAAA==.Dogmeat:BAAANQABCgQICAAAAA==.Dominates:BAAANQAECggIDAAAAA==.Dookey:BAAANQAECgEIAgAAAA==.',
Dr='Dreu:BAAANQADCgUIBwABNQAFFAYIFgAbAAQUAA==.Drewserk:BAABNQAECn85AAIcAAoKHhWhRQAAAgAcAAoKHhWhRQAAAgAAAA==.Driten:BAABNQAECn89AAIMAAkKfR75RAAZAgAMAAkKfR75RAAZAgAAAA==.Drocsid:BAAANQAECggIEQABNQAECgoKPAAJAMQjAA==.Drpiscisphd:BAAANQAECgEIAgABNQAECgoKPwAQAAQjAA==.Drsaltyballz:BAAANQAECgIIAgAAAA==.Drspoon:BAABNQAECn8uAAIWAAoKfRhSLQB0AQAWAAoKfRhSLQB0AQAAAA==.Drugpala:BAAANQAECgEJAwAAAA==.Drumuss:BAAANQAECgMIBQAAAA==.',
Ds='Dsancho:BAAANQAECgYIDAAAAA==.',
Du='Ducat:BAAANQAECgYICgAAAA==.Dudley:BAAANQAECgMIBAAAAA==.Duffun:BAABNQAECn8oAAIMAAgKERs3TAAEAgAMAAgKERs3TAAEAgABNQAECgoKRgAfABslAA==.Duffunha:BAABNQAECn9GAAMfAAoKGyWIAABVAwAfAAoKGyWIAABVAwAIAAEKZhgaGAFOAAAAAA==.Durto:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.',
Dy='Dyre:BAAANQAECgQICAAAAA==.Dyslexic:BAAANQAECgUIDAABNQAFFAUICwAJALMHAA==.Dyspepsia:BAACNQAFFH8LAAIJAAUKswfUIAB4AAAJAAUKswfUIAB4AAA1AAQKfyMAAgkACgq+E66FABwCAAkACgq+E66FABwCAAAA.',
['Dõ']='Dõngus:BAAANQADCgYIBgABNQAECggIDwABAAAAAA==.',
Ed='Edelgard:BAAANQAECgEIAgAAAA==.Edie:BAAANQAECgIIAwAAAA==.',
Ei='Eirenn:BAAANQAECggICgAAAA==.',
El='Eleaornu:BAABNQAECn8tAAINAAoKsxr4LACzAgANAAoKsxr4LACzAgAAAA==.Elimee:BAABNQAECn89AAIMAAoKDiRrHQBiAwAMAAoKDiRrHQBiAwAAAA==.Elipsis:BAAANQAECgIIAgAAAA==.Ellasia:BAAANQABCgMIAwAAAA==.Elvenbane:BAABNQAECn8YAAIEAAYKjAboegDgAAAEAAYKjAboegDgAAAAAA==.',
Em='Emart:BAAANQAECgQICAAAAA==.',
Er='Erayna:BAABNQAECn8wAAICAAoKQAx6IgCUAQACAAoKQAx6IgCUAQAAAA==.',
Es='Essence:BAABNQAECn8pAAIMAAoKuRepMQBbAgAMAAoKuRepMQBbAgAAAA==.',
Et='Etherious:BAAANQADCgUICwABNQADCggICwABAAAAAA==.',
Ev='Evedruid:BAAANQAECggIAQAAAA==.Evehunter:BAAANQAECggIAQAAAA==.Evelinah:BAABNQAECn8UAAMaAAoKZABj5wAoAAAaAAkKOABj5wAoAAALAAEKAAC/ZwAAAAAAAA==.Evepaladin:BAAANQAECggIAgAAAA==.Eveshaman:BAAANQAECgEIAQAAAA==.Evïe:BAAANQAECgEIBgABNQAECgoKPQAMAA4kAA==.',
Ex='Explode:BAAANQAECggIDAABNQAECgoKHAAYAHwYAA==.',
Fa='Falconclaw:BAAANQADCggIIQAAAA==.Falkensnoman:BAAANQAECgQICAAAAA==.Fayedra:BAABNQAECn8hAAIgAAcKCxWcHQCzAQAgAAcKCxWcHQCzAQAAAA==.',
Fe='Feenii:BAABNQAECn88AAISAAoKlRL2DAATAgASAAoKlRL2DAATAgAAAA==.',
Fi='Figgyandrii:BAAANQAECgYICQAAAA==.Fizzlelich:BAAANQADCggILwAAAA==.',
Fo='Foxdeer:BAABNQAECn8bAAIKAAcK4Ah4pgDTAAAKAAcK4Ah4pgDTAAAAAA==.Foxmachina:BAAANQAECgYIBgAAAA==.Foxxmccloud:BAAANQADCgIJAgABNQAECgoKLAAEAKQfAA==.',
Fu='Fungies:BAABNQAECn9CAAIKAAoKhhUQNQANAgAKAAoKhhUQNQANAgAAAA==.Furybest:BAAANQAECgcICQAAAA==.Furyrage:BAAANQAECgEIAQAAAA==.',
Ga='Gannir:BAAANQAECgEIAQAAAA==.Gano:BAAANQADCgQIBwAAAA==.Gatlokal:BAAANQADCggIAgAAAA==.Gatman:BAAANQADCgYICQAAAA==.',
Gi='Gimiltockel:BAAANQADCgUIBwAAAA==.Giramar:BAABNQAECn8YAAILAAgKpwpiIwAuAQALAAgKpwpiIwAuAQAAAA==.',
Go='Gochujang:BAAANQAECgQIBAABNQAFFAIIBgADAF8QAA==.Gojo:BAEANQAECgEIAwAAAA==.Goldeelock:BAAANQADCggIDQAAAA==.Gotchya:BAAANQABCgEIAQAAAA==.Goteem:BAAANQAECgUIBwAAAA==.Gothitelle:BAAANQAECgEIAgAAAA==.',
Gr='Grandad:BAAANQAECgQICwAAAA==.Grandest:BAAANQADCgQIBAAAAA==.Grantaire:BAAANQADCggIEgAAAA==.Grimmdogg:BAAANQAECgMIAwAAAA==.Grimrox:BAABNQAECn8kAAIDAAgKfRKzTgBjAQADAAgKfRKzTgBjAQAAAA==.Grombo:BAAANQAECgQICAAAAA==.',
Gu='Guano:BAAANQAECgEIAQAAAA==.',
Ha='Haanit:BAAANQADCgIIAgAAAA==.Hakela:BAAANQAECgEJAQAAAA==.Hardlyevoker:BAAANQADCgMIAwABNQAECgkJOAANAHohAA==.',
He='Healingwave:BAAANQADCgYIBgAAAA==.Hearnê:BAAANQADCgIIAQAAAA==.Heavyarm:BAAANQADCgEIAQAAAA==.Heethen:BAAANQAECgUICQAAAA==.Hexbox:BAABNQAECn8bAAMYAAkKohefcAC6AQAYAAgKGRqfcAC6AQADAAcKHg8xhwCSAQAAAA==.',
Hi='Himawari:BAABNQAECn8oAAQhAAgKeRPcEgBPAQAhAAcKeRPcEgBPAQAcAAIKIwdSDwE2AAAiAAEKAABKMwA1AAAAAA==.',
Ho='Hoffmin:BAABNQAECn83AAMbAAoKdx5PDgAEAwAbAAkKFyFPDgAEAwATAAEKGgyckQA3AAAAAA==.Holemeister:BAABNQAECn89AAIJAAoKASQ7MwD/AgAJAAoKASQ7MwD/AgAAAA==.Holyamin:BAAANQAECgQICAAAAA==.Holymann:BAAANQAECgUIDwAAAA==.Holyschnikey:BAABNQAECn80AAINAAgKnBSTZwDhAQANAAgKnBSTZwDhAQAAAA==.Holyz:BAABNQAECn8qAAINAAgKeyR/DgApAwANAAgKeyR/DgApAwAAAA==.Horgable:BAAANQADCgEIAQAAAA==.Horrorpops:BAABNQAECn8XAAIKAAoKVBSmNwACAgAKAAoKVBSmNwACAgABNQAECgoKPgAIAIciAA==.',
Hu='Hudfin:BAAANQADCgYIBgAAAA==.Hugginz:BAAANQADCgYIEgAAAA==.Hunzul:BAAANQADCggIDAAAAA==.Hurzal:BAAANQAECgUIBQAAAA==.',
Hy='Hypnototem:BAAANQAECgEIAQAAAA==.',
['Hè']='Hèimdall:BAABNQAECn8lAAIFAAgK7QngJwD+AAAFAAgK7QngJwD+AAAAAA==.',
['Hí']='Hílthaen:BAABNQAECn8tAAIaAAkKDh/3LgCsAgAaAAkKDh/3LgCsAgAAAA==.',
Ic='Icehead:BAAANQAECgQIAwAAAA==.Ichigokisu:BAAANQAECggIBQAAAA==.',
Ih='Ihavenobrain:BAAANQABCgIIAgAAAA==.',
Il='Illy:BAABNQAECn8dAAIbAAgKTxCMKgDtAQAbAAgKTxCMKgDtAQAAAA==.',
In='Instantdeath:BAAANQADCgMIAwAAAA==.Invali:BAAANQAECgEIAQAAAA==.',
Is='Ishivyounot:BAAANQADCgUICgAAAA==.',
Iv='Ivranda:BAABNQAECn8aAAIYAAcK2xjRYgDlAQAYAAcK2xjRYgDlAQAAAA==.',
Ix='Ixio:BAAANQADCgYIBgAAAA==.',
Ja='Jahan:BAACNQAFFH8HAAIaAAIKJB8hIACrAAAaAAIKJB8hIACrAAA1AAQKfzkAAxoACgpbJLIHAIcDABoACgoGI7IHAIcDACMABwpdHu8EAG0CAAE1AAQKBAgEAAEAAAAA.Jamie:BAABNQAECn8VAAMWAAcKgSSLKQB2AgAWAAYKgSSLKQB2AgAGAAEKAADP4AAzAAABNQAFFAgIEAAKAPEiAA==.Jarek:BAAANQABCgQIBAAAAA==.',
Je='Jegra:BAABNQAECn8sAAIkAAoKGh3TDQBRAgAkAAoKGh3TDQBRAgAAAA==.Jerith:BAABNQAECn8sAAMQAAkKUwzQEQCPAQAQAAkKUwzQEQCPAQAPAAYKPwWqNAAVAQAAAA==.Jerryy:BAEANQADCgEIAgABNQAECgEIAwABAAAAAA==.Jessilyn:BAAANQADCggIGAAAAA==.',
Ji='Jigari:BAAANQADCgcIDgAAAA==.Jinxed:BAAANQAECgMIAwAAAA==.',
Jo='Jord:BAAANQAECgQIBAAAAA==.',
Ju='Jubellina:BAABNQAECn81AAIXAAoKbg9DHAC/AQAXAAoKbg9DHAC/AQAAAA==.Jubîlee:BAAANQABCgIIAgAAAA==.Julianos:BAAANQAECgIIAwAAAA==.',
['Jà']='Jàzz:BAAANQADCggIJgAAAA==.',
Ka='Kaelora:BAAANQADCgYICQAAAA==.Kaerei:BAAANQADCgQIBAAAAA==.Kaleb:BAECNQAFFH8NAAITAAUKghZFDQA7AQATAAUKghZFDQA7AQA1AAQKf0cAAhMACgo1JLYGAIsDABMACgo1JLYGAIsDAAAA.Kalferno:BAAANQAECgYIDAAAAA==.Kalirkaz:BAABNQAECn8aAAICAAoKeQ0FHQDMAQACAAoKeQ0FHQDMAQABNQAECgoKLQAYAPEdAA==.Kayotica:BAAANQAECgUICQAAAA==.',
Ke='Keensmite:BAAANQAECgQIBAAAAA==.Kendall:BAAANQAECgQIBAABNQAECgoKHwAHAAsRAA==.',
Kh='Khallock:BAABNQAECn8YAAIUAAgKKA7pCgBKAQAUAAgKKA7pCgBKAQAAAA==.',
Ki='Kiemen:BAABNQAECn8fAAMHAAoKCxHFJQDsAQAHAAoKCxHFJQDsAQAGAAYK7ApShAAOAQAAAA==.Killko:BAABNQAECn8bAAMHAAgK6RBuRACwAQAHAAgK6RBuRACwAQAGAAIKpQrVyABaAAAAAA==.Kirisen:BAAANQAECgIIAwAAAA==.',
Kn='Knardan:BAABNQAECn8vAAIIAAkKhR+OVwBsAgAIAAkKhR+OVwBsAgAAAA==.',
Ko='Kotanx:BAAANQADCggIEQAAAA==.',
Kr='Kragsloor:BAAANQADCggICwAAAA==.Krickette:BAAANQAECgEIAgABNQAECgoKMAACAEAMAA==.',
Ku='Kuraki:BAABNQAECn8hAAIkAAcKUQvAKQAUAQAkAAcKUQvAKQAUAQAAAA==.',
Ky='Kyriea:BAAANQADCgYIBgAAAA==.',
La='Ladrar:BAAANQAECgIIAwAAAA==.Lanadiel:BAABNQAECn84AAIFAAoKiSFrCACRAgAFAAoKiSFrCACRAgAAAA==.Lasalghoul:BAAANQAECggIDgAAAA==.Lassyn:BAAANQAECggICQABNQAECggIDgABAAAAAA==.',
Le='Legend:BAABNQAECn8VAAIWAAgK2BUzUgCsAQAWAAgK2BUzUgCsAQAAAA==.Len:BAABNQAECn8yAAMYAAoK3xPCWQADAgAYAAkKzhLCWQADAgADAAcKQQyplACpAAAAAA==.Leoñidas:BAAANQAECgYIDgAAAA==.',
Li='Lian:BAAANQAECgQIBQAAAA==.Lianda:BAAANQAECggICAAAAA==.Lianse:BAAANQADCgYICwAAAA==.Liliara:BAABNQAECn86AAIIAAoKdRhLMQBQAgAIAAoKdRhLMQBQAgAAAA==.Lillyirl:BAAANQAECgEIAQAAAA==.Lillymae:BAABNQAECn8aAAIbAAkKGSLXDgD+AgAbAAkKGSLXDgD+AgAAAA==.Lillyslight:BAAANQADCgUIBQAAAA==.Lillytae:BAAANQADCgYIBgAAAA==.Lillyvani:BAAANQAECgQIBAAAAA==.Lilmoo:BAABNQAECn8UAAIIAAYKggUU6QCfAAAIAAYKggUU6QCfAAAAAA==.Lilpump:BAAANQAECgQICQABNQAECgoKLgAWAH0YAA==.Lindalinda:BAAANQADCgEIAQAAAA==.Linkhunter:BAAANQAECgUIDwABNQAECgoKPAAjALwhAA==.Linkmônk:BAAANQADCgcICgABNQAECgoKPAAjALwhAA==.',
Lo='Lodise:BAABNQAECn80AAIUAAkKrRF0BwCpAQAUAAkKrRF0BwCpAQAAAA==.Lorzz:BAABNQAECn85AAIaAAoK/xx7JADaAgAaAAoK/xx7JADaAgAAAA==.Loveydovey:BAAANQADCgIIAgAAAA==.',
Lu='Lucrio:BAABNQAECn83AAIGAAkKQRbtGQDnAQAGAAkKQRbtGQDnAQAAAA==.Ludlow:BAAANQADCgMIAwABNQAECgoKLwAQAO0TAA==.Lunalai:BAAANQAECgQIBAAAAA==.Lurim:BAABNQAECn8wAAIgAAoKKSAPBgAzAwAgAAoKKSAPBgAzAwAAAA==.Lushy:BAABNQAECn8/AAIPAAoKKBWEKwAaAgAPAAoKKBWEKwAaAgAAAA==.',
Ly='Lylindara:BAABNQAECn8ZAAIYAAgKJgjDkwBWAQAYAAgKJgjDkwBWAQAAAA==.Lylinette:BAAANQADCggIDwAAAA==.',
['Ló']='Lókï:BAAANQADCgEIAQAAAA==.',
Ma='Madgorilla:BAAANQADCgUIBQAAAA==.Mageofdeath:BAABNQAECn82AAMOAAoKCBO/CQDGAQAOAAgKyBO/CQDGAQAMAAgKqAqvKQFGAQABNQADCgMIAwABAAAAAA==.Mageskin:BAAANQAECgQICQAAAA==.Maladaptive:BAAANQADCgYIDwAAAA==.Manerva:BAAANQADCggIJgAAAA==.Mastorcheef:BAAANQADCgQIBAAAAA==.Mattsdruid:BAAANQAECgMIBAAAAA==.Maurin:BAAANQAECggIDQAAAA==.Maximumhonk:BAABNQAECn8zAAIYAAkKcRlvPQDvAQAYAAkKcRlvPQDvAQAAAA==.Maxonoa:BAAANQADCggJFwAAAA==.Maxximos:BAAANQAECgIIAgAAAA==.',
Me='Mekkadaddy:BAABNQAECn8hAAIIAAkKWhPGpQC6AQAIAAkKWhPGpQC6AQAAAA==.Mellow:BAAANQAECgMIAwAAAA==.Mendelia:BAABNQAECn8mAAIFAAgKLhTCJgCoAQAFAAgKLhTCJgCoAQAAAA==.Mercus:BAABNQAECn8jAAMPAAgKyA9aIgC4AQAPAAcKVg9aIgC4AQAQAAcKvA43RwCoAQAAAA==.Merllinna:BAAANQABCgIIAQAAAA==.Mervenious:BAABNQAECn8oAAMcAAoK4QlYdQBrAQAcAAoK4QlYdQBrAQAhAAIKrglbPABUAAAAAA==.',
Mi='Mindplague:BAABNQAECn8rAAILAAYKqRxoJQAEAgALAAYKqRxoJQAEAgAAAA==.Minipincin:BAAANQAECgUIBQAAAA==.Minmzey:BAAANQAECgQIBwAAAA==.Miroslava:BAAANQAECgUICQAAAA==.Missfire:BAABNQAECn8WAAIIAAgKwg+QeQCAAQAIAAgKwg+QeQCAAQABNQAECgoKJQACAOQUAA==.',
Mk='Mkaye:BAAANQAECgIIBAAAAA==.',
Mo='Moggle:BAABNQAECn8YAAIMAAYKiAcNOwEqAQAMAAYKiAcNOwEqAQAAAA==.Mondazi:BAABNQAECn9CAAMDAAoKSBxSGgByAgADAAoKSBxSGgByAgAYAAoK+A7NaADSAQAAAA==.Moonlilly:BAAANQADCgIIAgAAAA==.Morfy:BAAANQABCggIBgAAAA==.Morgzim:BAAANQADCgYJBwAAAA==.Moustaccio:BAAANQAECgEIAgAAAA==.Mozarta:BAAANQABCggIDQAAAA==.',
Ms='Msmanalow:BAAANQAECgEIAQABNQAECgoKJQACAOQUAA==.',
My='Mycen:BAABNQAECn8XAAIKAAgKbgw7kQC7AQAKAAgKbgw7kQC7AQAAAA==.Myeyesburn:BAAANQAECgMJBAAAAA==.',
['Má']='Málaketh:BAAANQAECggIEQAAAA==.',
Na='Nardena:BAAANQAECgIIAgAAAA==.Narz:BAABNQAECn9EAAIIAAoKCxJJPQAmAgAIAAoKCxJJPQAmAgAAAA==.Naughtypine:BAAANQAECgEIAQAAAA==.Naylz:BAAANQAECggIAQAAAA==.',
Nd='Ndiz:BAAANQAECgUIBQAAAA==.',
Ne='Necronomikon:BAABNQAECn8bAAIMAAgKxgy+qwAiAQAMAAgKxgy+qwAiAQAAAA==.Nerhzul:BAAANQADCgUIBQAAAA==.Neromoo:BAAANQAECgUIDQABNQAECgoKIQAVALIQAA==.Neruphuyt:BAABNQAECn8dAAIEAAgKAgnkXABdAQAEAAgKAgnkXABdAQAAAA==.',
Ni='Niath:BAAANQAECgUIDgAAAA==.Nightheal:BAAANQABCgQIBQABNQAECgkJKAAWAM0jAA==.Nightsniper:BAAANQAECgEIAQABNQAECgkJKAAWAM0jAA==.',
No='Notdinor:BAAANQADCgIIAgAAAA==.Notlilly:BAABNQAECn8oAAIhAAkKoBEeFQDVAQAhAAkKoBEeFQDVAQAAAA==.Notpillows:BAAANQAECgEIAgAAAA==.',
Ny='Nyxelle:BAAANQAECgIIAwAAAA==.',
['Nä']='Närz:BAAANQADCggIBQAAAA==.',
['Nò']='Nòvà:BAAANQAECgcIEgAAAA==.',
Oi='Oilfu:BAAANQADCgUIBQABNQAECgoKPwAPACgVAA==.',
Ok='Okioni:BAAANQAECgUIBQAAAA==.',
Ol='Olgon:BAACNQAFFH8HAAIIAAIK3QruHgCLAAAIAAIK3QruHgCLAAA1AAQKf0IAAggACgrAFRc3ADsCAAgACgrAFRc3ADsCAAAA.',
Op='Oprhawinfury:BAABNQAECn8jAAIGAAkKkQuwPAD1AAAGAAkKkQuwPAD1AAAAAA==.',
Or='Orgodemir:BAABNQAECn8hAAIaAAcKByWTIADtAgAaAAcKByWTIADtAgAAAA==.Orhamin:BAAANQADCgYIDwAAAA==.',
Os='Oshani:BAAANQAECggIDwAAAA==.',
Ou='Outlaw:BAAANQADCgcIBwAAAA==.',
Pa='Pacolyte:BAAANQAECgQIBgAAAA==.Paigor:BAAANQABCgIIAgAAAA==.Palathene:BAABNQAECn8mAAMJAAoKbyBiJACrAgAJAAoKbyBiJACrAgAFAAQKnR0wNABCAQAAAA==.Pallystorm:BAAANQAECgYICAAAAA==.Palmike:BAAANQADCgYIBgAAAA==.Pandemonia:BAABNQAECn87AAIKAAkKYxL0XQCBAQAKAAkKYxL0XQCBAQAAAA==.Parsie:BAAANQAECgcIDQAAAA==.Pathibas:BAAANQADCggIDQABNQAECgoKOwAiAJYgAA==.Pattycakes:BAABNQAECn8pAAIGAAkKRQ4yJgB+AQAGAAkKRQ4yJgB+AQAAAA==.',
Pe='Pericø:BAAANQADCgQIBAAAAA==.',
Ph='Pherocious:BAAANQAECgQIBgAAAA==.',
Pi='Pinktuesday:BAAANQADCggICAAAAA==.Pixeleen:BAACNQAFFH8FAAIIAAQKrATjFQANAQAIAAQKrATjFQANAQA1AAQKfzwAAwgACgpeIswmAPwCAAgACgpeIswmAPwCACUABQrfCvJMAP4AAAAA.',
Pl='Plexy:BAABNQAECn8gAAMaAAkKYSDbIQDnAgAaAAkKuh/bIQDnAgAjAAcK8hlaCADhAQAAAA==.',
Po='Pokitz:BAABNQAECn8gAAIJAAcKGwYi6wDOAAAJAAcKGwYi6wDOAAAAAA==.',
Pr='Primordinor:BAABNQAECn81AAIDAAgKNB1INQDIAQADAAgKNB1INQDIAQAAAA==.Probnotalive:BAABNQAECn89AAIIAAoK/x0pFwA+AwAIAAoK/x0pFwA+AwAAAA==.Probnoturmom:BAABNQAECn8wAAIaAAkKVR5ZLQCzAgAaAAkKVR5ZLQCzAgAAAA==.',
Pu='Puab:BAAANQAECgYIBgABNQAECgoKPAAJAMQjAA==.',
Qu='Quacko:BAAANQAECgYICgABNQAECgoKMAAgACkgAA==.Quietus:BAAANQADCgcICwAAAA==.',
Ra='Raevyn:BAAANQAECgIIAgAAAA==.Raikai:BAAANQAECgEIAgABNQAECgoKLQANALMaAA==.Rakan:BAABNQAECn9DAAMhAAoKJB9UBAC3AgAhAAoKJB9UBAC3AgAcAAUKeQ2M6AAUAQAAAA==.Rallick:BAACNQAFFH8HAAINAAIKhQZkGwB3AAANAAIKhQZkGwB3AAA1AAQKfzQAAg0ACgovGG4cAKgCAA0ACgovGG4cAKgCAAAA.Ranì:BAABNQAECn86AAMhAAoKxxbLCQD6AQAhAAoKxxbLCQD6AQAiAAEKfAfgLAAvAAAAAA==.Rathger:BAAANQADCgUICAAAAA==.Ratmilk:BAAANQAECgcIDAAAAA==.Razkhan:BAAANQADCgcIDQAAAA==.',
Rd='Rdk:BAAANQAECgMIBAAAAA==.',
Re='Redek:BAAANQADCgcICgAAAA==.Reft:BAAANQABCgEIAQAAAA==.Reighna:BAAANQADCggIDQAAAA==.Rendcurse:BAAANQADCgEIAQAAAA==.Rendwee:BAABNQAECn9BAAIdAAoKeSHuAwDMAgAdAAoKeSHuAwDMAgAAAA==.Reps:BAAANQAECggICwAAAA==.Retiredaggro:BAAANQAECgUIDgAAAA==.Retiredghoul:BAAANQADCgUIBQAAAA==.Retiredlight:BAAANQADCgEIAQAAAA==.Rewolf:BAABNQAECn8XAAIYAAYKCB6eTgClAQAYAAYKCB6eTgClAQAAAA==.',
Rh='Rhaella:BAAANQAECgEIAwAAAA==.Rhynar:BAAANQAECggICQAAAA==.',
Ri='Ricflairion:BAABNQAECn81AAImAAkKaAvGCQA6AQAmAAkKaAvGCQA6AQAAAA==.Rill:BAAANQADCggICwAAAA==.',
Ro='Rodcet:BAABNQAECn88AAIJAAoKxCM9EwADAwAJAAoKxCM9EwADAwAAAA==.Roflbubble:BAABNQAECn82AAMaAAkKshSnTADMAQAaAAkKshSnTADMAQALAAUKdAWqVQC2AAAAAA==.Rognan:BAAANQAECgQIBgAAAA==.Roku:BAAANQAECgcICAAAAA==.Ronkin:BAAANQADCggIJAAAAA==.Rookgue:BAABNQAECn87AAIQAAgKdBKmFABwAQAQAAgKdBKmFABwAQAAAA==.Rookoker:BAAANQAECgUIEgAAAA==.Rorygazer:BAABNQAECn8YAAIhAAYKDCIZEAAnAgAhAAYKDCIZEAAnAgAAAA==.Rosmerta:BAAANQAECgIIAgAAAA==.Rossdair:BAAANQAECgUIDAABNQAECgYIEAABAAAAAA==.Rossperot:BAABNQAECn8bAAIGAAcKLh10SgDsAQAGAAcKLh10SgDsAQAAAA==.',
Ry='Ryk:BAABNQAECn8VAAIQAAoKTBowBgCCAgAQAAoKTBowBgCCAgAAAA==.',
Sa='Saarin:BAAANQAECgQIBQAAAA==.Saelara:BAAANQAECgQIBQAAAA==.Sairal:BAAANQAECggIEAAAAA==.Saltytuesday:BAAANQADCgYICQAAAA==.Samgee:BAACNQAFFH8ZAAIJAAUK4RoqDgDtAAAJAAUK4RoqDgDtAAA1AAQKfz4AAgkACgrFIPQzAP0CAAkACgrFIPQzAP0CAAAA.Sanguathene:BAEANQAECgMIBAABNQAECgoKJgAJAG8gAA==.Sawlty:BAABNQAECn8kAAIlAAoKxwwYMADNAQAlAAoKxwwYMADNAQAAAA==.Saynar:BAABNQAECn82AAMbAAoKuyLKBgDXAgAbAAoKuyLKBgDXAgAeAAIKRR1VJgCHAAAAAA==.',
Sc='Scattered:BAABNQAECn8nAAMZAAoKqw4MJwA+AQAZAAYKqQsMJwA+AQAKAAcKeQ6XnADoAAAAAA==.Schecter:BAABNQAECn8YAAMYAAcKJyOUMQCaAgAYAAcKJyOUMQCaAgADAAEKCxj0KQE/AAAAAA==.Scintila:BAAANQADCgQIBAABNQAECgkJOwAKAGMSAA==.Scooti:BAAANQADCggIEAABNQAECgYIDQABAAAAAA==.',
Se='Seba:BAACNQAFFH8HAAIMAAIKoApxMgCFAAAMAAIKoApxMgCFAAA1AAQKf1YAAgwACgpoHcApAHoCAAwACgpoHcApAHoCAAAA.Sehren:BAAANQADCgcIBgAAAA==.Sehtrak:BAAANQADCggICAAAAA==.Selesne:BAABNQAECn8hAAIRAAcKfAo/BQAJAQARAAcKfAo/BQAJAQAAAA==.Seniandrays:BAAANQADCgQIBAAAAA==.Serannia:BAAANQADCgIIAgAAAA==.Seraphicktwo:BAABNQAECn8aAAMLAAgKRgzpPQA9AQALAAgKRgzpPQA9AQAaAAEKTgYI/gAvAAAAAA==.',
Sh='Shadowlune:BAAANQAECgEIAQAAAA==.Shadowtrance:BAAANQAECgEIAQABNQAECgoKOAAFABgZAA==.Shaggmz:BAABNQAECn8cAAIiAAYKxw/wFwAgAQAiAAYKxw/wFwAgAQAAAA==.Shawnkin:BAAANQADCgIIAgAAAA==.Shelyn:BAAANQAECgcICwAAAA==.Shinma:BAABNQAECn8cAAIFAAYK/AVGQwDmAAAFAAYK/AVGQwDmAAAAAA==.Shootermcgee:BAAANQAECgIIAgAAAA==.Showtootsies:BAAANQADCgUJBQAAAA==.Shrubbery:BAAANQAECgQIBwAAAA==.Shymary:BAABNQAECn8cAAMjAAYKWxA+CgDLAAAaAAQKlRVmigAAAQAjAAYKCgc+CgDLAAAAAA==.',
Si='Siete:BAAANQADCgYJBwAAAA==.Silëx:BAABNQAECn8hAAIOAAgK8BSsDgC/AQAOAAgK8BSsDgC/AQAAAA==.Sindiz:BAAANQAECgUIDQAAAA==.Sioc:BAAANQAECgMIAwAAAA==.Siouxiesioux:BAAANQAECgQIBgAAAA==.',
Sk='Skadie:BAAANQAECgYICgAAAA==.Skoot:BAAANQAECgYIDQAAAA==.Skullbender:BAAANQAECgEIAgAAAA==.',
Sl='Slimjimz:BAAANQADCgUIBQAAAA==.Slugondeez:BAABNQAECn84AAMNAAkKeiFNJwDMAgANAAkKeiFNJwDMAgAFAAIKUyMyTwCqAAAAAA==.',
Sm='Smitefist:BAAANQAECgIIAgABNQAECggIDwABAAAAAA==.',
Sn='Snkyturtle:BAABNQAECn88AAIIAAoKdg6LZwCtAQAIAAoKdg6LZwCtAQAAAA==.Snoopdogydog:BAAANQABCgcIBgAAAA==.Snuzzle:BAABNQAECn8sAAIgAAkKlBcYFAAjAgAgAAkKlBcYFAAjAgAAAA==.',
So='Sourmash:BAAANQAECgQIBgAAAA==.',
Sp='Spaghet:BAABNQAECn8bAAIDAAkKHQ1rggCfAQADAAkKHQ1rggCfAQAAAA==.Spillthetea:BAAANQADCggICQABNQAECgYIGAAWAB8DAA==.Spittoon:BAAANQADCgEJAQABNQADCggIIAABAAAAAA==.Sploot:BAABNQAECn8hAAIKAAoKhRyMQQCNAgAKAAoKhRyMQQCNAgAAAA==.',
Sr='Srasjet:BAAANQAECgUICQAAAA==.',
Ss='Ssarmandok:BAABNQAECn8XAAIJAAkKERasrgDCAQAJAAkKERasrgDCAQAAAA==.',
St='Stabytha:BAAANQAECgYIDAAAAA==.Stark:BAAANQABCgQIBAAAAA==.Starlight:BAABNQAECn8iAAMCAAoKxR0hDwDjAgACAAoKxR0hDwDjAgAEAAYKzxSzTgC3AAAAAA==.Stealthed:BAABNQAECn8VAAIgAAUKuRDhPwCPAAAgAAUKuRDhPwCPAAAAAA==.Stender:BAAANQADCgIIAgABNQAFFAIICQATAH8eAA==.Stonegoddess:BAAANQADCgQIBAAAAA==.Stormcall:BAAANQAECgUIEQAAAA==.Stratusfied:BAAANQADCgIIAgAAAA==.Strongmojo:BAAANQAECgEIAgAAAA==.Strongsad:BAAANQAECgEIAwAAAA==.',
Sw='Swiss:BAABNQAECn8aAAIDAAcKHw90gACjAQADAAcKHw90gACjAQAAAA==.',
Sy='Syldra:BAAANQABCgIIAgAAAA==.',
['Sá']='Sáëgárón:BAAANQAECgMIBAAAAA==.',
Ta='Taliden:BAAANQAECgMICAAAAA==.Tankinstine:BAAANQADCgYIBwAAAA==.Taraylda:BAABNQAECn8cAAMLAAkKORWVFwCtAQALAAkKORWVFwCtAQAaAAEK2yEZ8gBOAAAAAA==.Tarz:BAAANQAECgYIDgAAAA==.Tazzwolfsong:BAAANQADCgEIAQAAAA==.',
Te='Tecdor:BAAANQADCgYJBgAAAA==.Teronfiggy:BAABNQAECn8YAAIHAAkKRQdUXwApAQAHAAkKRQdUXwApAQAAAA==.',
Tf='Tfirs:BAAANQAECgUIBwABNQABCgUIAwABAAAAAA==.',
Th='Thehealczar:BAAANQAECgcIDwABNQAECgkJKAAWAM0jAA==.Theokoles:BAAANQAECggIDwAAAA==.Thesenate:BAAANQADCggIDwABNQAECgoKPAASAJUSAA==.Thickblòód:BAAANQAFFAEIAQAAAA==.Thordurin:BAAANQAECgYIBgAAAA==.Thorly:BAAANQADCgYIDQAAAA==.Thrazi:BAAANQAECgIIBQAAAA==.',
Ti='Tiadalma:BAAANQAECgIIAwAAAA==.Tinn:BAAANQADCggIEAAAAA==.',
To='Toospookie:BAAANQADCgYIDgAAAA==.Totem:BAAANQAECgQICAAAAA==.',
Tr='Tramplip:BAABNQAECn8aAAIZAAYKbAo8EwClAAAZAAYKbAo8EwClAAAAAA==.Treecloud:BAABNQAECn82AAMgAAoKHyGZBgDDAgAgAAoKHyGZBgDDAgAEAAEKMxGXdwA6AAAAAA==.Treferimore:BAABNQAECn8YAAIIAAYKhg+qtQACAQAIAAYKhg+qtQACAQAAAA==.Trevian:BAABNQAECn8hAAIJAAcKyQ7VxQCQAQAJAAcKyQ7VxQCQAQAAAA==.',
Tu='Tulimyrsky:BAAANQADCgUIBQAAAA==.Tuluxxi:BAABNQAECn87AAMYAAoK4yLlGgAEAwAYAAoK4yLlGgAEAwADAAgK4g49dADEAQAAAA==.Tutter:BAAANQAECgUICwAAAA==.',
Tw='Twopumpchump:BAABNQAECn8rAAInAAkKfBHdCQB1AQAnAAkKfBHdCQB1AQAAAA==.',
Tz='Tzxdh:BAAANQAECgIIAwABNQAECggIGAAFADYVAA==.Tzxdruid:BAAANQAECgIIAwABNQAECggIGAAFADYVAA==.',
Ug='Uglymancer:BAABNQAECn8mAAIKAAkKlxY6QgDaAQAKAAkKlxY6QgDaAQAAAA==.',
Uj='Ujimas:BAABNQAECn8eAAIDAAYKcRaIXAA1AQADAAYKcRaIXAA1AQAAAA==.',
Ut='Uthodne:BAAANQAECgEIAQABNQAECgoKLwAQAO0TAA==.',
Va='Vampireshade:BAABNQAECn8zAAMQAAkKmAukIgAFAQAQAAkKmAukIgAFAQARAAYK/gMzEgDlAAAAAA==.Vampirevoid:BAAANQADCgUIBQAAAA==.Vanililly:BAABNQAECn8rAAIWAAkK8A2FMABhAQAWAAkK8A2FMABhAQAAAA==.Vanimao:BAAANQAECgEIAQAAAA==.Varan:BAAANQAECgUICQAAAA==.',
Vb='Vbull:BAAANQAECgEIAQAAAA==.',
Ve='Velissari:BAAANQAECgUIDgAAAA==.Venatra:BAAANQADCgYICAAAAA==.Veritus:BAABNQAECn8rAAITAAkKfB4AHQCxAgATAAkKfB4AHQCxAgAAAA==.',
Vi='Vindict:BAAANQAECgQICAAAAA==.Violette:BAABNQAECn8lAAIIAAcKOBC5lABEAQAIAAcKOBC5lABEAQAAAA==.Vion:BAAANQABCgQIBAAAAA==.',
Vo='Voidlink:BAABNQAECn88AAMjAAoKvCHOAABPAwAjAAoKvCHOAABPAwALAAYKHxEMIgA6AQAAAA==.Voidstriker:BAAANQAECgEIAQAAAA==.',
Wa='Wackyrellek:BAABNQAECn8mAAMQAAoKdh2GDQDNAQAQAAkKdh2GDQDNAQAPAAkK8w4oQwCpAQAAAA==.Wakancer:BAABNQAECn8VAAIUAAUKQw8KEgAqAQAUAAUKQw8KEgAqAQAAAA==.Wakarisma:BAAANQAECgEIAQAAAA==.Wakataclysm:BAAANQAECgUICwAAAA==.Walnut:BAAANQAFFAEIAQABNQAFFAIIBgADAF8QAA==.Warchylde:BAAANQADCgQIBgAAAA==.Warolderoy:BAABNQAECn87AAMiAAoKliAqBACCAgAiAAoKPSAqBACCAgAhAAYKShyAFwC0AQAAAA==.',
We='Weedshaman:BAAANQADCgcJBwAAAA==.Weil:BAAANQAECgYIDQAAAA==.',
Wo='Woker:BAAANQAECgYICgABNQAECgoKPAASAJUSAA==.Woogie:BAAANQAECgQIBwAAAA==.Worthy:BAAANQAECgMIAwAAAA==.Woyer:BAAANQADCgEIAQAAAA==.',
Wu='Wummie:BAAANQAECgMIAwABNQAECgkJKAAKAD0eAA==.',
['Wò']='Wòógie:BAAANQADCgYIBgABNQAECgQIBwABAAAAAA==.',
Xa='Xader:BAAANQADCggIEAAAAA==.Xanneral:BAEANQAECgUIBwABNQAECgoKLwAHADMaAA==.',
Xe='Xenna:BAAANQAECgUIDgABNQAECgkJKgAJAEATAA==.Xeq:BAAANQAECgMIAwAAAA==.',
Xi='Xiata:BAAANQAECgIIAgAAAA==.',
Ye='Yeoman:BAABNQAECn8aAAIiAAgKRhAiEwBvAQAiAAgKRhAiEwBvAQAAAA==.Yewko:BAAANQAECgYIEwAAAA==.',
Yg='Yggdralith:BAAANQAECggIJAAAAQ==.',
Yi='Yibble:BAAANQAECgUIBQABNQAFFAQIDgAcANkeAA==.',
Yo='Yobagoya:BAAANQAECgEIAwAAAA==.',
Yu='Yukionne:BAAANQAECgEIAgAAAA==.Yunohealme:BAABNQAECn8aAAIHAAcK/Rn6MwAOAgAHAAcK/Rn6MwAOAgAAAA==.Yunosmall:BAAANQADCgMIAwAAAA==.Yunosmart:BAAANQADCgMIBAAAAA==.',
Yz='Yzerman:BAAANQAECgIIAgABNQAECgoKHwAHAAsRAA==.',
['Yö']='Yör:BAAANQADCgEIAQAAAA==.',
Za='Zaen:BAACNQAFFH8HAAIKAAIKkA//HwCUAAAKAAIKkA//HwCUAAA1AAQKf0IAAwoACgqoHp4kAPICAAoACgp0Hp4kAPICABkABgqiHTcGAE4BAAAA.Zanapheia:BAAANQADCgIIAgABNQAECgoKPAAIAHYOAA==.Zandre:BAABNQAECn8oAAIhAAkK2BemEwDrAQAhAAkK2BemEwDrAQAAAA==.Zarkir:BAACNQAFFH8HAAIWAAIKVyJmEADDAAAWAAIKVyJmEADDAAA1AAQKfzMAAxYACgpEIxINAEgDABYACgpEIxINAEgDAAcAAQrACcScADcAAAAA.',
Ze='Zelily:BAABNQAECn8wAAIIAAkK8Q2vhAACAgAIAAkK8Q2vhAACAgAAAA==.Zenarri:BAAANQADCgYICgAAAA==.Zepha:BAAANQAECgEIAQAAAA==.',
Zh='Zharvakko:BAABNQAECn8wAAMYAAoKFBd7PwDmAQAYAAoKFBd7PwDmAQADAAcKrhBlhACaAQABNQAECgoKLQAYAPEdAA==.Zhiana:BAABNQAECn8cAAMOAAgKQxFHDgDHAQAMAAgKOwxj3gDLAQAOAAgK7A1HDgDHAQAAAA==.',
Zo='Zornov:BAAANQAECgEIAQABNQAECgoKMAAgACkgAA==.',
Zu='Zugzok:BAAANQAECgMIBAAAAA==.Zulrich:BAAANQAECgYICwAAAA==.',
Zv='Zvirae:BAAANQAECgUIBwAAAA==.Zvirax:BAAANQADCggIKQABNQAECgUIBwABAAAAAA==.',
['Ás']='Ástrid:BAAANQAECgEIAwAAAA==.',
['Ëu']='Ëuni:BAAANQADCgQIBAAAAA==.',
['Ìs']='Ìsaac:BAAANQAECgYJEgAAAA==.',
['Ðo']='Ðolm:BAAANQAECgQIBwAAAA==.',
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
