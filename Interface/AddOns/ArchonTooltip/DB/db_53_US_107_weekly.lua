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
local provider = {region='US',realm='Gilneas',name='US',type='weekly',zone=53,date='2026-11-10',data={Ac='Acks:BAAANQADCgYICgABNQAFFAYICgABAF8JAA==.',
Ae='Aedra:BAAANQAECgIIAgAAAA==.Aeowyyn:BAABNQAECn8cAAMCAAgKjgoR/QAlAQACAAcKVQYR/QAlAQADAAIKlQfF1ABcAAAAAA==.Aex:BAABNQAECn8aAAMEAAoKtxGRLADzAAAEAAkKCRGRLADzAAAFAAMKygkHKAGkAAABNQAFFAYICgABAF8JAA==.',
Af='Afib:BAAANQAECgEIAQAAAA==.',
Ah='Ahnkhano:BAAANQAECgYIBgAAAA==.',
Ai='Ainge:BAAANQAECgEIAQAAAA==.Airiistra:BAAANQADCgMIAwAAAA==.',
Ak='Akbartheiiv:BAACNQAFFH8ZAAMGAAgKzBhIAgBxAgAGAAcK7xtIAgBxAgAHAAIKSwN+AgBQAAA1AAQKf2oAAwYACgpqJqIAAPMDAAYACgpqJqIAAPMDAAcACArUJBoBAFkDAAAA.Akorius:BAAANQAECgIIAgAAAA==.',
Al='Alarion:BAAANQAECgIIAgAAAA==.Allistrana:BAABNQAECn8sAAIIAAgK5BwrQgBjAgAIAAgK5BwrQgBjAgAAAA==.Allpower:BAAANQADCgYIDgAAAA==.Alpacalyptic:BAAANQAECgcICAAAAA==.Alreaux:BAAANQAECgQIBAAAAA==.Alyx:BAAANQADCgcIBwAAAA==.',
Am='Amadeux:BAAANQADCgIIAgABNQAECgoKJQAFAI0cAA==.Amairis:BAABNQAECn8fAAMHAAYK0hG5CAAXAQAHAAYK0hG5CAAXAQAGAAQKcwh1UwDAAAAAAA==.Ambiorix:BAAANQABCgUIBwAAAA==.',
An='Anrion:BAABNQAECn9KAAQJAAoKySEDEQAXAwAJAAoKjSEDEQAXAwAKAAYKsRgsPABmAQALAAIKZCNfIgCvAAAAAA==.Antiflag:BAAANQAECgYIBgAAAA==.Anzania:BAAANQADCgEIAQABNQADCgYIEwAMAAAAAA==.',
Ar='Arolz:BAAANQADCgYIBgAAAA==.',
At='Ataliya:BAABNQAECn8aAAINAAYK6AsKqwA+AQANAAYK6AsKqwA+AQAAAA==.',
Au='Auranar:BAABNQAECn8dAAIEAAgKbARALwDhAAAEAAgKbARALwDhAAAAAA==.Aurelya:BAABNQAECn8kAAIIAAcKsw7DggCPAQAIAAcKsw7DggCPAQAAAA==.Aurilia:BAABNQAECn8bAAIIAAYKnRwrWwC7AQAIAAYKnRwrWwC7AQAAAA==.',
Av='Avanicus:BAABNQAECn8ZAAMOAAkK/wy1CwCsAQAOAAgKcA21CwCsAQAPAAMKJAdeNAFRAAAAAA==.Aven:BAAANQAECgEIAQAAAA==.Avernas:BAAANQAECgQIBAAAAA==.Avé:BAABNQAECn86AAMCAAkK7hg3dwDMAQACAAkK7hg3dwDMAQABAAQKRA0ZTgCwAAAAAA==.',
Ax='Axellent:BAACNQAFFH8MAAIQAAQK/g6KAgDuAAAQAAQK/g6KAgDuAAA1AAQKfzcABBAACgqRHV0KABACABAACgpVGl0KABACABEACAoLG7lcANUBABIABQq/GkwSAH8BAAE1AAUUBggKAAEAXwkA.Axiomlegacy:BAABNQAECn8nAAMTAAoKUCEKDgBAAwATAAoKUCEKDgBAAwAUAAEKpwgs5gAuAAAAAA==.Axx:BAAANQAECgMIBAABNQAFFAYICgABAF8JAA==.',
Az='Azraith:BAAANQADCgcIBgAAAA==.Azulien:BAAANQAECgcIDQAAAA==.Azulin:BAAANQADCgUJBQAAAA==.',
Ba='Banderblitz:BAABNQAECn8wAAMSAAoKxRUSDgDSAQASAAcKcRkSDgDSAQARAAoKkBNVZgC4AQAAAA==.Banzgrave:BAAANQADCgcIBgAAAA==.Bar:BAACNQAFFH8IAAMIAAYKVQMfFwArAQAIAAUKjgMfFwArAQAGAAIK8wNpFQBzAAA1AAQKfx8AAwYACgrMGa0kAAsCAAYACAqMGK0kAAsCAAgACQrrCqGIAH0BAAAA.',
Be='Bearlyshady:BAABNQAECn9LAAQVAAoK9hoCGAA+AgAVAAoK9hoCGAA+AgAWAAQK9gmiQgCsAAAXAAEKugNHeQAsAAABNQADCgYIBgAMAAAAAA==.Bellarina:BAAANQAECgQICQAAAA==.Bellatrixie:BAAANQAECgQIDwAAAA==.Bennitely:BAAANQADCgEIAQAAAA==.Beriadhwen:BAAANQAECgYICgAAAA==.Bermy:BAABNQAECn8gAAMYAAoKfAr5FgC1AQAYAAoKegn5FgC1AQAPAAUKWwjdzwCgAAAAAA==.Berzerkercow:BAAANQADCgYIBwAAAA==.Bewildert:BAAANQADCgMIBAAAAA==.',
Bh='Bhawkwco:BAAANQADCgUIBQAAAA==.',
Bi='Bigjaina:BAABNQAECn89AAIZAAkKtR4bWgDLAgAZAAkKtR4bWgDLAgAAAA==.Biku:BAAANQAECgUIDwAAAA==.Bitesthesky:BAAANQAECgUIBQAAAA==.',
Bl='Blackhawkdk:BAACNQAFFH8FAAIUAAIK+QF0DQBnAAAUAAIK+QF0DQBnAAA1AAQKfzcAAxQACgpgG24VADQCABQACgpgG24VADQCABMAAQoAAMTFAD0AAAAA.Blackhawkm:BAAANQADCgcIBwAAAA==.Blende:BAAANQAECgQIBQABNQAECgcIEAAMAAAAAA==.Blindwarrior:BAAANQAECgIIAgAAAA==.Bloodshadow:BAABNQAECn8qAAIFAAgKggtIgQCcAQAFAAgKggtIgQCcAQAAAA==.',
Bo='Boraffe:BAAANQADCgMJAgAAAA==.Bovinity:BAAANQABCgcICgAAAA==.',
Br='Breakcooloz:BAAANQAFFAEIAQABNQAFFAUIBQAUAJoTAA==.Bretcoe:BAAANQADCgYIDAABNQAECgIIAgAMAAAAAA==.Bronzamdee:BAAANQADCggJCAAAAA==.Brooce:BAABNQAECn8+AAICAAkKVh6EPgBgAgACAAkKVh6EPgBgAgAAAA==.Broom:BAAANQAECgcICAABNQAECgkJPQAZALUeAA==.Brozken:BAAANQADCgUICAAAAA==.Brutak:BAAANQADCggICAAAAA==.',
Bu='Buzzliteyear:BAAANQADCgUIBQAAAA==.',
['Bä']='Bängbäng:BAAANQADCgYICgAAAA==.',
Ca='Caelix:BAAANQAECgQIBQAAAA==.Canadiana:BAAANQADCgYIBgAAAA==.Carafe:BAAANQAECgYICQABNQAECgoKKAAaAEIaAA==.Carbo:BAAANQAECggIBgABNQAECgoKJwAbABckAA==.Carbonight:BAABNQAECn8nAAIbAAoKFyTHAwBeAwAbAAoKFyTHAwBeAwAAAA==.Carlos:BAAANQAECggICAAAAA==.',
Ce='Celani:BAAANQADCggICAABNQAECggIFgAcACENAA==.Celintha:BAAANQADCgcICAAAAA==.Cellyne:BAAANQAECgQIEAAAAA==.',
Ch='Chaoswind:BAABNQAECn9EAAIcAAoK0xq1LQCrAgAcAAoK0xq1LQCrAgAAAA==.Charlee:BAABNQAECn8lAAIFAAoKNBKrQwA5AgAFAAoKNBKrQwA5AgAAAA==.Chaz:BAAANQAECgIIAgAAAA==.Cheeb:BAAANQADCgcIBwAAAA==.Cheebie:BAAANQABCgYIBgABNQADCgcIBwAMAAAAAA==.Chelives:BAEBNQAECn8oAAIQAAkKHQN/JQC5AAAQAAkKHQN/JQC5AAAAAA==.Cherryb:BAAANQABCgYIDAAAAA==.Chromus:BAACNQAFFH8eAAIdAAcKmhhqBQAuAgAdAAcKmhhqBQAuAgA1AAQKfysAAh0ACgrrHHgNAM8CAB0ACgrrHHgNAM8CAAAA.',
Ci='Cires:BAABNQAECn85AAIeAAoKYRfRDwC8AQAeAAoKYRfRDwC8AQAAAA==.',
Cl='Clareclaymor:BAAANQADCgUIBQAAAA==.',
Co='Colanasou:BAAANQAECgYIDAAAAA==.Coldbattler:BAABNQAECn8WAAIFAAgKSht7TAAiAgAFAAgKSht7TAAiAgAAAA==.Convictions:BAAANQAECgYICwABNQAFFAkJGAARAE8YAA==.Coppermöuth:BAAANQADCgYIBgAAAA==.Corrick:BAAANQAECgQICAAAAA==.Cowpatty:BAAANQADCgQIBAAAAA==.',
Cr='Crow:BAAANQAFFAgIEgAAAQ==.',
Cy='Cydric:BAABNQAECn8nAAICAAoK+x1UOAB1AgACAAoK+x1UOAB1AgAAAA==.',
Da='Daarrkstar:BAAANQAECgcIEAAAAA==.Dakaryn:BAAANQADCggIDQAAAA==.Damageguy:BAAANQAECgYIBgABNQAFFAcIIAARAIMeAA==.Darkynlord:BAAANQADCggICAAAAA==.',
De='Deadskvll:BAAANQADCgYIBgAAAA==.Deathbattler:BAAANQADCggIFAAAAA==.Deathrival:BAAANQADCggICAAAAA==.Dehnis:BAAANQADCgQIBAAAAA==.Delta:BAAANQADCgYICwAAAA==.Demonkare:BAAANQAECgUICgABNQAECgoKQAABAJEkAA==.Demoray:BAACNQAFFH8lAAMEAAgK3hyJBAAqAgAEAAcKuBuJBAAqAgAFAAEKmSI0LgBmAAA1AAQKfzEAAwQACgo0JmoGAGoDAAQACgo0JmoGAGoDAAUAAQppI1sbAWUAAAAA.Demvinity:BAAANQAECgQIDQAAAA==.Dethrone:BAABNQAECn85AAMPAAoKmh+bIACEAgAPAAkKAiCbIACEAgAYAAIKnRq8TACZAAAAAA==.Deus:BAABNQAECn87AAMGAAgKBRMfKwDOAQAGAAcKXhMfKwDOAQAHAAYKAxXwDgA9AQAAAA==.Dezka:BAAANQAECgEIAQAAAA==.',
Di='Dinosocks:BAACNQAFFH8RAAMFAAgKQAuyEABSAQAFAAQKwhKyEABSAQAEAAUKIANvFAD5AAA1AAQKfz4AAwQACgoDG28bAI8BAAUACAoiGXV0ACcCAAQACQqPFm8bAI8BAAAA.Dirtydragon:BAABNQAECn8yAAIdAAoKbx/GBQAGAwAdAAoKbx/GBQAGAwAAAA==.Divinedecay:BAABNQAECn8jAAITAAkKbA7OOQBNAQATAAkKbA7OOQBNAQABNQAECgoKPAAFAPAdAA==.',
Dj='Djaequitas:BAAANQABCgQIBgAAAA==.Djmelisandra:BAAANQABCgQIBAAAAA==.Djshamy:BAAANQABCgUICAAAAA==.',
Do='Dok:BAAANQAECgcIDAAAAA==.Donoraginn:BAAANQADCggIRgAAAA==.Donos:BAAANQADCggIMwABNQADCggIRgAMAAAAAA==.Dontkare:BAAANQADCgMIAwABNQAECgoKQAABAJEkAA==.Dorsai:BAAANQADCgUIBQAAAA==.Dotgenerate:BAAANQAECgQIBQAAAA==.',
Dr='Dracorex:BAAANQABCgIIAgAAAA==.Drark:BAAANQAECgQIBQAAAA==.Drathiel:BAAANQAECgEIAQAAAA==.Drayzr:BAAANQADCgUIBQAAAA==.Drizztknight:BAAANQADCgYIBgAAAA==.Drogon:BAACNQAFFH8FAAIUAAUKmhPDCACMAQAUAAUKmhPDCACMAQA1AAQKfx4AAhQACgrOHlYcAOICABQACgrOHlYcAOICAAAA.Drwho:BAABNQAECn8ZAAMfAAkKvxXXDwCqAQAfAAgK6xXXDwCqAQAZAAQKRxWTYQHxAAAAAA==.Drääx:BAAANQADCgQIBAAAAA==.Dräëxx:BAAANQADCgcIBwAAAA==.Drëëxx:BAAANQAECgEIAQAAAA==.',
Du='Duckymet:BAAANQADCggIEwAAAA==.',
Dw='Dwallin:BAAANQADCgQIBAAAAA==.',
Dy='Dyane:BAAANQADCgQIBAAAAA==.',
['Dô']='Dôz:BAAANQAECgQIBwAAAA==.',
Ed='Edoaldor:BAAANQAECgQIBwAAAA==.',
El='Ellery:BAAANQADCgUJBQAAAA==.',
Em='Empyrean:BAAANQAECgQIBQAAAA==.',
Ex='Exhumina:BAABNQAECn8UAAITAAcKUgkoVQDbAAATAAcKUgkoVQDbAAAAAA==.',
Fa='Facestealerr:BAABNQAECn8dAAIPAAYKhg6FrADnAAAPAAYKhg6FrADnAAAAAA==.',
Fe='Fearall:BAAANQAECggIAwAAAA==.Felgibson:BAAANQADCgYIDQAAAA==.Fenmoon:BAABNQAECn8uAAIVAAoKsA2CKwCPAQAVAAoKsA2CKwCPAQAAAA==.',
Fi='Finneaa:BAAANQADCgUIBQAAAA==.',
Fl='Flairrick:BAABNQAECn8nAAISAAgKdBbODQCLAQASAAgKdBbODQCLAQAAAA==.Flars:BAABNQAECn89AAIaAAoKGCa6AwBYAwAaAAoKGCa6AwBYAwAAAA==.Flatliner:BAABNQAECn8ZAAIDAAgKPge3iQB/AQADAAgKPge3iQB/AQAAAA==.Flik:BAAANQAECgcIEgABNQAFFAYICgABAF8JAA==.',
Fo='Forq:BAAANQADCgcIDgAAAA==.',
Fr='Frakz:BAAANQADCgUIBQAAAA==.Fran:BAAANQADCgYIBgABNQAECgkJPQAZALUeAA==.Frankzappn:BAABNQAECn8tAAQNAAoKJxnCOgCLAgANAAgKJBzCOgCLAgAgAAkK6xEfDgAeAgAcAAMKhwFBFQE/AAAAAA==.Fray:BAAANQADCggICAAAAA==.Freeguy:BAABNQAECn84AAIKAAoKWBf+IABEAgAKAAoKWBf+IABEAgAAAA==.Fruitcakes:BAABNQAECn8aAAQhAAYK0QTMIwC2AAAhAAUK/gPMIwC2AAAiAAUKLwUSOACtAAAjAAQK4gNeWgB8AAAAAA==.',
Fu='Fuddicus:BAAANQAECgIIAgAAAA==.Fuddrael:BAABNQAECn8oAAILAAoKxQk9FgBJAQALAAoKxQk9FgBJAQAAAA==.Fuddrucker:BAAANQAECgIIAgAAAA==.Fuddster:BAAANQADCgQIBAAAAA==.',
Ga='Gaddess:BAABNQAECn8oAAIGAAkKzQa9KwAQAQAGAAkKzQa9KwAQAQAAAA==.Gandàlf:BAAANQADCgYIBgAAAA==.Ganymede:BAAANQAECgUIBgAAAA==.Garan:BAAANQADCgMIAwAAAA==.',
Ge='Geilamaine:BAACNQAFFH8HAAIDAAQKyAdsEgACAQADAAQKyAdsEgACAQA1AAQKfzIABAMACgqcFwBVABsCAAMACgqcFwBVABsCAAIABQrKC1EAAdMAAAEAAQoTA9BrACEAAAAA.',
Gl='Glimagi:BAAANQAECgYIEAAAAA==.',
Gn='Gnxr:BAEANQAECgIIAgABNQAFFAQICwAjAH4jAA==.',
Go='Gonefishing:BAAANQADCgYIBgABNQAECgoKRQAFAIkYAA==.Goretex:BAAANQADCgEIAQABNQADCgcIBwAMAAAAAA==.Gotêtsu:BAABNQAECn8iAAMIAAoKIRI/MgBjAgAIAAoKIRI/MgBjAgAGAAMKzgb0UQBRAAAAAA==.',
Gr='Grimjawz:BAABNQAECn86AAIXAAoKNh9LCABCAwAXAAoKNh9LCABCAwAAAA==.Grippysocks:BAAANQAFFAIIAgABNQAFFAgIEQAFAEALAA==.',
Gu='Gummibear:BAABNQAECn8nAAMQAAgK2Q1VJQC6AAAQAAUKWA9VJQC6AAARAAQKIgoS3QCmAAAAAA==.Gurranq:BAAANQABCggICAABNQAECgkJKQAGAJ8YAA==.',
Gw='Gwiyomi:BAAANQAECgIIAgABNQAECgoKIgAaANkiAA==.',
Gy='Gyr:BAAANQAECgcICAAAAA==.',
Ha='Hakai:BAAANQADCgEIAQABNQAECgoKLgAJAAsUAA==.Hanbor:BAAANQADCgcIBwAAAA==.Haniku:BAABNQAECn8ZAAMSAAgK8Am7HwCVAAARAAgKtgg2xwBqAQASAAQKDAy7HwCVAAAAAA==.Harthoon:BAACNQAFFH8cAAIZAAcKLwjdDwBdAQAZAAcKLwjdDwBdAQA1AAQKfzMAAx8ACgq6HCULABMCABkACgoYElyeAEQCAB8ACAqAHiULABMCAAAA.',
He='Henos:BAAANQAECgUICAAAAA==.',
Ho='Hobomatt:BAAANQADCggICAAAAA==.Holiebelle:BAABNQAECn8hAAIDAAgKPRYgTQDMAQADAAgKPRYgTQDMAQAAAA==.Holyhalf:BAAANQAECgMIBAAAAA==.Holyhutch:BAAANQAECggIDgABNQAECgoKRAAPAPcdAA==.Holyshield:BAAANQADCgEIAQABNQAECgoKMgAIAPAeAA==.Honeynoats:BAABNQAECn8lAAIIAAgKiQnjhACIAQAIAAgKiQnjhACIAQAAAA==.Hotdwarf:BAABNQAECn8tAAQDAAoK2A5diAALAQADAAkKwQxdiAALAQABAAUKigiRSADLAAACAAMKYAn0VQFkAAAAAA==.',
Hr='Hrumm:BAACNQAFFH8cAAMEAAcK9xWNCAC/AQAEAAcKGBSNCAC/AQAFAAEKkw+LKwBYAAA1AAQKfywAAwQACgqPGu4YAJACAAQACgqPGu4YAJACAAUABQpuCj8MAe4AAAAA.',
Hu='Hullkk:BAACNQAFFH8gAAIRAAcKgx7zBgBSAgARAAcKgx7zBgBSAgA1AAQKfy8AAhEACgqfJVcQAH0DABEACgqfJVcQAH0DAAAA.Hun:BAAANQAECggICAAAAA==.Hush:BAAANQAECgUIBQAAAA==.Hutchanova:BAAANQAECgQIBQABNQAECgoKRAAPAPcdAA==.Hutchi:BAAANQAECgYIBAABNQAECgoKRAAPAPcdAA==.Hutchidari:BAAANQAECgEIAQABNQAECgoKRAAPAPcdAA==.Hutchkins:BAABNQAECn9EAAIPAAoK9x3xFQC+AgAPAAoK9x3xFQC+AgAAAA==.Hutchknight:BAABNQAECn8YAAMTAAgKfhV+LgCJAQATAAgKfhV+LgCJAQAUAAMKxAbXuAB7AAABNQAECgoKRAAPAPcdAA==.Hutchstab:BAAANQAECgQIBAABNQAECgoKRAAPAPcdAA==.Hutchyo:BAAANQAECgMIAwABNQAECgoKRAAPAPcdAA==.',
Hy='Hyd:BAAANQADCgQIAQABNQADCgcICQAMAAAAAA==.Hydro:BAAANQADCgcICQAAAA==.',
['Hä']='Häwtz:BAAANQAECgIIAgAAAA==.',
Ic='Icerus:BAABNQAECn8ZAAIIAAoKZBRCLwByAgAIAAoKZBRCLwByAgAAAA==.Icirus:BAABNQAECn9NAAMDAAoK+yAAEAAxAwADAAoK+yAAEAAxAwACAAQKkQqNSQGqAAAAAA==.',
Il='Illaandra:BAAANQADCgUIBQABNQAECgEIAQAMAAAAAA==.',
Im='Imsanity:BAAANQADCgQIBAAAAA==.',
In='Inseng:BAABNQAECn8iAAMaAAoK2SKACQBRAwAaAAoK2SKACQBRAwATAAYKlxfkTAD7AAAAAA==.',
It='Itzal:BAAANQAECgYIBgAAAA==.',
Ja='Jagere:BAABNQAECn83AAIFAAoK7xEDSwAlAgAFAAoK7xEDSwAlAgAAAA==.Jahde:BAABNQAECn8fAAIVAAkKpAUOTADbAAAVAAkKpAUOTADbAAAAAA==.Jaina:BAABNQAECn8YAAIFAAYK7A3wywAAAQAFAAYK7A3wywAAAQAAAA==.Jandrae:BAABNQAECn8/AAQaAAoKeRxzGgC3AgAaAAoKBBtzGgC3AgAUAAUKFx6zYACNAQATAAIKqwfxuwBQAAAAAA==.Jassykins:BAABNQAECn8aAAIFAAgKCAhxoQBUAQAFAAgKCAhxoQBUAQAAAA==.',
Je='Jessecuster:BAAANQADCgQJBAAAAA==.',
Ji='Jiffypop:BAAANQAECgIIAQABNQAECgUIBQAMAAAAAA==.Jillotty:BAAANQADCgUIBAAAAA==.Jirachii:BAAANQAECgEIAQABNQAFFAMICAAVACENAA==.',
Jo='Joanofarc:BAAANQADCgUJBQAAAA==.Joloc:BAABNQAECn8lAAIYAAkKSwyzGACmAQAYAAkKSwyzGACmAQAAAA==.Jonpaul:BAAANQABCgEIAQAAAA==.',
Ju='Jueles:BAAANQADCgMIAwABNQAECgkJHwAVAKQFAA==.',
['Jì']='Jìnx:BAAANQADCgQIBQAAAA==.',
Ka='Kaelaria:BAAANQADCgIIAgAAAA==.Kalrosa:BAABNQAECn8ZAAMSAAcKFROKEgA2AQARAAcKvQ9uhwBgAQASAAYKAhSKEgA2AQABNQAECgoKMAASAMUVAA==.Kare:BAAANQAECgYIEQABNQAECgoKQAABAJEkAA==.Karee:BAABNQAECn9AAAIBAAoKkSQyAgCuAwABAAoKkSQyAgCuAwAAAA==.Karfren:BAAANQAECgEJAQAAAA==.Kauko:BAAANQAECggICAAAAA==.Kazer:BAAANQADCgYJBgAAAA==.',
Ke='Kermodk:BAABNQAECn8tAAITAAoKUSDiFgD2AgATAAoKUSDiFgD2AgAAAA==.',
Kh='Khold:BAABNQAECn8jAAIBAAkKphC7LAB3AQABAAkKphC7LAB3AQAAAA==.',
Ki='Kissofdeath:BAAANQADCgMIBQAAAA==.',
Ko='Koltara:BAABNQAECn8cAAIKAAkK6B0cGACcAgAKAAkK6B0cGACcAgABNQAFFAcIHwAEAA4aAA==.Koltarax:BAAANQAECgEIAQABNQAFFAcIHwAEAA4aAA==.Koltarian:BAAANQAFFAEIAQABNQAFFAcIHwAEAA4aAA==.Koltaros:BAAANQAECgQIBAABNQAFFAcIHwAEAA4aAA==.Konshis:BAACNQAFFH8GAAIiAAMKWBHiBgDUAAAiAAMKWBHiBgDUAAA1AAQKf0QAAyIACgr9IIMKAOACACIACgr9IIMKAOACACMABgqnCxk3ANMAAAAA.Kookymonster:BAABNQAECn9NAAMPAAoKiiLTBwCOAwAPAAoKiiLTBwCOAwAYAAIK+R/JRgCsAAAAAA==.Kos:BAACNQAFFH8eAAQaAAcKWhNFBQC6AQAaAAcKUA9FBQC6AQAUAAUKqRywCwBSAQATAAEKAADIPQAYAAA1AAQKfzQAAxoACgp4IHEcAKYCABoACgq4H3EcAKYCABQABQppHTRYALABAAAA.',
Kr='Krathos:BAAANQADCgYJCAAAAA==.Krax:BAAANQADCgEIAQAAAA==.Kruk:BAAANQADCggIGAAAAA==.',
Ku='Kuragaru:BAACNQAFFH8eAAIkAAcKZRI5CQBnAQAkAAcKZRI5CQBnAQA1AAQKfzMAAiQACgomIb8EAEIDACQACgomIb8EAEIDAAAA.',
La='Lala:BAAANQAECgYIDQAAAA==.Lapis:BAABNQAECn80AAIcAAoKWiGADQBGAwAcAAoKWiGADQBGAwAAAA==.',
Le='Lester:BAABNQAECn8pAAMGAAkKnxj3HwA7AgAGAAgK7hf3HwA7AgAIAAYKEQvxigAgAQAAAA==.Levina:BAABNQAECn8sAAMWAAkKWBaoHAC9AQAVAAkKUhX6NQA7AgAWAAgKChWoHAC9AQAAAA==.Lexysady:BAABNQAECn8jAAMCAAoKihm4UwAhAgACAAoKihm4UwAhAgADAAQKXAm5wgCAAAAAAA==.',
Li='Liamsun:BAAANQADCggICAAAAA==.Lidrael:BAAANQADCgYIBgABNQAECgoKSwATAC0iAA==.Lidrahl:BAABNQAECn9LAAITAAoKLSIADABSAwATAAoKLSIADABSAwAAAA==.Lilihunt:BAAANQADCgYIBgAAAA==.Liliria:BAABNQAECn89AAIIAAoKDA0BaADnAQAIAAoKDA0BaADnAQAAAA==.Lillidân:BAAANQADCgUIBgABNQAECgoKMwAZAPweAA==.Lineman:BAAANQADCgIIAgAAAA==.',
Lj='Ljaeì:BAAANQADCggICAAAAA==.',
Ll='Lloreth:BAABNQAECn8wAAIXAAgKJRPPIQDNAQAXAAgKJRPPIQDNAQAAAA==.',
Ln='Lnpoop:BAABNQAECn9OAAMXAAoK9yCSBwBSAwAXAAoK9yCSBwBSAwAVAAMKOwkNdwBQAAAAAA==.',
Lo='Loafs:BAAANQAECgcIBwAAAA==.Lockjauz:BAAANQADCgQIBgAAAA==.Lonaki:BAAANQADCgIIAgAAAA==.Lorelei:BAAANQAECggIDQAAAA==.Lorrellia:BAAANQADCggICAAAAA==.Lovekiller:BAAANQADCgEIAQAAAA==.',
Lu='Luc:BAABNQAECn9BAAMdAAoKjR+QBQAOAwAdAAoKjR+QBQAOAwAlAAEKsQu0JQAuAAAAAA==.Lucariõ:BAACNQAFFH8bAAIIAAgK5xm+BQBCAgAIAAgK5xm+BQBCAgA1AAQKfzUAAwgACgoyIoQYABQDAAgACgoyIoQYABQDAAYAAQqMA+BiACsAAAAA.Lumina:BAABNQAECn8VAAIBAAgKNx1BGACeAQABAAgKNx1BGACeAQAAAA==.',
Ly='Lyllies:BAABNQAECn9FAAIFAAoKwSGWGQDSAgAFAAoKwSGWGQDSAgAAAA==.Lyv:BAAANQADCgYIBgABNQAECgEIAQAMAAAAAA==.',
Ma='Mafia:BAAANQADCggIEQAAAA==.Magnumrex:BAAANQADCgUIBQAAAA==.Maharette:BAAANQADCgMIAwAAAA==.Makkazul:BAABNQAECn8uAAIaAAkKMxFeOwDiAQAaAAkKMxFeOwDiAQAAAA==.Malgus:BAAANQADCgYIBgAAAA==.Matcauthon:BAAANQAECgUIDAAAAA==.Matrim:BAAANQADCggIEgAAAA==.Mattdæmon:BAABNQAECn8hAAMLAAcKnQVgHgDcAAAJAAYKcgYGXAATAQALAAcKMQNgHgDcAAAAAA==.Mazzak:BAAANQADCgIIAgAAAA==.',
Me='Meekogaia:BAABNQAECn9rAAMcAAoKvRdfSABAAgAcAAoKvRdfSABAAgANAAYKeBEyoABWAQAAAA==.Meekosan:BAAANQADCgcIBgAAAA==.',
Mi='Mijime:BAAANQADCgYIBgABNQAECgQIBAAMAAAAAA==.Millerowntoo:BAACNQAFFH8SAAQUAAcK8yDeAgAWAgAUAAUKJiLeAgAWAgAaAAEKJxxRGQBbAAATAAEKAABpOwAcAAA1AAQKfykAAxQACQqsJvYLAFsDABQACQqsJvYLAFsDABoAAwqEJCtyAMIAAAAA.Millions:BAACNQAFFH8KAAIBAAYKXwnHBgAaAQABAAYKXwnHBgAaAQA1AAQKfyAAAgEACQpaHHYJAJYCAAEACQpaHHYJAJYCAAAA.Mimzy:BAAANQADCgIIAgAAAA==.Mingzi:BAAANQADCgMIAwAAAA==.Minivan:BAAANQADCggICQAAAA==.Mital:BAAANQABCgYICwAAAA==.',
Mj='Mjoln:BAAANQAECgQIBAAAAA==.',
Mo='Molvnma:BAAANQAECggIAwAAAA==.Monkeycoke:BAABNQAECn8lAAMOAAkKnRQ9FAAHAQAPAAgKgRMJcgBvAQAOAAUKMhU9FAAHAQAAAA==.Montkriege:BAAANQAECgIIAgAAAA==.',
Mu='Munchkinz:BAAANQAECgIIAgABNQAECgoKLwAIABAjAA==.Murfie:BAABNQAECn8gAAIGAAoKThUtIgAjAgAGAAoKThUtIgAjAgAAAA==.Murica:BAAANQADCgYICgABNQAECgkJPQAZALUeAA==.',
My='Mythosrex:BAAANQADCgMIAwAAAA==.',
['Mì']='Mìr:BAAANQAFFAIIAgAAAA==.',
Na='Nashira:BAABNQAECn8yAAIcAAoK1RemPgBlAgAcAAoK1RemPgBlAgAAAA==.Nashness:BAABNQAECn8uAAMaAAoKGx1NHACoAgAaAAoKcBdNHACoAgAUAAgKayBMNwBJAgAAAA==.Naturdimund:BAAANQADCgMIAwAAAA==.Natures:BAAANQADCgEIAQAAAA==.',
Ne='Nerdvader:BAAANQADCgEJAQABNQAECgcIIQALAJ0FAA==.Nesquík:BAAANQAECgEIAQAAAA==.Nezar:BAABNQAECn8nAAIXAAgKYRw6EgCKAgAXAAgKYRw6EgCKAgAAAA==.',
Ni='Nicokira:BAAANQAECgEIAQAAAA==.Niis:BAABNQAECn8bAAMSAAkKXxENDQDnAQASAAkKXxENDQDnAQAQAAcKRwsAIQBFAQAAAA==.Niterage:BAABNQAECn85AAIJAAkKLQbZQQAWAQAJAAkKLQbZQQAWAQAAAA==.',
Nn='Nn:BAABNQAECn8pAAIWAAgKxBKCKQAnAQAWAAgKxBKCKQAnAQAAAA==.',
No='Noseheirs:BAAANQADCgQIBAAAAA==.Notoriuspab:BAAANQAECgIJAwAAAA==.Noyar:BAAANQADCgMIAwAAAA==.',
Nu='Nuckinphutz:BAAANQADCgEIAQAAAA==.',
['Nè']='Nègan:BAABNQAECn8yAAIFAAoKeBIMYwBQAgAFAAoKeBIMYwBQAgAAAA==.',
['Nì']='Nìr:BAACNQAFFH8SAAIJAAYKJxk6BwDLAQAJAAYKJxk6BwDLAQA1AAQKfxYAAgkACAqEG2UzABACAAkACAqEG2UzABACAAAA.',
Od='Odinrex:BAABNQAECn8oAAIFAAkKCRa8WwD6AQAFAAkKCRa8WwD6AQAAAA==.',
Op='Opuntia:BAABNQAECn8ZAAIhAAUKtBJBGACeAAAhAAUKtBJBGACeAAAAAA==.',
Or='Orexion:BAAANQADCgUIBQAAAA==.Oruwen:BAAANQADCggIDgABNQADCggIEgAMAAAAAA==.',
Ow='Ownham:BAABNQAECn8iAAMDAAoKIB+TLgCsAgADAAoKIB+TLgCsAgACAAcK9RkbxgAyAQABNQAFFAcIEgAUAPMgAA==.Ownown:BAAANQAECgUIBQABNQAFFAcIEgAUAPMgAA==.',
Pa='Paddingidiot:BAACNQAFFH8fAAMEAAcKDhr9BwDKAQAEAAcKHhP9BwDKAQAFAAQKyB+0DAAVAQA1AAQKfx8AAwQACgrGHGIWAKgCAAQACgq0G2IWAKgCAAUAAQrmJa0XAWsAAAAA.Pakez:BAAANQADCgIIAgAAAA==.Paladinheal:BAABNQAECn8wAAIDAAkKtxkLNQA2AgADAAkKtxkLNQA2AgAAAA==.Pallypaladin:BAACNQAFFH8SAAICAAcKOBO+CwCOAQACAAcKOBO+CwCOAQA1AAQKf00AAwIACgrgIosZAF4DAAIACgrgIosZAF4DAAEABQqLEnAvAOwAAAAA.Pardsz:BAAANQADCgYICAAAAA==.Partywolf:BAAANQAECgUIEQAAAA==.',
Ph='Phatzero:BAABNQAECn88AAIFAAoK8B25GgAuAwAFAAoK8B25GgAuAwAAAA==.',
Pi='Pikas:BAAANQABCgIIAgAAAA==.Pinjo:BAAANQAECgcIDAAAAA==.',
Po='Polard:BAABNQAECn8kAAMWAAoKbSNQBgAsAwAWAAoKbSNQBgAsAwAbAAMKvgFxVAALAAAAAA==.Pownown:BAABNQAECn8YAAIIAAoKSiTvAgAEBAAIAAoKSiTvAgAEBAABNQAFFAcIEgAUAPMgAA==.',
Pr='Procreeper:BAAANQAECgIIAQABNQAECgoKJwAbABckAA==.',
Ps='Pseudonym:BAAANQABCgMIAwAAAA==.',
Pu='Pupper:BAABNQAECn8iAAIRAAkKhBhPQAAzAgARAAkKhBhPQAAzAgAAAA==.',
Ra='Rabit:BAAANQAECgQIBgAAAA==.Radio:BAAANQAECgQIBAAAAA==.Raennt:BAAANQADCgEIAQAAAA==.Rafïki:BAAANQADCgYIBgAAAA==.Rainstorm:BAAANQADCgcIBwAAAA==.Rainyblu:BAAANQAECgQIBAAAAA==.Rawrshåk:BAABNQAECn8wAAMRAAoKXR3cQgDBAgARAAoKkxzcQgDBAgASAAIKAxodHwCbAAAAAA==.',
Rb='Rb:BAAANQAECgEIAwAAAA==.',
Rc='Rc:BAABNQAECn8qAAIdAAgKqBuDDwD8AQAdAAgKqBuDDwD8AQAAAA==.',
Re='Rennalla:BAAANQADCgcIBwABNQAECgoKSgAJAMkhAA==.',
Rh='Rhodraco:BAABNQAECn8oAAMlAAgKqgYNFQDSAAAlAAcKhwYNFQDSAAAmAAcK9AW8EADBAAAAAA==.Rhownyn:BAAANQADCgUIDQAAAA==.Rhoxy:BAAANQAECgcICAAAAA==.',
Ri='Rikku:BAAANQADCgEIAQAAAA==.Ripforged:BAABNQAECn8rAAIRAAgKfBjGhQANAgARAAgKfBjGhQANAgABNQAECggKKwARAHwYAA==.',
Rn='Rn:BAAANQAECgMIBQAAAA==.',
Ro='Rolgar:BAAANQADCgYIBwAAAA==.',
Rq='Rq:BAAANQAECgcICgAAAA==.',
Ry='Ryyukken:BAAANQAECgMIAwAAAA==.',
['Rà']='Ràwrshåk:BAAANQAECgEIAQAAAA==.',
['Rå']='Råwrshåk:BAAANQADCgUICgAAAA==.',
Sa='Saella:BAAANQAECgUIDAAAAA==.Sakarja:BAAANQADCgQIBAAAAA==.Saluda:BAABNQAECn8VAAIFAAYKpAI7AgGTAAAFAAYKpAI7AgGTAAAAAA==.Samesde:BAABNQAECn8cAAIPAAkKBwrfbAB9AQAPAAkKBwrfbAB9AQAAAA==.Sampson:BAAANQAECgcIBwABNQAECgkJPQAZALUeAA==.Samras:BAAANQAECggIDwAAAA==.Saphyria:BAAANQABCgIIAgAAAA==.Sarentu:BAACNQAFFH8IAAIjAAUKYwyGDADZAAAjAAUKYwyGDADZAAA1AAQKfysAAiMACgo6Hy4RANcCACMACgo6Hy4RANcCAAAA.Satoru:BAAANQADCgUIBQAAAA==.',
Se='Senile:BAABNQAECn8oAAInAAgKHhWxAgCpAQAnAAgKHhWxAgCpAQAAAA==.Sertia:BAAANQADCgEIAQAAAA==.Sesnic:BAABNQAECn8WAAMSAAYKlAe3JABsAAAQAAUKnwR4MgCjAAASAAMK4Aa3JABsAAAAAA==.',
Sh='Shaady:BAAANQABCgIIAgABNQADCgYIBgAMAAAAAA==.Shadesoflife:BAAANQABCgMIAwAAAA==.Shadydice:BAAANQADCgYICwABNQADCgYIBgAMAAAAAA==.Shadydk:BAAANQADCgYIBwABNQADCgYIBgAMAAAAAA==.Shadylid:BAAANQADCgYIBgAAAA==.Shadysmash:BAAANQADCggIEAAAAA==.Shadyvoid:BAAANQAECgUICgABNQADCgYIBgAMAAAAAA==.Shadówglider:BAABNQAECn8YAAIKAAYK6QfaPACpAAAKAAYK6QfaPACpAAAAAA==.Shaelia:BAAANQADCgIIAgAAAA==.Shale:BAABNQAECn8eAAIKAAoKVx6bGQCNAgAKAAoKVx6bGQCNAgAAAA==.Shamallaman:BAAANQAECgUJCAABNQAECgoKJgACALMiAA==.Shanck:BAAANQAECgYIDgAAAA==.Sharkweek:BAAANQAECgMIAwAAAA==.Shazám:BAAANQAECgIIAgAAAA==.Sheol:BAAANQADCggIFQAAAA==.Sheyoni:BAAANQADCggJGgAAAA==.Shydestroyer:BAAANQADCgMIAwAAAA==.',
Si='Si:BAABNQAECn8tAAIIAAkKhR5KKwCIAgAIAAkKhR5KKwCIAgAAAA==.Siersha:BAAANQADCgMIBAAAAA==.Sinfulness:BAAANQAECgQIDAAAAA==.',
Sk='Skikette:BAABNQAECn8zAAIPAAkKnQYOkQAkAQAPAAkKnQYOkQAkAQAAAA==.Skinrot:BAACNQAFFH8FAAIXAAIKSwRUEgBjAAAXAAIKSwRUEgBjAAA1AAQKfzsAAhcACgojDQ0qAIIBABcACgojDQ0qAIIBAAAA.',
Sm='Smig:BAABNQAECn8UAAIRAAYKewec8gD6AAARAAYKewec8gD6AAAAAA==.',
Sn='Snowball:BAABNQAECn8ZAAIQAAkKmhTPDwChAQAQAAkKmhTPDwChAQAAAA==.',
So='Soeki:BAABNQAECn8lAAIYAAgK4w/wBwA9AQAYAAgK4w/wBwA9AQAAAA==.Soluthon:BAAANQADCgQIBAAAAA==.Sonyaa:BAAANQADCgcICQAAAA==.Soullove:BAABNQAECn8zAAIYAAoKxRcWBQCYAQAYAAoKxRcWBQCYAQABNQAECgoKPwAXACIZAA==.Soullovez:BAABNQAECn8/AAMXAAoKIhl4EwB6AgAXAAoKIhl4EwB6AgAVAAQKJQQRkQCTAAAAAA==.Soulshocks:BAABNQAECn8vAAINAAkKdAyGZgA7AQANAAkKdAyGZgA7AQABNQAECgoKPwAXACIZAA==.Soulviver:BAABNQAECn88AAIIAAoKGBJOOwA5AgAIAAoKGBJOOwA5AgAAAA==.',
Sp='Spiritwarden:BAABNQAECn87AAIjAAoKXx6aEADfAgAjAAoKXx6aEADfAgAAAA==.Spliffy:BAAANQADCgQIBAAAAA==.Splootz:BAAANQADCggIEAABNQAFFAMIBAAMAAAAAA==.Spurey:BAAANQAECgUIBQAAAA==.',
Sq='Squirtdadday:BAAANQAECgIIAgAAAA==.',
St='Stargasm:BAAANQAECgEIAQAAAA==.Stimer:BAABNQAECn9QAAQRAAoKviWjCACuAwARAAoKViWjCACuAwAQAAgKQiRqCADMAgASAAYKSCPODQDXAQAAAA==.Stori:BAAANQADCggIEQAAAA==.',
Su='Sultanofswat:BAAANQADCgYICwAAAA==.Sunshiny:BAAANQADCggIEgAAAA==.Suxor:BAAANQAECgQIDgAAAA==.',
Sw='Swordboardal:BAACNQAFFH8QAAIQAAUKCw7jAwCuAAAQAAUKCw7jAwCuAAA1AAQKfzMAAhAACgqRFRwNANMBABAACgqRFRwNANMBAAAA.',
Sy='Sybius:BAAANQAECgQJCAAAAA==.Symptom:BAAANQAECgEIAQAAAA==.Syncophat:BAABNQAECn8vAAIFAAkKaR8oKgCJAgAFAAkKaR8oKgCJAgAAAA==.',
Ta='Tad:BAAANQAECgQIBgAAAA==.Taint:BAAANQADCgUICQAAAA==.Takia:BAABNQAECn8ZAAIFAAYK5QI5AwGSAAAFAAYK5QI5AwGSAAAAAA==.Talanzen:BAABNQAECn8fAAIZAAoKYCHwQQABAwAZAAoKYCHwQQABAwAAAA==.Talonia:BAAANQAECgQIBAABNQAECgoKLQAFADIbAA==.Tanakiko:BAAANQADCgUIBQAAAA==.Tanookii:BAAANQADCgMIAwAAAA==.Tarrzok:BAAANQADCgcICAABNQADCgYIBgAMAAAAAA==.',
Te='Teacup:BAAANQAECgIIBgABNQAECgoKKAAaAEIaAA==.',
Th='Thrakara:BAACNQAFFH8aAAMiAAcK7wrYBACCAQAiAAYKswfYBACCAQAjAAQKqQkbDQDNAAA1AAQKfzIAAyIACgodGMYRAGECACIACgodGMYRAGECACMABApJHiI4AFMBAAAA.Thrakaru:BAABNQAECn8eAAIZAAkKihIymgBMAgAZAAkKihIymgBMAgAAAA==.Thrakumi:BAAANQADCgcIBwAAAA==.Thunderhorns:BAABNQAECn8fAAIEAAgK6QJtNADEAAAEAAgK6QJtNADEAAAAAA==.Thundrall:BAABNQAECn8XAAIFAAcK7QHoAQGUAAAFAAcK7QHoAQGUAAAAAA==.',
Ti='Tightspaces:BAAANQABCgMIAwAAAA==.Tiltéd:BAABNQAECn8tAAMeAAoKSh87DAD8AQAeAAkKix07DAD8AQAkAAYKxSEzPgDtAQAAAA==.Tioshadow:BAAANQAECgIIAwABNQAFFAQIBwAjADkSAA==.',
To='Tobaeus:BAAANQADCggIEgAAAA==.Todem:BAAANQADCgEIAQAAAA==.Torches:BAAANQADCgcIBwAAAA==.Totemissues:BAAANQABCgMIAwABNQAECgoKPAAFAPAdAA==.',
Tr='Trayleen:BAAANQADCgUJBQAAAA==.Triad:BAAANQADCgYJBgAAAA==.Truths:BAACNQAFFH8YAAIRAAkKTxgvBQB8AgARAAkKTxgvBQB8AgA1AAQKfx0AAhEACgqfIYo1AOwCABEACgqfIYo1AOwCAAAA.Trystrom:BAAANQADCgYIDAAAAA==.',
Ts='Tsuo:BAAANQAECgcIDQAAAA==.Tsuoshock:BAAANQAECgUIBQAAAA==.',
Tx='Txavenger:BAAANQAECgIIAgAAAA==.Txblood:BAAANQADCgcICAAAAA==.Txfury:BAAANQAECgEIAQAAAA==.Txgunny:BAABNQAECn8nAAIRAAkK/gfikABKAQARAAkK/gfikABKAQAAAA==.Txstormin:BAAANQADCgMIAwAAAA==.',
Ty='Tymptriss:BAABNQAECn8dAAIYAAYKgwgrFgChAAAYAAYKgwgrFgChAAAAAA==.',
['Tí']='Títus:BAAANQAECgIIAgAAAA==.',
Um='Umbrage:BAAANQAECggIDgABNQAFFAcIHgAdAJoYAA==.Umbren:BAABNQAECn8tAAMFAAoKMhsnWwBjAgAFAAoKMhsnWwBjAgAEAAEK3ABKoQAXAAAAAA==.',
Ur='Urabadkity:BAAANQADCgYIEwAAAA==.',
Us='Usefulmelee:BAABNQAECn8aAAMkAAoKCRBTPAD0AQAeAAoKFA7zMQAXAgAkAAoK2A5TPAD0AQABNQAFFAcIHwAEAA4aAA==.',
Va='Valartha:BAABNQAECn8fAAIVAAcKEQ+AQQANAQAVAAcKEQ+AQQANAQAAAA==.Variste:BAAANQADCgMIAwAAAA==.',
Ve='Veil:BAAANQADCggJCAAAAA==.Velkån:BAAANQAECgEIAQAAAA==.Vellmora:BAAANQADCgUJBgAAAA==.Velsea:BAAANQAECgQICQAAAA==.Velstadt:BAABNQAECn81AAMjAAkKpxvSHQBGAgAjAAkKpxvSHQBGAgAhAAQKdxSAHwDuAAAAAA==.Venhance:BAAANQAECgcJEAAAAA==.Venotu:BAABNQAECn8wAAMBAAkKAR1TDADUAgABAAkKAR1TDADUAgACAAQKgA20HQGpAAAAAA==.Vermilion:BAAANQAECggIDgAAAA==.Vertebrae:BAAANQADCgYICAAAAA==.',
Vh='Vholatile:BAABNQAECn8bAAMOAAkKEg+/CAAAAgAOAAkKEg+/CAAAAgAYAAIKGgQTcwA8AAAAAA==.',
Vi='Violence:BAAANQADCgYIBgAAAA==.Viviel:BAAANQAECgcILAAAAQ==.',
Vo='Voidherron:BAAANQAECgYIDwAAAA==.Voodoomama:BAAANQADCgYIEQAAAA==.',
Wa='Waq:BAAANQADCgUIBQAAAA==.Warlockbot:BAACNQAFFH8PAAIPAAUK1xK4EQBxAQAPAAUK1xK4EQBxAQA1AAQKfyMAAg8ACgqjG1czALwCAA8ACgqjG1czALwCAAAA.Warmongral:BAAANQAECgQIBAAAAA==.Waterboot:BAAANQAECgEIAQAAAA==.Wattheyneed:BAAANQAECgEIAgAAAA==.',
We='Wendi:BAABNQAECn8aAAIYAAcKQwc/JwA9AQAYAAcKQwc/JwA9AQAAAA==.',
Wh='Wholesome:BAAANQADCgcICwAAAA==.',
Wi='Wig:BAAANQADCggIEgABNQAECgoKLQAeAEofAA==.Wildbill:BAAANQADCgYIBwAAAA==.Windcrow:BAAANQADCggICAAAAA==.Withher:BAAANQADCggICAAAAA==.',
Wo='Wombo:BAAANQAECgYICQAAAA==.Woolala:BAABNQAECn9FAAIFAAoKiRjWNwDDAgAFAAoKiRjWNwDDAgAAAA==.',
Wr='Wrahirn:BAAANQABCgYIBgAAAA==.Wrathran:BAAANQAECgIJAgAAAA==.',
Wu='Wut:BAAANQAECggIDgABNQAECgoKQQAdAI0fAA==.',
Xa='Xahiri:BAAANQADCgYIBgAAAA==.Xalisto:BAAANQADCgYICQAAAA==.',
Xl='Xlia:BAAANQAECgMIAwAAAA==.',
Ya='Yaana:BAAANQADCggIDwAAAA==.Yazmyn:BAABNQAECn8bAAIhAAoKYgxbFgB+AQAhAAoKYgxbFgB+AQAAAA==.',
Ye='Yerehmi:BAAANQAECgEIBAAAAA==.',
Yu='Yuny:BAABNQAECn9EAAQiAAoK+hc6CQCxAgAiAAoK+hc6CQCxAgAhAAUKuwGIHQBqAAAjAAIKqwbmXwAhAAAAAA==.',
Za='Zaier:BAABNQAECn9RAAMDAAoK0CDhCwBgAwADAAoK0CDhCwBgAwACAAkK1Q1jrgBcAQAAAA==.',
Ze='Zeltan:BAABNQAECn9kAAIDAAoKXSBfEQBDAwADAAoKXSBfEQBDAwAAAA==.',
Zh='Zhundrenga:BAABNQAECn8YAAITAAYKeQMMcACFAAATAAYKeQMMcACFAAAAAA==.',
Zo='Zoma:BAAANQADCgEIAQAAAA==.',
Zp='Zpad:BAAANQADCgcIDQAAAA==.',
['År']='Åres:BAAANQADCgEIAQAAAA==.',
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
