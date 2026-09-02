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
local provider = {region='US',realm='Exodar',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Abrakådabruh:BAAANQADCggICgAAAA==.',
Ae='Aeropos:BAAANQABCgEIAQAAAA==.',
Ah='Ahron:BAAANQADCggIDgABNQAECgQIBAABAAAAAA==.',
Ai='Ainjel:BAAANQADCgQIBAAAAA==.',
Ak='Akaitsuki:BAAANQADCgcIDAAAAA==.',
Al='Alexr:BAAANQADCgUIBQAAAA==.Alexxh:BAAANQADCgMIAwABNQADCgUIBQABAAAAAA==.',
Am='Amarantus:BAAANQADCgIIAgABNQAECgQICgABAAAAAA==.Ammerie:BAAANQADCgUIBQAAAA==.',
An='Anmodru:BAAANQADCgUIBQABNQAECgcICgABAAAAAA==.',
Ao='Aoefarm:BAAANQADCggIFAAAAA==.',
Aq='Aqulath:BAAANQAECgQIBQAAAA==.',
Ar='Aragos:BAAANQADCgEIAQAAAA==.Aridhol:BAAANQAECgEIAQAAAA==.',
As='Astravelle:BAAANQADCgUIBwAAAA==.',
At='Athená:BAAANQADCggICAAAAA==.Athenä:BAAANQAECgQIBAAAAA==.',
Au='Aubrii:BAAANQADCgQIBgAAAA==.',
Ba='Baladeva:BAAANQADCggIDgAAAA==.Barbaricboss:BAAANQADCgcIBwAAAA==.Barrak:BAAANQAECgQIBAAAAA==.Bau:BAAANQADCgYICgAAAA==.',
Be='Bearomir:BAAANQAECgMIAwAAAA==.',
Bi='Bigmikeyg:BAAANQADCggIDgAAAA==.Bigsteve:BAAANQADCggIDgAAAA==.',
Bl='Blanket:BAAANQAECgUIBQAAAA==.Bloodhunter:BAAANQADCgUIBwAAAA==.',
Bo='Boomchickun:BAAANQABCgIIAgABNQAECgcIDQABAAAAAA==.',
Br='Brickley:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.',
['Bè']='Bèyork:BAAANQADCggIDwAAAA==.',
Ca='Caicos:BAEANQAECgQIBQAAAA==.Calizon:BAAANQADCggIDQAAAA==.Canowhoopass:BAAANQADCgYIDAAAAA==.',
Ce='Cell:BAAANQAECgYICgAAAA==.Cellyne:BAAANQADCgUIBgAAAA==.Cerassin:BAAANQAECgcIDQAAAA==.Cereas:BAAANQADCgYICwAAAA==.',
Ch='Cheesedawg:BAAANQADCgEIAQAAAA==.Choofz:BAAANQADCggICAAAAA==.Chulk:BAAANQADCgcIDAAAAA==.',
Cl='Cloud:BAAANQAECgIIAgAAAA==.Clukdogg:BAAANQAECgUICQAAAA==.',
Co='Combination:BAAANQAECgcIDAAAAA==.Corvenall:BAAANQAECgEIAQAAAA==.',
Cr='Crashpad:BAAANQADCgYIBgAAAA==.Crossbow:BAAANQAECgYIBwAAAA==.',
Da='Dakkan:BAAANQADCggIDAAAAA==.Danidani:BAAANQAECgQIBAAAAA==.Darkluster:BAAANQADCgQIBAAAAA==.Darshun:BAAANQADCgMIAwAAAA==.Davinah:BAAANQADCgYICwAAAA==.Dayje:BAAANQADCgIIAgAAAA==.',
De='Deathation:BAAANQADCgQIBAAAAA==.Deathbcmesyu:BAAANQADCgcIDQAAAA==.',
Di='Diehappy:BAAANQADCgQIBAAAAA==.Dishonor:BAAANQADCgMIAwAAAA==.',
Do='Dommage:BAAANQAECgQIBAABNQAECgYICgABAAAAAA==.Downbadd:BAAANQABCgQIBQAAAA==.',
Dr='Druida:BAAANQADCgYICAAAAA==.Drywar:BAAANQAECgYIBwAAAA==.Dràgonkíng:BAAANQADCgUICQAAAA==.',
Dt='Dtinnel:BAAANQADCgMIAwABNQAECgYIBwABAAAAAA==.',
['Dà']='Dànger:BAAANQADCgcIDgAAAA==.',
Eg='Ego:BAAANQAECgEIAQAAAA==.',
Ei='Eisla:BAAANQAECgEIAQAAAA==.',
Em='Emmone:BAAANQADCgMIAwAAAA==.',
Ex='Exacerbator:BAAANQADCgYIBgAAAA==.',
Fa='Falcon:BAAANQABCgIIAwAAAA==.Faunna:BAAANQAECgQICgAAAA==.',
Fe='Feath:BAAANQADCgIIAgAAAA==.Feebeeboofae:BAAANQADCgYICAAAAA==.Felaz:BAAANQAECgEIAQAAAA==.Feoridor:BAAANQADCgIIAgAAAA==.',
Fi='Fingerguns:BAAANQAECgQIBQAAAA==.',
Fl='Floortank:BAAANQADCgYIDAAAAA==.',
Fr='Friday:BAAANQADCggIDgAAAA==.Frikilatar:BAAANQABCgIIBAAAAA==.Frrank:BAAANQAECgQIBwAAAA==.',
Ga='Galcain:BAAANQADCgUIBQAAAA==.',
Go='Googleyes:BAAANQADCgIIAgAAAA==.Goss:BAAANQADCgIIAgAAAA==.',
Gr='Graphene:BAAANQADCgEIAQAAAA==.Greybull:BAAANQADCggIDAAAAA==.Griffy:BAAANQADCgQIBAAAAA==.Grimseek:BAAANQADCggIDgABNQAECgcIDAABAAAAAA==.Growlyr:BAAANQAECgIIAgAAAA==.Grumandel:BAAANQADCggIDAAAAA==.',
Ha='Hakur:BAAANQAECgEIAQAAAA==.Hammertóe:BAAANQADCggIDQAAAA==.Hanma:BAAANQAECgQIBgAAAA==.Harribel:BAAANQADCggIDgAAAA==.',
He='Heiferina:BAAANQADCgMIAwAAAA==.Helixra:BAAANQADCgYIDwAAAA==.',
Hi='Hitachitotem:BAAANQAECgQIBwAAAA==.',
Hy='Hyperíon:BAAANQADCgYICwAAAA==.',
Ic='Icies:BAAANQAECgEIAgAAAA==.',
Jc='Jclif:BAAANQADCggIDwAAAA==.',
Je='Jehannum:BAAANQADCggIDgAAAA==.Jessira:BAAANQAECgMIAwAAAA==.',
Jo='Jonahheal:BAAANQADCgcIBwABNQAECgcIDQABAAAAAA==.Josen:BAAANQADCgcIDAAAAA==.',
Ka='Kaimi:BAAANQADCgQIBwAAAA==.Kainiy:BAAANQADCgUICwAAAA==.Kaizenn:BAAANQADCgIIAgAAAA==.Kaladjin:BAAANQADCggIDwAAAA==.Katarena:BAAANQAECgEIAQAAAA==.Kathyra:BAEANQADCgYICgABNQAECgQIBQABAAAAAA==.Kavax:BAAANQADCgcIDAAAAA==.',
Ke='Keel:BAAANQADCgEIAQAAAA==.Keeller:BAAANQAECgEIAQAAAA==.Keleris:BAAANQADCgUIBQAAAA==.Kentyr:BAAANQADCgEIAQAAAA==.',
Kh='Khasket:BAAANQADCgUIBQAAAA==.',
Ki='Kinký:BAAANQAECgIIAgAAAA==.Kiraelis:BAAANQADCggIDwAAAA==.',
Ko='Korvoh:BAAANQADCggIDgAAAA==.',
Kr='Kredriel:BAAANQADCgYIBwAAAA==.Krinmate:BAAANQAECgcICwAAAA==.Krystn:BAAANQADCgMIAwAAAA==.',
Ku='Kuurome:BAAANQADCgMIAwABNQAECgYIBwABAAAAAA==.',
Kw='Kwinny:BAAANQADCggICgAAAA==.',
Ky='Kyloris:BAAANQAECgIIAgAAAA==.Kynthria:BAAANQAECgQIBwAAAA==.',
['Kä']='Kämik:BAAANQADCggIDgAAAA==.',
['Kì']='Kìn:BAAANQADCgEIAQAAAA==.',
La='Lampion:BAAANQADCggIDgAAAA==.Lasstchance:BAAANQADCgQIBAAAAA==.Latinamaddog:BAAANQADCgcIDQAAAA==.',
Le='Leijona:BAAANQADCgQIBAAAAA==.Lenard:BAAANQADCgYIDgAAAA==.',
Li='Likeatrain:BAAANQADCgYIDAAAAA==.Linds:BAAANQADCgYIBgAAAA==.',
Lo='Lokininja:BAAANQAECgEIAQAAAA==.Loofuh:BAAANQADCgYIBgAAAA==.',
Lt='Ltdanslegs:BAAANQAECgQIBAAAAA==.',
Lu='Luxu:BAAANQAECgIIAgAAAA==.Luxzy:BAAANQADCgYIBgAAAA==.',
Ma='Makarich:BAAANQADCggIDQAAAA==.Malachron:BAAANQADCgYIDAAAAA==.Manbearcat:BAAANQADCgcIDAAAAA==.Marbleous:BAAANQAECgMIBAAAAA==.',
Me='Meatcurtains:BAAANQADCgUIBQABNQADCgYIBwABAAAAAA==.Memisstotem:BAAANQADCgYICwAAAA==.Merle:BAAANQAECgcIDAAAAA==.',
Mi='Minaxy:BAAANQAECgQIBQAAAA==.Mistborn:BAAANQAECgEIAQAAAA==.Mistsofpoly:BAAANQADCgQIBAABNQAECgUICAABAAAAAA==.',
Mo='Momoku:BAAANQADCggICgAAAA==.Mootalstrike:BAAANQADCggIDgAAAA==.Moshworm:BAAANQAECgEIAgAAAA==.',
Mv='Mvp:BAAANQADCgUIBQAAAA==.',
Ne='Nelaphim:BAAANQADCggIDgAAAA==.Nexassin:BAAANQAECgEIAQAAAA==.',
Ni='Nico:BAAANQADCggIDQAAAA==.Nightfang:BAAANQADCgUIBQAAAA==.Nimz:BAAANQADCgYIBwAAAA==.',
No='Noxxidari:BAAANQAECgQIBAAAAA==.Noxxus:BAAANQADCgcIBQAAAA==.',
Ob='Oblivia:BAAANQADCgQIBAAAAA==.',
Or='Orchist:BAAANQADCgcIDAAAAA==.Orimbo:BAAANQADCggIDgAAAA==.',
Pa='Paidu:BAAANQAECgYICgAAAA==.Palaritaz:BAAANQAECgIIAgAAAA==.',
Pe='Pestilancé:BAAANQADCggIDgAAAA==.',
Pi='Pinktp:BAAANQAECgIIAgAAAA==.Pitchblende:BAAANQADCggIDwAAAA==.',
Pr='Prangkim:BAAANQADCgMIBAAAAA==.Protagoras:BAAANQADCgQIBAAAAA==.',
Ra='Rajak:BAAANQADCgMIAwAAAA==.Rathidk:BAAANQAECgYICgAAAA==.',
Re='Redine:BAAANQADCgQIBAAAAA==.Reen:BAAANQADCgIIAgAAAA==.Rellt:BAAANQADCgQIBAAAAA==.Rendis:BAAANQAECgEIAQAAAA==.',
Rh='Rhayge:BAAANQADCggIDAAAAA==.',
Ru='Ruukia:BAAANQAECgYIBwAAAA==.',
Sa='Saboo:BAAANQADCgcICAAAAA==.Sahki:BAAANQADCgUICgAAAA==.Saltybreath:BAAANQADCggIDgABNQAECgQIBAABAAAAAA==.Sapientia:BAAANQADCgYIBgAAAA==.',
Sc='Scottkill:BAAANQADCggIDAABNQAECggIDgABAAAAAA==.',
Se='Seasnan:BAAANQADCgQIBgAAAA==.Seluna:BAAANQADCgUIBQAAAA==.',
Sh='Shadowdeath:BAAANQAECgEIAQAAAA==.Shadowheàrt:BAAANQADCgUIBQAAAA==.Shadowshifty:BAAANQADCgYIBgAAAA==.Shadowtotem:BAAANQADCgQIBAAAAA==.Shamdü:BAAANQAECgQIBAAAAA==.Shanson:BAAANQADCgYIBgAAAA==.Showerthots:BAAANQADCgQIBQAAAA==.',
Si='Sineth:BAAANQADCggICAAAAA==.',
Sk='Skooda:BAAANQAECgQIBAAAAA==.Skyded:BAAANQADCgUIBQAAAA==.Skyfell:BAAANQADCggICgAAAA==.Skyknight:BAAANQADCgUIBQAAAA==.',
Sn='Snapahead:BAAANQADCgYICgAAAA==.',
So='Solcon:BAAANQADCggIDgAAAA==.Somebodie:BAAANQADCgEIAQAAAA==.',
Sp='Spaazz:BAAANQAECgEIAQAAAA==.',
Sq='Squeakbolt:BAAANQADCgYICAAAAA==.',
St='Starofdreams:BAAANQADCgEIAQABNQADCgcIFQABAAAAAA==.Starweaver:BAAANQADCgcIFQAAAA==.Stormrender:BAAANQADCggICAAAAA==.Stormsong:BAAANQAECgYIBwAAAA==.Strangecandy:BAAANQADCgMIAwAAAA==.Strángeland:BAAANQADCgEIAQAAAA==.Störmrender:BAAANQADCgcIBwABNQADCggICAABAAAAAA==.',
Su='Sunarianna:BAAANQADCgYICgAAAA==.',
Sy='Sycla:BAAANQAECgMIAwAAAA==.Sylas:BAAANQADCgIIAgAAAA==.',
Ta='Taloriesh:BAAANQAECgIIAgAAAA==.Tanazir:BAAANQAECgEIAQAAAA==.Tarok:BAAANQADCgEIAQAAAA==.Tashien:BAAANQADCgQIBAAAAA==.',
Te='Teito:BAAANQADCggICgAAAA==.Terenii:BAAANQADCgYIBgAAAA==.',
Ti='Tilamano:BAAANQAECgMIBAAAAA==.Tilatree:BAAANQAECgEIAQABNQAECgMIBAABAAAAAA==.',
To='Tohrnarc:BAAANQAECgEIAgAAAA==.Tookkiiee:BAAANQADCggICAAAAA==.Totemwebz:BAAANQADCgcIDAAAAA==.',
Tr='Trenve:BAAANQADCgcIDQAAAA==.',
Tu='Turbomage:BAAANQABCgQIBAAAAA==.Tuzzyfits:BAAANQADCggIDwAAAA==.',
['Té']='Téchymoon:BAAANQAECgYICgAAAA==.',
Ug='Ugo:BAAANQADCgYIBgAAAA==.',
Um='Umbron:BAAANQAECgQIBQAAAA==.Umbrute:BAAANQADCgMIAwABNQAECgQIBQABAAAAAA==.',
Va='Valcristo:BAAANQADCggIDgAAAA==.Valdun:BAAANQADCgQIBAAAAA==.Vanaras:BAAANQADCgEIAQAAAA==.Vargrim:BAAANQAECgEIAQAAAA==.',
Ve='Venous:BAAANQADCgYIBgAAAA==.Vestt:BAAANQADCggIDgAAAA==.',
Vi='Vicariana:BAAANQAECgQIBwAAAA==.Viduus:BAAANQADCgMIAwABNQADCgYIBwABAAAAAA==.Viv:BAAANQADCgYIBgAAAA==.',
Vo='Vodmor:BAAANQADCgcICwAAAA==.Voldermort:BAAANQADCgYIBgAAAA==.',
Wa='Warrendemon:BAAANQAECgYICgAAAA==.',
We='Wedowarcrime:BAAANQADCgIIAgAAAA==.',
Wh='Whims:BAAANQADCgUIBQAAAA==.',
Wo='Woregontail:BAAANQADCgQIBgAAAA==.Wowbelly:BAAANQADCgQIBAAAAA==.',
Xa='Xandros:BAAANQADCgUIBQAAAA==.',
Xo='Xonk:BAAANQAECgYICgAAAA==.',
Yg='Ygcamel:BAAANQADCggIEgAAAA==.',
Za='Zalagrimbor:BAAANQAECgQIBQAAAA==.Zaps:BAAANQADCggIDwAAAA==.Zarev:BAAANQAECgcICwAAAA==.',
Ze='Zelie:BAAANQADCggIDgAAAA==.Zenreto:BAAANQADCggIDgAAAA==.',
Zo='Zoeri:BAAANQABCgEIAQAAAA==.Zoltraak:BAAANQADCgUICQAAAA==.',
['Än']='Änmoa:BAAANQAECgcICgAAAA==.',
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
