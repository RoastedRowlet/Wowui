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

local lookup = {'Priest-Holy','Priest-Shadow','Unknown-Unknown','Mage-Arcane','Warrior-Arms','Warrior-Protection','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-BeastMastery','Mage-Frost','Mage-Fire','Shaman-Elemental','Warlock-Destruction','Warlock-Demonology','DeathKnight-Blood','Druid-Restoration','Shaman-Restoration','Shaman-Enhancement','Paladin-Holy','Paladin-Retribution','Rogue-Assassination','Druid-Balance','DeathKnight-Frost','DeathKnight-Unholy','Hunter-Marksmanship','Rogue-Subtlety','Paladin-Protection','Evoker-Preservation','Warrior-Fury','Monk-Brewmaster',}
local provider = {region='US',realm='ScarletCrusade',name='US',type='weekly',zone=53,date='2026-10-06',data={Ac='Acefu:BAAANQAECgYIEQAAAA==.Acornella:BAABNQAECoEZAAMBAAkKoRKmQgA7AgABAAkKoRKmQgA7AgACAAIKhgvOXgBbAAABNQAFFAEIAQADAAAAAA==.Acornkei:BAAANQAFFAEIAQAAAA==.',
Ad='Adonsia:BAAANQADCgQIBAAAAA==.Adreva:BAAANQAECgQICQAAAA==.',
Ae='Aelana:BAAANQADCgQIBAAAAA==.Aendor:BAAANQADCgcIBwABNQAECgkJHQAEALYUAA==.Aerea:BAAANQAECgEIAgABNQAECgcIFAAFAI8NAA==.Aevastraa:BAAANQADCgEIAQABNQAECggIGwAGAHgOAA==.',
Ai='Ailanthus:BAAANQAECgcIDQAAAA==.',
Al='Albinophil:BAAANQADCgIIAgABNQAECgYICwADAAAAAA==.Alloisaber:BAAANQABCgEIAQAAAA==.Alunne:BAAANQADCgQIBAAAAA==.',
Am='Amna:BAAANQAECgQIBwAAAA==.',
An='Andrelsia:BAAANQADCgQIBwAAAA==.Andrilla:BAAANQADCgYJDAAAAA==.Ankeseth:BAAANQADCggJDQAAAA==.',
Ar='Aracelis:BAAANQADCggICAAAAA==.Araxiel:BAAANQADCggICwAAAA==.Archangël:BAAANQAECgEIAQAAAA==.Arkenos:BAAANQADCgYICwAAAA==.Arén:BAABNQAECoEaAAMHAAYKEiRrLgAEAgAHAAUKwiNrLgAEAgAIAAQKaB1yOwBBAQAAAA==.',
As='Ashenshugär:BAAANQADCgcIEQAAAA==.Aszian:BAAANQABCgcICgAAAA==.Aszun:BAABNQAECoEeAAIJAAcKjhDEhgDNAQAJAAcKjhDEhgDNAQAAAA==.',
At='Atractiva:BAABNQAECoEcAAMKAAgKwAgfEgBcAQALAAgKPwbSAwBxAQAKAAgKVAcfEgBcAQAAAA==.',
Au='Aura:BAAANQABCgQIBAAAAA==.',
Az='Azmar:BAAANQADCgIIAgAAAA==.Azuri:BAAANQADCgYICwABNQADCgcIEgADAAAAAA==.',
Ba='Balain:BAABNQAECoEUAAMFAAcKjw3upACVAQAFAAcKjw3upACVAQAGAAQKVAU0LQCcAAAAAA==.',
Be='Bear:BAAANQAECgEIAQAAAA==.Bearzerk:BAAANQAECgYIEQAAAA==.Benathar:BAAANQAECgMIBwAAAA==.Bethela:BAAANQABCgYIBgABNQAECgcIHgAJAI4QAA==.',
Bl='Blackmagék:BAAANQABCgIIAgAAAA==.Blaston:BAAANQAECgUICAAAAA==.Blightbeard:BAAANQADCggIDgAAAA==.Bloodthorn:BAAANQAECgUIDAAAAA==.',
Bo='Boomnescient:BAAANQADCgYICwAAAA==.Bottomdps:BAABNQAECoEjAAIMAAkKVhpWJADVAgAMAAkKVhpWJADVAgAAAA==.',
Br='Bramis:BAAANQADCggICAAAAA==.Branor:BAAANQAECgEIAQAAAA==.Bransonian:BAAANQADCgQJBgAAAA==.Brantu:BAABNQAECoEeAAMNAAcK+gM6SgCWAAAOAAcK+gPnxQARAQANAAUK3AE6SgCWAAAAAA==.Braultus:BAABNQAECoEfAAIPAAgK9xlyLQBEAgAPAAgK9xlyLQBEAgAAAA==.Bravehearth:BAAANQADCgEIAQAAAA==.Breuddwydwr:BAAANQADCgEIAQAAAA==.Brewtality:BAAANQADCggICAAAAA==.Breyastrasza:BAAANQADCgYIDwAAAA==.',
Ca='Caanu:BAABNQAECoEdAAIEAAkKthTmbQCNAgAEAAkKthTmbQCNAgAAAA==.Calydonia:BAAANQAECgIIAwAAAA==.',
Ce='Celdiseth:BAAANQADCggICwAAAA==.Cerdwin:BAAANQAECgUIDAABNQAECggIGgAQAA0PAA==.',
Ch='Charferad:BAAANQADCgYIDAAAAA==.Chatter:BAAANQADCgcICAAAAA==.Cheeseydeath:BAEANQAECgMIAwAAAA==.Chibeard:BAAANQAECgMIBwAAAA==.',
Cl='Clevercrane:BAAANQAECgMIAgABNQAECgYIDQADAAAAAA==.',
Co='Coolbro:BAAANQADCgcIBwAAAA==.Corialis:BAABNQAECoEXAAMRAAgKzRQyiQBFAQARAAYKkg8yiQBFAQAMAAMK/QwB3gChAAAAAA==.',
Cr='Crom:BAABNQAECoEhAAISAAgKsA4PFgDbAQASAAgKsA4PFgDbAQAAAA==.Crying:BAAANQAECgMIBgAAAA==.',
Cy='Cyn:BAAANQADCgQIBgAAAA==.',
Da='Dandarred:BAAANQAECgYIEwAAAA==.Dantey:BAAANQADCgIIAgABNQAECgcIEQADAAAAAA==.Darkwyn:BAAANQADCgUIBQAAAA==.Dawne:BAAANQAECggIEgAAAA==.Dazanna:BAABNQAECoEbAAMTAAgKdhFPUgAEAgATAAgKdhFPUgAEAgAUAAEKtQ44dAE0AAAAAA==.Dazjaxx:BAAANQABCgQIBwAAAA==.Dazre:BAAANQAECgIIAgAAAA==.',
De='Deeminor:BAAANQADCgIJAgAAAA==.Demeisen:BAABNQAECoEcAAIHAAcKyBHsOQCwAQAHAAcKyBHsOQCwAQAAAA==.Demonizerr:BAAANQAECgEIAQABNQAECgcIEQADAAAAAA==.',
Di='Diksensei:BAAANQADCgYIJAAAAA==.Diod:BAAANQAECgMIBQAAAA==.',
Dr='Dracomage:BAAANQADCgMIBgAAAA==.Dracotincan:BAAANQADCgIIAgAAAA==.Draegis:BAAANQABCgIIAgAAAA==.Dragyns:BAABNQAECoEhAAIVAAkK9yBRDwDnAgAVAAkK9yBRDwDnAgAAAA==.Dragynslance:BAAANQADCggIDAABNQAECgkJIQAVAPcgAA==.Drayper:BAAANQAECgQICAAAAA==.',
Du='Dunbarke:BAAANQAECgUIEAAAAA==.',
['Dê']='Dêadlights:BAAANQAECgQICQAAAA==.',
El='Elendrisa:BAAANQAECgUIDgAAAA==.Elisoria:BAAANQADCgYJBgAAAA==.Elliwynd:BAABNQAECoEZAAIQAAgKFBTsHQAVAgAQAAgKFBTsHQAVAgAAAA==.Elway:BAAANQADCgIIAgAAAA==.',
Em='Embermourne:BAAANQADCggICAAAAA==.',
Er='Eraela:BAAANQADCggICAAAAA==.Erinnys:BAABNQAECoEYAAIHAAgKLAe5QQB7AQAHAAgKLAe5QQB7AQAAAA==.',
Es='Esoteria:BAABNQAECoEfAAIEAAgKxBpHbwCKAgAEAAgKxBpHbwCKAgAAAA==.',
Eu='Eufemia:BAAANQADCgQJBwAAAA==.',
Ev='Evonnya:BAAANQADCggIDgAAAA==.',
Fe='Felfar:BAAANQADCggICwAAAA==.',
Fi='Finalomega:BAAANQAECgQIBwAAAA==.Finnshot:BAAANQAECgIIAgAAAA==.Finrod:BAAANQADCgQIBwAAAA==.',
Fl='Flaminfalcon:BAAANQAECgEIAgABNQAECgYIDQADAAAAAA==.',
Fo='Foulmilk:BAAANQADCgEIAQAAAA==.Foxflame:BAABNQAECoEaAAMQAAgKDQ+YJwCzAQAQAAgKDQ+YJwCzAQAWAAIKFwf4kABeAAAAAA==.',
Fr='Franzen:BAAANQADCgYIFAAAAA==.Frawd:BAAANQADCgcIBwABNQAECgkJKgAEANkkAA==.Freyalys:BAAANQADCgYIEwAAAA==.Frôstblade:BAAANQABCgYIBgAAAA==.',
Fu='Fulanita:BAAANQADCgcIEwAAAA==.Furyaid:BAABNQAECoEWAAIFAAgKOSJmIAAoAwAFAAgKOSJmIAAoAwAAAA==.',
Ga='Galadrael:BAAANQAECgQJBAAAAA==.Gaz:BAAANQADCgQIBAAAAA==.',
Ge='Genkithered:BAAANQAECgMIBwAAAA==.',
Gl='Gloomy:BAAANQADCgEIAQAAAA==.',
Go='Gourak:BAAANQAECgQICAAAAA==.',
Gr='Gravemarks:BAAANQADCgYIBAAAAA==.Grimhorn:BAAANQAECgIIBAAAAA==.Grimlie:BAAANQADCgYJDgABNQAECgcIHgANAPoDAA==.',
Gu='Guaritrice:BAAANQAECgEIAQAAAA==.',
Gw='Gwindor:BAAANQADCgQJBwAAAA==.',
['Gö']='Gödwyn:BAAANQAECgEIAQABNQAECgQICAADAAAAAA==.',
Ha='Hairyrage:BAAANQABCgQICAAAAA==.Hale:BAAANQADCgEIAgAAAA==.',
He='Healzey:BAAANQADCgUIBAAAAA==.Hetairoi:BAAANQAECgYICwAAAA==.',
Hi='Hillbroken:BAABNQAECoEjAAIXAAgKPBejJQA2AgAXAAgKPBejJQA2AgAAAA==.',
Ho='Holynez:BAAANQADCgcIDQAAAA==.',
Hu='Huan:BAAANQAECgIIAgAAAA==.Huntrix:BAAANQADCgYICgAAAA==.',
['Hà']='Hànks:BAAANQAECgMIAwAAAA==.',
Ib='Ibíng:BAAANQAECgEIAgAAAA==.',
In='Invariance:BAEANQADCgUIBQABNQAECgUIBQADAAAAAA==.Inèvitable:BAABNQAECoEiAAIYAAgKRh/NHQC7AgAYAAgKRh/NHQC7AgAAAA==.',
Ir='Ironphant:BAAANQAECgYIDQAAAA==.',
Is='Ishmethit:BAAANQADCgYIBgAAAA==.Istara:BAAANQADCgYIFAAAAA==.',
Je='Jebib:BAAANQAECgYIBgABNQAFFAcIHQAQAGgjAA==.Jeod:BAAANQADCgQIBwAAAA==.Jettonk:BAAANQABCgIIAgABNQAECgcIHgANAPoDAA==.',
Ji='Jirachi:BAAANQADCgEIAQAAAA==.',
Jo='Jolty:BAABNQAECoElAAMYAAkKqiJkEAAfAwAYAAkKqiJkEAAfAwAPAAQKoxdrdwD0AAAAAA==.',
Ju='Junghoulson:BAAANQAECgUIBQAAAA==.',
['Jð']='Jð:BAAANQAECgcICQAAAA==.',
Ka='Kaiou:BAAANQADCgMICQAAAA==.Kantor:BAABNQAECoEkAAIBAAgKiAjacgCLAQABAAgKiAjacgCLAQAAAA==.Karboomkin:BAAANQAECgIIAgABNQAFFAQIDAAJAEEZAA==.Kasenko:BAAANQADCggICAABNQAECgUIBQADAAAAAA==.Kasryna:BAAANQAECgUIBQAAAA==.',
Ke='Kelmair:BAAANQADCgYIBgAAAA==.Keta:BAAANQAECgEIAQAAAA==.Ketameanie:BAAANQAECgUIEwAAAA==.',
Kh='Khadguy:BAAANQAECgYIEwAAAA==.',
Km='Kmazing:BAAANQADCggJFAABNQAECggIHwAEAMQaAA==.',
Kn='Knikku:BAAANQADCggICAAAAA==.',
Ko='Konoha:BAABNQAECoEbAAMCAAgKqR/7EQDBAgACAAgKqR/7EQDBAgABAAEKoiI41gBUAAAAAA==.Koven:BAAANQADCggIJAAAAA==.',
Ku='Kultag:BAAANQAECgcIEgAAAA==.Kuun:BAAANQAECgYIDAAAAA==.',
Ky='Kyaw:BAAANQAECgUIDQAAAA==.Kynzo:BAAANQAECgQICAAAAA==.',
La='Laelah:BAAANQABCgQIBQAAAA==.Lasmína:BAAANQADCgQIBwAAAA==.Laykeezenith:BAACNQAFFIEOAAMJAAcKKiF5AQBTAgAJAAYKdSB5AQBTAgAZAAQKYh4nCQCLAQA1AAQKgSIAAxkACQoyIkEXAIgCABkACQo/HUEXAIgCAAkABwoWGnl3APIBAAAA.Lazuli:BAABNQAECoEqAAIMAAkKSRlPKwCuAgAMAAkKSRlPKwCuAgAAAA==.',
Le='Lehann:BAAANQAECgYIEAAAAA==.',
Lo='Lothryn:BAAANQAECgcIEAAAAA==.',
Lp='Lp:BAAANQAECgUICwABNQAECgYIDAADAAAAAA==.',
Lu='Lunariah:BAAANQADCgIJAgAAAA==.',
Ly='Lyllien:BAAANQAECgIIAgAAAA==.',
Ma='Marenus:BAABNQAECoEkAAIJAAgKNwrUfQDjAQAJAAgKNwrUfQDjAQAAAA==.Marten:BAAANQABCgIIAgAAAA==.Masume:BAAANQAECgMIAwAAAA==.Maély:BAAANQADCgUIBQAAAA==.',
Me='Mechadead:BAAANQAECgQIBAABNQAECgcIEQADAAAAAA==.Megaopto:BAAANQAECgUIEQAAAA==.Meowmix:BAAANQADCgMICAAAAA==.Methanny:BAAANQADCgQIBAAAAA==.',
Mi='Mizmonk:BAAANQADCggICAAAAA==.',
Mj='Mjölnir:BAAANQAECgcIEAAAAA==.',
Mo='Momentum:BAAANQAECgEIAQAAAA==.',
Ms='Msdiiva:BAAANQAECgEIAQAAAA==.',
Mu='Mushuu:BAAANQADCgYIBgAAAA==.',
['Mô']='Môjô:BAAANQABCgUIBQAAAA==.',
Na='Nahion:BAAANQADCgQJBwAAAA==.Nashira:BAAANQAECgYIEAAAAA==.',
Ne='Nemasus:BAAANQAECgQIDAAAAA==.Nepolian:BAAANQABCgYICAAAAA==.Neraine:BAAANQAECgEIAQAAAA==.',
Ni='Ninjahh:BAABNQAECoEWAAIaAAcKbA/gHgDEAQAaAAcKbA/gHgDEAQAAAA==.Nioshei:BAABNQAECoEbAAIRAAgKShh5PgA8AgARAAgKShh5PgA8AgAAAA==.',
No='Nochmuerta:BAAANQADCgUIBQABNQADCgcIBwADAAAAAA==.Nogrid:BAABNQAECoEkAAIbAAgKDR8oDQCnAgAbAAgKDR8oDQCnAgAAAA==.Noxstantine:BAAANQADCgQIBgAAAA==.',
Nu='Nuthar:BAAANQAECgYIEgAAAA==.',
Ny='Nyrrhi:BAAANQAECggIDQAAAA==.',
Ol='Oldeis:BAAANQADCgYJBgAAAA==.',
Or='Orneryosprey:BAAANQAECgQIBwABNQAECgYICwADAAAAAA==.',
Ou='Ouroborös:BAAANQAECgcIEAAAAA==.',
Oy='Oyashiro:BAAANQAECgUIBQAAAA==.',
Pa='Pamburu:BAAANQAECgcIEAAAAA==.Papagrape:BAABNQAECoEbAAIcAAgK8RvvDgCnAgAcAAgK8RvvDgCnAgAAAA==.Paradiselost:BAAANQADCgQIBwAAAA==.Parzivàl:BAAANQAECgEIAQAAAA==.Paxa:BAAANQAECgYIDgAAAA==.',
Pe='Pennelo:BAAANQADCgQJBAAAAA==.Persayis:BAAANQADCgYIDAAAAA==.',
Ph='Phoebel:BAAANQADCgIJAgABNQAECgcIHgAJAI4QAA==.',
Pi='Pineappledk:BAEANQADCggIEgABNQAECgMIBgADAAAAAA==.Pineapplle:BAEANQAECgMIBgAAAA==.',
Pl='Plazelly:BAAANQADCgcIDAAAAA==.',
Po='Podnov:BAABNQAECoEmAAIZAAkKHRy1EgC5AgAZAAkKHRy1EgC5AgAAAA==.Pollyanna:BAAANQABCgYICAAAAA==.',
Py='Pyrista:BAAANQAECggICwAAAA==.',
Qa='Qahili:BAAANQADCgUIBQAAAA==.Qang:BAAANQADCgYIDAAAAA==.',
Ra='Radiante:BAABNQAECoEhAAMTAAkKrxxKFwAMAwATAAkKrxxKFwAMAwAUAAIKkApBTAFjAAAAAA==.Rageadin:BAAANQABCgcIBQAAAA==.Raion:BAABNQAECoEbAAIbAAgKOyBkDACzAgAbAAgKOyBkDACzAgAAAA==.Raithis:BAACNQAFFIEIAAIJAAQK5A/MDQBBAQAJAAQK5A/MDQBBAQA1AAQKgSQAAgkACQqQJEsLAHIDAAkACQqQJEsLAHIDAAAA.Ralzin:BAAANQADCgEIAQAAAA==.Ramhadin:BAEANQADCgcIEAABNQAECgYIEQADAAAAAA==.Randel:BAAANQADCggICAAAAA==.Raucousrhea:BAAANQABCgIIAgAAAA==.Rav:BAAANQAECgQICwAAAA==.',
Re='Redvelvet:BAAANQAECgYIEAAAAA==.Resisting:BAAANQAECgYIDAAAAA==.Reznal:BAABNQAECoEaAAMMAAgKfh9ZLgCfAgAMAAgKfh9ZLgCfAgARAAQKhx+xgwBUAQAAAA==.',
Ro='Romam:BAAANQADCgQIBwAAAA==.',
Ry='Rydran:BAAANQADCgIIAgAAAA==.Rykria:BAAANQADCgYIFAAAAA==.',
Sa='Sableanne:BAABNQAECoEzAAIRAAkK0QVYfwBgAQARAAkK0QVYfwBgAQAAAA==.Saedirine:BAAANQADCgYIDAAAAA==.Saggi:BAAANQAECgEIAgAAAA==.',
Se='Secksiecutie:BAABNQAECoEbAAIXAAgKyA89NgDBAQAXAAgKyA89NgDBAQAAAA==.Secondwall:BAAANQADCgYIBgAAAA==.Selma:BAAANQABCgMIAwAAAA==.Serinar:BAABNQAECoEZAAIUAAgKAxN3iQDgAQAUAAgKAxN3iQDgAQAAAA==.',
Sh='Shadowbolt:BAAANQABCgQIBgAAAA==.Shoorah:BAAANQADCgEIAQAAAA==.',
Si='Siako:BAAANQAECgcIEQAAAA==.Silversaiyan:BAABNQAECoEfAAIdAAcKZB8TBgCIAgAdAAcKZB8TBgCIAgAAAA==.Sirlink:BAAANQABCgIIAgAAAA==.',
Sl='Slade:BAABNQAECoEjAAMaAAgKuCEnBwABAwAaAAgKuCEnBwABAwAVAAMKGRimYADiAAAAAA==.Sliyce:BAAANQADCgEIAQAAAA==.',
Sm='Smorc:BAAANQAECgMIAwAAAA==.',
Sn='Sneakyclubs:BAAANQADCgUICAAAAA==.Snowfawn:BAAANQADCgcJDwABNQAECggIDgADAAAAAA==.',
So='Sofedan:BAABNQAECoEkAAIZAAgKmgRhOQBWAQAZAAgKmgRhOQBWAQAAAA==.Sorgath:BAAANQAECgEIAQAAAA==.Soriel:BAABNQAECoEbAAIeAAgKHhIkDwDdAQAeAAgKHhIkDwDdAQAAAA==.Sorokwa:BAAANQAECggIEAAAAA==.',
Sq='Squeeze:BAAANQAECgUJCwAAAA==.',
St='Stillwater:BAABNQAECoEbAAMSAAgKsgZEGAC1AQASAAgKsgZEGAC1AQAMAAMKygPk6wB8AAAAAA==.',
Su='Suriden:BAAANQADCggICQAAAA==.',
Sw='Swagidan:BAABNQAECoExAAIHAAkKmhrwGACxAgAHAAkKmhrwGACxAgAAAA==.Sweaterpally:BAAANQADCgUICQAAAA==.Swiftera:BAAANQAECgIIAgAAAA==.Swiftlier:BAAANQADCgMIBgABNQAECggIHwAPAG8MAA==.',
Sy='Sylphrène:BAAANQAECgYIEQAAAA==.',
Ta='Taleth:BAAANQADCgcIEgAAAA==.Tandrana:BAAANQAECgEIAQAAAA==.Targanisha:BAAANQADCggICAABNQAECgkJIwAMAFYaAA==.Targdh:BAABNQAECoEdAAIIAAgKMRZLIQAjAgAIAAgKMRZLIQAjAgABNQAECgkJIwAMAFYaAA==.Targforeva:BAAANQAECgQIBgABNQAECgkJIwAMAFYaAA==.',
Te='Terminus:BAAANQADCgMIAwAAAA==.',
Ti='Ticebane:BAAANQAECgcIEwAAAA==.Tichus:BAAANQADCgYIDgAAAA==.Tiduspullo:BAAANQADCgIIAgABNQAECgMIAwADAAAAAA==.Titanbeard:BAAANQADCggIGAAAAA==.Titor:BAAANQAECgUIEQAAAA==.Tituspullo:BAAANQAECgMIAwAAAA==.',
To='Tolduan:BAAANQAECgYICwAAAA==.Totemik:BAAANQADCgUIBQAAAA==.Toughturkey:BAAANQADCgEIAQABNQAECgYICwADAAAAAA==.',
Tr='Tricarnetry:BAAANQAECgcIEQAAAA==.Tricarnity:BAAANQAECgMIAwABNQAECgcIEQADAAAAAA==.Trucknôrris:BAAANQADCgUIBwAAAA==.Trîela:BAAANQAECgUICgAAAA==.',
Ul='Ulfer:BAAANQADCgYIBgABNQAECggIGwAYAFUeAA==.',
Ve='Verakis:BAABNQAECoEbAAIGAAgKeA44FQCnAQAGAAgKeA44FQCnAQAAAA==.Verndarí:BAABNQAECoEfAAIPAAgKbwwtUwCFAQAPAAgKbwwtUwCFAQAAAA==.Verudora:BAAANQAECgEIAQAAAA==.',
Vi='Vishas:BAAANQAECgQIBgAAAA==.',
Vo='Vortheus:BAAANQADCggICwAAAA==.Votollis:BAAANQAECgEIAQAAAA==.',
Vr='Vrack:BAAANQADCgQIBAAAAA==.',
Wa='Warhowl:BAAANQABCggIDgAAAA==.Warlanen:BAAANQADCgQJBwAAAA==.',
Wi='Willbur:BAABNQAECoEjAAIEAAgKuhKPqAAQAgAEAAgKuhKPqAAQAgAAAA==.',
Wu='Wurthwhile:BAAANQADCgcIEQAAAA==.',
Wy='Wyndywalker:BAAANQAECgMIBwAAAA==.',
Xi='Xinnuo:BAAANQADCggIEAAAAA==.',
Za='Zamønk:BAAANQAECgQICAAAAA==.',
Ze='Zeigfeld:BAAANQADCgYIDAAAAA==.',
Zi='Ziarra:BAAANQADCgUIBQAAAA==.',
Zo='Zok:BAAANQAECgIIBAAAAA==.',
Zy='Zyzz:BAAANQADCgQJBAAAAA==.',
['Zä']='Zädä:BAAANQADCgQIBQAAAA==.',
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
