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

local lookup = {'Monk-Brewmaster','DemonHunter-Havoc','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Blood','Hunter-BeastMastery','Paladin-Retribution','Warrior-Arms','Unknown-Unknown','Priest-Holy','Priest-Discipline','Monk-Mistweaver','Monk-Windwalker','Warlock-Demonology','DeathKnight-Frost','Paladin-Holy','Mage-Arcane','Warrior-Fury','Warrior-Protection','Paladin-Protection','Shaman-Restoration','Mage-Frost','Warlock-Destruction','Druid-Guardian','DemonHunter-Devourer','Hunter-Survival','Hunter-Marksmanship','Druid-Balance','Shaman-Enhancement','Warlock-Affliction','DemonHunter-Vengeance','Priest-Shadow','Evoker-Devastation','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Evoker-Augmentation','Druid-Restoration','Mage-Fire','Evoker-Preservation',}
local provider = {region='US',realm='Trollbane',name='US',type='weekly',zone=53,date='2026-10-06',data={Ac='Acroin:BAAANQADCgQIBAAAAA==.',
Ad='Adeliz:BAAANQAECgcIEgAAAA==.Adorana:BAAANQADCgQIBAAAAA==.Adrunk:BAABNQAECoEiAAIBAAgK6B5XBwCpAgABAAgK6B5XBwCpAgAAAA==.',
Ae='Aeloesh:BAAANQADCgUICAAAAA==.Aelyra:BAAANQADCgYICAAAAA==.Aenatheon:BAAANQAECgYIEgAAAA==.',
Ag='Aggrum:BAABNQAECoEYAAICAAgK/RQOKwAeAgACAAgK/RQOKwAeAgAAAA==.',
Ah='Ahab:BAAANQAECgIIAgAAAA==.Ahexutroll:BAABNQAECoEZAAIDAAcKxBF4aQCzAQADAAcKxBF4aQCzAQAAAA==.',
Ai='Aiur:BAAANQAECgQIBQAAAA==.',
Ak='Akredfox:BAAANQAECgYIEwAAAA==.',
Al='Alexaviah:BAABNQAECoEbAAIEAAgKGRCsngCZAAAEAAgKGRCsngCZAAAAAA==.Alicedelight:BAABNQAECoEZAAIFAAYKVgYJjQCrAAAFAAYKVgYJjQCrAAAAAA==.Aloldious:BAAANQAECgYIDAAAAA==.Alwaysburnt:BAAANQAECgIIAgAAAA==.Alwayscooked:BAAANQADCgIIAgAAAA==.Alwaysrolled:BAAANQABCgQIBAAAAA==.',
Am='Amabeast:BAAANQADCgUIBQAAAA==.Amanitin:BAAANQADCgQIBAAAAA==.Amisia:BAAANQAECgUICQAAAA==.',
An='Anathas:BAABNQAECoEeAAIFAAcKyyRUGADTAgAFAAcKyyRUGADTAgAAAA==.Ancestor:BAAANQAECgUICwAAAA==.Angelfelis:BAABNQAECoEtAAIGAAkKEiQyBQCuAwAGAAkKEiQyBQCuAwAAAA==.Angelgoblin:BAAANQADCgQIBQAAAA==.Angriff:BAAANQAECgUICgAAAA==.Angrybeavor:BAAANQAECgUIDwAAAA==.Anine:BAAANQAECgEIAQAAAA==.Anlana:BAAANQAECgUIBQABNQAFFAMIBgAHAIoKAA==.Anuke:BAAANQADCgcIBwAAAA==.',
Ao='Aonaar:BAAANQAECgEIAQAAAA==.',
Ar='Archdemon:BAAANQAECgcIDwAAAA==.Arkroot:BAAANQADCggIDwAAAA==.Arlock:BAAANQAECgEIAQABNQAECggIIAAIABwZAA==.Arsy:BAAANQAECgMIAwABNQAECgUIBwAJAAAAAA==.Artichoke:BAAANQAECgIIAgABNQAECgUICwAJAAAAAA==.',
As='Ashidora:BAEANQADCgYJBgABNQAECggILAAKAHMcAA==.Ashidpriest:BAEBNQAECoEsAAMKAAgKcxxaLACYAgAKAAgKcxxaLACYAgALAAMK1g8MFgCxAAAAAA==.Ashtoreth:BAAANQAECgMIBgAAAA==.Assukun:BAABNQAECoEpAAIMAAkKciFsAwBoAwAMAAkKciFsAwBoAwAAAA==.Astaroth:BAAANQADCgEIAQABNQAECgEIAwAJAAAAAA==.Async:BAAANQAECgcIDgAAAA==.',
At='Ati:BAAANQADCgYIBgAAAA==.',
Au='Aurá:BAAANQADCgIIAgAAAA==.Autoattack:BAAANQADCgcIBwAAAA==.',
Ax='Axethegrippa:BAAANQAECgYIEAABNQAFFAUICQANADISAA==.Aximumeffort:BAAANQADCgYIBgABNQAFFAUICQANADISAA==.',
Az='Azenservis:BAAANQADCgQIBAAAAA==.Azseera:BAAANQAECgEIAQAAAA==.Azuzu:BAAANQADCgUJBQAAAA==.',
Ba='Baddmojo:BAAANQAECgIIAgAAAA==.Badmac:BAABNQAECoEpAAICAAgKxBn3JQBEAgACAAgKxBn3JQBEAgAAAA==.Baelliman:BAAANQAECggIDAAAAA==.Baellin:BAAANQAECgcIBwABNQAECggIDAAJAAAAAA==.Baium:BAAANQAECgEIAgABNQAECgcIHAAOAM4JAA==.Bakemono:BAAANQADCgIIAgAAAA==.Bakora:BAAANQAECgQIBQAAAA==.Banishedfate:BAABNQAECoEXAAMPAAcKnhIhPQCWAQAPAAcKnhIhPQCWAQAEAAMKGAtvngCaAAAAAA==.Banishedform:BAAANQADCgYICgABNQAECgcIFwAPAJ4SAA==.Banishedholy:BAAANQAECgMIAwABNQAECgcIFwAPAJ4SAA==.Baozi:BAAANQAECgQIBQABNQAECgYIEwAJAAAAAA==.Barelyholy:BAABNQAECoEbAAIQAAgK4RtBLgCSAgAQAAgK4RtBLgCSAgAAAA==.Barf:BAAANQAECgEIAwABNQAECgYIEwAJAAAAAA==.Barrendar:BAAANQADCgIIAgAAAA==.Bartholamew:BAAANQADCgcIDgAAAA==.',
Be='Bearballz:BAAANQADCgIIAgAAAA==.Beardey:BAAANQADCgUIBQAAAA==.Beefybeefboy:BAAANQAECgYIBgAAAA==.Berry:BAABNQAECoEgAAIRAAgKfhyyeAB2AgARAAgKfhyyeAB2AgAAAA==.Besneakies:BAAANQAECgYIEwAAAA==.',
Bi='Bigdamfred:BAAANQADCgEIAQAAAA==.Binnford:BAAANQAECgEIAQAAAA==.',
Bl='Blackfang:BAAANQADCgUIBQABNQAECggIGAACAP0UAA==.Blaqball:BAAANQADCgUIDQAAAA==.Blinkerz:BAAANQAECgUIBAAAAA==.Bludboil:BAAANQAECgUIBQABNQAFFAQIDgAOAP0PAA==.',
Bo='Bottombish:BAAANQADCggIDAAAAA==.Boulderjaw:BAABNQAECoEdAAISAAgKTg+FLwAvAAASAAgKTg+FLwAvAAAAAA==.Bovinna:BAAANQADCgQIBAAAAA==.Boxeybrown:BAABNQAECoEVAAITAAcKFRU6FwCKAQATAAcKFRU6FwCKAQAAAA==.',
Br='Braised:BAABNQAECoEaAAIUAAcKjB+cEgBSAgAUAAcKjB+cEgBSAgAAAA==.Brbdeported:BAAANQAECgIIAgAAAA==.Breakadakeys:BAABNQAECoEiAAIIAAgKqRhVZwA6AgAIAAgKqRhVZwA6AgAAAA==.Breccia:BAAANQAECgUICAAAAA==.Brutanious:BAAANQAECgQIBQABNQAECgUICwAJAAAAAA==.',
Bu='Bubbalicous:BAAANQAECggIBgAAAA==.Bubblebro:BAAANQAECgQICQAAAA==.Buffwarrior:BAAANQAECggIEwAAAA==.Bustamoon:BAAANQADCggIDgAAAA==.Butterface:BAAANQAECgUICwAAAA==.',
['Bà']='Bàckstabbath:BAAANQADCgMIAwAAAA==.',
Ca='Caeruleus:BAAANQADCgcIBwAAAA==.Cammikins:BAEBNQAECoEoAAIVAAkK+yF1DQBBAwAVAAkK+yF1DQBBAwAAAA==.Camstelation:BAEANQADCgUIBQABNQAECgkJKAAVAPshAA==.Cannolii:BAEANQADCgEIAQAAAA==.Cantmilkem:BAAANQADCgIIAgAAAA==.Cantric:BAAANQADCgQIBAAAAA==.Capellaz:BAABNQAECoEcAAIWAAcKnxHBDQClAQAWAAcKnxHBDQClAQAAAA==.Capriestson:BAABNQAECoEfAAIKAAcKlyNyIwDCAgAKAAcKlyNyIwDCAgAAAA==.Cardib:BAAANQAECgQIBgABNQAECgkJGAAXAO0dAA==.Carwel:BAAANQABCgIIAgAAAA==.Casandra:BAAANQAECggIEQAAAA==.Cassiopeias:BAAANQADCgUIBQAAAA==.',
Ce='Celerynn:BAAANQADCgUICAAAAA==.Celestaura:BAAANQAECgYIEgAAAA==.Cenerald:BAAANQADCggICAABNQAECggIGgAYAHQYAA==.Centares:BAAANQADCgYJEgAAAA==.',
Ch='Chandelan:BAAANQAECgIIAgAAAA==.Charlutes:BAAANQAECgUICQAAAA==.Chekzy:BAAANQAECgMIBQAAAA==.Chichii:BAAANQAECgMIBAAAAA==.Chilis:BAAANQADCgcIBwABNQAECggIHQAVAI4aAA==.Chiyuki:BAAANQADCgQJBAABNQAECgQIDAAJAAAAAA==.Choasman:BAAANQADCggIDgAAAA==.Chocolate:BAAANQADCgUJCAAAAA==.Chudpath:BAAANQAECgQIBwABNQAECgkJKgAMALceAA==.',
Cl='Cleome:BAAANQABCgEIAQAAAA==.',
Co='Coldstar:BAAANQADCgMIAwAAAA==.Coorsenjoyer:BAECNQAFFIESAAIFAAYKhR2xBAAQAgAFAAYKhR2xBAAQAgA1AAQKgSEAAgUACQqhIPkTAPcCAAUACQqhIPkTAPcCAAAA.Coorslatte:BAEANQAFFAQIBAABNQAFFAYIEgAFAIUdAA==.Copakid:BAAANQAECgUIEwAAAA==.Cowlie:BAABNQAECoEpAAIZAAkKvyM8AwCgAwAZAAkKvyM8AwCgAwAAAA==.Coøkiewizard:BAAANQADCgEIAQAAAA==.',
Cr='Crippy:BAABNQAECoEaAAMPAAkKCh3qEADpAgAPAAkKCh3qEADpAgAFAAIKQAIQsgBGAAABNQADCgIIAgAJAAAAAA==.Crippypal:BAAANQAECgUICQABNQADCgIIAgAJAAAAAA==.Crippyx:BAAANQADCgIIAgAAAA==.Crowls:BAAANQADCgMIAwABNQAECgkJKQAZAL8jAA==.Cruelwar:BAAANQAECgYIDQAAAA==.',
Cu='Cuckcmder:BAABNQAECoEZAAMFAAYKIg3CaAAsAQAFAAYKIg3CaAAsAQAEAAQKowG4sQBmAAAAAA==.',
Da='Daffodil:BAAANQADCgEIAQAAAA==.Dageron:BAAANQAECggIBwAAAA==.Daggoth:BAABNQAECoEbAAICAAgKJiKQFADaAgACAAgKJiKQFADaAgAAAA==.Dalrak:BAABNQAECoEqAAQaAAgKxCOMAQBFAwAaAAgKxCOMAQBFAwAbAAQKgxggSADpAAAGAAIK4BkdEgGLAAAAAA==.Dandarth:BAAANQADCgMIAwAAAA==.Danemos:BAAANQADCgMIAwABNQAFFAQIDgAOAP0PAA==.Dante:BAAANQAECgQIBAABNQAECggIGgAGAGEXAA==.Darkendelf:BAAANQAECgQIBQAAAA==.Darkothy:BAAANQAECgYIEgAAAA==.Darkstôrm:BAAANQAECgIIAgAAAA==.Darkvision:BAAANQAECgEIAQAAAA==.Darthroy:BAAANQAECgcIBwAAAA==.Dasdann:BAAANQADCgUIBQAAAA==.Datdude:BAAANQAECgIIAgAAAA==.Datshammy:BAAANQADCgUIBQAAAA==.Datvoodoomon:BAABNQAECoEqAAIcAAkKwCF4DABZAwAcAAkKwCF4DABZAwAAAA==.Daïn:BAABNQAECoEbAAIdAAgKchy1CgCyAgAdAAgKchy1CgCyAgAAAA==.',
Dc='Dcaý:BAAANQAECgUIBwAAAA==.',
De='Deadboii:BAAANQAECgEJAQAAAA==.Deadjuggalo:BAAANQAECgQIBQAAAA==.Deadlyfaith:BAAANQADCggIGgAAAA==.Deadstep:BAAANQAECgYIDgAAAA==.Deathzy:BAAANQADCgIIAgAAAA==.Deitzz:BAAANQADCgQIBAAAAA==.Deleralia:BAABNQAECoEaAAIYAAgKdBg+EAAdAgAYAAgKdBg+EAAdAgAAAA==.Demonlex:BAAANQAECgMIAwAAAA==.Demontopher:BAABNQAECoEfAAIeAAkKNiY9AADMAwAeAAkKNiY9AADMAwAAAA==.Derodrayne:BAAANQADCgYIBwAAAA==.Deshaler:BAAANQADCgcIBwAAAA==.Devoidshield:BAAANQAECgIIAgAAAA==.',
Di='Dicon:BAAANQADCgYIBgAAAA==.Dieric:BAAANQAECgUIEgAAAA==.Dinkle:BAAANQADCgMJAwABNQAECgcIEgAJAAAAAA==.Dividian:BAABNQAECoEaAAMGAAgKYRfzUQBSAgAGAAgKYRfzUQBSAgAaAAQKywbgDADFAAAAAA==.Dizana:BAAANQAECgcICAABNQAECgcIEgAJAAAAAA==.',
Do='Dorastrain:BAABNQAECoElAAIfAAgK6SWgAQB2AwAfAAgK6SWgAQB2AwAAAA==.',
Dr='Dracovoid:BAAANQAECgQIBwABNQAECgUIDwAJAAAAAA==.Dragondees:BAAANQAECgUIBgAAAA==.Dragonwyck:BAAANQAECgQIDAAAAA==.Draytheus:BAAANQAECgUICwAAAA==.Drganon:BAAANQAECgYICwAAAA==.Dripping:BAAANQAECgQICAAAAA==.Dromai:BAAANQADCgYICAAAAA==.',
Du='Duhdotsbruh:BAAANQAECgQIBAAAAA==.Duraf:BAAANQAECgQIBQAAAA==.Duugan:BAAANQADCgQIBAAAAA==.',
Ed='Edgarj:BAAANQADCgEIAQAAAA==.',
Ek='Eklipsch:BAAANQADCggIDwAAAA==.',
El='Eld:BAAANQABCgYIBwAAAA==.Electrocute:BAAANQADCgMIAwAAAA==.Electrocutey:BAABNQAECoEdAAIDAAcKcw9/cACfAQADAAcKcw9/cACfAQAAAA==.Elein:BAAANQAECgIIAgAAAA==.Eleman:BAAANQAECgIIAgAAAA==.Elfclover:BAABNQAECoEeAAIbAAkKqhbLHABQAgAbAAkKqhbLHABQAgAAAA==.Elijahx:BAABNQAECoEfAAISAAkKcxVkBwBZAgASAAkKcxVkBwBZAgAAAA==.Elijay:BAAANQAECgUICAAAAA==.Eljayye:BAAANQAECgEIAQAAAA==.',
Em='Emisha:BAAANQADCgIIAgAAAA==.Emmshunter:BAACNQAFFIEFAAIGAAMKmg+5EgD9AAAGAAMKmg+5EgD9AAA1AAQKgRYAAgYABwqqHp1AAIQCAAYABwqqHp1AAIQCAAAA.',
En='Entropy:BAAANQAECgEIAQAAAA==.Envi:BAAANQAECgIIBAAAAA==.',
Ep='Epicdemise:BAAANQAECgQIBAAAAA==.Epicdemon:BAAANQADCggIFgAAAA==.Epicwarlock:BAAANQADCggIFQAAAA==.Epona:BAABNQAECoEnAAMVAAgKVhPvigBAAQAVAAgKVhPvigBAAQADAAEKfwFYOgEbAAAAAA==.',
Er='Ern:BAAANQAECgIIAQAAAA==.Ernolock:BAAANQAECgMIAgAAAA==.Erzá:BAAANQAECgUIEAAAAA==.',
Es='Espina:BAAANQADCgUIBQAAAA==.',
Et='Eterna:BAAANQAECgcIEgAAAA==.',
Ev='Ev:BAAANQAECgIIAgAAAA==.Eveilyn:BAAANQAFFAEIAQAAAA==.Evilerno:BAAANQAECgIIAQAAAA==.Evileye:BAAANQADCgYIBgAAAA==.Evylenna:BAAANQAECgUIBQAAAA==.',
Ex='Exarchamus:BAABNQAECoEgAAIIAAgKHBkVXABbAgAIAAgKHBkVXABbAgAAAA==.',
Fa='Facemelt:BAABNQAECoEnAAIgAAkK5hzoDgDsAgAgAAkK5hzoDgDsAgAAAA==.Faloogâ:BAAANQADCgYIBgAAAA==.Farfy:BAABNQAECoEpAAIFAAkKgxqxHACyAgAFAAkKgxqxHACyAgAAAA==.Fartsmagoo:BAAANQAECgcIEQAAAA==.Faykan:BAABNQAECoEfAAIXAAcKQRl0DAAlAgAXAAcKQRl0DAAlAgAAAA==.',
Fe='Fedrameda:BAABNQAECoEZAAIGAAgKdxePUwBNAgAGAAgKdxePUwBNAgAAAA==.Felix:BAABNQAECoEdAAIUAAcKtR1aEwBJAgAUAAcKtR1aEwBJAgAAAA==.Fellender:BAAANQADCggIPwAAAA==.Fermented:BAABNQAECoEYAAIFAAgKahZ0OgD6AQAFAAgKahZ0OgD6AQAAAA==.',
Fi='Fishytea:BAAANQADCgIIAgAAAA==.Fixwarplz:BAAANQAECgUIBgAAAA==.Fizzle:BAAANQADCgQIBgAAAA==.',
Fl='Flintstones:BAABNQAECoEmAAIcAAkKcxtRIACsAgAcAAkKcxtRIACsAgAAAA==.Fluffykiitty:BAAANQADCgEIAQAAAA==.Flyinglizard:BAAANQAECgIIAgAAAA==.',
Fo='Fowlplay:BAAANQAECgUIBgAAAA==.Foxbox:BAAANQAECgYICgAAAA==.',
Fr='Frostedhoof:BAAANQAECgcIBwABNQAFFAMICAAbAFUUAA==.',
Fu='Fujee:BAABNQAECoEfAAMbAAgK4R2qFACkAgAbAAgKBh2qFACkAgAGAAQKwB2N2wAXAQAAAA==.Funkyt:BAAANQAECgYIDAAAAA==.Furijan:BAAANQADCgMIAwAAAA==.Furrysona:BAAANQAECgEIAQABNQAECgkJKgAhAOYYAA==.',
['Fâ']='Fâlooga:BAABNQAECoEbAAIRAAcKXhXTvgDjAQARAAcKXhXTvgDjAQAAAA==.',
['Fë']='Fëlörc:BAAANQADCgUIBQABNQADCgQIBAAJAAAAAA==.',
Ga='Gaidine:BAAANQADCgMJAwAAAA==.Galadriael:BAABNQAECoEeAAMWAAgK0x0qFgApAQARAAgKjhqgmAAxAgAWAAQKuB4qFgApAQAAAA==.Galtan:BAAANQAECgUIDAAAAA==.Gandoch:BAAANQADCgQIBAAAAA==.Garrod:BAABNQAECoEcAAIGAAkKCBNzSABtAgAGAAkKCBNzSABtAgAAAA==.Gasionaldo:BAAANQAECgIIAwAAAA==.Gattsu:BAAANQAECgIIAgAAAA==.',
Ge='Gelandra:BAAANQADCgQIBAABNQAECgkJLgAGAI4fAA==.Gennil:BAABNQAECoEtAAMWAAkKQCV3AADDAwAWAAkKQCV3AADDAwARAAEKphTVogE7AAAAAA==.Gestella:BAAANQAECgYIEwAAAA==.Gevo:BAABNQAECoEgAAIIAAkKOxYfWABmAgAIAAkKOxYfWABmAgAAAA==.',
Gi='Gineselle:BAAANQAECgIIBQAAAA==.Giveemhail:BAAANQADCgMIAwABNQAECgkJHgAEADwXAA==.',
Gl='Gloomblade:BAACNQAFFIEQAAMiAAYK/BlOAgAkAgAiAAYK/BlOAgAkAgAjAAIKlxvxCwC0AAA1AAQKgSAAAyMACQo6H0gKAMQCACMACQobHUgKAMQCACIABApNHudHAF0BAAAA.',
Gn='Gnomepimp:BAAANQADCgYIBgABNQAECgUIBwAJAAAAAA==.',
Go='Gojìra:BAAANQAECgYIEQAAAA==.Goragaia:BAABNQAECoEaAAIDAAgKnAhPdwCMAQADAAgKnAhPdwCMAQABNQABCgUIBQAJAAAAAA==.Gorbencleap:BAAANQABCgMIAwAAAA==.Gorion:BAAANQADCgQIBAAAAA==.',
Gr='Graypelt:BAAANQADCggIDwAAAA==.Grayscale:BAAANQADCgYIDAAAAA==.Grayventress:BAAANQADCgYIBgAAAA==.Greyseer:BAAANQAECgYIDQAAAA==.Grica:BAAANQADCgEIAQAAAA==.Gripsworth:BAAANQAECgQIBAABNQAECggJGQAMAOgXAA==.Gryphonheart:BAAANQADCgQIBAAAAA==.',
Gu='Guymontag:BAABNQAECoEoAAQQAAkKbhnlgQBrAQAQAAUK6xflgQBrAQAHAAkKpR7T2QAtAQAUAAMK2hVwRwCnAAAAAA==.',
Ha='Hammergobrr:BAAANQAECgQIBAAAAA==.Harbard:BAABNQAECoEgAAIGAAkKShlYMAC6AgAGAAkKShlYMAC6AgAAAA==.Hasselhøøf:BAABNQAECoEeAAIDAAgKbhTeUQAEAgADAAgKbhTeUQAEAgAAAA==.Hawkeyeik:BAABNQAECoEXAAIGAAgKiRi3UABVAgAGAAgKiRi3UABVAgAAAA==.Hawthorne:BAABNQAECoEhAAIhAAgKBhgaDwBMAgAhAAgKBhgaDwBMAgAAAA==.Hayywaffle:BAAANQADCggIDAAAAA==.',
He='Heeferk:BAAANQADCgcIBwAAAA==.Heilwelle:BAAANQADCgcIBwAAAA==.Hellothere:BAABNQAECoEgAAMHAAcKdialKQAEAwAHAAcKdialKQAEAwAUAAEKOQx2ZgArAAAAAA==.Hellren:BAAANQAECgEIAQABNQAECgMIBAAJAAAAAA==.Helmet:BAAANQADCgQIBAAAAA==.',
Hi='Hikons:BAABNQAECoEdAAIQAAgKmgpMbgClAQAQAAgKmgpMbgClAQAAAA==.Hinkle:BAAANQAECgUIEAABNQAECgcIEgAJAAAAAA==.',
Ho='Hobojoe:BAAANQAECgYIEAAAAA==.Holliehammer:BAAANQAECgUIBQAAAA==.Holyclover:BAAANQAECgIIAwAAAA==.Holysage:BAAANQADCgcIBwAAAA==.Holytoad:BAAANQADCgYIBgABNQAECgUIBQAJAAAAAA==.Hopsquash:BAAANQADCgUICAAAAA==.Hopstop:BAABNQAECoEcAAIGAAcKtQoilwCnAQAGAAcKtQoilwCnAQAAAA==.',
Hu='Hughass:BAAANQADCgYIFQABNQAECgMIBQAJAAAAAA==.Hugo:BAABNQAECoEaAAIHAAYKhBaYtAB8AQAHAAYKhBaYtAB8AQAAAA==.Hukkash:BAAANQABCgMIAwAAAA==.Hullr:BAAANQAECgQIBgAAAA==.Huwglyndur:BAABNQAECoEcAAIUAAcKYAbXNgAGAQAUAAcKYAbXNgAGAQAAAA==.',
Hy='Hyperiun:BAAANQAECgQIBAAAAA==.Hyperiunpala:BAAANQAECgYIEQAAAA==.',
Ia='Iari:BAAANQAECgYIBgAAAA==.',
Id='Idispizhorde:BAABNQAECoEmAAIEAAkKbxt/HgC3AgAEAAkKbxt/HgC3AgAAAA==.',
Ig='Igris:BAABNQAECoEfAAIIAAgK8RaVcAAhAgAIAAgK8RaVcAAhAgAAAA==.',
Il='Illihottie:BAAANQADCgQIBAAAAA==.Illiora:BAAANQADCgYIBQABNQAECgkJQwAVAFgcAA==.Illissia:BAAANQAECgIIAgAAAA==.',
Im='Imós:BAAANQADCgcICAAAAA==.',
Ir='Ironbrew:BAAANQAECgIIAwAAAA==.Ironpreacher:BAAANQADCgYIDQAAAA==.Ironspite:BAAANQADCggIDQAAAA==.',
Is='Ish:BAABNQAECoEpAAIgAAkKrh0KEQDOAgAgAAkKrh0KEQDOAgAAAA==.Ishibad:BAAANQAECgQIBQABNQAECgkJKQAgAK4dAA==.Isolie:BAAANQAECgEIAQAAAA==.Isongard:BAAANQABCgIIAgAAAA==.',
It='Itsthesham:BAAANQAECgQIBQABNQAECgkJHgANAHYcAA==.',
Iv='Ivok:BAAANQADCggIHwAAAA==.',
Iy='Iyooni:BAAANQABCgQIBAAAAA==.',
Ja='Jatbez:BAAANQADCgUIBwAAAA==.Jaykay:BAAANQADCgcJCgAAAA==.Jazmìne:BAAANQADCggIHgAAAA==.',
Je='Jessa:BAAANQAECgcIDAAAAA==.Jezuz:BAABNQAECoEbAAIKAAcK9xx4PABUAgAKAAcK9xx4PABUAgAAAA==.',
Ji='Jimbadd:BAAANQAECgQIBQAAAA==.Jimmieslock:BAACNQAFFIEVAAQOAAcKTSASAgBSAgAOAAYKdR8SAgBSAgAeAAEKEiYVBQBtAAAXAAEKnCRTEQBrAAA1AAQKgRoAAxcACQpfJn8HAIECAA4ACArnJTAVACIDABcABwoCJH8HAIECAAAA.Jimmiespala:BAAANQAECgIIAgABNQAFFAcIFQAOAE0gAA==.',
Jk='Jkils:BAAANQADCggIEQAAAA==.',
Jo='Jonbaptist:BAAANQAECgcIEwAAAA==.Jonile:BAAANQADCgQIBQAAAA==.Joyfulflame:BAAANQAECgUIBwABNQAECgcIHQADAHMPAA==.',
Jt='Jtrain:BAAANQAECgUIEgAAAA==.',
Ju='Judwin:BAABNQAECoEcAAMiAAgKzyJCCwAWAwAiAAgKzyJCCwAWAwAkAAIKmxZKFQB8AAAAAA==.',
['Jä']='Jäzmine:BAAANQADCgIIAgAAAA==.',
['Jè']='Jèssicà:BAABNQAECoEuAAIGAAkKjh/5FwAiAwAGAAkKjh/5FwAiAwAAAA==.',
['Jô']='Jôseph:BAAANQADCgUIBgAAAA==.',
['Jö']='Jöe:BAAANQADCgIIAgAAAA==.',
Ka='Kaalin:BAAANQADCgIJAgAAAA==.Kabutosan:BAAANQAECgEIAQABNQAFFAQIDgAOAP0PAA==.Kail:BAAANQADCgQIBAAAAA==.Kaleesi:BAAANQADCgcIEAAAAA==.Kamots:BAABNQAECoEZAAIGAAkKggdcgQDaAQAGAAkKggdcgQDaAQAAAA==.Kareokee:BAABNQAECoElAAISAAgKYA+TCwDlAQASAAgKYA+TCwDlAQAAAA==.Kargoroth:BAACNQAFFIEJAAIDAAUK1Ar3CwB2AQADAAUK1Ar3CwB2AQA1AAQKgSQAAgMACQqnHssjANgCAAMACQqnHssjANgCAAAA.Karral:BAABNQAECoEjAAMGAAkKLCHTFQAtAwAGAAkKLCHTFQAtAwAaAAEK1BebEAA+AAAAAA==.Katerzv:BAAANQADCgMIBAAAAA==.Kazdormu:BAABNQAECoEpAAMhAAkKfhZ/DQBvAgAhAAkKfhZ/DQBvAgAlAAEKVxC7IQArAAAAAA==.',
Kc='Kchaos:BAAANQADCgcIBwAAAA==.',
Ke='Kedira:BAAANQADCggIEAABNQAFFAIICAAPAKchAA==.Keloth:BAAANQADCgQIBAABNQAECgQIBAAJAAAAAA==.Keyztone:BAAANQAECggIAgAAAA==.',
Kh='Khadriel:BAABNQAECoEgAAIZAAgKNBK5IgAVAgAZAAgKNBK5IgAVAgAAAA==.',
Ki='Killinrapidy:BAAANQADCgUJCQAAAA==.Kitani:BAABNQAECoEyAAITAAkKRiNRAgB9AwATAAkKRiNRAgB9AwAAAA==.Kizbe:BAAANQADCgEIAQAAAA==.',
Kn='Knottybits:BAAANQAECgUICQAAAA==.',
Ko='Konsumer:BAAANQADCgQJBAABNQAECgUICgAJAAAAAA==.Kontakt:BAAANQADCgcIDgAAAA==.Konân:BAABNQAECoEeAAIdAAcK6Bz8DwBOAgAdAAcK6Bz8DwBOAgAAAA==.Kordim:BAAANQAECgQIDAABNQAECggIJwAYAL8RAA==.Korvakh:BAAANQAECgUIBgAAAA==.',
Kr='Kraduun:BAABNQAECoEYAAIIAAgKBQo8nQCpAQAIAAgKBQo8nQCpAQAAAA==.Krantly:BAAANQAECgEIAQAAAA==.Krenaele:BAAANQADCgYIBgAAAA==.Krenisdead:BAAANQADCgQIBAAAAA==.Krenniellin:BAAANQAECgUJDwAAAA==.Krys:BAAANQAECgcIEwAAAA==.',
La='Laev:BAEANQADCggICAABNQAECggILAAKAHMcAA==.Lairbear:BAAANQADCgYICwAAAA==.Lambadin:BAAANQADCgQIBAAAAA==.Lanadelrey:BAAANQAECgQICgAAAA==.Lanaru:BAAANQADCggIHAABNQAECgUIEAAJAAAAAA==.Lavi:BAAANQAECgUIDgAAAA==.',
Le='Leizil:BAABNQAECoEpAAIKAAkKUhNHPQBQAgAKAAkKUhNHPQBQAgAAAA==.Lennox:BAABNQAECoEdAAImAAcKcBPIKQCeAQAmAAcKcBPIKQCeAQAAAA==.Lesaire:BAAANQAECgIJAgAAAA==.Letara:BAAANQAECgYIBgAAAA==.Letheria:BAAANQADCgUIBQAAAA==.Lextor:BAAANQADCgQIBQAAAA==.',
Lh='Lhuani:BAACNQAFFIEIAAIRAAMKAhV6KgD0AAARAAMKAhV6KgD0AAA1AAQKgS8ABBEACQrLH0c2AA8DABEACQqoH0c2AA8DACcABAroGa8EADUBABYAAgoaFnopAIQAAAAA.',
Li='Liaelina:BAEBNQAECoEaAAIRAAcKDg7o1gCzAQARAAcKDg7o1gCzAQAAAA==.Lichte:BAAANQABCgMIAwAAAA==.Lightmyhole:BAAANQADCgEJAQABNQAFFAMIBQAGAJoPAA==.Like:BAAANQADCgUIBQAAAA==.Lilyachty:BAAANQADCgUICgABNQAECgkJGAAXAO0dAA==.Lilíth:BAAANQAECgcICgABNQAECggIEQAJAAAAAA==.Lindbergh:BAAANQAECgQIBAABNQAECgUICwAJAAAAAA==.Linshe:BAABNQAECoEhAAIRAAgKZA+fYgHIAAARAAgKZA+fYgHIAAAAAA==.Lizzie:BAAANQADCgUIBQAAAA==.',
Ll='Llillianna:BAAANQAECgQIDAAAAA==.',
Lo='Loosey:BAAANQABCgYIBgAAAA==.Lorm:BAAANQADCgQIBQAAAA==.Lostdream:BAAANQADCgMIBgAAAA==.',
Lu='Lucarien:BAAANQAECgMIBQAAAA==.Lumatoad:BAAANQAECgUIBQAAAA==.Lustyglory:BAAANQADCggICAAAAA==.',
Ma='Macareios:BAAANQADCgUIBQAAAA==.Madeintyø:BAAANQAECgUIBgABNQAECgkJGAAXAO0dAA==.Maelos:BAAANQAECgIIAgAAAA==.Mageaga:BAAANQADCgYICwAAAA==.Magnathul:BAABNQAECoEeAAMEAAkKHhm0LwBOAgAEAAkKHhm0LwBOAgAPAAIKCAnDggBeAAAAAA==.Magnumdruid:BAAANQADCgQJBAAAAA==.Makeah:BAABNQAECoEoAAIGAAkKNCIKEABQAwAGAAkKNCIKEABQAwAAAA==.Makhamou:BAABNQAECoEbAAMIAAgKeBkvWgBgAgAIAAgKVhgvWgBgAgASAAQKnxYxGAD5AAAAAA==.Malak:BAAANQAECgYIEAABNQAECgkJKAAQAG4ZAA==.Malinstur:BAABNQAECoEaAAIEAAgK+Ag8XwBsAQAEAAgK+Ag8XwBsAQAAAA==.Malted:BAAANQAECgYIBwAAAA==.Marianne:BAAANQADCgcICQAAAA==.Marjorye:BAABNQAECoEYAAIGAAcKBBx+VQBIAgAGAAcKBBx+VQBIAgAAAA==.Marnaught:BAAANQAECgUIBgABNQAECgUICQAJAAAAAA==.Marsy:BAAANQAECgUIBwAAAA==.Marzánna:BAAANQADCgQIBwABNQAECgcIGgAPAA0bAA==.Mashed:BAAANQADCgYICwABNQAECgUIBwAJAAAAAA==.Matts:BAAANQAECgEIAwAAAA==.Mausi:BAAANQADCgQIBAABNQAECgMIBQAJAAAAAA==.Maxxamus:BAAANQAECgEIAQAAAA==.Mazaal:BAABNQAECoEqAAMPAAkKuCS8AwCZAwAPAAkKuCS8AwCZAwAEAAEKBiRKsQBnAAAAAA==.',
Mc='Mcshaft:BAAANQABCgQIBQAAAA==.',
Me='Meatmuskett:BAAANQADCggICAAAAA==.Meatnormus:BAAANQADCgUIBQAAAA==.Mekeena:BAABNQAECoEaAAIKAAcKMhOtbQCdAQAKAAcKMhOtbQCdAQAAAA==.Melady:BAAANQADCgEIAQAAAA==.Melesandre:BAAANQAECgEIAQAAAA==.Melinee:BAAANQADCgcICgAAAA==.Mellinda:BAAANQAECgQICAAAAA==.Melzas:BAAANQAECgUIDAAAAA==.',
Mi='Midrok:BAABNQAECoEnAAIYAAgKvxF/PwBrAAAYAAgKvxF/PwBrAAAAAA==.Mikåh:BAAANQADCggIFAAAAA==.Milanova:BAAANQADCgQIBAAAAA==.Milkjugzz:BAAANQADCgQIBAAAAA==.Mirakuru:BAAANQADCgYIBgAAAA==.Miselah:BAAANQADCgQIBQAAAA==.Missyennefer:BAAANQADCgcIEgAAAA==.',
Mm='Mmbhpta:BAAANQAECgMIAwABNQAECgkJGAAXAO0dAA==.',
Mo='Mobythicc:BAAANQADCgcICQABNQAFFAUICQANADISAA==.Mondai:BAAANQABCgQIBAAAAA==.Monkpowahh:BAAANQADCgEIAQABNQAECgUIEgAJAAAAAA==.Montag:BAAANQAECgEIAQABNQAECgkJKAAQAG4ZAA==.Moonboomfred:BAAANQADCgMIAwAAAA==.Moonshower:BAABNQAECoEhAAIKAAgKjR+eKQCkAgAKAAgKjR+eKQCkAgAAAA==.Mooranda:BAAANQABCggIDgAAAA==.Moraear:BAAANQADCgIIAgAAAA==.Mordris:BAAANQADCgUIBQAAAA==.Morgaenei:BAAANQABCgMIAwAAAA==.',
Mt='Mtastyck:BAAANQAECgQIBgAAAA==.',
Mu='Mudsniffer:BAAANQAECgUIEgAAAA==.Multitool:BAEBNQAECoEpAAIUAAkKCyKgBABYAwAUAAkKCyKgBABYAwABNQADCgEIAQAJAAAAAA==.Mundekk:BAAANQAECgYIEQAAAA==.',
My='Mylo:BAAANQAECgEIAgAAAA==.Myobûky:BAAANQADCgUIBQAAAA==.Mystiecub:BAAANQABCgIJAQAAAA==.Mythgleam:BAAANQAECgIJAgAAAA==.Mythsol:BAAANQAECgEIAQAAAA==.Myththistle:BAAANQADCgEIAQAAAA==.',
['Má']='Mániac:BAAANQAECgIIAgAAAA==.',
Na='Nack:BAAANQADCgcICQABNQAECggIEwAJAAAAAA==.Nacks:BAAANQAECggIEwAAAA==.Nacksd:BAAANQADCgEIAQABNQAECggIEwAJAAAAAA==.Nacksly:BAAANQAECgIIAgABNQAECggIEwAJAAAAAA==.Nacksm:BAAANQADCggICAABNQAECggIEwAJAAAAAA==.Nacksp:BAAANQADCgUIBQABNQAECggIEwAJAAAAAA==.Naelandra:BAAANQADCgQJBAABNQAECgkJKAAQAG4ZAA==.Naliön:BAAANQADCggIFAAAAA==.Naotsugu:BAAANQAECgIIAgAAAA==.Nargacuga:BAAANQAECgEIAQABNQAECgkJHQARAB4hAA==.Nasarden:BAAANQAECgMIBAAAAA==.Nasir:BAAANQAECgMIBAAAAA==.Nastysage:BAAANQAECgUIEwAAAA==.Nastyxxnate:BAAANQAECgQIBAAAAA==.Natric:BAAANQAECgEIAwAAAA==.Naxdh:BAAANQADCggIDAABNQAECggIEwAJAAAAAA==.',
Ne='Nechanion:BAAANQADCggIFwAAAA==.Nessië:BAABNQAECoEZAAIVAAgKiwe5ggBXAQAVAAgKiwe5ggBXAQAAAA==.Nesthor:BAAANQADCgYIBgAAAA==.',
Ni='Nicodh:BAAANQAECgIIAgAAAA==.Nimibear:BAAANQAECgIIAgAAAA==.Nimidk:BAACNQAFFIEHAAIFAAMKxyIlDwAvAQAFAAMKxyIlDwAvAQA1AAQKgR8AAgUACQq8HZwbALoCAAUACQq8HZwbALoCAAAA.Ninjahealer:BAAANQAECgUICQAAAA==.',
No='Noobtotem:BAAANQADCgYICwABNQAECggIGwAQAOEbAA==.',
Nu='Nugsmasher:BAAANQADCgYIFwAAAA==.Nutdevourer:BAABNQAECoEiAAIZAAcKpx3rGQBvAgAZAAcKpx3rGQBvAgAAAA==.',
Ny='Nysellin:BAAANQAECgEIAQABNQAECgkJHQARAB4hAA==.',
['Né']='Néther:BAAANQADCgcICAAAAA==.',
Oa='Oakelvin:BAAANQAECgcJDgAAAA==.',
Ob='Obnoxiousego:BAAANQAFFAIIAgAAAA==.',
Od='Odartherogue:BAAANQADCgUIBAAAAA==.Oddknee:BAACNQAFFIEIAAMbAAMKVRSsEgDcAAAbAAMKVRSsEgDcAAAGAAEKGQoVMABLAAA1AAQKgTAAAxsACQq1IUQHAFADABsACQq1IUQHAFADAAYAAQr+F1EoAU8AAAAA.Odney:BAAANQAECgUIDQABNQAFFAMICAAbAFUUAA==.',
On='Onaria:BAAANQAECgcICwABNQAECgkJQwAVAFgcAA==.',
Oo='Oog:BAAANQADCggIEAABNQAECgMIBQAJAAAAAA==.',
Or='Oridox:BAABNQAECoEiAAIYAAgKNSByBwDdAgAYAAgKNSByBwDdAgAAAA==.Orumine:BAACNQAFFIEGAAIHAAMKigogFADaAAAHAAMKigogFADaAAA1AAQKgTAAAgcACQpCIWQcADwDAAcACQpCIWQcADwDAAAA.',
Ov='Overhere:BAAANQAECgEIAQABNQAECgUIEgAJAAAAAA==.',
Pa='Pahpi:BAAANQAECggIBgAAAA==.Palcan:BAAANQAECgMIBgAAAA==.Pallyftw:BAAANQADCgQIBAAAAA==.Papii:BAAANQAECggICQAAAA==.Paratussum:BAAANQADCgYIBgAAAA==.Parka:BAABNQAECoEsAAIPAAkKuCT/AQDBAwAPAAkKuCT/AQDBAwAAAA==.Pattysmash:BAAANQAECgYICwABNQAFFAUIDgAVAGEYAA==.',
Pb='Pbody:BAAANQAECggIEwAAAA==.',
Pe='Perhorn:BAAANQAECgYICgAAAA==.',
Po='Pollywog:BAAANQADCgcIBwABNQAECgUICwAJAAAAAA==.Polunocnicá:BAABNQAECoEaAAIPAAcKDRtWKQAaAgAPAAcKDRtWKQAaAgAAAA==.Pooj:BAAANQADCggIFwAAAA==.',
Pr='Primehunter:BAABNQAECoEYAAIGAAkKNxQ2RwBwAgAGAAkKNxQ2RwBwAgAAAA==.Primetime:BAAANQAECgUICgAAAA==.Prissila:BAAANQAECgEIAQAAAA==.Prollimix:BAAANQAECgQICQAAAA==.',
Ps='Psychoshorts:BAABNQAECoEcAAIEAAgKmxaVcwAiAQAEAAgKmxaVcwAiAQAAAA==.Psykick:BAAANQADCgEIAQAAAA==.',
Py='Pyropoint:BAAANQAECgYIEAAAAA==.',
Ra='Rachela:BAAANQAECgEIAgAAAA==.Ractiel:BAAANQAECgIIAgAAAA==.Raidhero:BAAANQAECgUICAAAAA==.Rain:BAAANQAECgQIBAAAAA==.Raked:BAABNQAECoEeAAMjAAcK3Q80HwDBAQAjAAcK+w40HwDBAQAkAAYKPQszDgBAAQAAAA==.Ranfna:BAAANQADCggICQAAAA==.Rapidkiill:BAAANQADCgQICQAAAA==.Rapidly:BAAANQADCgUJBQAAAA==.Raspberrytea:BAAANQABCggIFwAAAA==.Raviolio:BAAANQAECgMIAwABNQAECgMIBQAJAAAAAA==.',
Re='Reebz:BAAANQADCgYJBwABNQADCgMIAwAJAAAAAA==.Reflection:BAABNQAECoEiAAIKAAgKGggEdACHAQAKAAgKGggEdACHAQAAAA==.Rekcutnerd:BAAANQAECgIIBAAAAA==.Reloran:BAAANQABCgIIAgAAAA==.Reppa:BAAANQAECgQIBAAAAA==.Resacharia:BAAANQADCgIIBAAAAA==.Retiniris:BAABNQAECoEmAAMGAAgKlyAkhADTAQAGAAgKlyAkhADTAQAbAAEKDQMjhwAnAAAAAA==.',
Rh='Rhonstaris:BAAANQAECgQICgAAAA==.Rhylintras:BAAANQADCgQIBwABNQAECgcIGgAKADITAA==.',
Ri='Riceporridge:BAAANQAECgYIEwAAAA==.Rinari:BAAANQAECgQICAABNQAECgkJQwAVAFgcAA==.Riptakeoff:BAAANQADCgcIBwABNQAECgkJGAAXAO0dAA==.Riskofrain:BAAANQAECgQIBwAAAA==.Ritzcarltina:BAAANQADCgQJBAAAAA==.Ritzu:BAAANQADCggICAABNQAECgQIBgAJAAAAAA==.',
Ro='Rockemi:BAAANQABCgMIAwAAAA==.Rodo:BAAANQAECgQIBAAAAA==.Roxyviper:BAAANQAECgQIDQAAAA==.Royalfox:BAABNQAECoEcAAIBAAgK2AmUFQBoAQABAAgK2AmUFQBoAQAAAA==.',
Ru='Rubbish:BAAANQAECgMIBAAAAA==.',
Sa='Saatari:BAAANQAECgEJAQAAAA==.Saddeath:BAAANQADCgYIBgAAAA==.Saeyeon:BAAANQAECgUICQABNQAFFAEIAQAJAAAAAA==.Saeylaura:BAAANQADCggIEwAAAA==.Saintchuck:BAAANQAECgMIBQAAAA==.Sainted:BAAANQADCggIEQAAAA==.Salanaar:BAABNQAECoEqAAIFAAkKtyEfCgBXAwAFAAkKtyEfCgBXAwAAAA==.Salarix:BAAANQAECgMIBAAAAA==.Sanarian:BAAANQADCgUIBQAAAA==.Sanctified:BAAANQAECggIAgAAAA==.Sarja:BAAANQAECgcIEgAAAA==.Sarras:BAAANQADCggIFwAAAA==.Sasserfrass:BAABNQAECoEZAAIWAAcKSCBNBgB3AgAWAAcKSCBNBgB3AgAAAA==.Savaant:BAAANQADCgIIAgAAAA==.Sawk:BAAANQAECgEIAQAAAA==.Sayy:BAABNQAECoEdAAMRAAgK5xoJfwBoAgARAAgK5xoJfwBoAgAWAAQKZxLhIADBAAAAAA==.',
Sc='Scaledrage:BAAANQAECgcIEwAAAA==.Schism:BAEBNQAECoEWAAIQAAYK9hxIUgAEAgAQAAYK9hxIUgAEAgABNQADCggIFQAJAAAAAA==.',
Se='Seaotter:BAABNQAECoEkAAIEAAgK3RWwQQDvAQAEAAgK3RWwQQDvAQAAAA==.Sellioni:BAAANQAECgUIBQABNQAECgkJHQARAB4hAA==.Senhonrue:BAAANQAECgEIAQAAAA==.Serabian:BAAANQADCgUIBQAAAA==.Seraz:BAABNQAECoErAAIoAAkKaRxLCQAAAwAoAAkKaRxLCQAAAwAAAA==.Seregios:BAAANQAECgQIBAABNQAECgkJHQARAB4hAA==.Serenitey:BAAANQAECgEIAQAAAA==.Serraglyndur:BAABNQAECoEcAAIQAAcKLSJGJgC4AgAQAAcKLSJGJgC4AgAAAA==.',
Sh='Shaderaina:BAAANQADCggIHwAAAA==.Shadowgame:BAAANQADCgQIBAAAAA==.Shadowglowz:BAAANQADCgEIAQAAAA==.Shambe:BAAANQADCgIIAgAAAA==.Shamidzi:BAAANQADCgQIBQAAAA==.Shamzuh:BAAANQADCggIEQAAAA==.Sheabutters:BAAANQAECgcIEgAAAA==.Shennequa:BAAANQABCgUIBwAAAA==.Shmorg:BAAANQAECgMIBQAAAA==.Shunaiman:BAABNQAECoEcAAIOAAcKzgn6mgBzAQAOAAcKzgn6mgBzAQAAAA==.Shàdowdànce:BAAANQADCgUIBwAAAA==.Shábam:BAAANQAECgUICgAAAA==.',
Si='Sifferr:BAAANQAECgUICwAAAA==.Sijinn:BAAANQADCgYIDAAAAA==.Silus:BAAANQAECgQIBAAAAA==.',
Sk='Skezes:BAAANQADCgYIBgAAAA==.Skotom:BAAANQAECgQIBwAAAA==.Skyjericho:BAAANQAECgMIBgAAAA==.',
Sl='Slann:BAAANQAECgYICwAAAA==.Slattpal:BAABNQAECoEeAAIQAAkKmyEsCwBgAwAQAAkKmyEsCwBgAwAAAA==.Sleebydruid:BAABNQAECoEZAAImAAkKbhP0GgA2AgAmAAkKbhP0GgA2AgAAAA==.Sleebyevoker:BAAANQAECgYIEgABNQAECgkJGQAmAG4TAA==.Slokelock:BAAANQADCgQIBAAAAA==.',
Sm='Smurghl:BAAANQAECggICwAAAA==.',
Sn='Snackysteak:BAAANQADCgYIBgAAAA==.',
So='Socinks:BAAANQADCgcIBwAAAA==.Solistome:BAAANQAECgEIAQAAAA==.Somarlar:BAAANQADCgMIAwAAAA==.Sopho:BAAANQAECgYIDAAAAA==.Sophogue:BAAANQADCgUIBQABNQAECgYIDAAJAAAAAA==.Sophomage:BAAANQADCgYJBgABNQAECgYIDAAJAAAAAA==.',
Sp='Specialtea:BAAANQAECgMIBQAAAA==.Speity:BAAANQAECgUIBQAAAA==.Spider:BAAANQADCgQICAAAAA==.',
Sq='Squam:BAAANQADCgcIBwABNQAECggIIAARAH4cAA==.',
St='Starzpapi:BAAANQABCgIIAgABNQAECgkJGAAXAO0dAA==.Stoli:BAAANQAECgIIAgAAAA==.Stonebones:BAAANQAECgYICwAAAA==.Strappy:BAAANQADCgcIBwAAAA==.Stwife:BAACNQAFFIEQAAQEAAYKNQ/qBwB4AQAEAAUKTA7qBwB4AQAPAAEKWxzyFQBQAAAFAAEKVxODKQA5AAA1AAQKgSUAAwQACQroGyckAJECAAQACQomGyckAJECAA8ABAoZFMddAN8AAAAA.Störmë:BAAANQADCgUICQAAAA==.',
Su='Sufrucia:BAAANQAECgcIEgAAAA==.Sunday:BAAANQAECgYIDgAAAA==.Sunhime:BAAANQAECgEIAQABNQAECgcIEwAJAAAAAA==.Surâ:BAABNQAECoEfAAIVAAkKsiPGBwB0AwAVAAkKsiPGBwB0AwAAAA==.',
Sy='Symbol:BAAANQAECgcJEgABNQAECggIIAARAH4cAA==.Sympissal:BAAANQAECgEIAgAAAA==.',
['Sò']='Sònya:BAABNQAECoEkAAIDAAgKTBDuXwDSAQADAAgKTBDuXwDSAQAAAA==.',
['Sÿ']='Sÿlvanas:BAAANQAECgQIBwAAAA==.',
Ta='Tabhunter:BAAANQADCgcIEwAAAA==.Tagritalth:BAAANQAECgEIAQABNQABCgMIAwAJAAAAAA==.Taindnddra:BAAANQADCgEIAQABNQAECgUICgAJAAAAAA==.Talanas:BAAANQADCggIBQAAAA==.Talenat:BAAANQAECgEIAQAAAA==.Tanishalfelf:BAACNQAFFIERAAMHAAYK5BzzBgC4AQAHAAQKOSPzBgC4AQAQAAIKrgQpHQCLAAA1AAQKgSgAAwcACQrqJrgDANgDAAcACQrqJrgDANgDABAACAriE21HACoCAAAA.Tankaman:BAAANQADCgQIDQABNQAECgQIDQAJAAAAAA==.',
Te='Tegalia:BAAANQAECgEIAQAAAA==.Telliah:BAAANQABCgEJAQAAAA==.Tempestre:BAAANQADCgMIAwAAAA==.Terrorfury:BAAANQADCgUICQAAAA==.Texoutlaw:BAAANQAECgEIAQAAAA==.',
Th='Thalassikos:BAAANQAECgEIAQABNQAECgUIBwAJAAAAAA==.Thatredhead:BAAANQADCgQJBAAAAA==.Thegremlin:BAAANQAECgIIBAAAAA==.Thewraith:BAAANQAECgQIBQAAAA==.Thorcised:BAABNQAECoEkAAIFAAgKKxagOAAEAgAFAAgKKxagOAAEAgAAAA==.Thorin:BAABNQAECoEdAAIHAAcKRR92VwBnAgAHAAcKRR92VwBnAgAAAA==.Thorym:BAAANQADCgUIBQABNQAECggIGQAcAC4dAA==.Thoryndir:BAABNQAECoEZAAIcAAgKLh1gIgCdAgAcAAgKLh1gIgCdAgAAAA==.Thrym:BAABNQAECoEjAAIPAAgKBCFwDwD4AgAPAAgKBCFwDwD4AgAAAA==.Thundernut:BAAANQADCggIEAAAAA==.',
Ti='Tidalsong:BAAANQAECgMIBQAAAA==.Tigercub:BAAANQADCgcIBwAAAA==.Tirillian:BAAANQADCgUIBQAAAA==.Tirionsson:BAAANQAECgEIAwAAAA==.Tirnoir:BAAANQADCgQIBgABNQAECgQIBAAJAAAAAA==.',
Tk='Tkenga:BAAANQAECgUICQAAAA==.',
To='Tojarm:BAAANQADCgEIAQAAAA==.Tonicdeath:BAAANQAECgQIDQAAAA==.Torr:BAAANQAECgIIAgAAAA==.Torshana:BAAANQADCgQIBQAAAA==.Totemgobbler:BAAANQAECgEIAQAAAA==.Totemlyfine:BAAANQAECgYIEgAAAA==.',
Tr='Tralzind:BAAANQADCgMIAwAAAA==.Truthsayer:BAABNQAECoEiAAIKAAgKEBpbQwA5AgAKAAgKEBpbQwA5AgAAAA==.',
Ts='Tsquared:BAABNQAECoEqAAMWAAgKhhkMBwBZAgAWAAgKhhkMBwBZAgARAAUKRwathgF6AAAAAA==.Tsukasa:BAAANQAFFAEIAQAAAA==.Tsuruchi:BAAANQAECggIBQAAAA==.',
Tu='Tukk:BAAANQAECgUIBQAAAA==.Tumnina:BAAANQADCgYICwAAAA==.',
Tw='Twiinkletoes:BAAANQAECgEIAQAAAA==.Twopuffs:BAAANQAECgYICwAAAA==.',
Ty='Tyce:BAABNQAECoEbAAMGAAcKshLzlwClAQAGAAcKshLzlwClAQAbAAEKdgd/ggAtAAAAAA==.Tylannis:BAAANQAECgYIEQAAAA==.',
Ug='Ugacoop:BAABNQAECoEoAAMOAAkKyyNbBwCDAwAOAAkKeyNbBwCDAwAXAAIK3h73QgCuAAAAAA==.',
Ut='Uthrick:BAAANQADCgYIBgAAAA==.',
Va='Vaelisara:BAAANQAECgYIDgAAAA==.Valkerr:BAAANQAECggIBgAAAA==.',
Ve='Vehe:BAAANQAECgcIEAAAAA==.Veldrys:BAAANQADCggIFgABNQAECggIHwAbAOEdAA==.Veledaa:BAAANQADCgYJFgAAAA==.Venomnips:BAAANQADCgQIBAAAAA==.Verige:BAAANQAECgQIBQAAAA==.Vesperbough:BAAANQABCgIIAgAAAA==.Vetis:BAAANQADCggIGQAAAA==.',
Vi='Vicars:BAAANQADCgYICwABNQAECgQIDAAJAAAAAA==.Vickos:BAAANQAECggIEQAAAA==.Viejosabroso:BAAANQAECgMIBAAAAA==.Vilyawen:BAAANQABCgIIBAAAAA==.Virgil:BAAANQADCgUICgABNQAECggIGgAGAGEXAA==.Visionblast:BAAANQADCgEIAQAAAA==.Visionlink:BAAANQADCgEIAQAAAA==.Vixyn:BAAANQADCgYIDQAAAA==.',
Vo='Voidme:BAAANQADCgEIAQABNQAECgUIDwAJAAAAAA==.Voidshift:BAAANQABCgMIAwAAAA==.Vorellyn:BAAANQAECgMIBAAAAA==.',
Vu='Vuuddon:BAAANQABCgQIBAAAAA==.',
Vy='Vyce:BAAANQAECgIIAgAAAA==.',
['Và']='Vàlorie:BAAANQAECgYICgABNQAFFAIIAwAJAAAAAA==.',
['Vè']='Vèlkhànà:BAABNQAECoEdAAIRAAkKHiFzKgAxAwARAAkKHiFzKgAxAwAAAA==.',
Wa='Wafflesneggs:BAAANQAECgEIAQAAAA==.Wangdaulf:BAAANQADCggIGAAAAA==.Wardoogy:BAAANQADCggICAAAAA==.Warexios:BAAANQADCgYICgAAAA==.Warglaíves:BAAANQADCgYICwABNQAECgkJJgAcAHMbAA==.Warradord:BAAANQAECgUICAABNQAECgkJKAAQAG4ZAA==.Warsmedic:BAABNQAECoEcAAIQAAgKXxD/WgDlAQAQAAgKXxD/WgDlAQAAAA==.',
We='Wevaren:BAAANQADCgQIBQAAAA==.',
Wh='Whumha:BAAANQADCgQIBAAAAA==.',
Wi='Wilbur:BAAANQADCggIDAAAAA==.Williams:BAEBNQAECoEvAAIEAAkKMiXwBQCMAwAEAAkKMiXwBQCMAwAAAA==.Williamsjr:BAEBNQAECoEsAAIIAAkKlR+iMgDhAgAIAAkKlR+iMgDhAgABNQAECgkJLwAEADIlAA==.Wilumi:BAAANQAECggIAQAAAA==.Winkel:BAAANQAECgMIAwAAAA==.',
Wo='Wolfyhuntres:BAAANQADCgQIBQAAAA==.Wolvesfor:BAAANQAECgIIBAABNQAECggIGgAYAHQYAA==.Woopiing:BAEANQADCggIFQAAAA==.Woubbie:BAAANQABCgIIAwAAAA==.',
Wu='Wuhpow:BAAANQADCgIIAgAAAA==.Wunna:BAABNQAECoEYAAIXAAkK7R1aAwAAAwAXAAkK7R1aAwAAAwAAAA==.',
['Wá']='Wármonger:BAAANQADCgIIAgAAAA==.',
['Wâ']='Wâfflezz:BAAANQAECgIIAQAAAA==.',
Xa='Xanístus:BAABNQAECoEZAAMSAAcK6BoGCwDxAQASAAYKZBsGCwDxAQAIAAcK4RGtkwDDAQAAAA==.',
Xe='Xeppa:BAABNQAECoEhAAQOAAkKZRoaKwDAAgAOAAkKZRoaKwDAAgAeAAcKlhRpCQDEAQAXAAEKpQp1cwA1AAAAAA==.',
Xi='Xionz:BAABNQAECoEWAAIOAAcKERnQawDzAQAOAAcKERnQawDzAQAAAA==.',
Xu='Xuji:BAAANQABCgIIAgAAAA==.',
Ya='Yakella:BAABNQAECoEjAAMVAAkKGx18EgAdAwAVAAkKGx18EgAdAwADAAQKJRhmnwAnAQAAAA==.',
Ye='Yelgrun:BAAANQAECgMIAwAAAA==.Yellcat:BAABNQAECoEqAAImAAgKeB3XEwCMAgAmAAgKeB3XEwCMAgAAAA==.',
Yh='Yhoda:BAABNQAECoElAAIGAAkKoxvFMAC4AgAGAAkKoxvFMAC4AgAAAA==.',
Yo='Yodä:BAAANQAECggICAAAAA==.Youseitgar:BAABNQAECoEcAAIEAAkKmxIaPQAGAgAEAAkKmxIaPQAGAgAAAA==.',
Yu='Yuisis:BAAANQAECgUIBQAAAA==.',
Za='Zabidu:BAABNQAECoEqAAMMAAkKtx5UBwADAwAMAAkKtx5UBwADAwANAAQK0xVHOgAKAQAAAA==.Zamp:BAAANQADCgUIBQAAAA==.Zappyketch:BAABNQAECoEfAAIDAAkK4RpGNgB4AgADAAkK4RpGNgB4AgAAAA==.Zaraeiri:BAAANQADCgUIBQAAAA==.Zaraxaà:BAAANQAECgMJAwABNQAECgkJLgAGAI4fAA==.',
Ze='Zelenã:BAAANQAECgYICgAAAA==.Zelun:BAABNQAECoEpAAMVAAkKQxzsLACKAgAVAAgKpR3sLACKAgADAAYK2BSpdACTAQAAAA==.Zephon:BAABNQAECoEnAAMCAAkKfSApDQApAwACAAkKdCApDQApAwAZAAcKkRshJQD+AQAAAA==.',
Zi='Ziggley:BAAANQADCgYIBgABNQAECggIHwAhAOwRAA==.',
Zo='Zombiemarj:BAAANQADCggIIQABNQAECgcIGAAGAAQcAA==.',
['Zé']='Zéd:BAABNQAECoEeAAIGAAcKmSCpPgCKAgAGAAcKmSCpPgCKAgAAAA==.',
['Âx']='Âxel:BAAANQAECgUIBQABNQAECggIIAACALweAA==.',
['Æd']='Ædisgrace:BAAANQAECgEIAgAAAA==.',
['Æm']='Æmon:BAAANQAECgEIAQAAAA==.',
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
