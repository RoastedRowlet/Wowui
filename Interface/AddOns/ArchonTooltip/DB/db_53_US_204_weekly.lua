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

local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Warlock-Destruction','Mage-Arcane','Hunter-Marksmanship','Warrior-Fury','Warrior-Arms','Druid-Balance','Paladin-Holy','Shaman-Restoration','Warrior-Protection','DeathKnight-Frost','Hunter-Survival','Paladin-Retribution','Monk-Mistweaver','Rogue-Assassination','Rogue-Subtlety','Paladin-Protection','DeathKnight-Blood','Priest-Holy','Warlock-Affliction','Monk-Windwalker','Rogue-Outlaw','Shaman-Elemental','Druid-Guardian','Mage-Fire','Warlock-Demonology','Druid-Restoration','Shaman-Enhancement','DemonHunter-Havoc',}
local provider = {region='US',realm='SteamwheedleCartel',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aalwein:BAAANQAECgcIEwAAAA==.',
Ad='Adehn:BAAANQADCgEIAQAAAA==.',
Al='Alfrus:BAAANQADCggICQAAAA==.',
Am='Amarii:BAAANQAECgYIDgAAAA==.',
An='Andent:BAAANQABCgYICAABNQADCggIFgABAAAAAA==.',
Ap='Appostle:BAAANQADCgYICgAAAA==.',
Ar='Ara:BAABNQAECn8iAAICAAkKDRlUQACnAgACAAkKDRlUQACnAgAAAA==.',
As='Asteryn:BAAANQAECgIIAwAAAA==.',
Av='Avigar:BAAANQAECgUICgAAAA==.',
Ba='Bangan:BAAANQAECgEIAQAAAA==.Banisary:BAAANQADCgYIBgAAAA==.',
Be='Belakor:BAAANQAECgMIBgAAAA==.Bep:BAAANQAECgEIAQABNQAECgkJIwADAF4SAA==.Bepragosa:BAABNQAECn8jAAIDAAkKXhLABgCdAgADAAkKXhLABgCdAgAAAA==.',
Bi='Bighammer:BAAANQAECgUIBQABNQAFFAcIFQAEALcWAA==.Binpharteen:BAAANQADCgcICwAAAA==.Birgitè:BAAANQADCgYIBwAAAA==.',
Bl='Blaque:BAAANQAECgYIEAAAAA==.',
Bo='Bowguytome:BAABNQAFFH8FAAIFAAUK+CVQBAAsAgAFAAUK+CVQBAAsAgAAAA==.Bozo:BAAANQAECgIIAgAAAA==.',
Br='Brownbelt:BAABNQAECn8hAAMGAAkKNhDlCgAVAgAGAAkKNhDlCgAVAgAHAAUKuAMSDwG4AAAAAA==.Brîn:BAAANQAECgUIDwAAAA==.',
Bu='Buteihunter:BAABNQAECn8bAAICAAgKZSJuGAA3AwACAAgKZSJuGAA3AwAAAA==.Buteilock:BAAANQAECgQIBAABNQAECggIGwACAGUiAA==.Butherts:BAAANQAECggIDAAAAA==.',
Ch='Chelali:BAABNQAECn8jAAIHAAkKCBpCUwCNAgAHAAkKCBpCUwCNAgAAAA==.Chicharrone:BAABNQAECn8nAAIIAAcKvAfxYQBDAQAIAAcKvAfxYQBDAQAAAA==.Chizaru:BAABNQAECn8gAAIJAAkKax3fGwADAwAJAAkKax3fGwADAwAAAA==.Chlorophyll:BAAANQADCggICAAAAA==.Chyntobelt:BAAANQAECgQICwABNQAECgkJIQAGADYQAA==.',
Cr='Cryption:BAAANQAECggIDwAAAA==.',
Da='Daelyn:BAAANQAECgEIAQAAAA==.',
De='Deafenned:BAAANQADCggIDQAAAA==.Deafnight:BAAANQADCggIDAABNQADCggIDQABAAAAAA==.Deliquesce:BAAANQADCggICgAAAA==.',
Di='Diamante:BAABNQAECn8qAAIKAAgK5xoUPgBlAgAKAAgK5xoUPgBlAgAAAA==.Dignifeyed:BAAANQADCgcIBwAAAA==.Discoelsi:BAAANQAECgMIAwAAAA==.',
Dr='Dracarnoir:BAAANQADCgcIEAAAAA==.Dragonite:BAABNQAECn8nAAMHAAkKkiMZDQCPAwAHAAkKkiMZDQCPAwALAAMK2xH0MwCRAAAAAA==.Dremu:BAABNQAECn8hAAIIAAcK6R7ULAByAgAIAAcK6R7ULAByAgAAAA==.',
Du='Duskhunter:BAAANQAECgUICgAAAA==.',
Dy='Dysraxis:BAAANQABCggICgAAAA==.',
['Dï']='Dïnhö:BAAANQAECgMIBQAAAA==.',
El='Elahna:BAAANQAECgMIAwAAAA==.Elamaun:BAABNQAECn8cAAIJAAcKMBTScADCAQAJAAcKMBTScADCAQAAAA==.Eltiana:BAABNQAECn8fAAIEAAkKJAmO1gDXAQAEAAkKJAmO1gDXAQAAAA==.',
Em='Emisa:BAAANQADCgIIAgAAAA==.',
Ep='Ephex:BAAANQADCgUIBAAAAA==.Ephriest:BAAANQADCgMIBAABNQAECgYIDgABAAAAAA==.Ephury:BAAANQAECgYIDgAAAA==.Epic:BAAANQADCgIIAgAAAA==.',
Ev='Evhomang:BAAANQAECgYIBAABNQAFFAcIGAAMAEIhAA==.',
Fa='Faelyna:BAABNQAECn8eAAINAAcKAQ2uCAC8AQANAAcKAQ2uCAC8AQAAAA==.',
Fe='Fearbear:BAAANQADCgUJAwAAAA==.',
Fo='Forged:BAABNQAECn8wAAIOAAkKHCSIFgBpAwAOAAkKHCSIFgBpAwAAAA==.',
Fu='Fufufu:BAAANQADCgQIBAABNQAECggIKgAKAOcaAA==.',
Gi='Githyanki:BAAANQADCggIEQAAAA==.',
Go='Goop:BAAANQADCgUIBQABNQAECgkJIwAPAC0jAA==.',
Gr='Grangshammy:BAAANQAECgUIEwAAAA==.Grimskull:BAAANQADCgMIAwAAAA==.Grimvault:BAAANQAECgEIAQABNQAECgcIHwAEAF4dAA==.',
Ha='Hacelian:BAAANQADCgYIBgAAAA==.Han:BAABNQAECn8gAAMQAAkKKBMLKwA4AgAQAAkK9hILKwA4AgARAAYKNQz3MAAxAQAAAA==.Hargoroth:BAAANQADCggICwAAAA==.',
He='Henudorf:BAAANQAECgYIDQAAAA==.',
Ho='Holyverdict:BAAANQADCgQIAwAAAA==.',
Ic='Icaina:BAABNQAECn8oAAIKAAkKnx/xFQAeAwAKAAkKnx/xFQAeAwAAAA==.',
In='Infernnape:BAAANQAECgEIAgAAAA==.',
Ja='Jathy:BAAANQADCgQIBAAAAA==.',
Je='Jeisa:BAABNQAECn8cAAMSAAcKoQsNPwD7AAAOAAYK7QY6DgEAAQASAAYKKQwNPwD7AAAAAA==.',
Jh='Jhedu:BAAANQADCgcJBwAAAA==.',
Ju='Juanns:BAAANQADCgcJBwAAAA==.',
Ka='Kaj:BAABNQAECn8fAAIJAAkKPBIvUAAoAgAJAAkKPBIvUAAoAgAAAA==.Kallotera:BAAANQADCggICAAAAA==.Kalrou:BAAANQADCgUIBQABNQAECgkJJQATABEjAA==.Kastoria:BAAANQADCgUIBQAAAA==.Katnipp:BAABNQAECn8ZAAICAAcKgA+qkQDiAQACAAcKgA+qkQDiAQAAAA==.Kaylazune:BAABNQAECn8YAAIUAAcK1w6higByAQAUAAcK1w6higByAQAAAA==.',
Kh='Kharybdis:BAAANQAECgEIAQAAAA==.Khrala:BAAANQAECgUIEAAAAA==.',
Ki='Kindlana:BAAANQADCggICwAAAA==.Kiye:BAACNQAFFH8SAAICAAYK4xUZBQABAgACAAYK4xUZBQABAgA1AAQKfzAAAgIACQpZI68cACQDAAIACQpZI68cACQDAAAA.',
Ku='Kushan:BAAANQADCgEIAQAAAA==.Kuuro:BAABNQAECn8bAAIKAAYKdhCUnQA4AQAKAAYKdhCUnQA4AQAAAA==.',
La='Lattymag:BAAANQAECgUIDgAAAA==.Laughystabby:BAAANQADCgcIDgAAAA==.',
Le='Leibniz:BAABNQAECn8XAAIVAAcK0x16BQBoAgAVAAcK0x16BQBoAgAAAA==.Leisa:BAABNQAECn8bAAICAAcKoQ/EjADtAQACAAcKoQ/EjADtAQAAAA==.Lelwindae:BAAANQAECgQIBwAAAA==.',
Li='Lifemoon:BAAANQAECgQIBAAAAA==.Lildangerus:BAAANQADCgYIDQAAAA==.Liminara:BAEBNQAECn8eAAIOAAkKtg9KqgDGAQAOAAkKtg9KqgDGAQABNQAFFAYIEAACABQcAA==.Linaste:BAAANQAECggIEQAAAA==.',
Lo='Lohha:BAAANQADCgIIAgAAAA==.',
Lu='Lulu:BAACNQAFFH8kAAIWAAkKMSEpAACyAwAWAAkKMSEpAACyAwA1AAQKfyQAAhYACQp2JngDAJ4DABYACQp2JngDAJ4DAAAA.Lumaria:BAAANQAECgQIDAAAAA==.',
Ly='Lyllia:BAAANQAECgYIDgAAAA==.Lynoia:BAAANQADCggICAAAAA==.',
Ma='Makunel:BAAANQADCggICAAAAA==.Mandevu:BAAANQAECgEIAQAAAA==.Mangan:BAAANQAECgEJAwAAAA==.Manknus:BAABNQAECn8jAAIGAAgKgg+mDADtAQAGAAgKgg+mDADtAQAAAA==.Manthrax:BAABNQAECn8fAAIKAAgKLApEiABxAQAKAAgKLApEiABxAQAAAA==.Mathiyis:BAAANQABCgcICwABNQAECgQIBwABAAAAAA==.',
Me='Mexecutioner:BAABNQAECn8fAAIHAAcKFw0RsQCdAQAHAAcKFw0RsQCdAQAAAA==.',
Mi='Milkadin:BAAANQADCgIIAgAAAA==.Mirzan:BAAANQADCgEIAQAAAA==.Missmolt:BAABNQAECn8gAAIXAAgKcR9bBADJAgAXAAgKcR9bBADJAgAAAA==.',
Mo='Mogok:BAABNQAECn8bAAISAAYKvA1xOQAeAQASAAYKvA1xOQAeAQAAAA==.Molting:BAAANQAECgMJBwAAAA==.Moonkin:BAAANQABCgQIBQAAAA==.',
Mu='Musclegary:BAABNQAECn8xAAMYAAkKMCKiCgCQAwAYAAkKMCKiCgCQAwAKAAEK9RouEQFBAAAAAA==.',
My='Mykie:BAAANQADCggIDwAAAA==.Mylor:BAABNQAECn8mAAISAAcKwB1EFABgAgASAAcKwB1EFABgAgAAAA==.Myrddral:BAABNQAECn8aAAITAAcK8Bw7NwAqAgATAAcK8Bw7NwAqAgAAAA==.Mystifeyed:BAABNQAECn8fAAIZAAkKnQ3yHgChAQAZAAkKnQ3yHgChAQAAAA==.',
['Mü']='Mürsaat:BAAANQAECgYIEAAAAA==.',
Na='Nagrad:BAAANQAECgEIAQAAAA==.Namrekcah:BAAANQAECgEIAQABNQAFFAcIGwATAMYaAA==.',
Ni='Nilaya:BAAANQADCggICAAAAA==.Nimbledragon:BAAANQADCgYIDQAAAA==.',
Nt='Ntayu:BAABNQAECn8bAAICAAYKfgRv5AAzAQACAAYKfgRv5AAzAQAAAA==.',
Ol='Olizia:BAABNQAECn8eAAIMAAgK9hagLAA1AgAMAAgK9hagLAA1AgAAAA==.',
Op='Opex:BAABNQAECn8dAAICAAcKYAwTnQDJAQACAAcKYAwTnQDJAQAAAA==.',
Or='Oril:BAAANQADCgMIAwAAAA==.',
Ot='Otura:BAAANQADCgIIAgAAAA==.',
Pe='Perkyblade:BAABNQAECn8iAAMGAAgKOxClDQDYAQAGAAgKOxClDQDYAQALAAIKcwNLPQBKAAAAAA==.',
Pl='Planeswalker:BAAANQAECgQIBAAAAA==.',
Po='Poxic:BAAANQAECgIJBAAAAA==.',
Pr='Protection:BAAANQABCgYIBgAAAA==.',
Ps='Psychotic:BAAANQADCgMIAwAAAA==.',
Ra='Ravinar:BAABNQAECn8eAAIaAAcKRxheAgAmAgAaAAcKRxheAgAmAgAAAA==.Razzle:BAABNQAECn8mAAIbAAkK6BOZUQBdAgAbAAkK6BOZUQBdAgAAAA==.Raàm:BAAANQADCgQIBAAAAA==.',
Re='Relia:BAAANQADCgMIAwAAAA==.',
Ri='Rizzstoned:BAAANQADCggIEwAAAA==.',
Ro='Romulus:BAABNQAECn8cAAMcAAcKABQILwCeAQAcAAcKABQILwCeAQAIAAEKAABNwgAeAAAAAA==.',
Sa='Sarbarola:BAAANQADCgcIHAAAAA==.',
Se='Seraid:BAAANQADCggIFwAAAA==.',
Sh='Shallbedo:BAAANQAECgEIAQABNQAECgkJLAAdAK0PAA==.Shallmagi:BAAANQADCgUIBQABNQAECgkJLAAdAK0PAA==.Shmalexia:BAAANQABCgEJAQAAAA==.',
Si='Siatraler:BAAANQADCgUIBQAAAA==.Sigarette:BAACNQAFFH8bAAITAAcKxhr3AgBnAgATAAcKxhr3AgBnAgA1AAQKfzQAAhMACQrYIkYEAKwDABMACQrYIkYEAKwDAAAA.Sinardi:BAABNQAECn8fAAIeAAcKggqkSgBzAQAeAAcKggqkSgBzAQAAAA==.',
Sk='Skoob:BAAANQADCgEIAQAAAA==.Skymane:BAAANQAECgcIEQAAAA==.',
Sn='Snaggletooth:BAAANQADCggIDgAAAA==.',
So='Soongxiao:BAAANQAECgYICwAAAA==.Sorce:BAAANQADCgYIDAABNQAECggIKgAKAOcaAA==.Sovan:BAAANQADCgYIBgAAAA==.Sovix:BAAANQAECgQIBAAAAA==.Sovo:BAABNQAECn8eAAIEAAgKBBLDsQAeAgAEAAgKBBLDsQAeAgABNQAFFAUIFAAbACYNAA==.',
Sp='Sprick:BAAANQADCgQIBQAAAA==.',
Sq='Squanchi:BAAANQADCggIEgAAAA==.',
St='Steaknquake:BAABNQAECn8eAAIKAAcKMB9lPwBgAgAKAAcKMB9lPwBgAgAAAA==.',
Su='Sumdumfun:BAAANQAECgEIAQAAAA==.Sunflower:BAAANQAECgIIAgAAAA==.',
Sy='Sybri:BAABNQAECn8cAAICAAkKcB2YHwAXAwACAAkKcB2YHwAXAwAAAA==.Sylvandel:BAAANQAECgYIEQAAAA==.Sylvrshado:BAAANQADCgQIBAAAAA==.',
Sz='Szilvia:BAAANQAECgQIBAAAAA==.',
Ta='Talanthar:BAABNQAECn8fAAIEAAcKXh0nkQBdAgAEAAcKXh0nkQBdAgAAAA==.Talarrond:BAAANQAECggICAAAAA==.',
Te='Teagen:BAABNQAECn8bAAMcAAgKgwmwNQBpAQAcAAgKgwmwNQBpAQAIAAUKBAZViACtAAAAAA==.Teilssra:BAAANQAECgQIBwAAAA==.',
Th='Thalius:BAAANQAECgUIEwAAAA==.Thamachine:BAAANQADCgMIAwAAAA==.Thebear:BAAANQADCgcICgAAAA==.Thóridal:BAAANQAECgIIAgAAAA==.',
To='Tomexo:BAAANQAECgEIAQAAAA==.Toomanydeths:BAABNQAECn8bAAITAAgKbwlVYABuAQATAAgKbwlVYABuAQAAAA==.',
Tr='Trickledeath:BAAANQABCgIIAgAAAA==.Trunx:BAAANQAECgEIAQABNQAECgkJIwAPAC0jAA==.',
Tu='Tuminettlpot:BAAANQADCgYIBgAAAA==.',
Un='Untz:BAAANQADCgYICgAAAA==.',
Ur='Ursusmanny:BAAANQADCgEIAQAAAA==.',
Va='Vanthrall:BAAANQAECgUIEgAAAA==.',
Ve='Velysa:BAABNQAECn8bAAISAAcKNxAxLAB3AQASAAcKNxAxLAB3AQAAAA==.',
Wa='Warseeker:BAABNQAECn8bAAMYAAkKLxZbbQDUAQAYAAcK2hNbbQDUAQAKAAIKPRU+6gCRAAAAAA==.',
We='Weatherworn:BAAANQAECgQIBwAAAA==.Wera:BAAANQAECgUICQAAAA==.Weslow:BAAANQADCgMIAwAAAA==.',
Wi='Wirhlanir:BAAANQADCgMIAwAAAA==.',
Wo='Woodcrest:BAAANQADCgcIBwAAAA==.Wopertinger:BAAANQADCgMIAwABNQAECgYIDgABAAAAAA==.',
['Ës']='Ëscänör:BAABNQAECn8ZAAIOAAgKdRQImADuAQAOAAgKdRQImADuAQAAAA==.',
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
