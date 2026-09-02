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

local lookup = {'Unknown-Unknown','Paladin-Protection','Druid-Balance','Priest-Discipline','Evoker-Devastation','DeathKnight-Unholy','DeathKnight-Blood','Warlock-Demonology','Warlock-Destruction','Hunter-Marksmanship','Shaman-Restoration','Paladin-Holy','Rogue-Subtlety','Rogue-Assassination','Warrior-Arms','Shaman-Elemental','Evoker-Preservation','Mage-Arcane',}
local provider = {region='US',realm='Icecrown',name='US',type='weekly',zone=53,date='2026-09-01',data={Aa='Aaronstorm:BAAANQADCggIDgAAAA==.',
Ab='Absinythe:BAAANQADCggIBwAAAA==.',
Ac='Ackward:BAAANQAECgIIAgAAAA==.Ackwarder:BAAANQADCgcIDAABNQAECgIIAgABAAAAAA==.Acrylia:BAAANQADCgYICQAAAA==.',
Ae='Aeryx:BAAANQAECgYICAAAAA==.',
Ah='Ahsôka:BAAANQADCgYICgAAAA==.',
Ak='Akisa:BAAANQADCgEIAQAAAA==.',
Al='Alinael:BAAANQADCggICwAAAA==.Alisterr:BAAANQADCgUIBQAAAA==.Alistra:BAAANQADCgUIBQAAAA==.Alynaa:BAAANQAECgMIAwAAAA==.',
Am='Amadixiechic:BAAANQADCgQIBAAAAA==.Amafrey:BAAANQAECgMIAwAAAA==.Amo:BAAANQAECgUIBwAAAQ==.Amoret:BAAANQADCgEIAQABNQAECgUIBwABAAAAAQ==.',
An='Ancestraljr:BAAANQAECgEIAQAAAA==.Andalocke:BAAANQAECgIIAgAAAA==.Annalucia:BAAANQADCgEIAQAAAA==.Annboleyn:BAAANQADCgUIBQAAAA==.',
Ar='Arabelle:BAAANQAECgEIAQAAAA==.Archurroso:BAAANQADCgUIBQAAAA==.Ariens:BAAANQAECgQIBAAAAA==.Arlaeya:BAAANQAECgEIAQAAAA==.Artemislux:BAAANQAECgYIBgAAAA==.Aránda:BAAANQADCggICwAAAA==.',
As='Astelle:BAAANQAECgIIAgAAAA==.',
At='Atagos:BAAANQAECgIIAgAAAA==.Athanor:BAAANQADCggICAAAAA==.Atonementism:BAAANQAECgEIAQABNQADCgIIAgABAAAAAA==.',
Au='Aurawa:BAAANQADCgYIDAAAAA==.',
Av='Avannia:BAAANQADCgcICQAAAA==.Avaren:BAAANQADCggIDQABNQAECgQIBAABAAAAAA==.Avawen:BAAANQAECgUICAABNQAECgQIBAABAAAAAA==.Averyg:BAAANQADCgYIBgAAAA==.',
Aw='Awhbeans:BAAANQADCggIDwAAAA==.',
Ax='Axtafal:BAAANQADCggIDwAAAA==.',
Ba='Babaganouj:BAAANQADCgUICgAAAA==.Baineblood:BAAANQAECgEIAQAAAA==.Bandledin:BAAANQADCgYIDAAAAA==.Barelilus:BAAANQADCgcICwAAAA==.Bassproshops:BAAANQAECgcIDAAAAA==.Baulder:BAAANQADCgQICAAAAA==.',
Be='Bear:BAAANQADCgEIAQAAAA==.Belmyridon:BAAANQADCgYICQAAAA==.',
Bf='Bfc:BAAANQADCgUIBQAAAA==.',
Bi='Biaxident:BAAANQAECgEIAQAAAA==.Bigboy:BAAANQADCgYICQAAAA==.Birdyy:BAAANQADCgYICgAAAA==.',
Bj='Bjorne:BAAANQAECgIIAgAAAA==.',
Bl='Blazter:BAAANQAECgMIAwAAAA==.Blututh:BAAANQADCggICAAAAA==.Blïght:BAAANQADCgMIAwAAAA==.',
Bo='Bodhran:BAAANQAECgMIAwAAAA==.Bombadill:BAAANQADCgYICAAAAA==.Bonewings:BAAANQADCggICQAAAA==.Boombang:BAAANQAECgEIAQAAAA==.',
Br='Breezerk:BAAANQAECgMIBAAAAA==.',
Bu='Bullithead:BAAANQADCgYICQAAAA==.Bulrog:BAAANQAECgQIBAAAAA==.Bumpey:BAAANQADCgQIBQAAAA==.Bus:BAAANQAFFAEIAQABNQAFFAQIBgACAGQcAA==.Bushlite:BAAANQAECgQIBwAAAA==.',
By='Byni:BAAANQADCgYIDAAAAA==.',
Ca='Calorenn:BAAANQADCgYICgABNQAECgIIAwABAAAAAA==.Caluu:BAAANQAECgUIBQAAAA==.Cankles:BAAANQADCgMIAwAAAA==.Canolope:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Catfood:BAAANQAECgMIAwAAAA==.Cattibriee:BAAANQADCgMIAwAAAA==.',
Ce='Cece:BAAANQADCgcIDQAAAA==.Celedhring:BAAANQAECgIIAgAAAA==.',
Ch='Chaktaw:BAAANQAECgIIAQAAAA==.Chatubaholy:BAAANQAECgEIAQAAAA==.Chayito:BAAANQAECgUICgAAAA==.Cheezi:BAAANQADCggIDQAAAA==.Chickenism:BAEBNQAFFIEIAAIDAAYJPBEcAAAJAgADAAYJPBEcAAAJAgAAAA==.Chiknsmoothi:BAAANQADCgQIBAAAAA==.Chirpa:BAAANQADCgMIAwAAAA==.Chloe:BAAANQADCgcICgAAAA==.Chowtime:BAAANQAECgMIAwAAAA==.Chrysanthia:BAAANQADCgEIAQAAAA==.',
Ci='Cinderstorm:BAAANQADCgYIBgAAAA==.Citronia:BAAANQADCgEIAQAAAA==.',
Cl='Clamps:BAAANQAFFAEIAQAAAA==.Clandon:BAABNQAFFIEIAAIEAAYJEx0BAAB5AgAEAAYJEx0BAAB5AgAAAA==.Claxton:BAAANQAECgQIBAAAAA==.Clomari:BAAANQAECgQIBAAAAA==.',
Co='Concepts:BAAANQAECgQIBAAAAA==.Costcomember:BAAANQADCgIIAgAAAA==.',
Cr='Crashout:BAAANQADCggIAQAAAA==.Cron:BAAANQADCgcIBwAAAA==.Croneos:BAAANQADCgYICwAAAA==.Cross:BAAANQAECgMIAwAAAA==.',
Cu='Cudz:BAAANQADCgYICwAAAA==.Curl:BAAANQADCggIDgAAAA==.',
Da='Daddydeath:BAAANQAECgEIAQAAAA==.Dadrex:BAAANQADCgMIAwAAAA==.Dahrla:BAAANQADCgcIDQAAAA==.Daisyann:BAAANQAECgIIAgAAAA==.Dalmarr:BAAANQADCgYICgAAAA==.Dancouga:BAAANQAECgIIAgAAAA==.Daruncic:BAAANQADCgYIBgAAAA==.Dave:BAAANQAECgEIAQAAAA==.Dawnchatters:BAAANQADCgQIBAAAAA==.Dawntodusk:BAAANQADCgYIBgAAAA==.Daymia:BAAANQADCggIDwAAAA==.Dazknight:BAAANQAECgIIAwAAAA==.Dazshaman:BAAANQADCgYICgABNQAECgIIAwABAAAAAA==.',
De='Deadion:BAAANQAECgEIAQAAAQ==.Deadpaly:BAAANQADCgMIAwABNQAECgEIAQABAAAAAQ==.Deadspinwin:BAAANQADCgIIAgABNQAECgEIAQABAAAAAQ==.Dearmage:BAAANQAECgIIAgAAAA==.Deathgripz:BAAANQADCgUICQAAAA==.Decormei:BAAANQADCggIDwAAAA==.Deltaslim:BAAANQAECgQIBAAAAA==.Deltatoast:BAAANQADCgQICAAAAA==.Dennes:BAAANQADCgUIBQAAAA==.Destheleye:BAAANQADCgMIAwAAAA==.Dethnyte:BAAANQADCggICAAAAA==.',
Di='Diaf:BAAANQAECgQIDQAAAA==.Diniwen:BAAANQAECgMIAwAAAA==.Dirtbikes:BAAANQADCgUIBQAAAA==.Dithia:BAAANQAECgEIAQAAAA==.Division:BAAANQAECgUIBgAAAA==.',
Dj='Djparrot:BAAANQADCggIDgAAAA==.',
Do='Domrï:BAAANQAECgYICgAAAA==.Donkayslayer:BAAANQADCggIDQAAAA==.Donlock:BAAANQADCgcIBwAAAA==.Doohoo:BAAANQADCgUICQAAAA==.Dordrel:BAAANQADCgEIAQAAAA==.Downpour:BAAANQAECgcIBwAAAA==.',
Dr='Dracdad:BAAANQADCgEIAQAAAA==.Draevon:BAAANQADCgQICAABNQAECgMIAwABAAAAAA==.Dragondnutz:BAAANQADCggIDgAAAA==.Dragoness:BAAANQADCgQIBAAAAA==.Dragonflight:BAAANQADCggIDAAAAA==.Drakloak:BAABNQAECoERAAIFAAkJwiKiAACcAwAFAAkJwiKiAACcAwAAAA==.Drench:BAAANQADCggIDgAAAA==.',
Du='Duckdodger:BAAANQADCgIIAgAAAA==.',
Dv='Dv:BAAANQADCggIDgAAAA==.',
Dz='Dzasterpiece:BAAANQAFFAEIAQAAAA==.',
['Dä']='Däemarcus:BAAANQADCgYIEAAAAA==.',
Ec='Ectyxx:BAAANQAECgYICAAAAA==.',
Ed='Edris:BAAANQADCgcICwAAAA==.',
Ei='Eightlug:BAAANQADCgYIBgAAAA==.',
El='Elareis:BAAANQADCgQIBgAAAA==.Elwynn:BAAANQAECgUIBgAAAQ==.',
Em='Emosmaug:BAAANQAECgcICgAAAA==.',
En='Enkistral:BAAANQAECgMIAwAAAA==.Envi:BAAANQADCgcIDAAAAA==.',
Er='Erotaph:BAAANQADCgcICgAAAA==.',
Es='Esoteric:BAAANQAECgYICQAAAA==.',
Eu='Euron:BAAANQADCgYICwAAAA==.',
Ev='Evach:BAAANQAECggIEAAAAA==.Everblight:BAAANQADCgUIBQAAAA==.',
Fa='Facex:BAAANQADCggIBgAAAA==.Faelor:BAAANQADCgUIBQAAAA==.Faet:BAAANQAECgIIAgAAAA==.Faeyt:BAAANQADCgcIDQAAAA==.Fakename:BAAANQADCgMIAwAAAA==.Fatkokmage:BAAANQADCggIDAAAAA==.',
Fc='Fcawfng:BAAANQADCgIIAgAAAA==.',
Fe='Felakai:BAAANQADCgQIBgAAAA==.',
Fi='Fidgetspinna:BAAANQADCgIIAgAAAA==.Finesthour:BAABNQAFFIEGAAMGAAUJ5RMSAACoAQAGAAQJNBcSAACoAQAHAAEJqQaNBQAqAAAAAA==.Fingerlicker:BAAANQADCgcIDQAAAA==.Fitzwilliam:BAAANQAECgIIAgAAAA==.Fives:BAAANQADCgUIBQAAAA==.',
Fl='Fluxy:BAAANQADCgYIBgAAAA==.',
Fo='Fonzie:BAAANQAECgYIBgAAAA==.Foozykinz:BAAANQADCgMIAwAAAA==.Forlorn:BAAANQADCgYIBgAAAA==.Fortsmite:BAAANQADCgUIBwAAAA==.Foxicious:BAAANQAECgIIAgAAAA==.Foxjaw:BAAANQADCgIIAgAAAA==.Foxpaw:BAAANQAECgIIAgAAAA==.',
Fr='Fraggle:BAEANQADCgYICwAAAA==.Freshlock:BAAANQAECgQIBAAAAA==.Frostbitë:BAAANQADCgEIAQAAAA==.Frostfires:BAAANQAECgIIAgAAAA==.Frostlawlz:BAAANQADCgQIBAAAAA==.',
Fu='Fubashi:BAAANQAECgMIAwABNQAECgIIAgABAAAAAA==.Furritoo:BAAANQAECgIIAgAAAA==.Fuzzie:BAAANQADCgYIBgAAAA==.',
Ga='Gachiwl:BAABNQAFFIEHAAMIAAYJpRsbAACWAQAIAAQJXRsbAACWAQAJAAIJNRy1AADUAAAAAA==.Galirana:BAAANQAECgEIAQAAAA==.Gampshwago:BAAANQAECgYICgABNQADCgIIAgABAAAAAA==.Garion:BAAANQADCgQIBAAAAA==.Garkk:BAAANQAECgIIAgAAAA==.Garronan:BAABNQAFFIEIAAIKAAYJrRcbAAAnAgAKAAYJrRcbAAAnAgAAAA==.',
Ge='Geary:BAAANQADCgcIDQAAAA==.Gelina:BAAANQAECgMIAwAAAA==.Geveesa:BAAANQADCggIDwAAAA==.',
Gi='Gibletss:BAAANQAECgIIAgAAAA==.',
Gl='Glaivedigger:BAAANQAECgEIAgAAAA==.',
Go='Golda:BAAANQAECgIIAgAAAA==.Goonerbait:BAAANQADCgIIAgAAAA==.Goragon:BAAANQADCggICAAAAA==.',
Gr='Grass:BAAANQADCgUIBwAAAA==.Grcorolla:BAAANQAECgYICAAAAA==.Grindder:BAAANQADCgQIBAAAAA==.Groshnok:BAAANQADCgYICwAAAA==.Grunky:BAAANQAECgUIBQAAAA==.',
Gu='Guanyin:BAAANQADCgUIBQAAAA==.Gustobooms:BAAANQAECgMIAwAAAA==.',
['Gì']='Gìrthquake:BAAANQAECgYICQAAAA==.',
Ha='Haiayla:BAAANQADCgcIDAAAAA==.Haleybug:BAAANQADCgIIAgAAAA==.Halyax:BAAANQADCgMIAwAAAA==.Hammerslol:BAAANQADCggICAAAAA==.Hamoron:BAAANQADCgYIBgAAAA==.',
He='Healcheck:BAAANQADCgEIAQAAAA==.Herm:BAAANQADCgYIDAAAAA==.Hesel:BAAANQADCgcIDQAAAA==.',
Hi='Hihowareya:BAAANQAECgcIDgAAAA==.Hildegar:BAAANQADCgYICAAAAA==.',
Ho='Holdmydeeps:BAAANQAECgMIBAAAAA==.Horehronie:BAAANQADCggICQAAAA==.Hosebaggins:BAAANQADCgcIDQAAAA==.How:BAAANQADCgUIBQAAAA==.',
Hu='Hubbles:BAABNQAFFIEGAAILAAUJkA8xAADQAQALAAUJkA8xAADQAQAAAA==.Hububbles:BAAANQAECgIIAgABNQAFFAUIBgALAJAPAA==.',
Hy='Hybla:BAAANQADCgYIBgAAAA==.Hylikus:BAAANQAECgEIAQAAAA==.',
['Hë']='Hëlen:BAAANQADCgQIBAAAAA==.Hëllräisër:BAAANQADCgUIBQAAAA==.',
['Hô']='Hôlystôrm:BAAANQADCgYIDAAAAA==.',
Ic='Icesaber:BAAANQADCggIEgAAAA==.Ichigonyne:BAAANQADCgYICAAAAA==.Iciala:BAAANQADCgMIBAAAAA==.',
Ig='Iggar:BAAANQADCgQIBgAAAA==.Igotu:BAAANQADCgYIDgAAAA==.',
Im='Imira:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Impushpop:BAAANQADCgYICwAAAA==.',
In='Indigos:BAAANQADCgUIBwAAAA==.',
Ir='Irasyn:BAAANQADCgYICwAAAA==.',
Is='Isam:BAAANQAECgEIAQAAAA==.',
Ja='Jadefire:BAAANQAECgUIBgAAAA==.Jaedemon:BAAANQAECgYICQAAAA==.Jaysön:BAAANQADCgYICAAAAA==.',
Je='Jebuku:BAAANQAECgIIAgAAAA==.',
Ji='Jinxblue:BAAANQAECgMIAwAAAA==.Jiroyan:BAAANQADCggIDgAAAA==.',
Jo='Joralö:BAAANQADCgcICwAAAA==.',
Jt='Jtvikiing:BAAANQADCgUIBQABNQAECgYIBwABAAAAAA==.',
Ju='Jubilee:BAAANQAECgYICgAAAA==.Jumpies:BAAANQADCgcIDQAAAA==.Jupiturr:BAAANQAECgIIAgAAAA==.Juunbroh:BAAANQAECgEIAQAAAA==.',
['Jé']='Jénova:BAAANQADCgIIAwAAAA==.',
['Jö']='Jörd:BAAANQADCgMIAwAAAA==.',
Ka='Kaa:BAAANQADCgUIBQABNQAECgcICQABAAAAAA==.Kaarin:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.Kadowe:BAAANQAECgYIBwAAAA==.Kaiyla:BAAANQADCgcICQAAAA==.Kaladinn:BAAANQADCggIDwAAAA==.Kalintene:BAAANQADCgIIAgABNQAECgMIBAABAAAAAA==.Kargan:BAAANQADCgMIAwABNQADCgcIDQABAAAAAA==.Karthas:BAAANQADCggIDwAAAA==.',
Ke='Keir:BAAANQADCggIDwAAAA==.Kelsey:BAAANQADCgYICQABNQAECgMIBAABAAAAAA==.Kenny:BAAANQADCgcIDQAAAA==.Keyanor:BAAANQAECgEIAQAAAA==.',
Kh='Khaeltharion:BAAANQAECgMIAwAAAA==.Khalan:BAAANQAECgQIBgAAAA==.Khavatari:BAAANQAECgMIAwAAAA==.Khazidhea:BAAANQADCgMIBQABNQADCgYIDQABAAAAAA==.Khazrael:BAAANQADCgYIDQAAAA==.',
Ki='Kilmanov:BAAANQAECggIBgAAAA==.Kitmeup:BAAANQAFFAIIAgAAAA==.',
Ko='Kookiez:BAAANQADCgcIDQAAAA==.Korrupshun:BAAANQAECgIIAgAAAA==.Korvian:BAAANQADCggICAAAAA==.',
Kr='Kro:BAAANQADCgUIBwAAAA==.',
Ky='Kynigós:BAAANQAECgIIAwAAAA==.',
Kz='Kzerg:BAAANQADCggICAAAAA==.',
La='Labzy:BAAANQADCgQIBAAAAA==.Laestra:BAAANQABCgIIAgAAAA==.Lamìà:BAAANQADCgcIBwAAAA==.Lavendér:BAAANQAECgIIAgAAAA==.',
Le='Leerooy:BAAANQADCgIIAgAAAA==.Leobardo:BAAANQADCggIDAAAAA==.',
Li='Lihp:BAAANQADCgcIDAAAAA==.Liljj:BAAANQAECgIIAgAAAA==.Linndara:BAAANQADCgQIBAAAAA==.Linting:BAAANQAECgIIAgAAAA==.Lithsong:BAAANQAECgUICAAAAA==.',
Lo='Lockthor:BAAANQAECgIIAgAAAA==.Lonie:BAAANQADCgcIDQAAAA==.Loto:BAAANQADCgYIBgAAAA==.',
Lu='Lucyfury:BAAANQADCgEIAQAAAA==.Luedragosa:BAAANQAECgIIAgAAAA==.Lunademon:BAAANQADCgUIBQAAAA==.Lunadk:BAAANQAECgIIAgAAAA==.Luxmortae:BAAANQABCgIIAgAAAA==.Luxserena:BAAANQAECgEIAQAAAA==.',
Ly='Lysunder:BAAANQADCggIDgAAAA==.Lythronax:BAAANQAECgEIAQAAAA==.',
['Lö']='Löwen:BAAANQAECgQIBQAAAA==.',
Ma='Mackro:BAAANQADCggIDgAAAA==.Madblackjack:BAAANQADCgUICQAAAA==.Mahanar:BAAANQADCgUIBQAAAA==.Maimai:BAAANQADCgUIBQAAAA==.Makandcheese:BAAANQADCgIIAQAAAA==.Malisenta:BAAANQAECgQIBQAAAA==.Mallboro:BAAANQADCgQIBAAAAA==.Markoramius:BAAANQADCgcICwAAAA==.Marpew:BAAANQADCgUIBQAAAA==.',
Me='Mekhasingh:BAAANQAECgEIAQAAAA==.Mellicanisis:BAAANQADCgMIAwAAAA==.Melvalint:BAAANQAECgEIAQAAAA==.Memademic:BAAANQAECgIIAgAAAA==.Mendsong:BAAANQADCggIDQAAAA==.Merlins:BAAANQAECgIIAgAAAA==.',
Mi='Milestheevil:BAAANQADCgcICQAAAA==.Mindbullets:BAAANQADCgYIBwAAAA==.Mirah:BAAANQAECgQIBAAAAA==.',
Mm='Mmbeans:BAAANQADCgEIAQABNQAECgQICAABAAAAAA==.',
Mo='Mochikat:BAABNQAFFIEIAAIMAAYJFQ4mAAAdAgAMAAYJFQ4mAAAdAgAAAA==.Mogamemnon:BAAANQADCgEIAQAAAA==.Mogriya:BAAANQADCgcIBwAAAA==.Moisttank:BAAANQADCgEIAQAAAA==.Mokt:BAAANQADCgYIBgAAAA==.Mollywhop:BAAANQAECgEIAQAAAA==.Molyneaux:BAAANQADCgcIDgAAAA==.Mooskaroo:BAAANQAECgQIBQAAAA==.Moraa:BAAANQADCgYIBgAAAA==.Moregoth:BAAANQADCgcICgAAAA==.Morrows:BAAANQAECgEIAQAAAA==.',
Mu='Murph:BAAANQADCgcIDQAAAA==.Mutilatee:BAABNQAFFIEIAAMNAAYJphcrAAADAgANAAUJLRQrAAADAgAOAAIJdhYhAADVAAAAAA==.',
My='Myeyeonu:BAAANQADCgYICQABNQADCgYIDgABAAAAAA==.Myrollan:BAAANQADCgYIBgAAAA==.Mystshots:BAAANQADCgcIDQAAAA==.',
['Mí']='Míra:BAAANQAECgIIAgAAAA==.',
['Mø']='Møzrt:BAAANQADCgQIBQAAAA==.',
Na='Nachtengel:BAAANQAECgEIAQAAAA==.Nagda:BAAANQADCgYIBgAAAA==.Naismene:BAAANQADCgUICAAAAA==.Namswoam:BAAANQADCgIIAgAAAA==.Naustaire:BAAANQADCgUIBQAAAA==.Nazendrenz:BAAANQAECgYICAAAAA==.',
Ne='Necromantic:BAAANQAECgEIAQAAAA==.Neihtdk:BAAANQAECgIIAgAAAA==.Nerissraven:BAAANQAECgMIAwAAAA==.Nesaru:BAAANQADCgcIDQAAAA==.Nesho:BAAANQADCgQIBAAAAA==.Nesse:BAAANQADCgcIBgAAAA==.Nestah:BAAANQADCgcIDQAAAA==.',
Ni='Niemira:BAAANQADCgQIBAAAAA==.Nightshift:BAAANQADCgEIAQAAAA==.Nightwatch:BAAANQAECgEIAQAAAA==.Niknew:BAAANQADCgIIAwAAAA==.Nisaloth:BAAANQADCggIDgAAAA==.',
No='No:BAAANQADCgEIAQAAAA==.Nonaz:BAAANQADCggICQAAAA==.Nonrahnu:BAAANQABCgQIBAAAAA==.Nontoxic:BAAANQAECgIIAgAAAQ==.Noodlemaker:BAAANQAECgEIAQAAAA==.Noop:BAAANQADCgYICwAAAA==.Norot:BAAANQADCgYICwAAAA==.Northcut:BAAANQAECgEIAQAAAA==.',
Nu='Nual:BAAANQAECgYICwAAAA==.Nubur:BAAANQABCgIIAgAAAA==.Nudag:BAAANQADCgYICQAAAA==.',
Ny='Nystanari:BAAANQADCggICQAAAA==.',
Oa='Oakendeath:BAAANQADCgcICwAAAA==.',
Od='Odania:BAAANQAECgUIBgAAAA==.',
Ol='Older:BAAANQAECgIIAgAAAA==.Olk:BAAANQAECgEIAQAAAA==.',
Oo='Oohgabooga:BAAANQAECgYIBgAAAA==.',
Or='Oreganom:BAAANQADCgYIBgABNQAFFAYIBwAIADUWAA==.Oreganow:BAABNQAFFIEHAAMIAAYJNRZrAAAnAQAIAAMJcRVrAAAnAQAJAAMJ+RZHAAAhAQAAAA==.Orenghar:BAAANQAECgIIAgAAAA==.',
Os='Os:BAAANQADCgYICQAAAA==.',
Ov='Overbite:BAAANQADCgEIAQAAAA==.Overcast:BAAANQADCgUICAAAAA==.',
Pa='Pajamajacks:BAAANQAECgcIDQABNQAFFAMIBAABAAAAAA==.Pallylujâh:BAEANQAECgIIAgAAAA==.Palmerz:BAAANQAECgIIAgAAAA==.Pardak:BAAANQADCggIDgAAAA==.Partition:BAAANQADCgYIBgAAAA==.Pavlov:BAAANQAECgEIAQAAAA==.',
Pe='Pengpeng:BAAANQAECgYICQAAAA==.Pesmerga:BAAANQADCgIIAgAAAA==.Pestis:BAAANQABCgMIAwAAAA==.Pestosham:BAAANQAECgQIBAAAAA==.',
Ph='Phantasm:BAAANQADCggICAAAAA==.Phil:BAAANQABCgQIBAABNQADCgcIDAABAAAAAA==.Phriaa:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.Phungerclap:BAACNQAFFIEIAAIPAAYJ4yIGAACOAgAPAAYJ4yIGAACOAgA1AAQKgRoAAg8ACQnZJTEAAAcEAA8ACQnZJTEAAAcEAAAA.',
Pi='Pingu:BAAANQAFFAIIAgAAAA==.',
Pk='Pkspyro:BAAANQADCgYICQAAAA==.',
Po='Polarexpress:BAAANQADCgQIBAAAAA==.Ponfomage:BAAANQABCgQIBgABNQAECgEIAQABAAAAAA==.Ponfop:BAAANQAECgEIAQAAAA==.Popicus:BAAANQADCgcICwAAAA==.Porridge:BAAANQADCgUIBQAAAA==.',
Pr='Pratz:BAAANQAECgIIAgAAAA==.Priestism:BAEANQADCgYIBgABNQAFFAYICAADADwRAA==.Primordikal:BAAANQAECgEIAQAAAA==.Priscillå:BAAANQADCggIFAAAAA==.',
Pu='Pudders:BAAANQAFFAMIBAAAAA==.Punchfist:BAAANQAECgUIBQAAAA==.',
Qu='Quickcast:BAAANQAECgMIBAAAAA==.',
Ra='Radel:BAABNQAFFIEIAAIHAAYJjRkYAAAfAgAHAAYJjRkYAAAfAgAAAA==.Radpal:BAAANQAECgQIBgABNQAFFAYICAAHAI0ZAA==.Radwar:BAAANQAECgYIDAAAAA==.Raesham:BAAANQADCgYICQAAAA==.Ragemaster:BAAANQADCgMIBAAAAA==.Ralah:BAAANQADCgcIDQAAAA==.Ratdk:BAAANQAECgQICAAAAA==.Raydoth:BAAANQADCggIEAAAAA==.',
Re='Redi:BAAANQADCgYIBgAAAA==.Redsaint:BAAANQADCgUIBQAAAA==.Reinys:BAAANQADCgUIBQAAAA==.Reload:BAAANQAECgIIAgAAAA==.Renârd:BAAANQADCgcIBwAAAA==.Rezispacqt:BAAANQADCgYICwAAAA==.',
Rh='Rhizah:BAAANQAECgEIAQAAAA==.',
Ri='Richkrakbaby:BAAANQADCgYIBgAAAA==.Riskytriscut:BAAANQADCgMIAwAAAA==.Riyan:BAAANQADCgYIBgAAAA==.',
Ro='Rob:BAAANQADCggICAAAAA==.Robinhoød:BAAANQADCggIDQAAAA==.Rocknsham:BAAANQADCggICAAAAA==.Roosifer:BAAANQADCgIIAgAAAA==.Rossin:BAAANQADCgYIBgAAAA==.Roxington:BAAANQADCgQIBgAAAA==.',
Ry='Ryddlesr:BAAANQADCggICQAAAA==.Ryeshot:BAAANQAFFAMIBAAAAA==.Ryukotsuei:BAAANQADCgcIDQAAAA==.',
Sa='Sagemister:BAAANQADCgIIAgAAAA==.Sarlina:BAAANQAECgIIAgAAAA==.Sarudomi:BAAANQAECgcIDAAAAA==.Sarusham:BAAANQADCgIIAgAAAA==.Sarïss:BAAANQAECgIIAgAAAA==.Savviana:BAAANQADCgMIAwAAAA==.',
Sc='Scalemor:BAAANQAECgEIAQAAAA==.Scarlah:BAAANQADCgMIAwAAAA==.Sciel:BAAANQADCgcICgAAAA==.',
Se='Secretwife:BAAANQAECgEIAQAAAA==.Senara:BAAANQADCgcIDQAAAA==.Sephoniara:BAAANQADCgQIBAAAAA==.Sephonie:BAAANQADCgIIAwAAAA==.Serath:BAAANQADCgcICQAAAA==.',
Sh='Shaded:BAAANQABCgIIAgAAAA==.Shadowfactor:BAAANQADCgUICAAAAA==.Shadownej:BAAANQADCgYICwAAAA==.Shamonlee:BAAANQADCgYICgAAAA==.Sheepdoll:BAAANQAECgUICQAAAA==.Sheshindy:BAAANQAECgIIAgAAAA==.Shiftfour:BAAANQABCgEIAQAAAA==.Shiftysmom:BAAANQAECggIAgAAAA==.Shogun:BAAANQAECgMIAwAAAA==.Shortypie:BAAANQABCgIIAgAAAA==.Shåcø:BAAANQAECgYICgAAAA==.',
Si='Sickmoves:BAAANQADCgQIBAAAAA==.Sillypálly:BAAANQADCgQIBAAAAA==.Sinatra:BAAANQADCgEIAQAAAA==.Sindorael:BAAANQABCgMIAwAAAA==.Sinknight:BAAANQAECgMIAwAAAA==.Sithweaver:BAAANQADCgQIBAAAAA==.',
Sk='Skateorpie:BAAANQADCggIEAAAAA==.Skeebadae:BAAANQAECgMIAwAAAA==.Skelestar:BAAANQAECgIIAgAAAA==.Skrt:BAAANQADCgIIAgAAAA==.',
Sl='Slayabunny:BAAANQAFFAEIAQAAAA==.Slep:BAAANQADCgUICQAAAA==.Slepybaer:BAAANQADCgQIBAABNQADCgUICQABAAAAAA==.Slimzilla:BAAANQAECgEIAQAAAA==.',
Sm='Smaugvoker:BAAANQADCgYICQABNQAECgcICgABAAAAAA==.',
Sn='Sneakyheals:BAAANQADCgcIDAAAAA==.Snolin:BAAANQADCgIIAgAAAA==.Snowyrainz:BAAANQAECgEIAQAAAA==.',
So='Soliat:BAAANQAECgMIAwAAAA==.Sooblysham:BAAANQADCgcICgAAAA==.Soulshadez:BAAANQADCggICAAAAA==.Souupded:BAAANQAECgEIAQAAAA==.',
Sp='Sparklies:BAAANQADCgEIAQABNQADCgYICAABAAAAAA==.Spedometers:BAAANQAECgEIAQAAAA==.Spee:BAAANQABCgQIBAAAAA==.',
Sq='Squrly:BAAANQABCgIIBAAAAA==.',
Ss='Ssjryukan:BAAANQADCgUIBQAAAA==.',
St='Stacybeam:BAAANQAECgYICAAAAA==.Starrie:BAAANQAECgIIAgAAAA==.Staticshock:BAAANQADCgYICgAAAA==.Stealthylick:BAAANQADCgYICwAAAA==.Stelus:BAAANQADCggIDwAAAA==.Stereosity:BAAANQAECgQIBAABNQAECgQIBAABAAAAAA==.Stoicism:BAAANQADCgIIAgAAAA==.',
Su='Sunai:BAAANQADCgYICgAAAA==.Suntra:BAAANQADCgMIAwAAAA==.Suspenders:BAAANQADCgcIDQAAAA==.',
Sy='Sykodude:BAAANQAECgIIAgAAAA==.Sylvanassimp:BAAANQAECgUIBwAAAA==.',
Ta='Taelil:BAAANQADCgIIBAAAAA==.Takdrexus:BAAANQADCgQIBgAAAA==.Tanalock:BAAANQADCgYICwAAAA==.Tanalord:BAAANQAECgMIAwABNQAECgcIDgABAAAAAA==.Tatertot:BAAANQAECgMIAwAAAA==.',
Te='Teaswift:BAAANQADCgcICAAAAA==.Temuwhooper:BAAANQAECgQIBAAAAA==.',
Th='Thalyn:BAAANQADCgQIBAABNQAECgUIBwABAAAAAA==.Tharn:BAAANQADCgYIBgAAAA==.Thebabadook:BAAANQADCgUIBQABNQADCgUICgABAAAAAA==.Thelonnius:BAAANQADCggIEwAAAA==.Thortanous:BAAANQADCgYICAAAAA==.Throckmortus:BAAANQAECgMIAwAAAA==.Thuggymage:BAAANQAECgQICAAAAA==.Thunderboom:BAAANQAECgIIAgAAAA==.Thundercles:BAAANQADCggICAAAAA==.Thunderstruk:BAAANQADCgQIBAAAAA==.Thyself:BAAANQADCggIDAAAAA==.',
Ti='Tidebadra:BAAANQAECgQIBQAAAA==.Tideradra:BAABNQAFFIEHAAMQAAUJuRhJAACGAQAQAAQJ/BlJAACGAQALAAEJwgDeAwBFAAAAAA==.Ting:BAAANQADCggICAAAAA==.',
To='Toats:BAAANQADCgQIBgAAAA==.Toixic:BAAANQAECgcIDQABNQAFFAUIBgALAGoNAA==.Toixtem:BAABNQAFFIEGAAILAAUJag1HAACnAQALAAUJag1HAACnAQAAAA==.Tootihunt:BAAANQAFFAEIAQAAAA==.Topg:BAAANQADCggIDgAAAA==.Totmdispenzr:BAAANQADCgYICwAAAA==.Toukai:BAAANQADCgQIBAABNQADCgYIDAABAAAAAA==.Toukuhd:BAAANQADCgYIDAAAAA==.',
Tr='Trendz:BAAANQABCgQIBQAAAA==.Trihold:BAAANQADCgEIAQAAAA==.Trog:BAAANQADCgUIBQAAAA==.',
Ts='Tselli:BAAANQADCgYIBgABNQAECgYICAABAAAAAA==.Tsellie:BAAANQAECgYICAAAAA==.',
Tu='Tumbler:BAAANQADCgYIDwAAAA==.Turkleton:BAAANQAECgMIAwAAAA==.',
Tw='Twobelow:BAAANQADCgEIAQAAAA==.Twístedteå:BAAANQADCgYICAAAAA==.',
Ty='Tyraxous:BAAANQADCgYICgAAAA==.Tyrinnà:BAAANQADCgQIBAAAAA==.',
['Tö']='Törryn:BAAANQADCgYICgAAAA==.',
Ul='Ulah:BAAANQADCgYIBwAAAA==.',
Un='Unholybaine:BAAANQADCgIIAgAAAA==.Unknownz:BAAANQAECgMIBAAAAA==.Unstopubble:BAAANQAECgIIAgAAAA==.',
Uu='Uuchi:BAAANQADCgYICgAAAA==.',
Va='Vaariks:BAAANQADCgcIDQAAAA==.Vaera:BAAANQADCgYICQAAAA==.Valeindia:BAAANQADCgUIBQAAAA==.Valenia:BAAANQADCggIAQAAAA==.Valianthe:BAAANQADCggIDgAAAA==.Valner:BAAANQADCgUIBQAAAA==.Valthyria:BAAANQAECgUIBwAAAA==.Vanessaboo:BAAANQAECgIIAgABNQAFFAUIBgAGAOUTAA==.',
Ve='Vebel:BAAANQADCggICwAAAA==.Vegara:BAAANQADCgMIAwAAAA==.Velthyr:BAAANQADCgIIAgAAAA==.Velínthelyn:BAAANQADCgUIBAAAAA==.Vexthall:BAAANQADCgIIAgAAAA==.',
Vi='Vikingdrood:BAAANQAECgYIBwAAAA==.Vikingj:BAAANQADCgIIAgABNQAECgYIBwABAAAAAA==.Vikingsham:BAAANQADCgcIBwABNQAECgYIBwABAAAAAA==.Vinnyfr:BAAANQAECgYICQAAAA==.Viwi:BAAANQADCgcIDgAAAA==.',
Vo='Voidmelky:BAAANQADCgIIAgAAAA==.',
Wa='Warraxrage:BAAANQAECgYICwAAAA==.',
We='Welky:BAAANQADCgIIAgAAAA==.',
Wh='Wheel:BAAANQADCggIDwAAAA==.',
Wi='Winc:BAAANQADCgIIAgAAAA==.',
Wo='Wonsmash:BAAANQADCggICAAAAA==.',
Wy='Wynndiego:BAAANQAECgEIAQAAAA==.Wyrmslayer:BAAANQAECgcIBwAAAA==.',
Xa='Xaidra:BAABNQAFFIEIAAIRAAYJTQs2AAD+AQARAAYJTQs2AAD+AQAAAA==.Xanatu:BAAANQADCgYICwAAAA==.Xandyr:BAAANQABCgQIBAAAAA==.',
Xe='Xedk:BAAANQADCggICAAAAA==.Xepherite:BAAANQADCgYIBgABNQAECgYICQABAAAAAA==.Xephsham:BAAANQAECgYICQAAAA==.',
Yu='Yuimage:BAAANQADCgcIBwAAAA==.',
Za='Zafyria:BAAANQAECgIIAwAAAA==.Zalea:BAABNQAFFIEHAAISAAYJXBgaAABQAgASAAYJXBgaAABQAgAAAA==.',
Ze='Zekkial:BAAANQAECgIIAgAAAA==.Zendroza:BAAANQADCgcIBwAAAA==.',
Zi='Zippyzapper:BAAANQAECgEIAQAAAA==.',
Zo='Zoekai:BAAANQADCgYIDAAAAA==.Zolar:BAAANQADCgQIBAAAAA==.Zonovar:BAAANQAECgcIBwAAAA==.',
Zu='Zurks:BAAANQAECgQIBAAAAA==.',
['Zà']='Zàddy:BAAANQADCgEIAQAAAA==.',
['Äz']='Äzræll:BAAANQADCgYICgAAAA==.',
['Ås']='Åshborn:BAAANQAECgMIAwAAAA==.',
['Ði']='Ðixiewrecked:BAAANQADCggIDAAAAA==.',
['Ðu']='Ðuck:BAAANQADCgQIBgAAAA==.',
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
