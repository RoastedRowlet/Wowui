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

local lookup = {'Unknown-Unknown','Hunter-BeastMastery','DeathKnight-Blood','Paladin-Protection','Druid-Balance','Priest-Discipline','Mage-Arcane','Evoker-Devastation','DeathKnight-Frost','DeathKnight-Unholy','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Hunter-Marksmanship','DemonHunter-Devourer','Shaman-Restoration','Paladin-Holy','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Warrior-Arms','Warrior-Protection','Priest-Shadow','Druid-Restoration','Shaman-Elemental','Evoker-Preservation',}
local provider = {region='US',realm='Icecrown',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aaronstorm:BAAANQAECgEIAQAAAA==.',
Ac='Ackward:BAAANQAECgYICAAAAA==.Ackwarder:BAAANQAECgEIAQABNQAECgYICAABAAAAAA==.Acrylia:BAAANQADCgYIDwAAAA==.',
Ae='Aeryx:BAAANQAECgYIDgAAAA==.',
Ah='Ahsôka:BAAANQAECgEIAQAAAA==.',
Ak='Akisa:BAAANQADCgIIAgAAAA==.',
Al='Alagorn:BAAANQADCgYIBgAAAA==.Alinael:BAAANQADCggIEgAAAA==.Alisterr:BAAANQADCgcIDAAAAA==.Alistra:BAAANQADCggIDQAAAA==.Alynaa:BAAANQAECgUICAAAAA==.',
Am='Amadixiechic:BAAANQADCggIDAAAAA==.Amafrey:BAAANQAECgQIBwAAAA==.Amo:BAAANQAECgUICwAAAQ==.Amoresto:BAAANQADCgYIBgABNQAECgUICwABAAAAAQ==.Amoret:BAAANQADCgEIAQABNQAECgUICwABAAAAAQ==.',
An='Ancestraljr:BAAANQAECgQIBAAAAA==.Andaa:BAAANQADCgUIBQAAAA==.Andalocke:BAAANQAECgQIBgAAAA==.Annalucia:BAAANQADCgEIAQAAAA==.Annboleyn:BAAANQAECgEIAQAAAA==.',
Ar='Arabelle:BAAANQAECgUICgAAAA==.Archurroso:BAAANQADCgUIBQAAAA==.Ares:BAAANQADCgYIBgAAAA==.Ariens:BAAANQAECgQICAAAAA==.Arlaeya:BAAANQAECgEIAQAAAA==.Arocyra:BAAANQABCgQIBgAAAA==.Artemislux:BAAANQAECgYIDAAAAA==.Aránda:BAAANQADCggIEgAAAA==.',
As='Astelle:BAAANQAECgUIBwAAAA==.',
At='Atagos:BAAANQAECgUICwAAAA==.Athanor:BAAANQADCggICgABNQAECgUIAwABAAAAAA==.Atonementism:BAAANQAECgMIBAABNQAECgEIAQABAAAAAA==.',
Au='Aurawa:BAAANQAECgIIAgAAAA==.Austin:BAAANQAECgcIBwAAAA==.Autumnn:BAAANQADCgUIBQAAAA==.',
Av='Avannia:BAAANQADCgcICQAAAA==.Avaren:BAAANQAECgcICAABNQAECgQIBAABAAAAAA==.Avawen:BAAANQAECgYIDAABNQAECgQIBAABAAAAAA==.Averyg:BAAANQADCgYICQAAAA==.',
Aw='Awhbeans:BAAANQAECgIIAgAAAA==.',
Ax='Axtafal:BAAANQAECgIIAgAAAA==.',
Ay='Ayla:BAAANQADCgQIBAAAAA==.',
['Aá']='Aáronstorm:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.',
Ba='Babaganouj:BAAANQADCgYIEAAAAA==.Baineblood:BAAANQAECgQIBQAAAA==.Bandledin:BAAANQADCgcIDQAAAA==.Barelilus:BAAANQADCgcICwAAAA==.Barthus:BAAANQAECgIIAgABNQAECgMIBAABAAAAAA==.Baseballman:BAAANQADCggICAABNQAECgQIBAABAAAAAA==.Bassproshops:BAABNQAECoEWAAICAAkJrhk/DwCzAgACAAkJrhk/DwCzAgAAAA==.Baulder:BAAANQADCgQICAAAAA==.',
Be='Bear:BAAANQADCgEIAQABNQAFFAUICAADAMMkAA==.Belmyridon:BAAANQADCgcICgAAAA==.',
Bf='Bfc:BAAANQADCgUIBQAAAA==.',
Bi='Biaxident:BAAANQAECgMIBAAAAA==.Birdyy:BAAANQADCgYICgAAAA==.',
Bj='Bjorne:BAAANQAECgUICwAAAA==.',
Bl='Blammo:BAAANQADCgUIBQAAAA==.Blastoise:BAAANQAECgEIAQAAAA==.Blazter:BAAANQAECgUICAAAAA==.Blututh:BAAANQAECgYIBgAAAA==.Blïght:BAAANQADCggIDAAAAA==.',
Bo='Bodhran:BAAANQAECgMIBAAAAA==.Bombadill:BAAANQADCgYICAAAAA==.Bonewings:BAAANQADCggICQAAAA==.Boombang:BAAANQAECgEIAQAAAA==.',
Br='Breezerk:BAAANQAECgUICQAAAA==.',
Bu='Bubblebetuna:BAAANQABCgIIAgAAAA==.Buggerella:BAAANQADCgIIAgAAAA==.Bullithead:BAAANQADCgYICQAAAA==.Bulrog:BAAANQAECgYICgAAAA==.Bumpey:BAAANQADCgUICAAAAA==.Bus:BAAANQAFFAEIAgABNQAFFAUICgAEAKAfAA==.Bushlite:BAAANQAECgYIDQAAAA==.',
By='Byni:BAAANQADCggIFAAAAA==.',
Ca='Calorenn:BAAANQADCgYICgABNQAECgIIBAABAAAAAA==.Caluu:BAAANQAECgcIDAAAAA==.Cankles:BAAANQAECgQIBAAAAA==.Canolope:BAAANQADCgYIBgABNQAECgUIBwABAAAAAA==.Catfood:BAAANQAECgcICgAAAA==.Cattibriee:BAAANQADCgMIAwAAAA==.',
Ce='Cece:BAAANQADCggIFQAAAA==.Celedhring:BAAANQAECgUICwAAAA==.',
Ch='Chaktaw:BAAANQAECgQIBQAAAA==.Chatubaholy:BAAANQAECgEIAQAAAA==.Chayito:BAAANQAECgYIEAAAAA==.Cheezi:BAAANQAECgQIBAAAAA==.Chickenism:BAECNQAFFIEOAAIFAAcJNBsoAAClAgAFAAcJNBsoAAClAgA1AAQKgR0AAgUACQkaJlkAAPIDAAUACQkaJlkAAPIDAAAA.Chiknsmoothi:BAAANQADCgYICwAAAA==.Chirpa:BAAANQADCgMIAwAAAA==.Chiwallow:BAAANQAECgQIBAAAAA==.Chloe:BAAANQADCggIEgAAAA==.Chowtime:BAAANQAECgQIBwAAAA==.Chromium:BAAANQAECgUIAwAAAA==.Chrysanthia:BAAANQADCgEIAQAAAA==.',
Ci='Cinderstorm:BAAANQADCgYICQAAAA==.Cirilla:BAAANQABCgIIAgAAAA==.Citronia:BAAANQADCggICQAAAA==.',
Cl='Clamps:BAAANQAFFAEIAgAAAA==.Clandon:BAACNQAFFIEPAAIGAAcJ5B4CAADlAgAGAAcJ5B4CAADlAgA1AAQKgR0AAgYACQnVJgIAABAEAAYACQnVJgIAABAEAAAA.Claxton:BAAANQAECgcICwAAAA==.Clomari:BAAANQAECgYICgAAAA==.',
Co='Commietotem:BAAANQAECgEIAQAAAA==.Concepts:BAAANQAECgcICwAAAA==.Costcomember:BAAANQADCgcICQAAAA==.',
Cr='Crashout:BAAANQADCggIAQAAAA==.Cron:BAAANQADCgcIBwAAAA==.Croneos:BAAANQAECgEIAQAAAA==.Cross:BAAANQAECgUICAAAAA==.',
Cu='Cudz:BAAANQADCgcIEgAAAA==.Curl:BAAANQAECgEIAQAAAA==.',
Cy='Cytanous:BAAANQADCgYIBgAAAA==.',
Da='Daddydeath:BAAANQAECgQIBQAAAA==.Dadrex:BAAANQADCgMIAwAAAA==.Dahrla:BAAANQAECgMIAwAAAA==.Daisyann:BAAANQAECgMIBQAAAA==.Dallasx:BAAANQADCgUIBQAAAA==.Dalmarr:BAAANQADCgcIEQAAAA==.Dancouga:BAAANQAECgUICwAAAA==.Darkdarius:BAAANQADCgMIAwAAAA==.Daruncic:BAAANQAECgMIAwAAAA==.Dave:BAAANQAECgQIBQAAAA==.Dawnchatters:BAAANQADCgQIBAAAAA==.Dawntodusk:BAAANQADCgYIBgAAAA==.Daymia:BAAANQAECgIIAgAAAA==.Dazknight:BAAANQAECgQIBwAAAA==.Dazshaman:BAAANQADCgYIDwABNQAECgQIBwABAAAAAA==.',
De='Deadion:BAAANQAECgIIAwAAAQ==.Deadpaly:BAAANQADCgMIAwABNQAECgIIAwABAAAAAQ==.Deadspinwin:BAAANQADCgIIAgABNQAECgIIAwABAAAAAQ==.Dearmage:BAAANQAECgUIBwAAAA==.Deathgripz:BAAANQADCgYIDwAAAA==.Decormei:BAAANQAECgUICQAAAA==.Deltatoast:BAAANQADCgQICAAAAA==.Demolack:BAAANQABCgIIAgAAAA==.Dennes:BAAANQADCgcIDwAAAA==.Destheleye:BAAANQADCgMIAwAAAA==.Dethnyte:BAAANQAECgEIAQAAAA==.',
Di='Diaf:BAABNQAECoEdAAIHAAcJZBFhWgDVAQAHAAcJZBFhWgDVAQAAAA==.Diniwen:BAAANQAECgMIBAAAAA==.Dirtbikes:BAAANQAECgQIBAAAAA==.Dithia:BAAANQAECgQIBQAAAA==.Divided:BAAANQADCggICAAAAA==.Division:BAAANQAECgYIDAAAAA==.',
Dj='Djparrot:BAAANQAECgEIAQAAAA==.',
Do='Domrï:BAAANQAECgYICgAAAA==.Donkayslayer:BAAANQAECgIIAgAAAA==.Donlock:BAAANQADCgcIBwAAAA==.Doohoo:BAAANQAECgIIAgAAAA==.Dordrel:BAAANQADCgEIAQAAAA==.Downpour:BAAANQAECgcICwAAAA==.',
Dr='Dracdad:BAAANQADCgEIAQAAAA==.Draevon:BAAANQADCgQICAABNQAECgUICAABAAAAAA==.Dragondnutz:BAAANQAECgIIAgAAAA==.Dragoness:BAAANQADCgQIBAAAAA==.Dragonflight:BAAANQAECgIIAgAAAA==.Drakloak:BAACNQAFFIEIAAIIAAYJfRE7AAARAgAIAAYJfRE7AAARAgA1AAQKgRkAAggACQmSJMMAALUDAAgACQmSJMMAALUDAAAA.Drclaw:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.Drench:BAAANQAECgMIAwAAAA==.',
Du='Duckdodger:BAAANQADCgIIAgAAAA==.',
Dv='Dv:BAAANQADCggIDgAAAA==.',
Dz='Dzasterpiece:BAABNQAECoEcAAIJAAkJlCErAgBVAwAJAAkJlCErAgBVAwAAAA==.',
['Dà']='Dàmnàtion:BAAANQADCgEIAQAAAA==.',
['Dä']='Däemarcus:BAAANQAECgEIAQAAAA==.',
Ec='Ectyxx:BAABNQAECoESAAIHAAgJpBy5KgCbAgAHAAgJpBy5KgCbAgAAAA==.',
Ed='Edris:BAAANQADCggIEwAAAA==.',
Ei='Eightlug:BAAANQAECgEIAQAAAA==.',
El='Elareis:BAAANQADCgQICgAAAA==.Elebits:BAAANQADCgIIBAABNQAECgkJHgACABseAA==.Eluned:BAAANQAECgEIAQAAAA==.Elwynn:BAAANQAECgYIBwAAAQ==.Elycia:BAAANQADCgYIBgAAAA==.',
Em='Emosmaug:BAAANQAECggIEQAAAA==.',
En='Enkistral:BAAANQAECgMIAwABNQAECgcIBwABAAAAAA==.Envi:BAAANQAECgEIAQAAAA==.',
Er='Erotaph:BAAANQADCggIEgAAAA==.',
Es='Esoteric:BAAANQAECgYICQAAAA==.',
Eu='Euron:BAAANQAECgEIAQAAAA==.',
Ev='Evach:BAAANQAECggIEAAAAA==.Everblight:BAAANQADCgYICwAAAA==.',
Fa='Facex:BAAANQADCggIDAAAAA==.Faelor:BAAANQADCgYICwAAAA==.Faet:BAAANQAECgUIBwAAAA==.Faeyt:BAAANQAECgMIAwAAAA==.Fakename:BAAANQADCgMIAwAAAA==.Fatkokmage:BAAANQADCggIDAAAAA==.',
Fc='Fcawfng:BAAANQADCgUIBwAAAA==.',
Fe='Felakai:BAAANQADCgYIDAAAAA==.',
Fi='Fidgetspinna:BAAANQADCgIIAgAAAA==.Finaljudgmnt:BAAANQADCgIIAgABNQAECgUIBwABAAAAAA==.Finesthour:BAACNQAFFIEMAAMKAAYJ3hwQAAAkAgAKAAUJqiAQAAAkAgADAAEJ3gkeDgAqAAA1AAQKgRsAAgoACQlPJe0AANgDAAoACQlPJe0AANgDAAAA.Fingerlicker:BAAANQADCgcIDQAAAA==.Finnaburnya:BAAANQADCgYIBwAAAA==.Fitzwilliam:BAAANQAECgMIBQAAAA==.Fives:BAAANQAECgMIAwAAAA==.',
Fj='Fjordchi:BAAANQAECgIIAgAAAA==.',
Fl='Fluxy:BAAANQADCgYIBgAAAA==.',
Fo='Fonzie:BAAANQAECgYIBgAAAA==.Foozykinz:BAAANQADCgMIAwAAAA==.Forlorn:BAAANQAECgMIAwAAAA==.Fortsmite:BAAANQADCgUICQAAAA==.Foxicious:BAAANQAECgUIBwAAAA==.Foxjaw:BAAANQADCgIIAgAAAA==.Foxpaw:BAAANQAECgIIAgAAAA==.',
Fr='Fraggle:BAEANQADCgcIEgAAAA==.Freeza:BAAANQADCgQIBAAAAA==.Freshlock:BAAANQAECgYICgAAAA==.Frostbitë:BAAANQADCgEIAQAAAA==.Frostfires:BAAANQAECgQIBgAAAA==.Frostlawlz:BAAANQADCgUICQAAAA==.',
Fu='Fubashi:BAAANQAECgQIBwABNQAECgMIBAABAAAAAA==.Furritoo:BAAANQAECgUIBwAAAA==.Fuzzie:BAAANQADCgYICwAAAA==.',
Fy='Fyneshi:BAAANQADCgUIBQAAAA==.',
Ga='Gachiwl:BAACNQAFFIEOAAQLAAcJ9RhaAADoAQALAAUJERdaAADoAQAMAAIJrx2GAQDSAAANAAEJIBMdAgBYAAA1AAQKgRwABAwACQkqJhoBAGQDAAwACAmYJRoBAGQDAAsABgkDJTsQAIQCAA0AAgn0JR0IAOIAAAAA.Galirana:BAAANQAECgQIBQAAAA==.Gamergoo:BAAANQAECgUIBQAAAA==.Gampshwago:BAAANQAECgYICgABNQADCgIIAgABAAAAAA==.Garion:BAAANQADCgQIBAAAAA==.Garkk:BAAANQAECgIIAgAAAA==.Garronan:BAACNQAFFIEPAAMOAAcJmhkxAACeAgAOAAcJlxkxAACeAgACAAEJ8AG1CQBPAAA1AAQKgRsAAw4ACQnEJPcEADgDAA4ACAmGJPcEADgDAAIAAglsJWlxALsAAAAA.',
Ge='Geary:BAAANQAECgIIAgAAAA==.Gelina:BAAANQAECgMIAwAAAA==.Geveesa:BAAANQAECgIIAgAAAA==.',
Gi='Gibdk:BAAANQADCgIIAgABNQAECgUIBwABAAAAAA==.Gibletss:BAAANQAECgUIBwAAAA==.',
Gl='Glaivedigger:BAAANQAECgQIBgAAAA==.',
Gn='Gnual:BAAANQADCggICAABNQAECgYIEQABAAAAAA==.',
Go='Golda:BAAANQAECgUICwAAAA==.Goonerbait:BAAANQADCgIIAgAAAA==.Goragon:BAAANQAECgIIAgAAAA==.Gorkgork:BAAANQADCggICAAAAA==.',
Gr='Grass:BAAANQADCgcICQAAAA==.Grcorolla:BAAANQAECgcIDwAAAA==.Grindder:BAAANQADCgYICgAAAA==.Groshnok:BAAANQAECgIIAgAAAA==.Grunky:BAAANQAECggIDQAAAA==.',
Gu='Guanyin:BAAANQADCgUIBQAAAA==.Gustobooms:BAAANQAECgMIAwAAAA==.',
['Gì']='Gìrthquake:BAAANQAECggIEAAAAA==.',
Ha='Haiayla:BAAANQADCgcIDAAAAA==.Haleybug:BAAANQADCgUIBwAAAA==.Halyax:BAAANQADCgMIAwAAAA==.Hammerslol:BAAANQADCggICAAAAA==.Hamoron:BAAANQADCgYIBgAAAA==.',
He='Healcheck:BAAANQADCgMIBAAAAA==.Henter:BAAANQADCgUIBQAAAA==.Herm:BAAANQADCggIFAAAAA==.Hesel:BAAANQAECgIIAgAAAA==.',
Hi='Hihowareya:BAABNQAECoEZAAIPAAkJBiQxAgCYAwAPAAkJBiQxAgCYAwAAAA==.Hildegar:BAAANQAECgEIAQAAAA==.',
Ho='Hokiette:BAAANQADCggICAAAAA==.Holdmydeeps:BAAANQAECgUICAAAAA==.Holybabs:BAAANQADCgIIAgAAAA==.Horehronie:BAAANQADCggIDQAAAA==.Hosebaggins:BAAANQADCgcIDQABNQADCggICAABAAAAAA==.How:BAAANQADCgUIBQAAAA==.',
Hu='Hubbles:BAACNQAFFIEMAAIQAAYJGBBzAAAoAgAQAAYJGBBzAAAoAgA1AAQKgRsAAhAACQnJIEoEAE8DABAACQnJIEoEAE8DAAAA.Hububbles:BAAANQAECgQIBgABNQAFFAYIDAAQABgQAA==.',
Hy='Hybla:BAAANQADCgYIBgAAAA==.Hylikus:BAAANQAECgQIBQAAAA==.',
['Hë']='Hëlen:BAAANQADCgYICgAAAA==.Hëllräisër:BAAANQADCgUIBQAAAA==.',
['Hô']='Hôlystôrm:BAAANQAECgEIAQAAAA==.',
Ic='Icesaber:BAAANQAECgEIAQAAAA==.Ichigonyne:BAAANQADCgcIDwAAAA==.Iciala:BAAANQADCgMIBAAAAA==.',
Ig='Iggar:BAAANQADCgYIDAAAAA==.Igotu:BAAANQADCgcIFQAAAA==.',
Im='Imira:BAAANQADCgYIDAABNQAECgUICAABAAAAAA==.Impushpop:BAAANQADCggIEwAAAA==.Imsokool:BAAANQADCgUIBgAAAA==.Imsure:BAAANQAECgEIAQAAAA==.',
In='Indigos:BAAANQADCgUIBwAAAA==.',
Ir='Irasyn:BAAANQADCgYICwAAAA==.',
Is='Isam:BAAANQAECgQIBQAAAA==.',
Ja='Jadefire:BAAANQAECgYIBwAAAA==.Jaedemon:BAAANQAECgcIDgAAAA==.Jaysön:BAAANQADCgcIDwAAAA==.',
Je='Jebuku:BAAANQAECgMIBAAAAA==.Jenkeez:BAAANQABCgYIBgAAAA==.',
Ji='Jinxblue:BAAANQAECgQIBwAAAA==.Jiroyan:BAAANQAECgEIAQAAAA==.',
Jo='Joralö:BAAANQADCggIEgAAAA==.',
Jt='Jtvikiing:BAAANQAECgEIAgABNQAECgcIDgABAAAAAA==.',
Ju='Jubilee:BAAANQAECgYIEAAAAA==.Jumpies:BAAANQADCggIFQAAAA==.Jupiturr:BAAANQAECgMIBQAAAA==.Justian:BAAANQAECgEIAQAAAA==.Juunbroh:BAAANQAECgUICgAAAA==.',
['Jé']='Jénova:BAAANQAECgEIAQAAAA==.',
['Jö']='Jörd:BAAANQADCgMIAwAAAA==.',
Ka='Kaa:BAAANQADCgUIBQABNQAECggIBgABAAAAAA==.Kaarin:BAAANQADCgcIBwABNQAECgQIBQABAAAAAA==.Kadowe:BAAANQAECgcIDgAAAA==.Kaiyla:BAAANQADCgcICQAAAA==.Kaladinn:BAAANQAECgIIAgAAAA==.Kalintene:BAAANQADCgIIAgABNQAECgQICAABAAAAAA==.Kaonashi:BAAANQADCgcIBwAAAA==.Kargan:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Karthas:BAAANQAECgIIAgAAAA==.Kassian:BAAANQADCggICAAAAA==.Kastbeel:BAAANQADCgcIBwAAAA==.',
Ke='Keillea:BAAANQADCgcIBwABNQAECgcIEAABAAAAAA==.Keir:BAAANQAECgIIAgAAAA==.Kelsey:BAAANQADCgYICQABNQAECgMIBQABAAAAAA==.Kenny:BAAANQAECgMIAwAAAA==.Kevindurand:BAAANQABCgQIBAAAAA==.Keyanor:BAAANQAECgQIBQAAAA==.',
Kh='Khaeltharion:BAAANQAECgUICAAAAA==.Khalan:BAAANQAECgUICwAAAA==.Khavatari:BAAANQAECgUICAAAAA==.Khazidhea:BAAANQADCgQICQABNQAECgEIAQABAAAAAA==.Khazmyk:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Khazrael:BAAANQAECgEIAQAAAA==.Khazriel:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.',
Ki='Kilmanov:BAAANQAECggIBgAAAA==.Kitmeup:BAABNQAFFIEGAAIHAAUJegstAwCeAQAHAAUJegstAwCeAQAAAA==.',
Ko='Kookiez:BAAANQAECgQIBgAAAA==.Korrupshun:BAAANQAECgUIBwAAAA==.Korvian:BAAANQAECgQIBAAAAA==.',
Kr='Kro:BAAANQADCgYIDQAAAA==.',
Ky='Kynigós:BAAANQAECgIIBAAAAA==.',
Kz='Kzerg:BAAANQAECgQIBAAAAA==.',
La='Labzy:BAAANQADCgQIBAAAAA==.Laestra:BAAANQABCgIIAgAAAA==.Lamìà:BAAANQADCgcIBwAAAA==.Lavendér:BAAANQAECgUIBwAAAA==.',
Le='Leerooy:BAAANQADCgIIAgAAAA==.Leobardo:BAAANQADCggIDAAAAA==.',
Li='Lightsfury:BAAANQADCgEIAQABNQADCggIEgABAAAAAA==.Lihp:BAAANQAECgEIAQAAAA==.Liljj:BAAANQAECgIIAgAAAA==.Linndara:BAAANQADCgQIBAAAAA==.Linting:BAAANQAECgUIBwAAAA==.Lithsong:BAAANQAECgYIDgAAAA==.',
Lo='Lockthor:BAAANQAECgUIBwAAAA==.Lonie:BAAANQAECgIIAgAAAA==.Loto:BAAANQADCggICAAAAA==.',
Lu='Lucyfury:BAAANQADCgEIAQAAAA==.Luedragosa:BAAANQAECgIIAgAAAA==.Lunademon:BAAANQADCgUIBQAAAA==.Lunadk:BAAANQAECgYICAAAAA==.Luxmortae:BAAANQABCgIIAgAAAA==.Luxserena:BAAANQAECgEIAQAAAA==.Luxumbrae:BAAANQADCggICAAAAA==.',
Ly='Lysunder:BAAANQAECgIIAgAAAA==.Lythronax:BAAANQAECgQIBQAAAA==.',
['Lö']='Löwen:BAAANQAECgQICAAAAA==.',
Ma='Mackro:BAAANQADCggIDgAAAA==.Madblackjack:BAAANQADCgUICQAAAA==.Madmurph:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Maestro:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Magark:BAAANQAECgQIBAAAAA==.Mahanar:BAAANQADCgUIBQAAAA==.Maimai:BAAANQADCgYIBgAAAA==.Makandcheese:BAAANQADCgIIAQAAAA==.Malisenta:BAAANQAECgYICwAAAA==.Mallboro:BAAANQADCgQIBAAAAA==.Mardew:BAAANQAECgMIAwAAAA==.Markoramius:BAAANQAECgMIAwAAAA==.Marpew:BAAANQADCgcIDAABNQAECgMIAwABAAAAAA==.',
Me='Mekhasingh:BAAANQAECgUIBwAAAA==.Mellicanisis:BAAANQADCgMIAwAAAA==.Melvalint:BAAANQAECgQIBQAAAA==.Memademic:BAAANQAECgQIBgAAAA==.Memhuntz:BAAANQADCgUIBQAAAA==.Mendsong:BAAANQAECgUIBQAAAA==.Merlins:BAAANQAECgUICwAAAA==.Messner:BAAANQADCgcIBAAAAA==.',
Mi='Miamiganster:BAAANQAECgQIBAABNQADCgIIAgABAAAAAA==.Milestheevil:BAAANQADCgcICQAAAA==.Mindbullets:BAAANQADCgYIDQAAAA==.Mirah:BAAANQAECgQICAAAAA==.Misclick:BAAANQAECgQIBAAAAA==.',
Mm='Mmbeans:BAAANQADCgEIAQABNQAECgQICAABAAAAAA==.',
Mo='Mochabean:BAAANQAECgIIAgABNQAECgQIBQABAAAAAA==.Mochikat:BAACNQAFFIEOAAIRAAYJGhCvAAARAgARAAYJGhCvAAARAgA1AAQKgRwAAhEACQm1HZ0FADgDABEACQm1HZ0FADgDAAAA.Mogamemnon:BAAANQADCgUIBQAAAA==.Mogriya:BAAANQAECgIIAgAAAA==.Moisttank:BAAANQAECgEIAQAAAA==.Mokt:BAAANQAECgEIAQAAAA==.Mollywhop:BAAANQAECgQIBQAAAA==.Molyneaux:BAAANQADCgcIEwAAAA==.Moonpaw:BAAANQAECgEIAQAAAA==.Mooskaroo:BAAANQAECgYICwAAAA==.Moraa:BAAANQADCggIDwAAAA==.Moregoth:BAAANQADCgcIDwAAAA==.Morrows:BAAANQAECgUIBgAAAA==.Mossyoaks:BAAANQADCgYIBgAAAA==.Mossytank:BAAANQADCgUIBQAAAA==.',
Mu='Murph:BAAANQAECgIIAgAAAA==.Mutilatee:BAACNQAFFIEPAAMSAAcJ+RpEAABmAgASAAYJxhdEAABmAgATAAQJMBRJAACTAQA1AAQKgRsABBMACQkyJiAEAN8CABIABwmeJYUFAOQCABMABwnuIiAEAN8CABQAAQmgIUwOAFkAAAAA.',
My='Myeyeonu:BAAANQADCgYIDwABNQADCgcIFQABAAAAAA==.Myrollan:BAAANQADCgYIBgAAAA==.Mystampede:BAAANQAECgIIAgABNQAECgQIBAABAAAAAA==.Mystshots:BAAANQADCgcIDQAAAA==.',
['Mí']='Míra:BAAANQAECgUICwAAAA==.',
['Mø']='Møzrt:BAAANQADCggIDQAAAA==.',
Na='Nachtengel:BAAANQAECgQIBQAAAA==.Nagda:BAAANQADCgYIBgAAAA==.Naismene:BAAANQADCgcIDwAAAA==.Namswoam:BAAANQADCgIIAgAAAA==.Nate:BAAANQAECgEIAQAAAA==.Naustaire:BAAANQADCgUIBQAAAA==.Nazendrenz:BAAANQAECgYIDQAAAA==.',
Ne='Necromantic:BAAANQAECgQIBQAAAA==.Neihtdk:BAAANQAECgMIBAAAAA==.Nerissraven:BAAANQAECgMIBgAAAA==.Nesaru:BAAANQAECgMIAwAAAA==.Nesho:BAAANQADCgQIBAAAAA==.Nesse:BAAANQADCggIDQAAAA==.Nestah:BAAANQADCggIFQAAAA==.Neundorff:BAAANQADCgIIAgAAAA==.',
Ni='Niemira:BAAANQADCgQIBAAAAA==.Nightshift:BAAANQADCgIIAgAAAA==.Nightwatch:BAAANQAECgUIBgAAAA==.Niknew:BAAANQADCgIIBQAAAA==.Nisaloth:BAAANQADCggIFgAAAA==.',
No='No:BAAANQADCgEIAQAAAA==.Nonaz:BAAANQAECgIIAgAAAA==.Nonrahnu:BAAANQAECgMIAwAAAA==.Nontoxic:BAAANQAECgMIAwAAAQ==.Noodlemaker:BAAANQAECgUICAAAAA==.Noop:BAAANQADCggIGQAAAA==.Norot:BAAANQADCgYIEQAAAA==.Northcut:BAAANQAECgEIAQAAAA==.',
Nu='Nual:BAAANQAECgYIEQAAAA==.Nubur:BAAANQABCgIIAgAAAA==.Nudag:BAAANQADCgYIDwAAAA==.',
Ny='Nystanari:BAAANQAECgcIBwAAAA==.',
Oa='Oakendeath:BAAANQADCggIEwAAAA==.',
Od='Odania:BAAANQAECgYICgAAAA==.',
Ol='Older:BAAANQAECgUICwAAAA==.Olk:BAAANQAECgQIBQAAAA==.',
Om='Omari:BAAANQADCgQIBAAAAA==.',
On='Onlytotems:BAAANQADCgUIBQAAAA==.',
Oo='Oohgabooga:BAAANQAECgYIDAABNQAECgcIDAABAAAAAA==.',
Or='Oreganom:BAAANQAECgQIBAABNQAFFAcIDAALAIMZAA==.Oreganow:BAACNQAFFIEMAAQLAAcJgxlkAADfAQALAAUJDhZkAADfAQAMAAMJKiB3AAAoAQANAAEJ2g5rAgBUAAA1AAQKgRsAAwsACQmuJmAAANADAAsACQkoJWAAANADAAwACAm3JRcBAGYDAAAA.Orenghar:BAAANQAECgYICAAAAA==.',
Os='Os:BAAANQADCgcIEAAAAA==.',
Ov='Overbite:BAAANQADCgEIAQAAAA==.Overcast:BAAANQADCgcIDwAAAA==.',
Pa='Pajamajacks:BAABNQAECoEWAAIKAAgJ2R0CDgDDAgAKAAgJ2R0CDgDDAgABNQAFFAUICQAFAKcOAA==.Pallylujâh:BAEANQAECgQIBwAAAA==.Palmerz:BAAANQAECgIIAgAAAA==.Papi:BAAANQADCgQIBAABNQADCgUICAABAAAAAA==.Pardak:BAAANQADCggIFgAAAA==.Partition:BAAANQADCggIDgAAAA==.Pavlov:BAAANQAECgEIAQAAAA==.',
Pe='Pengpeng:BAAANQAECgcIDwAAAA==.Persephenie:BAAANQADCggIBwAAAA==.Pesmerga:BAAANQAECgEIAQAAAA==.Pestis:BAAANQABCgMIAwAAAA==.Pestosham:BAAANQAECgYICgAAAA==.Pestulence:BAAANQADCgMIAwAAAA==.',
Ph='Phantasm:BAAANQADCggICAAAAA==.Phil:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Philibert:BAAANQABCgQIBAAAAA==.Phriaa:BAAANQADCgQIBAABNQAECgUICAABAAAAAA==.Phungerclap:BAACNQAFFIEKAAIVAAcJpSAfAADaAgAVAAcJpSAfAADaAgA1AAQKgSQAAxUACQnEJkAAAAkEABUACQnEJkAAAAkEABYABQlnH80GANgBAAAA.',
Pi='Pikarfor:BAAANQADCgUIBQAAAA==.Pingu:BAACNQAFFIEGAAIQAAQJNxqtAQBtAQAQAAQJNxqtAQBtAQA1AAQKgRoAAhAACQmeIKQKANwCABAACQmeIKQKANwCAAAA.',
Pk='Pkspyro:BAAANQADCgYIDwAAAA==.',
Pl='Planckwar:BAAANQAECgUIBQAAAA==.',
Po='Polarexpress:BAAANQADCgQIBAAAAA==.Ponfomage:BAAANQAECgMIAwAAAA==.Ponfop:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Popicus:BAAANQADCggIEwAAAA==.Porridge:BAAANQADCgcIDAAAAA==.',
Pr='Pratz:BAAANQAECgUIBwAAAA==.Priestism:BAEANQADCgYIBgABNQAFFAcIDgAFADQbAA==.Primordikal:BAAANQAECgQIBQAAAA==.Priscillå:BAAANQAECgIIAgAAAA==.',
Pu='Pudders:BAACNQAFFIEJAAIFAAUJpw7SAQCVAQAFAAUJpw7SAQCVAQA1AAQKgRsAAgUACQmTIboFAFUDAAUACQmTIboFAFUDAAAA.Punchfist:BAAANQAECgUIBgAAAA==.',
Pw='Pwdrtoastman:BAAANQABCgYIBgAAAA==.',
Qu='Quickcast:BAAANQAECggIDAAAAA==.',
Ra='Radel:BAACNQAFFIENAAIDAAYJnBuKAAAWAgADAAYJnBuKAAAWAgA1AAQKgRsAAgMACQluJO8BAKkDAAMACQluJO8BAKkDAAAA.Radmonk:BAAANQADCgYIBgABNQAFFAYIDQADAJwbAA==.Radpal:BAAANQAFFAIIAgABNQAFFAYIDQADAJwbAA==.Radwar:BAAANQAECgYIDAAAAA==.Raesham:BAAANQADCgYIDwAAAA==.Ragemaster:BAAANQADCgQIBQAAAA==.Raginghunter:BAAANQADCgQIBAABNQADCgQIBQABAAAAAA==.Ralah:BAAANQAECgIIAgAAAA==.Ratdk:BAAANQAECgQICAAAAA==.Raydoth:BAAANQAECgIIAgAAAA==.',
Re='Redi:BAAANQADCgYIBgAAAA==.Redsaint:BAAANQADCgcIDAAAAA==.Reinys:BAAANQAECgEIAQAAAA==.Reload:BAAANQAECgIIAgABNQAECgUIBQABAAAAAA==.Renârd:BAAANQADCgcIBwAAAA==.Rezispacqt:BAAANQAECgEIAQAAAA==.',
Rh='Rheha:BAAANQADCgYIBgAAAA==.Rhizah:BAAANQAECgMIBAAAAA==.',
Ri='Richkrakbaby:BAAANQADCgcIDAAAAA==.Riskytriscut:BAAANQADCgMIAwAAAA==.Riyan:BAAANQADCggIDgAAAA==.',
Ro='Rob:BAAANQAECgEIAQAAAA==.Robinhoød:BAAANQAECgEIAQAAAA==.Rocknsham:BAAANQAECgMIAwAAAA==.Roosifer:BAAANQADCgIIAgAAAA==.Rossin:BAAANQADCggICgAAAA==.Roxington:BAAANQADCgYIDAAAAA==.',
Ry='Ryddlesr:BAAANQADCggICQAAAA==.Ryeshot:BAACNQAFFIELAAIXAAYJDh4iAABqAgAXAAYJDh4iAABqAgA1AAQKgRsAAhcACQknJl0AAOgDABcACQknJl0AAOgDAAAA.Ryukotsuei:BAAANQADCgcIEQAAAA==.Ryzonc:BAAANQABCgIIAgAAAA==.',
Sa='Sagemister:BAAANQADCgIIAgAAAA==.Sarlina:BAAANQAECgUICwAAAA==.Sarudomi:BAABNQAECoEXAAMFAAkJdSFlBwAyAwAFAAgJqyJlBwAyAwAYAAQJQwlPIADOAAAAAA==.Sarusham:BAAANQADCgIIAgAAAA==.Saruwu:BAAANQADCgQIBAAAAA==.Sarïss:BAAANQAECgUIBwAAAA==.Savviana:BAAANQADCgUIBwAAAA==.',
Sb='Sbw:BAAANQADCgQIAQABNQAECgkJGgAZAMYdAA==.',
Sc='Scalemor:BAAANQAECgUIBAAAAA==.Scales:BAAANQADCgQIBAAAAA==.Scarlah:BAAANQADCggICwAAAA==.Sciel:BAAANQADCggIEgAAAA==.Scrabbles:BAAANQAECgUIAwAAAA==.',
Se='Secretwife:BAAANQAECgUIBgAAAA==.Senara:BAAANQAECgIIAgAAAA==.Sendriss:BAAANQADCgQIBAAAAA==.Sephoniara:BAAANQAECgEIAQAAAA==.Sephonie:BAAANQADCgIIAwAAAA==.Serath:BAAANQAECgMIAwAAAA==.',
Sh='Shaded:BAAANQABCgIIAgAAAA==.Shadowfactor:BAAANQADCgcIDwAAAA==.Shadowhawks:BAAANQAECgIIAgAAAA==.Shadownej:BAAANQADCgcIEgAAAA==.Shamonlee:BAAANQAECgIIAgAAAA==.Shamydracdad:BAAANQADCgYIBgAAAA==.Shapaladin:BAAANQADCggICAAAAA==.Sheepdoll:BAAANQAECgYIDgAAAA==.Sherfin:BAAANQADCgMIAwAAAA==.Sheshindy:BAAANQAECgMIBQAAAA==.Shiftfour:BAAANQABCgEIAQAAAA==.Shiftysmom:BAAANQAECggIAwAAAA==.Shinigamì:BAAANQAECgMIAwAAAA==.Shockemilk:BAAANQABCgQIBgAAAA==.Shogun:BAAANQAECgUICAAAAA==.Shortypie:BAAANQABCgIIAgAAAA==.Shåcø:BAAANQAECgcIDgAAAA==.',
Si='Sickmoves:BAAANQADCgQIBAAAAA==.Sillypálly:BAAANQADCgQIBAAAAA==.Sinatra:BAAANQADCgEIAQAAAA==.Sindorael:BAAANQABCgMIAwAAAA==.Sinknight:BAAANQAECgMIAwAAAA==.Sithweaver:BAAANQADCgQIBAAAAA==.',
Sk='Skateorpie:BAAANQAECgMIAwAAAA==.Skeebadae:BAAANQAECgUICAAAAA==.Skelestar:BAAANQAECgUIBwAAAA==.Skrt:BAAANQADCgIIAgAAAA==.Skytanks:BAAANQADCgUIBQAAAA==.Skädir:BAAANQADCggICAABNQAECgcIDwABAAAAAA==.',
Sl='Slayabunny:BAAANQAFFAEIAgAAAA==.Slep:BAAANQAECgEIAQAAAA==.Slepybaer:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Slimzilla:BAAANQAECgcICAAAAA==.',
Sm='Smaugvoker:BAAANQADCgYICQABNQAECggIEQABAAAAAA==.Smegatron:BAAANQAECgQIBAAAAA==.',
Sn='Sneakyheals:BAAANQADCgcIEgAAAA==.Snolin:BAAANQADCgIIAgAAAA==.Snowblowwer:BAAANQADCgIIAgAAAA==.Snowyrainz:BAAANQAECgIIAwAAAA==.',
So='Soliat:BAAANQAECgQIBwAAAA==.Sooblysham:BAAANQADCggIDgAAAA==.Soulshadez:BAAANQADCggICAAAAA==.Souupded:BAAANQAECgEIAQAAAA==.',
Sp='Spamzvoltz:BAAANQADCgUIBQAAAA==.Sparklies:BAAANQADCgMIBAABNQADCgcICQABAAAAAA==.Spedometers:BAAANQAECgMIBAAAAA==.Spedometre:BAAANQADCgYIBgABNQAECgMIBAABAAAAAA==.Spee:BAAANQABCgQIBAAAAA==.Sprinkel:BAAANQADCgMIAwAAAA==.',
Sq='Squrly:BAAANQABCgIIBAAAAA==.',
Ss='Ssjryukan:BAAANQADCgUIBQAAAA==.',
St='Stacybeam:BAAANQAECgcIDwAAAA==.Standune:BAAANQADCggIAgAAAA==.Starrie:BAAANQAECgIIAgAAAA==.Staticshock:BAAANQADCgcIEQAAAA==.Stealthylick:BAAANQADCggIEwAAAA==.Stelus:BAAANQAECgIIAgAAAA==.Stereosity:BAAANQAECgQIBgABNQAECgQIBAABAAAAAA==.Stickobutter:BAAANQAECgEIAQAAAA==.Stoicism:BAAANQAECgEIAQAAAA==.',
Su='Sukuna:BAAANQAECgQIBAAAAA==.Sunai:BAAANQADCgYIEAAAAA==.Suntra:BAAANQADCgMIAwAAAA==.Supbro:BAAANQADCgMIAwAAAA==.Suspenders:BAAANQADCggIFQAAAA==.',
Sy='Sykodude:BAAANQAECgQIBgAAAA==.Sykototem:BAAANQADCgMIAwABNQAECgQIBgABAAAAAA==.Sylvanassimp:BAAANQAECgUIDAAAAA==.',
Ta='Taelil:BAAANQADCggIDAAAAA==.Tailented:BAAANQAECgUIAwAAAA==.Takdrexus:BAAANQADCgYIDAAAAA==.Tanalock:BAAANQADCggIEwAAAA==.Tanalord:BAAANQAECgQIBwABNQAECgkJGQAPAAYkAA==.Tatertot:BAAANQAECgQIBwAAAA==.',
Te='Teaswift:BAAANQADCggIEAAAAA==.Temuwhooper:BAAANQAECgQIBAAAAA==.',
Th='Thalyn:BAAANQADCgQIBAABNQAECgcIDgABAAAAAA==.Tharn:BAAANQADCgYIBgAAAA==.Thebabadook:BAAANQADCgYIBgABNQADCgYIEAABAAAAAA==.Thelonnius:BAAANQAECgMIBAAAAA==.Thornstaad:BAAANQAECgEIAgAAAA==.Thortanous:BAAANQADCgYICAAAAA==.Thrashmor:BAAANQAECgMIAwAAAA==.Throckmortus:BAAANQAECgMIAwAAAA==.Thuggymage:BAAANQAECgcIDwAAAA==.Thunderboom:BAAANQAECgUIBwAAAA==.Thundercles:BAAANQAECgEIAQAAAA==.Thunderstruk:BAAANQADCgQIBAAAAA==.Thyself:BAAANQAECgIIAgAAAA==.Thór:BAAANQADCgUIBQAAAA==.',
Ti='Tidebadra:BAAANQAECggIDAAAAA==.Tideradra:BAACNQAFFIENAAMZAAYJmRqrAADdAQAZAAUJbRmrAADdAQAQAAEJZAOiCgBJAAA1AAQKgRkAAxkACQmaJDQFAGsDABkACAkBJTQFAGsDABAACAlgDQkpANABAAAA.Ting:BAAANQAECgQIBAAAAA==.',
Tk='Tkd:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.',
To='Toats:BAAANQADCgUIBwAAAA==.Toixic:BAAANQAFFAEIAQABNQAFFAYICwAQAM0NAA==.Toixtem:BAABNQAFFIELAAIQAAYJzQ2zAAD9AQAQAAYJzQ2zAAD9AQAAAA==.Tomfoolery:BAAANQADCgQIBAAAAA==.Tootihunt:BAABNQAECoEZAAMOAAkJQSIPAwBzAwAOAAkJ5CEPAwBzAwACAAcJFx2rIwAZAgAAAA==.Topg:BAAANQADCggIEwAAAA==.Totmdispenzr:BAAANQADCgcIEgAAAA==.Toukai:BAAANQADCgYICgABNQADCgcIEwABAAAAAA==.Toukuhd:BAAANQADCgcIEwAAAA==.',
Tr='Trendz:BAAANQABCgQICQAAAA==.Trihold:BAAANQADCgEIAQAAAA==.Trog:BAAANQADCgUIBQAAAA==.',
Ts='Tselli:BAAANQAECgQIBAABNQAECgcIDwABAAAAAA==.Tsellie:BAAANQAECgcIDwAAAA==.',
Tu='Tumbler:BAAANQAECgEIAQAAAA==.Turkleton:BAAANQAECgYICQAAAA==.',
Tw='Twobelow:BAAANQADCgEIAQAAAA==.Twístedteå:BAAANQADCgcIDwAAAA==.',
Ty='Tyraxous:BAAANQAECgEIAQAAAA==.Tyrinnà:BAAANQADCgYICgAAAA==.',
['Tö']='Törryn:BAAANQAECgEIAQAAAA==.',
Ul='Ulah:BAAANQADCgcIDgAAAA==.',
Un='Unholyarrie:BAAANQADCgEIAQAAAA==.Unholybaine:BAAANQADCgIIAgAAAA==.Unknownz:BAAANQAECgYICgAAAA==.Unstopubble:BAAANQAECgUICwAAAA==.',
Us='Ushinoken:BAAANQABCgEIAQAAAA==.',
Uu='Uuchi:BAAANQAECgEIAQAAAA==.',
Va='Vaariks:BAAANQAECgIIAgAAAA==.Vaera:BAAANQADCgYIDwAAAA==.Valeindia:BAAANQADCggIDQAAAA==.Valenia:BAAANQAECggICAAAAA==.Valianthe:BAAANQAECgEIAQAAAA==.Valner:BAAANQAECgQIBAAAAA==.Valthyria:BAAANQAECgUIBwAAAA==.Vanessaboo:BAAANQAECgcICQABNQAFFAYIDAAKAN4cAA==.',
Ve='Vebel:BAAANQAECgEIAQAAAA==.Vegara:BAAANQADCgMIAwAAAA==.Velthyr:BAAANQADCgIIAgABNQADCggICAABAAAAAA==.Velínthelyn:BAAANQADCgUIBAAAAA==.Vexthall:BAAANQADCgIIAgAAAA==.',
Vi='Vikingdrood:BAAANQAECgcIDgAAAA==.Vikingj:BAAANQADCgUICAABNQAECgcIDgABAAAAAA==.Vikingsham:BAAANQADCgcIBwABNQAECgcIDgABAAAAAA==.Vinnyfr:BAABNQAECoETAAMTAAgJDhQGCABWAgATAAgJshMGCABWAgASAAYJ/QxhFwCOAQAAAA==.Viwi:BAAANQAECgIIAgAAAA==.',
Vo='Voidmelky:BAAANQADCgIIAgAAAA==.',
Wa='Warehouse:BAAANQADCgQIBgAAAA==.Warraxrage:BAAANQAECgcIEgAAAA==.Warraxsham:BAAANQADCggICAAAAA==.Watanabi:BAAANQAECgEIAQAAAA==.',
We='Welky:BAAANQADCgIIAgAAAA==.',
Wh='Wheel:BAAANQAECgMIAwAAAA==.',
Wi='Winc:BAAANQADCgIIAgAAAA==.',
Wo='Wonsmash:BAAANQADCggICwAAAA==.',
Wy='Wynndiego:BAAANQAECgQIBQAAAA==.Wyrmslayer:BAAANQAECggIDwAAAA==.',
Xa='Xaidra:BAACNQAFFIEPAAIaAAcJcgtoAABJAgAaAAcJcgtoAABJAgA1AAQKgRsAAhoACQlZHnYEAPsCABoACQlZHnYEAPsCAAAA.Xanatu:BAAANQADCggIEwAAAA==.Xandyr:BAAANQADCgUIBAAAAA==.',
Xe='Xedk:BAAANQAECgQICAAAAA==.Xepherite:BAAANQAECgQIBAABNQAECgcIEAABAAAAAA==.Xephsham:BAAANQAECgcIEAAAAA==.',
Yu='Yuimage:BAAANQAECgEIAQAAAA==.',
Za='Zaene:BAAANQADCggICAAAAA==.Zafyria:BAAANQAECgMIBgAAAA==.Zalea:BAACNQAFFIEOAAIHAAcJThwWAADOAgAHAAcJThwWAADOAgA1AAQKgR8AAgcACQntJeQAAOgDAAcACQntJeQAAOgDAAAA.',
Ze='Zekkial:BAAANQAECgUIBwAAAA==.Zendroza:BAAANQADCggIDwAAAA==.',
Zi='Zippyzapper:BAAANQAECgIIAwAAAA==.',
Zl='Zlliks:BAAANQADCgQIBAAAAA==.',
Zo='Zoekai:BAAANQADCgcIEwAAAA==.Zolar:BAAANQADCgQIBAAAAA==.Zonovar:BAAANQAECgcIDgAAAA==.',
Zu='Zurks:BAAANQAECgUICgAAAA==.Zurkz:BAAANQADCgEIAQAAAA==.',
['Zà']='Zàddy:BAAANQAECgEIAQAAAA==.',
['Äz']='Äzræll:BAAANQADCgcIEQAAAA==.',
['Ås']='Åshborn:BAAANQAECgMIAwAAAA==.',
['Ér']='Érìs:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.',
['Ði']='Ðixiewrecked:BAAANQAECgMIAgAAAA==.',
['Ðu']='Ðuck:BAAANQADCgYIDAAAAA==.',
['ßo']='ßooyeah:BAAANQADCgcIBwAAAA==.',
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
