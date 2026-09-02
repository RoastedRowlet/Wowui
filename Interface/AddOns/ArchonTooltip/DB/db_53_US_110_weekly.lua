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
local provider = {region='US',realm='Gorefiend',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Abuki:BAAANQAECgUIBgAAAA==.',
Ak='Akagane:BAAANQADCgQIBgAAAA==.',
Al='Alfuric:BAAANQADCgUIBwAAAA==.Althraniir:BAAANQABCgMIAwAAAA==.Altrois:BAAANQAECgIIAgAAAA==.',
Am='Amatrake:BAAANQAECgcIDAAAAA==.Amatsano:BAEANQADCgMIAwAAAA==.Amorsith:BAAANQADCgYICwABNQADCggICAABAAAAAA==.Amyst:BAAANQAECgQIBgAAAA==.',
An='Angrycrack:BAAANQADCggICwAAAA==.Angusill:BAAANQADCgMIAwAAAA==.Anjunabeets:BAAANQAFFAEIAQAAAA==.Anthran:BAAANQAECgQIBAAAAA==.',
Ar='Arcon:BAAANQAECgEIAQAAAA==.Arcscythe:BAAANQAECgEIAQAAAA==.Artoo:BAAANQADCgYIDAAAAA==.',
As='Ashesonly:BAAANQAECgIIAwAAAA==.',
Au='Auramis:BAAANQAECgQIBAAAAA==.',
Az='Azariel:BAAANQADCgUIBQAAAA==.',
Ba='Babydilla:BAAANQAECgcIDAAAAA==.Balgith:BAAANQADCgcIDAAAAA==.Bam:BAAANQADCggICAAAAA==.Bannagad:BAAANQAECgUIBwAAAA==.Battleburger:BAAANQADCgYICQAAAA==.Bauchelaine:BAAANQADCgQIBgAAAA==.Bawitaba:BAAANQADCggIDgAAAA==.',
Be='Benchknight:BAAANQAECgcIDAAAAA==.Beoron:BAAANQAECgYIDAAAAA==.',
Bi='Big:BAAANQADCggICAAAAA==.Bio:BAAANQAECggIAQAAAA==.Biolysis:BAAANQADCgUIBQABNQAECggIAQABAAAAAA==.',
Bl='Blowtortch:BAAANQADCggIDgAAAA==.',
Br='Brageus:BAAANQAECgEIAQAAAA==.Braintumor:BAAANQADCgcICwAAAA==.Brontag:BAAANQAECgEIAQAAAA==.Bruus:BAAANQADCggIDAAAAA==.',
Bu='Buns:BAAANQAECgEIAQAAAA==.Butternutter:BAAANQADCggIDQAAAA==.',
['Bé']='Béllas:BAAANQADCgYIBgAAAA==.',
Ca='Caissa:BAAANQADCgYIBgAAAA==.Calißoy:BAAANQAECgIIAgAAAA==.Canekii:BAAANQADCgYIBgAAAA==.Casini:BAAANQADCgQIBAAAAA==.',
Ce='Cerberus:BAAANQAECgQIBgAAAA==.',
Ch='Chaboomy:BAEANQAECggIDQAAAA==.Chidori:BAAANQADCgUIBQAAAA==.Chips:BAAANQADCggIDgAAAA==.',
Co='Coffeemaker:BAAANQAECgEIAQAAAA==.Collie:BAEANQAECgIIAgAAAA==.',
Cr='Croissant:BAAANQAECgEIAQAAAA==.Cräsh:BAAANQADCgMIAwAAAA==.',
Cy='Cycko:BAAANQADCgUIBQAAAA==.',
Da='Dalórien:BAAANQADCgMIBQAAAA==.Damaerin:BAAANQAECgMIAwAAAA==.Darkis:BAAANQAECgEIAQAAAA==.Darkseph:BAAANQADCgYIBwABNQADCggICAABAAAAAA==.Darthjarjar:BAAANQADCgMIAwAAAA==.Dayy:BAAANQAECgcIDAAAAA==.',
De='Deathsteak:BAAANQADCgUIBQAAAA==.Deepman:BAAANQAECgIIAgABNQAECgQIBAABAAAAAA==.Delessia:BAAANQADCgcIBwAAAA==.Deo:BAAANQAECgIIAgAAAA==.',
Di='Diggersby:BAAANQAECgUIBgAAAA==.Disastrous:BAAANQAECgYICAAAAA==.',
Do='Doson:BAAANQADCgcIBwAAAA==.',
Dr='Druidtime:BAAANQADCgUIBwAAAA==.Drunkenmasta:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.',
['Dø']='Døc:BAAANQADCggIDwAAAA==.',
Eg='Eggland:BAAANQAECgUIBwAAAA==.',
Ei='Eielmolate:BAAANQAECgcIDAAAAA==.',
En='Enimed:BAAANQAECgIIAgAAAA==.',
Eu='Eugenn:BAAANQADCgYICwAAAA==.',
Ev='Evil:BAAANQAECgQIBAAAAA==.',
Fa='Fam:BAAANQAECggIDQAAAA==.Fatherseph:BAAANQADCggICAAAAA==.',
Fi='Fisterdobble:BAAANQAECgIIAgAAAA==.',
Fl='Fleurdelys:BAAANQADCgUIBwAAAA==.',
Fo='Forgedd:BAAANQABCgMIAwAAAA==.',
Fr='Frostheart:BAAANQABCgQIBgAAAA==.Frozenpickle:BAAANQADCgYIBwAAAA==.',
Ge='Gerkindk:BAAANQADCggICAAAAA==.',
Gr='Grackalackin:BAAANQADCgYICwAAAA==.Grassfedgeez:BAAANQADCgYIBgAAAA==.',
Gu='Gulaj:BAAANQAECgEIAQAAAA==.Guldaniel:BAAANQADCggIDQAAAA==.',
['Gë']='Gënesis:BAAANQADCggIDAAAAA==.',
Ha='Ham:BAAANQADCggIEAAAAA==.',
He='Healgimp:BAAANQAECgIIAgAAAA==.',
Ho='Howdoitotem:BAAANQAECgQIBAAAAA==.',
Hu='Humaa:BAAANQADCgYIEAAAAA==.Huntus:BAAANQAECgUIBgAAAA==.',
Hy='Hyperiøn:BAAANQADCgIIAgAAAA==.',
Ic='Icy:BAAANQADCggICAAAAA==.',
Im='Impostor:BAAANQAECgQIBAAAAA==.',
['Iç']='Içyhot:BAAANQADCgEIAQAAAA==.',
Ja='Jabrick:BAAANQAECgMIAwAAAA==.Jattin:BAAANQADCgYIBgAAAA==.Jawnski:BAAANQADCgUICQAAAA==.',
Ji='Jibjabjibjab:BAAANQAECgQIBAAAAA==.',
Jo='Joharin:BAAANQADCgcIDAAAAA==.',
Jt='Jtabb:BAAANQABCgQIAgAAAA==.',
Ju='Juroda:BAAANQADCgYIBgABNQADCggICAABAAAAAA==.',
Ke='Kelamess:BAAANQADCggIEAAAAA==.Kelemvor:BAAANQAECgQIBAAAAA==.',
Kf='Kfp:BAAANQABCgEIAQAAAA==.',
Kh='Khandak:BAAANQAECgQIBAAAAA==.',
Ki='Kimmy:BAAANQADCgYIBgAAAA==.',
Kl='Kleenex:BAAANQADCgUIBQAAAA==.',
Ku='Kurisutina:BAAANQAECgQIBgAAAA==.',
Le='Leadblaster:BAAANQAECgQIBAAAAA==.Leethalfu:BAAANQADCgYICwAAAA==.Leethalrot:BAAANQADCgYICQABNQADCgYICwABAAAAAA==.Legosi:BAAANQADCggIDgAAAA==.Lemegegen:BAAANQAECgIIAgAAAA==.',
Lh='Lhux:BAAANQAECgQIBQAAAA==.',
Li='Lilbokchoy:BAAANQABCgQIBAAAAA==.Linkin:BAAANQABCgMIAwAAAA==.',
Lo='Loneassassin:BAAANQADCgQIBAAAAA==.Lorani:BAAANQAECgQIBAAAAA==.',
Lu='Lurth:BAAANQADCgIIAgABNQADCgQIBwABAAAAAA==.',
Ly='Lyxxie:BAAANQAECgQIBAAAAA==.',
Ma='Mageus:BAAANQADCgQIBAAAAA==.Matsumushi:BAAANQAECgEIAQAAAA==.',
Me='Mefesto:BAAANQAECgYIBwABNQABCgQIBAABAAAAAA==.Mellore:BAAANQADCgMIAwAAAA==.Metsutan:BAAANQAECgIIAgAAAA==.',
Mo='Moonster:BAAANQAECgIIAgAAAA==.',
['Mâ']='Mâtthêw:BAAANQADCgYIBgAAAA==.',
Ne='Nekcrotic:BAAANQADCgYICwAAAA==.Nekromant:BAAANQADCggIDwAAAA==.',
No='Nohric:BAAANQADCggIEgAAAA==.Norsem:BAAANQADCgYIBgAAAA==.',
Oh='Ohlorn:BAAANQAECgYICQAAAA==.',
On='Onfleek:BAAANQADCgYICwAAAA==.',
Or='Orakrak:BAAANQADCgQIBAAAAA==.Oroku:BAAANQADCgQICAAAAA==.',
Oz='Ozzmodius:BAAANQADCgIIAgAAAA==.',
Pa='Pakapunch:BAAANQADCgIIAgAAAA==.Papier:BAAANQADCggICAABNQADCggIDQABAAAAAA==.Parsephone:BAAANQAECgIIAgABNQADCggICAABAAAAAA==.Parstout:BAAANQADCggICAAAAA==.Pawsitivity:BAAANQADCgcIDAAAAA==.',
Pe='Petr:BAAANQAECgIIAgAAAA==.Pettigrew:BAAANQADCgQIBAAAAA==.Peut:BAAANQAECgEIAQAAAA==.',
Pi='Pipsqueak:BAAANQADCgcICwAAAA==.Pitchntents:BAAANQAECgIIAgAAAA==.',
Po='Porkins:BAAANQAECgIIAgAAAA==.',
Py='Pyraxx:BAAANQAECgYIBwAAAA==.',
Qt='Qtwithabooty:BAAANQAECgcIDQAAAA==.',
Qu='Quatermaine:BAAANQADCgUICQAAAA==.',
Ra='Radovan:BAAANQAFFAEIAQAAAA==.Raìdèn:BAAANQADCgYICwAAAA==.',
Re='Replicate:BAAANQAECgIIAgAAAA==.',
Rh='Rhinne:BAAANQAECgIIAgAAAA==.',
Ri='Riddic:BAAANQADCgEIAQAAAA==.',
Ry='Ryanqt:BAAANQADCggIDQAAAA==.Ryanx:BAAANQAECgcICwAAAA==.',
Sa='Samavati:BAAANQADCgcIDAAAAA==.Sarah:BAAANQAECgMIBAAAAA==.Sasori:BAAANQAECgcICgAAAA==.Sassyface:BAAANQAECgIIAgAAAA==.',
Se='Sellit:BAAANQADCgYICwAAAA==.',
Sh='Shadowdin:BAAANQAECgIIAgAAAA==.Shamzilla:BAAANQADCgcIBwAAAA==.Shockblast:BAAANQADCgEIAQAAAA==.',
Si='Sibbrena:BAAANQAECgQIBAAAAA==.Sillygoose:BAAANQADCgcIDQAAAA==.',
Sk='Skn:BAAANQAECgMIAwAAAA==.',
Sl='Slaughter:BAAANQADCgUICAAAAA==.',
Sm='Smartlurth:BAAANQADCgQIBwAAAA==.',
Sn='Snowjob:BAAANQADCggIDgAAAA==.',
So='Sonal:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.',
Sp='Spewns:BAAANQADCgMIAwAAAA==.',
Sq='Squanchy:BAAANQADCgMIAwAAAA==.',
St='Steakfries:BAAANQADCgMIAwAAAA==.Steamlock:BAAANQAECgEIAQAAAA==.Stellar:BAAANQADCgYIBgABNQAECgQICAABAAAAAA==.Stelthme:BAAANQADCgYICwABNQAECgQICAABAAAAAA==.',
Ta='Tanìs:BAAANQADCgYIBgAAAA==.Tarle:BAAANQADCgUICQAAAA==.Tazath:BAAANQAECgUICAABNQAECgYIDAABAAAAAA==.',
Te='Tendroni:BAAANQAECgEIAQAAAA==.',
Th='Theory:BAAANQAECgEIAQAAAA==.',
Tr='Trashii:BAAANQAECgEIAQAAAA==.Trenlight:BAAANQADCgcIBwAAAA==.Trentotem:BAAANQAECgcICgAAAA==.Trystan:BAAANQADCgcIDQAAAA==.',
Ts='Tsinga:BAAANQADCgUIBQAAAA==.',
Tu='Turlo:BAAANQADCgEIAQAAAA==.',
Tw='Twobrews:BAAANQAECgQIBQAAAA==.Twohammered:BAAANQADCgcICwABNQAECgQIBQABAAAAAA==.',
['Tø']='Tøm:BAAANQAECgcICwAAAA==.',
Ul='Ullirus:BAAANQADCgMIBAAAAA==.',
Un='Unbiased:BAAANQAECgIIAgAAAA==.Unshookable:BAAANQAECgYICQAAAA==.',
Va='Valsande:BAAANQADCgIIAgAAAA==.',
Ve='Vermax:BAAANQADCgQIBAAAAA==.',
Vo='Voidh:BAAANQAECgQIBwAAAA==.Voidlockus:BAAANQADCgYICAAAAA==.',
Vu='Vulcin:BAAANQAECgUIBQABNQAECgYIBwABAAAAAA==.',
Wa='War:BAAANQADCgQIBAABNQAECgQIBAABAAAAAA==.',
Wh='Whitelïght:BAAANQAECgEIAQAAAA==.Whsprngihntr:BAAANQADCggICAAAAA==.',
Wi='Wibblës:BAAANQADCggIDgAAAA==.',
Xi='Xial:BAAANQADCgcIDgABNQABCgMIAwABAAAAAA==.',
Xy='Xyfin:BAAANQADCggIDwAAAA==.',
Yd='Ydehhteb:BAAANQADCgEIAQABNQADCgYIBgABAAAAAA==.',
Za='Zandramadas:BAAANQAECgQIBAAAAA==.Zaraline:BAAANQADCgcICgAAAA==.',
Ze='Zeakz:BAAANQAECgEIAQAAAA==.',
Zy='Zyfae:BAAANQADCggICAAAAA==.Zyyn:BAAANQADCgUIBQAAAA==.',
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
