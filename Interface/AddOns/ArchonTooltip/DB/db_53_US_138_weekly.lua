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

local lookup = {'Unknown-Unknown','Mage-Arcane','Mage-Frost','Warlock-Demonology','Priest-Shadow',}
local provider = {region='US',realm='KulTiras',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aarix:BAAANQAECgIIAwAAAA==.',
Ae='Aendillan:BAAANQADCgUIBQAAAA==.',
Af='Affonasei:BAAANQAECgEIAQAAAA==.',
Ai='Aileen:BAAANQADCgQIAgAAAA==.',
Al='Alacrodie:BAAANQADCgIIAgAAAA==.',
Am='Amoonsi:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.',
An='Angrytotems:BAAANQADCgUIBQABNQAECgQIBwABAAAAAA==.Annaborshen:BAAANQABCgIIAgAAAA==.Antoccino:BAAANQAECgEIAQAAAA==.',
Ar='Aragorno:BAAANQAECgEIAQAAAA==.Arcturen:BAAANQADCgcIEgAAAA==.Arenthal:BAAANQAECgQIBAABNQAECgUICQABAAAAAA==.',
As='Asheby:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.Ashiera:BAAANQAECgEIAQAAAA==.Astralmorph:BAAANQADCgYIBgAAAA==.',
At='Atomic:BAAANQADCgMIBwAAAA==.',
Az='Azylstrid:BAAANQADCgYIBgAAAA==.',
Ba='Baeu:BAAANQABCgUIBwAAAA==.Balentine:BAAANQAECgMIBAAAAA==.Banostraza:BAAANQAECgEIAQAAAA==.Baspir:BAAANQAECgQIBQAAAA==.',
Be='Beeboop:BAAANQABCgYICAAAAA==.Belly:BAAANQAECgUIBwAAAA==.Belrae:BAAANQADCggIDQAAAA==.Benchfresh:BAAANQADCgYICAAAAA==.Bendah:BAAANQADCgcIBwAAAA==.Bender:BAAANQADCgYIBgAAAA==.Bezieck:BAAANQADCgUIBQAAAA==.',
Bi='Bigfolks:BAAANQADCgIIAgAAAA==.Bigollock:BAAANQADCgYICwAAAA==.',
Bl='Bloodarrow:BAAANQADCgEIAQAAAA==.Bloodbound:BAAANQADCgYIBgAAAA==.',
Bo='Bockchi:BAAANQABCgIIAgAAAA==.Bonegavel:BAAANQABCgQIBgAAAA==.',
Br='Branex:BAAANQADCggICAAAAA==.Branpaw:BAAANQADCgMIAwAAAA==.Brewdeez:BAAANQAECgQIBQAAAA==.Brewzen:BAAANQADCgYIBgAAAA==.Brewzer:BAAANQAECgYIBwAAAA==.Brick:BAAANQADCgQIBAAAAA==.Brint:BAAANQADCgQIBAAAAA==.Bronad:BAABNQAECoEYAAMCAAkJtyXwCQBuAwACAAkJtyXwCQBuAwADAAEJPx8FGABMAAAAAA==.Broomhandle:BAAANQAECgIIAgAAAA==.',
Bu='Burinn:BAAANQADCgcIEgABNQAECgMIAwABAAAAAA==.',
Ca='Caeus:BAAANQADCggIFQAAAA==.Cam:BAAANQAECgUIBwAAAA==.Carolinabele:BAAANQADCggICAAAAA==.Cauud:BAAANQADCgMIBAAAAA==.',
Cb='Cbd:BAAANQADCgcIDgAAAA==.',
Ce='Celerious:BAAANQABCgIIAgAAAA==.',
Ch='Chacruna:BAAANQAECgEIAgAAAA==.Chelan:BAAANQAECgMIAwAAAA==.Chronicler:BAAANQADCgEIAQAAAA==.Chuntspeed:BAAANQABCgYIBgAAAA==.Chuye:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.',
Cl='Clambulance:BAAANQAECgUICwAAAA==.',
Co='Codythedead:BAAANQAECgcIEgAAAA==.Coraf:BAAANQAECgcIEAAAAA==.Coyotl:BAAANQADCggIEAAAAA==.',
Cu='Cuvier:BAAANQADCgcIDgAAAA==.',
Da='Danak:BAAANQADCgEIAQAAAA==.',
De='Deadlyfrosty:BAAANQADCgIIAgAAAA==.Deathmob:BAAANQADCggIDwAAAA==.Debixie:BAAANQAECgUICQAAAA==.Decisive:BAAANQADCgYIBgABNQAFFAYICgAEAHkdAA==.Dejection:BAAANQABCgYIBwAAAA==.Demisi:BAAANQAECgIIAwAAAA==.Demiurge:BAAANQAECgUIBgAAAA==.',
Di='Diasundra:BAAANQAECgUIBgAAAA==.Dibbons:BAAANQAECgQIBQAAAA==.Divinatjin:BAAANQADCgYICQAAAA==.',
Do='Dottingyou:BAAANQAECgcIEgAAAA==.',
Dr='Dracthyrbm:BAAANQADCgIIAgAAAA==.Dreepy:BAAANQAECgUIBQAAAA==.Drransom:BAAANQADCgEIAQAAAA==.Dryan:BAAANQAECgEIAQAAAA==.',
Du='Duo:BAAANQAECgQIBQAAAA==.Duragon:BAAANQAECgEIAgAAAA==.',
Ei='Eipwoc:BAAANQADCggIBwAAAA==.',
El='Eloreith:BAAANQADCgYIBgAAAA==.',
Em='Emamagee:BAAANQADCgQIBgAAAA==.Emilia:BAAANQAECgQIBAAAAA==.',
En='Endressa:BAAANQAECgYICgAAAA==.',
Er='Erelios:BAAANQADCggIFQAAAA==.',
Es='Eski:BAAANQAECgQIBAAAAA==.Essaena:BAAANQAECgIIAwAAAA==.',
Eu='Eureka:BAEANQAECgQIBAAAAA==.',
Fa='Faddeyshnek:BAAANQAECgUIBwAAAA==.Fatgirljuice:BAAANQADCgQIBAABNQAECggIDgABAAAAAA==.',
Fe='Felysambre:BAAANQADCgcIDwAAAA==.',
Fi='Fish:BAACNQAFFIEHAAIFAAMJ+yWmAQBIAQAFAAMJ+yWmAQBIAQA1AAQKgRgAAgUACQkEJjwAAPEDAAUACQkEJjwAAPEDAAAA.',
Fl='Flight:BAAANQAECgcIEQAAAA==.Floofee:BAAANQADCgQIBAAAAA==.',
Fo='Footfinger:BAAANQABCgMIAwAAAA==.Forsynth:BAAANQAECgEIAQAAAA==.',
Fu='Fubar:BAAANQABCgQIAwAAAA==.',
Ga='Ganniy:BAAANQABCgEIAQAAAA==.',
Ge='Gewitt:BAAANQADCggIDwAAAA==.',
Go='Gonjah:BAAANQADCgYIBgAAAA==.',
Gr='Grabomage:BAAANQADCggICwABNQAECgkJGAACALclAA==.Grabovoker:BAAANQADCgIIAgABNQAECgkJGAACALclAA==.Grazienne:BAAANQADCgEIAQAAAA==.Greavos:BAAANQAECgEIAQAAAA==.Griggus:BAAANQADCggIDQAAAA==.Grimgar:BAAANQAECgEIAQAAAA==.Grimmshady:BAAANQADCgQIBQAAAA==.',
Gu='Gumbles:BAAANQAECgQIBQAAAA==.Gurney:BAAANQAECgMIAwAAAA==.Guzprimal:BAAANQAECgEIAQAAAA==.',
Gy='Gying:BAAANQADCgcIEgAAAA==.',
Ha='Hannie:BAAANQADCgIIAgAAAA==.',
He='Headhúnter:BAAANQAECgIIAgAAAA==.Heartsparx:BAAANQAECgQIBAAAAA==.Heatseeka:BAAANQAECgMIAwAAAA==.',
Hi='Hiphopinator:BAAANQAECgEIAgAAAA==.',
Ho='Ho:BAAANQADCgQIBAAAAA==.Holyshock:BAAANQAECgUICgAAAA==.Holyterror:BAAANQADCgIIAgAAAA==.',
Ia='Ianthe:BAAANQADCgYIDQAAAA==.',
Ib='Iboga:BAAANQAECgMIBAAAAA==.Ibrahimovic:BAAANQADCgUICQAAAA==.',
Ig='Ignitecro:BAAANQABCgUICQAAAA==.Igram:BAAANQADCggICwAAAA==.',
Il='Iluz:BAAANQADCgMIAwAAAA==.',
In='Inafume:BAAANQADCggIDgAAAA==.Inoxia:BAAANQAECgIIBgAAAA==.Intrépidice:BAAANQAECgEIAQAAAA==.',
Ix='Ixtabay:BAAANQAECggIDgAAAA==.',
Ja='Jamurra:BAAANQADCggIFwAAAA==.Jaylinn:BAAANQAECgQIBQAAAA==.Jazzmend:BAAANQADCgYICgAAAA==.',
Je='Jellykins:BAAANQADCggICwABNQAECgEIAQABAAAAAA==.',
Ji='Jimsonweed:BAAANQAECgQIBQAAAA==.',
Jo='Josie:BAAANQADCggIFAAAAA==.Jozbirt:BAAANQAECgUIBQAAAA==.',
Ka='Kaeiria:BAAANQADCgQIBAAAAA==.Kael:BAAANQAECgEIAQAAAA==.Kalaanri:BAAANQADCgcIDAAAAA==.Kalyandra:BAAANQADCgcIDwAAAA==.Karlach:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.Karumie:BAAANQAECgQIBQAAAA==.Kateera:BAAANQADCgQIBAAAAA==.',
Ke='Keljaden:BAAANQAECgMIAwAAAA==.',
Kh='Kheyra:BAAANQAECgMIAwAAAA==.',
Ki='Kittybeef:BAAANQABCgIIAgAAAA==.Kiwiiga:BAAANQAECgEIAQAAAA==.',
Kn='Knoxxic:BAAANQADCgMIBAAAAA==.',
Ko='Kohnor:BAAANQADCgIIAgAAAA==.Koopalizard:BAAANQADCgcIDQAAAA==.Kopi:BAAANQADCggIFwABNQAECgEIAQABAAAAAA==.Korlatt:BAAANQADCgcIEgAAAA==.Kowalabear:BAAANQAECgEIAQAAAA==.',
Ku='Kuaha:BAAANQADCgYIBgABNQADCgQIBAABAAAAAA==.Kupa:BAAANQADCgYIBQAAAA==.Kurston:BAAANQAECgMIAwAAAA==.',
Ky='Ky:BAAANQADCgEIAQAAAA==.',
['Kã']='Kãtniss:BAAANQADCgEIAQAAAA==.',
La='Labella:BAAANQADCgQIBAAAAA==.Laih:BAAANQAECgEIAQAAAA==.Landsong:BAAANQADCgQIBAAAAA==.',
Le='Leyote:BAAANQAECgEIAQAAAA==.',
Li='Liady:BAAANQADCgEIAQAAAA==.Lindithrial:BAAANQABCgQIBAAAAA==.Livingdead:BAAANQADCgcIBwAAAA==.',
Lo='Lorianne:BAAANQADCgYIBgAAAA==.Lowdangle:BAAANQADCgcIBwAAAA==.',
Lu='Luucifur:BAAANQABCgMIAwAAAA==.',
Ma='Mackpumpkin:BAAANQAECgIIAgAAAA==.Macktheknife:BAAANQADCgQIBAABNQAECggIDgABAAAAAA==.Madalyn:BAAANQADCgEIAQAAAA==.Makklehaney:BAAANQAECgEIAQAAAA==.Mallaah:BAAANQADCgUIBQAAAA==.Marovingian:BAAANQAECgEIAQAAAA==.Matthad:BAAANQADCggIFQAAAA==.',
Mc='Mcnastie:BAAANQAECgIIAwAAAA==.Mcsluts:BAAANQADCgYIBgAAAA==.',
Me='Melmirict:BAAANQADCgMIAwAAAA==.Merciala:BAAANQAECgMIAwAAAA==.',
Mi='Milyyanna:BAAANQADCgIIAgAAAA==.Mirilla:BAAANQADCgEIAQAAAA==.',
Mo='Moddoxx:BAAANQAECgEIAQAAAA==.Mohawk:BAAANQADCggIDgAAAA==.Molen:BAAANQAECgEIAQAAAA==.Mommyjuice:BAAANQAECggIDgAAAA==.Monkle:BAAANQAECgMIAwAAAA==.Monohan:BAAANQADCgUIBQABNQADCggIDwABAAAAAA==.Moonsii:BAAANQAECgEIAQAAAA==.Mooroth:BAAANQADCggIFAAAAA==.Morkilro:BAAANQABCgIIAgAAAA==.Morozko:BAAANQADCgQIBAAAAA==.',
Mu='Muddler:BAAANQADCggIFAAAAA==.Murinn:BAAANQAECgEIAQAAAA==.',
['Mà']='Màggles:BAAANQADCggICwAAAA==.',
Na='Nadd:BAAANQADCgcIEAAAAA==.Naledi:BAAANQADCggIDQAAAA==.Naralyn:BAAANQAECgUICAAAAA==.',
Ne='Negrido:BAAANQAECgQIBQAAAA==.Nei:BAAANQAECgEIAgAAAA==.Neon:BAAANQADCgUICQAAAA==.',
Ni='Nikem:BAAANQADCggIEwAAAA==.',
No='Noelle:BAAANQAECgEIAQAAAA==.Noriyuki:BAAANQADCggIFAAAAA==.',
Ny='Nyxahlia:BAAANQADCgUIBgAAAA==.',
Og='Oghom:BAAANQADCggICAAAAA==.',
Ol='Olderon:BAAANQAECgEIAQAAAA==.Olrong:BAAANQAECgEIAQAAAA==.',
On='Onuris:BAAANQABCgQIBAAAAA==.',
Op='Opacuslupus:BAAANQADCgcICwAAAA==.Oppressin:BAAANQAECgEIAQAAAA==.',
Os='Oshunn:BAAANQAECgYICgAAAA==.Oshìe:BAAANQAECgUICQAAAA==.Osroes:BAAANQAECgQICQAAAA==.',
Ov='Overdoom:BAAANQAECgQIBQAAAA==.Ovscur:BAAANQAECgQIBAAAAA==.',
Pa='Paladinjohn:BAAANQAECgcIEgAAAA==.Palykat:BAAANQADCgcIEgAAAA==.Papiroflz:BAAANQAECgQIBQAAAA==.',
Pe='Pennywisé:BAAANQAECgEIAQAAAA==.Pesttilence:BAAANQABCgUIBQAAAA==.',
Pl='Plaguegying:BAAANQAECgMIAwABNQADCgcIEgABAAAAAA==.Ploofee:BAAANQADCggIEwAAAA==.',
Pr='Progresz:BAAANQADCgUIBQAAAA==.',
Py='Pykel:BAAANQAECgQIBQAAAA==.',
Qa='Qaren:BAAANQADCgMIBAAAAA==.',
Ra='Raishun:BAAANQADCgIIAgAAAA==.Raizo:BAAANQADCgYICgAAAA==.Rake:BAAANQAECgQIBQAAAA==.Rawk:BAAANQADCgYIBgAAAA==.',
Re='Reeven:BAAANQAECgYICgAAAQ==.Revokely:BAAANQAECgQIBAAAAA==.',
Rh='Rhcpmage:BAAANQADCggICgABNQAECgkJGAACALclAA==.Rhetegast:BAAANQAECgQIBQAAAA==.',
Ri='Rike:BAAANQAECgEIAQAAAA==.',
Ro='Roland:BAAANQADCgIIAgAAAA==.Rolandin:BAAANQAECgEIAQAAAA==.',
Ry='Rylagosa:BAAANQADCggIEwAAAA==.Ryzesmidge:BAAANQAECgUIBQAAAA==.',
['Rê']='Rêdrum:BAAANQADCgYIBgABNQAECgYICwABAAAAAA==.',
Sa='Salandria:BAAANQAECgMIAwAAAA==.Sarionian:BAAANQADCggIEQAAAA==.Sarvinblue:BAAANQAECgUICQAAAA==.',
Se='Sevrin:BAAANQAECgQIBQAAAA==.Seymonty:BAAANQAECgQIBgAAAA==.',
Sh='Shaeko:BAAANQADCgQIBwAAAA==.Shazlulu:BAAANQADCgcIDwAAAA==.Shaznoir:BAAANQAECgMIAwAAAA==.Shilajit:BAAANQAECgEIAgAAAA==.Shokz:BAAANQABCgQIBAABNQADCggIEwABAAAAAA==.',
Sk='Skip:BAAANQADCgcIBwAAAA==.',
Sl='Sloe:BAAANQAECgEIAQAAAA==.',
Sm='Smokalot:BAAANQABCgIIAgAAAA==.Smokehunter:BAAANQADCgYIBgAAAA==.',
Sn='Snoop:BAAANQABCgQIBAAAAA==.',
So='Solstîce:BAAANQADCgQIBAABNQAECgYICwABAAAAAA==.',
Sp='Speedbeefbal:BAAANQABCgYIBwAAAA==.Speeddwrfbal:BAAANQABCgIIBAAAAA==.Speedmeat:BAAANQAECgMIAwAAAA==.Speedmonkbal:BAAANQADCgMIAQAAAA==.Spidêrs:BAAANQABCgQIBgAAAA==.Sporkulous:BAAANQAECgUIBwAAAA==.',
Sq='Squal:BAAANQADCggIAwAAAA==.Squiggle:BAAANQADCggIFAAAAA==.',
St='Steevii:BAAANQADCgMIAwAAAA==.Stewie:BAAANQADCggIDgAAAA==.Striker:BAAANQADCgMIBAABNQAECgEIAQABAAAAAA==.',
Su='Sunshíne:BAAANQADCggIFAAAAA==.',
Sy='Syreila:BAAANQAECgQIBwAAAA==.Syver:BAAANQAECgEIAQAAAA==.',
['Sí']='Sírlancealot:BAAANQADCgMIBAAAAA==.',
Ta='Talandroz:BAAANQAECgUIBwAAAA==.Tanagra:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Tanner:BAAANQAECgYICwAAAA==.',
Te='Tebo:BAAANQAECgEIAQAAAA==.Tedman:BAAANQADCggIDwAAAA==.Temel:BAAANQAECgIIAgAAAA==.Teostra:BAAANQAECgEIAQAAAA==.Testoecles:BAAANQADCgcICwABNQAECgEIAQABAAAAAA==.',
Th='Thadrack:BAAANQAECgQIBwAAAA==.Thalonstin:BAAANQADCgIIAgAAAA==.Thaneold:BAAANQAECgQICAABNQAECgYICwABAAAAAA==.Thassarian:BAAANQADCgYIBgAAAA==.Theodrid:BAAANQAECgcIEQAAAA==.Thunderstomp:BAAANQADCgIIAgAAAA==.',
Ti='Tinkerspell:BAAANQADCgYIBgAAAA==.Tinkíe:BAAANQAECgQIBQAAAA==.Tirzahdozier:BAAANQADCgYICgABNQADCggIFwABAAAAAA==.Tiwohnne:BAAANQADCgMIBAAAAA==.',
Tl='Tla:BAAANQADCgIIAgAAAA==.',
Tr='Treat:BAAANQAECgMIAwAAAA==.Trippyshock:BAAANQADCgEIAQABNQAFFAYICgAEAHkdAA==.Tristitia:BAAANQABCgQIBAAAAA==.',
Ty='Tyamat:BAAANQAECgEIAQAAAA==.Tyrinara:BAAANQADCggICAAAAA==.',
Ui='Uiewedaoez:BAAANQAECgQIBQAAAA==.',
Va='Vains:BAAANQAECgcIDAAAAA==.Valrith:BAAANQADCgYICwAAAA==.',
Ve='Velody:BAAANQADCgQIAQAAAA==.Veronica:BAAANQAECgEIAQAAAA==.Verren:BAAANQAECgEIAQAAAA==.Vestus:BAAANQABCgMIAwAAAA==.',
Vy='Vyrridyl:BAAANQAECgEIAQAAAA==.',
Wa='Watermark:BAAANQAECgIIAwAAAA==.',
We='Weeblewobble:BAAANQADCggIDwAAAA==.Weltamus:BAAANQADCgMIBAAAAA==.Weltazar:BAAANQAECgEIAQAAAA==.Weltzilla:BAAANQAECgEIAQAAAA==.Westside:BAAANQADCgQIBAABNQADCgYIDwABAAAAAA==.',
Wh='Whoosh:BAAANQAECgUIBwAAAA==.',
Wi='Wickët:BAAANQAECgIIAwAAAA==.Wildtiger:BAAANQAECgEIAQAAAA==.',
Wo='Wolfslied:BAAANQADCgQIBAABNQADCgQIBAABAAAAAA==.',
Wu='Wulfenhide:BAAANQAECgMIAwAAAA==.',
Wy='Wyzsky:BAAANQADCgQICAABNQAECgIIAgABAAAAAA==.',
Xa='Xalreth:BAAANQAECgEIAQAAAA==.Xaviana:BAAANQADCggIFAAAAQ==.',
Ya='Yastypoo:BAAANQAECgMIAwAAAA==.',
Za='Zarieda:BAAANQAECgQIBAAAAA==.',
Zu='Zud:BAAANQAECgIIAwAAAA==.',
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
