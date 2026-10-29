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
local provider = {region='US',realm='Bloodscalp',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abbpriest:BAAANQADCgYJBgABNQAECggJGQABAOYYAA==.Abruum:BAAANQADCgcIDAAAAA==.',
Ad='Admetus:BAABNQAECn8nAAICAAoKfh7nEADJAgACAAoKfh7nEADJAgAAAA==.Adobe:BAAANQADCggIGwAAAA==.',
Am='Amapriest:BAAANQAECgMIAwABNQAECgoKGAADAKcQAA==.Amathal:BAABNQAECn8YAAIDAAoKpxCopAA4AgADAAoKpxCopAA4AgAAAA==.',
An='Anderson:BAAANQADCgQIBAAAAA==.Ankheloios:BAAANQAECgUIDgAAAA==.',
Ar='Arcanehonkey:BAAANQADCggICAAAAA==.Aredhela:BAABNQAECn8bAAIEAAgKZxUdkQACAgAEAAgKZxUdkQACAgAAAA==.Arias:BAAANQAECgQIBAAAAA==.Armsdealer:BAAANQADCgUIBQAAAA==.Arro:BAAANQAECgEIAQAAAA==.',
As='Ascending:BAAANQAECgQICAAAAA==.Asha:BAACNQAFFH8UAAIFAAYKpxblBAA0AQAFAAYKpxblBAA0AQA1AAQKfyoAAwUACgrCHOoRANYCAAUACgrCHOoRANYCAAYAAQqxAV1sASYAAAAA.Ashveil:BAAANQADCgQIBAABNQAECgoKIwAHAIIaAA==.Astrialynn:BAAANQADCgYIBwABNQADCgcIBwAIAAAAAA==.Astrulawa:BAAANQAECgQICgAAAA==.',
At='Athrea:BAABNQAECn8qAAIHAAoKUCH8IwCyAgAHAAoKUCH8IwCyAgAAAA==.',
Av='Avasharm:BAAANQABCgYIBgABNQABCgYIAgAIAAAAAA==.',
Ba='Barakah:BAAANQAECgQIAwAAAA==.Barnre:BAAANQAECgIIBAAAAA==.Battlelord:BAAANQAECgIIBAAAAA==.',
Bd='Bdssm:BAAANQAECgcIBwAAAA==.',
Be='Bearito:BAAANQAECgQIDwAAAA==.Beefstick:BAABNQAECn8fAAIGAAkKshLIhwD7AQAGAAkKshLIhwD7AQAAAA==.Beserkfury:BAABNQAECn8pAAIFAAgK7gosGQA+AQAFAAgK7gosGQA+AQAAAA==.',
Bi='Biercan:BAAANQAECgYIDAAAAA==.Bigcarl:BAAANQAECgEIAQAAAA==.Binke:BAAANQADCgQIBAAAAA==.Bittyboop:BAAANQADCgYICwABNQAECgIIAwAIAAAAAA==.Bittywhite:BAAANQAECgIIAwAAAA==.Bittywyvern:BAAANQADCgUIBQABNQAECgIIAwAIAAAAAA==.',
Bj='Bjarna:BAAANQAECgQIBwABNQAECgUIBQAIAAAAAA==.',
Bl='Blayze:BAAANQAECgUICQAAAA==.Blinkytime:BAABNQAECn8kAAIEAAgKuBP0rwC/AQAEAAgKuBP0rwC/AQAAAA==.Bloodskull:BAAANQADCgEIAQAAAA==.Blúnt:BAAANQADCgQIBAAAAA==.',
Bo='Bobheals:BAABNQAECn8xAAIJAAoKpxoVDAB0AgAJAAoKpxoVDAB0AgAAAA==.Boibye:BAAANQAECgQICwAAAA==.Bolblock:BAAANQAECggIDwAAAA==.Bolo:BAACNQAFFH8KAAIKAAMKZhDfCgC7AAAKAAMKZhDfCgC7AAA1AAQKfzYAAgoACgqdH6kHACsDAAoACgqdH6kHACsDAAAA.Boostedww:BAAANQAECgQICwAAAA==.Borkoir:BAAANQAECgUIBQAAAA==.Bowlo:BAAANQAECgUIBQAAAA==.',
Br='Brambleclaw:BAABNQAECn83AAILAAoKyB5FDABQAwALAAoKyB5FDABQAwAAAA==.Brayker:BAABNQAECn83AAIEAAoKDCE6IgA7AwAEAAoKDCE6IgA7AwAAAA==.Breadoneal:BAABNQAECn8pAAMCAAgK+xleIwAvAgACAAgK+xleIwAvAgAEAAMKqQasXQGKAAAAAA==.Brewed:BAAANQAECgMIBAAAAA==.Brynjamin:BAAANQAECgQICAAAAA==.Brüenor:BAAANQAECgMIBQAAAA==.',
Bu='Bubbi:BAAANQADCgEIAQAAAA==.Bukkorosuzo:BAAANQAECgMICQAAAA==.Burntroot:BAABNQAECn8dAAIMAAcK5APuuAAgAQAMAAcK5APuuAAgAQAAAA==.',
['Bá']='Bálor:BAAANQAECgUIDgAAAA==.',
Ca='Cacci:BAAANQADCgcIBwAAAA==.Caedwyn:BAAANQAECgYIEAAAAA==.Camdakablam:BAAANQAECgcIEQAAAA==.Careadin:BAAANQADCgQIBAABNQAECggIGwANAGsgAA==.Careradin:BAABNQAECn8bAAINAAgKayBaDABwAgANAAgKayBaDABwAgAAAA==.Carereaper:BAAANQAECgEIAQABNQAECggIGwANAGsgAA==.Cartilage:BAABNQAECn8XAAMHAAkKcgwbKwAnAQAHAAkKBwwbKwAnAQAOAAUKSA0MbQDqAAAAAA==.Cassieruth:BAAANQAECggICgAAAA==.Catalei:BAAANQAECgEIAQAAAA==.',
Ce='Centrest:BAAANQADCgYJCAAAAA==.',
Ch='Chebbles:BAAANQADCgUIBgABNQAECgcIIgAPAMwRAA==.Chillidan:BAAANQAECgMIAwABNQAECgkJKQAQAFMhAA==.Chivi:BAAANQADCggIDgABNQAECggIIgARAKIcAA==.Chonkmonk:BAAANQADCgQIBAAAAA==.Chupacabrass:BAAANQAECgIIAgAAAA==.Chëbbles:BAAANQAECgMIAwABNQAECgcIIgAPAMwRAA==.',
Co='Colman:BAAANQAECgMICQAAAA==.Coorsbanquet:BAABNQAECn8ZAAMSAAcKOg8eNgCSAQASAAcKOg8eNgCSAQATAAUK/wxuEwCpAAABNQAECgcIGwAKAHUTAA==.Coorsbite:BAABNQAECn8bAAQKAAcKdROBFgAHAQAKAAQKvxWBFgAHAQARAAUKmQgVKQDlAAAUAAcKEQ/5CgDYAAAAAA==.Coorslight:BAAANQADCgYIBgABNQAECgcIGwAKAHUTAA==.Corrahthecow:BAAANQAECgEIAQABNQAECgcIGwAKAHUTAA==.',
Cr='Craccjar:BAAANQADCgYIBwAAAA==.Crackjar:BAAANQADCgUICAAAAA==.Croc:BAAANQAECgYIEAAAAA==.Crudala:BAAANQADCgcICQABNQAECgMIAgAIAAAAAA==.Crystle:BAABNQAECn8hAAIVAAoKNwojNQDmAQAVAAoKNwojNQDmAQAAAA==.Crystlemarie:BAAANQADCgMIAwAAAA==.',
Cs='Csyasha:BAAANQADCgcIBwABNQAECgoKGgAWAA4KAA==.',
Cu='Cubcadet:BAABNQAECn8hAAIEAAoKWhmXSQC4AgAEAAoKWhmXSQC4AgAAAA==.',
Cy='Cybear:BAABNQAECn8fAAIXAAoK8xifHwBAAgAXAAoK8xifHwBAAgAAAA==.',
Da='Dalanora:BAABNQAECn83AAQXAAoKMhp3JgDqAgAXAAoKMhp3JgDqAgABAAMKXRUdQwC4AAAYAAMKpBafGwCkAAAAAA==.Dammned:BAAANQAECgMIBAAAAA==.Dapalyu:BAABNQAECn8pAAMZAAoKQQ5CKwCDAQAZAAkKmw5CKwCDAQAEAAgKYQX1EwH+AAAAAA==.Davidx:BAAANQADCgQIBgAAAA==.',
De='Dekig:BAAANQAECgEIAQAAAA==.Demine:BAAANQAECgMIBAAAAA==.Detrazeral:BAAANQADCggIEAAAAA==.',
Di='Dico:BAAANQAECgcICgABNQAFFAcIGwANAB8XAA==.Dipper:BAABNQAECn8yAAIEAAoKkhacegA2AgAEAAoKkhacegA2AgAAAA==.',
Do='Dohan:BAAANQADCggIEAAAAA==.Dorìan:BAAANQADCggIFgAAAA==.Dorÿ:BAAANQADCgcIBwAAAA==.',
Dr='Draetona:BAAANQADCggIGQAAAA==.Druidthings:BAAANQADCgUIBQAAAA==.',
Ee='Eeveeko:BAABNQAECn8uAAIaAAoK6xcCDACwAgAaAAoK6xcCDACwAgAAAA==.',
Ej='Ejavuday:BAABNQAECn8wAAMDAAoKhR5CQQACAwADAAoKhR5CQQACAwAbAAEKgR2cRwA1AAAAAA==.',
En='Enerchi:BAABNQAECn8pAAIQAAkKUyF8CgArAwAQAAkKUyF8CgArAwAAAA==.',
Er='Erianar:BAAANQADCgEIAQAAAA==.Ervyne:BAABNQAECn8iAAMGAAoKvhCTbAA5AgAGAAoKnRCTbAA5AgAFAAUKmAaaUgDeAAAAAA==.',
Ev='Evera:BAABNQAECn8ZAAIHAAkKXQp7agBoAQAHAAkKXQp7agBoAQAAAA==.Evos:BAAANQADCgYJBgAAAA==.',
Ex='Exning:BAAANQADCggICAAAAA==.',
Fa='Fatherømally:BAAANQAECggIBAABNQAECgkJHQAEAEQWAA==.Fauci:BAAANQAECgYIBgABNQAFFAUIEAAWAAclAA==.',
Fe='Feihao:BAAANQAECgEIAQAAAA==.Feile:BAABNQAECn8tAAMXAAoKog6vawAaAgAXAAoKog6vawAaAgABAAEKAAArcQA+AAAAAA==.Feltree:BAAANQADCgQIBAAAAA==.',
Fi='Fishbox:BAAANQABCgYIDAAAAA==.',
Fl='Flashir:BAAANQADCgIIAgAAAA==.Flinzza:BAABNQAECn8jAAMaAAkKNhZ3GADgAQAaAAgKsRZ3GADgAQAcAAgK2hSnaQDPAQAAAA==.Flyknit:BAABNQAECn8XAAIEAAYKZRKc2gBmAQAEAAYKZRKc2gBmAQAAAA==.',
Fr='Fredthedh:BAABNQAECn8hAAMSAAoKixeVIwAsAgASAAgKXxeVIwAsAgAdAAUKChZWSwCZAAAAAA==.Fromtheback:BAAANQAECgIIAgAAAA==.Frosticals:BAABNQAECn8tAAIDAAkK4CEvQAAFAwADAAkK4CEvQAAFAwAAAA==.Frostsugar:BAAANQABCgQIBgAAAA==.',
Ga='Gaashw:BAAANQABCgQIBwAAAA==.Gabtvsorcere:BAAANQADCgYICQAAAA==.Ganandor:BAABNQAECn8kAAIWAAoKVBzaGwCfAgAWAAoKVBzaGwCfAgAAAA==.Gaulish:BAAANQAECgEIAgAAAA==.',
Ge='Geocide:BAABNQAECn8VAAIMAAcKVB3oVgAeAgAMAAcKVB3oVgAeAgAAAA==.Getagrip:BAAANQAECgIIBAABNQAFFAMICAAWAOMTAA==.Gethalyn:BAAANQAECgUIBwAAAA==.',
Gh='Ghasch:BAABNQAECn8cAAIcAAoK0BvACwAJAwAcAAoK0BvACwAJAwAAAA==.Ghume:BAAANQAECgQIDAAAAA==.',
Gi='Gianthippo:BAAANQADCgYICgAAAA==.Gilf:BAACNQAFFH8GAAIaAAUKYR/UAQDiAQAaAAUKYR/UAQDiAQA1AAQKfx4AAxoACQq6I9ABAJoDABoACQq6I9ABAJoDAAwABAqCCIzsAL4AAAE1AAUUBQgKABcAxxYA.',
Go='Goursh:BAAANQAECgEIAQAAAA==.',
Gr='Grizzoul:BAABNQAECn8bAAMUAAcKTgO9FADiAAAUAAcKTgO9FADiAAARAAMKxwEdNwBWAAAAAA==.Grreenry:BAAANQAECgEIAQAAAA==.Grumly:BAABNQAECn8XAAIbAAYKDgxRHgD6AAAbAAYKDgxRHgD6AAAAAA==.',
Ha='Hanswoloqued:BAACNQAFFH8FAAIXAAIKcwhBHACFAAAXAAIKcwhBHACFAAA1AAQKfyoAAhcACgpmFCtaAEgCABcACgpmFCtaAEgCAAAA.Haxz:BAAANQADCgUIBQAAAA==.',
He='Healufast:BAABNQAECn8nAAIVAAkK4B6eKgC+AgAVAAkK4B6eKgC+AgAAAA==.Heck:BAAANQADCgYIBgAAAA==.Helstrom:BAAANQADCggIEgAAAA==.',
Hj='Hjalmar:BAABNQAECn8iAAMCAAgKXRlhZgDkAQACAAcKFRlhZgDkAQAEAAYKOgftPQG9AAAAAA==.',
Ho='Holycõw:BAABNQAECn8dAAIEAAkKRBbkYACYAQAEAAkKRBbkYACYAQAAAA==.Holysabeline:BAABNQAECn83AAICAAoKdB1SHwDzAgACAAoKdB1SHwDzAgAAAA==.Hotpots:BAAANQAECggIEgAAAA==.',
Hu='Huchar:BAABNQAECn87AAINAAoK5x2vBQAtAgANAAoK5x2vBQAtAgAAAA==.Humpf:BAAANQADCgEIAQAAAA==.Hunterpanda:BAAANQADCgYIBgAAAA==.',
Hy='Hydraxix:BAAANQADCggICAAAAA==.Hypnose:BAAANQADCggIDgAAAA==.',
Ic='Iceblade:BAABNQAECn8ZAAICAAoKqBf4MQDaAQACAAoKqBf4MQDaAQAAAA==.',
Id='Idtrapdat:BAAANQAECgIIAgAAAA==.',
If='If:BAAANQADCgQIBAAAAA==.',
In='Incowgnito:BAAANQAECgcICQAAAA==.',
Ir='Ironßest:BAAANQABCgUICwAAAA==.',
Ja='Jadzi:BAAANQADCgYJCwAAAA==.Jaxxion:BAAANQADCgYIBgAAAA==.',
Je='Jensthyra:BAAANQABCgcICgAAAA==.Jessaiyan:BAABNQAECn8UAAISAAoK2g9REwC2AQASAAoK2g9REwC2AQAAAA==.',
Jo='Jobo:BAABNQAECn8dAAMJAAkKZw6TGACsAQAJAAkKZw6TGACsAQAPAAUKZASNhgC4AAAAAA==.Jobodot:BAABNQAECn8YAAIXAAcKSwdVyQA3AQAXAAcKSwdVyQA3AQAAAA==.',
Ju='Julaudette:BAAANQADCggIHgAAAA==.Juliania:BAAANQADCgYIBwAAAA==.Julzaria:BAAANQAECgYIEgAAAA==.Jurny:BAABNQAECn8jAAMBAAYKnxH+GwCNAQABAAYKnxH+GwCNAQAYAAIKVAVDJQBZAAAAAA==.',
Ka='Kahlandra:BAABNQAECn82AAIDAAoKShWheQCLAgADAAoKShWheQCLAgAAAA==.Kaizer:BAABNQAECn81AAIMAAkKLRkTNgCfAgAMAAkKLRkTNgCfAgAAAA==.Kandera:BAAANQADCgUIBQAAAA==.Karina:BAAANQADCgUJBQABNQAECgoKLwAGAHohAA==.',
Ke='Keizer:BAAANQAECgEIAQAAAA==.Keunen:BAABNQAECn8VAAMPAAYKGQZmSwCYAAAPAAYKGQZmSwCYAAAJAAMKdwK2dgAyAAAAAA==.Kevlock:BAAANQADCgYIBgAAAA==.Keyzer:BAAANQAECgcIEQAAAA==.',
Kh='Khanjuror:BAAANQAECgEIAQAAAA==.Kharún:BAAANQAECgYIBAAAAA==.Khornedog:BAABNQAECn8tAAIXAAoKGxrEMgDgAQAXAAoKGxrEMgDgAQAAAA==.Khrama:BAABNQAECn82AAILAAoKQiVVCwBYAwALAAoKQiVVCwBYAwAAAA==.',
Kl='Kleenonean:BAACNQAFFH8XAAIeAAYKxCUgAgCnAQAeAAYKxCUgAgCnAQA1AAQKf4wAAh4ACgpgJicAAAsEAB4ACgpgJicAAAsEAAAA.',
Kn='Knut:BAAANQADCggIEAAAAA==.',
Kr='Krackjarr:BAABNQAECn8aAAIXAAkKkAaJ0gAlAQAXAAkKkAaJ0gAlAQAAAA==.Kredor:BAAANQAECgIIBAAAAA==.',
Ku='Kungpowbeef:BAAANQAECgIIAgAAAA==.Kurzaan:BAAANQAECgMIAgAAAA==.Kuyaj:BAAANQADCgIIAgAAAA==.',
La='Lacio:BAABNQAECn81AAIeAAoKwAf2MQCTAQAeAAoKwAf2MQCTAQAAAA==.Larune:BAAANQABCgEIAQAAAA==.',
Le='Lemonpepper:BAACNQAFFH8FAAIKAAIKwgdCDgBuAAAKAAIKwgdCDgBuAAA1AAQKfygAAgoACgrqEtUbAA0CAAoACgrqEtUbAA0CAAAA.Lexxix:BAAANQADCgcIDAAAAA==.Leyru:BAAANQAECgUIDAAAAA==.',
Li='Liberos:BAABNQAECn8cAAIcAAcKBBTRTABiAQAcAAcKBBTRTABiAQAAAA==.Littlechiken:BAAANQADCgUIBQABNQAFFAUICgALAIgMAA==.',
Ln='Lninedkhack:BAABNQAECn8jAAMHAAoKghqsFgDKAQAHAAoKghqsFgDKAQAOAAIK9AeLdQBjAAAAAA==.',
Lo='Logaar:BAABNQAECn80AAMCAAoKMxFaTgAxAgACAAkK+Q9aTgAxAgAEAAoK/QpYvQCiAQAAAA==.',
Lu='Lubuu:BAAANQADCggIFwAAAA==.Lucyfurrawr:BAABNQAECn8aAAIfAAkKOBSlCQCoAQAfAAkKOBSlCQCoAQABNQAECgoKIgAQAM8ZAA==.Lunala:BAAANQADCgcIBwABNQAECgMIAgAIAAAAAA==.Luxurix:BAAANQADCggIEQAAAA==.',
Ma='Maer:BAAANQADCgQIBAAAAA==.Magtao:BAAANQADCgYIEQAAAA==.Malexannius:BAAANQADCgYIDwAAAA==.Manastorm:BAABNQAECn8ZAAIDAAkKUAXqhwAzAQADAAkKUAXqhwAzAQAAAA==.Maplebrick:BAAANQABCgIIAgAAAA==.Mariangel:BAAANQADCgEIAQAAAA==.Marric:BAAANQAECggJCgAAAA==.',
Me='Medean:BAAANQADCggICAAAAA==.Megtallica:BAABNQAECn8XAAIEAAYK9wWz8QCSAAAEAAYK9wWz8QCSAAAAAA==.Mehunglow:BAAANQADCgUICAAAAA==.Mellissaa:BAAANQADCggIEgAAAA==.Mensrea:BAABNQAECn8iAAMMAAoKiQq7LwCbAQAMAAoKiQq7LwCbAQAcAAEKmwLZ1AAnAAAAAA==.Merrycold:BAABNQAECn8dAAMHAAgKdxdQSwDoAQAHAAgKdxdQSwDoAQAOAAUKQxBAbADtAAABNQAECgoKHwAQALIYAA==.',
Mf='Mfgirthquake:BAABNQAECn9RAAMaAAoKMiW7AQAlAwAaAAoKMiW7AQAlAwAcAAQKfhrc3gCrAAAAAA==.',
Mi='Miisty:BAAANQAECgcIDAAAAA==.Mikklelee:BAAANQADCggIDwAAAA==.Mings:BAAANQAECgQICAAAAA==.Miniborohs:BAAANQAECgEIAQAAAA==.Mistweaver:BAABNQAECn87AAIgAAoKMSW6AwB0AwAgAAoKMSW6AwB0AwAAAA==.',
Mo='Mochi:BAABNQAECn8xAAIDAAoKvRfjNAAeAgADAAoKvRfjNAAeAgAAAA==.Mochïi:BAAANQADCgIJBAABNQAFFAcIFAADAIURAA==.Moghorva:BAAANQAECgIIAQAAAA==.Mojoe:BAABNQAECn8fAAIcAAkKRB05MAChAgAcAAkKRB05MAChAgAAAA==.Mommyswaggin:BAAANQAECgQIBwAAAA==.Moopster:BAABNQAECn8tAAIVAAoKISTMCgBsAwAVAAoKISTMCgBsAwAAAA==.Moopy:BAAANQAECgQIBAABNQAECgoKLQAVACEkAA==.Mootangclan:BAABNQAECn8XAAIMAAgKtxnkTQA/AgAMAAgKtxnkTQA/AgAAAA==.Moxi:BAAANQABCgUIBQAAAA==.',
Na='Nanashi:BAACNQAFFH8GAAIOAAMKlAj4EQC+AAAOAAMKlAj4EQC+AAA1AAQKfx8AAg4ACQpmH6kWANYCAA4ACQpmH6kWANYCAAAA.Nazgru:BAAANQADCgYIDAAAAA==.',
Ne='Necros:BAAANQAECgIIAgABNQAFFAcIGgAMAAMXAA==.Neiko:BAACNQAFFH8FAAMWAAIKxgwnBwCPAAAWAAIKmwonBwCPAAAhAAIKOwnSEwCHAAA1AAQKfyUAAxYACgr6GFwjAG0CABYACgoKF1wjAG0CACEABAp9GjxNACgBAAAA.Neptuneakis:BAABNQAECn8iAAIPAAcKzBHjMQAKAQAPAAcKzBHjMQAKAQAAAA==.Neptuno:BAAANQADCgEIAQABNQAECgcIIgAPAMwRAA==.Newcarsmell:BAAANQADCggIJgAAAA==.',
Ng='Ngl:BAAANQAECgQIBgAAAA==.',
Ni='Niceknife:BAAANQADCggIDQAAAA==.Nightwinger:BAAANQAECgQICAAAAA==.Nimrose:BAAANQAECgIIBAAAAA==.Niquid:BAABNQAECn8lAAIJAAoK8hH1DwAoAgAJAAoK8hH1DwAoAgAAAA==.Nivek:BAAANQAECgQICAAAAA==.Niylea:BAAANQADCgUIBQABNQAECgoKKgAHAFAhAA==.',
No='Nobu:BAACNQAFFH8QAAMWAAUKByUgBAAKAgAWAAUKViEgBAAKAgAhAAIKXyGBFgBdAAA1AAQKfzUAAxYACgoNJr4CALADABYACgqmJb4CALADACEACgqnIjUHABEDAAAA.Noobhuntard:BAAANQADCggICAAAAA==.Norinari:BAACNQAFFH8KAAQXAAUKxxYAGAA1AQAXAAQKOBQAGAA1AQABAAIKyhKODgCZAAAYAAEKAADZDwBFAAA1AAQKfzwABBgACgpSI4wEAJACABgABwoiI4wEAJACABcABwodI69BAI0CAAEAAwoKG+0vAAkBAAAA.Notahealer:BAAANQAECgcIEQAAAA==.Noxloxes:BAAANQADCgIIAgAAAA==.',
Oa='Oakshre:BAABNQAECn82AAIQAAoKKh04CwAhAwAQAAoKKh04CwAhAwAAAA==.',
Ob='Obliteration:BAAANQAECgYIDQABNQAECgkJKQAQAFMhAA==.',
Od='Odsw:BAAANQADCgMJAwAAAA==.',
Oe='Oenaa:BAAANQABCgQIBAAAAA==.',
Ol='Olivertwist:BAAANQAECgQIDAABNQAECgkJKQAQAFMhAA==.',
On='Ontwou:BAABNQAECn8hAAIGAAkKExxvYwBPAgAGAAkKExxvYwBPAgAAAA==.',
Or='Orbz:BAABNQAECn86AAIDAAoKKST4KQA9AwADAAoKKST4KQA9AwAAAA==.Orcazm:BAAANQAECgIIAQAAAA==.',
Pa='Padova:BAAANQAECgMIAwAAAA==.Palathal:BAAANQAECgQICAABNQAECgoKGAADAKcQAA==.Palyont:BAAANQAECgIIAgAAAA==.Pancakezebra:BAABNQAECn89AAIiAAoKrBvIAQCDAgAiAAoKrBvIAQCDAgAAAA==.Parse:BAAANQAECgIIAwAAAA==.',
Pe='Perdido:BAAANQADCgIIAgAAAA==.',
Ph='Phoenix:BAABNQAECn8tAAIEAAoKbBvQggAiAgAEAAoKbBvQggAiAgAAAA==.',
Pi='Pikechu:BAAANQAECgYIEAAAAA==.Pinkskies:BAAANQAECgIIAgAAAA==.',
Pl='Playless:BAAANQAECgYICwAAAA==.Pleasy:BAAANQAECgQIBwAAAA==.Plugtobacca:BAAANQADCgIIAgABNQAFFAUIEAAWAAclAA==.',
Po='Pocketchange:BAACNQAFFH8FAAMMAAIKBAxHFACIAAAMAAIKBAxHFACIAAAcAAIKzAisGQB0AAA1AAQKfyUAAxwACgqJF1BSAB0CABwACgqJF1BSAB0CAAwACAomE9JSABQBAAAA.Pocketwatch:BAAANQAECgQIBwABNQAFFAIIBQAMAAQMAA==.',
Pr='Prayze:BAAANQADCgYIBgAAAA==.Preservation:BAAANQADCgIIAgABNQAECgoKOwAgADElAA==.Promethêus:BAAANQAECgIIAQAAAA==.',
Pu='Purefriction:BAAANQADCgYICQAAAA==.Purehate:BAAANQAECgUIDAAAAA==.',
Qr='Qrz:BAAANQADCgMIAwAAAA==.',
Rb='Rbackwards:BAAANQADCgUIBQABNQAECgoKLgAXADEZAA==.',
Re='Relovan:BAABNQAECn8nAAIjAAgK6gs5bQBAAQAjAAgK6gs5bQBAAQAAAA==.Renothidan:BAACNQAFFH8FAAIEAAIKiwpgGQCBAAAEAAIKiwpgGQCBAAA1AAQKfykAAgQACgo+GiVcAIQCAAQACgo+GiVcAIQCAAAA.Ret:BAAANQADCgcICQABNQAECgoKUQAaADIlAA==.Reuben:BAAANQAECgEIAQAAAA==.Revin:BAABNQAECn8lAAIEAAkKCxVwoQDeAQAEAAkKCxVwoQDeAQAAAA==.Revrynth:BAABNQAECn8iAAQRAAgKohx2DwBjAgARAAgKohx2DwBjAgAKAAUKNhp1EwAyAQAUAAQKEBXjFADgAAAAAA==.Rexorcist:BAAANQAECgYICQAAAA==.',
Ri='Rimed:BAABNQAECn8bAAMDAAcKiw7f8ACpAQADAAcKMQ3f8ACpAQAbAAEKaBCvRwA1AAAAAA==.Rippèd:BAAANQADCgYIBgAAAA==.Rithcice:BAAANQADCgcIBwAAAA==.Rizzard:BAABNQAECn8XAAMMAAoKxBPOIgDpAQAMAAoKxBPOIgDpAQAcAAEKGgMf1QAnAAAAAA==.Rizzdolphler:BAACNQAFFH8JAAICAAQKtA5ZEwAsAQACAAQKtA5ZEwAsAQA1AAQKfyoAAwIACgomHFEiAOMCAAIACgomHFEiAOMCAAQABwo2Dl6zAPIAAAAA.',
Ro='Rorän:BAAANQAECgEIAQAAAA==.',
['Rö']='Rönburgundy:BAABNQAECn8uAAIXAAoKMRnwTABtAgAXAAoKMRnwTABtAgAAAA==.',
Sa='Sanako:BAAANQAECgcIDgAAAA==.Saneros:BAAANQAECgQIBAAAAA==.',
Sc='Scraggle:BAAANQAECgQIBQAAAA==.Scuffito:BAAANQAECgMIBAAAAA==.',
Sd='Sdh:BAAANQADCgEIAQAAAA==.',
Se='Seasondpally:BAAANQADCgcIBwAAAA==.Sermakan:BAAANQADCgIIAgAAAA==.Setheron:BAAANQAECgMICQAAAA==.',
Sh='Shamnira:BAAANQAECgQIBAAAAA==.Shamtul:BAAANQABCgYIEgAAAA==.Shlea:BAABNQAECn8jAAIUAAoKHgp4CwCoAQAUAAoKHgp4CwCoAQAAAA==.Shley:BAAANQADCgYIBgABNQAECgoKIwAUAB4KAA==.',
Si='Silvanna:BAAANQAECgQIBQAAAA==.Sivi:BAAANQAECgIIAgAAAA==.',
Sl='Slinkstir:BAAANQADCgYIBgAAAA==.',
Sm='Smh:BAAANQAECgQIBAAAAA==.',
Sn='Sneak:BAAANQAECgQIBAABNQAECgoKUQAaADIlAA==.',
So='Solendros:BAAANQAECgQIBAAAAA==.Sonoa:BAAANQAECggICgAAAA==.Sonthar:BAAANQADCgQJBAAAAA==.Sorix:BAAANQADCgIIAgAAAA==.Sorlight:BAABNQAECn8XAAIZAAcKkBwCGwAWAgAZAAcKkBwCGwAWAgAAAA==.Soulelf:BAAANQADCgEIAQAAAA==.Sourpets:BAABNQAECn8VAAIGAAcKURqJWABqAgAGAAcKURqJWABqAgAAAA==.Sourshocks:BAAANQAECgEIAQAAAA==.Sourwords:BAAANQAECgEIAQAAAA==.',
St='Standarshh:BAABNQAECn8yAAIGAAoKJB+IJwD6AgAGAAoKJB+IJwD6AgAAAA==.Stevenz:BAABNQAECn8iAAIDAAoKiiCPKQA+AwADAAoKiiCPKQA+AwAAAA==.Stillflygon:BAAANQADCgYIEgAAAA==.Stormcare:BAAANQADCgUIBQAAAA==.',
Su='Subtle:BAACNQAFFH8IAAMWAAMK4xOOAwDqAAAWAAMK4xOOAwDqAAAhAAEKYwEEFwA4AAA1AAQKfy4AAxYACQpJHlMgAH8CABYACQpJHlMgAH8CACEABgrlFKojAKsBAAAA.Sugarbabi:BAAANQAECggIEwAAAA==.Sugarrush:BAAANQADCggIDgAAAA==.Sugarshot:BAAANQAECgMIAgAAAA==.Sugartotem:BAAANQAECgUICgAAAA==.Sunmere:BAAANQADCgUIBQAAAA==.',
Sw='Swiftwing:BAAANQADCgQIBAAAAA==.',
Sy='Sydarliia:BAAANQAECgYIEAAAAA==.Sylrianah:BAABNQAECn83AAIVAAoKLA7rYwD0AQAVAAoKLA7rYwD0AQAAAA==.Sylveste:BAACNQAFFH8MAAICAAUKAQpNCQBXAQACAAUKAQpNCQBXAQA1AAQKfy0AAgIACgqjGiQVAJsCAAIACgqjGiQVAJsCAAAA.',
Ta='Tae:BAAANQAECgIIAgAAAA==.Tal:BAAANQAECggIDgABNQAECgkJHQAEAEQWAA==.Talis:BAAANQAECgEIAQAAAA==.Talridor:BAAANQADCgcIBgAAAA==.Tankhiskhan:BAAANQAECggIEQAAAA==.Tarlis:BAAANQAECgcIDAAAAA==.',
Te='Tei:BAAANQAECgMIAwAAAA==.Terily:BAAANQADCgcICgAAAA==.',
Th='Thannill:BAABNQAECn8pAAIHAAgKtxOmHACPAQAHAAgKtxOmHACPAQAAAA==.',
Ti='Ticktoklock:BAAANQAECggICQAAAA==.Tie:BAABNQAECn8rAAIZAAkKJRrcCAA2AgAZAAkKJRrcCAA2AgAAAA==.Tirala:BAABNQAECn8VAAIdAAoKMiLCBQABAwAdAAoKMiLCBQABAwAAAA==.',
To='Tomari:BAAANQABCgEIAQAAAA==.Tomias:BAAANQADCgMIAwAAAA==.Torzhu:BAAANQAECgUIEwAAAA==.Toy:BAAANQAECggIDwABNQAFFAcIGAAKAO0VAA==.',
Tr='Trauck:BAAANQAECgUIDwAAAA==.Travvy:BAACNQAFFH80AAMhAAkKuCFYAADUAgAWAAkKoBhsAAAyAwAhAAkKICFYAADUAgA1AAQKfyUAAyEACgqHJrUDAGMDACEACgouIrUDAGMDABYAAwr2IAxmABoBAAAA.Trevmo:BAABNQAECn8fAAIjAAoK3hH6cABBAgAjAAoK3hH6cABBAgAAAA==.Trexin:BAAANQAECgIIAwAAAA==.',
Tu='Turaylon:BAAANQADCgQIBAAAAA==.',
Tz='Tzuyu:BAABNQAECn8vAAMGAAoKeiGlCACXAwAGAAoKeiGlCACXAwAFAAEKIxGwhwA2AAAAAA==.',
Ud='Uddershock:BAAANQADCggIDgAAAA==.',
Un='Unapologetic:BAAANQAECgUIBQABNQAECgoKOwAgADElAA==.Unbreakabull:BAACNQAFFH8EAAIPAAIKuho5DwCuAAAPAAIKuho5DwCuAAA1AAQKfyEAAg8ACgpuI4QHAJUDAA8ACgpuI4QHAJUDAAAA.Unver:BAAANQADCgYIBgAAAA==.',
Va='Vae:BAAANQAECgYJEQABNQAECgoKIgAQAM8ZAA==.Valka:BAAANQAECgEIAQAAAA==.Vanthrall:BAAANQADCgUIBQAAAA==.',
Ve='Veldtt:BAAANQADCgIIAgAAAA==.Velera:BAABNQAECn8dAAIDAAgK1wfPhgA1AQADAAgK1wfPhgA1AQAAAA==.Vesemir:BAAANQADCgcIBwAAAA==.Veyle:BAABNQAECn83AAMWAAoKgiIhAgC/AwAWAAoKgiIhAgC/AwAhAAYK1B00HQDpAQAAAA==.',
Vi='Viibryd:BAAANQAECgMIBgAAAA==.Vine:BAAANQAECgUIBAAAAA==.',
Vy='Vyel:BAAANQADCgIIAgAAAA==.Vyndria:BAAANQADCgcIDQAAAA==.Vynstus:BAAANQADCggIHAAAAA==.Vyran:BAAANQADCgIIAgAAAA==.',
Wa='Waypal:BAAANQADCggIFwAAAA==.',
We='Weashadow:BAAANQAECgcICgAAAA==.Weashock:BAAANQADCgYIDAAAAA==.Weasy:BAAANQAECggIDAAAAA==.',
Wi='Windfury:BAABNQAECn8tAAIaAAoKWiJCAgCJAwAaAAoKWiJCAgCJAwAAAA==.Wingzard:BAABNQAECn8fAAIDAAgKZxV4tAAaAgADAAgKZxV4tAAaAgAAAA==.',
Wo='Wowdudesame:BAABNQAECn8XAAIjAAcKCR2KagBRAgAjAAcKCR2KagBRAgABNQAECgoKUQAaADIlAA==.',
Xl='Xl:BAABNQAECn8sAAIdAAoKhBgJIwCDAgAdAAoKhBgJIwCDAgAAAA==.',
Ya='Yaitoopmfp:BAABNQAECn8fAAQQAAoKshjRGQBzAgAQAAkKPhjRGQBzAgAgAAcKbg9GEAB4AQAkAAEKvBx/GQBVAAAAAA==.Yao:BAABNQAECn82AAMLAAoKqyCWDgA6AwALAAoKqyCWDgA6AwAHAAEKAAAK2wA6AAAAAA==.Yasrena:BAABNQAECn8oAAMVAAkK8w7tSwCBAQAVAAkK8w7tSwCBAQAeAAcKYhDuHQAZAQAAAA==.',
Ye='Yelp:BAAANQAECgQIBAAAAA==.',
Za='Zabara:BAAANQADCgYIBgABNQAECggIIgACAF0ZAA==.Zair:BAAANQADCgUIBQAAAA==.Zakaraki:BAABNQAECn83AAMRAAoKqx90BgAiAwARAAkK3h50BgAiAwAKAAgK8hUvGgAgAgAAAA==.Zaki:BAABNQAECn8dAAISAAoKyxWWFwChAgASAAoKyxWWFwChAgAAAA==.Zappin:BAAANQAECggICQABNQAFFAUIEAAWAAclAA==.',
Ze='Zealot:BAABNQAECn8XAAMEAAgKLBBBvACkAQAEAAgK/g9BvACkAQAZAAYK6wgjSADNAAAAAA==.Zeleria:BAAANQAECgMIAgAAAA==.Zerathis:BAAANQADCgEJAQAAAA==.',
Zi='Zinbek:BAAANQADCgUIBQAAAA==.Zip:BAAANQABCgYJBgAAAA==.Zipstin:BAAANQAECgEIAQAAAA==.',
Zo='Zo:BAAANQAECgEIAQAAAA==.Zoo:BAAANQAECgIIAgAAAA==.Zorb:BAABNQAECn81AAIPAAoK/xrfFAAgAwAPAAoK/xrfFAAgAwABNQAFFAIIBQAXALsIAA==.Zoshow:BAAANQAECgUICgAAAA==.Zoshôw:BAAANQAECgcIBwAAAA==.',
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
