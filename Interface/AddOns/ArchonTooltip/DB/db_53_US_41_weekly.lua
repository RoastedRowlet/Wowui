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

local lookup = {'Warlock-Destruction','Paladin-Holy','Mage-Arcane','Paladin-Retribution','Hunter-Marksmanship','Hunter-BeastMastery','DeathKnight-Unholy','Unknown-Unknown','Druid-Restoration','Evoker-Preservation','Shaman-Restoration','DeathKnight-Blood','Shaman-Elemental','Warrior-Protection','DeathKnight-Frost','Druid-Balance','Monk-Windwalker','Evoker-Devastation','DemonHunter-Vengeance','DemonHunter-Devourer','Evoker-Augmentation','Priest-Holy','Rogue-Assassination','Warlock-Demonology','Warlock-Affliction','Paladin-Protection','Shaman-Enhancement','Mage-Frost','DemonHunter-Havoc','Priest-Shadow','Druid-Feral','Monk-Mistweaver','Rogue-Subtlety','Hunter-Survival','Warrior-Arms','Monk-Brewmaster',}
local provider = {region='US',realm='Bloodscalp',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abbpriest:BAAANQADCgYJBgABNQAECggJGQABAOYYAA==.Abruum:BAAANQADCgcIDAAAAA==.',
Ad='Admetus:BAABNQAECn8zAAICAAoKoh8DHgDMAgACAAoKoh8DHgDMAgAAAA==.Adobe:BAAANQADCggIGwAAAA==.',
Am='Amapall:BAAANQAECggIEgABNQAECgoKHQADAI8UAA==.Amapriest:BAAANQAECgYIDgABNQAECgoKHQADAI8UAA==.Amathal:BAABNQAECn8dAAIDAAoKjxSopAA4AgADAAoKjxSopAA4AgAAAA==.',
An='Anderson:BAAANQADCgQIBAAAAA==.Ankheloios:BAAANQAECgUIDgAAAA==.',
Ar='Arcanehonkey:BAAANQADCggICAAAAA==.Aredhela:BAABNQAECn8mAAIEAAkK5RQdkQACAgAEAAkK5RQdkQACAgAAAA==.Arias:BAAANQAECgQIBAAAAA==.Armsdealer:BAAANQADCgUIBQAAAA==.Arro:BAAANQAECgEIAQAAAA==.',
As='Ascending:BAAANQAECgQICAAAAA==.Asha:BAACNQAFFH8bAAMFAAcKFxohCAB+AQAFAAcKFxohCAB+AQAGAAEKoQHPOAA2AAA1AAQKfy8AAwUACgrCHOoRANYCAAUACgrCHOoRANYCAAYAAQqxAV1sASYAAAAA.Ashveil:BAAANQADCgQIBAABNQAECgoKIwAHAIIaAA==.Astrialynn:BAAANQADCgYIBwABNQADCgcIBwAIAAAAAA==.Astrulawa:BAAANQAECgQICgAAAA==.',
At='Athrea:BAABNQAECn82AAIHAAoKRyL8IwCyAgAHAAoKRyL8IwCyAgAAAA==.',
Au='Aurhiel:BAAANQAECgEIAQAAAA==.',
Av='Avasharm:BAAANQABCgYIBgABNQABCgYIAgAIAAAAAA==.',
Ba='Barakah:BAAANQAECgQIAwAAAA==.Barnre:BAAANQAECgIIBAAAAA==.Battlelord:BAAANQAECgIIBAAAAA==.',
Bd='Bdssm:BAAANQAECgcIBwAAAA==.',
Be='Bearito:BAAANQAECgQIDwAAAA==.Beefstick:BAABNQAECn8hAAIGAAoKZBLIhwD7AQAGAAoKZBLIhwD7AQAAAA==.Beserkfury:BAABNQAECn8tAAIFAAoKEAp9HQCNAQAFAAoKEAp9HQCNAQAAAA==.',
Bi='Biercan:BAAANQAECgYIDAAAAA==.Bigcarl:BAAANQAECgEIAQAAAA==.Binke:BAAANQADCgQIBAAAAA==.Bittyboop:BAAANQADCggICwABNQAECgYIEgAIAAAAAA==.Bittywhite:BAAANQAECgUICAABNQAECgYIEgAIAAAAAA==.Bittywyvern:BAAANQADCgUIBQABNQAECgYIEgAIAAAAAA==.',
Bj='Bjarna:BAAANQAECggIEQAAAA==.',
Bl='Blayze:BAAANQAECgYIDwAAAA==.Blinkytime:BAABNQAECn8uAAIEAAkK4RSulACjAQAEAAkK4RSulACjAQAAAA==.Bloodskull:BAAANQADCgEIAQAAAA==.Blúnt:BAAANQADCgQIBAAAAA==.',
Bo='Bobheals:BAABNQAECn9EAAIJAAoKYhzOEgCcAgAJAAoKYhzOEgCcAgAAAA==.Boibye:BAAANQAECgQICwAAAA==.Bolblock:BAAANQAECggIDwAAAA==.Bolo:BAACNQAFFH8KAAIKAAMKZhBOEQC5AAAKAAMKZhBOEQC5AAA1AAQKfzYAAgoACgqdH6kHACsDAAoACgqdH6kHACsDAAAA.Boostedww:BAAANQAECgQICwAAAA==.Borkoir:BAAANQAECggIDgABNQAECggIEQAIAAAAAA==.Bowlo:BAABNQAFFH8GAAILAAQK3wwZFgAGAQALAAQK3wwZFgAGAQAAAA==.Bowzo:BAAANQAECgMIAwAAAA==.',
Br='Brambleclaw:BAABNQAECn89AAIMAAoKZCBFDABQAwAMAAoKZCBFDABQAwAAAA==.Brayker:BAABNQAECn8/AAIEAAoKhyM6IgA7AwAEAAoKhyM6IgA7AwAAAA==.Breadoneal:BAABNQAECn81AAMCAAoKVRpUHwDDAgACAAoKVRpUHwDDAgAEAAMKqQasXQGKAAAAAA==.Brewed:BAAANQAECgMIBAAAAA==.Brisketprime:BAAANQAECggIAgAAAA==.Brynjamin:BAAANQAECgQICAAAAA==.Brüenor:BAAANQAECgMIBQAAAA==.',
Bu='Bubbi:BAAANQADCgEIAQAAAA==.Bukkorosuzo:BAABNQAECn8UAAIDAAUK/Aiv8ADNAAADAAUK/Aiv8ADNAAAAAA==.Burntroot:BAABNQAECn8fAAINAAcK5APuuAAgAQANAAcK5APuuAAgAQAAAA==.',
['Bá']='Bálor:BAAANQAECgUIDgAAAA==.',
Ca='Cacci:BAAANQADCgcIBwAAAA==.Caedwyn:BAAANQAECgYIEgAAAA==.Camdakablam:BAAANQAECgcIEQAAAA==.Careadin:BAAANQADCgQIBAABNQAECggIGwAOAGsgAA==.Careradin:BAABNQAECn8bAAIOAAgKayBaDABwAgAOAAgKayBaDABwAgAAAA==.Carereaper:BAAANQAECgEIAQABNQAECggIGwAOAGsgAA==.Cartilage:BAABNQAECn8dAAMHAAkKQQ1/OwAnAQAHAAkKMAx/OwAnAQAPAAcKhQsMbQDqAAAAAA==.Cassieruth:BAAANQAECggICgAAAA==.Catalei:BAAANQAECgEIAQAAAA==.',
Ce='Centrest:BAAANQADCgYJCAAAAA==.Cerus:BAAANQADCgEIAQAAAA==.',
Ch='Chebbles:BAAANQADCgUIBgABNQAECgcIJAAQAMwRAA==.Chillidan:BAAANQAECgMIAwABNQAECgkJKQARAFMhAA==.Chivi:BAAANQADCggIDgABNQAECggIIgASAKIcAA==.Chonkmonk:BAAANQADCgQIBAAAAA==.Chupacabrass:BAAANQAECgIIAgAAAA==.Chupanibre:BAAANQADCgMIAwABNQAECgcIJAAQAMwRAA==.Chëbbles:BAAANQAECgMIAwABNQAECgcIJAAQAMwRAA==.',
Co='Colman:BAABNQAECn8UAAICAAUKQyQDRQAAAgACAAUKQyQDRQAAAgAAAA==.Comfy:BAAANQAECgEIAQAAAA==.Coorsbanquet:BAABNQAECn8lAAMTAAoKlBH0FAABAQAUAAoKIBDAJwBbAQATAAYKMxD0FAABAQABNQAECgoKKQAKACoPAA==.Coorsbite:BAABNQAECn8pAAQKAAoKKg/CEwC9AQAKAAgKcxDCEwC9AQAVAAkK5A3VCwA5AQASAAUKmQgVKQDlAAAAAA==.Coorslight:BAAANQADCgYIBgABNQAECgoKKQAKACoPAA==.Corrahthecow:BAAANQAECgEIAQABNQAECgoKKQAKACoPAA==.',
Cr='Craccjar:BAAANQADCgYIBwAAAA==.Crackjar:BAAANQADCgUICAAAAA==.Croc:BAAANQAECgcIEAAAAA==.Crudala:BAAANQADCgcICQABNQAECgMIAgAIAAAAAA==.Crystle:BAABNQAECn8wAAIWAAoKfAvLWADaAQAWAAoKfAvLWADaAQAAAA==.Crystlemarie:BAAANQADCgMIAwAAAA==.',
Cs='Csyasha:BAAANQADCgcIBwABNQAECgoKHAAXAI0LAA==.',
Cu='Cubcadet:BAABNQAECn8tAAIEAAoK+xqXSQC4AgAEAAoK+xqXSQC4AgAAAA==.',
Cy='Cybear:BAABNQAECn8qAAIYAAoKlRoHLQBbAgAYAAoKlRoHLQBbAgAAAA==.',
Da='Dalanora:BAABNQAECn88AAQYAAoKYBp3JgDqAgAYAAoKYBp3JgDqAgABAAMKXRUdQwC4AAAZAAMKpBafGwCkAAAAAA==.Dammned:BAAANQAECgQIBAAAAA==.Dapalyu:BAABNQAECn8vAAMaAAoKYRFCKwCDAQAaAAkKLhJCKwCDAQAEAAgKYQX1EwH+AAAAAA==.Davidx:BAAANQADCgQIBgAAAA==.',
De='Dekig:BAAANQAECgEIAQAAAA==.Demine:BAAANQAECgMIBAAAAA==.Detrazeral:BAAANQADCggIEAAAAA==.',
Di='Dico:BAAANQAECgcICgABNQAFFAgIHQAOABgYAA==.Dipper:BAABNQAECn82AAIEAAoKkhacegA2AgAEAAoKkhacegA2AgAAAA==.',
Do='Dohan:BAAANQADCggIEAAAAA==.Dorìan:BAAANQADCggIFgAAAA==.Dorÿ:BAAANQADCgcIBwAAAA==.',
Dr='Draetona:BAAANQADCggIGQAAAA==.Druidthings:BAAANQADCgUIBQAAAA==.',
Ee='Eeveeko:BAABNQAECn8uAAIbAAoK6xcCDACwAgAbAAoK6xcCDACwAgAAAA==.',
Ej='Ejavuday:BAABNQAECn8wAAMDAAoKhR5CQQACAwADAAoKhR5CQQACAwAcAAEKgR2cRwA1AAAAAA==.',
En='Enerchi:BAABNQAECn8pAAIRAAkKUyF8CgArAwARAAkKUyF8CgArAwAAAA==.',
Ep='Ephara:BAAANQAECgEIAQAAAA==.',
Er='Erianar:BAAANQADCgEIAQAAAA==.Ervyne:BAABNQAECn8iAAMGAAoKvhCTbAA5AgAGAAoKnRCTbAA5AgAFAAUKmAaaUgDeAAAAAA==.',
Ev='Evera:BAABNQAECn8uAAIHAAoK2AsGJwCpAQAHAAoK2AsGJwCpAQAAAA==.Evos:BAAANQADCgYJBgAAAA==.',
Ex='Exning:BAAANQADCggICAAAAA==.',
Fa='Fatherømally:BAAANQAECggIBAABNQAECgkJIQAEAMoWAA==.Fauci:BAAANQAECgYIBgABNQAFFAYIEQAXAC4hAA==.',
Fe='Feihao:BAAANQAECgEIAQAAAA==.Feile:BAABNQAECn8zAAMYAAoKgA+vawAaAgAYAAoKgA+vawAaAgABAAEKAAArcQA+AAAAAA==.Feltree:BAAANQADCgQIBAAAAA==.',
Fi='Fishbox:BAAANQABCgYIDAAAAA==.',
Fl='Flashir:BAAANQADCgIIAgAAAA==.Flinzza:BAABNQAECn8kAAMbAAkKYxd3GADgAQAbAAkKYxd3GADgAQALAAgK2hSnaQDPAQAAAA==.Flyknit:BAABNQAECn8XAAIEAAYKZRKc2gBmAQAEAAYKZRKc2gBmAQAAAA==.',
Fr='Fredthedh:BAABNQAECn8jAAMUAAoKjBeVIwAsAgAUAAgKXxeVIwAsAgAdAAUKChbEZACSAAAAAA==.Fromtheback:BAAANQAECgIIAgABNQAECgoKHwAHAMESAA==.Frosticals:BAABNQAECn8tAAIDAAkK4CEvQAAFAwADAAkK4CEvQAAFAwAAAA==.Frostsugar:BAAANQABCgQIBgAAAA==.',
Ga='Gaashw:BAAANQABCgQIBwAAAA==.Gabtvsorcere:BAAANQADCgYICgAAAA==.Ganandor:BAABNQAECn8kAAIXAAoKVBzaGwCfAgAXAAoKVBzaGwCfAgAAAA==.Garroz:BAAANQADCgEIAQAAAA==.Gaulish:BAAANQAECgQICAAAAA==.',
Ge='Geocide:BAABNQAECn8VAAINAAcKVB3oVgAeAgANAAcKVB3oVgAeAgAAAA==.Getagrip:BAAANQAECggIDAABNQAFFAQIDAAXAOMTAA==.Gethalyn:BAAANQAECgUIBwAAAA==.',
Gh='Ghasch:BAABNQAECn8cAAILAAoK0BvGGgDhAgALAAoK0BvGGgDhAgAAAA==.Ghume:BAAANQAECgQIDAAAAA==.',
Gi='Gianthippo:BAAANQADCgYICgABNQAECgkJFAAMADcJAA==.Gilf:BAACNQAFFH8SAAIbAAYKjx+CAQBzAQAbAAYKjx+CAQBzAQA1AAQKfyMAAxsACgptI9ABAJoDABsACgptI9ABAJoDAA0ABAqCCIzsAL4AAAE1AAUUCAgXABkAVxUA.',
Go='Goursh:BAAANQAECgEIAQAAAA==.',
Gr='Grizzoul:BAABNQAECn8cAAMVAAcKTgO9FADiAAAVAAcKTgO9FADiAAASAAMKxwEdNwBWAAAAAA==.Grreenry:BAAANQAECgEIAQAAAA==.Grumly:BAABNQAECn8dAAIcAAYKaw1RHgD6AAAcAAYKaw1RHgD6AAAAAA==.',
Ha='Hamms:BAAANQADCgEIAQABNQAECgoKKQAKACoPAA==.Hanhaitu:BAAANQADCgQIBgAAAA==.Hanswoloqued:BAACNQAFFH8KAAIYAAUKVwjlHQDBAAAYAAUKVwjlHQDBAAA1AAQKfy8AAhgACgqZFCtaAEgCABgACgqZFCtaAEgCAAAA.Haxz:BAAANQADCgUIBQAAAA==.',
He='Healufast:BAABNQAECn88AAIWAAoKbCDUFgAgAwAWAAoKbCDUFgAgAwAAAA==.Heck:BAAANQADCgYIBgAAAA==.Helstrom:BAAANQAECgIIAQAAAA==.',
Hj='Hjalmar:BAABNQAECn81AAMCAAoKWRxLKwB5AgACAAoKWRxLKwB5AgAEAAkKTBWggwDFAQAAAA==.',
Ho='Holycõw:BAABNQAECn8hAAIEAAkKyhacoQCKAQAEAAkKyhacoQCKAQAAAA==.Holysabeline:BAABNQAECn8/AAICAAoKxB9SHwDzAgACAAoKxB9SHwDzAgAAAA==.Hotpots:BAAANQAECggIEgAAAA==.Hotwíngs:BAAANQAECgcICQAAAA==.',
Hu='Huchar:BAABNQAECn9HAAIOAAoKliCICABaAgAOAAoKliCICABaAgAAAA==.Humpf:BAAANQADCgEIAQAAAA==.Hunterpanda:BAAANQADCgYIBgAAAA==.',
Hy='Hydraxix:BAAANQADCggICAAAAA==.',
Ic='Iceblade:BAABNQAECn8fAAICAAoKvBnjQgAJAgACAAoKvBnjQgAJAgAAAA==.',
Id='Idtrapdat:BAAANQAECgIIAgAAAA==.',
If='If:BAAANQADCgQIBAAAAA==.',
In='Incowgnito:BAAANQAECgcICQAAAA==.Invoice:BAAANQAECgUIBQAAAA==.',
Ir='Ironßest:BAAANQABCgUICwAAAA==.',
Ja='Jadzi:BAAANQADCgYJCwAAAA==.Jaxxion:BAAANQADCgYIBgAAAA==.',
Je='Jessaiyan:BAABNQAECn8UAAIUAAoK2g9LIACeAQAUAAoK2g9LIACeAQAAAA==.',
Jo='Jobo:BAABNQAECn8vAAMJAAoKSxj7DgDZAgAJAAoKSxj7DgDZAgAQAAUKZASNhgC4AAAAAA==.Jobodot:BAABNQAECn8YAAIYAAcKSwdVyQA3AQAYAAcKSwdVyQA3AQAAAA==.',
Ju='Julaudette:BAAANQAECgQIBQAAAA==.Juliania:BAAANQADCgYIBwAAAA==.Julzaria:BAABNQAECn8kAAIGAAoKHA95XgALAgAGAAoKHA95XgALAgAAAA==.Jurny:BAABNQAECn8rAAMBAAcKURA1DQDrAAABAAcKURA1DQDrAAAZAAIKVAVDJQBZAAAAAA==.',
Ka='Kahlandra:BAABNQAECn88AAIDAAoKJhaheQCLAgADAAoKJhaheQCLAgAAAA==.Kaizer:BAABNQAECn81AAINAAkKLRkTNgCfAgANAAkKLRkTNgCfAgAAAA==.Kandera:BAAANQADCgUIBQAAAA==.Karina:BAAANQADCgUJBQABNQAECgoKPwAGAD0kAA==.',
Ke='Keizer:BAAANQAECgEIAQAAAA==.Keunen:BAABNQAECn8iAAMQAAcKgQbrVADLAAAQAAcKgQbrVADLAAAJAAQKjASuZQBjAAAAAA==.Kevlock:BAAANQADCgYIBgAAAA==.Keyzer:BAAANQAECggIEQAAAA==.',
Kh='Khanjuror:BAAANQAECgEIAQAAAA==.Kharún:BAAANQAECgYIBAAAAA==.Khornedog:BAABNQAECn82AAIYAAoKRBz+VgBRAgAYAAoKRBz+VgBRAgAAAA==.Khrama:BAABNQAECn9CAAIMAAoK6CVVCwBYAwAMAAoK6CVVCwBYAwAAAA==.',
Kl='Kleenonean:BAACNQAFFH8YAAIeAAcKqSVUAwA5AgAeAAcKqSVUAwA5AgA1AAQKf6QAAh4ACgp5JicAAAsEAB4ACgp5JicAAAsEAAAA.',
Kn='Knut:BAAANQAECggIEQAAAA==.',
Kr='Krackjarr:BAABNQAECn8uAAIYAAoK6Ap0eQBxAQAYAAoK6Ap0eQBxAQAAAA==.Kredor:BAAANQAECgIIBAAAAA==.Kriptonic:BAAANQAECgYIBwAAAA==.Kriptskeeper:BAAANQAECgQIBAAAAA==.Kris:BAAANQAECgEIAQAAAA==.',
Ku='Kungpowbeef:BAAANQAECgIIAgAAAA==.Kurzaan:BAAANQAECgMIAgAAAA==.Kuyaj:BAAANQADCgIIAgAAAA==.',
La='Lacio:BAABNQAECn87AAIeAAoKwQf2MQCTAQAeAAoKwQf2MQCTAQAAAA==.Larune:BAAANQABCgEIAQAAAA==.',
Le='Lemonpepper:BAACNQAFFH8HAAIKAAQK7wU+DwDpAAAKAAQK7wU+DwDpAAA1AAQKfywAAgoACgrqEtUbAA0CAAoACgrqEtUbAA0CAAAA.Lexxix:BAAANQADCgcIDAAAAA==.Leyru:BAAANQAECgUIDAAAAA==.',
Li='Liberos:BAABNQAECn8dAAILAAcKlBTeaAB6AQALAAcKlBTeaAB6AQAAAA==.Lilnimjr:BAAANQADCgYICAAAAA==.Littlechiken:BAAANQADCgUIBQABNQAFFAYIDQAMAFUKAA==.',
Ln='Lninedkhack:BAABNQAECn8jAAMHAAoKghp9JQC0AQAHAAoKghp9JQC0AQAPAAIK9AeOnQBhAAAAAA==.',
Lo='Logaar:BAABNQAECn81AAMCAAoKqRFaTgAxAgACAAkKfBBaTgAxAgAEAAoK/QpYvQCiAQAAAA==.',
Lu='Lubuu:BAAANQADCggIGgAAAA==.Lucyfurrawr:BAABNQAECn8aAAIfAAkKOBSvFACDAQAfAAkKOBSvFACDAQABNQAECgoKIgARAM8ZAA==.Lunala:BAAANQADCgcIBwABNQAECgMIAgAIAAAAAA==.Luxurix:BAAANQADCggIEQAAAA==.',
Ma='Maer:BAAANQADCgUIBwAAAA==.Magtao:BAAANQADCgYIEQAAAA==.Malexannius:BAAANQADCgYIDwAAAA==.Manastorm:BAABNQAECn8lAAIDAAoKgQbJiwCPAQADAAoKgQbJiwCPAQAAAA==.Maplebrick:BAAANQABCgIIAgAAAA==.Mariangel:BAAANQADCgEIAQAAAA==.Marric:BAAANQAECggJCgAAAA==.',
Me='Medean:BAAANQADCggICAAAAA==.Megtallica:BAABNQAECn8eAAIEAAYKmAY4OAHGAAAEAAYKmAY4OAHGAAAAAA==.Mehunglow:BAAANQADCgUICAAAAA==.Mellissaa:BAAANQADCggIEgAAAA==.Mensrea:BAABNQAECn8uAAMNAAoKQQwFSwCqAQANAAoKQQwFSwCqAQALAAEKmwImCAEmAAAAAA==.Merrycold:BAABNQAECn8dAAMHAAgKdxdQSwDoAQAHAAgKdxdQSwDoAQAPAAUKQxBAbADtAAABNQAECgoKHwARALIYAA==.',
Mf='Mfgirthquake:BAABNQAECn9rAAMbAAoKayWoAQBPAwAbAAoKayWoAQBPAwALAAYKCh2llgD1AAAAAA==.',
Mi='Miisty:BAABNQAECn8bAAIDAAoKwQJR3AD0AAADAAoKwQJR3AD0AAAAAA==.Mikklelee:BAAANQADCggIDwAAAA==.Mings:BAAANQAECgQICAAAAA==.Miniborohs:BAAANQAECgEIAQAAAA==.Mistweaver:BAABNQAECn9RAAIgAAoKySW6AwB0AwAgAAoKySW6AwB0AwAAAA==.',
Mo='Mochi:BAABNQAECn8/AAIDAAoKFxiuUQAcAgADAAoKFxiuUQAcAgAAAA==.Mochïi:BAAANQADCgIJBAABNQAFFAgIFgADAO0TAA==.Moghorva:BAAANQAECgcIBgAAAA==.Mojoe:BAABNQAECn8mAAILAAoK9Bo5MAChAgALAAoK9Bo5MAChAgAAAA==.Mommyswaggin:BAAANQAECgYIBwAAAA==.Moopster:BAABNQAECn8wAAIWAAoKbSTMCgBsAwAWAAoKbSTMCgBsAwAAAA==.Moopy:BAAANQAECgQIBAABNQAECgoKMAAWAG0kAA==.Mootangclan:BAABNQAECn8XAAINAAgKtxnkTQA/AgANAAgKtxnkTQA/AgAAAA==.Moxi:BAAANQABCgUIBQAAAA==.',
Na='Nalthexon:BAAANQAECgYICwAAAA==.Nanashi:BAACNQAFFH8HAAIPAAQKLgruEADKAAAPAAQKLgruEADKAAA1AAQKfzEAAg8ACQojI6AHAC0DAA8ACQojI6AHAC0DAAAA.Nazgru:BAAANQADCgYIDAAAAA==.',
Ne='Necros:BAAANQAECgIIAgABNQAFFAcIGgANAAMXAA==.Neiko:BAACNQAFFH8KAAMhAAUKVgqVFgDUAAAhAAUKUwmVFgDUAAAXAAIKmwomDQCCAAA1AAQKfyoAAxcACgr6GFwjAG0CABcACgoKF1wjAG0CACEABAq1HIZ1AEgBAAAA.Neptuneakis:BAABNQAECn8kAAIQAAcKzBGVUgCRAQAQAAcKzBGVUgCRAQAAAA==.Neptuno:BAAANQADCgEIAQABNQAECgcIJAAQAMwRAA==.Newcarsmell:BAAANQADCggIJgAAAA==.',
Ng='Ngl:BAAANQAECgcIDQAAAA==.',
Ni='Niceknife:BAAANQADCggIDQAAAA==.Nicomi:BAABNQAECn9HAAIcAAoKyg1rDADTAQAcAAoKyg1rDADTAQAAAA==.Nightwinger:BAAANQAECgUICAAAAA==.Nimrose:BAAANQAECgIIBAAAAA==.Niquid:BAABNQAECn8nAAIJAAoK8hFzHQAYAgAJAAoK8hFzHQAYAgAAAA==.Nivek:BAAANQAECgQICAAAAA==.Niylea:BAAANQADCgUIBQABNQAECgoKNgAHAEciAA==.',
No='Nobu:BAACNQAFFH8RAAMXAAYKLiEgBAAKAgAXAAUKViEgBAAKAgAhAAMKgRsOGQC4AAA1AAQKf0AAAxcACgpAJr4CALADABcACgrZJb4CALADACEACgqnIsILABkDAAAA.Noobhuntard:BAAANQADCggICAAAAA==.Norinari:BAACNQAFFH8XAAQZAAgKVxVqAQBeAQAZAAUKzhdqAQBeAQAYAAUK/g0AGAA1AQABAAIKcBeODgCZAAA1AAQKf0EABBkACgp5JIwEAJACABkABwqrJIwEAJACABgABwodI69BAI0CAAEAAwoKG+0vAAkBAAAA.Notahealer:BAAANQAECgcIEQABNQAECggIEgAIAAAAAA==.Noxloxes:BAAANQADCgIIAgAAAA==.',
Oa='Oakshre:BAABNQAECn88AAIRAAoKiR44CwAhAwARAAoKiR44CwAhAwAAAA==.',
Ob='Obliteration:BAAANQAECgYIDQABNQAECgkJKQARAFMhAA==.',
Od='Odsw:BAAANQADCgMJAwAAAA==.',
Oe='Oenaa:BAAANQAECgUIBAAAAA==.',
Ol='Olivertwist:BAAANQAECgQIDAABNQAECgkJKQARAFMhAA==.',
On='Ontwou:BAABNQAECn8tAAIGAAoK7BxvYwBPAgAGAAoK7BxvYwBPAgAAAA==.',
Or='Orbz:BAABNQAECn9BAAIDAAoK+iT4KQA9AwADAAoK+iT4KQA9AwAAAA==.Orcazm:BAAANQAECgIIAQAAAA==.',
Pa='Padova:BAAANQAECgMIAwAAAA==.Palyont:BAAANQAECgMIBQAAAA==.Pancakezebra:BAABNQAECn9OAAIiAAoK4xsOAwCLAgAiAAoK4xsOAwCLAgAAAA==.Parse:BAAANQAECgIIAwAAAA==.',
Pe='Perdido:BAAANQADCgIIAgAAAA==.',
Ph='Phoenix:BAABNQAECn8tAAIEAAoKbBvQggAiAgAEAAoKbBvQggAiAgAAAA==.',
Pi='Pikechu:BAAANQAECgYIEAAAAA==.Pinkskies:BAAANQAECgIIAgAAAA==.',
Pl='Playless:BAAANQAECgYIDgAAAA==.Pleasy:BAAANQAECgUIBwAAAA==.Plugtobacca:BAAANQADCgIIAgABNQAFFAYIEQAXAC4hAA==.',
Po='Pocketchange:BAACNQAFFH8HAAMNAAQKsAt0FADLAAANAAQKsAt0FADLAAALAAIKzAiMJgBxAAA1AAQKfygAAwsACgqJF1BSAB0CAAsACgqJF1BSAB0CAA0ACAomE+eDAAgBAAAA.Pocketwatch:BAAANQAECggIDwABNQAFFAQIBwANALALAA==.',
Pr='Prayze:BAAANQADCgYIBgAAAA==.Preservation:BAAANQADCgIIAgABNQAECgoKUQAgAMklAA==.Promethêus:BAAANQAECgIIAQAAAA==.',
Pu='Purefriction:BAAANQADCgYICQAAAA==.Purehate:BAAANQAECgUIDAAAAA==.',
Qr='Qrz:BAAANQADCgMIAwAAAA==.',
Rb='Rbackwards:BAAANQADCgUIBQABNQAECgoKLgAYADEZAA==.',
Re='Re:BAAANQAECgIIAwAAAA==.Relovan:BAABNQAECn8zAAMOAAoKSRRLGQA/AQAjAAoKoAy6awC+AQAOAAQKMRxLGQA/AQAAAA==.Renothidan:BAACNQAFFH8IAAIEAAMKiwpFKAB6AAAEAAMKiwpFKAB6AAA1AAQKfy0AAgQACgo+GiVcAIQCAAQACgo+GiVcAIQCAAAA.Ret:BAAANQADCgcICQABNQAECgoKawAbAGslAA==.Reuben:BAAANQAECgEIAQAAAA==.Revin:BAABNQAECn9CAAIEAAoK/hg4aQD+AQAEAAoK/hg4aQD+AQAAAA==.Revrynth:BAABNQAECn8iAAQSAAgKohx2DwBjAgASAAgKohx2DwBjAgAKAAUKNhqmHQAoAQAVAAQKEBXjFADgAAAAAA==.Rexorcist:BAAANQAECgYICQAAAA==.',
Ri='Rimed:BAABNQAECn8cAAMDAAgKZw3f8ACpAQADAAgKRwzf8ACpAQAcAAEKaBCvRwA1AAAAAA==.Rippèd:BAAANQADCgYIBgAAAA==.Rithcice:BAAANQADCgcIBwAAAA==.Rizzard:BAABNQAECn8pAAMNAAoKLxveHgB9AgANAAoKLxveHgB9AgALAAEKGgMJBwEnAAAAAA==.Rizzdolphler:BAACNQAFFH8JAAICAAQKtA5ZEwAsAQACAAQKtA5ZEwAsAQA1AAQKfzEAAwIACgq/HVEiAOMCAAIACgq/HVEiAOMCAAQABwo2Dl0AAekAAAAA.',
Ro='Rorän:BAAANQAECgMIAwAAAA==.',
['Rö']='Rönburgundy:BAABNQAECn8uAAIYAAoKMRnwTABtAgAYAAoKMRnwTABtAgAAAA==.',
Sa='Sanako:BAAANQAECgcIDgAAAA==.Saneros:BAAANQAECgQIBAAAAA==.',
Sc='Scraggle:BAAANQAECgQIBQAAAA==.Scuffito:BAAANQAECgMIBAAAAA==.',
Sd='Sdh:BAAANQADCgEIAQAAAA==.',
Se='Seasondpally:BAAANQADCgcIBwAAAA==.Sermakan:BAAANQAECgYIBgAAAA==.Setheron:BAAANQAECgUIEgAAAA==.',
Sh='Shamnira:BAAANQAECgYICQAAAA==.Shamtul:BAAANQABCgYIEgAAAA==.Shlea:BAABNQAECn8nAAIVAAoKYAp4CwCoAQAVAAoKYAp4CwCoAQAAAA==.Shley:BAAANQADCgYIBgABNQAECgoKJwAVAGAKAA==.',
Si='Silvanna:BAAANQAECgcIDwAAAA==.Sivi:BAAANQAECgIIAgAAAA==.',
Sl='Slinkstir:BAAANQADCgYIBgAAAA==.',
Sm='Smh:BAAANQAECgQIBAAAAA==.',
Sn='Sneak:BAAANQAECgQIBQABNQAECgoKawAbAGslAA==.',
So='Solendros:BAAANQAECgQIBAAAAA==.Sonoa:BAAANQAECggICgAAAA==.Sonthar:BAAANQADCgQJBAAAAA==.Sorix:BAAANQADCgIIAgAAAA==.Sorlight:BAABNQAECn8XAAIaAAcKkBwCGwAWAgAaAAcKkBwCGwAWAgAAAA==.Soulelf:BAAANQADCgEIAQAAAA==.Sourpets:BAABNQAECn8WAAIGAAgKfxiJWABqAgAGAAgKfxiJWABqAgAAAA==.Sourshocks:BAAANQAECgEIAQAAAA==.Sourwords:BAAANQAECgEIAQAAAA==.',
St='Standarshh:BAABNQAECn8+AAIGAAoK2CCIJwD6AgAGAAoK2CCIJwD6AgAAAA==.Stevenz:BAABNQAECn8pAAIDAAoKiiCPKQA+AwADAAoKiiCPKQA+AwAAAA==.Stillflygon:BAAANQADCgYIEgAAAA==.Stormcare:BAAANQADCgUIBQAAAA==.',
Su='Subtle:BAACNQAFFH8MAAMXAAQK4xMpBwDZAAAXAAQK4xMpBwDZAAAhAAEKYwEEFwA4AAA1AAQKfy8AAxcACQpJHlMgAH8CABcACQpJHlMgAH8CACEABgrlFKojAKsBAAAA.Sugarbabi:BAAANQAECggIEwAAAA==.Sugarrush:BAAANQADCggIDgAAAA==.Sugarshot:BAAANQAECgIIAgAAAA==.Sugartotem:BAAANQAECgUICgAAAA==.Sunmere:BAAANQADCgUIBQAAAA==.',
Sw='Swiftwing:BAAANQADCgQIBAAAAA==.',
Sy='Sydarliia:BAAANQAECgYIEAAAAA==.Sylrianah:BAABNQAECn89AAIWAAoK6g/rYwD0AQAWAAoK6g/rYwD0AQAAAA==.Sylveste:BAACNQAFFH8NAAICAAYKYQr4CwCPAQACAAYKYQr4CwCPAQA1AAQKfzAAAgIACgoAHKgmAJQCAAIACgoAHKgmAJQCAAAA.',
Ta='Tae:BAAANQAECgYICAAAAA==.Tal:BAAANQAECggIDgABNQAECgkJIQAEAMoWAA==.Talis:BAAANQAECgEIAQAAAA==.Talridor:BAAANQADCgcIBgAAAA==.Tankhiskhan:BAABNQAECn8UAAIMAAkKNwnVZwBUAQAMAAkKNwnVZwBUAQAAAA==.Tarlis:BAABNQAECn8XAAMYAAkKfwyWVwDNAQAYAAkKfwyWVwDNAQAZAAcKOwaMEwD+AAAAAA==.',
Te='Tei:BAAANQAECggIDQAAAA==.Telys:BAAANQADCgUIBQAAAA==.Terily:BAAANQADCgcICgAAAA==.Terithresh:BAAANQAECgEIAQAAAA==.Tetchy:BAAANQADCgQIBAABNQAFFAQIDAAXAOMTAA==.',
Th='Thannill:BAABNQAECn8xAAIHAAoKbhP9HQDyAQAHAAoKbhP9HQDyAQAAAA==.',
Ti='Ticktoklock:BAAANQAECggIDAAAAA==.Tie:BAABNQAECn83AAIaAAkKJhsHDgBLAgAaAAkKJhsHDgBLAgAAAA==.Tirala:BAABNQAECn8WAAIdAAoKMiLGDADXAgAdAAoKMiLGDADXAgAAAA==.',
To='Tomari:BAAANQABCgEIAQAAAA==.Tomias:BAAANQADCgMIAwAAAA==.Torzhu:BAAANQAECgUIEwAAAA==.Toy:BAAANQAECgcIDwABNQAFFAkJIQAKAPsSAA==.',
Tr='Trauck:BAAANQAECgUIDwAAAA==.Travvy:BAACNQAFFH9GAAMXAAkKvyFsAAAyAwAXAAkKoBhsAAAyAwAhAAkKMSGlAADrAgA1AAQKfycAAyEACgqIJrUDAGMDACEACgovIrUDAGMDABcAAwr2IAxmABoBAAAA.Trevmo:BAABNQAECn8lAAMjAAoKqxT6cABBAgAjAAoK3hH6cABBAgAOAAYKPxNZHQAWAQAAAA==.Trexin:BAAANQAECgIIAwAAAA==.',
Tu='Turaylon:BAAANQADCgQIBAAAAA==.',
Tz='Tzuyu:BAABNQAECn8/AAMGAAoKPSSlCACXAwAGAAoKPSSlCACXAwAFAAEKIxGwhwA2AAAAAA==.',
Ud='Uddershock:BAAANQAECgUIBQAAAA==.',
Un='Unapologetic:BAAANQAECgUIBQABNQAECgoKUQAgAMklAA==.Unbreakabull:BAACNQAFFH8GAAIQAAQKUhxUEAD6AAAQAAQKUhxUEAD6AAA1AAQKfyUAAhAACgqgI4QHAJUDABAACgqgI4QHAJUDAAAA.Unver:BAAANQADCgYIBgAAAA==.',
Va='Vae:BAAANQAECgYIEQABNQAECgoKIgARAM8ZAA==.Valka:BAAANQAECgEIAQAAAA==.Vanthrall:BAAANQADCgUIBQAAAA==.',
Ve='Veldtt:BAAANQADCgIIAgAAAA==.Velera:BAABNQAECn8jAAIDAAoKoAeRjACNAQADAAoKoAeRjACNAQAAAA==.Vesemir:BAAANQADCgcIBwAAAA==.Veyle:BAABNQAECn89AAMXAAoKsyMhAgC/AwAXAAoKsyMhAgC/AwAhAAYK1B00HQDpAQAAAA==.',
Vi='Viibryd:BAAANQAECgYICQAAAA==.Vine:BAAANQAECgQIBAAAAA==.',
Vy='Vyel:BAAANQADCgIIAgAAAA==.Vyndria:BAAANQADCgcIDQAAAA==.Vynstus:BAAANQADCggIHAAAAA==.Vyran:BAAANQADCgIIAgAAAA==.',
Wa='Waypal:BAAANQADCggIFwAAAA==.',
We='Weashadow:BAAANQAECgcICgAAAA==.Weashock:BAAANQADCgYIDAAAAA==.Weasy:BAABNQAECn8WAAIGAAkK6yFgMQCAAgAGAAkK6yFgMQCAAgAAAA==.',
Wi='Windfury:BAABNQAECn8wAAIbAAoKqSJCAgCJAwAbAAoKqSJCAgCJAwAAAA==.Wingzard:BAABNQAECn8fAAIDAAgKZxV4tAAaAgADAAgKZxV4tAAaAgAAAA==.',
Wo='Wowdudesame:BAABNQAECn8ZAAIjAAgKrxqKagBRAgAjAAgKrxqKagBRAgABNQAECgoKawAbAGslAA==.',
Xl='Xl:BAABNQAECn8xAAIdAAoKYBoJIwCDAgAdAAoKYBoJIwCDAgAAAA==.',
Ya='Yaitoopmfp:BAABNQAECn8fAAQRAAoKshjRGQBzAgARAAkKPhjRGQBzAgAgAAcKbg/DGgBYAQAkAAEKvBznIgBTAAAAAA==.Yao:BAABNQAECn9DAAMMAAoK1iKWDgA6AwAMAAoK1iKWDgA6AwAHAAEKAAAK2wA6AAAAAA==.Yasrena:BAABNQAECn8wAAMeAAoK6A/0HQCgAQAeAAkKEBH0HQCgAQAWAAoK8w2rawCaAQAAAA==.',
Ye='Yelp:BAAANQAECgYICQAAAA==.',
Za='Zabara:BAAANQADCgYIBgABNQAECgoKNQACAFkcAA==.Zair:BAAANQADCgUIBQAAAA==.Zakaraki:BAABNQAECn89AAMSAAoK0SF0BgAiAwASAAoK0SF0BgAiAwAKAAgK8hUvGgAgAgAAAA==.Zaki:BAABNQAECn8dAAIUAAoKyxWWFwChAgAUAAoKyxWWFwChAgAAAA==.Zappin:BAAANQAECggIDgABNQAFFAYIEQAXAC4hAA==.',
Ze='Zealot:BAABNQAECn8gAAMEAAoKrxBBvACkAQAEAAoKjRBBvACkAQAaAAYK6wgjSADNAAAAAA==.Zeleria:BAAANQAECgMIAgAAAA==.Zerathis:BAAANQADCgEJAQAAAA==.Zerro:BAAANQAECgYICwAAAA==.',
Zi='Zinbek:BAAANQADCgUIBQAAAA==.Zip:BAAANQABCgYJBgAAAA==.Zipstin:BAAANQAECgEIAQAAAA==.',
Zo='Zo:BAAANQAECgMIBAAAAA==.Zoo:BAAANQAECgIIAgAAAA==.Zorb:BAABNQAECn81AAIQAAoK/xrfFAAgAwAQAAoK/xrfFAAgAwABNQAFFAIIBQAYALsIAA==.Zoshow:BAAANQAECgUICgAAAA==.Zoshôw:BAAANQAECgcIBwAAAA==.',
['Zõ']='Zõshow:BAAANQAECgQIBwAAAA==.',
['Ða']='Ðaredevil:BAABNQAECn8iAAIRAAoKzxkkEgDMAgARAAoKzxkkEgDMAgAAAA==.',
['Ðp']='Ðp:BAABNQAECn8WAAIUAAgKmQhAOQB7AQAUAAgKmQhAOQB7AQAAAA==.',
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
