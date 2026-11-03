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

local lookup = {'DeathKnight-Frost','Hunter-BeastMastery','Shaman-Elemental','Paladin-Protection','Warlock-Demonology','Unknown-Unknown','Hunter-Marksmanship','Hunter-Survival','DeathKnight-Blood','Warrior-Fury','Warrior-Arms','Priest-Discipline','DeathKnight-Unholy','Warrior-Protection','DemonHunter-Devourer','Rogue-Subtlety','Priest-Holy','Priest-Shadow','Monk-Brewmaster','Monk-Windwalker','DemonHunter-Havoc','Druid-Balance','Mage-Arcane','Warlock-Affliction','Warlock-Destruction','Evoker-Devastation','Paladin-Retribution','Paladin-Holy','Druid-Restoration','Monk-Mistweaver','Rogue-Outlaw','Shaman-Enhancement','Shaman-Restoration','Evoker-Augmentation','Rogue-Assassination',}
local provider = {region='US',realm='Darrowmere',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abaddonmoon:BAABNQAECn82AAIBAAoKWw7tOADxAQABAAoKWw7tOADxAQAAAA==.Absolute:BAAANQADCgQIBAAAAA==.',
Ah='Ahnari:BAACNQAFFH8MAAICAAUKMxE9EQDmAAACAAUKMxE9EQDmAAA1AAQKf0gAAgIACgpIH0kWAM4CAAIACgpIH0kWAM4CAAAA.',
Ai='Ailinaa:BAAANQAECgIIAgAAAA==.',
Al='Alerat:BAAANQADCggIDgABNQAECgoKJgADAH8LAA==.Alistìn:BAABNQAECn8eAAIEAAgK4B4NEQCOAgAEAAgK4B4NEQCOAgAAAA==.Alistín:BAAANQAECgQIBgAAAA==.Allahwe:BAAANQADCggICAAAAA==.Allo:BAAANQAECgUICgAAAA==.Alìstin:BAAANQADCgYIBgAAAA==.',
Am='Ameri:BAAANQAECgYICgAAAA==.',
An='Annalistiana:BAABNQAECn8zAAIFAAoKtxH7RQDNAQAFAAoKtxH7RQDNAQABNQAECgUICAAGAAAAAA==.',
Ap='Apiphone:BAAANQABCgQIBAAAAA==.',
Ar='Aradin:BAAANQAECgQIBwAAAA==.Archanfel:BAABNQAECn8rAAMHAAoKsgqqHwA3AQAHAAoKsgqqHwA3AQAIAAEKAABPEwAAAAAAAA==.Argasha:BAAANQAECgQIBgAAAA==.Aro:BAAANQADCggICAABNQAECgQICAAGAAAAAA==.',
Ay='Ayurvedas:BAAANQADCgYIBgAAAA==.',
Az='Azaadi:BAEANQADCgYIBgABNQAECgYIFgAJAOISAA==.',
Ba='Bandie:BAAANQAECgUIEgAAAA==.Bashan:BAAANQADCgEIAQAAAA==.Bayn:BAAANQABCggIFwAAAA==.',
Be='Beeftruck:BAABNQAECn80AAMKAAoKPBc7DQBrAQALAAoKvBYiTADqAQAKAAcKxhc7DQBrAQAAAA==.Berried:BAABNQAECn9LAAIMAAoK2BhMAgB0AgAMAAoK2BhMAgB0AgAAAA==.',
Bi='Bigred:BAAANQAECgUIEQAAAA==.Biminem:BAAANQADCgYIBgAAAA==.Bitomax:BAAANQAECgQICQAAAA==.',
Bl='Blað:BAAANQADCgEIAQAAAA==.Bloôdymary:BAAANQAECgQIEgAAAA==.',
Br='Brakun:BAAANQAECgMIBwAAAA==.Brewer:BAAANQADCgQIBAAAAA==.Brienne:BAAANQAECgIIAgAAAA==.Briline:BAAANQADCgQIBAAAAA==.Brolly:BAAANQAECggIEAAAAA==.',
Ca='Calamari:BAAANQADCgQIBAAAAA==.Camine:BAABNQAECn8+AAINAAoK7xpNMQBoAgANAAoK7xpNMQBoAgAAAA==.Capmurica:BAAANQAECgQIEwAAAA==.Castadrood:BAAANQAECgUIDAAAAA==.Cates:BAAANQADCgUIBQAAAA==.',
Ch='Choppstik:BAAANQADCgQIBAAAAA==.',
Co='Cocstrong:BAAANQAECggIBwAAAA==.Coriolis:BAAANQAECgUICAAAAA==.',
Cr='Craano:BAAANQABCgQIBAABNQADCggIFwAGAAAAAA==.',
Da='Dagdag:BAAANQAECgIIAQAAAA==.Dagnamagus:BAAANQADCgUIBwAAAA==.',
De='Deathcokie:BAAANQAECgUICgAAAA==.Deatho:BAABNQAECn84AAMOAAoKhyYyAAACBAAOAAoKeyYyAAACBAALAAcKzRtKUADbAQAAAA==.Dedtho:BAAANQAECggICwABNQAECgoKOAAOAIcmAA==.Deermeat:BAAANQAECgYIBgAAAA==.Deimos:BAAANQAECgcIEgAAAA==.',
Di='Diamondshard:BAAANQADCgUICgAAAA==.Diviniah:BAAANQADCgYIBgAAAA==.',
Do='Dotdotcurse:BAAANQADCggICAAAAA==.',
Dr='Drash:BAAANQAECgIIBAAAAA==.Dreadful:BAABNQAECn8lAAIPAAoK8RTbIwApAgAPAAoK8RTbIwApAgAAAA==.Dreyra:BAAANQAECgIIBAABNQAECgoKHAAIAHIXAA==.Droodtrass:BAAANQAECgQICAAAAA==.Drunksausage:BAAANQABCgQIBAAAAA==.',
Du='Duncan:BAAANQAECgUIBgABNQAECgoKLwALADcIAA==.',
Dy='Dymetrius:BAAANQAECgMIAwAAAA==.',
['Dö']='Döctorfate:BAABNQAECn88AAIQAAoKYA0bHgDhAQAQAAoKYA0bHgDhAQAAAA==.',
Ed='Ediela:BAAANQADCgEIAQAAAA==.',
Ef='Effinsoldier:BAAANQAECgYIDwAAAA==.',
El='Elix:BAAANQADCgEIAQAAAA==.Elvira:BAABNQAECn8bAAIFAAoKGgnXpACLAQAFAAoKGgnXpACLAQAAAA==.',
En='Endlessagony:BAAANQAECgYIDgAAAA==.Endwa:BAAANQAECgIIAgAAAA==.',
Ep='Epsicarinae:BAAANQADCggIFgAAAA==.',
Er='Erel:BAAANQAECgUIBwAAAA==.Eridrel:BAABNQAECn8gAAMRAAkKxAtQTADOAQARAAkKxAtQTADOAQASAAUKVgaaUgDFAAAAAA==.',
Fi='Fiyero:BAABNQAECn8vAAILAAoKNwi3sgCeAQALAAoKNwi3sgCeAQAAAA==.',
Fl='Fleabath:BAAANQADCggJDgABNQAECggIJwACAF8OAA==.',
Fr='Frostfury:BAAANQAECgEIAQAAAA==.',
Fu='Fury:BAABNQAECn9TAAMKAAoKNCRGAgBdAwAKAAoKsCBGAgBdAwALAAcKKB3tfAAiAgAAAA==.',
Ga='Galdames:BAABNQAECn8kAAICAAoKfiL/FgA+AwACAAoKfiL/FgA+AwAAAA==.Gandolphgrey:BAAANQAECgUICgAAAA==.',
Ge='Genghar:BAAANQAECgEIAQAAAA==.Gertluzgin:BAAANQAECggIDAAAAA==.',
Gi='Gilforty:BAAANQADCggJEAAAAA==.',
Go='Gonk:BAABNQAECn8WAAITAAoKghAUEQDXAQATAAoKghAUEQDXAQAAAA==.',
Gr='Gripnkill:BAABNQAECn9oAAMBAAoKfBzUJQBmAgABAAgKLhrUJQBmAgAJAAoKbBmsMABOAgAAAA==.',
Gu='Gump:BAAANQAECgQIBAABNQAECgoKNAAKADwXAA==.',
Gv='Gvendalyn:BAABNQAECn9LAAICAAoKZiY2AgDkAwACAAoKZiY2AgDkAwAAAA==.',
Gy='Gyatsò:BAABNQAECn8uAAIUAAkKahsVFwCUAgAUAAkKahsVFwCUAgAAAA==.',
Ha='Harshc:BAAANQAECgcIDwABNQAECgkJHgAVADkSAA==.Harshdh:BAABNQAECn8eAAIVAAkKORL5JgCWAQAVAAkKORL5JgCWAQAAAA==.Hashirama:BAAANQAECggICAAAAA==.',
He='Helapa:BAAANQAECgMIBAAAAA==.Helel:BAABNQAECn9SAAMNAAoKOiLqCgCmAgAJAAoK2xpdHgC/AgANAAoKDSLqCgCmAgAAAA==.',
Ho='Hops:BAAANQAECggIDAAAAA==.',
Ip='Ipokeu:BAAANQADCgUIBQAAAA==.',
Ja='Jabohabo:BAABNQAECn8qAAILAAoKuyGSGQBSAwALAAoKuyGSGQBSAwAAAA==.Jaffy:BAAANQAECgYIDwAAAA==.Jamninja:BAAANQADCggIFwAAAA==.Javamaster:BAAANQADCgIIAgAAAA==.Jaxxson:BAAANQAECgcIEwAAAA==.',
Je='Jellyfish:BAAANQAECgEIAQAAAA==.Jeriko:BAAANQADCgQIBAAAAA==.Jessamyn:BAAANQAECgQIBAAAAA==.',
Jh='Jhoira:BAAANQABCgIIAgAAAA==.',
Jo='Jordyy:BAABNQAECn8VAAIFAAgKrhkkTABvAgAFAAgKrhkkTABvAgAAAA==.',
Ka='Kalifa:BAACNQAFFH8UAAIWAAYKUhvJBwBUAQAWAAYKUhvJBwBUAQA1AAQKfzUAAhYACgrlJAQDAFUDABYACgrlJAQDAFUDAAAA.Karrod:BAAANQAECgIIAgAAAA==.Kayohs:BAABNQAECn8nAAIXAAgKCw9ufgB+AQAXAAgKCw9ufgB+AQAAAA==.',
Kh='Khrysus:BAABNQAECn8qAAIUAAoKVw9uKQDSAQAUAAoKVw9uKQDSAQAAAA==.',
Ki='Kiv:BAACNQAFFH8IAAIFAAQKWRAaFQDSAAAFAAQKWRAaFQDSAAA1AAQKfzkABBgACgrAIcoCAG0CAAUACgojIE4iAPsCABgACgqYHsoCAG0CABkAAQqdFxluAEIAAAAA.Kiwaj:BAAANQADCgMIAwABNQAECgQJCgAGAAAAAA==.',
Kn='Knoa:BAAANQAECgEIAgAAAA==.',
Ko='Kodachi:BAAANQAECgcIEgAAAA==.Kokopelli:BAAANQABCgIIAgAAAA==.Komayetu:BAAANQADCgQICAAAAA==.',
Kr='Krashed:BAAANQADCgMIBAAAAA==.Krateis:BAAANQADCggICwAAAA==.',
Ku='Kunfool:BAAANQADCgQIBAAAAA==.',
Kv='Kvit:BAAANQAECgMIBQAAAA==.',
Ky='Kyoki:BAABNQAECn80AAIaAAoKFg7qFAD+AQAaAAoKFg7qFAD+AQAAAA==.',
La='Laberynt:BAAANQAECgQIBQAAAA==.Lazyace:BAAANQAECgIIAgAAAA==.',
Li='Liendrel:BAAANQABCgYIBgAAAA==.',
Ly='Lyset:BAAANQADCgEIAQABNQAECgMIBQAGAAAAAA==.',
Ma='Maeze:BAABNQAECn8nAAICAAgKXw6ZngDJAQACAAgKXw6ZngDJAQAAAA==.Malandru:BAACNQAFFH8WAAMbAAYKdBIqEwAiAQAbAAQKKRMqEwAiAQAcAAUKSA15FAAbAQA1AAQKfzIAAxwACgrCGtYoAMUCABwACQpgHdYoAMUCABsAAwp4IZEKAQ0BAAAA.Mawwow:BAABNQAECn8+AAIbAAoKWCXXEQCBAwAbAAoKWCXXEQCBAwAAAA==.',
Me='Meekah:BAACNQAFFH8LAAIRAAQKmgtxFwAIAQARAAQKmgtxFwAIAQA1AAQKfy8AAxEACgq7DPpwAMoBABEACgq7DPpwAMoBAAwAAwqXB14dAHcAAAAA.Melyndia:BAAANQADCggICgABNQAFFAIIBgAdAPcTAA==.Meriks:BAAANQADCgYIBgABNQAFFAMIBgAPAPMhAA==.',
Mi='Mickfurry:BAAANQAECggICwABNQAFFAcIFgAeADMbAA==.Micksippy:BAACNQAFFH8WAAIeAAcKMxvcAQD/AQAeAAcKMxvcAQD/AQA1AAQKfzYAAx4ACgpXJMsDAHIDAB4ACgpXJMsDAHIDABMABAruCdwYAH8AAAAA.Milamber:BAAANQAECgYICgAAAA==.Milfy:BAAANQADCgQJBAABNQAECgQICAAGAAAAAA==.',
Mu='Muriggy:BAAANQAECgEIAQAAAA==.',
My='Mylarna:BAABNQAECn8mAAIDAAoKfwsvdwC8AQADAAoKfwsvdwC8AQAAAA==.Mynx:BAABNQAECn8eAAIHAAoKuxZvGACKAQAHAAoKuxZvGACKAQAAAA==.',
Mz='Mzivvee:BAAANQADCgMIAgABNQAECgYIFAAfAMISAA==.',
Na='Nargo:BAAANQAECgQIBwAAAA==.Nashea:BAAANQADCgcJEAAAAA==.',
Ne='Neltharis:BAAANQABCgQIBAAAAA==.Neona:BAAANQADCgUIBwAAAA==.',
Ni='Nixii:BAABNQAECn8xAAIWAAoKqRMbOwAbAgAWAAoKqRMbOwAbAgAAAA==.',
No='Nocticula:BAABNQAECn9CAAIRAAoKyw0pPgAJAgARAAoKyw0pPgAJAgAAAA==.',
Ny='Nyalota:BAAANQADCggIFAAAAA==.Nyet:BAABNQAECn8VAAMKAAgKPRIgGQCyAAALAAcKlhCzxABxAQAKAAMKqxYgGQCyAAAAAA==.',
Og='Ogucci:BAAANQADCggICAAAAA==.',
Ok='Oktoberfist:BAAANQAECgEIAQABNQAFFAUIEQAWAGkNAA==.',
Op='Opalauria:BAAANQAECgQIBAAAAA==.',
Or='Orine:BAAANQAECggIDAAAAA==.Orion:BAAANQAECggIDwAAAA==.Orioz:BAACNQAFFH8QAAIgAAYKvB4hAQBkAQAgAAYKvB4hAQBkAQA1AAQKfz4AAiAACgpNJTwBAFMDACAACgpNJTwBAFMDAAAA.',
Oz='Oz:BAABNQAECn8xAAIFAAkKASOlFwCeAgAFAAkKASOlFwCeAgAAAA==.',
Pa='Pakali:BAAANQABCgMIAgAAAA==.Paladinhalos:BAAANQADCgcIDQAAAA==.Paladinsan:BAABNQAECn8UAAIcAAYKchWWXQBvAQAcAAYKchWWXQBvAQABNQAECgoKJAACAH4iAA==.',
Ph='Phobos:BAAANQADCgIIAgABNQAECgcIEgAGAAAAAA==.',
Pi='Pillowprince:BAAANQAECggICAAAAA==.',
Po='Police:BAAANQADCgUIBQABNQAECgoKKwAhAMEfAQ==.',
Ps='Psychomurda:BAAANQADCgYIBgABNQAFFAQICwARAJoLAA==.',
Pu='Punches:BAAANQAECggIBAAAAA==.',
Py='Pytheas:BAAANQADCgYIBgABNQAECgcIEgAGAAAAAA==.',
Ra='Radio:BAAANQAECgcIEQAAAA==.Raistlin:BAAANQAECggIEAABNQAFFAUIEQAWAGkNAA==.',
Re='Renfri:BAAANQAECgYIDwAAAA==.',
Ro='Robel:BAAANQAECgQIBgAAAA==.Roflburger:BAABNQAECn8bAAIgAAcKrRceFgBsAQAgAAcKrRceFgBsAQAAAA==.Rovox:BAAANQAECgQJCgAAAA==.',
Sa='Sadness:BAAANQADCgcIBwAAAA==.Sardrian:BAAANQAECgMIBAAAAA==.Saî:BAAANQADCgYIBgAAAA==.',
Sc='Scarletwrath:BAAANQAECgIIBAAAAA==.',
Se='Seika:BAAANQABCgEIAQAAAA==.Seimie:BAABNQAECn8rAAIZAAgKlAVDDwDCAAAZAAgKlAVDDwDCAAAAAA==.Senethotsare:BAAANQADCgUIBwAAAA==.',
Sg='Sgaeyl:BAAANQADCgQIBAAAAA==.',
Sh='Shaboudi:BAAANQAECgQIBAABNQAECgoKFgATAIIQAA==.Shammwow:BAABNQAECn8VAAIDAAgK5wJ7xQAHAQADAAgK5wJ7xQAHAQAAAA==.Sherryl:BAABNQAECn88AAIdAAoKXBIyFwARAgAdAAoKXBIyFwARAgAAAA==.',
Si='Siddharthä:BAABNQAECn8eAAIbAAoKexDuggCGAQAbAAoKexDuggCGAQAAAA==.',
Sk='Skdragon:BAABNQAECn8fAAMaAAkKfRtREQA/AgAaAAgKJB5REQA/AgAiAAUKWA1cEwD7AAAAAA==.Skyara:BAAANQAECgYICgABNQAECgoKMAASAEgeAA==.Skylaar:BAAANQAECgQIBQAAAA==.',
Sm='Smitey:BAAANQAECgMIAwAAAA==.',
So='Soulstik:BAAANQADCgcIDQAAAA==.',
Sp='Spiritshard:BAAANQAECgEIBQAAAA==.Spriggens:BAAANQAECgcIEgABNQAECgoKSwACAGYmAA==.',
St='Stalkr:BAAANQADCgQIBAAAAA==.Sthise:BAAANQADCgYICgAAAA==.',
Sy='Sykoman:BAACNQAFFH8aAAIWAAgKfRnGBABfAgAWAAgKfRnGBABfAgA1AAQKfysAAhYACgpdJVQNAGADABYACgpdJVQNAGADAAAA.Sykowoman:BAAANQAECgQJBAABNQAFFAgIGgAWAH0ZAA==.',
['Sì']='Sìleñtclãw:BAAANQADCgEIAQAAAA==.Sìrius:BAAANQADCggIDgAAAA==.',
Te='Terumi:BAAANQAECgMIBAAAAA==.',
Th='Theodrei:BAAANQAECgEIAQAAAA==.Thiizz:BAABNQAECn84AAINAAoKhByMDwBeAgANAAoKhByMDwBeAgAAAA==.Thracious:BAAANQADCgUIBwAAAA==.Thïzz:BAAANQAECgUIDwABNQAECgoKKgALALshAA==.',
Ti='Ticklemebutt:BAAANQAECgUIEAAAAA==.Tinksy:BAAANQADCgYIBgABNQAECgQICAAGAAAAAA==.Titanx:BAAANQADCgMJBAAAAA==.',
To='Toeto:BAAANQAECgQIBQAAAA==.Toetoeto:BAAANQAECgcIEQAAAA==.Toetoetoete:BAAANQADCgcJCAAAAA==.Tooe:BAAANQAECgQIEgAAAA==.Torquei:BAAANQAECgcIEAAAAA==.Toxan:BAAANQADCgUIBgAAAA==.',
Tp='Tpaman:BAAANQADCgMIBAAAAA==.',
Tr='Triks:BAABNQAECn8YAAMfAAcKdBZQCgDXAQAfAAcKdBZQCgDXAQAjAAEKcgOjqgAmAAAAAA==.',
Ts='Tsjudilla:BAAANQADCgQJBAAAAA==.',
Tu='Tujefe:BAABNQAECn8uAAIFAAkKnhQfawAcAgAFAAkKnhQfawAcAgAAAA==.',
Ty='Tylorialin:BAAANQADCgMIAwABNQAECgoKNAAKADwXAA==.',
Ur='Urpalharsh:BAAANQADCgIIAgABNQAECgkJHgAVADkSAA==.',
Va='Vahldire:BAAANQAECgMIBgAAAA==.Valeeraa:BAABNQAECn8cAAMjAAkKJghLIAATAQAjAAgKiwhLIAATAQAfAAYKuQXAEwDBAAAAAA==.Valeri:BAAANQADCgcIBwAAAA==.Varken:BAAANQAECgMIAwAAAA==.',
Ve='Veresa:BAAANQAECgIIBgAAAA==.',
Vo='Voidwrath:BAAANQAECggICAAAAA==.',
Wa='Waeder:BAAANQADCgcIFwAAAA==.Waren:BAAANQAECgMIAwAAAA==.',
Wi='Wingman:BAAANQAECgQIBQAAAA==.Wisteria:BAABNQAECn83AAQZAAoKlhKpFQDAAQAZAAcK/gypFQDAAQAFAAkKKw/vZgBnAQAYAAEKSQOTNAAoAAABNQAECgcIEgAGAAAAAA==.',
Wo='Wompalot:BAAANQADCggIDwABNQAECgYIDwAGAAAAAA==.Wompeter:BAAANQAECgYIDwAAAA==.Womplock:BAAANQADCgYICwAAAA==.Wompnhood:BAAANQAECgIIAgABNQAECgYIDwAGAAAAAA==.Wooly:BAAANQADCgMIAwAAAA==.',
Wr='Wrâth:BAABNQAECn8kAAIXAAgKlw370QDiAQAXAAgKlw370QDiAQAAAA==.',
Xa='Xael:BAAANQAECgUICgAAAA==.',
Xu='Xunarii:BAAANQADCgUIBQABNQAECgoKMAASAEgeAA==.',
Za='Zalus:BAAANQADCgYICgAAAA==.',
Ze='Zeal:BAAANQAECgQICAAAAA==.Zenatria:BAAANQADCgcICwAAAA==.',
Zi='Zindetra:BAAANQAECgMIAwAAAA==.',
Zo='Zorana:BAAANQAECgQIBAAAAA==.',
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
