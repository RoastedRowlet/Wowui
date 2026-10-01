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

local lookup = {'DeathKnight-Unholy','DeathKnight-Frost','Warrior-Protection','Shaman-Restoration','Unknown-Unknown','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Druid-Restoration','Druid-Feral','Druid-Guardian','Paladin-Retribution','Evoker-Preservation','Paladin-Protection','DemonHunter-Havoc','Hunter-BeastMastery','Paladin-Holy','Warrior-Arms','Warrior-Fury','Mage-Arcane','Shaman-Elemental','Mage-Frost','DemonHunter-Vengeance','Monk-Brewmaster','Monk-Windwalker','Rogue-Assassination','Rogue-Subtlety','DemonHunter-Devourer','Evoker-Devastation','Priest-Discipline','DeathKnight-Blood','Priest-Shadow','Priest-Holy','Druid-Balance',}
local provider = {region='US',realm='Perenolde',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aanien:BAAANQADCgYICAAAAA==.',
Ac='Acedk:BAABNQAECoEhAAMBAAkKSSL9DAApAwABAAkKMiH9DAApAwACAAUKKyFqLADXAQAAAA==.Aceslam:BAAANQAECggIEwABNQAECgkJIQABAEkiAA==.',
Ad='Adrador:BAAANQAECgUIDAAAAA==.Adrenaline:BAABNQAECoErAAIDAAkKvCIJAgB6AwADAAkKvCIJAgB6AwAAAA==.',
Ae='Aelik:BAABNQAECoEfAAIBAAYKSBgqRwCUAQABAAYKSBgqRwCUAQAAAA==.Aeolian:BAAANQADCgYIDgAAAA==.Aeru:BAAANQADCgQIBAAAAA==.',
Ak='Akueria:BAAANQADCgcIBwAAAA==.',
Al='Alayssa:BAAANQAECgQICQAAAA==.Alda:BAAANQADCgYIFgAAAA==.Alemental:BAAANQAECgYICwAAAA==.Aleska:BAAANQAECgQICwAAAA==.Allarius:BAAANQAECgQIBAAAAA==.Alo:BAABNQAECoEZAAIEAAgK4xVaRAADAgAEAAgK4xVaRAADAgABNQAECgEJAQAFAAAAAA==.',
Am='Amilee:BAAANQADCgcICQAAAA==.Amoondai:BAAANQADCgYICAAAAA==.Amoondrin:BAAANQAECgYICgAAAA==.',
An='Analiya:BAAANQADCgQJBQAAAA==.Anatyr:BAAANQADCgcIBwAAAA==.',
Ar='Aramathis:BAAANQAECgUIBQAAAA==.Araviin:BAAANQAECgUICAAAAA==.Arbor:BAAANQAECgQIBwAAAA==.Arcillias:BAAANQADCgYJBgABNQAECgQJBwAFAAAAAA==.Arilas:BAAANQAECgQIBAABNQAECgQJBwAFAAAAAA==.Arkanist:BAAANQAECgMIBgAAAA==.Arthia:BAAANQADCgYICQAAAA==.Arvidpally:BAAANQAECgIIAwAAAA==.',
As='Ashesius:BAABNQAECoEkAAQGAAgKZBR4CwAsAgAGAAgK+RN4CwAsAgAHAAMKtgjD5gCIAAAIAAEKBgF/LAAZAAAAAA==.Ashmehameha:BAAANQAECgEIAQABNQAECgYIBwAFAAAAAA==.',
At='Atredes:BAAANQAECgQICwAAAA==.',
Au='Auspex:BAAANQAECgUIDQAAAA==.',
Av='Avaryn:BAABNQAECoEYAAIJAAkK2BWDFgBDAgAJAAkK2BWDFgBDAgAAAA==.',
Ax='Aximlii:BAAANQADCgIIBAAAAA==.',
Ba='Babs:BAAANQADCgMIAwAAAA==.Badaracka:BAABNQAECoEhAAMKAAkKAiLMAgBSAwAKAAkKAiLMAgBSAwALAAUKlh7REQC/AQAAAA==.Bahamuth:BAABNQAECoEbAAIMAAgKlRU6agADAgAMAAgKlRU6agADAgAAAA==.Bahamutsrage:BAAANQADCggIDgABNQAECgQIBAAFAAAAAA==.Balder:BAAANQAECgYICwABNQAFFAIIBAAFAAAAAQ==.Barbattos:BAABNQAECoEpAAINAAkKxiHyBABIAwANAAkKxiHyBABIAwAAAA==.',
Bd='Bdyrk:BAAANQAECgUICQABNQAECgkJIQAKAAIiAA==.',
Be='Bealzeboss:BAAANQADCgcICQAAAA==.Bexley:BAABNQAECoEXAAIOAAgKzxh3EwAcAgAOAAgKzxh3EwAcAgAAAA==.',
Bi='Biggerbunny:BAAANQAECgcIBwAAAA==.Biglarry:BAAANQADCgMJBQAAAA==.Biianca:BAAANQADCgUICQAAAA==.',
Bl='Blacklok:BAAANQAECgEIAgABNQAECgkJIQAPALUjAA==.Blanne:BAAANQABCgIIAgAAAA==.Blargle:BAAANQAECgIIAwAAAA==.Blegh:BAABNQAECoEdAAIMAAkK0SDRGgAvAwAMAAkK0SDRGgAvAwAAAA==.Blinx:BAAANQAECgEIAgAAAA==.Bloodrake:BAABNQAECoEeAAIQAAgKUxnEQABgAgAQAAgKUxnEQABgAgAAAA==.Blueray:BAAANQADCgYIBgAAAA==.',
Bm='Bman:BAAANQAECgQIBgAAAA==.',
Br='Braneour:BAABNQAECoEbAAMOAAgKqxTrGwC0AQAOAAgKqxTrGwC0AQARAAYK1QfyjQAgAQAAAA==.Browel:BAAANQAECgYIDwAAAA==.',
Bu='Bumm:BAAANQADCgYICgAAAA==.',
Bz='Bzspy:BAABNQAECoEbAAMSAAkKkhbdTABlAgASAAkKkhbdTABlAgATAAIK9AqEIABhAAAAAA==.',
['Bë']='Bëar:BAAANQAECgEIAQAAAA==.',
Ca='Calyptus:BAAANQAECgYIDwAAAA==.Capylaura:BAAANQAECgMIBgAAAA==.Caratine:BAAANQADCgcIDQAAAA==.Cassandrah:BAABNQAECoEYAAIUAAgKDB+FTwC7AgAUAAgKDB+FTwC7AgAAAA==.',
Ce='Celìa:BAAANQADCggICgAAAA==.',
Ch='Chillymage:BAAANQADCgcIBwAAAA==.Christy:BAAANQADCgYIFQAAAA==.Chugg:BAAANQAECgQICwAAAA==.',
Ci='Ciaphus:BAABNQAECoEcAAQMAAgKNRIlmgCBAQAMAAcKFhAlmgCBAQARAAcKIwpTbgB7AQAOAAMKtwq0RQB8AAAAAA==.Cinnamonster:BAAANQAECgQIBwAAAA==.',
Cl='Clogs:BAAANQAECgUIBgAAAA==.',
Co='Coffeedemon:BAAANQAECgIJAgAAAA==.Coldslappins:BAAANQADCgUIBQABNQAECggIGwAOAKsUAA==.Convalescent:BAAANQADCgYIBgAAAA==.Coragrr:BAAANQAECgIIAwAAAA==.',
Cr='Cracklepants:BAACNQAFFIEFAAIVAAIKyQZdGwCMAAAVAAIKyQZdGwCMAAA1AAQKgScAAhUACQqdGNQqAJYCABUACQqdGNQqAJYCAAAA.Crashout:BAAANQADCgYICgAAAA==.',
Cu='Curtastrophe:BAABNQAECoEZAAIWAAgKCx0bBACyAgAWAAgKCx0bBACyAgAAAA==.',
Da='Daelanos:BAAANQAECgUIBQAAAA==.Dallas:BAAANQADCgYICwAAAA==.',
De='Deathoof:BAAANQAECgYIDwAAAA==.Demonblaze:BAAANQAECgIJAgAAAA==.Demonilla:BAAANQAECgYICwAAAA==.Destro:BAABNQAECoEXAAIHAAgKjQqGcAC1AQAHAAgKjQqGcAC1AQAAAA==.',
Di='Dilaudyd:BAAANQADCgcICQAAAA==.Disbeleaf:BAAANQAECgYICAAAAA==.Dishu:BAAANQABCgQIBAAAAA==.Dispel:BAAANQADCgYIBgAAAA==.Disputatious:BAAANQADCgQIBAAAAA==.',
Dn='Dntblink:BAAANQADCgUIBQAAAA==.',
Do='Dogaz:BAAANQADCgYIFQAAAA==.Dogsoldier:BAAANQADCgQIBAAAAA==.Donori:BAAANQADCgEIAQAAAA==.Doomphoenix:BAAANQADCgQJBAAAAA==.',
Dr='Dragonias:BAAANQAECgIIAwAAAA==.Drakthorn:BAAANQADCggIEAAAAA==.Drinny:BAAANQAECgYIDgAAAA==.Dripington:BAABNQAECoEdAAMCAAgKbiA3EQDJAgACAAgKbiA3EQDJAgABAAEKGRM1rAA2AAAAAA==.',
Ea='Earthangel:BAAANQAECgEIAgAAAA==.',
Ef='Efon:BAAANQADCgUIBQABNQAECgQICQAFAAAAAA==.',
Ei='Eine:BAAANQAECgYIEwAAAA==.',
El='Eldergreen:BAAANQAECgUIEAAAAA==.Elfwine:BAAANQAECgEIAgAAAA==.Elindria:BAABNQAECoEhAAMPAAkKtSNYAwCwAwAPAAkKtSNYAwCwAwAXAAEKLQomJQA0AAAAAA==.Elminstir:BAAANQAECgYIDAAAAA==.Eluzhion:BAAANQADCgUICAAAAA==.Elysian:BAAANQAECgUICQAAAA==.',
Er='Erizhal:BAAANQABCgIIAgAAAA==.Eruptyon:BAAANQAECgEIAQABNQAECgUIDwAFAAAAAA==.',
Es='Esabel:BAAANQAECgcIDgABNQAECgQICQAFAAAAAA==.',
Ev='Eviae:BAAANQAECgEIAgAAAA==.Evillure:BAAANQAECgQJBAAAAA==.',
Ex='Explanation:BAAANQADCgQIBAAAAA==.',
Fa='Falan:BAAANQAECgEIAQAAAA==.Farfins:BAAANQADCgYIBgAAAA==.',
Fe='Feår:BAAANQAECgQIBwAAAA==.',
Fi='Finley:BAAANQADCgQIBAAAAA==.Fixation:BAAANQABCgIIAgAAAA==.',
Fl='Flane:BAACNQAFFIEMAAIYAAUKQRcTAgCBAQAYAAUKQRcTAgCBAQA1AAQKgR4AAxgACQp+HdcFAL0CABgACQp+HdcFAL0CABkAAQonHUhNAFAAAAAA.Flexdruid:BAAANQADCgQIBgAAAA==.',
Fr='Fragil:BAABNQAECoEVAAMaAAcK8hpOHQA9AgAaAAcK8hpOHQA9AgAbAAQKHQ+ZMgDpAAAAAA==.',
Ga='Galena:BAAANQAECgIIAwAAAA==.Galian:BAAANQADCggICgAAAA==.Ganonn:BAAANQAECgQICQAAAA==.',
Ge='Geshtal:BAAANQAECgQIBQAAAA==.',
Gi='Girion:BAAANQAECgEIAgAAAA==.',
Gl='Glaiven:BAEBNQAECoErAAMPAAkKVSExCgA4AwAPAAkKPyExCgA4AwAcAAcKzxgyJQDgAQAAAA==.Glyr:BAAANQAECgEJAQAAAA==.',
Go='Gorgrin:BAAANQAECgEIAQAAAA==.',
Gr='Groguu:BAAANQAECgQIBAABNQAECgkJIQABAEkiAA==.',
Ha='Harkanum:BAABNQAECoEkAAMdAAgK5ghvFwCSAQAdAAgK5ghvFwCSAQANAAgKqwSGIwBfAQAAAA==.Harvester:BAAANQAECgMIBwAAAA==.',
He='Healinturds:BAAANQADCgEIAQAAAA==.Helloagain:BAAANQAECggJEgAAAA==.',
Hi='Hidethetotem:BAAANQAECgEIAgAAAA==.Hikari:BAABNQAECoEaAAIMAAkKuBvgOACnAgAMAAkKuBvgOACnAgAAAA==.Hiown:BAAANQABCgYICAAAAA==.',
Ho='Holyrebel:BAAANQAECgEIAQAAAA==.Holyspike:BAAANQAECgIIAwAAAA==.Homerr:BAAANQAECgIIAgAAAA==.Honiahaka:BAABNQAECoEcAAIQAAgKPwkUcgDRAQAQAAgKPwkUcgDRAQAAAA==.Hotsdog:BAAANQADCgIIAgAAAA==.Hottcakes:BAABNQAECoEeAAIUAAkKyR9OGwBWAwAUAAkKyR9OGwBWAwABNQAFFAcIEwAHAEoVAA==.',
Hu='Humanoidlite:BAAANQAFFAEIAQAAAA==.Humanoidlock:BAAANQADCgYIDAABNQAFFAEIAQAFAAAAAA==.Humanoidwar:BAABNQAECoEiAAMSAAkK5xwiKgDnAgASAAkK5xwiKgDnAgADAAIK8QVwMABEAAABNQAFFAEIAQAFAAAAAA==.',
In='Inoru:BAAANQAECgMIAwAAAA==.',
Ir='Irmaline:BAAANQAECgIIAwAAAA==.',
It='Ithurtshuh:BAAANQAECgEIAQABNQAECgEIAQAFAAAAAA==.',
Ja='Jabbawockie:BAAANQAECggIDwAAAA==.Jackcat:BAAANQADCgQIAwAAAA==.',
Je='Jeffee:BAAANQAECgYIDwAAAA==.Jennifleur:BAAANQADCgcIBwAAAA==.Jequalsjosh:BAAANQAECgcIBwAAAA==.Jerk:BAACNQAFFIELAAIcAAUKWSIpAwD0AQAcAAUKWSIpAwD0AQA1AAQKgSgAAhwACQrtJKoCAKUDABwACQrtJKoCAKUDAAAA.Jesper:BAABNQAECoEkAAIEAAgKFB5qIACyAgAEAAgKFB5qIACyAgAAAA==.Jetz:BAAANQAECgQICQAAAA==.',
Ji='Jilara:BAAANQAECgMIBQAAAA==.Jimmyjim:BAAANQAECgIIAwAAAA==.',
Jo='Jockko:BAAANQADCggICAAAAA==.Joink:BAAANQADCgYICQAAAA==.',
Jp='Jpepps:BAABNQAECoEeAAMHAAcK+wwBdwCiAQAHAAcKPQwBdwCiAQAGAAMKcAToVABtAAAAAA==.',
Jr='Jrose:BAAANQADCgYIEQAAAA==.',
Ka='Kagozo:BAEANQAECgEIAQABNQAECgIIAgAFAAAAAA==.Kaiatra:BAAANQAECgIIAwAAAA==.Kalamor:BAAANQADCggICAAAAA==.Kaloran:BAAANQAECgUIDAAAAA==.Katalaystar:BAAANQADCgYIDAABNQAECggIGgAJAIMaAA==.Katalegdh:BAAANQAECgEIAQAAAA==.Kaìju:BAAANQAECgMICAAAAA==.',
Kh='Khaelyn:BAAANQADCgIJAgAAAA==.Khai:BAAANQAECggIDQAAAA==.',
Ki='Kiae:BAAANQADCgYJBwAAAA==.Kidneyspears:BAAANQADCgYIBgAAAA==.Kilaura:BAAANQADCgUIBQAAAA==.Kilmandaros:BAAANQAECgUIBQAAAA==.Kimblee:BAAANQADCgQIBAAAAA==.',
Ko='Korbix:BAAANQABCgUIBAABNQAECgUIBgAFAAAAAA==.',
Ku='Kudria:BAAANQAECgYIDAAAAA==.Kunei:BAAANQABCgYICQABNQAECgEIAQAFAAAAAA==.Kurdran:BAAANQABCgQIAgAAAA==.Kuroyukihime:BAAANQAECgYIEAAAAA==.',
Ky='Kynae:BAAANQAECgQIEQAAAA==.Kyross:BAAANQABCgIIAgAAAA==.',
['Ká']='Kárma:BAAANQADCgYICwABNQAECgQIBwAFAAAAAA==.',
La='Lashela:BAAANQAECgUICAAAAA==.Laughter:BAAANQAECgEIAgAAAA==.Laylla:BAAANQAECgIIAgAAAA==.Lazulie:BAAANQADCgYJEwAAAA==.',
Le='Lefnedrav:BAAANQADCgYIBgABNQAECgYIEAAFAAAAAA==.Lektrik:BAAANQADCgcIDwAAAA==.Lexapayne:BAAANQADCgEIAQABNQAECgUICgAFAAAAAA==.Leyra:BAAANQAECgYICwABNQAECgkJIQAPALUjAA==.',
Li='Lighthammer:BAAANQADCggIDgAAAA==.Lightmessiah:BAAANQAECgcIEgAAAA==.Lightnig:BAAANQADCgUIBQAAAA==.Lilyvain:BAAANQAECgEIAQAAAA==.Lireal:BAABNQAECoEbAAIRAAgK4R/KFwDxAgARAAgK4R/KFwDxAgAAAA==.Livnod:BAAANQADCgcIBwAAAA==.',
Lo='Lonon:BAAANQAECgcJEwAAAA==.Loosescrew:BAAANQADCgQIBQAAAA==.Lorine:BAABNQAECoEXAAIOAAgKFhHQGgDAAQAOAAgKFhHQGgDAAQAAAA==.',
Lu='Lunara:BAAANQADCgYIDAAAAA==.',
Ly='Lynnethe:BAAANQAECgYICQAAAA==.',
Ma='Malkiel:BAAANQAECgQICwAAAA==.Mantang:BAAANQABCgIIAgAAAA==.Mastakillah:BAAANQADCgQICAABNQAECgQIDAAFAAAAAA==.',
Me='Meeseeks:BAAANQAECgcIDQAAAA==.Merckel:BAABNQAECoEdAAIcAAgKzRj8FgB3AgAcAAgKzRj8FgB3AgAAAA==.Messorom:BAAANQADCgEIAQAAAA==.',
Mi='Michello:BAAANQAECgIIAwAAAA==.Mightytot:BAAANQADCgQIBAAAAA==.Millia:BAAANQAECgUIDwAAAA==.Mint:BAABNQAECoEfAAIRAAkKGBUELQB5AgARAAkKGBUELQB5AgAAAA==.Mintberrytea:BAAANQAECgQJBAABNQAECgkJHwARABgVAA==.Misstress:BAAANQAECgUIDQAAAA==.',
Mo='Moistweaver:BAAANQADCgYJBgAAAA==.Monoxide:BAAANQADCgUIBQABNQAECgYJDwAFAAAAAA==.Moonhunt:BAAANQADCggIIAAAAA==.Morkleb:BAAANQAECgEIAQAAAA==.Morrag:BAAANQAECgQICQAAAA==.Morrtisha:BAAANQAECgYICwAAAA==.',
Mu='Munden:BAAANQADCgUIBQAAAA==.',
My='Myxie:BAAANQAECgQICgAAAA==.',
['Mí']='Mísfìt:BAABNQAECoEdAAIEAAgKyB54IACyAgAEAAgKyB54IACyAgAAAA==.',
Na='Nakaito:BAAANQAECgQIBgABNQAECggIFwAaAFoRAA==.Narcoleptic:BAABNQAECoEgAAMNAAgK8hR2FgAaAgANAAgK8hR2FgAaAgAdAAUKPw8wIAAQAQAAAA==.Nashty:BAAANQADCgIIAgAAAA==.Naturaljuice:BAAANQAECgcICgABNQAFFAcIEwAHAEoVAA==.Naturebreakr:BAAANQAECgcICwAAAA==.',
Ne='Nex:BAAANQAECggIEgAAAA==.',
Ni='Nightsawdy:BAAANQAECgQIBgAAAA==.Niightstorm:BAAANQAECgEIAgAAAA==.Nilvannas:BAAANQADCggICAAAAA==.Nitefire:BAAANQADCgYIFgAAAA==.Nitélifé:BAAANQADCggIEwAAAA==.',
Of='Offspring:BAAANQABCgIIAgAAAA==.',
Om='Omora:BAAANQAECgQICAABNQAECgYIEAAFAAAAAA==.',
Op='Opalinnas:BAABNQAECoEaAAIJAAgKgxpvEACWAgAJAAgKgxpvEACWAgAAAA==.Optimism:BAAANQADCgIIAgAAAA==.',
Pa='Paladrone:BAAANQABCggIDwABNQADCgEIAQAFAAAAAA==.Pallyandtank:BAAANQAECgEJAQAAAA==.Panzer:BAAANQAECgUIDAAAAA==.Parts:BAAANQAECgYIDAABNQAECggIGQASAJARAA==.Passionfruit:BAAANQADCgQJBAAAAA==.Paul:BAAANQAECgUICgAAAA==.',
Pe='Peachtea:BAAANQAECgEJAgAAAA==.Pepecojon:BAAANQADCggIDwAAAA==.',
Pi='Piebaby:BAAANQADCgEIAQAAAA==.Pirodeath:BAAANQAECgUIBQAAAA==.',
Pl='Plovdiv:BAAANQADCgcJCQAAAA==.',
Po='Poah:BAAANQAECgYIBgAAAA==.',
Pr='Pray:BAABNQAECoEcAAIeAAgKMiTwAABLAwAeAAgKMiTwAABLAwAAAA==.Prodarkangel:BAAANQADCgcJCQAAAA==.',
Pu='Puckllane:BAAANQAECgEIAgAAAA==.Punkin:BAAANQADCgQIBAAAAA==.',
Py='Pyre:BAABNQAECoEcAAIeAAcKOA5DCQCQAQAeAAcKOA5DCQCQAQABNQAECgEJAQAFAAAAAA==.',
['Pü']='Püff:BAAANQADCgEIAQABNQAECgQJBwAFAAAAAA==.',
Qu='Quanah:BAAANQAECgQICQAAAA==.Quivver:BAAANQADCgYIEgAAAA==.',
Ra='Rabmaxx:BAAANQAECggICgAAAA==.Raina:BAAANQADCgYIBgAAAA==.Ravenlight:BAABNQAECoEZAAIMAAgKTRSuaQAFAgAMAAgKTRSuaQAFAgAAAA==.Ravenwynnd:BAABNQAECoEdAAMSAAgKch9pNgC1AgASAAgKBR9pNgC1AgADAAYK3RtcDgDtAQAAAA==.Raynman:BAABNQAECoEaAAIVAAgK0g/dTwDoAQAVAAgK0g/dTwDoAQAAAA==.',
Re='Reylariel:BAAANQADCgMIAwAAAA==.',
Rh='Rhydian:BAAANQADCgQIBAAAAA==.Rhyzer:BAAANQAECgEIAgAAAA==.',
Ri='Riiver:BAAANQADCgYIBgAAAA==.',
Ro='Roderick:BAAANQADCgcICQAAAA==.Root:BAAANQADCgUIDQABNQAECgkJJQABADkfAA==.',
Ru='Rubmytotem:BAAANQAECgQJBQAAAA==.',
Sa='Sabazia:BAABNQAECoEbAAIfAAgKShPPOQDeAQAfAAgKShPPOQDeAQAAAA==.Sabelinå:BAAANQAECgEIAQAAAA==.Sable:BAAANQADCgEIAQAAAA==.Sacred:BAAANQAECgQIBgAAAA==.Saerise:BAAANQADCgcIBwAAAA==.Sairalindë:BAAANQAECgEIAgAAAA==.Salamandra:BAAANQADCgQIBAABNQAECgYIEAAFAAAAAA==.Saleath:BAAANQAECgIIAgAAAA==.Salios:BAAANQAECgEIAQAAAA==.Sanara:BAAANQABCgUIBwABNQAECgEIAgAFAAAAAA==.Sanctifier:BAAANQADCgUIBQAAAA==.',
Sc='Scrept:BAAANQAECgcICQAAAA==.Scynix:BAEANQAECgYJCwAAAA==.',
Se='Seizuregoat:BAAANQAECgMJAwAAAA==.Senus:BAAANQADCgEIAQAAAA==.Servoker:BAAANQAECgUICQAAAA==.',
Sh='Shabzyt:BAAANQAECgUICgAAAA==.Shaienne:BAAANQADCgcIDgAAAA==.Shammander:BAAANQADCgcIDgAAAA==.Shamrockshak:BAAANQAECgIIBAAAAA==.Shamron:BAAANQADCgEIAQAAAA==.Shenuton:BAAANQADCgMIAwAAAA==.Shieldbash:BAABNQAECoEjAAIDAAgK9iUlAgBzAwADAAgK9iUlAgBzAwAAAA==.Shockthêràpy:BAABNQAECoEfAAMEAAkKHCBpEgAJAwAEAAkKHCBpEgAJAwAVAAEKzw4P9AA7AAAAAA==.Shoes:BAAANQAECgYICgAAAA==.Shtdruid:BAAANQAECgEIAQAAAA==.',
Si='Sibearian:BAAANQAECgUIDgABNQAECgYIDwAFAAAAAA==.Sibeson:BAAANQAECgUIBQABNQAECgYIDwAFAAAAAA==.Simi:BAAANQAECgUICgAAAA==.',
Sm='Smokesçreen:BAABNQAECoEbAAMXAAcK+A1KDwBfAQAPAAcKjApPOwByAQAXAAcKEQ1KDwBfAQAAAA==.',
So='Soonerpride:BAAANQAECgQICQAAAA==.Soothed:BAAANQADCggICAAAAA==.',
Sp='Spearminttea:BAAANQADCgIIAgAAAA==.Spellbreakr:BAABNQAECoEVAAIUAAkKOxslXwCTAgAUAAkKOxslXwCTAgAAAA==.Spirtbreaker:BAAANQAECgQICAAAAA==.',
Sq='Squeak:BAAANQADCgEJAQAAAA==.Squiby:BAABNQAECoEaAAMgAAgKMR5KEgCdAgAgAAgKMR5KEgCdAgAhAAEKlxXqxAA8AAAAAA==.',
St='Stankowitz:BAAANQABCgQICAABNQADCgYIBgAFAAAAAA==.Starboi:BAAANQADCgUIBQAAAA==.Starce:BAAANQABCgMIAwAAAA==.Steveirwin:BAAANQADCgUIBQAAAA==.Stheris:BAAANQAECgcICQAAAA==.Stuefester:BAAANQAECgYIEQAAAA==.',
Sv='Sveika:BAAANQAECgIIAwAAAA==.',
Sy='Sylaria:BAEANQADCgcICQAAAA==.Syreline:BAAANQAECgEIAQAAAA==.',
['Sï']='Sïn:BAAANQAECgMIBwAAAA==.',
['Sý']='Sýlver:BAAANQAECgUIEAAAAA==.',
Ta='Tarpalantir:BAAANQADCgcICAAAAA==.Taurne:BAABNQAECoEhAAMJAAgK8hoKFABkAgAJAAgK8hoKFABkAgAiAAMKiQVBfAB+AAAAAA==.',
Tc='Tchnce:BAAANQADCgcICgAAAA==.',
Te='Teknoman:BAABNQAECoEbAAMSAAgKRBXiXwAmAgASAAgKRBXiXwAmAgADAAEKBwU6OQAjAAAAAA==.Telephone:BAAANQAECgEIBAAAAA==.Tempered:BAABNQAECoEZAAISAAgKkBFKdgDjAQASAAgKkBFKdgDjAQAAAA==.Teresen:BAAANQADCgIIAgAAAA==.',
Th='Thaitea:BAAANQADCgIIBAAAAA==.Thalindra:BAAANQAECgEIAgAAAA==.Tharain:BAAANQAECgEIAQAAAA==.Thebigbeast:BAAANQAECgQIDAABNQAFFAcIEwAHAEoVAA==.Thecurt:BAABNQAECoEcAAIYAAgKCiOwAwAgAwAYAAgKCiOwAwAgAwAAAA==.Thunderrbutt:BAAANQAECgYIEwAAAA==.Thyralizen:BAAANQADCgIIAgAAAA==.',
Ti='Tiael:BAAANQAECgIIAgAAAA==.Timaeus:BAAANQADCgUIEAAAAA==.Tinylef:BAAANQAECgYIEAAAAA==.Tirouke:BAAANQAECgEIAQAAAA==.Titanlock:BAAANQADCgUIBwAAAA==.',
Tk='Tkdfath:BAAANQADCgYIBgAAAA==.',
To='Toralina:BAAANQAECgEIAQAAAA==.Torvia:BAAANQADCgYJCAAAAA==.',
Tr='Trisinz:BAAANQAECgUJCQAAAA==.',
Tu='Tuerto:BAAANQAECgQIBgAAAA==.Turbojohnson:BAAANQAECgEIAQAAAA==.Turk:BAABNQAECoEjAAIcAAgKag0PJQDiAQAcAAgKag0PJQDiAQAAAA==.Turkish:BAABNQAECoEUAAICAAcKyQugOgB0AQACAAcKyQugOgB0AQAAAA==.',
Tw='Twinkytoes:BAAANQADCggIEwAAAA==.',
Ty='Tychaa:BAAANQADCgYIEgAAAA==.Tyranax:BAAANQAECgUIDgAAAA==.Tyrith:BAAANQADCgMJAwAAAA==.',
Ul='Ullyr:BAAANQAECggIDwABNQAFFAIIBQAVAMkGAA==.',
Us='Userdel:BAAANQAECgUIDAAAAA==.',
Va='Vadose:BAAANQADCgYIBgABNQAECgUICgAFAAAAAA==.Valytrois:BAAANQAECgEIAQAAAA==.Variant:BAAANQAECgMIAwAAAA==.Varinix:BAAANQADCgUIBQAAAA==.Vauld:BAAANQADCgQJBQAAAA==.',
Ve='Veiksla:BAAANQADCgYIFAAAAA==.Vengerr:BAAANQADCgYIDwAAAA==.Verace:BAAANQAECggIAQAAAA==.Verradic:BAAANQAECgQIBAAAAA==.',
Vi='Vitur:BAABNQAECoEnAAIcAAkKdiLECQAiAwAcAAkKdiLECQAiAwAAAA==.Vivi:BAAANQADCgYIBgAAAA==.',
Vo='Voidbunny:BAAANQAECgYJDwAAAA==.Volaine:BAAANQAECgEIAgAAAA==.Volgar:BAAANQADCgEIAQAAAA==.Volition:BAAANQADCgYIBgAAAA==.Volt:BAAANQAECgcIDgABNQAECggIFwAHAI0KAA==.',
Vr='Vrye:BAAANQAECggIBwAAAA==.',
Vy='Vynaeda:BAAANQAECgUIDwAAAA==.',
['Vô']='Vôx:BAAANQAECgIIBQABNQAECgMIAwAFAAAAAA==.',
Wa='Wakko:BAAANQADCgcIEwAAAA==.Walkure:BAAANQADCgYIFgAAAA==.',
We='Weirdscience:BAAANQABCgQIBAAAAA==.Wetasstotem:BAAANQAECgcIBwABNQAFFAcIEwAHAEoVAA==.',
Wh='Whew:BAAANQADCggICQAAAA==.',
Wi='Widge:BAAANQAECgQIBAAAAA==.Wikker:BAAANQADCgQIBAAAAA==.',
Wr='Wreckbums:BAAANQAECgMIBAAAAA==.Wreckd:BAAANQADCgYIBgABNQAECggIGQASAJARAA==.Wrongway:BAAANQADCgIJAgAAAA==.',
Xa='Xanthad:BAAANQADCgUICAAAAA==.',
Xb='Xb:BAAANQADCgYIFgAAAA==.',
Xi='Xitãozinho:BAAANQAECgEIAQAAAA==.',
Xy='Xyomi:BAAANQADCgIJAgAAAA==.',
Ya='Yaalia:BAAANQAECgEIAgAAAA==.Yaan:BAAANQAECgYICQAAAA==.',
Za='Zain:BAAANQADCgYIBgABNQAECggIJAAGAGQUAA==.Zandibar:BAAANQAECgEIAgAAAA==.Zaptoasted:BAAANQADCgYIBgAAAA==.Zariea:BAAANQAECgIIAgABNQAECgcIHwABAEgYAA==.Zavac:BAAANQADCgUIBwAAAA==.',
Ze='Zelritch:BAAANQADCggICAAAAA==.',
Zi='Zinfandell:BAAANQAECgUIBgAAAA==.',
Zo='Zorrloc:BAAANQADCgQIBAAAAA==.',
Zu='Zuggie:BAAANQAECgIIAgAAAA==.Zugtail:BAAANQAECgEIAQABNQAECgIIAgAFAAAAAA==.Zurtrinik:BAAANQAECgUICwABNQAFFAUIDAAYAEEXAA==.',
Zy='Zyntalla:BAAANQAECgEIAgAAAA==.',
Zz='Zzonked:BAAANQAECgEIAQAAAA==.',
['Zê']='Zêp:BAAANQADCgcIFwAAAA==.',
['Àr']='Àrròw:BAAANQADCgYICgAAAA==.',
['Ðo']='Ðoogle:BAAANQAECgIIAwABNQABCgMIAwAFAAAAAA==.',
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
