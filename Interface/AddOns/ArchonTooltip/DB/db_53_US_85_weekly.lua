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

local lookup = {'Warrior-Arms','Hunter-BeastMastery','Unknown-Unknown','Paladin-Retribution','Evoker-Devastation','Shaman-Elemental','Shaman-Restoration','Warrior-Fury','DemonHunter-Havoc','Priest-Shadow','Priest-Holy','Priest-Discipline','Rogue-Subtlety','Rogue-Assassination','Druid-Balance','Druid-Restoration','Paladin-Holy','Warlock-Demonology','Rogue-Outlaw','Mage-Arcane','Druid-Guardian','Monk-Mistweaver','Mage-Frost','Warrior-Protection','Monk-Windwalker','Warlock-Destruction','DeathKnight-Frost','DeathKnight-Unholy','Hunter-Marksmanship','Evoker-Preservation','DemonHunter-Devourer','Shaman-Enhancement','Paladin-Protection','DemonHunter-Vengeance','Monk-Brewmaster','Warlock-Affliction','Druid-Feral','DeathKnight-Blood','Hunter-Survival',}
local provider = {region='US',realm='Eitrigg',name='US',type='weekly',zone=53,date='2026-10-27',data={Al='Alys:BAAANQAECgcIEgAAAA==.',
Am='Amaniatres:BAABNQAECn8VAAIBAAgKbBVvlQDmAQABAAgKbBVvlQDmAQAAAA==.Ammartin:BAABNQAECn8WAAICAAYKdAnmzQBlAQACAAYKdAnmzQBlAQAAAA==.Amperage:BAAANQADCgUIEAABNQAECggIFQABAGwVAA==.',
An='Anaan:BAAANQAECgUIEAAAAA==.Anahera:BAAANQADCgcIBwABNQAECgQICwADAAAAAA==.Anthion:BAAANQABCgIIAgAAAA==.Anzhelina:BAABNQAECn8cAAIEAAoKjhqpLQBHAgAEAAoKjhqpLQBHAgAAAA==.',
Ap='Apis:BAAANQAECgIIAgAAAA==.Apostasy:BAAANQADCgUIBQAAAA==.Aprys:BAAANQABCggIEwAAAA==.',
Ar='Arathan:BAAANQADCgYIBgAAAA==.Arihana:BAABNQAECn8VAAIFAAYK6AbaJgD+AAAFAAYK6AbaJgD+AAAAAA==.',
As='Asapshocky:BAACNQAFFH8LAAIGAAYKyBKjEgBFAQAGAAYKyBKjEgBFAQA1AAQKfzEAAgYACgooIPgJAOcCAAYACgooIPgJAOcCAAAA.Asmoday:BAAANQADCggIJAAAAA==.',
Ba='Baahp:BAAANQAECgUICgABNQAECgkJLAAHABgXAA==.Barley:BAAANQABCgIIAgAAAA==.',
Be='Belassandra:BAAANQADCggIDQAAAA==.Belgerra:BAABNQAECn8UAAMIAAcKDxc3EACjAQAIAAYKwRQ3EACjAQABAAYKVBIA0ABTAQAAAA==.Bellabelle:BAAANQAECgEIAQAAAA==.Bevian:BAAANQADCgMIAwABNQAECgQIBAADAAAAAA==.',
Bi='Biggiepants:BAABNQAECn8sAAIJAAoKxBUzFgD6AQAJAAoKxBUzFgD6AQAAAA==.Biggnome:BAAANQADCgYIBgABNQAECgEIAQADAAAAAA==.Bighead:BAAANQAECgMIAwABNQAECgEIAQADAAAAAA==.Bigr:BAAANQAECgEIAQAAAA==.Bigwarlocks:BAAANQADCggICAABNQAECgEIAQADAAAAAA==.Biollante:BAAANQADCgYICAAAAA==.',
Bo='Bootyßandaid:BAAANQAECgUIDAAAAA==.',
Bu='Buckis:BAABNQAECn8VAAIEAAYKdQmNAwEZAQAEAAYKdQmNAwEZAQAAAA==.',
Ca='Camderags:BAAANQAECgEIAQAAAA==.Canon:BAAANQAECggICQAAAA==.Catasucked:BAAANQADCgMIAwAAAA==.',
Ce='Celios:BAAANQAECgIIAwAAAA==.',
Ch='Chillin:BAAANQADCgEIAQAAAA==.Choggy:BAABNQAECn8zAAQKAAoKuBGCIQAqAgAKAAkKYRCCIQAqAgALAAYKmBXVawATAQAMAAEKQQ2QKQAxAAAAAA==.Churro:BAAANQADCgcIBwAAAA==.',
Ci='Cindrõz:BAAANQAECgQIBQAAAA==.',
Co='Conception:BAAANQAECgUIBQABNQAECggIIwALAAUXAA==.Cough:BAAANQAECgEIAQAAAA==.',
Cr='Crinklecut:BAABNQAECn8VAAMNAAcK/QeuNgAEAQANAAYKqweuNgAEAQAOAAMKPgjeRABkAAAAAA==.Crow:BAABNQAECn8vAAMPAAoKzCKHCgB4AwAPAAoKzCKHCgB4AwAQAAkKfB5rHQBGAgAAAA==.',
Da='Daijin:BAAANQAECgcIEwAAAA==.Danielallen:BAAANQAECgQIDwAAAA==.Danyrogue:BAAANQAECgcIBwABNQAFFAcIDwACAGcaAA==.',
De='Deadlybeard:BAAANQADCgQICQABNQAECggIMQARAHEkAA==.Deadlywrath:BAABNQAECn8xAAIRAAgKcSSTDwDaAgARAAgKcSSTDwDaAgAAAA==.Deadmenace:BAAANQADCgYJCwAAAA==.Decåying:BAABNQAECn8xAAISAAgKCwpaawAoAQASAAgKCwpaawAoAQAAAA==.Demonsangel:BAAANQAECgUICAAAAA==.Deni:BAAANQAECgQIDQAAAA==.Denli:BAAANQAECgEIAgAAAA==.',
Di='Diagnosis:BAABNQAECn8ZAAIEAAgKRCQ6IABDAwAEAAgKRCQ6IABDAwAAAA==.Divine:BAAANQAECgEIAQAAAA==.',
Do='Doctrine:BAAANQAECgIIAgAAAA==.Donnabb:BAAANQAECgYIEgAAAA==.Donteatbees:BAAANQAECgYICwAAAA==.Dop:BAAANQAECgUICQAAAA==.Doran:BAAANQADCgUIBQAAAA==.Dottierotten:BAAANQAECgIIAwAAAA==.',
Dr='Drenrah:BAABNQAECn8pAAMRAAkKQBApLQDzAQARAAkKQBApLQDzAQAEAAEKAAByywEiAAAAAA==.',
Ed='Edend:BAAANQADCgUICgAAAA==.',
Ei='Eiduartpaw:BAAANQAECggIEQAAAA==.',
El='Elbryan:BAAANQAECgYIDwAAAA==.Electracutie:BAABNQAECn8bAAIHAAgKiApAUwBKAQAHAAgKiApAUwBKAQAAAA==.Elementdemon:BAABNQAECn8qAAITAAkKtBFgCQD2AQATAAkKtBFgCQD2AQAAAA==.',
En='Enthalpy:BAABNQAECn8yAAIUAAoK9RrOYwC2AgAUAAoK9RrOYwC2AgAAAA==.',
Es='Esperzoa:BAAANQAECgUIDQAAAA==.',
Eu='Eucalicdes:BAABNQAECn89AAIVAAoKExfBCwD8AQAVAAoKExfBCwD8AQAAAA==.',
Ev='Evøkër:BAAANQADCgQIBAABNQAECgoKJQAWAMgbAA==.',
Ez='Ezra:BAAANQADCgcIDQAAAA==.',
Fa='Falshin:BAAANQADCggICAAAAA==.Fancy:BAAANQAECgMIBQAAAA==.Fangyi:BAABNQAECn8xAAMXAAgKIRKuDwCtAQAXAAgKIRKuDwCtAQAUAAcKjwo6FQFpAQAAAA==.',
Fi='Fiction:BAAANQAECggIEAAAAA==.',
Fl='Flabutt:BAAANQAECgYICAAAAA==.Florita:BAAANQAECgMIBAAAAA==.',
Fo='Fordinn:BAABNQAECn8rAAQYAAcKKhsiGQCgAQAYAAcKiBUiGQCgAQABAAYKvxRWwwB0AQAIAAQKMhwJGgACAQAAAA==.',
Fr='Freeree:BAAANQADCgMIAwAAAA==.Fren:BAAANQAECgYIEAAAAA==.Frenzy:BAAANQAECgIIAQAAAA==.Fruitcakes:BAAANQAECgIIAgAAAA==.',
Fu='Furrypunch:BAABNQAECn8lAAMWAAoKyBvZCwDGAgAWAAoKyBvZCwDGAgAZAAEKJgE4UAAXAAAAAA==.',
Ga='Garataz:BAAANQADCgUIBQABNQAECgIIAwADAAAAAA==.Garzhvog:BAAANQAECgYIBgABNQAECgoKNAAaAJQgAA==.Gasket:BAACNQAFFH8FAAIbAAIKExYsDQCZAAAbAAIKExYsDQCZAAA1AAQKfzAAAxwACgrOHAg5AEECABwACArAHAg5AEECABsACAoNGewyAFYBAAAA.',
Gh='Ghostdragona:BAAANQADCgcIBwAAAA==.Ghostown:BAAANQADCgQIBAAAAA==.',
Go='Goliathan:BAAANQAECgEIAQAAAA==.',
Gr='Graceful:BAABNQAECn8pAAIZAAkKHA1TMACUAQAZAAkKHA1TMACUAQAAAA==.Grenie:BAAANQADCgcICAAAAA==.Grit:BAAANQAECgUICAAAAA==.Grëzel:BAAANQADCgYIBgABNQAECgUIBwADAAAAAA==.',
Ha='Handicap:BAAANQAECgEIAgABNQAECggIGQAEAEQkAA==.Hark:BAACNQAFFH8FAAICAAIKdwkKGQCMAAACAAIKdwkKGQCMAAA1AAQKfy4AAwIACgqSG9Q/AKsCAAIACgqSG9Q/AKsCAB0AAQpjCPiLADMAAAAA.Harpin:BAABNQAECn8uAAILAAoKsh1fFADDAgALAAoKsh1fFADDAgAAAA==.Harvin:BAABNQAECn8qAAIeAAgK/x6nBgB8AgAeAAgK/x6nBgB8AgAAAA==.',
He='Heals:BAAANQAECggICAAAAA==.Heisenburgg:BAAANQAECgEIAQABNQAECgYIBwADAAAAAA==.Helanua:BAABNQAECn8mAAIGAAgKWA4jSgAwAQAGAAgKWA4jSgAwAQAAAA==.',
Hi='Highlight:BAAANQAECgcIEAAAAA==.Hippopotamus:BAAANQADCgIIAgAAAA==.Hit:BAAANQAECgYIBwAAAA==.Hitt:BAAANQADCgEIAQABNQAECgYIBwADAAAAAA==.',
Ho='Holyish:BAAANQAECgIIAgAAAA==.Holyrollers:BAABNQAECn8YAAILAAoKyAgQWQBQAQALAAoKyAgQWQBQAQAAAA==.Holytide:BAABNQAECn8WAAMHAAcK5Q5HZAARAQAHAAYKowtHZAARAQAGAAUK6gIj6ADHAAAAAA==.Hops:BAAANQADCgQIBAAAAA==.Hornsie:BAAANQADCgIIAgAAAA==.Horrorfang:BAABNQAECn8lAAIcAAgKLhopOABFAgAcAAgKLhopOABFAgAAAA==.',
['Hä']='Häwke:BAAANQAECgEIAQAAAA==.',
Ib='Ibaar:BAACNQAFFH8ZAAIFAAcK3iNeAADFAgAFAAcK3iNeAADFAgA1AAQKfygAAgUACgroI1oGACUDAAUACgroI1oGACUDAAAA.',
Ic='Icialiaa:BAAANQADCgIIAgABNQAECgQIBAADAAAAAA==.',
In='Inno:BAABNQAECn8nAAIfAAoKYCK8BADeAgAfAAoKYCK8BADeAgAAAA==.',
It='Ithacus:BAABNQAECn8sAAIgAAkKNBZ1DQC6AQAgAAkKNBZ1DQC6AQAAAA==.Itspriesty:BAAANQAECgEIAQAAAA==.',
Ja='Janari:BAAANQADCggIFAAAAA==.Jandaar:BAAANQADCgYICQAAAA==.Jatt:BAAANQADCggICAAAAA==.Jattix:BAAANQADCgQIBAAAAA==.',
Jd='Jdawgprime:BAAANQABCgQIBAAAAA==.',
Ji='Jilkaeden:BAAANQAECgcIEgAAAA==.',
Jo='Jorek:BAABNQAECn8xAAIBAAgKdQ1bdgAqAQABAAgKdQ1bdgAqAQAAAA==.Josh:BAAANQAECgMICgAAAA==.',
Jr='Jrue:BAAANQADCgcIBwAAAA==.',
Ju='Jurtkal:BAAANQAECgEIAgAAAA==.',
Ka='Kaiva:BAAANQAECgQICwAAAA==.Kavik:BAAANQAECgIIAgAAAA==.',
Ke='Keflá:BAAANQAECgQICAAAAA==.Keineliebe:BAAANQAECgIIAgAAAA==.Kelencye:BAAANQAECgMICQAAAA==.',
Kh='Khaas:BAABNQAECn8gAAIcAAcKoApwMgD7AAAcAAcKoApwMgD7AAAAAA==.Khanloa:BAAANQADCgUIBQAAAA==.Kheleze:BAAANQAECgUICQABNQAECgcIFAAhAMkbAA==.',
Ki='Killerbell:BAAANQAECgYICQAAAA==.Killshot:BAAANQAECgEIAgAAAA==.',
Ko='Korihor:BAAANQAECgQIEwAAAA==.',
Kr='Krestus:BAABNQAECn8iAAQfAAoKsx++DQAQAgAfAAkKOB6+DQAQAgAiAAcKKR/JDgDMAQAJAAQKrA5HOQDtAAAAAA==.Krispy:BAABNQAECn8XAAQZAAcKdBg2KADeAQAZAAcKdBg2KADeAQAjAAcKFQlQDQDsAAAWAAEKxAL6VAAgAAAAAA==.Krispyy:BAAANQAECgcICgAAAA==.Krix:BAAANQAECgYICAAAAA==.',
Ku='Kuroji:BAAANQABCgEIAQAAAA==.',
La='Laerin:BAAANQAECgYICAAAAA==.Landreielea:BAABNQAECn8aAAICAAkKAAwUmADYAQACAAkKAAwUmADYAQAAAA==.Laxus:BAAANQAECgYIEgAAAA==.',
Le='Lerenor:BAAANQAECgUIBwAAAA==.Levophed:BAAANQAECgUJCgAAAA==.',
Li='Lily:BAABNQAECn8YAAIVAAcKRBCRIgCDAQAVAAcKRBCRIgCDAQAAAA==.Linnt:BAAANQAECgEIAgAAAA==.Liyara:BAACNQAFFH8FAAIEAAIKmhjDFACYAAAEAAIKmhjDFACYAAA1AAQKfy8AAgQACgoJJC0ZAF8DAAQACgoJJC0ZAF8DAAAA.',
Ll='Llorsa:BAABNQAECn8lAAILAAcKsQttXgA9AQALAAcKsQttXgA9AQAAAA==.Lltoj:BAAANQADCgEIAQAAAA==.',
Lu='Lusavahza:BAAANQADCgUIBgAAAA==.Luxian:BAAANQAECgIIAgAAAA==.',
Ly='Lyann:BAAANQAECgEIAQAAAA==.Lyssirix:BAAANQAECgEIAQAAAA==.',
['Lä']='Ländrei:BAAANQAECgIIAwABNQAECgkJGgACAAAMAA==.',
Ma='Macy:BAAANQABCgIIAgAAAA==.Mahralla:BAAANQADCgUIBQAAAA==.Maikagond:BAAANQADCgYIBgABNQAECgoKMwAEAOwLAA==.Makaria:BAAANQAECgUIEAAAAA==.Malbisa:BAAANQAECgUICwAAAA==.Malphoz:BAAANQADCgUIBQAAAA==.Mandragora:BAAANQAECgIIAwAAAA==.Marli:BAAANQADCgIIAgAAAA==.',
Mc='Mcsorley:BAAANQADCgMIAwAAAA==.',
Mi='Mickey:BAABNQAECn8aAAIZAAkKvhuxGgBpAgAZAAkKvhuxGgBpAgAAAA==.Mikiik:BAABNQAECn8dAAMaAAYKTAUrSgChAAASAAQKBgVpFAGhAAAaAAUKwwUrSgChAAAAAA==.Mikk:BAAANQADCgIJAgAAAA==.Mildoo:BAABNQAECn8mAAIkAAkKPg7ABAClAQAkAAkKPg7ABAClAQAAAA==.Milkymoo:BAAANQAECgUICQABNQAFFAcIIgALALYWAA==.',
Mo='Monq:BAAANQAECggIEQAAAA==.Moón:BAABNQAECn8gAAIlAAgKsg/IFQCfAQAlAAgKsg/IFQCfAQAAAA==.',
My='Mythlocked:BAAANQAECgIIAgAAAA==.',
['Mî']='Mîlk:BAAANQADCgIIAgAAAA==.',
Na='Naomii:BAAANQADCgIIAgAAAA==.Narus:BAAANQAECgYICwABNQAECgcIKwAYACobAA==.',
Ne='Nephadin:BAAANQADCggICAABNQAECgoKMgAhAGYgAA==.Neviaa:BAABNQAECn8kAAMcAAgKwhdJRAAJAgAcAAgKwhdJRAAJAgAmAAYKtg2uRADPAAAAAA==.',
Ni='Nickypoo:BAAANQADCgYICQAAAA==.Nightmenace:BAAANQAECgQIBgAAAA==.Niq:BAAANQAECgIIAgAAAA==.',
No='Norii:BAAANQADCgMIAwABNQAECgQIBAADAAAAAA==.Nothealster:BAABNQAECn8ZAAIKAAcKAgkiPQBCAQAKAAcKAgkiPQBCAQAAAA==.Novacane:BAAANQAECgEIAgAAAA==.',
Ob='Obitrice:BAABNQAECn8aAAICAAgKVxK6nADNAQACAAgKVxK6nADNAQABNQAECgYIFQAVAKwVAA==.Obsidiian:BAAANQAECggIDwAAAA==.Obsidion:BAABNQAECn8SAAMLAAcKOgjMpgAhAQALAAYKiQjMpgAhAQAKAAUKCgnQLwCWAAABNQAECgcIKwAYACobAA==.',
Od='Odie:BAAANQAECgIIAgAAAA==.',
Or='Organdonor:BAABNQAECn8gAAILAAoKQRAMYwD3AQALAAoKQRAMYwD3AQAAAA==.',
Os='Ossin:BAAANQAECgIIBgAAAA==.',
Pa='Pantherlilly:BAAANQAECgUICwAAAA==.',
Pe='Perry:BAAANQAECgUICgAAAA==.',
Ph='Phlampped:BAAANQADCgYIBgABNQAFFAYIBwAIABEKAA==.',
Po='Pozufuma:BAABNQAECn8lAAIIAAcKmhlIDAD4AQAIAAcKmhlIDAD4AQAAAA==.',
Ps='Psychomantis:BAABNQAECn81AAMKAAoKmhX6LQC1AQAKAAgKqxD6LQC1AQALAAoKngsAZQApAQAAAA==.',
Ra='Radium:BAAANQADCgcICAAAAA==.Ravenbear:BAAANQAECgUIEAAAAA==.',
Re='Redpool:BAABNQAECn8gAAICAAkKGguSXQCFAQACAAkKGguSXQCFAQAAAA==.Rethandra:BAAANQAECgEIAQAAAA==.Retrix:BAAANQAECgQICAAAAA==.Revorra:BAAANQAECgUIEAABNQAECgcIKwAYACobAA==.Rezelflezel:BAAANQAECgYIBwAAAA==.',
Ri='Ristvakbaen:BAABNQAECn80AAQaAAoKlCA8AgDiAQASAAgKixyFWgBHAgAaAAgK/h88AgDiAQAkAAIKxRICKgBFAAAAAA==.',
Ro='Robynlee:BAABNQAECn8jAAILAAgKBRepaADlAQALAAgKBRepaADlAQAAAA==.Rohini:BAAANQADCgQIBgAAAA==.Rovik:BAAANQAECgQICgAAAA==.',
Sa='Santeclair:BAAANQAECgEIAQAAAA==.',
Sc='Sceryna:BAABNQAECn8lAAMEAAoKbRqHYgBzAgAEAAoKbRqHYgBzAgAhAAIKtReBXgBhAAAAAA==.Schiftly:BAAANQADCgQIBAAAAA==.Scrmndemn:BAABNQAECn8YAAIEAAgKHwR/CQEPAQAEAAgKHwR/CQEPAQAAAA==.',
Se='Sef:BAAANQAECgUIDgAAAA==.Sequan:BAAANQADCgUIBQAAAA==.Serpent:BAAANQAFFAMIBAABNQAFFAUIBgAhANcGAA==.',
Sh='Shamadeus:BAAANQAECgYICgABNQAECgoKNAAaAJQgAA==.Shamenio:BAAANQAECgEIAQAAAA==.Shamtastical:BAABNQAECn8WAAIHAAcKhhIbnwA5AQAHAAcKhhIbnwA5AQABNQAECggIIwALAAUXAA==.Sheeara:BAAANQADCgIIAgAAAA==.Shikita:BAABNQAECn8mAAIQAAcKaR4WGwBfAgAQAAcKaR4WGwBfAgAAAA==.Shimadin:BAACNQAFFH8SAAIEAAYKsBAIEQA9AQAEAAYKsBAIEQA9AQA1AAQKfz4AAgQACgoaI5wNAAgDAAQACgoaI5wNAAgDAAAA.Shimjun:BAAANQAECgYIBwABNQAFFAYIEgAEALAQAA==.Shimsong:BAAANQAECgEIAwABNQAFFAYIEgAEALAQAA==.Shirma:BAAANQAECgEIAQAAAA==.Shmerek:BAABNQAECn8xAAIYAAgKxhjzDABpAQAYAAgKxhjzDABpAQAAAA==.',
Si='Sierramist:BAABNQAECn8wAAIWAAgK9xyGBwBqAgAWAAgK9xyGBwBqAgAAAA==.Sijon:BAAANQAECgEIAQAAAA==.Silverpacem:BAAANQAECgQIBgAAAA==.Silverstream:BAABNQAECn82AAIQAAoK2xn9DQBOAgAQAAoK2xn9DQBOAgAAAA==.',
So='Solbin:BAABNQAECn8gAAIiAAgKnCLCAwAgAwAiAAgKnCLCAwAgAwABNQAECgoKMAAUAKEfAA==.Solexine:BAAANQADCgQIBAAAAA==.Solitudé:BAAANQAECgQIDAABNQAFFAIIBQAbAP4cAA==.Soteirian:BAABNQAECn8zAAMEAAoK7AuKZACPAQAEAAoK7AuKZACPAQAhAAEKAADVdwAlAAAAAA==.',
Sp='Spiritlinkin:BAABNQAECn8iAAIGAAkKPBhRLACtAQAGAAkKPBhRLACtAQAAAA==.',
St='Stalariais:BAAANQADCgYIBgABNQAECggIDwADAAAAAA==.Steakhammer:BAAANQAECgYIBQABNQAECgoKJQAWAMgbAA==.Steve:BAABNQAECn8WAAIBAAYKCQ3kzABbAQABAAYKCQ3kzABbAQAAAA==.Straw:BAAANQAECgEIAQABNQAECgoKJQAEAH0PAA==.',
Su='Sugardawn:BAAANQAECgQIBQAAAA==.Sugarkitty:BAAANQADCgcIBwAAAA==.Supereclipse:BAABNQAECn8kAAICAAcKnhH1bwBXAQACAAcKnhH1bwBXAQAAAA==.',
Sy='Sydvicious:BAABNQAECn8rAAIJAAoKFyHjCADGAgAJAAoKFyHjCADGAgAAAA==.',
Ta='Taintedwater:BAAANQAECgQIBAAAAA==.Tairnanach:BAAANQADCgYIDgAAAA==.Taladiir:BAAANQAECggIDgAAAA==.Talana:BAAANQAECgcIDQAAAA==.Tayger:BAAANQADCgcJEAAAAA==.',
Td='Tdog:BAAANQADCgcIDgAAAA==.',
Te='Tecks:BAABNQAECn8xAAILAAgKBA3NSgCGAQALAAgKBA3NSgCGAQAAAA==.Teslá:BAAANQAECgEIAQAAAA==.',
Th='Thaldur:BAAANQAECgIIAgABNQAECgoKIgAfALMfAA==.Thayo:BAAANQAECgEIAwAAAA==.Theatrix:BAAANQAECgMIBQABNQAECggIFQABAGwVAA==.Themajor:BAAANQAECgQIBQAAAA==.Therossyas:BAAANQAECgYIEQAAAA==.Thezuggest:BAAANQADCgMJAwAAAA==.Thicctotems:BAACNQAFFH8RAAMHAAUKwCBKDQB5AQAHAAUKwCBKDQB5AQAGAAEKCQTbNAA/AAA1AAQKfzAAAwcACQqTH1cLAA4DAAcACQqTH1cLAA4DAAYAAgoRFA0DAYkAAAAA.Threat:BAABNQAECn82AAIEAAkK2iRuCwCkAwAEAAkK2iRuCwCkAwAAAA==.Thunderthigh:BAAANQADCgYIAwAAAA==.Thungerthi:BAAANQADCgUICAAAAA==.',
Ti='Tiamaat:BAABNQAECn8xAAMPAAgKpgV2OgDdAAAPAAgKpgV2OgDdAAAQAAEK6QFnegApAAAAAA==.Tinysanta:BAAANQAECgIIBQAAAA==.Titus:BAAANQADCgYICQAAAA==.',
To='Toatani:BAAANQADCgMJAwABNQAECgQICwADAAAAAA==.Tokkaebi:BAAANQAECgMIBQAAAA==.Torvar:BAAANQADCggIDwAAAA==.',
Ty='Tyletos:BAABNQAECn8wAAMUAAoKoR/JIQBUAwAUAAoKZx/JIQBUAwAXAAUKXR02EgCDAQAAAA==.',
Ug='Ugolok:BAAANQADCgcIDQAAAA==.',
Ur='Uriél:BAAANQADCgQIBAABNQAFFAIIBQAbAP4cAA==.Urubaen:BAAANQAECggIDgABNQAECgoKNAAaAJQgAA==.',
Va='Valanoth:BAAANQADCgIIAgAAAA==.Valeene:BAABNQAECn8oAAIPAAoKMB86GgD3AgAPAAoKMB86GgD3AgAAAA==.Varek:BAAANQAECgEIAQAAAA==.Varlann:BAAANQAECgEIAwAAAA==.',
Ve='Veiler:BAABNQAECn83AAQCAAoKZw1kSgC+AQACAAkK/wxkSgC+AQAdAAgKDgU5RAA3AQAnAAIKiAPkDQA2AAAAAA==.Veruca:BAAANQAECgYIBwAAAA==.Veviseron:BAABNQAECn8tAAIXAAkK/wZuGgAhAQAXAAkK/wZuGgAhAQAAAA==.',
Vi='Vinstalation:BAAANQAECgQICgAAAA==.',
Vo='Vonbismarck:BAABNQAECn8nAAMCAAkKkAvVTwCtAQACAAkKhQvVTwCtAQAdAAYKmAk7RwAiAQAAAA==.',
Vr='Vritraz:BAACNQAFFH8FAAIbAAIK/hyHDAClAAAbAAIK/hyHDAClAAA1AAQKfy4AAhsACgrLIIMKAEYDABsACgrLIIMKAEYDAAAA.',
Wa='Warsonge:BAAANQAECgUICgAAAA==.Waxoff:BAAANQAECgIIAgAAAA==.',
We='Wendypini:BAABNQAECn85AAICAAoKdRbmSgCNAgACAAoKdRbmSgCNAgAAAA==.',
Wh='Whitlock:BAAANQAECgMIBgAAAA==.',
Xe='Xendria:BAAANQADCggICgAAAA==.',
Ya='Yannhal:BAAANQAECgIIAwAAAA==.',
Za='Zangelf:BAAANQABCggIFAAAAA==.Zangolf:BAAANQAECgEIAwAAAA==.',
Zo='Zodiaac:BAABNQAECn8xAAImAAgKtxcHOAAoAgAmAAgKtxcHOAAoAgAAAA==.',
Zy='Zy:BAAANQAECgEIAQAAAA==.',
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
