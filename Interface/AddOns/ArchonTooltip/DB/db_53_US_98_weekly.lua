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

local lookup = {'Druid-Balance','Mage-Arcane','Paladin-Retribution','Unknown-Unknown','Paladin-Protection','Paladin-Holy','DeathKnight-Frost','DeathKnight-Blood','Hunter-Marksmanship','Warlock-Affliction','Warlock-Demonology','Monk-Windwalker','Shaman-Elemental','Monk-Brewmaster','Hunter-BeastMastery','Druid-Restoration','Shaman-Restoration','Warlock-Destruction','Rogue-Subtlety','Rogue-Assassination','Priest-Holy','Warrior-Fury','Warrior-Arms','DemonHunter-Vengeance','DemonHunter-Havoc','Mage-Frost','Druid-Feral','Shaman-Enhancement','DeathKnight-Unholy','Evoker-Preservation','Evoker-Devastation','Hunter-Survival','Warrior-Protection','Priest-Discipline','Priest-Shadow','Evoker-Augmentation','Monk-Mistweaver',}
local provider = {region='US',realm='Frostmane',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abaz:BAAANQADCgYICQAAAA==.Aberdus:BAABNQAECoEaAAIBAAgKLhBBPgDbAQABAAgKLhBBPgDbAQAAAA==.Abysswalker:BAAANQADCgMIAwAAAA==.',
Ac='Accalon:BAAANQAECgUIDwAAAA==.',
Ad='Advacus:BAACNQAFFIEGAAICAAMKkR1fJQAZAQACAAMKkR1fJQAZAQA1AAQKgRwAAgIACQrFIeIrAC0DAAIACQrFIeIrAC0DAAAA.',
Ag='Agamar:BAAANQAECgEIAQAAAA==.Ageina:BAAANQADCggICAABNQAFFAQIBwADAC4gAA==.Agnostec:BAAANQADCgIIAwAAAA==.',
Ak='Akrama:BAAANQAECgUIDwAAAA==.',
Al='Alatáriel:BAAANQAECgEJAQAAAA==.Alectrona:BAAANQADCgYICAAAAA==.Althenot:BAAANQADCgcIDwAAAA==.',
Am='Amari:BAAANQADCgEIAQAAAA==.Amegoracy:BAAANQAECgUIDQAAAA==.',
An='Andalorian:BAAANQAECgMJAwAAAA==.Anderthel:BAAANQADCgQIBQAAAA==.Anruu:BAAANQAECgcIDgAAAA==.',
Ar='Araleth:BAAANQADCggICwAAAA==.Aratol:BAAANQADCggICAABNQAECgYIEAAEAAAAAA==.Archolaoch:BAABNQAECoEeAAIFAAgKzBV1GgDyAQAFAAgKzBV1GgDyAQAAAA==.Arconite:BAAANQADCgQIBQABNQAECgcIDAAEAAAAAA==.Arizonatea:BAAANQAECgEIAQAAAA==.Arkthurus:BAAANQAECgIJAgAAAA==.',
As='Ashenknight:BAAANQADCgEJAQAAAA==.Ashijin:BAABNQAECoEeAAMDAAkK+BcIZABBAgADAAkK+BcIZABBAgAGAAEKAgHzHwETAAAAAA==.Astei:BAAANQADCgUIBQAAAA==.',
At='Athelos:BAAANQAECgEIAQAAAA==.Atroce:BAABNQAECoElAAMHAAkK4iKICgAxAwAHAAgK1yOICgAxAwAIAAgK2xuKKQBcAgAAAA==.',
Au='Aura:BAAANQAECgYIDwAAAA==.Auxilium:BAAANQADCggIDgAAAA==.',
Aw='Awnen:BAAANQAECgIIAwAAAA==.',
Ax='Axes:BAAANQAECgIIAgAAAA==.Axkicker:BAABNQAECoE1AAIJAAgKWhiTIAAsAgAJAAgKWhiTIAAsAgAAAA==.',
Ay='Aystic:BAAANQAECgEIAQABNQAECgQIBAAEAAAAAA==.',
Ba='Balethar:BAAANQAECgUICgABNQAECggIGgADACkbAA==.Ballador:BAAANQAECgcIDQAAAA==.Balluh:BAAANQAECgYIEAAAAA==.Balzluzzak:BAABNQAECoEeAAMKAAcKvwtjCwCMAQAKAAcKuQtjCwCMAQALAAUKEwVC6ADLAAAAAA==.Baughter:BAAANQABCgcICwAAAA==.',
Be='Beetledeww:BAAANQADCgQIBAAAAA==.Beetledont:BAAANQADCgYIBgAAAA==.Beezbonk:BAAANQAECggICAAAAA==.Bellemorte:BAAANQABCgQIBAAAAA==.Bellmage:BAABNQAECoEZAAICAAgKMBkPewBwAgACAAgKMBkPewBwAgAAAA==.Belttoash:BAAANQADCggIGwAAAA==.Beneficiary:BAAANQADCgYIBgAAAA==.Bestricer:BAACNQAFFIEsAAIMAAgKLSM5AABOAwAMAAgKLSM5AABOAwA1AAQKgS0AAgwACQpLJjwCALQDAAwACQpLJjwCALQDAAAA.Bevis:BAABNQAECoEZAAILAAgKYR/BJwDNAgALAAgKYR/BJwDNAgABNQAFFAMIBQANAOgZAA==.',
Bi='Bigmayex:BAABNQAECoEeAAIOAAgKIyUfAwBTAwAOAAgKIyUfAwBTAwAAAA==.Bilmuri:BAABNQAECoEWAAMPAAkKhRzVLADGAgAPAAgKSB3VLADGAgAJAAUKjxF+QgAPAQAAAA==.Bippot:BAABNQAECoErAAIDAAkKbCCmJwAMAwADAAkKbCCmJwAMAwAAAA==.',
Bl='Blackbride:BAAANQADCggICgAAAA==.Bloodybill:BAAANQADCgUJBQAAAA==.Blort:BAAANQADCggICAAAAA==.',
Bo='Bombadormu:BAAANQADCgcIBwAAAA==.Bonezs:BAABNQAECoEiAAIQAAgKMyRuBgBJAwAQAAgKMyRuBgBJAwAAAA==.Boredfordays:BAAANQAECgEIAQAAAA==.Bossvega:BAAANQADCggILAAAAA==.',
Br='Bruhkakke:BAAANQAECggIBAABNQAFFAUIDAARAIwJAA==.',
Bu='Bucon:BAAANQADCgYIDAAAAA==.Bugbear:BAAANQAECgEIAQAAAA==.Bumbly:BAAANQAECgUIDAAAAA==.Bushybrowsy:BAABNQAECoErAAMKAAgKORFJBwAIAgAKAAgKORFJBwAIAgASAAEK2gN+cwA1AAAAAA==.Buttermeupz:BAABNQAECoEZAAIGAAgKERLAVwDwAQAGAAgKERLAVwDwAQAAAA==.Buttsnorkle:BAAANQAECgIIAgAAAA==.',
['Bá']='Bámboo:BAAANQAECgQICAAAAA==.',
Ca='Cacho:BAAANQAECgcIEQAAAA==.Cactuss:BAAANQAECgQICAABNQAECgkJHgACAEsJAA==.Caothand:BAAANQAECgQIBAAAAA==.',
Cc='Ccyll:BAAANQADCgcIEAAAAA==.',
Ce='Celindri:BAAANQADCgcIBwAAAA==.Cerridwen:BAAANQABCgIIAgAAAA==.',
Ch='Chazandi:BAAANQADCgQIBAABNQAECgkJKgACAOUVAA==.Chazpriest:BAAANQAECgcIBwABNQAECgkJKgACAOUVAA==.Chazzbadgurl:BAAANQAECgcICwABNQAECgkJKgACAOUVAA==.Chazzie:BAAANQADCgYIBgABNQAECgkJKgACAOUVAA==.Chexmix:BAABNQAECoEZAAMTAAYKFQwaKQBiAQATAAYKdQsaKQBiAQAUAAQKzgiOZQDLAAAAAA==.Chicho:BAAANQAECgIIAgABNQAECgkJKgAQAKobAA==.Chomboslice:BAAANQAECgcIEAAAAA==.',
Ci='Cinnamon:BAABNQAECoEjAAIVAAgK/R29IwDBAgAVAAgK/R29IwDBAgAAAA==.',
Cm='Cmil:BAACNQAFFIELAAMGAAUKuBHOCQCcAQAGAAUKuBHOCQCcAQADAAEKwgEvKwBEAAA1AAQKgSkABAYACQqHH08VABgDAAYACQqHH08VABgDAAMABwrFDfqwAIQBAAUAAgrBFKtSAGcAAAAA.',
Co='Coffeegin:BAAANQADCgMIAwAAAA==.',
Cr='Crittingbull:BAAANQAECgQICQAAAA==.Cruiddeath:BAAANQAECgQICQABNQAECgkJJAAWAEYLAA==.',
Cu='Curserodlock:BAABNQAECoEkAAMWAAkKRgvtDgCaAQAWAAgKtwvtDgCaAQAXAAYKvQWB4QDuAAAAAA==.',
Cy='Cyanide:BAAANQAECgYICwAAAA==.',
Da='Dabbinshamin:BAAANQADCggIDwAAAA==.Dads:BAACNQAFFIEVAAINAAcKYBV0AgBtAgANAAcKYBV0AgBtAgA1AAQKgR8AAw0ACQr5InEPAF8DAA0ACQr5InEPAF8DABEAAwpKARzoAGoAAAAA.Daedra:BAAANQAECgYIDQABNQAECggIFwAJAL4KAA==.Daillin:BAAANQADCgEIAQAAAA==.Dakadakadaka:BAABNQAECoEcAAMJAAgK9B2UHgA/AgAJAAcKAx6UHgA/AgAPAAEKiR3GIwFZAAAAAA==.Darcdk:BAAANQAECgUICwABNQAFFAUIDwAGAPsOAA==.Darcevoker:BAAANQADCgcIBwABNQAFFAUIDwAGAPsOAA==.Darcpaladin:BAACNQAFFIEPAAIGAAUK+w4uCwCGAQAGAAUK+w4uCwCGAQA1AAQKgSQAAgYACQrLGdcgANQCAAYACQrLGdcgANQCAAAA.Darcpriest:BAAANQAECgQIBQABNQAFFAUIDwAGAPsOAA==.Darkrune:BAAANQAECgIIAwAAAA==.Darkschneide:BAABNQAECoEVAAILAAkKQxDCWwAiAgALAAkKQxDCWwAiAgAAAA==.Darthboo:BAAANQAECgQIBQAAAA==.Darthknight:BAAANQADCggICwABNQAECgkJJgADAIwfAA==.Darthtemplar:BAABNQAECoEmAAQDAAkKjB8LJAAbAwADAAkKjB8LJAAbAwAGAAEKBgfzBwEzAAAFAAEKBA/6aQAmAAAAAA==.',
De='Deathbug:BAAANQADCggICQAAAA==.Deckaye:BAAANQAECgMIAQABNQAECgUICgAEAAAAAA==.Deimoes:BAAANQAECgQIBAAAAA==.Demodorn:BAACNQAFFIEKAAIYAAQK9AF0AwCeAAAYAAQK9AF0AwCeAAA1AAQKgS8AAhgACQreC3MOAKABABgACQreC3MOAKABAAAA.Demyst:BAACNQAFFIEJAAIRAAQKrhpZDABdAQARAAQKrhpZDABdAQA1AAQKgSQAAxEACQprHT8aAOwCABEACQprHT8aAOwCAA0AAgqUDZb3AGIAAAAA.Demön:BAAANQAECgMIAwAAAA==.Dewwarrior:BAAANQAECgUICwAAAA==.Dezeraz:BAEANQAECgYIBgABNQAFFAUIEQAVABoaAA==.',
Dh='Dhecaye:BAAANQAECgUICgAAAA==.',
Di='Disengage:BAAANQAECgUICAABNQAFFAQICAACAO8VAA==.',
Do='Dohdan:BAAANQAECgIIAgAAAA==.Donkey:BAABNQAECoEeAAIGAAgKFR0bIwDIAgAGAAgKFR0bIwDIAgAAAA==.Donmega:BAAANQADCggIKAAAAA==.Dougalleone:BAACNQAFFIEIAAIUAAQKwBm7BgBxAQAUAAQKwBm7BgBxAQA1AAQKgR0AAxQACQrbIRoKACMDABQACQrbIRoKACMDABMABgogGL0kAIwBAAAA.Dougallmaki:BAAANQAECgIIAgAAAA==.',
Dr='Drekkwarr:BAAANQAECgEIAQABNQAECggIHQANAKYdAA==.Drentalth:BAAANQADCgEIAQAAAA==.Drezzakzdh:BAAANQAECgYIDAABNQAECgYIDgAEAAAAAA==.Drezzakzz:BAAANQAECgYIDgAAAA==.Drezzpally:BAAANQADCgMIAwAAAA==.',
Du='Dugren:BAAANQAECgIIAQAAAA==.Duracreate:BAAANQAECgIIAwAAAA==.',
Ea='Eamil:BAAANQADCgcJBwAAAA==.',
Ek='Ekaterin:BAABNQAECoErAAICAAkKwSDJLAAqAwACAAkKwSDJLAAqAwAAAA==.Ekewa:BAAANQAECgMIAwAAAA==.',
El='Elaidine:BAABNQAECoEfAAMYAAgK9R0oBQC3AgAYAAgK9R0oBQC3AgAZAAEKRgH0kQANAAAAAA==.Electraknub:BAAANQADCgYICwAAAA==.Electroh:BAAANQAECgYIDgAAAA==.Eliseda:BAAANQAECgQIBQABNQAECggIIgARANkWAA==.',
Em='Emerald:BAAANQABCgQICAAAAA==.',
Ev='Evilnapkin:BAAANQAECgQICAAAAA==.Evion:BAABNQAECoEWAAIPAAcKAxjBZgAcAgAPAAcKAxjBZgAcAgAAAA==.Evoke:BAAANQAECgcICwAAAA==.',
Fa='Falconsha:BAAANQAECgIIAgAAAA==.Fattynattyy:BAAANQADCgYIBgAAAA==.',
Fe='Fendis:BAAANQADCggICAABNQAECgkJLAACABQaAA==.',
Fi='Fiercia:BAAANQAECgUICgABNQAECgkJJwAHAFUkAA==.Firefrost:BAABNQAECoExAAMaAAkK7SCnAQBYAwAaAAkK7SCnAQBYAwACAAEKgQbppQE3AAAAAA==.Firescrotum:BAABNQAECoElAAINAAgK6xGGVQD2AQANAAgK6xGGVQD2AQAAAA==.',
Fl='Flashquinaz:BAAANQADCgYIBgAAAA==.',
Fo='Fourimborniy:BAAANQAECggIEgAAAA==.',
Fr='Frenzi:BAAANQADCgYICQAAAA==.',
Fu='Fundipme:BAAANQAECgQIBAABNQAFFAYIEQAFAMoUAA==.',
['Fá']='Fáelen:BAABNQAECoEcAAIbAAkKCB9FBAArAwAbAAkKCB9FBAArAwAAAA==.',
Ga='Galasmina:BAAANQAECgUIDAAAAA==.Galaxius:BAAANQADCgEIAQABNQAECgcIDAAEAAAAAA==.Ganda:BAAANQADCgEJAQAAAA==.Gangactivity:BAAANQADCgUIBQABNQAECgkJKwAMADYlAA==.Garm:BAABNQAECoEZAAICAAkKjiCiIQBLAwACAAkKjiCiIQBLAwAAAA==.Gavinrad:BAAANQAECgcIDgAAAA==.',
Ge='Generaname:BAAANQADCgcJDQAAAA==.Generanancy:BAAANQADCgIJAgAAAA==.',
Gh='Ghostshadow:BAAANQAECgIIBAAAAA==.',
Gi='Gilene:BAAANQADCgUICAAAAA==.Girthfury:BAABNQAFFIEMAAIRAAUKjAndCwBoAQARAAUKjAndCwBoAQAAAA==.',
Gl='Glaalinix:BAAANQADCgMIBgAAAA==.',
Gn='Gnew:BAAANQADCgUICgAAAA==.Gnumchuck:BAAANQAECgYIEgAAAA==.',
Go='Goat:BAAANQAECgMIAwAAAA==.Goku:BAABNQAECoEiAAMRAAkKpCB0EgAdAwARAAkKpCB0EgAdAwANAAEKeAhyJgEqAAAAAA==.Goodman:BAAANQAECgUIDwAAAA==.Goom:BAAANQAECggIDgABNQAFFAYIEwAMAFccAA==.Goomei:BAACNQAFFIETAAIMAAYKVxwPAwAMAgAMAAYKVxwPAwAMAgA1AAQKgR8AAgwACQqRIFMTAJ0CAAwACQqRIFMTAJ0CAAAA.Goomkin:BAABNQAECoEdAAIBAAkKnRgSKgBjAgABAAkKnRgSKgBjAgABNQAFFAYIEwAMAFccAA==.Gordanramsey:BAAANQADCgUIBQAAAA==.Gorok:BAAANQAECgIIAgAAAA==.',
Gr='Gravymonk:BAAANQAECgcIDwAAAA==.Greatbooty:BAAANQAECgIIBAAAAA==.Gremmi:BAAANQADCgYIBgAAAA==.Grishy:BAAANQAECggICAABNQAFFAQICAACAO8VAA==.Grombeefdal:BAAANQADCgYICwAAAA==.Grosgland:BAAANQAECgEIAQAAAA==.Groundbeéf:BAACNQAFFIEQAAIcAAUKyR1rAQDXAQAcAAUKyR1rAQDXAQA1AAQKgSMAAhwACQryJHEDAGADABwACQryJHEDAGADAAAA.Grovoath:BAAANQADCgcIDQAAAA==.Grumpypally:BAAANQAECgQIBwAAAA==.',
Gu='Gurthon:BAAANQADCggIDwAAAA==.',
Ha='Halligan:BAAANQAECgQICAAAAA==.Hallowfear:BAAANQAECgUJDgAAAA==.Handadinite:BAAANQADCgUICAAAAA==.Handysummons:BAABNQAECoEaAAILAAgK4RzuMwCfAgALAAgK4RzuMwCfAgAAAA==.Harie:BAAANQAECgUICQAAAA==.Harydotter:BAAANQAECgYIBgAAAA==.Hawtsoss:BAAANQABCgQIBwAAAA==.',
He='Hein:BAAANQAECgQIBwAAAA==.Heiny:BAABNQAECoEuAAQIAAkKziXCAwCuAwAIAAkKtCTCAwCuAwAHAAcKOyNeFgC1AgAdAAYKaiRILwBQAgAAAA==.Heinyheinyho:BAAANQADCgMIBAABNQAECgkJLgAIAM4lAA==.',
Ho='Hoid:BAAANQAECgQIBAAAAA==.Holeybeef:BAAANQAECgQICAAAAA==.Holymoly:BAAANQADCgMIAQABNQAECgkJMQAaAO0gAA==.Holynoodles:BAAANQAECgcIEwAAAA==.Holytest:BAACNQAFFIEGAAIVAAMKix5DFQAdAQAVAAMKix5DFQAdAQA1AAQKgS4AAhUACQoSIsYQACwDABUACQoSIsYQACwDAAAA.Hoofmetoo:BAAANQAECgYIEAAAAA==.Howboudah:BAAANQADCgcIBwAAAA==.',
Hu='Hulzar:BAAANQAECgcIEgAAAA==.',
Hy='Hypernova:BAAANQADCgYIBgAAAA==.Hypocrisy:BAAANQAECggICAAAAA==.',
['Hô']='Hôlyblight:BAABNQAECoEtAAMGAAkKZxnYJwCxAgAGAAkKZxnYJwCxAgADAAgKkxF0jADZAQAAAA==.',
Ib='Ibis:BAAANQAECgYIBQABNQAECgkJGwAeABENAA==.',
Id='Idotyouto:BAAANQADCgcIBwAAAA==.',
Il='Ilbryen:BAAANQAECgQIBQABNQAFFAQICQAXADYUAA==.Illaam:BAAANQADCggIDAAAAA==.Illidrag:BAAANQAECggIEQAAAA==.Ilovejacky:BAAANQADCgQIBQABNQADCgYICwAEAAAAAA==.',
Im='Immørtlzed:BAACNQAFFIEVAAIRAAcKiyPSAADHAgARAAcKiyPSAADHAgA1AAQKgSgAAxEACQq6JR0DAKkDABEACQq6JR0DAKkDAA0AAgpUFYLlAI4AAAAA.',
In='Inara:BAAANQADCgEIAQABNQAECgkJJAAMAMAVAA==.Insurion:BAAANQAECgQIBgAAAA==.Invective:BAAANQAECgUICQAAAA==.',
Ir='Ironstorm:BAAANQADCgQIBAAAAA==.',
Iz='Izzyumi:BAAANQADCgYIBgAAAA==.',
Ja='Jarizard:BAACNQAFFIENAAIeAAUK9wqfCgBSAQAeAAUK9wqfCgBSAQA1AAQKgSYAAx4ACQpbFH4VAEYCAB4ACQpbFH4VAEYCAB8AAQrzB+A5ADAAAAAA.Jarrie:BAAANQAECgQIBAAAAA==.Jassar:BAAANQAECgEJAgAAAA==.Jaxek:BAABNQAECoEmAAIbAAkKAyNUAgCAAwAbAAkKAyNUAgCAAwAAAA==.Jaxs:BAACNQAFFIEMAAIRAAUKDxFbCgCHAQARAAUKDxFbCgCHAQA1AAQKgSQAAhEACQoIGsYxAHQCABEACQoIGsYxAHQCAAAA.Jaylen:BAAANQAECgQICQAAAA==.Jaymo:BAAANQAECgcIEAAAAA==.',
Je='Jebke:BAAANQAECgYIEgAAAA==.Jeneke:BAAANQADCgIIAgAAAA==.',
Jo='Johnwick:BAAANQADCgQIBAAAAA==.Jopha:BAACNQAFFIEQAAIXAAUKjR/ECgDTAQAXAAUKjR/ECgDTAQA1AAQKgSIAAxcACQoEJJ8ZAEYDABcACQoEJJ8ZAEYDABYAAQrpH8AlAF0AAAAA.Jophr:BAAANQAECgUIBgABNQAFFAUIEAAXAI0fAA==.Jore:BAAANQAECgIIAwAAAA==.',
Jp='Jpbruiser:BAABNQAECoEtAAIDAAkKAxnAUwBxAgADAAkKAxnAUwBxAgAAAA==.',
Ju='Jumpndeath:BAACNQAFFIEJAAIIAAQKDhrVDQBFAQAIAAQKDhrVDQBFAQA1AAQKgR4AAwgACQpLIPYPABsDAAgACQpLIPYPABsDAAcAAQoEDfiPADoAAAE1AAQKCAgGAAQAAAAA.Jumpnjudge:BAAANQAECggIBgAAAA==.Jumpnpray:BAAANQAECggIDgABNQAECggIBgAEAAAAAA==.Justgetme:BAABNQAECoEaAAMDAAgKKRuMdwAOAgADAAgKzxqMdwAOAgAFAAIKvyMlRgCtAAAAAA==.',
Ka='Kaan:BAAANQADCgEIAQAAAA==.Kaariel:BAAANQADCgYIBgAAAA==.Kabo:BAACNQAFFIEJAAIXAAQK+AuJFwAkAQAXAAQK+AuJFwAkAQA1AAQKgSQAAhcACQp3GQBPAIICABcACQp3GQBPAIICAAAA.Kadela:BAAANQADCgcIEAAAAA==.Kagger:BAAANQAFFAIIBAAAAA==.Kardoroth:BAABNQAECoEaAAIdAAkKbSQnDQA7AwAdAAkKbSQnDQA7AwAAAA==.Karîba:BAACNQAFFIEIAAQdAAQKwBcuDAAeAQAdAAMKlB4uDAAeAQAIAAMKZArKFwCyAAAHAAEK3Q9YFwBIAAA1AAQKgS8ABB0ACQo0JlsHAHkDAB0ACQp1JVsHAHkDAAcABQrhIigxAOQBAAgABArcFTB1APwAAAAA.',
Ke='Keld:BAEANQAECgYIDAAAAA==.Kellienna:BAAANQAECgQIBgABNQAECgkJJgADAIwfAA==.Kelsaz:BAACNQAFFIENAAQPAAUK5hfcEwDzAAAPAAMKWxfcEwDzAAAJAAMKew5oFADEAAAgAAEKIAcQAgBRAAA1AAQKgSIAAw8ACQrGI+0+AIkCAA8ACAquJO0+AIkCAAkABgqwFCE3AGkBAAAA.Kelshock:BAAANQAECgEIAgAAAA==.Kelsi:BAABNQAECoEkAAIMAAkKwBVcGQBNAgAMAAkKwBVcGQBNAgAAAA==.Kerrìgàn:BAACNQAFFIEJAAMZAAQKfQ6RCwApAQAZAAQKfQ6RCwApAQAYAAEKlgpVBwAwAAA1AAQKgTEAAxkACQr5IOwOABUDABkACQoQIOwOABUDABgABQrzG7oPAIgBAAAA.Kestral:BAABNQAECoEbAAIeAAkKEQ1ZGwD1AQAeAAkKEQ1ZGwD1AQAAAA==.',
Kh='Khalisi:BAAANQAECgEIAwAAAA==.',
Ki='Kitara:BAAANQADCgIIAgAAAA==.',
Ko='Koochlathom:BAAANQAECgEIAQABNQAECggIGAAGAFcdAA==.Kookiie:BAACNQAFFIEQAAIZAAUKYCDBBADrAQAZAAUKYCDBBADrAQA1AAQKgSIAAhkACQp6JeYIAF4DABkACQp6JeYIAF4DAAAA.Koom:BAAANQAECgMIBAAAAA==.Korgoroth:BAAANQABCgIIAwAAAA==.Kosian:BAAANQAECgIIAwABNQAECgkJLAACABQaAA==.Kosigan:BAAANQADCgUIBQABNQAECgkJKwACAMEgAA==.',
Kr='Krepuscular:BAABNQAECoEeAAIXAAcKMh0lXwBSAgAXAAcKMh0lXwBSAgAAAA==.Kryptiq:BAACNQAFFIENAAIhAAUK1B8QAQDNAQAhAAUK1B8QAQDNAQA1AAQKgSEAAiEACQrpJAACAI8DACEACQrpJAACAI8DAAAA.Kryptìq:BAAANQAECgUIBgABNQAFFAUIDQAhANQfAA==.',
Ku='Kurisami:BAAANQAECgUIBQAAAA==.',
La='Larielin:BAAANQADCgYIBgAAAA==.Larra:BAACNQAFFIEJAAIVAAQKKQ8dEgBGAQAVAAQKKQ8dEgBGAQA1AAQKgRwABCIACQqiEUsGABMCACIACQpcD0sGABMCABUAAwpHFDyyAMgAACMAAQr9DMNzACgAAAAA.',
Le='Leman:BAAANQAECgMIAwAAAA==.Lemondonut:BAAANQADCgUIBQAAAA==.Leomessi:BAAANQADCgQIAwABNQAECggIIAAPAIgUAA==.Levitas:BAABNQAECoEiAAIhAAgKHREvFAC2AQAhAAgKHREvFAC2AQAAAA==.Leyron:BAABNQAECoEUAAIUAAgK9xRfJAA4AgAUAAgK9xRfJAA4AgABNQAECgkJJgADAIwfAA==.',
Li='Likkhan:BAAANQAECgEIAQAAAA==.Lithel:BAAANQADCggIEwAAAA==.',
Lo='Lockdragoon:BAAANQABCgIIBAAAAA==.Logics:BAABNQAECoEoAAMjAAkKfh+YCwAXAwAjAAkKfh+YCwAXAwAVAAYKMQMiqwDaAAAAAA==.Longsham:BAAANQADCgUIBgAAAA==.Lostmyvigor:BAAANQAECgQICAAAAA==.Lostvoker:BAABNQAECoEiAAMkAAkKZxR8BwAMAgAkAAkKZxR8BwAMAgAfAAIK1AZNMQBlAAAAAA==.',
Lu='Lucarad:BAAANQAECgUIBgAAAA==.Lucivia:BAABNQAECoEcAAIKAAcK/Ro+BgArAgAKAAcK/Ro+BgArAgAAAA==.Lumafist:BAABNQAECoErAAIMAAkKNiVRAQDRAwAMAAkKNiVRAQDRAwAAAA==.Lunär:BAAANQAECgIIAgAAAA==.',
['Lè']='Lènneth:BAABNQAECoEkAAMjAAgKFg79KgCmAQAjAAgKFg79KgCmAQAVAAMKORHYwQCcAAAAAA==.',
Ma='Maddelyn:BAACNQAFFIELAAICAAYKnxO6DQDoAQACAAYKnxO6DQDoAQA1AAQKgSQAAgIACQojJbUOAJQDAAIACQojJbUOAJQDAAAA.Magicdaddy:BAAANQADCgEIAQAAAA==.Majaer:BAAANQADCgYIBgAAAA==.Mapp:BAABNQAECoEaAAMJAAgKYBWBLQC6AQAJAAcKRBGBLQC6AQAPAAYKtxWVmgCfAQAAAA==.Mashanu:BAACNQAFFIEJAAINAAQKeRavDABlAQANAAQKeRavDABlAQA1AAQKgRcAAg0ACQpYHtMgAOoCAA0ACQpYHtMgAOoCAAE1AAUUBAoJAA0AeRYA.Mashpriest:BAAANQADCgIIAgAAAA==.Mazur:BAAANQAECgcIDgAAAA==.',
Mc='Mcmonkton:BAAANQADCgIIAgAAAA==.',
Me='Meanssa:BAEBNQAECoEgAAIIAAkKLxfXKABfAgAIAAkKLxfXKABfAgAAAA==.Megamaxamx:BAAANQADCgIIAgAAAA==.Melaan:BAAANQAECggIEwAAAA==.Meldatonin:BAAANQAECgIIAgAAAA==.Metaslave:BAAANQAECgEIAQAAAA==.Mewreck:BAAANQADCgIIAgAAAA==.',
Mi='Mindleseye:BAAANQAECgYIBgAAAA==.Misosalty:BAABNQAECoEwAAQlAAgKdRmGEQA5AgAlAAgKdRmGEQA5AgAMAAUKIBAHOwADAQAOAAMKXBj/HQDaAAAAAA==.',
Mo='Mohjito:BAAANQAECgcIEwAAAA==.Monica:BAAANQAECgEIAQAAAA==.Moojinbuu:BAAANQAECgMIAwAAAA==.Mooshanu:BAAANQABCgMIBAABNQAFFAQKCQANAHkWAA==.Mootini:BAAANQAECgEIAQAAAA==.Morguth:BAACNQAFFIEIAAIPAAQKDA6QDQBEAQAPAAQKDA6QDQBEAQA1AAQKgRYAAg8ACQp3HVAzAK8CAA8ACQp3HVAzAK8CAAAA.Moripally:BAABNQAECoEaAAIDAAkKUhx+MADpAgADAAkKUhx+MADpAgABNQAFFAQICwAjAFoiAA==.Moripriest:BAACNQAFFIELAAIjAAQKWiJoBgCTAQAjAAQKWiJoBgCTAQA1AAQKgS8AAiMACQqcI20EAIQDACMACQqcI20EAIQDAAAA.Moriwarrior:BAABNQAECoEZAAIXAAcKUxsFbQArAgAXAAcKUxsFbQArAgABNQAFFAQICwAjAFoiAA==.',
Mu='Murky:BAAANQAECgUICgAAAA==.Murnemerch:BAAANQADCgYIEgAAAA==.Musclewizard:BAABNQAECoEWAAIXAAYKvxiZmgCwAQAXAAYKvxiZmgCwAQAAAA==.',
My='Myrthael:BAAANQADCgUIBQAAAA==.Mythiks:BAAANQADCgIIAgABNQAECggIFwAJAL4KAA==.',
['Mï']='Mïlo:BAAANQAECgcIEQAAAA==.',
['Mô']='Môon:BAAANQADCgcIBwAAAA==.',
Na='Nancybrew:BAABNQAECoEeAAIMAAgK/RtrGABZAgAMAAgK/RtrGABZAgAAAA==.Natalie:BAAANQADCggICAABNQAECgQIBAAEAAAAAA==.',
Ne='Nesqwik:BAAANQADCggIHAAAAA==.Nevan:BAABNQAECoEiAAIGAAgK8R4mIgDNAgAGAAgK8R4mIgDNAgAAAA==.',
Ni='Nidalee:BAAANQAECgcIDgAAAA==.Nineball:BAABNQAECoEdAAMTAAgKJRxDGwDpAQATAAYKEx1DGwDpAQAUAAUKoBeTRQBqAQAAAA==.Niyx:BAAANQAECgYIDgAAAA==.',
No='Noochallange:BAAANQAECgYIEgAAAA==.Norex:BAACNQAFFIEIAAMIAAQKhAo4FADiAAAIAAQKhAo4FADiAAAHAAIKKgMvFABrAAA1AAQKgR4ABAcACQpFF/AsAAECAAcACAqOF/AsAAECAB0ABgpBDOt2ABUBAAgAAwqJFLiKALMAAAAA.Notgood:BAAANQAECgEIAQAAAA==.',
Nu='Nuggie:BAAANQAECgUIDAAAAA==.',
Ny='Nylariaa:BAAANQADCgYIBgAAAA==.',
Ol='Oldmagic:BAAANQAECgQIEAAAAA==.Olzpot:BAAANQAECgEIAQAAAA==.',
Oo='Ooglaboogla:BAABNQAECoEfAAMNAAgKGRsaQQBGAgANAAcK+hsaQQBGAgARAAYKCRWycgCEAQAAAA==.',
Or='Orbitguy:BAAANQADCgUIBQAAAA==.Orbutt:BAAANQADCgYICgAAAA==.Orillian:BAAANQADCgYIBwAAAA==.',
Ov='Overtime:BAAANQAECgcIEQAAAA==.',
Ox='Oxyrotten:BAAANQAECgIJAgAAAA==.',
Pa='Palablort:BAABNQAECoEYAAMGAAgKVx3ILACZAgAGAAgKVx3ILACZAgADAAUKZBQB0wA7AQAAAA==.Panzeria:BAABNQAECoEcAAIjAAkK3yMyCwAdAwAjAAkK3yMyCwAdAwAAAA==.Pawsome:BAAANQAECgcIEwAAAA==.',
Pi='Pixel:BAAANQAECgMIBwAAAA==.',
Pl='Plinkie:BAAANQADCgEIAQAAAA==.',
Pm='Pmon:BAAANQADCgYIBgAAAA==.',
Pr='Prlestest:BAAANQAECgUICwABNQAECgkJMQAaAO0gAA==.Proowee:BAAANQAECggIDwAAAA==.Propayne:BAAANQAECggIBQAAAA==.',
Ps='Pseudoholy:BAAANQAECgUICQAAAA==.',
Pu='Pukebreath:BAAANQADCgEIAQAAAA==.Putridvigor:BAABNQAECoEdAAIIAAcKiyMoGgDFAgAIAAcKiyMoGgDFAgAAAA==.',
['Pä']='Pälii:BAAANQAECgUIDwAAAA==.',
Qi='Qizai:BAAANQAECgEIAQAAAA==.',
Ra='Ramaan:BAAANQAECgIIAgAAAA==.Rastaa:BAABNQAECoEXAAMJAAgKvgrDLwCnAQAJAAgKGQrDLwCnAQAPAAEKKArAPAE2AAAAAA==.Ravette:BAABNQAECoEVAAIZAAcKiR04JgBCAgAZAAcKiR04JgBCAgAAAA==.Ravissante:BAAANQAECgEIAQAAAA==.Ravyndrath:BAAANQADCgMIAwAAAA==.Rawranator:BAAANQAECgQIBgAAAA==.',
Rh='Rhonis:BAAANQADCgEIAQAAAA==.',
Ri='Ricksancheez:BAAANQAECgYICQAAAA==.',
Ro='Roidgnome:BAAANQAECgEIAwAAAA==.Ronnycoleman:BAAANQADCgIIAgAAAA==.',
Ru='Runeka:BAAANQAECgEIAQABNQAECggIGAAYAPIgAA==.',
Ry='Ryleth:BAAANQADCggIDQAAAA==.',
Sa='Safehaven:BAAANQAECgUICQAAAA==.Samwìse:BAACNQAFFIEKAAIVAAQK6w3BEgA9AQAVAAQK6w3BEgA9AQA1AAQKgToAAxUACQooH2AVABADABUACQooH2AVABADACMABgrKDcI6ACkBAAAA.Sarenrae:BAAANQAECgQIBQABNQAECggIEwAEAAAAAA==.Sarranidan:BAAANQAECgYIEwABNQAECgkJLAACABQaAA==.Sathelyn:BAAANQADCgcIBwABNQAECgkJJAAWAEYLAA==.Sato:BAAANQABCgIIAgAAAA==.',
Sc='Scatman:BAAANQADCgUIBQAAAA==.Scire:BAAANQAECgMIBAAAAA==.Scopenrage:BAAANQAECgQIBAABNQAECggIFAAdAGsfAA==.',
Se='Sedontas:BAAANQAECgQIBQAAAA==.Senggolbacok:BAAANQAECgQIBAAAAA==.Serengenuity:BAACNQAFFIEQAAMVAAUKcxi/CgC1AQAVAAUKGBi/CgC1AQAiAAIKGhURAgCmAAA1AAQKgSMABBUACQqpIgAdAOUCABUACQp8IgAdAOUCACIABgqhH4sGAAkCACMABAr0Hfc8ABoBAAAA.Serenidin:BAAANQADCgYIBgAAAA==.',
Sh='Shampane:BAAANQADCgUIBQABNQAECgkJMQAaAO0gAA==.Shark:BAAANQAECgcJEQAAAA==.Sheera:BAAANQADCgEIAQAAAA==.Shiggles:BAAANQAECggIDAABNQAFFAUIDAARAIwJAA==.Shiggyll:BAAANQAECgMIBAABNQAFFAMIBgAVAIseAA==.Shiryunuri:BAAANQADCgYIBgAAAA==.Shizzo:BAAANQADCgQIBAAAAA==.Shmoople:BAAANQADCgcIDAAAAA==.Shockin:BAABNQAECoEdAAIcAAkKDQ/NDwBSAgAcAAkKDQ/NDwBSAgAAAA==.Shootin:BAAANQAECgIJBAAAAA==.Shypoke:BAAANQABCgEIAQAAAA==.Shøstákovich:BAAANQAECgEIAQAAAA==.',
Si='Sifen:BAAANQAECggIEwABNQAFFAMIBQANAOgZAA==.Sifting:BAABNQAECoEpAAICAAgK+B4gUgDMAgACAAgK+B4gUgDMAgAAAA==.Sinsheretic:BAAANQAECgQIBAAAAA==.Sinswrath:BAACNQAFFIEQAAIDAAUKFR/bBQDSAQADAAUKFR/bBQDSAQA1AAQKgSIAAgMACQpGJdMRAHEDAAMACQpGJdMRAHEDAAAA.',
Sk='Skidxx:BAAANQADCgYIDQAAAA==.Skulker:BAAANQADCgMIBgAAAA==.Skygnome:BAACNQAFFIEFAAMeAAIKogWgEwB2AAAeAAIKogWgEwB2AAAkAAEKrwCiCwAuAAA1AAQKgSMAAh4ACQrPGQwNAMICAB4ACQrPGQwNAMICAAAA.Skyhørn:BAAANQAECgIIAgAAAA==.',
Sl='Slaye:BAAANQAECgQICAAAAA==.Slimjjim:BAAANQAECgcIDAAAAA==.',
Sm='Smiteheal:BAAANQADCgYIBgAAAA==.Smores:BAAANQADCgEIAQABNQAFFAYIEgAQAFshAA==.',
Sn='Snake:BAAANQADCgUIBQAAAA==.Sneakyteeth:BAABNQAECoEoAAITAAkKLBgYDACjAgATAAkKLBgYDACjAgAAAA==.',
So='Songi:BAABNQAECoErAAIdAAkK9CTrCwBGAwAdAAkK9CTrCwBGAwAAAA==.Soulwhisper:BAACNQAFFIEMAAIdAAUKJxd5BwCAAQAdAAUKJxd5BwCAAQA1AAQKgSQAAh0ACQruIXITAAYDAB0ACQruIXITAAYDAAAA.',
Sp='Spanda:BAABNQAECoEdAAIOAAgKqRgRDQANAgAOAAgKqRgRDQANAgAAAA==.Sparrkel:BAAANQAECgQIBQAAAA==.Splagzhul:BAAANQAECgMIAwAAAA==.Splendi:BAAANQAECgQIBAABNQAECggIHQAOAKkYAA==.Sprogg:BAAANQAECgEIAQAAAA==.Spyropaly:BAABNQAECoEmAAIGAAkKaCE/CwBgAwAGAAkKaCE/CwBgAwAAAA==.Spyroshaman:BAAANQADCgUICQABNQAECgkJJgAGAGghAA==.',
St='Stampede:BAAANQADCggIDwAAAA==.Stepzlol:BAAANQADCgYICwAAAA==.Stormsinger:BAABNQAECoEiAAMRAAgK2RbeTwD5AQARAAgK2RbeTwD5AQANAAgKxAyTZQC/AQAAAA==.',
Su='Sugarblast:BAACNQAFFIEJAAINAAUKMxetCQCiAQANAAUKMxetCQCiAQA1AAQKgS4AAg0ACQoXJHcJAJADAA0ACQoXJHcJAJADAAAA.Sukaii:BAAANQAECgYICwAAAA==.Summonuber:BAAANQAECgIIAQAAAA==.Suou:BAACNQAFFIEJAAIXAAQKNhRWEwBXAQAXAAQKNhRWEwBXAQA1AAQKgSIAAxcACQrtHhs0ANsCABcACQrtHhs0ANsCABYAAQqcILUmAFYAAAAA.',
Sv='Svekkê:BAAANQAECgcIAQAAAA==.',
Sy='Sylint:BAAANQADCgYICwAAAA==.Sylliseas:BAAANQADCgYIBgAAAA==.',
Ta='Tandaley:BAAANQADCgQIBQABNQAECggIIgARANkWAA==.Tandea:BAAANQAECgYIBgAAAA==.Tanthyr:BAAANQADCgQIBQABNQAECggIIgARANkWAA==.Targon:BAAANQADCgcIBwAAAA==.',
Te='Testme:BAAANQADCgcICAAAAA==.Textaco:BAAANQADCgEIAQAAAA==.',
Th='Thedevilssin:BAAANQAECgUIBwAAAA==.Theodas:BAAANQAECgcIDQAAAA==.Thiccgnome:BAABNQAFFIEFAAIVAAMKFg/VGQDqAAAVAAMKFg/VGQDqAAAAAA==.Thiccthighs:BAAANQAECgEIAQAAAA==.Thirdlegolas:BAAANQAECgEIAQAAAA==.Thuuros:BAABNQAECoEiAAIdAAgKJhyYMABJAgAdAAgKJhyYMABJAgAAAA==.',
Ti='Tikariia:BAAANQAECgQIBAAAAA==.Tiktok:BAAANQAECgUIBQAAAA==.Tipsygypsy:BAAANQAECggIEAAAAA==.Tirent:BAAANQAECgQICQAAAA==.',
To='Tokenbeef:BAAANQAECgYIDgAAAA==.Tokenshaman:BAABNQAECoEgAAIcAAgKsQ7LEgAYAgAcAAgKsQ7LEgAYAgAAAA==.Tokentrees:BAAANQADCgUJBQAAAA==.Touchspell:BAABNQAECoEeAAICAAkKSwnR1QC1AQACAAkKSwnR1QC1AQAAAA==.Toxicdk:BAABNQAECoEcAAQHAAkKpSAqJABCAgAHAAkKKBsqJABCAgAIAAYK4h6LPwDhAQAdAAQK6iP6UgCeAQAAAA==.Toxicshamy:BAAANQAECggICQABNQAECgkJHAAHAKUgAA==.',
Tr='Traylay:BAACNQAFFIEJAAIDAAQKRxM3DABLAQADAAQKRxM3DABLAQA1AAQKgR0AAgMACQprIWIzAN4CAAMACQprIWIzAN4CAAAA.Trixaintime:BAAANQADCgcIBwAAAA==.Trommel:BAAANQAECgEIAQAAAA==.Trydoom:BAAANQADCgYIBgAAAA==.Trèè:BAAANQADCgMIBQAAAA==.',
Tt='Ttocs:BAACNQAFFIEFAAINAAMK6BnOEQATAQANAAMK6BnOEQATAQA1AAQKgTEAAg0ACQoJJW0DAMwDAA0ACQoJJW0DAMwDAAAA.',
Tu='Tujori:BAACNQAFFIEQAAIVAAUK6gvIDgB+AQAVAAUK6gvIDgB+AQA1AAQKgSEAAhUACQoAGBc7AFkCABUACQoAGBc7AFkCAAAA.',
Tw='Twherk:BAABNQAECoEbAAIGAAgKLxHXXQDbAQAGAAgKLxHXXQDbAQABNQAFFAUIDAARAIwJAA==.Twoeye:BAAANQADCgYIBgAAAA==.',
Ug='Uglydorf:BAABNQAECoEgAAIPAAgKiBSiUgBQAgAPAAgKiBSiUgBQAgAAAA==.',
Um='Umokthra:BAAANQAECgEIAQAAAA==.',
Us='Ustoo:BAABNQAECoEXAAIaAAcK0A9ODgCaAQAaAAcK0A9ODgCaAQAAAA==.',
Va='Vae:BAAANQAECgMJAwAAAA==.Vaeros:BAAANQAECgUIEAAAAA==.Valanteil:BAAANQABCgYIBAABNQAECggIIgARANkWAA==.Varcina:BAAANQAECgcIEwABNQAFFAQICAAdAMAXAA==.Variana:BAABNQAECoEYAAMYAAgK8iDJAwD1AgAYAAgK8iDJAwD1AgAZAAIKQw/0cAB7AAAAAA==.Vaylle:BAAANQADCgQJBAAAAA==.',
Ve='Vekz:BAABNQAECoEnAAIGAAgKAB5nKACvAgAGAAgKAB5nKACvAgAAAA==.Veles:BAAANQAECgEIAQAAAA==.Velicia:BAAANQAECgMIAwAAAA==.Velytia:BAAANQAECgcIEQAAAA==.Vexøs:BAAANQADCggIDwAAAA==.',
Vi='Vitiliga:BAABNQAECoEXAAIWAAcKfwdWFAAzAQAWAAcKfwdWFAAzAQAAAA==.',
Vo='Volcanicbird:BAAANQAECgMIAwAAAA==.Vomax:BAAANQADCgEIAQAAAA==.',
Wa='Wasteofpants:BAAANQAECgUIBwAAAA==.Waterbôy:BAAANQAECgQIBgABNQAECgkJLQAGAGcZAA==.',
Wh='Whoasked:BAAANQADCgMIAwABNQAECgkJKwACAMEgAA==.Whîrly:BAAANQADCgUIBgAAAA==.',
Wo='Wolf:BAAANQAECgIIAgAAAA==.',
Wt='Wtfheal:BAAANQAECggIEwABNQAFFAUIDAARAIwJAA==.',
Wu='Wumbology:BAAANQAECgIIAgAAAA==.',
['Wà']='Wàrrior:BAAANQADCgUICQAAAA==.',
Ya='Yakimandu:BAAANQADCggICAABNQAECgkJKQAdAEYfAA==.Yamashaman:BAABNQAECoEYAAIRAAgKbx7rKgCUAgARAAgKbx7rKgCUAgABNQAECgkJKQAdAEYfAA==.Yamo:BAAANQADCggIEgAAAA==.Yardgnome:BAAANQAECggICwAAAA==.',
Yu='Yuna:BAABNQAECoEWAAIVAAYKqh/wSQAgAgAVAAYKqh/wSQAgAgAAAA==.',
Za='Zacheris:BAABNQAECoEWAAICAAgKBBwpewBwAgACAAgKBBwpewBwAgAAAA==.Zafod:BAAANQAECgIIAgAAAA==.Zalvator:BAAANQABCggIEgABNQAECgQIBAAEAAAAAA==.Zamasu:BAAANQAECgIJAwAAAA==.Zapped:BAAANQAECgEIAQAAAA==.Zaszadin:BAEBNQAECoEVAAIDAAcKsBqaeAALAgADAAcKsBqaeAALAgAAAA==.Zaszhadoom:BAEANQADCgYIBgABNQAECgcIFQADALAaAA==.',
Ze='Zekt:BAAANQADCgcICQAAAA==.Zeltron:BAAANQADCgUICgAAAA==.Zephyre:BAAANQADCgcIBwAAAA==.Zerax:BAAANQAECgYIEAAAAA==.Zerolinkin:BAAANQAECgEIAQAAAA==.',
Zi='Zillagoth:BAAANQADCggICQAAAA==.Zira:BAABNQAECoEcAAIlAAcKsAugIgBEAQAlAAcKsAugIgBEAQAAAA==.',
Zo='Zombidruid:BAAANQAECgIIAgAAAA==.Zombiebubble:BAAANQAECgEIAQAAAA==.Zoìdberg:BAABNQAECoEaAAIRAAkKJh1+HQDZAgARAAkKJh1+HQDZAgAAAA==.',
Zs='Zselk:BAAANQADCgUIBQAAAA==.Zshot:BAAANQAECgQICgAAAA==.',
Zu='Zubzer:BAAANQADCgYIBgAAAA==.',
Zz='Zzor:BAACNQAFFIEIAAICAAQKNhprHQBcAQACAAQKNhprHQBcAQA1AAQKgTEAAgIACQpdI64aAGMDAAIACQpdI64aAGMDAAAA.',
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
