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

local lookup = {'Warlock-Affliction','Warlock-Destruction','Paladin-Protection','Shaman-Elemental','Druid-Balance','Hunter-BeastMastery','Unknown-Unknown','Shaman-Restoration','Mage-Arcane','Paladin-Holy','DemonHunter-Havoc','Monk-Windwalker','Hunter-Marksmanship','Priest-Holy','Priest-Shadow','Paladin-Retribution','Warrior-Arms','Hunter-Survival','Druid-Guardian','Druid-Restoration','Shaman-Enhancement','Monk-Brewmaster','Druid-Feral','Warrior-Fury','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Demonology','Priest-Discipline','Warrior-Protection','Evoker-Devastation','DemonHunter-Vengeance','Rogue-Subtlety','Mage-Frost','Monk-Mistweaver','DemonHunter-Devourer',}
local provider = {region='US',realm='Dawnbringer',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abdalhazred:BAACNQAFFH8SAAIBAAcK4R6jAAC6AQABAAcK4R6jAAC6AQA1AAQKfzkAAwEACgqaIhoBAGEDAAEACgqVIhoBAGEDAAIAAgqsGTdMAJsAAAAA.Abilus:BAABNQAECn8qAAIDAAYKehnhLQBvAQADAAYKehnhLQBvAQAAAA==.Abolis:BAABNQAECn8gAAIEAAYKeAx8kgDPAAAEAAYKeAx8kgDPAAAAAA==.',
Ad='Adarlan:BAAANQAECgIIAgAAAA==.Adolin:BAAANQAECgIIAwAAAA==.',
Ae='Aelianna:BAAANQAECgQICwAAAA==.',
Ah='Ahqwanken:BAAANQADCgMIBgAAAA==.',
Ai='Aintnowei:BAAANQAECgQIBQAAAA==.',
Al='Allina:BAAANQADCgYIBgAAAA==.Alnara:BAAANQAECgUIDgAAAA==.',
Am='Amoradis:BAAANQADCgcIDwAAAA==.',
An='Anarran:BAAANQAECgIIAwABNQAECgkJIwAFAPUOAA==.Animalfury:BAABNQAECn86AAIFAAgKWwvYMQBjAQAFAAgKWwvYMQBjAQAAAA==.Anthestria:BAAANQAECgQIBwAAAA==.',
Aq='Aqurala:BAABNQAECn81AAIGAAoKYiFkFgBBAwAGAAoKYiFkFgBBAwAAAA==.',
Ar='Arasham:BAAANQAECgQIBAABNQAECgoKKAAGAI8XAA==.Aravenn:BAABNQAECn8oAAIGAAoKjxdqeAAeAgAGAAoKjxdqeAAeAgAAAA==.Arionaa:BAAANQAECgEIAQAAAA==.Arkangel:BAAANQADCgYIBgABNQAECggIAQAHAAAAAA==.Artemesia:BAAANQAECgYICgABNQAFFAcIEgAIAOgbAA==.Artison:BAAANQAECgIIAgABNQAECgoKHAAJAPUQAA==.',
As='Ashiru:BAAANQADCgMIBQAAAA==.Assandra:BAAANQADCgUIBQAAAA==.',
At='Ateup:BAAANQAECgEIAQABNQAECgUIDgAHAAAAAA==.Athenos:BAAANQAECgMIAQABNQAECgYIAgAHAAAAAA==.Atlás:BAAANQAECgUIBwAAAA==.',
Au='Aurum:BAABNQAECn8ZAAIKAAkKghExeQCtAQAKAAkKghExeQCtAQAAAA==.',
Av='Avatartele:BAABNQAECn9JAAIEAAoKqhlaJQA/AgAEAAoKqhlaJQA/AgAAAA==.Avatartouka:BAABNQAECn9hAAMIAAoK3iRCAwDqAwAIAAoK3iRCAwDqAwAEAAkK8R3FIgBQAgAAAA==.Avrala:BAAANQADCgIJAgAAAA==.Avraria:BAABNQAECn8UAAILAAkKhwjyQgAQAQALAAkKhwjyQgAQAQAAAA==.Avylastral:BAAANQAECgIIAwAAAA==.',
Az='Azshaxa:BAACNQAFFH8VAAIMAAUKqhfbCADbAAAMAAUKqhfbCADbAAA1AAQKfy0AAgwACgr1G14ZAHkCAAwACgr1G14ZAHkCAAAA.',
['Aí']='Aísling:BAAANQAECgYIEgAAAA==.',
Ba='Bagador:BAACNQAFFH8GAAINAAMKoQP8EwCcAAANAAMKoQP8EwCcAAA1AAQKfycAAg0ACgqvFEYUAOwBAA0ACgqvFEYUAOwBAAAA.Banesnarl:BAAANQAECggIAgAAAA==.Barby:BAAANQAECgEIAgAAAA==.Barrs:BAAANQADCgMIAwAAAA==.Bastille:BAAANQAECgEIAQAAAA==.',
Be='Bearbuthealz:BAAANQAECgIIAwAAAA==.Beautifulluv:BAABNQAECn8nAAMOAAoK4BZDUADjAQAOAAoK4BZDUADjAQAPAAcKjgqYQAArAQAAAA==.Bekabeka:BAACNQAFFH8SAAIKAAcKCBjmBAAzAgAKAAcKCBjmBAAzAgA1AAQKf0MAAwoACgqQH4YZABIDAAoACgqQH4YZABIDABAAAQqJDXmAATkAAAAA.Bekabekabeka:BAAANQABCggJAQABNQAFFAcIEgAKAAgYAA==.Belfour:BAAANQADCgQIBAAAAA==.Bera:BAAANQAECggIBQAAAA==.',
Bi='Billybobjr:BAABNQAECn8sAAIIAAoK8Rz+OAAeAgAIAAoK8Rz+OAAeAgAAAA==.',
Bl='Blackbart:BAAANQADCgQIBAAAAA==.Bloodar:BAAANQAECggICQAAAA==.',
Bo='Bonski:BAAANQAECgYIEQAAAA==.Boomdoom:BAAANQAECgYIDQAAAA==.Boosterman:BAABNQAECn8hAAMQAAgKnB4dWwCHAgAQAAgKnB4dWwCHAgAKAAIK/xKS3gBKAAAAAA==.',
Br='Brakkar:BAAANQAECgMICAAAAA==.Brandish:BAAANQAECgEIAQAAAA==.Braxxis:BAABNQAECn8WAAIRAAgKJxDtbQCiAQARAAgKJxDtbQCiAQABNQAFFAYIFwASAHocAA==.Breadstick:BAABNQAECn8ZAAMTAAcK9BpwGADrAQATAAcK9BpwGADrAQAUAAQK6Re1UQCeAAAAAA==.Bress:BAAANQADCgYIBgABNQAECgkJHgADADsiAA==.Brihunts:BAACNQAFFH8FAAIGAAMKmRqtDgADAQAGAAMKmRqtDgADAQA1AAQKfxsAAgYACAqKHc1zALwBAAYACAqKHc1zALwBAAAA.Britotems:BAAANQAECgEIAgAAAA==.Brozo:BAAANQAECgEIAQAAAA==.Brutaal:BAAANQADCgQIBAAAAA==.Bruutaal:BAAANQAECgQICwAAAA==.',
Bu='Bubsydogo:BAAANQAECgEIAQAAAA==.',
Ca='Cacellice:BAAANQADCggICAAAAA==.Canoodles:BAAANQAECgcIDQAAAA==.',
Ce='Celaian:BAAANQAECgUICQABNQAECgQICQAHAAAAAA==.Celpanda:BAAANQAECgQICQAAAA==.',
Ch='Chadee:BAAANQADCggICAABNQAECggIJAAHAAAAAA==.Charybdia:BAAANQADCggJGwAAAA==.Cheesecake:BAABNQAECn8XAAIGAAgKIg85jQDwAQAGAAgKIg85jQDwAQAAAA==.Chidõri:BAABNQAECn8sAAQVAAoKgRfAEQBNAgAVAAkKhhXAEQBNAgAIAAgKTxgeOAAiAgAEAAQKNBQa0wDuAAAAAA==.Chopstix:BAAANQADCgQIBAAAAA==.Chunni:BAABNQAECn8uAAMWAAoKWAuKDQA9AQAWAAoKoAqKDQA9AQAMAAcKxQUAQQAPAQAAAA==.',
Co='Codap:BAAANQADCgEIAQAAAA==.Coolbeard:BAAANQAECgMIAwAAAA==.Cortex:BAAANQAECgYICgABNQAFFAIIBQAXAOsOAA==.',
Cr='Crayonman:BAABNQAECn8uAAIVAAoKeR3EBwCdAgAVAAoKeR3EBwCdAgAAAA==.Cronus:BAAANQAECgQICgABNQAECgcIDwAHAAAAAA==.Cruelkitty:BAAANQAECgQIBgAAAA==.',
Cy='Cyralai:BAAANQAECggICAAAAA==.',
Da='Dahlinar:BAAANQAECgUIEQAAAA==.Dalov:BAABNQAECn8iAAMKAAcKSR4RSQBDAgAKAAcKSR4RSQBDAgAQAAUK8x0H5QBRAQAAAA==.Damageworg:BAAANQAECgEIAQAAAA==.Dankley:BAABNQAECn8XAAIYAAcKFwZtHAC1AAAYAAcKFwZtHAC1AAAAAA==.Danystorm:BAAANQADCgcIBwABNQAFFAcIEgAIAOgbAA==.Darkomenz:BAAANQADCgEIAQAAAA==.Dayspot:BAAANQAECgEIAQAAAA==.',
Dd='Ddream:BAAANQADCgEIAQABNQAECgYIAgAHAAAAAA==.',
De='Deaddude:BAABNQAECn8oAAIZAAgKvxujLABlAgAZAAgKvxujLABlAgABNQAECgoKGQAEABMXAA==.Deathboi:BAABNQAECn8oAAIaAAoKSBBHHwDTAQAaAAoKSBBHHwDTAQAAAA==.Deathburgur:BAAANQAECggIDAAAAA==.Deathcuddles:BAABNQAECn8UAAIbAAcKSgK5hgCWAAAbAAcKSgK5hgCWAAAAAA==.Deathflower:BAAANQAECgEIAQAAAA==.Dedcow:BAABNQAECn8oAAIZAAkK2hn7FQBMAgAZAAkK2hn7FQBMAgAAAA==.',
Di='Diana:BAABNQAECn82AAIGAAoKQAuIYADtAQAGAAoKQAuIYADtAQAAAA==.Dionysus:BAAANQAECggIAQAAAA==.',
Do='Dontjudgemê:BAAANQADCgYJCgAAAA==.Dorcina:BAAANQADCgcICAAAAA==.Dornth:BAAANQAECgYIAgAAAA==.Downpour:BAAANQADCgUIBQAAAA==.',
Dr='Dracthyr:BAAANQAECgEIAgAAAA==.Dragam:BAAANQAECgQIBAABNQAECgoKJQAcAAYaAA==.Dragonwarrio:BAABNQAECn8rAAIMAAoKER1uDgBjAgAMAAoKER1uDgBjAgAAAA==.Draltina:BAABNQAECn8XAAICAAkK+wf3IABpAQACAAkK+wf3IABpAQAAAA==.Drazira:BAAANQAECgEIAQAAAA==.Dresstokill:BAAANQADCggJEQAAAA==.Drmonkborg:BAAANQAECgUICwABNQAECgoKKgAOAEsgAA==.Drovis:BAAANQAECgEIAgAAAA==.Druzzlek:BAAANQADCggIEQAAAA==.Drzaius:BAAANQAECggICAAAAA==.',
Du='Dubalnuar:BAAANQADCgUIEAAAAA==.Dubalpally:BAAANQADCgcIDQAAAA==.Dubaltrok:BAAANQADCgYIEgAAAA==.Dudde:BAABNQAECn8ZAAMEAAoKExenNwCYAgAEAAoKExenNwCYAgAVAAIKNAeOLQBsAAAAAA==.Dulapin:BAAANQADCgIIAgAAAA==.Duskfu:BAABNQAECn8qAAIMAAoKJh4bDQB7AgAMAAoKJh4bDQB7AgAAAA==.Dustylock:BAABNQAECn8lAAMcAAoKBhq1VABXAgAcAAoKBhq1VABXAgACAAEKzQeAfQAvAAAAAA==.',
Ea='Earthele:BAABNQAECn8bAAMEAAcKLwplhADvAAAEAAcKLwplhADvAAAIAAIK7QjRCwFQAAAAAA==.',
El='Elderblood:BAAANQADCgYIBgAAAA==.Elfcaster:BAAANQAECgEIAwAAAA==.Elfowl:BAAANQADCgYIBwABNQAECgoKMQAOAH0PAA==.',
Em='Emanonsahi:BAAANQAECgEIAQAAAA==.Emmel:BAAANQADCgcIDQAAAA==.',
Eq='Equeslucis:BAAANQAECggICQAAAA==.',
Er='Eromir:BAAANQAECgQICwABNQAECgUIDgAHAAAAAA==.Eryi:BAAANQAECgMICQAAAA==.',
Ev='Eviserator:BAAANQADCgYIDAAAAA==.',
Fa='Fable:BAABNQAECn8kAAIKAAkK0BgePgALAgAKAAkK0BgePgALAgAAAA==.Faegen:BAAANQADCgMIAwAAAA==.Fallumn:BAAANQADCgEIAQAAAA==.Fangytooth:BAAANQADCgYIBgABNQAECgoKLgAVAHkdAA==.Faze:BAAANQAECgUICwAAAA==.',
Fb='Fbitortamilf:BAAANQAECgUICgAAAA==.',
Fe='Fenlian:BAAANQAECgMIAwAAAA==.Feydoria:BAAANQAECgQIBQAAAA==.',
Fi='Firstfira:BAAANQAECgIIBwAAAA==.',
Fr='Frontman:BAABNQAECn8eAAMKAAgKiBllVQAZAgAKAAgKiBllVQAZAgAQAAIKjQ0DYwGBAAAAAA==.Frostscythe:BAAANQAECgEIAQAAAA==.',
Fu='Funkycolors:BAAANQAECgQIBQABNQAECgoKJQAcAAYaAA==.',
Ga='Gabomonk:BAAANQADCgEIAQABNQAECgIIAgAHAAAAAA==.Gavrael:BAAANQADCgQIBwAAAA==.',
Ge='Genma:BAAANQAECgYIDgAAAA==.Gewch:BAAANQAECgQIBQAAAA==.',
Gi='Gitgudder:BAAANQAECgQIBwAAAA==.',
Gl='Gloçk:BAABNQAECn8WAAMBAAoKThJPCgDUAQABAAoKFBJPCgDUAQAcAAIKaAXH/QBKAAAAAA==.',
Go='Goofy:BAAANQAECggIEwAAAA==.',
Gr='Graeae:BAAANQAECgIIAwAAAA==.Grimaldi:BAABNQAECn8jAAIFAAkK9Q5MLQCCAQAFAAkK9Q5MLQCCAQAAAA==.Grimvaka:BAAANQADCgYIBwAAAA==.Gripforceone:BAAANQAECggIAgAAAA==.',
Gu='Gunduin:BAABNQAECn86AAIGAAoKSRvNPgBHAgAGAAoKSRvNPgBHAgAAAA==.',
Gw='Gwinden:BAAANQADCgYICwAAAA==.',
Gy='Gyda:BAACNQAFFH8IAAIOAAMKXxzGGwD9AAAOAAMKXxzGGwD9AAA1AAQKf0oAAw4ACgrRIQIeAPkCAA4ACgrRIQIeAPkCAB0AAgoKDKEgAF0AAAAA.Gyuyuki:BAABNQAECn8/AAIEAAoKCA5DRQCoAQAEAAoKCA5DRQCoAQAAAA==.',
['Gó']='Gódofwàr:BAAANQAECgIIAgAAAA==.',
Ha='Haggish:BAAANQAECgQIBwAAAA==.Hakeo:BAEBNQAECn8pAAIeAAkKCiNxCQC1AgAeAAkKCiNxCQC1AgAAAA==.',
He='Heidie:BAAANQAECgUICAAAAA==.Hemajang:BAAANQAECgEIAgAAAA==.Hermin:BAAANQADCggIDgAAAA==.',
Hi='Hikomosil:BAABNQAECn8WAAIBAAcKiA18CwCzAQABAAcKiA18CwCzAQAAAA==.',
Ho='Holdmybeerz:BAAANQADCgUIBQAAAA==.Homiekissér:BAAANQAECgcIDAAAAA==.Hotzz:BAAANQAECgEIAQABNQAECgoKMgAIAHAdAA==.',
Hu='Hudsonhawk:BAAANQAECgEIAQAAAA==.',
['Hë']='Hëllen:BAAANQADCgIIAgAAAA==.',
['Hú']='Húñtrèss:BAAANQAECgEIBAAAAA==.',
Im='Imakittycat:BAABNQAECn8tAAIUAAoKYB2+FACiAgAUAAoKYB2+FACiAgAAAA==.Impared:BAAANQAECgYIBwABNQAECggIEAAHAAAAAA==.',
Is='Isummon:BAAANQADCgEIAQAAAA==.',
Iv='Ivey:BAAANQADCggIDAAAAA==.',
Ja='Jacburton:BAAANQADCgEIAQAAAA==.Jacenne:BAAANQAECgEIAwAAAA==.',
Je='Jenesis:BAABNQAECn9MAAMQAAoK4CPICwA/AwAQAAoK4CPICwA/AwAKAAEKHgOZMwEkAAAAAA==.Jerkme:BAAANQAECggICgAAAA==.',
Jo='Josephyn:BAABNQAECn8kAAIKAAoKTRYJSQBDAgAKAAoKTRYJSQBDAgABNQAFFAcIEgAIAOgbAA==.Jotaro:BAAANQADCgUIBQAAAA==.',
Ju='Juggernåut:BAAANQADCgMIAwAAAA==.',
Ka='Kaale:BAAANQAECgQIBQABNQAECgYIFwAUAC0iAA==.Kadaffy:BAAANQAECgEIAQAAAA==.Kahoa:BAAANQAECgQIBAAAAA==.Kakuta:BAABNQAECn9BAAMKAAoKliFWDQBfAwAKAAoKliFWDQBfAwAQAAoKlw8/cADbAQAAAA==.Kakutæ:BAAANQAECggIDAABNQAECgoKQQAKAJYhAA==.Kalru:BAAANQADCgYIAwAAAA==.Kargar:BAAANQAECgEJAgAAAA==.Karot:BAAANQAECgUIDAAAAA==.Katharsis:BAABNQAECn8qAAIQAAoKpBjodQBBAgAQAAoKpBjodQBBAgAAAA==.',
Ke='Keba:BAAANQAECgIIAgABNQAFFAcIEgAKAAgYAA==.Keit:BAEANQADCgUIBQABNQAFFAUIDQALAIIWAA==.Keévs:BAAANQADCgUIBQAAAA==.',
Kh='Khalidisi:BAABNQAECn8bAAIKAAgK3BzPKwC4AgAKAAgK3BzPKwC4AgAAAA==.Khalizar:BAAANQADCgUIBQAAAA==.Khanna:BAAANQADCgIIAgAAAA==.Khenja:BAAANQADCgUIBQAAAA==.',
Ki='Killinthyme:BAAANQADCgYIBgAAAA==.',
Kk='Kkiilleerr:BAAANQAECgQIBAAAAA==.',
Ko='Korath:BAAANQABCgIIAgAAAA==.Korbulo:BAAANQAECgUIBwAAAA==.Korlothel:BAAANQAECgEIAgABNQAECgoKKAAGAI8XAA==.',
Kr='Kriptos:BAAANQADCgEIAQABNQAECgYIAgAHAAAAAA==.Kronu:BAAANQADCgcIBgAAAA==.Krumpus:BAAANQAECgEIAgAAAA==.Kryma:BAAANQAECgMIAwAAAA==.',
Ku='Kungfuuy:BAAANQAECgEIAQAAAA==.',
Ky='Kylogos:BAAANQAECgEIAQAAAA==.Kynsong:BAABNQAECn8qAAMOAAoKSRN7TgDpAQAOAAoKSRN7TgDpAQAdAAEKJAHzNAAHAAAAAA==.Kysia:BAAANQAECgUICgABNQAFFAMICwAQAC0PAA==.',
['Ké']='Kéévály:BAAANQADCgcIBgAAAA==.',
['Kî']='Kîrah:BAACNQAFFH8GAAIOAAQKxxhfGAAeAQAOAAQKxxhfGAAeAQA1AAQKfyQAAg4ACQrdIbEZAA4DAA4ACQrdIbEZAA4DAAAA.',
La='Larcine:BAAANQAECgEIAQABNQAECggIGQAcAJwOAA==.Lav:BAEANQAECgMIAwAAAA==.',
Le='Lerazal:BAABNQAECn8WAAIfAAoKIRUnEwAdAgAfAAoKIRUnEwAdAgAAAA==.Leshah:BAAANQADCggICwAAAA==.',
Li='Liir:BAAANQAECgUIBQAAAA==.Lilbilly:BAAANQAECgEIAwAAAA==.Lildh:BAABNQAECn8jAAIgAAkK1REYCgCmAQAgAAkK1REYCgCmAQAAAA==.Lilypetal:BAAANQAECgcICwAAAA==.Liyi:BAAANQAECgUIBgAAAA==.',
Lo='Lorastyrell:BAAANQAECgEIAgAAAA==.Loughalnan:BAAANQADCgQIBAABNQAECgoKNQAGAGIhAA==.Loìsbethe:BAAANQAECgQIBgAAAA==.',
Lu='Luciferra:BAABNQAECn87AAIOAAoK7h+3GQAOAwAOAAoK7h+3GQAOAwABNQAFFAcIEgAIAOgbAA==.Luu:BAAANQAECgMIBgABNQAECgoKKwAKAHcPAA==.',
Ly='Lytho:BAAANQAECgUICAAAAA==.',
Ma='Madomi:BAAANQAECgMIBAABNQAECgoKOgAGAEkbAA==.Maetromundo:BAAANQADCgcICwAAAA==.Magelock:BAAANQAECgIIAwABNQAECgQICAAHAAAAAA==.Magickul:BAAANQAECgYIAgABNQAECgQICAAHAAAAAA==.Malabooty:BAAANQAECgQIBAABNQAECgoKJwAUAA4XAA==.Malakii:BAAANQADCgEIAQAAAA==.Maletsy:BAAANQAECgYIEQABNQAECgoKOgAGAEkbAA==.Maliboo:BAABNQAECn8nAAMUAAoKDhcrEgCMAgAUAAoKDhcrEgCMAgAFAAMKKAjMmAB2AAAAAA==.Mandalor:BAAANQADCgEIAQAAAA==.Maxamus:BAABNQAECn81AAMRAAoKXCHyIwApAwARAAoKXCHyIwApAwAYAAEK2SEmJwBgAAAAAA==.',
Mc='Mceuan:BAAANQADCgIIAgAAAA==.',
Me='Medarisa:BAABNQAECn8aAAIcAAUKyw6LrQDlAAAcAAUKyw6LrQDlAAAAAA==.Mederia:BAAANQADCgEIAQAAAA==.Medívh:BAAANQAECgUICgAAAA==.Meelly:BAAANQADCgQIBAAAAA==.Melisandr:BAAANQADCgUIBQAAAA==.Merkenier:BAABNQAECn8jAAMFAAoKIQoNOAA/AQAFAAoKIQoNOAA/AQATAAEKAABwiAAAAAAAAA==.Merkshamalot:BAAANQAECgIIBgABNQAECgoKIwAFACEKAA==.Merkur:BAAANQAECgEIAwABNQAECgoKIwAFACEKAA==.Merkurry:BAAANQAECgEIBAABNQAECgoKIwAFACEKAA==.',
Mi='Mieks:BAAANQAECgUICgAAAA==.Milloge:BAAANQAECggICAABNQAECgoKRAAbAFcjAA==.Missmayhem:BAAANQAECgUIEQAAAA==.',
Mo='Modifiedmix:BAAANQAECgEIAQAAAA==.Monatazumaa:BAAANQADCggIDwAAAA==.Monkeyfudge:BAAANQADCgUIBQAAAA==.Moonfalls:BAAANQAECgMIBQABNQAECggIIAAOACcZAA==.',
Mt='Mtghazzard:BAAANQAECgUIBQAAAA==.',
Mu='Mugato:BAAANQAECgEIAQAAAA==.Murdette:BAAANQAECgUIBwABNQAECgkJJgARAJQjAA==.',
My='Mystych:BAABNQAECn8cAAMSAAkKIRC6BQDeAQASAAkKIRC6BQDeAQAGAAEKAADJWgEAAAAAAA==.',
['Må']='Mågi:BAAANQAECgQICAAAAA==.',
['Mé']='Méabh:BAAANQAECgIIAQABNQAECgYIEgAHAAAAAA==.',
['Mö']='Möôôöõöóòòõô:BAABNQAECn87AAMKAAoKwxQ/YAD3AQAKAAoKwxQ/YAD3AQAQAAUKYA62HQHtAAAAAA==.',
Na='Nakednwasted:BAAANQADCgYIBgAAAA==.Nanakii:BAAANQAECgIJAwAAAA==.Nathrold:BAAANQAECgUICwABNQAECgoKFgABAE4SAA==.',
Ne='Necos:BAAANQADCgYICgAAAA==.Neptune:BAACNQAFFH8SAAIIAAcK6BtrBABLAgAIAAcK6BtrBABLAgA1AAQKf0QAAwgACgoBJY8FALUDAAgACgoBJY8FALUDAAQAAQptDJDtADoAAAAA.Nerfpaladins:BAAANQAECgUIBgAAAA==.Nerfpriests:BAABNQAECn8ZAAIPAAgKORSmIwAVAgAPAAgKORSmIwAVAgAAAA==.Nerissl:BAAANQADCgIIAgAAAA==.',
Ni='Niemwa:BAAANQADCgQIBAAAAA==.Nightbird:BAABNQAECn8YAAIhAAkKYxPTMAAlAgAhAAkKYxPTMAAlAgAAAA==.Nightwingqt:BAAANQAECggIDwAAAA==.Nimrock:BAAANQABCgIIAgAAAA==.Ninediewatt:BAAANQADCgcIEAAAAA==.',
['Nè']='Nèo:BAAANQADCgYIEAAAAA==.',
Ob='Obsaedia:BAAANQAECgcIEgABNQAECggIJAAHAAAAAQ==.',
Oc='Oculo:BAAANQAECgEIAwAAAA==.',
Od='Odysseus:BAABNQAECn8XAAMVAAoKZBUNFAC7AQAVAAgKWRYNFAC7AQAEAAQK0Aq9pwCjAAAAAA==.',
Ok='Oktobra:BAABNQAECn8UAAIQAAcKigIlTQGlAAAQAAcKigIlTQGlAAAAAA==.',
On='Onos:BAAANQADCggJCAAAAA==.',
Or='Orillin:BAABNQAECn9EAAMbAAoKVyPKBgAxAwAbAAoKVyPKBgAxAwAaAAIKdg+yygBXAAAAAA==.Orioan:BAABNQAECn8qAAMQAAkKeiAPRgDCAgAQAAkKeiAPRgDCAgAKAAIKMQ0M0ABlAAAAAA==.',
Os='Osÿrus:BAAANQADCgQIBAAAAA==.',
Ou='Ouroboro:BAAANQAECgQIBAAAAA==.',
Pa='Padcadaver:BAAANQAECgEIAgAAAA==.Paddy:BAAANQAECgYIEwAAAA==.Padeönwë:BAAANQAECgEIAgAAAA==.Padraig:BAAANQAECgEIAgAAAA==.Padspectre:BAAANQAECgEIAgAAAA==.Padtipsy:BAAANQAECgEIAgAAAA==.Padvici:BAAANQAECgEIAgAAAA==.Palantyr:BAACNQAFFH8HAAIEAAQKBA2MHADcAAAEAAQKBA2MHADcAAA1AAQKf2wAAgQACgpsICcTAMcCAAQACgpsICcTAMcCAAAA.Pallytings:BAAANQADCgQIBAAAAA==.Panurita:BAABNQAECn8yAAIIAAoKcB0AIACoAgAIAAoKcB0AIACoAgAAAA==.',
Pe='Pellidillion:BAAANQADCgcICwAAAA==.Pepas:BAAANQAECggIDQAAAA==.',
Pi='Picard:BAAANQAECgEIAwAAAA==.',
Po='Polgára:BAAANQAECgIIAgAAAA==.',
Pr='Prepotente:BAAANQADCgUIBQABNQAECgkJIwAFAPUOAA==.',
Pu='Puppysmacks:BAAANQAECgEIAQABNQAECgEIAgAHAAAAAA==.Purity:BAAANQAECgMIAwAAAA==.',
Qe='Qevelana:BAAANQADCgMIBAAAAA==.',
Qu='Quetzalcoatl:BAAANQADCgUICQAAAA==.',
Ra='Raambox:BAABNQAECn80AAIRAAoKaQ5FXgDQAQARAAoKaQ5FXgDQAQAAAA==.Raddish:BAABNQAECn8VAAIOAAcKYQ3PqwATAQAOAAcKYQ3PqwATAQAAAA==.Raedl:BAAANQAECgYIDAAAAA==.Ragriefy:BAAANQADCgUIBQAAAA==.Raiinn:BAAANQADCgEIAQAAAA==.Ramantu:BAAANQADCgIJAgAAAA==.Ramranch:BAAANQAECgQIBgABNQAECgoKLAAIAPEcAA==.Randay:BAAANQAECggIDgAAAA==.Rathix:BAAANQABCgIIAQAAAA==.Raylee:BAAANQAECgQIBAAAAA==.Razuki:BAAANQAECgYIDAAAAA==.',
Re='Reeker:BAAANQAECgEIAQAAAA==.Retton:BAAANQAECgYICAABNQAECgYIFwAUAC0iAA==.Revenge:BAABNQAECn9nAAIQAAoKFyV1CgBHAwAQAAoKFyV1CgBHAwAAAA==.',
Rh='Rhovanion:BAAANQADCgUIBQABNQAFFAQICQAZALAFAA==.Rhuac:BAAANQADCggICgAAAA==.',
Ri='Riddik:BAAANQADCggIDQAAAA==.Rifle:BAAANQAECgQICgABNQAECgoKOAAEAIMTAA==.Rika:BAAANQAECgYIDAAAAA==.Risakah:BAAANQAECggICAAAAA==.',
Ro='Robo:BAAANQABCggIGgAAAA==.Robolich:BAABNQAECn8eAAIZAAoKCiGwFABbAgAZAAoKCiGwFABbAgAAAA==.Rosefist:BAEANQAECgUIBgAAAA==.Rosemourne:BAEANQADCggICAABNQAECgUIBgAHAAAAAA==.Roshwyn:BAABNQAECn8UAAIGAAUKjweg/wCYAAAGAAUKjweg/wCYAAAAAA==.Rottedmeat:BAAANQAECggIDAAAAA==.',
Ru='Rubmytotems:BAABNQAECn8eAAMIAAkK6BQwUQC2AQAIAAkK6BQwUQC2AQAEAAEKAAABPwEuAAAAAA==.Ruckus:BAABNQAECn8xAAIQAAoKwhjjbgBSAgAQAAoKwhjjbgBSAgAAAA==.',
Rx='Rxmblock:BAAANQAECgEIAgAAAA==.Rxmboxx:BAAANQADCgIIAgAAAA==.',
Sa='Saelin:BAAANQAECgcIDAABNQAECgYIFwAUAC0iAA==.Saintquake:BAAANQAECgQIBAAAAA==.Sareenastar:BAABNQAECn8oAAIOAAoKMSWVEwAwAwAOAAoKMSWVEwAwAwAAAA==.',
Sc='Scarless:BAAANQADCggICwAAAA==.',
Se='Seafood:BAAANQAECggIEAAAAA==.Sennara:BAAANQAECgcIDwAAAA==.Sephiróth:BAAANQAECgIIAQAAAA==.Serenitynow:BAAANQADCgYICAAAAA==.Sethworgen:BAAANQAECgEIAQAAAA==.',
Sh='Shadowlillee:BAAANQAECgIIAgAAAA==.Shadowmeteor:BAACNQAFFH8PAAIPAAUKjBkdCAD7AAAPAAUKjBkdCAD7AAA1AAQKfxoAAg8ACgo+HRYJAMMCAA8ACgo+HRYJAMMCAAAA.Shakey:BAAANQAECgEIAQAAAA==.Shalen:BAAANQAECggIDgAAAA==.Shamrox:BAAANQAECgYIDAAAAA==.Sharar:BAAANQAECgUICQAAAA==.Sharker:BAAANQADCgMIAwAAAA==.Sharkerprest:BAAANQADCgYIBgAAAA==.Sharkerwarlo:BAAANQAECgEJAQAAAA==.Sharpenator:BAAANQAECgQIAwAAAA==.Sheraa:BAAANQAECgUICgAAAA==.Shieldknight:BAAANQAECgYICQAAAA==.Shiftystrike:BAABNQAECn8aAAIXAAcKnB2xDADmAQAXAAcKnB2xDADmAQAAAA==.Shifushield:BAAANQADCggIEQAAAA==.Shirazormu:BAAANQAECgEIAgABNQAECgUIBQAHAAAAAA==.Shrike:BAAANQADCgYICgABNQAFFAgIGQAPALoQAA==.',
Si='Silentwindy:BAAANQAECgEIAQAAAA==.Silmarkthree:BAABNQAECn8hAAIJAAoKmw2zxAD7AQAJAAoKmw2zxAD7AQAAAA==.Sinbåd:BAAANQAECgMIAwAAAA==.',
Sk='Skol:BAACNQAFFH8JAAIZAAQKsAU8GgCMAAAZAAQKsAU8GgCMAAA1AAQKfygAAhkACQoaELZbAIMBABkACQoaELZbAIMBAAAA.',
Sl='Slipknoth:BAACNQAFFH8dAAMPAAcK0RcLBQDxAQAPAAcK0RcLBQDxAQAOAAYKxxDSDAC9AQA1AAQKf0wABA8ACgq4JPECAFADAA8ACgq4JPECAFADAA4ABAriFKOzALYAAB0AAwrBD7IQAGwAAAAA.',
Sn='Snakeplizken:BAAANQADCggIAQAAAA==.',
So='Sorean:BAACNQAFFH8XAAISAAYKehxeAABaAQASAAYKehxeAABaAQA1AAQKfzgAAxIACgqnIg0BACIDABIACgqnIg0BACIDAA0AAQpjDdGJADUAAAAA.Sorrel:BAAANQADCggIFAAAAA==.',
Sp='Specialmove:BAAANQAECgYICwAAAA==.',
St='Stabby:BAAANQAECggIBgAAAA==.Staghealz:BAAANQAECgEIAwAAAA==.Starlet:BAAANQADCgIIAgAAAA==.Starlune:BAAANQAECgQIBQAAAA==.Stifs:BAABNQAECn8oAAIDAAoKLxPyFwCiAQADAAoKLxPyFwCiAQAAAA==.Stinkinglily:BAAANQABCgQIBwAAAA==.Stonebeard:BAAANQADCggIIQAAAA==.Stormstream:BAAANQADCgMICQAAAA==.',
Su='Suelustra:BAABNQAECn8ZAAIcAAgKnA5SdQBmAQAcAAgKnA5SdQBmAQAAAA==.Surená:BAAANQAECgcICAAAAA==.',
Sy='Sykotyk:BAABNQAECn8lAAIIAAoKjBbJOgB0AgAIAAoKjBbJOgB0AgAAAA==.',
Ta='Tadagain:BAAANQAECgcIEwAAAA==.Talix:BAAANQAECgIIBAAAAA==.Tamaira:BAAANQAECgUICwAAAA==.Tankybears:BAABNQAECn8XAAMUAAYKLSIMJwDpAQAUAAYKLSIMJwDpAQAFAAQKfBPacwD7AAAAAA==.Tanthirria:BAAANQADCgQIBAAAAA==.Tart:BAAANQAECgYIDgAAAA==.',
Te='Telekinesis:BAABNQAECn8hAAQGAAkKvBMXeQAdAgAGAAkKvBMXeQAdAgANAAYKwAYYTAAEAQASAAEKAADNEwAxAAAAAA==.Tenara:BAABNQAECn8kAAMIAAoK3x62PABtAgAIAAoK3x62PABtAgAEAAQKqw6O+wCbAAABNQAECgYIFwAUAC0iAA==.Teos:BAAANQADCgYIBgABNQAFFAQICQAZALAFAA==.',
Th='Thalanor:BAAANQAECgEIAQAAAA==.Thaliak:BAAANQADCgYIBwABNQAECgQICAAHAAAAAA==.Tharad:BAAANQAECgQIAgABNQAECgcIDwAHAAAAAA==.Tharris:BAAANQADCgYIBgAAAA==.Tholin:BAAANQADCggIEwAAAA==.Thunderlily:BAABNQAECn8nAAMJAAkKfAjonABYAQAJAAkKPQjonABYAQAiAAEKvQZURwA1AAAAAA==.',
Ti='Timcol:BAAANQAECgIIAgABNQAECggICAAHAAAAAA==.Tinychaos:BAAANQAECgUIBQAAAA==.Tirra:BAAANQADCggIDgAAAA==.',
Tr='Tracther:BAAANQADCgYIDwAAAA==.Trapps:BAAANQADCgYIDAAAAA==.Treedemon:BAAANQADCgYIBgAAAA==.Treelock:BAABNQAECn8WAAIcAAkKmhhOcAAOAgAcAAkKmhhOcAAOAgAAAA==.Trelapin:BAAANQADCggIDQAAAA==.',
Tw='Twinrova:BAAANQADCggICAAAAA==.',
Ty='Tybearon:BAAANQADCgYIBwAAAA==.Tyinthus:BAAANQAECggICAAAAA==.Tyrelitha:BAAANQADCgQIBgAAAA==.',
Ug='Ugdeth:BAAANQAECggICQABNQAFFAQIBwAjAE0MAA==.',
Uh='Uhtrad:BAABNQAECn8bAAIDAAoKnQ4PLQB1AQADAAoKnQ4PLQB1AQAAAA==.Uhura:BAAANQADCgYIBgAAAA==.',
Ul='Ulfrir:BAAANQAECgQIBQAAAA==.Ullhr:BAAANQADCgYICwAAAA==.Ultradukes:BAAANQADCgEIAQAAAA==.Ultralord:BAAANQADCgQIBAAAAA==.',
Un='Unleashed:BAAANQAECgEIAQAAAA==.',
Ur='Ursaline:BAAANQAECgEIAQABNQAECgcIDQAHAAAAAA==.',
Va='Valock:BAABNQAECn8ZAAIcAAcKEwWNtgDSAAAcAAcKEwWNtgDSAAAAAA==.Vanshifty:BAABNQAECn9GAAIUAAoKkR5DEQDJAgAUAAoKkR5DEQDJAgAAAA==.',
Ve='Venli:BAAANQAECgMIBQAAAA==.',
Vo='Voidentine:BAAANQABCggIBgAAAA==.',
Vy='Vyx:BAAANQAECgIIBQAAAA==.',
Wa='Waffle:BAABNQAECn8dAAIGAAkKkhHlhwCMAQAGAAkKkhHlhwCMAQAAAA==.Wardaelos:BAAANQADCggIIAAAAA==.Wargue:BAABNQAECn8cAAMYAAkKJRFuDwBsAQAYAAcKNhNuDwBsAQARAAYKQgjD7gAEAQAAAA==.Wasprepared:BAAANQADCgQIBAAAAA==.Watson:BAAANQAECgYICQABNQAECgcIDwAHAAAAAA==.',
We='Weeaboos:BAAANQADCgQICgAAAA==.Welindis:BAAANQADCgcJBwABNQAECgMIBgAHAAAAAA==.Wenus:BAAANQABCgQIAwAAAA==.',
Wh='Whofurmoover:BAAANQAECgQICQAAAA==.',
Wi='Winrodan:BAABNQAECn8eAAIDAAkKOyJ0FQBVAgADAAkKOyJ0FQBVAgABNQAECgkJHgADADsiAA==.Wizzard:BAAANQAECggIJAAAAQ==.',
['Wó']='Wóof:BAAANQADCgMIAwAAAA==.',
Xa='Xaandu:BAAANQADCgQIBAAAAA==.Xaris:BAABNQAECn8mAAIjAAkK9xIhEwC8AQAjAAkK9xIhEwC8AQABNQAECgoKKgAOAEkTAA==.',
Xi='Xiladin:BAAANQAECgMIBwAAAA==.',
Xt='Xtremes:BAAANQADCgcIBwAAAA==.',
['Xí']='Xíe:BAABNQAECn8aAAIeAAgKxREdFwC6AQAeAAgKxREdFwC6AQAAAA==.',
Yi='Yimm:BAAANQADCgEIAQAAAA==.',
Yo='Yourdadsadad:BAAANQAECgUIBQABNQAFFAgIFQARABofAA==.',
['Yø']='Yø:BAAANQAECgQIBAAAAA==.',
Za='Zalendria:BAAANQAECgEIAQAAAA==.',
Zb='Zbm:BAAANQAECgIJAgAAAA==.',
Ze='Zealotry:BAAANQAECgEIAQABNQAECgMIAwAHAAAAAA==.Zeldy:BAABNQAECn80AAIGAAoKqhrDNgDGAgAGAAoKqhrDNgDGAgAAAA==.Zelene:BAAANQAECgEIAQAAAA==.Zenthareal:BAABNQAECn8rAAMkAAkK0RXCLQDUAQAkAAkK0RXCLQDUAQALAAEKYwjglAAyAAAAAA==.Zenzi:BAAANQAECgMIAwAAAA==.',
Zm='Zmaster:BAAANQAECgUIEAAAAA==.',
Zu='Zunarri:BAAANQADCgYICAABNQAFFAMIBQAGAJkaAA==.Zunnari:BAAANQAECgQIBAABNQAFFAMIBQAGAJkaAA==.',
Zw='Zwar:BAAANQADCgMJAwABNQAECgUIEAAHAAAAAA==.',
Zy='Zyri:BAAANQAECgEIAQAAAA==.',
['Ða']='Ðark:BAABNQAECn9AAAIGAAoKhh9lHQAiAwAGAAoKhh9lHQAiAwAAAA==.',
['Ðr']='Ðr:BAAANQAECggIDAAAAA==.',
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
