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

local lookup = {'Unknown-Unknown','Paladin-Retribution','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','Druid-Balance','Druid-Restoration','Priest-Holy','Priest-Discipline','Mage-Arcane','Priest-Shadow','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Devourer','DeathKnight-Frost','Warrior-Arms','Rogue-Assassination','Hunter-Survival','Warrior-Protection','Shaman-Elemental','Hunter-Marksmanship','Hunter-BeastMastery','Monk-Brewmaster','Monk-Mistweaver',}
local provider = {region='US',realm='Bonechewer',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aandras:BAAANQAECgEIAQAAAA==.',
Ab='Abbey:BAAANQADCgYIBgAAAA==.Abhayah:BAAANQAECgMIAwAAAA==.Absportls:BAAANQAECgIIAgAAAA==.',
Ac='Acelliste:BAAANQAECgMIAwAAAA==.',
Ad='Adventurerr:BAAANQADCgMIBQAAAA==.',
Af='Affgrezz:BAEANQADCgQIBAABNQAECgIIAwABAAAAAA==.',
Ai='Aidlef:BAAANQAECgMIBAABNQAECgcIEgABAAAAAA==.Aikenbranwen:BAAANQADCggIJAAAAA==.',
Al='Alandor:BAAANQADCgUICgAAAA==.Allfire:BAAANQAECgcIEwAAAA==.Aluunix:BAAANQAECgQIBQAAAA==.Alyse:BAAANQAECgcIEQAAAA==.Alyta:BAAANQADCggIGgAAAA==.Alzulra:BAAANQADCgYIBgAAAA==.',
Am='Amayla:BAAANQADCgcIBwAAAA==.Amoracon:BAAANQADCgUIBQAAAA==.',
An='Anulstorm:BAAANQADCgYIBgAAAA==.Anundir:BAAANQAECgQICQAAAA==.',
Ao='Aondor:BAAANQAECgQICAAAAA==.',
Ap='Applepi:BAAANQADCgEIAQAAAA==.',
Ar='Arcanical:BAAANQADCgYIDAAAAA==.Arday:BAAANQAECgcIDwAAAA==.Aroromunroe:BAAANQAFFAEIAQABNQADCggIDgABAAAAAA==.Arrancateta:BAAANQAECgQIBgAAAA==.',
As='Asena:BAAANQADCgQIBAABNQAECgkJHwACAA8hAA==.Ashblast:BAAANQADCgQIBAAAAA==.Ashira:BAAANQAECgEIAQABNQAECgcIEgABAAAAAA==.Astarouge:BAAANQAECgQICAAAAA==.Astrasneaky:BAAANQAECgcIDQAAAA==.',
At='Atchafalaya:BAAANQAECgQIBQABNQAECgQICQABAAAAAA==.',
Av='Avatarstate:BAAANQADCgQIBAAAAA==.Avayl:BAAANQADCgQIBgAAAA==.',
Aw='Awrina:BAAANQAECgQIBAAAAA==.',
Az='Azylrog:BAAANQADCgQICwAAAA==.',
Ba='Babymiko:BAAANQADCgQIBQAAAA==.Babypeech:BAAANQADCgUIBQAAAA==.Bakulu:BAAANQAECgEIAQAAAA==.Bantoou:BAAANQAECgEIAQAAAA==.Bathoryz:BAAANQAECgcIDAAAAA==.Battlescars:BAAANQADCgYIDgAAAA==.Bauhaus:BAAANQADCgUICQAAAA==.Bauld:BAAANQAECgIIAgAAAA==.',
Be='Beardybear:BAAANQAECgQIBgAAAA==.Bearface:BAAANQADCgYIBgAAAA==.Bearicaide:BAAANQAECgQIBQAAAA==.Beautiful:BAAANQADCgYIBgAAAA==.Beefygee:BAAANQADCgMIAwAAAA==.Belldrak:BAAANQADCgUIBQAAAA==.Belldren:BAAANQADCgUIBQAAAA==.Belldrin:BAAANQADCggIDwAAAA==.Bepaulie:BAAANQADCgIIAgABNQAECgUICAABAAAAAA==.Bergidum:BAAANQADCgcIDAAAAA==.Beriamilbinc:BAAANQADCgYICAAAAA==.',
Bh='Bhucket:BAAANQADCgEIAQAAAA==.',
Bi='Bignagos:BAAANQADCgYICgAAAA==.Bigolboi:BAAANQAECgEIAQAAAA==.Bigthickheal:BAAANQADCgEIAQAAAA==.',
Bl='Blackk:BAAANQAECgcIEgAAAA==.Blackxcoffee:BAAANQADCgIIAgAAAA==.Bladesong:BAAANQAECgEIAQAAAA==.Blood:BAAANQAECgYICAAAAA==.Blorglock:BAABNQAECoEcAAMDAAkJjhzIEwDDAgADAAgJBxzIEwDDAgAEAAQJhxl/HgBHAQAAAA==.Blorgonp:BAAANQADCgYIBgABNQAECgkJHAADAI4cAA==.Blorgonw:BAAANQAECgQIBAABNQAECgkJHAADAI4cAA==.Blowaegis:BAAANQAFFAEIAQAAAA==.Blownoutshax:BAAANQADCgEIAQAAAA==.Bluntnfortys:BAAANQADCgYICwAAAA==.Blupenguiny:BAAANQAECgYIDgAAAA==.',
Bm='Bmfsleeps:BAAANQADCgUICAAAAA==.',
Bn='Bnortwarrior:BAAANQAECgQIBQABNQAECgEIAQABAAAAAA==.',
Bo='Boanz:BAAANQAECgEIAQAAAA==.Bobasaurus:BAAANQAECgUIDgAAAA==.Bombastik:BAAANQAECgEIAQAAAA==.Booperry:BAAANQADCggICAAAAA==.Bosskün:BAAANQADCgMIAwAAAA==.Bountie:BAAANQAECgYICgAAAA==.Bountiè:BAAANQADCgEIAQABNQAECgYICgABAAAAAA==.Boyoyong:BAAANQADCgQIBAAAAA==.',
Br='Brainmatter:BAAANQADCgUIBQAAAA==.Brandedsoul:BAAANQADCgIIAgAAAA==.Brewztler:BAAANQADCgYIEAAAAA==.Brightscale:BAAANQADCggIDgAAAA==.Broham:BAAANQAECgEIAQAAAA==.Bromeheal:BAAANQADCgIIAgAAAA==.Bronik:BAAANQAECgQICAAAAA==.',
Bu='Buffmage:BAAANQAECgUIDQAAAA==.Bullman:BAAANQAECgQIBgABNQAECggIFwAFAJobAA==.Bullrûsh:BAAANQAECgYICQAAAA==.Bullviper:BAAANQADCgYIDwAAAA==.',
['Bè']='Bèrsèrk:BAAANQADCgcIBwABNQAECgcIEgABAAAAAA==.',
['Bì']='Bìgdaddy:BAAANQADCgYICwAAAA==.',
['Bø']='Bønestørm:BAAANQAECgcIEgAAAA==.',
['Bù']='Bùndee:BAAANQAECgQIBQAAAA==.',
Ca='Cabbâge:BAAANQADCgEIAQAAAA==.Cacapants:BAAANQADCgQIBAAAAA==.Cadencegs:BAAANQAECgMIAwAAAA==.Caliex:BAAANQAECgQIBAAAAA==.Califax:BAAANQAECgcIEgAAAA==.Caller:BAAANQADCgIIAgAAAA==.Callsignwiz:BAAANQAECgEIAQABNQAECgQIBwABAAAAAA==.Cannedbeans:BAAANQADCgMIAwAAAA==.Canuckcow:BAAANQADCgMIAwAAAA==.Captantrips:BAAANQADCgcIDgAAAA==.Carltonswag:BAAANQADCgcIBwAAAA==.Catazhanir:BAAANQADCggIEgAAAA==.Catclown:BAAANQAECgYIDgAAAA==.Cavonesee:BAAANQADCgcICAAAAA==.Caylaramose:BAAANQADCggICAAAAA==.Cazsandra:BAAANQAECgcIDAAAAA==.',
Cc='Ccs:BAAANQADCgYIEwAAAA==.',
Ch='Chadsoss:BAAANQADCgYIBgAAAA==.Chamlio:BAAANQADCgYIEAAAAA==.Channis:BAAANQADCgQIAwAAAA==.Chenaccles:BAAANQADCgQIBAAAAA==.Chickenrally:BAAANQAECgQIDQAAAA==.Chinobear:BAAANQADCgYIEQAAAA==.Chixilog:BAAANQADCgQIBAAAAA==.Chodyboy:BAAANQABCgYIBgAAAA==.Cholmondeley:BAAANQADCgIIAgAAAA==.Chuchix:BAABNQAECoEaAAMGAAkJWxogFgCkAgAGAAgJURsgFgCkAgAHAAIJrAKeOwBIAAAAAA==.Chuckler:BAAANQABCgYIDQAAAA==.',
Cl='Cladtu:BAAANQAECgIIAgAAAA==.Cleiah:BAAANQADCgUIBQAAAA==.Cloudfisto:BAAANQADCggIDQAAAA==.',
Co='Colacolaz:BAABNQAECoEdAAMDAAkJnyXXBQBPAwADAAgJ2CTXBQBPAwAEAAYJuSMsCABVAgAAAA==.Colasham:BAAANQAECgYICAABNQAECgkJHQADAJ8lAA==.Coldhands:BAAANQADCgEIAQABNQAECgUIDQABAAAAAA==.Colombiano:BAAANQAECgQIBAABNQAECgQICwABAAAAAA==.Coltoff:BAABNQAECoEeAAMIAAkJKBZoGgBzAgAIAAkJKBZoGgBzAgAJAAEJIAF7HQAfAAAAAA==.Conker:BAAANQADCgUIBQAAAA==.Coprates:BAAANQAECgIIAgAAAA==.Corgiquester:BAAANQAECgEIAQAAAA==.Corpserot:BAAANQADCgEIAQAAAA==.Corsin:BAAANQADCgQIBQAAAA==.Cowbustion:BAAANQAECgMICQAAAA==.',
Cp='Cptxcrunch:BAAANQADCgUIBgAAAA==.',
Cr='Cracken:BAAANQADCggICgABNQAECgYIDQABAAAAAA==.Crankshot:BAAANQADCgYICgABNQAECgMIAwABAAAAAA==.Crimsonrayne:BAAANQAECgQIBQAAAA==.Crusherlol:BAAANQAECgMIBQAAAA==.Crusherlul:BAAANQADCgYIEAABNQAECgMIBQABAAAAAA==.',
Cu='Curfew:BAAANQAECgYICwAAAA==.',
['Cà']='Càt:BAAANQADCgEIAQAAAA==.',
Da='Dabigoldk:BAAANQAECgUIBQAAAA==.Dahlya:BAAANQADCgEIAQABNQADCggICQABAAAAAA==.Dannzig:BAAANQADCgIIAgAAAA==.Daragon:BAAANQADCgEIAQABNQAECgcIDQABAAAAAA==.Darkravèn:BAAANQAECgQICgAAAA==.Darthkitsune:BAAANQAECgMIAwAAAA==.Datbubblelol:BAAANQAECgQIAwAAAA==.Datchick:BAAANQADCgcIFQAAAA==.Dawnkeeper:BAAANQADCgIIAgAAAA==.Dawnlily:BAAANQABCgcICwAAAA==.Daxy:BAAANQADCgIIAgAAAA==.Daymandeuces:BAAANQAECggIAwAAAA==.Dazbek:BAABNQAECoEfAAIKAAkJBB7PJwDyAgAKAAkJBB7PJwDyAgAAAA==.',
De='Decày:BAAANQADCgUIBgABNQAECgYIEQABAAAAAA==.Deepdutch:BAAANQAECgQICQAAAA==.Deezzeezz:BAAANQAECgUICQABNQAECggIEwABAAAAAA==.Degeneffe:BAAANQAECgEIAQAAAA==.Demoreknight:BAAANQAECgcIEAAAAA==.Devilboy:BAAANQAECgUIDQAAAA==.Dextrey:BAAANQADCggICAABNQAECgUICgABAAAAAA==.',
Di='Dialuptacos:BAAANQABCgYIBgAAAA==.Diddycombs:BAAANQADCgYIBgAAAA==.Discbrown:BAABNQAECoEeAAMLAAkJfR7bBgAuAwALAAkJfR7bBgAuAwAIAAEJeQKHiAA7AAAAAA==.Discmemommy:BAAANQAECgQIBAABNQAECgYIEQABAAAAAA==.Discontent:BAAANQADCggIEQAAAA==.Divinesmoke:BAAANQADCgUIBQAAAA==.',
Dj='Djblink:BAAANQADCgIIAgABNQAECgIIAwABAAAAAA==.',
Dk='Dkgaming:BAAANQAECgIIAwAAAA==.',
Do='Dogeared:BAAANQAECgQICQAAAA==.Domore:BAAANQAECgYIBgAAAA==.Donniedrako:BAAANQADCgQIBAAAAA==.Donson:BAAANQAECgcIEwAAAA==.Donsun:BAAANQADCgUIBQAAAA==.Doodlebobb:BAAANQAECgEIAQAAAA==.Doomlakalaka:BAAANQADCgUIEwAAAA==.Dorgh:BAAANQADCgIIAgAAAA==.Doskya:BAAANQADCgQIBAAAAA==.Doubleclap:BAAANQADCggIEwAAAA==.',
Dp='Dpzofdoom:BAAANQAECgEIAQAAAA==.',
Dr='Dracthwnd:BAABNQAECoEcAAMMAAkJNh9dAgDAAgAMAAkJjx5dAgDAAgANAAgJNRxOCQByAgAAAA==.Dragbrown:BAAANQADCgYIBgAAAA==.Dragonsins:BAABNQAECoEYAAIDAAkJWSHXAwBwAwADAAkJWSHXAwBwAwAAAA==.Drahron:BAAANQADCggIAgAAAA==.Drdiksmasher:BAAANQAECgIIAwAAAA==.Drekka:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Drogmax:BAAANQAECgMIAwAAAA==.Droptopp:BAAANQAECgQICQAAAA==.Drusys:BAAANQAECgIIAgAAAA==.Dryrod:BAAANQABCgYIBwAAAA==.',
Du='Duckelf:BAAANQAECgYIEAAAAA==.Dunranger:BAAANQAECgEIAQAAAA==.Durrga:BAAANQAFFAEIAQAAAA==.',
['Dã']='Dãftmõnk:BAAANQAECgUIBgAAAA==.',
Ed='Edgecrusherr:BAAANQAECgMIAwAAAA==.',
Eg='Egwenalmere:BAAANQADCgcIFwAAAA==.',
El='Elainia:BAAANQADCgYIDgAAAA==.Elisaveta:BAAANQADCgcICgAAAA==.Elliaa:BAAANQADCgcIEQAAAA==.Elliard:BAAANQADCgUICAAAAA==.Elodi:BAAANQADCgYIBgAAAA==.',
Em='Emanx:BAAANQABCgIIAgABNQAECgUICAABAAAAAA==.Embér:BAAANQAECggIAQAAAA==.',
En='Enheduanna:BAAANQADCgUICAAAAA==.',
Eo='Eowyen:BAAANQADCgUIBQAAAA==.',
Ep='Epiiphany:BAAANQADCgYIBwAAAA==.',
Er='Erydius:BAAANQAECgEIAQAAAA==.',
Es='Esdeath:BAAANQABCgIIAgAAAA==.',
['Eì']='Eìrì:BAAANQAECgEIAQAAAA==.',
['Eô']='Eôwyn:BAAANQADCgYIDQAAAA==.',
Fa='Faclion:BAAANQAECgUICQAAAA==.Faketurkey:BAAANQAECgIIAgAAAA==.Falkhor:BAAANQADCggICAAAAA==.Fari:BAAANQADCggIEwAAAA==.Farstryder:BAAANQADCgYIBgAAAA==.Fatlootz:BAAANQAECgYIEQAAAA==.',
Fe='Fellwarden:BAAANQADCgMIAwAAAA==.Feltyah:BAAANQADCgUIEgAAAA==.',
Fi='Finnajuggyou:BAAANQAECgIIAgAAAA==.Finniker:BAAANQAECgIIAgAAAA==.Fiorina:BAAANQAECgQICgAAAA==.Firefóx:BAAANQADCggICAAAAA==.Fishnet:BAAANQAECgIIAgAAAA==.Fishthicc:BAAANQADCgYIEAAAAA==.',
Fl='Flashnikko:BAAANQADCgIIAgAAAA==.Flexkin:BAAANQAECgUIDQAAAA==.',
Fo='Foe:BAABNQAECoEYAAMIAAkJzhyQFACiAgAIAAkJzhyQFACiAgAJAAEJahYCGQA3AAAAAA==.Fornor:BAABNQAECoEXAAIFAAgJmhtQFQChAgAFAAgJmhtQFQChAgAAAA==.Foxfù:BAAANQADCgYIDAAAAA==.Foxkníght:BAABNQAECoEaAAIFAAkJWSLiBACGAwAFAAkJWSLiBACGAwAAAA==.Foxxalot:BAAANQADCgQIBAAAAA==.Foxxpachi:BAAANQADCggIGgAAAA==.',
Fr='Franký:BAAANQADCgUIBgAAAA==.Frogus:BAAANQAECgUICgAAAA==.',
Fu='Fungbuck:BAAANQADCgQIBAAAAA==.Fungbucko:BAAANQABCgQIBAAAAA==.Fuule:BAAANQADCggIGwAAAA==.Fuusei:BAAANQAECgQIBgAAAA==.',
Fy='Fyrdrakon:BAAANQAECgUICgAAAA==.',
Ga='Gabeitch:BAAANQADCgMIAwAAAA==.Galapagós:BAAANQADCgQIBwABNQADCgUIBQABAAAAAA==.Galaxus:BAABNQAECoEbAAIOAAkJehl+CwDiAgAOAAkJehl+CwDiAgAAAA==.Gammastorm:BAAANQAECgYICgAAAA==.',
Gh='Ghall:BAAANQADCgIIAgAAAA==.Ghrell:BAEANQAECgUICQAAAA==.',
Gi='Gickygackers:BAAANQADCgYIDgAAAA==.Gigglepeak:BAAANQAECgIIAgAAAA==.Girlhands:BAAANQADCgIIAgAAAA==.',
Gl='Glekimage:BAAANQAECgMIAwAAAA==.',
Go='Goatmylk:BAAANQADCgYIDQAAAA==.Gobblr:BAAANQADCgMIBAAAAA==.Goldensorbet:BAAANQADCgYIBgAAAA==.Golokis:BAAANQADCggICAABNQAECgcIDwABAAAAAA==.Gonuhreeuh:BAAANQAECgQIBAABNQAECgUIEwABAAAAAA==.Gotz:BAAANQADCggIDgAAAA==.',
Gr='Grattick:BAAANQAECgEIAQAAAA==.Greenlightt:BAAANQADCgYIEAAAAA==.Greenxll:BAAANQAECgYIEgAAAA==.Greypa:BAAANQAECgIIAgAAAA==.Grezulock:BAEANQAECgIIAwAAAA==.Griggles:BAAANQAECgQICAAAAA==.Grikol:BAAANQADCgIIAgAAAA==.Grizzbane:BAAANQADCgEIAQAAAA==.Grolk:BAAANQADCggIEwAAAA==.',
Gu='Guerita:BAAANQADCgUIBQAAAA==.Gumptruck:BAAANQAECgUICwAAAA==.',
Gw='Gwenevere:BAAANQADCgMIAwAAAA==.',
Ha='Habibii:BAAANQADCgQIBAAAAA==.Hardendaire:BAAANQADCgQIBwAAAA==.Hashypally:BAAANQAECgQIBAAAAA==.Hathern:BAAANQADCgIIAgAAAA==.Hawkmees:BAAANQAECgUIDQAAAA==.Hazbretzul:BAAANQAECgYICgAAAA==.',
He='Heelza:BAAANQADCgUICAAAAA==.Hellskitchën:BAAANQADCgQIBQAAAA==.Help:BAAANQAECgQIBAAAAA==.Hephs:BAAANQADCgYIDQABNQAECgQICAABAAAAAA==.Hermionejean:BAAANQADCgUIBQAAAA==.Hexuz:BAAANQAECgQIBAAAAA==.',
Hi='Hipster:BAAANQAECgIIAwABNQABCgIIAgABAAAAAA==.',
Ho='Holeekow:BAAANQADCgEIAgAAAA==.Hollymollie:BAAANQADCggIDAAAAA==.Holoey:BAAANQABCgIIAgAAAA==.Holymobeus:BAAANQADCgcIBwAAAA==.Holypower:BAAANQADCgYICQAAAA==.Holythot:BAAANQAECgYIEAAAAA==.Hoofanhammer:BAAANQADCgEIAQAAAA==.Hozrozlok:BAAANQAECgUIDAAAAA==.',
Hu='Hufgar:BAAANQADCgUICwAAAA==.Huntdry:BAAANQAECgQIBwAAAA==.Hurkoh:BAAANQAECgQIBAAAAA==.Hushpuppié:BAAANQAECgMIBQAAAA==.',
Hy='Hypereon:BAAANQAECgYICgAAAA==.',
Ic='Iceden:BAAANQAECgIIAgAAAA==.Icyweenor:BAAANQAECgIIAgAAAA==.',
Id='Idkdude:BAAANQAECgQICAAAAA==.',
Ie='Ielarth:BAAANQADCgEIAQAAAA==.',
If='Ifhediehedie:BAAANQADCgcIBwAAAA==.',
Il='Illadarina:BAAANQAECgYIDQAAAA==.Illí:BAAANQADCgYIBgAAAA==.',
In='Incetardis:BAAANQADCgYIEwAAAA==.',
Ir='Iradoria:BAAANQAECgcIEgAAAA==.',
Is='Isoldè:BAAANQADCgcIBwAAAA==.Istabu:BAAANQAECgEIAQAAAA==.',
It='Itachi:BAACNQAFFIELAAMFAAYJ/xbEAADJAQAFAAUJRBfEAADJAQAPAAIJSRLcBACoAAA1AAQKgSAAAwUACQlRJoEBANQDAAUACQncJYEBANQDAA8ABgnNJd8LAJcCAAAA.Itamï:BAAANQAECgUIDQAAAA==.',
Iv='Ivannacream:BAAANQADCggICAAAAA==.',
Ja='Jaagren:BAAANQADCgYIBgAAAA==.Jadawin:BAAANQAECgYIBwAAAA==.Jaketta:BAAANQAECgEIAQAAAA==.Jaquemehof:BAAANQADCgYIBgAAAA==.Jasnah:BAABNQAECoEXAAIKAAkJqg9xTwBeAgAKAAkJqg9xTwBeAgAAAA==.Jayrel:BAABNQAECoEaAAMJAAkJdRWyBADzAQAIAAkJhRH7IABEAgAJAAgJaxCyBADzAQAAAA==.',
Je='Jerrik:BAAANQAECgQIBwAAAA==.',
Jo='Joeyexotic:BAAANQAECgIIAgAAAA==.Jokem:BAAANQADCgUIBQAAAA==.',
Ju='Juankkii:BAAANQADCggICgABNQAECgIIAwABAAAAAA==.Juggerbear:BAAANQADCgYIDgAAAA==.Juiçy:BAAANQADCggIDgAAAA==.Juls:BAAANQAECgQICAAAAA==.Justhetip:BAAANQADCgEIAQAAAA==.',
['Jä']='Jäger:BAAANQAECgQIBQAAAA==.',
Ka='Kagama:BAAANQAECgQIBQAAAA==.Kalatabi:BAAANQADCggICAABNQAECgYIDwABAAAAAA==.Kalatai:BAAANQAECgYIDwAAAA==.Kamisenshi:BAAANQADCgIIAgAAAA==.Karayna:BAAANQAECgEIAQAAAA==.Kareemcheese:BAAANQAECgQIBQAAAA==.Kauko:BAAANQAECgQIBwAAAA==.',
Ke='Kellanash:BAAANQADCgQIBAAAAA==.Kezwik:BAAANQAECgUICAAAAA==.',
Kh='Khaotick:BAAANQADCgYIEAAAAA==.Kheetz:BAAANQAECgEIAgAAAA==.',
Ki='Kikomo:BAAANQAECgEIAQAAAA==.Kikosho:BAAANQAECgIIBAAAAA==.Kilaaj:BAAANQADCgIIAgAAAA==.Killerbane:BAAANQADCgcIEAAAAA==.Kinclakis:BAAANQADCgQIBAAAAA==.Kinthor:BAAANQABCgIIAgAAAA==.Kirrin:BAAANQAECgYICwAAAA==.',
Kn='Kneecap:BAAANQAECgYICgAAAA==.Kneepad:BAAANQADCgcIBwAAAA==.Knetikara:BAAANQAECgYIEQAAAA==.',
Ko='Kokokrantz:BAAANQAECgMIAwAAAA==.Korthix:BAAANQAECgUICgAAAA==.Kosi:BAAANQAECgIIAQAAAA==.',
Kr='Kraanan:BAAANQADCgUIBQAAAA==.Kreiedril:BAAANQADCgcIFAAAAA==.Krispytoo:BAAANQAECgYICwAAAA==.',
Ku='Kulltena:BAAANQADCggICAAAAA==.Kulltina:BAAANQADCggICAAAAA==.',
Ky='Kyokaii:BAAANQAECgMIAwAAAA==.Kyrasala:BAAANQADCgIIAgAAAA==.',
La='Laarken:BAAANQADCggIEQAAAA==.Lacedtotems:BAAANQAFFAEIAQAAAA==.Lagexe:BAAANQADCggIEQAAAA==.Laybia:BAAANQADCgEIAQAAAA==.Lazlo:BAAANQAECgQIAwAAAA==.',
Le='Lenrela:BAAANQAECgUIBwAAAA==.Lestealth:BAAANQAECgIIAwAAAA==.Letena:BAAANQAECgcIEQAAAA==.Levyymage:BAAANQAECgEIAgAAAA==.',
Li='Lialyndra:BAAANQADCgYICgAAAA==.Licelia:BAAANQAECgYIEAAAAA==.Lilballohate:BAAANQADCgEIAQAAAA==.Liligayle:BAAANQADCgMIAwAAAA==.Linane:BAAANQAECgQIDwAAAA==.Lite:BAAANQADCggICQABNQAECgYIEAABAAAAAA==.Liveevil:BAAANQAFFAEIAQAAAA==.',
Ll='Llama:BAAANQADCgYIBgAAAA==.',
Lo='Loathsome:BAAANQADCgEIAQABNQAECgQIBwABAAAAAA==.Lolmagician:BAAANQABCgIIAgAAAA==.Loquail:BAAANQADCgUIBQAAAA==.Lorike:BAAANQAECggIAgAAAA==.Losthobo:BAAANQADCgEIAQAAAA==.',
Lu='Lucifoor:BAAANQADCgUIDQAAAA==.Luftim:BAAANQAECgEIAQAAAA==.Lunastellara:BAAANQADCgYIBgAAAA==.Lunoxx:BAAANQADCgUICAAAAA==.Lurang:BAAANQAECgIIAgAAAA==.',
Ma='Macacbre:BAAANQADCgYICQAAAA==.Macdotnalds:BAAANQADCgMIAwAAAA==.Madetolock:BAAANQADCgYICgAAAA==.Maerlyna:BAAANQABCgEIAQAAAA==.Magebrew:BAAANQADCgYIBwAAAA==.Mageycat:BAAANQADCgYICAABNQAECgYIDgABAAAAAA==.Magicma:BAAANQAECgQIBAABNQAECgQIBgABAAAAAA==.Mahlah:BAAANQABCgIIBAAAAA==.Makarov:BAAANQADCgEIAQAAAA==.Malevir:BAAANQABCgUIBQAAAA==.Maliun:BAAANQAECgQIBQAAAA==.Malusdemon:BAAANQADCggIGQAAAA==.Mamasota:BAAANQADCgcIDQAAAA==.Marisol:BAAANQADCgUIDQAAAA==.Markfunk:BAAANQAECgcIEgAAAA==.Markiepoo:BAAANQADCgcIBwABNQAECgcIEgABAAAAAA==.Markyboom:BAAANQADCgIIAgABNQAECgcIEgABAAAAAA==.Markykong:BAAANQADCgYIBwABNQAECgcIEgABAAAAAA==.Maryjaiyne:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Mawmatz:BAAANQADCgEIAQAAAA==.',
Me='Mebashum:BAAANQAECgYIBAAAAA==.Medihunter:BAAANQADCgIIAgABNQAECgQIBwABAAAAAA==.Meditations:BAAANQAECgQIBwAAAA==.Meleath:BAAANQADCgEIAQAAAA==.Melibeth:BAAANQABCgEIAQAAAA==.Metrakatanke:BAAANQADCgQIBAAAAA==.Mexiflip:BAAANQADCgYICQAAAA==.',
Mi='Midoriya:BAAANQAECgEIAQAAAA==.Milgan:BAAANQAECgcIEQAAAA==.Minimochi:BAABNQAECoElAAIIAAkJog0GLAD/AQAIAAkJog0GLAD/AQAAAA==.Missblackk:BAAANQADCgIIAgAAAA==.Mithyr:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.',
Mn='Mneme:BAABNQAECoEeAAIHAAkJQiQbAQCfAwAHAAkJQiQbAQCfAwAAAA==.',
Mo='Monkeypiglet:BAABNQAECoERAAIQAAcJ9hrSOQBRAgAQAAcJ9hrSOQBRAgAAAA==.Moogpal:BAAANQAECgIIAgABNQAECgQIBgABAAAAAA==.Moogul:BAAANQAECgQIBgAAAA==.Moovoe:BAAANQAECgIIAgAAAA==.Morcarth:BAAANQAECgQIBQAAAA==.Mortal:BAAANQADCgEIAQAAAA==.Morts:BAAANQADCgYIBgAAAA==.',
Mu='Mulks:BAAANQAECgYIEQAAAA==.Multiblox:BAAANQAECgUIDQAAAA==.Murgruuk:BAAANQADCggICAAAAA==.',
My='Myling:BAAANQADCggIAgAAAA==.',
['Mà']='Màrkham:BAAANQABCgYIBwAAAA==.',
['Må']='Måjïñßûüü:BAAANQADCgIIAgAAAA==.',
Na='Naam:BAAANQAECgQICAAAAA==.Nadrin:BAAANQADCgYIFQAAAA==.Naedora:BAAANQAECgQICQAAAA==.Namixx:BAAANQAECgYIDwAAAA==.Naruwnd:BAAANQADCggICAABNQAECgkJHAAMADYfAA==.Nathaanis:BAABNQAECoEZAAICAAgJsRncMABFAgACAAgJsRncMABFAgAAAA==.',
Ne='Necrodamus:BAAANQAECgEIAQAAAA==.Neliera:BAAANQABCgUIBQAAAA==.Neonseal:BAAANQADCggICAAAAA==.Neopolitangs:BAAANQAECgMIBAAAAA==.Nevs:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Nevsy:BAAANQADCgYICAAAAA==.Nezdispenser:BAAANQAECgEIAQAAAA==.',
Ni='Niduash:BAAANQADCgMIAwAAAA==.Nightchill:BAAANQAECgUICQAAAA==.Nimbletoes:BAAANQAECgUICwAAAA==.Ninabudhu:BAAANQADCggICAAAAA==.Nirza:BAAANQADCggIFQAAAA==.Niziel:BAAANQAECgcIEQAAAA==.',
No='Nofurrys:BAAANQADCggICQAAAA==.Nokorin:BAAANQAECgEIAgAAAA==.Nolo:BAAANQADCgUIBQABNQAECgkJGwARAAIhAA==.Noros:BAABNQAECoEbAAIRAAkJAiFTAgB2AwARAAkJAiFTAgB2AwAAAA==.',
Nu='Nuggalicious:BAAANQAECgEIAQAAAA==.Nursjoy:BAAANQADCggICAAAAA==.',
Ok='Oko:BAAANQAECgQIBAAAAA==.',
Ol='Oldmanpeanut:BAAANQADCggICAABNQAECgIIAwABAAAAAA==.',
Om='Omenwar:BAAANQADCggIGAAAAA==.Omni:BAAANQADCggICwAAAA==.',
Or='Orelia:BAAANQAECgMIAwAAAA==.Orfnanu:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Ornarl:BAAANQAECgMIBgAAAA==.',
Ot='Ottawa:BAAANQADCgYIBgAAAA==.',
Ox='Oxsana:BAAANQAECgUIBQAAAA==.',
Pa='Packtastic:BAAANQAECgQICQAAAA==.Padthang:BAAANQAECgUICQAAAA==.Pakipot:BAAANQAECgIIAgAAAA==.Palazyn:BAAANQADCggIEAABNQAECgYIDQABAAAAAA==.Pallymar:BAAANQADCggICAABNQAECgkJFgASAIckAA==.Panhexual:BAAANQADCgQIBAAAAA==.Parketor:BAAANQAECgIIAgAAAA==.Pathyx:BAAANQAECgIIAgAAAA==.',
Pe='Peacefulguy:BAAANQABCgQIBgAAAA==.Peachjars:BAAANQAECgcIEwAAAA==.Pelvis:BAAANQADCgQIBAABNQADCggICwABAAAAAA==.Perixi:BAAANQADCgYICgAAAA==.Perpekto:BAAANQADCgUIBQAAAA==.Peterpewpew:BAAANQADCggICwAAAA==.',
Ph='Phedragon:BAAANQADCgIIAgAAAA==.Phedrah:BAAANQAECgUICgAAAA==.Philipx:BAAANQADCgQIBAAAAA==.',
Pi='Picklenator:BAAANQADCggIHgAAAA==.Pierreplays:BAAANQADCgUIBQAAAA==.Pillowhands:BAAANQADCgQIBAAAAA==.Pilto:BAAANQAECgMIBQAAAA==.Pingo:BAAANQAECgEIAQAAAA==.Pinkmj:BAAANQADCgMIBgAAAA==.Pitchief:BAAANQAECgEIAQAAAA==.',
Po='Polendina:BAAANQAECgcIEgAAAA==.Pooginator:BAAANQADCgYICAAAAA==.Porcelinà:BAAANQAECgMIAwABNQAECgYIDgABAAAAAA==.',
Pr='Prada:BAAANQAECgEIAQAAAA==.Premmish:BAAANQADCggICAAAAA==.Primeork:BAAANQADCgUIBQAAAA==.Prometheuss:BAAANQADCgQIBAAAAA==.',
Ps='Psammophile:BAAANQAECgcIEgAAAA==.Psymmer:BAAANQADCgYICAABNQAECgIIAgABAAAAAA==.Psynge:BAAANQADCgYICgABNQAECgIIAgABAAAAAA==.Psynnergy:BAAANQAECgIIAgAAAA==.Psytellar:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.',
Pt='Ptsd:BAAANQAECgEIAQAAAA==.',
Pu='Pumprstltskn:BAAANQAECgQIBgAAAA==.Puppyflower:BAAANQADCgYIBQAAAA==.Purplepally:BAAANQADCgEIAQAAAA==.Purpleshroom:BAAANQADCgQIBAABNQADCggICwABAAAAAA==.Put:BAAANQADCgYIDwAAAA==.',
Py='Pyrat:BAAANQAECgEIAQAAAA==.Pyroangel:BAAANQAECgEIAQAAAA==.Pyrotwopnto:BAAANQADCgYIEgAAAA==.',
['Pí']='Píneapple:BAAANQAECgIIAwAAAA==.',
Qe='Qertinya:BAAANQADCgYIEQAAAA==.',
Qu='Quadman:BAAANQAECgcIEgAAAA==.Quaxly:BAAANQADCgQIBAAAAA==.Quinexorable:BAABNQAECoEaAAITAAkJPCFUAQB2AwATAAkJPCFUAQB2AwAAAA==.',
Ra='Ragedaddy:BAAANQAECgcIDwAAAA==.Rahkar:BAAANQAECgQICAAAAA==.Rainndance:BAAANQAECgMIBwAAAA==.Raitan:BAAANQADCgQICwAAAA==.Rallet:BAAANQADCgIIAgAAAA==.Ramrodveazy:BAAANQAECgIIBAAAAA==.Ranaklos:BAAANQADCgQIBAABNQADCgIIAgABAAAAAA==.Rancimus:BAAANQAECgQICAAAAA==.Rangore:BAAANQADCgQIBAAAAA==.Ranocthan:BAAANQAECgEIAQAAAA==.Rarcher:BAAANQAECgUIBgAAAA==.Rasmuz:BAAANQADCgYICgAAAA==.Rauthar:BAAANQAECgQICAAAAA==.Rayyven:BAAANQADCgQIBAAAAA==.Razorken:BAAANQADCgYIBgAAAA==.Razorsharp:BAAANQAECgcIDAAAAA==.',
Re='Recon:BAABNQAECoEbAAMMAAgJEQ2/BQC3AQAMAAgJEQ2/BQC3AQANAAQJoQIhIQCJAAAAAA==.Reefermadnes:BAAANQAECgYIEAAAAA==.Reelsteel:BAAANQADCgYIDgAAAA==.Relnamah:BAAANQADCgUICwAAAA==.Reoloc:BAEANQADCgYICQABNQAECgYIDAABAAAAAA==.Retandspank:BAAANQABCgQIBAAAAA==.Revdev:BAABNQAECoEuAAICAAkJqxd+JwB4AgACAAkJqxd+JwB4AgAAAA==.Revoke:BAAANQADCgEIAQABNQAECgQIBwABAAAAAA==.Rezowulf:BAAANQAECgYIAgAAAA==.',
Rh='Rhapsydee:BAAANQADCgUIBQAAAA==.Rhododendron:BAAANQADCgcIBwAAAA==.Rhoñin:BAAANQABCgEIAQAAAA==.Rhuney:BAAANQAECgYICAAAAA==.Rhunie:BAAANQADCgcIBwABNQAECgYICAABAAAAAA==.Rhyllii:BAAANQAECgQIBAAAAA==.',
Ri='Riftmaker:BAAANQABCgIIAgAAAA==.Rivermage:BAAANQABCgIIAgAAAA==.',
Ro='Roadburner:BAAANQAECggICQAAAA==.Roccotaco:BAAANQADCgYICgAAAA==.Romenhoff:BAAANQAECgcIDwAAAA==.Rootbeer:BAAANQAECgEIAQABNQADCgYIBgABAAAAAA==.Roshambu:BAAANQAECgEIAQAAAA==.Roxinator:BAAANQAECgQIBAAAAA==.Roxorath:BAAANQADCgQIBAAAAA==.Roxyrocko:BAAANQADCgcIBwAAAA==.',
Ru='Ruikiea:BAAANQAECgIIAwABNQAECgcIHgAUAP0UAA==.',
Ry='Ryomage:BAAANQABCgMIAwAAAA==.',
['Rà']='Ràggà:BAAANQAECgQIBAAAAA==.',
['Rí']='Rían:BAAANQADCgcIFQAAAA==.',
Sa='Sacerdota:BAAANQADCgQIBAAAAA==.Saelenei:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.Saevra:BAAANQADCgMIAwAAAA==.Sairadoka:BAAANQAECgIIAgAAAA==.Samzori:BAAANQAECgQIBgAAAA==.Sanatizer:BAAANQAECgYICwAAAA==.Sandret:BAAANQAECgQIBQAAAA==.Sarris:BAAANQAECgUIBQAAAA==.Sathriel:BAAANQAECgYIDwAAAA==.Savagetotemz:BAAANQAECgcIEQAAAA==.',
Sc='Scalelujah:BAAANQAECgMIAwABNQADCgYIBgABAAAAAA==.Scottadin:BAAANQAECgQICQAAAA==.',
Se='Seanasy:BAAANQABCgIIAgAAAA==.Seanx:BAAANQADCgUIBQAAAA==.Secondenvoy:BAAANQAECgQIBQAAAA==.Seerawh:BAAANQAECgYICgAAAA==.Sehetep:BAAANQAECgEIAQAAAA==.Sephyrea:BAAANQADCgYIBgAAAA==.Serigon:BAAANQADCgUIBQAAAA==.',
Sh='Shadownd:BAABNQAECoEZAAMIAAkJBSFqDwDRAgAIAAgJ/x9qDwDRAgAJAAMJJx3nDADiAAABNQAECgkJHAAMADYfAA==.Shadowsloth:BAAANQADCgYICQAAAA==.Shahli:BAAANQADCgIIAgAAAA==.Shakiro:BAAANQAECgQICwAAAA==.Shaloendril:BAAANQADCgUICgABNQAECggIGQACAPcYAA==.Shalzind:BAAANQADCgIIAgAAAA==.Shamchan:BAAANQAECgQIBAAAAA==.Shamergency:BAAANQADCgUICgAAAA==.Shammyrock:BAAANQAECgUICQAAAA==.Shamtony:BAAANQABCgQIBgAAAA==.Sharkk:BAAANQAECgEIAQAAAA==.Shaylar:BAAANQAECgIIAgAAAA==.Sheisunholy:BAAANQADCgIIAgAAAA==.Sherminator:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Shiherlis:BAAANQADCggICwAAAA==.Shmacken:BAAANQAECgYIDQAAAA==.Shockinglee:BAAANQAECgQIBQABNQAECgQIBwABAAAAAA==.Shosannaa:BAAANQAECgIIAgAAAA==.Shuriken:BAABNQAECoEcAAMVAAkJoCNUAgCZAwAVAAkJoCNUAgCZAwAWAAEJ6RWxxwA/AAAAAA==.',
Si='Siete:BAAANQADCggIFgAAAA==.Sikbubblez:BAAANQAECgUIDAAAAA==.Sikshockz:BAAANQADCggIEAAAAA==.Silentblades:BAAANQAECgIIAgAAAA==.Sindazia:BAAANQADCggIDgAAAA==.Sinistry:BAAANQADCgUIBgAAAA==.Siopau:BAAANQADCgQIBAAAAA==.Sixunder:BAAANQADCgcIBwAAAA==.',
Sk='Skrinkles:BAAANQAECgQIBAAAAA==.Skullwhisper:BAAANQAECgQIBwAAAA==.',
Sl='Slomar:BAAANQADCggIFwAAAA==.Slowar:BAAANQADCggICAAAAA==.Slowpallh:BAAANQADCgYICAABNQADCggICAABAAAAAA==.Slowrog:BAAANQADCgUIAwABNQADCggICAABAAAAAA==.Slowsh:BAAANQADCgUIBQABNQADCggICAABAAAAAA==.',
Sm='Smoggely:BAAANQAECgUICQAAAA==.Smoketotem:BAAANQAECgEIAQAAAA==.',
Sn='Sneakzalot:BAAANQADCgMIAwAAAA==.Snowbreeze:BAAANQAECgIIAgAAAA==.Snowfláme:BAAANQAECgUICAAAAA==.',
So='Solarity:BAAANQABCgUIBQAAAA==.Solfyr:BAAANQADCgYIBgABNQAECgUICgABAAAAAA==.Solie:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Solki:BAAANQADCgIIAgAAAA==.Solrak:BAAANQAECgIIAgAAAA==.Soobatai:BAAANQADCgYIBgAAAA==.Soot:BAAANQAECgYIBwAAAA==.Soots:BAAANQADCgUIBQAAAA==.Sootzy:BAAANQAECgQIBQABNQAFFAUICgAEAEYcAA==.Sophiane:BAAANQAECgEIAQAAAA==.Soulcaller:BAAANQADCggICAAAAA==.Soulkhan:BAAANQADCgUIBQAAAA==.Soulkrusher:BAAANQAECgIIAgAAAA==.',
Sp='Spadeii:BAAANQAECgYIDwAAAA==.Spadex:BAAANQADCggIEAABNQAECgYIDwABAAAAAA==.Spagheddy:BAAANQADCggIDQAAAA==.Spankky:BAAANQADCgYIBwAAAA==.Spellzy:BAAANQAECgUIEwAAAA==.Spicylatina:BAAANQADCgYIBgAAAA==.',
Sq='Squachy:BAAANQADCgYIBgABNQAECgkJGgAJAHUVAA==.',
Ss='Sseoyoon:BAAANQAECgIIAgAAAA==.Ssnneezzyy:BAAANQAECgQIBwAAAA==.',
St='Starwnd:BAAANQAECgUIBQABNQAECgkJHAAMADYfAA==.Steadchi:BAAANQAECgYICgAAAQ==.Stolibear:BAAANQAECgcIDQAAAA==.Stolidh:BAAANQAECgEIAQABNQAECgcIDQABAAAAAA==.Stolidk:BAAANQADCgUIBQABNQAECgcIDQABAAAAAA==.Stolip:BAAANQADCggICAABNQAECgcIDQABAAAAAA==.Stoneycrusty:BAAANQAECgYIEAAAAA==.Straywalker:BAAANQADCgEIAQAAAA==.Strongside:BAAANQAECgQIBAAAAA==.Stublimë:BAAANQAECgIIAgAAAA==.Studdie:BAAANQADCgYICQAAAA==.',
Su='Succeeds:BAAANQAECggICAAAAA==.Sungjinwooz:BAAANQAECgQIBgAAAA==.Suntitan:BAAANQADCgIIAgABNQAECgQIBgABAAAAAA==.Suuhdude:BAAANQAECgQICQABNQAECgYIDgABAAAAAA==.Suzue:BAAANQAECgEIAQAAAA==.',
Sw='Swd:BAAANQAECgUIBgAAAA==.Swiffty:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.Swudge:BAAANQAECgEIAQAAAA==.',
Sy='Syladeith:BAAANQAECgUICgAAAA==.Sylbanas:BAAANQADCgQICgABNQAECgIIAwABAAAAAA==.Syldrunk:BAAANQADCgcIDgAAAA==.Sylvashaman:BAAANQAECgMIBAAAAA==.',
['Sé']='Séii:BAAANQADCgYIBgAAAA==.',
['Sÿ']='Sÿdney:BAAANQADCggICwAAAA==.',
Ta='Tabarnaka:BAAANQAECgQIBgAAAA==.Tairnock:BAAANQAECgUIBQAAAA==.Takabaka:BAAANQADCgEIAQABNQADCgQIBAABAAAAAA==.Tankadina:BAAANQADCgEIAQAAAA==.Tanzee:BAABNQAECoEaAAMIAAkJbg7bJgAfAgAIAAkJbg7bJgAfAgALAAEJpAs6SgAuAAAAAA==.Tarmesan:BAABNQAECoEaAAINAAkJ4iCUAgBcAwANAAkJ4iCUAgBcAwAAAA==.Tastytooth:BAAANQAECgUIBwAAAA==.Taytaytyrone:BAAANQADCgEIAQAAAA==.',
Td='Tdog:BAAANQAECgUICQAAAA==.',
Te='Tegadin:BAAANQADCgYIEAAAAA==.Telemanus:BAAANQADCgUIBQAAAA==.Telhani:BAAANQAECgQIBAAAAA==.Tesse:BAAANQADCgMIAwAAAA==.',
Th='Thadude:BAAANQADCgcIBwABNQAECgYIEAABAAAAAA==.Thannos:BAAANQAECgcIEgAAAA==.Thanos:BAAANQADCgIIAgAAAA==.Thanozul:BAAANQAECgEIAQAAAA==.Thark:BAAANQAECgQIBwAAAA==.Thawnn:BAAANQADCgQIBQAAAA==.Theberos:BAAANQADCgYIBAAAAA==.Thebighoss:BAAANQADCgQIBAAAAA==.Thedùde:BAAANQADCgUIBQABNQAECgYIEAABAAAAAA==.Thelgrus:BAAANQADCgcIGAAAAA==.Thoern:BAAANQADCgYIBgAAAA==.Thorane:BAAANQADCgYIBgAAAA==.Thrashcan:BAAANQAECgQIBwAAAA==.Threem:BAAANQAECgEIAQAAAA==.Threepercent:BAAANQAECgcIDAAAAA==.Threesteps:BAAANQADCgIIAgAAAA==.Throad:BAAANQADCgUIAQAAAA==.Throatzilla:BAAANQABCgYIBgAAAA==.Throwbackhlz:BAAANQAECgIIAwAAAA==.Throwinshåde:BAAANQADCgcICgAAAA==.Thudmuffin:BAAANQAECgQICAABNQAECgQIBwABAAAAAA==.Thyrealest:BAAANQADCgEIAQAAAA==.Thysania:BAAANQABCgYICQABNQABCgIIAgABAAAAAA==.',
Ti='Tides:BAAANQAECgUIDAAAAA==.Tilyne:BAAANQABCgIIAgAAAA==.Tinarii:BAABNQAECoEZAAIXAAkJpiYyAAD4AwAXAAkJpiYyAAD4AwAAAA==.Tinyshadow:BAAANQADCggIEwAAAA==.Tinytit:BAAANQAECgQIBAAAAA==.Tinytusk:BAAANQABCgIIAgAAAA==.Titdruid:BAAANQADCgUIBQAAAA==.Titpoosy:BAAANQADCgYICQAAAA==.Tiusele:BAAANQABCgEIAQAAAA==.',
To='Tonystonk:BAAANQAECgEIAQAAAA==.Toombz:BAAANQADCgYIBgAAAA==.Totemkoff:BAAANQABCgMIAwAAAA==.',
Tr='Tragha:BAAANQADCgUIBwAAAA==.Trayker:BAAANQADCgQIBAAAAA==.Traynisa:BAAANQADCgUICAAAAA==.Treykor:BAAANQADCgQIBAAAAA==.Tria:BAAANQAECgEIAwAAAA==.Trixrforkids:BAAANQADCgYIBgAAAA==.Trlight:BAAANQAECgcICAAAAA==.Trollsicle:BAAANQAECgQIBwAAAA==.Trotah:BAAANQADCgYICQAAAA==.Tryzz:BAAANQAECgUICwAAAA==.',
Tu='Tubhead:BAAANQADCgYIFQAAAA==.Tunare:BAAANQAECgEIAQAAAA==.Tusknflamer:BAAANQADCgUIBwAAAA==.',
Tw='Twoman:BAAANQAECgUIBQABNQAECgcIEgABAAAAAA==.Twylla:BAAANQAECgUIBgAAAA==.',
Ty='Tynak:BAAANQADCgQIBAAAAA==.',
Ug='Ugroto:BAAANQAECggICAAAAA==.',
Ul='Uldred:BAAANQADCgUIBQABNQAECgcIEgABAAAAAA==.',
Un='Unclesnottyp:BAAANQAECgEIAwAAAA==.Unmortal:BAAANQAECgQIBwAAAA==.',
Ur='Urotherdaddy:BAAANQAECgEIAQAAAA==.Uruker:BAAANQADCgIIAgAAAA==.',
Us='Useurblinker:BAAANQADCgcIBwAAAA==.',
Va='Valglacius:BAAANQADCgYICwAAAA==.Valkrin:BAAANQADCgYIBgAAAA==.Valonthir:BAAANQADCgQICwAAAA==.Valstone:BAAANQADCgIIAgABNQADCgYICwABAAAAAA==.Vancleave:BAAANQADCggIEwAAAA==.Vaylethrayne:BAAANQABCgQIBQAAAA==.',
Ve='Verguetta:BAAANQAECgIIAwAAAA==.Verinsedai:BAAANQADCgcIFwAAAA==.Vesimer:BAAANQADCggIDQAAAA==.',
Vi='Vicvondik:BAAANQADCgQIBAAAAA==.Vildri:BAAANQAECgIIAgAAAA==.Violetknight:BAAANQADCgIIAgAAAA==.',
Vo='Voidrey:BAAANQAECgMIBAAAAA==.Voikullten:BAAANQADCgUIBQAAAA==.Vornash:BAAANQAECgIIAgAAAA==.',
Vy='Vylent:BAAANQABCgQIBwAAAA==.',
Wa='Waddleweaver:BAAANQADCggICAAAAA==.Warkraz:BAAANQADCgMIAwAAAA==.Warrush:BAAANQAECgUIBwAAAA==.Watchmedps:BAAANQADCgcICwAAAA==.',
Wi='Wildthang:BAAANQADCgQIBAAAAA==.Willhelt:BAAANQAECgIIAgAAAA==.Willpray:BAAANQAECgMIBAAAAA==.Windle:BAAANQADCggICAAAAA==.',
Wo='Wontondesire:BAAANQAECgYICgAAAA==.',
Xa='Xantry:BAEANQAECgUICAAAAA==.',
Xb='Xbambs:BAAANQADCgQIBAAAAA==.',
Xe='Xerovladej:BAAANQAECgQIBQAAAA==.',
Xo='Xoog:BAAANQAECgEIAQAAAA==.Xozo:BAAANQADCgIIAgAAAA==.',
Xu='Xualene:BAAANQADCggICAABNQAECgIIBAABAAAAAA==.Xurk:BAAANQADCggICAAAAA==.',
Xw='Xwarrior:BAAANQAECgQICQAAAA==.',
Ya='Yaaz:BAAANQAECgYICgAAAA==.Yamata:BAAANQADCgQIBAAAAA==.',
Ye='Yetistorm:BAAANQADCgMIAwAAAA==.',
Yu='Yuee:BAAANQAECgMIAwAAAA==.Yukonicüs:BAAANQAECgQIBAABNQAECggIEQABAAAAAA==.',
Za='Zaehara:BAAANQAECgEIAQAAAA==.Zanarian:BAAANQAECgEIAQAAAA==.Zappinboi:BAAANQAECgUIBwABNQAFFAUICAAYAMkPAA==.Zatkiel:BAAANQAECgEIAQAAAA==.',
Ze='Zealot:BAAANQADCggIEAAAAA==.Zedar:BAAANQAECgQIBAABNQAECgQIAwABAAAAAA==.Zeju:BAAANQAECgEIAgAAAA==.Zekinett:BAAANQADCgUIBQAAAA==.Zenolinwæ:BAAANQAECgUIBQAAAA==.Zeohavoc:BAAANQADCgIIAgAAAA==.',
Zh='Zhondari:BAAANQADCgYIBgAAAA==.',
Zi='Zivanya:BAAANQAECgEIAQAAAA==.',
Zu='Zurprise:BAAANQADCgYICAAAAA==.',
Zx='Zxz:BAAANQAECgQIBgAAAA==.',
Zy='Zyrgarran:BAAANQADCgYIDQAAAA==.',
['Zá']='Záraya:BAAANQAECgYIDgAAAA==.',
['Zú']='Zúpái:BAAANQAECgEIAQAAAA==.',
['Àz']='Àzæs:BAAANQAECgEIAQAAAA==.',
['Ät']='Ätreo:BAAANQAECgMIAwAAAA==.',
['Æl']='Ælusive:BAAANQADCgcIBwAAAA==.',
['Ço']='Çondemned:BAAANQADCgQIBAABNQADCgUIBgABAAAAAA==.',
['Ém']='Émperor:BAAANQADCgUIBQAAAA==.',
['Îc']='Îcyhot:BAAANQADCgUIBgAAAA==.',
['Ðr']='Ðräx:BAAANQAECgMIBQAAAA==.',
['Óh']='Óhelgur:BAAANQADCgIIAgAAAA==.',
['Öh']='Öhgr:BAAANQAECgMIBAAAAA==.',
['ßí']='ßíll:BAAANQADCggIEwAAAA==.',
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
