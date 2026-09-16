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

local lookup = {'Unknown-Unknown','Warrior-Arms','Priest-Discipline','Priest-Holy','Priest-Shadow','Hunter-BeastMastery','DeathKnight-Blood','Paladin-Retribution','Paladin-Protection','DemonHunter-Devourer','DemonHunter-Vengeance','Druid-Balance','Shaman-Restoration','Shaman-Enhancement','Warrior-Fury','Rogue-Subtlety','Mage-Arcane','Evoker-Devastation','Evoker-Augmentation','DeathKnight-Frost','Hunter-Marksmanship','DeathKnight-Unholy','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Monk-Windwalker','Shaman-Elemental','DemonHunter-Havoc','Paladin-Holy','Rogue-Assassination','Rogue-Outlaw','Druid-Restoration','Mage-Frost','Warrior-Protection','Evoker-Preservation',}
local provider = {region='US',realm='Icecrown',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aaronstorm:BAAANQAECgQIBQAAAA==.',
Ac='Acesaber:BAAANQABCgIIAgAAAA==.Ackward:BAAANQAECgcIDwAAAA==.Ackwarder:BAAANQAECgQIBQABNQAECgcIDwABAAAAAA==.Acrylia:BAAANQADCgcIFgAAAA==.',
Ae='Aeryx:BAAANQAECgYIEwAAAA==.',
Ah='Ahsôka:BAAANQAECgQIBQAAAA==.',
Ak='Akisa:BAAANQADCgIIAgAAAA==.',
Al='Alagorn:BAAANQADCgcIBwAAAA==.Alinael:BAAANQADCggIEgAAAA==.Alisterr:BAAANQADCgcIDAAAAA==.Alistra:BAAANQADCggIDQAAAA==.Alynaa:BAAANQAECgUIDAAAAA==.',
Am='Amadixiechic:BAAANQADCggIDAAAAA==.Amafrey:BAAANQAECgUIDAAAAA==.Amo:BAAANQAECgcIEgAAAQ==.Amoresto:BAAANQADCgYIBgABNQAECgcIEgABAAAAAQ==.Amoret:BAAANQADCgQIBQABNQAECgcIEgABAAAAAQ==.',
An='Ancestraljr:BAAANQAECgQIBgAAAA==.Andaa:BAAANQADCgUIBQAAAA==.Andalocke:BAAANQAECgYIDAAAAA==.Andrew:BAAANQADCgQIBAAAAA==.Annalucia:BAAANQADCgEIAQAAAA==.Annboleyn:BAAANQAECgEIAQAAAA==.',
Ap='Aporkchop:BAAANQAECgEIAQAAAA==.',
Ar='Arabelle:BAAANQAECgUIDAAAAA==.Arcatraz:BAAANQADCgEIAQABNQAECgIIBAABAAAAAA==.Archurroso:BAAANQADCgUIBQAAAA==.Ares:BAAANQADCgcIDQAAAA==.Ariens:BAAANQAECgcIDAAAAA==.Arlaeya:BAAANQAECgEIAQAAAA==.Arocyra:BAAANQABCgYIDAAAAA==.Artemislux:BAAANQAECgYIEAAAAA==.Aránda:BAAANQAECgMIAwAAAA==.',
As='Astelle:BAAANQAECgYIDQAAAA==.',
At='Atagos:BAABNQAECoEZAAICAAcJQRRLUADyAQACAAcJQRRLUADyAQAAAA==.Athanor:BAAANQADCggICgABNQAECgUIBwABAAAAAA==.Atonementism:BAAANQAECgQICAABNQAECgEIAQABAAAAAA==.',
Au='Aurawa:BAAANQAECgIIAgAAAA==.Austin:BAAANQAECggIDwAAAA==.Autumnn:BAAANQADCgUIBQAAAA==.',
Av='Avannia:BAAANQADCgcICwAAAA==.Avaren:BAAANQAECgcIDwABNQAECgQIBAABAAAAAA==.Avarens:BAAANQAECgQIBAABNQAECgQIBAABAAAAAA==.Avawen:BAABNQAECoEYAAQDAAkJ6h48AQD9AgADAAgJBh88AQD9AgAEAAUJNBX8QwB3AQAFAAEJeBC5RAA8AAABNQAECgQIBAABAAAAAA==.Averyg:BAAANQADCgYIDgAAAA==.',
Aw='Awhbeans:BAAANQAECgQIBgAAAA==.',
Ax='Axtafal:BAAANQAECgQIBgAAAA==.',
Ay='Ayla:BAAANQADCgQIBAAAAA==.',
['Aá']='Aáronstorm:BAAANQADCggICgABNQAECgQIBQABAAAAAA==.',
Ba='Babaganouj:BAAANQADCgYIFQABNQADCgcIDQABAAAAAA==.Baineblood:BAAANQAECgQICQAAAA==.Bainelock:BAAANQADCgcIBwAAAA==.Bandledin:BAAANQAECgQIBAAAAA==.Barelilus:BAAANQADCgcICwAAAA==.Barthus:BAAANQAECgIIAgABNQAECgUICQABAAAAAA==.Baseballman:BAAANQADCggICAABNQAECgQIBAABAAAAAA==.Bassproshops:BAABNQAECoEfAAIGAAkJbx4cDAAeAwAGAAkJbx4cDAAeAwAAAA==.Baulder:BAAANQADCgQICAAAAA==.',
Be='Bear:BAAANQADCgEIAQABNQAFFAUIDQAHAIwmAA==.Belmyridon:BAAANQADCgcICgAAAA==.',
Bf='Bfc:BAAANQADCgUIBQAAAA==.',
Bi='Biaxident:BAAANQAECgMIBgAAAA==.Bigboy:BAAANQAECgIIAQAAAA==.Birdyy:BAAANQADCgYICgAAAA==.',
Bj='Bjorne:BAAANQAECgUICwAAAA==.',
Bl='Blammo:BAAANQADCgUIBQAAAA==.Blastoise:BAAANQAECgEIAgAAAA==.Blazter:BAAANQAECgYIDgAAAA==.Blueberryjam:BAAANQADCgYIBgABNQAECgUICgABAAAAAA==.Blututh:BAAANQAECgYIBgAAAA==.Blïght:BAAANQADCggIEwAAAA==.',
Bm='Bmjr:BAAANQAECggIDgAAAA==.',
Bo='Bodhran:BAAANQAECgMIBQAAAA==.Bombadill:BAAANQAECgEIAQAAAA==.Bonewings:BAAANQADCggICQAAAA==.Boombang:BAAANQAECgEIAQAAAA==.',
Br='Breezerk:BAAANQAECgcIEQAAAA==.Brudrushah:BAAANQADCgMIAwABNQAECgUIBgABAAAAAA==.',
Bu='Bubblebetuna:BAAANQABCgIIAgABNQABCgYIBgABAAAAAA==.Buggerella:BAAANQAECgIIAgAAAA==.Bullithead:BAAANQADCggICQAAAA==.Bulrog:BAAANQAECgcIEQAAAA==.Bumpey:BAAANQADCgUICAABNQADCggIDAABAAAAAA==.Bus:BAAANQAFFAIIBAAAAA==.Bushlite:BAAANQAECgYIEwAAAA==.',
By='Byni:BAAANQAECgIIAgAAAA==.',
['Bá']='Bádabing:BAAANQABCgQIBgAAAA==.',
Ca='Calorenn:BAAANQADCgYICgABNQAECgQICAABAAAAAA==.Caluu:BAABNQAECoEYAAMIAAkJBxmeKAByAgAIAAkJgRWeKAByAgAJAAIJsxcwLgCJAAAAAA==.Cankles:BAAANQAECgQIBwAAAA==.Canolope:BAAANQADCgYIBgABNQAECgYIDQABAAAAAA==.Catfood:BAAANQAECgcIEQAAAA==.Cattibriee:BAAANQADCgMIAwAAAA==.',
Ce='Cece:BAAANQAECgQIBAAAAA==.Celedhring:BAAANQAECgUICwAAAA==.',
Ch='Chaktaw:BAAANQAECgYICwAAAA==.Chatubaholy:BAAANQAECgQIBQAAAA==.Chayito:BAABNQAECoEbAAMKAAgJLBj+HADyAQAKAAYJxR3+HADyAQALAAUJUQxMCwASAQAAAA==.Cheezi:BAAANQAECgQIBAAAAA==.Chickenism:BAECNQAFFIEUAAIMAAcJSiBGAADLAgAMAAcJSiBGAADLAgA1AAQKgScAAgwACQkyJkkAAAIEAAwACQkyJkkAAAIEAAAA.Chiknsmoothi:BAAANQADCgYICwAAAA==.Chirpa:BAAANQADCgMIAwAAAA==.Chiwallow:BAAANQAECgQIBAAAAA==.Chloe:BAAANQAECgQIBAAAAA==.Chowtime:BAAANQAECgYIDQAAAA==.Chromium:BAAANQAECgUIBwAAAA==.Chrysanthia:BAAANQADCgEIAQAAAA==.',
Ci='Cinderstorm:BAAANQADCgYICQAAAA==.Cirilla:BAAANQABCgIIAgAAAA==.Citronia:BAAANQADCggICQAAAA==.',
Cl='Clamps:BAABNQAECoEWAAMNAAgJ8iDKEwC6AgANAAgJ8iDKEwC6AgAOAAEJ/AVsIAA6AAAAAA==.Clandmage:BAAANQAECgYIBgAAAA==.Clandon:BAACNQAFFIEWAAIDAAcJ0x8HAADkAgADAAcJ0x8HAADkAgA1AAQKgSYAAgMACQnVJgQAAA8EAAMACQnVJgQAAA8EAAAA.Claxton:BAABNQAECoEVAAMPAAgJ7AxGBgDVAQAPAAgJ7AxGBgDVAQACAAEJ0waW2QAzAAAAAA==.Clomari:BAAANQAECgYICwAAAA==.',
Co='Cole:BAAANQADCgcIBwAAAA==.Commietotem:BAAANQAECgEIAgAAAA==.Concepts:BAAANQAECgcIEgAAAA==.Costcomember:BAAANQADCgcICQAAAA==.',
Cr='Crashout:BAAANQAECgEIAQAAAA==.Cron:BAAANQADCgcIBwAAAA==.Croneos:BAAANQAECgEIAQAAAA==.Cross:BAAANQAECgYIDgAAAA==.',
Cu='Cudz:BAAANQADCgcIEgAAAA==.Curl:BAAANQAECgEIAgAAAA==.',
Cy='Cyn:BAAANQADCgEIAQAAAA==.Cytanous:BAAANQADCgYICwAAAA==.',
Da='Daddydeath:BAAANQAECgUICgAAAA==.Dadrex:BAAANQADCgMIAwAAAA==.Dagonfive:BAAANQAECgMIAwAAAA==.Dahrla:BAAANQAECgMIBQAAAA==.Daisyann:BAAANQAECgMICAAAAA==.Dallasx:BAAANQADCgUIBQAAAA==.Dalmarr:BAAANQADCgcIFwAAAA==.Dancouga:BAABNQAECoEZAAIQAAcJjQvYFwDGAQAQAAcJjQvYFwDGAQAAAA==.Darkdarius:BAAANQADCgUICAAAAA==.Darthmaulus:BAAANQAECgMIAwABNQAECgQIBwABAAAAAA==.Daruncic:BAAANQAECgQIBwAAAA==.Dave:BAAANQAECgUICgAAAA==.Dawnchatters:BAAANQADCgQIBAAAAA==.Dawntodusk:BAAANQADCgYIBgAAAA==.Daymia:BAAANQAECgQIBgAAAA==.Dazknight:BAAANQAECgUICgAAAA==.Dazshaman:BAAANQADCggIFAABNQAECgUICgABAAAAAA==.',
De='Deadion:BAAANQAECgQIBwAAAQ==.Deadpaly:BAAANQADCgMIAwABNQAECgQIBwABAAAAAQ==.Deadspinwin:BAAANQADCgIIAgABNQAECgQIBwABAAAAAQ==.Dearmage:BAAANQAECgYIDQAAAA==.Deathgripz:BAAANQADCgYIEwAAAA==.Decormei:BAAANQAECgUICwAAAA==.Dedman:BAAANQABCgQIAwAAAA==.Deltatoast:BAAANQADCgQICAAAAA==.Demera:BAAANQAECgQIBAAAAA==.Demolack:BAAANQADCgIIBgAAAA==.Destheleye:BAAANQADCgMIAwAAAA==.Dethnyte:BAAANQAECgIIAgAAAA==.',
Di='Diaf:BAABNQAECoEdAAIRAAcJZBGNhAC+AQARAAcJZBGNhAC+AQAAAA==.Diniwen:BAAANQAECgYICgAAAA==.Dirtbikes:BAAANQAECgYICQAAAA==.Discordmod:BAAANQAECgQIBAAAAA==.Dithia:BAAANQAECgUICgAAAA==.Divided:BAAANQAECgMIAwAAAA==.Division:BAAANQAECgcIEAAAAA==.',
Dj='Djparrot:BAAANQAECgMIBAAAAA==.',
Do='Domrï:BAAANQAECgYICgAAAA==.Donkayslayer:BAAANQAECgQIBgAAAA==.Donlock:BAAANQAECgUIBQAAAA==.Doohoo:BAAANQAECgIIBAAAAA==.Dordrel:BAAANQADCgEIAQAAAA==.Downpour:BAAANQAECgcICwAAAA==.',
Dr='Dracdad:BAAANQADCgEIAQABNQADCggIDgABAAAAAA==.Draevon:BAAANQADCgQICAABNQAECgUIDAABAAAAAA==.Dragondnutz:BAAANQAECgIIAgAAAA==.Dragoness:BAAANQADCgQIBAAAAA==.Dragonflight:BAAANQAECgUIBwAAAA==.Drakloak:BAACNQAFFIEMAAMSAAYJdR1VAAAwAgASAAYJ9RlVAAAwAgATAAIJdRYnAgDPAAA1AAQKgRwAAxIACQmSJF8BAJUDABIACQmSJF8BAJUDABMAAgneGf8NAJQAAAAA.Drclaw:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.Drench:BAAANQAECgUICQAAAA==.',
Du='Duckdodger:BAAANQADCgIIAgAAAA==.Durota:BAAANQADCggIEAAAAA==.',
Dv='Dv:BAAANQADCggIDgAAAA==.',
Dz='Dzasterpiece:BAACNQAFFIEKAAMUAAYJzROuAACzAQAUAAUJWBOuAACzAQAHAAEJGhbREQBCAAA1AAQKgSUAAxQACQmWIrQBAKYDABQACQmWIrQBAKYDAAcAAQnhDId/ADkAAAAA.',
['Dà']='Dàmnàtion:BAAANQADCgEIAQAAAA==.',
['Dä']='Däemarcus:BAAANQAECgQIBQAAAA==.',
Ec='Ectyxx:BAABNQAECoEYAAIRAAkJAx+VJAAAAwARAAkJAx+VJAAAAwAAAA==.',
Ed='Edris:BAAANQADCggIEwAAAA==.',
Ef='Effört:BAAANQADCggIEQAAAA==.',
Ei='Eightlug:BAAANQAECgEIAQAAAA==.',
El='Elareis:BAAANQADCgQICgAAAA==.Elebits:BAAANQADCgIIBAABNQAECgkJJAAGAIgeAA==.Eluned:BAAANQAECgMIBQAAAA==.Elwynn:BAAANQAECgcIDgAAAQ==.Elycia:BAAANQADCgYICwAAAA==.',
Em='Emosmaug:BAABNQAECoEXAAIKAAkJCB0ZCgD8AgAKAAkJCB0ZCgD8AgAAAA==.',
En='Enkistral:BAAANQAECgMIAwABNQAFFAIIAgABAAAAAA==.Envi:BAAANQAECgMIBAAAAA==.',
Er='Eretar:BAAANQADCgUIBQAAAA==.Erotaph:BAAANQAECgQIBAAAAA==.',
Es='Esoteric:BAAANQAECgYICQAAAA==.',
Eu='Euron:BAAANQAECgQIBQAAAA==.',
Ev='Evach:BAABNQAECoEbAAMVAAkJgR+oEgBcAgAVAAgJaB+oEgBcAgAGAAIJrRuiqgCOAAAAAA==.Everblight:BAAANQADCgYICwAAAA==.',
Fa='Facex:BAAANQADCggIDQAAAA==.Faelor:BAAANQADCggIEwAAAA==.Faet:BAAANQAECgYIDQAAAA==.Faeyt:BAAANQAECgQIBwAAAA==.Fakename:BAAANQAECgMIAwAAAA==.Fatkokmage:BAAANQADCggIDAAAAA==.',
Fc='Fcawfng:BAAANQADCgUIBwAAAA==.',
Fe='Felakai:BAAANQADCgcIEwAAAA==.',
Fi='Fidgetspinna:BAAANQADCgIIAgAAAA==.Finaljudgmnt:BAAANQADCgIIAgABNQAECgYIDQABAAAAAA==.Finesthour:BAACNQAFFIEQAAMWAAYJJh89AAAiAgAWAAUJQSE9AAAiAgAHAAEJmxSMEgA8AAA1AAQKgSQAAhYACQl8Jj4AAAkEABYACQl8Jj4AAAkEAAAA.Fingerlicker:BAAANQADCgcIDQAAAA==.Finnaburnya:BAAANQADCgYIBwAAAA==.Finnacreep:BAAANQADCgcIBwAAAA==.Fitzwilliam:BAAANQAECgQICAAAAA==.Fives:BAAANQAECgMIBgAAAA==.',
Fj='Fjordchi:BAAANQAECgQIBgAAAA==.',
Fl='Fluxy:BAAANQADCgYIBgAAAA==.',
Fo='Fonzie:BAAANQAECgcICgAAAA==.Foozykinz:BAAANQADCgMIAwAAAA==.Forlorn:BAAANQAECgQIBwAAAA==.Fortsmite:BAAANQADCgUICQAAAA==.Foxicious:BAAANQAECgYIDQAAAA==.Foxjaw:BAAANQADCgIIAgAAAA==.Foxpaw:BAAANQAECgYIDQAAAA==.',
Fr='Fraggle:BAEANQADCgcIGQAAAA==.Freeza:BAAANQADCgQIBAAAAA==.Freshlock:BAAANQAECgYIEAAAAA==.Frostbitë:BAAANQADCgEIAQAAAA==.Frostfires:BAAANQAECgQICgAAAA==.Frostlawlz:BAAANQADCgUICQAAAA==.',
Fu='Fubashi:BAAANQAECgYIDgABNQAECgUICQABAAAAAA==.Furritoo:BAAANQAECgYIDQAAAA==.Fuzzie:BAAANQADCgYIDgAAAA==.',
Fy='Fyneshi:BAAANQADCgUIBQAAAA==.',
Ga='Gachiwl:BAACNQAFFIEVAAQXAAcJvxpXAAA/AgAXAAYJOBpXAAA/AgAYAAIJFCB2AgDNAAAZAAEJqBM9BABRAAA1AAQKgSUABBgACQk1JmwBAFYDABgACAmYJWwBAFYDABkABwncJdUAABQDABcABgkDJUYfAHQCAAAA.Galirana:BAAANQAECgQIBwAAAA==.Gamergoo:BAAANQAECgYICwAAAA==.Gampshwago:BAAANQAECgYICgABNQADCgQIBAABAAAAAA==.Garion:BAAANQADCgQIBAAAAA==.Garkk:BAAANQAECgYICAAAAA==.Garronan:BAACNQAFFIEWAAMVAAcJFBxnAACGAgAVAAcJCBtnAACGAgAGAAEJLgngDQBiAAA1AAQKgSQAAxUACQkqJe0EAFEDABUACAn5JO0EAFEDAAYAAglsJcWhALMAAAAA.',
Ge='Geary:BAAANQAECgQIBgAAAA==.Gelina:BAAANQAECgYICQAAAA==.Geveesa:BAAANQAECgQIBgAAAA==.',
Gi='Gibdk:BAAANQADCgIIAgABNQAECgYIDQABAAAAAA==.Gibletss:BAAANQAECgYIDQAAAA==.',
Gl='Glaivedigger:BAAANQAECgQICQAAAA==.',
Go='Golda:BAABNQAECoEZAAIaAAcJRwxkGgCKAQAaAAcJRwxkGgCKAQAAAA==.Goonerbait:BAAANQADCgIIAgAAAA==.Goragon:BAAANQAECgQIBgAAAA==.Gorkgork:BAAANQADCggICAAAAA==.',
Gr='Grass:BAAANQADCgcICgAAAA==.Grcorolla:BAABNQAECoEaAAICAAkJCCV1BQCuAwACAAkJCCV1BQCuAwAAAA==.Grindder:BAAANQADCgYICgAAAA==.Groshnok:BAAANQAECgQIBgAAAA==.Grunky:BAAANQAECggIEwAAAA==.',
Gu='Guanyin:BAAANQADCgUIBQAAAA==.Gustobooms:BAAANQAECgMIAwAAAA==.',
Gw='Gwantanamata:BAAANQADCggICAAAAA==.',
['Gì']='Gìrthquake:BAABNQAECoEZAAIbAAkJtCCsCgBIAwAbAAkJtCCsCgBIAwAAAA==.',
Ha='Haiayla:BAAANQADCgcIDAAAAA==.Haleybug:BAAANQADCgUIBwAAAA==.Halyax:BAAANQAECgQIBAAAAA==.Hammerslol:BAAANQADCggICAAAAA==.Hamoron:BAAANQADCgYIBgAAAA==.',
He='Healcheck:BAAANQADCgMIBAAAAA==.Henter:BAAANQADCgUIBQAAAA==.Herm:BAAANQAECgEIAQAAAA==.Hesel:BAAANQAECgIIAwAAAA==.',
Hi='Hihowareya:BAABNQAECoEiAAIKAAkJWyY0AAAHBAAKAAkJWyY0AAAHBAAAAA==.Hildegar:BAAANQAECgUIBgAAAA==.',
Ho='Hokiette:BAAANQAECgQIBAAAAA==.Holdmydeeps:BAAANQAECgUIDAAAAA==.Holybabs:BAAANQADCgIIAgAAAA==.Horehronie:BAAANQADCggIFQAAAA==.Hosebaggins:BAAANQADCgcIDQABNQAECgQIBAABAAAAAA==.How:BAAANQADCgUIBQAAAA==.',
Hu='Hubbles:BAACNQAFFIESAAINAAcJBQ+TAABfAgANAAcJBQ+TAABfAgA1AAQKgSQAAg0ACQncIX8HAD8DAA0ACQncIX8HAD8DAAAA.Hububbles:BAAANQAECgQIBgABNQAFFAcIEgANAAUPAA==.',
Hy='Hybla:BAAANQADCgYIBgAAAA==.Hylikus:BAAANQAECgUICgAAAA==.',
['Hë']='Hëlen:BAAANQADCgYICgAAAA==.Hëllräisër:BAAANQADCgUIBQAAAA==.',
['Hô']='Hôlystôrm:BAAANQAECgIIAwAAAA==.',
Ic='Icesaber:BAAANQAECgQIBQAAAA==.Ichigonyne:BAAANQADCgcIFgAAAA==.Iciala:BAAANQADCgMIBAAAAA==.',
Ig='Iggar:BAAANQADCggIFAAAAA==.Igotu:BAAANQAECgEIAQAAAA==.',
Im='Imira:BAAANQADCgYIDAABNQAECgUIDAABAAAAAA==.Impushpop:BAAANQADCggIGAAAAA==.Imsokool:BAAANQADCgcIDQAAAA==.Imsure:BAAANQAECgMIBAAAAA==.',
In='Indigos:BAAANQADCgYIDQAAAA==.Ineedhelp:BAAANQAECggIAQAAAA==.',
Ir='Irasyn:BAAANQADCgYICwAAAA==.',
Is='Isam:BAAANQAECgQIBQAAAA==.',
Ja='Jadefire:BAAANQAECgcIDgAAAA==.Jaedemon:BAABNQAECoEYAAIcAAkJgxnwCgDfAgAcAAkJgxnwCgDfAgAAAA==.Jaysön:BAAANQADCgcIDwAAAA==.',
Je='Jebuku:BAAANQAECgUICQAAAA==.Jenkeez:BAAANQABCggICAAAAA==.Jetpakmonkey:BAAANQADCgcIBwAAAA==.',
Ji='Jinxblue:BAAANQAECgQIBwAAAA==.Jiroyan:BAAANQAECgEIAgAAAA==.',
Jo='Joralö:BAAANQADCggIEgAAAA==.',
Jt='Jtvikiing:BAAANQAECgEIAgABNQAECggIEwAMAMIZAA==.',
Ju='Jubilee:BAABNQAECoEZAAMUAAcJphK8GwCtAQAUAAcJPBG8GwCtAQAWAAYJfAzfQgBOAQAAAA==.Jumpies:BAAANQAECgQIBAAAAA==.Jupiturr:BAAANQAECgMIBQAAAA==.Justian:BAAANQAECgEIAQAAAA==.Juunbroh:BAABNQAECoEYAAIdAAcJzQ81QQCtAQAdAAcJzQ81QQCtAQAAAA==.',
['Jé']='Jénova:BAAANQAECgEIAQAAAA==.',
['Jö']='Jörd:BAAANQADCgMIAwAAAA==.',
Ka='Kaa:BAAANQADCgUIBQABNQAECggICgABAAAAAA==.Kaarin:BAAANQADCgcIBwABNQAECgQIBwABAAAAAA==.Kadowe:BAABNQAECoEWAAIRAAgJwx0sKwDkAgARAAgJwx0sKwDkAgAAAA==.Kaiyla:BAAANQADCgcICQAAAA==.Kaladinn:BAAANQAECgIIBAAAAA==.Kalintene:BAAANQADCgIIAgABNQAECgQIDAABAAAAAA==.Kalpanda:BAAANQADCgcIDQABNQAECgYICwABAAAAAA==.Kaonashi:BAAANQADCgcIBwAAAA==.Kargan:BAAANQAECgIIAwABNQAECgQIBgABAAAAAA==.Karma:BAAANQADCgcICwAAAA==.Karthas:BAAANQAECgQIBgAAAA==.Kassian:BAAANQAECgQIBAAAAA==.Kastbeel:BAAANQADCgcIBwAAAA==.Kayhana:BAAANQADCgUIBQAAAA==.',
Ke='Keillea:BAAANQADCgcIDgABNQAECggIGwAOAH4eAA==.Keir:BAAANQAECgQIBgAAAA==.Kelsey:BAAANQADCgYICQABNQAECgMIBwABAAAAAA==.Kenny:BAAANQAECgMIBQAAAA==.Kevindurand:BAAANQABCgQIBAAAAA==.Keyanor:BAAANQAECgQIBQAAAA==.',
Kh='Khaeltharion:BAAANQAECgUIDAAAAA==.Khalan:BAAANQAECgUIEAAAAA==.Khavatari:BAAANQAECgYIDgAAAA==.Khazidhea:BAAANQADCgQICgABNQAECgIIAwABAAAAAA==.Khazmyk:BAAANQADCgIIAgABNQAECgIIAwABAAAAAA==.Khazrael:BAAANQAECgIIAwAAAA==.Khazriel:BAAANQADCgcICwABNQAECgIIAwABAAAAAA==.',
Ki='Killig:BAAANQABCgIIAgAAAA==.Kilmanov:BAAANQAECggIBgAAAA==.Kitmeup:BAABNQAFFIEMAAIRAAYJbhPYAgARAgARAAYJbhPYAgARAgAAAA==.',
Ko='Kookiez:BAAANQAECgYIDQAAAA==.Korbane:BAAANQADCgUIBQAAAA==.Korrupshun:BAAANQAECgYIDQAAAA==.Korvian:BAAANQAECgUICQAAAA==.Kozzyy:BAAANQADCgIIAgAAAA==.',
Kr='Kraizy:BAAANQAECgYIBgABNQAECgkJHQAIAMUgAA==.Kro:BAAANQADCgYIDQAAAA==.Krymsy:BAAANQAECgQIBAAAAA==.',
Ky='Kynigós:BAAANQAECgUIDQAAAA==.',
Kz='Kzerg:BAAANQAECgQIBwAAAA==.',
La='Labzy:BAAANQADCgQIBAAAAA==.Laestra:BAAANQABCgIIAgAAAA==.Lalinthor:BAAANQADCgEIAQAAAA==.Lamìà:BAAANQADCgcIBwABNQAECgUICAABAAAAAA==.Lavendér:BAAANQAECgYICgAAAA==.',
Le='Leerooy:BAAANQADCgIIAgAAAA==.Leobardo:BAAANQADCggIDAAAAA==.',
Li='Lightsfury:BAAANQADCgEIAQABNQAECgMIAwABAAAAAA==.Lihp:BAAANQAECgMIAwAAAA==.Liljj:BAAANQAECgIIAgAAAA==.Linndara:BAAANQADCgQIBAAAAA==.Linting:BAAANQAECgYIDQAAAA==.Lithsong:BAABNQAECoEYAAMHAAgJDCLVCgAJAwAHAAgJDCLVCgAJAwAWAAIJSgJMdwBNAAAAAA==.',
Lo='Lockthor:BAAANQAECgYIDQAAAA==.Lonie:BAAANQAECgQIBgAAAA==.Loto:BAAANQADCggICAAAAA==.',
Lu='Lucyfury:BAAANQADCgEIAQAAAA==.Luedragosa:BAAANQAECgQICgAAAA==.Lunademon:BAAANQADCgUIBQAAAA==.Lunadk:BAAANQAECgcIDwAAAA==.Luxmortae:BAAANQABCgIIAgAAAA==.Luxserena:BAAANQAECgEIAQAAAA==.Luxumbrae:BAAANQAECgMIAwAAAA==.',
Ly='Lynthara:BAAANQADCgYIBgAAAA==.Lysunder:BAAANQAECgQIBgAAAA==.Lythronax:BAAANQAECgUICgAAAA==.',
['Lö']='Löwen:BAAANQAECgUICwAAAA==.',
Ma='Mackro:BAAANQADCggIDgAAAA==.Madblackjack:BAAANQADCgUICQAAAA==.Madmurph:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Maestro:BAAANQAECgQIBgAAAA==.Magark:BAAANQAECgQIBAAAAA==.Mahanar:BAAANQADCgcICAAAAA==.Maimai:BAAANQADCgcICQAAAA==.Makandcheese:BAAANQADCgIIAQAAAA==.Malisenta:BAAANQAECgcIEQAAAA==.Mallboro:BAAANQADCgQIBAAAAA==.Mardew:BAAANQAECgUICAAAAA==.Markoramius:BAAANQAECgQIBwAAAA==.Marpew:BAAANQADCgcIDAABNQAECgUICAABAAAAAA==.',
Me='Mekhasingh:BAAANQAECgcICwAAAA==.Mellicanisis:BAAANQADCgMIAwAAAA==.Melvalint:BAAANQAECgQIBwAAAA==.Memademic:BAAANQAECgYIDAAAAA==.Memhuntz:BAAANQADCgUIBQAAAA==.Mendsong:BAAANQAECgUICAAAAA==.Merlins:BAABNQAECoEaAAIXAAcJkRcnLQAmAgAXAAcJkRcnLQAmAgAAAA==.Messner:BAAANQAECgIIAgAAAA==.',
Mi='Miamiganster:BAAANQAFFAMIAwABNQADCgQIBAABAAAAAA==.Milestheevil:BAAANQADCgcICQAAAA==.Mindbullets:BAAANQADCgYIDgAAAA==.Mirah:BAAANQAECgYIDQAAAA==.Misclick:BAAANQAECgUICAAAAA==.',
Mm='Mmbeans:BAAANQAECgEIAQABNQAECgUIDQABAAAAAA==.',
Mo='Mochabean:BAAANQAECgIIAgABNQAECgQICQABAAAAAA==.Mochikat:BAACNQAFFIETAAIdAAYJFxJiAQAFAgAdAAYJFxJiAQAFAgA1AAQKgSUAAh0ACQleIjgDAJADAB0ACQleIjgDAJADAAAA.Mogamemnon:BAAANQADCgUIBQAAAA==.Mogriya:BAAANQAECgIIBAAAAA==.Moisttank:BAAANQAECgEIAQAAAA==.Mokt:BAAANQAECgEIAgAAAA==.Mollywhop:BAAANQAECgUICgAAAA==.Molyneaux:BAAANQAECgQIBAAAAA==.Moonpaw:BAAANQAECgMIBQAAAA==.Mooskaroo:BAAANQAECgcIEgAAAA==.Moraa:BAAANQADCggIFwAAAA==.Moregoth:BAAANQAECgMIAwAAAA==.Morrows:BAAANQAECgUIBgAAAA==.Mossyoaks:BAAANQADCggICAAAAA==.Mossytank:BAAANQADCgUIBQAAAA==.Mossywarrior:BAAANQADCgEIAQAAAA==.',
Mu='Muggle:BAAANQADCgcIBwAAAA==.Multiply:BAAANQAECgIIAgAAAA==.Murph:BAAANQAECgIIAgAAAA==.Murphgoat:BAAANQAECgQIBAAAAA==.Mutilatee:BAACNQAFFIEVAAMQAAcJjiFwAABoAgAQAAYJDR1wAABoAgAeAAQJHhkEAQCRAQA1AAQKgSQABB4ACQm8JvAGAOcCABAABwnMJQYGAPUCAB4ABwmYI/AGAOcCAB8AAQmgIY0RAFQAAAAA.',
My='Myeyeonu:BAAANQADCgYIFAABNQAECgEIAQABAAAAAA==.Myrollan:BAAANQADCgYIBgAAAA==.Mystampede:BAAANQAECgMIBAABNQAECgQIBAABAAAAAA==.Mystshots:BAAANQAECgYICwAAAA==.Myysteria:BAAANQADCggICAAAAA==.',
['Mí']='Míra:BAABNQAECoEZAAIHAAcJniRbDQDnAgAHAAcJniRbDQDnAgAAAA==.',
['Mø']='Møzrt:BAAANQADCggIFQABNQAECgYIBgABAAAAAA==.',
Na='Nachtengel:BAAANQAECgUICgAAAA==.Nagda:BAAANQADCgYIBgAAAA==.Naismene:BAAANQAECgIIAgAAAA==.Namswoam:BAAANQADCgQIBAAAAA==.Nate:BAAANQAECgEIAQAAAA==.Naustaire:BAAANQADCgUIBQAAAA==.Nazendrenz:BAABNQAECoEbAAMXAAcJXCTbIABqAgAXAAYJKiTbIABqAgAYAAQJ5xEGIwAhAQAAAA==.',
Ne='Necromantic:BAAANQAECgUICgAAAA==.Neihtdk:BAAANQAECgUICAAAAA==.Nerissraven:BAAANQAECgMICQAAAA==.Nesaru:BAAANQAECgQIBwAAAA==.Nesho:BAAANQADCgQIBAAAAA==.Nesse:BAAANQADCggIDQAAAA==.Nestah:BAAANQAECgQIBAAAAA==.Neundorff:BAAANQADCgIIAgAAAA==.',
Ni='Niemira:BAAANQADCgQIBAAAAA==.Nightshift:BAAANQADCgIIAgAAAA==.Nightwatch:BAAANQAECgYIDAAAAA==.Niknew:BAAANQADCgMIBgAAAA==.Nisaloth:BAAANQAECgEIAQAAAA==.',
No='No:BAAANQADCgEIAQAAAA==.Nonaz:BAAANQAECgIIAgAAAA==.Nonrahnu:BAAANQAECgMIAwAAAA==.Nontoxic:BAAANQAECgMIAwAAAQ==.Noodlemaker:BAAANQAECgcIDQAAAA==.Noop:BAAANQADCggIJwAAAA==.Norot:BAAANQADCgcIGAAAAA==.Northcut:BAAANQAECgEIAQAAAA==.Nozomga:BAEANQABCgIIAwAAAA==.',
Nu='Nual:BAABNQAECoEcAAIFAAgJIRkIDwB7AgAFAAgJIRkIDwB7AgAAAA==.Nubur:BAAANQABCgIIAgAAAA==.Nudag:BAAANQAECgQIBAAAAA==.Nukelele:BAAANQADCggICAAAAA==.',
Ny='Nystanari:BAAANQAECgcIDAAAAA==.',
['Nï']='Nïghtmare:BAAANQADCgIIAwAAAA==.',
Oa='Oakendeath:BAAANQADCggIEwAAAA==.',
Od='Odania:BAAANQAECggIEAAAAA==.',
Ol='Older:BAABNQAECoEZAAIgAAcJ7iQzBgDxAgAgAAcJ7iQzBgDxAgAAAA==.Olk:BAAANQAECgUICgAAAA==.',
Om='Omari:BAAANQADCgQIBAAAAA==.',
On='Onlytotems:BAAANQADCgUIBQAAAA==.',
Oo='Oohgabooga:BAAANQAECgcIDgABNQAFFAEIAQABAAAAAA==.',
Or='Oreganom:BAAANQAECgQICAABNQAFFAcIEgAXADoeAA==.Oreganow:BAACNQAFFIESAAQXAAcJOh5iAAA2AgAXAAYJTxliAAA2AgAYAAMJmSDcAAAeAQAZAAEJ5SLaAQBnAAA1AAQKgSQABBcACQm1Jo0AAN8DABcACQnkJY0AAN8DABgACAm4JUoBAF8DABkAAgnRJXALAOAAAAAA.Orenghar:BAAANQAECgYIDgAAAA==.',
Os='Os:BAAANQADCgcIEAAAAA==.',
Ov='Overbite:BAAANQADCgEIAQAAAA==.Overcast:BAAANQADCggIEAAAAA==.',
Pa='Pajamajacks:BAABNQAECoEdAAIWAAgJ7R57EADTAgAWAAgJ7R57EADTAgABNQAFFAYIDwAMAKQVAA==.Pallylujâh:BAEANQAECgQICwAAAA==.Palmerz:BAAANQAECgIIAgAAAA==.Papi:BAAANQADCggIDAAAAA==.Papy:BAAANQADCgMIAwAAAA==.Pardak:BAAANQAECgEIAQAAAA==.Partition:BAAANQAECgEIAQAAAA==.Pavlov:BAAANQAECgEIAQAAAA==.',
Pe='Pengpeng:BAABNQAECoEbAAMRAAkJAg5yWwA2AgARAAkJAg5yWwA2AgAhAAEJggvBJgA6AAAAAA==.Perryy:BAAANQAECgEIAQAAAA==.Persephenie:BAAANQADCggIBwAAAA==.Pesmerga:BAAANQAECgEIAQAAAA==.Pestis:BAAANQABCgMIAwAAAA==.Pestosham:BAAANQAECgYICgAAAA==.Pestulence:BAAANQADCgMIAwAAAA==.',
Ph='Phantasm:BAAANQADCggICAAAAA==.Phil:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.Philibert:BAAANQABCgcICQAAAA==.Phriaa:BAAANQAECgIIAgABNQAECgUIDAABAAAAAA==.Phungerclap:BAACNQAFFIELAAICAAcJmiKHAAC8AgACAAcJmiKHAAC8AgA1AAQKgSkAAwIACQndJqEAAP8DAAIACQndJqEAAP8DACIABQlnH1kKAMsBAAAA.',
Pi='Pikarfor:BAAANQAECgUIBwAAAA==.Pingu:BAACNQAFFIEMAAINAAYJ9xUaAQAeAgANAAYJ9xUaAQAeAgA1AAQKgSMAAg0ACQkMI0QFAGMDAA0ACQkMI0QFAGMDAAAA.',
Pk='Pkspyro:BAAANQAECgQIBAAAAA==.',
Pl='Planckshock:BAAANQADCgIIAgABNQAFFAYIDAASABchAA==.Planckwar:BAAANQAECggICgAAAA==.',
Po='Polarexpress:BAAANQADCggICgAAAA==.Ponfomage:BAAANQAECgQIBwAAAA==.Ponfop:BAAANQAECgIIBAABNQAECgQIBwABAAAAAA==.Popicus:BAAANQADCggIEwAAAA==.Porridge:BAAANQAECgIIAgAAAA==.',
Pr='Pratz:BAAANQAECgYIDQAAAA==.Priestism:BAEANQADCgYIBgABNQAFFAcIFAAMAEogAA==.Primordikal:BAAANQAECgYICwAAAA==.Priscillå:BAAANQAECgQIBAAAAA==.',
Pu='Pudders:BAACNQAFFIEPAAIMAAYJpBWtAQAQAgAMAAYJpBWtAQAQAgA1AAQKgR8AAgwACQlXIzIJAEkDAAwACQlXIzIJAEkDAAAA.Punchfist:BAAANQAECgUIBwAAAA==.Puppy:BAAANQABCgcICgAAAA==.',
Pw='Pwdrtoastman:BAAANQABCggICAAAAA==.',
Qu='Quartzviper:BAAANQADCgYICQAAAA==.Quickcast:BAABNQAECoEYAAIRAAkJSh8MHAAoAwARAAkJSh8MHAAoAwAAAA==.',
Ra='Radel:BAACNQAFFIETAAIHAAYJoBwqAQAfAgAHAAYJoBwqAQAfAgA1AAQKgSQAAgcACQkLJUgCALgDAAcACQkLJUgCALgDAAAA.Radlyn:BAAANQAECgUIBQABNQAFFAYIEwAHAKAcAA==.Radmonk:BAAANQADCgYIBgABNQAFFAYIEwAHAKAcAA==.Radpal:BAABNQAECoEYAAIJAAkJ7Q76FgBjAQAJAAkJ7Q76FgBjAQABNQAFFAYIEwAHAKAcAA==.Radwar:BAAANQAECggIDgAAAA==.Raesham:BAAANQADCgYIFQAAAA==.Ragemaster:BAAANQADCgUIBgAAAA==.Raginghunter:BAAANQADCgQIBAABNQADCgUIBgABAAAAAA==.Raidbuff:BAAANQAECgIIAgAAAA==.Ralah:BAAANQAECgQIBgAAAA==.Ratdk:BAAANQAECgUIDQAAAA==.Raydoth:BAAANQAECgQIBQAAAA==.Raziel:BAAANQADCgYIBgAAAA==.',
Re='Redi:BAAANQADCgYIBgAAAA==.Redsaint:BAAANQAECgIIAgAAAA==.Reinys:BAAANQAECgQIBQAAAA==.Reload:BAAANQAECgIIAgABNQAECgYICwABAAAAAA==.Remiwolf:BAAANQADCggICAAAAA==.Renârd:BAAANQADCggICQAAAA==.Rezispacqt:BAAANQAECgEIAQAAAA==.',
Rh='Rheha:BAAANQADCgYIBgAAAA==.Rhizah:BAAANQAECgQICAAAAA==.',
Ri='Richkrakbaby:BAAANQAECgEIAQAAAA==.Riskytriscut:BAAANQADCgMIAwAAAA==.Riyan:BAAANQADCggIDgAAAA==.',
Ro='Rob:BAAANQAECgUIBgAAAA==.Robinhoød:BAAANQAECgMIBAAAAA==.Rocknsham:BAAANQAECgMIAwAAAA==.Roosifer:BAAANQADCgIIAgAAAA==.Rossin:BAAANQAECgMIAwAAAA==.Roxington:BAAANQADCgYIDAAAAA==.',
Ry='Ryddlesr:BAAANQADCggICQAAAA==.Ryeshot:BAACNQAFFIEQAAIFAAYJwSEzAACEAgAFAAYJwSEzAACEAgA1AAQKgSQAAgUACQmkJhsAAAsEAAUACQmkJhsAAAsEAAAA.Ryukotsuei:BAAANQAECgQIBAAAAA==.Ryzonc:BAAANQABCgIIAgAAAA==.',
Sa='Sagemister:BAAANQADCgIIAgAAAA==.Sange:BAAANQADCgQIBwAAAA==.Sanguinet:BAAANQAECgIIAgAAAA==.Sarlina:BAAANQAECgUIEwAAAA==.Sarrius:BAAANQABCgIIAgAAAA==.Sarudomi:BAABNQAECoEZAAMMAAkJySGTBwBiAwAMAAkJySGTBwBiAwAgAAQJQwl5KgDNAAAAAA==.Sarusham:BAAANQAECgQICAAAAA==.Saruu:BAAANQADCggIDgAAAA==.Saruwu:BAAANQADCgQIBAAAAA==.Sarïss:BAAANQAECgYIDQAAAA==.Savviana:BAAANQADCgcIDgAAAA==.',
Sb='Sbw:BAAANQAECgQIBAABNQAECgkJJAAbAJUeAA==.',
Sc='Scalemor:BAAANQAECgUICAAAAA==.Scales:BAAANQADCgUIBgAAAA==.Scarlah:BAAANQAECgEIAQAAAA==.Sciel:BAAANQAECgQIBAAAAA==.Scrabbles:BAAANQAECgUIBwAAAA==.',
Se='Secretwife:BAAANQAECgUIBgAAAA==.Senara:BAAANQAECgQIBgAAAA==.Sendriss:BAAANQADCgQIBAAAAA==.Sephoniara:BAAANQAECgEIAQAAAA==.Sephonie:BAAANQADCgIIAwAAAA==.Serath:BAAANQAECgMIBAAAAA==.',
Sh='Shaded:BAAANQABCgIIAgAAAA==.Shadowfactor:BAAANQADCgcIFQAAAA==.Shadowhawks:BAAANQAECgQIBgAAAA==.Shadownej:BAAANQADCgcIGAAAAA==.Shadowsteel:BAAANQADCggICAAAAA==.Shamonlee:BAAANQAECgQIBgAAAA==.Shamydracdad:BAAANQADCggIDgAAAA==.Shapaladin:BAAANQADCggICAABNQAECgIIAgABAAAAAA==.Sheepdoll:BAAANQAECgcIEwAAAA==.Shengo:BAAANQADCgEIAQAAAA==.Sherfin:BAAANQADCgYICQAAAA==.Sheshindy:BAAANQAECgQICQAAAA==.Shiftfour:BAAANQABCgEIAQAAAA==.Shiftysmom:BAAANQAECggIDgAAAA==.Shigz:BAAANQADCgYIBgABNQAECgYIDgABAAAAAA==.Shinigamì:BAAANQAECgQIBwAAAA==.Shockemilk:BAAANQABCgQIBgAAAA==.Shocklock:BAAANQAECggICAAAAA==.Shogun:BAAANQAECgYIDgAAAA==.Shortypie:BAAANQABCgIIAgAAAA==.Shámázing:BAAANQAECgQIBgAAAA==.Shåcø:BAABNQAECoEaAAMeAAkJ7BlkCQCyAgAeAAkJ8RZkCQCyAgAQAAgJBBuWDABnAgABNQAECgkJGgAeAOwZAA==.',
Si='Sickmoves:BAAANQADCgQIBAAAAA==.Sillyheals:BAAANQADCgYIBgABNQADCgcICwABAAAAAA==.Sillypálly:BAAANQADCgcICwAAAA==.Sinatra:BAAANQADCgEIAQAAAA==.Sindorael:BAAANQADCgQIBAAAAA==.Sinknight:BAAANQAECgYICQAAAA==.Sithweaver:BAAANQADCgQIBAAAAA==.',
Sk='Skateorpie:BAAANQAECgMIBgAAAA==.Skeebadae:BAAANQAECgUICAAAAA==.Skelestar:BAAANQAECgYIDQAAAA==.Skrt:BAAANQADCgIIAgAAAA==.Skytanks:BAAANQADCgUIBQAAAA==.Skädir:BAAANQAECgEIAQABNQAECgkJGwARAAIOAA==.',
Sl='Slayabunny:BAABNQAECoEZAAMCAAgJlSFkGAAHAwACAAgJeCBkGAAHAwAiAAUJMRiRDgBrAQAAAA==.Slep:BAAANQAECgQIBQAAAA==.Slepybaer:BAAANQADCgQIBAABNQAECgQIBQABAAAAAA==.Slimzilla:BAAANQAFFAEIAQAAAA==.',
Sm='Smaugkfc:BAAANQAECggIBgABNQAECgkJFwAKAAgdAA==.Smaugkitten:BAAANQADCgUIBQABNQAECgkJFwAKAAgdAA==.Smaugvoker:BAAANQADCgYICQABNQAECgkJFwAKAAgdAA==.Smegatron:BAAANQAECgQIBQAAAA==.',
Sn='Sneakyheals:BAAANQADCggIGgAAAA==.Sneakyrage:BAAANQAECgUIBQAAAA==.Snolin:BAAANQADCgIIAgAAAA==.Snowblowwer:BAAANQADCgIIAgAAAA==.Snowyrainz:BAAANQAECgIIAwAAAA==.',
So='Soliat:BAAANQAECgUIDAAAAA==.Sooblysham:BAAANQADCggIDgAAAA==.Soulshadez:BAAANQADCggICAAAAA==.Souupded:BAAANQAECgYIBwAAAA==.',
Sp='Spamzvoltz:BAAANQAECgYIBgAAAA==.Sparklies:BAAANQADCgMIBAABNQADCgcICQABAAAAAA==.Spedometers:BAAANQAECgMIBQAAAA==.Spedometre:BAAANQAECgIIAgABNQAECgMIBQABAAAAAA==.Spee:BAAANQABCgQIBAAAAA==.Sprinkel:BAAANQADCgMIAwAAAA==.',
Sq='Squrly:BAAANQABCgIIBAAAAA==.',
Ss='Ssjryukan:BAAANQADCgUIBQAAAA==.',
St='Stacybeam:BAAANQAECggIEQAAAA==.Standune:BAAANQADCggIAgAAAA==.Starrie:BAAANQAECgYIBgAAAA==.Staticshock:BAAANQADCgcIEwAAAA==.Steakñbake:BAAANQADCgcIBwAAAA==.Stealthylick:BAAANQAECgIIAgAAAA==.Stelus:BAAANQAECgIIBAAAAA==.Stereosity:BAAANQAECgQIBgABNQAECgQIBAABAAAAAA==.Stickobutter:BAAANQAECgQIBQAAAA==.Stoicism:BAAANQAECgEIAQAAAA==.Stopngo:BAAANQADCgYIBgAAAA==.',
Su='Sukuna:BAAANQAECgQIBAAAAA==.Sunai:BAAANQADCggIGAAAAA==.Suntra:BAAANQADCgMIAwAAAA==.Supbro:BAAANQADCgMIAwAAAA==.Suspenders:BAAANQAECgIIAgAAAA==.',
Sy='Sykodude:BAAANQAECgQICgAAAA==.Sykototem:BAAANQADCgMIAwABNQAECgQICgABAAAAAA==.Sylvanassimp:BAAANQAECgUIDAAAAA==.Syrac:BAAANQADCgYIBgAAAA==.',
Ta='Taelil:BAAANQAECgIIAgAAAA==.Tailented:BAAANQAECgUIBwAAAA==.Takadra:BAAANQADCgcIEwAAAA==.Tanalock:BAAANQAECgMIAwAAAA==.Tanalord:BAAANQAECggIDwABNQAECgkJIgAKAFsmAA==.Tatertot:BAAANQAECgUIDAAAAA==.',
Te='Teaswift:BAAANQADCggIEQAAAA==.Temuwhooper:BAAANQAECgQIBAAAAA==.',
Th='Thalyn:BAAANQADCgQIBAABNQAECggIGAAgAMYNAA==.Tharn:BAAANQADCgYIBgAAAA==.Thebabadook:BAAANQADCgcIDQAAAA==.Thelonliest:BAAANQAECgQICQAAAA==.Thornstaad:BAAANQAECgEIAgAAAA==.Thortanous:BAAANQADCgYICAAAAA==.Thrashmor:BAAANQAECgMIAwAAAA==.Throckmortus:BAAANQAECgMIAwAAAA==.Thuggymage:BAAANQAECgcIEwAAAA==.Thunderboom:BAAANQAECgUIBwAAAA==.Thundercles:BAAANQAECgEIAgAAAA==.Thunderstruk:BAAANQADCgQIBAAAAA==.Thyself:BAAANQAECgUIBwAAAA==.Thór:BAAANQADCgUIBQAAAA==.',
Ti='Tidebadra:BAABNQAECoESAAIOAAgJhRzZBADiAgAOAAgJhRzZBADiAgAAAA==.Tideradra:BAACNQAFFIEUAAMbAAcJ1Bs3AACnAgAbAAcJ1Bs3AACnAgANAAEJZAMLEwBFAAA1AAQKgR0AAxsACQkLJXYIAGUDABsACAmBJXYIAGUDAA0ACAlmDug8ALkBAAAA.Ting:BAAANQAECgQIBQAAAA==.',
Tk='Tkd:BAAANQAECgEIAQABNQAECgQICAABAAAAAA==.',
To='Toats:BAAANQADCgUIBwAAAA==.Toixic:BAAANQAFFAEIAQABNQAFFAYIEAANANgNAA==.Toixtem:BAACNQAFFIEQAAINAAYJ2A2EAQDxAQANAAYJ2A2EAQDxAQA1AAQKgRYAAg0ACQnSIKMNAPQCAA0ACQnSIKMNAPQCAAAA.Tomfoolery:BAAANQADCgQIBAAAAA==.Tootihunt:BAACNQAFFIEFAAMVAAMJKBocCADlAAAVAAMJcxIcCADlAAAGAAEJniPxDQBhAAA1AAQKgRwAAxUACQlKIkQFAEkDABUACQntIUQFAEkDAAYABwkXHQ8+AAACAAAA.Topg:BAAANQAECgQIBAAAAA==.Totmdispenzr:BAAANQADCgcIGQAAAA==.Toukai:BAAANQADCgcIEQABNQAECgIIAgABAAAAAA==.Toukuhd:BAAANQAECgIIAgAAAA==.',
Tr='Traia:BAAANQADCgQIBAAAAA==.Tralinadia:BAAANQADCggICAAAAA==.Travaxian:BAAANQADCgYIBgAAAA==.Trendz:BAAANQABCgQICQAAAA==.Trihold:BAAANQADCgEIAQAAAA==.Trog:BAAANQADCgUIBQAAAA==.',
Ts='Tselli:BAAANQAECgQIBAABNQAECggIFwAOAFwfAA==.Tsellie:BAABNQAECoEXAAMOAAgJXB8yBAD5AgAOAAgJXB8yBAD5AgANAAIJfSHtjACiAAAAAA==.',
Tu='Tumbler:BAAANQAECgMIBAAAAA==.Turkleton:BAAANQAECgcICwAAAA==.',
Tw='Twobelow:BAAANQADCgEIAQAAAA==.Twístedteå:BAAANQAECgIIAgAAAA==.',
Ty='Tyraxous:BAAANQAECgQIBQAAAA==.Tyrinnà:BAAANQADCgYICgAAAA==.',
['Tö']='Törryn:BAAANQAECgQIBQAAAA==.',
Ul='Ulah:BAAANQADCgcIEwAAAA==.',
Un='Unholyarrie:BAAANQADCgEIAQAAAA==.Unholybaine:BAAANQADCgIIAgAAAA==.Unknownz:BAAANQAECgcIEAAAAA==.Unstopubble:BAABNQAECoEZAAIJAAcJ8xq5CwAjAgAJAAcJ8xq5CwAjAgAAAA==.',
Us='Ushinoken:BAAANQABCgEIAQAAAA==.',
Uu='Uuchi:BAAANQAECgQIBQAAAA==.',
Va='Vaariks:BAAANQAECgQIBgAAAA==.Vaera:BAAANQAECgQIBAAAAA==.Valeindia:BAAANQADCggIDQAAAA==.Valenia:BAAANQAECggICAAAAA==.Valianthe:BAAANQAECgEIAgAAAA==.Valner:BAAANQAECgQICAAAAA==.Valthyria:BAAANQAECgcIDgAAAA==.Vandamnit:BAAANQADCgcIBwAAAA==.Vanessaboo:BAAANQAECgcICQABNQAFFAYIEAAWACYfAA==.',
Ve='Vebel:BAAANQAECgEIAgAAAA==.Vegara:BAAANQADCgMIAwAAAA==.Velthyr:BAAANQADCgIIAgABNQADCggICAABAAAAAA==.Velínthelyn:BAAANQADCgUIBAAAAA==.Vexthall:BAAANQADCgIIAgAAAA==.',
Vi='Vikingdrood:BAABNQAECoETAAIMAAgJwhkDGwBuAgAMAAgJwhkDGwBuAgAAAA==.Vikingj:BAAANQADCggIEAABNQAECggIEwAMAMIZAA==.Vikingsham:BAAANQADCgcIBwABNQAECggIEwAMAMIZAA==.Vinnyfr:BAABNQAECoEcAAMQAAkJ5BodBgDyAgAQAAkJBxodBgDyAgAeAAgJshP/DwA9AgAAAA==.Viwi:BAAANQAECgIIBAAAAA==.',
Vo='Voidmelky:BAAANQADCgIIAgAAAA==.',
Wa='Warehouse:BAAANQADCgUICwAAAA==.Warraxrage:BAABNQAECoEdAAMCAAgJ+Rt9MQB3AgACAAgJ+Rt9MQB3AgAPAAIJXBeaEgCfAAAAAA==.Watanabi:BAAANQAECgQIBQAAAA==.',
We='Welky:BAAANQADCgIIAgAAAA==.',
Wh='Wheel:BAAANQAECgUICAAAAA==.',
Wi='Winc:BAAANQADCgIIAgAAAA==.',
Wo='Wonsmash:BAAANQAECgMIAwAAAA==.',
Wy='Wynndiego:BAAANQAECgUICgAAAA==.Wyrmslayer:BAAANQAFFAEIAQAAAA==.',
Xa='Xaidra:BAACNQAFFIEWAAIjAAcJcgsBAQA4AgAjAAcJcgsBAQA4AgA1AAQKgSQAAiMACQlUIP8FAAADACMACQlUIP8FAAADAAAA.Xanatu:BAAANQAECgIIAgAAAA==.Xandyr:BAAANQADCgUIBAAAAA==.',
Xe='Xedk:BAAANQAECgQIEAAAAA==.Xepherite:BAAANQAECgUIBgABNQAFFAEIAQABAAAAAA==.Xephsham:BAAANQAFFAEIAQAAAA==.',
Ya='Yarayara:BAAANQADCggICAAAAA==.Yautja:BAAANQADCgMIAwABNQAECgQICQABAAAAAA==.',
Yo='Yogafire:BAAANQABCgUIBgABNQAECgMIBgABAAAAAA==.',
Yu='Yuimage:BAAANQAECgQIBQAAAA==.',
Za='Zaene:BAAANQAECgIIAgAAAA==.Zafyria:BAAANQAECgQICgAAAA==.Zalea:BAACNQAFFIEVAAIRAAcJtx1GAADBAgARAAcJtx1GAADBAgA1AAQKgSkAAhEACQlVJsAAAPQDABEACQlVJsAAAPQDAAAA.Zaluid:BAAANQAECgYIBgABNQAFFAcIFQARALcdAA==.',
Ze='Zekkial:BAAANQAECgYIDQAAAA==.Zendroza:BAAANQADCggIDwABNQAECgUIBwABAAAAAA==.',
Zi='Zippyzapper:BAAANQAECgIIAwAAAA==.',
Zl='Zlliks:BAAANQADCgQIBAAAAA==.',
Zo='Zoekai:BAAANQAECgIIAgAAAA==.Zolar:BAAANQADCggIDAAAAA==.Zonovar:BAABNQAECoEYAAIOAAkJJyCdAgBBAwAOAAkJJyCdAgBBAwAAAA==.',
Zu='Zurks:BAAANQAECgUIDwAAAA==.Zurkz:BAAANQAECgUIBQAAAA==.',
['Zà']='Zàddy:BAAANQAECgUIBgAAAA==.',
['Äz']='Äzræll:BAAANQADCggIFgAAAA==.',
['Ås']='Åshborn:BAAANQAECgcICgAAAA==.',
['Ér']='Érìs:BAAANQADCggIDAABNQAECgUICAABAAAAAA==.',
['Ði']='Ðixiewrecked:BAAANQAECgUIBwAAAA==.',
['Ðu']='Ðuck:BAAANQADCgYIDAAAAA==.',
['ßo']='ßooyeah:BAAANQAECgIIAgAAAA==.',
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
