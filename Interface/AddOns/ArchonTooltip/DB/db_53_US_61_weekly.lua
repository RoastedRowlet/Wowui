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

local lookup = {'DeathKnight-Frost','Hunter-BeastMastery','Shaman-Elemental','Paladin-Protection','Warlock-Demonology','Unknown-Unknown','Hunter-Marksmanship','Warrior-Arms','Priest-Discipline','DeathKnight-Unholy','Warrior-Protection','DemonHunter-Devourer','Warrior-Fury','Rogue-Subtlety','Monk-Brewmaster','DeathKnight-Blood','Monk-Windwalker','DemonHunter-Havoc','Druid-Balance','Mage-Arcane','Warlock-Affliction','Warlock-Destruction','Evoker-Devastation','Paladin-Holy','Paladin-Retribution','Priest-Holy','Druid-Restoration','Monk-Mistweaver','Rogue-Outlaw','Shaman-Enhancement','Shaman-Restoration','Evoker-Augmentation','Priest-Shadow','Rogue-Assassination',}
local provider = {region='US',realm='Darrowmere',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abaddonmoon:BAABNQAECn8nAAIBAAoKIw3tOADxAQABAAoKIw3tOADxAQAAAA==.Absolute:BAAANQADCgQIBAAAAA==.',
Ah='Ahnari:BAACNQAFFH8JAAICAAQKMxHyBgD1AAACAAQKMxHyBgD1AAA1AAQKfzYAAgIACgrsFhgGAGoCAAIACgrsFhgGAGoCAAAA.',
Ai='Ailinaa:BAAANQAECgIIAgAAAA==.',
Al='Alerat:BAAANQADCggIDgABNQAECgoKJAADAH8LAA==.Alistìn:BAABNQAECn8eAAIEAAgK4B4NEQCOAgAEAAgK4B4NEQCOAgAAAA==.Alistín:BAAANQAECgQIBgAAAA==.Allahwe:BAAANQADCggICAAAAA==.Allo:BAAANQAECgQIBAAAAA==.Alìstin:BAAANQADCgYIBgAAAA==.',
Am='Ameri:BAAANQAECgYICgAAAA==.',
An='Annalistiana:BAABNQAECn8kAAIFAAoKMQ/bXwA4AgAFAAoKMQ/bXwA4AgABNQAECgUICAAGAAAAAA==.',
Ap='Apiphone:BAAANQABCgQIBAAAAA==.',
Ar='Aradin:BAAANQAECgEIAwAAAA==.Archanfel:BAABNQAECn8fAAIHAAgKGgxRNACrAQAHAAgKGgxRNACrAQAAAA==.Argasha:BAAANQAECgQIBgAAAA==.Aro:BAAANQADCggICAABNQAECgQICAAGAAAAAA==.',
Ay='Ayurvedas:BAAANQADCgYIBgAAAA==.',
Az='Azaadi:BAEANQADCgYIBgABNQAECgMICAAGAAAAAA==.',
Ba='Balthizar:BAAANQAECggIBgAAAA==.Bandie:BAAANQAECgUIEAAAAA==.Bashan:BAAANQADCgEIAQAAAA==.Bayn:BAAANQABCggIFwAAAA==.',
Be='Beeftruck:BAABNQAECn8qAAIIAAoKphaiCAAyAgAIAAoKphaiCAAyAgAAAA==.Berried:BAABNQAECn83AAIJAAoKkBbaBABwAgAJAAoKkBbaBABwAgAAAA==.',
Bi='Bigred:BAAANQAECgUIEAAAAA==.Biminem:BAAANQADCgYIBgAAAA==.Bitomax:BAAANQAECgQICQAAAA==.',
Bl='Blað:BAAANQADCgEIAQAAAA==.Bloôdymary:BAAANQAECgUICgAAAA==.',
Br='Brakun:BAAANQADCgQICAAAAA==.Brewer:BAAANQADCgQIBAAAAA==.Brienne:BAAANQAECgIIAgAAAA==.Briline:BAAANQADCgQIBAAAAA==.Brolly:BAAANQAECggIBgAAAA==.',
Ca='Calamari:BAAANQADCgQIBAAAAA==.Camine:BAABNQAECn8yAAIKAAoKYBdNMQBoAgAKAAoKYBdNMQBoAgAAAA==.Capmurica:BAAANQAECgUIDQAAAA==.Castadrood:BAAANQAECgYICAAAAA==.Cates:BAAANQADCgUIBQAAAA==.',
Ch='Choppstik:BAAANQADCgQIBAAAAA==.',
Co='Cocstrong:BAAANQAECggIBwAAAA==.Coriolis:BAAANQAECgUICAAAAA==.',
Cr='Craano:BAAANQABCgQIBAABNQADCggIFwAGAAAAAA==.',
Da='Dagdag:BAAANQAECgIIAQAAAA==.Dagnamagus:BAAANQADCgUIBwAAAA==.',
De='Deathcokie:BAAANQAECgUICgAAAA==.Deatho:BAABNQAECn8xAAMLAAoKeyYyAAACBAALAAoKeyYyAAACBAAIAAIKphzfIgGUAAAAAA==.Deimos:BAAANQAECgQIBwAAAA==.',
Di='Diamondshard:BAAANQADCgUICgAAAA==.Diviniah:BAAANQADCgYIBgAAAA==.',
Do='Dotdotcurse:BAAANQADCggICAAAAA==.',
Dr='Drash:BAAANQAECgIIBAAAAA==.Dreadful:BAABNQAECn8fAAIMAAgKnBXbIwApAgAMAAgKnBXbIwApAgAAAA==.Dreyra:BAAANQADCggIJwABNQAECgkJKQANAIQZAA==.Droodtrass:BAAANQAECgQICAAAAA==.Drunksausage:BAAANQABCgQIBAAAAA==.',
Du='Duncan:BAAANQAECgUIBgABNQAECggIKwAIAB0JAA==.',
['Dö']='Döctorfate:BAABNQAECn8tAAIOAAkKBQwbHgDhAQAOAAkKBQwbHgDhAQAAAA==.',
Ed='Ediela:BAAANQADCgEIAQAAAA==.',
Ef='Effinsoldier:BAAANQAECgQIBgAAAA==.',
El='Elix:BAAANQADCgEIAQAAAA==.Elvira:BAABNQAECn8YAAIFAAgK6AjXpACLAQAFAAgK6AjXpACLAQAAAA==.',
En='Endlessagony:BAAANQAECgUIBgAAAA==.Endwa:BAAANQAECgIIAgAAAA==.',
Ep='Epsicarinae:BAAANQADCggIEgAAAA==.',
Er='Erel:BAAANQAECgEIAwAAAA==.Eridrel:BAAANQAECgUIDAAAAA==.',
Fi='Fiyero:BAABNQAECn8rAAIIAAgKHQm3sgCeAQAIAAgKHQm3sgCeAQAAAA==.',
Fl='Fleabath:BAAANQADCggJDgABNQAECggIGgACAF8OAA==.',
Fu='Fury:BAABNQAECn9AAAMNAAoKpSJGAgBdAwANAAoKIR9GAgBdAwAIAAcKKB3tfAAiAgAAAA==.',
Ga='Galdames:BAABNQAECn8gAAICAAoKMCH/FgA+AwACAAoKMCH/FgA+AwAAAA==.Gandolphgrey:BAAANQAECgQICQAAAA==.',
Ge='Genghar:BAAANQAECgEIAQAAAA==.Gertluzgin:BAAANQAECgIIAgAAAA==.',
Gi='Gilforty:BAAANQADCggJEAAAAA==.',
Go='Gonk:BAABNQAECn8UAAIPAAgK1hEUEQDXAQAPAAgK1hEUEQDXAQAAAA==.',
Gr='Gripnkill:BAABNQAECn9jAAMBAAoKfxvUJQBmAgABAAgKLhrUJQBmAgAQAAoKyResMABOAgAAAA==.',
Gu='Gump:BAAANQAECgQIBAABNQAECgoKKgAIAKYWAA==.',
Gv='Gvendalyn:BAABNQAECn84AAICAAoKuSU2AgDkAwACAAoKuSU2AgDkAwAAAA==.',
Gy='Gyatsò:BAABNQAECn8rAAIRAAgKuhzDCwBZAQARAAgKuhzDCwBZAQAAAA==.',
Ha='Harshc:BAAANQAECgYIDgABNQAECgkJFgASABoPAA==.Harshdh:BAABNQAECn8WAAISAAkKGg/WDQB/AQASAAkKGg/WDQB/AQAAAA==.',
He='Helapa:BAAANQAECgMIBAAAAA==.Helel:BAABNQAECn87AAMKAAoK+B9nEwAdAwAKAAkKDSJnEwAdAwAQAAoKAhpdHgC/AgAAAA==.',
Ho='Hops:BAAANQAECggICgAAAA==.',
Ip='Ipokeu:BAAANQADCgUIBQAAAA==.',
Ja='Jabohabo:BAABNQAECn8kAAIIAAkKUCKSGQBSAwAIAAkKUCKSGQBSAwAAAA==.Jaffy:BAAANQAECgIIAgAAAA==.Jamninja:BAAANQADCggIFwAAAA==.Javamaster:BAAANQADCgIIAgAAAA==.Jaxxson:BAAANQAECgcIEwAAAA==.',
Je='Jellyfish:BAAANQAECgEIAQAAAA==.Jeriko:BAAANQADCgQIBAAAAA==.Jessamyn:BAAANQADCggIHgAAAA==.',
Jh='Jhoira:BAAANQABCgIIAgAAAA==.',
Jo='Jordyy:BAABNQAECn8VAAIFAAgKrhkkTABvAgAFAAgKrhkkTABvAgAAAA==.',
Ka='Kalifa:BAACNQAFFH8UAAITAAYKUhvKAgB4AQATAAYKUhvKAgB4AQA1AAQKfycAAhMACgqsInQTACsDABMACgqsInQTACsDAAAA.Kayohs:BAABNQAECn8aAAIUAAcKqgnkTwAcAQAUAAcKqgnkTwAcAQAAAA==.',
Kh='Khrysus:BAABNQAECn8iAAIRAAoKcQ5uKQDSAQARAAoKcQ5uKQDSAQAAAA==.',
Ki='Kiv:BAACNQAFFH8IAAIFAAQKWRDqCADgAAAFAAQKWRDqCADgAAA1AAQKfy8ABAUACgojIE4iAPsCAAUACgojIE4iAPsCABUAAwrCHAQJAJYAABYAAQqdFxluAEIAAAAA.Kiwaj:BAAANQADCgMIAwABNQAECgQJCgAGAAAAAA==.',
Kn='Knoa:BAAANQAECgEIAgAAAA==.',
Ko='Kodachi:BAAANQAECggICAAAAA==.Kokopelli:BAAANQABCgIIAgAAAA==.Komayetu:BAAANQADCgQICAAAAA==.',
Kr='Krashed:BAAANQADCgMIBAAAAA==.Krateis:BAAANQADCggICwAAAA==.',
Ku='Kunfool:BAAANQADCgQIBAAAAA==.',
Kv='Kvit:BAAANQAECgMIBQAAAA==.',
Ky='Kyoki:BAABNQAECn8wAAIXAAoK2w3qFAD+AQAXAAoK2w3qFAD+AQAAAA==.',
La='Lazyace:BAAANQAECgIIAgAAAA==.',
Li='Liendrel:BAAANQABCgYIBgAAAA==.',
Ly='Lyset:BAAANQADCgEIAQABNQAECgMIBQAGAAAAAA==.',
Ma='Maeze:BAABNQAECn8aAAICAAgKXw6ZngDJAQACAAgKXw6ZngDJAQAAAA==.Malandru:BAACNQAFFH8VAAMYAAUKfhF5FAAbAQAYAAQKvwx5FAAbAQAZAAQKKRP8BwDkAAA1AAQKfywAAxgACgpmGtYoAMUCABgACQr6HNYoAMUCABkAAwp4IQqEAMYAAAAA.Mawwow:BAABNQAECn8tAAIZAAoKJCLXEQCBAwAZAAoKJCLXEQCBAwAAAA==.',
Me='Meekah:BAACNQAFFH8KAAIaAAMKyA3lDgDKAAAaAAMKyA3lDgDKAAA1AAQKfyYAAxoACgr+C/pwAMoBABoACgr+C/pwAMoBAAkAAwqXB14dAHcAAAAA.Melyndia:BAAANQADCggICgABNQAECgkJLgAbAAYhAA==.Meriks:BAAANQADCgYIBgABNQAFFAMIBgAMAPMhAA==.',
Mi='Mickfurry:BAAANQAECggICwABNQAFFAUIEAAcALwdAA==.Micksippy:BAACNQAFFH8QAAIcAAUKvB2aAwC7AQAcAAUKvB2aAwC7AQA1AAQKfzAAAxwACgq0I8sDAHIDABwACgq0I8sDAHIDAA8ABAruCakMAI0AAAAA.Milamber:BAAANQAECgUICgAAAA==.Milfy:BAAANQADCgQJBAABNQAECgQICAAGAAAAAA==.',
Mu='Muriggy:BAAANQAECgEIAQAAAA==.',
My='Mylarna:BAABNQAECn8kAAIDAAoKfwuoNADuAAADAAoKfwuoNADuAAAAAA==.Mynx:BAABNQAECn8XAAIHAAkKmhjUIwAvAgAHAAkKmhjUIwAvAgAAAA==.',
Mz='Mzivvee:BAAANQADCgMIAgABNQAECgYIFAAdAMISAA==.',
Na='Nargo:BAAANQAECgMIAwAAAA==.Nashea:BAAANQADCgcJEAAAAA==.',
Ne='Neltharis:BAAANQABCgQIBAAAAA==.Neona:BAAANQADCgUIBwAAAA==.',
Ni='Nixii:BAABNQAECn8uAAITAAoKGRIbOwAbAgATAAoKGRIbOwAbAgAAAA==.',
No='Nocticula:BAABNQAECn8vAAIaAAoKJAj9LABJAQAaAAoKJAj9LABJAQAAAA==.',
Ny='Nyalota:BAAANQADCggIFAAAAA==.Nyet:BAABNQAECn8VAAMNAAgKPRJaCwDGAAAIAAcKlhCzxABxAQANAAMKqxZaCwDGAAAAAA==.',
Og='Ogucci:BAAANQADCggICAAAAA==.',
Ok='Oktoberfist:BAAANQAECgEIAQABNQAECgYIBwAGAAAAAA==.',
Op='Opalauria:BAAANQAECgMIAwAAAA==.',
Or='Orine:BAAANQAECgYIBwAAAA==.Orion:BAAANQAECggICwAAAA==.Orioz:BAACNQAFFH8KAAIeAAMKaxw8AQAGAQAeAAMKaxw8AQAGAQA1AAQKfywAAh4ACgpoIkcAADEDAB4ACgpoIkcAADEDAAAA.',
Oz='Oz:BAABNQAECn8nAAIFAAgKXyDhCQAJAgAFAAgKXyDhCQAJAgAAAA==.',
Pa='Pakali:BAAANQABCgMIAgAAAA==.Paladinhalos:BAAANQADCgcIBwAAAA==.Paladinsan:BAAANQAECgYIDgABNQAECgoKIAACADAhAA==.',
Ph='Phobos:BAAANQADCgIIAgABNQAECgQIBwAGAAAAAA==.',
Pi='Pillowprince:BAAANQAECggICAAAAA==.',
Po='Police:BAAANQADCgUIBQABNQAECgoKKwAfAMEfAQ==.',
Ps='Psychomurda:BAAANQADCgYIBgABNQAFFAMICgAaAMgNAA==.',
Py='Pytheas:BAAANQADCgYIBgABNQAECgQIBwAGAAAAAA==.',
Ra='Radio:BAAANQAECgUICAAAAA==.Raistlin:BAAANQAECgYIBwAAAA==.',
Re='Renfri:BAAANQAECgIIAgAAAA==.',
Ro='Robel:BAAANQAECgQIBgAAAA==.Roflburger:BAAANQAECgQIDQAAAA==.Rovox:BAAANQAECgQJCgAAAA==.',
Sa='Sadness:BAAANQADCgcIBwAAAA==.Sardrian:BAAANQAECgEIAQAAAA==.Saî:BAAANQADCgYIBgAAAA==.',
Sc='Scarletwrath:BAAANQAECgEIAQAAAA==.',
Se='Seika:BAAANQABCgEIAQAAAA==.Seimie:BAABNQAECn8cAAIWAAcKsASjBwClAAAWAAcKsASjBwClAAAAAA==.Senethotsare:BAAANQADCgUIBwAAAA==.',
Sh='Shaboudi:BAAANQAECgQIBAABNQAECggIFAAPANYRAA==.Shammwow:BAABNQAECn8UAAIDAAcK/wJ7xQAHAQADAAcK/wJ7xQAHAQAAAA==.Sherryl:BAABNQAECn8tAAIbAAkKMRDLKgDHAQAbAAkKMRDLKgDHAQAAAA==.',
Sk='Skdragon:BAABNQAECn8XAAMXAAgKpxVREQA/AgAXAAcKShdREQA/AgAgAAUKWA1cEwD7AAAAAA==.Skyara:BAAANQAECgYICQABNQAECgoKKQAhABIfAA==.Skylaar:BAAANQAECgEIAQAAAA==.',
Sm='Smitey:BAAANQAECgMIAwAAAA==.',
So='Soulstik:BAAANQADCgcIDQAAAA==.',
Sp='Spiritshard:BAAANQAECgIIAwAAAA==.Spriggens:BAAANQAECgcIEAABNQAECgoKOAACALklAA==.',
St='Stalkr:BAAANQADCgQIBAAAAA==.Sthise:BAAANQADCgYJCgAAAA==.',
Sy='Sykoman:BAACNQAFFH8YAAITAAcKuBvGBABfAgATAAcKuBvGBABfAgA1AAQKfyAAAhMACgpoJFQNAGADABMACgpoJFQNAGADAAAA.Sykowoman:BAAANQAECgQJBAABNQAFFAcIGAATALgbAA==.',
['Sì']='Sìrius:BAAANQADCggIDgAAAA==.',
Te='Terumi:BAAANQAECgEIAQAAAA==.',
Th='Theodrei:BAAANQAECgEIAQAAAA==.Thiizz:BAABNQAECn8qAAIKAAkK3xxvKACYAgAKAAkK3xxvKACYAgAAAA==.Thracious:BAAANQADCgUIBwAAAA==.Thïzz:BAAANQAECgUIDgABNQAECgkJJAAIAFAiAA==.',
Ti='Ticklemebutt:BAAANQAECgUIEAAAAA==.Tinksy:BAAANQADCgYIBgABNQAECgQICAAGAAAAAA==.Titanx:BAAANQADCgMJBAAAAA==.',
To='Toeto:BAAANQAECgQIBQAAAA==.Toetoeto:BAAANQAECgcIEQAAAA==.Toetoetoete:BAAANQADCgcJCAAAAA==.Tooe:BAAANQAECgQIEgAAAA==.Torquei:BAAANQAECgcIEAAAAA==.Toxan:BAAANQADCgUIBgAAAA==.',
Tp='Tpaman:BAAANQADCgMIBAAAAA==.',
Tr='Triks:BAABNQAECn8WAAMdAAcKdBabAgAnAQAdAAcKdBabAgAnAQAiAAEKcgOjqgAmAAAAAA==.',
Ts='Tsjudilla:BAAANQADCgQJBAAAAA==.',
Tu='Tujefe:BAABNQAECn8sAAIFAAkKnhQfawAcAgAFAAkKnhQfawAcAgAAAA==.',
Ty='Tylorialin:BAAANQADCgMIAwABNQAECgoKKgAIAKYWAA==.',
Ur='Urpalharsh:BAAANQADCgIIAgABNQAECgkJFgASABoPAA==.',
Va='Vahldire:BAAANQADCggILQAAAA==.Valeeraa:BAAANQAECgYIDgAAAA==.Valeri:BAAANQADCgcIBwAAAA==.',
Ve='Veresa:BAAANQAECgIIAwAAAA==.',
Wa='Waeder:BAAANQADCgcIFAAAAA==.Waren:BAAANQAECgMIAwAAAA==.',
Wi='Wisteria:BAABNQAECn8rAAQWAAoKUxCpFQDAAQAWAAcK/gypFQDAAQAFAAkKlQzIlQCwAQAVAAEKSQOTNAAoAAABNQAECgQIBwAGAAAAAA==.',
Wo='Wompalot:BAAANQADCggIDwABNQAECgYICQAGAAAAAA==.Wompeter:BAAANQAECgYICQAAAA==.Womplock:BAAANQADCgYIBgAAAA==.Wompnhood:BAAANQADCgYICQABNQAECgYICQAGAAAAAA==.Wooly:BAAANQADCgMIAwAAAA==.',
Wr='Wrâth:BAABNQAECn8kAAIUAAgKlw370QDiAQAUAAgKlw370QDiAQAAAA==.',
Xa='Xael:BAAANQAECgUICgAAAA==.',
Xu='Xunarii:BAAANQADCgUIBQABNQAECgoKKQAhABIfAA==.',
Za='Zalus:BAAANQADCgYICgAAAA==.',
Ze='Zeal:BAAANQAECgQICAAAAA==.Zenatria:BAAANQADCgcICwAAAA==.',
Zi='Zindetra:BAAANQADCgEIAgAAAA==.',
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
