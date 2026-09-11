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

local lookup = {'Unknown-Unknown','Warlock-Demonology','DemonHunter-Devourer',}
local provider = {region='US',realm='Perenolde',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aanien:BAAANQADCgYICAAAAA==.',
Ac='Acedk:BAAANQAECggIDgAAAA==.',
Ad='Adrador:BAAANQADCggIFAAAAA==.Adrenaline:BAAANQAECgcIDwAAAA==.',
Ae='Aelik:BAAANQAECgUICwAAAA==.Aeolian:BAAANQADCgYIDgAAAA==.',
Ak='Akueria:BAAANQADCgcIBwAAAA==.',
Al='Alayssa:BAAANQADCggIFgAAAA==.Alda:BAAANQADCgQIBgAAAA==.Alemental:BAAANQAECgQIBQAAAA==.Allarius:BAAANQAECgQIBAAAAA==.Alo:BAAANQAECgQIBAABNQAECgEIAQABAAAAAA==.',
Am='Amilee:BAAANQADCgUIBwAAAA==.Amoondai:BAAANQADCgYICAAAAA==.Amoondrin:BAAANQAECgUIBwAAAA==.',
An='Analiya:BAAANQADCgEIAQAAAA==.Anatyr:BAAANQADCgUIBQAAAA==.',
Ar='Aramathis:BAAANQADCgYIDwAAAA==.Araviin:BAAANQAECgEIAQAAAA==.Arbor:BAAANQADCgYICAAAAA==.Arcillias:BAAANQADCgUIBQABNQAECgQIBgABAAAAAA==.Arthia:BAAANQADCgYICQAAAA==.Arvidpally:BAAANQADCgcICAAAAA==.',
As='Ashesius:BAAANQAECgYICwAAAA==.',
At='Atredes:BAAANQAECgQIBgAAAA==.',
Au='Auspex:BAAANQAECgMIAwAAAA==.',
Av='Avaryn:BAAANQAECgQIBQAAAA==.',
Ba='Badaracka:BAAANQAECggICwAAAA==.Bahamuth:BAAANQAECgMIBAAAAA==.Bahamutsrage:BAAANQADCgYIBgABNQADCgcIDAABAAAAAA==.Balder:BAAANQADCgYIBgABNQAECgcIEgABAAAAAQ==.Barbattos:BAAANQAECgYIDQAAAA==.',
Bd='Bdyrk:BAAANQADCgcIBwABNQAECggICwABAAAAAA==.',
Be='Bexley:BAAANQAECgIIAwAAAA==.',
Bi='Biglarry:BAAANQADCgMIBQAAAA==.Biianca:BAAANQADCgIIBAAAAA==.',
Bl='Blacklok:BAAANQADCggICAABNQAECgYICQABAAAAAA==.Blanne:BAAANQABCgIIAgAAAA==.Blargle:BAAANQADCgYICgAAAA==.Blegh:BAAANQAECgcIDgAAAA==.Blinx:BAAANQAECgEIAgAAAA==.Bloodrake:BAAANQAECgYICwAAAA==.Blueray:BAAANQADCgYIBgAAAA==.',
Bm='Bman:BAAANQADCggIDQAAAA==.',
Br='Braneour:BAAANQAECgQIBQAAAA==.',
Bu='Bumm:BAAANQADCgIIBAAAAA==.',
Bz='Bzspy:BAAANQAECgUICgAAAA==.',
['Bë']='Bëar:BAAANQAECgEIAQAAAA==.',
Ca='Calyptus:BAAANQAECgYICgAAAA==.Capylaura:BAAANQAECgIIAwAAAA==.Caratine:BAAANQADCgcIDQAAAA==.Cassandrah:BAAANQAECgYICQAAAA==.',
Ce='Celìa:BAAANQADCggICgAAAA==.',
Ch='Christy:BAAANQADCgQIBgAAAA==.Chugg:BAAANQAECgEIAQAAAA==.',
Ci='Ciaphus:BAAANQAECgQIBQAAAA==.Cinnamonster:BAAANQABCgUIBQAAAA==.',
Cl='Clogs:BAAANQAECgEIAQAAAA==.',
Co='Convalescent:BAAANQADCgYIBgAAAA==.Coragrr:BAAANQAECgIIAwAAAA==.',
Cr='Cracklepants:BAAANQAECgYIEAAAAA==.Crashout:BAAANQADCgYICgAAAA==.',
Cu='Curtastrophe:BAAANQAECgIIAwAAAA==.',
Da='Daelanos:BAAANQAECgEIAQAAAA==.Dallas:BAAANQADCgYICwAAAA==.',
De='Deathoof:BAAANQADCggIEgABNQAECgIIAgABAAAAAA==.Demonilla:BAAANQAECgQIBQAAAA==.Destro:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.',
Di='Dilaudyd:BAAANQADCgUIBwAAAA==.Dispel:BAAANQADCgYIBgAAAA==.Disputatious:BAAANQADCgQIBAAAAA==.',
Do='Dogaz:BAAANQADCgQIBQAAAA==.Dogsoldier:BAAANQADCgQIBAAAAA==.Donori:BAAANQADCgEIAQAAAA==.',
Dr='Dragonias:BAAANQADCgcIDgAAAA==.Drakthorn:BAAANQADCgQIBAAAAA==.Drinny:BAAANQAECgIIAgAAAA==.Dripington:BAAANQAECgYICQAAAA==.',
Ea='Earthangel:BAAANQADCggIEgAAAA==.',
Ef='Efon:BAAANQADCgUIBQABNQADCggIFgABAAAAAA==.',
Ei='Eine:BAAANQAECgYICwAAAA==.',
El='Eldergreen:BAAANQAECgMIAwAAAA==.Elfwine:BAAANQADCggIEgAAAA==.Elindria:BAAANQAECgYICQAAAA==.Elminstir:BAAANQAECgQIBAAAAA==.Eluzhion:BAAANQADCgUICAAAAA==.Elysian:BAAANQAECgIIBAAAAA==.',
Er='Erizhal:BAAANQABCgIIAgAAAA==.Eruptyon:BAAANQADCggIDgABNQADCggIFAABAAAAAA==.',
Es='Esabel:BAAANQAECgMIAwABNQADCggIFgABAAAAAA==.',
Ev='Eviae:BAAANQADCggIEgAAAA==.Evillure:BAAANQADCggIFQAAAA==.',
Ex='Explanation:BAAANQADCgQIBAAAAA==.',
Fa='Falan:BAAANQAECgEIAQAAAA==.Farfins:BAAANQADCgYIBgAAAA==.',
Fe='Feår:BAAANQADCgcIEAAAAA==.',
Fi='Finley:BAAANQADCgQIBAAAAA==.',
Fl='Flane:BAAANQAECggIEgAAAA==.Flexdruid:BAAANQADCgQIBgAAAA==.',
Fr='Fragil:BAAANQAECgQIBQAAAA==.',
Ga='Galena:BAAANQADCgcIFAAAAA==.Ganonn:BAAANQADCggIDQAAAA==.',
Ge='Geshtal:BAAANQADCgYICwAAAA==.',
Gi='Girion:BAAANQADCggIEgAAAA==.',
Gl='Glaiven:BAEANQAECgcIDwAAAA==.Glyr:BAAANQAECgEIAQAAAA==.',
Go='Gorgrin:BAAANQADCgcIDgAAAA==.',
Ha='Harkanum:BAAANQAECgYICwAAAA==.Harrow:BAAANQADCgcIEQAAAA==.Harvester:BAAANQAECgEIAQAAAA==.',
He='Healinturds:BAAANQADCgEIAQAAAA==.Helloagain:BAAANQAECgQIBwAAAA==.',
Hi='Hidethetotem:BAAANQADCgUICQAAAA==.Hikari:BAAANQAECgYICgAAAA==.',
Ho='Holyspike:BAAANQADCgcIDgAAAA==.Homerr:BAAANQADCgcIDgAAAA==.Honiahaka:BAAANQAECgQIBQAAAA==.Hottcakes:BAAANQAECgQIBQABNQAECgkJGQACAFciAA==.',
Hu='Humanoidlite:BAAANQAECgEIAQABNQAECgcIDgABAAAAAA==.Humanoidlock:BAAANQADCgYIDAABNQAECgcIDgABAAAAAA==.Humanoidwar:BAAANQAECgcIDgAAAA==.',
In='Inoru:BAAANQADCgYICgAAAA==.',
Ir='Irmaline:BAAANQADCgcIDgAAAA==.',
It='Ithurtshuh:BAAANQADCgEIAQABNQADCgYIDwABAAAAAA==.',
Ja='Jabbawockie:BAAANQADCggICAAAAA==.',
Je='Jennifleur:BAAANQADCgcIBwAAAA==.Jerk:BAABNQAECoEYAAIDAAkJJyKpAwBnAwADAAkJJyKpAwBnAwAAAA==.Jesper:BAAANQAECgYICwAAAA==.Jetz:BAAANQADCggIFQAAAA==.',
Ji='Jilara:BAAANQADCggIEQAAAA==.Jimmyjim:BAAANQADCgYICwAAAA==.',
Jo='Jockko:BAAANQADCggICAAAAA==.Joink:BAAANQADCgYICQAAAA==.',
Jp='Jpepps:BAAANQAECgUICQAAAA==.',
Jr='Jrose:BAAANQADCgYIEQAAAA==.',
Ka='Kagozo:BAEANQAECgEIAQAAAA==.Kaiatra:BAAANQADCgcIFAAAAA==.Kaloran:BAAANQADCgYIBgAAAA==.Katalaystar:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Katalegdh:BAAANQADCgUIBQAAAA==.Kaìju:BAAANQAECgIIAgAAAA==.',
Ki='Kilmandaros:BAAANQADCgIIBAAAAA==.',
Ku='Kudria:BAAANQAECgMIAwAAAA==.Kunei:BAAANQABCgQIBgAAAA==.Kurdran:BAAANQABCgIIAgAAAA==.Kuroyukihime:BAAANQAECgQIBQAAAA==.',
['Ká']='Kárma:BAAANQADCgYICwABNQADCgcIEAABAAAAAA==.',
La='Lashela:BAAANQADCggIEQAAAA==.Laughter:BAAANQADCgcIDgAAAA==.Laylla:BAAANQADCgUIBQAAAA==.Lazulie:BAAANQADCgYIDAAAAA==.',
Le='Lefnedrav:BAAANQADCgYIBgABNQADCggICAABAAAAAA==.Lexapayne:BAAANQADCgEIAQABNQAECgMIBQABAAAAAA==.',
Li='Lighthammer:BAAANQADCgcICQAAAA==.Lightmessiah:BAAANQAECgIIAgAAAA==.Lightnig:BAAANQADCgUIBQAAAA==.Lilyvain:BAAANQADCgcICgAAAA==.Lireal:BAAANQAECgQIBAAAAA==.Livnod:BAAANQADCgUIBQAAAA==.',
Lo='Lonon:BAAANQAECgQIBgAAAA==.Loosescrew:BAAANQADCgEIAQAAAA==.Lorine:BAAANQAECgYICwAAAA==.',
Lu='Lunara:BAAANQADCgYIDAAAAA==.',
Ly='Lynnethe:BAAANQADCggIEwAAAA==.',
Ma='Malkiel:BAAANQAECgQICwAAAA==.Mastakillah:BAAANQADCgQICAABNQADCgYIDAABAAAAAA==.',
Me='Meeseeks:BAAANQAECgcIBwAAAA==.Merckel:BAAANQAECgUIBQAAAA==.',
Mi='Michello:BAAANQADCgcIDgAAAA==.Mightytot:BAAANQADCgIIAgAAAA==.Millia:BAAANQADCggIFAAAAA==.Mint:BAAANQAECggIEgAAAA==.Mintberrytea:BAAANQAECgQIBAABNQAECggIEgABAAAAAA==.Misstress:BAAANQAECgIIAgAAAA==.',
Mo='Moistweaver:BAAANQADCgYIBgAAAA==.Monoxide:BAAANQADCgUIBQABNQAECgIIAwABAAAAAA==.Moonhunt:BAAANQADCggIEQAAAA==.Morkleb:BAAANQADCgQIBAAAAA==.Morrag:BAAANQADCggIFQAAAA==.Morrtisha:BAAANQAECgQIBAAAAA==.',
My='Myxie:BAAANQAECgEIAQAAAA==.',
['Mí']='Mísfìt:BAAANQAECgYICgAAAA==.',
Na='Nakaito:BAAANQADCggICwABNQAECgMIAwABAAAAAA==.Narcoleptic:BAAANQAECgUICgAAAA==.Naturaljuice:BAAANQAECgcIBwABNQAECgkJGQACAFciAA==.Naturebreakr:BAAANQAECgQIBAAAAA==.',
Ne='Nex:BAAANQAECgMIAwAAAA==.',
Ni='Nightsawdy:BAAANQADCggIFAAAAA==.Niightstorm:BAAANQADCggIDgAAAA==.Nitefire:BAAANQADCgQIBgAAAA==.Nitélifé:BAAANQADCgcIDAAAAA==.',
Om='Omora:BAAANQADCggICAAAAA==.',
Op='Opalinnas:BAAANQAECgIIAgAAAA==.Optimism:BAAANQABCgYIBgAAAA==.',
Pa='Panzer:BAAANQAECgEIAQAAAA==.Parts:BAAANQADCggICAABNQAECgQIBgABAAAAAA==.Passionfruit:BAAANQADCgQIBAAAAA==.',
Pe='Peachtea:BAAANQAECgEIAQAAAA==.Pepecojon:BAAANQADCggIDwAAAA==.',
Pi='Pirodeath:BAAANQADCggIFgAAAA==.',
Po='Poah:BAAANQAECgYIBgAAAA==.',
Pr='Pray:BAAANQAECgQIBQAAAA==.Prodarkangel:BAAANQADCgcICQAAAA==.',
Pu='Puckllane:BAAANQAECgEIAgAAAA==.',
Py='Pyre:BAAANQAECgYICwABNQAECgEIAQABAAAAAA==.',
['Pü']='Püff:BAAANQADCgEIAQABNQAECgQIBgABAAAAAA==.',
Qu='Quanah:BAAANQADCggIDQAAAA==.Quivver:BAAANQADCgIIAgAAAA==.',
Ra='Rabmaxx:BAAANQADCgYIGAAAAA==.Raina:BAAANQADCgYIBgAAAA==.Ravenlight:BAAANQAECgYIBwAAAA==.Ravenwynnd:BAAANQAECgYIBgAAAA==.Raynman:BAAANQAECgQIBQAAAA==.',
Rh='Rhydian:BAAANQADCgQIBAAAAA==.Rhyzer:BAAANQADCgYIEAAAAA==.',
Ri='Riiver:BAAANQADCgYIBgAAAA==.',
Ro='Roderick:BAAANQADCgUIBwAAAA==.Root:BAAANQADCgQIBAABNQAECgcIEgABAAAAAA==.',
Ru='Rubmytotem:BAAANQAECgEIAQAAAA==.',
Sa='Sabazia:BAAANQAECgQIBQAAAA==.Sable:BAAANQADCgEIAQAAAA==.Saerise:BAAANQADCgUIBQAAAA==.Sairalindë:BAAANQADCgcIEAAAAA==.Saleath:BAAANQAECgIIAgAAAA==.Salios:BAAANQAECgEIAQAAAA==.Sanara:BAAANQABCgUIBwAAAA==.Sanctifier:BAAANQADCgUIBQAAAA==.',
Sc='Scrept:BAAANQAECgMIBQAAAA==.Scynix:BAEANQAECgQIBQAAAA==.',
Se='Senus:BAAANQADCgEIAQAAAA==.Servoker:BAAANQADCggICAAAAA==.',
Sh='Shabzyt:BAAANQADCgcIEQAAAA==.Shaienne:BAAANQADCgcIDgAAAA==.Shamrockshak:BAAANQAECgEIAgAAAA==.Shieldbash:BAAANQAECgUICgAAAA==.Shockthêràpy:BAAANQAECgYICwAAAA==.Shoes:BAAANQAECgYICgAAAA==.Shtdruid:BAAANQAECgEIAQAAAA==.',
Si='Sibearian:BAAANQAECgIIAgAAAA==.Simi:BAAANQAECgMIBQAAAA==.',
Sm='Smokesçreen:BAAANQAECgQIBgAAAA==.',
So='Soonerpride:BAAANQADCgUIBQAAAA==.Soothed:BAAANQADCggICAAAAA==.',
Sp='Spearminttea:BAAANQADCgIIAgAAAA==.Spellbreakr:BAAANQAECgcIDAAAAA==.Spirtbreaker:BAAANQADCgYICgAAAA==.',
Sq='Squiby:BAAANQAECgYICwAAAA==.',
St='Stankowitz:BAAANQABCgQICAABNQADCgYIBgABAAAAAA==.Starce:BAAANQABCgMIAwAAAA==.Steveirwin:BAAANQADCgUIBQAAAA==.Stheris:BAAANQADCggIEgAAAA==.Stuefester:BAAANQAECgYICwAAAA==.',
Sv='Sveika:BAAANQADCgcIEAAAAA==.',
Sy='Sylaria:BAEANQADCgUIBwAAAA==.Syreline:BAAANQAECgEIAQAAAA==.',
['Sï']='Sïn:BAAANQAECgIIAgAAAA==.',
['Sý']='Sýlver:BAAANQAECgMIAwAAAA==.',
Ta='Tarpalantir:BAAANQADCgIIAgAAAA==.Taurne:BAAANQAECgcIDgAAAA==.',
Tc='Tchnce:BAAANQADCgcICgAAAA==.',
Te='Teknoman:BAAANQAECgQIBQAAAA==.Telephone:BAAANQAECgEIAQAAAA==.Tempered:BAAANQAECgQIBgAAAA==.',
Th='Thaitea:BAAANQADCgIIBAAAAA==.Thalindra:BAAANQADCgcIEQAAAA==.Tharain:BAAANQADCgQIBgAAAA==.Thebigbeast:BAAANQAECgEIAQABNQAECgkJGQACAFciAA==.Thecurt:BAAANQAECgQIBQAAAA==.',
Ti='Tiael:BAAANQADCggIFQAAAA==.Tirouke:BAAANQADCgIIAgAAAA==.Titanlock:BAAANQADCgMIBQAAAA==.',
Tk='Tkdfath:BAAANQADCgYIBgAAAA==.',
To='Toralina:BAAANQADCgYIBgAAAA==.Torvia:BAAANQADCgUIBwAAAA==.',
Tr='Trisinz:BAAANQADCggIEQAAAA==.',
Tu='Tuerto:BAAANQAECgQIBAAAAA==.Turk:BAAANQAECgUICgAAAA==.Turkish:BAAANQAECgIIAgAAAA==.',
Tw='Twinkytoes:BAAANQADCggICQAAAA==.',
Ty='Tychaa:BAAANQADCgIIAgAAAA==.Tyranax:BAAANQADCggIFgAAAA==.Tyrith:BAAANQADCgEIAQAAAA==.',
Ul='Ullyr:BAAANQADCggICAABNQAECgYIEAABAAAAAA==.',
Va='Valytrois:BAAANQAECgEIAQAAAA==.Variant:BAAANQAECgIIAgAAAA==.Vauld:BAAANQADCgEIAQAAAA==.',
Ve='Veiksla:BAAANQADCgQIBAAAAA==.Vengerr:BAAANQADCgQIBAAAAA==.Verace:BAAANQADCggICAAAAA==.Verradic:BAAANQADCgcIDAAAAA==.',
Vi='Vitur:BAAANQAECgYIDAAAAA==.',
Vo='Voidbunny:BAAANQAECgMIBAAAAA==.Volaine:BAAANQADCggIEgAAAA==.Volition:BAAANQADCgYIBgAAAA==.Volt:BAAANQAECgEIAQAAAA==.',
Vy='Vynaeda:BAAANQAECgQICAAAAA==.',
['Vô']='Vôx:BAAANQAECgIIAgAAAA==.',
Wa='Wakko:BAAANQADCgcIEwAAAA==.Walkure:BAAANQADCgQIBgAAAA==.',
We='Weirdscience:BAAANQABCgQIBAAAAA==.',
Wr='Wreckbums:BAAANQAECgMIBAAAAA==.Wreckd:BAAANQADCgYIBgABNQAECgQIBgABAAAAAA==.',
Xa='Xanthad:BAAANQADCgUICAAAAA==.',
Xb='Xb:BAAANQADCgQIBgAAAA==.',
Ya='Yaalia:BAAANQADCggIEgAAAA==.Yaan:BAAANQADCgcIDQAAAA==.',
Za='Zain:BAAANQADCgYIBgABNQAECgYICwABAAAAAA==.Zandibar:BAAANQADCggIEgAAAA==.Zavac:BAAANQADCgUIBwAAAA==.',
Ze='Zelritch:BAAANQADCggICAAAAA==.',
Zi='Zinfandell:BAAANQADCggIFAAAAA==.',
Zo='Zorrloc:BAAANQADCgQIBAAAAA==.',
Zu='Zuggie:BAAANQADCgQIBgABNQADCgcIBwABAAAAAA==.Zugtail:BAAANQADCgcIBwAAAA==.Zurtrinik:BAAANQADCggICAABNQAECggIEgABAAAAAA==.',
Zy='Zyntalla:BAAANQADCggIEgAAAA==.',
Zz='Zzonked:BAAANQAECgEIAQAAAA==.',
['Zê']='Zêp:BAAANQADCgcIEwAAAA==.',
['Àr']='Àrròw:BAAANQADCgUIBQAAAA==.',
['Ðo']='Ðoogle:BAAANQADCgcIFAABNQABCgMIAwABAAAAAA==.',
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
