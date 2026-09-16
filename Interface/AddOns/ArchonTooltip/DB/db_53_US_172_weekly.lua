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

local lookup = {'Unknown-Unknown','Warrior-Protection','Evoker-Preservation','Shaman-Elemental','Monk-Brewmaster','Monk-Windwalker','DemonHunter-Havoc','DemonHunter-Devourer','Warlock-Demonology','Warrior-Arms','Paladin-Holy','DeathKnight-Unholy','Druid-Restoration',}
local provider = {region='US',realm='Perenolde',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aanien:BAAANQADCgYICAAAAA==.',
Ac='Acedk:BAAANQAECggIEAAAAA==.Aceslam:BAAANQAECgEIAQABNQAECggIEAABAAAAAA==.',
Ad='Adrador:BAAANQAECgMIAwAAAA==.Adrenaline:BAABNQAECoEaAAICAAgJ5SDaAgD4AgACAAgJ5SDaAgD4AgAAAA==.',
Ae='Aelik:BAAANQAECgUIEAAAAA==.Aeolian:BAAANQADCgYIDgAAAA==.',
Ak='Akueria:BAAANQADCgcIBwAAAA==.',
Al='Alayssa:BAAANQAECgIIAgAAAA==.Alda:BAAANQADCgUICwAAAA==.Alemental:BAAANQAECgQIBQAAAA==.Aleska:BAAANQAECgQIBAAAAA==.Allarius:BAAANQAECgQIBAAAAA==.Alo:BAAANQAECgYICgABNQAECgEIAQABAAAAAA==.',
Am='Amilee:BAAANQADCgYICAAAAA==.Amoondai:BAAANQADCgYICAAAAA==.Amoondrin:BAAANQAECgYICAAAAA==.',
An='Analiya:BAAANQADCgMIBAAAAA==.Anatyr:BAAANQADCgYIBgAAAA==.',
Ar='Aramathis:BAAANQAECgQIBAAAAA==.Araviin:BAAANQAECgUIBgAAAA==.Arbor:BAAANQAECgMIAwAAAA==.Arcillias:BAAANQADCgUIBQABNQAECgQIBgABAAAAAA==.Arkanist:BAAANQAECgEIAQAAAA==.Arthia:BAAANQADCgYICQAAAA==.Arvidpally:BAAANQADCggICwAAAA==.',
As='Ashesius:BAAANQAECgYIEQAAAA==.Ashmehameha:BAAANQADCgYIBgABNQADCgcICwABAAAAAA==.',
At='Atredes:BAAANQAECgQICQAAAA==.',
Au='Auspex:BAAANQAECgUICAAAAA==.',
Av='Avaryn:BAAANQAECgcIDAAAAA==.',
Ba='Badaracka:BAAANQAECggIEwAAAA==.Bahamuth:BAAANQAECgYICgAAAA==.Bahamutsrage:BAAANQADCgYIBgABNQADCgcIEwABAAAAAA==.Balder:BAAANQAECgEIAQABNQAFFAEIAQABAAAAAQ==.Barbattos:BAABNQAECoEYAAIDAAgJfiAbBwDgAgADAAgJfiAbBwDgAgAAAA==.',
Bd='Bdyrk:BAAANQADCgcIBwABNQAECggIEwABAAAAAA==.',
Be='Bealzeboss:BAAANQADCgcIBwAAAA==.Bexley:BAAANQAECgYICQAAAA==.',
Bi='Biglarry:BAAANQADCgMIBQAAAA==.Biianca:BAAANQADCgUICQAAAA==.',
Bl='Blacklok:BAAANQADCggIDgABNQAECgcIEAABAAAAAA==.Blanne:BAAANQABCgIIAgAAAA==.Blargle:BAAANQADCgYICgAAAA==.Blegh:BAAANQAECgcIEwAAAA==.Blinx:BAAANQAECgEIAgAAAA==.Bloodrake:BAAANQAECgYIEQAAAA==.Blueray:BAAANQADCgYIBgAAAA==.',
Bm='Bman:BAAANQAECgIIAgAAAA==.',
Br='Braneour:BAAANQAECgUICgAAAA==.Browel:BAAANQAECgQIBAAAAA==.',
Bu='Bumm:BAAANQADCgIIBAAAAA==.',
Bz='Bzspy:BAAANQAECgUIDwAAAA==.',
['Bë']='Bëar:BAAANQAECgEIAQAAAA==.',
Ca='Calyptus:BAAANQAECgYIDgAAAA==.Capylaura:BAAANQAECgMIBgAAAA==.Caratine:BAAANQADCgcIDQAAAA==.Cassandrah:BAAANQAECgYIDwAAAA==.',
Ce='Celìa:BAAANQADCggICgAAAA==.',
Ch='Christy:BAAANQADCgUICgAAAA==.Chugg:BAAANQAECgIIAwAAAA==.',
Ci='Ciaphus:BAAANQAECgYICwAAAA==.Cinnamonster:BAAANQADCgYICQAAAA==.',
Cl='Clogs:BAAANQAECgUIBgAAAA==.',
Co='Coffeedemon:BAAANQADCgYIBgAAAA==.Coldslappins:BAAANQADCgUIBQABNQAECgUICgABAAAAAA==.Convalescent:BAAANQADCgYIBgAAAA==.Coragrr:BAAANQAECgIIAwAAAA==.',
Cr='Cracklepants:BAABNQAECoEbAAIEAAgJWRMeLQAWAgAEAAgJWRMeLQAWAgAAAA==.Crashout:BAAANQADCgYICgAAAA==.',
Cu='Curtastrophe:BAAANQAECgYICQAAAA==.',
Da='Daelanos:BAAANQAECgUIBQAAAA==.Dallas:BAAANQADCgYICwAAAA==.',
De='Deathoof:BAAANQAECgQIBAABNQAECgQIBgABAAAAAA==.Demonilla:BAAANQAECgQIBQAAAA==.Destro:BAAANQAECgYIBwAAAA==.',
Di='Dilaudyd:BAAANQADCgYICAAAAA==.Dishu:BAAANQABCgQIBAAAAA==.Dispel:BAAANQADCgYIBgAAAA==.Disputatious:BAAANQADCgQIBAAAAA==.',
Dn='Dntblink:BAAANQADCgUIBQAAAA==.',
Do='Dogaz:BAAANQADCgUICgAAAA==.Dogsoldier:BAAANQADCgQIBAAAAA==.Donori:BAAANQADCgEIAQAAAA==.',
Dr='Dragonias:BAAANQADCgcIDgAAAA==.Drakthorn:BAAANQADCgQIBAAAAA==.Drinny:BAAANQAECgYICAAAAA==.Dripington:BAAANQAECgYIDwAAAA==.',
Ea='Earthangel:BAAANQADCggIGgAAAA==.',
Ef='Efon:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.',
Ei='Eine:BAAANQAECgYIEQAAAA==.',
El='Eldergreen:BAAANQAECgQIBwAAAA==.Elfwine:BAAANQADCggIGAAAAA==.Elindria:BAAANQAECgcIEAAAAA==.Elminstir:BAAANQAECgQIBAAAAA==.Eluzhion:BAAANQADCgUICAAAAA==.Elysian:BAAANQAECgUICQAAAA==.',
Er='Erizhal:BAAANQABCgIIAgAAAA==.Eruptyon:BAAANQAECgEIAQABNQAECgQIBgABAAAAAA==.',
Es='Esabel:BAAANQAECgQIBwABNQAECgIIAgABAAAAAA==.',
Ev='Eviae:BAAANQADCggIGgAAAA==.Evillure:BAAANQADCggIHQAAAA==.',
Ex='Explanation:BAAANQADCgQIBAAAAA==.',
Fa='Falan:BAAANQAECgEIAQAAAA==.Farfins:BAAANQADCgYIBgAAAA==.',
Fe='Fedor:BAAANQADCggICAAAAA==.Feår:BAAANQAECgMIAwAAAA==.',
Fi='Finley:BAAANQADCgQIBAAAAA==.Fixation:BAAANQABCgIIAgAAAA==.',
Fl='Flane:BAABNQAECoEZAAMFAAkJHh1DAwDsAgAFAAkJHh1DAwDsAgAGAAEJJx3ONQBWAAAAAA==.Flexdruid:BAAANQADCgQIBgAAAA==.',
Fr='Fragil:BAAANQAECgYICQAAAA==.',
Ga='Galena:BAAANQADCggIHAAAAA==.Ganonn:BAAANQAECgIIAgAAAA==.',
Ge='Geshtal:BAAANQADCgYIDQAAAA==.',
Gi='Girion:BAAANQADCggIGgAAAA==.',
Gl='Glaiven:BAEBNQAECoEaAAMHAAgJ9iClCgDlAgAHAAgJ+h+lCgDlAgAIAAcJzxhxGgANAgAAAA==.Glyr:BAAANQAECgEIAQAAAA==.',
Go='Gorgrin:BAAANQADCggIEQAAAA==.',
Gr='Groguu:BAAANQAECgQIBAABNQAECggIEAABAAAAAA==.',
Ha='Harkanum:BAAANQAECgYIEQAAAA==.Harvester:BAAANQAECgEIAgAAAA==.',
He='Healinturds:BAAANQADCgEIAQAAAA==.Helloagain:BAAANQAECggIDwAAAA==.',
Hi='Hidethetotem:BAAANQADCggIEQAAAA==.Hikari:BAAANQAECgcIDAAAAA==.',
Ho='Holyrebel:BAAANQADCgQIBAABNQADCgYIDwABAAAAAA==.Holyspike:BAAANQADCggIEQAAAA==.Homerr:BAAANQADCgcIDgAAAA==.Honiahaka:BAAANQAECgYICwAAAA==.Hotsdog:BAAANQADCgIIAgAAAA==.Hottcakes:BAAANQAECgYICwABNQAFFAUICQAJALQNAA==.',
Hu='Humanoidlite:BAAANQAECgEIAQABNQAECggIFwAKALEWAA==.Humanoidlock:BAAANQADCgYIDAABNQAECggIFwAKALEWAA==.Humanoidwar:BAABNQAECoEXAAMKAAgJsRZkNABqAgAKAAgJsRZkNABqAgACAAIJ8QV9IABKAAAAAA==.',
In='Inoru:BAAANQADCggIEgAAAA==.',
Ir='Irmaline:BAAANQADCggIEQAAAA==.',
It='Ithurtshuh:BAAANQADCgEIAQABNQADCgYIDwABAAAAAA==.',
Ja='Jabbawockie:BAAANQAECggICAAAAA==.',
Je='Jeffee:BAAANQAECgQIBAAAAA==.Jennifleur:BAAANQADCgcIBwAAAA==.Jerk:BAABNQAECoEhAAIIAAkJ7SQ9AQDIAwAIAAkJ7SQ9AQDIAwAAAA==.Jesper:BAAANQAECgYIEQAAAA==.Jetz:BAAANQAECgIIAgAAAA==.',
Ji='Jilara:BAAANQADCggIGAAAAA==.Jimmyjim:BAAANQADCggIDgAAAA==.',
Jo='Jockko:BAAANQADCggICAAAAA==.Joink:BAAANQADCgYICQAAAA==.',
Jp='Jpepps:BAAANQAECgcIEAAAAA==.',
Jr='Jrose:BAAANQADCgYIEQAAAA==.',
Ka='Kagozo:BAEANQAECgEIAQABNQAECgIIAgABAAAAAA==.Kaiatra:BAAANQADCggIHAAAAA==.Kaloran:BAAANQAECgQIBAAAAA==.Katalaystar:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Katalegdh:BAAANQADCggIDQAAAA==.Kaìju:BAAANQAECgIIBAAAAA==.',
Kh='Khai:BAAANQAECggIBAAAAA==.',
Ki='Kiae:BAAANQADCgYIBgAAAA==.Kidneyspears:BAAANQADCgYIBgAAAA==.Kilaura:BAAANQADCgUIBQAAAA==.Kilmandaros:BAAANQADCgIIBAAAAA==.Kimblee:BAAANQADCgQIBAAAAA==.',
Ku='Kudria:BAAANQAECgMIAwAAAA==.Kunei:BAAANQABCgYICQAAAA==.Kurdran:BAAANQABCgQIAgAAAA==.Kuroyukihime:BAAANQAECgQICQAAAA==.',
Ky='Kynae:BAAANQAECgQIBAAAAA==.',
['Ká']='Kárma:BAAANQADCgYICwABNQAECgMIAwABAAAAAA==.',
La='Lashela:BAAANQAECgEIAQAAAA==.Laughter:BAAANQADCggIEQAAAA==.Laylla:BAAANQADCgYICwAAAA==.Lazulie:BAAANQADCgYIDgAAAA==.',
Le='Lefnedrav:BAAANQADCgYIBgABNQAECgYIBgABAAAAAA==.Lexapayne:BAAANQADCgEIAQABNQAECgMIBQABAAAAAA==.Leyra:BAAANQADCgYIBgABNQAECgcIEAABAAAAAA==.',
Li='Lighthammer:BAAANQADCgcICQAAAA==.Lightmessiah:BAAANQAECgUIBwAAAA==.Lightnig:BAAANQADCgUIBQAAAA==.Lilyvain:BAAANQADCgcIDAAAAA==.Lireal:BAAANQAECgUICQAAAA==.Livnod:BAAANQADCgYIBgAAAA==.',
Lo='Lonon:BAAANQAECgYIDAAAAA==.Loosescrew:BAAANQADCgMIBAAAAA==.Lorine:BAAANQAECgYICwAAAA==.',
Lu='Lunara:BAAANQADCgYIDAAAAA==.',
Ly='Lynnethe:BAAANQADCggIEwAAAA==.',
Ma='Malkiel:BAAANQAECgQICwAAAA==.Mantang:BAAANQABCgIIAgAAAA==.Mastakillah:BAAANQADCgQICAABNQADCgYIDAABAAAAAA==.',
Me='Meeseeks:BAAANQAECgcIDQAAAA==.Merckel:BAAANQAECgYICwAAAA==.',
Mi='Michello:BAAANQADCggIEQAAAA==.Mightytot:BAAANQADCgIIAgAAAA==.Millia:BAAANQAECgQIBgAAAA==.Mint:BAABNQAECoEeAAILAAkJGBUSGQCWAgALAAkJGBUSGQCWAgAAAA==.Mintberrytea:BAAANQAECgQIBAABNQAECgkJHgALABgVAA==.Misstress:BAAANQAECgMIBQAAAA==.',
Mo='Moistweaver:BAAANQADCgYIBgAAAA==.Monoxide:BAAANQADCgUIBQABNQAECgYICQABAAAAAA==.Moonhunt:BAAANQADCggIGgAAAA==.Morkleb:BAAANQADCggIDAAAAA==.Morrag:BAAANQAECgIIAgAAAA==.Morrtisha:BAAANQAECgQIBQAAAA==.',
My='Myxie:BAAANQAECgEIAgAAAA==.',
['Mí']='Mísfìt:BAAANQAECgYIDwAAAA==.',
Na='Nakaito:BAAANQADCggICwABNQAECgQIBwABAAAAAA==.Narcoleptic:BAAANQAECgUIDwAAAA==.Nashty:BAAANQADCgIIAgAAAA==.Naturaljuice:BAAANQAECgcIBwABNQAFFAUICQAJALQNAA==.Naturebreakr:BAAANQAECgQIBAAAAA==.',
Ne='Nex:BAAANQAECgQIBAAAAA==.',
Ni='Nightsawdy:BAAANQAECgEIAQAAAA==.Niightstorm:BAAANQADCggIFgAAAA==.Nitefire:BAAANQADCgUICwAAAA==.Nitélifé:BAAANQADCgcIDAAAAA==.',
Of='Offspring:BAAANQABCgIIAgAAAA==.',
Om='Omora:BAAANQAECgQIBAABNQAECgYIBgABAAAAAA==.',
Op='Opalinnas:BAAANQAECgIIAgAAAA==.Optimism:BAAANQABCggICAAAAA==.',
Pa='Panzer:BAAANQAECgIIAwAAAA==.Parts:BAAANQAECgEIAQABNQAECgUICwABAAAAAA==.Passionfruit:BAAANQADCgQIBAAAAA==.',
Pe='Peachtea:BAAANQAECgEIAgAAAA==.Pepecojon:BAAANQADCggIDwAAAA==.',
Pi='Pirodeath:BAAANQADCggIFgAAAA==.',
Pl='Plovdiv:BAAANQADCgcIBwAAAA==.',
Po='Poah:BAAANQAECgYIBgAAAA==.',
Pr='Pray:BAAANQAECgYICwAAAA==.Prodarkangel:BAAANQADCgcICQAAAA==.',
Pu='Puckllane:BAAANQAECgEIAgAAAA==.Punkin:BAAANQADCgEIAQAAAA==.',
Py='Pyre:BAAANQAECgYIEQABNQAECgEIAQABAAAAAA==.',
['Pü']='Püff:BAAANQADCgEIAQABNQAECgQIBgABAAAAAA==.',
Qu='Quanah:BAAANQAECgIIAgAAAA==.Quivver:BAAANQADCgUIBwAAAA==.',
Ra='Raina:BAAANQADCgYIBgAAAA==.Ravenlight:BAAANQAECgcIDgAAAA==.Ravenwynnd:BAAANQAECgYIDAAAAA==.Raynman:BAAANQAECgYICgAAAA==.',
Rh='Rhydian:BAAANQADCgQIBAAAAA==.Rhyzer:BAAANQADCggIGAAAAA==.',
Ri='Riiver:BAAANQADCgYIBgAAAA==.',
Ro='Roderick:BAAANQADCgYICAAAAA==.Root:BAAANQADCgQICAABNQAECggIGgAMAAYdAA==.',
Ru='Rubmytotem:BAAANQAECgEIAQAAAA==.',
Sa='Sabazia:BAAANQAECgUICgAAAA==.Sable:BAAANQADCgEIAQAAAA==.Saerise:BAAANQADCgYIBgAAAA==.Sairalindë:BAAANQADCggIGAAAAA==.Salamandra:BAAANQADCgQIBAABNQAECgYIBgABAAAAAA==.Saleath:BAAANQAECgIIAgAAAA==.Salios:BAAANQAECgEIAQAAAA==.Sanara:BAAANQABCgUIBwABNQADCggIGgABAAAAAA==.Sanctifier:BAAANQADCgUIBQAAAA==.',
Sc='Scrept:BAAANQAECgYICAAAAA==.Scynix:BAEANQAECgQIBQAAAA==.',
Se='Senus:BAAANQADCgEIAQAAAA==.Servoker:BAAANQADCggICAAAAA==.',
Sh='Shabzyt:BAAANQAECgIIAgAAAA==.Shaienne:BAAANQADCgcIDgAAAA==.Shammander:BAAANQADCgUICAAAAA==.Shamrockshak:BAAANQAECgEIAwAAAA==.Shenuton:BAAANQADCgMIAwAAAA==.Shieldbash:BAAANQAECgYIEAAAAA==.Shockthêràpy:BAAANQAECggIEwAAAA==.Shoes:BAAANQAECgYICgAAAA==.Shtdruid:BAAANQAECgEIAQAAAA==.',
Si='Sibearian:BAAANQAECgQIBgAAAA==.Simi:BAAANQAECgMIBQAAAA==.',
Sm='Smokesçreen:BAAANQAECgUICwAAAA==.',
So='Soonerpride:BAAANQAECgIIAgAAAA==.Soothed:BAAANQADCggICAAAAA==.',
Sp='Spearminttea:BAAANQADCgIIAgAAAA==.Spellbreakr:BAAANQAECgcIDgAAAA==.Spirtbreaker:BAAANQAECgQIBAAAAA==.',
Sq='Squiby:BAAANQAECgYIEQAAAA==.',
St='Stankowitz:BAAANQABCgQICAABNQADCgYIBgABAAAAAA==.Starce:BAAANQABCgMIAwAAAA==.Steveirwin:BAAANQADCgUIBQAAAA==.Stheris:BAAANQAECgIIAgAAAA==.Stuefester:BAAANQAECgYIEQAAAA==.',
Sv='Sveika:BAAANQADCggIEwAAAA==.',
Sy='Sylaria:BAEANQADCgYICAAAAA==.Syreline:BAAANQAECgEIAQAAAA==.',
['Sï']='Sïn:BAAANQAECgIIBAAAAA==.',
['Sý']='Sýlver:BAAANQAECgQIBwAAAA==.',
Ta='Tarpalantir:BAAANQADCgcICAAAAA==.Taurne:BAABNQAECoEWAAINAAgJ8hrFCgCIAgANAAgJ8hrFCgCIAgAAAA==.',
Tc='Tchnce:BAAANQADCgcICgAAAA==.',
Te='Teknoman:BAAANQAECgUICgAAAA==.Telephone:BAAANQAECgEIAwAAAA==.Tempered:BAAANQAECgUICwAAAA==.Teresen:BAAANQADCgIIAgAAAA==.',
Th='Thaitea:BAAANQADCgIIBAAAAA==.Thalindra:BAAANQADCggIGQAAAA==.Tharain:BAAANQADCgUICwAAAA==.Thebigbeast:BAAANQAECgQIBQABNQAFFAUICQAJALQNAA==.Thecurt:BAAANQAECgYICwAAAA==.Thunderrbutt:BAAANQAECgQIBAAAAA==.',
Ti='Tiael:BAAANQAECgIIAgAAAA==.Timaeus:BAAANQADCgQIBAAAAA==.Tinylef:BAAANQAECgYIBgAAAA==.Tirouke:BAAANQADCgYICAAAAA==.Titanlock:BAAANQADCgQIBgAAAA==.',
Tk='Tkdfath:BAAANQADCgYIBgAAAA==.',
To='Toralina:BAAANQADCgYIBgAAAA==.Torvia:BAAANQADCgYICAAAAA==.',
Tr='Trisinz:BAAANQAECgQIBAAAAA==.',
Tu='Tuerto:BAAANQAECgQIBgAAAA==.Turbojohnson:BAAANQAECgEIAQAAAA==.Turk:BAAANQAECgYIEAAAAA==.Turkish:BAAANQAECgUIBwAAAA==.',
Tw='Twinkytoes:BAAANQADCggIEQAAAA==.',
Ty='Tychaa:BAAANQADCgUIBwAAAA==.Tyranax:BAAANQAECgEIAQAAAA==.Tyrith:BAAANQADCgIIAgAAAA==.',
Us='Userdel:BAAANQAECgMIAwAAAA==.',
Va='Valytrois:BAAANQAECgEIAQAAAA==.Variant:BAAANQAECgMIAwAAAA==.Vauld:BAAANQADCgMIBAAAAA==.',
Ve='Veiksla:BAAANQADCgUICQAAAA==.Vengerr:BAAANQADCgQIBAAAAA==.Verace:BAAANQAECgEIAQAAAA==.Verradic:BAAANQADCgcIEwAAAA==.',
Vi='Vitur:BAAANQAECgYIEgAAAA==.',
Vo='Voidbunny:BAAANQAECgUICQAAAA==.Volaine:BAAANQADCggIGgAAAA==.Volition:BAAANQADCgYIBgAAAA==.Volt:BAAANQAECgUIBgABNQAECgYIBwABAAAAAA==.',
Vr='Vrye:BAAANQAECggIBwAAAA==.',
Vy='Vynaeda:BAAANQAECgUIDQAAAA==.',
['Vô']='Vôx:BAAANQAECgIIBAAAAA==.',
Wa='Wakko:BAAANQADCgcIEwAAAA==.Walkure:BAAANQADCgUICwAAAA==.',
We='Weirdscience:BAAANQABCgQIBAAAAA==.',
Wh='Whew:BAAANQADCgIIAgAAAA==.',
Wr='Wreckbums:BAAANQAECgMIBAAAAA==.Wreckd:BAAANQADCgYIBgABNQAECgUICwABAAAAAA==.Wrongway:BAAANQABCgIIAgAAAA==.',
Xa='Xanthad:BAAANQADCgUICAAAAA==.',
Xb='Xb:BAAANQADCgUICwAAAA==.',
Xi='Xitãozinho:BAAANQADCgYIBgAAAA==.',
Ya='Yaalia:BAAANQADCggIGgAAAA==.Yaan:BAAANQAECgIIAgAAAA==.',
Za='Zain:BAAANQADCgYIBgABNQAECgYIEQABAAAAAA==.Zandibar:BAAANQADCggIFwAAAA==.Zavac:BAAANQADCgUIBwAAAA==.',
Ze='Zelritch:BAAANQADCggICAAAAA==.',
Zi='Zinfandell:BAAANQAECgMIAwAAAA==.',
Zo='Zorrloc:BAAANQADCgQIBAAAAA==.',
Zu='Zuggie:BAAANQADCgUICwABNQADCggICgABAAAAAA==.Zugtail:BAAANQADCggICgAAAA==.Zurtrinik:BAAANQAECgIIAgABNQAECgkJGQAFAB4dAA==.',
Zy='Zyntalla:BAAANQADCggIGgAAAA==.',
Zz='Zzonked:BAAANQAECgEIAQAAAA==.',
['Zê']='Zêp:BAAANQADCgcIFwAAAA==.',
['Àr']='Àrròw:BAAANQADCgYICgAAAA==.',
['Ðo']='Ðoogle:BAAANQADCggIHAABNQABCgMIAwABAAAAAA==.',
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
