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
local provider = {region='US',realm='Perenolde',name='US',type='weekly',zone=53,date='2026-09-01',data={Aa='Aanien:BAAANQADCgYICAAAAA==.',
Ac='Acedk:BAAANQAECgQIBgAAAA==.',
Ad='Adrador:BAAANQADCggIDgAAAA==.Adrenaline:BAAANQAECgYICAAAAA==.',
Ae='Aelik:BAAANQAECgUIBwAAAA==.Aeolian:BAAANQADCgUICAAAAA==.',
Al='Alayssa:BAAANQADCggIDgAAAA==.Alda:BAAANQADCgIIAgAAAA==.Alemental:BAAANQAECgEIAQAAAA==.Allarius:BAAANQADCgYIBgAAAA==.',
Am='Amilee:BAAANQADCgMIBQAAAA==.Amoondai:BAAANQADCgIIAgAAAA==.Amoondrin:BAAANQAECgEIAgAAAA==.',
An='Anatyr:BAAANQADCgMIAwAAAA==.',
Ar='Aramathis:BAAANQADCgUICgAAAA==.Arbor:BAAANQADCgIIAgAAAA==.Arcillias:BAAANQADCgUIBQABNQAECgQIBgABAAAAAA==.Arthia:BAAANQADCgYICQAAAA==.Arvidpally:BAAANQADCgUIBQAAAA==.',
As='Ashesius:BAAANQAECgQIBQAAAA==.',
At='Atredes:BAAANQAECgIIAgAAAA==.',
Au='Auspex:BAAANQADCgYIBgAAAA==.',
Av='Avaryn:BAAANQAECgIIAwAAAA==.',
Ba='Badaracka:BAAANQAECgMIAwAAAA==.Bahamuth:BAAANQAECgEIAQAAAA==.Bahamutsrage:BAAANQADCgYIBgAAAA==.Barbattos:BAAANQAECgUIBwAAAA==.',
Be='Bexley:BAAANQAECgEIAQAAAA==.',
Bi='Biglarry:BAAANQADCgMIBQAAAA==.',
Bl='Blacklok:BAAANQADCggICAABNQAECgIIAwABAAAAAA==.Blargle:BAAANQADCgUICQAAAA==.Blegh:BAAANQAECgYIBwAAAA==.Blinx:BAAANQAECgEIAQAAAA==.Bloodrake:BAAANQAECgQIBQAAAA==.',
Bm='Bman:BAAANQADCgUIBQAAAA==.',
Br='Braneour:BAAANQAECgEIAQAAAA==.',
Bu='Bumm:BAAANQADCgIIAwAAAA==.',
Bz='Bzspy:BAAANQAECgIIAwAAAA==.',
['Bë']='Bëar:BAAANQAECgEIAQAAAA==.',
Ca='Calyptus:BAAANQAECgIIAwAAAA==.Capylaura:BAAANQAECgIIAgAAAA==.Caratine:BAAANQADCgYICgAAAA==.Cassandrah:BAAANQAECgMIAwAAAA==.',
Ce='Celìa:BAAANQADCggICgAAAA==.',
Ch='Christy:BAAANQADCgIIAgAAAA==.Chugg:BAAANQADCggICAAAAA==.',
Ci='Ciaphus:BAAANQAECgEIAQAAAA==.',
Cl='Clogs:BAAANQAECgEIAQAAAA==.',
Co='Coragrr:BAAANQAECgIIAwAAAA==.',
Cr='Cracklepants:BAAANQAECgUICgAAAA==.Crashout:BAAANQADCgQIBAAAAA==.',
Cu='Curtastrophe:BAAANQAECgEIAgAAAA==.',
Da='Daelanos:BAAANQADCgcIBwAAAA==.Dallas:BAAANQADCgMIBQAAAA==.',
De='Deathoof:BAAANQADCgcICgABNQADCgcIDQABAAAAAA==.Demonilla:BAAANQADCgYIBgAAAA==.Destro:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.',
Di='Dilaudyd:BAAANQADCgMIBQAAAA==.Disputatious:BAAANQADCgQIBAAAAA==.',
Do='Dogaz:BAAANQADCgIIAgAAAA==.Donori:BAAANQADCgEIAQAAAA==.',
Dr='Dragonias:BAAANQADCgYICwAAAA==.Drakthorn:BAAANQADCgQIBAAAAA==.Drinny:BAAANQADCgcIDQAAAA==.Dripington:BAAANQAECgMIAwAAAA==.',
Ea='Earthangel:BAAANQADCgYICgAAAA==.',
Ef='Efon:BAAANQADCgUIBQABNQADCggIDgABAAAAAA==.',
Ei='Eine:BAAANQAECgQIBQAAAA==.',
El='Eldergreen:BAAANQADCggIDgAAAA==.Elfwine:BAAANQADCgYICgAAAA==.Elindria:BAAANQAECgIIAwAAAA==.Elminstir:BAAANQADCgYICwAAAA==.Eluzhion:BAAANQADCgUICAAAAA==.Elysian:BAAANQAECgIIAgAAAA==.',
Er='Eruptyon:BAAANQADCgYIBgABNQADCgcIDAABAAAAAA==.',
Ev='Eviae:BAAANQADCgYICgAAAA==.Evillure:BAAANQADCgYIDAAAAA==.',
Ex='Explanation:BAAANQADCgQIBAAAAA==.',
Fa='Falan:BAAANQADCgYICwAAAA==.',
Fe='Feår:BAAANQADCgYICwAAAA==.',
Fi='Finley:BAAANQADCgQIBAAAAA==.',
Fl='Flane:BAAANQAECgcICgAAAA==.Flexdruid:BAAANQADCgMIAwAAAA==.',
Fr='Fragil:BAAANQAECgEIAQAAAA==.',
Ga='Galena:BAAANQADCgYIDQAAAA==.Ganonn:BAAANQADCgUIBQAAAA==.',
Ge='Geshtal:BAAANQADCgUIBQAAAA==.',
Gi='Girion:BAAANQADCgYICgAAAA==.',
Gl='Glaiven:BAEANQAECgYICAAAAA==.Glyr:BAAANQAECgEIAQAAAA==.',
Go='Gorgrin:BAAANQADCgYICwAAAA==.',
Ha='Harkanum:BAAANQAECgQIBQAAAA==.Harrow:BAAANQADCgYICgAAAA==.Harvester:BAAANQADCgcICAAAAA==.',
He='Healinturds:BAAANQADCgEIAQAAAA==.Helloagain:BAAANQAECgMIAwAAAA==.',
Hi='Hidethetotem:BAAANQADCgUICQAAAA==.Hikari:BAAANQAECgQIBAAAAA==.',
Ho='Holyspike:BAAANQADCgYICwAAAA==.Homerr:BAAANQADCgYICwAAAA==.Honiahaka:BAAANQAECgEIAQAAAA==.Hottcakes:BAAANQAECgEIAQABNQAFFAEIAQABAAAAAA==.',
Hu='Humanoidlite:BAAANQABCgQIBgABNQAECgUIBQABAAAAAA==.Humanoidlock:BAAANQADCgYIDAABNQAECgUIBQABAAAAAA==.Humanoidwar:BAAANQAECgUIBQAAAA==.',
In='Inoru:BAAANQADCgYICgAAAA==.',
Ir='Irmaline:BAAANQADCgYICwAAAA==.',
It='Ithurtshuh:BAAANQADCgEIAQABNQADCgYICQABAAAAAA==.',
Je='Jerk:BAAANQAECgcIDQAAAA==.Jesper:BAAANQAECgQIBQAAAA==.Jetz:BAAANQADCgcICwAAAA==.',
Ji='Jilara:BAAANQADCgYICQAAAA==.Jimmyjim:BAAANQADCgYICwAAAA==.',
Jo='Joink:BAAANQADCgYIBgAAAA==.',
Jp='Jpepps:BAAANQAECgMIBAAAAA==.',
Jr='Jrose:BAAANQADCgYICwAAAA==.',
Ka='Kaiatra:BAAANQADCgYIDQAAAA==.Katalaystar:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Katalegdh:BAAANQABCgQIBQABNQADCgEIAQABAAAAAA==.Kaìju:BAAANQADCgYICwAAAA==.',
Ki='Kilmandaros:BAAANQADCgIIAgAAAA==.',
Ko='Korhina:BAAANQAECgQIBQAAAA==.',
Ku='Kudria:BAAANQADCgUIBwAAAA==.Kunei:BAAANQABCgMIAQAAAA==.Kurdran:BAAANQABCgIIAgAAAA==.Kuroyukihime:BAAANQAECgEIAQAAAA==.',
['Ká']='Kárma:BAAANQADCgYIBgABNQADCgYICwABAAAAAA==.',
La='Lashela:BAAANQADCgYICQAAAA==.Laughter:BAAANQADCgYICwAAAA==.Lazulie:BAAANQADCgYIBgAAAA==.',
Le='Lexapayne:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.',
Li='Lighthammer:BAAANQADCgIIAgAAAA==.Lightmessiah:BAAANQAECgEIAQAAAA==.Lilyvain:BAAANQADCgcIBwAAAA==.Lireal:BAAANQADCggIDgAAAA==.Livnod:BAAANQADCgMIAwAAAA==.',
Lo='Lonon:BAAANQAECgIIAgAAAA==.Lorine:BAAANQAECgQIBQAAAA==.',
Lu='Lunara:BAAANQADCgYIDAAAAA==.',
Ly='Lynnethe:BAAANQADCgcICwAAAA==.',
Ma='Malkiel:BAAANQAECgQIBwAAAA==.Mastakillah:BAAANQADCgQICAAAAA==.',
Me='Meeseeks:BAAANQAECgEIAQAAAA==.Merckel:BAAANQADCgcIDgAAAA==.',
Mi='Michello:BAAANQADCgYICwAAAA==.Millia:BAAANQADCgcIDAAAAA==.Mint:BAAANQAECgcICwAAAA==.Mintberrytea:BAAANQADCgMIAwABNQAECgcICwABAAAAAA==.Misstress:BAAANQAECgIIAgAAAA==.',
Mo='Moistweaver:BAAANQADCgYIBgAAAA==.Monoxide:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Moonhunt:BAAANQADCgQIBwAAAA==.Morkleb:BAAANQADCgQIBAAAAA==.Morrag:BAAANQADCgcICwAAAA==.Morrtisha:BAAANQADCgYIBgAAAA==.',
My='Myxie:BAAANQADCgcIDAAAAA==.',
['Mí']='Mísfìt:BAAANQAECgMIBAAAAA==.',
Na='Nakaito:BAAANQADCgQIBAABNQADCggIDQABAAAAAA==.Narcoleptic:BAAANQAECgQIBQAAAA==.Naturebreakr:BAAANQADCgYICgAAAA==.',
Ne='Nex:BAAANQADCgQICAAAAA==.',
Ni='Nightsawdy:BAAANQADCgYIDAAAAA==.Niightstorm:BAAANQADCgYIBgAAAA==.Nitefire:BAAANQADCgIIAgAAAA==.Nitélifé:BAAANQADCgQIBQAAAA==.',
Op='Opalinnas:BAAANQAECgIIAgAAAA==.',
Pa='Panzer:BAAANQADCggICAAAAA==.Passionfruit:BAAANQADCgQIBAAAAA==.',
Pe='Peachtea:BAAANQADCgIIAgAAAA==.Pepecojon:BAAANQADCggICAAAAA==.',
Pi='Pirodeath:BAAANQADCggIDgAAAA==.',
Pr='Pray:BAAANQAECgEIAQAAAA==.Prodarkangel:BAAANQADCgcICQAAAA==.',
Pu='Puckllane:BAAANQAECgEIAgAAAA==.',
Py='Pyre:BAAANQAECgQIBQABNQAECgEIAQABAAAAAA==.',
Qu='Quanah:BAAANQADCgUIBQAAAA==.Quivver:BAAANQADCgIIAgAAAA==.',
Ra='Rabmaxx:BAAANQADCgYICgAAAA==.Ravenlight:BAAANQAECgEIAQAAAA==.Raynman:BAAANQAECgEIAQAAAA==.',
Rh='Rhydian:BAAANQADCgQIBAAAAA==.Rhyzer:BAAANQADCgYICgAAAA==.',
Ri='Riiver:BAAANQADCgYIBgAAAA==.',
Ro='Roderick:BAAANQADCgMIBQAAAA==.Root:BAAANQADCgQIBAABNQAECgQICQABAAAAAA==.',
Ru='Rubmytotem:BAAANQADCgcIDAAAAA==.',
Sa='Sabazia:BAAANQAECgEIAQAAAA==.Sable:BAAANQADCgEIAQAAAA==.Saerise:BAAANQADCgMIAwAAAA==.Sairalindë:BAAANQADCgUICQAAAA==.Saleath:BAAANQADCgcIBwAAAA==.Salios:BAAANQAECgEIAQAAAA==.Sanctifier:BAAANQADCgUIBQAAAA==.',
Sc='Scrept:BAAANQAECgMIBQAAAA==.Scynix:BAEANQAECgEIAQAAAA==.',
Sh='Shabzyt:BAAANQADCgUICgAAAA==.Shaienne:BAAANQADCgcIDgAAAA==.Shamrockshak:BAAANQAECgEIAQAAAA==.Shockthêràpy:BAAANQAECgYIBwAAAA==.Shoes:BAAANQAECgQIBAAAAA==.Shtdruid:BAAANQADCgcIDAAAAA==.',
Si='Sibearian:BAAANQADCgcIDQAAAA==.Simi:BAAANQAECgIIAgAAAA==.',
Sm='Smokesçreen:BAAANQAECgIIAgAAAA==.',
So='Soonerpride:BAAANQADCgUIBQAAAA==.Soothed:BAAANQADCggICAAAAA==.',
Sp='Spearminttea:BAAANQADCgIIAgAAAA==.Spellbreakr:BAAANQAECgUIBQAAAA==.Spirtbreaker:BAAANQADCgYICgAAAA==.',
Sq='Squiby:BAAANQAECgQIBQAAAA==.',
St='Stankowitz:BAAANQABCgQIBgABNQADCgYIBgABAAAAAA==.Stheris:BAAANQADCgUICgAAAA==.Stix:BAAANQADCggICAABNQAECgIIAgABAAAAAA==.Stuefester:BAAANQAECgQIBQAAAA==.',
Sv='Sveika:BAAANQADCgYIDQAAAA==.',
Sy='Sylaria:BAEANQADCgMIBQAAAA==.Syreline:BAAANQADCgUIBgAAAA==.',
['Sï']='Sïn:BAAANQADCgYICwAAAA==.',
['Sý']='Sýlver:BAAANQADCggICgAAAA==.',
Ta='Tarpalantir:BAAANQADCgIIAgAAAA==.Taurne:BAAANQAECgcIBwAAAA==.',
Tc='Tchnce:BAAANQADCgcICgAAAA==.',
Te='Teknoman:BAAANQAECgEIAQAAAA==.Telephone:BAAANQADCgQIBAAAAA==.Tempered:BAAANQAECgIIAgAAAA==.',
Th='Thaitea:BAAANQADCgIIBAAAAA==.Thalindra:BAAANQADCgYICgAAAA==.Tharain:BAAANQADCgIIAgAAAA==.Thecurt:BAAANQAECgEIAQAAAA==.',
Ti='Tiael:BAAANQADCgcIDQAAAA==.Titanlock:BAAANQADCgMIBQAAAA==.',
To='Torvia:BAAANQADCgMIBQAAAA==.',
Tr='Trisinz:BAAANQADCggICQAAAA==.',
Tu='Turk:BAAANQAECgQIBQAAAA==.Turkish:BAAANQADCgcICwAAAA==.',
Tw='Twinkytoes:BAAANQADCgEIAQAAAA==.',
Ty='Tychaa:BAAANQADCgIIAgAAAA==.Tyranax:BAAANQADCgUICAAAAA==.',
Va='Variant:BAAANQADCgcIBwAAAA==.',
Ve='Verradic:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.',
Vi='Vitur:BAAANQAECgUIBgAAAA==.',
Vo='Voidbunny:BAAANQAECgEIAQAAAA==.Volaine:BAAANQADCgYICgAAAA==.Volt:BAAANQAECgEIAQAAAA==.',
Vy='Vynaeda:BAAANQAECgMIBQAAAA==.',
['Vô']='Vôx:BAAANQADCgUICgAAAA==.',
Wa='Wakko:BAAANQADCgcIDAAAAA==.Walkure:BAAANQADCgIIAgAAAA==.',
Wr='Wreckbums:BAAANQAECgMIBAAAAA==.',
Xa='Xanthad:BAAANQADCgUIBQAAAA==.',
Xb='Xb:BAAANQADCgIIAgAAAA==.',
Ya='Yaalia:BAAANQADCgYICgAAAA==.Yaan:BAAANQADCgYIBgAAAA==.',
Za='Zain:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.Zandibar:BAAANQADCgYICgAAAA==.Zavac:BAAANQADCgIIAgAAAA==.',
Ze='Zelritch:BAAANQADCggICAAAAA==.',
Zi='Zinfandell:BAAANQADCgYIDAAAAA==.',
Zu='Zuggie:BAAANQADCgIIAgABNQADCgQIBAABAAAAAA==.Zugtail:BAAANQADCgQIBAAAAA==.',
Zy='Zyntalla:BAAANQADCgYICgAAAA==.',
Zz='Zzonked:BAAANQAECgEIAQAAAA==.',
['Zê']='Zêp:BAAANQADCgcIDQAAAA==.',
['Ðo']='Ðoogle:BAAANQADCgYIDQABNQABCgIIAgABAAAAAA==.',
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
