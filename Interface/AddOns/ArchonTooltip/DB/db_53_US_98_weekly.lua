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

local lookup = {'Paladin-Retribution','Paladin-Protection','Unknown-Unknown','Paladin-Holy','DeathKnight-Blood','DeathKnight-Frost','Hunter-Marksmanship','Warlock-Affliction','Warlock-Demonology','Monk-Windwalker','Shaman-Elemental','Monk-Brewmaster','Druid-Restoration','Shaman-Restoration','Warlock-Destruction','Mage-Arcane','Rogue-Subtlety','Rogue-Assassination','Priest-Holy','Warrior-Fury','Warrior-Arms','DemonHunter-Vengeance','DemonHunter-Havoc','Mage-Frost','Druid-Feral','Druid-Balance','Shaman-Enhancement','DeathKnight-Unholy','Evoker-Preservation','Evoker-Devastation','Hunter-BeastMastery','Warrior-Protection','Priest-Discipline','Priest-Shadow','Evoker-Augmentation','Monk-Mistweaver',}
local provider = {region='US',realm='Frostmane',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abaz:BAAANQADCgYICQAAAA==.Aberdus:BAAANQAECgYIDwAAAA==.',
Ac='Accalon:BAAANQAECgUICgAAAA==.',
Ad='Advacus:BAAANQAFFAIIAwAAAA==.',
Ag='Agamar:BAAANQAECgEIAQAAAA==.Ageina:BAAANQADCggICAABNQAFFAQIBwABAC4gAA==.Agnostec:BAAANQADCgIIAwAAAA==.',
Ak='Akrama:BAAANQAECgUICgAAAA==.',
Al='Alatáriel:BAAANQAECgEJAQAAAA==.Alectrona:BAAANQADCgYICAAAAA==.Althenot:BAAANQADCgcIDwAAAA==.',
Am='Amari:BAAANQADCgEIAQAAAA==.Amegoracy:BAAANQAECgUIDQAAAA==.',
An='Andalorian:BAAANQAECgMJAwAAAA==.Anderthel:BAAANQADCgIIAgAAAA==.Anruu:BAAANQAECgYIDQAAAA==.',
Ar='Araleth:BAAANQADCgcIBwAAAA==.Archolaoch:BAABNQAECoEYAAICAAcKDBWMHQCjAQACAAcKDBWMHQCjAQAAAA==.Arconite:BAAANQADCgQIBQABNQAECgcIDAADAAAAAA==.Arizonatea:BAAANQAECgEIAQAAAA==.Arkthurus:BAAANQAECgIJAgAAAA==.',
As='Ashenknight:BAAANQADCgEJAQAAAA==.Ashijin:BAABNQAECoEbAAMBAAkK6xefTwBWAgABAAkK6xefTwBWAgAEAAEKAgGiBQETAAAAAA==.Astei:BAAANQADCgUIBQAAAA==.',
At='Athelos:BAAANQADCgUICQAAAA==.Atroce:BAABNQAECoEdAAMFAAkKGSBfIgBtAgAFAAgK2xtfIgBtAgAGAAYKdiL5IQArAgAAAA==.',
Au='Aura:BAAANQAECgYIDwAAAA==.Auxilium:BAAANQADCggIDgAAAA==.',
Aw='Awnen:BAAANQAECgEIAQAAAA==.',
Ax='Axes:BAAANQAECgIIAgAAAA==.Axkicker:BAABNQAECoE1AAIHAAgKWhhyGwBBAgAHAAgKWhhyGwBBAgAAAA==.',
Ba='Balethar:BAAANQAECgUICgABNQAFFAEIAQADAAAAAA==.Ballador:BAAANQAECgYIBwAAAA==.Balluh:BAAANQAECgYIEAAAAA==.Balzluzzak:BAABNQAECoEYAAMIAAcKqAuaCQCUAQAIAAcKqAuaCQCUAQAJAAUKwAQO1QC5AAAAAA==.Baughter:BAAANQABCgcICwAAAA==.',
Be='Beetledeww:BAAANQADCgQIBAAAAA==.Beetledont:BAAANQADCgYIBgAAAA==.Beezbonk:BAAANQAECggICAAAAA==.Bellemorte:BAAANQABCgQIBAAAAA==.Bellmage:BAAANQAECgcIEQAAAA==.Belttoash:BAAANQADCggIEwAAAA==.Beneficiary:BAAANQADCgYIBgAAAA==.Bestricer:BAACNQAFFIElAAIKAAgKniA5AAAhAwAKAAgKniA5AAAhAwA1AAQKgSwAAgoACQoVJpQBAMEDAAoACQoVJpQBAMEDAAAA.Bevis:BAAANQAECgcIEQABNQAECgkJKwALAN8kAA==.',
Bi='Bigmayex:BAABNQAECoEcAAIMAAgKIyWHAgBdAwAMAAgKIyWHAgBdAwAAAA==.Bilmuri:BAAANQAECggIEAAAAA==.Bippot:BAABNQAECoErAAIBAAkKbCCjGgAwAwABAAkKbCCjGgAwAwAAAA==.',
Bl='Blackbride:BAAANQADCggICgAAAA==.Bloodybill:BAAANQADCgUJBQAAAA==.Blort:BAAANQADCggICAAAAA==.',
Bo='Bombadormu:BAAANQADCgcIBwAAAA==.Bonezs:BAABNQAECoEbAAINAAcKxyPrCwDXAgANAAcKxyPrCwDXAgAAAA==.Boredfordays:BAAANQAECgEIAQAAAA==.Bossvega:BAAANQADCggIJAAAAA==.',
Br='Bruhkakke:BAAANQAECggIBAABNQAFFAQIBwAOAEUJAA==.',
Bu='Bugbear:BAAANQADCggIHQAAAA==.Bumbly:BAAANQAECgUIDAAAAA==.Bushybrowsy:BAABNQAECoElAAMIAAgKFxHkBQAXAgAIAAgKFxHkBQAXAgAPAAEK2gOSbAA3AAAAAA==.Buttermeupz:BAABNQAECoEYAAIEAAcKyhGSXQCzAQAEAAcKyhGSXQCzAQAAAA==.Buttsnorkle:BAAANQAECgIIAgAAAA==.',
['Bá']='Bámboo:BAAANQAECgQIBAAAAA==.',
Ca='Cacho:BAAANQAECgcIEQAAAA==.Cactuss:BAAANQAECgQIBAABNQAECggIGQAQAOEIAA==.Caothand:BAAANQADCggIEQAAAA==.',
Cc='Ccyll:BAAANQADCgcIEAAAAA==.',
Ce='Cerridwen:BAAANQABCgIJAgAAAA==.',
Ch='Chazandi:BAAANQADCgQIBAABNQAECgkJJgAQAOUTAA==.Chazzbadgurl:BAAANQAECgcICwABNQAECgkJJgAQAOUTAA==.Chexmix:BAABNQAECoEZAAMRAAYKFQwaJgBoAQARAAYKdQsaJgBoAQASAAQKzgiSVADQAAAAAA==.Chicho:BAAANQAECgIIAgABNQAECgkJJAANAKAYAA==.Chomboslice:BAAANQAECgcIEAAAAA==.',
Ci='Cinnamon:BAABNQAECoEcAAITAAgKjRlTLgBvAgATAAgKjRlTLgBvAgAAAA==.',
Cm='Cmil:BAACNQAFFIEGAAMEAAQK9xkrDgD9AAAEAAMKDhYrDgD9AAABAAEKwgF9IgBGAAA1AAQKgScABAQACQqaHOMVAP4CAAQACQqaHOMVAP4CAAEABwrFDU2RAJcBAAIAAgrBFKpHAG8AAAAA.',
Co='Coffeegin:BAAANQADCgMIAwAAAA==.',
Cr='Crittingbull:BAAANQAECgQIBQAAAA==.Cruiddeath:BAAANQAECgMIBgABNQAECggIIQAUAB4MAA==.',
Cu='Curserodlock:BAABNQAECoEhAAMUAAgKHgxuDACjAQAUAAgKtwtuDACjAQAVAAUK/AUU0QDeAAAAAA==.',
Cy='Cyanide:BAAANQAECgYICwAAAA==.',
Da='Dabbinshamin:BAAANQADCggIDwAAAA==.Dads:BAACNQAFFIEQAAILAAYKSRVvAwAOAgALAAYKSRVvAwAOAgA1AAQKgR8AAwsACQr5Im0LAHUDAAsACQr5Im0LAHUDAA4AAwpKAdnOAHMAAAAA.Daedra:BAAANQAECgYICgABNQAECgYIDgADAAAAAA==.Daillin:BAAANQADCgEIAQAAAA==.Dakadakadaka:BAAANQAECgYIEQAAAA==.Darcdk:BAAANQAECgUICwABNQAFFAUIDAAEAPsOAA==.Darcevoker:BAAANQADCgcIBwABNQAFFAUIDAAEAPsOAA==.Darcpaladin:BAACNQAFFIEMAAIEAAUK+w5UCACLAQAEAAUK+w5UCACLAQA1AAQKgR8AAgQACQp7GfgdAMsCAAQACQp7GfgdAMsCAAAA.Darcpriest:BAAANQAECgQIBQABNQAFFAUIDAAEAPsOAA==.Darkrune:BAAANQAECgIIAwAAAA==.Darkschneide:BAAANQAECgYIEAAAAA==.Darthboo:BAAANQAECgQIBAAAAA==.Darthtemplar:BAABNQAECoEdAAMBAAkKQx5QJQD7AgABAAkKQx5QJQD7AgACAAEKBA+yXAAoAAAAAA==.',
De='Deathbug:BAAANQADCgEIAQAAAA==.Deckaye:BAAANQAECgMIAQABNQAECgQIBgADAAAAAA==.Deimoes:BAAANQADCgYIDQAAAA==.Demodorn:BAACNQAFFIEHAAIWAAQKcwGpAgCZAAAWAAQKcwGpAgCZAAA1AAQKgSwAAhYACQqIC+gLAK0BABYACQqIC+gLAK0BAAAA.Demyst:BAABNQAECoEdAAMOAAkKFRtuJQCVAgAOAAkKFRtuJQCVAgALAAIKlA3E3QBlAAAAAA==.Demön:BAAANQAECgMIAwAAAA==.Dewwarrior:BAAANQAECgQICQAAAA==.Dezeraz:BAEANQAECgYIBgABNQAFFAUIDAATABoaAA==.',
Dh='Dhecaye:BAAANQAECgQIBgAAAA==.',
Di='Disengage:BAAANQAECgUIBwABNQAECgkJHgAQAF8kAA==.',
Do='Dohdan:BAAANQADCgYICAAAAA==.Donkey:BAABNQAECoEYAAIEAAgKoRf6MgBdAgAEAAgKoRf6MgBdAgAAAA==.Donmega:BAAANQADCggIIQAAAA==.Dougalleone:BAABNQAECoEbAAMSAAkKLiFACAAkAwASAAkKLiFACAAkAwARAAYKIBgSIgCTAQAAAA==.Dougallmaki:BAAANQAECgIIAgAAAA==.',
Dr='Drekkwarr:BAAANQAECgEIAQABNQAECggIGwALAKYdAA==.Drentalth:BAAANQADCgEIAQAAAA==.Drezzakzdh:BAAANQAECgYIDAABNQAECgYIDgADAAAAAA==.Drezzakzz:BAAANQAECgYIDgAAAA==.',
Du='Dugren:BAAANQAECgIIAQAAAA==.Duracreate:BAAANQAECgEIAQAAAA==.',
Ea='Eamil:BAAANQADCgcJBwAAAA==.',
Ek='Ekaterin:BAABNQAECoEoAAIQAAkKbiAvIwA7AwAQAAkKbiAvIwA7AwAAAA==.Ekewa:BAAANQADCgcJBwAAAA==.',
El='Elaidine:BAABNQAECoEYAAMWAAcKJB3ZBgBNAgAWAAcKJB3ZBgBNAgAXAAEKRgHgfwAOAAAAAA==.Electraknub:BAAANQADCgYJBwAAAA==.Electroh:BAAANQAECgYIDgAAAA==.Eliseda:BAAANQAECgQIBAABNQAECggIIAAOANkWAA==.',
Em='Emerald:BAAANQABCgIIBAAAAA==.',
Ev='Evilnapkin:BAAANQAECgQIBAAAAA==.Evion:BAAANQAECgYIDgAAAA==.Evoke:BAAANQAECgUIBQAAAA==.',
Fa='Falconsha:BAAANQADCggIIgAAAA==.Fattynattyy:BAAANQADCgYIBgAAAA==.',
Fe='Fendis:BAAANQADCggICAABNQAECgkJKQAQAPkZAA==.',
Fi='Fiercia:BAAANQAECgUICgABNQAECgkJIwAGAFsiAA==.Firefrost:BAABNQAECoEqAAMYAAkKaSBYAQBdAwAYAAkKaSBYAQBdAwAQAAEKgQZ+hgE5AAAAAA==.Firescrotum:BAABNQAECoEeAAILAAgKBg1ZVgDQAQALAAgKBg1ZVgDQAQAAAA==.',
Fl='Flashquinaz:BAAANQADCgYIBgAAAA==.',
Fo='Fourimborniy:BAAANQAECggIEgAAAA==.',
Fr='Frenzi:BAAANQADCgYICQAAAA==.',
Fu='Fundipme:BAAANQADCgcIDAAAAA==.',
['Fá']='Fáelen:BAABNQAECoEZAAIZAAkKgR6LAwAoAwAZAAkKgR6LAwAoAwAAAA==.',
Ga='Galasmina:BAAANQAECgUICQAAAA==.Galaxius:BAAANQADCgEIAQABNQAECgcIDAADAAAAAA==.Ganda:BAAANQADCgEJAQAAAA==.Gangactivity:BAAANQADCgUIBQABNQAECgkJIgAKAEcjAA==.Garm:BAAANQAECgYIEgAAAA==.Gavinrad:BAAANQAECgYICAAAAA==.',
Ge='Generaname:BAAANQADCgcJDQAAAA==.Generanancy:BAAANQADCgIJAgAAAA==.',
Gh='Ghostshadow:BAAANQAECgIIBAAAAA==.',
Gi='Gilene:BAAANQADCgQIBAAAAA==.Girthfury:BAABNQAFFIEHAAIOAAQKRQl8DAAcAQAOAAQKRQl8DAAcAQAAAA==.',
Gl='Glaalinix:BAAANQADCgIIAgAAAA==.',
Gn='Gnew:BAAANQADCgUICgAAAA==.Gnumchuck:BAAANQAECgYIEAAAAA==.',
Go='Goat:BAAANQAECgMIAwAAAA==.Goku:BAABNQAECoEaAAMOAAkKrB/pEAAVAwAOAAkKrB/pEAAVAwALAAEKeAg2CQEsAAAAAA==.Goodman:BAAANQAECgUICgAAAA==.Goom:BAAANQAECgYIBgABNQAFFAUIDQAKAJATAA==.Goomei:BAACNQAFFIENAAIKAAUKkBM/BACcAQAKAAUKkBM/BACcAQA1AAQKgR0AAgoACQoZILoRAI8CAAoACQoZILoRAI8CAAAA.Goomkin:BAABNQAECoEdAAIaAAkKnRimIwB5AgAaAAkKnRimIwB5AgABNQAFFAUIDQAKAJATAA==.Gordanramsey:BAAANQADCgUIBQAAAA==.Gorok:BAAANQAECgIIAgAAAA==.',
Gr='Gravymonk:BAAANQAECgYJDgAAAA==.Greatbooty:BAAANQAECgIIBAAAAA==.Gremmi:BAAANQADCgYIBgAAAA==.Grishy:BAAANQAECggICAABNQAECgkJHgAQAF8kAA==.Grombeefdal:BAAANQADCgYICwAAAA==.Grosgland:BAAANQAECgEIAQAAAA==.Groundbeéf:BAACNQAFFIEMAAIbAAUKHB32AADeAQAbAAUKHB32AADeAQA1AAQKgSAAAhsACQryJBMCAIEDABsACQryJBMCAIEDAAAA.Grovoath:BAAANQADCgYICwAAAA==.Grumpypally:BAAANQAECgQIBwAAAA==.',
Gu='Gurthon:BAAANQADCggIDwAAAA==.',
Ha='Halligan:BAAANQAECgQICAAAAA==.Hallowfear:BAAANQAECgUJDgAAAA==.Handadinite:BAAANQADCgUICAAAAA==.Handysummons:BAAANQAECgcIEgAAAA==.Harie:BAAANQAECgUICQAAAA==.Hawtsoss:BAAANQABCgQIBwAAAA==.',
He='Hein:BAAANQAECgQIBwAAAA==.Heiny:BAABNQAECoEoAAQFAAkKziXQAgC3AwAFAAkKtCTQAgC3AwAGAAcK9SL5EwCqAgAcAAYKaiSjIgBuAgAAAA==.Heinyheinyho:BAAANQADCgMIBAABNQAECgkJKAAFAM4lAA==.',
Ho='Holeybeef:BAAANQAECgQIBQAAAA==.Holymoly:BAAANQADCgMIAQABNQAECgkJKgAYAGkgAA==.Holynoodles:BAAANQAECgYIEQAAAA==.Holytest:BAABNQAECoErAAITAAkKkB9pDwAiAwATAAkKkB9pDwAiAwAAAA==.Hoofmetoo:BAAANQAECgQICgAAAA==.Howboudah:BAAANQADCgcIBwAAAA==.',
Hu='Hulzar:BAAANQAECgYIEAAAAA==.',
Hy='Hypernova:BAAANQADCgYIBgAAAA==.Hypocrisy:BAAANQAECggICAAAAA==.',
['Hô']='Hôlyblight:BAABNQAECoEqAAMEAAkKsBW1KgCFAgAEAAkKsBW1KgCFAgABAAgKkxG3cgDqAQAAAA==.',
Id='Idotyouto:BAAANQADCgcIBwAAAA==.',
Il='Ilbryen:BAAANQAECgQIBQABNQAECgkJIAAVABMeAA==.Illaam:BAAANQADCggIDAAAAA==.Illidrag:BAAANQAECggJCgAAAA==.Ilovejacky:BAAANQADCgEIAQABNQADCgYICQADAAAAAA==.',
Im='Immørtlzed:BAACNQAFFIEUAAIOAAcKiyNjAADXAgAOAAcKiyNjAADXAgA1AAQKgSEAAg4ACQq6JSgCALMDAA4ACQq6JSgCALMDAAAA.',
In='Inara:BAAANQADCgEIAQABNQAECggIHgAKAKoTAA==.Insurion:BAAANQAECgQIBgAAAA==.Invective:BAAANQAECgMIAwAAAA==.',
Ir='Ironstorm:BAAANQADCgQIBAAAAA==.',
Iz='Izzyumi:BAAANQADCgYIBgAAAA==.',
Ja='Jarizard:BAACNQAFFIEJAAIdAAQKfAvVCQA3AQAdAAQKfAvVCQA3AQA1AAQKgSMAAx0ACQojFLkTAEQCAB0ACQojFLkTAEQCAB4AAQrzByc1ADAAAAAA.Jarrie:BAAANQADCggJDgAAAA==.Jassar:BAAANQAECgEJAgAAAA==.Jaxek:BAABNQAECoEjAAIZAAkKeiGKAgBdAwAZAAkKeiGKAgBdAwAAAA==.Jaxs:BAACNQAFFIEIAAIOAAUKkxCfBwCPAQAOAAUKkxCfBwCPAQA1AAQKgSEAAg4ACQoIGuIoAIMCAA4ACQoIGuIoAIMCAAAA.Jaylen:BAAANQAECgQICQAAAA==.Jaymo:BAAANQAECgYICgAAAA==.',
Je='Jebke:BAAANQAECgUIDAAAAA==.Jeneke:BAAANQADCgIIAgAAAA==.',
Jo='Johnwick:BAAANQADCgQIBAAAAA==.Jopha:BAACNQAFFIEMAAIVAAUK/BvuCAC/AQAVAAUK/BvuCAC/AQA1AAQKgR8AAxUACQoEJAMUAFIDABUACQoEJAMUAFIDABQAAQrpH/UgAF0AAAAA.Jophr:BAAANQADCgYJDQABNQAFFAUIDAAVAPwbAA==.Jore:BAAANQAECgIIAwAAAA==.',
Jp='Jpbruiser:BAABNQAECoEmAAIBAAkK0RcSTQBeAgABAAkK0RcSTQBeAgAAAA==.',
Ju='Jumpndeath:BAABNQAECoEcAAMFAAkKHiAZDQAmAwAFAAkKHiAZDQAmAwAGAAEKBA1SfwA8AAAAAA==.Jumpnpray:BAAANQAECggIDAABNQAECgkJHAAFAB4gAA==.Justgetme:BAAANQAFFAEIAQAAAA==.',
Ka='Kaan:BAAANQADCgEIAQAAAA==.Kaariel:BAAANQADCgYIBgAAAA==.Kabo:BAABNQAECoEhAAIVAAkKdxkBQQCOAgAVAAkKdxkBQQCOAgAAAA==.Kadela:BAAANQADCgcIDAAAAA==.Kagger:BAAANQAFFAEIAgAAAA==.Kardoroth:BAABNQAECoEXAAIcAAkKbyPwCgA+AwAcAAkKbyPwCgA+AwAAAA==.Karîba:BAACNQAFFIEFAAQFAAMKZAoQEwC3AAAFAAMKZAoQEwC3AAAGAAEK3Q8QFABIAAAcAAEK0AHPGQAyAAA1AAQKgSsABBwACQohJgkGAH0DABwACQpxJQkGAH0DAAYABApHIvU3AIYBAAUABArcFbZpAAEBAAAA.',
Ke='Keld:BAEANQAECgYIDAAAAA==.Kellienna:BAAANQAECgQIBgABNQAECgkJHQABAEMeAA==.Kelsaz:BAACNQAFFIEIAAMfAAQKghoHDwDtAAAfAAMKehYHDwDtAAAHAAMKQA08EQDFAAA1AAQKgSAAAx8ACQqGI7YwAJkCAB8ACAquJLYwAJkCAAcABgpQFMgwAGsBAAAA.Kelshock:BAAANQAECgEIAgAAAA==.Kelsi:BAABNQAECoEeAAIKAAgKqhP4HQDrAQAKAAgKqhP4HQDrAQAAAA==.Kerrìgàn:BAACNQAFFIEHAAMXAAQKDAsfCQApAQAXAAQKDAsfCQApAQAWAAEKlgreBQAwAAA1AAQKgSQAAxcACQrHIK8MABcDABcACQreH68MABcDABYABQrzG7oMAJYBAAAA.Kestral:BAABNQAECoEZAAIdAAkK/ws0GQDxAQAdAAkK/ws0GQDxAQAAAA==.',
Kh='Khalisi:BAAANQAECgEIAwAAAA==.',
Ki='Kitara:BAAANQADCgIIAgAAAA==.',
Ko='Koochlathom:BAAANQAECgEIAQABNQAECggIGAAEAFcdAA==.Kookiie:BAACNQAFFIEMAAIXAAUKVB/qAwDcAQAXAAUKVB/qAwDcAQA1AAQKgR8AAhcACQpRJdcGAGkDABcACQpRJdcGAGkDAAAA.Koom:BAAANQAECgMIBAAAAA==.Korgoroth:BAAANQABCgIIAwAAAA==.Kosian:BAAANQAECgIIAwABNQAECgkJKQAQAPkZAA==.Kosigan:BAAANQADCgUIBQABNQAECgkJKAAQAG4gAA==.',
Kr='Krepuscular:BAABNQAECoEXAAIVAAcKVhyEVwBBAgAVAAcKVhyEVwBBAgAAAA==.Kryptiq:BAACNQAFFIEIAAIgAAQKBB2vAQBJAQAgAAQKBB2vAQBJAQA1AAQKgSAAAiAACQrpJF4BAKEDACAACQrpJF4BAKEDAAAA.Kryptìq:BAAANQAECgUIBgABNQAFFAQICAAgAAQdAA==.',
La='Larielin:BAAANQADCgYIBgAAAA==.Larra:BAABNQAECoEaAAQhAAkKKhFpBQAYAgAhAAkKXA9pBQAYAgATAAMK3hLInQDHAAAiAAEK/QzUZgAoAAAAAA==.',
Le='Leman:BAAANQAECgMIAwAAAA==.Lemondonut:BAAANQADCgUIBQAAAA==.Leomessi:BAAANQADCgQIAwABNQAECgcIGgAfAEESAA==.Levitas:BAABNQAECoEcAAIgAAcKlQ9eFgBkAQAgAAcKlQ9eFgBkAQAAAA==.Leyron:BAAANQAECgcIDAABNQAECgkJHQABAEMeAA==.',
Li='Likkhan:BAAANQAECgEIAQAAAA==.Lithel:BAAANQADCgUIBQAAAA==.',
Lo='Lockdragoon:BAAANQABCgIIBAAAAA==.Logics:BAABNQAECoElAAMiAAkKJR7CCwABAwAiAAkKJR7CCwABAwATAAYKMQP9lADgAAAAAA==.Longsham:BAAANQADCgUIBgAAAA==.Lostmyvigor:BAAANQAECgQICAAAAA==.Lostvoker:BAABNQAECoEhAAMjAAkKZxQjBgAdAgAjAAkKZxQjBgAdAgAeAAIK1AYYLQBnAAAAAA==.',
Lu='Lucarad:BAAANQAECgUIBgAAAA==.Lucivia:BAAANQAECgYIEwAAAA==.Lumafist:BAABNQAECoEiAAIKAAkKRyNbBAB1AwAKAAkKRyNbBAB1AwAAAA==.Lunär:BAAANQADCgYIBgAAAA==.',
['Lè']='Lènneth:BAABNQAECoEeAAMiAAgK0Q2cJQCxAQAiAAgK0Q2cJQCxAQATAAMKORHVqQCgAAAAAA==.',
Ma='Maddelyn:BAACNQAFFIEIAAIQAAUKVRfZDQC8AQAQAAUKVRfZDQC8AQA1AAQKgSEAAhAACQrfJLwMAJcDABAACQrfJLwMAJcDAAAA.Magicdaddy:BAAANQADCgEIAQAAAA==.Majaer:BAAANQADCgYIBgAAAA==.Mapp:BAAANQAECgcIEgAAAA==.Mashanu:BAAANQAFFAIIBAAAAA==.Mashpriest:BAAANQADCgIIAgAAAA==.Mazur:BAAANQAECgcIDgAAAA==.',
Mc='Mcmonkton:BAAANQADCgIIAgAAAA==.',
Me='Meanssa:BAEBNQAECoEcAAIFAAkKqhRWKgA2AgAFAAkKqhRWKgA2AgAAAA==.Megamaxamx:BAAANQADCgIIAgAAAA==.Melaan:BAAANQAECgcIDAAAAA==.Meldatonin:BAAANQAECgIIAgAAAA==.Metaslave:BAAANQAECgEIAQAAAA==.Mewreck:BAAANQADCgIIAgAAAA==.',
Mi='Mindleseye:BAAANQADCgQIBwAAAA==.Misosalty:BAABNQAECoEqAAQkAAgKZRkoDwBEAgAkAAgKZRkoDwBEAgAKAAUK8A8fMwANAQAMAAEKPRXtJgA9AAAAAA==.',
Mo='Mohjito:BAAANQAECgcIEgAAAA==.Monica:BAAANQAECgEIAQAAAA==.Mooshanu:BAAANQABCgMIBAABNQAFFAIIBAADAAAAAA==.Mootini:BAAANQAECgEIAQAAAA==.Morguth:BAAANQAFFAIIAwAAAA==.Moripally:BAAANQAECggIEAABNQAFFAQIBwAiAO0hAA==.Moripriest:BAACNQAFFIEHAAIiAAQK7SH+BACbAQAiAAQK7SH+BACbAQA1AAQKgSgAAiIACQo0I0oFAGwDACIACQo0I0oFAGwDAAAA.Moriwarrior:BAABNQAECoEXAAIVAAcKJxtoXgArAgAVAAcKJxtoXgArAgABNQAFFAQIBwAiAO0hAA==.',
Mu='Murky:BAAANQAECgUIBgAAAA==.Murnemerch:BAAANQADCgYIBwAAAA==.Musclewizard:BAAANQAECgYIEAAAAA==.',
My='Myrthael:BAAANQADCgUIBQAAAA==.Mythiks:BAAANQADCgIIAgABNQAECgYIDgADAAAAAA==.',
['Mï']='Mïlo:BAAANQAECgYIEAAAAA==.',
['Mô']='Môon:BAAANQADCgcIBwAAAA==.',
Na='Nancybrew:BAABNQAECoEcAAIKAAgKkhvLFQBUAgAKAAgKkhvLFQBUAgAAAA==.',
Ne='Nesqwik:BAAANQADCggIHAAAAA==.Nevan:BAABNQAECoEbAAIEAAgKhhzPIQC2AgAEAAgKhhzPIQC2AgAAAA==.',
Ni='Nidalee:BAAANQAECgYICAAAAA==.Nineball:BAAANQAECgYIEwAAAA==.Niyx:BAAANQAECgYIDgAAAA==.',
No='Noochallange:BAAANQAECgUIDAAAAA==.Norex:BAABNQAECoEcAAQGAAkKRRcGJAAYAgAGAAgKjhcGJAAYAgAcAAYKQQwSYwAbAQAFAAEKABW8qAA5AAAAAA==.Notgood:BAAANQAECgEIAQAAAA==.',
Nu='Nuggie:BAAANQAECgUIBwAAAA==.',
Ny='Nylariaa:BAAANQADCgYIBgAAAA==.',
Ol='Oldmagic:BAAANQAECgQIDQAAAA==.Olzpot:BAAANQAECgEIAQAAAA==.',
Oo='Ooglaboogla:BAABNQAECoEYAAMLAAcK2xprPAA7AgALAAcK2xprPAA7AgAOAAUKuxQ2egBFAQAAAA==.',
Or='Orbitguy:BAAANQADCgUIBQAAAA==.Orbutt:BAAANQADCgYICgAAAA==.Orillian:BAAANQADCgYIBwAAAA==.',
Ov='Overtime:BAAANQAECgcIEQAAAA==.',
Ox='Oxyrotten:BAAANQAECgIJAgAAAA==.',
Pa='Palablort:BAABNQAECoEYAAMEAAgKVx1iJQChAgAEAAgKVx1iJQChAgABAAUKZBT8sgBFAQAAAA==.Panzeria:BAABNQAECoEcAAIiAAkK3yMhCAA6AwAiAAkK3yMhCAA6AwAAAA==.Pawsome:BAAANQAECgcIEwAAAA==.',
Pi='Pixel:BAAANQAECgMIBQAAAA==.',
Pl='Plinkie:BAAANQADCgEIAQAAAA==.',
Pm='Pmon:BAAANQADCgYIBgAAAA==.',
Pr='Prlestest:BAAANQAECgUJBwAAAA==.Proowee:BAAANQAECggIDwAAAA==.Propayne:BAAANQAECggIBAAAAA==.',
Ps='Pseudoholy:BAAANQAECgQIBAAAAA==.',
Pu='Pukebreath:BAAANQADCgEIAQAAAA==.Putridvigor:BAABNQAECoEZAAIFAAcKiyPOFQDQAgAFAAcKiyPOFQDQAgAAAA==.',
['Pä']='Pälii:BAAANQAECgUICgAAAA==.',
Qi='Qizai:BAAANQAECgEIAQAAAA==.',
Ra='Ramaan:BAAANQAECgIIAgAAAA==.Rastaa:BAAANQAECgYIDgAAAA==.Ravette:BAAANQAECgYIDwAAAA==.Ravissante:BAAANQAECgEIAQAAAA==.Rawranator:BAAANQAECgQIBgAAAA==.',
Rh='Rhonis:BAAANQADCgEIAQAAAA==.',
Ri='Ricksancheez:BAAANQAECgEIAwAAAA==.',
Ro='Roidgnome:BAAANQAECgEIAgAAAA==.Ronnycoleman:BAAANQADCgIIAgAAAA==.',
Ru='Runeka:BAAANQAECgEIAQABNQAECgcIDgADAAAAAA==.',
Sa='Safehaven:BAAANQAECgIIBAAAAA==.Samwìse:BAACNQAFFIEHAAITAAQK6w0SDgBNAQATAAQK6w0SDgBNAQA1AAQKgTQAAxMACQrpHiEQAB0DABMACQrpHiEQAB0DACIABgqBDbwzADEBAAAA.Sarenrae:BAAANQAECgQIBQABNQAECgcIDAADAAAAAA==.Sarranidan:BAAANQAECgYIEwABNQAECgkJKQAQAPkZAA==.Sathelyn:BAAANQADCgcIBwABNQAECggIIQAUAB4MAA==.Sato:BAAANQABCgIIAgAAAA==.',
Sc='Scatman:BAAANQADCgUIBQAAAA==.Scire:BAAANQAECgMIBAAAAA==.Scopenrage:BAAANQAECgQIBAABNQAECggIEwAcAI4eAA==.',
Se='Sedontas:BAAANQAECgQIBQAAAA==.Senggolbacok:BAAANQAECgQIBAAAAA==.Serengenuity:BAACNQAFFIEMAAMTAAUK5Bf3BwDCAQATAAUKihf3BwDCAQAhAAIKGhW+AQCwAAA1AAQKgSAABCEACQqWIqIFABACABMACQoYIpAdAMYCACEABgqhH6IFABACACIABAr0HSw1ACYBAAAA.',
Sh='Shampane:BAAANQADCgUIBQABNQAECgkJKgAYAGkgAA==.Shark:BAAANQAECgcJEQAAAA==.Sheera:BAAANQADCgEIAQAAAA==.Shiggles:BAAANQAECggICAABNQAFFAQIBwAOAEUJAA==.Shiggyll:BAAANQAECgMIBAABNQAECgkJKwATAJAfAA==.Shiryunuri:BAAANQADCgYIBgAAAA==.Shizzo:BAAANQADCgQIBAAAAA==.Shmoople:BAAANQADCgcIDAAAAA==.Shockandorc:BAAANQAECgMIAwAAAA==.Shockin:BAABNQAECoEdAAIbAAkKDQ8KDQBhAgAbAAkKDQ8KDQBhAgAAAA==.Shootin:BAAANQAECgIJBAAAAA==.Shypoke:BAAANQABCgEIAQAAAA==.Shøstákovich:BAAANQAECgEIAQAAAA==.',
Si='Sifen:BAAANQAECggIDAABNQAECgkJKwALAN8kAA==.Sifting:BAABNQAECoEiAAIQAAgKvhzGWQChAgAQAAgKvhzGWQChAgAAAA==.Sinsheretic:BAAANQAECgQIBAAAAA==.Sinswrath:BAACNQAFFIEMAAIBAAUKnh49BADUAQABAAUKnh49BADUAQA1AAQKgR8AAgEACQo2JTAQAGsDAAEACQo2JTAQAGsDAAAA.',
Sk='Skidxx:BAAANQADCgYIDQAAAA==.Skulker:BAAANQADCgMIAwAAAA==.Skygnome:BAABNQAECoEgAAIdAAkKRxn7CwDAAgAdAAkKRxn7CwDAAgAAAA==.',
Sl='Slaye:BAAANQAECgQICAAAAA==.Slimjjim:BAAANQAECgcIDAAAAA==.',
Sm='Smiteheal:BAAANQADCgYIBgAAAA==.Smores:BAAANQADCgEIAQABNQAFFAUIDAANADQjAA==.',
Sn='Snake:BAAANQADCgUIBQAAAA==.Sneakyteeth:BAABNQAECoEhAAIRAAgKAhYnEQBLAgARAAgKAhYnEQBLAgAAAA==.',
So='Songi:BAABNQAECoEoAAIcAAkK9CQdBgB8AwAcAAkK9CQdBgB8AwAAAA==.Soulwhisper:BAACNQAFFIEJAAIcAAUKJxcaBACRAQAcAAUKJxcaBACRAQA1AAQKgSEAAhwACQqqIWoOABoDABwACQqqIWoOABoDAAAA.',
Sp='Spanda:BAABNQAECoEdAAIMAAgKqRgrCwAbAgAMAAgKqRgrCwAbAgAAAA==.Sparrkel:BAAANQAECgQIBQAAAA==.Splagzhul:BAAANQAECgIIAgAAAA==.Splendi:BAAANQAECgQIBAABNQAECggIHQAMAKkYAA==.Sprogg:BAAANQAECgEIAQAAAA==.Spyropaly:BAABNQAECoEjAAIEAAkKaCGhCABoAwAEAAkKaCGhCABoAwAAAA==.Spyroshaman:BAAANQADCgUICQABNQAECgkJIwAEAGghAA==.',
St='Stampede:BAAANQADCggIDwAAAA==.Stepzlol:BAAANQADCgYICQAAAA==.Stormsinger:BAABNQAECoEgAAMOAAgK2Rb9QwAEAgAOAAgK2Rb9QwAEAgALAAcKWQyQawCJAQAAAA==.',
Su='Sugarblast:BAACNQAFFIEIAAILAAUKMxfXBgCpAQALAAUKMxfXBgCpAQA1AAQKgSsAAgsACQoXJIEGAKUDAAsACQoXJIEGAKUDAAAA.Sukaii:BAAANQAECgUIBQAAAA==.Summonuber:BAAANQAECgIIAQAAAA==.Suou:BAABNQAECoEgAAMVAAkKEx6VLgDUAgAVAAkKEx6VLgDUAgAUAAEKnCByIQBZAAAAAA==.',
Sv='Svekkê:BAAANQAECgcIAQAAAA==.',
Sy='Sylint:BAAANQADCgYICwAAAA==.Sylliseas:BAAANQADCgYIBgAAAA==.',
Ta='Tandaley:BAAANQADCgQIBQABNQAECggIIAAOANkWAA==.Tandea:BAAANQAECgYIBgAAAA==.Tanthyr:BAAANQADCgEIAQAAAA==.',
Te='Testme:BAAANQADCgcICAAAAA==.Textaco:BAAANQADCgEIAQAAAA==.',
Th='Thedevilssin:BAAANQAECgUIBwAAAA==.Theodas:BAAANQAECgcIDQAAAA==.Thiccgnome:BAAANQAFFAIIAgAAAA==.Thiccthighs:BAAANQAECgEIAQAAAA==.Thirdlegolas:BAAANQAECgEIAQAAAA==.Thuuros:BAABNQAECoEbAAIcAAgKJhxVJQBbAgAcAAgKJhxVJQBbAgAAAA==.',
Ti='Tikariia:BAAANQAECgQIBAAAAA==.Tipsygypsy:BAAANQAECgYIDgAAAA==.Tirent:BAAANQAECgQICQAAAA==.',
To='Tokenbeef:BAAANQAECgUIDAAAAA==.Tokenshaman:BAABNQAECoEaAAIbAAgK3A2AEAAaAgAbAAgK3A2AEAAaAgAAAA==.Tokentrees:BAAANQADCgUJBQAAAA==.Touchspell:BAABNQAECoEZAAIQAAgK4Qi5zgCXAQAQAAgK4Qi5zgCXAQAAAA==.Toxicdk:BAABNQAECoEZAAQGAAkKSiAXHABfAgAGAAkKKBsXHABfAgAFAAYK4h5UNgDwAQAcAAEKWSFAmQBiAAAAAA==.Toxicshamy:BAAANQAECggICAABNQAECgkJGQAGAEogAA==.',
Tr='Traylay:BAABNQAECoEbAAIBAAkKMCE8JwDxAgABAAkKMCE8JwDxAgAAAA==.Trixaintime:BAAANQADCgcIBwAAAA==.Trommel:BAAANQAECgEIAQAAAA==.Trydoom:BAAANQADCgYIBgAAAA==.Trèè:BAAANQADCgMIBQAAAA==.',
Tt='Ttocs:BAABNQAECoErAAILAAkK3yQnAwDMAwALAAkK3yQnAwDMAwAAAA==.',
Tu='Tujori:BAACNQAFFIEMAAITAAUKwwodCwCMAQATAAUKwwodCwCMAQA1AAQKgR4AAhMACQoXF5k1AE4CABMACQoXF5k1AE4CAAAA.',
Tw='Twherk:BAABNQAECoEUAAIEAAgK9ArKeABbAQAEAAgK9ArKeABbAQABNQAFFAQIBwAOAEUJAA==.Twoeye:BAAANQADCgYIBgAAAA==.',
Ug='Uglydorf:BAABNQAECoEaAAIfAAcKQRJxawDjAQAfAAcKQRJxawDjAQAAAA==.',
Um='Umokthra:BAAANQAECgEIAQAAAA==.',
Us='Ustoo:BAAANQAECgYIEAAAAA==.',
Va='Vae:BAAANQAECgMJAwAAAA==.Vaeros:BAAANQAECgUICwAAAA==.Varcina:BAAANQAECgYIDAABNQAFFAMIBQAFAGQKAA==.Variana:BAAANQAECgcIDgAAAA==.Vaylle:BAAANQADCgQJBAAAAA==.',
Ve='Vekz:BAABNQAECoEgAAIEAAgKAB4BIQC6AgAEAAgKAB4BIQC6AgAAAA==.Veles:BAAANQAECgEIAQAAAA==.Velytia:BAAANQAECgcIEQAAAA==.Vexøs:BAAANQADCggIDwAAAA==.',
Vi='Vitiliga:BAAANQAECgYIDgAAAA==.',
Vo='Volcanicbird:BAAANQAECgMIAwAAAA==.Vomax:BAAANQADCgEIAQAAAA==.',
Wa='Wasteofpants:BAAANQAECgUIBwAAAA==.Waterbôy:BAAANQAECgQIBAABNQAECgkJKgAEALAVAA==.',
Wh='Whîrly:BAAANQADCgUIBgAAAA==.',
Wo='Wolf:BAAANQAECgIIAgAAAA==.',
Wt='Wtfheal:BAAANQAECggICwABNQAFFAQIBwAOAEUJAA==.',
Wu='Wumbology:BAAANQADCgQIBAAAAA==.',
['Wà']='Wàrrior:BAAANQADCgUICQAAAA==.',
Ya='Yamashaman:BAAANQAECgcIEgAAAA==.Yamo:BAAANQADCgcIBwAAAA==.Yardgnome:BAAANQAECgYIBgAAAA==.',
Yu='Yuna:BAAANQAECgYIEAAAAA==.',
Za='Zacheris:BAAANQAECgcIEgABNQAECgkJJQAFAKwSAA==.Zafod:BAAANQADCgYICQAAAA==.Zamasu:BAAANQAECgIJAwAAAA==.Zapped:BAAANQAECgEIAQAAAA==.Zaszadin:BAEBNQAECoEUAAIBAAcKsBosXwAkAgABAAcKsBosXwAkAgAAAA==.Zaszhadoom:BAEANQADCgYIBgABNQAECgcIFAABALAaAA==.',
Ze='Zekt:BAAANQADCgcICQAAAA==.Zeltron:BAAANQADCgUICgAAAA==.Zerax:BAAANQAECgUICgAAAA==.Zerolinkin:BAAANQAECgEIAQAAAA==.',
Zi='Zillagoth:BAAANQADCggICQAAAA==.Zira:BAAANQAECgYIEgAAAA==.',
Zo='Zombidruid:BAAANQADCgUJCAAAAA==.Zombiebubble:BAAANQAECgEIAQAAAA==.Zoìdberg:BAAANQAFFAEIBAAAAA==.',
Zs='Zselk:BAAANQADCgUIBQAAAA==.Zshot:BAAANQAECgQICQAAAA==.',
Zu='Zubzer:BAAANQADCgYIBgAAAA==.',
Zz='Zzor:BAACNQAFFIEFAAIQAAMK7BXYIAABAQAQAAMK7BXYIAABAQA1AAQKgS4AAhAACQpdI5ESAHoDABAACQpdI5ESAHoDAAAA.',
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
