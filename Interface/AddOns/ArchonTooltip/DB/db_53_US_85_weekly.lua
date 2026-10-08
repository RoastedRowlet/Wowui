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

local lookup = {'Unknown-Unknown','Shaman-Elemental','DemonHunter-Havoc','Priest-Shadow','Priest-Holy','Druid-Balance','Druid-Restoration','Hunter-BeastMastery','Paladin-Holy','Warlock-Demonology','Rogue-Outlaw','Mage-Arcane','Druid-Guardian','Mage-Frost','Warrior-Fury','Warrior-Arms','Warrior-Protection','DeathKnight-Unholy','DeathKnight-Frost','Monk-Windwalker','Evoker-Devastation','Paladin-Retribution','Warlock-Destruction','Warlock-Affliction','Paladin-Protection','DeathKnight-Blood','Monk-Mistweaver','DemonHunter-Vengeance','Shaman-Restoration','Hunter-Marksmanship',}
local provider = {region='US',realm='Eitrigg',name='US',type='weekly',zone=53,date='2026-10-06',data={Al='Alys:BAAANQAECgQIBAAAAA==.',
Am='Amaniatres:BAAANQAECgcIEwAAAA==.Ammartin:BAAANQAECgUIDgAAAA==.Amperage:BAAANQADCgUIEAABNQAECgcIEwABAAAAAA==.',
An='Anaan:BAAANQAECgMIAwAAAA==.Anahera:BAAANQADCgcIBwABNQAECgQICQABAAAAAA==.Anthion:BAAANQABCgIIAgAAAA==.Anzhelina:BAAANQAECgcIDAAAAA==.',
Ap='Apis:BAAANQAECgIIAgAAAA==.Aprys:BAAANQABCggIDwAAAA==.',
Ar='Arihana:BAAANQAECgQICQAAAA==.',
As='Asapshocky:BAACNQAFFIEJAAICAAQKIxRZDgBIAQACAAQKIxRZDgBIAQA1AAQKgSAAAgIACQqNHiUgAO4CAAIACQqNHiUgAO4CAAAA.Asmoday:BAAANQADCggIDwAAAA==.',
Ba='Baahp:BAAANQAECgUICQAAAA==.Barley:BAAANQABCgIIAgAAAA==.',
Be='Belgerra:BAAANQAECgYJDQAAAA==.Bellabelle:BAAANQADCgYIDAAAAA==.Bevian:BAAANQADCgEIAQABNQAECgQICAABAAAAAA==.',
Bi='Biggiepants:BAABNQAECoEYAAIDAAgKFxiOJwA4AgADAAgKFxiOJwA4AgAAAA==.Biggnome:BAAANQADCgYIBgABNQADCgUICQABAAAAAA==.Bighead:BAAANQAECgMIAwABNQADCgUICQABAAAAAA==.Bigr:BAAANQADCgIIAgAAAA==.Bigwarlocks:BAAANQADCggICAABNQADCgUICQABAAAAAA==.Biollante:BAAANQADCgYICAAAAA==.',
Bo='Bootyßandaid:BAAANQAECgUICgAAAA==.',
Bu='Buckis:BAAANQAECgQIBwAAAA==.',
Ca='Camderags:BAAANQADCggICAAAAA==.Catasucked:BAAANQADCgMIAwAAAA==.',
Ch='Chillin:BAAANQADCgEIAQAAAA==.Choggy:BAABNQAECoEgAAMEAAcKiBpKHQAzAgAEAAcKiBpKHQAzAgAFAAIKKxlexQCRAAAAAA==.Churro:BAAANQADCgcIBwAAAA==.',
Ci='Cindrõz:BAAANQAECgQIBAAAAA==.',
Co='Conception:BAAANQADCggIFAABNQAECgYIEwABAAAAAA==.Cough:BAAANQADCgUICQAAAA==.',
Cr='Crinklecut:BAAANQAECgQICgAAAA==.Crow:BAABNQAECoEdAAMGAAgKDSM7EwAZAwAGAAgKDSM7EwAZAwAHAAcKJBwWGQBMAgAAAA==.',
Da='Danielallen:BAAANQAECgQICQAAAA==.Danyrogue:BAAANQAECgcIBwABNQAFFAYIDQAIAJcWAA==.',
De='Deadlybeard:BAAANQADCgQICQABNQAECgcIHQAJAK0hAA==.Deadlywrath:BAABNQAECoEdAAIJAAcKrSFgKwCgAgAJAAcKrSFgKwCgAgAAAA==.Deadmenace:BAAANQADCgYJCwAAAA==.Decåying:BAABNQAECoEdAAIKAAcK1AjQoABlAQAKAAcK1AjQoABlAQAAAA==.Demonsangel:BAAANQABCgIIAgAAAA==.Deni:BAAANQAECgQIBAAAAA==.Denli:BAAANQADCgQIAgAAAA==.',
Di='Diagnosis:BAAANQAECgcIEAAAAA==.',
Do='Donnabb:BAAANQAECgQIDAAAAA==.Donteatbees:BAAANQAECgQIBwAAAA==.Dop:BAAANQAECgQIBwAAAA==.Doran:BAAANQADCgUIBQAAAA==.Dottierotten:BAAANQADCggIDgAAAA==.',
Dr='Drenrah:BAAANQAECgUIEwAAAA==.',
Ed='Edend:BAAANQADCgUICgAAAA==.',
Ei='Eiduartpaw:BAAANQAECgUICQAAAA==.',
El='Electracutie:BAAANQAECgcIDAAAAA==.Elementdemon:BAABNQAECoEeAAILAAcKuw/ACgCtAQALAAcKuw/ACgCtAQAAAA==.',
En='Enthalpy:BAABNQAECoEfAAIMAAgKwBpIfgBqAgAMAAgKwBpIfgBqAgAAAA==.',
Es='Esperzoa:BAAANQAECgQIDAAAAA==.',
Eu='Eucalicdes:BAABNQAECoEkAAINAAgK8xczEAAeAgANAAgK8xczEAAeAgAAAA==.',
Ev='Evøkër:BAAANQADCgQIBAABNQAECgYIBwABAAAAAA==.',
Ez='Ezra:BAAANQADCgUICgAAAA==.',
Fa='Falshin:BAAANQADCggICAAAAA==.Fancy:BAAANQADCgYIJAAAAA==.Fangyi:BAABNQAECoEdAAMOAAcKFBG0DgCTAQAOAAcKFBG0DgCTAQAMAAcKYgnm+gBxAQAAAA==.',
Fi='Fiction:BAAANQAECggIDAAAAA==.',
Fl='Flabutt:BAAANQAECgIIAgAAAA==.Florita:BAAANQAECgEIAQAAAA==.',
Fo='Fordinn:BAABNQAECoEeAAQPAAcKoxizFgAPAQAQAAYKDBFctgBlAQARAAQKjRflIAAYAQAPAAQKBhyzFgAPAQAAAA==.',
Fr='Fren:BAAANQAECgUICQAAAA==.Fruitcakes:BAAANQAECgIIAgAAAA==.',
Fu='Furrypunch:BAAANQAECgYIBwAAAA==.',
Ga='Gasket:BAABNQAECoEjAAMSAAgKFR7ULwBNAgASAAgKFR7ULwBNAgATAAUKRhLCWgDtAAAAAA==.',
Gh='Ghostdragona:BAAANQADCgcIBwAAAA==.',
Gr='Graceful:BAABNQAECoEZAAIUAAcKqg38LgBsAQAUAAcKqg38LgBsAQAAAA==.Grit:BAAANQAECgMJAwAAAA==.',
Ha='Handicap:BAAANQAECgEIAQABNQAECgcIEAABAAAAAA==.Hark:BAABNQAECoEjAAIIAAgKERt9QACFAgAIAAgKERt9QACFAgAAAA==.Harpin:BAABNQAECoEeAAIFAAgK1B0gKgCiAgAFAAgK1B0gKgCiAgAAAA==.Harvin:BAAANQAECgUIEQAAAA==.',
He='Heals:BAAANQAECggICAAAAA==.Heisenburgg:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Helanua:BAAANQAECgYIDQAAAA==.',
Hi='Highlight:BAAANQAECgQIBgAAAA==.Hippopotamus:BAAANQADCgIIAgAAAA==.Hit:BAAANQAECgIIAgAAAA==.Hitt:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.',
Ho='Holyish:BAAANQAECgIIAgAAAA==.Holyrollers:BAAANQAECgcIBwAAAA==.Holytide:BAAANQAECgMJBAAAAA==.Hops:BAAANQADCgQIBAAAAA==.Hornsie:BAAANQADCgIIAgAAAA==.Horrorfang:BAAANQAECgUIEQAAAA==.',
['Hä']='Häwke:BAAANQADCgQIBwAAAA==.',
Ib='Ibaar:BAACNQAFFIEXAAIVAAYKPSTDAABuAgAVAAYKPSTDAABuAgA1AAQKgSIAAhUACQpjI/QEADUDABUACQpjI/QEADUDAAAA.',
Ic='Icialiaa:BAAANQADCgIIAgABNQAECgQIAwABAAAAAA==.',
In='Inno:BAAANQAECgUIDwAAAA==.',
It='Ithacus:BAAANQAECgUIEwAAAA==.Itspriesty:BAAANQAECgEIAQAAAA==.',
Ja='Janari:BAAANQADCgYIBgAAAA==.Jandaar:BAAANQADCgYICQAAAA==.Jatt:BAAANQADCggICAAAAA==.Jattwuzza:BAAANQADCgQIBAAAAA==.',
Jd='Jdawgprime:BAAANQABCgQIBAAAAA==.',
Ji='Jilkaeden:BAAANQAECgQIBQAAAA==.',
Jo='Jorek:BAABNQAECoEdAAIQAAcKNA/roACfAQAQAAcKNA/roACfAQAAAA==.Josh:BAAANQAECgIIAgAAAA==.',
Jr='Jrue:BAAANQADCgcIBwAAAA==.',
Ju='Jurtkal:BAAANQAECgEIAQAAAA==.',
Ka='Kaiva:BAAANQAECgQICQAAAA==.Kavik:BAAANQAECgIIAgAAAA==.',
Ke='Keflá:BAAANQAECgMIAwAAAA==.Kelencye:BAAANQAECgMIBwAAAA==.',
Kh='Khaas:BAAANQAECgUICwAAAA==.Khanloa:BAAANQADCgUIBQAAAA==.Kheleze:BAAANQADCggIDgABNQAECgUIDQABAAAAAA==.',
Ki='Killerbell:BAAANQAECgEIAwAAAA==.Killshot:BAAANQADCgcICQAAAA==.',
Ko='Korihor:BAAANQAECgQIDAAAAA==.',
Kr='Krestus:BAAANQAECgUICwAAAA==.Krispy:BAAANQAECgQIBgAAAA==.Krispyy:BAAANQAECgUIBQAAAA==.Krix:BAAANQAECgMIAwAAAA==.',
Ku='Kuroji:BAAANQABCgEIAQAAAA==.',
La='Laerin:BAAANQAECgQIBgAAAA==.Landreielea:BAAANQAECgYIDAAAAA==.Laxus:BAAANQAECgUICQAAAA==.',
Le='Lerenor:BAAANQAECgIIAgAAAA==.Levophed:BAAANQAECgUJCAAAAA==.',
Li='Lily:BAAANQAECgUIDwAAAA==.Linnt:BAAANQAECgEIAQAAAA==.Liyara:BAABNQAECoEiAAIWAAgKuySTIQAmAwAWAAgKuySTIQAmAwAAAA==.',
Ll='Llorsa:BAAANQAECgUIDwAAAA==.Lltoj:BAAANQADCgEIAQAAAA==.',
Lu='Lusavahza:BAAANQADCgUIBgAAAA==.Luxian:BAAANQADCgYIBgAAAA==.',
['Lä']='Ländrei:BAAANQAECgIIAgABNQAECgYIDAABAAAAAA==.',
Ma='Macy:BAAANQABCgIIAgAAAA==.Mahralla:BAAANQADCgUIBQAAAA==.Maikagond:BAAANQADCgYIBgABNQAECgcIHQAWAJoLAA==.Makaria:BAAANQAECgQICgAAAA==.Malbisa:BAAANQADCggIEQAAAA==.Malphoz:BAAANQADCgUIBQAAAA==.Mandragora:BAAANQADCggIEwAAAA==.Marli:BAAANQADCgIIAgAAAA==.',
Mi='Mickey:BAABNQAECoEYAAIUAAgKDRpZHQAfAgAUAAgKDRpZHQAfAgAAAA==.Mikiik:BAAANQAECgUIDwAAAA==.Mikk:BAAANQADCgIJAgAAAA==.Mildoo:BAAANQAECgUIEQAAAA==.Milkymoo:BAAANQAECgQIAwABNQAFFAcIGgAFAL0SAA==.',
Mo='Monq:BAAANQAECgUIBgAAAA==.Moón:BAAANQAECgYIEwAAAA==.',
['Mî']='Mîlk:BAAANQADCgIIAgAAAA==.',
Na='Narus:BAAANQAECgQIBgABNQAECgcIHgAPAKMYAA==.',
Ne='Neviaa:BAAANQAECgYIDwAAAA==.',
Ni='Nickypoo:BAAANQADCgYICQAAAA==.Nightmenace:BAAANQAECgQIBgAAAA==.Niq:BAAANQAECgEIAQAAAA==.',
No='Nothealster:BAAANQAECgUIEwAAAA==.Novacane:BAAANQAECgEIAgAAAA==.',
Ob='Obitrice:BAAANQAECgYIEwABNQAECgQICQABAAAAAA==.Obsidiian:BAAANQAECgUICQAAAA==.Obsidion:BAAANQAECgUIBwABNQAECgcIHgAPAKMYAA==.',
Od='Odie:BAAANQAECgIIAgAAAA==.',
Or='Organdonor:BAABNQAECoEaAAIFAAgKSROjVAD4AQAFAAgKSROjVAD4AQAAAA==.',
Os='Ossin:BAAANQAECgIIAwAAAA==.',
Pa='Pantherlilly:BAAANQAECgEIAQAAAA==.',
Pe='Perry:BAAANQAECgIIAwAAAA==.',
Ph='Phlampped:BAAANQADCgYIBgABNQAFFAUICQAWADwbAA==.',
Po='Pozufuma:BAAANQAECgUIDwAAAA==.',
Ps='Psychomantis:BAABNQAECoEgAAMEAAgKkxFrKwCjAQAEAAcKsw9rKwCjAQAFAAYK6QlfjgAwAQAAAA==.',
Ra='Radium:BAAANQABCgMIBAAAAA==.Ravenbear:BAAANQAECgUIDgAAAA==.',
Re='Redpool:BAAANQAECgUIEwAAAA==.Rethandra:BAAANQADCgEIAQAAAA==.Retrix:BAAANQAECgQICAAAAA==.Revorra:BAAANQAECgQIDAABNQAECgcIHgAPAKMYAA==.Rezelflezel:BAAANQAECgUIBQAAAA==.',
Ri='Ristvakbaen:BAABNQAECoEhAAQKAAgK8x+VSABbAgAKAAcK0h2VSABbAgAXAAMKQSIqKQAlAQAYAAEKxRKBJQBFAAAAAA==.',
Ro='Robynlee:BAAANQAECgYIEwAAAA==.Rohini:BAAANQADCgQIBgAAAA==.Rovik:BAAANQAECgQIBwAAAA==.',
Sc='Sceryna:BAABNQAECoEbAAMWAAgKuxwfTQCGAgAWAAgKuxwfTQCGAgAZAAIKtRcJUgBrAAAAAA==.Schiftly:BAAANQADCgQIBAAAAA==.Scrmndemn:BAAANQAECgcIEwAAAA==.',
Se='Sef:BAAANQAECgUICwAAAA==.Serpent:BAAANQADCgUIBQABNQAFFAUIDAAaAJMPAA==.',
Sh='Shamtastical:BAAANQAECgUIEAABNQAECgYIEwABAAAAAA==.Shikita:BAAANQAECgUIEAAAAA==.Shimadin:BAACNQAFFIEMAAIWAAQKmRSHDABGAQAWAAQKmRSHDABGAQA1AAQKgScAAhYACQp6IlwvAO0CABYACQp6IlwvAO0CAAAA.Shimjun:BAAANQAECgYIBgABNQAFFAQIDAAWAJkUAA==.Shimsong:BAAANQADCggIDQABNQAFFAQIDAAWAJkUAA==.Shirma:BAAANQABCgIIAgAAAA==.Shmerek:BAABNQAECoEdAAIRAAcKQxfIEQDbAQARAAcKQxfIEQDbAQAAAA==.',
Si='Sierramist:BAABNQAECoEbAAIbAAcKExwYEgAvAgAbAAcKExwYEgAvAgAAAA==.Silverpacem:BAAANQAECgQIBAAAAA==.Silverstream:BAABNQAECoEkAAIHAAkKfRnZEACwAgAHAAkKfRnZEACwAgAAAA==.',
So='Solbin:BAABNQAECoEYAAIcAAcK5iN+BADSAgAcAAcK5iN+BADSAgABNQAECggIIAAMAMAeAA==.Solexine:BAAANQADCgQIBAAAAA==.Solitudé:BAAANQAECgMIBwABNQAECggIIwATADMkAA==.Soteirian:BAABNQAECoEdAAMWAAcKmgs+tgB4AQAWAAcKmgs+tgB4AQAZAAEKgASXaQAmAAAAAA==.',
Sp='Spiritlinkin:BAAANQAECgUIDAAAAA==.',
St='Stalariais:BAAANQADCgYIBgABNQAECgcIDAABAAAAAA==.Steve:BAAANQAECgUIDAAAAA==.',
Su='Sugardawn:BAAANQAECgQIBAAAAA==.Sugarkitty:BAAANQADCgcIBwAAAA==.Supereclipse:BAAANQAECgUIDwAAAA==.',
Sy='Sydvicious:BAABNQAECoEWAAIDAAcKWR+eHwB3AgADAAcKWR+eHwB3AgAAAA==.',
Ta='Taintedwater:BAAANQAECgQIAwAAAA==.Tairnanach:BAAANQADCgYIDgAAAA==.Taladiir:BAAANQAECgIIAgAAAA==.Tayger:BAAANQADCgcJEAAAAA==.',
Td='Tdog:BAAANQADCgcIDgAAAA==.',
Te='Tecks:BAABNQAECoEdAAIFAAcKTwjJhQBLAQAFAAcKTwjJhQBLAQAAAA==.Teslá:BAAANQAECgEIAQAAAA==.',
Th='Thayo:BAAANQAECgEIAQAAAA==.Theatrix:BAAANQAECgMIBAABNQAECgcIEwABAAAAAA==.Themajor:BAAANQAECgIIAgAAAA==.Therossyas:BAAANQAECgQIBAAAAA==.Thezuggest:BAAANQADCgMJAwAAAA==.Thicctotems:BAACNQAFFIEMAAMdAAQK/R3BCgCAAQAdAAQK/R3BCgCAAQACAAEKCQSwLAA/AAA1AAQKgSIAAx0ACArwIQksAI4CAB0ACArwIQksAI4CAAIAAgoRFHDkAJAAAAAA.Threat:BAABNQAECoEfAAIWAAgKaiWuFQBdAwAWAAgKaiWuFQBdAwAAAA==.Thunderthigh:BAAANQADCgYIAwAAAA==.Thungerthi:BAAANQADCgUICAAAAA==.',
Ti='Tiamaat:BAABNQAECoEdAAMGAAcKGgbeaQD5AAAGAAYKSQbeaQD5AAAHAAEK6QEEawAqAAAAAA==.Tinysanta:BAAANQAECgIIBAAAAA==.Titus:BAAANQADCgYICQAAAA==.',
To='Toatani:BAAANQADCgMJAwABNQAECgQICQABAAAAAA==.Tokkaebi:BAAANQABCgIIAgAAAA==.Torvar:BAAANQADCggIDwAAAA==.',
Ty='Tyletos:BAABNQAECoEgAAMMAAgKwB64TwDRAgAMAAgKhh64TwDRAgAOAAUKVxvmDgCPAQAAAA==.',
Ug='Ugolok:BAAANQADCgcIDQAAAA==.',
Ur='Uriél:BAAANQADCgQIBAABNQAECggIIwATADMkAA==.Urubaen:BAAANQADCgUIBgABNQAECggIIQAKAPMfAA==.',
Va='Valanoth:BAAANQADCgIIAgAAAA==.Valeene:BAABNQAECoEaAAIGAAgKfSCiFgD6AgAGAAgKfSCiFgD6AgAAAA==.',
Ve='Veiler:BAABNQAECoEkAAMeAAgKoggaPABBAQAeAAcKogUaPABBAQAIAAUKdQlTyAA9AQAAAA==.Veruca:BAAANQAECgIIAgAAAA==.Veviseron:BAABNQAECoEcAAIOAAYKZwcWGgD7AAAOAAYKZwcWGgD7AAAAAA==.',
Vi='Vinstalation:BAAANQAECgQIBwAAAA==.',
Vo='Vonbismarck:BAAANQAECgUIEgAAAA==.',
Vr='Vritraz:BAABNQAECoEjAAITAAgKMyQADgAIAwATAAgKMyQADgAIAwAAAA==.',
Wa='Warsonge:BAAANQAECgUIBwAAAA==.',
We='Wendypini:BAABNQAECoEjAAIIAAgKyxVHVQBJAgAIAAgKyxVHVQBJAgAAAA==.',
Wh='Whitlock:BAAANQAECgIIAwAAAA==.',
Xe='Xendria:BAAANQADCggICgAAAA==.',
Ya='Yannhal:BAAANQAECgIIAgAAAA==.',
Za='Zangelf:BAAANQABCggIFAAAAA==.Zangolf:BAAANQABCggJDQAAAA==.',
Zo='Zodiaac:BAABNQAECoEdAAIaAAcKYRqzNAAaAgAaAAcKYRqzNAAaAgAAAA==.',
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
