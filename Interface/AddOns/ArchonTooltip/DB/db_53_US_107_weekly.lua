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

local lookup = {'Paladin-Protection','Paladin-Retribution','Paladin-Holy','Hunter-Marksmanship','Hunter-BeastMastery','Priest-Shadow','Priest-Discipline','Priest-Holy','DemonHunter-Havoc','DemonHunter-Devourer','DemonHunter-Vengeance','Unknown-Unknown','Shaman-Elemental','Warlock-Affliction','Warlock-Demonology','Warrior-Protection','Warrior-Arms','Warrior-Fury','DeathKnight-Blood','DeathKnight-Unholy','Druid-Balance','Druid-Guardian','Druid-Restoration','Warlock-Destruction','Mage-Arcane','DeathKnight-Frost','Druid-Feral','Shaman-Restoration','Evoker-Preservation','Rogue-Assassination','Mage-Frost','Shaman-Enhancement','Monk-Brewmaster','Monk-Mistweaver','Monk-Windwalker','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','Mage-Fire',}
local provider = {region='US',realm='Gilneas',name='US',type='weekly',zone=53,date='2026-11-03',data={Ac='Acks:BAAANQADCgYICgABNQAFFAUICQABALsGAA==.',
Ae='Aedra:BAAANQAECgIIAgAAAA==.Aeowyyn:BAABNQAECn8cAAMCAAgKjgoR/QAlAQACAAcKVQYR/QAlAQADAAIKlQeNyQBYAAAAAA==.Aex:BAABNQAECn8aAAMEAAoKtxHYKADqAAAEAAkKCRHYKADqAAAFAAMKygkHKAGkAAABNQAFFAUICQABALsGAA==.',
Af='Afib:BAAANQAECgEIAgAAAA==.',
Ah='Ahnkhano:BAAANQAECgYIBgAAAA==.',
Ai='Ainge:BAAANQAECgEIAQAAAA==.Airiistra:BAAANQADCgMIAwAAAA==.',
Ak='Akbartheiiv:BAACNQAFFH8ZAAMGAAgKzBhIAgBxAgAGAAcK7xtIAgBxAgAHAAIKSwM+AgBQAAA1AAQKf2kAAwYACgpqJqIAAPMDAAYACgpqJqIAAPMDAAcACArUJBoBAFkDAAAA.Akorius:BAAANQAECgIIAgAAAA==.',
Al='Alarion:BAAANQAECgIIAgAAAA==.Allistrana:BAABNQAECn8qAAIIAAgK5BwrQgBjAgAIAAgK5BwrQgBjAgAAAA==.Allpower:BAAANQADCgYIDgAAAA==.Alpacalyptic:BAAANQAECgcICQAAAA==.Alyx:BAAANQADCgcIBwAAAA==.',
Am='Amadeux:BAAANQADCgIIAgABNQAECgoKJQAFAI0cAA==.Amairis:BAABNQAECn8dAAMHAAYKyxAvCAAHAQAHAAYKyxAvCAAHAQAGAAQKcwh1UwDAAAAAAA==.Ambiorix:BAAANQABCgUIBQAAAA==.',
An='Anrion:BAABNQAECn9CAAQJAAoKICADEQAXAwAJAAoK4x8DEQAXAwAKAAYKsRgsPABmAQALAAIKZCNfIgCvAAAAAA==.Antiflag:BAAANQAECgYIBgAAAA==.Anzania:BAAANQADCgEIAQABNQADCgYIEwAMAAAAAA==.',
Ar='Arolz:BAAANQADCgYIBgAAAA==.',
At='Ataliya:BAABNQAECn8aAAINAAYK6AsKqwA+AQANAAYK6AsKqwA+AQAAAA==.',
Au='Auranar:BAABNQAECn8dAAIEAAgKbATgKgDdAAAEAAgKbATgKgDdAAAAAA==.Aurelya:BAABNQAECn8kAAIIAAcKsw7DggCPAQAIAAcKsw7DggCPAQAAAA==.Aurilia:BAAANQAECgQIEgAAAA==.',
Av='Avanicus:BAABNQAECn8ZAAMOAAkK/wy1CwCsAQAOAAgKcA21CwCsAQAPAAMKJAdeNAFRAAAAAA==.Aven:BAAANQAECgEIAQAAAA==.Avernas:BAAANQAECgQIBAAAAA==.Avé:BAABNQAECn8wAAMCAAkK4hR6fACUAQACAAkK4hR6fACUAQABAAQKRA0ZTgCwAAAAAA==.',
Ax='Axellent:BAACNQAFFH8MAAIQAAQK/g4CAgD2AAAQAAQK/g4CAgD2AAA1AAQKfzYABBAACgqRHY0IABsCABAACgpVGo0IABsCABEACAoLG5xPAN0BABIABQq/GkwSAH8BAAE1AAUUBQgJAAEAuwYA.Axiomlegacy:BAABNQAECn8nAAMTAAoKUCEKDgBAAwATAAoKUCEKDgBAAwAUAAEKpwgs5gAuAAAAAA==.',
Az='Azraith:BAAANQADCgcIBgAAAA==.Azulien:BAAANQAECgcIDQAAAA==.Azulin:BAAANQADCgUJBQAAAA==.',
Ba='Banderblitz:BAABNQAECn8pAAMSAAkKyRYSDgDSAQARAAkKaBLXjQD6AQASAAcKcRkSDgDSAQAAAA==.Banzgrave:BAAANQADCgcIBgAAAA==.Bar:BAACNQAFFH8IAAMIAAYKVQOqEwA0AQAIAAUKjgOqEwA0AQAGAAIK8wNpFQBzAAA1AAQKfx8AAwYACgrMGa0kAAsCAAYACAqMGK0kAAsCAAgACQrrCqGIAH0BAAAA.',
Be='Bearlyshady:BAABNQAECn9LAAQVAAoK9hooFQBCAgAVAAoK9hooFQBCAgAWAAQK9gmiQgCsAAAXAAEKugNHeQAsAAABNQADCgYIBgAMAAAAAA==.Bellarina:BAAANQAECgQICwAAAA==.Bellatrixie:BAAANQAECgQIDwAAAA==.Bennitely:BAAANQADCgEIAQAAAA==.Beriadhwen:BAAANQAECgUIBQAAAA==.Bermy:BAABNQAECn8gAAMYAAoKfAr5FgC1AQAYAAoKegn5FgC1AQAPAAUKWwgdxwCUAAAAAA==.Berzerkercow:BAAANQADCgYIBwAAAA==.Bewildert:BAAANQADCgMIBAAAAA==.',
Bh='Bhawkwco:BAAANQADCgUIBQAAAA==.',
Bi='Bigjaina:BAABNQAECn89AAIZAAkKtR4bWgDLAgAZAAkKtR4bWgDLAgAAAA==.Biku:BAAANQAECgUIEQAAAA==.Bitesthesky:BAAANQAECgUIBQAAAA==.',
Bl='Blackhawkdk:BAABNQAECn80AAMUAAoKRhkuFgAQAgAUAAoKRhkuFgAQAgATAAEKAADExQA9AAAAAA==.Blackhawkm:BAAANQADCgcIBwAAAA==.Blende:BAAANQAECgQIBQABNQAECgcIEgAMAAAAAA==.Blindwarrior:BAAANQAECgIIAgAAAA==.Bloodshadow:BAABNQAECn8iAAIFAAcKvgsglwA/AQAFAAcKvgsglwA/AQAAAA==.',
Bo='Boraffe:BAAANQADCgMJAgAAAA==.Bovinity:BAAANQABCgcICgAAAA==.',
Br='Breakcooloz:BAAANQAFFAEIAQABNQAFFAUIBQAUAJoTAA==.Bretcoe:BAAANQADCgYIDAABNQAECgIIAgAMAAAAAA==.Bronzamdee:BAAANQADCggJCAAAAA==.Brooce:BAABNQAECn83AAICAAgK8R1qYAB4AgACAAgK8R1qYAB4AgAAAA==.Broom:BAAANQAECgcICgABNQAECgkJPQAZALUeAA==.Brozken:BAAANQADCgUICAAAAA==.Brutak:BAAANQADCggICAAAAA==.',
Bu='Burstinurass:BAACNQAFFH8FAAIUAAUKmhPDCACMAQAUAAUKmhPDCACMAQA1AAQKfx0AAhQACgqnHlYcAOICABQACgqnHlYcAOICAAAA.Buzzliteyear:BAAANQADCgUIBQAAAA==.',
['Bä']='Bängbäng:BAAANQADCgYICgAAAA==.',
Ca='Caelix:BAAANQAECgQIBQAAAA==.Canadiana:BAAANQADCgYIBgAAAA==.Carafe:BAAANQAECgYICwABNQAECgoKJQAaAEIaAA==.Carbo:BAAANQAECgYICgABNQAECgoKJwAbABckAA==.Carbonight:BAABNQAECn8nAAIbAAoKFyTHAwBeAwAbAAoKFyTHAwBeAwAAAA==.Carlos:BAAANQAECggIDgAAAA==.',
Ce='Celani:BAAANQADCggICAABNQAECggIFgAcACENAA==.Celintha:BAAANQADCgcICAAAAA==.Cellyne:BAAANQAECgQIEgAAAA==.',
Ch='Chaoswind:BAABNQAECn9EAAIcAAoK0xq1LQCrAgAcAAoK0xq1LQCrAgAAAA==.Charlee:BAABNQAECn8cAAIFAAkKERBXXADLAQAFAAkKERBXXADLAQAAAA==.Chaz:BAAANQAECgIIAgAAAA==.Cheeb:BAAANQADCgcIBwAAAA==.Cheebie:BAAANQABCgYIBgABNQADCgcIBwAMAAAAAA==.Chelives:BAEBNQAECn8mAAIQAAgKfALZJQCZAAAQAAgKfALZJQCZAAAAAA==.Cherryb:BAAANQABCgYIDAAAAA==.Chromus:BAACNQAFFH8eAAIdAAcKmhgHBAA1AgAdAAcKmhgHBAA1AgA1AAQKfyoAAh0ACgrrHHgNAM8CAB0ACgrrHHgNAM8CAAAA.',
Ci='Cires:BAABNQAECn8zAAIeAAoKnxU4EACiAQAeAAoKnxU4EACiAQAAAA==.',
Cl='Clareclaymor:BAAANQADCgUIBQAAAA==.',
Co='Colanasou:BAAANQAECgQIDQAAAA==.Coldbattler:BAAANQAECgYIEAAAAA==.Convictions:BAAANQAECgYICwABNQAFFAgIFwARANIaAA==.Coppermöuth:BAAANQADCgYIBgAAAA==.Corrick:BAAANQAECgQICAAAAA==.Cowpatty:BAAANQADCgQIBAAAAA==.',
Cr='Crow:BAAANQAFFAYIDwAAAQ==.',
Cy='Cydric:BAABNQAECn8lAAICAAoK3B3oLQCAAgACAAoK3B3oLQCAAgAAAA==.',
Da='Daarrkstar:BAAANQAECgcIEgAAAA==.Dakaryn:BAAANQADCggIDQAAAA==.Damageguy:BAAANQAECgYIBgABNQAFFAcIIAARAIMeAA==.Darkynlord:BAAANQADCggICAAAAA==.',
De='Deadskvll:BAAANQADCgYIBgAAAA==.Deathbattler:BAAANQADCggIFAAAAA==.Deathrival:BAAANQADCggICAAAAA==.Dehnis:BAAANQADCgQIBAAAAA==.Delta:BAAANQADCgYICwAAAA==.Demonkare:BAAANQAECgUICgABNQAECgoKQAABAJEkAA==.Demoray:BAACNQAFFH8lAAMEAAgK3hyJBAAqAgAEAAcKuBuJBAAqAgAFAAEKmSI0LgBmAAA1AAQKfzEAAwQACgo0JmoGAGoDAAQACgo0JmoGAGoDAAUAAQppI/8GAWcAAAAA.Demvinity:BAAANQAECgQIDAAAAA==.Dethrone:BAABNQAECn8vAAMPAAoK9h4EIABuAgAPAAkKRh8EIABuAgAYAAIKnRq8TACZAAAAAA==.Deus:BAABNQAECn87AAMGAAgKBRMfKwDOAQAGAAcKXhMfKwDOAQAHAAYKAxXwDgA9AQAAAA==.Dezka:BAAANQADCggICAAAAA==.',
Di='Dinosocks:BAACNQAFFH8PAAMFAAcK8AyyEABSAQAFAAQKwhKyEABSAQAEAAQKPANvFAD5AAA1AAQKfz0AAwQACgqLGkoZAH4BAAUACAoiGXV0ACcCAAQACQoGFkoZAH4BAAAA.Dirtydragon:BAABNQAECn8sAAIdAAkKNCDgBgDBAgAdAAkKNCDgBgDBAgAAAA==.Divinedecay:BAABNQAECn8hAAITAAgKhw7MPAAkAQATAAgKhw7MPAAkAQABNQAECgoKOAAFAHMcAA==.',
Dj='Djaequitas:BAAANQABCgQIBgAAAA==.Djmelisandra:BAAANQABCgQIBAAAAA==.Djshamy:BAAANQABCgUICAAAAA==.',
Do='Dok:BAAANQAECgUICgAAAA==.Donoraginn:BAAANQADCggIRQAAAA==.Donos:BAAANQADCggIMwABNQADCggIRQAMAAAAAA==.Dontkare:BAAANQADCgMIAwABNQAECgoKQAABAJEkAA==.Dorsai:BAAANQADCgUIBQAAAA==.Dotgenerate:BAAANQAECgQIBQAAAA==.',
Dr='Dracorex:BAAANQAECgEIAQAAAA==.Drark:BAAANQAECgIIBAAAAA==.Drathiel:BAAANQAECgEIAQAAAA==.Drayzr:BAAANQADCgUIBQAAAA==.Drizztknight:BAAANQADCgYIBgAAAA==.Drwho:BAABNQAECn8XAAMfAAgKNRfXDwCqAQAfAAcKtRfXDwCqAQAZAAQKRxWTYQHxAAAAAA==.Drääx:BAAANQADCgQIBAAAAA==.Dräëxx:BAAANQADCgcIBwAAAA==.Drëëxx:BAAANQAECgEIAQAAAA==.',
Du='Duckymet:BAAANQADCggIEwAAAA==.Duvari:BAAANQAECgEIAQAAAA==.',
Dw='Dwallin:BAAANQADCgQIBAAAAA==.',
Dy='Dyane:BAAANQADCgQIBAAAAA==.',
['Dô']='Dôz:BAAANQAECgQIBwAAAA==.',
Ed='Edoaldor:BAAANQAECgQIBAAAAA==.',
El='Ellery:BAAANQADCgUJBQAAAA==.',
Em='Empyrean:BAAANQAECgQIBQAAAA==.',
Ex='Exhumina:BAAANQAECgMIDgAAAA==.',
Fa='Facestealerr:BAABNQAECn8XAAIPAAUKQhDItwCwAAAPAAUKQhDItwCwAAAAAA==.',
Fe='Felgibson:BAAANQADCgYIDQAAAA==.Fenmoon:BAABNQAECn8pAAIVAAoKtQxgKACCAQAVAAoKtQxgKACCAQAAAA==.',
Fi='Finneaa:BAAANQADCgUIBQAAAA==.',
Fl='Flairrick:BAABNQAECn8gAAISAAgKFhb6CwCHAQASAAgKFhb6CwCHAQAAAA==.Flars:BAABNQAECn87AAIaAAoKASbyAgBcAwAaAAoKASbyAgBcAwAAAA==.Flatliner:BAABNQAECn8ZAAIDAAgKPge3iQB/AQADAAgKPge3iQB/AQAAAA==.Flik:BAAANQAECgcIEgABNQAFFAUICQABALsGAA==.',
Fo='Forq:BAAANQADCgcIDgAAAA==.',
Fr='Frakz:BAAANQADCgUIBQAAAA==.Fran:BAAANQADCgYIBgABNQAECgkJPQAZALUeAA==.Frankzappn:BAABNQAECn8pAAQNAAkK+hrCOgCLAgANAAgKJBzCOgCLAgAgAAcKDBJMEwCbAQAcAAMKhwFBFQE/AAAAAA==.Fray:BAAANQADCggICAAAAA==.Freeguy:BAABNQAECn80AAIKAAkKAhj+IABEAgAKAAkKAhj+IABEAgAAAA==.Fruitcakes:BAABNQAECn8aAAQhAAYK0QTMIwC2AAAhAAUK/gPMIwC2AAAiAAUKLwUSOACtAAAjAAQK4gNeWgB8AAAAAA==.',
Fu='Fuddicus:BAAANQAECgIIAwAAAA==.Fuddrael:BAABNQAECn8oAAILAAoKxQk9FgBJAQALAAoKxQk9FgBJAQAAAA==.Fuddrucker:BAAANQAECgIIAgAAAA==.Fuddster:BAAANQADCgQIBAAAAA==.',
Ga='Gaddess:BAABNQAECn8mAAIGAAgKrgZdLADpAAAGAAgKrgZdLADpAAAAAA==.Gamork:BAAANQAECgEIAQABNQAECggIIwAGAO4XAA==.Gandàlf:BAAANQADCgYIBgAAAA==.Ganymede:BAAANQAECgUIBwAAAA==.Garan:BAAANQADCgMIAwAAAA==.',
Ge='Geilamaine:BAABNQAECn8qAAQDAAoKnBcAVQAbAgADAAoKnBcAVQAbAgACAAMKDQnSTgFLAAABAAEK8AKTYwAhAAAAAA==.Gerona:BAAANQAECgEIAQAAAA==.',
Gl='Glimagi:BAAANQAECgQIDwAAAA==.',
Gn='Gnxr:BAEANQAECgIIAgABNQAFFAQICwAjAH4jAA==.',
Go='Gonefishing:BAAANQADCgYIBgABNQAECgoKRQAFAIkYAA==.Goretex:BAAANQADCgEIAQABNQADCgcIBwAMAAAAAA==.Gotêtsu:BAAANQAECggIEwAAAA==.',
Gr='Grimjawz:BAABNQAECn86AAIXAAoKNh+NBgBHAwAXAAoKNh+NBgBHAwAAAA==.Grimpath:BAAANQAECgEIAgAAAA==.Grippysocks:BAAANQAFFAIIAgABNQAFFAcIDwAFAPAMAA==.',
Gu='Gummibear:BAABNQAECn8hAAMQAAUKWA9rIADCAAAQAAUKWA9rIADCAAARAAEK+wQ6VQExAAAAAA==.Gurranq:BAAANQAECgEIAQABNQAECggIIwAGAO4XAA==.',
Gw='Gwiyomi:BAAANQAECgIIAgABNQAECgoKGQAaAHAgAA==.',
Gy='Gyr:BAAANQAECgcICAAAAA==.',
Ha='Hakai:BAAANQADCgEIAQABNQAECgoKLgAJAAsUAA==.Hanbor:BAAANQADCgcIBwAAAA==.Haniku:BAABNQAECn8VAAIRAAgKtgg2xwBqAQARAAgKtgg2xwBqAQAAAA==.Harthoon:BAACNQAFFH8cAAIZAAcKLwgFDABjAQAZAAcKLwgFDABjAQA1AAQKfzIAAx8ACgq6HCULABMCABkACgoYElyeAEQCAB8ACAqAHiULABMCAAAA.',
He='Henos:BAAANQAECgUICAAAAA==.',
Ho='Hobomatt:BAAANQADCggICAAAAA==.Holiebelle:BAABNQAECn8bAAIDAAgKEBabRADOAQADAAgKEBabRADOAQAAAA==.Holyhutch:BAAANQAECgcIDwABNQAECgoKPAAPACodAA==.Holyshield:BAAANQADCgEIAQABNQAECgoKMgAIAPAeAA==.Honeynoats:BAABNQAECn8lAAIIAAgKiQnjhACIAQAIAAgKiQnjhACIAQAAAA==.Hotdwarf:BAABNQAECn8hAAQDAAYKAA7auwAEAQADAAUKbQvauwAEAQABAAUKlAeRSADLAAACAAIK4AbvNwFnAAAAAA==.',
Hr='Hrumm:BAACNQAFFH8cAAMEAAcK9xWNCAC/AQAEAAcKGBSNCAC/AQAFAAEKkw99JwBYAAA1AAQKfysAAwQACgqPGu4YAJACAAQACgqPGu4YAJACAAUABQpuCj8MAe4AAAAA.',
Hu='Hullkk:BAACNQAFFH8gAAIRAAcKgx7zBgBSAgARAAcKgx7zBgBSAgA1AAQKfy8AAhEACgqfJVcQAH0DABEACgqfJVcQAH0DAAAA.Hun:BAAANQAECggICAAAAA==.Hush:BAAANQAECgUIBwAAAA==.Hutchadina:BAAANQAECgEIAwABNQAECgoKPAAPACodAA==.Hutchanova:BAAANQAECgQIBgABNQAECgoKPAAPACodAA==.Hutchi:BAAANQAECgYICAABNQAECgoKPAAPACodAA==.Hutchkins:BAABNQAECn88AAIPAAoKKh0aFwChAgAPAAoKKh0aFwChAgAAAA==.Hutchknight:BAABNQAECn8VAAMTAAcK1BftMQBZAQATAAcK1BftMQBZAQAUAAMKxAbXuAB7AAABNQAECgoKPAAPACodAA==.Hutchstab:BAAANQAECgQIBAABNQAECgoKPAAPACodAA==.Hutchyo:BAAANQAECgIIAgABNQAECgoKPAAPACodAA==.',
Hy='Hyd:BAAANQADCgQIAQABNQADCgcICQAMAAAAAA==.Hydro:BAAANQADCgcICQAAAA==.',
['Hä']='Häwtz:BAAANQAECgIIAgAAAA==.',
Ic='Icerus:BAABNQAECn8UAAIIAAoKZBG6LQBZAgAIAAoKZBG6LQBZAgAAAA==.Icirus:BAABNQAECn9HAAMDAAoK1yCPDQA0AwADAAoK1yCPDQA0AwACAAQKkQqNSQGqAAAAAA==.',
Il='Illaandra:BAAANQADCgUIBQABNQAECgEIAQAMAAAAAA==.',
Im='Imsanity:BAAANQADCgQIBAAAAA==.',
In='Inseng:BAABNQAECn8ZAAMaAAoKcCCACQBRAwAaAAoKcCCACQBRAwATAAUKjhhBcQAwAQAAAA==.Invisibo:BAAANQAECgEIAQABNQAECggIIwAGAO4XAA==.',
It='Itzal:BAAANQAECgYIBgAAAA==.',
Ja='Jagere:BAABNQAECn8xAAIFAAoKjxGBQwATAgAFAAoKjxGBQwATAgAAAA==.Jahde:BAABNQAECn8cAAIVAAgKQQX+UQCqAAAVAAgKQQX+UQCqAAAAAA==.Jaina:BAABNQAECn8YAAIFAAYK7A09tgABAQAFAAYK7A09tgABAQAAAA==.Jandrae:BAABNQAECn87AAQaAAoKeRxzGgC3AgAaAAoKABtzGgC3AgAUAAUKFx6zYACNAQATAAIKqwfxuwBQAAAAAA==.Jassykins:BAABNQAECn8ZAAIFAAgKBQgHkgBKAQAFAAgKBQgHkgBKAQAAAA==.',
Je='Jessecuster:BAAANQADCgQJBAAAAA==.',
Ji='Jiffypop:BAAANQAECgIIAwABNQAECgUIBwAMAAAAAA==.Jillotty:BAAANQADCgUIBAAAAA==.Jirachii:BAAANQAECgEIAgABNQAFFAMICAAVACENAA==.',
Jo='Joanofarc:BAAANQADCgUJBQAAAA==.Joloc:BAABNQAECn8fAAIYAAcKIg2zGACmAQAYAAcKIg2zGACmAQAAAA==.Jonpaul:BAAANQABCgEIAQAAAA==.',
Ju='Jueles:BAAANQADCgMIAwABNQAECggIHAAVAEEFAA==.',
['Jì']='Jìnx:BAAANQADCgQIBQAAAA==.',
Ka='Kaelaria:BAAANQADCgIIAgAAAA==.Kalrosa:BAABNQAECn8ZAAMSAAcKFRPrDwA4AQARAAcKvQ+geABiAQASAAYKAhTrDwA4AQABNQAECgkJKQASAMkWAA==.Kare:BAAANQAECgYIEQABNQAECgoKQAABAJEkAA==.Karee:BAABNQAECn9AAAIBAAoKkSQyAgCuAwABAAoKkSQyAgCuAwAAAA==.Karfren:BAAANQAECgEJAQAAAA==.Kauko:BAAANQAECggICAAAAA==.Kazer:BAAANQADCgYJBgAAAA==.',
Ke='Kermodk:BAABNQAECn8qAAITAAkKZiHiFgD2AgATAAkKZiHiFgD2AgAAAA==.',
Kh='Khold:BAABNQAECn8gAAIBAAgK8BC7LAB3AQABAAgK8BC7LAB3AQAAAA==.',
Ki='Kissofdeath:BAAANQADCgMIBQAAAA==.',
Ko='Koltara:BAABNQAECn8cAAIKAAkK6B0cGACcAgAKAAkK6B0cGACcAgABNQAFFAcIHwAFAA4aAA==.Koltarax:BAAANQAECgEIAQABNQAFFAcIHwAFAA4aAA==.Koltarian:BAAANQAFFAEIAQABNQAFFAcIHwAFAA4aAA==.Koltaros:BAAANQAECgQIBAABNQAFFAcIHwAFAA4aAA==.Konshis:BAABNQAECn9AAAMiAAoK/SCDCgDgAgAiAAoK/SCDCgDgAgAjAAYKpwtuMgDTAAAAAA==.Kookymonster:BAABNQAECn9MAAMPAAoKiiLTBwCOAwAPAAoKiiLTBwCOAwAYAAIK+R/JRgCsAAAAAA==.Kos:BAACNQAFFH8eAAQaAAcKWhPfBABtAQAaAAcKUA/fBABtAQAUAAUKqRywCwBSAQATAAEKAADIPQAYAAA1AAQKfzQAAxoACgp4IHEcAKYCABoACgq4H3EcAKYCABQABQppHTRYALABAAAA.',
Kr='Krathos:BAAANQADCgYJCAAAAA==.Krax:BAAANQADCgEIAQAAAA==.Kruk:BAAANQADCggIGAAAAA==.',
Ku='Kuragaru:BAACNQAFFH8eAAIkAAcKZRJqBwBoAQAkAAcKZRJqBwBoAQA1AAQKfzIAAiQACgomIb8EAEIDACQACgomIb8EAEIDAAAA.',
La='Lala:BAAANQAECgYICgAAAA==.Lapis:BAABNQAECn80AAIcAAoKWiGXCgBXAwAcAAoKWiGXCgBXAwAAAA==.',
Le='Lester:BAABNQAECn8jAAIGAAgK7hf3HwA7AgAGAAgK7hf3HwA7AgAAAA==.Levina:BAABNQAECn8sAAMWAAkKWBaoHAC9AQAVAAkKUhX6NQA7AgAWAAgKChWoHAC9AQAAAA==.Lexysady:BAABNQAECn8cAAMCAAoKLRTtiwAOAgACAAoKLRTtiwAOAgADAAQKbQjQuQB2AAAAAA==.',
Li='Liamsun:BAAANQADCggICAAAAA==.Lidrael:BAAANQADCgYIBgABNQAECgoKSwATAC0iAA==.Lidrahl:BAABNQAECn9LAAITAAoKLSIADABSAwATAAoKLSIADABSAwAAAA==.Lilihunt:BAAANQADCgYIBgAAAA==.Liliria:BAABNQAECn89AAIIAAoKDA1FVgCoAQAIAAoKDA1FVgCoAQAAAA==.Lillidân:BAAANQADCgUIBgABNQAECgoKMwAZAPweAA==.Lineman:BAAANQADCgIIAgAAAA==.',
Lj='Ljaeì:BAAANQADCggICAAAAA==.',
Ll='Lloreth:BAABNQAECn8pAAIXAAgKnhCGIQCcAQAXAAgKnhCGIQCcAQAAAA==.',
Ln='Lnpoop:BAABNQAECn9HAAMXAAoKyyCzBgBEAwAXAAoKyyCzBgBEAwAVAAMKOwnWbgBRAAAAAA==.',
Lo='Loafs:BAAANQAECgcIBwAAAA==.Lockjauz:BAAANQADCgQIBgAAAA==.Lonaki:BAAANQADCgIIAgAAAA==.Lorelei:BAAANQAECggIDwAAAA==.Lorrellia:BAAANQADCggICAAAAA==.Lovekiller:BAAANQADCgEIAQAAAA==.',
Lu='Luc:BAABNQAECn88AAMdAAoKRR6HBgDOAgAdAAoKRR6HBgDOAgAlAAEKsQsYIwAuAAAAAA==.Lucariõ:BAACNQAFFH8aAAIIAAcKqhq+BQBCAgAIAAcKqhq+BQBCAgA1AAQKfzQAAwgACgoyIoQYABQDAAgACgoyIoQYABQDAAYAAQqMAyhaACsAAAAA.Lumina:BAAANQAECgcIEwAAAA==.',
Ly='Lyllies:BAABNQAECn9FAAIFAAoKwSH1EwDcAgAFAAoKwSH1EwDcAgAAAA==.Lyv:BAAANQADCgYIBgABNQAECgEIAQAMAAAAAA==.',
Ma='Mafia:BAAANQADCggIEQAAAA==.Magnumrex:BAAANQADCgUIBQAAAA==.Maharette:BAAANQADCgMIAwAAAA==.Makkazul:BAABNQAECn8uAAIaAAkKMxFeOwDiAQAaAAkKMxFeOwDiAQAAAA==.Malgus:BAAANQADCgYIBgAAAA==.Matcauthon:BAAANQAECgUIDAAAAA==.Matrim:BAAANQADCggIEgAAAA==.Mattdæmon:BAABNQAECn8hAAMLAAcKnQVgHgDcAAAJAAYKcgYGXAATAQALAAcKMQNgHgDcAAAAAA==.Mazzak:BAAANQADCgIIAgAAAA==.',
Me='Meekogaia:BAABNQAECn9rAAMcAAoKvRdfSABAAgAcAAoKvRdfSABAAgANAAYKeBEyoABWAQAAAA==.Meekosan:BAAANQADCgcIBgAAAA==.',
Mi='Mijime:BAAANQADCgYIBgABNQAECgQIBAAMAAAAAA==.Millerowntoo:BAACNQAFFH8SAAQUAAcK8yDeAgAWAgAUAAUKJiLeAgAWAgAaAAEKJxxbFgBbAAATAAEKAABpOwAcAAA1AAQKfykAAxQACQqsJvYLAFsDABQACQqsJvYLAFsDABoAAwqEJKllAMYAAAAA.Millions:BAACNQAFFH8JAAIBAAUKuwbHBgAaAQABAAUKuwbHBgAaAQA1AAQKfxgAAgEACQqdFB4PAAACAAEACQqdFB4PAAACAAAA.Mimzy:BAAANQADCgIIAgAAAA==.Mingzi:BAAANQADCgMIAwAAAA==.Minivan:BAAANQADCggICQAAAA==.Mital:BAAANQAECgEIAgAAAA==.',
Mj='Mjoln:BAAANQAECgQIBAAAAA==.',
Mo='Molvnma:BAAANQAECggIBQAAAA==.Monkeycoke:BAABNQAECn8jAAMOAAgKfhU9FAAHAQAPAAcKVhSMdgA/AQAOAAUKMhU9FAAHAQAAAA==.Montkriege:BAAANQAECgIIBgAAAA==.',
Mu='Munchkinz:BAAANQAECgIIAgABNQAECgoKLwAIABAjAA==.Murfie:BAABNQAECn8gAAIGAAoKThUtIgAjAgAGAAoKThUtIgAjAgAAAA==.Murica:BAAANQADCgYICgABNQAECgkJPQAZALUeAA==.',
My='Mythosrex:BAAANQAECgIIAQAAAA==.',
['Mì']='Mìr:BAAANQAFFAIIAgAAAA==.',
Na='Nashira:BAABNQAECn8wAAIcAAoKmBemPgBlAgAcAAoKmBemPgBlAgAAAA==.Nashness:BAABNQAECn8uAAMaAAoKGx1NHACoAgAaAAoKcBdNHACoAgAUAAgKayBMNwBJAgAAAA==.Naturdimund:BAAANQADCgMIAwAAAA==.Natures:BAAANQADCgEIAQAAAA==.',
Ne='Nerdvader:BAAANQADCgEJAQABNQAECgcIIQALAJ0FAA==.Nesquík:BAAANQADCgYIIAAAAA==.Nezar:BAABNQAECn8gAAIXAAgKZxolEQBvAgAXAAgKZxolEQBvAgAAAA==.',
Ni='Nicokira:BAAANQAECgEIAQAAAA==.Niis:BAABNQAECn8YAAMSAAgKSRANDQDnAQASAAgKSRANDQDnAQAQAAcKRwsAIQBFAQAAAA==.Niterage:BAABNQAECn8xAAIJAAgKdAU6QgDtAAAJAAgKdAU6QgDtAAAAAA==.',
Nn='Nn:BAABNQAECn8iAAIWAAgK6RFzJgAZAQAWAAgK6RFzJgAZAQAAAA==.',
No='Noseheirs:BAAANQADCgQIBAAAAA==.Notoriuspab:BAAANQAECgIJAwAAAA==.Noyar:BAAANQADCgMIAwAAAA==.',
Nu='Nuckinphutz:BAAANQADCgEIAQAAAA==.',
['Nè']='Nègan:BAABNQAECn8yAAIFAAoKeBIMYwBQAgAFAAoKeBIMYwBQAgAAAA==.',
['Nì']='Nìr:BAACNQAFFH8SAAIJAAYKJxk6BwDLAQAJAAYKJxk6BwDLAQA1AAQKfxYAAgkACAqEG2UzABACAAkACAqEG2UzABACAAAA.',
Od='Odinrex:BAABNQAECn8lAAIFAAkKCRZ+TgDyAQAFAAkKCRZ+TgDyAQAAAA==.',
Op='Opuntia:BAAANQAECgQIEgAAAA==.',
Or='Orexion:BAAANQADCgUIBQAAAA==.Oruwen:BAAANQADCggIDgABNQADCggIEgAMAAAAAA==.',
Ow='Ownham:BAABNQAECn8dAAMDAAoKdhuTLgCsAgADAAoKdhuTLgCsAgACAAcK9RnerwAwAQABNQAFFAcIEgAUAPMgAA==.',
Ox='Oximus:BAAANQAECgEIAQAAAA==.',
Pa='Paddingidiot:BAACNQAFFH8fAAMFAAcKDhpmCgAaAQAEAAcKHhP9BwDKAQAFAAQKyB9mCgAaAQA1AAQKfx4AAwQACgrGHGIWAKgCAAQACgoLG2IWAKgCAAUAAQrmJXsDAW0AAAAA.Pakez:BAAANQADCgIIAgAAAA==.Paladinheal:BAABNQAECn8vAAIDAAkKDRlpLwAyAgADAAkKDRlpLwAyAgAAAA==.Pallypaladin:BAACNQAFFH8SAAICAAcKOBO+CwCOAQACAAcKOBO+CwCOAQA1AAQKf00AAwIACgrgIosZAF4DAAIACgrgIosZAF4DAAEABQqLEvspAPEAAAAA.Pardsz:BAAANQADCgYICAAAAA==.Partywolf:BAAANQAECgUIEgAAAA==.',
Ph='Phatzero:BAABNQAECn84AAIFAAoKcxy5GgAuAwAFAAoKcxy5GgAuAwAAAA==.',
Pi='Pikas:BAAANQABCgIIAgAAAA==.Pinjo:BAAANQAECgcIDAAAAA==.',
Po='Polard:BAABNQAECn8hAAMWAAoKXiNQBgAsAwAWAAoKXiNQBgAsAwAbAAMKvgGlSgALAAAAAA==.Pownown:BAAANQAECggIEwABNQAFFAcIEgAUAPMgAA==.',
Pr='Procreeper:BAAANQAECgMIAwABNQAECgoKJwAbABckAA==.',
Ps='Pseudonym:BAAANQABCgMIAwAAAA==.',
Pu='Pupper:BAABNQAECn8iAAIRAAkKhBjuNgA6AgARAAkKhBjuNgA6AgAAAA==.',
Ra='Rabit:BAAANQAECgQIBgAAAA==.Radio:BAAANQAECgQIBAAAAA==.Raennt:BAAANQADCgEIAQAAAA==.Rafïki:BAAANQADCgYIBgAAAA==.Rainstorm:BAAANQADCgcIBwAAAA==.Rainyblu:BAAANQAECgUIBQAAAA==.Rawrshåk:BAABNQAECn8tAAMRAAkKhB7cQgDBAgARAAkKnR3cQgDBAgASAAIKAxrHGgCfAAAAAA==.',
Rb='Rb:BAAANQAECgEIAwAAAA==.',
Rc='Rc:BAABNQAECn8pAAIdAAcKfRxkEAC8AQAdAAcKfRxkEAC8AQAAAA==.',
Re='Rennalla:BAAANQADCgcIBwABNQAECgoKQgAJACAgAA==.',
Rh='Rhizomb:BAAANQAECgEIAQAAAA==.Rhodraco:BAABNQAECn8hAAMlAAgK2gWLEwDOAAAlAAcKHwaLEwDOAAAmAAYKTgX/EwBxAAAAAA==.Rhownyn:BAAANQADCgUIDQAAAA==.Rhoxy:BAAANQAECgcICAAAAA==.',
Ri='Rikku:BAAANQADCgEIAQAAAA==.Ripforged:BAABNQAECn8rAAIRAAgKfBgEaACPAQARAAgKfBgEaACPAQABNQAECggKKwARAHwYAA==.',
Rn='Rn:BAAANQAECgMIBQAAAA==.',
Ro='Rolgar:BAAANQADCgYIBwAAAA==.',
Rq='Rq:BAAANQAECgcICgAAAA==.',
Ry='Ryyukken:BAAANQAECgIIAwAAAA==.',
['Rà']='Ràwrshåk:BAAANQAECgEIAQAAAA==.',
['Rå']='Råwrshåk:BAAANQADCgUIBQAAAA==.',
Sa='Saella:BAAANQAECgUICwAAAA==.Sakarja:BAAANQADCgQIBAAAAA==.Saluda:BAAANQAECgUIEgAAAA==.Samesde:BAABNQAECn8UAAIPAAcKnAZqowDZAAAPAAcKnAZqowDZAAAAAA==.Sampson:BAAANQAECgcIBwABNQAECgkJPQAZALUeAA==.Samras:BAAANQAECgcICQAAAA==.Saphyria:BAAANQABCgIIAgAAAA==.Sarentu:BAACNQAFFH8IAAIjAAUKYwyGDADZAAAjAAUKYwyGDADZAAA1AAQKfyoAAiMACgo6Hy4RANcCACMACgo6Hy4RANcCAAAA.Satoru:BAAANQADCgUIBQAAAA==.',
Se='Senile:BAABNQAECn8hAAInAAgKwBN6AgCTAQAnAAgKwBN6AgCTAQAAAA==.Sertia:BAAANQADCgEIAQAAAA==.Sesnic:BAABNQAECn8WAAMSAAYKlAcAIABuAAAQAAUKnwR4MgCjAAASAAMK4AYAIABuAAAAAA==.',
Sh='Shaady:BAAANQABCgIIAgABNQADCgYIBgAMAAAAAA==.Shadesoflife:BAAANQABCgMIAwAAAA==.Shadydice:BAAANQADCgYICwABNQADCgYIBgAMAAAAAA==.Shadydk:BAAANQADCgYIBwABNQADCgYIBgAMAAAAAA==.Shadylady:BAAANQAECgEIAQAAAA==.Shadylid:BAAANQADCgYIBgAAAA==.Shadysmash:BAAANQADCggIEAAAAA==.Shadyvoid:BAAANQAECgUICQABNQADCgYIBgAMAAAAAA==.Shadówglider:BAAANQAECgQIEQAAAA==.Shaelia:BAAANQADCgIIAgAAAA==.Shale:BAABNQAECn8eAAIKAAoKVx6bGQCNAgAKAAoKVx6bGQCNAgAAAA==.Shamallaman:BAAANQAECgUJCAABNQAECgoKJgACALMiAA==.Shanck:BAAANQAECgUICQAAAA==.Sharkweek:BAAANQAECgMIAwAAAA==.Shazám:BAAANQAECgIIAgAAAA==.Sheol:BAAANQADCggIFQAAAA==.Sheyoni:BAAANQADCggJGgAAAA==.Shreck:BAAANQAECggIAQAAAA==.Shydestroyer:BAAANQADCgMIAwAAAA==.',
Si='Si:BAABNQAECn8sAAIIAAkKhR5eIwCWAgAIAAkKhR5eIwCWAgAAAA==.Siersha:BAAANQADCgMIBAAAAA==.Sinfulness:BAAANQAECgUIDgAAAA==.',
Sk='Skikette:BAABNQAECn8zAAIPAAkKnQbZhAAeAQAPAAkKnQbZhAAeAQAAAA==.Skinrot:BAABNQAECn84AAIXAAoK0gyEJQB6AQAXAAoK0gyEJQB6AQAAAA==.',
Sm='Smig:BAABNQAECn8UAAIRAAYKewec8gD6AAARAAYKewec8gD6AAAAAA==.',
Sn='Snowball:BAABNQAECn8XAAIQAAgKqRVxEAB2AQAQAAgKqRVxEAB2AQAAAA==.',
So='Soeki:BAABNQAECn8eAAIYAAcKtxAACQANAQAYAAcKtxAACQANAQAAAA==.Soluthon:BAAANQADCgQIBAAAAA==.Sonyaa:BAAANQADCgcICQAAAA==.Soullove:BAABNQAECn8xAAIYAAoKVRYKBQB3AQAYAAoKVRYKBQB3AQABNQAECgoKNgAXANsXAA==.Soullovez:BAABNQAECn82AAMXAAoK2xdNFQAuAgAXAAoK2xdNFQAuAgAVAAQKJQQRkQCTAAAAAA==.Soulshocks:BAABNQAECn8uAAINAAkKdAyCWgA7AQANAAkKdAyCWgA7AQABNQAECgoKNgAXANsXAA==.Soulviver:BAABNQAECn84AAIIAAkKvhISSwDSAQAIAAkKvhISSwDSAQAAAA==.',
Sp='Spiritwarden:BAABNQAECn81AAIjAAoKXx6aEADfAgAjAAoKXx6aEADfAgAAAA==.Spliffy:BAAANQADCgQIBAAAAA==.Splootz:BAAANQADCggIEAABNQAECgoKFQAjADMMAA==.Spoiledbratt:BAAANQAECgIIBwAAAA==.Spurey:BAAANQAECgEIAQAAAA==.',
Sq='Squirtdadday:BAAANQAECgIIAgAAAA==.',
St='Stargasm:BAAANQAECgEIAQAAAA==.Stimer:BAABNQAECn9LAAQRAAoKjyWjCACuAwARAAoKVSWjCACuAwAQAAgKQiRqCADMAgASAAYKWSHODQDXAQAAAA==.Stori:BAAANQADCggIEQAAAA==.',
Su='Sultanofswat:BAAANQADCgYICwAAAA==.Sunshiny:BAAANQADCggIEgAAAA==.Suxor:BAAANQAECgQIDgAAAA==.',
Sw='Swordboardal:BAACNQAFFH8MAAIQAAUKCw5JAwCyAAAQAAUKCw5JAwCyAAA1AAQKfzMAAhAACgqRFeQKAN0BABAACgqRFeQKAN0BAAAA.',
Sy='Sybius:BAAANQAECgQJCAAAAA==.Symptom:BAAANQAECgEIAQAAAA==.Syncophat:BAABNQAECn8mAAIFAAkKFxyNNgA9AgAFAAkKFxyNNgA9AgAAAA==.',
Ta='Tad:BAAANQAECgQIBgAAAA==.Taint:BAAANQADCgUICQAAAA==.Takia:BAAANQAECgUIEAAAAA==.Talanzen:BAABNQAECn8fAAIZAAoKYCHwQQABAwAZAAoKYCHwQQABAwAAAA==.Talbain:BAAANQAECgEIAQABNQAECggIIwAGAO4XAA==.Talonia:BAAANQAECgQIBQABNQAECgoKJwAFADIbAA==.Tanakiko:BAAANQADCgUIBQAAAA==.Tarrzok:BAAANQADCgcICAABNQADCgYIBgAMAAAAAA==.',
Te='Teacup:BAAANQAECgIIBgABNQAECgoKJQAaAEIaAA==.',
Th='Thrakara:BAACNQAFFH8aAAMiAAcK7wrYBACCAQAiAAYKswfYBACCAQAjAAQKqQkbDQDNAAA1AAQKfzEAAyIACgrHF8YRAGECACIACgrHF8YRAGECACMABApJHiI4AFMBAAAA.Thrakaru:BAABNQAECn8eAAIZAAkKihIymgBMAgAZAAkKihIymgBMAgAAAA==.Thrakumi:BAAANQADCgcIBwAAAA==.Thunderhorns:BAABNQAECn8YAAIEAAcKqgIINwCcAAAEAAcKqgIINwCcAAAAAA==.Thundrall:BAAANQAECgUIEQAAAA==.',
Ti='Tightspaces:BAAANQABCgMIAwAAAA==.Tiltéd:BAABNQAECn8tAAMeAAoKSh+HCgAFAgAeAAkKix2HCgAFAgAkAAYKxSG7NADqAQAAAA==.Tioshadow:BAAANQAECgIIAwABNQAFFAQIBwAjADkSAA==.',
To='Tobaeus:BAAANQADCggIEgAAAA==.Todem:BAAANQADCgEIAQAAAA==.Torches:BAAANQADCgcIBwAAAA==.Totemissues:BAAANQABCgMIAwABNQAECgoKOAAFAHMcAA==.',
Tr='Trayleen:BAAANQADCgUJBQAAAA==.Triad:BAAANQADCgYJBgAAAA==.Truths:BAACNQAFFH8XAAIRAAgK0hovBQB8AgARAAgK0hovBQB8AgA1AAQKfx0AAhEACgqfIYo1AOwCABEACgqfIYo1AOwCAAAA.Trystrom:BAAANQADCgYIDAAAAA==.',
Ts='Tsuo:BAAANQAECgcIDQAAAA==.Tsuoshock:BAAANQAECgUIBQAAAA==.',
Tx='Txavenger:BAAANQAECgIIAgAAAA==.Txblood:BAAANQADCgcICAAAAA==.Txfury:BAAANQAECgEIAQAAAA==.Txgunny:BAABNQAECn8lAAIRAAgKhwfKlQAeAQARAAgKhwfKlQAeAQAAAA==.Txstormin:BAAANQADCgMIAwAAAA==.',
Ty='Tyfuun:BAAANQAECgUIBwABNQAFFAUICQABALsGAA==.Tymptriss:BAABNQAECn8XAAIYAAUKawb1GgBxAAAYAAUKawb1GgBxAAAAAA==.',
['Tí']='Títus:BAAANQAECgIIAgAAAA==.',
Um='Umbrage:BAAANQAECggIDgABNQAFFAcIHgAdAJoYAA==.Umbren:BAABNQAECn8nAAMFAAoKMhsnWwBjAgAFAAoKMhsnWwBjAgAEAAEK3ABKoQAXAAAAAA==.',
Ur='Urabadkity:BAAANQADCgYIEwAAAA==.',
Us='Usefulmelee:BAABNQAECn8aAAMkAAoKCRCmNADqAQAeAAoKFA7zMQAXAgAkAAoK2A6mNADqAQABNQAFFAcIHwAFAA4aAA==.',
Va='Valartha:BAABNQAECn8YAAIVAAYK3g3VSADOAAAVAAYK3g3VSADOAAAAAA==.Variste:BAAANQADCgMIAwAAAA==.',
Ve='Veil:BAAANQADCggJCAAAAA==.Velkån:BAAANQAECgEIAQAAAA==.Vellmora:BAAANQADCgUJBgAAAA==.Velsea:BAAANQAECgQICQAAAA==.Velstadt:BAABNQAECn8uAAMjAAgK6xvSHQBGAgAjAAgK6xvSHQBGAgAhAAQKdxSAHwDuAAAAAA==.Venhance:BAAANQAECgcJEAAAAA==.Venotu:BAABNQAECn8sAAIBAAkKAR1TDADUAgABAAkKAR1TDADUAgAAAA==.Vermilion:BAAANQAECggIEQAAAA==.Vertebrae:BAAANQADCgYICAAAAA==.',
Vh='Vholatile:BAABNQAECn8YAAMOAAgKLw+/CAAAAgAOAAgKLw+/CAAAAgAYAAIKGgQTcwA8AAAAAA==.',
Vi='Violence:BAAANQADCgYIBgAAAA==.Viviel:BAAANQAECggIKAAAAQ==.',
Vo='Voidherron:BAAANQAECgYIEAAAAA==.Voodoomama:BAAANQADCgYIEQAAAA==.',
Wa='Waq:BAAANQADCgUIBQAAAA==.Warlockbot:BAACNQAFFH8PAAIPAAUK1xK4EQBxAQAPAAUK1xK4EQBxAQA1AAQKfyMAAg8ACgqjG1czALwCAA8ACgqjG1czALwCAAAA.Warmongral:BAAANQAECgQIBAAAAA==.Waterboot:BAAANQADCgQIBwAAAA==.Wattheyneed:BAAANQAECgEIAgAAAA==.',
We='Wendi:BAABNQAECn8aAAIYAAcKQwc/JwA9AQAYAAcKQwc/JwA9AQAAAA==.',
Wh='Wholesome:BAAANQADCgcICwAAAA==.',
Wi='Wig:BAAANQADCggIEgABNQAECgoKLQAeAEofAA==.Wildbill:BAAANQADCgYIBwAAAA==.Windcrow:BAAANQADCggICAAAAA==.Withher:BAAANQADCggICAAAAA==.',
Wo='Wombo:BAAANQAECgMIAwAAAA==.Woolala:BAABNQAECn9FAAIFAAoKiRjWNwDDAgAFAAoKiRjWNwDDAgAAAA==.',
Wr='Wrahirn:BAAANQABCgYIBgAAAA==.Wrathran:BAAANQAECgIJAgAAAA==.',
Wu='Wut:BAAANQAECggIEQABNQAECgoKPAAdAEUeAA==.',
Xa='Xahiri:BAAANQADCgYIBgAAAA==.Xalisto:BAAANQADCgYICQAAAA==.',
Xl='Xlia:BAAANQAECgMIBAAAAA==.',
Ya='Yaana:BAAANQADCggIDwAAAA==.Yazmyn:BAABNQAECn8ZAAIhAAoKngtbFgB+AQAhAAoKngtbFgB+AQAAAA==.',
Ye='Yerehmi:BAAANQAECgEIBAAAAA==.',
Yu='Yuny:BAABNQAECn85AAMiAAoK/hRnCwBDAgAiAAoK/hRnCwBDAgAhAAUKuwHMGgBsAAAAAA==.',
Za='Zaier:BAABNQAECn9QAAMDAAoK0CA2CQBuAwADAAoK0CA2CQBuAwACAAkK1Q2dnQBRAQAAAA==.',
Ze='Zeltan:BAABNQAECn9jAAIDAAoKSSBfEQBDAwADAAoKSSBfEQBDAwAAAA==.',
Zh='Zhundrenga:BAAANQAECgQIDwAAAA==.',
Zo='Zoma:BAAANQADCgEIAQAAAA==.',
Zp='Zpad:BAAANQADCgcIDQAAAA==.',
['År']='Åres:BAAANQAECgEIAQAAAA==.Årtemïs:BAAANQAECgEIAQAAAA==.',
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
