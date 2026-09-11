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

local lookup = {'Warrior-Arms','Unknown-Unknown','Warlock-Destruction','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','Warrior-Fury','Warlock-Demonology','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Devourer','DemonHunter-Havoc','Hunter-Marksmanship','Hunter-BeastMastery','Shaman-Elemental','Warlock-Affliction','Mage-Arcane','Paladin-Retribution','Paladin-Protection','Priest-Discipline','DeathKnight-Unholy','Shaman-Restoration','Monk-Mistweaver','Shaman-Enhancement','Mage-Frost',}
local provider = {region='US',realm='Magtheridon',name='US',type='weekly',zone=53,date='2026-09-08',data={Ac='Acacia:BAAANQADCgcIDAAAAA==.',
Ag='Agave:BAAANQAECgMIBAAAAA==.',
Ai='Aizun:BAAANQAECgcICwAAAA==.',
Ak='Akulagos:BAAANQAECgEIAQAAAA==.',
Al='Alakavahm:BAAANQADCgQIBAAAAA==.Aldenfire:BAAANQADCgMIAwAAAA==.Alesce:BAABNQAECoEZAAIBAAkJOg8mLAA4AgABAAkJOg8mLAA4AgAAAA==.Alii:BAAANQAECgEIAQAAAA==.',
Am='Amaraukyou:BAAANQADCgEIAQAAAA==.Amenadiel:BAAANQAECgUIBwAAAA==.Amythistle:BAAANQADCgYIEAAAAA==.',
An='Andrü:BAAANQAECgUIBwAAAA==.',
Ar='Arnblass:BAAANQAECgMIBAAAAA==.',
As='Ascend:BAAANQAECgIIAgAAAA==.Ashtana:BAAANQAECgIIAgAAAA==.Ashtar:BAAANQAECgUICAAAAA==.',
Au='Aurora:BAAANQADCgcIBwAAAA==.',
Av='Aviee:BAAANQAECgcIEAAAAA==.',
Ax='Axidin:BAAANQAECgEIAQAAAA==.',
Az='Azushi:BAAANQADCggIEAABNQAECgkJGQABAJQVAA==.',
Ba='Babyfox:BAAANQADCgMIAwAAAA==.Babymage:BAAANQAECgcIEQAAAA==.Badform:BAAANQADCggIFgAAAA==.Badkitteh:BAAANQADCgYIDAAAAA==.Baelstrom:BAAANQADCgIIAgABNQAECgYIBgACAAAAAA==.Baendron:BAAANQAECgQIBgAAAA==.Bahcrypt:BAAANQADCgYIBgAAAA==.Bakaris:BAAANQADCgUIBQAAAA==.Barbarik:BAAANQAECgYICAABNQAECgkJGAADAPsZAA==.Barberry:BAAANQADCgQIBAABNQAECgcIEQACAAAAAA==.Baretwallace:BAAANQADCggICQABNQAECggIDgACAAAAAA==.Bayesian:BAAANQABCgIIAgAAAA==.',
Be='Beefwildfire:BAAANQADCgQIBQAAAA==.Beercheer:BAAANQADCgUICwAAAA==.Beertholomew:BAAANQAECgMIAwAAAA==.Beestkyn:BAAANQADCgUIBQAAAA==.Behodakhtala:BAAANQADCgYIDwAAAA==.Bellanzo:BAAANQAECgUIBQAAAA==.',
Bi='Bigzee:BAEANQAECgcIEQAAAA==.',
Bl='Blargin:BAAANQADCgIIAgAAAA==.Blorgin:BAABNQAECoEZAAMEAAkJdCNbAgBXAwAEAAgJkiRbAgBXAwAFAAIJVx2tIgCxAAAAAA==.Bluntmàn:BAAANQAECgQIBAAAAA==.',
Bo='Boogieman:BAAANQADCgYIBgAAAA==.Boohwodoy:BAAANQADCgcIBwAAAA==.Bookers:BAAANQAECgQIBAAAAA==.Booplzs:BAAANQADCgUIBQAAAA==.Borgo:BAAANQADCgIIAgABNQAECgQIBwACAAAAAA==.Boulangerie:BAABNQAECoEZAAIGAAkJFiTMAADKAwAGAAkJFiTMAADKAwAAAA==.Boulior:BAAANQAECgIIAwAAAA==.Bowvice:BAEANQADCgUIBQABNQAECggIEwACAAAAAA==.Boyd:BAABNQAECoESAAMHAAgJ4RiGAgBGAgAHAAcJ4xqGAgBGAgABAAEJzwomowBAAAAAAA==.',
Br='Brewmungandr:BAAANQADCggIEgAAAA==.Bromayzo:BAAANQABCgIIAgAAAA==.',
Ca='Canadatrash:BAAANQAECgEIAQABNQAECggIDgACAAAAAA==.Carraway:BAAANQAECgYICwAAAA==.Cashewz:BAAANQADCgQIBAAAAA==.',
Ce='Ceasarsalad:BAABNQAECoEWAAMDAAkJfBhaCgAZAgAIAAkJXRQJFwBGAgADAAcJtRNaCgAZAgAAAA==.Ceazitt:BAAANQAECgEIAQABNQAECgMIAwACAAAAAA==.Ceazyweasley:BAAANQAECgMIAwAAAA==.Ceci:BAAANQABCgMIAwAAAA==.Celestriå:BAAANQADCgYIEAAAAA==.Cetana:BAAANQAECggIDgAAAA==.',
Ch='Chadlockb:BAAANQAFFAEIAQAAAA==.Cheesee:BAAANQAECgUICQAAAA==.Chiko:BAAANQAECgEIAQAAAA==.Christlike:BAAANQABCgQIBAAAAA==.Chronite:BAAANQAECgQIBwAAAA==.Chucho:BAAANQADCgYIBgAAAA==.Chárgers:BAAANQADCgcIEgAAAA==.',
Ci='Cindr:BAABNQAECoEXAAMJAAkJNB9DAwAnAwAJAAkJWh5DAwAnAwAKAAUJSxnMBgATAQAAAA==.Circumstance:BAAANQAECgUIBQAAAA==.',
Cl='Cleattus:BAAANQAECgMIBAAAAA==.',
Co='Colddblooded:BAAANQAECgQIBwAAAA==.Cololol:BAABNQAECoEYAAILAAkJyyRMAgCVAwALAAkJyyRMAgCVAwAAAA==.Compcomp:BAAANQAECgMIBAAAAA==.Compi:BAAANQAECgEIAQABNQAECgMIBAACAAAAAA==.Cooper:BAAANQAECgQIBgAAAA==.Corlys:BAAANQAECgQIBgAAAA==.',
Cr='Crew:BAABNQAECoEXAAIMAAkJJyJPAwBOAwAMAAkJJyJPAwBOAwAAAA==.Cronoz:BAAANQAECgUICAAAAA==.',
Cu='Cucokai:BAAANQADCggICwAAAA==.Cuddlestomp:BAABNQAECoEZAAMNAAkJqCA8BwD+AgANAAgJ/CE8BwD+AgAOAAYJwhEuPACXAQAAAA==.',
Cz='Czernabog:BAAANQAECgEIAQAAAA==.',
['Cä']='Cämulos:BAAANQAECgMIAwAAAA==.',
['Cí']='Círí:BAEANQAECgIIAgABNQAECgYIBgACAAAAAA==.',
Da='Dabbosh:BAAANQAECgQIBAAAAA==.Dahl:BAAANQAECgQIBAABNQAECgYICAACAAAAAA==.Damnhammer:BAAANQAECgYICwAAAA==.Dandie:BAAANQADCgYIBgAAAA==.Darthjinwoo:BAAANQAECgYICQAAAA==.Darthmerlin:BAAANQADCgQIBAABNQAECgYICQACAAAAAA==.Dasakko:BAAANQAECgMIAwABNQAECgcIDgACAAAAAA==.Dasmonko:BAAANQADCggIDAABNQAECgcIDgACAAAAAA==.',
Db='Dbowzillaz:BAABNQAECoEXAAINAAkJBSJsAgCIAwANAAkJBSJsAgCIAwAAAA==.',
De='Deathskeeper:BAAANQADCgYIDAAAAA==.Demithania:BAAANQADCggIDAAAAA==.Demonhunterl:BAAANQAECgQIBgAAAA==.Denden:BAAANQADCgUIBQAAAA==.',
Dh='Dhsil:BAAANQADCggIDgABNQAECgUIBQACAAAAAA==.',
Di='Diabòlic:BAABNQAECoEXAAMIAAkJ6h0PEQB7AgAIAAgJsxwPEQB7AgADAAQJbxl8HABCAQAAAA==.Dirtydiana:BAAANQAECgUIBwAAAA==.',
Dj='Djavol:BAAANQAECgYIBgAAAA==.',
Do='Doc:BAAANQADCgUICgAAAA==.Doguntarth:BAABNQAECoEZAAIBAAkJlBXzGgCsAgABAAkJlBXzGgCsAgAAAA==.',
Dr='Drafi:BAAANQADCgIIAgABNQAECgEIAQACAAAAAA==.Drankincup:BAABNQAECoEcAAIPAAkJ/xsQCQAiAwAPAAkJ/xsQCQAiAwAAAA==.Drstagger:BAEANQAECgYICwABNQAECgcIDgACAAAAAA==.',
Du='Dullahan:BAAANQADCgQIBAAAAA==.Durotann:BAAANQAECgEIAgAAAA==.Dusios:BAAANQADCggIDgAAAA==.Duskflower:BAAANQAECggIDwAAAA==.',
El='Elexandur:BAAANQAECgYIBwAAAA==.Elissa:BAAANQADCgYIBgAAAA==.Eliänna:BAAANQADCgIIAgAAAA==.Elleri:BAAANQAECgMIBAAAAA==.',
Ep='Epnokicks:BAAANQAECggIEAAAAA==.',
Er='Eroicel:BAAANQAECggIEwAAAA==.',
Ev='Evarielle:BAAANQAECgIIAgABNQAECggIEwACAAAAAA==.',
Fa='Fadedhalo:BAAANQAECgIIAwAAAA==.Falaya:BAABNQAECoEWAAQDAAkJvSNTBwBbAgADAAYJgiNTBwBbAgAIAAQJtiL7MgCOAQAQAAEJkyOTDgBnAAAAAA==.Falst:BAAANQAECgQIBgAAAA==.',
Fe='Fennlar:BAAANQAECgMIBQAAAA==.',
Fl='Flakey:BAAANQABCgIIAgAAAA==.Flawlessxi:BAAANQAECgUICAAAAA==.Flyntflosy:BAAANQAECggIDAAAAA==.',
Fo='Fowl:BAAANQAECgcIBwAAAA==.',
Fr='Fragment:BAAANQABCgIIAwAAAA==.',
Fu='Fuehriån:BAABNQAECoEQAAIRAAkJrg1uPQBDAgARAAkJrg1uPQBDAgAAAA==.Funstar:BAAANQADCgYIBgABNQAECggICAACAAAAAA==.Furyess:BAAANQAECgcICwAAAA==.',
Ga='Gaelsi:BAAANQAECgUIBAAAAA==.Galactic:BAAANQAECgUICAABNQAECgcIBwACAAAAAA==.Galgore:BAAANQAECgUIBQAAAA==.Garolok:BAAANQAECgQIBgAAAA==.Gasandflames:BAAANQAECgUIBQAAAA==.Gascans:BAAANQAECgUICAAAAA==.Gazelle:BAEANQAECgQIBgAAAA==.Gazerakhan:BAAANQAECgMIAwABNQAECgcIDgACAAAAAA==.Gazerielle:BAAANQAECgcIDgAAAA==.',
Gl='Glizzylizzy:BAAANQAECgcIEQAAAA==.',
Go='Gothgrippers:BAAANQADCgcIEQAAAA==.Gowownage:BAAANQAECgcIBwAAAA==.',
Gr='Gradeus:BAABNQAECoEYAAISAAkJ7hulDQDtAgASAAkJ7hulDQDtAgAAAA==.Granddh:BAAANQAECgcIDwAAAA==.Graydius:BAAANQADCgQIBAAAAA==.Greenmango:BAAANQADCggIDAAAAA==.Grimeclipse:BAAANQAECgQIBAAAAA==.Grovehart:BAAANQADCgcIEwAAAA==.Grumpoo:BAAANQADCggICAAAAA==.',
Gu='Gurt:BAAANQADCgUIBQAAAA==.Gutz:BAAANQAECgUIBQAAAA==.',
Ha='Haku:BAAANQADCggICAAAAA==.Halestorm:BAAANQADCgYICgAAAA==.Hattori:BAAANQABCgMIBQAAAA==.Havefun:BAAANQAECgcIDQABNQAECggICAACAAAAAA==.',
He='Hedonist:BAAANQADCggICAABNQAECgkJGAADAPsZAA==.Hellsbringer:BAAANQAECgMIAwAAAA==.Heretik:BAAANQAECgQIBQAAAA==.Hevnoraak:BAAANQAECgEIAQAAAA==.',
Ho='Hold:BAAANQAECggIEAAAAA==.Holycandi:BAAANQAECgIIAwAAAA==.Holydoyle:BAAANQAECgYIBgAAAA==.Holyho:BAAANQAECgYIBgAAAA==.Holyjuice:BAAANQAECgQIBAAAAA==.Hotpøcket:BAAANQAECgYICgAAAA==.',
Hu='Huntlzs:BAAANQAECgUICAAAAA==.',
Hy='Hyperìen:BAEBNQAECoEZAAITAAkJMiQJAQCVAwATAAkJMiQJAQCVAwAAAA==.',
['Hø']='Hølý:BAAANQADCgYICAAAAA==.',
Ic='Icedoggi:BAAANQAECgQIBQAAAA==.',
Im='Immortalmage:BAAANQADCgYIBgAAAA==.Imsopro:BAAANQABCgIIAgAAAA==.',
In='Indeed:BAAANQAECgcIEQABNQAFFAIIBAACAAAAAA==.Inferna:BAAANQADCgUIBQAAAA==.Innerbeast:BAAANQAECgQIBAABNQAFFAYICQAUAHAfAA==.Intiq:BAAANQADCgIIAgAAAA==.',
Ir='Irbaboon:BAAANQAECgQIBwAAAA==.Irreletaur:BAABNQAECoEYAAIBAAgJAxm9IACBAgABAAgJAxm9IACBAgAAAA==.',
It='Itisovernow:BAAANQADCgQIBAABNQADCgYICAACAAAAAA==.Itsevokernow:BAAANQADCgUIBQABNQADCgYICAACAAAAAA==.Itsovernow:BAAANQADCgYICAAAAA==.',
Iz='Izimir:BAAANQAECgUIBQAAAA==.',
Ja='Jamloo:BAAANQAECgUIBQAAAA==.Jangokin:BAAANQAECgcIEgAAAA==.Jayiasan:BAAANQAECgMIAwABNQAECgcICwACAAAAAA==.Jazz:BAAANQADCgUICQAAAA==.',
Ji='Jimbaha:BAAANQAECgMIAwAAAA==.Jinks:BAAANQADCgYIDAAAAA==.',
['Jè']='Jèrmz:BAAANQADCgYICQAAAA==.',
Ka='Kabang:BAAANQAECgUICQAAAA==.Kachoo:BAAANQAFFAIIAgAAAA==.Kaige:BAAANQAECgEIAgAAAA==.Kalithor:BAAANQADCgcICwAAAA==.Kathoes:BAAANQAECgEIAQAAAA==.',
Ke='Kelennin:BAAANQADCgIIAgAAAA==.Kellwildfire:BAAANQAECgYICgAAAA==.',
Kf='Kfish:BAAANQADCgYICwAAAA==.',
Kh='Khamael:BAAANQAECgIIAgAAAA==.Kheiron:BAAANQAECggIDgAAAA==.',
Ki='Kinu:BAAANQAECgcIDQAAAA==.Kitane:BAAANQAECgEIAQAAAA==.',
Kl='Klarina:BAAANQAECgQIBgAAAA==.',
Kn='Knox:BAAANQADCgcIEwAAAA==.',
Ko='Kobieta:BAAANQADCggICAAAAA==.Koda:BAAANQADCgYICgAAAA==.Kosolapaya:BAAANQADCgIIAgAAAA==.Kotharsevant:BAAANQADCgcIBwAAAA==.',
Ku='Kurolion:BAAANQAECgYIDAAAAA==.Kurzon:BAAANQADCgEIAQAAAA==.',
Kw='Kwanrbless:BAAANQADCgIIAgAAAA==.',
Ky='Kyblade:BAAANQAECgQIBgAAAA==.',
['Kø']='Køs:BAAANQAECgQIBgAAAA==.',
La='Lampro:BAAANQADCggIDAABNQAECgcIEQACAAAAAA==.Lavajato:BAAANQADCgYICQABNQAECgIIBQACAAAAAA==.',
Le='Leemius:BAAANQAECgIIBAAAAA==.Leosbryn:BAAANQAECgQIBgAAAA==.Leviträ:BAAANQADCgUIBQAAAA==.',
Li='Liable:BAAANQAECgIIAwAAAA==.Ligmadeebliz:BAAANQAECgUICgAAAA==.Lilfister:BAAANQAECgEIAQABNQAFFAIIBAACAAAAAA==.Lilraz:BAAANQADCgYIBgAAAA==.Liltazzvert:BAAANQAECgUICAAAAA==.Linksded:BAAANQADCgEIAQAAAA==.Listerfyne:BAAANQADCgYIAgAAAA==.Littlepain:BAAANQADCgEIAQAAAA==.',
Lu='Lucero:BAAANQAECgEIAQAAAA==.',
Ly='Lyra:BAAANQADCgUIBgABNQAECgEIAQACAAAAAA==.',
Ma='Mabey:BAAANQAECgEIAQAAAA==.Maerron:BAAANQAECgIIAgAAAA==.Mafi:BAAANQABCgQIBAAAAA==.Mageblprows:BAAANQADCgUIDQAAAA==.Mangemonpain:BAAANQADCgcIDQABNQADCgcIEQACAAAAAA==.Maraayla:BAAANQADCggICAAAAA==.Matikz:BAABNQAECoEWAAIEAAkJqBviBAD2AgAEAAkJqBviBAD2AgAAAA==.Maximages:BAAANQADCggIDwAAAA==.Maximon:BAAANQAECgUIBwAAAA==.Maylla:BAAANQADCgcIBwAAAA==.',
Me='Meddle:BAAANQAFFAIIAgAAAA==.Mehrunesd:BAAANQAECgUIBwAAAA==.Meowwmix:BAAANQABCgIIAgAAAA==.Merrydeath:BAAANQADCgYICQAAAA==.Meyea:BAABNQAECoEZAAIVAAkJmCQWAgCuAwAVAAkJmCQWAgCuAwAAAA==.',
Mi='Miller:BAAANQAECgUIDAAAAA==.Miru:BAAANQADCgYIEAAAAA==.Mitis:BAAANQADCgQIBAAAAA==.Mizdems:BAAANQAECgQIBgAAAA==.',
Mo='Moistjustice:BAAANQAECgIIAgAAAA==.Moonfun:BAAANQADCgcICgABNQAECggICAACAAAAAA==.Moufon:BAAANQADCgUICgAAAA==.',
My='Myrodragon:BAAANQAECgQIBAAAAA==.',
['Mé']='Mércy:BAAANQAECgQIBwAAAA==.',
Na='Navah:BAAANQAECgEIAQAAAA==.',
Ne='Neandratroll:BAAANQAECgMIBAAAAA==.Necrodis:BAAANQAECgEIAQABNQAECgYICQACAAAAAA==.Nezemzy:BAAANQADCgUIBQABNQADCgcIEQACAAAAAA==.',
Ni='Nightlevels:BAAANQAECggIDgAAAA==.',
No='No:BAAANQADCgcIBwAAAA==.Nodens:BAAANQADCgQIBAAAAA==.Nogardd:BAAANQAECgQIBgAAAA==.Notpetya:BAAANQAECgIIAwAAAA==.Nottills:BAAANQADCgYIDAAAAA==.',
Nu='Nudleboi:BAAANQADCgUIBQAAAA==.Nuulruk:BAAANQADCggIEwAAAA==.',
Ny='Nylaehh:BAAANQAECgEIAQAAAA==.Nyxtro:BAAANQADCggIDwAAAA==.',
Oi='Oilslick:BAAANQAECgQIBgAAAA==.',
On='Onornu:BAABNQAECoEZAAIWAAkJEyQ9AQCsAwAWAAkJEyQ9AQCsAwAAAA==.',
Or='Orlidan:BAAANQAECgYICAAAAA==.',
Ot='Oth:BAAANQAFFAEIAQAAAA==.',
Ox='Oxylock:BAABNQAECoEZAAMIAAkJgB/IAwA3AwAIAAkJgB/IAwA3AwADAAcJKQfxGwBGAQAAAA==.',
Pa='Palgeron:BAAANQADCgIIAgAAAA==.Pathlon:BAAANQADCgcIDwAAAA==.',
Pe='Peetypirate:BAAANQADCgQIBQAAAA==.Pekapow:BAABNQAECoEZAAIXAAkJqRFiCAAxAgAXAAkJqRFiCAAxAgAAAA==.Peta:BAAANQADCgEIAQAAAA==.',
Ph='Phobius:BAAANQAECgcIEQAAAA==.',
Pi='Pinkmango:BAAANQAECgcIDgAAAA==.Pireyne:BAAANQADCgYICgAAAA==.Pistachioz:BAAANQAECgUIBwAAAA==.',
Pl='Playfultouch:BAAANQADCgYICwAAAA==.Plunkaplunk:BAAANQADCgYICwAAAA==.',
Po='Poco:BAAANQAECgMIAwAAAA==.Polymorphine:BAAANQADCggIDAAAAA==.Poonzer:BAEANQAECggIEwAAAA==.Porosity:BAAANQAECgUICAAAAA==.',
Pr='Pretreckless:BAAANQADCgEIAQAAAA==.Proudclod:BAAANQAECgEIAQAAAA==.',
Qe='Qetesh:BAAANQADCgcIBwAAAA==.',
Ra='Ragnan:BAAANQADCgYICwAAAA==.Rain:BAAANQADCgUIBQABNQAECgQIBgACAAAAAA==.Ralinis:BAAANQADCgYIBgABNQADCgUIBQACAAAAAA==.Rathi:BAAANQAECgEIAQABNQAECgQIBwACAAAAAA==.Ravicavasar:BAAANQADCgYICgAAAA==.Razfu:BAAANQAECgcIEQAAAA==.Razul:BAAANQADCggIDAAAAA==.',
Re='Redharvest:BAAANQAECgQIBQAAAA==.Rekles:BAAANQADCgUIBQABNQAECgUIBwACAAAAAA==.Relentless:BAAANQADCggIFAAAAA==.Retribution:BAAANQAECgUIBQAAAA==.Reznoop:BAEANQAECgIIAgABNQAECggIEwACAAAAAA==.',
Ri='Richardtwist:BAAANQADCgYIEAAAAA==.',
Rk='Rkoo:BAAANQADCgcIEQAAAA==.',
Ro='Roobee:BAAANQABCgEIAQABNQADCgYICgACAAAAAA==.Roxzor:BAAANQAECgIIAgABNQAECgQIBwACAAAAAA==.Royok:BAAANQAECgUICAAAAA==.',
Ru='Ruwey:BAAANQABCgIIAgAAAA==.',
Sa='Sakardi:BAAANQAECgIIAgAAAA==.Sawedoff:BAAANQAECgQICQAAAA==.',
Sc='Scalybum:BAAANQAECgQIBAAAAA==.Scamall:BAAANQAECgEIAQAAAA==.Schizophreni:BAAANQAECgUICQABNQAECgkJGQAGABYkAA==.Scionoffury:BAAANQAECgQIBAAAAA==.Scotcolumbus:BAAANQAECgYICAAAAA==.Scullcrusher:BAAANQABCgYIBwAAAA==.',
Se='Secsysalad:BAAANQAECgQIBQABNQAECgkJFgADAHwYAA==.Seefoo:BAAANQAECgIIAgAAAA==.Sekhy:BAAANQADCggICAAAAA==.Sero:BAAANQAECgIIAgAAAA==.',
Sg='Sgsmagicman:BAAANQADCgcIEgABNQADCggICAACAAAAAA==.',
Sh='Shaamwow:BAAANQAECgIIAgAAAA==.Shade:BAAANQAECgcIEQAAAA==.Shadoewolfe:BAAANQADCgYIDAAAAA==.Shageron:BAABNQAECoEZAAMNAAkJ6iFpBQAsAwANAAkJWSFpBQAsAwAOAAcJUhQFLADnAQAAAA==.Shallshock:BAAANQAECgMIBwAAAA==.Shandoe:BAAANQADCgQIBAAAAA==.Shankspec:BAAANQAECgcIDwAAAA==.Shaolinshamy:BAAANQAECgEIAQAAAA==.Shifterxmag:BAAANQAECgUICAAAAA==.Shikaca:BAAANQADCgYICgAAAA==.Shinseina:BAAANQAECgQIBgAAAA==.Shockbite:BAAANQABCgMIBAAAAA==.Shockinawe:BAAANQADCgMIAwAAAA==.Short:BAAANQADCgIIAgAAAA==.Shämash:BAAANQAECgQIBQAAAA==.Shöck:BAAANQAECgEIAQAAAA==.',
Si='Sicastic:BAAANQADCgYIBgABNQAECgQIBwACAAAAAA==.Siccness:BAAANQAECgQIBwAAAA==.Sieben:BAAANQAECgEIAQAAAA==.Siic:BAAANQADCgYIBgABNQAECgQIBwACAAAAAA==.Sindrex:BAAANQAECgcIEQAAAA==.',
Sk='Skwerl:BAAANQADCgMIAwAAAA==.',
Sl='Slurmage:BAAANQAECgQIBgAAAA==.',
Sm='Smittywerben:BAAANQAECgIIAgAAAA==.Smokfun:BAAANQAECggICAAAAA==.Smooshi:BAABNQAECoEZAAMWAAkJxBa2EwBzAgAWAAkJxBa2EwBzAgAYAAQJ5hAqEAARAQAAAA==.',
Sn='Sneaktarts:BAAANQADCggICAAAAA==.',
So='Sololeveling:BAAANQAECgUIBwAAAA==.Sootor:BAAANQADCgYICwAAAA==.',
Sp='Spags:BAAANQAECgEIAQABNQAECgQIBQACAAAAAA==.Sparklefarts:BAAANQADCgYIBgAAAA==.',
St='Starfun:BAAANQAECgIIAgABNQAECggICAACAAAAAA==.Steelheals:BAAANQADCgQIBQAAAA==.Stenzwar:BAAANQAECgEIAQABNQAECgkJGQAVAJgkAA==.Stevensiegal:BAAANQADCgIIAgAAAA==.Stormbless:BAAANQAECgcIEwAAAA==.Stormfallz:BAAANQAECgYICQAAAA==.',
Su='Superfrenzy:BAAANQADCgMIAwAAAA==.Supertotemz:BAAANQAECgEIAQAAAA==.Supervoid:BAAANQAECgIIAgABNQAECgcIBwACAAAAAA==.',
Sw='Swag:BAAANQADCgIIAgABNQADCggIDgACAAAAAA==.Sweegie:BAAANQAECgMIBAAAAA==.Sweegz:BAAANQADCgYIBgAAAA==.Sweetlou:BAAANQADCggICAAAAA==.',
Sy='Syds:BAAANQAECgIIAgAAAA==.Synapticzion:BAAANQADCgcICQAAAA==.',
['Sí']='Sílk:BAAANQADCgcIDgAAAA==.',
Ta='Taara:BAAANQAECgcIDgAAAA==.Takeshi:BAAANQABCgIIAgAAAA==.Takkana:BAAANQAECgcIDgAAAA==.Tatsuki:BAAANQABCgIIBAAAAA==.',
Te='Terk:BAABNQAECoEZAAQYAAkJ1yKnAACrAwAYAAkJ1yKnAACrAwAPAAEJESRWeQBlAAAWAAEJZAONlwAsAAAAAA==.',
Th='Thalrymere:BAAANQAECgQIBAAAAA==.Thiccerlegs:BAAANQADCgYICAAAAA==.',
Ti='Tidebeard:BAAANQAFFAEIAQAAAA==.Tikz:BAAANQAECgQIBgAAAA==.',
To='Tock:BAABNQAECoEZAAMYAAgJTBbQCADnAQAYAAYJChbQCADnAQAPAAYJLxBZOQBvAQAAAA==.Tokenwarrior:BAAANQAECgIIAgAAAA==.',
Tr='Tralina:BAAANQADCgMIAwABNQAECgcICwACAAAAAA==.Trapstâr:BAAANQAFFAEIAQABNQAFFAUIBwAPAEoSAA==.',
Ts='Tsarfun:BAAANQADCgQIBAABNQAECggICAACAAAAAA==.Tsireya:BAAANQADCgYIBgAAAA==.Tsunayoshii:BAAANQAECgYIBgAAAA==.',
Tu='Turf:BAAANQADCgUIBQAAAA==.',
Un='Undeadwaifu:BAAANQADCgEIAQAAAA==.Unkledeath:BAAANQAECgIIAwAAAA==.',
Va='Vaeryn:BAAANQADCggIFAAAAA==.Valesyrin:BAAANQAECgQIBgAAAA==.Vansapanda:BAAANQADCggIEAAAAA==.Vaughn:BAABNQAECoEWAAMHAAkJuBvOAAAMAwAHAAkJVBnOAAAMAwABAAMJ1xCCggC4AAAAAA==.',
Ve='Veggieboi:BAAANQADCgcIBwAAAA==.Vellast:BAAANQAECgIIAgAAAA==.',
Vi='Viande:BAAANQADCgQIBAAAAA==.Victory:BAAANQAECgIIAwAAAA==.Vigilo:BAAANQAECgcIEAAAAA==.Vilhelmina:BAAANQAECgUICwAAAA==.Viruzdk:BAAANQAECgcIDgAAAA==.',
Vl='Vlad:BAAANQAECgMIBgAAAA==.Vladivostok:BAAANQADCgEIAQAAAA==.',
Wa='Wafi:BAAANQAECgEIAQAAAA==.Wamp:BAAANQAECgcIEQAAAA==.Warwonka:BAAANQAECgcIEQAAAA==.Watchurbeard:BAAANQAECgQIBgAAAA==.',
We='Weenrgulpr:BAAANQADCgUICAAAAA==.',
Wh='Whamass:BAAANQAECgMIAwAAAA==.Whippy:BAAANQADCggICAABNQAECgcIEQACAAAAAA==.',
Wi='Windowlicker:BAAANQAECgUIBQAAAA==.Winnydafoo:BAAANQADCgQIBgAAAA==.',
Wr='Wrapfire:BAAANQAECgIIAgAAAA==.',
['Wí']='Wíldspirit:BAAANQADCgQIBQAAAA==.',
Ya='Yacob:BAABNQAECoEZAAMRAAkJKCG7DABXAwARAAkJKCG7DABXAwAZAAUJNBpoBwBfAQAAAA==.Yamarahj:BAABNQAECoEYAAQDAAkJ+xnKBgBmAgADAAgJChjKBgBmAgAIAAcJ4hfbKADIAQAQAAEJ0xneEQBNAAAAAA==.',
Yo='Yorikk:BAAANQAECgQICQAAAA==.',
Yu='Yui:BAAANQABCgIIAgAAAA==.',
Za='Zafhir:BAAANQABCgUICAAAAA==.Zankanotachi:BAAANQAECgEIAQAAAA==.Zarmaku:BAAANQAECgMIAwAAAA==.Zartath:BAAANQADCgcIBwAAAA==.Zauber:BAABNQAECoEZAAQQAAkJRSYGAADtAwAQAAkJQSYGAADtAwAIAAcJ7CJqDACuAgADAAYJ5iToCAA2AgAAAA==.Zazie:BAAANQAECgQIBgAAAA==.Zazu:BAAANQADCgIIAgAAAA==.',
Ze='Zepian:BAAANQAECgYICAAAAA==.',
Zi='Zirraj:BAABNQAECoEZAAMBAAkJMyUQAgDMAwABAAkJMyUQAgDMAwAHAAUJdBu/BgBvAQAAAA==.',
Zy='Zygon:BAAANQADCggICAABNQAECgcIBwACAAAAAA==.',
['Âr']='Ârthilasi:BAAANQAECgQIBAAAAA==.',
['Èó']='Èówyn:BAAANQAECgQICAAAAA==.',
['Év']='Évié:BAEANQAECgYIBgAAAA==.',
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
