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

local lookup = {'Warlock-Destruction','Paladin-Holy','Mage-Arcane','Paladin-Retribution','Hunter-Marksmanship','Hunter-BeastMastery','DeathKnight-Unholy','Unknown-Unknown','Druid-Restoration','Evoker-Preservation','DeathKnight-Blood','Shaman-Elemental','Warrior-Protection','DeathKnight-Frost','Druid-Balance','Monk-Windwalker','Evoker-Devastation','DemonHunter-Devourer','DemonHunter-Vengeance','Evoker-Augmentation','Priest-Holy','Rogue-Assassination','Warlock-Demonology','Warlock-Affliction','Paladin-Protection','Shaman-Enhancement','Mage-Frost','Shaman-Restoration','DemonHunter-Havoc','Priest-Shadow','Druid-Feral','Monk-Mistweaver','Rogue-Subtlety','Hunter-Survival','Warrior-Arms','Monk-Brewmaster',}
local provider = {region='US',realm='Bloodscalp',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abbpriest:BAAANQADCgYJBgABNQAECggJGQABAOYYAA==.Abruum:BAAANQADCgcIDAAAAA==.',
Ad='Admetus:BAABNQAECn8rAAICAAoKoh9pFQDgAgACAAoKoh9pFQDgAgAAAA==.Adobe:BAAANQADCggIGwAAAA==.',
Am='Amapriest:BAAANQAECgQICAABNQAECgoKHQADAI8UAA==.Amathal:BAABNQAECn8dAAIDAAoKjxSopAA4AgADAAoKjxSopAA4AgAAAA==.',
An='Anderson:BAAANQADCgQIBAAAAA==.Ankheloios:BAAANQAECgUIDgAAAA==.',
Ar='Arcanehonkey:BAAANQADCggICAAAAA==.Aredhela:BAABNQAECn8bAAIEAAgKZxUdkQACAgAEAAgKZxUdkQACAgAAAA==.Arias:BAAANQAECgQIBAAAAA==.Armsdealer:BAAANQADCgUIBQAAAA==.Arro:BAAANQAECgEIAQAAAA==.',
As='Ascending:BAAANQAECgQICAAAAA==.Asha:BAACNQAFFH8VAAIFAAcKMxgDBQB6AQAFAAcKMxgDBQB6AQA1AAQKfy4AAwUACgrCHOoRANYCAAUACgrCHOoRANYCAAYAAQqxAV1sASYAAAAA.Ashveil:BAAANQADCgQIBAABNQAECgoKIwAHAIIaAA==.Astrialynn:BAAANQADCgYIBwABNQADCgcIBwAIAAAAAA==.Astrulawa:BAAANQAECgQICgAAAA==.',
At='Athrea:BAABNQAECn8uAAIHAAoKLyL8IwCyAgAHAAoKLyL8IwCyAgAAAA==.',
Au='Aurhiel:BAAANQAECgEIAQAAAA==.',
Av='Avasharm:BAAANQABCgYIBgABNQABCgYIAgAIAAAAAA==.',
Ba='Barakah:BAAANQAECgQIAwAAAA==.Barnre:BAAANQAECgIIBAAAAA==.Battlelord:BAAANQAECgIIBAAAAA==.',
Bd='Bdssm:BAAANQAECgcIBwAAAA==.',
Be='Bearito:BAAANQAECgQIEAAAAA==.Beefstick:BAABNQAECn8hAAIGAAoKZBLIhwD7AQAGAAoKZBLIhwD7AQAAAA==.Beserkfury:BAABNQAECn8tAAIFAAoKEAokGACNAQAFAAoKEAokGACNAQAAAA==.',
Bi='Biercan:BAAANQAECgYIDAAAAA==.Bigcarl:BAAANQAECgEIAQAAAA==.Binke:BAAANQADCgQIBAAAAA==.Bittyboop:BAAANQADCggICwABNQAECgUICQAIAAAAAA==.Bittywhite:BAAANQAECgMIBAABNQAECgUICQAIAAAAAA==.Bittywyvern:BAAANQADCgUIBQABNQAECgUICQAIAAAAAA==.',
Bj='Bjarna:BAAANQAECggIDwAAAA==.',
Bl='Blayze:BAAANQAECgYIDgAAAA==.Blinkytime:BAABNQAECn8rAAIEAAgKKxT0rwC/AQAEAAgKKxT0rwC/AQAAAA==.Bloodskull:BAAANQADCgEIAQAAAA==.Blúnt:BAAANQADCgQIBAAAAA==.',
Bo='Bobheals:BAABNQAECn87AAIJAAoK1Bu4DgCXAgAJAAoK1Bu4DgCXAgAAAA==.Boibye:BAAANQAECgQICwAAAA==.Bolblock:BAAANQAECggIDwAAAA==.Bolo:BAACNQAFFH8KAAIKAAMKZhBwDQC7AAAKAAMKZhBwDQC7AAA1AAQKfzYAAgoACgqdH6kHACsDAAoACgqdH6kHACsDAAAA.Boostedww:BAAANQAECgQICwAAAA==.Borkoir:BAAANQAECggIDgABNQAECggIDwAIAAAAAA==.Bowlo:BAAANQAECgUIBQAAAA==.Bowzo:BAAANQAECgMIBAAAAA==.',
Br='Brambleclaw:BAABNQAECn89AAILAAoKZCBFDABQAwALAAoKZCBFDABQAwAAAA==.Brayker:BAABNQAECn89AAIEAAoKhyM6IgA7AwAEAAoKhyM6IgA7AwAAAA==.Breadoneal:BAABNQAECn8tAAMCAAoKVRoiFgDaAgACAAoKVRoiFgDaAgAEAAMKqQasXQGKAAAAAA==.Brewed:BAAANQAECgMIBAAAAA==.Brynjamin:BAAANQAECgQICAAAAA==.Brüenor:BAAANQAECgMIBQAAAA==.',
Bu='Bubbi:BAAANQADCgEIAQAAAA==.Bukkorosuzo:BAAANQAECgUIDgAAAA==.Burntroot:BAABNQAECn8fAAIMAAcK5APuuAAgAQAMAAcK5APuuAAgAQAAAA==.',
['Bá']='Bálor:BAAANQAECgUIDgAAAA==.',
Ca='Cacci:BAAANQADCgcIBwAAAA==.Caedwyn:BAAANQAECgcIEwAAAA==.Camdakablam:BAAANQAECgcIEQAAAA==.Careadin:BAAANQADCgQIBAABNQAECggIGwANAGsgAA==.Careradin:BAABNQAECn8bAAINAAgKayBaDABwAgANAAgKayBaDABwAgAAAA==.Carereaper:BAAANQAECgEIAQABNQAECggIGwANAGsgAA==.Cartilage:BAABNQAECn8dAAMHAAkKQQ2zMgAsAQAHAAkKMAyzMgAsAQAOAAcKhQsMbQDqAAAAAA==.Cassieruth:BAAANQAECggIDQAAAA==.Catalei:BAAANQAECgEIAQAAAA==.',
Ce='Centrest:BAAANQADCgYJCAAAAA==.Cerus:BAAANQADCgEIAQAAAA==.',
Ch='Chebbles:BAAANQADCgUIBgABNQAECgcIJAAPAMwRAA==.Chillidan:BAAANQAECgMIAwABNQAECgkJKQAQAFMhAA==.Chivi:BAAANQADCggIDgABNQAECggIIgARAKIcAA==.Chonkmonk:BAAANQADCgQIBAAAAA==.Chupacabrass:BAAANQAECgIIAgAAAA==.Chëbbles:BAAANQAECgMIAwABNQAECgcIJAAPAMwRAA==.',
Co='Colman:BAAANQAECgUIDgAAAA==.Coorsbanquet:BAABNQAECn8bAAMSAAgKZg4eNgCSAQASAAgKZg4eNgCSAQATAAUK/wx1GACnAAAAAA==.Coorsbite:BAABNQAECn8gAAQKAAcKdRMGHAADAQAKAAQKvxUGHAADAQARAAUKmQgVKQDlAAAUAAcKEQ/TDQDYAAABNQAECggIGwASAGYOAA==.Coorslight:BAAANQADCgYIBgABNQAECggIGwASAGYOAA==.Corrahthecow:BAAANQAECgEIAQABNQAECggIGwASAGYOAA==.',
Cr='Craccjar:BAAANQADCgYIBwAAAA==.Crackjar:BAAANQADCgUICAAAAA==.Croc:BAAANQAECgYIEAAAAA==.Crudala:BAAANQADCgcICQABNQAECgMIAgAIAAAAAA==.Crystle:BAABNQAECn8rAAIVAAoKfAvyQwDwAQAVAAoKfAvyQwDwAQAAAA==.Crystlemarie:BAAANQADCgMIAwAAAA==.',
Cs='Csyasha:BAAANQADCgcIBwABNQAECgoKHAAWAI0LAA==.',
Cu='Cubcadet:BAABNQAECn8nAAIEAAoKrRqXSQC4AgAEAAoKrRqXSQC4AgAAAA==.',
Cy='Cybear:BAABNQAECn8kAAIXAAoK8xjvMQAZAgAXAAoK8xjvMQAZAgAAAA==.',
Da='Dalanora:BAABNQAECn88AAQXAAoKYBp3JgDqAgAXAAoKYBp3JgDqAgABAAMKXRUdQwC4AAAYAAMKpBafGwCkAAAAAA==.Dammned:BAAANQAECgQIBQAAAA==.Dapalyu:BAABNQAECn8vAAMZAAoKYRFCKwCDAQAZAAkKLhJCKwCDAQAEAAgKYQX1EwH+AAAAAA==.Davidx:BAAANQADCgQIBgAAAA==.',
De='Dekig:BAAANQAECgEIAQAAAA==.Demine:BAAANQAECgMIBAAAAA==.Detrazeral:BAAANQADCggIEAAAAA==.',
Di='Dico:BAAANQAECgcICgABNQAFFAcIGwANAB8XAA==.Dipper:BAABNQAECn82AAIEAAoKkhacegA2AgAEAAoKkhacegA2AgAAAA==.',
Do='Dohan:BAAANQADCggIEAAAAA==.Dorìan:BAAANQADCggIFgAAAA==.Dorÿ:BAAANQADCgcIBwAAAA==.',
Dr='Draetona:BAAANQADCggIGQAAAA==.Druidthings:BAAANQADCgUIBQAAAA==.',
Ee='Eeveeko:BAABNQAECn8uAAIaAAoK6xcCDACwAgAaAAoK6xcCDACwAgAAAA==.',
Ej='Ejavuday:BAABNQAECn8wAAMDAAoKhR5CQQACAwADAAoKhR5CQQACAwAbAAEKgR2cRwA1AAAAAA==.',
En='Enerchi:BAABNQAECn8pAAIQAAkKUyF8CgArAwAQAAkKUyF8CgArAwAAAA==.',
Er='Erianar:BAAANQADCgEIAQAAAA==.Ervyne:BAABNQAECn8iAAMGAAoKvhCTbAA5AgAGAAoKnRCTbAA5AgAFAAUKmAaaUgDeAAAAAA==.',
Ev='Evera:BAABNQAECn8gAAIHAAoKYgmCLwA+AQAHAAoKYgmCLwA+AQAAAA==.Evos:BAAANQADCgYJBgAAAA==.',
Ex='Exning:BAAANQADCggICAAAAA==.',
Fa='Fatherømally:BAAANQAECggIBgABNQAECgkJHQAEAEQWAA==.Fauci:BAAANQAECgYIBgABNQAFFAUIEAAWAAclAA==.',
Fe='Feihao:BAAANQAECgEIAQAAAA==.Feile:BAABNQAECn8zAAMXAAoKgA+vawAaAgAXAAoKgA+vawAaAgABAAEKAAArcQA+AAAAAA==.Feltree:BAAANQADCgQIBAAAAA==.',
Fi='Fishbox:BAAANQABCgYIDAAAAA==.',
Fl='Flashir:BAAANQADCgIIAgAAAA==.Flinzza:BAABNQAECn8kAAMaAAkKYxd3GADgAQAaAAkKYxd3GADgAQAcAAgK2hSnaQDPAQAAAA==.Flyknit:BAABNQAECn8XAAIEAAYKZRKc2gBmAQAEAAYKZRKc2gBmAQAAAA==.',
Fr='Fredthedh:BAABNQAECn8jAAMSAAoKjBeVIwAsAgASAAgKXxeVIwAsAgAdAAUKChY7VwCRAAAAAA==.Fromtheback:BAAANQAECgIIAgABNQAECgoKHwAHAMESAA==.Frosticals:BAABNQAECn8tAAIDAAkK4CEvQAAFAwADAAkK4CEvQAAFAwAAAA==.Frostsugar:BAAANQABCgQIBgAAAA==.',
Ga='Gaashw:BAAANQABCgQIBwAAAA==.Gabtvsorcere:BAAANQADCgYICgAAAA==.Ganandor:BAABNQAECn8kAAIWAAoKVBzaGwCfAgAWAAoKVBzaGwCfAgAAAA==.Garroz:BAAANQADCgEIAQAAAA==.Gaulish:BAAANQAECgIIBgAAAA==.',
Ge='Geocide:BAABNQAECn8VAAIMAAcKVB3oVgAeAgAMAAcKVB3oVgAeAgAAAA==.Getagrip:BAAANQAECggIDAABNQAFFAMICAAWAOMTAA==.Gethalyn:BAAANQAECgUIBwAAAA==.',
Gh='Ghasch:BAABNQAECn8cAAIcAAoK0BuGEgD6AgAcAAoK0BuGEgD6AgAAAA==.Ghume:BAAANQAECgQIDAAAAA==.',
Gi='Gianthippo:BAAANQADCgYICgABNQAECggIEgAIAAAAAA==.Gilf:BAACNQAFFH8LAAIaAAYK3h4lAQBjAQAaAAYK3h4lAQBjAQA1AAQKfyIAAxoACgptI9ABAJoDABoACgptI9ABAJoDAAwABAqCCIzsAL4AAAAA.',
Go='Goursh:BAAANQAECgEIAQAAAA==.',
Gr='Grizzoul:BAABNQAECn8cAAMUAAcKTgO9FADiAAAUAAcKTgO9FADiAAARAAMKxwEdNwBWAAAAAA==.Grreenry:BAAANQAECgEIAQAAAA==.Grumly:BAABNQAECn8dAAIbAAYKaw1RHgD6AAAbAAYKaw1RHgD6AAAAAA==.',
Ha='Hanswoloqued:BAACNQAFFH8HAAIXAAIKBwuTIQCNAAAXAAIKBwuTIQCNAAA1AAQKfy4AAhcACgqZFCtaAEgCABcACgqZFCtaAEgCAAAA.Haxz:BAAANQADCgUIBQAAAA==.',
He='Healufast:BAABNQAECn8vAAIVAAkK4B6eKgC+AgAVAAkK4B6eKgC+AgAAAA==.Heck:BAAANQADCgYIBgAAAA==.Helstrom:BAAANQAECgIIAgAAAA==.',
Hj='Hjalmar:BAABNQAECn8lAAMCAAkKMxo1TACwAQACAAgKDxo1TACwAQAEAAYKBA3tPQG9AAAAAA==.',
Ho='Holycõw:BAABNQAECn8dAAIEAAkKRBb/fgCPAQAEAAkKRBb/fgCPAQAAAA==.Holysabeline:BAABNQAECn89AAICAAoKxB9SHwDzAgACAAoKxB9SHwDzAgAAAA==.Hotpots:BAAANQAECggIEgAAAA==.Hotwíngs:BAAANQAECgYIBAAAAA==.',
Hu='Huchar:BAABNQAECn8/AAINAAoKwB8jBwBGAgANAAoKwB8jBwBGAgAAAA==.Humpf:BAAANQADCgEIAQAAAA==.Hunterpanda:BAAANQADCgYIBgAAAA==.',
Hy='Hydraxix:BAAANQADCggICAAAAA==.Hypnose:BAAANQADCggIFQAAAA==.',
Ic='Iceblade:BAABNQAECn8fAAICAAoKvBnGNAAWAgACAAoKvBnGNAAWAgAAAA==.',
Id='Idtrapdat:BAAANQAECgIIAgAAAA==.',
If='If:BAAANQADCgQIBAAAAA==.',
In='Incowgnito:BAAANQAECgcICgAAAA==.Invoice:BAAANQAECgUIBQAAAA==.',
Ir='Ironßest:BAAANQABCgUICwAAAA==.',
Ja='Jadzi:BAAANQADCgYJCwAAAA==.Jaxxion:BAAANQADCgYIBgAAAA==.',
Je='Jessaiyan:BAABNQAECn8UAAISAAoK2g8uGgCmAQASAAoK2g8uGgCmAQAAAA==.',
Jo='Jobo:BAABNQAECn8nAAMJAAoKkRAyGgDsAQAJAAoKkRAyGgDsAQAPAAUKZASNhgC4AAAAAA==.Jobodot:BAABNQAECn8YAAIXAAcKSwdVyQA3AQAXAAcKSwdVyQA3AQAAAA==.',
Ju='Julaudette:BAAANQAECgQIBQAAAA==.Juliania:BAAANQADCgYIBwAAAA==.Julzaria:BAABNQAECn8dAAIGAAoKUgy2VQDeAQAGAAoKUgy2VQDeAQAAAA==.Jurny:BAABNQAECn8oAAMBAAYKnxH+GwCNAQABAAYKnxH+GwCNAQAYAAIKVAVDJQBZAAAAAA==.',
Ka='Kahlandra:BAABNQAECn88AAIDAAoKJhaheQCLAgADAAoKJhaheQCLAgAAAA==.Kaizer:BAABNQAECn81AAIMAAkKLRkTNgCfAgAMAAkKLRkTNgCfAgAAAA==.Kandera:BAAANQADCgUIBQAAAA==.Karina:BAAANQADCgUJBQABNQAECgoKNQAGAB8kAA==.',
Ke='Keizer:BAAANQAECgEIAQAAAA==.Keunen:BAABNQAECn8ZAAMPAAYKGQa9WQCPAAAPAAYKGQa9WQCPAAAJAAMKdwK2dgAyAAAAAA==.Kevlock:BAAANQADCgYIBgAAAA==.Keyzer:BAAANQAECggIEQAAAA==.',
Kh='Khanjuror:BAAANQAECgEIAQAAAA==.Kharún:BAAANQAECgYIBgAAAA==.Khornedog:BAABNQAECn8yAAIXAAoKhBvaRADRAQAXAAoKhBvaRADRAQAAAA==.Khrama:BAABNQAECn86AAILAAoKZSVVCwBYAwALAAoKZSVVCwBYAwAAAA==.',
Kl='Kleenonean:BAACNQAFFH8YAAIeAAcKqSW3AQAIAgAeAAcKqSW3AQAIAgA1AAQKf5QAAh4ACgpgJicAAAsEAB4ACgpgJicAAAsEAAAA.',
Kn='Knut:BAAANQAECgEIAQAAAA==.',
Kr='Krackjarr:BAABNQAECn8hAAIXAAoKwgbfhAAeAQAXAAoKwgbfhAAeAQAAAA==.Kredor:BAAANQAECgIIBAAAAA==.Kriptskeeper:BAAANQAECgQIBAAAAA==.Kris:BAAANQAECgEIAQAAAA==.',
Ku='Kungpowbeef:BAAANQAECgIIAgAAAA==.Kurzaan:BAAANQAECgMIAwAAAA==.Kuyaj:BAAANQADCgIIAgAAAA==.',
La='Lacio:BAABNQAECn87AAIeAAoKwQf2MQCTAQAeAAoKwQf2MQCTAQAAAA==.Larune:BAAANQABCgEIAQAAAA==.',
Le='Lemonpepper:BAACNQAFFH8GAAIKAAMKCAYQDgCvAAAKAAMKCAYQDgCvAAA1AAQKfywAAgoACgrqEtUbAA0CAAoACgrqEtUbAA0CAAAA.Lexxix:BAAANQADCgcIDAAAAA==.Leyru:BAAANQAECgUIDAAAAA==.',
Li='Liberos:BAABNQAECn8dAAIcAAcKlBQVVACQAQAcAAcKlBQVVACQAQAAAA==.Lilnimjr:BAAANQADCgYICAAAAA==.Littlechiken:BAAANQADCgUIBQABNQAFFAUIDAALAIgMAA==.',
Ln='Lninedkhack:BAABNQAECn8jAAMHAAoKghprHgC8AQAHAAoKghprHgC8AQAOAAIK9Af1iABhAAAAAA==.',
Lo='Logaar:BAABNQAECn81AAMCAAoKqRFaTgAxAgACAAkKfBBaTgAxAgAEAAoK/QpYvQCiAQAAAA==.',
Lu='Lubuu:BAAANQADCggIFwAAAA==.Luckymagi:BAAANQAECgEIAQAAAA==.Lucyfurrawr:BAABNQAECn8aAAIfAAkKOBTMDgCLAQAfAAkKOBTMDgCLAQABNQAECgoKIgAQAM8ZAA==.Lunala:BAAANQADCgcIBwABNQAECgMIAgAIAAAAAA==.Luxurix:BAAANQADCggIEQAAAA==.',
Ma='Maellis:BAAANQAECgEIAQAAAA==.Maer:BAAANQADCgQIBAAAAA==.Magtao:BAAANQADCgYIEQAAAA==.Malexannius:BAAANQADCgYIDwAAAA==.Manastorm:BAABNQAECn8iAAIDAAoKWwZheACMAQADAAoKWwZheACMAQAAAA==.Maplebrick:BAAANQABCgIIAgAAAA==.Mariangel:BAAANQADCgEIAQAAAA==.Marric:BAAANQAECggJCgAAAA==.',
Me='Medean:BAAANQADCggICAAAAA==.Megtallica:BAABNQAECn8ZAAIEAAYKmAayCwGgAAAEAAYKmAayCwGgAAAAAA==.Mehunglow:BAAANQADCgUICAAAAA==.Mellissaa:BAAANQADCggIEgAAAA==.Mensrea:BAABNQAECn8oAAMMAAoKiQo8QQCUAQAMAAoKiQo8QQCUAQAcAAEKmwLw8AAmAAAAAA==.Merrycold:BAABNQAECn8dAAMHAAgKdxdQSwDoAQAHAAgKdxdQSwDoAQAOAAUKQxBAbADtAAABNQAECgoKHwAQALIYAA==.',
Mf='Mfgirthquake:BAABNQAECn9eAAMaAAoKMiVbAgAlAwAaAAoKMiVbAgAlAwAcAAYKCh16ggD6AAAAAA==.',
Mi='Miisty:BAAANQAECggIEAAAAA==.Mikklelee:BAAANQADCggIDwAAAA==.Mings:BAAANQAECgQICAAAAA==.Miniborohs:BAAANQAECgEIAQAAAA==.Mistweaver:BAABNQAECn9JAAIgAAoKySW6AwB0AwAgAAoKySW6AwB0AwAAAA==.',
Mo='Mochi:BAABNQAECn85AAIDAAoKvRcZRQAZAgADAAoKvRcZRQAZAgAAAA==.Mochïi:BAAANQADCgIJBAABNQAFFAcIFAADAIURAA==.Moghorva:BAAANQAECgcICwAAAA==.Mojoe:BAABNQAECn8jAAIcAAoK7Ro5MAChAgAcAAoK7Ro5MAChAgAAAA==.Mommyswaggin:BAAANQAECgQIBwAAAA==.Moopster:BAABNQAECn8wAAIVAAoKbSTMCgBsAwAVAAoKbSTMCgBsAwAAAA==.Moopy:BAAANQAECgQIBAABNQAECgoKMAAVAG0kAA==.Mootangclan:BAABNQAECn8XAAIMAAgKtxnkTQA/AgAMAAgKtxnkTQA/AgAAAA==.Moxi:BAAANQABCgUIBQAAAA==.',
Na='Nalthexon:BAAANQAECgUIBQAAAA==.Nanashi:BAACNQAFFH8GAAIOAAMKlAj4EQC+AAAOAAMKlAj4EQC+AAA1AAQKfykAAg4ACQoLIqAMANQCAA4ACQoLIqAMANQCAAAA.Nazgru:BAAANQADCgYIDAAAAA==.',
Ne='Necros:BAAANQAECgIIAgABNQAFFAcIGgAMAAMXAA==.Neiko:BAACNQAFFH8HAAMWAAIKxgwoCQCGAAAhAAIKQQsbGACNAAAWAAIKmwooCQCGAAA1AAQKfykAAxYACgr6GFwjAG0CABYACgoKF1wjAG0CACEABAoCHNleAD0BAAAA.Neptuneakis:BAABNQAECn8kAAIPAAcKzBGVUgCRAQAPAAcKzBGVUgCRAQAAAA==.Neptuno:BAAANQADCgEIAQABNQAECgcIJAAPAMwRAA==.Newcarsmell:BAAANQADCggIJgAAAA==.',
Ng='Ngl:BAAANQAECgcIEQAAAA==.',
Ni='Niceknife:BAAANQAECgEIAwAAAA==.Nicomi:BAAANQAECgUIBwAAAA==.Nightwinger:BAAANQAECgUICgAAAA==.Nimrose:BAAANQAECgIIBAAAAA==.Niquid:BAABNQAECn8nAAIJAAoK8hGzFgAZAgAJAAoK8hGzFgAZAgAAAA==.Nivek:BAAANQAECgQICAAAAA==.Niylea:BAAANQADCgUIBQABNQAECgoKLgAHAC8iAA==.',
No='Nobu:BAACNQAFFH8QAAMWAAUKByUgBAAKAgAWAAUKViEgBAAKAgAhAAIKXyEdHABdAAA1AAQKfz8AAxYACgpAJr4CALADABYACgrZJb4CALADACEACgqnImgJABcDAAAA.Noobhuntard:BAAANQADCggICAAAAA==.Norinari:BAACNQAFFH8KAAQXAAUKxxYAGAA1AQAXAAQKOBQAGAA1AQABAAIKyhKODgCZAAAYAAEKAADZDwBFAAA1AAQKfz0ABBgACgpSI4wEAJACABgABwoiI4wEAJACABcABwodI69BAI0CAAEAAwoKG+0vAAkBAAE1AAUUBggLABoA3h4A.Notahealer:BAAANQAECgcIEQABNQAECggIEwAIAAAAAA==.Noxloxes:BAAANQADCgIIAgAAAA==.',
Oa='Oakshre:BAABNQAECn88AAIQAAoKiR44CwAhAwAQAAoKiR44CwAhAwAAAA==.',
Ob='Obliteration:BAAANQAECgYIDQABNQAECgkJKQAQAFMhAA==.',
Od='Odsw:BAAANQADCgMJAwAAAA==.',
Oe='Oenaa:BAAANQAECgUIBAAAAA==.',
Ol='Olivertwist:BAAANQAECgQIDAABNQAECgkJKQAQAFMhAA==.',
On='Ontwou:BAABNQAECn8lAAIGAAoKaRxvYwBPAgAGAAoKaRxvYwBPAgAAAA==.',
Or='Orbz:BAABNQAECn9BAAIDAAoK+iT4KQA9AwADAAoK+iT4KQA9AwAAAA==.Orcazm:BAAANQAECgIIAQAAAA==.',
Pa='Padova:BAAANQAECgMIBAAAAA==.Palathal:BAAANQAECggIEQABNQAECgoKHQADAI8UAA==.Palyont:BAAANQAECgIIAgAAAA==.Pancakezebra:BAABNQAECn9GAAIiAAoKxxttAgCLAgAiAAoKxxttAgCLAgAAAA==.Parse:BAAANQAECgIIAwAAAA==.',
Pe='Perdido:BAAANQADCgIIAgAAAA==.',
Ph='Phoenix:BAABNQAECn8tAAIEAAoKbBvQggAiAgAEAAoKbBvQggAiAgAAAA==.',
Pi='Pikechu:BAAANQAECgYIEAAAAA==.Pinkskies:BAAANQAECgIIAgAAAA==.',
Pl='Playless:BAAANQAECgYIEQAAAA==.Pleasy:BAAANQAECgUIBwAAAA==.Plugtobacca:BAAANQADCgIIAgABNQAFFAUIEAAWAAclAA==.',
Po='Pocketchange:BAACNQAFFH8HAAMMAAQKsAsLEADRAAAMAAQKsAsLEADRAAAcAAIKzAiaHwBxAAA1AAQKfygAAxwACgqJF1BSAB0CABwACgqJF1BSAB0CAAwACAomEwtrAAwBAAAA.Pocketwatch:BAAANQAECgQIBwABNQAFFAQIBwAMALALAA==.',
Pr='Prayze:BAAANQADCgYIBgAAAA==.Preservation:BAAANQADCgIIAgABNQAECgoKSQAgAMklAA==.Promethêus:BAAANQAECgIIAQAAAA==.',
Pu='Purefriction:BAAANQADCgYICQAAAA==.Purehate:BAAANQAECgUIDAAAAA==.',
Qr='Qrz:BAAANQAECgEIAQAAAA==.',
Rb='Rbackwards:BAAANQADCgUIBQABNQAECgoKLgAXADEZAA==.',
Re='Relovan:BAABNQAECn8rAAMNAAoKSRSKEwBGAQANAAQKMRyKEwBGAQAjAAgK6gsNiAA9AQAAAA==.Renothidan:BAACNQAFFH8HAAIEAAIKiwq/HwB+AAAEAAIKiwq/HwB+AAA1AAQKfy0AAgQACgo+GiVcAIQCAAQACgo+GiVcAIQCAAAA.Ret:BAAANQADCgcICQABNQAECgoKXgAaADIlAA==.Reuben:BAAANQAECgEIAQAAAA==.Revin:BAABNQAECn8rAAIEAAoKXhecgQCJAQAEAAoKXhecgQCJAQAAAA==.Revrynth:BAABNQAECn8iAAQRAAgKohx2DwBjAgARAAgKohx2DwBjAgAKAAUKNhqnGAAtAQAUAAQKEBXjFADgAAAAAA==.Rexorcist:BAAANQAECgYICQAAAA==.',
Ri='Rimed:BAABNQAECn8bAAMDAAcKiw7f8ACpAQADAAcKMQ3f8ACpAQAbAAEKaBCvRwA1AAAAAA==.Rippèd:BAAANQADCgYIBgAAAA==.Rithcice:BAAANQADCgcIBwAAAA==.Rizzard:BAABNQAECn8YAAMMAAoK0hXrLADyAQAMAAoK0hXrLADyAQAcAAEKGgPv7wAnAAAAAA==.Rizzdolphler:BAACNQAFFH8JAAICAAQKtA5ZEwAsAQACAAQKtA5ZEwAsAQA1AAQKfzEAAwIACgq/HVEiAOMCAAIACgq/HVEiAOMCAAQABwo2DuncAOQAAAAA.',
Ro='Rorän:BAAANQAECgMIAwAAAA==.',
['Rö']='Rönburgundy:BAABNQAECn8uAAIXAAoKMRnwTABtAgAXAAoKMRnwTABtAgAAAA==.',
Sa='Sanako:BAAANQAECgcIDgAAAA==.Saneros:BAAANQAECgQIBAAAAA==.',
Sc='Scraggle:BAAANQAECgQIBQAAAA==.Scuffito:BAAANQAECgMIBAAAAA==.',
Sd='Sdh:BAAANQADCgEIAQAAAA==.',
Se='Seasondpally:BAAANQADCgcIBwAAAA==.Sermakan:BAAANQAECgEIAgAAAA==.Setheron:BAAANQAECgUIDgAAAA==.',
Sh='Shamnira:BAAANQAECgcICAAAAA==.Shamtul:BAAANQABCgYIEgAAAA==.Shlea:BAABNQAECn8nAAIUAAoKYAp4CwCoAQAUAAoKYAp4CwCoAQAAAA==.Shley:BAAANQADCgYIBgABNQAECgoKJwAUAGAKAA==.',
Si='Silvanna:BAAANQAECgYICgAAAA==.Sivi:BAAANQAECgIIAgAAAA==.',
Sl='Slinkstir:BAAANQADCgYIBgAAAA==.',
Sm='Smh:BAAANQAECgQIBAAAAA==.',
Sn='Sneak:BAAANQAECgQICgABNQAECgoKXgAaADIlAA==.',
So='Solendros:BAAANQAECgQIBAAAAA==.Sonoa:BAAANQAECggICgAAAA==.Sonthar:BAAANQADCgQJBAAAAA==.Sorix:BAAANQADCgIIAgAAAA==.Sorlight:BAABNQAECn8XAAIZAAcKkBwCGwAWAgAZAAcKkBwCGwAWAgAAAA==.Soulelf:BAAANQADCgEIAQAAAA==.Sourpets:BAABNQAECn8VAAIGAAcKURqJWABqAgAGAAcKURqJWABqAgAAAA==.Sourshocks:BAAANQAECgEIAwAAAA==.Sourwords:BAAANQAECgEIAQAAAA==.',
St='Standarshh:BAABNQAECn84AAIGAAoK0R+IJwD6AgAGAAoK0R+IJwD6AgAAAA==.Stevenz:BAABNQAECn8oAAIDAAoKiiCPKQA+AwADAAoKiiCPKQA+AwAAAA==.Stillflygon:BAAANQADCgYIEgAAAA==.Stormcare:BAAANQADCgUIBQAAAA==.',
Su='Subtle:BAACNQAFFH8IAAMWAAMK4xPJBADeAAAWAAMK4xPJBADeAAAhAAEKYwEEFwA4AAA1AAQKfy8AAxYACQpJHlMgAH8CABYACQpJHlMgAH8CACEABgrlFKojAKsBAAAA.Sugarbabi:BAAANQAECggIEwAAAA==.Sugarrush:BAAANQAECgIIBAAAAA==.Sugarshot:BAAANQAECgIIAgAAAA==.Sugartotem:BAAANQAECgUIDgAAAA==.Sunmere:BAAANQADCgUIBQAAAA==.',
Sw='Swiftwing:BAAANQADCgQIBAAAAA==.',
Sy='Sydarliia:BAAANQAECgYIEAAAAA==.Sylrianah:BAABNQAECn89AAIVAAoK6g/rYwD0AQAVAAoK6g/rYwD0AQAAAA==.Sylveste:BAACNQAFFH8NAAICAAYKYQpxCACaAQACAAYKYQpxCACaAQA1AAQKfy8AAgIACgoAHBcbALICAAIACgoAHBcbALICAAAA.',
Ta='Tae:BAAANQAECgcICAAAAA==.Tal:BAAANQAECggIEAABNQAECgkJHQAEAEQWAA==.Talis:BAAANQAECgEIAQAAAA==.Talridor:BAAANQADCgcIBgAAAA==.Tankhiskhan:BAAANQAECggIEgAAAA==.Tarlis:BAAANQAECggIDgAAAA==.',
Te='Tei:BAAANQAECggIDQAAAA==.Terily:BAAANQADCgcICgAAAA==.',
Th='Thannill:BAABNQAECn8sAAIHAAkKDhQ9HQDHAQAHAAkKDhQ9HQDHAQAAAA==.',
Ti='Ticktoklock:BAAANQAECggIDAAAAA==.Tie:BAABNQAECn8xAAIZAAkKJhvzCgBVAgAZAAkKJhvzCgBVAgAAAA==.Tirala:BAABNQAECn8WAAIdAAoKMiKgCQDjAgAdAAoKMiKgCQDjAgAAAA==.',
To='Tomari:BAAANQABCgEIAQAAAA==.Tomias:BAAANQADCgMIAwAAAA==.Torzhu:BAAANQAECgUIEwAAAA==.Toy:BAAANQAECggIDwABNQAFFAgIGgAKAJoTAA==.',
Tr='Trauck:BAAANQAECgUIEQAAAA==.Travvy:BAACNQAFFH89AAMhAAkKvyFqAADhAgAWAAkKoBhsAAAyAwAhAAkKJyFqAADhAgA1AAQKfyYAAyEACgqHJrUDAGMDACEACgouIrUDAGMDABYAAwr2IAxmABoBAAAA.Trevmo:BAABNQAECn8lAAMjAAoKqxT6cABBAgAjAAoK3hH6cABBAgANAAYKPxPeFgAfAQAAAA==.Trexin:BAAANQAECgIIAwAAAA==.',
Tu='Turaylon:BAAANQADCgQIBAAAAA==.',
Tz='Tzuyu:BAABNQAECn81AAMGAAoKHySlCACXAwAGAAoKHySlCACXAwAFAAEKIxGwhwA2AAAAAA==.',
Ud='Uddershock:BAAANQAECgUIBQAAAA==.',
Un='Unapologetic:BAAANQAECgUIBQABNQAECgoKSQAgAMklAA==.Unbreakabull:BAACNQAFFH8FAAIPAAMKUhyCCwAAAQAPAAMKUhyCCwAAAQA1AAQKfyUAAg8ACgqgI4QHAJUDAA8ACgqgI4QHAJUDAAAA.Unver:BAAANQADCgYIBgAAAA==.',
Va='Vae:BAAANQAECgYJEQABNQAECgoKIgAQAM8ZAA==.Valka:BAAANQAECgEIAQAAAA==.Vanthrall:BAAANQADCgUIBQAAAA==.',
Ve='Veldtt:BAAANQADCgIIAgAAAA==.Velera:BAABNQAECn8eAAIDAAkKkgcLkgBUAQADAAkKkgcLkgBUAQAAAA==.Vesemir:BAAANQADCgcIBwAAAA==.Veyle:BAABNQAECn89AAMWAAoKsyMhAgC/AwAWAAoKsyMhAgC/AwAhAAYK1B00HQDpAQAAAA==.',
Vi='Viibryd:BAAANQAECgQICAAAAA==.Vine:BAAANQAECgUIBAAAAA==.',
Vy='Vyel:BAAANQADCgIIAgAAAA==.Vyndria:BAAANQADCgcIDQAAAA==.Vynstus:BAAANQADCggIHAAAAA==.Vyran:BAAANQADCgIIAgAAAA==.',
Wa='Waypal:BAAANQADCggIFwAAAA==.',
We='Weashadow:BAAANQAECgcICwAAAA==.Weashock:BAAANQADCgYIDAAAAA==.Weasy:BAABNQAECn8UAAIGAAgKyiC3NADNAgAGAAgKyiC3NADNAgAAAA==.',
Wi='Windfury:BAABNQAECn8wAAIaAAoKqSJCAgCJAwAaAAoKqSJCAgCJAwAAAA==.Wingzard:BAABNQAECn8fAAIDAAgKZxV4tAAaAgADAAgKZxV4tAAaAgAAAA==.',
Wo='Wowdudesame:BAABNQAECn8XAAIjAAcKCR2KagBRAgAjAAcKCR2KagBRAgABNQAECgoKXgAaADIlAA==.',
Xl='Xl:BAABNQAECn8xAAIdAAoKYBoJIwCDAgAdAAoKYBoJIwCDAgAAAA==.',
Ya='Yaitoopmfp:BAABNQAECn8fAAQQAAoKshjRGQBzAgAQAAkKPhjRGQBzAgAgAAcKbg/RFQBkAQAkAAEKvBxJHgBUAAAAAA==.Yao:BAABNQAECn86AAMLAAoK2yGWDgA6AwALAAoK2yGWDgA6AwAHAAEKAAAK2wA6AAAAAA==.Yasrena:BAABNQAECn8rAAMVAAoK8w05VgCoAQAVAAoK8w05VgCoAQAeAAcKYhA1JgAVAQAAAA==.',
Ye='Yelp:BAAANQAECgYICwAAAA==.',
Za='Zabara:BAAANQADCgYIBgABNQAECgkJJQACADMaAA==.Zair:BAAANQADCgUIBQAAAA==.Zakaraki:BAABNQAECn89AAMRAAoK0SF0BgAiAwARAAoK0SF0BgAiAwAKAAgK8hUvGgAgAgAAAA==.Zaki:BAABNQAECn8dAAISAAoKyxWWFwChAgASAAoKyxWWFwChAgAAAA==.Zalujin:BAAANQAECgEIAQAAAA==.Zappin:BAAANQAECggIDgABNQAFFAUIEAAWAAclAA==.',
Ze='Zealot:BAABNQAECn8dAAMEAAkKKBBBvACkAQAEAAkKABBBvACkAQAZAAYK6wgjSADNAAAAAA==.Zeleria:BAAANQAECgMIAgAAAA==.Zerathis:BAAANQADCgEJAQAAAA==.Zerro:BAAANQAECgEIAQAAAA==.',
Zi='Zinbek:BAAANQADCgUIBQAAAA==.Zip:BAAANQABCgYJBgAAAA==.Zipstin:BAAANQAECgEIAQAAAA==.',
Zo='Zo:BAAANQAECgMIBgAAAA==.Zoo:BAAANQAECgIIAgAAAA==.Zorb:BAABNQAECn81AAIPAAoK/xrfFAAgAwAPAAoK/xrfFAAgAwABNQAFFAIIBQAXALsIAA==.Zoshow:BAAANQAECgUICgAAAA==.Zoshôw:BAAANQAECgcIBwAAAA==.',
['Zõ']='Zõshow:BAAANQAECgQIBwAAAA==.',
['Ða']='Ðaredevil:BAABNQAECn8iAAIQAAoKzxkkEgDMAgAQAAoKzxkkEgDMAgAAAA==.',
['Ðp']='Ðp:BAABNQAECn8WAAISAAgKmQhAOQB7AQASAAgKmQhAOQB7AQAAAA==.',
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
