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

local lookup = {'Warrior-Arms','Priest-Holy','Shaman-Restoration','DeathKnight-Blood','Monk-Mistweaver','Warlock-Demonology','DeathKnight-Frost','Paladin-Holy','Paladin-Retribution','Warlock-Affliction','Warlock-Destruction','Warrior-Protection','Rogue-Subtlety','Rogue-Outlaw','Monk-Windwalker','Priest-Shadow','Druid-Guardian','Shaman-Elemental','Hunter-Survival','Paladin-Protection','Druid-Feral','Hunter-BeastMastery','Mage-Arcane','Unknown-Unknown','Warrior-Fury','Hunter-Marksmanship','Druid-Balance','DemonHunter-Devourer','Shaman-Enhancement','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster',}
local provider = {region='US',realm='Maelstrom',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Absydion:BAAANQAECgYICgAAAA==.',
Ae='Aelion:BAAANQAECgIIAwABNQAECggIGAABAIMcAA==.',
An='Anegos:BAAANQADCggIDwABNQAFFAUIBwACACUMAA==.Anyliea:BAAANQAECgIIAgAAAA==.',
Ar='Arwenah:BAAANQAECgYIEQAAAA==.',
As='Asahhealer:BAABNQAECn8qAAIDAAkKHxcpPQBoAgADAAkKHxcpPQBoAgAAAA==.Astridd:BAABNQAECn8eAAIEAAkKwCETDABQAwAEAAkKwCETDABQAwAAAA==.Aszcuul:BAAANQADCgEIAQABNQAECggIHgAFAKYcAA==.',
Au='Aurorabelli:BAAANQAECgYIDAAAAA==.Auróra:BAABNQAECn8hAAIGAAkKEyEPFQA1AwAGAAkKEyEPFQA1AwAAAA==.',
Av='Averlence:BAAANQAECgQICAAAAA==.',
Aw='Awriya:BAAANQABCgIIAgAAAA==.',
Ba='Bahumn:BAAANQAECgQIBQABNQAECgkJFQAHAAoXAA==.Batteryacid:BAAANQADCggICQAAAA==.',
Be='Bergles:BAABNQAECn8qAAMIAAkKqBf8PgBmAgAIAAkKqBf8PgBmAgAJAAgKARsUaQBdAgAAAA==.',
Bi='Bigtee:BAAANQADCgIJAgAAAA==.',
Bo='Bonitoflakes:BAAANQADCgQIBAAAAA==.Bonnieblüe:BAAANQAECggIBQAAAA==.Bopeep:BAAANQADCgcICAAAAA==.',
Br='Brekta:BAAANQADCggIEAAAAA==.',
Bu='Bullshiza:BAAANQABCgUIBQAAAA==.Burningfel:BAABNQAECn8qAAQKAAgK5BXDBwAZAgAKAAgKRRTDBwAZAgALAAcKlBONEwDTAQAGAAIKhAuDJQFsAAAAAA==.',
Ca='Calihye:BAAANQAECgEIAQABNQAFFAYIFgAFAOohAA==.Camel:BAABNQAECn8bAAMJAAYKDguy9wAoAQAJAAYKDguy9wAoAQAIAAMKPwOH/gB3AAAAAA==.Cattlestance:BAABNQAECn8mAAIMAAkKtxMJEgACAgAMAAkKtxMJEgACAgAAAA==.',
Ce='Ceriebrium:BAAANQAECgEIAQAAAA==.',
Co='Coldphyre:BAAANQAECgIIAwAAAA==.',
Da='Dakka:BAAANQADCgcICwAAAA==.Damnedsuen:BAAANQAECgMICQAAAA==.Dashdashdash:BAAANQAECgUIEAAAAA==.',
De='Deceiverdave:BAAANQADCgEIAQAAAA==.Derazen:BAAANQADCgYIBgAAAA==.Destyne:BAAANQAECgIIAwAAAA==.',
Di='Dixonfire:BAAANQADCgEIAQAAAA==.',
Dj='Dj:BAABNQAECn8iAAMNAAgKTxm/FgAoAgANAAgK8xe/FgAoAgAOAAcK/Rb2CAACAgABNQAFFAQICAAPAHMQAA==.',
Do='Dodgydave:BAAANQAECgQIBAAAAA==.Doomzeer:BAABNQAECn8YAAIQAAkKaRu3EgDTAgAQAAkKaRu3EgDTAgAAAA==.',
Dr='Drakarys:BAAANQAECgQIBQAAAA==.Drezlek:BAAANQADCgcICwAAAA==.Drezz:BAAANQADCggIFgAAAA==.Dràgøn:BAAANQAECggIAgAAAA==.',
Du='Durkanis:BAABNQAECn8pAAIRAAkKaCLnBABRAwARAAkKaCLnBABRAwAAAA==.',
El='Eleesa:BAAANQAECgUICwAAAA==.Element:BAAANQAECgYIEwAAAA==.',
Em='Emi:BAABNQAECn8bAAMDAAkKkx76IgDZAgADAAkKkx76IgDZAgASAAQK8BL21gDiAAAAAA==.',
Ex='Exury:BAACNQAFFH8GAAISAAIKgBinHgC5AAASAAIKgBinHgC5AAA1AAQKfxkAAhIACQq5HrgpANcCABIACQq5HrgpANcCAAAA.',
Fa='Faelin:BAAANQADCgYIBAAAAA==.',
Fe='Felenus:BAAANQAECgEJAQAAAA==.Fenrir:BAAANQAECgQIBQAAAA==.',
Fi='Fir:BAABNQAECn8qAAIDAAkKyR6dHQD0AgADAAkKyR6dHQD0AgAAAA==.',
Fl='Floknidemon:BAABNQAECn8qAAIDAAgK5g6LcQCzAQADAAgK5g6LcQCzAQAAAA==.',
Fo='Forthrich:BAABNQAECn8kAAIJAAgKrAtOtQCuAQAJAAgKrAtOtQCuAQAAAA==.Fozuul:BAAANQAECggICgABNQAECggIHgAFAKYcAA==.',
Fr='Fredò:BAABNQAECn8oAAIPAAkKxh4OEQDWAgAPAAkKxh4OEQDWAgAAAA==.Frozono:BAAANQAECgUIBgAAAA==.Frâust:BAAANQAECgYIEAAAAA==.',
Ga='Galadril:BAAANQAECgEIAQAAAA==.Gandulf:BAAANQADCgUIBQAAAA==.Garriott:BAAANQADCgYIDAAAAA==.Gawkin:BAABNQAECn8pAAMIAAkK8CJjCQB8AwAIAAkK8CJjCQB8AwAJAAEKmh8begFaAAAAAA==.',
Ge='Geodude:BAAANQADCgUIBQAAAA==.',
Go='Goaty:BAAANQAECgEIAgAAAA==.',
Gr='Grimspear:BAABNQAECn8qAAITAAkKgB1wAgAUAwATAAkKgB1wAgAUAwAAAA==.',
Gu='Gumbercules:BAAANQAECgQICgAAAA==.Gurnsey:BAAANQADCgQIBAAAAA==.',
['Gæ']='Gæa:BAAANQAECgYIBwAAAA==.',
Ha='Halogirl:BAAANQAECgYIEAAAAA==.Haters:BAAANQADCgIIAgAAAA==.',
He='Heelorestus:BAABNQAECn8fAAMQAAgKvhN3JwDsAQAQAAgKvhN3JwDsAQACAAQKJAWx1QCeAAAAAA==.Hellbreed:BAAANQADCgIIAgAAAA==.',
Ho='Holix:BAAANQADCgEIAQAAAA==.Holyfrog:BAABNQAECn8wAAIIAAkKChXSPgBnAgAIAAkKChXSPgBnAgAAAA==.Holythis:BAABNQAECn8yAAIUAAkKjxwrEACYAgAUAAkKjxwrEACYAgAAAA==.',
If='Ifrit:BAAANQAECgcIBQAAAA==.',
Ig='Ignis:BAABNQAECn8pAAMVAAgKqA8rFwCBAQAVAAcKLA4rFwCBAQARAAgKQA2aJQBjAQAAAA==.',
In='Infiltrata:BAABNQAECn8rAAINAAgKkxz1EABuAgANAAgKkxz1EABuAgAAAA==.Injunjoe:BAAANQAECgQIBAAAAA==.',
Io='Io:BAABNQAECn8dAAIEAAkKWCMsDABQAwAEAAkKWCMsDABQAwAAAA==.',
Is='Ishida:BAAANQABCggIEQAAAA==.',
Ja='Janelik:BAAANQAECgUIDAAAAA==.',
Ji='Jimihendrix:BAAANQADCgYJDgAAAA==.',
Jo='Jofixit:BAABNQAECn8rAAIWAAgKMRzbSACQAgAWAAgKMRzbSACQAgAAAA==.',
Ju='Judgemedaddy:BAAANQAECgEIAQAAAA==.',
Ka='Kanda:BAAANQAFFAIIAgAAAA==.Kasunas:BAABNQAECn8oAAIJAAkKfRiQTgClAgAJAAkKfRiQTgClAgAAAA==.Kaynub:BAAANQAECgEIAQABNQAECgkJMQAXACsgAA==.',
Ke='Kealthas:BAAANQAECgYIDgAAAA==.Kedri:BAABNQAECn81AAIWAAkKrhSjTACGAgAWAAkKrhSjTACGAgAAAA==.Keihas:BAAANQAECgYIDgAAAA==.Kermitt:BAAANQAECgMIAwAAAA==.',
Ki='Kikko:BAACNQAFFH8IAAISAAMKixzZFgAJAQASAAMKixzZFgAJAQA1AAQKfyYAAhIACQppJGQcAB4DABIACQppJGQcAB4DAAAA.Kikkomouse:BAAANQAECgUICAABNQAFFAMICAASAIscAA==.',
Ko='Kobane:BAAANQAECgEIAQAAAA==.',
Ku='Kujara:BAAANQADCgMIAwAAAA==.Kurando:BAAANQAECggICAABNQAECgkJKAAJAH0YAA==.Kurrindor:BAABNQAECn8eAAMUAAgK6B+JEACUAgAUAAgK6B+JEACUAgAJAAEKIR6hfQFVAAAAAA==.',
Ly='Lylith:BAAANQADCggIFAAAAA==.',
Ma='Macheon:BAAANQAECgEIAQAAAA==.Madashell:BAAANQADCgcIDAAAAA==.Maerwyn:BAAANQADCggJDQAAAA==.Magenub:BAABNQAECn8xAAIXAAkKKyDrMwAiAwAXAAkKKyDrMwAiAwAAAA==.Malexling:BAABNQAECn8aAAIJAAYKJRYFxwCIAQAJAAYKJRYFxwCIAQAAAA==.Masa:BAABNQAECn8iAAIMAAkKxh3XBgDxAgAMAAkKxh3XBgDxAgAAAA==.Mawe:BAAANQAECgEJAgAAAA==.',
Mi='Mistie:BAAANQABCgIIAgABNQAECgUJDAAYAAAAAA==.Mistlee:BAAANQAECgEIAgAAAA==.Mitternacht:BAABNQAECn89AAISAAkK6xwjIwD5AgASAAkK6xwjIwD5AgAAAA==.',
Mo='Moggo:BAAANQADCgQIBwAAAA==.Moodew:BAABNQAECn8eAAIDAAcKEBWHawDFAQADAAcKEBWHawDFAQAAAA==.',
Ms='Msdeath:BAABNQAECn8bAAIRAAYK5R/mFAASAgARAAYK5R/mFAASAgAAAA==.',
My='Mya:BAAANQABCgQIBwAAAA==.Mykeroni:BAAANQADCgMIAwAAAA==.Myraku:BAAANQADCggIDAABNQAECgUIEgAYAAAAAA==.',
Na='Nachiko:BAAANQADCgMIAwAAAA==.Naois:BAAANQAECgQICQABNQAECgkJKAAJAH0YAA==.Nashalion:BAABNQAECn8VAAMHAAkKChf4JABnAgAHAAkKChf4JABnAgAEAAEK8gE24wAZAAAAAA==.',
Ni='Nickchurch:BAAANQAECgIIAgAAAA==.Nidorhina:BAAANQABCgQIAwAAAA==.',
No='Nodarf:BAABNQAECn8lAAIZAAgK8g7cDgC9AQAZAAgK8g7cDgC9AQAAAA==.Norielin:BAAANQADCgQIBwAAAA==.',
Ok='Okayheals:BAABNQAECn8qAAIDAAgKwgvYgACFAQADAAgKwgvYgACFAQAAAA==.',
Ol='Olumine:BAAANQAECgEIAQAAAA==.',
Or='Orin:BAAANQADCgUIBgAAAA==.',
Pa='Panda:BAACNQAFFH8YAAQWAAcKch18DgBoAQATAAQKLR3OAAB6AQAWAAQKkRp8DgBoAQAaAAMKOA1hFgDUAAA1AAQKfzIABBoACQqNJJgZAIcCABMABwrdJH8EAJoCABoACAqHIZgZAIcCABYACQqtHqFNAIMCAAAA.',
Pi='Picolás:BAABNQAECn8ZAAIXAAYKHBhN6QC0AQAXAAYKHBhN6QC0AQAAAA==.',
Pr='Preacharound:BAAANQABCgMIAwAAAA==.Primrose:BAABNQAECn8cAAICAAkKTxq4NwCGAgACAAkKTxq4NwCGAgAAAA==.Probono:BAAANQAECgUIDQAAAA==.',
Qu='Quarian:BAAANQADCggICAAAAA==.',
Qw='Qwing:BAAANQAECgQIBQABNQAECgkJFQAHAAoXAA==.',
Ra='Rainee:BAAANQADCgQIAwAAAA==.Raxefal:BAABNQAECn8bAAQLAAcKHQ6PRwCoAAAGAAYKDwvpwABFAQALAAMKjgmPRwCoAAAKAAIKMhDNHgCAAAAAAA==.',
Re='Reptar:BAAANQAECgYICgABNQAFFAYIGQAbABQcAA==.Rezø:BAABNQAECn8kAAMCAAkKDBRrPQBxAgACAAkKDBRrPQBxAgAQAAcKgxUdKgDTAQAAAA==.',
Ro='Roadkilldk:BAAANQAECgcIEgAAAA==.',
['Rä']='Rägæ:BAAANQADCgYICAAAAA==.',
Sa='Sableye:BAABNQAECn8oAAIcAAkKGxl3FQC2AgAcAAkKGxl3FQC2AgAAAA==.Saguero:BAEBNQAECn8pAAMDAAkKeBiVPABrAgADAAkKeBiVPABrAgASAAgK2RB4ZwDmAQAAAA==.Satmorii:BAAANQABCggIDwAAAA==.',
Sc='Schatten:BAAANQADCgYIBgABNQAECgcIEwAYAAAAAA==.Schithappens:BAAANQABCgMIAwAAAA==.Scruffy:BAAANQAECgEIAQAAAA==.',
Se='Selina:BAAANQAECgcIDQAAAA==.Senortickle:BAAANQAECggICgAAAA==.',
Sh='Shaunara:BAAANQAECgEIAQABNQAECgkJHgAEAMAhAA==.Shinoitamis:BAAANQAECggICgABNQAECgkJPgAJAIUfAA==.Shinotenshi:BAABNQAECn8+AAIJAAkKhR+JIwA1AwAJAAkKhR+JIwA1AwAAAA==.Shìva:BAAANQADCggICAAAAA==.Shînon:BAAANQAECgMIAwABNQAECgkJJAACAAwUAA==.',
Si='Siphin:BAAANQAECggICQAAAA==.',
So='Solàire:BAABNQAECn8lAAMIAAgKkgrjfQCcAQAIAAgKkgrjfQCcAQAJAAIKWQaZfwFSAAAAAA==.Sonicice:BAAANQADCgQIAQAAAA==.',
Sp='Spacewafflez:BAAANQAECgEIAQAAAA==.',
St='Starburnz:BAAANQADCgMIAwABNQAECggIHgAFAKYcAA==.Stimutax:BAAANQAECgIIAwAAAA==.',
Ta='Tamborine:BAAANQADCgIIAgAAAA==.Taurenvar:BAABNQAECn8vAAIdAAkKOiIrAgCMAwAdAAkKOiIrAgCMAwAAAA==.',
Th='Thekeres:BAAANQAECgMIAwAAAA==.',
To='Tora:BAAANQAECgYJBgAAAA==.',
Tr='Trollbrudda:BAABNQAECn86AAMbAAkKkCA5DgBXAwAbAAkKkCA5DgBXAwARAAMKuBc4PgC9AAAAAA==.',
Um='Umgross:BAAANQADCgYIBgAAAA==.',
Un='Unholygrudge:BAAANQADCgIIAgAAAA==.',
Ve='Velenus:BAAANQAECgEIAQAAAA==.Vesperion:BAAANQADCgQICgAAAA==.',
Vi='Vickdak:BAAANQABCgUIBgAAAA==.Vilehatred:BAAANQAECgIIAwAAAA==.',
Vo='Voltz:BAAANQADCggIEAAAAA==.',
Wa='Wallis:BAAANQAECgUIBgAAAA==.Warmoz:BAAANQAECgcIEwAAAA==.',
Wu='Wunhunglo:BAAANQABCgQIBAAAAA==.',
Xe='Xergiator:BAABNQAECn8jAAIWAAcKCgn2uACNAQAWAAcKCgn2uACNAQAAAA==.',
Za='Zaligator:BAABNQAECn8gAAMeAAcKUxWfDACGAQAfAAcKGRRWGADBAQAeAAcKvBGfDACGAQAAAA==.Zarideyne:BAAANQAECgEIAQAAAA==.',
Zo='Zombinized:BAAANQADCgUIBQAAAA==.',
Zu='Zuulian:BAABNQAECn8eAAQFAAgKphzuEQBaAgAFAAgKphzuEQBaAgAgAAEKAAA1NAAkAAAPAAEKAAAbcwAkAAAAAA==.',
Zy='Zylph:BAAANQAECgUIEgAAAA==.',
['Ín']='Ínnothule:BAAANQAECgMIAwAAAA==.',
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
