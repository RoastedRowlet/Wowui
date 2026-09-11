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

local lookup = {'Unknown-Unknown','Warlock-Demonology','Warlock-Destruction','Mage-Arcane','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Unholy','Priest-Holy','Warrior-Arms','Paladin-Retribution','Monk-Mistweaver',}
local provider = {region='US',realm='Bonechewer',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aandras:BAAANQADCggIDQAAAA==.',
Ab='Abbey:BAAANQADCgYIBgAAAA==.Abhayah:BAAANQADCgcIEwAAAA==.Absportls:BAAANQADCgcIDAAAAA==.',
Ac='Acelliste:BAAANQAECgMIAwAAAA==.',
Ad='Adventurerr:BAAANQADCgMIBQAAAA==.',
Af='Affgrezz:BAEANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
Ai='Aidlef:BAAANQAECgMIAwABNQAECgcIDAABAAAAAA==.Aikenbranwen:BAAANQADCggIGwAAAA==.',
Al='Alandor:BAAANQADCgUICgAAAA==.Allfire:BAAANQAECgYIDAAAAA==.Aluunix:BAAANQAECgEIAQAAAA==.Alyse:BAAANQAECgYICwAAAA==.Alyta:BAAANQADCggIGgAAAA==.',
Am='Amayla:BAAANQADCgcIBwAAAA==.',
An='Anulstorm:BAAANQABCgQIBAAAAA==.Anundir:BAAANQAECgQIBQAAAA==.',
Ao='Aondor:BAAANQAECgIIBAAAAA==.',
Ap='Applepi:BAAANQADCgEIAQAAAA==.',
Ar='Arcanical:BAAANQADCgYIDAAAAA==.Arday:BAAANQAECgYICwAAAA==.Aroromunroe:BAAANQAECgQICAABNQADCggIDgABAAAAAA==.Arrancateta:BAAANQAECgIIAgAAAA==.',
As='Ashblast:BAAANQADCgQIBAAAAA==.Ashira:BAAANQADCgcIEQABNQAECgcICwABAAAAAA==.Astarouge:BAAANQAECgQICAAAAA==.Astrasneaky:BAAANQAECgYICQAAAA==.',
At='Atchafalaya:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.',
Av='Avatarstate:BAAANQADCgQIBAAAAA==.Avayl:BAAANQADCgIIAgAAAA==.',
Aw='Awrina:BAAANQADCggIFQAAAA==.',
Az='Azylrog:BAAANQADCgQICwAAAA==.',
Ba='Babypeech:BAAANQABCgYIBgAAAA==.Bakulu:BAAANQADCgcIEgAAAA==.Bantoou:BAAANQADCgcIEgAAAA==.Bathoryz:BAAANQAECgcICgAAAA==.Battlescars:BAAANQADCgUICAAAAA==.Bauhaus:BAAANQADCgMIBAAAAA==.Bauld:BAAANQADCgcIDwAAAA==.',
Be='Beardybear:BAAANQAECgQIBgAAAA==.Bearicaide:BAAANQAECgQIBQAAAA==.Beautiful:BAAANQADCgYIBgAAAA==.Beefygee:BAAANQADCgMIAwAAAA==.Belldrak:BAAANQADCgUIBQAAAA==.Belldrin:BAAANQADCggIDAAAAA==.Bepaulie:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.Bergidum:BAAANQADCgUIBQAAAA==.Beriamilbinc:BAAANQADCgYICAAAAA==.',
Bi='Biglett:BAAANQAECgYICQAAAA==.Bignagos:BAAANQADCgMIBAAAAA==.Bigthickheal:BAAANQADCgEIAQAAAA==.',
Bl='Blackk:BAAANQAECgcICwAAAA==.Blackxcoffee:BAAANQADCgIIAgAAAA==.Bladesong:BAAANQADCgcICwAAAA==.Blood:BAAANQAECgEIAQAAAA==.Blorglock:BAAANQAECgcIDwAAAA==.Blorgonw:BAAANQADCgYIEQABNQAECgcIDwABAAAAAA==.Blowaegis:BAAANQAECgQIBAAAAA==.Blownoutshax:BAAANQADCgEIAQAAAA==.Bluntnfortys:BAAANQADCgUIBQAAAA==.Blupenguiny:BAAANQAECgQICAAAAA==.',
Bm='Bmfsleeps:BAAANQADCgUICAAAAA==.',
Bn='Bnortwarrior:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.',
Bo='Boanz:BAAANQADCggIDQAAAA==.Bobasaurus:BAAANQAECgQICAAAAA==.Bombastik:BAAANQADCgYIBgAAAA==.Bosskün:BAAANQADCgMIAwAAAA==.Bountie:BAAANQAECgQIBAAAAA==.Boyoyong:BAAANQADCgQIBAAAAA==.',
Br='Brainmatter:BAAANQADCgUIBQAAAA==.Brandedsoul:BAAANQADCgIIAgAAAA==.Brewztler:BAAANQADCgUICgAAAA==.Brightscale:BAAANQADCggIDgAAAA==.Broham:BAAANQAECgEIAQAAAA==.Bromeheal:BAAANQADCgIIAgAAAA==.Bronik:BAAANQAECgQIBAAAAA==.',
Bu='Buffmage:BAAANQAECgQICAAAAA==.Bullman:BAAANQADCgcICAABNQAECgcIDgABAAAAAA==.Bullrûsh:BAAANQAECgMIAwABNQAECgYIBgABAAAAAA==.Bullviper:BAAANQADCgYIDwAAAA==.',
['Bè']='Bèrsèrk:BAAANQADCgcIBwABNQAECgYICwABAAAAAA==.',
['Bì']='Bìgdaddy:BAAANQADCgUIBQAAAA==.',
['Bø']='Bønestørm:BAAANQAECgYICwAAAA==.',
['Bù']='Bùndee:BAAANQAECgEIAQAAAA==.',
Ca='Cabbâge:BAAANQADCgEIAQAAAA==.Cacapants:BAAANQADCgMIAwAAAA==.Caliex:BAAANQAECgQIBAAAAA==.Califax:BAAANQAECgcICwAAAA==.Callsignwiz:BAAANQABCgYIDQABNQAECgMIAwABAAAAAA==.Cannedbeans:BAAANQADCgMIAwAAAA==.Captantrips:BAAANQADCgQIBwAAAA==.Catazhanir:BAAANQADCggICgAAAA==.Catclown:BAAANQAECgYICAAAAA==.Catscrtchfvr:BAAANQADCgQIBAAAAA==.Cavonesee:BAAANQADCgcICAAAAA==.Caylaramose:BAAANQADCggICAAAAA==.Cazsandra:BAAANQAECgYIBwAAAA==.',
Cc='Ccs:BAAANQADCgYIDQAAAA==.',
Ch='Chamlio:BAAANQADCgUICgAAAA==.Channis:BAAANQADCgQIAwAAAA==.Chenaccles:BAAANQADCgQIBAAAAA==.Chickenrally:BAAANQAECgQIBQAAAA==.Chinobear:BAAANQADCgYIEAAAAA==.Chixilog:BAAANQADCgQIBAAAAA==.Chodyboy:BAAANQABCgYIBgAAAA==.Chuchix:BAAANQAECgcIDwAAAA==.Chuckler:BAAANQABCgYIBwAAAA==.',
Cl='Cladtu:BAAANQAECgIIAgAAAA==.Cleiah:BAAANQADCgUIBQAAAA==.Cloudfisto:BAAANQADCgYICAAAAA==.',
Co='Colacolaz:BAABNQAECoEUAAMCAAkJgSSuCQDRAgACAAcJsSOuCQDRAgADAAYJoSN/BwBXAgAAAA==.Colasham:BAAANQAECgMIAwABNQAECgkJFAACAIEkAA==.Coldhands:BAAANQADCgEIAQABNQAECgUICAABAAAAAA==.Colombiano:BAAANQADCgYIDQABNQAECgMIAwABAAAAAA==.Coltoff:BAAANQAECgcIEAAAAA==.Conker:BAAANQADCgUIBQAAAA==.Coprates:BAAANQADCgcIDwAAAA==.Corgiquester:BAAANQADCgYIBwAAAA==.Corpserot:BAAANQADCgEIAQAAAA==.Corsin:BAAANQADCgQIBQAAAA==.Cowbustion:BAAANQAECgMIBgAAAA==.',
Cr='Cracken:BAAANQADCggICgABNQAECgUIBwABAAAAAA==.Crankshot:BAAANQADCgUIBQABNQADCgYICQABAAAAAA==.Crimsonrayne:BAAANQAECgQIBQAAAA==.Crusherlol:BAAANQAECgIIAgAAAA==.Crusherlul:BAAANQADCgYICwABNQAECgIIAgABAAAAAA==.',
Da='Dabigoldk:BAAANQAECgUIBQAAAA==.Dannzig:BAAANQADCgIIAgAAAA==.Daragon:BAAANQADCgEIAQABNQAECgQIBgABAAAAAA==.Darkravèn:BAAANQAECgQIBgAAAA==.Darthkitsune:BAAANQADCgYICQAAAA==.Datbubblelol:BAAANQAECgEIAQAAAA==.Datchick:BAAANQADCgcIDwAAAA==.Dawnlily:BAAANQABCgQIBAAAAA==.Dazbek:BAABNQAECoEXAAIEAAkJPRpTIADVAgAEAAkJPRpTIADVAgAAAA==.',
De='Decày:BAAANQADCgQIBAABNQAECgYIDAABAAAAAA==.Deepdutch:BAAANQAECgQIBQAAAA==.Deezzeezz:BAAANQAECgEIAQABNQAECggIEQABAAAAAA==.Degeneffe:BAAANQADCgcIFAAAAA==.Demoreknight:BAAANQAECgUICQAAAA==.Devilboy:BAAANQAECgQICAAAAA==.Dextrey:BAAANQADCggICAABNQAECgUIBQABAAAAAA==.',
Di='Dialuptacos:BAAANQABCgYIBgAAAA==.Diddycombs:BAAANQADCgYIBgAAAA==.Discbrown:BAAANQAECggIEwAAAA==.Discmemommy:BAAANQADCgYICAABNQAECgYIDAABAAAAAA==.Discontent:BAAANQADCgcICQAAAA==.',
Dj='Djblink:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.',
Dk='Dkgaming:BAAANQAECgEIAQAAAA==.',
Do='Dogeared:BAAANQAECgQIBQAAAA==.Domore:BAAANQADCggIFgAAAA==.Donniedrako:BAAANQADCgQIBAAAAA==.Donson:BAAANQAECgYIDAAAAA==.Donsun:BAAANQADCgUIBQAAAA==.Doodlebobb:BAAANQADCgcIFAAAAA==.Doomlakalaka:BAAANQADCgUIEAAAAA==.Dorgh:BAAANQADCgIIAgAAAA==.Doubleclap:BAAANQADCggIDAAAAA==.',
Dp='Dpzofdoom:BAAANQADCgcIFAAAAA==.',
Dr='Dracthwnd:BAABNQAECoEYAAMFAAkJJR17AgBQAgAGAAgJNRyqBgCbAgAFAAgJ2Rp7AgBQAgAAAA==.Dragbrown:BAAANQADCgYIBgAAAA==.Dragonsins:BAAANQAECggIDgAAAA==.Drdiksmasher:BAAANQAECgEIAQAAAA==.Drekka:BAAANQADCgEIAQAAAA==.Droptopp:BAAANQAECgQICAAAAA==.Drusys:BAAANQADCgYIBgAAAA==.Dryrod:BAAANQABCgYIBwAAAA==.',
Du='Duckelf:BAAANQAECgYICgAAAA==.Durrga:BAAANQAECgcICgAAAA==.',
['Dã']='Dãftmõnk:BAAANQAECgEIAQAAAA==.',
Ed='Edgecrusherr:BAAANQADCggICAAAAA==.',
Eg='Egwenalmere:BAAANQADCgcIEQAAAA==.',
El='Elainia:BAAANQADCgUICAAAAA==.Elisaveta:BAAANQADCgcICgAAAA==.Elliaa:BAAANQADCgYICgAAAA==.Elodi:BAAANQADCgYIBgAAAA==.',
Em='Emanx:BAAANQABCgIIAgABNQAECgIIAgABAAAAAA==.',
En='Enheduanna:BAAANQADCgUICAAAAA==.',
Eo='Eowyen:BAAANQADCgUIBQAAAA==.',
Ep='Epiiphany:BAAANQADCgYIBwAAAA==.',
['Eì']='Eìrì:BAAANQAECgEIAQAAAA==.',
['Eô']='Eôwyn:BAAANQADCgQIBwAAAA==.',
Fa='Faclion:BAAANQAECgQIBAAAAA==.Faketurkey:BAAANQAECgIIAgAAAA==.Fari:BAAANQADCgcICwAAAA==.Fatlootz:BAAANQAECgYIDAAAAA==.',
Fe='Feltyah:BAAANQADCgUIDQAAAA==.',
Fi='Finnajuggyou:BAAANQAECgIIAgAAAA==.Finniker:BAAANQAECgIIAgAAAA==.Fiorina:BAAANQAECgQIBgAAAA==.Firefóx:BAAANQADCggICAAAAA==.Fishnet:BAAANQADCgYIBgAAAA==.Fishthicc:BAAANQADCgYIEAAAAA==.',
Fl='Flashnikko:BAAANQADCgIIAgAAAA==.Flexkin:BAAANQAECgQICAAAAA==.',
Fo='Foe:BAAANQAECggIEgAAAA==.Fornor:BAAANQAECgcIDgAAAA==.Foxfù:BAAANQADCgYIDAAAAA==.Foxkníght:BAAANQAECgcIDgAAAA==.Foxxpachi:BAAANQADCggIEgAAAA==.',
Fr='Franký:BAAANQADCgUIBgAAAA==.Frogus:BAAANQAECgQIBQAAAA==.',
Fu='Fungbuck:BAAANQABCgUIBwAAAA==.Fungbucko:BAAANQABCgQIBAAAAA==.Fuule:BAAANQADCgcIEwAAAA==.Fuusei:BAAANQAECgIIAgAAAA==.',
Fy='Fyrdrakon:BAAANQAECgMIBQAAAA==.',
Ga='Gabeitch:BAAANQADCgMIAwAAAA==.Galapagós:BAAANQADCgQIBwABNQADCgUIBQABAAAAAA==.Galaxus:BAAANQAECgcIEAAAAA==.Gammastorm:BAAANQAECgQIBAAAAA==.',
Gh='Ghall:BAAANQADCgIIAgAAAA==.Ghrell:BAEANQAECgIIBAAAAA==.',
Gi='Gickygackers:BAAANQADCgYIDgAAAA==.Gigglepeak:BAAANQADCggIDwAAAA==.Girlhands:BAAANQADCgIIAgAAAA==.',
Gl='Glekimage:BAAANQAECgMIAwAAAA==.',
Go='Goatmylk:BAAANQADCgYIDQAAAA==.Gobblr:BAAANQADCgMIBAAAAA==.Golokis:BAAANQADCggICAABNQAECgcICAABAAAAAA==.Gonuhreeuh:BAAANQAECgQIBAABNQAECgUIDwABAAAAAA==.Gotz:BAAANQADCgUIBgAAAA==.',
Gr='Grattick:BAAANQADCgcIEgAAAA==.Greenlightt:BAAANQADCgUICgAAAA==.Greenxll:BAAANQAECgQICAAAAA==.Grezulock:BAEANQAECgEIAQAAAA==.Griggles:BAAANQAECgIIAwAAAA==.Grikol:BAAANQADCgIIAgAAAA==.Grizzbane:BAAANQADCgEIAQAAAA==.Grolk:BAAANQADCgYICwAAAA==.',
Gu='Guerita:BAAANQADCgUIBQAAAA==.Gumptruck:BAAANQAECgQIBgAAAA==.',
Gw='Gwenevere:BAAANQADCgMIAwAAAA==.',
Ha='Habibii:BAAANQADCgQIBAAAAA==.Hardendaire:BAAANQADCgQIBwAAAA==.Hashypally:BAAANQAECgMIAwAAAA==.Hathern:BAAANQADCgIIAgAAAA==.Hawkmees:BAAANQAECgQIBgAAAA==.Hazbretzul:BAAANQAECgQIBAAAAA==.',
He='Heelza:BAAANQADCgUIBQAAAA==.Hellskitchën:BAAANQADCgQIBAAAAA==.Help:BAAANQADCgcICAAAAA==.Hephs:BAAANQADCgYIDQABNQAECgQIBAABAAAAAA==.Hermionejean:BAAANQADCgUIBQAAAA==.Hexuz:BAAANQAECgQIBAAAAA==.',
Hi='Hipster:BAAANQAECgIIAwABNQABCgIIAgABAAAAAA==.',
Ho='Holeekow:BAAANQADCgEIAgAAAA==.Hollymollie:BAAANQADCggIDAAAAA==.Holymobeus:BAAANQABCgYIBAAAAA==.Holypower:BAAANQADCgYICQAAAA==.Holythot:BAAANQAECgUICgAAAA==.Hozrozlok:BAAANQAECgUICAAAAA==.',
Hu='Hufgar:BAAANQADCgUICwAAAA==.Huntdry:BAAANQAECgMIAwAAAA==.Hurkoh:BAAANQADCggIEgAAAA==.Hushpuppié:BAAANQAECgEIAgAAAA==.',
Hy='Hypereon:BAAANQAECgQIBAAAAA==.',
Ic='Icanthelpyou:BAAANQAECgYIBwAAAA==.Iceden:BAAANQADCggIDQAAAA==.Icyweenor:BAAANQAECgEIAQAAAA==.',
Id='Idkdude:BAAANQAECgQICAAAAA==.',
Ie='Ielarth:BAAANQADCgEIAQAAAA==.',
Il='Illadarina:BAAANQAECgUIBwAAAA==.Illí:BAAANQADCgYIBgAAAA==.',
In='Incetardis:BAAANQADCgYIDQAAAA==.',
Ir='Iradoria:BAAANQAECgcICwAAAA==.',
Is='Isoldè:BAAANQADCgcIBwAAAA==.Istabu:BAAANQADCgYIBgAAAA==.',
It='Itachi:BAABNQAECoEXAAIHAAkJvyW3AADhAwAHAAkJvyW3AADhAwAAAA==.Itamï:BAAANQAECgQICAAAAA==.',
Iv='Ivannacream:BAAANQADCggICAAAAA==.',
Ja='Jaagren:BAAANQADCgYIBgAAAA==.Jadawin:BAAANQAECgEIAQAAAA==.Jaketta:BAAANQAECgEIAQAAAA==.Jasnah:BAABNQAECoEOAAIEAAkJaALydgB8AQAEAAkJaALydgB8AQAAAA==.Jayrel:BAAANQAECgcIDgAAAA==.',
Je='Jerrik:BAAANQAECgMIAwAAAA==.',
Jo='Joeyexotic:BAAANQADCgYIBgAAAA==.Jokem:BAAANQADCgUIBQAAAA==.',
Ju='Juankkii:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Juggerbear:BAAANQADCgYIDgAAAA==.Juiçy:BAAANQADCgYIBgAAAA==.Juls:BAAANQAECgQIBAAAAA==.Justhetip:BAAANQADCgEIAQAAAA==.',
['Jä']='Jäger:BAAANQAECgEIAQAAAA==.',
Ka='Kagama:BAAANQAECgEIAQAAAA==.Kalatabi:BAAANQADCggICAABNQAECgUICQABAAAAAA==.Kalatai:BAAANQAECgUICQAAAA==.Kamisenshi:BAAANQADCgIIAgAAAA==.Karayna:BAAANQADCggIEAAAAA==.Kareemcheese:BAAANQAECgEIAQAAAA==.Kauko:BAAANQAECgMIAwAAAA==.',
Ke='Kellanash:BAAANQADCgQIBAAAAA==.Kezwik:BAAANQAECgUIBQAAAA==.',
Kh='Khaotick:BAAANQADCgUICgAAAA==.Kheetz:BAAANQAECgEIAQAAAA==.',
Ki='Kikosho:BAAANQAECgEIAgAAAA==.Kilaaj:BAAANQADCgIIAgAAAA==.Killerbane:BAAANQADCgcICQAAAA==.Kinclakis:BAAANQADCgQIBAAAAA==.Kinthor:BAAANQABCgIIAgAAAA==.Kirrin:BAAANQAECgQIBQAAAA==.',
Kn='Kneecap:BAAANQAECgQIBAAAAA==.Kneepad:BAAANQADCgcIBwAAAA==.Knetikara:BAAANQAECgYIDAAAAA==.',
Ko='Kokokrantz:BAAANQADCggIEAAAAA==.Korthix:BAAANQAECgUIBQAAAA==.Kosi:BAAANQABCgYIDAAAAA==.',
Kr='Kreiedril:BAAANQADCgYIDgAAAA==.Krispytoo:BAAANQAECgQIBQAAAA==.',
Ku='Kulltina:BAAANQADCggICAAAAA==.',
Ky='Kyokaii:BAAANQADCgUIBQAAAA==.Kyrasala:BAAANQADCgIIAgAAAA==.',
La='Laarken:BAAANQADCggICQAAAA==.Lacedtotems:BAAANQAECgcIEQAAAA==.Lagexe:BAAANQADCggIEQAAAA==.Lazlo:BAAANQAECgQIAwAAAA==.',
Le='Lenrela:BAAANQAECgIIAgAAAA==.Lestealth:BAAANQAECgIIAgAAAA==.Letena:BAAANQAECgYICgAAAA==.Levyymage:BAAANQAECgEIAQAAAA==.',
Li='Lialyndra:BAAANQADCgQIBAAAAA==.Licelia:BAAANQAECgUICgAAAA==.Lilballohate:BAAANQADCgEIAQAAAA==.Liligayle:BAAANQADCgMIAwAAAA==.Linane:BAAANQAECgQICQAAAA==.Lite:BAAANQADCggICQAAAA==.Liveevil:BAAANQAFFAEIAQAAAA==.',
Lo='Loathsome:BAAANQADCgEIAQABNQAECgQIBwABAAAAAA==.Lolmagician:BAAANQABCgIIAgAAAA==.Loquail:BAAANQADCgUIBQAAAA==.',
Lu='Lucifoor:BAAANQADCgUICgAAAA==.Luftim:BAAANQAECgEIAQAAAA==.Lunoxx:BAAANQADCgUICAAAAA==.Lurang:BAAANQADCgcIBwAAAA==.',
Ma='Macacbre:BAAANQADCgMIAwAAAA==.Macdotnalds:BAAANQADCgMIAwAAAA==.Madetolock:BAAANQADCgMIBAAAAA==.Maerlyna:BAAANQABCgEIAQAAAA==.Magebrew:BAAANQADCgYIBwAAAA==.Mageycat:BAAANQADCgYICAABNQAECgYICAABAAAAAA==.Magicma:BAAANQAECgQIBAAAAA==.Mahlah:BAAANQABCgIIAgAAAA==.Makarov:BAAANQADCgEIAQAAAA==.Maliun:BAAANQAECgEIAQAAAA==.Malusdemon:BAAANQADCggIGAAAAA==.Mamasota:BAAANQADCgcIDQAAAA==.Marisol:BAAANQADCgUICAAAAA==.Markfunk:BAAANQAECgYICwAAAA==.Markiepoo:BAAANQADCgcIBwABNQAECgYICwABAAAAAA==.Markyboom:BAAANQADCgIIAgABNQAECgYICwABAAAAAA==.Markykong:BAAANQADCgYIBwABNQAECgYICwABAAAAAA==.Mawmatz:BAAANQADCgEIAQAAAA==.',
Me='Mebashum:BAAANQAECgEIAQAAAA==.Meditations:BAAANQAECgMIAwAAAA==.Meleath:BAAANQADCgEIAQAAAA==.Melibeth:BAAANQABCgEIAQAAAA==.Metrakatanke:BAAANQADCgQIBAAAAA==.Mexiflip:BAAANQADCgYICQAAAA==.',
Mi='Midoriya:BAAANQAECgEIAQAAAA==.Milgan:BAAANQAECgYICgAAAA==.Minimochi:BAABNQAECoEcAAIIAAgJNwvsJQC/AQAIAAgJNwvsJQC/AQAAAA==.Missblackk:BAAANQADCgIIAgAAAA==.Mithyr:BAAANQADCgcIBwAAAA==.',
Mn='Mneme:BAAANQAECggIEwAAAA==.',
Mo='Monkeypiglet:BAABNQAECoELAAIJAAYJ0heQQQDEAQAJAAYJ0heQQQDEAQAAAA==.Moogpal:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Moogul:BAAANQAECgIIAgABNQAECgQIBAABAAAAAA==.Moovoe:BAAANQADCgYIBgAAAA==.Morcarth:BAAANQAECgEIAQAAAA==.Mortal:BAAANQADCgEIAQAAAA==.Morts:BAAANQADCgYIBgAAAA==.',
Mu='Mulks:BAAANQAECgYIDQAAAA==.Multiblox:BAAANQAECgQICAAAAA==.Murgruuk:BAAANQADCggICAAAAA==.',
['Mà']='Màrkham:BAAANQABCgQIBAAAAA==.',
Na='Naam:BAAANQAECgQIBAAAAA==.Nadrin:BAAANQADCgUIDwAAAA==.Naedora:BAAANQAECgQIBQAAAA==.Namixx:BAAANQAECgUICgAAAA==.Naruwnd:BAAANQADCggICAABNQAECgkJGAAFACUdAA==.Nathaanis:BAABNQAECoEZAAIKAAgJsRm8GAB9AgAKAAgJsRm8GAB9AgAAAA==.',
Ne='Necrodamus:BAAANQAECgEIAQAAAA==.Neliera:BAAANQABCgUIBQAAAA==.Neopolitangs:BAAANQAECgMIBAAAAA==.Nevsy:BAAANQADCgYIBgAAAA==.Nezdispenser:BAAANQADCgcICwAAAA==.',
Ni='Niduash:BAAANQADCgMIAwAAAA==.Nightchill:BAAANQAECgQIBAAAAA==.Nimbletoes:BAAANQAECgQIBgAAAA==.Nirza:BAAANQADCgYIDQAAAA==.Niziel:BAAANQAECgYICgAAAA==.',
No='Nofurrys:BAAANQADCggICQAAAA==.Nokorin:BAAANQADCgYICgAAAA==.Nolo:BAAANQADCgUIBQABNQAECggIEAABAAAAAA==.Noros:BAAANQAECggIEAAAAA==.',
Nu='Nuggalicious:BAAANQADCgcIDQAAAA==.Nursjoy:BAAANQADCggICAAAAA==.',
Ok='Oko:BAAANQADCgYIBgAAAA==.',
Om='Omenwar:BAAANQADCgcIEAAAAA==.Omni:BAAANQADCggICwAAAA==.',
Or='Orelia:BAAANQAECgMIAwAAAA==.Orfnanu:BAAANQADCgQIBAABNQADCgYIDAABAAAAAA==.Ornarl:BAAANQAECgIIAwAAAA==.',
Ot='Ottawa:BAAANQADCgYIBgAAAA==.',
Pa='Packtastic:BAAANQAECgMIBQAAAA==.Padthang:BAAANQAECgIIBAAAAA==.Palazyn:BAAANQADCggICgABNQAECgUIBwABAAAAAA==.Panhexual:BAAANQADCgQIBAAAAA==.Parketor:BAAANQADCggICAAAAA==.Pathyx:BAAANQAECgIIAgAAAA==.',
Pe='Peacefulguy:BAAANQABCgQIBgAAAA==.Peachjars:BAAANQAECgYIDAAAAA==.Pelvis:BAAANQADCgQIBAAAAA==.Perixi:BAAANQADCgYICgAAAA==.Perpekto:BAAANQADCgUIBQAAAA==.Peterpewpew:BAAANQADCgMIAwAAAA==.',
Ph='Phedragon:BAAANQADCgEIAQAAAA==.Phedrah:BAAANQAECgQIBgAAAA==.Philipx:BAAANQADCgQIBAAAAA==.',
Pi='Picklenator:BAAANQADCgcIFAAAAA==.Pierreplays:BAAANQADCgUIBQAAAA==.Pillowhands:BAAANQADCgQIBAAAAA==.Pilto:BAAANQAECgIIAwAAAA==.Pingo:BAAANQADCgcIEAAAAA==.Pinkmj:BAAANQADCgMIBgAAAA==.Pitchief:BAAANQAECgEIAQAAAA==.',
Po='Polendina:BAAANQAECgcICwAAAA==.Pooginator:BAAANQADCgYICAAAAA==.',
Pr='Prada:BAAANQADCgcIBwAAAA==.Premmish:BAAANQADCggICAAAAA==.Primeork:BAAANQADCgUIBQAAAA==.',
Ps='Psammophile:BAAANQAECgYICwAAAA==.Psymmer:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Psynge:BAAANQADCgYICgABNQAECgEIAQABAAAAAA==.Psynnergy:BAAANQAECgEIAQAAAA==.Psytellar:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.',
Pu='Pumprstltskn:BAAANQAECgIIAgAAAA==.Puppyflower:BAAANQADCgYIBQAAAA==.Purplepally:BAAANQADCgEIAQAAAA==.Purpleshroom:BAAANQADCgQIBAABNQADCgQIBAABAAAAAA==.Put:BAAANQADCgYICQAAAA==.',
Py='Pyrat:BAAANQADCggIFAAAAA==.Pyroangel:BAAANQADCgcIEQAAAA==.Pyrotwopnto:BAAANQADCgYIDgAAAA==.',
['Pí']='Píneapple:BAAANQAECgIIAwAAAA==.',
Qe='Qertinya:BAAANQADCgUICgAAAA==.',
Qu='Quadman:BAAANQAECgcIDAAAAA==.Quaxly:BAAANQADCgQIBAAAAA==.Quinexorable:BAAANQAECgcIDgAAAA==.',
Ra='Ragedaddy:BAAANQAECgcICAAAAA==.Rahkar:BAAANQAECgQIBAAAAA==.Rainndance:BAAANQAECgMIBAAAAA==.Raitan:BAAANQADCgQICwAAAA==.Rallet:BAAANQADCgIIAgAAAA==.Ramrodveazy:BAAANQAECgEIAQAAAA==.Ranaklos:BAAANQADCgQIBAABNQADCgIIAgABAAAAAA==.Rancimus:BAAANQAECgQICAAAAA==.Rangore:BAAANQADCgQIBAAAAA==.Ranocthan:BAAANQAECgEIAQAAAA==.Rarcher:BAAANQAECgEIAQAAAA==.Rasmuz:BAAANQADCgUIBwAAAA==.Rauthar:BAAANQAECgQIBAAAAA==.Rayyven:BAAANQADCgQIBAAAAA==.Razorsharp:BAAANQAECgQIBQAAAA==.',
Re='Recon:BAAANQAECgcIEAABNQAECggIDgABAAAAAA==.Reefermadnes:BAAANQAECgYICgAAAA==.Reelsteel:BAAANQADCgYICAAAAA==.Relnamah:BAAANQADCgUICwAAAA==.Reoloc:BAEANQADCgMIAwABNQADCgYIBgABAAAAAA==.Retandspank:BAAANQABCgQIBAAAAA==.Revdev:BAABNQAECoEjAAIKAAgJdxeyHgBNAgAKAAgJdxeyHgBNAgAAAA==.Revoke:BAAANQADCgEIAQABNQAECgQIBwABAAAAAA==.',
Rh='Rhapsydee:BAAANQADCgUIBQAAAA==.Rhododendron:BAAANQADCgcIBwAAAA==.Rhoñin:BAAANQABCgEIAQAAAA==.Rhuney:BAAANQAECgIIAgAAAA==.Rhunie:BAAANQADCgcIBwABNQAECgIIAgABAAAAAA==.Rhyllii:BAAANQADCggIFQAAAA==.',
Ri='Ripzug:BAAANQAECgQIBQAAAA==.',
Ro='Roadburner:BAAANQAECggIAQAAAA==.Roccotaco:BAAANQADCgQIBAAAAA==.Romenhoff:BAAANQAECgcICAAAAA==.Rootbeer:BAAANQAECgEIAQAAAA==.Roshambu:BAAANQADCgQIBQAAAA==.Roxinator:BAAANQADCgYIBgAAAA==.',
Ru='Ruikiea:BAAANQAECgEIAgABNQAECgYIEAABAAAAAA==.',
['Rà']='Ràggà:BAAANQAECgQIBAAAAA==.',
['Rí']='Rían:BAAANQADCgcIDwAAAA==.',
Sa='Saelenei:BAAANQADCgIIAgABNQADCgYICQABAAAAAA==.Saevra:BAAANQADCgMIAwAAAA==.Sairadoka:BAAANQADCgcIDwAAAA==.Samzori:BAAANQAECgEIAgAAAA==.Sanatizer:BAAANQAECgQIBQAAAA==.Sandret:BAAANQAECgQIBQAAAA==.Sarris:BAAANQAECgUIBQAAAA==.Sathriel:BAAANQAECgUICgAAAA==.Savagetotemz:BAAANQAECgcIBwAAAA==.',
Sc='Scalelujah:BAAANQADCgcICgABNQAECgEIAQABAAAAAA==.Scottadin:BAAANQAECgQICAAAAA==.',
Se='Seanx:BAAANQADCgUIBQAAAA==.Secondenvoy:BAAANQAECgEIAQAAAA==.Seerawh:BAAANQAECgYICgAAAA==.Sehetep:BAAANQAECgEIAQAAAA==.Sephyrea:BAAANQADCgYIBgAAAA==.Serigon:BAAANQABCgUIBwAAAA==.',
Sh='Shadownd:BAAANQAECggIEAABNQAECgkJGAAFACUdAA==.Shadowsloth:BAAANQADCgYIBgAAAA==.Shahli:BAAANQADCgIIAgAAAA==.Shakiro:BAAANQAECgMIAwAAAA==.Shaloendril:BAAANQADCgUIBQABNQAECgcIEAABAAAAAA==.Shamchan:BAAANQADCgYIBgAAAA==.Shamergency:BAAANQADCgUICgAAAA==.Shammyrock:BAAANQAECgQIBAAAAA==.Shamtony:BAAANQABCgQIBgAAAA==.Sharkk:BAAANQADCgYIBgAAAA==.Shaylar:BAAANQADCgcIDwAAAA==.Sherminator:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Shiherlis:BAAANQADCgMIAwABNQADCgQIBAABAAAAAA==.Shmacken:BAAANQAECgUIBwAAAA==.Shockinglee:BAAANQAECgEIAQABNQAECgQIBwABAAAAAA==.Shosannaa:BAAANQAECgIIAgAAAA==.Shuriken:BAAANQAECggIDwAAAA==.',
Si='Siete:BAAANQADCggIDgAAAA==.Sikbubblez:BAAANQAECgUIBgAAAA==.Sikshockz:BAAANQADCggIEAAAAA==.Silentblades:BAAANQADCgcIBwAAAA==.Sindazia:BAAANQADCggIDgAAAA==.Sinistry:BAAANQADCgEIAQAAAA==.Siopau:BAAANQADCgQIBAAAAA==.Sixunder:BAAANQADCgcIBwAAAA==.',
Sk='Skrinkles:BAAANQAECgQIBAAAAA==.Skullwhisper:BAAANQAECgIIAwAAAA==.',
Sl='Slomar:BAAANQADCgcIFQAAAA==.Slowar:BAAANQADCggICAAAAA==.Slowpallh:BAAANQADCgYICAABNQADCggICAABAAAAAA==.Slowrog:BAAANQADCgUIAwABNQADCggICAABAAAAAA==.Slowsh:BAAANQADCgUIBQABNQADCggICAABAAAAAA==.',
Sm='Smoggely:BAAANQAECgUIBwAAAA==.Smoketotem:BAAANQADCgYIDwAAAA==.',
Sn='Sneakzalot:BAAANQADCgMIAwAAAA==.Snowbreeze:BAAANQADCgcIDwAAAA==.Snowfláme:BAAANQAECgIIAgAAAA==.',
So='Solarity:BAAANQABCgUIBQAAAA==.Solie:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.Solki:BAAANQADCgIIAgAAAA==.Solrak:BAAANQADCgMIAwAAAA==.Soobatai:BAAANQADCgYIBgAAAA==.Soot:BAAANQAECgEIAQAAAA==.Sootzy:BAAANQAECgIIAgABNQAFFAMIBAABAAAAAA==.Sophiane:BAAANQAECgEIAQAAAA==.Soulcaller:BAAANQADCggICAAAAA==.Soulkrusher:BAAANQADCgYIDAAAAA==.',
Sp='Spadeii:BAAANQAECgUICQAAAA==.Spadex:BAAANQADCggICAABNQAECgUICQABAAAAAA==.Spagheddy:BAAANQADCggIDAAAAA==.Spellzy:BAAANQAECgUIDwAAAA==.Spicylatina:BAAANQADCgYIBgAAAA==.',
Sq='Squachy:BAAANQADCgYIBgABNQAECgcIDgABAAAAAA==.',
Ss='Sseoyoon:BAAANQADCgUIBQAAAA==.Ssnneezzyy:BAAANQAECgMIAwAAAA==.',
St='Starwnd:BAAANQAECgUIBQABNQAECgkJGAAFACUdAA==.Steadchi:BAAANQAECgQIBAAAAQ==.Stolibear:BAAANQAECgQIBgAAAA==.Stolidh:BAAANQADCgQIBAABNQAECgQIBgABAAAAAA==.Stolidk:BAAANQADCgUIBQABNQAECgQIBgABAAAAAA==.Stolip:BAAANQADCggICAABNQAECgQIBgABAAAAAA==.Stoneycrusty:BAAANQAECgYICwAAAA==.Straywalker:BAAANQADCgEIAQAAAA==.Strongside:BAAANQABCgIIAgAAAA==.Stublimë:BAAANQADCggIFAAAAA==.Studdie:BAAANQADCgYICQAAAA==.',
Su='Succeeds:BAAANQAECggICAAAAA==.Sungjinwooz:BAAANQAECgQIBQAAAA==.Suntitan:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Suuhdude:BAAANQAECgQIBQAAAA==.',
Sw='Swd:BAAANQAECgEIAQAAAA==.Swiffty:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.Swudge:BAAANQAECgEIAQAAAA==.',
Sy='Syladeith:BAAANQAECgQIBwAAAA==.Sylbanas:BAAANQADCgQICgABNQAECgEIAQABAAAAAA==.Syldrunk:BAAANQADCgcIDgAAAA==.Sylvashaman:BAAANQAECgEIAQAAAA==.',
['Sé']='Séii:BAAANQADCgYIBgAAAA==.',
['Sÿ']='Sÿdney:BAAANQADCgMIAwAAAA==.',
Ta='Tabarnaka:BAAANQAECgIIAgAAAA==.Tairnock:BAAANQADCggIDgAAAA==.Takabaka:BAAANQADCgEIAQABNQADCgQIBAABAAAAAA==.Tankadina:BAAANQADCgEIAQAAAA==.Tanzee:BAAANQAECgcIDgAAAA==.Tarmesan:BAAANQAECgcIDgAAAA==.Tastytooth:BAAANQAECgIIAgAAAA==.Taytaytyrone:BAAANQADCgEIAQAAAA==.',
Td='Tdog:BAAANQAECgUIBQAAAA==.',
Te='Tegadin:BAAANQADCgUICgAAAA==.Telemanus:BAAANQADCgUIBQAAAA==.Tesse:BAAANQADCgMIAwAAAA==.',
Th='Thannos:BAAANQAECgcICwAAAA==.Thanozul:BAAANQADCggIEQAAAA==.Thark:BAAANQAECgQIBAAAAA==.Thawnn:BAAANQADCgIIAgAAAA==.Thedùde:BAAANQADCgUIBQABNQADCggICQABAAAAAA==.Thelgrus:BAAANQADCgcIEgAAAA==.Thorane:BAAANQADCgYIBgAAAA==.Thrashcan:BAAANQAECgMIAwAAAA==.Threem:BAAANQADCgcIDAAAAA==.Threesteps:BAAANQADCgIIAgAAAA==.Throad:BAAANQADCgUIAQAAAA==.Throwbackhlz:BAAANQAECgEIAQAAAA==.Throwinshåde:BAAANQADCgcICgAAAA==.Thudmuffin:BAAANQAECgQICAABNQAECgQIBwABAAAAAA==.Thyrealest:BAAANQADCgEIAQAAAA==.Thysania:BAAANQABCgQIBwABNQABCgIIAgABAAAAAA==.',
Ti='Tides:BAAANQAECgQIBwAAAA==.Tinarii:BAAANQAECgcIEAAAAA==.Tinyshadow:BAAANQADCgcIEQAAAA==.Tinytit:BAAANQAECgQIBAAAAA==.Tinytusk:BAAANQABCgIIAgAAAA==.Titdruid:BAAANQADCgUIBQAAAA==.Titpoosy:BAAANQADCgYICAAAAA==.',
To='Tonystonk:BAAANQADCgUICgAAAA==.Toombz:BAAANQADCgYIBgAAAA==.Totemkoff:BAAANQABCgMIAwAAAA==.',
Tr='Tragha:BAAANQADCgMIBQAAAA==.Trayker:BAAANQADCgQIBAAAAA==.Traynisa:BAAANQADCgUICAAAAA==.Treykor:BAAANQADCgQIBAAAAA==.Tria:BAAANQADCgYIDwAAAA==.Trixrforkids:BAAANQADCgYIBgAAAA==.Trlight:BAAANQAECgEIAQAAAA==.Trollsicle:BAAANQAECgQIBwAAAA==.Trotah:BAAANQADCgYICQAAAA==.Tryzz:BAAANQAECgQIBgAAAA==.',
Tu='Tubhead:BAAANQADCgYIEQAAAA==.Tunare:BAAANQADCgYIDgABNQADCgcIBwABAAAAAA==.Tusknflamer:BAAANQADCgUIBwAAAA==.',
Tw='Twylla:BAAANQAECgUIBgAAAA==.',
Ty='Tynak:BAAANQADCgQIBAAAAA==.',
Ug='Ugroto:BAAANQADCggIEAAAAA==.',
Un='Unclesnottyp:BAAANQAECgEIAQAAAA==.Unmortal:BAAANQAECgMIAwAAAA==.',
Ur='Urotherdaddy:BAAANQADCgYIBgAAAA==.Uruker:BAAANQADCgIIAgAAAA==.',
Us='Useurblinker:BAAANQADCgcIBwAAAA==.',
Va='Valglacius:BAAANQADCgYICwAAAA==.Valkrin:BAAANQADCgYIBgAAAA==.Valonthir:BAAANQADCgQICwAAAA==.Valstone:BAAANQADCgIIAgABNQADCgYICwABAAAAAA==.Vancleave:BAAANQADCgYICwAAAA==.Vaylethrayne:BAAANQABCgQIBQAAAA==.',
Ve='Verguetta:BAAANQAECgEIAQAAAA==.Verinsedai:BAAANQADCgcIEQAAAA==.Vesimer:BAAANQADCggIDQAAAA==.',
Vi='Vicvondik:BAAANQADCgQIBAAAAA==.Vildri:BAAANQADCgcIDwAAAA==.Violetknight:BAAANQADCgIIAgAAAA==.',
Vo='Voidrey:BAAANQAECgMIBAAAAA==.Voikullten:BAAANQADCgUIBQAAAA==.Vornash:BAAANQADCgYIDAAAAA==.',
Vy='Vylent:BAAANQABCgQIBwAAAA==.',
Wa='Waddleweaver:BAAANQADCggICAAAAA==.Warkraz:BAAANQADCgMIAwAAAA==.Warrush:BAAANQAECgIIAgAAAA==.Watchmedps:BAAANQADCgcICwAAAA==.',
Wi='Wildthang:BAAANQADCgQIBAAAAA==.Willpray:BAAANQAECgIIAgAAAA==.Windle:BAAANQADCggICAAAAA==.',
Wo='Wontondesire:BAAANQAECgQIBAAAAA==.',
Xa='Xantry:BAEANQAECgIIAwAAAA==.',
Xb='Xbambs:BAAANQADCgQIBAAAAA==.',
Xe='Xerovladej:BAAANQADCgYIDAAAAA==.',
Xo='Xoog:BAAANQADCgcIEgAAAA==.Xozo:BAAANQADCgIIAgAAAA==.',
Xu='Xurk:BAAANQADCggICAAAAA==.',
Xw='Xwarrior:BAAANQAECgQIBQAAAA==.',
Ya='Yaaz:BAAANQAECgQIBAAAAA==.Yamata:BAAANQADCgQIBAAAAA==.',
Ye='Yetistorm:BAAANQADCgMIAwAAAA==.',
Yu='Yuee:BAAANQAECgMIAwAAAA==.',
Za='Zaehara:BAAANQAECgEIAQAAAA==.Zanarian:BAAANQAECgEIAQAAAA==.Zappinboi:BAAANQAECgIIAgABNQAECgkJFwALAIEdAA==.Zatkiel:BAAANQADCgcIBwAAAA==.',
Ze='Zealot:BAAANQADCgYIDgAAAA==.Zedar:BAAANQADCggIFwABNQAECgEIAQABAAAAAA==.Zeju:BAAANQAECgEIAgAAAA==.Zekinett:BAAANQADCgUIBQAAAA==.Zenolinwæ:BAAANQADCggIFgAAAA==.Zeohavoc:BAAANQADCgIIAgAAAA==.',
Zh='Zhondari:BAAANQADCgYIBgAAAA==.',
Zi='Zivanya:BAAANQADCgcIDgAAAA==.',
Zu='Zurprise:BAAANQADCgYICAAAAA==.',
Zx='Zxz:BAAANQAECgQIBgAAAA==.',
Zy='Zyrgarran:BAAANQADCgYIBwAAAA==.',
['Zá']='Záraya:BAAANQAECgQIBwAAAA==.',
['Zú']='Zúpái:BAAANQAECgEIAQAAAA==.',
['Àz']='Àzæs:BAAANQADCgcIEAAAAA==.',
['Ät']='Ätreo:BAAANQADCgQIBAAAAA==.',
['Æl']='Ælusive:BAAANQADCgcIBwAAAA==.',
['Ço']='Çondemned:BAAANQADCgQIBAABNQADCgQIBAABAAAAAA==.',
['Ém']='Émperor:BAAANQADCgUIBQAAAA==.',
['Îc']='Îcyhot:BAAANQADCgQIBAAAAA==.',
['Ðr']='Ðräx:BAAANQAECgIIAgAAAA==.',
['Óh']='Óhelgur:BAAANQADCgIIAgAAAA==.',
['Öh']='Öhgr:BAAANQAECgEIAQAAAA==.',
['ßí']='ßíll:BAAANQADCgYICwAAAA==.',
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
