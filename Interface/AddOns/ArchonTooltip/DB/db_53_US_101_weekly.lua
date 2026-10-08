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

local lookup = {'DeathKnight-Unholy','Shaman-Restoration','DeathKnight-Blood','Rogue-Assassination','Monk-Windwalker','Monk-Mistweaver','Unknown-Unknown','Priest-Shadow','Druid-Guardian','Druid-Restoration','Priest-Holy','Priest-Discipline','Warlock-Demonology','Shaman-Elemental','Druid-Balance','Warrior-Fury','Warrior-Arms','Hunter-BeastMastery','DeathKnight-Frost','DemonHunter-Vengeance','Warlock-Destruction','Warrior-Protection','DemonHunter-Devourer','DemonHunter-Havoc','Paladin-Protection','Paladin-Holy','Shaman-Enhancement','Hunter-Marksmanship','Evoker-Devastation','Evoker-Augmentation','Paladin-Retribution','Warlock-Affliction',}
local provider = {region='US',realm='Galakrond',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aastrid:BAAANQADCgYIDAAAAA==.',
Ad='Adorabúll:BAAANQADCgEIAQAAAA==.',
Ae='Aevriia:BAAANQADCgIIAgAAAA==.',
Ak='Akélla:BAAANQAECggICAAAAA==.',
Al='Aldric:BAAANQAECgQIBAAAAA==.Alien:BAAANQAFFAIIAgAAAA==.Althenzdormu:BAAANQAECgUIDgAAAA==.Altruist:BAAANQAECgQICQABNQAECgcIGAABAC0WAA==.',
Am='Amaethon:BAAANQAECgQICAAAAA==.',
An='Ancaera:BAAANQADCggIDQAAAA==.Andalikus:BAABNQAECoEcAAICAAgKGyNUEQAlAwACAAgKGyNUEQAlAwAAAA==.Andorra:BAAANQADCgYICwAAAA==.Andybocelli:BAAANQADCgYIBgAAAA==.Anrien:BAAANQAECgYIDwAAAA==.',
Ar='Ari:BAAANQADCgcIBwAAAA==.Around:BAAANQAECgQIBgAAAA==.',
As='Asharal:BAAANQADCgYIBgAAAA==.',
At='Atriste:BAABNQAECoEYAAMBAAcKLRb6TgCvAQABAAcKLRb6TgCvAQADAAUKlQfbggDLAAAAAA==.',
Au='Aunyx:BAABNQAECoEXAAIEAAcKsAxeOgCoAQAEAAcKsAxeOgCoAQAAAA==.',
Az='Azenoth:BAAANQADCggIGgAAAA==.',
Ba='Babajaga:BAAANQADCgIJAgAAAA==.Baloth:BAAANQADCgYJBgABNQAECgcIFwAFAKIQAA==.',
Be='Beej:BAABNQAECoEjAAIGAAgKzBmNDwBgAgAGAAgKzBmNDwBgAgAAAA==.',
Bi='Biggooch:BAAANQAECgcIEAAAAA==.Bison:BAAANQADCgcJBwAAAA==.',
Bl='Blackrose:BAAANQADCgYIDQABNQAECggIEwAHAAAAAA==.Blightbeard:BAAANQAECgUICgAAAA==.Blîss:BAAANQAECgUICwAAAA==.',
Br='Brayliel:BAAANQADCgQIBQAAAA==.Brut:BAAANQAECgQIBwABNQAECgkJJAAIAFMhAA==.',
Bu='Bullsi:BAAANQADCggIEAABNQAECggIJwAJAHsXAA==.Bumpy:BAAANQADCggICAAAAA==.Bustus:BAABNQAECoEXAAIKAAcKIwe7OAAiAQAKAAcKIwe7OAAiAQAAAA==.',
Ca='Calinia:BAAANQABCgMIBQAAAA==.Carole:BAABNQAECoEnAAMBAAgKiyB/JwB8AgABAAgKiyB/JwB8AgADAAYKqhK3XgBWAQAAAA==.Caroll:BAABNQAECoEkAAQIAAkKUyE2CwAcAwAIAAgKFSM2CwAcAwALAAQK/xUBoQD2AAAMAAMKQgs1GACUAAAAAA==.Carsomavra:BAAANQADCgQICAAAAA==.Cathercy:BAAANQAECgUIDQAAAA==.',
Ch='Chrollo:BAAANQAECgUIDgAAAA==.Chunt:BAAANQADCgYIDQAAAA==.',
Cl='Cloggy:BAAANQADCgYIBgABNQAFFAUICAANALsbAA==.',
Co='Corannis:BAABNQAECoEWAAIOAAcKKROPZQC/AQAOAAcKKROPZQC/AQAAAA==.Corax:BAAANQADCgQIBgAAAA==.',
Cr='Cranberries:BAAANQAECgIIAQABNQAECgkJKQACAGwKAA==.Cravedog:BAABNQAECoEyAAMJAAgKmCMGBQAoAwAJAAgKmCMGBQAoAwAPAAMK9Qt9hQCLAAAAAA==.Creepi:BAAANQAECgUIDQAAAA==.Crockett:BAAANQABCggIDAABNQAECgEIAQAHAAAAAA==.Cromgabhar:BAAANQADCgYJBgABNQAECgUICQAHAAAAAA==.',
Cu='Cupcáke:BAAANQAECgcIDwAAAA==.Curthodnes:BAAANQADCgIJAgAAAA==.',
Da='Dalmas:BAAANQADCgUIBQAAAA==.Damaso:BAAANQAECgQIBQAAAA==.Damik:BAAANQAECgEIAQAAAA==.Darku:BAAANQAECgYIEgAAAA==.Darlàrk:BAAANQAECgYICQAAAA==.Dawnmane:BAAANQAFFAEIAQAAAA==.',
De='Delderach:BAAANQAECgUIDQAAAA==.Dellila:BAAANQABCgcIBwAAAA==.Denin:BAAANQAECgYIEAAAAA==.Derphardigan:BAAANQADCgYIBgABNQAECgUICQAHAAAAAA==.',
Di='Diego:BAAANQADCgMIAwAAAA==.Dirkette:BAAANQAECgcIEwAAAA==.',
Dk='Dkxsmurfx:BAAANQADCgYICAAAAA==.',
Do='Dokai:BAABNQAECoEXAAIFAAcKohDyKwCIAQAFAAcKohDyKwCIAQAAAA==.',
Dr='Dracmiz:BAAANQADCggIEAAAAA==.Drathan:BAAANQADCgMJAwAAAA==.',
Dt='Dthnght:BAAANQADCgQIBwAAAA==.',
Du='Duskweaver:BAAANQADCgIIAgAAAA==.',
Ea='Earthboy:BAAANQADCgIIAgABNQAECgkJJAAIAFMhAA==.',
El='Elaenei:BAAANQADCgcIEwAAAA==.Eliance:BAAANQAECgQIDQAAAA==.Elienn:BAAANQADCgYIEQAAAA==.Elinore:BAAANQADCgQIBAAAAA==.',
Er='Errius:BAABNQAECoEZAAIDAAYKvgoUcwAEAQADAAYKvgoUcwAEAQAAAA==.',
Es='Esh:BAAANQADCgQIBAABNQAECggIDgAHAAAAAA==.',
Eu='Eunja:BAEANQADCggIGwAAAQ==.',
Fa='Facetious:BAAANQADCgIIAgAAAA==.',
Fi='Filharmonic:BAAANQADCgUJEQAAAA==.Fizzbin:BAAANQADCgMIAwAAAA==.',
Fo='Foid:BAACNQAFFIEJAAMQAAMKnBstAQAZAQAQAAMKnBstAQAZAQARAAEKWA2DNQBEAAA1AAQKgRoAAxAACQp3I6ACAC0DABAACQp3I6ACAC0DABEAAQobAlFLARUAAAE1AAUUAwoJABAAnBsA.',
Fu='Furiah:BAAANQADCgYICwAAAA==.Fusaa:BAABNQAECoEmAAINAAgKLhVvXQAdAgANAAgKLhVvXQAdAgAAAA==.',
Ga='Gahzoo:BAAANQADCgYIFAAAAA==.Gallindo:BAAANQADCgIIAgABNQAECgUIBgAHAAAAAA==.Gangry:BAAANQADCgYIBgAAAA==.Garretjax:BAAANQADCgYIEwAAAA==.Garuda:BAAANQAECgYIDwAAAA==.',
Ge='Gelst:BAAANQADCgUIEAAAAA==.Gelstoo:BAAANQADCgYIBgAAAA==.Gerbs:BAAANQADCgYIBgAAAA==.Gerbzarrion:BAAANQAECgQIDQAAAA==.Getherdone:BAAANQADCgUIDAAAAA==.',
Gi='Gilgador:BAAANQAECgcIDQABNQAECgcIEgAHAAAAAA==.',
Gr='Grassfed:BAAANQAECgUICAAAAA==.',
Gu='Guilehart:BAAANQABCgIIAQAAAA==.',
Ha='Hawknnib:BAAANQAECgQICQAAAA==.Hawknnin:BAAANQADCgcIBwABNQAECgQICQAHAAAAAA==.',
Ho='Hothala:BAAANQADCgYIDwAAAA==.',
Hu='Hunterpulled:BAABNQAECoE2AAISAAgK3BO6ZAAgAgASAAgK3BO6ZAAgAgAAAA==.',
Ic='Icnothing:BAAANQADCgcIEAAAAA==.',
In='Infectedarms:BAAANQAECgYIDQAAAA==.Invisabull:BAAANQADCgYIBgABNQAECgUICQAHAAAAAA==.',
Ip='Ipwnallnoobs:BAABNQAECoEYAAITAAgKFQnVPwCFAQATAAgKFQnVPwCFAQAAAA==.',
Ir='Irisila:BAAANQADCggIEwABNQAECgUIBgAHAAAAAA==.',
Ja='Jaskilz:BAAANQADCgQIBgAAAA==.Jaypharyn:BAAANQAECgQICQAAAA==.Jazel:BAAANQADCgQICAAAAA==.',
Je='Jellyapes:BAAANQAECgQICAAAAA==.',
Jo='Johalea:BAAANQADCgYIEQAAAA==.',
Ju='Juliå:BAAANQADCgYIDQAAAA==.',
['Jå']='Jåsper:BAAANQAECgUIDgAAAA==.',
Ka='Kahea:BAEANQADCgYIBgABNQAECgYICQAHAAAAAA==.Kaileena:BAABNQAECoEaAAIUAAgK8RcACQAuAgAUAAgK8RcACQAuAgAAAA==.Kasia:BAAANQAECgUIDgAAAA==.Kassani:BAAANQADCgEJAQAAAA==.Kasuga:BAAANQADCgQIBAABNQAECgkJIAAVAEYkAA==.',
Ki='Kieler:BAAANQAECgQIBQAAAA==.Kierrings:BAAANQAECgQIBwAAAA==.Kikala:BAAANQADCgMIAwAAAA==.Kirarah:BAABNQAECoEWAAISAAcKeyTQJgDdAgASAAcKeyTQJgDdAgAAAA==.Kiylo:BAAANQADCgEIAQAAAA==.Kizune:BAAANQADCgcIBwAAAA==.',
Kl='Klauss:BAABNQAECoEdAAIGAAgK9wp8HgB1AQAGAAgK9wp8HgB1AQAAAA==.Klax:BAAANQADCgcIEwAAAA==.',
Ko='Kordjin:BAAANQADCgIIAgAAAA==.',
Kr='Krornik:BAAANQADCgYIDgABNQAECgEIAQAHAAAAAA==.',
Ku='Kuyaros:BAAANQADCgUIBQAAAA==.',
['Kí']='Kíhanna:BAABNQAECoEdAAISAAgKMyGVIAD4AgASAAgKMyGVIAD4AgAAAA==.',
Le='Legenddairy:BAABNQAECoEnAAIJAAgKexecEAAXAgAJAAgKexecEAAXAgAAAA==.',
Li='Liemach:BAAANQADCgIIAgAAAA==.',
Lj='Ljósálfr:BAABNQAECoEaAAIWAAgKDCIUBgDnAgAWAAgKDCIUBgDnAgAAAA==.',
Lo='Lochramae:BAAANQAECgYIEAAAAA==.',
Lu='Lunaluvegood:BAAANQADCgUIBQAAAA==.Lunargaze:BAABNQAECoErAAMXAAkK1B8JCgAsAwAXAAkKtB8JCgAsAwAYAAQKGR4fSgBCAQAAAA==.',
['Lâ']='Lâriel:BAAANQAECgYIEAAAAA==.',
Ma='Madmartigan:BAAANQAECgUICQAAAA==.Mamimisan:BAAANQAECgYIDgAAAA==.Matix:BAAANQABCggIFQAAAA==.',
Me='Mechadockie:BAAANQAECgQIBwAAAA==.',
Mi='Miklo:BAAANQADCgUICgAAAA==.Mirah:BAAANQADCgMIAwAAAA==.Mistazee:BAAANQAECgUIBgAAAA==.Mizan:BAAANQAECggICQABNQAECgkJKgAZAKocAA==.Mizeroni:BAABNQAECoEqAAMZAAkKqhxGCwDFAgAZAAkKqhxGCwDFAgAaAAEKjARLCAEyAAAAAA==.Mizkat:BAAANQADCgcIAQABNQAECgkJKgAZAKocAA==.Mizky:BAAANQADCgQIBAAAAA==.',
Mo='Mormra:BAAANQAECgEIAQAAAA==.',
Mt='Mtruckski:BAAANQABCgIIAgABNQAECgQIBwAHAAAAAA==.',
My='Myoo:BAAANQADCgUIBgAAAA==.',
['Më']='Mërcy:BAAANQADCgYIDQAAAA==.',
Na='Naklus:BAAANQADCgUICQAAAA==.',
Ne='Neilia:BAAANQAECgcIEgAAAA==.Nerdroot:BAAANQADCgMIAwABNQAECgYIGQAYAPYGAA==.Nerdvana:BAAANQADCgYIBgABNQAECgYIGQAYAPYGAA==.Neropoison:BAAANQADCgIIAwAAAA==.Nessamos:BAAANQADCgIIAgAAAA==.',
Ni='Nikalkhano:BAAANQADCgYICQAAAA==.',
Nl='Nlani:BAAANQAECgQICwAAAA==.',
Nu='Nuvi:BAAANQADCgUICAAAAA==.',
Oc='Octarius:BAAANQAECgIIAgABNQAECgQIBgAHAAAAAA==.',
On='Onomirigaru:BAABNQAECoEdAAIXAAgKwg6pJwDnAQAXAAgKwg6pJwDnAQAAAA==.',
Op='Oproer:BAAANQADCggICAAAAA==.',
Ox='Oxygentank:BAAANQAECgYIBwAAAA==.',
Pa='Parne:BAAANQADCgUIBQAAAA==.',
Pi='Piccolo:BAAANQAECggIAQAAAA==.Pips:BAAANQADCgYIBgABNQAECgYIGwABAGMNAA==.',
Pl='Platura:BAABNQAECoEYAAIaAAcKvxfGVAD7AQAaAAcKvxfGVAD7AQAAAA==.',
Pv='Pvp:BAAANQADCgMIAwAAAA==.',
Ra='Raezune:BAAANQABCgYICwAAAA==.Rajia:BAABNQAECoEYAAIVAAcKbwUdKAAsAQAVAAcKbwUdKAAsAQAAAA==.Ranron:BAAANQAECgMIAwAAAA==.Rassaphore:BAAANQADCggIDwAAAA==.Raínbow:BAAANQADCgcJCgABNQAECgUICAAHAAAAAA==.',
Re='Reapin:BAAANQAECgUIDgAAAA==.Rezeldâ:BAAANQAECgEIAQAAAA==.',
Rh='Rhaegalsh:BAAANQAECgcIEQAAAA==.',
Ri='Rionach:BAABNQAECoEXAAIJAAcKsA0LIABVAQAJAAcKsA0LIABVAQAAAA==.Rivon:BAAANQADCggIGgAAAA==.',
Ru='Runeneya:BAAANQAECggIBwAAAA==.',
Sc='Schtzngigllz:BAAANQADCgQIBAABNQAECgEIAQAHAAAAAA==.Scoop:BAABNQAECoEVAAMLAAcKbxwrVAD6AQALAAYKmBwrVAD6AQAIAAYKJBaVLwB+AQAAAA==.',
Se='Seanan:BAABNQAECoEkAAIbAAgK8iJHBABIAwAbAAgK8iJHBABIAwAAAA==.Seera:BAAANQADCgIIAgAAAA==.Seran:BAABNQAECoEgAAIaAAgKPQaHfwBxAQAaAAgKPQaHfwBxAQAAAA==.',
Sh='Shammwow:BAAANQAECgcICgAAAA==.Shamoo:BAAANQAECgYIBgAAAA==.Shaudis:BAABNQAECoEcAAINAAcKaBijYQARAgANAAcKaBijYQARAgAAAA==.Shiftyshape:BAAANQAECgEJAQAAAA==.Shigurexx:BAABNQAECoEWAAIcAAgKEQ0/LgCzAQAcAAgKEQ0/LgCzAQAAAA==.Shoe:BAABNQAECoEkAAIdAAgKkReXEAAuAgAdAAgKkReXEAAuAgAAAA==.Shootup:BAAANQADCgQJCQAAAA==.',
Sk='Skiliz:BAAANQADCgYIBgAAAA==.',
Sl='Slapurdaddy:BAAANQADCgUJCQAAAA==.',
So='Somassen:BAABNQAECoEZAAISAAYKoAyKrAB4AQASAAYKoAyKrAB4AQAAAA==.Sonashee:BAAANQAECgcIDQAAAA==.Sorender:BAAANQADCgYIEAAAAA==.',
St='Steelbutt:BAAANQADCggIHAAAAA==.',
Su='Supersoakêr:BAAANQAECgQIBAABNQAECgcIDQAHAAAAAA==.Surii:BAAANQADCgYICwAAAA==.',
Ta='Talene:BAAANQADCgUIBgAAAA==.Tamarins:BAAANQAECgUIDgAAAA==.Tappy:BAABNQAECoEjAAILAAgKvRE9WgDjAQALAAgKvRE9WgDjAQAAAA==.',
Te='Terkarakk:BAABNQAECoEbAAIJAAgK+iPABAAyAwAJAAgK+iPABAAyAwABNQAFFAEIAQAHAAAAAA==.',
Th='Thirryn:BAABNQAECoEYAAIeAAcK4AhQDwAdAQAeAAcK4AhQDwAdAQAAAA==.Thorybos:BAAANQAECgcIEwAAAA==.',
Ti='Tippy:BAAANQAECgIIAwAAAA==.',
To='Toom:BAAANQAECgQIDQAAAA==.',
Tr='Traylinna:BAAANQADCgEIAQAAAA==.Trophyhubby:BAABNQAECoEZAAMLAAYKWgtojwAtAQALAAYKWgtojwAtAQAIAAQKAAa5TwCnAAAAAA==.',
Tu='Tuknark:BAAANQADCgYIEQAAAA==.',
Ty='Tyeren:BAAANQAECgUIDQAAAA==.Tyeriel:BAACNQAFFIEJAAMTAAQKyAkADADVAAATAAMKnQwADADVAAABAAIKiQIFGQBnAAA1AAQKgScAAxMACQqsG6EdAHYCABMACQohG6EdAHYCAAEABAoMGPN8AP8AAAAA.Typpy:BAAANQAECgIIAgAAAA==.',
Tz='Tzuriel:BAEBNQAECoEfAAMZAAkKlB7FCwC9AgAZAAcKOyPFCwC9AgAfAAcKoxHktgB3AQAAAA==.',
Va='Valkyriewing:BAAANQAECgUIDQAAAA==.Valvet:BAAANQADCggIIAAAAA==.',
Ve='Velaste:BAAANQADCgQIBAAAAA==.',
Vi='Vikril:BAABNQAECoEVAAQDAAcKSRQyXgBYAQADAAUKQxcyXgBYAQABAAYKpA1RcAAvAQATAAEKpQmekgA1AAAAAA==.Vincenzo:BAAANQADCgUICgAAAA==.',
Vo='Volkanoth:BAAANQAECgUIBwAAAA==.',
Vy='Vylus:BAAANQAECgYIEAAAAA==.',
['Vá']='Vásh:BAABNQAECoEYAAMQAAcKDA8YEwBHAQARAAcKyQyfpwCOAQAQAAYKDg0YEwBHAQAAAA==.',
We='Webjibaro:BAAANQADCgUICgAAAA==.Weeblewobble:BAAANQADCgYIEQAAAA==.Weili:BAAANQAECgUIDAAAAA==.',
Wh='Whiney:BAAANQAECgIIAgABNQAECgYICQAHAAAAAA==.',
Wi='Wikidfiend:BAAANQADCgQIBQAAAA==.William:BAAANQAECgYIDgAAAA==.Windee:BAAANQADCgYICgAAAA==.Wishi:BAAANQADCgQIBAAAAA==.',
Wr='Wrast:BAAANQAECgUICQAAAA==.Wravyn:BAABNQAECoEZAAISAAYKggd3wABNAQASAAYKggd3wABNAQAAAA==.',
Xa='Xalted:BAAANQADCgUJCQAAAA==.Xandria:BAAANQADCgUIBQAAAA==.Xaylios:BAAANQAECgYICQAAAA==.',
Xy='Xyara:BAABNQAECoEnAAQVAAkKVhiLJABEAQANAAcKhBc4ZQAGAgAVAAUK6RKLJABEAQAgAAMKLA9HFgC/AAAAAA==.',
Yo='Yoghurt:BAABNQAECoEZAAMQAAgKYBcdCAA+AgAQAAgKYBcdCAA+AgARAAEKtALMPwEoAAAAAA==.',
Yu='Yunlan:BAAANQAECgEIAQAAAA==.',
Za='Zalidus:BAAANQAECgUICQAAAA==.Zanthor:BAAANQAECgUICQABNQAECgkJJgAFAHcSAA==.',
Ze='Zehnia:BAAANQABCgcIDQAAAA==.Zephira:BAAANQADCgUIBgAAAA==.',
Zi='Zibzab:BAAANQAECgUIDQAAAA==.',
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
