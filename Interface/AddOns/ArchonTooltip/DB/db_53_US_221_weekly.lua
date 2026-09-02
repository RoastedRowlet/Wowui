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

local lookup = {'Unknown-Unknown',}
local provider = {region='US',realm='Thunderlord',name='US',type='weekly',zone=53,date='2026-09-01',data={Aa='Aaliyah:BAAANQAECgUICQAAAA==.',
Ab='Abyssknight:BAAANQADCggIDgAAAA==.',
Ac='Acesso:BAAANQADCgYIDAAAAA==.',
Ad='Adeonus:BAAANQADCgYIDAAAAA==.Adraydenn:BAAANQADCggIDwABNQAECgIIAgABAAAAAA==.',
Ae='Aecheron:BAAANQADCgcIDAABNQAECgMIAwABAAAAAA==.',
Ag='Aggrocrack:BAAANQADCggIFAAAAA==.',
Ah='Ahngus:BAAANQADCgcIDQAAAA==.',
Ai='Air:BAAANQADCgcIDAAAAA==.',
Al='Alexhunt:BAAANQAECgYICQAAAA==.Alplarn:BAAANQADCgIIAwAAAA==.Althsar:BAAANQADCgEIAQAAAA==.',
An='Anitwa:BAAANQAECgEIAQABNQAECgYICQABAAAAAA==.Anomari:BAAANQADCgUIBQAAAA==.',
Ap='Apkuggull:BAAANQAECgEIAQAAAA==.Appeal:BAAANQADCgMIAwAAAA==.',
Ar='Arandiel:BAAANQAECgQIBAAAAA==.Aranina:BAAANQADCgYICAAAAA==.Arcturrus:BAAANQADCgYICgAAAA==.Arel:BAAANQAECgYIDAAAAA==.Arkayist:BAAANQAECgEIAQAAAA==.Arrwyn:BAAANQADCgIIAgABNQADCgQIBAABAAAAAA==.Arter:BAAANQAECgEIAQABNQAECgMIBQABAAAAAA==.Aryhm:BAAANQAECgEIAQAAAA==.',
As='Asatralth:BAAANQAECgIIAgAAAA==.Asguard:BAAANQADCgYIDgAAAA==.Asheryo:BAAANQABCgMIAwAAAA==.Assphyxiate:BAAANQADCgYICwAAAA==.',
Au='Automagic:BAAANQAECgQIBQAAAA==.',
Ay='Aymine:BAAANQADCggIDgAAAA==.',
Ba='Babihotdog:BAAANQAECgEIAQAAAA==.Badwolff:BAAANQADCgcIBwAAAA==.Baerog:BAAANQADCgcIDAAAAA==.Banf:BAAANQAECgIIAwAAAA==.Baodabao:BAAANQAECgYICwAAAA==.Basicblends:BAAANQAECgQIBAAAAA==.',
Bb='Bblglizzy:BAAANQADCgEIAQAAAA==.',
Be='Beefglizzy:BAAANQAECgYIBgAAAA==.Beelzaboot:BAAANQAECgEIAQAAAA==.Belanor:BAAANQAECgIIAgAAAA==.Berry:BAAANQAECgYICAAAAA==.',
Bi='Bigbahungas:BAAANQADCggICgAAAA==.Bigchudifer:BAAANQADCgQIBAABNQAECgYICQABAAAAAA==.Bigdamfury:BAAANQADCgYIBgAAAA==.Bignipsmcgee:BAAANQAECgEIAQAAAA==.Bigthunder:BAAANQADCgUIBQAAAA==.Binkalul:BAAANQADCgUIBQAAAA==.Biolimit:BAAANQAECgYIBAAAAA==.',
Bl='Blacktastic:BAAANQADCgYIDAAAAA==.Blastee:BAAANQAECgQIBQAAAA==.Blath:BAAANQADCggIDwAAAA==.Blazius:BAAANQAECgEIAQAAAA==.Bleebles:BAAANQADCgMIAwAAAA==.Blitzkregmag:BAAANQADCgEIAQAAAA==.',
Bo='Bobertl:BAAANQAECgQIBgAAAA==.Boomnecrotic:BAAANQADCgYIBgAAAA==.Boonney:BAAANQADCgYIBgAAAA==.',
Br='Breathboy:BAAANQADCgYIBwAAAA==.Bronder:BAAANQADCgMIBQAAAA==.Bronzehoofs:BAAANQADCgMIBAAAAA==.',
Bu='Bubblemews:BAAANQADCgQIAwAAAA==.Bullwinklee:BAAANQABCgMIAwAAAA==.Burghmaul:BAAANQADCggIDgAAAA==.',
Ca='Cahri:BAAANQADCgQICAAAAA==.Calenesandra:BAAANQAECgEIAQAAAA==.Canon:BAAANQADCgcIDAAAAA==.Capodost:BAAANQADCgEIAQAAAA==.',
Ce='Celasong:BAAANQADCgEIAQAAAA==.Celestialhex:BAAANQABCgIIAgAAAA==.Ceree:BAAANQADCgUIBQAAAA==.',
Ch='Chimeranzomb:BAAANQADCgQIBAAAAA==.Chiwi:BAAANQADCgYIAwAAAA==.Chocogeta:BAAANQADCgYICwAAAA==.Chì:BAAANQADCgEIAQAAAA==.',
Cl='Cladie:BAAANQADCgQIBAAAAA==.Cladoe:BAAANQADCgEIAQAAAA==.Cladow:BAAANQAECgQIBQAAAA==.Clag:BAAANQADCgIIAgAAAA==.',
Co='Cogblock:BAAANQAECgMIBAAAAA==.Conqor:BAAANQAECgQIBAAAAA==.',
Cr='Cronosphere:BAAANQADCgcIEAAAAA==.Crushaturty:BAAANQADCgMIAwAAAA==.',
Cu='Cubes:BAAANQADCgUIBQAAAA==.',
Cy='Cyndrainna:BAAANQABCgMIBAAAAA==.Cyndrin:BAAANQADCggICgAAAA==.',
Da='Daddyglock:BAAANQADCgEIAQAAAA==.Daerper:BAAANQADCgcIBwABNQADCggIDAABAAAAAA==.Danayro:BAAANQADCgQIBAAAAA==.Darklego:BAAANQAECgcIDQAAAA==.Darksign:BAAANQADCgIIAgAAAA==.Davemage:BAAANQADCgcIDAAAAA==.Dawnbringer:BAAANQAECgIIBAAAAA==.',
De='Deaddhunter:BAAANQADCgEIAQAAAA==.Deaddmage:BAAANQADCgUIBQAAAA==.Deadlylight:BAAANQADCgYIBgAAAA==.Delillama:BAAANQAECgIIAgAAAA==.Destnny:BAAANQADCggICQAAAA==.Destrohunter:BAAANQADCgcIBwAAAA==.Destroker:BAAANQADCggIEAAAAA==.',
Dh='Dhspudd:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Di='Dillpo:BAAANQABCgMIAwAAAA==.Dioress:BAAANQADCgUIBQAAAA==.Dis:BAAANQAECgYICAABNQAECggIDwABAAAAAA==.Disyx:BAAANQADCgUIBQAAAA==.Diyanå:BAAANQAECgQIBQAAAA==.',
Do='Domainz:BAAANQADCggICAAAAA==.Dommymommie:BAAANQADCgMIAwAAAA==.Donzm:BAAANQADCgcIBgABNQAECgYICgABAAAAAA==.Donzw:BAAANQAECgYICgAAAA==.Dorkwaffle:BAAANQADCgIIAgAAAA==.',
Dr='Dracthick:BAAANQADCgEIAQAAAA==.Dragun:BAAANQADCgEIAQAAAA==.Draxxor:BAAANQADCgQIBAAAAA==.Dreamender:BAAANQADCggIBQAAAA==.Droknor:BAAANQADCgQICAAAAA==.Druidllama:BAAANQAECgMIAwAAAA==.Drumin:BAAANQAECgUICAAAAA==.',
Dw='Dwarvanhand:BAAANQAECgcIDQAAAA==.',
['Dæ']='Dærper:BAAANQADCggIDAAAAA==.',
Ea='Earthmender:BAAANQADCgEIAQAAAA==.Eatmacookie:BAAANQADCgYICQAAAA==.',
El='Elazar:BAAANQAECgIIAgAAAA==.Elemenope:BAAANQADCgYICgAAAA==.Elguasonbb:BAAANQADCgUICAAAAA==.Elidori:BAAANQADCgMIAwAAAA==.',
Em='Emashasha:BAAANQADCgQIBAAAAA==.Emitlyght:BAAANQADCggIEQAAAA==.',
En='Eniri:BAAANQADCgIIAgAAAA==.Enyeto:BAAANQAECgMIBQAAAA==.',
Er='Eroviaevia:BAAANQADCgYIBwAAAA==.',
Eu='Eunomia:BAAANQAECgQICAAAAA==.',
Ex='Exra:BAAANQADCgQIAwAAAA==.',
Ez='Ezekeel:BAAANQAECgMIAwAAAA==.Ezoghoul:BAAANQAECgEIAQAAAA==.',
Fa='Fakelock:BAEANQADCgMIAwABNQADCggICwABAAAAAA==.Fakendruid:BAEANQADCggICwAAAA==.Fauxx:BAAANQADCgUIBQAAAA==.',
Fe='Felfae:BAAANQADCgYIBwAAAA==.',
Fi='Filip:BAAANQADCgEIAQAAAA==.',
Fl='Flamefenix:BAAANQADCgUIBQAAAA==.Flumpy:BAAANQAECgQIBQAAAA==.Flurpymcdoof:BAAANQADCgIIAgAAAA==.',
Fo='Folken:BAAANQAECgEIAQAAAA==.Foodtruck:BAAANQADCggIDwAAAA==.Forbiddyn:BAAANQAECgcIDAAAAA==.Foxiefoxy:BAAANQADCgYICQAAAA==.',
Fr='Fraiser:BAAANQADCgQIBAABNQAECgMIBQABAAAAAA==.',
Fu='Fulgrum:BAAANQADCgIIAwAAAA==.Funkweave:BAEANQAECgIIAgAAAA==.Fupacabras:BAAANQADCgUIBgAAAA==.Furidas:BAAANQADCgYIDAAAAA==.',
['Fö']='Föxfïre:BAAANQADCgIIAgAAAA==.',
Ga='Garogg:BAAANQAECgIIAgAAAA==.Garotomoreno:BAAANQAECgQIBQAAAA==.Garrut:BAAANQADCggIDwAAAA==.',
Gi='Giirthquakee:BAAANQADCgYICgABNQAECgEIAQABAAAAAA==.Gimmage:BAAANQADCggICAAAAA==.',
Gl='Glorbruid:BAAANQADCggIDAAAAA==.',
Go='Gojosatóru:BAAANQAECgMIAwAAAA==.Goldenchef:BAAANQADCgYIBgAAAA==.Gotcowbell:BAAANQADCgcICAAAAA==.',
Gr='Grahnis:BAAANQADCgQIBgABNQADCgcICAABAAAAAA==.Grasswhistle:BAAANQAECgEIAQABNQAECgUIBwABAAAAAA==.Grayzor:BAAANQADCggIEAAAAA==.Greendust:BAAANQADCgYICQAAAA==.Greenperor:BAAANQAECgMIAwAAAA==.Grenthor:BAAANQADCgEIAQAAAA==.Grenvar:BAAANQAECgMIAwAAAA==.Grigdor:BAAANQAECgUIBwAAAA==.',
Gu='Guass:BAAANQAECgQIBQAAAA==.Gunbolt:BAAANQADCgcIBwAAAA==.',
['Gø']='Gøhåñ:BAAANQADCgYIBgAAAA==.',
['Gù']='Gùndèr:BAAANQAECgEIAQAAAA==.',
Ha='Hailrazor:BAAANQADCgIIAgAAAA==.Hakiry:BAAANQADCggIDwAAAA==.Hatrix:BAAANQADCgMIAwAAAA==.Haunt:BAAANQADCgYICAAAAA==.Hawkkaye:BAAANQADCgYICwAAAA==.Haze:BAAANQADCgcIBwAAAA==.Hazesamaa:BAAANQAECgYIDQAAAA==.',
He='Healsforfree:BAAANQADCgIIAgAAAA==.Healsgoodman:BAAANQADCgEIAgAAAA==.Hellviera:BAAANQADCgIIAgAAAA==.Hernog:BAAANQAECgIIAgAAAA==.Hexmenixy:BAAANQADCgYICwAAAA==.',
Hi='Hianu:BAAANQAECgEIAQAAAA==.Highlordhunt:BAAANQADCgUIBQAAAA==.',
Ho='Holabenjy:BAAANQADCgYICAAAAA==.Holybenjy:BAAANQADCgIIAgAAAA==.Holybibble:BAAANQADCgIIAgAAAA==.Holybox:BAAANQAECgEIAQAAAA==.Holyfady:BAAANQADCgIIAgAAAA==.Holyfenix:BAAANQAECgEIAQAAAA==.Holynixy:BAAANQADCgYIBgAAAA==.Holypaladinn:BAAANQADCgEIAQAAAA==.Holyzyn:BAAANQADCgYICgAAAA==.Hoonding:BAAANQADCgYIBgABNQAECgYIDQABAAAAAA==.Hordak:BAAANQADCgUIBwAAAA==.Horne:BAAANQADCgEIAQAAAA==.Hotstuffbaby:BAAANQADCgMIAwAAAA==.Hottodot:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.Howde:BAAANQADCggIDgAAAA==.Howdydoo:BAAANQADCgcIDAAAAA==.',
Hu='Hudini:BAAANQAECgQIBAAAAA==.Hushweaver:BAAANQADCgQIBgAAAA==.',
Hy='Hypal:BAAANQAECgEIAQABNQADCgMIAwABAAAAAA==.Hypd:BAAANQADCgMIAwAAAA==.Hypev:BAAANQAECgEIAQABNQADCgMIAwABAAAAAA==.Hypm:BAAANQADCgIIAgABNQADCgMIAwABAAAAAA==.Hyps:BAAANQAECgMIBwABNQADCgMIAwABAAAAAA==.Hypt:BAAANQADCgEIAQABNQADCgMIAwABAAAAAA==.',
Ia='Iakned:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.',
Ib='Ibichi:BAAANQADCgMIBAAAAA==.',
Ic='Icet:BAAANQAECgUIBQAAAA==.',
Il='Illshankya:BAAANQADCgYICAAAAA==.',
Im='Imihn:BAAANQADCgYICwAAAA==.',
In='Invìctús:BAAANQADCggIDgAAAA==.',
It='Ithir:BAAANQADCgUIBQAAAA==.Itsemma:BAAANQADCggIDwAAAA==.',
Iu='Iustitia:BAAANQABCgIIAgAAAA==.',
Iy='Iylara:BAAANQADCgYIDgAAAA==.',
Ja='Jaanus:BAAANQADCgMIAwAAAA==.Jackodm:BAAANQAECgYIBwAAAA==.Jad:BAAANQAECgEIAQAAAA==.Janicafae:BAAANQADCgMIAwAAAA==.Jareth:BAAANQABCgQIBwAAAA==.Jawo:BAAANQADCggIDwAAAA==.',
Je='Jeefberky:BAAANQADCgYIBgAAAA==.Jersey:BAAANQADCgQIBAAAAA==.Jetts:BAAANQAECgEIAQAAAA==.',
Jo='Johnnysinz:BAAANQAECgIIAgAAAA==.Johnnyzyns:BAAANQADCgIIAgAAAA==.Johnret:BAAANQAECgEIAQAAAA==.',
Jp='Jp:BAAANQAECgcICwAAAA==.',
Ju='Juno:BAAANQADCgUICQAAAA==.',
Ka='Kadester:BAAANQADCgEIAQAAAA==.Kaimen:BAAANQADCggIBwAAAA==.Kalipriest:BAAANQADCggIDgAAAA==.Kalipso:BAAANQADCgYICgAAAA==.Kamehameha:BAAANQADCgUIBwAAAA==.Kamwar:BAAANQAECggIDgABNQAFFAEIAQABAAAAAA==.Karideer:BAAANQADCgYICgAAAA==.Kaylax:BAAANQADCgYICwAAAA==.Kaylost:BAAANQADCgMIAwAAAA==.Kaylub:BAAANQADCggIDgAAAA==.Kazrim:BAAANQADCgQIBAAAAA==.',
Ke='Keldhar:BAAANQADCggIDgAAAA==.Kenparcell:BAAANQADCgUIBQAAAA==.Kerash:BAAANQADCgUICQAAAA==.Kevindk:BAAANQADCgYIBgAAAA==.Kevintt:BAAANQAECgUIBQAAAA==.Keys:BAAANQADCgYICgAAAA==.',
Ki='Killachefcjr:BAAANQADCgQIBAAAAA==.Kimori:BAAANQADCgUIBQAAAA==.',
Kn='Knugget:BAAANQAECgEIAQAAAA==.',
Ko='Kodiakhunter:BAAANQADCgcIBwAAAA==.Kodlighting:BAAANQADCgQIBgAAAA==.Koniqeo:BAAANQADCgYICgAAAA==.Koressme:BAAANQADCgYIBgAAAA==.Korlat:BAAANQADCgYIDAAAAA==.Kozdiniar:BAAANQAFFAEIAQAAAA==.Kozurai:BAAANQADCggICAABNQAFFAEIAQABAAAAAA==.',
Kr='Krëegz:BAAANQADCgMIAwAAAA==.Krëëgz:BAAANQADCgEIAQABNQADCgMIAwABAAAAAA==.',
Ku='Kugot:BAAANQADCggICAAAAA==.Kurupted:BAAANQADCggIDgAAAA==.',
Ky='Kydrea:BAAANQADCgYICQAAAA==.Kyne:BAAANQADCgYIBgAAAA==.Kynyselda:BAAANQADCgYIBgAAAA==.Kyrabear:BAAANQADCgQIBgAAAA==.',
['Kâ']='Kânê:BAAANQAECgEIAQAAAA==.',
La='Ladrón:BAAANQADCgYICQAAAA==.Larkos:BAAANQADCgYIBgAAAA==.Lassamyna:BAAANQADCgUIBQAAAA==.Latías:BAAANQAECgUIBgAAAA==.',
Le='Leechygos:BAAANQADCgcIBwAAAA==.Legenddairy:BAAANQADCgcIDAAAAA==.Leheo:BAAANQADCgEIAQAAAA==.Leigong:BAAANQADCgYIBgAAAA==.',
Li='Liani:BAAANQADCgIIAgAAAA==.Lickmyhorns:BAAANQAECgUICQAAAA==.Liendrah:BAEANQAECgYICgAAAA==.Lightmf:BAAANQAECgIIAgAAAA==.Lightninglip:BAAANQADCgUICAAAAA==.Lightwaves:BAAANQADCggIDQAAAA==.Lilet:BAAANQADCggIDgAAAA==.Lilitsune:BAAANQADCgcIDQAAAA==.Liotrix:BAAANQADCgYIBgABNQADCggICgABAAAAAA==.Liradel:BAAANQADCgIIAgAAAA==.Lisri:BAAANQAECgIIAgAAAA==.Lizolio:BAAANQADCggIDwAAAA==.',
Ll='Llomel:BAAANQADCgYIBwAAAA==.',
Lo='Lochlan:BAAANQADCgQIBwAAAA==.Lohhano:BAAANQABCgQIBQAAAA==.',
Lu='Lucianagi:BAAANQAECgMIBAAAAA==.Lussprodz:BAAANQADCgUIBQAAAA==.Luurg:BAAANQADCgcICQAAAA==.',
Ma='Mageunal:BAAANQADCgEIAQAAAA==.Magikkosa:BAAANQAECgQIBQAAAA==.Maibutzbrewy:BAAANQADCgQIBgAAAA==.Majamojopowa:BAAANQABCgQIBQAAAA==.Malekíth:BAAANQADCggIAgAAAA==.Manutters:BAAANQADCggICgAAAA==.Marrylanders:BAAANQAECgUICQAAAA==.Marrylock:BAAANQADCgUIBQAAAA==.Martiul:BAAANQAECgYICQAAAA==.Mayven:BAAANQADCgUIBQAAAA==.',
Me='Megapally:BAAANQADCgQIBAAAAA==.Mellie:BAAANQADCgMIAwAAAA==.Melmei:BAAANQADCgYICgAAAA==.Meriweather:BAAANQADCgYIDAAAAA==.Merlinajax:BAAANQADCgYIDAAAAA==.Meszyra:BAAANQAECgcICgAAAA==.',
Mi='Michaelcera:BAAANQAECgQIBQAAAA==.Mijuku:BAAANQAECgYIBwAAAA==.Mikehawk:BAAANQADCgcIDAAAAA==.Misoeternal:BAAANQADCgYIDAAAAA==.Mitchard:BAAANQAECgMIAwAAAA==.Mittenza:BAAANQADCgcIDQAAAA==.Mixelplix:BAAANQADCgYICwAAAA==.Mizstriss:BAAANQAECgUIBQAAAA==.',
Mo='Molari:BAAANQADCgMIAwAAAA==.Monksymeg:BAAANQADCgIIAgAAAA==.Monkwilbo:BAAANQADCgYIBgAAAA==.Moonfur:BAAANQADCgUIBwAAAA==.Mordath:BAAANQADCgYICwAAAA==.Mordoom:BAAANQAECgMIAwAAAA==.Morikai:BAAANQADCgYICgAAAA==.Morinn:BAAANQADCgUIBQAAAA==.Mosag:BAAANQAECgQIBQAAAA==.Moushou:BAAANQADCgcIBwAAAA==.',
Ms='Mspacman:BAAANQADCgYIBgAAAA==.',
Mu='Mudslide:BAAANQADCgUIBQAAAA==.Muffduster:BAAANQADCgUIBQAAAA==.Muffintopper:BAAANQAECgQIBgAAAA==.Muppie:BAAANQADCgMIBAAAAA==.Mutovenator:BAAANQADCgEIAQAAAA==.',
My='Mychef:BAAANQADCgUIBQAAAA==.Myrrha:BAAANQAECgUIBgAAAA==.',
['Mô']='Mônah:BAAANQADCgEIAQABNQADCgQIBAABAAAAAA==.',
Na='Nakiro:BAAANQADCgMIBgAAAA==.Namhanharal:BAAANQADCgUIBQAAAA==.Natch:BAAANQADCgUICgAAAA==.',
Ne='Nedilap:BAAANQAECgEIAQAAAA==.Nef:BAAANQAECgEIAQAAAA==.Neqousa:BAAANQADCgIIAgAAAA==.Nerbench:BAAANQABCgIIAgAAAA==.Nerdi:BAAANQADCgQIBAAAAA==.Nerokos:BAAANQADCgYIBgAAAA==.',
Ni='Nightx:BAAANQAECgEIAQAAAA==.Nitewang:BAAANQADCgQIBAAAAA==.Nitewing:BAAANQAECgcIDQABNQADCgQIBAABAAAAAA==.',
No='Noccs:BAAANQADCgYIBAAAAA==.Noctaro:BAEANQAECggIAQAAAA==.Nokona:BAAANQADCgQIBAAAAA==.Notpizza:BAAANQAECgMIAwABNQAECgcICAABAAAAAA==.',
Nu='Nuikha:BAAANQADCgYIBwAAAA==.Nukenfoobs:BAAANQADCgEIAQABNQAECgQIBgABAAAAAA==.',
Ny='Nyoazz:BAAANQADCgEIAQAAAA==.',
Ob='Obnixa:BAAANQAECgIIAwAAAA==.',
Op='Opithel:BAAANQAECgIIAgAAAA==.Opizerka:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.',
Or='Oriestus:BAAANQADCgEIAQAAAA==.Oriko:BAAANQADCggIDwAAAA==.Oríllas:BAAANQAECgIIAwAAAA==.',
Os='Osric:BAAANQADCgIIAgABNQAECgQIBQABAAAAAA==.',
Oy='Oyogo:BAAANQAECgYICgABNQAFFAEIAQABAAAAAA==.Oyogu:BAAANQADCgUIBQABNQAFFAEIAQABAAAAAA==.',
Pa='Paech:BAAANQADCgYIBgAAAA==.Pairädice:BAAANQADCgYIBgAAAA==.Paladane:BAAANQAECgEIAQAAAA==.Pallymorph:BAAANQADCgIIAgAAAA==.Palsdruid:BAAANQADCgQIBgAAAA==.Pamalinaa:BAAANQADCggICAAAAA==.Papanezz:BAAANQADCgQIBAAAAA==.Patapouf:BAAANQAECgEIAQAAAA==.Payback:BAAANQADCgEIAQAAAA==.',
Pe='Pearbandit:BAAANQADCgYIBgAAAA==.Pegully:BAAANQAECgEIAQAAAA==.',
Ph='Phephraan:BAAANQAECgEIAQAAAA==.Phinehas:BAAANQADCgYICgAAAA==.Phwaz:BAAANQADCgYICwAAAA==.Phyxyzin:BAAANQADCgUIBwAAAA==.',
Pi='Piddles:BAAANQABCgQIBgAAAA==.Pinchebean:BAAANQADCgIIAgAAAA==.Pinktress:BAAANQADCgcIDQAAAA==.Pizzadough:BAAANQAECgcICAAAAA==.',
Pl='Plskillmie:BAAANQAECgIIAgAAAA==.',
Po='Possecutor:BAAANQAECgcIDQAAAA==.Pownadin:BAAANQADCgQIBQAAAA==.',
Pr='Prabis:BAAANQADCgUIBQAAAA==.Pryîto:BAAANQADCgYICgAAAA==.',
Pu='Pumachaka:BAAANQADCgcIBwAAAA==.Pushinp:BAAANQADCgQIBAAAAA==.',
Py='Pyresia:BAAANQADCgYICgAAAA==.',
Qu='Quackshot:BAAANQAECgIIAgAAAA==.',
Qw='Qwertysquid:BAAANQADCgEIAQAAAA==.',
Ra='Raegen:BAEANQADCgQIBAABNQAECggIAQABAAAAAA==.Raezer:BAEANQADCggICAABNQAECggIAQABAAAAAA==.Raikomori:BAAANQADCgYIBgAAAA==.Ranare:BAAANQAECgEIAQAAAA==.Ratonfusse:BAAANQABCgQIBAAAAA==.Ravenhart:BAAANQADCgEIAgAAAA==.Raxmanus:BAAANQADCgYIDAAAAA==.',
Re='Readthebible:BAAANQADCgIIAgAAAA==.Redvelvett:BAAANQADCgcIDAAAAA==.Reilini:BAAANQAECgYIBAAAAA==.Remedium:BAAANQABCgQIBgAAAA==.Renascor:BAAANQADCgcIBwABNQAECgcICgABAAAAAA==.',
Rh='Rhojin:BAAANQADCgcICgAAAA==.',
Ri='Rikimaruu:BAAANQADCgcIDgAAAA==.Rinaari:BAAANQADCgUIBQAAAA==.',
Ro='Rockethunt:BAAANQAECgMIAwAAAA==.Rokurota:BAAANQADCgUIBwAAAA==.Royalborn:BAAANQAECgEIAQAAAA==.',
Ru='Rubikon:BAAANQAECgEIAQAAAA==.Rueldalf:BAAANQADCgYICQAAAA==.Ruïn:BAAANQADCggIDwAAAA==.',
Sa='Salidan:BAAANQADCgMIAwAAAA==.Samlock:BAAANQAECgUICQAAAA==.Sap:BAAANQAECgUICQAAAA==.Satyrlord:BAAANQADCgYIDAAAAA==.Savella:BAAANQADCgcIDgAAAA==.',
Sc='Scarletblade:BAAANQAECgMIBAAAAA==.Schamwoww:BAAANQADCgYICwAAAA==.Sclas:BAAANQADCgIIAgAAAA==.Scubar:BAAANQADCgYIBgAAAA==.',
Se='Seafox:BAAANQABCgQIBQAAAA==.Sear:BAAANQAECgIIAgAAAA==.Selest:BAAANQADCgEIAQAAAA==.Seraphiina:BAAANQADCgcIBwAAAA==.',
Sh='Shamiam:BAAANQADCgUIBQAAAA==.Shamozmo:BAAANQADCgMIAgAAAA==.Shineup:BAAANQADCggICAAAAA==.Shockkor:BAAANQADCgcIDQAAAA==.Shockujin:BAAANQADCgcICwABNQAECgYICgABAAAAAA==.Shox:BAAANQADCgMIAwAAAA==.Shý:BAAANQADCgIIAgAAAA==.',
Si='Silanris:BAAANQADCgQICAAAAA==.Sitaana:BAAANQADCgcIBwAAAA==.',
Sk='Skillr:BAAANQADCgYICgAAAA==.Skyekníght:BAAANQADCggICgAAAA==.',
Sl='Sleezyaf:BAAANQAECgQIBAAAAA==.Slermp:BAAANQADCgYIBgAAAA==.Slicett:BAAANQADCgMIAwAAAA==.Slowcase:BAAANQAECgQIBwAAAA==.',
Sm='Smoochem:BAAANQADCggICAAAAA==.',
Sn='Sneaze:BAAANQADCgUIBQAAAA==.',
So='Socketss:BAAANQADCggICAAAAA==.Sohjinra:BAAANQAECgEIAQAAAA==.Sollaria:BAAANQADCgMIAwAAAA==.Sololvling:BAAANQADCggIDgAAAA==.Sovereign:BAAANQAECgcIDQAAAA==.',
Sp='Sp:BAAANQADCgIIAgAAAA==.Sparkleclaws:BAAANQADCgUIBgAAAA==.Sparkycleave:BAAANQADCgYICwAAAA==.Spookyloops:BAAANQAECgIIAgAAAA==.',
Ss='Sslipknot:BAAANQADCgEIAQAAAA==.',
St='Stealthfire:BAAANQAECgUIBwAAAA==.Sterny:BAAANQADCgYIBgAAAA==.Stidetroll:BAAANQADCgYIDAAAAA==.Stormstrikes:BAAANQADCgcIDAAAAA==.Stromdin:BAAANQADCggIDwAAAA==.',
Su='Sugaboomboom:BAAANQADCgYIBgAAAA==.Sumo:BAAANQABCgIIAgAAAA==.Sunarr:BAAANQAECgEIAQAAAA==.Sunkenlily:BAAANQADCgQIBAAAAA==.Superace:BAAANQAECgcIBwAAAA==.Surlee:BAAANQADCgYIBAAAAA==.Surlydude:BAAANQADCgEIAQAAAA==.Suule:BAAANQADCgUIBwAAAA==.',
Sw='Swiffys:BAAANQAECgEIAQAAAA==.Swissy:BAAANQADCgQIBAAAAA==.Swordnoob:BAAANQAECgEIAQAAAA==.',
Sy='Synkadevour:BAAANQADCgYICAAAAA==.Synkareaper:BAAANQADCgQIBgABNQADCgYICAABAAAAAA==.',
Ta='Taappy:BAAANQAECgEIAQAAAA==.Taggs:BAAANQADCgYICgAAAA==.Taggsy:BAAANQADCgEIAQAAAA==.Tail:BAAANQADCggIDwAAAA==.Tails:BAAANQADCgMIBgAAAA==.Tajomaru:BAAANQADCgIIAgAAAA==.Tanmand:BAAANQADCgYICwAAAA==.Tanthora:BAAANQADCgMIAwAAAA==.Tao:BAAANQADCgMIAwAAAA==.Tauri:BAAANQADCgMIBQAAAA==.',
Te='Tenebris:BAAANQADCgUIBgAAAA==.Terrycrews:BAAANQADCgcICwAAAA==.',
Th='Thasper:BAAANQABCgEIAQAAAA==.Thebigkodiak:BAAANQADCgYIBgAAAA==.Thebutler:BAAANQADCgYIBgABNQAECgcIDQABAAAAAA==.Thegrimus:BAAANQAECgQIBAAAAA==.Thekeres:BAAANQADCgUICQAAAA==.Thickums:BAAANQADCgEIAQAAAA==.Thornwhisper:BAAANQADCgcIBwAAAA==.Throh:BAAANQADCgIIAgAAAA==.Thussy:BAAANQAECgEIAQAAAA==.',
Ti='Timøthy:BAAANQAECgIIAwAAAA==.',
Tk='Tkaniaa:BAAANQADCgQIBAAAAA==.',
To='Tokeyes:BAAANQADCgMIBAAAAA==.Tossdirt:BAAANQAECggIDwAAAA==.Toxle:BAAANQADCgYIBgAAAA==.Toysruskid:BAAANQADCgIIAgAAAA==.',
Tr='Trakshot:BAEANQAECggICwABNQAECgYIBwABAAAAAA==.Trippdaddy:BAAANQAECgIIAgAAAA==.',
Tu='Tuckford:BAAANQADCgEIAQAAAA==.',
Tw='Twiz:BAAANQADCgEIAQAAAA==.',
Tx='Txcreekwoo:BAAANQADCgEIAQAAAA==.',
Ty='Typhal:BAAANQAECgUICAAAAA==.Typo:BAAANQADCgEIAQAAAA==.',
Uh='Uhtain:BAAANQADCgYIDAABNQADCgYICwABAAAAAA==.Uhtan:BAAANQADCgYICwAAAA==.',
Un='Uncleklaus:BAAANQAECgQIBAAAAA==.Ungnite:BAAANQAECgEIAQAAAA==.Unikorn:BAAANQADCgEIAQAAAA==.',
Ur='Urthron:BAAANQADCggIDAAAAA==.',
Us='Ushiamdi:BAAANQAECgQIBAAAAA==.',
Ut='Utaan:BAAANQADCgYIDAABNQADCgYICwABAAAAAA==.',
Va='Vaiel:BAAANQADCgcICAAAAA==.Valanthé:BAAANQADCgIIAgAAAA==.',
Ve='Veluna:BAAANQABCgMIAwABNQAECgYIDAABAAAAAA==.Veravvang:BAAANQAECgMIAwABNQADCggICAABAAAAAA==.Veroshia:BAAANQADCgYICwAAAA==.Vexea:BAAANQAECgMIBAABNQAECgQIBQABAAAAAA==.Vexx:BAAANQADCgcIDAAAAA==.',
Vh='Vhail:BAAANQADCgMIBQAAAA==.',
Vi='Virali:BAAANQAECgQIBAAAAA==.Virussuckss:BAAANQADCgcIBgAAAA==.Vispper:BAAANQAECgQIBAAAAA==.Viyinx:BAAANQADCgYIBgABNQAECgUIBgABAAAAAA==.',
Vk='Vkdk:BAAANQADCgYIBgAAAA==.',
Vo='Vorel:BAAANQADCgYIBgAAAA==.',
Vp='Vpung:BAAANQADCgMIBgAAAA==.',
Vy='Vyllin:BAAANQAECgQIBQAAAA==.Vynarran:BAAANQAECgQIBAAAAA==.',
Wa='Watchdodo:BAAANQADCgUIDQAAAA==.Wax:BAAANQADCgQIBAAAAA==.',
We='Weebscum:BAAANQAECgUICQAAAA==.',
Wi='Willowblessu:BAAANQAECgYICAAAAA==.Willòw:BAAANQADCgEIAQAAAA==.Windler:BAAANQADCgEIAQAAAA==.Wisha:BAAANQADCgEIAQAAAA==.',
Wo='Wojiaonl:BAAANQADCgEIAQAAAA==.Wolty:BAAANQADCgQIBwAAAA==.Wovenxlight:BAEANQAECgQIBAAAAA==.',
Wr='Wrathin:BAAANQADCgYIBgAAAA==.',
Xa='Xaeora:BAAANQADCgYIBgAAAA==.',
Xe='Xeona:BAAANQADCgMIBQAAAA==.Xesolyt:BAAANQADCgMIAwAAAA==.',
Ye='Yeahbrother:BAAANQADCgIIAgAAAA==.Yeralt:BAAANQADCgEIAQAAAA==.',
Yo='Yoshikawa:BAAANQAECgUICAAAAA==.',
Za='Zaivama:BAAANQADCgMIAgAAAA==.Zandren:BAAANQADCgYICgAAAA==.Zaranthari:BAAANQADCgMIAwAAAA==.Zarindela:BAAANQAECgcICgAAAA==.',
Ze='Zeenalizard:BAAANQADCgIIAgABNQADCggIDwABAAAAAA==.Zegoo:BAAANQAECgEIAQAAAA==.Zendezit:BAAANQADCggIDgAAAA==.Zenthura:BAAANQADCgIIAgABNQAECgcICgABAAAAAA==.Zenïca:BAAANQADCgUIBQAAAA==.',
Zi='Zimbadah:BAAANQADCgYICwAAAA==.',
Zn='Znny:BAAANQAECgQIBAAAAA==.',
Zy='Zynling:BAAANQABCgEIAQAAAA==.Zynpouch:BAAANQAECgQIBgAAAA==.',
['Áf']='Áfterlight:BAAANQADCgUIBQAAAA==.',
['Âr']='Ârthas:BAAANQAECgEIAQAAAA==.',
['Çr']='Çrimes:BAAANQADCgQIBAAAAA==.',
['Çu']='Çutty:BAAANQADCgIIAgAAAA==.',
['ßâ']='ßâßygirl:BAAANQADCgEIAQAAAA==.',
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
