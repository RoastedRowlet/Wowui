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

local lookup = {'Unknown-Unknown','Paladin-Holy','Shaman-Enhancement','Shaman-Elemental','Shaman-Restoration','DeathKnight-Blood','DemonHunter-Devourer','DemonHunter-Havoc','Warrior-Arms','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Druid-Balance','Druid-Restoration','Druid-Feral','Hunter-BeastMastery','Mage-Arcane','Priest-Holy','Rogue-Assassination','Rogue-Subtlety','Paladin-Retribution','Druid-Guardian','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','Warrior-Protection','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','Hunter-Marksmanship','DeathKnight-Frost','DemonHunter-Vengeance','Hunter-Survival','Paladin-Protection','Priest-Shadow','Warlock-Affliction','Warrior-Fury',}
local provider = {region='US',realm='AltarofStorms',name='US',type='weekly',zone=53,date='2026-11-17',data={Ad='Adiina:BAAANQADCgQIBQAAAA==.',
Ae='Aelera:BAAANQADCgMIAwAAAA==.',
Ah='Ahnkoh:BAAANQADCgYICQAAAA==.',
Ak='Ak:BAAANQADCgUIDQABNQABCgEIAQABAAAAAA==.',
Al='Alcool:BAAANQAECgMIAwAAAA==.Alindril:BAABNQAECn86AAICAAoKhQ7QWgCtAQACAAoKhQ7QWgCtAQAAAA==.Alistarfall:BAAANQAECggIDwAAAA==.Alledra:BAAANQADCgEIAQAAAA==.Alyriana:BAABNQAECn8/AAQDAAoK9xbEDQA5AgADAAoK9xbEDQA5AgAEAAQK8RAB5ADPAAAFAAQKxwWM5gCdAAAAAA==.',
Am='Amiyo:BAAANQAECgEIAQAAAA==.',
An='Anixa:BAAANQADCgQIBAAAAA==.',
Aq='Aquasance:BAAANQADCgcIBwAAAA==.',
Ar='Arylis:BAAANQADCgMIAwAAAA==.',
As='Asalamalikum:BAABNQAECn8VAAIEAAkKixLMNwD1AQAEAAkKixLMNwD1AQABNQAFFAYIEQAGANMbAA==.Ashfallen:BAAANQAECgQIDgAAAA==.',
At='Atpl:BAABNQAECn8WAAMHAAkKIQ2uKwA6AQAHAAkKhQmuKwA6AQAIAAQK1BTGVQDLAAAAAA==.Atthegates:BAABNQAECn9DAAIJAAoKnBLGZQDPAQAJAAoKnBLGZQDPAQAAAA==.',
Az='Azrel:BAAANQAECgYIBgAAAA==.',
Ba='Bachira:BAAANQADCgMIAwAAAA==.Baddragon:BAACNQAFFH8RAAQKAAcKwRFLCAC6AQAKAAYKKhBLCAC6AQALAAMKiBWkCADoAAAMAAMKuBkECQCdAAA1AAQKfykABAsACgpZJP0EAEcDAAsACgrjI/0EAEcDAAoABQrHD38wABgBAAwABAotIGIVANoAAAAA.Balboo:BAAANQAECgcICQABNQAFFAgIGgANAJAXAA==.Balto:BAACNQAFFH8aAAMNAAgKkBdjBwAXAgANAAcK0BtjBwAXAgAOAAMKgxHECwAGAQA1AAQKf1cABA0ACgqAJjIBAIEDAA0ACgqAJjIBAIEDAA8ABwqRJYkMAAoCAA4ABwrAGH80AE8BAAAA.Bamcis:BAABNQAECn8dAAIQAAgKkRE3mgCAAQAQAAgKkRE3mgCAAQAAAA==.Bayleef:BAABNQAECn8wAAIOAAoK4x4HDwDkAgAOAAoK4x4HDwDkAgAAAA==.',
Bd='Bdragon:BAAANQADCgUIBQAAAA==.',
Be='Belac:BAABNQAECn8pAAIJAAoKCRKUiwD/AQAJAAoKCRKUiwD/AQAAAA==.Bemillion:BAAANQABCgIIAgAAAA==.Bettyboom:BAABNQAECn9MAAIRAAoKHBjZQQBIAgARAAoKHBjZQQBIAgABNQABCgMIAwABAAAAAA==.',
Bo='Boorase:BAAANQAECgQIBwAAAA==.',
Br='Brewlaw:BAAANQADCggIDgAAAA==.Brujita:BAAANQADCgIIAgAAAA==.Brèè:BAABNQAECn8wAAIIAAoK0B+ODwAmAwAIAAoK0B+ODwAmAwAAAA==.',
Bu='Bunny:BAABNQAECn8lAAISAAoKrwyMdgC4AQASAAoKrwyMdgC4AQAAAA==.',
Ca='Caelith:BAABNQAECn9VAAIRAAoKXRK2WgAFAgARAAoKXRK2WgAFAgAAAA==.Calrinara:BAAANQADCggIFgABNQAECgoKHQAOABAUAA==.Cause:BAABNQAECn8XAAMTAAYK1xoLUgB1AQATAAUK1BkLUgB1AQAUAAMKWhSDogC+AAABNQAECgYIHAARAD0eAA==.',
Cl='Cl:BAAANQAECgEJAQABNQAECgoKKQAJAAkSAA==.',
Co='Conall:BAACNQAFFH8OAAIVAAUKvg0bDgAWAQAVAAUKvg0bDgAWAQA1AAQKfzAAAxUACgpzGb5kAG0CABUACgpzGb5kAG0CAAIAAQq/AR0wAScAAAAA.Confetti:BAABNQAECn8mAAIOAAoKlyF0DAACAwAOAAoKlyF0DAACAwAAAA==.',
['Cä']='Cäpriestsun:BAAANQAECgQIBQAAAA==.',
Da='Daiquiri:BAAANQADCgUIBQABNQAECgoKJgAOAJchAA==.Dajova:BAAANQAECgcIBwAAAA==.Darling:BAAANQAECgEIAgAAAA==.',
Dd='Ddofpain:BAAANQADCgIIAgAAAA==.',
De='Deadmawheals:BAABNQAECn8tAAMNAAoKxhedGQA/AgANAAoKxhedGQA/AgAWAAEKAADKaQAkAAAAAA==.Deathblooms:BAACNQAFFH8QAAIGAAgK7RMXCQCSAQAGAAgK7RMXCQCSAQA1AAQKfysAAgYACQqAIg8GACQDAAYACQqAIg8GACQDAAAA.Dermo:BAAANQAECgQIBAAAAA==.',
Di='Dimfate:BAAANQABCgYIBwAAAA==.Diredayz:BAAANQAECgcIBwAAAA==.',
Dm='Dmaw:BAABNQAECn8YAAQXAAcKCg6qPAAwAQAXAAYKCg6qPAAwAQAYAAUKOBADLQADAQAZAAUKdgvoIADaAAAAAA==.',
Do='Doublmisting:BAAANQADCggICAAAAA==.',
Dr='Dragonsloot:BAAANQAECgYIBgABNQAECgoKPwAHANMZAA==.Drarkbull:BAABNQAECn8YAAMaAAgKBB12DQDmAQAaAAcK5x52DQDmAQAJAAEKsRGVJQE8AAAAAA==.Dreki:BAAANQADCgYIBgAAAA==.Drizzitt:BAAANQAECgQICQAAAA==.',
Dy='Dyspeptic:BAAANQAECgIIAgABNQAFFAUICwAVALMHAA==.',
['Dé']='Déathshadow:BAAANQAECgcIDQAAAA==.',
['Dó']='Dónkey:BAAANQADCggICAAAAA==.',
Eh='Ehunter:BAAANQADCgIIAgAAAA==.',
El='Eleara:BAAANQAECgIIAgAAAA==.Electro:BAABNQAECn8VAAIEAAYK9x5enABfAQAEAAYK9x5enABfAQABNQAECgYIHAARAD0eAA==.Elementtamer:BAAANQADCgMIAwAAAA==.',
Es='Esh:BAABNQAECn8dAAMbAAkKqSIAGQAkAwAbAAgKuCEAGQAkAwAcAAIKQCX0OADdAAAAAA==.Espressó:BAAANQADCggICAABNQAECgoKJgAOAJchAA==.',
Ev='Evildarkness:BAAANQADCggICAAAAA==.Evilemt:BAAANQADCggICwAAAA==.',
Fa='Fappio:BAAANQAECgMIAwABNQAECgoKPAAKACMjAA==.',
Fe='Fenlok:BAAANQADCgUIBQAAAA==.',
Fi='Firiana:BAAANQAECgUICQAAAA==.',
Fr='Frieeren:BAAANQAECgIIAgABNQAFFAUICAAQAD8UAA==.Frogsbreath:BAAANQADCgUIBQAAAA==.',
Ga='Galdrel:BAAANQADCgYIBwAAAA==.Ganksta:BAAANQAECgQIBgAAAA==.',
Gr='Graevold:BAAANQAECgYICAAAAA==.Gravekeeper:BAAANQAECgcIBgAAAA==.Greymist:BAAANQADCggICAAAAA==.Grimoire:BAAANQAECggICwAAAA==.',
Gu='Gullar:BAAANQAECgEIAQAAAA==.Guzzug:BAAANQADCgUIBQABNQAECgoKFgAZAIIQAA==.',
Ha='Hallsblack:BAAANQADCgIIAgAAAA==.Harami:BAAANQAECgEIAgABNQAECggICwABAAAAAA==.Hartplate:BAAANQABCgUIBQAAAA==.Haymaker:BAABNQAECn8qAAMGAAkKrSFvEACaAgAGAAgKrSFvEACaAgAdAAYKxA/8ggATAQAAAA==.',
He='Heide:BAABNQAECn8dAAIOAAoKEBQUGgA+AgAOAAoKEBQUGgA+AgAAAA==.Helmon:BAAANQADCgIIAQAAAA==.',
Hi='Hizø:BAAANQAECgQIBQAAAA==.',
Ho='Ho:BAAANQAECgMIAwAAAA==.Hoofling:BAAANQAECgEIAgAAAA==.Hordeelf:BAAANQAECgIIAgAAAA==.Hordeforsure:BAACNQAFFH8SAAMeAAkKShMHDAB+AQAeAAcKwRIHDAB+AQAQAAIKoRRlIwCmAAA1AAQKfz8AAx4ACgoEJtoBAFUDAB4ACgrRJdoBAFUDABAAAwqcI1kWAdYAAAE1AAQKAggCAAEAAAAA.',
Hu='Humanwolf:BAAANQADCgMIBQAAAA==.',
Il='Iliyana:BAAANQAECgQIBQAAAA==.',
In='Inovar:BAACNQAFFH8NAAMbAAQKTRueHgAAAQAbAAMKLB2eHgAAAQAcAAEKjxcbEABOAAA1AAQKfzAAAxsACgofJN4VADIDABsACgofJN4VADIDABwAAQonIwJiAGEAAAAA.',
It='Ithelx:BAAANQAECgUIBQAAAA==.',
Iz='Izugzug:BAACNQAFFH8RAAMGAAYK0xt2DQAwAQAGAAYK0xt2DQAwAQAfAAEKhwhkIAA9AAA1AAQKfzcAAwYACgrFJEAIAHkDAAYACgrFJEAIAHkDAB0ABgoMEIx+ACIBAAAA.',
Je='Jefflewis:BAAANQABCgQIBAAAAA==.',
Jo='Joolam:BAAANQADCgQIBAAAAA==.',
Ju='Julibean:BAAANQAECgQIBAAAAA==.',
Jx='Jxyy:BAAANQADCgUIBQABNQAFFAUKFQAQADcjAA==.',
Ka='Kaminey:BAAANQAECggICwAAAA==.Karizev:BAAANQADCggICAAAAA==.',
Ke='Kekson:BAAANQAECggIDQAAAA==.Kenway:BAAANQAECgMIAwAAAA==.Keyoshe:BAAANQADCgIIAgAAAA==.',
Kh='Khagtar:BAAANQADCgQIBAAAAA==.Kheliyah:BAAANQAECgYIDgAAAA==.',
Ki='Kickinugget:BAABNQAECn8gAAIXAAkKOx/3DACNAgAXAAkKOx/3DACNAgAAAA==.',
Ko='Korrkil:BAAANQADCgUIBQAAAA==.',
La='Lainora:BAAANQADCgUIBQAAAA==.Lanthrastus:BAAANQAECgUIEwAAAA==.Largecaliber:BAAANQADCggICAAAAA==.Lazors:BAAANQABCggIBwAAAA==.',
Li='Liability:BAAANQADCgEIAQAAAA==.Lilac:BAAANQADCgIIAgAAAA==.Lirria:BAAANQABCgMIAwAAAA==.Lisanalgaib:BAABNQAECn85AAIgAAoK8BXxCQDHAQAgAAoK8BXxCQDHAQAAAA==.',
Ly='Lynxxy:BAAANQAECgEIAQAAAA==.',
Ma='Magital:BAAANQAECggIDgABNQAECgoKPwAHANMZAA==.Magnetic:BAAANQAECgIIAwABNQAECgYIHAARAD0eAA==.Manalorian:BAAANQADCgQIBAAAAA==.Maurita:BAAANQAECgUIDQAAAA==.',
Mc='Mcvoke:BAAANQABCgQIBQAAAA==.Mcwusseena:BAAANQABCgQIBQABNQABCgQIBQABAAAAAA==.',
Me='Meawggramar:BAAANQADCgEIAQAAAA==.Medalea:BAAANQABCgQIBgAAAA==.Medior:BAAANQADCgUIBQAAAA==.Menethel:BAAANQAECgYICgABNQAECggICgABAAAAAA==.Meowjin:BAAANQADCggICAAAAA==.Merune:BAAANQADCggICAAAAA==.Meudail:BAAANQADCgIIAgAAAA==.',
Mi='Miasmata:BAABNQAECn84AAIfAAoK0xmBJwBbAgAfAAoK0xmBJwBbAgAAAA==.Mikeoxlongg:BAAANQAECgEIAQABNQAECgcIFAAbALsJAA==.Missgrey:BAAANQADCgQIBAAAAA==.',
Mo='Mordaut:BAABNQAECn8uAAIRAAoKYBx8QQBJAgARAAoKYBx8QQBJAgAAAA==.Morts:BAABNQAECn8oAAMFAAoKRBeeRgBHAgAFAAoKRBeeRgBHAgAEAAEKAAA8JwEAAAAAAA==.',
Mu='Muzuki:BAAANQAECgQIDgAAAA==.',
My='Mylaw:BAAANQADCgYIDgAAAA==.',
Na='Nabi:BAAANQAECgYIEAABNQAECgcIEAABAAAAAA==.Naianasha:BAABNQAECn8fAAIMAAgKzwhMDgBiAQAMAAgKzwhMDgBiAQAAAA==.',
Ne='Neris:BAABNQAECn8dAAMOAAkKzRHtIwAGAgAOAAkKzRHtIwAGAgANAAMKSwohlgCAAAABNQAFFAQIDQAbAE0bAA==.',
No='Nobara:BAAANQAECgEIAQAAAA==.Noggenkarl:BAAANQAECggICgAAAA==.Nosfyrakktu:BAAANQAECgYIDgABNQAECggIDwABAAAAAA==.',
Nu='Nun:BAAANQAECgEIAQAAAA==.',
Ob='Obscur:BAABNQAECn8qAAMbAAoKGBTNRQADAgAbAAoKGBTNRQADAgAcAAIKLQi8aABQAAAAAA==.',
On='Onepiece:BAAANQADCgEIAQABNQAFFAgIGgANAJAXAA==.',
Os='Osti:BAABNQAECn9NAAMQAAoKxCWrBABqAwAhAAoKfSHyAACFAwAQAAoKliWrBABqAwABNQAFFAIIBwAXANMeAA==.',
Pa='Pahine:BAABNQAECn8xAAIDAAoKyxEIEAAVAgADAAoKyxEIEAAVAgABNQAECggICwABAAAAAA==.Pallywackèr:BAAANQAECgEIAQAAAA==.',
Pe='Pearlmc:BAAANQAFFAEIAQAAAA==.Pepedin:BAABNQAECn8/AAMiAAoKFRyNCgCOAgAiAAoKFRyNCgCOAgAVAAgKDQ9azgB+AQAAAA==.',
Ph='Phantoma:BAAANQADCgcIFQAAAA==.',
Pn='Pnkrweb:BAAANQAECgcIEgABNQAFFAEIAQABAAAAAA==.',
Po='Polloloco:BAAANQADCgcIBwAAAA==.Popshot:BAAANQAECgMIBAAAAA==.',
Pr='Profit:BAABNQAECn9YAAMSAAoKBSKKBwC7AwASAAoKBSKKBwC7AwAjAAYKmRrsLAC+AQAAAA==.',
Pu='Punduh:BAABNQAECn9dAAIYAAoKMSH2AwCAAwAYAAoKMSH2AwCAAwAAAA==.',
Ra='Rabbidhalo:BAAANQAECgcIBwABNQAECgkJGgAEAAAaAA==.Rabbidtotem:BAABNQAECn8aAAMEAAkKABrbTABDAgAEAAgKThnbTABDAgAFAAIKvwr+9gA1AAAAAA==.Rainquis:BAAANQABCgIIAgAAAA==.Rajabra:BAABNQAECn8tAAITAAoKIx7iCgAoAgATAAoKIx7iCgAoAgAAAA==.Rasoon:BAAANQADCgYIBgAAAA==.Raveroller:BAAANQAECgYIDQAAAA==.',
Re='Redryder:BAAANQAECgQIBgAAAA==.Reevoke:BAACNQAFFH8MAAMLAAgK3RSjAQArAgALAAcKZxWjAQArAgAMAAEKKhI/DgBOAAA1AAQKfyAAAwsACgrBI3MDAHEDAAsACgrsIHMDAHEDAAwABwqfGoUGAPABAAAA.Reighven:BAAANQAECggIEAABNQAFFAYIEQAGANMbAA==.Rekson:BAAANQAECgEIAQABNQAECgEIAgABAAAAAA==.',
Rh='Rhyderlight:BAAANQAECgIIAgAAAA==.Rhythm:BAABNQAECn8cAAIRAAYKPR5/GQFhAQARAAYKPR5/GQFhAQAAAA==.',
Ro='Rola:BAAANQADCggIDgAAAA==.Rolla:BAAANQADCggIHAAAAA==.Romolus:BAAANQADCgYIBgAAAA==.',
Ru='Ruddertrim:BAABNQAECn81AAMQAAoKih6TUQAqAgAQAAoKih6TUQAqAgAeAAcKBxMOOQCIAQAAAA==.',
Sa='Sadist:BAAANQABCgIIAgAAAA==.Salinedione:BAAANQAECgQICgAAAA==.Sargeruas:BAAANQAECgEIAQAAAA==.Satoru:BAAANQAECgEIAQAAAA==.',
Sc='Scottiiee:BAAANQADCggIFQAAAA==.Scratch:BAAANQADCgUIBwAAAA==.',
Se='Segen:BAABNQAECn83AAIRAAoKXw2BbgDUAQARAAoKXw2BbgDUAQAAAA==.Semip:BAAANQAECgUIEQAAAA==.Sen:BAABNQAECn8tAAMeAAoKnRfKFQDrAQAeAAoKERbKFQDrAQAQAAUKUBn81gBSAQAAAA==.',
Sg='Sgttapeworm:BAAANQADCgUIBgAAAA==.',
Sh='Shacewoman:BAAANQAECgIIAgAAAA==.Shaera:BAAANQAECgUIBgAAAA==.Shaitan:BAAANQADCgEIAQABNQAECggICwABAAAAAA==.Sheeple:BAAANQADCgYIBgAAAA==.Shwah:BAAANQAECgEIAQAAAA==.Shîver:BAAANQAECgcICwAAAA==.',
Si='Sidearm:BAAANQAECgQIBAAAAA==.Silvane:BAAANQAECgQIAwAAAA==.',
Sk='Skaadooshh:BAAANQADCgUJCQABNQAFFAYIEQAGANMbAA==.',
Sl='Slayèr:BAAANQADCgYIBgAAAA==.',
Sn='Snaptraphunt:BAAANQADCgIIAgAAAA==.Snipedyou:BAAANQAECgEIAgAAAA==.',
So='Soleah:BAAANQAECgQIBAAAAA==.Sophie:BAAANQADCgIIAgAAAA==.',
St='Staberella:BAAANQADCgMIAwAAAA==.Stache:BAABNQAECn8oAAMCAAoKjBykIQC0AgACAAoKjBykIQC0AgAVAAEKAAClzgEAAAAAAA==.Stevethuzad:BAAANQAECgIIAgABNQAECgoKFgAZAIIQAA==.Stormydaniel:BAABNQAECn8cAAIDAAoKuAW5GQB6AQADAAoKuAW5GQB6AQAAAA==.',
Sy='Synikal:BAABNQAECn82AAIFAAoKVBQnUQDOAQAFAAoKVBQnUQDOAQAAAA==.',
['Sâ']='Sâuron:BAAANQABCgcJCQAAAA==.',
['Sæ']='Sæ:BAAANQAECgIIAwAAAA==.',
Ta='Taleiran:BAABNQAECn8/AAIHAAoK0xlJGQCQAgAHAAoK0xlJGQCQAgAAAA==.',
Th='Thdro:BAAANQADCgYIBgAAAA==.Thehollow:BAAANQAECgQIBAABNQAECggIHwAMAM8IAA==.Threeofseven:BAAANQADCgcICAAAAA==.Thrøat:BAABNQAECn9GAAIGAAoKax93FABqAgAGAAoKax93FABqAgAAAA==.',
Ti='Tiberiius:BAABNQAECn8nAAMQAAoKnx8fSACUAgAQAAoKnx8fSACUAgAeAAUKIRYJRAA4AQAAAA==.Tilly:BAABNQAECn8kAAIIAAkKCRTxLACrAQAIAAkKCRTxLACrAQAAAA==.Titus:BAAANQAECgcIDAAAAA==.',
To='Toes:BAAANQADCgIIAgAAAA==.Toranny:BAAANQAECgEIAQABNQAECgcIBwABAAAAAA==.',
Tr='Trigodun:BAAANQADCgYIBgAAAA==.Trobaugh:BAAANQAECgEIAQAAAA==.',
Un='Undeadlysoul:BAABNQAECn8/AAQbAAoK6iDgFgDEAgAbAAoKjiDgFgDEAgAkAAYKnx11CgDQAQAcAAEKbhuYagBMAAAAAA==.Undedagaindk:BAACNQAFFH8jAAMdAAkKdB6gAABQAgAdAAgKdB6gAABQAgAGAAEKAACrOgAdAAA1AAQKfzsAAx0ACgpPJosJAHIDAB0ACgpPJosJAHIDAAYAAQq+JRiwAGsAAAAA.',
Up='Uppercut:BAABNQAECn8fAAMlAAkKqBdICQANAgAlAAkKSBRICQANAgAaAAIKAB48OQBbAAAAAA==.',
Us='Ussford:BAABNQAECn83AAQYAAgK8R0GCgCtAgAYAAcK2CEGCgCtAgAZAAYKHQmDHQB5AAAXAAQKPwASggAEAAABNQAECgoKOwAbAGccAA==.Ussorlando:BAABNQAECn87AAIbAAoKZxx2KABtAgAbAAoKZxx2KABtAgAAAA==.',
Va='Valaw:BAAANQADCggIHAAAAA==.Valgprincess:BAAANQADCgUIBQAAAA==.Vallaw:BAAANQADCggICQAAAA==.',
Vi='Vignette:BAAANQADCgcIBwAAAA==.Vincentius:BAABNQAECn8qAAIiAAoKwAnVJABIAQAiAAoKwAnVJABIAQAAAA==.',
Vo='Voidberg:BAAANQADCgEIAQAAAA==.Voidflame:BAAANQAECgQICAAAAA==.Volteil:BAAANQADCgYIBgAAAA==.',
Vu='Vuori:BAABNQAECn8cAAMFAAgK0CBAXgCeAQAFAAcK8B9AXgCeAQAEAAUKrhR/pQBJAQAAAA==.',
Wa='Warstomp:BAAANQAECgMIBAAAAA==.',
We='Wetdog:BAAANQADCgIIAgABNQAFFAgIGgANAJAXAA==.',
Wh='Whixx:BAABNQAECn8oAAIbAAgK2wkRowAQAQAbAAgK2wkRowAQAQABNQAECgoKIQAEAGQSAA==.',
Wi='Wikm:BAAANQAECgUIBgAAAA==.Will:BAAANQAECgcIBwABNQAFFAYIEwAVAK0kAA==.',
Xn='Xnaisa:BAABNQAECn9DAAIFAAoKrSMfCgB7AwAFAAoKrSMfCgB7AwAAAA==.',
Xp='Xplosive:BAAANQADCgMIAwABNQAECgQIBgABAAAAAA==.',
Ys='Yshaarj:BAAANQADCgYICgABNQAECggIEgABAAAAAA==.',
Za='Zale:BAAANQAECgEIAQAAAA==.Zapey:BAABNQAECn8hAAIEAAoKZBKFZgDtAQAEAAoKZBKFZgDtAQAAAA==.',
Ze='Zerude:BAABNQAECn8vAAIKAAoKwxM3GAA5AgAKAAoKwxM3GAA5AgAAAA==.',
Zm='Zmr:BAABNQAECn8oAAMFAAoK4x7MOQB4AgAFAAoK4x7MOQB4AgAEAAYKTh6UigCKAQAAAA==.Zmrr:BAAANQADCgIIAgABNQAECgoKKAAFAOMeAA==.',
Zo='Zoomies:BAAANQAECgMIAwABNQAECgoKPAAKACMjAA==.',
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
