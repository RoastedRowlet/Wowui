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

local lookup = {'Paladin-Protection','Paladin-Retribution','Paladin-Holy','Hunter-Marksmanship','Hunter-BeastMastery','Priest-Shadow','Priest-Discipline','Priest-Holy','DemonHunter-Havoc','DemonHunter-Devourer','DemonHunter-Vengeance','Unknown-Unknown','Shaman-Elemental','Warlock-Affliction','Warlock-Demonology','Warrior-Protection','Warrior-Fury','Warrior-Arms','DeathKnight-Blood','DeathKnight-Unholy','Druid-Balance','Druid-Guardian','Druid-Restoration','Warlock-Destruction','Mage-Arcane','DeathKnight-Frost','Druid-Feral','Shaman-Restoration','Evoker-Preservation','Rogue-Assassination','Mage-Frost','Shaman-Enhancement','Monk-Brewmaster','Monk-Mistweaver','Monk-Windwalker','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','Mage-Fire',}
local provider = {region='US',realm='Gilneas',name='US',type='weekly',zone=53,date='2026-10-27',data={Ac='Acks:BAAANQAECgEIAQABNQAFFAUICAABALsGAA==.',
Ae='Aedra:BAAANQAECgIIAgAAAA==.Aeowyyn:BAABNQAECn8VAAMCAAgKjgoR/QAlAQACAAcKVQYR/QAlAQADAAIKgQWgDAFeAAAAAA==.Aex:BAABNQAECn8WAAMEAAgK0BE0PABwAQAEAAcK4RA0PABwAQAFAAMKygkHKAGkAAABNQAFFAUICAABALsGAA==.',
Af='Afib:BAAANQADCgcICAAAAA==.',
Ah='Ahnkhano:BAAANQAECgYIBgAAAA==.',
Ai='Ainge:BAAANQAECgEIAwAAAA==.Airiistra:BAAANQADCgMIAwAAAA==.',
Ak='Akbartheiiv:BAACNQAFFH8ZAAMGAAgKzBhIAgBxAgAGAAcK7xtIAgBxAgAHAAIKSwPlAQBRAAA1AAQKf14AAwYACgppJqIAAPMDAAYACgppJqIAAPMDAAcACArUJBoBAFkDAAAA.Akorius:BAAANQAECgIIAwAAAA==.',
Al='Alarion:BAAANQAECgEIAQAAAA==.Alexanderson:BAAANQAECgEIAgAAAA==.Allistrana:BAABNQAECn8jAAIIAAgK5BwrQgBjAgAIAAgK5BwrQgBjAgAAAA==.Allpower:BAAANQADCgYIDgAAAA==.Alpacalyptic:BAAANQAECgcICgAAAA==.Alyx:BAAANQADCgcIBwAAAA==.',
Am='Amadeux:BAAANQADCgIIAgABNQAECgkJIwAFAHMcAA==.Amairis:BAABNQAECn8aAAMHAAYKqxDmBgDxAAAHAAYKqxDmBgDxAAAGAAQKcwh1UwDAAAAAAA==.Ambiorix:BAAANQABCgUIBQAAAA==.',
An='Anrion:BAABNQAECn8/AAQJAAoK6h8DEQAXAwAJAAoKrR8DEQAXAwAKAAYKsRgsPABmAQALAAIKZCNfIgCvAAAAAA==.Antiflag:BAAANQAECgYIBwAAAA==.Anzania:BAAANQADCgEIAQABNQADCgYIEwAMAAAAAA==.',
Ar='Arolz:BAAANQADCgYIBgAAAA==.',
At='Ataliya:BAABNQAECn8aAAINAAYK6AuibQDIAAANAAYK6AuibQDIAAAAAA==.',
Au='Auranar:BAABNQAECn8ZAAIEAAcKUwQtKQC9AAAEAAcKUwQtKQC9AAAAAA==.Aurelya:BAABNQAECn8kAAIIAAcKsw7DggCPAQAIAAcKsw7DggCPAQAAAA==.Aurilia:BAAANQAECgUIEQAAAA==.',
Av='Avanicus:BAABNQAECn8ZAAMOAAkK/wy1CwCsAQAOAAgKcA21CwCsAQAPAAMKJAdeNAFRAAAAAA==.Aven:BAAANQAECgEIAQAAAA==.Avernas:BAAANQAECgQIBgAAAA==.Avé:BAABNQAECn8qAAMCAAkK2hK7ZACOAQACAAkKjhK7ZACOAQABAAQKRA0ZTgCwAAAAAA==.',
Ax='Axellent:BAACNQAFFH8MAAIQAAQK/g6EAQD3AAAQAAQK/g6EAQD3AAA1AAQKfy4ABBAACgp8HGkFADkCABAACgpVGmkFADkCABEABQq/GkwSAH8BABIABgrAGavJAGQBAAE1AAUUBQgIAAEAuwYA.Axiomlegacy:BAABNQAECn8nAAMTAAoKUCEKDgBAAwATAAoKUCEKDgBAAwAUAAEKpwgs5gAuAAAAAA==.',
Az='Azraith:BAAANQADCgcIBgAAAA==.Azulien:BAAANQAECgcIEgAAAA==.Azulin:BAAANQADCgUJBQAAAA==.',
Ba='Banderblitz:BAABNQAECn8pAAMRAAkKyRYSDgDSAQASAAkKaBLXjQD6AQARAAcKcRkSDgDSAQAAAA==.Banzgrave:BAAANQADCgcIBwAAAA==.Bar:BAACNQAFFH8IAAMIAAYKVQNHDwA2AQAIAAUKjgNHDwA2AQAGAAIK8wNpFQBzAAA1AAQKfx8AAwYACgrMGa0kAAsCAAYACAqMGK0kAAsCAAgACQrrCqGIAH0BAAAA.',
Be='Bearlyshady:BAABNQAECn9CAAQVAAoK3hpOEQA0AgAVAAoK3hpOEQA0AgAWAAQK9gmiQgCsAAAXAAEKugNHeQAsAAABNQADCgYIBgAMAAAAAA==.Bellarina:BAAANQAECgQIDAAAAA==.Bellatrixie:BAAANQAECgQIEgAAAA==.Bennitely:BAAANQADCgEIAQAAAA==.Beriadhwen:BAAANQAECgEIAQAAAA==.Bermy:BAABNQAECn8gAAMYAAoKfAr5FgC1AQAYAAoKegn5FgC1AQAPAAUKWwi/pACnAAAAAA==.Berzerkercow:BAAANQADCgYIBwAAAA==.Bewildert:BAAANQADCgMIBAAAAA==.',
Bh='Bhawkwco:BAAANQADCgUIBQAAAA==.',
Bi='Bigjaina:BAABNQAECn89AAIZAAkKtR5KLwA0AgAZAAkKtR5KLwA0AgAAAA==.Biku:BAAANQAECgUIEQAAAA==.Bitesthesky:BAAANQAECgUIBQAAAA==.',
Bl='Blackhawkdk:BAABNQAECn8xAAMUAAoKRhkCEAAgAgAUAAoKRhkCEAAgAgATAAEKAADExQA9AAAAAA==.Blackhawkm:BAAANQADCgcIBwAAAA==.Blende:BAAANQAECgQIBwABNQAECgYIEAAMAAAAAA==.Blindwarrior:BAAANQAECgIIAwAAAA==.Bloodshadow:BAABNQAECn8cAAIFAAcKvgvMhgAkAQAFAAcKvgvMhgAkAQAAAA==.',
Bo='Boraffe:BAAANQADCgMJAgAAAA==.Bovinity:BAAANQABCgcICgAAAA==.',
Br='Breakcooloz:BAAANQAFFAEIAQABNQAFFAUIBQAUAJoTAA==.Bretcoe:BAAANQADCgYIDAABNQAECgIIAgAMAAAAAA==.Bronzamdee:BAAANQADCggJCAAAAA==.Brooce:BAABNQAECn8wAAICAAgKfxxqYAB4AgACAAgKfxxqYAB4AgAAAA==.Broom:BAAANQAECgQIBgABNQAECgkJPQAZALUeAA==.Brozken:BAAANQADCgUICAAAAA==.Brutak:BAAANQADCggICAAAAA==.',
Bu='Burstinurass:BAACNQAFFH8FAAIUAAUKmhPDCACMAQAUAAUKmhPDCACMAQA1AAQKfxsAAhQACgqnHlYcAOICABQACgqnHlYcAOICAAAA.Buzzliteyear:BAAANQADCgUIBQAAAA==.',
['Bä']='Bängbäng:BAAANQADCgYICgAAAA==.',
Ca='Caelix:BAAANQAECgQIBQAAAA==.Canadiana:BAAANQADCgYIBgAAAA==.Carafe:BAAANQAECgYIBwABNQAECgoKIgAaAEIaAA==.Carbo:BAAANQAECgYICgABNQAECgoKJgAbABckAA==.Carbonight:BAABNQAECn8mAAIbAAoKFyTHAwBeAwAbAAoKFyTHAwBeAwAAAA==.Carlos:BAAANQAECggIDAAAAA==.',
Ce='Celani:BAAANQADCggICAABNQAECggIFgAcACENAA==.Celintha:BAAANQADCgMIBAAAAA==.Cellyne:BAAANQAECgQIEwAAAA==.',
Ch='Chaoswind:BAABNQAECn86AAIcAAoKhBq1LQCrAgAcAAoKhBq1LQCrAgAAAA==.Charlee:BAABNQAECn8UAAIFAAkKpw0dSgC/AQAFAAkKpw0dSgC/AQAAAA==.Chaz:BAAANQAECgIIAgAAAA==.Cheeb:BAAANQADCgcIBwAAAA==.Cheebie:BAAANQABCgYIBgABNQADCgcIBwAMAAAAAA==.Chelives:BAEBNQAECn8jAAIQAAcK0wEGIQCHAAAQAAcK0wEGIQCHAAAAAA==.Cherryb:BAAANQABCgYIDAAAAA==.Chromus:BAACNQAFFH8dAAIdAAYKgRuwAwDsAQAdAAYKgRuwAwDsAQA1AAQKfykAAh0ACgrrHHgNAM8CAB0ACgrrHHgNAM8CAAAA.',
Ci='Cires:BAABNQAECn8sAAIeAAoKlxRaDgCbAQAeAAoKlxRaDgCbAQAAAA==.',
Co='Colanasou:BAAANQAECgMICgAAAA==.Coldbattler:BAAANQAECgYIDAAAAA==.Convictions:BAAANQAECgYIDQABNQAFFAgIFwASANIaAA==.Corrick:BAAANQAECgIICAAAAA==.Cowpatty:BAAANQADCgQIBAAAAA==.',
Cr='Crow:BAAANQAFFAYIDwAAAQ==.',
Cy='Cydric:BAABNQAECn8hAAICAAoKNRzFKQBZAgACAAoKNRzFKQBZAgAAAA==.',
Da='Daarrkstar:BAAANQAECgYIEAAAAA==.Dakaryn:BAAANQADCggIDQAAAA==.Damageguy:BAAANQAECgYIBwABNQAFFAYIHwASACMhAA==.Darkynlord:BAAANQADCggICAAAAA==.',
De='Deadskvll:BAAANQADCgYIBgAAAA==.Deathbattler:BAAANQADCggIFAAAAA==.Deathrival:BAAANQADCggICAAAAA==.Dehnis:BAAANQADCgQIBAAAAA==.Delta:BAAANQADCgYICwAAAA==.Demonkare:BAAANQAECgUICgABNQAECgoKNwABAM4jAA==.Demoray:BAACNQAFFH8lAAMEAAgK3hyJBAAqAgAEAAcKuBuJBAAqAgAFAAEKmSI0LgBmAAA1AAQKfy8AAwQACgodJvQCAAUDAAQACgodJvQCAAUDAAUAAQppIy3lAGsAAAAA.Demvinity:BAAANQAECgQIDwAAAA==.Dethrone:BAABNQAECn8mAAMPAAoKQh1/IQA2AgAPAAkKGR1/IQA2AgAYAAIKnRq8TACZAAAAAA==.Deus:BAABNQAECn87AAMGAAgKBRMfKwDOAQAGAAcKXhMfKwDOAQAHAAYKAxXwDgA9AQAAAA==.',
Di='Dinosocks:BAACNQAFFH8PAAMFAAcK8AyyEABSAQAFAAQKwhKyEABSAQAEAAQKPANvFAD5AAA1AAQKfzkAAwQACgp/GpESAJgBAAUACAoTGXV0ACcCAAQACQoGFpESAJgBAAAA.Dirtydragon:BAABNQAECn8pAAIdAAkKCh8GBgCXAgAdAAkKCh8GBgCXAgAAAA==.Divinedecay:BAABNQAECn8eAAITAAcKUg5aPADxAAATAAcKUg5aPADxAAABNQAECgoKNAAFAEgcAA==.',
Dj='Djaequitas:BAAANQABCgQIBgAAAA==.Djmelisandra:BAAANQABCgQIBAAAAA==.Djshamy:BAAANQABCgUICAAAAA==.',
Do='Dok:BAAANQAECgYICAAAAA==.Donoraginn:BAAANQAECgEIAQAAAA==.Donos:BAAANQADCggILwABNQAECgEIAQAMAAAAAA==.Dontkare:BAAANQADCgMIAwABNQAECgoKNwABAM4jAA==.Dorsai:BAAANQADCgUIBQAAAA==.Dotgenerate:BAAANQAECgQIBQAAAA==.',
Dr='Dracorex:BAAANQABCgIIAgAAAA==.Drark:BAAANQAECgMIBgAAAA==.Drathiel:BAAANQAECgEIAQAAAA==.Drizztknight:BAAANQADCgYIBgAAAA==.Drwho:BAABNQAECn8XAAMfAAgKNRfXDwCqAQAfAAcKtRfXDwCqAQAZAAQKRxWTYQHxAAAAAA==.Drääx:BAAANQADCgQIBAAAAA==.Dräëxx:BAAANQADCgcIBwAAAA==.Drëëxx:BAAANQAECgEIAQAAAA==.',
Du='Duckymet:BAAANQADCggIEwAAAA==.Duvari:BAAANQAECgEIAQAAAA==.',
Dw='Dwallin:BAAANQADCgQIBAAAAA==.',
Dy='Dyane:BAAANQADCgQIBAAAAA==.',
['Dô']='Dôz:BAAANQAECgQICAAAAA==.',
Ed='Edoaldor:BAAANQADCgUICgAAAA==.',
El='Ellery:BAAANQADCgUJBQAAAA==.',
Em='Empyrean:BAAANQAECgQIBQAAAA==.',
Ex='Exhumina:BAAANQAECgMIDAAAAA==.',
Fa='Facestealerr:BAAANQAECgQIEwAAAA==.',
Fe='Felgibson:BAAANQADCgYIDQAAAA==.Fenmoon:BAABNQAECn8kAAIVAAoKiAwgJwBMAQAVAAoKiAwgJwBMAQAAAA==.',
Fi='Finneaa:BAAANQADCgUIBQAAAA==.',
Fl='Flairrick:BAABNQAECn8YAAIRAAcKIBaYDAAuAQARAAcKIBaYDAAuAQAAAA==.Flars:BAABNQAECn8zAAIaAAoK6SS/AwA3AwAaAAoK6SS/AwA3AwAAAA==.Flatliner:BAABNQAECn8ZAAIDAAgKPge3iQB/AQADAAgKPge3iQB/AQAAAA==.Flik:BAAANQAECgcIEwABNQAFFAUICAABALsGAA==.',
Fo='Forq:BAAANQADCgcIDgAAAA==.',
Fr='Frakz:BAAANQADCgUIBQAAAA==.Fran:BAAANQADCgYIBgABNQAECgkJPQAZALUeAA==.Frankzappn:BAABNQAECn8iAAQNAAkK+hrCOgCLAgANAAgKJBzCOgCLAgAgAAQKMBL/IACTAAAcAAMKhwFBFQE/AAAAAA==.Fray:BAAANQADCggICAAAAA==.Freeguy:BAABNQAECn8yAAIKAAkKuxb+IABEAgAKAAkKuxb+IABEAgAAAA==.Fruitcakes:BAABNQAECn8aAAQhAAYK0QTMIwC2AAAhAAUK/gPMIwC2AAAiAAUKLwUSOACtAAAjAAQK4gNeWgB8AAAAAA==.',
Fu='Fuddicus:BAAANQAECgIIBQAAAA==.Fuddrael:BAABNQAECn8oAAILAAoKxQnLDwDWAAALAAoKxQnLDwDWAAAAAA==.Fuddrucker:BAAANQAECgIIAgAAAA==.Fuddster:BAAANQADCgQIBAAAAA==.',
Ga='Gaddess:BAABNQAECn8jAAIGAAcK3gYFKADIAAAGAAcK3gYFKADIAAAAAA==.Gandàlf:BAAANQADCgYIBgAAAA==.Ganymede:BAAANQAECgUICAAAAA==.Garan:BAAANQAECgEIAwAAAA==.',
Ge='Geilamaine:BAABNQAECn8lAAQDAAoKHxcAVQAbAgADAAoKHxcAVQAbAgACAAEKngrrPwE3AAABAAEK8AIOVQAhAAAAAA==.Gerona:BAAANQAECgEIAQAAAA==.',
Gl='Glimagi:BAAANQAECgQIEAAAAA==.',
Gn='Gnxr:BAEANQAECgIIAgABNQAFFAQICgAjACkjAA==.',
Go='Gonefishing:BAAANQADCgYIBgABNQAECgoKPwAFAHIYAA==.Gotêtsu:BAAANQAECggIDwAAAA==.',
Gr='Grimjawz:BAABNQAECn8wAAIXAAoKcB3MCADAAgAXAAoKcB3MCADAAgAAAA==.Grimpath:BAAANQAECgEIAgAAAA==.Grippysocks:BAAANQAFFAIIAgABNQAFFAcIDwAFAPAMAA==.',
Gu='Gummibear:BAABNQAECn8cAAMQAAUKeQ6sKQDtAAAQAAUKeQ6sKQDtAAASAAEK+wQ6VQExAAAAAA==.',
Gw='Gwiyomi:BAAANQAECgIIAgABNQAECgoKGQAaAHAgAA==.',
Gy='Gyr:BAAANQAECgUICQAAAA==.',
Ha='Hakai:BAAANQADCgEIAQABNQAECgoKLAAJAAoUAA==.Hanbor:BAAANQADCgcIBwAAAA==.Haniku:BAABNQAECn8VAAISAAgKtgg2xwBqAQASAAgKtgg2xwBqAQAAAA==.Harthoon:BAACNQAFFH8bAAIZAAYKmAikDgAdAQAZAAYKmAikDgAdAQA1AAQKfzEAAx8ACgptGyULABMCABkACgrKEFyeAEQCAB8ACAqAHiULABMCAAAA.',
He='Henos:BAAANQAECgUIBQAAAA==.',
Ho='Hobomatt:BAAANQADCggICAAAAA==.Holiebelle:BAABNQAECn8aAAIDAAcKQxi+OQC0AQADAAcKQxi+OQC0AQAAAA==.Holyhutch:BAAANQAECgcIEQABNQAECgoKMAAPAOUaAA==.Holyshield:BAAANQADCgEIAQABNQAECgoKLgAIAHkeAA==.Honeynoats:BAABNQAECn8lAAIIAAgKiQnjhACIAQAIAAgKiQnjhACIAQAAAA==.Hotdwarf:BAABNQAECn8bAAQDAAYKAA7auwAEAQADAAUKbQvauwAEAQABAAUKlAeRSADLAAACAAEKBwSlTQEuAAAAAA==.',
Hr='Hrumm:BAACNQAFFH8bAAMEAAYKjxaNCAC/AQAEAAYKOBSNCAC/AQAFAAEKkw/8HwBcAAA1AAQKfyoAAwQACgraGe4YAJACAAQACgraGe4YAJACAAUABQpuCj8MAe4AAAAA.',
Hu='Hullkk:BAACNQAFFH8fAAISAAYKIyHzBgBSAgASAAYKIyHzBgBSAgA1AAQKfy4AAhIACgqfJVcQAH0DABIACgqfJVcQAH0DAAAA.Hun:BAAANQAECggICAAAAA==.Hush:BAAANQAECgYIBwAAAA==.Hutchadina:BAAANQAECgIIBAABNQAECgoKMAAPAOUaAA==.Hutchanova:BAAANQAECgQIBgABNQAECgoKMAAPAOUaAA==.Hutchi:BAAANQAECgYIBwABNQAECgoKMAAPAOUaAA==.Hutchkins:BAABNQAECn8wAAIPAAoK5RpKIAA8AgAPAAoK5RpKIAA8AgAAAA==.Hutchknight:BAAANQAECggIDwABNQAECgoKMAAPAOUaAA==.Hutchyo:BAAANQAECgIIBAABNQAECgoKMAAPAOUaAA==.Hutchyr:BAAANQAECgEIAQABNQAECgoKMAAPAOUaAA==.',
Hy='Hyd:BAAANQADCgQIAQABNQADCgcICQAMAAAAAA==.Hydro:BAAANQADCgcICQAAAA==.',
['Hä']='Häwtz:BAAANQAECgIIAgAAAA==.',
Ic='Icerus:BAAANQAECggIDAAAAA==.Icirus:BAABNQAECn9AAAMDAAoK1yDnBwBMAwADAAoK1yDnBwBMAwACAAQKkQqNSQGqAAAAAA==.',
Id='Idraven:BAAANQAECgEIAQAAAA==.',
Il='Illaandra:BAAANQADCgUIBQABNQAECgEIAQAMAAAAAA==.',
Im='Imsanity:BAAANQADCgQIBAAAAA==.',
In='Inseng:BAABNQAECn8ZAAMaAAoKcCCACQBRAwAaAAoKcCCACQBRAwATAAUKjhhBcQAwAQAAAA==.Invasion:BAAANQAECgEIAQAAAA==.',
It='Itzal:BAAANQAECgYIBgAAAA==.',
Ja='Jagere:BAABNQAECn8oAAIFAAoKDg71OgD1AQAFAAoKDg71OgD1AQAAAA==.Jahde:BAABNQAECn8aAAIVAAcK5wVbRQCvAAAVAAcK5wVbRQCvAAAAAA==.Jaina:BAABNQAECn8VAAIFAAYK7A1ylQAGAQAFAAYK7A1ylQAGAQAAAA==.Jandrae:BAABNQAECn83AAQaAAoKhRtzGgC3AgAaAAoKDRpzGgC3AgAUAAUKFx6zYACNAQATAAIKqwfxuwBQAAAAAA==.Jassykins:BAAANQAECgUIEQAAAA==.',
Je='Jessecuster:BAAANQADCgQJBAAAAA==.',
Ji='Jiffypop:BAAANQAECgIIAwABNQAECgYIBwAMAAAAAA==.Jillotty:BAAANQADCgUIBAAAAA==.Jirachii:BAAANQAECgEIAgABNQAFFAMICAAVACENAA==.',
Jo='Joanofarc:BAAANQADCgUJBQAAAA==.Joloc:BAABNQAECn8fAAIYAAcKIg2zGACmAQAYAAcKIg2zGACmAQAAAA==.Jonpaul:BAAANQABCgEIAQAAAA==.',
Ju='Jueles:BAAANQADCgMIAwABNQAECgcIGgAVAOcFAA==.',
['Jì']='Jìnx:BAAANQADCgQIBQAAAA==.',
Ka='Kalrosa:BAAANQAECgYIEgABNQAECgkJKQARAMkWAA==.Kare:BAAANQAECgYIDgABNQAECgoKNwABAM4jAA==.Karee:BAABNQAECn83AAIBAAoKziMyAgCuAwABAAoKziMyAgCuAwAAAA==.Karfren:BAAANQAECgEJAQAAAA==.Kauko:BAAANQAECggICAAAAA==.Kazer:BAAANQADCgYJBgAAAA==.',
Ke='Kermodk:BAABNQAECn8pAAITAAkKZiHiFgD2AgATAAkKZiHiFgD2AgAAAA==.',
Kh='Khold:BAABNQAECn8eAAIBAAgK1w+7LAB3AQABAAgK1w+7LAB3AQAAAA==.',
Ki='Kissofdeath:BAAANQAECgEIAQAAAA==.',
Ko='Koltara:BAABNQAECn8cAAIKAAkK6B0cGACcAgAKAAkK6B0cGACcAgABNQAFFAYIHgAFADocAA==.Koltarax:BAAANQAECgEIAQABNQAFFAYIHgAFADocAA==.Koltarian:BAAANQAFFAEIAQABNQAFFAYIHgAFADocAA==.Koltaros:BAAANQAECgQIBQABNQAFFAYIHgAFADocAA==.Konshis:BAABNQAECn88AAMiAAoK8SCDCgDgAgAiAAoK8SCDCgDgAgAjAAYKpwvtKQDWAAAAAA==.Kookymonster:BAABNQAECn9EAAMPAAoKkCDTBwCOAwAPAAoKkCDTBwCOAwAYAAIK+R/JRgCsAAAAAA==.Kos:BAACNQAFFH8dAAQaAAYKURZFBQC6AQAaAAYKRRFFBQC6AQAUAAUKqRywCwBSAQATAAEKAADIPQAYAAA1AAQKfzMAAxoACgp4IHEcAKYCABoACgq4H3EcAKYCABQABQppHTRYALABAAAA.',
Kr='Krathos:BAAANQADCgYJCAAAAA==.Krax:BAAANQADCgEIAQAAAA==.Kruk:BAAANQADCggIGAAAAA==.',
Ku='Kuragaru:BAACNQAFFH8dAAIkAAYKBxa2BQDCAQAkAAYKBxa2BQDCAQA1AAQKfzEAAiQACgomIb8EAEIDACQACgomIb8EAEIDAAAA.',
La='Lala:BAAANQAECgYIBgAAAA==.Lapis:BAABNQAECn8qAAIcAAkK2iCPFwAWAwAcAAkK2iCPFwAWAwAAAA==.',
Le='Lester:BAABNQAECn8fAAIGAAgK7hf3HwA7AgAGAAgK7hf3HwA7AgAAAA==.Levina:BAABNQAECn8sAAMWAAkKWBaoHAC9AQAVAAkKUhX6NQA7AgAWAAgKChWoHAC9AQAAAA==.Lexysady:BAABNQAECn8XAAMCAAoKcxPtiwAOAgACAAoKcxPtiwAOAgADAAIKeQiEIgEyAAAAAA==.',
Li='Liamsun:BAAANQADCggICAAAAA==.Lidrael:BAAANQADCgYIBgABNQAECgoKQgATABoiAA==.Lidrahl:BAABNQAECn9CAAITAAoKGiIADABSAwATAAoKGiIADABSAwAAAA==.Lilihunt:BAAANQADCgYIBgAAAA==.Liliria:BAABNQAECn86AAIIAAoKDA2xQACxAQAIAAoKDA2xQACxAQAAAA==.Lillidân:BAAANQADCgUIBgABNQAECgoKMwAZAPweAA==.Lineman:BAAANQADCgIIAgAAAA==.',
Lj='Ljaeì:BAAANQADCggICAAAAA==.',
Ll='Lloreth:BAABNQAECn8nAAIXAAcKHRKVHAB/AQAXAAcKHRKVHAB/AQAAAA==.',
Ln='Lnpoop:BAABNQAECn8/AAMXAAoK3h16BwDjAgAXAAoK3h16BwDjAgAVAAMKOwnMXwBVAAAAAA==.',
Lo='Loafs:BAAANQAECgcIBwAAAA==.Lockjauz:BAAANQADCgQIBgAAAA==.Lonaki:BAAANQADCgIIAgAAAA==.Lorelei:BAAANQAECgYIDwAAAA==.Lorrellia:BAAANQADCggICAAAAA==.Lovekiller:BAAANQADCgEIAQAAAA==.',
Lu='Luc:BAABNQAECn8yAAIdAAoKFR7BBgB5AgAdAAoKFR7BBgB5AgAAAA==.Lucariõ:BAACNQAFFH8aAAIIAAcKqhq+BQBCAgAIAAcKqhq+BQBCAgA1AAQKfzMAAwgACgoJIYQYABQDAAgACgoJIYQYABQDAAYAAQqMA/dKAC4AAAAA.Lumina:BAAANQAECgYIDgAAAA==.',
Ly='Lyllies:BAABNQAECn85AAIFAAoKMiB9HQB3AgAFAAoKMiB9HQB3AgAAAA==.Lyv:BAAANQADCgYIBgABNQAECgEIAQAMAAAAAA==.',
Ma='Mafia:BAAANQADCggIEQAAAA==.Magnumrex:BAAANQADCgUIBQAAAA==.Maharette:BAAANQADCgMIAwAAAA==.Makkazul:BAABNQAECn8uAAIaAAkKMxFDKQCMAQAaAAkKMxFDKQCMAQAAAA==.Malgus:BAAANQADCgYIBgAAAA==.Matcauthon:BAAANQAECgUIBwAAAA==.Matrim:BAAANQADCggIEgAAAA==.Mattdæmon:BAABNQAECn8hAAMLAAcKnQVgHgDcAAAJAAYKcgYGXAATAQALAAcKMQNgHgDcAAAAAA==.Mazzak:BAAANQADCgIIAgAAAA==.',
Me='Meekogaia:BAABNQAECn9jAAMcAAoKaRdfSABAAgAcAAoKaRdfSABAAgANAAYKeBEyoABWAQAAAA==.Meekosan:BAAANQADCgcIBwAAAA==.',
Mi='Mijime:BAAANQADCgYIBgABNQAECgQIBAAMAAAAAA==.Millerowntoo:BAACNQAFFH8SAAQUAAcK8yDeAgAWAgAUAAUKJiLeAgAWAgAaAAEKJxwhEgBcAAATAAEKAABpOwAcAAA1AAQKfygAAxQACQqJJvYLAFsDABQACAqkJvYLAFsDABoAAwqEJLVRANAAAAAA.Millions:BAABNQAFFH8IAAIBAAUKuwbHBgAaAQABAAUKuwbHBgAaAQAAAA==.Mimzy:BAAANQADCgIIAgAAAA==.Mingzi:BAAANQADCgMIAwAAAA==.Minivan:BAAANQADCggICQAAAA==.Mital:BAAANQAECgEIAwAAAA==.',
Mj='Mjoln:BAAANQAECgQIBAAAAA==.',
Mo='Mobius:BAAANQADCggIFQABNQAECgcIIAAOAGgWAA==.Molvnma:BAAANQAECggIBAAAAA==.Monkeycoke:BAABNQAECn8gAAMOAAcKaBY9FAAHAQAPAAcKVhTiYQA/AQAOAAQKnxY9FAAHAQAAAA==.Montkriege:BAAANQAECgIICAAAAA==.Moonwarden:BAAANQAECgEIAQAAAA==.',
Mu='Munchkinz:BAAANQAECgIIAgABNQAECgoKLAAIANYiAA==.Murfie:BAABNQAECn8gAAIGAAoKThUtIgAjAgAGAAoKThUtIgAjAgAAAA==.Murica:BAAANQADCgYICgABNQAECgkJPQAZALUeAA==.',
My='Mythosrex:BAAANQADCgMIAwAAAA==.',
['Mì']='Mìr:BAAANQAFFAEIAQAAAA==.',
Na='Nashira:BAABNQAECn8sAAIcAAoKmBemPgBlAgAcAAoKmBemPgBlAgAAAA==.Nashness:BAABNQAECn8qAAMaAAoKGx1NHACoAgAaAAoKcBdNHACoAgAUAAgKayBMNwBJAgAAAA==.Naturdimund:BAAANQADCgMIAwAAAA==.Natures:BAAANQADCgEIAQAAAA==.',
Ne='Nerdvader:BAAANQADCgEJAQABNQAECgcIIQALAJ0FAA==.Nesquík:BAAANQADCgYIHAAAAA==.Nezar:BAABNQAECn8YAAIXAAcK2BSHHgBsAQAXAAcK2BSHHgBsAQAAAA==.',
Ni='Nicokira:BAAANQAECgEIAgAAAA==.Niis:BAABNQAECn8YAAMRAAgKSRANDQDnAQARAAgKSRANDQDnAQAQAAcKRwsAIQBFAQAAAA==.Niterage:BAABNQAECn8qAAIJAAcKRAUuWwAXAQAJAAcKRAUuWwAXAQAAAA==.',
Nn='Nn:BAABNQAECn8aAAIWAAcKmBJDKgBFAQAWAAcKmBJDKgBFAQAAAA==.',
No='Noseheirs:BAAANQADCgQIBAAAAA==.Notoriuspab:BAAANQAECgIJAwAAAA==.Noyar:BAAANQADCgMIAwAAAA==.',
Nu='Nuckinphutz:BAAANQADCgEIAQAAAA==.',
['Nè']='Nègan:BAABNQAECn8qAAIFAAoKhxEMYwBQAgAFAAoKhxEMYwBQAgAAAA==.',
['Nì']='Nìr:BAACNQAFFH8SAAIJAAYKJxl3BABJAQAJAAYKJxl3BABJAQA1AAQKfxUAAgkACAqEGxUjAHwBAAkACAqEGxUjAHwBAAAA.',
Od='Odinrex:BAABNQAECn8hAAIFAAcKcxZhZwBsAQAFAAcKcxZhZwBsAQAAAA==.',
Op='Opuntia:BAAANQAECgQIEQAAAA==.',
Or='Orexion:BAAANQADCgUIBQAAAA==.',
Ow='Ownham:BAABNQAECn8bAAMDAAoKdhuTLgCsAgADAAoKdhuTLgCsAgACAAcKqBcxlgAmAQABNQAFFAcIEgAUAPMgAA==.',
Ox='Oximus:BAAANQAECgEIAQAAAA==.',
Pa='Paddingidiot:BAACNQAFFH8eAAMFAAYKOhwIBwAlAQAEAAYKjxP9BwDKAQAFAAQKyB8IBwAlAQA1AAQKfx0AAwQACgrGHGIWAKgCAAQACgpQGGIWAKgCAAUAAQrmJYPiAG8AAAAA.Pakez:BAAANQADCgIIAgAAAA==.Paladinheal:BAABNQAECn8mAAIDAAkKABYeLAD6AQADAAkKABYeLAD6AQAAAA==.Pallypaladin:BAACNQAFFH8RAAICAAYKdhC+CwCOAQACAAYKdhC+CwCOAQA1AAQKf0QAAwIACgprIosZAF4DAAIACgprIosZAF4DAAEABQpeEEIlANYAAAAA.Pardsz:BAAANQADCgYICAAAAA==.Partywolf:BAAANQAECgUIEwAAAA==.',
Ph='Phatzero:BAABNQAECn80AAIFAAoKSBy5GgAuAwAFAAoKSBy5GgAuAwAAAA==.',
Pi='Pikas:BAAANQABCgIIAgAAAA==.Pinjo:BAAANQAECgcIDwAAAA==.',
Po='Polard:BAABNQAECn8fAAMWAAoKIR1QBgAsAwAWAAkKICFQBgAsAwAbAAMKvgElOwALAAAAAA==.Pownown:BAAANQAECgYIDQABNQAFFAcIEgAUAPMgAA==.',
Pr='Procreeper:BAAANQAECgMIBAABNQAECgoKJgAbABckAA==.',
Ps='Pseudonym:BAAANQAECgEIAgAAAA==.',
Pu='Pupper:BAABNQAECn8eAAISAAgKOxv2LAAoAgASAAgKOxv2LAAoAgAAAA==.',
Ra='Rabit:BAAANQAECgQIBwAAAA==.Radio:BAAANQAECgQIBAAAAA==.Raennt:BAAANQADCgEIAQAAAA==.Rafïki:BAAANQADCgYIBgAAAA==.Rainstorm:BAAANQADCgcIBwAAAA==.Rainyblu:BAAANQAECgQIBAAAAA==.Rawrshåk:BAABNQAECn8sAAMSAAkKFx7cQgDBAgASAAkKnR3cQgDBAgARAAIKhhggFgCVAAAAAA==.',
Rb='Rb:BAAANQAECgEIAwAAAA==.',
Rc='Rc:BAABNQAECn8lAAIdAAcKkBt0DQClAQAdAAcKkBt0DQClAQAAAA==.',
Re='Rennalla:BAAANQADCgcIBwABNQAECgoKPwAJAOofAA==.',
Rh='Rhizomb:BAAANQAECgEIAQAAAA==.Rhodraco:BAABNQAECn8ZAAMlAAcKTQZPEgCuAAAlAAYKpQZPEgCuAAAmAAQKmQVCHgBvAAAAAA==.Rhownyn:BAAANQADCgUICgAAAA==.Rhoxy:BAAANQADCggIEwAAAA==.',
Ri='Rikku:BAAANQADCgEIAQAAAA==.Ripforged:BAABNQAECn8pAAISAAgKnBfOUwCHAQASAAgKnBfOUwCHAQABNQAECggKKQASAJwXAA==.',
Rn='Rn:BAAANQAECgIIAgAAAA==.',
Ro='Rolgar:BAAANQADCgYIBwAAAA==.',
Rq='Rq:BAAANQAECgcICgAAAA==.',
Ry='Ryyukken:BAAANQAECgIIBQAAAA==.',
['Rà']='Ràwrshåk:BAAANQAECgEIAQAAAA==.',
Sa='Saella:BAAANQAECgQIBgAAAA==.Sakarja:BAAANQADCgQIBAAAAA==.Saluda:BAAANQAECgUIDgAAAA==.Samesde:BAAANQAECgQIDQAAAA==.Sampson:BAAANQAECgcIBwABNQAECgkJPQAZALUeAA==.Samras:BAAANQAECgcICgAAAA==.Saphyria:BAAANQAECgEIAQAAAA==.Sarentu:BAACNQAFFH8HAAIjAAQKSxCGDADZAAAjAAQKSxCGDADZAAA1AAQKfykAAiMACgo6Hy4RANcCACMACgo6Hy4RANcCAAAA.Satoru:BAAANQADCgUIBQAAAA==.',
Se='Seanjohn:BAAANQAECgEIAQAAAA==.Senile:BAABNQAECn8aAAInAAcKBBP8AwCJAQAnAAcKBBP8AwCJAQAAAA==.Sertia:BAAANQADCgEIAQAAAA==.Sesnic:BAAANQAECgQIEwAAAA==.',
Sh='Shaady:BAAANQABCgIIAgABNQADCgYIBgAMAAAAAA==.Shadesoflife:BAAANQABCgMIAwAAAA==.Shadydice:BAAANQADCgYICwABNQADCgYIBgAMAAAAAA==.Shadydk:BAAANQADCgYIBwABNQADCgYIBgAMAAAAAA==.Shadylid:BAAANQADCgYIBgAAAA==.Shadysmash:BAAANQADCggIEAAAAA==.Shadyvoid:BAAANQAECgUICAABNQADCgYIBgAMAAAAAA==.Shadówglider:BAAANQAECgQIDgAAAA==.Shaelia:BAAANQADCgIIAgAAAA==.Shale:BAABNQAECn8eAAIKAAoKVx6bGQCNAgAKAAoKVx6bGQCNAgAAAA==.Shamallaman:BAAANQAECgUJCQABNQAECgoKIwACAEchAA==.Shanck:BAAANQAECgUIBQAAAA==.Sharkweek:BAAANQAECgMIBAAAAA==.Shazám:BAAANQAECgIIAgAAAA==.Sheol:BAAANQADCggIFQAAAA==.Sheyoni:BAAANQADCggJGgAAAA==.Shreck:BAAANQAECggIAQAAAA==.Shydestroyer:BAAANQAECgEIAQAAAA==.',
Si='Si:BAABNQAECn8iAAIIAAkKoR0kGwCGAgAIAAkKoR0kGwCGAgAAAA==.Siersha:BAAANQADCgEIAQAAAA==.Sinfulness:BAAANQAECgUIEgAAAA==.',
Sk='Skikette:BAABNQAECn8tAAIPAAkKkAZehQDpAAAPAAkKkAZehQDpAAAAAA==.Skinrot:BAABNQAECn8uAAIXAAoKpAzSHgBpAQAXAAoKpAzSHgBpAQAAAA==.',
Sm='Smig:BAABNQAECn8UAAISAAYKeweZsQCpAAASAAYKeweZsQCpAAAAAA==.',
Sn='Snowball:BAABNQAECn8XAAIQAAgKqRWhCwCFAQAQAAgKqRWhCwCFAQAAAA==.',
So='Soeki:BAABNQAECn8YAAIYAAcK1g8gBwAJAQAYAAcK1g8gBwAJAQAAAA==.Soluthon:BAAANQADCgQIBAAAAA==.Sonyaa:BAAANQADCgcICQAAAA==.Soullove:BAABNQAECn8qAAIYAAkK8xUNDwAKAgAYAAkK8xUNDwAKAgABNQAECgkJLgAXAH8YAA==.Soullovez:BAABNQAECn8uAAMXAAkKfxjRHABOAgAXAAkKfxjRHABOAgAVAAQKJQQRkQCTAAAAAA==.Soulshocks:BAABNQAECn8oAAINAAkKcwwoRgA9AQANAAkKcwwoRgA9AQABNQAECgkJLgAXAH8YAA==.Soulviver:BAABNQAECn8xAAIIAAkK0RGOZADyAQAIAAkK0RGOZADyAQAAAA==.',
Sp='Spiritwarden:BAABNQAECn8tAAIjAAoKsR2aEADfAgAjAAoKsR2aEADfAgAAAA==.Spliffy:BAAANQADCgQIBAAAAA==.Splootz:BAAANQADCggIEAABNQAFFAMIAwAMAAAAAA==.Spoiledbratt:BAAANQAECgIIBAAAAA==.',
Sq='Squirtdadday:BAAANQAECgIIAgAAAA==.',
St='Stargasm:BAAANQAECgEIAQAAAA==.Stimer:BAABNQAECn9DAAQSAAoKjyWjCACuAwASAAoKxSOjCACuAwAQAAgKQiRqCADMAgARAAYKWSHODQDXAQAAAA==.Stori:BAAANQADCggIEQAAAA==.',
Su='Sultanofswat:BAAANQADCgYIBgAAAA==.Sunshiny:BAAANQADCggIDwAAAA==.Suxor:BAAANQAECgQIDwAAAA==.',
Sw='Swordboardal:BAACNQAFFH8IAAIQAAMKMQ2JBQCoAAAQAAMKMQ2JBQCoAAA1AAQKfzIAAhAACgqRFZAHAOoBABAACgqRFZAHAOoBAAAA.',
Sy='Sybius:BAAANQAECgQJCQAAAA==.Symptom:BAAANQAECgEIAgAAAA==.Syncophat:BAABNQAECn8gAAIFAAcKDBrbXwB/AQAFAAcKDBrbXwB/AQAAAA==.',
Ta='Tad:BAAANQAECgMIAwAAAA==.Taint:BAAANQADCgUICQAAAA==.Takia:BAAANQAECgQIEQAAAA==.Talanzen:BAABNQAECn8fAAIZAAoKYCHwQQABAwAZAAoKYCHwQQABAwAAAA==.Talonia:BAAANQAECgQIBQABNQAECgkJIgAFAMkcAA==.Tanakiko:BAAANQADCgUIBQAAAA==.Tarrzok:BAAANQADCgcICAABNQADCgYIBgAMAAAAAA==.',
Te='Teacup:BAAANQAECgIICAABNQAECgoKIgAaAEIaAA==.',
Th='Thrakara:BAACNQAFFH8ZAAMiAAYKswdeAwA7AQAiAAYKswdeAwA7AQAjAAMKPQwbDQDNAAA1AAQKfzAAAyIACgp4F8YRAGECACIACgp4F8YRAGECACMABApJHiI4AFMBAAAA.Thrakaru:BAABNQAECn8eAAIZAAkKihIymgBMAgAZAAkKihIymgBMAgAAAA==.Thrakumi:BAAANQADCgcIBwAAAA==.Thunderhorns:BAAANQAECgcIEgAAAA==.Thundrall:BAAANQAECgQICwAAAA==.',
Ti='Tightspaces:BAAANQABCgMIAwAAAA==.Tiltéd:BAABNQAECn8pAAMeAAoKJx7DBwAbAgAeAAkKix3DBwAbAgAkAAYKjx4gLgDAAQAAAA==.Tioshadow:BAAANQAECgIIAwABNQAFFAQIBwAjADkSAA==.',
To='Tobaeus:BAAANQADCgYICgAAAA==.Todem:BAAANQADCgEIAQAAAA==.Torches:BAAANQADCgcIBwAAAA==.Totemissues:BAAANQABCgMIAwABNQAECgoKNAAFAEgcAA==.',
Tr='Trayleen:BAAANQADCgUJBQAAAA==.Triad:BAAANQADCgYJBgAAAA==.Truths:BAACNQAFFH8XAAISAAgK0hovBQB8AgASAAgK0hovBQB8AgA1AAQKfx0AAhIACgqfIYo1AOwCABIACgqfIYo1AOwCAAAA.Trystrom:BAAANQADCgYIDAAAAA==.',
Ts='Tsuo:BAAANQAECgcIDwAAAA==.Tsuoshock:BAAANQAECgUIBQAAAA==.',
Tx='Txavenger:BAAANQAECgIIAgAAAA==.Txblood:BAAANQADCgcICAAAAA==.Txfury:BAAANQAECgEIAQAAAA==.Txgunny:BAABNQAECn8iAAISAAcKmgePjgDyAAASAAcKmgePjgDyAAAAAA==.Txstormin:BAAANQAECgEIAQAAAA==.',
Ty='Tyfuun:BAAANQAECgMIBAABNQAFFAUICAABALsGAA==.Tymptriss:BAAANQAECgUIEwAAAA==.',
['Tí']='Títus:BAAANQAECgIIAgAAAA==.',
Um='Umbrage:BAAANQAECggIDwABNQAFFAYIHQAdAIEbAA==.Umbren:BAABNQAECn8iAAMFAAkKyRwnWwBjAgAFAAkKyRwnWwBjAgAEAAEK3ABKoQAXAAAAAA==.',
Ur='Urabadkity:BAAANQADCgYIEwAAAA==.',
Us='Usefulmelee:BAABNQAECn8aAAMkAAoKCRBCJgD0AQAeAAoKFA7zMQAXAgAkAAoK2A5CJgD0AQABNQAFFAYIHgAFADocAA==.',
Va='Valartha:BAABNQAECn8TAAIVAAUKrw5OSwCYAAAVAAUKrw5OSwCYAAAAAA==.Variste:BAAANQADCgMIAwAAAA==.',
Ve='Veil:BAAANQADCggJCAAAAA==.Velkån:BAAANQAECgEIAQAAAA==.Vellmora:BAAANQADCgUJBgAAAA==.Velsea:BAAANQAECgQIBgAAAA==.Velstadt:BAABNQAECn8qAAMjAAgK6xrSHQBGAgAjAAgK6xrSHQBGAgAhAAQKdxSAHwDuAAAAAA==.Venhance:BAAANQAECgcJEAAAAA==.Venotu:BAABNQAECn8lAAIBAAkK7htTDADUAgABAAkK7htTDADUAgAAAA==.Vermilion:BAAANQAECgcIDgAAAA==.Vertebrae:BAAANQADCgYICAAAAA==.',
Vh='Vholatile:BAABNQAECn8YAAMOAAgKLw+/CAAAAgAOAAgKLw+/CAAAAgAYAAIKGgQTcwA8AAAAAA==.',
Vi='Violence:BAAANQADCgYIBgAAAA==.Viviel:BAAANQAECgcIKAAAAQ==.',
Vo='Voidherron:BAAANQAECgYIEAAAAA==.Voidknight:BAAANQAECgEIAQAAAA==.Voodoomama:BAAANQADCgYIEQAAAA==.',
Wa='Waq:BAAANQADCgUIBQAAAA==.Warlockbot:BAACNQAFFH8PAAIPAAUK1xK4EQBxAQAPAAUK1xK4EQBxAQA1AAQKfyMAAg8ACgqjG1czALwCAA8ACgqjG1czALwCAAAA.Warmongral:BAAANQADCgYIDwAAAA==.Waterboot:BAAANQADCgQIBwAAAA==.Wattheyneed:BAAANQAECgEIAwAAAA==.',
We='Wendi:BAABNQAECn8aAAIYAAcKQwc/JwA9AQAYAAcKQwc/JwA9AQAAAA==.',
Wh='Wholesome:BAAANQADCgcICwAAAA==.',
Wi='Wig:BAAANQADCggIEgABNQAECgoKKQAeACceAA==.Wildbill:BAAANQADCgYIBwAAAA==.Windcrow:BAAANQADCggICAAAAA==.Withher:BAAANQADCggICAAAAA==.',
Wo='Wombo:BAAANQAECgMIBQAAAA==.Woolala:BAABNQAECn8/AAIFAAoKchjWNwDDAgAFAAoKchjWNwDDAgAAAA==.',
Wr='Wrahirn:BAAANQABCgYIBgAAAA==.Wrathran:BAAANQAECgIJAgAAAA==.',
Wu='Wut:BAAANQAECgcIDwABNQAECgoKMgAdABUeAA==.',
Xa='Xahiri:BAAANQADCgYIBgAAAA==.Xalisto:BAAANQADCgYICQAAAA==.',
Xl='Xlia:BAAANQAECgMIBgAAAA==.',
Ya='Yaana:BAAANQAECgEIAQAAAA==.Yazmyn:BAABNQAECn8XAAIhAAgK5QxbFgB+AQAhAAgK5QxbFgB+AQAAAA==.',
Ye='Yerehmi:BAAANQAECgEIAgAAAA==.',
Yu='Yuny:BAABNQAECn8vAAIiAAgKqBOGDQCxAQAiAAgKqBOGDQCxAQAAAA==.',
Za='Zaier:BAABNQAECn9GAAMDAAoKHSAABgBwAwADAAoKHSAABgBwAwACAAgKcA3JlAApAQAAAA==.',
Ze='Zeltan:BAABNQAECn9aAAIDAAoK0B9fEQBDAwADAAoK0B9fEQBDAwAAAA==.',
Zh='Zhundrenga:BAAANQAECgQIDgAAAA==.',
Zo='Zoma:BAAANQADCgEIAQAAAA==.',
Zp='Zpad:BAAANQADCgcIBwAAAA==.',
['År']='Åres:BAAANQAECgEIAwAAAA==.',
['ßl']='ßlastvenom:BAAANQADCgYICQAAAA==.',
['ßä']='ßäbaracus:BAAANQADCgQIBAAAAA==.',
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
