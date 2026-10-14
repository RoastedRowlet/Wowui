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

local lookup = {'DemonHunter-Vengeance','DemonHunter-Havoc','Mage-Arcane','Mage-Frost','Priest-Holy','Unknown-Unknown','Evoker-Preservation','Paladin-Holy','Warrior-Arms','DeathKnight-Blood','Druid-Balance','Rogue-Assassination','Shaman-Restoration','Warrior-Protection','Warrior-Fury','Monk-Brewmaster','Warlock-Destruction','Shaman-Enhancement','Warlock-Demonology','Druid-Feral','Paladin-Retribution','Hunter-Marksmanship','DeathKnight-Frost','Rogue-Subtlety','DeathKnight-Unholy','Shaman-Elemental','Priest-Shadow','Druid-Restoration','Priest-Discipline','DemonHunter-Devourer','Hunter-BeastMastery','Monk-Mistweaver','Druid-Guardian','Evoker-Devastation','Monk-Windwalker','Warlock-Affliction','Hunter-Survival','Paladin-Protection',}
local provider = {region='US',realm='Nordrassil',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aairidari:BAABNQAECn8eAAMBAAcKOAl5GwD+AAACAAcKKQfNUwA8AQABAAYK4Ql5GwD+AAAAAA==.',
Ab='Abruna:BAAANQAECgcIEQABNQAFFAUIEQADAKwTAA==.Abruno:BAACNQAFFH8RAAIDAAUKrBOkGwCbAQADAAUKrBOkGwCbAQA1AAQKfygAAwMACQpPIqw/AAYDAAMACQo8Iaw/AAYDAAQAAQpaHQAAAAAAAAAA.Abruto:BAAANQAECgYICgABNQAFFAUIEQADAKwTAA==.',
Ae='Aeown:BAAANQAECgMIBgABNQAECgkJNgAFAK8RAA==.Aerdis:BAAANQADCggIFQABNQAECgYIDQAGAAAAAA==.',
Ah='Aharuka:BAAANQADCgEIAQAAAA==.',
Ak='Akukho:BAAANQADCgIIAgAAAA==.',
Al='Alandrìas:BAABNQAECn8hAAIBAAgKpgjYFgA8AQABAAgKpgjYFgA8AQAAAA==.Altera:BAABNQAECn8hAAIHAAgKwxDIIADKAQAHAAgKwxDIIADKAQAAAA==.',
Am='Amuri:BAAANQAECgQIBAAAAA==.',
An='Andelarenn:BAAANQABCgIIAgAAAA==.Andere:BAAANQAECgYIBwAAAA==.Androo:BAAANQAECgcIDQABNQAFFAUIEQAIAEoXAA==.Androonatorz:BAACNQAFFH8RAAIIAAUKShczCgC1AQAIAAUKShczCgC1AQA1AAQKfyUAAggACQoPIikbAAcDAAgACQoPIikbAAcDAAAA.Anfernay:BAABNQAECn8gAAIJAAkKExJTeQAoAgAJAAkKExJTeQAoAgAAAA==.Antheion:BAAANQADCggICAABNQAECgYIGwAKAIwTAA==.Antiaxxis:BAAANQADCgEIAQAAAA==.',
Ap='Apawthetic:BAAANQAECgcIEQABNQAFFAUIEAALAJQYAA==.',
Aq='Aquadab:BAAANQADCgQICAAAAA==.',
Ar='Arcanodare:BAAANQADCggICAAAAA==.Arkalis:BAAANQADCgYIBgAAAA==.Arveiturace:BAAANQAECgMIBgAAAA==.',
As='Ashborrn:BAAANQADCgUIBQAAAA==.Ashtar:BAABNQAECn8mAAIJAAgKnxBwjQD2AQAJAAgKnxBwjQD2AQAAAA==.Asukajo:BAAANQADCgMIAwAAAA==.',
At='Attack:BAAANQAECgYICgAAAA==.',
Ax='Axhure:BAAANQABCgMIAgAAAA==.',
Ba='Babydoll:BAAANQAECgQICAAAAA==.Bajablast:BAAANQADCgcIDQAAAA==.Barma:BAAANQAECgYICQAAAA==.Barrin:BAAANQAECgYICgAAAA==.',
Be='Bearlyseen:BAABNQAECn8XAAIMAAgKlRmlIwBmAgAMAAgKlRmlIwBmAgABNQAFFAUIDAANACgMAA==.Beltirra:BAAANQAECgIIAgAAAA==.',
Bh='Bhangbros:BAAANQADCgcIBwAAAA==.',
Bi='Biggums:BAAANQAECgMIAwAAAA==.Bigmobility:BAABNQAECn8pAAIKAAkKpiL0BwB8AwAKAAkKpiL0BwB8AwAAAA==.Bigwill:BAABNQAECn8vAAIEAAkKiR/VAgAtAwAEAAkKiR/VAgAtAwAAAA==.',
Bl='Blargy:BAABNQAECn8wAAILAAkKOxhSJACrAgALAAkKOxhSJACrAgAAAA==.Bleach:BAAANQAECgUICQAAAA==.',
Bo='Borealslam:BAAANQADCgQIBAAAAA==.Bouzol:BAAANQAECgYIBgAAAA==.',
Br='Brighterbonk:BAAANQAECgIIAgAAAA==.Brimara:BAAANQAECgUIDAAAAA==.Brothaagamor:BAAANQADCgIIAgAAAA==.',
Bu='Bucketojoy:BAAANQAECgcIEgAAAA==.',
['Bà']='Bàtman:BAAANQAECgQIBwAAAA==.',
Ca='Caliburne:BAABNQAECn8vAAQJAAkKeB2APQDQAgAJAAkKXxyAPQDQAgAOAAUKhh9xFgC/AQAPAAMK6h78GAAPAQAAAA==.Captamerica:BAAANQABCgQIBgAAAA==.Capz:BAACNQAFFH8WAAIJAAcKKh+CBACIAgAJAAcKKh+CBACIAgA1AAQKfyIAAgkACQpMJlsfADkDAAkACQpMJlsfADkDAAAA.',
Ce='Cedrin:BAAANQADCggIHQAAAA==.Ceez:BAAANQAECgYIDAAAAA==.Ceezinator:BAAANQADCgQIBAAAAA==.',
Ch='Chichujongar:BAAANQAECgcIDgABNQAFFAUIEAAQAH8LAA==.Chickenstwip:BAAANQADCgEIAgABNQAECgkJJgADABEcAA==.Chopperr:BAAANQAECgMIAwABNQAECgkJJgADABEcAA==.Chosenöne:BAAANQADCgEIAQAAAA==.Chèn:BAAANQAECgcIEgAAAA==.',
Ci='Cindrella:BAABNQAECn8tAAIEAAkKCSWVAADDAwAEAAkKCSWVAADDAwAAAA==.',
Cl='Clayre:BAACNQAFFH8LAAIRAAUKRBGHAACkAQARAAUKRBGHAACkAQA1AAQKfz0AAhEACQpII7gAALMDABEACQpII7gAALMDAAAA.Clow:BAAANQAECgUICwAAAA==.',
Co='Colossus:BAAANQAECgEIAgAAAA==.Coolcrush:BAAANQADCgMIBgABNQAECggIIwASAIwkAA==.Corven:BAACNQAFFH8QAAITAAUKmxbCDQCcAQATAAUKmxbCDQCcAQA1AAQKfzsAAxMACQoeI1ULAHADABMACQoeI1ULAHADABEAAQpFBQqEACUAAAAA.',
Cr='Craziks:BAAANQADCgIIAgAAAA==.Critzwar:BAACNQAFFH8OAAIJAAUK6xVnEACuAQAJAAUK6xVnEACuAQA1AAQKfx8AAgkACQqlIYowAPoCAAkACQqlIYowAPoCAAAA.Crönus:BAAANQADCggIEwAAAA==.',
Ct='Cthuluwu:BAAANQADCggICAAAAA==.',
Da='Daedyxes:BAABNQAECn8bAAIKAAcKygyxYgBkAQAKAAcKygyxYgBkAQAAAA==.Daní:BAAANQADCgUIBwABNQAECgEIAQAGAAAAAA==.Darfur:BAAANQAECggIBAAAAA==.Darkensi:BAAANQABCgYICQAAAA==.Dasherdeez:BAAANQADCgQJBwAAAA==.Daygath:BAAANQAECgEJAQAAAA==.',
De='Deadlyiris:BAABNQAECn8qAAIJAAkKYh1HOQDdAgAJAAkKYh1HOQDdAgABNQAFFAEIAQAGAAAAAA==.Deadshot:BAAANQAECgQIBwAAAA==.Deatharin:BAAANQADCgUIBgAAAA==.Deathjak:BAAANQAECgcICAABNQAECgkJHgADAPEgAA==.Demonbulio:BAAANQAECgcIDwAAAA==.Demonisthicc:BAABNQAECn8uAAIUAAkKARx3BgABAwAUAAkKARx3BgABAwAAAA==.Demonslayeer:BAAANQADCggIDQAAAA==.Devi:BAAANQAECgUICwAAAA==.',
Di='Diaravynn:BAAANQADCgMIBQAAAA==.Dithehealer:BAABNQAECn8iAAIVAAgKKxWOjwABAgAVAAgKKxWOjwABAgAAAA==.Divain:BAAANQADCgQIBgAAAA==.',
Dk='Dkdi:BAAANQADCggIFwAAAA==.',
Do='Dozekar:BAAANQAECgEIAQAAAA==.',
Dr='Drenamai:BAAANQAECgQICQAAAA==.Drexywexyuwu:BAAANQADCgcJBwAAAA==.',
Du='Duhmptruhk:BAABNQAECn8aAAIJAAgKExZhfgAbAgAJAAgKExZhfgAbAgAAAA==.Dunbroch:BAACNQAFFH8SAAIWAAYKZhqIBwDQAQAWAAYKZhqIBwDQAQA1AAQKfykAAhYACQozHiIVALMCABYACQozHiIVALMCAAAA.Duskforge:BAAANQABCgIJAgAAAA==.',
Dw='Dwagen:BAAANQAECgQIBAAAAA==.',
['Dé']='Démonicblood:BAACNQAFFH8JAAIXAAUKoxx4BgCTAQAXAAUKoxx4BgCTAQA1AAQKfyIAAhcACQqjGv4gAIECABcACQqjGv4gAIECAAAA.',
Eg='Eggplantgodx:BAABNQAECn8qAAMBAAkK/iJjAwAsAwABAAgK/iJjAwAsAwACAAgKKRm0LgAsAgAAAA==.',
Ek='Ekhart:BAAANQAECgEIAQAAAA==.',
El='Elfajah:BAAANQADCgYICQAAAA==.Eliicia:BAACNQAFFH8PAAIMAAUKXw9DCACGAQAMAAUKXw9DCACGAQA1AAQKfycAAwwACQrpHEYYALYCAAwACQrpHEYYALYCABgACAqwDe0xACgBAAAA.',
Em='Emmy:BAAANQAECgQIDwAAAA==.Emofineshyt:BAAANQADCgcICgAAAA==.Emogothbabe:BAABNQAECn8mAAMDAAkKERy6ZAC1AgADAAkKERy6ZAC1AgAEAAMK8w7SKwCZAAAAAA==.Emowrecky:BAABNQAECn8cAAMTAAcKZBs2YQAxAgATAAcKZBs2YQAxAgARAAEKYwz6dgA2AAAAAA==.',
En='Endo:BAACNQAFFH8NAAMZAAUKthWKCgBlAQAZAAQKaBuKCgBlAQAXAAMKhQ+iEADMAAA1AAQKfzIAAxkACQpRJRwSACUDABkACAq1JRwSACUDABcABwrlIC8sADcCAAAA.Endorush:BAABNQAECn8dAAICAAgKhx/5GADQAgACAAgKhx/5GADQAgABNQAFFAUIDQAZALYVAA==.Endrigosa:BAAANQAECgUIBgAAAA==.Eneldenes:BAAANQAECgUICwAAAA==.Enjoyer:BAAANQAECgcIDgAAAA==.',
Er='Ereitherla:BAAANQAECgUIEgAAAA==.',
Es='Esmenet:BAAANQAECgYIEAAAAA==.Espressð:BAAANQAECgcIEQABNQAECgkJJgADABEcAA==.',
Ex='Excalibear:BAAANQAECgYIDwABNQAFFAUIDAANACgMAA==.',
Ey='Eydis:BAAANQADCgcIDgAAAA==.',
Fe='Feironor:BAAANQAECgMIAwAAAA==.Fenrys:BAAANQAECgEIAQAAAA==.',
Fi='Fikareous:BAAANQADCggIDQABNQAECgUIBQAGAAAAAA==.',
Fl='Flayre:BAABNQAECn8kAAMNAAgK8RxzRABMAgANAAcKFx1zRABMAgAaAAcK1Ba5ZgDpAQAAAA==.Fleredil:BAABNQAECn8mAAMbAAgKTCBhEADvAgAbAAgKTCBhEADvAgAFAAEKgQUr+wAuAAAAAA==.Flingernle:BAABNQAECn8bAAIaAAgKSSH9IwD0AgAaAAgKSSH9IwD0AgAAAA==.',
Fo='Forepray:BAACNQAFFH8OAAIbAAQKExFSCwAzAQAbAAQKExFSCwAzAQA1AAQKfzEAAhsACQqaIH0JAEUDABsACQqaIH0JAEUDAAAA.Forger:BAABNQAECn8iAAMOAAgKjAzFGgCHAQAOAAgKjAzFGgCHAQAJAAIKQQjqNQFhAAAAAA==.Forsakey:BAAANQADCggIFAABNQAFFAYIDQAcAIQYAA==.',
Fr='Fraun:BAAANQADCggJEQAAAA==.Freshdk:BAAANQAECgQIBAAAAA==.',
Fu='Fullyprotpal:BAAANQAECgEIAQAAAA==.Furioustotem:BAAANQAECgUIEgAAAA==.Future:BAAANQADCgUIBgABNQAECgkJLAADAMQjAA==.',
Ga='Galten:BAAANQADCgUIBQAAAA==.Gantz:BAAANQADCgIJAgAAAA==.',
Ge='Geekbarr:BAAANQADCgUIBQABNQAECgkJJgADABEcAA==.',
Gh='Ghettox:BAAANQADCgYICAAAAA==.Ghostw:BAAANQAECgUIDAAAAA==.',
Gi='Giovanni:BAAANQAECggICAAAAA==.Gizik:BAAANQADCgcICwABNQAFFAcIFwAbABESAA==.',
Gn='Gnasher:BAAANQABCgQIBAAAAA==.',
Go='Golgotterath:BAACNQAFFH8MAAINAAUKKAynDgBeAQANAAUKKAynDgBeAQA1AAQKfzAAAw0ACQpyHFtHAEECAA0ACQpyHFtHAEECABoAAQqNB5s2ATAAAAAA.Gorm:BAABNQAECn8dAAIDAAkKcRiQVADXAgADAAkKcRiQVADXAgABNQAECgQIBQAGAAAAAA==.',
Gr='Grippyshocks:BAAANQAECgIIAQABNQAECgkJIAACAGchAA==.',
Ha='Halbruck:BAAANQAECgcIEQAAAA==.Haldane:BAABNQAECn8nAAIVAAgKiwm3zQB6AQAVAAgKiwm3zQB6AQABNQAFFAEIAQAGAAAAAA==.Harrydottur:BAAANQAECgcIDQABNQAFFAMIBwATAIgYAA==.Havochunter:BAAANQAECgQIBQAAAA==.',
He='Heidegger:BAAANQADCgYICgAAAA==.Helinndealin:BAACNQAFFH8OAAIdAAUKRCCsAADoAQAdAAUKRCCsAADoAQA1AAQKfysAAx0ACQqwJFABAEcDAB0ACArgJFABAEcDAAUACAotIp9IAEkCAAAA.Hellin:BAAANQADCgMIAQAAAA==.Heolstor:BAABNQAECn8jAAIKAAkKThiPJQCNAgAKAAkKThiPJQCNAgAAAA==.Hephsdh:BAAANQAECgYICQAAAA==.Heraois:BAAANQAECgcIEwAAAA==.Heriod:BAAANQABCgEIAQAAAA==.',
Hg='Hgshake:BAAANQADCgYIBgAAAA==.',
Ho='Holytës:BAAANQADCggIFQAAAA==.Holywráth:BAAANQADCgUIDwAAAA==.',
Hu='Hunterdh:BAAANQAECgYIEAAAAA==.',
Hy='Hynixx:BAABNQAECn8eAAMPAAkKxhkJCQBKAgAPAAgKJRoJCQBKAgAJAAYKsxMevwB6AQABNQAFFAQIDgAbABMRAA==.',
Il='Illidope:BAABNQAECn8gAAQCAAkKZyFzFQDuAgACAAkKQSFzFQDuAgAeAAgK+xy4IgAxAgABAAEKAADiLQBGAAAAAA==.',
In='Infinitevoid:BAAANQADCggIFQAAAA==.Innervatez:BAABNQAFFH8LAAIcAAUKJCMDBADvAQAcAAUKJCMDBADvAQAAAA==.Inteaus:BAAANQADCggIGgAAAA==.',
Io='Ionúin:BAAANQADCgQJBAAAAA==.',
Iv='Ivÿ:BAAANQADCgMIBQAAAA==.',
Ja='Jaekir:BAABNQAECn8hAAIEAAgKERVfCwAIAgAEAAgKERVfCwAIAgAAAA==.Jakfrost:BAABNQAECn8eAAMDAAkK8SB3WwDJAgADAAgKeyB3WwDJAgAEAAMKKiKIGgAcAQAAAA==.Jakie:BAAANQADCgYICgABNQAECggIFwAJAN8aAA==.Jarten:BAACNQAFFH8LAAIXAAUKXxn1BwBvAQAXAAUKXxn1BwBvAQA1AAQKfzEAAhcACQoRIF4QAAoDABcACQoRIF4QAAoDAAAA.Jayaah:BAAANQAECgIIAgAAAA==.Jaylebate:BAAANQAECgQIBwAAAA==.',
Je='Jerrenn:BAAANQAECgQIBAAAAA==.Jesseatamer:BAACNQAFFH8LAAIfAAUKzB/RCwCOAQAfAAUKzB/RCwCOAQA1AAQKfy8AAh8ACQoMJe8HAJ0DAB8ACQoMJe8HAJ0DAAAA.',
Ji='Jitsuru:BAAANQADCgUIBQAAAA==.',
Jo='Jox:BAAANQABCgUIBQAAAA==.Joxor:BAAANQABCgUIBQAAAA==.',
Js='Jstdeath:BAAANQADCgEIAQABNQAECgkJLQAJADUWAA==.Jstrawr:BAABNQAECn8tAAIJAAkKNRZFYQBnAgAJAAkKNRZFYQBnAgAAAA==.Jsttotem:BAAANQAECgUIBQABNQAECgkJLQAJADUWAA==.',
Ka='Kalmek:BAAANQAECgcICQAAAA==.Kaln:BAAANQAECgIIBQABNQAECgQIBQAGAAAAAA==.Karen:BAAANQAECgUIDgAAAA==.Kasalu:BAAANQABCgQIBAAAAA==.Kastia:BAAANQAECgIIAwAAAA==.Katrynwel:BAAANQAECgQIBAAAAA==.Katsumi:BAAANQAECgEIAQAAAA==.',
Ke='Keliki:BAABNQAECn8gAAMaAAgKzhjBQABvAgAaAAgKzhjBQABvAgANAAMKdQ7j7ACLAAAAAA==.Kellenah:BAAANQADCgYICwAAAA==.Kettama:BAAANQADCggIEAABNQAECgkJJgADABEcAA==.',
Kh='Khold:BAABNQAECn8ZAAIXAAgKThxyKQBJAgAXAAgKThxyKQBJAgAAAA==.Khrogann:BAAANQAECggIEQAAAA==.',
Ki='Kijana:BAAANQADCggICAAAAA==.Killalltoday:BAABNQAECn8jAAINAAgK1hFPaADQAQANAAgK1hFPaADQAQAAAA==.Kirkk:BAAANQAECgEIAQAAAA==.',
Kl='Klaminus:BAAANQADCgQJBAABNQAECgIIAgAGAAAAAA==.',
Kn='Knixx:BAACNQAFFH8RAAIFAAUKKhSTDwCVAQAFAAUKKhSTDwCVAQA1AAQKfz8AAwUACQokJt8AAOQDAAUACQokJt8AAOQDAB0ABgrzEXMPADIBAAAA.Knuppelus:BAAANQADCgYIDAAAAA==.',
Ko='Kobyashimaru:BAAANQADCgUIBQAAAA==.Koshi:BAAANQADCgMIAwAAAA==.Kotastrophe:BAAANQAECgMIAwABNQAECggIGgAJABMWAA==.Koveras:BAAANQADCgYIBwAAAA==.Koyaanis:BAAANQADCggIDgAAAA==.Koyya:BAABNQAECn8ZAAMSAAkK5Ar2EwAmAgASAAkK5Ar2EwAmAgANAAcK1xIcfwCKAQAAAA==.',
Kr='Krathos:BAAANQAECgIIAwAAAA==.Krenmonk:BAAANQAECgEIAQAAAA==.Krennic:BAAANQADCgcIBwAAAA==.Krunchee:BAAANQAECgIIAwAAAA==.',
Ku='Kufoo:BAABNQAECn8kAAIPAAgKbySNAgBOAwAPAAgKbySNAgBOAwAAAA==.Kurao:BAAANQAECgMIBQAAAA==.Kurukai:BAAANQADCgMIAwAAAA==.',
Ky='Kyrian:BAACNQAFFH8YAAMYAAYKviJOAQBbAgAYAAYKviJOAQBbAgAMAAMKvRGdDwDrAAA1AAQKfysAAxgACQqgIh0FADkDABgACQqgIh0FADkDAAwAAwpZHGltAPMAAAAA.',
La='Lagøless:BAABNQAECn8fAAIfAAkKZSDIEgBTAwAfAAkKZSDIEgBTAwAAAA==.',
Le='Leo:BAAANQAECgEIAQAAAA==.',
Li='Liatris:BAAANQAECgUIBQAAAA==.Likestoflash:BAEANQADCgYIBgABNQAECgkJLAAfACwfAA==.Lissaris:BAAANQADCgEIAgAAAA==.',
Lo='Lohal:BAABNQAECn8gAAITAAgKlhiMXgA4AgATAAgKlhiMXgA4AgAAAA==.Lohmi:BAAANQAECgUIEAAAAA==.Lormn:BAAANQADCgEIAQAAAA==.',
Lu='Luania:BAAANQAECgIIAwAAAA==.',
Ly='Lyna:BAAANQADCggJDAAAAA==.Lyravega:BAAANQADCggICAAAAA==.Lyshkä:BAABNQAECn8uAAIgAAgK/RsBEAB7AgAgAAgK/RsBEAB7AgAAAA==.Lyzzardkng:BAABNQAECn8YAAIVAAgKTwiGywB+AQAVAAgKTwiGywB+AQAAAA==.',
['Lý']='Lýra:BAAANQAECgQIBwAAAA==.',
Ma='Maango:BAAANQAECggIEAAAAA==.Maemu:BAAANQABCgUIBQAAAA==.Magerthat:BAAANQADCgQIBgAAAA==.Magicaltickl:BAAANQAECgcIEwAAAA==.Magiki:BAAANQADCgcICwAAAA==.Malkala:BAAANQADCgMIAwAAAA==.Malonormu:BAAANQABCgYIBAAAAA==.Mamadeezy:BAAANQADCgYJCwAAAA==.Mando:BAAANQAECgIIAwABNQAECgUIEgAGAAAAAA==.Manical:BAAANQAECgMICAAAAA==.Marcel:BAAANQADCgYIEQABNQAECgIIAgAGAAAAAA==.Martinikiss:BAAANQAECgcIBwAAAA==.Mashiach:BAACNQAFFH8LAAIFAAUKEB1BDADBAQAFAAUKEB1BDADBAQA1AAQKfyUAAwUACQpnI4gPAEgDAAUACQpnI4gPAEgDABsAAQoAACB3ADYAAAAA.Matthyjsz:BAAANQADCgIIAgAAAA==.',
Me='Megumin:BAAANQAECgQIBwABNQAECgkJLQAVAHojAA==.Melikefire:BAABNQAECn8bAAIDAAkK1haklwBQAgADAAkK1haklwBQAgAAAA==.Melodious:BAAANQAECgEIAQAAAA==.Memecompdall:BAAANQAECgIIAgAAAA==.Merek:BAABNQAECn8fAAIQAAgKyB/2BgDSAgAQAAgKyB/2BgDSAgAAAA==.Mettix:BAAANQADCgIIAgAAAA==.',
Mi='Mirigosa:BAAANQAECgEIAQABNQAECgkJLQAEAAklAA==.Mistybdk:BAABNQAECn8WAAIKAAkKdBLeNgAsAgAKAAkKdBLeNgAsAgABNQAFFAcIFgAhAOITAA==.Mistyd:BAACNQAFFH8WAAIhAAcK4hOFAABGAgAhAAcK4hOFAABGAgA1AAQKfzkAAiEACQrbJIEBAMsDACEACQrbJIEBAMsDAAAA.',
Mo='Mogfooyen:BAAANQABCgQIBgAAAA==.Moonbeam:BAAANQAECgIIAgAAAA==.Morgause:BAAANQAECgUIDwAAAA==.Morllan:BAABNQAECn8cAAITAAkKRw5sgADgAQATAAkKRw5sgADgAQAAAA==.',
Mu='Muirdin:BAAANQADCgEJAQAAAA==.',
My='Mykinlive:BAAANQADCgIIAgAAAA==.',
['Må']='Mångix:BAAANQAECgQIBAAAAA==.',
['Mé']='Mélusine:BAABNQAECn8ZAAMJAAkKURLMiAACAgAJAAkKpw/MiAACAgAPAAQKrRAcHQDYAAAAAA==.',
Na='Naanomage:BAAANQAECgIIAgAAAA==.Naija:BAAANQADCgIIAgAAAA==.Narcotx:BAAANQADCgIIAgAAAA==.',
Ne='Necrotoxin:BAAANQADCgYIBgAAAA==.',
Ni='Nightmaratic:BAAANQADCgYIBgAAAA==.Nightsdeath:BAAANQAECgEIAQAAAA==.Nightsever:BAABNQAECn8nAAIeAAkKwSIyBwBeAwAeAAkKwSIyBwBeAwAAAA==.Nirath:BAABNQAECn8jAAIiAAgK6wRhIABOAQAiAAgK6wRhIABOAQAAAA==.',
No='Noiire:BAAANQAECgcICQABNQAFFAUIDwAMAF8PAA==.',
Od='Odysse:BAAANQADCgYICQAAAA==.Odyssé:BAABNQAECn8cAAIfAAkKTR4mIQARAwAfAAkKTR4mIQARAwAAAA==.',
Ok='Okami:BAAANQAECgUIEAAAAA==.',
On='Onehotelf:BAAANQAECgQIBAAAAA==.',
Oo='Ooyagoddess:BAAANQAECgEIAQAAAA==.',
Or='Orienn:BAAANQADCgYIBgAAAA==.',
Pa='Pacamonk:BAABNQAECn8pAAIjAAkKDR/7DAAIAwAjAAkKDR/7DAAIAwAAAA==.Palenar:BAAANQADCgQIBAAAAA==.Papatiny:BAAANQAECgYICgAAAA==.Pawsa:BAAANQAECgUICwABNQAECgkJJgADABEcAA==.Pawthetic:BAACNQAFFH8QAAMLAAUKlBgCEgBEAQALAAQKlBgCEgBEAQAcAAEKVw4fFABNAAA1AAQKfzAAAxwACQoRH2UQANECABwACAo/IGUQANECAAsACQozHvkeANECAAAA.',
Pe='Peelforheals:BAABNQAECn8uAAMbAAkKQh9lDgAHAwAbAAkKQh9lDgAHAwAdAAQKuAtEFwC5AAAAAA==.Penguindemic:BAABNQAECn8fAAMTAAkKnSRhBgCbAwATAAkKnSRhBgCbAwARAAEKoCJ4aQBNAAAAAA==.Pep:BAAANQAECgcIEQAAAA==.Pepperoni:BAAANQADCggIDQAAAA==.Perdator:BAAANQAECgQIBgAAAA==.Petruccius:BAACNQAFFH8OAAILAAMKPg7lFgD0AAALAAMKPg7lFgD0AAA1AAQKf0QAAgsACQo/IDAMAGgDAAsACQo/IDAMAGgDAAAA.Pewpewlepew:BAAANQAECgQICQAAAA==.',
Ph='Phaeku:BAAANQADCgMIAwAAAA==.',
Pi='Picklebreath:BAAANQADCgUICgAAAA==.Pinksparklez:BAAANQADCgUICAABNQAECgEIAQAGAAAAAA==.',
Pl='Plague:BAAANQAECgMIAwAAAA==.',
Po='Poptartsz:BAAANQAECgQICQAAAA==.Potatolockx:BAAANQAECgQIAwAAAA==.',
Pr='Prayre:BAAANQAECgEIAQAAAA==.Precht:BAAANQAECgIIAgAAAA==.Prikarea:BAAANQAECgUIBQAAAA==.Prospa:BAAANQABCgQIBgABNQAECgkJJgADABEcAA==.Prumper:BAABNQAECn8YAAIDAAgKhBKkwwD7AQADAAgKhBKkwwD7AQAAAA==.',
Pu='Purah:BAAANQADCgEIAgAAAA==.',
Qu='Quesoblanco:BAAANQAECgcIEwAAAA==.',
Qy='Qybxboogietk:BAABNQAECn8YAAICAAgK9BXaMAAdAgACAAgK9BXaMAAdAgAAAA==.',
Ra='Rabid:BAAANQAECgQIBwAAAA==.Raeliana:BAAANQADCgQIBAAAAA==.Raghallov:BAAANQAECgMIBgAAAA==.Rampa:BAAANQADCgYIEQABNQAECgkJJgADABEcAA==.',
Re='Reaperan:BAAANQAECgEIAQAAAA==.Regena:BAABNQAECn82AAMFAAkKrxHESwA+AgAFAAkKrxHESwA+AgAbAAMKOQJHaQBYAAAAAA==.Remorse:BAACNQAFFH8RAAIOAAUKXBR7AgBrAQAOAAUKXBR7AgBrAQA1AAQKf0EAAg4ACQoLIk4GAAADAA4ACQoLIk4GAAADAAAA.Rendwick:BAAANQADCgYICQAAAA==.Required:BAAANQAECgcICAABNQAFFAYIEQACANAgAA==.',
Ri='Riker:BAAANQADCgQIBAABNQAECgEIAQAGAAAAAA==.Rim:BAABNQAECn8mAAINAAgKvxx2MwCPAgANAAgKvxx2MwCPAgAAAA==.',
Ro='Ronfar:BAACNQAFFH8NAAISAAUKSBhnAgCtAQASAAUKSBhnAgCtAQA1AAQKf0EAAhIACQr9IrQCAHsDABIACQr9IrQCAHsDAAAA.Rootx:BAAANQAECgMIAwABNQAFFAcIHwALAKUiAA==.',
Ru='Rukidingme:BAAANQADCgEIAQAAAA==.Rustyglass:BAAANQABCgYIBAAAAA==.Ruttisðir:BAAANQAECgIIAwAAAA==.',
Ry='Ryhorn:BAAANQADCggIDgAAAA==.Ryno:BAAANQADCgUIBwAAAA==.Ryujin:BAAANQAECgcIEQAAAA==.Ryù:BAAANQAECgIIAwAAAA==.',
Sa='Salo:BAAANQADCgMIBgAAAA==.Salòme:BAAANQADCgIIAgABNQAECggIHgAfAGUKAA==.Sanazenet:BAAANQADCggJDAAAAA==.Saphiriel:BAAANQAECgMIBQAAAA==.Saviorself:BAAANQADCgMIAwABNQAFFAUIEAALAJQYAA==.',
Sc='Scarscar:BAAANQAECgcICgAAAA==.Schwinn:BAAANQADCgQIBAAAAA==.',
Se='Segarth:BAAANQAECgcIDwAAAA==.Selen:BAAANQAECgcIEQAAAA==.Semballin:BAAANQABCgMJAwAAAA==.Seråphiel:BAAANQAECgEIAQAAAA==.Seswatha:BAAANQAECgUIBQABNQAFFAUIDAANACgMAA==.',
Sh='Shamandroo:BAABNQAECn8YAAINAAkK0BrAJgDHAgANAAkK0BrAJgDHAgABNQAFFAUIEQAIAEoXAA==.Shamdi:BAAANQADCgYIBgAAAA==.Shanghaied:BAAANQADCgcIDAAAAA==.Shawtyy:BAAANQADCgMIAwAAAA==.Shmongus:BAAANQADCgIIAgABNQAECgcIDgAGAAAAAA==.Shortandold:BAAANQAECgcIDQAAAA==.Shådowfire:BAAANQAECgEIAQAAAA==.Shìft:BAABNQAECn8mAAIcAAgKzx1YEwCvAgAcAAgKzx1YEwCvAgAAAA==.',
Si='Sightofhand:BAAANQADCgQIBAAAAA==.Sintram:BAAANQAECgMIAwAAAA==.',
Sl='Slighted:BAAANQAECgMIBgABNQAECgcIDgAGAAAAAA==.Slimydruid:BAAANQAECgQIBgAAAA==.Slow:BAABNQAECn8sAAIDAAkKxCMRHABmAwADAAkKxCMRHABmAwAAAA==.',
Sm='Smokinontech:BAAANQADCgQIBAABNQAECgkJJgADABEcAA==.Smokze:BAAANQADCggJCAAAAA==.',
So='Sockoh:BAAANQAECgcIEwAAAA==.Sonicberger:BAAANQAECgUIBAABNQAECgkJHAAKAE8aAA==.Sonicoberg:BAAANQAECgQIBAABNQAECgkJHAAKAE8aAA==.Soniko:BAAANQAECgcIDgAAAA==.Sonícberger:BAABNQAECn8cAAMKAAkKTxoPIgCiAgAKAAkKiBkPIgCiAgAZAAIKXhslugB0AAAAAA==.Soulcaliber:BAAANQADCgQIBAAAAA==.',
St='Stain:BAAANQAECgQJCAAAAA==.Stealth:BAAANQAECgQIBAABNQAECggIIwAkACUbAA==.Stinkfist:BAAANQADCgcIFgAAAA==.Stonehenge:BAAANQAFFAEIAQAAAA==.Stonepalm:BAAANQADCgcIGwAAAA==.Stratan:BAAANQAECgIIAgAAAA==.Strawk:BAABNQAECn8YAAIaAAcKBQ7mfgCjAQAaAAcKBQ7mfgCjAQAAAA==.',
Su='Subbzero:BAAANQADCgEIAQAAAA==.Suffer:BAAANQADCggICQABNQAECgkJLAADAMQjAA==.Sunlight:BAAANQADCgYIBgAAAA==.Supercat:BAAANQAECgEIAQAAAA==.Surf:BAAANQAECgUICQAAAA==.',
Sw='Swankydranky:BAACNQAFFH8QAAQQAAUKfwvCBQARAQAQAAUKKQbCBQARAQAjAAQKAgrvCgAFAQAgAAEKVgAjDgAlAAA1AAQKfyoABBAACQq1FDcSAL8BABAACAoQEzcSAL8BACMACQosEdQzAHIBACAAAgphBL5HAEYAAAAA.Swankypally:BAAANQAECgcICgABNQAFFAUIEAAQAH8LAA==.',
Sy='Syesc:BAAANQABCgQJBAAAAA==.Sylandris:BAAANQADCgIIAgAAAA==.',
['Sá']='Sásukeuchiha:BAAANQADCgYIEwABNQAECggIHgAfAGUKAA==.',
Ta='Tabbz:BAABNQAECn8hAAIaAAkKjhmzMAC1AgAaAAkKjhmzMAC1AgAAAA==.Tallael:BAABNQAECn8lAAISAAkK0w/qDgB6AgASAAkK0w/qDgB6AgAAAA==.Tallyhochick:BAABNQAECn8kAAIfAAgKPg8JfAASAgAfAAgKPg8JfAASAgAAAA==.Taman:BAABNQAECn8bAAINAAgKNx2bPwBfAgANAAgKNx2bPwBfAgAAAA==.Taylerswift:BAAANQAECgEJAQAAAA==.',
Th='Thebestname:BAAANQAECgcIEwAAAA==.Thebigonion:BAAANQADCggIGgAAAA==.Theexile:BAABNQAECn8kAAMMAAgK4xqOKgA7AgAMAAgKjhiOKgA7AgAYAAYKOhlOIQC/AQAAAA==.Theigh:BAAANQAECgEIAQAAAA==.Thonard:BAAANQAECgUIDAABNQAECgkJMwAXAO4iAA==.',
Ti='Tinydeath:BAABNQAECn8fAAIKAAgKwhVjSQDPAQAKAAgKwhVjSQDPAQAAAA==.Tinyfu:BAAANQADCgQIBAAAAA==.Tinytamer:BAABNQAECn8eAAMfAAgK+Bl7XQBbAgAfAAgKWRl7XQBbAgAlAAMKRRL6DQDMAAABNQAECggIHwAKAMIVAA==.',
Tm='Tmakrist:BAAANQAECgEIAwAAAA==.',
To='Toko:BAACNQAFFH8MAAIfAAUKZBnqCAC1AQAfAAUKZBnqCAC1AQA1AAQKfykAAh8ACQqpI1wdACEDAB8ACQqpI1wdACEDAAAA.Tomblord:BAABNQAECn8VAAMXAAcK6gqpUABoAQAXAAcKwgqpUABoAQAKAAYKuAUahADoAAAAAA==.',
Tr='Trailblazah:BAAANQAECgUICgAAAA==.Treeheals:BAAANQADCggICAAAAA==.Truthes:BAAANQADCgYIBwABNQAECggIIwAkACUbAA==.Truths:BAAANQADCgIJAgABNQAECggIIwAkACUbAA==.Truthsx:BAABNQAECn8jAAMkAAgKJRvvAwCpAgAkAAgKJRvvAwCpAgATAAUKZw6B3wAEAQAAAA==.Truthy:BAAANQADCgYICAABNQAECggIIwAkACUbAA==.Truthz:BAAANQADCgYJBgABNQAECggIIwAkACUbAA==.',
Ts='Tsukúne:BAAANQADCgQIBAAAAA==.',
Ty='Tyg:BAAANQADCggIDAAAAA==.Tylaatape:BAABNQAECn8ZAAQZAAcKHxFifwAbAQAZAAcK5AVifwAbAQAXAAUK0A7hYgAPAQAKAAEKXhr3uwBNAAAAAA==.Tyraell:BAAANQAECggIDwAAAA==.',
['Tõ']='Tõkó:BAAANQADCgUIBQABNQAFFAUIDAAfAGQZAA==.',
Um='Umbrae:BAAANQADCgMIAQAAAA==.Umfray:BAAANQAECgIIAwABNQAECgUICwAGAAAAAA==.',
Us='Usgasdanelv:BAABNQAECn8cAAISAAkKzxmlDACiAgASAAkKzxmlDACiAgAAAA==.',
Uz='Uzala:BAAANQAECgUICwAAAA==.',
Va='Vanleiden:BAAANQADCgEIAQAAAA==.Vazro:BAABNQAECn8sAAMIAAgKzxQFXgD8AQAIAAgKzxQFXgD8AQAVAAYKLQZsEAH9AAAAAA==.',
Ve='Vendiyre:BAAANQAECgYIBgAAAA==.Venthyl:BAACNQAFFH8IAAILAAUK/SDRDACZAQALAAUK/SDRDACZAQA1AAQKfycAAgsACQrVJCMKAHsDAAsACQrVJCMKAHsDAAAA.Veyra:BAAANQABCgMIAwAAAA==.',
Vi='Vizan:BAAANQABCgcIBwABNQAECggIIwAkACUbAA==.',
Wa='Warzone:BAAANQADCgUIBQAAAA==.',
We='Wellby:BAAANQAECgEIAQAAAA==.Westerin:BAABNQAECn8fAAIRAAgKrw64DwAAAgARAAgKrw64DwAAAgAAAA==.',
Wi='Wildnature:BAAANQADCggIDgAAAA==.Wimateeka:BAABNQAECn8jAAQmAAkKuhaMHQD7AQAmAAYKnRuMHQD7AQAVAAgK1hN9lAD2AQAIAAIKggVMDwFSAAAAAA==.Windfury:BAAANQAECgYICAABNQAECgkJLAADAMQjAA==.Windigo:BAAANQAECgIIAgAAAA==.Winginit:BAAANQAECgEIAQABNQAFFAUIEAALAJQYAA==.',
Wo='Wooqles:BAAANQADCgUIBQABNQADCgYICAAGAAAAAA==.',
Wr='Wrastelas:BAAANQADCggICAAAAA==.',
Wu='Wuilhem:BAAANQADCgEIAQAAAA==.Wurkim:BAAANQADCgQIBAABNQADCggICAAGAAAAAA==.',
Xa='Xaala:BAAANQAECgQIBQAAAA==.',
Xo='Xosderdk:BAAANQADCgIIAgAAAA==.',
Ya='Yarjuul:BAAANQAECgIIAgABNQAECgUICwAGAAAAAA==.',
Ye='Yespaladin:BAACNQAFFH8LAAIKAAUK4hTpDQBwAQAKAAUK4hTpDQBwAQA1AAQKfzAAAgoACQquINUOADcDAAoACQquINUOADcDAAAA.',
Yi='Yimity:BAAANQAECgMIAwAAAA==.',
Yo='Yogí:BAACNQAFFH8PAAINAAUKqxTDDAB7AQANAAUKqxTDDAB7AQA1AAQKfywAAg0ACQpfIboOAEsDAA0ACQpfIboOAEsDAAAA.Yozomoto:BAACNQAFFH8QAAIfAAUK5SHkBwDJAQAfAAUK5SHkBwDJAQA1AAQKfy0AAx8ACQp3JEMoAPUCAB8ACQp3JEMoAPUCABYAAgo8D9t0AGMAAAAA.',
Za='Zalandria:BAAANQAECgUIDAAAAA==.',
Ze='Zeltemis:BAABNQAECn8XAAIfAAgKpQiGjQDrAQAfAAgKpQiGjQDrAQAAAA==.',
Zi='Zipsion:BAABNQAECn8oAAIfAAgKviO2FwA6AwAfAAgKviO2FwA6AwAAAA==.Zivver:BAABNQAECn8jAAIOAAkKlSLqAgB6AwAOAAkKlSLqAgB6AwAAAA==.Zizka:BAABNQAECn8cAAIbAAgKlgXFOABcAQAbAAgKlgXFOABcAQAAAA==.',
Zo='Zolandir:BAAANQAECgIIAgAAAA==.',
Zu='Zuljia:BAAANQADCggICAABNQAECgYIGwAcAFkbAA==.',
['Òh']='Òhká:BAAANQADCgMIAwAAAA==.',
['Üt']='Üther:BAABNQAECn8tAAIVAAkKeiNjEACHAwAVAAkKeiNjEACHAwAAAA==.',
['ßu']='ßubbleøseven:BAAANQAECgcIDgAAAA==.',
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
