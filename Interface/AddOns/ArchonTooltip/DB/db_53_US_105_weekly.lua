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

local lookup = {'Unknown-Unknown','Evoker-Devastation','Evoker-Augmentation','DeathKnight-Frost','Warrior-Arms','Paladin-Retribution','Shaman-Elemental','Shaman-Restoration','Mage-Arcane','DemonHunter-Devourer','Paladin-Protection','Hunter-BeastMastery','Shaman-Enhancement','Evoker-Preservation','Warlock-Demonology','DeathKnight-Unholy','Monk-Windwalker','Priest-Shadow','Warrior-Fury','Hunter-Survival','Hunter-Marksmanship','DeathKnight-Blood','Warlock-Destruction','DemonHunter-Havoc','DemonHunter-Vengeance',}
local provider = {region='US',realm='Garrosh',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aadolin:BAAANQAECgcIDQAAAA==.',
Ac='Acamar:BAAANQADCgYIDgAAAA==.',
Ad='Adeleska:BAAANQAECgUIBwAAAA==.Aderina:BAAANQADCgIIAgAAAA==.Adessa:BAAANQAECgYICQAAAA==.',
Ae='Aellibash:BAAANQADCgIIAgABNQAECgQIBgABAAAAAA==.Aenivath:BAAANQADCgUICAAAAA==.Aeovina:BAAANQABCgcICQAAAA==.',
Ag='Agnergam:BAAANQADCgcIBwAAAA==.Agorath:BAAANQADCgYIBgAAAA==.',
Ai='Aisatsana:BAAANQADCgQIBgAAAA==.',
Al='Alexstrasz:BAAANQAECgMIBAAAAA==.Alopex:BAAANQAECgQICAAAAA==.',
Am='Amaellara:BAAANQAECgUICQAAAA==.Amajiki:BAAANQADCgYIAwAAAA==.',
An='Annorah:BAAANQADCgEIAQAAAA==.Anthathein:BAAANQADCgUICAAAAA==.',
Ao='Aoda:BAAANQAECgEIAQAAAA==.Aotrom:BAAANQAECgEIAQAAAA==.',
Ar='Archblade:BAAANQAECgMIBAAAAA==.Armagnac:BAAANQAECgcIEgAAAA==.Arthias:BAAANQADCgEIAQAAAA==.',
As='Asroldal:BAAANQADCgYIBgAAAA==.',
At='Atem:BAAANQABCgIIAgAAAA==.Atom:BAAANQADCgYIBAAAAA==.',
Au='Aufare:BAAANQAECgEIAgAAAA==.',
Av='Avarya:BAAANQAECgYIDwAAAA==.Averagesham:BAAANQAECggIDQABNQAFFAYICwACAOIgAA==.Averagevoker:BAACNQAFFIELAAMCAAYJ4iCKAAD9AQACAAUJpSKKAAD9AQADAAEJEhhXAwBmAAA1AAQKgR8AAwIACQnGJccAALsDAAIACQnGJccAALsDAAMAAQkuH/QQAFoAAAAA.Averwine:BAAANQADCgYICAAAAA==.',
Ba='Babynimyk:BAAANQAECgIIAgAAAA==.Backyard:BAAANQADCgYIDAAAAA==.Bael:BAAANQAECgMIAwAAAA==.Balooi:BAAANQABCgYICQAAAA==.Baraxius:BAAANQABCgEIAQAAAA==.Bashtaz:BAAANQAECggICAABNQAFFAQIBwAEANcbAA==.Basixx:BAAANQAECgEIAQAAAA==.Bayleaf:BAAANQAECgUIDAABNQAFFAYICwACAOIgAA==.',
Bb='Bbeloree:BAAANQAECgEIAQAAAA==.',
Be='Bearykyns:BAAANQAECgYICwAAAA==.Beastwarden:BAAANQAECgUICwAAAA==.Beatrixkiddo:BAAANQADCgYIBgAAAA==.Bejay:BAAANQADCgYIBgABNQAECgcICQABAAAAAA==.Belladar:BAAANQADCgMIAwAAAA==.Belokk:BAAANQABCgcIBwAAAA==.Bemused:BAAANQAECgEIAQAAAA==.Benpai:BAAANQAECgEIAQAAAA==.Besticle:BAABNQAECoEcAAIFAAkJXx02FwAPAwAFAAkJXx02FwAPAwAAAA==.',
Bi='Bigcheddarz:BAAANQADCgMIAwAAAA==.Bigchungass:BAAANQADCgYIBgABNQAECgkJFwAGAPklAA==.Bigttgothgf:BAAANQAECgUIBAAAAA==.Bilberry:BAAANQABCgQICAAAAA==.Binkie:BAAANQADCgcIEwABNQAECgQIBgABAAAAAA==.',
Bj='Bjaculator:BAAANQAECgcICQAAAA==.',
Bl='Blackgranite:BAAANQADCggICAABNQAECgEIAwABAAAAAA==.Blacklotus:BAAANQAECgIIAgAAAA==.Blayze:BAAANQADCgYIBgAAAA==.Blep:BAAANQAECgUICAAAAA==.Bloodoath:BAAANQADCgEIAQABNQAECggIGgAHADgSAA==.Blueheal:BAAANQADCgUICwAAAA==.Bluemilk:BAAANQAECgEIAQAAAA==.Blueshiver:BAAANQAECgEIAQAAAA==.',
Bo='Bombadore:BAAANQADCgYIBgAAAA==.Bonesaw:BAAANQADCgIIAgABNQAECgQIBQABAAAAAA==.Booktök:BAAANQAECgIIAgABNQAECgUICwABAAAAAA==.Bowlinder:BAABNQAECoEaAAMHAAgJuCHqDAArAwAHAAgJuCHqDAArAwAIAAgJORZJKQAgAgAAAA==.Boyvine:BAAANQAECgQIBAAAAA==.',
Br='Brahmana:BAAANQABCgQICQAAAA==.Braldar:BAAANQAECgIIAgAAAA==.Branas:BAAANQADCggIEAAAAA==.Braxiss:BAAANQAECgYIEAAAAA==.Brilin:BAAANQAECgUICgAAAA==.Brithio:BAAANQADCgMIAQAAAA==.Broguë:BAAANQAECgEIAQAAAA==.Brokton:BAAANQADCgQIBAAAAA==.Brucarus:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Brueld:BAAANQADCgMIAwABNQAECggIGgAHADgSAA==.',
Bu='Bulldozzers:BAAANQADCgUIBQAAAA==.Bullshzitt:BAAANQAECggIAQAAAA==.Bumper:BAAANQADCgcIBwAAAA==.Busin:BAAANQADCgYIDgAAAA==.',
['Bî']='Bîllydakîd:BAAANQADCgYIBgAAAA==.',
Ca='Calabag:BAAANQAECgMIAwABNQAECgYIDwABAAAAAA==.Calabloom:BAAANQAECgYIDwAAAA==.Caland:BAAANQADCgIIAgAAAA==.Calibern:BAAANQADCggIEgAAAA==.Calmm:BAAANQAECgMIAwABNQAECgkJFwAGAPklAA==.Canthndice:BAAANQADCgcIEQAAAA==.Capncrunchh:BAAANQADCgYIBwAAAA==.Catraxa:BAAANQADCgYIBgAAAA==.Cavalina:BAAANQAECgUIEgAAAA==.Cavick:BAAANQAECgIIAwAAAA==.Cawnor:BAAANQAECgMIBAAAAA==.Caótica:BAAANQADCggICgAAAA==.',
Ce='Celyanar:BAAANQADCgMIAgABNQAECgQIBAABAAAAAA==.Ceradwyn:BAAANQADCgYIDQAAAA==.',
Ch='Charön:BAABNQAECoEgAAIJAAkJqR+rHQAgAwAJAAkJqR+rHQAgAwAAAA==.Cheezewizard:BAAANQADCgEIAQAAAA==.Chentrocka:BAABNQAECoEfAAIJAAkJOh6aGwAqAwAJAAkJOh6aGwAqAwAAAA==.Chillberto:BAAANQADCggIDwAAAA==.Chiselin:BAAANQAECgQIBAAAAA==.',
Cl='Clankss:BAAANQADCggIDAAAAA==.Clerikyns:BAAANQADCgcIBwABNQAECgYICwABAAAAAA==.Clicks:BAAANQADCgMIAwAAAA==.Clics:BAAANQADCggICAAAAA==.',
Co='Coalgrim:BAAANQAECgQICwAAAA==.Cosmíc:BAAANQAECgEIAQAAAA==.',
Cp='Cptbyakuya:BAABNQAECoEfAAIGAAkJTyNYBQChAwAGAAkJTyNYBQChAwAAAA==.',
Cr='Craterbip:BAAANQAECgUIBQAAAA==.Crimsonk:BAAANQABCgIIAgAAAA==.',
Cu='Curoconcum:BAAANQADCgYIBwAAAA==.',
Cy='Cyrub:BAAANQADCgUICwAAAA==.',
Da='Dabrinto:BAAANQADCgYIBgAAAA==.Daedrian:BAAANQAECgEIAQAAAA==.Dallena:BAAANQAECgQIBwABNQAECgUIBAABAAAAAA==.Dankweaver:BAAANQAECgUICgAAAA==.Daratri:BAAANQADCgYIBgAAAA==.Darktales:BAAANQADCgYIBgAAAA==.Darthxander:BAAANQADCgYIDwAAAA==.Daywrecker:BAAANQAECgMIBQAAAA==.Dayyman:BAAANQAECgYIEQAAAA==.Dazuk:BAAANQADCgYIBgAAAA==.',
De='Deathlysham:BAAANQADCgIIAgAAAA==.Deathshroom:BAAANQADCgYIDwAAAA==.Deathsun:BAAANQAECgcICQAAAA==.Deform:BAAANQAECgUIBQAAAA==.Deianaera:BAAANQADCgQIBAAAAA==.Delldestus:BAAANQAECgEIAQAAAA==.Demonics:BAAANQADCgYIBgAAAA==.Demonstix:BAAANQAECgIIAwAAAA==.Demv:BAAANQADCgIIAgAAAA==.Depressa:BAAANQADCgQIBAABNQAECgcICQABAAAAAA==.Dernius:BAAANQADCggIEQAAAA==.Despairykyns:BAAANQADCgYICQABNQAECgYICwABAAAAAA==.Dethbringa:BAAANQAECgYIDgAAAA==.Dewfall:BAAANQAECgcIEwAAAA==.Deylithdreyn:BAAANQADCggICAAAAA==.',
Dh='Dhuoth:BAAANQAECgYIDwAAAA==.',
Di='Diagoraz:BAAANQADCgUIBwAAAA==.Dialtone:BAAANQADCgQIBwAAAA==.Dialtonee:BAAANQADCgMIAwABNQADCgQIBwABAAAAAA==.Digitalbäth:BAAANQADCgUIBQAAAA==.Digoshadow:BAAANQAECgIIAgAAAA==.Dillonharper:BAAANQADCggICAAAAA==.Disgruntld:BAAANQADCgcICgAAAA==.Disturbd:BAAANQADCgQIBQABNQAECgUICAABAAAAAA==.Ditdoo:BAAANQADCgYICwAAAA==.',
Dk='Dkmetcàlf:BAAANQADCggICAAAAA==.',
Do='Donkeymonk:BAAANQAECgEIAQAAAA==.Dorkyspork:BAAANQAECgEIAQAAAA==.',
Dr='Dragonis:BAAANQADCggICAAAAA==.Dravenstone:BAAANQADCgIIAgAAAA==.Dreamerzz:BAAANQADCgYIBwAAAA==.Drovac:BAAANQAECgEIAQAAAA==.Druidxd:BAAANQADCgQIBAAAAA==.Drumittz:BAAANQADCgEIAQAAAA==.Drworm:BAABNQAECoEcAAIEAAgJ1hkKDgBvAgAEAAgJ1hkKDgBvAgAAAA==.Drääko:BAAANQABCgUICwAAAA==.Drêdd:BAAANQABCgIIAgAAAA==.',
Ds='Dsonic:BAAANQADCgQIBAAAAA==.',
Du='Dubbies:BAAANQAECgIIAgAAAA==.Durtluz:BAAANQADCgcICAAAAA==.Dustandblood:BAAANQADCgMIAgAAAA==.',
Dy='Dyrim:BAAANQADCgUICwAAAA==.',
['Dæ']='Dæmonkawlr:BAAANQADCgQIBAAAAA==.',
['Dê']='Dêformjr:BAAANQAECgYIDwAAAA==.Dêvarim:BAAANQABCgQIBAAAAA==.',
['Dë']='Dëformjr:BAAANQADCgYIBgAAAA==.Dëförmjr:BAAANQAECgQIBAAAAA==.',
['Dú']='Dúbletap:BAAANQADCgYIBgAAAA==.',
Eh='Ehvie:BAAANQADCggICAABNQAECgYIDwABAAAAAA==.',
El='Elbrujo:BAAANQABCgcICgAAAA==.Elenii:BAAANQAECgYIDQAAAA==.Eleynra:BAAANQADCgIIAgAAAA==.Elybear:BAAANQADCgUIBQAAAA==.Elychan:BAAANQADCgYIBgAAAA==.Elygance:BAAANQADCggICAAAAA==.Elÿ:BAAANQAECggIDAAAAA==.',
Em='Emptyside:BAAANQADCggIFAAAAA==.',
En='Enchorxxi:BAAANQAECgIIAgAAAA==.Enetrenazara:BAAANQAECgIIAgAAAA==.Eniar:BAAANQADCgUIBQABNQAECgMIAwABAAAAAA==.Eniaro:BAAANQAECgMIAwAAAA==.Enlonger:BAAANQAECgcIEgAAAA==.',
Ep='Epicgooner:BAAANQAECgUICAAAAA==.',
Er='Erahm:BAAANQADCgUIBQAAAA==.Erahmm:BAAANQAECgIIAgAAAA==.Ergaraskreia:BAAANQADCgIIAgAAAA==.Erielia:BAAANQADCgIIAgABNQADCgYICAABAAAAAA==.',
Es='Esmirelda:BAAANQAECgQIBQAAAA==.Essn:BAABNQAECoEkAAIKAAkJHiZlAAD3AwAKAAkJHiZlAAD3AwAAAA==.',
Eu='Eulune:BAEANQADCggIFwABNQAECgcIDAABAAAAAA==.',
Ev='Evelynna:BAAANQADCggIFAAAAA==.',
Ex='Exsull:BAAANQAECgQIBAAAAA==.',
Fa='Faible:BAAANQABCgQIBAAAAA==.Faithwarrior:BAAANQAECgIIAgAAAA==.Falk:BAAANQAECgEIAQAAAA==.Falron:BAABNQAECoGfAAILAAgJmyUgBAAVAwALAAgJmyUgBAAVAwAAAA==.Fathlia:BAAANQAECgQICQAAAA==.',
Fe='Fezzjin:BAAANQAECgIIAwAAAA==.',
Fi='Filbrust:BAAANQADCgIIAgAAAA==.Fishtanked:BAAANQADCgQIBgAAAA==.Fitzofrage:BAAANQADCgYIBwAAAA==.',
Fl='Flashlights:BAAANQADCgYICQABNQAECgIIAgABAAAAAA==.Fleshbiter:BAAANQADCggIDgAAAA==.Flowingdeath:BAAANQADCgYICQAAAA==.Flowingrage:BAAANQADCgYIBgABNQADCgYICQABAAAAAA==.',
Fm='Fmjserval:BAAANQAECgEIAQAAAA==.',
Fo='Fomtoolery:BAAANQABCgUIBQAAAA==.Foot:BAAANQAECgcIEwAAAA==.Forcefaith:BAAANQAECgYICwAAAA==.',
Fr='Freduardo:BAAANQADCgUIBgAAAA==.Freva:BAAANQAECgQIBgAAAA==.Friarfox:BAAANQADCgYIBgABNQAECgQIBgABAAAAAA==.Frostfiree:BAAANQADCgcICAABNQAECggIGgAHADgSAA==.Fruitpuddle:BAAANQABCgEIAQAAAA==.Frøsty:BAAANQADCgEIAQAAAA==.',
Fu='Furlock:BAAANQADCgYICQAAAA==.Furryhugger:BAAANQAECgIIBAAAAA==.Furstab:BAAANQADCgQIBwAAAA==.',
['Fì']='Fìzzypop:BAAANQADCgEIAQAAAA==.',
Ga='Galepalm:BAAANQAECgQIBAAAAA==.Gambriniss:BAAANQAECgEIAQAAAA==.Gamea:BAAANQAECgUICwAAAA==.Garloch:BAAANQADCgcIBwAAAA==.Gazrosh:BAAANQADCgcIFwABNQAECgMIAwABAAAAAA==.',
Ge='Geladra:BAAANQADCgcIBwABNQAECgYIEAABAAAAAA==.Gemmothy:BAAANQADCgMIBQAAAA==.',
Gi='Gibbychona:BAAANQAECggIEQAAAA==.',
Gl='Glowshroom:BAAANQADCgEIAQABNQADCgYIDwABAAAAAA==.',
Go='Golotak:BAAANQADCgcIBwAAAA==.Gonnagetproc:BAAANQADCggICAAAAA==.Googale:BAAANQADCgIIAgAAAA==.Gordoc:BAAANQADCggIFwAAAA==.Gothboy:BAAANQADCggICAAAAA==.',
Gr='Graff:BAAANQAECgIIAwAAAA==.Grailed:BAAANQADCgEIAQAAAA==.Gratiana:BAAANQADCgQIBAAAAA==.Gravem:BAAANQADCgUIBQAAAA==.Gravie:BAAANQADCgIIAgAAAA==.Graystaf:BAAANQAECgEIAQAAAA==.Greggorie:BAAANQAECgEIAQAAAA==.Grennan:BAAANQADCggIDQAAAA==.Greyowl:BAAANQADCggIEAAAAA==.Grifflez:BAAANQAECgIIAwAAAA==.Grumpli:BAAANQAECgYICwAAAA==.',
Gu='Guytheshower:BAAANQAECgQIBQAAAA==.',
Gw='Gweilo:BAAANQAECgUIBQAAAA==.',
Ha='Habek:BAAANQADCgQIBQAAAA==.Hamadaver:BAAANQABCgQIBwAAAA==.Handofblood:BAAANQAECgMIBAAAAA==.Handymandy:BAAANQAECgcIBwABNQAECgkJFwAGAPklAA==.Harderrock:BAAANQADCgEIAQABNQAECgYICAABAAAAAA==.Hardrockgirl:BAAANQAECgMIAwABNQAECgYICAABAAAAAA==.Harmonechi:BAAANQAECgYIDgAAAA==.Haveasip:BAAANQAECgIIAgAAAA==.',
He='Healdealer:BAAANQADCgQIBAAAAA==.Healmonbello:BAAANQAECgYICAAAAA==.Healystix:BAAANQAECgEIAQABNQAECgIIAwABAAAAAA==.Hellzcrusade:BAAANQAECgIIAgAAAA==.Henchi:BAAANQADCgIIAgABNQADCgUIDQABAAAAAA==.',
Hi='Higherheal:BAAANQADCgMIAwAAAA==.',
Ho='Hodesh:BAAANQADCgMIAwAAAA==.Holypuuss:BAABNQAECoEXAAMGAAkJ+SVhBgCRAwAGAAkJRiNhBgCRAwALAAEJEyVOMQBsAAAAAA==.Honeybumms:BAAANQAECgQIBwAAAA==.Hopeslayer:BAAANQADCgcIDAABNQAECgYIDwABAAAAAA==.Hoplitedruid:BAAANQAECgUICgAAAA==.Houndoom:BAAANQADCgYICgAAAA==.',
Ht='Htiál:BAAANQADCgIIAgAAAA==.Htiâl:BAAANQADCgIIAgABNQADCgIIAgABAAAAAA==.',
Hu='Huntko:BAAANQADCggIEgAAAA==.',
Hy='Hyperthymia:BAAANQAECggIEwAAAA==.Hyrakka:BAAANQAECgEIAQABNQADCgUIDQABAAAAAA==.',
Ic='Iceeveins:BAAANQADCggICAAAAA==.Icystyx:BAAANQAECgIIAwAAAA==.',
Il='Ilyamurometz:BAAANQAECgcIEAAAAA==.',
Im='Immorta:BAAANQAECgcIEAAAAA==.',
In='Indigokiya:BAAANQAECgQIBAAAAA==.Influencer:BAAANQADCgcIBwAAAA==.Ingesteel:BAAANQADCgEIAQAAAA==.Inodoro:BAAANQAECgYICgAAAA==.',
Io='Iordgodplaya:BAAANQADCgcIDwAAAA==.',
Ir='Irabmal:BAAANQAECgcIEwAAAA==.Iriclaw:BAABNQAECoEgAAIMAAkJViZwAAD5AwAMAAkJViZwAAD5AwAAAA==.Ironpanda:BAAANQADCgEIAQAAAA==.',
Is='Isothymia:BAAANQAECgUIBgABNQAECggIEwABAAAAAA==.',
It='Itsmepip:BAAANQAECgMIAwAAAA==.',
Ja='Jacoby:BAAANQAECgUIBQABNQAECgkJIQANAEUkAA==.Jadefires:BAAANQADCgYIDgABNQADCggIGAABAAAAAA==.Jadelite:BAAANQADCggIGAAAAA==.Janddasham:BAAANQAECgYIDQAAAA==.Janddavoker:BAABNQAECoEhAAIOAAkJcCAtAwBOAwAOAAkJcCAtAwBOAwAAAA==.Jarnbrez:BAAANQADCgMIAwAAAA==.Jawnwick:BAAANQADCgMIAwAAAA==.Jaxo:BAAANQAECgIIAgABNQAECgUIDQABAAAAAA==.',
Jh='Jherri:BAAANQAECgIIAgAAAA==.',
Ji='Jimbeamer:BAAANQAECgEIAQAAAA==.',
Jk='Jkm:BAAANQAECgEIAgAAAA==.',
Jo='Joanexotic:BAAANQAECgIIBAAAAA==.Joetothemama:BAAANQADCgYIBgAAAA==.Jojolion:BAAANQAECgEIAgAAAA==.',
Jr='Jrocmfka:BAAANQAECgQIBQAAAA==.',
Jt='Jtama:BAAANQADCgUIBwAAAA==.',
Ju='Junefyre:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Juntor:BAAANQADCgcIBwAAAA==.',
Ka='Kaeliin:BAAANQADCgcIBwAAAA==.Kage:BAAANQADCgQIBgAAAA==.Kaiderten:BAAANQADCgYICAAAAA==.Kailo:BAAANQAECgEIAQAAAA==.Kal:BAAANQADCgUICwAAAA==.Kalorondir:BAAANQABCgUIBwAAAA==.Kamila:BAAANQADCggIDAAAAA==.Kaorí:BAAANQAECgUIBgAAAA==.Karatekyns:BAAANQADCgIIAgABNQAECgYICwABAAAAAA==.Kaselian:BAAANQAECgIIAgAAAA==.Kattara:BAAANQAECgcIDAAAAA==.Kayalanii:BAAANQADCggICAAAAA==.Kazuhla:BAAANQAECgQIBgAAAA==.',
Ke='Keiryn:BAAANQAECgIIAgAAAA==.Kentyrakka:BAAANQAECgIIAgAAAA==.',
Kh='Khaotikpyre:BAACNQAFFIEGAAIJAAQJwgZyCwArAQAJAAQJwgZyCwArAQA1AAQKgRoAAgkACQlZGV47AKQCAAkACQlZGV47AKQCAAAA.',
Ki='Kiffypoo:BAAANQAECgEIAQAAAA==.Kil:BAAANQAECgcIEgAAAA==.Kiljaiden:BAAANQABCgIIAgAAAA==.Kiltree:BAAANQADCgIIAgABNQAECgcIEgABAAAAAA==.Kisho:BAAANQADCgMIAwAAAA==.Kiyoshie:BAAANQAECgYIDwAAAA==.',
Kl='Klanky:BAAANQADCggICAAAAA==.',
Kn='Kn:BAAANQAECgIIAgAAAA==.',
Ko='Kodiakpax:BAAANQADCgQIBAAAAA==.Kontroll:BAEANQADCggIFQAAAA==.Kookee:BAABNQAECoEcAAIPAAgJSxrqIgBgAgAPAAgJSxrqIgBgAgAAAA==.Korice:BAAANQAECgUICgAAAA==.',
Kr='Krypticgrip:BAAANQAECgcIDAABNQAFFAQIBgAJAMIGAA==.',
Ku='Kumaa:BAAANQAECgMIAwAAAA==.',
Ky='Kyle:BAAANQAECgEIAgAAAA==.Kylidon:BAAANQADCgYIBgAAAA==.Kynlauriana:BAAANQADCgEIAQAAAA==.',
La='Lalaind:BAAANQADCgYICAAAAA==.Larissa:BAAANQAECgQIBgAAAA==.Lathillea:BAAANQAECgEIAQAAAA==.Launchpad:BAAANQADCgQIBAAAAA==.Lazzirus:BAAANQAECgYICwAAAA==.',
Le='Leedict:BAAANQAECgQIBQAAAA==.Leerøy:BAAANQAECgQIBgAAAA==.Leilani:BAAANQADCgYIDQAAAA==.Leinalei:BAAANQADCggICAABNQAECgcIDQABAAAAAA==.Lessii:BAEBNQAECoEaAAIQAAgJsRo+FwCMAgAQAAgJsRo+FwCMAgAAAA==.',
Li='Lidande:BAAANQADCgYIBgAAAA==.Lidarcis:BAAANQAECgYICgAAAA==.Liedora:BAAANQADCgUIBgAAAA==.Lightpraiser:BAAANQAECgIIAwAAAA==.Limjahey:BAAANQADCggIEAAAAA==.Linra:BAAANQAECgUICAAAAA==.Littlefatt:BAAANQAECgYICwAAAA==.',
Ll='Llich:BAAANQAECgIIAgAAAA==.',
Lu='Luassei:BAAANQADCgMIBQAAAA==.Lucishifts:BAAANQAECgcIDgAAAA==.Lucîan:BAAANQADCggIGgAAAA==.Lumaris:BAAANQADCgcIBwAAAA==.Lunamorr:BAAANQADCgYIBgAAAA==.Luphoe:BAAANQADCgUIBQAAAA==.',
Ly='Lyserra:BAAANQAECgEIAgAAAA==.Lyudmila:BAAANQADCgYIBgABNQADCggIDAABAAAAAA==.',
Ma='Mabell:BAAANQADCgEIAQAAAA==.Maddawggamin:BAAANQADCgQIBAAAAA==.Maekar:BAAANQADCgYIBwAAAA==.Mafi:BAAANQADCgMIAwAAAA==.Magenos:BAAANQAECgQIBAAAAA==.Magic:BAAANQADCgUIBQAAAA==.Magicpants:BAAANQAECgEIAQAAAA==.Magobiga:BAAANQADCgYICAAAAA==.Mahrx:BAABNQAECoEfAAIRAAkJESVGAgCVAwARAAkJESVGAgCVAwAAAA==.Malaricia:BAAANQABCgQIBAAAAA==.Mawaru:BAAANQAECgEIAQAAAA==.Maxanadu:BAAANQADCgUICgAAAA==.',
Me='Meatpipe:BAAANQAECgEIAQAAAA==.Medarela:BAAANQAECgMIAwAAAA==.Meeke:BAABNQAECoEcAAISAAkJpyCiBABjAwASAAkJpyCiBABjAwAAAA==.Mell:BAABNQAECoEYAAIGAAkJARyaFwDjAgAGAAkJARyaFwDjAgAAAA==.Melmin:BAAANQAECgMIBQAAAA==.Meroman:BAAANQADCgUICwAAAA==.Metamora:BAAANQAECgIIAgAAAA==.Meuria:BAAANQAECgIIAgAAAA==.',
Mi='Midgetlord:BAABNQAECoEaAAIGAAkJNSLYCwBNAwAGAAkJNSLYCwBNAwAAAA==.Miklos:BAAANQADCgYICwAAAA==.Misstearly:BAAANQADCgYIBgAAAA==.',
Mo='Moneebagz:BAAANQADCggIGwAAAA==.Montblanc:BAAANQADCggICAAAAA==.Moonem:BAAANQAECgUIDgAAAA==.Moosteerious:BAEANQADCggICAABNQADCggIFQABAAAAAA==.Mossacre:BAABNQAECoESAAMFAAcJTBg8SQAPAgAFAAcJTBg8SQAPAgATAAEJrAl4HQAxAAAAAA==.Mossherder:BAAANQABCgEIAQAAAA==.',
['Mé']='Méta:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.',
Na='Naanda:BAAANQABCgcICwAAAA==.Nachopapa:BAAANQADCgYICgAAAA==.Nalorspace:BAAANQADCgYIEQAAAA==.Naniwa:BAAANQAECgcIDgAAAA==.Narwail:BAAANQAECgIIBAAAAA==.Narweil:BAAANQADCgUIBQABNQAECgIIBAABAAAAAA==.Narwhall:BAAANQADCgYICwABNQAECgIIBAABAAAAAA==.Nasathen:BAAANQAECgEIAQABNQAECgQIBgABAAAAAA==.Natanus:BAAANQADCgUICwAAAA==.Natsuko:BAAANQADCgMIAwAAAA==.Nazaric:BAAANQAECgUICAAAAA==.Nazaricksm:BAAANQADCgMIAwABNQAECgUICAABAAAAAA==.Nazgeul:BAAANQADCgYICwAAAA==.',
Nb='Nbi:BAAANQABCgQIBQABNQAECgQIBAABAAAAAA==.',
Ne='Necrodik:BAAANQADCgQIBAAAAA==.Neladris:BAAANQADCgIIAgAAAA==.Nelagorn:BAAANQADCgIIAgAAAA==.Nemesís:BAAANQABCgYIBwAAAA==.Neohorn:BAAANQAECgEIAQAAAA==.Neomyk:BAAANQADCggIDgAAAA==.Neoptolemus:BAAANQADCgUICwAAAA==.Neoqled:BAAANQADCgYICAAAAA==.Neorhon:BAAANQADCgUIBQAAAA==.Nerclopse:BAABNQAECoEaAAIHAAgJOBLYKwAeAgAHAAgJOBLYKwAeAgAAAA==.Neverender:BAAANQAECgEIAQAAAA==.Nexian:BAAANQABCgQIBgAAAA==.',
Ni='Niarwodahs:BAAANQAECgIIAgAAAA==.Niaryci:BAAANQAECgQIBQAAAA==.Nightfangz:BAAANQADCgYIDAAAAA==.Nims:BAAANQADCgQIBAAAAA==.',
No='Noritotem:BAAANQAECgUIBQAAAA==.Note:BAAANQADCgUICQAAAA==.Notec:BAAANQADCggIAQAAAA==.Notics:BAAANQAECgIIAgAAAA==.Novacainê:BAAANQADCggIEAAAAA==.',
Nu='Nuff:BAAANQADCgQIBAAAAA==.Nuikai:BAAANQAECgQICAAAAA==.Nukum:BAAANQADCgQIBQAAAA==.',
Ob='Obsidiansun:BAAANQAECgQIBwAAAA==.',
Oc='Octame:BAAANQADCggIGQAAAA==.',
Ol='Olethvia:BAAANQADCgMIAwABNQAECgQIBAABAAAAAA==.',
On='Onlylight:BAAANQADCggICAAAAA==.',
Oo='Oororoe:BAAANQADCgUIBQAAAA==.',
Op='Opalescence:BAAANQADCgYIEwAAAA==.Optional:BAABNQAECoEbAAIUAAkJYCU2AADPAwAUAAkJYCU2AADPAwAAAA==.',
Or='Orgargo:BAAANQADCggIDgAAAA==.',
Os='Osley:BAAANQADCgMIBgAAAA==.',
Ou='Oule:BAEANQAECgcIDAAAAA==.',
Pa='Pallorx:BAAANQADCgQIBAAAAA==.Palpatiné:BAAANQADCgQIBAAAAA==.Paluoth:BAAANQADCgEIAQAAAA==.Pandasennin:BAAANQADCgUICwAAAA==.Papachains:BAAANQADCgYIDAABNQAECggIAQABAAAAAA==.Papashootin:BAAANQAECggIAQAAAA==.Paperplate:BAAANQAECgcIEgAAAA==.Paradox:BAAANQAECgcIEAAAAA==.Pattyhealsu:BAABNQAECoEbAAIIAAkJeSAYCAA3AwAIAAkJeSAYCAA3AwAAAA==.Pawlyn:BAAANQADCgEIAQAAAA==.',
Pe='Peachizz:BAAANQAECgEIAQAAAA==.Pelivarondo:BAABNQAECoEhAAMUAAcJDRvZAgBLAgAUAAcJDRvZAgBLAgAMAAIJTgjHtABpAAAAAA==.Pelizandeth:BAAANQADCggIHAABNQAECgcIIQAUAA0bAA==.Pepegas:BAAANQADCggIFwAAAA==.Pestillia:BAAANQAECgQIBgAAAA==.',
Ph='Phoffynax:BAAANQADCggIGgAAAA==.Phundip:BAAANQADCgMIBgABNQAECgIIAwABAAAAAA==.',
Pi='Pistolbeat:BAAANQADCgUIBQAAAA==.',
Pk='Pkthunder:BAAANQADCgUIBQAAAA==.',
Pl='Playful:BAAANQADCggIDgAAAA==.Plopopotamus:BAAANQAECgYICQAAAA==.',
Po='Poedanrin:BAAANQADCggICAAAAA==.Polikarp:BAAANQABCgQIBwAAAA==.Pookìe:BAAANQAECgMIBAAAAA==.Poorsol:BAAANQAECgIIAwAAAA==.',
Ps='Psyko:BAAANQADCgMIAwABNQADCggICAABAAAAAA==.',
Qu='Quickbrown:BAAANQAECgEIAgAAAA==.',
Ra='Ragenel:BAAANQADCgYIBgAAAA==.Rahxe:BAAANQADCggIFgAAAA==.Raikz:BAAANQAECgIIAgAAAA==.Raiyne:BAAANQADCggIDwAAAA==.Randolphus:BAAANQAECgMIAwABNQAECgMIBAABAAAAAA==.Rateddz:BAAANQAECgEIAQAAAA==.Rats:BAABNQAECoEgAAIKAAkJoR5FBwAyAwAKAAkJoR5FBwAyAwAAAA==.Ratshield:BAAANQAECgUIBQABNQAECgkJIAAKAKEeAA==.',
Re='Rendis:BAAANQADCgIIAgAAAA==.Reno:BAAANQAECgQIBQAAAA==.Reurog:BAAANQAECgMIBQAAAA==.Revanjmt:BAAANQADCgYIBAAAAA==.',
Rh='Rhakudu:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.',
Ri='Rian:BAABNQAECoEZAAIVAAkJuSK0AgCOAwAVAAkJuSK0AgCOAwABNQAFFAYICAAJAJgUAA==.Rigbee:BAAANQABCgIIAgAAAA==.Ritalia:BAAANQAECgcIDgAAAA==.',
Rm='Rmnieech:BAAANQAECgEIAQAAAA==.',
Ro='Roadiee:BAAANQADCgYIEAAAAA==.Roadiex:BAAANQADCgIIAwAAAA==.Roadkyll:BAAANQAECgEIAQAAAA==.Ronynn:BAAANQADCgEIAQAAAA==.Rosamoon:BAAANQADCgYICgAAAA==.Rosilyn:BAAANQAECgUIBQAAAA==.',
Ru='Rurrick:BAAANQAECgEIAQAAAA==.',
Ry='Ryzee:BAAANQAFFAEIAQAAAA==.',
['Rå']='Råinè:BAAANQADCgcIBwABNQAECgMIAwABAAAAAA==.',
Sa='Sahmash:BAAANQADCgIIAgAAAA==.Salara:BAAANQAECgUICQAAAA==.Salasong:BAAANQADCgYICwAAAA==.Saltytoast:BAAANQAECgEIAQAAAA==.Sambda:BAAANQADCgYIBwABNQADCggIDAABAAAAAA==.Sambraicho:BAAANQADCggIDAAAAA==.Samburai:BAAANQADCgQIBQABNQADCggIDAABAAAAAA==.Samuella:BAAANQAECgUICQAAAA==.Sandrinea:BAAANQAECgIIAgAAAA==.Sarinya:BAAANQADCgYIBgAAAA==.Sauceym:BAAANQABCgUIBQAAAA==.Saytens:BAAANQAECggICAAAAA==.',
Sc='Scargiver:BAAANQADCgEIAQAAAA==.Scarllett:BAAANQAECgIIAwABNQAECgIIBAABAAAAAA==.Scarykyns:BAAANQADCgYIBgABNQAECgYICwABAAAAAA==.Schatzi:BAAANQADCggICAAAAA==.Scrubmage:BAAANQADCggICwAAAA==.',
Se='Secondwall:BAAANQAECgQIBAAAAA==.Sedale:BAAANQAECgQIBAAAAA==.Seesdeline:BAAANQADCgUIAgABNQADCgYIBgABAAAAAA==.Seilene:BAAANQADCgYIFQABNQADCggIGAABAAAAAA==.Selisi:BAAANQAECgQIBAABNQAECgUIBQABAAAAAA==.Senddra:BAAANQABCgYICAAAAA==.Seo:BAAANQAECgIIAgAAAA==.Seraf:BAABNQAECoEbAAMQAAkJGyRYBQB9AwAQAAkJqiFYBQB9AwAWAAUJsBjKNwB5AQAAAA==.Serafain:BAAANQAECgEIAQABNQAECgkJGwAQABskAA==.',
Sh='Shadowerise:BAAANQADCgUIBQAAAA==.Shaforgold:BAAANQAECgcIEAAAAA==.Shalazard:BAAANQADCggIFAAAAA==.Shamananana:BAAANQADCgYIBgAAAA==.Sharrina:BAAANQABCgEIAQAAAA==.Shibal:BAAANQAECgQIBQAAAA==.Shinystepdad:BAAANQADCgUIBQAAAA==.Shotorock:BAAANQADCggIGgAAAA==.Shrekismydad:BAAANQADCgQIBAAAAA==.Shroompie:BAAANQADCgYIBgABNQADCgYIDwABAAAAAA==.Shroomshock:BAAANQADCgYICQABNQADCgYIDwABAAAAAA==.Shushumen:BAAANQAECgQICQAAAA==.Shänk:BAAANQABCggIEAAAAA==.',
Si='Sicknezz:BAAANQADCgYICwABNQAECggICQABAAAAAA==.Sidewinder:BAAANQAECgQIBQABNQAECgkJGwAUAGAlAA==.Siinyster:BAAANQADCgMIAwAAAA==.Sikmode:BAAANQAECgIIAwAAAA==.Sildrusil:BAAANQADCgEIAQAAAA==.Sindari:BAAANQAECgUICwAAAA==.Sinturio:BAAANQAECgMIAwAAAA==.Sipsy:BAAANQAECgEIAgAAAA==.',
Sk='Skarg:BAAANQAECgMIBwAAAA==.Skyeashe:BAAANQADCgYIEgAAAA==.',
Sl='Sleezytease:BAAANQADCgcIBwAAAA==.Slimdusty:BAAANQADCgQICAAAAA==.Slingblades:BAAANQAECggICQAAAA==.Slobbrknckr:BAAANQADCgcIBwABNQAECgkJFwAGAPklAA==.Slowmo:BAAANQAECggICAAAAA==.',
Sm='Smittles:BAAANQAECgIIAwAAAA==.',
Sn='Sneakystix:BAAANQADCgYIBgABNQAECgIIAwABAAAAAA==.',
So='Sootclaw:BAAANQADCgYICQAAAA==.Sophus:BAAANQAECgEIAgAAAA==.Soren:BAAANQADCgYIBgAAAA==.Sorenko:BAAANQAECgEIAQABNQADCgYIBgABAAAAAA==.',
Sp='Spagooter:BAABNQAECoEVAAMPAAgJZR0IIwBfAgAPAAcJPh4IIwBfAgAXAAEJdRcZVQBEAAAAAA==.Sparklepants:BAABNQAECoEVAAIJAAgJkh/kLgDVAgAJAAgJkh/kLgDVAgAAAA==.Spencerz:BAAANQADCgEIAQAAAA==.Speyesee:BAAANQAECgMIBgAAAA==.Splashydank:BAAANQADCggIFAAAAA==.Spookyish:BAAANQAECgQIBQAAAA==.',
Sq='Squidstens:BAAANQABCgMIAwAAAA==.',
St='Stabbydank:BAAANQADCgcIDQAAAA==.Stackss:BAAANQAECgEIAQAAAA==.Stonedninja:BAAANQADCgIIAQAAAA==.Stonemason:BAAANQAECgEIAQAAAA==.Stoneskin:BAAANQADCgQIBAAAAA==.Strawberymik:BAAANQADCgEIAQAAAA==.',
Su='Submisive:BAAANQADCgcIDgAAAA==.Supe:BAAANQAECgEIAQAAAA==.',
Sw='Swagruid:BAAANQAECgQIBgAAAA==.Swampslinger:BAAANQAECgMIBQAAAA==.Swordlady:BAAANQAECgUICQABNQAECgYIDQABAAAAAA==.',
Sy='Syntari:BAAANQAECgQIBgAAAA==.Syntyr:BAAANQADCgMIAwAAAA==.Synyra:BAAANQADCgcIBwAAAA==.Synìk:BAAANQADCgUICgAAAA==.',
['Sö']='Söma:BAAANQAECgIIAwAAAA==.',
Ta='Taktixxloxx:BAAANQABCgMIAwAAAA==.Talenalat:BAAANQAECgEIAgAAAA==.Tankerbelle:BAAANQADCgEIAQAAAA==.Tannarisse:BAAANQADCgQIBQAAAA==.Taymatt:BAAANQAECgEIAgAAAA==.Tazstinko:BAAANQAECgUICAABNQAECggIHAAEANYZAA==.',
Te='Teaveen:BAAANQADCgIIAgAAAA==.Tectonic:BAAANQAECgYIDAABNQAFFAEIAQABAAAAAA==.Tejasgeek:BAAANQAECgEIAgAAAA==.Tenleron:BAAANQABCgMIAgAAAA==.Tenntoes:BAAANQADCgYIBgAAAA==.',
Th='Thegoob:BAAANQABCgMIAwAAAA==.Theiceflare:BAAANQADCgYICQAAAA==.Themuffinman:BAAANQAECgEIAQAAAA==.Theworrirawr:BAAANQAECgYIEAAAAA==.Thour:BAAANQABCgMIAgAAAA==.Thur:BAAANQAECgQIBgAAAA==.Thänatos:BAAANQAECgIIAgAAAA==.',
Ti='Tiesci:BAAANQAECgcIDQAAAA==.Tinyclash:BAAANQADCgQIBAAAAA==.Tinypap:BAAANQADCggIFwAAAA==.Tippe:BAAANQADCggIGAAAAA==.',
Tl='Tlálocx:BAAANQAECgEIAQAAAA==.',
To='Toastedblade:BAAANQAECgMIAwAAAA==.Toldyousoul:BAAANQAECgEIAQAAAA==.Tonytots:BAAANQAECgQIBAAAAA==.Tottemakk:BAAANQADCgEIAQAAAA==.Toughshots:BAAANQADCgEIAQAAAA==.Toxenima:BAAANQAECgMIAwAAAA==.Toxiciti:BAAANQAECgQIBgAAAA==.',
Tr='Tramlaw:BAAANQADCgIIAgAAAA==.Trashedara:BAAANQADCgUIBQAAAA==.Treebirth:BAAANQAECggIEwAAAA==.Treyu:BAAANQADCgYIBgAAAA==.Triegh:BAAANQAECgMIAwAAAA==.Troyano:BAAANQADCgQIBAAAAA==.Trunder:BAAANQAECgIIAwAAAA==.',
Ts='Tsaindorcus:BAAANQAECgQIDgAAAA==.Tsunamyz:BAAANQADCgIIBQAAAA==.',
Tu='Tuskgwel:BAAANQADCgIIAQAAAA==.',
Ty='Tyfoon:BAAANQABCgIIAgAAAA==.',
Ud='Uders:BAAANQAECgEIAQAAAA==.',
Uh='Uhlvar:BAAANQAECgYICgAAAA==.Uhm:BAABNQAECoETAAIFAAkJhB/BDwBJAwAFAAkJhB/BDwBJAwAAAA==.',
Ui='Uil:BAEANQAECgEIAQABNQAECgcIDAABAAAAAA==.',
Ul='Ultramad:BAAANQAECgUIBgAAAA==.Ultramellow:BAAANQAECgEIAQABNQAECgUIBgABAAAAAA==.',
Un='Unclesquid:BAAANQADCggIEwAAAA==.Unholydubzzy:BAAANQADCgEIAQAAAA==.',
Up='Upngo:BAAANQAECggIDwAAAA==.',
Ur='Urotherdaddy:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.',
Us='Uskthyr:BAAANQADCgUICQAAAA==.',
Va='Vanakin:BAAANQAECgQIBAABNQAFFAYIDAAYAKsbAA==.Vandredor:BAACNQAFFIEMAAIYAAYJqxuBAABUAgAYAAYJqxuBAABUAgA1AAQKgRsAAxgACQmkIEEKAOsCABgACQl1IEEKAOsCABkABglaHJMFAOcBAAAA.Vastatio:BAAANQADCgEIAQAAAA==.Vasträ:BAAANQADCgUICwAAAA==.',
Ve='Velicelia:BAAANQAECgUICwAAAA==.Vesroth:BAAANQAECgQIBAAAAA==.',
Vi='Viborge:BAAANQADCggIEAAAAA==.View:BAAANQAECgYIEAAAAA==.Vince:BAAANQADCggIGAAAAA==.Vissra:BAAANQADCgUIBQAAAA==.',
Vu='Vulpermon:BAAANQADCgMIBAAAAA==.Vuly:BAAANQADCgEIAQAAAA==.',
['Vä']='Vääko:BAAANQAECgEIAQAAAA==.',
['Ví']='Vínce:BAAANQADCgIIAgAAAA==.',
Wa='Warbaby:BAAANQADCgYIBgAAAA==.Warlarren:BAAANQADCgEIAQAAAA==.',
We='Weatherr:BAAANQAFFAMIAwAAAA==.Weki:BAAANQADCggIDAAAAA==.',
Wh='Whippoorwill:BAAANQAECgYIDwAAAA==.Whiskyslayer:BAAANQAECgYICQAAAA==.',
Wi='Wickeda:BAAANQAECgMIAwAAAA==.Williamp:BAAANQADCgYICgAAAA==.',
Wn='Wntlmd:BAAANQAECgMIBQAAAA==.',
Wo='Wolfnacht:BAAANQAECgEIAQAAAA==.',
Wu='Wukangmei:BAAANQADCgMIAwAAAA==.',
['Wà']='Wàrødør:BAAANQAECgQIBQAAAA==.',
Xe='Xene:BAAANQAECgQIEgAAAA==.',
Xh='Xhade:BAAANQADCgIIAgABNQADCggIGAABAAAAAA==.',
Xr='Xriss:BAAANQADCgYIDgAAAA==.Xrs:BAAANQADCgQIBAAAAA==.',
Ya='Yanedin:BAAANQAECgcIEgAAAA==.Yathrr:BAAANQADCgYICwAAAA==.',
Yo='Yorforger:BAAANQAECgQIBAABNQAECgcIDgABAAAAAA==.Youngbj:BAAANQAECgEIAQABNQAECgcICQABAAAAAA==.Younger:BAAANQAECgEIAgAAAA==.Youngerxx:BAAANQADCgYIBgAAAA==.',
Ys='Yserene:BAAANQADCgcIBwAAAA==.',
Yu='Yukonícus:BAAANQADCgYIBgABNQAECggIEQABAAAAAA==.Yukonïcus:BAAANQAECggIEQAAAA==.Yumm:BAAANQADCgcIBwAAAA==.Yuridemo:BAAANQAECgcIDAAAAA==.',
['Yè']='Yènnefer:BAAANQADCgYICAAAAA==.',
Za='Zaldrena:BAAANQADCgYIBgAAAA==.Zanotgaming:BAAANQADCgcIBwAAAA==.Zaraydorine:BAAANQADCgUIBQAAAA==.',
Zb='Zbrickashaw:BAAANQAECgMIAwAAAA==.',
Ze='Zelrin:BAABNQAECoEZAAIJAAkJHBeQRgB7AgAJAAkJHBeQRgB7AgAAAA==.Zenthalion:BAAANQAECgEIAQAAAA==.',
Zi='Zippee:BAAANQADCgQIBAAAAA==.',
Zo='Zobi:BAAANQADCgMIAwAAAA==.Zoomhunt:BAAANQAECgYICwABNQAFFAEIAQABAAAAAA==.Zoommage:BAAANQAFFAEIAQAAAA==.',
Zu='Zuluugargorg:BAAANQAECgQIBgAAAA==.',
Zy='Zyrun:BAAANQADCgQIBAAAAA==.',
['Ãd']='Ãdaria:BAAANQADCgIIAgAAAA==.',
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
