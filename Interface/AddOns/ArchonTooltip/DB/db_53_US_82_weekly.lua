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
local provider = {region='US',realm='Duskwood',name='US',type='weekly',zone=53,date='2026-09-01',data={Ad='Adhira:BAAANQADCgUICAAAAA==.',
Ae='Aegennai:BAAANQADCgcIDQAAAA==.Aegondk:BAEANQAECgYIBwAAAA==.Aelias:BAAANQADCgYICQAAAA==.Aevaela:BAAANQAECgIIAgAAAA==.',
Ag='Agilaz:BAAANQADCggIDgAAAA==.',
Ak='Akey:BAAANQADCgYIBgAAAQ==.Akhae:BAAANQAECgMIAwAAAA==.',
Al='Albinism:BAAANQADCgYICQAAAA==.Alcadeias:BAAANQADCgYIBwAAAA==.Alethiah:BAAANQADCgQIBQAAAA==.',
An='Anaeda:BAAANQADCgcIDAAAAA==.Andrömëdä:BAAANQADCgEIAQAAAA==.Anubisre:BAAANQADCgIIAgAAAA==.',
Ar='Arccane:BAAANQADCgIIAgAAAA==.Arthar:BAAANQADCgYIBgABNQADCgYIDAABAAAAAA==.',
As='Ashvyth:BAAANQADCggIDgAAAA==.',
Aw='Awwyeah:BAAANQADCgIIAgAAAQ==.',
Ba='Baldpunch:BAAANQADCgYIBwAAAA==.Balomdruid:BAAANQADCgQIBAAAAA==.Barnabus:BAAANQAECgEIAQAAAA==.',
Be='Beachbecrazy:BAAANQADCgcICAAAAA==.Beaj:BAAANQADCgEIAQAAAA==.Beastlypläyä:BAAANQADCgIIAgAAAA==.Belládonna:BAAANQADCggICAAAAA==.',
Bi='Bilac:BAAANQADCgEIAQABNQAECgQIBAABAAAAAA==.',
Bl='Blusoleil:BAAANQADCgEIAQAAAA==.',
Bo='Bonerblast:BAAANQADCggICgAAAA==.Boston:BAAANQAECgEIAQAAAA==.',
Br='Branches:BAAANQADCgYICwAAAA==.Brewtholomew:BAAANQAECgEIAQAAAA==.Briggsey:BAAANQADCgYICwAAAA==.Briznot:BAAANQADCgcIDAAAAA==.Bryce:BAAANQADCgUIBQAAAA==.',
Bu='Bubbadubya:BAAANQADCgQIBQAAAA==.Bunnyfu:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.Burningwolf:BAAANQAECgEIAQAAAA==.',
['Bó']='Bórs:BAAANQAECgIIAgAAAA==.',
Ca='Caiden:BAAANQADCgYIBgAAAA==.Caitlyn:BAAANQADCgEIAQAAAA==.Caleesia:BAAANQADCgQIBQAAAA==.Carnìfex:BAAANQADCgYICQAAAA==.Caskaerta:BAAANQADCgUIBQAAAA==.Catbrin:BAAANQADCgcIDQAAAA==.',
Ce='Cerà:BAAANQADCgYIBgAAAA==.',
Ch='Chapslop:BAAANQADCgcIDAAAAA==.',
Cl='Clobberben:BAAANQADCgQIBAAAAA==.Cloudbreaker:BAAANQADCgEIAQAAAA==.',
Co='Cobramage:BAAANQADCgQIBAAAAA==.Constellate:BAAANQADCgYIBgAAAA==.Cotterpins:BAAANQADCgcIDAAAAA==.',
Cy='Cybrkatz:BAAANQADCgIIAgAAAA==.',
Cz='Cztalone:BAAANQADCgQIBAAAAA==.',
['Cè']='Cèlane:BAAANQAECgMIAwAAAA==.',
Da='Damitsu:BAEANQADCgUIBQABNQADCgYICQABAAAAAA==.Damnitsu:BAEANQADCgYICQAAAA==.Darckside:BAAANQABCgMIAwAAAA==.',
De='Deadflexy:BAAANQADCgcIDAAAAA==.Deathberry:BAAANQADCggIDQAAAA==.Deathvoker:BAAANQADCgYICwAAAA==.Deekan:BAAANQADCgcIDQAAAA==.Demonblood:BAAANQAECgEIAQAAAA==.Deräth:BAAANQADCgYIBgAAAA==.Devlik:BAAANQADCgEIAQAAAA==.Dew:BAAANQADCgYIBgAAAA==.',
Di='Dimensius:BAAANQAECgEIAQAAAA==.Dinkalopogis:BAAANQADCgQIBQAAAA==.Ditsie:BAAANQADCgUIBQAAAA==.',
Dm='Dmega:BAAANQADCgYIDAAAAA==.',
Dr='Dragondude:BAAANQADCggIDgAAAA==.',
Du='Durango:BAAANQADCgMIAwAAAA==.',
Dy='Dyelin:BAAANQADCggIDgAAAA==.',
El='Elyron:BAAANQADCggIDgAAAA==.',
En='Endofall:BAAANQAECgEIAQAAAA==.',
Ep='Epiczimbabue:BAAANQADCgEIAQAAAA==.',
Es='Esrahaddon:BAAANQAECgEIAQAAAA==.',
Et='Et:BAAANQAECgEIAQAAAA==.Etheri:BAAANQADCgQIBAAAAA==.',
Ez='Ezhra:BAAANQABCgEIAQABNQADCgQIBQABAAAAAA==.Ezind:BAAANQADCgEIAQAAAA==.',
Fa='Fakename:BAAANQADCggIDQAAAA==.Fakesaint:BAAANQAECgMIAwAAAA==.Fangstorm:BAAANQADCggIDgAAAA==.Farorê:BAAANQADCgYIBgAAAA==.Fazz:BAAANQADCgQIBAAAAA==.',
Fe='Feldruid:BAAANQAECgEIAQAAAA==.Felup:BAAANQAECgMIAwAAAA==.',
Fo='Folstagg:BAAANQADCgcIDAAAAA==.Foreverem:BAAANQADCgYIBgAAAA==.',
Fr='Frostynewf:BAAANQADCgYIBgAAAA==.',
Fu='Fujitora:BAAANQADCggIDgAAAA==.',
Gl='Glenys:BAAANQADCgEIAQAAAA==.',
Gr='Graxus:BAAANQADCgQIBAAAAA==.Greth:BAAANQADCgQIBQAAAA==.Grimshotzz:BAAANQADCggICQAAAA==.',
Gu='Gudge:BAAANQAECgQIBAAAAA==.Gummypenguin:BAAANQAECgYIDAABNQAECggIDwABAAAAAA==.',
Ha='Hadhox:BAAANQADCgYICwAAAA==.Hathdox:BAAANQADCgYICgABNQADCgYICwABAAAAAA==.Hawkulees:BAAANQADCgMIAwAAAA==.Hazelnoot:BAAANQAECgMIAwAAAA==.',
He='Hegaphie:BAAANQADCgEIAQAAAA==.Hexcist:BAAANQADCggIDQAAAA==.',
Hi='Hitsuryu:BAAANQADCgcIDQAAAA==.',
Ho='Hollyanne:BAAANQADCggIDgAAAA==.Hoonicorn:BAAANQADCgEIAQABNQADCgIIAgABAAAAAA==.Hornsharp:BAAANQADCgQIBgAAAA==.',
Hu='Hunalli:BAAANQADCgUIBwABNQAECgQIBAABAAAAAA==.Hunilla:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.',
Ia='Iamu:BAAANQADCgMIAwAAAA==.',
Ie='Ieatwetsocks:BAAANQAECgUIBwAAAA==.',
Ig='Ignivar:BAAANQADCgUICAAAAA==.',
In='Insaint:BAAANQADCgYIBgAAAA==.',
Ir='Ironfield:BAAANQADCggIDgAAAA==.Irony:BAAANQAECgIIAgAAAA==.',
Is='Isabellë:BAAANQADCggIDgAAAA==.',
Je='Jessamine:BAAANQAECgMIAwAAAA==.Jetta:BAAANQADCgYICQAAAA==.Jezzak:BAAANQADCggIDgABNQAECgEIAQABAAAAAA==.',
Jo='John:BAAANQAECgYICQAAAA==.Jorien:BAAANQADCggIDQAAAA==.',
Jp='Jp:BAAANQADCgQIBQAAAA==.Jpd:BAAANQADCgQIBQABNQADCgQIBQABAAAAAA==.',
Ju='Justadwarf:BAAANQADCgcICQAAAA==.Juston:BAAANQADCggIDgAAAA==.',
Ka='Kaboonsky:BAAANQAECgEIAQAAAA==.Kaeamani:BAAANQADCgYIBwAAAA==.Kaenaya:BAAANQADCgIIAgAAAA==.Kamikori:BAAANQADCgcIDQAAAA==.Kardell:BAAANQADCgYIDAAAAA==.Kardels:BAAANQADCgQIBAABNQADCgYIDAABAAAAAA==.Karnadaz:BAAANQAECgYICgAAAA==.Karnkarn:BAAANQADCgcICAAAAA==.Karnn:BAAANQADCggIDgAAAA==.Katalight:BAAANQADCgEIAQAAAA==.',
Ke='Keho:BAAANQAECgEIAQAAAA==.',
Ki='Kiascendance:BAAANQAECgQIBQAAAA==.',
Ko='Kolosho:BAAANQADCgcIEwAAAA==.Korxon:BAAANQAECgQIBAAAAA==.Kotus:BAAANQADCgcIDQAAAA==.',
Ks='Ksyusha:BAAANQADCgYIBgAAAA==.',
['Kä']='Kämi:BAAANQADCgEIAQABNQADCgYIDwABAAAAAA==.',
La='Lanuadra:BAAANQAECgEIAQAAAA==.',
Le='Leasidhe:BAAANQADCgcICAABNQADCgQIBAABAAAAAA==.',
Lg='Lghtninstorm:BAAANQADCgEIAQAAAA==.',
Li='Lillié:BAAANQABCgIIAQAAAA==.Lilysham:BAAANQAECggIDAAAAA==.Lindar:BAAANQABCgIIAgAAAA==.Linddrel:BAAANQADCggIFQAAAA==.',
['Lø']='Løllîe:BAAANQADCgYIBgAAAA==.',
Ma='Macarius:BAAANQADCgcICwAAAA==.Macdee:BAAANQADCgMIAwABNQADCgYIDAABAAAAAA==.Mageless:BAAANQADCgIIAgAAAA==.Magpie:BAAANQADCgYIDAAAAA==.Maimed:BAAANQADCggIDQAAAA==.Malotan:BAAANQABCgEIAQABNQABCgIIAgABAAAAAA==.Manaster:BAAANQADCgEIAQAAAA==.Maravanna:BAAANQADCgEIAQAAAA==.Martlok:BAAANQADCggIDQAAAA==.Mathas:BAAANQADCgYICgAAAA==.Maynis:BAAANQABCgQIBAAAAA==.',
Mc='Mcbrynhammer:BAAANQADCgIIAwAAAA==.',
Me='Merkii:BAAANQADCgYIBgABNQADCgcIBwABAAAAAA==.',
Mi='Micflinigan:BAAANQADCgcICwAAAA==.Minarii:BAAANQADCgYIDQAAAA==.',
Mo='Mochimochi:BAAANQADCgQIBAAAAA==.Mommieuppies:BAAANQADCgcIBwAAAA==.Moonshae:BAAANQAECgMIAwAAAA==.Mortalbion:BAAANQADCgUICgAAAA==.',
My='Mystiquè:BAAANQADCgQIBQAAAA==.',
Na='Naithin:BAAANQAECgEIAQAAAA==.',
Ni='Nightray:BAAANQADCgYIDAAAAA==.',
No='Nonsocial:BAAANQAECgMIAwABNQAFFAIIAgABAAAAAA==.Noriisa:BAAANQAECgEIAQAAAA==.Notamathguy:BAAANQADCggIDgAAAA==.Noudders:BAAANQADCgUIBQAAAA==.',
Ny='Nyvak:BAAANQADCgYIBgAAAA==.',
Od='Odinhand:BAAANQAECgMIAwAAAA==.',
Ol='Oliissa:BAAANQADCgQIBQAAAA==.',
Oz='Ozwäldo:BAAANQAECgYICgAAAA==.',
Pa='Pandapí:BAAANQADCgYIBgAAAA==.Panduh:BAAANQAECgEIAQAAAA==.Pandóra:BAAANQADCgIIAwAAAA==.Pariousa:BAAANQAECggICwAAAA==.',
Pe='Peppermintxo:BAAANQADCgIIAgABNQADCgIIAgABAAAAAA==.',
Pi='Pinkeepink:BAAANQADCgYICgAAAA==.',
Pr='Pres:BAAANQADCgQIBAAAAA==.Prild:BAAANQABCgQIBgAAAA==.',
Pu='Pumpernickle:BAAANQADCgcICQAAAA==.',
Ra='Rahzon:BAAANQADCgYIBgAAAA==.Ralganor:BAAANQAECgMIAwAAAA==.Ralzin:BAAANQADCgMIAwAAAA==.Ramanash:BAAANQADCgQIBwAAAA==.Raynlight:BAAANQADCggIDQAAAA==.',
Re='Retacus:BAAANQADCgYIBgAAAA==.',
Ri='Rina:BAAANQAECgYICQAAAA==.Ringadingg:BAAANQADCggIDgAAAA==.',
Sa='Sarka:BAAANQADCgcIBwAAAA==.Sasquatch:BAAANQADCgcIDAAAAA==.',
Sc='Scony:BAAANQADCgYIBwAAAA==.Scribs:BAAANQADCgYICQAAAA==.',
Se='Seismic:BAAANQADCggICAAAAA==.Severànce:BAAANQAECgIIAgAAAA==.Sevivify:BAAANQADCgIIAwABNQAECgIIAgABAAAAAA==.',
Sh='Shablammy:BAAANQADCgcIDQAAAA==.Shadowginni:BAAANQADCgcIDAAAAA==.Shanker:BAAANQADCgMIAwAAAA==.Shefu:BAAANQAECgIIAgAAAA==.Shfifty:BAAANQAECgEIAQAAAA==.Shutupbird:BAAANQADCgMIAwAAAA==.',
Si='Silris:BAAANQADCgMIAwAAAA==.',
Sk='Skydragon:BAAANQADCgUICAAAAA==.',
Sl='Slonk:BAAANQADCgYICgAAAA==.',
So='Sofia:BAAANQADCgcIDAAAAA==.',
Sp='Spiritly:BAAANQADCgMIAwAAAA==.Sploof:BAAANQADCgYIBgAAAA==.',
St='Starmist:BAAANQADCgQIBQAAAA==.Stubly:BAAANQADCgQIBAAAAA==.',
Su='Sunfyrie:BAAANQADCgYIBgAAAA==.',
Sw='Sweèt:BAAANQADCgYIBgAAAA==.',
Ta='Taurdk:BAAANQADCggICgAAAA==.Taylorshift:BAAANQADCggIDQAAAA==.',
Te='Teaar:BAAANQADCgUIBQABNQADCggIDQABAAAAAA==.Teetau:BAAANQADCggIDgAAAA==.',
Th='Thadregosa:BAAANQADCggIDgAAAA==.Thander:BAAANQADCgMIAwABNQADCgUIBQABAAAAAA==.',
Ti='Tiffy:BAAANQADCgQIBAAAAA==.Timoleon:BAAANQADCgMIAwAAAA==.Tirna:BAAANQADCgUIBQAAAA==.Tirnotham:BAAANQADCgYIBgAAAA==.',
Tm='Tmtglizzy:BAAANQAECgIIAgAAAA==.',
To='Tokalu:BAAANQADCgcIDAAAAA==.Tonjudsonson:BAAANQAECgYICgAAAA==.Torath:BAAANQADCgUIBQAAAA==.',
Tu='Turdimer:BAAANQADCgQIBwAAAA==.',
Tw='Twiki:BAAANQADCgcIDQAAAA==.Twobricks:BAAANQAECgMIAwAAAA==.',
Ty='Tyrielas:BAAANQADCgYIBwAAAA==.Tyrssana:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.',
Uh='Uhmerica:BAAANQAECgMIAwAAAA==.',
Ur='Urdeadtoo:BAAANQAECgEIAQAAAA==.Urthkwayk:BAAANQADCgYIBgAAAA==.',
Va='Vaterunser:BAAANQADCgYIBgAAAA==.Vazoom:BAAANQAECgEIAQAAAA==.',
Ve='Velskud:BAAANQADCgQIBwAAAA==.',
Vi='Vinhar:BAAANQADCgUIBwAAAA==.',
Vo='Voidsavage:BAAANQADCgUICAAAAA==.Voidwing:BAAANQADCgUIBQAAAA==.Volic:BAAANQADCggICwAAAQ==.Voznje:BAAANQAECgEIAQAAAA==.',
We='Wesleypipes:BAAANQADCgcIDQAAAA==.',
Wh='Whisteria:BAAANQADCgYIBgAAAA==.',
Wi='Wizalf:BAAANQADCgEIAQAAAA==.',
Wo='Wolfmato:BAAANQAECgQIBAAAAA==.',
Wy='Wynne:BAAANQADCgQIBAAAAA==.',
Xa='Xalabro:BAAANQADCgcIDQAAAA==.',
Xe='Xerxeis:BAAANQABCgIIAgABNQADCgcIEwABAAAAAA==.',
Xo='Xousa:BAAANQADCgQIBgABNQAECggICwABAAAAAA==.',
Ys='Yssuplef:BAAANQADCgYIBgAAAA==.',
Za='Zaiyra:BAAANQADCgEIAQAAAA==.Zakoor:BAAANQADCgUICAAAAA==.Zareena:BAAANQADCgQIBAAAAA==.Zarnia:BAAANQADCgMIAwAAAA==.Zarrock:BAAANQADCgIIAgAAAA==.Zavatan:BAAANQADCgQIBwAAAA==.',
Ze='Zebbyzebzeb:BAAANQADCgQIBwAAAA==.Zekia:BAAANQADCgcIBwAAAA==.Zerm:BAAANQAECgEIAQAAAA==.',
Zi='Zinnkura:BAAANQADCgIIAgAAAA==.',
Zo='Zorsa:BAAANQADCgYICgAAAA==.',
Zu='Zuljawn:BAAANQADCggIDgAAAA==.',
Zy='Zyphos:BAAANQADCgIIAgAAAA==.',
['Ñô']='Ñôg:BAAANQADCgEIAQAAAA==.',
['Ød']='Ødis:BAAANQADCgIIAgAAAA==.',
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
