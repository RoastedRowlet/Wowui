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

local lookup = {'Warrior-Arms','Hunter-BeastMastery','Unknown-Unknown','Paladin-Retribution','Evoker-Devastation','Shaman-Elemental','Shaman-Restoration','Warrior-Fury','DemonHunter-Havoc','Priest-Shadow','Priest-Holy','Priest-Discipline','Rogue-Subtlety','Rogue-Assassination','Druid-Balance','Druid-Restoration','Druid-Feral','Paladin-Holy','Warlock-Demonology','Paladin-Protection','Rogue-Outlaw','Mage-Arcane','Druid-Guardian','Monk-Mistweaver','Mage-Frost','Warrior-Protection','Monk-Windwalker','Warlock-Affliction','DeathKnight-Frost','DeathKnight-Unholy','Hunter-Marksmanship','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Devourer','Shaman-Enhancement','DemonHunter-Vengeance','Monk-Brewmaster','Warlock-Destruction','DeathKnight-Blood','Hunter-Survival',}
local provider = {region='US',realm='Eitrigg',name='US',type='weekly',zone=53,date='2026-11-03',data={Al='Alys:BAAANQAECgcIDwAAAA==.',
Am='Amaniatres:BAABNQAECn8VAAIBAAgKbBVvlQDmAQABAAgKbBVvlQDmAQAAAA==.Ammartin:BAABNQAECn8cAAICAAYKdAnmzQBlAQACAAYKdAnmzQBlAQAAAA==.Amperage:BAAANQADCgUIEAABNQAECggIFQABAGwVAA==.',
An='Anaan:BAAANQAECgYIDAAAAA==.Anahera:BAAANQADCgcIBwABNQAECgQICQADAAAAAA==.Anthion:BAAANQADCgEIAwAAAA==.Anzhelina:BAABNQAECn8gAAIEAAoKHB2YNgBcAgAEAAoKHB2YNgBcAgAAAA==.',
Ap='Apis:BAAANQAECgIIAgAAAA==.Apostasy:BAAANQADCgUIBQAAAA==.Aprys:BAAANQADCgEIAQAAAA==.',
Ar='Arathan:BAAANQADCggIDgAAAA==.Arihana:BAABNQAECn8VAAIFAAYK6AbaJgD+AAAFAAYK6AbaJgD+AAAAAA==.',
As='Asapshocky:BAACNQAFFH8LAAIGAAYKyBKjEgBFAQAGAAYKyBKjEgBFAQA1AAQKfzsAAgYACgpGIzAIACcDAAYACgpGIzAIACcDAAAA.Asmoday:BAAANQADCggILAAAAA==.',
Az='Azerwrath:BAAANQADCgEIAQAAAA==.',
Ba='Baahp:BAAANQAECgcIEAABNQAECgoKNQAHANMVAA==.Balgarde:BAAANQADCgEIAQAAAA==.Barley:BAAANQADCgEIAQAAAA==.',
Be='Bearlytanks:BAAANQAECgIIAgAAAA==.Belassandra:BAAANQAECgQIBAAAAA==.Belgerra:BAABNQAECn8aAAMIAAcKNBc3EACjAQAIAAYKwRQ3EACjAQABAAcKFxFKlQAfAQAAAA==.Bellabelle:BAAANQAECgEIAQAAAA==.Bevian:BAAANQAECgIIAgABNQAECgUIDwADAAAAAA==.',
Bi='Biggiepants:BAABNQAECn82AAIJAAoKEBeuHADvAQAJAAoKEBeuHADvAQAAAA==.Biggnome:BAAANQADCgYIBgABNQADCgUICQADAAAAAA==.Bighead:BAAANQAECgMIAwABNQADCgUICQADAAAAAA==.Bigr:BAAANQADCgcICAAAAA==.Bigwarlocks:BAAANQADCggICAABNQADCgUICQADAAAAAA==.Biollante:BAAANQADCgYICQAAAA==.',
Bo='Bootyßandaid:BAAANQAECgUICgAAAA==.',
Bu='Buckis:BAABNQAECn8aAAIEAAYKdQmNAwEZAQAEAAYKdQmNAwEZAQAAAA==.',
Ca='Cahk:BAAANQADCgEIAQAAAA==.Camderags:BAAANQADCggICAAAAA==.Canon:BAAANQAECggICAAAAA==.Casidor:BAAANQADCgEIAQAAAA==.Catasucked:BAAANQADCgMIAwAAAA==.',
Ce='Celios:BAAANQAECgIIAgAAAA==.',
Ch='Chillin:BAAANQADCgEIAQAAAA==.Choggy:BAABNQAECn85AAQKAAoKoBKCIQAqAgAKAAkKsBCCIQAqAgALAAYKmBUyhgAMAQAMAAEKQQ2QKQAxAAAAAA==.Churro:BAAANQADCgcIBwAAAA==.',
Ci='Cindrõz:BAAANQAECgQIBAAAAA==.',
Co='Conception:BAAANQAECgUIBQABNQAECgkJJAALAA0VAA==.Cough:BAAANQADCgUICQAAAA==.',
Cr='Crinklecut:BAABNQAECn8VAAMNAAcK/QeuNgAEAQANAAYKqweuNgAEAQAOAAMKPghNTABdAAAAAA==.Crow:BAABNQAECn8zAAMPAAoKBSOHCgB4AwAPAAoKBSOHCgB4AwAQAAkKfB5rHQBGAgAAAA==.',
Da='Daijin:BAABNQAECn8cAAIRAAkKGBS4CgDhAQARAAkKGBS4CgDhAQAAAA==.Danielallen:BAAANQAECgQICQAAAA==.Danyrogue:BAAANQAECgcIBwABNQAFFAcIDwACAGcaAA==.',
De='Deadlybeard:BAAANQADCgQICQABNQAECggINQASAHEkAA==.Deadlywrath:BAABNQAECn81AAISAAgKcSRdGADHAgASAAgKcSRdGADHAgAAAA==.Deadmenace:BAAANQADCgYJCwAAAA==.Decåying:BAABNQAECn8zAAITAAgKmwqwhAAeAQATAAgKmwqwhAAeAQAAAA==.Demonsangel:BAAANQAECgQIBAAAAA==.Deni:BAAANQAECgUICQAAAA==.Denli:BAAANQADCgQIAwAAAA==.',
Di='Diagnosis:BAABNQAECn8dAAIEAAoKNyI6IABDAwAEAAoKNyI6IABDAwAAAA==.Divine:BAAANQAECgEIAQAAAA==.',
Do='Doctaz:BAAANQAECgMIAwAAAA==.Doctrine:BAAANQAECgIIAgAAAA==.Donnabb:BAAANQAECgYIEgAAAA==.Donteatbees:BAAANQAECgcICwAAAA==.Dop:BAAANQAECgUIBwAAAA==.Doran:BAAANQADCgUIBQAAAA==.Dottierotten:BAAANQAECgIIAgAAAA==.',
Dr='Drenrah:BAABNQAECn8vAAMSAAkKQBBJQQDcAQASAAkKQBBJQQDcAQAEAAQKMgOSSgFRAAAAAA==.',
Ed='Edend:BAAANQADCgUICgAAAA==.',
Ei='Eiduartpaw:BAABNQAECn8aAAQSAAoKtwrDwAD6AAASAAoKtwrDwAD6AAAUAAUKiguMPgCDAAAEAAIK6gXSRAFYAAABNQAFFAQICAACAGoXAA==.',
El='Elbryan:BAAANQAECgYICAAAAA==.Electracutie:BAABNQAECn8bAAIHAAgKiAo/agBDAQAHAAgKiAo/agBDAQAAAA==.Elementdemon:BAABNQAECn8tAAIVAAkK5hI6AwCQAQAVAAkK5hI6AwCQAQAAAA==.',
En='Enthalpy:BAABNQAECn87AAIWAAoK+Bu4LwBjAgAWAAoK+Bu4LwBjAgAAAA==.',
Er='Eross:BAAANQADCgEIAQAAAA==.',
Es='Esperzoa:BAAANQAECgUIDAAAAA==.',
Eu='Eucalicdes:BAABNQAECn9DAAIXAAoKvRd1DwBrAgAXAAoKvRd1DwBrAgAAAA==.',
Ev='Evøkër:BAAANQADCgQIBQABNQAECgoKLwAYAHkeAA==.',
Ez='Ezra:BAAANQAECgIIAgAAAA==.',
Fa='Falshin:BAAANQADCggICAAAAA==.Fancy:BAAANQAECgIIAwAAAA==.Fangyi:BAABNQAECn8zAAMZAAgKVxKuDwCtAQAZAAgKVxKuDwCtAQAWAAcKjwo6FQFpAQAAAA==.Faytes:BAAANQAECgMIAwAAAA==.',
Fi='Fiction:BAAANQAECggIDAAAAA==.Findy:BAAANQADCgEIAgAAAA==.',
Fl='Flabutt:BAAANQAECgYIBwAAAA==.Florita:BAAANQAECgQICQAAAA==.',
Fo='Fordinn:BAABNQAECn8yAAQaAAgK4RjEFAA4AQABAAgKnxJWwwB0AQAaAAcKdxbEFAA4AQAIAAQKMhwJGgACAQAAAA==.',
Fr='Freemi:BAAANQAECgQIBAAAAA==.Freeree:BAAANQADCgMIAwAAAA==.Fren:BAAANQAECgYIEAAAAA==.Fruitcakes:BAAANQAECgIIAgAAAA==.',
Fu='Furrypunch:BAABNQAECn8vAAMYAAoKeR5nBgDwAgAYAAoKeR5nBgDwAgAbAAEKJgGIWwAWAAAAAA==.',
Ga='Garataz:BAAANQADCgUIBQABNQAECgYIBwADAAAAAA==.Garzhvog:BAAANQAECggICgABNQAECgoKPgAcAGshAA==.Gasket:BAACNQAFFH8HAAIdAAIKwxc4EACiAAAdAAIKwxc4EACiAAA1AAQKfzUAAx4ACgr6HAg5AEECAB4ACArAHAg5AEECAB0ACAq4GjoxAKcBAAAA.',
Gh='Ghostdragona:BAAANQADCgcICAAAAA==.Ghostown:BAAANQADCgQIBAAAAA==.',
Gr='Graceful:BAABNQAECn8vAAIbAAkKtw56HwBqAQAbAAkKtw56HwBqAQAAAA==.Gravehammer:BAAANQADCgEIAQAAAA==.Grenie:BAAANQADCgcICAAAAA==.Grit:BAAANQAECgUICAAAAA==.Grëzel:BAAANQADCgYIBgABNQAECgUIBwADAAAAAA==.',
Ha='Handicap:BAAANQAECgEIAQABNQAECgoKHQAEADciAA==.Hark:BAACNQAFFH8HAAICAAIKTA6YHQCTAAACAAIKTA6YHQCTAAA1AAQKfzIAAwIACgpsHNQ/AKsCAAIACgpsHNQ/AKsCAB8AAQpjCPiLADMAAAAA.Harpin:BAABNQAECn84AAILAAoKGh7CFAAFAwALAAoKGh7CFAAFAwAAAA==.Harvin:BAABNQAECn8yAAIgAAgKwx9WCACTAgAgAAgKwx9WCACTAgAAAA==.',
He='Heals:BAAANQAECggICAAAAA==.Heisenburgg:BAAANQAECgMIAgABNQAECgYIBQADAAAAAA==.Helanua:BAABNQAECn8nAAIGAAgKfQ85XAA2AQAGAAgKfQ85XAA2AQAAAA==.Heshangxiong:BAAANQADCgEIAQAAAA==.',
Hi='Highlight:BAAANQAECgcIDgAAAA==.Hippopotamus:BAAANQADCgIIAgAAAA==.Hit:BAAANQAECgYIBQAAAA==.Hitt:BAAANQADCgEIAgABNQAECgYIBQADAAAAAA==.',
Ho='Holybuttkick:BAAANQADCggICQAAAA==.Holyish:BAAANQAECgIIAgAAAA==.Holyrollers:BAABNQAECn8cAAILAAoKDAlaYQCAAQALAAoKDAlaYQCAAQAAAA==.Holytide:BAABNQAECn8cAAMHAAcKsRF6cwAlAQAHAAYK5w56cwAlAQAGAAUKeAMj6ADHAAAAAA==.Hops:BAAANQADCgQICAAAAA==.Hornsie:BAAANQADCgIIAgAAAA==.Horrorfang:BAABNQAECn8uAAIeAAkKGx3lFAAeAgAeAAkKGx3lFAAeAgAAAA==.',
['Hä']='Häwke:BAAANQADCgQICAAAAA==.',
Ib='Ibaar:BAACNQAFFH8bAAMFAAgKPyJeAADFAgAFAAcK3iNeAADFAgAhAAEKIho2CgBZAAA1AAQKfywAAgUACgo/JFoGACUDAAUACgo/JFoGACUDAAAA.',
Ic='Icialiaa:BAAANQADCgIIAwABNQAECgYIBgADAAAAAA==.',
In='Inno:BAABNQAECn8vAAIiAAoKCCUaBAAXAwAiAAoKCCUaBAAXAwAAAA==.',
It='Ithacus:BAABNQAECn8yAAIjAAkKLhdjEADSAQAjAAkKLhdjEADSAQAAAA==.Itspriesty:BAAANQAECgEIAQAAAA==.',
Ja='Janari:BAAANQADCggIFgAAAA==.Jandaar:BAAANQADCgYICQAAAA==.Jatt:BAAANQAECggIBgAAAA==.Jattix:BAAANQADCgQIBAAAAA==.',
Jd='Jdawgprime:BAAANQADCgEIAQABNQADCgEIAQADAAAAAA==.',
Ji='Jilkaeden:BAAANQAECgcIDwAAAA==.',
Jo='Jorek:BAABNQAECn81AAIBAAgKOA7qhQBCAQABAAgKOA7qhQBCAQAAAA==.Josh:BAAANQAECgMICQAAAA==.',
Jr='Jrue:BAAANQAECgMIBQAAAA==.',
Ju='Jurtkal:BAAANQAECgIIAQAAAA==.',
Ka='Kaiva:BAAANQAECgQICQAAAA==.Katabrie:BAAANQADCgEIAQAAAA==.Kavik:BAAANQAECgIIAgAAAA==.Kazulyn:BAAANQADCgEIAQAAAA==.',
Ke='Keflá:BAAANQAECgQIBwAAAA==.Keineliebe:BAAANQAECgIIAgAAAA==.Kelencye:BAAANQAECgMICQAAAA==.',
Kh='Khaas:BAABNQAECn8mAAIeAAcKoAqJOwD7AAAeAAcKoAqJOwD7AAAAAA==.Khanloa:BAAANQADCgUIBwAAAA==.Kheleze:BAAANQAECgUICAABNQAECgcIFAAUAMkbAA==.',
Ki='Killerbell:BAAANQAECgYICwAAAA==.Killshot:BAAANQADCgcICQAAAA==.',
Ko='Korihor:BAABNQAECn8aAAIUAAYKzA0ROwAYAQAUAAYKzA0ROwAYAQAAAA==.',
Kr='Krestus:BAABNQAECn8jAAQiAAoKsx87EwD8AQAiAAkKOB47EwD8AQAkAAcKKR/JDgDMAQAJAAQKrA4xRQDeAAAAAA==.Krispy:BAABNQAECn8gAAQlAAgKBRcmCwBSAQAbAAcKdBg2KADeAQAlAAgKsxAmCwBSAQAYAAEKxAL6VAAgAAAAAA==.Krispyy:BAAANQAECgcICgAAAA==.Krix:BAAANQAECgUICQAAAA==.',
Ku='Kuroji:BAAANQADCgEIAQAAAA==.',
La='Laerin:BAAANQAECgcICQAAAA==.Landreielea:BAABNQAECn8bAAICAAkKdQwUmADYAQACAAkKdQwUmADYAQAAAA==.Laxus:BAAANQAECgYIDgAAAA==.',
Le='Lerenor:BAAANQAECgUIBwAAAA==.Levophed:BAAANQAECgUICAAAAA==.',
Li='Lightseeker:BAAANQAECgEIAQABNQAECgYIDgADAAAAAA==.Lily:BAABNQAECn8YAAIXAAcKRBCRIgCDAQAXAAcKRBCRIgCDAQAAAA==.Linnt:BAAANQAECgcICAAAAA==.Liyara:BAACNQAFFH8HAAIEAAIKIBtgGACkAAAEAAIKIBtgGACkAAA1AAQKfzMAAgQACgoJJC0ZAF8DAAQACgoJJC0ZAF8DAAAA.',
Ll='Llorsa:BAABNQAECn8rAAILAAcK6BB+XwCHAQALAAcK6BB+XwCHAQAAAA==.Lltoj:BAAANQADCgEIAQAAAA==.',
Lu='Lusavahza:BAAANQADCgUIBgAAAA==.Luxian:BAAANQAECgIIAwAAAA==.',
Ly='Lyann:BAAANQADCgEIAQAAAA==.Lyssirix:BAAANQAECgIIAgAAAA==.',
['Lä']='Ländrei:BAAANQAECgIIAgABNQAECgkJGwACAHUMAA==.',
Ma='Macy:BAAANQADCgEIAQAAAA==.Mahralla:BAAANQADCgUIBQAAAA==.Mahway:BAAANQADCgEIAQAAAA==.Maikagond:BAAANQADCgYIBgABNQAECgoKNwAEAI4MAA==.Makaria:BAAANQAECgUIDQAAAA==.Malbisa:BAAANQAECgUIDgAAAA==.Malphoz:BAAANQADCgUIBQAAAA==.Mandragora:BAAANQAECgYIBwAAAA==.Marli:BAAANQADCgIIAgAAAA==.',
Mc='Mcsorley:BAAANQADCgMIAwAAAA==.',
Mi='Mickey:BAABNQAECn8aAAIbAAkKvhuxGgBpAgAbAAkKvhuxGgBpAgAAAA==.Mikiik:BAABNQAECn8jAAMmAAcKkAXPFgCLAAATAAQKBgVpFAGhAAAmAAYK+wXPFgCLAAAAAA==.Mikk:BAAANQADCgIJAgAAAA==.Mildoo:BAABNQAECn8sAAIcAAkKBQ/gBwCcAQAcAAkKBQ/gBwCcAQAAAA==.Milkymoo:BAAANQAECgUICQABNQAFFAcIIgALALYWAA==.',
Mo='Monq:BAAANQAECggIDgAAAA==.Moón:BAABNQAECn8nAAIRAAgKyxOOEABuAQARAAgKyxOOEABuAQAAAA==.',
My='Mythlocked:BAAANQAECgMIBAAAAA==.',
['Mî']='Mîlk:BAAANQADCgIIAgAAAA==.',
Na='Naomii:BAAANQADCgIIAgAAAA==.Narus:BAAANQAECgYIDwABNQAECggIMgAaAOEYAA==.',
Ne='Nephadin:BAAANQADCggICAABNQAECgoKPAAUAH0hAA==.Nephdragon:BAAANQAECgUIBQABNQAECgoKPAAUAH0hAA==.Neviaa:BAABNQAECn8nAAMeAAkKlxZJRAAJAgAeAAkKlxZJRAAJAgAnAAYKtg36UwDHAAAAAA==.',
Ni='Nickypoo:BAAANQADCgYICgAAAA==.Nightmenace:BAAANQAECgQIBgAAAA==.Niq:BAAANQAECgIIAQAAAA==.',
No='Norasong:BAAANQAECgQIBAAAAA==.Norii:BAAANQADCgMIAwABNQAECgUIDwADAAAAAA==.Nothealster:BAABNQAECn8ZAAIKAAcKAgkiPQBCAQAKAAcKAgkiPQBCAQAAAA==.Novacane:BAAANQAECgEIAgAAAA==.',
Ob='Obitrice:BAABNQAECn8fAAICAAkKdxK6nADNAQACAAkKdxK6nADNAQABNQAECgcIGwAXAIsUAA==.Obsidiian:BAAANQAECggICwAAAA==.Obsidion:BAABNQAECn8UAAMLAAcKBwrMpgAhAQALAAYKowrMpgAhAQAKAAUKCgkEOwCTAAABNQAECggIMgAaAOEYAA==.',
Od='Odie:BAAANQAECgIIAgAAAA==.',
On='Onetrueshot:BAAANQAECggICAAAAA==.Onlyfangs:BAAANQADCgEIAQABNQAECgUIEAADAAAAAA==.',
Or='Organdonor:BAABNQAECn8gAAILAAoKQRAMYwD3AQALAAoKQRAMYwD3AQAAAA==.',
Os='Ossin:BAAANQAECgIIAwAAAA==.',
Pa='Pantherlilly:BAAANQAECgQICQAAAA==.',
Pe='Perry:BAAANQAECgUICAAAAA==.',
Ph='Phlampped:BAAANQADCgYIBgABNQAFFAYIDwAEAHscAA==.',
Po='Pozufuma:BAABNQAECn8rAAMIAAcKnBlIDAD4AQAIAAcKnBlIDAD4AQAaAAQKsQ+yJAChAAAAAA==.',
Ps='Psychomantis:BAABNQAECn89AAMKAAoKbhAWFADhAQAKAAoKbhAWFADhAQALAAoKngtnfwAgAQAAAA==.',
Ra='Radium:BAAANQADCgcICQAAAA==.Ravenbear:BAAANQAECgUIEAAAAA==.Ravenwolf:BAAANQADCgEIAQAAAA==.',
Re='Redpool:BAABNQAECn8mAAICAAkKGguOcQCUAQACAAkKGguOcQCUAQAAAA==.Rethandra:BAAANQAECgIIAQAAAA==.Retrix:BAAANQAECgQICAAAAA==.Revorra:BAAANQAECgUIEAABNQAECggIMgAaAOEYAA==.Rezelflezel:BAAANQAECgYIBQAAAA==.',
Ri='Risko:BAAANQADCgEIAQAAAA==.Ristvakbaen:BAABNQAECn8+AAQcAAoKayEuAgCgAgAcAAkKNBwuAgCgAgATAAgKixyFWgBHAgAmAAgK/h9BAwDXAQAAAA==.Riteye:BAAANQADCgEIAQAAAA==.',
Ro='Robynlee:BAABNQAECn8kAAILAAkKDRWpaADlAQALAAkKDRWpaADlAQAAAA==.Rogùe:BAAANQAECgEIAQAAAA==.Rohh:BAAANQADCgEIAQAAAA==.Rohini:BAAANQADCgQIBwAAAA==.Rosebelle:BAAANQADCgQIBAAAAA==.Rovik:BAAANQAECgQIBwAAAA==.Roweena:BAAANQADCgEIAQAAAA==.',
Sa='Santeclair:BAAANQAECgMIAwAAAA==.',
Sc='Sceryna:BAABNQAECn8sAAQEAAoK6xqHYgBzAgAEAAoK6xqHYgBzAgAUAAIKtReBXgBhAAASAAEKYQIp9AAeAAAAAA==.Schiftly:BAAANQADCgQIBQAAAA==.Schwiggity:BAAANQADCgIIAgABNQAECgYIBwADAAAAAA==.Scrmndemn:BAABNQAECn8YAAIEAAgKHwR/CQEPAQAEAAgKHwR/CQEPAQAAAA==.',
Se='Sef:BAAANQAECgUICwAAAA==.Sequan:BAAANQADCgUIBQAAAA==.Serpent:BAAANQAFFAMIBAABNQAFFAYIBwAUANcGAA==.',
Sh='Shamadeus:BAAANQAECgQICAABNQAECgoKPgAcAGshAA==.Shamenio:BAAANQAECgUIBAAAAA==.Shamtastical:BAABNQAECn8aAAIHAAcKERMMeAAYAQAHAAcKERMMeAAYAQABNQAECgkJJAALAA0VAA==.Sheeara:BAAANQADCgYIBgAAAA==.Shikita:BAABNQAECn8pAAIQAAkKfBqWEwBHAgAQAAkKfBqWEwBHAgAAAA==.Shimadin:BAACNQAFFH8TAAIEAAcKsBAIEQA9AQAEAAcKsBAIEQA9AQA1AAQKf0UAAgQACgpHJJURAAwDAAQACgpHJJURAAwDAAAA.Shimjun:BAAANQAECgYIBgABNQAFFAcIEwAEALAQAA==.Shimsong:BAAANQADCggIDQABNQAFFAcIEwAEALAQAA==.Shirma:BAAANQABCgIIAgAAAA==.Shmerek:BAABNQAECn81AAIaAAgKNRq2EQALAgAaAAgKNRq2EQALAgAAAA==.',
Si='Sierramist:BAABNQAECn8yAAIYAAgKNx0uCQCIAgAYAAgKNx0uCQCIAgAAAA==.Sijon:BAAANQAECgEIAQAAAA==.Silverpacem:BAAANQAECgQIBAAAAA==.Silverstream:BAABNQAECn9AAAIQAAoKgBwMCQAJAwAQAAoKgBwMCQAJAwAAAA==.',
Sm='Smidyy:BAAANQADCgEIAQAAAA==.Smith:BAAANQADCgIIAgAAAA==.',
So='Solbin:BAABNQAECn8gAAIkAAgKnCLCAwAgAwAkAAgKnCLCAwAgAwABNQAECgoKMgAWAJkgAA==.Solexine:BAAANQADCgQIBAAAAA==.Solitudé:BAAANQAECgQICgABNQAFFAIIBwAdAIEeAA==.Soteirian:BAABNQAECn83AAMEAAoKjgwxgwCGAQAEAAoKjgwxgwCGAQAUAAEKAADVdwAlAAAAAA==.',
Sp='Spiritlinkin:BAABNQAECn8wAAIGAAoKFBwSFgCXAgAGAAoKFBwSFgCXAgAAAA==.',
St='Stalariais:BAAANQADCgYIBwABNQAECggIDgADAAAAAA==.Steakhammer:BAAANQAECgYIBQABNQAECgoKLwAYAHkeAA==.Steve:BAABNQAECn8dAAIBAAgKIgvrkQAmAQABAAgKIgvrkQAmAQAAAA==.Straw:BAAANQABCgIIAgABNQAECgoKLAASACIUAA==.',
Su='Sugardawn:BAAANQAECgQIBAAAAA==.Sugarkitty:BAAANQADCgcIBwAAAA==.Supereclipse:BAABNQAECn8qAAICAAcKnhF0kgDkAQACAAcKnhF0kgDkAQAAAA==.',
Sy='Sydvicious:BAABNQAECn8rAAIJAAoKFyFsDQCoAgAJAAoKFyFsDQCoAgAAAA==.',
Ta='Taintedwater:BAAANQAECgYIBgAAAA==.Tairnanach:BAAANQADCgYIDgAAAA==.Taladiir:BAAANQAECggIDQAAAA==.Talana:BAAANQAECgcICwAAAA==.Tayger:BAAANQADCgcJEAAAAA==.',
Td='Tdog:BAAANQADCgcIDgAAAA==.',
Te='Tecks:BAABNQAECn81AAILAAgK6g3kXgCJAQALAAgK6g3kXgCJAQAAAA==.Teslá:BAAANQAECgEIAQAAAA==.Tevish:BAAANQADCgEIAQAAAA==.',
Th='Thaldur:BAAANQAECgIIAQABNQAECgoKIwAiALMfAA==.Thayo:BAAANQAECgEIAQAAAA==.Theatrix:BAAANQAECgMIBAABNQAECggIFQABAGwVAA==.Thefreeman:BAAANQAECgQIBAAAAA==.Themajor:BAAANQAECgQIBQAAAA==.Therossyas:BAABNQAECn8VAAICAAYKXBF6kQBLAQACAAYKXBF6kQBLAQAAAA==.Thezuggest:BAAANQADCgMJAwAAAA==.Thicctotems:BAACNQAFFH8RAAMHAAUKwCBKDQB5AQAHAAUKwCBKDQB5AQAGAAEKCQTbNAA/AAA1AAQKfzEAAwcACQqvIb0PABcDAAcACQqvIb0PABcDAAYAAgoRFA0DAYkAAAAA.Threat:BAABNQAECn9EAAIEAAoKtCXmBQBcAwAEAAoKtCXmBQBcAwAAAA==.Thunderthigh:BAAANQADCgYIAwAAAA==.Thungerthi:BAAANQADCgUICAAAAA==.',
Ti='Tiamaat:BAABNQAECn81AAMPAAgKKQYARgDZAAAPAAgKKQYARgDZAAAQAAEK6QFnegApAAAAAA==.Tinysanta:BAAANQAECgIIBAAAAA==.Titus:BAAANQADCgYICwAAAA==.',
To='Toatani:BAAANQAECgQIBAABNQAECgQICQADAAAAAA==.Tokkaebi:BAAANQAECgMIAwAAAA==.Torquamada:BAAANQADCgEIAQAAAA==.Torvar:BAAANQADCggIDwAAAA==.',
Ty='Tyletos:BAABNQAECn8yAAMWAAoKmSDJIQBUAwAWAAoKYCDJIQBUAwAZAAUKXR02EgCDAQAAAA==.',
Ug='Ugolok:BAAANQADCgcIDgAAAA==.',
Ur='Uriél:BAAANQADCgQIBAABNQAFFAIIBwAdAIEeAA==.Urubaen:BAAANQAECgcIDwABNQAECgoKPgAcAGshAA==.',
Va='Valanoth:BAAANQADCgIIAwAAAA==.Valeene:BAABNQAECn8sAAIPAAoKlCA6GgD3AgAPAAoKlCA6GgD3AgAAAA==.Varek:BAAANQAECgEIAQAAAA==.Varlann:BAAANQADCgEIAgAAAA==.',
Ve='Veiler:BAABNQAECn89AAQCAAoKjg1uZwCtAQACAAkKJg1uZwCtAQAfAAgKDgU5RAA3AQAoAAIKiAMWEQA1AAAAAA==.Veruca:BAAANQAECgYIBgAAAA==.Veviseron:BAABNQAECn8zAAIZAAkK/wb3EgAgAQAZAAkK/wb3EgAgAQAAAA==.',
Vi='Vinstalation:BAAANQAECgQIBwAAAA==.',
Vo='Vonbismarck:BAABNQAECn8vAAMCAAkK7Q84XgDFAQACAAkK7Q84XgDFAQAfAAYKmAk7RwAiAQAAAA==.',
Vr='Vritraz:BAACNQAFFH8HAAIdAAIKgR6RDwCtAAAdAAIKgR6RDwCtAAA1AAQKfzIAAh0ACgrLIIMKAEYDAB0ACgrLIIMKAEYDAAAA.',
Wa='Warsonge:BAAANQAECgUICQAAAA==.Washamage:BAAANQADCgEIAQAAAA==.Waxoff:BAAANQAECgIIAgAAAA==.',
We='Wendypini:BAABNQAECn89AAICAAoKIhfmSgCNAgACAAoKIhfmSgCNAgAAAA==.',
Wh='Whitlock:BAAANQAECgMIBAAAAA==.',
Xe='Xendria:BAAANQADCggICgAAAA==.',
Ya='Yannhal:BAAANQAECgIIAgAAAA==.',
Za='Zalia:BAAANQADCgEIAQAAAA==.Zangelf:BAAANQADCgEIAgAAAA==.Zarrana:BAAANQADCgEIAQAAAA==.',
Zo='Zodiaac:BAABNQAECn81AAInAAgK1hgHOAAoAgAnAAgK1hgHOAAoAgAAAA==.',
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
