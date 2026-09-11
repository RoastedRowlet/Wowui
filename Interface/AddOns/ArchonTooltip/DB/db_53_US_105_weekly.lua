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

local lookup = {'Unknown-Unknown','Evoker-Devastation','Evoker-Augmentation','DeathKnight-Frost','Mage-Arcane','Paladin-Retribution','DemonHunter-Devourer','Paladin-Protection','Hunter-BeastMastery','Evoker-Preservation','Monk-Windwalker','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','DemonHunter-Havoc','DemonHunter-Vengeance',}
local provider = {region='US',realm='Garrosh',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aadolin:BAAANQAECgUIBgAAAA==.',
Ac='Acamar:BAAANQADCgQICAAAAA==.',
Ad='Adeleska:BAAANQAECgQIBAAAAA==.Aderina:BAAANQADCgIIAgAAAA==.Adessa:BAAANQAECgYICQAAAA==.',
Ae='Aellibash:BAAANQADCgIIAgABNQAECgQIBgABAAAAAA==.Aenivath:BAAANQADCgQIBAAAAA==.Aeovina:BAAANQABCgYIBwAAAA==.',
Ag='Agnergam:BAAANQADCgcIBwAAAA==.',
Ai='Aisatsana:BAAANQADCgQIBgAAAA==.',
Al='Alexstrasz:BAAANQABCgIIAgAAAA==.Alopex:BAAANQAECgIIBAAAAA==.',
Am='Amaellara:BAAANQAECgMIBAAAAA==.',
An='Anthathein:BAAANQADCgUICAAAAA==.',
Ao='Aoda:BAAANQAECgEIAQAAAA==.Aotrom:BAAANQAECgEIAQAAAA==.',
Aq='Aqualina:BAAANQADCgQIBAAAAA==.',
Ar='Archblade:BAAANQAECgEIAQAAAA==.Armagnac:BAAANQAECgYICwAAAA==.Arthias:BAAANQADCgEIAQAAAA==.',
As='Asroldal:BAAANQADCgYIBgAAAA==.',
At='Atem:BAAANQABCgIIAgAAAA==.',
Au='Aufare:BAAANQAECgEIAQAAAA==.',
Av='Avarya:BAAANQAECgYICwAAAA==.Averagesham:BAAANQAECgcICgABNQAECgkJHAACAMQlAA==.Averagevoker:BAABNQAECoEcAAMCAAkJxCVvAADVAwACAAkJxCVvAADVAwADAAEJLh9JDABeAAAAAA==.Averwine:BAAANQADCgYICAAAAA==.',
Ba='Babynimyk:BAAANQADCggICAAAAA==.Backyard:BAAANQADCgYIBgAAAA==.Bael:BAAANQAECgIIAgAAAA==.Balooi:BAAANQABCgYICQAAAA==.Baraxius:BAAANQABCgEIAQAAAA==.Bashtaz:BAAANQAECgEIAQABNQAECgkJGwAEAJQkAA==.Basixx:BAAANQADCgIIAgAAAA==.Bayleaf:BAAANQAECgQICQABNQAECgkJHAACAMQlAA==.',
Be='Bearykyns:BAAANQAECgQIBQAAAA==.Beastwarden:BAAANQAECgQIBgAAAA==.Beatrixkiddo:BAAANQADCgYIBgAAAA==.Beautyschool:BAAANQAECgcIEQAAAA==.Bejay:BAAANQADCgYIBgABNQAECgUIBgABAAAAAA==.Belladar:BAAANQADCgMIAwAAAA==.Bemused:BAAANQAECgEIAQAAAA==.Benpai:BAAANQAECgEIAQAAAA==.Besticle:BAAANQAECgcIEAAAAA==.',
Bi='Bigcheddarz:BAAANQADCgMIAwAAAA==.Bigchungass:BAAANQADCgYIBgABNQAECggIEAABAAAAAA==.Bigttgothgf:BAAANQAECgQIAwAAAA==.Bilberry:BAAANQABCgQIBQAAAA==.Binkie:BAAANQADCgYIDAABNQAECgIIAgABAAAAAA==.',
Bj='Bjaculator:BAAANQAECgUIBgAAAA==.',
Bl='Blackgranite:BAAANQADCggICAABNQAECgEIAwABAAAAAA==.Blep:BAAANQAECgIIAwAAAA==.Blueheal:BAAANQADCgQIBgAAAA==.Bluemilk:BAAANQAECgEIAQAAAA==.Blueshiver:BAAANQADCggIFAAAAA==.',
Bo='Bombadore:BAAANQADCgYIBgAAAA==.Bonesaw:BAAANQADCgIIAgABNQADCgcIBwABAAAAAA==.Bowlinder:BAAANQAFFAEIAQAAAA==.Boyvine:BAAANQADCggIFQAAAA==.',
Br='Braldar:BAAANQADCgYICwAAAA==.Branas:BAAANQADCggIEAAAAA==.Braxiss:BAAANQAECgYICgAAAA==.Brilin:BAAANQAECgQIBQAAAA==.Brithio:BAAANQADCgMIAQAAAA==.Broguë:BAAANQADCgcIEgAAAA==.Brokton:BAAANQADCgQIBAAAAA==.Brueld:BAAANQABCgUIBgABNQAECgYIDQABAAAAAA==.',
Bu='Bullshzitt:BAAANQAECggIAQAAAA==.Busin:BAAANQADCgYICgAAAA==.',
['Bî']='Bîllydakîd:BAAANQADCgYIBgAAAA==.',
Ca='Calabag:BAAANQADCgYIBgABNQAECgYICwABAAAAAA==.Calabloom:BAAANQAECgYICwAAAA==.Caland:BAAANQADCgIIAgAAAA==.Calibern:BAAANQADCgcICgAAAA==.Calmm:BAAANQAECgMIAwABNQAECggIEAABAAAAAA==.Canthndice:BAAANQADCgcIDQAAAA==.Capncrunchh:BAAANQADCgEIAQAAAA==.Cavalina:BAAANQAECgQICAAAAA==.Cavick:BAAANQAECgEIAQAAAA==.Cawnor:BAAANQAECgEIAQAAAA==.Caótica:BAAANQADCgMIAgAAAA==.',
Ce='Celyanar:BAAANQADCgMIAgABNQAECgQIBAABAAAAAA==.Ceradwyn:BAAANQADCgUIBwAAAA==.',
Ch='Charön:BAABNQAECoEXAAIFAAkJThxiGgD4AgAFAAkJThxiGgD4AgAAAA==.Chentrocka:BAAANQAECgcIEQAAAA==.Chillberto:BAAANQADCggIDwAAAA==.Chiselin:BAAANQADCgcICQAAAA==.',
Cl='Clankss:BAAANQADCgQIBAAAAA==.Clerikyns:BAAANQADCgcIBwABNQAECgQIBQABAAAAAA==.Clicks:BAAANQADCgMIAwAAAA==.',
Co='Coalgrim:BAAANQAECgMIBgAAAA==.Cosmíc:BAAANQADCgYIEQAAAA==.',
Cp='Cptbyakuya:BAABNQAECoEWAAIGAAgJih80CwAMAwAGAAgJih80CwAMAwAAAA==.',
Cr='Craterbip:BAAANQADCgcICwAAAA==.Crimsonk:BAAANQABCgIIAgAAAA==.',
Cu='Curoconcum:BAAANQADCgYIBwAAAA==.',
Cy='Cyrub:BAAANQADCgQIBgAAAA==.',
Da='Dabrinto:BAAANQADCgYIBgAAAA==.Daedrian:BAAANQAECgEIAQAAAA==.Dallena:BAAANQAECgQIBwAAAA==.Dankweaver:BAAANQAECgQIBQAAAA==.Darthxander:BAAANQADCgUICQAAAA==.Daywrecker:BAAANQAECgIIAgAAAA==.Dayyman:BAAANQAECgUICwAAAA==.Dazuk:BAAANQADCgYIBgAAAA==.',
De='Deathlysham:BAAANQADCgIIAgAAAA==.Deathshroom:BAAANQADCgUICQABNQADCgYIBgABAAAAAA==.Deathsun:BAAANQAECgUIBQAAAA==.Deform:BAAANQAECgUIBQAAAA==.Deianaera:BAAANQADCgQIBAAAAA==.Delldestus:BAAANQADCgMIAwAAAA==.Demonics:BAAANQADCgYIBgAAAA==.Demonstix:BAAANQAECgEIAgAAAA==.Demv:BAAANQADCgIIAgAAAA==.Depressa:BAAANQADCgQIBAABNQAECgcICAABAAAAAA==.Dernius:BAAANQADCggICQAAAA==.Despairykyns:BAAANQADCgYICQABNQAECgQIBQABAAAAAA==.Dethbringa:BAAANQAECgQICAAAAA==.Dewfall:BAAANQAECgcIDgAAAA==.Deylithdreyn:BAAANQABCgUIBwAAAA==.',
Dh='Dhuoth:BAAANQAECgYICQAAAA==.',
Di='Diagoraz:BAAANQADCgUIBwAAAA==.Dialtone:BAAANQADCgQIBwAAAA==.Dialtonee:BAAANQADCgMIAwAAAA==.Digitalbäth:BAAANQADCgUIBQABNQAECgcIEQABAAAAAA==.Digoshadow:BAAANQAECgIIAgAAAA==.Disgruntld:BAAANQADCgIIAgAAAA==.Ditdoo:BAAANQADCgYICwAAAA==.',
Dk='Dkmetcàlf:BAAANQADCggICAAAAA==.',
Do='Dorkyspork:BAAANQAECgEIAQAAAA==.',
Dr='Dragonis:BAAANQADCggICAAAAA==.Dravenstone:BAAANQADCgIIAgAAAA==.Dreamerzz:BAAANQADCgYIBwAAAA==.Drovac:BAAANQADCgcIDQAAAA==.Druidxd:BAAANQADCgQIBAAAAA==.Drumittz:BAAANQADCgEIAQAAAA==.Drworm:BAAANQAECgYIDQAAAA==.Drääko:BAAANQABCgUIBwAAAA==.Drêdd:BAAANQABCgIIAgAAAA==.',
Ds='Dsonic:BAAANQADCgQIBAAAAA==.',
Du='Dubbies:BAAANQADCggIFgAAAA==.Durtluz:BAAANQADCgcICAAAAA==.Dustandblood:BAAANQADCgMIAgAAAA==.',
Dy='Dyrim:BAAANQADCgQIBgAAAA==.',
['Dæ']='Dæmonkawlr:BAAANQADCgQIBAAAAA==.',
['Dê']='Dêformjr:BAAANQAECgUICQAAAA==.Dêvarim:BAAANQABCgQIBAAAAA==.',
['Dë']='Dëformjr:BAAANQADCgYIBgAAAA==.Dëförmjr:BAAANQAECgQIBAAAAA==.',
['Dú']='Dúbletap:BAAANQADCgYIBgAAAA==.',
El='Elbrujo:BAAANQABCgIIAwAAAA==.Elenii:BAAANQAECgUIBwAAAA==.Eleynra:BAAANQADCgIIAgAAAA==.Elybear:BAAANQADCgUIBQAAAA==.Elychan:BAAANQADCgYIBgAAAA==.Elygance:BAAANQADCggICAAAAA==.Elÿ:BAAANQAECgQIBAAAAA==.',
Em='Emptyside:BAAANQADCggIDwAAAA==.',
En='Enchorxxi:BAAANQADCggIDwAAAA==.Enetrenazara:BAAANQADCgYIBgABNQADCgYICQABAAAAAA==.Eniar:BAAANQADCgUIBQABNQADCggICAABAAAAAA==.Eniaro:BAAANQADCggICAAAAA==.Enlonger:BAAANQAECgcICwAAAA==.',
Ep='Epicgooner:BAAANQAECgUIBQAAAA==.',
Er='Erahmm:BAAANQADCggIEwAAAA==.Ergaraskreia:BAAANQADCgIIAgAAAA==.Erielia:BAAANQADCgIIAgABNQADCgYICAABAAAAAA==.',
Es='Esmirelda:BAAANQAECgEIAQAAAA==.Essn:BAABNQAECoEbAAIHAAkJtyS6AADWAwAHAAkJtyS6AADWAwAAAA==.',
Eu='Eulune:BAEANQADCggIFwABNQAECgYICgABAAAAAA==.',
Ev='Evelynna:BAAANQADCgcIDAAAAA==.',
Ex='Exsull:BAAANQADCggIFQAAAA==.',
Fa='Faible:BAAANQABCgIIAgAAAA==.Faithwarrior:BAAANQADCgYIBgAAAA==.Falron:BAABNQAECoFYAAIIAAgJmiTMAgAUAwAIAAgJmiTMAgAUAwAAAA==.Fathlia:BAAANQAECgQIBQAAAA==.',
Fe='Fezzjin:BAAANQAECgEIAQAAAA==.',
Fi='Filbrust:BAAANQADCgIIAgAAAA==.Fishtanked:BAAANQADCgQIBgAAAA==.Fitzofrage:BAAANQADCgYIBwAAAA==.',
Fl='Flashlights:BAAANQADCgYICQAAAA==.Fleshbiter:BAAANQADCgYICQAAAA==.Flowingdeath:BAAANQADCgMIAwABNQADCgYIBgABAAAAAA==.Flowingrage:BAAANQADCgYIBgAAAA==.',
Fm='Fmjserval:BAAANQADCgMIBQAAAA==.',
Fo='Fomtoolery:BAAANQABCgUIBQAAAA==.Foot:BAAANQAECgcIDAAAAA==.Forcefaith:BAAANQAECgQIBQAAAA==.',
Fr='Freduardo:BAAANQADCgUIBgAAAA==.Freva:BAAANQAECgQIBQAAAA==.Frostfiree:BAAANQADCgcICAABNQAECgYIDQABAAAAAA==.Fruitpuddle:BAAANQABCgEIAQABNQAECgYIDQABAAAAAA==.Frøsty:BAAANQADCgEIAQAAAA==.',
Fu='Furlock:BAAANQADCgMIAwAAAA==.Furryhugger:BAAANQAECgIIAgAAAA==.Furstab:BAAANQADCgQIBQAAAA==.',
['Fì']='Fìzzypop:BAAANQADCgEIAQAAAA==.',
Ga='Galepalm:BAAANQAECgQIBAAAAA==.Gambriniss:BAAANQADCgcIEgAAAA==.Gamea:BAAANQAECgUIBwAAAA==.Garloch:BAAANQADCgcIBwAAAA==.Gazrosh:BAAANQADCgcIEAAAAA==.',
Ge='Geladra:BAAANQADCgcIBwABNQAECgYICwABAAAAAA==.Gemmothy:BAAANQADCgMIBQAAAA==.',
Gi='Gibbychona:BAAANQAECgYICwAAAA==.',
Gl='Glowshroom:BAAANQADCgEIAQABNQADCgYIBgABAAAAAA==.',
Go='Golotak:BAAANQADCgcIBwAAAA==.Gonnagetproc:BAAANQADCggICAAAAA==.Googale:BAAANQADCgEIAQAAAA==.Gordoc:BAAANQADCgcIEgAAAA==.Gothboy:BAAANQADCggICAAAAA==.',
Gr='Graff:BAAANQAECgEIAQAAAA==.Grailed:BAAANQADCgEIAQAAAA==.Gravem:BAAANQADCgUIBQAAAA==.Gravie:BAAANQADCgIIAgAAAA==.Graystaf:BAAANQAECgEIAQAAAA==.Greggorie:BAAANQAECgEIAQAAAA==.Grennan:BAAANQADCggIDQAAAA==.Greyowl:BAAANQADCggICAAAAA==.Grifflez:BAAANQAECgEIAQAAAA==.Grumpli:BAAANQAECgUICAAAAA==.',
Gu='Guytheshower:BAAANQAECgEIAQAAAA==.',
Gw='Gweilo:BAAANQADCgcIBwAAAA==.',
Ha='Habek:BAAANQADCgQIBQAAAA==.Hamadaver:BAAANQABCgQIBgAAAA==.Handofblood:BAAANQAECgMIBAAAAA==.Handymandy:BAAANQADCggICAABNQAECggIEAABAAAAAA==.Harderrock:BAAANQADCgEIAQABNQAECgYICAABAAAAAA==.Hardrockgirl:BAAANQAECgMIAwABNQAECgYICAABAAAAAA==.Harmonechi:BAAANQAECgUICAAAAA==.',
He='Healdealer:BAAANQADCgQIBAAAAA==.Healmonbello:BAAANQAECgIIAgAAAA==.Healystix:BAAANQADCgIIAgABNQAECgEIAgABAAAAAA==.Hellzcrusade:BAAANQADCggIEwAAAA==.Henchi:BAAANQADCgIIAgABNQADCgUIBQABAAAAAA==.',
Hi='Higherheal:BAAANQADCgMIAwAAAA==.',
Ho='Hodesh:BAAANQADCgMIAwAAAA==.Holypuuss:BAAANQAECggIEAAAAA==.Honeybumms:BAAANQAECgIIAwAAAA==.Hopeslayer:BAAANQADCgUIBQABNQAECgYICwABAAAAAA==.Hoplitedruid:BAAANQAECgQIBQAAAA==.Houndoom:BAAANQADCgYICgAAAA==.',
Ht='Htiál:BAAANQADCgIIAgAAAA==.Htiâl:BAAANQADCgIIAgABNQADCgIIAgABAAAAAA==.',
Hu='Huntko:BAAANQADCggIEgAAAA==.',
Hy='Hyperthymia:BAAANQAECgcICwAAAA==.Hyrakka:BAAANQAECgEIAQABNQADCgUIBQABAAAAAA==.',
Ic='Iceeveins:BAAANQADCggICAAAAA==.Icystyx:BAAANQAECgEIAQAAAA==.',
Il='Ilyamurometz:BAAANQAECgYICQAAAA==.',
Im='Immorta:BAAANQAECgYICQAAAA==.',
In='Indigokiya:BAAANQADCgYIEgAAAA==.Ingesteel:BAAANQADCgEIAQAAAA==.Inodoro:BAAANQAECgYIBgAAAA==.',
Io='Iordgodplaya:BAAANQADCgcICwAAAA==.',
Ir='Irabmal:BAAANQAECgQIBAAAAA==.Iriclaw:BAABNQAECoEXAAIJAAkJcSXKAADOAwAJAAkJcSXKAADOAwAAAA==.Ironpanda:BAAANQADCgEIAQAAAA==.',
Is='Isothymia:BAAANQAECgEIAQABNQAECgcICwABAAAAAA==.',
It='Itsmepip:BAAANQADCggIDwAAAA==.',
Ja='Jacoby:BAAANQAECgUIBQABNQAECggIEwABAAAAAA==.Jadefires:BAAANQADCgYICgABNQADCggIEAABAAAAAA==.Jadelite:BAAANQADCggIEAAAAA==.Janddasham:BAAANQAECgYICQAAAA==.Janddavoker:BAABNQAECoEYAAIKAAkJ3B2fAgBAAwAKAAkJ3B2fAgBAAwAAAA==.Jaxo:BAAANQAECgEIAQABNQAECgUIDQABAAAAAA==.',
Jh='Jherri:BAAANQADCgYIDgAAAA==.',
Ji='Jimbeamer:BAAANQAECgEIAQAAAA==.',
Jk='Jkm:BAAANQAECgEIAQAAAA==.',
Jo='Joanexotic:BAAANQAECgIIAgAAAA==.Jojolion:BAAANQAECgEIAQAAAA==.',
Jr='Jrocmfka:BAAANQAECgEIAQAAAA==.',
Jt='Jtama:BAAANQADCgUIBwAAAA==.',
Ka='Kage:BAAANQADCgQIBgAAAA==.Kaiderten:BAAANQADCgIIAgAAAA==.Kailo:BAAANQADCgYIEQAAAA==.Kal:BAAANQADCgQIBgAAAA==.Kalorondir:BAAANQABCgQIBgAAAA==.Kamila:BAAANQADCggIDAAAAA==.Kaorí:BAAANQAECgMIAwAAAA==.Karatekyns:BAAANQADCgIIAgABNQAECgQIBQABAAAAAA==.Kaselian:BAAANQADCgcICQAAAA==.Katatree:BAAANQADCggICAAAAA==.Kattara:BAAANQAECgMIAwAAAA==.Kayalanii:BAAANQADCggICAAAAA==.Kazuhla:BAAANQAECgIIAgAAAA==.',
Ke='Keiryn:BAAANQADCgYICwAAAA==.Kenté:BAAANQADCgUIBQAAAA==.',
Kh='Khaotikpyre:BAABNQAECoEYAAIFAAkJNxnEIQDMAgAFAAkJNxnEIQDMAgAAAA==.',
Ki='Kiffypoo:BAAANQADCggIFAAAAA==.Kil:BAAANQAECgYICwAAAA==.Kiljaiden:BAAANQABCgIIAgAAAA==.Kinner:BAAANQAECgEIAQAAAA==.Kisho:BAAANQADCgMIAwAAAA==.Kiyoshie:BAAANQAECgYICwAAAA==.',
Kl='Klanky:BAAANQADCggICAAAAA==.',
Kn='Kn:BAAANQADCgcIDAAAAA==.',
Ko='Kontroll:BAEANQADCggICwAAAA==.Kookee:BAAANQAECgcIEgAAAA==.Korice:BAAANQAECgQIBQAAAA==.',
Kr='Krypticgrip:BAAANQAECgcICgABNQAECgkJGAAFADcZAA==.',
Ku='Kumaa:BAAANQADCggIDQAAAA==.',
Ky='Kyle:BAAANQAECgEIAQAAAA==.Kylidon:BAAANQADCgYIBgAAAA==.Kynlauriana:BAAANQADCgEIAQAAAA==.',
La='Lalaind:BAAANQADCgYICAAAAA==.Larissa:BAAANQAECgIIAgAAAA==.Lathillea:BAAANQADCggIFAAAAA==.Launchpad:BAAANQADCgQIBAAAAA==.Lazzirus:BAAANQAECgYIBwAAAA==.',
Le='Leedict:BAAANQAECgQIBQAAAA==.Leerøy:BAAANQAECgIIAgAAAA==.Leilani:BAAANQADCgYIDQAAAA==.Leinalei:BAAANQADCggICAABNQAECgUIBQABAAAAAA==.Lessii:BAEANQAECgcIDwAAAA==.',
Li='Lidande:BAAANQADCgYIBgAAAA==.Lidarcis:BAAANQAECgMIBAAAAA==.Liedora:BAAANQADCgUIBgAAAA==.Lightpraiser:BAAANQAECgEIAQAAAA==.Limjahey:BAAANQADCggICAAAAA==.Linra:BAAANQAECgUIBgAAAA==.Littlefatt:BAAANQAECgQIBQAAAA==.',
Ll='Llich:BAAANQADCggICAAAAA==.',
Lu='Luassei:BAAANQADCgEIAQAAAA==.Lucishifts:BAAANQAECgMIBgAAAA==.Lucîan:BAAANQADCggIEwAAAA==.Lumaris:BAAANQADCgcIBwAAAA==.Lunamorr:BAAANQADCgYIBgAAAA==.',
Ly='Lyserra:BAAANQAECgEIAQAAAA==.',
Ma='Maddawggamin:BAAANQADCgQIBAAAAA==.Mafi:BAAANQADCgMIAwAAAA==.Magenos:BAAANQAECgQIBAAAAA==.Magicpants:BAAANQADCgcIDgAAAA==.Magobiga:BAAANQADCgYICAAAAA==.Mahrx:BAABNQAECoEXAAILAAkJwiMGAgB6AwALAAkJwiMGAgB6AwAAAA==.Mawaru:BAAANQAECgEIAQAAAA==.Maxanadu:BAAANQADCgQIBQAAAA==.',
Me='Meatpipe:BAAANQAECgEIAQAAAA==.Medarela:BAAANQADCgcIEgAAAA==.Meeke:BAAANQAFFAIIAwAAAA==.Mell:BAAANQAFFAEIAQAAAA==.Melmin:BAAANQAECgIIAgAAAA==.Mercyful:BAAANQADCggICQAAAA==.Meroman:BAAANQADCgQIBgAAAA==.Metamora:BAAANQADCggIFwAAAA==.Meuria:BAAANQADCggIEwAAAA==.',
Mi='Midgetlord:BAAANQAECggIDwAAAA==.Miklos:BAAANQADCgQIBQAAAA==.Misstearly:BAAANQADCgYIBgAAAA==.',
Mo='Moneebagz:BAAANQADCggIFAAAAA==.Montblanc:BAAANQADCggICAAAAA==.Moonem:BAAANQAECgQICQAAAA==.Mossacre:BAAANQAECgYICAAAAA==.Mossherder:BAAANQABCgEIAQAAAA==.',
['Mé']='Méta:BAAANQADCgcICAABNQADCggIFwABAAAAAA==.',
Na='Nachopapa:BAAANQADCgYICgAAAA==.Nalorspace:BAAANQADCgYICwAAAA==.Naniwa:BAAANQAECgYIBwAAAA==.Narwail:BAAANQAECgEIAgAAAA==.Narweil:BAAANQADCgUIBQABNQAECgEIAgABAAAAAA==.Narwhall:BAAANQADCgYICwABNQAECgEIAgABAAAAAA==.Natanus:BAAANQADCgQIBgAAAA==.Nazaric:BAAANQAECgMIAwAAAA==.Nazgeul:BAAANQADCgYICwAAAA==.',
Nb='Nbi:BAAANQABCgQIBQABNQADCgYIBgABAAAAAA==.',
Ne='Necrodik:BAAANQADCgQIBAAAAA==.Neladris:BAAANQADCgIIAgAAAA==.Nelagorn:BAAANQADCgIIAgAAAA==.Nemesís:BAAANQABCgMIAwAAAA==.Neohorn:BAAANQADCgYIDAAAAA==.Neomyk:BAAANQADCggIDgAAAA==.Neoptolemus:BAAANQADCgQIBgAAAA==.Neoqled:BAAANQADCgIIAgAAAA==.Neorhon:BAAANQADCgUIBQAAAA==.Nerclopse:BAAANQAECgYIDQAAAA==.Neverender:BAAANQADCgcIFAAAAA==.Nexian:BAAANQABCgQIBgAAAA==.',
Ni='Niarwodahs:BAAANQADCgcIBwAAAA==.Niaryci:BAAANQAECgEIAQAAAA==.Nightfangz:BAAANQADCgYIDAAAAA==.',
No='Noritotem:BAAANQADCgcIDQAAAA==.Note:BAAANQADCgUICQAAAA==.Notec:BAAANQADCggIAQAAAA==.Novacainê:BAAANQADCggICAAAAA==.',
Nu='Nuikai:BAAANQAECgQIBAAAAA==.Nukum:BAAANQADCgQIBAAAAA==.',
Ob='Obsidiansun:BAAANQAECgQIBwAAAA==.',
Oc='Octame:BAAANQADCggIFAAAAA==.',
Ol='Olethvia:BAAANQADCgMIAwABNQAECgQIBAABAAAAAA==.',
Oo='Oororoe:BAAANQADCgUIBQAAAA==.',
Op='Opalescence:BAAANQADCgYIDQAAAA==.Optional:BAAANQAFFAEIAQAAAA==.',
Or='Orgargo:BAAANQADCgYIBgAAAA==.',
Os='Osley:BAAANQADCgMIAwAAAA==.',
Ou='Oule:BAEANQAECgYICgAAAA==.',
Pa='Pallorx:BAAANQADCgQIBAAAAA==.Palpatiné:BAAANQADCgQIBAAAAA==.Paluoth:BAAANQADCgEIAQAAAA==.Pandasennin:BAAANQADCgQIBgAAAA==.Papachains:BAAANQADCgYIDAABNQAECggIAQABAAAAAA==.Papashootin:BAAANQAECggIAQAAAA==.Paperplate:BAAANQAECgYICgAAAA==.Paradox:BAAANQAECgUICQAAAA==.Pattyhealsu:BAAANQAECgcIEQAAAA==.Pawlyn:BAAANQADCgEIAQAAAA==.',
Pe='Peachizz:BAAANQAECgEIAQAAAA==.Pelivarondo:BAAANQAECgYIEAAAAA==.Pelizandeth:BAAANQADCgYIDAABNQAECgYIEAABAAAAAA==.Pepegas:BAAANQADCggIDwAAAA==.Pestillia:BAAANQAECgIIAgAAAA==.',
Ph='Phoffynax:BAAANQADCggIEwAAAA==.Phundip:BAAANQADCgMIBgABNQADCggIEgABAAAAAA==.',
Pi='Pistolbeat:BAAANQADCgUIBQAAAA==.',
Pl='Playful:BAAANQADCggIDgAAAA==.Plopopotamus:BAAANQAECgYIBQAAAA==.',
Po='Polikarp:BAAANQABCgQIBwAAAA==.Pookìe:BAAANQAECgMIBAAAAA==.Poorsol:BAAANQAECgIIAwAAAA==.',
Ps='Psyko:BAAANQADCgMIAwABNQADCggICAABAAAAAA==.',
Qu='Quickbrown:BAAANQAECgEIAQAAAA==.',
Ra='Rahxe:BAAANQADCggIDgAAAA==.Raikz:BAAANQAECgIIAgAAAA==.Raiyne:BAAANQADCggIDwAAAA==.Rats:BAABNQAECoEXAAIHAAgJhhkCDQCfAgAHAAgJhhkCDQCfAgAAAA==.Ratshield:BAAANQADCgQIBAABNQAECggIFwAHAIYZAA==.',
Re='Rendis:BAAANQADCgIIAgAAAA==.Reno:BAAANQAECgEIAQAAAA==.Reurog:BAAANQAECgEIAQAAAA==.',
Rh='Rhakudu:BAAANQADCgYIBgABNQADCggIEQABAAAAAA==.',
Ri='Rian:BAABNQAECoEVAAIMAAkJ/SB+AwBmAwAMAAkJ/SB+AwBmAwABNQAECgkJGQAFAMAgAA==.Ritalia:BAAANQAECgQIBwAAAA==.',
Rm='Rmnieech:BAAANQADCgUIDwAAAA==.',
Ro='Roadiee:BAAANQADCgYICgAAAA==.Roadiex:BAAANQADCgIIAwAAAA==.Roadkyll:BAAANQADCgcIEgAAAA==.Ronynn:BAAANQADCgEIAQAAAA==.Rosamoon:BAAANQADCgYICgAAAA==.Rosilyn:BAAANQADCgcIBwAAAA==.',
Ru='Rurrick:BAAANQAECgEIAQAAAA==.',
Ry='Ryzee:BAAANQAECgYICAAAAA==.',
['Rå']='Råinè:BAAANQADCgcIBwABNQADCggICAABAAAAAA==.',
Sa='Sahmash:BAAANQADCgIIAgAAAA==.Salara:BAAANQAECgQIBAAAAA==.Salasong:BAAANQADCgUIBQAAAA==.Saltytoast:BAAANQAECgEIAQAAAA==.Sambda:BAAANQADCgUIBQAAAA==.Sambraicho:BAAANQADCggICAAAAA==.Samburai:BAAANQADCgQIBQABNQADCgUIBQABAAAAAA==.Samuella:BAAANQAECgMIBAAAAA==.Sandrinea:BAAANQADCggIFQAAAA==.Sarinya:BAAANQADCgYIBgAAAA==.Saytens:BAAANQADCggIAwAAAA==.',
Sc='Scargiver:BAAANQADCgEIAQAAAA==.Scarllett:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Schatzi:BAAANQADCggICAAAAA==.Scrubmage:BAAANQADCggICwAAAA==.',
Se='Secondwall:BAAANQAECgQIBAAAAA==.Sedale:BAAANQAECgQIBAAAAA==.Seesdeline:BAAANQADCgUIAgABNQADCgYIBgABAAAAAA==.Seilene:BAAANQADCgUICgABNQADCgcIEAABAAAAAA==.Senddra:BAAANQABCgQIBgAAAA==.Seo:BAAANQADCggICQAAAA==.Seraf:BAAANQAECggIDwAAAA==.Serafain:BAAANQAECgEIAQABNQAECggIDwABAAAAAA==.',
Sh='Shadowerise:BAAANQADCgUIBQAAAA==.Shaforgold:BAAANQAECgcICQAAAA==.Shalazard:BAAANQADCggIFAAAAA==.Shamananana:BAAANQADCgYIBgAAAA==.Sharrina:BAAANQABCgEIAQAAAA==.Shibal:BAAANQAECgEIAQAAAA==.Shinystepdad:BAAANQADCgUIBQAAAA==.Shotorock:BAAANQADCgYIEgAAAA==.Shrekismydad:BAAANQADCgQIBAAAAA==.Shroomshock:BAAANQADCgYIBgAAAA==.Shushumen:BAAANQAECgQIBQAAAA==.Shänk:BAAANQABCgQICgAAAA==.',
Si='Sicknezz:BAAANQADCgYICwABNQAECggICAABAAAAAA==.Sidewinder:BAAANQAECgEIAQABNQAFFAEIAQABAAAAAA==.Siinyster:BAAANQADCgMIAwAAAA==.Sikmode:BAAANQADCggIEgAAAA==.Sildrusil:BAAANQADCgEIAQAAAA==.Sindari:BAAANQAECgUIBgAAAA==.Sinturio:BAAANQADCggIEwAAAA==.Sipsy:BAAANQAECgEIAQAAAA==.',
Sk='Skarg:BAAANQAECgMIBAAAAA==.Skyeashe:BAAANQADCgYIDAAAAA==.',
Sl='Sleezytease:BAAANQADCgcIBwAAAA==.Slimdusty:BAAANQADCgQICAAAAA==.Slingblades:BAAANQAECggICAAAAA==.Slobbrknckr:BAAANQADCgcIBwABNQAECggIEAABAAAAAA==.Slowmo:BAAANQADCgYIBgAAAA==.',
Sm='Smittles:BAAANQAECgEIAQAAAA==.',
Sn='Sneakybob:BAAANQADCggICAAAAA==.Sneakystix:BAAANQADCgYIBgABNQAECgEIAgABAAAAAA==.',
So='Sootclaw:BAAANQADCgYICQAAAA==.Sophus:BAAANQAECgEIAQAAAA==.Soren:BAAANQADCgYIBgAAAA==.Sorenko:BAAANQAECgEIAQABNQADCgYIBgABAAAAAA==.',
Sp='Spagooter:BAABNQAECoEOAAMNAAgJZBuBFABdAgANAAcJ9BuBFABdAgAOAAEJdRchSQBGAAAAAA==.Sparklepants:BAAANQAECgcICwAAAA==.Spencerz:BAAANQADCgEIAQAAAA==.Speyesee:BAAANQAECgIIAgAAAA==.Splashydank:BAAANQADCgcIDAAAAA==.',
St='Stabbydank:BAAANQADCgYIBgAAAA==.Stackss:BAAANQAECgEIAQAAAA==.Stonedninja:BAAANQADCgIIAQAAAA==.Stonemason:BAAANQADCgcIFAAAAA==.Stoneskin:BAAANQADCgQIBAAAAA==.Strawberymik:BAAANQADCgEIAQAAAA==.',
Su='Submisive:BAAANQADCgcIDgAAAA==.Supe:BAAANQADCgcIEwAAAA==.',
Sw='Swagruid:BAAANQAECgIIAgAAAA==.Swampslinger:BAAANQAECgMIAwAAAA==.Swordlady:BAAANQAECgQIBAABNQAECgUIBwABAAAAAA==.',
Sy='Syntari:BAAANQAECgIIAgAAAA==.Synìk:BAAANQADCgUICgAAAA==.',
['Sö']='Söma:BAAANQAECgIIAwAAAA==.',
Ta='Taktixxloxx:BAAANQABCgMIAwAAAA==.Talenalat:BAAANQAECgEIAQAAAA==.Tankerbelle:BAAANQADCgEIAQAAAA==.Tannarisse:BAAANQADCgQIBAAAAA==.Taymatt:BAAANQAECgEIAQAAAA==.Tazstinko:BAAANQAECgEIAQABNQAECgYIDQABAAAAAA==.',
Te='Tectonic:BAAANQAECgYIDAABNQAECggIBwABAAAAAA==.Tejasgeek:BAAANQAECgEIAQAAAA==.Tenleron:BAAANQABCgIIAgAAAA==.Tenntoes:BAAANQADCgYIBgAAAA==.',
Th='Theiceflare:BAAANQADCgMIAwAAAA==.Themuffinman:BAAANQADCgcIEgAAAA==.Theworrirawr:BAAANQAECgUICgAAAA==.Thur:BAAANQAECgIIAgAAAA==.Thänatos:BAAANQAECgIIAgAAAA==.',
Ti='Tiesci:BAAANQAECgQIBQABNQAECgUIBQABAAAAAA==.Tinyclash:BAAANQADCgQIBAAAAA==.Tinypap:BAAANQADCggIEAAAAA==.Tippe:BAAANQADCggIEAAAAA==.',
Tl='Tlálocx:BAAANQADCggIEQAAAA==.',
To='Toastedblade:BAAANQAECgEIAQAAAA==.Toldyousoul:BAAANQAECgEIAQAAAA==.Tonytots:BAAANQADCggIDgAAAA==.Tottemakk:BAAANQADCgEIAQAAAA==.Toughshots:BAAANQADCgEIAQAAAA==.Toxenima:BAAANQADCgcIDAAAAA==.Toxiciti:BAAANQAECgIIAgAAAA==.',
Tr='Tramlaw:BAAANQADCgIIAgAAAA==.Trashedara:BAAANQADCgUIBQAAAA==.Treebirth:BAAANQAECgYICwAAAA==.Treyu:BAAANQADCgYIBgAAAA==.Triegh:BAAANQABCgUIBQAAAA==.Trunder:BAAANQAECgEIAQAAAA==.',
Ts='Tsaindorcus:BAAANQAECgQICgAAAA==.Tsunamyz:BAAANQADCgIIBQAAAA==.',
Tu='Tuskgwel:BAAANQADCgIIAQAAAA==.',
Ty='Tyfoon:BAAANQABCgIIAgAAAA==.',
Ud='Uders:BAAANQAECgEIAQAAAA==.',
Uh='Uhlvar:BAAANQAECgYICgAAAA==.Uhm:BAAANQAECggICAAAAA==.',
Ui='Uil:BAEANQADCgQIBAABNQAECgYICgABAAAAAA==.',
Ul='Ultramad:BAAANQAECgEIAQAAAA==.Ultramellow:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.',
Un='Unclesquid:BAAANQADCggIEwAAAA==.Unholydubzzy:BAAANQADCgEIAQAAAA==.',
Up='Upngo:BAAANQAECgQIBwAAAA==.',
Us='Uskthyr:BAAANQADCgUIBQAAAA==.',
Va='Vanakin:BAAANQAECgQIBAABNQAFFAUIBgAPABMIAA==.Vandredor:BAACNQAFFIEGAAIPAAUJEwjsAACKAQAPAAUJEwjsAACKAQA1AAQKgRkAAw8ACQmiH8kFAPQCAA8ACQl0H8kFAPQCABAABglaHHgDAOwBAAAA.Vastatio:BAAANQADCgEIAQAAAA==.Vasträ:BAAANQADCgQIBgAAAA==.',
Ve='Velicelia:BAAANQAECgQIBwAAAA==.Vesroth:BAAANQADCggIFAAAAA==.',
Vi='Viborge:BAAANQADCggIDgAAAA==.View:BAAANQAECgYICgAAAA==.Vince:BAAANQADCggIEQAAAA==.Vissra:BAAANQADCgUIBQAAAA==.',
Vu='Vulpermon:BAAANQADCgMIBAAAAA==.',
['Vä']='Vääko:BAAANQADCgcIEgAAAA==.',
['Ví']='Vínce:BAAANQADCgIIAgAAAA==.',
Wa='Warlarren:BAAANQADCgEIAQAAAA==.',
We='Weatherr:BAAANQAECggIBgAAAA==.Weki:BAAANQADCggIDAAAAA==.',
Wh='Whippoorwill:BAAANQAECgYICwAAAA==.Whiskyslayer:BAAANQAECgYIBQAAAA==.',
Wi='Williamp:BAAANQADCgQIBAAAAA==.',
Wn='Wntlmd:BAAANQAECgMIBAAAAA==.',
Wo='Wolfnacht:BAAANQAECgEIAQAAAA==.',
Wu='Wukangmei:BAAANQADCgMIAwAAAA==.',
['Wà']='Wàrødør:BAAANQAECgEIAQAAAA==.',
Xe='Xene:BAAANQAECgQICQAAAA==.',
Xh='Xhade:BAAANQADCgIIAgABNQADCggIEAABAAAAAA==.',
Xr='Xriss:BAAANQADCgQICAAAAA==.Xrs:BAAANQADCgQIBAAAAA==.',
Ya='Yanedin:BAAANQAECgcICwAAAA==.Yathrr:BAAANQADCgUIBQAAAA==.',
Yo='Yorforger:BAAANQAECgIIAgABNQAECgcICgABAAAAAA==.Youngbj:BAAANQAECgEIAQABNQAECgUIBgABAAAAAA==.Younger:BAAANQAECgEIAgAAAA==.Youngerxx:BAAANQADCgYIBgAAAA==.',
Yu='Yukonícus:BAAANQADCgYIBgABNQAECgUICwABAAAAAA==.Yukonïcus:BAAANQAECgUICwAAAA==.Yumm:BAAANQADCgcIBwAAAA==.Yuridemo:BAAANQAECgcICwAAAA==.',
['Yè']='Yènnefer:BAAANQADCgUIBQAAAA==.',
Za='Zaldrena:BAAANQADCgYIBgAAAA==.Zanotgaming:BAAANQADCgcIBwAAAA==.Zaraydorine:BAAANQADCgUIBQAAAA==.',
Zb='Zbrickashaw:BAAANQADCggIDgAAAA==.',
Ze='Zelrin:BAABNQAECoEWAAIFAAkJHBVNLwCFAgAFAAkJHBVNLwCFAgAAAA==.Zenthalion:BAAANQAECgEIAQAAAA==.',
Zi='Zippee:BAAANQADCgQIBAAAAA==.',
Zo='Zobi:BAAANQADCgMIAwAAAA==.Zoomhunt:BAAANQAECgUIBgABNQAFFAEIAQABAAAAAA==.Zoommage:BAAANQAFFAEIAQAAAA==.',
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
