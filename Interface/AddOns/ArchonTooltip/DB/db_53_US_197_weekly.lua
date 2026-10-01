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

local lookup = {'Hunter-BeastMastery','Monk-Brewmaster','Unknown-Unknown','DeathKnight-Blood','Mage-Arcane','Mage-Fire','DeathKnight-Unholy','Priest-Shadow','Monk-Windwalker','Priest-Holy','Paladin-Retribution','Warrior-Fury','Warrior-Arms','Paladin-Holy','Shaman-Enhancement','Shaman-Elemental',}
local provider = {region='US',realm='SistersofElune',name='US',type='weekly',zone=53,date='2026-09-29',data={Al='Althenara:BAAANQADCgUIBgAAAA==.Alysard:BAAANQAECgIIAgAAAA==.',
Am='Amaurine:BAAANQAECgIIBAAAAA==.',
An='Anoras:BAAANQADCgcIEAAAAA==.',
Ar='Aratfu:BAAANQAECgIIAwABNQAECgcIGgABAB8VAA==.Arteymis:BAAANQADCgQIBAABNQAECggIGwACACcgAA==.Arui:BAAANQAECgMIBAAAAA==.',
At='Athania:BAAANQADCgEIAQABNQAECgYIDwADAAAAAA==.Athornia:BAAANQADCgUIBQAAAA==.',
Au='Aumery:BAABNQAECoEYAAIEAAcKRxEVRwCaAQAEAAcKRxEVRwCaAQAAAA==.Autoflick:BAAANQADCgYJBgAAAA==.',
Aw='Awwee:BAAANQADCgUJBQAAAA==.',
Az='Azinozl:BAAANQADCgcIBwAAAA==.Azipaly:BAAANQAECgYICAAAAA==.Azurite:BAAANQAECgYICgAAAA==.',
Ba='Baelthos:BAAANQAECgMIBAAAAA==.Barebut:BAAANQADCgEIAQAAAA==.',
Be='Bermon:BAAANQADCgYIBgABNQAECgcIGAAEAEcRAA==.Berrypunch:BAAANQADCgYIDwAAAA==.',
Bi='Bingo:BAAANQAECgQICAAAAA==.',
Bl='Bluebyyou:BAAANQAECgMICQABNQAECgQIBAADAAAAAA==.',
Bo='Borgor:BAAANQADCgEIAQAAAA==.',
Bu='Bubblé:BAAANQAECgUICQAAAA==.Bustei:BAAANQAECgEIAQAAAA==.',
Ca='Caelion:BAAANQAECgYIEgAAAA==.Cannex:BAAANQAECgMIAwAAAA==.',
Ce='Celestia:BAAANQAECgUIBwAAAA==.',
Cl='Clarinet:BAAANQABCgEIAQABNQAECgQJBAADAAAAAA==.Clarinetbdk:BAAANQAECgQJBAAAAA==.',
De='Deathhunter:BAAANQABCgQIBAAAAA==.Deekon:BAAANQAECgYIDgAAAA==.Deshand:BAAANQABCgEIAQAAAA==.Deyvian:BAAANQADCgQIBAAAAA==.',
Do='Dooplikit:BAAANQADCgYIBwAAAA==.',
Dp='Dpn:BAABNQAECoEeAAMFAAgKKCOFJgAvAwAFAAgKKCOFJgAvAwAGAAEK1AssCQBFAAABNQAECgQIBwADAAAAAA==.',
Dr='Draxil:BAAANQADCgcICgAAAA==.Druish:BAAANQADCgYICgAAAA==.',
Du='Durpp:BAAANQAECgMIBAAAAA==.Dusyk:BAAANQADCgMIAwABNQADCggICQADAAAAAA==.',
['Dä']='Däisymäy:BAAANQADCgEIAQABNQAECgQICAADAAAAAA==.',
Eg='Egud:BAAANQAECgUIEAAAAA==.',
El='Elipse:BAAANQADCgQIBAAAAA==.Eliri:BAAANQAECgcIEwAAAA==.Ellenad:BAAANQAECgEIAgAAAA==.',
En='Enemy:BAAANQAECgUICQABNQAECgYIBgADAAAAAA==.',
Es='Estia:BAAANQABCgEIAQAAAA==.',
Ev='Everflux:BAAANQAECgYIEgAAAA==.Evo:BAAANQAECgYIBgAAAA==.',
Ey='Ey:BAAANQADCggIGgAAAA==.',
Fa='Farisu:BAACNQAFFIEIAAMHAAUKNwmJCQDzAAAHAAQK2QWJCQDzAAAEAAEKsBayIABCAAA1AAQKgRsAAwcACQrWHdohAHQCAAcACQqvHNohAHQCAAQABArqG2toAAcBAAAA.',
Fe='Feoran:BAAANQADCgIIAgAAAA==.',
Fj='Fjara:BAAANQADCgYIBgAAAA==.',
Fl='Flick:BAAANQAECgQIBAAAAA==.',
Ge='Georish:BAAANQAECgIIAgAAAA==.',
Gi='Gilgamësh:BAAANQADCgIIAgAAAA==.Ginseng:BAAANQAECgYIDwAAAA==.Giritos:BAAANQADCgYIBgAAAA==.Girthquake:BAAANQAECgYIEwAAAA==.',
Go='Gorg:BAAANQADCgMIAwAAAA==.',
['Gé']='Gémini:BAAANQAECgMIAwAAAA==.',
Ha='Haavoc:BAAANQAECgEIAQABNQAECgcIEQADAAAAAA==.Hagul:BAAANQAECgIIAgAAAA==.Hakuad:BAAANQADCgIIAgAAAA==.Halanhar:BAAANQADCgcICgAAAA==.Hashi:BAAANQADCgIIAgAAAA==.',
He='Hellrocker:BAAANQAECgMIAwAAAA==.Hermione:BAAANQAECgMIBAABNQAECgEIAQADAAAAAA==.Hestia:BAAANQABCgQIBAAAAA==.',
Ho='Holyvader:BAAANQADCggICAAAAA==.',
Hu='Hukhan:BAAANQABCgYICAAAAA==.Huraaki:BAAANQAECgIIAgAAAA==.',
In='Innis:BAAANQAECgUIEQAAAA==.',
Ir='Irine:BAAANQAECgIIAwAAAA==.Irore:BAAANQAECgIIAgAAAA==.',
It='Itszoi:BAAANQADCgIIAgAAAA==.',
Je='Jetahnna:BAAANQAECgEIAgAAAA==.',
Ji='Jibbs:BAAANQADCggIEgAAAA==.',
Jo='Jozlinn:BAABNQAECoEbAAIIAAcKxgXlNAAnAQAIAAcKxgXlNAAnAQAAAA==.',
Ka='Kaeldar:BAAANQAECgIIBQAAAA==.Kajadin:BAAANQAECgMIBAAAAA==.Karatedonkey:BAAANQAECgMIBAAAAA==.Kardai:BAEANQAECgMIBAAAAA==.Katreia:BAAANQAECgcIBwABNQAFFAYIEQAEAJoVAA==.Kazimas:BAAANQADCgcJFQAAAA==.',
Kh='Khalcite:BAAANQAECgMIBAAAAA==.',
Ki='Kittyshaman:BAAANQAECgYIDwAAAA==.',
Kr='Kristyleigh:BAAANQABCgQIBAAAAA==.',
Ku='Kurono:BAAANQAECgMIBAAAAA==.Kuross:BAAANQAECgIIBQAAAA==.',
La='Laermeluion:BAAANQAECgcIBwABNQAFFAYIEQAEAJoVAA==.Larra:BAAANQAECgQICAAAAA==.',
Le='Leen:BAAANQAECgEIAQAAAA==.Lefthian:BAAANQAECgQICAAAAA==.',
Lf='Lftwentyones:BAAANQADCgYICwABNQAECgcIEwADAAAAAA==.',
Li='Limptriscuit:BAAANQADCgYIBgAAAA==.',
Lo='Loshing:BAAANQAECgEIAwAAAA==.',
Lu='Lunakae:BAAANQADCgIIAgAAAA==.',
Ma='Macumba:BAAANQADCgEIAQAAAA==.Madeline:BAABNQAECoEaAAIIAAgK/h57DwDKAgAIAAgK/h57DwDKAgAAAA==.Malafar:BAAANQAECgYIBwAAAA==.Maranwae:BAAANQAECgQIEQAAAA==.Masochist:BAAANQAECgQIDAABNQAECgEIAQADAAAAAA==.',
Me='Melokoi:BAAANQAECgEIAgAAAA==.Merlose:BAAANQAECgIJAwAAAA==.',
Mi='Mieditos:BAAANQAECgMIAwAAAA==.Minirocks:BAAANQAECgcIEQABNQAECgkJHQAJABAgAA==.',
Mo='Moondivine:BAAANQAECgEIAQAAAA==.Moonfaith:BAAANQAECgEIAQABNQAECgEIAQADAAAAAA==.Moosader:BAAANQADCgYIGQAAAA==.',
Na='Naleana:BAAANQADCgYIFgAAAA==.Narzwaz:BAAANQAECgMIBAAAAA==.Nataly:BAAANQAECgUIDAAAAA==.',
Ne='Neytri:BAAANQAECgUIEAAAAA==.',
No='Nommo:BAAANQAECgQIBAAAAA==.Nophica:BAAANQAECgQIBAAAAA==.Novaxian:BAAANQAECgEIAQAAAA==.',
Nz='Nzoth:BAAANQAECgcICQAAAA==.',
On='Oneeyedwilly:BAAANQADCgcIBwAAAA==.',
Os='Osaka:BAAANQAECgMIBAAAAA==.',
Pa='Patches:BAAANQAECgQICgAAAA==.',
Pl='Plagos:BAAANQADCgEIAQAAAA==.',
Po='Pouncival:BAAANQADCgEIAQAAAA==.',
Pr='Prahumn:BAABNQAECoEfAAIKAAgKRR7pHgC+AgAKAAgKRR7pHgC+AgAAAA==.',
Pu='Purplicious:BAAANQADCggIFQAAAA==.',
Py='Pymilocs:BAAANQAECgYIDwAAAA==.',
Qi='Qixx:BAAANQAECgQIBgAAAA==.',
Qu='Quint:BAAANQADCgUIDQAAAA==.',
Ra='Rabore:BAAANQAECgMIAwAAAA==.Raktal:BAAANQABCgIIAgAAAA==.Ralee:BAAANQAECgYIEAAAAA==.Ralienne:BAAANQADCgIIAgABNQAECgYIEAADAAAAAA==.Ravinia:BAAANQADCgEIAQAAAA==.',
Re='Rennai:BAAANQAECgIIAgAAAA==.',
Ri='Richter:BAAANQADCggIIAAAAA==.Rin:BAEANQAECgUICAAAAA==.',
Ro='Rogelink:BAAANQADCgYIBgAAAA==.Rosan:BAAANQAECgMIBQAAAA==.Royakan:BAAANQABCgUIBQAAAA==.',
Ru='Rumtumtugger:BAAANQADCgUIBQAAAA==.',
Sa='Samoset:BAAANQAECgMIAwAAAA==.Sasten:BAAANQADCgMIAwAAAA==.',
Se='Serosion:BAAANQADCgcIBwAAAA==.',
Sh='Shaile:BAAANQAECgYIDwAAAA==.Shalu:BAAANQABCgUIBQAAAA==.Shammysham:BAAANQADCggIFgAAAA==.Shifthappons:BAAANQADCgUIBQAAAA==.Shockisha:BAAANQAECgEJAQAAAA==.Shogoth:BAAANQADCgEIAQAAAA==.',
Si='Sightseer:BAAANQAECgYICwAAAA==.Silverthorn:BAAANQAECgIIAwAAAA==.',
Sk='Skrom:BAAANQADCgIIAgAAAA==.',
Sw='Sweetti:BAAANQADCgcIBwABNQAECgQICAADAAAAAA==.',
Sy='Sybbil:BAAANQADCgQIBAAAAA==.',
Ta='Tad:BAAANQAECgQICgAAAA==.Takara:BAAANQABCggIFQAAAA==.Taken:BAAANQAECgIIAgAAAA==.Tazra:BAABNQAECoEhAAILAAgKyB1PQACKAgALAAgKyB1PQACKAgAAAA==.',
Th='Theshammslam:BAAANQADCgMIAwAAAA==.Thomaz:BAABNQAECoEcAAMMAAgKuAgHEwAbAQANAAcKHAmNoABnAQAMAAYKoQcHEwAbAQAAAA==.Thx:BAAANQADCgEJAQAAAA==.',
Ti='Tiarini:BAAANQADCggIGQAAAA==.Tilee:BAAANQADCgUIBQAAAA==.',
To='Tondri:BAABNQAECoEbAAIOAAgKQhHzTADxAQAOAAgKQhHzTADxAQAAAA==.Tonkatruck:BAAANQAECgMIAwAAAA==.',
Tr='Traice:BAAANQABCgYICQAAAA==.',
Tu='Tuyenlotus:BAABNQAECoEbAAIPAAkK1xbMCAC7AgAPAAkK1xbMCAC7AgAAAA==.',
['Tò']='Tòkkí:BAAANQAECgIIAgAAAA==.',
Va='Vahnya:BAAANQAECgYIDwAAAA==.',
Ve='Venekor:BAAANQADCggICQAAAA==.',
Vi='Vicarrion:BAAANQAECgYICwAAAA==.Viscera:BAAANQADCgEIAQAAAA==.Vitesse:BAAANQADCgcIBwAAAA==.',
Vl='Vlane:BAAANQADCgEIAQAAAA==.',
Vr='Vrat:BAABNQAECoEaAAIBAAcKHxXfaQDnAQABAAcKHxXfaQDnAQAAAA==.',
['Ví']='Ví:BAAANQAECgQIBQAAAA==.',
Wa='Warfare:BAAANQAECgcIEQAAAA==.Warxie:BAAANQADCggIDgAAAA==.',
We='Wendrix:BAAANQADCggICAAAAA==.',
Wt='Wtfoxtrot:BAAANQADCggICAAAAA==.',
Yo='Yourmageisty:BAAANQAECgYIDwAAAA==.',
Yu='Yulíana:BAAANQAECgUIDAAAAA==.',
Za='Zanot:BAAANQADCgQIBAAAAA==.',
Zc='Zcart:BAAANQAECgYIDwAAAA==.',
Ze='Zelara:BAAANQAECgIIAQAAAA==.Zeluxum:BAAANQAECgEJAQABNQAECgMIAwADAAAAAA==.Zerkio:BAAANQAECgYIEgAAAA==.Zertloc:BAABNQAECoEaAAIQAAkKmhkhJAC9AgAQAAkKmhkhJAC9AgAAAA==.',
Zi='Zieda:BAAANQAECgQICAAAAA==.',
Zo='Zoids:BAAANQADCgEIAQAAAA==.',
Zu='Zulix:BAAANQADCgEIAQAAAA==.Zulixx:BAAANQADCgQIBAAAAA==.',
Zy='Zyriatchi:BAAANQAECgMIAwAAAA==.',
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
