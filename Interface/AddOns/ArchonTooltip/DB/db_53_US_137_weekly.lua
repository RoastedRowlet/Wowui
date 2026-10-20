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

local lookup = {'DemonHunter-Vengeance','Paladin-Retribution','Shaman-Restoration','Unknown-Unknown','Druid-Feral','Warrior-Arms','Mage-Arcane','Monk-Windwalker','DeathKnight-Frost','Druid-Restoration','Druid-Balance','Priest-Holy','Shaman-Elemental','DeathKnight-Unholy','Paladin-Protection','Shaman-Enhancement','Warlock-Demonology','Warlock-Destruction','Monk-Mistweaver','Hunter-Survival','Priest-Discipline','Priest-Shadow','DeathKnight-Blood','Evoker-Preservation','Hunter-BeastMastery','Warrior-Protection','Evoker-Devastation','Paladin-Holy','Monk-Brewmaster','Rogue-Assassination','Mage-Frost',}
local provider = {region='US',realm='Korialstrasz',name='US',type='weekly',zone=53,date='2026-10-20',data={Ac='Accursed:BAACNQAFFH8LAAIBAAQKPB+5AAD2AAABAAQKPB+5AAD2AAA1AAQKfywAAgEACQoxJPEBAHkDAAEACQoxJPEBAHkDAAAA.Activesloth:BAAANQADCgQJBAABNQAECgoKJgACAIIfAA==.',
Ad='Adekeai:BAAANQAECgYIEwAAAA==.Adol:BAAANQADCgYIBgAAAA==.',
Ae='Aelys:BAAANQAECgQIBQAAAA==.',
Al='Aleighta:BAABNQAECn8YAAIDAAkKYgwSiAB2AQADAAkKYgwSiAB2AQAAAA==.Alenara:BAAANQADCgMJAwAAAA==.Allblond:BAAANQADCgYIBgAAAA==.Alyx:BAAANQADCgYIBgAAAA==.',
Am='Amouri:BAAANQABCgIIAgAAAA==.',
An='Anacreon:BAAANQAECgQIAgAAAA==.Anaiah:BAAANQADCggIDgABNQAECgUIEQAEAAAAAA==.',
Ar='Arcey:BAAANQADCgIIAgAAAA==.Arun:BAAANQADCgQIBAABNQAECgUICwAEAAAAAA==.',
As='Asmodius:BAAANQADCgMIAwAAAA==.Aspros:BAAANQAECggIEAAAAA==.',
At='Atlantis:BAAANQAECgUICgAAAA==.Atonement:BAABNQAECn8dAAICAAkK8xWcEAD2AQACAAkK8xWcEAD2AQAAAA==.',
Av='Avengence:BAAANQADCgIIAgAAAA==.',
Ay='Ayshan:BAAANQAECgQIBAABNQAECgQIBQAEAAAAAA==.',
Ba='Badoussi:BAAANQAECgQICAABNQAFFAQIBQAFACoJAA==.Baja:BAAANQAECgQIBAAAAA==.Bakugo:BAAANQADCgMIAwAAAA==.Bananas:BAAANQAECgEIAQAAAA==.',
Be='Beansy:BAAANQADCgUICgAAAA==.Beefomancer:BAAANQAECgMIAwAAAA==.Belladin:BAABNQAECn8lAAICAAoKChbUcQBMAgACAAoKChbUcQBMAgAAAA==.Belzugaim:BAABNQAECn8UAAIGAAgKVgsFpwC7AQAGAAgKVgsFpwC7AQABNQADCgQIBwAEAAAAAA==.',
Bi='Bipolarcurys:BAAANQAECgQICwAAAA==.Bismuth:BAAANQAECgUICwAAAA==.',
Bl='Blamethedps:BAAANQAECgQIBgABNQAECggIFgAHAHUbAA==.Blameyomomma:BAAANQAECgYICgABNQAECggIFgAHAHUbAA==.Blamezuko:BAABNQAECn8WAAIHAAgKdRt0ngBEAgAHAAgKdRt0ngBEAgAAAA==.Blite:BAAANQADCgUIDQAAAA==.Blumoon:BAAANQADCgcIBwAAAA==.',
Bo='Bombakaap:BAACNQAFFH8IAAIIAAQK8grLBADIAAAIAAQK8grLBADIAAA1AAQKfyMAAggACgpJHMgGAKMBAAgACgpJHMgGAKMBAAAA.Bomburst:BAAANQAECgUIDAAAAA==.Bonelespizza:BAACNQAFFH8IAAIJAAIKex5cFACbAAAJAAIKex5cFACbAAA1AAQKfzMAAgkACgrGH/MQAAcDAAkACgrGH/MQAAcDAAAA.Bonkthump:BAAANQAECgEIAQAAAA==.Boogiebabe:BAABNQAECn8xAAMKAAkKvxQiCAC7AQAKAAkKvxQiCAC7AQALAAQKOwdohQC8AAAAAA==.Bornix:BAAANQADCgUIBQABNQAECgkJMgAHADYWAA==.',
Br='Briaris:BAAANQAECgcIEAABNQAECgoKJwAFALIZAA==.Brosar:BAAANQAECgEIAQAAAA==.Brugaras:BAAANQABCgIIAgAAAA==.',
['Bê']='Bêz:BAAANQAECgQIBAAAAA==.',
['Bë']='Bëz:BAABNQAECn8ZAAIBAAYKgCFABABZAQABAAYKgCFABABZAQAAAA==.',
Ca='Cadzan:BAAANQABCgUIAwAAAA==.Caith:BAAANQABCgYIBgAAAA==.Calabretta:BAAANQADCgcIGQAAAA==.Cannan:BAAANQADCgYIBgAAAA==.Captcow:BAAANQABCgYIBgAAAA==.Caver:BAAANQADCgcIDQAAAA==.',
Ch='Charysmaa:BAAANQADCgUIDwAAAA==.Cheoekar:BAAANQAECgUIBwABNQAFFAQIDAAMAN4YAA==.',
Co='Cobey:BAABNQAECn8jAAICAAkKSRdLjAANAgACAAkKSRdLjAANAgAAAA==.Coldrick:BAAANQAECgMIBQABNQAECgcIBAAEAAAAAA==.Cosmicjay:BAACNQAFFH8IAAINAAQKgBFhBgDtAAANAAQKgBFhBgDtAAA1AAQKfyEAAg0ACQqyH3ssAMwCAA0ACQqyH3ssAMwCAAAA.Cosmicnova:BAABNQAECn8UAAIJAAgKfhOlJwABAQAJAAgKfhOlJwABAQABNQAFFAQICAANAIARAA==.',
Cr='Crumpet:BAAANQAECggIAgAAAA==.',
Cu='Cursedknight:BAAANQADCgYIEgAAAA==.',
Da='Daegán:BAAANQADCgMIAwAAAA==.Daffodil:BAAANQAECgUIEgAAAA==.Dalavian:BAAANQABCgQIBAAAAA==.Dannyhurt:BAAANQADCgcIDwAAAA==.Dantruis:BAACNQAFFH8LAAIOAAUKyQ+iDQAyAQAOAAUKyQ+iDQAyAQA1AAQKfyMAAg4ACgrzHcocAN8CAA4ACgrzHcocAN8CAAAA.Darlins:BAAANQADCgYIBgAAAA==.',
Di='Dianah:BAAANQADCgUICgAAAA==.Diggy:BAAANQADCgYICwAAAA==.Dinsfirë:BAAANQADCgIIAgAAAA==.Diothorn:BAABNQAECn8YAAMCAAYKvA3n/wAgAQACAAYKyAvn/wAgAQAPAAMKaA80VgCIAAAAAA==.Divanas:BAAANQAECgUIDQAAAA==.Divi:BAAANQAECgUIEQAAAA==.Divinium:BAAANQADCgQIBAABNQAECgUIEQAEAAAAAA==.',
Do='Dogfacethug:BAAANQAECgEIAQAAAA==.Dorianna:BAAANQAECgYIDAAAAA==.',
Dr='Dreamit:BAAANQADCgMIAwAAAA==.Drease:BAAANQADCgEIAQAAAA==.Drpepperz:BAAANQAECgEIAgAAAA==.Drunkdragon:BAAANQADCgcICwAAAA==.',
Ea='Earthtide:BAAANQADCgYICwAAAA==.',
El='Elfsa:BAAANQAECgQICAAAAA==.Ellayria:BAAANQAECgUIEgAAAA==.Elymaria:BAAANQAECgQIEAAAAA==.',
Em='Emberrose:BAABNQAECn8VAAIFAAYKlwfZEAChAAAFAAYKlwfZEAChAAAAAA==.',
En='Enhancedpant:BAABNQAECn8aAAIQAAcKjRnsFQAKAgAQAAcKjRnsFQAKAgAAAA==.Ensetral:BAAANQAECgQIDAAAAA==.',
Ev='Evernight:BAAANQAECgcIDQAAAA==.',
Fa='Fakedruid:BAAANQAECgEIAQABNQAECgMIAwAEAAAAAA==.',
Fe='Feerahion:BAAANQADCgMIAwAAAA==.Feledris:BAAANQAECgcIBwAAAA==.Felwynne:BAAANQAECgUIDAAAAA==.Feybeasts:BAAANQAECgQIBwAAAA==.Feárbomber:BAABNQAECn8iAAMRAAoKfxN9fQDsAQARAAkKMBJ9fQDsAQASAAIKIxCxVgB6AAAAAA==.',
Fh='Fhala:BAAANQADCggICAAAAA==.Fharia:BAAANQAECgYIDQAAAA==.',
Fi='Fivo:BAAANQABCgEIAQAAAA==.',
Fl='Flayr:BAAANQADCggICgAAAA==.Flopper:BAAANQABCgQIBAAAAA==.',
Fr='Fries:BAEANQAECggICAABNQAECggIDwAEAAAAAA==.',
Fu='Fusky:BAAANQAECgUIEAAAAA==.',
Fy='Fynn:BAABNQAECn8oAAIQAAkK4h1zCQDeAgAQAAkK4h1zCQDeAgAAAA==.',
['Fé']='Férn:BAAANQAECgEIAQAAAA==.',
Ga='Galadria:BAACNQAFFH8FAAILAAIKrAa5DACNAAALAAIKrAa5DACNAAA1AAQKfzIAAgsACQprHF0dAN4CAAsACQprHF0dAN4CAAAA.Garamond:BAAANQADCggIDwAAAA==.Garnd:BAAANQADCgIIAgAAAA==.Garrish:BAAANQABCgQIBgAAAA==.Gastly:BAAANQADCgEIAQAAAA==.',
Ge='Gerwik:BAAANQAECgQIBwAAAA==.',
Gi='Gimlih:BAAANQADCgEIAQAAAA==.',
Go='Gogetta:BAAANQAECggICwAAAA==.Govana:BAAANQAECgEIAQAAAA==.',
Gr='Greenleaves:BAAANQAECgIJAgAAAA==.',
Gu='Gummiwormz:BAAANQADCgQIBAAAAA==.',
Gy='Gyat:BAAANQADCgUJBwABNQAECggIIAAOAEwYAA==.',
Ha='Hailin:BAABNQAECn8tAAICAAoKrBd+KACGAQACAAoKrBd+KACGAQAAAA==.Haunter:BAAANQAECgUIDQAAAA==.',
He='Heherawr:BAAANQADCgIIAgABNQADCgMIBgAEAAAAAA==.',
Hi='Hima:BAAANQAECgUICwAAAA==.',
Ho='Holyjenkins:BAAANQAECgQIBAAAAA==.Horngrry:BAAANQAECgUIDQAAAA==.',
Il='Illtrytoheal:BAAANQADCgYICgAAAA==.',
Im='Imkillho:BAAANQAECgQJBAABNQAECgUIDQAEAAAAAA==.',
In='Inosuke:BAAANQADCgQIBAAAAA==.Inspiredbox:BAAANQAECgIIAwAAAA==.',
Is='Issyo:BAAANQAECgMIAwAAAA==.',
Ja='Jankismith:BAABNQAECn8YAAITAAUKOwtINADJAAATAAUKOwtINADJAAAAAA==.Jayy:BAABNQAECn8UAAIUAAUKhwo7BQD3AAAUAAUKhwo7BQD3AAAAAA==.',
Jf='Jflyer:BAAANQADCgIIAgABNQAFFAQICAANAIARAA==.',
Ji='Jimin:BAAANQAECgcIEQAAAA==.Jitoflight:BAAANQADCgEIAQAAAA==.',
Jm='Jmajk:BAAANQABCgcICAAAAA==.',
Ju='Jugger:BAAANQADCgcICQAAAA==.',
Ka='Kachiko:BAAANQADCgYICQAAAA==.Kaethis:BAAANQABCgUJBQAAAA==.Kaia:BAAANQAECgYIDAAAAA==.Kamchan:BAAANQAECgQIBQABNQAFFAUICwAMAH4JAA==.Kamerth:BAABNQAECn8UAAQVAAUKgQTxIQBWAAAMAAUKiAInzwC3AAAWAAQKLAVuIACIAAAVAAIKAgjxIQBWAAAAAA==.Kapbam:BAAANQADCggICgAAAA==.Karluron:BAAANQAECgYIEAAAAA==.Karlutros:BAABNQAECn8eAAIWAAgKxRTkJwDrAQAWAAgKxRTkJwDrAQAAAA==.Katbaka:BAAANQADCggIDAABNQAFFAUIEAAXAIklAA==.Katmoreahh:BAAANQADCgcIBwABNQAFFAUIEAAXAIklAA==.Katuwuagain:BAACNQAFFH8QAAIXAAUKiSVXBQAMAQAXAAUKiSVXBQAMAQA1AAQKfy8AAhcACQpnJe8IAHIDABcACQpnJe8IAHIDAAAA.Kayonalani:BAAANQAECgEIAQAAAA==.Kazure:BAABNQAECn8iAAIYAAoKwAajJQCRAQAYAAoKwAajJQCRAQAAAA==.',
Ke='Kelilia:BAABNQAECn8vAAIGAAkKBhImcgA+AgAGAAkKBhImcgA+AgAAAA==.Kenilar:BAAANQAECgQIBwAAAA==.Keybricker:BAAANQADCgMIAwABNQAECgMIAwAEAAAAAA==.',
Ko='Konga:BAAANQAECgQIDgAAAA==.Korngry:BAAANQADCgUIBgABNQAECgUIDQAEAAAAAA==.',
Kr='Krakkin:BAAANQADCgYIHwAAAA==.Krenil:BAAANQADCgQIDwAAAA==.',
Ku='Kuassei:BAABNQAECn8aAAIKAAkKNBr0BwC+AQAKAAkKNBr0BwC+AQAAAA==.',
Ky='Kyatto:BAAANQAECgcIDwABNQAFFAUIEAAXAIklAA==.Kyllea:BAAANQAECgQICAAAAA==.',
La='Laaksy:BAAANQAECgUIBwABNQAECgkJHwAZAG4aAA==.Ladraina:BAAANQADCgYIBgAAAA==.Landock:BAAANQADCgYIGgAAAA==.Larynnoelle:BAAANQAECggIEwAAAA==.',
Le='Lebronjames:BAAANQAECgcICQABNQAFFAMICAAJABEXAA==.Leotart:BAABNQAECn8pAAIKAAkKtxPxBQD1AQAKAAkKtxPxBQD1AQAAAA==.Lesbians:BAAANQAECgUICwAAAA==.Leyland:BAAANQADCgcIGwAAAA==.',
Li='Lilsus:BAAANQADCggICAABNQAECgQIBAAEAAAAAA==.Linaraline:BAAANQADCgQIBAAAAA==.Linni:BAABNQAECn8cAAIKAAgKyAm1PQA2AQAKAAgKyAm1PQA2AQAAAA==.Lizawizah:BAAANQAECgQIBAAAAA==.',
Lo='Lortnok:BAAANQAECgIIAwAAAA==.Lotharlock:BAAANQADCgQIBAAAAA==.Lotharpally:BAAANQAECgUIBwAAAA==.Lotharshammy:BAAANQAECgQIBgAAAA==.',
Lu='Lukadoncic:BAACNQAFFH8IAAMJAAMKERdrBAD0AAAJAAMKERdrBAD0AAAXAAIKCxdGIACHAAA1AAQKfzEABAkACgp5HRAbALICAAkACgp5HRAbALICAA4ABgpbGBl0AEcBABcAAwqcGCqKANcAAAAA.Lunila:BAAANQADCgEIAQABNQAECgQIAwAEAAAAAA==.',
['Lö']='Lögäñ:BAAANQAECggIDgAAAA==.',
Ma='Maeby:BAAANQAECgUIBQABNQAECgkJHAAMAOwaAA==.Magnessa:BAAANQAECgYICwAAAA==.Malekai:BAAANQADCgYICAAAAA==.Malovious:BAAANQADCggIHwAAAA==.Mano:BAAANQAECgcIBgAAAA==.Marist:BAABNQAECn8YAAINAAkKCQvgewCvAQANAAkKCQvgewCvAQAAAA==.Marshabrady:BAAANQAECgEIAQAAAA==.Marwowi:BAAANQADCgIIAgAAAA==.',
Me='Memelord:BAAANQADCgQIBAAAAA==.Menadare:BAAANQAECgUICQAAAA==.Metaslave:BAAANQAECgUICgABNQAECgoKJgACAIIfAA==.Meteion:BAAANQAECgEIAQAAAA==.',
Mi='Mianceden:BAABNQAECn8XAAIaAAUKFRugDwDBAAAaAAUKFRugDwDBAAAAAA==.Miansbane:BAAANQAECgQIBwAAAA==.Micahscream:BAAANQAECgIIAgAAAA==.Midheaven:BAAANQAECgUICgAAAA==.Miku:BAAANQADCgcIDwABNQAECgoKLQACAKwXAA==.Milent:BAAANQAECgYIDQAAAA==.Mimix:BAAANQABCgIIAgAAAA==.Miquiztli:BAAANQAECggIAwAAAA==.Mizoci:BAAANQAECgEIBAAAAA==.',
Mo='Mongoose:BAABNQAECn8fAAIZAAkKbhqZJAAEAwAZAAkKbhqZJAAEAwAAAA==.Monkeyk:BAAANQADCgMIAwAAAA==.',
Ms='Msspelled:BAAANQAECgYIDwAAAA==.',
Mu='Muichiro:BAAANQADCgQIBAAAAA==.',
Mv='Mvpiam:BAAANQAECgYIBwAAAA==.Mvpsevoker:BAAANQADCgcICQAAAA==.Mvpspally:BAAANQADCgEIAQAAAA==.',
Mx='Mximus:BAAANQADCgMIAwABNQAECgcIBAAEAAAAAA==.',
My='Mystí:BAABNQAECn8YAAIHAAoKBBTggQB7AgAHAAoKBBTggQB7AgAAAA==.',
['Má']='Májorpáin:BAAANQAECgUIBwABNQAECgoKIgARAH8TAA==.',
Na='Nabstarr:BAABNQAECn8aAAIMAAgKwxeFCwAsAgAMAAgKwxeFCwAsAgAAAA==.Namaiki:BAAANQADCgUICQAAAA==.Nasroth:BAAANQAECgYIDQAAAA==.Nasstina:BAAANQAECgEIAQABNQAECggICQAEAAAAAA==.Natureterror:BAAANQADCggIFQAAAA==.Naví:BAAANQADCgIIAgAAAA==.',
Ni='Nicefella:BAAANQAECgEIAQAAAA==.Niibyter:BAAANQAECgUIEgAAAA==.Nitrolan:BAAANQADCgUIBQAAAA==.',
No='Nodiddles:BAAANQADCgYIBgAAAA==.',
Oc='Oceanbreeze:BAAANQADCgYIBgAAAA==.',
Oj='Ojasam:BAAANQAECgIIAQAAAA==.',
On='Onlylocks:BAAANQAECgYIDAAAAA==.',
Or='Oralia:BAAANQADCgQIBAAAAA==.Orlisman:BAAANQAECggIEQAAAA==.',
Pa='Palobo:BAAANQABCgQIBAAAAA==.Pandamunx:BAAANQADCgEJAQAAAA==.',
Ph='Phaka:BAABNQAECn8gAAIOAAgKTBhATADkAQAOAAgKTBhATADkAQAAAA==.Phelanx:BAAANQAECgIIAgAAAA==.Philanthropy:BAABNQAECn8sAAMYAAgK2h+hDADbAgAYAAgK2h+hDADbAgAbAAEKRw7iEgBIAAAAAA==.Philsoom:BAAANQAECgUIBQAAAA==.',
Pi='Pizzeroloko:BAABNQAECn8nAAIFAAoKshnaBgD7AgAFAAoKshnaBgD7AgAAAA==.',
Pl='Placebo:BAABNQAECn8cAAIMAAkK7Br8EADvAQAMAAkK7Br8EADvAQAAAA==.Playforever:BAAANQADCgQIBwAAAA==.Pläze:BAAANQAECgIIAgAAAA==.',
Pr='Prahd:BAAANQAECgcIEgAAAA==.',
Pu='Purrsephonie:BAABNQAECn8VAAIZAAUKqQPABAH8AAAZAAUKqQPABAH8AAAAAA==.',
Pw='Pweist:BAAANQADCggIFwABNQAECgMIAwAEAAAAAA==.',
Py='Pyronorish:BAAANQADCgQIEgAAAA==.Pytthia:BAABNQAECn8YAAMWAAcKAg2yMwCFAQAWAAcKAg2yMwCFAQAVAAUKLg0+EgADAQAAAA==.',
Ra='Raptalia:BAAANQAECgEIAQABNQAECgoKLQACAKwXAA==.Rayquaza:BAAANQADCgIIAgABNQAFFAgIGwAKAAITAA==.Raziel:BAAANQAECgMIBQAAAA==.',
Re='Reldruin:BAAANQADCgUICAAAAA==.Rexi:BAAANQADCgQICAAAAA==.',
Rh='Rhaena:BAAANQAECgIIAgAAAA==.Rhombus:BAABNQAECn8UAAIcAAUKZAr0PwDrAAAcAAUKZAr0PwDrAAAAAA==.',
Ri='Rickjamesbia:BAAANQAECgEIAQAAAA==.Riorson:BAABNQAECn8gAAIXAAoKgQ8EIwDsAAAXAAoKgQ8EIwDsAAAAAA==.Rizhir:BAAANQADCgQIEQAAAA==.',
Ro='Ronkey:BAAANQAECgIIAgAAAA==.Ronkzar:BAAANQADCgUICAAAAA==.',
Sa='Sacklord:BAAANQADCggICAAAAA==.Sakai:BAAANQADCggICAAAAA==.Saltydog:BAAANQADCgQIFAAAAA==.',
Sc='Scurge:BAAANQAECgYICgABNQAECgcIBAAEAAAAAA==.',
Se='Sebasmatute:BAAANQADCggICAAAAA==.Seizo:BAAANQAECgQIBwAAAA==.Serazen:BAAANQAECggIEAAAAA==.Setal:BAAANQAECgEIAQAAAA==.',
Sh='Shallteàr:BAAANQAECgQIAwAAAA==.Shammysathh:BAAANQAECgIIAgAAAA==.Shamurloc:BAAANQADCgEIAQAAAA==.Sheenatonic:BAAANQADCgYIDAABNQAECggIEwAEAAAAAA==.Sheenzilla:BAAANQADCgYIDAABNQAECggIEwAEAAAAAA==.Shiftr:BAAANQAECgEIAQABNQAECggIDQAEAAAAAA==.Shockaholix:BAAANQADCgUIBQABNQAECgcIBAAEAAAAAA==.Shoinked:BAAANQAECgUIDQAAAA==.Shoveldin:BAAANQAECgQIBAAAAA==.',
Si='Sices:BAAANQADCgQIBAAAAA==.Silentpaw:BAABNQAECn8dAAIdAAUKGCOUBgAIAQAdAAUKGCOUBgAIAQABNQAECgoKIgARAH8TAA==.',
Sm='Smallblades:BAAANQADCgUIBQAAAA==.Smallêntropy:BAAANQAECgUIEQAAAA==.Smelt:BAAANQADCgYICAAAAA==.Smuurfdk:BAEANQADCggICAABNQAECgcIDwAEAAAAAA==.Smuurfhands:BAEANQAECgcIDwAAAA==.',
So='Sogekin:BAAANQADCgIIAgAAAA==.',
Sp='Spriggy:BAAANQAECgMICQAAAA==.',
St='Stabbytrout:BAABNQAECn8fAAIeAAkKKCNICABSAwAeAAkKKCNICABSAwAAAA==.Stabyotoe:BAAANQADCgUIBQAAAA==.',
Su='Sugar:BAAANQADCggICAAAAA==.Sunetra:BAABNQAECn8VAAICAAgKaAtc4QBZAQACAAgKaAtc4QBZAQAAAA==.Sushi:BAAANQADCgcIDwAAAA==.',
['Sà']='Sàlanis:BAAANQADCgMIAwABNQAECggIIwAcAJQkAA==.',
['Sã']='Sãlanis:BAAANQAECgEIAQABNQAECggIIwAcAJQkAA==.',
['Sä']='Sälanis:BAABNQAECn8jAAMcAAgKlCSgAQBAAwAcAAgKlCSgAQBAAwACAAEKAADFuQErAAAAAA==.Säpättäck:BAAANQAECgYIBgAAAA==.',
Ta='Taal:BAAANQADCgQIBAABNQAECgkJKAAQAOIdAA==.Taehyung:BAAANQAECgcICgAAAA==.Tainthel:BAAANQADCgUIBQAAAA==.Tairyn:BAABNQAECn8tAAMGAAoKNSGeIAA1AwAGAAoKNSGeIAA1AwAaAAIKZxafNwB0AAAAAA==.Taloki:BAAANQAECgIIAgAAAA==.Tatsuhisa:BAAANQADCgYIEAAAAA==.',
Te='Telavore:BAAANQAECgEIAQAAAA==.Telle:BAAANQAECgQIBgAAAA==.Terciodk:BAAANQAECgUIBQAAAA==.Terregoat:BAAANQADCgUIBQAAAA==.',
Th='Thrallmarr:BAAANQADCgIIAgAAAA==.Thruder:BAAANQADCgQIBgAAAA==.',
Ti='Titfortat:BAAANQADCgYICwAAAA==.',
To='Tomaktoma:BAAANQADCgMIAwAAAA==.Tophdh:BAAANQAECgUIBQAAAA==.Totemicblank:BAAANQAECgIIAgAAAA==.',
Tr='Traydle:BAAANQAECggIDQAAAA==.Trondur:BAABNQAECn8aAAIGAAkKLx8JUACZAgAGAAkKLx8JUACZAgAAAA==.Trydel:BAAANQADCgcIEQABNQAECggIDQAEAAAAAA==.Trygon:BAAANQADCgYIBgABNQAECggIDQAEAAAAAA==.',
Tu='Tuffnnice:BAAANQAECgEIAQAAAA==.Tuini:BAAANQADCgcIFAAAAA==.',
Ty='Tydis:BAAANQADCgYIGgAAAA==.',
['Tá']='Tálonstorm:BAABNQAECn8bAAIGAAUKewIMqwBWAAAGAAUKewIMqwBWAAAAAA==.',
Ul='Ultra:BAAANQABCgIIAgAAAA==.',
Va='Valynaria:BAAANQAECgQIBQAAAA==.Vani:BAAANQAECgUIDQAAAA==.',
Ve='Vendetta:BAAANQAECgcIBAAAAA==.',
Vi='Victim:BAAANQABCgIIAgAAAA==.Vilthrax:BAAANQAECgIIAwAAAA==.',
Vu='Vulcanus:BAAANQAECgEIAQAAAA==.',
['Vè']='Vèngeance:BAAANQAECgUJBQAAAA==.',
Wa='Warchiéf:BAAANQAECgYIEgAAAA==.Warent:BAAANQABCgIIAgAAAA==.',
Wh='Whalaski:BAABNQAECn8wAAIZAAkKSxp4CwAYAgAZAAkKSxp4CwAYAgAAAA==.Whistledown:BAAANQADCgYIBgAAAA==.',
Wi='Wickedsin:BAAANQADCgYIFgAAAA==.Wickedstorm:BAAANQADCggIFAAAAA==.Wingstop:BAAANQADCgIIAgABNQAECgYIDAAEAAAAAA==.',
Wo='Woggieboggie:BAAANQAECggIAgAAAA==.',
Wr='Wreckitman:BAACNQAFFH8JAAMKAAQKtwYIBgC8AAAKAAQKtwYIBgC8AAALAAIK5wAqEwAwAAA1AAQKfykAAwoACQp3GjwSAL4CAAoACQp3GjwSAL4CAAsABwrUBNBmADEBAAAA.',
Xa='Xaalath:BAABNQAECn8ZAAMfAAYK+wxfGwAXAQAfAAYK+wxfGwAXAQAHAAEKAACL5AEhAAAAAA==.',
['Xé']='Xéno:BAABNQAECn8rAAIYAAkKJxGzBQB+AQAYAAkKJxGzBQB+AQAAAA==.',
Yo='Yobaz:BAAANQADCgUIEQAAAA==.Yohanan:BAAANQABCgYICwAAAA==.Yozomi:BAAANQADCgYIHQAAAA==.',
Za='Zappya:BAAANQAECgEIAQAAAA==.Zarorisk:BAAANQAECgUIBgABNQAFFAQIBQAFACoJAA==.',
Ze='Zedd:BAABNQAECn8aAAIKAAkKIw0gNQByAQAKAAkKIw0gNQByAQABNQADCgcIFAAEAAAAAA==.Zewse:BAAANQAECgIIAgAAAA==.',
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
