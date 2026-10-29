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

local lookup = {'DeathKnight-Frost','Warrior-Arms','Priest-Holy','Shaman-Restoration','DeathKnight-Blood','Monk-Mistweaver','Warlock-Demonology','Paladin-Holy','Paladin-Retribution','Rogue-Subtlety','Warlock-Destruction','Warlock-Affliction','Warrior-Protection','DeathKnight-Unholy','DemonHunter-Havoc','Rogue-Outlaw','Monk-Windwalker','Priest-Shadow','Druid-Guardian','Shaman-Elemental','Hunter-Survival','Priest-Discipline','Paladin-Protection','Druid-Feral','Hunter-BeastMastery','Mage-Arcane','Unknown-Unknown','Warrior-Fury','Hunter-Marksmanship','Druid-Balance','DemonHunter-Devourer','Mage-Frost','Shaman-Enhancement','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Monk-Brewmaster',}
local provider = {region='US',realm='Maelstrom',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Absydion:BAAANQAECggIDQAAAA==.',
Ad='Adema:BAAANQADCgIIAgABNQAECgoKIgABAK0VAA==.',
Ae='Aelion:BAAANQAECgIIBAABNQAECgkJGgACALAcAA==.',
An='Anegos:BAAANQADCggIDwABNQAFFAUIBwADACUMAA==.Anyliea:BAAANQAECgIIAgAAAA==.',
Ar='Arwenah:BAABNQAECn8dAAIEAAcK8xE9XQAnAQAEAAcK8xE9XQAnAQAAAA==.',
As='Asahhealer:BAABNQAECn8yAAIEAAkKfRjrPQBoAgAEAAkKfRjrPQBoAgAAAA==.Astridd:BAACNQAFFH8KAAIFAAQKBiDJBwAaAQAFAAQKBiDJBwAaAQA1AAQKfysAAgUACgomIzYEAB8DAAUACgomIzYEAB8DAAAA.Aszcuul:BAAANQADCgEIAQABNQAECgoKLQAGAM4aAA==.',
Au='Aurorabelli:BAAANQAECgYIDwAAAA==.Auróra:BAABNQAECn8uAAIHAAoK8yCkFQA0AwAHAAoK8yCkFQA0AwAAAA==.',
Av='Averlence:BAAANQAECgQICwAAAA==.',
Aw='Awriya:BAAANQAECgEIAQAAAA==.',
Ba='Bahumn:BAAANQAECgQIBQABNQAECgoKIgABAK0VAA==.Batteryacid:BAAANQAECgIIAwAAAA==.',
Be='Bergles:BAABNQAECn85AAMIAAoK/hp2PwBnAgAIAAoK/hp2PwBnAgAJAAgKhRsiawBcAgAAAA==.',
Bi='Bigtee:BAAANQADCgcICQAAAA==.',
Bo='Bonitoflakes:BAAANQADCgQIBAAAAA==.Bonnieblüe:BAABNQAECn8ZAAIKAAkKIAr1OACDAQAKAAkKIAr1OACDAQAAAA==.Bopeep:BAAANQADCgcICAAAAA==.',
Br='Brekta:BAAANQAECgEIAQAAAA==.Brewwizard:BAAANQAECgUICwABNQAECgkJKAAGADIPAA==.',
Bu='Bullshiza:BAAANQABCgUIBwAAAA==.Burningfel:BAABNQAECn8zAAQLAAkK/xZHBABjAQAMAAgKRRTYBwAZAgALAAkKHhRHBABjAQAHAAIKhAsVKQFsAAAAAA==.',
Ca='Calihye:BAAANQAECgEIAgABNQAFFAcIFwAGAEEgAA==.Camel:BAABNQAECn8oAAMJAAcKugpAlgAmAQAJAAcKugpAlgAmAQAIAAMKPwNWAQF3AAAAAA==.Cattlestance:BAABNQAECn8zAAINAAoKoxR0CADMAQANAAoKoxR0CADMAQAAAA==.',
Ce='Ceriebrium:BAAANQAECgMIBgAAAA==.',
Ch='Chichi:BAAANQABCggIDAAAAA==.',
Co='Coldphyre:BAAANQAECgIIAwAAAA==.Corvo:BAAANQAECgIIAgABNQAECgoKNwAJADEfAA==.',
Da='Dakka:BAAANQADCgcICwAAAA==.Damnedsuen:BAABNQAECn8WAAMFAAYKiBdPOAADAQAFAAYKiBdPOAADAQAOAAIKphAbvwBtAAAAAA==.Dashdashdash:BAABNQAECn8ZAAIPAAYKsBgHSACJAQAPAAYKsBgHSACJAQAAAA==.',
De='Deceiverdave:BAAANQAECgQIBgAAAA==.Derazen:BAAANQADCgYIBgAAAA==.Destyne:BAAANQAECgUIDQAAAA==.',
Di='Dixonfire:BAAANQADCgEIAQAAAA==.',
Dj='Dj:BAABNQAECn80AAMKAAkKtxkhKQDgAQAKAAkKPhghKQDgAQAQAAkKxhbGAgCJAQABNQAFFAUIDwARAGoaAA==.',
Do='Dodgydave:BAAANQAECgQIBQAAAA==.Doomzeer:BAABNQAECn8eAAMSAAoK8RrwEgDTAgASAAoK8RrwEgDTAgADAAEKlg4YvwBAAAAAAA==.',
Dr='Dragon:BAAANQAECgUIBQAAAA==.Drakarys:BAAANQAECgUIBgAAAA==.Drezlek:BAAANQADCgcICwAAAA==.Drezz:BAAANQADCggIFgAAAA==.Dràgøn:BAAANQAECggIAwAAAA==.',
Du='Durkanis:BAABNQAECn82AAITAAoKLCMiAwAIAwATAAoKLCMiAwAIAwAAAA==.',
El='Eleesa:BAAANQAECgUIDwAAAA==.Element:BAABNQAECn8WAAIUAAcKLxFWigCKAQAUAAcKLxFWigCKAQAAAA==.',
Em='Emi:BAACNQAFFH8NAAIEAAUKGBtiBQC5AQAEAAUKGBtiBQC5AQA1AAQKfyUAAwQACgrKIHYjANkCAAQACgrKIHYjANkCABQABArwErXZAOEAAAAA.',
Ex='Exury:BAACNQAFFH8GAAIUAAIKgBhGHwC5AAAUAAIKgBhGHwC5AAA1AAQKfxoAAhQACQq5HlsqANcCABQACQq5HlsqANcCAAAA.',
Fa='Faelin:BAAANQADCgYIBAAAAA==.',
Fe='Felenus:BAAANQAECgEJAQAAAA==.Fenrir:BAAANQAECgQIDAAAAA==.',
Fi='Fir:BAABNQAECn8wAAIEAAoK0B8WHgDzAgAEAAoK0B8WHgDzAgAAAA==.',
Fl='Floknidemon:BAABNQAECn8zAAIEAAkKMw/YcgCzAQAEAAkKMw/YcgCzAQAAAA==.',
Fo='Forthrich:BAABNQAECn81AAIJAAoKuw2fVQC1AQAJAAoKuw2fVQC1AQAAAA==.Fozuul:BAAANQAECggIDgABNQAECgoKLQAGAM4aAA==.',
Fr='Fredò:BAABNQAECn8vAAIRAAoKVR5LEQDWAgARAAoKVR5LEQDWAgAAAA==.Freeports:BAAANQAECgEIAQAAAA==.Frozono:BAAANQAECgUIBwAAAA==.Frâust:BAABNQAECn8WAAMBAAgKCwuCVQBXAQABAAgKCwuCVQBXAQAOAAEKHAQc9QAiAAABNQAECgkJKQAMANYMAA==.',
Ga='Galadril:BAAANQAECgEIAQAAAA==.Gandulf:BAAANQADCgUIBQAAAA==.Garriott:BAAANQAECgEIBQAAAA==.Gawkin:BAABNQAECn8yAAMIAAoKTCSUCQB8AwAIAAoKTCSUCQB8AwAJAAEKmh/ffwFaAAAAAA==.',
Ge='Geodude:BAAANQADCgUIBQAAAA==.',
Go='Goaty:BAAANQAECgYIDgAAAA==.',
Gr='Grimspear:BAABNQAECn80AAIVAAoKJh95AgATAwAVAAoKJh95AgATAwAAAA==.',
Gu='Gumbercules:BAAANQAECgQIDQAAAA==.Gurnsey:BAAANQAECgEIAQAAAA==.',
['Gæ']='Gæa:BAAANQAECgYICAAAAA==.',
Ha='Halogirl:BAABNQAECn8iAAMWAAkK/BtfAQCTAgAWAAkK/BtfAQCTAgASAAUKUgcdSQD3AAAAAA==.Haters:BAAANQAECgEIAgAAAA==.',
He='Heelorestus:BAABNQAECn8pAAMSAAgKqBTVJwDsAQASAAgKqBTVJwDsAQADAAQKJAWU2ACeAAAAAA==.Hellbreed:BAAANQADCgIIAgAAAA==.',
Ho='Holix:BAAANQADCgEIAQAAAA==.Holyfrog:BAABNQAECn82AAIIAAoKbRWvPwBmAgAIAAoKbRWvPwBmAgAAAA==.Holythis:BAABNQAECn86AAIXAAoKTRxdEACYAgAXAAoKTRxdEACYAgAAAA==.',
If='Ifrit:BAAANQAECgcIBgAAAA==.',
Ig='Ignis:BAABNQAECn80AAMYAAkKhg6WFwB/AQAYAAcKig6WFwB/AQATAAkKMwxGJgBjAQAAAA==.',
In='Infiltrata:BAABNQAECn9CAAIKAAoKeRu8GwA/AgAKAAoKeRu8GwA/AgAAAA==.Injunjoe:BAAANQAECgQIBAAAAA==.',
Io='Io:BAABNQAECn8lAAIFAAoKJCRlDABPAwAFAAoKJCRlDABPAwAAAA==.',
Is='Ishida:BAAANQAECgEIAQAAAA==.',
Ja='Janelik:BAAANQAECgYIEgAAAA==.',
Ji='Jimihendrix:BAAANQAECgYICgAAAA==.',
Jo='Jofixit:BAABNQAECn80AAIZAAkK5RpQSgCOAgAZAAkK5RpQSgCOAgAAAA==.Joristine:BAAANQAECgEIAQAAAA==.',
Ju='Judgemedaddy:BAAANQAECgEIAQAAAA==.',
Ka='Kanda:BAACNQAFFH8FAAIZAAMKTgrcDgDbAAAZAAMKTgrcDgDbAAA1AAQKfx8AAhkACgrFHGouAOICABkACgrFHGouAOICAAAA.Kasunas:BAABNQAECn83AAIJAAoKMR81KABhAgAJAAoKMR81KABhAgAAAA==.Kaynub:BAAANQAECgEIAgABNQAECgoKPgAaAOYhAA==.',
Ke='Kealthas:BAAANQAECgYIDwAAAA==.Kedri:BAABNQAECn9NAAIZAAoKtBjEJQBMAgAZAAoKtBjEJQBMAgAAAA==.Keihas:BAAANQAECgcIEwAAAA==.Kermitt:BAAANQAECgMIAwAAAA==.',
Ki='Kikko:BAACNQAFFH8IAAIUAAMKixxjFwAJAQAUAAMKixxjFwAJAQA1AAQKfyYAAhQACQppJNIcAB0DABQACQppJNIcAB0DAAAA.Kikkomouse:BAAANQAECgUICgABNQAFFAMICAAUAIscAA==.',
Ko='Kobane:BAAANQAECgEIBQAAAA==.Konkine:BAAANQABCgEIAQAAAA==.Kozanu:BAAANQADCgYIBgAAAA==.',
Ku='Kujara:BAAANQADCgMIAwAAAA==.Kurando:BAAANQAECggICwABNQAECgoKNwAJADEfAA==.Kurrindor:BAABNQAECn8gAAMXAAgK6B+0EACTAgAXAAgK6B+0EACTAgAJAAEKIR5/gwFVAAAAAA==.',
Ly='Lylith:BAAANQADCggIFAAAAA==.',
Ma='Macheon:BAAANQAECgEIAgAAAA==.Madashell:BAAANQADCgcIDAAAAA==.Maerwyn:BAAANQADCggJDQAAAA==.Magenub:BAABNQAECn8+AAIaAAoK5iFeDAD1AgAaAAoK5iFeDAD1AgAAAA==.Malexling:BAABNQAECn8nAAIJAAcKFBZhbwB1AQAJAAcKFBZhbwB1AQAAAA==.Masa:BAACNQAFFH8JAAINAAUK3RkSAgDNAAANAAUK3RkSAgDNAAA1AAQKfygAAw0ACgq3HvQGAPECAA0ACgq3HvQGAPECAAIAAwpWETWkAMMAAAAA.Matt:BAAANQAECgEIAQAAAA==.Mawe:BAAANQAECgEJBAAAAA==.',
Mi='Mistie:BAAANQABCgIIAgABNQAECgUJDAAbAAAAAA==.Mistlee:BAAANQAECgEIAgAAAA==.Mitternacht:BAABNQAECn9LAAIUAAoKyByKIwD5AgAUAAoKyByKIwD5AgAAAA==.',
Mo='Moggo:BAAANQADCgQIBwAAAA==.Moodew:BAABNQAECn8sAAIEAAkKgRmmGgBrAgAEAAkKgRmmGgBrAgAAAA==.',
Ms='Msdeath:BAABNQAECn8oAAITAAcKch9GDADxAQATAAcKch9GDADxAQAAAA==.',
My='Mya:BAAANQABCgQIBwAAAA==.Mykeroni:BAAANQADCgMIAwAAAA==.Myraku:BAAANQADCggIDAABNQAECgYIFwAHAKsGAA==.',
Na='Nachiko:BAAANQADCgMIAwAAAA==.Naois:BAAANQAECgQIDAABNQAECgoKNwAJADEfAA==.Nashalion:BAABNQAECn8iAAMBAAoKrRXyGAAIAgABAAoKrRXyGAAIAgAFAAEK8gGc5QAZAAAAAA==.',
Ne='Nemlock:BAAANQAECgEIAQABNQAECgcIFwAaALcEAA==.',
Ni='Nickchurch:BAAANQAECgIIAgAAAA==.Nidorhina:BAAANQABCgQIAwAAAA==.',
No='Nodarf:BAABNQAECn8uAAIcAAkKtA/7DgC9AQAcAAkKtA/7DgC9AQAAAA==.Norielin:BAAANQADCgQIBwAAAA==.',
Ok='Okayheals:BAABNQAECn8zAAIEAAkKwQo7ggCFAQAEAAkKwQo7ggCFAQAAAA==.',
Ol='Olumine:BAAANQAECgEIAgAAAA==.',
Or='Orin:BAAANQAECgEIAQAAAA==.',
Ot='Otherhandish:BAAANQAECgEIAQAAAA==.',
Pa='Panda:BAACNQAFFH8ZAAQZAAcKch32DgBoAQAVAAQKLR3TAAB6AQAZAAUKkRr2DgBoAQAdAAMKOA3RFgDUAAA1AAQKf0AABBkACgrYJdoJAAYDABkACgqFItoJAAYDABUACAoKJYYEAJkCAB0ACAqHIe0ZAIcCAAAA.',
Ph='Phuzzi:BAAANQAECggICAAAAA==.',
Pi='Picolás:BAABNQAECn8cAAIaAAYKHBht6wCzAQAaAAYKHBht6wCzAQAAAA==.',
Pr='Preacharound:BAAANQABCgMIAwAAAA==.Primrose:BAABNQAECn8oAAIDAAoKYxzGHAB6AgADAAoKYxzGHAB6AgAAAA==.Probono:BAABNQAECn8YAAISAAcKHgi6JgDRAAASAAcKHgi6JgDRAAAAAA==.',
Qu='Quarian:BAAANQADCggICAAAAA==.',
Qw='Qwing:BAAANQAECgUIBgABNQAECgoKIgABAK0VAA==.',
Ra='Rainee:BAAANQADCgQIAwAAAA==.Raxefal:BAABNQAECn8pAAQMAAkK1gwLCwDiAAAMAAUKPwsLCwDiAAAHAAYK0gwIiQDgAAALAAMK1wv7RwCoAAAAAA==.',
Re='Reptar:BAAANQAECgYICwABNQAFFAYIGQAeABQcAA==.Restdrag:BAAANQADCgYIBgAAAA==.Rezø:BAABNQAECn8yAAMDAAoKMhuEFwCnAgADAAoKMhuEFwCnAgASAAgKxBSGKgDTAQAAAA==.',
Ro='Roadkilldk:BAABNQAECn8cAAMBAAcKSQxlUwBiAQABAAcKSQxlUwBiAQAFAAEKxwJ04gAcAAAAAA==.',
['Rä']='Rägæ:BAAANQAECgEIAQAAAA==.',
Sa='Sableye:BAABNQAECn80AAIfAAoKXxuwFQC2AgAfAAoKXxuwFQC2AgAAAA==.Saguero:BAEBNQAECn82AAMEAAoKHBwVHgBSAgAEAAoKHBwVHgBSAgAUAAkKog7gaADmAQAAAA==.Satmorii:BAAANQABCggIEQAAAA==.',
Sc='Schatten:BAAANQAECgUIBQABNQAECggIGAANAP8YAA==.Schithappens:BAAANQABCgMIAwAAAA==.Scruffy:BAAANQAECgEIAQAAAA==.',
Se='Selina:BAABNQAECn8XAAMaAAoKtBhoLABBAgAaAAkKuhRoLABBAgAgAAgKKxmyDADtAQAAAA==.Senortickle:BAABNQAECn8WAAIYAAoKTyQsBAB4AgAYAAoKTyQsBAB4AgAAAA==.',
Sh='Shaunara:BAAANQAECgEIAgABNQAFFAQICgAFAAYgAA==.Shinoitamis:BAAANQAECggICgABNQAECgkJQQAJAIUfAA==.Shinotenshi:BAABNQAECn9BAAIJAAkKhR9QJAA0AwAJAAkKhR9QJAA0AwAAAA==.Shìva:BAAANQADCggICAAAAA==.Shînon:BAAANQAECgMIAwABNQAECgoKMgADADIbAA==.',
Si='Siphin:BAAANQAECggICQAAAA==.',
So='Solar:BAAANQAECgIIBAABNQAFFAMIBwAeAPYLAA==.Solàire:BAABNQAECn8uAAMIAAkKSwoRfwCcAQAIAAkKSwoRfwCcAQAJAAUKcAmw0QDAAAAAAA==.Sonicice:BAAANQADCgQIAQAAAA==.',
Sp='Spacewafflez:BAAANQAECgIIBAAAAA==.',
St='Starburnz:BAAANQADCgMIAwABNQAECgoKLQAGAM4aAA==.Stimutax:BAAANQAECgIIBQAAAA==.',
Ta='Tamborine:BAAANQAECgEIAgAAAA==.Taurenvar:BAABNQAECn88AAIhAAoKcCE+AgCKAwAhAAoKcCE+AgCKAwAAAA==.',
Te='Teddyhappy:BAAANQAECgcICAAAAA==.',
Th='Thekeres:BAAANQAECgQICQAAAA==.',
To='Tora:BAAANQAECgYJBwAAAA==.',
Tr='Trollbrudda:BAABNQAECn9KAAMeAAoKZyB0DgBWAwAeAAoKZyB0DgBWAwATAAMKuBeHPwC9AAAAAA==.',
Um='Umgross:BAAANQADCgYIBgAAAA==.',
Un='Unholygrudge:BAAANQADCgIIAgAAAA==.',
Ve='Velenus:BAAANQAECgMIBQAAAA==.Vesperion:BAAANQADCgQICgABNQAECgkJKQAMANYMAA==.',
Vi='Vickdak:BAAANQAECgEIAQAAAA==.Vilehatred:BAAANQAECgYICgAAAA==.',
Vo='Voltz:BAAANQAECgEIAQAAAA==.',
Wa='Wallis:BAABNQAECn8XAAIaAAcKtwQCtwDZAAAaAAcKtwQCtwDZAAAAAA==.Warmoz:BAABNQAECn8YAAINAAgK/xgAEAApAgANAAgK/xgAEAApAgAAAA==.',
Wu='Wunhunglo:BAAANQABCgQIBAAAAA==.',
Xe='Xergiator:BAABNQAECn8oAAIZAAkKowh7uwCMAQAZAAkKowh7uwCMAQAAAA==.',
Za='Zaligator:BAABNQAECn8kAAQiAAgKEBXBDACGAQAjAAgKChSAGADAAQAiAAcKvBHBDACGAQAkAAEK8ggtMQAkAAAAAA==.Zarideyne:BAAANQAECgEIAQAAAA==.',
Zo='Zombinized:BAAANQADCgUIBQAAAA==.',
Zu='Zuulian:BAABNQAECn8tAAQGAAoKzhrvCgD1AQAGAAoKzhrvCgD1AQARAAMKBQc2PQBjAAAlAAEKAAD8NAAjAAAAAA==.',
Zy='Zylph:BAABNQAECn8XAAIHAAYKqwaG3AAQAQAHAAYKqwaG3AAQAQAAAA==.',
['Ín']='Ínnothule:BAAANQAECgMIBAAAAA==.',
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
