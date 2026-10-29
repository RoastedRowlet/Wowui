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

local lookup = {'Unknown-Unknown','Paladin-Holy','Shaman-Enhancement','Shaman-Elemental','Shaman-Restoration','DeathKnight-Blood','Warrior-Arms','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Druid-Balance','Druid-Restoration','Druid-Feral','Mage-Arcane','DemonHunter-Havoc','Priest-Holy','Paladin-Retribution','Druid-Guardian','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','Warrior-Protection','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','Hunter-Marksmanship','Hunter-BeastMastery','DeathKnight-Frost','DemonHunter-Vengeance','DemonHunter-Devourer','Hunter-Survival','Paladin-Protection','Priest-Shadow','Rogue-Assassination','Warlock-Affliction',}
local provider = {region='US',realm='AltarofStorms',name='US',type='weekly',zone=53,date='2026-10-27',data={Ad='Adiina:BAAANQADCgQIBQAAAA==.',
Ae='Aelera:BAAANQADCgMIAwAAAA==.',
Ah='Ahnkoh:BAAANQADCgYICQAAAA==.',
Ak='Ak:BAAANQADCgUIDQABNQABCgEIAQABAAAAAA==.',
Al='Alcool:BAAANQAECgMIAwAAAA==.Alindril:BAABNQAECn80AAICAAoKPQ49NQDLAQACAAoKPQ49NQDLAQAAAA==.Alistarfall:BAAANQAECggIDAAAAA==.Alledra:BAAANQABCggICwAAAA==.Alyriana:BAABNQAECn83AAQDAAkKyRTICwDhAQADAAkKyRTICwDhAQAEAAQK8RAB5ADPAAAFAAQKxwWM5gCdAAAAAA==.',
Am='Amiyo:BAAANQAECgEIAQAAAA==.',
An='Anixa:BAAANQADCgQIBAAAAA==.',
Aq='Aquasance:BAAANQADCgcIBwAAAA==.',
Ar='Arylis:BAAANQADCgMIAwAAAA==.',
As='Asalamalikum:BAAANQAECggIDAABNQAFFAUIDAAGAKwhAA==.Ashfallen:BAAANQAECgMIBQAAAA==.',
At='Atpl:BAAANQAECggICgAAAA==.Atthegates:BAABNQAECn8xAAIHAAoKIhD2TwCUAQAHAAoKIhD2TwCUAQAAAA==.',
Az='Azrel:BAAANQAECgYIBgAAAA==.',
Ba='Bachira:BAAANQADCgMIAwAAAA==.Baddragon:BAACNQAFFH8RAAQIAAcKwRFLCAC6AQAIAAYKKhBLCAC6AQAJAAMKiBWkCADoAAAKAAMKuBkECQCdAAA1AAQKfycABAkACgrjI/0EAEcDAAkACgrjI/0EAEcDAAgABQrHD38wABgBAAoAAwptH2IVANoAAAAA.Balboo:BAAANQAECgcICQABNQAFFAcIFgALAMIYAA==.Balto:BAACNQAFFH8WAAMLAAcKwhhjBwAXAgALAAYKXh5jBwAXAgAMAAMKgxHECwAGAQA1AAQKf0sABAsACgoHJlwDAMgDAAsACgoHJlwDAMgDAA0ABwqRJbQFACkCAAwABQpUFcFHAPYAAAAA.Bayleef:BAABNQAECn8uAAIMAAoKjBwHDwDkAgAMAAoKjBwHDwDkAgAAAA==.',
Bd='Bdragon:BAAANQADCgUIBQAAAA==.',
Be='Belac:BAABNQAECn8lAAIHAAoK1RCUiwD/AQAHAAoK1RCUiwD/AQAAAA==.Bemillion:BAAANQABCgIIAgAAAA==.Bettyboom:BAABNQAECn82AAIOAAoKqhVLOgAKAgAOAAoKqhVLOgAKAgABNQABCgMIAwABAAAAAA==.',
Bo='Boorase:BAAANQAECgQIBwAAAA==.',
Br='Brewlaw:BAAANQADCgQIBwAAAA==.Brujita:BAAANQADCgIIAgAAAA==.Brèè:BAABNQAECn8wAAIPAAoK0B+ODwAmAwAPAAoK0B+ODwAmAwAAAA==.',
Bu='Bunny:BAABNQAECn8lAAIQAAoKrwzMWQBNAQAQAAoKrwzMWQBNAQAAAA==.',
Ca='Caelith:BAABNQAECn9AAAIOAAoKMBHaQgDsAQAOAAoKMBHaQgDsAQAAAA==.Calrinara:BAAANQADCggIFgABNQAECggIEwABAAAAAA==.Cause:BAAANQAECgUIEwABNQAECgYIFwAOACkdAA==.',
Cl='Cl:BAAANQAECgEJAQABNQAECgoKJQAHANUQAA==.',
Co='Conall:BAACNQAFFH8JAAIRAAQKQgmaGwDLAAARAAQKQgmaGwDLAAA1AAQKfygAAxEACgoWGb5kAG0CABEACgoWGb5kAG0CAAIAAQq/AR0wAScAAAAA.Confetti:BAABNQAECn8gAAIMAAkKGSG/DAACAwAMAAkKGSG/DAACAwAAAA==.',
['Cä']='Cäpriestsun:BAAANQAECgMIAwAAAA==.',
Da='Daiquiri:BAAANQADCgUIBQABNQAECgkJIAAMABkhAA==.Dajova:BAAANQAECgcIBwAAAA==.Darling:BAAANQAECgEIAQAAAA==.',
Dd='Ddofpain:BAAANQADCgIIAgAAAA==.',
De='Deadmawheals:BAABNQAECn8iAAMLAAoKuxMEFgDzAQALAAkKuxMEFgDzAQASAAEKAADKaQAkAAAAAA==.Deathblooms:BAACNQAFFH8OAAIGAAcKfRDzBQBAAQAGAAcKfRDzBQBAAQA1AAQKfxkAAgYACQq2G8sNAGkCAAYACQq2G8sNAGkCAAAA.Dermo:BAAANQAECgMIAwAAAA==.',
Di='Dimfate:BAAANQABCgYIBgAAAA==.',
Dm='Dmaw:BAABNQAECn8YAAQTAAcKCg6qPAAwAQATAAYKCg6qPAAwAQAUAAUKOBADLQADAQAVAAUKdgvoIADaAAAAAA==.',
Do='Doublmisting:BAAANQADCggICAAAAA==.',
Dr='Drarkbull:BAABNQAECn8YAAMWAAgKBB26BgAIAgAWAAcK5x66BgAIAgAHAAEKsRG57ABAAAAAAA==.Dreki:BAAANQADCgYIBgAAAA==.Drizzitt:BAAANQAECgMIBAAAAA==.',
Dy='Dyspeptic:BAAANQAECgIIAgABNQAFFAUICwARALMHAA==.',
['Dé']='Déathshadow:BAAANQAECgIIAQAAAA==.',
['Dó']='Dónkey:BAAANQADCggICAAAAA==.',
Eh='Ehunter:BAAANQADCgIIAgAAAA==.',
El='Electro:BAAANQAECgQIEQABNQAECgYIFwAOACkdAA==.Elementtamer:BAAANQADCgMIAwAAAA==.',
Es='Esh:BAABNQAECn8cAAMXAAkKqSIAGQAkAwAXAAgKuCEAGQAkAwAYAAIKQCX0OADdAAAAAA==.',
Ev='Evildarkness:BAAANQADCggICAAAAA==.Evilemt:BAAANQADCggICwAAAA==.Evilmt:BAAANQADCgYIBwAAAA==.',
Fa='Fappio:BAAANQAECgMIAwABNQAECgoKMwAIAFEgAA==.',
Fe='Fenlok:BAAANQADCgUIBQAAAA==.',
Fi='Firiana:BAAANQAECgUICQAAAA==.',
Fr='Frogsbreath:BAAANQADCgUIBQAAAA==.',
Ga='Galdrel:BAAANQADCgYIBwAAAA==.Ganksta:BAAANQAECgQIBQAAAA==.',
Gr='Graevold:BAAANQAECgQIBAAAAA==.Greymist:BAAANQADCggICAAAAA==.Grimoire:BAAANQAECggICwAAAA==.',
Gu='Gullar:BAAANQAECgEIAQAAAA==.Guzzug:BAAANQADCgUIBQABNQAECgoKFgAVAIIQAA==.',
Ha='Hallsblack:BAAANQADCgIIAgAAAA==.Harami:BAAANQAECgEIAQABNQAECggICwABAAAAAA==.Hartplate:BAAANQABCgUIBQAAAA==.Haymaker:BAABNQAECn8gAAMGAAgK2hvnHgCaAQAGAAcKjRvnHgCaAQAZAAYKxA/8ggATAQAAAA==.',
He='Heide:BAAANQAECggIEwAAAA==.Helmon:BAAANQADCgIIAQAAAA==.',
Hi='Hizø:BAAANQAECgQIBQAAAA==.',
Ho='Ho:BAAANQAECgMIAwAAAA==.Hoofling:BAAANQAECgEIAQAAAA==.Hordeelf:BAAANQAECgIJAgAAAA==.Hordeforsure:BAACNQAFFH8RAAMaAAgKLRMHDAB+AQAaAAYKcxIHDAB+AQAbAAIKoRRlIwCmAAA1AAQKfzEAAxoACgrcJc8GAGMDABoACgqpJc8GAGMDABsAAwqcI1kWAdYAAAE1AAQKAgkCAAEAAAAA.',
Hu='Humanwolf:BAAANQADCgMIBQAAAA==.',
Il='Iliyana:BAAANQAECgQIBQAAAA==.',
In='Inovar:BAACNQAFFH8LAAMXAAQKTRueHgAAAQAXAAMKLB2eHgAAAQAYAAEKjxdlCgBUAAA1AAQKfzAAAxcACgofJN4VADIDABcACgofJN4VADIDABgAAQonIwJiAGEAAAAA.',
It='Ithelx:BAAANQABCgQIBAAAAA==.',
Iz='Izugzug:BAACNQAFFH8MAAMGAAUKrCH8DgBlAQAGAAUKrCH8DgBlAQAcAAEKhwhkIAA9AAA1AAQKfy8AAwYACgqmJEAIAHkDAAYACgqmJEAIAHkDABkABgoMEIx+ACIBAAAA.',
Je='Jefflewis:BAAANQABCgQIBAAAAA==.',
Jo='Joolam:BAAANQADCgQIBAAAAA==.',
Ju='Julibean:BAAANQAECgQIBAAAAA==.',
Jx='Jxyy:BAAANQADCgUIBQABNQAFFAQKDAAbAGEbAA==.',
Ka='Kaminey:BAAANQAECggICwAAAA==.Karizev:BAAANQADCggICAAAAA==.',
Ke='Kekson:BAAANQAECgUIBQAAAA==.Keyoshe:BAAANQADCgIIAgAAAA==.',
Kh='Khagtar:BAAANQADCgIIAgAAAA==.Kheliyah:BAAANQAECgYIDgAAAA==.',
Ki='Kickinugget:BAABNQAECn8XAAITAAgK9xoXFACmAQATAAgK9xoXFACmAQAAAA==.',
Ko='Korrkil:BAAANQADCgUIBQAAAA==.',
La='Lanthrastus:BAAANQAECgUICgAAAA==.Largecaliber:BAAANQADCggICAAAAA==.Lazors:BAAANQABCggIBwAAAA==.',
Li='Liability:BAAANQADCgEIAQAAAA==.Lilac:BAAANQADCgIIAgAAAA==.Lirria:BAAANQABCgMIAwAAAA==.Lisanalgaib:BAABNQAECn84AAIdAAoK8BVpBQDZAQAdAAoK8BVpBQDZAQAAAA==.',
Ly='Lynxxy:BAAANQAECgEIAQAAAA==.',
Ma='Magital:BAAANQAECgcIDgABNQAECgoKKgAeAO4WAA==.Magnetic:BAAANQAECgIIAwABNQAECgYIFwAOACkdAA==.Manalorian:BAAANQADCgQIBAAAAA==.Maurita:BAAANQAECgUIBgAAAA==.',
Me='Meawggramar:BAAANQADCgEIAQAAAA==.Medalea:BAAANQABCgQIBgAAAA==.Medier:BAAANQADCggIDAAAAA==.Medior:BAAANQADCgUIBQAAAA==.Menethel:BAAANQAECgYICgABNQAECggICgABAAAAAA==.Meowjin:BAAANQADCggICAAAAA==.Meudail:BAAANQADCgIIAgAAAA==.',
Mi='Miah:BAAANQADCgEIAQAAAA==.Miasmata:BAABNQAECn8uAAIcAAoKzxn+GAAIAgAcAAoKzxn+GAAIAgAAAA==.Mikeoxlongg:BAAANQAECgEIAQABNQAECgcIFAAXALsJAA==.Missgrey:BAAANQADCgQIBAAAAA==.',
Mo='Mordaut:BAABNQAECn8jAAIOAAkK6Bq8RQDiAQAOAAkK6Bq8RQDiAQAAAA==.Morts:BAABNQAECn8lAAIFAAoKIBeeRgBHAgAFAAoKIBeeRgBHAgAAAA==.',
Mu='Muzuki:BAAANQAECgQIBQAAAA==.',
My='Mylaw:BAAANQADCgQICAAAAA==.',
Na='Nabi:BAAANQAECgYIEAABNQAECgcIEAABAAAAAA==.Naianasha:BAABNQAECn8fAAIKAAgKzwhMDgBiAQAKAAgKzwhMDgBiAQAAAA==.',
Ne='Neris:BAABNQAECn8dAAMMAAkKzRHtIwAGAgAMAAkKzRHtIwAGAgALAAMKSwohlgCAAAABNQAFFAQICwAXAE0bAA==.',
No='Nobara:BAAANQAECgEIAQAAAA==.Noggenkarl:BAAANQAECggICgAAAA==.Nosfyrakktu:BAAANQAECgUICQABNQAECggIDAABAAAAAA==.',
Nu='Nun:BAAANQAECgEIAQAAAA==.',
Ob='Obscur:BAABNQAECn8ZAAMXAAgKexGnfQDsAQAXAAgKExGnfQDsAQAYAAIKLQi8aABQAAAAAA==.',
On='Onepiece:BAAANQADCgEIAQABNQAFFAcIFgALAMIYAA==.',
Os='Osti:BAABNQAECn88AAMbAAoKPiR1CAAUAwAfAAoKfSHyAACFAwAbAAoKkCF1CAAUAwABNQAFFAIIBwATANMeAA==.',
Pa='Pahine:BAABNQAECn8mAAIDAAkKwQ+jDADLAQADAAkKwQ+jDADLAQABNQAECggICwABAAAAAA==.Pallywackèr:BAAANQAECgEIAQAAAA==.',
Pe='Pepedin:BAABNQAECn8kAAMgAAoKOhHMIwDgAAARAAgKDQ9azgB+AQAgAAcKvRDMIwDgAAAAAA==.',
Ph='Phantoma:BAAANQADCgcIEwAAAA==.',
Pn='Pnkrweb:BAAANQAECgYIEQAAAA==.',
Po='Polloloco:BAAANQADCgcIBwAAAA==.Popshot:BAAANQAECgMIBAAAAA==.',
Pr='Profit:BAABNQAECn86AAMQAAoKTB/2DQAKAwAQAAoKTB/2DQAKAwAhAAYKmRrsLAC+AQAAAA==.',
Pu='Punduh:BAABNQAECn9DAAIUAAoKciCNAgBtAwAUAAoKciCNAgBtAwAAAA==.',
Ra='Rabbidhalo:BAAANQAECgcIBwABNQAECgkJGQAEAAAaAA==.Rabbidtotem:BAABNQAECn8ZAAMEAAkKABrbTABDAgAEAAgKThnbTABDAgAFAAIKvwrwxAA3AAAAAA==.Rainquis:BAAANQABCgIIAgAAAA==.Rajabra:BAABNQAECn8tAAIiAAoKIx7ZBQBYAgAiAAoKIx7ZBQBYAgAAAA==.Rasoon:BAAANQADCgYIBgAAAA==.Raveroller:BAAANQAECgcICQAAAA==.',
Re='Redryder:BAAANQAECgQIBgAAAA==.Reevoke:BAACNQAFFH8KAAIJAAcKZxWjAQArAgAJAAcKZxWjAQArAgA1AAQKfxYAAwkACgrFIXMDAHEDAAkACgrsIHMDAHEDAAoAAwpmEGgNAKgAAAAA.Reighven:BAAANQAECggIEAABNQAFFAUIDAAGAKwhAA==.Rekson:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Rexson:BAABNQAECn8dAAIbAAgKkRGTWwCLAQAbAAgKkRGTWwCLAQAAAA==.',
Rh='Rhyderlight:BAAANQAECgIIAgAAAA==.Rhythm:BAABNQAECn8XAAIOAAYKKR1/GQFhAQAOAAYKKR1/GQFhAQAAAA==.',
Ro='Rola:BAAANQADCgUIDgAAAA==.Rolla:BAAANQADCggIDgAAAA==.Romolus:BAAANQADCgYIBgAAAA==.',
Ru='Ruddertrim:BAABNQAECn8lAAMbAAoK4hauYABVAgAbAAoK4hauYABVAgAaAAcKgw8OOQCIAQAAAA==.',
Sa='Sadist:BAAANQABCgIIAgAAAA==.Salinedione:BAAANQAECgQICgAAAA==.Sargeruas:BAAANQAECgEIAQAAAA==.Satoru:BAAANQAECgEIAQAAAA==.',
Sc='Scottiiee:BAAANQADCggIFQAAAA==.Scratch:BAAANQADCgUIBwAAAA==.',
Se='Segen:BAABNQAECn8kAAIOAAkKaAy7YQCJAQAOAAkKaAy7YQCJAQAAAA==.Semip:BAAANQAECgMIBwAAAA==.Sen:BAABNQAECn8jAAMaAAoKwBZ0IQBCAgAaAAoKNRV0IQBCAgAbAAUKUBn81gBSAQAAAA==.',
Sg='Sgttapeworm:BAAANQADCgUIBgAAAA==.',
Sh='Shacewoman:BAAANQAECgQIAgAAAA==.Shaera:BAAANQAECgUIBQAAAA==.Shaitan:BAAANQADCgEIAQABNQAECggICwABAAAAAA==.Sheeple:BAAANQADCgYIBgAAAA==.Shîver:BAAANQAECgcICwAAAA==.',
Si='Sidearm:BAAANQAECgQIBAAAAA==.Silvane:BAAANQAECgMIAwAAAA==.',
Sk='Skaadooshh:BAAANQADCgUJCQABNQAFFAUIDAAGAKwhAA==.',
Sl='Slayèr:BAAANQADCgYIBgAAAA==.',
Sn='Snaptraphunt:BAAANQADCgIIAgAAAA==.Snipedyou:BAAANQADCggIEgAAAA==.',
So='Sophie:BAAANQADCgIIAgAAAA==.',
St='Staberella:BAAANQADCgMIAwAAAA==.Stache:BAABNQAECn8dAAICAAoKTRpmFwCJAgACAAoKTRpmFwCJAgAAAA==.Stevethuzad:BAAANQAECgIIAgABNQAECgoKFgAVAIIQAA==.Stevo:BAAANQADCgYIDQAAAA==.Stormydaniel:BAAANQAECggIEAAAAA==.',
Sy='Synikal:BAABNQAECn8sAAIFAAgKERNDegCdAQAFAAgKERNDegCdAQAAAA==.',
['Sâ']='Sâuron:BAAANQABCgcJCQAAAA==.',
['Sæ']='Sæ:BAAANQAECgIIAwAAAA==.',
Ta='Taleiran:BAABNQAECn8qAAIeAAoK7hZJGQCQAgAeAAoK7hZJGQCQAgAAAA==.',
Th='Thdro:BAAANQADCgYIBgAAAA==.Threeofseven:BAAANQADCgcICAAAAA==.Thrøat:BAABNQAECn8yAAIGAAoKax+rDQBrAgAGAAoKax+rDQBrAgAAAA==.',
Ti='Tiberiius:BAABNQAECn8jAAMbAAoKyx0fSACUAgAbAAoKyx0fSACUAgAaAAUKIRYJRAA4AQAAAA==.Tilly:BAABNQAECn8cAAIPAAcKuRXmOgDeAQAPAAcKuRXmOgDeAQAAAA==.Titus:BAAANQAECgcIDAAAAA==.',
To='Toes:BAAANQADCgIIAgAAAA==.Toranny:BAAANQAECgEIAQAAAA==.',
Tr='Trigodun:BAAANQADCgYIBgAAAA==.Trobaugh:BAAANQAECgEIAQAAAA==.',
Un='Undeadlysoul:BAABNQAECn81AAQXAAoKCR+3EgCTAgAXAAoKdx63EgCTAgAjAAYKnx11CgDQAQAYAAEKbhuYagBMAAAAAA==.Undedagaindk:BAACNQAFFH8cAAMZAAgKuR8RAgAyAgAZAAcKuR8RAgAyAgAGAAEKAACrOgAdAAA1AAQKfzkAAxkACgpPJosJAHIDABkACgpPJosJAHIDAAYAAQq+JRiwAGsAAAAA.',
Up='Uppercut:BAAANQAECggIEgAAAA==.',
Us='Ussford:BAABNQAECn8oAAQUAAgK7RCFJQBNAQAUAAcK+BKFJQBNAQAVAAYKHQmqFACAAAATAAQKPwASggAEAAABNQAECgoKKAAXANcWAA==.Ussorlando:BAABNQAECn8oAAIXAAoK1xbfLgDLAgAXAAoK1xbfLgDLAgAAAA==.',
Va='Valaw:BAAANQADCggIGgAAAA==.Valgprincess:BAAANQADCgUIBQAAAA==.Vallaw:BAAANQADCggICQAAAA==.',
Vi='Vignette:BAAANQADCgcIBwAAAA==.Vincentius:BAABNQAECn8hAAIgAAgKcQmNIAD3AAAgAAgKcQmNIAD3AAAAAA==.',
Vo='Voidberg:BAAANQADCgEIAQAAAA==.Voidflame:BAAANQAECgQICAAAAA==.Volteil:BAAANQADCgYIBgAAAA==.',
Vu='Vuori:BAABNQAECn8aAAMFAAcK+yAATwBaAQAFAAYK/h8ATwBaAQAEAAUKrhR/pQBJAQAAAA==.',
Wa='Warstomp:BAAANQAECgMIBAAAAA==.',
We='Wetdog:BAAANQADCgIIAgABNQAFFAcIFgALAMIYAA==.',
Wh='Whixx:BAABNQAECn8mAAIXAAgK2gn+cgAVAQAXAAgK2gn+cgAVAQAAAA==.',
Wi='Wikm:BAAANQAECgUIBgAAAA==.Will:BAAANQAECgcIBwABNQAFFAQIDQARADQjAA==.',
Xn='Xnaisa:BAABNQAECn8vAAIFAAoK+yCICQApAwAFAAoK+yCICQApAwAAAA==.',
Xp='Xplosive:BAAANQADCgMIAwABNQAECgQIBgABAAAAAA==.',
Ys='Yshaarj:BAAANQADCgYICgABNQAECggIEgABAAAAAA==.',
Za='Zale:BAAANQAECgEIAQAAAA==.Zapey:BAAANQAECgcIDwABNQAECggIJgAXANoJAA==.',
Ze='Zerude:BAABNQAECn8uAAIIAAoKlhM3GAA5AgAIAAoKlhM3GAA5AgAAAA==.',
Zm='Zmr:BAABNQAECn8jAAMFAAkKCB3MOQB4AgAFAAkKCB3MOQB4AgAEAAYKTh6UigCKAQAAAA==.Zmrr:BAAANQADCgIIAgABNQAECgkJIwAFAAgdAA==.',
['Çh']='Çhris:BAAANQADCggIFQAAAA==.',
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
