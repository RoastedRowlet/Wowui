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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','Unknown-Unknown','Shaman-Elemental','Paladin-Retribution','Warlock-Destruction','Mage-Arcane','Warrior-Fury','Warrior-Arms','Druid-Balance','Paladin-Holy','Shaman-Restoration','Warrior-Protection','DeathKnight-Frost','Hunter-Survival','Monk-Mistweaver','Rogue-Assassination','Rogue-Subtlety','Paladin-Protection','DeathKnight-Blood','Priest-Holy','DeathKnight-Unholy','Mage-Frost','Warlock-Affliction','Monk-Windwalker','Rogue-Outlaw','Druid-Guardian','Mage-Fire','Warlock-Demonology','Druid-Restoration','Druid-Feral','Shaman-Enhancement','DemonHunter-Havoc',}
local provider = {region='US',realm='SteamwheedleCartel',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aalwein:BAABNQAECn8gAAIBAAkK1BtlTAD4AQABAAkK1BtlTAD4AQAAAA==.',
Ad='Adehn:BAAANQAECgEIAQAAAA==.',
Al='Alfrus:BAAANQADCggICwAAAA==.',
Am='Amarii:BAABNQAECn8cAAICAAcKHgSaLQDLAAACAAcKHgSaLQDLAAAAAA==.',
An='Andent:BAAANQADCgEIAQABNQADCggIFwADAAAAAA==.',
Ap='Appostle:BAAANQADCggIGQAAAA==.',
Ar='Ara:BAABNQAECn8mAAIBAAoK4haEQQCmAgABAAoK4haEQQCmAgAAAA==.Ardiir:BAAANQAECgEIAQABNQAECgoKKAAEAG8WAA==.',
As='Asteryn:BAAANQAECgIIAwAAAA==.',
Av='Avigar:BAAANQAECgYIEAAAAA==.',
Ba='Bangan:BAAANQAECgEIAQAAAA==.Banisary:BAAANQADCgYIBgAAAA==.',
Be='Belakor:BAABNQAECn8YAAIFAAgK2grEsAAvAQAFAAgK2grEsAAvAQAAAA==.Bep:BAAANQAECgEIAQABNQAECgoKKgAGAA4UAA==.Bepragosa:BAABNQAECn8qAAIGAAoKDhTIBgCdAgAGAAoKDhTIBgCdAgAAAA==.',
Bi='Bighammer:BAAANQAECgUIBQABNQAFFAgIGQAHACAUAA==.Binpharteen:BAAANQADCgcICwAAAA==.',
Bl='Blaque:BAABNQAECn8fAAIBAAkKfg2xZwCsAQABAAkKfg2xZwCsAQAAAA==.',
Bo='Bowguytome:BAACNQAFFH8FAAICAAUK+CWBBAArAgACAAUK+CWBBAArAgA1AAQKfyQAAgIACAqGJmkXAJ4CAAIACAqGJmkXAJ4CAAAA.Bozo:BAAANQAECgIIBgAAAA==.',
Br='Brownbelt:BAABNQAECn83AAMIAAoKZRH+CgAWAgAIAAoKZRH+CgAWAgAJAAUKuANbEgG4AAAAAA==.Brîn:BAABNQAECn8lAAIGAAYKwwmAEgCqAAAGAAYKwwmAEgCqAAAAAA==.',
Bu='Buteihunter:BAACNQAFFH8HAAIBAAQKfRfJDAADAQABAAQKfRfJDAADAQA1AAQKfzoAAgEACQpiJBwIADgDAAEACQpiJBwIADgDAAAA.Buteilock:BAAANQAECggIDQABNQAFFAQIBwABAH0XAA==.Butherts:BAAANQAECggIEwAAAA==.',
Bw='Bwonshifty:BAAANQAECggICQAAAA==.',
Ch='Chelali:BAABNQAECn8nAAIJAAoK9RldVACNAgAJAAoK9RldVACNAgAAAA==.Chicharrone:BAABNQAECn8xAAIKAAoK/AfkYgBDAQAKAAoK/AfkYgBDAQAAAA==.Chizaru:BAABNQAECn8lAAILAAoK/R1qHAACAwALAAoK/R1qHAACAwAAAA==.Chlorophyll:BAAANQAECgYIBwAAAA==.Chyntobelt:BAAANQAECgQIDwABNQAECgoKNwAIAGURAA==.',
Cr='Cryption:BAAANQAECggIEgAAAA==.',
Da='Daelyn:BAAANQAECgMIBAAAAA==.',
De='Deafenned:BAAANQADCggIDQAAAA==.Deafnight:BAAANQADCggIDAABNQADCggIDQADAAAAAA==.Deliquesce:BAAANQADCggIDQAAAA==.Deäthtoall:BAAANQADCgUIBQAAAA==.',
Di='Diamante:BAACNQAFFH8FAAIMAAMKBwyBFgC+AAAMAAMKBwyBFgC+AAA1AAQKf0MAAgwACgpTGyEbALECAAwACgpTGyEbALECAAAA.Dignifeyed:BAAANQADCgcIBwAAAA==.Discoelsi:BAAANQAECgMIAwAAAA==.',
Dr='Dracarnoir:BAAANQADCgcIEAAAAA==.Dragonite:BAABNQAECn80AAMJAAoKUyNqDQCOAwAJAAoKUyNqDQCOAwANAAMK2xGyNACQAAAAAA==.Drakemichael:BAAANQADCgUIBQAAAA==.Dremu:BAABNQAECn8qAAIKAAgKrhxZLQByAgAKAAgKrhxZLQByAgAAAA==.',
Du='Duskhunter:BAAANQAECgUIDwAAAA==.',
Dy='Dysraxis:BAAANQADCgEIAQAAAA==.',
['Dï']='Dïnhö:BAAANQAECgMIBQAAAA==.',
El='Elahna:BAAANQAECgQIBwAAAA==.Elamaun:BAABNQAECn8vAAILAAgK0Ri3KgBNAgALAAgK0Ri3KgBNAgAAAA==.Eltiana:BAABNQAECn8fAAIHAAkKJAm92QDUAQAHAAkKJAm92QDUAQAAAA==.',
Em='Emisa:BAAANQADCgYICAAAAA==.',
En='Enochen:BAAANQAECggIBwAAAA==.',
Ep='Ephex:BAAANQADCgUIBAAAAA==.Ephriest:BAAANQADCgMIBQABNQAECgYIDgADAAAAAA==.Ephury:BAAANQAECgYIDgAAAA==.Epic:BAAANQADCgIIAgAAAA==.',
Er='Ertraz:BAAANQAECgEIAgAAAA==.',
Ev='Evhomang:BAAANQAECgYIBAABNQAFFAoKKgAOAMYgAA==.',
Fa='Faelyna:BAABNQAECn8sAAIPAAkK8QtSBgCZAQAPAAkK8QtSBgCZAQAAAA==.',
Fe='Fearbear:BAAANQADCgUIAwAAAA==.',
Fo='Forged:BAABNQAECn9BAAIFAAkKHCQkFwBoAwAFAAkKHCQkFwBoAwAAAA==.',
Fu='Fufufu:BAAANQADCgQIBAABNQAFFAMIBQAMAAcMAA==.',
Gi='Githyanki:BAAANQADCggIEQAAAA==.',
Go='Goop:BAAANQADCgUIBgABNQAECgoKJgAQAGIiAA==.',
Gr='Grangshammy:BAABNQAECn8oAAIEAAoKbxaUKwD5AQAEAAoKbxaUKwD5AQAAAA==.Grimskull:BAAANQADCgYIBwAAAA==.Grimvault:BAAANQAECgIIAgABNQAECggIMwAHAModAA==.',
['Gä']='Gäbothär:BAAANQADCgEIAQAAAA==.',
Ha='Hacelian:BAAANQADCgYIBgAAAA==.Han:BAABNQAECn8gAAMRAAkKKBP0KwA4AgARAAkK9hL0KwA4AgASAAYKNQyIMQAxAQAAAA==.Hargoroth:BAAANQADCggICwAAAA==.',
He='Henudorf:BAAANQAECgYIDQAAAA==.',
Ho='Holyverdict:BAAANQADCgQIAwAAAA==.',
Ic='Icaina:BAABNQAECn89AAIMAAkKKSJRFgAeAwAMAAkKKSJRFgAeAwAAAA==.',
In='Incinderella:BAAANQAECgUIDAABNQAECgMIAgADAAAAAA==.Infernnape:BAAANQAECgEIAgAAAA==.',
Ja='Jadefire:BAAANQAECggIDgAAAA==.Jakana:BAAANQAECgMIAgAAAA==.Jathy:BAAANQADCgQIBQAAAA==.',
Je='Jeisa:BAABNQAECn8uAAMTAAcKoQsoMgDAAAAFAAYK7QYuEgEAAQATAAcKWwooMgDAAAAAAA==.',
Jh='Jhedu:BAAANQAECgYIBgAAAA==.',
Ju='Juanns:BAAANQADCgcJBwAAAA==.',
Ka='Kaj:BAABNQAECn8fAAILAAkKPBI3UQAnAgALAAkKPBI3UQAnAgAAAA==.Kallotera:BAAANQADCggICAAAAA==.Kalrou:BAAANQADCgUIBQABNQAECgoKKwAUABYjAA==.Kalyptra:BAAANQADCgEIAQAAAA==.Kastoria:BAAANQADCgYIDAAAAA==.Katnipp:BAABNQAECn8sAAIBAAkKdxapNwA5AgABAAkKdxapNwA5AgAAAA==.Kaylazune:BAABNQAECn8rAAIVAAcKsBPCYgB8AQAVAAcKsBPCYgB8AQAAAA==.',
Ke='Keltara:BAAANQAECgEIAQAAAA==.',
Kh='Kharybdis:BAAANQAECgEIAQAAAA==.Khrala:BAABNQAECn8mAAIWAAoKChD6GwDTAQAWAAoKChD6GwDTAQAAAA==.',
Ki='Kindlana:BAAANQADCggIEAAAAA==.Kiye:BAACNQAFFH8ZAAIBAAcKyRPrAwCUAQABAAcKyRPrAwCUAQA1AAQKfzoAAgEACgqyI5cNAAgDAAEACgqyI5cNAAgDAAAA.',
Kl='Kliforr:BAAANQADCgEIAQAAAA==.',
Ku='Kushan:BAAANQADCgEIAQAAAA==.Kuuro:BAABNQAECn8uAAIMAAcKoxm7PQDuAQAMAAcKoxm7PQDuAQAAAA==.',
Ky='Kydori:BAAANQADCgUIBQABNQAECgcIJwAXAKsQAA==.',
La='Lattylock:BAAANQADCgUIBQAAAA==.Lattymag:BAABNQAECn8bAAIHAAcKqwGYBAGGAAAHAAcKqwGYBAGGAAAAAA==.Laughystabby:BAAANQADCgcIEAAAAA==.',
Le='Leibniz:BAABNQAECn8qAAIYAAcKIyCMBQBoAgAYAAcKIyCMBQBoAgAAAA==.Leisa:BAABNQAECn8uAAIBAAcK7xAEjwDrAQABAAcK7xAEjwDrAQAAAA==.Lelwindae:BAABNQAECn8cAAMFAAgKfQj2vgAWAQAFAAgKfQj2vgAWAQATAAEKAADAdQAnAAAAAA==.',
Li='Lifemoon:BAAANQAECgUIEAAAAA==.Lildangerus:BAAANQADCgYIDgAAAA==.Liminara:BAEBNQAECn8iAAIFAAoKJBG3rADGAQAFAAoKJBG3rADGAQABNQAFFAcIEQABAFIcAA==.Linaste:BAABNQAECn8gAAMFAAoKBxzzZABsAgAFAAoKBxzzZABsAgALAAMKARUbmADHAAAAAA==.',
Lo='Lohha:BAAANQADCgIIAgAAAA==.',
Lu='Lulu:BAACNQAFFH8kAAIZAAkKMSEuAACyAwAZAAkKMSEuAACyAwA1AAQKfyQAAhkACQp2Jo4DAJ4DABkACQp2Jo4DAJ4DAAAA.Lumaria:BAAANQAECgQIDAAAAA==.',
Ly='Lyllia:BAAANQAECgYIDgAAAA==.Lynoia:BAAANQADCggICAAAAA==.Lynora:BAAANQADCgEIAQAAAA==.',
Ma='Makunel:BAAANQAECgIIAwAAAA==.Mandevu:BAAANQAECgEIAQAAAA==.Mangan:BAAANQAECgEJAwAAAA==.Manknus:BAABNQAECn84AAIIAAkKRRHFDADtAQAIAAkKRRHFDADtAQAAAA==.Manthrax:BAABNQAECn85AAIMAAoK5AwnRADRAQAMAAoK5AwnRADRAQAAAA==.Mathiyis:BAAANQADCgEIAQABNQAECgQIBwADAAAAAA==.',
Me='Mexecutioner:BAABNQAECn87AAMJAAoKDA/FUADaAQAJAAoKDA/FUADaAQANAAEK8gZcPQAtAAAAAA==.',
Mi='Milkadin:BAAANQADCgIIAgAAAA==.Mirzan:BAAANQADCgEIAQAAAA==.Missmolt:BAABNQAECn8zAAIaAAgKGCBmBADJAgAaAAgKGCBmBADJAgAAAA==.',
Mo='Mogok:BAABNQAECn8yAAITAAgK+AxmIAA2AQATAAgK+AxmIAA2AQAAAA==.Molting:BAAANQAECgMJBwAAAA==.Moonkin:BAAANQADCgEIAgAAAA==.',
Mu='Musclegary:BAABNQAECn9GAAMEAAoK8iLPCgCQAwAEAAoK8iLPCgCQAwAMAAEK9RpUFAFBAAAAAA==.',
My='Mykie:BAAANQADCggIEQAAAA==.Mylor:BAABNQAECn8tAAITAAkKwRuFFABfAgATAAkKwRuFFABfAgAAAA==.Myrddral:BAABNQAECn8tAAIUAAcKQR7mNwApAgAUAAcKQR7mNwApAgAAAA==.Mystifeyed:BAABNQAECn8kAAIbAAoKZA6BHwChAQAbAAoKZA6BHwChAQAAAA==.',
['Mü']='Mürsaat:BAABNQAECn8qAAIFAAkKqQktqwA4AQAFAAkKqQktqwA4AQAAAA==.',
Na='Nagrad:BAAANQAECgEIAQAAAA==.Namrekcah:BAAANQAECgEIAQABNQAFFAcIHAAUAMYaAA==.',
Ni='Nilaya:BAAANQADCggICAAAAA==.Nimbledragon:BAAANQADCgYIDQAAAA==.',
Nt='Ntayu:BAABNQAECn8uAAIBAAcKlwUYuQD8AAABAAcKlwUYuQD8AAAAAA==.',
Ol='Olizia:BAABNQAECn8uAAIOAAoKOBiNHAAyAgAOAAoKOBiNHAAyAgAAAA==.',
Oo='Oopsipoopied:BAAANQADCgcIBwAAAA==.',
Op='Opex:BAABNQAECn8xAAIBAAkKghEXdQCLAQABAAkKghEXdQCLAQAAAA==.',
Or='Oril:BAAANQADCgMIAwAAAA==.',
Os='Osairis:BAAANQADCgUIBQAAAA==.',
Ot='Otura:BAAANQADCgIIAgAAAA==.',
Pe='Perkyblade:BAABNQAECn8/AAMIAAoKSRLTCADRAQAIAAoKSRLTCADRAQANAAMKUwUhPgBKAAAAAA==.',
Pl='Planeswalker:BAAANQAECgUIEQAAAA==.',
Po='Poxic:BAAANQAECgIJBAAAAA==.',
Pr='Primalbooty:BAAANQADCgMIAwABNQAFFAQIBwABAH0XAA==.Protection:BAAANQAECgIIAQAAAA==.',
Ps='Psychotic:BAAANQADCgMIAwAAAA==.',
Ra='Ravinar:BAABNQAECn80AAIcAAkKxRfOAQDcAQAcAAkKxRfOAQDcAQAAAA==.Raynorama:BAAANQAECgIIAgABNQAECgoKOQALAFcgAA==.Razzle:BAABNQAECn8sAAIdAAoKHBT9UgBdAgAdAAoKHBT9UgBdAgAAAA==.Raàm:BAAANQADCgQIBQAAAA==.',
Re='Relia:BAAANQADCgMIAwAAAA==.',
Ri='Rizzstoned:BAAANQADCggIFQAAAA==.',
Ro='Romulus:BAABNQAECn8pAAQeAAcK+RUJKABkAQAeAAcK+RUJKABkAQAfAAYK2BIxFQAuAQAKAAEKAACGxAAeAAAAAA==.',
Sa='Sarbarola:BAAANQADCggIJwAAAA==.',
Se='Seraid:BAAANQADCggIIwAAAA==.',
Sh='Shallbedo:BAAANQAECgQICAABNQAECgoKNwAgAOMQAA==.Shallmagi:BAAANQADCgUIBQABNQAECgoKNwAgAOMQAA==.Shmalexia:BAAANQADCgEIAQAAAA==.',
Si='Siatraler:BAAANQAECgYIEQAAAA==.Sigarette:BAACNQAFFH8cAAIUAAcKxhoiAwBnAgAUAAcKxhoiAwBnAgA1AAQKf08AAhQACgpFJU0EAKwDABQACgpFJU0EAKwDAAAA.Sinardi:BAABNQAECn8qAAIhAAcK/guLSwBzAQAhAAcK/guLSwBzAQAAAA==.',
Sk='Skoob:BAAANQAECgEIAQAAAA==.Skymane:BAAANQAECggIEgAAAA==.',
Sn='Snaggletooth:BAAANQADCggIEwAAAA==.',
So='Soongxiao:BAAANQAECggIDgAAAA==.Sorce:BAAANQADCgYIDAABNQAFFAMIBQAMAAcMAA==.Sovan:BAAANQADCgYIBgAAAA==.Sovix:BAAANQAECgQIBAAAAA==.Sovo:BAABNQAECn8yAAIHAAkKnRZtPAA1AgAHAAkKnRZtPAA1AgABNQAFFAcIFwAdAG0MAA==.',
Sp='Sprick:BAAANQADCgQIBQAAAA==.',
Sq='Squanchi:BAAANQAECgEIAQAAAA==.',
St='Steaknquake:BAABNQAECn80AAIMAAkKMh4MFwDSAgAMAAkKMh4MFwDSAgAAAA==.',
Su='Sumdumfun:BAAANQAECgUIBgAAAA==.Sunflower:BAAANQAECgMIAgAAAA==.',
Sy='Sybri:BAABNQAECn8iAAIBAAkKcB1oIAAWAwABAAkKcB1oIAAWAwAAAA==.Sylvandel:BAABNQAECn8nAAICAAcKXRFmIAAvAQACAAcKXRFmIAAvAQAAAA==.Sylvandelle:BAAANQADCgUIBQAAAA==.Sylvrshado:BAAANQADCgQIBAAAAA==.',
Sz='Szilvia:BAAANQAECgQIBAAAAA==.',
Ta='Talanthar:BAABNQAECn8zAAIHAAgKyh01XADXAQAHAAgKyh01XADXAQAAAA==.Talarrond:BAABNQAECn8bAAIhAAgKfAoKMQBSAQAhAAgKfAoKMQBSAQAAAA==.',
Te='Teagen:BAABNQAECn8kAAMeAAkKFhHDGQDxAQAeAAkKFhHDGQDxAQAKAAUKBAayiQCtAAAAAA==.Teilssra:BAAANQAECgQIBwAAAA==.Tekkadhar:BAAANQADCgEIAQAAAA==.',
Th='Thalius:BAABNQAECn8iAAIWAAcK2QxyOwD8AAAWAAcK2QxyOwD8AAAAAA==.Thamachine:BAAANQADCgMIBAAAAA==.Thóridal:BAAANQAECgIIAgAAAA==.',
To='Tome:BAAANQAFFAcIAQABNQAFFAgIBQACAPglAA==.Toomanydeths:BAABNQAECn8jAAIUAAkKUQpbPQAiAQAUAAkKUQpbPQAiAQAAAA==.',
Tr='Trickledeath:BAAANQADCgEIAQAAAA==.Trunx:BAAANQAECgEIAQABNQAECgoKJgAQAGIiAA==.',
Ts='Tsaraph:BAAANQAECgYIBgAAAA==.',
Tt='Ttaug:BAAANQAECgEIAQAAAA==.',
Tu='Tuminettlpot:BAAANQADCgYIBgAAAA==.',
Un='Untz:BAAANQADCgYICwAAAA==.',
Ur='Ursusmanny:BAAANQADCgEIAQAAAA==.',
Va='Vanthrall:BAAANQAECgUIEgAAAA==.',
Ve='Velestia:BAAANQAECgUICAAAAA==.Velithel:BAAANQADCgMIAwAAAA==.Velysa:BAABNQAECn8vAAITAAkKgRA5HABYAQATAAkKgRA5HABYAQAAAA==.',
Vu='Vudrer:BAAANQABCgUIAwAAAA==.',
Wa='Warseeker:BAABNQAECn8bAAMEAAkKLxbwbgDTAQAEAAcK2hPwbgDTAQAMAAIKPRX47ACRAAAAAA==.',
We='Weatherworn:BAABNQAECn8aAAIMAAcKaxULUACgAQAMAAcKaxULUACgAQAAAA==.Wera:BAAANQAECgYIEgAAAA==.Weslow:BAAANQADCgMIAwAAAA==.',
Wi='Wirhlanir:BAAANQADCgMIAwAAAA==.',
Wo='Woodcrest:BAAANQADCggIEAAAAA==.Wopertinger:BAAANQAECggIBwABNQAECggIFAAFAPwGAA==.',
Yo='Yoril:BAAANQAECgEIAQAAAA==.',
Ze='Zenaara:BAAANQAECgYICAAAAA==.',
['Ës']='Ëscänör:BAABNQAECn8ZAAIFAAgKdRR+mgDuAQAFAAgKdRR+mgDuAQAAAA==.',
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
