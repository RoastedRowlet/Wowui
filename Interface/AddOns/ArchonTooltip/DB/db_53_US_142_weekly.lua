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

local lookup = {'Unknown-Unknown','Priest-Shadow',}
local provider = {region='US',realm="Lightning'sBlade",name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Abused:BAAANQADCgUIBQAAAA==.',
Ad='Adelaide:BAAANQAECgYICgABNQAECgQIBQABAAAAAA==.',
Ag='Aglovale:BAAANQAECgMIAwAAAA==.Agravaine:BAAANQADCgEIAQABNQAECgMIAwABAAAAAA==.',
Aj='Ajunlucky:BAAANQAECgUIBgAAAA==.',
Ak='Akuselgunk:BAAANQADCgcIDQAAAA==.',
Al='Alexari:BAAANQADCgUIBgAAAA==.Alnilam:BAAANQAECgEIAQAAAA==.',
Ar='Ardith:BAAANQABCgQIBQAAAA==.Arkveld:BAAANQAECgMIAwAAAA==.Aroxw:BAAANQAECgQIBAAAAA==.Arthritis:BAAANQABCgIIAgAAAA==.',
Ay='Aylinn:BAAANQADCgMIAwAAAA==.',
Ba='Ballsmasher:BAAANQADCgUIBQAAAA==.',
Be='Bearias:BAAANQADCgUIBQAAAA==.Bernarnold:BAAANQAECgQIBAAAAA==.Bettyspready:BAAANQADCgYICQAAAA==.',
Bi='Bigfart:BAAANQADCgUIBgAAAA==.Bigmanooshki:BAAANQADCgcIDwAAAA==.Bigpoppapump:BAAANQAECgEIAQAAAA==.Bigthumbb:BAAANQABCgEIAQAAAA==.Binnyi:BAAANQADCgcIDQAAAA==.',
Bl='Blackfoot:BAAANQAECgIIAgAAAA==.Blankjr:BAAANQADCgYICQAAAA==.Blindpov:BAAANQAECgcIDwAAAA==.',
Bo='Bouberry:BAAANQADCgcIBwAAAA==.Bounce:BAAANQADCgYIDAAAAA==.',
Br='Brabiant:BAAANQADCgYIBgAAAA==.Brake:BAAANQAECgEIAQAAAA==.Breakerr:BAAANQADCggIDQAAAA==.',
Bu='Bubbleaddict:BAAANQADCggIDgAAAA==.Bubbly:BAAANQAECgIIAgAAAA==.',
['Bë']='Bërshton:BAAANQADCgMIAwAAAA==.',
Ca='Caleris:BAAANQAECgEIAQAAAA==.Cattle:BAAANQAECgMIAwAAAA==.',
Cy='Cylic:BAAANQAECgQIBAAAAA==.Cyrùsdh:BAAANQADCgYIBgAAAA==.',
Da='Daddiestouch:BAAANQADCgUICQAAAA==.Dampundies:BAAANQADCgYIBgAAAA==.Dangerdream:BAAANQAECgYIBwAAAA==.Dankheals:BAAANQADCgYIBgAAAA==.Dantee:BAAANQAECgEIAQAAAA==.Daps:BAAANQADCgQIBAAAAA==.Datsmywife:BAAANQAECgQIBQAAAA==.Davis:BAAANQAECgMIBAAAAA==.Dayquill:BAAANQADCgYIBgAAAA==.',
De='Derpdragon:BAAANQAECgYICQAAAA==.Deviiarrc:BAAANQAECgYICgAAAA==.Devviarc:BAAANQADCgMIAwABNQAECgYICgABAAAAAA==.',
Dl='Dlamb:BAAANQADCgYICAAAAA==.',
Do='Dorik:BAAANQADCgEIAQAAAA==.Doroga:BAAANQAECgEIAQAAAA==.',
Dr='Dracar:BAAANQADCgcIDQAAAA==.Drmmrfist:BAAANQAECgEIAQAAAA==.',
Dw='Dwippietiggs:BAAANQAECgEIAQAAAA==.',
['Dä']='Däwntouchme:BAAANQADCgYIBgAAAA==.',
Ea='Easymac:BAAANQADCgIIAwABNQAECgEIAQABAAAAAA==.',
Ee='Eetee:BAAANQADCgYICgABNQADCggIDgABAAAAAA==.',
Em='Emoux:BAAANQADCgYIBgAAAA==.',
Ep='Epìx:BAAANQADCggIBgAAAA==.',
Er='Eralt:BAAANQADCgcIDQAAAA==.Ereye:BAAANQAECgQIBwAAAA==.',
Es='Esstina:BAAANQADCgMIAwAAAA==.Estuku:BAAANQAECgUIBgAAAA==.',
Et='Etatoned:BAAANQADCgQIBAABNQADCggIDgABAAAAAA==.Etengaged:BAAANQADCggIDgAAAA==.',
Ev='Evrae:BAAANQAECgQIBAAAAA==.',
Fa='Faithshand:BAAANQADCgcIDQAAAA==.',
Fe='Feio:BAAANQADCgQIBAAAAA==.',
Fi='Finkenator:BAAANQAFFAIIBAAAAA==.Finkler:BAAANQAECgcIDQABNQAFFAIIBAABAAAAAA==.Firedanny:BAAANQADCgQIAgAAAA==.Fistsofpeace:BAAANQAECgEIAQAAAA==.',
Fl='Flameshock:BAAANQAECgMIAwAAAA==.',
Fr='Friendshaped:BAAANQAECgMIAwAAAA==.Frigidbeach:BAAANQADCgcIBwAAAA==.',
Ga='Gamthor:BAAANQADCgUIBgAAAA==.',
Gl='Glaiveerror:BAAANQADCgYIDAAAAA==.Globoe:BAAANQAFFAEIAQAAAA==.Gloreb:BAAANQAFFAQIBAAAAA==.',
Go='Goomi:BAAANQADCgUIBgAAAA==.Gordef:BAAANQADCgcIDgAAAA==.Gotchabch:BAAANQADCgMIAwAAAA==.',
Gr='Grahz:BAAANQADCgYICAAAAA==.',
Gu='Gusto:BAAANQADCggIDAAAAA==.',
Ha='Harrowing:BAAANQAECgcIDgAAAA==.Haurt:BAAANQAECgEIAQAAAA==.',
He='Heavyhooves:BAAANQADCgYICgAAAA==.Hellful:BAAANQAECgEIAQAAAA==.Hemoladi:BAAANQAECgEIAQAAAA==.',
Hi='Hischier:BAAANQADCggIDgAAAA==.',
Ho='Holycri:BAAANQAECgQIBQAAAA==.Holymilkman:BAAANQABCgQIAgAAAA==.Hotdogramen:BAAANQADCgMIAwAAAA==.',
Hu='Hu:BAAANQADCggICAABNQAECgMIAwABAAAAAA==.',
['Hô']='Hôly:BAAANQAECgQIBAAAAA==.',
In='Insañe:BAAANQAECgcIBwAAAA==.Invi:BAAANQAECgMIAwAAAA==.',
Ja='Jabwingle:BAAANQADCgEIAQABNQADCggIEgABAAAAAA==.',
Ju='Juiice:BAAANQADCgcICgAAAA==.',
['Jë']='Jësus:BAAANQAECgIIAwAAAA==.',
Ka='Kalandaelis:BAAANQADCgcICwAAAA==.Kaldren:BAAANQADCgMIBAAAAA==.Kalel:BAAANQADCgYICgAAAA==.Karmakazie:BAAANQADCgQIBAAAAA==.Katasha:BAAANQADCgYIBgAAAA==.Kazraghand:BAAANQAECgEIAQAAAA==.',
Ke='Kei:BAAANQAECgUICAAAAA==.Kelsio:BAAANQAECgQIBQAAAA==.Kess:BAAANQADCgIIAgAAAA==.Keyboardcatt:BAAANQADCgYICwAAAA==.',
Kh='Kharos:BAAANQAECgUICAAAAA==.',
Ki='Kinks:BAAANQADCgcIDQAAAA==.Kirkoth:BAAANQADCgMIAwAAAA==.',
Kn='Knuts:BAAANQAECgUIBQAAAA==.',
Ko='Korialz:BAAANQADCgYIAQAAAA==.Kowtagion:BAAANQAECgQIBQAAAA==.',
Kr='Krelsh:BAAANQAECgYICQAAAA==.Krostikard:BAAANQADCgcICwAAAA==.',
Ku='Kumquat:BAAANQADCgYIBgAAAA==.Kungfudegru:BAAANQAECgEIAQAAAA==.',
Ky='Kyruutos:BAAANQADCgUIBQAAAA==.',
['Kí']='Kítkat:BAAANQAECgIIAgAAAA==.',
Le='Leibowitzy:BAAANQAECgEIAQAAAA==.Letra:BAAANQADCgMIAwAAAA==.',
Li='Lidela:BAAANQADCgIIAgAAAA==.Lightshax:BAAANQAECgEIAQAAAA==.Lilchow:BAAANQADCgMIAwAAAA==.Linedra:BAAANQADCggIDwAAAA==.',
Lo='Loreena:BAAANQADCgEIAQAAAA==.',
Lu='Luckydog:BAAANQADCgMIBAABNQADCggIDwABAAAAAA==.Ludey:BAAANQAECgQIBAAAAA==.Lutray:BAAANQADCgcIDQAAAA==.',
Ma='Maomao:BAAANQAECgQIBQAAAA==.Marodd:BAAANQADCgcIDQAAAA==.Mashîra:BAAANQAECgQIBAAAAA==.Mattsz:BAAANQADCgYIBwABNQADCggIDQABAAAAAA==.',
Me='Meanmachine:BAAANQADCgEIAQAAAA==.Meatwangs:BAAANQAECgMIAwAAAA==.Merihem:BAAANQADCgIIAgAAAA==.Mewfasa:BAAANQADCggICAAAAA==.',
Mi='Minasuzune:BAAANQADCgcIDQAAAA==.Minus:BAAANQADCgIIAgAAAA==.',
Mo='Moondotter:BAAANQADCgYICAAAAA==.Moonslayer:BAAANQADCgcICwAAAA==.Moovefool:BAAANQADCgYICgAAAA==.',
['Mã']='Mãshîrã:BAAANQADCggICAABNQAECgQIBAABAAAAAA==.',
['Må']='Måshîrå:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.',
Na='Nakor:BAAANQADCgYIBgAAAA==.Nalian:BAAANQADCgQIBAABNQADCgcIBwABAAAAAA==.Nalliella:BAAANQADCgcIDQAAAA==.',
Ne='Neenzy:BAAANQADCgEIAQAAAA==.Nefeli:BAAANQAECgQIBAAAAA==.Nelinne:BAAANQADCgYICAAAAA==.Nestia:BAAANQADCgYICQAAAA==.Never:BAAANQAECgcIDAAAAA==.',
Ni='Nightshade:BAAANQAECgQIBAAAAA==.Nix:BAAANQABCgMIAQAAAA==.',
Oc='Ocllo:BAAANQADCgcIDQAAAA==.',
Oj='Ojo:BAAANQADCgUIBQAAAA==.',
On='Oniana:BAAANQAECgMIAwAAAA==.',
Ow='Owwmyballs:BAAANQADCgMIAwAAAA==.',
Oz='Ozygo:BAAANQADCgYIBgAAAA==.',
Pa='Pagamas:BAAANQAECgUIBwAAAA==.Palandari:BAAANQADCgEIAQAAAA==.Pandawan:BAAANQABCgIIAgAAAA==.Panter:BAAANQADCgYICQAAAA==.',
Pe='Pebble:BAAANQADCgcIBwAAAA==.',
Ph='Phodoe:BAAANQADCgcIDQAAAA==.',
Pi='Pinquisitor:BAAANQADCgEIAQABNQABCgIIAgABAAAAAA==.',
Po='Pokeureyeout:BAAANQADCgUICgAAAA==.',
Pr='Prodyne:BAAANQAECgQIBAAAAA==.',
['Pî']='Pîlot:BAAANQADCgQIBAABNQADCgUICQABAAAAAA==.',
Qu='Quag:BAAANQADCgUIBQAAAA==.Quiettreader:BAAANQAECgEIAQAAAA==.Quokka:BAAANQAECgIIAwAAAA==.',
Ra='Raegwin:BAAANQADCgIIAgAAAA==.Raidboss:BAAANQADCgcIDQAAAA==.',
Re='Redeath:BAAANQADCgYICQAAAA==.Redirect:BAAANQADCgUIBQABNQADCgYICQABAAAAAA==.Redonculous:BAAANQAECgEIAQAAAA==.Redpool:BAAANQAECgQIBQAAAA==.Rehvenge:BAAANQADCgEIAQAAAA==.Rektroll:BAAANQAECgIIAgAAAA==.Revansong:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.Reymnant:BAAANQADCgMIAwAAAA==.',
Ro='Ronx:BAAANQADCgEIAQAAAA==.Roxxiloxxi:BAAANQAECgMIAwAAAA==.',
Ru='Rudeboy:BAAANQADCgYIBgAAAA==.',
Sa='Sabria:BAAANQAECgQIBAAAAA==.Sahria:BAAANQADCgUIBwAAAA==.Sarhia:BAAANQABCgEIAQAAAA==.Savanari:BAAANQAECgEIAQABNQABCgIIAgABAAAAAA==.',
Sc='Schizadin:BAAANQADCgYIBgAAAA==.Schnoze:BAAANQADCgcIDAAAAA==.',
Se='Sebekuul:BAAANQADCgYIBgAAAQ==.Selys:BAAANQAECgYICgAAAA==.Sence:BAAANQABCgQIBAAAAA==.Sephurik:BAAANQAFFAIIAgAAAA==.',
Sh='Shadowwife:BAAANQADCgYIBgAAAA==.Shamaneez:BAAANQABCgEIAQAAAA==.Shanamana:BAAANQADCgcICAAAAA==.Shiestee:BAAANQADCgcICwAAAA==.Shiriax:BAAANQADCgcIBwAAAA==.',
Si='Sikanda:BAAANQADCgMIAwABNQAECgMIAwABAAAAAA==.Silvea:BAAANQADCggICAAAAA==.Sinara:BAAANQAECgEIAQAAAA==.Sion:BAAANQAECgMIAwAAAA==.Sithlordz:BAAANQADCgYICQAAAA==.',
Sk='Sky:BAAANQADCggICAAAAA==.Skyelf:BAAANQAECgEIAQAAAA==.',
Sl='Sloppysloosh:BAAANQADCgMIAwAAAA==.',
Sm='Smallpox:BAAANQADCgUICwAAAA==.',
Sn='Snooflepoof:BAAANQAECgQIBAAAAA==.',
So='Socks:BAAANQADCgUIBQAAAA==.Solunara:BAAANQADCgUIBQABNQADCgcIBwABAAAAAA==.',
Sp='Spectrecles:BAAANQAECgUIBwAAAA==.Speez:BAAANQADCgYICwAAAA==.',
St='Stablehand:BAAANQADCggICwAAAA==.Steve:BAAANQAFFAEIAgAAAA==.Stonedfel:BAAANQAECgEIAQAAAA==.',
Su='Sunhoof:BAAANQADCgcIBwAAAA==.',
['Sø']='Sørrow:BAAANQADCgYICAAAAA==.',
Ta='Tabi:BAAANQADCgcIDQAAAA==.',
Te='Test:BAAANQADCggIBgAAAA==.',
Th='Thedayman:BAAANQADCggICAAAAA==.Thetaint:BAAANQAECgMIAwAAAA==.',
Ti='Tinee:BAAANQADCgQIBAAAAA==.Tinket:BAAANQAECgQIBQAAAA==.',
Tr='Trentlock:BAAANQAECgUIBQAAAA==.',
Ty='Tynisa:BAAANQADCgIIAgAAAA==.',
Un='Unstablesha:BAAANQADCgYIBgAAAA==.',
Va='Varandar:BAAANQAECgUIBQAAAA==.',
Vi='Vil:BAABNQAFFIEGAAICAAUJiyMIAAAmAgACAAUJiyMIAAAmAgAAAA==.Vilonus:BAAANQADCgYIDAAAAA==.',
Vo='Voidbwoy:BAAANQADCgYICwAAAA==.Voy:BAAANQADCggIDQAAAA==.',
Vu='Vulpes:BAAANQABCgEIAQAAAA==.Vurx:BAAANQAECgEIAQAAAA==.',
Wi='Williie:BAAANQADCgYIBgAAAA==.',
Wu='Wuoshi:BAAANQAECgEIAQAAAA==.Wuuzzyy:BAAANQAECgIIAgAAAA==.',
Xa='Xaliko:BAAANQADCgcIDQAAAA==.Xanbaran:BAAANQAECgQIBAAAAA==.',
Xy='Xyrtrew:BAAANQAECgYICgAAAA==.',
Yu='Yuki:BAAANQADCgYIBgAAAA==.',
Za='Zambesi:BAAANQADCgcIBwAAAA==.Zaradinna:BAAANQADCgEIAQAAAA==.Zartini:BAAANQAECgIIAgAAAA==.',
['Âk']='Âkaeus:BAAANQADCgUIBQAAAA==.',
['Ïn']='Ïnø:BAAANQADCgYIBgAAAA==.',
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
