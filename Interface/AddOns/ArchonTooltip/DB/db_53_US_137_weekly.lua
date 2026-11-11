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

local lookup = {'DemonHunter-Vengeance','Paladin-Retribution','Shaman-Restoration','Shaman-Elemental','Unknown-Unknown','Druid-Balance','DeathKnight-Unholy','Druid-Feral','Warrior-Arms','Mage-Arcane','Monk-Windwalker','Shaman-Enhancement','DeathKnight-Frost','Druid-Restoration','Priest-Holy','Evoker-Devastation','Paladin-Protection','Hunter-BeastMastery','DemonHunter-Devourer','Warlock-Demonology','Warlock-Destruction','Monk-Mistweaver','Hunter-Survival','Priest-Shadow','Priest-Discipline','DeathKnight-Blood','Evoker-Preservation','Paladin-Holy','Rogue-Subtlety','Rogue-Assassination','Warrior-Protection','Warlock-Affliction','Evoker-Augmentation','Monk-Brewmaster','Mage-Frost',}
local provider = {region='US',realm='Korialstrasz',name='US',type='weekly',zone=53,date='2026-11-10',data={Ac='Accursed:BAACNQAFFH8MAAIBAAUKpRtDAQAWAQABAAUKpRtDAQAWAQA1AAQKfy8AAgEACgq6I/EBAHkDAAEACgq6I/EBAHkDAAAA.Activesloth:BAAANQADCgQJBAABNQAECgoKOAACAB0iAA==.',
Ad='Adekeai:BAABNQAECn8lAAMDAAkKMAyDdQA8AQADAAgKOAuDdQA8AQAEAAQKDQTKsgCPAAAAAA==.Adol:BAAANQADCgYIBgAAAA==.',
Ae='Aelys:BAAANQAECgQIBQABNQAECgQIBwAFAAAAAA==.',
Al='Aleighta:BAABNQAECn8gAAIDAAoK9w+8QQD2AQADAAoK9w+8QQD2AQAAAA==.Alenara:BAAANQADCgMJAwAAAA==.Allblond:BAAANQADCgYIBgAAAA==.',
Am='Amouri:BAAANQABCgIIAgAAAA==.',
An='Anacreon:BAAANQAECgcICgAAAA==.Anaiah:BAAANQADCggIDgABNQAECggIJwAGAPIEAA==.',
Ar='Arcey:BAAANQADCgIIAgAAAA==.Arun:BAAANQADCgUICAABNQAECgcIEQAFAAAAAA==.',
As='Asmodius:BAAANQADCgMIBAAAAA==.Aspros:BAABNQAECn8XAAIHAAoKFQ4HTwDYAQAHAAoKFQ4HTwDYAQAAAA==.',
At='Atlantis:BAAANQAECgUIDAAAAA==.Atonement:BAABNQAECn8kAAICAAoKphTmawDlAQACAAoKphTmawDlAQAAAA==.',
Av='Avengence:BAAANQADCgIIAgAAAA==.',
Ay='Ayshan:BAAANQAECgQIBwAAAA==.',
Ba='Badoussi:BAAANQAECgQIBwABNQAFFAYICgAIAKEQAA==.Baja:BAAANQAECggIDAAAAA==.Bakugo:BAAANQADCgMIBAAAAA==.Bananas:BAAANQAECgEIAQAAAA==.',
Be='Beansy:BAAANQADCgUICgAAAA==.Beefomancer:BAAANQAECgMIAwAAAA==.Belladin:BAABNQAECn8lAAICAAoKChbUcQBMAgACAAoKChbUcQBMAgAAAA==.Belzugaim:BAABNQAECn8UAAIJAAgKVgsFpwC7AQAJAAgKVgsFpwC7AQABNQADCgQIBwAFAAAAAA==.',
Bi='Bingcrosby:BAAANQADCgEIAQAAAA==.Bipolarcurys:BAAANQAECgUIEAAAAA==.Bismuth:BAAANQAECgcIEQAAAA==.',
Bl='Blamethedps:BAAANQAECgQIBgABNQAECgoKHgAKAEEZAA==.Blameyomomma:BAAANQAECgYICgABNQAECgoKHgAKAEEZAA==.Blamezuko:BAABNQAECn8eAAIKAAoKQRniQQA5AgAKAAoKQRniQQA5AgAAAA==.Blite:BAAANQADCggIJQAAAA==.Blumoon:BAAANQADCgcIBwAAAA==.',
Bo='Bombakaap:BAACNQAFFH8LAAILAAQKnw/HCQDLAAALAAQKnw/HCQDLAAA1AAQKfy0AAgsACgpXH4cNAHQCAAsACgpXH4cNAHQCAAAA.Bomburst:BAABNQAECn8YAAIMAAgKxwlXHAA6AQAMAAgKxwlXHAA6AQAAAA==.Bonelespizza:BAACNQAFFH8JAAINAAIKex5cFACbAAANAAIKex5cFACbAAA1AAQKf0QAAg0ACgr5IycKAAcDAA0ACgr5IycKAAcDAAAA.Bonkthump:BAAANQABCggIEAAAAA==.Boogiebabe:BAABNQAECn9DAAMOAAoKLReSEwB4AgAOAAoKLReSEwB4AgAGAAQKOwdohQC8AAAAAA==.Bornix:BAAANQAECgMIAwABNQAECgoKOwAKAHUWAA==.',
Br='Briaris:BAAANQAECgcIEAABNQAECgoKLAAIAAocAA==.Brosar:BAAANQAECgEIAQAAAA==.Brugaras:BAAANQABCgIIAgAAAA==.',
['Bê']='Bêz:BAAANQAECgMIAwAAAA==.',
['Bë']='Bëz:BAABNQAECn8hAAIBAAcK2B8kCwAgAgABAAcK2B8kCwAgAgAAAA==.',
Ca='Cadzan:BAAANQABCgUIAwAAAA==.Caith:BAAANQABCgYIBgAAAA==.Calabretta:BAAANQADCgcIGQAAAA==.Cannan:BAAANQADCgYIBgAAAA==.Captcow:BAAANQABCgYIBgAAAA==.Caver:BAAANQADCgcIDQAAAA==.',
Ch='Charysmaa:BAAANQADCggIJwAAAA==.Cheoekar:BAAANQAECgUIBwABNQAFFAUIDwAPAOYbAA==.',
Ci='Cink:BAAANQAECggICAAAAA==.',
Co='Cobey:BAABNQAECn80AAICAAoKBRlLjAANAgACAAoKBRlLjAANAgAAAA==.Coldrick:BAAANQAECgMIBgABNQAECgYIDAAFAAAAAA==.Cosmicjay:BAACNQAFFH8LAAIEAAQKOBKzEADaAAAEAAQKOBKzEADaAAA1AAQKfyIAAgQACQrDIHssAMwCAAQACQrDIHssAMwCAAAA.Cosmicnova:BAABNQAECn8cAAINAAkKqRRDNgCzAQANAAkKqRRDNgCzAQABNQAFFAQICwAEADgSAA==.',
Cr='Crumpet:BAAANQAECggIAgAAAA==.',
Cu='Cursedknight:BAAANQADCgYIEgAAAA==.',
Da='Daegán:BAAANQADCgMIAwAAAA==.Daffodil:BAABNQAECn8YAAIQAAYK4giRFADaAAAQAAYK4giRFADaAAAAAA==.Dalaney:BAAANQADCgcIDQAAAA==.Dalavian:BAAANQABCgQIBAAAAA==.Dannyhurt:BAAANQADCgcIDwAAAA==.Dantruis:BAACNQAFFH8VAAMHAAcKAxa1AgBhAQAHAAYK6hq1AgBhAQANAAEKaQLMHABJAAA1AAQKfz8AAwcACgrhIVEHAPgCAAcACgrhIVEHAPgCAA0AAwpKFKhuAM0AAAAA.Darlins:BAAANQADCgcIBwAAAA==.',
Di='Dianah:BAAANQADCgUICwAAAA==.Diggy:BAAANQADCgcIDAAAAA==.Dinsfirë:BAAANQADCgQIBgAAAA==.Diothorn:BAABNQAECn8nAAMCAAkKHwx/qwBiAQACAAkKAgt/qwBiAQARAAMKaA80VgCIAAAAAA==.Divanas:BAAANQAECgYIDwAAAA==.Divi:BAABNQAECn8ZAAIPAAgKxB0tNwBMAgAPAAgKxB0tNwBMAgAAAA==.Divinium:BAAANQADCgQIBAABNQAECggIGQAPAMQdAA==.',
Do='Dorianna:BAABNQAECn8aAAIGAAgKIAdIQwAFAQAGAAgKIAdIQwAFAQAAAA==.',
Dr='Dreamit:BAAANQADCgMIAwAAAA==.Drease:BAAANQAECgYIBwAAAA==.Drpepperz:BAAANQAECgEIAQAAAA==.Drunkdragon:BAAANQADCgcICwAAAA==.',
Ea='Earthtide:BAAANQADCgYICwAAAA==.',
El='Elfsa:BAAANQAECgQICAAAAA==.Ellayria:BAABNQAECn8cAAISAAgKiBL4cADDAQASAAgKiBL4cADDAQAAAA==.Elymaria:BAABNQAECn8WAAIEAAgK1QWPigDgAAAEAAgK1QWPigDgAAAAAA==.',
Em='Emberrose:BAABNQAECn8dAAIIAAcKRAjpJQC2AAAIAAcKRAjpJQC2AAAAAA==.',
En='Enhancedpant:BAABNQAECn8jAAIMAAoKNxrsFQAKAgAMAAoKNxrsFQAKAgAAAA==.Ensetral:BAAANQAECgQIDAAAAA==.',
Ev='Evernight:BAAANQAECgcIDQAAAA==.',
Ez='Ezluckyfree:BAAANQAECggIDQAAAA==.',
Fa='Fakedruid:BAAANQAECgEIAQABNQAECgMIAwAFAAAAAA==.',
Fe='Feledris:BAAANQAECgcICgAAAA==.Felwynne:BAABNQAECn8XAAITAAkKAxHxHgCXAQATAAkKAxHxHgCXAQAAAA==.Ferrah:BAAANQAECgEIAQAAAA==.Feybeasts:BAAANQAECgQIBwAAAA==.Feárbomber:BAABNQAECn8qAAMUAAoKaBjnSQDkAQAUAAkKzRfnSQDkAQAVAAIKIxCxVgB6AAAAAA==.',
Fh='Fhala:BAAANQADCggICAAAAA==.Fharia:BAAANQAECgUIEAAAAA==.',
Fi='Fivo:BAAANQABCgEIAQAAAA==.',
Fl='Flayr:BAAANQADCggIEwAAAA==.',
Fr='Fries:BAEANQAECggICAABNQAECggIDwAFAAAAAA==.',
Fu='Fusky:BAABNQAECn8YAAIDAAgKQReIRQDmAQADAAgKQReIRQDmAQAAAA==.',
Fy='Fynn:BAABNQAECn8yAAIMAAoKMR1zCQDeAgAMAAoKMR1zCQDeAgAAAA==.',
['Fé']='Férn:BAAANQAECgEIAQAAAA==.',
Ga='Galadria:BAACNQAFFH8IAAIGAAQKrAZ0GgB8AAAGAAQKrAZ0GgB8AAA1AAQKf0QAAgYACgq0HskWAEwCAAYACgq0HskWAEwCAAAA.Garamond:BAAANQADCggIDwAAAA==.Garnd:BAAANQAECgQICAAAAA==.Garrish:BAAANQABCgQIBgAAAA==.Gastly:BAAANQADCgEIAwAAAA==.',
Ge='Gerwik:BAAANQAECgUIEAAAAA==.',
Gi='Gimlih:BAAANQADCgEIAQAAAA==.',
Go='Gogetta:BAAANQAECggIEQAAAA==.Govana:BAAANQAECgEIAQAAAA==.',
Gr='Greenleaves:BAAANQAECgIIAgAAAA==.',
Gu='Gummiwormz:BAAANQADCgQIBAAAAA==.',
Gy='Gyat:BAAANQADCgUJBwABNQAECggIJgAHAKwYAA==.',
Ha='Hailin:BAABNQAECn85AAMCAAoKCRl3VgCTAgACAAoKCRl3VgCTAgARAAEKAAAkdgAAAAAAAA==.Haunter:BAABNQAECn8aAAIRAAcK9RYeKwCEAQARAAcK9RYeKwCEAQAAAA==.',
He='Heherawr:BAAANQADCgIIAgABNQADCgMIBgAFAAAAAA==.',
Hi='Highmico:BAAANQAECgMIAwABNQAECgoKLAAPAN8dAA==.Hightroller:BAAANQAECgIIAgAAAA==.Hima:BAAANQAECgcIEQAAAA==.',
Ho='Holyjenkins:BAAANQAECgQIBAAAAA==.Horngrry:BAAANQAECgYIDgAAAA==.',
Hu='Huntingpants:BAAANQAECgQIBAABNQAECgoKIwAMADcaAA==.',
Ic='Icianri:BAAANQAECgIIAgAAAA==.',
Il='Illtrytoheal:BAAANQADCgYICgAAAA==.',
Im='Imkillho:BAAANQAECgQJBAABNQAECgYIDgAFAAAAAA==.',
In='Inosuke:BAAANQADCgQIBAAAAA==.Inspiredbox:BAAANQAECggICwAAAA==.',
Is='Issyo:BAAANQAECggIBQAAAA==.',
Ja='Jankismith:BAABNQAECn8oAAIWAAgKEQwUGQBYAQAWAAgKEQwUGQBYAQAAAA==.Jayy:BAABNQAECn8aAAIXAAYKCQ21CQArAQAXAAYKCQ21CQArAQAAAA==.',
Jf='Jflyer:BAAANQADCgIIAgABNQAFFAQICwAEADgSAA==.',
Ji='Jimin:BAABNQAECn8VAAIDAAcKugozmQBIAQADAAcKugozmQBIAQAAAA==.Jitoflight:BAAANQADCgEIAQAAAA==.',
Jm='Jmajk:BAAANQABCgcICAAAAA==.',
Ju='Jugger:BAAANQADCgcICgAAAA==.',
Ka='Kachiko:BAAANQADCgYICQAAAA==.Kaethis:BAAANQABCgUJBQAAAA==.Kaia:BAAANQAECgYIDAAAAA==.Kamchan:BAAANQAECgQIBQAAAA==.Kamerth:BAABNQAECn8gAAQYAAYKNw8CNgDOAAAYAAUKmwoCNgDOAAAPAAUKuwInzwC3AAAZAAIKAgjxIQBWAAAAAA==.Kapbam:BAAANQADCggICgAAAA==.Karluron:BAABNQAECn8aAAIYAAkK7hBhGwClAQAYAAkK7hBhGwClAQAAAA==.Karlutros:BAABNQAECn8tAAIYAAoKyBMHFQD4AQAYAAoKyBMHFQD4AQAAAA==.Katbaka:BAAANQADCggIDAABNQAFFAYIFQAaAD8hAA==.Katmoreahh:BAAANQADCgcIBwABNQAFFAYIFQAaAD8hAA==.Katuwuagain:BAACNQAFFH8VAAIaAAYKPyGQCwCcAQAaAAYKPyGQCwCcAQA1AAQKf0IAAhoACQr8JSsCAGUDABoACQr8JSsCAGUDAAAA.Kayonalani:BAAANQAECgEIAQAAAA==.Kazure:BAABNQAECn8yAAIbAAoKCQ4JEQDaAQAbAAoKCQ4JEQDaAQAAAA==.',
Ke='Kelilia:BAABNQAECn88AAIJAAoK8hAmcgA+AgAJAAoK8hAmcgA+AgAAAA==.Keniilar:BAAANQADCgEIAgAAAA==.Kenilar:BAAANQAECgUIEQAAAA==.Keybricker:BAAANQADCgMIAwABNQAECgMIAwAFAAAAAA==.',
Ko='Konga:BAABNQAECn8dAAIMAAYKzBPvHwANAQAMAAYKzBPvHwANAQAAAA==.Korngry:BAAANQADCgUIBgABNQAECgYIDgAFAAAAAA==.',
Kr='Krakkin:BAAANQAECgQIAQAAAA==.Krenil:BAAANQAECgIIAwAAAA==.',
Ku='Kuassei:BAABNQAECn8iAAIOAAkK4B6QFgBNAgAOAAkK4B6QFgBNAgAAAA==.',
Ky='Kyatto:BAAANQAECgcIDwABNQAFFAYIFQAaAD8hAA==.Kyllea:BAAANQAECgcIDwAAAA==.',
La='Laaksy:BAAANQAECgUIBwABNQAECgkJHwASAG4aAA==.Ladraina:BAAANQADCggICgAAAA==.Landock:BAAANQAECgIIAgAAAA==.Lanien:BAAANQADCgUIBQAAAA==.Lantasia:BAAANQADCgIIAgAAAA==.Larynnoelle:BAABNQAECn8dAAIcAAkKPwz1fwCaAQAcAAkKPwz1fwCaAQAAAA==.',
Le='Lebronjames:BAABNQAECn8XAAMdAAoKCBDCTACzAQAdAAgKKhHCTACzAQAeAAQK2AW2PgCLAAABNQAFFAUIEQANALQZAA==.Leotart:BAABNQAECn88AAIOAAoKxRVvFQBfAgAOAAoKxRVvFQBfAgAAAA==.Lesbians:BAAANQAECgUICwAAAA==.Leyland:BAAANQADCgcIGwAAAA==.',
Li='Lilsus:BAAANQADCggICAABNQAECgQIBAAFAAAAAA==.Linaraline:BAAANQADCgUIBgAAAA==.Linni:BAABNQAECn8kAAIOAAkK2Qi1PQA2AQAOAAkK2Qi1PQA2AQAAAA==.Lizawizah:BAAANQAECgQIBAAAAA==.',
Lo='Lortnok:BAAANQAECgIIAwABNQAECgcIDQAFAAAAAA==.Lotharlock:BAAANQADCgQIBAAAAA==.Lotharpally:BAAANQAECgUIBwAAAA==.Lotharshammy:BAAANQAECgcIDQAAAA==.',
Lu='Lukadoncic:BAACNQAFFH8RAAMNAAUKtBlKBwBNAQANAAUKtBlKBwBNAQAaAAIKCxdGIACHAAA1AAQKf0QABA0ACgpYIOcWAIUCAA0ACgpYIOcWAIUCAAcABgpbGBl0AEcBABoAAwqcGCqKANcAAAAA.Luminescent:BAAANQADCgMIAwAAAA==.Lunila:BAAANQADCgEIAQABNQAECgQIAwAFAAAAAA==.',
['Lö']='Lögäñ:BAABNQAECn8jAAMRAAoKlxMeGACgAQARAAoKlxMeGACgAQACAAQKiwXhdwFkAAAAAA==.',
Ma='Maeby:BAAANQAECgUIBQABNQAECgkJIgAPAOwaAA==.Magepants:BAAANQAECgMIAwABNQAECgoKIwAMADcaAA==.Magnessa:BAAANQAECgYICwAAAA==.Malekai:BAAANQADCgYICQAAAA==.Malovious:BAAANQADCggIHwAAAA==.Mano:BAABNQAECn8VAAIGAAkKOwnQOAA6AQAGAAkKOwnQOAA6AQAAAA==.Marist:BAABNQAECn8ZAAIEAAoKhAvgewCvAQAEAAoKhAvgewCvAQAAAA==.Marshabrady:BAAANQADCgEIAgAAAA==.Marwowi:BAAANQADCgIIAgAAAA==.',
Me='Memelord:BAAANQADCgQIBAAAAA==.Menadare:BAAANQAECgUICQAAAA==.Metaslave:BAAANQAECgUICgABNQAECgoKOAACAB0iAA==.Meteion:BAAANQAECgEIAQAAAA==.',
Mi='Mianceden:BAABNQAECn8iAAIfAAcK8Bd/GgAaAQAfAAcK8Bd/GgAaAQAAAA==.Miansbane:BAAANQAECgQIBwAAAA==.Micahscream:BAAANQAECgIIAgAAAA==.Midheaven:BAAANQAECgcIEAAAAA==.Miku:BAAANQADCgcIDwABNQAECgoKOQACAAkZAA==.Milent:BAAANQAECgYIDQAAAA==.Mimix:BAAANQADCggIDwAAAA==.Miquiztli:BAAANQAECggIBAAAAA==.Mizoci:BAAANQAECgUIBgAAAA==.',
Mo='Mongoose:BAABNQAECn8fAAISAAkKbhqZJAAEAwASAAkKbhqZJAAEAwAAAA==.Monkeyk:BAAANQADCggIDAAAAA==.',
Ms='Msspelled:BAABNQAECn8YAAMgAAcKuhAVGwCqAAAUAAcKYxAusQBuAQAgAAUKzREVGwCqAAAAAA==.',
Mu='Muichiro:BAAANQADCgQIBQAAAA==.Murcielago:BAAANQAECgIIAgAAAA==.',
Mv='Mvpiam:BAAANQAECgYIBwAAAA==.Mvpsevoker:BAAANQADCgcICQAAAA==.Mvpspally:BAAANQADCgEIAQAAAA==.',
Mx='Mximus:BAAANQADCgMIAwABNQAECgYIDAAFAAAAAA==.',
My='Mystí:BAABNQAECn8cAAIKAAoK8BnggQB7AgAKAAoK8BnggQB7AgAAAA==.',
['Má']='Májorpáin:BAAANQAECgYICgABNQAECgoKKgAUAGgYAA==.',
Na='Nabstarr:BAABNQAECn8wAAIPAAoKcB0ZEgA4AwAPAAoKcB0ZEgA4AwAAAA==.Namaiki:BAAANQADCgUICQAAAA==.Nasroth:BAAANQAECgYIDQAAAA==.Nasstina:BAAANQAECgEIAQABNQAECggICgAFAAAAAA==.Natureterror:BAAANQADCggIFQAAAA==.Naví:BAAANQADCgIIAgAAAA==.',
Ni='Nicefella:BAAANQAECgEIAQAAAA==.Niibyter:BAABNQAECn8YAAIfAAYKsxwRFgBJAQAfAAYKsxwRFgBJAQAAAA==.Nitrolan:BAAANQADCgUIBQAAAA==.',
No='Nodiddles:BAAANQADCgYIBgAAAA==.Nofers:BAAANQADCgEIAQAAAA==.',
Ob='Oberon:BAAANQABCgMIAwAAAA==.',
Oc='Oceanbreeze:BAAANQADCggICAAAAA==.',
Oj='Ojasam:BAAANQAECgMIAQAAAA==.',
On='Onlylocks:BAAANQAECgYIDAAAAA==.',
Or='Oralia:BAAANQADCgQIBAAAAA==.Orasha:BAAANQADCgIIAgAAAA==.Orlisman:BAABNQAECn8XAAMDAAoKMRalOgB0AgADAAoKMRalOgB0AgAEAAEKXgIrAAEoAAAAAA==.',
Pa='Palobo:BAAANQABCgQIBAAAAA==.Pandamunx:BAAANQADCgEJAQAAAA==.',
Pe='Peludin:BAAANQADCgQIBAAAAA==.',
Ph='Phaka:BAABNQAECn8mAAIHAAgKrBhATADkAQAHAAgKrBhATADkAQAAAA==.Phelanx:BAAANQAECgMIAgAAAA==.Philanthropy:BAABNQAECn8sAAMbAAgK2h+hDADbAgAbAAgK2h+hDADbAgAQAAEKRw5lIgA/AAAAAA==.Philsoom:BAAANQAECgYIBQAAAA==.',
Pi='Pizzeroloko:BAABNQAECn8sAAIIAAoKChzaBgD7AgAIAAoKChzaBgD7AgAAAA==.',
Pl='Placebo:BAABNQAECn8iAAIPAAkK7BqZKwC6AgAPAAkK7BqZKwC6AgAAAA==.Playforever:BAAANQADCgQIBwAAAA==.Pläze:BAAANQAECgIIAgAAAA==.',
Pr='Prahd:BAAANQAECgcIEgAAAA==.',
Pu='Purrsephonie:BAABNQAECn8nAAISAAgK/gRouwAgAQASAAgK/gRouwAgAQAAAA==.',
Pw='Pweist:BAAANQADCggIFwABNQAECgMIAwAFAAAAAA==.',
Py='Pyronorish:BAAANQAECgQIBgAAAA==.Pytthia:BAABNQAECn8cAAMYAAcK8Q2yMwCFAQAYAAcK8Q2yMwCFAQAZAAUKLg0+EgADAQAAAA==.',
Ra='Raptalia:BAAANQAECgEIAQABNQAECgoKOQACAAkZAA==.Rayquaza:BAAANQADCgIIAgABNQAFFAgIHQAOAMMTAA==.Raziel:BAAANQAECgMIBQAAAA==.',
Re='Redpepperz:BAAANQABCgIIBAAAAA==.Reldruin:BAAANQADCgUICAAAAA==.Rexi:BAAANQADCgQICwAAAA==.',
Rh='Rhaena:BAAANQAECgIIAgAAAA==.Rhombus:BAABNQAECn8aAAIcAAYKagyRhgAQAQAcAAYKagyRhgAQAQAAAA==.',
Ri='Rickjamesbia:BAAANQAECgEIAQAAAA==.Riorson:BAABNQAECn8gAAIaAAoKgQ//SwDGAQAaAAoKgQ//SwDGAQAAAA==.Rizhir:BAAANQADCgUIFgAAAA==.',
Ro='Ronkey:BAAANQAECgIIAgAAAA==.Ronkzar:BAAANQADCgUICAAAAA==.',
['Rô']='Rôflstômp:BAAANQAECgYIBwAAAA==.',
Sa='Sacklord:BAAANQADCggICAAAAA==.Sakai:BAAANQADCggICAAAAA==.Salanis:BAAANQAECgIIAgABNQAECgoKJgAcAAwkAA==.Saltydog:BAAANQADCgQIGwAAAA==.Sammy:BAAANQABCgUIBQAAAA==.',
Sc='Scurge:BAAANQAECgYIDAAAAA==.',
Se='Sebasmatute:BAAANQAECgcIBwAAAA==.Seizo:BAAANQAECgQIBwAAAA==.Serazen:BAABNQAECn8ZAAMhAAkKJQquEgAHAQAhAAgKhQquEgAHAQAQAAUKAgU/GQCaAAAAAA==.Setal:BAAANQAECgIIAgAAAA==.',
Sh='Shallteàr:BAAANQAECgQICwAAAA==.Shammysathh:BAAANQAECgIIAgAAAA==.Shamurloc:BAAANQADCgEIAQAAAA==.Sheenatonic:BAAANQADCgYIDAABNQAECgkJHQAcAD8MAA==.Sheenzilla:BAAANQADCgYIDAABNQAECgkJHQAcAD8MAA==.Shiftr:BAABNQAECn8YAAIGAAoKZxY0GQAwAgAGAAoKZxY0GQAwAgAAAA==.Shockaholix:BAAANQADCgUIBQABNQAECgYIDAAFAAAAAA==.Shoinked:BAAANQAECgUIDQAAAA==.Shoveldin:BAAANQAECgQIBAAAAA==.',
Si='Sices:BAAANQADCgQIBAAAAA==.Silentpaw:BAABNQAECn8yAAMiAAgKKyFcBQA3AgAiAAgKKyFcBQA3AgALAAMKcBU0QgCRAAABNQAECgoKKgAUAGgYAA==.',
Sl='Slamarama:BAAANQADCgIIAwAAAA==.',
Sm='Smallblades:BAAANQADCgUIBQAAAA==.Smallêntropy:BAABNQAECn8ZAAIBAAgKKhHpEgAGAQABAAgKKhHpEgAGAQAAAA==.Smelt:BAAANQADCgYICAAAAA==.Smuurfdk:BAEANQADCggICAABNQAECgcIDwAFAAAAAA==.Smuurfhands:BAEANQAECgcIDwAAAA==.',
So='Sogekin:BAAANQADCgIIAwAAAA==.Soulbringer:BAAANQAECggIDQAAAA==.',
Sp='Spriggy:BAAANQAECgcIEgAAAA==.',
St='Stabbytrout:BAABNQAECn8fAAIeAAkKKCNICABSAwAeAAkKKCNICABSAwAAAA==.Stabyotoe:BAAANQADCggIDQAAAA==.',
Su='Sugar:BAAANQADCggICAAAAA==.Sunetra:BAABNQAECn8eAAICAAoKmQtgoAB3AQACAAoKmQtgoAB3AQAAAA==.Sushi:BAAANQADCgcIDwAAAA==.',
['Sà']='Sàlanis:BAAANQADCgMIAwABNQAECgoKJgAcAAwkAA==.',
['Sã']='Sãlanis:BAAANQAECgQICAABNQAECgoKJgAcAAwkAA==.',
['Sä']='Sälanis:BAABNQAECn8mAAMcAAoKDCQrBADWAwAcAAoKDCQrBADWAwACAAEKAADFuQErAAAAAA==.Säpättäck:BAAANQAECgYIBgAAAA==.',
Ta='Taal:BAAANQADCgQIBAABNQAECgoKMgAMADEdAA==.Taehyung:BAAANQAECgcIEQAAAA==.Taintcleaver:BAAANQAECgIIAwAAAA==.Tainthel:BAAANQADCgUIBQAAAA==.Tairyn:BAABNQAECn9DAAMJAAoKpiKeIAA1AwAJAAoK1iGeIAA1AwAfAAkKKxvKCgAFAgAAAA==.Taloki:BAAANQAECgQIDAAAAA==.Tatsuhisa:BAAANQADCgYIEAAAAA==.',
Te='Telavore:BAAANQADCgUIBQAAAA==.Telle:BAAANQAECgYIBwAAAA==.Terciodk:BAAANQAECgcIBgAAAA==.Terregoat:BAAANQADCgUIBQAAAA==.',
Th='Thrallmarr:BAAANQADCgIIAgAAAA==.Thruder:BAAANQADCgQIBgAAAA==.',
Ti='Titfortat:BAAANQAECgEIAQAAAA==.',
To='Tomaktoma:BAAANQADCgUIBwAAAA==.Tophdh:BAAANQAECgUIBQAAAA==.Totemicblank:BAAANQAECgIIAgAAAA==.',
Tr='Traydle:BAAANQAECggIDAAAAA==.Trondur:BAABNQAECn8aAAIJAAkKLx8JUACZAgAJAAkKLx8JUACZAgAAAA==.Trydel:BAAANQADCgcIEQABNQAECggIDAAFAAAAAA==.Trygon:BAAANQADCgYIBgABNQAECggIDAAFAAAAAA==.',
Tu='Tuffnnice:BAAANQABCgcICgAAAA==.Tuini:BAAANQADCgcIFQAAAA==.',
['Tá']='Tálonstorm:BAABNQAECn8tAAIJAAgKtQMJ0QC+AAAJAAgKtQMJ0QC+AAAAAA==.',
Ul='Ultra:BAAANQABCgIIAgAAAA==.',
Va='Valynaria:BAAANQAECgMICAAAAA==.Vani:BAAANQAECgYIEwAAAA==.',
Ve='Vendetta:BAAANQAECgYIBQABNQAECgYIDAAFAAAAAA==.',
Vi='Victim:BAAANQABCgIIAgAAAA==.Vilthrax:BAAANQAECgIIAwAAAA==.',
Vu='Vulcanus:BAAANQAECgEIAQAAAA==.',
['Vè']='Vèngeance:BAAANQAECgUIBQAAAA==.',
Wa='Warchiéf:BAAANQAECgYIEgAAAA==.Warent:BAAANQABCgIIAgAAAA==.',
Wh='Whalaski:BAACNQAFFH8FAAISAAIKpgd5IQCQAAASAAIKpgd5IQCQAAA1AAQKf0IAAhIACgozG8A8AE0CABIACgozG8A8AE0CAAAA.Whistledown:BAAANQADCggICgAAAA==.',
Wi='Wickedsin:BAAANQAECgQIBAAAAA==.Wickedstorm:BAAANQADCggIFAAAAA==.Wingstop:BAAANQAECgEIAgABNQAECggIGgAGACAHAA==.',
Wo='Woggieboggie:BAAANQAECggIAgAAAA==.',
Wr='Wreckitman:BAACNQAFFH8JAAMOAAQKtwY+DgCjAAAOAAQKtwY+DgCjAAAGAAIK5wCCIwAqAAA1AAQKfykAAw4ACQp3GjwSAL4CAA4ACQp3GjwSAL4CAAYABwrUBNBmADEBAAAA.',
Xa='Xaalath:BAABNQAECn8nAAMjAAgKSgz9EwA3AQAjAAgKSgz9EwA3AQAKAAEKAACL5AEhAAAAAA==.',
['Xé']='Xéno:BAABNQAECn8rAAIbAAkKJxFfIADQAQAbAAkKJxFfIADQAQAAAA==.',
Yo='Yobaz:BAAANQAECgQIBAAAAA==.Yohanan:BAAANQABCgYICwAAAA==.Yozomi:BAAANQAECgQIBAAAAA==.',
Za='Zappya:BAAANQADCgEIAgAAAA==.Zarinah:BAAANQADCgcIBwABNQAECggIGgAGACAHAA==.Zarorisk:BAAANQAECgUIBgABNQAFFAYICgAIAKEQAA==.',
Ze='Zedd:BAABNQAECn8iAAIOAAoKjA4gNQByAQAOAAoKjA4gNQByAQABNQADCgcIFQAFAAAAAA==.Zewse:BAAANQAECgUIBgAAAA==.',
['ße']='ßez:BAAANQADCgIIAgAAAA==.',
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
