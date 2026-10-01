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

local lookup = {'Hunter-Marksmanship','Druid-Restoration','Unknown-Unknown','Warrior-Fury','Priest-Discipline','Priest-Holy','Druid-Guardian','Warlock-Affliction','Shaman-Restoration','Paladin-Retribution','Warrior-Protection','DeathKnight-Frost','DemonHunter-Devourer','Warlock-Destruction','Warlock-Demonology','Hunter-BeastMastery','Evoker-Preservation','Priest-Shadow','DeathKnight-Blood','Rogue-Subtlety','Monk-Windwalker','Druid-Balance','Monk-Brewmaster','Rogue-Assassination','Mage-Frost','Shaman-Elemental','Paladin-Protection',}
local provider = {region='US',realm='Tanaris',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aalicya:BAAANQAECgEJAQAAAA==.',
Ac='Acegoblain:BAAANQAECgYICQABNQAFFAQIDAABAFkMAA==.',
Ad='Adind:BAABNQAECoEfAAICAAkKXxteCQD/AgACAAkKXxteCQD/AgAAAA==.Adonra:BAAANQADCgYIBgAAAA==.',
Ae='Aeromage:BAAANQADCgQIBAABNQADCgYIBgADAAAAAA==.Aeropally:BAAANQADCgUIBQABNQADCgYIBgADAAAAAA==.Aerorising:BAAANQADCgYIBgAAAA==.',
Ag='Aggressive:BAAANQADCgYIBgAAAA==.',
Ak='Akkiba:BAAANQADCgYICwAAAA==.',
Al='Alaval:BAAANQAECgQIBQAAAA==.Aldabaran:BAAANQADCgcIDgAAAA==.Alestalker:BAAANQADCgUIBQABNQADCgcIBwADAAAAAA==.Aletheïa:BAAANQADCggIDgAAAA==.Althamon:BAAANQADCgQIBQAAAA==.',
An='Andromalius:BAAANQADCgIIAgAAAA==.Antamun:BAABNQAECoEeAAIEAAkKqBVIBgBVAgAEAAkKqBVIBgBVAgAAAA==.',
Ao='Aoasis:BAAANQAECgQICQAAAA==.',
Aq='Aqueefer:BAAANQAECgQICAABNQAECgQIBQADAAAAAA==.',
Ar='Araethea:BAABNQAECoEbAAMFAAkKih4zAgDeAgAFAAgKnR8zAgDeAgAGAAUKzhz7VgDBAQAAAA==.Arasettey:BAAANQADCggICAABNQAECgkJFgAHAAAgAA==.Arethusa:BAAANQADCggICAAAAA==.Arislynn:BAAANQAECgUIDAAAAA==.Aryn:BAAANQAECgYIDwAAAA==.',
Au='Austin:BAAANQADCggICAAAAA==.',
Az='Azirra:BAAANQADCgYICwAAAA==.',
['Aù']='Aùriel:BAAANQAECgcIEgAAAA==.',
Ba='Badgerhollis:BAAANQADCgUICAAAAA==.Bailey:BAAANQAECgEIAQAAAA==.Bamalock:BAAANQAECgEIAQAAAA==.Bathin:BAABNQAECoEYAAIIAAcKkxfNBQAaAgAIAAcKkxfNBQAaAgAAAA==.Bathwater:BAABNQAECoEhAAIJAAkKLSKVCABfAwAJAAkKLSKVCABfAwAAAA==.',
Be='Bearbottom:BAAANQADCgYIBgAAAA==.Bearn:BAAANQADCggIDgAAAA==.',
Bi='Biffster:BAABNQAECoEcAAIKAAgK2RE6ZAAVAgAKAAgK2RE6ZAAVAgAAAA==.Bighellion:BAAANQADCgIIAgAAAA==.Bigmageguy:BAAANQAECgQIBAAAAA==.Bigpumps:BAAANQADCgEIAQABNQADCggJCAADAAAAAA==.Bigtriangle:BAABNQAECoEbAAILAAgKFhs4CgBOAgALAAgKFhs4CgBOAgABNQAECgkJFgAHAAAgAA==.Billiamson:BAAANQADCggIEwAAAA==.Birttok:BAAANQADCgEIAQAAAA==.',
Bj='Bjoris:BAABNQAECoEZAAIMAAgK+RjDHwA+AgAMAAgK+RjDHwA+AgAAAA==.',
Bl='Blackhawk:BAAANQABCgcJBQAAAA==.Bloodaxe:BAAANQADCggIBAAAAA==.',
Bo='Bornferal:BAAANQAECgUJBQAAAA==.',
Br='Bryzx:BAACNQAFFIETAAIJAAcKzBscAQCKAgAJAAcKzBscAQCKAgA1AAQKgRsAAgkACQqAIuMIAFwDAAkACQqAIuMIAFwDAAAA.Bryzxbless:BAAANQAECgEIAQABNQAECgYICAADAAAAAA==.',
Bu='Bubblebee:BAAANQAECgYIEQAAAA==.Bullan:BAAANQADCggICQAAAA==.Butterskotch:BAAANQADCgYIBgAAAA==.Buttpeanut:BAAANQAECgQICQAAAA==.',
Ca='Cakestripper:BAAANQAECgIIBAAAAA==.Cavetard:BAAANQADCgEJAQAAAA==.',
Ce='Ceravolo:BAAANQAECgEIAQAAAA==.',
Cl='Clairvoyance:BAAANQABCgMIAwABNQAECgcIGAAKAI8PAA==.',
Cr='Crunchynuget:BAABNQAECoEhAAIKAAkKzhsMNQC2AgAKAAkKzhsMNQC2AgAAAA==.',
Cy='Cynemon:BAAANQAECgQIBQAAAA==.Cynleel:BAAANQAECgEIAQABNQAECgQIBQADAAAAAA==.',
Da='Dadu:BAAANQADCgEJAQAAAA==.Daifuku:BAABNQAECoEgAAIMAAkKvR6mDAD/AgAMAAkKvR6mDAD/AgAAAA==.Darknonsence:BAAANQADCgQIBQAAAA==.David:BAAANQADCgQIBAABNQAECggIBwADAAAAAA==.',
De='Demonetizeme:BAAANQAECgYICwABNQAECgQIBQADAAAAAA==.Demonvomit:BAAANQAECgYJEAAAAA==.Dernix:BAAANQADCgUIBQABNQAECgMIAwADAAAAAA==.Deroy:BAAANQADCgEIAQAAAA==.Deåth:BAAANQAECgMIBQAAAA==.',
Di='Dissociative:BAAANQAECgYIDgAAAA==.',
Do='Dorktard:BAAANQADCgcIBwAAAA==.Dorpy:BAAANQADCgIIAgAAAA==.Dotfeardead:BAAANQADCgYIBgAAAA==.',
Dr='Draegohl:BAAANQADCgYIFAAAAA==.Dragordawn:BAAANQABCgUICQAAAA==.Drofiery:BAAANQAECgEJAQAAAA==.',
Ds='Dsypha:BAAANQAECgQIBwAAAA==.',
['Då']='Dåmage:BAAANQAECgMIAwAAAA==.',
Ed='Edric:BAAANQAECgUICQAAAA==.Edyion:BAAANQAECgQIBgAAAA==.',
Ef='Efreet:BAAANQAECgYIDAAAAA==.',
El='Elimae:BAEANQADCgMIBQAAAA==.Elvenfury:BAAANQADCggICAAAAA==.',
En='Enochian:BAAANQADCgMIBAAAAA==.',
Er='Erwinnas:BAAANQABCgEIAQAAAA==.',
Eu='Eurae:BAAANQAECgIIAgAAAA==.',
Ev='Evileye:BAAANQADCgYIBgABNQADCggJCAADAAAAAA==.Evoda:BAAANQAECgEJAQAAAA==.',
Ex='Extrodinaire:BAAANQAECgcIEgAAAA==.',
Ez='Eziopandator:BAAANQABCggIGwAAAA==.',
Fa='Fabiio:BAAANQAECgEIAQAAAA==.Fadedemon:BAABNQAECoEZAAINAAgK3RPwHgAdAgANAAgK3RPwHgAdAgAAAA==.Faedilan:BAAANQADCgQIBAAAAA==.Farrahmoans:BAAANQAECgUIDwAAAA==.',
Fe='Fellvarg:BAAANQAECgQIBQAAAA==.Felsgoodman:BAABNQAECoEhAAMOAAkK4R6XAwDsAgAOAAgKNCGXAwDsAgAPAAgKMhJcVgAHAgAAAA==.Felstriker:BAAANQADCgYIDQAAAA==.Ferluci:BAAANQAECgEIAQAAAA==.',
Fi='Filí:BAAANQADCgMIBQAAAA==.Firugan:BAAANQADCgYICgAAAA==.',
Fj='Fjaril:BAAANQADCggIKwABNQAECgYIBgADAAAAAA==.',
Fu='Fulgur:BAAANQADCgYIBgAAAA==.Fumistra:BAAANQADCggIDgAAAA==.',
Ga='Gahïjï:BAAANQADCgIIAgABNQAECgQICQADAAAAAA==.Galroot:BAAANQADCgUICAABNQAFFAQIDAABAFkMAA==.Galsnipes:BAACNQAFFIEMAAMBAAQKWQwJDQAUAQABAAQKggoJDQAUAQAQAAEKxgw5JgBOAAA1AAQKgScAAwEACArSH8wPAMYCAAEACArSH8wPAMYCABAAAQpTDZAQAUIAAAAA.Galvakrond:BAAANQAECgMIBQAAAA==.',
Ge='Geearr:BAAANQADCggIFgAAAA==.',
Gn='Gnarly:BAAANQADCgQIBAAAAA==.Gnomylanta:BAAANQADCgMIBwAAAA==.',
Go='Goldenhealer:BAAANQAECgUIBQABNQAECgkJFgAHAAAgAA==.Gomldruid:BAAANQAECggICAAAAA==.Gomletta:BAAANQAECgMIBQAAAA==.',
Gr='Grak:BAABNQAECoEYAAIRAAgKrglDHwCaAQARAAgKrglDHwCaAQABNQAECgkJFgASAMwSAA==.Gratescott:BAAANQAECgUIBwAAAA==.Grik:BAAANQAECgQICAAAAA==.Grimgull:BAAANQADCgUICgAAAA==.',
Gw='Gwyndora:BAAANQAECgUIBwAAAA==.',
['Gø']='Gøøber:BAAANQADCgUIBQAAAA==.',
He='Healup:BAAANQAECgYICgAAAA==.Hellenita:BAAANQADCgIIAgAAAA==.',
Hi='Hildebrand:BAAANQADCgYJBgAAAA==.Hitomitanaka:BAAANQAECgcICgAAAA==.',
Ho='Holyoshyy:BAAANQAECgYIDwAAAA==.Holytiber:BAAANQADCgEIAQAAAA==.Holyvengence:BAAANQAECgQIBgAAAA==.',
Hu='Hup:BAAANQADCggIDAAAAA==.',
Id='Idiorr:BAAANQADCgYIBgAAAA==.',
Ie='Iemanja:BAAANQAECgIIAgAAAA==.',
In='Inarin:BAAANQADCgYIFAAAAA==.',
Is='Ismitethou:BAAANQADCggICQABNQAECgIIAgADAAAAAA==.',
It='Itzsavage:BAAANQADCgQIBAAAAA==.',
Ja='Jachyra:BAAANQAECgUICgAAAA==.Jackmanss:BAAANQADCgYICgAAAA==.Jaell:BAAANQADCgMIBQAAAA==.Jamezon:BAAANQAECgYICgAAAA==.',
Je='Jes:BAAANQAECgMIAwAAAA==.',
Ji='Jitlok:BAAANQAECgQIBgAAAA==.',
Jo='Johnashr:BAAANQADCgQIBAABNQADCgYIEQADAAAAAA==.Joonbug:BAAANQABCgQJBwAAAA==.',
Ju='Juràssic:BAAANQAECgUICAAAAA==.',
Ka='Kaeul:BAABNQAECoEXAAIJAAgKPCUrCgBPAwAJAAgKPCUrCgBPAwAAAA==.Kahrot:BAAANQAECggICgAAAA==.Kalia:BAAANQADCgEIAgAAAA==.Kalius:BAAANQAECgQIBgAAAA==.Kando:BAAANQADCgIIAgAAAA==.Kazgrom:BAAANQADCgQIBQAAAA==.Kazool:BAAANQADCggIEAAAAA==.',
Ke='Keanuleaves:BAAANQADCgYIBgABNQAECgUIDwADAAAAAA==.',
Ki='Killerattack:BAAANQADCggIDwABNQAECgkJFgAHAAAgAA==.Killerheal:BAABNQAECoEWAAIHAAkKACDIAwAwAwAHAAkKACDIAwAwAwAAAA==.Kiralan:BAAANQADCgcJCQAAAA==.Kizzu:BAAANQAECgYIEAAAAA==.',
Kl='Klawdius:BAAANQADCgEIAQAAAA==.',
Kn='Knash:BAAANQADCgEIAQAAAA==.Knower:BAAANQADCggIGwAAAA==.',
Ko='Kostah:BAAANQAECgcIEAAAAA==.',
Kr='Kracu:BAAANQADCgIIAgAAAA==.',
['Kí']='Kíli:BAAANQADCgMIBQAAAA==.',
['Kø']='Køteb:BAABNQAECoEcAAMTAAgKDxzCIAB4AgATAAgKDxzCIAB4AgAMAAMKpwMCbQB1AAAAAA==.',
Le='Leadshot:BAAANQAECgQIDQAAAA==.',
Ly='Lyzbeth:BAAANQABCgUJAwAAAA==.',
['Lï']='Lïmes:BAAANQADCggJDwAAAA==.',
Ma='Maakha:BAAANQAECgQIBgAAAA==.Mabalzich:BAAANQADCgYIFAAAAA==.Madamewhimzy:BAAANQAECgEIAQAAAA==.Madsumo:BAAANQAECgYIBgAAAA==.Magroot:BAABNQAECoEYAAIUAAgKUhgeDwBoAgAUAAgKUhgeDwBoAgAAAA==.Makula:BAAANQAECgQIBgAAAA==.Mana:BAAANQAECgYICQAAAA==.Manabun:BAAANQAECgQIBQAAAA==.Manacakes:BAAANQAECgQIBgAAAA==.Manamuffins:BAAANQADCgYICgAAAA==.Manapie:BAAANQADCgQJBAAAAA==.Mannadina:BAABNQAECoEcAAIGAAkKmhiTIAC1AgAGAAkKmhiTIAC1AgAAAA==.Mannalight:BAAANQADCgEIAQABNQAECgkJHAAGAJoYAA==.Mapera:BAAANQAECgQIBgAAAA==.Marandra:BAAANQADCgIJAgAAAA==.Maray:BAAANQADCgYIDAAAAA==.Marjaya:BAAANQAECgEIAQAAAA==.Maynarde:BAAANQABCgYIBgAAAA==.',
Me='Medivarg:BAAANQADCgUIBQAAAA==.Meloncauley:BAAANQAECgYIEwAAAA==.',
Mi='Michaal:BAAANQADCgcIBwAAAA==.Mirisa:BAAANQAECgMIAwAAAA==.Mirosa:BAAANQAECgQIBgAAAA==.Mistmuncher:BAAANQADCgcIBwAAAA==.',
Mo='Mooahdib:BAAANQAECgMIAwAAAA==.',
Mu='Murmur:BAAANQAECgIIAwAAAA==.',
My='Mybrother:BAAANQAECgMIAgAAAA==.',
Na='Nangsa:BAAANQAECgQIBQAAAA==.Nautisassin:BAAANQADCggIKAABNQAECgYIBgADAAAAAA==.',
Ne='Neilrodimus:BAAANQADCgQIBAAAAA==.Nessva:BAAANQAECgUIDAAAAA==.Neçromonger:BAABNQAECoEeAAMQAAkKeSVWCAB9AwAQAAgKaSZWCAB9AwABAAMKfCGxOQAcAQAAAA==.',
Ni='Nikidas:BAAANQADCgYIBgAAAA==.Ninurta:BAAANQADCggIKQAAAA==.',
No='Noxz:BAABNQAECoEhAAQSAAkKmR59DgDXAgASAAkKmR59DgDXAgAGAAcKpxILVgDEAQAFAAEKNxTBIQA1AAAAAA==.',
Ny='Nyiais:BAAANQAECgQIBgAAAA==.',
Ob='Obsessedwith:BAAANQAECgUIDAAAAA==.',
Oh='Ohamernster:BAAANQAECgIIAQAAAA==.',
Oo='Oonspork:BAAANQADCgUIBQAAAA==.',
Pa='Paladinrob:BAAANQADCgEIAgAAAA==.Palyfight:BAAANQADCgIIAgAAAA==.Pangurrban:BAAANQADCgMIBQAAAA==.',
Pe='Persiflage:BAAANQADCggIFQAAAA==.',
Po='Poinen:BAAANQAECgQIBAABNQAECgkJFgASAMwSAA==.',
Pr='Priestin:BAAANQAECgEIAQAAAA==.',
Ps='Psyscape:BAAANQADCgQIBQAAAA==.',
Ra='Raginghavoc:BAAANQAECgQIBAAAAA==.Raichi:BAABNQAECoEhAAIVAAkKJRoiFABrAgAVAAkKJRoiFABrAgAAAA==.Raihne:BAAANQADCgEIAQAAAA==.Ramasseuse:BAAANQABCgIIAgAAAA==.',
Re='Reallyreally:BAAANQAECggIDQAAAA==.Reeally:BAAANQAECgMIAwABNQAECggIDQADAAAAAA==.Reelly:BAAANQADCgUIBwABNQAECggIDQADAAAAAA==.Reppitt:BAAANQADCgMIBAAAAA==.',
Ri='Rionnach:BAAANQADCgQIBAAAAA==.Riopia:BAAANQADCgYIDAAAAA==.Riptheramore:BAAANQAECgQIBAAAAA==.',
Ro='Rod:BAAANQADCgUIBQAAAA==.Roenwyn:BAAANQADCgIIAgAAAA==.Ronny:BAAANQADCgIJAgABNQAECgkJIgAWAFYhAA==.Ronosaur:BAABNQAECoEiAAIWAAkKViEhDQBEAwAWAAkKViEhDQBEAwAAAA==.Rons:BAAANQAECgUICAABNQAECgkJIgAWAFYhAA==.Rozzinor:BAAANQAECgEIAQABNQAECgQIDAADAAAAAA==.Rozzjung:BAAANQAECgMIBAABNQAECgQIDAADAAAAAA==.',
Ru='Rubyrhod:BAAANQABCgMIAwAAAA==.Rubystars:BAAANQADCggJDAABNQAFFAQIBQAQAD0KAA==.Ruslah:BAAANQAECgUIBwAAAA==.',
Sa='Sacredmoo:BAAANQADCgIIAgABNQADCggIDAADAAAAAA==.Salèèñä:BAAANQADCgQJBAAAAA==.Sangoki:BAABNQAECoEZAAIXAAgK3BPfDADuAQAXAAgK3BPfDADuAQAAAA==.Sanguinius:BAAANQAECgUICAAAAA==.Savageslayer:BAABNQAECoEhAAMWAAkKrxjkIACQAgAWAAkKrxjkIACQAgAHAAEKiwcXRwAiAAAAAA==.Savagespally:BAAANQADCgMIAwAAAA==.',
Se='Senshi:BAAANQADCgcIDQAAAA==.Serrena:BAAANQADCgYIBgAAAA==.Seventl:BAABNQAECoEYAAMYAAgKOhi8GABlAgAYAAgKOhi8GABlAgAUAAQKqQdHNADYAAAAAA==.',
Sh='Shadowbloom:BAAANQAECgEIAQAAAA==.Shamace:BAAANQAECgMIBAAAAA==.Shaokhan:BAABNQAECoEmAAIVAAkKuBzvEQCLAgAVAAkKuBzvEQCLAgAAAA==.Shar:BAAANQADCgUIBQAAAA==.Shoosts:BAAANQADCgUIBgAAAA==.Shåmwõw:BAAANQADCgYIBgAAAA==.',
Si='Simbru:BAAANQAECgMIBQAAAA==.Sioux:BAAANQADCgYIBwAAAA==.',
Sp='Spheres:BAAANQADCggIDAAAAA==.',
Sq='Squant:BAAANQABCgEIAQAAAA==.',
St='Stainman:BAAANQAECgUIBQABNQAECgcIEQADAAAAAA==.Steele:BAAANQAECgQIBAAAAA==.Stoogatz:BAAANQAECgQIDAAAAA==.Stormiee:BAAANQADCgMIBQAAAA==.Strongbow:BAAANQADCgYIEQAAAA==.',
Su='Suicidekings:BAAANQAECgUIBwABNQAECgYIDgADAAAAAA==.',
['Sí']='Símbá:BAAANQAECgIIAgAAAA==.',
['Sø']='Sølari:BAAANQAECgEIAQAAAA==.',
Ta='Takerfan:BAABNQAECoEYAAIWAAcKowrvSAB0AQAWAAcKowrvSAB0AQAAAA==.Tallyblue:BAAANQAECgUICQAAAA==.Tanarisfry:BAAANQAECgUIBwAAAA==.Taserface:BAAANQADCgQJBwAAAA==.',
Te='Temüjin:BAAANQAECgcIEQAAAA==.',
Th='Tharamore:BAAANQAECgQIAgABNQAECgQIBAADAAAAAA==.Theeonlyone:BAABNQAECoEZAAIPAAcKXxRTZwDRAQAPAAcKXxRTZwDRAQAAAA==.',
Ti='Tiberlock:BAAANQADCgMJBAAAAA==.Tioshadow:BAAANQAECgYICwABNQAECgkJJgAVALgcAA==.Tiosombra:BAAANQADCggICAABNQAECgkJJgAVALgcAA==.Tiranii:BAAANQAECgUICwAAAA==.Titannus:BAAANQAECgUIBgABNQAECgYIBgADAAAAAA==.',
Tr='Tralisa:BAAANQADCgEIAQAAAA==.Tribalrage:BAAANQAECgQICAAAAA==.',
Tu='Tuktu:BAAANQAECgQIBwAAAA==.',
Ty='Tymberh:BAAANQABCgIIAgABNQAECgYIBgADAAAAAA==.',
Um='Umbraheart:BAEANQAECgEIAQABNQAECggIIQAZAIQaAA==.',
Va='Vael:BAAANQAECgQJBAAAAA==.Vandal:BAABNQAECoEWAAQSAAkKzBJ5HwDzAQASAAgKTBF5HwDzAQAFAAYKngqpDAA4AQAGAAEK+wXSwwA/AAAAAA==.Varrigos:BAAANQADCgYIFAAAAA==.',
Vo='Voltz:BAABNQAECoEVAAIaAAgKSA5HVADYAQAaAAgKSA5HVADYAQAAAA==.',
We='Wetbread:BAAANQAECgYIEAAAAA==.',
Wi='Wiind:BAABNQAECoEfAAIRAAkKGxKXEgBVAgARAAkKGxKXEgBVAgAAAA==.',
Wo='Wolfbaine:BAAANQADCgIIAgAAAA==.',
Xa='Xalityr:BAAANQAECgEIAQABNQAECgQICQADAAAAAA==.Xanaxos:BAAANQAECgEIAQAAAA==.Xanis:BAAANQADCgUIDgAAAA==.',
Xh='Xhaltrix:BAAANQABCgcIBwAAAA==.',
Xo='Xonz:BAABNQAECoEiAAIbAAkKyxwgCwCoAgAbAAkKyxwgCwCoAgAAAA==.',
Xu='Xuljin:BAAANQADCggICwABNQAECgkJJgAVALgcAA==.',
Yo='Yomamasez:BAAANQAECgUIDAAAAA==.',
Ze='Zethieran:BAAANQADCgMIAwAAAA==.',
Zh='Zhenith:BAAANQAECgYIDwABNQADCgcIBwADAAAAAA==.',
Zi='Zippoo:BAAANQABCgIIAgAAAA==.Zirnbie:BAAANQAECgQIBQAAAA==.',
Zo='Zoub:BAAANQAECgMIAwAAAA==.',
['Äc']='Ächilles:BAAANQADCgEIAQAAAA==.',
['Ða']='Ðark:BAAANQADCgEIAQABNQAECgkJJgAQAN4fAA==.',
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
