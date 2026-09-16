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

local lookup = {'Priest-Shadow','Priest-Holy','Druid-Balance','Unknown-Unknown','Warrior-Arms','DeathKnight-Unholy','DeathKnight-Blood','Warlock-Demonology','Warlock-Destruction','Rogue-Assassination','Rogue-Outlaw','Rogue-Subtlety','Shaman-Elemental','Shaman-Restoration','Monk-Windwalker','Monk-Brewmaster','Mage-Arcane','DemonHunter-Havoc','Hunter-BeastMastery','Druid-Feral','Evoker-Augmentation','Paladin-Retribution','Paladin-Holy','Evoker-Preservation',}
local provider = {region='US',realm='Cenarius',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aalen:BAABNQAECoEaAAMBAAgJqQ9BFAAeAgABAAgJqQ9BFAAeAgACAAQJlwi2cACpAAAAAA==.',
Ab='Aby:BAAANQAECgEIAgAAAA==.',
Ac='Achooah:BAABNQAECoEeAAIDAAgJICOYDAAaAwADAAgJICOYDAAaAwAAAA==.Acturus:BAAANQADCggIHQAAAA==.',
Ad='Adekeh:BAAANQADCgYIBgAAAA==.',
Ae='Aela:BAAANQAECgYIDAAAAA==.Aenie:BAAANQADCggIEgAAAA==.Aerose:BAAANQAECgMIAwAAAA==.Aethelia:BAAANQADCggIDgAAAA==.',
Ak='Aki:BAAANQAECgMIAwAAAA==.Akie:BAAANQADCggIDgABNQAECgMIAwAEAAAAAA==.',
Al='Aladrelis:BAAANQADCggICAABNQAECgIIAwAEAAAAAA==.Alarana:BAAANQADCgYIBgAAAA==.Allizana:BAAANQAECgQIAwABNQAFFAEIAQAEAAAAAA==.Alumeena:BAAANQADCggIDQAAAA==.',
Am='Amelei:BAAANQAECgcIDgAAAA==.Amorlordros:BAAANQADCgYIBAAAAA==.Amylynn:BAAANQAECgEIAQAAAA==.Amyquivers:BAAANQADCggIGQAAAA==.',
An='Andarieal:BAAANQAECgQIBgAAAA==.Androlas:BAAANQADCgQIBAAAAA==.Angeldown:BAAANQADCgQIBAAAAA==.Ankhling:BAAANQAECgYIDgAAAA==.Annahlia:BAAANQADCgQIBAAAAA==.Annoying:BAAANQAECgEIAQAAAA==.Anyafire:BAAANQADCgUICgAAAA==.',
Ap='Appian:BAAANQADCgYIGQAAAA==.',
Ar='Aralye:BAAANQAECgEIAQAAAA==.Armsop:BAAANQADCgUICgAAAA==.Armîda:BAAANQAECgQIBgAAAA==.Arnika:BAAANQAECgUICAAAAA==.Arvalyn:BAAANQAECgQIBwAAAA==.',
As='Ashlien:BAAANQADCgQIBAAAAA==.Astralvoid:BAAANQAECgUICQAAAA==.Asuya:BAAANQADCgYICgAAAA==.',
At='Atalune:BAAANQADCgYIBgAAAA==.Athaesia:BAAANQADCgIIAgAAAA==.',
Au='Aus:BAAANQADCggIEAABNQAECgYIDwAEAAAAAA==.',
Av='Avakai:BAAANQADCgQIBQAAAA==.Avawar:BAAANQABCgIIAgAAAA==.',
Ax='Axazon:BAAANQAECgYIDwAAAA==.Axellered:BAAANQADCgQIBQAAAA==.',
Az='Azark:BAAANQAECgEIAQAAAA==.Azzerria:BAAANQAECgEIAQAAAA==.',
Ba='Bartholoméw:BAAANQAECgcIDgAAAA==.Bascus:BAAANQAECgMIAwAAAA==.Bassuu:BAAANQAECgQIBAAAAA==.',
Be='Beefdaddy:BAAANQAECgYICAAAAA==.Beendayho:BAAANQADCgMIAwAAAA==.Beerrun:BAAANQADCgYIBwAAAA==.Belfør:BAAANQAECgMIBQAAAA==.Bellius:BAAANQAECgUICAAAAA==.Bennissia:BAAANQADCgYICwAAAA==.Betula:BAAANQADCgQICgAAAA==.',
Bi='Bigolbert:BAAANQADCgQICAAAAA==.Bipolaire:BAAANQADCgMIAwAAAA==.',
Bj='Björk:BAAANQADCgYIBgAAAA==.',
Bl='Blaids:BAAANQABCgEIAQAAAA==.Blaixava:BAAANQADCgYIBgAAAA==.Blazefury:BAAANQAECgUICQAAAA==.Blueyez:BAAANQADCgcICgAAAA==.',
Bo='Bobsalami:BAAANQADCgMICQAAAA==.Bophedese:BAAANQADCgEIAQAAAA==.Boragarsh:BAAANQAECgQIBAAAAA==.Bowlyne:BAAANQAECgUIDwAAAA==.Boyz:BAAANQADCggIDgAAAA==.',
Br='Brannflake:BAAANQADCgYIDQABNQAECgYIDAAEAAAAAA==.Brewkong:BAEANQAECgIIBAAAAA==.Bruhsabi:BAAANQADCggIDAAAAA==.Brumsta:BAAANQAECggIEAAAAA==.Brutalious:BAAANQADCggIEgAAAA==.Bruutii:BAABNQAECoEZAAIFAAgJnBagNwBaAgAFAAgJnBagNwBaAgAAAA==.',
Bu='Bubbleandrun:BAAANQAECgQIBgAAAA==.Buckaroo:BAAANQAECgQIBAABNQAECgUIBQAEAAAAAA==.Buckcherry:BAAANQAECgUIBQAAAA==.Bulvaan:BAAANQAECgMIBgAAAA==.',
['Bì']='Bìtterbabe:BAAANQADCggIDgAAAA==.',
Ca='Caell:BAAANQAECgIIAgAAAA==.Calair:BAAANQADCgIIAgAAAQ==.Calandia:BAAANQAECgIIAgAAAA==.Cannoneer:BAAANQAECgQIBAABNQAECggIGgAGAAYdAA==.Cannonia:BAABNQAECoEaAAMGAAgJBh1AEQDLAgAGAAgJBh1AEQDLAgAHAAEJvBjpewBDAAAAAA==.Cantdance:BAAANQADCgQICAAAAA==.Cantora:BAAANQAECgEIAQAAAA==.Carlyy:BAAANQADCgUIBQABNQAECgMIBgAEAAAAAA==.Castolo:BAAANQABCgYICQAAAA==.Catrunner:BAAANQADCgMIAwAAAA==.Cayvie:BAAANQAECgIIAgAAAA==.',
Ce='Cedroes:BAAANQAECgUIDgAAAA==.Celandine:BAAANQADCggIHQAAAA==.Cerenus:BAAANQAECgQIBAAAAA==.',
Ch='Chaoswolf:BAAANQADCggIEgAAAA==.Cheapthrills:BAAANQADCggIDgAAAA==.Chickfilafry:BAAANQAECgMIAwAAAA==.Chickfilagal:BAAANQADCgUIBQAAAA==.Chipadip:BAABNQAECoEaAAIGAAgJWBy6FQCcAgAGAAgJWBy6FQCcAgAAAA==.Chiqasaurus:BAAANQAECgEIAQAAAA==.',
Ci='Cindoria:BAAANQAECgMIAwAAAA==.Cinzia:BAAANQADCggICAAAAA==.',
Cl='Clockblocked:BAAANQAECgUICgAAAA==.Clolarion:BAAANQADCggIEwAAAA==.',
Co='Coltyn:BAAANQAECgQIBgAAAA==.Contrakt:BAAANQAECgUICQAAAA==.',
Cr='Crackiechan:BAAANQAECgMIAwAAAA==.Crashcash:BAAANQADCgQIBgAAAA==.Croatan:BAAANQADCgIIAgAAAA==.',
Cu='Curiel:BAAANQAECgEIAQAAAA==.Cutters:BAAANQADCgUIBwAAAA==.',
Cv='Cviper:BAABNQAECoEZAAMIAAgJ1yMaBgBKAwAIAAgJ1yMaBgBKAwAJAAEJNh5GVgBCAAAAAA==.',
Cy='Cyanos:BAAANQADCgYICwAAAA==.Cymbre:BAAANQADCggIDgAAAA==.',
Da='Dad:BAAANQAECgEIAQAAAA==.Dae:BAAANQAECgUICQAAAA==.Dallinarr:BAAANQADCgUIBQAAAA==.Daridru:BAAANQADCgYIBgAAAA==.Darifire:BAAANQADCgQIBAAAAA==.Darkhrt:BAAANQAECgEIAgAAAA==.Darkson:BAAANQADCgYIBgAAAA==.Dawnweaver:BAAANQADCgUIBQAAAA==.Dazedxar:BAAANQAECgMIBAAAAA==.',
De='Deadtotem:BAAANQAECgYIBwAAAA==.Deathdeath:BAAANQAECgMIBQABNQAECgUIBgAEAAAAAA==.Deathwavez:BAAANQAECgYICwAAAA==.Degaen:BAAANQADCgEIAQAAAA==.Delirium:BAAANQADCggIGgAAAA==.Dennis:BAABNQAECoEaAAIKAAgJsCSMAwBGAwAKAAgJsCSMAwBGAwAAAA==.Deosil:BAAANQADCggICAAAAA==.Departéd:BAECNQAFFIEHAAILAAUJIRQ1AADAAQALAAUJIRQ1AADAAQA1AAQKgSwAAwsACQkyI1sAAMQDAAsACQkyI1sAAMQDAAoAAQkeHmNDAE8AAAAA.Deplete:BAAANQADCgIIAgABNQAECgIIAgAEAAAAAA==.Derasia:BAAANQADCgMIAwAAAA==.Deyvia:BAAANQADCgEIAQAAAA==.',
Di='Dianasia:BAAANQADCgUIBQAAAA==.Dinothunder:BAAANQAECggIDQAAAA==.Dippindots:BAAANQAECgQIBAABNQAECgYIDAAEAAAAAA==.Dirf:BAAANQADCggIEgAAAA==.Dirtytree:BAAANQADCgYIBgAAAA==.Disc:BAAANQADCgYIBgAAAA==.Discobear:BAAANQAFFAMIBAAAAA==.',
Dk='Dkartha:BAAANQADCggICAAAAA==.',
Do='Docent:BAAANQADCgEIAQAAAA==.Doomui:BAAANQAECgEIAgAAAA==.Dorflundgren:BAAANQAECggIBwAAAA==.Doruh:BAAANQAECgYIBwAAAA==.Dotdragon:BAAANQADCgEIAQAAAA==.',
Dr='Draegon:BAAANQADCgUIBgABNQADCggIHQAEAAAAAA==.Draemonk:BAAANQADCgYICAABNQADCggIHQAEAAAAAA==.Draenorious:BAAANQADCggIHQAAAA==.Dragonix:BAAANQAECgQIBAAAAA==.Drakonetta:BAAANQADCgUICQAAAA==.',
Ds='Dseed:BAAANQADCgMIAwAAAA==.',
Du='Dudris:BAAANQAECgEIAQABNQAECgEIAQAEAAAAAA==.Dumbasmus:BAAANQAECgQIBQAAAA==.',
['Dä']='Däkk:BAAANQADCggICAAAAA==.',
['Dé']='Déathgoddess:BAAANQADCggIGwAAAA==.',
Ea='Eavie:BAAANQAECgEIAQAAAA==.',
Ed='Ediah:BAAANQADCggIGQAAAA==.Edibleundies:BAAANQADCgMIBQABNQADCgQIBAAEAAAAAA==.',
Ee='Eeveé:BAAANQAECgMIAwAAAA==.',
El='Electronaut:BAEANQADCggIDQAAAA==.Elestrae:BAAANQADCgUIBQAAAA==.Eljefe:BAAANQADCgQIBgAAAA==.Elleria:BAAANQADCgUIBgAAAA==.Ellobb:BAAANQADCgUIBQAAAA==.',
Em='Emeraldstar:BAAANQADCggICgAAAA==.',
En='Envelion:BAAANQAECgUICQAAAA==.',
Er='Erand:BAAANQAECgQICAAAAA==.',
Es='Esvanka:BAAANQAECgcIDwAAAA==.',
Et='Ethuul:BAAANQABCgIIAgAAAA==.',
Eu='Euterpe:BAAANQAECgIIAwAAAA==.',
Ex='Exfeld:BAAANQABCgEIAQAAAA==.Exoddus:BAAANQADCggIGgAAAA==.',
Fa='Fae:BAAANQADCgYIBgAAAA==.Faein:BAAANQAECgEIAQAAAA==.Faelynatlyf:BAAANQAECgYICwAAAA==.Falamoto:BAAANQAECgEIAQAAAA==.Fallen:BAAANQAECgUIBQAAAA==.Faltraz:BAAANQADCggICAAAAA==.Fangskin:BAAANQAECgIIBQAAAA==.',
Fe='Feltoast:BAAANQADCgEIAQABNQADCggIFAAEAAAAAA==.Feyn:BAAANQAECgQICAAAAA==.',
Fh='Fhaeos:BAAANQADCgQIBgAAAA==.',
Fi='Fiode:BAAANQAECgUICAAAAA==.',
Fj='Fjall:BAAANQAECgIIAwAAAA==.',
Fl='Flipsmage:BAAANQADCgcIBwAAAA==.',
Fo='Foomanpan:BAAANQADCggICAAAAA==.',
Fr='Fresh:BAAANQADCgcIDQAAAA==.Frieren:BAAANQAECgMIBAAAAA==.Frostea:BAAANQAECgUICAAAAA==.Fruitloops:BAAANQADCgYICgABNQAECgYIDAAEAAAAAA==.',
Fu='Furrowcious:BAAANQABCgEIAQAAAA==.Fuzybear:BAAANQADCgYIBwABNQADCgcIDQAEAAAAAA==.',
Fy='Fyo:BAABNQAECoEaAAIMAAgJ0yK0AwA7AwAMAAgJ0yK0AwA7AwAAAA==.Fyorin:BAAANQAECgQIBQAAAA==.',
['Fä']='Fäyëth:BAAANQAECgQIBAABNQAECgQIBAAEAAAAAA==.',
Ga='Gamerkun:BAAANQAECgQICAAAAA==.Gankz:BAAANQAECgQIBwAAAA==.Gardios:BAAANQADCgUIBQAAAA==.Gargon:BAAANQAECgQIBAAAAA==.Gatchagooner:BAAANQAECgMIBwAAAA==.Gautham:BAAANQADCgIIAgAAAA==.',
Gh='Ghettofab:BAAANQAECgIIAgAAAA==.',
Gi='Gihum:BAAANQADCgMICQAAAA==.Ginjjow:BAAANQADCgUIBQAAAA==.Girthquakè:BAAANQAECgQIBgAAAA==.',
Gj='Gjoflash:BAAANQABCgIIAgAAAA==.Gjolock:BAAANQABCgIIAgAAAA==.',
Gl='Glaizer:BAAANQADCggICAAAAA==.Glaurung:BAAANQADCgUICgAAAA==.Glorfindel:BAAANQADCgQIBAAAAA==.Glue:BAABNQAECoEZAAINAAgJwB0xFwC9AgANAAgJwB0xFwC9AgAAAA==.',
Gn='Gnomestomper:BAAANQAECgUICQAAAA==.',
Go='Goldenlotus:BAABNQAECoEaAAMOAAgJgR+PEwC8AgAOAAgJgR+PEwC8AgANAAIJpQxhmQB3AAAAAA==.Golder:BAAANQAECgcIEwAAAA==.Goldlight:BAAANQADCgcIFgAAAA==.Goodshammy:BAAANQADCggIEAAAAA==.Goodwllhntng:BAAANQADCggICAAAAA==.Goreyok:BAAANQADCgQIBAAAAA==.Gorgoneion:BAEANQAECgQICAABNQAECggIGQAFAGkcAA==.Gortess:BAEBNQAECoEZAAIFAAgJaRzaJAC6AgAFAAgJaRzaJAC6AgAAAA==.',
Gr='Graatch:BAAANQADCgYICwAAAA==.Grandaddy:BAAANQAECgEIAQAAAA==.Greentotems:BAAANQAECgIIAgAAAA==.Greyferret:BAAANQADCgIIAgAAAA==.Grifin:BAAANQADCgIIAgAAAA==.Grimåldus:BAAANQABCgMIAwAAAA==.Gryfalia:BAAANQAECgMIBAAAAA==.',
Gu='Guinevera:BAAANQADCgMICQAAAA==.Gulo:BAAANQABCgIIAgABNQAECggJFwAPAJIjAA==.',
['Gó']='Góat:BAAANQAECgcIEgAAAA==.',
Ha='Haahoo:BAAANQADCggICAAAAA==.Haart:BAAANQABCgcICQAAAA==.Haavok:BAAANQAECgcIDgAAAQ==.Hadoken:BAAANQAECgUIBwAAAA==.Haist:BAAANQAECgQIBAAAAA==.Halenia:BAAANQADCgYIDAAAAA==.Halftoon:BAAANQADCgEIAQAAAA==.Halyte:BAAANQAECgEIAQAAAA==.Hamoonraza:BAAANQAECgIIAwAAAA==.Handwelor:BAAANQADCgUICAAAAA==.Haneel:BAAANQADCgUICAAAAA==.Hanske:BAAANQADCggIGQAAAA==.Happyfeet:BAAANQAECgQIBQAAAA==.Harak:BAAANQAECgEIAQAAAA==.Harath:BAAANQADCgEIAQAAAA==.Harf:BAAANQADCgcIFQAAAA==.Hatestar:BAAANQAECgEIAgAAAA==.Hauthen:BAAANQAECgQIBgAAAA==.Havoc:BAAANQAECgQIBgAAAA==.',
He='Heliokine:BAAANQADCggIDgAAAA==.Heys:BAAANQADCgEIAQAAAA==.',
Hi='Himi:BAAANQAECgcIEwAAAA==.Hindenburg:BAAANQADCgcIFAAAAA==.',
Ho='Hobemian:BAAANQADCgcIDQAAAA==.Holyfíre:BAAANQADCgUIBQAAAA==.Holynenaea:BAAANQAECgYICQAAAA==.Holypally:BAAANQAECgIIAgAAAA==.Holyram:BAAANQADCggIFgAAAA==.Hoodsman:BAAANQAECgYIEAAAAA==.Horvon:BAAANQAECgUIBAAAAA==.Hound:BAABNQAECoEXAAMPAAgJkiMlBQAwAwAPAAgJkiMlBQAwAwAQAAEJjB0mHABDAAABNQAECggJFwAPAJIjAA==.',
Hu='Hushh:BAAANQADCgYICAAAAA==.',
Hy='Hyos:BAAANQAECgQIBAABNQAECggIGgABAKkPAA==.',
['Há']='Háze:BAAANQAECgQIBAAAAA==.',
['Hâ']='Hâldor:BAAANQAECgEIAQAAAA==.',
Ia='Ianna:BAAANQAECgEIAQABNQAECgIIAgAEAAAAAA==.',
Ib='Ibop:BAAANQADCggICAABNQAECgQIBAAEAAAAAA==.',
Ic='Icewall:BAAANQADCgQIBAAAAA==.',
Ih='Ihzfrsfld:BAAANQAECgMIAwAAAA==.',
Ik='Ikassei:BAAANQADCgcIBwAAAA==.',
Il='Ilexia:BAAANQAECgIIAgAAAA==.Illavoida:BAAANQABCgUIBQAAAA==.Illidansboss:BAAANQAECgQIBwAAAA==.Illidiet:BAAANQADCgcICwAAAA==.',
In='Infierna:BAAANQAECgQIDAAAAA==.',
Ir='Ironfistxrio:BAAANQADCggIHQAAAA==.Ironscale:BAAANQAECgEIAQAAAA==.',
Is='Isath:BAAANQAECgEIAgAAAA==.',
Iw='Iwillblessú:BAAANQADCggICAAAAA==.Iwillpeeonu:BAAANQAECgUIDgAAAA==.',
Ix='Ixix:BAAANQAECgUICQAAAA==.',
Ja='Jackysan:BAAANQADCgQIBAABNQAECgQICAAEAAAAAA==.Jalani:BAAANQAECgUIBgAAAA==.Jaq:BAAANQADCgYIBgABNQAECggJFwAPAJIjAA==.Jatee:BAAANQADCgYIBgAAAA==.Java:BAAANQAECgIIAgAAAA==.',
Jd='Jdsc:BAAANQADCgMIAwAAAA==.',
Je='Jeffrotull:BAAANQAECgQIBQAAAA==.Jentoo:BAAANQAECgUIBgAAAA==.Jerg:BAAANQAECgUIBgAAAA==.Jerode:BAAANQAECgEIAQAAAA==.Jetpackcat:BAAANQAECgcIEAAAAA==.Jexzyn:BAAANQADCggIEQAAAA==.',
Ji='Jizza:BAAANQAECgEIAQAAAA==.',
Jo='Joe:BAAANQADCgYIBgABNQAECgcICAAEAAAAAA==.Joepiden:BAAANQAECgUIDQABNQAECgYIDAAEAAAAAA==.Jond:BAAANQAECgcIEwAAAA==.',
Jr='Jrôxs:BAAANQAECgUIBQAAAA==.',
Ju='Jubilee:BAAANQAECgUIBwAAAA==.Jubnon:BAAANQAECgIIAwAAAA==.',
Ka='Kadeth:BAAANQADCggIGgAAAA==.Kagekitsoon:BAAANQADCgMIAwABNQADCgMIBgAEAAAAAA==.Kahawse:BAAANQADCggICAAAAA==.Kamer:BAAANQAECgQICAAAAA==.Kamm:BAAANQADCgQIBAAAAA==.Kanekii:BAAANQADCgMIAwAAAA==.Kaptalon:BAAANQAECgQIDgAAAA==.Katarina:BAABNQAECoEaAAIMAAgJjgwDEgARAgAMAAgJjgwDEgARAgAAAA==.Kathu:BAAANQAECgEIAwAAAA==.Kawaii:BAAANQAECgIIBAAAAA==.Kazanot:BAAANQADCgYICQABNQAECgEIAQAEAAAAAA==.Kazenazza:BAAANQADCgcIEwAAAA==.',
Ke='Kelarie:BAAANQADCgIIAgAAAA==.Keltaryn:BAAANQAECgUIBQAAAA==.Kephzax:BAABNQAECoEXAAIRAAgJIAYNigCxAQARAAgJIAYNigCxAQAAAA==.Kerapac:BAABNQAECoEZAAIHAAgJ8wwKMACmAQAHAAgJ8wwKMACmAQAAAA==.Kezinik:BAACNQAFFIEJAAMHAAUJAg0kBQA6AQAHAAUJAg0kBQA6AQAGAAEJTAAgDgApAAA1AAQKgRsAAgcACQmrH04JACMDAAcACQmrH04JACMDAAAA.Kezursine:BAAANQAECgMIAwAAAA==.',
Ki='Kireek:BAAANQAECgYIDgAAAA==.Kitas:BAAANQADCgcIDQAAAA==.Kizuna:BAAANQADCgEIAQAAAA==.',
Kl='Klegain:BAAANQADCggIDQAAAA==.',
Kn='Knockknocks:BAAANQADCgYICgAAAA==.',
Ko='Koujii:BAABNQAECoEZAAISAAgJfht3DgClAgASAAgJfht3DgClAgAAAA==.',
Kr='Kristyana:BAAANQAECgEIAQABNQAECgIIAwAEAAAAAA==.',
Ks='Ksenja:BAAANQAECgEIAQAAAA==.',
Ku='Kuum:BAAANQADCgcIBwAAAA==.',
Kw='Kwaichngcain:BAAANQADCgMIAwAAAA==.',
Ky='Kyfujú:BAAANQADCgEIAQAAAA==.Kylgard:BAAANQADCgUIBAAAAA==.Kyliara:BAAANQABCgQIBwAAAA==.Kylire:BAAANQABCgQIBAAAAA==.Kylisar:BAAANQABCgUIBgAAAA==.Kylithra:BAAANQABCgMIBQAAAA==.Kylmara:BAAANQADCgQIBgAAAA==.Kylneldth:BAAANQABCgQIBQAAAA==.Kylorend:BAAANQAECgYIDAAAAA==.Kylral:BAAANQABCgQIBAAAAA==.Kylsoonmar:BAAANQABCgQIBgAAAA==.Kysindra:BAAANQAECgcIDgAAAA==.Kyutir:BAAANQADCggIDgAAAA==.Kyuu:BAAANQAECgEIAQAAAA==.Kyygo:BAAANQAECgUICQAAAA==.',
['Ká']='Kámm:BAAANQAECgQIBwAAAA==.',
['Kè']='Kètåsét:BAAANQADCgQICwAAAA==.',
La='Lacedunlaced:BAAANQADCggICAABNQAECgcIDAAEAAAAAA==.Ladyneasa:BAAANQAECgUICAAAAA==.Lainn:BAAANQADCgMIAgAAAA==.Lambofgoad:BAAANQAECgYIBgAAAA==.Lamennais:BAAANQADCggIGgAAAA==.Lapsene:BAAANQADCggIEgAAAA==.Lasagna:BAAANQADCgYIDgABNQAECgYIDAAEAAAAAA==.Lavendae:BAAANQAECgEIAgAAAA==.Laxus:BAABNQAECoEaAAITAAgJah+6EQDpAgATAAgJah+6EQDpAgAAAA==.',
Le='Leahpali:BAAANQADCgIIAgAAAA==.Lebronflames:BAAANQADCgYICAABNQAECgYIDAAEAAAAAA==.Lesath:BAAANQAECgYICwAAAA==.Lesca:BAAANQADCgYIBgABNQAECggIGgAGAFgcAA==.Leshalles:BAAANQAECgYIDQAAAA==.Leviathayne:BAAANQADCgEIAgAAAA==.',
Li='Liazel:BAABNQAECoEYAAITAAgJgCHmDQAMAwATAAgJgCHmDQAMAwAAAA==.Lilrage:BAAANQADCgUIBQAAAA==.Lilsquishy:BAAANQADCgYIEQAAAA==.Limen:BAAANQAECgEIAQAAAA==.Lissael:BAAANQADCggIDgAAAA==.',
Lo='Loaruun:BAAANQAECgYIDQAAAA==.Loopi:BAAANQAECgMIAwAAAA==.',
Lu='Lunatick:BAABNQAECoEZAAIUAAgJRRiABACDAgAUAAgJRRiABACDAgAAAA==.',
Ly='Lyriele:BAAANQADCgYIBgAAAA==.',
['Læ']='Læris:BAEANQAECgEIAQABNQAECggIGQAFAGkcAA==.',
['Lü']='Lünar:BAAANQADCgUICAAAAA==.',
Ma='Madridm:BAAANQADCggICAAAAA==.Maegumi:BAAANQAECgQIBAAAAA==.Maeliá:BAAANQABCgIIAgAAAA==.Magdalin:BAAANQADCgYICwABNQAECgUIBwAEAAAAAA==.Magdalyne:BAAANQAECgUIBwAAAA==.Magedudee:BAABNQAECoEZAAIRAAgJICHiJwDyAgARAAgJICHiJwDyAgAAAA==.Magespec:BAAANQAECgEIAgAAAA==.Maghom:BAAANQADCgcIEgAAAA==.Magicdrae:BAAANQABCgIIAgABNQADCggIHQAEAAAAAA==.Malestrom:BAAANQADCggIHQAAAA==.Malfei:BAAANQADCggIEgAAAA==.Manalenna:BAAANQADCgYIBgABNQAECgIIAwAEAAAAAA==.Manate:BAAANQAECgcIEwAAAA==.Manawavez:BAAANQADCgYIBgAAAA==.Mancakesyrup:BAAANQAECgUICQAAAA==.Mandori:BAAANQAECgMIBQAAAA==.Manusbane:BAAANQADCggICQAAAA==.Marceh:BAAANQADCgcIGgAAAA==.Marineoracle:BAEANQAECgUIBQAAAA==.Marter:BAAANQADCgMIBAAAAA==.Martypriest:BAAANQAECgYIEAAAAA==.Mashal:BAAANQAECgMIAwAAAA==.Mavraan:BAAANQADCgMIAwAAAA==.Mayse:BAAANQADCggIHQAAAA==.',
Me='Me:BAAANQAECgQICQAAAA==.Meatsac:BAAANQAECgcIDwAAAA==.Mellennah:BAAANQAECgUICQAAAA==.',
Mi='Micromenace:BAAANQADCgQIBAAAAA==.Mikdra:BAAANQADCgUIBQAAAA==.Milkshake:BAAANQABCgIIAgABNQADCggIDwAEAAAAAA==.Missanthropy:BAAANQADCgQIBAAAAA==.Misspelling:BAAANQADCgcIBwAAAA==.',
Mo='Mohpnya:BAAANQADCgYIBwAAAA==.Mongsok:BAABNQAECoEZAAIPAAgJISGRCADWAgAPAAgJISGRCADWAgAAAA==.Monkmonkmonk:BAAANQAECgMIAwABNQAECgUIBgAEAAAAAA==.Moonshíne:BAAANQAECgIIAwAAAA==.Moy:BAAANQAECgUIDAAAAA==.Moÿ:BAAANQAECgYIBQAAAA==.',
Mu='Mumple:BAAANQAECgQIBgAAAA==.Murlok:BAAANQAECgIIAgAAAA==.Mustashe:BAAANQADCgUIBQABNQAECgYIDAAEAAAAAA==.',
My='Mynöghra:BAAANQADCgcIDQABNQADCggIEgAEAAAAAA==.Myshak:BAAANQAECgEIAgAAAA==.Mysticsoul:BAABNQAECoEaAAIOAAgJ5xpaHQBvAgAOAAgJ5xpaHQBvAgAAAA==.',
['Mè']='Mègàmägë:BAAANQAECgEIAQAAAA==.',
['Mó']='Mórrigan:BAAANQADCgIIAgAAAA==.',
Na='Nadizel:BAAANQADCgcIFwAAAA==.Naglfer:BAAANQADCgEIAQAAAA==.Narisse:BAAANQADCgQIBAAAAA==.Narzud:BAAANQADCgQIBAAAAA==.Nasa:BAAANQADCgYIBgAAAA==.Nazmyr:BAAANQAECgQICQAAAA==.',
Ne='Necrofeelyea:BAAANQADCgYICAAAAA==.Neotron:BAAANQADCgYIDAAAAA==.',
Ni='Nickelbritt:BAAANQAECgUIBgAAAA==.Niish:BAAANQAECgIIAgAAAA==.',
No='Noani:BAAANQAECgYIDQAAAA==.Notsu:BAAANQADCgcICgAAAA==.Novidius:BAAANQAECgQIBAAAAA==.',
Nu='Numkins:BAAANQAECgQIBAAAAA==.',
['Ní']='Níghts:BAAANQAECgQIBgAAAA==.',
Oe='Oephelia:BAAANQAECgMIBQAAAA==.',
Oj='Ojaru:BAAANQAECgMIBAAAAA==.',
Ol='Olliver:BAAANQADCgMIBgAAAA==.Oloo:BAAANQAECgQIBAAAAA==.',
On='Onlyhams:BAABNQAECoEaAAICAAgJUhIwKgAKAgACAAgJUhIwKgAKAgAAAA==.',
Or='Oras:BAAANQADCggIGQAAAA==.Orayleina:BAAANQADCgYIEgAAAA==.',
Ot='Othelli:BAAANQADCgUIBQAAAA==.',
Pa='Packafist:BAAANQAECgQIBQABNQAECgYIBwAEAAAAAA==.Palm:BAAANQADCgIIAgAAAA==.Palpalpal:BAAANQAECgMIBAABNQAECgUIBgAEAAAAAA==.Paulywag:BAAANQADCgYIEgAAAA==.Paulywog:BAAANQADCgUIBQAAAA==.Pawsed:BAAANQAECgQIBQAAAA==.',
Pe='Perleana:BAAANQAECgUICQAAAA==.Perra:BAAANQAECgYICwAAAA==.Petergriffon:BAAANQADCggIFAAAAA==.',
Ph='Philmikehawk:BAABNQAECoEaAAIFAAgJXSRmDwBMAwAFAAgJXSRmDwBMAwAAAA==.',
Pi='Picklestack:BAAANQAECgQIBAAAAA==.Pikatin:BAAANQADCggICAAAAA==.',
Pl='Platemage:BAAANQAECgcIDAAAAA==.',
Ps='Psyk:BAAANQAECgYICwAAAA==.',
Pu='Puding:BAAANQAECgUICAAAAA==.',
Pw='Pwnykeg:BAAANQADCggIGgAAAA==.',
Py='Pyixi:BAAANQADCgUIDQAAAA==.',
['Pà']='Pàulywog:BAAANQAECgQIBgAAAA==.',
['Pá']='Páppajohn:BAAANQAECgIIAgAAAA==.',
Qb='Qb:BAABNQAECoEXAAIVAAgJnxacAwBHAgAVAAgJnxacAwBHAgAAAA==.',
Qu='Quelenna:BAAANQADCggIGgAAAA==.Questorwar:BAAANQADCgcIDAAAAA==.Quintus:BAAANQADCggIEgAAAA==.',
Ra='Ragmer:BAAANQAECgQIBAAAAA==.Ragnariuss:BAAANQAECgQIBAAAAA==.Raira:BAAANQAECgEIAQAAAA==.Ravenfeld:BAAANQAECgIIAgAAAA==.Raviolli:BAAANQABCgYIBgAAAA==.',
Re='Rebelangel:BAAANQADCgQIBAAAAA==.Redbeauty:BAAANQADCgUICgAAAA==.Redvail:BAAANQADCgYIFQAAAA==.Refuting:BAAANQAECgMIAwABNQAECgMIBQAEAAAAAA==.Reivida:BAAANQAECgEIAwAAAA==.Remyxz:BAAANQAECgUIBQAAAA==.Renlaut:BAAANQAECgIIAgAAAA==.Reported:BAAANQADCgQIBAABNQAECgcIGgAGAOYTAA==.Reprisal:BAABNQAECoEaAAIGAAcJ5hPFKgDlAQAGAAcJ5hPFKgDlAQAAAA==.',
Rh='Rhapsady:BAAANQADCgYIBgAAAA==.',
Ri='Riffraff:BAAANQADCggIHQAAAA==.Rioz:BAAANQADCgUIBQAAAA==.Ripbozo:BAAANQAECgUICwAAAA==.Ritsnimle:BAAANQAECgEIAQAAAA==.',
Ro='Rocknocker:BAAANQAECgYIDwAAAA==.Rokkmar:BAAANQADCgIIAwAAAA==.Rookie:BAABNQAECoEZAAIMAAgJehZaCwB+AgAMAAgJehZaCwB+AgAAAA==.Rowsi:BAAANQADCggICAAAAA==.Roxene:BAAANQADCggIGwAAAA==.',
Ru='Rukaza:BAAANQAECgcIEgAAAA==.',
['Rè']='Rènara:BAAANQADCgMIAwAAAA==.',
Sa='Saelyraria:BAAANQAECgEIAQAAAA==.Safijiva:BAAANQAECgQICQAAAA==.Saintrawrs:BAAANQADCgQIBQAAAA==.Saiti:BAABNQAECoEZAAIGAAgJWxggGwBnAgAGAAgJWxggGwBnAgAAAA==.Sanleras:BAAANQAECgQIBAAAAA==.Sanovia:BAAANQADCgYIEQAAAA==.Sanrao:BAAANQADCgUIBQAAAA==.Sarao:BAAANQAECgQICAAAAA==.',
Sc='Schutzengel:BAAANQADCgcIBwAAAA==.Scoondk:BAAANQAECgEIAQAAAA==.Scuttlebug:BAAANQAECgYIBgAAAA==.Scynthyace:BAABNQAECoEZAAICAAgJGSRGBwAyAwACAAgJGSRGBwAyAwAAAA==.',
Se='Selystina:BAAANQADCgYIBgAAAA==.Sensistar:BAAANQAECgQICAAAAA==.Sephen:BAAANQAECgIIAgAAAA==.Septemberr:BAAANQADCgYICwAAAA==.Sermac:BAAANQADCgYIEQAAAA==.',
Sh='Shadowfacs:BAAANQADCgMIBwAAAA==.Shadowvail:BAAANQADCgQIBgAAAA==.Shakama:BAAANQADCgcIFwAAAA==.Shallowhale:BAAANQADCgUICQAAAA==.Shallzappy:BAAANQAECgYIDwAAAA==.Shamander:BAAANQADCgQIBgAAAA==.Shammyfox:BAAANQADCgYIEwAAAA==.Shamuraijack:BAAANQAECgQIBAABNQAECgYIDAAEAAAAAA==.Sharlock:BAAANQABCgYIBgAAAA==.Sheepngone:BAAANQADCgcIBwAAAA==.Shihow:BAAANQABCgYIBgAAAA==.Shooth:BAAANQAECgcICQAAAA==.Shortangry:BAAANQADCggIEAAAAA==.Shrubs:BAAANQAECgEIAgABNQAECgIIAgAEAAAAAA==.',
Si='Sickminded:BAAANQAECgUIDAAAAA==.Sikes:BAAANQADCgYIDAAAAA==.Sikés:BAAANQAECgMIBAAAAA==.Silvain:BAAANQAECgUICwAAAA==.Sinkhole:BAAANQADCggICAAAAA==.',
Sk='Skittzo:BAAANQADCgYICgAAAA==.',
Sl='Slashstar:BAAANQADCggICQAAAA==.Slinky:BAAANQADCgcIBwAAAA==.',
Sm='Smexyandikno:BAAANQAECgcIEwAAAA==.',
Sn='Snokums:BAAANQAECgIIAgAAAA==.Snozzberry:BAAANQADCggIEgAAAA==.Snykes:BAAANQADCgUIDQAAAA==.',
So='Solaren:BAAANQAECgEIAQAAAA==.Soulsplash:BAAANQADCgUICgAAAA==.',
Sp='Spellsling:BAAANQADCgYIBgAAAA==.Spence:BAABNQAECoEWAAIRAAgJEBGtYwAcAgARAAgJEBGtYwAcAgAAAA==.',
St='Stankonia:BAAANQADCgMIBQAAAA==.Stanlitwochi:BAAANQAECgYIDgAAAA==.Starbie:BAAANQADCgUIBQAAAA==.Sticky:BAAANQAECgQIBAAAAA==.Stormkitty:BAAANQAECgEIAgAAAA==.Stout:BAAANQAECgYICAAAAA==.Stubs:BAAANQADCggICAAAAA==.Stumblerut:BAAANQADCgQIBAABNQAECgEIAgAEAAAAAA==.Stuntyron:BAAANQAECgMIAwAAAA==.Stícky:BAAANQADCgQIBAABNQADCggIEgAEAAAAAA==.',
Su='Sums:BAAANQAECgcIDwAAAA==.Sunadrae:BAAANQADCgcIBwAAAA==.Sunser:BAAANQAECgYIEQAAAA==.Superdruid:BAAANQADCggIDgAAAA==.Supremus:BAAANQAECgEIAQAAAA==.',
Sv='Svetlanka:BAAANQAECgEIAgAAAA==.',
Sy='Sylrêith:BAAANQADCggIHQAAAA==.Sylyndra:BAAANQAECgIIBQAAAA==.Syralvia:BAAANQAECgEIAQAAAA==.',
['Sø']='Søulz:BAAANQADCgUIBwAAAA==.',
Ta='Tabaleina:BAAANQADCgMIAgAAAA==.Taltosh:BAAANQADCggIEgAAAA==.Tardishunter:BAAANQADCggIHQAAAA==.Tartarrus:BAAANQAECgYIBwAAAA==.Taterthots:BAAANQADCgYICQAAAA==.Taulmäril:BAAANQAECgEIAgAAAA==.',
Te='Tearsofpain:BAAANQADCggIDgAAAA==.Tearsofrain:BAAANQADCgMIBwAAAA==.Tearsofsolan:BAAANQADCgIIAgAAAA==.Teddista:BAAANQABCgIIAwAAAA==.Tellamental:BAEANQABCgIIAwABNQAECgcICwAEAAAAAA==.Tellen:BAEANQAECgcICwAAAA==.',
Th='Tharkeves:BAAANQADCgUIBQAAAA==.That:BAAANQADCggIDgAAAA==.Thdoria:BAAANQABCgQIBAAAAA==.Thequae:BAAANQADCggIEgAAAA==.Therin:BAAANQADCggIBgAAAA==.This:BAAANQADCgYIBgAAAA==.Thostin:BAAANQADCgcIDAAAAA==.Thotlety:BAAANQAECgEIAQAAAA==.Thrèsh:BAAANQAECgcIDwAAAA==.Thymara:BAAANQAECgYICwAAAA==.',
Ti='Tiamot:BAAANQADCggIGQAAAA==.Ticksndots:BAAANQAECgUICAAAAA==.Tirinas:BAAANQADCgIIAgAAAA==.',
To='Toastragosa:BAAANQADCggIFAAAAA==.Tobais:BAAANQAECgQIBAAAAA==.Tombstone:BAAANQAECgQIBgAAAA==.',
Tr='Trapmedaddy:BAAANQADCgMIAwAAAA==.Trigzy:BAAANQADCgUIBgAAAA==.Triqqy:BAAANQAECgQIBAAAAA==.Triqzy:BAAANQADCgQIBAAAAA==.Troikka:BAAANQAECgQIBgAAAA==.Tropicana:BAAANQAECgEIAQAAAA==.Truinnean:BAAANQAECgQIBQAAAA==.',
Tu='Tuarang:BAAANQADCggIDgAAAA==.Turokuruvar:BAAANQAECgEIAQAAAA==.',
Tw='Twinevil:BAAANQADCggIDwAAAA==.',
Ty='Tynker:BAAANQAECgIIAgAAAA==.Tyravelle:BAAANQADCggIDgAAAA==.',
['Tú']='Túg:BAAANQADCggIDAABNQAECggIEAAEAAAAAA==.',
Un='Undousedrice:BAAANQAECgUIBgAAAA==.Unleashes:BAAANQAECgMIBQAAAA==.',
Uz='Uzu:BAAANQADCgMIBQAAAA==.',
Va='Vaelwyn:BAAANQADCgYIBgAAAA==.Validar:BAAANQADCggIEwAAAA==.Valërie:BAAANQAECgQIBAAAAA==.Vanarian:BAABNQAECoEZAAIDAAgJxRMtHgBLAgADAAgJxRMtHgBLAgAAAA==.Varaza:BAAANQADCgIIAgAAAA==.',
Ve='Velaania:BAAANQAECgIIAgAAAA==.Veleno:BAAANQADCgUIBQAAAA==.Venóm:BAAANQADCgEIAQABNQADCgUIBQAEAAAAAA==.Vertaí:BAAANQADCggIGwAAAA==.Veter:BAAANQAECgQICgAAAA==.Vexxon:BAAANQAECggIBwABNQAECggICAAEAAAAAA==.',
Vi='Vibrotron:BAAANQAECgUICQAAAA==.Vicinia:BAAANQADCgMIAwAAAA==.Victraa:BAAANQADCgYIBgAAAA==.Virusalert:BAAANQADCgYIBwAAAA==.',
Vo='Voidpera:BAAANQAECgEIAQAAAA==.',
Vu='Vulpics:BAAANQAECgUIDQAAAA==.',
['Vè']='Vèrten:BAAANQADCgYIBgAAAA==.',
Wa='Warexx:BAAANQADCggIGQAAAA==.Wasupnow:BAAANQAECgUIBwAAAA==.',
We='Weetchdoctah:BAAANQAECgQIBAAAAA==.Weewarrior:BAAANQAECggICAAAAA==.Wenadin:BAAANQADCggIHAAAAA==.Wetwibution:BAABNQAECoEZAAMWAAgJWAxkTQDBAQAWAAgJWAxkTQDBAQAXAAcJ6gktTAB9AQAAAA==.',
Wh='Whimpy:BAAANQADCgcIDQAAAA==.Whovias:BAAANQADCgUIDgABNQADCgYIGQAEAAAAAA==.',
Wi='William:BAAANQADCggIHAAAAA==.',
Wr='Wrathawk:BAAANQADCgYIBwAAAA==.',
Xh='Xhii:BAABNQAECoEaAAIQAAgJqB9rAwDjAgAQAAgJqB9rAwDjAgAAAA==.',
Xi='Xingxong:BAAANQADCgUIBQAAAA==.',
Xu='Xuann:BAAANQAECgMIAwAAAA==.',
Xy='Xykaz:BAABNQAECoEZAAIRAAgJ9BWCUQBXAgARAAgJ9BWCUQBXAgAAAA==.',
Ya='Yanakiria:BAAANQAECgIIAwAAAA==.',
Ye='Yendi:BAAANQAECgQIBAAAAA==.',
Yn='Yngvar:BAAANQAECgcIDAAAAA==.',
Yo='Yokira:BAAANQABCggIDgAAAA==.You:BAAANQAECgQIBAAAAA==.',
Yr='Yrrmad:BAAANQABCgEIAQAAAA==.',
Za='Zarknoth:BAAANQAECgcIDwAAAA==.',
Ze='Zelmancha:BAAANQAECgcICgAAAA==.Zenkichi:BAAANQADCgYIDgAAAA==.Zephyyra:BAAANQADCggIEgAAAA==.Zethriel:BAAANQAECgIIAgAAAA==.Zevorra:BAAANQADCgYIBgABNQADCggIHQAEAAAAAA==.',
Zh='Zhealan:BAAANQADCgYICQAAAA==.',
Zi='Zibreezie:BAAANQADCgQIBgAAAA==.Zilmage:BAAANQAECgUICwAAAA==.Zinathyr:BAABNQAECoEaAAIYAAgJBRdADwAvAgAYAAgJBRdADwAvAgAAAA==.',
Zo='Zorrita:BAAANQADCgMIBgAAAA==.',
Zu='Zulrahk:BAAANQADCgYIBgAAAA==.',
Zy='Zycie:BAAANQAECgQICAAAAA==.',
Zz='Zzuul:BAAANQAECgQIBAAAAA==.',
['Zý']='Zýe:BAAANQAECgIIAgAAAA==.',
['Æx']='Æxil:BAAANQADCgMICQAAAA==.',
['Él']='Éleanor:BAAANQAECgQICgAAAA==.',
['Öh']='Öhai:BAAANQAECgIIAgAAAA==.',
['ßr']='ßröádin:BAAANQADCgMIAwAAAA==.',
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
