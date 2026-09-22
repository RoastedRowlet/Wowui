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

local lookup = {'Hunter-Marksmanship','Druid-Restoration','Unknown-Unknown','Warrior-Fury','Shaman-Restoration','Warrior-Protection','Paladin-Retribution','DeathKnight-Frost','Warlock-Destruction','Warlock-Demonology','Hunter-BeastMastery','Evoker-Preservation','Priest-Holy','Priest-Shadow','Priest-Discipline','Monk-Windwalker','Druid-Balance','Druid-Guardian','Paladin-Protection',}
local provider = {region='US',realm='Tanaris',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aalicya:BAAANQAECgEJAQAAAA==.',
Ac='Acegoblain:BAAANQAECgYICQABNQAFFAQJCQABAGwLAA==.',
Ad='Adind:BAABNQAECoEXAAICAAkKjBULDwB5AgACAAkKjBULDwB5AgAAAA==.Adonra:BAAANQADCgYIBgAAAA==.',
Ae='Aeromage:BAAANQADCgQIBAAAAA==.Aeropally:BAAANQADCgQIBAAAAA==.Aerorising:BAAANQADCgYIBgAAAA==.',
Ak='Akkiba:BAAANQADCgYICwAAAA==.',
Al='Alaval:BAAANQAECgEIAQAAAA==.Aldabaran:BAAANQADCgcIDgAAAA==.Aldolador:BAAANQABCgIIAgABNQABCgQICgADAAAAAA==.Alestalker:BAAANQADCgUIBQABNQADCgUIBQADAAAAAA==.Aletheïa:BAAANQADCggIDgAAAA==.Althamon:BAAANQADCgQIBQAAAA==.',
An='Andromalius:BAAANQADCgIIAgAAAA==.Antamun:BAABNQAECoEZAAIEAAgKcBUxBgAkAgAEAAgKcBUxBgAkAgAAAA==.',
Ao='Aoasis:BAAANQAECgQICQAAAA==.',
Aq='Aqueefer:BAAANQAECgUIBAABNQAECgEIAQADAAAAAA==.',
Ar='Araethea:BAAANQAECgcJEQAAAA==.Arasettey:BAAANQADCggICAABNQAFFAIIAgADAAAAAA==.Arethusa:BAAANQADCggICAAAAA==.Arislynn:BAAANQAECgQJBwAAAA==.Aryn:BAAANQAECgUICQAAAA==.',
Au='Austin:BAAANQADCggICAAAAA==.',
Az='Azirra:BAAANQADCgQIBQAAAA==.',
['Aù']='Aùriel:BAAANQAECgUICwAAAA==.',
Ba='Badgerhollis:BAAANQADCgUICAAAAA==.Bailey:BAAANQAECgEIAQAAAA==.Bamalock:BAAANQAECgEIAQAAAA==.Bathin:BAAANQAECgUIDgAAAA==.Bathwater:BAABNQAECoEcAAIFAAgKfCL9DgAQAwAFAAgKfCL9DgAQAwAAAA==.',
Be='Bearbottom:BAAANQADCgYIBgAAAA==.Bearn:BAAANQADCggIDgAAAA==.',
Bi='Biffster:BAAANQAECgYIEwAAAA==.Bighellion:BAAANQADCgIIAgAAAA==.Bigpumps:BAAANQADCgEIAQABNQADCggJCAADAAAAAA==.Bigtriangle:BAABNQAECoEZAAIGAAgKbBoMBwBzAgAGAAgKbBoMBwBzAgABNQAFFAIIAgADAAAAAA==.Billiamson:BAAANQADCgcIDgAAAA==.',
Bj='Bjoris:BAAANQAECgUIDgAAAA==.',
Bl='Blackhawk:BAAANQABCgcJBQAAAA==.Bloodaxe:BAAANQADCggIBAAAAA==.',
Bo='Bornferal:BAAANQAECgUJBQAAAA==.',
Br='Bryzx:BAACNQAFFIENAAIFAAYKnR2RAQAzAgAFAAYKnR2RAQAzAgA1AAQKgRkAAgUACQqAIgoGAHADAAUACQqAIgoGAHADAAAA.Bryzxbless:BAAANQAECgEIAQAAAA==.',
Bu='Bubblebee:BAAANQAECgUIDAAAAA==.Bullan:BAAANQADCggICQAAAA==.Butterskotch:BAAANQADCgYIBgAAAA==.Buttpeanut:BAAANQAECgMIBQAAAA==.',
Ca='Cavetard:BAAANQADCgEJAQAAAA==.',
Cl='Clairvoyance:BAAANQABCgMIAwABNQAECgYIEQADAAAAAA==.',
Cr='Crunchynuget:BAABNQAECoEbAAIHAAkKuRolLgChAgAHAAkKuRolLgChAgAAAA==.',
Cy='Cynemon:BAAANQAECgEJAQAAAA==.Cynleel:BAAANQAECgEIAQABNQAECgEJAQADAAAAAA==.',
Da='Dadu:BAAANQADCgEJAQAAAA==.Daifuku:BAABNQAECoEXAAIIAAgKtx2fEQCbAgAIAAgKtx2fEQCbAgAAAA==.Darknonsence:BAAANQADCgQIBQAAAA==.David:BAAANQADCgQIBAABNQAECgQIBwADAAAAAA==.',
De='Demonetizeme:BAAANQAECgMJBQABNQAECgEIAQADAAAAAA==.Demonvomit:BAAANQAECgYJEAAAAA==.Dernix:BAAANQADCgUIBQABNQAECgMIAwADAAAAAA==.Deroy:BAAANQADCgEIAQAAAA==.Deåth:BAAANQAECgIIAgAAAA==.',
Di='Dissociative:BAAANQAECgYIDgAAAA==.',
Do='Dorktard:BAAANQADCgUIBQAAAA==.Dorpy:BAAANQADCgIIAgAAAA==.Dotfeardead:BAAANQADCgYIBgAAAA==.',
Dr='Draegohl:BAAANQADCgUIDgAAAA==.Dragordawn:BAAANQABCgUIBwAAAA==.Drofiery:BAAANQAECgEJAQAAAA==.',
Ds='Dsypha:BAAANQAECgIIAwAAAA==.',
['Då']='Dåmage:BAAANQAECgEJAQAAAA==.',
Ed='Edric:BAAANQAECgQIBAAAAA==.Edyion:BAAANQAECgEJAgAAAA==.',
Ef='Efreet:BAAANQAECgUIBwAAAA==.',
El='Elimae:BAEANQADCgMIBQAAAA==.Elvenfury:BAAANQADCggJCAAAAA==.',
En='Enochian:BAAANQADCgMIBAAAAA==.',
Er='Erwinnas:BAAANQABCgEIAQAAAA==.',
Eu='Eurae:BAAANQAECgIIAgAAAA==.',
Ev='Evileye:BAAANQADCgYIBgABNQADCggJCAADAAAAAA==.Evoda:BAAANQAECgEJAQAAAA==.',
Ex='Extrodinaire:BAAANQAECgUICwAAAA==.',
Ez='Eziopandator:BAAANQABCggIGQAAAA==.',
Fa='Fabiio:BAAANQABCgQICgAAAA==.Fadedemon:BAAANQAECgUIDgAAAA==.Faedilan:BAAANQADCgQIBAAAAA==.Farrahmoans:BAAANQAECgQICgAAAA==.',
Fe='Fellvarg:BAAANQAECgEJAgAAAA==.Felsgoodman:BAABNQAECoEcAAMJAAgKNCHrAgD8AgAJAAgKNCHrAgD8AgAKAAcKChPeTwDhAQAAAA==.Felstriker:BAAANQADCgYIDQAAAA==.Ferluci:BAAANQADCgUICgAAAA==.',
Fi='Filí:BAAANQADCgMIBQAAAA==.Firugan:BAAANQADCgYICgAAAA==.',
Fj='Fjaril:BAAANQADCggJIwABNQAECgEJAQADAAAAAA==.',
Fu='Fulgur:BAAANQADCgYIBgAAAA==.Fumistra:BAAANQADCggIDQAAAA==.',
Ga='Galroot:BAAANQADCgUICAABNQAFFAQJCQABAGwLAA==.Galsnipes:BAACNQAFFIEJAAMBAAQKbAujCQAiAQABAAQKggqjCQAiAQALAAEKFAkWHwBMAAA1AAQKgSAAAwEACAr+HSERAJwCAAEACAr+HSERAJwCAAsAAQpTDVvqAEUAAAAA.Galvakrond:BAAANQAECgEJAgAAAA==.',
Ge='Geearr:BAAANQADCggIFgAAAA==.',
Gn='Gnomylanta:BAAANQADCgMIAwAAAA==.',
Go='Gomldruid:BAAANQAECggICAAAAA==.Gomletta:BAAANQAECgEJAgAAAA==.',
Gr='Grak:BAABNQAECoEYAAIMAAgKrgnUGgCiAQAMAAgKrgnUGgCiAQABNQAECgcIEAADAAAAAA==.Gratescott:BAAANQAECgMIAwAAAA==.Grik:BAAANQAECgMIBAAAAA==.Grimgull:BAAANQADCgUICgAAAA==.',
Gw='Gwyndora:BAAANQAECgEJAgAAAA==.',
['Gø']='Gøøber:BAAANQADCgUIBQAAAA==.',
He='Healup:BAAANQAECgQIBQAAAA==.Hellenita:BAAANQADCgIIAgAAAA==.',
Hi='Hildebrand:BAAANQADCgYJBgAAAA==.Hitomitanaka:BAAANQAECgMIAwAAAA==.',
Ho='Holyoshyy:BAAANQAECgUICQAAAA==.Holytiber:BAAANQADCgEIAQAAAA==.Holyvengence:BAAANQAECgQIBAAAAA==.',
Hu='Hup:BAAANQADCggICAAAAA==.',
Id='Idiorr:BAAANQADCgYIBgAAAA==.',
Ie='Iemanja:BAAANQADCggIDwAAAA==.',
In='Inarin:BAAANQADCgUIDgAAAA==.',
Is='Ismitethou:BAAANQADCggICQAAAA==.',
It='Itzsavage:BAAANQADCgQIBAAAAA==.',
Ja='Jachyra:BAAANQAECgQIBQAAAA==.Jackmanss:BAAANQADCgYICgAAAA==.Jaell:BAAANQADCgMIBQAAAA==.Jamezon:BAAANQAECgQIBAAAAA==.',
Je='Jes:BAAANQAECgMIAwAAAA==.',
Ji='Jitlok:BAAANQAECgEJAgAAAA==.',
Jo='Johnashr:BAAANQADCgQIBAABNQADCgYICwADAAAAAA==.Joonbug:BAAANQABCgQJBwAAAA==.',
Ju='Juràssic:BAAANQAECgMJAwAAAA==.',
Ka='Kaeul:BAAANQAECgcJEwAAAA==.Kalia:BAAANQADCgEIAgAAAA==.Kalius:BAAANQAECgEJAgAAAA==.Kando:BAAANQADCgIIAgAAAA==.Kazgrom:BAAANQADCgQIBQAAAA==.Kazool:BAAANQADCggIEAAAAA==.',
Ke='Keanuleaves:BAAANQADCgYIBgABNQAECgQICgADAAAAAA==.',
Ki='Killerattack:BAAANQADCggIDwABNQAFFAIIAgADAAAAAA==.Killerheal:BAAANQAFFAIIAgAAAA==.Kiralan:BAAANQADCgcJCQAAAA==.Kizzu:BAAANQAECgUJCgAAAA==.',
Kn='Knash:BAAANQADCgEIAQAAAA==.Knower:BAAANQADCggIGwAAAA==.',
Ko='Kostah:BAAANQAECgYJDgAAAA==.',
Kr='Kracu:BAAANQADCgIIAgAAAA==.',
['Kí']='Kíli:BAAANQADCgMIBQAAAA==.',
['Kø']='Køteb:BAAANQAECgYIEgAAAA==.',
Le='Leadshot:BAAANQAECgQJCQAAAA==.',
Ly='Lyzbeth:BAAANQABCgUJAwAAAA==.',
['Lï']='Lïmes:BAAANQADCggJDwAAAA==.',
Ma='Maakha:BAAANQAECgEJAgAAAA==.Mabalzich:BAAANQADCgUIDgAAAA==.Madamewhimzy:BAAANQAECgEIAQAAAA==.Madsumo:BAAANQADCggIFgABNQAECgEJAQADAAAAAA==.Magroot:BAAANQAECgUIDgAAAA==.Makula:BAAANQAECgEJAgAAAA==.Mana:BAAANQAECgYIBwAAAA==.Manabun:BAAANQAECgEJAQAAAA==.Manacakes:BAAANQAECgMIBQAAAA==.Manamuffins:BAAANQADCgYJCgAAAA==.Manapie:BAAANQADCgQJBAAAAA==.Mannadina:BAABNQAECoEZAAINAAgKaBniIgB9AgANAAgKaBniIgB9AgAAAA==.Mannalight:BAAANQADCgEIAQABNQAECggIGQANAGgZAA==.Mapera:BAAANQAECgEJAgAAAA==.Marandra:BAAANQADCgIJAgAAAA==.Maray:BAAANQADCgQJCgAAAA==.Marjaya:BAAANQAECgEJAQAAAA==.Maynarde:BAAANQABCgYIBgAAAA==.',
Me='Medivarg:BAAANQADCgUIBQAAAA==.Meloncauley:BAAANQAECgYJDwAAAA==.',
Mi='Michaal:BAAANQADCgUJBQAAAA==.Mirisa:BAAANQADCgUIBQAAAA==.Mirosa:BAAANQAECgEJAgAAAA==.Mistmuncher:BAAANQADCgcIBwAAAA==.',
Mo='Mooahdib:BAAANQADCgcIDQAAAA==.',
Mu='Murmur:BAAANQAECgIIAwAAAA==.',
My='Mybrother:BAAANQAECgIIAQAAAA==.',
Na='Nangsa:BAAANQAECgEJAQAAAA==.Nautisassin:BAAANQADCggIIAABNQAECgEJAQADAAAAAA==.',
Ne='Nessva:BAAANQAECgQJBwAAAA==.Neçromonger:BAABNQAECoEYAAILAAgKaSaIBQCPAwALAAgKaSaIBQCPAwAAAA==.',
Ni='Nikidas:BAAANQADCgYIBgAAAA==.Ninurta:BAAANQADCggIIwAAAA==.',
No='Noxz:BAABNQAECoEcAAQOAAgKbB8NDgC/AgAOAAgKbB8NDgC/AgANAAYK1RDAVgB+AQAPAAEKNxSzHAA1AAAAAA==.',
Ny='Nyiais:BAAANQAECgEJAgAAAA==.',
Ob='Obsessedwith:BAAANQAECgQJBwAAAA==.',
Oo='Oonspork:BAAANQADCgUIBQAAAA==.',
Pa='Paladinrob:BAAANQADCgEIAgAAAA==.Palyfight:BAAANQADCgIIAgAAAA==.Pangurrban:BAAANQADCgMIBQAAAA==.',
Pe='Persiflage:BAAANQADCggJEAAAAA==.',
Po='Poinen:BAAANQADCggIFwABNQAECgcIEAADAAAAAA==.',
Pr='Priestin:BAAANQAECgEIAQAAAA==.',
Ps='Psyscape:BAAANQADCgQIBQAAAA==.',
Ra='Raginghavoc:BAAANQAECgQIBAAAAA==.Raichi:BAABNQAECoEcAAIQAAgKCBsvEgBVAgAQAAgKCBsvEgBVAgAAAA==.Raihne:BAAANQADCgEIAQAAAA==.Ramasseuse:BAAANQABCgIIAgAAAA==.',
Re='Reallyreally:BAAANQAECggICQAAAA==.Reeally:BAAANQADCggIDAABNQAECggICQADAAAAAA==.Reelly:BAAANQADCgUIBQABNQAECggICQADAAAAAA==.Reppitt:BAAANQADCgMIBAAAAA==.',
Ri='Riopia:BAAANQADCgUICgAAAA==.',
Ro='Rod:BAAANQADCgUIBQAAAA==.Roenwyn:BAAANQADCgIIAgAAAA==.Ronny:BAAANQADCgIJAgABNQAECgkJHgARAL8fAA==.Ronosaur:BAABNQAECoEeAAIRAAkKvx8UDQAzAwARAAkKvx8UDQAzAwAAAA==.Rons:BAAANQAECgMJBAABNQAECgkJHgARAL8fAA==.Rozzinor:BAAANQAECgEIAQABNQAECgQICAADAAAAAA==.Rozzjung:BAAANQAECgMJBAABNQAECgQICAADAAAAAA==.',
Ru='Rubyrhod:BAAANQABCgMIAwAAAA==.Rubystars:BAAANQADCggJDAABNQAFFAEIAQADAAAAAA==.Ruslah:BAAANQAECgEJAgAAAA==.',
Sa='Sacredmoo:BAAANQADCgIIAgABNQADCggIDAADAAAAAA==.Salèèñä:BAAANQADCgQJBAAAAA==.Sangoki:BAAANQAECgUIDgAAAA==.Sanguinius:BAAANQAECgQJCAAAAA==.Savageslayer:BAABNQAECoEcAAMRAAgKQhqpIQBgAgARAAgKQhqpIQBgAgASAAEKiweZNwAkAAAAAA==.Savagespally:BAAANQADCgMIAwAAAA==.',
Se='Senshi:BAAANQADCgcIDQAAAA==.Serrena:BAAANQABCgQJBAAAAA==.Seventl:BAAANQAECgUIDQAAAA==.',
Sh='Shadowbloom:BAAANQAECgEIAQAAAA==.Shamace:BAAANQAECgMIBAAAAA==.Shaokhan:BAABNQAECoEjAAIQAAkKKRsVDgCcAgAQAAkKKRsVDgCcAgAAAA==.Shoosts:BAAANQADCgUIBgAAAA==.Shåmwõw:BAAANQADCgYIBgAAAA==.',
Si='Simbru:BAAANQAECgEJAgAAAA==.Sioux:BAAANQADCgYIBwAAAA==.',
Sp='Spheres:BAAANQADCggIDAAAAA==.',
Sq='Squant:BAAANQABCgEIAQAAAA==.',
St='Stoogatz:BAAANQAECgQICAAAAA==.Stormiee:BAAANQADCgMIBQAAAA==.Strongbow:BAAANQADCgYICwAAAA==.',
Su='Suicidekings:BAAANQAECgIJAgABNQAECgUJCQADAAAAAA==.',
['Sí']='Símbá:BAAANQADCgEIAQABNQADCggICQADAAAAAA==.',
Ta='Takerfan:BAAANQAECgYIDgAAAA==.Tallyblue:BAAANQAECgMJBAAAAA==.Tanarisfry:BAAANQAECgIIAgAAAA==.Taserface:BAAANQADCgQJBwAAAA==.',
Te='Temüjin:BAAANQAECgUICgAAAA==.',
Th='Tharamore:BAAANQAECgQIAgAAAA==.Theeonlyone:BAAANQAECgUIDgAAAA==.',
Ti='Tiberlock:BAAANQADCgMJBAAAAA==.Tioshadow:BAAANQAECgUICQABNQAECgkJIwAQACkbAA==.Tiosombra:BAAANQADCggICAABNQAECgkJIwAQACkbAA==.Tiranii:BAAANQAECgQJBgAAAA==.Titannus:BAAANQAECgEJAQAAAA==.',
Tr='Tralisa:BAAANQADCgEIAQAAAA==.Tribalrage:BAAANQAECgIJAwAAAA==.',
Tu='Tuktu:BAAANQAECgQIBwAAAA==.',
Ty='Tymberh:BAAANQABCgIIAgABNQAECgEJAQADAAAAAA==.',
Va='Vael:BAAANQAECgQJBAAAAA==.Vandal:BAAANQAECgcIEAAAAA==.Varrigos:BAAANQADCgUIDgAAAA==.',
Vo='Voltz:BAAANQAECgcIDgAAAA==.',
We='Wetbread:BAAANQAECgUICgAAAA==.',
Wi='Wiind:BAABNQAECoEcAAIMAAgKmhP+EgAlAgAMAAgKmhP+EgAlAgAAAA==.',
Wo='Wolfbaine:BAAANQADCgIIAgAAAA==.',
Xa='Xalityr:BAAANQAECgEIAQABNQAECgQICQADAAAAAA==.Xanaxos:BAAANQAECgEIAQAAAA==.Xanis:BAAANQADCgUJDgAAAA==.',
Xh='Xhaltrix:BAAANQABCgcIBwAAAA==.',
Xo='Xonz:BAABNQAECoEdAAITAAkKdxzXBwDLAgATAAkKdxzXBwDLAgAAAA==.',
Xu='Xuljin:BAAANQADCggICwABNQAECgkJIwAQACkbAA==.',
Yo='Yomamasez:BAAANQAECgQIBwAAAA==.',
Ze='Zethieran:BAAANQADCgMIAwAAAA==.',
Zh='Zhenith:BAAANQAECgQJCQABNQADCgUIBQADAAAAAA==.',
Zi='Zippoo:BAAANQABCgIIAgAAAA==.Zirnbie:BAAANQAECgEIAQAAAA==.',
Zo='Zoub:BAAANQAECgMIAwAAAA==.',
['Äc']='Ächilles:BAAANQADCgEIAQAAAA==.',
['Ða']='Ðark:BAAANQADCgEIAQABNQAECgkJHwALAOwdAA==.',
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
