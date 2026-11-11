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

local lookup = {'DeathKnight-Frost','Warrior-Arms','Priest-Holy','Shaman-Restoration','DeathKnight-Blood','Monk-Mistweaver','Shaman-Elemental','Warlock-Demonology','Paladin-Holy','Paladin-Retribution','Rogue-Subtlety','Warlock-Destruction','Warlock-Affliction','Warrior-Protection','DeathKnight-Unholy','DemonHunter-Havoc','Rogue-Outlaw','Monk-Windwalker','Priest-Shadow','Druid-Guardian','Hunter-Survival','Priest-Discipline','Paladin-Protection','Druid-Feral','Mage-Frost','Hunter-BeastMastery','Mage-Arcane','Evoker-Devastation','Unknown-Unknown','Warrior-Fury','Hunter-Marksmanship','Druid-Balance','DemonHunter-Devourer','Shaman-Enhancement','Druid-Restoration','Evoker-Augmentation','Evoker-Preservation','Monk-Brewmaster',}
local provider = {region='US',realm='Maelstrom',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Absydion:BAAANQAECggICwAAAA==.',
Ad='Adema:BAAANQADCgYICAABNQAECgoKMQABAPcVAA==.',
Ae='Aelion:BAAANQAECgIIAwABNQAECgkJGgACALAcAA==.',
An='Anegos:BAAANQADCggIDwABNQAFFAUIBwADACUMAA==.Anyliea:BAAANQAECgIIAgAAAA==.',
Ar='Arwenah:BAABNQAECn8mAAIEAAkK9g4mXwCEAQAEAAkK9g4mXwCEAQAAAA==.',
As='Asahhealer:BAABNQAECn87AAIEAAoK7xnrPQBoAgAEAAoK7xnrPQBoAgAAAA==.Astridd:BAACNQAFFH8OAAIFAAQKDiFSDQAQAQAFAAQKDiFSDQAQAQA1AAQKfy8AAgUACgotJL0EADYDAAUACgotJL0EADYDAAAA.Aszcuul:BAAANQADCgEIAQABNQAECgoKLQAGAM4aAA==.',
Au='Aurorabelli:BAABNQAECn8XAAMHAAkKbwfsbAAqAQAHAAkKbwfsbAAqAQAEAAYK+QfLuwDzAAAAAA==.Auróra:BAABNQAECn8vAAIIAAoKGiGkFQA0AwAIAAoKGiGkFQA0AwAAAA==.',
Av='Averlence:BAAANQAECgQICwAAAA==.',
Aw='Awriya:BAAANQABCgIIAgAAAA==.',
Ba='Bahumn:BAAANQAECggIDAABNQAECgoKMQABAPcVAA==.Batteryacid:BAAANQAECgcICQAAAA==.',
Be='Bergles:BAABNQAECn9DAAMJAAoK/hp2PwBnAgAJAAoK/hp2PwBnAgAKAAoKvRs9UwAiAgAAAA==.',
Bi='Bigtee:BAAANQADCgcICQAAAA==.',
Bo='Bonitoflakes:BAAANQADCgQIBAAAAA==.Bonnieblüe:BAACNQAFFH8JAAILAAQKbAJJGQCfAAALAAQKbAJJGQCfAAA1AAQKfy8AAgsACQqUCipTAJsBAAsACQqUCipTAJsBAAAA.Bopeep:BAAANQADCgcICAAAAA==.',
Br='Brekta:BAAANQADCggIEAAAAA==.Brewwizard:BAAANQAECgUICgABNQAECgoKLgAGAGARAA==.',
Bu='Bullshiza:BAAANQABCgUIBwAAAA==.Burningfel:BAABNQAECn9EAAQMAAoKqhUQBQCZAQANAAgKRRTYBwAZAgAMAAkKNRUQBQCZAQAIAAkKwAzoagCDAQAAAA==.',
Ca='Calihye:BAAANQAECgEIAQABNQAFFAgIGAAGAJweAA==.Camel:BAABNQAECn8zAAMKAAcKCQuSzQAmAQAKAAcKCQuSzQAmAQAJAAMKPwNWAQF3AAAAAA==.Catakatoan:BAAANQAECgQIBAAAAA==.Cattlestance:BAABNQAECn8zAAIOAAoKoxTMDgCyAQAOAAoKoxTMDgCyAQAAAA==.',
Ce='Ceriebrium:BAAANQAECgMICwAAAA==.',
Ch='Chichi:BAAANQADCgEIAQAAAA==.',
Co='Coldphyre:BAAANQAECgIIAwAAAA==.',
Da='Dakka:BAAANQADCgcICwAAAA==.Damnedsuen:BAABNQAECn8aAAMFAAYKiBdLTgD2AAAFAAYKiBdLTgD2AAAPAAIKphAbvwBtAAAAAA==.Dashdashdash:BAABNQAECn8oAAIQAAgKxRaHJQDJAQAQAAgKxRaHJQDJAQAAAA==.',
De='Deceiverdave:BAAANQAECgYICQAAAA==.Derazen:BAAANQADCgYIBgAAAA==.Destyne:BAAANQAECgQIDwAAAA==.',
Di='Dixonfire:BAAANQADCgEIAQAAAA==.',
Dj='Dj:BAABNQAECn83AAMLAAoKpxnhMQAgAgALAAoK3BfhMQAgAgARAAkKWRfCAwCHAQABNQAFFAYIEAASAKwYAA==.',
Do='Dodgydave:BAAANQAECgQIBQAAAA==.Doomzeer:BAABNQAECn8eAAMTAAoK8RrwEgDTAgATAAoK8RrwEgDTAgADAAEKlg4S5QA9AAAAAA==.',
Dr='Dragon:BAAANQAECgUIBQAAAA==.Drakarys:BAAANQAECgUIBQAAAA==.Drezlek:BAAANQADCgcICwAAAA==.Drezz:BAAANQADCggIFgAAAA==.Dràgøn:BAAANQAECggIAgAAAA==.',
Du='Durkanis:BAABNQAECn82AAIUAAoKLCP4BABRAwAUAAoKLCP4BABRAwAAAA==.',
El='Elamun:BAAANQAECgMIAwABNQAECgoKOwAEAO8ZAA==.Eleesa:BAAANQAECgUICwAAAA==.Element:BAABNQAECn8WAAIHAAcKLxFWigCKAQAHAAcKLxFWigCKAQAAAA==.',
Em='Emi:BAACNQAFFH8PAAIEAAYK3BzNBQAZAgAEAAYK3BzNBQAZAgA1AAQKfycAAwQACgrKIHYjANkCAAQACgrKIHYjANkCAAcABArwErXZAOEAAAAA.',
Ex='Exury:BAACNQAFFH8GAAIHAAIKgBhGHwC5AAAHAAIKgBhGHwC5AAA1AAQKfxsAAgcACgqSH1sqANcCAAcACgqSH1sqANcCAAAA.',
Fa='Faelin:BAAANQADCgYIBAAAAA==.',
Fe='Felenus:BAAANQAECgEJAQAAAA==.Fenrir:BAAANQAECgcICwAAAA==.',
Fi='Fir:BAABNQAECn8wAAIEAAoK0B8WHgDzAgAEAAoK0B8WHgDzAgAAAA==.',
Fl='Floknidemon:BAABNQAECn9EAAIEAAoKvQ+FRQDmAQAEAAoKvQ+FRQDmAQAAAA==.',
Fo='Forthrich:BAABNQAECn9QAAIKAAoKChDfbADjAQAKAAoKChDfbADjAQAAAA==.Fozuul:BAAANQAECggIDwABNQAECgoKLQAGAM4aAA==.',
Fr='Fredò:BAACNQAFFH8HAAISAAIKJxP9DQCBAAASAAIKJxP9DQCBAAA1AAQKfzcAAhIACgqOH0sRANYCABIACgqOH0sRANYCAAAA.Frozono:BAAANQAECgUIBgAAAA==.Frâust:BAABNQAECn8bAAMBAAkKngqCVQBXAQABAAkKngqCVQBXAQAPAAEKHAQc9QAiAAABNQAECgkJKQANANYMAA==.',
Ga='Galadril:BAAANQAECgEIAQAAAA==.Gandulf:BAAANQADCgUIBQAAAA==.Garriott:BAAANQAECgMIAgAAAA==.Gawkin:BAABNQAECn84AAMJAAoKSySUCQB8AwAJAAoKSySUCQB8AwAKAAEKmh/ffwFaAAAAAA==.',
Ge='Geodude:BAAANQADCgUIBQAAAA==.',
Go='Goaty:BAAANQAECgUIDQAAAA==.',
Gr='Grimspear:BAABNQAECn86AAIVAAoKJh95AgATAwAVAAoKJh95AgATAwAAAA==.',
Gu='Gumbercules:BAAANQAECgYIDQAAAA==.Gurnsey:BAAANQAECgEIAQAAAA==.',
['Gæ']='Gæa:BAAANQAECgYIBwAAAA==.',
Ha='Hakunamatata:BAAANQAECgMIBAAAAA==.Halogirl:BAABNQAECn81AAQWAAoKPh+GAQD8AgAWAAkK/h6GAQD8AgATAAUKEgkdSQD3AAADAAIKISIXrADJAAAAAA==.',
He='Heelorestus:BAABNQAECn8qAAMTAAkKRxPVJwDsAQATAAkKRxPVJwDsAQADAAQKJAWU2ACeAAAAAA==.Hellbreed:BAAANQADCgIIAgAAAA==.',
Ho='Holix:BAAANQADCgEIAQAAAA==.Holyfrog:BAABNQAECn88AAIJAAoKdhevPwBmAgAJAAoKdhevPwBmAgAAAA==.Holythis:BAABNQAECn86AAIXAAoKTRxdEACYAgAXAAoKTRxdEACYAgAAAA==.',
If='Ifrit:BAAANQAECgcIBQAAAA==.',
Ig='Ignis:BAABNQAECn89AAMYAAoKtw6WFwB/AQAYAAcKig6WFwB/AQAUAAoKrwxGJgBjAQAAAA==.',
In='Infiltrata:BAABNQAECn9VAAILAAoKeRvWJwBRAgALAAoKeRvWJwBRAgAAAA==.Injunjoe:BAAANQAECgQIBAAAAA==.',
Io='Io:BAACNQAFFH8GAAIFAAIKEBkLGgCNAAAFAAIKEBkLGgCNAAA1AAQKfyUAAgUACgokJGUMAE8DAAUACgokJGUMAE8DAAAA.',
Is='Ishida:BAAANQABCggIEwAAAA==.',
Ja='Janelik:BAABNQAECn8dAAIZAAYKHATqIQC3AAAZAAYKHATqIQC3AAAAAA==.',
Ji='Jimihendrix:BAAANQAECgYICgAAAA==.',
Jo='Jofixit:BAABNQAECn9FAAIaAAoKBxxzLwB3AgAaAAoKBxxzLwB3AgAAAA==.',
Ju='Judgemedaddy:BAAANQAECgEIAQAAAA==.',
Ka='Kanda:BAACNQAFFH8FAAIaAAMKTgonFgDRAAAaAAMKTgonFgDRAAA1AAQKfykAAhoACgpYH2ouAOICABoACgpYH2ouAOICAAAA.Kasunas:BAABNQAECn89AAIKAAoK2B+cKwCmAgAKAAoK2B+cKwCmAgAAAA==.Kaynub:BAAANQAECgEIAQABNQAECgoKRQAbABQiAA==.',
Ke='Kealthas:BAAANQAECgYIDgAAAA==.Kedri:BAABNQAECn9gAAIaAAoKihpwMwBpAgAaAAoKihpwMwBpAgAAAA==.Keihas:BAABNQAECn8ZAAIcAAkKaxhJEABTAgAcAAkKaxhJEABTAgAAAA==.Kermitt:BAAANQAECgQIBQAAAA==.',
Ki='Kikko:BAACNQAFFH8IAAIHAAMKixxjFwAJAQAHAAMKixxjFwAJAQA1AAQKfygAAgcACgo0JNIcAB0DAAcACgo0JNIcAB0DAAAA.Kikkomouse:BAAANQAECgUICAABNQAFFAMICAAHAIscAA==.',
Ko='Kobane:BAAANQAECgIIAQAAAA==.Konkine:BAAANQABCgEIAQAAAA==.Kozanu:BAAANQADCgYICgAAAA==.',
Ku='Kujara:BAAANQADCgMIAwAAAA==.Kurando:BAAANQAECggICAABNQAECgoKPQAKANgfAA==.Kurrindor:BAABNQAECn8nAAMXAAoKXB20EACTAgAXAAoKXB20EACTAgAKAAEKIR5/gwFVAAAAAA==.',
Ly='Lylith:BAAANQADCggIFAAAAA==.',
Ma='Macheon:BAAANQAECgEIAQAAAA==.Madashell:BAAANQADCgcIDAAAAA==.Maerwyn:BAAANQADCggJDQAAAA==.Magenub:BAABNQAECn9FAAIbAAoKFCJ7FADwAgAbAAoKFCJ7FADwAgAAAA==.Malexling:BAABNQAECn8sAAIKAAcKFBZbowBxAQAKAAcKFBZbowBxAQAAAA==.Masa:BAACNQAFFH8KAAIOAAYKKRn2AQAPAQAOAAYKKRn2AQAPAQA1AAQKfy8AAw4ACgrEHvQGAPECAA4ACgrEHvQGAPECAAIAAwpWER3SALwAAAAA.Mawe:BAAANQAECgEJAgAAAA==.',
Mi='Mistie:BAAANQABCgIIAgABNQAECgUIDAAdAAAAAA==.Mistlee:BAAANQAECgEIAgAAAA==.Mitternacht:BAABNQAECn9RAAIHAAoKyByKIwD5AgAHAAoKyByKIwD5AgAAAA==.',
Mo='Moggo:BAAANQADCgQIBwAAAA==.Moodew:BAABNQAECn8+AAIEAAoK2BglHADDAgAEAAoK2BglHADDAgAAAA==.',
Ms='Msdeath:BAABNQAECn8zAAIUAAcKph9UEQANAgAUAAcKph9UEQANAgAAAA==.',
My='Mya:BAAANQABCgQIBwAAAA==.Mykeroni:BAAANQADCgMIAwAAAA==.Myraku:BAAANQADCggIDAABNQAECgcIHQAIAFYHAA==.',
Na='Nachiko:BAAANQADCgMIAwAAAA==.Naois:BAAANQAECgQICQABNQAECgoKPQAKANgfAA==.Nashalion:BAABNQAECn8xAAMBAAoK9xWwJQBmAgABAAoK9xWwJQBmAgAFAAEK8gGc5QAZAAAAAA==.',
Ni='Nickchurch:BAAANQAECgIIAgAAAA==.Nidorhina:BAAANQABCgQIAwAAAA==.',
No='Nodarf:BAABNQAECn8/AAIeAAoKZBF2CgDRAQAeAAoKZBF2CgDRAQAAAA==.Norielin:BAAANQADCgQIBwAAAA==.',
Ok='Okayheals:BAABNQAECn9EAAIEAAoK4AxDSgDTAQAEAAoK4AxDSgDTAQAAAA==.',
Ol='Olumine:BAAANQAECgEIAQAAAA==.',
Or='Orin:BAAANQADCgUIBgAAAA==.',
Ot='Otherhandish:BAAANQABCgIIAgAAAA==.',
Pa='Panda:BAACNQAFFH8aAAQaAAgKFBv2DgBoAQAVAAQKLR3TAAB6AQAaAAYKTRj2DgBoAQAfAAMKOA3RFgDUAAA1AAQKf1EABBoACgptJuoRAP4CABoACgqQIuoRAP4CABUACgrvJV8BAPoCAB8ACArOIe0ZAIcCAAAA.',
Ph='Phuzzi:BAAANQAECggICAAAAA==.',
Pi='Picolás:BAABNQAECn8cAAIbAAYKHBht6wCzAQAbAAYKHBht6wCzAQAAAA==.',
Pr='Preacharound:BAAANQABCgMIAwAAAA==.Primrose:BAABNQAECn8oAAIDAAoKYxyaOACGAgADAAoKYxyaOACGAgAAAA==.Probono:BAABNQAECn8jAAITAAcKTwgvNADaAAATAAcKTwgvNADaAAAAAA==.',
Qu='Quarian:BAAANQAECgUICAAAAA==.',
Qw='Qwing:BAAANQAECgYIDAABNQAECgoKMQABAPcVAA==.',
Ra='Rainee:BAAANQADCgQIAwAAAA==.Raxefal:BAABNQAECn8pAAQNAAkK1gxSFQDLAAAIAAYK0gwcwwBFAQANAAUKPwtSFQDLAAAMAAMK1wv7RwCoAAAAAA==.',
Re='Reptar:BAAANQAECgYICgABNQAFFAYIGQAgABQcAA==.Restdrag:BAAANQADCgYIBgAAAA==.Rezø:BAABNQAECn84AAMDAAoKMhuYJQCoAgADAAoKMhuYJQCoAgATAAgKxBSGKgDTAQAAAA==.',
Ro='Roadkilldk:BAABNQAECn8dAAMBAAgK6wplUwBiAQABAAgK6wplUwBiAQAFAAEKxwJ04gAcAAAAAA==.',
['Rä']='Rägæ:BAAANQADCgYICAAAAA==.',
Sa='Sableye:BAABNQAECn9BAAIhAAoKcBxPDwBTAgAhAAoKcBxPDwBTAgAAAA==.Saguero:BAEBNQAECn82AAMEAAoKHBw7PQBrAgAEAAoKHBw7PQBrAgAHAAkKog7gaADmAQAAAA==.Satmorii:BAAANQABCggIEQAAAA==.',
Sc='Schatten:BAAANQAECgUIBwABNQAECgkJGQAOAIIXAA==.Schithappens:BAAANQABCgMIAwAAAA==.Scruffy:BAAANQAECgEIAQAAAA==.',
Se='Selina:BAABNQAECn8XAAMZAAoKtBiyDADtAQAbAAkKuhTQSQAiAgAZAAgKKxmyDADtAQAAAA==.Senortickle:BAABNQAECn8dAAIYAAoKAyXoBgB7AgAYAAoKAyXoBgB7AgAAAA==.',
Sh='Shaunara:BAAANQAECgEIAQABNQAFFAQIDgAFAA4hAA==.Shinoitamis:BAAANQAECggICgABNQAECgkJSQAKAIUfAA==.Shinotenshi:BAABNQAECn9JAAIKAAkKhR9QJAA0AwAKAAkKhR9QJAA0AwAAAA==.Shìva:BAAANQADCggICAAAAA==.Shînon:BAAANQAECgMIAwABNQAECgoKOAADADIbAA==.',
Si='Siphin:BAAANQAECggICQAAAA==.',
So='Solar:BAAANQAECgIIBAABNQAFFAMIBwAgAPYLAA==.Solàire:BAABNQAECn88AAMJAAoKkAsRfwCcAQAJAAoKkAsRfwCcAQAKAAoKbApnkgCSAQAAAA==.Sonicice:BAAANQADCgQIAQAAAA==.',
Sp='Spacewafflez:BAAANQAECgIIAwAAAA==.',
St='Starburnz:BAAANQADCgMIAwABNQAECgoKLQAGAM4aAA==.Stimutax:BAAANQAECgIIAwAAAA==.',
Ta='Tamborine:BAAANQADCgIIAgAAAA==.Taurenvar:BAABNQAECn9MAAIiAAoKKiM+AgCKAwAiAAoKKiM+AgCKAwAAAA==.',
Te='Teddyhappy:BAABNQAECn8XAAQUAAoKNhZ8EQAKAgAUAAkKNhZ8EQAKAgAYAAEK3wYVTwAbAAAjAAEKJQOxhAAYAAAAAA==.',
Th='Thekeres:BAAANQAECggICwAAAA==.',
To='Tora:BAABNQAECn8bAAMeAAoK4AcfIACRAAACAAcK8whN3gAuAQAeAAoKbgMfIACRAAAAAA==.',
Tr='Trollbrudda:BAABNQAECn9NAAMgAAoKaSF0DgBWAwAgAAoKaSF0DgBWAwAUAAMKuBeHPwC9AAAAAA==.',
Um='Umgross:BAAANQADCgYIBgAAAA==.',
Un='Unholygrudge:BAAANQADCgIIAgAAAA==.',
Ve='Velenus:BAAANQAFFAEIAQAAAA==.Vesperion:BAAANQADCgQICgABNQAECgkJKQANANYMAA==.',
Vi='Vickdak:BAAANQABCgUIBgAAAA==.Vilehatred:BAAANQAECgUICgAAAA==.',
Vo='Voltz:BAAANQADCggIEAAAAA==.',
Wa='Wallis:BAABNQAECn8nAAIbAAgKXwUrvgAYAQAbAAgKXwUrvgAYAQAAAA==.Warmoz:BAABNQAECn8ZAAIOAAkKghcAEAApAgAOAAkKghcAEAApAgAAAA==.',
Wu='Wunhunglo:BAAANQABCgQIBAAAAA==.',
Xe='Xergiator:BAABNQAECn8xAAIaAAkKtAh7uwCMAQAaAAkKtAh7uwCMAQAAAA==.',
Za='Zaligator:BAABNQAECn8kAAQkAAgKEBXBDACGAQAcAAgKChSAGADAAQAkAAcKvBHBDACGAQAlAAEK8ghZPAAkAAAAAA==.Zarideyne:BAAANQAECgEIAQAAAA==.',
Zo='Zombinized:BAAANQADCgUIBgAAAA==.',
Zu='Zuulian:BAABNQAECn8tAAQGAAoKzhooEgBaAgAGAAoKzhooEgBaAgASAAMKBQdgTQBeAAAmAAEKAAD8NAAjAAAAAA==.',
Zy='Zylph:BAABNQAECn8dAAIIAAcKVgfarADnAAAIAAcKVgfarADnAAAAAA==.',
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
