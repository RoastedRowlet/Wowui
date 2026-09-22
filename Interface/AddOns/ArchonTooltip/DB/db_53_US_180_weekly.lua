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

local lookup = {'Mage-Arcane','Unknown-Unknown','Warlock-Demonology','Warlock-Destruction','Paladin-Retribution','DeathKnight-Blood','DeathKnight-Unholy','Monk-Mistweaver','Priest-Holy','Monk-Brewmaster','Warrior-Arms','Monk-Windwalker','Shaman-Restoration','Shaman-Elemental','Hunter-Survival','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Assassination',}
local provider = {region='US',realm='Rivendare',name='US',type='weekly',zone=53,date='2026-09-22',data={Ad='Ado:BAAANQADCgMIAwABNQAFFAYJCwABALIRAA==.',
Ae='Aelin:BAAANQAECgQIBAAAAA==.',
Ai='Aimer:BAAANQAECgIIBAABNQAFFAYJCwABALIRAA==.',
Al='Alkanz:BAAANQAECgYIDwAAAA==.Allinaa:BAAANQAECgIIAgAAAA==.Alya:BAAANQAECgYIEwAAAA==.',
An='Anika:BAAANQAECgcIEgAAAA==.Anshi:BAAANQAECgQIBAABNQAECgUJDQACAAAAAA==.',
Ar='Arlyx:BAABNQAECoEXAAMDAAkKsRg1OQA5AgADAAcKXhk1OQA5AgAEAAUKoRXXHwBOAQAAAA==.Arnwaz:BAAANQAECgQIBgAAAA==.Arthuria:BAAANQAECgMIBQAAAA==.',
As='Ashzazul:BAAANQABCgcICwAAAA==.Asianverstop:BAAANQAECgcIDAAAAA==.',
At='Atelwen:BAAANQADCgYJBgAAAA==.',
Ba='Baf:BAABNQAECoEdAAIFAAgKJCMuHAACAwAFAAgKJCMuHAACAwAAAA==.Banano:BAAANQAECgIIAgAAAA==.Banjodave:BAAANQAECgIJAgAAAA==.',
Be='Berfomat:BAAANQAECgcJEwAAAA==.Berfsteals:BAAANQADCgIIBAAAAA==.Berfy:BAAANQADCggICgAAAA==.',
Bj='Bjorn:BAAANQAECgYICQAAAA==.',
Bl='Blackky:BAAANQAECgEJAQAAAA==.Bloodyfupa:BAAANQADCgEIAQAAAA==.Bloomyvfd:BAAANQAECgQJBQAAAA==.',
Bo='Bocc:BAAANQADCgQIBQABNQAECgUJBQACAAAAAA==.Boombip:BAAANQABCgMIAwAAAA==.Boxxylove:BAAANQADCggICgABNQAECgYIEwACAAAAAA==.',
Br='Brockz:BAAANQADCgQIBwAAAA==.',
Bu='Bulldan:BAAANQABCgIIAQAAAA==.',
['Bî']='Bîa:BAAANQAECgYIDQAAAA==.',
Ca='Cavalis:BAAANQAECgcJEwAAAA==.',
Ce='Ceedk:BAACNQAFFIEIAAIGAAUKvR5OBAC1AQAGAAUKvR5OBAC1AQA1AAQKgR4AAwcACQp4JlcDALMDAAcACQp4JlcDALMDAAYABwqSIXYYAJUCAAAA.Ceesh:BAAANQAECggIAgABNQAFFAUJCAAGAL0eAA==.',
Ch='Chickenparm:BAAANQADCgYICQAAAA==.',
Cj='Cjjackpot:BAAANQADCgYJCwAAAA==.',
Co='Cobb:BAAANQAECgQICAABNQAECgUJBQACAAAAAA==.Coorsbanquet:BAAANQADCgMIAwAAAA==.',
Cr='Creativezd:BAAANQAFFAMJAwABNQAFFAUJCAAGAL0eAA==.Crowley:BAAANQAECgMJBAAAAA==.',
Da='Dadgoo:BAAANQAECgMJBAAAAA==.Damnskippy:BAAANQADCgUIDQAAAA==.Dannÿ:BAAANQAECgUIDQAAAA==.Darkire:BAAANQAECgMIAwAAAA==.',
De='Deathroll:BAABNQAECoEaAAIIAAgKABGDEQDgAQAIAAgKABGDEQDgAQAAAA==.Demosucc:BAAANQAFFAMJBAAAAA==.Dethandra:BAAANQADCggICAAAAA==.',
Dk='Dkchilly:BAABNQAECoEdAAIHAAkKrh3OEADzAgAHAAkKrh3OEADzAgAAAA==.',
Do='Doomward:BAAANQADCggJHwAAAA==.Dorien:BAAANQAECgcJEwAAAA==.',
['Då']='Dårk:BAAANQADCgEIAQAAAA==.',
El='Elysele:BAAANQADCgUIBQABNQAECggIHAAJAKsNAA==.',
Er='Erale:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.',
Fa='Faewryn:BAAANQAECgYIDwAAAA==.Falekia:BAAANQAECgcICgAAAA==.Falnaz:BAAANQAECgIIAwAAAA==.Fay:BAABNQAECoEdAAIKAAgK/R+eBADPAgAKAAgK/R+eBADPAgAAAA==.',
Fe='Fellus:BAAANQADCgIIAgAAAA==.Fengmeng:BAAANQADCggIEwAAAA==.',
Fi='Fishnchimps:BAAANQAECggJCwAAAA==.',
Fr='Fríeren:BAAANQAECgEIAQAAAA==.',
Fu='Fupalicious:BAAANQAECgUIEAAAAA==.',
Ga='Gaiserik:BAAANQAECgUJBgAAAA==.Garlictoast:BAAANQADCgYJBgAAAA==.',
Gi='Gillgamesh:BAAANQAECgQIBAAAAA==.',
Gr='Gracile:BAAANQADCggIEAAAAA==.Gragolf:BAAANQAECgYJCgAAAA==.Greggor:BAAANQAECgUICAAAAA==.Griffin:BAAANQADCggIDgAAAA==.Grippyfupa:BAAANQAECgQIBgAAAA==.',
Gu='Gulzerak:BAAANQAECgcIDgAAAA==.Gustabo:BAAANQADCgIIAgAAAA==.',
Ha='Hawtynaughty:BAAANQADCgYIBgAAAA==.',
He='Helcular:BAAANQADCggIFgAAAA==.Hexuz:BAAANQAECgcJEgAAAA==.',
Ho='Holyblunt:BAABNQAECoEfAAIFAAkKeiRdCACWAwAFAAkKeiRdCACWAwAAAA==.',
In='Inthezone:BAAANQAECgcIDQAAAA==.Invisus:BAAANQAECgUJBwAAAA==.',
Is='Ispayders:BAAANQAECgEIAQAAAA==.',
Ja='Jarlan:BAABNQAECoEiAAILAAkKwiDHFwAqAwALAAkKwiDHFwAqAwAAAA==.Jarlhun:BAAANQADCggIEgABNQAECgkJIgALAMIgAA==.Jarmon:BAAANQAECgQICgABNQAECgkJIgALAMIgAA==.',
Ju='Justin:BAAANQAECgcJDwAAAA==.',
Ka='Kattsumoto:BAABNQAECoEcAAMIAAgKnx9uBwDRAgAIAAgKnx9uBwDRAgAMAAQK6xitKgAWAQAAAA==.',
Ke='Ketharion:BAAANQAECgUIDgAAAA==.',
Kh='Khato:BAAANQAECgMJBQAAAA==.',
Ku='Kurazan:BAABNQAECoEdAAILAAkK/ByyKgDCAgALAAkK/ByyKgDCAgAAAA==.Kurisu:BAAANQAECgYIDQAAAA==.',
La='Lafaymignon:BAAANQABCgIIAgAAAA==.Lavabolter:BAAANQABCgIIAgAAAA==.Laîlyne:BAAANQAECgYIDwAAAA==.',
Le='Leo:BAAANQAECgYJCgAAAA==.Leone:BAAANQAECgQIBQAAAA==.',
Li='Lilath:BAAANQAECgEIAQAAAA==.',
Lo='Logical:BAAANQAECgcJEgAAAA==.',
Lu='Lute:BAABNQAECoEWAAIGAAcKihmYLQD1AQAGAAcKihmYLQD1AQAAAA==.',
['Lá']='Lárien:BAAANQAECgQIBgAAAA==.',
Ma='Manon:BAABNQAECoEdAAMNAAgKfQ5uRgDRAQANAAgKfQ5uRgDRAQAOAAYKMwaCfAAhAQAAAA==.Maxacry:BAAANQADCgIIAgAAAA==.',
Me='Meowmixx:BAAANQAECgEIAQAAAA==.',
Mi='Mischief:BAAANQADCgYICwAAAA==.',
Mo='Mortred:BAAANQAECgEIAQAAAA==.',
Mt='Mth:BAAANQAECgIIAgABNQAECggIGQAPAA0eAA==.',
Ni='Nickignomaj:BAAANQADCgcJBwABNQAECggJHgALAKsbAA==.Nisara:BAAANQAECgMIAwAAAA==.',
No='Norina:BAAANQADCgYIBgAAAA==.',
Om='Omantul:BAABNQAECoEVAAINAAYK/xmzTAC1AQANAAYK/xmzTAC1AQAAAA==.',
Oo='Oobie:BAAANQADCgYIBgAAAA==.',
Oz='Ozzthehunter:BAAANQADCgIIAgAAAA==.',
Pa='Pants:BAAANQADCggJEAAAAA==.',
Ph='Phizz:BAAANQADCggJCgABNQAFFAYIEwABAAEcAA==.',
Pl='Pllwprincess:BAAANQADCgIIAgAAAA==.',
Po='Poofty:BAAANQADCgUIBQAAAA==.',
Pr='Predator:BAACNQAFFIEOAAILAAUKMh4nBAD8AQALAAUKMh4nBAD8AQA1AAQKgScAAgsACQqyJlwBAO8DAAsACQqyJlwBAO8DAAAA.',
Pu='Puke:BAAANQAECgIJAwAAAA==.Purpledisco:BAAANQADCggICAABNQAECgYIEwACAAAAAA==.Purplepower:BAABNQAECoEbAAILAAgKyRlbQwBaAgALAAgKyRlbQwBaAgAAAA==.',
Pw='Pwincess:BAAANQAECgQIBAAAAA==.',
Qw='Qwelmo:BAAANQADCgEJAgAAAA==.',
Ro='Rolypoly:BAAANQAECgUJBQAAAA==.',
Ry='Ryø:BAAANQAECgYIDwAAAA==.',
Se='Seigler:BAAANQAECgMIBgAAAA==.Seraphym:BAAANQADCgUIBQAAAA==.',
Sh='Shaviji:BAAANQAECgYIBgAAAA==.Shigzen:BAAANQADCgUIBQABNQAECgYIDgACAAAAAA==.Shore:BAABNQAECoEZAAMPAAgKDR76AQDWAgAPAAgKDR76AQDWAgAQAAIKxA6aSwB2AAAAAA==.Shuralya:BAABNQAECoEcAAIFAAgKVyLMHAD+AgAFAAgKVyLMHAD+AgAAAA==.',
So='Sonofabirch:BAAANQADCgMIAwAAAA==.',
St='Striga:BAAANQABCgEIAQAAAA==.',
Su='Sully:BAAANQADCggIDgAAAA==.Survas:BAABNQAECoEaAAIRAAgKxhCWEgAjAgARAAgKxhCWEgAjAgAAAA==.',
Ta='Tavgoesboom:BAAANQAECgQIBQABNQAECggJCwACAAAAAA==.',
Te='Texmexdruid:BAAANQADCggIDgAAAA==.',
Th='Thunderlinkx:BAAANQAECgEIAQAAAA==.',
Ti='Titlecard:BAAANQADCgUIDwAAAA==.',
Tr='Triage:BAABNQAECoEVAAIBAAkKuhShXQB1AgABAAkKuhShXQB1AgAAAA==.',
Ts='Tsu:BAEANQADCgEIAQABNQAECgQJBgACAAAAAA==.',
Tu='Tul:BAAANQADCgUIBQAAAA==.',
Tw='Twotoedfupa:BAAANQADCggIGgABNQAECgUIEAACAAAAAA==.',
Ty='Tyrias:BAAANQAECggJCAAAAA==.',
Ug='Ugin:BAAANQAECgcIEgAAAA==.',
Um='Umbrasyl:BAAANQAECgIIAwAAAA==.',
Un='Unclecharlie:BAAANQADCgEJAQABNQAECggIFgAHAAEkAA==.Undeadrogue:BAAANQADCgQIBAAAAA==.',
Va='Vasrin:BAAANQAECgYICgAAAA==.',
Vo='Voidomo:BAAANQAECgYIDwAAAA==.Vonbearback:BAAANQADCgIIAwAAAA==.',
Wa='Waterlance:BAAANQADCggJEAAAAA==.',
Wh='Whatchashots:BAAANQADCggICAAAAA==.',
Wi='Wisecraic:BAAANQADCgYIDwAAAA==.',
Wo='Wocoxl:BAACNQAFFIELAAISAAUKjA0pAgCWAQASAAUKjA0pAgCWAQA1AAQKgSMAAxIACQrfHOkQAIMCABIACAq8HOkQAIMCABEACAozFqUUAAoCAAAA.',
Xe='Xendamo:BAAANQADCggIEAAAAA==.',
Ya='Yaracklea:BAAANQAECgIJAgAAAA==.',
Yi='Yinokiea:BAAANQAECgMIBgAAAA==.',
['Yü']='Yüki:BAAANQADCgIIAgAAAA==.',
Za='Zabaniya:BAAANQADCggJFAAAAA==.',
Ze='Zenedict:BAAANQAECgcIDwAAAA==.',
Zs='Zsofi:BAAANQAECgYIEAAAAA==.',
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
