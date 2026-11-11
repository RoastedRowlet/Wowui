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
local provider = {region='US',realm='Bloodscalp',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abbpriest:BAAANQADCgYJBgABNQAECggJGQABAOYYAA==.Abruum:BAAANQADCgcIDAAAAA==.',
Ad='Admetus:BAABNQAECn8vAAICAAoKoh+IGgDUAgACAAoKoh+IGgDUAgAAAA==.Adobe:BAAANQADCggIGwAAAA==.',
Am='Amapall:BAAANQAECggIEQABNQAECgoKHQADAI8UAA==.Amapriest:BAAANQAECgYIDgABNQAECgoKHQADAI8UAA==.Amathal:BAABNQAECn8dAAIDAAoKjxSopAA4AgADAAoKjxSopAA4AgAAAA==.',
An='Anderson:BAAANQADCgQIBAAAAA==.Ankheloios:BAAANQAECgUIDgAAAA==.',
Ar='Arcanehonkey:BAAANQADCggICAAAAA==.Aredhela:BAABNQAECn8hAAIEAAkKSxQdkQACAgAEAAkKSxQdkQACAgAAAA==.Arias:BAAANQAECgQIBAAAAA==.Armsdealer:BAAANQADCgUIBQAAAA==.Arro:BAAANQAECgEIAQAAAA==.',
As='Ascending:BAAANQAECgQICAAAAA==.Asha:BAACNQAFFH8aAAMFAAcKFxqQBgCDAQAFAAcKFxqQBgCDAQAGAAEKoQEINQA2AAA1AAQKfy8AAwUACgrCHOoRANYCAAUACgrCHOoRANYCAAYAAQqxAV1sASYAAAAA.Ashveil:BAAANQADCgQIBAABNQAECgoKIwAHAIIaAA==.Astrialynn:BAAANQADCgYIBwABNQADCgcIBwAIAAAAAA==.Astrulawa:BAAANQAECgQICgAAAA==.',
At='Athrea:BAABNQAECn8yAAIHAAoKRyL8IwCyAgAHAAoKRyL8IwCyAgAAAA==.',
Au='Aurhiel:BAAANQABCgMIBAAAAA==.',
Av='Avasharm:BAAANQABCgYIBgABNQABCgYIAgAIAAAAAA==.',
Ba='Barakah:BAAANQAECgQIAwAAAA==.Barnre:BAAANQAECgIIBAAAAA==.Battlelord:BAAANQAECgIIBAAAAA==.',
Bd='Bdssm:BAAANQAECgcIBwAAAA==.',
Be='Bearito:BAAANQAECgQIDwAAAA==.Beefstick:BAABNQAECn8hAAIGAAoKZBLIhwD7AQAGAAoKZBLIhwD7AQAAAA==.Beserkfury:BAABNQAECn8tAAIFAAoKEApwGwCPAQAFAAoKEApwGwCPAQAAAA==.',
Bi='Biercan:BAAANQAECgYIDAAAAA==.Bigcarl:BAAANQAECgEIAQAAAA==.Binke:BAAANQADCgQIBAAAAA==.Bittyboop:BAAANQADCggICwABNQAECgUICAAIAAAAAA==.Bittywhite:BAAANQAECgUICAAAAA==.Bittywyvern:BAAANQADCgUIBQABNQAECgUICAAIAAAAAA==.',
Bj='Bjarna:BAAANQAECggIEQAAAA==.',
Bl='Blayze:BAAANQAECgYIDwAAAA==.Blinkytime:BAABNQAECn8tAAIEAAgKuRT0rwC/AQAEAAgKuRT0rwC/AQAAAA==.Bloodskull:BAAANQADCgEIAQAAAA==.Blúnt:BAAANQADCgQIBAAAAA==.',
Bo='Bobheals:BAABNQAECn9EAAIJAAoKYhz0EACfAgAJAAoKYhz0EACfAgAAAA==.Boibye:BAAANQAECgQICwAAAA==.Bolblock:BAAANQAECggIDwAAAA==.Bolo:BAACNQAFFH8KAAIKAAMKZhCLDwC7AAAKAAMKZhCLDwC7AAA1AAQKfzYAAgoACgqdH6kHACsDAAoACgqdH6kHACsDAAAA.Boostedww:BAAANQAECgQICwAAAA==.Borkoir:BAAANQAECggIDgABNQAECggIEQAIAAAAAA==.Bowlo:BAAANQAFFAIIAgAAAA==.Bowzo:BAAANQAECgMIAwAAAA==.',
Br='Brambleclaw:BAABNQAECn89AAILAAoKZCBFDABQAwALAAoKZCBFDABQAwAAAA==.Brayker:BAABNQAECn8+AAIEAAoKhyM6IgA7AwAEAAoKhyM6IgA7AwAAAA==.Breadoneal:BAABNQAECn8xAAMCAAoKVRpGGwDOAgACAAoKVRpGGwDOAgAEAAMKqQasXQGKAAAAAA==.Brewed:BAAANQAECgMIBAAAAA==.Brynjamin:BAAANQAECgQICAAAAA==.Brüenor:BAAANQAECgMIBQAAAA==.',
Bu='Bubbi:BAAANQADCgEIAQAAAA==.Bukkorosuzo:BAAANQAECgUIEgAAAA==.Burntroot:BAABNQAECn8fAAIMAAcK5APuuAAgAQAMAAcK5APuuAAgAQAAAA==.',
['Bá']='Bálor:BAAANQAECgUIDgAAAA==.',
Ca='Cacci:BAAANQADCgcIBwAAAA==.Caedwyn:BAAANQAECgYIEgAAAA==.Camdakablam:BAAANQAECgcIEQAAAA==.Careadin:BAAANQADCgQIBAABNQAECggIGwANAGsgAA==.Careradin:BAABNQAECn8bAAINAAgKayBaDABwAgANAAgKayBaDABwAgAAAA==.Carereaper:BAAANQAECgEIAQABNQAECggIGwANAGsgAA==.Cartilage:BAABNQAECn8dAAMHAAkKQQ0qOAAoAQAHAAkKMAwqOAAoAQAOAAcKhQsMbQDqAAAAAA==.Cassieruth:BAAANQAECggICgAAAA==.Catalei:BAAANQAECgEIAQAAAA==.',
Ce='Centrest:BAAANQADCgYJCAAAAA==.Cerus:BAAANQADCgEIAQAAAA==.',
Ch='Chebbles:BAAANQADCgUIBgABNQAECgcIJAAPAMwRAA==.Chillidan:BAAANQAECgMIAwABNQAECgkJKQAQAFMhAA==.Chivi:BAAANQADCggIDgABNQAECggIIgARAKIcAA==.Chonkmonk:BAAANQADCgQIBAAAAA==.Chupacabrass:BAAANQAECgIIAgAAAA==.Chupanibre:BAAANQADCgMIAwABNQAECgcIJAAPAMwRAA==.Chëbbles:BAAANQAECgMIAwABNQAECgcIJAAPAMwRAA==.',
Co='Colman:BAAANQAECgUIEgAAAA==.Coorsbanquet:BAABNQAECn8iAAMSAAoKFhHuJABeAQASAAoKIBDuJABeAQATAAUKWxAXFwDQAAABNQAECgoKJQAKAGwRAA==.Coorsbite:BAABNQAECn8lAAQKAAoKbBH/FgBsAQAKAAYK6BL/FgBsAQAUAAkK5A0ICwA5AQARAAUKmQgVKQDlAAAAAA==.Coorslight:BAAANQADCgYIBgABNQAECgoKJQAKAGwRAA==.Corrahthecow:BAAANQAECgEIAQABNQAECgoKJQAKAGwRAA==.',
Cr='Craccjar:BAAANQADCgYIBwAAAA==.Crackjar:BAAANQADCgUICAAAAA==.Croc:BAAANQAECgcIEAAAAA==.Crudala:BAAANQADCgcICQABNQAECgMIAgAIAAAAAA==.Crystle:BAABNQAECn8wAAIVAAoKfAsdUADjAQAVAAoKfAsdUADjAQAAAA==.Crystlemarie:BAAANQADCgMIAwAAAA==.',
Cs='Csyasha:BAAANQADCgcIBwABNQAECgoKHAAWAI0LAA==.',
Cu='Cubcadet:BAABNQAECn8tAAIEAAoK+xqXSQC4AgAEAAoK+xqXSQC4AgAAAA==.',
Cy='Cybear:BAABNQAECn8qAAIXAAoKlRquJwBiAgAXAAoKlRquJwBiAgAAAA==.',
Da='Dalanora:BAABNQAECn88AAQXAAoKYBp3JgDqAgAXAAoKYBp3JgDqAgABAAMKXRUdQwC4AAAYAAMKpBafGwCkAAAAAA==.Dammned:BAAANQAECgQIBAAAAA==.Dapalyu:BAABNQAECn8vAAMZAAoKYRFCKwCDAQAZAAkKLhJCKwCDAQAEAAgKYQX1EwH+AAAAAA==.Davidx:BAAANQADCgQIBgAAAA==.',
De='Dekig:BAAANQAECgEIAQAAAA==.Demine:BAAANQAECgMIBAAAAA==.Detrazeral:BAAANQADCggIEAAAAA==.',
Di='Dico:BAAANQAECgcICgABNQAFFAcIGwANAB8XAA==.Dipper:BAABNQAECn82AAIEAAoKkhacegA2AgAEAAoKkhacegA2AgAAAA==.',
Do='Dohan:BAAANQADCggIEAAAAA==.Dorìan:BAAANQADCggIFgAAAA==.Dorÿ:BAAANQADCgcIBwAAAA==.',
Dr='Draetona:BAAANQADCggIGQAAAA==.Druidthings:BAAANQADCgUIBQAAAA==.',
Ee='Eeveeko:BAABNQAECn8uAAIaAAoK6xcCDACwAgAaAAoK6xcCDACwAgAAAA==.',
Ej='Ejavuday:BAABNQAECn8wAAMDAAoKhR5CQQACAwADAAoKhR5CQQACAwAbAAEKgR2cRwA1AAAAAA==.',
En='Enerchi:BAABNQAECn8pAAIQAAkKUyF8CgArAwAQAAkKUyF8CgArAwAAAA==.',
Er='Erianar:BAAANQADCgEIAQAAAA==.Ervyne:BAABNQAECn8iAAMGAAoKvhCTbAA5AgAGAAoKnRCTbAA5AgAFAAUKmAaaUgDeAAAAAA==.',
Ev='Evera:BAABNQAECn8oAAIHAAoKhwt2JACoAQAHAAoKhwt2JACoAQAAAA==.Evos:BAAANQADCgYJBgAAAA==.',
Ex='Exning:BAAANQADCggICAAAAA==.',
Fa='Fatherømally:BAAANQAECggIBAABNQAECgkJIQAEAMoWAA==.Fauci:BAAANQAECgYIBgABNQAFFAYIEQAWAC4hAA==.',
Fe='Feihao:BAAANQAECgEIAQAAAA==.Feile:BAABNQAECn8zAAMXAAoKgA+vawAaAgAXAAoKgA+vawAaAgABAAEKAAArcQA+AAAAAA==.Feltree:BAAANQADCgQIBAAAAA==.',
Fi='Fishbox:BAAANQABCgYIDAAAAA==.',
Fl='Flashir:BAAANQADCgIIAgAAAA==.Flinzza:BAABNQAECn8kAAMaAAkKYxd3GADgAQAaAAkKYxd3GADgAQAcAAgK2hSnaQDPAQAAAA==.Flyknit:BAABNQAECn8XAAIEAAYKZRKc2gBmAQAEAAYKZRKc2gBmAQAAAA==.',
Fr='Fredthedh:BAABNQAECn8jAAMSAAoKjBeVIwAsAgASAAgKXxeVIwAsAgAdAAUKChaTXwCRAAAAAA==.Fromtheback:BAAANQAECgIIAgABNQAECgoKHwAHAMESAA==.Frosticals:BAABNQAECn8tAAIDAAkK4CEvQAAFAwADAAkK4CEvQAAFAwAAAA==.Frostsugar:BAAANQABCgQIBgAAAA==.',
Ga='Gaashw:BAAANQABCgQIBwAAAA==.Gabtvsorcere:BAAANQADCgYICgAAAA==.Ganandor:BAABNQAECn8kAAIWAAoKVBzaGwCfAgAWAAoKVBzaGwCfAgAAAA==.Garroz:BAAANQADCgEIAQAAAA==.Gaulish:BAAANQAECgQICAAAAA==.',
Ge='Geocide:BAABNQAECn8VAAIMAAcKVB3oVgAeAgAMAAcKVB3oVgAeAgAAAA==.Getagrip:BAAANQAECggIDAABNQAFFAQIDAAWAOMTAA==.Gethalyn:BAAANQAECgUIBwAAAA==.',
Gh='Ghasch:BAABNQAECn8cAAIcAAoK0BugFwDlAgAcAAoK0BugFwDlAgAAAA==.Ghume:BAAANQAECgQIDAAAAA==.',
Gi='Gianthippo:BAAANQADCgYICgABNQAECgkJFAALADcJAA==.Gilf:BAACNQAFFH8QAAIaAAYKjx8uAQB5AQAaAAYKjx8uAQB5AQA1AAQKfyMAAxoACgptI9ABAJoDABoACgptI9ABAJoDAAwABAqCCIzsAL4AAAE1AAUUBwgRABgAHRkA.',
Go='Goursh:BAAANQAECgEIAQAAAA==.',
Gr='Grizzoul:BAABNQAECn8cAAMUAAcKTgO9FADiAAAUAAcKTgO9FADiAAARAAMKxwEdNwBWAAAAAA==.Grreenry:BAAANQAECgEIAQAAAA==.Grumly:BAABNQAECn8dAAIbAAYKaw1RHgD6AAAbAAYKaw1RHgD6AAAAAA==.',
Ha='Hanswoloqued:BAACNQAFFH8KAAIXAAUKVwhKGgDFAAAXAAUKVwhKGgDFAAA1AAQKfy8AAhcACgqZFCtaAEgCABcACgqZFCtaAEgCAAAA.Haxz:BAAANQADCgUIBQAAAA==.',
He='Healufast:BAABNQAECn8zAAIVAAoKrx6eKgC+AgAVAAoKrx6eKgC+AgAAAA==.Heck:BAAANQADCgYIBgAAAA==.Helstrom:BAAANQAECgIIAQAAAA==.',
Hj='Hjalmar:BAABNQAECn8sAAMCAAoK6Bl2RQDrAQACAAkKwBl2RQDrAQAEAAcK9wzl/gDWAAAAAA==.',
Ho='Holycõw:BAABNQAECn8hAAIEAAkKyhbfkwCPAQAEAAkKyhbfkwCPAQAAAA==.Holysabeline:BAABNQAECn8+AAICAAoKxB9SHwDzAgACAAoKxB9SHwDzAgAAAA==.Hotpots:BAAANQAECggIEgAAAA==.Hotwíngs:BAAANQAECgcICQAAAA==.',
Hu='Huchar:BAABNQAECn9DAAINAAoKliCVBwBgAgANAAoKliCVBwBgAgAAAA==.Humpf:BAAANQADCgEIAQAAAA==.Hunterpanda:BAAANQADCgYIBgAAAA==.',
Hy='Hydraxix:BAAANQADCggICAAAAA==.Hypnose:BAAANQADCggIFQAAAA==.',
Ic='Iceblade:BAABNQAECn8fAAICAAoKvBlhPQAOAgACAAoKvBlhPQAOAgAAAA==.',
Id='Idtrapdat:BAAANQAECgIIAgAAAA==.',
If='If:BAAANQADCgQIBAAAAA==.',
In='Incowgnito:BAAANQAECgcICQAAAA==.Invoice:BAAANQAECgUIBQAAAA==.',
Ir='Ironßest:BAAANQABCgUICwAAAA==.',
Ja='Jadzi:BAAANQADCgYJCwAAAA==.Jaxxion:BAAANQADCgYIBgAAAA==.',
Je='Jessaiyan:BAABNQAECn8UAAISAAoK2g/AHQCiAQASAAoK2g/AHQCiAQAAAA==.',
Jo='Jobo:BAABNQAECn8vAAMJAAoKSxhaDQDdAgAJAAoKSxhaDQDdAgAPAAUKZASNhgC4AAAAAA==.Jobodot:BAABNQAECn8YAAIXAAcKSwdVyQA3AQAXAAcKSwdVyQA3AQAAAA==.',
Ju='Julaudette:BAAANQAECgQIBQAAAA==.Juliania:BAAANQADCgYIBwAAAA==.Julzaria:BAABNQAECn8kAAIGAAoKHA8rVAANAgAGAAoKHA8rVAANAgAAAA==.Jurny:BAABNQAECn8qAAMBAAcKURCRDADmAAABAAcKURCRDADmAAAYAAIKVAVDJQBZAAAAAA==.',
Ka='Kahlandra:BAABNQAECn88AAIDAAoKJhaheQCLAgADAAoKJhaheQCLAgAAAA==.Kaizer:BAABNQAECn81AAIMAAkKLRkTNgCfAgAMAAkKLRkTNgCfAgAAAA==.Kandera:BAAANQADCgUIBQAAAA==.Karina:BAAANQADCgUJBQABNQAECgoKPwAGAD0kAA==.',
Ke='Keizer:BAAANQAECgEIAQAAAA==.Keunen:BAABNQAECn8fAAMPAAcKIAYbUwDAAAAPAAcKIAYbUwDAAAAJAAMKdwK2dgAyAAAAAA==.Kevlock:BAAANQADCgYIBgAAAA==.Keyzer:BAAANQAECggIEQAAAA==.',
Kh='Khanjuror:BAAANQAECgEIAQAAAA==.Kharún:BAAANQAECgYIBAAAAA==.Khornedog:BAABNQAECn8yAAIXAAoKhBv+VgBRAgAXAAoKhBv+VgBRAgAAAA==.Khrama:BAABNQAECn8+AAILAAoK6CVVCwBYAwALAAoK6CVVCwBYAwAAAA==.',
Kl='Kleenonean:BAACNQAFFH8YAAIeAAcKqSVzAgD7AQAeAAcKqSVzAgD7AQA1AAQKf6AAAh4ACgp5JicAAAsEAB4ACgp5JicAAAsEAAAA.',
Kn='Knut:BAAANQAECgQICAAAAA==.',
Kr='Krackjarr:BAABNQAECn8oAAIXAAoKTwlgeABfAQAXAAoKTwlgeABfAQAAAA==.Kredor:BAAANQAECgIIBAAAAA==.Kriptonic:BAAANQADCgIIAgAAAA==.Kriptskeeper:BAAANQAECgQIBAAAAA==.Kris:BAAANQAECgEIAQAAAA==.',
Ku='Kungpowbeef:BAAANQAECgIIAgAAAA==.Kurzaan:BAAANQAECgMIAgAAAA==.Kuyaj:BAAANQADCgIIAgAAAA==.',
La='Lacio:BAABNQAECn87AAIeAAoKwQf2MQCTAQAeAAoKwQf2MQCTAQAAAA==.Larune:BAAANQABCgEIAQAAAA==.',
Le='Lemonpepper:BAACNQAFFH8HAAIKAAQK7wWkDQDrAAAKAAQK7wWkDQDrAAA1AAQKfywAAgoACgrqEtUbAA0CAAoACgrqEtUbAA0CAAAA.Lexxix:BAAANQADCgcIDAAAAA==.Leyru:BAAANQAECgUIDAAAAA==.',
Li='Liberos:BAABNQAECn8dAAIcAAcKlBQxYQB9AQAcAAcKlBQxYQB9AQAAAA==.Lilnimjr:BAAANQADCgYICAAAAA==.Littlechiken:BAAANQADCgUIBQABNQAFFAUIDAALAIgMAA==.',
Ln='Lninedkhack:BAABNQAECn8jAAMHAAoKghqeIgC3AQAHAAoKghqeIgC3AQAOAAIK9AdclQBhAAAAAA==.',
Lo='Logaar:BAABNQAECn81AAMCAAoKqRFaTgAxAgACAAkKfBBaTgAxAgAEAAoK/QpYvQCiAQAAAA==.',
Lu='Lubuu:BAAANQADCggIGgAAAA==.Lucyfurrawr:BAABNQAECn8aAAIfAAkKOBQcEgCFAQAfAAkKOBQcEgCFAQABNQAECgoKIgAQAM8ZAA==.Lunala:BAAANQADCgcIBwABNQAECgMIAgAIAAAAAA==.Luxurix:BAAANQADCggIEQAAAA==.',
Ma='Maer:BAAANQADCgQIBAAAAA==.Magtao:BAAANQADCgYIEQAAAA==.Malexannius:BAAANQADCgYIDwAAAA==.Manastorm:BAABNQAECn8lAAIDAAoKgQYTgwCQAQADAAoKgQYTgwCQAQAAAA==.Maplebrick:BAAANQABCgIIAgAAAA==.Mariangel:BAAANQADCgEIAQAAAA==.Marric:BAAANQAECggJCgAAAA==.',
Me='Medean:BAAANQADCggICAAAAA==.Megtallica:BAABNQAECn8eAAIEAAYKmAY4OAHGAAAEAAYKmAY4OAHGAAAAAA==.Mehunglow:BAAANQADCgUICAAAAA==.Mellissaa:BAAANQADCggIEgAAAA==.Mensrea:BAABNQAECn8sAAMMAAoKRQsaSACeAQAMAAoKRQsaSACeAQAcAAEKmwIC/wAmAAAAAA==.Merrycold:BAABNQAECn8dAAMHAAgKdxdQSwDoAQAHAAgKdxdQSwDoAQAOAAUKQxBAbADtAAABNQAECgoKHwAQALIYAA==.',
Mf='Mfgirthquake:BAABNQAECn9mAAMaAAoKNyWXAgAqAwAaAAoKNyWXAgAqAwAcAAYKCh37jQD3AAAAAA==.',
Mi='Miisty:BAABNQAECn8YAAIDAAgKtwLI8wC4AAADAAgKtwLI8wC4AAAAAA==.Mikklelee:BAAANQADCggIDwAAAA==.Mings:BAAANQAECgQICAAAAA==.Miniborohs:BAAANQAECgEIAQAAAA==.Mistweaver:BAABNQAECn9RAAIgAAoKySW6AwB0AwAgAAoKySW6AwB0AwAAAA==.',
Mo='Mochi:BAABNQAECn88AAIDAAoKvReHTgAVAgADAAoKvReHTgAVAgAAAA==.Mochïi:BAAANQADCgIJBAABNQAFFAgIFgADAO0TAA==.Moghorva:BAAANQAECgcIBgAAAA==.Mojoe:BAABNQAECn8mAAIcAAoK9Bo5MAChAgAcAAoK9Bo5MAChAgAAAA==.Mommyswaggin:BAAANQAECgYIBwAAAA==.Moopster:BAABNQAECn8wAAIVAAoKbSTMCgBsAwAVAAoKbSTMCgBsAwAAAA==.Moopy:BAAANQAECgQIBAABNQAECgoKMAAVAG0kAA==.Mootangclan:BAABNQAECn8XAAIMAAgKtxnkTQA/AgAMAAgKtxnkTQA/AgAAAA==.Moxi:BAAANQABCgUIBQAAAA==.',
Na='Nalthexon:BAAANQAECgYICwAAAA==.Nanashi:BAACNQAFFH8HAAIOAAQKLgrWDgDNAAAOAAQKLgrWDgDNAAA1AAQKfywAAg4ACQrNIgEJABQDAA4ACQrNIgEJABQDAAAA.Nazgru:BAAANQADCgYIDAAAAA==.',
Ne='Necros:BAAANQAECgIIAgABNQAFFAcIGgAMAAMXAA==.Neiko:BAACNQAFFH8KAAMhAAUKVgqeFADUAAAhAAUKUwmeFADUAAAWAAIKmwpqCwCCAAA1AAQKfyoAAxYACgr6GFwjAG0CABYACgoKF1wjAG0CACEABAq1HFRqAEsBAAAA.Neptuneakis:BAABNQAECn8kAAIPAAcKzBGVUgCRAQAPAAcKzBGVUgCRAQAAAA==.Neptuno:BAAANQADCgEIAQABNQAECgcIJAAPAMwRAA==.Newcarsmell:BAAANQADCggIJgAAAA==.',
Ng='Ngl:BAAANQAECgcIDQAAAA==.',
Ni='Niceknife:BAAANQADCggIDQAAAA==.Nicomi:BAABNQAECn8gAAIbAAoKyAjhDgCFAQAbAAoKyAjhDgCFAQAAAA==.Nightwinger:BAAANQAECgUICAAAAA==.Nimrose:BAAANQAECgIIBAAAAA==.Niquid:BAABNQAECn8nAAIJAAoK8hGKGgAbAgAJAAoK8hGKGgAbAgAAAA==.Nivek:BAAANQAECgQICAAAAA==.Niylea:BAAANQADCgUIBQABNQAECgoKMgAHAEciAA==.',
No='Nobu:BAACNQAFFH8RAAMWAAYKLiEgBAAKAgAWAAUKViEgBAAKAgAhAAMKgRu8FgC4AAA1AAQKf0AAAxYACgpAJr4CALADABYACgrZJb4CALADACEACgqnItwKABoDAAAA.Noobhuntard:BAAANQADCggICAAAAA==.Norinari:BAACNQAFFH8RAAQYAAcKHRm6AQAXAQAXAAQKOBQAGAA1AQAYAAQKHBq6AQAXAQABAAIKcBeODgCZAAA1AAQKf0EABBgACgp5JIwEAJACABgABwqrJIwEAJACABcABwodI69BAI0CAAEAAwoKG+0vAAkBAAAA.Notahealer:BAAANQAECgcIEQABNQAECggIEgAIAAAAAA==.Noxloxes:BAAANQADCgIIAgAAAA==.',
Oa='Oakshre:BAABNQAECn88AAIQAAoKiR44CwAhAwAQAAoKiR44CwAhAwAAAA==.',
Ob='Obliteration:BAAANQAECgYIDQABNQAECgkJKQAQAFMhAA==.',
Od='Odsw:BAAANQADCgMJAwAAAA==.',
Oe='Oenaa:BAAANQAECgUIBAAAAA==.',
Ol='Olivertwist:BAAANQAECgQIDAABNQAECgkJKQAQAFMhAA==.',
On='Ontwou:BAABNQAECn8pAAIGAAoK7BxvYwBPAgAGAAoK7BxvYwBPAgAAAA==.',
Or='Orbz:BAABNQAECn9BAAIDAAoK+iT4KQA9AwADAAoK+iT4KQA9AwAAAA==.Orcazm:BAAANQAECgIIAQAAAA==.',
Pa='Padova:BAAANQAECgMIAwAAAA==.Palyont:BAAANQAECgMIBQAAAA==.Pancakezebra:BAABNQAECn9OAAIiAAoK4xuxAgCOAgAiAAoK4xuxAgCOAgAAAA==.Parse:BAAANQAECgIIAwAAAA==.',
Pe='Perdido:BAAANQADCgIIAgAAAA==.',
Ph='Phoenix:BAABNQAECn8tAAIEAAoKbBvQggAiAgAEAAoKbBvQggAiAgAAAA==.',
Pi='Pikechu:BAAANQAECgYIEAAAAA==.Pinkskies:BAAANQAECgIIAgAAAA==.',
Pl='Playless:BAAANQAECgYIDgAAAA==.Pleasy:BAAANQAECgUIBwAAAA==.Plugtobacca:BAAANQADCgIIAgABNQAFFAYIEQAWAC4hAA==.',
Po='Pocketchange:BAACNQAFFH8HAAMMAAQKsAt4EgDMAAAMAAQKsAt4EgDMAAAcAAIKzAiYIwBxAAA1AAQKfygAAxwACgqJF1BSAB0CABwACgqJF1BSAB0CAAwACAomE8R5AAkBAAAA.Pocketwatch:BAAANQAECggIDwABNQAFFAQIBwAMALALAA==.',
Pr='Prayze:BAAANQADCgYIBgAAAA==.Preservation:BAAANQADCgIIAgABNQAECgoKUQAgAMklAA==.Promethêus:BAAANQAECgIIAQAAAA==.',
Pu='Purefriction:BAAANQADCgYICQAAAA==.Purehate:BAAANQAECgUIDAAAAA==.',
Qr='Qrz:BAAANQADCgMIAwAAAA==.',
Rb='Rbackwards:BAAANQADCgUIBQABNQAECgoKLgAXADEZAA==.',
Re='Re:BAAANQAECgIIAwAAAA==.Relovan:BAABNQAECn8vAAMNAAoKSRTPFgBBAQAjAAoKNgxqZQC6AQANAAQKMRzPFgBBAQAAAA==.Renothidan:BAACNQAFFH8IAAIEAAMKiwqUJAB8AAAEAAMKiwqUJAB8AAA1AAQKfy0AAgQACgo+GiVcAIQCAAQACgo+GiVcAIQCAAAA.Ret:BAAANQADCgcICQABNQAECgoKZgAaADclAA==.Reuben:BAAANQAECgEIAQAAAA==.Revin:BAABNQAECn84AAIEAAoKbxcjcADbAQAEAAoKbxcjcADbAQAAAA==.Revrynth:BAABNQAECn8iAAQRAAgKohx2DwBjAgARAAgKohx2DwBjAgAKAAUKNhqvGwAqAQAUAAQKEBXjFADgAAAAAA==.Rexorcist:BAAANQAECgYICQAAAA==.',
Ri='Rimed:BAABNQAECn8cAAMDAAgKZw3f8ACpAQADAAgKRwzf8ACpAQAbAAEKaBCvRwA1AAAAAA==.Rippèd:BAAANQADCgYIBgAAAA==.Rithcice:BAAANQADCgcIBwAAAA==.Rizzard:BAABNQAECn8pAAMMAAoKLxvBGwCDAgAMAAoKLxvBGwCDAgAcAAEKGgMW/gAnAAAAAA==.Rizzdolphler:BAACNQAFFH8JAAICAAQKtA5ZEwAsAQACAAQKtA5ZEwAsAQA1AAQKfzEAAwIACgq/HVEiAOMCAAIACgq/HVEiAOMCAAQABwo2Do3wAOwAAAAA.',
Ro='Rorän:BAAANQAECgMIAwAAAA==.',
['Rö']='Rönburgundy:BAABNQAECn8uAAIXAAoKMRnwTABtAgAXAAoKMRnwTABtAgAAAA==.',
Sa='Sanako:BAAANQAECgcIDgAAAA==.Saneros:BAAANQAECgQIBAAAAA==.',
Sc='Scraggle:BAAANQAECgQIBQAAAA==.Scuffito:BAAANQAECgMIBAAAAA==.',
Sd='Sdh:BAAANQADCgEIAQAAAA==.',
Se='Seasondpally:BAAANQADCgcIBwAAAA==.Setheron:BAAANQAECgUIEgAAAA==.',
Sh='Shamnira:BAAANQAECgYICAAAAA==.Shamtul:BAAANQABCgYIEgAAAA==.Shlea:BAABNQAECn8nAAIUAAoKYAp4CwCoAQAUAAoKYAp4CwCoAQAAAA==.Shley:BAAANQADCgYIBgABNQAECgoKJwAUAGAKAA==.',
Si='Silvanna:BAAANQAECgYIDAAAAA==.Sivi:BAAANQAECgIIAgAAAA==.',
Sl='Slinkstir:BAAANQADCgYIBgAAAA==.',
Sm='Smh:BAAANQAECgQIBAAAAA==.',
Sn='Sneak:BAAANQAECgQIBQABNQAECgoKZgAaADclAA==.',
So='Solendros:BAAANQAECgQIBAAAAA==.Sonoa:BAAANQAECggICgAAAA==.Sonthar:BAAANQADCgQJBAAAAA==.Sorix:BAAANQADCgIIAgAAAA==.Sorlight:BAABNQAECn8XAAIZAAcKkBwCGwAWAgAZAAcKkBwCGwAWAgAAAA==.Soulelf:BAAANQADCgEIAQAAAA==.Sourpets:BAABNQAECn8VAAIGAAcKURqJWABqAgAGAAcKURqJWABqAgAAAA==.Sourshocks:BAAANQAECgEIAQAAAA==.Sourwords:BAAANQAECgEIAQAAAA==.',
St='Standarshh:BAABNQAECn86AAIGAAoKmiCIJwD6AgAGAAoKmiCIJwD6AgAAAA==.Stevenz:BAABNQAECn8pAAIDAAoKiiCPKQA+AwADAAoKiiCPKQA+AwAAAA==.Stillflygon:BAAANQADCgYIEgAAAA==.Stormcare:BAAANQADCgUIBQAAAA==.',
Su='Subtle:BAACNQAFFH8MAAMWAAQK4xP5BQDaAAAWAAQK4xP5BQDaAAAhAAEKYwEEFwA4AAA1AAQKfy8AAxYACQpJHlMgAH8CABYACQpJHlMgAH8CACEABgrlFKojAKsBAAAA.Sugarbabi:BAAANQAECggIEwAAAA==.Sugarrush:BAAANQADCggIDgAAAA==.Sugarshot:BAAANQAECgIIAgAAAA==.Sugartotem:BAAANQAECgUICgAAAA==.Sunmere:BAAANQADCgUIBQAAAA==.',
Sw='Swiftwing:BAAANQADCgQIBAAAAA==.',
Sy='Sydarliia:BAAANQAECgYIEAAAAA==.Sylrianah:BAABNQAECn89AAIVAAoK6g/rYwD0AQAVAAoK6g/rYwD0AQAAAA==.Sylveste:BAACNQAFFH8NAAICAAYKYQpPCgCUAQACAAYKYQpPCgCUAQA1AAQKfzAAAgIACgoAHJgiAJwCAAIACgoAHJgiAJwCAAAA.',
Ta='Tae:BAAANQAECgYICAAAAA==.Tal:BAAANQAECggIDgABNQAECgkJIQAEAMoWAA==.Talis:BAAANQAECgEIAQAAAA==.Talridor:BAAANQADCgcIBgAAAA==.Tankhiskhan:BAABNQAECn8UAAILAAkKNwnVZwBUAQALAAkKNwnVZwBUAQAAAA==.Tarlis:BAABNQAECn8XAAMXAAkKfwxcUADQAQAXAAkKfwxcUADQAQAYAAcKOwaiEQAAAQAAAA==.',
Te='Tei:BAAANQAECggIDQAAAA==.Telys:BAAANQADCgUIBQAAAA==.Terily:BAAANQADCgcICgAAAA==.Terithresh:BAAANQAECgEIAQAAAA==.Tetchy:BAAANQADCgQIBAABNQAFFAQIDAAWAOMTAA==.',
Th='Thannill:BAABNQAECn8tAAIHAAkKghR7IADJAQAHAAkKghR7IADJAQAAAA==.',
Ti='Ticktoklock:BAAANQAECggIDAAAAA==.Tie:BAABNQAECn8zAAIZAAkKJhuvDABQAgAZAAkKJhuvDABQAgAAAA==.Tirala:BAABNQAECn8WAAIdAAoKMiJrCwDbAgAdAAoKMiJrCwDbAgAAAA==.',
To='Tomari:BAAANQABCgEIAQAAAA==.Tomias:BAAANQADCgMIAwAAAA==.Torzhu:BAAANQAECgUIEwAAAA==.Toy:BAAANQAECggIDwABNQAFFAgIGwAKANMTAA==.',
Tr='Trauck:BAAANQAECgUIDwAAAA==.Travvy:BAACNQAFFH9GAAMhAAkKvyF5AADrAgAWAAkKoBhsAAAyAwAhAAkKMSF5AADrAgA1AAQKfycAAyEACgqIJrUDAGMDACEACgovIrUDAGMDABYAAwr2IAxmABoBAAAA.Trevmo:BAABNQAECn8lAAMjAAoKqxT6cABBAgAjAAoK3hH6cABBAgANAAYKPxO3GgAZAQAAAA==.Trexin:BAAANQAECgIIAwAAAA==.',
Tu='Turaylon:BAAANQADCgQIBAAAAA==.',
Tz='Tzuyu:BAABNQAECn8/AAMGAAoKPSSlCACXAwAGAAoKPSSlCACXAwAFAAEKIxGwhwA2AAAAAA==.',
Ud='Uddershock:BAAANQAECgUIBQAAAA==.',
Un='Unapologetic:BAAANQAECgUIBQABNQAECgoKUQAgAMklAA==.Unbreakabull:BAACNQAFFH8GAAIPAAQKUhwQDgD8AAAPAAQKUhwQDgD8AAA1AAQKfyUAAg8ACgqgI4QHAJUDAA8ACgqgI4QHAJUDAAAA.Unver:BAAANQADCgYIBgAAAA==.',
Va='Vae:BAAANQAECgYJEQABNQAECgoKIgAQAM8ZAA==.Valka:BAAANQAECgEIAQAAAA==.Vanthrall:BAAANQADCgUIBQAAAA==.',
Ve='Veldtt:BAAANQADCgIIAgAAAA==.Velera:BAABNQAECn8fAAIDAAkKpAcSnwBTAQADAAkKpAcSnwBTAQAAAA==.Vesemir:BAAANQADCgcIBwAAAA==.Veyle:BAABNQAECn89AAMWAAoKsyMhAgC/AwAWAAoKsyMhAgC/AwAhAAYK1B00HQDpAQAAAA==.',
Vi='Viibryd:BAAANQAECgQIBgAAAA==.Vine:BAAANQAECgQIBAAAAA==.',
Vy='Vyel:BAAANQADCgIIAgAAAA==.Vyndria:BAAANQADCgcIDQAAAA==.Vynstus:BAAANQADCggIHAAAAA==.Vyran:BAAANQADCgIIAgAAAA==.',
Wa='Waypal:BAAANQADCggIFwAAAA==.',
We='Weashadow:BAAANQAECgcICgAAAA==.Weashock:BAAANQADCgYIDAAAAA==.Weasy:BAABNQAECn8WAAIGAAkK6yEPKwCGAgAGAAkK6yEPKwCGAgAAAA==.',
Wi='Windfury:BAABNQAECn8wAAIaAAoKqSJCAgCJAwAaAAoKqSJCAgCJAwAAAA==.Wingzard:BAABNQAECn8fAAIDAAgKZxV4tAAaAgADAAgKZxV4tAAaAgAAAA==.',
Wo='Wowdudesame:BAABNQAECn8ZAAIjAAgKrxqKagBRAgAjAAgKrxqKagBRAgABNQAECgoKZgAaADclAA==.',
Xl='Xl:BAABNQAECn8xAAIdAAoKYBoJIwCDAgAdAAoKYBoJIwCDAgAAAA==.',
Ya='Yaitoopmfp:BAABNQAECn8fAAQQAAoKshjRGQBzAgAQAAkKPhjRGQBzAgAgAAcKbg+4GABdAQAkAAEKvBwCIQBTAAAAAA==.Yao:BAABNQAECn8/AAMLAAoKqiKWDgA6AwALAAoKqiKWDgA6AwAHAAEKAAAK2wA6AAAAAA==.Yasrena:BAABNQAECn8wAAMeAAoK6A/MGwCgAQAeAAkKEBHMGwCgAQAVAAoK8w3QZACZAQAAAA==.',
Ye='Yelp:BAAANQAECgYICQAAAA==.',
Za='Zabara:BAAANQADCgYIBgABNQAECgoKLAACAOgZAA==.Zair:BAAANQADCgUIBQAAAA==.Zakaraki:BAABNQAECn89AAMRAAoK0SF0BgAiAwARAAoK0SF0BgAiAwAKAAgK8hUvGgAgAgAAAA==.Zaki:BAABNQAECn8dAAISAAoKyxWWFwChAgASAAoKyxWWFwChAgAAAA==.Zappin:BAAANQAECggIDgABNQAFFAYIEQAWAC4hAA==.',
Ze='Zealot:BAABNQAECn8gAAMEAAoKrxBBvACkAQAEAAoKjRBBvACkAQAZAAYK6wgjSADNAAAAAA==.Zeleria:BAAANQAECgMIAgAAAA==.Zerathis:BAAANQADCgEJAQAAAA==.Zerro:BAAANQAECgUIBQAAAA==.',
Zi='Zinbek:BAAANQADCgUIBQAAAA==.Zip:BAAANQABCgYJBgAAAA==.Zipstin:BAAANQAECgEIAQAAAA==.',
Zo='Zo:BAAANQAECgMIAwAAAA==.Zoo:BAAANQAECgIIAgAAAA==.Zorb:BAABNQAECn81AAIPAAoK/xrfFAAgAwAPAAoK/xrfFAAgAwABNQAFFAIIBQAXALsIAA==.Zoshow:BAAANQAECgUICgAAAA==.Zoshôw:BAAANQAECgcIBwAAAA==.',
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
