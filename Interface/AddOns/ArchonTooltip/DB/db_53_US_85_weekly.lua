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

local lookup = {'Unknown-Unknown','Evoker-Devastation','Shaman-Elemental','Shaman-Restoration','DemonHunter-Havoc','Priest-Shadow','Priest-Holy','Priest-Discipline','Druid-Balance','Druid-Restoration','Hunter-BeastMastery','Paladin-Holy','Warlock-Demonology','Paladin-Retribution','Rogue-Outlaw','Mage-Arcane','Druid-Guardian','Mage-Frost','Warrior-Protection','Warrior-Arms','Warrior-Fury','DeathKnight-Unholy','DeathKnight-Frost','Monk-Windwalker','Hunter-Marksmanship','Evoker-Preservation','DemonHunter-Devourer','Shaman-Enhancement','Warlock-Affliction','Druid-Feral','Paladin-Protection','DeathKnight-Blood','Warlock-Destruction','Monk-Mistweaver','DemonHunter-Vengeance',}
local provider = {region='US',realm='Eitrigg',name='US',type='weekly',zone=53,date='2026-10-13',data={Al='Alys:BAAANQAECgQIBAAAAA==.',
Am='Amaniatres:BAAANQAECgcIEwAAAA==.Ammartin:BAAANQAECgUIEAAAAA==.Amperage:BAAANQADCgUIEAABNQAECgcIEwABAAAAAA==.',
An='Anaan:BAAANQAECgUIBwAAAA==.Anahera:BAAANQADCgcIBwABNQAECgQICQABAAAAAA==.Anthion:BAAANQABCgIIAgAAAA==.Anzhelina:BAAANQAECgcIDgAAAA==.',
Ap='Apis:BAAANQAECgIIAgAAAA==.Aprys:BAAANQABCggIEAAAAA==.',
Ar='Arihana:BAABNQAECn8VAAICAAYK6AaTJgD+AAACAAYK6AaTJgD+AAAAAA==.',
As='Asapshocky:BAACNQAFFH8JAAIDAAQKchY3EgBFAQADAAQKchY3EgBFAQA1AAQKfyAAAgMACQoaHQQoAN8CAAMACQoaHQQoAN8CAAAA.Asmoday:BAAANQADCggIGgAAAA==.',
Ba='Baahp:BAAANQAECgUICQABNQAECgkJHwAEAP8QAA==.Barley:BAAANQABCgIIAgAAAA==.',
Be='Belgerra:BAAANQAECgYIEAAAAA==.Bellabelle:BAAANQADCgcIDQAAAA==.Bevian:BAAANQADCgMIAwABNQAECgQICgABAAAAAA==.',
Bi='Biggiepants:BAABNQAECn8fAAIFAAkKyhUhIwB+AgAFAAkKyhUhIwB+AgAAAA==.Biggnome:BAAANQADCgYIBgABNQADCgUICQABAAAAAA==.Bighead:BAAANQAECgMIAwABNQADCgUICQABAAAAAA==.Bigr:BAAANQADCgcICAAAAA==.Bigwarlocks:BAAANQADCggICAABNQADCgUICQABAAAAAA==.Biollante:BAAANQADCgYICAAAAA==.',
Bo='Bootyßandaid:BAAANQAECgUICgAAAA==.',
Bu='Buckis:BAAANQAECgUICwAAAA==.',
Ca='Camderags:BAAANQADCggICAAAAA==.Canon:BAAANQAECggIAgAAAA==.Catasucked:BAAANQADCgMIAwAAAA==.',
Ce='Celios:BAAANQAECgIIAgAAAA==.',
Ch='Chillin:BAAANQADCgEIAQAAAA==.Choggy:BAABNQAECn8mAAQGAAkKYRAuIQAqAgAGAAkKYRAuIQAqAgAHAAMKqRaCwgDPAAAIAAEKQQ0PKQAxAAAAAA==.Churro:BAAANQADCgcIBwAAAA==.',
Ci='Cindrõz:BAAANQAECgQIBAAAAA==.',
Co='Conception:BAAANQADCggIFAABNQAECgcIHQAHAF4XAA==.Cough:BAAANQADCgUICQAAAA==.',
Cr='Crinklecut:BAAANQAECgQIDAAAAA==.Crow:BAABNQAECn8hAAMJAAkKQiJpCgB4AwAJAAkKQiJpCgB4AwAKAAcKJBwUHQBFAgAAAA==.',
Da='Daijin:BAAANQAECgUIBQAAAA==.Danielallen:BAAANQAECgQICQAAAA==.Danyrogue:BAAANQAECgcIBwABNQAFFAcIDwALAGcaAA==.',
De='Deadlybeard:BAAANQADCgQICQABNQAECgcIJAAMAAkkAA==.Deadlywrath:BAABNQAECn8kAAIMAAcKCSTzJgDLAgAMAAcKCSTzJgDLAgAAAA==.Deadmenace:BAAANQADCgYJCwAAAA==.Decåying:BAABNQAECn8kAAINAAcKXwsLswBkAQANAAcKXwsLswBkAQAAAA==.Demonsangel:BAAANQAECgQIBAAAAA==.Deni:BAAANQAECgQIBQAAAA==.Denli:BAAANQADCgQIAgAAAA==.',
Di='Diagnosis:BAABNQAECn8VAAIOAAgKRCSCHwBEAwAOAAgKRCSCHwBEAwAAAA==.',
Do='Doctrine:BAAANQAECgIIAgAAAA==.Donnabb:BAAANQAECgQIEAAAAA==.Donteatbees:BAAANQAECgYICQAAAA==.Dop:BAAANQAECgQIBwAAAA==.Doran:BAAANQADCgUIBQAAAA==.Dottierotten:BAAANQAECgIIAgAAAA==.',
Dr='Drenrah:BAABNQAECn8fAAMMAAcK3g0piACAAQAMAAcK3g0piACAAQAOAAEKAAD4xAEiAAAAAA==.',
Ed='Edend:BAAANQADCgUICgAAAA==.',
Ei='Eiduartpaw:BAAANQAECgUICQAAAA==.',
El='Elbryan:BAAANQAECgQIBAAAAA==.Electracutie:BAAANQAECgcIDAAAAA==.Elementdemon:BAABNQAECn8kAAIPAAgK3xFQCQD2AQAPAAgK3xFQCQD2AQAAAA==.',
En='Enthalpy:BAABNQAECn8nAAIQAAkKNxgJYgC6AgAQAAkKNxgJYgC6AgAAAA==.',
Es='Esperzoa:BAAANQAECgQIDAAAAA==.',
Eu='Eucalicdes:BAABNQAECn8tAAIRAAkKcBY1DwBqAgARAAkKcBY1DwBqAgAAAA==.',
Ev='Evøkër:BAAANQADCgQIBAABNQAECggIEQABAAAAAA==.',
Ez='Ezra:BAAANQADCgUICgAAAA==.',
Fa='Falshin:BAAANQADCggICAAAAA==.Fancy:BAAANQADCggILAAAAA==.Fangyi:BAABNQAECn8kAAMSAAcKUhSBDwCuAQASAAcKUhSBDwCuAQAQAAcKjwqLEgFqAQAAAA==.',
Fi='Fiction:BAAANQAECggIDAAAAA==.',
Fl='Flabutt:BAAANQAECgUIBwAAAA==.Florita:BAAANQAECgEIAQAAAA==.',
Fo='Fordinn:BAABNQAECn8lAAQTAAcKKhvHGACgAQATAAYK1RjHGACgAQAUAAYKvxQpwQB0AQAVAAQKMhzUGQACAQAAAA==.',
Fr='Freeree:BAAANQADCgMIAwAAAA==.Fren:BAAANQAECgUIDQAAAA==.Fruitcakes:BAAANQAECgIIAgAAAA==.',
Fu='Furrypunch:BAAANQAECggIEQAAAA==.',
Ga='Gasket:BAABNQAECn8nAAMWAAkKRhx5OABBAgAWAAgKwBx5OABBAgAXAAcKhxa2QgCzAQAAAA==.',
Gh='Ghostdragona:BAAANQADCgcIBwAAAA==.Ghostown:BAAANQADCgQIBAAAAA==.',
Gr='Graceful:BAABNQAECn8iAAIYAAgKFg/GLwCUAQAYAAgKFg/GLwCUAQAAAA==.Grit:BAAANQAECgUICAAAAA==.Grëzel:BAAANQADCgYIBgABNQAECgQIBgABAAAAAA==.',
Ha='Handicap:BAAANQAECgEIAQABNQAECggIFQAOAEQkAA==.Hark:BAABNQAECn8mAAMLAAkKrhjaPgCsAgALAAkKrhjaPgCsAgAZAAEKYwgOigAzAAAAAA==.Harpin:BAABNQAECn8iAAIHAAgK1B2eMwCWAgAHAAgK1B2eMwCWAgAAAA==.Harvin:BAABNQAECn8aAAIaAAcKzh82EgCHAgAaAAcKzh82EgCHAgAAAA==.',
He='Heals:BAAANQAECggICAAAAA==.Heisenburgg:BAAANQADCggIDQABNQAECgQIBAABAAAAAA==.Helanua:BAAANQAECgYIEwAAAA==.',
Hi='Highlight:BAAANQAECgQICAAAAA==.Hippopotamus:BAAANQADCgIIAgAAAA==.Hit:BAAANQAECgQIBAAAAA==.Hitt:BAAANQADCgEIAQABNQAECgQIBAABAAAAAA==.',
Ho='Holyish:BAAANQAECgIIAgAAAA==.Holyrollers:BAAANQAECggIDwAAAA==.Holytide:BAAANQAECgYICgAAAA==.Hops:BAAANQADCgQIBAAAAA==.Hornsie:BAAANQADCgIIAgAAAA==.Horrorfang:BAABNQAECn8YAAIWAAcK8hyJNwBFAgAWAAcK8hyJNwBFAgAAAA==.',
['Hä']='Häwke:BAAANQADCgQIBwAAAA==.',
['Hü']='Hüntress:BAAANQADCgMIAwAAAA==.',
Ib='Ibaar:BAACNQAFFH8ZAAICAAcK3iNYAADGAgACAAcK3iNYAADGAgA1AAQKfyIAAgIACQrmIjsGACYDAAIACQrmIjsGACYDAAAA.',
Ic='Icialiaa:BAAANQADCgIIAgABNQAECgQIAwABAAAAAA==.',
In='Inno:BAABNQAECn8ZAAIbAAcK8SSMEQDeAgAbAAcK8SSMEQDeAgAAAA==.',
It='Ithacus:BAABNQAECn8eAAIcAAcK7hkHFAAlAgAcAAcK7hkHFAAlAgAAAA==.Itspriesty:BAAANQAECgEIAQAAAA==.',
Ja='Janari:BAAANQADCgcIDQAAAA==.Jandaar:BAAANQADCgYICQAAAA==.Jatt:BAAANQADCggICAAAAA==.Jattix:BAAANQADCgQIBAAAAA==.',
Jd='Jdawgprime:BAAANQABCgQIBAAAAA==.',
Ji='Jilkaeden:BAAANQAECgQICQAAAA==.',
Jo='Jorek:BAABNQAECn8kAAIUAAcKcQ+DtACUAQAUAAcKcQ+DtACUAQAAAA==.Josh:BAAANQAECgMIBQAAAA==.',
Jr='Jrue:BAAANQADCgcIBwAAAA==.',
Ju='Jurtkal:BAAANQAECgEIAQAAAA==.',
Ka='Kaiva:BAAANQAECgQICQAAAA==.Kavik:BAAANQAECgIIAgAAAA==.',
Ke='Keflá:BAAANQAECgQIBwAAAA==.Keineliebe:BAAANQAECgIIAgAAAA==.Kelencye:BAAANQAECgMIBwAAAA==.',
Kh='Khaas:BAAANQAECgYIEQAAAA==.Khanloa:BAAANQADCgUIBQAAAA==.Kheleze:BAAANQAECgQIBAABNQAECgUIEAABAAAAAA==.',
Ki='Killerbell:BAAANQAECgEIAwAAAA==.Killshot:BAAANQADCgcICQAAAA==.',
Ko='Korihor:BAAANQAECgQIDgAAAA==.',
Kr='Krestus:BAAANQAECgYIEAAAAA==.Krispy:BAAANQAECgYIDAAAAA==.Krispyy:BAAANQAECgUIBQAAAA==.Krix:BAAANQAECgUIBAAAAA==.',
Ku='Kuroji:BAAANQABCgEIAQAAAA==.',
La='Laerin:BAAANQAECgYICAAAAA==.Landreielea:BAAANQAECgYIEgAAAA==.Laxus:BAAANQAECgYIDgAAAA==.',
Le='Lerenor:BAAANQAECgQIBgAAAA==.Levophed:BAAANQAECgUJCAAAAA==.',
Li='Lily:BAABNQAECn8YAAIRAAcKRBD5IQCCAQARAAcKRBD5IQCCAQAAAA==.Linnt:BAAANQAECgEIAQAAAA==.Liyara:BAABNQAECn8mAAIOAAkKjiN7GABgAwAOAAkKjiN7GABgAwAAAA==.',
Ll='Llorsa:BAABNQAECn8ZAAIHAAcKdweumQBDAQAHAAcKdweumQBDAQAAAA==.Lltoj:BAAANQADCgEIAQAAAA==.',
Lu='Lusavahza:BAAANQADCgUIBgAAAA==.Luxian:BAAANQADCgYIDAAAAA==.',
['Lä']='Ländrei:BAAANQAECgIIAgABNQAECgYIEgABAAAAAA==.',
Ma='Macy:BAAANQABCgIIAgAAAA==.Mahralla:BAAANQADCgUIBQAAAA==.Maikagond:BAAANQADCgYIBgABNQAECgcIIwAOAD0NAA==.Makaria:BAAANQAECgQICwAAAA==.Malbisa:BAAANQAECgUIBQAAAA==.Malphoz:BAAANQADCgUIBQAAAA==.Mandragora:BAAANQAECgIIAgAAAA==.Marli:BAAANQADCgIIAgAAAA==.',
Mi='Mickey:BAABNQAECn8aAAIYAAkKvhtYGgBpAgAYAAkKvhtYGgBpAgAAAA==.Mikiik:BAAANQAECgUIEwAAAA==.Mikk:BAAANQADCgIJAgAAAA==.Mildoo:BAABNQAECn8eAAIdAAcKIxCYCwCtAQAdAAcKIxCYCwCtAQAAAA==.Milkymoo:BAAANQAECgQIBwABNQAFFAcIIQAHALYWAA==.',
Mo='Monq:BAAANQAECgcICwAAAA==.Moón:BAABNQAECn8aAAIeAAcKnw9sFQChAQAeAAcKnw9sFQChAQAAAA==.',
My='Mythlocked:BAAANQAECgEIAQAAAA==.',
['Mî']='Mîlk:BAAANQADCgIIAgAAAA==.',
Na='Naomii:BAAANQADCgIIAgAAAA==.Narus:BAAANQAECgYICgABNQAECgcIJQATACobAA==.',
Ne='Nephadin:BAAANQADCggICAABNQAECggIIwAfAD4eAA==.Neviaa:BAABNQAECn8ZAAMWAAcKoxh7QwAJAgAWAAcKoxh7QwAJAgAgAAEKAAANywAwAAAAAA==.',
Ni='Nickypoo:BAAANQADCgYICQAAAA==.Nightmenace:BAAANQAECgQIBgAAAA==.Niq:BAAANQAECgEIAQAAAA==.',
No='Norii:BAAANQADCgMIAwABNQAECgQICgABAAAAAA==.Nothealster:BAABNQAECn8ZAAIGAAcKAgmSPABCAQAGAAcKAgmSPABCAQAAAA==.Novacane:BAAANQAECgEIAgAAAA==.',
Ob='Obitrice:BAAANQAECgYIEwABNQAECgQIDQABAAAAAA==.Obsidiian:BAAANQAECgUICQAAAA==.Obsidion:BAAANQAECgcIDgABNQAECgcIJQATACobAA==.',
Od='Odie:BAAANQAECgIIAgAAAA==.',
Or='Organdonor:BAABNQAECn8cAAIHAAgKcxPGYQD3AQAHAAgKcxPGYQD3AQAAAA==.',
Os='Ossin:BAAANQAECgIIAwAAAA==.',
Pa='Pantherlilly:BAAANQAECgEIAQAAAA==.',
Pe='Perry:BAAANQAECgUICAAAAA==.',
Ph='Phlampped:BAAANQADCgYIBgABNQAFFAUICQAOAOIcAA==.',
Po='Pozufuma:BAABNQAECn8ZAAIVAAcKaxcuDAD4AQAVAAcKaxcuDAD4AQAAAA==.',
Ps='Psychomantis:BAABNQAECn8nAAMGAAgKORSDLQC1AQAGAAcKIRKDLQC1AQAHAAcKLwoZkQBeAQAAAA==.',
Ra='Radium:BAAANQADCgcICAAAAA==.Ravenbear:BAAANQAECgUIEAAAAA==.',
Re='Redpool:BAAANQAECgUIEwAAAA==.Rethandra:BAAANQADCgEIAQAAAA==.Retrix:BAAANQAECgQICAAAAA==.Revorra:BAAANQAECgUIEAABNQAECgcIJQATACobAA==.Rezelflezel:BAAANQAECgUIBQAAAA==.',
Ri='Ristvakbaen:BAABNQAECn8lAAQhAAgK0yDrGwCNAQANAAcKWxz5WABIAgAhAAQKACPrGwCNAQAdAAEKxRKbKQBFAAAAAA==.',
Ro='Robynlee:BAABNQAECn8dAAIHAAcKXhdKZwDlAQAHAAcKXhdKZwDlAQAAAA==.Rohini:BAAANQADCgQIBgAAAA==.Rovik:BAAANQAECgQIBwAAAA==.',
Sc='Sceryna:BAABNQAECn8dAAMOAAgKRB6DYAB0AgAOAAgKRB6DYAB0AgAfAAIKtBdSXQBhAAAAAA==.Schiftly:BAAANQADCgQIBAAAAA==.Scrmndemn:BAAANQAECgcIEwAAAA==.',
Se='Sef:BAAANQAECgUICwAAAA==.Serpent:BAAANQAFFAIIAgABNQAFFAUIDwAgAL8OAA==.',
Sh='Shamadeus:BAAANQAECgQIBAABNQAECggIJQAhANMgAA==.Shamtastical:BAAANQAECgUIEAABNQAECgcIHQAHAF4XAA==.Shikita:BAABNQAECn8aAAIKAAcKaR63GgBfAgAKAAcKaR63GgBfAgAAAA==.Shimadin:BAACNQAFFH8QAAIOAAQKNxaEEAA9AQAOAAQKNxaEEAA9AQA1AAQKfyoAAg4ACQoLIjFBAM4CAA4ACQoLIjFBAM4CAAAA.Shimjun:BAAANQAECgYIBgABNQAFFAQIEAAOADcWAA==.Shimsong:BAAANQADCggIDQABNQAFFAQIEAAOADcWAA==.Shirma:BAAANQABCgIIAgAAAA==.Shmerek:BAABNQAECn8kAAITAAcKrBuBEQAMAgATAAcKrBuBEQAMAgAAAA==.',
Si='Sierramist:BAABNQAECn8iAAIiAAcKWRz5FAAoAgAiAAcKWRz5FAAoAgAAAA==.Silverpacem:BAAANQAECgQIBAAAAA==.Silverstream:BAABNQAECn8oAAIKAAkKfRllFACjAgAKAAkKfRllFACjAgAAAA==.',
So='Solbin:BAABNQAECn8dAAIjAAgKnCKyAwAgAwAjAAgKnCKyAwAgAwABNQAECgkJKwAQADYgAA==.Solexine:BAAANQADCgQIBAAAAA==.Solitudé:BAAANQAECgQICgABNQAECgkJJgAXAAAjAA==.Soteirian:BAABNQAECn8jAAMOAAcKPQ0WyQCDAQAOAAcKPQ0WyQCDAQAfAAEKAAB1dgAlAAAAAA==.',
Sp='Spiritlinkin:BAABNQAECn8VAAIDAAcKRBjTYwDyAQADAAcKRBjTYwDyAQAAAA==.',
St='Stalariais:BAAANQADCgYIBgABNQAECggIDgABAAAAAA==.Steakhammer:BAAANQADCgMIBAABNQAECggIEQABAAAAAA==.Steve:BAAANQAECgUIEQAAAA==.',
Su='Sugardawn:BAAANQAECgQIBAAAAA==.Sugarkitty:BAAANQADCgcIBwAAAA==.Supereclipse:BAABNQAECn8YAAILAAcKSw4okADlAQALAAcKSw4okADlAQAAAA==.',
Sy='Sydvicious:BAABNQAECn8dAAIFAAgKYSB7EQAQAwAFAAgKYSB7EQAQAwAAAA==.',
Ta='Taintedwater:BAAANQAECgQIAwAAAA==.Tairnanach:BAAANQADCgYIDgAAAA==.Taladiir:BAAANQAECgMIBAAAAA==.Tayger:BAAANQADCgcJEAAAAA==.',
Td='Tdog:BAAANQADCgcIDgAAAA==.',
Te='Tecks:BAABNQAECn8kAAIHAAcKLgpIkQBdAQAHAAcKLgpIkQBdAQAAAA==.Teslá:BAAANQAECgEIAQAAAA==.',
Th='Thaldur:BAAANQAECgEIAQABNQAECgYIEAABAAAAAA==.Thayo:BAAANQAECgEIAQAAAA==.Theatrix:BAAANQAECgMIBAABNQAECgcIEwABAAAAAA==.Themajor:BAAANQAECgQIBAAAAA==.Therossyas:BAAANQAECgQIBwAAAA==.Thezuggest:BAAANQADCgMJAwAAAA==.Thicctotems:BAACNQAFFH8QAAMEAAQK3iDvDAB5AQAEAAQK3iDvDAB5AQADAAEKCQT2MwA/AAA1AAQKfyUAAwQACArwIS42AIQCAAQACArwIS42AIQCAAMAAgoRFKD/AIkAAAAA.Threat:BAABNQAECn8nAAIOAAkKZSQXCwClAwAOAAkKZSQXCwClAwAAAA==.Thunderthigh:BAAANQADCgYIAwAAAA==.Thungerthi:BAAANQADCgUICAAAAA==.',
Ti='Tiamaat:BAABNQAECn8kAAMJAAcKRAaCagAdAQAJAAcKRAaCagAdAQAKAAEK6QFpeAApAAAAAA==.Tinysanta:BAAANQAECgIIBAAAAA==.Titus:BAAANQADCgYICQAAAA==.',
To='Toatani:BAAANQADCgMJAwABNQAECgQICQABAAAAAA==.Torvar:BAAANQADCggIDwAAAA==.',
Ty='Tyletos:BAABNQAECn8rAAMQAAkKNiA7IABZAwAQAAkK9B87IABZAwASAAUKXR34EQCEAQAAAA==.',
Ug='Ugolok:BAAANQADCgcIDQAAAA==.',
Ur='Uriél:BAAANQADCgQIBAABNQAECgkJJgAXAAAjAA==.Urubaen:BAAANQAECgYIBgABNQAECggIJQAhANMgAA==.',
Va='Valanoth:BAAANQADCgIIAgAAAA==.Valeene:BAABNQAECn8gAAIJAAgK/SDwGQD3AgAJAAgK/SDwGQD3AgAAAA==.',
Ve='Veiler:BAABNQAECn8nAAMZAAkKSwtwQwA3AQALAAYKcgxvwgB4AQAZAAcK+gRwQwA3AQAAAA==.Veruca:BAAANQAECgUIBgAAAA==.Veviseron:BAABNQAECn8jAAISAAcKsgYjGgAhAQASAAcKsgYjGgAhAQAAAA==.',
Vi='Vinstalation:BAAANQAECgQIBwAAAA==.',
Vo='Vonbismarck:BAABNQAECn8dAAMZAAcKwgh1RgAiAQAZAAYKmAl1RgAiAQALAAIKbAV3OwFjAAAAAA==.',
Vr='Vritraz:BAABNQAECn8mAAIXAAkKACM2CgBIAwAXAAkKACM2CgBIAwAAAA==.',
Wa='Warsonge:BAAANQAECgUICQAAAA==.',
We='Wendypini:BAABNQAECn8sAAILAAkKoxapSQCOAgALAAkKoxapSQCOAgAAAA==.',
Wh='Whitlock:BAAANQAECgIIAwAAAA==.',
Xe='Xendria:BAAANQADCggICgAAAA==.',
Ya='Yannhal:BAAANQAECgIIAgAAAA==.',
Za='Zangelf:BAAANQABCggIFAAAAA==.Zangolf:BAAANQABCggIDQAAAA==.',
Zo='Zodiaac:BAABNQAECn8kAAIgAAcKkRtiNwApAgAgAAcKkRtiNwApAgAAAA==.',
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
