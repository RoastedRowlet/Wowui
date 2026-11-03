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

local lookup = {'Warlock-Affliction','Warlock-Destruction','Paladin-Protection','Shaman-Elemental','Druid-Balance','Hunter-BeastMastery','Unknown-Unknown','Shaman-Restoration','Paladin-Holy','Monk-Windwalker','Hunter-Marksmanship','Priest-Holy','Priest-Shadow','Paladin-Retribution','Warrior-Arms','Hunter-Survival','Druid-Guardian','Druid-Restoration','Shaman-Enhancement','Monk-Brewmaster','Druid-Feral','Warrior-Fury','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Demonology','Priest-Discipline','Warrior-Protection','DemonHunter-Havoc','Evoker-Devastation','DemonHunter-Vengeance','Rogue-Subtlety','Mage-Arcane','Mage-Frost','Monk-Mistweaver','DemonHunter-Devourer',}
local provider = {region='US',realm='Dawnbringer',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abdalhazred:BAACNQAFFH8RAAIBAAYKwR60AABdAQABAAYKwR60AABdAQA1AAQKfzgAAwEACgqaIhoBAGEDAAEACgqVIhoBAGEDAAIAAgqsGTdMAJsAAAAA.Abilus:BAABNQAECn8nAAIDAAYKehnhLQBvAQADAAYKehnhLQBvAQAAAA==.Abolis:BAABNQAECn8fAAIEAAYKRQsUhgDJAAAEAAYKRQsUhgDJAAAAAA==.',
Ad='Adarlan:BAAANQAECgIIAgAAAA==.Adolin:BAAANQAECgIIAwAAAA==.',
Ae='Aelianna:BAAANQAECgMIBgAAAA==.',
Ah='Ahqwanken:BAAANQADCgMIBgAAAA==.',
Ai='Aintnowei:BAAANQAECgQIBAAAAA==.',
Al='Allina:BAAANQADCgYIBgAAAA==.Alnara:BAAANQAECgUICwAAAA==.',
Am='Amoradis:BAAANQADCgcIDwAAAA==.',
An='Anarran:BAAANQAECgIIAwABNQAECgkJHgAFAEENAA==.Animalfury:BAABNQAECn8vAAIFAAcKwgkuOAAeAQAFAAcKwgkuOAAeAQAAAA==.Anthestria:BAAANQAECgQIBwAAAA==.',
Aq='Aqurala:BAABNQAECn81AAIGAAoKYiFkFgBBAwAGAAoKYiFkFgBBAwAAAA==.',
Ar='Arasham:BAAANQAECgQIBAABNQAECgoKJAAGAI8XAA==.Aravenn:BAABNQAECn8kAAIGAAoKjxdqeAAeAgAGAAoKjxdqeAAeAgAAAA==.Arionaa:BAAANQAECgEIAgAAAA==.Arkangel:BAAANQADCgYIBgABNQAECggIAgAHAAAAAA==.Artemesia:BAAANQAECgYICgABNQAFFAcIEgAIAOgbAA==.Artison:BAAANQAECgIIAgABNQAECgcIEAAHAAAAAA==.',
As='Ashiru:BAAANQADCgMIBQAAAA==.Assandra:BAAANQADCgUIBQAAAA==.',
At='Ateup:BAAANQADCgQJBQABNQAECgUICwAHAAAAAA==.Athenos:BAAANQAECgMIAQABNQAECgYIAgAHAAAAAA==.Atlás:BAAANQAECgUIBwAAAA==.',
Au='Aurum:BAABNQAECn8ZAAIJAAkKghHLXAByAQAJAAkKghHLXAByAQAAAA==.',
Av='Avatartele:BAABNQAECn9HAAIEAAoKMxliIQA7AgAEAAoKMxliIQA7AgAAAA==.Avatartouka:BAABNQAECn9cAAMIAAoK3iSKAgD4AwAIAAoK3iSKAgD4AwAEAAkK8hxBIABCAgAAAA==.Avrala:BAAANQADCgIJAgAAAA==.Avraria:BAAANQAECggIDAAAAA==.Avylastral:BAAANQAECgIIAgAAAA==.',
Ax='Axel:BAAANQAECggIAgAAAA==.',
Az='Azshaxa:BAACNQAFFH8VAAIKAAUKqheKBwDcAAAKAAUKqheKBwDcAAA1AAQKfy0AAgoACgr1G14ZAHkCAAoACgr1G14ZAHkCAAAA.',
['Aí']='Aísling:BAAANQAECgYIEQAAAA==.',
Ba='Bagador:BAACNQAFFH8GAAILAAMKoQM7EACeAAALAAMKoQM7EACeAAA1AAQKfyAAAgsACgoGE+QTAMwBAAsACgoGE+QTAMwBAAAA.Banesnarl:BAAANQAECggIAgAAAA==.Barby:BAAANQAECgEIAQAAAA==.Barrs:BAAANQADCgMIAwAAAA==.',
Be='Bearbuthealz:BAAANQAECgIIAgAAAA==.Beautifulluv:BAABNQAECn8nAAMMAAoK4BZLRADvAQAMAAoK4BZLRADvAQANAAcKjgqYQAArAQAAAA==.Bekabeka:BAACNQAFFH8RAAIJAAYKshcBBgDfAQAJAAYKshcBBgDfAQA1AAQKf0EAAwkACgp4H4YZABIDAAkACgp4H4YZABIDAA4AAQqJDR1hATwAAAAA.Bekabekabeka:BAAANQABCggJAQABNQAFFAYIEQAJALIXAA==.Belfour:BAAANQADCgQIBAAAAA==.Bera:BAAANQAECggIBAAAAA==.',
Bi='Billybobjr:BAABNQAECn8sAAIIAAoK8RwIMQApAgAIAAoK8RwIMQApAgAAAA==.',
Bl='Blackbart:BAAANQADCgQIBAAAAA==.Bloodar:BAAANQAECggICQAAAA==.',
Bo='Bonski:BAAANQAECgYIDwAAAA==.Boomdoom:BAAANQAECgcICwAAAA==.Boosterman:BAABNQAECn8hAAMOAAgKnB4dWwCHAgAOAAgKnB4dWwCHAgAJAAIK/xLczwBMAAAAAA==.',
Br='Brakkar:BAAANQAECgMICAAAAA==.Brandish:BAAANQAECgMIBAAAAA==.Braxxis:BAABNQAECn8VAAIPAAgKJxB5YACkAQAPAAgKJxB5YACkAQABNQAFFAYIFwAQAHocAA==.Breadstick:BAABNQAECn8YAAMRAAcK9BpwGADrAQARAAcK9BpwGADrAQASAAQK6Rc4SQCfAAAAAA==.Bress:BAAANQADCgYIBgABNQAECgkJHgADADsiAA==.Brihunts:BAABNQAECn8WAAIGAAgKJh0eagCmAQAGAAgKJh0eagCmAQAAAA==.Britotems:BAAANQAECgEIAQAAAA==.Brutaal:BAAANQADCgQJBAAAAA==.Bruutaal:BAAANQAECgMIBgAAAA==.',
Bu='Bubsydogo:BAAANQADCggICAAAAA==.',
Ca='Cacellice:BAAANQADCggICAAAAA==.Canoodles:BAAANQAECgcICQAAAA==.',
Ce='Celaian:BAAANQAECgUICAABNQAECgQICAAHAAAAAA==.Celpanda:BAAANQAECgQICAAAAA==.',
Ch='Chadee:BAAANQADCggICAABNQAECggIIAAHAAAAAA==.Charybdia:BAAANQADCggJGwAAAA==.Cheesecake:BAABNQAECn8XAAIGAAgKIg85jQDwAQAGAAgKIg85jQDwAQAAAA==.Chidõri:BAABNQAECn8qAAQTAAoKgRfAEQBNAgATAAkKhhXAEQBNAgAIAAcK4xb0RADNAQAEAAQKNBQa0wDuAAAAAA==.Chopstix:BAAANQADCgQIBAAAAA==.Chunni:BAABNQAECn8uAAMUAAoKWAu4CwBFAQAUAAoKoAq4CwBFAQAKAAcKxQUAQQAPAQAAAA==.Chöpper:BAAANQAECgIIAQAAAA==.',
Co='Codap:BAAANQADCgEIAQAAAA==.Coolbeard:BAAANQAECgMIBgAAAA==.Cortex:BAAANQAECgYICgABNQAECgoKJgAVABcdAA==.',
Cr='Crayonman:BAABNQAECn8qAAITAAoKOByTBwCHAgATAAoKOByTBwCHAgAAAA==.Cronus:BAAANQAECgQIDAABNQAECgcIDwAHAAAAAA==.Cruelkitty:BAAANQAECgQIBQAAAA==.',
Cy='Cyralai:BAAANQAECggICgAAAA==.',
Da='Dahlinar:BAAANQAECgQIDAAAAA==.Dalov:BAABNQAECn8iAAMJAAcKSR4RSQBDAgAJAAcKSR4RSQBDAgAOAAUK8x0H5QBRAQAAAA==.Damageworg:BAAANQAECgEIAQAAAA==.Dankley:BAABNQAECn8WAAIWAAcKFwa3GAC2AAAWAAcKFwa3GAC2AAAAAA==.Danystorm:BAAANQADCgcIBwABNQAFFAcIEgAIAOgbAA==.Darkomenz:BAAANQADCgEIAQAAAA==.',
Dd='Ddream:BAAANQADCgEIAQABNQAECgYIAgAHAAAAAA==.',
De='Deaddude:BAABNQAECn8oAAIXAAgKvxujLABlAgAXAAgKvxujLABlAgABNQAECgoKGQAEABMXAA==.Deathboi:BAABNQAECn8nAAIYAAkKtRCBIACqAQAYAAkKtRCBIACqAQAAAA==.Deathburgur:BAAANQAECggIDAAAAA==.Deathcuddles:BAABNQAECn8UAAIZAAcKSgK5hgCWAAAZAAcKSgK5hgCWAAAAAA==.Dedcow:BAABNQAECn8mAAIXAAkKvxfEFgApAgAXAAkKvxfEFgApAgAAAA==.',
Di='Diana:BAABNQAECn8tAAIGAAkKyAqTawCjAQAGAAkKyAqTawCjAQAAAA==.Dionysus:BAAANQAECggIAgAAAA==.',
Do='Dontjudgemê:BAAANQADCgYJCgAAAA==.Dorcina:BAAANQADCgcICAAAAA==.Dornth:BAAANQAECgYIAgAAAA==.Downpour:BAAANQADCgUIBQAAAA==.',
Dr='Dracthyr:BAAANQAECgEIAgAAAA==.Dragam:BAAANQAECgQIBAABNQAECgkJIQAaAEgYAA==.Dragonwarrio:BAABNQAECn8rAAIKAAoKER3CDABnAgAKAAoKER3CDABnAgAAAA==.Draltina:BAABNQAECn8XAAICAAkK+wf3IABpAQACAAkK+wf3IABpAQAAAA==.Drazira:BAAANQAECgEIAQAAAA==.Dresstokill:BAAANQADCggJEQAAAA==.Drmonkborg:BAAANQAECgUICwABNQAECgoKJQAMAK4fAA==.Drovis:BAAANQADCgIIAgAAAA==.Druzzlek:BAAANQADCggIEQAAAA==.',
Du='Dubalnuar:BAAANQADCgUIEAAAAA==.Dubalpally:BAAANQADCgcIDQAAAA==.Dubaltrok:BAAANQADCgYIEgAAAA==.Dudde:BAABNQAECn8ZAAMEAAoKExenNwCYAgAEAAoKExenNwCYAgATAAIKNAfxKQBsAAAAAA==.Dulapin:BAAANQADCgIIAgAAAA==.Duskfu:BAABNQAECn8pAAIKAAoKJh5iCwCBAgAKAAoKJh5iCwCBAgAAAA==.Dustylock:BAABNQAECn8hAAMaAAkKSBi1VABXAgAaAAkKSBi1VABXAgACAAEKzQeAfQAvAAAAAA==.',
Ea='Earthele:BAABNQAECn8bAAMEAAcKLwoCdgDvAAAEAAcKLwoCdgDvAAAIAAIK7QjRCwFQAAAAAA==.',
El='Elderblood:BAAANQADCgYIBgAAAA==.Elfcaster:BAAANQAECgEIBAAAAA==.Elfowl:BAAANQADCgYIBwABNQAECgkJLQAMAIAPAA==.',
Em='Emanonsahi:BAAANQABCgQIBgAAAA==.Emmel:BAAANQADCgcIDQAAAA==.',
Eq='Equeslucis:BAAANQAECggIBAAAAA==.',
Er='Eromir:BAAANQAECgQIBwABNQAECgUICwAHAAAAAA==.Eryi:BAAANQAECgMICQAAAA==.',
Ev='Eviserator:BAAANQADCgYIDAAAAA==.',
Fa='Fable:BAABNQAECn8jAAIJAAkK0BigMgAhAgAJAAkK0BigMgAhAgAAAA==.Faegen:BAAANQADCgMIAwAAAA==.Fallumn:BAAANQADCgEIAQAAAA==.Fangytooth:BAAANQAECgEIAQABNQAECgoKKgATADgcAA==.Faze:BAAANQAECgUICgAAAA==.',
Fb='Fbitortamilf:BAAANQAECgUICQAAAA==.',
Fe='Fenlian:BAAANQAECgMIAwAAAA==.Feydoria:BAAANQAECgQIBAAAAA==.',
Fi='Firstfira:BAAANQAECgIICQAAAA==.',
Fr='Frontman:BAABNQAECn8dAAMJAAgKiBllVQAZAgAJAAgKiBllVQAZAgAOAAIKjQ0DYwGBAAAAAA==.',
Fu='Funkycolors:BAAANQAECgQIBAABNQAECgkJIQAaAEgYAA==.',
Ga='Gabomonk:BAAANQADCgEIAQABNQAECgIIAgAHAAAAAA==.Gavrael:BAAANQADCgQIBwAAAA==.',
Ge='Genma:BAAANQAECgYIDgAAAA==.Gewch:BAAANQAECgQIBAAAAA==.',
Gi='Gitgudder:BAAANQAECgQIBQAAAA==.',
Gl='Gloçk:BAAANQAECggIEwAAAA==.',
Go='Goofy:BAAANQAECggIEwAAAA==.Gorbad:BAAANQAECgEIAQAAAA==.',
Gr='Graeae:BAAANQAECgIIAgAAAA==.Grimaldi:BAABNQAECn8eAAIFAAkKQQ2IKgByAQAFAAkKQQ2IKgByAQAAAA==.Grimvaka:BAAANQADCgYIBwAAAA==.Gripforceone:BAAANQAECggIAgAAAA==.',
Gu='Gunduin:BAABNQAECn82AAIGAAkKSRvgNABDAgAGAAkKSRvgNABDAgAAAA==.',
Gw='Gwinden:BAAANQADCgYICwAAAA==.',
Gy='Gyda:BAACNQAFFH8GAAIMAAMKXxzhFwACAQAMAAMKXxzhFwACAQA1AAQKf0cAAwwACgrRIQIeAPkCAAwACgrRIQIeAPkCABsAAgoKDKEgAF0AAAAA.Gyuyuki:BAABNQAECn89AAIEAAoKCA6sPACnAQAEAAoKCA6sPACnAQAAAA==.',
['Gó']='Gódofwàr:BAAANQAECgIIAgAAAA==.',
Ha='Haggish:BAAANQAECgQIBwAAAA==.Hakeo:BAEBNQAECn8pAAIcAAkKCiNxCQC1AgAcAAkKCiNxCQC1AgAAAA==.Hanokan:BAAANQAECgEIAQAAAA==.',
He='Heidie:BAAANQAECgUIBgAAAA==.Hermin:BAAANQADCggIDgAAAA==.',
Hi='Hikomosil:BAABNQAECn8WAAIBAAcKiA18CwCzAQABAAcKiA18CwCzAQAAAA==.',
Ho='Holdmybeerz:BAAANQADCgUIBQAAAA==.Homiekissér:BAAANQAECgcICQAAAA==.',
Hu='Hudsonhawk:BAAANQAECgEIAQAAAA==.',
['Hë']='Hëllen:BAAANQADCgIIAgAAAA==.',
['Hú']='Húñtrèss:BAAANQAECgEIAgAAAA==.',
Im='Imakittycat:BAABNQAECn8tAAISAAoKYB2+FACiAgASAAoKYB2+FACiAgAAAA==.Impared:BAAANQAECgYIBgABNQAECggIEAAHAAAAAA==.',
Is='Isummon:BAAANQADCgEIAQAAAA==.',
Iv='Ivey:BAAANQADCggIDAAAAA==.',
Ja='Jacburton:BAAANQADCgEIAQAAAA==.Jacenne:BAAANQAECgEIAgAAAA==.Jairus:BAAANQAECggIAQAAAA==.',
Je='Jenesis:BAABNQAECn9EAAMOAAoKxiIyDwAaAwAOAAoKxiIyDwAaAwAJAAEKHgOZMwEkAAAAAA==.Jenisis:BAAANQAECgEIAQAAAA==.Jerkme:BAAANQAECggICwAAAA==.',
Jo='Josephyn:BAABNQAECn8kAAIJAAoKTRYJSQBDAgAJAAoKTRYJSQBDAgABNQAFFAcIEgAIAOgbAA==.Jotaro:BAAANQADCgUIBQAAAA==.',
Ju='Juggernåut:BAAANQADCgMIAwAAAA==.',
Ka='Kaale:BAAANQAECgIIAgABNQAECgUIEwAHAAAAAA==.Kahoa:BAAANQAECgQIBAAAAA==.Kakuta:BAABNQAECn9BAAMJAAoKliFWDQBfAwAJAAoKliFWDQBfAwAOAAoKlw9gYwDPAQAAAA==.Kakutæ:BAAANQAECggIDwABNQAECgoKQQAJAJYhAA==.Kalru:BAAANQADCgYIAwAAAA==.Kalypsso:BAAANQAECgEIAQAAAA==.Kargar:BAAANQAECgEJAgAAAA==.Karot:BAAANQAECgUICgAAAA==.Katharsis:BAABNQAECn8qAAIOAAoKpBjodQBBAgAOAAoKpBjodQBBAgAAAA==.',
Ke='Keba:BAAANQAECgIIAwABNQAFFAYIEQAJALIXAA==.Keit:BAEANQADCgUIBQABNQAFFAUIDQAdAIIWAA==.Keévs:BAAANQAECgEIAgAAAA==.',
Kh='Khalidisi:BAABNQAECn8bAAIJAAgK3BzPKwC4AgAJAAgK3BzPKwC4AgAAAA==.Khalizar:BAAANQADCgUIBQAAAA==.Khanna:BAAANQADCgIIAgAAAA==.Khenja:BAAANQADCgUIBQAAAA==.',
Ki='Killinthyme:BAAANQADCgYIBgAAAA==.',
Kk='Kkiilleerr:BAAANQAECgQIBAAAAA==.',
Ko='Korath:BAAANQABCgIIAgAAAA==.Korbulo:BAAANQAECgUIBwAAAA==.Korlothel:BAAANQABCgIIAgABNQAECgoKJAAGAI8XAA==.',
Kr='Kriptos:BAAANQADCgEIAQABNQAECgYIAgAHAAAAAA==.Kronar:BAAANQAECgEIAgAAAA==.Kronu:BAAANQAECgEIAQAAAA==.Krumpus:BAAANQAECgEIAQAAAA==.Kryma:BAAANQAECgMIAwAAAA==.',
Ku='Kungfuuy:BAAANQADCgQIBgAAAA==.',
Ky='Kylogos:BAAANQAECgEIAQAAAA==.Kynsong:BAABNQAECn8pAAMMAAoKxxLLRgDkAQAMAAoKxxLLRgDkAQAbAAEKJAHzNAAHAAAAAA==.Kysia:BAAANQAECgUICQABNQAFFAMICwAOAC0PAA==.',
['Ké']='Kéévály:BAAANQAECgEIAQAAAA==.',
['Kî']='Kîrah:BAACNQAFFH8FAAIMAAMK/RjMGwDQAAAMAAMK/RjMGwDQAAA1AAQKfx4AAgwACQpIIbEZAA4DAAwACQpIIbEZAA4DAAAA.',
La='Larcine:BAAANQADCggICAABNQAECggIFAAaAN0MAA==.',
Le='Lerazal:BAABNQAECn8WAAIeAAoKIRUnEwAdAgAeAAoKIRUnEwAdAgAAAA==.Leshah:BAAANQADCggICwAAAA==.Lexanteus:BAAANQADCgUIBQABNQAECgoKFgAeACEVAA==.',
Li='Liir:BAAANQAECgUIBQAAAA==.Lilbilly:BAAANQAECgEIAwAAAA==.Lildh:BAABNQAECn8jAAIfAAkK1RGMCACwAQAfAAkK1RGMCACwAQAAAA==.Lilypetal:BAAANQAECggICQAAAA==.Liyi:BAAANQAECgUICwAAAA==.',
Lo='Lorastyrell:BAAANQAECgEIAwAAAA==.Loughalnan:BAAANQADCgQIBAABNQAECgoKNQAGAGIhAA==.Loìsbethe:BAAANQAECgQIBgAAAA==.',
Lu='Luciferra:BAABNQAECn87AAIMAAoK7h+3GQAOAwAMAAoK7h+3GQAOAwABNQAFFAcIEgAIAOgbAA==.Luu:BAAANQAECgMIBAABNQAECgoKJgAJAPAOAA==.',
Ly='Lytho:BAAANQAECgUIBgAAAA==.',
Ma='Madomi:BAAANQAECgIIAgABNQAECgkJNgAGAEkbAA==.Maetromundo:BAAANQADCgcICwAAAA==.Magelock:BAAANQAECgIIAgABNQAECgQIBwAHAAAAAA==.Magickul:BAAANQAECgYIAQABNQAECgQIBwAHAAAAAA==.Malakii:BAAANQADCgEIAQAAAA==.Maletsy:BAAANQAECgYIEAABNQAECgkJNgAGAEkbAA==.Maliboo:BAABNQAECn8jAAMSAAoKjxQ6EgBcAgASAAoKjxQ6EgBcAgAFAAMKKAjMmAB2AAAAAA==.Mandalor:BAAANQADCgEIAQAAAA==.Maxamus:BAABNQAECn8zAAMPAAoKfyDyIwApAwAPAAoKfyDyIwApAwAWAAEK2SH+IQBiAAAAAA==.',
Mc='Mceuan:BAAANQADCgIIAgAAAA==.',
Me='Medarisa:BAABNQAECn8VAAIaAAQK4w8YugCsAAAaAAQK4w8YugCsAAAAAA==.Mederia:BAAANQADCgEIAQAAAA==.Medívh:BAAANQAECgUIBwAAAA==.Meelly:BAAANQADCgQIBAAAAA==.Megagengar:BAAANQAECgEIAQAAAA==.Megalucario:BAAANQAECgEIAQAAAA==.Melisandr:BAAANQADCgUIBQAAAA==.Merkenier:BAABNQAECn8jAAMFAAoKIQosMgBAAQAFAAoKIQosMgBAAQARAAEKAADvfAAAAAAAAA==.Merkshamalot:BAAANQAECgIIBQABNQAECgoKIwAFACEKAA==.Merkur:BAAANQADCggIJAABNQAECgoKIwAFACEKAA==.Merkurry:BAAANQADCgQIBQABNQAECgoKIwAFACEKAA==.',
Mi='Mieks:BAAANQAECgYIDQAAAA==.Missmayhem:BAAANQAECgQIDQAAAA==.',
Mo='Modifiedmix:BAAANQAECgEIAgAAAA==.Monatazumaa:BAAANQADCggIDwAAAA==.Monkeyfudge:BAAANQADCgUIBQAAAA==.Moonfalls:BAAANQAECgIIAgABNQAECggIHQAMALEYAA==.',
Mu='Mugato:BAAANQABCgEIAQAAAA==.Murdette:BAAANQAECgUIBQABNQAECggIEAAHAAAAAA==.',
My='Mystych:BAABNQAECn8cAAMQAAkKIRDOBADrAQAQAAkKIRDOBADrAQAGAAEKAADRRwEAAAAAAA==.',
['Må']='Mågi:BAAANQAECgQICAAAAA==.',
['Mé']='Méabh:BAAANQAECgIIAgABNQAECgYIEQAHAAAAAA==.',
['Mö']='Möôôöõöóòòõô:BAABNQAECn83AAMJAAoKYBQ/YAD3AQAJAAoKYBQ/YAD3AQAOAAUKYA62HQHtAAAAAA==.',
Na='Nakednwasted:BAAANQADCgYIBgAAAA==.Nanakii:BAAANQAECgIJAwAAAA==.Nathrold:BAAANQAECgYIDAABNQAECggIEwAHAAAAAA==.',
Ne='Necos:BAAANQADCgYICgAAAA==.Neptune:BAACNQAFFH8SAAIIAAcK6BsGAwBUAgAIAAcK6BsGAwBUAgA1AAQKfz8AAwgACgp3ItEMADsDAAgACgp3ItEMADsDAAQAAQptDDLcADoAAAAA.Nerfpaladins:BAAANQAECgUIBgAAAA==.Nerfpriests:BAABNQAECn8ZAAINAAgKORSmIwAVAgANAAgKORSmIwAVAgAAAA==.Nerissl:BAAANQADCgIIAgAAAA==.',
Ni='Niemwa:BAAANQADCgQIBAAAAA==.Nightbird:BAABNQAECn8UAAIgAAkKMhIGLQASAgAgAAkKMhIGLQASAgAAAA==.Nightwingqt:BAAANQAECggIEgAAAA==.Nimrock:BAAANQABCgIIAgAAAA==.Ninediewatt:BAAANQAECgEIAQAAAA==.',
['Nè']='Nèo:BAAANQADCgYIEAAAAA==.',
Ob='Obsaedia:BAAANQAECgcIFAABNQAECggIIAAHAAAAAQ==.',
Od='Odysseus:BAABNQAECn8XAAMTAAoKZBWIEQC7AQATAAgKWRaIEQC7AQAEAAQK0AqqlwCjAAAAAA==.',
Ok='Oktobra:BAABNQAECn8UAAIOAAcKigIlTQGlAAAOAAcKigIlTQGlAAAAAA==.',
On='Onos:BAAANQADCggJCAAAAA==.',
Or='Orillin:BAABNQAECn88AAMZAAoK3yKEBwAbAwAZAAoK3yKEBwAbAwAYAAIKdg+yygBXAAAAAA==.Orioan:BAABNQAECn8qAAMOAAkKeiAPRgDCAgAOAAkKeiAPRgDCAgAJAAIKMQ0cwgBlAAAAAA==.',
Os='Osun:BAAANQAECgEIAQAAAA==.Osÿrus:BAAANQADCgQIBAAAAA==.',
Ou='Ouroboro:BAAANQAECgQIBAAAAA==.',
Pa='Padcadaver:BAAANQAECgEIAgAAAA==.Paddy:BAAANQAECgYIEwAAAA==.Padeönwë:BAAANQAECgEIAQAAAA==.Padraig:BAAANQAECgEIAwAAAA==.Padspectre:BAAANQAECgEIAQAAAA==.Padtipsy:BAAANQAECgEIAwAAAA==.Padvici:BAAANQAECgEIAgAAAA==.Palantyr:BAACNQAFFH8HAAIEAAQKBA2MHADcAAAEAAQKBA2MHADcAAA1AAQKf10AAgQACgrmHx8SALsCAAQACgrmHx8SALsCAAAA.Pallytings:BAAANQADCgQIBAAAAA==.Panurita:BAABNQAECn8wAAIIAAoKkhyTHgCYAgAIAAoKkhyTHgCYAgAAAA==.',
Pe='Pellidillion:BAAANQADCgcICwAAAA==.Pepas:BAAANQAECggIDQAAAA==.',
Po='Polgára:BAAANQAECgIIAgAAAA==.',
Pr='Prepotente:BAAANQAECgEIAgABNQAECgkJHgAFAEENAA==.',
Pu='Puppysmacks:BAAANQAECgEIAgABNQAECgEIAwAHAAAAAA==.Purity:BAAANQAECgMIAwAAAA==.',
Qe='Qevelana:BAAANQADCgMIBAAAAA==.',
Qu='Quetzalcoatl:BAAANQADCgUICQAAAA==.',
Ra='Raambox:BAABNQAECn8yAAIPAAkKvw6lYQChAQAPAAkKvw6lYQChAQAAAA==.Raddish:BAAANQAECgcIEwAAAA==.Raedl:BAAANQAECgYICwAAAA==.Ragriefy:BAAANQADCgUIBQAAAA==.Rahjlynn:BAAANQAECgEIAQAAAA==.Raiinn:BAAANQADCgEIAQAAAA==.Ramantu:BAAANQADCgIJAgAAAA==.Ramranch:BAAANQAECgQIBQABNQAECgoKLAAIAPEcAA==.Randay:BAAANQAECggIDQAAAA==.Rathix:BAAANQABCgIIAQAAAA==.Raylee:BAAANQAECgQIBAAAAA==.Razuki:BAAANQAECgYIDgAAAA==.',
Re='Reeker:BAAANQABCgQIAgAAAA==.Retton:BAAANQAECgQIBAABNQAECgUIEwAHAAAAAA==.Revenge:BAABNQAECn9aAAIOAAoKFCWaCwAzAwAOAAoKFCWaCwAzAwAAAA==.',
Rh='Rhovanion:BAAANQADCgUIBQABNQAFFAMIBQAXAGsFAA==.Rhuac:BAAANQADCggICgAAAA==.',
Ri='Riddik:BAAANQADCggIDQAAAA==.Rifle:BAAANQAECgQICgABNQAECgoKOAAEAIMTAA==.Rika:BAAANQAECgYIDgAAAA==.Risakah:BAAANQAECggICQAAAA==.',
Ro='Robo:BAAANQAECgEIAQAAAA==.Robolich:BAABNQAECn8eAAIXAAoKCiEuEgBjAgAXAAoKCiEuEgBjAgAAAA==.Rosefist:BAEANQAECgUIBQAAAA==.Rosemourne:BAEANQADCggICAABNQAECgUIBQAHAAAAAA==.Roshwyn:BAABNQAECn8UAAIGAAUKjwdO7ACYAAAGAAUKjwdO7ACYAAAAAA==.Rottedmeat:BAAANQAECggIDAAAAA==.',
Ru='Rubmytotems:BAABNQAECn8dAAMIAAkKiBKLTQCpAQAIAAkKiBKLTQCpAQAEAAEKAAABPwEuAAAAAA==.Ruckus:BAABNQAECn8xAAIOAAoKwhjjbgBSAgAOAAoKwhjjbgBSAgAAAA==.',
Rx='Rxmblock:BAAANQAECgEIAQAAAA==.Rxmboxx:BAAANQADCgIIAgAAAA==.',
Sa='Saelin:BAAANQAECgcICwABNQAECgUIEwAHAAAAAA==.Saintquake:BAAANQAECgQIBAAAAA==.Sareenastar:BAABNQAECn8kAAIMAAoK4ySVEwAwAwAMAAoK4ySVEwAwAwAAAA==.',
Sc='Scarless:BAAANQADCggICwAAAA==.',
Se='Seafood:BAAANQAECggIDwAAAA==.Sennara:BAAANQAECgcIDwAAAA==.Sephiróth:BAAANQAECgIIAQAAAA==.Serenitynow:BAAANQADCgYICAAAAA==.Sethworgen:BAAANQADCggICAAAAA==.',
Sh='Shadowlillee:BAAANQAECgIIAwAAAA==.Shadowmeteor:BAACNQAFFH8NAAINAAUKzBbnBgD9AAANAAUKzBbnBgD9AAA1AAQKfxoAAg0ACgo+HesHAMgCAA0ACgo+HesHAMgCAAAA.Shakey:BAAANQAECgEIAQAAAA==.Shalen:BAAANQAECggICgAAAA==.Shamrox:BAAANQAECgYIDAAAAA==.Sharar:BAAANQAECgUIBwAAAA==.Sharker:BAAANQADCgMIAwAAAA==.Sharkerprest:BAAANQADCgYIBgAAAA==.Sharkerwarlo:BAAANQAECgEJAQAAAA==.Sharpenator:BAAANQAECgQIBAAAAA==.Sheraa:BAAANQAECgUICgAAAA==.Shieldknight:BAAANQAECgYICQAAAA==.Shiftystrike:BAABNQAECn8WAAIVAAYKXBlSEgBVAQAVAAYKXBlSEgBVAQAAAA==.Shifushield:BAAANQADCggIEQAAAA==.Shirazormu:BAAANQAECgEIAQABNQAECgUIBQAHAAAAAA==.Shrike:BAAANQADCgYICgABNQAFFAgIGQANALoQAA==.',
Si='Silentwindy:BAAANQAECgEIAQAAAA==.Silmarkthree:BAABNQAECn8dAAIhAAgKAQ6zxAD7AQAhAAgKAQ6zxAD7AQAAAA==.Sinbåd:BAAANQADCggICgAAAA==.',
Sk='Skol:BAACNQAFFH8FAAIXAAMKawV2FgCMAAAXAAMKawV2FgCMAAA1AAQKfycAAhcACQpPD7ZbAIMBABcACQpPD7ZbAIMBAAAA.',
Sl='Slipknoth:BAACNQAFFH8dAAMNAAcK0RcLBQDxAQANAAcK0RcLBQDxAQAMAAYKxxDjCQDJAQA1AAQKf0MABA0ACgp4JKUCAEsDAA0ACgp4JKUCAEsDAAwABAriFDumALkAABsAAwrBD+YOAGwAAAAA.Slithice:BAAANQAECgIIAgABNQAFFAYIEQABAMEeAA==.',
Sn='Snakeplizken:BAAANQADCggIAQAAAA==.',
So='Sorean:BAACNQAFFH8XAAIQAAYKehxHAABjAQAQAAYKehxHAABjAQA1AAQKfzYAAxAACgqnItEAADADABAACgqnItEAADADAAsAAQpjDdGJADUAAAAA.Sorrel:BAAANQAECgEIAQAAAA==.',
Sp='Specialmove:BAAANQAECgYIDAAAAA==.',
St='Stabby:BAAANQAECggIBwAAAA==.Staghealz:BAAANQADCgYICAAAAA==.Staldorn:BAAANQADCgIIAgAAAA==.Starlet:BAAANQADCgIIAgAAAA==.Starlune:BAAANQAECgQIBwAAAA==.Stifs:BAABNQAECn8jAAIDAAoKyhKrGgBmAQADAAoKyhKrGgBmAQAAAA==.Stinkinglily:BAAANQABCgQIBwAAAA==.Stonebeard:BAAANQADCggIIQAAAA==.Stormstream:BAAANQADCgMICQAAAA==.',
Su='Suelustra:BAABNQAECn8UAAIaAAgK3QxqugBZAQAaAAgK3QxqugBZAQAAAA==.',
Sy='Sykotyk:BAABNQAECn8lAAIIAAoKjBbJOgB0AgAIAAoKjBbJOgB0AgAAAA==.',
Ta='Tadagain:BAAANQAECgcIEgAAAA==.Talairn:BAAANQAECgEIAgAAAA==.Talix:BAAANQAECgIIAgAAAA==.Tamaira:BAAANQAECgUICQAAAA==.Tankybears:BAAANQAECgUIEwAAAA==.Tanthirria:BAAANQAECgEIAQAAAA==.Tart:BAAANQAECgYIDwAAAA==.',
Te='Telekinesis:BAABNQAECn8eAAQGAAgK2xUXeQAdAgAGAAgK2xUXeQAdAgALAAYKwAYYTAAEAQAQAAEKAADNEwAxAAAAAA==.Tenara:BAABNQAECn8jAAMIAAoK3x62PABtAgAIAAoK3x62PABtAgAEAAQKqw6O+wCbAAABNQAECgUIEwAHAAAAAA==.Teos:BAAANQADCgYIBgABNQAFFAMIBQAXAGsFAA==.',
Th='Thalanor:BAAANQAECgEIAQAAAA==.Thaliak:BAAANQADCgYIBwABNQAECgQIBwAHAAAAAA==.Tharad:BAAANQAECgQIBQABNQAECgcIDwAHAAAAAA==.Tharris:BAAANQAECgEIAQAAAA==.Tholin:BAAANQADCggIEwAAAA==.Thunderlily:BAABNQAECn8nAAMhAAkKfAj1jgBaAQAhAAkKPQj1jgBaAQAiAAEKvQZURwA1AAAAAA==.',
Ti='Timcol:BAAANQAECgIIAgABNQAECggIAQAHAAAAAA==.Tinychaos:BAAANQAECgUIBgAAAA==.Tirra:BAAANQADCggIDgAAAA==.',
Tr='Tracther:BAAANQADCgYIDwAAAA==.Trapps:BAAANQADCgYIDAAAAA==.Treedemon:BAAANQADCgYIBgAAAA==.Treelock:BAABNQAECn8WAAIaAAkKmhhOcAAOAgAaAAkKmhhOcAAOAgAAAA==.Trelapin:BAAANQADCggIDQAAAA==.',
Tw='Twinrova:BAAANQADCggICAAAAA==.',
Ty='Tybearon:BAAANQADCgYIBwAAAA==.Tyinthus:BAAANQAECggICAABNQAECggIAQAHAAAAAA==.Tyrelitha:BAAANQADCgQIBgAAAA==.',
Ug='Ugdeth:BAAANQAECggICQABNQAFFAQIBwAjAE0MAA==.',
Uh='Uhtrad:BAABNQAECn8XAAIDAAkKDg4PLQB1AQADAAkKDg4PLQB1AQAAAA==.Uhura:BAAANQADCgYIBgAAAA==.',
Ul='Ulfrir:BAAANQAECgQIBQAAAA==.Ullhr:BAAANQADCgYICwAAAA==.Ultradukes:BAAANQADCgEIAQAAAA==.Ultralord:BAAANQADCgQIBAAAAA==.',
Un='Unleashed:BAAANQAECgEIAQAAAA==.',
Ur='Ursaline:BAAANQAECgEIAQABNQAECgcIDwAHAAAAAA==.',
Va='Valock:BAAANQAECgYIEwAAAA==.Vanshifty:BAABNQAECn9DAAISAAoKTx5DEQDJAgASAAoKTx5DEQDJAgAAAA==.',
Ve='Venli:BAAANQAECgMIBQAAAA==.',
Vo='Voidentine:BAAANQABCggIBgAAAA==.',
Vy='Vyx:BAAANQAECgIIAwAAAA==.',
Wa='Waffle:BAABNQAECn8dAAIGAAkKkhHZcgCRAQAGAAkKkhHZcgCRAQAAAA==.Wardaelos:BAAANQAECgEIAQAAAA==.Wargue:BAABNQAECn8YAAMWAAkKUw99DgBTAQAWAAcKFxF9DgBTAQAPAAYKQgjD7gAEAQAAAA==.Wasprepared:BAAANQADCgQIBAAAAA==.Watson:BAAANQAECgYICQABNQAECgcIDwAHAAAAAA==.',
We='Weeaboos:BAAANQADCgQICgAAAA==.Welindis:BAAANQADCgcJBwABNQAECgMIBgAHAAAAAA==.Wenus:BAAANQABCgQIAwAAAA==.',
Wh='Whofurmoover:BAAANQAECgQICQAAAA==.',
Wi='Winrodan:BAABNQAECn8eAAIDAAkKOyJ0FQBVAgADAAkKOyJ0FQBVAgABNQAECgkJHgADADsiAA==.Wizzard:BAAANQAECggIIAAAAQ==.',
['Wó']='Wóof:BAAANQADCgMIAwAAAA==.',
Xa='Xaandu:BAAANQADCgQIBAAAAA==.Xaris:BAABNQAECn8iAAIjAAgKLRKkFAB4AQAjAAgKLRKkFAB4AQABNQAECgoKKQAMAMcSAA==.',
Xi='Xiladin:BAAANQAECgMIBAAAAA==.',
Xt='Xtremes:BAAANQADCgcIBwAAAA==.',
['Xí']='Xíe:BAABNQAECn8aAAIcAAgKxREdFwC6AQAcAAgKxREdFwC6AQAAAA==.',
Yi='Yimm:BAAANQADCgEIAQAAAA==.',
Yo='Yourdadsadad:BAAANQAECgUIBQABNQAFFAcIEwAPAFsgAA==.',
['Yø']='Yø:BAAANQAECgQIBAAAAA==.',
Zb='Zbm:BAAANQAECgIJAgAAAA==.',
Ze='Zeldy:BAABNQAECn8yAAIGAAoKURnDNgDGAgAGAAoKURnDNgDGAgAAAA==.Zenthareal:BAABNQAECn8rAAMkAAkK0RXCLQDUAQAkAAkK0RXCLQDUAQAdAAEKYwjglAAyAAAAAA==.Zenzi:BAAANQADCgcIHAAAAA==.',
Zm='Zmaster:BAAANQAECgUIEAAAAA==.',
Zu='Zunarri:BAAANQADCgYICAABNQAECggIFgAGACYdAA==.',
Zw='Zwar:BAAANQADCgMJAwABNQAECgUIEAAHAAAAAA==.',
Zy='Zyri:BAAANQAECgEIAQAAAA==.',
['Ða']='Ðark:BAABNQAECn8+AAIGAAoKPB9lHQAiAwAGAAoKPB9lHQAiAwAAAA==.',
['Ðr']='Ðr:BAAANQAECggICQAAAA==.',
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
