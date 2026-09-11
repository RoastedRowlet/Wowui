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

local lookup = {'Unknown-Unknown','Shaman-Elemental','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','DemonHunter-Havoc','Evoker-Devastation','DemonHunter-Devourer','Monk-Windwalker','Paladin-Retribution','Paladin-Protection','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Blood','Mage-Arcane','Shaman-Enhancement',}
local provider = {region='US',realm="Aman'Thul",name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aadonis:BAAANQADCgIIAwAAAA==.Aanubus:BAAANQADCggIBwABNQADCggICQABAAAAAA==.Aarek:BAAANQABCgQIAgABNQAECgIIAgABAAAAAA==.',
Ab='Abyssalmaw:BAAANQAECgUIBgAAAA==.',
Ac='Achillesqt:BAAANQADCgIIAgAAAA==.Acionna:BAAANQADCggIDwAAAA==.',
Ad='Ada:BAAANQADCgIIAgAAAA==.Adekeahokeha:BAAANQADCgYIBQAAAA==.Adrenalin:BAAANQAECgQIBAAAAA==.',
Ae='Aedros:BAAANQAECgMIBAAAAA==.Aegis:BAAANQADCgIIAgAAAA==.Aellan:BAAANQAECgQICAAAAA==.',
Af='Afflexion:BAAANQADCggICAAAAA==.',
Ag='Agonier:BAAANQADCgUIBgAAAA==.',
Aj='Ajira:BAAANQADCgcIDwAAAA==.',
Ak='Akiaki:BAAANQAECgEIAgAAAA==.',
Al='Aladk:BAAANQAECgcIDAAAAA==.Alafus:BAAANQAECgMIAwABNQAECgcIDAABAAAAAA==.Alalock:BAAANQAECgEIAQABNQAECgcIDAABAAAAAA==.Alaria:BAAANQAECgQIBAABNQAECgcIEAABAAAAAA==.Alarian:BAAANQAECgYICQAAAA==.Aldai:BAAANQADCggIEgAAAA==.Alendros:BAAANQADCgIIAgAAAA==.Alexsia:BAAANQADCgEIAQAAAA==.Aliiah:BAAANQADCggICgAAAA==.Alir:BAAANQAECgcIDgAAAA==.Alista:BAAANQADCgIIAgAAAA==.Alle:BAAANQAECgIIAgAAAA==.Allen:BAAANQAECgUIBgAAAA==.Allyren:BAAANQAECgMIBAAAAA==.Allythriea:BAAANQADCgcIDQAAAA==.Althen:BAAANQADCggICAAAAA==.',
Am='Ambertwo:BAAANQADCggIFAAAAA==.Amitheria:BAAANQAECgEIAgAAAA==.',
An='Andreb:BAAANQAECgMIBAAAAA==.Andromyda:BAAANQADCgcIDQAAAA==.Angelofnite:BAAANQADCgcIDQAAAA==.Angrychicken:BAAANQADCgUIBQAAAA==.Ankh:BAAANQAECgMIAwAAAA==.Antopanto:BAAANQAECgMIBAAAAA==.',
Ar='Arasmina:BAAANQAECgcIDgAAAA==.Arcanystra:BAAANQADCgcICwAAAA==.Arcathal:BAAANQAECgYICgAAAA==.Arcshottx:BAAANQAECgMIBAAAAA==.Arliis:BAAANQAECgUIBgAAAA==.Arniy:BAAANQADCgYIDQABNQAECgcIEAABAAAAAA==.Artey:BAAANQAECgQIBAAAAA==.',
As='Ascot:BAAANQADCgQIBAABNQAECgMIBQABAAAAAA==.Asenathe:BAAANQADCggIAgAAAA==.Ashaad:BAAANQAECgIIAgAAAA==.Asyluun:BAAANQAECgEIAQAAAA==.',
At='Atorvas:BAAANQADCgMIAwAAAA==.',
Au='Auchioane:BAAANQAECgMIBAAAAA==.Aurelyia:BAAANQADCgYIEQAAAA==.',
Aw='Awakenimg:BAAANQADCgEIAQAAAA==.',
Az='Azador:BAAANQAECgMIBAAAAA==.Azael:BAAANQAECgQIBAAAAA==.Azarion:BAAANQADCgEIAQAAAA==.Azayzel:BAAANQADCgYIBgAAAA==.Azemm:BAAANQADCgYIBgABNQABCgIIAgABAAAAAA==.',
Ba='Backburner:BAAANQADCgMIAwAAAA==.Badvoodoo:BAAANQAECgIIBAAAAA==.Balahara:BAAANQADCgYIBgAAAA==.Balfor:BAAANQAECgUICAAAAA==.Bandarpallie:BAAANQADCgYICAAAAA==.Bara:BAAANQABCgMIAwAAAA==.Baynage:BAAANQAECgYIBgAAAA==.',
Be='Beastah:BAAANQADCgUICAAAAA==.Beauxmax:BAAANQADCgQIBAAAAA==.Beefkakes:BAAANQADCgEIAQAAAA==.Belest:BAAANQAECgEIAgAAAA==.Belfhee:BAAANQADCgEIAQAAAA==.Belkelmor:BAAANQADCgMIAwAAAA==.Bellaros:BAAANQAECgIIAgAAAA==.Belè:BAAANQAECgUICQAAAA==.Beorm:BAAANQADCgYICgAAAA==.Bermagi:BAAANQAECgIIAgAAAA==.',
Bi='Biders:BAAANQADCgEIAQAAAA==.Bigarchrules:BAAANQADCgUIBQAAAA==.Bigbanana:BAAANQAECgUIBgAAAA==.Bigdaddy:BAAANQAECgYIDQAAAA==.Bigrilla:BAAANQADCgYIEQAAAA==.Bigsecksi:BAAANQADCggIFAAAAA==.Bilbearbagns:BAAANQADCgYIBgAAAA==.Billkills:BAAANQADCgIIAgAAAA==.Billpie:BAAANQADCgYIBwAAAA==.Binkei:BAAANQADCgEIAQAAAA==.',
Bl='Blacksky:BAAANQADCgYIDwAAAA==.Blade:BAAANQAECgMIBAAAAA==.Blastette:BAAANQADCgYIDgAAAA==.Blayze:BAAANQAECgQICAAAAA==.Bloodclaw:BAAANQABCgUIBQAAAA==.Bloodgimp:BAAANQAECgQIBAAAAA==.Bloodlust:BAAANQAECgcIDQAAAA==.Bloodslay:BAAANQAECgUICgAAAA==.Bloodtank:BAAANQADCgYIBgAAAA==.Bluebrood:BAAANQAECgEIAQAAAA==.',
Bo='Boenarrow:BAAANQADCgYICgAAAA==.Bojack:BAAANQAECgUIBgAAAA==.Bombshot:BAAANQADCgYICAAAAA==.Boomdeeznutz:BAAANQADCgUICwAAAA==.Boomkinbill:BAAANQADCgEIAQAAAA==.Botmage:BAAANQAECgMIBAAAAA==.Bovinei:BAAANQADCgYICAAAAA==.',
Br='Brackk:BAAANQADCgYIBgAAAA==.Braedaevia:BAAANQAECgQIBAAAAA==.Brahnson:BAAANQADCgQICAAAAA==.Breldyr:BAAANQAECgUICQAAAA==.Bronnir:BAAANQADCgIIAgAAAA==.Brotis:BAAANQADCgcIDQAAAA==.Brylen:BAABNQAFFIELAAICAAYJrSIvAABnAgACAAYJrSIvAABnAgAAAA==.',
Bu='Bubblerat:BAAANQADCgYIBgAAAA==.Bullus:BAAANQAECgEIAQAAAA==.Buntz:BAAANQAECgcIDgAAAA==.',
Ca='Caain:BAAANQAECgQIBAAAAA==.Caalypso:BAAANQAECgUIEAAAAA==.Caileron:BAAANQADCggIIAAAAA==.Cakesnpies:BAAANQAECgQIBAAAAA==.Callofdeath:BAAANQADCgYICAAAAA==.Cancelyn:BAAANQADCgYIBwAAAA==.Capsmasher:BAAANQADCgYIBgAAAA==.Cashehm:BAAANQADCgcICgAAAA==.Caströ:BAAANQAECgEIAQAAAA==.',
Ce='Cecilbgnome:BAAANQADCgYIAgAAAA==.Celad:BAAANQAECgQIBQAAAA==.Cenedra:BAAANQAECgQIBAAAAA==.',
Ch='Chaihard:BAAANQADCgUIBQAAAA==.Cheesenonion:BAAANQADCgYICwABNQAECgQIBQABAAAAAA==.Chocolates:BAAANQADCgIIAgAAAA==.Chromitez:BAAANQAECgQIBQAAAA==.Chroren:BAAANQAECgUIBgAAAA==.Chubberz:BAAANQADCggICQABNQAECgYICAABAAAAAA==.Churlish:BAAANQAECgYIDQAAAA==.',
Cl='Clawyaeyeout:BAAANQADCgQIBAAAAA==.Cleavís:BAAANQAECgMIBAAAAA==.Cllu:BAAANQADCgcIBwAAAA==.',
Co='Cogedor:BAAANQADCgEIAQAAAA==.Colourzz:BAAANQABCgIIAgAAAA==.Corepia:BAAANQADCggIEgAAAA==.Cozymonday:BAAANQAECgQIBwAAAA==.',
Cr='Cramberly:BAAANQAECgEIAQAAAA==.Crikeys:BAAANQADCgMIAwAAAA==.Crispynips:BAAANQADCggIDgAAAA==.Crnreaper:BAAANQADCgYICAAAAA==.Crotch:BAAANQABCgIIAgAAAA==.',
Cu='Custodes:BAAANQADCgYIBgAAAA==.',
Da='Dabita:BAAANQAECgQIDgAAAA==.Daewong:BAAANQAECgcIEAAAAA==.Dagami:BAAANQADCggIDwAAAA==.Daiganzan:BAAANQAECgMIAwAAAA==.Daisuke:BAAANQADCgYIDwAAAA==.Dajango:BAAANQAECgMIBAAAAA==.Daknar:BAAANQAECgQIBAAAAA==.Dalenvoidy:BAAANQADCgcIEAAAAA==.Damâ:BAAANQADCgYIBgAAAA==.Dankharx:BAAANQABCgQIBgAAAA==.Darkelas:BAAANQADCggICAAAAA==.Darknessbull:BAAANQAECgYICgAAAA==.Daronn:BAAANQAECgYIBwAAAA==.Darthas:BAAANQADCggIEAAAAA==.Dashhunt:BAAANQAECgUICAAAAA==.Dashmagic:BAAANQADCgUIBQABNQAECgUICAABAAAAAA==.Davy:BAAANQAECgYICwAAAQ==.',
De='Deadlyyrage:BAAANQADCgUICwAAAA==.Deathkill:BAAANQADCgcIDQAAAA==.Deekay:BAAANQADCgYICAAAAA==.Deeri:BAAANQAECgMIBAAAAA==.Defyndk:BAAANQADCgIIAgABNQADCgYIBgABAAAAAA==.Defynds:BAAANQADCgYIBgAAAA==.Demonesla:BAAANQADCgMIAwAAAA==.Demoslayer:BAAANQADCgQIBgAAAA==.Denardiir:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.Desir:BAAANQAECgQIBgAAAA==.Desperate:BAAANQADCgUIBQAAAA==.Destanna:BAAANQADCgMIAwAAAA==.Detoxic:BAAANQAECgEIAQAAAA==.Dewdeath:BAAANQAECgEIAQAAAA==.Dewdvoker:BAAANQAECgEIAQAAAA==.',
Di='Diabsoule:BAAANQADCgIIAgAAAA==.Dilendra:BAAANQADCggICwABNQAECgIIBAABAAAAAA==.Diman:BAAANQADCgUIBQAAAA==.Dingodash:BAAANQADCgYIBgAAAA==.Diseased:BAAANQAECgUICAAAAA==.Dizzimajizz:BAAANQAECgUICAAAAA==.',
Dm='Dmgfordays:BAAANQAECgQIBgAAAA==.',
Do='Dogê:BAAANQAECgYICAAAAA==.Domme:BAAANQAECgYIBgAAAQ==.Dornag:BAAANQADCgMIBgAAAA==.Dovakin:BAAANQADCgUIBQAAAA==.Downpour:BAAANQADCgYICAAAAA==.',
Dr='Dragonhopes:BAAANQADCgYIBgAAAA==.Drakenkorin:BAAANQADCgMIAwAAAA==.Drated:BAAANQADCggIEAABNQAECggIGgADAI4PAA==.Drazalgor:BAAANQADCgIIBAAAAA==.Drepung:BAAANQAECgMIBQAAAA==.Dretlok:BAAANQAECgMIBAAAAA==.Droopyclam:BAAANQABCgQIBAAAAA==.',
Du='Duck:BAAANQADCgYICQAAAA==.Duckpunch:BAAANQAECgQIBgAAAA==.Dukhan:BAAANQAECgUIBwAAAA==.Dukkhadk:BAAANQAECgEIAQAAAA==.Durinsoñ:BAAANQAECgQIBQAAAA==.Durzy:BAAANQAECgEIAQABNQAECgYICgABAAAAAA==.Duskaryn:BAAANQAECggIAgAAAA==.',
Dw='Dworglaranna:BAAANQADCgQIBAABNQAECgMIBAABAAAAAA==.',
Dy='Dying:BAAANQAECgQIBAAAAA==.Dylanspally:BAAANQAECgQIBQAAAA==.',
Ea='Eaglekick:BAAANQADCggIFgAAAA==.Easilyamused:BAAANQADCggIEwAAAA==.',
Ec='Eclips:BAAANQAECgEIAQAAAA==.',
Ed='Eddo:BAAANQADCgYIBgAAAA==.Edrissa:BAAANQADCgYIBgAAAA==.',
El='Elandiel:BAABNQAECoEaAAQDAAgJjg+CJQDcAQADAAcJLRCCJQDcAQAEAAMJUwjJNACZAAAFAAEJ4wGzGQAjAAAAAA==.Elladale:BAAANQAECgEIAQAAAA==.Ellaxstrasza:BAAANQADCgUIBwAAAA==.Elleryl:BAAANQADCggIEgAAAA==.Ellisen:BAAANQADCgcIDgAAAA==.Elsaemonk:BAAANQADCgYICgAAAA==.Elynna:BAAANQADCgYICQAAAA==.',
Em='Emmaroids:BAAANQADCgQIBQAAAA==.Emmuu:BAAANQAECgQIBAABNQADCggICAABAAAAAA==.',
En='Enjoi:BAAANQADCgQIBAAAAA==.',
Et='Etyeehaw:BAAANQAECgQIDAAAAA==.',
Ev='Evaêlfie:BAAANQADCgYICQAAAA==.Eviltank:BAAANQAECgEIAQAAAA==.',
Ez='Ezzbot:BAAANQAECgUIBgAAAA==.',
Fa='Fabulously:BAAANQAECgQIBgABNQAECgYIEQABAAAAAA==.Fallèn:BAAANQADCgYIBgAAAA==.Falnyr:BAAANQAECgUIDgAAAA==.Fanchone:BAAANQADCgYICgAAAA==.Fandahvis:BAAANQAECgMIBAAAAA==.Faroosh:BAAANQADCgUIBwAAAA==.Fartshart:BAAANQAECgEIAQAAAA==.',
Fe='Fearus:BAAANQABCgQIBQAAAA==.Felanthropy:BAAANQAECgEIAQAAAA==.Felbunny:BAAANQAECgUIBgAAAA==.Felinae:BAAANQADCggIDgAAAQ==.Felmagus:BAAANQAECgMIBAAAAA==.Felrrak:BAABNQAECoEmAAIGAAgJLhdBCwBhAgAGAAgJLhdBCwBhAgAAAA==.Felstro:BAAANQAECgEIAQAAAA==.Felwynbrooke:BAAANQAECgQIBwAAAA==.Ferynis:BAAANQADCggIFAAAAA==.',
Fi='Firekhan:BAAANQAECgUIBgAAAA==.Fistful:BAAANQAECgcIDgAAAA==.',
Fl='Flador:BAAANQAECgMIAwAAAA==.Flickatotem:BAAANQADCgYIDwAAAA==.Florinka:BAAANQADCggIEgAAAA==.Fluffydecay:BAAANQADCgEIAQABNQAECgQIBAABAAAAAA==.Flumble:BAAANQADCgQICAAAAA==.Fluticasone:BAAANQADCgYIBgAAAA==.',
Fo='Forgedhorny:BAAANQADCgUIBgAAAA==.Fourcheeks:BAAANQAECgYICgAAAA==.Fourthchild:BAAANQADCgQIBAAAAA==.Fozzydk:BAAANQADCgYIBgAAAA==.',
Fr='Frierén:BAAANQADCggIFAAAAA==.Frostburn:BAAANQABCgIIAQABNQADCgcIFgABAAAAAA==.Frostlass:BAAANQADCgQIBQAAAA==.Frostyflakez:BAAANQADCggIEgAAAA==.Frostyfruit:BAAANQAECgQIBgAAAA==.',
Fu='Furnous:BAAANQAECgYIEgAAAA==.Fuzzydks:BAAANQADCggIEgABNQAECgUIBgABAAAAAA==.',
Ga='Galenddrel:BAAANQADCgIIAgAAAA==.Gant:BAAANQADCgUICAAAAA==.Gargamus:BAAANQAECgQIBAAAAA==.',
Ge='Gemashdk:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.Gemashrogue:BAAANQAECgIIAgAAAA==.Gemtastic:BAAANQADCgIIAgAAAA==.Georgieanne:BAAANQADCgUICwAAAA==.',
Gh='Ghazali:BAAANQADCggICAAAAA==.Gheru:BAAANQADCgUIBQAAAA==.Ghoolies:BAAANQADCgYIDgABNQAECgMIAwABAAAAAA==.',
Gi='Gildartz:BAAANQADCgYIBgAAAA==.',
Gl='Glitterspark:BAAANQADCggIDQAAAA==.Glittr:BAAANQADCgQIBAABNQAECggILAAHALcjAA==.Glitty:BAABNQAECoEsAAIHAAgJtyOCAgBOAwAHAAgJtyOCAgBOAwAAAA==.Glodslock:BAAANQADCgYICAAAAA==.',
Go='Goated:BAAANQADCgcIFgAAAA==.Goliathxx:BAAANQADCgIIAwAAAA==.Gonewe:BAAANQADCggIIAAAAA==.Gongaga:BAAANQADCgYICQAAAA==.Googam:BAAANQAECgQIBAAAAA==.Gornuts:BAAANQAECgMIBAAAAA==.Gosly:BAAANQAECgYICAAAAA==.Gozhuntsurv:BAAANQABCgEIAQAAAA==.Gozrogueolaw:BAAANQADCgUIBQAAAA==.',
Gr='Grailliford:BAAANQAECgEIAQAAAA==.Greeneyes:BAAANQADCgMIAwAAAA==.Grelle:BAAANQADCgQIBAAAAA==.Grimlock:BAAANQADCggICAAAAA==.Grimthursday:BAAANQADCggIDwABNQAECgUICAABAAAAAA==.Grip:BAAANQAECgYIDgAAAA==.Groxigar:BAAANQADCgQIBAAAAA==.Groxom:BAAANQADCgUIBQAAAA==.Grumpu:BAAANQADCgcIDwAAAA==.Grutok:BAAANQAECgIIAgAAAA==.',
Gu='Guzwar:BAAANQAECgIIBAAAAA==.',
Gy='Gyftable:BAAANQAECgMIBAAAAA==.Gypsierose:BAAANQADCgcIGwAAAA==.',
['Gí']='Gíngervítis:BAAANQADCgEIAQAAAA==.',
['Gï']='Gïmli:BAAANQADCgEIAQAAAA==.',
['Gò']='Gòrilla:BAAANQADCgQIBgAAAA==.',
Ha='Hairytoad:BAAANQAECgUIEAAAAA==.Hardlightsgt:BAAANQADCgIIAgAAAA==.Harubless:BAAANQADCggICAAAAA==.Harushear:BAACNQAFFIEGAAIIAAUJfRjLAADhAQAIAAUJfRjLAADhAQA1AAQKgRoAAggACQmbJFMBALgDAAgACQmbJFMBALgDAAAA.Harushorn:BAAANQAECgUIBwAAAA==.Harvester:BAAANQAECgEIAgAAAA==.Havocbringer:BAAANQADCggIDgAAAA==.',
He='Headaxe:BAAANQAECgQIBAAAAA==.Healmemutt:BAAANQAECgEIAgAAAA==.Hearte:BAAANQAECgYICgAAAA==.Hellweaver:BAAANQADCgYIBgAAAA==.Hermano:BAAANQAECgQICAABNQAECgUIBQABAAAAAA==.Hermiscuous:BAAANQADCgUIDwABNQAECgUIBQABAAAAAA==.Hermy:BAAANQAECgUIBQAAAA==.Herpys:BAAANQADCgYIBgAAAA==.Hexmachine:BAAANQAECgMIBAAAAA==.',
Hi='Hinters:BAAANQAECgMIBAAAAA==.',
Ho='Holing:BAAANQAECgcIDgAAAA==.Holybm:BAAANQADCgUICgAAAA==.Holyhealz:BAEANQAECgEIAgAAAA==.Honeyduke:BAAANQAECgIIBAAAAA==.Hopenottodie:BAAANQAECgEIAQAAAA==.Hopes:BAAANQAECgMIBAAAAA==.',
Hr='Hrulgath:BAAANQADCgQIAwAAAA==.',
Hu='Humbler:BAAANQADCgEIAQAAAA==.Huntum:BAAANQADCgUIBQAAAA==.Huntzha:BAAANQADCggIEgAAAA==.',
Hy='Hyndis:BAAANQADCggIFAAAAA==.Hyorinmâru:BAAANQADCggIDAAAAA==.',
['Hí']='Híppiechick:BAAANQADCgcIEAAAAA==.',
Ia='Iamoutofammo:BAAANQADCggIEwAAAA==.Ianix:BAAANQAECgQIBQAAAA==.',
Ic='Iceni:BAAANQAECgMIBAAAAA==.',
Id='Idíot:BAAANQADCggIHQAAAA==.',
If='Ifelforu:BAAANQAECgIIAgAAAA==.',
Ih='Ihaslegs:BAAANQADCgcIBwAAAA==.',
Il='Ilidun:BAAANQABCgIIAQAAAA==.Illimoo:BAAANQADCggIEwAAAA==.Ilumminus:BAAANQADCgQIBwABNQADCggIDwABAAAAAA==.',
Im='Imoldgrèg:BAAANQADCgMIAwABNQAECgQIBQABAAAAAA==.',
In='Incineratus:BAAANQAECgMIBAAAAA==.Ineci:BAAANQADCgYIDgAAAA==.Infurrnal:BAAANQAECgQIBAAAAA==.Innerpeace:BAAANQAECgEIAQAAAA==.Inspirez:BAAANQADCgYICAAAAA==.Instamissed:BAAANQADCgUIBQAAAA==.Intolerence:BAAANQADCgIIAgAAAA==.',
Ip='Ipooptotems:BAAANQADCgcIDQAAAA==.',
Ir='Ironbeard:BAAANQADCgMIAwAAAA==.',
Is='Ishootstuff:BAAANQAECgYICQAAAA==.',
It='Itsnotbatman:BAAANQAECgUIBgAAAA==.',
Iv='Ivanra:BAAANQAECgYICAAAAA==.',
Iz='Izlek:BAAANQAECgUICgAAAA==.',
['Iì']='Iìe:BAAANQAECgYICwAAAA==.',
Ja='Jagermaster:BAAANQADCgMIAwAAAA==.Janeygirl:BAAANQAECgUICAAAAA==.',
Je='Jeningze:BAAANQADCgYIBgAAAA==.Jestiny:BAAANQAECgEIAQAAAA==.Jezebel:BAAANQADCgYIDgAAAA==.',
Jo='Johannuz:BAAANQAECgMIBQAAAA==.Johngoblikon:BAAANQADCgcIDQAAAA==.Johnyf:BAAANQADCgcIDQAAAA==.Jonesy:BAAANQAECgcIDgAAAA==.Jononononono:BAAANQAECgYICgAAAA==.Jonz:BAAANQAECgQIBAAAAA==.Joshington:BAAANQAECgEIAQAAAA==.Jotuunnz:BAAANQADCgUIBQAAAA==.Jox:BAAANQADCgQIBAAAAA==.',
Ju='Juícyfruít:BAAANQABCgQIBwAAAA==.',
Ka='Kahlia:BAAANQADCgcIEAAAAA==.Kaiden:BAAANQADCgYIBgAAAA==.Kalanix:BAAANQADCgcIGwAAAA==.Kalji:BAAANQADCgcIBwABNQAECgcIEAABAAAAAA==.Kanatari:BAAANQAECgEIAQAAAA==.Kansch:BAAANQADCgMIAwABNQAECgUIEAABAAAAAA==.Karaleigh:BAAANQAECgYICgAAAA==.Katallia:BAAANQADCggICAAAAA==.Kateley:BAAANQADCggIEgAAAA==.Kattadin:BAAANQADCgcICwAAAA==.Kaybs:BAAANQADCggIDAAAAA==.',
Ke='Kelanthus:BAAANQAECgQIBwAAAA==.Kellalas:BAAANQADCgUICwAAAA==.Kelvinator:BAAANQADCgYICAAAAA==.Kernni:BAAANQADCggIFAAAAA==.Kes:BAAANQADCgYIBgAAAA==.',
Ki='Kirisera:BAAANQADCggIGwAAAA==.Kittymik:BAEANQAECgMIBQABNQAECgYICQABAAAAAA==.Kixa:BAAANQADCgQIBAABNQAECgMIBAABAAAAAA==.',
Kl='Klawfel:BAAANQADCgYICwAAAA==.',
Ko='Kohatu:BAAANQABCgIIAgAAAA==.Komoekomoe:BAAANQADCgUIAgAAAA==.Kormath:BAAANQABCgIIAgAAAA==.Korrack:BAAANQADCgYICAAAAA==.Korruptoor:BAAANQABCgQIBAAAAA==.Kotath:BAAANQADCgUIBwAAAA==.Kowbruh:BAAANQADCgYICwAAAA==.',
Ku='Kuddy:BAAANQAECgQICAAAAA==.Kumamizu:BAAANQADCgcIDQAAAA==.',
Kw='Kwr:BAAANQADCggIFQAAAA==.Kwyn:BAAANQADCgYIDgABNQAECgMIBAABAAAAAA==.',
Ky='Kyxa:BAAANQADCgYIBgABNQAECgMIBAABAAAAAA==.',
['Kè']='Kèw:BAAANQADCgcIEAAAAA==.',
La='Lacronista:BAAANQADCggIDgAAAA==.Lagavulin:BAAANQADCgcIBwAAAA==.Landacious:BAAANQADCgUIBQAAAA==.Lazerchìckèn:BAAANQADCgQIBAAAAA==.',
Le='Lebronjr:BAAANQAECgQIBwAAAA==.Leere:BAAANQADCgYIBgAAAA==.Leeshpal:BAAANQADCgYICAAAAA==.Legolash:BAAANQAECgMIBAAAAA==.Lemerix:BAAANQADCgUIBwAAAA==.Leniisha:BAAANQADCgYIEQAAAA==.Lewy:BAAANQAECgEIAgAAAA==.Lexicon:BAAANQAECgUIBgAAAA==.Lexxen:BAAANQAECgYIDAAAAA==.Leàfy:BAAANQAECgQIBQAAAA==.',
Li='Lightblade:BAAANQAECgUICAAAAA==.Lilibewhan:BAAANQABCgEIAQAAAA==.Limonae:BAAANQAECgIIBQAAAA==.Lisellee:BAAANQADCgIIAgABNQADCggIIAABAAAAAA==.',
Ll='Lljunior:BAAANQABCgMIAwAAAA==.',
Lo='Locha:BAAANQAECgEIAgAAAA==.Lockstøck:BAAANQAECgUICAAAAA==.Longicorn:BAAANQADCgYIBgABNQAECgYIDwABAAAAAA==.Lostváyne:BAAANQADCgYIBgAAAA==.Lovemylamb:BAAANQAECgEIAQABNQAECgkJHQADAEAjAA==.',
Ls='Ls:BAAANQAECgQICAAAAA==.',
Lu='Ludal:BAAANQADCgYIDgAAAA==.Luketism:BAAANQAECgIIAgAAAA==.Lunen:BAAANQAECgcIDgAAAA==.Lusidity:BAAANQADCggIDgAAAA==.',
Ly='Lythorn:BAAANQAECgEIAQAAAA==.',
['Lè']='Lèpton:BAAANQAECgEIAQAAAA==.',
['Lé']='Léäf:BAAANQAECgUICAAAAA==.',
['Lõ']='Lõx:BAAANQAECgUICQAAAA==.',
Ma='Madamgrey:BAAANQAECgQIBAAAAA==.Maebyfunke:BAAANQADCggICAAAAA==.Magestørm:BAAANQAECgUIBQAAAA==.Magicboi:BAAANQADCgcIDQAAAA==.Magicmagnus:BAAANQADCgYICAAAAA==.Magictacos:BAAANQAECgQIBwAAAA==.Magistrasza:BAAANQAECgcIDgAAAA==.Majkusanagi:BAAANQAECgQIBAAAAA==.Makisig:BAAANQADCgcIFAAAAA==.Malfy:BAAANQAECgEIAQAAAA==.Malvnaire:BAAANQADCgEIAQAAAA==.Mancrak:BAAANQADCgIIAgAAAA==.Maraach:BAAANQAECgQIBQAAAA==.Mariandor:BAAANQADCgYICAAAAA==.Marlinn:BAAANQAECgYIDwABNQAECgkJGAAJABobAA==.Marlos:BAAANQAECgEIAQAAAA==.Marrmite:BAAANQADCgYIBgAAAA==.Marthaus:BAAANQADCgYIBgABNQAECgUICAABAAAAAA==.Martmist:BAAANQAECgUICAAAAA==.Mateo:BAAANQADCggIEgAAAA==.Mathias:BAAANQADCggIFAAAAA==.Mattiass:BAAANQAECgMIBgAAAA==.Mattrik:BAAANQAECgMIBAAAAA==.Maximilia:BAAANQAECgYICQAAAA==.Maydayx:BAAANQADCggIDwAAAA==.',
Mc='Mcdoom:BAAANQAECgQIBAAAAA==.Mcduff:BAAANQADCgcIDwAAAA==.',
Me='Meaningreen:BAAANQADCgcIDAAAAA==.Mekuntizichi:BAAANQADCgcICAAAAA==.Melazaelf:BAAANQADCgMIAwAAAA==.Melzas:BAAANQADCgIIAgAAAA==.Messages:BAAANQADCggICAAAAA==.',
Mi='Midknîght:BAAANQADCgIIAgABNQADCgYIBgABAAAAAA==.Midwa:BAACNQAFFIEFAAIKAAQJZhrcAAB7AQAKAAQJZhrcAAB7AQA1AAQKgRkAAgoACQlmJsUAAO8DAAoACQlmJsUAAO8DAAAA.Miishah:BAAANQAECgQIAwAAAA==.Minisaph:BAAANQADCgcIBwAAAA==.Missfun:BAAANQAECgEIAQAAAA==.Mistel:BAAANQADCgEIAQAAAA==.Mistyfuzz:BAAANQAECgQIBgAAAA==.Mithrendir:BAAANQADCggIDwAAAA==.',
Mo='Mogimp:BAAANQADCgQIBwABNQAECgQIBAABAAAAAA==.Moguette:BAAANQAECgQIBQABNQAECgQIBQABAAAAAA==.Moistroll:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Molith:BAAANQABCgYICAAAAA==.Monkkha:BAAANQADCgYICAAAAA==.Montecarlo:BAAANQAECgQIBQAAAA==.Moonhill:BAAANQAECgEIAQAAAA==.Moordenaar:BAAANQAECgMIBAAAAA==.Morgainne:BAAANQADCgEIAQAAAA==.Morphia:BAAANQADCgYIBgAAAA==.Mortarius:BAAANQADCgcIDQAAAA==.Movicol:BAAANQAECgEIAQAAAA==.Mozire:BAAANQADCgYICAAAAA==.Moñklee:BAAANQADCgUIBgABNQADCgYICwABAAAAAA==.',
Mt='Mtnaan:BAAANQAECgEIAQAAAA==.',
Mu='Muerteamigo:BAAANQADCgMIAQAAAA==.Murz:BAAANQADCggIEQAAAA==.Musch:BAAANQADCgYIBgABNQAECgUIEAABAAAAAA==.Musde:BAAANQAECgUIEAAAAA==.Musterick:BAAANQAECgEIAQAAAA==.Muther:BAAANQAECgEIAQAAAA==.',
My='Myctlan:BAAANQADCgYIEgAAAA==.Myrddn:BAAANQADCgUIDAAAAA==.Myrdi:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Myrsham:BAAANQAECgEIAQAAAA==.Mytearsheal:BAAANQAECgEIAQAAAA==.Mythbrediir:BAAANQAECgQIBQAAAA==.',
Na='Naadina:BAAANQADCgYIDgAAAA==.Nadazarter:BAAANQADCggIHgAAAA==.Naggo:BAAANQADCgYIBwAAAA==.Nalph:BAAANQADCgEIAQAAAA==.Narassii:BAAANQADCgMIAwAAAA==.Nathun:BAAANQAECgIIAgAAAA==.Navillas:BAAANQAECgEIAQAAAA==.Nayha:BAAANQAECgEIAQAAAA==.',
Ne='Nebulachimi:BAAANQAECgUIEgAAAA==.Nebularyu:BAAANQADCgUICgAAAA==.Nedimus:BAAANQAECgMIBgABNQAECgEIAgABAAAAAA==.Nekhrimah:BAAANQAECgEIAQAAAA==.Neoaerith:BAAANQAECgIIAgAAAA==.Nerii:BAAANQAECgEIAQAAAA==.Nerpthas:BAAANQAECgIIAwAAAA==.',
Ni='Niagarafall:BAAANQADCgIIAgAAAA==.Nidalàp:BAAANQADCgcIBwAAAA==.Nieriality:BAAANQAECgQICwAAAA==.Nilin:BAAANQAECgQIBQAAAA==.Nina:BAAANQAECgQIBAABNQABCgIIAgABAAAAAA==.Nisulus:BAAANQADCgYIDgAAAA==.Niteañgel:BAAANQADCggIFAAAAA==.Niç:BAAANQAECgMIBAAAAA==.',
No='Noctuana:BAAANQADCgUIDwABNQADCggIFQABAAAAAA==.Nojruh:BAAANQADCgQICAAAAA==.North:BAAANQAECgYICwAAAA==.Notbeezy:BAAANQAECgQIBgAAAA==.Nox:BAAANQAECggIDwAAAA==.',
Nu='Numbnut:BAAANQADCgQIBAAAAA==.Numbskull:BAAANQADCgQIBAAAAA==.Numnutts:BAAANQAECgQIBQAAAA==.Nutelle:BAAANQADCgYIBwAAAA==.',
['Nè']='Nèrp:BAAANQAECgYICAAAAA==.',
['Nú']='Númenórean:BAAANQAECgUIDgAAAA==.',
['Nü']='Nüts:BAAANQAECgMIAwAAAA==.',
Ob='Obadiah:BAAANQADCgYIBgAAAA==.',
Og='Ogriv:BAAANQADCgUIBwAAAA==.',
Oi='Oii:BAAANQAECgEIAQAAAA==.',
Ol='Olunaija:BAAANQADCggICgAAAA==.',
Om='Omm:BAEANQADCggIIAAAAA==.Omninan:BAAANQABCgEIAQAAAA==.',
Oo='Oos:BAAANQADCgQIBAAAAA==.',
Or='Oroqen:BAAANQAECgIIAgAAAA==.',
Ou='Ouchiheal:BAAANQAECgcICgAAAA==.',
Ov='Overhealer:BAAANQAECgcIDQAAAA==.',
['Oà']='Oàthor:BAAANQADCgIIAgAAAA==.',
Pa='Pachi:BAAANQADCgYICwAAAA==.Paladipuss:BAAANQADCgYICgAAAA==.Paladumb:BAABNQAECoEsAAMKAAgJmhs5EwCyAgAKAAgJmhs5EwCyAgALAAEJEArFLwAoAAAAAA==.Palatism:BAAANQAECgYICgAAAA==.Panchovy:BAABNQAECoEYAAIJAAkJGhvsBQDcAgAJAAkJGhvsBQDcAgAAAA==.Parrexion:BAAANQADCgEIAQAAAA==.',
Pe='Peculiar:BAAANQAECgEIAQAAAA==.Pegor:BAAANQADCgEIAQABNQADCggIIAABAAAAAA==.Peps:BAAANQADCggICAAAAA==.Peseshet:BAAANQADCggIEwAAAA==.',
Ph='Phantom:BAAANQADCgQIBQAAAA==.Phatboii:BAAANQADCgYIBgAAAA==.Phazonicide:BAAANQADCgYIBgAAAA==.Phlaea:BAAANQAECgMIBAAAAA==.',
Pi='Pieata:BAAANQADCgYIEgAAAA==.',
Po='Pogo:BAAANQAECgQICAAAAA==.Poisoning:BAAANQADCgIIAgAAAA==.Poknat:BAAANQADCggICAAAAA==.Polkievoke:BAAANQADCgUIBQAAAA==.Pomdoes:BAAANQADCgMIAwAAAA==.Poppylotus:BAAANQADCgYIEgAAAA==.Postee:BAAANQADCggICAABNQADCggICQABAAAAAA==.',
Pr='Precioùs:BAAANQAECgUICAAAAA==.Prettyhectic:BAAANQAECgcIDAAAAA==.Priincebun:BAAANQAECggICAAAAA==.Prinsesdonut:BAAANQAECgMIBAAAAA==.Projecjx:BAAANQADCgYICgAAAA==.Protagonist:BAABNQAECoEVAAMGAAkJ/CAcBwDNAgAGAAgJfiAcBwDNAgAIAAUJVRRTJwBIAQABNQAFFAYICwACAK0iAA==.Prozium:BAAANQAECgQIBAABNQABCgQIAwABAAAAAA==.',
Pu='Purifythis:BAAANQADCgMIAwAAAA==.',
Py='Pyrotic:BAAANQADCgYICAAAAA==.',
['Pê']='Pêpsï:BAAANQABCgEIAQAAAA==.',
Qu='Quag:BAAANQADCgYIBwAAAA==.Quinny:BAAANQAECgMIBAAAAA==.Quintar:BAAANQAECgYIDQAAAA==.',
Ra='Raagnar:BAAANQADCgYIBgAAAA==.Rabbage:BAAANQAECgMIAwAAAA==.Raeka:BAAANQADCggIFgAAAA==.Raenda:BAAANQADCgYICgAAAA==.Ragarlem:BAAANQADCgYIDAAAAA==.Ragefright:BAAANQAECgYIBgABNQAECggIDwABAAAAAA==.Rageie:BAAANQADCggIEgAAAA==.Rageieboop:BAAANQADCggIEwAAAA==.Ragemore:BAAANQAECgQIBgAAAA==.Rahvine:BAAANQADCgcIDAAAAA==.Raiteq:BAAANQAECgQIBQAAAA==.Raitev:BAAANQAECgIIAgABNQAECgQIBQABAAAAAA==.Raputami:BAAANQAECgYICAAAAA==.Rastoons:BAAANQADCggIFQAAAA==.Rawlôck:BAAANQAECgcIDgAAAA==.Raxor:BAAANQADCggIFAAAAA==.Raya:BAAANQAECgEIAQAAAA==.',
Rd='Rde:BAAANQABCgYIBwAAAA==.',
Re='Redoctobah:BAAANQADCgcIDQAAAA==.Regret:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.Reignrott:BAAANQAECgMIBAAAAA==.Reika:BAAANQADCgIIAgAAAA==.Replaceable:BAAANQABCgIIAwABNQAECgUIBAABAAAAAA==.Reptizzle:BAAANQADCgQIBAAAAA==.Restorer:BAAANQAECgEIAgAAAA==.Retalica:BAAANQAECgEIAQAAAA==.Retrishi:BAAANQAECgIIBQAAAA==.Retxbladés:BAAANQADCgUICQAAAA==.Revelstat:BAAANQADCgQIBgAAAA==.Reverb:BAAANQAECgUICQAAAA==.Rexsham:BAAANQAECgYICQAAAA==.Rexyclog:BAAANQADCggIFAAAAA==.Reyku:BAAANQAECgEIAQAAAA==.',
Rh='Rhydon:BAAANQADCgIIAgAAAA==.',
Ri='Ricard:BAAANQADCgYIBgAAAA==.Rickettsia:BAAANQAECgMIBAAAAA==.Riderme:BAAANQAECgMIBgAAAA==.Rig:BAAANQADCggICAAAAA==.Rildis:BAAANQADCgcIBwABNQADCggIDAABAAAAAA==.Rippen:BAAANQADCgYIDQAAAA==.',
Rl='Rlain:BAAANQADCgQIBAABNQAECgMIBAABAAAAAA==.',
Ro='Robyngdfelow:BAAANQAECgMIAwAAAA==.Rohovart:BAAANQADCgcIDQAAAA==.Rollingrick:BAAANQAECgMIBQAAAA==.',
Rp='Rpro:BAAANQADCgEIAQAAAA==.',
Rr='Rroach:BAAANQAECgMIBAAAAA==.',
Ru='Runaway:BAAANQAECgIIAgAAAA==.Rustycrack:BAAANQAECgEIAQAAAA==.Ruul:BAAANQAECgEIAQAAAA==.',
Ry='Ryilla:BAAANQADCgcIEgAAAA==.Rynoe:BAAANQADCggIDwAAAA==.Ryujinx:BAAANQADCgEIAQAAAA==.',
['Rá']='Ráric:BAAANQADCggIDgAAAA==.',
Sa='Sableman:BAAANQADCgYIDQAAAA==.Saccromycaes:BAAANQADCggIDAAAAA==.Saclem:BAAANQADCgUIBgAAAA==.Saha:BAAANQAECgEIAQAAAA==.Saintayah:BAAANQAECgYIDAAAAA==.Salokin:BAAANQADCgYIBgABNQAFFAIIAgABAAAAAA==.Salorellin:BAAANQAECgcIDgAAAA==.Sandrèena:BAAANQAECgMIBAAAAA==.Sanity:BAAANQAECgEIAQAAAA==.Sarakatawen:BAAANQADCgcIGwAAAA==.Sarumash:BAAANQADCgUIBQAAAA==.Satanah:BAAANQADCgUICQAAAA==.Satomi:BAAANQADCgUICQAAAA==.Satre:BAAANQAECgUIBwAAAA==.',
Se='Seculoe:BAAANQAECgMIAwAAAA==.Seedypete:BAAANQADCgYICwAAAA==.Seemébloody:BAAANQAECgQIAwAAAA==.Seldarine:BAAANQADCgEIAQAAAA==.Selten:BAAANQAECgEIAQAAAA==.Sendel:BAAANQADCgQIBAAAAA==.Senescence:BAABNQAECoEdAAQDAAkJQCOYCwC4AgADAAcJcCKYCwC4AgAEAAUJch/0DwDKAQAFAAEJjyG7EQBOAAAAAA==.Sesshomar:BAAANQADCgEIAQAAAA==.Seventhchild:BAAANQADCgQIBAAAAA==.',
Sh='Sh:BAAANQAECgUICgAAAA==.Shadopaw:BAAANQAECgMIBAAAAA==.Shadyllama:BAAANQAECgMIBAAAAA==.Shamkat:BAAANQADCgcIEAAAAA==.Shammah:BAAANQAECgQIBQAAAA==.Shamuoo:BAAANQADCgQIBAAAAA==.Sharlo:BAAANQADCgQICgAAAA==.Sharnie:BAAANQAECgMIBAAAAA==.Shellatrix:BAAANQAECgUIBwAAAA==.Shepp:BAAANQAECgQIBQAAAA==.Shootette:BAAANQAECgMIBAAAAA==.Shãmtastic:BAAANQADCgYIBgAAAA==.',
Si='Silandryn:BAAANQAECgEIAQAAAA==.Sinderela:BAAANQAECgQICAAAAA==.Sinisterwing:BAAANQAECgUIBgAAAA==.',
Sk='Skeptikk:BAAANQAECgcIDgAAAA==.Skinnery:BAAANQADCgcIDQAAAA==.Skrull:BAAANQAECgQICAAAAA==.',
Sl='Slateray:BAAANQAECgEIAQAAAA==.Slipnslide:BAAANQADCgIIAgAAAA==.',
Sm='Smaque:BAAANQAECgYICwAAAA==.Smegging:BAAANQADCgYICQAAAA==.',
Sn='Snaare:BAAANQADCgYIBgAAAA==.',
So='Solcaris:BAAANQADCgYICAAAAA==.Sorie:BAAANQAECgMIAwAAAA==.Soùlstealer:BAAANQADCgQIBAAAAA==.',
Sp='Sparkdead:BAAANQADCgMIAwAAAA==.Spatspell:BAAANQADCggICQAAAA==.Spazzimitazz:BAAANQADCgIIAgAAAA==.Spazzy:BAAANQAECgQICAAAAA==.Spenna:BAAANQAECgEIAQAAAA==.Spudacus:BAAANQAECgMIBAAAAA==.Spuddk:BAAANQAECgYICQAAAA==.',
St='Stabforcash:BAAANQAFFAQIBAAAAA==.Starleaf:BAAANQADCgQIBgAAAA==.Stellarluse:BAAANQADCggIIAAAAA==.Stickler:BAAANQADCggIFwAAAA==.Stonque:BAAANQADCgcIBwABNQAECgYICwABAAAAAA==.Stormchief:BAAANQADCgMIAwAAAA==.Stormgoat:BAAANQADCgYIBwAAAA==.Stormie:BAAANQADCgcICwAAAA==.Streuth:BAAANQAECgcIDgAAAA==.Strummer:BAABNQAECoEsAAMMAAgJQSSjAwBhAwAMAAgJQSSjAwBhAwANAAIJUxV8LwCHAAAAAA==.Stubbyholder:BAAANQADCggICAAAAA==.',
Su='Subaru:BAAANQADCggIEAAAAA==.Subaruu:BAAANQADCgQIBAABNQADCggIEAABAAAAAA==.Subsiding:BAAANQADCgQIBAAAAA==.Subtera:BAAANQADCgcIBwAAAA==.Supagroova:BAAANQADCgIIAgAAAA==.Supernothing:BAAANQAECgEIAQAAAA==.Superswede:BAAANQADCggIHQAAAA==.',
Sw='Switchdoctor:BAAANQADCggICAABNQADCggICQABAAAAAA==.Sworf:BAAANQAECgYIDQAAAA==.',
Sy='Syaarhunter:BAAANQADCgcIEQAAAA==.Syaarknight:BAAANQADCgYIBwAAAA==.Syaarpally:BAAANQADCgYIDAAAAA==.Syazar:BAAANQADCggIFQAAAA==.Sylanthia:BAAANQAECgMIBAAAAA==.Sylblades:BAAANQADCgIIBAAAAA==.',
['Só']='Sóg:BAAANQAECgEIAgABNQAECgYICQABAAAAAA==.',
['Sø']='Søbz:BAAANQADCggICgAAAA==.Søg:BAAANQAECgYICQAAAA==.',
['Sù']='Sùnjin:BAAANQADCgcIDgABNQAECgQIBAABAAAAAA==.',
Ta='Tabknight:BAAANQAECgYICgAAAA==.Taelron:BAAANQADCgMIBAAAAA==.Taelstard:BAAANQADCgcIGwAAAA==.Taichook:BAAANQAECgEIAQABNQAECgUICgABAAAAAA==.Taithos:BAAANQAECgUICgAAAA==.Talanardonis:BAAANQADCgQIBAAAAA==.Tanktough:BAAANQADCgUICQAAAA==.Tarago:BAAANQAECgMICAAAAA==.Taranisis:BAAANQAECgMIAwAAAA==.Targetone:BAAANQAECgMIAwAAAA==.Tasall:BAAANQADCgYICQAAAA==.Tauntflaunt:BAAANQAECgcICQAAAA==.Tayy:BAAANQADCgEIAQAAAA==.',
Te='Tech:BAAANQAECgMIBAAAAA==.Tenkris:BAAANQADCgcIFQAAAA==.Tenleigh:BAAANQADCgYICAAAAA==.Terroria:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Terrorizor:BAAANQAECgEIAQAAAA==.',
Th='Thalía:BAAANQADCgcIFwAAAA==.Thargroar:BAAANQAECgYICgAAAA==.Thazix:BAAANQADCgMIAwABNQAECgQIBQABAAAAAA==.Thefluffyman:BAAANQAECgQIBwAAAA==.Thiss:BAAANQAECgQIBQAAAA==.Thordak:BAAANQADCggIEQAAAA==.Thoridian:BAAANQADCgQIBwAAAA==.Thurlarra:BAAANQADCgEIAQAAAA==.Thùnder:BAAANQADCgMIAwAAAA==.',
Ti='Titdor:BAAANQADCgIIAgAAAA==.',
To='Tobythemonk:BAAANQAECgYIBgAAAA==.Toehacker:BAAANQAECgQIBgAAAA==.Toliman:BAAANQADCgMIAwAAAA==.Tolkarkiller:BAAANQADCggIFgAAAA==.Tomarr:BAEANQAECgcIDgABNQAECgEIAQABAAAAAA==.Tonsham:BAAANQADCgYIBwAAAA==.Totemspanker:BAAANQADCgcIDQAAAA==.Totoki:BAAANQADCggICAAAAA==.Touchitonce:BAAANQADCgcIDAAAAA==.Toxic:BAAANQADCgIIAgAAAA==.Toóz:BAAANQAECgYICAAAAA==.',
Tr='Trailblayxur:BAAANQAECgEIAQAAAA==.Traser:BAAANQADCgEIAQAAAA==.Trickyknight:BAAANQAECgQICAAAAA==.Trickymage:BAAANQADCgUIBQAAAA==.Trinityheals:BAAANQADCgYIBgAAAA==.',
Tu='Tuckerius:BAAANQADCgYIBwAAAA==.Turahk:BAAANQAECgEIAQAAAA==.Turtlesoup:BAAANQAECgUICAAAAA==.',
Tw='Twofoottall:BAAANQADCgMIAwAAAA==.',
Ty='Tylerolothus:BAAANQAECgEIAQAAAA==.Tynndera:BAAANQADCggIFQAAAA==.Tyrawr:BAAANQAECgQIBAABNQAECgkJGAAOAGMeAA==.Tyth:BAAANQAECgMIBAAAAA==.',
['Tí']='Tím:BAAANQAECgMIBAAAAA==.',
Ud='Udderlyfuzzy:BAAANQAECgIIAwABNQAECgQIBAABAAAAAA==.',
Un='Unclegrandpa:BAAANQADCgQIBgAAAA==.',
Ur='Urôt:BAAANQADCggICAAAAA==.',
Uw='Uwusue:BAAANQAECgYIBwAAAA==.',
Va='Vaeline:BAAANQABCgUIBgAAAA==.Valac:BAABNQAECoEYAAIOAAkJYx5bBwAPAwAOAAkJYx5bBwAPAwAAAA==.Valkyrie:BAAANQAECgQIBAAAAA==.Valothos:BAAANQAECgEIAgAAAA==.Valtiell:BAAANQAECgcIDgAAAA==.Valuri:BAAANQAECgIIAwAAAA==.Varainne:BAAANQAECgUIBgAAAA==.',
Ve='Vegimitê:BAAANQADCgUIBQAAAA==.Vegymite:BAAANQADCgEIAQAAAA==.Velgath:BAAANQAECgcIEgAAAA==.Velkhana:BAAANQAECgQIBgAAAA==.Velmorra:BAAANQAECgIIAgAAAA==.Veratis:BAAANQADCggIFAAAAA==.',
Vi='Victoria:BAAANQAECgIIAgAAAA==.Vinee:BAAANQADCggIIAAAAA==.Vioneva:BAAANQAECgQIBQAAAA==.Viscelock:BAAANQAECgMIAwAAAA==.Vivyregosa:BAABNQAECoEYAAIPAAkJoBryIQDLAgAPAAkJoBryIQDLAgAAAA==.',
Vx='Vxi:BAAANQAFFAMIBAAAAA==.',
Wa='Wagglehoof:BAAANQADCgcIDAAAAA==.Wain:BAAANQADCggIFAAAAA==.Wakantanka:BAAANQADCggIDwAAAA==.Wanglord:BAAANQAECgQIBwAAAA==.Wardõn:BAAANQADCgUIBQAAAA==.Warpig:BAAANQADCgUIBgAAAA==.Warriormilan:BAAANQADCgIIAgAAAA==.Waxedtaco:BAAANQADCgYICAAAAA==.',
Wh='Wheato:BAAANQAECgYICgAAAA==.Whipshot:BAAANQADCggICQAAAA==.Whiteflame:BAAANQAECgQIBAAAAA==.Whiteopal:BAAANQAECgQIBQAAAA==.',
Wi='Willowsun:BAAANQAECgIIAgAAAA==.Winterzap:BAAANQADCggICAAAAA==.Wipe:BAAANQADCggICAABNQAFFAYICwACAK0iAA==.',
Wo='Wolfyhunter:BAAANQADCgYIBgAAAA==.',
Wu='Wulfrick:BAAANQADCgMIBQAAAA==.',
['Wí']='Wítchypoo:BAAANQADCggIEwAAAA==.',
Xa='Xane:BAAANQADCgYIBgAAAA==.Xanetia:BAAANQADCgcIEgAAAA==.Xatir:BAAANQADCgQIBwAAAA==.',
Xi='Xinful:BAAANQABCgQIBAABNQAECgEIAQABAAAAAA==.Xint:BAAANQABCgEIAQAAAA==.',
Xj='Xjaryl:BAAANQADCgcIDgAAAA==.',
Xo='Xoger:BAAANQABCgQIBAAAAA==.',
Ya='Yamasharma:BAAANQADCgUIBgAAAA==.',
Ye='Yeehaww:BAAANQAECgQIBAAAAA==.',
Za='Zaharax:BAAANQAECgEIAQAAAA==.Zaharis:BAAANQAECgUIBgAAAA==.Zanakari:BAAANQADCgYIDQAAAA==.Zasilia:BAAANQADCgUIBQAAAA==.Zass:BAAANQADCgQIBAAAAA==.',
Ze='Zensetrazath:BAAANQAECgQIBQAAAA==.Zerath:BAAANQADCgYIBwAAAA==.',
Zh='Zhanqui:BAAANQAECgEIAQAAAA==.',
Zi='Ziba:BAAANQAECgcIDgAAAA==.Zilithus:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Zipzamzoom:BAAANQADCggIAgABNQADCggICQABAAAAAA==.',
Zo='Zoroo:BAAANQAECgIIBAAAAA==.',
Zr='Zross:BAAANQADCgcIDQAAAA==.',
Zu='Zudo:BAAANQAECgMIBQAAAA==.Zuthrais:BAABNQAECoEsAAICAAgJEQ5pIgD/AQACAAgJEQ5pIgD/AQAAAA==.Zuulik:BAAANQADCgYIDgAAAA==.',
Zz='Zz:BAACNQAFFIEIAAIQAAUJlBMgAADxAQAQAAUJlBMgAADxAQA1AAQKgRgAAhAACQkWJT8AAOADABAACQkWJT8AAOADAAAA.',
['Án']='Ángelpie:BAAANQADCgYICwAAAA==.',
['Är']='Ärrôw:BAAANQADCgYIAgAAAA==.',
['Ås']='Åshka:BAAANQABCgIIAgAAAA==.',
['Él']='Élryk:BAAANQABCgUICAAAAA==.',
['ßa']='ßankai:BAAANQADCgQIBAABNQADCggIDAABAAAAAA==.',
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
