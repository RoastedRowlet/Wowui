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

local lookup = {'Unknown-Unknown','DemonHunter-Havoc','DemonHunter-Devourer','Mage-Arcane','Evoker-Augmentation','Evoker-Devastation','Monk-Windwalker','Paladin-Holy','Warlock-Demonology','Warlock-Destruction','Shaman-Elemental','Priest-Shadow',}
local provider = {region='US',realm="Lightning'sBlade",name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abused:BAAANQADCgUIBQAAAA==.',
Ad='Adelaide:BAAANQAECgcIDwABNQAECgYICwABAAAAAA==.',
Ag='Aglovale:BAAANQAECgQIBwAAAA==.Agravaine:BAAANQADCgEIAQABNQAECgQIBwABAAAAAA==.',
Aj='Ajunlucky:BAAANQAECgcIDQAAAA==.',
Ak='Akuselgunk:BAAANQADCgcIDQAAAA==.',
Al='Alexari:BAAANQADCggICwAAAA==.Alnilam:BAAANQAECgQIBQAAAA==.Alphonse:BAAANQADCgUIBQAAAA==.',
Ar='Arbys:BAAANQADCgMIAwAAAA==.Arcos:BAAANQADCgUIBQAAAA==.Ardith:BAAANQABCgQIBQAAAA==.Arkveld:BAAANQAECgQIBgAAAA==.Armados:BAAANQADCgQIBAAAAA==.Aroxw:BAAANQAECgUICQAAAA==.Arthritis:BAAANQABCgIIAgAAAA==.',
At='Athineana:BAAANQABCgIIAwAAAA==.',
Ay='Aylinn:BAAANQAECgQIBAAAAA==.Aylira:BAAANQAECgEIAQAAAA==.',
Az='Azulas:BAAANQADCgMIAwABNQADCggICwABAAAAAA==.',
Ba='Balfas:BAAANQADCgQIBAABNQAECgYICgABAAAAAA==.Ballsmasher:BAAANQADCggIDQAAAA==.',
Be='Bearias:BAAANQADCgUIBQAAAA==.Bearnanas:BAAANQADCgQIBAAAAA==.Bernarnold:BAAANQAECgQIBwAAAA==.Bettyspready:BAAANQAECgIIAgAAAA==.',
Bi='Bigfart:BAAANQADCggIDgAAAA==.Bigmanooshki:BAAANQADCggIGAAAAA==.Bigpoppapump:BAAANQAECgUIBgAAAA==.Bigthumbb:BAAANQABCgUIBQAAAA==.Binnyi:BAAANQAECgMIAwAAAA==.',
Bl='Blackfoot:BAAANQAECgQIBgAAAA==.Blankjr:BAAANQADCgYIDwAAAA==.Blindpov:BAABNQAECoEYAAMCAAgJ9CMIBwDQAgACAAcJOCEIBwDQAgADAAcJPSD9EABcAgAAAA==.',
Bo='Bonquiquie:BAAANQADCgQIBAAAAA==.Boop:BAAANQADCggIDgAAAA==.Bouberry:BAAANQADCgcIDgAAAA==.Bounce:BAAANQADCgYIDAAAAA==.',
Br='Brabiant:BAAANQADCgYIBgAAAA==.Brake:BAAANQAECgUIBgAAAA==.Breakerr:BAAANQADCggIDgAAAA==.Brøken:BAAANQAECgcIBwAAAA==.',
Bu='Bubbleaddict:BAAANQAECgMIAwAAAA==.Bubbly:BAAANQAECgIIAgAAAA==.',
['Bë']='Bërshton:BAAANQADCgQIBwAAAA==.',
Ca='Caitlín:BAAANQADCgYIBgAAAA==.Caleris:BAAANQAECgQIBQAAAA==.Cattle:BAAANQAECgQIBwAAAA==.',
Co='Cottage:BAAANQAECgIIAgAAAA==.',
Cy='Cylic:BAAANQAECgcICwAAAA==.Cyrùsdh:BAAANQADCgYIBgAAAA==.',
Da='Daddiestouch:BAAANQADCgYIDwAAAA==.Dampundies:BAAANQAECgEIAQAAAA==.Dangerdream:BAAANQAECgcIDAAAAA==.Dankheals:BAAANQADCgYIBgAAAA==.Dantee:BAAANQAECgEIAQAAAA==.Daps:BAAANQADCgQIBAAAAA==.Datsmywife:BAAANQAECgYICwAAAA==.Davis:BAAANQAECgUICQAAAA==.Dayquill:BAAANQAECgEIAQAAAA==.',
De='Deadasice:BAAANQADCgEIAQAAAA==.Derpdragon:BAAANQAECgcIEAAAAA==.Deviiarrc:BAAANQAECgcIEQAAAA==.Devviarc:BAAANQADCggICwABNQAECgcIEQABAAAAAA==.',
Dl='Dlamb:BAAANQAECgEIAQAAAA==.',
Do='Dorik:BAAANQADCgEIAQAAAA==.Doroga:BAAANQAECgIIAwAAAA==.',
Dr='Dracar:BAAANQAECgEIAQAAAA==.Drmmrfist:BAAANQAECgQIBQAAAA==.',
Dw='Dwippietiggs:BAAANQAECgQIBAAAAA==.',
['Dä']='Däwntouchme:BAAANQADCgYIBgAAAA==.',
Ea='Earthfeather:BAAANQADCgcIBwAAAA==.Easymac:BAAANQADCgIIAwABNQAECgUIBgABAAAAAA==.',
Ee='Eetee:BAAANQADCgYIEAABNQAECgMIAwABAAAAAA==.',
Em='Emberstone:BAAANQADCgQIBAAAAA==.Emoux:BAAANQADCgYIBgAAAA==.',
Ep='Epìx:BAAANQADCggIBgAAAA==.',
Er='Eralt:BAAANQAECgMIAwAAAA==.Ereye:BAAANQAECgQICgAAAA==.',
Es='Esstina:BAAANQADCgMIAwAAAA==.Estuku:BAAANQAECgUIBgAAAA==.',
Et='Etatoned:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.Etengaged:BAAANQAECgMIAwAAAA==.',
Ev='Evrae:BAAANQAECgUICQAAAA==.',
Ex='Extragrace:BAAANQADCgcIBwAAAA==.',
Ey='Eyeofjazz:BAAANQABCgYIBgAAAA==.',
Fa='Faithshand:BAAANQAECgMIAwAAAA==.Fatkow:BAAANQADCgYIBgABNQAECggIDQABAAAAAA==.',
Fe='Feelzdope:BAAANQADCgQIBAAAAA==.Feio:BAAANQADCgQIBAAAAA==.',
Fi='Finkenator:BAABNQAFFIEKAAIEAAUJWQ3fAgCwAQAEAAUJWQ3fAgCwAQAAAA==.Finkler:BAAANQAECgcIDgABNQAFFAUICgAEAFkNAA==.Firedanny:BAAANQAECgEIAQAAAA==.Fistsofpeace:BAAANQAECgQIBQAAAA==.',
Fl='Flameshock:BAAANQAECgQIBwAAAA==.',
Fr='Friendshaped:BAAANQAECgMIAwABNQAECgUIBQABAAAAAA==.Frigidbeach:BAAANQAECgEIAQAAAA==.',
Ga='Gamthor:BAAANQADCggIDgAAAA==.',
Gl='Glaiveerror:BAAANQADCgYIDwAAAA==.Globoe:BAABNQAFFIEHAAMFAAYJJRq+AAAkAQAFAAMJ8Bm+AAAkAQAGAAMJWRq2AQAVAQAAAA==.Gloreb:BAABNQAFFIEFAAIHAAUJSxjlAAC1AQAHAAUJSxjlAAC1AQAAAA==.',
Go='Goomi:BAAANQADCggIDgAAAA==.Gordef:BAAANQAECgMIAwAAAA==.Gotchabch:BAAANQADCgMIAwAAAA==.',
Gr='Grahz:BAAANQAECgEIAQAAAA==.Grismago:BAAANQAECgEIAQAAAA==.Grizzlebee:BAAANQADCgUIBQAAAA==.',
Gu='Gusto:BAAANQADCggIDAAAAA==.',
Ha='Harrowing:BAABNQAECoEYAAIIAAkJjhbYDQC7AgAIAAkJjhbYDQC7AgAAAA==.Haurt:BAAANQAECgIIAwAAAA==.',
He='Heavyhooves:BAAANQADCgcIEQAAAA==.Hellful:BAAANQAECgEIAQAAAA==.Hemoladi:BAAANQAECgMIBAAAAA==.',
Hi='Hischier:BAAANQAECgQIBAAAAA==.',
Ho='Holycri:BAAANQAECgUIBgAAAA==.Holymilkman:BAAANQABCgQIBgAAAA==.Hotdogramen:BAAANQADCgMIAwAAAA==.Hotmess:BAAANQADCgYIBgAAAA==.',
Hu='Hu:BAAANQAECgUIBQAAAA==.',
['Hô']='Hôly:BAAANQAECgQIBwAAAA==.',
In='Insañe:BAAANQAECgcICwAAAA==.Invi:BAAANQAECgMIAwAAAA==.',
It='Itsjazz:BAAANQABCgMIAwAAAA==.',
Ja='Jabwingle:BAAANQADCgEIAQABNQAECgQICAABAAAAAA==.Jayylols:BAAANQABCgEIAQAAAA==.',
Jo='Jokerzwild:BAAANQADCgQIBAAAAA==.',
Ju='Juiice:BAAANQAECgEIAQAAAA==.',
['Jë']='Jësus:BAAANQAECgQIBgAAAA==.',
Ka='Kalandaelis:BAAANQADCggIDQAAAA==.Kaldren:BAAANQADCgQIBgAAAA==.Kalel:BAAANQAECgEIAQAAAA==.Karmakazie:BAAANQADCgYICgAAAA==.Katasha:BAAANQAECgEIAQAAAA==.Kazraghand:BAAANQAECgQIBQAAAA==.',
Ke='Kei:BAAANQAECgcIDwAAAA==.Kelsio:BAAANQAECgUICgAAAA==.Kess:BAAANQADCgYICAAAAA==.Keyboardcatt:BAAANQADCggIDQAAAA==.',
Kh='Kharos:BAAANQAECgcIDwAAAA==.',
Ki='Kinks:BAAANQADCggIFQAAAA==.Kirkoth:BAAANQADCgMIAwAAAA==.',
Kn='Knuts:BAAANQAECggIBQAAAA==.',
Ko='Korialz:BAAANQADCgYIAQAAAA==.Kowtagion:BAAANQAECggIDQAAAA==.',
Kr='Krahz:BAAANQADCgYIAwAAAA==.Krelsh:BAAANQAECgcIEAAAAA==.Krostikard:BAAANQAECgQIBAAAAA==.',
Ku='Kumquat:BAAANQADCgYIBgAAAA==.Kungfudegru:BAAANQAECgEIAQAAAA==.',
Ky='Kyruutos:BAAANQAECgIIAgAAAA==.',
['Kí']='Kítkat:BAAANQAECgMIBQAAAA==.',
Le='Leibowitzy:BAAANQAECgMIBAAAAA==.Leiptr:BAAANQADCgYIBgAAAA==.Letra:BAAANQADCgMIAwAAAA==.',
Lh='Lhehitman:BAAANQADCggICAAAAA==.',
Li='Lichenric:BAAANQADCgcIBwAAAA==.Lidela:BAAANQAECgEIAQAAAA==.Lightshax:BAAANQAECgQIBQAAAA==.Lilchow:BAAANQADCgMIAwAAAA==.Linedra:BAAANQAECgEIAQAAAA==.',
Lo='Loreena:BAAANQADCgEIAQAAAA==.',
Lu='Luckydog:BAAANQADCggIDAAAAA==.Ludey:BAAANQAECgUICQAAAA==.Lumidk:BAAANQABCgIIAgAAAA==.Lutray:BAAANQADCggIFQAAAA==.',
Ma='Maomao:BAAANQAECgUICgAAAA==.Marodd:BAAANQAECgMIAwAAAA==.Mashîra:BAAANQAECgYICgAAAA==.Matilda:BAAANQABCgQIBAAAAA==.Mattsz:BAAANQADCgcIDQABNQADCggIEQABAAAAAA==.',
Me='Meanmachine:BAAANQADCgUIBgAAAA==.Meatpocket:BAAANQADCgcIBwAAAA==.Meatwangs:BAAANQAECgYICQAAAA==.Merihem:BAAANQADCgUICAAAAA==.Mewfasa:BAAANQADCggICAAAAA==.',
Mi='Milize:BAAANQAECgQIBAAAAA==.Minasuzune:BAAANQAECgMIAwAAAA==.Miney:BAAANQADCgUIBQAAAA==.Minus:BAAANQADCgIIAgAAAA==.',
Mo='Moondotter:BAAANQADCgcICQAAAA==.Moonslayer:BAAANQAECgIIAgAAAA==.Moovefool:BAAANQADCgcIEQAAAA==.',
['Mã']='Mãshîrã:BAAANQADCggICAABNQAECgYICgABAAAAAA==.',
['Mä']='Mähäret:BAAANQADCgUIBQAAAA==.',
['Må']='Måshìra:BAAANQADCgcIBwABNQAECgYICgABAAAAAA==.Måshîrå:BAAANQAECgIIAgABNQAECgYICgABAAAAAA==.',
Na='Nakor:BAAANQAECgEIAQAAAA==.Nalian:BAAANQAECgMIAwAAAA==.Nalliella:BAAANQAECgEIAQAAAA==.',
Ne='Neenzy:BAAANQADCgYIBwAAAA==.Nefeli:BAAANQAECgUICQAAAA==.Nelinne:BAAANQAECgEIAQAAAA==.Nestia:BAAANQADCgYIDwAAAA==.Never:BAABNQAECoEWAAMJAAkJOB8SEwBqAgAJAAcJiB4SEwBqAgAKAAUJoh1tEwClAQAAAA==.',
Ni='Nightshade:BAAANQAECgQICAAAAA==.Nix:BAAANQADCgYIBgAAAA==.',
Oc='Ocllo:BAAANQAECgMIAwAAAA==.',
Og='Oghealz:BAAANQADCgIIAgAAAA==.',
Oj='Ojo:BAAANQAECgMIAwAAAA==.',
On='Oniana:BAAANQAECgQIBwAAAA==.',
Ow='Owwmyballs:BAAANQADCgMIAwAAAA==.',
Oz='Ozygo:BAAANQADCgYIBgAAAA==.',
Pa='Pagamas:BAAANQAECgcIDgAAAA==.Palandari:BAAANQADCggICAAAAA==.Pandawan:BAAANQADCgUIBQAAAA==.Panter:BAAANQADCggIEQAAAA==.Paperplanes:BAAANQADCgQIBAAAAA==.',
Pe='Pebble:BAAANQADCggIDAAAAA==.',
Ph='Phodoe:BAAANQAECgMIAwAAAA==.',
Pi='Pinquisitor:BAAANQADCgEIAQABNQADCgUIBQABAAAAAA==.',
Pl='Playne:BAAANQADCggICAAAAA==.',
Po='Pokeureyeout:BAAANQADCgcIEQAAAA==.Port:BAAANQABCgIIAgABNQAECgYIDQABAAAAAA==.',
Pr='Prodyne:BAAANQAECgUICQAAAA==.',
['Pî']='Pîlot:BAAANQADCgQIBAABNQADCgYIDwABAAAAAA==.',
Qu='Quag:BAAANQADCgUIBQABNQAECgUICAABAAAAAA==.Quiettreader:BAAANQAECgMIBAAAAA==.Quokka:BAAANQAECgIIAwAAAA==.',
Ra='Raegwin:BAAANQADCgcICQAAAA==.Raidboss:BAAANQADCggIEQAAAA==.',
Re='Redeath:BAAANQADCgcIEAAAAA==.Redirect:BAAANQADCgUICgABNQADCgcIEAABAAAAAA==.Redonculous:BAAANQAECgQIBQAAAA==.Redpool:BAAANQAECgYICwAAAA==.Rehvenge:BAAANQADCgYIBwAAAA==.Rektroll:BAAANQAECgQICQAAAA==.Revansong:BAAANQADCgYICgABNQAECgQIBgABAAAAAA==.Reymnant:BAAANQADCgMIAwAAAA==.',
Ro='Ronx:BAAANQAECgMIAwAAAA==.Roxxiloxxi:BAAANQAECgQIBwAAAA==.',
Ru='Rudeboy:BAAANQAECgEIAQAAAA==.',
['Rö']='Röwan:BAAANQADCgUIBQAAAA==.',
Sa='Sabria:BAAANQAECgUIBQAAAA==.Sagitta:BAAANQADCgcIBwABNQADCggIDAABAAAAAA==.Sahria:BAAANQADCgYIDQAAAA==.Sarhia:BAAANQADCgUIBQAAAA==.Savanari:BAAANQAECgEIAQABNQABCgIIAgABAAAAAA==.',
Sc='Schizadin:BAAANQADCgYIBgAAAA==.Schnoze:BAAANQAECgEIAQAAAA==.',
Se='Sebekuul:BAAANQADCgYIBgAAAQ==.Selys:BAAANQAECgYIEAAAAA==.Sence:BAAANQABCgQIBAAAAA==.Sephurik:BAACNQAFFIEGAAIEAAMJEhYDBgAPAQAEAAMJEhYDBgAPAQA1AAQKgRoAAgQACQmFHesaAPUCAAQACQmFHesaAPUCAAAA.',
Sh='Shadowwife:BAAANQADCgYIBgAAAA==.Shamaneez:BAAANQABCgQIBQAAAA==.Shamanism:BAAANQADCgUIBQAAAA==.Shanamana:BAAANQAECgQIBAAAAA==.Shawnalenee:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.Shiestee:BAAANQAECgEIAQAAAA==.Shiriax:BAAANQADCgcIBwAAAA==.',
Si='Sikanda:BAAANQADCggICwABNQAECgQIBwABAAAAAA==.Silvea:BAAANQADCggICwAAAA==.Sinara:BAAANQAECgEIAQAAAA==.Sion:BAAANQAECgQIBwAAAA==.Sithlordz:BAAANQADCgYICQAAAA==.',
Sk='Sky:BAAANQAECgUIBQAAAA==.Skyelf:BAAANQAECgUIBgAAAA==.',
Sl='Sloppysloosh:BAAANQADCgQIBgAAAA==.',
Sm='Smallpox:BAAANQADCgUIDQAAAA==.',
Sn='Snooflepoof:BAAANQAECgYICgAAAA==.',
So='Socks:BAAANQAECgEIAQAAAA==.Solunara:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.',
Sp='Spectrecles:BAAANQAECgYIDQAAAA==.Speez:BAAANQADCggIEwAAAA==.',
St='Stablehand:BAAANQAECgQIBAAAAA==.Steve:BAACNQAFFIEGAAILAAMJXAdTAwD0AAALAAMJXAdTAwD0AAA1AAQKgRoAAgsACQmRIOQGAEkDAAsACQmRIOQGAEkDAAAA.Stonedfel:BAAANQAECgMIBAAAAA==.',
Su='Sunhoof:BAAANQAECgIIAgAAAA==.Supahotvile:BAAANQADCgcICAAAAA==.',
Sy='Syx:BAAANQADCgYIBgAAAA==.',
['Sø']='Sørrow:BAAANQAECgEIAQAAAA==.',
Ta='Tabi:BAAANQAECgMIAwAAAA==.Taldresh:BAAANQADCgUIBQAAAA==.Tanorgalaria:BAAANQADCggICAAAAA==.',
Te='Test:BAAANQAECgcIAQAAAA==.',
Th='Thedayman:BAAANQADCggICAAAAA==.Thetaint:BAAANQAECgYICQAAAA==.',
Ti='Tinee:BAAANQADCggIDQAAAA==.Tinket:BAAANQAECgYICwAAAA==.',
Tr='Travonnis:BAAANQADCggIDAAAAA==.Trentlock:BAAANQAECgcICwAAAA==.',
Ts='Tsu:BAAANQAECgUIBQAAAA==.',
Ty='Tynisa:BAAANQADCggICgAAAA==.',
Un='Unstablesha:BAAANQADCgYIBgAAAA==.',
Ut='Utilities:BAAANQADCggICAAAAA==.',
Va='Vaderbear:BAAANQADCggICAAAAA==.Varandar:BAAANQAECgcIDAAAAA==.',
Vi='Via:BAAANQADCgQIBAAAAA==.Vil:BAACNQAFFIEMAAIMAAYJHCAWAACKAgAMAAYJHCAWAACKAgA1AAQKgRoAAgwACQmjJikAAP0DAAwACQmjJikAAP0DAAAA.Vilonus:BAAANQAECgIIAgAAAA==.',
Vo='Voidbwoy:BAAANQADCggIEwAAAA==.Voy:BAAANQAECgEIAQAAAA==.',
Vu='Vulpes:BAAANQABCgUIAwAAAA==.Vurx:BAAANQAECgEIAQAAAA==.',
Wi='Williie:BAAANQAECgEIAQAAAA==.Withengar:BAAANQADCggICAAAAA==.',
Wu='Wuoshi:BAAANQAECgEIAQAAAA==.Wuuzzyy:BAAANQAECgQIBwAAAA==.',
Xa='Xaliko:BAAANQAECgMIAwAAAA==.Xanbaran:BAAANQAECgUICQAAAA==.',
Xi='Xiphus:BAAANQABCgMIBQAAAA==.',
Xy='Xyrtrew:BAAANQAECggIEgAAAA==.',
Yu='Yuki:BAAANQADCgYIBgAAAA==.',
Za='Zambesi:BAAANQADCggICAAAAA==.Zaradinna:BAAANQADCgEIAQAAAA==.Zartini:BAAANQAECgUIBwAAAA==.',
Ze='Zerk:BAAANQADCgEIAQAAAA==.',
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
