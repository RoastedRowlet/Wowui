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

local lookup = {'Unknown-Unknown','Druid-Balance','Shaman-Enhancement','DemonHunter-Vengeance','Warrior-Fury','Shaman-Elemental','Rogue-Assassination','DemonHunter-Devourer','Evoker-Devastation','Evoker-Augmentation','Warrior-Arms','Warlock-Destruction','Warlock-Demonology','Hunter-BeastMastery','Priest-Holy','DeathKnight-Unholy','Mage-Arcane','Priest-Discipline','Hunter-Marksmanship','DeathKnight-Frost','Paladin-Retribution','Paladin-Holy','Shaman-Restoration','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','DeathKnight-Blood','Mage-Frost','Druid-Restoration','DemonHunter-Havoc','Warlock-Affliction','Rogue-Subtlety','Rogue-Outlaw','Paladin-Protection','Priest-Shadow',}
local provider = {region='US',realm='Exodar',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abrakådabruh:BAAANQAECgUIDgAAAA==.',
Ac='Acnologia:BAAANQADCgQIBQAAAA==.',
Ae='Aeropos:BAAANQABCgEIAQAAAA==.',
Ah='Ahron:BAAANQAECgcIEgABNQAECggIDwABAAAAAA==.',
Ai='Ainjel:BAAANQADCgYICgAAAA==.Ainz:BAAANQADCgMIBAAAAA==.',
Ak='Akaitsuki:BAAANQAECgYIDwAAAA==.',
Al='Alex:BAAANQADCggICAAAAA==.Alexdh:BAAANQADCgcIBwAAAA==.Alexr:BAAANQADCgUIBQABNQADCgcIBwABAAAAAA==.Alexxh:BAAANQADCgMIAwABNQADCgcIBwABAAAAAA==.Alisson:BAAANQADCgEIAQABNQADCgcIBwABAAAAAA==.',
Am='Amarantus:BAAANQADCgIIAgABNQAECgkJKAACAJgYAA==.Ammerie:BAAANQADCgUJBQAAAA==.',
An='Anmoa:BAAANQAECgUIBQABNQAECgkJKwADALYlAA==.Anmodru:BAAANQADCgUIBQABNQAECgkJKwADALYlAA==.',
Ao='Aoefarm:BAAANQADCggIGAAAAA==.',
Aq='Aqulath:BAABNQAECoEcAAIEAAgKJSETAwD1AgAEAAgKJSETAwD1AgAAAA==.',
Ar='Aragos:BAAANQADCgEIAQAAAA==.Ardênt:BAAANQADCgIIAgAAAA==.Aridhol:BAAANQAECgEJAQAAAA==.Arradrius:BAAANQAECgYIBwAAAA==.',
As='Ashaala:BAAANQABCgIIBgAAAA==.Astravelle:BAAANQAECgEIAQAAAA==.',
At='Athená:BAAANQAECgUICQAAAA==.Athenä:BAAANQAECgcIEwAAAA==.',
Au='Aubrii:BAAANQADCgcIDgAAAA==.Aukatsang:BAAANQAECgYIEAAAAA==.',
Ay='Ayo:BAAANQADCgcIBwAAAA==.',
Az='Azeloth:BAAANQAECgYIEAAAAA==.',
Ba='Babzx:BAAANQADCgcICgAAAA==.Baladeva:BAAANQAECgUICwAAAA==.Banaritaz:BAAANQAECgYIEgAAAA==.Barbaricboss:BAAANQAECgQIBQAAAA==.Barrak:BAAANQAECggIDwAAAA==.Bau:BAAANQADCgYICgAAAA==.',
Be='Bearomir:BAABNQAECoEXAAIFAAgKWx9vAwDXAgAFAAgKWx9vAwDXAgAAAA==.Beersnob:BAAANQAECgYIDQAAAA==.',
Bh='Bhis:BAAANQADCgMIBgAAAA==.',
Bi='Bigblcktotem:BAACNQAFFIELAAIGAAMK8wzPEQDiAAAGAAMK8wzPEQDiAAA1AAQKgSAAAgYACQpyIqINAGEDAAYACQpyIqINAGEDAAAA.Bigmikeyg:BAAANQAECgUIDQAAAA==.Bigsteve:BAAANQAECgUICgAAAA==.',
Bl='Blanket:BAABNQAECoEaAAIHAAYK7h4WJAAFAgAHAAYK7h4WJAAFAgAAAA==.Bloodhunter:BAAANQADCgUIBwAAAA==.',
Bo='Boomchickun:BAAANQABCgIIAgABNQAECgkJKAAIAOccAA==.',
Br='Brickley:BAAANQADCgYIBgABNQAECggIHAAEACUhAA==.',
Bu='Bubbahowl:BAAANQADCgUIBQAAAA==.',
['Bè']='Bèyork:BAAANQAECgYICwAAAA==.',
['Bø']='Bønd:BAAANQAECgEIAgAAAA==.',
Ca='Caicos:BAEBNQAECoEkAAMJAAkKeBE+DgBCAgAJAAkKeBE+DgBCAgAKAAEKVwE0IAAZAAAAAA==.Calizon:BAAANQAECgcIEAAAAA==.Camc:BAAANQADCgQIBAAAAA==.Canowhoopass:BAAANQAECgUICwAAAA==.Caser:BAAANQADCgMJAwAAAA==.Catharsis:BAAANQABCggIDAAAAA==.',
Ce='Cell:BAACNQAFFIELAAILAAUKyAnCDQBrAQALAAUKyAnCDQBrAQA1AAQKgSkAAgsACQpHIM4XAD4DAAsACQpHIM4XAD4DAAAA.Cellyne:BAAANQADCgUIBgAAAA==.Cerassin:BAABNQAECoEoAAIIAAkK5xwfDQD0AgAIAAkK5xwfDQD0AgAAAA==.Cereas:BAAANQAECgUIDgAAAA==.',
Ch='Cheesedawg:BAAANQADCgEIAQAAAA==.Cherrish:BAAANQADCgUICQAAAA==.Choofz:BAAANQADCggIEAAAAA==.',
Cl='Clariel:BAAANQABCgEIAQAAAA==.Cloud:BAAANQAECggIEgAAAA==.Clukdogg:BAAANQAECgcIEgAAAA==.',
Co='Combination:BAACNQAFFIEKAAMMAAUKuwj8AgDaAAAMAAMKIgf8AgDaAAANAAMKqgpsFwDWAAA1AAQKgSYAAwwACQr9HGcFALMCAAwACQpAGWcFALMCAA0ABwrfE6hjANwBAAAA.Corvenall:BAAANQAECgYIDgAAAA==.',
Cr='Crashpad:BAAANQAECgMIAwAAAA==.Crossbow:BAABNQAECoEkAAIOAAkK/BjTLQCkAgAOAAkK/BjTLQCkAgAAAA==.',
Da='Daggers:BAAANQAECgUIBQAAAA==.Dakkan:BAAANQADCggIDAAAAA==.Dallarth:BAAANQADCgUIBQAAAA==.Danidani:BAABNQAECoEaAAIPAAcKjyHiJQCYAgAPAAcKjyHiJQCYAgAAAA==.Darkluster:BAAANQADCgQIBAAAAA==.Darrknes:BAAANQAECgEIAQAAAA==.Darshun:BAAANQADCgUICgAAAA==.Davinah:BAAANQAECgQIBwAAAA==.Dayje:BAAANQADCgIIAwAAAA==.',
De='Deathation:BAAANQADCgUICAAAAA==.Deathbcmesyu:BAAANQAECgUIDQAAAA==.Demonovest:BAAANQAECgUICgAAAA==.',
Di='Diehappy:BAAANQADCgcIEAAAAA==.Dishonor:BAAANQADCgMIBQAAAA==.',
Do='Dommage:BAAANQAECgUIBQAAAA==.Donkyote:BAAANQADCgEIAQAAAA==.Downbadd:BAAANQABCgQIBQAAAA==.',
Dr='Druida:BAAANQAECgYICAAAAA==.Drywar:BAABNQAECoEbAAILAAkK3iBtJQD8AgALAAkK3iBtJQD8AgAAAA==.Dràgonkíng:BAAANQADCgcIGwAAAA==.',
Dt='Dtinnel:BAAANQAECgYIEQABNQAECgkJNgAQANwkAA==.',
['Dà']='Dànger:BAAANQAECgUICAAAAA==.',
Ef='Efran:BAAANQABCgIIAgAAAA==.',
Eg='Ego:BAABNQAECoEZAAILAAgKgh/uMQDHAgALAAgKgh/uMQDHAgAAAA==.',
Ei='Eisla:BAAANQAECgYIEgAAAA==.',
El='Elfor:BAAANQADCgMIAwABNQAECgUIDgABAAAAAA==.',
Em='Emmone:BAAANQAECgQICAAAAA==.',
Ex='Exacerbator:BAAANQADCgYIGAAAAA==.',
Fa='Falcon:BAAANQABCgQIBQAAAA==.Fargecia:BAAANQAECgUICAAAAA==.Faunna:BAABNQAECoEoAAICAAkKmBgFHwCgAgACAAkKmBgFHwCgAgAAAA==.',
Fe='Fearbomb:BAAANQADCgQIBAAAAA==.Feath:BAAANQADCgIIAgAAAA==.Feebeeboofae:BAAANQAECgYIDwAAAA==.Felaz:BAABNQAECoEbAAIRAAcK9RmdlgAPAgARAAcK9RmdlgAPAgAAAA==.Feoridor:BAAANQADCgIIAgAAAA==.Festy:BAAANQADCggICAAAAA==.',
Fi='Fingerguns:BAABNQAECoEnAAMPAAkKWiA/CQBXAwAPAAkKWiA/CQBXAwASAAUK2wbyEADhAAAAAA==.',
Fl='Floortank:BAAANQAECgUIBwAAAA==.',
Fr='Friday:BAAANQAECgUICAAAAA==.Frikilatar:BAAANQABCgQICAAAAA==.Frrank:BAABNQAECoEkAAILAAkKoCaUAQDtAwALAAkKoCaUAQDtAwAAAA==.',
Ga='Galcain:BAABNQAECoEeAAMOAAkK0h5xIQDZAgAOAAgK7R9xIQDZAgATAAYKkRPvKwCXAQAAAA==.',
Go='Googleyes:BAAANQADCgUICgAAAA==.Goss:BAAANQADCgYICAAAAA==.',
Gr='Graphene:BAAANQADCgQICQAAAA==.Greybull:BAAANQAECgQJCwAAAA==.Griffy:BAAANQADCgQIBAAAAA==.Grimseek:BAAANQAECgUIDgABNQAFFAUICgAMALsIAA==.Growlyr:BAABNQAECoEdAAMQAAgKfSC3FQDVAgAQAAgKfSC3FQDVAgAUAAEKChj7ewBFAAAAAA==.Grumandel:BAAANQAECgUIDAAAAA==.',
Ha='Hakur:BAABNQAECoEbAAIVAAgKYxCeeADaAQAVAAgKYxCeeADaAQAAAA==.Hammertóe:BAAANQADCggIGgAAAA==.Hanma:BAAANQAECgYIEAAAAA==.Harribel:BAAANQAECgUIDgAAAA==.',
He='Heiferina:BAAANQAECgcICQAAAA==.Helixra:BAAANQAECgUICQAAAA==.Hellcroh:BAAANQAECgMIAwAAAA==.',
Hi='Hiyodam:BAAANQADCgUIAwAAAA==.Hiyodaw:BAAANQADCgIIAgAAAA==.Hizzon:BAAANQADCgcIDAAAAA==.',
Hy='Hyperíon:BAAANQAECgEIAQAAAA==.',
Ic='Icies:BAAANQAECgUIEwAAAA==.',
Is='Iselle:BAAANQADCgYIBgAAAA==.Ishamaël:BAAANQADCgUIBQABNQAECgkJHQAGALUWAA==.',
Ja='Jailene:BAAANQABCgUIBQAAAA==.Jawny:BAAANQADCgUIBQAAAA==.',
Jc='Jclif:BAABNQAECoEYAAIRAAcK3RATtwDHAQARAAcK3RATtwDHAQAAAA==.',
Je='Jehannum:BAAANQAECgUICwAAAA==.Jessira:BAAANQAECgUJDwAAAA==.',
Jo='Jonahheal:BAABNQAECoEVAAIWAAgKQSCEFgD5AgAWAAgKQSCEFgD5AgABNQAFFAUIDgAXAKseAA==.Josen:BAAANQAECgYIEQAAAA==.',
Ka='Kach:BAAANQAECgEIAQAAAA==.Kaimi:BAAANQADCgQIDQAAAA==.Kainiy:BAAANQADCgYIFQAAAA==.Kaizenn:BAAANQADCgIIAgAAAA==.Kaladjin:BAABNQAECoEYAAQYAAcKJBJKIgC5AQAYAAcKFBJKIgC5AQAZAAcKWAgsFgA0AQAaAAYKEglRJQD6AAAAAA==.Katarena:BAAANQAECgYIDQAAAA==.Kathyra:BAEBNQAECoEZAAMNAAYK9Qt0mgA/AQANAAYK9Qt0mgA/AQAMAAEKfwIPeQAiAAABNQAECgkJJAAJAHgRAA==.Kavax:BAAANQAECgUIDAAAAA==.',
Ke='Keel:BAAANQADCgEIAQAAAA==.Keeller:BAAANQAECgMIBAAAAA==.Keleris:BAAANQADCgcIDAAAAA==.Kentyr:BAAANQADCgQIBQAAAA==.Kez:BAAANQAECgQIBAAAAA==.',
Kh='Khasket:BAAANQAECgEIAQAAAA==.',
Ki='Kinký:BAABNQAECoEcAAILAAgKSRD7dADnAQALAAgKSRD7dADnAQABNQADCgcJBwABAAAAAA==.Kiraelis:BAAANQAECgYIDgAAAA==.',
Ko='Konvik:BAAANQADCgIIAgAAAA==.Korvoh:BAAANQAECgUIDgAAAA==.',
Kr='Kragar:BAAANQADCgIIAgAAAA==.Kredriel:BAAANQAECgEJAQAAAA==.Krinmate:BAACNQAFFIEKAAIPAAUKKxGuCQCnAQAPAAUKKxGuCQCnAQA1AAQKgSQAAw8ACQrTEPBHAP4BAA8ACQqDEPBHAP4BABIABQpTBy8RAN0AAAAA.Krystn:BAAANQAECgEIAQAAAA==.',
Ku='Kumaro:BAAANQABCgYIBgAAAA==.Kuurome:BAAANQADCgMIAwABNQAECgkJNgAQANwkAA==.',
Kw='Kwinny:BAAANQAECgUIDgAAAA==.',
Ky='Kyloris:BAAANQAECggIAgAAAA==.Kynthria:BAAANQAECgYIDwAAAA==.',
['Kä']='Kämik:BAAANQAECgUICwAAAA==.',
['Kì']='Kìn:BAAANQADCgQIBQAAAA==.',
La='Lampion:BAAANQAECgYIEgAAAA==.Landon:BAAANQADCgYIBgABNQAECgYIDAABAAAAAA==.Lasstchance:BAAANQADCgcIEAAAAA==.Latinamaddog:BAAANQAECgYIEgAAAA==.',
Le='Leijona:BAAANQADCgYIDQAAAA==.Lelathon:BAAANQAECggICAAAAA==.Lenard:BAAANQADCgYIFAAAAA==.Leröth:BAAANQAECgQIBQAAAA==.',
Li='Likeatrain:BAAANQAECgUIDQAAAA==.Lilwagyu:BAAANQAECgYIBgAAAA==.Linds:BAAANQAECgYIEAAAAA==.',
Lo='Lokininja:BAAANQAECgEIAgAAAA==.Lokki:BAAANQADCgYJBgAAAA==.Loofuh:BAAANQADCgYIBgAAAA==.',
Lt='Ltdanslegs:BAAANQAECgcIEwAAAA==.',
Lu='Luardreu:BAAANQADCgQIBAAAAA==.Luxu:BAABNQAECoEjAAIbAAgKjyGhEgDuAgAbAAgKjyGhEgDuAgAAAA==.Luxzy:BAAANQAECgEIAQAAAA==.',
Ma='Magicbarbee:BAAANQADCgYJDAAAAA==.Makarich:BAAANQAECgQICAAAAA==.Malachron:BAAANQAECgUICAAAAA==.Manbearcat:BAAANQAECgUIDAAAAA==.Marbleous:BAABNQAECoEeAAILAAcKQB9aVQBIAgALAAcKQB9aVQBIAgAAAA==.',
Mc='Mcpink:BAAANQADCgUICQABNQAECgUIDAABAAAAAA==.',
Me='Meatcurtains:BAAANQADCgUIBQABNQAECgYIDAABAAAAAA==.Melancholic:BAAANQADCggICQABNQAECgQICAABAAAAAA==.Memisstotem:BAAANQAECgcIEAAAAA==.Merle:BAABNQAECoElAAMLAAkKJyDGGAA5AwALAAkKJyDGGAA5AwAFAAUKZxmfEQA0AQAAAA==.',
Mi='Minaxy:BAABNQAECoEkAAIVAAgKVx2BQACKAgAVAAgKVx2BQACKAgAAAA==.Mistborn:BAAANQAECgYICwABNQAECgYIEgABAAAAAA==.Mistsofpoly:BAAANQADCgcIEAABNQAFFAUICAAXAKYLAA==.',
Mo='Momoku:BAAANQAECgUIDQAAAA==.Moolimbo:BAAANQADCggICAABNQAECgcIGAACAFkRAA==.Mootalstrike:BAAANQAECgYIEAAAAA==.Moshworm:BAAANQAECgUIDwAAAA==.',
Mu='Muramasa:BAAANQAECgEIAQABNQAECgkJNgAQANwkAA==.',
Mv='Mvp:BAAANQADCgcIDgAAAA==.',
Na='Namis:BAAANQADCgQIBAAAAA==.',
Ne='Nelaphim:BAABNQAECoEWAAMcAAYKKB4uCgDVAQAcAAYKKB4uCgDVAQARAAYKXwvv5gBpAQAAAA==.Nexassin:BAAANQAECgEIAQAAAA==.',
Ni='Nico:BAAANQAECgcIEAAAAA==.Nightfang:BAAANQADCggIBQAAAA==.Nimz:BAAANQAECgUICAABNQAECgYIDAABAAAAAA==.',
No='Noctrine:BAAANQABCgYICQAAAA==.Noxxidari:BAAANQAECgYIEwAAAA==.Noxxus:BAAANQAECgcIEgAAAA==.',
Ny='Nymphis:BAAANQADCgQIBgAAAA==.Nymunandria:BAAANQADCgUIBQAAAA==.Nymz:BAAANQADCgQIBAABNQAECgYIDAABAAAAAA==.',
Ob='Oblivia:BAAANQADCggIBAAAAA==.Obsidiansoul:BAAANQADCgcIBwAAAA==.',
On='Onagne:BAAANQAECgEIAQABNQAECgkJIQALAN8bAA==.Onepunch:BAAANQADCgcIBwAAAA==.',
Or='Orchist:BAAANQAECgUIDAAAAA==.Orimbo:BAABNQAECoEYAAMCAAcKWRHETQBZAQACAAYKZg/ETQBZAQAdAAEK6gGiXgAqAAAAAA==.',
Pa='Paidu:BAABNQAECoEcAAMeAAkKChViOACIAQAIAAgK8QmyKwCkAQAeAAUKsxxiOACIAQAAAA==.Palaritaz:BAAANQAECgIIBAABNQAECgYIEgABAAAAAA==.',
Pe='Pestilancé:BAAANQAECgUIDgAAAA==.',
Ph='Phenothal:BAAANQADCgQIBAAAAA==.',
Pi='Pinktp:BAAANQAECgIIAgAAAA==.Pion:BAAANQADCgQIBAAAAA==.Pitchblende:BAABNQAECoEZAAIWAAcK3xAmXgCxAQAWAAcK3xAmXgCxAQAAAA==.',
Po='Polylock:BAAANQAECgQIBQAAAA==.Portiaa:BAAANQAECgMIBAAAAA==.',
Pr='Prangkim:BAAANQADCgUICQAAAA==.Protagoras:BAAANQADCgQIBAAAAA==.',
Pu='Purejoy:BAAANQAECgIIAwAAAA==.',
Qu='Quickslice:BAAANQADCgcJBwAAAA==.Quillz:BAAANQAECgQICAAAAA==.',
Ra='Rajak:BAAANQADCgMIAwAAAA==.Rathidk:BAABNQAECoEtAAIbAAkKqiOABgB4AwAbAAkKqiOABgB4AwAAAA==.',
Re='Redine:BAAANQADCgcICgAAAA==.Reen:BAAANQADCgcICQAAAA==.Rellt:BAAANQADCgcIEAAAAA==.Rendis:BAAANQAECgQIBQAAAA==.',
Rh='Rhayge:BAAANQAECgUIDgAAAA==.',
Ri='Riemann:BAAANQABCggICwAAAA==.',
Ro='Roxas:BAAANQADCgIIAgAAAA==.',
Ru='Ruukia:BAABNQAECoE2AAIQAAkK3CQ5BgB7AwAQAAkK3CQ5BgB7AwAAAA==.',
Sa='Saboo:BAAANQAECgYIEQAAAA==.Sahki:BAAANQADCgUIDAAAAA==.Saltybreath:BAAANQAECgUIDgABNQAECgcIEwABAAAAAA==.Sapientia:BAAANQAECgUJBgAAAA==.Savagex:BAAANQADCgMIAwAAAA==.',
Sc='Scottkill:BAAANQADCggIDAABNQAFFAUIDgARACcYAA==.',
Se='Seasnan:BAAANQAECgEIAQAAAA==.Segur:BAAANQABCgIIAgAAAA==.Seluna:BAAANQAECgcIEgAAAA==.Senlock:BAAANQABCgIIAgABNQAECgUIDAABAAAAAA==.',
Sh='Shadizzon:BAAANQABCgQJBAAAAA==.Shadowcloak:BAAANQABCgMIAwAAAA==.Shadowdeath:BAAANQAECgUIEQAAAA==.Shadowheàrt:BAAANQAECgIIAwAAAA==.Shadowshifty:BAAANQADCgcJBwAAAA==.Shadowtotem:BAAANQAECgQIBAAAAA==.Shagi:BAAANQADCgcIBwABNQADCgcJDAABAAAAAA==.Shamdü:BAABNQAECoEnAAILAAkK9BtINAC9AgALAAkK9BtINAC9AgAAAA==.Shanson:BAAANQAECgYICwAAAA==.Sharroz:BAAANQAECgIIBAAAAA==.Shizuuku:BAAANQADCgEIAQABNQAECgkJNgAQANwkAA==.Shockybalboa:BAAANQAECgYICgAAAA==.Showerthots:BAAANQADCggIIAAAAA==.',
Si='Silvver:BAAANQADCgcIBwAAAA==.Sineth:BAAANQADCggIEAAAAA==.',
Sk='Skooda:BAABNQAECoEdAAIGAAgKdQ3HVADWAQAGAAgKdQ3HVADWAQAAAA==.Skyded:BAAANQADCgUIBQAAAA==.Skyfell:BAABNQAECoEYAAIIAAcKcxaZIgD5AQAIAAcKcxaZIgD5AQAAAA==.Skyknight:BAAANQAECgUIBwAAAA==.',
Sl='Sloan:BAAANQADCgMIAwAAAA==.',
Sn='Snapahead:BAAANQAECgEIAQAAAA==.',
So='Solcon:BAAANQAECgUIDQAAAA==.Solence:BAAANQADCgIIAgAAAA==.Somebodie:BAAANQAECgIIAgAAAA==.',
Sp='Spaazz:BAAANQAECgYIEgAAAA==.Sparkwire:BAAANQADCggICAAAAA==.',
Sq='Squeakbolt:BAAANQADCgcIDwAAAA==.',
St='Starofdreams:BAAANQADCgEIAQABNQAECgYIEQABAAAAAA==.Starweaver:BAAANQAECgYIEQAAAA==.Stormrender:BAABNQAECoEZAAMYAAcKQxZFHwDcAQAYAAcKQxZFHwDcAQAaAAEK5AKtRAAiAAAAAA==.Stormsong:BAABNQAECoEZAAMGAAkK1hq5IgDFAgAGAAkK1hq5IgDFAgAXAAMK8gq9wQCRAAAAAA==.Strangecandy:BAAANQAECgIIAwAAAA==.Strangrdangr:BAAANQADCgQIBAAAAA==.Strángeland:BAAANQAECgIIAgAAAA==.Störmrender:BAAANQADCgcIDgABNQAECgcIGQAYAEMWAA==.',
Su='Suhalo:BAAANQADCgMIAwAAAA==.Sunarianna:BAAANQAECgQIBgAAAA==.Superpull:BAAANQAECgUICQABNQABCgIIAgABAAAAAA==.',
Sy='Sycla:BAABNQAECoEXAAMMAAgKlhN7GACbAQAMAAYKnBV7GACbAQANAAIKgw2s6QCAAAAAAA==.Sylas:BAAANQAECgQICAAAAA==.',
Ta='Taloriesh:BAAANQAECgQICwAAAA==.Tanazir:BAEANQAECgEIAQAAAA==.Tarok:BAAANQADCgUICQAAAA==.Tashien:BAAANQAECgMIAwAAAA==.',
Te='Tealzin:BAAANQABCgQIBQAAAA==.Techytechy:BAAANQAECgYIBgAAAA==.Teito:BAAANQAECgMIBgAAAA==.Terenii:BAAANQAECgIIAgAAAA==.',
Ti='Tilamano:BAABNQAECoEdAAQNAAgKwyNrEQAhAwANAAgKXSNrEQAhAwAMAAUKWSMhDwD3AQAfAAUKECGkCACxAQAAAA==.Tilatree:BAAANQAECgEIAgABNQAECggIHQANAMMjAA==.',
To='Tohrnarc:BAABNQAECoEYAAIRAAYKmiH+hAA4AgARAAYKmiH+hAA4AgAAAA==.Tookkiiee:BAAANQAECggICwAAAA==.Totem:BAAANQAECgQIBgAAAA==.Totemwebz:BAAANQAECgUIDAAAAA==.',
Tr='Trenve:BAAANQAECgYIEgAAAA==.',
Tu='Turbomage:BAAANQADCgcIBwAAAA==.Tuzzyfits:BAABNQAECoEZAAIXAAcKmRuWPAAkAgAXAAcKmRuWPAAkAgAAAA==.',
Ty='Tyrethia:BAAANQAECgQICQAAAA==.',
['Té']='Téchymoon:BAABNQAECoEoAAIMAAkKBxQYBwCDAgAMAAkKBxQYBwCDAgAAAA==.',
Ug='Ugo:BAAANQAECgQIBAAAAA==.',
Um='Umbron:BAABNQAECoEgAAQHAAkKehqLDwDFAgAHAAkKZRmLDwDFAgAgAAcKLxoDFwAEAgAhAAEKMA8iGAA0AAAAAA==.',
Un='Undertaker:BAAANQABCggIDAAAAA==.',
Va='Valcristo:BAABNQAECoEWAAIiAAYKKSWhEABGAgAiAAYKKSWhEABGAgAAAA==.Valdun:BAAANQADCgYIDwAAAA==.Vanaras:BAAANQADCgYIBwAAAA==.Vargrim:BAAANQAECgUIEQAAAA==.',
Ve='Venous:BAABNQAECoEXAAMHAAcKwRPtLgCzAQAHAAcKwRPtLgCzAQAgAAUK8Q3aKgA3AQAAAA==.Vestt:BAAANQADCggIFQAAAA==.',
Vi='Vicariana:BAABNQAECoEiAAQjAAkKECA7FgBnAgAjAAcKFh47FgBnAgAPAAgKyxagVADKAQASAAMK9SQzDABDAQAAAA==.Victhyr:BAAANQAECgUICQAAAA==.Vidette:BAAANQADCgYIDAAAAA==.Viduus:BAAANQAECgYIDAAAAA==.Viv:BAAANQAECgUJCgAAAA==.',
Vo='Vodmor:BAAANQAECgQIDAAAAA==.Voldermort:BAAANQADCgcIEwAAAA==.',
Wa='Warrendemon:BAABNQAECoESAAIIAAkKXx/XEADDAgAIAAkKXx/XEADDAgAAAA==.',
We='Wedowarcrime:BAAANQADCgIIAgAAAA==.',
Wh='Whims:BAAANQAECgUIBgAAAA==.',
Wi='Wildheart:BAAANQAECgEJAQAAAA==.Wingchún:BAAANQADCgIIAgAAAA==.',
Wo='Woregontail:BAAANQADCgcIFAAAAA==.Wowbelly:BAAANQAECgQIBQAAAA==.',
Xa='Xandeath:BAAANQAECgQIBAAAAA==.Xandros:BAAANQAECgYICwAAAA==.',
Xo='Xonk:BAABNQAECoEhAAIfAAkKnBm/BABGAgAfAAkKnBm/BABGAgAAAA==.',
Yg='Ygcamel:BAAANQADCggJEgAAAA==.',
Yi='Yiazmat:BAAANQABCgcICwAAAA==.',
Za='Zaklu:BAAANQAECgIIAwAAAA==.Zalagrimbor:BAABNQAECoEdAAMGAAkKtRZRLwB9AgAGAAkKtRZRLwB9AgAXAAMKgAXV0QBrAAAAAA==.Zalathar:BAAANQABCgQIBAAAAA==.Zaps:BAABNQAECoEZAAIGAAcKqCHwJQCyAgAGAAcKqCHwJQCyAgAAAA==.Zarev:BAACNQAFFIELAAITAAUKxR0OBQDHAQATAAUKxR0OBQDHAQA1AAQKgSIAAhMACQpyIkMKABEDABMACQpyIkMKABEDAAAA.',
Ze='Zeenab:BAAANQADCgIIAgAAAA==.Zegrath:BAAANQADCgcJDAAAAA==.Zelie:BAABNQAECoEWAAMXAAYKRAvYiQAaAQAXAAYKRAvYiQAaAQAGAAUK9wBB2ABwAAAAAA==.Zenreto:BAAANQAECgUIDgAAAA==.',
Zo='Zoeri:BAAANQAECgEIAQAAAA==.Zoltraak:BAAANQADCgYIDwAAAA==.',
['Än']='Änmoa:BAABNQAECoErAAIDAAkKtiVlAADnAwADAAkKtiVlAADnAwAAAA==.',
['Ïn']='Ïnsane:BAAANQAECgIIAgAAAA==.',
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
