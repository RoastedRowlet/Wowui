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

local lookup = {'DemonHunter-Vengeance','Paladin-Retribution','Shaman-Restoration','Shaman-Elemental','Unknown-Unknown','DeathKnight-Unholy','Druid-Feral','Warrior-Arms','Mage-Arcane','Monk-Windwalker','DeathKnight-Frost','Druid-Restoration','Druid-Balance','Priest-Holy','Evoker-Devastation','Paladin-Protection','Hunter-BeastMastery','Shaman-Enhancement','Warlock-Demonology','Warlock-Destruction','Monk-Mistweaver','Hunter-Survival','Priest-Shadow','Priest-Discipline','DeathKnight-Blood','Evoker-Preservation','Paladin-Holy','Warrior-Protection','Evoker-Augmentation','Monk-Brewmaster','Rogue-Assassination','Mage-Frost',}
local provider = {region='US',realm='Korialstrasz',name='US',type='weekly',zone=53,date='2026-10-27',data={Ac='Accursed:BAACNQAFFH8LAAIBAAQKPB89AQDnAAABAAQKPB89AQDnAAA1AAQKfywAAgEACQoxJPEBAHkDAAEACQoxJPEBAHkDAAAA.Activesloth:BAAANQADCgQJBAABNQAECgoKLAACAIIfAA==.',
Ad='Adekeai:BAABNQAECn8bAAMDAAkKFQ4PcQDrAAADAAcK+QkPcQDrAAAEAAMK9AHhvgA5AAAAAA==.Adol:BAAANQADCgYIBgAAAA==.',
Ae='Aelys:BAAANQAECgQIBgABNQAECgUICAAFAAAAAA==.',
Al='Aleighta:BAABNQAECn8fAAIDAAkKDA/GMwDPAQADAAkKDA/GMwDPAQAAAA==.Alenara:BAAANQADCgMJAwAAAA==.Allblond:BAAANQADCgYIBgAAAA==.Alyx:BAAANQAECgEIAwAAAA==.',
Am='Amouri:BAAANQABCgIIAgAAAA==.',
An='Anacreon:BAAANQAECgcIBQAAAA==.Anaiah:BAAANQADCggIDgABNQAECgUIEQAFAAAAAA==.',
Ar='Arcey:BAAANQADCgIIAgAAAA==.Arun:BAAANQADCgQIBAABNQAECgUICwAFAAAAAA==.',
As='Asmodius:BAAANQADCgMIAwAAAA==.Aspros:BAABNQAECn8UAAIGAAoKFQ4HTwDYAQAGAAoKFQ4HTwDYAQAAAA==.',
At='Atlantis:BAAANQAECgUIDgAAAA==.Atonement:BAABNQAECn8jAAICAAoKphTxQQD0AQACAAoKphTxQQD0AQAAAA==.',
Av='Avengence:BAAANQADCgIIAgAAAA==.',
Ay='Ayshan:BAAANQAECgUICAAAAA==.',
Ba='Badoussi:BAAANQAECgQICAABNQAFFAYICgAHAKEQAA==.Baja:BAAANQAECggIDQAAAA==.Bakugo:BAAANQADCgMIAwAAAA==.Bananas:BAAANQAECgEIAQAAAA==.',
Be='Beansy:BAAANQADCgUICgAAAA==.Beefomancer:BAAANQAECgMIBAAAAA==.Belladin:BAABNQAECn8lAAICAAoKChbUcQBMAgACAAoKChbUcQBMAgAAAA==.Belzugaim:BAABNQAECn8UAAIIAAgKVgsFpwC7AQAIAAgKVgsFpwC7AQABNQADCgQIBwAFAAAAAA==.Bertheigh:BAAANQAECgEIAQAAAA==.',
Bi='Bipolarcurys:BAAANQAECgQIDQAAAA==.Bismuth:BAAANQAECgUICwAAAA==.',
Bl='Blamethedps:BAAANQAECgQIBgABNQAECgkJHQAJAFsaAA==.Blameyomomma:BAAANQAECgYICwABNQAECgkJHQAJAFsaAA==.Blamezuko:BAABNQAECn8dAAIJAAkKWxrANgAXAgAJAAkKWxrANgAXAgAAAA==.Blite:BAAANQADCgYIEwAAAA==.Blumoon:BAAANQADCgcIBwAAAA==.',
Bo='Bombakaap:BAACNQAFFH8LAAIKAAQKnw+PBgDVAAAKAAQKnw+PBgDVAAA1AAQKfy0AAgoACgpXH1QIAI0CAAoACgpXH1QIAI0CAAAA.Bomburst:BAAANQAECgYIDQAAAA==.Bonelespizza:BAACNQAFFH8JAAILAAIKex5cFACbAAALAAIKex5cFACbAAA1AAQKf0AAAgsACgqtIjwGAAYDAAsACgqtIjwGAAYDAAAA.Bonkthump:BAAANQAECgEIAwAAAA==.Boogiebabe:BAABNQAECn85AAMMAAoK/BQyEQATAgAMAAoK/BQyEQATAgANAAQKOwdohQC8AAAAAA==.Bornix:BAAANQADCgUIBQABNQAECgoKNQAJAFkUAA==.',
Br='Briaris:BAAANQAECgcIEQABNQAECgoKKgAHABUbAA==.Brosar:BAAANQAECgEIAgAAAA==.Brugaras:BAAANQABCgIIAgAAAA==.',
['Bê']='Bêz:BAAANQAECgMICgAAAA==.',
['Bë']='Bëz:BAABNQAECn8gAAIBAAcK2B9mBwCLAQABAAcK2B9mBwCLAQAAAA==.',
Ca='Cadzan:BAAANQABCgUIAwAAAA==.Caith:BAAANQABCgYIBgAAAA==.Calabretta:BAAANQADCgcIGQAAAA==.Cannan:BAAANQADCgYIBgAAAA==.Captcow:BAAANQAECgEIAQAAAA==.Caver:BAAANQADCgcIDQAAAA==.',
Ch='Charysmaa:BAAANQADCgYIFQAAAA==.Cheoekar:BAAANQAECgUICQABNQAFFAUIDwAOAOYbAA==.',
Co='Cobey:BAABNQAECn8nAAICAAoK5hZLjAANAgACAAoK5hZLjAANAgAAAA==.Coldrick:BAAANQAECgMIBgABNQAECgYIDAAFAAAAAA==.Cosmicjay:BAACNQAFFH8LAAIEAAQKOBLZCgDgAAAEAAQKOBLZCgDgAAA1AAQKfyIAAgQACQrDIHssAMwCAAQACQrDIHssAMwCAAAA.Cosmicnova:BAABNQAECn8cAAILAAkKqRR1IQDAAQALAAkKqRR1IQDAAQABNQAFFAQICwAEADgSAA==.',
Cr='Crumpet:BAAANQAECggIAgAAAA==.',
Cu='Cursedknight:BAAANQADCgYIEgAAAA==.',
Da='Daegán:BAAANQADCgMIAwAAAA==.Daffodil:BAABNQAECn8YAAIPAAYK4gj7DgDlAAAPAAYK4gj7DgDlAAAAAA==.Dalaney:BAAANQADCgUIBQAAAA==.Dalavian:BAAANQABCgQIBAAAAA==.Dannyhurt:BAAANQADCgcIDwAAAA==.Dantruis:BAACNQAFFH8PAAIGAAYKYBZ0AwAQAQAGAAYKYBZ0AwAQAQA1AAQKfy0AAgYACgoDILAJAIcCAAYACgoDILAJAIcCAAAA.Darlins:BAAANQADCgcIBwAAAA==.',
Di='Dianah:BAAANQADCgUICgAAAA==.Diggy:BAAANQADCgcICwAAAA==.Dinsfirë:BAAANQADCgMIAwAAAA==.Diothorn:BAABNQAECn8gAAMCAAgKyAxDmwAdAQACAAgKewtDmwAdAQAQAAMKaA80VgCIAAAAAA==.Divanas:BAAANQAECgUIDgAAAA==.Divi:BAAANQAECgYIEgAAAA==.Divinium:BAAANQADCgQIBAABNQAECgYIEgAFAAAAAA==.',
Do='Dogfacethug:BAAANQAECgEIAgAAAA==.Dorianna:BAAANQAECgYIDwAAAA==.',
Dr='Dreamit:BAAANQADCgMIAwAAAA==.Drease:BAAANQADCgcICAAAAA==.Drpepperz:BAAANQAECgEIAwAAAA==.Drunkdragon:BAAANQADCgcICwAAAA==.',
Ea='Earthtide:BAAANQAECgEIAQAAAA==.',
El='Elaana:BAAANQAECgIIAQAAAA==.Elfsa:BAAANQAECgQICAAAAA==.Ellayria:BAABNQAECn8VAAIRAAcKkBMtcgBSAQARAAcKkBMtcgBSAQAAAA==.Elymaria:BAAANQAECgYIEQAAAA==.',
Em='Emberrose:BAABNQAECn8VAAIHAAYKlwfOIgD6AAAHAAYKlwfOIgD6AAAAAA==.',
En='Enhancedpant:BAABNQAECn8dAAISAAkK3BbsFQAKAgASAAkK3BbsFQAKAgAAAA==.Ensetral:BAAANQAECgQIDAAAAA==.',
Ev='Evernight:BAAANQAECgcIDwAAAA==.',
Fa='Fakedruid:BAAANQAECgEIAwABNQAECgMIBAAFAAAAAA==.',
Fe='Feerahion:BAAANQAECgEIAQAAAA==.Feledris:BAAANQAECgcIBwAAAA==.Felwynne:BAAANQAECgUIDgAAAA==.Ferrah:BAAANQAECgEIAQAAAA==.Feybeasts:BAAANQAECgQIBwAAAA==.Feárbomber:BAABNQAECn8iAAMTAAoKfxN9fQDsAQATAAkKMBJ9fQDsAQAUAAIKIxCxVgB6AAAAAA==.',
Fh='Fhala:BAAANQADCggICAAAAA==.Fharia:BAAANQAECgYIEAAAAA==.',
Fi='Fivo:BAAANQABCgEIAQAAAA==.',
Fl='Flayr:BAAANQADCggIEgAAAA==.Flopper:BAAANQAECgEIAQAAAA==.',
Fr='Fries:BAEANQAECggICAABNQAECggIEQAFAAAAAA==.',
Fu='Fusky:BAABNQAECn8XAAIDAAcKnxdONgDEAQADAAcKnxdONgDEAQAAAA==.',
Fy='Fynn:BAABNQAECn8sAAISAAoKvhxzCQDeAgASAAoKvhxzCQDeAgAAAA==.',
['Fé']='Férn:BAAANQAECgEIAgAAAA==.',
Ga='Galadria:BAACNQAFFH8GAAINAAMKrAaVEgCEAAANAAMKrAaVEgCEAAA1AAQKfzoAAg0ACgpYHV0dAN4CAA0ACgpYHV0dAN4CAAAA.Garamond:BAAANQAECgEIAQAAAA==.Garnd:BAAANQADCgIIAgAAAA==.Garrish:BAAANQABCgQIBgAAAA==.Gastly:BAAANQADCgEIAQAAAA==.',
Ge='Gerwik:BAAANQAECgUIDAAAAA==.',
Gi='Gimlih:BAAANQADCgEIAQAAAA==.',
Go='Gogetta:BAAANQAECggIEAAAAA==.Goldenlock:BAAANQAECgEIAgAAAA==.Govana:BAAANQAECgEIAgAAAA==.',
Gr='Greenleaves:BAAANQAECgIIAgAAAA==.',
Gu='Gummiwormz:BAAANQADCgQIBAAAAA==.',
Gy='Gyat:BAAANQADCgUJBwABNQAECggIJQAGAEwYAA==.',
Ha='Hailin:BAABNQAECn8yAAMCAAoKrBd3VgCTAgACAAoKrBd3VgCTAgAQAAEKAABzXAAAAAAAAA==.Haunter:BAAANQAECgUIDQAAAA==.',
He='Heherawr:BAAANQADCgIIAgABNQADCgMIBgAFAAAAAA==.',
Hi='Highmico:BAAANQAECgMIAwABNQAECgoKJQAOAN8dAA==.Hima:BAAANQAECgUICwAAAA==.',
Ho='Holyjenkins:BAAANQAECgQIBAAAAA==.Horngrry:BAAANQAECgYIEQAAAA==.',
Hu='Huntingpants:BAAANQAECgQIBAAAAA==.',
Ic='Icianri:BAAANQAECgIIAgAAAA==.',
Il='Illtrytoheal:BAAANQADCgYICgAAAA==.',
Im='Imkillho:BAAANQAECgQJBAABNQAECgYIEQAFAAAAAA==.',
In='Inosuke:BAAANQADCgQIBAAAAA==.Inspiredbox:BAAANQAECgMIBAAAAA==.',
Is='Issyo:BAAANQAECggIAwAAAA==.',
Iz='Izel:BAAANQAECggIAQAAAA==.',
Ja='Jankismith:BAABNQAECn8cAAIVAAYKJA3GGgDfAAAVAAYKJA3GGgDfAAAAAA==.Jayy:BAABNQAECn8aAAIWAAYKCQ14BgA8AQAWAAYKCQ14BgA8AQAAAA==.',
Jf='Jflyer:BAAANQADCgIIAgABNQAFFAQICwAEADgSAA==.',
Ji='Jimin:BAABNQAECn8VAAIDAAcKugozmQBIAQADAAcKugozmQBIAQAAAA==.Jitoflight:BAAANQADCgEIAQAAAA==.',
Jm='Jmajk:BAAANQABCgcICAAAAA==.',
Ju='Jugger:BAAANQADCgcICQAAAA==.',
Ka='Kachiko:BAAANQADCgYICQAAAA==.Kaethis:BAAANQABCgUJBQAAAA==.Kaia:BAAANQAECgYIEQAAAA==.Kamchan:BAAANQAECgQIBwABNQAFFAYIDAAOACMJAA==.Kamerth:BAABNQAECn8aAAQXAAYKMA0WKQDAAAAXAAUKEwgWKQDAAAAOAAUKuwInzwC3AAAYAAIKAgjxIQBWAAAAAA==.Kapbam:BAAANQADCggICgAAAA==.Karluron:BAABNQAECn8YAAIXAAgKNxA3HAAqAQAXAAgKNxA3HAAqAQAAAA==.Karlutros:BAABNQAECn8fAAIXAAkKKRTkJwDrAQAXAAkKKRTkJwDrAQAAAA==.Katbaka:BAAANQAECgEIAQABNQAFFAYIFQAZAD8hAA==.Katmoreahh:BAAANQADCgcIBwABNQAFFAYIFQAZAD8hAA==.Katuwuagain:BAACNQAFFH8VAAIZAAYKPyH0BABdAQAZAAYKPyH0BABdAQA1AAQKfzcAAhkACQrZJe8IAHIDABkACQrZJe8IAHIDAAAA.Kayonalani:BAAANQAECgEIAgAAAA==.Kazure:BAABNQAECn8rAAIaAAoKowmsDQCeAQAaAAoKowmsDQCeAQAAAA==.',
Ke='Kelilia:BAABNQAECn8xAAIIAAoKyRAmcgA+AgAIAAoKyRAmcgA+AgAAAA==.Kenilar:BAAANQAECgUICgAAAA==.Keybricker:BAAANQADCgMIAwABNQAECgMIBAAFAAAAAA==.',
Ko='Konga:BAAANQAECgQIEgAAAA==.Korngry:BAAANQADCgUIBgABNQAECgYIEQAFAAAAAA==.',
Kr='Krakkin:BAAANQAECgEIAQAAAA==.Krenil:BAAANQADCgQIEQAAAA==.',
Ku='Kuassei:BAABNQAECn8gAAIMAAkK4B72DABiAgAMAAkK4B72DABiAgAAAA==.',
Ky='Kyatto:BAAANQAECgcIDwABNQAFFAYIFQAZAD8hAA==.Kyllea:BAAANQAECgUICQAAAA==.',
La='Laaksy:BAAANQAECgUICQABNQAECgkJHwARAG4aAA==.Ladraina:BAAANQADCgcIBwAAAA==.Landock:BAAANQADCgYIHQAAAA==.Lanien:BAAANQADCgUIBQAAAA==.Larynnoelle:BAABNQAECn8bAAIbAAkKQgz1fwCaAQAbAAkKQgz1fwCaAQAAAA==.',
Le='Lebronjames:BAAANQAECggIDgABNQAFFAQIDAALABEXAA==.Leotart:BAABNQAECn80AAIMAAoK2ROZDQBVAgAMAAoK2ROZDQBVAgAAAA==.Lesbians:BAAANQAECgUICwAAAA==.Leyland:BAAANQADCgcIGwAAAA==.',
Li='Lilsus:BAAANQADCggICAABNQAECgQIBAAFAAAAAA==.Linaraline:BAAANQADCgQIBAAAAA==.Linni:BAABNQAECn8hAAIMAAgKyAm1PQA2AQAMAAgKyAm1PQA2AQAAAA==.Lizawizah:BAAANQAECgQIBAAAAA==.',
Lo='Lortnok:BAAANQAECgIIAwAAAA==.Lotharlock:BAAANQADCgQIBAAAAA==.Lotharpally:BAAANQAECgUIBwAAAA==.Lotharshammy:BAAANQAECgYIBwAAAA==.',
Lu='Lukadoncic:BAACNQAFFH8MAAMLAAQKERcQCADtAAALAAQKERcQCADtAAAZAAIKCxdGIACHAAA1AAQKfzcABAsACgqHHhAbALICAAsACgqHHhAbALICAAYABgpbGBl0AEcBABkAAwqcGCqKANcAAAAA.Luminescent:BAAANQADCgMIAwAAAA==.Lunila:BAAANQADCgEIAQABNQAECgQIBgAFAAAAAA==.',
['Lö']='Lögäñ:BAABNQAECn8XAAMQAAkK7hC9GAA5AQAQAAkK7hC9GAA5AQACAAQKiwXhdwFkAAAAAA==.',
Ma='Maeby:BAAANQAECgUIBQABNQAECgkJIgAOAOwaAA==.Magepants:BAAANQAECgMIAwAAAA==.Magnessa:BAAANQAECgYIDgAAAA==.Malekai:BAAANQADCgYICAAAAA==.Malovious:BAAANQAECgEIAwAAAA==.Mano:BAAANQAECgcIDwAAAA==.Marist:BAABNQAECn8YAAIEAAkKCQvgewCvAQAEAAkKCQvgewCvAQAAAA==.Marshabrady:BAAANQAECgEIAQAAAA==.Marwowi:BAAANQADCgIIAgAAAA==.',
Me='Memelord:BAAANQADCgQIBAAAAA==.Menadare:BAAANQAECgUICgAAAA==.Metaslave:BAAANQAECgUIDAABNQAECgoKLAACAIIfAA==.Meteion:BAAANQAECgEIAQAAAA==.',
Mi='Mianceden:BAABNQAECn8cAAIcAAYKuxg1FgDmAAAcAAYKuxg1FgDmAAAAAA==.Miansbane:BAAANQAECgQIBwAAAA==.Micahscream:BAAANQAECgIIAgAAAA==.Midheaven:BAAANQAECgUICgAAAA==.Miku:BAAANQADCgcIDwABNQAECgoKMgACAKwXAA==.Milent:BAAANQAECgYIEQAAAA==.Mimix:BAAANQABCgIIAgAAAA==.Miquiztli:BAAANQAECggIBAAAAA==.Mizoci:BAAANQAECgUICwAAAA==.',
Mo='Mongoose:BAABNQAECn8fAAIRAAkKbhqZJAAEAwARAAkKbhqZJAAEAwAAAA==.Monkeyk:BAAANQADCgMIAwAAAA==.',
Ms='Msspelled:BAAANQAECgYIEgAAAA==.',
Mu='Muichiro:BAAANQADCgQIBAAAAA==.Murcielago:BAAANQADCgIIAgAAAA==.',
Mv='Mvpiam:BAAANQAECgYIBwAAAA==.Mvpsevoker:BAAANQADCgcICQAAAA==.Mvpspally:BAAANQADCgEIAQAAAA==.',
Mx='Mximus:BAAANQADCgMIAwABNQAECgYIDAAFAAAAAA==.',
My='Mystí:BAABNQAECn8aAAIJAAoKRhfggQB7AgAJAAoKRhfggQB7AgAAAA==.',
['Má']='Májorpáin:BAAANQAECgcICwABNQAECgoKIgATAH8TAA==.',
Na='Nabstarr:BAABNQAECn8iAAIOAAkKLBqhHQBzAgAOAAkKLBqhHQBzAgAAAA==.Namaiki:BAAANQADCgUICQAAAA==.Nasroth:BAAANQAECgYIDQAAAA==.Nasstina:BAAANQAECgEIAQABNQAECggIDQAFAAAAAA==.Natureterror:BAAANQAECgEIAQAAAA==.Naví:BAAANQADCgIIAgAAAA==.',
Ni='Nicefella:BAAANQAECgEIAQAAAA==.Niibyter:BAABNQAECn8YAAIcAAYKsxwyDQBkAQAcAAYKsxwyDQBkAQAAAA==.Nitrolan:BAAANQADCgUIBQAAAA==.',
No='Nodiddles:BAAANQADCgYIBgAAAA==.',
Ob='Oberon:BAAANQAECgEIAQAAAA==.',
Oc='Oceanbreeze:BAAANQADCgcIBwAAAA==.',
Oj='Ojasam:BAAANQAECgEIBgAAAA==.',
On='Onlylocks:BAAANQAECgYIDQAAAA==.',
Or='Oralia:BAAANQADCgQIBAAAAA==.Orlisman:BAABNQAECn8XAAMDAAoKMRalOgB0AgADAAoKMRalOgB0AgAEAAEKXgIRzwAoAAAAAA==.',
Pa='Palobo:BAAANQAECgEIAQAAAA==.Pandamunx:BAAANQADCgEJAQAAAA==.',
Ph='Phaka:BAABNQAECn8lAAIGAAgKTBhATADkAQAGAAgKTBhATADkAQAAAA==.Phelanx:BAAANQAECgMIAwAAAA==.Philanthropy:BAABNQAECn8sAAMaAAgK2h+hDADbAgAaAAgK2h+hDADbAgAPAAEKRw6+GwA/AAAAAA==.Philsoom:BAAANQAECgUIBQAAAA==.',
Pi='Pizzeroloko:BAABNQAECn8qAAIHAAoKFRvaBgD7AgAHAAoKFRvaBgD7AgAAAA==.',
Pl='Placebo:BAABNQAECn8iAAIOAAkK7BqZKwC6AgAOAAkK7BqZKwC6AgAAAA==.Playforever:BAAANQADCgQIBwAAAA==.Pläze:BAAANQAECgIIAwAAAA==.',
Pr='Prahd:BAAANQAECgcIEwAAAA==.',
Pu='Purrsephonie:BAABNQAECn8bAAIRAAYKWgQLuwC6AAARAAYKWgQLuwC6AAAAAA==.',
Pw='Pweist:BAAANQADCggIFwABNQAECgMIBAAFAAAAAA==.',
Py='Pyronorish:BAAANQAECgQIBAAAAA==.Pytthia:BAABNQAECn8cAAMXAAcK8Q2yMwCFAQAXAAcK8Q2yMwCFAQAYAAUKLg0+EgADAQAAAA==.',
Ra='Raptalia:BAAANQAECgEIAQABNQAECgoKMgACAKwXAA==.Rayquaza:BAAANQADCgIIAgABNQAFFAgIGwAMAAITAA==.Raziel:BAAANQAECgMIBQAAAA==.',
Re='Reldruin:BAAANQADCgUICAAAAA==.Rexi:BAAANQADCgQICAAAAA==.',
Rh='Rhaena:BAAANQAECgIIAgAAAA==.Rhombus:BAABNQAECn8aAAIbAAYKagzbXAArAQAbAAYKagzbXAArAQAAAA==.',
Ri='Rickjamesbia:BAAANQAECgEIAQAAAA==.Riorson:BAABNQAECn8gAAIZAAoKgQ//SwDGAQAZAAoKgQ//SwDGAQAAAA==.Rizhir:BAAANQADCgUIFgAAAA==.',
Ro='Ronkey:BAAANQAECgIIAgAAAA==.Ronkzar:BAAANQADCgUICAAAAA==.',
['Rô']='Rôflstômp:BAAANQAECgYIBgAAAA==.',
Sa='Sacklord:BAAANQAECgEIAQAAAA==.Sakai:BAAANQADCggICAAAAA==.Salanis:BAAANQAECgIIAgABNQAECggIIwAbAJQkAA==.Saltydog:BAAANQADCgQIGAAAAA==.Sammy:BAAANQAECgEIAQAAAA==.',
Sc='Scurge:BAAANQAECgYIDAAAAA==.',
Se='Sebasmatute:BAAANQAECgcIBwAAAA==.Seizo:BAAANQAECgQIBwAAAA==.Serazen:BAABNQAECn8UAAMdAAgKDgsDCgDuAAAdAAgKhQoDCgDuAAAPAAMKHwUDFQCGAAAAAA==.Setal:BAAANQAECgEIAQAAAA==.',
Sh='Shallteàr:BAAANQAECgQIBwAAAA==.Shammysathh:BAAANQAECgIIAwAAAA==.Shamurloc:BAAANQADCgEIAQAAAA==.Sheenatonic:BAAANQADCgYIDAABNQAECgkJGwAbAEIMAA==.Sheenzilla:BAAANQADCgYIDAABNQAECgkJGwAbAEIMAA==.Shiftr:BAAANQAECgcICQABNQAECgoKFgAKAHoPAA==.Shockaholix:BAAANQADCgUIBQABNQAECgYIDAAFAAAAAA==.Shoinked:BAAANQAECgUIEQAAAA==.Shoveldin:BAAANQAECgQIBAAAAA==.',
Si='Sices:BAAANQADCgQIBAAAAA==.Silentpaw:BAABNQAECn8jAAIeAAYKPiE5CABkAQAeAAYKPiE5CABkAQABNQAECgoKIgATAH8TAA==.',
Sm='Smallblades:BAAANQADCgUIBQAAAA==.Smallêntropy:BAAANQAECgYIEgAAAA==.Smelt:BAAANQADCgYICAAAAA==.Smuurfdk:BAEANQAECgEIAQABNQAECgcIEAAFAAAAAA==.Smuurfhands:BAEANQAECgcIEAAAAA==.',
So='Sogekin:BAAANQADCgIIAgAAAA==.',
Sp='Spriggy:BAAANQAECgQIEgAAAA==.',
St='Stabbytrout:BAABNQAECn8fAAIfAAkKKCNICABSAwAfAAkKKCNICABSAwAAAA==.Stabyotoe:BAAANQADCgUIBQAAAA==.',
Su='Sugar:BAAANQADCggICAAAAA==.Sunetra:BAABNQAECn8cAAICAAkKPgxYeABhAQACAAkKPgxYeABhAQAAAA==.Sushi:BAAANQADCgcIDwAAAA==.',
['Sà']='Sàlanis:BAAANQADCgMIAwABNQAECggIIwAbAJQkAA==.',
['Sã']='Sãlanis:BAAANQAECgIIBAABNQAECggIIwAbAJQkAA==.',
['Sä']='Sälanis:BAABNQAECn8jAAMbAAgKlCTaCQArAwAbAAgKlCTaCQArAwACAAEKAADFuQErAAAAAA==.Säpättäck:BAAANQAECgYIBgAAAA==.',
Ta='Taal:BAAANQADCgQIBAABNQAECgoKLAASAL4cAA==.Taehyung:BAAANQAECgcIDgAAAA==.Taintcleaver:BAAANQAECgEIAQAAAA==.Tainthel:BAAANQADCgUIBQAAAA==.Tairyn:BAABNQAECn8xAAMIAAoKdyGeIAA1AwAIAAoKdyGeIAA1AwAcAAIKZxafNwB0AAAAAA==.Taloki:BAAANQAECgIIBAAAAA==.Tatsuhisa:BAAANQADCgYIEAAAAA==.',
Te='Telavore:BAAANQAECgEIAwAAAA==.Telle:BAAANQAECgQIBwAAAA==.Terciodk:BAAANQAECgQICAAAAA==.Terregoat:BAAANQADCgUIBQAAAA==.',
Th='Thrallmarr:BAAANQADCgIIAgAAAA==.Thruder:BAAANQADCgQIBgAAAA==.',
Ti='Titfortat:BAAANQADCgYICwAAAA==.',
To='Tomaktoma:BAAANQADCgUIBgAAAA==.Tophdh:BAAANQAECgUIBgAAAA==.Totemicblank:BAAANQAECgIIAgAAAA==.',
Tr='Traydle:BAAANQAECggIEAAAAA==.Trondur:BAABNQAECn8aAAIIAAkKLx8JUACZAgAIAAkKLx8JUACZAgAAAA==.Trydel:BAAANQADCgcIEQABNQAECggIEAAFAAAAAA==.Trygon:BAAANQADCgYIBgABNQAECggIEAAFAAAAAA==.',
Ts='Tseris:BAAANQAECgEIAQAAAA==.',
Tu='Tuffnnice:BAAANQAECgEIBAAAAA==.Tuini:BAAANQADCgcIFQAAAA==.',
Ty='Tydis:BAAANQADCgYIGgAAAA==.',
['Tá']='Tálonstorm:BAABNQAECn8hAAIIAAYKQQIN1gBlAAAIAAYKQQIN1gBlAAAAAA==.',
Ul='Ultra:BAAANQAECgEIAgAAAA==.',
Va='Valynaria:BAAANQAECgMICgAAAA==.Vani:BAAANQAECgYIDgAAAA==.',
Ve='Vendetta:BAAANQAECgYIBgABNQAECgYIDAAFAAAAAA==.',
Vi='Victim:BAAANQABCgIIAgAAAA==.Vilthrax:BAAANQAECgIIBQAAAA==.',
Vu='Vulcanus:BAAANQAECgEIAQAAAA==.',
['Vè']='Vèngeance:BAAANQAECgUIBQAAAA==.',
Wa='Warchiéf:BAAANQAECgYIEgAAAA==.Warent:BAAANQABCgIIAgAAAA==.',
Wh='Whalaski:BAABNQAECn83AAIRAAoK0xm7KQA6AgARAAoK0xm7KQA6AgAAAA==.Whistledown:BAAANQADCgcIBwAAAA==.',
Wi='Wickedsin:BAAANQADCgYIFgAAAA==.Wickedstorm:BAAANQADCggIFAAAAA==.Wingstop:BAAANQADCgIIAgABNQAECgYIDwAFAAAAAA==.',
Wo='Woggieboggie:BAAANQAECggIAgAAAA==.',
Wr='Wreckitman:BAACNQAFFH8JAAMMAAQKtwa5CQCtAAAMAAQKtwa5CQCtAAANAAIK5wAFGwAvAAA1AAQKfykAAwwACQp3GjwSAL4CAAwACQp3GjwSAL4CAA0ABwrUBNBmADEBAAAA.',
Xa='Xaalath:BAABNQAECn8gAAMgAAgKLgziDQArAQAgAAgKLgziDQArAQAJAAEKAACL5AEhAAAAAA==.',
['Xé']='Xéno:BAABNQAECn8rAAIaAAkKJxFdEABmAQAaAAkKJxFdEABmAQAAAA==.',
Yo='Yobaz:BAAANQADCgYIFwAAAA==.Yohanan:BAAANQAECgEIAgAAAA==.Yozomi:BAAANQADCgYIIQAAAA==.',
Za='Zappya:BAAANQAECgEIAgAAAA==.Zarorisk:BAAANQAECgUIBgABNQAFFAYICgAHAKEQAA==.',
Ze='Zedd:BAABNQAECn8cAAIMAAkKYA4gNQByAQAMAAkKYA4gNQByAQABNQADCgcIFQAFAAAAAA==.Zewse:BAAANQAECgUIBgAAAA==.',
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
