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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','Unknown-Unknown','Shaman-Elemental','Paladin-Retribution','Warlock-Destruction','Mage-Arcane','Warrior-Fury','Warrior-Arms','Druid-Balance','Druid-Restoration','Paladin-Holy','Shaman-Restoration','Warrior-Protection','DeathKnight-Frost','Hunter-Survival','Monk-Mistweaver','Mage-Fire','Rogue-Assassination','Rogue-Subtlety','Paladin-Protection','DeathKnight-Blood','Priest-Holy','DeathKnight-Unholy','Mage-Frost','Warlock-Affliction','Monk-Windwalker','Rogue-Outlaw','Druid-Guardian','Warlock-Demonology','Druid-Feral','Shaman-Enhancement','DemonHunter-Havoc',}
local provider = {region='US',realm='SteamwheedleCartel',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aalwein:BAABNQAECn8gAAIBAAkK1BupagA+AgABAAkK1BupagA+AgAAAA==.',
Ad='Adehn:BAAANQAECgMIAwAAAA==.',
Al='Alfrus:BAAANQADCggICwAAAA==.',
Am='Amarii:BAABNQAECn8jAAICAAgK0gNANADWAAACAAgK0gNANADWAAAAAA==.',
An='Andent:BAAANQABCgYICAABNQADCggIFgADAAAAAA==.',
Ap='Appostle:BAAANQADCggIGAAAAA==.',
Ar='Ara:BAABNQAECn8mAAIBAAoK4haEQQCmAgABAAoK4haEQQCmAgAAAA==.',
As='Asteryn:BAAANQAECgIIAwAAAA==.',
Av='Avigar:BAABNQAECn8VAAIEAAYKmwmtsQAvAQAEAAYKmwmtsQAvAQAAAA==.',
Ba='Bangan:BAAANQAECgEIAQAAAA==.Banisary:BAAANQADCgYIBgAAAA==.',
Be='Belakor:BAABNQAECn8lAAIFAAkK4Ao4tQBmAQAFAAkK4Ao4tQBmAQAAAA==.Bep:BAAANQAECgEIAQABNQAECgoKLAAGAGkVAA==.Bepragosa:BAABNQAECn8sAAIGAAoKaRXIBgCdAgAGAAoKaRXIBgCdAgAAAA==.',
Bi='Bighammer:BAAANQAECgUIBQABNQAFFAgIGgAHACAUAA==.Binpharteen:BAAANQADCgcICwAAAA==.Birgitè:BAAANQADCgYIEwAAAA==.',
Bl='Blaque:BAABNQAECn8iAAIBAAoK5wwYbgDlAQABAAoK5wwYbgDlAQAAAA==.',
Bo='Bootylightz:BAAANQABCgUIAQAAAA==.Bowguytome:BAACNQAFFH8FAAICAAUK+CWBBAArAgACAAUK+CWBBAArAgA1AAQKfyUAAgIACAqGJmkXAJ4CAAIACAqGJmkXAJ4CAAAA.Bozo:BAAANQAECgIIBgAAAA==.',
Br='Brownbelt:BAABNQAECn9CAAMIAAoK2xL+CgAWAgAIAAoK2xL+CgAWAgAJAAUKuANbEgG4AAAAAA==.Brîn:BAABNQAECn8sAAIGAAgKdwq7CwAGAQAGAAgKdwq7CwAGAQAAAA==.',
Bu='Buteihunter:BAACNQAFFH8HAAIBAAQKfRcFEgD5AAABAAQKfRcFEgD5AAA1AAQKf0QAAgEACgo/JbQFAGADAAEACgo/JbQFAGADAAAA.Buteilock:BAAANQAECggIDAABNQAFFAQIBwABAH0XAA==.Butherts:BAAANQAECggIEwAAAA==.',
Bw='Bwonshifty:BAAANQAECggIBQAAAA==.',
Ch='Chelali:BAABNQAECn8oAAIJAAoK9RldVACNAgAJAAoK9RldVACNAgAAAA==.Chicharrone:BAABNQAECn83AAMKAAoK/AfkYgBDAQAKAAoK/AfkYgBDAQALAAUKngSnVQCiAAAAAA==.Chizaru:BAABNQAECn8lAAIMAAoK/R1qHAACAwAMAAoK/R1qHAACAwAAAA==.Chlorophyll:BAAANQAECgYIBgAAAA==.Chyntobelt:BAAANQAECgQIDwABNQAECgoKQgAIANsSAA==.',
Cl='Clacks:BAAANQADCgIIAgAAAA==.',
Cr='Cryption:BAAANQAECggIEAAAAA==.',
Da='Daelyn:BAAANQAECgQIBAAAAA==.',
De='Deafenned:BAAANQADCggIDQAAAA==.Deafnight:BAAANQADCggIDAABNQADCggIDQADAAAAAA==.Deliquesce:BAAANQADCggICgAAAA==.Deäthtoall:BAAANQADCgUIBQAAAA==.',
Di='Diamante:BAACNQAFFH8IAAINAAQKzQxHFgAEAQANAAQKzQxHFgAEAQA1AAQKf0oAAg0ACgraG7wjAKUCAA0ACgraG7wjAKUCAAAA.Dignifeyed:BAAANQADCgcIBwAAAA==.Discoelsi:BAAANQAECgMIAwAAAA==.',
Dr='Dracarnoir:BAAANQADCgcIEAAAAA==.Dragonite:BAABNQAECn80AAMJAAoKUyNqDQCOAwAJAAoKUyNqDQCOAwAOAAMK2xGyNACQAAAAAA==.Drakemichael:BAAANQADCgUIBQAAAA==.Dremu:BAABNQAECn84AAIKAAkKRx3uGwAmAgAKAAkKRx3uGwAmAgAAAA==.',
Du='Duskhunter:BAAANQAECgUIDwAAAA==.',
Dy='Dysraxis:BAAANQABCggIDgAAAA==.',
['Dï']='Dïnhö:BAAANQAECgMIBQAAAA==.',
El='Elahna:BAAANQAECgQIBwAAAA==.Elamaun:BAABNQAECn82AAIMAAgKiRk2NwA+AgAMAAgKiRk2NwA+AgAAAA==.Eltiana:BAABNQAECn8fAAIHAAkKJAm92QDUAQAHAAkKJAm92QDUAQAAAA==.',
Em='Emisa:BAAANQADCgYIBwAAAA==.',
En='Enochen:BAAANQAECggIBQAAAA==.',
Ep='Ephex:BAAANQADCgUIBAAAAA==.Ephriest:BAAANQADCgMIBAABNQAECgYIDgADAAAAAA==.Ephury:BAAANQAECgYIDgAAAA==.Epic:BAAANQADCgIIAgAAAA==.',
Er='Ertraz:BAAANQAECgEIAQAAAA==.',
Et='Ethahell:BAAANQADCgEIAQAAAA==.',
Ev='Evhomang:BAAANQAECgYIBAABNQAFFAoKMAAPADYiAA==.',
Fa='Faelyna:BAABNQAECn81AAIQAAkKLw4DBwC9AQAQAAkKLw4DBwC9AQAAAA==.',
Fe='Fearbear:BAAANQADCgUIAwAAAA==.',
Fo='Forged:BAABNQAECn9BAAIFAAkKHCQkFwBoAwAFAAkKHCQkFwBoAwAAAA==.',
Fu='Fufufu:BAAANQADCgQIBAABNQAFFAQICAANAM0MAA==.',
Gi='Githyanki:BAAANQADCggIEQAAAA==.',
Go='Goop:BAAANQADCgUIBQABNQAECgoKKAARAGIiAA==.',
Gr='Grangshammy:BAABNQAECn8tAAIEAAoKbRe/NAADAgAEAAoKbRe/NAADAgAAAA==.Grimskull:BAAANQADCgYICgAAAA==.Grimvault:BAAANQAECgIIAgABNQAECgkJOgAHAAEdAA==.',
Ha='Hacelian:BAAANQADCgYIBgAAAA==.Haeltree:BAAANQAECgMIAwABNQAECgkJPAASAPMXAA==.Han:BAABNQAECn8gAAMTAAkKKBP0KwA4AgATAAkK9hL0KwA4AgAUAAYKNQyIMQAxAQAAAA==.Hargoroth:BAAANQADCggICwAAAA==.Harlock:BAAANQADCgcIBwAAAA==.',
He='Henudorf:BAAANQAECgYIDQAAAA==.',
Ho='Holyverdict:BAAANQADCgQIAwAAAA==.',
Ic='Icaina:BAABNQAECn9DAAINAAkKKSJRFgAeAwANAAkKKSJRFgAeAwAAAA==.',
In='Incinderella:BAAANQAECgUICwABNQAECgMIAgADAAAAAA==.Infernnape:BAAANQAECgEIAgAAAA==.',
Ja='Jadefire:BAAANQAECggIDgAAAA==.Jakana:BAAANQAECgMIAgAAAA==.Jathy:BAAANQADCgQIBAAAAA==.',
Je='Jeisa:BAABNQAECn87AAMVAAgK8AqzNQDbAAAFAAYK7QYuEgEAAQAVAAgK4AmzNQDbAAAAAA==.',
Jh='Jhedu:BAAANQAECgcIDQAAAA==.',
Ju='Juanns:BAAANQADCgcJBwAAAA==.',
Ka='Kaj:BAABNQAECn8fAAIMAAkKPBI3UQAnAgAMAAkKPBI3UQAnAgAAAA==.Kallotera:BAAANQADCggICAAAAA==.Kalrou:BAAANQADCgUIBQABNQAECgoKKwAWABYjAA==.Kastoria:BAAANQADCgcIDAAAAA==.Katnipp:BAABNQAECn82AAIBAAoKCBqCLACQAgABAAoKCBqCLACQAgAAAA==.Kaylazune:BAABNQAECn84AAIXAAgKKxVmUwDtAQAXAAgKKxVmUwDtAQAAAA==.',
Ke='Keltara:BAAANQAECgQICAAAAA==.',
Kh='Kharybdis:BAAANQAECgEIAQAAAA==.Khrala:BAABNQAECn8vAAIYAAoKgBOoHAD9AQAYAAoKgBOoHAD9AQAAAA==.',
Ki='Kindlana:BAAANQADCggIDwAAAA==.Kiye:BAACNQAFFH8ZAAIBAAcKyRNLBQAAAgABAAcKyRNLBQAAAgA1AAQKfzsAAgEACgqyI4oWAO0CAAEACgqyI4oWAO0CAAAA.',
Ku='Kushan:BAAANQADCgEIAQAAAA==.Kuuro:BAABNQAECn87AAINAAgKThfdQQAMAgANAAgKThfdQQAMAgAAAA==.',
Ky='Kydori:BAAANQAECgUIBQABNQAECggILgAZAEIPAA==.',
La='Lattylock:BAAANQADCgUIBQAAAA==.Lattymag:BAABNQAECn8hAAIHAAcKtwFIGQGKAAAHAAcKtwFIGQGKAAAAAA==.Laughystabby:BAAANQADCgcIDgAAAA==.',
Le='Leibniz:BAABNQAECn83AAIaAAgKch2MBQBoAgAaAAgKch2MBQBoAgAAAA==.Leisa:BAABNQAECn81AAIBAAgKdg8EjwDrAQABAAgKdg8EjwDrAQAAAA==.Lelwindae:BAABNQAECn8cAAMFAAgKfQho5wARAQAFAAgKfQho5wARAQAVAAEKAADAdQAnAAAAAA==.',
Li='Lifemoon:BAAANQAECgUIDAAAAA==.Lildangerus:BAAANQADCgYIDgAAAA==.Liminara:BAEBNQAECn8jAAIFAAoKJBG3rADGAQAFAAoKJBG3rADGAQABNQAFFAgIEgABAFUcAA==.Linaste:BAABNQAECn8hAAMFAAoKRx3zZABsAgAFAAoKRx3zZABsAgAMAAMKARXXrQDCAAAAAA==.',
Lo='Lohha:BAAANQADCgIIAgAAAA==.',
Lu='Lulu:BAACNQAFFH8kAAIbAAkKMSEuAACyAwAbAAkKMSEuAACyAwA1AAQKfyQAAhsACQp2Jo4DAJ4DABsACQp2Jo4DAJ4DAAAA.Lumaria:BAAANQAECgQIDAAAAA==.',
Ly='Lyllia:BAAANQAECgYIDgAAAA==.Lynoia:BAAANQADCggICAAAAA==.',
Ma='Makunel:BAAANQAECgIIAgAAAA==.Mandevu:BAAANQAECgEIAQAAAA==.Mangan:BAAANQAECgEJAwAAAA==.Manknus:BAABNQAECn9JAAIIAAoKXxVGCAAlAgAIAAoKXxVGCAAlAgAAAA==.Mannydemons:BAAANQADCgYIBgAAAA==.Manthrax:BAABNQAECn9HAAINAAoKlBLqOQAwAgANAAoKlBLqOQAwAgAAAA==.Mathiyis:BAAANQABCgcICwABNQAECgQIBwADAAAAAA==.',
Me='Mexecutioner:BAABNQAECn9NAAMJAAoKxhDcUgAGAgAJAAoKxhDcUgAGAgAOAAEK8gYxSQAqAAAAAA==.',
Mi='Milkadin:BAAANQADCgIIAgAAAA==.Mirzan:BAAANQADCgEIAQAAAA==.Missmolt:BAABNQAECn9AAAIcAAgKGCBmBADJAgAcAAgKGCBmBADJAgAAAA==.',
Mo='Mogok:BAABNQAECn88AAIVAAgKERH+HQCAAQAVAAgKERH+HQCAAQAAAA==.Molting:BAAANQAECgMJBwAAAA==.Moonkin:BAAANQABCgQIBQAAAA==.',
Mu='Musclegary:BAABNQAECn9IAAMEAAoK+yLPCgCQAwAEAAoK+yLPCgCQAwANAAEK9RpUFAFBAAAAAA==.',
My='Mykie:BAAANQADCggIDwAAAA==.Mylor:BAABNQAECn82AAIVAAkKEhwEDwA5AgAVAAkKEhwEDwA5AgAAAA==.Myrddral:BAABNQAECn8vAAIWAAgKMR4VKwCrAQAWAAgKMR4VKwCrAQAAAA==.Mystifeyed:BAABNQAECn8kAAIdAAoKZA6BHwChAQAdAAoKZA6BHwChAQAAAA==.',
['Mü']='Mürsaat:BAABNQAECn81AAIFAAkKWwuuqwB4AQAFAAkKWwuuqwB4AQAAAA==.',
Na='Nagrad:BAAANQAECgEIAQAAAA==.Namrekcah:BAAANQAECgEIAQABNQAFFAgIHgAWAE8aAA==.',
Ni='Nilaya:BAAANQADCggICAAAAA==.Nimbledragon:BAAANQADCgYIDQAAAA==.',
Nt='Ntayu:BAABNQAECn87AAIBAAgKVAYjvQA3AQABAAgKVAYjvQA3AQAAAA==.',
Ol='Olizia:BAABNQAECn82AAIPAAoKvxmdHwBPAgAPAAoKvxmdHwBPAgAAAA==.',
Oo='Oopsipoopied:BAAANQADCgcIBwAAAA==.',
Op='Opex:BAABNQAECn9KAAIBAAoK3hRyUQAqAgABAAoK3hRyUQAqAgAAAA==.',
Or='Oril:BAAANQADCgMIAwAAAA==.',
Os='Osairis:BAAANQADCgUIBQAAAA==.',
Ot='Otura:BAAANQADCgIIAgAAAA==.',
Pe='Perkyblade:BAABNQAECn9TAAMIAAoKaxUKCQAUAgAIAAoKaxUKCQAUAgAOAAMKUwUhPgBKAAAAAA==.',
Pl='Planeswalker:BAAANQAECgUIEAAAAA==.',
Po='Poxic:BAAANQAECgIIBAAAAA==.',
Pr='Primalbooty:BAAANQADCgMIAwABNQAFFAQIBwABAH0XAA==.Protection:BAAANQAECgIIAQAAAA==.',
Ps='Psychotic:BAAANQADCgMIAwAAAA==.',
Ra='Rago:BAAANQADCgYIBgAAAA==.Raithneach:BAAANQAECgQIBAABNQAECgcIBwADAAAAAA==.Ravinar:BAABNQAECn88AAISAAkK8xdyAgDkAQASAAkK8xdyAgDkAQAAAA==.Raynorama:BAAANQAECgIIAgAAAA==.Razzle:BAABNQAECn8sAAIeAAoKHBT9UgBdAgAeAAoKHBT9UgBdAgAAAA==.Raàm:BAAANQADCgQIBAAAAA==.',
Re='Relia:BAAANQADCgMIAwAAAA==.',
Ri='Rizzstoned:BAAANQADCggIEwAAAA==.',
Ro='Romulus:BAABNQAECn8wAAULAAgKOhaYKACsAQALAAgKOhaYKACsAQAfAAYK2BKHHAAnAQAdAAUK2AUlVgBqAAAKAAEKAACGxAAeAAAAAA==.',
Sa='Sarbarola:BAAANQADCggILAAAAA==.',
Se='Seraid:BAAANQADCggIIgAAAA==.',
Sh='Shallbedo:BAAANQAECgUIBgABNQAECgoKPgAgALQSAA==.Shallmagi:BAAANQADCgUIBQABNQAECgoKPgAgALQSAA==.Shmalexia:BAAANQABCgEJAQAAAA==.',
Si='Siatraler:BAAANQAECgYIDwAAAA==.Sigarette:BAACNQAFFH8eAAIWAAgKTxoiAwBnAgAWAAgKTxoiAwBnAgA1AAQKf1MAAhYACgpJJU0EAKwDABYACgpJJU0EAKwDAAAA.Sinardi:BAABNQAECn8wAAIhAAcKSAyLSwBzAQAhAAcKSAyLSwBzAQAAAA==.',
Sk='Skoob:BAAANQAECgEIAQAAAA==.Skymane:BAABNQAECn8ZAAIXAAkKGgl9ggCQAQAXAAkKGgl9ggCQAQAAAA==.',
Sn='Snaggletooth:BAAANQADCggIEwAAAA==.',
So='Soongxiao:BAAANQAECgcIDAAAAA==.Sorce:BAAANQAECgEIAQABNQAFFAQICAANAM0MAA==.Sovan:BAAANQADCgYIBgAAAA==.Sovix:BAAANQAECgQIBAAAAA==.Sovo:BAABNQAECn8yAAIHAAkKnRbcSwArAgAHAAkKnRbcSwArAgABNQAFFAgIGQAeABQMAA==.',
Sp='Sprick:BAAANQADCgQIBQAAAA==.',
St='Steaknquake:BAABNQAECn88AAINAAkKMh5DHwDCAgANAAkKMh5DHwDCAgAAAA==.',
Su='Sumdumfun:BAAANQAECgUIBgAAAA==.Sunflower:BAAANQAECgMIAgAAAA==.',
Sy='Sybri:BAABNQAECn8iAAIBAAkKcB1oIAAWAwABAAkKcB1oIAAWAwAAAA==.Sylvandel:BAABNQAECn80AAICAAgKChA9IQBkAQACAAgKChA9IQBkAQAAAA==.Sylvandelle:BAAANQADCgUIBQAAAA==.Sylvrshado:BAAANQADCgQIBAAAAA==.',
Sz='Szilvia:BAAANQAECgQIBAAAAA==.',
Ta='Talanthar:BAABNQAECn86AAIHAAkKAR07VAAVAgAHAAkKAR07VAAVAgAAAA==.Talarrond:BAABNQAECn8nAAIhAAgKjgxKNgBxAQAhAAgKjgxKNgBxAQAAAA==.',
Te='Teagen:BAABNQAECn8sAAMLAAoKnhEtGwAyAgALAAoKnhEtGwAyAgAKAAUKBAayiQCtAAAAAA==.Teilssra:BAAANQAECgQIBwAAAA==.Tekkadhar:BAAANQADCgIIAgAAAA==.',
Th='Thalius:BAABNQAECn8qAAIYAAgKpAzrOAA1AQAYAAgKpAzrOAA1AQAAAA==.Thamachine:BAAANQADCgMIAwAAAA==.Thóridal:BAAANQAECgIIAgAAAA==.',
To='Toomanydeths:BAABNQAECn8vAAMWAAoKqQmLPwBAAQAWAAoKqQmLPwBAAQAYAAQKOAZ4YwB/AAAAAA==.',
Tr='Trickledeath:BAAANQABCgIIAgAAAA==.Trunx:BAAANQAECgEIAQABNQAECgoKKAARAGIiAA==.',
Ts='Tsaraph:BAAANQAECgYIDAAAAA==.',
Tu='Tuminettlpot:BAAANQADCgYIBgAAAA==.',
Un='Untz:BAAANQADCgYICgAAAA==.',
Ur='Ursusmanny:BAAANQADCggICgAAAA==.',
Va='Vanthrall:BAAANQAECgUIEgAAAA==.',
Ve='Velestia:BAAANQAECgUIBwAAAA==.Velithel:BAAANQADCgMIAwAAAA==.Velysa:BAABNQAECn84AAIVAAkKlBETIQBmAQAVAAkKlBETIQBmAQAAAA==.Verstümmeln:BAAANQADCgYICgAAAA==.',
Vu='Vudrer:BAAANQABCgUIAwAAAA==.',
Wa='Warseeker:BAABNQAECn8cAAMEAAkKLxbwbgDTAQAEAAcK2hPwbgDTAQANAAIKPRX47ACRAAAAAA==.',
We='Weatherworn:BAABNQAECn8nAAINAAgKUBX8SwDjAQANAAgKUBX8SwDjAQAAAA==.Wera:BAAANQAECgYIDQAAAA==.Weslow:BAAANQADCgMIAwAAAA==.',
Wi='Wirhlanir:BAAANQADCgMIAwAAAA==.',
Wo='Woodcrest:BAAANQADCggIDwAAAA==.Wopertinger:BAAANQAECggICQABNQAECggIFAAFAPwGAA==.',
Yo='Yoril:BAAANQAECgEIAQAAAA==.',
Ze='Zenaara:BAAANQAECggIDwAAAA==.Zephidel:BAAANQADCgQIBAAAAA==.',
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
