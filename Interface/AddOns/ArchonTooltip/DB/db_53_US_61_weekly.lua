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

local lookup = {'DeathKnight-Frost','Hunter-BeastMastery','Shaman-Elemental','Paladin-Protection','Warlock-Demonology','Unknown-Unknown','Hunter-Marksmanship','Hunter-Survival','DeathKnight-Blood','Shaman-Restoration','Warrior-Fury','Warrior-Arms','Priest-Discipline','Paladin-Retribution','DeathKnight-Unholy','Warrior-Protection','DemonHunter-Devourer','Rogue-Subtlety','Priest-Holy','Priest-Shadow','Monk-Brewmaster','Monk-Windwalker','DemonHunter-Havoc','Druid-Balance','Mage-Arcane','Warlock-Affliction','Warlock-Destruction','Evoker-Devastation','Paladin-Holy','Druid-Restoration','Monk-Mistweaver','Rogue-Outlaw','Shaman-Enhancement','Mage-Frost','Evoker-Augmentation','Rogue-Assassination',}
local provider = {region='US',realm='Darrowmere',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abaddonmoon:BAABNQAECn8+AAIBAAoKWw7tOADxAQABAAoKWw7tOADxAQAAAA==.Absolute:BAAANQADCgQIBAAAAA==.',
Ah='Ahnari:BAACNQAFFH8MAAICAAUKMxHqEwDiAAACAAUKMxHqEwDiAAA1AAQKf0gAAgIACgpIHyscAMUCAAIACgpIHyscAMUCAAAA.',
Ai='Ailinaa:BAAANQAECgIIAgAAAA==.',
Al='Alerat:BAAANQADCggIDgABNQAECgoKKAADAAEMAA==.Alistìn:BAABNQAECn8eAAIEAAgK4B4NEQCOAgAEAAgK4B4NEQCOAgAAAA==.Alistín:BAAANQAECgQIBgAAAA==.Allahwe:BAAANQAECgEIAgAAAA==.Allo:BAAANQAECgUICwAAAA==.Alìstin:BAAANQADCgYIBgAAAA==.',
Am='Ameri:BAAANQAECgYIDgAAAA==.',
An='Annalistiana:BAABNQAECn87AAIFAAoKyxOUQgD8AQAFAAoKyxOUQgD8AQABNQAECgUICgAGAAAAAA==.',
Ap='Apiphone:BAAANQABCgQIBAAAAA==.',
Ar='Aradin:BAAANQAECgQIBwAAAA==.Archanfel:BAABNQAECn8tAAMHAAoK0goCIwA+AQAHAAoK0goCIwA+AQAIAAEKAACLFQAAAAAAAA==.Argasha:BAAANQAECgQICQAAAA==.Aro:BAAANQADCggICAABNQAECgQICQAGAAAAAA==.Artemesya:BAAANQAECgEIAgAAAA==.',
Ay='Ayurvedas:BAAANQADCgYIBgAAAA==.',
Az='Azaadi:BAEANQADCgYIBgABNQAECgYIFgAJAOISAA==.',
Ba='Bandie:BAABNQAECn8WAAMKAAYKjQ6IkgDrAAAKAAYKjQ6IkgDrAAADAAEK7gUlAwEkAAAAAA==.Bashan:BAAANQADCgEIAQAAAA==.Bayn:BAAANQABCggIFwAAAA==.',
Be='Beeftruck:BAABNQAECn81AAMLAAoKPBfGDQCMAQAMAAoKvBYnWADjAQALAAgKBRXGDQCMAQAAAA==.Berried:BAABNQAECn9VAAINAAoKdBkQAgC7AgANAAoKdBkQAgC7AgAAAA==.',
Bi='Bigred:BAABNQAECn8VAAIOAAUKsgamLAHWAAAOAAUKsgamLAHWAAAAAA==.Biminem:BAAANQADCgYIBgAAAA==.Bitomax:BAAANQAECgQICQAAAA==.',
Bl='Blað:BAAANQADCgEIAQAAAA==.Bloôdymary:BAAANQAECgUIEwAAAA==.',
Br='Brakun:BAAANQAECgUIBwAAAA==.Brewer:BAAANQADCgQIBAAAAA==.Brienne:BAAANQAECgIIAgAAAA==.Briline:BAAANQADCgQIBAAAAA==.Brolly:BAABNQAECn8ZAAICAAoKAQPq1ADtAAACAAoKAQPq1ADtAAAAAA==.',
Ca='Calamari:BAAANQADCgQIBAAAAA==.Camine:BAABNQAECn9BAAIPAAoK7xpNMQBoAgAPAAoK7xpNMQBoAgAAAA==.Capmurica:BAABNQAECn8dAAMEAAcKZgqhMQDeAAAEAAcKZgqhMQDeAAAOAAEKkwN7xgElAAAAAA==.Castadrood:BAAANQAECgUIDwAAAA==.Cates:BAAANQADCgUIBQAAAA==.',
Ch='Choppstik:BAAANQADCgQIBAAAAA==.',
Co='Cocstrong:BAAANQAECggIBwAAAA==.Coriolis:BAAANQAECgUICgAAAA==.',
Cr='Craano:BAAANQABCgQIBAABNQAECgEIAQAGAAAAAA==.',
Da='Dagdag:BAAANQAECgIIAQAAAA==.Dagnamagus:BAAANQADCgUIBwAAAA==.',
De='Deathcokie:BAAANQAECgUIDAAAAA==.Deatho:BAABNQAECn84AAMQAAoKhyYyAAACBAAQAAoKeyYyAAACBAAMAAcKzRvZXADUAQAAAA==.Dedtho:BAAANQAECggIEAABNQAECgoKOAAQAIcmAA==.Deermeat:BAAANQAECgUICAAAAA==.Deimos:BAABNQAECn8UAAQJAAcKmBR4RwASAQAJAAUKmBd4RwASAQABAAUKPQisjQCAAAAPAAEKAADx9QAhAAAAAA==.',
Di='Diamondshard:BAAANQAECgEIAgAAAA==.Diviniah:BAAANQADCgYIBgAAAA==.',
Do='Dotdotcurse:BAAANQADCggICAAAAA==.',
Dr='Drash:BAAANQAECgIIBQAAAA==.Dreadful:BAABNQAECn8lAAIRAAoK8RTbIwApAgARAAoK8RTbIwApAgAAAA==.Dreyra:BAAANQAECgQIBQABNQAECgoKJAAIAOEXAA==.Droodtrass:BAAANQAECgQICAAAAA==.Drunksausage:BAAANQAECgEIAQAAAA==.',
Du='Duncan:BAAANQAECgUIBgABNQAECgoKLwAMADcIAA==.',
Dy='Dymetrius:BAAANQAECgMIAwAAAA==.',
['Dö']='Döctorfate:BAABNQAECn9EAAISAAoKNA4bHgDhAQASAAoKNA4bHgDhAQAAAA==.',
Ed='Ediela:BAAANQADCgEIAQAAAA==.',
Ef='Effinsoldier:BAAANQAECgUIEAAAAA==.',
El='Elix:BAAANQADCgEIAQAAAA==.Elixir:BAAANQAECgEIAgAAAA==.Elvira:BAABNQAECn8bAAIFAAoKGgnXpACLAQAFAAoKGgnXpACLAQAAAA==.',
En='Endlessagony:BAAANQAECgYIDQAAAA==.Endwa:BAAANQAECgIIAgAAAA==.',
Ep='Epsicarinae:BAAANQAECgEIAQAAAA==.',
Er='Erel:BAAANQAECgUICAAAAA==.Eridrel:BAABNQAECn8kAAMTAAkKVgwbVgDNAQATAAkKVgwbVgDNAQAUAAUKVgaaUgDFAAAAAA==.',
Fa='Fasriel:BAAANQAECgEIBQAAAA==.',
Fi='Fiyero:BAABNQAECn8vAAIMAAoKNwi3sgCeAQAMAAoKNwi3sgCeAQAAAA==.',
Fl='Fleabath:BAAANQADCggIDgABNQAECgkJKQACAIAOAA==.',
Fu='Fury:BAABNQAECn9UAAMLAAoKNCRGAgBdAwALAAoKsCBGAgBdAwAMAAcKKB3tfAAiAgAAAA==.',
Ga='Galdames:BAABNQAECn8mAAICAAoKjyL/FgA+AwACAAoKjyL/FgA+AwAAAA==.Gandolphgrey:BAAANQAECgUICwAAAA==.Gasai:BAAANQADCggICAAAAA==.',
Ge='Gertluzgin:BAAANQAECggIEQAAAA==.',
Gi='Gilforty:BAAANQAECgEIAgAAAA==.',
Go='Gonk:BAABNQAECn8WAAIVAAoKghAUEQDXAQAVAAoKghAUEQDXAQAAAA==.',
Gr='Gripnkill:BAABNQAECn9pAAMBAAoKfBzUJQBmAgABAAgKLhrUJQBmAgAJAAoKbBmsMABOAgAAAA==.',
Gu='Gump:BAAANQAECgQIBwABNQAECgoKNQALADwXAA==.',
Gv='Gvendalyn:BAABNQAECn9OAAICAAoKZiY2AgDkAwACAAoKZiY2AgDkAwAAAA==.',
Gy='Gyatsò:BAABNQAECn8uAAIWAAkKahsVFwCUAgAWAAkKahsVFwCUAgAAAA==.',
Ha='Harshc:BAABNQAECn8ZAAITAAkKeRBWkwBcAQATAAkKeRBWkwBcAQABNQAECgkJHgAXADkSAA==.Harshdh:BAABNQAECn8eAAIXAAkKORI3LACYAQAXAAkKORI3LACYAQAAAA==.Hashirama:BAAANQAECggICAAAAA==.',
He='Helapa:BAAANQAECgMIBQAAAA==.Helel:BAABNQAECn9aAAMPAAoKOiJnEwAdAwAPAAoKDSJnEwAdAwAJAAoKCRtdHgC/AgAAAA==.',
Ho='Hops:BAAANQAECggICwAAAA==.',
Ip='Ipokeu:BAAANQADCgUIBQAAAA==.',
Ja='Jabohabo:BAABNQAECn8qAAIMAAoKuyGSGQBSAwAMAAoKuyGSGQBSAwAAAA==.Jaffy:BAAANQAECggIEwAAAA==.Jamninja:BAAANQAECgEIAQAAAA==.Javamaster:BAAANQADCgIIAgAAAA==.Jaxxson:BAABNQAECn8VAAIKAAcKSR4FRQBNAgAKAAcKSR4FRQBNAgAAAA==.',
Je='Jellyfish:BAAANQAECgEIAgAAAA==.Jeriko:BAAANQADCgQIBAAAAA==.Jessamyn:BAAANQAECgQIBgAAAA==.',
Jh='Jhoira:BAAANQABCgIIAgAAAA==.',
Jo='Jordyy:BAABNQAECn8VAAIFAAgKrhkkTABvAgAFAAgKrhkkTABvAgAAAA==.',
Ka='Kalifa:BAACNQAFFH8UAAIYAAYKUhv6CQBMAQAYAAYKUhv6CQBMAQA1AAQKfzUAAhgACgrlJMkDAFADABgACgrlJMkDAFADAAAA.Karrod:BAAANQAECgIIAgAAAA==.Kayohs:BAABNQAECn8vAAIZAAoKAg3paADRAQAZAAoKAg3paADRAQAAAA==.',
Kh='Khrysus:BAABNQAECn8sAAIWAAoKVw9uKQDSAQAWAAoKVw9uKQDSAQAAAA==.',
Ki='Kiv:BAACNQAFFH8IAAIFAAQKWRBhGQDMAAAFAAQKWRBhGQDMAAA1AAQKfzkABBoACgrAIbsDAGACAAUACgojIE4iAPsCABoACgqYHrsDAGACABsAAQqdFxluAEIAAAAA.Kiwaj:BAAANQAECgEIAQABNQAECgQJCgAGAAAAAA==.',
Kn='Knoa:BAAANQAECgEIBQAAAA==.',
Ko='Kodachi:BAAANQAECgcIEwAAAA==.Kokopelli:BAAANQAECgEIAQAAAA==.Komayetu:BAAANQAECgUIBQAAAA==.',
Kr='Krashed:BAAANQAECgEIAgAAAA==.Krateis:BAAANQAECgEIAQAAAA==.',
Ku='Kunfool:BAAANQAECgEIAQAAAA==.',
Kv='Kvit:BAAANQAECgMIBQAAAA==.',
Ky='Kyoki:BAABNQAECn80AAIcAAoKFg7qFAD+AQAcAAoKFg7qFAD+AQAAAA==.',
La='Laberynt:BAAANQAECgYIBgAAAA==.Lazyace:BAAANQAECgIIBAAAAA==.',
Li='Liendrel:BAAANQABCgYIBgAAAA==.',
Ly='Lyset:BAAANQADCgEIAQABNQAECgMIBQAGAAAAAA==.',
Ma='Maeze:BAABNQAECn8pAAICAAkKgA6vjACBAQACAAkKgA6vjACBAQAAAA==.Malandru:BAACNQAFFH8WAAMOAAYKdBIqEwAiAQAOAAQKKRMqEwAiAQAdAAUKSA15FAAbAQA1AAQKfzUAAx0ACgrCGtYoAMUCAB0ACQpgHdYoAMUCAA4AAwp7IpEKAQ0BAAAA.Mawwow:BAABNQAECn9GAAIOAAoKWCVQEAAkAwAOAAoKWCVQEAAkAwAAAA==.',
Me='Meatfingers:BAAANQAECgEIAQAAAA==.Meekah:BAACNQAFFH8MAAITAAUKCgoNFQBGAQATAAUKCgoNFQBGAQA1AAQKfzAAAxMACgq7DPpwAMoBABMACgq7DPpwAMoBAA0AAwqXB14dAHcAAAAA.Melyndia:BAAANQADCggICgABNQAFFAIIBgAeAPcTAA==.Meriks:BAAANQADCgYIBgABNQAFFAMIBgARAPMhAA==.',
Mi='Mickfurry:BAAANQAECggIDAABNQAFFAcIFgAfADMbAA==.Micksippy:BAACNQAFFH8WAAIfAAcKMxt5AgD3AQAfAAcKMxt5AgD3AQA1AAQKfzkAAx8ACgpXJMsDAHIDAB8ACgpXJMsDAHIDABUABAruCZAbAHsAAAAA.Milamber:BAAANQAECgYICwAAAA==.Milfy:BAAANQADCgQJBAABNQAECgQICQAGAAAAAA==.',
Mu='Muriggy:BAAANQAECgEIAQAAAA==.',
My='Mylarna:BAABNQAECn8oAAIDAAoKAQwvdwC8AQADAAoKAQwvdwC8AQAAAA==.Mynx:BAABNQAECn8gAAIHAAoKGBeSGACyAQAHAAoKGBeSGACyAQAAAA==.',
Mz='Mzivvee:BAAANQADCgMIAgABNQAECgYIFAAgAMISAA==.',
Na='Nargo:BAAANQAECgQIBwAAAA==.Nashea:BAAANQADCgcJEAAAAA==.',
Ne='Neltharis:BAAANQABCgQIBAAAAA==.Neona:BAAANQADCgUIBwAAAA==.',
Ni='Nixii:BAABNQAECn8xAAIYAAoKqRMbOwAbAgAYAAoKqRMbOwAbAgAAAA==.',
No='Nocticula:BAABNQAECn9GAAITAAoK8g5FRgAJAgATAAoK8g5FRgAJAgAAAA==.',
Ny='Nyalota:BAAANQADCggIFAAAAA==.Nyet:BAABNQAECn8VAAMLAAgKPRIKHQCvAAAMAAcKlhCzxABxAQALAAMKqxYKHQCvAAAAAA==.',
Og='Ogucci:BAAANQADCggICAAAAA==.',
Ok='Oktoberfist:BAAANQAECgEIAQABNQAFFAUIEQAYAGkNAA==.',
Op='Opalauria:BAAANQAECgQIBAAAAA==.',
Or='Orgullo:BAAANQAECgMIAwAAAA==.Orine:BAAANQAECggICgAAAA==.Orion:BAAANQAECggIDAAAAA==.Orioz:BAACNQAFFH8QAAIhAAYKvB5gAQBfAQAhAAYKvB5gAQBfAQA1AAQKf0cAAiEACgqCJREBAGEDACEACgqCJREBAGEDAAAA.',
Oz='Oz:BAABNQAECn81AAIFAAoKJyGSEgDUAgAFAAoKJyGSEgDUAgAAAA==.',
Pa='Pakali:BAAANQABCgMIAgAAAA==.Paladinhalos:BAAANQADCgcIDQAAAA==.Paladinsan:BAAANQAECgQIEQABNQAECgoKJgACAI8iAA==.',
Ph='Phobos:BAAANQADCgIIAgABNQAECgcIFAAJAJgUAA==.',
Pi='Pillowprince:BAAANQAECggICAAAAA==.',
Po='Police:BAAANQADCgUIBQABNQAECgoKKwAKAMEfAQ==.',
Ps='Psychomurda:BAAANQADCgYIBgABNQAFFAUIDAATAAoKAA==.',
Pu='Punches:BAAANQAECggIAwAAAA==.',
Py='Pytheas:BAAANQADCgYIBgABNQAECgcIFAAJAJgUAA==.',
Ra='Radio:BAABNQAECn8WAAIOAAoKQB0BXAAMAgAOAAoKQB0BXAAMAgAAAA==.Raistlin:BAAANQAECggIDQABNQAFFAUIEQAYAGkNAA==.',
Re='Renfri:BAABNQAECn8aAAIiAAkKogu/DwB2AQAiAAkKogu/DwB2AQAAAA==.',
Ro='Robel:BAAANQAECgQICwAAAA==.Roflburger:BAABNQAECn8fAAIhAAkKaRS4EQDjAQAhAAkKaRS4EQDjAQAAAA==.Rovox:BAAANQAECgQJCgAAAA==.',
Sa='Sadness:BAAANQAECgEIAQAAAA==.Sardrian:BAAANQAECgcIDAAAAA==.Saî:BAAANQADCgYIBgAAAA==.',
Sc='Scarletwrath:BAAANQADCgYICwAAAA==.',
Se='Seika:BAAANQAECgEIAwAAAA==.Seimie:BAABNQAECn8xAAIbAAgK6gVvEADHAAAbAAgK6gVvEADHAAAAAA==.Senethotsare:BAAANQADCgUIBwAAAA==.',
Sg='Sgaeyl:BAAANQAECgMIAwAAAA==.',
Sh='Shaboudi:BAAANQAECgQIBAABNQAECgoKFgAVAIIQAA==.Shammwow:BAABNQAECn8VAAIDAAgK5wJ7xQAHAQADAAgK5wJ7xQAHAQAAAA==.Sherryl:BAABNQAECn9EAAIeAAoKpRLnGgAXAgAeAAoKpRLnGgAXAgAAAA==.',
Si='Siddharthä:BAABNQAECn8jAAIOAAoKlhEYiACnAQAOAAoKlhEYiACnAQAAAA==.',
Sk='Skdragon:BAABNQAECn8hAAMcAAkKfRtREQA/AgAcAAgKJB5REQA/AgAjAAUKWA1cEwD7AAAAAA==.Skyara:BAAANQAECgYICgABNQAECgoKNAAUANkfAA==.Skylaar:BAAANQAECgQIBAAAAA==.',
Sm='Smitey:BAAANQAECgMIAwAAAA==.',
So='Soulstik:BAAANQADCgcIDQAAAA==.',
Sp='Spiritshard:BAAANQAECgEIBAAAAA==.Spriggens:BAAANQAECgcIEQABNQAECgoKTgACAGYmAA==.',
St='Stalkr:BAAANQADCgQIBAAAAA==.Sthise:BAAANQAECgMIAwAAAA==.',
Sy='Sykoman:BAACNQAFFH8aAAIYAAgKfRnGBABfAgAYAAgKfRnGBABfAgA1AAQKfywAAhgACgpdJVQNAGADABgACgpdJVQNAGADAAAA.Sykowoman:BAAANQAECgQJBAABNQAFFAgIGgAYAH0ZAA==.',
['Sì']='Sìleñtclãw:BAAANQADCgEIAQAAAA==.Sìrius:BAAANQAECgEIAQAAAA==.',
Te='Terumi:BAAANQAECgQICAAAAA==.',
Th='Theodrei:BAAANQABCgQIBwAAAA==.Thiizz:BAABNQAECn84AAIPAAoKhBxWEgBXAgAPAAoKhBxWEgBXAgAAAA==.Thracious:BAAANQADCgUIBwAAAA==.Thïzz:BAAANQAECgUIDgABNQAECgoKKgAMALshAA==.',
Ti='Ticklemebutt:BAAANQAECgUIEAAAAA==.Tinksy:BAAANQADCgYIBgABNQAECgQICQAGAAAAAA==.Titanx:BAAANQADCgMJBAAAAA==.',
To='Toeto:BAAANQAECgQIBQAAAA==.Toetoeto:BAAANQAECgcIEQAAAA==.Toetoetoete:BAAANQADCgcJCAAAAA==.Tooe:BAAANQAECgQIEgAAAA==.Torquei:BAAANQAECgcIEQAAAA==.Toxan:BAAANQADCgUIBgAAAA==.',
Tp='Tpaman:BAAANQADCgMIBAAAAA==.',
Tr='Triks:BAABNQAECn8YAAMgAAcKdBZQCgDXAQAgAAcKdBZQCgDXAQAkAAEKcgOjqgAmAAAAAA==.',
Ts='Tsjudilla:BAAANQADCgQJBAAAAA==.',
Tu='Tujefe:BAABNQAECn8uAAIFAAkKnhQfawAcAgAFAAkKnhQfawAcAgAAAA==.',
Ty='Tylorialin:BAAANQADCgMIAwABNQAECgoKNQALADwXAA==.',
Ur='Urpalharsh:BAAANQADCgIIAgABNQAECgkJHgAXADkSAA==.',
Va='Vahldire:BAAANQAECgQICwAAAA==.Valeeraa:BAABNQAECn8hAAMkAAoKWAkIGgBMAQAkAAkK3gkIGgBMAQAgAAYKuQXAEwDBAAAAAA==.Valeri:BAAANQADCgcIBwAAAA==.Varken:BAAANQAECgMIAwAAAA==.',
Ve='Veresa:BAAANQAECgEIAwAAAA==.',
Vo='Voidwrath:BAAANQAECgYIBgAAAA==.',
Wa='Waeder:BAAANQADCgcIFwAAAA==.Waren:BAAANQAECgMIAwAAAA==.',
Wi='Wingman:BAAANQAECgQIBwAAAA==.Wisteria:BAABNQAECn83AAQbAAoKlhKpFQDAAQAbAAcK/gypFQDAAQAFAAkKKw8PcwBsAQAaAAEKSQOTNAAoAAABNQAECgcIFAAJAJgUAA==.',
Wo='Wompalicious:BAAANQADCgEIAQABNQAECggIFQAZABwDAA==.Wompalot:BAAANQADCggIDwABNQAECggIFQAZABwDAA==.Wompeter:BAABNQAECn8VAAIZAAgKHAMbxAANAQAZAAgKHAMbxAANAQAAAA==.Womplock:BAAANQADCgYICwAAAA==.Wompnhood:BAAANQAECgIIBAABNQAECggIFQAZABwDAA==.Wooly:BAAANQADCgMIAwAAAA==.',
Wr='Wrâth:BAABNQAECn8kAAIZAAgKlw370QDiAQAZAAgKlw370QDiAQAAAA==.',
Xa='Xael:BAAANQAECgUICwAAAA==.',
Xu='Xunarii:BAAANQADCgUIBQABNQAECgoKNAAUANkfAA==.',
Za='Zalus:BAAANQADCgYICgAAAA==.Zaymaa:BAAANQAECgEIAQAAAA==.',
Ze='Zeal:BAAANQAECgQICQAAAA==.Zenatria:BAAANQADCgcICwAAAA==.',
Zi='Zindetra:BAAANQAECgMIAwAAAA==.',
Zo='Zorana:BAAANQAECgQIBQAAAA==.',
['Ów']='Ówl:BAAANQADCgUIDwAAAA==.',
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
