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

local lookup = {'Warlock-Affliction','Warlock-Destruction','Paladin-Protection','Shaman-Elemental','Druid-Balance','Hunter-BeastMastery','Unknown-Unknown','Shaman-Restoration','Mage-Arcane','Paladin-Holy','DemonHunter-Havoc','Monk-Windwalker','DemonHunter-Vengeance','Hunter-Marksmanship','Hunter-Survival','Priest-Holy','Priest-Shadow','Paladin-Retribution','Druid-Restoration','Warrior-Arms','Druid-Guardian','Shaman-Enhancement','Monk-Brewmaster','Druid-Feral','Warrior-Fury','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Demonology','Priest-Discipline','Warrior-Protection','Evoker-Devastation','Rogue-Subtlety','Mage-Frost','Monk-Mistweaver','DemonHunter-Devourer',}
local provider = {region='US',realm='Dawnbringer',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abdalhazred:BAACNQAFFH8SAAIBAAcK4R7hAACtAQABAAcK4R7hAACtAQA1AAQKfz8AAwEACgqLIxoBAGEDAAEACgqLIxoBAGEDAAIAAgqsGTdMAJsAAAAA.Abilus:BAABNQAECn8qAAIDAAYKehnhLQBvAQADAAYKehnhLQBvAQAAAA==.Abolis:BAABNQAECn8gAAIEAAYKeAwZnQDNAAAEAAYKeAwZnQDNAAAAAA==.',
Ad='Adarlan:BAAANQAECgIIAgAAAA==.Adolin:BAAANQAECgYIBwAAAA==.',
Ae='Aelianna:BAAANQAECgQICQAAAA==.',
Ah='Ahqwanken:BAAANQADCgMIBgAAAA==.',
Ai='Aintnowei:BAAANQAECgQIBAAAAA==.',
Al='Allina:BAAANQADCgYIBgAAAA==.Alnara:BAAANQAECgUICwAAAA==.',
Am='Amoradis:BAAANQADCgcIDwAAAA==.',
An='Anarran:BAAANQAECgIIAgABNQAECgoKJgAFAPwOAA==.Animalfury:BAABNQAECn9CAAIFAAgKYAzFMwBvAQAFAAgKYAzFMwBvAQAAAA==.Anthestria:BAAANQAECgQIBwAAAA==.',
Aq='Aqurala:BAABNQAECn84AAIGAAoKYiFkFgBBAwAGAAoKYiFkFgBBAwAAAA==.',
Ar='Arasham:BAAANQAECgQIBAABNQAECgoKKAAGAI8XAA==.Aravenn:BAABNQAECn8oAAIGAAoKjxdqeAAeAgAGAAoKjxdqeAAeAgAAAA==.Arionaa:BAAANQABCgIIAgAAAA==.Arkangel:BAAANQADCgYIBgABNQAECggIAQAHAAAAAA==.Artemesia:BAAANQAECgYICgABNQAFFAcIEgAIAOgbAA==.Artison:BAAANQAECgIIAgABNQAECgoKIAAJAEYTAA==.',
As='Ashiru:BAAANQADCgMIBQAAAA==.Assandra:BAAANQADCgUIBQAAAA==.',
At='Ateup:BAAANQADCgQJBQABNQAECgUICwAHAAAAAA==.Athenos:BAAANQAECgMIAQABNQAECggIAgAHAAAAAA==.Atlás:BAAANQAECgUIBwAAAA==.',
Au='Aurum:BAABNQAECn8ZAAIKAAkKghExeQCtAQAKAAkKghExeQCtAQAAAA==.',
Av='Avatartele:BAABNQAECn9MAAIEAAoKqhl8KQA6AgAEAAoKqhl8KQA6AgAAAA==.Avatartouka:BAABNQAECn9kAAMIAAoK3iTsAwDkAwAIAAoK3iTsAwDkAwAEAAkK8R1+JgBMAgAAAA==.Avrala:BAAANQADCgIJAgAAAA==.Avraria:BAABNQAECn8XAAILAAkKkAj0RwAOAQALAAkKkAj0RwAOAQAAAA==.Avylastral:BAAANQAECgIIAgAAAA==.',
Az='Azshaxa:BAACNQAFFH8VAAIMAAUKqhcwCgAlAQAMAAUKqhcwCgAlAQA1AAQKfy0AAgwACgr1G14ZAHkCAAwACgr1G14ZAHkCAAAA.',
['Aí']='Aísling:BAABNQAECn8aAAINAAcKUhMoEgCNAQANAAcKUhMoEgCNAQAAAA==.',
Ba='Bagador:BAACNQAFFH8GAAIOAAMKoQM6FwCaAAAOAAMKoQM6FwCaAAA1AAQKfy8AAw4ACgqgFQsTABICAA4ACgqgFQsTABICAA8AAQrYC/sSAEYAAAAA.Banesnarl:BAAANQAECggIAgAAAA==.Barby:BAAANQAECgEIAgAAAA==.Barrs:BAAANQADCgMIAwAAAA==.',
Be='Bearbuthealz:BAAANQAECgIIAgAAAA==.Bearforcewon:BAAANQAECgYIBgAAAA==.Beautifulluv:BAABNQAECn8qAAMQAAoKnBf1PQBDAgAQAAoKnBf1PQBDAgARAAcKjgqYQAArAQAAAA==.Bekabeka:BAACNQAFFH8SAAIKAAcKCBhfBgAtAgAKAAcKCBhfBgAtAgA1AAQKf0gAAwoACgpHIIYZABIDAAoACgpHIIYZABIDABIAAQqJDXSSATgAAAAA.Bekabekabeka:BAAANQABCggJAQABNQAFFAcIEgAKAAgYAA==.Belfour:BAAANQADCgQIBAAAAA==.Bera:BAAANQAECggIAwAAAA==.',
Bi='Billybobjr:BAABNQAECn8sAAIIAAoK8RwhPwAYAgAIAAoK8RwhPwAYAgAAAA==.',
Bl='Blackbart:BAAANQADCgQIBAAAAA==.Bloodar:BAAANQAECggICQAAAA==.',
Bo='Bonski:BAABNQAECn8VAAIGAAgK2g80lQCKAQAGAAgK2g80lQCKAQAAAA==.Boomdoom:BAABNQAECn8XAAITAAoKMARXQAAKAQATAAoKMARXQAAKAQAAAA==.Boosterman:BAABNQAECn8kAAMSAAkKlB8dWwCHAgASAAkKlB8dWwCHAgAKAAMKGxiMtwCsAAAAAA==.',
Br='Brakkar:BAAANQAECgMICAAAAA==.Braxxis:BAABNQAECn8WAAIUAAgKJxAMdwCfAQAUAAgKJxAMdwCfAQABNQAFFAcIGAAPABwaAA==.Breadstick:BAABNQAECn8fAAQVAAcKMx1wGADrAQAVAAcKMx1wGADrAQATAAQK6RcVVwCcAAAFAAEKAADrowAAAAAAAA==.Bress:BAAANQADCgYIBgABNQAECgkJHgADADsiAA==.Brihunts:BAACNQAFFH8HAAIGAAMK6RzODwAKAQAGAAMK6RzODwAKAQA1AAQKfxsAAgYACAqKHTSCALUBAAYACAqKHTSCALUBAAAA.Britotems:BAAANQAECgEIAQAAAA==.Brutaal:BAAANQADCgQIBAAAAA==.Bruutaal:BAAANQAECgQICQAAAA==.',
Bu='Bubsydogo:BAAANQADCggICAAAAA==.',
Ca='Cacellice:BAAANQADCggICAAAAA==.Canoodles:BAAANQAECgcICQAAAA==.',
Ce='Celaian:BAAANQAECgUICAABNQAECgQICAAHAAAAAA==.Celpanda:BAAANQAECgQICAAAAA==.',
Ch='Chadee:BAAANQADCggICAABNQAECggIJQAHAAAAAA==.Charybdia:BAAANQADCggJGwAAAA==.Cheesecake:BAABNQAECn8XAAIGAAgKIg85jQDwAQAGAAgKIg85jQDwAQAAAA==.Chidõri:BAABNQAECn8sAAQWAAoKgRfAEQBNAgAWAAkKhhXAEQBNAgAIAAgKTxgZPgAdAgAEAAQKNBQa0wDuAAAAAA==.Chopstix:BAAANQADCgQIBAAAAA==.Chunni:BAABNQAECn8yAAMXAAoKLQzpDQBLAQAXAAoKdQvpDQBLAQAMAAcKxQUAQQAPAQAAAA==.',
Co='Codap:BAAANQADCgEIAQAAAA==.Coolbeard:BAAANQAECgMIAwAAAA==.Cortex:BAAANQAECgYICgABNQAFFAIIBQAYAOsOAA==.',
Cr='Crayonman:BAABNQAECn8uAAIWAAoKeR21CACYAgAWAAoKeR21CACYAgAAAA==.Cronus:BAAANQAECgQICgABNQAECgcIDwAHAAAAAA==.Cruelkitty:BAAANQAECgQIBQAAAA==.',
Cy='Cyralai:BAAANQAECggICAAAAA==.',
Da='Dahlinar:BAAANQAECgUIEQAAAA==.Dalov:BAABNQAECn8iAAMKAAcKSR4RSQBDAgAKAAcKSR4RSQBDAgASAAUK8x0H5QBRAQAAAA==.Damageworg:BAAANQAECgEIAQAAAA==.Dankley:BAABNQAECn8cAAIZAAcKywbnHQDBAAAZAAcKywbnHQDBAAAAAA==.Danystorm:BAAANQADCgcIBwABNQAFFAcIEgAIAOgbAA==.Darkomenz:BAAANQADCgEIAQAAAA==.',
Dd='Ddream:BAAANQADCgEIAQABNQAECggIAgAHAAAAAA==.',
De='Deaddude:BAABNQAECn8oAAIaAAgKvxujLABlAgAaAAgKvxujLABlAgABNQAECgoKGQAEABMXAA==.Deathboi:BAABNQAECn8yAAIbAAoKCRMiGwAMAgAbAAoKCRMiGwAMAgAAAA==.Deathburgur:BAAANQAECggICwAAAA==.Deathcuddles:BAABNQAECn8UAAIcAAcKSgK5hgCWAAAcAAcKSgK5hgCWAAAAAA==.Dedcow:BAABNQAECn8qAAIaAAkK2hmOFwBKAgAaAAkK2hmOFwBKAgAAAA==.',
Di='Diana:BAABNQAECn82AAIGAAoKQAu0awDrAQAGAAoKQAu0awDrAQAAAA==.Dionysus:BAAANQAECggIAQAAAA==.',
Do='Dontjudgemê:BAAANQADCgYJCgAAAA==.Dorcina:BAAANQADCgcICAAAAA==.Dornth:BAAANQAECggIAgAAAA==.Downpour:BAAANQADCgUIBQAAAA==.',
Dr='Dragam:BAAANQAECgQIBAABNQAECgoKJQAdAAYaAA==.Dragonwarrio:BAABNQAECn8rAAIMAAoKER24DwBhAgAMAAoKER24DwBhAgAAAA==.Draltina:BAABNQAECn8XAAICAAkK+wf3IABpAQACAAkK+wf3IABpAQAAAA==.Drazira:BAAANQAECgEIAQAAAA==.Dresstokill:BAAANQADCggJEQAAAA==.Drmonkborg:BAAANQAECgUICwABNQAECgoKLgAQAEsgAA==.Drovis:BAAANQADCgIIAgAAAA==.Druzzlek:BAAANQADCggIEQAAAA==.Drzaius:BAAANQAECggICAAAAA==.',
Du='Dubalnuar:BAAANQADCgUIEAAAAA==.Dubalpally:BAAANQADCgcIDQAAAA==.Dubaltrok:BAAANQADCgYIEgAAAA==.Dudde:BAABNQAECn8ZAAMEAAoKExenNwCYAgAEAAoKExenNwCYAgAWAAIKNAdIMABsAAAAAA==.Dulapin:BAAANQADCgIIAgAAAA==.Duskfu:BAABNQAECn8qAAIMAAoKJh5ADgB5AgAMAAoKJh5ADgB5AgAAAA==.Dustylock:BAABNQAECn8lAAMdAAoKBhq1VABXAgAdAAoKBhq1VABXAgACAAEKzQeAfQAvAAAAAA==.',
Ea='Earthele:BAABNQAECn8bAAMEAAcKLwr4jQDvAAAEAAcKLwr4jQDvAAAIAAIK7QjRCwFQAAAAAA==.',
El='Elderblood:BAAANQADCgYIBgAAAA==.Elfcaster:BAAANQAECgEIAgAAAA==.Elfowl:BAAANQAECgIIAgABNQAECgoKNQAQAIcPAA==.',
Em='Emanonsahi:BAAANQABCgQIBgAAAA==.Emmel:BAAANQADCgcIDQAAAA==.',
Eq='Equeslucis:BAAANQAECggIBAAAAA==.',
Er='Eromir:BAAANQAECgQIBwABNQAECgUICwAHAAAAAA==.Eryi:BAAANQAECgMICQAAAA==.',
Ev='Eviserator:BAAANQADCgYIDAAAAA==.',
Fa='Fable:BAABNQAECn8kAAIKAAkK0BjvQwAEAgAKAAkK0BjvQwAEAgAAAA==.Faegen:BAAANQADCgMIAwAAAA==.Fallumn:BAAANQADCgEIAQAAAA==.Fangytooth:BAAANQADCgYIBgABNQAECgoKLgAWAHkdAA==.Faze:BAAANQAECgUICgAAAA==.',
Fb='Fbitortamilf:BAAANQAECgUICQAAAA==.',
Fe='Fenlian:BAAANQAECgQIBwAAAA==.Feydoria:BAAANQAECgQIBAAAAA==.',
Fi='Firstfira:BAAANQAECgIIAwAAAA==.',
Fr='Frontman:BAABNQAECn8fAAMKAAgKiBllVQAZAgAKAAgKiBllVQAZAgASAAIKjQ0DYwGBAAAAAA==.',
Fu='Funkycolors:BAAANQAECgQIBAABNQAECgoKJQAdAAYaAA==.',
Ga='Gabomonk:BAAANQADCgEIAQABNQAECgIIAgAHAAAAAA==.Gavrael:BAAANQADCgQIBwAAAA==.',
Ge='Genma:BAAANQAECgYIEAAAAA==.Gewch:BAAANQAECgQIBAAAAA==.',
Gi='Gitgudder:BAAANQAECgUIBQAAAA==.',
Gl='Gloçk:BAABNQAECn8WAAMBAAoKThJPCgDUAQABAAoKFBJPCgDUAQAdAAIKaAU9BwFJAAAAAA==.',
Go='Goofy:BAAANQAECggIEwAAAA==.',
Gr='Graeae:BAAANQAECgIIAgAAAA==.Grimaldi:BAABNQAECn8mAAIFAAoK/A4SKQC3AQAFAAoK/A4SKQC3AQAAAA==.Grimvaka:BAAANQADCgYIBwAAAA==.Gripforceone:BAAANQAECggIAQAAAA==.',
Gu='Gunduin:BAABNQAECn87AAIGAAoKSRu/RgBEAgAGAAoKSRu/RgBEAgAAAA==.',
Gw='Gwinden:BAAANQADCgYICwAAAA==.',
Gy='Gyda:BAACNQAFFH8KAAIQAAMKXxyAHwD1AAAQAAMKXxyAHwD1AAA1AAQKf0oAAxAACgrRIQIeAPkCABAACgrRIQIeAPkCAB4AAgoKDKEgAF0AAAAA.Gyuyuki:BAABNQAECn9BAAIEAAoKhA5GSgCsAQAEAAoKhA5GSgCsAQAAAA==.',
['Gó']='Gódofwàr:BAAANQAECgIIAgAAAA==.',
Ha='Haggish:BAAANQAECgQIBwAAAA==.Hakeo:BAEBNQAECn8pAAIfAAkKCiNxCQC1AgAfAAkKCiNxCQC1AgAAAA==.',
He='Heidie:BAAANQAECgUIBgAAAA==.Hermin:BAAANQADCggIDgAAAA==.',
Hi='Hikomosil:BAABNQAECn8WAAIBAAcKiA18CwCzAQABAAcKiA18CwCzAQAAAA==.',
Ho='Holdmybeerz:BAAANQADCgUIBQAAAA==.Homiekissér:BAAANQAECgcICQAAAA==.',
Hu='Hudsonhawk:BAAANQAECgEIAQAAAA==.',
['Hë']='Hëllen:BAAANQADCgIIAgAAAA==.',
['Hú']='Húñtrèss:BAAANQAECgEIAgAAAA==.',
Il='Ilovedaddy:BAAANQADCgIIAgABNQAECgEIAQAHAAAAAA==.',
Im='Imakittycat:BAABNQAECn8tAAITAAoKYB2+FACiAgATAAoKYB2+FACiAgAAAA==.Impared:BAAANQAECgYIBgABNQAECggIEAAHAAAAAA==.',
Is='Isummon:BAAANQADCgEIAQAAAA==.',
Iv='Ivey:BAAANQADCggIDAAAAA==.',
Ja='Jacburton:BAAANQADCgEIAQAAAA==.Jacenne:BAAANQAECgEIAgAAAA==.',
Je='Jenesis:BAABNQAECn9UAAMSAAoK4CPkDQA3AwASAAoK4CPkDQA3AwAKAAEKHgOZMwEkAAAAAA==.Jerkme:BAAANQAECggICgAAAA==.',
Jo='Jondon:BAEANQAECggICAAAAA==.Josephyn:BAABNQAECn8kAAIKAAoKTRYJSQBDAgAKAAoKTRYJSQBDAgABNQAFFAcIEgAIAOgbAA==.Jotaro:BAAANQADCgUIBQAAAA==.',
Ju='Juggernåut:BAAANQADCgMIAwAAAA==.',
Ka='Kaale:BAAANQAECgQIBAABNQAECgcIHwATAPgjAA==.Kahoa:BAAANQAECgQIBAAAAA==.Kakuta:BAABNQAECn9BAAMKAAoKliFWDQBfAwAKAAoKliFWDQBfAwASAAoKlw9zfADUAQAAAA==.Kakutæ:BAAANQAECggIDAABNQAECgoKQQAKAJYhAA==.Kalru:BAAANQADCgYIAwAAAA==.Kargar:BAAANQAECgEJAgAAAA==.Karot:BAAANQAECgUICgAAAA==.Katharsis:BAABNQAECn8qAAISAAoKpBjodQBBAgASAAoKpBjodQBBAgAAAA==.',
Ke='Keba:BAAANQAECgcIBwABNQAFFAcIEgAKAAgYAA==.Keit:BAEANQADCgUIBQABNQAFFAUIEgALAN0aAA==.Keévs:BAAANQADCgUIBQAAAA==.',
Kh='Khalidisi:BAABNQAECn8bAAIKAAgK3BzPKwC4AgAKAAgK3BzPKwC4AgAAAA==.Khalizar:BAAANQADCgUIBQAAAA==.Khanna:BAAANQADCgIIAgAAAA==.Khenja:BAAANQADCgUIBQAAAA==.',
Ki='Killinthyme:BAAANQADCgYIBgAAAA==.',
Kk='Kkiilleerr:BAAANQAECgQIBAAAAA==.',
Ko='Korath:BAAANQABCgIIAgAAAA==.Korbulo:BAAANQAECgUIBwAAAA==.Korlothel:BAAANQABCgIIAgABNQAECgoKKAAGAI8XAA==.',
Kr='Kriptos:BAAANQADCgEIAQABNQAECggIAgAHAAAAAA==.Kronu:BAAANQADCgcIBgAAAA==.Krumpus:BAAANQAECgEIAQAAAA==.Kryma:BAAANQAECgMIAwAAAA==.',
Ku='Kungfuuy:BAAANQADCgQIBgAAAA==.',
Ky='Kylogos:BAAANQAECgEIAQAAAA==.Kynsong:BAABNQAECn8rAAMQAAoKSROqVwDeAQAQAAoKSROqVwDeAQAeAAEKJAHzNAAHAAAAAA==.Kysia:BAAANQAECgUICQABNQAFFAMICwASAC0PAA==.',
['Ké']='Kéévály:BAAANQADCgcIBgAAAA==.',
['Kî']='Kîrah:BAACNQAFFH8GAAIQAAQKxxikGwAVAQAQAAQKxxikGwAVAQA1AAQKfyQAAhAACQrdIbEZAA4DABAACQrdIbEZAA4DAAAA.',
La='Larcine:BAAANQAECgcICAABNQAECggIGQAdAJwOAA==.Lav:BAEANQAECgMIAwAAAA==.',
Le='Lerazal:BAABNQAECn8WAAIgAAoKIRUnEwAdAgAgAAoKIRUnEwAdAgAAAA==.Leshah:BAAANQADCggICwAAAA==.Lexanteus:BAAANQADCgUIBQABNQAECgoKFgAgACEVAA==.',
Li='Liir:BAAANQAECgUIBQAAAA==.Lilbilly:BAAANQAECgEIAQAAAA==.Lildh:BAABNQAECn8jAAINAAkK1RFACwClAQANAAkK1RFACwClAQAAAA==.Lilypetal:BAAANQAECggICwAAAA==.Liyi:BAAANQAECgUIBgAAAA==.',
Lo='Lorastyrell:BAAANQABCgEIAQAAAA==.Loughalnan:BAAANQADCgQIBAABNQAECgoKOAAGAGIhAA==.Loìsbethe:BAAANQAECgQIBgAAAA==.',
Lu='Luciferra:BAABNQAECn9EAAIQAAoK7h+3GQAOAwAQAAoK7h+3GQAOAwABNQAFFAcIEgAIAOgbAA==.Luu:BAAANQAECgMIBAABNQAECgoKNAAKAHcPAA==.',
Ly='Lytho:BAAANQAECgUIBgAAAA==.',
Ma='Madomi:BAAANQAECgMIBAABNQAECgoKOwAGAEkbAA==.Maetromundo:BAAANQADCgcICwAAAA==.Magelock:BAAANQAECgIIAgABNQAECgQIBwAHAAAAAA==.Magickul:BAAANQAECgYIAQABNQAECgQIBwAHAAAAAA==.Malabooty:BAAANQAECgQIBAABNQAECgoKJwATAA4XAA==.Malakii:BAAANQADCgEIAQAAAA==.Maletsy:BAAANQAECgYIEAABNQAECgoKOwAGAEkbAA==.Maliboo:BAABNQAECn8nAAMTAAoKDhcsFACJAgATAAoKDhcsFACJAgAFAAMKKAjMmAB2AAAAAA==.Mandalor:BAAANQADCgEIAQAAAA==.Maxamus:BAABNQAECn82AAMUAAoKXCHyIwApAwAUAAoKXCHyIwApAwAZAAEK2SHnKgBeAAAAAA==.',
Mc='Mceuan:BAAANQADCgIIAgAAAA==.',
Me='Medarisa:BAABNQAECn8aAAIdAAUKyw4AtwDlAAAdAAUKyw4AtwDlAAAAAA==.Mederia:BAAANQADCgEIAQAAAA==.Medívh:BAAANQAECgUIBwAAAA==.Meelly:BAAANQADCgQIBAAAAA==.Melisandr:BAAANQADCgUIBQAAAA==.Merkenier:BAABNQAECn8jAAMFAAoKIQoaPAA+AQAFAAoKIQoaPAA+AQAVAAEKAAAhkAAAAAAAAA==.Merkshamalot:BAAANQAECgIIAgABNQAECgoKIwAFACEKAA==.Merkurry:BAAANQADCgQIBQABNQAECgoKIwAFACEKAA==.',
Mi='Mieks:BAAANQAECgUICgAAAA==.Milloge:BAAANQAECggIEAABNQAECgoKSgAcAHEjAA==.Missmayhem:BAAANQAECgUIEQAAAA==.',
Mo='Modifiedmix:BAAANQAECgEIAQAAAA==.Monatazumaa:BAAANQADCggIDwAAAA==.Monkeyfudge:BAAANQADCgUIBQAAAA==.Moonfalls:BAAANQAECgMICAABNQAECgoKKAAQAIoZAA==.',
Mt='Mtghazzard:BAAANQAECggICAAAAA==.',
Mu='Mugato:BAAANQABCgEIAQAAAA==.Murdette:BAAANQAECgUIBQABNQAECgkJJgAUAJQjAA==.',
My='Mystych:BAABNQAECn8eAAMPAAkKIRBOBgDeAQAPAAkKIRBOBgDeAQAGAAEKAABdaAEAAAAAAA==.',
['Må']='Mågi:BAAANQAECgQICAAAAA==.',
['Mé']='Méabh:BAAANQAECgIIAQABNQAECgcIGgANAFITAA==.',
['Mö']='Möôôöõöóòòõô:BAABNQAECn87AAMKAAoKwxQ/YAD3AQAKAAoKwxQ/YAD3AQASAAUKYA62HQHtAAAAAA==.',
Na='Nakednwasted:BAAANQADCgYIBgAAAA==.Nanakii:BAAANQAECgIJAwAAAA==.Nathrold:BAAANQAECgUICwABNQAECgoKFgABAE4SAA==.',
Ne='Necos:BAAANQADCgYICgAAAA==.Neptune:BAACNQAFFH8SAAIIAAcK6BvVBQBJAgAIAAcK6BvVBQBJAgA1AAQKf0UAAwgACgoBJYcGALEDAAgACgoBJYcGALEDAAQAAQptDMT4ADoAAAAA.Nerfpaladins:BAAANQAECgUIBgAAAA==.Nerfpriests:BAABNQAECn8ZAAIRAAgKORSmIwAVAgARAAgKORSmIwAVAgAAAA==.Nerissl:BAAANQADCgIIAgAAAA==.',
Ni='Niemwa:BAAANQADCgQIBAAAAA==.Nightbird:BAABNQAECn8YAAIhAAkKYxPTNQAkAgAhAAkKYxPTNQAkAgAAAA==.Nightwingqt:BAAANQAECggIDgAAAA==.Nimrock:BAAANQABCgIIAgAAAA==.Ninediewatt:BAAANQADCgcIEAAAAA==.',
['Nè']='Nèo:BAAANQADCgYIEAAAAA==.',
Ob='Obsaedia:BAAANQAECgcIEQABNQAECggIJQAHAAAAAQ==.',
Od='Odysseus:BAABNQAECn8XAAMWAAoKZBW9FQC5AQAWAAgKWRa9FQC5AQAEAAQK0ApDsgCjAAAAAA==.',
Ok='Oktobra:BAABNQAECn8UAAISAAcKigIlTQGlAAASAAcKigIlTQGlAAAAAA==.',
On='Onos:BAAANQADCggJCAAAAA==.',
Or='Orillin:BAABNQAECn9KAAMcAAoKcSP8BgA0AwAcAAoKcSP8BgA0AwAbAAIKdg+yygBXAAAAAA==.Orioan:BAABNQAECn8qAAMSAAkKeiAPRgDCAgASAAkKeiAPRgDCAgAKAAIKMQ0C2wBhAAAAAA==.',
Os='Osÿrus:BAAANQADCgQIBAAAAA==.',
Ou='Ouroboro:BAAANQAECgQIBAAAAA==.',
Pa='Paddy:BAABNQAECn8dAAIIAAgKeRcJQgAMAgAIAAgKeRcJQgAMAgAAAA==.Palantyr:BAACNQAFFH8HAAIEAAQKBA2MHADcAAAEAAQKBA2MHADcAAA1AAQKf20AAgQACgrSIHITAM8CAAQACgrSIHITAM8CAAAA.Pallytings:BAAANQADCgQIBAAAAA==.Panurita:BAABNQAECn8yAAIIAAoKcB2FJwDGAgAIAAoKcB2FJwDGAgAAAA==.',
Pe='Pellidillion:BAAANQADCgcICwAAAA==.Pepas:BAAANQAECggIDQAAAA==.',
Po='Polgára:BAAANQAECgIIAgAAAA==.',
Pr='Prepotente:BAAANQADCgUIBQABNQAECgoKJgAFAPwOAA==.',
Pu='Purity:BAAANQAECgMIAwAAAA==.',
Qe='Qevelana:BAAANQADCgMIBAAAAA==.',
Qu='Quetzalcoatl:BAAANQADCgUICQAAAA==.',
Ra='Raambox:BAABNQAECn80AAIUAAoKaQ5JZgDOAQAUAAoKaQ5JZgDOAQAAAA==.Raddish:BAAANQAECgYIEwAAAA==.Raedl:BAAANQAECgYICwAAAA==.Ragriefy:BAAANQADCgUIBQAAAA==.Raiinn:BAAANQADCgEIAQAAAA==.Ramantu:BAAANQADCgIJAgAAAA==.Ramranch:BAAANQAECgQIBQABNQAECgoKLAAIAPEcAA==.Randay:BAAANQAECggIDQAAAA==.Rathix:BAAANQABCgIIAQAAAA==.Raylee:BAAANQAECgQIAwAAAA==.Razuki:BAAANQAECgYIDAAAAA==.',
Re='Reeker:BAAANQABCgQIAgAAAA==.Remyl:BAAANQAECgUIBQAAAA==.Retton:BAAANQAECgYICAABNQAECgcIHwATAPgjAA==.',
Rh='Rhovanion:BAAANQADCgUIBQABNQAFFAUICgAaALAFAA==.Rhuac:BAAANQADCggICgAAAA==.',
Ri='Riddik:BAAANQADCggIDQAAAA==.Rifle:BAAANQAECgQICQABNQAECgoKOAAEAIMTAA==.Rika:BAAANQAECgYICwAAAA==.Risakah:BAAANQAECggICAAAAA==.',
Ro='Robolich:BAABNQAECn8eAAIaAAoKCiGZFgBUAgAaAAoKCiGZFgBUAgAAAA==.Rosefist:BAEANQAECgUIBQAAAA==.Rosemourne:BAEANQADCggICAABNQAECgUIBQAHAAAAAA==.Roshwyn:BAABNQAECn8ZAAIGAAYK9gdF8ADPAAAGAAYK9gdF8ADPAAAAAA==.Rottedmeat:BAAANQAECggICwAAAA==.',
Ru='Rubmytotems:BAABNQAECn8eAAMIAAkK6BSIWACyAQAIAAkK6BSIWACyAQAEAAEKAAABPwEuAAAAAA==.Ruckus:BAABNQAECn8xAAISAAoKwhjjbgBSAgASAAoKwhjjbgBSAgAAAA==.',
Rx='Rxmblock:BAAANQAECgEIAQAAAA==.Rxmboxx:BAAANQADCgIIAgAAAA==.',
Sa='Saelin:BAAANQAECgcICwABNQAECgcIHwATAPgjAA==.Saintquake:BAAANQAECgQIBAAAAA==.Salinor:BAAANQAECgQIBAAAAA==.Sareenastar:BAABNQAECn8oAAIQAAoKMSWVEwAwAwAQAAoKMSWVEwAwAwAAAA==.',
Sc='Scarless:BAAANQADCggICwAAAA==.',
Se='Seafood:BAAANQAECggIDwAAAA==.Sennara:BAAANQAECgcIDwAAAA==.Sephiróth:BAAANQAECgIIAQAAAA==.Serenitynow:BAAANQADCgYIDAAAAA==.Sethworgen:BAAANQADCggICAAAAA==.',
Sh='Shadowlillee:BAAANQAECgIIAgAAAA==.Shadowmeteor:BAACNQAFFH8TAAIRAAcKcxvjBQBjAQARAAcKcxvjBQBjAQA1AAQKfxoAAhEACgo+Hc8JAMICABEACgo+Hc8JAMICAAAA.Shakey:BAAANQAECgEIAQAAAA==.Shalen:BAAANQAECggIDwAAAA==.Shamrox:BAAANQAECgYICQAAAA==.Sharar:BAAANQAECgUIBwAAAA==.Sharker:BAAANQADCgMIAwAAAA==.Sharkerprest:BAAANQADCgYIBgAAAA==.Sharkerwarlo:BAAANQAECgEJAQAAAA==.Sharpenator:BAAANQAECgQIAwAAAA==.Sheraa:BAAANQAECgYICQAAAA==.Shieldknight:BAAANQAECgYICAAAAA==.Shiftystrike:BAABNQAECn8kAAIYAAgKLB7mCABcAgAYAAgKLB7mCABcAgAAAA==.Shifushield:BAAANQADCggIEQAAAA==.Shirazormu:BAAANQAECgEIAQABNQAECgUIBQAHAAAAAA==.Shrike:BAAANQADCgYICgABNQAFFAkJGwARANMPAA==.',
Si='Silentwindy:BAAANQAECgEIAQAAAA==.Silmarkthree:BAABNQAECn8lAAIJAAoKpQ6zxAD7AQAJAAoKpQ6zxAD7AQAAAA==.Sinbåd:BAAANQAECgMIAwAAAA==.',
Sk='Skol:BAACNQAFFH8KAAIaAAUKsAW4HQCGAAAaAAUKsAW4HQCGAAA1AAQKfygAAhoACQoaELZbAIMBABoACQoaELZbAIMBAAAA.',
Sl='Slipknoth:BAACNQAFFH8dAAMRAAcK0RcLBQDxAQARAAcK0RcLBQDxAQAQAAYKxxBZDwCxAQA1AAQKf04ABBEACgq4JEgDAE8DABEACgq4JEgDAE8DABAABAriFNu8ALQAAB4AAwrBD78RAG0AAAAA.',
Sn='Snakeplizken:BAAANQADCggIAQAAAA==.',
So='Sorean:BAACNQAFFH8YAAIPAAcKHBo/AACpAQAPAAcKHBo/AACpAQA1AAQKfzgAAw8ACgqnIigBAB0DAA8ACgqnIigBAB0DAA4AAQpjDdGJADUAAAAA.Sorrel:BAAANQADCggIFAAAAA==.',
Sp='Specialmove:BAAANQAECgYICQAAAA==.',
St='Stabby:BAAANQAECggIBgAAAA==.Staghealz:BAAANQADCgYICAAAAA==.Starlet:BAAANQADCgIIAgAAAA==.Starlune:BAAANQAECgQIBQAAAA==.Stifs:BAABNQAECn8oAAIDAAoKLxNoGgCfAQADAAoKLxNoGgCfAQAAAA==.Stinkinglily:BAAANQABCgQIBwAAAA==.Stonebeard:BAAANQADCggIIQAAAA==.Stormstream:BAAANQADCgMICQAAAA==.',
Su='Suelustra:BAABNQAECn8ZAAIdAAgKnA6MfgBkAQAdAAgKnA6MfgBkAQAAAA==.Surená:BAAANQAECgcICwAAAA==.',
Sy='Sykotyk:BAABNQAECn8lAAIIAAoKjBbJOgB0AgAIAAoKjBbJOgB0AgAAAA==.',
Ta='Tadagain:BAAANQAECgcIEgAAAA==.Talairn:BAAANQADCgYICgAAAA==.Talix:BAAANQAECgIIAgAAAA==.Tamaira:BAAANQAECgUICQAAAA==.Tankybears:BAABNQAECn8fAAMTAAcK+CMMJwDpAQATAAcK+CMMJwDpAQAFAAQKfBPacwD7AAAAAA==.Tanthirria:BAAANQADCgQIBAAAAA==.Tart:BAAANQAECgUIEgAAAA==.',
Te='Telekinesis:BAABNQAECn8hAAQGAAkKvBMXeQAdAgAGAAkKvBMXeQAdAgAOAAYKwAYYTAAEAQAPAAEKAADNEwAxAAAAAA==.Tenara:BAABNQAECn8kAAMIAAoK3x62PABtAgAIAAoK3x62PABtAgAEAAQKqw6O+wCbAAABNQAECgcIHwATAPgjAA==.Teos:BAAANQADCgYIBgABNQAFFAUICgAaALAFAA==.',
Th='Thalanor:BAAANQABCggIJAAAAA==.Thaliak:BAAANQADCgYIBwABNQAECgQIBwAHAAAAAA==.Tharad:BAAANQAECgQIAgABNQAECgcIDwAHAAAAAA==.Tharris:BAAANQADCgYIBgAAAA==.Tholin:BAAANQADCggIEwAAAA==.Thunderlily:BAABNQAECn8nAAMJAAkKfAg5pgBYAQAJAAkKPQg5pgBYAQAiAAEKvQZURwA1AAAAAA==.',
Ti='Timcol:BAAANQAECgIIAgABNQAECggICAAHAAAAAA==.Tinychaos:BAAANQAECgUIAwAAAA==.Tirra:BAAANQADCggIDgAAAA==.',
Tr='Tracther:BAAANQADCgYIDwAAAA==.Trapps:BAAANQADCgYIDAAAAA==.Treedemon:BAAANQADCgYIBgAAAA==.Treelock:BAABNQAECn8WAAIdAAkKmhhOcAAOAgAdAAkKmhhOcAAOAgAAAA==.Trelapin:BAAANQADCggIDQAAAA==.',
Tw='Twinrova:BAAANQADCggICAAAAA==.',
Ty='Tybearon:BAAANQADCgYIBwAAAA==.Tyinthus:BAAANQAECggICAAAAA==.Tyrelitha:BAAANQADCgQIBgAAAA==.',
Ug='Ugdeth:BAAANQAECggICQABNQAFFAQIBwAjAE0MAA==.',
Uh='Uhtrad:BAABNQAECn8bAAIDAAoKnQ4PLQB1AQADAAoKnQ4PLQB1AQAAAA==.Uhura:BAAANQADCgYIBgAAAA==.',
Ul='Ulfrir:BAAANQAECgQIBQAAAA==.Ullhr:BAAANQADCgYICwAAAA==.Ultradukes:BAAANQADCgEIAQAAAA==.Ultralord:BAAANQADCgQIBAAAAA==.',
Un='Unleashed:BAAANQAECgEIAQAAAA==.',
Ur='Ursaline:BAAANQAECgEIAQABNQAECgcIDQAHAAAAAA==.',
Va='Valock:BAABNQAECn8dAAIdAAcKEwX0vwDRAAAdAAcKEwX0vwDRAAAAAA==.Vanshifty:BAABNQAECn9MAAITAAoKZh9DEQDJAgATAAoKZh9DEQDJAgAAAA==.',
Ve='Venli:BAAANQAECgMIBQAAAA==.',
Vo='Voidentine:BAAANQABCggIBgAAAA==.',
Vy='Vyx:BAAANQAECgIIAwAAAA==.',
Wa='Waffle:BAABNQAECn8dAAIGAAkKkhEelQCLAQAGAAkKkhEelQCLAQAAAA==.Wardaelos:BAAANQADCggIIAAAAA==.Wargue:BAABNQAECn8cAAMZAAkKJREhEQBnAQAZAAcKNhMhEQBnAQAUAAYKQgjD7gAEAQAAAA==.Wasprepared:BAAANQADCgQIBAAAAA==.Watson:BAAANQAECgYICAABNQAECgcIDwAHAAAAAA==.',
We='Weeaboos:BAAANQADCgQICgAAAA==.Welindis:BAAANQADCgcJBwABNQAECgMIBgAHAAAAAA==.Wenus:BAAANQABCgQIAwAAAA==.',
Wh='Whofurmoover:BAAANQAECgQICQAAAA==.',
Wi='Winrodan:BAABNQAECn8eAAIDAAkKOyJ0FQBVAgADAAkKOyJ0FQBVAgABNQAECgkJHgADADsiAA==.Wizzard:BAAANQAECggIJQAAAQ==.',
['Wó']='Wóof:BAAANQADCgMIAwAAAA==.',
Xa='Xaandu:BAAANQADCgQIBAAAAA==.Xaris:BAABNQAECn8qAAIjAAkKDhOPFAC7AQAjAAkKDhOPFAC7AQABNQAECgoKKwAQAEkTAA==.',
Xi='Xiladin:BAAANQAECgMIBwAAAA==.',
Xt='Xtremes:BAAANQADCgcIBwAAAA==.',
['Xí']='Xíe:BAABNQAECn8aAAIfAAgKxREdFwC6AQAfAAgKxREdFwC6AQAAAA==.',
Yi='Yimm:BAAANQADCgEIAQAAAA==.',
Yo='Yourdadsadad:BAAANQAECgUIBQABNQAFFAgIFQAUABofAA==.',
['Yø']='Yø:BAAANQAECgQIBAAAAA==.',
Zb='Zbm:BAAANQAECgIJAgAAAA==.',
Ze='Zeldy:BAABNQAECn82AAIGAAoKqhrDNgDGAgAGAAoKqhrDNgDGAgAAAA==.Zenthareal:BAABNQAECn8rAAMkAAkK0RXCLQDUAQAkAAkK0RXCLQDUAQALAAEKYwjglAAyAAAAAA==.Zenzi:BAAANQAECgMIBQAAAA==.',
Zm='Zmaster:BAAANQAECgUIEAAAAA==.',
Zu='Zunarri:BAAANQADCgYICAABNQAFFAMIBwAGAOkcAA==.Zunnari:BAAANQAECgQIBAABNQAFFAMIBwAGAOkcAA==.',
Zw='Zwar:BAAANQADCgMJAwABNQAECgUIEAAHAAAAAA==.',
Zy='Zyri:BAAANQAECgEIAQAAAA==.',
['Ða']='Ðark:BAABNQAECn9CAAIGAAoK3x9lHQAiAwAGAAoK3x9lHQAiAwAAAA==.',
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
