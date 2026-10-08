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

local lookup = {'DeathKnight-Unholy','DeathKnight-Frost','Druid-Balance','DemonHunter-Devourer','Unknown-Unknown','Paladin-Retribution','Paladin-Holy','Warlock-Affliction','Mage-Arcane','DeathKnight-Blood','Hunter-BeastMastery','Rogue-Assassination','DemonHunter-Vengeance','Priest-Holy','Warlock-Demonology','Warlock-Destruction','DemonHunter-Havoc','Evoker-Augmentation','Evoker-Devastation','Monk-Windwalker','Monk-Brewmaster','Warrior-Arms','Warrior-Fury','Shaman-Restoration','Shaman-Elemental','Druid-Feral','Shaman-Enhancement','Druid-Restoration','Mage-Frost','Monk-Mistweaver','Warrior-Protection','Priest-Shadow','Paladin-Protection',}
local provider = {region='US',realm="Quel'dorei",name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abiotic:BAAANQADCgQIBQAAAA==.',
Ac='Acaleus:BAAANQAECgQIBAAAAA==.',
Ad='Adric:BAAANQAECgUIDAAAAA==.Aduhgall:BAAANQADCgcIDQAAAA==.',
Ah='Ahnji:BAAANQADCgMIBAAAAA==.',
Ai='Aings:BAABNQAECoEmAAMBAAgK2SO5FgDtAgABAAgKIiK5FgDtAgACAAcKQiKEGQCYAgAAAA==.Airbubble:BAAANQABCgEIAQAAAA==.Aiydaen:BAAANQADCgQIAwAAAA==.Aiytan:BAAANQADCgMIAwAAAA==.',
Al='Alarus:BAABNQAECoEsAAIDAAgKFhkfKwBdAgADAAgKFhkfKwBdAgAAAA==.Alex:BAABNQAECoEgAAIEAAgKwRSeHwA0AgAEAAgKwRSeHwA0AgAAAA==.Alivathor:BAAANQAECgIIAgABNQAECgYIDgAFAAAAAA==.Allypally:BAABNQAECoEZAAIGAAgKLAuLpgCbAQAGAAgKLAuLpgCbAQAAAA==.',
Am='Amgrod:BAEANQADCgUJBQAAAA==.Amway:BAAANQAECgQICAAAAA==.',
An='Andaarian:BAAANQADCgUIBQAAAA==.Andeyn:BAAANQADCgQIBQAAAA==.Angelkitty:BAAANQADCgYIBgAAAA==.',
Ap='Apophiz:BAAANQADCgYIBgAAAA==.',
Ar='Arcadius:BAAANQADCgIIAgAAAA==.Ardur:BAAANQADCgUIBQAAAA==.Aremis:BAAANQAECgQICQAAAA==.Arkhitype:BAAANQAECgYIEgAAAA==.Aryadel:BAAANQABCgQIBAAAAA==.Aryahi:BAAANQAECggIAQAAAA==.',
As='Ashyslashy:BAAANQAECgcIEAAAAA==.Asur:BAAANQAECgYIEQAAAA==.',
Au='Auracorusca:BAABNQAECoEWAAIHAAgKpx79IQDOAgAHAAgKpx79IQDOAgAAAA==.Auris:BAAANQADCgQIBAAAAA==.',
Ay='Aydain:BAAANQADCgQIBAAAAA==.Aynilith:BAAANQAECgYIDQAAAA==.',
Ba='Bajr:BAAANQAECgcIDQAAAA==.Bakura:BAABNQAECoEhAAIIAAgKMRzXAwCSAgAIAAgKMRzXAwCSAgAAAA==.Banker:BAABNQAECoEbAAIEAAcKIQrHMwB+AQAEAAcKIQrHMwB+AQAAAA==.Baroo:BAAANQADCgcIJQAAAA==.Barudd:BAAANQABCgQIBAAAAA==.',
Be='Berko:BAABNQAECoE4AAIJAAgKSR8ZbACRAgAJAAgKSR8ZbACRAgAAAA==.Beyorne:BAAANQAECgEIAQAAAA==.',
Bh='Bhaang:BAAANQAECgQIBgAAAA==.',
Bi='Bigbear:BAAANQADCgYIBgABNQAECggIJQAKAColAA==.Bigbill:BAAANQAECgIIAgAAAA==.Bigdeath:BAAANQAECgUIEwAAAA==.Biletooth:BAAANQADCgcICgABNQAECgMICAAFAAAAAA==.Bizco:BAABNQAECoEbAAILAAcKfRpVYAAsAgALAAcKfRpVYAAsAgAAAA==.',
Bj='Bjebo:BAABNQAECoEmAAIDAAgKNw5zQwC6AQADAAgKNw5zQwC6AQAAAA==.',
Bl='Bluffshot:BAABNQAECoEeAAIMAAgKdB/tEQDNAgAMAAgKdB/tEQDNAgAAAA==.',
Br='Brutes:BAAANQADCggICAABNQAFFAMIBgACAJsgAA==.Brynjalf:BAAANQAECgQIBwAAAA==.Bràe:BAAANQABCgMIAQAAAA==.',
Bx='Bxck:BAAANQAECgEIAQAAAA==.',
['Bï']='Bïcho:BAAANQAFFAEIAQAAAA==.',
Ca='Calambar:BAAANQADCgYIBgAAAA==.Cascadio:BAAANQAECgEIAQAAAA==.Castanza:BAAANQADCgQIBwAAAA==.Caswyn:BAAANQAECgQIBwAAAA==.',
Ch='Charjer:BAAANQAECgYIEgAAAA==.Chillwolf:BAAANQABCgIIAgAAAA==.Chokengag:BAAANQADCgMIAwAAAA==.Choney:BAAANQAECgQIBgAAAA==.',
Co='Codedgar:BAAANQADCgUIBQABNQAECgcIDwAFAAAAAA==.Coffeeshot:BAAANQADCgYIBgAAAA==.Cojostudio:BAAANQADCggICAAAAA==.Comboost:BAAANQAECgEIAQAAAA==.Costcolshirt:BAAANQADCgMIAwAAAA==.',
Cr='Cranks:BAAANQADCggICAAAAA==.Crashcake:BAABNQAECoEbAAICAAkKmR1lFADIAgACAAkKmR1lFADIAgAAAA==.Creakybones:BAAANQABCgIIAgAAAA==.Croager:BAAANQAECgcIDwAAAA==.',
Cu='Cup:BAABNQAECoEaAAIHAAcKHRSfYwDIAQAHAAcKHRSfYwDIAQAAAA==.',
Cv='Cvv:BAAANQADCgQIBAABNQAECgMIAwAFAAAAAA==.',
Cy='Cyberlinde:BAAANQAECgQIBAAAAA==.Cywen:BAAANQADCggJCAABNQAFFAUIDwAMAC8bAA==.',
Da='Daelaris:BAABNQAECoEaAAIJAAgKYh9VVADHAgAJAAgKYh9VVADHAgAAAA==.Damonoris:BAAANQAECgYIDQAAAA==.Damthrax:BAAANQAECgQIBQAAAA==.Danielan:BAAANQAECgUIBQAAAA==.Davegrôwl:BAAANQADCgEJAQABNQAECgMICAAFAAAAAA==.',
De='Deadair:BAAANQADCgMIAwAAAA==.Deadlyalba:BAAANQADCgYIBgAAAA==.Deadzeo:BAAANQADCgYICQAAAA==.Dejavoid:BAAANQADCggICgAAAA==.Demonblades:BAABNQAECoEeAAIEAAgKdBgTGwBjAgAEAAgKdBgTGwBjAgAAAA==.Demonbreaker:BAABNQAECoEcAAINAAgKhxV6CgADAgANAAgKhxV6CgADAgAAAA==.Denarten:BAABNQAECoEeAAIGAAkKeyGZIQAlAwAGAAkKeyGZIQAlAwAAAA==.',
Di='Diotima:BAAANQADCgUICQAAAA==.Dirtymorris:BAAANQAECgcIEQAAAA==.Disrupt:BAAANQAECgQIBQAAAA==.',
Do='Dockevorkian:BAABNQAECoEsAAIOAAkKMSHxEAArAwAOAAkKMSHxEAArAwAAAA==.Dornaaealdor:BAAANQADCgIIAgAAAA==.Dortwaz:BAABNQAECoEiAAMPAAgKbhfUaQD5AQAPAAcKOxfUaQD5AQAQAAIKlhUlUACDAAAAAA==.Doublebonus:BAAANQADCggICAABNQAFFAMIBgACAJsgAA==.Dougdk:BAABNQAECoElAAIKAAgKKiVOCwBKAwAKAAgKKiVOCwBKAwAAAA==.',
Dr='Dracoz:BAAANQADCgEIAQAAAA==.Dricex:BAAANQADCgYIBgABNQAECgIIAgAFAAAAAA==.Drinnagon:BAAANQADCgcIBwABNQAECgkJHgAGAHshAA==.Drinntellect:BAAANQAECgMIAwABNQAECgkJHgAGAHshAA==.Drinnundead:BAAANQADCgEIAQABNQAECgkJHgAGAHshAA==.Druelf:BAAANQADCgUIBQAAAA==.Dryblood:BAAANQADCgQIBAAAAA==.Dryx:BAAANQAECgIIAgAAAA==.',
Du='Dunaarn:BAAANQADCgMIAwAAAA==.',
Ea='Eargroan:BAAANQADCgYICwABNQAECgkJGwANAPUjAA==.',
El='Elilla:BAAANQAECgYIEgAAAA==.Elkminster:BAAANQAECgIIAgAAAA==.Ellenaya:BAAANQAECggIDQAAAA==.Elorela:BAAANQADCgQIBAABNQAECgUIDAAFAAAAAA==.',
En='Enjoy:BAACNQAFFIEGAAICAAMKmyBLCQAFAQACAAMKmyBLCQAFAQA1AAQKgSYAAwIACQo9JYkEAIkDAAIACQrVJIkEAIkDAAEACQrtInYgAKkCAAAA.',
Fa='Famiki:BAAANQADCgcICwAAAA==.',
Fe='Felnollid:BAABNQAECoEjAAMRAAkKcRvuGQCoAgARAAkK7RruGQCoAgAEAAUKiw0kRAD7AAAAAA==.Fenanigans:BAABNQAECoEfAAIMAAkKviCwCwARAwAMAAkKviCwCwARAwAAAA==.Fenquisition:BAAANQADCggICAABNQAECgkJHwAMAL4gAA==.',
Fi='Firebender:BAAANQADCgQIBQAAAA==.Firetiger:BAAANQADCgcIBwAAAA==.Fistandcider:BAAANQADCgMIAwAAAA==.',
Fl='Fluffyhusky:BAABNQAECoEbAAMSAAcKlAa5EwDJAAATAAcKBQQjJQD0AAASAAUKvQi5EwDJAAAAAA==.',
Fo='Fontss:BAAANQAECgYIBwAAAA==.Fonyfish:BAAANQAFFAQIBAAAAA==.',
Fu='Fubina:BAEBNQAECoEqAAMUAAkKuxueDgDbAgAUAAkKuxueDgDbAgAVAAIK5R1pIgCgAAAAAA==.',
Fy='Fyjalla:BAAANQADCggIEAAAAA==.',
['Fâ']='Fâllênknîght:BAAANQAECgYIDgAAAA==.',
Ga='Gabh:BAAANQADCgYIBgAAAA==.',
Gi='Gilgaglaive:BAABNQAECoEYAAIEAAkKBxbgFgCRAgAEAAkKBxbgFgCRAgAAAA==.Gilgämesh:BAACNQAFFIEKAAIWAAUKsQ6+EAB+AQAWAAUKsQ6+EAB+AQA1AAQKgSgAAxYACQr6IYYnAAsDABYACQr6IYYnAAsDABcAAQr9HO4mAFUAAAAA.',
Gl='Glomah:BAABNQAECoEeAAIKAAgKtiIREAAaAwAKAAgKtiIREAAaAwAAAA==.Glorm:BAABNQAECoEgAAIYAAgKzBABZQCuAQAYAAgKzBABZQCuAQAAAA==.',
Go='Gobropro:BAAANQADCgYIBgAAAA==.Gorathan:BAAANQADCgMIAwAAAA==.',
Gr='Grabbyhands:BAAANQAECgMICAAAAA==.Grantul:BAABNQAECoEeAAIXAAcK9xaTCgD7AQAXAAcK9xaTCgD7AQAAAA==.Grimthore:BAAANQADCgUICgABNQAECgcIDAAFAAAAAA==.Grolgan:BAAANQADCgYIBgAAAA==.Gromz:BAAANQAECgcICQAAAA==.',
Gu='Gulbhang:BAABNQAECoEiAAMPAAgK2R4CKQDIAgAPAAgK2R4CKQDIAgAQAAEKXA/XbwA5AAAAAA==.',
Hb='Hbkdx:BAAANQAECgUIBQAAAA==.',
He='Health:BAAANQAECgMIAwAAAA==.',
Ho='Holdi:BAAANQADCgYIBgABNQAECggIHwAGAJEQAA==.Holyhammer:BAAANQAECgYIBgAAAA==.Holyoke:BAAANQADCgEIAQAAAA==.',
Hu='Hujo:BAAANQAECgcIEQAAAA==.Hushpupi:BAAANQAECgUIDAAAAA==.Huskerpower:BAAANQADCgcJDQAAAA==.',
Ic='Iceharted:BAAANQADCgEIAQAAAA==.Icesloth:BAABNQAECoEWAAIZAAgK2hYxQwA9AgAZAAgK2hYxQwA9AgAAAA==.',
Id='Idamarie:BAAANQAECgUICwAAAA==.Iduun:BAAANQADCgEIAQAAAA==.',
Il='Iladelle:BAAANQAECgYIDQAAAA==.',
In='Indecisa:BAAANQADCgUIBQAAAA==.',
Io='Iorak:BAAANQADCgEIAQAAAA==.',
Ir='Irinon:BAAANQADCgcIDAAAAA==.',
Ix='Ixiya:BAAANQADCgQIBwAAAA==.',
Ja='Jafuds:BAAANQAECgcIBwABNQAFFAUIEAAKAPoZAA==.Jaggerss:BAAANQAECgEIAQABNQAFFAMIBgACAJsgAA==.Jamaican:BAAANQADCgYIEAAAAA==.Jaste:BAAANQAECgYICwAAAA==.',
Ji='Jimit:BAAANQADCgcIBwAAAA==.Jimmym:BAAANQAECgQICAAAAA==.Jirakaidae:BAAANQADCgYICwABNQAECgQICQAFAAAAAA==.',
Jo='Jordis:BAAANQADCgMIAwAAAA==.',
Ju='Juju:BAAANQAECgEIAQAAAA==.',
Ka='Kaedeyn:BAAANQADCgEIAQAAAA==.Kaeltharon:BAAANQADCgQIAwAAAA==.Kamekaze:BAAANQADCgYIBgAAAA==.Kandrys:BAAANQADCgQIBAAAAA==.Kasgotojim:BAAANQAECgQIBAAAAA==.Kaypop:BAAANQADCggICAAAAA==.Kayy:BAAANQADCgIIAgAAAA==.',
Ke='Kerrster:BAAANQADCgQIBAAAAA==.',
Kh='Khármá:BAAANQAECgcICgAAAA==.',
Ki='Kicklocks:BAAANQAECgEIAQAAAA==.Kikuri:BAAANQAECgYICgAAAA==.Killt:BAAANQAECgYIDAAAAA==.',
Ko='Koojoé:BAAANQAECgQIBQAAAA==.',
Ku='Kurzulan:BAAANQAECgcIEQAAAA==.',
La='Laghles:BAABNQAECoEtAAILAAgKSyFlKQDTAgALAAgKSyFlKQDTAgAAAA==.Laroes:BAAANQAECgEIAQABNQAECggIHgAKALYiAA==.Larua:BAAANQABCgQJBAAAAA==.',
Le='Lemanjá:BAAANQAECgQIBgAAAA==.',
Li='Lightlooter:BAAANQADCgYIBgAAAA==.Liliane:BAAANQAECgYIDgAAAA==.Limbless:BAAANQAECgUICQAAAA==.',
Lo='Loahealth:BAAANQAECgcIDwAAAA==.Lockrocks:BAABNQAECoEeAAQIAAgKOhOICwCIAQAPAAcKGw5TigCeAQAIAAYK1BGICwCIAQAQAAUKgwwELQAOAQABNQAECgcIDAAFAAAAAA==.Lockstar:BAAANQADCgYICgAAAA==.Loko:BAAANQAECgcIBwAAAA==.Lontra:BAAANQADCgUIDAAAAA==.Loozer:BAAANQAECgcIDAAAAA==.Loralast:BAAANQADCgQIBAAAAA==.',
Lu='Luzifer:BAAANQADCgYIBgAAAA==.',
Ma='Magelyman:BAAANQAECgYIDAAAAA==.Mahlaan:BAABNQAECoElAAIKAAgKDhmFLQBEAgAKAAgKDhmFLQBEAgAAAA==.Malakai:BAAANQADCgIIAgABNQAECgUICQAFAAAAAA==.Malekai:BAAANQAECgUJCAABNQAECgUICQAFAAAAAA==.Malyce:BAAANQAECgMIAwABNQAECgUICQAFAAAAAA==.Malzen:BAAANQADCgMIAwABNQAECgUICQAFAAAAAA==.Manaleia:BAAANQADCggIDAAAAA==.Manasolid:BAAANQADCgEIAQAAAA==.Mar:BAAANQAECgIIAgAAAA==.Maruug:BAAANQADCgYIBgAAAA==.Marvinah:BAAANQAECgIIBwAAAA==.Maydie:BAAANQAECgEIAQAAAA==.',
Me='Meatcurtin:BAAANQADCgQICAAAAA==.Meatlover:BAAANQAECgUJCAAAAA==.Mediocre:BAABNQAECoEWAAIaAAcKDh8cCQCHAgAaAAcKDh8cCQCHAgAAAA==.Meeshka:BAAANQAECgUIDQAAAA==.Meraleona:BAAANQAECgcICgAAAA==.Methslinger:BAAANQAECgQIBwAAAA==.',
Mi='Migue:BAAANQABCgEIAgABNQAECgkJPAAGAL4iAA==.Miltonroe:BAAANQADCggICAABNQAECggIJQAbAFcNAA==.',
Mo='Moarass:BAAANQAECgQJBgABNQAECgcIGgAcACsWAA==.Moris:BAAANQAECgUICwAAAA==.Mortmuzi:BAAANQADCgYJBwAAAA==.Mosrael:BAAANQAECggIDAAAAA==.',
Ms='Mswizzlë:BAAANQAECgYICgAAAA==.',
Mu='Muldah:BAABNQAECoEnAAMJAAgKcxYBkABEAgAJAAgKQBUBkABEAgAdAAcKqQpkGAAPAQAAAA==.',
Na='Nas:BAAANQAECgYIEwAAAA==.Nausicaa:BAAANQABCgYICQAAAA==.Nausicaä:BAAANQADCgUIBQAAAA==.Navie:BAAANQAECgYIDwAAAA==.Nazgûl:BAAANQABCgYIBAAAAA==.',
Ne='Nekros:BAAANQADCgcIBwABNQAECgYIEgAFAAAAAA==.Neø:BAABNQAECoEfAAMCAAgKXhiSMwDTAQACAAcKNhaSMwDTAQABAAYKQhs1UwCdAQAAAA==.',
Ni='Nicebud:BAAANQAECgEIAQAAAA==.Nightsfury:BAAANQAECgQIBAAAAA==.Nightshala:BAAANQAECgQIBAAAAA==.',
No='Nollid:BAAANQADCgYIBgABNQAECgkJIwARAHEbAA==.Nornyr:BAAANQADCgEIAQAAAA==.',
Nu='Nunsrsus:BAAANQAECgcIDwAAAA==.',
Ny='Nymerias:BAAANQADCgYJDgAAAA==.Nyrrah:BAAANQAECgQIBQAAAA==.',
['Ná']='Nácht:BAAANQAECgIIAgAAAA==.',
['Ný']='Nýghtmyst:BAAANQAECgEJAQAAAA==.',
Ok='Oku:BAAANQADCgUIBQAAAA==.',
Om='Omaticaya:BAABNQAECoEgAAIDAAcKeAr7VQBVAQADAAcKeAr7VQBVAQAAAA==.Omèn:BAAANQADCgUIBQAAAA==.',
Op='Optikon:BAAANQAECgUIDAAAAA==.',
Or='Oriax:BAAANQAECgIIAgABNQAECggILAADABYZAA==.',
Ow='Owlbearcat:BAAANQAECgYIDQABNQAECgcIDwAFAAAAAA==.',
Pa='Packerssuck:BAAANQADCgEIAQAAAA==.Paean:BAAANQADCgYIGQAAAA==.Paj:BAABNQAECoEiAAIJAAkKmB9jHABcAwAJAAkKmB9jHABcAwAAAA==.',
Pe='Pelledrusil:BAAANQADCgUIBQAAAA==.Peria:BAAANQADCgYIBgAAAA==.',
Pk='Pkalygos:BAAANQAECgYIDQAAAA==.',
Pl='Pleione:BAAANQAECgUICQAAAA==.',
Po='Portadave:BAAANQADCgYICQAAAA==.Powerstrokee:BAAANQAECgEIAgAAAA==.',
Pr='Preyforme:BAABNQAECoEdAAILAAgKUQgSgwDWAQALAAgKUQgSgwDWAQAAAA==.Prusik:BAAANQADCgcIBwABNQAECgMIAwAFAAAAAA==.',
Ps='Psychelone:BAAANQADCggIDgAAAA==.',
Pu='Puffshot:BAAANQAECgEIAQABNQAECggIHgAMAHQfAA==.',
Qu='Quillan:BAAANQADCgUIDQABNQAECgcIDwAFAAAAAA==.',
Qy='Qyxh:BAAANQAECgYIEgAAAA==.',
Ra='Raine:BAAANQADCggIEAAAAA==.Rannath:BAAANQAECggIAwABNQAECggIDAAFAAAAAA==.Rastafarian:BAAANQADCgUICQAAAA==.',
Re='Redeye:BAAANQAECgEIAQAAAA==.Rehne:BAAANQAECgEJAQAAAA==.Rexhavoc:BAABNQAECoEXAAIEAAgKARH7IwAHAgAEAAgKARH7IwAHAgAAAA==.Rexion:BAAANQAECgEIAQAAAA==.',
Ri='Rigormortits:BAAANQAECgQIBAAAAA==.Ripre:BAAANQADCgUICwAAAA==.',
Ro='Rosary:BAAANQAECgYIEgAAAA==.Rosewoodren:BAAANQADCgcICwAAAA==.',
Ru='Ruint:BAAANQADCgUIBQAAAA==.Runeclad:BAAANQAECgYIDgAAAA==.',
Ry='Ryla:BAAANQADCgIIAgABNQAECgcIGwAMAKkaAA==.',
['Rï']='Rïvkah:BAAANQADCgUIBwABNQAECgQIBQAFAAAAAA==.',
Sa='Saauurrora:BAAANQADCgYIBgAAAA==.Saintshift:BAAANQADCgEJAQABNQAECgMIAwAFAAAAAA==.Salitheion:BAAANQAECgIIAgAAAA==.Sapper:BAABNQAECoEqAAIeAAkKXR6DBwD/AgAeAAkKXR6DBwD/AgAAAA==.Sarn:BAAANQADCggICAAAAA==.Sathi:BAAANQAECgIIAQAAAA==.Sayuri:BAAANQADCgEIAQAAAA==.',
Se='Sennest:BAAANQADCgUIAwAAAA==.',
Sh='Shikí:BAAANQAECgEIAgAAAA==.Shladoran:BAAANQAECgUIEQAAAA==.Shos:BAABNQAECoEeAAIfAAkKuxxzBwDAAgAfAAkKuxxzBwDAAgAAAA==.',
Si='Siberianwolf:BAAANQAECgEIAQAAAA==.Sinnister:BAAANQADCgYIBgAAAA==.',
Sk='Skully:BAAANQADCgUIBQABNQAECggIJQAKAColAA==.',
Sl='Sledge:BAAANQADCgMIAwAAAA==.',
Sn='Snapdragyn:BAAANQADCggIBgAAAA==.Snorina:BAABNQAECoEkAAIgAAgKCiBBEADZAgAgAAgKCiBBEADZAgAAAA==.',
So='Solàrflàré:BAAANQADCgMIAwAAAA==.Sosgoraan:BAAANQADCgcJBwAAAA==.Sosozen:BAAANQAECgYIEgAAAA==.Soul:BAAANQAECgYICAAAAA==.',
Sp='Spirittoast:BAAANQAECgEIAQAAAA==.',
Sr='Sriman:BAAANQAECgYIBgAAAA==.',
St='Starkiller:BAAANQADCgYIDgAAAA==.Stonesolid:BAABNQAECoEfAAIWAAcKzBjvbwAjAgAWAAcKzBjvbwAjAgAAAA==.Stratovarius:BAAANQADCgYIBgAAAA==.',
Su='Sugouri:BAAANQAECggICAAAAA==.Supremacy:BAABNQAECoEZAAMPAAgKXyWDHQD5AgAPAAcK4iWDHQD5AgAQAAEKzSGwXQBhAAAAAA==.',
Sw='Sweetspot:BAAANQAECgcIDAABNQAECgcIDAAFAAAAAA==.Swiftshammy:BAAANQADCgQIBAAAAA==.Swytch:BAABNQAECoEbAAIMAAcKqRohJgAsAgAMAAcKqRohJgAsAgAAAA==.',
Sy='Sylrytherin:BAAANQADCgYICgABNQAECggIJAAgAAogAA==.Sylvii:BAABNQAECoEkAAIcAAgKqBKlIwDbAQAcAAgKqBKlIwDbAQAAAA==.',
Ta='Tabor:BAAANQAECgQIBQAAAA==.Taggz:BAAANQABCgQIBAAAAA==.Taladryn:BAAANQADCgcIDQAAAA==.Tarahly:BAABNQAECoEUAAIHAAYK+yGSPgBMAgAHAAYK+yGSPgBMAgAAAA==.Tauryel:BAAANQAECgIIAwABNQAECgUICQAFAAAAAA==.',
Te='Tekhan:BAAANQADCgQIBAAAAA==.Tethlis:BAAANQADCggICAABNQAECgcIBwAFAAAAAA==.',
Th='Thasarias:BAAANQAECgUIBwAAAA==.Themoosifer:BAACNQAFFIEWAAIEAAcKyxhiAQB9AgAEAAcKyxhiAQB9AgA1AAQKgSQAAgQACQqXIt8MAAcDAAQACQqXIt8MAAcDAAAA.Thyck:BAABNQAECoEbAAILAAgKIRMYXAA3AgALAAgKIRMYXAA3AgAAAA==.Thydis:BAABNQAECoEmAAIGAAkKRAu1kwDIAQAGAAkKRAu1kwDIAQAAAA==.',
Ti='Tiancit:BAAANQADCgEIAQAAAA==.Tibbs:BAABNQAECoEeAAMTAAgKxhF8FADmAQATAAgKKRF8FADmAQASAAYKzRB3DgAxAQAAAA==.Ticklepickle:BAAANQAECgQICAAAAA==.',
To='Tooch:BAAANQADCggICAAAAA==.',
Tr='Trumalice:BAAANQADCgQICgAAAA==.',
Un='Uncorrupted:BAABNQAECoEdAAMhAAkK6BKDIgChAQAhAAgK+BSDIgChAQAGAAIKigRoegExAAAAAA==.',
Up='Updog:BAAANQAECgEIAQABNQAECgQICAAFAAAAAA==.',
Va='Vaelm:BAAANQADCgIIAwAAAA==.Valericia:BAAANQADCgQIBAAAAA==.Valindrux:BAAANQAECgYIEAAAAA==.Valjin:BAAANQADCgQIBAABNQAECgYIEAAFAAAAAA==.Valuryan:BAAANQADCggIEAABNQAECgYIEAAFAAAAAA==.',
Ve='Velathila:BAAANQAECgEIAgAAAA==.',
Vi='Violêt:BAAANQADCgYIBgAAAA==.Vizzelok:BAAANQAECgYIEAAAAA==.',
Vo='Voidchris:BAABNQAECoElAAMEAAgKix7qEgC9AgAEAAgKix7qEgC9AgARAAEKOgdthgAuAAAAAA==.Voidormu:BAAANQAECgEIAQAAAA==.',
Wa='Warelf:BAAANQAECggIEwAAAA==.Warleck:BAAANQAECgEIAQAAAA==.',
Wh='Whodey:BAAANQAECgUICQAAAA==.',
Wi='Wisp:BAAANQADCgYIDwAAAA==.',
Wy='Wylia:BAAANQAECgQIBQAAAA==.',
Xc='Xcw:BAAANQAECgIIAgAAAA==.',
Yy='Yyirium:BAAANQADCgIIAgAAAA==.',
Za='Zakkmorris:BAAANQADCgEIAQAAAA==.Zakuren:BAABNQAECoEnAAILAAgK7g/cZwAZAgALAAgK7g/cZwAZAgAAAA==.',
Zi='Ziggi:BAAANQADCgYIBgABNQAECgMIAwAFAAAAAA==.',
Zo='Zondoul:BAAANQADCgYIBgAAAA==.',
Zu='Zuldave:BAABNQAECoEZAAIYAAcKxxebUgDvAQAYAAcKxxebUgDvAQAAAA==.',
Zy='Zylera:BAAANQAECgIIAgAAAA==.Zyphor:BAAANQADCggICAAAAA==.Zyth:BAAANQABCgMIAgAAAA==.',
['Ñî']='Ñîx:BAAANQAECgYIEgAAAA==.',
['Ød']='Ødinson:BAAANQAECgEJAQAAAA==.',
['ßæ']='ßær:BAAANQAECgIJAgAAAA==.',
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
