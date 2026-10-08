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

local lookup = {'Hunter-BeastMastery','Monk-Brewmaster','Unknown-Unknown','DeathKnight-Blood','Paladin-Holy','DeathKnight-Unholy','Mage-Arcane','Mage-Fire','Warrior-Protection','Priest-Holy','Shaman-Restoration','Warrior-Arms','Priest-Discipline','Priest-Shadow','Shaman-Elemental','Shaman-Enhancement','Paladin-Retribution','Warrior-Fury','Mage-Frost','Hunter-Marksmanship',}
local provider = {region='US',realm='SistersofElune',name='US',type='weekly',zone=53,date='2026-10-06',data={Al='Althenara:BAAANQAECgQIBAAAAA==.Alysard:BAAANQAECgYICAAAAA==.',
Am='Amaurine:BAAANQAECgIIBAAAAA==.',
An='Anoras:BAAANQADCgcIEAAAAA==.',
Ar='Aratfu:BAAANQAECgQIBwABNQAECggIGwABAH0VAA==.Archivus:BAAANQADCgYIBgAAAA==.Arteymis:BAAANQADCgQIBAABNQAECggIGwACACcgAA==.Arui:BAAANQAECgQICAAAAA==.',
At='Athania:BAAANQAECgQIBAABNQAECgcIEAADAAAAAA==.Athornia:BAAANQADCgUIBQAAAA==.',
Au='Aumery:BAABNQAECoEfAAIEAAcKLRMHTACmAQAEAAcKLRMHTACmAQAAAA==.Autoflick:BAAANQADCgYJBgAAAA==.',
Aw='Awwee:BAAANQADCgUJBQAAAA==.',
Az='Azinozl:BAAANQAECgQIAgABNQAECggIDwADAAAAAA==.Azipaly:BAAANQAECggIDwAAAA==.Azurite:BAAANQAECgYIEAAAAA==.',
Ba='Baelthos:BAAANQAECgQICAAAAA==.Barebut:BAAANQADCgEIAQAAAA==.',
Be='Bermon:BAAANQADCgYIDAABNQAECgcIHwAEAC0TAA==.Berrypunch:BAAANQADCgYIDwAAAA==.',
Bi='Bingo:BAAANQAECgQICAAAAA==.',
Bl='Bluebyyou:BAAANQAECgQICgABNQAECgUICQADAAAAAA==.',
Bo='Borgor:BAAANQADCgEIAQAAAA==.',
Bu='Bubblé:BAAANQAECgUIDQAAAA==.Bustei:BAAANQAECgEIAQAAAA==.',
Ca='Caelion:BAABNQAECoEcAAIFAAgKPiJTFAAfAwAFAAgKPiJTFAAfAwAAAA==.Cannex:BAAANQAECgQIBwAAAA==.',
Ce='Celestia:BAAANQAECgUIBwAAAA==.',
Cl='Clarinet:BAAANQABCgEIAQABNQAECgQIBAADAAAAAA==.Clarinetbdk:BAAANQAECgQIBAAAAA==.',
Co='Coomerlord:BAAANQABCgYIBgAAAA==.',
Da='Daki:BAAANQADCgUIBQABNQAECgcIGQAGACcMAA==.',
De='Deathhunter:BAAANQABCgQIBAAAAA==.Deekon:BAAANQAECgYIEgAAAA==.Delryn:BAAANQAECgEIAQAAAA==.Deshand:BAAANQABCgEIAQAAAA==.Deyvian:BAAANQADCgQIBAAAAA==.',
Do='Dooplikit:BAAANQADCgYIBwAAAA==.',
Dp='Dpn:BAABNQAECoEhAAMHAAgKKCMGMwAYAwAHAAgKKCMGMwAYAwAIAAEK1AvECgA/AAABNQAECgQIBwADAAAAAA==.',
Dr='Draxil:BAAANQADCgcICgAAAA==.Druish:BAAANQADCgYICgAAAA==.',
Du='Durpp:BAAANQAECgQICAAAAA==.Dusyk:BAAANQAECgIIAgAAAA==.',
['Dä']='Däisymäy:BAAANQADCgEIAQABNQAECgUIEQADAAAAAA==.',
Eg='Egud:BAABNQAECoEYAAIJAAcKSxhBEQDkAQAJAAcKSxhBEQDkAQAAAA==.',
El='Elipse:BAAANQADCgUIBgAAAA==.Eliri:BAAANQAECgcIEwABNQAFFAIIAgADAAAAAA==.Ellenad:BAAANQAECgIIAwAAAA==.',
En='Enemy:BAAANQAECgUICQABNQAECgcICwADAAAAAA==.',
Es='Estia:BAAANQABCgEIAQAAAA==.',
Ev='Everflux:BAABNQAECoEaAAIKAAcKIx/wNQBuAgAKAAcKIx/wNQBuAgAAAA==.Evo:BAAANQAECgcICwAAAA==.',
Ey='Ey:BAAANQAECgIIAgAAAA==.',
Fa='Farisu:BAACNQAFFIELAAMGAAUKTA9tDAAZAQAGAAQKdA1tDAAZAQAEAAEKsBYJJwBBAAA1AAQKgR0AAwYACQrWHRMuAFcCAAYACQqvHBMuAFcCAAQABArqGxB1AP0AAAAA.',
Fe='Feoran:BAAANQADCgIIAgAAAA==.',
Fj='Fjara:BAAANQADCgYIBgAAAA==.',
Fl='Flick:BAAANQAECgQIBAAAAA==.',
Fr='Frontallover:BAAANQADCgEIAQABNQAFFAIIAgADAAAAAA==.',
Ge='Georish:BAAANQAECgUIBgAAAA==.',
Gi='Gilgamësh:BAAANQADCgIIAgAAAA==.Ginseng:BAAANQAECgcIEAAAAA==.Giritos:BAAANQADCgYIBgAAAA==.Girthquake:BAABNQAECoEeAAILAAgKcCPUEAAoAwALAAgKcCPUEAAoAwAAAA==.',
Go='Gorg:BAAANQADCgMIAwAAAA==.',
['Gé']='Gémini:BAAANQAECgUICAAAAA==.',
Ha='Haavoc:BAAANQAECgEIAQABNQAECggIGwAMAH0HAA==.Hagul:BAAANQAECgIIAgAAAA==.Hakuad:BAAANQADCgIIAgAAAA==.Halanhar:BAAANQADCgcICgAAAA==.Hashi:BAAANQADCgIIAgAAAA==.',
He='Hellrocker:BAAANQAECgQIBwAAAA==.Hermione:BAAANQAECgMIBAABNQAECgEIAQADAAAAAA==.Hestia:BAAANQABCgQIBAAAAA==.',
Ho='Holyvader:BAAANQADCggICAAAAA==.',
Hu='Hukhan:BAAANQABCgYICAAAAA==.Huraaki:BAAANQAECgIIAgAAAA==.',
In='Innis:BAABNQAECoEZAAMKAAcKXBz6SwAYAgAKAAcKXBz6SwAYAgANAAEKVwfRKQAqAAAAAA==.',
Ir='Irine:BAAANQAECgUICgAAAA==.Irore:BAAANQAECgQIBgAAAA==.',
It='Itszoi:BAAANQADCgIIAgAAAA==.',
Je='Jenjyandi:BAAANQADCgYIBgABNQAECgQICAADAAAAAA==.Jetahnna:BAAANQAECgMIBQAAAA==.',
Ji='Jibbs:BAAANQADCggIEgAAAA==.',
Jo='Jozlinn:BAABNQAECoEhAAIOAAcK6QWYOwAjAQAOAAcK6QWYOwAjAQAAAA==.',
Ka='Kaeldar:BAAANQAECgIIBQAAAA==.Kajadin:BAAANQAECgQICAAAAA==.Karatedonkey:BAAANQAECgQICAAAAA==.Kardai:BAEANQAECgQICAAAAA==.Katreia:BAAANQAECgcICgABNQAFFAYIFwAEAHgWAA==.Kazimas:BAAANQADCgcJFQAAAA==.',
Kh='Khalcite:BAAANQAECgQICAAAAA==.',
Ki='Kittyshaman:BAABNQAECoEZAAIPAAgKXwUSgwBsAQAPAAgKXwUSgwBsAQAAAA==.',
Kr='Kristyleigh:BAAANQABCgQIBAAAAA==.',
Ku='Kurono:BAAANQAECgQICAAAAA==.Kuross:BAAANQAECgIIBgAAAA==.',
La='Laermeluion:BAAANQAECgcIBwABNQAFFAYIFwAEAHgWAA==.Larra:BAAANQAECgUIEQAAAA==.',
Le='Leen:BAAANQAECgEIAQAAAA==.Lefthian:BAAANQAECgQIDAAAAA==.Leonidas:BAAANQADCgYIBgAAAA==.',
Lf='Lftwentyones:BAAANQADCgYICwABNQAFFAIIAgADAAAAAA==.',
Li='Limptriscuit:BAAANQADCgYIBgAAAA==.',
Lo='Loshing:BAAANQAECgEIAwAAAA==.',
Lu='Lunakae:BAAANQADCgIIAgAAAA==.',
Ma='Macumba:BAAANQADCgQIBwAAAA==.Madeline:BAABNQAECoEaAAIOAAgK/h4IEwC0AgAOAAgK/h4IEwC0AgAAAA==.Malafar:BAAANQAECgYIBwAAAA==.Maranwae:BAABNQAECoEaAAMLAAcKDBkNUQD0AQALAAcKDBkNUQD0AQAPAAIKpAhd9QBmAAAAAA==.Masochist:BAAANQAECgYIDgABNQAECgEIAQADAAAAAA==.',
Me='Melokoi:BAAANQAECgEIAgAAAA==.Merlose:BAAANQAECgIJAwAAAA==.',
Mi='Mieditos:BAAANQAECgMIBAAAAA==.Minirocks:BAABNQAECoEbAAMQAAgK7g9IEgAjAgAQAAgK7g9IEgAjAgALAAcKPBXQYgC2AQAAAA==.',
Mo='Moondivine:BAAANQAECgEIAQAAAA==.Moonfaith:BAAANQAECgEIAQABNQAECgEIAQADAAAAAA==.Moosader:BAAANQADCgYIHwAAAA==.',
Na='Naleana:BAAANQADCgYIHAAAAA==.Narzwaz:BAAANQAECgQICAAAAA==.Nataly:BAAANQAECgUIDwAAAA==.',
Ne='Neytri:BAABNQAECoEYAAIBAAcKrg3yjgC6AQABAAcKrg3yjgC6AQAAAA==.',
No='Nommo:BAAANQAECgUICQAAAA==.Nophica:BAAANQAECgYICgAAAA==.Novaxian:BAAANQAECgMIBAAAAA==.Noxicous:BAAANQADCggICAAAAA==.',
Nz='Nzoth:BAAANQAECgcIDgAAAA==.',
On='Oneeyedwilly:BAAANQADCgcIBwAAAA==.',
Os='Osaka:BAAANQAECgQICAAAAA==.',
Pa='Patches:BAAANQAECgUICwAAAA==.',
Pe='Peänuts:BAAANQADCggICAAAAA==.',
Pl='Plagos:BAAANQADCgQIBQAAAA==.',
Po='Pouncival:BAAANQADCgEIAQAAAA==.',
Pr='Prahumn:BAABNQAECoEnAAMKAAkKTR0NFQASAwAKAAkKTR0NFQASAwAOAAEKmQaJewAhAAAAAA==.',
Pu='Purplicious:BAAANQAECgIIAgAAAA==.',
Py='Pymilocs:BAABNQAECoEYAAIPAAgKUh7JJwDCAgAPAAgKUh7JJwDCAgAAAA==.',
Qi='Qixx:BAAANQAECgQICQAAAA==.',
Qu='Quint:BAAANQADCgUIDQAAAA==.',
Ra='Rabore:BAAANQAECgMIAwAAAA==.Raktal:BAAANQABCgIIAgAAAA==.Ralee:BAABNQAECoEZAAIGAAcKJwz3ZQBTAQAGAAcKJwz3ZQBTAQAAAA==.Ralienne:BAAANQADCgYICAABNQAECgcIGQAGACcMAA==.Ravinia:BAAANQADCgEIAQAAAA==.',
Re='Rennai:BAAANQAECgIIAgAAAA==.',
Ri='Richter:BAAANQADCggIIAAAAA==.Rin:BAEANQAECgYIDgAAAA==.',
Ro='Rogelink:BAAANQADCgYIBgAAAA==.Rosan:BAAANQAECgMIBQAAAA==.Royakan:BAAANQABCgUIBQAAAA==.',
Ru='Rumtumtugger:BAAANQADCgUIBQAAAA==.',
Sa='Samoset:BAAANQAECgQIBwAAAA==.Sasten:BAAANQADCgMIAwAAAA==.',
Se='Serosion:BAAANQADCgcIBwAAAA==.',
Sh='Shaile:BAAANQAECgcIEAAAAA==.Shalu:BAAANQABCgUIBQAAAA==.Shammysham:BAAANQADCggIFgAAAA==.Shifthappons:BAAANQADCgUIBQAAAA==.Shockisha:BAAANQAECgEJAQAAAA==.Shogoth:BAAANQADCgEIAQAAAA==.',
Si='Sightseer:BAAANQAECgYIEQAAAA==.Silverthorn:BAAANQAECgUIDAAAAA==.',
Sk='Skrom:BAAANQADCgIIAgAAAA==.',
Sn='Sney:BAAANQADCgUIBQABNQAECgcIGQAGACcMAA==.',
Sw='Sweetti:BAAANQADCgcIBwABNQAECgUIEQADAAAAAA==.',
Sy='Sybbil:BAAANQADCgQIBAAAAA==.',
Ta='Tad:BAAANQAECgUICwAAAA==.Takara:BAAANQABCggIGQAAAA==.Taken:BAAANQAECgQIBgAAAA==.Tazra:BAABNQAECoElAAIRAAkKKx63NQDVAgARAAkKKx63NQDVAgAAAA==.',
Th='Theshammslam:BAAANQADCgMIAwAAAA==.Thomaz:BAABNQAECoEeAAMSAAgKuAhgFgAUAQAMAAcKHAkdtQBoAQASAAYKoQdgFgAUAQAAAA==.Thx:BAAANQAECgIIAgAAAA==.',
Ti='Tiarini:BAAANQADCggIIAAAAA==.Tilee:BAAANQADCgUIBQAAAA==.',
To='Tondri:BAABNQAECoEjAAIFAAgKwRQFTwAPAgAFAAgKwRQFTwAPAgAAAA==.Tonkatruck:BAAANQAECgQIBwAAAA==.',
Tr='Traice:BAAANQABCgYICQAAAA==.',
Tu='Tuyenlotus:BAABNQAECoEeAAIQAAkKfhiOCgC1AgAQAAkKfhiOCgC1AgAAAA==.',
['Tò']='Tòkkí:BAAANQAECgUIBQAAAA==.',
Va='Vahnya:BAABNQAECoEYAAIPAAgKoxS0TQATAgAPAAgKoxS0TQATAgAAAA==.',
Ve='Venekor:BAAANQADCggICQAAAA==.',
Vi='Vicarrion:BAAANQAECgYIEQAAAA==.Viscera:BAAANQADCgIIAwAAAA==.Vitesse:BAAANQADCgcIBwAAAA==.',
Vl='Vlane:BAAANQADCgEIAQAAAA==.',
Vr='Vrat:BAABNQAECoEbAAIBAAgKfRWaXgAxAgABAAgKfRWaXgAxAgAAAA==.',
['Ví']='Ví:BAAANQAECgQIBQAAAA==.',
Wa='Warfare:BAABNQAECoEbAAIMAAgKfQdGrACBAQAMAAgKfQdGrACBAQAAAA==.Warxie:BAAANQADCggIDgABNQAECgUIBwADAAAAAA==.',
We='Wendrix:BAAANQADCggICAAAAA==.',
Wt='Wtfoxtrot:BAAANQADCggICAAAAA==.',
Yo='Yourmageisty:BAABNQAECoEYAAMTAAcKwxXgHADfAAAHAAYKqBO55QCXAQATAAMKVhngHADfAAAAAA==.',
Yu='Yulíana:BAAANQAECgYIDwAAAA==.',
Za='Zanot:BAAANQADCgQIBAAAAA==.',
Zc='Zcart:BAABNQAECoEYAAMBAAgKSRBDagASAgABAAgKSRBDagASAgAUAAIKEAWRbQBTAAAAAA==.',
Ze='Zelara:BAAANQAECgIIAQAAAA==.Zeluxum:BAAANQAECgEJAQABNQAECgQIBwADAAAAAA==.Zerkio:BAABNQAECoEcAAILAAgKTxVwRQAhAgALAAgKTxVwRQAhAgAAAA==.Zertloc:BAABNQAECoEtAAIPAAkKyx3EGQAXAwAPAAkKyx3EGQAXAwAAAA==.',
Zi='Zieda:BAAANQAECgYICgAAAA==.',
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
