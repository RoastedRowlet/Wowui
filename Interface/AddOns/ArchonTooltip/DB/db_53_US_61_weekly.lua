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

local lookup = {'DeathKnight-Frost','Hunter-BeastMastery','Shaman-Elemental','Paladin-Protection','Warlock-Demonology','Unknown-Unknown','Hunter-Marksmanship','Warrior-Arms','Priest-Discipline','DeathKnight-Unholy','Warrior-Protection','DemonHunter-Devourer','Warrior-Fury','Rogue-Subtlety','DeathKnight-Blood','Monk-Windwalker','Druid-Balance','Warlock-Affliction','Warlock-Destruction','Evoker-Devastation','Paladin-Retribution','Paladin-Holy','Priest-Holy','Druid-Restoration','Monk-Mistweaver','Shaman-Enhancement','Shaman-Restoration','Priest-Shadow','Mage-Arcane',}
local provider = {region='US',realm='Darrowmere',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abaddonmoon:BAABNQAECn8iAAIBAAkK+g3bNwDxAQABAAkK+g3bNwDxAQAAAA==.',
Ah='Ahnari:BAACNQAFFH8FAAICAAMKbwJiHQDBAAACAAMKbwJiHQDBAAA1AAQKfysAAgIACQrlEXNbAF8CAAIACQrlEXNbAF8CAAAA.',
Ai='Ailinaa:BAAANQAECgIIAgAAAA==.',
Al='Alerat:BAAANQADCggIDgABNQAECggIHwADAHwNAA==.Alistìn:BAABNQAECn8aAAIEAAgK4B7WEACPAgAEAAgK4B7WEACPAgAAAA==.Alistín:BAAANQAECgQIBgAAAA==.Allahwe:BAAANQADCggICAAAAA==.Allo:BAAANQADCggICQAAAA==.Alìstin:BAAANQADCgYIBgAAAA==.',
Am='Ameri:BAAANQAECgYICgAAAA==.',
An='Annalistiana:BAABNQAECn8dAAIFAAkK0w5oXgA5AgAFAAkK0w5oXgA5AgABNQAECgUICAAGAAAAAA==.',
Ap='Apiphone:BAAANQABCgQIBAAAAA==.',
Ar='Aradin:BAAANQAECgEIAwAAAA==.Archanfel:BAABNQAECn8cAAIHAAgKGgzOMwCrAQAHAAgKGgzOMwCrAQAAAA==.Argasha:BAAANQAECgQIBgAAAA==.Aro:BAAANQADCggICAABNQAECgQICAAGAAAAAA==.',
Ay='Ayurvedas:BAAANQADCgYIBgAAAA==.',
Az='Azaadi:BAEANQADCgYIBgABNQAECgMIBQAGAAAAAA==.',
Ba='Bandie:BAAANQAECgUIDAAAAA==.Bashan:BAAANQADCgEIAQAAAA==.Bayn:BAAANQABCggIFwAAAA==.',
Be='Beeftruck:BAABNQAECn8dAAIIAAkKcRGrcQA7AgAIAAkKcRGrcQA7AgAAAA==.Berried:BAABNQAECn8wAAIJAAkK2hbMBABwAgAJAAkK2hbMBABwAgAAAA==.',
Bi='Bigred:BAAANQAECgUIDAAAAA==.Biminem:BAAANQADCgYIBgAAAA==.Bitomax:BAAANQAECgQIBQAAAA==.',
Bl='Blað:BAAANQADCgEIAQAAAA==.Bloôdymary:BAAANQAECgQICAAAAA==.',
Br='Brewer:BAAANQADCgQIBAAAAA==.Briline:BAAANQADCgQIBAAAAA==.',
Ca='Calamari:BAAANQADCgQIBAAAAA==.Camine:BAABNQAECn8sAAIKAAgKKBq/MABoAgAKAAgKKBq/MABoAgAAAA==.Capmurica:BAAANQAECgMICQAAAA==.Castadrood:BAAANQAECgIIAgAAAA==.Cates:BAAANQADCgUIBQAAAA==.',
Ch='Choppstik:BAAANQADCgQIBAAAAA==.',
Co='Cocstrong:BAAANQAECggIBwAAAA==.Coriolis:BAAANQAECgUICAAAAA==.',
Cr='Craano:BAAANQABCgQIBAABNQADCggIFwAGAAAAAA==.',
Da='Dagdag:BAAANQAECgIIAQAAAA==.Dagnamagus:BAAANQADCgUIBwAAAA==.',
De='Deathcokie:BAAANQAECgUICgAAAA==.Deatho:BAABNQAECn8tAAMLAAkK0CYwAAADBAALAAkK0CYwAAADBAAIAAIKphyDHwGTAAAAAA==.Deimos:BAAANQAECgMIAwAAAA==.',
Di='Diamondshard:BAAANQADCgUICgAAAA==.Diviniah:BAAANQADCgYIBgAAAA==.',
Do='Dotdotcurse:BAAANQADCggICAAAAA==.',
Dr='Drash:BAAANQAECgIIAwAAAA==.Dreadful:BAABNQAECn8fAAIMAAgKnBV+IwAqAgAMAAgKnBV+IwAqAgAAAA==.Dreyra:BAAANQADCggIJwABNQAECggIIwANAPUbAA==.Droodtrass:BAAANQAECgQICAAAAA==.Drunksausage:BAAANQABCgQIBAAAAA==.',
Du='Duncan:BAAANQAECgQIBAABNQAECggIKgAIABUJAA==.',
['Dö']='Döctorfate:BAABNQAECn8qAAIOAAgKrgy+HQDhAQAOAAgKrgy+HQDhAQAAAA==.',
Ed='Ediela:BAAANQADCgEIAQAAAA==.',
Ef='Effinsoldier:BAAANQAECgQIBAAAAA==.',
El='Elix:BAAANQADCgEIAQAAAA==.Elvira:BAABNQAECn8YAAIFAAgK6AiPogCLAQAFAAgK6AiPogCLAQAAAA==.',
En='Endwa:BAAANQAECgIIAgAAAA==.',
Ep='Epsicarinae:BAAANQADCggICgAAAA==.',
Er='Erel:BAAANQAECgEIAwAAAA==.Eridrel:BAAANQAECgUIDAAAAA==.',
Fi='Fiyero:BAABNQAECn8qAAIIAAgKFQmqsACeAQAIAAgKFQmqsACeAQAAAA==.',
Fl='Fleabath:BAAANQADCggJDgABNQAECgcIGQACACoOAA==.',
Fu='Fury:BAABNQAECn83AAMNAAkKwyJCAgBdAwANAAkKvh5CAgBdAwAIAAcKgBw8ewAjAgAAAA==.',
Ga='Galdames:BAABNQAECn8XAAICAAkKox9XFgBAAwACAAkKox9XFgBAAwAAAA==.Gandolphgrey:BAAANQAECgQICQAAAA==.',
Ge='Genghar:BAAANQADCggIEAAAAA==.Gertluzgin:BAAANQAECgEIAQAAAA==.',
Gi='Gilforty:BAAANQADCggJEAAAAA==.',
Go='Gonk:BAAANQAECgcIEwAAAA==.',
Gr='Gripnkill:BAABNQAECn9hAAMBAAkKSRsVJQBmAgABAAgKLhoVJQBmAgAPAAkKiRYkMABPAgAAAA==.',
Gu='Gump:BAAANQAECgMIAwABNQAECgkJHQAIAHERAA==.',
Gv='Gvendalyn:BAABNQAECn8uAAICAAkKBSYmAgDkAwACAAkKBSYmAgDkAwAAAA==.',
Gy='Gyatsò:BAABNQAECn8kAAIQAAgKuhzBFgCUAgAQAAgKuhzBFgCUAgAAAA==.',
Ha='Harshc:BAAANQAECgUIDAABNQAECgcIDQAGAAAAAA==.Harshdh:BAAANQAECgcIDQAAAA==.',
He='Helapa:BAAANQAECgMIBAAAAA==.Helel:BAABNQAECn83AAMKAAkKWiI+EwAdAwAKAAkKDSI+EwAdAwAPAAkKiRsAHgC/AgAAAA==.',
Ho='Hops:BAAANQAECggICAAAAA==.',
Ip='Ipokeu:BAAANQADCgUIBQAAAA==.',
Ja='Jabohabo:BAABNQAECn8iAAIIAAkKgSAiGQBSAwAIAAkKgSAiGQBSAwAAAA==.Jaffy:BAAANQAECgEIAQAAAA==.Jamninja:BAAANQADCggIFwAAAA==.Javamaster:BAAANQADCgIIAgAAAA==.Jaxxson:BAAANQAECgcIEwAAAA==.',
Je='Jellyfish:BAAANQAECgEIAQAAAA==.Jeriko:BAAANQADCgQIBAAAAA==.Jessamyn:BAAANQADCggIHgAAAA==.',
Jh='Jhoira:BAAANQABCgIIAgAAAA==.',
Jo='Jordyy:BAAANQAECgcIEgAAAA==.',
Ka='Kalifa:BAACNQAFFH8PAAIRAAUKyReaCwCwAQARAAUKyReaCwCwAQA1AAQKfyIAAhEACQqBITYTACwDABEACQqBITYTACwDAAAA.Kayohs:BAAANQAECgQIDgAAAA==.',
Kh='Khrysus:BAABNQAECn8fAAIQAAkKwg/7KADSAQAQAAkKwg/7KADSAQAAAA==.',
Ki='Kiv:BAABNQAECn8rAAQFAAkKQSBtIQD7AgAFAAkKQSBtIQD7AgASAAMKwhw9FwDUAAATAAEKnReEbQBCAAAAAA==.Kiwaj:BAAANQADCgMIAwABNQAECgQJCgAGAAAAAA==.',
Kn='Knoa:BAAANQAECgEIAgAAAA==.',
Ko='Kodachi:BAAANQAECgEIAQAAAA==.Kokopelli:BAAANQABCgIIAgAAAA==.Komayetu:BAAANQADCgQICAAAAA==.',
Kr='Krashed:BAAANQADCgMIBAAAAA==.Krateis:BAAANQADCggICwAAAA==.',
Ku='Kunfool:BAAANQADCgQIBAAAAA==.',
Kv='Kvit:BAAANQAECgIIAgAAAA==.',
Ky='Kyoki:BAABNQAECn8sAAIUAAkKxQ7HFAD+AQAUAAkKxQ7HFAD+AQAAAA==.',
La='Lazyace:BAAANQAECgIIAgAAAA==.',
Li='Liendrel:BAAANQABCgYIBgAAAA==.',
Ly='Lyset:BAAANQADCgEIAQABNQAECgIIAgAGAAAAAA==.',
Ma='Maeze:BAABNQAECn8ZAAICAAcKKg5SnADKAQACAAcKKg5SnADKAQAAAA==.Malandru:BAACNQAFFH8QAAMVAAUKPxKPEgAiAQAVAAQKPxKPEgAiAQAWAAQKVwsIFAAbAQA1AAQKfykAAxYACQpwG2goAMUCABYACAp4HmgoAMUCABUAAwp4IZ4GAQ0BAAAA.Mawwow:BAABNQAECn8nAAIVAAkKWSRhEQCCAwAVAAkKWSRhEQCCAwAAAA==.',
Me='Meekah:BAACNQAFFH8HAAIXAAMKOgriIADUAAAXAAMKOgriIADUAAA1AAQKfyIAAxcACQo1CqRvAMoBABcACQo1CqRvAMoBAAkAAwqXBxgdAHcAAAAA.Melyndia:BAAANQADCggICgABNQAECgkJKwAYAAYhAA==.Meriks:BAAANQADCgYIBgABNQAFFAMIBQAMAPMhAA==.',
Mi='Mickfurry:BAAANQAECgcICwABNQAFFAUIEAAZALwdAA==.Micksippy:BAACNQAFFH8QAAIZAAUKvB2AAwC8AQAZAAUKvB2AAwC8AQA1AAQKfysAAhkACQoHJLsDAHIDABkACQoHJLsDAHIDAAAA.Milamber:BAAANQAECgUICgAAAA==.Milfy:BAAANQADCgQJBAABNQAECgQICAAGAAAAAA==.',
My='Mylarna:BAABNQAECn8fAAIDAAgKfA14dQC9AQADAAgKfA14dQC9AQAAAA==.Mynx:BAAANQAECgcIEwAAAA==.',
Mz='Mzivvee:BAAANQADCgMIAgABNQAECgUIEwAGAAAAAA==.',
Na='Nashea:BAAANQADCgcJEAAAAA==.',
Ne='Neltharis:BAAANQABCgQIBAAAAA==.Neona:BAAANQADCgUIBwAAAA==.',
Ni='Nixii:BAABNQAECn8qAAIRAAgKFBVxOgAbAgARAAgKFBVxOgAbAgAAAA==.',
No='Nocticula:BAABNQAECn8oAAIXAAgKAQmyggCLAQAXAAgKAQmyggCLAQAAAA==.',
Ny='Nyalota:BAAANQADCggIFAAAAA==.Nyet:BAAANQAFFAIIAgAAAA==.',
Og='Ogucci:BAAANQADCggICAAAAA==.',
Ok='Oktoberfist:BAAANQAECgEIAQABNQAFFAUIDQARAIwHAA==.',
Op='Opalauria:BAAANQAECgMIAwAAAA==.',
Or='Orine:BAAANQADCgYICQAAAA==.Orion:BAAANQAECgYICQAAAA==.Orioz:BAACNQAFFH8HAAIaAAMKWBwPBAAPAQAaAAMKWBwPBAAPAQA1AAQKfyMAAhoACQolJNABAJkDABoACQolJNABAJkDAAAA.',
Oz='Oz:BAABNQAECn8gAAIFAAcKOyQvKgDZAgAFAAcKOyQvKgDZAgAAAA==.',
Pa='Pakali:BAAANQABCgMIAgAAAA==.Paladinhalos:BAAANQADCgcIBwAAAA==.Paladinsan:BAAANQAECgQICAABNQAECgkJFwACAKMfAA==.',
Ph='Phobos:BAAANQADCgIIAgABNQAECgMIAwAGAAAAAA==.',
Pi='Pillowprince:BAAANQAECggICAAAAA==.',
Po='Police:BAAANQADCgUIBQABNQAECgkJJwAbAEUfAQ==.',
Ps='Psychomurda:BAAANQADCgYIBgABNQAFFAMIBwAXADoKAA==.',
Py='Pytheas:BAAANQADCgYIBgABNQAECgMIAwAGAAAAAA==.',
Ra='Radio:BAAANQAECgUIBwAAAA==.Raistlin:BAAANQAECgUIBgABNQAFFAUIDQARAIwHAA==.',
Re='Renfri:BAAANQAECgEIAQAAAA==.',
Ro='Robel:BAAANQAECgQIBgAAAA==.Roflburger:BAAANQAECgUICAAAAA==.Rovox:BAAANQAECgQJCgAAAA==.',
Sa='Sadness:BAAANQADCgcIBwAAAA==.Sardrian:BAAANQAECgEIAQAAAA==.Saî:BAAANQADCgYIBgAAAA==.',
Sc='Scarletwrath:BAAANQADCgYICwAAAA==.',
Se='Seika:BAAANQABCgEIAQAAAA==.Seimie:BAAANQAECgUIDgAAAA==.Senethotsare:BAAANQADCgUIBwAAAA==.',
Sh='Shaboudi:BAAANQAECgQIBAABNQAECgcIEwAGAAAAAA==.Shammwow:BAAANQAECgcIEwAAAA==.Sherryl:BAABNQAECn8qAAIYAAgKig9eKgDHAQAYAAgKig9eKgDHAQAAAA==.',
Sk='Skdragon:BAAANQAECgYIDwAAAA==.Skyara:BAAANQAECgYIBwABNQAECgkJJgAcABshAA==.Skylaar:BAAANQADCggICgAAAA==.',
Sm='Smitey:BAAANQAECgMIAwAAAA==.',
So='Soulstik:BAAANQADCgcIDQAAAA==.',
Sp='Spiritshard:BAAANQAECgEIAQAAAA==.Spriggens:BAAANQAECgYIDgABNQAECgkJLgACAAUmAA==.',
St='Stalkr:BAAANQADCgQIBAAAAA==.Sthise:BAAANQADCgYJCgAAAA==.',
Sy='Sykoman:BAACNQAFFH8XAAIRAAcKuBuQBABfAgARAAcKuBuQBABfAgA1AAQKfx0AAhEACQp6JCQNAGADABEACQp6JCQNAGADAAAA.Sykowoman:BAAANQAECgQJBAABNQAFFAcIFwARALgbAA==.',
['Sì']='Sìrius:BAAANQADCggIDgAAAA==.',
Te='Terumi:BAAANQADCgcIEAAAAA==.',
Th='Thiizz:BAABNQAECn8mAAIKAAgKyh3xJwCYAgAKAAgKyh3xJwCYAgAAAA==.Thracious:BAAANQADCgUIBwAAAA==.Thïzz:BAAANQAECgUIDQABNQAECgkJIgAIAIEgAA==.',
Ti='Ticklemebutt:BAAANQAECgUIEAAAAA==.Tinksy:BAAANQADCgYIBgABNQAECgQICAAGAAAAAA==.Titanx:BAAANQADCgMJBAAAAA==.',
To='Toeto:BAAANQAECgQIBQAAAA==.Toetoeto:BAAANQAECgcIEQAAAA==.Toetoetoete:BAAANQADCgcJCAAAAA==.Tooe:BAAANQAECgQIEgAAAA==.Torquei:BAAANQAECgcIEAAAAA==.Toxan:BAAANQADCgUIBgAAAA==.',
Tp='Tpaman:BAAANQADCgMIBAAAAA==.',
Tr='Triks:BAAANQAECgYIDwAAAA==.',
Ts='Tsjudilla:BAAANQADCgQJBAAAAA==.',
Tu='Tujefe:BAABNQAECn8pAAIFAAkK/RCtaQAcAgAFAAkK/RCtaQAcAgAAAA==.',
Ty='Tylorialin:BAAANQADCgMIAwABNQAECgkJHQAIAHERAA==.',
Ur='Urpalharsh:BAAANQADCgIIAgABNQAECgcIDQAGAAAAAA==.',
Va='Vahldire:BAAANQADCggILQAAAA==.Valeeraa:BAAANQAECgUICAAAAA==.Valeri:BAAANQADCgcIBwAAAA==.',
Ve='Veresa:BAAANQADCgYICAAAAA==.',
Wa='Waeder:BAAANQADCgcIEwAAAA==.Waren:BAAANQAECgMIAwAAAA==.',
Wi='Wisteria:BAABNQAECn8pAAQTAAkKgBCEFQDAAQATAAcK/gyEFQDAAQAFAAgKKQyukwCwAQASAAEKSQMaNAAoAAABNQAECgMIAwAGAAAAAA==.',
Wo='Wompalot:BAAANQADCggIDwABNQAECgQIBAAGAAAAAA==.Wompeter:BAAANQAECgQIBAAAAA==.Womplock:BAAANQADCgYIBgAAAA==.Wompnhood:BAAANQADCgYICQABNQAECgQIBAAGAAAAAA==.Wooly:BAAANQADCgMIAwAAAA==.',
Wr='Wrâth:BAABNQAECn8kAAIdAAgKlw0U0ADjAQAdAAgKlw0U0ADjAQAAAA==.',
Xa='Xael:BAAANQAECgUICgAAAA==.',
Xu='Xunarii:BAAANQADCgUIBQABNQAECgkJJgAcABshAA==.',
Za='Zalus:BAAANQADCgYICgAAAA==.',
Ze='Zeal:BAAANQAECgQICAAAAA==.Zenatria:BAAANQADCgcICwAAAA==.',
Zi='Zindetra:BAAANQADCgEIAQAAAA==.',
Zo='Zorana:BAAANQAECgIIAgAAAA==.',
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
