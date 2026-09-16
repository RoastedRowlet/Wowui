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

local lookup = {'Unknown-Unknown','Warlock-Demonology','Shaman-Restoration','DeathKnight-Blood','Warlock-Destruction','Monk-Windwalker','Warrior-Fury','Evoker-Preservation','Evoker-Devastation','Warrior-Arms','Monk-Mistweaver','Mage-Frost','Mage-Arcane','Hunter-BeastMastery','Shaman-Elemental','Shaman-Enhancement','Druid-Balance','Rogue-Assassination','Paladin-Retribution','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Holy','Warrior-Protection','Monk-Brewmaster','Priest-Shadow','Priest-Holy','Priest-Discipline',}
local provider = {region='US',realm='AzjolNerub',name='US',type='weekly',zone=53,date='2026-09-15',data={Ad='Addy:BAAANQAECgUICQAAAA==.Adelethe:BAAANQADCgYIBgAAAA==.Aditu:BAAANQADCgMIAwAAAA==.',
Ae='Aestian:BAAANQAECgEIAQAAAA==.',
Ah='Ahhotep:BAAANQADCgEIAQAAAA==.',
Ai='Ailysely:BAAANQADCgUIDgAAAA==.Aispere:BAAANQADCgEIAQABNQADCgYIEAABAAAAAA==.',
Al='Alerzhulan:BAAANQAECgQIBgAAAA==.Aletheia:BAAANQADCggICAAAAA==.Alfurn:BAAANQADCgIIAgAAAA==.Aliveknightt:BAAANQADCggICAAAAA==.Alledria:BAAANQABCgUIBgAAAA==.Alorely:BAAANQAECgQIBgAAAA==.',
Am='Amanara:BAAANQAECgEIAQAAAA==.Amoonia:BAAANQADCgUICgAAAA==.',
An='Anciientpaw:BAAANQAECgcIEgAAAA==.Andrasomnius:BAAANQAECgQIBAAAAA==.Angbar:BAAANQAECgQIBAAAAA==.Anguirus:BAAANQAECgQICAAAAA==.Anuksunàmun:BAAANQADCgYIDAAAAA==.',
Aq='Aqulenas:BAAANQAECgEIAQAAAA==.',
Ar='Arakhan:BAAANQADCgYICAAAAA==.Arcadian:BAAANQAECgYIEQAAAA==.Arceeprime:BAAANQADCgcICQAAAA==.Arextheelder:BAAANQAECgEIAQAAAA==.Argentum:BAAANQADCggICAABNQAECgUICQABAAAAAA==.Armorscales:BAABNQAECoEdAAICAAkJ/x96CAAqAwACAAkJ/x96CAAqAwAAAA==.Arntraz:BAAANQAECgEIAQAAAA==.Arrabbiato:BAAANQAECgQIBAAAAA==.Arronaxx:BAAANQADCgYIEAAAAA==.Arçadia:BAAANQAECgIIAgAAAA==.',
As='Ashnikko:BAAANQADCgYIBgAAAA==.Ashtori:BAAANQABCgQIBgAAAA==.Astayoni:BAAANQADCgcIDQAAAA==.Asterfleur:BAAANQADCgYIBwABNQAECgQIBQABAAAAAA==.Astrine:BAAANQAECgcIDQAAAA==.',
At='Ataraxya:BAAANQAECgEIAQAAAA==.',
Au='Auberon:BAAANQAECgcIEQAAAA==.Aufta:BAAANQAECgQIBQAAAA==.Aumer:BAAANQABCggICwAAAA==.',
Az='Azi:BAAANQAFFAEIAQAAAA==.Azurite:BAAANQADCgYIDwAAAA==.',
Ba='Backpedal:BAAANQADCgcIEwAAAA==.Badankhadonk:BAABNQAECoEbAAIDAAkJuyJbAwCKAwADAAkJuyJbAwCKAwAAAA==.Bakkutteh:BAAANQABCgIIBAAAAA==.Balen:BAAANQAECgEIAQAAAA==.Bandersin:BAAANQADCgUIBQAAAA==.Bansheex:BAAANQADCgQIBAAAAA==.',
Be='Beefmuffinz:BAAANQAECgcIDgAAAA==.Beethozart:BAAANQADCgUICAAAAA==.Belcebu:BAAANQABCggIDgAAAA==.Belholy:BAAANQADCggIFAAAAA==.Bellafleur:BAAANQABCgYIDgABNQAECgQIBQABAAAAAA==.Bendeekay:BAABNQAECoEYAAIEAAkJ/R5JCQAjAwAEAAkJ/R5JCQAjAwAAAA==.Benilok:BAAANQAECgMIAwAAAA==.Bethgibbons:BAAANQADCgQIBQAAAA==.',
Bg='Bgpocalypse:BAAANQADCgYIBgAAAA==.',
Bl='Blackblood:BAAANQAECgQIBgAAAA==.Bloodache:BAAANQAECgQIBgAAAA==.Blux:BAAANQADCgYIBgAAAA==.',
Bo='Boil:BAAANQAECgQIBQAAAA==.Bonemarrow:BAAANQAECgIIAgAAAA==.',
Br='Brakeable:BAAANQADCgIIBAAAAA==.Braké:BAAANQAECgQIBgAAAA==.Brewskies:BAAANQAECgYICwAAAA==.Brightstar:BAAANQADCgUIBQAAAA==.Brionthicc:BAAANQAECgMIAwABNQAECggIHQAFALQeAA==.Brownington:BAAANQAECgYIDQAAAA==.Bruhilda:BAAANQAECgMIBAAAAA==.Brìonik:BAABNQAECoEdAAMFAAgJtB5hBQCgAgAFAAgJJB1hBQCgAgACAAMJ0hdTgQDsAAAAAA==.',
Bu='Bubbleroundi:BAAANQAECgYIDgAAAA==.Bubudder:BAAANQAECgYIDQAAAA==.Buffstuff:BAAANQAECgUIBgAAAA==.',
Ca='Caeviro:BAAANQAECgUICQAAAA==.Canadaishere:BAAANQADCgEIAQAAAA==.Cantheartitz:BAAANQAECgQICAAAAA==.Catdav:BAAANQADCggIGAAAAA==.',
Ch='Charbol:BAAANQADCgQIBAAAAA==.Chelraani:BAAANQAECgEIAQAAAA==.Chess:BAAANQAECgUIBQAAAA==.Chiichard:BAAANQADCgYICAAAAA==.Chunkamonk:BAAANQADCgQIBAAAAA==.',
Ci='Cigar:BAAANQADCgUICQABNQAECgYIEAABAAAAAA==.',
Cl='Clazzicola:BAABNQAECoEYAAIGAAkJkx7tBwDoAgAGAAkJkx7tBwDoAgAAAA==.',
Co='Combatwombat:BAAANQABCgEIAQAAAA==.Cowdeer:BAAANQAECgQIBgAAAA==.',
Cp='Cptncrush:BAAANQAECgQIBgAAAA==.',
Cr='Creamsickle:BAAANQABCgIIBAAAAA==.',
Cu='Cupcakes:BAAANQADCgYIDAAAAA==.Cutethulu:BAAANQAECgQICAAAAA==.',
Cy='Cydarr:BAAANQADCgQIBAAAAA==.Cyther:BAABNQAECoEdAAIHAAgJpyTnAABAAwAHAAgJpyTnAABAAwAAAA==.',
Da='Dadbodftw:BAAANQAECgMIBgAAAA==.Daddylight:BAAANQAECgMIAwAAAA==.Daelyn:BAAANQADCgYIAgAAAA==.Dakk:BAAANQADCggICAAAAA==.Darkdottie:BAAANQAECgQIBgAAAA==.Darkenstormy:BAAANQAECgEIAQAAAA==.Darkmage:BAAANQABCgYIBgAAAA==.',
De='Deadlight:BAAANQAECgYICgAAAA==.Deadtofall:BAAANQADCgYIDwAAAA==.Deathshikzs:BAABNQAECoEXAAIEAAYJbhkiKgDNAQAEAAYJbhkiKgDNAQAAAA==.Decix:BAAANQAECgIIAgABNQAFFAEIAQABAAAAAA==.Deity:BAAANQAECgIIAgABNQAECgMIBgABAAAAAA==.Demonllxll:BAAANQAECgQICQAAAA==.Demontime:BAAANQADCgMIAwAAAA==.Desolation:BAAANQAECgYICwAAAA==.Despia:BAAANQAECgEIAQAAAA==.Devastacia:BAAANQADCggICAAAAA==.',
Di='Dicot:BAAANQAECgEIAQAAAA==.Diety:BAAANQAECgMIBgAAAA==.Dimension:BAAANQAECgEIAQAAAA==.Disconnect:BAAANQABCgUIBwAAAA==.',
Dj='Djpallyd:BAAANQAECgcIDgAAAA==.',
Do='Doughy:BAAANQADCggIEAAAAA==.',
Dr='Dragonu:BAABNQAECoEZAAMIAAkJgRtxBQAPAwAIAAkJgRtxBQAPAwAJAAEJIQ3cKAA1AAAAAA==.Draktyr:BAABNQAECoEZAAMKAAgJ9hzfLwB/AgAKAAgJ9hzfLwB/AgAHAAEJLAYiHgAuAAAAAA==.Droody:BAAANQABCgIIAgAAAA==.',
El='Ellalais:BAAANQAECgQIBgAAAA==.Ellismom:BAAANQAECgYICwAAAA==.',
En='Enchanceurpp:BAAANQADCgYIBgAAAA==.End:BAAANQAECgIIAgAAAA==.',
Er='Ereithelda:BAABNQAECoEdAAILAAgJOyI3BAALAwALAAgJOyI3BAALAwAAAA==.Ericka:BAAANQADCgYIBwAAAA==.Erina:BAAANQABCggIDwAAAA==.Erowid:BAAANQADCggICwABNQAECgkJGQAIAIEbAA==.Errutu:BAAANQAECgYICwAAAA==.',
Ev='Evox:BAAANQADCgcIEgAAAA==.',
Fa='Fann:BAAANQAECgQIBgAAAA==.Fauna:BAAANQADCggICAAAAA==.',
Fe='Feathiir:BAAANQADCgEIAQAAAA==.Fewz:BAABNQAECoEdAAMMAAkJ4yLYAABHAwAMAAgJXiXYAABHAwANAAEJEA93KwFFAAAAAA==.',
Fl='Flakflap:BAAANQAECgUIBQABNQAECgkJHQAEAO4cAA==.Flakov:BAAANQADCggIDgABNQAECgkJHQAEAO4cAA==.Flaktop:BAABNQAECoEdAAIEAAkJ7hxWEAC/AgAEAAkJ7hxWEAC/AgAAAA==.Flatplate:BAAANQADCgUIBQAAAA==.Fler:BAAANQAECgQIBQAAAA==.',
Fo='Forbacon:BAAANQAECgMIBgAAAA==.Force:BAAANQAECgQIBgAAAA==.Fouris:BAAANQADCggICwAAAA==.',
Fr='Fridgie:BAABNQAECoEbAAIOAAgJNSIgFgDHAgAOAAgJNSIgFgDHAgAAAA==.Friggenmage:BAAANQAECgYICgAAAA==.Frostbitte:BAAANQADCgEIAQAAAA==.Frozenruby:BAAANQABCggIDQAAAA==.Frozenturtle:BAAANQAECgEIAQAAAA==.',
Ft='Ftwiamtank:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.',
Ga='Garcutt:BAABNQAECoEcAAINAAgJERoNSgBvAgANAAgJERoNSgBvAgAAAA==.',
Ge='Geddan:BAAANQADCgQIBgAAAA==.Genericpal:BAAANQAECgcIEQAAAA==.Geritol:BAAANQADCggICAAAAA==.',
Gi='Gichio:BAAANQAECgUIBQAAAA==.Ginrai:BAAANQADCgUIBQAAAA==.',
Gl='Gladstone:BAAANQAECgMIBQAAAA==.',
Gn='Gnawbear:BAEANQAECgMIBwAAAA==.',
Go='Goatassassin:BAAANQAECgQIBAAAAA==.Goatshifter:BAAANQAECgMIBAABNQAECgQIBAABAAAAAA==.',
Gr='Grayeyes:BAAANQADCgMIAwAAAA==.Greenngoblin:BAAANQAECgQIBQAAAA==.Grämps:BAAANQADCgYIBgAAAA==.',
Gu='Guino:BAAANQADCgYICwAAAA==.',
Gw='Gwenelly:BAAANQADCgYICQAAAA==.',
Ha='Hamnqueso:BAAANQADCgYICgAAAA==.Hardeesdelux:BAAANQADCgUICQABNQADCgcIGQABAAAAAA==.Hazis:BAABNQAECoEeAAIEAAgJTBt6FQCCAgAEAAgJTBt6FQCCAgAAAA==.',
Hi='Hinala:BAAANQAECgYIDgAAAA==.',
Ho='Holy:BAAANQAECgUIBQABNQAECgkJHQAPAMoYAA==.Holydad:BAAANQADCgcIBwAAAA==.Honeybutter:BAAANQAECggIEAAAAA==.Hordebreaker:BAAANQABCgIIAgAAAA==.',
Hu='Huesitos:BAAANQAECgQICQAAAA==.Huntzilla:BAAANQADCgYICwAAAA==.Huukend:BAAANQAECgYICQAAAA==.',
In='Inanitas:BAAANQADCggICAAAAA==.Innominot:BAAANQADCgUIBQAAAA==.',
Ja='Jackoldean:BAAANQADCgIIAgAAAA==.Jacques:BAAANQADCggICAAAAA==.Jadaveon:BAAANQAECgUIBQAAAA==.Jalene:BAAANQADCggIDQAAAA==.Jargen:BAAANQADCgQIBAABNQADCgQIBAABAAAAAA==.',
Je='Jettadari:BAAANQAECgYICgABNQAFFAEIAQABAAAAAA==.Jettadin:BAAANQAFFAEIAQAAAA==.',
Jw='Jwalker:BAAANQADCgQIBQAAAA==.',
['Jë']='Jëks:BAABNQAECoEdAAMDAAgJ2iCPFgCiAgADAAgJ2iCPFgCiAgAQAAQJ7QzLFgD5AAAAAA==.',
Ka='Kakozaps:BAABNQAECoEmAAMPAAkJIyBKEgDwAgAPAAgJxSBKEgDwAgAQAAQJHxu0EQBjAQAAAA==.Kallar:BAAANQAECgMIAwABNQAECgQIBgABAAAAAA==.Kayeera:BAAANQADCgcIDQAAAA==.Kaylrandi:BAAANQADCgIIBwAAAA==.Kayna:BAAANQAECgUIBQAAAA==.',
Ke='Kearza:BAAANQADCgYICgAAAA==.Keiyona:BAAANQADCgIIAgABNQAECgQICAABAAAAAA==.Kennethv:BAAANQAECgEIAQAAAA==.Keny:BAAANQAECgUIBgAAAA==.Kero:BAAANQADCgMIAwABNQAECgQIBgABAAAAAA==.Kev:BAAANQAECggIBAAAAA==.',
Kh='Khibanee:BAAANQADCgcIEwAAAA==.Khiell:BAAANQAECggIEgAAAA==.Khrominius:BAAANQAECgQIBQAAAA==.',
Ki='Kinigit:BAAANQAECgUIBQABNQAECgkJHQARAGYcAA==.Kirïtö:BAAANQADCgMIAwAAAA==.Kitaradin:BAAANQAECgUICgAAAA==.',
Kn='Knghtmre:BAABNQAECoEYAAINAAgJmA/naQAJAgANAAgJmA/naQAJAgAAAA==.',
Ko='Konpalitaa:BAAANQAECgEIAQAAAA==.',
Kr='Kragon:BAAANQADCggICAAAAA==.',
Ku='Kuranaa:BAAANQADCgYIEAAAAA==.Kurulak:BAAANQAECgYICwAAAA==.',
Ky='Kymru:BAAANQADCgYICQAAAA==.',
La='Lacerveza:BAAANQAECgEIAQAAAA==.Lahyanhou:BAAANQAECgEIAQAAAA==.Lawanorder:BAAANQADCggIBwAAAA==.',
Le='Leriope:BAAANQAECgYICwAAAA==.',
Li='Lichfiend:BAAANQADCgYICgAAAA==.Lihpfu:BAAANQAECgQICAABNQAECgYIEgABAAAAAA==.Lilem:BAAANQADCgIIAgAAAA==.',
Lj='Lj:BAAANQAECgYICwAAAA==.',
Lu='Luxure:BAAANQAECgEIAQAAAA==.',
Ma='Maegan:BAAANQADCgcIEwAAAA==.Mager:BAAANQAECgEIAQAAAA==.Mageshyte:BAABNQAECoEaAAINAAgJ2x27PwCUAgANAAgJ2x27PwCUAgAAAA==.Magolock:BAAANQAECgIIBAABNQAECgIIBAABAAAAAA==.Magus:BAAANQADCggICAAAAA==.Maidrim:BAABNQAECoEfAAISAAkJmCBtBQAQAwASAAkJmCBtBQAQAwAAAA==.Mamajumbo:BAAANQADCggIGQAAAA==.Mana:BAABNQAECoEdAAIPAAkJyhimFADXAgAPAAkJyhimFADXAgAAAA==.Marellias:BAAANQAECgYICAABNQAECggIFwATAOclAA==.Marikel:BAAANQADCgYICAAAAA==.Marlea:BAAANQAECgYIBgAAAA==.Maruka:BAAANQAECgUICQAAAA==.',
Me='Meletha:BAAANQADCggICAAAAA==.Metahorfasis:BAAANQADCgcIBwAAAA==.',
Mi='Michaelken:BAAANQAECgQIBQAAAA==.Midari:BAAANQADCgEIAQAAAA==.Mierin:BAAANQADCgUIBQAAAA==.Mierín:BAAANQAECgIIAgAAAA==.Migrains:BAAANQAECgUICgAAAA==.Milkmesloppy:BAAANQADCgYIBgABNQAECgkJHQACAP8fAA==.Miskaabin:BAAANQAECgMIAwAAAA==.Missdemon:BAAANQADCggICAAAAA==.',
Mo='Mojodaddy:BAAANQABCgQIBgAAAA==.Mojogreens:BAAANQADCgUIBQAAAA==.Monsart:BAAANQADCgMIAwAAAA==.Montura:BAAANQADCgQIBAAAAA==.Moonie:BAAANQADCgYICwAAAA==.Moonpetals:BAAANQADCgIIAgAAAA==.Moralizdormi:BAAANQAECgQICAAAAA==.',
Mp='Mpd:BAAANQAECgEIAQAAAA==.',
My='Mylendria:BAAANQABCgYIBwAAAA==.Mystique:BAAANQAECgQIBQAAAA==.',
['Mí']='Míerín:BAABNQAECoEbAAIOAAgJiyTGDAAXAwAOAAgJiyTGDAAXAwAAAA==.',
Na='Naama:BAAANQADCgEIAQAAAA==.Naelih:BAAANQADCggICwAAAA==.Natlès:BAAANQAECgMIAwAAAA==.Natzu:BAAANQAECgEIAQAAAA==.Naushan:BAAANQADCgIIAgAAAA==.Nazari:BAABNQAECoEYAAITAAkJgBInOQAZAgATAAkJgBInOQAZAgAAAA==.',
Ne='Necronu:BAAANQADCggICAABNQAECgkJGQAIAIEbAA==.',
Ni='Nikkolos:BAAANQADCgUIBQAAAA==.',
No='Nogusta:BAABNQAECoEcAAIKAAgJaBXaQgApAgAKAAgJaBXaQgApAgAAAA==.Notdecix:BAAANQAFFAEIAQAAAA==.',
Nu='Nuggets:BAAANQADCgYIEAAAAA==.',
Ob='Obyss:BAAANQADCgQIBAAAAA==.',
On='Onlyshams:BAAANQAECgYIBwAAAA==.',
Oo='Oorggtejedor:BAAANQADCgUIBQAAAA==.',
Or='Orondo:BAAANQADCgYIEQAAAA==.',
Os='Ospfiend:BAAANQADCgYIBgAAAA==.',
Ou='Oumura:BAAANQAECgQIBAAAAA==.',
Pa='Pallyoop:BAAANQAECgcIBwAAAA==.Patharok:BAAANQADCgMIAwABNQAECgQICQABAAAAAA==.Pathator:BAAANQADCgcIDQABNQAECgQICQABAAAAAA==.Patheros:BAAANQABCgUIBQABNQAECgQICQABAAAAAA==.Paxmansigh:BAAANQADCgcIGwAAAA==.',
Ph='Phantöm:BAAANQAECgYIEAAAAA==.',
Pl='Placcid:BAAANQAECgIIAwAAAA==.Planknstein:BAAANQAECgEIAQAAAA==.Plantoor:BAAANQAECgUICgAAAA==.',
Po='Pockett:BAAANQADCgQIBAAAAA==.Ponarp:BAAANQAECgQIBgAAAA==.Porkchop:BAAANQAECgYICwAAAA==.',
Pr='Prismclaw:BAAANQAECgYICwAAAA==.Processing:BAABNQAECoEdAAIRAAgJqR+XFgCfAgARAAgJqR+XFgCfAgAAAA==.',
Pu='Puddleheal:BAAANQADCgcIGQAAAA==.Puffdamagic:BAAANQAECgYIDwAAAA==.',
Pw='Pwnstarz:BAAANQADCgYIEQAAAA==.',
Py='Pyous:BAAANQADCgUICgAAAA==.',
Qp='Qplus:BAAANQAECgQIBgAAAA==.',
Qu='Quaenie:BAAANQAECgQIBgAAAA==.Quintin:BAAANQADCggIEQAAAA==.',
Ra='Ragetotem:BAAANQADCgIIAgAAAA==.Ragewarg:BAAANQAECgEIAQAAAA==.Raginsteel:BAAANQADCgYICwAAAA==.Ralvarr:BAAANQAECgIIAgAAAA==.Rayleigh:BAAANQAECgEIAQABNQADCgMIAwABAAAAAA==.',
Re='Redchord:BAAANQAECgEIAQAAAA==.Regidør:BAAANQAFFAEIAQAAAA==.Relik:BAAANQAECgQIBgAAAA==.',
Ri='Rilliccine:BAAANQADCgYIBgAAAA==.Rilliguine:BAAANQADCgQIBAAAAA==.Rillinetti:BAAANQAECgQIBQAAAA==.Rillini:BAAANQAECgIIAgAAAA==.Rilliti:BAAANQADCgYICwAAAA==.Risky:BAAANQADCgIIAgABNQADCgcIEwABAAAAAA==.Rivertam:BAAANQADCggICAAAAA==.',
Ro='Robotnik:BAAANQAECgIIAQAAAA==.Rogu:BAAANQADCgYIEAAAAA==.Rondon:BAAANQAECgEIAQAAAA==.Rookdh:BAABNQAECoEcAAIUAAgJGB6LDQCyAgAUAAgJGB6LDQCyAgAAAA==.Rosey:BAAANQAECgQIBQAAAA==.Royale:BAAANQAECgQIBgAAAA==.',
Ru='Rudyeightbal:BAAANQADCgYIBgAAAA==.Rum:BAAANQADCggIFAAAAA==.Rustedbarrel:BAAANQAECgUIBwAAAA==.',
Sa='Saelyres:BAAANQAECgEIAQAAAA==.Sagesse:BAAANQADCggIDgAAAA==.Samifleur:BAAANQAECgQIBQAAAA==.Sammy:BAAANQAECgQIBgAAAA==.Santaclaaws:BAABNQAECoEfAAMVAAkJsx+UDADQAgAVAAgJISCUDADQAgAUAAIJ4hrMPgCbAAAAAA==.Santafuego:BAAANQADCgYIBgABNQAECgkJHwAVALMfAA==.Santapal:BAABNQAECoEZAAMWAAgJjxxbEwDGAgAWAAgJjxxbEwDGAgATAAEJBAQV9wAsAAABNQAECgkJHwAVALMfAA==.Saphotic:BAAANQAECgcICwABNQAFFAEIAQABAAAAAA==.Sayvil:BAAANQAECgQIBgAAAQ==.',
Se='Semmers:BAAANQAECgMIBQAAAA==.Sensational:BAAANQAECgIIAgAAAA==.Septiria:BAAANQADCgcIDQAAAA==.Sergio:BAAANQADCgQIBAAAAA==.Seyren:BAAANQADCgQIBAAAAA==.',
Sh='Shalash:BAAANQADCgYIBgABNQAECggIFwASALIaAA==.Shamadeano:BAAANQADCgcIFgAAAA==.Shamanshikz:BAAANQAECgIIAwAAAA==.Shamiska:BAAANQADCgcIEgAAAA==.Shampooh:BAAANQADCgcIEwAAAA==.Shamrockk:BAAANQADCggICAAAAA==.Shaokhan:BAAANQAECgYICwAAAA==.Sharazzy:BAAANQAECgEIAQAAAA==.Sharpcukuee:BAAANQAECgEIAQAAAA==.Shian:BAAANQAECgEIAQAAAA==.Shieldee:BAAANQAECgUICAAAAA==.Shikzzs:BAAANQAECgQICAAAAA==.Shockeei:BAABNQAECoEXAAINAAkJdiHuDQB1AwANAAkJdiHuDQB1AwAAAA==.Shortdon:BAAANQADCgEIAQAAAA==.Shortebus:BAAANQADCgcIDQAAAA==.',
Si='Sighh:BAAANQADCgEIAQAAAA==.Sijth:BAABNQAECoEZAAMWAAcJSBToMgDzAQAWAAcJSBToMgDzAQATAAQJZw/zngDPAAAAAA==.Silvereyes:BAAANQABCgYIBQAAAA==.Silverwar:BAAANQAECgQIBgAAAA==.Simmune:BAEBNQAECoEdAAIWAAgJhx+yDQD8AgAWAAgJhx+yDQD8AgAAAA==.Six:BAAANQADCggICAAAAA==.Sixior:BAAANQAECgQIBgAAAA==.Sixpath:BAAANQADCgQIAgAAAA==.Sixs:BAAANQADCggICAAAAA==.',
Sk='Skepti:BAAANQAECgQIBgAAAA==.Skreep:BAAANQADCgUIBQAAAA==.',
Sl='Slybiscuit:BAAANQAECgMIBAAAAA==.',
Sm='Smeeta:BAAANQAECgUIDAAAAA==.',
Sn='Sneakerbaby:BAAANQADCgYIBgAAAA==.',
So='Soram:BAAANQADCgYIBgAAAA==.Sourdevil:BAAANQABCgIIBAAAAA==.Soùl:BAAANQADCggIHgAAAA==.',
Sp='Spike:BAAANQADCgcIDwAAAA==.',
St='Starlara:BAAANQABCgYICAAAAA==.Stazz:BAAANQAECgUICgAAAA==.Steelerayne:BAAANQAECgEIAQAAAA==.Stonecrab:BAAANQAECgcIDQAAAA==.Stormcontrol:BAAANQAECgUICAAAAA==.Stormii:BAAANQADCgcIDAAAAA==.Stormtotem:BAAANQADCgUIBwAAAA==.Strangerdk:BAAANQAECgQIBQAAAA==.Styless:BAAANQABCgYIBwAAAA==.Stðne:BAAANQADCgMIAwAAAA==.',
Sv='Svenraiden:BAAANQABCgEIAQAAAA==.',
Sw='Swagboyxx:BAAANQADCgQIBAAAAA==.Swishersweet:BAAANQAECgYIDwAAAA==.Swordfish:BAAANQADCgcICgAAAA==.',
Sy='Sybrooke:BAAANQADCgYIDAAAAA==.Syrinne:BAAANQADCgEIAQAAAA==.',
Ta='Tabrieus:BAAANQAECgYICwAAAA==.Taegia:BAAANQADCgUIBQABNQAECggIHQALADsiAA==.Talanth:BAAANQAECgQIBQAAAA==.Talbott:BAAANQADCgEIAQAAAA==.Tarrisx:BAAANQADCgEIAQABNQAECgUIDAABAAAAAA==.Tayon:BAAANQAECgEIAQAAAA==.Tayvin:BAAANQADCgEIAQAAAA==.',
Te='Termana:BAABNQAECoEdAAIXAAgJeyVuAQBtAwAXAAgJeyVuAQBtAwAAAA==.',
Th='Thassa:BAAANQADCgEIAQAAAA==.Thatsmypurse:BAAANQADCggICAAAAA==.Theodoró:BAAANQAECgUIBQAAAA==.Thug:BAAANQADCgcIFQAAAA==.',
Ti='Tiferet:BAAANQAECgQIBgAAAA==.Tigiw:BAAANQADCgYICgAAAA==.Tinysunshine:BAAANQAECgIIAgAAAA==.Tinyt:BAAANQADCgMIAwAAAA==.Titonatty:BAAANQABCgQIBAAAAA==.',
To='Tolenkar:BAAANQAECgQIBgAAAA==.Tomato:BAAANQAFFAEIAQAAAA==.Torfelori:BAAANQAECgMIAwAAAA==.Torvalar:BAAANQAECgYICwAAAA==.Tove:BAAANQAECgQIBQAAAA==.',
Tr='Trûth:BAAANQAECggIBwAAAA==.',
Tu='Turdyl:BAAANQAECgcIDwAAAA==.',
Ty='Tyfelsion:BAAANQAECgEIAQAAAA==.Tyrelline:BAAANQAECgIIAgAAAA==.Tystrolf:BAAANQADCggICAAAAA==.',
['Tá']='Tárris:BAAANQADCgcIBwABNQAECgUIDAABAAAAAA==.',
['Tô']='Tôx:BAAANQAECgYIDwAAAA==.',
Um='Umbranwings:BAAANQAECgQIBAAAAA==.',
Un='Unheardjp:BAAANQADCgMIBQAAAA==.',
Ur='Ursus:BAAANQAECgQIBgAAAA==.',
Va='Vaerix:BAAANQAECgEIAQAAAA==.Valydrin:BAAANQAECgQIBgAAAA==.',
Ve='Vexadrine:BAABNQAECoEeAAIYAAgJQB2CBACjAgAYAAgJQB2CBACjAgAAAA==.',
Vy='Vysis:BAABNQAECoEZAAQZAAkJjBNdEABjAgAZAAkJjBNdEABjAgAaAAUJOhclSABjAQAbAAMJTQz8DQDIAAABNQADCggIGgABAAAAAA==.',
We='Weebdestroya:BAAANQADCgIIAgAAAA==.',
Wh='Whisperfål:BAAANQADCgIIAgAAAA==.',
Wi='Wickèr:BAAANQAECgQICAAAAA==.Wieldblade:BAAANQAECgYIDAAAAA==.',
Wu='Wunderbar:BAAANQAECgEIAQAAAA==.',
Wy='Wyldfire:BAABNQAECoEdAAIRAAkJZhypDQAMAwARAAkJZhypDQAMAwAAAA==.',
Xa='Xanith:BAAANQADCgYIBgAAAA==.',
Yi='Yia:BAAANQAECgIIBAAAAA==.Yilnara:BAAANQAECgEIAQAAAA==.',
Ys='Ysa:BAAANQAECgYIDQAAAA==.',
Za='Zarich:BAAANQAECgUICQAAAA==.',
Ze='Zekkun:BAAANQADCggICAAAAA==.',
Zo='Zoga:BAEANQADCgUIBQABNQAECgQIBgABAAAAAA==.Zogah:BAEANQADCgQIBAABNQAECgQIBgABAAAAAA==.Zoganian:BAEANQAECgEIAQABNQAECgQIBgABAAAAAA==.',
Zu='Zullthornp:BAAANQADCgUICQAAAA==.',
['Æb']='Æbony:BAAANQABCgIIAgAAAA==.',
['Év']='Évélýn:BAAANQADCgUIBQAAAA==.',
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
