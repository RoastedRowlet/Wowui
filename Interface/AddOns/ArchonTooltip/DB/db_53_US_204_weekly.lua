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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','Unknown-Unknown','Warlock-Destruction','Mage-Arcane','Warrior-Fury','Warrior-Arms','Druid-Balance','Paladin-Holy','Shaman-Restoration','Warrior-Protection','DeathKnight-Frost','Hunter-Survival','Paladin-Retribution','Monk-Mistweaver','Shaman-Elemental','Rogue-Assassination','Rogue-Subtlety','Paladin-Protection','DeathKnight-Blood','Priest-Holy','DeathKnight-Unholy','Warlock-Affliction','Monk-Windwalker','Rogue-Outlaw','Druid-Guardian','Mage-Fire','Warlock-Demonology','Druid-Restoration','Shaman-Enhancement','DemonHunter-Havoc',}
local provider = {region='US',realm='SteamwheedleCartel',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aalwein:BAABNQAECn8XAAIBAAgKjxipagA+AgABAAgKjxipagA+AgAAAA==.',
Ad='Adehn:BAAANQADCgEIAQAAAA==.',
Al='Alfrus:BAAANQADCggICwAAAA==.',
Am='Amarii:BAABNQAECn8WAAICAAcK5wODGADDAAACAAcK5wODGADDAAAAAA==.',
An='Andent:BAAANQABCgYICAABNQADCggIFgADAAAAAA==.',
Ap='Appostle:BAAANQADCggIEgAAAA==.',
Ar='Ara:BAABNQAECn8mAAIBAAoK4haEQQCmAgABAAoK4haEQQCmAgAAAA==.',
As='Asteryn:BAAANQAECgIIAwAAAA==.',
Av='Avigar:BAAANQAECgYIDwAAAA==.',
Ba='Bangan:BAAANQAECgEIAQAAAA==.Banisary:BAAANQADCgYIBgAAAA==.',
Be='Belakor:BAAANQAECgUICwAAAA==.Bep:BAAANQAECgEIAQABNQAECgoKJgAEAGISAA==.Bepragosa:BAABNQAECn8mAAIEAAoKYhLIBgCdAgAEAAoKYhLIBgCdAgAAAA==.',
Bi='Bighammer:BAAANQAECgUIBQABNQAFFAcIFgAFALcWAA==.Binpharteen:BAAANQADCgcICwAAAA==.',
Bl='Blaque:BAABNQAECn8bAAIBAAgKSg0IJQCFAQABAAgKSg0IJQCFAQAAAA==.',
Bo='Bowguytome:BAACNQAFFH8FAAICAAUK+CWBBAArAgACAAUK+CWBBAArAgA1AAQKfxQAAgIACApzJmkXAJ4CAAIACApzJmkXAJ4CAAAA.Bozo:BAAANQAECgIIBAAAAA==.',
Br='Brownbelt:BAABNQAECn8oAAMGAAoKlQ/+CgAWAgAGAAoKlQ/+CgAWAgAHAAUKuANbEgG4AAAAAA==.Brîn:BAABNQAECn8ZAAIEAAYKjAgoLQAYAQAEAAYKjAgoLQAYAQAAAA==.',
Bu='Buteihunter:BAABNQAECn8iAAIBAAkKECHmGAA2AwABAAkKECHmGAA2AwAAAA==.Buteilock:BAAANQAECgQIBAABNQAECgkJIgABABAhAA==.Butherts:BAAANQAECggIDAAAAA==.',
Bw='Bwonshifty:BAAANQAECggIBQAAAA==.',
Ch='Chelali:BAABNQAECn8kAAIHAAkKCBpdVACNAgAHAAkKCBpdVACNAgAAAA==.Chicharrone:BAABNQAECn8qAAIIAAkKPQbkYgBDAQAIAAkKPQbkYgBDAQAAAA==.Chizaru:BAABNQAECn8gAAIJAAkKax1qHAACAwAJAAkKax1qHAACAwAAAA==.Chyntobelt:BAAANQAECgQIDAABNQAECgoKKAAGAJUPAA==.',
Cr='Cryption:BAAANQAECggIEAAAAA==.',
Da='Daelyn:BAAANQAECgIIAgAAAA==.',
De='Deafenned:BAAANQADCggIDQAAAA==.Deafnight:BAAANQADCggIDAABNQADCggIDQADAAAAAA==.Deliquesce:BAAANQADCggICgAAAA==.',
Di='Diamante:BAABNQAECn8wAAIKAAoKARnfPgBkAgAKAAoKARnfPgBkAgAAAA==.Dignifeyed:BAAANQADCgcIBwAAAA==.Discoelsi:BAAANQAECgMIAwAAAA==.',
Dr='Dracarnoir:BAAANQADCgcIEAAAAA==.Dragonite:BAABNQAECn8rAAMHAAoKByJqDQCOAwAHAAoKByJqDQCOAwALAAMK2xGyNACQAAAAAA==.Drakemichael:BAAANQADCgUIBQAAAA==.Dremu:BAABNQAECn8jAAIIAAgKrhxZLQByAgAIAAgKrhxZLQByAgAAAA==.',
Du='Duskhunter:BAAANQAECgUICgAAAA==.',
Dy='Dysraxis:BAAANQABCggICgAAAA==.',
['Dï']='Dïnhö:BAAANQAECgMIBQAAAA==.',
El='Elahna:BAAANQAECgQIBwAAAA==.Elamaun:BAABNQAECn8iAAIJAAcKshb3FQClAQAJAAcKshb3FQClAQAAAA==.Eltiana:BAABNQAECn8fAAIFAAkKJAm92QDUAQAFAAkKJAm92QDUAQAAAA==.',
Em='Emisa:BAAANQADCgYIBwAAAA==.',
Ep='Ephex:BAAANQADCgUIBAAAAA==.Ephriest:BAAANQADCgMIBAABNQAECgYIDgADAAAAAA==.Ephury:BAAANQAECgYIDgAAAA==.Epic:BAAANQADCgIIAgAAAA==.',
Ev='Evhomang:BAAANQAECgYIBAABNQAFFAgIGwAMACEcAA==.',
Fa='Faelyna:BAABNQAECn8jAAINAAcKKw27CAC8AQANAAcKKw27CAC8AQAAAA==.',
Fe='Fearbear:BAAANQADCgUIAwAAAA==.',
Fo='Forged:BAABNQAECn83AAIOAAkKHCQkFwBoAwAOAAkKHCQkFwBoAwAAAA==.',
Fu='Fufufu:BAAANQADCgQIBAABNQAECgoKMAAKAAEZAA==.',
Gi='Githyanki:BAAANQADCggIEQAAAA==.',
Go='Goop:BAAANQADCgUIBQABNQAECgoKJgAPAGIiAA==.',
Gr='Grangshammy:BAABNQAECn8XAAIQAAgKrhRdegC0AQAQAAgKrhRdegC0AQAAAA==.Grimskull:BAAANQADCgMIAwAAAA==.Grimvault:BAAANQAECgEIAQABNQAECggIJwAFAModAA==.',
Ha='Hacelian:BAAANQADCgYIBgAAAA==.Han:BAABNQAECn8gAAMRAAkKKBP0KwA4AgARAAkK9hL0KwA4AgASAAYKNQyIMQAxAQAAAA==.Hargoroth:BAAANQADCggICwAAAA==.',
He='Henudorf:BAAANQAECgYIDQAAAA==.',
Ho='Holyverdict:BAAANQADCgQIAwAAAA==.',
Ic='Icaina:BAABNQAECn8tAAIKAAkKnx9RFgAeAwAKAAkKnx9RFgAeAwAAAA==.',
In='Infernnape:BAAANQAECgEIAgAAAA==.',
Ja='Jathy:BAAANQADCgQIBAAAAA==.',
Je='Jeisa:BAABNQAECn8jAAMTAAcKoQt3GQDBAAAOAAYK7QYuEgEAAQATAAcKWwp3GQDBAAAAAA==.',
Jh='Jhedu:BAAANQAECgYIBgAAAA==.',
Ju='Juanns:BAAANQADCgcJBwAAAA==.',
Ka='Kaj:BAABNQAECn8fAAIJAAkKPBI3UQAnAgAJAAkKPBI3UQAnAgAAAA==.Kallotera:BAAANQADCggICAAAAA==.Kalrou:BAAANQADCgUIBQABNQAECgoKKAAUAIcgAA==.Kastoria:BAAANQADCgUIBQAAAA==.Katnipp:BAABNQAECn8bAAIBAAkKWQ7tkwDhAQABAAkKWQ7tkwDhAQAAAA==.Kaylazune:BAABNQAECn8fAAIVAAcKMBEGIQB/AQAVAAcKMBEGIQB/AQAAAA==.',
Kh='Kharybdis:BAAANQAECgEIAQAAAA==.Khrala:BAABNQAECn8WAAIWAAYKbxO0ZQB6AQAWAAYKbxO0ZQB6AQAAAA==.',
Ki='Kindlana:BAAANQADCggICwAAAA==.Kiye:BAACNQAFFH8UAAIBAAYK5hZLBQAAAgABAAYK5hZLBQAAAgA1AAQKfzAAAgEACQpZI3sdACIDAAEACQpZI3sdACIDAAAA.',
Ku='Kushan:BAAANQADCgEIAQAAAA==.Kuuro:BAABNQAECn8iAAIKAAcKnBWqFgChAQAKAAcKnBWqFgChAQAAAA==.',
La='Lattymag:BAAANQAECgUIDgAAAA==.Laughystabby:BAAANQADCgcIDgAAAA==.',
Le='Leibniz:BAABNQAECn8eAAIXAAcKIyBVAQCzAQAXAAcKIyBVAQCzAQAAAA==.Leisa:BAABNQAECn8iAAIBAAcK7xAiOwBCAQABAAcK7xAiOwBCAQAAAA==.Lelwindae:BAAANQAECgQICwAAAA==.',
Li='Lifemoon:BAAANQAECgQIBAAAAA==.Lildangerus:BAAANQADCgYIDgAAAA==.Liminara:BAEBNQAECn8fAAIOAAoKcA+3rADGAQAOAAoKcA+3rADGAQABNQAFFAcIEQABAFIcAA==.Linaste:BAABNQAECn8ZAAMOAAoK2xTzZABsAgAOAAoK2xTzZABsAgAJAAMKghNNZQCGAAAAAA==.',
Lo='Lohha:BAAANQADCgIIAgAAAA==.',
Lu='Lulu:BAACNQAFFH8kAAIYAAkKMSEuAACyAwAYAAkKMSEuAACyAwA1AAQKfyQAAhgACQp2Jo4DAJ4DABgACQp2Jo4DAJ4DAAAA.Lumaria:BAAANQAECgQIDAAAAA==.',
Ly='Lyllia:BAAANQAECgYIDgAAAA==.Lynoia:BAAANQADCggICAAAAA==.',
Ma='Makunel:BAAANQAECgIIAgAAAA==.Mandevu:BAAANQAECgEIAQAAAA==.Mangan:BAAANQAECgEJAwAAAA==.Manknus:BAABNQAECn8pAAIGAAgKjRDFDADtAQAGAAgKjRDFDADtAQAAAA==.Manthrax:BAABNQAECn8nAAIKAAkKwQsJIQBkAQAKAAkKwQsJIQBkAQAAAA==.Mathiyis:BAAANQABCgcICwABNQAECgQIBwADAAAAAA==.',
Me='Mexecutioner:BAABNQAECn8oAAMHAAoK7wuONgA8AQAHAAoK7wuONgA8AQALAAEK8gaCJAAvAAAAAA==.',
Mi='Milkadin:BAAANQADCgIIAgAAAA==.Mirzan:BAAANQADCgEIAQAAAA==.Missmolt:BAABNQAECn8nAAIZAAgKGCAbAQCiAQAZAAgKGCAbAQCiAQAAAA==.',
Mo='Mogok:BAABNQAECn8fAAITAAYKvA00OgAdAQATAAYKvA00OgAdAQAAAA==.Molting:BAAANQAECgMJBwAAAA==.Moonkin:BAAANQABCgQIBQAAAA==.',
Mu='Musclegary:BAABNQAECn80AAMQAAoK6B7PCgCQAwAQAAoK6B7PCgCQAwAKAAEK9RpUFAFBAAAAAA==.',
My='Mykie:BAAANQADCggIDwAAAA==.Mylor:BAABNQAECn8nAAITAAgK0ByFFABfAgATAAgK0ByFFABfAgAAAA==.Myrddral:BAABNQAECn8hAAIUAAcKQR42DQB9AQAUAAcKQR42DQB9AQAAAA==.Mystifeyed:BAABNQAECn8iAAIaAAkKnQ2BHwChAQAaAAkKnQ2BHwChAQAAAA==.',
['Mü']='Mürsaat:BAABNQAECn8aAAIOAAcKDwlq3gBeAQAOAAcKDwlq3gBeAQAAAA==.',
Na='Nagrad:BAAANQAECgEIAQAAAA==.Namrekcah:BAAANQAECgEIAQABNQAFFAcIGwAUAMYaAA==.',
Ni='Nilaya:BAAANQADCggICAAAAA==.Nimbledragon:BAAANQADCgYIDQAAAA==.',
Nt='Ntayu:BAABNQAECn8iAAIBAAcKiwWzVAAGAQABAAcKiwWzVAAGAQAAAA==.',
Ol='Olizia:BAABNQAECn8iAAIMAAkKVxabLQA0AgAMAAkKVxabLQA0AgAAAA==.',
Oo='Oopsipoopied:BAAANQADCgcIBwAAAA==.',
Op='Opex:BAABNQAECn8jAAIBAAkKIw1wVAAHAQABAAkKIw1wVAAHAQAAAA==.',
Or='Oril:BAAANQADCgMIAwAAAA==.',
Os='Osairis:BAAANQADCgUIBQAAAA==.',
Ot='Otura:BAAANQADCgIIAgAAAA==.',
Pe='Perkyblade:BAABNQAECn8rAAMGAAkK1BBKBgA7AQAGAAkK1BBKBgA7AQALAAIKcwMhPgBKAAAAAA==.',
Pl='Planeswalker:BAAANQAECgQICgAAAA==.',
Po='Poxic:BAAANQAECgIJBAAAAA==.',
Pr='Protection:BAAANQAECgIIAQAAAA==.',
Ps='Psychotic:BAAANQADCgMIAwAAAA==.',
Ra='Ravinar:BAABNQAECn8kAAIbAAcKAhljAgAmAgAbAAcKAhljAgAmAgAAAA==.Razzle:BAABNQAECn8oAAIcAAoKrhH9UgBdAgAcAAoKrhH9UgBdAgAAAA==.Raàm:BAAANQADCgQIBAAAAA==.',
Re='Relia:BAAANQADCgMIAwAAAA==.',
Ri='Rizzstoned:BAAANQADCggIEwAAAA==.',
Ro='Romulus:BAABNQAECn8jAAMdAAcK+RUKCgCWAQAdAAcK+RUKCgCWAQAIAAEKAACGxAAeAAAAAA==.',
Sa='Sarbarola:BAAANQADCggIIQAAAA==.',
Se='Seraid:BAAANQADCggIHwAAAA==.',
Sh='Shallbedo:BAAANQAECgEIAQABNQAECgoKLwAeAFUOAA==.Shallmagi:BAAANQADCgUIBQABNQAECgoKLwAeAFUOAA==.Shmalexia:BAAANQABCgEJAQAAAA==.',
Si='Siatraler:BAAANQAECgQIBAAAAA==.Sigarette:BAACNQAFFH8bAAIUAAcKxhoiAwBnAgAUAAcKxhoiAwBnAgA1AAQKfzkAAhQACgqtIk0EAKwDABQACgqtIk0EAKwDAAAA.Sinardi:BAABNQAECn8kAAIfAAcKSwtCJwDTAAAfAAcKSwtCJwDTAAAAAA==.',
Sk='Skoob:BAAANQADCgEIAQAAAA==.Skymane:BAAANQAECgcIEQAAAA==.',
Sn='Snaggletooth:BAAANQADCggIEwAAAA==.',
So='Soongxiao:BAAANQAECgcICwAAAA==.Sorce:BAAANQADCgYIDAABNQAECgoKMAAKAAEZAA==.Sovan:BAAANQADCgYIBgAAAA==.Sovix:BAAANQAECgQIBAAAAA==.Sovo:BAABNQAECn8jAAIFAAkKBBKwWgAIAQAFAAkKBBKwWgAIAQABNQAFFAYIFQAcAHALAA==.',
Sp='Sprick:BAAANQADCgQIBQAAAA==.',
Sq='Squanchi:BAAANQADCggIEgAAAA==.',
St='Steaknquake:BAABNQAECn8kAAIKAAcKHyBtDQD1AQAKAAcKHyBtDQD1AQAAAA==.',
Su='Sumdumfun:BAAANQAECgEIAQAAAA==.Sunflower:BAAANQAECgIIAgAAAA==.',
Sy='Sybri:BAABNQAECn8cAAIBAAkKcB1oIAAWAwABAAkKcB1oIAAWAwAAAA==.Sylvandel:BAABNQAECn8bAAICAAcKTxFSCwA4AQACAAcKTxFSCwA4AQAAAA==.Sylvrshado:BAAANQADCgQIBAAAAA==.',
Sz='Szilvia:BAAANQAECgQIBAAAAA==.',
Ta='Talanthar:BAABNQAECn8nAAIFAAgKyh0EDwDxAQAFAAgKyh0EDwDxAQAAAA==.Talarrond:BAAANQAECggIDwAAAA==.',
Te='Teagen:BAABNQAECn8bAAMdAAgKgwlNNgBpAQAdAAgKgwlNNgBpAQAIAAUKBAayiQCtAAAAAA==.Teilssra:BAAANQAECgQIBwAAAA==.',
Th='Thalius:BAABNQAECn8eAAIWAAcK2QzjGAAdAQAWAAcK2QzjGAAdAQAAAA==.Thamachine:BAAANQADCgMIAwAAAA==.Thebear:BAAANQADCgcICgAAAA==.Thóridal:BAAANQAECgIIAgAAAA==.',
To='Tomexo:BAAANQAECgEIAgAAAA==.Toomanydeths:BAABNQAECn8bAAIUAAgKbwklYQBtAQAUAAgKbwklYQBtAQAAAA==.',
Tr='Trickledeath:BAAANQABCgIIAgAAAA==.Trunx:BAAANQAECgEIAQABNQAECgoKJgAPAGIiAA==.',
Ts='Tsaraph:BAAANQADCgYIBgAAAA==.',
Tu='Tuminettlpot:BAAANQADCgYIBgAAAA==.',
Un='Untz:BAAANQADCgYICgAAAA==.',
Ur='Ursusmanny:BAAANQADCgEIAQAAAA==.',
Va='Vanthrall:BAAANQAECgUIEgAAAA==.',
Ve='Velestia:BAAANQABCgIIAgAAAA==.Velithel:BAAANQADCgMIAwAAAA==.Velysa:BAABNQAECn8hAAITAAcKNxDFLAB2AQATAAcKNxDFLAB2AQAAAA==.',
Wa='Warseeker:BAABNQAECn8bAAMQAAkKLxbwbgDTAQAQAAcK2hPwbgDTAQAKAAIKPRX47ACRAAAAAA==.',
We='Weatherworn:BAAANQAECgUIDAAAAA==.Wera:BAAANQAECgcIDAAAAA==.Weslow:BAAANQADCgMIAwAAAA==.',
Wi='Wirhlanir:BAAANQADCgMIAwAAAA==.',
Wo='Woodcrest:BAAANQADCgcIBwAAAA==.Wopertinger:BAAANQADCgMIAwABNQAECggIEAADAAAAAA==.',
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
