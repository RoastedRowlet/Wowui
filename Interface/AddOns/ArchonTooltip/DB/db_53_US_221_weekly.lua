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

local lookup = {'Unknown-Unknown','Warrior-Arms','Shaman-Elemental','Priest-Shadow','Priest-Holy','Rogue-Subtlety','Warrior-Fury','Rogue-Outlaw','Druid-Balance','Mage-Arcane','Paladin-Protection','Rogue-Assassination','Paladin-Retribution','Shaman-Restoration',}
local provider = {region='US',realm='Thunderlord',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aaliyah:BAAANQAECgcIDwAAAA==.',
Ab='Abyssknight:BAAANQADCggIDgAAAA==.',
Ac='Acesso:BAAANQADCgcIEwAAAA==.',
Ad='Adeonus:BAAANQADCgYIDAAAAA==.Adraydenn:BAAANQADCggIFgABNQAECgUIBwABAAAAAA==.',
Ae='Aecheron:BAAANQADCgcIDAABNQAECgQIBAABAAAAAA==.',
Ag='Aggressor:BAAANQADCgMIAwAAAA==.Aggrocrack:BAAANQADCggIHAAAAA==.',
Ah='Ahngus:BAAANQAECgEIAQAAAA==.',
Ai='Air:BAAANQADCggIFAAAAA==.',
Al='Alakander:BAAANQAECgIIAwAAAA==.Alexdruids:BAAANQAECgIIAgABNQAECggIEQABAAAAAA==.Alexhunt:BAAANQAECggIEQAAAA==.Alplarn:BAAANQAECgIIAgAAAA==.Althsar:BAAANQADCgEIAQAAAA==.Alucardias:BAAANQADCgYIBgAAAA==.',
An='Anitwa:BAAANQAECgQIBQABNQAECgcIEQABAAAAAA==.Anomari:BAAANQADCgUIBQAAAA==.',
Ap='Apkuggull:BAAANQAECgEIAgAAAA==.Appeal:BAAANQADCgMIAwAAAA==.',
Ar='Arandiel:BAAANQAECgUICQAAAA==.Aranina:BAAANQADCgcIDwAAAA==.Arcturrus:BAAANQADCgYICgAAAA==.Arel:BAAANQAECgYIDAAAAA==.Arkayist:BAAANQAECgEIAQAAAA==.Arowid:BAAANQADCgQIBAAAAA==.Arrwyn:BAAANQADCgIIAgABNQADCgQIBAABAAAAAA==.Arter:BAAANQAECgEIAQABNQAECgYICwABAAAAAA==.Aryhm:BAAANQAECgEIAQAAAA==.',
As='Asatralth:BAAANQAECgIIAgAAAA==.Asguard:BAAANQAECgEIAQAAAA==.Asheryo:BAAANQADCgUIBQAAAA==.Assphyxiate:BAAANQADCggIEwAAAA==.Aszshara:BAAANQADCgUIBQAAAA==.',
Au='Automagic:BAAANQAECgQIBQAAAA==.',
Ay='Aymine:BAAANQAECgQIBAAAAA==.',
Ba='Babihotdog:BAAANQAECgEIAQAAAA==.Badwolff:BAAANQADCggIDwAAAA==.Baerog:BAAANQADCgcIEAAAAA==.Banf:BAAANQAECgIIAwAAAA==.Baodabao:BAAANQAECggIEgAAAA==.Basicblends:BAAANQAECgQIBAAAAA==.',
Bb='Bblglizzy:BAAANQADCgEIAQAAAA==.',
Be='Beefglizzy:BAAANQAECgYICAAAAA==.Beelzaboot:BAAANQAECgMIBAAAAA==.Belanor:BAAANQAECgUIBwAAAA==.Berry:BAAANQAECgYIDgAAAA==.',
Bi='Bigbahungas:BAAANQADCggICgAAAA==.Bigchudifer:BAAANQADCgQIBAABNQAECgcIEQABAAAAAA==.Bigdamfury:BAAANQADCgcIDQAAAA==.Bignipsmcgee:BAAANQAECgEIAQAAAA==.Bigthunder:BAAANQADCgUIBQAAAA==.Binkalul:BAAANQADCgUIBQAAAA==.Biolimit:BAAANQAECgYIBAAAAA==.Bitss:BAAANQADCgEIAQABNQADCggIHAABAAAAAA==.',
Bl='Blacktastic:BAAANQADCggIDwAAAA==.Bladebane:BAAANQADCgQIBAAAAA==.Blastee:BAAANQAECgQICQAAAA==.Blath:BAAANQADCggIGAAAAA==.Blazius:BAAANQAECgQIBQAAAA==.Bleebles:BAAANQADCgMIAwAAAA==.Blinkinpark:BAAANQADCgEIAQAAAA==.Blitzkregmag:BAAANQADCgEIAQAAAA==.',
Bo='Bobertl:BAAANQAECgUICAAAAA==.Boomnecrotic:BAAANQAECgIIAgAAAA==.Boonney:BAAANQADCgYIBgAAAA==.Bopgun:BAAANQADCgEIAQAAAA==.',
Br='Breathboy:BAAANQAECgEIAQAAAA==.Bronder:BAAANQADCgUICgAAAA==.Bronzehoofs:BAAANQADCgMIBAAAAA==.',
Bu='Bubblemews:BAAANQADCgQIAwAAAA==.Bulletbill:BAAANQADCgUIBQAAAA==.Bullwinklee:BAAANQABCgUIBwAAAA==.Burghmaul:BAAANQAECgEIAQAAAA==.',
Ca='Cahri:BAAANQADCgQICAAAAA==.Calenesandra:BAAANQAECgIIAwAAAA==.Canon:BAAANQADCgcIDAAAAA==.Capodost:BAAANQADCgEIAQAAAA==.',
Ce='Celasong:BAAANQADCgEIAQAAAA==.Celestialhex:BAAANQABCgIIAgAAAA==.Celtïc:BAAANQADCgQIBAAAAA==.Celydrea:BAAANQADCgIIAgAAAA==.Ceree:BAAANQAECgIIAgAAAA==.',
Ch='Chimeranzomb:BAAANQADCgQIBAAAAA==.Chiwi:BAAANQADCgYIAwAAAA==.Chocogeta:BAAANQADCggIEwAAAA==.Chucknourysh:BAAANQADCgIIAgAAAA==.Chì:BAAANQADCggICQAAAA==.',
Cl='Cladie:BAAANQADCgQIBAAAAA==.Cladoe:BAAANQAECgEIAQAAAA==.Cladow:BAAANQAECgUICgAAAA==.Clag:BAAANQADCgIIAgAAAA==.',
Co='Cogblock:BAAANQAECgQICAAAAA==.Conqor:BAAANQAECgQIBAAAAA==.',
Cr='Crimsonbull:BAAANQADCggICAABNQAECgYIDAABAAAAAA==.Cronosphere:BAAANQADCgcIEAAAAA==.Crushaturty:BAAANQADCgQIBwAAAA==.',
Cu='Cubes:BAAANQADCgUIBQAAAA==.',
Cy='Cyndrainna:BAAANQABCgMIBgAAAA==.Cyndrin:BAAANQAECgIIAgAAAA==.',
Da='Daddyglock:BAAANQADCgYIBwAAAA==.Daerper:BAAANQADCgcIBwABNQADCggIDAABAAAAAA==.Danayro:BAAANQADCgQIBAAAAA==.Darklego:BAABNQAECoEYAAICAAkJfiJSCQBcAwACAAkJfiJSCQBcAwAAAA==.Darksign:BAAANQADCgIIAgAAAA==.Davemage:BAAANQADCggIFAAAAA==.Dawnhorn:BAAANQADCgQIBAAAAA==.',
De='Deaddhunter:BAAANQADCgEIAQAAAA==.Deaddmage:BAAANQADCgUIBQAAAA==.Deadlylight:BAAANQADCgYIBgAAAA==.Deepyram:BAAANQADCgEIAQAAAA==.Delillama:BAAANQAECgMIBQAAAA==.Demolior:BAAANQABCgEIAQAAAA==.Destnny:BAAANQAECgEIAgAAAA==.Destrohunter:BAAANQADCgcIBwAAAA==.Destroker:BAAANQAECgMIAwAAAA==.',
Dh='Dhspudd:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Di='Dillpo:BAAANQABCgUIBgAAAA==.Dioress:BAAANQADCggIEgAAAA==.Dis:BAAANQAECgYICgABNQAECgkJGgADAMAkAA==.Disyx:BAAANQAECgIIAgAAAA==.Diyanå:BAAANQAECgcIDAAAAA==.',
Do='Domainz:BAAANQAECgYIBgAAAA==.Dommymommie:BAAANQADCgMIAwAAAA==.Donalan:BAAANQAECgEIAQAAAA==.Donzm:BAAANQADCgcIBgABNQAECgcIEQABAAAAAA==.Donzw:BAAANQAECgcIEQAAAA==.Dorkwaffle:BAAANQADCgIIAgAAAA==.',
Dr='Dracthick:BAAANQAECgYIBgAAAA==.Dragonbender:BAEANQADCgUIBQAAAA==.Dragun:BAAANQADCgIIAgAAAA==.Draxxor:BAAANQAECgEIAQAAAA==.Dreamender:BAAANQAECggIBQAAAA==.Droknor:BAAANQADCgQICAAAAA==.Druidllama:BAAANQAECgQIBwAAAA==.Drumin:BAAANQAECgUIDAAAAA==.',
Dw='Dwarvanhand:BAABNQAECoEYAAMEAAkJix30CQCiAgAEAAcJ6CL0CQCiAgAFAAIJlgwQVgCQAAAAAA==.',
['Dâ']='Dâwn:BAAANQAECggICgAAAA==.',
['Dã']='Dãwn:BAAANQAECggIAgAAAA==.',
['Dæ']='Dærper:BAAANQADCggIDAAAAA==.',
Ea='Earthmender:BAAANQADCgYIBwAAAA==.Eatmacookie:BAAANQADCgYIDwAAAA==.',
El='Elazar:BAAANQAECgIIAgAAAA==.Elderian:BAAANQADCgUIBgAAAA==.Elemenope:BAAANQADCggIEgAAAA==.Elguasonbb:BAAANQADCgUICAAAAA==.Elidori:BAAANQADCggICwAAAA==.',
Em='Emashasha:BAAANQADCgQIBAAAAA==.Emerys:BAAANQADCgIIAgAAAA==.Emitlyght:BAAANQADCggIFQAAAA==.',
En='Eniri:BAAANQAECgIIAgAAAA==.Enyeto:BAAANQAECgYICwAAAA==.',
Er='Eroviaevia:BAAANQADCggIDgAAAA==.',
Es='Esterossa:BAAANQADCgYIBgAAAA==.',
Eu='Eunomia:BAAANQAECgYIDgAAAA==.',
Ex='Exra:BAAANQADCgQIAwAAAA==.',
Ez='Ezekeel:BAAANQAECgQIBwAAAA==.Ezoghoul:BAAANQAECgQIBQAAAA==.',
Fa='Faeare:BAAANQADCgYIBgAAAA==.Fakedemon:BAEANQADCgIIAgABNQAECgEIAQABAAAAAA==.Fakelock:BAEANQADCgMIAwABNQAECgEIAQABAAAAAA==.Fakendruid:BAEANQAECgEIAQAAAA==.Fauxx:BAAANQADCgYICwAAAA==.',
Fd='Fdup:BAAANQAECgIIAQAAAA==.',
Fe='Felfae:BAAANQADCgYIDQAAAA==.Feverish:BAAANQADCgUIBQAAAA==.',
Fi='Filip:BAAANQAECgEIAQAAAA==.',
Fl='Flamefenix:BAAANQADCggIDQAAAA==.Flumpy:BAAANQAECgUIDAAAAA==.Flurpymcdoof:BAAANQADCgYICAAAAA==.',
Fo='Folken:BAAANQAECgQIBAAAAA==.Foodtruck:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Forbiddyn:BAAANQAECgcIEAAAAA==.Foxiefoxy:BAAANQADCgYIDwAAAA==.',
Fr='Fraiser:BAAANQADCgYICgABNQAECgYICwABAAAAAA==.',
Fu='Fulgrum:BAAANQADCgIIAwAAAA==.Funkweave:BAEANQAECgUIBwAAAA==.Fupacabras:BAAANQAECgIIAgAAAA==.Furidas:BAAANQAECgEIAQAAAA==.',
['Fö']='Föxfïre:BAAANQADCgIIAgAAAA==.',
Ga='Gaius:BAAANQABCgIIAgAAAA==.Garogg:BAAANQAECgYICAAAAA==.Garotomoreno:BAAANQAECgYICwAAAA==.Garrut:BAAANQAECgMIAwAAAA==.Gaymr:BAAANQADCgIIAgAAAA==.',
Gi='Giirthquakee:BAAANQADCgcIDwABNQAECgEIAQABAAAAAA==.Gimmage:BAAANQAECgIIAgAAAA==.',
Gl='Glorbruid:BAAANQADCggIDAAAAA==.',
Go='Gojosatóru:BAAANQAECgQIBwAAAA==.Goldenchef:BAAANQADCgYIBgAAAA==.Gordatamara:BAAANQADCgEIAQAAAA==.Gotcowbell:BAAANQAECgEIAQAAAA==.',
Gr='Grahnis:BAAANQADCgUICAABNQAECgEIAQABAAAAAA==.Grasswhistle:BAAANQAECgEIAQABNQAECgYIDQABAAAAAA==.Grayzor:BAAANQAECgEIAQAAAA==.Greendust:BAAANQADCgYICQAAAA==.Greenperor:BAAANQAECgQIBwAAAA==.Grenthor:BAAANQADCgEIAQAAAA==.Grenvar:BAAANQAECgYICQAAAA==.Grigdor:BAAANQAECgcIDgAAAA==.Gràcias:BAAANQADCgYIBgAAAA==.',
Gu='Guass:BAAANQAECgYICwAAAA==.Gunbolt:BAAANQAECgMIBQAAAA==.',
['Gø']='Gøhåñ:BAAANQADCgYIBgAAAA==.',
['Gù']='Gùndèr:BAAANQAECgMIBAAAAA==.',
Ha='Habrosh:BAAANQAECgQIBAAAAA==.Hailrazor:BAAANQADCgIIAgAAAA==.Hakiry:BAAANQAECgIIAgAAAA==.Harike:BAAANQADCgMIAwAAAA==.Hatrix:BAAANQADCgMIAwAAAA==.Haunt:BAAANQADCgcIDwAAAA==.Havokhuntr:BAAANQADCgQIBAAAAA==.Hawkdalock:BAAANQADCgUIBQAAAA==.Hawkkaye:BAAANQADCgYICwAAAA==.Haze:BAAANQAECgEIAQAAAA==.Hazesamaa:BAABNQAECoEYAAIGAAkJdwklDABCAgAGAAkJdwklDABCAgAAAA==.',
He='Healsforfree:BAAANQADCgIIAgAAAA==.Healsgoodman:BAAANQADCgEIAgAAAA==.Hellviera:BAAANQADCgIIAgAAAA==.Hernog:BAAANQAECgYICAAAAA==.Hexmenixy:BAAANQADCggIEwAAAA==.',
Hi='Hianu:BAAANQAECgQIBQAAAA==.Highlordhunt:BAAANQADCgUIBQAAAA==.',
Ho='Holabenjy:BAAANQAECgIIAgAAAA==.Holybenjy:BAAANQAECgEIAQAAAA==.Holybibble:BAAANQADCgIIBAAAAA==.Holybox:BAAANQAECgEIAQAAAA==.Holyfady:BAAANQAECgEIAQAAAA==.Holyfenix:BAAANQAECgEIAQAAAA==.Holynixy:BAAANQADCggIDgAAAA==.Holypaladinn:BAAANQADCgEIAQAAAA==.Holyzyn:BAAANQAECgEIAQAAAA==.Hoonding:BAAANQADCgcICAABNQAECgkJGAAGAHcJAA==.Hordak:BAAANQADCgYIDAAAAA==.Horne:BAAANQADCgEIAQAAAA==.Hotstuffbaby:BAAANQADCgQIBAAAAA==.Hottodot:BAAANQAECgQIBAAAAA==.Howde:BAAANQADCggIDgAAAA==.Howdydoo:BAAANQADCgcIEwAAAA==.',
Hu='Hudini:BAAANQAECgcIDwAAAA==.Hushweaver:BAAANQADCgQICgAAAA==.',
Hy='Hypal:BAAANQAECgEIAQABNQADCgMIAwABAAAAAA==.Hypd:BAAANQADCgMIAwAAAA==.Hypev:BAAANQAECgEIAQABNQADCgMIAwABAAAAAA==.Hypm:BAAANQADCgIIAgABNQADCgMIAwABAAAAAA==.Hyps:BAAANQAECggIDgABNQADCgMIAwABAAAAAA==.Hypt:BAAANQAECgUIBwABNQADCgMIAwABAAAAAA==.',
Ia='Iakned:BAAANQADCggICAABNQAECgQIBQABAAAAAA==.',
Ib='Ibichi:BAAANQADCgUIBgAAAA==.',
Ic='Icet:BAAANQAECgUICgAAAA==.',
Il='Illshankya:BAAANQAECgIIAgAAAA==.',
Im='Imihn:BAAANQADCggIDQAAAA==.',
In='Invìctús:BAAANQAECgQIBAAAAA==.',
It='Ithir:BAAANQADCgYICwAAAA==.Itsemma:BAAANQAECgIIAgAAAA==.',
Iu='Iustitia:BAAANQABCgIIBAAAAA==.',
Iy='Iylara:BAAANQAECgEIAQAAAA==.',
Iz='Izhira:BAAANQABCgMIAgAAAA==.',
Ja='Jaanus:BAAANQADCgMIAwAAAA==.Jackdalilguy:BAAANQADCgUIBQAAAA==.Jackodes:BAAANQAECgIIAgABNQAECgcIDgABAAAAAA==.Jackodm:BAAANQAECgcIDgAAAA==.Jad:BAAANQAECgMIBAAAAA==.Janicafae:BAAANQADCgMIAwAAAA==.Jareth:BAAANQABCgUIDAAAAA==.Jawa:BAAANQADCgUIBQABNQAECgMIAwABAAAAAA==.Jawo:BAAANQAECgMIAwAAAA==.',
Je='Jeefberky:BAAANQADCgYIBgAAAA==.Jersey:BAAANQADCgUIBQAAAA==.Jetts:BAAANQAECgQIBQAAAA==.',
Jo='Johnnysinz:BAAANQAECgUIBwAAAA==.Johnnyzyns:BAAANQAECgcIBwAAAA==.Johnret:BAAANQAECgMIBAAAAA==.',
Jp='Jp:BAAANQAFFAIIAgAAAA==.',
Ju='Juhla:BAAANQADCgEIAQAAAA==.Juno:BAAANQADCgUICQAAAA==.',
Ka='Kadester:BAAANQAECgEIAQAAAA==.Kaelwyn:BAAANQABCgIIAgAAAA==.Kaimen:BAAANQAECgIIAgAAAA==.Kalipriest:BAAANQAECgQIBAAAAA==.Kalipso:BAAANQAECgIIAgAAAA==.Kamehameha:BAAANQADCgUIBwAAAA==.Kamwar:BAABNQAECoEYAAMHAAkJFiQZAADiAwAHAAkJESQZAADiAwACAAMJPyCnagAIAQABNQAECgkJHQAIAJYlAA==.Karideer:BAAANQADCggIDAAAAA==.Karnaughm:BAAANQADCgUIAQAAAA==.Kaylax:BAAANQADCgYICwAAAA==.Kaylost:BAAANQADCgMIAwAAAA==.Kaylub:BAAANQAECgQIBAAAAA==.Kazrim:BAAANQADCgQIBAAAAA==.',
Ke='Keldhar:BAAANQAECgMIAwAAAA==.Kenparcell:BAAANQADCgcIBwAAAA==.Kerash:BAAANQADCgYIDwAAAA==.Kevindk:BAAANQADCgYIBgAAAA==.Kevindrd:BAAANQADCgYIBgABNQAECgYICwABAAAAAA==.Kevintt:BAAANQAECgYICwAAAA==.Keys:BAAANQADCggIFAAAAA==.',
Kh='Khodad:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Khundalar:BAAANQADCgQIBAAAAA==.',
Ki='Kiarraa:BAAANQADCgEIAQAAAA==.Killachefcjr:BAAANQADCgcICwAAAA==.Kimi:BAAANQADCgQIBAAAAA==.Kimori:BAAANQADCgUIBQAAAA==.Kinzee:BAAANQADCgEIAQAAAA==.',
Kn='Knugget:BAAANQAECgEIAQAAAA==.',
Ko='Kodiakhunter:BAAANQADCgcIDgAAAA==.Kodlighting:BAAANQADCgUICgAAAA==.Koniqeo:BAAANQADCggIEgAAAA==.Koressme:BAAANQADCggIDAAAAA==.Korlat:BAAANQADCgcIEwAAAA==.Kozdiniar:BAABNQAECoEbAAIJAAkJESRCAgCmAwAJAAkJESRCAgCmAwAAAA==.Kozurai:BAAANQAECgUIBQABNQAECgkJGwAJABEkAA==.',
Kr='Kristree:BAAANQADCgIIAgAAAA==.Krëegz:BAAANQAECgIIAgAAAA==.Krëëgz:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.',
Ku='Kugot:BAAANQADCggICAAAAA==.Kurupted:BAAANQAECgEIAQAAAA==.',
Ky='Kydrea:BAAANQADCgYIDwAAAA==.Kyne:BAAANQADCggICAAAAA==.Kynyselda:BAAANQAECgQIBAAAAA==.Kyrabear:BAAANQADCgQIBgAAAA==.',
['Kâ']='Kânê:BAAANQAECgQIBgAAAA==.',
La='Ladrón:BAAANQADCgYIDAAAAA==.Larc:BAAANQADCgYICQAAAA==.Larkos:BAAANQADCgYIBgAAAA==.Lassamyna:BAAANQADCgUIBQAAAA==.Latías:BAAANQAECgcICwAAAA==.',
Le='Leechygos:BAAANQADCggIDwAAAA==.Legenddairy:BAAANQADCggIFAAAAA==.Legirlas:BAAANQADCgQIBAABNQADCgUIBwABAAAAAA==.Leheo:BAAANQADCgEIAQAAAA==.Leigong:BAAANQAECgQIBAAAAA==.Lenorand:BAAANQABCgUIBgABNQAECgEIAQABAAAAAA==.',
Li='Liani:BAAANQADCgIIAgAAAA==.Lickmyhorns:BAAANQAECgUICQAAAA==.Liendrah:BAEANQAECgYIEAAAAA==.Lightmf:BAAANQAECgQIBAAAAA==.Lightninglip:BAAANQADCgcIEAAAAA==.Lightwaves:BAAANQAECgQIBAAAAA==.Lilet:BAAANQAECgMIAwAAAA==.Lilitsune:BAAANQAECgEIAQAAAA==.Liotrix:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Liradel:BAAANQADCgIIAgAAAA==.Lisri:BAAANQAECgIIBAAAAA==.Lizolio:BAAANQADCggIEQAAAA==.',
Ll='Llomel:BAAANQADCgYICAAAAA==.',
Lo='Lochlan:BAAANQADCgcIDgAAAA==.Lohhano:BAAANQABCgYIBwAAAA==.Louanna:BAAANQADCgUIBQAAAA==.',
Lu='Lucianagi:BAAANQAECgMIBgAAAA==.Lucilla:BAAANQADCgUIBQAAAA==.Lussprodz:BAAANQADCgUIBQAAAA==.Luurg:BAAANQADCgcIDgAAAA==.',
Ma='Mageunal:BAAANQADCgEIAQAAAA==.Magikkosa:BAAANQAECgQICAAAAA==.Maibutzbrewy:BAAANQADCgQIBgAAAA==.Majamojopowa:BAAANQABCgUIBQAAAA==.Malekíth:BAAANQADCggIAgAAAA==.Manutters:BAAANQADCggIDgAAAA==.Marrylanders:BAABNQAECoEXAAIKAAkJih7PDwA+AwAKAAkJih7PDwA+AwAAAA==.Marrylock:BAAANQADCgUIBQAAAA==.Martiul:BAAANQAECgcIEQAAAA==.Mastayoda:BAAANQABCgMIAwAAAA==.Mayven:BAAANQADCgUICgAAAA==.',
Mc='Mcboomii:BAAANQADCggICAAAAA==.',
Me='Megapally:BAAANQADCgQIBAAAAA==.Mellie:BAAANQADCgMIAwAAAA==.Melmei:BAAANQAECgEIAQAAAA==.Meriweather:BAAANQADCgcIEwAAAA==.Merlinajax:BAAANQADCgYIDAAAAA==.Mertlek:BAAANQADCgQIBAABNQAECgcIEQABAAAAAA==.Meszyra:BAAANQAECggIEgAAAA==.',
Mi='Michaelcera:BAAANQAECgYICwAAAA==.Mijuku:BAAANQAECgYIDgAAAA==.Mikehawk:BAAANQADCgcIDAAAAA==.Minusgreen:BAAANQADCgYIBQAAAA==.Misoeternal:BAAANQADCgcIEwAAAA==.Mistafista:BAAANQADCgUIBQAAAA==.Mitchard:BAAANQAECgYICQAAAA==.Mittenza:BAAANQADCggIFgAAAA==.Mixelplix:BAAANQADCggIEwAAAA==.Mizstriss:BAAANQAECgUIBQAAAA==.',
Mo='Molari:BAAANQADCgcICgAAAA==.Monksymeg:BAAANQADCgIIAgAAAA==.Monkwilbo:BAAANQADCgYIBgAAAA==.Moonfur:BAAANQAECgEIAQAAAA==.Mordath:BAAANQADCggIEwAAAA==.Mordoom:BAAANQAECgQIBAAAAA==.Morikai:BAAANQAECgEIAQAAAA==.Morinn:BAAANQADCgYIBgAAAA==.Mosag:BAAANQAECgUICgAAAA==.Moushou:BAAANQAECgIIAgAAAA==.',
Ms='Mspacman:BAAANQADCggIDgAAAA==.',
Mu='Mudslide:BAAANQADCgUIBQAAAA==.Muffduster:BAAANQADCgUIBQAAAA==.Muffintopper:BAAANQAECgUICwAAAA==.Muppie:BAAANQADCgMIBAAAAA==.Mutovenator:BAAANQADCggICQAAAA==.',
My='Mychef:BAAANQADCgUIBQAAAA==.Myrrha:BAAANQAECgcIDQAAAA==.',
['Mï']='Mïsterfox:BAAANQADCgUIBwAAAA==.',
['Mô']='Mônah:BAAANQADCgQIBQABNQADCgYICgABAAAAAA==.',
Na='Nakiro:BAAANQADCgYIDAAAAA==.Namhanharal:BAAANQADCgUIBQAAAA==.Natch:BAAANQADCgUICwAAAA==.',
Ne='Nedilap:BAAANQAECgQIBQAAAA==.Nef:BAAANQAECgEIAQAAAA==.Neqousa:BAAANQADCgIIAgAAAA==.Nerbench:BAAANQABCgIIAgAAAA==.Nerdchillpal:BAAANQADCgYIBgAAAA==.Nerdi:BAAANQADCgQIBAAAAA==.Nerokos:BAAANQADCgcIBwAAAA==.Nerve:BAAANQADCgEIAQAAAA==.',
Ni='Nightx:BAAANQAECgIIAwAAAA==.Nishkavel:BAAANQABCgEIAQAAAA==.Nitewang:BAAANQADCgQIBAAAAA==.Nitewing:BAABNQAECoEYAAILAAkJyiPPAACqAwALAAkJyiPPAACqAwABNQADCgQIBAABAAAAAA==.Niza:BAAANQABCgYIDAAAAA==.',
No='Noccs:BAAANQADCgYIBQAAAA==.Noctaro:BAEANQAECggIDAAAAA==.Nokona:BAAANQADCgYICgAAAA==.Notpizza:BAAANQAECgMIAwABNQAFFAEIAQABAAAAAA==.',
Nu='Nuikha:BAAANQADCgYIBwAAAA==.Nukenfoobs:BAAANQADCgEIAQABNQAECgUICwABAAAAAA==.',
Ny='Nyoazz:BAAANQADCgEIAQAAAA==.',
Ob='Obnixa:BAAANQAECgQIBwAAAA==.Obnixlis:BAAANQADCgYIBgAAAA==.',
Od='Ody:BAAANQAECgEIAQAAAA==.',
Og='Ogakal:BAAANQABCgYIDwAAAA==.',
Ol='Oldstorm:BAAANQADCgEIAQABNQAECgQIBAABAAAAAA==.',
On='Onfiree:BAAANQAECggICQAAAA==.',
Op='Opithel:BAAANQAECgUIBwABNQAECgYICgABAAAAAA==.Opizerka:BAAANQAECgYICgAAAA==.',
Or='Oriestus:BAAANQADCgEIAQAAAA==.Oriko:BAAANQAECgUIBQAAAA==.Oríllas:BAAANQAECgQIBwAAAA==.',
Os='Osric:BAAANQADCgIIAgABNQAECgUICgABAAAAAA==.',
Oy='Oyogo:BAAANQAECggIEgABNQAFFAMIBAABAAAAAA==.Oyogu:BAAANQADCgUIBQABNQAFFAMIBAABAAAAAA==.',
Pa='Paech:BAAANQADCgYIBgAAAA==.Pairädice:BAAANQADCgYIDAAAAA==.Paladane:BAAANQAECgMIBAAAAA==.Pallymorph:BAAANQADCgIIAgAAAA==.Palsdruid:BAAANQADCgYIDAAAAA==.Pamalinaa:BAAANQAECgEIAQAAAA==.Pamplemousse:BAAANQAECggIAQAAAA==.Papanezz:BAAANQAECgIIAgAAAA==.Patapouf:BAAANQAECgIIAwAAAA==.Payback:BAAANQADCgEIAQAAAA==.',
Pe='Pearbandit:BAAANQAECgEIAQAAAA==.Pegully:BAAANQAECgEIAQAAAA==.Pewxtwo:BAAANQADCgEIAQAAAA==.',
Ph='Phephraan:BAAANQAECgMIBAAAAA==.Phinehas:BAAANQADCgYIDwAAAA==.Phwaz:BAAANQADCgcIEgAAAA==.Phyxyzin:BAAANQADCgUICwAAAA==.',
Pi='Piddles:BAAANQABCgYICgAAAA==.Pikeysham:BAAANQADCgMIAwAAAA==.Pinchebean:BAAANQAECgEIAQAAAA==.Pinktress:BAAANQAECgMIAwAAAA==.Pizzadough:BAAANQAFFAEIAQAAAA==.',
Pl='Plskillmie:BAAANQAECgQIBgAAAA==.',
Po='Pocahontis:BAAANQABCgIIAgAAAA==.Polygonnacry:BAAANQADCgMIAwAAAA==.Popatop:BAAANQADCgQIBAAAAA==.Possecutor:BAABNQAECoEYAAIEAAkJwxvgBQAUAwAEAAkJwxvgBQAUAwAAAA==.Pownadin:BAAANQADCgQIBQAAAA==.',
Pr='Prabis:BAAANQADCgcIDAAAAA==.Praesidius:BAAANQADCgEIAQAAAA==.Pryîto:BAAANQADCggIDAAAAA==.',
Pu='Pumachaka:BAAANQADCgcIBwAAAA==.Pushinp:BAAANQADCgQIBAAAAA==.',
Py='Pyresia:BAAANQAECgQIBAAAAA==.Pyrocity:BAAANQADCgYIBgAAAA==.',
Qu='Quackshot:BAAANQAECgQIBgAAAA==.',
Qw='Qwertysquid:BAAANQADCgMIBAAAAA==.',
Ra='Rads:BAAANQABCgEIAQAAAA==.Raegen:BAEANQADCgUIBQABNQAECggIDAABAAAAAA==.Raezer:BAEANQADCggICAABNQAECggIDAABAAAAAA==.Raikomori:BAAANQAECgEIAQAAAA==.Ralroc:BAAANQADCgYIBgAAAA==.Ranare:BAAANQAECgIIAwAAAA==.Rathrus:BAAANQAECgQIBAAAAA==.Ratonfusse:BAAANQABCgQIBAAAAA==.Ravenhart:BAAANQADCgEIAgAAAA==.Raxmanus:BAAANQADCgYIEAAAAA==.Rayru:BAAANQADCggICAAAAA==.Rayvienne:BAAANQADCgIIAgAAAA==.',
Re='Readthebible:BAAANQADCgIIAgAAAA==.Redvelvett:BAAANQADCgcIEAAAAA==.Reilini:BAAANQAECggICQAAAA==.Remedium:BAAANQABCgQICAAAAA==.Renascor:BAAANQAECgQIBQABNQAECggIEgABAAAAAA==.Reàp:BAAANQADCgMIAwAAAA==.',
Rh='Rhojin:BAAANQADCgcIEAAAAA==.',
Ri='Rikimaruu:BAAANQAECgUIBQAAAA==.Rinaari:BAAANQADCgUIBQAAAA==.Rivelia:BAAANQADCgcIBwABNQAECgcIDQABAAAAAA==.',
Ro='Rockethunt:BAAANQAECgMIAwAAAA==.Rokurota:BAAANQADCgUICgAAAA==.Ronek:BAAANQABCgQIBgAAAA==.Royalborn:BAAANQAECgEIAQAAAA==.',
Ru='Rubikon:BAAANQAECgQIBQAAAA==.Rueldalf:BAAANQADCgYIDwAAAA==.Ruïn:BAAANQADCggIEgAAAA==.',
['Rô']='Rôôstêr:BAAANQADCgQIBAAAAA==.',
Sa='Salidan:BAAANQADCgMIAwAAAA==.Salt:BAAANQAECgEIAQABNQAECgYICwABAAAAAA==.Samlock:BAAANQAECgcIEAAAAA==.Sap:BAABNQAECoEOAAQIAAYJ8xozBgClAQAIAAYJLxczBgClAQAMAAQJGRo9FQBIAQAGAAMJiQ8VJwC2AAABNQAECggIDQABAAAAAA==.Satyrlord:BAAANQADCggIFAAAAA==.Savella:BAAANQAECgMIAwAAAA==.',
Sc='Scarletblade:BAAANQAECgUICQAAAA==.Schamwoww:BAAANQADCggIEgAAAA==.Sclas:BAAANQADCgIIAgAAAA==.Scubar:BAAANQADCgcIDQAAAA==.',
Se='Seafox:BAAANQADCgIIAgAAAA==.Sear:BAAANQAECgYICAAAAA==.Selest:BAAANQADCgEIAQAAAA==.Selkets:BAAANQADCgUIBQAAAA==.Selkola:BAAANQABCgUIBQAAAA==.Seraphiina:BAAANQAECgQIBAAAAA==.',
Sh='Shadowbinder:BAAANQADCggICAAAAA==.Shamiam:BAAANQADCgUIBQAAAA==.Shamozmo:BAAANQADCgMIAgAAAA==.Shataree:BAAANQADCgQIBAAAAA==.Shineup:BAAANQADCggIEAAAAA==.Shintetsu:BAAANQADCgYIBgAAAA==.Shockkor:BAAANQADCgcIDgAAAA==.Shockujin:BAAANQADCgcICwABNQAECgcIDwABAAAAAA==.Shox:BAAANQADCgMIAwAAAA==.Shý:BAAANQADCgIIAgAAAA==.',
Si='Silanris:BAAANQADCgQICAAAAA==.Sitaana:BAAANQADCgcIBwAAAA==.',
Sk='Skillr:BAAANQAECgEIAQAAAA==.Skyekníght:BAAANQADCggICgAAAA==.',
Sl='Sleezyaf:BAAANQAECgQIBgAAAA==.Slermp:BAAANQADCgYIBgAAAA==.Slicett:BAAANQADCgMIAwAAAA==.Slowcase:BAAANQAECgcIDgAAAA==.',
Sm='Smoochem:BAAANQADCggICAAAAA==.',
Sn='Sneaze:BAAANQADCgUIBQAAAA==.',
So='Socketss:BAAANQAECgEIAQAAAA==.Sohjinra:BAAANQAECgEIAQAAAA==.Sollaria:BAAANQADCgMIAwAAAA==.Sololvlin:BAAANQADCgYIBgAAAA==.Sololvling:BAAANQAECgQIBwAAAA==.Sovereign:BAABNQAECoEYAAINAAkJRRxgEgC6AgANAAkJRRxgEgC6AgAAAA==.',
Sp='Sp:BAAANQADCgYICAAAAA==.Sparkleclaws:BAAANQADCgUIBgAAAA==.Sparkycleave:BAAANQADCgYICwAAAA==.Spicy:BAAANQAECgEIAQAAAA==.Splashaxuss:BAAANQADCgUIBQAAAA==.Spookyloops:BAAANQAECggICAAAAA==.Sproggles:BAAANQADCgcIBwAAAA==.',
Ss='Sslipknot:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.',
St='Stealthfire:BAAANQAECgYIDQAAAA==.Sterny:BAAANQAECgEIAQAAAA==.Stidetroll:BAAANQAECgEIAQAAAA==.Stormstrikes:BAAANQADCggIFAAAAA==.',
Su='Substandard:BAAANQAECgMIAwAAAA==.Sugaboomboom:BAAANQADCgYIBgAAAA==.Sumo:BAAANQABCgIIAgAAAA==.Sumwon:BAAANQADCggICAAAAA==.Sunarr:BAAANQAECgQIBQAAAA==.Sunkenlily:BAAANQADCgYICgAAAA==.Superace:BAAANQAECggIDwAAAA==.Surlee:BAAANQADCgYIBAAAAA==.Surlydude:BAAANQADCgEIAQAAAA==.Suule:BAAANQADCgYIDQAAAA==.',
Sw='Swaggernaut:BAAANQADCggICAAAAA==.Swiffys:BAAANQAECgUIBgAAAA==.Swissy:BAAANQADCgQIBwAAAA==.Swordnoob:BAAANQAECgEIAQAAAA==.',
Sy='Synkadevour:BAAANQAECgEIAQAAAA==.Synkareaper:BAAANQADCgQIBgABNQAECgEIAQABAAAAAA==.Synxzc:BAAANQADCgUIBQAAAA==.',
Ta='Taappy:BAAANQAECgQIBQAAAA==.Taggs:BAAANQAECgMIAwAAAA==.Taggsy:BAAANQADCgEIAQAAAA==.Tail:BAAANQAECgIIAgAAAA==.Tails:BAAANQADCgUICwAAAA==.Tajomaru:BAAANQADCgIIAgAAAA==.Tanmand:BAAANQADCgcIEgAAAA==.Tanthora:BAAANQADCgYICQAAAA==.Tao:BAAANQADCgMIAwAAAA==.',
Te='Teddymouse:BAAANQADCgUIBQABNQAECggIBQABAAAAAA==.Tenebris:BAAANQADCgUIBgAAAA==.Terrycrews:BAAANQAECgEIAQAAAA==.',
Th='Thasper:BAAANQABCgMIAwAAAA==.Thebigkodiak:BAAANQADCgYIBgAAAA==.Thebutler:BAAANQAECgIIAgABNQAECgkJGAAEAIsdAA==.Thegrimus:BAAANQAECgYICgAAAA==.Thekeres:BAAANQADCgUICQAAAA==.Thickums:BAAANQADCgEIAQAAAA==.Thornwhisper:BAAANQADCgcIBwAAAA==.Throh:BAAANQADCgUIBwAAAA==.Thussy:BAAANQAECgEIAQAAAA==.',
Ti='Timøthy:BAAANQAECgIIAwAAAA==.',
Tk='Tkaniaa:BAAANQADCgQIBQAAAA==.',
To='Tokeyes:BAAANQADCgcICwAAAA==.Torwa:BAAANQAECgIIAwAAAA==.Tossdirt:BAABNQAECoEaAAMDAAkJwCT2AQC7AwADAAkJwCT2AQC7AwAOAAEJCghFlAAwAAAAAA==.Toxle:BAAANQAECgEIAQAAAA==.Toysruskid:BAAANQADCgIIAgAAAA==.',
Tr='Trippdaddy:BAAANQAECgIIAgAAAA==.',
Tu='Tuckford:BAAANQADCgYIBwAAAA==.',
Tw='Twinswords:BAAANQADCgYIBQAAAA==.Twiz:BAAANQADCgEIAQAAAA==.',
Tx='Txcreekwoo:BAAANQADCgMIAwAAAA==.',
Ty='Typhal:BAAANQAECgYIDQAAAA==.Typo:BAAANQADCgEIAQAAAA==.',
Uh='Uhtain:BAAANQADCggIFAABNQADCggIFAABAAAAAA==.Uhtan:BAAANQADCggIFAAAAA==.',
Un='Uncleklaus:BAAANQAECgYICgAAAA==.Ungnite:BAAANQAECgEIAQAAAA==.Unicornfartz:BAAANQADCggICAAAAA==.Unikorn:BAAANQADCgEIAQAAAA==.',
Ur='Urthron:BAAANQAECgIIAgAAAA==.',
Us='Ushiamdi:BAAANQAECgYICgAAAA==.',
Ut='Utaan:BAAANQADCggIFAABNQADCggIFAABAAAAAA==.',
Va='Vaerenaris:BAAANQADCgEIAQAAAA==.Vaiel:BAAANQAECgEIAQAAAA==.Valanthé:BAAANQADCgYICAAAAA==.Vandrey:BAAANQADCgYIBgAAAA==.Vazen:BAAANQADCgEIAQAAAA==.',
Ve='Velarasta:BAAANQADCgUIBQAAAA==.Veluna:BAAANQABCgMIAwABNQAECgYIDAABAAAAAA==.Veravvang:BAAANQAECgQIBwABNQADCggICAABAAAAAA==.Verdereina:BAAANQADCgcIBwAAAA==.Veroshia:BAAANQADCggIEwAAAA==.Vexea:BAAANQAECgMIBgABNQAECgYICwABAAAAAA==.Vexx:BAAANQADCgcIDAAAAA==.',
Vi='Vinladen:BAAANQADCgMIAwABNQAECgQICQABAAAAAA==.Violettcloud:BAAANQAECgMIBAAAAA==.Virali:BAAANQAECgQICAAAAA==.Virussuckss:BAAANQADCgYIBgAAAA==.Vispper:BAAANQAECgQIBwAAAA==.Viyinx:BAAANQAECgQIBAABNQAECgcIDQABAAAAAA==.Vizuel:BAAANQADCgQICAABNQAECgEIAQABAAAAAA==.',
Vk='Vkdk:BAAANQADCgYIBgAAAA==.',
Vo='Vondrake:BAAANQABCgIIAgAAAA==.Vorel:BAAANQADCgYIBgAAAA==.',
Vp='Vpung:BAAANQAECgMIAwAAAA==.',
Vy='Vyllin:BAAANQAECgYICwAAAA==.Vynarran:BAAANQAECgUICAAAAA==.Vynlann:BAAANQADCgQIBAAAAA==.',
Wa='Warringmyer:BAAANQADCgcIBwAAAA==.Warriorlol:BAAANQAECggIDQAAAA==.Watchdodo:BAAANQADCggIFQAAAA==.Wax:BAAANQADCgQIBAAAAA==.',
We='Weebscum:BAAANQAECgcIEAAAAA==.',
Wi='Willowblessu:BAAANQAECgcIDwAAAA==.Willòw:BAAANQADCgEIAQAAAA==.Windler:BAAANQADCgEIAQAAAA==.Wisha:BAAANQADCgEIAQAAAA==.',
Wo='Wojiaonl:BAAANQADCgEIAQAAAA==.Wolty:BAAANQADCgYIDQAAAA==.Woodglue:BAAANQADCggICAAAAA==.Wovenxlight:BAEANQAECgQIBAAAAA==.',
Wr='Wrathin:BAAANQADCgYIBgAAAA==.Wrayvin:BAAANQABCgEIAQAAAA==.',
Xa='Xaeora:BAAANQAECgEIAQAAAA==.',
Xe='Xeona:BAAANQADCgUICgAAAA==.Xesolyt:BAAANQADCgMIAwAAAA==.',
Ye='Yeahbrother:BAAANQADCgIIAgAAAA==.Yeralt:BAAANQADCgEIAQAAAA==.',
Yo='Yoshikawa:BAAANQAECgUIDAABNQAECgYICgABAAAAAA==.',
Za='Zaivama:BAAANQADCgIIAgAAAA==.Zandren:BAAANQADCgYICgAAAA==.Zaranthari:BAAANQADCgMIAwAAAA==.Zarindela:BAAANQAECgcICgAAAA==.',
Ze='Zeenalizard:BAAANQAECgMIAwAAAA==.Zegoo:BAAANQAECgIIBAAAAA==.Zendezit:BAAANQAECgIIAgAAAA==.Zenthura:BAAANQADCgIIAgABNQAECgcICgABAAAAAA==.Zenïca:BAAANQADCgUICQAAAA==.',
Zi='Zimbadah:BAAANQADCggIEwAAAA==.',
Zn='Znny:BAAANQAECgYICgAAAA==.',
Zy='Zynling:BAAANQABCgUIBQAAAA==.Zynpouch:BAAANQAECgYIDAAAAA==.',
['Áf']='Áfterlight:BAAANQADCgUIBQAAAA==.',
['Ár']='Árthas:BAAANQADCgMIAwAAAA==.',
['Âr']='Ârthas:BAAANQAECgQIBQAAAA==.',
['Çr']='Çrimes:BAAANQADCgcICQAAAA==.',
['Çu']='Çutty:BAAANQAECgMIBAAAAA==.',
['ßâ']='ßâßygirl:BAAANQADCgYIBgAAAA==.',
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
