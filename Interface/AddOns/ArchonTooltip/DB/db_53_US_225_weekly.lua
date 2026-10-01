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

local lookup = {'Monk-Brewmaster','DeathKnight-Blood','Hunter-BeastMastery','Unknown-Unknown','Priest-Holy','Priest-Discipline','Monk-Mistweaver','Monk-Windwalker','DemonHunter-Havoc','Paladin-Holy','Mage-Arcane','Warlock-Demonology','Warrior-Fury','Warrior-Protection','Paladin-Protection','Warrior-Arms','Shaman-Restoration','Warlock-Destruction','DemonHunter-Devourer','Hunter-Survival','Hunter-Marksmanship','Druid-Balance','Warlock-Affliction','DemonHunter-Vengeance','Shaman-Elemental','Priest-Shadow','Evoker-Devastation','Mage-Frost','DeathKnight-Unholy','Rogue-Assassination','Rogue-Subtlety','Paladin-Retribution','Rogue-Outlaw','Evoker-Augmentation','DeathKnight-Frost','Shaman-Enhancement','Druid-Guardian','Mage-Fire','Evoker-Preservation','Druid-Restoration',}
local provider = {region='US',realm='Trollbane',name='US',type='weekly',zone=53,date='2026-09-29',data={Ac='Acroin:BAAANQADCgQIBAAAAA==.',
Ad='Adeliz:BAAANQAECgcIEgAAAA==.Adorana:BAAANQADCgQIBAAAAA==.Adrunk:BAABNQAECoEiAAIBAAgK6B7gBQC6AgABAAgK6B7gBQC6AgAAAA==.',
Ae='Aeloesh:BAAANQADCgUICAAAAA==.Aelyra:BAAANQADCgYICAAAAA==.Aenatheon:BAAANQAECgUIDAAAAA==.',
Ag='Aggrum:BAAANQAECgcIDgAAAA==.',
Ah='Ahab:BAAANQAECgIIAgAAAA==.Ahexutroll:BAAANQAECgYIDwAAAA==.',
Ai='Aidren:BAAANQAECgIIAgAAAA==.Aiur:BAAANQAECgEIAQAAAA==.',
Ak='Akredfox:BAAANQAECgYIEQAAAA==.',
Al='Alexaviah:BAAANQAECgYIEgAAAA==.Alicedelight:BAAANQAECgUIEAAAAA==.Aloldious:BAAANQAECgYIDAAAAA==.Alwaysburnt:BAAANQAECgIIAgAAAA==.Alwayscooked:BAAANQADCgIIAgAAAA==.Alwaysrolled:BAAANQABCgQIBAAAAA==.',
Am='Amabeast:BAAANQADCgUIBQAAAA==.Amanitin:BAAANQADCgQIBAAAAA==.Amisia:BAAANQAECgQIBAAAAA==.',
An='Anathas:BAABNQAECoEYAAICAAcKoiRwFQDUAgACAAcKoiRwFQDUAgAAAA==.Ancestor:BAAANQAECgUIBgAAAA==.Angelfelis:BAABNQAECoElAAIDAAkKPCPtBQCYAwADAAkKPCPtBQCYAwAAAA==.Angelgoblin:BAAANQADCgQIBQAAAA==.Angriff:BAAANQAECgUIBQAAAA==.Angrybeavor:BAAANQAECgUICgAAAA==.Anuke:BAAANQADCgcIBwAAAA==.',
Ao='Aonaar:BAAANQADCgcIEwAAAA==.',
Ar='Archdemon:BAAANQAECgcIDwAAAA==.Arkroot:BAAANQADCggIDwAAAA==.Arlock:BAAANQADCggJCAAAAA==.Arsy:BAAANQAECgMIAwABNQAECgUIBQAEAAAAAA==.Artichoke:BAAANQAECgIIAgABNQAECgQIBgAEAAAAAA==.',
As='Ashidora:BAEANQADCgYJBgABNQAECggIJQAFADAUAA==.Ashidpriest:BAEBNQAECoElAAMFAAgKMBSqSwDvAQAFAAgKMhOqSwDvAQAGAAMK1g+HEwCzAAAAAA==.Ashtoreth:BAAANQAECgMIBgAAAA==.Assukun:BAABNQAECoEhAAIHAAgKPyI1BgALAwAHAAgKPyI1BgALAwAAAA==.Async:BAAANQAECgcIDgAAAA==.',
At='Ati:BAAANQADCgYIBgAAAA==.',
Au='Aurá:BAAANQADCgIIAgAAAA==.Autoattack:BAAANQADCgcIBwAAAA==.',
Ax='Axethegrippa:BAAANQAECgUIDwABNQAFFAUICQAIADISAA==.Aximumeffort:BAAANQADCgYIBgABNQAFFAUICQAIADISAA==.',
Az='Azenservis:BAAANQADCgQIBAAAAA==.Azseera:BAAANQADCggICAAAAA==.Azuzu:BAAANQADCgUJBQAAAA==.',
Ba='Baddmojo:BAAANQADCgQIBAAAAA==.Badmac:BAABNQAECoEiAAIJAAgKvBd6JAApAgAJAAgKvBd6JAApAgAAAA==.Baelliman:BAAANQAECggICgAAAA==.Baellin:BAAANQAECgcIBwABNQAECggICgAEAAAAAA==.Baium:BAAANQAECgEIAgABNQAECgYIEgAEAAAAAA==.Bakemono:BAAANQABCgYIEgAAAA==.Bakora:BAAANQAECgEIAQAAAA==.Banishedfate:BAAANQAECgYIDgAAAA==.Banishedform:BAAANQADCgYICgABNQAECgYIDgAEAAAAAA==.Banishedholy:BAAANQADCggIDwABNQAECgYIDgAEAAAAAA==.Baozi:BAAANQAECgQIBQABNQAECgYIEwAEAAAAAA==.Barelyholy:BAABNQAECoEXAAIKAAgKxxtGJgCcAgAKAAgKxxtGJgCcAgAAAA==.Barf:BAAANQAECgEIAwABNQAECgYIEwAEAAAAAA==.Barrendar:BAAANQADCgIIAgAAAA==.Bartholamew:BAAANQADCgUIBwAAAA==.',
Be='Bearballz:BAAANQADCgIIAgAAAA==.Beardey:BAAANQADCgUIBQAAAA==.Berry:BAABNQAECoEeAAILAAgKfhxSYwCJAgALAAgKfhxSYwCJAgAAAA==.Besneakies:BAAANQAECgUIEQAAAA==.',
Bi='Bigdamfred:BAAANQADCgEIAQAAAA==.Binnford:BAAANQADCgcJFwAAAA==.',
Bl='Blackfang:BAAANQADCgUIBQABNQAECgcIDgAEAAAAAA==.Blaqball:BAAANQADCgUIDQAAAA==.Bludboil:BAAANQAECgUIBQABNQAFFAQICgAMAH8MAA==.',
Bo='Bottombish:BAAANQADCggIDAAAAA==.Boulderjaw:BAABNQAECoEWAAINAAcKSAs+DgB6AQANAAcKSAs+DgB6AQAAAA==.Bovinna:BAAANQADCgQIBAAAAA==.Boxeybrown:BAABNQAECoEVAAIOAAcKFRVOEwCUAQAOAAcKFRVOEwCUAQAAAA==.',
Br='Braised:BAABNQAECoEaAAIPAAcKjB9EDgBrAgAPAAcKjB9EDgBrAgAAAA==.Brbdeported:BAAANQAECgIIAgAAAA==.Breakadakeys:BAABNQAECoEcAAIQAAgKLhjxVgBDAgAQAAgKLhjxVgBDAgAAAA==.Breccia:BAAANQAECgMIAwAAAA==.Brutanious:BAAANQAECgIIAgABNQAECgUICwAEAAAAAA==.',
Bu='Bubbalicous:BAAANQAECggIBgAAAA==.Bubblebro:BAAANQAECgQICQAAAA==.Buffwarrior:BAAANQAECgcIEAAAAA==.Bustamoon:BAAANQADCggIDgAAAA==.Butterface:BAAANQAECgQIBgAAAA==.',
['Bà']='Bàckstabbath:BAAANQADCgMIAwAAAA==.',
Ca='Caeruleus:BAAANQADCgcIBwAAAA==.Cammikins:BAEBNQAECoEkAAIRAAkKvSBtDAA6AwARAAkKvSBtDAA6AwAAAA==.Camstelation:BAEANQADCgUIBQABNQAECgkJJAARAL0gAA==.Cantmilkem:BAAANQADCgIIAgAAAA==.Cantric:BAAANQADCgQIBAAAAA==.Capellaz:BAAANQAECgYIEgAAAA==.Capriestson:BAABNQAECoEZAAIFAAcKlyOHHADMAgAFAAcKlyOHHADMAgAAAA==.Cardib:BAAANQAECgQIBAABNQAECggIFwASAIwfAA==.Casandra:BAAANQAECgcIEAAAAA==.Cassiopeias:BAAANQADCgUIBQAAAA==.',
Ce='Celerynn:BAAANQADCgUICAAAAA==.Celestaura:BAAANQAECgUIDAAAAA==.Cenerald:BAAANQADCggICAAAAA==.Centares:BAAANQADCgYJEgAAAA==.',
Ch='Charlutes:BAAANQAECgQIBAAAAA==.Chekzy:BAAANQAECgIIAgAAAA==.Chichii:BAAANQAECgMIBAAAAA==.Chilis:BAAANQADCgcIBwABNQAECgYIEwAEAAAAAA==.Chiyuki:BAAANQADCgQJBAABNQAECgQICAAEAAAAAA==.Choasman:BAAANQADCgYIDAAAAA==.Chocolate:BAAANQADCgUJCAAAAA==.Chudpath:BAAANQAECgQIBwABNQAECgkJJgAHAEYeAA==.',
Cl='Cleome:BAAANQABCgEIAQAAAA==.',
Co='Coorsenjoyer:BAECNQAFFIEQAAICAAYKyBvdAwABAgACAAYKyBvdAwABAgA1AAQKgR4AAgIACQpYINoTAOICAAIACQpYINoTAOICAAAA.Coorslatte:BAEANQAECgYIBwABNQAFFAYIEAACAMgbAA==.Copakid:BAAANQAECgUIDgAAAA==.Cowlie:BAABNQAECoEhAAITAAgKWSMnCQAsAwATAAgKWSMnCQAsAwAAAA==.Coøkiewizard:BAAANQADCgEIAQAAAA==.',
Cr='Crippy:BAAANQAECgcIEQABNQADCgIIAgAEAAAAAA==.Crippypal:BAAANQAECgUICQABNQADCgIIAgAEAAAAAA==.Crippyx:BAAANQADCgIIAgAAAA==.Crowls:BAAANQADCgMIAwABNQAECggIIQATAFkjAA==.Cruelwar:BAAANQAECgYIDQAAAA==.',
Cu='Cuckcmder:BAAANQAECgYIEwAAAA==.',
Da='Daffodil:BAAANQADCgEIAQAAAA==.Daggoth:BAABNQAECoEaAAIJAAgKJiI2DwD2AgAJAAgKJiI2DwD2AgAAAA==.Dalrak:BAABNQAECoEjAAQUAAgKJyNgAQBAAwAUAAgKJyNgAQBAAwAVAAQKgxj4PgDyAAADAAIK4Bng8gCOAAAAAA==.Dandarth:BAAANQADCgMIAwAAAA==.Danemos:BAAANQADCgMIAwABNQAFFAQICgAMAH8MAA==.Dante:BAAANQAECgQIBAABNQAECggIGgADAGEXAA==.Darkendelf:BAAANQAECgQIBQAAAA==.Darkothy:BAAANQAECgUIDAAAAA==.Darkvision:BAAANQAECgEIAQAAAA==.Darthroy:BAAANQADCgIIAgAAAA==.Dasdann:BAAANQADCgUIBQAAAA==.Datshammy:BAAANQADCgUIBQAAAA==.Datvoodoomon:BAABNQAECoEmAAIWAAkK6R9cCwBYAwAWAAkK6R9cCwBYAwAAAA==.Daïn:BAAANQAECgcIEwAAAA==.',
Dc='Dcaý:BAAANQAECgUIBgAAAA==.',
De='Deadboii:BAAANQAECgEJAQAAAA==.Deadjuggalo:BAAANQAECgEIAQAAAA==.Deadlyfaith:BAAANQADCgYIEgAAAA==.Deadstep:BAAANQAECgUIDAAAAA==.Deathzy:BAAANQADCgIIAgAAAA==.Deitzz:BAAANQADCgQIBAAAAA==.Deleralia:BAAANQAECgcIEgAAAA==.Demontopher:BAABNQAECoEcAAIXAAkKNiYkAADbAwAXAAkKNiYkAADbAwAAAA==.Derodrayne:BAAANQADCgYIBwAAAA==.Deshaler:BAAANQADCgcIBwAAAA==.Devoidshield:BAAANQAECgIIAgAAAA==.',
Di='Dicon:BAAANQADCgYIBgAAAA==.Dieric:BAAANQAECgUIDQAAAA==.Dinkle:BAAANQADCgMJAwABNQAECgcIDwAEAAAAAA==.Dividian:BAABNQAECoEaAAMDAAgKYRcOPwBmAgADAAgKYRcOPwBmAgAUAAQKywZ2CwDJAAAAAA==.Dizana:BAAANQAECgEIAQABNQAECgcIEgAEAAAAAA==.',
Do='Dorastrain:BAABNQAECoEfAAIYAAgKtSVOAQB7AwAYAAgKtSVOAQB7AwAAAA==.',
Dr='Dracovoid:BAAANQAECgQIBgABNQAECgUICgAEAAAAAA==.Dragondees:BAAANQAECgUIBgAAAA==.Dragonwyck:BAAANQAECgQICgAAAA==.Draytheus:BAAANQAECgUICwAAAA==.Drganon:BAAANQAECgYICwAAAA==.Dripping:BAAANQAECgQICAAAAA==.Dromai:BAAANQADCgYICAAAAA==.',
Du='Duhdotsbruh:BAAANQAECgQIBAAAAA==.Duraf:BAAANQADCgcICQAAAA==.Duugan:BAAANQADCgQIBAAAAA==.',
Ed='Edgarj:BAAANQADCgEIAQAAAA==.',
Ek='Eklipsch:BAAANQADCggIDwAAAA==.',
El='Eld:BAAANQABCgYIBwAAAA==.Electrocute:BAAANQADCgMIAwAAAA==.Electrocutey:BAAANQAECgYIEgAAAA==.Elein:BAAANQADCgEIAQAAAA==.Eleman:BAAANQAECgEIAQAAAA==.Elfclover:BAABNQAECoEXAAIVAAcKUxW0KQCuAQAVAAcKUxW0KQCuAQAAAA==.Elijahx:BAAANQAECgcIEgAAAA==.Elijay:BAAANQAECgUICAAAAA==.Eljayye:BAAANQADCgcJFwAAAA==.',
Em='Emisha:BAAANQADCgIIAgAAAA==.Emmshunter:BAAANQAFFAIIAgAAAA==.',
En='Entropy:BAAANQAECgEIAQAAAA==.Envi:BAAANQAECgIIBAAAAA==.',
Ep='Epicdemise:BAAANQADCggIEAAAAA==.Epicdemon:BAAANQADCggIFAAAAA==.Epicwarlock:BAAANQADCggIFQAAAA==.Epona:BAABNQAECoEgAAMRAAcK5hObXQCgAQARAAcK5hObXQCgAQAZAAEKfwHAGwEdAAAAAA==.',
Er='Erzá:BAAANQAECgUIEAAAAA==.',
Es='Espina:BAAANQADCgUIBQAAAA==.',
Et='Eterna:BAAANQAECgUIDAAAAA==.',
Ev='Ev:BAAANQAECgIIAgAAAA==.Eveilyn:BAAANQAECgcIDAAAAA==.Evilerno:BAAANQAECgIIAQAAAA==.Evileye:BAAANQADCgYIBgAAAA==.Evylenna:BAAANQAECgUIBQAAAA==.',
Ex='Exarchamus:BAABNQAECoEZAAIQAAgK/BGJawADAgAQAAgK/BGJawADAgAAAA==.',
Fa='Facemelt:BAABNQAECoEfAAIaAAgKIx7rDwDBAgAaAAgKIx7rDwDBAgAAAA==.Farfy:BAABNQAECoEhAAICAAgKwBqwHgCHAgACAAgKwBqwHgCHAgAAAA==.Fartsmagoo:BAAANQAECgYICwAAAA==.Faykan:BAAANQAECgUIEQAAAA==.',
Fe='Fedrameda:BAABNQAECoEXAAIDAAgKPhd7RQBRAgADAAgKPhd7RQBRAgAAAA==.Felix:BAAANQAECgYIEwAAAA==.Fellender:BAAANQADCggIPgAAAA==.Fermented:BAABNQAECoEYAAICAAgKahbUMQAHAgACAAgKahbUMQAHAgAAAA==.',
Fi='Fixwarplz:BAAANQAECgEIAQAAAA==.Fizzle:BAAANQADCgQIBgAAAA==.',
Fl='Flintstones:BAABNQAECoEhAAIWAAkK0BnJHgChAgAWAAkK0BnJHgChAgAAAA==.Fluffykiitty:BAAANQADCgEIAQAAAA==.Flyinglizard:BAAANQADCggICAAAAA==.',
Fo='Fowlplay:BAAANQAECgEIAQAAAA==.Foxbox:BAAANQAECgQIBQAAAA==.',
Fr='Frostedhoof:BAAANQADCggICAABNQAFFAIIBQAVAJ8TAA==.',
Fu='Fujee:BAABNQAECoEZAAMVAAcKdB+OGABhAgAVAAcKQR6OGABhAgADAAQKwB1AvAAeAQAAAA==.Funkyt:BAAANQAECgUICgAAAA==.Furrysona:BAAANQAECgEIAQABNQAECgkJJgAbAIcXAA==.',
['Fâ']='Fâlooga:BAAANQAECgYIEwAAAA==.',
Ga='Gaidine:BAAANQADCgMJAwAAAA==.Galadriael:BAABNQAECoEXAAMcAAgK0x1+EgA+AQALAAgKjhp0hAA5AgAcAAQKuB5+EgA+AQAAAA==.Galtan:BAAANQAECgQIBwAAAA==.Gandoch:BAAANQADCgQIBAAAAA==.Garrod:BAAANQAECgcIEQAAAA==.Gasionaldo:BAAANQAECgEIAQAAAA==.Gattsu:BAAANQAECgIIAgAAAA==.',
Ge='Gennil:BAABNQAECoEnAAMcAAkKkiSUAACsAwAcAAkKkiSUAACsAwALAAEKphT9gwE9AAAAAA==.Gestella:BAAANQAECgUIDgAAAA==.Gevo:BAABNQAECoEYAAIQAAgK2RWxYgAdAgAQAAgK2RWxYgAdAgAAAA==.',
Gi='Gineselle:BAAANQAECgIIAwAAAA==.Giveemhail:BAAANQADCgMIAwABNQAECgkJGAAdAF8UAA==.',
Gl='Gloomblade:BAACNQAFFIELAAMeAAUKPRcBAwC4AQAeAAUK/hYBAwC4AQAfAAIKlxstCgC1AAA1AAQKgSAAAx8ACQo6H8sIANQCAB8ACQobHcsIANQCAB4ABApNHn85AGsBAAAA.',
Gn='Gnomepimp:BAAANQADCgYIBgABNQAECgUIBgAEAAAAAA==.',
Go='Gojìra:BAAANQAECgUICwAAAA==.Goragaia:BAAANQAECgYIDwAAAA==.Gorbencleap:BAAANQABCgMIAwAAAA==.Gorion:BAAANQADCgQIBAAAAA==.',
Gr='Graypelt:BAAANQADCggIDwAAAA==.Grayscale:BAAANQADCgYIDAAAAA==.Greyseer:BAAANQAECgUIBwAAAA==.Grica:BAAANQADCgEIAQAAAA==.Gripsworth:BAAANQAECgQIBAABNQAECggJGQAHAOgXAA==.Gryphonheart:BAAANQADCgQIBAAAAA==.',
Gu='Guymontag:BAABNQAECoEgAAQgAAgKoh7uUwBIAgAgAAcKix/uUwBIAgAKAAUK6xdncQBxAQAPAAMK2hXhPQCtAAAAAA==.',
Ha='Hammergobrr:BAAANQABCgQIBAAAAA==.Harbard:BAABNQAECoEaAAIDAAgKqhj1RgBMAgADAAgKqhj1RgBMAgAAAA==.Hasselhøøf:BAAANQAECgcJEgAAAA==.Hawkeyeik:BAAANQAECgYIDwAAAA==.Hawthorne:BAABNQAECoEZAAIbAAgKChSvDwAjAgAbAAgKChSvDwAjAgAAAA==.Hayywaffle:BAAANQADCggIDAAAAA==.',
He='Heilwelle:BAAANQADCgcIBwAAAA==.Hellothere:BAABNQAECoEZAAMgAAcKcyYYIgAKAwAgAAcKcyYYIgAKAwAPAAEKOQyAWgArAAAAAA==.Hellren:BAAANQAECgEIAQAAAA==.Helmet:BAAANQADCgQIBAAAAA==.',
Hi='Hikons:BAABNQAECoEaAAIKAAgKmgpqXwCtAQAKAAgKmgpqXwCtAQAAAA==.Hinkle:BAAANQAECgUICwABNQAECgcIDwAEAAAAAA==.',
Ho='Hobojoe:BAAANQAECgYIDQAAAA==.Holyclover:BAAANQAECgEIAQAAAA==.Holysage:BAAANQADCgcIBwAAAA==.Holytoad:BAAANQADCgYIBgAAAA==.Hopsquash:BAAANQADCgQIBAAAAA==.Hopstop:BAAANQAECgYIEgAAAA==.',
Hu='Hughass:BAAANQADCgYIFQABNQAECgMIBQAEAAAAAA==.Hugo:BAABNQAECoEZAAIgAAYKURYblwCIAQAgAAYKURYblwCIAQAAAA==.Hukkash:BAAANQABCgMIAwAAAA==.Hullr:BAAANQAECgQIBgAAAA==.Huwglyndur:BAAANQAECgYIEgAAAA==.',
Hy='Hyperiunpala:BAAANQAECgYIDwAAAA==.',
Ia='Iari:BAAANQADCggIDgAAAA==.',
Id='Idispizhorde:BAABNQAECoEfAAIdAAkK8RaEJABhAgAdAAkK8RaEJABhAgAAAA==.',
Ig='Igris:BAABNQAECoEYAAIQAAgK8RYmXgAsAgAQAAgK8RYmXgAsAgAAAA==.',
Il='Illihottie:BAAANQADCgQIBAAAAA==.Illiora:BAAANQADCgYIBQABNQAECggIQAARABseAA==.Illissia:BAAANQAECgIIAgAAAA==.',
Im='Imós:BAAANQADCgcICAAAAA==.',
Ir='Ironbrew:BAAANQAECgEIAQAAAA==.Ironpreacher:BAAANQADCgYIDQAAAA==.Ironspite:BAAANQADCggIDQAAAA==.',
Is='Ish:BAABNQAECoElAAIaAAkKrh1PDQDpAgAaAAkKrh1PDQDpAgAAAA==.Ishibad:BAAANQAECgIIAwABNQAECgkJJQAaAK4dAA==.Isolie:BAAANQAECgEIAQAAAA==.Isongard:BAAANQABCgIIAgAAAA==.',
It='Itsthesham:BAAANQAECgQIBQABNQAECggIGgAIAN8cAA==.',
Iv='Ivok:BAAANQADCggIFwAAAA==.',
Iy='Iyooni:BAAANQABCgQIBAAAAA==.',
Ja='Jatbez:BAAANQADCgMIBQAAAA==.Jaykay:BAAANQADCgcJCgAAAA==.Jazmìne:BAAANQADCggJHgAAAA==.',
Je='Jessa:BAAANQAECgcIDAAAAA==.Jezuz:BAAANQAECgYIEAAAAA==.',
Ji='Jimbadd:BAAANQAECgQIBAAAAA==.Jimmieslock:BAACNQAFFIETAAQMAAYKAiE3AwD8AQAMAAUKIyA3AwD8AQASAAEKnCQDDwBvAAAXAAEKEianAwBvAAA1AAQKgRoAAwwACQpfJoIOADUDAAwACArnJYIOADUDABIABwoCJMIGAIwCAAAA.Jimmiespala:BAAANQAECgIIAgABNQAFFAYIEwAMAAIhAA==.',
Jk='Jkils:BAAANQADCggIEQAAAA==.',
Jo='Jonbaptist:BAAANQAECgYIDAAAAA==.Jonile:BAAANQADCgQIBQAAAA==.Joyfulflame:BAAANQAECgIIAgABNQAECgYIEgAEAAAAAA==.',
Jt='Jtrain:BAAANQAECgUIDgAAAA==.',
Ju='Judwin:BAABNQAECoEXAAMeAAgK1SEHCQAZAwAeAAgK1SEHCQAZAwAhAAIKmxapEwCAAAAAAA==.',
['Jä']='Jäzmine:BAAANQADCgIIAgAAAA==.',
['Jè']='Jèssicà:BAABNQAECoEkAAIDAAgKVyCfJADLAgADAAgKVyCfJADLAgAAAA==.',
['Jô']='Jôseph:BAAANQADCgUIBgAAAA==.',
['Jö']='Jöe:BAAANQADCgIIAgAAAA==.',
Ka='Kaalin:BAAANQADCgIJAgAAAA==.Kabutosan:BAAANQAECgEIAQABNQAFFAQICgAMAH8MAA==.Kail:BAAANQADCgQIBAAAAA==.Kaleesi:BAAANQADCgcIEAAAAA==.Kamots:BAAANQAECgcIEQAAAA==.Kareokee:BAABNQAECoEeAAINAAgKPQ3FCgDOAQANAAgKPQ3FCgDOAQAAAA==.Kargoroth:BAABNQAECoEiAAIZAAkKzB14HwDbAgAZAAkKzB14HwDbAgAAAA==.Karnaga:BAAANQABCgcJCgAAAA==.Karral:BAABNQAECoEjAAMDAAkKLCEdDgBMAwADAAkKLCEdDgBMAwAUAAEK1BdjDgBJAAAAAA==.Katerzv:BAAANQADCgMIBAAAAA==.Kazdormu:BAABNQAECoElAAMbAAkKfhZ1CwCCAgAbAAkKfhZ1CwCCAgAiAAEKVxDHHQAsAAAAAA==.',
Kc='Kchaos:BAAANQADCgcIBwAAAA==.',
Ke='Kedira:BAAANQADCggIEAABNQAECgkJQgAjAAklAA==.Keloth:BAAANQADCgQIBAABNQAECgQIBAAEAAAAAA==.Keyztone:BAAANQAECggIAgAAAA==.',
Kh='Khadriel:BAABNQAECoEYAAITAAcKNQ8LKgCzAQATAAcKNQ8LKgCzAQAAAA==.',
Ki='Killinrapidy:BAAANQADCgUJCQAAAA==.Kitani:BAABNQAECoEtAAIOAAkKPCPeAQCDAwAOAAkKPCPeAQCDAwAAAA==.',
Kn='Knottybits:BAAANQAECgMIBAAAAA==.',
Ko='Konsumer:BAAANQADCgQJBAABNQAECgUIBgAEAAAAAA==.Kontakt:BAAANQADCgcIDgAAAA==.Konân:BAABNQAECoEYAAIkAAcK3hy3DQBSAgAkAAcK3hy3DQBSAgAAAA==.Kordim:BAAANQAECgQIDAABNQAECgcIIAAlAGoRAA==.Korvakh:BAAANQAECgEIAQAAAA==.',
Kr='Kraduun:BAAANQAECgYIEQAAAA==.Krantly:BAAANQADCggIFwAAAA==.Krenaele:BAAANQADCgYIBgAAAA==.Krenniellin:BAAANQAECgUJDwAAAA==.Krys:BAAANQAECgYIDAAAAA==.',
La='Laev:BAEANQADCggICAABNQAECggIJQAFADAUAA==.Lairbear:BAAANQADCgYICwAAAA==.Lambadin:BAAANQADCgQIBAAAAA==.Lanadelrey:BAAANQAECgQIBAAAAA==.Lanaru:BAAANQADCggIFQABNQAECgUIEAAEAAAAAA==.Lavi:BAAANQAECgUICQAAAA==.',
Le='Leizil:BAABNQAECoEhAAIFAAgKDRMEQwATAgAFAAgKDRMEQwATAgAAAA==.Lennox:BAAANQAECgYIEwAAAA==.Lesaire:BAAANQAECgIJAgAAAA==.Letara:BAAANQADCgYIBgAAAA==.Lextor:BAAANQADCgQIBQAAAA==.',
Lh='Lhuani:BAACNQAFFIEFAAILAAIKqB5SKwC5AAALAAIKqB5SKwC5AAA1AAQKgSwABAsACQrLHxwqACQDAAsACQqoHxwqACQDACYABAroGRMEAEIBABwAAgoaFvIjAIsAAAAA.',
Li='Liaelina:BAEANQAECgYIEgAAAA==.Lichte:BAAANQABCgMIAwAAAA==.Lightmyhole:BAAANQADCgEJAQABNQAFFAIIAgAEAAAAAA==.Like:BAAANQADCgUIBQAAAA==.Lilyachty:BAAANQADCgUICgABNQAECggIFwASAIwfAA==.Lilíth:BAAANQAECgcIBwABNQAECgcIEAAEAAAAAA==.Lindbergh:BAAANQAECgQIBAABNQAECgQIBgAEAAAAAA==.Linshe:BAABNQAECoEaAAILAAcKtQ6LwACzAQALAAcKtQ6LwACzAQAAAA==.Lizzie:BAAANQADCgUIBQAAAA==.',
Ll='Llillianna:BAAANQAECgQICAAAAA==.',
Lo='Loosey:BAAANQABCgYIBgAAAA==.Lorm:BAAANQADCgQIBQAAAA==.Lostdream:BAAANQADCgMIAwAAAA==.',
Lu='Lucarien:BAAANQAECgMIBQAAAA==.Lustyglory:BAAANQADCggICAAAAA==.',
Ma='Macareios:BAAANQADCgUIBQAAAA==.Madeintyø:BAAANQAECgQIBQABNQAECggIFwASAIwfAA==.Maelos:BAAANQAECgIIAgAAAA==.Mageaga:BAAANQADCgYICwAAAA==.Magnathul:BAABNQAECoEaAAIdAAgKIBk7KwAyAgAdAAgKIBk7KwAyAgAAAA==.Magnumdruid:BAAANQADCgQJBAAAAA==.Makeah:BAABNQAECoElAAIDAAgK5iOdFQAZAwADAAgK5iOdFQAZAwAAAA==.Makhamou:BAAANQAECgYIEAAAAA==.Malak:BAAANQAECgQJCgAAAA==.Malinstur:BAABNQAECoEaAAIdAAgK+AioTQB2AQAdAAgK+AioTQB2AQAAAA==.Malted:BAAANQAECgEIAQAAAA==.Marianne:BAAANQADCgcIBwAAAA==.Marjorye:BAAANQAECgUIEAAAAA==.Marnaught:BAAANQAECgEJAQABNQAECgMIBAAEAAAAAA==.Marsy:BAAANQAECgUIBQAAAA==.Marzánna:BAAANQADCgQIBwABNQAECgYIEAAEAAAAAA==.Mashed:BAAANQADCgYICwABNQAECgUIBQAEAAAAAA==.Matts:BAAANQAECgEIAwAAAA==.Mausi:BAAANQADCgQIBAABNQAECgIIAgAEAAAAAA==.Maxxamus:BAAANQAECgEIAQAAAA==.Mazaal:BAABNQAECoEmAAIjAAkKuCTxAgCgAwAjAAkKuCTxAgCgAwAAAA==.',
Mc='Mcshaft:BAAANQABCgQIBQAAAA==.',
Me='Meatmuskett:BAAANQADCggICAAAAA==.Mekeena:BAAANQAECgYIEAAAAA==.Melesandre:BAAANQAECgEIAQAAAA==.Melinee:BAAANQADCgcICQAAAA==.Mellinda:BAAANQAECgIIBAAAAA==.Melzas:BAAANQAECgUICwAAAA==.',
Mi='Midrok:BAABNQAECoEgAAIlAAcKahHTFQCCAQAlAAcKahHTFQCCAQAAAA==.Mikåh:BAAANQADCggIFAAAAA==.Milkjugzz:BAAANQADCgQIBAAAAA==.Miselah:BAAANQADCgQIBQAAAA==.Missyennefer:BAAANQADCgcIEgAAAA==.',
Mm='Mmbhpta:BAAANQAECgMIAwABNQAECggIFwASAIwfAA==.',
Mo='Mobythicc:BAAANQADCgcICQABNQAFFAUICQAIADISAA==.Mondai:BAAANQABCgQIBAAAAA==.Monkpowahh:BAAANQADCgEIAQABNQAECgUIDQAEAAAAAA==.Montag:BAAANQADCggIDgABNQAECggIIAAgAKIeAA==.Moonboomfred:BAAANQADCgMIAwAAAA==.Moonshower:BAABNQAECoEZAAIFAAgKAR+ZIQCwAgAFAAgKAR+ZIQCwAgAAAA==.Mooranda:BAAANQABCggIDgAAAA==.Moraear:BAAANQADCgIJAgAAAA==.Morgaenei:BAAANQABCgMIAwAAAA==.',
Mt='Mtastyck:BAAANQAECgIIAgAAAA==.',
Mu='Mudsniffer:BAAANQAECgUIDQAAAA==.Multitool:BAEBNQAECoEhAAIPAAgKViMMBgAdAwAPAAgKViMMBgAdAwAAAA==.Mundekk:BAAANQAECgQICwAAAA==.',
My='Mylo:BAAANQAECgEIAQAAAA==.Myobûky:BAAANQADCgUIBQAAAA==.Mystiecub:BAAANQABCgIJAQAAAA==.Mythgleam:BAAANQAECgIJAgAAAA==.Mythsol:BAAANQAECgEIAQAAAA==.Myththistle:BAAANQADCgEIAQAAAA==.',
['Má']='Mániac:BAAANQADCgcIDAAAAA==.',
Na='Nack:BAAANQADCgcICQABNQAECggIEwAEAAAAAA==.Nacks:BAAANQAECggIEwAAAA==.Nacksd:BAAANQADCgEIAQABNQAECggIEwAEAAAAAA==.Nacksly:BAAANQAECgIIAgABNQAECggIEwAEAAAAAA==.Nacksm:BAAANQADCggICAABNQAECggIEwAEAAAAAA==.Nacksp:BAAANQADCgUIBQABNQAECggIEwAEAAAAAA==.Naelandra:BAAANQADCgQJBAABNQAECggIIAAgAKIeAA==.Naliön:BAAANQADCggIFAAAAA==.Naotsugu:BAAANQAECgEIAQAAAA==.Nargacuga:BAAANQAECgEIAQABNQAECggIFgALAGgfAA==.Nasarden:BAAANQAECgMIBAAAAA==.Nasir:BAAANQAECgEIAQAAAA==.Nastysage:BAAANQAECgUIDgAAAA==.Nastyxxnate:BAAANQADCggIDAAAAA==.Natric:BAAANQAECgEIAgAAAA==.Naxdh:BAAANQADCggIDAABNQAECggIEwAEAAAAAA==.',
Ne='Nechanion:BAAANQADCggJEAAAAA==.Nessië:BAAANQAECgUIDgAAAA==.Nesthor:BAAANQADCgYIBgAAAA==.',
Ni='Nicodh:BAAANQAECgIIAgAAAA==.Nimibear:BAAANQAECgIIAgAAAA==.Nimidk:BAABNQAECoEcAAICAAkKhB0TGAC8AgACAAkKhB0TGAC8AgAAAA==.Ninjahealer:BAAANQAECgMIBAAAAA==.',
No='Noobtotem:BAAANQADCgYICwABNQAECggIFwAKAMcbAA==.Nooffensë:BAEANQADCgcJDAABNQAECgYIEgAEAAAAAA==.',
Nu='Nugsmasher:BAAANQADCgYIEQAAAA==.Nutdevourer:BAABNQAECoEhAAITAAcKpx1tFgB+AgATAAcKpx1tFgB+AgAAAA==.',
['Né']='Néther:BAAANQADCgcICAAAAA==.',
Oa='Oakelvin:BAAANQAECgcJDgAAAA==.',
Ob='Obnoxiousego:BAAANQAECgcIEgAAAA==.',
Od='Odartherogue:BAAANQADCgUIBAAAAA==.Oddknee:BAACNQAFFIEFAAMVAAIKnxN8FgCEAAAVAAIKSw98FgCEAAADAAEKGQrJJwBLAAA1AAQKgS0AAxUACQqNIecFAF0DABUACQqNIecFAF0DAAMAAQr+F1YIAVAAAAAA.Odney:BAAANQAECgUIDQABNQAFFAIIBQAVAJ8TAA==.',
On='Onaria:BAAANQAECgcICwABNQAECggIQAARABseAA==.',
Or='Oridox:BAABNQAECoEbAAIlAAcKPCEgCACUAgAlAAcKPCEgCACUAgAAAA==.Orumine:BAABNQAECoEsAAIgAAkKwyC6GQA1AwAgAAkKwyC6GQA1AwAAAA==.',
Ov='Overhere:BAAANQAECgEIAQABNQAECgUIDQAEAAAAAA==.',
Pa='Pahpi:BAAANQAECggIBgAAAA==.Palcan:BAAANQAECgMIAwAAAA==.Papii:BAAANQAECggIBQAAAA==.Paratussum:BAAANQADCgYIBgAAAA==.Parka:BAABNQAECoEjAAIjAAkKJCP1AgCfAwAjAAkKJCP1AgCfAwAAAA==.Pattysmash:BAAANQAECgYICwABNQAFFAUICgARAMAUAA==.',
Pb='Pbody:BAAANQAECgcIEgAAAA==.',
Pe='Perhorn:BAAANQAECgMIBAAAAA==.',
Po='Pollywog:BAAANQADCgcIBwABNQAECgQIBgAEAAAAAA==.Polunocnicá:BAAANQAECgYIEAAAAA==.Pooj:BAAANQADCggIFwAAAA==.',
Pr='Primehunter:BAAANQAFFAEIAQAAAA==.Primetime:BAAANQAECgUICgAAAA==.Prissila:BAAANQADCgYJDwAAAA==.Prollimix:BAAANQAECgIIBQAAAA==.',
Ps='Psychoshorts:BAAANQAECgYIEwAAAA==.Psykick:BAAANQADCgEIAQAAAA==.',
Py='Pyropoint:BAAANQAECgYICgAAAA==.',
Ra='Rachela:BAAANQAECgEIAgAAAA==.Ractiel:BAAANQADCgYIEwAAAA==.Raidhero:BAAANQAECgMIBAAAAA==.Rain:BAAANQAECgQIBAAAAA==.Raked:BAAANQAECgUIEgAAAA==.Ranfna:BAAANQADCggICQAAAA==.Rapidkiill:BAAANQADCgQICQAAAA==.Rapidly:BAAANQADCgUJBQAAAA==.Raspberrytea:BAAANQABCggIFQAAAA==.Raviolio:BAAANQAECgMIAwABNQAECgMIBQAEAAAAAA==.',
Re='Reebz:BAAANQADCgYJBwABNQADCgIIAgAEAAAAAA==.Reflection:BAABNQAECoEbAAIFAAgK3weQZACMAQAFAAgK3weQZACMAQAAAA==.Rekcutnerd:BAAANQAECgEIAgAAAA==.Reloran:BAAANQABCgIIAgAAAA==.Reppa:BAAANQADCggICAAAAA==.Retiniris:BAABNQAECoEfAAMDAAcKQCG4MgCSAgADAAcKQCG4MgCSAgAVAAEKDQO2dgAoAAAAAA==.',
Rh='Rhonstaris:BAAANQAECgQIBgAAAA==.Rhylintras:BAAANQADCgQIBwABNQAECgYIEAAEAAAAAA==.',
Ri='Riceporridge:BAAANQAECgYIEwAAAA==.Rinari:BAAANQAECgQIBQABNQAECggIQAARABseAA==.Riptakeoff:BAAANQADCgcIBwABNQAECggIFwASAIwfAA==.Riskofrain:BAAANQAECgQIBQAAAA==.Ritzcarltina:BAAANQADCgQJBAAAAA==.Ritzu:BAAANQADCggICAABNQAECgQIBgAEAAAAAA==.',
Ro='Rockemi:BAAANQABCgMIAwAAAA==.Rodo:BAAANQADCgcIDQAAAA==.Roxyviper:BAAANQAECgQIDQAAAA==.Royalfox:BAABNQAECoEaAAIBAAgKNwlUEwBoAQABAAgKNwlUEwBoAQAAAA==.',
Ru='Rubbish:BAAANQAECgEIAQAAAA==.',
Sa='Saatari:BAAANQAECgEJAQAAAA==.Saddeath:BAAANQADCgYIBgAAAA==.Saeylaura:BAAANQADCggIEwAAAA==.Saintchuck:BAAANQAECgIIAgAAAA==.Sainted:BAAANQADCggIEQAAAA==.Salanaar:BAABNQAECoEmAAICAAkK+SAECQBVAwACAAkK+SAECQBVAwAAAA==.Salarix:BAAANQAECgMIBAAAAA==.Sanarian:BAAANQADCgUIBQAAAA==.Sarja:BAAANQAECgUIDAAAAA==.Sarras:BAAANQADCggIFgAAAA==.Sasserfrass:BAAANQAECgYIEAAAAA==.Savaant:BAAANQADCgIIAgAAAA==.Sayy:BAABNQAECoEbAAMLAAgKZRrgbwBqAgALAAgKZRrgbwBqAgAcAAQKZxL6GgDVAAAAAA==.',
Sc='Scaledrage:BAAANQAECgcIDgAAAA==.Schism:BAEANQAECgYIEAABNQADCggIFQAEAAAAAA==.',
Se='Seaotter:BAABNQAECoEcAAIdAAgKQRJCPQDGAQAdAAgKQRJCPQDGAQAAAA==.Sellioni:BAAANQAECgUIBQABNQAECggIFgALAGgfAA==.Senhonrue:BAAANQAECgEIAQAAAA==.Serabian:BAAANQADCgUIBQAAAA==.Seraz:BAABNQAECoEkAAInAAkKQRutCQDpAgAnAAkKQRutCQDpAgAAAA==.Seregios:BAAANQAECgQIBAABNQAECggIFgALAGgfAA==.Serenitey:BAAANQADCgcJFwAAAA==.Serraglyndur:BAAANQAECgYIEgAAAA==.',
Sh='Shaderaina:BAAANQADCggIGQAAAA==.Shadowgame:BAAANQADCgQIBAAAAA==.Shadowglowz:BAAANQADCgEIAQAAAA==.Shambe:BAAANQADCgIIAgAAAA==.Shamidzi:BAAANQADCgQIBQAAAA==.Shamzuh:BAAANQADCgUIAwAAAA==.Sheabutters:BAAANQAECgcIDwAAAA==.Shennequa:BAAANQABCgUIBQAAAA==.Shmorg:BAAANQAECgMIBQAAAA==.Shunaiman:BAAANQAECgYIEgAAAA==.Shàdowdànce:BAAANQADCgUIBwAAAA==.Shábam:BAAANQAECgUIBgAAAA==.',
Si='Sifferr:BAAANQAECgUICwAAAA==.Sijinn:BAAANQADCgYIDAAAAA==.Silus:BAAANQAECgQIBAAAAA==.',
Sk='Skezes:BAAANQADCgYIBgAAAA==.Skotom:BAAANQAECgEIAQAAAA==.Skyjericho:BAAANQAECgMIBgAAAA==.',
Sl='Slann:BAAANQAECgYICgAAAA==.Slattpal:BAABNQAECoEbAAIKAAkKcSE0CQBjAwAKAAkKcSE0CQBjAwAAAA==.Sleebydruid:BAAANQAECggIDwAAAA==.Sleebyevoker:BAAANQAECgYIEgABNQAECggIDwAEAAAAAA==.',
Sm='Smurghl:BAAANQAECgQIBAAAAA==.',
Sn='Snackysteak:BAAANQADCgYIBgAAAA==.',
So='Socinks:BAAANQADCgcIBwAAAA==.Solistome:BAAANQADCgcJEQAAAA==.Somarlar:BAAANQADCgMIAwAAAA==.Sopho:BAAANQAECgYIDAAAAA==.Sophogue:BAAANQADCgUIBQABNQAECgYIDAAEAAAAAA==.Sophomage:BAAANQADCgYJBgABNQAECgYIDAAEAAAAAA==.',
Sp='Specialtea:BAAANQAECgIIAgAAAA==.Spider:BAAANQADCgMIBAAAAA==.',
Sq='Squam:BAAANQADCgcIBwABNQAECggIHgALAH4cAA==.',
St='Starzpapi:BAAANQABCgIIAgABNQAECggIFwASAIwfAA==.Stonebones:BAAANQAECgYIBgAAAA==.Strappy:BAAANQADCgcIBwAAAA==.Stwife:BAACNQAFFIEKAAQdAAUKIgyeCAALAQAdAAQKuAmeCAALAQAjAAEKWxxUEgBTAAACAAEKiA0AKAApAAA1AAQKgSIAAx0ACQrJGvceAIkCAB0ACQrFGfceAIkCACMABAoZFEtRAOYAAAAA.Störmë:BAAANQADCgUICQAAAA==.',
Su='Sufrucia:BAAANQAECgcIEgAAAA==.Sunday:BAAANQAECgYIDgAAAA==.Sunhime:BAAANQAECgEIAQABNQAECgcIDgAEAAAAAA==.Surâ:BAAANQAECgcIEwAAAA==.',
Sy='Symbol:BAAANQAECgcJEgABNQAECggIHgALAH4cAA==.Sympissal:BAAANQAECgEIAQAAAA==.',
['Sò']='Sònya:BAABNQAECoEdAAIZAAgK7Q8sUwDcAQAZAAgK7Q8sUwDcAQAAAA==.',
['Sÿ']='Sÿlvanas:BAAANQAECgIIAwAAAA==.',
Ta='Tabhunter:BAAANQADCgcJDAAAAA==.Tagritalth:BAAANQAECgEIAQABNQABCgMIAwAEAAAAAA==.Taindnddra:BAAANQADCgEIAQABNQAECgUIBgAEAAAAAA==.Talanas:BAAANQADCggIBQAAAA==.Tanishalfelf:BAACNQAFFIENAAMgAAUKYB3aCABSAQAgAAMKJSbaCABSAQAKAAIKrgQbGACNAAA1AAQKgSYAAyAACQrqJvcBAOoDACAACQrqJvcBAOoDAAoACAriE1g8ADMCAAAA.Tankaman:BAAANQADCgQIDQABNQAECgQICQAEAAAAAA==.',
Te='Tegalia:BAAANQAECgEIAQAAAA==.Telliah:BAAANQABCgEJAQAAAA==.Tempestre:BAAANQADCgMIAwAAAA==.Terrorfury:BAAANQADCgUICQAAAA==.Texoutlaw:BAAANQAECgEIAQAAAA==.',
Th='Thalassikos:BAAANQAECgEIAQABNQAECgQIBgAEAAAAAA==.Thatredhead:BAAANQADCgQJBAAAAA==.Thegremlin:BAAANQAECgIIBAAAAA==.Thewraith:BAAANQAECgEIAQAAAA==.Thorcised:BAABNQAECoEfAAICAAgKmxTbNQDzAQACAAgKmxTbNQDzAQAAAA==.Thorin:BAAANQAECgYIEgAAAA==.Thorym:BAAANQADCgUIBQABNQAECggIGQAWAC4dAA==.Thoryndir:BAABNQAECoEZAAIWAAgKLh3BHACyAgAWAAgKLh3BHACyAgAAAA==.Thrym:BAABNQAECoEcAAIjAAgKRx+qEADPAgAjAAgKRx+qEADPAgAAAA==.Thundernut:BAAANQADCggIEAAAAA==.',
Ti='Tidalsong:BAAANQAECgIIAgAAAA==.Tirillian:BAAANQADCgUIBQAAAA==.Tirionsson:BAAANQAECgEIAgAAAA==.Tirnoir:BAAANQADCgQIBgABNQAECgQIBAAEAAAAAA==.',
Tk='Tkenga:BAAANQAECgMIBAAAAA==.',
To='Tojarm:BAAANQADCgEIAQAAAA==.Tonicdeath:BAAANQAECgQICQAAAA==.Torr:BAAANQADCgYIDAAAAA==.Torshana:BAAANQADCgQIBQAAAA==.Totemgobbler:BAAANQAECgEIAQAAAA==.Totemlyfine:BAAANQAECgUIDAAAAA==.',
Tr='Tralzind:BAAANQADCgMIAwAAAA==.Truthsayer:BAABNQAECoEbAAIFAAcKIRvrRgADAgAFAAcKIRvrRgADAgAAAA==.',
Ts='Tsquared:BAABNQAECoEfAAMcAAgKrBbDBgBEAgAcAAgKrBbDBgBEAgALAAMKhARCagF3AAAAAA==.Tsukasa:BAAANQAFFAEIAQAAAA==.Tsuruchi:BAAANQAECgUIBQAAAA==.',
Tu='Tukk:BAAANQAECgUIBQAAAA==.Tumnina:BAAANQADCgYICwAAAA==.',
Tw='Twiinkletoes:BAAANQADCggIEQAAAA==.Twopuffs:BAAANQAECgUIBQAAAA==.',
Ty='Tyce:BAAANQAECgYIEQAAAA==.Tylannis:BAAANQAECgYIEQAAAA==.',
Ug='Ugacoop:BAABNQAECoElAAMMAAgKQCR5DgA1AwAMAAgK5iN5DgA1AwASAAIK3h5KPwCwAAAAAA==.',
Ut='Uthrick:BAAANQADCgYIBgAAAA==.',
Va='Vaelisara:BAAANQAECgQICAAAAA==.',
Ve='Vehe:BAAANQAECgcIDgAAAA==.Veldrys:BAAANQADCggIFgABNQAECgcIGQAVAHQfAA==.Veledaa:BAAANQADCgYJFgAAAA==.Venomnips:BAAANQADCgQIBAAAAA==.Verige:BAAANQAECgEIAQAAAA==.Vesperbough:BAAANQABCgIIAgAAAA==.Vetis:BAAANQADCggIFQAAAA==.',
Vi='Vicars:BAAANQADCgYICwABNQAECgQICAAEAAAAAA==.Vickos:BAAANQAECgYIDAAAAA==.Vilyawen:BAAANQABCgIIBAAAAA==.Virgil:BAAANQADCgUICgABNQAECggIGgADAGEXAA==.Visionblast:BAAANQADCgEIAQAAAA==.Visionlink:BAAANQADCgEJAQAAAA==.Vixyn:BAAANQADCgYIBwAAAA==.',
Vo='Voidme:BAAANQADCgEIAQABNQAECgUICgAEAAAAAA==.Voidshift:BAAANQABCgMIAwAAAA==.Vorellyn:BAAANQAECgIIAQAAAA==.',
Vu='Vuuddon:BAAANQABCgQIBAAAAA==.',
Vy='Vyce:BAAANQAECgIIAgAAAA==.',
['Và']='Vàlorie:BAAANQAECgYICgABNQAFFAEIAQAEAAAAAA==.',
['Vè']='Vèlkhànà:BAABNQAECoEWAAILAAgKaB9kUwCxAgALAAgKaB9kUwCxAgAAAA==.',
Wa='Wafflesneggs:BAAANQAECgEIAQAAAA==.Wangdaulf:BAAANQADCgUIEAAAAA==.Wardoogy:BAAANQADCggICAAAAA==.Warexios:BAAANQADCgYICgAAAA==.Warglaíves:BAAANQADCgYICwABNQAECgkJIQAWANAZAA==.Warradord:BAAANQAECgQIBwABNQAECggIIAAgAKIeAA==.Warsmedic:BAABNQAECoEaAAIKAAgKXxBsTQDvAQAKAAgKXxBsTQDvAQAAAA==.',
We='Wevaren:BAAANQADCgQIBQAAAA==.',
Wh='Whumha:BAAANQADCgQIBAAAAA==.',
Wi='Wilbur:BAAANQADCggIDAAAAA==.Williams:BAEBNQAECoErAAIdAAkKriTfAgC0AwAdAAkKriTfAgC0AwAAAA==.Williamsjr:BAEBNQAECoEqAAIQAAkKHB+mJwDyAgAQAAkKHB+mJwDyAgABNQAECgkJKwAdAK4kAA==.Wilumi:BAAANQAECggIAQAAAA==.Winkel:BAAANQAECgMIAwAAAA==.',
Wo='Wolfyhuntres:BAAANQADCgQIBQAAAA==.Wolvesfor:BAAANQAECgIIBAAAAA==.Woopiing:BAEANQADCggIFQAAAA==.Woubbie:BAAANQABCgIIAwAAAA==.',
Wu='Wuhpow:BAAANQADCgIIAgAAAA==.Wunna:BAABNQAECoEXAAISAAgKjB90BADOAgASAAgKjB90BADOAgAAAA==.',
['Wá']='Wármonger:BAAANQADCgIIAgAAAA==.',
['Wâ']='Wâfflezz:BAAANQAECgIIAQAAAA==.',
Xa='Xanístus:BAAANQAECgYIDwAAAA==.',
Xe='Xeppa:BAAANQAECggIEwAAAA==.',
Xi='Xionz:BAAANQAECgUIDgAAAA==.',
Ya='Yakella:BAABNQAECoEaAAMRAAYKNST8LQBpAgARAAYKNST8LQBpAgAZAAQKJRiAiwAwAQAAAA==.',
Ye='Yelgrun:BAAANQADCgcIEwAAAA==.Yellcat:BAABNQAECoEkAAIoAAgKeB09EACZAgAoAAgKeB09EACZAgAAAA==.',
Yh='Yhoda:BAABNQAECoElAAIDAAkKoxucIwDQAgADAAkKoxucIwDQAgAAAA==.',
Yo='Yodä:BAAANQADCgUIBQAAAA==.Youseitgar:BAABNQAECoEYAAIdAAkKxBGeMwD+AQAdAAkKxBGeMwD+AQAAAA==.',
Yu='Yuisis:BAAANQAECgUIBQAAAA==.',
Za='Zabidu:BAABNQAECoEmAAMHAAkKRh7MBQAVAwAHAAkKRh7MBQAVAwAIAAEKIBp9TgBJAAAAAA==.Zamp:BAAANQADCgIIAgAAAA==.Zappyketch:BAABNQAECoEdAAIZAAkK4RpWKwCTAgAZAAkK4RpWKwCTAgAAAA==.Zaraeiri:BAAANQADCgUIBQAAAA==.Zaraxaà:BAAANQAECgMJAwABNQAECggIJAADAFcgAA==.',
Ze='Zelenã:BAAANQAECgYICQAAAA==.Zelun:BAABNQAECoEgAAMRAAkKkxpCJgCQAgARAAgKvxtCJgCQAgAZAAUKBxQlgQBLAQAAAA==.Zephon:BAABNQAECoEjAAMJAAkKoB9SCwArAwAJAAkKlx9SCwArAwATAAcKkRtVIAAPAgAAAA==.',
Zi='Ziggley:BAAANQADCgYIBgABNQAECggIGAAbAI8RAA==.',
Zo='Zombiemarj:BAAANQADCggIIQABNQAECgUIEAAEAAAAAA==.',
['Zé']='Zéd:BAABNQAECoEYAAIDAAcKch4iPQBsAgADAAcKch4iPQBsAgAAAA==.',
['Âx']='Âxel:BAAANQAECgUIBQABNQAECggIHgAJALIdAA==.',
['Æd']='Ædisgrace:BAAANQAECgEIAgAAAA==.',
['Æm']='Æmon:BAAANQADCgQIBAAAAA==.',
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
