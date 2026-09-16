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

local lookup = {'Unknown-Unknown','Mage-Arcane','Mage-Frost','DeathKnight-Unholy','Shaman-Restoration','Warlock-Demonology','Warlock-Destruction','Priest-Shadow','Rogue-Assassination','Rogue-Subtlety','Warlock-Affliction','Paladin-Retribution','Paladin-Protection',}
local provider = {region='US',realm='KulTiras',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aarix:BAAANQAECgQIBwAAAA==.',
Ae='Aendillan:BAAANQADCgUIBQAAAA==.',
Af='Affonasei:BAAANQAECgQIBQAAAA==.',
Ag='Agkistrodon:BAAANQADCgUIBQABNQAECgQIBwABAAAAAA==.',
Ai='Aicaramba:BAAANQAECgEIAQAAAA==.Aileen:BAAANQADCgQIAgAAAA==.',
Al='Alacrodie:BAAANQADCgIIBAAAAA==.',
Am='Amoonsi:BAAANQADCgMIAwABNQAECgIIAwABAAAAAA==.',
An='Angrytotems:BAAANQADCgYICwABNQAECgQIBwABAAAAAA==.Annaborshen:BAAANQABCgIIAgAAAA==.Antoccino:BAAANQAECgQIBQAAAA==.',
Ar='Aragorno:BAAANQAECgIIAwAAAA==.Arcturen:BAAANQADCggIGgAAAA==.Ardala:BAAANQABCgIIAgAAAA==.Arenthal:BAAANQAECgQIBAABNQAECgcIEAABAAAAAA==.',
As='Ashalana:BAAANQADCgUIBQAAAA==.Asheby:BAAANQADCgMIAwABNQAECgQIBAABAAAAAA==.Ashiera:BAAANQAECgUIBgAAAA==.Astralmorph:BAAANQADCgYIBgAAAA==.',
At='Atomic:BAAANQADCgUICQAAAA==.',
Az='Azylstrid:BAAANQADCgYIDAAAAA==.',
Ba='Baeu:BAAANQABCgUIBwAAAA==.Balentine:BAAANQAECgMIBgAAAA==.Banostraza:BAAANQAECgMIAwAAAA==.Baspir:BAAANQAECgUICgAAAA==.',
Be='Beeboop:BAAANQABCgYIEAAAAA==.Belly:BAAANQAECgYIDQAAAA==.Belrae:BAAANQADCggIDQAAAA==.Benchfresh:BAAANQAECgYIBgAAAA==.Bendah:BAAANQAECgEIAQAAAA==.Bender:BAAANQADCgYIBgAAAA==.Bezieck:BAAANQADCgYICgAAAA==.',
Bi='Bigfolks:BAAANQADCgIIAgAAAA==.Bigollock:BAAANQADCgYICwAAAA==.Bili:BAAANQABCgEIAQAAAA==.',
Bl='Bloodarrow:BAAANQADCgUIBgAAAA==.Bloodbound:BAAANQADCgYIBgAAAA==.',
Bo='Bockchi:BAAANQAECgEIAQAAAA==.Bonegavel:BAAANQABCgQIBgAAAA==.Bookhuntress:BAAANQADCgUIBQAAAA==.',
Br='Branex:BAAANQADCggICAAAAA==.Branpaw:BAAANQADCgMIAwAAAA==.Brewdeez:BAAANQAECgYICwAAAA==.Brewzen:BAAANQADCgYIBgAAAA==.Brewzer:BAAANQAECgYIDQAAAA==.Brick:BAAANQADCgQIBAAAAA==.Brint:BAAANQADCgQIBAAAAA==.Bronad:BAABNQAECoEhAAMCAAkJLCbBAQDeAwACAAkJLCbBAQDeAwADAAEJPx/JIgBFAAAAAA==.Broomhandle:BAAANQAECgMIBQAAAA==.',
Bu='Bumbushka:BAAANQAECgUIBQAAAA==.Burinn:BAAANQADCggIGgABNQAECgQIBwABAAAAAA==.',
Ca='Caeus:BAAANQAECgEIAQAAAA==.Cam:BAAANQAECgYIDAAAAA==.Carolinabele:BAAANQADCggICAAAAA==.Cauud:BAAANQADCgUICQAAAA==.',
Cb='Cbd:BAAANQADCgcIEwAAAA==.',
Ce='Celerious:BAAANQABCgIIAgAAAA==.',
Ch='Chacruna:BAAANQAECgIIAwAAAA==.Chelan:BAAANQAECgQIBwAAAA==.Chronicler:BAAANQADCgEIAQAAAA==.Chuntspeed:BAAANQABCgYICgAAAA==.Chuye:BAAANQAECgEIAQABNQAECgUICgABAAAAAA==.',
Cl='Clambulance:BAAANQAECgYIDgAAAA==.',
Co='Codythedead:BAABNQAECoEdAAIEAAkJ/R4fCQA4AwAEAAkJ/R4fCQA4AwAAAA==.Coraf:BAABNQAECoEaAAIFAAkJZB8EBwBHAwAFAAkJZB8EBwBHAwAAAA==.Coyotl:BAAANQADCggIEAAAAA==.',
Cu='Cuvier:BAAANQADCggIFgAAAA==.',
Da='Danak:BAAANQADCgIIAwAAAA==.',
De='Deadlyfrosty:BAAANQADCgUIBwAAAA==.Deathmob:BAAANQAECgQIBAAAAA==.Debixie:BAAANQAECgYIDgAAAA==.Decisive:BAAANQADCgYIBgABNQAFFAYIEAAGAJEfAA==.Dejection:BAAANQABCgYIBwAAAA==.Demisi:BAAANQAECgQIBgAAAA==.Demiurge:BAAANQAECgYICwAAAA==.',
Di='Diasundra:BAAANQAECgUICwAAAA==.Dibbons:BAAANQAECgQIBQAAAA==.Divinatjin:BAAANQADCgYICQAAAA==.',
Do='Dottingyou:BAABNQAECoEcAAMHAAkJXR2MDwDcAQAGAAcJaRwyJABYAgAHAAYJIhqMDwDcAQAAAA==.',
Dr='Dracthyrbm:BAAANQADCgYICAAAAA==.Dreepy:BAAANQAECgUIBQAAAA==.Drransom:BAAANQADCgEIAQAAAA==.Dryan:BAAANQAECgEIAQAAAA==.',
Du='Duo:BAAANQAECgYICwAAAA==.Duragon:BAAANQAECgYICAAAAA==.',
Ei='Eipwoc:BAAANQADCggIBwAAAA==.',
El='Elciere:BAAANQADCgQIBAAAAA==.Eloreith:BAAANQAECgQIBgAAAA==.',
Em='Emamagee:BAAANQADCgQIBgAAAA==.Emilia:BAAANQAECgUICQAAAA==.',
En='Endressa:BAAANQAECgYIDwAAAA==.',
Er='Erelios:BAAANQAECgEIAQAAAA==.',
Es='Eski:BAAANQAECggIDgAAAA==.Essaena:BAAANQAECgQIBwAAAA==.',
Eu='Eureka:BAEANQAECgYICgAAAA==.',
Fa='Faddeyshnek:BAAANQAECgYIDQAAAA==.Fatgirljuice:BAAANQAECgMIBgABNQAECggIDgABAAAAAA==.',
Fe='Felysambre:BAAANQADCggIFwAAAA==.',
Fi='Fish:BAACNQAFFIEPAAIIAAcJiCIOAADvAgAIAAcJiCIOAADvAgA1AAQKgSIAAggACQnJJhcAAAwEAAgACQnJJhcAAAwEAAAA.',
Fl='Flight:BAABNQAECoEdAAMJAAkJlBpBDwBIAgAJAAcJOxtBDwBIAgAKAAYJPBOMGgClAQAAAA==.Floofee:BAAANQADCgQIBAAAAA==.',
Fo='Footfinger:BAAANQABCgUIBgAAAA==.Forsynth:BAAANQAECgMIBAAAAA==.',
Fu='Fubar:BAAANQABCgQIAwAAAA==.',
Ga='Ganniy:BAAANQABCgEIAQAAAA==.',
Ge='Gewitt:BAAANQAECgMIAwAAAA==.',
Go='Gonjah:BAAANQAECgEIAQAAAA==.',
Gr='Grabomage:BAAANQAECgEIAQABNQAECgkJIQACACwmAA==.Grabovoker:BAAANQADCgIIAgABNQAECgkJIQACACwmAA==.Grazienne:BAAANQADCgIIAwAAAA==.Greavos:BAAANQAECgQIBQAAAA==.Griggus:BAAANQAECgIIAgAAAA==.Grimgar:BAAANQAECgQIBQAAAA==.Grimmshady:BAAANQADCgQIBQAAAA==.',
Gu='Gumbles:BAAANQAECgUICgAAAA==.Gurney:BAAANQAECgMIAwAAAA==.Guzprimal:BAAANQAECgEIAQAAAA==.',
Gy='Gying:BAAANQADCggIGgAAAA==.',
Ha='Hanekawa:BAAANQAECgQIBAABNQAECgkJGwADAEwjAA==.Hannie:BAAANQADCgIIBAAAAA==.',
He='Headhúnter:BAAANQAECgYICAAAAA==.Heartsparx:BAAANQAECgUICQAAAA==.Heatseeka:BAAANQAECgQIBwAAAA==.',
Hi='Hiphopinator:BAAANQAECgMIBQAAAA==.',
Ho='Ho:BAAANQADCgQIBAAAAA==.Holyshock:BAAANQAECgcIEQAAAA==.Holyterror:BAAANQADCgIIBAAAAA==.',
Ia='Ianthe:BAAANQADCggIEwAAAA==.',
Ib='Iboga:BAAANQAECgQIBgAAAA==.Ibrahimovic:BAAANQADCggIEQAAAA==.',
Ig='Ignitecro:BAAANQABCgcIDwAAAA==.Igram:BAAANQAECgEIAQAAAA==.',
Il='Iluz:BAAANQADCgMIAwAAAA==.',
In='Inafume:BAAANQADCggIDgAAAA==.Inoxia:BAAANQAECgIIBgAAAA==.Intrépidice:BAAANQAECgMIAwAAAA==.',
Ix='Ixtabay:BAABNQAECoEYAAQLAAkJiB06AQDcAgALAAkJdRs6AQDcAgAHAAMJjhNOMgDDAAAGAAMJvQ3ekADAAAAAAA==.',
Ja='Jamurra:BAAANQAECgIIAgAAAA==.Jaylinn:BAAANQAECgYICwAAAA==.Jazzmend:BAAANQAECgQIBAAAAA==.',
Je='Jeanne:BAAANQAECgUIBgAAAA==.Jellykins:BAAANQAECgQIBAAAAA==.',
Ji='Jimjamjuju:BAAANQAECgQIBAAAAA==.Jimsonweed:BAAANQAECgQIBwAAAA==.',
Jo='Josie:BAAANQAECgIIAgAAAA==.Jozbirt:BAAANQAECgcIDAAAAA==.',
Ka='Kaeiria:BAAANQADCgQIBAAAAA==.Kael:BAAANQAECgQIBQAAAA==.Kalaanri:BAAANQADCggIFAAAAA==.Kalyandra:BAAANQAECgQIBAAAAA==.Karlach:BAAANQADCgUIBQABNQAECgUICQABAAAAAA==.Karumie:BAAANQAECgUICgAAAA==.Kateera:BAAANQADCgQIBAAAAA==.',
Ke='Keden:BAAANQADCgIIAgAAAA==.Keljaden:BAAANQAECgMIBQAAAA==.',
Kh='Kheyra:BAAANQAECgQIBwAAAA==.',
Ki='Kittybeef:BAAANQABCgIIAgAAAA==.Kiwiiga:BAAANQAECgIIAwAAAA==.',
Kn='Knoxxic:BAAANQADCgMIBAAAAA==.',
Ko='Kohnor:BAAANQADCgIIBAAAAA==.Koopalizard:BAAANQAECgMIAwAAAA==.Kopi:BAAANQADCggIFwABNQAECgQIBQABAAAAAA==.Korlatt:BAAANQAECgIIAgAAAA==.Kowalabear:BAAANQAECgEIAQAAAA==.',
Ku='Kuaha:BAAANQADCgYIBgABNQADCgQIBAABAAAAAA==.Kupa:BAAANQADCgYIBwAAAA==.Kurom:BAAANQADCgYIBgAAAA==.Kurston:BAAANQAECgQIBwAAAA==.',
Ky='Ky:BAAANQADCgEIAQAAAA==.',
['Kã']='Kãtniss:BAAANQADCgIIAwAAAA==.',
La='Labella:BAAANQADCgQIBAAAAA==.Laih:BAAANQAECgEIAQAAAA==.Landsong:BAAANQADCgQIBAAAAA==.',
Le='Leyote:BAAANQAECgQIBQAAAA==.',
Li='Liady:BAAANQADCgEIAQAAAA==.Lilyfox:BAAANQADCgcIBwAAAA==.Lindithrial:BAAANQABCgQIBAAAAA==.Livingdead:BAAANQADCgcIDgAAAA==.',
Lo='Lorianne:BAAANQADCgYICAAAAA==.Lowdangle:BAAANQADCgcIBwAAAA==.',
Lu='Luucifur:BAAANQABCgMIAwAAAA==.',
Ma='Mackpumpkin:BAAANQAECgIIAgAAAA==.Macktheknife:BAAANQADCgQIBAABNQAECgkJGAALAIgdAA==.Madalyn:BAAANQADCgEIAQAAAA==.Makklehaney:BAAANQAECgMIBAAAAA==.Mallaah:BAAANQADCgUIBQAAAA==.Marovingian:BAAANQAECgMIBAAAAA==.Matthad:BAAANQAECgEIAQAAAA==.',
Mc='Mcnastie:BAAANQAECgQIBgAAAA==.Mcsluts:BAAANQADCgYICwAAAA==.',
Me='Melmirict:BAAANQADCgMIAwAAAA==.Merciala:BAAANQAECgQIBQAAAA==.',
Mi='Milyyanna:BAAANQADCgIIBAAAAA==.Mirilla:BAAANQAECgYIBgAAAA==.',
Mo='Moddoxx:BAAANQAECgQIBQAAAA==.Mohawk:BAAANQAECgMIAwAAAA==.Molen:BAAANQAECgEIAQAAAA==.Mommyjuice:BAAANQAECggIDgAAAA==.Monkle:BAAANQAECgQIBwAAAA==.Monohan:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.Moonsii:BAAANQAECgIIAwAAAA==.Mooroth:BAAANQAECgUIBQAAAA==.Morkilro:BAAANQABCgIIAgAAAA==.Morozko:BAAANQADCgQIBAAAAA==.',
Mu='Muddler:BAAANQAECgIIAgAAAA==.Murinn:BAAANQAECgMIBAAAAA==.',
['Mà']='Màggles:BAAANQAECgEIAQAAAA==.',
Na='Nadd:BAAANQADCggIGAAAAA==.Naledi:BAAANQADCggIDQAAAA==.Naralyn:BAAANQAECgYIDgAAAA==.',
Ne='Negrido:BAAANQAECgYICwAAAA==.Nei:BAAANQAECgEIBAAAAA==.Neon:BAAANQADCgUICQAAAA==.',
Ni='Nikem:BAAANQAECgIIAgAAAA==.',
No='Noelle:BAAANQAECgQIBAAAAA==.Noriyuki:BAAANQAECgIIAgAAAA==.',
Ny='Nyxahlia:BAAANQADCgUIBgAAAA==.',
Og='Oghom:BAAANQADCggICAAAAA==.Ogrekin:BAAANQAECgQIBAAAAA==.',
Ol='Olderon:BAAANQAECgIIAwAAAA==.Olrong:BAAANQAECgQIBQAAAA==.Oluja:BAAANQAECgMIBAAAAA==.',
On='Onuris:BAAANQABCgQIBgAAAA==.',
Op='Opacuslupus:BAAANQAECgEIAQAAAA==.Oppressin:BAAANQAECgMIBAAAAA==.',
Os='Oshunn:BAAANQAECgYIEAAAAA==.Oshìe:BAAANQAECgYIDwAAAA==.Osroes:BAAANQAECgQIDgAAAA==.',
Ov='Overdoom:BAAANQAECgYICwAAAA==.Ovscur:BAAANQAECgQICAAAAA==.',
Pa='Paladinjohn:BAABNQAECoEdAAIMAAkJVSW3AwC8AwAMAAkJVSW3AwC8AwAAAA==.Palykat:BAAANQADCggIGgAAAA==.Papiroflz:BAAANQAECgYICwAAAA==.',
Pe='Pennywisé:BAAANQAECgYIBwAAAA==.Pesttilence:BAAANQABCgYIDAAAAA==.',
Pl='Plaguegying:BAAANQAECgQIBwABNQADCggIGgABAAAAAA==.Ploofee:BAAANQADCggIGwAAAA==.',
Pr='Progresz:BAAANQADCggICQAAAA==.',
Py='Pykel:BAAANQAECgUICgAAAA==.',
Qa='Qaren:BAAANQADCgUICQAAAA==.',
Ra='Raishun:BAAANQADCgIIAgAAAA==.Raizo:BAAANQAECgEIAQAAAA==.Rake:BAAANQAECgYICwAAAA==.Rassina:BAAANQADCgEIAQAAAA==.Rawk:BAAANQADCgYIBgAAAA==.',
Re='Reeven:BAAANQAECgYIDwAAAQ==.Revokely:BAAANQAECgUICAAAAA==.',
Rh='Rhcpmage:BAAANQADCggICgABNQAECgkJIQACACwmAA==.Rhetegast:BAAANQAECgUICgAAAA==.',
Ri='Rike:BAAANQAECgQIBQAAAA==.Ristretto:BAAANQADCgUIBQABNQAECgQIBQABAAAAAA==.',
Ro='Roland:BAAANQADCgUIBwAAAA==.Rolandin:BAAANQAECgQIBQAAAA==.',
Ry='Rylagosa:BAAANQAECgIIAgAAAA==.Ryzesmidge:BAAANQAECgYICwAAAA==.',
['Rê']='Rêdrum:BAAANQAECgIIAgABNQAECgYIDwABAAAAAA==.',
Sa='Salandria:BAAANQAECgYICQAAAA==.Sarionian:BAAANQADCggIGQAAAA==.Sarjin:BAAANQADCgYIBgABNQAECgQIBwABAAAAAA==.Sarvinblue:BAAANQAECgYIDgAAAA==.',
Sc='Scopolamine:BAAANQADCgIIAgAAAA==.',
Se='Sevrin:BAAANQAECgYICwAAAA==.Seymonty:BAAANQAECgQICgAAAA==.',
Sh='Shaeko:BAAANQADCgUICAAAAA==.Shazlulu:BAAANQADCggIFwAAAA==.Shaznoir:BAAANQAECgQIBwAAAA==.Shilajit:BAAANQAECgEIAgAAAA==.Shokz:BAAANQADCgMIAwABNQADCggIGwABAAAAAA==.',
Sk='Skip:BAAANQADCgcIBwAAAA==.Skøøma:BAAANQABCgIIBAAAAA==.',
Sl='Sloe:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.',
Sm='Smokalot:BAAANQADCggICAAAAA==.Smokehunter:BAAANQADCgYIBgAAAA==.',
Sn='Snoop:BAAANQABCgQIBAAAAA==.',
So='Solstîce:BAAANQADCgQIBAABNQAECgYIDwABAAAAAA==.',
Sp='Speedbeefbal:BAAANQADCgMIAwAAAA==.Speeddwrfbal:BAAANQABCgUIBgAAAA==.Speedmeat:BAAANQAECgUICAAAAA==.Speedmonkbal:BAAANQADCgUIAwAAAA==.Spidêrs:BAAANQABCgQICAAAAA==.Sporkulous:BAAANQAECgUIDQAAAA==.',
Sq='Squal:BAAANQADCggIAwAAAA==.Squiggle:BAAANQAECgIIAgAAAA==.',
St='Steevii:BAAANQADCgMIAwAAAA==.Stewie:BAAANQAECgEIAQAAAA==.Striker:BAAANQADCgUICQABNQAECgQIBQABAAAAAA==.',
Su='Sunshíne:BAAANQADCggIGgAAAA==.',
Sy='Syreila:BAAANQAECgUIDAAAAA==.Syver:BAAANQAECgQIBQAAAA==.',
['Sí']='Sírlancealot:BAAANQADCgMIBAAAAA==.',
Ta='Takeke:BAAANQAECgEIAQAAAA==.Takeroux:BAAANQADCgIIAgAAAA==.Talandroz:BAAANQAECgYIDQAAAA==.Tanagra:BAAANQADCgIIAgABNQAECgQIBQABAAAAAA==.Tanner:BAAANQAECggIEwAAAA==.',
Te='Tebo:BAAANQAECgEIAgAAAA==.Tedman:BAAANQAECgIIAgAAAA==.Temel:BAAANQAECgIIBAAAAA==.Teostra:BAAANQAECgYIBwAAAA==.Testoecles:BAAANQADCgcICwABNQAECgEIAgABAAAAAA==.',
Th='Thadrack:BAAANQAECgQIBwAAAA==.Thalonstin:BAAANQADCgIIBAAAAA==.Thaneold:BAAANQAECgQICQABNQAECgYIEQABAAAAAA==.Thassarian:BAAANQAECgQIBAAAAA==.Theodrid:BAABNQAECoEdAAINAAkJpSDCAgBSAwANAAkJpSDCAgBSAwAAAA==.Thunderstomp:BAAANQADCgIIAgAAAA==.',
Ti='Tinkerspell:BAAANQADCgYICwAAAA==.Tinkíe:BAAANQAECgYICwAAAA==.Tirzahdozier:BAAANQADCgcIEQABNQAECgIIAgABAAAAAA==.Tiwohnne:BAAANQADCgMIBAAAAA==.',
Tl='Tla:BAAANQADCgIIBAAAAA==.',
Tr='Treat:BAAANQAECgMIBQAAAA==.Trippyshock:BAAANQADCgEIAQABNQAFFAYIEAAGAJEfAA==.Tristitia:BAAANQABCgYIBgAAAA==.',
Tw='Twiggle:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Twistedsquid:BAAANQABCgQIBAAAAA==.',
Ty='Tyamat:BAAANQAECgIIAwAAAA==.Tyche:BAAANQADCgUIBQAAAA==.Tyrinara:BAAANQADCggICAAAAA==.',
Ui='Uiewedaoez:BAAANQAECgYICwAAAA==.',
Va='Vains:BAAANQAECgcIEgAAAA==.Valrith:BAAANQADCgYIEQAAAA==.',
Ve='Velody:BAAANQADCgQIAQAAAA==.Vendettuh:BAAANQADCgYIBgAAAA==.Veronica:BAAANQAECgQIBQAAAA==.Verren:BAAANQAECgMIBAAAAA==.Vestus:BAAANQABCgUIBwAAAA==.',
Vy='Vyrridyl:BAAANQAECgEIAQAAAA==.',
Wa='Watermark:BAAANQAECgUIBwAAAA==.',
We='Weeblewobble:BAAANQAECgEIAgAAAA==.Weltamus:BAAANQADCgUICQAAAA==.Weltazar:BAAANQAECgEIAQAAAA==.Weltzilla:BAAANQAECgMIBAAAAA==.Westside:BAAANQAECgMIAwAAAA==.',
Wh='Whoosh:BAAANQAECgYIDQAAAA==.',
Wi='Wickët:BAAANQAECgYICQAAAA==.Wildtiger:BAAANQAECgIIAwAAAA==.',
Wo='Wolfslied:BAAANQADCgQIBAABNQADCgQIBAABAAAAAA==.',
Wu='Wulfenhide:BAAANQAECgMIBQAAAA==.',
Wy='Wyzsky:BAAANQADCgQICgABNQAECgIIBAABAAAAAA==.',
Xa='Xalreth:BAAANQAECgMIBAAAAA==.Xaviana:BAAANQADCggIHAAAAQ==.',
Ya='Yastypoo:BAAANQAECgUICAAAAA==.',
Za='Zarieda:BAAANQAECgYICgAAAA==.',
Zu='Zud:BAAANQAECgQIBwAAAA==.',
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
