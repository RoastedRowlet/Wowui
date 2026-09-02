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

local lookup = {'Unknown-Unknown','Evoker-Devastation','Paladin-Retribution','Paladin-Protection','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Elemental',}
local provider = {region='US',realm="Aman'Thul",name='US',type='weekly',zone=53,date='2026-09-01',data={Aa='Aadonis:BAAANQADCgIIAwAAAA==.Aarek:BAAANQABCgQIAgABNQADCgcICAABAAAAAA==.',
Ab='Abyssalmaw:BAAANQAECgEIAQAAAA==.',
Ac='Acionna:BAAANQADCggIDwAAAA==.',
Ad='Ada:BAAANQADCgIIAgAAAA==.Adekeahokeha:BAAANQADCgUIBQAAAA==.Adrenalin:BAAANQADCggIDQAAAA==.',
Ae='Aedros:BAAANQAECgEIAQAAAA==.Aegis:BAAANQADCgEIAQAAAA==.Aellan:BAAANQAECgQIBgAAAA==.',
Af='Afflexion:BAAANQADCggICAAAAA==.',
Ag='Agonier:BAAANQADCgEIAQAAAA==.',
Aj='Ajira:BAAANQADCgYICgAAAA==.',
Ak='Akiaki:BAAANQADCgIIAgAAAA==.',
Al='Aladk:BAAANQAECgMIBQAAAA==.Alafus:BAAANQADCgIIAgABNQAECgMIBQABAAAAAA==.Alalock:BAAANQADCgIIAgABNQAECgMIBQABAAAAAA==.Alaria:BAAANQADCgYICQABNQAECgYICQABAAAAAA==.Alarian:BAAANQAECgMIAwAAAA==.Aldai:BAAANQADCgYICgAAAA==.Alendros:BAAANQADCgIIAgAAAA==.Alexsia:BAAANQADCgEIAQAAAA==.Aliiah:BAAANQADCggICgAAAA==.Alir:BAAANQAECgUIBwAAAA==.Alle:BAAANQAECgIIAgAAAA==.Allen:BAAANQAECgUIBgAAAA==.Allyren:BAAANQAECgEIAQAAAA==.Allythriea:BAAANQADCgQIBgAAAA==.',
Am='Ambertwo:BAAANQADCgcIDAAAAA==.',
An='Andreb:BAAANQAECgEIAQAAAA==.Andromyda:BAAANQADCgQIBgAAAA==.Angelofnite:BAAANQADCgQIBgAAAA==.Angrychicken:BAAANQADCgUIBQAAAA==.Ankh:BAAANQADCggIDgAAAA==.Antopanto:BAAANQADCgQIBQAAAA==.',
Ar='Arasmina:BAAANQAECgUIBwAAAA==.Arcanystra:BAAANQADCgQIBAAAAA==.Arcathal:BAAANQAECgQIBAAAAA==.Arcshottx:BAAANQAECgEIAQAAAA==.Arliis:BAAANQAECgEIAQAAAA==.Arniy:BAAANQADCgYIDQABNQAECgYICQABAAAAAA==.',
As='Asenathe:BAAANQADCggIAgAAAA==.Ashaad:BAAANQADCgYICwAAAA==.Asyluun:BAAANQADCgYIDAAAAA==.',
At='Atorvas:BAAANQADCgMIAwAAAA==.',
Au='Auchioane:BAAANQAECgEIAQAAAA==.Aurelyia:BAAANQADCgYICwAAAA==.',
Aw='Awakenimg:BAAANQADCgEIAQAAAA==.',
Az='Azador:BAAANQAECgEIAQAAAA==.Azael:BAAANQADCgcICQAAAA==.Azarion:BAAANQADCgEIAQAAAA==.',
Ba='Backburner:BAAANQADCgMIAwAAAA==.Badvoodoo:BAAANQAECgEIAQAAAA==.Balfor:BAAANQAECgMIAwAAAA==.Bandarpallie:BAAANQADCgYICAAAAA==.Baynage:BAAANQADCggICwAAAA==.',
Be='Beefkakes:BAAANQADCgEIAQAAAA==.Belest:BAAANQADCgcICgAAAA==.Belfhee:BAAANQADCgEIAQAAAA==.Belkelmor:BAAANQADCgEIAQAAAA==.Bellaros:BAAANQADCgUICQAAAA==.Belè:BAAANQAECgQIBAAAAA==.Beorm:BAAANQADCgYICgAAAA==.Bermagi:BAAANQAECgEIAQAAAA==.',
Bi='Bigbanana:BAAANQAECgQIBAAAAA==.Bigdaddy:BAAANQAECgUIBwAAAA==.Bigrilla:BAAANQADCgYIDAAAAA==.Bigsecksi:BAAANQADCgcIDAAAAA==.Billkills:BAAANQADCgIIAgAAAA==.Billpie:BAAANQADCgQIBQAAAA==.Binkei:BAAANQADCgEIAQAAAA==.',
Bl='Blacksky:BAAANQADCgYICAAAAA==.Blade:BAAANQAECgEIAQAAAA==.Blastette:BAAANQADCgQICAAAAA==.Blayze:BAAANQAECgEIAQAAAA==.Bloodgimp:BAAANQADCggICgAAAA==.Bloodlust:BAAANQAECgcICgAAAA==.Bloodslay:BAAANQAECgQIBQAAAA==.Bloodtank:BAAANQADCgQIBgAAAA==.Bluebrood:BAAANQADCgcIDAAAAA==.',
Bo='Boenarrow:BAAANQADCgQIBAAAAA==.Bojack:BAAANQAECgMIAwAAAA==.Bombshot:BAAANQADCgYICAAAAA==.Boomdeeznutz:BAAANQADCgQIBgAAAA==.Botmage:BAAANQAECgIIAgAAAA==.Bovinei:BAAANQADCgYICAAAAA==.',
Br='Brackk:BAAANQADCgYIBgAAAA==.Braedaevia:BAAANQAECgEIAQAAAA==.Brahnson:BAAANQADCgQICAAAAA==.Breldyr:BAAANQAECgQIBAAAAA==.Bronnir:BAAANQADCgIIAgAAAA==.Brotis:BAAANQADCgUIBwAAAA==.Brylen:BAAANQAFFAMIBAAAAA==.',
Bu='Bubblerat:BAAANQADCgUIBQAAAA==.Bullus:BAAANQAECgEIAQAAAA==.Buntz:BAAANQAECgUIBwAAAA==.',
Ca='Caain:BAAANQAECgQIBAAAAA==.Caalypso:BAAANQAECgIIBgAAAA==.Caileron:BAAANQADCgcIEwAAAA==.Cakesnpies:BAAANQAECgEIAQAAAA==.Callofdeath:BAAANQADCgQIBgAAAA==.Cancelyn:BAAANQADCgYIBwAAAA==.Capsmasher:BAAANQADCgYIBgAAAA==.Cashehm:BAAANQADCgcICgAAAA==.Caströ:BAAANQADCggIDgAAAA==.',
Ce='Cecilbgnome:BAAANQADCgIIAgAAAA==.Celad:BAAANQAECgEIAQAAAA==.Cenedra:BAAANQADCggIDgAAAA==.',
Ch='Chromitez:BAAANQAECgEIAQAAAA==.Chroren:BAAANQAECgQIBQAAAA==.Chubberz:BAAANQADCggICAABNQAECgIIAgABAAAAAA==.Churlish:BAAANQAECgYIBwAAAA==.',
Cl='Clawyaeyeout:BAAANQADCgQIBAAAAA==.Cleavís:BAAANQAECgEIAQAAAA==.',
Co='Cogedor:BAAANQADCgEIAQAAAA==.Corepia:BAAANQADCgYICgAAAA==.Cozymonday:BAAANQAECgMIAwAAAA==.',
Cr='Cramberly:BAAANQADCggIDQAAAA==.Crispynips:BAAANQADCgYIDAAAAA==.Crnreaper:BAAANQADCgYICAAAAA==.Crotch:BAAANQABCgIIAgAAAA==.',
Da='Dabita:BAAANQAECgQICAAAAA==.Daewong:BAAANQAECgYICQAAAA==.Dagami:BAAANQADCggICgAAAA==.Daiganzan:BAAANQAECgMIAwAAAA==.Daisuke:BAAANQADCgUICQAAAA==.Dajango:BAAANQAECgEIAQAAAA==.Daknar:BAAANQADCggIDgAAAA==.Dalenvoidy:BAAANQADCgUICQAAAA==.Damâ:BAAANQADCgYIBgAAAA==.Dankharx:BAAANQABCgQIBAAAAA==.Darillia:BAAANQADCgIIAgAAAA==.Darkelas:BAAANQADCggICAAAAA==.Darknessbull:BAAANQAECgQIBAAAAA==.Daronn:BAAANQAECgEIAQAAAA==.Darthas:BAAANQADCgYICgAAAA==.Dashhunt:BAAANQAECgMIAwAAAA==.Davy:BAAANQAECgUIBQAAAQ==.',
De='Deadlyyrage:BAAANQADCgQIBgAAAA==.Deathkill:BAAANQADCgcIDQAAAA==.Deekay:BAAANQADCgYICAAAAA==.Deeri:BAAANQAECgEIAQAAAA==.Defyndk:BAAANQADCgIIAgABNQADCgYIBgABAAAAAA==.Defynds:BAAANQADCgYIBgAAAA==.Demoslayer:BAAANQADCgMIAwAAAA==.Denardiir:BAAANQADCggIFQABNQAECgEIAQABAAAAAA==.Desir:BAAANQAECgIIAgAAAA==.Detoxic:BAAANQAECgEIAQAAAA==.Dewdeath:BAAANQADCggIDQAAAA==.Dewdvoker:BAAANQAECgEIAQAAAA==.',
Di='Diabsoule:BAAANQADCgIIAgAAAA==.Dingodash:BAAANQADCgUIBQAAAA==.Diseased:BAAANQAECgMIAwAAAA==.Dizzimajizz:BAAANQAECgQIBAAAAA==.',
Dm='Dmgfordays:BAAANQAECgIIAgAAAA==.',
Do='Dogê:BAAANQAECgIIAgAAAA==.Domme:BAAANQADCggICAAAAQ==.Dornag:BAAANQADCgMIBgAAAA==.Downpour:BAAANQADCgYIBgAAAA==.',
Dr='Dragonhopes:BAAANQADCgYIBgAAAA==.Drakenkorin:BAAANQADCgMIAwAAAA==.Drated:BAAANQADCggIEAABNQAECgQICAABAAAAAA==.Drepung:BAAANQAECgEIAQAAAA==.Dretlok:BAAANQAECgEIAQAAAA==.',
Du='Duck:BAAANQADCgYICQAAAA==.Duckpunch:BAAANQAECgQIBQAAAA==.Dukhan:BAAANQAECgIIAgAAAA==.Durinsoñ:BAAANQAECgEIAQAAAA==.Durzy:BAAANQADCggIDQABNQAECgIIAgABAAAAAA==.',
Dw='Dworglaranna:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
Dy='Dying:BAAANQAECgQIBAAAAA==.Dylanspally:BAAANQAECgEIAQAAAA==.',
Ea='Eaglekick:BAAANQADCggIDgAAAA==.Easilyamused:BAAANQADCgYICwAAAA==.',
Ec='Eclips:BAAANQADCgYICwAAAA==.',
Ed='Eddo:BAAANQADCgYIBgAAAA==.Edrissa:BAAANQADCgYIBgAAAA==.',
El='Elandiel:BAAANQAECgQICAAAAA==.Elladale:BAAANQADCgcIDQAAAA==.Ellaxstrasza:BAAANQADCgIIAgAAAA==.Elleryl:BAAANQADCgYICgAAAA==.Ellisen:BAAANQADCgcIDgAAAA==.Elsaemonk:BAAANQADCgQIBAAAAA==.Elynna:BAAANQADCgYICQAAAA==.',
Em='Emmaroids:BAAANQADCgQIBQAAAA==.Emmuu:BAAANQADCgYIBwAAAA==.',
En='Enoc:BAAANQADCgYIBgAAAA==.',
Et='Etyeehaw:BAAANQAECgIIBAAAAA==.',
Ev='Evaêlfie:BAAANQADCgYICQAAAA==.Eviltank:BAAANQADCgYICAAAAA==.',
Ez='Ezzbot:BAAANQAECgEIAQAAAA==.',
Fa='Fabulously:BAAANQAECgQIBAABNQAECgYICAABAAAAAA==.Fallèn:BAAANQADCgYIBgAAAA==.Falnyr:BAAANQAECgQIBAAAAA==.Fanchone:BAAANQADCgQIBAAAAA==.Fandahvis:BAAANQAECgEIAQAAAA==.Faroosh:BAAANQADCgIIAgAAAA==.Fartshart:BAAANQADCgcIDQAAAA==.',
Fe='Felanthropy:BAAANQADCgcIGAAAAA==.Felbunny:BAAANQAECgEIAQAAAA==.Felinae:BAAANQADCgYIBgAAAQ==.Felmagus:BAAANQAECgIIAwAAAA==.Felrrak:BAAANQAECgcIEgAAAA==.Felstro:BAAANQADCgQIBAAAAA==.Felwynbrooke:BAAANQAECgMIAwAAAA==.Ferynis:BAAANQADCgYIDAAAAA==.',
Fi='Firekhan:BAAANQAECgEIAQAAAA==.Fistful:BAAANQAECgUIBwAAAA==.',
Fl='Flador:BAAANQADCgcIDQAAAA==.Flickatotem:BAAANQADCgQICwAAAA==.Florinka:BAAANQADCgYICgAAAA==.Fluffydecay:BAAANQADCgEIAQABNQAECgIIAwABAAAAAA==.Flumble:BAAANQADCgQICAAAAA==.Fluticasone:BAAANQADCgYIBgAAAA==.',
Fo='Forgedhorny:BAAANQADCgUIBgAAAA==.Fourcheeks:BAAANQAECgQIBAAAAA==.Fourthchild:BAAANQADCgQIBAAAAA==.Fozzydk:BAAANQADCgYIBgAAAA==.',
Fr='Frierén:BAAANQADCggIDAAAAA==.Frostburn:BAAANQABCgIIAQABNQADCgcIEAABAAAAAA==.Frostlass:BAAANQADCgQIBQAAAA==.Frostyflakez:BAAANQADCggICgAAAA==.Frostyfruit:BAAANQAECgIIAgAAAA==.',
Fu='Furnous:BAAANQAECgQIBwAAAA==.Fuzzydks:BAAANQADCgcICgABNQAECgQIBQABAAAAAA==.',
Ga='Galenddrel:BAAANQADCgIIAgAAAA==.Gant:BAAANQADCgMIAwAAAA==.Gargamus:BAAANQADCgIIAQAAAA==.',
Ge='Gemashdk:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.Gemashrogue:BAAANQAECgEIAQAAAA==.Gemtastic:BAAANQADCgIIAgAAAA==.',
Gh='Ghoolies:BAAANQADCgQICAABNQADCgcIDQABAAAAAA==.',
Gl='Glitterspark:BAAANQADCgYIBgAAAA==.Glitty:BAABNQAECoEcAAICAAgJgyBdAgAOAwACAAgJgyBdAgAOAwAAAA==.Glodslock:BAAANQADCgYICAAAAA==.',
Go='Goated:BAAANQADCgcIEAAAAA==.Goliathxx:BAAANQADCgIIAgAAAA==.Gonewe:BAAANQADCgcIEwAAAA==.Gongaga:BAAANQADCgMIAwAAAA==.Googam:BAAANQADCgEIAQAAAA==.Gornuts:BAAANQAECgEIAQAAAA==.Gosly:BAAANQAECgIIAgAAAA==.Gozhuntsurv:BAAANQABCgEIAQAAAA==.Gozrogueolaw:BAAANQADCgUIBQAAAA==.',
Gr='Grailliford:BAAANQADCgcIGAAAAA==.Grelle:BAAANQADCgQIBAAAAA==.Grimlock:BAAANQADCggICAAAAA==.Grimthursday:BAAANQADCggIDwABNQAECgMIAwABAAAAAA==.Grip:BAAANQAECgYICQAAAA==.Groxigar:BAAANQADCgQIBAAAAA==.Groxom:BAAANQADCgUIBQAAAA==.Grumpu:BAAANQADCgcIDwAAAA==.Grutok:BAAANQADCgcICAAAAA==.',
Gy='Gyftable:BAAANQAECgEIAQAAAA==.Gypsierose:BAAANQADCgcIEwAAAA==.',
['Gí']='Gíngervítis:BAAANQADCgEIAQAAAA==.',
['Gò']='Gòrilla:BAAANQADCgIIAgAAAA==.',
Ha='Hairytoad:BAAANQAECgIIBgAAAA==.Hardlightsgt:BAAANQADCgIIAgAAAA==.Harubless:BAAANQADCggICAAAAA==.Harushear:BAAANQAFFAEIAQAAAA==.Harushorn:BAAANQAECgUIBwAAAA==.Harvester:BAAANQAECgEIAQAAAA==.Havocbringer:BAAANQADCggIDgAAAA==.',
He='Headaxe:BAAANQADCgYIBgAAAA==.Healmemutt:BAAANQADCgYICAAAAA==.Hearte:BAAANQAECgQIBAAAAA==.Hermano:BAAANQAECgIIBAABNQAECgUIBQABAAAAAA==.Hermiscuous:BAAANQADCgQICgABNQAECgUIBQABAAAAAA==.Hermy:BAAANQAECgUIBQAAAA==.Herpys:BAAANQADCgYIBgAAAA==.Hexmachine:BAAANQAECgEIAQAAAA==.',
Hi='Hinters:BAAANQAECgEIAQAAAA==.',
Ho='Holing:BAAANQAECgUIBwAAAA==.Holybm:BAAANQADCgUICgAAAA==.Holyhealz:BAEANQAECgEIAgAAAA==.Honeyduke:BAAANQAECgIIAwAAAA==.Hopenottodie:BAAANQADCgYIDgAAAA==.Hopes:BAAANQAECgEIAQAAAA==.',
Hr='Hrulgath:BAAANQADCgQIAwAAAA==.',
Hu='Humbler:BAAANQADCgEIAQAAAA==.Huntum:BAAANQABCgEIAQAAAA==.Huntzha:BAAANQADCgYICgAAAA==.',
Hy='Hyndis:BAAANQADCgYIDAAAAA==.Hyorinmâru:BAAANQADCgcICgAAAA==.',
['Hí']='Híppiechick:BAAANQADCgcIEAAAAA==.',
Ia='Iamoutofammo:BAAANQADCgYICwAAAA==.Ianix:BAAANQAECgEIAQAAAA==.',
Ic='Iceni:BAAANQAECgEIAQAAAA==.',
Id='Idíot:BAAANQADCgcIEAAAAA==.',
If='Ifelforu:BAAANQAECgIIAgAAAA==.',
Il='Ilidun:BAAANQABCgIIAQAAAA==.Illimoo:BAAANQADCgYICwABNQADCgcICgABAAAAAA==.Ilumminus:BAAANQADCgQIBAABNQADCggICAABAAAAAA==.',
In='Incineratus:BAAANQAECgEIAQAAAA==.Ineci:BAAANQADCgQICAAAAA==.Infurrnal:BAAANQADCggICgAAAA==.Innerpeace:BAAANQADCgYICQAAAA==.Inspirez:BAAANQADCgYICAAAAA==.Instamissed:BAAANQADCgUIBQAAAA==.',
Ip='Ipooptotems:BAAANQADCgQIBgAAAA==.',
Ir='Ironbeard:BAAANQADCgMIAwAAAA==.',
Is='Ishootstuff:BAAANQAECgMIAwAAAA==.',
It='Itsnotbatman:BAAANQAECgEIAQAAAA==.',
Iv='Ivanra:BAAANQAECgIIAgAAAA==.',
Iz='Izlek:BAAANQAECgQIBQAAAA==.',
['Iì']='Iìe:BAAANQAECgQIBQAAAA==.',
Ja='Janeygirl:BAAANQAECgMIAwAAAA==.',
Je='Jeningze:BAAANQADCgUIBQAAAA==.Jestiny:BAAANQADCgcIDAAAAA==.Jezebel:BAAANQADCgQICAAAAA==.',
Jo='Johannuz:BAAANQAECgIIAgAAAA==.Johngoblikon:BAAANQADCgcIDQAAAA==.Johnyf:BAAANQADCgQIBgAAAA==.Jonesy:BAAANQAECgUIBwAAAA==.Jononononono:BAAANQAECgQIBAAAAA==.Jonz:BAAANQADCggIDQAAAA==.Joshington:BAAANQADCggIDgAAAA==.Jotuunnz:BAAANQADCgUIBQAAAA==.Jox:BAAANQADCgQIBAAAAA==.',
Ju='Juícyfruít:BAAANQABCgQIBwAAAA==.',
Ka='Kahlia:BAAANQADCgUICQAAAA==.Kaiden:BAAANQADCgYIBgAAAA==.Kalanix:BAAANQADCgcIEwAAAA==.Kanatari:BAAANQAECgEIAQAAAA==.Karaleigh:BAAANQAECgQIBAAAAA==.Kateley:BAAANQADCgYICgAAAA==.Kattadin:BAAANQADCgQIBAAAAA==.Kaybs:BAAANQADCgQIBAAAAA==.',
Ke='Kelanthus:BAAANQAECgMIAwAAAA==.Kellalas:BAAANQADCgQIBgAAAA==.Kelvinator:BAAANQADCgQIBgAAAA==.Kernni:BAAANQADCgYIDAAAAA==.',
Ki='Kirisera:BAAANQADCgcIEQAAAA==.Kittymik:BAAANQAECgIIAgAAAA==.Kixa:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
Kl='Klawfel:BAAANQADCgYICwAAAA==.',
Ko='Kohatu:BAAANQABCgIIAgAAAA==.Komoekomoe:BAAANQADCgUIAgAAAA==.Korrack:BAAANQADCgYICAAAAA==.Kotath:BAAANQADCgQIBQAAAA==.Kowbruh:BAAANQADCgUIBQAAAA==.',
Ku='Kuddy:BAAANQAECgQIBQAAAA==.Kumamizu:BAAANQADCgQIBgAAAA==.',
Kw='Kwr:BAAANQADCgcIDAAAAA==.Kwyn:BAAANQADCgQICAABNQAECgEIAQABAAAAAA==.',
['Kè']='Kèw:BAAANQADCgUICQAAAA==.',
La='Lacronista:BAAANQADCgYIBgAAAA==.Lazerchìckèn:BAAANQADCgQIBAAAAA==.',
Le='Lebronjr:BAAANQAECgQIBgAAAA==.Leere:BAAANQADCgYIBgAAAA==.Leeshpal:BAAANQADCgYIBgAAAA==.Legolash:BAAANQAECgEIAQAAAA==.Lemerix:BAAANQADCgUIBwAAAA==.Leniisha:BAAANQADCgYICwAAAA==.Lewy:BAAANQADCggIDQAAAA==.Lexicon:BAAANQAECgEIAQAAAA==.Lexxen:BAAANQAECgUIBgAAAA==.Leàfy:BAAANQAECgEIAQAAAA==.',
Li='Lightblade:BAAANQAECgMIAwAAAA==.Limonae:BAAANQAECgIIAgAAAA==.Lisellee:BAAANQADCgIIAgABNQADCgcIEwABAAAAAA==.',
Lo='Lockstøck:BAAANQAECgIIAwAAAA==.Lovemylamb:BAAANQAECgEIAQABNQAECgcIDgABAAAAAA==.',
Ls='Ls:BAAANQAECgQIBAAAAA==.',
Lu='Ludal:BAAANQADCgQICAAAAA==.Lunen:BAAANQAECgUIBwAAAA==.Lusidity:BAAANQADCggIDgAAAA==.',
Ly='Lythorn:BAAANQADCgcICwAAAA==.',
['Lè']='Lèpton:BAAANQADCgcIGAAAAA==.',
['Lé']='Léäf:BAAANQAECgMIAwAAAA==.',
['Lõ']='Lõx:BAAANQAECgQIBAAAAA==.',
Ma='Magestørm:BAAANQADCggIEgAAAA==.Magicboi:BAAANQADCgYIBwAAAA==.Magicmagnus:BAAANQADCgIIAgAAAA==.Magictacos:BAAANQAECgMIAwAAAA==.Magistrasza:BAAANQAECgUIBwAAAA==.Majkusanagi:BAAANQADCggIDwAAAA==.Makisig:BAAANQADCgcIDQAAAA==.Malfy:BAAANQADCgIIAgAAAA==.Malvnaire:BAAANQADCgEIAQAAAA==.Mancrak:BAAANQADCgIIAgAAAA==.Maraach:BAAANQAECgEIAQAAAA==.Mariandor:BAAANQADCgYICAAAAA==.Marlinn:BAAANQAECgUICQABNQAFFAIIAgABAAAAAA==.Marlos:BAAANQADCgYICAAAAA==.Marthaus:BAAANQADCgYIBgAAAA==.Martmist:BAAANQAECgMIAwAAAA==.Mateo:BAAANQADCgcIDgAAAA==.Mathias:BAAANQADCgcIDAAAAA==.Mattiass:BAAANQAECgIIAwAAAA==.Mattrik:BAAANQAECgEIAQAAAA==.Maximilia:BAAANQAECgMIAwAAAA==.Maydayx:BAAANQADCggIDwAAAA==.',
Mc='Mcdoom:BAAANQADCgQIBAABNQAECgIIAwABAAAAAA==.Mcduff:BAAANQADCgUICAAAAA==.',
Me='Meaningreen:BAAANQADCgUIBQAAAA==.Melzas:BAAANQADCgIIAgAAAA==.Messages:BAAANQABCgQIAwAAAA==.',
Mi='Midknîght:BAAANQADCgIIAgABNQADCgYIBgABAAAAAA==.Midwa:BAAANQAFFAEIAQAAAA==.Miishah:BAAANQADCgcIBwAAAA==.Minisaph:BAAANQADCgcIBwAAAA==.Missfun:BAAANQADCgcIDQAAAA==.Mistel:BAAANQADCgEIAQAAAA==.Mistyfuzz:BAAANQAECgQIBgAAAA==.Mithrendir:BAAANQADCggICAAAAA==.',
Mo='Mogimp:BAAANQADCgQIBwABNQADCggICgABAAAAAA==.Moguette:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Moistroll:BAAANQAECgEIAQABNQAECgIIAwABAAAAAA==.Molith:BAAANQABCgQIBQAAAA==.Monkkha:BAAANQADCgYICAAAAA==.Montecarlo:BAAANQAECgMIAwAAAA==.Moonhill:BAAANQAECgEIAQABNQAFFAEIAQABAAAAAA==.Moordenaar:BAAANQAECgEIAQAAAA==.Morphia:BAAANQADCgYIBgAAAA==.Mortarius:BAAANQADCgQIBgAAAA==.Movicol:BAAANQADCggICAAAAA==.Mozire:BAAANQADCgYICAAAAA==.Moñklee:BAAANQADCgUIBgABNQADCgYICwABAAAAAA==.',
Mt='Mtnaan:BAAANQADCgYIDAAAAA==.',
Mu='Muerteamigo:BAAANQADCgMIAQAAAA==.Murz:BAAANQADCgcIBwAAAA==.Musch:BAAANQADCgYIBgABNQAECgIIBgABAAAAAA==.Musde:BAAANQAECgIIBgAAAA==.Musterick:BAAANQADCgUIBAAAAA==.Muther:BAAANQADCgQICAAAAA==.',
My='Myctlan:BAAANQADCgYIDAAAAA==.Myrddn:BAAANQADCgIIAgAAAA==.Myrsham:BAAANQADCgYICAAAAA==.Mytearsheal:BAAANQADCgcIEAAAAA==.Mythbrediir:BAAANQAECgEIAQAAAA==.',
Na='Naadina:BAAANQADCgQICAAAAA==.Nadazarter:BAAANQADCgYIFgAAAA==.Naggo:BAAANQADCgUIBQAAAA==.Nalph:BAAANQADCgEIAQAAAA==.Narassii:BAAANQADCgMIAwAAAA==.Nathun:BAAANQADCgUIBQAAAA==.Navillas:BAAANQADCgcIGAAAAA==.Nayha:BAAANQADCgIIAgAAAA==.',
Ne='Nebulachimi:BAAANQAECgQICAAAAA==.Nebularyu:BAAANQADCgUIBwAAAA==.Nedimus:BAAANQADCgYIDQAAAA==.Nekhrimah:BAAANQAECgEIAQAAAA==.Neoaerith:BAAANQAECgIIAgAAAA==.Nerii:BAAANQADCgYIDAAAAA==.',
Ni='Niagarafall:BAAANQADCgIIAgAAAA==.Nidalàp:BAAANQADCgcIBwAAAA==.Nieriality:BAAANQAECgMIAwAAAA==.Nilin:BAAANQAECgEIAQAAAA==.Nina:BAAANQADCgYIBwABNQABCgIIAgABAAAAAA==.Nisulus:BAAANQADCgMIAgAAAA==.Niteañgel:BAAANQADCgcIDAAAAA==.Niç:BAAANQAECgEIAQAAAA==.',
No='Noctuana:BAAANQADCgQICgABNQADCgcIDQABAAAAAA==.Nojruh:BAAANQADCgQICAAAAA==.North:BAAANQAECgUIBQAAAA==.Notbeezy:BAAANQAECgIIAgAAAA==.Nox:BAAANQAECgYICgAAAA==.',
Nu='Numbnut:BAAANQADCgQIBAAAAA==.Numbskull:BAAANQADCgQIBAAAAA==.Numnutts:BAAANQAECgEIAQAAAA==.Nutelle:BAAANQADCgUIBwAAAA==.',
['Nè']='Nèrp:BAAANQAECgIIAgAAAA==.',
['Nú']='Númenórean:BAAANQAECgQICAAAAA==.',
['Nü']='Nüts:BAAANQADCgcIDQAAAA==.',
Ob='Obadiah:BAAANQABCgEIAQAAAA==.',
Og='Ogriv:BAAANQADCgQIBAAAAA==.',
Oi='Oii:BAAANQAECgEIAQAAAA==.',
Om='Omm:BAEANQADCgcIEwAAAA==.Omninan:BAAANQABCgEIAQAAAA==.',
Oo='Oos:BAAANQADCgQIBAAAAA==.',
Or='Oroqen:BAAANQADCgYICwAAAA==.',
Ou='Ouchiheal:BAAANQAECgUIBQAAAA==.',
Ov='Overhealer:BAAANQAECgUIBgAAAA==.',
['Oà']='Oàthor:BAAANQADCgEIAQAAAA==.',
Pa='Pachi:BAAANQADCgYIBgAAAA==.Paladipuss:BAAANQADCgYIBgAAAA==.Paladumb:BAABNQAECoEcAAMDAAgJUhTuEAAXAgADAAgJLBTuEAAXAgAEAAEJEAoZHQArAAAAAA==.Palatism:BAAANQAECgQIBAAAAA==.Panchovy:BAAANQAFFAIIAgAAAA==.Parrexion:BAAANQADCgEIAQAAAA==.',
Pe='Peculiar:BAAANQADCggIDQAAAA==.Peps:BAAANQADCggICAAAAA==.Peseshet:BAAANQADCgYICwAAAA==.',
Ph='Phantom:BAAANQADCgMIAwAAAA==.Phazonicide:BAAANQADCgYIBgAAAA==.Phlaea:BAAANQAECgEIAQAAAA==.',
Pi='Pieata:BAAANQADCgYIDQAAAA==.',
Po='Pogo:BAAANQAECgQICAAAAA==.Polkievoke:BAAANQADCgUIBQAAAA==.Pomdoes:BAAANQADCgMIAwAAAA==.Poppylotus:BAAANQADCgQIDAAAAA==.',
Pr='Precioùs:BAAANQAECgMIAwAAAA==.Prettyhectic:BAAANQAECgMIAwAAAA==.Prinsesdonut:BAAANQAECgEIAQAAAA==.Protagonist:BAAANQAFFAEIAgABNQAFFAMIBAABAAAAAA==.Prozium:BAAANQADCggIDgAAAA==.',
Pu='Purifythis:BAAANQADCgMIAwAAAA==.',
Py='Pyrotic:BAAANQADCgYICAAAAA==.',
['Pê']='Pêpsï:BAAANQABCgEIAQAAAA==.',
Qu='Quag:BAAANQADCgUIBQAAAA==.Quinny:BAAANQAECgEIAQAAAA==.Quintar:BAAANQAECgQIBwAAAA==.',
Ra='Raagnar:BAAANQADCgUIBQAAAA==.Rabbage:BAAANQADCggIDgAAAA==.Raeka:BAAANQADCggIDgAAAA==.Raenda:BAAANQADCgQIBAAAAA==.Ragarlem:BAAANQADCgYIBgAAAA==.Ragefright:BAAANQADCgcIBwABNQAECgYICgABAAAAAA==.Rageie:BAAANQADCgcICgAAAA==.Rageieboop:BAAANQADCgYICwAAAA==.Ragemore:BAAANQAECgIIAgAAAA==.Rahvine:BAAANQADCgUIBQAAAA==.Raiteq:BAAANQAECgMIAwAAAA==.Raitev:BAAANQAECgIIAgABNQAECgMIAwABAAAAAA==.Raputami:BAAANQAECgQIBAAAAA==.Rastoons:BAAANQADCgcIEwAAAA==.Rawlôck:BAAANQAECgUIBwAAAA==.Raxor:BAAANQADCgYIDAAAAA==.Raya:BAAANQADCgcIDQAAAA==.',
Re='Redoctobah:BAAANQADCgQIBgAAAA==.Reignrott:BAAANQAECgEIAQAAAA==.Replaceable:BAAANQABCgIIAwABNQAECgIIAgABAAAAAA==.Restorer:BAAANQAECgEIAQAAAA==.Retalica:BAAANQADCgYICAAAAA==.Retrishi:BAAANQAECgIIAgAAAA==.Retxbladés:BAAANQADCgQIBgAAAA==.Revelstat:BAAANQADCgMIBAAAAA==.Reverb:BAAANQAECgMIBAAAAA==.Rexsham:BAAANQAECgMIAwAAAA==.Rexyclog:BAAANQADCgMIBwAAAA==.Reyku:BAAANQADCgYICQAAAA==.',
Rh='Rhydon:BAAANQADCgIIAgAAAA==.',
Ri='Ricard:BAAANQADCgYIBgAAAA==.Rickettsia:BAAANQAECgEIAQAAAA==.Riderme:BAAANQAECgMIAwAAAA==.Rippen:BAAANQADCgYIDQAAAA==.',
Rl='Rlain:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
Ro='Robyngdfelow:BAAANQADCggIEAAAAA==.Rohovart:BAAANQADCgQIBgAAAA==.Rollingrick:BAAANQAECgEIAQAAAA==.',
Rp='Rpro:BAAANQADCgEIAQAAAA==.',
Rr='Rroach:BAAANQAECgEIAQAAAA==.',
Ru='Rustycrack:BAAANQADCgcICQAAAA==.',
Ry='Ryilla:BAAANQADCgcICwAAAA==.Rynoe:BAAANQADCgUIBwAAAA==.Ryujinx:BAAANQADCgEIAQAAAA==.',
['Rá']='Ráric:BAAANQADCggIDgAAAA==.',
Sa='Sableman:BAAANQADCgUICwAAAA==.Saccromycaes:BAAANQADCgQIBAAAAA==.Saclem:BAAANQADCgUIBgAAAA==.Saha:BAAANQADCgYICAAAAA==.Saintayah:BAAANQAECgUIBgAAAA==.Salokin:BAAANQADCgYIBgABNQAFFAEIAQABAAAAAA==.Salorellin:BAAANQAECgUIBwAAAA==.Sandrèena:BAAANQAECgEIAQAAAA==.Sanity:BAAANQAECgEIAQAAAA==.Sarakatawen:BAAANQADCgUIDwAAAA==.Satanah:BAAANQADCgUICQAAAA==.Satomi:BAAANQADCgUIBQAAAA==.Satre:BAAANQAECgIIAgAAAA==.',
Se='Seculoe:BAAANQAECgEIAQAAAA==.Seedypete:BAAANQADCgYICwAAAA==.Seemébloody:BAAANQAECgQIAwAAAA==.Seldarine:BAAANQADCgEIAQAAAA==.Selten:BAAANQADCgYICAAAAA==.Senescence:BAAANQAECgcIDgAAAA==.Sesshomar:BAAANQADCgEIAQAAAA==.Seventhchild:BAAANQADCgQIBAAAAA==.',
Sh='Sh:BAAANQAECgQIBAAAAA==.Shadopaw:BAAANQAECgMIAwAAAA==.Shadyllama:BAAANQAECgEIAQAAAA==.Shamkat:BAAANQADCgUICQAAAA==.Shammah:BAAANQAECgEIAQAAAA==.Shamuoo:BAAANQADCgQIBAAAAA==.Sharlo:BAAANQADCgMIBgAAAA==.Sharnie:BAAANQAECgEIAQAAAA==.Shellatrix:BAAANQAECgIIAgAAAA==.Shepp:BAAANQAECgEIAQAAAA==.Shootette:BAAANQAECgEIAQAAAA==.Shãmtastic:BAAANQADCgYIBgAAAA==.',
Si='Silandryn:BAAANQADCgEIAQAAAA==.Sinderela:BAAANQAECgQICAAAAA==.Sinisterwing:BAAANQAECgEIAQAAAA==.',
Sk='Skeptikk:BAAANQAECgUIBwAAAA==.Skinnery:BAAANQADCgQIBgAAAA==.Skrull:BAAANQAECgQIBAAAAA==.',
Sl='Slateray:BAAANQADCgcIDgAAAA==.',
Sm='Smaque:BAAANQADCgUIBQABNQADCgcIBwABAAAAAA==.Smegging:BAAANQADCgQIBAAAAA==.',
Sn='Snaare:BAAANQABCgIIBAAAAA==.',
So='Solcaris:BAAANQADCgYICAAAAA==.Sorie:BAAANQAECgIIAgAAAA==.Soùlstealer:BAAANQADCgQIBAAAAA==.',
Sp='Spatspell:BAAANQADCggICAAAAA==.Spazzy:BAAANQAECgQIBAAAAA==.Spenna:BAAANQADCgYIBgAAAA==.Spudacus:BAAANQAECgEIAQAAAA==.Spuddk:BAAANQAECgMIAwAAAA==.',
St='Stabforcash:BAAANQAECggICAAAAA==.Starleaf:BAAANQADCgQIBgAAAA==.Stellarluse:BAAANQADCgcIEwAAAA==.Stickler:BAAANQADCggIDwAAAA==.Stonque:BAAANQADCgcIBwAAAA==.Stormchief:BAAANQADCgIIAgAAAA==.Stormgoat:BAAANQADCgUIBwAAAA==.Stormie:BAAANQADCgcICwAAAA==.Streuth:BAAANQAECgUIBwAAAA==.Strummer:BAABNQAECoEcAAMFAAgJXSAjAwAIAwAFAAgJXSAjAwAIAwAGAAIJUxUhIACUAAAAAA==.',
Su='Subaru:BAAANQADCgYICAAAAA==.Subaruu:BAAANQADCgQIBAABNQADCgYICAABAAAAAA==.Subsiding:BAAANQADCgQIBAAAAA==.Subtera:BAAANQADCgcIBwAAAA==.Supagroova:BAAANQADCgIIAgAAAA==.Supernothing:BAAANQADCgUICAAAAA==.Superswede:BAAANQADCgYIDwAAAA==.',
Sw='Sworf:BAAANQAECgMIBAAAAA==.',
Sy='Syaarhunter:BAAANQADCgcICgAAAA==.Syaarknight:BAAANQADCgEIAQAAAA==.Syaarpally:BAAANQADCgYIBgAAAA==.Syazar:BAAANQADCgcIDQAAAA==.Sylanthia:BAAANQAECgEIAQAAAA==.',
['Só']='Sóg:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.',
['Sø']='Søg:BAAANQAECgMIAwAAAA==.',
['Sù']='Sùnjin:BAAANQADCgYICQABNQADCggICgABAAAAAA==.',
Ta='Tabknight:BAAANQAECgQIBAAAAA==.Taelron:BAAANQADCgMIBAAAAA==.Taelstard:BAAANQADCgcIEwAAAA==.Taichook:BAAANQADCgYIBgABNQAECgIIBAABAAAAAA==.Taithos:BAAANQAECgIIBAAAAA==.Taizen:BAAANQADCgUIBQAAAA==.Tanktough:BAAANQADCgUIBQAAAA==.Tarago:BAAANQAECgEIAgAAAA==.Taranisis:BAAANQADCgcICwAAAA==.Tasall:BAAANQADCgYICQAAAA==.Tauntflaunt:BAAANQAECgUIAwAAAA==.Tayy:BAAANQADCgEIAQAAAA==.',
Te='Tech:BAAANQAECgEIAQAAAA==.Tenkris:BAAANQADCgYIDgAAAA==.Tenleigh:BAAANQADCgYICAAAAA==.Terroria:BAAANQADCgYIBgABNQADCgcICQABAAAAAA==.Terrorizor:BAAANQADCgcIGAAAAA==.',
Th='Thalía:BAAANQADCgcIEQAAAA==.Thargroar:BAAANQAECgQIBAAAAA==.Thefluffyman:BAAANQAECgQIBAAAAA==.Thiss:BAAANQAECgEIAQAAAA==.Thordak:BAAANQADCgYICQAAAA==.Thoridian:BAAANQADCgQIBwAAAA==.Thurlarra:BAAANQADCgEIAQAAAA==.',
Ti='Titdor:BAAANQADCgIIAgAAAA==.',
To='Tobythemonk:BAAANQADCggIEAAAAA==.Toehacker:BAAANQAECgIIAgAAAA==.Tolkarkiller:BAAANQADCggIDgAAAA==.Tomarr:BAEANQAECgUIBwABNQADCggIEAABAAAAAA==.Tonsham:BAAANQADCgUIBwAAAA==.Totemspanker:BAAANQADCgQIBgAAAA==.Totoki:BAAANQADCggICAAAAA==.Touchitonce:BAAANQADCgUIBgAAAA==.Toxic:BAAANQADCgIIAgAAAA==.Toóz:BAAANQAECgIIAgAAAA==.',
Tr='Trailblayxur:BAAANQADCggIDgAAAA==.Traser:BAAANQADCgEIAQAAAA==.Trickyknight:BAAANQAECgIIBAAAAA==.Trickymage:BAAANQADCgUIBQAAAA==.',
Tu='Tuckerius:BAAANQADCgUIBQAAAA==.Turahk:BAAANQADCggIDgAAAA==.Turtlesoup:BAAANQAECgMIAwAAAA==.',
Tw='Twofoottall:BAAANQADCgMIAwAAAA==.',
Ty='Tylerolothus:BAAANQADCgMIAwAAAA==.Tynndera:BAAANQADCgcIDQAAAA==.Tyrawr:BAAANQAECgQIBAABNQAECgcIDQABAAAAAA==.Tyth:BAAANQAECgEIAQAAAA==.',
['Tí']='Tím:BAAANQAECgEIAQAAAA==.',
Ud='Udderlyfuzzy:BAAANQAECgIIAwAAAA==.',
Un='Unclegrandpa:BAAANQADCgQIBgAAAA==.',
Ur='Urôt:BAAANQADCggICAAAAA==.',
Uw='Uwusue:BAAANQAECgYIBwAAAA==.',
Va='Vaeline:BAAANQABCgEIAQAAAA==.Valac:BAAANQAECgcIDQAAAA==.Valkyrie:BAAANQAECgQIBAAAAA==.Valothos:BAAANQADCgcIGAAAAA==.Valtiell:BAAANQAECgUIBwAAAA==.Valuri:BAAANQAECgEIAQAAAA==.Varainne:BAAANQAECgEIAQAAAA==.',
Ve='Vegimitê:BAAANQADCgUIBQAAAA==.Vegymite:BAAANQADCgEIAQAAAA==.Velgath:BAAANQAECgcIDgAAAA==.Velkhana:BAAANQAECgIIAgAAAA==.Velmorra:BAAANQADCggIDgAAAA==.Veratis:BAAANQADCgYIDAAAAA==.',
Vi='Victoria:BAAANQADCgYICwAAAA==.Vinee:BAAANQADCgcIEwAAAA==.Vioneva:BAAANQAECgEIAQAAAA==.Viscelock:BAAANQAECgIIAgAAAA==.Vivyregosa:BAAANQAECgcIDQAAAA==.',
Vx='Vxi:BAAANQAFFAEIAQAAAA==.',
Wa='Wagglehoof:BAAANQADCgUIBQAAAA==.Wain:BAAANQADCgYIDAAAAA==.Wakantanka:BAAANQADCgcICwAAAA==.Wanglord:BAAANQAECgQIBQAAAA==.Warpig:BAAANQADCgUIBgAAAA==.Warriormilan:BAAANQADCgIIAgAAAA==.Waxedtaco:BAAANQADCgYICAAAAA==.',
Wh='Wheato:BAAANQAECgIIAgAAAA==.Whipshot:BAAANQADCggICAAAAA==.Whiteflame:BAAANQADCggIDwAAAA==.Whiteopal:BAAANQAECgEIAQAAAA==.',
Wi='Willowsun:BAAANQADCggIEAAAAA==.Wipe:BAAANQADCggICAABNQAFFAMIBAABAAAAAA==.',
Wo='Wolfyhunter:BAAANQADCgYIBgAAAA==.',
Wu='Wulfrick:BAAANQADCgMIBQAAAA==.',
['Wí']='Wítchypoo:BAAANQADCgYICwAAAA==.',
Xa='Xanetia:BAAANQADCgUICwAAAA==.Xatir:BAAANQADCgQIBwAAAA==.',
Xi='Xint:BAAANQABCgEIAQAAAA==.',
Xj='Xjaryl:BAAANQADCgcIDgAAAA==.',
Ya='Yamasharma:BAAANQADCgUIBgAAAA==.',
Ye='Yeehaww:BAAANQAECgEIAQAAAA==.',
Za='Zaharax:BAAANQADCgcIGAAAAA==.Zaharis:BAAANQAECgUIBQAAAA==.Zanakari:BAAANQADCgYIBgAAAA==.Zass:BAAANQADCgQIBAAAAA==.',
Ze='Zensetrazath:BAAANQAECgEIAQAAAA==.Zerath:BAAANQADCgYIBwAAAA==.',
Zh='Zhanqui:BAAANQADCggIDgAAAA==.',
Zi='Ziba:BAAANQAECgUIBwAAAA==.',
Zo='Zoroo:BAAANQAECgEIAQAAAA==.',
Zr='Zross:BAAANQADCgcIDAAAAA==.',
Zu='Zudo:BAAANQAECgIIAgAAAA==.Zuthrais:BAABNQAECoEcAAIHAAgJQwnLFQDcAQAHAAgJQwnLFQDcAQAAAA==.Zuulik:BAAANQADCgQICAAAAA==.',
Zz='Zz:BAAANQAFFAMIAwAAAA==.',
['Är']='Ärrôw:BAAANQADCgIIAgAAAA==.',
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
