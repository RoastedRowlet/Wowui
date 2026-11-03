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

local lookup = {'DeathKnight-Frost','Warrior-Arms','Priest-Holy','Shaman-Restoration','DeathKnight-Blood','Monk-Mistweaver','Warlock-Demonology','Paladin-Holy','Paladin-Retribution','Rogue-Subtlety','Warlock-Destruction','Warlock-Affliction','Warrior-Protection','DeathKnight-Unholy','DemonHunter-Havoc','Rogue-Outlaw','Monk-Windwalker','Priest-Shadow','Druid-Guardian','Shaman-Elemental','Hunter-Survival','Priest-Discipline','Paladin-Protection','Druid-Feral','Mage-Frost','Hunter-BeastMastery','Mage-Arcane','Unknown-Unknown','Warrior-Fury','Hunter-Marksmanship','Druid-Balance','DemonHunter-Devourer','Shaman-Enhancement','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Monk-Brewmaster',}
local provider = {region='US',realm='Maelstrom',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Absydion:BAAANQAECggICwAAAA==.',
Ad='Adema:BAAANQADCgYICAABNQAECgoKLwABAOIVAA==.',
Ae='Aelion:BAAANQAECgIIAwABNQAECgkJGgACALAcAA==.',
An='Anegos:BAAANQADCggIDwABNQAFFAUIBwADACUMAA==.Anyliea:BAAANQAECgIIAgAAAA==.',
Ar='Arwenah:BAABNQAECn8mAAIEAAkK9g4NUgCYAQAEAAkK9g4NUgCYAQAAAA==.',
As='Asahhealer:BAABNQAECn83AAIEAAoKjhfrPQBoAgAEAAoKjhfrPQBoAgAAAA==.Astridd:BAACNQAFFH8OAAIFAAQKDiGTCgAYAQAFAAQKDiGTCgAYAQA1AAQKfy8AAgUACgotJP4DAD0DAAUACgotJP4DAD0DAAAA.Aszcuul:BAAANQADCgEIAgABNQAECgoKLQAGAM4aAA==.',
Au='Aurorabelli:BAAANQAECgYIEwAAAA==.Auróra:BAABNQAECn8vAAIHAAoKGiGkFQA0AwAHAAoKGiGkFQA0AwAAAA==.',
Av='Averlence:BAAANQAECgQICwAAAA==.',
Aw='Awriya:BAAANQADCgEIAQAAAA==.',
Ba='Bahumn:BAAANQAECggIDAABNQAECgoKLwABAOIVAA==.Batteryacid:BAAANQAECgMIBQAAAA==.',
Be='Bergles:BAABNQAECn9DAAMIAAoK/hp2PwBnAgAIAAoK/hp2PwBnAgAJAAoKvRvsRQAlAgAAAA==.Beryl:BAAANQADCgEIAQAAAA==.',
Bi='Bigtee:BAAANQADCgcICQAAAA==.',
Bo='Bonitoflakes:BAAANQADCgQIBAAAAA==.Bonnieblüe:BAACNQAFFH8FAAIKAAMKpgECGQCEAAAKAAMKpgECGQCEAAA1AAQKfyIAAgoACQp5CixJAI8BAAoACQp5CixJAI8BAAAA.Bopeep:BAAANQADCgcICQAAAA==.',
Br='Brekta:BAAANQADCggIEQAAAA==.Brewwizard:BAAANQAECgUICwABNQAECgoKLgAGAGARAA==.',
Bu='Bullshiza:BAAANQADCgEIAQAAAA==.Burningfel:BAABNQAECn89AAQLAAoK5RRSBACbAQAMAAgKRRTYBwAZAgALAAkKNRVSBACbAQAHAAkKWguAZwBmAQAAAA==.',
Ca='Calihye:BAAANQAECgEIAQABNQAFFAcIFwAGAEEgAA==.Camel:BAABNQAECn8sAAMJAAcKugrcwgAQAQAJAAcKugrcwgAQAQAIAAMKPwNWAQF3AAAAAA==.Catakatoan:BAAANQAECgQIBAAAAA==.Cattlestance:BAABNQAECn8zAAINAAoKoxRaDAC7AQANAAoKoxRaDAC7AQAAAA==.',
Ce='Ceriebrium:BAAANQAECgMICAAAAA==.',
Co='Coldphyre:BAAANQAECgIIAwAAAA==.Corvo:BAAANQAECgIIBAABNQAECgoKPQAJANgfAA==.',
Da='Dakka:BAAANQADCgcICwAAAA==.Damnedsuen:BAABNQAECn8aAAMFAAYKiBdDRwD3AAAFAAYKiBdDRwD3AAAOAAIKphAbvwBtAAAAAA==.Dashdashdash:BAABNQAECn8hAAIPAAgKhRaEIgC7AQAPAAgKhRaEIgC7AQAAAA==.',
De='Deceiverdave:BAAANQAECgYICwAAAA==.Derazen:BAAANQADCgYIBgAAAA==.Destyne:BAAANQAECgQIDwAAAA==.',
Di='Dixonfire:BAAANQADCgEIAQAAAA==.',
Dj='Dj:BAABNQAECn83AAMKAAoKpxkMLAAXAgAKAAoK3BcMLAAXAgAQAAkKWRdbAwCHAQABNQAFFAUIDwARAGoaAA==.',
Do='Dodgydave:BAAANQAECgQIBQAAAA==.Doomzeer:BAABNQAECn8eAAMSAAoK8RrwEgDTAgASAAoK8RrwEgDTAgADAAEKlg7R2AA9AAAAAA==.',
Dr='Dragon:BAAANQAECgUIBQAAAA==.Drakarys:BAAANQAECgUIBQAAAA==.Drezlek:BAAANQADCgcIDAAAAA==.Drezz:BAAANQADCggIGAAAAA==.Dràgøn:BAAANQAECggIAgAAAA==.',
Du='Durkanis:BAABNQAECn82AAITAAoKLCPiBAD2AgATAAoKLCPiBAD2AgAAAA==.',
El='Eleesa:BAAANQAECgUICwAAAA==.Element:BAABNQAECn8WAAIUAAcKLxFWigCKAQAUAAcKLxFWigCKAQAAAA==.',
Em='Emi:BAACNQAFFH8PAAIEAAYK3BwZBAAgAgAEAAYK3BwZBAAgAgA1AAQKfycAAwQACgrKIHYjANkCAAQACgrKIHYjANkCABQABArwErXZAOEAAAAA.',
En='Enøch:BAAANQAECgEIAQAAAA==.',
Ex='Exury:BAACNQAFFH8GAAIUAAIKgBhGHwC5AAAUAAIKgBhGHwC5AAA1AAQKfxsAAhQACgqSH1sqANcCABQACgqSH1sqANcCAAAA.',
Fa='Faelin:BAAANQADCgYIBAAAAA==.',
Fe='Felenus:BAAANQAECgEJAQAAAA==.Fenrir:BAAANQAECgYICwAAAA==.',
Fi='Fir:BAABNQAECn8wAAIEAAoK0B8WHgDzAgAEAAoK0B8WHgDzAgAAAA==.',
Fl='Floknidemon:BAABNQAECn89AAIEAAoKlA7pPgDoAQAEAAoKlA7pPgDoAQAAAA==.',
Fo='Forthrich:BAABNQAECn8/AAIJAAoKvQ08dwCfAQAJAAoKvQ08dwCfAQAAAA==.Fozuul:BAAANQAECggIEAABNQAECgoKLQAGAM4aAA==.',
Fr='Fredò:BAACNQAFFH8GAAIRAAIKJxNGDAB/AAARAAIKJxNGDAB/AAA1AAQKfzMAAhEACgrGHksRANYCABEACgrGHksRANYCAAAA.Freeports:BAAANQAECgEIAQAAAA==.Frozono:BAAANQAECgUIBgAAAA==.Frâust:BAABNQAECn8bAAMBAAkKngqCVQBXAQABAAkKngqCVQBXAQAOAAEKHAQc9QAiAAABNQAECgkJKQAMANYMAA==.',
Ga='Galadril:BAAANQAECgEIAQAAAA==.Gandulf:BAAANQADCgUIBQAAAA==.Garriott:BAAANQAECgMIBAAAAA==.Gawkin:BAABNQAECn84AAMIAAoKSySUCQB8AwAIAAoKSySUCQB8AwAJAAEKmh/ffwFaAAAAAA==.',
Ge='Geodude:BAAANQADCgUIBQAAAA==.',
Go='Goaty:BAAANQAECgQIEAAAAA==.',
Gr='Grimspear:BAABNQAECn86AAIVAAoKJh95AgATAwAVAAoKJh95AgATAwAAAA==.',
Gu='Gumbercules:BAAANQAECgUIDgAAAA==.Gurnsey:BAAANQAECgEIAQAAAA==.',
['Gæ']='Gæa:BAAANQAECgYIBwAAAA==.',
Ha='Hakunamatata:BAAANQAECgEIAwAAAA==.Halogirl:BAABNQAECn8qAAMWAAkKJB2UAQDIAgAWAAkKJB2UAQDIAgASAAUKEgkdSQD3AAAAAA==.Haters:BAAANQAECgEIAQAAAA==.',
He='Heelorestus:BAABNQAECn8qAAMSAAkKRxPVJwDsAQASAAkKRxPVJwDsAQADAAQKJAWU2ACeAAAAAA==.Hellbreed:BAAANQADCgIIAgAAAA==.',
Ho='Holix:BAAANQADCgEIAQAAAA==.Holyfrog:BAABNQAECn88AAIIAAoKdhevPwBmAgAIAAoKdhevPwBmAgAAAA==.Holythis:BAABNQAECn86AAIXAAoKTRxdEACYAgAXAAoKTRxdEACYAgAAAA==.',
If='Ifrit:BAAANQAECgcIBQAAAA==.',
Ig='Ignis:BAABNQAECn89AAMYAAoKtw6WFwB/AQAYAAcKig6WFwB/AQATAAoKrwxGJgBjAQAAAA==.',
In='Infiltrata:BAABNQAECn9OAAIKAAoKeRvXJQA6AgAKAAoKeRvXJQA6AgAAAA==.Injunjoe:BAAANQAECgQIBAAAAA==.',
Io='Io:BAACNQAFFH8GAAIFAAIKEBnCFQCTAAAFAAIKEBnCFQCTAAA1AAQKfyUAAgUACgokJGUMAE8DAAUACgokJGUMAE8DAAAA.',
Is='Ishida:BAAANQAECgEIAQAAAA==.',
Ja='Janelik:BAABNQAECn8XAAIZAAYK4QP3HwCnAAAZAAYK4QP3HwCnAAAAAA==.',
Ji='Jimihendrix:BAAANQAECgYICgAAAA==.',
Jo='Jofixit:BAABNQAECn8+AAIaAAoKBxyFLgBaAgAaAAoKBxyFLgBaAgAAAA==.',
Ju='Judgemedaddy:BAAANQAECgEIAQAAAA==.',
Ka='Kanda:BAACNQAFFH8FAAIaAAMKTgo8EwDVAAAaAAMKTgo8EwDVAAA1AAQKfyIAAhoACgrSHWouAOICABoACgrSHWouAOICAAAA.Kasunas:BAABNQAECn89AAIJAAoK2B9JIwCwAgAJAAoK2B9JIwCwAgAAAA==.Kaynub:BAAANQAECgEIAQABNQAECgoKRQAbABQiAA==.',
Ke='Kealthas:BAAANQAECgYIDgAAAA==.Kedri:BAABNQAECn9WAAIaAAoK2Bm3NABDAgAaAAoK2Bm3NABDAgAAAA==.Keihas:BAAANQAECgcIEQAAAA==.Kermitt:BAAANQAECgQIBQAAAA==.',
Ki='Kikko:BAACNQAFFH8IAAIUAAMKixxjFwAJAQAUAAMKixxjFwAJAQA1AAQKfygAAhQACgo0JNIcAB0DABQACgo0JNIcAB0DAAAA.Kikkomouse:BAAANQAECgUICAABNQAFFAMICAAUAIscAA==.',
Ko='Kobane:BAAANQAECgEIAQAAAA==.Konkine:BAAANQADCgEIAQAAAA==.Kozanu:BAAANQADCgYIBwAAAA==.',
Ku='Kujara:BAAANQADCgMIBAAAAA==.Kurando:BAAANQAECggICAABNQAECgoKPQAJANgfAA==.Kurrindor:BAABNQAECn8gAAMXAAgK6B+0EACTAgAXAAgK6B+0EACTAgAJAAEKIR5/gwFVAAAAAA==.',
Ly='Lylith:BAAANQADCggIFAAAAA==.',
Ma='Macheon:BAAANQAECgEIAQAAAA==.Madashell:BAAANQADCgcIDAAAAA==.Maerwyn:BAAANQADCggJDQAAAA==.Magenub:BAABNQAECn9FAAIbAAoKFCIBEAD9AgAbAAoKFCIBEAD9AgAAAA==.Malexling:BAABNQAECn8sAAIJAAcKFBa7kABqAQAJAAcKFBa7kABqAQAAAA==.Masa:BAACNQAFFH8JAAINAAUK3Rm7AgDJAAANAAUK3Rm7AgDJAAA1AAQKfywAAw0ACgrEHvQGAPECAA0ACgrEHvQGAPECAAIAAwpWEafCALwAAAAA.Matt:BAAANQAECgEIAQAAAA==.Mawe:BAAANQAECgEJAgAAAA==.',
Mi='Mistie:BAAANQADCgEIAQABNQAECgUIDAAcAAAAAA==.Mistlee:BAAANQAECgEIAgAAAA==.Mitternacht:BAABNQAECn9RAAIUAAoKyByKIwD5AgAUAAoKyByKIwD5AgAAAA==.',
Mo='Moggo:BAAANQADCgQIBwAAAA==.Moodew:BAABNQAECn80AAIEAAkKbRqxJQBoAgAEAAkKbRqxJQBoAgAAAA==.',
Ms='Msdeath:BAABNQAECn8sAAITAAcKch9eEQDlAQATAAcKch9eEQDlAQAAAA==.',
My='Mya:BAAANQADCgEIAQAAAA==.Mykeroni:BAAANQADCgMIAwAAAA==.Myraku:BAAANQADCggIDAABNQAECgYIFwAHAKsGAA==.',
Na='Nachiko:BAAANQADCgMIBAAAAA==.Naois:BAAANQAECgQICQABNQAECgoKPQAJANgfAA==.Nashalion:BAABNQAECn8vAAMBAAoK4hWwJQBmAgABAAoK4hWwJQBmAgAFAAEK8gGc5QAZAAAAAA==.',
Ne='Nemlock:BAAANQAECgEIAgABNQAECgcIHgAbAOcEAA==.',
Ni='Nickchurch:BAAANQAECgIIAgAAAA==.Nidorhina:BAAANQADCgEIAQAAAA==.Ninkaly:BAAANQADCgEIAQAAAA==.',
No='Nodarf:BAABNQAECn84AAIdAAoKOREdCQDIAQAdAAoKOREdCQDIAQAAAA==.Norielin:BAAANQADCgQIBwAAAA==.',
Ok='Okayheals:BAABNQAECn89AAIEAAoK6ApjRwDDAQAEAAoK6ApjRwDDAQAAAA==.',
Ol='Olumine:BAAANQAECgEIAQAAAA==.',
Or='Orin:BAAANQADCgUIBgAAAA==.',
Ot='Otherhandish:BAAANQAECgEIAQAAAA==.',
Pa='Panda:BAACNQAFFH8aAAQaAAgKFBv2DgBoAQAVAAQKLR3TAAB6AQAaAAYKTRj2DgBoAQAeAAMKOA3RFgDUAAA1AAQKf0oABBoACgrcJYsOAAEDABoACgqQIosOAAEDABUACAoTJYYEAJkCAB4ACArOIe0ZAIcCAAAA.',
Ph='Phuzzi:BAAANQAECggICAAAAA==.',
Pi='Picolás:BAABNQAECn8cAAIbAAYKHBht6wCzAQAbAAYKHBht6wCzAQAAAA==.',
Pr='Preacharound:BAAANQADCgEIAQAAAA==.Primrose:BAABNQAECn8oAAIDAAoKYxz+KwBiAgADAAoKYxz+KwBiAgAAAA==.Probono:BAABNQAECn8dAAISAAcKPQgSLwDXAAASAAcKPQgSLwDXAAAAAA==.',
Qu='Quarian:BAAANQAECgQIBAAAAA==.',
Qw='Qwing:BAAANQAECgYIDAABNQAECgoKLwABAOIVAA==.',
Ra='Rainee:BAAANQADCgQIAwAAAA==.Raxefal:BAABNQAECn8pAAQMAAkK1gzrEQDMAAAHAAYK0gwcwwBFAQAMAAUKPwvrEQDMAAALAAMK1wv7RwCoAAAAAA==.',
Re='Reprises:BAAANQADCgEIAQAAAA==.Reptar:BAAANQAECgYICgABNQAFFAYIGQAfABQcAA==.Restdrag:BAAANQADCgYIBgAAAA==.Rezø:BAABNQAECn8zAAMDAAoKMhvFIwCUAgADAAoKMhvFIwCUAgASAAgKxBSGKgDTAQAAAA==.',
Ro='Roadkilldk:BAABNQAECn8dAAMBAAgK6wplUwBiAQABAAgK6wplUwBiAQAFAAEKxwJ04gAcAAAAAA==.',
['Rä']='Rägæ:BAAANQADCgYICAAAAA==.',
Sa='Sableye:BAABNQAECn8+AAIgAAoKtBvPDQBRAgAgAAoKtBvPDQBRAgAAAA==.Saguero:BAEBNQAECn82AAMEAAoKHBwLLABEAgAEAAoKHBwLLABEAgAUAAkKog7gaADmAQAAAA==.Satmorii:BAAANQADCgEIAQAAAA==.',
Sc='Schatten:BAAANQAECgUIBwABNQAECggIGAANAP8YAA==.Schithappens:BAAANQADCgEIAQAAAA==.Scruffy:BAAANQAECgEIAQAAAA==.',
Se='Selina:BAABNQAECn8XAAMZAAoKtBiyDADtAQAbAAkKuhS0PQAxAgAZAAgKKxmyDADtAQAAAA==.Senortickle:BAABNQAECn8bAAIYAAoKAyWqBQCBAgAYAAoKAyWqBQCBAgAAAA==.Seymourbutts:BAAANQADCgEIAQAAAA==.',
Sh='Shaunara:BAAANQAECgEIAQABNQAFFAQIDgAFAA4hAA==.Shinoitamis:BAAANQAECggICgABNQAECgkJQQAJAIUfAA==.Shinotenshi:BAABNQAECn9BAAIJAAkKhR9QJAA0AwAJAAkKhR9QJAA0AwAAAA==.Shìva:BAAANQADCggICAAAAA==.Shînon:BAAANQAECgMIAwABNQAECgoKMwADADIbAA==.',
Si='Siphin:BAAANQAECggICQAAAA==.',
So='Solar:BAAANQAECgMIBQABNQAFFAMIBwAfAPYLAA==.Solàire:BAABNQAECn81AAMIAAoKbQwRfwCcAQAIAAkKSwoRfwCcAQAJAAgKBgqHpABEAQAAAA==.Sonicice:BAAANQADCgQIBQAAAA==.',
Sp='Spacewafflez:BAAANQAECgIIAwAAAA==.',
St='Starburnz:BAAANQADCgMIBAABNQAECgoKLQAGAM4aAA==.Stimutax:BAAANQAECgIIAwAAAA==.',
Ta='Tamborine:BAAANQADCgIIAwAAAA==.Taurenvar:BAABNQAECn9GAAIhAAoKKiM+AgCKAwAhAAoKKiM+AgCKAwAAAA==.',
Te='Teddyhappy:BAAANQAECggIDgAAAA==.',
Th='Thekeres:BAAANQAECggICwAAAA==.',
To='Tora:BAAANQAECgYJBgAAAA==.',
Tr='Trollbrudda:BAABNQAECn9MAAMfAAoKViF0DgBWAwAfAAoKViF0DgBWAwATAAMKuBeHPwC9AAAAAA==.',
Um='Umgross:BAAANQADCgYIBgAAAA==.',
Un='Unholygrudge:BAAANQADCgIIAgAAAA==.',
Ve='Velenus:BAAANQAECgMIBQAAAA==.Vesperion:BAAANQADCgQICgABNQAECgkJKQAMANYMAA==.',
Vi='Vickdak:BAAANQABCgUIBgAAAA==.Vilehatred:BAAANQAECgUICwAAAA==.',
Vo='Voltz:BAAANQADCggIEgAAAA==.',
Wa='Wallis:BAABNQAECn8eAAIbAAcK5wShzQDjAAAbAAcK5wShzQDjAAAAAA==.Warmoz:BAABNQAECn8YAAINAAgK/xgAEAApAgANAAgK/xgAEAApAgAAAA==.',
Wu='Wunhunglo:BAAANQADCgEIAgAAAA==.',
Xe='Xergiator:BAABNQAECn8uAAIaAAkKtAjVogAoAQAaAAkKtAjVogAoAQAAAA==.',
Za='Zaligator:BAABNQAECn8kAAQiAAgKEBXBDACGAQAjAAgKChSAGADAAQAiAAcKvBHBDACGAQAkAAEK8ggYOAAkAAAAAA==.Zarideyne:BAAANQAECgEIAQAAAA==.',
Zo='Zombinized:BAAANQADCgUIBQAAAA==.',
Zu='Zuulian:BAABNQAECn8tAAQGAAoKzhooEgBaAgAGAAoKzhooEgBaAgARAAMKBQdjRwBfAAAlAAEKAAD8NAAjAAAAAA==.',
Zy='Zylph:BAABNQAECn8XAAIHAAYKqwaG3AAQAQAHAAYKqwaG3AAQAQAAAA==.',
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
