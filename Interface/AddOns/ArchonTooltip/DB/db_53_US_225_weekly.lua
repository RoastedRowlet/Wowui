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

local lookup = {'Monk-Brewmaster','Hunter-BeastMastery','Unknown-Unknown','Priest-Holy','Priest-Discipline','Monk-Mistweaver','DemonHunter-Havoc','Mage-Arcane','Warlock-Demonology','Warrior-Protection','Warrior-Arms','Shaman-Restoration','Warlock-Destruction','DeathKnight-Blood','DemonHunter-Devourer','Hunter-Survival','Hunter-Marksmanship','Druid-Balance','Warlock-Affliction','DemonHunter-Vengeance','Shaman-Elemental','Evoker-Devastation','Mage-Frost','Rogue-Subtlety','Rogue-Assassination','Paladin-Retribution','Paladin-Holy','Paladin-Protection','DeathKnight-Unholy','Priest-Shadow','Monk-Windwalker','Evoker-Augmentation','DeathKnight-Frost','Druid-Guardian','Evoker-Preservation','Druid-Restoration',}
local provider = {region='US',realm='Trollbane',name='US',type='weekly',zone=53,date='2026-09-22',data={Ac='Acroin:BAAANQADCgQIBAAAAA==.',
Ad='Adeliz:BAAANQAECgcIDAAAAA==.Adorana:BAAANQADCgQIBAAAAA==.Adrunk:BAABNQAECoEcAAIBAAgK3h2QBQCjAgABAAgK3h2QBQCjAgAAAA==.',
Ae='Aeloesh:BAAANQADCgUICAAAAA==.Aelyra:BAAANQADCgYICAAAAA==.Aenatheon:BAAANQAECgQJBwAAAA==.',
Ag='Aggrum:BAAANQAECgcJCgAAAA==.',
Ah='Ahab:BAAANQAECgIIAgAAAA==.Ahexutroll:BAAANQAECgUICQAAAA==.',
Ai='Aiur:BAAANQADCggJGwAAAA==.',
Ak='Akredfox:BAAANQAECgUICwAAAA==.',
Al='Alexaviah:BAAANQAECgYJDQAAAA==.Alicedelight:BAAANQAECgUIDAAAAA==.Alwaysburnt:BAAANQAECgIIAgAAAA==.Alwayscooked:BAAANQADCgIIAgAAAA==.Alwaysrolled:BAAANQABCgQIBAAAAA==.',
Am='Amabeast:BAAANQADCgUIBQAAAA==.Amanitin:BAAANQADCgQIBAAAAA==.Amisia:BAAANQADCggJHwAAAA==.',
An='Anathas:BAAANQAECgYJDgAAAA==.Ancestor:BAAANQADCgEIAQAAAA==.Angelfelis:BAABNQAECoEcAAICAAgKkyKPEgAPAwACAAgKkyKPEgAPAwAAAA==.Angelgoblin:BAAANQADCgQIBQAAAA==.Angriff:BAAANQADCggIDgAAAA==.Angrybeavor:BAAANQAECgQJBQAAAA==.Anuke:BAAANQADCgcIBwAAAA==.',
Ao='Aonaar:BAAANQADCgcIEwAAAA==.',
Ar='Archdemon:BAAANQAECgcIDwAAAA==.Arkroot:BAAANQADCggIDwAAAA==.Arlock:BAAANQADCggJCAAAAA==.Arsy:BAAANQAECgMIAwAAAA==.Artichoke:BAAANQAECgIIAgABNQAECgQIBAADAAAAAA==.',
As='Ashidora:BAEANQADCgYJBgABNQAECggIHAAEADIRAA==.Ashidpriest:BAEBNQAECoEcAAMEAAgKMhHmRADPAQAEAAgKNBDmRADPAQAFAAMK1g98EAC3AAAAAA==.Ashtoreth:BAAANQAECgMJBAAAAA==.Assukun:BAABNQAECoEZAAIGAAgK1iAgBQAPAwAGAAgK1iAgBQAPAwAAAA==.Async:BAAANQAECgcIDQAAAA==.',
At='Ati:BAAANQADCgYIBgAAAA==.',
Au='Aurá:BAAANQADCgIIAgAAAA==.Autoattack:BAAANQADCgcIBwAAAA==.',
Ax='Axethegrippa:BAAANQAECgUJDwABNQAFFAEIAQADAAAAAA==.Aximumeffort:BAAANQADCgYIBgABNQAFFAEIAQADAAAAAA==.',
Az='Azenservis:BAAANQADCgQIBAAAAA==.Azseera:BAAANQADCgcJBwAAAA==.Azuzu:BAAANQADCgUJBQAAAA==.',
Ba='Baddmojo:BAAANQADCgQIBAAAAA==.Badmac:BAABNQAECoEaAAIHAAcK2hjAJQDjAQAHAAcK2hjAJQDjAQAAAA==.Baelliman:BAAANQAECgcICgAAAA==.Baium:BAAANQAECgEIAgABNQAECgUIDAADAAAAAA==.Bakemono:BAAANQABCgYIDwAAAA==.Bakora:BAAANQADCggIHAAAAA==.Banishedfate:BAAANQAECgYIDAAAAA==.Banishedform:BAAANQADCgYICgABNQAECgYIDAADAAAAAA==.Banishedholy:BAAANQADCgYJDAABNQAECgYIDAADAAAAAA==.Baozi:BAAANQAECgQIBQABNQAECgYIDQADAAAAAA==.Barelyholy:BAAANQAECgYJDQAAAA==.Barf:BAAANQAECgEJAwABNQAECgYIDQADAAAAAA==.Barrendar:BAAANQADCgIIAgAAAA==.Bartholamew:BAAANQADCgUIBwAAAA==.',
Be='Bearballz:BAAANQADCgIIAgAAAA==.Beardey:BAAANQADCgUIBQAAAA==.Berry:BAABNQAECoEYAAIIAAgK3ht+WACDAgAIAAgK3ht+WACDAgAAAA==.Besneakies:BAAANQAECgUJDAAAAA==.',
Bi='Bigdamfred:BAAANQADCgEIAQAAAA==.Binnford:BAAANQADCgcJFwAAAA==.',
Bl='Blackfang:BAAANQADCgUIBQABNQAECgcJCgADAAAAAA==.Blaqball:BAAANQADCgUJCQAAAA==.Bludboil:BAAANQADCgcIBwABNQAFFAIJBgAJACgTAA==.',
Bo='Bottombish:BAAANQADCggIDAAAAA==.Boulderjaw:BAAANQAECgYIDgAAAA==.Boxeybrown:BAABNQAECoEVAAIKAAcKFRWYDgCsAQAKAAcKFRWYDgCsAQAAAA==.',
Br='Braised:BAAANQAECgYJEAAAAA==.Brbdeported:BAAANQAECgIIAgAAAA==.Breakadakeys:BAABNQAECoEXAAILAAgKHhcCRgBQAgALAAgKHhcCRgBQAgAAAA==.Breccia:BAAANQADCggIGgAAAA==.Brutanious:BAAANQAECgEIAQABNQAECgQIBgADAAAAAA==.',
Bu='Bubbalicous:BAAANQAECggIBgAAAA==.Bubblebro:BAAANQAECgQICQAAAA==.Buffwarrior:BAAANQAECgcJDQAAAA==.Bustamoon:BAAANQADCggIDgAAAA==.Butterface:BAAANQAECgEIAgABNQAECgQIBAADAAAAAA==.',
['Bà']='Bàckstabbath:BAAANQADCgMIAwAAAA==.',
Ca='Caeruleus:BAAANQADCgcIBwAAAA==.Cammikins:BAEBNQAECoEbAAIMAAkKvSB+CABRAwAMAAkKvSB+CABRAwAAAA==.Cantmilkem:BAAANQADCgIIAgAAAA==.Capellaz:BAAANQAECgUIDAAAAA==.Capriestson:BAAANQAECgYIEAAAAA==.Cardib:BAAANQAECgMIAwABNQAECggIFwANAIwfAA==.Casandra:BAAANQAECgcIDwAAAA==.Cassiopeias:BAAANQADCgUIBQAAAA==.',
Ce='Celerynn:BAAANQADCgUICAAAAA==.Celestaura:BAAANQAECgQJBwAAAA==.Cenerald:BAAANQADCggICAAAAA==.Centares:BAAANQADCgYJEgAAAA==.',
Ch='Charlutes:BAAANQAECgQIBAAAAA==.Chekzy:BAAANQADCggIGQAAAA==.Chichii:BAAANQAECgMIBAAAAA==.Chilis:BAAANQADCgcIBwABNQAECgYJDQADAAAAAA==.Chiyuki:BAAANQADCgQJBAABNQAECgQIBwADAAAAAA==.Choasman:BAAANQADCgYIDAAAAA==.Chocolate:BAAANQADCgUJCAAAAA==.Chudpath:BAAANQAECgQIBwABNQAECgkJHQAGAHEbAA==.',
Cl='Cleome:BAAANQABCgEIAQAAAA==.',
Co='Coorsenjoyer:BAECNQAFFIEKAAIOAAQK2ROzCAAoAQAOAAQK2ROzCAAoAQA1AAQKgRkAAg4ACQoTH2kPAPICAA4ACQoTH2kPAPICAAAA.Copakid:BAAANQAECgQJCQAAAA==.Cowlie:BAABNQAECoEZAAIPAAgKlCFPCgANAwAPAAgKlCFPCgANAwAAAA==.Coøkiewizard:BAAANQADCgEIAQAAAA==.',
Cr='Crippy:BAAANQAECgYJDAABNQADCgIIAgADAAAAAA==.Crippypal:BAAANQAECgUIBwABNQADCgIIAgADAAAAAA==.Crippyx:BAAANQADCgIIAgAAAA==.Crowls:BAAANQADCgMIAwAAAA==.Cruelwar:BAAANQAECgYIDQAAAA==.',
Cu='Cuckcmder:BAAANQAECgUIDQAAAA==.',
Da='Daffodil:BAAANQADCgEIAQAAAA==.Daggoth:BAAANQAECgcIEwAAAA==.Dalrak:BAABNQAECoEbAAQQAAgKSCJIAQAiAwAQAAgK4yFIAQAiAwARAAQKgxilNQD+AAACAAIK4BlMzwCUAAAAAA==.Dandarth:BAAANQADCgMIAwAAAA==.Danemos:BAAANQADCgMIAwABNQAFFAIJBgAJACgTAA==.Dante:BAAANQAECgQIBAABNQAECgYJDwADAAAAAA==.Darkendelf:BAAANQAECgQIBQAAAA==.Darkothy:BAAANQAECgQJBwAAAA==.Darkvision:BAAANQAECgEIAQAAAA==.Dasdann:BAAANQADCgUIBQAAAA==.Datshammy:BAAANQADCgUIBQAAAA==.Datvoodoomon:BAABNQAECoEdAAISAAkKQx+yCwBCAwASAAkKQx+yCwBCAwAAAA==.Daïn:BAAANQAECgYIDAAAAA==.',
Dc='Dcaý:BAAANQAECgUIBQAAAA==.',
De='Deadboii:BAAANQAECgEJAQAAAA==.Deadjuggalo:BAAANQADCggIFgAAAA==.Deadlyfaith:BAAANQADCgYJDQAAAA==.Deadstep:BAAANQAECgQICAAAAA==.Deathzy:BAAANQADCgIIAgAAAA==.Deitzz:BAAANQADCgQIBAAAAA==.Deleralia:BAAANQAECgcIDwAAAA==.Demontopher:BAABNQAECoEcAAITAAkKNiYJAADuAwATAAkKNiYJAADuAwAAAA==.Derodrayne:BAAANQADCgYIBwAAAA==.Deshaler:BAAANQADCgcIBwAAAA==.Devoidshield:BAAANQAECgIIAgAAAA==.',
Di='Dicon:BAAANQADCgYIBgAAAA==.Dieric:BAAANQAECgUICAAAAA==.Dinkle:BAAANQADCgMJAwABNQAECgYICQADAAAAAA==.Dividian:BAAANQAECgYJDwAAAA==.',
Do='Dorastrain:BAABNQAECoEYAAIUAAgKRiUUAQBuAwAUAAgKRiUUAQBuAwAAAA==.',
Dr='Dracovoid:BAAANQAECgIJAgABNQAECgQJBQADAAAAAA==.Dragondees:BAAANQAECgIJAgAAAA==.Dragonwyck:BAAANQAECgQIBgAAAA==.Draytheus:BAAANQAECgQIBgAAAA==.Drganon:BAAANQAECgUIBQAAAA==.Dripping:BAAANQAECgQICAAAAA==.Dromai:BAAANQADCgQJBAAAAA==.',
Du='Duhdotsbruh:BAAANQAECgQIBAAAAA==.Duraf:BAAANQADCgQJBAAAAA==.Duugan:BAAANQADCgQIBAAAAA==.',
Ed='Edgarj:BAAANQADCgEIAQAAAA==.',
Ek='Eklipsch:BAAANQADCggIDwAAAA==.',
El='Eld:BAAANQABCgYIBwAAAA==.Electabuzz:BAEANQADCgcIBwABNQAECgkJJQALACQeAA==.Electrocute:BAAANQADCgMIAwAAAA==.Electrocutey:BAAANQAECgUIDAAAAA==.Elein:BAAANQADCgEIAQAAAA==.Eleman:BAAANQAECgEIAQAAAA==.Elfclover:BAABNQAECoEWAAIRAAcKUxUrIgDJAQARAAcKUxUrIgDJAQAAAA==.Elijahx:BAAANQAECgcJEgAAAA==.Elijay:BAAANQAECgUICAAAAA==.Eljayye:BAAANQADCgcJFwAAAA==.',
Em='Emisha:BAAANQADCgIIAgAAAA==.Emmshunter:BAAANQAECgYIDAAAAA==.',
En='Envi:BAAANQAECgIIAwAAAA==.',
Ep='Epicdemise:BAAANQADCggJDwAAAA==.Epicdemon:BAAANQADCgYIDAAAAA==.Epicwarlock:BAAANQADCggIDQAAAA==.Epona:BAABNQAECoEZAAMMAAcKQBNHUACnAQAMAAcKQBNHUACnAQAVAAEKfwFe+AAdAAAAAA==.',
Er='Erzá:BAAANQAECgUICwAAAA==.',
Es='Espina:BAAANQADCgUIBQAAAA==.',
Et='Eterna:BAAANQAECgUIBwAAAA==.',
Ev='Eveilyn:BAAANQAECgcICgAAAA==.Evilerno:BAAANQADCggJCAAAAA==.Evileye:BAAANQADCgYIBgAAAA==.',
Ex='Exarchamus:BAAANQAECgUIEgAAAA==.',
Fa='Facemelt:BAAANQAECgcJEwAAAA==.Farfy:BAABNQAECoEZAAIOAAgKTRYfJwAeAgAOAAgKTRYfJwAeAgAAAA==.Fartsmagoo:BAAANQAECgUJCgAAAA==.Faykan:BAAANQAECgUICgAAAA==.',
Fe='Fedrameda:BAAANQAECgUIDgAAAA==.Felix:BAAANQAECgYJDQAAAA==.Fellender:BAAANQADCggINAAAAA==.Fermented:BAABNQAECoEWAAIOAAcKhBdGMQDeAQAOAAcKhBdGMQDeAQAAAA==.',
Fi='Fizzle:BAAANQADCgQIBgAAAA==.',
Fl='Flintstones:BAABNQAECoEcAAISAAgKiRhZIwBSAgASAAgKiRhZIwBSAgAAAA==.Fluffykiitty:BAAANQADCgEIAQAAAA==.',
Fo='Fowlplay:BAAANQADCgYJFgAAAA==.Foxbox:BAAANQAECgEIAQAAAA==.',
Fr='Frostedhoof:BAAANQADCggICAABNQAECgkJJAARAFQgAA==.',
Fu='Fujee:BAAANQAECgYIEQAAAA==.Funkyt:BAAANQAECgMIBQAAAA==.Furrysona:BAAANQAECgEIAQABNQAECgkJHQAWALcVAA==.',
['Fâ']='Fâlooga:BAAANQAECgUIDQAAAA==.',
Ga='Gaidine:BAAANQADCgMJAwAAAA==.Galadriael:BAABNQAECoEXAAMXAAgK0x3nDQBSAQAIAAgKjhqiaQBUAgAXAAQKuB7nDQBSAQAAAA==.Galtan:BAAANQAECgMJAwAAAA==.Garrod:BAAANQAECgYICgAAAA==.Gasionaldo:BAAANQADCgEJAQAAAA==.Gattsu:BAAANQAECgIIAgAAAA==.',
Ge='Gennil:BAABNQAECoEeAAIXAAkKQiRzAACsAwAXAAkKQiRzAACsAwAAAA==.Gestella:BAAANQAECgQJCQAAAA==.Gevo:BAAANQAECgYIDQAAAA==.',
Gi='Gineselle:BAAANQAECgEIAQAAAA==.Giveemhail:BAAANQADCgMIAwABNQAECggIEgADAAAAAA==.',
Gl='Gloomblade:BAABNQAECoEcAAMYAAkKfx7vBgDtAgAYAAkKGx3vBgDtAgAZAAEKJBduWQBJAAAAAA==.',
Gn='Gnomepimp:BAAANQADCgYIBgABNQAECgUIBQADAAAAAA==.',
Go='Gojìra:BAAANQAECgUJBwAAAA==.Goragaia:BAAANQAECgYICQAAAA==.Gorbencleap:BAAANQABCgMIAwAAAA==.Gorion:BAAANQADCgQIBAAAAA==.',
Gr='Graypelt:BAAANQADCgcIBwAAAA==.Grayscale:BAAANQADCgYICgAAAA==.Greyseer:BAAANQAECgQIBgAAAA==.Grica:BAAANQADCgEIAQAAAA==.Gripsworth:BAAANQAECgQIBAABNQAECggJGQAGAOgXAA==.',
Gu='Guymontag:BAABNQAECoEYAAQaAAcKzB66PwBTAgAaAAcKzB66PwBTAgAbAAMK5RRdnQDJAAAcAAMK2hWcMQDDAAAAAA==.',
Ha='Halston:BAAANQADCgEIAQABNQAECgcIDwADAAAAAA==.Hammergobrr:BAAANQABCgQIBAAAAA==.Harbard:BAAANQAECgcIEgAAAA==.Hasselhøøf:BAAANQAECgcJEgAAAA==.Hawkeyeik:BAAANQAECgYICQAAAA==.Hawthorne:BAAANQAECgYIDgAAAA==.Hayywaffle:BAAANQADCggIDAAAAA==.',
He='Heilwelle:BAAANQADCgcIBwAAAA==.Hellothere:BAABNQAECoEZAAMaAAcKcyZMGAAaAwAaAAcKcyZMGAAaAwAcAAEKOQyOSgAzAAAAAA==.Hellren:BAAANQADCgYICQAAAA==.Helmet:BAAANQADCgQIBAAAAA==.',
Hi='Hikons:BAAANQAECgcJEwAAAA==.Hinkle:BAAANQAECgUICQABNQAECgYICQADAAAAAA==.',
Ho='Hobojoe:BAAANQAECgUICQAAAA==.Holyclover:BAAANQAECgEIAQAAAA==.Holysage:BAAANQADCgcIBwAAAA==.Holytoad:BAAANQADCgYIBgAAAA==.Hopsquash:BAAANQADCgQIBAAAAA==.Hopstop:BAAANQAECgUIDAAAAA==.',
Hu='Hughass:BAAANQADCgYIEgABNQAECgMIBQADAAAAAA==.Hugo:BAAANQAECgUIDwAAAA==.Hullr:BAAANQAECgQIBgAAAA==.Huwglyndur:BAAANQAECgUIDAAAAA==.',
Hy='Hyperiunpala:BAAANQAECgUJCQAAAA==.',
Ia='Iari:BAAANQADCggIDgAAAA==.',
Id='Idispizhorde:BAABNQAECoEXAAIdAAkK3RKuIgBPAgAdAAkK3RKuIgBPAgAAAA==.',
Ig='Igris:BAAANQAECgYJDQAAAA==.',
Il='Illihottie:BAAANQADCgQIBAAAAA==.Illiora:BAAANQADCgYIBQABNQAECggJMgAMAI4YAA==.Illissia:BAAANQAECgEJAQAAAA==.',
Im='Imós:BAAANQADCgcICAAAAA==.',
Ir='Ironpreacher:BAAANQADCgYIDQAAAA==.Ironspite:BAAANQADCggIDQAAAA==.',
Is='Ish:BAABNQAECoEiAAIeAAkKjB0fCQAaAwAeAAkKjB0fCQAaAwAAAA==.Ishibad:BAAANQAECgIIAwABNQAECgkJIgAeAIwdAA==.Isolie:BAAANQAECgEIAQAAAA==.Isongard:BAAANQABCgIIAgAAAA==.',
It='Itsthesham:BAAANQAECgQIBQABNQAECggJGAAfAN8cAA==.',
Iv='Ivok:BAAANQADCggIDwAAAA==.',
Iy='Iyooni:BAAANQABCgQIBAAAAA==.',
Ja='Jatbez:BAAANQADCgMIBQAAAA==.Jaykay:BAAANQADCgcJCgAAAA==.Jazmìne:BAAANQADCggJHgAAAA==.',
Je='Jessa:BAAANQAECgUIBQAAAA==.Jezuz:BAAANQAECgUICgAAAA==.',
Ji='Jimbadd:BAAANQAECgQIBAAAAA==.Jimmieslock:BAACNQAFFIENAAQJAAUKjiCGBACLAQAJAAQKnx+GBACLAQATAAEKEiZlAgBxAAANAAEKjCPdCwBtAAA1AAQKgRgAAwkACQo5JmUJAEUDAAkACAq8JWUJAEUDAA0ABwoCJOAFAJgCAAAA.Jimmiespala:BAAANQAECgIIAgABNQAFFAUIDQAJAI4gAA==.',
Jk='Jkils:BAAANQADCggIEQAAAA==.',
Jo='Jonbaptist:BAAANQAECgYIDAAAAA==.Jonile:BAAANQADCgEIAQAAAA==.Joyfulflame:BAAANQADCgMIAwABNQAECgUIDAADAAAAAA==.',
Jt='Jtrain:BAAANQAECgUIDgAAAA==.',
Ju='Judwin:BAAANQAECggIEAAAAA==.',
['Jä']='Jäzmine:BAAANQADCgIIAgAAAA==.',
['Jè']='Jèssicà:BAABNQAECoEgAAICAAgKrh4pJACoAgACAAgKrh4pJACoAgAAAA==.',
['Jô']='Jôseph:BAAANQADCgUIBgAAAA==.',
['Jö']='Jöe:BAAANQADCgIIAgAAAA==.',
Ka='Kaalin:BAAANQADCgIJAgAAAA==.Kabutosan:BAAANQAECgEIAQABNQAFFAIJBgAJACgTAA==.Kail:BAAANQADCgQIBAAAAA==.Kaleesi:BAAANQADCgcIEAAAAA==.Kamots:BAAANQAECgcJDAAAAA==.Kareokee:BAAANQAECgYIEwAAAA==.Kargoroth:BAABNQAECoEfAAIVAAkKqx1rGADoAgAVAAkKqx1rGADoAgAAAA==.Karnaga:BAAANQABCgcJCgAAAA==.Karral:BAABNQAECoEaAAMCAAkKrB5xDwAnAwACAAkKrB5xDwAnAwAQAAEK1Bd3DABLAAAAAA==.Katerzv:BAAANQADCgMIBAAAAA==.Kazdormu:BAABNQAECoEcAAMWAAkKbxKADABOAgAWAAkKbxKADABOAgAgAAEKVxAHGQAvAAAAAA==.',
Kc='Kchaos:BAAANQADCgcIBwAAAA==.',
Ke='Kedira:BAAANQADCggIEAABNQAECgkJPAAhAFEkAA==.Keloth:BAAANQADCgQIBAABNQAECgQIBAADAAAAAA==.Keyztone:BAAANQAECggIAgAAAA==.',
Kh='Khadriel:BAAANQAECgYJEAAAAA==.',
Ki='Killinrapidy:BAAANQADCgUJCQAAAA==.Kitani:BAABNQAECoEkAAIKAAkKoCHlAQBlAwAKAAkKoCHlAQBlAwAAAA==.',
Kn='Knottybits:BAAANQAECgEJAQABNQAECgEJAQADAAAAAA==.',
Ko='Konsumer:BAAANQADCgQJBAABNQAECgEJAQADAAAAAA==.Kontakt:BAAANQADCgcIDgAAAA==.Konân:BAAANQAECgYJDgAAAA==.Kordim:BAAANQAECgQICAABNQAECgcJGQAiAAsQAA==.Korvakh:BAAANQAECgEIAQAAAA==.',
Kr='Kraduun:BAAANQAECgUJCwAAAA==.Krantly:BAAANQADCggJFQAAAA==.Krenniellin:BAAANQAECgUJDwAAAA==.Krys:BAAANQAECgYIDAAAAA==.',
La='Laev:BAEANQADCggICAABNQAECggIHAAEADIRAA==.Lairbear:BAAANQADCgYJBgAAAA==.Lambadin:BAAANQADCgQIBAAAAA==.Lanaru:BAAANQADCggIFQABNQAECgUICwADAAAAAA==.Lavi:BAAANQAECgQIBAAAAA==.',
Le='Leizil:BAABNQAECoEZAAIEAAgKBxMzMwAmAgAEAAgKBxMzMwAmAgAAAA==.Lennox:BAAANQAECgYIDQAAAA==.Lesaire:BAAANQAECgIJAgAAAA==.Letara:BAAANQADCgYIBgAAAA==.Lextor:BAAANQADCgEIAQAAAA==.',
Lh='Lhuani:BAABNQAECoEjAAIIAAkKqB/nGwBHAwAIAAkKqB/nGwBHAwAAAA==.',
Li='Liaelina:BAEANQAECgUIDAAAAA==.Lichte:BAAANQABCgMIAwAAAA==.Lightmyhole:BAAANQADCgEJAQABNQAECgYIDAADAAAAAA==.Like:BAAANQADCgUIBQAAAA==.Lilyachty:BAAANQADCgUICgABNQAECggIFwANAIwfAA==.Lindbergh:BAAANQAECgQIBAAAAA==.Linshe:BAAANQAECgYJEgAAAA==.Lizzie:BAAANQADCgUIBQAAAA==.',
Ll='Llillianna:BAAANQAECgQIBwAAAA==.',
Lo='Loosey:BAAANQABCgYIBgAAAA==.Lorm:BAAANQADCgEIAQAAAA==.',
Lu='Lucarien:BAAANQAECgMIBQAAAA==.Lustyglory:BAAANQADCggICAAAAA==.',
Ma='Macareios:BAAANQADCgUIBQAAAA==.Madeintyø:BAAANQAECgMIAwABNQAECggIFwANAIwfAA==.Maelos:BAAANQAECgIIAgAAAA==.Mageaga:BAAANQADCgYICwAAAA==.Magnathul:BAAANQAECgcIEQAAAA==.Magnumdruid:BAAANQADCgQJBAAAAA==.Makeah:BAABNQAECoEdAAICAAgK5iI7FAADAwACAAgK5iI7FAADAwAAAA==.Makhamou:BAAANQAECgYIDwAAAA==.Malak:BAAANQAECgQJCgAAAA==.Malinstur:BAAANQAECgYIEQAAAA==.Marjorye:BAAANQAECgQJCwAAAA==.Marnaught:BAAANQAECgEJAQAAAA==.Marzánna:BAAANQADCgQIBwABNQAECgUICgADAAAAAA==.Mashed:BAAANQADCgYICwABNQAECgMIAwADAAAAAA==.Matts:BAAANQAECgEIAwAAAA==.Maxxamus:BAAANQAECgEIAQAAAA==.Mazaal:BAABNQAECoEdAAIhAAkKTCROAgCrAwAhAAkKTCROAgCrAwAAAA==.',
Mc='Mcshaft:BAAANQABCgQIBQAAAA==.',
Me='Meatmuskett:BAAANQADCggICAAAAA==.Mekeena:BAAANQAECgUICgAAAA==.Melesandre:BAAANQADCgYJEAAAAA==.Melinee:BAAANQADCgYIBwAAAA==.Mellinda:BAAANQAECgEIAgAAAA==.Melzas:BAAANQAECgQICgAAAA==.',
Mi='Midrok:BAABNQAECoEZAAIiAAcKCxDnEAB+AQAiAAcKCxDnEAB+AQAAAA==.Mikåh:BAAANQADCggJDgAAAA==.Milkjugzz:BAAANQADCgQIBAAAAA==.Miselah:BAAANQADCgEIAQAAAA==.Missyennefer:BAAANQADCgcIEgAAAA==.',
Mo='Mobythicc:BAAANQADCgcICQABNQAFFAEIAQADAAAAAA==.Mondai:BAAANQABCgQIBAAAAA==.Monkpowahh:BAAANQADCgEIAQABNQAECgQJBQADAAAAAA==.Montag:BAAANQADCggIDgABNQAECgcIGAAaAMweAA==.Moonboomfred:BAAANQADCgMIAwAAAA==.Moonshower:BAAANQAECgYJDgAAAA==.Mooranda:BAAANQABCggIDgAAAA==.Moraear:BAAANQADCgIJAgAAAA==.Morgaenei:BAAANQABCgMIAwAAAA==.',
Mt='Mtastyck:BAAANQADCgYICAAAAA==.',
Mu='Mudsniffer:BAAANQAECgQJBQAAAA==.Multitool:BAEBNQAECoEZAAIcAAgKKh2WCQCaAgAcAAgKKh2WCQCaAgAAAA==.Mundekk:BAAANQAECgQJBwAAAA==.',
My='Myobûky:BAAANQADCgUIBQAAAA==.Mystiecub:BAAANQABCgIJAQAAAA==.Mythgleam:BAAANQAECgIJAgAAAA==.Myththistle:BAAANQADCgEIAQAAAA==.',
['Má']='Mániac:BAAANQADCgYICwAAAA==.',
Na='Nack:BAAANQADCgcICQABNQAECggJEwADAAAAAA==.Nacks:BAAANQAECggJEwAAAA==.Nacksd:BAAANQADCgEIAQABNQAECggJEwADAAAAAA==.Nacksly:BAAANQAECgIIAgABNQAECggJEwADAAAAAA==.Nacksm:BAAANQADCggICAABNQAECggJEwADAAAAAA==.Nacksp:BAAANQADCgUIBQABNQAECggJEwADAAAAAA==.Naelandra:BAAANQADCgQJBAABNQAECgcIGAAaAMweAA==.Naliön:BAAANQADCggIFAAAAA==.Naotsugu:BAAANQADCggIEQAAAA==.Nargacuga:BAAANQAECgEIAQABNQAECgYIEAADAAAAAA==.Nasarden:BAAANQAECgMIBAAAAA==.Nasir:BAAANQADCggIEwAAAA==.Nastysage:BAAANQAECgUJCwAAAA==.Nastyxxnate:BAAANQADCgcJCgAAAA==.Natric:BAAANQAECgEJAQAAAA==.Naxdh:BAAANQADCgYICQABNQAECggJEwADAAAAAA==.',
Ne='Nechanion:BAAANQADCggJEAAAAA==.Nessië:BAAANQAECgQICQAAAA==.Nesthor:BAAANQADCgYIBgAAAA==.',
Ni='Nimibear:BAAANQAECgIIAgAAAA==.Nimidk:BAABNQAECoEZAAIOAAkKBB0TFADBAgAOAAkKBB0TFADBAgAAAA==.Ninjahealer:BAAANQAECgEJAQAAAA==.',
No='Noobtotem:BAAANQADCgYICwABNQAECgYJDQADAAAAAA==.Nooffensë:BAEANQADCgcJDAABNQAECgUIDAADAAAAAA==.',
Nu='Nugsmasher:BAAANQADCgYICwAAAA==.Nutdevourer:BAABNQAECoEYAAIPAAcKOxy6FgBhAgAPAAcKOxy6FgBhAgAAAA==.',
['Né']='Néther:BAAANQADCgcICAAAAA==.',
Oa='Oakelvin:BAAANQAECgcJDgAAAA==.',
Ob='Obnoxiousego:BAAANQAECggIEQAAAA==.',
Od='Odartherogue:BAAANQADCgUIBAAAAA==.Oddknee:BAABNQAECoEkAAMRAAkKVCCUBgBDAwARAAkKVCCUBgBDAwACAAEK/hfc4gBUAAAAAA==.Odney:BAAANQAECgQICAABNQAECgkJJAARAFQgAA==.',
On='Onaria:BAAANQAECgcICwABNQAECggJMgAMAI4YAA==.',
Or='Oridox:BAAANQAECgYJEQAAAA==.Orumine:BAABNQAECoEhAAIaAAkK4B+oFwAfAwAaAAkK4B+oFwAfAwAAAA==.',
Ov='Overhere:BAAANQAECgEIAQABNQAECgQJBQADAAAAAA==.',
Pa='Pahpi:BAAANQAECggIBgAAAA==.Palcan:BAAANQADCgUJEAAAAA==.Papii:BAAANQAECggIAgAAAA==.Paratussum:BAAANQADCgYIBgAAAA==.Parka:BAABNQAECoEaAAIhAAkKthz+DADaAgAhAAkKthz+DADaAgAAAA==.Pattysmash:BAAANQAECgYICwABNQAFFAMIBQAMAP4UAA==.',
Pb='Pbody:BAAANQAECgcIEgAAAA==.',
Pe='Perhorn:BAAANQADCgYJDQAAAA==.',
Po='Pollywog:BAAANQADCgcIBwABNQAECgQIBAADAAAAAA==.Polunocnicá:BAAANQAECgUICgAAAA==.Pooj:BAAANQADCggIFwAAAA==.',
Pr='Primehunter:BAAANQAECgUIBQAAAA==.Primetime:BAAANQAECgUICgAAAA==.Prissila:BAAANQADCgYJDwAAAA==.Prollimix:BAAANQAECgEJAwAAAA==.',
Ps='Psychoshorts:BAAANQAECgUJDQAAAA==.Psykick:BAAANQADCgEIAQAAAA==.',
Py='Pyropoint:BAAANQAECgQIBAAAAA==.',
Ra='Rachela:BAAANQAECgEIAQAAAA==.Ractiel:BAAANQADCgUIDgAAAA==.Raidhero:BAAANQAECgIIAgAAAA==.Rain:BAAANQAECgQIBAAAAA==.Raked:BAAANQAECgUIDgAAAA==.Ranfna:BAAANQADCggICQAAAA==.Rapidkiill:BAAANQADCgQIBwAAAA==.Rapidly:BAAANQADCgUJBQAAAA==.Raspberrytea:BAAANQABCggJDwAAAA==.Raviolio:BAAANQAECgMIAwABNQAECgMIBQADAAAAAA==.',
Re='Reebz:BAAANQADCgYJBwABNQADCgIIAgADAAAAAA==.Reflection:BAAANQAECgYJEgAAAA==.Rekcutnerd:BAAANQAECgEJAQAAAA==.Reppa:BAAANQADCggICAAAAA==.Retiniris:BAABNQAECoEYAAMCAAcKciAQLACDAgACAAcKciAQLACDAgARAAEKDQNHZAArAAAAAA==.',
Rh='Rhonstaris:BAAANQAECgEJAgAAAA==.Rhylintras:BAAANQADCgQIBwABNQAECgUICgADAAAAAA==.',
Ri='Riceporridge:BAAANQAECgYIDQAAAA==.Riptakeoff:BAAANQADCgcIBwABNQAECggIFwANAIwfAA==.Riskofrain:BAAANQAECgEIAQAAAA==.Ritzcarltina:BAAANQADCgQJBAAAAA==.Ritzu:BAAANQADCggICAABNQAECgQIBgADAAAAAA==.',
Ro='Rockemi:BAAANQABCgMIAwAAAA==.Rodo:BAAANQADCgYIBgAAAA==.Roxyviper:BAAANQAECgQIDQAAAA==.Royalfox:BAAANQAECgYJEAAAAA==.',
Ru='Rubbish:BAAANQADCggJHgAAAA==.',
Sa='Saatari:BAAANQAECgEJAQAAAA==.Saddeath:BAAANQADCgYIBgAAAA==.Saeylaura:BAAANQADCggIEwAAAA==.Saintchuck:BAAANQADCggIFwAAAA==.Sainted:BAAANQADCggIEQAAAA==.Salanaar:BAABNQAECoEdAAIOAAkKgh0AEgDVAgAOAAkKgh0AEgDVAgAAAA==.Salarix:BAAANQAECgMIBAAAAA==.Sanarian:BAAANQADCgUIBQAAAA==.Sanctified:BAAANQAECggIBwAAAA==.Sarja:BAAANQAECgUIDAAAAA==.Sarras:BAAANQADCggIEgAAAA==.Sasserfrass:BAAANQAECgYJCwAAAA==.Savaant:BAAANQADCgIIAgAAAA==.Sayy:BAAANQAECgcIEAAAAA==.',
Sc='Scaledrage:BAAANQAECgcIBwAAAA==.Schism:BAAANQAECgYJCgABNQADCggIFQADAAAAAA==.',
Se='Seaotter:BAAANQAECgYJEAAAAA==.Sellioni:BAAANQAECgUIBQABNQAECgYIEAADAAAAAA==.Senhonrue:BAAANQAECgEIAQAAAA==.Serabian:BAAANQADCgUIBQAAAA==.Seraz:BAABNQAECoEdAAIjAAkKORoGCgDHAgAjAAkKORoGCgDHAgAAAA==.Seregios:BAAANQAECgQIBAABNQAECgYIEAADAAAAAA==.Serenitey:BAAANQADCgcJFwAAAA==.Serraglyndur:BAAANQAECgUIDAAAAA==.',
Sh='Shaderaina:BAAANQADCggIEgAAAA==.Shadowgame:BAAANQADCgQIBAAAAA==.Shambe:BAAANQADCgIIAgAAAA==.Shamidzi:BAAANQADCgQIBQAAAA==.Sheabutters:BAAANQAECgYICQAAAA==.Shennequa:BAAANQABCgUIBQAAAA==.Shmorg:BAAANQAECgMIBQAAAA==.Shunaiman:BAAANQAECgUIDAAAAA==.Shàdowdànce:BAAANQADCgUIBwAAAA==.Shábam:BAAANQAECgEJAQAAAA==.',
Si='Sifferr:BAAANQAECgQJBwAAAA==.Sijinn:BAAANQADCgYIDAAAAA==.Silus:BAAANQAECgQIBAAAAA==.',
Sk='Skezes:BAAANQADCgYIBgAAAA==.Skotom:BAAANQADCggJFAAAAA==.Skyjericho:BAAANQAECgMJBAAAAA==.',
Sl='Slann:BAAANQAECgUJBQAAAA==.Slattpal:BAABNQAECoEYAAIbAAkKIB/VCQBIAwAbAAkKIB/VCQBIAwAAAA==.Sleebydruid:BAAANQAECgcIBwAAAA==.Sleebyevoker:BAAANQAECgYIEgABNQAECgcIBwADAAAAAA==.',
Sm='Smurghl:BAAANQADCgcIBwAAAA==.',
Sn='Snackysteak:BAAANQADCgYIBgAAAA==.',
So='Socinks:BAAANQADCgcJBwAAAA==.Solistome:BAAANQADCgcJEQAAAA==.Somarlar:BAAANQADCgMIAwAAAA==.Sopho:BAAANQAECgYIDAAAAA==.Sophogue:BAAANQADCgUIBQABNQAECgYIDAADAAAAAA==.Sophomage:BAAANQADCgYJBgABNQAECgYIDAADAAAAAA==.',
Sp='Specialtea:BAAANQADCggIFgAAAA==.',
Sq='Squam:BAAANQADCgcIBwABNQAECggJGAAIAN4bAA==.',
St='Starzpapi:BAAANQABCgIIAgABNQAECggIFwANAIwfAA==.Stonebones:BAAANQADCgcICAAAAA==.Strappy:BAAANQADCgcIBwAAAA==.Stwife:BAABNQAECoEfAAMdAAkKMhqbFQDBAgAdAAkKbxmbFQDBAgAhAAIKVA+vXgBlAAAAAA==.Störmë:BAAANQADCgUJCQAAAA==.',
Su='Sufrucia:BAAANQAECgcJCwAAAA==.Sunday:BAAANQAECgYIDgAAAA==.Sunhime:BAAANQAECgEIAQABNQAECgcIBwADAAAAAA==.Surâ:BAAANQAECgYIEQAAAA==.',
Sy='Symbol:BAAANQAECgcJEgABNQAECggJGAAIAN4bAA==.Sympissal:BAAANQADCggJFwAAAA==.',
['Sò']='Sònya:BAAANQAECgYIEgAAAA==.',
['Sÿ']='Sÿlvanas:BAAANQAECgIJAQAAAA==.',
Ta='Tabhunter:BAAANQADCgcJDAAAAA==.Tagritalth:BAAANQADCgcIDQABNQABCgMIAwADAAAAAA==.Taindnddra:BAAANQADCgEIAQABNQAECgEJAQADAAAAAA==.Talanas:BAAANQADCggIBQAAAA==.Tanishalfelf:BAACNQAFFIEIAAMaAAQKYx+DBQBWAQAaAAMKJSaDBQBWAQAbAAEKyQWBFwBNAAA1AAQKgSMAAxoACQroJhsBAPYDABoACQroJhsBAPYDABsABwqVFLRAAPIBAAAA.Tankaman:BAAANQADCgQJCwABNQAECgQIBgADAAAAAA==.',
Te='Telliah:BAAANQABCgEJAQAAAA==.Tempestre:BAAANQADCgMIAwAAAA==.Terrorfury:BAAANQADCgUICQAAAA==.Texoutlaw:BAAANQAECgEIAQAAAA==.',
Th='Thalassikos:BAAANQAECgEIAQABNQAECgIJAgADAAAAAA==.Thatredhead:BAAANQADCgQJBAAAAA==.Thegremlin:BAAANQAECgIJAwAAAA==.Thewraith:BAAANQAECgEJAQAAAA==.Thorcised:BAABNQAECoEaAAIOAAgKvxLSMQDbAQAOAAgKvxLSMQDbAQAAAA==.Thorin:BAAANQAECgUIDAAAAA==.Thorym:BAAANQADCgUIBQABNQAECgYJEwADAAAAAA==.Thoryndir:BAAANQAECgYJEwAAAA==.Thrym:BAAANQAECgcIEQAAAA==.Thundernut:BAAANQADCggIEAAAAA==.',
Ti='Tidalsong:BAAANQADCggIHAAAAA==.Tirillian:BAAANQADCgUIBQAAAA==.Tirionsson:BAAANQAECgEJAQAAAA==.Tirnoir:BAAANQADCgQIBgABNQAECgQIBAADAAAAAA==.',
Tk='Tkenga:BAAANQAECgEJAQAAAA==.',
To='Tojarm:BAAANQADCgEIAQAAAA==.Tonicdeath:BAAANQAECgQIBgAAAA==.Torr:BAAANQADCgYIBgAAAA==.Torshana:BAAANQADCgEIAQAAAA==.Totemgobbler:BAAANQAECgEIAQAAAA==.Totemlyfine:BAAANQAECgUICAAAAA==.',
Tr='Tralzind:BAAANQADCgMIAwAAAA==.Truthsayer:BAAANQAECgYJEQAAAA==.',
Ts='Tsquared:BAABNQAECoEYAAMXAAgK/g9DBwDxAQAXAAgK/g9DBwDxAQAIAAMKhASrQgF/AAAAAA==.Tsukasa:BAAANQAECgUJBQAAAA==.Tsuruchi:BAAANQAECgUIBQAAAA==.',
Tu='Tukk:BAAANQAECgQIBAAAAA==.Tumnina:BAAANQADCgYICwAAAA==.',
Tw='Twiinkletoes:BAAANQADCggIDAAAAA==.Twopuffs:BAAANQAECgQJBAAAAA==.',
Ty='Tyce:BAAANQAECgUIDAAAAA==.Tylannis:BAAANQAECgYIEQAAAA==.',
Ug='Ugacoop:BAABNQAECoEdAAMJAAgK6CJgHAC+AgAJAAcKzCJgHAC+AgANAAIK3h54OgC0AAAAAA==.',
Ut='Uthrick:BAAANQADCgYIBgAAAA==.',
Va='Vaelisara:BAAANQAECgQJCAAAAA==.',
Ve='Vehe:BAAANQAECgcJBwAAAA==.Veldrys:BAAANQADCggJDgABNQAECgYIEQADAAAAAA==.Veledaa:BAAANQADCgYJFgAAAA==.Venomnips:BAAANQADCgQIBAAAAA==.Verige:BAAANQAECgEIAQAAAA==.Vesperbough:BAAANQABCgIJAgAAAA==.Vetis:BAAANQADCggIEAAAAA==.',
Vi='Vicars:BAAANQADCgYICwABNQAECgQIBwADAAAAAA==.Vickos:BAAANQAECgYJCAAAAA==.Vilyawen:BAAANQABCgIIBAAAAA==.Virgil:BAAANQADCgUJCgABNQAECgYJDwADAAAAAA==.Visionblast:BAAANQADCgEIAQAAAA==.Visionlink:BAAANQADCgEJAQAAAA==.Vixyn:BAAANQADCgEJAQAAAA==.',
Vo='Voidme:BAAANQADCgEIAQABNQAECgQJBQADAAAAAA==.Voidshift:BAAANQABCgMIAwAAAA==.Vorellyn:BAAANQAECgEJAQAAAA==.',
Vu='Vuuddon:BAAANQABCgIIAgAAAA==.',
Vy='Vyce:BAAANQADCgYJBgAAAA==.',
['Và']='Vàlorie:BAAANQAECgYICgABNQAECgcICgADAAAAAA==.',
['Vè']='Vèlkhànà:BAAANQAECgYIEAAAAA==.',
Wa='Wafflesneggs:BAAANQAECgEIAQAAAA==.Wangdaulf:BAAANQADCgUIEAAAAA==.Wardoogy:BAAANQADCggICAAAAA==.Warexios:BAAANQADCgYICgAAAA==.Warglaíves:BAAANQADCgYICwABNQAECggIHAASAIkYAA==.Warradord:BAAANQAECgQJBAABNQAECgcIGAAaAMweAA==.Warsmedic:BAAANQAECgYJEAAAAA==.',
We='Wevaren:BAAANQADCgEIAQAAAA==.',
Wh='Whumha:BAAANQADCgQIBAAAAA==.',
Wi='Wilbur:BAAANQADCgQIBAAAAA==.Williams:BAEANQAECggJEwABNQAECgkJJQALACQeAA==.Williamsjr:BAEBNQAECoElAAILAAkKJB51HQAIAwALAAkKJB51HQAIAwABNQAECgkJJQALACQeAA==.Wilumi:BAAANQAECggIAQAAAA==.Winkel:BAAANQAECgIIAgAAAA==.',
Wo='Wolfyhuntres:BAAANQADCgQIBQAAAA==.Wolvesfor:BAAANQAECgIJBAAAAA==.Woopiing:BAAANQADCggIFQAAAA==.Woubbie:BAAANQABCgIIAwAAAA==.',
Wu='Wuhpow:BAAANQADCgIIAgAAAA==.Wunna:BAABNQAECoEXAAINAAgKjB+zAwDcAgANAAgKjB+zAwDcAgAAAA==.',
['Wá']='Wármonger:BAAANQADCgIIAgAAAA==.',
Xa='Xanístus:BAAANQAECgUICQAAAA==.',
Xe='Xeppa:BAAANQAECgcJEgAAAA==.',
Xi='Xionz:BAAANQAECgQJCQAAAA==.',
Ya='Yakella:BAAANQAECgUICwAAAA==.',
Ye='Yelgrun:BAAANQADCgcIEwAAAA==.Yellcat:BAABNQAECoEbAAIkAAgKCR1qDACkAgAkAAgKCR1qDACkAgAAAA==.',
Yh='Yhoda:BAABNQAECoEcAAICAAgK9RqfMwBlAgACAAgK9RqfMwBlAgAAAA==.',
Yo='Yodä:BAAANQADCgUIBQAAAA==.Youseitgar:BAAANQAECggJCwAAAA==.',
Yu='Yuisis:BAAANQAECgUIBQAAAA==.',
Za='Zabidu:BAABNQAECoEdAAIGAAkKcRveBQD8AgAGAAkKcRveBQD8AgAAAA==.Zappyketch:BAABNQAECoEbAAIVAAkK4RpGIACuAgAVAAkK4RpGIACuAgAAAA==.Zaraeiri:BAAANQADCgUIBQAAAA==.Zaraxaà:BAAANQAECgMJAwABNQAECggIIAACAK4eAA==.',
Ze='Zelenã:BAAANQAECgEIAwAAAA==.Zelun:BAABNQAECoEYAAMMAAkKIBh7JAB5AgAMAAgK/Rh7JAB5AgAVAAUKBxTxaQBWAQAAAA==.Zephon:BAABNQAECoEaAAMHAAkKHh6YCwAKAwAHAAkKnh2YCwAKAwAPAAcKkRswGwArAgAAAA==.',
Zi='Ziggley:BAAANQADCgYIBgABNQAECgYJDQADAAAAAA==.',
Zo='Zombiemarj:BAAANQADCggIIQABNQAECgQJCwADAAAAAA==.',
['Zé']='Zéd:BAAANQAECgYIEQAAAA==.',
['Âx']='Âxel:BAAANQADCgUIBQABNQAECgcIGAAHAOoeAA==.',
['Æd']='Ædisgrace:BAAANQAECgEIAgAAAA==.',
['Æm']='Æmon:BAAANQADCgQJBAAAAA==.',
['Él']='Élvira:BAAANQADCgMIAwAAAA==.',
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
