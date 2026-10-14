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

local lookup = {'Mage-Arcane','Warlock-Demonology','Paladin-Holy','Paladin-Retribution','DemonHunter-Devourer','DeathKnight-Blood','Warrior-Arms','Hunter-BeastMastery','Priest-Holy','Priest-Shadow','DemonHunter-Vengeance','DemonHunter-Havoc','Unknown-Unknown','Hunter-Marksmanship','Warrior-Fury','Mage-Frost','Shaman-Enhancement','DeathKnight-Frost','Hunter-Survival','Warrior-Protection','Paladin-Protection','Druid-Guardian','Druid-Feral','Rogue-Subtlety','Rogue-Assassination','Shaman-Elemental','Priest-Discipline','Shaman-Restoration','Evoker-Preservation','Druid-Restoration','Warlock-Destruction','Druid-Balance','Evoker-Devastation','Evoker-Augmentation','Monk-Mistweaver','Monk-Windwalker','DeathKnight-Unholy','Warlock-Affliction',}
local provider = {region='US',realm='Skullcrusher',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Absolute:BAAANQAECggIEQAAAA==.Abzclap:BAAANQAECgYIBgABNQAECgkJKQABAHsjAA==.Abzdh:BAAANQAECgMIBQABNQAECgkJKQABAHsjAA==.Abzlock:BAAANQAECgQICAABNQAECgkJKQABAHsjAA==.Abzmage:BAABNQAECn8pAAIBAAkKeyMeEACSAwABAAkKeyMeEACSAwAAAA==.Abzp:BAAANQAECgYIDAABNQAECgkJKQABAHsjAA==.Abzrogue:BAAANQAECgYICgABNQAECgkJKQABAHsjAA==.Abzsh:BAAANQAECgQICQAAAA==.',
Ac='Acoreüs:BAEBNQAECn8iAAICAAcKXQ2hnACZAQACAAcKXQ2hnACZAQAAAA==.',
Ad='Adramelk:BAAANQAECgIIBQABNQAECggIGQADALwaAA==.',
Ae='Aed:BAAANQABCgEIAQAAAA==.Aeiay:BAAANQAECgUIEwAAAA==.',
Ai='Aibh:BAAANQADCgUIBwAAAA==.',
Al='Alastorias:BAAANQAECgIIAgAAAA==.Alethice:BAAANQADCgcIBwAAAA==.Alexandrap:BAAANQAECgQIBgAAAA==.Allmighto:BAECNQAFFH8bAAMDAAcKLR17AgCBAgADAAcKLR17AgCBAgAEAAEKAAARLwBNAAA1AAQKfy0AAgMACQp9I74FAJ4DAAMACQp9I74FAJ4DAAAA.Alyssaxoo:BAACNQAFFH8GAAIDAAMK6A3sFwDgAAADAAMK6A3sFwDgAAA1AAQKfyEAAwMACQq0E8lKADsCAAMACQq0E8lKADsCAAQAAQoAAHStAS4AAAAA.',
Am='Amorsith:BAAANQADCggICAAAAA==.',
An='Androstraz:BAAANQADCggICAAAAA==.Anjkh:BAAANQAECgEIAQAAAA==.Anniesthesia:BAAANQAECgUIDgAAAA==.Anoobyss:BAABNQAECn8VAAIFAAUKiQ5zSgD9AAAFAAUKiQ5zSgD9AAAAAA==.Anorexorcist:BAAANQABCgEIAQABNQAFFAIICgAGAOcNAA==.Anorxorcist:BAAANQAECgIIAgABNQAFFAIICgAGAOcNAA==.Anorxxorcist:BAACNQAFFH8KAAIGAAIK5w0uJABqAAAGAAIK5w0uJABqAAA1AAQKfx4AAgYACQrgE9FHANYBAAYACQrgE9FHANYBAAAA.Ansky:BAAANQADCggICAAAAA==.Anthraxx:BAAANQADCggJDwABNQAECgcIFwABAAsOAA==.Anyone:BAAANQAECgUIDQABNQAECgcIFwAHAMYQAA==.',
Ap='Aporkchop:BAAANQAECgEIBAAAAA==.Applebottom:BAABNQAECn8sAAIIAAkKByFpIQAQAwAIAAkKByFpIQAQAwAAAA==.',
Ar='Archenemyy:BAABNQAECn8ZAAMJAAgKmxXsUQAqAgAJAAgKmxXsUQAqAgAKAAIKUwLpcABCAAAAAA==.Arda:BAABNQAECn8rAAIIAAgKjSFgJwD5AgAIAAgKjSFgJwD5AgAAAA==.Arelina:BAAANQAECgIIBgAAAA==.Arune:BAAANQAECgYICgAAAA==.',
As='Aspyrx:BAABNQAECn8nAAIGAAgK4xMQSwDIAQAGAAgK4xMQSwDIAQAAAA==.Assol:BAAANQADCgUIDgAAAA==.Astelan:BAEBNQAECn8oAAIKAAkKUyBKCQBHAwAKAAkKUyBKCQBHAwAAAA==.Astärea:BAABNQAECn8ZAAMLAAcK7QsAFQBYAQALAAcK7QsAFQBYAQAMAAYKggYlWwASAQAAAA==.',
Au='Aurorä:BAAANQAECgYIDgAAAA==.',
Ay='Ayeola:BAAANQADCgEIAQAAAA==.',
Az='Aztëk:BAAANQAECgIIAgAAAA==.',
Ba='Bachaterah:BAAANQADCgEIAQAAAA==.Baddawg:BAAANQAECgQIBgABNQAECgkJLAABAOcXAA==.Baeldaeg:BAABNQAECn8XAAMFAAkKzhYeFwCjAgAFAAkKzhYeFwCjAgALAAIK1wzrKgBYAAAAAA==.Bahahahamut:BAABNQAECn8eAAIJAAkKdxyMGwADAwAJAAkKdxyMGwADAwABNQAECgkJFwAFAM4WAA==.Bannett:BAAANQAECgUICAAAAA==.Baoboi:BAAANQADCgQIBAAAAA==.Bashing:BAAANQAECgYICAABNQAECgkJLgAGALYfAA==.Bauce:BAAANQADCgQIBAAAAA==.Baxterevo:BAAANQAECgYIDwAAAA==.Baybx:BAAANQABCgUIBgAAAA==.',
Be='Beardgrim:BAAANQADCggICAAAAA==.Beefyweefy:BAAANQADCggIDQABNQAECgcIDgANAAAAAA==.Bella:BAABNQAECn8UAAIOAAcKtQrQPQBeAQAOAAcKtQrQPQBeAQAAAA==.',
Bi='Bianchi:BAAANQAECggIEAAAAA==.Bibleman:BAAANQADCggICAAAAA==.Biddy:BAAANQADCgYIBgAAAA==.Bienfrosty:BAAANQAECgUIBQAAAA==.Bigbowlp:BAEANQAECgQIBAABNQAFFAcIGAAPADMmAA==.Bigchungus:BAAANQADCgYIBgAAAA==.Bigguns:BAAANQAECgEJAQAAAA==.Bigmonk:BAAANQADCgIIAgAAAA==.Bigpumpa:BAAANQAECgQICwAAAA==.Billygoatgrf:BAABNQAECn8cAAIQAAgKzBpbBwB6AgAQAAgKzBpbBwB6AgAAAA==.',
Bl='Blackvomit:BAAANQAECgIIAgAAAA==.Blakkbeard:BAACNQAFFH8FAAIRAAIK2AyVBQCuAAARAAIK2AyVBQCuAAA1AAQKfycAAhEACQpEIHcIAO8CABEACQpEIHcIAO8CAAAA.Blazefort:BAABNQAFFH8FAAISAAQK6gtNDQAAAQASAAQK6gtNDQAAAQAAAA==.Blightmommie:BAAANQAECgUIBgAAAA==.Blitzeye:BAABNQAECn8lAAITAAgKDBVLBQBsAgATAAgKDBVLBQBsAgAAAA==.Bludskal:BAAANQADCgYIBgABNQAECgkJLgAGALYfAA==.Bløod:BAAANQAECgEIAQAAAA==.',
Bo='Bolger:BAAANQADCgMIAwAAAA==.Bonix:BAAANQADCgIIBAAAAA==.Boosteddots:BAAANQAECgEIAwAAAA==.Boozeftw:BAAANQADCgUIBQAAAA==.Bowjobdamage:BAAANQADCgMIAwAAAA==.',
Br='Braincell:BAABNQAECn8VAAQPAAYKiBPgFABNAQAPAAYKLBHgFABNAQAUAAUKJxAWKgDkAAAHAAQKYxRvAQHUAAABNQAECgkJFwAFAM4WAA==.Breemonic:BAABNQAECn8YAAIMAAkKbAjEQQCtAQAMAAkKbAjEQQCtAQAAAA==.Brewdie:BAAANQADCgUIBgAAAA==.Britannican:BAAANQAECgEIAQAAAA==.Brrooks:BAAANQADCggICAAAAA==.Bruce:BAACNQAFFH8KAAQPAAUK9hl/AADlAQAPAAUK9hl/AADlAQAUAAIK8ghWBwBqAAAHAAEK/Rk1OwBJAAA1AAQKfyIABBQACQrqH+gLAHcCABQACQoWGOgLAHcCAAcACQpUGjxmAFkCAA8ABAr5HY4SAHYBAAAA.',
Bu='Bubblekush:BAAANQAECgIIAgAAAA==.Bubbleøseven:BAAANQADCgQIBAAAAA==.Bullshifter:BAAANQAECgQIBgAAAA==.Bullshoc:BAAANQADCgIIAgAAAA==.Burgleslight:BAAANQAECgEIAQAAAA==.Butturz:BAABNQAECn8UAAIKAAYKJiFLHQBUAgAKAAYKJiFLHQBUAgAAAA==.',
['Bø']='Bønecrusher:BAAANQABCgEIAQAAAA==.',
Ca='Cabala:BAAANQAECgIIAwAAAA==.Cailleach:BAAANQAECgIJAgAAAA==.Cainz:BAAANQAECgYIDwAAAA==.Caraxes:BAAANQAECgQIBQABNQAECgkJNQATAB8gAA==.',
Ce='Celeryman:BAABNQAECn8YAAQEAAgKdRqUfAAtAgAEAAgKdRqUfAAtAgADAAMKWQXg+ACGAAAVAAIKPQsEZABMAAAAAA==.Celian:BAAANQAECgEIAQAAAA==.Centuro:BAAANQAECgEIBAAAAA==.',
Ch='Chillywillie:BAAANQAECgUIBQABNQAECggIIgABANQXAA==.Chobi:BAABNQAECn8aAAMWAAkKnCT8AQC1AwAWAAkKnCT8AQC1AwAXAAEKAABfOABVAAAAAA==.',
Ci='Cinnamen:BAABNQAECn8iAAIYAAkKsx/tBgAOAwAYAAkKsx/tBgAOAwAAAA==.',
Cl='Claudine:BAAANQAECgUIEAABNQAECggIFQABAEADAA==.Clearstoned:BAAANQADCgUIBQABNQAECgkJKwABANUhAA==.',
Co='Coaa:BAABNQAECn8cAAIIAAcK3hT6hgD5AQAIAAcK3hT6hgD5AQAAAA==.Colossus:BAABNQAECn8UAAIEAAcK1gT2EAH8AAAEAAcK1gT2EAH8AAAAAA==.Contrap:BAABNQAECn8kAAIIAAgKZB3aWABmAgAIAAgKZB3aWABmAgAAAA==.Coolbreeze:BAABNQAECn8WAAIWAAcKlRpDEwApAgAWAAcKlRpDEwApAgAAAA==.Corpsgrinder:BAABNQAECn8WAAIZAAkKeBpPGwCfAgAZAAkKeBpPGwCfAgAAAA==.',
Cr='Crashöut:BAAANQADCgIIAgAAAA==.Crysix:BAAANQAECgEIAQAAAA==.',
Cz='Cz:BAAANQADCgQIBAAAAA==.Czera:BAAANQADCgMIAwAAAA==.',
Da='Dahialkahina:BAAANQAECgQIBwAAAA==.Damagenpayne:BAAANQABCgEIAQAAAA==.Darkmeadow:BAAANQAECgUIDwAAAA==.Dastard:BAABNQAECn8hAAIaAAkK9BpOMQCyAgAaAAkK9BpOMQCyAgAAAA==.',
De='Deadlock:BAAANQAECgEIAgAAAA==.Deadplank:BAABNQAECn8XAAIGAAcKyBMZVgCYAQAGAAcKyBMZVgCYAQAAAA==.Deathlyfrost:BAAANQAECgEIAQAAAA==.Deathstouch:BAAANQAECgEIAgAAAA==.Deftonia:BAABNQAECn8YAAIEAAgK3gS27AA8AQAEAAgK3gS27AA8AQAAAA==.Degenerate:BAAANQADCgYICAAAAA==.Dementïa:BAABNQAECn8lAAMIAAgK2R5ZNADMAgAIAAgK2R5ZNADMAgAOAAEKsAH4mgAiAAAAAA==.Demonbläde:BAAANQAECgUIBgAAAA==.Dethany:BAABNQAECn8VAAIaAAYK4QVvvwAPAQAaAAYK4QVvvwAPAQABNQAECggIFQABAEADAA==.Devondric:BAABNQAECn87AAMJAAkKTyJOBQCdAwAJAAkKTyJOBQCdAwAbAAEKeQZULQApAAAAAA==.Devotion:BAAANQAECgEIAQABNQAFFAQIDwADAGYSAA==.Devotional:BAACNQAFFH8PAAMDAAQKZhLlEQA8AQADAAQKZhLlEQA8AQAEAAIKkQGSKwBsAAA1AAQKfzcAAwMACQptHowYABYDAAMACQptHowYABYDAAQAAwqDERM/AbQAAAAA.',
Di='Diekuh:BAAANQAECgEIAQAAAA==.Diivinity:BAAANQADCggICAABNQAECgkJJwAEAO0aAA==.Dimepiece:BAAANQADCgUIBwAAAA==.Dithi:BAAANQADCgQIBAAAAA==.Divinaputits:BAAANQAECgcJCgAAAA==.',
Dm='Dmatch:BAAANQAECgYIDgAAAA==.',
Do='Docholigay:BAAANQAECgMIBQAAAA==.Dojoh:BAAANQADCgMIAwAAAA==.Dommiemommie:BAAANQAECgQICgABNQAECgUIBgANAAAAAA==.Doozpal:BAABNQAECn8wAAIDAAkKhhfNMgCXAgADAAkKhhfNMgCXAgAAAA==.Dorinspins:BAEBNQAECn8eAAIHAAkKZRnUVgCDAgAHAAkKZRnUVgCDAgAAAA==.Downset:BAAANQAECgMIAwABNQAECgkJLAABAOcXAA==.',
Dr='Drakonman:BAAANQAECgIIAwAAAA==.Draynen:BAABNQAECn8tAAMRAAkKUSOVAgB+AwARAAkKUSOVAgB+AwAcAAIKShCw7wCFAAABNQAFFAQICAAdAGEXAA==.Drbanner:BAAANQADCgUIBQAAAA==.Drboom:BAAANQAECgUICgAAAA==.Drezd:BAABNQAECn8xAAIOAAkKdA9VKAAFAgAOAAkKdA9VKAAFAgAAAA==.',
Du='Duck:BAAANQAECgEIAgABNQAECgQIBwANAAAAAA==.Duckduck:BAAANQAECgEIAQABNQAECgQIBwANAAAAAA==.Dulcïnea:BAAANQAECggIBgABNQAECggIJQAIANkeAA==.Dumpymilk:BAAANQAECgEIAQABNQAECgkJFwAFAM4WAA==.',
Ea='Eao:BAABNQAECn8rAAIIAAgKcQ0MggAFAgAIAAgKcQ0MggAFAgAAAA==.',
Ed='Edrana:BAAANQADCgYIBgABNQAECgIIAgANAAAAAA==.',
Eh='Ehvyn:BAAANQADCggICgAAAA==.',
El='Elblaize:BAAANQAECgEIAgAAAA==.Elitistjerk:BAAANQADCgEIAQAAAA==.Ellisis:BAABNQAECn8bAAIVAAgK1RxEEwBrAgAVAAgK1RxEEwBrAgAAAA==.',
Em='Emriq:BAABNQAECn8jAAIEAAgKbBmNdABAAgAEAAgKbBmNdABAAgAAAA==.',
En='Enmai:BAABNQAECn8cAAICAAcKBQztqAB8AQACAAcKBQztqAB8AQAAAA==.',
Ep='Epiphany:BAABNQAECn8VAAIBAAgKQAMWIQFQAQABAAgKQAMWIQFQAQAAAA==.',
Er='Eraylina:BAABNQAECn8XAAIBAAcKCw5h9ACgAQABAAcKCw5h9ACgAQAAAA==.Ertivoker:BAAANQADCggICAABNQAECggIHAAQAMwaAA==.',
Eu='Eugima:BAAANQAECgEIAQAAAA==.Eulogy:BAABNQAECn8rAAMKAAgK7BnIGgBxAgAKAAgK7BnIGgBxAgAJAAUK9hxQewCjAQAAAA==.',
Ev='Evangelise:BAAANQADCgEIAQAAAA==.Eveille:BAAANQAECgEIAwAAAA==.',
Ex='Exxitus:BAAANQAECgUICQAAAA==.',
Fa='Faerielana:BAEBNQAECn8WAAIBAAgKxAt42ADTAQABAAgKxAt42ADTAQABNQAECggIGgAeAAoXAA==.Faith:BAAANQAECgMIBwAAAA==.Falsoqt:BAABNQAECn8UAAIfAAgKyRgfBwCVAgAfAAgKyRgfBwCVAgAAAA==.Fatblackcow:BAAANQADCgEIAQAAAA==.Fatgum:BAEANQADCgQIBAABNQAFFAcIGwADAC0dAA==.',
Fe='Fecalmatters:BAAANQAECgEIBAAAAA==.Felachio:BAABNQAECn8mAAIIAAgKkRkSVgBtAgAIAAgKkRkSVgBtAgAAAA==.',
Fj='Fjörgyn:BAACNQAFFH8cAAIaAAcKOyAuAQDOAgAaAAcKOyAuAQDOAgA1AAQKfygAAhoACQraJPgNAHgDABoACQraJPgNAHgDAAAA.',
Fl='Flankster:BAAANQAECgMIBgAAAA==.Flanksterr:BAAANQAECgQICQAAAA==.',
Fo='Fork:BAABNQAECn81AAISAAkKeiVtAQDcAwASAAkKeiVtAQDcAwAAAA==.Forsetí:BAAANQAECgEIAQAAAA==.Fozziedaburr:BAABNQAECn8lAAMeAAkKvR8GDAAIAwAeAAkKvR8GDAAIAwAgAAUKBxVEYQBGAQAAAA==.',
Fr='Frasierkrane:BAAANQADCgQIBwAAAA==.Frontmage:BAABNQAECn8dAAIBAAgKAx5YYAC+AgABAAgKAx5YYAC+AgAAAA==.',
Ft='Ftfk:BAAANQADCggIFgABNQAECgkJJQAdALshAA==.',
Ga='Galie:BAABNQAECn8lAAMgAAkKvBLMMgBLAgAgAAkKvBLMMgBLAgAWAAUKIQ2kOwDMAAAAAA==.Galiè:BAAANQADCgUICwAAAA==.Garrahoth:BAAANQAECgcIDgAAAA==.',
Ge='Gekk:BAABNQAECn8nAAMdAAgKHQxWIwCpAQAdAAgKHQxWIwCpAQAhAAUKIwp6JwD0AAAAAA==.',
Gi='Giaus:BAABNQAECn8gAAIBAAgKUB9/fgCBAgABAAgKUB9/fgCBAgAAAA==.Girby:BAAANQADCgcIBwAAAA==.',
Gl='Glaaive:BAAANQADCgEIAQAAAA==.Gleipnir:BAAANQADCgIIAgAAAA==.Glimmerwisp:BAABNQAECn8gAAIBAAkKNAxzxAD6AQABAAkKNAxzxAD6AQAAAA==.',
Go='Gobzilla:BAABNQAECn8WAAIcAAgKWBEVcwCvAQAcAAgKWBEVcwCvAQAAAA==.Gonn:BAAANQADCgUIBQAAAA==.Goub:BAAANQAECgcIEQAAAA==.',
Gr='Grapefantuh:BAAANQAECgQICAAAAA==.Grapefroot:BAAANQADCgcIBwAAAA==.Grapeinator:BAABNQAECn8YAAIEAAgKvhGQlwDvAQAEAAgKvhGQlwDvAQAAAA==.Grasseater:BAAANQADCgYIBgABNQAFFAMICAADAFEYAA==.Grimreapr:BAAANQAECgIIBAAAAA==.Grimrieber:BAABNQAECn8fAAMUAAkKthuxDwArAgAUAAgKZBuxDwArAgAHAAEKpR3zOQFYAAAAAA==.Gromn:BAABNQAECn81AAQTAAkKHyDXAQA9AwATAAkKHyDXAQA9AwAIAAMKlQaEJwGaAAAOAAEKegVVlQApAAAAAA==.',
Ha='Hanb:BAAANQADCggIEQABNQAECgQIBgANAAAAAA==.Happywoodz:BAAANQAECgEIAQABNQAECggIHwAcADMiAA==.Hashed:BAABNQAECn8YAAIEAAkKxB41NwDvAgAEAAkKxB41NwDvAgAAAA==.Hays:BAAANQAECgcICwAAAA==.Haysevoker:BAACNQAFFH8YAAQiAAYKjxz7BwC/AAAiAAIKriL7BwC/AAAhAAIKcRaqCwCPAAAdAAIKmw7UEwCOAAA1AAQKfyIABCIACQqOHqQEALQCACIACQqNHqQEALQCACEACApnDpUZAK0BAB0AAwrEDYs8ALIAAAAA.',
He='Heebb:BAAANQADCggICAAAAA==.Henn:BAAANQAECgIIAgAAAA==.Herself:BAAANQAECgEIAQABNQAECgcIFwAHAMYQAA==.',
Hi='Himself:BAAANQAECgEIAgAAAA==.',
Ho='Hobb:BAAANQADCgUIBQAAAA==.Holemilk:BAAANQADCggIEAAAAA==.Holycopter:BAAANQADCggIGgAAAA==.Holymojo:BAABNQAECn8XAAMJAAgKqyK3FgAcAwAJAAgKqyK3FgAcAwAbAAEKOQ8GKAA0AAAAAA==.Hoodler:BAECNQAFFH8QAAIeAAYKMh8dAwAaAgAeAAYKMh8dAwAaAgA1AAQKfy8AAx4ACQrPJYYCAKQDAB4ACQrPJYYCAKQDABcAAQp0Fdo8AEAAAAAA.Hoodlery:BAECNQAFFH8LAAIjAAYK+CA6AgAOAgAjAAYK+CA6AgAOAgA1AAQKfx0AAiMACQpTHs8JAOoCACMACQpTHs8JAOoCAAE1AAUUBggQAB4AMh8A.Hoofjob:BAACNQAFFH8QAAIkAAYK1hCwBQC6AQAkAAYK1hCwBQC6AQA1AAQKfycAAiQACQpYHhEYAIQCACQACQpYHhEYAIQCAAAA.',
Hu='Huskydots:BAACNQAFFH8HAAMCAAMKihD/LwCaAAACAAIKDhD/LwCaAAAfAAEKgRFDGwBPAAA1AAQKfyYAAwIACQpIFn1qABoCAAIACApZFn1qABoCAB8AAworDnRIAKUAAAAA.',
['Hé']='Hércules:BAAANQADCgIIAgAAAA==.',
Ia='Iaell:BAAANQAECgIIAgABNQAECggIJgAIAJEZAA==.',
Ib='Iblastpants:BAAANQAECgUIEQAAAA==.',
Id='Idd:BAAANQAECgIIBQAAAA==.',
Ig='Iggyy:BAAANQAECgUIEgAAAA==.',
Im='Imshaman:BAAANQAECgUIBQAAAA==.',
In='Inflammo:BAAANQAECgEIAgAAAA==.Insaneisbad:BAAANQADCggICQAAAA==.Insaneness:BAAANQAECggIDwAAAA==.',
Ir='Irila:BAAANQAECgMJCAAAAA==.',
It='Ithrein:BAAANQADCgYICwAAAA==.Its:BAAANQAECgUIEgABNQAECgcIFwAHAMYQAA==.',
Iz='Izumî:BAAANQADCggIEwAAAA==.',
Ja='Jackdáripper:BAAANQABCgYIBgAAAA==.Jakè:BAAANQAECgIIAgAAAA==.Jangosan:BAAANQAECgIIAgABNQAECgkJJQAYAMoVAA==.Jaslen:BAAANQADCgYIBgAAAA==.Jasono:BAAANQADCgYICgAAAA==.Jaspy:BAABNQAECn8sAAIWAAkKbhwdCwC4AgAWAAkKbhwdCwC4AgAAAA==.',
Je='Jeffdennis:BAABNQAECn8bAAIHAAkK+RJPcwA3AgAHAAkK+RJPcwA3AgAAAA==.',
Ji='Jimmybuffler:BAABNQAECn8XAAIDAAgKBRvPOgB3AgADAAgKBRvPOgB3AgAAAA==.',
Jo='Jomgpallie:BAABNQAECn8aAAIEAAgK4Q58qwDDAQAEAAgK4Q58qwDDAQAAAA==.Jonra:BAAANQAECgEIAQAAAA==.Josefbugman:BAAANQAECgQIBwAAAA==.',
Ju='Judykiki:BAAANQAECgQICwABNQAECgYIFwAGANYUAA==.Juecy:BAAANQAECgcIBwAAAA==.Juju:BAAANQAECgYIEQAAAA==.Juktal:BAABNQAECn8aAAITAAgKbxCYBgAmAgATAAgKbxCYBgAmAgAAAA==.Justyn:BAABNQAECn8ZAAMHAAcKZA/GrgCiAQAHAAcKZA/GrgCiAQAUAAEKAAChTQARAAAAAA==.',
Ka='Kaeden:BAAANQADCgQJBAAAAA==.Kahlán:BAAANQABCgcICQAAAA==.Kainz:BAAANQAECgIIBAAAAA==.Kaonazor:BAAANQADCgYIBgAAAA==.Kaoscontrol:BAAANQADCgUIDgAAAA==.Karbonette:BAAANQADCgYIBgAAAA==.Kattakuri:BAAANQAECgQIBAAAAA==.Kazaju:BAABNQAECn8ZAAMfAAkKuh5FLQAXAQACAAYKdhxohgDRAQAfAAMKYSRFLQAXAQAAAA==.',
Ki='Kialorstus:BAABNQAECn8hAAQSAAkKxRY4KgBFAgASAAkKxRY4KgBFAgAlAAQKIguYowCvAAAGAAEK5gSH0QAqAAAAAA==.Kinzington:BAAANQAECgYICgABNQAECgkJLAABAOcXAA==.Kirbo:BAAANQAECgcIDQAAAA==.Kitagawa:BAABNQAECn8uAAIGAAkKth8yFgD5AgAGAAkKth8yFgD5AgAAAA==.Kitten:BAAANQAECgYIDwAAAA==.',
Kl='Klondikecow:BAAANQABCgMIBAAAAA==.',
Ko='Kolakua:BAAANQADCgQIBAAAAA==.Korianth:BAAANQAECgUICgAAAA==.Korlon:BAAANQADCgYICwAAAA==.Kouw:BAABNQAECn8WAAIEAAkK8A7pmQDqAQAEAAkK8A7pmQDqAQAAAA==.',
Kr='Kradyn:BAAANQAECgUJBgAAAA==.Kragfoerend:BAABNQAECn8YAAIHAAcKEgM/8wDyAAAHAAcKEgM/8wDyAAAAAA==.Kramx:BAAANQAECgMIBAAAAA==.Krankenstein:BAABNQAECn8nAAIGAAgKhxnMMABLAgAGAAgKhxnMMABLAgAAAA==.Krankson:BAAANQADCgIIAgAAAA==.Kriix:BAABNQAECn8ZAAIZAAgK5iBaEgDnAgAZAAgK5iBaEgDnAgAAAA==.Krusnik:BAAANQADCgUICAAAAA==.Kruurk:BAAANQADCgQIBAAAAA==.',
Ks='Ksubii:BAAANQAECgYIBwAAAA==.',
Ku='Kuhtta:BAAANQAECgUIEwAAAA==.Kumdobeast:BAAANQAECgQIEAAAAA==.Kuothe:BAAANQAECgUIEgAAAA==.',
Ky='Kyina:BAAANQAECgEIAQAAAA==.Kyotpal:BAAANQADCgYIDAAAAA==.Kyotsas:BAAANQAECggIBgAAAA==.',
La='Lazyriver:BAABNQAECn8aAAISAAYKSw58VwBGAQASAAYKSw58VwBGAQABNQAECgYKGgASAEsOAA==.',
Le='Legoland:BAAANQAECggIBAAAAA==.Leonphelps:BAAANQADCgYIBwAAAA==.Lesnichii:BAABNQAECn8ZAAIgAAgKgA9nQgDpAQAgAAgKgA9nQgDpAQAAAA==.Lewakex:BAAANQAECggIEgAAAA==.Leyninade:BAABNQAECn8aAAIgAAgKQxTpOgAYAgAgAAgKQxTpOgAYAgAAAA==.',
Li='Lightbrngr:BAABNQAECn8pAAIEAAkKgByTPQDaAgAEAAkKgByTPQDaAgAAAA==.Lihuai:BAAANQADCggIDAAAAA==.Liilpeep:BAAANQAECggIDAAAAA==.Lilbertha:BAAANQAECgIIBAAAAA==.Lilchigirl:BAAANQADCgYIBgAAAA==.Lildipster:BAAANQADCggIGAABNQAECgkJFwAFAM4WAA==.Lildump:BAAANQAECgcIEgABNQAECgkJFAAcAPAdAA==.Limitlessone:BAABNQAECn8aAAIBAAcKCh7SlwBQAgABAAcKCh7SlwBQAgAAAA==.Lionescanor:BAAANQAECgMIAQAAAA==.Liptonaysti:BAAANQAECgQIDQAAAA==.Lissandine:BAEBNQAECn8jAAMLAAkKqRIrCwAbAgALAAkKqRIrCwAbAgAMAAUKHgR7bQC9AAAAAA==.Liya:BAAANQAECgEIAwABNQAFFAQIDAAGAGghAA==.Lizzywizzy:BAAANQADCgYIBgABNQAECgkJFwAFAM4WAA==.',
Lo='Locrian:BAAANQAECgEIAgAAAA==.Lokikillz:BAAANQAECgYIEQAAAA==.Lotharn:BAAANQADCgMIAQAAAA==.Lowdy:BAABNQAECn8nAAMHAAkKNROscAA+AgAHAAkKXxKscAA+AgAPAAIKeBi3JQB8AAAAAA==.',
Lu='Luulk:BAABNQAECn8XAAIGAAYK1hTBYABsAQAGAAYK1hTBYABsAQAAAA==.',
Ly='Lych:BAAANQAECgcIDgAAAA==.Lyclaw:BAAANQADCgMIAwAAAA==.',
['Lì']='Lìllith:BAAANQAECgYIDgAAAA==.Lìvíd:BAAANQADCgIIAgAAAA==.',
Ma='Madoris:BAAANQAECgUIEQAAAA==.Magemagerson:BAABNQAECn8dAAIBAAkKMCH0JQBIAwABAAkKMCH0JQBIAwAAAA==.Magnuss:BAABNQAECn8VAAMBAAkKTgdw4wC/AQABAAkKTgdw4wC/AQAQAAIKJQN0OwBPAAAAAA==.Magvox:BAAANQAECgEIAQAAAA==.Mahini:BAAANQADCgYIBgAAAA==.Mahnion:BAAANQADCggICAAAAA==.Malleus:BAABNQAECn8YAAISAAcK1A8eRwCbAQASAAcK1A8eRwCbAQAAAA==.Mammutos:BAABNQAECn8bAAIeAAcKnhWpKgDFAQAeAAcKnhWpKgDFAQAAAA==.Manifred:BAAANQADCgYIFAAAAA==.Manion:BAABNQAECn8kAAMcAAgKyCCHIADlAgAcAAgKyCCHIADlAgAaAAYKWROVjACBAQAAAA==.Manipepper:BAABNQAECn8WAAMCAAYKcAbu2AASAQACAAYKcAbu2AASAQAfAAIK6gTaZgBUAAAAAA==.Manippiez:BAAANQAECgMIBwAAAA==.Manipulating:BAAANQADCgYIBgAAAA==.Manipulation:BAAANQAECgEIAQAAAA==.Mannarchy:BAAANQADCgQIBAAAAA==.Mantrà:BAAANQAECgIIAgAAAA==.Maplemaga:BAAANQAECggIDQAAAA==.Margot:BAAANQADCgYIDAABNQAECgQIBgANAAAAAA==.Masochista:BAACNQAFFH8MAAIGAAQKaCEaDQB9AQAGAAQKaCEaDQB9AQA1AAQKfxkAAgYACQpcJVEIAHgDAAYACQpcJVEIAHgDAAAA.Mastric:BAEBNQAECn8qAAICAAgK/QZ4pwB/AQACAAgK/QZ4pwB/AQAAAA==.',
Mc='Mccaffrey:BAABNQAECn8nAAIHAAgKSRavfgAbAgAHAAgKSRavfgAbAgAAAA==.',
Me='Meetch:BAABNQAECn8nAAIlAAgKXR0YJgCjAgAlAAgKXR0YJgCjAgAAAA==.Megdar:BAABNQAECn8WAAIkAAcKwwxdNQBlAQAkAAcKwwxdNQBlAQAAAA==.Melledreu:BAACNQAFFH8GAAIQAAIKtAK5CQB1AAAQAAIKtAK5CQB1AAA1AAQKf14AAxAACQqaDNEOALsBABAACQooDNEOALsBAAEACQpABVb7AJMBAAAA.Mellessan:BAAANQAECgEIBAAAAA==.Merix:BAABNQAECn8nAAMZAAkKtx/aRQCpAQAZAAUK8h/aRQCpAQAYAAUKtx0JJwCKAQAAAA==.Mestea:BAABNQAECn8XAAMcAAcK4wiFogArAQAcAAcK4wiFogArAQAaAAIKIAlLDAFsAAAAAA==.Mewing:BAAANQAECgQIBAABNQAECggIIgAEAP4jAA==.',
Mi='Miraclemill:BAAANQADCgcIFQAAAA==.Mirra:BAABNQAECn8bAAIJAAcKkRcbagDcAQAJAAcKkRcbagDcAQAAAA==.',
Mo='Mojobtw:BAAANQADCgcIBwAAAA==.Momoshirow:BAAANQADCgQIBwAAAA==.Momø:BAAANQADCgUJBQAAAA==.Monsterboy:BAAANQADCgIIAgAAAA==.Mortamur:BAABNQAECn8eAAIBAAkKrRSxjwBgAgABAAkKrRSxjwBgAgAAAA==.Mortelinnos:BAABNQAECn8rAAIMAAgKWCQqDABHAwAMAAgKWCQqDABHAwAAAA==.',
My='Mysticguru:BAABNQAECn8cAAIcAAYKVh30bQC9AQAcAAYKVh30bQC9AQAAAA==.Mythrax:BAABNQAECn8hAAMTAAkKcxvLAgD8AgATAAkKcxvLAgD8AgAOAAIKpwbldABjAAAAAA==.',
['Mà']='Mànion:BAAANQAECgEIAQAAAA==.',
Na='Naisu:BAAANQAECggICAAAAA==.Naradrae:BAAANQAECgQIDQAAAA==.Narodaran:BAAANQAECggIDAAAAA==.Naughtyrawr:BAAANQAECgUIDAAAAA==.',
Ne='Necropete:BAAANQAECgIIAgABNQAFFAEIAQANAAAAAA==.Neondemon:BAAANQAECgMIBAAAAA==.Nevets:BAABNQAECn8lAAIOAAkK8R6bCwAdAwAOAAkK8R6bCwAdAwAAAA==.Nevrs:BAAANQAECgUIDQAAAA==.Newworld:BAAANQAECgEIAQAAAA==.',
Ni='Nikolajokic:BAAANQAECgIIAwAAAA==.Nimit:BAABNQAECn8iAAIIAAgKEBwzSQCPAgAIAAgKEBwzSQCPAgAAAA==.',
No='Noazora:BAAANQAECgEIAQAAAA==.Noughtsee:BAABNQAECn8YAAIBAAYK9AiiJAFLAQABAAYK9AiiJAFLAQAAAA==.Novic:BAABNQAECn8iAAIJAAkKWRGoYwDxAQAJAAkKWRGoYwDxAQAAAA==.Noxinox:BAAANQADCgYIBwAAAA==.Nozom:BAAANQADCgEIAQABNQAECgcIDgANAAAAAA==.',
Nu='Nualia:BAABNQAECn8fAAIEAAkK/xvmPwDSAgAEAAkK/xvmPwDSAgAAAA==.',
['Né']='Némésis:BAAANQAECgQIDwAAAA==.',
Oc='Oceaná:BAAANQADCggICAAAAA==.',
Oj='Ojacks:BAAANQAECgMIAwAAAA==.Ojaks:BAABNQAECn8VAAIRAAgKCBS8FQAJAgARAAgKCBS8FQAJAgAAAA==.',
Op='Operendi:BAAANQADCgYIBgAAAA==.',
Or='Orbian:BAAANQADCgcIBwAAAA==.Orobus:BAACNQAFFH8HAAIPAAMK8RbDAQADAQAPAAMK8RbDAQADAQA1AAQKfxoAAw8ACQprIPwFALICAA8ACAprIPwFALICABQAAQoAALw7AFMAAAAA.',
Os='Oscassey:BAABNQAECn8nAAIZAAgK2grrPwDHAQAZAAgK2grrPwDHAQAAAA==.',
Ox='Oxley:BAABNQAECn8aAAIXAAgKGBocCwB8AgAXAAgKGBocCwB8AgAAAA==.',
Pa='Paladingus:BAABNQAECn8dAAMEAAgKWB4geAA4AgAEAAgKKxsgeAA4AgAVAAQKbCCDLwBeAQAAAA==.Pandidin:BAABNQAECn8kAAMjAAgKlxbGFwD+AQAjAAgKlxbGFwD+AQAkAAIKuQ2HXgBgAAAAAA==.Pauldrons:BAACNQAFFH8GAAMlAAIKzgk/GgCGAAAlAAIKzgk/GgCGAAASAAEKowIkIQA1AAA1AAQKf0YAAyUACQrQEr5CAA0CACUACQrGEr5CAA0CABIABwrPBqdeACMBAAAA.',
Pe='Peenar:BAABNQAECn8cAAQOAAkKsyE0DwDxAgAOAAgKsyE0DwDxAgAIAAIK8iNiHQG6AAATAAIKJhytDgCvAAAAAA==.Peenpikmin:BAAANQADCgQJBAAAAA==.Pejorative:BAAANQADCgYIBgAAAA==.',
Ph='Pharlock:BAABNQAECn8ZAAICAAcK3Ba8awAWAgACAAcK3Ba8awAWAgAAAA==.Pharlòck:BAAANQADCgUIBgABNQAECgcIGQACANwWAA==.Phobia:BAAANQADCggICAABNQAECggIKwAKAOwZAA==.',
Pi='Picklelips:BAAANQADCgQIBQAAAA==.',
Pl='Plankie:BAAANQADCgUICAAAAA==.Plankreaver:BAAANQADCgIIAgAAAA==.Planks:BAAANQAECgIIAwAAAA==.Plankz:BAAANQADCgMIAwAAAA==.',
Po='Pooterdiddle:BAAANQAECgUICAAAAA==.',
Pr='Priesttess:BAAANQADCgcICgAAAA==.Prohealin:BAABNQAECn8lAAIJAAgKBge5hwB7AQAJAAgKBge5hwB7AQAAAA==.',
Ps='Psarahdactyl:BAAANQADCgIIAgAAAA==.Psychosís:BAAANQADCgQIBAAAAA==.',
Pt='Ptiteagacee:BAABNQAECn8dAAQKAAgKaRrgJgDxAQAKAAYK4RrgJgDxAQAJAAYKTxl0ZwDkAQAbAAUKGhrbCwB+AQAAAA==.',
Pu='Pufdaddy:BAAANQAECgUIDwAAAA==.Puffpuffy:BAAANQADCgYIBgAAAA==.Puffymüffins:BAAANQADCgIIAgABNQAECggIHQAIAO8bAA==.Pumpkinq:BAABNQAECn9CAAMYAAkK5yEkAwBzAwAYAAkK1iEkAwBzAwAZAAQKvBoZZgASAQAAAA==.',
Py='Pyre:BAAANQABCgIJAgAAAA==.',
['Pì']='Pìkachu:BAABNQAECn8rAAMBAAkKcBssTgDlAgABAAkKcBssTgDlAgAQAAMK7xiqJADGAAAAAA==.',
Ra='Raby:BAAANQADCgYIBgAAAA==.Ragemommie:BAAANQAECgMIBAABNQAECgUIBgANAAAAAA==.Rainer:BAAANQAECgEIAgAAAA==.Ramiel:BAAANQAECgEIAgAAAA==.Rasmus:BAABNQAECn8fAAIVAAgKPxVuIADeAQAVAAgKPxVuIADeAQAAAA==.Raykwan:BAAANQADCgUIBQAAAA==.Rayquaza:BAABNQAECn8lAAIdAAkKuyFrBABoAwAdAAkKuyFrBABoAwAAAA==.Razzahola:BAAANQADCgIIAgABNQAECgQIBQANAAAAAA==.Razzmatazz:BAABNQAECn8kAAIBAAgK7Bj1iwBnAgABAAgK7Bj1iwBnAgAAAA==.',
Re='Reddeyes:BAABNQAECn8bAAIhAAcKewedIABMAQAhAAcKewedIABMAQAAAA==.Regulüs:BAAANQAECggIDwAAAA==.Rescue:BAABNQAECn8sAAIBAAkK5xckbwCfAgABAAkK5xckbwCfAgAAAA==.Reva:BAEANQAECgcICQABNQAECgkJKAAKAFMgAA==.',
Ri='Rising:BAAANQAECgEIAQAAAA==.',
Ro='Roamin:BAAANQADCggJCAAAAA==.Roasted:BAABNQAECn8qAAIBAAkKCBoTXgDDAgABAAkKCBoTXgDDAgAAAA==.Rockma:BAAANQAECggICQAAAA==.Rollandburn:BAAANQAECgQIEQAAAA==.Romantacykmc:BAAANQADCgUIDQAAAA==.Roxymigurdia:BAABNQAECn8dAAIIAAkKFyUZBADHAwAIAAkKFyUZBADHAwAAAA==.',
Ru='Rufföaddy:BAABNQAECn8rAAIDAAgKoiMhFAAwAwADAAgKoiMhFAAwAwAAAA==.Rumproast:BAAANQAECgIIBAABNQAECgcIDgANAAAAAA==.Runeesa:BAAANQAECgYIEwAAAA==.',
Ry='Rylena:BAABNQAECn8cAAMIAAcKWiKGTACGAgAIAAcKWiKGTACGAgAOAAUK3BDgTAD6AAAAAA==.Ryuke:BAAANQAECgYIBwAAAA==.Ryvalry:BAAANQAECgEIAQAAAA==.',
['Rà']='Ràvenn:BAAANQAECgEIAQABNQAECgUIDAANAAAAAA==.',
['Râ']='Râmên:BAAANQADCgEIAQAAAA==.',
Sa='Sagikos:BAEBNQAECn8aAAMeAAgKChfzIQATAgAeAAgKChfzIQATAgAgAAEKFAl/rAA5AAAAAA==.Sardras:BAABNQAECn8mAAIeAAgKDyXoBgBSAwAeAAgKDyXoBgBSAwAAAA==.Sark:BAAANQAECgYICQAAAA==.Sathor:BAAANQAECgUICgAAAA==.Sauccyy:BAAANQAECgQIBQAAAA==.Saucecity:BAAANQAECgQIBQAAAA==.Saucyjenkins:BAAANQAECgYIDQAAAA==.',
Sc='Scranton:BAAANQAECgEIAQAAAA==.',
Se='Sean:BAAANQADCgYICwAAAA==.Selest:BAAANQADCgEIAQAAAA==.Sellout:BAAANQAECgEIAQAAAA==.Semprefi:BAAANQADCgcIBwAAAA==.',
Sh='Shaani:BAAANQAECgEIAQAAAA==.Shace:BAAANQAECggICQAAAA==.Shadowfoot:BAAANQADCgUIBQAAAA==.Shadowhut:BAAANQADCgQIBAAAAA==.Shalanot:BAEANQAECgUIDQABNQAECggIGgAeAAoXAA==.Shamerific:BAAANQAECgEIAQAAAA==.Shamlus:BAAANQAECgEIAQABNQAECgcIFgADAIgkAA==.Shammooz:BAACNQAFFH8GAAIRAAIKpRlCBQC8AAARAAIKpRlCBQC8AAA1AAQKf2AAAhEACQrdH7MGABcDABEACQrdH7MGABcDAAAA.Shamyshaman:BAAANQAECgEIAgAAAA==.Shinier:BAABNQAECn8pAAIDAAkKjSPVBACpAwADAAkKjSPVBACpAwAAAA==.Shockwoods:BAABNQAECn8fAAMcAAgKMyK6GgADAwAcAAgKMyK6GgADAwAaAAIK7A5ECAF0AAAAAA==.Shondo:BAAANQAECgYIBgAAAA==.',
Si='Silversmage:BAAANQAECgUICgAAAA==.Simohayha:BAAANQADCgIIAgAAAA==.Sixseven:BAAANQAECgUJBQAAAA==.',
Sk='Skeeboo:BAAANQABCgYIBgAAAA==.Skülly:BAAANQAECgQIBAAAAA==.',
Sl='Slappywappy:BAABNQAECn8bAAIBAAYKNx3ByQDwAQABAAYKNx3ByQDwAQAAAA==.',
Sm='Smorcin:BAABNQAECn8fAAIHAAgK5R4qUgCQAgAHAAgK5R4qUgCQAgAAAA==.',
Sn='Sneekybeef:BAAANQAECgYIBgAAAA==.',
So='Softdeath:BAAANQADCgcIBwAAAA==.Sosoh:BAAANQAECgIIBQABNQAECgYIFwAGANYUAA==.',
Sp='Spellnchill:BAABNQAECn8VAAIBAAgKSAoU1wDWAQABAAgKSAoU1wDWAQAAAA==.Spintor:BAABNQAECn8ZAAIKAAcK6hQLKQDcAQAKAAcK6hQLKQDcAQAAAA==.Spookyy:BAAANQADCgMIAwAAAA==.',
Sq='Squidseye:BAAANQAECgYIDQAAAA==.',
St='Stainn:BAAANQAECgMIAwAAAA==.Stalk:BAAANQABCgIIAgAAAA==.Steelwaves:BAAANQAECgEJAgAAAA==.Stevelock:BAAANQADCgMIAwABNQAECgEIAQANAAAAAA==.Stoade:BAAANQAECgEIBQAAAA==.Stormfang:BAAANQADCgIIAgAAAA==.Stormrise:BAAANQAECgUIDAAAAA==.Stricker:BAABNQAECn8kAAMeAAkKRiH7BgBRAwAeAAkKRiH7BgBRAwAgAAMKOB3afQDRAAAAAA==.',
Su='Sukuta:BAAANQAECgIIAgAAAA==.Sunamue:BAAANQADCgYIBgAAAA==.Surious:BAAANQADCgYIBgABNQAECgQIBgANAAAAAA==.',
Sw='Sweettooth:BAAANQAECgMIBQAAAA==.',
Sy='Syphian:BAAANQAECgEIBAAAAA==.Syrenda:BAAANQADCgUIBQAAAA==.',
Ta='Taasdingo:BAAANQADCgYIDQABNQAECgkJFwAFAM4WAA==.Tacoboat:BAABNQAECn8wAAIHAAgK9QrYqgCtAQAHAAgK9QrYqgCtAQAAAA==.Tacopizza:BAAANQADCggICQAAAA==.Taishigi:BAABNQAECn8cAAICAAkKyw6acQAHAgACAAkKyw6acQAHAgAAAA==.Tapewyrm:BAABNQAECn8gAAICAAgKlxb+XQA6AgACAAgKlxb+XQA6AgAAAA==.Tathfak:BAAANQADCgUIBQAAAA==.Tatter:BAAANQADCgEIAQAAAA==.',
Te='Tecknique:BAABNQAECn8fAAMGAAkKPwkYWACQAQAGAAkKPwkYWACQAQAlAAEKAAAb5QAtAAAAAA==.Teedge:BAACNQAFFH8KAAIhAAQKlRHeBgApAQAhAAQKlRHeBgApAQA1AAQKfzIAAyEACQqiHU0JANwCACEACQrZG00JANwCACIABArGG0wQADABAAAA.Teefz:BAAANQAECgUICwAAAA==.Terraphy:BAAANQADCgYICwABNQAECgUIDgANAAAAAA==.',
Th='Thaldric:BAAANQABCgQIBgAAAA==.Thanos:BAAANQADCgMIAwAAAA==.Thatwhitekid:BAABNQAECn8bAAIRAAgKPhrODQCOAgARAAgKPhrODQCOAgAAAA==.Thepaintrain:BAABNQAECn8XAAMHAAcKxhDwsACdAQAHAAcKxhDwsACdAQAPAAEKAABMMwAzAAAAAA==.Theporkchop:BAAANQADCgIIAgAAAA==.Thomasa:BAAANQAECgEIAgAAAA==.Thorodron:BAAANQADCgEJAQAAAA==.Thundera:BAAANQAECgQIEQAAAA==.',
Ti='Tierjar:BAAANQADCgcIBwAAAA==.Timberdoc:BAAANQAECgUIEQAAAA==.Timmehh:BAAANQAECgcICAABNQAFFAQICgAhAJURAA==.Tindril:BAABNQAECn8mAAQeAAgKFyWgBwBHAwAeAAgKFyWgBwBHAwAWAAQKXAwcRgCSAAAgAAEKAABxuAAmAAAAAA==.',
To='Tolan:BAABNQAECn8ZAAIDAAgKvBrgQQBbAgADAAgKvBrgQQBbAgAAAA==.Toovok:BAAANQADCggICAAAAA==.Totemtartt:BAABNQAECn8rAAIcAAkKFx3mKQC6AgAcAAkKFx3mKQC6AgAAAA==.Toxcyurifeet:BAAANQADCggICAABNQAFFAMIBwAPAPEWAA==.Toxicai:BAABNQAECn8gAAIjAAgKghONGgDTAQAjAAgKghONGgDTAQAAAA==.',
Tr='Trakeus:BAABNQAECn8UAAMMAAgKDxZiLAA8AgAMAAgKDxZiLAA8AgAFAAEKXwF1dwATAAAAAA==.Treespriest:BAAANQAECgcIBwAAAA==.Treyman:BAABNQAECn8fAAIEAAkKFBTYZABoAgAEAAkKFBTYZABoAgAAAA==.Tribune:BAABNQAECn8lAAIGAAgKRSGLIACtAgAGAAgKRSGLIACtAgABNQAECgkJGgAWAJwkAA==.Trinitree:BAAANQAECgQIBQAAAA==.Trinkler:BAAANQAECgYIEgAAAA==.',
Tu='Tunka:BAAANQADCgcIEAAAAA==.',
Tw='Twist:BAABNQAECn8bAAIQAAcKkBYmCwANAgAQAAcKkBYmCwANAgAAAA==.',
Ty='Tychondris:BAABNQAECn8rAAIIAAgKUAqPlwDVAQAIAAgKUAqPlwDVAQAAAA==.Tyzonelfalas:BAAANQAECgcIDAAAAA==.',
Ul='Ulsoga:BAABNQAECn8hAAImAAgKFA9nCAAHAgAmAAgKFA9nCAAHAgAAAA==.',
Un='Unbórn:BAAANQAECgIIAgAAAA==.Undeadbeast:BAAANQADCgYICgAAAA==.',
Ut='Utica:BAAANQADCgcJCQAAAA==.',
Va='Vaiko:BAAANQADCgMIAwAAAA==.Valak:BAAANQAECgEIAgAAAA==.Valkyries:BAAANQAECggIBAAAAA==.Varibash:BAAANQADCggICAABNQAECggIKwAKAOwZAA==.Vaspara:BAACNQAFFH8IAAIDAAMKURiPFQABAQADAAMKURiPFQABAQA1AAQKfxoAAgMACQoTHVYfAPECAAMACQoTHVYfAPECAAAA.',
Ve='Vergalis:BAAANQAECgEIAQAAAA==.',
Vi='Vileknight:BAAANQAECgEIAQAAAA==.Visark:BAAANQADCggICAAAAA==.Visz:BAAANQADCgQIBAAAAA==.Vitlania:BAAANQAECgQIBAAAAA==.',
Vo='Voidlìlíth:BAABNQAECn8iAAIBAAgK1BcnoABAAgABAAgK1BcnoABAAgAAAA==.Voidwak:BAAANQAECgUIDQAAAA==.Vorronni:BAABNQAECn8hAAMJAAgKiCC/JADWAgAJAAgKiCC/JADWAgAbAAEKFRvDIgBPAAAAAA==.',
Wa='Wardo:BAACNQAFFH8aAAMCAAYKLhuKCgDEAQACAAUKZhmKCgDEAQAfAAEKhiADFQBgAAA1AAQKfzkABAIACQpHJZIPAFIDAAIACAohJZIPAFIDAB8ABwqbG38NACACACYAAQrUG9AvADUAAAAA.Warhelm:BAAANQADCgMIAwAAAA==.Warlok:BAAANQADCgEIAQAAAA==.Wastedraider:BAAANQAECgUICAAAAA==.Wastedtank:BAAANQAECgEIAgAAAA==.',
We='Wellen:BAAANQADCgUICQAAAA==.Werewolf:BAAANQAECgYICgAAAA==.',
Wh='Whitemist:BAAANQAECgUICwAAAA==.Whitepikmin:BAABNQAECn8iAAMWAAkK7x9xCQDaAgAWAAgK7x9xCQDaAgAXAAEKAADjPQA8AAAAAA==.',
Wi='Wilmer:BAABNQAECn8iAAIIAAkK1h0aJQABAwAIAAkK1h0aJQABAwAAAA==.Wily:BAAANQADCggIDgAAAA==.Windowsvista:BAAANQAECgYIEAAAAA==.Winterlock:BAAANQADCgcJDQAAAA==.Wiseguy:BAAANQADCgcICQAAAA==.',
Wo='Wookieweener:BAAANQAECgQIBAABNQAECggIFQAHADwXAA==.',
Wr='Wravc:BAAANQAECgQICQAAAQ==.',
Xa='Xaden:BAAANQAECggIAQAAAA==.Xaspen:BAAANQAECgYIEQAAAA==.',
Xe='Xerukin:BAAANQADCgYJDAAAAA==.',
Xo='Xoroth:BAAANQAECgUICgAAAA==.Xoyan:BAAANQAECggICgAAAA==.',
Ya='Yargonz:BAAANQAECgcIEQAAAA==.Yargz:BAABNQAECn8UAAIVAAgKKQxILAB2AQAVAAgKKQxILAB2AQABNQAFFAYIGgAGAD0IAA==.Yargzdk:BAACNQAFFH8aAAIGAAYKPQgrEABNAQAGAAYKPQgrEABNAQA1AAQKfyMAAgYACQr6ETtMAMIBAAYACQr6ETtMAMIBAAAA.',
Ye='Yeyol:BAABNQAECn8nAAIZAAgKrRnzHACTAgAZAAgKrRnzHACTAgAAAA==.',
Yo='Yolius:BAABNQAECn8VAAIbAAUK3RgIDQBkAQAbAAUK3RgIDQBkAQAAAA==.Yoogi:BAAANQAECgEIAQABNQAECgcIDgANAAAAAA==.',
Yu='Yungnetero:BAAANQAECgQICQAAAA==.Yunikon:BAABNQAECn8yAAQEAAkKpiAxIwA2AwAEAAkKpiAxIwA2AwADAAcKwg9SfwCYAQAVAAcKoBTPKgCDAQABNQAECgkJFwAFAM4WAA==.',
Za='Zabala:BAAANQAECgEIAQABNQAECggIIwAEAGwZAA==.Zavorotnuk:BAAANQAECgEIAQAAAA==.',
Ze='Zell:BAAANQAECgYIDAABNQAECgcIFgADAIgkAA==.Zelluss:BAABNQAECn8WAAIDAAcKiCQVIgDiAgADAAcKiCQVIgDiAgAAAA==.Zelrin:BAAANQAECgEIAgAAAA==.Zeltari:BAAANQADCgQICAAAAA==.Zeothule:BAAANQAECggIAgAAAA==.Zephyrex:BAAANQAECgEIAwAAAA==.Zerkerpete:BAAANQAFFAEIAQAAAA==.',
Zh='Zhaphiria:BAABNQAFFH8IAAMdAAQKYRcyDABTAQAdAAQKYRcyDABTAQAiAAIKog5UCQCJAAAAAA==.Zhul:BAABNQAECn8bAAIIAAgKQhc1XgBZAgAIAAgKQhc1XgBZAgABNQAECggIHQAEAFgeAA==.',
Zi='Zijin:BAAANQAECgIIAgAAAA==.Zimmy:BAAANQADCgYIBgAAAA==.',
Zo='Zohzah:BAAANQAECgEIAQAAAA==.Zoomies:BAAANQAECgUICgAAAA==.',
Zu='Zuldahn:BAAANQADCgYIBgAAAA==.',
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
