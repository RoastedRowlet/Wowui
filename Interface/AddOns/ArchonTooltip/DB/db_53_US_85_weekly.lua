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

local lookup = {'Monk-Windwalker','Warrior-Arms','Hunter-BeastMastery','Unknown-Unknown','Paladin-Retribution','Evoker-Devastation','Shaman-Elemental','Shaman-Restoration','Warrior-Fury','Priest-Holy','DemonHunter-Havoc','Priest-Shadow','Priest-Discipline','Rogue-Subtlety','Rogue-Assassination','Druid-Balance','Druid-Restoration','Druid-Feral','Paladin-Holy','Warlock-Demonology','Paladin-Protection','Rogue-Outlaw','Mage-Arcane','Druid-Guardian','Monk-Mistweaver','Mage-Frost','Warrior-Protection','Warlock-Destruction','DeathKnight-Frost','DeathKnight-Unholy','Hunter-Marksmanship','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Devourer','Shaman-Enhancement','DemonHunter-Vengeance','Monk-Brewmaster','Warlock-Affliction','DeathKnight-Blood','Hunter-Survival',}
local provider = {region='US',realm='Eitrigg',name='US',type='weekly',zone=53,date='2026-11-17',data={Al='Alys:BAABNQAECn8YAAIBAAcKqwbSOgDRAAABAAcKqwbSOgDRAAAAAA==.',
Am='Amaniatres:BAABNQAECn8VAAICAAgKbBVvlQDmAQACAAgKbBVvlQDmAQAAAA==.Ammartin:BAABNQAECn8kAAIDAAoKgwvsbADoAQADAAoKgwvsbADoAQAAAA==.Amperage:BAAANQADCgUIEAABNQAECggIFQACAGwVAA==.',
An='Anaan:BAAANQAECggIDAAAAA==.Anahera:BAAANQADCgcIBwABNQAECgQICwAEAAAAAA==.Anthion:BAAANQABCgIIAgAAAA==.Anzhelina:BAABNQAECn8nAAIFAAoKvR8oLgCpAgAFAAoKvR8oLgCpAgAAAA==.',
Ap='Apis:BAAANQAECgIIAgAAAA==.Aprys:BAAANQABCggIFQAAAA==.',
Ar='Arathan:BAAANQADCggIFAAAAA==.Arihana:BAABNQAECn8VAAIGAAYK6AbaJgD+AAAGAAYK6AbaJgD+AAAAAA==.',
As='Asapshocky:BAACNQAFFH8LAAIHAAYKyBKjEgBFAQAHAAYKyBKjEgBFAQA1AAQKf0MAAgcACgqbI/wIADADAAcACgqbI/wIADADAAAA.Asmoday:BAAANQADCggILAAAAA==.',
Ba='Baahp:BAAANQAECgcIEAABNQAECgoKQAAIAJgZAA==.Barley:BAAANQABCgIIAgAAAA==.',
Be='Bearlytanks:BAAANQAECgIIAwAAAA==.Belassandra:BAAANQAECgQIBAAAAA==.Belgerra:BAABNQAECn8aAAMJAAcKNBc3EACjAQAJAAYKwRQ3EACjAQACAAcKFxFWrwAbAQAAAA==.Bellabelle:BAAANQAECgQIBgAAAA==.Bevian:BAAANQAECgIIAgABNQAECgcIFQAKALQMAA==.',
Bi='Biggiepants:BAABNQAECn84AAILAAoKWRnDHgAVAgALAAoKWRnDHgAVAgAAAA==.Biggnome:BAAANQADCgYIBgABNQADCgUICQAEAAAAAA==.Bighead:BAAANQAECgMIAwABNQADCgUICQAEAAAAAA==.Bigr:BAAANQADCgcICAAAAA==.Bigwarlocks:BAAANQADCggICAABNQADCgUICQAEAAAAAA==.Biollante:BAAANQADCgYICAAAAA==.',
Bo='Bootyßandaid:BAAANQAECgUICgAAAA==.',
Bu='Buckis:BAABNQAECn8gAAIFAAYKgQmNAwEZAQAFAAYKgQmNAwEZAQAAAA==.',
Ca='Camderags:BAAANQADCggICAAAAA==.Canon:BAAANQAECggIDQAAAA==.Catasucked:BAAANQADCgMIAwAAAA==.',
Ce='Celios:BAAANQAECgIIAgAAAA==.',
Ch='Chillin:BAAANQADCgEIAQAAAA==.Choggy:BAABNQAECn9AAAQMAAoKWBWCIQAqAgAMAAkKzBOCIQAqAgAKAAcK7hRhiABAAQANAAEKQQ2QKQAxAAAAAA==.Churro:BAAANQADCgcIBwAAAA==.',
Ci='Cindrõz:BAAANQAECgQIBAAAAA==.',
Co='Conception:BAAANQAECgUICQABNQAECgoKMQAKADYYAA==.Cough:BAAANQADCgUICQAAAA==.',
Cr='Crinklecut:BAABNQAECn8VAAMOAAcK/QeuNgAEAQAOAAYKqweuNgAEAQAPAAMKPgjqUABdAAAAAA==.Crow:BAABNQAECn8zAAMQAAoKBSOHCgB4AwAQAAoKBSOHCgB4AwARAAkKfB5rHQBGAgAAAA==.',
Da='Daijin:BAABNQAECn8gAAISAAkK4BeyCwAbAgASAAkK4BeyCwAbAgAAAA==.Danielallen:BAAANQAECgQICQAAAA==.Danyrogue:BAAANQAECgcIBwABNQAFFAgIEAADAAsaAA==.',
De='Deadlybeard:BAAANQADCgQICQABNQAECgkJNgATAHUkAA==.Deadlywrath:BAABNQAECn82AAITAAkKdSR6EwAeAwATAAkKdSR6EwAeAwAAAA==.Deadmenace:BAAANQADCgYJCwAAAA==.Decåying:BAABNQAECn9BAAIUAAkKFQqgggBbAQAUAAkKFQqgggBbAQAAAA==.Demonsangel:BAAANQAECgUIBQAAAA==.Deni:BAAANQAECgUICQAAAA==.Denli:BAAANQADCgQIAgAAAA==.',
Di='Diagnosis:BAABNQAECn8fAAIFAAoKNyI6IABDAwAFAAoKNyI6IABDAwAAAA==.Divine:BAAANQAECgIIAwAAAA==.',
Do='Doctaz:BAAANQAECgQIBwAAAA==.Doctrine:BAAANQAECgUIBwAAAA==.Donnabb:BAAANQAECgYIEwAAAA==.Donteatbees:BAAANQAECgcICwAAAA==.Dop:BAAANQAECgUIBwAAAA==.Doran:BAAANQADCgUIBQAAAA==.Dottierotten:BAAANQAECgUIBwAAAA==.',
Dr='Drenrah:BAABNQAECn8vAAMTAAkKQBC8VADBAQATAAkKQBC8VADBAQAFAAQKMgNvdgFQAAAAAA==.',
Ed='Edend:BAAANQADCgUICgAAAA==.',
Ei='Eiduartpaw:BAABNQAECn8eAAQTAAoKswqfmQDxAAATAAoKswqfmQDxAAAFAAYKAwinEAHQAAAVAAUKigtASQCAAAABNQAFFAQICAADAGoXAA==.',
El='Elbryan:BAAANQAECgYICAAAAA==.Electracutie:BAABNQAECn8bAAIIAAgKiArkgQAuAQAIAAgKiArkgQAuAQAAAA==.Elementdemon:BAABNQAECn8wAAIWAAkKHhSNAwClAQAWAAkKHhSNAwClAQAAAA==.',
En='Enthalpy:BAABNQAECn9EAAIXAAoKDRySLwCCAgAXAAoKDRySLwCCAgAAAA==.',
Es='Esperzoa:BAAANQAECgUIDAAAAA==.',
Eu='Eucalicdes:BAABNQAECn9DAAIYAAoKvRd1DwBrAgAYAAoKvRd1DwBrAgAAAA==.',
Ev='Evøkër:BAAANQADCgQIBAABNQAECgoKMAAZAHkeAA==.',
Ez='Ezra:BAAANQAECgYIDgAAAA==.',
Fa='Falshin:BAAANQADCggICAAAAA==.Fancy:BAAANQAECgMIAwAAAA==.Fangyi:BAABNQAECn87AAMaAAkKhhGuDwCtAQAaAAkKhhGuDwCtAQAXAAcKjwo6FQFpAQAAAA==.Faytes:BAAANQAECgMIBQAAAA==.',
Fi='Fiction:BAAANQAECggIDAAAAA==.',
Fl='Flabutt:BAAANQAECgYIBwAAAA==.Florita:BAAANQAECgQICQAAAA==.',
Fo='Fordinn:BAABNQAECn9BAAQbAAkKcBhoEQChAQAbAAgKFRdoEQChAQACAAgK6hIIkABhAQAJAAQKMhwJGgACAQAAAA==.',
Fr='Freemi:BAAANQAECgUICAAAAA==.Freeree:BAAANQADCgMIAwAAAA==.Fren:BAABNQAECn8cAAIYAAoKPB09CgCaAgAYAAoKPB09CgCaAgAAAA==.Frenzy:BAAANQAECgcIBwAAAA==.Fruitcakes:BAAANQAECgIIAgAAAA==.',
Fu='Furrypaw:BAAANQAECgUICQABNQAECgoKMAAZAHkeAA==.Furrypunch:BAABNQAECn8wAAMZAAoKeR46CADlAgAZAAoKeR46CADlAgABAAIKUQVoVgBKAAAAAA==.',
Ga='Garataz:BAAANQADCgcICQABNQAECgYIDgAEAAAAAA==.Garzhvog:BAAANQAECggIDAABNQAECgoKTAAcAE8jAA==.Gasket:BAACNQAFFH8JAAIdAAIK5x8vEwCzAAAdAAIK5x8vEwCzAAA1AAQKfzkAAx4ACgr6HAg5AEECAB4ACArAHAg5AEECAB0ACAq4Gl9AAJoBAAAA.',
Gh='Ghostdragona:BAAANQADCgcIBwAAAA==.Ghostown:BAAANQADCgQIBAAAAA==.',
Gr='Graceful:BAABNQAECn8zAAIBAAkKcw85JQBwAQABAAkKcw85JQBwAQAAAA==.Grenie:BAAANQADCgcICAAAAA==.Grit:BAAANQAECgYIDgAAAA==.Grëzel:BAAANQADCgYIBgABNQAECggIDwAEAAAAAA==.',
Ha='Handicap:BAAANQAECgEIAQABNQAECgoKHwAFADciAA==.Hark:BAACNQAFFH8JAAIDAAIKTA4rJQCMAAADAAIKTA4rJQCMAAA1AAQKfzoAAwMACgrXHNQ/AKsCAAMACgrXHNQ/AKsCAB8AAQpjCPiLADMAAAAA.Harpin:BAABNQAECn8/AAIKAAoKGh6THgDoAgAKAAoKGh6THgDoAgAAAA==.Harvin:BAABNQAECn8yAAIgAAgKwx9NCgCRAgAgAAgKwx9NCgCRAgAAAA==.',
He='Heals:BAAANQAECggICAAAAA==.Heisenburgg:BAAANQAECgMIAwABNQAECgYIBQAEAAAAAA==.Helanua:BAABNQAECn8rAAIHAAkK3g0tbABDAQAHAAkK3g0tbABDAQAAAA==.',
Hi='Highlight:BAAANQAECgcIDgAAAA==.Hippopotamus:BAAANQADCgIIAgAAAA==.Hit:BAAANQAECgYIBQAAAA==.Hitt:BAAANQADCgEIAQABNQAECgYIBQAEAAAAAA==.',
Ho='Holybuttkick:BAAANQADCggIEQAAAA==.Holyish:BAAANQAECgIIAgAAAA==.Holyrollers:BAABNQAECn8mAAIKAAoKXg8ZTgAAAgAKAAoKXg8ZTgAAAgAAAA==.Holytide:BAABNQAECn8jAAMIAAgK5BBaewBBAQAIAAcKYw5aewBBAQAHAAcKGAWHnADOAAAAAA==.Hops:BAAANQADCgQIBAAAAA==.Hornsie:BAAANQADCgIIAgAAAA==.Horrorfang:BAABNQAECn9AAAIeAAoKaB1EDwCKAgAeAAoKaB1EDwCKAgAAAA==.',
['Hä']='Häwke:BAAANQADCgQIBwAAAA==.',
Ib='Ibaar:BAACNQAFFH8bAAMGAAgKPyJeAADFAgAGAAcK3iNeAADFAgAhAAEKIhrPDQBSAAA1AAQKfy4AAwYACgo/JFoGACUDAAYACgo/JFoGACUDACEAAQpBIPMYAGAAAAAA.',
Ic='Icialiaa:BAAANQADCgIIAgABNQAECgYIDwAEAAAAAA==.',
In='Inno:BAABNQAECn8yAAIiAAoKCCWeBQAGAwAiAAoKCCWeBQAGAwAAAA==.',
It='Ithacus:BAABNQAECn81AAIjAAoK7Ba/DwAZAgAjAAoK7Ba/DwAZAgAAAA==.Itspriesty:BAAANQAECgEIAQAAAA==.',
Ja='Janari:BAAANQADCggIFAAAAA==.Jandaar:BAAANQADCgYICQAAAA==.Jatt:BAAANQAECgYICgAAAA==.Jattix:BAAANQADCgQIBAAAAA==.',
Jd='Jdawgprime:BAAANQABCgQIBAAAAA==.',
Ji='Jilkaeden:BAAANQAECgcIDwAAAA==.',
Jo='Jorek:BAABNQAECn9DAAICAAkKxw+IcwCoAQACAAkKxw+IcwCoAQAAAA==.Josh:BAAANQAECgMICQAAAA==.',
Jr='Jrue:BAAANQAECgMIBQAAAA==.',
Ju='Jurtkal:BAAANQAECgEIAQAAAA==.',
Ka='Kahnoisseur:BAAANQADCgUIBQAAAA==.Kaiva:BAAANQAECgQICwAAAA==.Kavik:BAAANQAECgIIAgAAAA==.',
Ke='Keflá:BAAANQAECgQIBwAAAA==.Keineliebe:BAAANQAECgIIAgAAAA==.Kelencye:BAAANQAECgMICQAAAA==.',
Kh='Khaas:BAABNQAECn8tAAIeAAgKawqUOwAnAQAeAAgKawqUOwAnAQAAAA==.Khanloa:BAAANQADCgUIBQAAAA==.Kheleze:BAAANQAECgcIDwABNQAECggICQAEAAAAAA==.',
Ki='Killerbell:BAAANQAECgYICwAAAA==.Killshot:BAAANQADCgcICQAAAA==.',
Ko='Korihor:BAABNQAECn8fAAIVAAcKBhJkLgAGAQAVAAcKBhJkLgAGAQAAAA==.',
Kr='Krestus:BAABNQAECn8sAAQLAAoKrSDaEQCaAgALAAkKaxvaEQCaAgAiAAkKOB7zGADpAQAkAAcKKR/JDgDMAQAAAA==.Krispy:BAABNQAECn8jAAQlAAgKVRd/DQBTAQABAAgK1hY2KADeAQAlAAgKnRF/DQBTAQAZAAEKxAL6VAAgAAAAAA==.Krispyy:BAAANQAECgcICgAAAA==.Krix:BAAANQAECgUICgAAAA==.',
Ku='Kuroji:BAAANQABCgEIAQAAAA==.',
La='Laerin:BAAANQAECgcICQAAAA==.Landreielea:BAABNQAECn8eAAIDAAoKCgwUmADYAQADAAoKCgwUmADYAQAAAA==.Laxus:BAAANQAECgYIDgAAAA==.',
Le='Lerenor:BAAANQAECggIDwAAAA==.Levophed:BAAANQAECgUICAAAAA==.',
Li='Lightseeker:BAAANQAECgEIAQABNQAECgYIDgAEAAAAAA==.Lily:BAABNQAECn8YAAIYAAcKRBCRIgCDAQAYAAcKRBCRIgCDAQAAAA==.Linadra:BAAANQADCgEIAQAAAA==.Linnt:BAAANQAECgcICAAAAA==.Liyara:BAACNQAFFH8JAAIFAAIKMx1CHwCiAAAFAAIKMx1CHwCiAAA1AAQKfzsAAgUACgoJJC0ZAF8DAAUACgoJJC0ZAF8DAAAA.',
Ll='Llorsa:BAABNQAECn8yAAIKAAgKyQ8/ZQCwAQAKAAgKyQ8/ZQCwAQAAAA==.Lltoj:BAAANQADCgEIAQAAAA==.',
Lu='Lusavahza:BAAANQADCgUIBgAAAA==.Luxian:BAAANQAECgIIAwAAAA==.',
Ly='Lyssirix:BAAANQAECgMIAgAAAA==.',
['Lä']='Ländrei:BAAANQAECgIIAgABNQAECgoKHgADAAoMAA==.',
Ma='Macy:BAAANQABCgIIAgAAAA==.Mahralla:BAAANQADCgUIBQAAAA==.Maikagond:BAAANQADCgYIBgABNQAECgoKSAAFADoPAA==.Makaria:BAAANQAECgUIDQAAAA==.Malbisa:BAAANQAECgUIDgAAAA==.Malphoz:BAAANQADCgUIBQAAAA==.Mandragora:BAAANQAECgYIDgAAAA==.Marli:BAAANQADCgIIAgAAAA==.',
Mc='Mcsorley:BAAANQADCgMIAwAAAA==.',
Mi='Mickey:BAABNQAECn8aAAIBAAkKvhuxGgBpAgABAAkKvhuxGgBpAgAAAA==.Mikiik:BAABNQAECn8kAAMcAAgK4QXLFgCnAAAcAAcKRgbLFgCnAAAUAAQKBgVpFAGhAAAAAA==.Mikk:BAAANQADCgIIAgAAAA==.Mildoo:BAABNQAECn8sAAImAAkKBQ9LCwCSAQAmAAkKBQ9LCwCSAQAAAA==.Milkymoo:BAAANQAECgUICgABNQAFFAcIIgAKALYWAA==.',
Mo='Monq:BAAANQAECggIDgAAAA==.Moón:BAABNQAECn8pAAMSAAkKeBSrEQCsAQASAAkKeBSrEQCsAQARAAEKbQaHhAAcAAAAAA==.',
My='Mythlocked:BAAANQAECgUICAAAAA==.',
['Mî']='Mîlk:BAAANQADCgIIAgAAAA==.',
Na='Naomii:BAAANQADCgIIAgAAAA==.Narus:BAABNQAECn8VAAIkAAcK2Qk+GgDEAAAkAAcK2Qk+GgDEAAABNQAECgkJQQAbAHAYAA==.',
Ne='Nephadin:BAAANQADCggICAABNQAECgoKQQAVAM8hAA==.Nephdragon:BAAANQAECgUICAABNQAECgoKQQAVAM8hAA==.Neviaa:BAABNQAECn8oAAMeAAkKlxZJRAAJAgAeAAkKlxZJRAAJAgAnAAYKtg19YQC/AAAAAA==.',
Ni='Nickypoo:BAAANQADCgYICQAAAA==.Nightmenace:BAAANQAECgQIBgAAAA==.Niq:BAAANQAECgIIAQAAAA==.',
No='Norasmine:BAAANQAECgUIBQABNQAECgYIDwAEAAAAAA==.Norasong:BAAANQAECgUICQAAAA==.Norii:BAAANQADCgMIAwABNQAECgcIFQAKALQMAA==.Nothealster:BAABNQAECn8ZAAIMAAcKAgkiPQBCAQAMAAcKAgkiPQBCAQAAAA==.Novacane:BAAANQAECgEIAgAAAA==.',
Ob='Obitrice:BAABNQAECn8oAAIDAAkKdxK6nADNAQADAAkKdxK6nADNAQABNQAECgkJIQAYAE8TAA==.Obsidiian:BAAANQAECgYICwAAAA==.Obsidion:BAABNQAECn8cAAMKAAgKhQvMpgAhAQAKAAgKhQvMpgAhAQAMAAYKCglFRQCXAAABNQAECgkJQQAbAHAYAA==.',
Od='Odie:BAAANQAECgIIAgAAAA==.',
On='Onetrueshot:BAAANQAECggICAAAAA==.',
Or='Organdonor:BAABNQAECn8gAAIKAAoKQRAMYwD3AQAKAAoKQRAMYwD3AQAAAA==.',
Os='Ossin:BAAANQAECgIIAwAAAA==.',
Pa='Pantherlilly:BAAANQAECgQICQAAAA==.',
Pe='Perry:BAAANQAECgcICQAAAA==.',
Ph='Phlampped:BAAANQADCgYIBgABNQAFFAYIBwACABEKAA==.',
Po='Pozufuma:BAABNQAECn8yAAMJAAgKHhdIDAD4AQAJAAcK2RlIDAD4AQAbAAUKIg58JwDAAAAAAA==.',
Ps='Psychomantis:BAABNQAECn89AAMMAAoKbhCIGADgAQAMAAoKbhCIGADgAQAKAAoKngvEkgBeAQAAAA==.',
Ra='Radium:BAAANQADCgcICAAAAA==.Ravenbear:BAAANQAECgUIEAAAAA==.',
Re='Redpool:BAABNQAECn8mAAIDAAkKGgv+jQCbAQADAAkKGgv+jQCbAQAAAA==.Rethandra:BAAANQAECgIIAQAAAA==.Retrix:BAAANQAECgQICAAAAA==.Revorra:BAABNQAECn8VAAMjAAYKTAdgKgDCAAAjAAUKjQVgKgDCAAAIAAYKvgZI7wCMAAABNQAECgkJQQAbAHAYAA==.Rezelflezel:BAAANQAECgYIBQAAAA==.',
Ri='Ristvakbaen:BAABNQAECn9MAAQcAAoKTyOTAQCiAgAmAAkKxx4vAgDMAgAcAAoKfyKTAQCiAgAUAAgKixyFWgBHAgAAAA==.',
Ro='Robynlee:BAABNQAECn8xAAIKAAoKNhh6RAAmAgAKAAoKNhh6RAAmAgAAAA==.Rogùe:BAAANQAECgIIAgAAAA==.Rohini:BAAANQADCgQIBgAAAA==.Rosebelle:BAAANQADCgUICAAAAA==.Rovik:BAAANQAECgQIBwAAAA==.',
Sa='Samâell:BAAANQAECgMIAwAAAA==.Santeclair:BAAANQAECgQIBwAAAA==.',
Sc='Sceryna:BAABNQAECn8yAAQFAAoK/BuHYgBzAgAFAAoK/BuHYgBzAgAVAAIKtReBXgBhAAATAAEKYQKJDAEeAAAAAA==.Schiftly:BAAANQADCgQIBAAAAA==.Schwiggity:BAAANQADCgQIBQABNQAECgYIDgAEAAAAAA==.Scrmndemn:BAABNQAECn8fAAIFAAkKwAR/CQEPAQAFAAkKwAR/CQEPAQAAAA==.',
Se='Sef:BAAANQAECgYICwAAAA==.Sequan:BAAANQADCgUIBQAAAA==.Serpent:BAAANQAFFAMIBAABNQAFFAYIBwAVANcGAA==.',
Sh='Shamadeus:BAAANQAECgQICAABNQAECgoKTAAcAE8jAA==.Shamenio:BAAANQAECgYICAAAAA==.Shamtastical:BAABNQAECn8aAAIIAAcKERMbnwA5AQAIAAcKERMbnwA5AQABNQAECgoKMQAKADYYAA==.Sheeara:BAAANQADCgYIBgAAAA==.Shikita:BAABNQAECn85AAIRAAkKnxsmFQB8AgARAAkKnxsmFQB8AgAAAA==.Shimadin:BAACNQAFFH8TAAIFAAcKsBAIEQA9AQAFAAcKsBAIEQA9AQA1AAQKf1IAAgUACgqPJI0SABwDAAUACgqPJI0SABwDAAAA.Shimjun:BAAANQAECgcIBgABNQAFFAcIEwAFALAQAA==.Shirma:BAAANQABCgIIAgAAAA==.Shmerek:BAABNQAECn9DAAIbAAkKcBsRCwAXAgAbAAkKcBsRCwAXAgAAAA==.',
Si='Sierramist:BAABNQAECn83AAIZAAkKzRwDCQDPAgAZAAkKzRwDCQDPAgAAAA==.Sijon:BAAANQAECgEIAQAAAA==.Silverpacem:BAAANQAECgQIBAAAAA==.Silverstream:BAABNQAECn9EAAIRAAoKZB06CwAZAwARAAoKZB06CwAZAwAAAA==.',
Sm='Smith:BAAANQADCgIIAgAAAA==.',
So='Solbin:BAABNQAECn8iAAIkAAgK+CLCAwAgAwAkAAgK+CLCAwAgAwABNQAECgoKMgAXAJkgAA==.Solexine:BAAANQADCgQIBAAAAA==.Solitudé:BAAANQAECgQICgABNQAFFAIICQAdAMQhAA==.Soteirian:BAABNQAECn9IAAMFAAoKOg/8gADLAQAFAAoKOg/8gADLAQAVAAEKAADVdwAlAAAAAA==.',
Sp='Spiritlinkin:BAABNQAECn84AAIHAAoKFBz1HACJAgAHAAoKFBz1HACJAgAAAA==.',
St='Stalariais:BAAANQADCgYIBgABNQAECggIDgAEAAAAAA==.Steakhammer:BAAANQAECgUIBQABNQAECgoKMAAZAHkeAA==.Steve:BAABNQAECn8hAAICAAkKhwvrjwBhAQACAAkKhwvrjwBhAQAAAA==.Straw:BAAANQABCgIIAgABNQAECgoKOgATACIUAA==.',
Su='Sugardawn:BAAANQAECgQIBAAAAA==.Sugarkitty:BAAANQADCgcIBwAAAA==.Supereclipse:BAABNQAECn8xAAIDAAgKlhLGiACmAQADAAgKlhLGiACmAQAAAA==.',
Sy='Sydvicious:BAABNQAECn8rAAILAAoKFyHvEQAPAwALAAoKFyHvEQAPAwAAAA==.',
Ta='Taintedwater:BAAANQAECgYIDwAAAA==.Tairnanach:BAAANQADCgYIDgAAAA==.Taladiir:BAABNQAECn8UAAIDAAoKFQxhdADWAQADAAoKFQxhdADWAQAAAA==.Talana:BAAANQAECgYIEAAAAA==.Tayger:BAAANQADCgcJEAAAAA==.',
Td='Tdog:BAAANQADCgcIDgAAAA==.',
Te='Tecks:BAABNQAECn9DAAIKAAkK4w0YZACzAQAKAAkK4w0YZACzAQAAAA==.Teslá:BAAANQAECgEIAQAAAA==.',
Th='Thaldur:BAAANQAECgIIAQABNQAECgoKLAALAK0gAA==.Thayo:BAAANQAECgEIAQAAAA==.Theatrix:BAAANQAECgMIBAABNQAECggIFQACAGwVAA==.Thefreeman:BAAANQAECgUICAAAAA==.Themajor:BAAANQAECgQIBQAAAA==.Therossyas:BAABNQAECn8VAAIDAAYKXBE4tQBHAQADAAYKXBE4tQBHAQAAAA==.Thezuggest:BAAANQADCgMJAwAAAA==.Thicctotems:BAACNQAFFH8SAAMIAAYKUB1KDQB5AQAIAAYKUB1KDQB5AQAHAAEKCQTbNAA/AAA1AAQKfzEAAwgACQqvIb0WAAEDAAgACQqvIb0WAAEDAAcAAgoRFA0DAYkAAAAA.Threat:BAABNQAECn9WAAIFAAoKMSYVAwB+AwAFAAoKMSYVAwB+AwAAAA==.Thunderthigh:BAAANQADCgYIAwAAAA==.Thungerthi:BAAANQADCgUICAAAAA==.',
Ti='Tiamaat:BAABNQAECn9DAAMQAAkKpAZ5RAASAQAQAAkKpAZ5RAASAQARAAEK6QFnegApAAAAAA==.Tinysanta:BAAANQAECgIIBAAAAA==.Titus:BAAANQADCgYICQAAAA==.',
To='Toatani:BAAANQAECgQIBQABNQAECgQICwAEAAAAAA==.Tokkaebi:BAAANQAECgcICwAAAA==.Torvar:BAAANQADCggIDwAAAA==.',
Ty='Tyletos:BAABNQAECn8yAAMXAAoKmSDJIQBUAwAXAAoKYCDJIQBUAwAaAAUKXR02EgCDAQAAAA==.',
Ug='Ugolok:BAAANQADCgcIDQAAAA==.',
Ur='Uriél:BAAANQADCgQIBAABNQAFFAIICQAdAMQhAA==.Urubaen:BAABNQAECn8UAAQkAAkKmxocDwDFAQAkAAcKrRscDwDFAQAiAAQKJBGpPQC2AAALAAEKRQwgigArAAABNQAECgoKTAAcAE8jAA==.',
Va='Valanoth:BAAANQADCgIIAgAAAA==.Valeene:BAABNQAECn8wAAIQAAoKACE6GgD3AgAQAAoKACE6GgD3AgAAAA==.Varek:BAAANQAECgcICAAAAA==.',
Ve='Veiler:BAABNQAECn89AAQDAAoKjg0kgwCzAQADAAkKJg0kgwCzAQAfAAgKDgU5RAA3AQAoAAIKiAOcFAA1AAAAAA==.Veruca:BAAANQAECgYIBgAAAA==.Veviseron:BAABNQAECn88AAIaAAoKlAZGFwArAQAaAAoKlAZGFwArAQAAAA==.',
Vi='Vinstalation:BAAANQAECgQIBwAAAA==.',
Vo='Vonbismarck:BAABNQAECn8vAAMDAAkK7Q8HegDIAQADAAkK7Q8HegDIAQAfAAYKmAk7RwAiAQAAAA==.',
Vr='Vritraz:BAACNQAFFH8JAAIdAAIKxCEOEgDAAAAdAAIKxCEOEgDAAAA1AAQKfzoAAh0ACgplI4MKAEYDAB0ACgplI4MKAEYDAAAA.',
Wa='Warsonge:BAAANQAECgUICQAAAA==.Waxoff:BAAANQAECgQIAwAAAA==.',
We='Wendypini:BAABNQAECn9BAAIDAAoKIhfmSgCNAgADAAoKIhfmSgCNAgAAAA==.',
Wh='Whitlock:BAAANQAECgQICAAAAA==.',
Xe='Xendria:BAAANQADCggICgAAAA==.',
Ya='Yannhal:BAAANQAECgIIAgAAAA==.',
Za='Zangelf:BAAANQABCggIFAAAAA==.',
Zo='Zodiaac:BAABNQAECn9DAAMnAAkKwxcHOAAoAgAnAAkKwxcHOAAoAgAeAAEKAABlpwAAAAAAAA==.',
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
