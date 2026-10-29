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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','Unknown-Unknown','Warlock-Destruction','Mage-Arcane','Warrior-Fury','Warrior-Arms','Druid-Balance','Paladin-Holy','Shaman-Restoration','Warrior-Protection','DeathKnight-Frost','Hunter-Survival','Paladin-Retribution','Monk-Mistweaver','Shaman-Elemental','Rogue-Assassination','Rogue-Subtlety','Paladin-Protection','DeathKnight-Blood','Priest-Holy','DeathKnight-Unholy','Mage-Frost','Warlock-Affliction','Monk-Windwalker','Rogue-Outlaw','Druid-Guardian','Mage-Fire','Warlock-Demonology','Druid-Restoration','Shaman-Enhancement','DemonHunter-Havoc',}
local provider = {region='US',realm='SteamwheedleCartel',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aalwein:BAABNQAECn8dAAIBAAgKLhypagA+AgABAAgKLhypagA+AgAAAA==.',
Ad='Adehn:BAAANQADCgIIAgAAAA==.',
Al='Alfrus:BAAANQADCggICwAAAA==.',
Am='Amarii:BAABNQAECn8WAAICAAcK5wPiKgC0AAACAAcK5wPiKgC0AAAAAA==.',
An='Andent:BAAANQABCgYICAABNQADCggIFgADAAAAAA==.',
Ap='Appostle:BAAANQADCggIEgAAAA==.',
Ar='Ara:BAABNQAECn8mAAIBAAoK4haEQQCmAgABAAoK4haEQQCmAgAAAA==.',
As='Asteryn:BAAANQAECgIIAwAAAA==.',
Av='Avigar:BAAANQAECgYIDwAAAA==.',
Ba='Bangan:BAAANQAECgEIAQAAAA==.Banisary:BAAANQADCgYIBgAAAA==.',
Be='Belakor:BAAANQAECgUIDwAAAA==.Bep:BAAANQAECgEIAQABNQAECgoKKQAEABUTAA==.Bepragosa:BAABNQAECn8pAAIEAAoKFRPIBgCdAgAEAAoKFRPIBgCdAgAAAA==.',
Bi='Bighammer:BAAANQAECgUIBQABNQAFFAgIGAAFACAUAA==.Binpharteen:BAAANQADCgcICwAAAA==.',
Bl='Blaque:BAABNQAECn8dAAIBAAgKfg1XYQB7AQABAAgKfg1XYQB7AQAAAA==.',
Bo='Bowguytome:BAACNQAFFH8FAAICAAUK+CWBBAArAgACAAUK+CWBBAArAgA1AAQKfyIAAgIACAp6JmkXAJ4CAAIACAp6JmkXAJ4CAAAA.Bozo:BAAANQAECgIIBgAAAA==.',
Br='Brownbelt:BAABNQAECn8wAAMGAAoKsRD+CgAWAgAGAAoKsRD+CgAWAgAHAAUKuANbEgG4AAAAAA==.Brîn:BAABNQAECn8fAAIEAAYKmwmuDgCpAAAEAAYKmwmuDgCpAAAAAA==.',
Bu='Buteihunter:BAABNQAECn8zAAIBAAkKCiNLBQA6AwABAAkKCiNLBQA6AwAAAA==.Buteilock:BAAANQAECgQIBAABNQAECgkJMwABAAojAA==.Butherts:BAAANQAECggIEwAAAA==.',
Bw='Bwonshifty:BAAANQAECggIBQAAAA==.',
Ch='Chelali:BAABNQAECn8nAAIHAAoK9RldVACNAgAHAAoK9RldVACNAgAAAA==.Chicharrone:BAABNQAECn8tAAIIAAkK8wbkYgBDAQAIAAkK8wbkYgBDAQAAAA==.Chizaru:BAABNQAECn8hAAIJAAkKax1qHAACAwAJAAkKax1qHAACAwAAAA==.Chlorophyll:BAAANQAECgYIBgAAAA==.Chyntobelt:BAAANQAECgQIDAABNQAECgoKMAAGALEQAA==.',
Cr='Cryption:BAAANQAECggIEAAAAA==.',
Da='Daelyn:BAAANQAECgIIAgAAAA==.',
De='Deafenned:BAAANQADCggIDQAAAA==.Deafnight:BAAANQADCggIDAABNQADCggIDQADAAAAAA==.Deliquesce:BAAANQADCggICgAAAA==.Deäthtoall:BAAANQADCgUIBQAAAA==.',
Di='Diamante:BAABNQAECn86AAIKAAoKzxrUFwCEAgAKAAoKzxrUFwCEAgAAAA==.Dignifeyed:BAAANQADCgcIBwAAAA==.Discoelsi:BAAANQAECgMIAwAAAA==.',
Dr='Dracarnoir:BAAANQADCgcIEAAAAA==.Dragonite:BAABNQAECn8tAAMHAAoKUyNqDQCOAwAHAAoKUyNqDQCOAwALAAMK2xGyNACQAAAAAA==.Drakemichael:BAAANQADCgUIBQAAAA==.Dremu:BAABNQAECn8pAAIIAAgKrhxZLQByAgAIAAgKrhxZLQByAgAAAA==.',
Du='Duskhunter:BAAANQAECgUIDwAAAA==.',
Dy='Dysraxis:BAAANQABCggIDgAAAA==.',
['Dï']='Dïnhö:BAAANQAECgMIBQAAAA==.',
El='Elahna:BAAANQAECgQIBwAAAA==.Elamaun:BAABNQAECn8qAAIJAAgK/BffIABAAgAJAAgK/BffIABAAgAAAA==.Eltiana:BAABNQAECn8fAAIFAAkKJAm92QDUAQAFAAkKJAm92QDUAQAAAA==.',
Em='Emisa:BAAANQADCgYIBwAAAA==.',
Ep='Ephex:BAAANQADCgUIBAAAAA==.Ephriest:BAAANQADCgMIBAABNQAECgYIDgADAAAAAA==.Ephury:BAAANQAECgYIDgAAAA==.Epic:BAAANQADCgIIAgAAAA==.',
Er='Ertraz:BAAANQADCgEIAQAAAA==.',
Ev='Evhomang:BAAANQAECgYIBAABNQAFFAoKJQAMAEcfAA==.',
Fa='Faelyna:BAABNQAECn8pAAINAAcKKw27CAC8AQANAAcKKw27CAC8AQAAAA==.',
Fe='Fearbear:BAAANQADCgUIAwAAAA==.',
Fo='Forged:BAABNQAECn9AAAIOAAkKHCQkFwBoAwAOAAkKHCQkFwBoAwAAAA==.',
Fu='Fufufu:BAAANQADCgQIBAABNQAECgoKOgAKAM8aAA==.',
Gi='Githyanki:BAAANQADCggIEQAAAA==.',
Go='Goop:BAAANQADCgUIBQABNQAECgoKJgAPAGIiAA==.',
Gr='Grangshammy:BAABNQAECn8iAAIQAAoKrhX4IgDoAQAQAAoKrhX4IgDoAQAAAA==.Grimskull:BAAANQADCgMIAwAAAA==.Grimvault:BAAANQAECgIIAgABNQAECggILQAFAModAA==.',
Ha='Hacelian:BAAANQADCgYIBgAAAA==.Han:BAABNQAECn8gAAMRAAkKKBP0KwA4AgARAAkK9hL0KwA4AgASAAYKNQyIMQAxAQAAAA==.Hargoroth:BAAANQADCggICwAAAA==.',
He='Henudorf:BAAANQAECgYIDQAAAA==.',
Ho='Holyverdict:BAAANQADCgQIAwAAAA==.',
Ic='Icaina:BAABNQAECn81AAIKAAkKXiFRFgAeAwAKAAkKXiFRFgAeAwAAAA==.',
In='Incinderella:BAAANQAECgQIBAABNQAECgMIAgADAAAAAA==.Infernnape:BAAANQAECgEIAgAAAA==.',
Ja='Jadefire:BAAANQAECgYICAAAAA==.Jakana:BAAANQAECgMIAgAAAA==.Jathy:BAAANQADCgQIBAAAAA==.',
Je='Jeisa:BAABNQAECn8oAAMTAAcKoQvpKAC/AAAOAAYK7QYuEgEAAQATAAcKWwrpKAC/AAAAAA==.',
Jh='Jhedu:BAAANQAECgYIBgAAAA==.',
Ju='Juanns:BAAANQADCgcJBwAAAA==.',
Ka='Kaj:BAABNQAECn8fAAIJAAkKPBI3UQAnAgAJAAkKPBI3UQAnAgAAAA==.Kallotera:BAAANQADCggICAAAAA==.Kalrou:BAAANQADCgUIBQABNQAECgoKKwAUABYjAA==.Kastoria:BAAANQADCgUICAAAAA==.Katnipp:BAABNQAECn8iAAIBAAkKixQvRwDJAQABAAkKixQvRwDJAQAAAA==.Kaylazune:BAABNQAECn8lAAIVAAcKqxL1UQBqAQAVAAcKqxL1UQBqAQAAAA==.',
Kh='Kharybdis:BAAANQAECgEIAQAAAA==.Khrala:BAABNQAECn8eAAIWAAkKuBAPJwBCAQAWAAkKuBAPJwBCAQAAAA==.',
Ki='Kindlana:BAAANQADCggICwAAAA==.Kiye:BAACNQAFFH8VAAIBAAcKvxNLBQAAAgABAAcKvxNLBQAAAgA1AAQKfzkAAgEACgq4Iv0HABoDAAEACgq4Iv0HABoDAAAA.',
Ku='Kushan:BAAANQADCgEIAQAAAA==.Kuuro:BAABNQAECn8oAAIKAAcKBBlVMwDSAQAKAAcKBBlVMwDSAQAAAA==.',
Ky='Kydori:BAAANQADCgUIBQABNQAECgcIIQAXAKsQAA==.',
La='Lattylock:BAAANQADCgUIBQAAAA==.Lattymag:BAABNQAECn8VAAIFAAYKngGRCQFXAAAFAAYKngGRCQFXAAAAAA==.Laughystabby:BAAANQADCgcIDgAAAA==.',
Le='Leibniz:BAABNQAECn8kAAIYAAcKIyCMBQBoAgAYAAcKIyCMBQBoAgAAAA==.Leisa:BAABNQAECn8oAAIBAAcK7xAEjwDrAQABAAcK7xAEjwDrAQAAAA==.Lelwindae:BAAANQAECgQIDwAAAA==.',
Li='Lifemoon:BAAANQAECgQICAAAAA==.Lildangerus:BAAANQADCgYIDgAAAA==.Liminara:BAEBNQAECn8hAAIOAAoKJBG3rADGAQAOAAoKJBG3rADGAQABNQAFFAcIEQABAFIcAA==.Linaste:BAABNQAECn8cAAMOAAoKbhjzZABsAgAOAAoKbhjzZABsAgAJAAMKghNEngB8AAAAAA==.',
Lo='Lohha:BAAANQADCgIIAgAAAA==.',
Lu='Lulu:BAACNQAFFH8kAAIZAAkKMSEuAACyAwAZAAkKMSEuAACyAwA1AAQKfyQAAhkACQp2Jo4DAJ4DABkACQp2Jo4DAJ4DAAAA.Lumaria:BAAANQAECgQIDAAAAA==.',
Ly='Lyllia:BAAANQAECgYIDgAAAA==.Lynoia:BAAANQADCggICAAAAA==.',
Ma='Makunel:BAAANQAECgIIAgAAAA==.Mandevu:BAAANQAECgEIAQAAAA==.Mangan:BAAANQAECgEJAwAAAA==.Manknus:BAABNQAECn8xAAIGAAkKnRCqCACNAQAGAAkKnRCqCACNAQAAAA==.Manthrax:BAABNQAECn8wAAIKAAoK5AxvMgDWAQAKAAoK5AxvMgDWAQAAAA==.Mathiyis:BAAANQABCgcICwABNQAECgQIBwADAAAAAA==.',
Me='Mexecutioner:BAABNQAECn8yAAMHAAoKAA66QADMAQAHAAoKAA66QADMAQALAAEK8gZ6MwAtAAAAAA==.',
Mi='Milkadin:BAAANQADCgIIAgAAAA==.Mirzan:BAAANQADCgEIAQAAAA==.Missmolt:BAABNQAECn8tAAIaAAgKGCBmBADJAgAaAAgKGCBmBADJAgAAAA==.',
Mo='Mogok:BAABNQAECn8nAAITAAcKWg3CHgAFAQATAAcKWg3CHgAFAQAAAA==.Molting:BAAANQAECgMJBwAAAA==.Moonkin:BAAANQABCgQIBQAAAA==.',
Mu='Musclegary:BAABNQAECn88AAMQAAoKGR/PCgCQAwAQAAoKGR/PCgCQAwAKAAEK9RpUFAFBAAAAAA==.',
My='Mykie:BAAANQADCggIDwAAAA==.Mylor:BAABNQAECn8tAAITAAkKwRuFFABfAgATAAkKwRuFFABfAgAAAA==.Myrddral:BAABNQAECn8nAAIUAAcKQR7mNwApAgAUAAcKQR7mNwApAgAAAA==.Mystifeyed:BAABNQAECn8jAAIbAAoKZA6BHwChAQAbAAoKZA6BHwChAQAAAA==.',
['Mü']='Mürsaat:BAABNQAECn8hAAIOAAcKbglq3gBeAQAOAAcKbglq3gBeAQAAAA==.',
Na='Nagrad:BAAANQAECgEIAQAAAA==.Namrekcah:BAAANQAECgEIAQABNQAFFAcIGwAUAMYaAA==.',
Ni='Nilaya:BAAANQADCggICAAAAA==.Nimbledragon:BAAANQADCgYIDQAAAA==.',
Nt='Ntayu:BAABNQAECn8oAAIBAAcKjAUZmgD8AAABAAcKjAUZmgD8AAAAAA==.',
Ol='Olizia:BAABNQAECn8mAAIMAAoK1RabLQA0AgAMAAoK1RabLQA0AgAAAA==.',
Oo='Oopsipoopied:BAAANQADCgcIBwAAAA==.',
Op='Opex:BAABNQAECn8qAAIBAAkKJw5vnwDIAQABAAkKJw5vnwDIAQAAAA==.',
Or='Oril:BAAANQADCgMIAwAAAA==.',
Os='Osairis:BAAANQADCgUIBQAAAA==.',
Ot='Otura:BAAANQADCgIIAgAAAA==.',
Pe='Perkyblade:BAABNQAECn81AAMGAAkKAxIJCACeAQAGAAkKAxIJCACeAQALAAMKUwUhPgBKAAAAAA==.',
Pl='Planeswalker:BAAANQAECgQIDAAAAA==.',
Po='Poxic:BAAANQAECgIJBAAAAA==.',
Pr='Primalbooty:BAAANQADCgMIAwABNQAECgkJMwABAAojAA==.Protection:BAAANQAECgIIAQAAAA==.',
Ps='Psychotic:BAAANQADCgMIAwAAAA==.',
Ra='Ravinar:BAABNQAECn8sAAIcAAgKPhhjAgAmAgAcAAgKPhhjAgAmAgAAAA==.Razzle:BAABNQAECn8qAAIdAAoKMBL9UgBdAgAdAAoKMBL9UgBdAgAAAA==.Raàm:BAAANQADCgQIBAAAAA==.',
Re='Relia:BAAANQADCgMIAwAAAA==.',
Ri='Rizzstoned:BAAANQADCggIEwAAAA==.',
Ro='Romulus:BAABNQAECn8jAAMeAAcK+RXxHQByAQAeAAcK+RXxHQByAQAIAAEKAACGxAAeAAAAAA==.',
Sa='Sarbarola:BAAANQADCgcIIwAAAA==.',
Se='Seraid:BAAANQADCggIIgAAAA==.',
Sh='Shallbedo:BAAANQAECgEIAQABNQAECgoKMwAfAE4PAA==.Shallmagi:BAAANQADCgUIBQABNQAECgoKMwAfAE4PAA==.Shmalexia:BAAANQABCgEJAQAAAA==.',
Si='Siatraler:BAAANQAECgYICwAAAA==.Sigarette:BAACNQAFFH8bAAIUAAcKxhoiAwBnAgAUAAcKxhoiAwBnAgA1AAQKf0IAAhQACgpFJU0EAKwDABQACgpFJU0EAKwDAAAA.Sinardi:BAABNQAECn8qAAIgAAcK/gsKNQAGAQAgAAcK/gsKNQAGAQAAAA==.',
Sk='Skoob:BAAANQADCgEIAQAAAA==.Skymane:BAAANQAECggIEgAAAA==.',
Sn='Snaggletooth:BAAANQADCggIEwAAAA==.',
So='Soongxiao:BAAANQAECgcIDAAAAA==.Sorce:BAAANQADCgYIDAABNQAECgoKOgAKAM8aAA==.Sovan:BAAANQADCgYIBgAAAA==.Sovix:BAAANQAECgQIBAAAAA==.Sovo:BAABNQAECn8wAAIFAAkKnRYGKQBPAgAFAAkKnRYGKQBPAgABNQAFFAcIFwAdAG0MAA==.',
Sp='Sprick:BAAANQADCgQIBQAAAA==.',
St='Steaknquake:BAABNQAECn8sAAIKAAgK5x77FgCNAgAKAAgK5x77FgCNAgAAAA==.',
Su='Sumdumfun:BAAANQAECgEIAQAAAA==.Sunflower:BAAANQAECgMIAgAAAA==.',
Sy='Sybri:BAABNQAECn8gAAIBAAkKcB1oIAAWAwABAAkKcB1oIAAWAwAAAA==.Sylvandel:BAABNQAECn8hAAICAAcKXBHKGgAtAQACAAcKXBHKGgAtAQAAAA==.Sylvandelle:BAAANQADCgUIBQAAAA==.Sylvrshado:BAAANQADCgQIBAAAAA==.',
Sz='Szilvia:BAAANQAECgQIBAAAAA==.',
Ta='Talanthar:BAABNQAECn8tAAIFAAgKyh3DTgDCAQAFAAgKyh3DTgDCAQAAAA==.Talarrond:BAABNQAECn8UAAIgAAgKvwhjKgBJAQAgAAgKvwhjKgBJAQAAAA==.',
Te='Teagen:BAABNQAECn8dAAMeAAkKNwlNNgBpAQAeAAkKNwlNNgBpAQAIAAUKBAayiQCtAAAAAA==.Teilssra:BAAANQAECgQIBwAAAA==.Tekkadhar:BAAANQADCgEIAQAAAA==.',
Th='Thalius:BAABNQAECn8iAAIWAAcK2QycMAAGAQAWAAcK2QycMAAGAQAAAA==.Thamachine:BAAANQADCgMIAwAAAA==.Thebear:BAAANQADCgcICgAAAA==.Thóridal:BAAANQAECgIIAgAAAA==.',
To='Toomanydeths:BAABNQAECn8cAAIUAAkKNgklYQBtAQAUAAkKNgklYQBtAQAAAA==.',
Tr='Trickledeath:BAAANQABCgIIAgAAAA==.Trunx:BAAANQAECgEIAQABNQAECgoKJgAPAGIiAA==.',
Ts='Tsaraph:BAAANQADCgYICwAAAA==.',
Tu='Tuminettlpot:BAAANQADCgYIBgAAAA==.',
Un='Untz:BAAANQADCgYICgAAAA==.',
Ur='Ursusmanny:BAAANQADCgEIAQAAAA==.',
Va='Vanthrall:BAAANQAECgUIEgAAAA==.',
Ve='Velestia:BAAANQAECgUIBwAAAA==.Velithel:BAAANQADCgMIAwAAAA==.Velysa:BAABNQAECn8nAAITAAcKNxDFLAB2AQATAAcKNxDFLAB2AQAAAA==.',
Vu='Vudrer:BAAANQABCgUIAwAAAA==.',
Wa='Warseeker:BAABNQAECn8bAAMQAAkKLxbwbgDTAQAQAAcK2hPwbgDTAQAKAAIKPRX47ACRAAAAAA==.',
We='Weatherworn:BAAANQAECgUIEQAAAA==.Wera:BAAANQAECgcIDAAAAA==.Weslow:BAAANQADCgMIAwAAAA==.',
Wi='Wirhlanir:BAAANQADCgMIAwAAAA==.',
Wo='Woodcrest:BAAANQADCggIDwAAAA==.',
Yo='Yoril:BAAANQAECgEIAQAAAA==.',
['Ës']='Ëscänör:BAABNQAECn8ZAAIOAAgKdRR+mgDuAQAOAAgKdRR+mgDuAQAAAA==.',
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
