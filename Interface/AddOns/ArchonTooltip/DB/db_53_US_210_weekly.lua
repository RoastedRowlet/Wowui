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

local lookup = {'Hunter-Marksmanship','Druid-Restoration','Unknown-Unknown','Warrior-Fury','Priest-Discipline','Priest-Holy','Druid-Guardian','Paladin-Holy','Warlock-Affliction','Shaman-Restoration','Paladin-Retribution','Warrior-Protection','DeathKnight-Frost','Hunter-BeastMastery','Shaman-Enhancement','DemonHunter-Devourer','Mage-Frost','Warlock-Destruction','Warlock-Demonology','Evoker-Preservation','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Blood','Rogue-Subtlety','Monk-Windwalker','Druid-Balance','Monk-Brewmaster','Rogue-Assassination','Shaman-Elemental','Paladin-Protection','Evoker-Devastation','Evoker-Augmentation',}
local provider = {region='US',realm='Tanaris',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aalicya:BAAANQAECgEIAQAAAA==.',
Ac='Acegoblain:BAAANQAECgcIDAABNQAFFAUIEAABAPUOAA==.',
Ad='Adind:BAABNQAECoEoAAICAAkKvhx+CwD3AgACAAkKvhx+CwD3AgAAAA==.Adonra:BAAANQADCgYIBgAAAA==.',
Ae='Aeromage:BAAANQADCgQIBAABNQADCgYICwADAAAAAA==.Aeropally:BAAANQADCgYICwAAAA==.Aerorising:BAAANQADCgYIBgABNQADCgYICwADAAAAAA==.',
Ag='Aggressive:BAAANQADCgYIBgAAAA==.',
Ak='Akkiba:BAAANQADCgYICwAAAA==.',
Al='Alaval:BAAANQAECgUICgAAAA==.Aldabaran:BAAANQADCgcIDgAAAA==.Aldolador:BAAANQAECgIIAQAAAA==.Alestalker:BAAANQADCgUIBQABNQADCgcICQADAAAAAA==.Aletheïa:BAAANQADCggIDgAAAA==.Althamon:BAAANQADCgQIBQAAAA==.',
An='Andromalius:BAAANQADCgIIAgAAAA==.Antamun:BAABNQAECoEkAAIEAAkKlBZPBwBcAgAEAAkKlBZPBwBcAgAAAA==.',
Ao='Aoasis:BAAANQAECgYIDwAAAA==.',
Aq='Aqueefer:BAAANQAECgQICAABNQAECgUICgADAAAAAA==.',
Ar='Araethea:BAABNQAECoEiAAMFAAkK3h9nAgDlAgAFAAgK9R9nAgDlAgAGAAYKZSFIPABUAgAAAA==.Arasettey:BAAANQADCggICAABNQAFFAUICQAHABIcAA==.Arethusa:BAAANQADCggICAAAAA==.Arislynn:BAAANQAECgYIEgAAAA==.Aryn:BAAANQAECgYIDwAAAA==.',
As='Assumì:BAAANQAECgQIBAAAAA==.',
Au='Austin:BAAANQADCggICAAAAA==.',
Az='Azirra:BAAANQADCgYIDAAAAA==.Azrissil:BAAANQADCgUIBQAAAA==.',
['Aù']='Aùriel:BAABNQAECoEeAAIIAAgKZCJ3FAAeAwAIAAgKZCJ3FAAeAwAAAA==.',
Ba='Badgerhollis:BAAANQADCgUICAAAAA==.Bailey:BAAANQAECgEIAQAAAA==.Bamalock:BAAANQAECgEIAQAAAA==.Bathin:BAABNQAECoEgAAIJAAgKHxlNBAB3AgAJAAgKHxlNBAB3AgAAAA==.Bathwater:BAABNQAECoEnAAIKAAkKnSIZCgBcAwAKAAkKnSIZCgBcAwAAAA==.',
Be='Bearbottom:BAAANQADCgYIBgAAAA==.Bearn:BAAANQADCggIDgAAAA==.',
Bi='Biffster:BAABNQAECoEcAAILAAgK2REOfAACAgALAAgK2REOfAACAgAAAA==.Bighellion:BAAANQADCgIIAgAAAA==.Bigmageguy:BAAANQAECgQIBAABNQAECgUIBQADAAAAAA==.Bigpumps:BAAANQADCgEIAQABNQADCggJCAADAAAAAA==.Bigtriangle:BAABNQAECoEbAAIMAAgKERsYDABJAgAMAAgKERsYDABJAgABNQAFFAUICQAHABIcAA==.Billiamson:BAAANQAECgIIAgAAAA==.Birttok:BAAANQADCgEIAQAAAA==.',
Bj='Bjoris:BAABNQAECoEhAAINAAgK6RoNIgBSAgANAAgK6RoNIgBSAgAAAA==.',
Bl='Blackhawk:BAAANQABCgcJBQAAAA==.Bloodaxe:BAAANQAECgEIAQAAAA==.',
Bo='Booddha:BAAANQADCgQIBAAAAA==.Bornferal:BAAANQAECgUJBQAAAA==.Botasamigo:BAAANQADCgEIAQAAAA==.',
Br='Bryzx:BAACNQAFFIETAAIKAAcKzBvYAQB9AgAKAAcKzBvYAQB9AgA1AAQKgRsAAgoACQqAIrILAE4DAAoACQqAIrILAE4DAAAA.Bryzxbless:BAAANQAECgEIAQABNQAECgYICAADAAAAAA==.',
Bu='Bubblebee:BAABNQAECoEZAAIOAAgKqxJwXQAzAgAOAAgKqxJwXQAzAgAAAA==.Bullan:BAAANQADCggICQAAAA==.Butterskotch:BAAANQADCgYIBgAAAA==.Buttpeanut:BAAANQAECgQIDQAAAA==.',
Ca='Cakestripper:BAAANQAECgMICgAAAA==.Cavetard:BAAANQADCgEJAQAAAA==.',
Ce='Ceravolo:BAAANQAECgEIAQAAAA==.',
Cl='Clairvoyance:BAAANQABCgMIAwABNQAECggIHwALALQPAA==.',
Co='Corvetteman:BAAANQADCgEIAQAAAA==.',
Cr='Crunchynuget:BAABNQAECoEoAAILAAkKCR8YHgA0AwALAAkKCR8YHgA0AwAAAA==.',
Cy='Cynemon:BAAANQAECgQICQAAAA==.Cynleel:BAAANQAECgEIAQABNQAECgQICQADAAAAAA==.',
Da='Dadu:BAAANQADCgEJAQAAAA==.Daifuku:BAABNQAECoEoAAINAAkKUCF3BwBaAwANAAkKUCF3BwBaAwAAAA==.Darknonsence:BAAANQADCgQIBQAAAA==.David:BAAANQADCgQIBAABNQAECggICQADAAAAAA==.',
De='Demonetizeme:BAAANQAECgYIDwABNQAECgUICgADAAAAAA==.Demonvomit:BAAANQAECgYJEAAAAA==.Dernix:BAAANQADCgUIBQABNQAECgMIAwADAAAAAA==.Deroy:BAAANQADCgEIAQAAAA==.Deåth:BAAANQAECgMIBQAAAA==.',
Di='Dissociative:BAAANQAECgYIDgAAAA==.',
Do='Dorktard:BAAANQADCgcICQAAAA==.Dorpy:BAAANQADCgYIBgAAAA==.Dotfeardead:BAAANQADCgYIBgAAAA==.',
Dr='Draegohl:BAAANQADCgYIGgAAAA==.Dragordawn:BAAANQABCgUICQAAAA==.Drofiery:BAAANQAECgEJAQAAAA==.',
Ds='Dsypha:BAAANQAECgQIBwAAAA==.',
['Då']='Dåmage:BAAANQAECgMICAAAAA==.',
Ed='Edric:BAAANQAECgUICQAAAA==.Edyion:BAAANQAECgQICgAAAA==.',
Ef='Efreet:BAAANQAECgYIEgAAAA==.',
El='Elimae:BAEANQADCgMIBQAAAA==.Elvenfury:BAAANQADCggICgAAAA==.',
En='Enochian:BAAANQADCgQIBQAAAA==.',
Er='Erwinnas:BAAANQABCgEIAQAAAA==.',
Eu='Eurae:BAAANQAECgIIAwAAAA==.',
Ev='Evileye:BAAANQADCgYIBgABNQADCggJCAADAAAAAA==.Evoda:BAAANQAECgQIBQAAAA==.',
Ex='Extrodinaire:BAABNQAECoEeAAIPAAgK1Rd/DgBpAgAPAAgK1Rd/DgBpAgAAAA==.',
Ez='Eziopandator:BAAANQABCggIGwAAAA==.',
Fa='Fabiio:BAAANQAECgEIAQABNQAECgIIAQADAAAAAA==.Fadedemon:BAABNQAECoEhAAIQAAgKYRpGFwCMAgAQAAgKYRpGFwCMAgAAAA==.Faedilan:BAAANQADCgQIBAAAAA==.Farrahmoans:BAABNQAECoEZAAIRAAcKYiDxBQCAAgARAAcKYiDxBQCAAgAAAA==.',
Fe='Fellvarg:BAAANQAECgQICQAAAA==.Felsgoodman:BAABNQAECoEnAAMSAAkK4R4sBADeAgASAAgKNCEsBADeAgATAAgKrxSUWwAjAgAAAA==.Felstriker:BAAANQAECgYIBgAAAA==.Feoleets:BAAANQADCgIIAgAAAA==.Ferluci:BAAANQAECgEIAQAAAA==.',
Fi='Filí:BAAANQADCgQIBgAAAA==.Firugan:BAAANQADCgYICgAAAA==.',
Fj='Fjaril:BAAANQAECgMIAwABNQAECgYIDAADAAAAAA==.',
Fu='Fulgur:BAAANQADCgYIBgAAAA==.Fumistra:BAAANQADCggIDgAAAA==.',
Ga='Gahïjï:BAAANQADCgIIAgABNQAECgYIDwADAAAAAA==.Galroot:BAAANQADCgUICAABNQAFFAUIEAABAPUOAA==.Galsnipes:BAACNQAFFIEQAAMBAAUK9Q4jCwBmAQABAAUKkQ4jCwBmAQAOAAEKxgx3LgBOAAA1AAQKgSoAAwEACArSH9oTAKwCAAEACArSH9oTAKwCAA4AAQpTDZEwAUEAAAAA.Galvakrond:BAAANQAECgQICQAAAA==.',
Ge='Gearno:BAAANQADCgIIAgAAAA==.Geearr:BAAANQADCggIFgAAAA==.',
Gn='Gnarly:BAAANQADCgQIBAAAAA==.',
Go='Goldenhealer:BAAANQAECgUIBQABNQAFFAUICQAHABIcAA==.Gomldruid:BAAANQAECggICAAAAA==.Gomletta:BAAANQAECgQICQAAAA==.',
Gr='Grak:BAABNQAECoEdAAIUAAgK0AteIQCkAQAUAAgK0AteIQCkAQABNQAECgkJHQAVAIwTAA==.Gratescott:BAAANQAECgUIDAAAAA==.Grik:BAAANQAECgUIDQAAAA==.Grimgull:BAAANQADCgUICgAAAA==.',
Gw='Gwyndora:BAAANQAECgUIDAAAAA==.',
['Gø']='Gøøber:BAAANQADCgUIBQAAAA==.',
He='Healup:BAAANQAECgYICwAAAA==.Hellenita:BAAANQADCgIIAgAAAA==.',
Hi='Hildebrand:BAAANQADCgYJBgAAAA==.Hitomitanaka:BAAANQAECgcIDQAAAA==.',
Ho='Holyoshyy:BAAANQAECgcIEQAAAA==.Holytiber:BAAANQADCgEIAQAAAA==.Holyvengence:BAAANQAECgQICQAAAA==.',
Hu='Hup:BAAANQADCggIDAAAAA==.',
Id='Idiorr:BAAANQADCgYIBgAAAA==.',
Ie='Iemanja:BAAANQAECgIIAgAAAA==.',
In='Inarin:BAAANQADCgYIGgAAAA==.',
Is='Ismitethou:BAAANQADCggICQABNQAECgQIBgADAAAAAA==.',
It='Itzsavage:BAAANQADCgQIBAAAAA==.',
Ja='Jachyra:BAAANQAECgYIEAAAAA==.Jackmanss:BAAANQADCgYICgAAAA==.Jaell:BAAANQADCgQIBgAAAA==.Jamezon:BAAANQAECgYICgAAAA==.',
Je='Jes:BAAANQAECgMIAwAAAA==.',
Ji='Jitlok:BAAANQAECgQICgAAAA==.',
Jo='Johnashr:BAAANQADCgQIBAABNQADCgYIEQADAAAAAA==.Johnzanpally:BAAANQABCgMIAwAAAA==.Joonbug:BAAANQABCgQJBwAAAA==.',
Ju='Juràssic:BAAANQAECgUIDQAAAA==.',
Ka='Kaeul:BAABNQAECoEZAAIKAAgKvCXuCgBVAwAKAAgKvCXuCgBVAwAAAA==.Kahrot:BAAANQAECggIEQAAAA==.Kalia:BAAANQADCgEIAgAAAA==.Kalius:BAAANQAECgQICgAAAA==.Kando:BAAANQADCgMIAwAAAA==.Kazgrom:BAAANQADCgQIBQAAAA==.Kazool:BAAANQAECgUIBQAAAA==.',
Ke='Keanuleaves:BAAANQADCgYIBgABNQAECgcIGQARAGIgAA==.',
Ki='Killerattack:BAAANQADCggIDwABNQAFFAUICQAHABIcAA==.Killerheal:BAACNQAFFIEJAAIHAAUKEhwTAQC8AQAHAAUKEhwTAQC8AQA1AAQKgRgAAgcACQqsIMEEADEDAAcACQqsIMEEADEDAAAA.Kiralan:BAAANQADCgcJCQAAAA==.Kizzu:BAABNQAECoEbAAMWAAcKSBySMQBDAgAWAAcKSBySMQBDAgANAAcKdxZGNADPAQAAAA==.',
Kl='Klawdius:BAAANQADCgYIBwAAAA==.',
Kn='Knash:BAAANQADCgEIAQAAAA==.Knower:BAAANQADCggIGwAAAA==.',
Ko='Kostah:BAAANQAECgcIEAAAAA==.',
Kr='Kracu:BAAANQADCgIIAgAAAA==.',
['Kí']='Kíli:BAAANQADCgQIBgAAAA==.',
['Kø']='Køteb:BAABNQAECoEiAAMXAAgKDxzsJwBlAgAXAAgKDxzsJwBlAgANAAMKpwOGfABwAAAAAA==.',
Le='Leadshot:BAAANQAECgQIEQAAAA==.Leves:BAAANQADCggICAABNQAECgUIBQADAAAAAA==.',
Ly='Lyzbeth:BAAANQABCgUJAwAAAA==.',
['Lï']='Lïmes:BAAANQAECgQIBAAAAA==.',
Ma='Maakha:BAAANQAECgQICgAAAA==.Mabalzich:BAAANQADCgYIGgAAAA==.Madamewhimzy:BAAANQAECgEIAQAAAA==.Madsumo:BAAANQAECgYIDAAAAA==.Magroot:BAABNQAECoEgAAIYAAgKAB0dCwC0AgAYAAgKAB0dCwC0AgAAAA==.Makula:BAAANQAECgQICAAAAA==.Mana:BAAANQAECgcICgAAAA==.Manabun:BAAANQAECgQIBwAAAA==.Manacakes:BAAANQAECgUIBwAAAA==.Manamuffins:BAAANQADCgYICgAAAA==.Manapie:BAAANQADCgQJBAAAAA==.Mannadina:BAABNQAECoEcAAIGAAkKmhhpKQClAgAGAAkKmhhpKQClAgAAAA==.Mannalight:BAAANQADCgEIAQABNQAECgkJHAAGAJoYAA==.Mapera:BAAANQAECgQICgAAAA==.Marandra:BAAANQADCgIJAgAAAA==.Maraxx:BAAANQAECgQIBQAAAA==.Maray:BAAANQAECgIIAgAAAA==.Marjaya:BAAANQAECgEIAQAAAA==.Maynarde:BAAANQABCgYIBgAAAA==.',
Me='Medivarg:BAAANQADCgUIBQAAAA==.Meloncauley:BAABNQAECoEXAAMXAAYKPRIGVwB1AQAXAAYKPRIGVwB1AQANAAMKbASjfwBnAAAAAA==.',
Mi='Michaal:BAAANQADCgcIBwAAAA==.Mirisa:BAAANQAECgMIAwAAAA==.Mirosa:BAAANQAECgQICgAAAA==.Mistmuncher:BAAANQADCgcIBwAAAA==.',
Mo='Mooahdib:BAAANQAECgMIBQAAAA==.',
Mu='Murmur:BAAANQAECgIIAwAAAA==.',
My='Mybrother:BAAANQAECgMIBAAAAA==.',
Na='Nangsa:BAAANQAECgQICQAAAA==.Nautisassin:BAAANQAECgQIBQABNQAECgYIDAADAAAAAA==.',
Ne='Neilrodimus:BAAANQADCgQIBAAAAA==.Nessva:BAAANQAECgYIEgAAAA==.Neçromonger:BAABNQAECoEnAAMOAAkKDyZ6AgDXAwAOAAkKDyZ6AgDXAwABAAMKfCGXQgAPAQAAAA==.',
Ni='Nikidas:BAAANQADCgYIBgAAAA==.Ninurta:BAAANQADCggILQAAAA==.',
No='Noxz:BAABNQAECoEnAAQVAAkKmR5YEgC7AgAVAAkKmR5YEgC7AgAGAAgKIROZUAAIAgAFAAEKNxQrJwAwAAAAAA==.',
Ny='Nyiais:BAAANQAECgQICgAAAA==.',
Ob='Obsessedwith:BAAANQAECgYIEgAAAA==.',
Oh='Ohamernster:BAAANQAECgIIAQAAAA==.',
Oo='Oonspork:BAAANQADCgUIBQAAAA==.',
Pa='Paladinrob:BAAANQADCgEIAgAAAA==.Palyfight:BAAANQADCgIIAgAAAA==.Pangurrban:BAAANQADCgQIBgAAAA==.',
Pe='Persiflage:BAAANQADCggIHAAAAA==.',
Po='Poinen:BAAANQAECgQIBAABNQAECgkJHQAVAIwTAA==.',
Pr='Priestin:BAAANQAECgEIAQAAAA==.',
Ps='Psyscape:BAAANQADCgQIBQAAAA==.',
Ra='Raginghavoc:BAAANQAECgUIBQAAAA==.Raichi:BAABNQAECoEnAAIZAAkK2RqOFgBxAgAZAAkK2RqOFgBxAgAAAA==.Raihne:BAAANQADCgEIAQAAAA==.Ramasseuse:BAAANQABCgIIAgAAAA==.',
Re='Reallyreally:BAABNQAECoEZAAIOAAgKphq1MgCxAgAOAAgKphq1MgCxAgAAAA==.Reeally:BAAANQAECgQICQABNQAECggIGQAOAKYaAA==.Reelly:BAAANQADCgUIBwABNQAECggIGQAOAKYaAA==.Reppitt:BAAANQADCgQIBQAAAA==.',
Ri='Rik:BAAANQAECgQIBAAAAA==.Rionnach:BAAANQADCgQIBAAAAA==.Riopia:BAAANQADCgYIDAAAAA==.Riptheramore:BAAANQAECgUIBQAAAA==.',
Ro='Rod:BAAANQADCgUIBQAAAA==.Roenwyn:BAAANQADCgMIAwAAAA==.Ronny:BAAANQAECgEIAQABNQAECgkJKwAaAFYhAA==.Ronosaur:BAABNQAECoErAAMaAAkKViHCEAAvAwAaAAkKViHCEAAvAwACAAMK6xT5RADRAAAAAA==.Ronrad:BAAANQADCggICAABNQAECgkJKwAaAFYhAA==.Rons:BAAANQAECgUICAABNQAECgkJKwAaAFYhAA==.Roulette:BAAANQADCgYIBwAAAA==.Rozzinor:BAAANQAECgIIAwABNQAECgYIEgADAAAAAA==.Rozzjung:BAAANQAECgMIBQABNQAECgYIEgADAAAAAA==.',
Ru='Rubyrhod:BAAANQABCgMIAwAAAA==.Rubystars:BAAANQADCggJDAABNQAFFAQICQAOAEcXAA==.Ruslah:BAAANQAECgUIDAAAAA==.',
Sa='Sacredmoo:BAAANQADCgIIAgABNQADCggIDAADAAAAAA==.Salèèñä:BAAANQADCgQJBAAAAA==.Sangoki:BAABNQAECoEhAAIbAAgKphWqDQD+AQAbAAgKphWqDQD+AQAAAA==.Sanguinius:BAAANQAECgYIDgAAAA==.Savageslayer:BAABNQAECoEnAAMaAAkKExl8JgB+AgAaAAkKExl8JgB+AgAHAAEKiwd5VgAiAAAAAA==.Savagespally:BAAANQADCgMIAwAAAA==.',
Se='Sendrin:BAAANQAECgEIAQAAAA==.Senshi:BAAANQADCgcIDQAAAA==.Serrena:BAAANQAECgEIAQAAAA==.Seventl:BAABNQAECoEgAAMcAAgKNBy8GQCHAgAcAAgKNBy8GQCHAgAYAAQKqQcrOADTAAAAAA==.',
Sh='Shadowbloom:BAAANQAECgIIAwAAAA==.Shamace:BAAANQAECgMIBAAAAA==.Shammoo:BAAANQAECgQIBAAAAA==.Shaokhan:BAACNQAFFIEFAAIZAAMKDhE3CgDVAAAZAAMKDhE3CgDVAAA1AAQKgSkAAhkACQpaHewTAJUCABkACQpaHewTAJUCAAAA.Shar:BAAANQADCgUIBQAAAA==.Shoktopus:BAAANQADCgYIBgABNQAECgUICgADAAAAAA==.Shoosts:BAAANQADCgUIBgAAAA==.Shåmwõw:BAAANQADCgYIBgAAAA==.',
Si='Simbru:BAAANQAECgQICQAAAA==.Sioux:BAAANQADCgYIBwAAAA==.',
Sp='Spheres:BAAANQADCggIDAAAAA==.',
Sq='Squant:BAAANQABCgEIAQAAAA==.',
St='Stainman:BAAANQAECgUICQABNQAECggIGQALAA0eAA==.Steele:BAAANQAECgQIBAAAAA==.Stoogatz:BAAANQAECgYIEgAAAA==.Stormiee:BAAANQADCgQIBgAAAA==.Strongbow:BAAANQADCgYIEQAAAA==.',
Su='Suicidekings:BAAANQAECgUIDAABNQAECgYIDgADAAAAAA==.',
['Sí']='Símbá:BAAANQAECgQIBgAAAA==.',
['Sø']='Sølari:BAAANQAECgEIAQAAAA==.',
Ta='Takerfan:BAABNQAECoEgAAIaAAgKVwyKRACzAQAaAAgKVwyKRACzAQAAAA==.Tallyblue:BAAANQAECgUIDgAAAA==.Tanarisfry:BAAANQAECgYICwAAAA==.Taserface:BAAANQADCgQJBwAAAA==.',
Te='Temüjin:BAABNQAECoEcAAIRAAgKuBenBwBDAgARAAgKuBenBwBDAgAAAA==.',
Th='Tharamore:BAAANQAECgQIAgABNQAECgUIBQADAAAAAA==.Theeonlyone:BAABNQAECoEcAAITAAgKahNNYwAMAgATAAgKahNNYwAMAgAAAA==.',
Ti='Tiberlock:BAAANQADCgQIBQAAAA==.Tioshadow:BAAANQAECgYIDQABNQAFFAMIBQAZAA4RAA==.Tiosombra:BAAANQADCggICAABNQAFFAMIBQAZAA4RAA==.Tiranii:BAAANQAECgYIEQAAAA==.Titannus:BAAANQAECgUICwABNQAECgYIDAADAAAAAA==.',
Tr='Tralisa:BAAANQADCgIIAgAAAA==.Tribalrage:BAAANQAECgQIDAAAAA==.',
Tu='Tuktu:BAAANQAECgQIBwAAAA==.',
Ty='Tymberh:BAAANQADCggIDgABNQAECgYIDAADAAAAAA==.',
Um='Umbraheart:BAEANQAECgEIAQABNQAECggIKQARANccAA==.',
Va='Vael:BAAANQAECgQIBAAAAA==.Vandal:BAABNQAECoEdAAQVAAkKjBP/GABmAgAVAAkKjBP/GABmAgAFAAYKngqPDgAuAQAGAAEK+wXM3AA/AAAAAA==.Varrigos:BAAANQADCgYIGgAAAA==.Vartence:BAAANQADCgIIAgAAAA==.',
Ve='Vega:BAAANQAECggICAAAAA==.',
Vo='Voltz:BAABNQAECoEVAAIdAAgKSA4ZZADEAQAdAAgKSA4ZZADEAQAAAA==.',
We='Wetbread:BAABNQAECoEcAAIWAAgKKhOYRwDSAQAWAAgKKhOYRwDSAQAAAA==.',
Wi='Wiind:BAABNQAECoEfAAIUAAkKGxIfFQBLAgAUAAkKGxIfFQBLAgAAAA==.',
Wo='Wolfbaine:BAAANQADCgIIAgAAAA==.',
Xa='Xalityr:BAAANQAECgEIAgABNQAECgYIDwADAAAAAA==.Xanaxos:BAAANQAECgEIAQAAAA==.Xanis:BAAANQADCgUIDgAAAA==.',
Xh='Xhaltrix:BAAANQABCgcIBwAAAA==.',
Xo='Xonz:BAABNQAECoEoAAIeAAkK9hwqDgCUAgAeAAkK9hwqDgCUAgAAAA==.',
Xu='Xuljin:BAAANQADCggICwABNQAFFAMIBQAZAA4RAA==.',
Yo='Yomamasez:BAAANQAECgYIEgAAAA==.',
Ze='Zethieran:BAAANQADCgMIAwAAAA==.',
Zh='Zhenith:BAABNQAECoEYAAMfAAcKsxOkFgDAAQAfAAcKsxOkFgDAAQAgAAEKiA5KIAAzAAABNQADCgcICQADAAAAAA==.',
Zi='Zippoo:BAAANQABCgIIAgAAAA==.Zirnbie:BAAANQAECgQICQAAAA==.',
Zo='Zoub:BAAANQAECgQIBAAAAA==.',
['Äc']='Ächilles:BAAANQADCgEIAQAAAA==.',
['Är']='Ärc:BAAANQABCgYICAAAAA==.',
['Ða']='Ðark:BAAANQADCgUIBgABNQAECgkJJwAOAD8gAA==.',
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
