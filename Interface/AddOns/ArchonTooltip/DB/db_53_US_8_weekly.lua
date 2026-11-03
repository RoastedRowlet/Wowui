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

local lookup = {'Unknown-Unknown','Paladin-Holy','Shaman-Enhancement','Shaman-Elemental','Shaman-Restoration','DeathKnight-Blood','Warrior-Arms','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Druid-Balance','Druid-Restoration','Druid-Feral','Mage-Arcane','DemonHunter-Havoc','Priest-Holy','Rogue-Assassination','Rogue-Subtlety','Paladin-Retribution','Druid-Guardian','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','Warrior-Protection','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','Hunter-Marksmanship','Hunter-BeastMastery','DeathKnight-Frost','DemonHunter-Vengeance','DemonHunter-Devourer','Hunter-Survival','Paladin-Protection','Priest-Shadow','Warlock-Affliction','Warrior-Fury',}
local provider = {region='US',realm='AltarofStorms',name='US',type='weekly',zone=53,date='2026-11-03',data={Ad='Adiina:BAAANQADCgQIBQAAAA==.',
Ae='Aelera:BAAANQADCgMIAwAAAA==.',
Ah='Ahnkoh:BAAANQADCgYICQAAAA==.',
Ak='Ak:BAAANQADCgUIDQABNQABCgEIAQABAAAAAA==.',
Al='Alcool:BAAANQAECgMIAwAAAA==.Alindril:BAABNQAECn86AAICAAoKhQ6oRgDGAQACAAoKhQ6oRgDGAQAAAA==.Alistarfall:BAAANQAECggIDwAAAA==.Alledra:BAAANQADCgEIAQAAAA==.Alyriana:BAABNQAECn8/AAQDAAoK9xaQCgBBAgADAAoK9xaQCgBBAgAEAAQK8RAB5ADPAAAFAAQKxwWM5gCdAAAAAA==.',
Am='Amiyo:BAAANQAECgEIAQAAAA==.',
An='Anixa:BAAANQADCgQIBAAAAA==.',
Ar='Arylis:BAAANQADCgMIAwAAAA==.',
As='Asalamalikum:BAAANQAECgcIDgABNQAFFAUIDAAGAKwhAA==.Ashfallen:BAAANQAECgQIBgAAAA==.',
At='Atpl:BAAANQAECgcIDgAAAA==.Atthegates:BAABNQAECn85AAIHAAoKnBJIVgDGAQAHAAoKnBJIVgDGAQAAAA==.',
Az='Azrel:BAAANQAECgYIBgAAAA==.',
Ba='Bachira:BAAANQADCgMIAwAAAA==.Baddragon:BAACNQAFFH8RAAQIAAcKwRFLCAC6AQAIAAYKKhBLCAC6AQAJAAMKiBWkCADoAAAKAAMKuBkECQCdAAA1AAQKfygABAkACgpZJP0EAEcDAAkACgrjI/0EAEcDAAgABQrHD38wABgBAAoABAotIGIVANoAAAAA.Balboo:BAAANQAECgcICQABNQAFFAcIFwALAMIYAA==.Balto:BAACNQAFFH8XAAMLAAcKwhhjBwAXAgALAAYKXh5jBwAXAgAMAAMKgxHECwAGAQA1AAQKf1UABAsACgodJksBAHoDAAsACgodJksBAHoDAA0ABwqRJd0IABMCAAwABwrAGEoqAFIBAAAA.Bayleef:BAABNQAECn8wAAIMAAoK4x4HDwDkAgAMAAoK4x4HDwDkAgAAAA==.',
Bd='Bdragon:BAAANQADCgUIBQAAAA==.',
Be='Belac:BAABNQAECn8pAAIHAAoKCRKUiwD/AQAHAAoKCRKUiwD/AQAAAA==.Bemillion:BAAANQABCgIIAgAAAA==.Bettyboom:BAABNQAECn9BAAIOAAoK1xb5RQAWAgAOAAoK1xb5RQAWAgABNQABCgMIAwABAAAAAA==.',
Bo='Boorase:BAAANQAECgQIBwAAAA==.',
Br='Brewlaw:BAAANQADCggIDgAAAA==.Brujita:BAAANQADCgIIAgAAAA==.Brèè:BAABNQAECn8wAAIPAAoK0B+ODwAmAwAPAAoK0B+ODwAmAwAAAA==.',
Bu='Bunny:BAABNQAECn8lAAIQAAoKrwyMdgC4AQAQAAoKrwyMdgC4AQAAAA==.',
Ca='Caelith:BAABNQAECn9JAAIOAAoKRhHIVwDjAQAOAAoKRhHIVwDjAQAAAA==.Calrinara:BAAANQADCggIFgABNQAECgoKHQAMABAUAA==.Cause:BAABNQAECn8VAAMRAAYK1xoLUgB1AQARAAUK1BkLUgB1AQASAAMKWhTagwDBAAABNQAECgYIGQAOAD0eAA==.',
Cl='Cl:BAAANQAECgEJAQABNQAECgoKKQAHAAkSAA==.',
Co='Conall:BAACNQAFFH8JAAITAAQKQgmaGwDLAAATAAQKQgmaGwDLAAA1AAQKfywAAxMACgpzGb5kAG0CABMACgpzGb5kAG0CAAIAAQq/AR0wAScAAAAA.Confetti:BAABNQAECn8hAAIMAAkKjSG/DAACAwAMAAkKjSG/DAACAwAAAA==.',
['Cä']='Cäpriestsun:BAAANQAECgYIAwAAAA==.',
Da='Daiquiri:BAAANQADCgUIBQABNQAECgkJIQAMAI0hAA==.Dajova:BAAANQAECgcIBwAAAA==.Darling:BAAANQAECgEIAgAAAA==.',
Dd='Ddofpain:BAAANQADCgIIAgAAAA==.',
De='Deadmawheals:BAABNQAECn8rAAMLAAoKOBaHFgAxAgALAAoKOBaHFgAxAgAUAAEKAADKaQAkAAAAAA==.Deathblooms:BAACNQAFFH8OAAIGAAcKfRAYCQA0AQAGAAcKfRAYCQA0AQA1AAQKfx8AAgYACQrKILQHAP0CAAYACQrKILQHAP0CAAAA.Dermo:BAAANQAECgQIBAAAAA==.',
Di='Dimfate:BAAANQABCgYIBwAAAA==.',
Dm='Dmaw:BAABNQAECn8YAAQVAAcKCg6qPAAwAQAVAAYKCg6qPAAwAQAWAAUKOBADLQADAQAXAAUKdgvoIADaAAAAAA==.',
Do='Dolsaekki:BAAANQABCgQIBAAAAA==.Doublmisting:BAAANQADCggICAAAAA==.',
Dr='Drarkbull:BAABNQAECn8YAAMYAAgKBB34CQD0AQAYAAcK5x74CQD0AQAHAAEKsRHkCQE8AAAAAA==.Dreki:BAAANQADCgYIBgAAAA==.Drizzitt:BAAANQAECgQIBQAAAA==.',
Dy='Dyspeptic:BAAANQAECgIIAgABNQAFFAUICwATALMHAA==.',
['Dé']='Déathshadow:BAAANQAECggIBwAAAA==.',
['Dó']='Dónkey:BAAANQADCggICAAAAA==.',
Eh='Ehunter:BAAANQADCgIIAgAAAA==.',
El='Eleara:BAAANQAECgEIAQAAAA==.Electro:BAABNQAECn8UAAIEAAUKLiBenABfAQAEAAUKLiBenABfAQABNQAECgYIGQAOAD0eAA==.Elementtamer:BAAANQADCgMIAwAAAA==.',
Es='Esh:BAABNQAECn8dAAMZAAkKqSIAGQAkAwAZAAgKuCEAGQAkAwAaAAIKQCX0OADdAAAAAA==.Espressó:BAAANQADCggICAABNQAECgkJIQAMAI0hAA==.',
Ev='Evildarkness:BAAANQADCggICAAAAA==.Evilemt:BAAANQADCggICwAAAA==.',
Fa='Fappio:BAAANQAECgMIAwABNQAECgoKNwAIACMjAA==.',
Fe='Fenlok:BAAANQADCgUIBQAAAA==.',
Fi='Firiana:BAAANQAECgUICQAAAA==.',
Fr='Frogsbreath:BAAANQADCgUIBQAAAA==.',
Ga='Galdrel:BAAANQADCgYIBwAAAA==.Ganksta:BAAANQAECgQIBgAAAA==.',
Gr='Graevold:BAAANQAECgYIBQAAAA==.Gravekeeper:BAAANQAECgcIBQAAAA==.Greymist:BAAANQADCggICAAAAA==.Grimoire:BAAANQAECggICwAAAA==.',
Gu='Gullar:BAAANQAECgEIAQAAAA==.Guzzug:BAAANQADCgUIBQABNQAECgoKFgAXAIIQAA==.',
Ha='Hallsblack:BAAANQADCgIIAgAAAA==.Harami:BAAANQAECgEIAgABNQAECggICwABAAAAAA==.Hartplate:BAAANQABCgUIBQAAAA==.Haymaker:BAABNQAECn8qAAMGAAkKrSFjDQCmAgAGAAgKrSFjDQCmAgAbAAYKxA/8ggATAQAAAA==.',
He='Heide:BAABNQAECn8dAAIMAAoKEBTuEwBCAgAMAAoKEBTuEwBCAgAAAA==.Helmon:BAAANQADCgIIAQAAAA==.',
Hi='Hizø:BAAANQAECgQIBQAAAA==.',
Ho='Ho:BAAANQAECgMIAwAAAA==.Hoofling:BAAANQAECgEIAgAAAA==.Hordeelf:BAAANQAECgIJAgAAAA==.Hordeforsure:BAACNQAFFH8RAAMcAAgKLRMHDAB+AQAcAAYKcxIHDAB+AQAdAAIKoRRlIwCmAAA1AAQKfzYAAxwACgrcJc8GAGMDABwACgqpJc8GAGMDAB0AAwqcI1kWAdYAAAE1AAQKAgkCAAEAAAAA.',
Hu='Humanwolf:BAAANQADCgMIBQAAAA==.',
Il='Iliyana:BAAANQAECgQIBQAAAA==.',
In='Inovar:BAACNQAFFH8NAAMZAAQKTRueHgAAAQAZAAMKLB2eHgAAAQAaAAEKjxceDQBQAAA1AAQKfzAAAxkACgofJN4VADIDABkACgofJN4VADIDABoAAQonIwJiAGEAAAAA.',
It='Ithelx:BAAANQAECgUIBQAAAA==.',
Iz='Izugzug:BAACNQAFFH8MAAMGAAUKrCH8DgBlAQAGAAUKrCH8DgBlAQAeAAEKhwhkIAA9AAA1AAQKfzMAAwYACgqmJEAIAHkDAAYACgqmJEAIAHkDABsABgoMEIx+ACIBAAAA.',
Je='Jefflewis:BAAANQABCgQIBAAAAA==.',
Jo='Joolam:BAAANQADCgQIBAAAAA==.',
Ju='Julibean:BAAANQAECgQIBAAAAA==.',
Jx='Jxyy:BAAANQADCgUIBQABNQAFFAQKDQAdAGEbAA==.',
Ka='Kaminey:BAAANQAECggICwAAAA==.Karizev:BAAANQADCggICAAAAA==.',
Ke='Kekson:BAAANQAECgYIBwAAAA==.Kenway:BAAANQAECgEIAQAAAA==.Keyoshe:BAAANQADCgIIAgAAAA==.',
Kh='Khagtar:BAAANQADCgIIAgAAAA==.Kheliyah:BAAANQAECgYIDgAAAA==.',
Ki='Kickinugget:BAABNQAECn8ZAAIVAAgKhB00EwD9AQAVAAgKhB00EwD9AQAAAA==.',
Ko='Korrkil:BAAANQADCgUIBQAAAA==.',
La='Lanthrastus:BAAANQAECgUICgAAAA==.Largecaliber:BAAANQADCggICAAAAA==.Lazors:BAAANQABCggIBwAAAA==.',
Li='Liability:BAAANQADCgEIAQAAAA==.Lilac:BAAANQADCgIIAgAAAA==.Lirria:BAAANQABCgMIAwAAAA==.Lisanalgaib:BAABNQAECn85AAIfAAoK8BWSBwDRAQAfAAoK8BWSBwDRAQAAAA==.',
Ly='Lynxxy:BAAANQAECgEIAQAAAA==.',
Ma='Magital:BAAANQAECgcIDgABNQAECgoKNAAgAHYXAA==.Magnetic:BAAANQAECgIIAwABNQAECgYIGQAOAD0eAA==.Manalorian:BAAANQADCgQIBAAAAA==.Maurita:BAAANQAECgYICwAAAA==.',
Mc='Mcwusseena:BAAANQABCgQIBQAAAA==.',
Me='Meawggramar:BAAANQADCgEIAQAAAA==.Medalea:BAAANQABCgQIBgAAAA==.Medior:BAAANQADCgUIBQAAAA==.Menethel:BAAANQAECgYICgABNQAECggICgABAAAAAA==.Meowjin:BAAANQADCggICAAAAA==.Merune:BAAANQADCggICAAAAA==.Meudail:BAAANQADCgIIAgAAAA==.',
Mi='Miasmata:BAABNQAECn80AAIeAAoK0xmyIgADAgAeAAoK0xmyIgADAgAAAA==.Mikeoxlongg:BAAANQAECgEIAQABNQAECgcIFAAZALsJAA==.Missgrey:BAAANQADCgQIBAAAAA==.',
Mo='Mordaut:BAABNQAECn8qAAIOAAkKPhthUQD0AQAOAAkKPhthUQD0AQAAAA==.Morts:BAABNQAECn8nAAMFAAoKOReeRgBHAgAFAAoKOReeRgBHAgAEAAEKAABTBwEAAAAAAA==.',
Mu='Muzuki:BAAANQAECgQIBgAAAA==.',
My='Mylaw:BAAANQADCgYIDgAAAA==.',
Na='Nabi:BAAANQAECgYIEAABNQAECgcIEAABAAAAAA==.Naianasha:BAABNQAECn8fAAIKAAgKzwhMDgBiAQAKAAgKzwhMDgBiAQAAAA==.',
Ne='Neris:BAABNQAECn8dAAMMAAkKzRHtIwAGAgAMAAkKzRHtIwAGAgALAAMKSwohlgCAAAABNQAFFAQIDQAZAE0bAA==.',
No='Nobara:BAAANQAECgEIAQAAAA==.Noggenkarl:BAAANQAECggICgAAAA==.Nosfyrakktu:BAAANQAECgYIDgABNQAECggIDwABAAAAAA==.',
Nu='Nun:BAAANQAECgEIAQAAAA==.',
Ob='Obscur:BAABNQAECn8hAAMZAAkK7BDoVQCZAQAZAAkK7BDoVQCZAQAaAAIKLQi8aABQAAAAAA==.',
On='Onepiece:BAAANQADCgEIAQABNQAFFAcIFwALAMIYAA==.',
Os='Osti:BAABNQAECn9GAAMdAAoKzCQuBgBKAwAhAAoKfSHyAACFAwAdAAoKgCQuBgBKAwABNQAFFAIIBwAVANMeAA==.',
Pa='Pahine:BAABNQAECn8wAAIDAAoK9hB9DQAJAgADAAoK9hB9DQAJAgABNQAECggICwABAAAAAA==.Pallywackèr:BAAANQAECgEIAQAAAA==.',
Pe='Pearlmc:BAAANQAFFAEIAQAAAA==.Pepedin:BAABNQAECn8vAAMiAAoKxBYJDgAVAgAiAAoKshYJDgAVAgATAAgKDQ9azgB+AQAAAA==.',
Ph='Phantoma:BAAANQADCgcIFQAAAA==.',
Pn='Pnkrweb:BAAANQAECgcIEgABNQAFFAEIAQABAAAAAA==.',
Po='Polloloco:BAAANQADCgcIBwAAAA==.Popshot:BAAANQAECgMIBAAAAA==.',
Pr='Profit:BAABNQAECn9EAAMQAAoKKSERCgB3AwAQAAoKKSERCgB3AwAjAAYKmRrsLAC+AQAAAA==.',
Pu='Punduh:BAABNQAECn9MAAIWAAoK0yAkAwCDAwAWAAoK0yAkAwCDAwAAAA==.',
Ra='Rabbidhalo:BAAANQAECgcIBwABNQAECgkJGgAEAAAaAA==.Rabbidtotem:BAABNQAECn8aAAMEAAkKABrbTABDAgAEAAgKThnbTABDAgAFAAIKvwpW4AA1AAAAAA==.Rainquis:BAAANQABCgIIAgAAAA==.Rajabra:BAABNQAECn8tAAIRAAoKIx6wCAAzAgARAAoKIx6wCAAzAgAAAA==.Rasoon:BAAANQADCgYIBgAAAA==.Raveroller:BAAANQAECgYIDQAAAA==.',
Re='Redryder:BAAANQAECgQIBgAAAA==.Reevoke:BAACNQAFFH8MAAMJAAgK3RSjAQArAgAJAAcKZxWjAQArAgAKAAEKKhKmCgBVAAA1AAQKfyAAAwkACgrBI3MDAHEDAAkACgrsIHMDAHEDAAoABwqfGnIFAPMBAAAA.Reighven:BAAANQAECggIEAABNQAFFAUIDAAGAKwhAA==.Rekson:BAAANQAECgEIAQABNQAECgEIAgABAAAAAA==.Rexson:BAABNQAECn8dAAIdAAgKkRGnfQB3AQAdAAgKkRGnfQB3AQAAAA==.',
Rh='Rhyderlight:BAAANQAECgIIAgAAAA==.Rhythm:BAABNQAECn8ZAAIOAAYKPR5/GQFhAQAOAAYKPR5/GQFhAQAAAA==.',
Ro='Rola:BAAANQADCggIDgAAAA==.Rolla:BAAANQADCggIHAAAAA==.Romolus:BAAANQADCgYIBgAAAA==.',
Ru='Ruddertrim:BAABNQAECn8sAAMdAAoKYBv/UADrAQAdAAoKYBv/UADrAQAcAAcKBxMOOQCIAQAAAA==.',
Sa='Sadist:BAAANQABCgIIAgAAAA==.Salinedione:BAAANQAECgQICgAAAA==.Sargeruas:BAAANQAECgEIAQAAAA==.Satoru:BAAANQAECgEIAQAAAA==.',
Sc='Scottiiee:BAAANQADCggIFQAAAA==.Scratch:BAAANQADCgUIBwAAAA==.',
Se='Segen:BAABNQAECn8uAAIOAAoK+Qz6XgDPAQAOAAoK+Qz6XgDPAQAAAA==.Semip:BAAANQAECgQICAAAAA==.Sen:BAABNQAECn8tAAMcAAoKnRfdEQDrAQAcAAoKERbdEQDrAQAdAAUKUBn81gBSAQAAAA==.',
Sg='Sgttapeworm:BAAANQADCgUIBgAAAA==.',
Sh='Shacewoman:BAAANQAECgMIAgAAAA==.Shaera:BAAANQAECgYIBgAAAA==.Shaitan:BAAANQADCgEIAQABNQAECggICwABAAAAAA==.Sheeple:BAAANQADCgYIBgAAAA==.Shwah:BAAANQAECgIIAQAAAA==.Shîver:BAAANQAECgcICwAAAA==.',
Si='Sidearm:BAAANQAECgQIBAAAAA==.Silvane:BAAANQAECgQIAwAAAA==.',
Sk='Skaadooshh:BAAANQADCgUJCQABNQAFFAUIDAAGAKwhAA==.',
Sl='Slayèr:BAAANQADCgYIBgAAAA==.',
Sn='Snaptraphunt:BAAANQADCgIIAgAAAA==.Snipedyou:BAAANQAECgEIAgAAAA==.',
So='Soleah:BAAANQAECgQIBAAAAA==.Sophie:BAAANQADCgIIAgAAAA==.',
St='Staberella:BAAANQADCgMIAwAAAA==.Stache:BAABNQAECn8hAAICAAoK4hrZIwB2AgACAAoK4hrZIwB2AgAAAA==.Stevethuzad:BAAANQAECgIIAgABNQAECgoKFgAXAIIQAA==.Stormydaniel:BAABNQAECn8cAAIDAAoKuAUWFQB8AQADAAoKuAUWFQB8AQAAAA==.',
Sy='Synikal:BAABNQAECn8zAAIFAAoKmxPRSAC9AQAFAAoKmxPRSAC9AQAAAA==.',
['Sâ']='Sâuron:BAAANQABCgcJCQAAAA==.',
['Sæ']='Sæ:BAAANQAECgIIAwAAAA==.',
Ta='Taleiran:BAABNQAECn80AAIgAAoKdhdJGQCQAgAgAAoKdhdJGQCQAgAAAA==.',
Th='Thdro:BAAANQADCgYIBgAAAA==.Thehollow:BAAANQAECgQIBAABNQAECggIHwAKAM8IAA==.Threeofseven:BAAANQADCgcICAAAAA==.Thrøat:BAABNQAECn87AAIGAAoKax/yEgBYAgAGAAoKax/yEgBYAgAAAA==.',
Ti='Tiberiius:BAABNQAECn8nAAMdAAoKnx8fSACUAgAdAAoKnx8fSACUAgAcAAUKIRYJRAA4AQAAAA==.Tilly:BAABNQAECn8kAAIPAAkKCRQXJACtAQAPAAkKCRQXJACtAQAAAA==.Titus:BAAANQAECgcIDAAAAA==.',
To='Toes:BAAANQADCgIIAgAAAA==.Toranny:BAAANQAECgEIAQAAAA==.',
Tr='Trigodun:BAAANQADCgYIBgAAAA==.Trobaugh:BAAANQAECgEIAQAAAA==.',
Un='Undeadlysoul:BAABNQAECn88AAQZAAoKrR/lFwCcAgAZAAoKLR/lFwCcAgAkAAYKnx11CgDQAQAaAAEKbhuYagBMAAAAAA==.Undedagaindk:BAACNQAFFH8cAAMbAAgKuR8RAgAyAgAbAAcKuR8RAgAyAgAGAAEKAACrOgAdAAA1AAQKfzoAAxsACgpPJosJAHIDABsACgpPJosJAHIDAAYAAQq+JRiwAGsAAAAA.',
Up='Uppercut:BAABNQAECn8WAAMlAAkKhRR4CADaAQAlAAkKJRF4CADaAQAYAAIKAB7jLwBdAAAAAA==.',
Us='Ussford:BAABNQAECn8vAAQWAAgK3RW/EADAAQAWAAcKnBi/EADAAQAXAAYKHQn4GAB+AAAVAAQKPwASggAEAAABNQAECgoKLwAZABUaAA==.Ussorlando:BAABNQAECn8vAAIZAAoKFRrfLgDLAgAZAAoKFRrfLgDLAgAAAA==.',
Va='Valaw:BAAANQADCggIHAAAAA==.Valgprincess:BAAANQADCgUIBQAAAA==.Vallaw:BAAANQADCggICQAAAA==.',
Vi='Vignette:BAAANQADCgcIBwAAAA==.Vincentius:BAABNQAECn8jAAIiAAgKcQmGKQD0AAAiAAgKcQmGKQD0AAAAAA==.',
Vo='Voidberg:BAAANQADCgEIAQAAAA==.Voidflame:BAAANQAECgQICAAAAA==.Volteil:BAAANQADCgYIBgAAAA==.',
Vu='Vuori:BAABNQAECn8bAAMFAAcK+yBDfgCRAQAFAAYK/h9DfgCRAQAEAAUKrhR/pQBJAQAAAA==.',
Wa='Warstomp:BAAANQAECgMIBAAAAA==.',
We='Wetdog:BAAANQADCgIIAgABNQAFFAcIFwALAMIYAA==.',
Wh='Whixx:BAABNQAECn8oAAIZAAgK2wkEjQAMAQAZAAgK2wkEjQAMAQABNQAECgkJGgAEAJESAA==.',
Wi='Wikm:BAAANQAECgUIBgAAAA==.Will:BAAANQAECgcIBwABNQAFFAUIDgATADQjAA==.',
Xn='Xnaisa:BAABNQAECn86AAIFAAoKVyObCABxAwAFAAoKVyObCABxAwAAAA==.',
Xp='Xplosive:BAAANQADCgMIAwABNQAECgQIBgABAAAAAA==.',
Ys='Yshaarj:BAAANQADCgYICgABNQAECggIEgABAAAAAA==.',
Za='Zale:BAAANQAECgEIAQAAAA==.Zapey:BAABNQAECn8aAAIEAAkKkRKFZgDtAQAEAAkKkRKFZgDtAQAAAA==.',
Ze='Zerude:BAABNQAECn8vAAIIAAoKwxM3GAA5AgAIAAoKwxM3GAA5AgAAAA==.',
Zm='Zmr:BAABNQAECn8mAAMFAAoK4x7FKgBLAgAFAAoK4x7FKgBLAgAEAAYKTh6UigCKAQAAAA==.Zmrr:BAAANQADCgIIAgABNQAECgoKJgAFAOMeAA==.',
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
