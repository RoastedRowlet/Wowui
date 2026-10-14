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

local lookup = {'Mage-Frost','Monk-Brewmaster','Warlock-Demonology','Priest-Holy','Warrior-Fury','Mage-Arcane','Warlock-Destruction','Paladin-Holy','Paladin-Retribution','Paladin-Protection','Unknown-Unknown','Warlock-Affliction','DeathKnight-Blood','DeathKnight-Unholy','Druid-Balance','Druid-Guardian','Monk-Mistweaver','Hunter-Survival','Hunter-BeastMastery','Evoker-Preservation','Shaman-Enhancement','Hunter-Marksmanship','Warrior-Arms','Monk-Windwalker','Shaman-Elemental','Shaman-Restoration','Rogue-Assassination','DemonHunter-Vengeance','Priest-Shadow','Rogue-Subtlety','DeathKnight-Frost',}
local provider = {region='US',realm='Rivendare',name='US',type='weekly',zone=53,date='2026-10-13',data={Ad='Ado:BAAANQAECgMIAwABNQAFFAcIGAABAG8UAA==.',
Ae='Aela:BAAANQAECgEIAgABNQAECgkJLAACAEMiAA==.Aelin:BAAANQAECgQIBwAAAA==.',
Af='Affliction:BAAANQADCgEIAQAAAA==.',
Ai='Aimer:BAAANQAECgUIDAABNQAFFAcIGAABAG8UAA==.',
Al='Alkanz:BAABNQAECn8XAAIDAAcKjQpBpwCAAQADAAcKjQpBpwCAAQAAAA==.Allinaa:BAAANQAECgIIAwAAAA==.Alya:BAABNQAECn8wAAIEAAkKKRreLACyAgAEAAkKKRreLACyAgAAAA==.',
An='Anika:BAABNQAECn8bAAIFAAkK+wkPEQCSAQAFAAkK+wkPEQCSAQAAAA==.Anshi:BAAANQAECgQIBAABNQAECggIGwAGAEMXAA==.',
Ar='Archspìre:BAAANQAECgEIAgAAAA==.Arise:BAAANQADCgIIAgAAAA==.Arlyx:BAABNQAECn8dAAMDAAkK2RzKWwBAAgADAAcKdB/KWwBAAgAHAAUK0hZHJwA8AQAAAA==.Arnwaz:BAAANQAECgYIEQAAAA==.Arthuria:BAABNQAECn8XAAMIAAUKthKQqgAoAQAIAAUKthKQqgAoAQAJAAQKCxSYEwH4AAAAAA==.',
As='Ashfia:BAAANQAECgEIBQAAAA==.Ashmegan:BAAANQAECgEIBAAAAA==.Ashrom:BAAANQAECgEIBAAAAA==.Ashzazul:BAAANQAECgEIBAAAAA==.Ashzia:BAAANQAECgEIBAAAAA==.Asianverstop:BAAANQAECggIDwAAAA==.',
At='Atelwen:BAAANQADCgYJBgAAAA==.',
Ba='Baf:BAABNQAECn8qAAIJAAkK7SPsFwBjAwAJAAkK7SPsFwBjAwAAAA==.Banano:BAAANQAECgIIAgAAAA==.Banjodave:BAAANQAECggIDAAAAA==.',
Be='Berfomat:BAABNQAECn8hAAIKAAkKPyDMBwAiAwAKAAkKPyDMBwAiAwAAAA==.Berfsteals:BAAANQADCgIIBAAAAA==.Berfy:BAAANQADCggICgAAAA==.',
Bj='Bjorn:BAAANQAECgYICgAAAA==.',
Bl='Black:BAAANQADCggICgAAAA==.Blackky:BAAANQAECgEIAgAAAA==.Bloodyfupa:BAAANQADCgEIAQAAAA==.Bloomyvfd:BAAANQAECgQIDwAAAA==.',
Bo='Bocc:BAAANQADCgQIBQABNQAECgcIEAALAAAAAA==.Boombip:BAAANQAECgEIAQAAAA==.Boxxylove:BAAANQADCggIGgABNQAECgkJMAAEACkaAA==.',
Br='Brockz:BAAANQADCgQIBwAAAA==.Broxar:BAAANQAECgEIAQAAAA==.',
Bu='Bulldan:BAAANQABCgIIAQAAAA==.',
['Bî']='Bîa:BAABNQAECn8vAAIJAAgKHCOxKQAeAwAJAAgKHCOxKQAeAwAAAA==.',
Ca='Cavalis:BAABNQAECn8qAAQDAAkKzhQ3gADhAQADAAcKrBA3gADhAQAHAAMKrx2LNgDmAAAMAAMKWw8VGQC+AAAAAA==.',
Ce='Ceedk:BAACNQAFFH8JAAINAAUKIyFcDACKAQANAAUKIyFcDACKAQA1AAQKfyEAAw4ACQrIJpERACkDAA4ACQrIJpERACkDAA0ABwrYITAsAGUCAAE1AAUUBwgWAA8A9CEA.Ceesh:BAAANQAECggIBwABNQAFFAcIFgAPAPQhAA==.',
Ch='Chickenparm:BAAANQAECgIIAgAAAA==.Chll:BAAANQAECgIIAgABNQAECgkJJQAOABoiAA==.',
Ci='Citizenmagi:BAAANQAECgEIAQAAAA==.',
Cj='Cjjackpot:BAAANQADCgYJCwAAAA==.',
Co='Cobb:BAAANQAECgcIEAAAAA==.Coorsbanquet:BAAANQADCgMIAwAAAA==.',
Cr='Creativezd:BAABNQAFFH8WAAMPAAcK9CG7AwB7AgAPAAcKjB67AwB7AgAQAAUKXSIlAQDsAQAAAA==.Crowley:BAAANQAECgMIDQAAAA==.',
Da='Dadgoo:BAAANQAECgYIDQAAAA==.Damnskippy:BAAANQAECgUIBgAAAA==.Dannÿ:BAAANQAECgUIEwAAAA==.Darkire:BAAANQAECgQIEQAAAA==.',
De='Deathroll:BAABNQAECn8lAAIRAAkKVxSfFAAuAgARAAkKVxSfFAAuAgAAAA==.Deaux:BAAANQAECggICgAAAA==.Demosucc:BAACNQAFFH8TAAMDAAUKCB4xEACFAQADAAQKuSExEACFAQAHAAEKphZqGQBSAAA1AAQKfxkAAwMACQr1IkQgAAADAAMACAq1I0QgAAADAAcAAQp3HlltAEMAAAAA.',
Di='Diabolic:BAAANQAECgUIBQAAAA==.',
Dk='Dkchilly:BAABNQAECn8lAAIOAAkKGiIJIADJAgAOAAkKGiIJIADJAgAAAA==.',
Do='Doomward:BAAANQAECgEIAwAAAA==.Dorien:BAABNQAECn8oAAMSAAkKnRrzAgDyAgASAAkKXBjzAgDyAgATAAgKFxrRXgBXAgAAAA==.',
['Då']='Dårk:BAAANQADCgEIAQAAAA==.',
El='Elysele:BAAANQADCgUIBQABNQAECgkJKgAEAMMPAA==.',
Er='Erale:BAAANQAECgcIDwAAAA==.',
Fa='Faewryn:BAABNQAECn8XAAIIAAcKchwFSwA6AgAIAAcKchwFSwA6AgAAAA==.Falekia:BAAANQAECgcICwAAAA==.Falnaz:BAAANQAECgIIAwAAAA==.Fay:BAABNQAECn8sAAICAAkKQyLVAwBIAwACAAkKQyLVAwBIAwAAAA==.',
Fe='Fellus:BAAANQADCgIIAgAAAA==.Fengmeng:BAAANQADCggIEwAAAA==.',
Fi='Fishnchimps:BAAANQAECggIDwAAAA==.',
Fr='Freezah:BAAANQADCgIIAgAAAA==.Fríeren:BAAANQAECgYIEAAAAA==.',
Fu='Fupalicious:BAAANQAECgUIEgABNQAECgUIEgALAAAAAA==.',
Ga='Gaiserik:BAAANQAECgcIDQAAAA==.Galad:BAAANQAECggICQAAAA==.Garlictoast:BAAANQADCgYJBgAAAA==.',
Gi='Gillgamesh:BAAANQAECgcICwAAAA==.',
Go='Goochegg:BAAANQADCgUIBQAAAA==.',
Gr='Gracile:BAAANQAECgEIAQAAAA==.Gragolf:BAAANQAECgcICwAAAA==.Greggor:BAAANQAECgUICQAAAA==.Griffin:BAAANQADCggIDgAAAA==.Grippyfupa:BAAANQAECgQICAAAAA==.',
Gu='Gulzerak:BAAANQAFFAQIBAABNQAFFAYIFgAUACohAA==.Gustabo:BAAANQADCgIIAgAAAA==.',
Ha='Hawtynaughty:BAAANQADCgYIBgAAAA==.',
He='Helcular:BAAANQAECgYIEAAAAA==.Hexuz:BAABNQAECn8dAAIVAAkK4RCKDgCBAgAVAAkK4RCKDgCBAgAAAA==.',
Ho='Holyblunt:BAACNQAFFH8IAAIJAAMKDR8HFgD3AAAJAAMKDR8HFgD3AAA1AAQKfysAAgkACQqrJWcQAIcDAAkACQqrJWcQAIcDAAAA.Hotboydragon:BAAANQAECgcIBwABNQAECggIDwALAAAAAA==.',
Id='Idk:BAAANQAECgcICgAAAA==.',
In='Inthezone:BAABNQAECn8UAAMTAAcKAxLajgDoAQATAAcKAxLajgDoAQAWAAUKEAZdUgDaAAAAAA==.Invisus:BAAANQAECgYIEwAAAA==.',
Is='Ispayders:BAAANQAECgEIAQAAAA==.',
Ja='Jarlan:BAABNQAECn8qAAIXAAkKzSFsMQD3AgAXAAkKzSFsMQD3AgAAAA==.Jarlhun:BAAANQAECgEIAQABNQAECgkJKgAXAM0hAA==.Jarmon:BAABNQAECn8ZAAIYAAYK4x+MIwAGAgAYAAYK4x+MIwAGAgABNQAECgkJKgAXAM0hAA==.',
Ju='Justin:BAABNQAECn8nAAINAAkKAhgHLQBgAgANAAkKAhgHLQBgAgAAAA==.',
Ka='Katakuri:BAAANQAECgMIAwAAAA==.Kattsumoto:BAABNQAECn8pAAMRAAkKMyIxBQBOAwARAAkKMyIxBQBOAwAYAAQKHhosRQDsAAAAAA==.',
Ke='Ketharion:BAABNQAECn8mAAMIAAgKcBTnXwD2AQAIAAgKcBTnXwD2AQAJAAUKgAlZEgH6AAAAAA==.',
Kh='Khato:BAAANQAECgMICgAAAA==.',
Ku='Kurazan:BAACNQAFFH8IAAIXAAMKOx4eHwAHAQAXAAMKOx4eHwAHAQA1AAQKfyYAAhcACQqEH55BAMICABcACQqEH55BAMICAAAA.Kurisu:BAABNQAECn8gAAIDAAcK4w2EmwCcAQADAAcK4w2EmwCcAQAAAA==.',
La='Lafaymignon:BAAANQABCgIIAgAAAA==.Lavabolter:BAAANQAECgEIAQAAAA==.Laîlyne:BAABNQAECn8XAAIZAAcKHhIjcADMAQAZAAcKHhIjcADMAQAAAA==.',
Le='Leo:BAAANQAECgcICwAAAA==.Leone:BAAANQAECgYIDwAAAA==.',
Li='Lilath:BAAANQAECgEIAgAAAA==.',
Lo='Logical:BAABNQAECn8eAAIJAAgK/xVmiAARAgAJAAgK/xVmiAARAgAAAA==.',
Lu='Lute:BAABNQAECn8mAAINAAgK8BwCIQCqAgANAAgK8BwCIQCqAgAAAA==.',
['Lá']='Lárien:BAAANQAECgQIBwAAAA==.',
Ma='Manon:BAABNQAECn8oAAMaAAkK8w7AYQDlAQAaAAkK8w7AYQDlAQAZAAgKKwc+lgBpAQAAAA==.Maxacry:BAAANQADCgIIAgAAAA==.',
Mc='Mcchungus:BAAANQAECgQIBAAAAA==.',
Me='Meowmixx:BAAANQAECgEIAQAAAA==.',
Mi='Mischief:BAAANQADCgYICwAAAA==.',
Mo='Morewyn:BAAANQADCggICAAAAA==.Mortred:BAAANQAECgEIAQAAAA==.',
Mt='Mtd:BAAANQADCggICAABNQAECgkJNgASALEfAA==.Mth:BAABNQAECn8WAAMSAAcK/xdPBgA2AgASAAcK/xdPBgA2AgAWAAUKigoVTAD+AAABNQAECgkJNgASALEfAA==.',
Na='Naz:BAAANQAECgIIAgAAAA==.',
Ni='Nickignomaj:BAAANQAECgUIBgABNQAECgkJJgAXAJIcAA==.Nisara:BAAANQAECgMIBAAAAA==.',
No='Norina:BAAANQADCgYIBgAAAA==.',
Ob='Obv:BAAANQAECggIEAAAAA==.',
Om='Omantul:BAABNQAECn8cAAIaAAcKMBkgWwD7AQAaAAcKMBkgWwD7AQAAAA==.',
Oo='Oobie:BAAANQADCgYIBgAAAA==.',
Ow='Owocoxl:BAAANQAECgIIAgABNQAFFAcIGwAbAGESAA==.',
Oz='Ozziee:BAAANQAECgMIBwAAAA==.Ozzthehunter:BAAANQADCgIIAgAAAA==.',
Pa='Pants:BAAANQADCggIGQAAAA==.',
Ph='Phakes:BAAANQAECgUIBQAAAA==.Phengzera:BAAANQADCgcIBwAAAA==.Phizz:BAAANQADCggICgABNQAFFAcIIgAGALkeAA==.',
Pl='Pllwprincess:BAAANQADCgIIAgAAAA==.',
Po='Poofty:BAAANQADCgUIBQAAAA==.',
Pr='Predator:BAACNQAFFH8bAAIXAAcKgiZlAQD/AgAXAAcKgiZlAQD/AgA1AAQKfzQAAhcACQqzJtYDANkDABcACQqzJtYDANkDAAAA.',
Pu='Puke:BAABNQAECn8ZAAIcAAgKriTaAgBGAwAcAAgKriTaAgBGAwAAAA==.Purpledisco:BAAANQADCggICAABNQAECgkJMAAEACkaAA==.Purplepower:BAABNQAECn8iAAIXAAgKoRnXcgA4AgAXAAgKoRnXcgA4AgAAAA==.',
Pw='Pwincess:BAAANQAECgQIBAAAAA==.',
Qw='Qwelmo:BAAANQADCgEJAgAAAA==.',
Ri='Rigaud:BAAANQADCgMIAwAAAA==.',
Ro='Roaka:BAAANQAECgEIAQAAAA==.Rolypoly:BAAANQAECgUIBQAAAA==.',
Ry='Ryaine:BAAANQAECgEIAQAAAA==.Ryø:BAABNQAECn8XAAIQAAcKJhjfGgDIAQAQAAcKJhjfGgDIAQAAAA==.',
Se='Seigler:BAABNQAECn8ZAAISAAcK0QynCAC+AQASAAcK0QynCAC+AQAAAA==.Senne:BAAANQAECgIIAgAAAA==.Seraphym:BAAANQADCgUIBQAAAA==.',
Sh='Shaviji:BAAANQAECgcIDgAAAA==.Shigzen:BAAANQAECgIIAwABNQAECgkJGQAdANYUAA==.Shore:BAABNQAECn82AAMSAAkKsR9EAQBoAwASAAkKmR9EAQBoAwAWAAMK5A2DYQCeAAAAAA==.Shuralya:BAABNQAECn83AAIJAAkKXiNGFQBuAwAJAAkKXiNGFQBuAwAAAA==.',
Sk='Skoob:BAAANQAECgMIAwAAAA==.',
So='Sonofabirch:BAAANQADCgMIAwAAAA==.',
St='Striga:BAAANQABCgEIAQAAAA==.',
Su='Sully:BAAANQADCggIDgAAAA==.Survas:BAABNQAECn8mAAIeAAkK0BIeEwBRAgAeAAkK0BIeEwBRAgAAAA==.',
Ta='Tavgoesboom:BAAANQAECgQICAABNQAECggIDwALAAAAAA==.Tazee:BAAANQAECgUIBgABNQAECgkJIQAIAC8jAA==.',
Te='Terrin:BAAANQAECgcIDQAAAA==.Texmexdruid:BAAANQADCggIDgAAAA==.',
Th='Tharkun:BAAANQAECgYIEwAAAA==.Thunderlinkx:BAAANQAECgEIAgABNQAECgcIDwALAAAAAA==.',
Ti='Titlecard:BAAANQAECgEIAgAAAA==.',
Tr='Triage:BAABNQAECn8bAAIGAAkK2BiilABWAgAGAAkK2BiilABWAgAAAA==.',
Ts='Tsu:BAEANQADCgEIAQABNQAECgUIEwALAAAAAA==.Tsuko:BAEANQADCgEIAQABNQAECgUIEwALAAAAAA==.',
Tu='Tul:BAAANQAECggIDQAAAA==.',
Tw='Twotoedfupa:BAAANQAECgUIEgAAAA==.',
Ty='Tyrias:BAABNQAECn8dAAIJAAgK7gMUfAFXAAAJAAgK7gMUfAFXAAAAAA==.',
Ug='Ugin:BAABNQAECn8bAAMOAAkKWAybUwDAAQAOAAkKJwybUwDAAQAfAAMKJArbhACTAAAAAA==.',
Um='Umbrasyl:BAAANQAECgIIBAAAAA==.',
Un='Unclecharlie:BAAANQAECgQIBQABNQAECgkJIAAOAF0lAA==.Undeadrogue:BAAANQADCgQIBAAAAA==.',
Va='Vasrin:BAABNQAECn8gAAIVAAkKFyEfBgAjAwAVAAkKFyEfBgAjAwAAAA==.',
Vo='Voidomo:BAABNQAECn8qAAQMAAgKGxkfBgBQAgAMAAgKKxcfBgBQAgADAAYKaA06rgBvAQAHAAMKNxtVPADPAAAAAA==.Vonbearback:BAAANQADCgIIAwAAAA==.',
Wa='Waterlance:BAAANQAECgEIAQAAAA==.',
Wh='Whatchashots:BAAANQADCggICAAAAA==.',
Wi='Wisecraic:BAAANQAECgEIBAAAAA==.',
Wo='Wocoxl:BAACNQAFFH8bAAIbAAcKYRISAwA3AgAbAAcKYRISAwA3AgA1AAQKfysAAxsACQocHrojAGUCABsACAocHrojAGUCAB4ACAp2FXkeANoBAAAA.',
Wu='Wutank:BAAANQADCgMIAwAAAA==.',
Xe='Xendamo:BAAANQADCggIEAAAAA==.',
Ya='Yaracklea:BAAANQAECgQIDAAAAA==.',
Yi='Yinokiea:BAAANQAECgMIBgAAAA==.',
['Yü']='Yüki:BAAANQADCgIIAgAAAA==.',
Za='Zabaniya:BAAANQADCggIHQAAAA==.',
Ze='Zenedict:BAAANQAECgcIEgAAAA==.',
Zs='Zsofi:BAABNQAECn8lAAIEAAkKZRwlJwDLAgAEAAkKZRwlJwDLAgAAAA==.',
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
