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

local lookup = {'Unknown-Unknown','Mage-Arcane','Shaman-Elemental','Rogue-Assassination','Rogue-Outlaw','Shaman-Restoration','Monk-Mistweaver','Druid-Guardian','DeathKnight-Frost','Priest-Shadow','DeathKnight-Unholy','Priest-Holy','Warrior-Arms','Warrior-Fury','Paladin-Holy','Hunter-BeastMastery','Hunter-Marksmanship','Evoker-Preservation','Evoker-Devastation','DemonHunter-Devourer','DemonHunter-Havoc','DeathKnight-Blood','Monk-Windwalker',}
local provider = {region='US',realm='Azgalor',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aaradh:BAAANQAECgYIDgAAAA==.Aaradk:BAAANQAECgQICQABNQAECgYIDgABAAAAAA==.Aarahunt:BAAANQAECgIIAgABNQAECgYIDgABAAAAAA==.',
Ab='Abaddondk:BAAANQAECgYIBgAAAA==.Abilify:BAAANQABCgcIFQAAAA==.Abnaruk:BAAANQAECgEIAQAAAA==.',
Ac='Acez:BAAANQAECggIEAAAAA==.',
Ad='Addilynn:BAAANQADCgEIAQAAAA==.Adoriah:BAAANQADCgYICwAAAA==.Adsaw:BAAANQAECgYICQAAAA==.',
Ae='Aelania:BAAANQADCggICQAAAA==.Aelunara:BAAANQAECgUIDAAAAA==.Aemoz:BAAANQADCgcICgAAAA==.',
Af='Aftershocks:BAAANQAECgEIAQAAAA==.',
Ag='Agh:BAAANQAECgQIBgAAAA==.',
Ai='Ailric:BAAANQAECgEIAgAAAA==.',
Al='Alarakian:BAAANQADCggIDAAAAA==.Alexei:BAAANQAECgIIAgAAAA==.Aliakin:BAAANQAECgMIBAAAAA==.Alistarburns:BAAANQAECgYIDgAAAA==.Alkhan:BAAANQAECgQIBQABNQAECggIFgACABcMAA==.Alteredbeest:BAAANQADCgQIBAAAAA==.Altos:BAAANQAECgcIEwAAAA==.Alyssachik:BAAANQADCgcIDAAAAA==.',
Am='Amarxd:BAABNQAECoEZAAIDAAkJQSCICQBXAwADAAkJQSCICQBXAwAAAA==.Amdabear:BAAANQADCgcIDAAAAA==.',
An='Angerclaw:BAAANQAECgQIBAAAAA==.Ankaramessi:BAAANQADCgQIBQAAAA==.',
Ap='Apotheke:BAAANQAECggIAQAAAA==.',
Aq='Aquaria:BAAANQADCggICAAAAA==.',
Ar='Arakisa:BAAANQADCgMIAwAAAA==.Arcanemagik:BAAANQADCggIFAAAAA==.Arcanmage:BAAANQAECgUIDQAAAA==.Arcanofrosty:BAAANQAECgEIAQAAAA==.Aresascends:BAAANQADCgUIBQAAAA==.Arinthe:BAAANQADCgQIBAAAAA==.',
At='Atalmon:BAAANQAECgMIBAAAAA==.',
Au='Aurochi:BAAANQADCgMIAwAAAA==.',
Av='Avastin:BAAANQADCgcICgAAAA==.',
Aw='Awni:BAAANQAECgQICgAAAA==.',
Ba='Bacon:BAAANQAECgYICgAAAA==.Badonkadonkk:BAAANQABCgIIAgAAAA==.Bahbahr:BAAANQAECgYIDAAAAA==.Baknow:BAAANQAECgEIAQAAAA==.Bambuu:BAAANQABCgYIBgAAAA==.Bangbangji:BAAANQAECgUICQABNQAECgkJGgAEANUYAA==.Bantum:BAAANQADCggICAAAAA==.Bartholas:BAAANQAECgEIAgAAAA==.Bazzoo:BAAANQAECgEIAgAAAA==.',
Be='Beastmodex:BAAANQAECgUIBgAAAA==.Beastyboo:BAAANQAECgcIEQAAAA==.Benzos:BAABNQAECoEaAAMFAAgJZiKoAQAWAwAFAAgJZiKoAQAWAwAEAAEJERA8SQA8AAAAAA==.Bequin:BAAANQAECgEIAQAAAA==.Berrd:BAAANQAECgMIBAAAAA==.Bewbbs:BAAANQAECgMIAwAAAA==.',
Bh='Bhangbhang:BAAANQAECgYIDgAAAA==.',
Bi='Biggerbits:BAAANQAECgEIAQAAAA==.Bigkrayze:BAAANQAECgEIAQABNQAECgQICwABAAAAAA==.Bigpapapump:BAAANQADCggIAQAAAA==.Bigpullz:BAAANQABCgEIAQAAAA==.',
Bj='Bjordom:BAAANQADCgYIBgAAAA==.',
Bl='Bluerose:BAAANQADCgcIDAAAAA==.Blurry:BAAANQAECgIIAgAAAA==.',
Bo='Bountmage:BAAANQADCgUIBQAAAA==.',
Br='Bradyswife:BAAANQADCgYIDQAAAA==.Brisketboy:BAAANQADCgQIBAAAAA==.Bro:BAAANQAECgEIAQAAAA==.Bronthos:BAAANQADCggICAAAAA==.',
Bu='Buffbutton:BAAANQAECgQIBQABNQAECgQICgABAAAAAA==.Buffstallion:BAAANQADCggICAAAAA==.',
['Bï']='Bïllï:BAAANQAECgcIEQAAAA==.',
Ca='Caerisma:BAAANQAECgQICAAAAQ==.Caravaggio:BAAANQADCgQIBQAAAA==.Catawba:BAAANQADCgMIAwAAAA==.',
Ce='Cellica:BAAANQAECgQIBQAAAA==.Cerywen:BAAANQADCgIIAgAAAA==.',
Ch='Chadwik:BAAANQADCgYIDQAAAA==.Charbzenberg:BAAANQAECgIIAgAAAA==.Charisma:BAAANQADCgYICQABNQAECgQICAABAAAAAQ==.Chungae:BAAANQABCgEIAQAAAA==.',
Ci='Ciomara:BAAANQADCgUIBgAAAA==.',
Cl='Cloax:BAAANQAECgcIDgAAAA==.',
Co='Cobblepot:BAAANQABCgUIBQAAAA==.Coconut:BAAANQADCgIIAgABNQADCggIFgABAAAAAA==.Coinbrew:BAAANQADCgQIBAAAAA==.Comardrac:BAAANQADCgQIBAAAAA==.Coned:BAAANQADCgEIAQAAAA==.Coobin:BAAANQADCgQIBAAAAA==.Coobins:BAAANQADCgcIBwAAAA==.',
Cr='Cranberrie:BAAANQADCggICAAAAA==.Crapo:BAAANQADCggIEgAAAA==.Cryhavok:BAAANQAECgcIEAAAAA==.',
Cu='Cussack:BAAANQAECgcIEgAAAA==.',
Da='Dabubble:BAAANQADCgIIAgAAAA==.Dadaji:BAAANQADCgQIAQABNQAECgkJGgAEANUYAA==.Daghar:BAAANQAECgIIAwAAAA==.Dalisaan:BAAANQADCgMIAwAAAA==.Dalé:BAAANQADCggICwAAAA==.Danastan:BAAANQAECgMIBAAAAA==.Darkgol:BAAANQADCggIFgABNQAECgUICwABAAAAAA==.Davioon:BAAANQAECgIIBAAAAA==.Dayrb:BAAANQADCgUIBQAAAA==.',
De='Deadtalini:BAAANQAECgcIEQAAAA==.Deah:BAAANQADCgYIDAAAAA==.Deaththroes:BAAANQAECgEIAQAAAA==.Deckerdramon:BAAANQAECgUICgAAAA==.Demomachin:BAAANQAECgQICAAAAA==.Demyze:BAAANQADCggIEAAAAA==.Deucalyon:BAAANQADCggIFQAAAA==.Devilchildd:BAAANQADCgMIAwAAAA==.Devours:BAABNQAECoEYAAIGAAkJIxzFDQDzAgAGAAkJIxzFDQDzAgAAAA==.',
Di='Dirtyhooves:BAAANQADCgEIAQABNQADCgYIDQABAAAAAA==.Divo:BAAANQADCgEIAgAAAA==.Diâblö:BAABNQAECoEfAAIHAAkJtCYJAAANBAAHAAkJtCYJAAANBAAAAA==.',
Do='Dohtem:BAAANQADCgYIBgABNQAECgYIDAABAAAAAA==.Donmegah:BAAANQAECgEIAQAAAA==.Dotmoo:BAAANQADCgEIAQAAAA==.',
Dr='Dragibbay:BAAANQADCgUIBQAAAA==.Dragoncito:BAAANQADCgMIAwAAAA==.Draki:BAAANQADCgYIEAAAAA==.Dredtotem:BAAANQADCgYIBgAAAA==.Droodums:BAAANQAECgEIAQAAAA==.Druidmon:BAAANQADCgYICgAAAA==.',
Du='Duggo:BAAANQAECgEIAQAAAA==.Dutanu:BAAANQAECgEIAgAAAA==.',
Ei='Eibhlean:BAAANQAECgMIBAABNQAECgEIAQABAAAAAA==.Eireckt:BAAANQADCgIIAgAAAA==.Eirrin:BAAANQAECgMIAwABNQAECgYIEAABAAAAAA==.',
El='Elariin:BAAANQAECgMIAwAAAA==.Elendira:BAAANQADCgYIBgAAAA==.Ellektra:BAAANQABCgcIBwAAAA==.Elleredreaux:BAAANQAECgUIBwAAAA==.',
Em='Emongar:BAAANQABCgEIAQAAAA==.',
En='Endomorphism:BAAANQADCggIDgABNQAECgkJFgAIAHQiAA==.',
Es='Estradiol:BAAANQADCgYICwAAAA==.',
Et='Etherhand:BAAANQADCgQIBAAAAA==.',
Ex='Exiza:BAAANQAECgMIBAAAAA==.',
Ez='Ezmelora:BAAANQAECgQIBAAAAA==.',
Fa='Fableshoot:BAAANQADCgQIBAAAAA==.Falconlaugh:BAAANQAECgEIAQAAAA==.Fancyrager:BAAANQADCgEIAQABNQADCgIIAgABAAAAAA==.Fantasie:BAAANQADCgcIEAABNQAECgYIDAABAAAAAA==.Fatherclutch:BAAANQADCgQIBgABNQADCgYICAABAAAAAA==.Fauxpawz:BAAANQADCgYICwAAAA==.Fayia:BAAANQAECgcIEAAAAA==.',
Fe='Felpal:BAAANQABCgMIAQABNQAECgQICwABAAAAAA==.Felwoof:BAAANQAECgYICwAAAA==.Felzak:BAAANQADCgYIBgAAAA==.Fentacide:BAAANQADCgMIAwAAAA==.',
Fi='Firewraith:BAAANQADCgYICwAAAA==.',
Fl='Flarllek:BAAANQADCgQICwAAAA==.Flexxed:BAABNQAECoEbAAIJAAkJLyGHBQAnAwAJAAkJLyGHBQAnAwAAAA==.',
Fo='Foopz:BAAANQADCgIIAgABNQADCgMIAQABAAAAAA==.',
Fr='Frakkinfrik:BAAANQABCgIIAgAAAA==.Frikkinfrak:BAAANQABCgIIAgAAAA==.Friskie:BAAANQAECgMIAwABNQAECgYIDAABAAAAAA==.Fry:BAABNQAECoEaAAIKAAkJ2BcvDAC3AgAKAAkJ2BcvDAC3AgAAAA==.',
Fu='Fubardruid:BAAANQADCgcIDwAAAA==.Fuguestate:BAAANQAECgUICgAAAA==.Furystrike:BAAANQAECggIDQABNQAECggIIwALACojAA==.',
Ga='Galenaa:BAAANQADCgUIBwAAAA==.Galixie:BAAANQABCgIIAgAAAA==.Ganondrow:BAAANQAECgYICgAAAA==.',
Ge='Gemelo:BAAANQAECgEIAQAAAA==.Geromul:BAAANQADCgYICgAAAA==.Gerrexs:BAAANQADCgYIDAAAAA==.',
Gh='Ghst:BAAANQADCggICAAAAA==.',
Gi='Gibayy:BAAANQAECgEIAQAAAA==.Gibsonex:BAAANQADCggIEwAAAA==.Gilliamm:BAAANQAECgYIEQAAAA==.',
Gl='Gleste:BAAANQADCgQIBQAAAA==.',
Go='Golath:BAAANQAECgUICwAAAA==.Gonguker:BAAANQADCgIIAgAAAA==.Gonthielhunt:BAAANQADCggIEwAAAA==.Gothbutta:BAAANQADCgQICAAAAA==.',
Gr='Grado:BAAANQADCgIIAgAAAA==.Graydeon:BAAANQADCggIEAAAAA==.Gregano:BAAANQADCgEIAQABNQAECgYICwABAAAAAA==.Gregorian:BAAANQAECgYICwAAAA==.Gremliin:BAABNQAECoEYAAIMAAkJxRu8DADsAgAMAAkJxRu8DADsAgAAAA==.Grigo:BAAANQAECgIIBAAAAA==.Grippyt:BAAANQAECgEIAQAAAA==.Grymni:BAAANQADCgYIBgAAAA==.',
Ha='Hammerbell:BAAANQADCggICAAAAA==.Havideeznuts:BAAANQADCggIEwAAAA==.',
He='Healmeharder:BAAANQADCgEIAQAAAA==.Healthcare:BAAANQADCggIEwAAAA==.',
Hi='Hierba:BAAANQADCggIDgAAAA==.Hilltop:BAAANQABCgEIAQAAAA==.Hippo:BAAANQAECgUICgAAAA==.',
Ho='Holdor:BAAANQADCgEIAQAAAA==.Holdors:BAAANQADCgUIBQAAAA==.Holier:BAAANQADCgYIBgABNQADCggICAABAAAAAA==.Holybloodboi:BAAANQADCgUIBQABNQAECgQIBgABAAAAAA==.Holyfae:BAAANQADCgMIAwAAAA==.Holynoodle:BAAANQAECgEIAQABNQAECgUIDgABAAAAAA==.',
Hy='Hymnbral:BAAANQAECgQIBAAAAA==.',
Ic='Icebergx:BAAANQADCgIIAwAAAA==.',
Il='Iliohae:BAAANQAECgQICwAAAA==.Illyssa:BAAANQADCgYICAAAAA==.',
Im='Imptricity:BAAANQADCgQIBAAAAA==.',
In='Insanegrippy:BAAANQADCgYIBgABNQAECgkJHgAGANogAA==.Intaria:BAABNQAECoEXAAMNAAgJahFtRgAaAgANAAgJKxFtRgAaAgAOAAMJlw7REQCvAAAAAA==.',
Is='Iseetouch:BAAANQABCgQIBAAAAA==.Isomorphism:BAAANQADCgYIBgAAAA==.',
It='Itchystraws:BAAANQAECgIIAgAAAA==.',
Ja='Jackbeef:BAAANQAECgYIEQAAAA==.Jadedhooves:BAAANQAECgQIBgAAAA==.Jaggedlilhun:BAAANQAECgUICwAAAA==.Jaggedshammy:BAAANQADCggIEAABNQAECgUICwABAAAAAA==.Jagruk:BAAANQADCgIIAgABNQADCgYIBgABAAAAAA==.Jareyk:BAAANQAECgUICgAAAA==.Jarladorin:BAAANQADCgcICgAAAA==.Jaxodk:BAAANQAECgUIDQAAAA==.',
Jb='Jbrealone:BAAANQADCgMIAwAAAA==.',
Je='Jedai:BAABNQAECoEfAAIPAAkJGh0TDQADAwAPAAkJGh0TDQADAwAAAA==.Jerrysix:BAAANQAECgQICQAAAA==.',
Ju='Judadiah:BAAANQADCggIFgAAAA==.Judo:BAAANQAECgUICQAAAA==.Justbeginner:BAAANQADCggIEAAAAA==.',
Jy='Jyloti:BAAANQAECgIIAgAAAA==.',
['Jà']='Jàxx:BAAANQADCggIFgAAAA==.',
['Jå']='Jåggy:BAAANQADCgYIBgABNQAECgUICwABAAAAAA==.',
Ka='Kalrock:BAAANQAECgUICgAAAA==.Kalrotten:BAAANQADCgcICgABNQAECgUICgABAAAAAA==.Kalulu:BAAANQADCgMIAwAAAA==.Kalyssi:BAAANQADCgYIBgAAAA==.Kancisa:BAAANQAECgEIAQAAAA==.Karkit:BAAANQADCgYICQAAAA==.Katkot:BAAANQAECgEIAQAAAA==.Kayro:BAAANQADCgUICAAAAA==.',
Ke='Keledrian:BAAANQADCgQIBAAAAA==.',
Kh='Khagolith:BAAANQAECgQICAAAAA==.',
Ki='Kioria:BAAANQADCgcIDQAAAA==.Kirishino:BAAANQADCggIFAAAAA==.',
Kk='Kkodabear:BAAANQADCggIDwAAAA==.',
Ko='Kobiter:BAAANQAECgUIBwABNQAECgcIEAABAAAAAA==.Kobito:BAAANQAECgcIEAAAAA==.Korvas:BAAANQABCgMIAQAAAA==.Koup:BAABNQAECoEYAAMQAAkJqSNSBACMAwAQAAkJqSNSBACMAwARAAEJfhIcTQA2AAAAAA==.Koupe:BAAANQAECgQIBgABNQAECgkJGAAQAKkjAA==.',
Kr='Kranx:BAAANQADCgUIBQAAAA==.Krayzebeef:BAAANQAECgQICwAAAA==.Kriss:BAAANQADCgcIFQAAAA==.',
Ku='Kungfudk:BAAANQADCgQIBAAAAA==.Kupe:BAAANQADCgUIBQABNQAECgkJGAAQAKkjAA==.',
Ky='Kyewanda:BAAANQAECgIIAgAAAA==.Kyusakuu:BAAANQAECgYIDAAAAA==.',
La='Laanu:BAAANQADCgcIBwABNQAECgUICwABAAAAAA==.Lahey:BAAANQAECgcIEAAAAA==.Lakes:BAAANQAECgQICAAAAA==.Lanuna:BAAANQAECgMIAwAAAA==.Lathara:BAAANQAECgEIAQAAAA==.Lavs:BAAANQAECgQIBgAAAA==.Laxkeeper:BAAANQADCgUIBwAAAA==.',
Le='Legostepper:BAAANQADCgMIAwAAAA==.Leronis:BAAANQAECgcIEQAAAA==.Lexiah:BAAANQAECgMIAwAAAA==.',
Li='Lilicyhot:BAAANQADCgcIDAAAAA==.Lizardbrain:BAAANQAECgEIAQAAAQ==.',
Lo='Loamathor:BAAANQADCggIDQAAAA==.Loesh:BAAANQADCgIIAgAAAA==.Lorilyn:BAAANQAECgQIBgAAAA==.Lorthag:BAAANQAECgYICgAAAA==.Lovebuz:BAAANQADCgYIBgAAAA==.Loverone:BAAANQADCgIIAgAAAA==.Loyalty:BAAANQADCgUICQAAAA==.',
Lu='Lucciola:BAAANQADCgQIBAAAAA==.Lulbah:BAAANQAECgIIAgAAAA==.Lunareclips:BAAANQADCgIIAgAAAA==.Lunarus:BAAANQAECgQIBQAAAA==.',
['Lì']='Lìfe:BAAANQAECgYIDAAAAA==.',
['Ló']='Lónnìe:BAAANQAECgQIBQAAAA==.Lónníe:BAAANQAECgQIBAAAAA==.',
Ma='Maelona:BAAANQAECgIIAgAAAA==.Magrumok:BAAANQAECgQIBwAAAA==.Magthars:BAAANQADCgYIDQAAAA==.Magtide:BAAANQAFFAEIAQAAAA==.Malväryx:BAAANQADCggIIAAAAA==.Manbearpig:BAABNQAECoEWAAIQAAgJDiIPEAD3AgAQAAgJDiIPEAD3AgAAAA==.Manman:BAAANQAECgIIAgAAAA==.Marshes:BAAANQADCgIIAgABNQAECgQICAABAAAAAA==.Masshooter:BAAANQADCgYICQAAAA==.Mazirek:BAAANQADCgMIAwAAAA==.',
Mc='Mctigly:BAAANQAECgEIAQAAAA==.',
Me='Megadefi:BAAANQAECgEIAQAAAA==.Megol:BAAANQADCggIDQAAAA==.Melirraei:BAAANQADCgYIDAAAAA==.Melith:BAAANQADCgYIBgAAAA==.Melkiel:BAAANQAECgYIDQAAAA==.Meltman:BAAANQABCgIIAgAAAA==.Mentalmidget:BAAANQAECgUICgAAAA==.Mesa:BAABNQAECoF6AAISAAgJ5CXjAQB9AwASAAgJ5CXjAQB9AwAAAA==.Methaen:BAAANQADCgEIAQAAAA==.',
Mi='Miclovin:BAAANQAECgYIDwAAAA==.Microplastic:BAAANQAECgQICgAAAA==.Midsized:BAAANQADCgIIAgAAAA==.Mikexz:BAAANQADCgEIAQAAAA==.Mikoani:BAAANQAECgUICwAAAA==.Mirumahn:BAAANQADCgUIBwAAAA==.Misocursed:BAAANQADCgYIEwAAAA==.Misoquick:BAAANQADCgcIDwAAAA==.Missogyny:BAAANQAECgUIDQAAAA==.Mithunzi:BAAANQAECgQIBwAAAA==.',
Mo='Moadeab:BAAANQADCgUIBwAAAA==.Mogando:BAAANQADCgYICAABNQAECgcICwABAAAAAA==.Mogrogarg:BAAANQAECgQICgAAAA==.Mogrosham:BAAANQAECgEIAQAAAA==.Mogrougarg:BAAANQAECgIIAgABNQAECgQICgABAAAAAA==.Mojojojò:BAAANQADCgIIAgAAAA==.Momimilkers:BAAANQADCgcIDAABNQAECggIGwATAAwaAA==.Mommasha:BAAANQADCgQIBAAAAA==.Monkky:BAAANQADCgYIBgAAAA==.Moonshift:BAAANQAECggICAAAAA==.Mordin:BAAANQADCgcICwAAAA==.Morenthia:BAAANQADCggICAAAAA==.Moribelar:BAAANQAECgEIAQAAAA==.Mormonhunter:BAAANQAECgEIAQAAAA==.Morriffic:BAAANQAECgQIBQABNQAECgUICQABAAAAAA==.Morventhas:BAAANQADCgIIAgAAAA==.Mosshead:BAAANQADCggIDwAAAA==.Mousethyr:BAAANQAECgUICAAAAA==.',
Mu='Muahah:BAAANQAECgEIAgAAAA==.Munric:BAAANQAECgUICgAAAA==.',
My='Myboycleetus:BAAANQAECgMIAwAAAA==.Mylocky:BAAANQAECgEIAQAAAA==.Mynon:BAAANQADCgMIAwAAAA==.',
['Mä']='Mäze:BAAANQADCgYIBgAAAA==.',
['Mé']='Méudäil:BAAANQAECgQIBAAAAA==.',
Na='Nachobussy:BAAANQAECgUIBQAAAA==.Nachothings:BAABNQAECoEYAAMUAAkJWxYFEQCKAgAUAAkJWxYFEQCKAgAVAAEJVhmhSABOAAABNQAECgUIBQABAAAAAA==.',
Ne='Necrokat:BAAANQAECgIIAgAAAA==.Nephelia:BAAANQADCgYIBgAAAA==.Nezha:BAAANQAECgEIAQABNQAECgcICgABAAAAAA==.',
Ni='Nightmist:BAAANQADCgcIEwAAAA==.Nihility:BAAANQAECgcICgAAAA==.Nirgand:BAAANQAECgEIAQABNQAECgcICwABAAAAAA==.Nitak:BAAANQAECggICAAAAA==.',
No='Noodlestang:BAAANQAECgUIDgAAAA==.Nool:BAAANQADCgcIEAAAAA==.Norgand:BAAANQAECgcICwAAAA==.Nosleep:BAAANQAECgcIEQAAAA==.Notdumb:BAAANQADCgQIBwAAAA==.',
Nu='Nullify:BAAANQADCgUICQAAAA==.',
Ny='Nydeath:BAAANQAECgEIAQAAAA==.Nyduss:BAAANQAECgIIAwAAAA==.Nymphs:BAAANQADCgEIAQABNQAECgQICAABAAAAAA==.Nyraxys:BAAANQAECgYICAAAAA==.Nyxpal:BAAANQAECgIIAgAAAQ==.',
Ob='Obalo:BAAANQADCgcICQAAAA==.Obrlord:BAAANQADCgcIDgAAAA==.',
Oc='Ocopoko:BAAANQADCgcIBwAAAA==.',
Od='Oddzmage:BAAANQADCggICAAAAA==.',
On='Onibushi:BAAANQAECgYIDAAAAA==.',
Oo='Oof:BAAANQAECgMIAwAAAA==.',
Op='Ophinias:BAAANQADCgcICAAAAA==.Optimize:BAAANQAECggIEAAAAA==.',
Or='Orastal:BAAANQAECgIIAgABNQAECgQIBwABAAAAAA==.Ordonoir:BAAANQAECgIIAgAAAA==.Oroki:BAAANQADCggIAgAAAA==.',
Pa='Paid:BAAANQADCgMIAwAAAA==.Palledized:BAAANQADCgcICAAAAA==.Paloadin:BAAANQAECgIIAgAAAA==.Pandadander:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Pandalo:BAAANQADCgUICQAAAA==.Pandalock:BAAANQADCgcIDgAAAA==.Parasiite:BAAANQAECgYIDwAAAA==.',
Pe='Pebbles:BAAANQADCgYIBgABNQAECgIIAwABAAAAAA==.Peepocute:BAAANQAECgIIAwAAAA==.',
Ph='Phadenstar:BAAANQADCgQICAAAAA==.Phylus:BAAANQADCggICAAAAA==.Physiowar:BAAANQAECgYICAAAAA==.',
Pi='Pickledeath:BAAANQAECgQIBgAAAA==.Pizzapuff:BAAANQADCgYICwAAAA==.',
Pl='Plaguemachin:BAAANQADCgMIAwAAAA==.',
Po='Ponchoe:BAAANQADCgQIBQAAAA==.Poobahdrag:BAABNQAECoEaAAMSAAgJ2iNOBAAuAwASAAgJ2iNOBAAuAwATAAIJMQrXIQB+AAAAAA==.Poundpup:BAAANQADCgcIBwAAAA==.',
Pr='Prell:BAAANQADCggICQAAAA==.Preservation:BAAANQAECgYIBgAAAA==.',
Pu='Pugi:BAAANQADCgEIAQAAAA==.',
Qt='Qtyy:BAAANQAECgQIBgAAAA==.',
Ra='Raawwrr:BAAANQADCgYIBwAAAA==.Rabbi:BAAANQADCgIIAQAAAA==.Racken:BAAANQAECgMIBgAAAA==.Ragehound:BAAANQADCgYIBwAAAA==.Rainhealz:BAAANQADCgIIAgAAAA==.Ranzor:BAAANQAECgUICQAAAA==.Rashis:BAAANQAECgMIBAAAAA==.Rattpack:BAAANQAECgEIAQAAAA==.Raveyn:BAAANQAECgQIBgAAAA==.',
Re='Redjak:BAAANQABCgYICwAAAA==.Regino:BAAANQAECgMIBwAAAA==.Reitiado:BAAANQADCgIIAgAAAA==.Rekieuwu:BAAANQADCgYIBgABNQAECgUICgABAAAAAA==.Rekita:BAAANQAECgUICgAAAA==.Retispagheti:BAAANQADCggICAAAAA==.Retnuh:BAAANQAECgQICAAAAA==.Revivified:BAAANQADCgcIBwAAAA==.',
Rh='Rhibbons:BAAANQADCgEIAQAAAA==.Rhyneaux:BAAANQADCgEIAQAAAA==.',
Rn='Rn:BAAANQAECgIIAgAAAA==.',
Ro='Roderika:BAAANQADCgcIDgABNQAECgkJGAAWACgjAA==.Rogsicle:BAABNQAECoEYAAIWAAkJKCP0AwCKAwAWAAkJKCP0AwCKAwAAAA==.Roldin:BAAANQAECgEIAQAAAA==.Rolockrad:BAAANQAECgQIBgAAAA==.Romanflak:BAAANQADCgYIBgAAAA==.Roostr:BAAANQAECgUICQAAAA==.Rord:BAAANQAECgUICgAAAA==.Royjacked:BAAANQADCggIEgAAAA==.',
Ru='Rubberr:BAAANQAECgEIAQAAAA==.Rubbershank:BAAANQAECgIIAwAAAA==.Rufío:BAAANQAECgMIAwAAAA==.Rumblebee:BAAANQADCgQIBAAAAA==.Runicstrike:BAABNQAECoEjAAQLAAgJKiNwDwDhAgALAAcJbiRwDwDhAgAWAAUJNxoZOwBlAQAJAAUJYBirJABIAQAAAA==.',
['Rø']='Røøm:BAAANQADCgYIBgAAAA==.',
Sa='Sagalia:BAAANQADCgIIAgABNQAECggICAABAAAAAA==.Sahra:BAAANQAECgQIDQAAAA==.Sanctustrike:BAAANQAECggIBgABNQAECggIIwALACojAA==.Saraphina:BAAANQADCggIEQAAAA==.Sauruman:BAAANQADCgEIAQAAAA==.',
Se='Sellandre:BAAANQADCggIDQAAAA==.Selvalamhi:BAAANQADCgQIBAABNQAECgcICwABAAAAAA==.Seronja:BAAANQAECgEIAgAAAA==.Serpompom:BAAANQADCgUIBQAAAA==.',
Sh='Shazzai:BAAANQADCgYIBgAAAA==.Sherfight:BAAANQAECgYIDAAAAA==.Shielddaddy:BAAANQAECgEIAgAAAA==.Shieldsftl:BAAANQADCgUIBgABNQADCgcIDgABAAAAAA==.Shiftycent:BAAANQADCgcICgAAAA==.Shnyaga:BAABNQAECoF5AAMMAAgJWCNYBwAwAwAMAAgJWCNYBwAwAwAKAAQJBh/pHgCGAQAAAA==.Shockybalboa:BAAANQADCgQIBAAAAA==.Shunkd:BAAANQAECgQIBAAAAA==.Shøcker:BAAANQABCgMIAgAAAA==.',
Si='Sianda:BAAANQABCgIIAgAAAA==.Silithaine:BAAANQADCgUIBQAAAA==.Simpsforimps:BAAANQAECgEIAQAAAA==.Sizurp:BAAANQABCgIIAgAAAA==.',
Sj='Sjardags:BAAANQADCgIIAgAAAA==.',
Sk='Skinwalk:BAAANQAECgIIAwAAAA==.Skrai:BAAANQAECgIIAQAAAA==.',
Sl='Sleew:BAAANQAECgcIDwAAAA==.Slippydippy:BAAANQAECgEIAQAAAA==.',
Sm='Smokintrees:BAAANQADCgUIBwAAAA==.',
Sn='Sneakylizard:BAAANQADCgYICwAAAA==.Snocaps:BAAANQADCgYIBgAAAA==.',
So='Soggypringle:BAAANQADCgMIBAAAAA==.Solnath:BAAANQAECgcIEQAAAA==.',
Sp='Specsdraco:BAAANQAECgcIEwAAAA==.Spewpuke:BAAANQAECgYIEAAAAA==.Spicytomato:BAAANQAECgYICQAAAA==.Spirtforge:BAAANQADCgYIBgAAAA==.',
St='Staci:BAAANQAECgEIAQAAAA==.Starfree:BAAANQAECggIEAAAAA==.Starstorm:BAAANQADCgQIBAABNQAECgcIDwABAAAAAA==.Stgermain:BAAANQAECgcIDwAAAA==.Stormlotus:BAAANQAECgIIAgAAAA==.Stormsorrow:BAAANQADCgEIAQAAAA==.Strikeanywer:BAAANQADCgYICAAAAA==.',
Su='Superstoned:BAAANQADCgIIAgAAAA==.Surudk:BAAANQADCggIDwAAAA==.',
Sy='Sylrana:BAAANQAECgIIAgAAAA==.Sylri:BAAANQADCgYIBgAAAA==.',
Ta='Taktikil:BAAANQADCgQICAAAAA==.Talrad:BAAANQAECgMIAwAAAA==.Tazerxface:BAAANQAECgcIEgAAAA==.',
Te='Tealgos:BAAANQAECgQICwAAAA==.',
Th='Thaiddous:BAAANQAECgUIBwAAAA==.Thanx:BAAANQAECgIIAgAAAA==.Thebeefchief:BAABNQAECoEYAAIIAAkJKiIfAQCBAwAIAAkJKiIfAQCBAwAAAA==.Thebigmon:BAAANQAECgUIDAAAAA==.Thedabara:BAAANQADCgMIAwAAAA==.Thedon:BAAANQADCgYICwAAAA==.Therealnmula:BAAANQADCgUICgAAAA==.Thewhite:BAAANQAECgYICgAAAA==.Thorxx:BAAANQADCgUIBQAAAA==.Thrudheals:BAAANQAECgQICwAAAA==.Thugnastie:BAAANQAECgMIBwAAAA==.Thylia:BAAANQADCgYIBgAAAA==.',
Ti='Tika:BAAANQAECgMIAwAAAA==.',
To='Toastyshamy:BAAANQAECgIIAgAAAA==.Tofrenm:BAAANQAECgMIAwAAAA==.Togashi:BAAANQAECgYIEAAAAA==.Topacio:BAAANQADCggIDgAAAA==.Topnacho:BAAANQADCgEIAQABNQAECgUIBQABAAAAAA==.Torskeprime:BAAANQADCgEIAQAAAA==.Totalpyro:BAAANQAECgMIAwAAAA==.Totesschnook:BAAANQADCgMIAwAAAA==.Toymueto:BAAANQAECgQIBAAAAA==.',
Tr='Treespirit:BAAANQAECgYIBgAAAA==.Tricep:BAAANQADCgYIBgAAAA==.Tripallie:BAAANQADCgQIBgAAAA==.Trishian:BAAANQADCgMIBAAAAA==.Trunkmuffin:BAAANQADCgMIAQAAAA==.Truthless:BAEANQAECgcIDgAAAA==.',
Tu='Tuckermax:BAAANQADCgYICgAAAA==.Tunks:BAAANQAECgUICQAAAA==.Tusk:BAAANQAECgQICAAAAA==.',
Ty='Tyranbae:BAAANQADCggICAABNQAECggIGgASANojAA==.',
Ug='Uglyashell:BAAANQADCgQIBgAAAA==.',
Un='Unit:BAAANQAECgcIDgAAAA==.',
Uv='Uva:BAAANQADCggIHAAAAA==.',
Va='Valanui:BAAANQADCgIIAgAAAA==.Valendara:BAAANQAECgUICQAAAA==.Valsorin:BAAANQAECgEIAQAAAA==.Valtaea:BAABNQAECoEWAAICAAgJFwwGdADrAQACAAgJFwwGdADrAQAAAA==.',
Vi='Vishas:BAAANQADCgMIAwAAAA==.Vixol:BAAANQADCgQIBAAAAA==.',
Vo='Voidheals:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Volairne:BAAANQADCgQIBwAAAA==.Voreah:BAAANQAECgEIAQABNQAECgMIBAABAAAAAA==.',
Wa='Wafflxs:BAABNQAECoEbAAIHAAkJtyTjAACnAwAHAAkJtyTjAACnAwAAAA==.Walkingheals:BAAANQADCgIIAwAAAA==.Wanpisu:BAAANQAECgUICwAAAA==.Warglave:BAAANQAECgIIAgAAAA==.Warmo:BAAANQADCggICAAAAA==.',
We='Weiwu:BAABNQAECoEaAAIXAAgJvBxlCwCXAgAXAAgJvBxlCwCXAgAAAA==.Wellfookthat:BAAANQAECgcIEQAAAA==.Wellfookyew:BAAANQADCgcIBwABNQAECgcIEQABAAAAAA==.Weolf:BAAANQABCgIIAQAAAA==.',
Wh='Whiteshadows:BAAANQAECgMIBAAAAA==.Whyvala:BAAANQADCgYIEwABNQABCgIIBAABAAAAAA==.',
Wi='Wiisp:BAAANQAECgMIBQAAAA==.',
Wo='Wolnney:BAAANQAECgcIEQAAAA==.Wowimhealing:BAAANQADCgcIEAAAAA==.',
['Wâ']='Wâarseer:BAAANQADCgYICwAAAA==.',
Xa='Xalatoes:BAABNQAECoEeAAIGAAkJ2iCmBwA9AwAGAAkJ2iCmBwA9AwAAAA==.Xanathar:BAAANQADCgYICAAAAA==.Xandertheone:BAAANQADCgUIBQAAAA==.Xandrin:BAAANQADCgEIAQAAAA==.',
Xi='Xiren:BAAANQABCgIIAgAAAA==.',
Xr='Xraiz:BAAANQADCggIFQAAAA==.',
Xy='Xyne:BAAANQADCggICQAAAA==.',
Ya='Yakiwhack:BAAANQADCgEIAQAAAA==.',
Yo='Yogonine:BAABNQAECoEgAAIHAAkJRyKGAQCCAwAHAAkJRyKGAQCCAwAAAA==.Yourboyblue:BAAANQADCgYICgAAAA==.',
Yv='Yverrius:BAAANQADCgMIBgAAAA==.',
Za='Zanydruid:BAAANQADCgQICAAAAA==.Zanza:BAAANQAECgEIAQAAAA==.Zarione:BAAANQADCgYIBgAAAA==.',
Ze='Zearyth:BAAANQADCgcIDQAAAA==.Zemus:BAAANQADCggIDAAAAA==.Zenevieva:BAAANQADCgIIAgAAAA==.',
Zh='Zhamazu:BAAANQADCgMIBAAAAA==.Zhayden:BAAANQAECgQIBAAAAA==.Zhygår:BAAANQAECgEIAQAAAA==.',
Zi='Ziberia:BAAANQADCgIIAgAAAA==.',
Zo='Zodin:BAAANQADCgMIBQABNQAECgIIAgABAAAAAA==.Zombiez:BAAANQAECgUIDAAAAA==.Zoryn:BAAANQADCgYICQABNQABCgMIAwABAAAAAA==.',
['Él']='Élowen:BAAANQAECgEIAQAAAA==.',
['ßo']='ßoß:BAAANQABCgcICQAAAA==.',
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
