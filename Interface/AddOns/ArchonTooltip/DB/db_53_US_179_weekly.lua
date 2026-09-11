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
local provider = {region='US',realm='Rexxar',name='US',type='weekly',zone=53,date='2026-09-08',data={Ad='Adanac:BAAANQADCggICwAAAA==.Adow:BAAANQAECgEIAQAAAA==.Adynne:BAAANQAECgIIAgABNQAECgIIAgABAAAAAA==.',
Ae='Aered:BAAANQADCgUIBgAAAA==.',
Ah='Ahira:BAAANQAECgMIBAAAAA==.',
Ai='Aishe:BAAANQADCggIEwAAAA==.',
Ak='Akashã:BAAANQAECgYICQAAAA==.Akuria:BAAANQAECgUIBwAAAA==.',
Al='Alacía:BAAANQADCgIIAgAAAA==.Alahna:BAAANQADCgcIEAAAAA==.',
An='Anies:BAAANQAECgQIBgAAAA==.',
Aq='Aquarian:BAAANQADCgcIBwAAAA==.',
Ar='Artëmîs:BAAANQAECgEIAQAAAA==.',
As='Asmodeuss:BAAANQADCggIEAAAAA==.Assasincross:BAAANQADCgEIAQAAAA==.',
Au='Aurna:BAAANQAECgIIBAABNQAECgQICQABAAAAAA==.',
Ba='Babysneeze:BAAANQADCgYIBQAAAA==.Badbev:BAAANQADCgMIBAABNQADCgYICQABAAAAAA==.Barene:BAAANQAECggIBwAAAA==.Batmuhn:BAAANQADCgEIAQAAAA==.',
Be='Belserion:BAAANQAECggIEAAAAA==.Beltryne:BAAANQADCggIDQABNQAECggIEAABAAAAAA==.Berol:BAAANQAECgMIAwAAAA==.Beroldin:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Bevar:BAAANQADCgMIAwABNQADCgYICQABAAAAAA==.Bevell:BAAANQADCgQIAgABNQADCgYICQABAAAAAA==.',
Bl='Blindmafaka:BAAANQAECgIIAgAAAA==.',
Bo='Bonney:BAAANQAECgEIAQAAAA==.Bonzai:BAAANQADCgQIAwAAAA==.',
Br='Bradycam:BAAANQAECgQIBAAAAA==.Brightlock:BAAANQADCgYIDAAAAA==.',
Bu='Bulloo:BAAANQADCgIIAgAAAA==.',
Ca='Cantpalyhard:BAAANQADCgIIBAABNQAECgMIBAABAAAAAA==.Casella:BAAANQAECgYICQAAAA==.',
Ce='Celerrime:BAAANQABCgUIBgAAAA==.',
Ch='Chilindrina:BAAANQABCgIIAgAAAA==.Chupacabbra:BAAANQAECgUIBgAAAA==.',
Cl='Cleth:BAAANQAECgIIAgAAAA==.',
Co='Corax:BAAANQAECgIIAgAAAA==.',
Cu='Cutie:BAAANQADCgMIAwAAAA==.',
Da='Damachi:BAAANQAECgEIAQAAAA==.Danji:BAAANQAECgQIBAAAAA==.Darkasuna:BAAANQADCgQIBAAAAA==.Darmorae:BAAANQAECgIIAgAAAA==.Dashii:BAAANQADCggIAQABNQAECggIAQABAAAAAA==.Datewoo:BAAANQADCgQIBAAAAA==.',
De='Deathlock:BAAANQAECggIAQAAAA==.Deathris:BAAANQADCggIFgAAAA==.Demonish:BAAANQAECgQIBAAAAA==.Demontotem:BAAANQADCggIFAAAAA==.',
Di='Dillinquent:BAAANQADCgUIBgAAAA==.',
Dr='Dracfu:BAAANQADCgIIAgABNQAECgYICQABAAAAAA==.Drackpally:BAAANQADCggICQAAAA==.Dracshot:BAAANQAECgYICQAAAA==.Dracslana:BAAANQADCgUICAABNQAECgYICQABAAAAAA==.Draffel:BAAANQADCggIDgAAAA==.',
Du='Dukstorm:BAAANQADCggICAAAAA==.Dundinn:BAAANQADCgMIAwABNQAECgQICQABAAAAAA==.Dunzer:BAAANQAECgMIBAAAAA==.',
Ed='Edithpoothe:BAAANQAECgQIBAAAAA==.',
El='Electricks:BAAANQAECgQIBAAAAA==.Elicia:BAAANQADCgUIBQAAAA==.',
Em='Emmii:BAAANQADCgEIAQAAAA==.',
En='Enazure:BAAANQADCgcICwAAAA==.',
Ep='Epiphaný:BAAANQAECgQIBgABNQAECggIAQABAAAAAA==.',
Er='Eradoria:BAAANQADCggIFAAAAA==.',
Et='Etrigon:BAAANQADCgYICAAAAA==.',
Ev='Evadne:BAAANQADCgYICAAAAA==.',
Ex='Extremespeed:BAAANQADCgcIEwABNQAECgQIBAABAAAAAA==.',
Fa='Fangy:BAAANQABCgIIAwAAAA==.',
Fi='Fistantillus:BAAANQABCgIIAwAAAA==.',
Fl='Flopper:BAAANQAECgYICQAAAA==.',
Fo='Foxyboo:BAAANQAECgMIBAAAAA==.',
Fr='Freak:BAAANQADCggIAQAAAA==.Freakpeachh:BAAANQAECgQIBAAAAA==.',
Ga='Galerodra:BAAANQADCggICAAAAA==.Garalline:BAAANQADCgYICAAAAA==.',
Gn='Gnomatic:BAAANQAECgQIBgAAAA==.',
Go='Gooberetta:BAAANQAECgIIAwAAAA==.Gope:BAAANQAECgQIBwAAAA==.',
Gr='Gromiir:BAAANQAECgQIBAAAAA==.',
['Gä']='Gärrus:BAAANQAECgIIAgAAAA==.',
He='Hellkat:BAAANQADCgIIAgAAAA==.',
Hi='Higarosa:BAAANQADCgQIBAAAAA==.Highbull:BAAANQAECggIAQAAAA==.',
Ho='Holiblade:BAAANQAECgMIAwAAAA==.Holyhannah:BAAANQADCgIIAQAAAA==.Hooligun:BAAANQADCgYICwAAAA==.',
Hy='Hypérian:BAAANQAECgEIAQAAAA==.',
Ia='Ianes:BAAANQADCgYIBwAAAA==.Iantha:BAAANQADCgUIBQAAAA==.',
Ic='Icesikle:BAAANQAECgQIBAAAAA==.',
Ij='Ijustshotyou:BAAANQAECgQICgAAAA==.',
In='Insaniac:BAAANQADCggIBwAAAA==.Intervention:BAAANQABCgIIBAAAAA==.',
Iz='Izumo:BAAANQADCggIDQAAAA==.',
Ja='Jatswamdi:BAAANQAECgYICQAAAA==.',
Jn='Jnymango:BAAANQAECgQIBAAAAA==.',
Jo='Johnnysham:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.Jollakeratu:BAAANQAECgIIAgAAAA==.Josequervo:BAAANQADCgIIAgAAAA==.',
Ju='Jugram:BAAANQADCgUICAAAAA==.Jusmissiner:BAAANQADCggIEAAAAA==.Juut:BAAANQADCggIDgAAAA==.',
Ke='Keelhorn:BAAANQAECgUICQAAAA==.',
Ki='Kilthas:BAAANQADCggIDQAAAA==.Kinkyhawt:BAEANQAECgYIBQAAAA==.Kintssiralop:BAAANQADCgUIBgAAAA==.Kirio:BAAANQADCgIIAgAAAA==.Kitsunenohi:BAAANQAECgIIAgAAAA==.Kitsunezorro:BAAANQAECgIIAwAAAA==.',
Ko='Kornbread:BAAANQADCgEIAwAAAA==.',
Kr='Kraelith:BAAANQAECgMIAwAAAA==.Krattos:BAAANQAECgEIAQAAAA==.',
Ks='Ksandra:BAAANQADCgYIDwAAAA==.Ksares:BAAANQAECgYICgAAAA==.',
Ky='Kyantzmi:BAAANQADCgEIAQAAAA==.Kyogre:BAAANQADCgUIDQAAAA==.',
La='Laeflockxo:BAAANQADCggICAAAAA==.Laefnia:BAAANQAECgYICwAAAA==.Laraydra:BAAANQADCgYICAABNQAECgQICQABAAAAAA==.Lastofgoobs:BAAANQADCgIIAgAAAA==.',
Li='Lildarleena:BAAANQADCgUIBQAAAA==.Lilis:BAAANQADCgYIDgAAAA==.Lilithe:BAAANQAECgMIAwAAAA==.Littlebev:BAAANQADCgYICQAAAA==.',
Lo='Longshankss:BAAANQAECgEIAQAAAA==.',
Lu='Lucifers:BAAANQADCgMIAwAAAA==.',
Ma='Maiikeru:BAAANQADCgUIBgAAAA==.Malaurray:BAAANQADCggICQAAAA==.Maluin:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.',
Mc='Mcchong:BAAANQADCgUIBQAAAA==.Mckennah:BAAANQAECgIIAgAAAA==.',
Me='Melinea:BAAANQAECgMIAwAAAA==.Mereidith:BAAANQAECgYIDwAAAA==.Mesohungry:BAAANQAECgQIBAAAAA==.',
Mi='Mir:BAAANQADCggICAAAAA==.Missnoms:BAAANQADCgYIEgAAAA==.',
Mo='Moostradamas:BAAANQADCgcIEgAAAA==.Morcilla:BAAANQAECgEIAQAAAA==.',
Na='Nacole:BAAANQADCgYIBgAAAA==.Nalleth:BAAANQADCgYIBgAAAA==.Naturegoob:BAAANQAECgQIBgAAAA==.Naughtynurse:BAAANQAECgQIBAAAAA==.',
Ne='Neuma:BAAANQADCgcIDQAAAA==.',
Ni='Nicfurry:BAAANQADCgEIAQAAAA==.Nightflower:BAAANQAECgQIBQAAAA==.',
No='Nostromo:BAAANQAECgYICQAAAA==.',
Ob='Obiejuan:BAAANQAECgYIDAAAAA==.',
Od='Odbc:BAAANQAECgYIBgAAAA==.Oddball:BAAANQAECgUICAAAAA==.',
Or='Orthiaa:BAAANQADCgYIDwAAAA==.',
Pa='Paintrain:BAAANQAECgMIAwAAAA==.',
Pe='Peso:BAAANQAECgEIAQABNQAECggIAQABAAAAAA==.Pez:BAAANQAECgYICQAAAA==.',
Ph='Phaidon:BAAANQADCggICAAAAA==.',
Pi='Pixularformd:BAAANQADCgYICQAAAA==.',
Po='Polyhedroll:BAAANQAECgcIEgABNQADCgYIBgABAAAAAA==.Postmalorne:BAAANQADCgEIAQAAAA==.Powerzone:BAAANQADCgEIAgAAAA==.',
Pu='Punchandkick:BAAANQAECgIIAwAAAA==.Punchdeath:BAAANQADCgUIBQAAAA==.',
Qu='Quivermethis:BAAANQADCgUIBQAAAA==.',
Ra='Radge:BAAANQAECgcICwAAAA==.Ralanar:BAAANQAECgQICQAAAA==.Raljah:BAAANQAECgMIAwABNQAECgMIAwABAAAAAA==.',
Re='React:BAAANQAECgYICQAAAA==.Renpriest:BAAANQADCgYIDQAAAA==.',
Ri='Richpplwater:BAAANQADCgIIAgAAAA==.',
Ru='Rubyraeven:BAAANQADCgYIBgAAAA==.',
Ry='Ryobi:BAAANQAECgUIBwAAAA==.',
Sa='Saintangel:BAAANQABCgQIAgAAAA==.Salinan:BAAANQAECgYIDAAAAA==.Saric:BAAANQAECgQIBAAAAA==.',
Se='Serdav:BAAANQADCgYIBgAAAA==.',
Sh='Shak:BAAANQADCgYIBgAAAA==.Shalai:BAAANQAECgQIBQAAAA==.Shilóh:BAAANQADCgYIBgAAAA==.Shyandrial:BAAANQADCgYIEgAAAA==.Shyness:BAAANQADCggICAAAAA==.',
Sk='Skychades:BAAANQADCggIEwAAAA==.',
Sn='Sneakygoob:BAAANQADCgMIAwAAAA==.',
Sp='Spookycurse:BAAANQADCgEIAQAAAA==.Spookydeath:BAAANQAECgUICgAAAA==.Spookypriest:BAAANQADCgIIAgAAAA==.',
Sr='Srsnacksalot:BAAANQADCgQIBAAAAA==.',
St='Stileto:BAAANQADCggIDQABNQAECggIAQABAAAAAA==.Stoneydracco:BAAANQAECgQIBQAAAA==.',
Su='Sumtinwng:BAAANQADCggIEQAAAA==.Sunchipz:BAAANQADCgQIBAAAAA==.Supervicious:BAAANQADCggIDgAAAA==.',
Sy='Sylur:BAAANQAECgQIBAAAAA==.',
Ta='Tahren:BAAANQAECggIEQAAAA==.Tahshock:BAAANQADCgYICwABNQAECggIEQABAAAAAA==.Taler:BAAANQADCgIIAgAAAA==.Talerion:BAAANQAECgIIAwAAAA==.',
Te='Temporalize:BAAANQABCgYIBgAAAA==.',
Th='Thatonemonk:BAAANQADCgQIBAAAAA==.Thistelbear:BAAANQAECgEIAQAAAA==.Thornbloom:BAAANQADCggICAAAAA==.Thrallsux:BAAANQABCgYIBwAAAA==.Thraun:BAAANQADCggIDgAAAA==.Thunderdin:BAAANQAECgQIAwABNQAECgYIBgABAAAAAA==.',
Ti='Tirrian:BAAANQADCggICAAAAA==.Titszilla:BAAANQADCgMIAwABNQAECggIAQABAAAAAA==.',
To='Tokidh:BAAANQADCgYIBgAAAA==.Tokihots:BAAANQADCgQICAAAAA==.',
Tw='Twamsack:BAAANQABCgQIBAAAAA==.',
Um='Umbrarogue:BAAANQADCggIDQAAAA==.',
Va='Vaara:BAAANQABCgEIAQAAAA==.Valaa:BAAANQAECgEIAQAAAA==.Vanddrena:BAAANQAECgQIBAAAAA==.',
Ve='Velien:BAAANQAECgUIBQAAAA==.',
Vi='Vicotr:BAAANQADCgQIBgAAAA==.Viddysouls:BAAANQADCgYIDgAAAA==.Vite:BAAANQADCggIAgAAAA==.',
Vo='Vonmiller:BAAANQAECgMIBgAAAA==.',
Vy='Vynllàn:BAAANQADCgYICgAAAA==.',
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
