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

local lookup = {'DeathKnight-Frost','Hunter-BeastMastery','Shaman-Elemental','Paladin-Protection','Warlock-Demonology','Unknown-Unknown','Hunter-Marksmanship','Warrior-Arms','Priest-Discipline','DeathKnight-Unholy','Warrior-Protection','DemonHunter-Devourer','Rogue-Subtlety','Warrior-Fury','Monk-Brewmaster','DeathKnight-Blood','Monk-Windwalker','DemonHunter-Havoc','Druid-Balance','Mage-Arcane','Warlock-Affliction','Warlock-Destruction','Evoker-Devastation','Paladin-Retribution','Paladin-Holy','Priest-Holy','Druid-Restoration','Monk-Mistweaver','Rogue-Outlaw','Shaman-Enhancement','Shaman-Restoration','Evoker-Augmentation','Priest-Shadow','Rogue-Assassination',}
local provider = {region='US',realm='Darrowmere',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abaddonmoon:BAABNQAECn8yAAIBAAoKWw7KKACPAQABAAoKWw7KKACPAQAAAA==.Absolute:BAAANQADCgQIBAAAAA==.',
Ah='Ahnari:BAACNQAFFH8MAAICAAUKMxECDQDsAAACAAUKMxECDQDsAAA1AAQKfz8AAgIACgp3GUwdAHgCAAIACgp3GUwdAHgCAAAA.',
Ai='Ailinaa:BAAANQAECgIIAgAAAA==.',
Al='Alerat:BAAANQADCggIDgABNQAECgoKJgADAH8LAA==.Alistìn:BAABNQAECn8eAAIEAAgK4B4NEQCOAgAEAAgK4B4NEQCOAgAAAA==.Alistín:BAAANQAECgQIBgAAAA==.Allahwe:BAAANQADCggICAAAAA==.Allo:BAAANQAECgUIBwAAAA==.Alìstin:BAAANQADCgYIBgAAAA==.',
Am='Ameri:BAAANQAECgYICgAAAA==.',
An='Annalistiana:BAABNQAECn8uAAIFAAoKtxF1MQDnAQAFAAoKtxF1MQDnAQABNQAECgUICAAGAAAAAA==.',
Ap='Apiphone:BAAANQABCgQIBAAAAA==.',
Ar='Aradin:BAAANQAECgQIBwAAAA==.Archanfel:BAABNQAECn8iAAIHAAkKrgtRNACrAQAHAAkKrgtRNACrAQAAAA==.Argasha:BAAANQAECgQIBgAAAA==.Aro:BAAANQADCggICAABNQAECgQICAAGAAAAAA==.',
Ay='Ayurvedas:BAAANQADCgYIBgAAAA==.',
Az='Azaadi:BAEANQADCgYIBgABNQAECgUIDQAGAAAAAA==.',
Ba='Bandie:BAAANQAECgUIEQAAAA==.Bashan:BAAANQADCgEIAQAAAA==.Bayn:BAAANQABCggIFwAAAA==.',
Be='Beeftruck:BAABNQAECn8sAAIIAAoKvBaUNgD5AQAIAAoKvBaUNgD5AQAAAA==.Berried:BAABNQAECn9BAAIJAAoK5xfTAQBOAgAJAAoK5xfTAQBOAgAAAA==.',
Bi='Bigred:BAAANQAECgUIEQAAAA==.Biminem:BAAANQADCgYIBgAAAA==.Bitomax:BAAANQAECgQICQAAAA==.',
Bl='Blað:BAAANQADCgEIAQAAAA==.Bloôdymary:BAAANQAECgQIDAAAAA==.',
Br='Brakun:BAAANQADCgQICAAAAA==.Brewer:BAAANQADCgQIBAAAAA==.Brienne:BAAANQAECgIIAgAAAA==.Briline:BAAANQADCgQIBAAAAA==.Brolly:BAAANQAECggIBAAAAA==.',
Ca='Calamari:BAAANQADCgQIBAAAAA==.Camine:BAABNQAECn84AAIKAAoKCxlNMQBoAgAKAAoKCxlNMQBoAgAAAA==.Capmurica:BAAANQAECgUIDwAAAA==.Castadrood:BAAANQAECgYIBwAAAA==.Cates:BAAANQADCgUIBQAAAA==.',
Ch='Choppstik:BAAANQADCgQIBAAAAA==.',
Co='Cocstrong:BAAANQAECggIBwAAAA==.Coriolis:BAAANQAECgUICAAAAA==.',
Cr='Craano:BAAANQABCgQIBAABNQADCggIFwAGAAAAAA==.',
Da='Dagdag:BAAANQAECgIIAQAAAA==.Dagnamagus:BAAANQADCgUIBwAAAA==.',
De='Deathcokie:BAAANQAECgUICgAAAA==.Deatho:BAABNQAECn84AAMLAAoKhyYyAAACBAALAAoKeyYyAAACBAAIAAcKzRunOQDrAQAAAA==.Dedtho:BAAANQAECggICAABNQAECgoKOAALAIcmAA==.Deimos:BAAANQAECgUICgAAAA==.',
Di='Diamondshard:BAAANQADCgUICgAAAA==.Diviniah:BAAANQADCgYIBgAAAA==.',
Do='Dotdotcurse:BAAANQADCggICAAAAA==.',
Dr='Drash:BAAANQAECgIIBAAAAA==.Dreadful:BAABNQAECn8hAAIMAAoK8RTbIwApAgAMAAoK8RTbIwApAgAAAA==.Dreyra:BAAANQAECgIIAgABNQAECggIDwAGAAAAAA==.Droodtrass:BAAANQAECgQICAAAAA==.Drunksausage:BAAANQABCgQIBAAAAA==.',
Du='Duncan:BAAANQAECgUIBgABNQAECgoKLwAIADcIAA==.',
Dy='Dymetrius:BAAANQAECgMIAwAAAA==.',
['Dö']='Döctorfate:BAABNQAECn83AAINAAoKYA0bHgDhAQANAAoKYA0bHgDhAQAAAA==.',
Ed='Ediela:BAAANQADCgEIAQAAAA==.',
Ef='Effinsoldier:BAAANQAECgYICAAAAA==.',
El='Elix:BAAANQADCgEIAQAAAA==.Elvira:BAABNQAECn8bAAIFAAoKGgnXpACLAQAFAAoKGgnXpACLAQAAAA==.',
En='Endlessagony:BAAANQAECgcICAAAAA==.Endwa:BAAANQAECgIIAgAAAA==.',
Ep='Epsicarinae:BAAANQADCggIFgAAAA==.',
Er='Erel:BAAANQAECgUIBwAAAA==.Eridrel:BAAANQAECgUIEAAAAA==.',
Fi='Fiyero:BAABNQAECn8vAAIIAAoKNwi3sgCeAQAIAAoKNwi3sgCeAQAAAA==.',
Fl='Fleabath:BAAANQADCggJDgABNQAECggIIQACAF8OAA==.',
Fu='Fury:BAABNQAECn9KAAMOAAoK7yNGAgBdAwAOAAoKayBGAgBdAwAIAAcKKB3tfAAiAgAAAA==.',
Ga='Galdames:BAABNQAECn8iAAICAAoKfiL/FgA+AwACAAoKfiL/FgA+AwAAAA==.Gandolphgrey:BAAANQAECgUICgAAAA==.',
Ge='Gertluzgin:BAAANQAECgIIAgAAAA==.',
Gi='Gilforty:BAAANQADCggJEAAAAA==.',
Go='Gonk:BAABNQAECn8WAAIPAAoKghAUEQDXAQAPAAoKghAUEQDXAQAAAA==.',
Gr='Gripnkill:BAABNQAECn9oAAMBAAoKfBzUJQBmAgABAAgKLhrUJQBmAgAQAAoKbBmsMABOAgAAAA==.',
Gu='Gump:BAAANQAECgQIBAABNQAECgoKLAAIALwWAA==.',
Gv='Gvendalyn:BAABNQAECn9CAAICAAoKySU2AgDkAwACAAoKySU2AgDkAwAAAA==.',
Gy='Gyatsò:BAABNQAECn8rAAIRAAgKuhwVFwCUAgARAAgKuhwVFwCUAgAAAA==.',
Ha='Harshc:BAAANQAECgYIDgABNQAECgkJHgASADkSAA==.Harshdh:BAABNQAECn8eAAISAAkKORK+HAC0AQASAAkKORK+HAC0AQAAAA==.',
He='Helapa:BAAANQAECgMIBAAAAA==.Helel:BAABNQAECn9HAAMKAAoKOiJnEwAdAwAKAAoKDSJnEwAdAwAQAAoKlhpdHgC/AgAAAA==.',
Ho='Hops:BAAANQAECggICQAAAA==.',
Ip='Ipokeu:BAAANQADCgUIBQAAAA==.',
Ja='Jabohabo:BAABNQAECn8nAAIIAAoKjyGSGQBSAwAIAAoKjyGSGQBSAwAAAA==.Jaffy:BAAANQAECgcIBwAAAA==.Jamninja:BAAANQADCggIFwAAAA==.Javamaster:BAAANQADCgIIAgAAAA==.Jaxxson:BAAANQAECgcIEwAAAA==.',
Je='Jellyfish:BAAANQAECgEIAQAAAA==.Jeriko:BAAANQADCgQIBAAAAA==.Jessamyn:BAAANQADCggIHgAAAA==.',
Jh='Jhoira:BAAANQABCgIIAgAAAA==.',
Jo='Jordyy:BAABNQAECn8VAAIFAAgKrhkkTABvAgAFAAgKrhkkTABvAgAAAA==.',
Ka='Kalifa:BAACNQAFFH8UAAITAAYKUhteBQBeAQATAAYKUhteBQBeAQA1AAQKfy8AAhMACgqfI6QJALgCABMACgqfI6QJALgCAAAA.Karrod:BAAANQADCggIGQAAAA==.Kayohs:BAABNQAECn8hAAIUAAgKgA0ibgBqAQAUAAgKgA0ibgBqAQAAAA==.',
Kh='Khrysus:BAABNQAECn8mAAIRAAoKUQ9uKQDSAQARAAoKUQ9uKQDSAQAAAA==.',
Ki='Kiv:BAACNQAFFH8IAAIFAAQKWRDFDwDUAAAFAAQKWRDFDwDUAAA1AAQKfzkABBUACgrAIQkBAL4CAAUACgojIE4iAPsCABUACgqYHgkBAL4CABYAAQqdFxluAEIAAAAA.Kiwaj:BAAANQADCgMIAwABNQAECgQJCgAGAAAAAA==.',
Kn='Knoa:BAAANQAECgEIAgAAAA==.',
Ko='Kodachi:BAAANQAECgcICwAAAA==.Kokopelli:BAAANQABCgIIAgAAAA==.Komayetu:BAAANQADCgQICAAAAA==.',
Kr='Krashed:BAAANQADCgMIBAAAAA==.Krateis:BAAANQADCggICwAAAA==.',
Ku='Kunfool:BAAANQADCgQIBAAAAA==.',
Kv='Kvit:BAAANQAECgMIBQAAAA==.',
Ky='Kyoki:BAABNQAECn80AAIXAAoKFg7qFAD+AQAXAAoKFg7qFAD+AQAAAA==.',
La='Laberynt:BAAANQAECgQIBAAAAA==.Lazyace:BAAANQAECgIIAgAAAA==.',
Li='Liendrel:BAAANQABCgYIBgAAAA==.',
Ly='Lyset:BAAANQADCgEIAQABNQAECgMIBQAGAAAAAA==.',
Ma='Maeze:BAABNQAECn8hAAICAAgKXw6ZngDJAQACAAgKXw6ZngDJAQAAAA==.Malandru:BAACNQAFFH8WAAMYAAYKdBIqEwAiAQAYAAQKKRMqEwAiAQAZAAUKSA15FAAbAQA1AAQKfy8AAxkACgpmGtYoAMUCABkACQr6HNYoAMUCABgAAwp4IZEKAQ0BAAAA.Mawwow:BAABNQAECn85AAIYAAoKWCWGCgAiAwAYAAoKWCWGCgAiAwAAAA==.',
Me='Meekah:BAACNQAFFH8LAAIaAAQKmgtfEgAMAQAaAAQKmgtfEgAMAQA1AAQKfysAAxoACgqdDPpwAMoBABoACgqdDPpwAMoBAAkAAwqXB14dAHcAAAAA.Melyndia:BAAANQADCggICgABNQAFFAIIBgAbAPcTAA==.Meriks:BAAANQADCgYIBgABNQAFFAMIBgAMAPMhAA==.',
Mi='Mickfurry:BAAANQAECggICwABNQAFFAYIFQAcAOccAA==.Micksippy:BAACNQAFFH8VAAIcAAYK5xzrAQC3AQAcAAYK5xzrAQC3AQA1AAQKfzMAAxwACgoWJMsDAHIDABwACgoWJMsDAHIDAA8ABAruCVIUAIYAAAAA.Milamber:BAAANQAECgYICgAAAA==.Milfy:BAAANQADCgQJBAABNQAECgQICAAGAAAAAA==.',
Mu='Muriggy:BAAANQAECgEIAQAAAA==.',
My='Mylarna:BAABNQAECn8mAAIDAAoKfwsvdwC8AQADAAoKfwsvdwC8AQAAAA==.Mynx:BAABNQAECn8dAAIHAAoKuxbmEQClAQAHAAoKuxbmEQClAQAAAA==.',
Mz='Mzivvee:BAAANQADCgMIAgABNQAECgYIFAAdAMISAA==.',
Na='Nargo:BAAANQAECgQIBwAAAA==.Nashea:BAAANQADCgcJEAAAAA==.',
Ne='Neltharis:BAAANQABCgQIBAAAAA==.Neona:BAAANQADCgUIBwAAAA==.',
Ni='Nixii:BAABNQAECn8xAAITAAoKqRMbOwAbAgATAAoKqRMbOwAbAgAAAA==.',
No='Nocticula:BAABNQAECn84AAIaAAoKsgivSQCKAQAaAAoKsgivSQCKAQAAAA==.',
Ny='Nyalota:BAAANQADCggIFAAAAA==.Nyet:BAABNQAECn8VAAMOAAgKPRIqEwC7AAAIAAcKlhCzxABxAQAOAAMKqxYqEwC7AAAAAA==.',
Og='Ogucci:BAAANQADCggICAAAAA==.',
Ok='Oktoberfist:BAAANQAECgEIAQABNQAFFAUIEQATAGkNAA==.',
Op='Opalauria:BAAANQAECgQIBAAAAA==.',
Or='Orine:BAAANQAECgYIBQAAAA==.Orion:BAAANQAECgcICwAAAA==.Orioz:BAACNQAFFH8PAAIeAAUKtyJVAQAZAQAeAAUKtyJVAQAZAQA1AAQKfzUAAh4ACgowI+EBAJcDAB4ACgowI+EBAJcDAAAA.',
Oz='Oz:BAABNQAECn8wAAIFAAkKASMGDgC6AgAFAAkKASMGDgC6AgAAAA==.',
Pa='Pakali:BAAANQABCgMIAgAAAA==.Paladinhalos:BAAANQADCgcIDQAAAA==.Paladinsan:BAAANQAECgQIEAABNQAECgoKIgACAH4iAA==.',
Ph='Phobos:BAAANQADCgIIAgABNQAECgUICgAGAAAAAA==.',
Pi='Pillowprince:BAAANQAECggICAAAAA==.',
Po='Police:BAAANQADCgUIBQABNQAECgoKKwAfAMEfAQ==.',
Ps='Psychomurda:BAAANQADCgYIBgABNQAFFAQICwAaAJoLAA==.',
Pu='Punches:BAAANQAECggIAgAAAA==.',
Py='Pytheas:BAAANQADCgYIBgABNQAECgUICgAGAAAAAA==.',
Ra='Radio:BAAANQAECgcIDAAAAA==.Raistlin:BAAANQAECgUIBgABNQAFFAUIEQATAGkNAA==.',
Re='Renfri:BAAANQAECgcIBwAAAA==.',
Ro='Robel:BAAANQAECgQIBgAAAA==.Roflburger:BAABNQAECn8UAAIeAAYKSxhjFgAlAQAeAAYKSxhjFgAlAQAAAA==.Rovox:BAAANQAECgQJCgAAAA==.',
Sa='Sadness:BAAANQADCgcIBwAAAA==.Sardrian:BAAANQAECgEIAQAAAA==.Saî:BAAANQADCgYIBgAAAA==.',
Sc='Scarletwrath:BAAANQADCgYICwAAAA==.',
Se='Seika:BAAANQABCgEIAQAAAA==.Seimie:BAABNQAECn8lAAIWAAgKTQX/CwDAAAAWAAgKTQX/CwDAAAAAAA==.Senethotsare:BAAANQADCgUIBwAAAA==.',
Sh='Shaboudi:BAAANQAECgQIBAABNQAECgoKFgAPAIIQAA==.Shammwow:BAABNQAECn8UAAIDAAcK/wJ7xQAHAQADAAcK/wJ7xQAHAQAAAA==.Sherryl:BAABNQAECn83AAIbAAoKpRGhEAAcAgAbAAoKpRGhEAAcAgAAAA==.',
Si='Siddharthä:BAABNQAECn8dAAIYAAoK6g+jYwCRAQAYAAoK6g+jYwCRAQAAAA==.',
Sk='Skdragon:BAABNQAECn8cAAMXAAkKfRtREQA/AgAXAAgKJB5REQA/AgAgAAUKWA1cEwD7AAAAAA==.Skyara:BAAANQAECgYICgABNQAECgoKLAAhAEgeAA==.Skylaar:BAAANQAECgMIAwAAAA==.',
Sm='Smitey:BAAANQAECgMIAwAAAA==.',
So='Soulstik:BAAANQADCgcIDQAAAA==.',
Sp='Spiritshard:BAAANQAECgEIAgAAAA==.Spriggens:BAAANQAECgcIEQABNQAECgoKQgACAMklAA==.',
St='Stalkr:BAAANQADCgQIBAAAAA==.Sthise:BAAANQADCgYICgAAAA==.',
Sy='Sykoman:BAACNQAFFH8aAAITAAgKfRnGBABfAgATAAgKfRnGBABfAgA1AAQKfykAAhMACgpWJVQNAGADABMACgpWJVQNAGADAAAA.Sykowoman:BAAANQAECgQJBAABNQAFFAgIGgATAH0ZAA==.',
['Sì']='Sìleñtclãw:BAAANQADCgEIAQAAAA==.Sìrius:BAAANQADCggIDgAAAA==.',
Te='Terumi:BAAANQAECgMIBAAAAA==.',
Th='Theodrei:BAAANQABCgQIBwAAAA==.Thiizz:BAABNQAECn8wAAIKAAoKhBxvKACYAgAKAAoKhBxvKACYAgAAAA==.Thracious:BAAANQADCgUIBwAAAA==.Thïzz:BAAANQAECgUIDgABNQAECgoKJwAIAI8hAA==.',
Ti='Ticklemebutt:BAAANQAECgUIEAAAAA==.Tinksy:BAAANQADCgYIBgABNQAECgQICAAGAAAAAA==.Titanx:BAAANQADCgMJBAAAAA==.',
To='Toeto:BAAANQAECgQIBQAAAA==.Toetoeto:BAAANQAECgcIEQAAAA==.Toetoetoete:BAAANQADCgcJCAAAAA==.Tooe:BAAANQAECgQIEgAAAA==.Torquei:BAAANQAECgcIEAAAAA==.Toxan:BAAANQADCgUIBgAAAA==.',
Tp='Tpaman:BAAANQADCgMIBAAAAA==.',
Tr='Triks:BAABNQAECn8YAAMdAAcKdBZQCgDXAQAdAAcKdBZQCgDXAQAiAAEKcgOjqgAmAAAAAA==.',
Ts='Tsjudilla:BAAANQADCgQJBAAAAA==.',
Tu='Tujefe:BAABNQAECn8uAAIFAAkKnhQfawAcAgAFAAkKnhQfawAcAgAAAA==.',
Ty='Tylorialin:BAAANQADCgMIAwABNQAECgoKLAAIALwWAA==.',
Ur='Urpalharsh:BAAANQADCgIIAgABNQAECgkJHgASADkSAA==.',
Va='Vahldire:BAAANQAECgQIAwAAAA==.Valeeraa:BAABNQAECn8XAAMdAAcK/gXAEwDBAAAdAAYKuQXAEwDBAAAiAAMKrwZNRwBfAAAAAA==.Valeri:BAAANQADCgcIBwAAAA==.Varken:BAAANQAECgMIAwAAAA==.',
Vo='Voidwrath:BAAANQABCgMIAwAAAA==.',
Wa='Waeder:BAAANQADCgcIFwAAAA==.Waren:BAAANQAECgMIAwAAAA==.',
Wi='Wingman:BAAANQAECgIIAgAAAA==.Wisteria:BAABNQAECn8vAAQWAAoKUxCpFQDAAQAWAAcK/gypFQDAAQAFAAkKlQzIlQCwAQAVAAEKSQOTNAAoAAABNQAECgUICgAGAAAAAA==.',
Wo='Wompalot:BAAANQADCggIDwABNQAECgcICgAGAAAAAA==.Wompeter:BAAANQAECgcICgAAAA==.Womplock:BAAANQADCgYICwAAAA==.Wompnhood:BAAANQADCgYICQABNQAECgcICgAGAAAAAA==.Wooly:BAAANQADCgMIAwAAAA==.',
Wr='Wrâth:BAABNQAECn8kAAIUAAgKlw370QDiAQAUAAgKlw370QDiAQAAAA==.',
Xa='Xael:BAAANQAECgUICgAAAA==.',
Xu='Xunarii:BAAANQADCgUIBQABNQAECgoKLAAhAEgeAA==.',
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
