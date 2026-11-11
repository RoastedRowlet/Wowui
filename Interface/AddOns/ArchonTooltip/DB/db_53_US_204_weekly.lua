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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','Unknown-Unknown','Paladin-Retribution','Warlock-Destruction','Mage-Arcane','Warrior-Fury','Warrior-Arms','Druid-Balance','Druid-Restoration','Paladin-Holy','Shaman-Restoration','Warrior-Protection','DeathKnight-Frost','Hunter-Survival','Monk-Mistweaver','Shaman-Elemental','Mage-Fire','Rogue-Assassination','Rogue-Subtlety','Paladin-Protection','DeathKnight-Blood','Priest-Holy','DeathKnight-Unholy','Mage-Frost','Warlock-Affliction','Monk-Windwalker','Rogue-Outlaw','Druid-Guardian','Warlock-Demonology','Druid-Feral','Shaman-Enhancement','DemonHunter-Havoc',}
local provider = {region='US',realm='SteamwheedleCartel',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aalwein:BAABNQAECn8gAAIBAAkK1BsGXQD2AQABAAkK1BsGXQD2AQAAAA==.',
Ad='Adehn:BAAANQAECgMIAwAAAA==.',
Al='Alfrus:BAAANQADCggICwAAAA==.',
Am='Amarii:BAABNQAECn8jAAICAAgK0gMAMQDXAAACAAgK0gMAMQDXAAAAAA==.',
An='Andent:BAAANQABCgYICAABNQADCggIFgADAAAAAA==.',
Ap='Appostle:BAAANQADCggIGAAAAA==.',
Ar='Ara:BAABNQAECn8mAAIBAAoK4haEQQCmAgABAAoK4haEQQCmAgAAAA==.',
As='Asteryn:BAAANQAECgIIAwAAAA==.',
Av='Avigar:BAAANQAECgUIEQAAAA==.',
Ba='Bangan:BAAANQAECgEIAQAAAA==.Banisary:BAAANQADCgYIBgAAAA==.',
Be='Belakor:BAABNQAECn8eAAIEAAkK4Ar+pgBqAQAEAAkK4Ar+pgBqAQAAAA==.Bep:BAAANQAECgEIAQABNQAECgoKLAAFAGkVAA==.Bepragosa:BAABNQAECn8sAAIFAAoKaRXIBgCdAgAFAAoKaRXIBgCdAgAAAA==.',
Bi='Bighammer:BAAANQAECgUIBQABNQAFFAgIGgAGACAUAA==.Binpharteen:BAAANQADCgcICwAAAA==.Birgitè:BAAANQADCgYIEwAAAA==.',
Bl='Blaque:BAABNQAECn8iAAIBAAoK5wzZYgDnAQABAAoK5wzZYgDnAQAAAA==.',
Bo='Bootylightz:BAAANQABCgUIAQAAAA==.Bowguytome:BAACNQAFFH8FAAICAAUK+CWBBAArAgACAAUK+CWBBAArAgA1AAQKfyUAAgIACAqGJmkXAJ4CAAIACAqGJmkXAJ4CAAAA.Bozo:BAAANQAECgIIBgAAAA==.',
Br='Brownbelt:BAABNQAECn85AAMHAAoKsxH+CgAWAgAHAAoKsxH+CgAWAgAIAAUKuANbEgG4AAAAAA==.Brîn:BAABNQAECn8lAAIFAAYKwwkoLQAYAQAFAAYKwwkoLQAYAQAAAA==.',
Bu='Buteihunter:BAACNQAFFH8HAAIBAAQKfRdqDwD+AAABAAQKfRdqDwD+AAA1AAQKf0QAAgEACgo/JccEAGUDAAEACgo/JccEAGUDAAAA.Buteilock:BAAANQAECggIDAABNQAFFAQIBwABAH0XAA==.Butherts:BAAANQAECggIEwAAAA==.',
Bw='Bwonshifty:BAAANQAECggIBQAAAA==.',
Ch='Chelali:BAABNQAECn8oAAIIAAoK9RldVACNAgAIAAoK9RldVACNAgAAAA==.Chicharrone:BAABNQAECn82AAMJAAoK/AfkYgBDAQAJAAoK/AfkYgBDAQAKAAUKngSDUACjAAAAAA==.Chizaru:BAABNQAECn8lAAILAAoK/R1qHAACAwALAAoK/R1qHAACAwAAAA==.Chlorophyll:BAAANQAECgYIBgAAAA==.Chyntobelt:BAAANQAECgQIDwABNQAECgoKOQAHALMRAA==.',
Cr='Cryption:BAAANQAECggIEAAAAA==.',
Da='Daelyn:BAAANQAECgQIBAAAAA==.',
De='Deafenned:BAAANQADCggIDQAAAA==.Deafnight:BAAANQADCggIDAABNQADCggIDQADAAAAAA==.Deliquesce:BAAANQADCggICgAAAA==.Deäthtoall:BAAANQADCgUIBQAAAA==.',
Di='Diamante:BAACNQAFFH8IAAIMAAQKzQwAFAAEAQAMAAQKzQwAFAAEAQA1AAQKf0oAAgwACgraG/kfAKkCAAwACgraG/kfAKkCAAAA.Dignifeyed:BAAANQADCgcIBwAAAA==.Discoelsi:BAAANQAECgMIAwAAAA==.',
Dr='Dracarnoir:BAAANQADCgcIEAAAAA==.Dragonite:BAABNQAECn80AAMIAAoKUyNqDQCOAwAIAAoKUyNqDQCOAwANAAMK2xGyNACQAAAAAA==.Drakemichael:BAAANQADCgUIBQAAAA==.Dremu:BAABNQAECn8xAAIJAAkKThyqHgD3AQAJAAkKThyqHgD3AQAAAA==.',
Du='Duskhunter:BAAANQAECgUIDwAAAA==.',
Dy='Dysraxis:BAAANQABCggIDgAAAA==.',
['Dï']='Dïnhö:BAAANQAECgMIBQAAAA==.',
El='Elahna:BAAANQAECgQIBwAAAA==.Elamaun:BAABNQAECn8vAAILAAgK0Rj0MgBBAgALAAgK0Rj0MgBBAgAAAA==.Eltiana:BAABNQAECn8fAAIGAAkKJAm92QDUAQAGAAkKJAm92QDUAQAAAA==.',
Em='Emisa:BAAANQADCgYIBwAAAA==.',
En='Enochen:BAAANQAECggIBQAAAA==.',
Ep='Ephex:BAAANQADCgUIBAAAAA==.Ephriest:BAAANQADCgMIBAABNQAECgYIDgADAAAAAA==.Ephury:BAAANQAECgYIDgAAAA==.Epic:BAAANQADCgIIAgAAAA==.',
Er='Ertraz:BAAANQAECgEIAQAAAA==.',
Et='Ethahell:BAAANQADCgEIAQAAAA==.',
Ev='Evhomang:BAAANQAECgYIBAABNQAFFAoKLgAOAMghAA==.',
Fa='Faelyna:BAABNQAECn8uAAIPAAkK7gwqBwCYAQAPAAkK7gwqBwCYAQAAAA==.',
Fe='Fearbear:BAAANQADCgUIAwAAAA==.',
Fo='Forged:BAABNQAECn9BAAIEAAkKHCQkFwBoAwAEAAkKHCQkFwBoAwAAAA==.',
Fu='Fufufu:BAAANQADCgQIBAABNQAFFAQICAAMAM0MAA==.',
Gi='Githyanki:BAAANQADCggIEQAAAA==.',
Go='Goop:BAAANQADCgUIBQABNQAECgoKKAAQAGIiAA==.',
Gr='Grangshammy:BAABNQAECn8rAAIRAAoKbRdqLwAHAgARAAoKbRdqLwAHAgAAAA==.Grimskull:BAAANQADCgYIBwAAAA==.Grimvault:BAAANQAECgIIAgABNQAECgkJOgAGAAEdAA==.',
Ha='Hacelian:BAAANQADCgYIBgAAAA==.Haeltree:BAAANQAECgMIAwABNQAECgkJNQASAMUXAA==.Han:BAABNQAECn8gAAMTAAkKKBP0KwA4AgATAAkK9hL0KwA4AgAUAAYKNQyIMQAxAQAAAA==.Hargoroth:BAAANQADCggICwAAAA==.',
He='Henudorf:BAAANQAECgYIDQAAAA==.',
Ho='Holyverdict:BAAANQADCgQIAwAAAA==.',
Ic='Icaina:BAABNQAECn9DAAIMAAkKKSJRFgAeAwAMAAkKKSJRFgAeAwAAAA==.',
In='Incinderella:BAAANQAECgUICwABNQAECgMIAgADAAAAAA==.Infernnape:BAAANQAECgEIAgAAAA==.',
Ja='Jadefire:BAAANQAECggIDQAAAA==.Jakana:BAAANQAECgMIAgAAAA==.Jathy:BAAANQADCgQIBAAAAA==.',
Je='Jeisa:BAABNQAECn81AAMVAAgK8AoqMgDbAAAEAAYK7QYuEgEAAQAVAAgK4AkqMgDbAAAAAA==.',
Jh='Jhedu:BAAANQAECgYIBgAAAA==.',
Ju='Juanns:BAAANQADCgcJBwAAAA==.',
Ka='Kaj:BAABNQAECn8fAAILAAkKPBI3UQAnAgALAAkKPBI3UQAnAgAAAA==.Kallotera:BAAANQADCggICAAAAA==.Kalrou:BAAANQADCgUIBQABNQAECgoKKwAWABYjAA==.Kastoria:BAAANQADCgYICwAAAA==.Katnipp:BAABNQAECn82AAIBAAoKCBpaJgCXAgABAAoKCBpaJgCXAgAAAA==.Kaylazune:BAABNQAECn8yAAIXAAgKRBQzVQDQAQAXAAgKRBQzVQDQAQAAAA==.',
Ke='Keltara:BAAANQAECgMIBAAAAA==.',
Kh='Kharybdis:BAAANQAECgEIAQAAAA==.Khrala:BAABNQAECn8rAAIYAAoK8hC5HgDZAQAYAAoK8hC5HgDZAQAAAA==.',
Ki='Kindlana:BAAANQADCggIDwAAAA==.Kiye:BAACNQAFFH8ZAAIBAAcKyRNLBQAAAgABAAcKyRNLBQAAAgA1AAQKfzsAAgEACgqyI8gSAPkCAAEACgqyI8gSAPkCAAAA.',
Ku='Kushan:BAAANQADCgEIAQAAAA==.Kuuro:BAABNQAECn81AAIMAAgKKBc/PQAKAgAMAAgKKBc/PQAKAgAAAA==.',
Ky='Kydori:BAAANQADCgUIBQABNQAECggILgAZAEIPAA==.',
La='Lattylock:BAAANQADCgUIBQAAAA==.Lattymag:BAABNQAECn8hAAIGAAcKtwGRDwGKAAAGAAcKtwGRDwGKAAAAAA==.Laughystabby:BAAANQADCgcIDgAAAA==.',
Le='Leibniz:BAABNQAECn8xAAIaAAgKch2MBQBoAgAaAAgKch2MBQBoAgAAAA==.Leisa:BAABNQAECn81AAIBAAgKdg8EjwDrAQABAAgKdg8EjwDrAQAAAA==.Lelwindae:BAABNQAECn8cAAMEAAgKfQhq2QASAQAEAAgKfQhq2QASAQAVAAEKAADAdQAnAAAAAA==.',
Li='Lifemoon:BAAANQAECgUIDAAAAA==.Lildangerus:BAAANQADCgYIDgAAAA==.Liminara:BAEBNQAECn8jAAIEAAoKJBG3rADGAQAEAAoKJBG3rADGAQABNQAFFAcIEQABAFIcAA==.Linaste:BAABNQAECn8hAAMEAAoKRx3zZABsAgAEAAoKRx3zZABsAgALAAMKARUbpADGAAAAAA==.',
Lo='Lohha:BAAANQADCgIIAgAAAA==.',
Lu='Lulu:BAACNQAFFH8kAAIbAAkKMSEuAACyAwAbAAkKMSEuAACyAwA1AAQKfyQAAhsACQp2Jo4DAJ4DABsACQp2Jo4DAJ4DAAAA.Lumaria:BAAANQAECgQIDAAAAA==.',
Ly='Lyllia:BAAANQAECgYIDgAAAA==.Lynoia:BAAANQADCggICAAAAA==.',
Ma='Makunel:BAAANQAECgIIAgAAAA==.Mandevu:BAAANQAECgEIAQAAAA==.Mangan:BAAANQAECgEJAwAAAA==.Manknus:BAABNQAECn9AAAIHAAoKQRJBCQDyAQAHAAoKQRJBCQDyAQAAAA==.Manthrax:BAABNQAECn9DAAIMAAoKlBIjNAA2AgAMAAoKlBIjNAA2AgAAAA==.Mathiyis:BAAANQABCgcICwABNQAECgQIBwADAAAAAA==.',
Me='Mexecutioner:BAABNQAECn9FAAMIAAoKuhAgTgACAgAIAAoKuhAgTgACAgANAAEK8gbcRAAqAAAAAA==.',
Mi='Milkadin:BAAANQADCgIIAgAAAA==.Mirzan:BAAANQADCgEIAQAAAA==.Missmolt:BAABNQAECn86AAIcAAgKGCBmBADJAgAcAAgKGCBmBADJAgAAAA==.',
Mo='Mogok:BAABNQAECn85AAIVAAgK/AwAJAA5AQAVAAgK/AwAJAA5AQAAAA==.Molting:BAAANQAECgMJBwAAAA==.Moonkin:BAAANQABCgQIBQAAAA==.',
Mu='Musclegary:BAABNQAECn9IAAMRAAoK+yLPCgCQAwARAAoK+yLPCgCQAwAMAAEK9RpUFAFBAAAAAA==.',
My='Mykie:BAAANQADCggIDwAAAA==.Mylor:BAABNQAECn82AAIVAAkKEhyUDQA/AgAVAAkKEhyUDQA/AgAAAA==.Myrddral:BAABNQAECn8vAAIWAAgKMR6+JwCyAQAWAAgKMR6+JwCyAQAAAA==.Mystifeyed:BAABNQAECn8kAAIdAAoKZA6BHwChAQAdAAoKZA6BHwChAQAAAA==.',
['Mü']='Mürsaat:BAABNQAECn8tAAIEAAkKNwrOsQBWAQAEAAkKNwrOsQBWAQAAAA==.',
Na='Nagrad:BAAANQAECgEIAQAAAA==.Namrekcah:BAAANQAECgEIAQABNQAFFAgIHgAWAE8aAA==.',
Ni='Nilaya:BAAANQADCggICAAAAA==.Nimbledragon:BAAANQADCgYIDQAAAA==.',
Nt='Ntayu:BAABNQAECn81AAIBAAgKVAbkrwA3AQABAAgKVAbkrwA3AQAAAA==.',
Ol='Olizia:BAABNQAECn81AAIOAAoKvxkxHABXAgAOAAoKvxkxHABXAgAAAA==.',
Oo='Oopsipoopied:BAAANQADCgcIBwAAAA==.',
Op='Opex:BAABNQAECn88AAIBAAoKpBEsVQALAgABAAoKpBEsVQALAgAAAA==.',
Or='Oril:BAAANQADCgMIAwAAAA==.',
Os='Osairis:BAAANQADCgUIBQAAAA==.',
Ot='Otura:BAAANQADCgIIAgAAAA==.',
Pe='Perkyblade:BAABNQAECn9JAAMHAAoKMBMpCQD1AQAHAAoKMBMpCQD1AQANAAMKUwUhPgBKAAAAAA==.',
Pl='Planeswalker:BAAANQAECgUIEAAAAA==.',
Po='Poxic:BAAANQAECgIJBAAAAA==.',
Pr='Primalbooty:BAAANQADCgMIAwABNQAFFAQIBwABAH0XAA==.Protection:BAAANQAECgIIAQAAAA==.',
Ps='Psychotic:BAAANQADCgMIAwAAAA==.',
Ra='Ravinar:BAABNQAECn81AAISAAkKxRdRAgDPAQASAAkKxRdRAgDPAQAAAA==.Raynorama:BAAANQAECgIIAgABNQAECgoKPAALAHkgAA==.Razzle:BAABNQAECn8sAAIeAAoKHBT9UgBdAgAeAAoKHBT9UgBdAgAAAA==.Raàm:BAAANQADCgQIBAAAAA==.',
Re='Relia:BAAANQADCgMIAwAAAA==.',
Ri='Rizzstoned:BAAANQADCggIEwAAAA==.',
Ro='Romulus:BAABNQAECn8wAAUKAAgKOhYPJQCtAQAKAAgKOhYPJQCtAQAfAAYK2BJuGQAoAQAdAAUK2AUaUQBqAAAJAAEKAACGxAAeAAAAAA==.',
Sa='Sarbarola:BAAANQADCggIJAAAAA==.',
Se='Seraid:BAAANQADCggIIgAAAA==.',
Sh='Shallbedo:BAAANQAECgUIBgABNQAECgoKPgAgALQSAA==.Shallmagi:BAAANQADCgUIBQABNQAECgoKPgAgALQSAA==.Shmalexia:BAAANQABCgEJAQAAAA==.',
Si='Siatraler:BAAANQAECgYIDwAAAA==.Sigarette:BAACNQAFFH8eAAIWAAgKTxoiAwBnAgAWAAgKTxoiAwBnAgA1AAQKf1MAAhYACgpJJU0EAKwDABYACgpJJU0EAKwDAAAA.Sinardi:BAABNQAECn8qAAIhAAcK/guLSwBzAQAhAAcK/guLSwBzAQAAAA==.',
Sk='Skoob:BAAANQAECgEIAQAAAA==.Skymane:BAAANQAECggIEgAAAA==.',
Sn='Snaggletooth:BAAANQADCggIEwAAAA==.',
So='Soongxiao:BAAANQAECgcIDAAAAA==.Sorce:BAAANQADCgYIDAABNQAFFAQICAAMAM0MAA==.Sovan:BAAANQADCgYIBgAAAA==.Sovix:BAAANQAECgQIBAAAAA==.Sovo:BAABNQAECn8yAAIGAAkKnRZiRQAvAgAGAAkKnRZiRQAvAgABNQAFFAcIFwAeAG0MAA==.',
Sp='Sprick:BAAANQADCgQIBQAAAA==.',
St='Steaknquake:BAABNQAECn81AAIMAAkKMh7MGwDFAgAMAAkKMh7MGwDFAgAAAA==.',
Su='Sumdumfun:BAAANQAECgUIBgAAAA==.Sunflower:BAAANQAECgMIAgAAAA==.',
Sy='Sybri:BAABNQAECn8iAAIBAAkKcB1oIAAWAwABAAkKcB1oIAAWAwAAAA==.Sylvandel:BAABNQAECn8uAAICAAgKChDfHgBmAQACAAgKChDfHgBmAQAAAA==.Sylvandelle:BAAANQADCgUIBQAAAA==.Sylvrshado:BAAANQADCgQIBAAAAA==.',
Sz='Szilvia:BAAANQAECgQIBAAAAA==.',
Ta='Talanthar:BAABNQAECn86AAIGAAkKAR1XTQAZAgAGAAkKAR1XTQAZAgAAAA==.Talarrond:BAABNQAECn8gAAIhAAgKBwwKNABlAQAhAAgKBwwKNABlAQAAAA==.',
Te='Teagen:BAABNQAECn8rAAMKAAkKFhEgHgDyAQAKAAkKFhEgHgDyAQAJAAUKBAayiQCtAAAAAA==.Teilssra:BAAANQAECgQIBwAAAA==.Tekkadhar:BAAANQADCgEIAQAAAA==.',
Th='Thalius:BAABNQAECn8kAAIYAAgKpAw/NgAzAQAYAAgKpAw/NgAzAQAAAA==.Thamachine:BAAANQADCgMIAwAAAA==.Thóridal:BAAANQAECgIIAgAAAA==.',
To='Toomanydeths:BAABNQAECn8qAAIWAAkKhQrzQQAoAQAWAAkKhQrzQQAoAQAAAA==.',
Tr='Trickledeath:BAAANQABCgIIAgAAAA==.Trunx:BAAANQAECgEIAQABNQAECgoKKAAQAGIiAA==.',
Ts='Tsaraph:BAAANQAECgYIBwAAAA==.',
Tu='Tuminettlpot:BAAANQADCgYIBgAAAA==.',
Un='Untz:BAAANQADCgYICgAAAA==.',
Ur='Ursusmanny:BAAANQADCgEIAQAAAA==.',
Va='Vanthrall:BAAANQAECgUIEgAAAA==.',
Ve='Velestia:BAAANQAECgUIBwAAAA==.Velithel:BAAANQADCgMIAwAAAA==.Velysa:BAABNQAECn8xAAIVAAkKgRC/IABSAQAVAAkKgRC/IABSAQAAAA==.Verstümmeln:BAAANQADCgYIBgAAAA==.',
Vu='Vudrer:BAAANQABCgUIAwAAAA==.',
Wa='Warseeker:BAABNQAECn8cAAMRAAkKLxbwbgDTAQARAAcK2hPwbgDTAQAMAAIKPRX47ACRAAAAAA==.',
We='Weatherworn:BAABNQAECn8gAAIMAAcK4xYNUQC3AQAMAAcK4xYNUQC3AQAAAA==.Wera:BAAANQAECgYIDQAAAA==.Weslow:BAAANQADCgMIAwAAAA==.',
Wi='Wirhlanir:BAAANQADCgMIAwAAAA==.',
Wo='Woodcrest:BAAANQADCggIDwAAAA==.Wopertinger:BAAANQAECggICQABNQAECggIFAAEAPwGAA==.',
Yo='Yoril:BAAANQAECgEIAQAAAA==.',
Ze='Zenaara:BAAANQAECggIDwAAAA==.',
['Ës']='Ëscänör:BAABNQAECn8ZAAIEAAgKdRR+mgDuAQAEAAgKdRR+mgDuAQAAAA==.',
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
