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

local lookup = {'DemonHunter-Vengeance','Paladin-Retribution','Shaman-Restoration','Shaman-Elemental','Druid-Balance','Unknown-Unknown','DeathKnight-Unholy','Druid-Feral','Warrior-Arms','Mage-Arcane','Monk-Windwalker','DeathKnight-Frost','Druid-Restoration','Priest-Holy','Evoker-Devastation','Paladin-Protection','Hunter-BeastMastery','Shaman-Enhancement','DemonHunter-Devourer','Warlock-Demonology','Warlock-Destruction','Monk-Mistweaver','Hunter-Survival','Priest-Shadow','Priest-Discipline','DeathKnight-Blood','Evoker-Preservation','Paladin-Holy','Warrior-Protection','Warlock-Affliction','Evoker-Augmentation','Monk-Brewmaster','Rogue-Assassination','Mage-Frost',}
local provider = {region='US',realm='Korialstrasz',name='US',type='weekly',zone=53,date='2026-11-03',data={Ac='Accursed:BAACNQAFFH8LAAIBAAQKPB+sAQDbAAABAAQKPB+sAQDbAAA1AAQKfy4AAgEACQoxJPEBAHkDAAEACQoxJPEBAHkDAAAA.Activesloth:BAAANQADCgQJBAABNQAECgoKOAACAB0iAA==.',
Ad='Adekeai:BAABNQAECn8dAAMDAAkK/w6/dwAYAQADAAcKJgu/dwAYAQAEAAMK9AEW3gA4AAAAAA==.Adol:BAAANQADCgYIBgAAAA==.',
Ae='Aelys:BAAANQAECgQIBQAAAA==.',
Al='Aleighta:BAABNQAECn8gAAIDAAoK9w8LNwANAgADAAoK9w8LNwANAgAAAA==.Alenara:BAAANQADCgMJAwAAAA==.Allblond:BAAANQADCgYIBgAAAA==.Alyx:BAAANQAECgEIAQAAAA==.',
Am='Amouri:BAAANQADCgEIAgAAAA==.',
An='Anacreon:BAAANQAECgcICQAAAA==.Anaiah:BAAANQADCggIDgABNQAECgcIIQAFANQDAA==.',
Ar='Arcey:BAAANQADCgIIAgAAAA==.Arun:BAAANQADCgQIBQABNQAECgcIEAAGAAAAAA==.',
As='Asmodius:BAAANQADCgMIAwAAAA==.Aspros:BAABNQAECn8WAAIHAAoKFQ4HTwDYAQAHAAoKFQ4HTwDYAQAAAA==.',
At='Atlantis:BAAANQAECgUICgAAAA==.Atonement:BAABNQAECn8jAAICAAoKphQiXwDbAQACAAoKphQiXwDbAQAAAA==.',
Av='Avengence:BAAANQADCgIIAgAAAA==.',
Ay='Ayshan:BAAANQAECgMICAABNQAECgQIBQAGAAAAAA==.',
Ba='Badoussi:BAAANQAECgQICAABNQAFFAYICgAIAKEQAA==.Baja:BAAANQAECggIDQAAAA==.Bakugo:BAAANQADCgMIAwAAAA==.Bananas:BAAANQAECgEIAQAAAA==.',
Be='Beansy:BAAANQADCgUICwAAAA==.Beefomancer:BAAANQAECgMIAwAAAA==.Belladin:BAABNQAECn8lAAICAAoKChbUcQBMAgACAAoKChbUcQBMAgAAAA==.Belzugaim:BAABNQAECn8UAAIJAAgKVgsFpwC7AQAJAAgKVgsFpwC7AQABNQADCgQICQAGAAAAAA==.Bertheigh:BAAANQADCgEIAgAAAA==.',
Bi='Bingcrosby:BAAANQAECgEIAQAAAA==.Bipolarcurys:BAAANQAECgUIEAAAAA==.Bismuth:BAAANQAECgcIEAAAAA==.',
Bl='Blamethedps:BAAANQAECgQIBgABNQAECgoKHgAKAEEZAA==.Blameyomomma:BAAANQAECgYICgABNQAECgoKHgAKAEEZAA==.Blamezuko:BAABNQAECn8eAAIKAAoKQRnLOgA6AgAKAAoKQRnLOgA6AgAAAA==.Blite:BAAANQADCgcIGgAAAA==.Blumoon:BAAANQADCgcIBwAAAA==.',
Bo='Bombakaap:BAACNQAFFH8LAAILAAQKnw9pCADMAAALAAQKnw9pCADMAAA1AAQKfy0AAgsACgpXH9QLAHkCAAsACgpXH9QLAHkCAAAA.Bomburst:BAAANQAECgYIEwAAAA==.Bonelespizza:BAACNQAFFH8JAAIMAAIKex5cFACbAAAMAAIKex5cFACbAAA1AAQKf0IAAgwACgr5IywIABEDAAwACgr5IywIABEDAAAA.Bonkthump:BAAANQAECgEIAwAAAA==.Boogiebabe:BAABNQAECn88AAMNAAoKtBVkEgBZAgANAAoKtBVkEgBZAgAFAAQKOwdohQC8AAAAAA==.Bornix:BAAANQAECgMIAwABNQAECgoKNQAKAFkUAA==.',
Br='Briaris:BAAANQAECgcIEAABNQAECgoKLAAIAAocAA==.Brosar:BAAANQAECgEIAQAAAA==.Brugaras:BAAANQAECgEIAQAAAA==.',
['Bê']='Bêz:BAAANQAECgMIBQAAAA==.',
['Bë']='Bëz:BAABNQAECn8hAAIBAAcK2B8kCwAgAgABAAcK2B8kCwAgAgAAAA==.',
Ca='Cadzan:BAAANQADCgEIAQAAAA==.Caith:BAAANQADCgEIAQAAAA==.Calabretta:BAAANQADCgcIGQAAAA==.Cannan:BAAANQADCgYIBgAAAA==.Captcow:BAAANQADCgEIAwAAAA==.Caver:BAAANQADCgcIDQAAAA==.',
Ch='Charysmaa:BAAANQADCggIHQAAAA==.Cheoekar:BAAANQAECgUIBwABNQAFFAUIDwAOAOYbAA==.',
Ci='Cink:BAAANQAECggICAAAAA==.',
Co='Cobey:BAABNQAECn8uAAICAAoKoBhqeACdAQACAAoKoBhqeACdAQAAAA==.Coldrick:BAAANQAECgMIBgABNQAECgYIDQAGAAAAAA==.Cosmicjay:BAACNQAFFH8LAAIEAAQKOBJgDgDfAAAEAAQKOBJgDgDfAAA1AAQKfyIAAgQACQrDIHssAMwCAAQACQrDIHssAMwCAAAA.Cosmicnova:BAABNQAECn8cAAIMAAkKqRTpLgCzAQAMAAkKqRTpLgCzAQABNQAFFAQICwAEADgSAA==.',
Cr='Crumpet:BAAANQAECggIAgAAAA==.',
Cu='Cursedknight:BAAANQADCgYIEgAAAA==.',
Da='Daegán:BAAANQADCgMIBAAAAA==.Daffodil:BAABNQAECn8YAAIPAAYK4gisEgDcAAAPAAYK4gisEgDcAAAAAA==.Dalaney:BAAANQADCgcIBwAAAA==.Dalavian:BAAANQADCgEIAQAAAA==.Dannyhurt:BAAANQADCgcIEAAAAA==.Dantruis:BAACNQAFFH8UAAIHAAYK6hr+AQBoAQAHAAYK6hr+AQBoAQA1AAQKfzYAAwcACgrTIUcGAPsCAAcACgrTIUcGAPsCAAwAAQroElCXAD8AAAAA.Darlins:BAAANQADCgcICAAAAA==.',
Di='Dianah:BAAANQADCgUICgAAAA==.Diggy:BAAANQADCgcIDgAAAA==.Dinsfirë:BAAANQADCgQIBAAAAA==.Diothorn:BAABNQAECn8mAAMCAAkKHwzhmgBWAQACAAkKAgvhmgBWAQAQAAMKaA80VgCIAAAAAA==.Divanas:BAAANQAECgYIDwAAAA==.Divi:BAABNQAECn8XAAIOAAcKNh9SOgAaAgAOAAcKNh9SOgAaAgAAAA==.Divinium:BAAANQADCgQIBAABNQAECgcIFwAOADYfAA==.Dixiefly:BAAANQADCgEIAgAAAA==.',
Do='Dogfacethug:BAAANQAECgEIAgAAAA==.Dorianna:BAABNQAECn8WAAIFAAgKGQf7PAAFAQAFAAgKGQf7PAAFAQAAAA==.',
Dr='Dreamit:BAAANQADCgMIAwAAAA==.Drease:BAAANQAECgQIBAAAAA==.Drpepperz:BAAANQAECgEIBAAAAA==.Drunkdragon:BAAANQADCgcIDAAAAA==.',
Ea='Earthtide:BAAANQADCgYICwAAAA==.',
El='Elaana:BAAANQAECgIIAgAAAA==.Elfsa:BAAANQAECgQICAAAAA==.Ellayria:BAABNQAECn8aAAIRAAgKiBJrYwC3AQARAAgKiBJrYwC3AQAAAA==.Elymaria:BAABNQAECn8UAAIEAAcKjgVhjgC2AAAEAAcKjgVhjgC2AAAAAA==.',
Em='Emberrose:BAABNQAECn8cAAIIAAcKjQcIIgCsAAAIAAcKjQcIIgCsAAAAAA==.',
En='Enhancedpant:BAABNQAECn8gAAISAAkK3BbsFQAKAgASAAkK3BbsFQAKAgAAAA==.Ensetral:BAAANQAECgQIDAAAAA==.',
Ev='Evernight:BAAANQAECgcIDQAAAA==.',
Ex='Exiledmyst:BAAANQADCgEIAQAAAA==.',
Ez='Ezluckyfree:BAAANQAECgUIBgAAAA==.',
Fa='Fakedruid:BAAANQAECgEIAQABNQAECgMIAwAGAAAAAA==.',
Fe='Feerahion:BAAANQAECgEIAQAAAA==.Feledris:BAAANQAECgcICwAAAA==.Felwynne:BAABNQAECn8UAAITAAgKdRA8IgBVAQATAAgKdRA8IgBVAQAAAA==.Ferrah:BAAANQAECgEIAQAAAA==.Feybeasts:BAAANQAECgQIBwAAAA==.Feárbomber:BAABNQAECn8qAAMUAAoKaBixPQDrAQAUAAkKzRexPQDrAQAVAAIKIxCxVgB6AAAAAA==.',
Ff='Ffand:BAAANQAECgEIAQAAAA==.',
Fh='Fhala:BAAANQADCggICAAAAA==.Fharia:BAAANQAECgUIEQAAAA==.',
Fi='Fivo:BAAANQADCgEIAQAAAA==.',
Fl='Flayr:BAAANQADCggIEgAAAA==.',
Fr='Fries:BAEANQAECggICAABNQAECggIDwAGAAAAAA==.',
Fu='Fusky:BAABNQAECn8XAAIDAAcKnxeaSgC2AQADAAcKnxeaSgC2AQAAAA==.',
Fy='Fynn:BAABNQAECn8vAAISAAoKMR1zCQDeAgASAAoKMR1zCQDeAgAAAA==.',
['Fä']='Fätpàndà:BAAANQAECgIIAgAAAA==.',
['Fé']='Férn:BAAANQAECgEIAQAAAA==.',
Ga='Galadria:BAACNQAFFH8HAAIFAAQKrAbnFgB9AAAFAAQKrAbnFgB9AAA1AAQKfz8AAgUACgoTHl0dAN4CAAUACgoTHl0dAN4CAAAA.Garamond:BAAANQADCggIDwAAAA==.Garillip:BAAANQADCgEIAQAAAA==.Garnd:BAAANQAECgQIBAAAAA==.Garrish:BAAANQADCgEIAQAAAA==.Gastly:BAAANQADCgEIAQAAAA==.',
Ge='Gerwik:BAAANQAECgUIEAAAAA==.',
Gi='Gimlih:BAAANQADCgEIAQAAAA==.',
Go='Gogetta:BAABNQAECn8WAAMDAAoKYBa5RQDKAQADAAgKlhO5RQDKAQAEAAgKlxCwkQB4AQAAAA==.Goldenlock:BAAANQAECgEIAgAAAA==.Govana:BAAANQAECgEIAQAAAA==.',
Gr='Greenleaves:BAAANQAECgIIAgAAAA==.',
Gu='Gummiwormz:BAAANQADCgQIBAAAAA==.',
Gy='Gyat:BAAANQADCgUJCAABNQAECggIJgAHAKwYAA==.',
Ha='Hailin:BAABNQAECn82AAMCAAoKrhh3VgCTAgACAAoKrhh3VgCTAgAQAAEKAADCbAAAAAAAAA==.Haldaer:BAAANQADCgEIAgAAAA==.Haunter:BAABNQAECn8UAAIQAAYKIBseKwCEAQAQAAYKIBseKwCEAQAAAA==.Havocskiss:BAAANQADCgEIAQAAAA==.',
He='Heherawr:BAAANQADCgIIAgABNQADCgMIBgAGAAAAAA==.',
Hi='Highmico:BAAANQAECgMIAwABNQAECgoKLAAOAN8dAA==.Hima:BAAANQAECgcIEAAAAA==.',
Ho='Hofmann:BAAANQADCgEIAQAAAA==.Holyjenkins:BAAANQAECgQIBAAAAA==.Homulily:BAAANQADCgEIAQAAAA==.Horngrry:BAAANQAECgYIDgAAAA==.',
Hu='Huntingpants:BAAANQAECgQIBAABNQAECgkJIAASANwWAA==.',
Ic='Icianri:BAAANQAECgIIAgAAAA==.',
Il='Illtrytoheal:BAAANQADCgYICgAAAA==.',
Im='Imabear:BAAANQADCgEIAQAAAA==.Imkillho:BAAANQAECgQJBAABNQAECgYIDgAGAAAAAA==.',
In='Inosuke:BAAANQADCgQIBAAAAA==.Inspiredbox:BAAANQAECgYIBwAAAA==.',
Is='Issyo:BAAANQAECggIBgAAAA==.',
Ja='Jankismith:BAABNQAECn8iAAIWAAcKDAxxGgAlAQAWAAcKDAxxGgAlAQAAAA==.Jayy:BAABNQAECn8aAAIXAAYKCQ1KCAA2AQAXAAYKCQ1KCAA2AQAAAA==.',
Jf='Jflyer:BAAANQADCgIIAgABNQAFFAQICwAEADgSAA==.',
Ji='Jimin:BAABNQAECn8VAAIDAAcKugozmQBIAQADAAcKugozmQBIAQAAAA==.Jitoflight:BAAANQADCgEIAQAAAA==.',
Jm='Jmajk:BAAANQADCgEIAgAAAA==.',
Ju='Jugger:BAAANQADCgcICQAAAA==.Jumbo:BAAANQADCgEIAQAAAA==.',
Ka='Kachiko:BAAANQADCgYICQAAAA==.Kaethis:BAAANQADCgEIAgAAAA==.Kaia:BAAANQAECgcIDAAAAA==.Kamchan:BAAANQAECgQIBQABNQAFFAYIDAAOACMJAA==.Kamerth:BAABNQAECn8gAAQYAAYKNw89MADPAAAYAAUKmwo9MADPAAAOAAUKuwInzwC3AAAZAAIKAgjxIQBWAAAAAA==.Kapbam:BAAANQADCggICgAAAA==.Karluron:BAABNQAECn8ZAAIYAAgKNxCrHQBkAQAYAAgKNxCrHQBkAQAAAA==.Karlutros:BAABNQAECn8nAAIYAAoKyBP3EgDzAQAYAAoKyBP3EgDzAQAAAA==.Katbaka:BAAANQADCggIDQABNQAFFAYIFQAaAD8hAA==.Katmoreahh:BAAANQADCgcIBwABNQAFFAYIFQAaAD8hAA==.Katuwuagain:BAACNQAFFH8VAAIaAAYKPyGmBwBRAQAaAAYKPyGmBwBRAQA1AAQKf0AAAhoACQrqJTICAGEDABoACQrqJTICAGEDAAAA.Kayonalani:BAAANQAECgEIAQAAAA==.Kazure:BAABNQAECn8yAAIbAAoKCQ78DgDdAQAbAAoKCQ78DgDdAQAAAA==.',
Ke='Kelilia:BAABNQAECn81AAIJAAoK8hAmcgA+AgAJAAoK8hAmcgA+AgAAAA==.Kenilar:BAAANQAECgUIDgAAAA==.Keybricker:BAAANQADCgMIAwABNQAECgMIAwAGAAAAAA==.',
Ko='Konga:BAABNQAECn8YAAISAAYKzBPSHAANAQASAAYKzBPSHAANAQAAAA==.Korngry:BAAANQADCgUIBgABNQAECgYIDgAGAAAAAA==.',
Kr='Krakkin:BAAANQAECgEIAQAAAA==.Krenil:BAAANQAECgIIAgAAAA==.',
Ku='Kuassei:BAABNQAECn8iAAINAAkK4B7mEgBRAgANAAkK4B7mEgBRAgAAAA==.',
Ky='Kyatto:BAAANQAECgcIDwABNQAFFAYIFQAaAD8hAA==.Kyllea:BAAANQAECgcIDgAAAA==.',
La='Laaksy:BAAANQAECgUIBwABNQAECgkJHwARAG4aAA==.Ladraina:BAAANQADCggICQAAAA==.Landock:BAAANQADCgYIIQAAAA==.Lanien:BAAANQADCgUIBQAAAA==.Lantasia:BAAANQABCgMIAwAAAA==.Larynnoelle:BAABNQAECn8dAAIcAAkKPwz1fwCaAQAcAAkKPwz1fwCaAQAAAA==.',
Le='Lebronjames:BAAANQAECggIEgABNQAFFAQIEAAMALIaAA==.Leotart:BAABNQAECn84AAINAAoKAxQ5FAA+AgANAAoKAxQ5FAA+AgAAAA==.Lesbians:BAAANQAECgUICwAAAA==.Leyland:BAAANQADCgcIHgAAAA==.',
Li='Lilsus:BAAANQADCggICAABNQAECgQIBAAGAAAAAA==.Linaraline:BAAANQADCgUIBQAAAA==.Linni:BAABNQAECn8iAAINAAgK4wm1PQA2AQANAAgK4wm1PQA2AQAAAA==.Lizawizah:BAAANQAECgQIBAAAAA==.',
Lo='Lortnok:BAAANQAECgIIAwABNQAECgYIBgAGAAAAAA==.Lotharlock:BAAANQADCgQIBAAAAA==.Lotharpally:BAAANQAECgUIBwAAAA==.Lotharshammy:BAAANQAECgcIDAAAAA==.',
Lu='Lukadoncic:BAACNQAFFH8QAAMMAAQKshqNCQD5AAAMAAQKshqNCQD5AAAaAAIKCxdGIACHAAA1AAQKfz8ABAwACgqiH84UAHkCAAwACgqiH84UAHkCAAcABgpbGBl0AEcBABoAAwqcGCqKANcAAAAA.Luminescent:BAAANQADCgMIAwAAAA==.Lunila:BAAANQADCgEIAQABNQAECgQIAwAGAAAAAA==.',
['Lö']='Lögäñ:BAABNQAECn8dAAMQAAkKYxJfHQBOAQAQAAkKYxJfHQBOAQACAAQKiwXhdwFkAAAAAA==.',
Ma='Maeby:BAAANQAECgUIBQABNQAECgkJIgAOAOwaAA==.Magepants:BAAANQAECgMIAwABNQAECgkJIAASANwWAA==.Magnessa:BAAANQAECgYICwAAAA==.Malekai:BAAANQADCgYICAAAAA==.Malovious:BAAANQADCggIIQAAAA==.Mano:BAABNQAECn8VAAIFAAkKOwnyMgA7AQAFAAkKOwnyMgA7AQAAAA==.Marist:BAABNQAECn8ZAAIEAAoKhAvgewCvAQAEAAoKhAvgewCvAQAAAA==.Marshabrady:BAAANQAECgEIAgAAAA==.Marwowi:BAAANQADCgIIAgAAAA==.',
Me='Memelord:BAAANQADCgQIBQAAAA==.Menadare:BAAANQAECgUICQAAAA==.Metaslave:BAAANQAECgUICgABNQAECgoKOAACAB0iAA==.Meteion:BAAANQAECgEIAQAAAA==.',
Mi='Miance:BAAANQADCgEIAQABNQAECgYIHAAdALsYAA==.Mianceden:BAABNQAECn8cAAIdAAYKuxg7HgBjAQAdAAYKuxg7HgBjAQAAAA==.Miansbane:BAAANQAECgQIBwAAAA==.Micahscream:BAAANQAECgIIAgAAAA==.Midheaven:BAAANQAECgUICgAAAA==.Miku:BAAANQADCgcIEAABNQAECgoKNgACAK4YAA==.Milent:BAAANQAECgYIDQAAAA==.Mimix:BAAANQADCggIDgAAAA==.Minasa:BAAANQADCgEIAQAAAA==.Miquiztli:BAAANQAECggIBAAAAA==.Mizoci:BAAANQAECgUICAAAAA==.',
Mo='Mongoose:BAABNQAECn8fAAIRAAkKbhqZJAAEAwARAAkKbhqZJAAEAwAAAA==.Monkeyk:BAAANQADCggICwAAAA==.',
Ms='Msspelled:BAABNQAECn8YAAMeAAcKuhAVGwCqAAAUAAcKYxAusQBuAQAeAAUKzREVGwCqAAAAAA==.',
Mu='Muichiro:BAAANQADCgQIBAAAAA==.Murcielago:BAAANQAECgIIAgAAAA==.',
Mv='Mvpiam:BAAANQAECgYIBwAAAA==.Mvpsevoker:BAAANQADCgcICQAAAA==.Mvpspally:BAAANQADCgEIAQAAAA==.',
Mx='Mximus:BAAANQADCgMIAwABNQAECgYIDQAGAAAAAA==.',
My='Mystí:BAABNQAECn8cAAIKAAoK8BnggQB7AgAKAAoK8BnggQB7AgAAAA==.',
['Má']='Májorpáin:BAAANQAECgYICgABNQAECgoKKgAUAGgYAA==.',
Na='Nabstarr:BAABNQAECn8mAAIOAAkKLBpuLABgAgAOAAkKLBpuLABgAgAAAA==.Namaiki:BAAANQADCgUICQAAAA==.Nasroth:BAAANQAECgYIDQAAAA==.Nasstina:BAAANQAECgEIAQABNQAECggIDQAGAAAAAA==.Natureterror:BAAANQADCggIFgAAAA==.Naví:BAAANQADCgIIAgAAAA==.',
Ni='Nicefella:BAAANQAECgEIAQAAAA==.Niibyter:BAABNQAECn8YAAIdAAYKsxy4EgBSAQAdAAYKsxy4EgBSAQAAAA==.Nitrolan:BAAANQADCgUIBQAAAA==.',
No='Nodiddles:BAAANQADCgYIBgAAAA==.',
Ob='Oberon:BAAANQABCgMIAwAAAA==.',
Oc='Oceanbreeze:BAAANQADCggICQAAAA==.',
Oj='Ojasam:BAAANQAECgEIBgAAAA==.',
On='Onlylocks:BAAANQAECgYIDAAAAA==.',
Or='Oralia:BAAANQADCgQIBAAAAA==.Orasha:BAAANQADCgIIAgAAAA==.Orlisman:BAABNQAECn8XAAMDAAoKMRalOgB0AgADAAoKMRalOgB0AgAEAAEKXgJL7gAoAAAAAA==.',
Pa='Palobo:BAAANQABCgQIBAAAAA==.Pandamunx:BAAANQADCgEJAQAAAA==.',
Pe='Peludin:BAAANQADCgQIBAAAAA==.',
Ph='Phaka:BAABNQAECn8mAAIHAAgKrBhATADkAQAHAAgKrBhATADkAQAAAA==.Phelanx:BAAANQAECgMIAgAAAA==.Philanthropy:BAABNQAECn8sAAMbAAgK2h+hDADbAgAbAAgK2h+hDADbAgAPAAEKRw7zHwA/AAAAAA==.Philsoom:BAAANQAECgYIBgAAAA==.',
Pi='Pizzeroloko:BAABNQAECn8sAAIIAAoKChzaBgD7AgAIAAoKChzaBgD7AgAAAA==.',
Pl='Placebo:BAABNQAECn8iAAIOAAkK7BqZKwC6AgAOAAkK7BqZKwC6AgAAAA==.Playforever:BAAANQADCgQIBwAAAA==.Pläze:BAAANQAECgIIAgAAAA==.',
Pr='Prahd:BAAANQAECgcIEgAAAA==.',
Pu='Purrsephonie:BAABNQAECn8hAAIRAAcKbQSkwQDqAAARAAcKbQSkwQDqAAAAAA==.',
Pw='Pweist:BAAANQADCggIGAABNQAECgMIAwAGAAAAAA==.',
Py='Pyronorish:BAAANQAECgQIBgAAAA==.Pytthia:BAABNQAECn8cAAMYAAcK8Q2yMwCFAQAYAAcK8Q2yMwCFAQAZAAUKLg0+EgADAQAAAA==.',
Qu='Quicknclever:BAAANQAECgEIAQAAAA==.',
Ra='Raptalia:BAAANQAECgEIAQABNQAECgoKNgACAK4YAA==.Rayo:BAAANQADCgEIAQAAAA==.Rayphe:BAAANQADCgEIAQAAAA==.Rayquaza:BAAANQADCgIIAgABNQAFFAgIHAANAGgTAA==.Razclat:BAAANQAECgEIAQAAAA==.Raziel:BAAANQAECgMIBQAAAA==.',
Re='Redpepperz:BAAANQAECgIIAgAAAA==.Reldruin:BAAANQADCgUICQAAAA==.Rexi:BAAANQADCgQICAAAAA==.',
Rh='Rhaena:BAAANQAECgIIAgAAAA==.Rhombus:BAABNQAECn8aAAIcAAYKagyvdgAgAQAcAAYKagyvdgAgAQAAAA==.',
Ri='Rickjamesbia:BAAANQAECgEIAQAAAA==.Riorson:BAABNQAECn8gAAIaAAoKgQ//SwDGAQAaAAoKgQ//SwDGAQAAAA==.Rizhir:BAAANQADCgUIFgAAAA==.',
Ro='Ronkey:BAAANQAECgIIAgAAAA==.Ronkzar:BAAANQADCgUICgAAAA==.',
['Rô']='Rôflstômp:BAAANQAECgYICQAAAA==.',
Sa='Sacklord:BAAANQADCggICAAAAA==.Sakai:BAAANQADCggICAAAAA==.Salanis:BAAANQAECgIIAgABNQAECgoKJgAcAAwkAA==.Saltnpepperz:BAAANQAECgIIAgAAAA==.Saltydog:BAAANQADCgQIGwAAAA==.Sammy:BAAANQAECgEIAgAAAA==.',
Sc='Scurge:BAAANQAECgYIDQAAAA==.',
Se='Sebasmatute:BAAANQAECgcIBwAAAA==.Seizo:BAAANQAECgQIBwAAAA==.Serazen:BAABNQAECn8UAAMfAAgKDgtSDQDiAAAfAAgKhQpSDQDiAAAPAAMKHwXXGACEAAAAAA==.Setal:BAAANQAECgIIAgAAAA==.',
Sg='Sgtpepperz:BAAANQAECgIIAgAAAA==.',
Sh='Shallteàr:BAAANQAECgQIDQAAAA==.Shammysathh:BAAANQAECgIIAgAAAA==.Shamurloc:BAAANQADCgEIAQAAAA==.Sheenatonic:BAAANQADCgYIDAABNQAECgkJHQAcAD8MAA==.Sheenzilla:BAAANQADCgYIDAABNQAECgkJHQAcAD8MAA==.Shiftr:BAAANQAECgcIDQABNQAECgoKGAALACURAA==.Shockaholix:BAAANQADCgUIBQABNQAECgYIDQAGAAAAAA==.Shoinked:BAAANQAECgUIDQAAAA==.Shoveldin:BAAANQAECgQIBAAAAA==.',
Si='Sices:BAAANQADCgQIBQAAAA==.Silentpaw:BAABNQAECn8sAAMgAAcKZiGNBgDdAQAgAAcKZiGNBgDdAQALAAMKcBXGPACRAAABNQAECgoKKgAUAGgYAA==.',
Sl='Slamarama:BAAANQADCgIIAgAAAA==.',
Sm='Smallblades:BAAANQADCgUIBQAAAA==.Smallêntropy:BAABNQAECn8XAAIBAAcKrxLwEwDaAAABAAcKrxLwEwDaAAAAAA==.Smelt:BAAANQADCgYICAAAAA==.Smuurfdk:BAEANQADCggICQABNQAECgcIDwAGAAAAAA==.Smuurfhands:BAEANQAECgcIDwAAAA==.',
So='Sogekin:BAAANQADCgIIAgAAAA==.Soulbringer:BAAANQAECggICgAAAA==.',
Sp='Spriggy:BAAANQAECgQIEQAAAA==.',
St='Stabbytrout:BAABNQAECn8fAAIhAAkKKCNICABSAwAhAAkKKCNICABSAwAAAA==.Stabyotoe:BAAANQADCgUIBQAAAA==.',
Su='Sugar:BAAANQADCggICAAAAA==.Sunetra:BAABNQAECn8eAAICAAoKmQs7kQBpAQACAAoKmQs7kQBpAQAAAA==.Sushi:BAAANQADCgcIEQAAAA==.',
Sy='Sylvariel:BAAANQADCgEIAQAAAA==.',
['Sà']='Sàlanis:BAAANQADCgMIAwABNQAECgoKJgAcAAwkAA==.',
['Sã']='Sãlanis:BAAANQAECgIIBQABNQAECgoKJgAcAAwkAA==.',
['Sä']='Sälanis:BAABNQAECn8mAAMcAAoKDCQGAwDiAwAcAAoKDCQGAwDiAwACAAEKAADFuQErAAAAAA==.Säpättäck:BAAANQAECgYIBgAAAA==.',
Ta='Taal:BAAANQADCgQIBAABNQAECgoKLwASADEdAA==.Taehyung:BAAANQAECgcIEQAAAA==.Taintcleaver:BAAANQAECgEIAgAAAA==.Tainthel:BAAANQADCgUIBQAAAA==.Tairyn:BAABNQAECn8/AAMJAAoKRyKeIAA1AwAJAAoKdyGeIAA1AwAdAAkKKxsCCQAPAgAAAA==.Taloki:BAAANQAECgQICgAAAA==.Tatsuhisa:BAAANQADCgYIEAAAAA==.',
Te='Telavore:BAAANQAECgEIAgAAAA==.Telle:BAAANQAECgQIBgAAAA==.Terciodk:BAAANQAECgUICQAAAA==.Terregoat:BAAANQADCgUIBQAAAA==.',
Th='Thrallmarr:BAAANQADCgIIAgAAAA==.Thruder:BAAANQADCgQIBgAAAA==.',
Ti='Tinkerfoot:BAAANQADCgEIAQAAAA==.Titfortat:BAAANQADCgYICwAAAA==.',
To='Tomaktoma:BAAANQADCgUIBgAAAA==.Tophdh:BAAANQAECgUIBQAAAA==.Totemicblank:BAAANQAECgIIAgAAAA==.',
Tr='Traydle:BAAANQAECggIDQAAAA==.Trondur:BAABNQAECn8aAAIJAAkKLx8JUACZAgAJAAkKLx8JUACZAgAAAA==.Trydel:BAAANQADCgcIEgABNQAECggIDQAGAAAAAA==.Trygon:BAAANQADCgYIBgABNQAECggIDQAGAAAAAA==.',
Tu='Tuffnnice:BAAANQAECgEIAgAAAA==.Tuini:BAAANQADCgcIFQAAAA==.',
Ty='Tydis:BAAANQAECgEIAQAAAA==.',
['Tá']='Tálonstorm:BAABNQAECn8nAAIJAAcKZAJZ3ACIAAAJAAcKZAJZ3ACIAAAAAA==.',
Ul='Ultra:BAAANQABCgIIAgAAAA==.',
Va='Valynaria:BAAANQAECgMICAAAAA==.Vani:BAABNQAECn8UAAIOAAcK7wy2awBdAQAOAAcK7wy2awBdAQAAAA==.',
Ve='Vendetta:BAAANQAECgYICAABNQAECgYIDQAGAAAAAA==.',
Vi='Victim:BAAANQADCgEIAQAAAA==.Vilthrax:BAAANQAECgIIAwAAAA==.',
Vu='Vulcanus:BAAANQAECgEIAQAAAA==.',
['Vè']='Vèngeance:BAAANQAECgUIBQAAAA==.',
Wa='Warchiéf:BAAANQAECgYIEgAAAA==.Warent:BAAANQADCgEIAQAAAA==.',
Wh='Whalaski:BAABNQAECn8/AAIRAAoKMxtJMQBQAgARAAoKMxtJMQBQAgAAAA==.Whistledown:BAAANQADCggICQAAAA==.',
Wi='Wickedsin:BAAANQAECgQIBAAAAA==.Wickedstorm:BAAANQADCggIFQAAAA==.Wingstop:BAAANQAECgEIAgABNQAECggIFgAFABkHAA==.',
Wo='Woggieboggie:BAAANQAECggIAgAAAA==.Woolybülly:BAAANQAECgIIAgAAAA==.',
Wr='Wreckitman:BAACNQAFFH8JAAMNAAQKtwZhDACqAAANAAQKtwZhDACqAAAFAAIK5wAQIAAqAAA1AAQKfykAAw0ACQp3GjwSAL4CAA0ACQp3GjwSAL4CAAUABwrUBNBmADEBAAAA.',
Xa='Xaalath:BAABNQAECn8jAAMiAAgKSgxxEgAnAQAiAAgKSgxxEgAnAQAKAAEKAACL5AEhAAAAAA==.',
Xy='Xyah:BAAANQADCgEIAQAAAA==.',
['Xé']='Xéno:BAABNQAECn8rAAIbAAkKJxECFQBjAQAbAAkKJxECFQBjAQAAAA==.',
Yo='Yobaz:BAAANQADCgYIFwAAAA==.Yohanan:BAAANQADCgEIAQAAAA==.Yozomi:BAAANQADCgYIJAAAAA==.',
Za='Zappya:BAAANQAECgEIAgAAAA==.Zarorisk:BAAANQAECgUIBgABNQAFFAYICgAIAKEQAA==.',
Ze='Zedd:BAABNQAECn8fAAINAAkKYA4gNQByAQANAAkKYA4gNQByAQABNQADCgcIFQAGAAAAAA==.Zewse:BAAANQAECgUIBgAAAA==.',
Zu='Zurath:BAAANQADCgEIAQAAAA==.',
Zy='Zyrax:BAAANQADCgEIAQAAAA==.',
['Øm']='Ømen:BAAANQADCgEIAQAAAA==.',
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
