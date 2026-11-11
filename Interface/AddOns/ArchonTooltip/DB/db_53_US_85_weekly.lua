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

local lookup = {'Monk-Windwalker','Warrior-Arms','Hunter-BeastMastery','Unknown-Unknown','Paladin-Retribution','Evoker-Devastation','Shaman-Elemental','Shaman-Restoration','Warrior-Fury','DemonHunter-Havoc','Priest-Shadow','Priest-Holy','Priest-Discipline','Rogue-Subtlety','Rogue-Assassination','Druid-Balance','Druid-Restoration','Druid-Feral','Paladin-Holy','Warlock-Demonology','Paladin-Protection','Rogue-Outlaw','Mage-Arcane','Druid-Guardian','Monk-Mistweaver','Mage-Frost','Warrior-Protection','Warlock-Destruction','DeathKnight-Frost','DeathKnight-Unholy','Hunter-Marksmanship','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Devourer','Shaman-Enhancement','DemonHunter-Vengeance','Monk-Brewmaster','Warlock-Affliction','DeathKnight-Blood','Hunter-Survival',}
local provider = {region='US',realm='Eitrigg',name='US',type='weekly',zone=53,date='2026-11-10',data={Al='Alys:BAABNQAECn8YAAIBAAcKqwZjNwDRAAABAAcKqwZjNwDRAAAAAA==.',
Am='Amaniatres:BAABNQAECn8VAAICAAgKbBVvlQDmAQACAAgKbBVvlQDmAQAAAA==.Ammartin:BAABNQAECn8eAAIDAAYKLwvmzQBlAQADAAYKLwvmzQBlAQAAAA==.Amperage:BAAANQADCgUIEAABNQAECggIFQACAGwVAA==.',
An='Anaan:BAAANQAECgUIDgAAAA==.Anahera:BAAANQADCgcIBwABNQAECgQICwAEAAAAAA==.Anthion:BAAANQABCgIIAgAAAA==.Anzhelina:BAABNQAECn8nAAIFAAoKvR9BKAC0AgAFAAoKvR9BKAC0AgAAAA==.',
Ap='Apis:BAAANQAECgIIAgAAAA==.Aprys:BAAANQABCggIFQAAAA==.',
Ar='Arathan:BAAANQADCggIFAAAAA==.Arihana:BAABNQAECn8VAAIGAAYK6AbaJgD+AAAGAAYK6AbaJgD+AAAAAA==.',
As='Asapshocky:BAACNQAFFH8LAAIHAAYKyBKjEgBFAQAHAAYKyBKjEgBFAQA1AAQKf0EAAgcACgqbIykIADIDAAcACgqbIykIADIDAAAA.Asmoday:BAAANQADCggILAAAAA==.',
Ba='Baahp:BAAANQAECgcIEQABNQAECgoKPAAIAGUZAA==.Barley:BAAANQABCgIIAgAAAA==.',
Be='Bearlytanks:BAAANQAECgIIAwAAAA==.Belassandra:BAAANQAECgQIBAAAAA==.Belgerra:BAABNQAECn8aAAMJAAcKNBc3EACjAQAJAAYKwRQ3EACjAQACAAcKFxE3pQAdAQAAAA==.Bellabelle:BAAANQAECgQIBQAAAA==.Bevian:BAAANQAECgIIAgABNQAECgUIDwAEAAAAAA==.',
Bi='Biggiepants:BAABNQAECn83AAIKAAoK4xeYHwD6AQAKAAoK4xeYHwD6AQAAAA==.Biggnome:BAAANQADCgYIBgABNQAECgEIAQAEAAAAAA==.Bighead:BAAANQAECgMIAwABNQAECgEIAQAEAAAAAA==.Bigr:BAAANQAECgEIAQAAAA==.Bigwarlocks:BAAANQADCggICAABNQAECgEIAQAEAAAAAA==.Biollante:BAAANQADCgYICAAAAA==.',
Bo='Bootyßandaid:BAAANQAECgUIDAAAAA==.',
Bu='Buckis:BAABNQAECn8fAAIFAAYKgQmNAwEZAQAFAAYKgQmNAwEZAQAAAA==.',
Ca='Camderags:BAAANQAECgEIAQAAAA==.Canon:BAAANQAECggICQAAAA==.Catasucked:BAAANQADCgMIAwAAAA==.',
Ce='Celios:BAAANQAECgIIAwAAAA==.',
Ch='Chillin:BAAANQADCgEIAQAAAA==.Choggy:BAABNQAECn8/AAQLAAoKoBKCIQAqAgALAAkKsBCCIQAqAgAMAAcK7hRRfgBGAQANAAEKQQ2QKQAxAAAAAA==.Churro:BAAANQADCgcIBwAAAA==.',
Ci='Cindrõz:BAAANQAECgQIBQAAAA==.',
Co='Conception:BAAANQAECgUIBQABNQAECgkJLQAMAFYZAA==.Cough:BAAANQAECgEIAQAAAA==.',
Cr='Crinklecut:BAABNQAECn8VAAMOAAcK/QeuNgAEAQAOAAYKqweuNgAEAQAPAAMKPggSTwBdAAAAAA==.Crow:BAABNQAECn8zAAMQAAoKBSOHCgB4AwAQAAoKBSOHCgB4AwARAAkKfB5rHQBGAgAAAA==.',
Da='Daijin:BAABNQAECn8gAAISAAkK4BcQCgAhAgASAAkK4BcQCgAhAgAAAA==.Danielallen:BAAANQAECgQIDwAAAA==.Danyrogue:BAAANQAECgcIBwABNQAFFAgIEAADAAsaAA==.',
De='Deadlybeard:BAAANQADCgQICQABNQAECggINQATAHEkAA==.Deadlywrath:BAABNQAECn81AAITAAgKcSTjHQC8AgATAAgKcSTjHQC8AgAAAA==.Deadmenace:BAAANQADCgYJCwAAAA==.Decåying:BAABNQAECn85AAIUAAgKmwqZjQAsAQAUAAgKmwqZjQAsAQAAAA==.Demonsangel:BAAANQAECgQIBgAAAA==.Deni:BAAANQAECgUIDAAAAA==.Denli:BAAANQAECgEIAgAAAA==.',
Di='Diagnosis:BAABNQAECn8fAAIFAAoKNyI6IABDAwAFAAoKNyI6IABDAwAAAA==.Divine:BAAANQAECgIIBAAAAA==.',
Do='Doctaz:BAAANQAECgMIBQAAAA==.Doctrine:BAAANQAECgUIBQAAAA==.Donnabb:BAAANQAECgYIEwAAAA==.Donteatbees:BAAANQAECgcIDAAAAA==.Dop:BAAANQAECgUICQAAAA==.Doran:BAAANQADCgUIBQAAAA==.Dottierotten:BAAANQAECgUICAAAAA==.',
Dr='Drenrah:BAABNQAECn8vAAMTAAkKQBCqTADOAQATAAkKQBCqTADOAQAFAAQKMgOsZQFRAAAAAA==.',
Ed='Edend:BAAANQADCgUICgAAAA==.',
Ei='Eiduartpaw:BAABNQAECn8aAAQTAAoKswrvjQD8AAATAAoKswrvjQD8AAAVAAUKigvMRACAAAAFAAIK6gW4YQFWAAABNQAFFAQICAADAGoXAA==.',
El='Elbryan:BAAANQAECgYICwAAAA==.Electracutie:BAABNQAECn8bAAIIAAgKiAp9eAAzAQAIAAgKiAp9eAAzAQAAAA==.Elementdemon:BAABNQAECn8vAAIWAAkKHhRTAwClAQAWAAkKHhRTAwClAQAAAA==.',
En='Enthalpy:BAABNQAECn9EAAIXAAoKDRyJKgCKAgAXAAoKDRyJKgCKAgAAAA==.',
Es='Esperzoa:BAAANQAECgUIDQAAAA==.',
Eu='Eucalicdes:BAABNQAECn9DAAIYAAoKvRd1DwBrAgAYAAoKvRd1DwBrAgAAAA==.',
Ev='Evøkër:BAAANQADCgQIBAABNQAECgoKMAAZAHkeAA==.',
Ez='Ezra:BAAANQAECgYICAAAAA==.',
Fa='Falshin:BAAANQADCggICAAAAA==.Fancy:BAAANQAECgIIBAAAAA==.Fangyi:BAABNQAECn8zAAMaAAgKVxKuDwCtAQAaAAgKVxKuDwCtAQAXAAcKjwo6FQFpAQAAAA==.Faytes:BAAANQAECgMIBQAAAA==.',
Fi='Fiction:BAAANQAECggIEAAAAA==.',
Fl='Flabutt:BAAANQAECgYICAAAAA==.Florita:BAAANQAECgQICQAAAA==.',
Fo='Fordinn:BAABNQAECn87AAQbAAkKcBiODwClAQAbAAgKFReODwClAQACAAgK6hJWwwB0AQAJAAQKMhwJGgACAQAAAA==.',
Fr='Freemi:BAAANQAECgQIBgAAAA==.Freeree:BAAANQADCgMIAwAAAA==.Fren:BAABNQAECn8aAAIYAAkKehy4DgA5AgAYAAkKehy4DgA5AgAAAA==.Frenzy:BAAANQAECgcIAwAAAA==.Fruitcakes:BAAANQAECgIIAgAAAA==.',
Fu='Furrypaw:BAAANQAECgUIBwABNQAECgoKMAAZAHkeAA==.Furrypunch:BAABNQAECn8wAAMZAAoKeR6IBwDoAgAZAAoKeR6IBwDoAgABAAIKUQX8UQBKAAAAAA==.',
Ga='Garataz:BAAANQADCgUIBQABNQAECgUIDQAEAAAAAA==.Garzhvog:BAAANQAECggIDAABNQAECgoKSAAcAE8jAA==.Gasket:BAACNQAFFH8JAAIdAAIK5x+sEAC6AAAdAAIK5x+sEAC6AAA1AAQKfzkAAx4ACgr6HAg5AEECAB4ACArAHAg5AEECAB0ACAq4Gnk6AJ4BAAAA.',
Gh='Ghostdragona:BAAANQADCgcIBwAAAA==.Ghostown:BAAANQADCgQIBAAAAA==.',
Gr='Graceful:BAABNQAECn8yAAIBAAkKcw95IgBwAQABAAkKcw95IgBwAQAAAA==.Grenie:BAAANQADCgcICAAAAA==.Grit:BAAANQAECgYIDgAAAA==.Grëzel:BAAANQADCgYIBgABNQAECgcIDgAEAAAAAA==.',
Ha='Handicap:BAAANQAECgEIAgABNQAECgoKHwAFADciAA==.Hark:BAACNQAFFH8JAAIDAAIKTA67IQCPAAADAAIKTA67IQCPAAA1AAQKfzYAAwMACgqpHNQ/AKsCAAMACgqpHNQ/AKsCAB8AAQpjCPiLADMAAAAA.Harpin:BAABNQAECn8/AAIMAAoKGh5pGgDzAgAMAAoKGh5pGgDzAgAAAA==.Harvin:BAABNQAECn8yAAIgAAgKwx+NCQCRAgAgAAgKwx+NCQCRAgAAAA==.',
He='Heals:BAAANQAECggICAAAAA==.Heisenburgg:BAAANQAECgIIAgABNQAECgYIBwAEAAAAAA==.Helanua:BAABNQAECn8rAAIHAAkK3g22YwBDAQAHAAkK3g22YwBDAQAAAA==.',
Hi='Highlight:BAAANQAECgcIEAAAAA==.Hippopotamus:BAAANQADCgIIAgAAAA==.Hit:BAAANQAECgYIBwAAAA==.Hitt:BAAANQADCgEIAQABNQAECgYIBwAEAAAAAA==.',
Ho='Holybuttkick:BAAANQADCggICQAAAA==.Holyish:BAAANQAECgIIAgAAAA==.Holyrollers:BAABNQAECn8dAAIMAAoKugpgZwCQAQAMAAoKugpgZwCQAQAAAA==.Holytide:BAABNQAECn8iAAMIAAcKsREfgwAUAQAIAAYK5w4fgwAUAQAHAAcKGAWgkgDOAAAAAA==.Hops:BAAANQADCgQIBAAAAA==.Hornsie:BAAANQADCgIIAgAAAA==.Horrorfang:BAABNQAECn84AAIeAAoKHx00DwB+AgAeAAoKHx00DwB+AgAAAA==.',
['Hä']='Häwke:BAAANQAECgEIAQAAAA==.',
Ib='Ibaar:BAACNQAFFH8bAAMGAAgKPyJeAADFAgAGAAcK3iNeAADFAgAhAAEKIho4DABSAAA1AAQKfy0AAwYACgo/JFoGACUDAAYACgo/JFoGACUDACEAAQpBIIoXAF8AAAAA.',
Ic='Icialiaa:BAAANQADCgIIAgABNQAECgYIEAAEAAAAAA==.',
In='Inno:BAABNQAECn8yAAIiAAoKCCXfBAAPAwAiAAoKCCXfBAAPAwAAAA==.',
It='Ithacus:BAABNQAECn81AAIjAAoK7BZgDgAbAgAjAAoK7BZgDgAbAgAAAA==.Itspriesty:BAAANQAECgEIAQAAAA==.',
Ja='Janari:BAAANQADCggIFAAAAA==.Jandaar:BAAANQADCgYICQAAAA==.Jatt:BAAANQAECgYICgAAAA==.Jattix:BAAANQADCgQIBAAAAA==.',
Jd='Jdawgprime:BAAANQABCgQIBAAAAA==.',
Ji='Jilkaeden:BAAANQAECgcIEgAAAA==.',
Jo='Jorek:BAABNQAECn87AAICAAgKYg4WigBaAQACAAgKYg4WigBaAQAAAA==.Josh:BAAANQAECgMICQAAAA==.',
Jr='Jrue:BAAANQAECgMIBQAAAA==.',
Ju='Jurtkal:BAAANQAECgIIAgAAAA==.',
Ka='Kaiva:BAAANQAECgQICwAAAA==.Kavik:BAAANQAECgIIAgAAAA==.',
Ke='Keflá:BAAANQAECgQICAAAAA==.Keineliebe:BAAANQAECgIIAgAAAA==.Kelencye:BAAANQAECgMICQAAAA==.',
Kh='Khaas:BAABNQAECn8sAAIeAAcKoApAQAD+AAAeAAcKoApAQAD+AAAAAA==.Khanloa:BAAANQADCgUIBQAAAA==.Kheleze:BAAANQAECgUICQABNQAECgcIFAAVAMkbAA==.',
Ki='Killerbell:BAAANQAECgYICwAAAA==.Killshot:BAAANQAECgEIAgAAAA==.',
Ko='Korihor:BAABNQAECn8cAAIVAAcK6xEiKwAGAQAVAAcK6xEiKwAGAQAAAA==.',
Kr='Krestus:BAABNQAECn8sAAQKAAoKrSAKEACeAgAKAAkKaxsKEACeAgAiAAkKOB6vFgDxAQAkAAcKKR/JDgDMAQAAAA==.Krispy:BAABNQAECn8iAAQlAAgKVRdtDABUAQABAAcKdBg2KADeAQAlAAgKnRFtDABUAQAZAAEKxAL6VAAgAAAAAA==.Krispyy:BAAANQAECgcICgAAAA==.Krix:BAAANQAECgUICgAAAA==.',
Ku='Kuroji:BAAANQABCgEIAQAAAA==.',
La='Laerin:BAAANQAECgcICQAAAA==.Landreielea:BAABNQAECn8eAAIDAAoKCgwUmADYAQADAAoKCgwUmADYAQAAAA==.Laxus:BAAANQAECgYIEgAAAA==.',
Le='Lerenor:BAAANQAECgcIDgAAAA==.Levophed:BAAANQAECgUICgAAAA==.',
Li='Lightseeker:BAAANQAECgEIAQABNQAECgYIEgAEAAAAAA==.Lily:BAABNQAECn8YAAIYAAcKRBCRIgCDAQAYAAcKRBCRIgCDAQAAAA==.Linadra:BAAANQADCgEIAQAAAA==.Linnt:BAAANQAECgcICQAAAA==.Liyara:BAACNQAFFH8JAAIFAAIKMx2GGwCnAAAFAAIKMx2GGwCnAAA1AAQKfzcAAgUACgoJJC0ZAF8DAAUACgoJJC0ZAF8DAAAA.',
Ll='Llorsa:BAABNQAECn8xAAIMAAcKFBGfbQB8AQAMAAcKFBGfbQB8AQAAAA==.Lltoj:BAAANQADCgEIAQAAAA==.',
Lu='Lusavahza:BAAANQADCgUIBgAAAA==.Luxian:BAAANQAECgIIAwAAAA==.',
Ly='Lyann:BAAANQAECgEIAQAAAA==.Lyssirix:BAAANQAECgIIAwAAAA==.',
['Lä']='Ländrei:BAAANQAECgIIAwABNQAECgoKHgADAAoMAA==.',
Ma='Macy:BAAANQABCgIIAgAAAA==.Mahralla:BAAANQADCgUIBQAAAA==.Maikagond:BAAANQADCgYIBgABNQAECgoKPwAFAAYNAA==.Makaria:BAAANQAECgUIEAAAAA==.Malbisa:BAAANQAECgUIDwAAAA==.Malphoz:BAAANQADCgUIBQAAAA==.Mandragora:BAAANQAECgUIDQAAAA==.Marli:BAAANQADCgIIAgAAAA==.',
Mc='Mcsorley:BAAANQADCgMIAwAAAA==.',
Mi='Mickey:BAABNQAECn8aAAIBAAkKvhuxGgBpAgABAAkKvhuxGgBpAgAAAA==.Mikiik:BAABNQAECn8jAAMcAAcKkAX9GQCHAAAUAAQKBgVpFAGhAAAcAAYK+wX9GQCHAAAAAA==.Mikk:BAAANQADCgIJAgAAAA==.Mildoo:BAABNQAECn8sAAImAAkKBQ/3CQCXAQAmAAkKBQ/3CQCXAQAAAA==.Milkymoo:BAAANQAECgUICQABNQAFFAcIIgAMALYWAA==.',
Mo='Monq:BAAANQAECggIEAAAAA==.Moón:BAABNQAECn8oAAMSAAgKyxNjFABmAQASAAgKyxNjFABmAQARAAEKbQbpfQAcAAAAAA==.',
My='Mythlocked:BAAANQAECgMIBwAAAA==.',
['Mî']='Mîlk:BAAANQADCgIIAgAAAA==.',
Na='Naomii:BAAANQADCgIIAgAAAA==.Narus:BAABNQAECn8VAAIkAAcK2QkoGADEAAAkAAcK2QkoGADEAAABNQAECgkJOwAbAHAYAA==.',
Ne='Nephadin:BAAANQADCggICAABNQAECgoKPwAVAI4hAA==.Nephdragon:BAAANQAECgUICAABNQAECgoKPwAVAI4hAA==.Neviaa:BAABNQAECn8nAAMeAAkKlxZJRAAJAgAeAAkKlxZJRAAJAgAnAAYKtg2OWwDGAAAAAA==.',
Ni='Nickypoo:BAAANQADCgYICQAAAA==.Nightmenace:BAAANQAECgQIBgAAAA==.Niq:BAAANQAECgIIAgAAAA==.',
No='Norasong:BAAANQAECgUICQAAAA==.Norii:BAAANQADCgMIAwABNQAECgUIDwAEAAAAAA==.Nothealster:BAABNQAECn8ZAAILAAcKAgkiPQBCAQALAAcKAgkiPQBCAQAAAA==.Novacane:BAAANQAECgEIAgAAAA==.',
Ob='Obitrice:BAABNQAECn8jAAIDAAkKdxK6nADNAQADAAkKdxK6nADNAQABNQAECgkJHwAYAE8TAA==.Obsidiian:BAAANQAECgYIDQAAAA==.Obsidion:BAABNQAECn8ZAAMMAAgKhQvMpgAhAQAMAAgKhQvMpgAhAQALAAUKCgnZQACXAAABNQAECgkJOwAbAHAYAA==.',
Od='Odie:BAAANQAECgIIAgAAAA==.',
On='Onetrueshot:BAAANQAECggICAAAAA==.',
Or='Organdonor:BAABNQAECn8gAAIMAAoKQRAMYwD3AQAMAAoKQRAMYwD3AQAAAA==.',
Os='Ossin:BAAANQAECgIIBgAAAA==.',
Pa='Pantherlilly:BAAANQAECgQICgAAAA==.',
Pe='Perry:BAAANQAECgcICwAAAA==.',
Ph='Phlampped:BAAANQADCgYIBgABNQAFFAYIBwACABEKAA==.',
Po='Pozufuma:BAABNQAECn8xAAMJAAcK2RlIDAD4AQAJAAcK2RlIDAD4AQAbAAQKsQ/8KQCaAAAAAA==.',
Ps='Psychomantis:BAABNQAECn89AAMLAAoKbhDMFgDgAQALAAoKbhDMFgDgAQAMAAoKngvEkgBeAQAAAA==.',
Ra='Radium:BAAANQADCgcICAAAAA==.Ravenbear:BAAANQAECgUIEAAAAA==.',
Re='Redpool:BAABNQAECn8mAAIDAAkKGgtXgQCcAQADAAkKGgtXgQCcAQAAAA==.Rethandra:BAAANQAECgIIAQAAAA==.Retrix:BAAANQAECgQICAAAAA==.Revorra:BAABNQAECn8UAAMjAAYK0QdgKgDCAAAjAAQKkQVgKgDCAAAIAAYKvgZI7wCMAAABNQAECgkJOwAbAHAYAA==.Rezelflezel:BAAANQAECgYIBwAAAA==.',
Ri='Ristvakbaen:BAABNQAECn9IAAQcAAoKTyNuAQCkAgAmAAkKBR2BAgCqAgAcAAoKfyJuAQCkAgAUAAgKixyFWgBHAgAAAA==.',
Ro='Robynlee:BAABNQAECn8tAAIMAAkKVhllSwD1AQAMAAkKVhllSwD1AQAAAA==.Rogùe:BAAANQAECgIIAgAAAA==.Rohini:BAAANQADCgQIBgAAAA==.Rosebelle:BAAANQADCgQIBAAAAA==.Rovik:BAAANQAECgQICgAAAA==.',
Sa='Samâell:BAAANQAECgMIAwAAAA==.Santeclair:BAAANQAECgMIBQAAAA==.',
Sc='Sceryna:BAABNQAECn8vAAQFAAoK/BuHYgBzAgAFAAoK/BuHYgBzAgAVAAIKtReBXgBhAAATAAEKYQJFAwEeAAAAAA==.Schiftly:BAAANQADCgQIBAAAAA==.Schwiggity:BAAANQADCgIIAgABNQAECgUIDQAEAAAAAA==.Scrmndemn:BAABNQAECn8fAAIFAAkKwAR/CQEPAQAFAAkKwAR/CQEPAQAAAA==.',
Se='Sef:BAAANQAECgUIDgAAAA==.Sequan:BAAANQADCgUIBQAAAA==.Serpent:BAAANQAFFAMIBAABNQAFFAYIBwAVANcGAA==.',
Sh='Shamadeus:BAAANQAECgQICAABNQAECgoKSAAcAE8jAA==.Shamenio:BAAANQAECgQIBwAAAA==.Shamtastical:BAABNQAECn8aAAIIAAcKERMlhgAMAQAIAAcKERMlhgAMAQABNQAECgkJLQAMAFYZAA==.Sheeara:BAAANQADCgYIBgAAAA==.Shikita:BAABNQAECn8wAAIRAAkK2Rr6EwBzAgARAAkK2Rr6EwBzAgAAAA==.Shimadin:BAACNQAFFH8TAAIFAAcKsBAIEQA9AQAFAAcKsBAIEQA9AQA1AAQKf1IAAgUACgqPJEUQACQDAAUACgqPJEUQACQDAAAA.Shimjun:BAAANQAECgYIBwABNQAFFAcIEwAFALAQAA==.Shimsong:BAAANQAECgEIAwABNQAFFAcIEwAFALAQAA==.Shirma:BAAANQAECgEIAQAAAA==.Shmerek:BAABNQAECn87AAIbAAgKXBoaEQCOAQAbAAgKXBoaEQCOAQAAAA==.',
Si='Sierramist:BAABNQAECn80AAIZAAkK6hsICQC4AgAZAAkK6hsICQC4AgAAAA==.Sijon:BAAANQAECgEIAQAAAA==.Silverpacem:BAAANQAECgQIBgAAAA==.Silverstream:BAABNQAECn9AAAIRAAoKgBwRCwAFAwARAAoKgBwRCwAFAwAAAA==.',
Sm='Smith:BAAANQADCgIIAgAAAA==.',
So='Solbin:BAABNQAECn8iAAIkAAgK+CLCAwAgAwAkAAgK+CLCAwAgAwABNQAECgoKMgAXAJkgAA==.Solexine:BAAANQADCgQIBAAAAA==.Solitudé:BAAANQAECgQICwABNQAFFAIICQAdAMQhAA==.Soteirian:BAABNQAECn8/AAMFAAoKBg3migChAQAFAAoKBg3migChAQAVAAEKAADVdwAlAAAAAA==.',
Sp='Spiritlinkin:BAABNQAECn82AAIHAAoKFBwRGgCOAgAHAAoKFBwRGgCOAgAAAA==.',
St='Stalariais:BAAANQADCgYIBgABNQAECggIDwAEAAAAAA==.Steakhammer:BAAANQAECgUIBQABNQAECgoKMAAZAHkeAA==.Steve:BAABNQAECn8dAAICAAgKIguDoQAlAQACAAgKIguDoQAlAQAAAA==.Straw:BAAANQABCgIIAgABNQAECgoKNgATACIUAA==.',
Su='Sugardawn:BAAANQAECgQIBQAAAA==.Sugarkitty:BAAANQADCgcIBwAAAA==.Supereclipse:BAABNQAECn8wAAIDAAcKGhN0kgDkAQADAAcKGhN0kgDkAQAAAA==.',
Sy='Sydvicious:BAABNQAECn8rAAIKAAoKFyHUDwCgAgAKAAoKFyHUDwCgAgAAAA==.',
Ta='Taintedwater:BAAANQAECgYIEAAAAA==.Tairnanach:BAAANQADCgYIDgAAAA==.Taladiir:BAAANQAECggIEQAAAA==.Talana:BAAANQAECgYIEQAAAA==.Tayger:BAAANQADCgcJEAAAAA==.',
Td='Tdog:BAAANQADCgcIDgAAAA==.',
Te='Tecks:BAABNQAECn87AAIMAAgK6g06bACAAQAMAAgK6g06bACAAQAAAA==.Teslá:BAAANQAECgEIAQAAAA==.',
Th='Thaldur:BAAANQAECgIIAgABNQAECgoKLAAKAK0gAA==.Thayo:BAAANQAECgEIAwAAAA==.Theatrix:BAAANQAECgMIBQABNQAECggIFQACAGwVAA==.Thefreeman:BAAANQAECgQIBgAAAA==.Themajor:BAAANQAECgQIBQAAAA==.Therossyas:BAABNQAECn8VAAIDAAYKXBH5pgBJAQADAAYKXBH5pgBJAQAAAA==.Thezuggest:BAAANQADCgMJAwAAAA==.Thicctotems:BAACNQAFFH8RAAMIAAUKwCBKDQB5AQAIAAUKwCBKDQB5AQAHAAEKCQTbNAA/AAA1AAQKfzEAAwgACQqvIbYTAAgDAAgACQqvIbYTAAgDAAcAAgoRFA0DAYkAAAAA.Threat:BAABNQAECn9NAAIFAAoKMSbWAwB2AwAFAAoKMSbWAwB2AwAAAA==.Thunderthigh:BAAANQADCgYIAwAAAA==.Thungerthi:BAAANQADCgUICAAAAA==.',
Ti='Tiamaat:BAABNQAECn87AAMQAAgKKQZsSwDfAAAQAAgKKQZsSwDfAAARAAEK6QFnegApAAAAAA==.Tinysanta:BAAANQAECgIIBQAAAA==.Titus:BAAANQADCgYICQAAAA==.',
To='Toatani:BAAANQAECgQIBQABNQAECgQICwAEAAAAAA==.Tokkaebi:BAAANQAECgcICQAAAA==.Torvar:BAAANQADCggIDwAAAA==.',
Ty='Tyletos:BAABNQAECn8yAAMXAAoKmSDJIQBUAwAXAAoKYCDJIQBUAwAaAAUKXR02EgCDAQAAAA==.',
Ug='Ugolok:BAAANQADCgcIDQAAAA==.',
Ur='Uriél:BAAANQADCgQIBAABNQAFFAIICQAdAMQhAA==.Urubaen:BAAANQAECgcIEQABNQAECgoKSAAcAE8jAA==.',
Va='Valanoth:BAAANQADCgIIAgAAAA==.Valeene:BAABNQAECn8sAAIQAAoKlCA6GgD3AgAQAAoKlCA6GgD3AgAAAA==.Varek:BAAANQAECgYICAAAAA==.Varlann:BAAANQAECgEIAwAAAA==.',
Ve='Veiler:BAABNQAECn89AAQDAAoKjg2IdgC1AQADAAkKJg2IdgC1AQAfAAgKDgU5RAA3AQAoAAIKiAP3EgA1AAAAAA==.Veruca:BAAANQAECgYIBgAAAA==.Veviseron:BAABNQAECn88AAIaAAoKlAbZFAAtAQAaAAoKlAbZFAAtAQAAAA==.',
Vi='Vinstalation:BAAANQAECgQICgAAAA==.',
Vo='Vonbismarck:BAABNQAECn8vAAMDAAkK7Q9NbgDJAQADAAkK7Q9NbgDJAQAfAAYKmAk7RwAiAQAAAA==.',
Vr='Vritraz:BAACNQAFFH8JAAIdAAIKxCGLDwDGAAAdAAIKxCGLDwDGAAA1AAQKfzYAAh0ACgplI4MKAEYDAB0ACgplI4MKAEYDAAAA.',
Wa='Warsonge:BAAANQAECgUICgAAAA==.Waxoff:BAAANQAECgMIAwAAAA==.',
We='Wendypini:BAABNQAECn9BAAIDAAoKIhfmSgCNAgADAAoKIhfmSgCNAgAAAA==.',
Wh='Whitlock:BAAANQAECgQICQAAAA==.',
Xe='Xendria:BAAANQADCggICgAAAA==.',
Ya='Yannhal:BAAANQAECgIIAwAAAA==.',
Za='Zangelf:BAAANQABCggIFAAAAA==.Zangolf:BAAANQAECgEIAgAAAA==.',
Zo='Zodiaac:BAABNQAECn87AAMnAAgK1hgHOAAoAgAnAAgK1hgHOAAoAgAeAAEKAACZoAAAAAAAAA==.',
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
