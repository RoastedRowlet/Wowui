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

local lookup = {'Warlock-Demonology','Unknown-Unknown','Hunter-BeastMastery','Warrior-Protection','Rogue-Subtlety','DeathKnight-Blood','Evoker-Preservation','DeathKnight-Unholy','DeathKnight-Frost','Paladin-Retribution','Shaman-Enhancement','Priest-Shadow','Priest-Discipline','DemonHunter-Havoc','Hunter-Survival','Monk-Windwalker','Hunter-Marksmanship','Mage-Frost','Paladin-Holy','Warlock-Destruction','Rogue-Assassination','Warrior-Arms','Shaman-Restoration','Warrior-Fury','Mage-Arcane','Druid-Restoration','Shaman-Elemental','Druid-Guardian','Evoker-Devastation','Druid-Balance','Druid-Feral','Rogue-Outlaw','Monk-Mistweaver','DemonHunter-Devourer','DemonHunter-Vengeance',}
local provider = {region='US',realm="Blade'sEdge",name='US',type='weekly',zone=53,date='2026-10-06',data={Ac='Acotas:BAAANQADCgQJAwAAAA==.',
Ae='Aephiona:BAAANQADCgcIBwAAAA==.',
Af='Affli:BAABNQAECoEdAAIBAAgKNB0sOgCKAgABAAgKNB0sOgCKAgAAAA==.',
Ai='Aiunar:BAAANQAECgcIEwAAAA==.Aiupriesty:BAAANQAECgMIBAABNQAECgcIEwACAAAAAA==.',
Ak='Aka:BAAANQADCgIIAgAAAA==.Akaza:BAAANQADCggIDAAAAA==.',
Al='Alastiria:BAAANQAECgQICQAAAA==.Aleinara:BAAANQAECgcICgAAAA==.',
Am='Amazngrace:BAAANQADCgYIBgAAAA==.',
An='Andsey:BAAANQADCgcIEwABNQAECgUICgACAAAAAA==.Annore:BAAANQAECgYIEQAAAA==.',
Aq='Aquelius:BAAANQAECgQIBQAAAA==.Aqular:BAABNQAECoEbAAIDAAYKJxd+iwDCAQADAAYKJxd+iwDCAQAAAA==.',
Ar='Argyre:BAABNQAECoEqAAIEAAkKEiU8AQC4AwAEAAkKEiU8AQC4AwAAAA==.Artifice:BAABNQAECoEaAAIFAAkKlSTCAQCjAwAFAAkKlSTCAQCjAwAAAA==.',
As='Asynic:BAAANQAECgUICAAAAA==.Asynicl:BAAANQADCggICgAAAA==.',
Av='Avadakedevra:BAAANQAECggIAQAAAA==.',
Aw='Awooing:BAAANQADCggIDgABNQAECgQICQACAAAAAA==.',
Az='Azaziel:BAABNQAECoEkAAIGAAkKew7OQwDNAQAGAAkKew7OQwDNAQAAAA==.Azells:BAAANQADCgEIAQABNQAFFAMIBwAHAEIeAA==.Azumok:BAAANQADCgcIBwAAAA==.',
Ba='Bail:BAAANQAECgIIBAAAAA==.Bariesh:BAAANQADCgQIBAAAAA==.',
Be='Bearface:BAAANQADCgUIBQAAAA==.Behindyou:BAAANQADCgcICgAAAA==.Belgaria:BAAANQADCgcIGwAAAA==.Belloftrix:BAAANQAECgIIAgAAAA==.Berryknight:BAAANQAECgQICAAAAA==.Bewlzeye:BAAANQAECgQIDAAAAA==.',
Bi='Bigjonmachne:BAABNQAECoEYAAMIAAcKrxUyUwCdAQAIAAcKiBUyUwCdAQAJAAQK5xToVQAHAQABNQAECgkJJgAKADYfAA==.Binky:BAAANQADCgUIBQAAAA==.',
Bl='Blackdog:BAAANQAECgIIAwAAAA==.Blackguyy:BAAANQAECgUIEAAAAA==.Bloodletter:BAAANQABCgIIAgAAAA==.Bloodsail:BAAANQAECgYIBgAAAA==.',
Bo='Bollux:BAABNQAECoEiAAILAAgKDRTmDwBQAgALAAgKDRTmDwBQAgAAAA==.Bonetatter:BAAANQAECgEIAQAAAA==.Bongonnaink:BAABNQAECoEgAAMMAAgKxxeqGgBSAgAMAAgKxxeqGgBSAgANAAEKjxmfIABJAAAAAA==.Bownyxia:BAAANQAECgYIBwABNQAFFAcIFQAJAPwZAA==.Bowties:BAACNQAFFIEVAAQJAAcK/BnVAwCiAQAJAAUK6RTVAwCiAQAIAAUKcRqLBwB+AQAGAAEKoBEuKwA0AAA1AAQKgTkABAgACQqbJnADALMDAAgACQqkJXADALMDAAkACQoLJeYCAKoDAAYAAgrjDIKkAGYAAAAA.',
Br='Brewfú:BAAANQADCgIJAgAAAA==.Brotie:BAACNQAFFIEIAAIOAAMK6gxQDwDPAAAOAAMK6gxQDwDPAAA1AAQKgSIAAg4ACQoQHCIdAIsCAA4ACQoQHCIdAIsCAAE1AAUUBwgVAAkA/BkA.',
Bt='Btmanight:BAAANQAECgcICwAAAA==.',
Bu='Bullshiift:BAAANQADCgYIBgAAAA==.Burgershaq:BAAANQADCgYIBgAAAA==.Burntbiscuit:BAAANQADCgUIBQAAAA==.Buugada:BAAANQAECgEIAQAAAA==.',
Ca='Caedo:BAAANQADCgIIAgABNQADCgMIAwACAAAAAA==.Caliclysm:BAAANQAECgQIBAAAAA==.Calischism:BAAANQAECgUIBwAAAA==.Canadiangoos:BAAANQADCgUJBQAAAA==.Cantspell:BAAANQAECgIIAgAAAA==.Carobnica:BAAANQADCgQJBAABNQADCgYIBgACAAAAAA==.Cavantes:BAAANQADCgIIAgAAAA==.',
Ce='Celaris:BAAANQAECgEIAQAAAA==.Cell:BAAANQABCgIIAgAAAA==.Celleyna:BAAANQABCggICQAAAA==.',
Ch='Chataykay:BAAANQAECgEIAQAAAA==.Chathsong:BAAANQADCggICAAAAA==.Chichichikin:BAAANQADCgcIBwAAAA==.Chunkyclaps:BAAANQADCgEIAQAAAA==.',
Ci='Citrus:BAABNQAECoElAAMPAAgKlhOjBQAyAgAPAAgKlhOjBQAyAgADAAEK6AkJMgE/AAAAAA==.',
Cn='Cn:BAABNQAECoEkAAIKAAgKxCFdLwDtAgAKAAgKxCFdLwDtAgAAAA==.',
Co='Codeman:BAABNQAECoEgAAIGAAgKXx6eHQCrAgAGAAgKXx6eHQCrAgAAAA==.Cordine:BAAANQADCgYIBgAAAA==.',
Cp='Cptinsaneo:BAACNQAFFIEPAAIIAAUK4RRfBwCCAQAIAAUK4RRfBwCCAQA1AAQKgSQAAggACQpsHksdAL8CAAgACQpsHksdAL8CAAAA.',
Cr='Crimdh:BAAANQAECgQJBAABNQAFFAUIDAAQAPkRAA==.Crimdk:BAAANQAECgUIBwABNQAFFAUIDAAQAPkRAA==.',
Cz='Czin:BAAANQAECgIIAgAAAA==.',
Da='Dalén:BAAANQADCgUIBQAAAA==.',
De='Deathverses:BAACNQAFFIERAAIRAAUKHiZiAwAuAgARAAUKHiZiAwAuAgA1AAQKgUUAAhEACQrFJj8BANsDABEACQrFJj8BANsDAAAA.Demonbiscuit:BAACNQAFFIEIAAIOAAUKyR7pBADlAQAOAAUKyR7pBADlAQA1AAQKgSkAAg4ACQpnJgsBAOoDAA4ACQpnJgsBAOoDAAAA.Denarkis:BAAANQADCgQIBAAAAA==.Derekor:BAAANQADCgMIAwAAAA==.Derpydawg:BAAANQADCgYIBgABNQAFFAQIBgASANoEAA==.Destructus:BAAANQAECgEIAgAAAA==.Deviancy:BAABNQAECoEdAAMTAAgKARhHPwBJAgATAAgKARhHPwBJAgAKAAIK7AxpTgFgAAAAAA==.Devocean:BAAANQADCgUIBQAAAA==.Dexxt:BAAANQAECgMIBQAAAA==.',
Di='Dikslapp:BAAANQAECgUIBQABNQAECgYIDAACAAAAAA==.Dirlin:BAAANQADCgcIDQAAAA==.Ditto:BAAANQADCggJNgAAAA==.',
Dl='Dlitinaro:BAABNQAECoEdAAIGAAgKliP0DgAkAwAGAAgKliP0DgAkAwAAAA==.',
Do='Donoph:BAABNQAECoEfAAITAAgKuyX5CAB0AwATAAgKuyX5CAB0AwAAAA==.Doomar:BAABNQAECoEhAAMBAAgK7h9xZwD/AQABAAYKyx9xZwD/AQAUAAMKox9qLwAAAQAAAA==.Dordire:BAAANQAECgEJAQAAAA==.Dotzilla:BAAANQADCgEIAQAAAA==.',
Dr='Dragindznuts:BAAANQADCgQIBAAAAA==.Drayn:BAABNQAECoEfAAIBAAgKfiBIKgDDAgABAAgKfiBIKgDDAgAAAA==.Dreaveous:BAABNQAECoElAAMBAAgKiA1vdgDUAQABAAgKiA1vdgDUAQAUAAUKwwRYPQDBAAAAAA==.Drugar:BAAANQAECgQICQAAAA==.',
Du='Duint:BAAANQADCgcJDAAAAA==.',
Eb='Eborsisk:BAAANQADCgEIAQAAAA==.',
Ec='Eclipsion:BAAANQAECgUICwAAAA==.',
Ee='Eelane:BAAANQAECgQICQAAAA==.',
El='Elementali:BAAANQAECgQIBAAAAA==.Ell:BAAANQADCgYIFgAAAA==.Eltain:BAAANQADCgQIBAAAAA==.',
En='Endurall:BAAANQADCgQIBAABNQAECggIJgAVAMMYAA==.',
Er='Eradication:BAABNQAECoEcAAIWAAkKiCMQCwCXAwAWAAkKiCMQCwCXAwAAAA==.',
Et='Etheria:BAAANQAECgQIBQABNQAFFAUIDgAXABwUAA==.',
Ev='Evilexo:BAAANQADCgcIBwAAAA==.',
Ex='Exxotic:BAAANQABCgIIAgAAAA==.',
Fa='Faedia:BAAANQAECgMIAwABNQAECgUICgACAAAAAA==.Fahlafflez:BAABNQAECoEYAAMYAAgKZg7ODADHAQAYAAgKZg7ODADHAQAWAAYKZgaz2QACAQAAAA==.Fahros:BAABNQAECoEQAAIZAAcKvyM1lgA3AgAZAAcKvyM1lgA3AgAAAA==.Farkhaz:BAAANQADCggICAAAAA==.Faydron:BAAANQADCgMJAwABNQAECgYIEwACAAAAAA==.',
Fe='Felful:BAAANQAECgMIAwABNQAECggILAAKAFMeAA==.',
Ff='Ffloyd:BAAANQADCgcIBwAAAA==.',
Fi='Fingielock:BAAANQAECgQICwAAAA==.Firedeezball:BAAANQADCgcIBwAAAA==.Fishinfridge:BAAANQAECgcIEAAAAA==.',
Fl='Flloyd:BAABNQAECoEfAAIaAAgKbxAbIwDgAQAaAAgKbxAbIwDgAQAAAA==.Floÿd:BAAANQADCgYIDAAAAA==.Fløyd:BAAANQADCgYIBgAAAA==.',
Fo='Folid:BAAANQADCgUIBwAAAA==.Fortwooh:BAAANQADCggIEwAAAA==.',
Fr='Francy:BAAANQAECgUICAAAAA==.',
Fu='Fuzzyspells:BAAANQAECgQIBAAAAA==.',
Ga='Gambling:BAAANQADCggICAAAAA==.Gatzul:BAAANQADCgMIBAABNQADCggICAACAAAAAA==.',
Gh='Ghostbladez:BAAANQAECgQJCAAAAA==.',
Gi='Gib:BAAANQADCgMIAwAAAA==.Girthmaster:BAAANQADCgQIBAAAAA==.',
Gn='Gnomaste:BAAANQADCgcIEwAAAA==.',
Go='Gomga:BAAANQADCggICAABNQAECggILAAKAFMeAA==.Goththighs:BAACNQAFFIEUAAIZAAUKlyDsDADwAQAZAAUKlyDsDADwAQA1AAQKgSEAAhkACQpqJeQjAEQDABkACQpqJeQjAEQDAAAA.',
Gr='Grawler:BAAANQADCgYIBwAAAA==.Grimdk:BAAANQAECgIIBAAAAA==.Grissa:BAAANQAECggIDgAAAA==.',
Gu='Gumgumfury:BAAANQADCggIHAAAAA==.',
Ha='Halru:BAAANQADCgYICwAAAA==.Halzlok:BAABNQAECoEYAAIbAAYKbhbxcwCVAQAbAAYKbhbxcwCVAQAAAA==.Harmful:BAAANQADCgcIBwABNQAECgcIEQACAAAAAA==.',
He='Herøn:BAAANQADCgYICgAAAA==.',
Hi='Hilarie:BAAANQADCgYICwAAAA==.',
Hu='Hundigob:BAAANQABCgUIBgAAAA==.Hunterschmax:BAABNQAECoEdAAMDAAgK9BIaXQA0AgADAAgK9BIaXQA0AgARAAMKxgc8XQCJAAAAAA==.',
Ic='Icemachine:BAAANQABCgUIBwAAAA==.',
Ih='Ihot:BAAANQAECgUIDAAAAA==.',
Ik='Ikayhaimahn:BAABNQAECoEaAAIcAAkKCSOaAgCHAwAcAAkKCSOaAgCHAwAAAA==.',
In='Incideranus:BAAANQADCggIBAAAAA==.Indishaman:BAABNQAECoEkAAIXAAkK4iM3BQCNAwAXAAkK4iM3BQCNAwAAAA==.',
Ir='Iris:BAAANQADCgMJAwAAAA==.Ironbound:BAAANQADCgUIBQABNQAECgcIIgAXAJ8ZAA==.',
Iv='Ivoric:BAAANQAECggICAAAAA==.',
Ja='Jabronygos:BAACNQAFFIENAAIdAAUKVhQlBACEAQAdAAUKVhQlBACEAQA1AAQKgSoAAh0ACQrWIPQFABsDAB0ACQrWIPQFABsDAAAA.Jarnroz:BAAANQADCgIIAgAAAA==.Jaythirian:BAAANQAECgYIBgAAAA==.',
Je='Jeatalena:BAAANQAECgQIDAAAAA==.Jengà:BAAANQADCggIDQABNQAECgkJIwAZAAwgAA==.',
Jh='Jhara:BAAANQAECgUICgAAAA==.',
Jo='Joeheals:BAAANQADCgUIBwAAAA==.',
Ju='Junior:BAAANQAECgEIAQABNQAFFAMIBwAHAEIeAA==.',
Ka='Kablinkiaa:BAAANQAECgEIAQAAAA==.Kaendas:BAAANQAECgIIAgAAAA==.Kaizayu:BAAANQAECgIIAgAAAA==.Kalier:BAAANQAECgMIAwAAAA==.Kalistria:BAAANQADCgIIAgAAAA==.Kalypso:BAAANQAECgQICQAAAA==.Kamekazi:BAAANQADCggICQAAAA==.Katastrophic:BAAANQADCggIEwAAAA==.Katieylyn:BAAANQAECgcIEAABNQAFFAMIBwAHAEIeAA==.',
Ke='Keelanllan:BAAANQAECgEIAQAAAA==.Keilun:BAEANQADCgQIBAAAAA==.Kertzz:BAAANQAECgEIAQABNQAECgEIAQACAAAAAA==.Kew:BAAANQAECgIIAgAAAA==.',
Ki='Kizira:BAAANQAECgMIAwABNQAECgUICgACAAAAAA==.',
Kn='Kneecromance:BAAANQAECgEJAQAAAA==.Knightxl:BAAANQADCgEIAQAAAA==.',
Ko='Kokuten:BAAANQADCgQIBAABNQAFFAUIDgAXABwUAA==.Koral:BAAANQAECgEIAQAAAA==.',
Ku='Kungfuhealya:BAAANQAECgYIEQAAAA==.Kurog:BAAANQABCgEIAQAAAA==.',
La='Larrydale:BAAANQADCgYICwAAAA==.Lazerturkey:BAAANQADCgcIBwAAAA==.',
Le='Lea:BAAANQADCgcIBwABNQADCgYIBgACAAAAAA==.Lefica:BAAANQABCgIJAgAAAA==.Legacyx:BAAANQADCgcIDAABNQAECgkJHAAWAIgjAA==.Leonardorich:BAAANQADCgcIEQAAAA==.Leondis:BAABNQAECoEtAAIDAAkK3iGWCQCBAwADAAkK3iGWCQCBAwAAAA==.Lexifu:BAACNQAFFIEKAAIaAAQKXgiVCAAkAQAaAAQKXgiVCAAkAQA1AAQKgS4AAxoACQogIiAEAHQDABoACQogIiAEAHQDAB4ABQoyDbpqAPUAAAAA.Lexipriest:BAAANQAECgYIDAAAAA==.Leylla:BAAANQADCgMIAwABNQAECgEIAQACAAAAAA==.',
Li='Lightful:BAABNQAECoEsAAIKAAgKUx5nQwClAgAKAAgKUx5nQwClAgAAAA==.Lilbro:BAACNQAFFIENAAIWAAcKcRGqBgAmAgAWAAcKcRGqBgAmAgA1AAQKgSUAAhYACQpVJRkJAKUDABYACQpVJRkJAKUDAAAA.Lit:BAAANQADCggIDQABNQAECgcIEQACAAAAAA==.',
Lo='Lobais:BAAANQAECgMIAwABNQAECgcICgACAAAAAA==.Lokii:BAAANQABCgMIAwAAAA==.',
Lu='Lumiel:BAAANQABCgcICwAAAA==.Lumos:BAAANQADCggICAAAAA==.Lumosmaxiima:BAAANQADCggIFAAAAA==.',
Ma='Madamme:BAAANQAECgYJDQAAAA==.Madkingzack:BAAANQAECgcIEwAAAA==.Madpriest:BAAANQADCgcIBwAAAA==.Maevea:BAAANQAECgMIAwAAAA==.Malagig:BAAANQADCgIIAgAAAA==.Malaviolence:BAAANQABCgcICgAAAA==.Malistavias:BAAANQAECgcICgAAAA==.Malliki:BAAANQAECgUIBQAAAA==.Marnangus:BAABNQAECoEcAAIWAAcKMxj5fQD9AQAWAAcKMxj5fQD9AQABNQADCgYICAACAAAAAA==.Marnolkas:BAAANQADCggICgABNQAECgEIAQACAAAAAA==.Mathan:BAABNQAECoEdAAITAAgKhCbaBgCJAwATAAgKhCbaBgCJAwAAAA==.Maudib:BAABNQAECoEkAAMcAAgKQhLrFgC6AQAcAAgKfhHrFgC6AQAfAAYKIww4GAA/AQAAAA==.Mavie:BAAANQABCgIIAgABNQAECgkJHAAWAIgjAA==.Mawile:BAABNQAECoEVAAQcAAYKlRQiIgBAAQAeAAYKFAy5WQBDAQAcAAUK/RQiIgBAAQAfAAQKdgluIwDDAAAAAA==.',
Me='Meesha:BAAANQAECgQIBAAAAA==.Mehunta:BAAANQADCgIIAgAAAA==.Melinarra:BAAANQAECgUIDAAAAA==.Messe:BAABNQAECoEmAAMVAAgKwxj2HwBXAgAVAAgKwxj2HwBXAgAgAAYK8hOwDABuAQAAAA==.Methious:BAAANQAECgMIBAAAAA==.',
Mi='Milicious:BAAANQABCgMJBQAAAA==.Mindcontrol:BAAANQAECgUIBQABNQAECggIGgADAHUeAA==.',
Mo='Molatile:BAAANQAECgQICwAAAA==.Montu:BAAANQADCggIDwAAAA==.Moogyver:BAAANQABCggIEQAAAA==.Moonsguard:BAAANQADCgcIFwAAAA==.Moovit:BAAANQAECgEIAQAAAA==.Mordekaíser:BAAANQAECgIIAgAAAA==.Moth:BAAANQAECgYIEwAAAA==.',
Mu='Murre:BAAANQADCgYIBgAAAA==.',
Na='Naasmiu:BAAANQADCgYIBgABNQAECgIIBQACAAAAAA==.Nachokimbo:BAAANQADCggICAAAAA==.Nasmiuu:BAAANQAECgIIBQAAAA==.',
Ne='Nekfury:BAAANQAECgQICAAAAA==.Nepeta:BAABNQAECoEWAAQcAAYKOh+7EgD0AQAcAAYKmhy7EgD0AQAfAAUKOx6mEQCxAQAeAAMKPRijcgDWAAAAAA==.Nevenel:BAAANQADCgMIAwAAAA==.',
Ni='Nivan:BAAANQAECgQICQAAAA==.Nixdorf:BAAANQAECggICAAAAA==.Niço:BAAANQAECgcICQAAAA==.',
No='Nocturnall:BAAANQADCgQIBAAAAA==.Noicce:BAABNQAECoEcAAIfAAgKrRzgCACNAgAfAAgKrRzgCACNAgAAAA==.Noicewar:BAAANQAECgIIAgAAAA==.Notcrims:BAACNQAFFIEMAAIQAAUK+RE6BgByAQAQAAUK+RE6BgByAQA1AAQKgRcAAhAACQrrHKsTAJgCABAACQrrHKsTAJgCAAAA.Notcrym:BAAANQAECgEIAQABNQAFFAUIDAAQAPkRAA==.',
Nu='Numrea:BAAANQADCgIIAgAAAA==.Nutz:BAAANQAECggICAAAAA==.',
Oa='Oakmoss:BAAANQAECgcIEgAAAA==.',
Or='Oralian:BAAANQADCggICAAAAA==.Orcleave:BAAANQAECgcIEgAAAA==.Orwan:BAAANQAECgQIBgAAAA==.',
Pe='Pea:BAAANQAECgMIAwABNQADCgYIBgACAAAAAA==.',
Pi='Pisslowmage:BAAANQAECgUIBgABNQAECgcIEgACAAAAAA==.',
Pr='Pristene:BAAANQAECgYIBgAAAA==.Priyatama:BAAANQAECgQIBAAAAA==.',
Qu='Quorra:BAAANQADCgUJBgAAAA==.',
Ra='Ragecakes:BAAANQADCgYIBQAAAA==.Rakagar:BAAANQAECgUICQAAAA==.Raktot:BAAANQADCgEIAQAAAA==.Razluz:BAAANQADCgYIEwAAAA==.',
Re='Reue:BAABNQAECoElAAIhAAkKjQ9rFgDmAQAhAAkKjQ9rFgDmAQAAAA==.',
Rh='Rhaegos:BAAANQAECgEIAQAAAA==.',
Ri='Riggzz:BAAANQAECgQIBAAAAA==.',
Ru='Ruuna:BAAANQABCgIIAgAAAA==.',
['Rí']='Rígg:BAAANQAECgEIAQAAAA==.',
Sa='Salla:BAAANQAECgQIBAAAAA==.',
Sc='Schmaximus:BAAANQADCgYJDgABNQAECggIHQADAPQSAA==.Scrapyjack:BAABNQAECoEYAAIOAAgKWxvaIQBlAgAOAAgKWxvaIQBlAgABNQAECggIHQAGAJYjAA==.',
Se='Senna:BAAANQADCgMIAwAAAA==.',
Sh='Shale:BAABNQAECoEnAAIHAAkKhA3YGgD8AQAHAAkKhA3YGgD8AQAAAA==.Shammit:BAAANQADCgIIAgAAAA==.Shammytyme:BAAANQAECgYIEQAAAA==.Shampow:BAAANQAECgYIDAAAAA==.Shamyhagar:BAAANQADCgQIBAAAAA==.Shangtsung:BAACNQAFFIEHAAIaAAMKKRIjCgDsAAAaAAMKKRIjCgDsAAA1AAQKgSwAAxoACQqmIv8FAFADABoACQqmIv8FAFADAB4AAgqhEBiJAHwAAAAA.Sharaiya:BAAANQAECgYIDQAAAA==.Sharkmanfive:BAAANQAECgQICAAAAA==.Shaure:BAAANQADCgIIAgAAAA==.Shearwater:BAAANQAECgcIDwAAAA==.',
Si='Silmeriaa:BAAANQABCgIIAgAAAA==.Silversesu:BAAANQAECgEIAQABNQAECggIGAAZAK8SAA==.',
Sk='Skippybmm:BAAANQADCggICAABNQAECgcICgACAAAAAA==.Skirtero:BAAANQADCgYIBgAAAA==.',
Sl='Slappydappy:BAAANQADCgYIBgABNQAFFAMIBgATALwYAA==.Slava:BAAANQAECggIDwAAAA==.Sledgehammer:BAAANQADCgIIAgAAAA==.Sleepytoker:BAAANQADCgYICwAAAA==.',
So='Softbaked:BAAANQADCgUIBgAAAA==.Soltergeist:BAABNQAECoEjAAIGAAgKcRmTMAAxAgAGAAgKcRmTMAAxAgAAAA==.',
Sp='Spine:BAAANQAECgcICgAAAA==.',
Ss='Ssyd:BAAANQADCggICAAAAA==.',
St='Starlsbarkly:BAAANQADCgUIBQAAAA==.Steaknshock:BAAANQAECgYIBgAAAA==.Stormhoofs:BAACNQAFFIELAAILAAQKKRtOAgB6AQALAAQKKRtOAgB6AQA1AAQKgToAAgsACQqsJV8AAO0DAAsACQqsJV8AAO0DAAAA.',
Su='Subzone:BAABNQAECoEXAAIOAAgKHSCzHgB+AgAOAAgKHSCzHgB+AgAAAA==.Sumnabiscuit:BAACNQAFFIEGAAMSAAQK2gT0AQD+AAASAAQKBgT0AQD+AAAZAAIKPwNTRgB6AAA1AAQKgRoAAxkACQpqFJ+eACUCABkACQotEp+eACUCABIAAwqGE48fAMoAAAAA.Sunder:BAAANQADCgUIBQABNQAECggILAAKAFMeAA==.Sunmaster:BAAANQAECgYIEgAAAA==.Supercharged:BAAANQADCggICAAAAA==.',
Sy='Synora:BAAANQADCgcIBwABNQAECgUICgACAAAAAA==.',
['Sê']='Sêlene:BAAANQABCggICAAAAA==.',
Ta='Tackshi:BAAANQADCggIDAAAAA==.Tankinit:BAAANQAECgEIAQAAAA==.Tarea:BAAANQADCgQIBwAAAA==.Tatterbone:BAAANQADCgYIEAABNQAECgEIAQACAAAAAA==.',
Te='Temufuzzy:BAAANQADCgEJAQAAAA==.Tenzink:BAABNQAECoEiAAIhAAkKNBxlCQDZAgAhAAkKNBxlCQDZAgAAAA==.',
Tf='Tflow:BAABNQAECoEjAAIZAAkKDCB1HwBSAwAZAAkKDCB1HwBSAwAAAA==.',
Th='Théworld:BAAANQABCgIIBAABNQADCgcIFwACAAAAAA==.',
Ti='Tindranga:BAAANQADCggIIQAAAA==.Titansgrippy:BAAANQAECgYIDAAAAA==.',
To='Tolbert:BAAANQADCgMIAwABNQADCgYIBgACAAAAAA==.Totemir:BAABNQAECoEYAAIbAAcKtCBIMACVAgAbAAcKtCBIMACVAgAAAA==.',
Tr='Trammatize:BAAANQAECgYIEwAAAA==.Triptamean:BAAANQADCggIFwAAAA==.',
Tw='Twobladebray:BAABNQAECoEaAAMiAAgKQBULIgAbAgAiAAgKjxQLIgAbAgAjAAEK2Bn5JwBIAAAAAA==.',
Un='Undeadnite:BAAANQAECgEIAQAAAA==.Unglaus:BAAANQAECgYIBgAAAA==.',
Uz='Uzington:BAACNQAFFIEGAAIEAAMKWR3+AgADAQAEAAMKWR3+AgADAQA1AAQKgSQAAgQACQq/IFcEACcDAAQACQq/IFcEACcDAAAA.',
Va='Valeta:BAAANQADCggIJAAAAA==.Valzlok:BAAANQAECgQICAAAAA==.Vanessa:BAABNQAECoEbAAIgAAgKXBDYCADxAQAgAAgKXBDYCADxAQAAAA==.Vanillacream:BAAANQADCgMIAwAAAA==.Vayth:BAAANQADCggICAAAAA==.',
Ve='Veilthorn:BAAANQAECgEIAQAAAA==.Velinieron:BAAANQAECgcIDwAAAA==.Velithiri:BAAANQAECgQIDgAAAA==.Vellash:BAAANQADCgEIAQAAAA==.',
Vi='Vilencia:BAAANQABCgUICwAAAA==.Vince:BAAANQADCgUIBgAAAA==.Vinny:BAAANQABCgIIAgAAAA==.',
Vo='Vonulter:BAAANQAECgUIDwAAAA==.',
Vy='Vylon:BAAANQAECgUIDgAAAA==.Vynlandis:BAAANQAECgEIAQAAAA==.Vyrel:BAAANQADCgYICgAAAA==.',
['Vê']='Vêga:BAAANQAECgcIBwABNQAFFAQIBgASANoEAA==.',
Wa='Warbezerker:BAAANQADCgcIBwAAAA==.Waycores:BAAANQAECgUIBQAAAA==.',
We='Weenbean:BAAANQAECgYICAAAAA==.',
Wh='Whakoopa:BAAANQAECgQIBAAAAA==.Whispertree:BAABNQAECoEmAAIeAAkKzhsGGgDdAgAeAAkKzhsGGgDdAgAAAA==.Whìspèr:BAAANQAECgIIAgAAAA==.',
Wi='Wilddonut:BAAANQADCgQJBAAAAA==.Wiseguys:BAAANQAECgcIBwABNQAFFAQIBgASANoEAA==.Wixypoo:BAAANQAECgEIAQAAAA==.',
Wo='Woodnzhood:BAAANQAECgIIAwAAAA==.Worhammer:BAAANQADCgYIBgAAAA==.',
Wr='Wrylah:BAABNQAECoEZAAIdAAgKyRKQEwD2AQAdAAgKyRKQEwD2AQAAAA==.',
Wu='Wuxian:BAAANQADCgYIBgABNQAFFAUIDgAXABwUAA==.',
Wy='Wyyn:BAAANQAECgYIBgAAAA==.',
Xa='Xanboi:BAABNQAECoEgAAMDAAgKwiRVHwD+AgADAAcKiSVVHwD+AgARAAEKSh+sawBbAAAAAA==.',
Xe='Xegos:BAAANQADCgQIBAAAAA==.',
Yi='Yikkle:BAAANQABCgIIAwAAAA==.',
Ys='Ysar:BAAANQAECgYIEwAAAA==.',
Yu='Yumzug:BAAANQADCgQIBAAAAA==.',
['Yô']='Yôshi:BAAANQAECggICAAAAA==.',
Ze='Zeebu:BAAANQAECgQICQAAAA==.Zephryyn:BAAANQADCggIDwAAAA==.',
Zh='Zhilan:BAABNQAECoEnAAIaAAcKYw6rMABhAQAaAAcKYw6rMABhAQAAAA==.',
Zi='Zilliwax:BAAANQADCgYIBgAAAA==.',
Zo='Zoda:BAAANQADCgQIBgAAAA==.Zoko:BAAANQAECgEIAQAAAA==.',
Zu='Zurgadhunter:BAABNQAECoEbAAIjAAgKnB0xBgCQAgAjAAgKnB0xBgCQAgAAAA==.Zuzuk:BAAANQADCgMIAwAAAA==.Zuzuki:BAAANQADCgQIBAAAAA==.',
['Zú']='Zúz:BAAANQAECgYICwAAAA==.',
['Ða']='Ðalinor:BAAANQADCggICAAAAA==.',
['Ðe']='Ðemaea:BAAANQADCgUIAwAAAA==.',
['Ði']='Ðittø:BAAANQADCgIIAgABNQADCggJNgACAAAAAA==.',
['Øc']='Øctø:BAAANQAECgEIAQAAAA==.',
['Ør']='Øreø:BAABNQAECoEfAAIjAAgK/R7TBADEAgAjAAgK/R7TBADEAgAAAA==.',
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
