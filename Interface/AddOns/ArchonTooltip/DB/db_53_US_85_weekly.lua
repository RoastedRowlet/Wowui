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

local lookup = {'Warrior-Arms','Hunter-BeastMastery','Unknown-Unknown','Paladin-Retribution','Evoker-Devastation','Shaman-Elemental','Shaman-Restoration','Warrior-Fury','DemonHunter-Havoc','Priest-Shadow','Priest-Holy','Priest-Discipline','Rogue-Assassination','Rogue-Subtlety','Druid-Balance','Druid-Restoration','Paladin-Holy','Warlock-Demonology','Rogue-Outlaw','Mage-Arcane','Druid-Guardian','Monk-Mistweaver','Mage-Frost','Warrior-Protection','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Frost','Hunter-Marksmanship','Evoker-Preservation','DemonHunter-Devourer','Shaman-Enhancement','DemonHunter-Vengeance','Warlock-Destruction','Warlock-Affliction','Druid-Feral','Paladin-Protection','DeathKnight-Blood',}
local provider = {region='US',realm='Eitrigg',name='US',type='weekly',zone=53,date='2026-10-20',data={Al='Alys:BAAANQAECgYICQAAAA==.',
Am='Amaniatres:BAABNQAECn8VAAIBAAgKbBVvlQDmAQABAAgKbBVvlQDmAQAAAA==.Ammartin:BAABNQAECn8UAAICAAYKdAnmzQBlAQACAAYKdAnmzQBlAQAAAA==.Amperage:BAAANQADCgUIEAABNQAECggIFQABAGwVAA==.',
An='Anaan:BAAANQAECgYICwAAAA==.Anahera:BAAANQADCgcIBwABNQAECgQICQADAAAAAA==.Anthion:BAAANQABCgIIAgAAAA==.Anzhelina:BAABNQAECn8UAAIEAAoKoxm8UQCgAgAEAAoKoxm8UQCgAgAAAA==.',
Ap='Apis:BAAANQAECgIIAgAAAA==.Apostasy:BAAANQABCgUIAwAAAA==.Aprys:BAAANQABCggIEQAAAA==.',
Ar='Arihana:BAABNQAECn8VAAIFAAYK6AbaJgD+AAAFAAYK6AbaJgD+AAAAAA==.',
As='Asapshocky:BAACNQAFFH8KAAIGAAUKKBOjEgBFAQAGAAUKKBOjEgBFAQA1AAQKfycAAgYACgodG6QHAO0BAAYACgodG6QHAO0BAAAA.Asmoday:BAAANQADCggIIAAAAA==.',
Ba='Baahp:BAAANQAECgUICQABNQAECgkJJwAHACQTAA==.Barley:BAAANQABCgIIAgAAAA==.',
Be='Belassandra:BAAANQADCgUIBQAAAA==.Belgerra:BAABNQAECn8UAAMIAAcKDxc3EACjAQAIAAYKwRQ3EACjAQABAAYKVBIA0ABTAQAAAA==.Bellabelle:BAAANQADCgcIDQAAAA==.Bevian:BAAANQADCgMIAwAAAA==.',
Bi='Biggiepants:BAABNQAECn8nAAIJAAkKNxYtBwDVAQAJAAkKNxYtBwDVAQAAAA==.Biggnome:BAAANQADCgYIBgABNQADCgUICQADAAAAAA==.Bighead:BAAANQAECgMIAwABNQADCgUICQADAAAAAA==.Bigr:BAAANQADCgcICAAAAA==.Bigwarlocks:BAAANQADCggICAABNQADCgUICQADAAAAAA==.Biollante:BAAANQADCgYICAAAAA==.',
Bo='Bootyßandaid:BAAANQAECgUICgAAAA==.',
Bu='Buckis:BAAANQAECgYIDwAAAA==.',
Ca='Camderags:BAAANQADCggICAAAAA==.Canon:BAAANQAECggIBAAAAA==.Catasucked:BAAANQADCgMIAwAAAA==.',
Ce='Celios:BAAANQAECgIIAgAAAA==.',
Ch='Chillin:BAAANQADCgEIAQAAAA==.Choggy:BAABNQAECn8sAAQKAAoKPxGCIQAqAgAKAAkKYRCCIQAqAgALAAUKrBM0TwDcAAAMAAEKQQ2QKQAxAAAAAA==.Churro:BAAANQADCgcIBwAAAA==.',
Ci='Cindrõz:BAAANQAECgQIBAAAAA==.',
Co='Conception:BAAANQAECgUIBQABNQAECggIEAADAAAAAA==.Cough:BAAANQADCgUICQAAAA==.',
Cr='Crinklecut:BAABNQAECn8UAAMNAAYKFwg6OABsAAAOAAUKsweuNgAEAQANAAMKPgg6OABsAAAAAA==.Crow:BAABNQAECn8pAAMPAAoKoyKHCgB4AwAPAAkKlyKHCgB4AwAQAAkKMx79CQCXAQAAAA==.',
Da='Daijin:BAAANQAECgYICgAAAA==.Danielallen:BAAANQAECgQICQAAAA==.Danyrogue:BAAANQAECgcIBwABNQAFFAcIDwACAGcaAA==.',
De='Deadlybeard:BAAANQADCgQICQABNQAECggIKgARAHEkAA==.Deadlywrath:BAABNQAECn8qAAIRAAgKcSTVCQAlAgARAAgKcSTVCQAlAgAAAA==.Deadmenace:BAAANQADCgYJCwAAAA==.Decåying:BAABNQAECn8qAAISAAgKCworQgAIAQASAAgKCworQgAIAQAAAA==.Demonsangel:BAAANQAECgUIBAAAAA==.Deni:BAAANQAECgQICQAAAA==.Denli:BAAANQADCgQIAgAAAA==.',
Di='Diagnosis:BAABNQAECn8WAAIEAAgKRCQ6IABDAwAEAAgKRCQ6IABDAwAAAA==.',
Do='Doctrine:BAAANQAECgIIAgAAAA==.Donnabb:BAAANQAECgYIEgAAAA==.Donteatbees:BAAANQAECgYICgAAAA==.Dop:BAAANQAECgQIBwAAAA==.Doran:BAAANQADCgUIBQAAAA==.Dottierotten:BAAANQAECgIIAgAAAA==.',
Dr='Drenrah:BAABNQAECn8hAAMRAAgKbg1riQCAAQARAAgKbg1riQCAAQAEAAEKAAByywEiAAAAAA==.',
Ed='Edend:BAAANQADCgUICgAAAA==.',
Ei='Eiduartpaw:BAAANQAECgYIDAAAAA==.',
El='Elbryan:BAAANQAECgQICAAAAA==.Electracutie:BAAANQAECggIEgAAAA==.Elementdemon:BAABNQAECn8pAAITAAgKdBJgCQD2AQATAAgKdBJgCQD2AQAAAA==.',
En='Enthalpy:BAABNQAECn8uAAIUAAoK+Rh5EgDSAQAUAAoK+Rh5EgDSAQAAAA==.',
Es='Esperzoa:BAAANQAECgUIDAAAAA==.',
Eu='Eucalicdes:BAABNQAECn8zAAIVAAoKhhZ1DwBrAgAVAAoKhhZ1DwBrAgAAAA==.',
Ev='Evøkër:BAAANQADCgQIBAABNQAECgkJGwAWAGEcAA==.',
Ez='Ezra:BAAANQADCgcIDQAAAA==.',
Fa='Falshin:BAAANQADCggICAAAAA==.Fancy:BAAANQAECgEIAQAAAA==.Fangyi:BAABNQAECn8qAAMXAAgKIRKuDwCtAQAXAAgKIRKuDwCtAQAUAAcKjwo6FQFpAQAAAA==.',
Fi='Fiction:BAAANQAECggIDAAAAA==.',
Fl='Flabutt:BAAANQAECgUIBwAAAA==.Florita:BAAANQAECgEIAQAAAA==.',
Fo='Fordinn:BAABNQAECn8rAAQYAAcKKhvMDADjAAABAAYKvxRWwwB0AQAIAAQKMhwJGgACAQAYAAcKiBXMDADjAAAAAA==.',
Fr='Freeree:BAAANQADCgMIAwAAAA==.Fren:BAAANQAECgYIDgAAAA==.Fruitcakes:BAAANQAECgIIAgAAAA==.',
Fu='Furrypunch:BAABNQAECn8bAAMWAAkKYRzZCwDGAgAWAAkKYRzZCwDGAgAZAAEKJgErPQAYAAAAAA==.',
Ga='Gasket:BAABNQAECn8rAAMaAAoKIxoIOQBBAgAaAAgKwBwIOQBBAgAbAAgKohTwHgArAQAAAA==.',
Gh='Ghostdragona:BAAANQADCgcIBwAAAA==.Ghostown:BAAANQADCgQIBAAAAA==.',
Gr='Graceful:BAABNQAECn8nAAIZAAgKFg9TMACUAQAZAAgKFg9TMACUAQAAAA==.Grenie:BAAANQADCgMIAwAAAA==.Grit:BAAANQAECgUICAAAAA==.Grëzel:BAAANQADCgYIBgABNQAECgQIBgADAAAAAA==.',
Ha='Handicap:BAAANQAECgEIAQABNQAECggIFgAEAEQkAA==.Hark:BAABNQAECn8qAAMCAAoKVhjUPwCrAgACAAoKVhjUPwCrAgAcAAEKYwj4iwAzAAAAAA==.Harpin:BAABNQAECn8mAAILAAoKsh18NACWAgALAAoKsh18NACWAgAAAA==.Harvin:BAABNQAECn8iAAIdAAgKUB63AQBcAgAdAAgKUB63AQBcAgAAAA==.',
He='Heals:BAAANQAECggICAAAAA==.Heisenburgg:BAAANQADCggIDQABNQAECgYIBQADAAAAAA==.Helanua:BAABNQAECn8fAAIGAAcKsw5KMAD9AAAGAAcKsw5KMAD9AAAAAA==.',
Hi='Highlight:BAAANQAECgUIDQAAAA==.Hippopotamus:BAAANQADCgIIAgAAAA==.Hit:BAAANQAECgYIBQAAAA==.Hitt:BAAANQADCgEIAQABNQAECgYIBQADAAAAAA==.',
Ho='Holyish:BAAANQAECgIIAgAAAA==.Holyrollers:BAABNQAECn8XAAILAAkKIAniLgBCAQALAAkKIAniLgBCAQAAAA==.Holytide:BAAANQAECgcIDwAAAA==.Hops:BAAANQADCgQIBAAAAA==.Hornsie:BAAANQADCgIIAgAAAA==.Horrorfang:BAABNQAECn8eAAIaAAcK8hwpOABFAgAaAAcK8hwpOABFAgAAAA==.',
['Hä']='Häwke:BAAANQADCgQIBwAAAA==.',
Ib='Ibaar:BAACNQAFFH8ZAAIFAAcK3iNeAADFAgAFAAcK3iNeAADFAgA1AAQKfyQAAgUACgoXI1oGACUDAAUACgoXI1oGACUDAAAA.',
Ic='Icialiaa:BAAANQADCgIIAgABNQAECgQIAwADAAAAAA==.',
In='Inno:BAABNQAECn8cAAIeAAkK2yHgEQDdAgAeAAkK2yHgEQDdAgAAAA==.',
It='Ithacus:BAABNQAECn8kAAIfAAgKZxdSFAAjAgAfAAgKZxdSFAAjAgAAAA==.Itspriesty:BAAANQAECgEIAQAAAA==.',
Ja='Janari:BAAANQADCgcIDQAAAA==.Jandaar:BAAANQADCgYICQAAAA==.Jatt:BAAANQADCggICAAAAA==.Jattix:BAAANQADCgQIBAAAAA==.',
Jd='Jdawgprime:BAAANQABCgQIBAAAAA==.',
Ji='Jilkaeden:BAAANQAECgcIDwAAAA==.',
Jo='Jorek:BAABNQAECn8qAAIBAAgKdQ2ORgAUAQABAAgKdQ2ORgAUAQAAAA==.Josh:BAAANQAECgMICAAAAA==.',
Jr='Jrue:BAAANQADCgcIBwAAAA==.',
Ju='Jurtkal:BAAANQAECgEIAQAAAA==.',
Ka='Kaiva:BAAANQAECgQICQAAAA==.Kavik:BAAANQAECgIIAgAAAA==.',
Ke='Keflá:BAAANQAECgQIBwAAAA==.Keineliebe:BAAANQAECgIIAgAAAA==.Kelencye:BAAANQAECgMICQAAAA==.',
Kh='Khaas:BAABNQAECn8aAAIaAAcKZwopJADWAAAaAAcKZwopJADWAAAAAA==.Khanloa:BAAANQADCgUIBQAAAA==.Kheleze:BAAANQAECgUICAAAAA==.',
Ki='Killerbell:BAAANQAECgEIAwAAAA==.Killshot:BAAANQADCgcICQAAAA==.',
Ko='Korihor:BAAANQAECgUIDgAAAA==.',
Kr='Krestus:BAABNQAECn8XAAMgAAkKtR/JDgDMAQAeAAkKohs2IABMAgAgAAcKKR/JDgDMAQAAAA==.Krispy:BAAANQAECgYIDAAAAA==.Krispyy:BAAANQAECgcICgAAAA==.Krix:BAAANQAECgYICAAAAA==.',
Ku='Kuroji:BAAANQABCgEIAQAAAA==.',
La='Laerin:BAAANQAECgYICAAAAA==.Landreielea:BAABNQAECn8YAAICAAgKnQwUmADYAQACAAgKnQwUmADYAQAAAA==.Laxus:BAAANQAECgYIDgAAAA==.',
Le='Lerenor:BAAANQAECgQIBgAAAA==.Levophed:BAAANQAECgUJCAAAAA==.',
Li='Lily:BAABNQAECn8YAAIVAAcKRBCRIgCDAQAVAAcKRBCRIgCDAQAAAA==.Linnt:BAAANQAECgIIAQAAAA==.Liyara:BAABNQAECn8rAAIEAAoKzCEtGQBfAwAEAAoKzCEtGQBfAwAAAA==.',
Ll='Llorsa:BAABNQAECn8fAAILAAcKawqWNAAtAQALAAcKawqWNAAtAQAAAA==.Lltoj:BAAANQADCgEIAQAAAA==.',
Lu='Lusavahza:BAAANQADCgUIBgAAAA==.Luxian:BAAANQADCggIFAAAAA==.',
['Lä']='Ländrei:BAAANQAECgIIAgABNQAECggIGAACAJ0MAA==.',
Ma='Macy:BAAANQABCgIIAgAAAA==.Mahralla:BAAANQADCgUIBQAAAA==.Maikagond:BAAANQADCgYIBgABNQAECggIKQAEAKwMAA==.Makaria:BAAANQAECgUIDQAAAA==.Malbisa:BAAANQAECgUIBwAAAA==.Malphoz:BAAANQADCgUIBQAAAA==.Mandragora:BAAANQAECgIIAgAAAA==.Marli:BAAANQADCgIIAgAAAA==.',
Mc='Mcsorley:BAAANQADCgMIAwAAAA==.',
Mi='Mickey:BAABNQAECn8aAAIZAAkKvhuxGgBpAgAZAAkKvhuxGgBpAgAAAA==.Mikiik:BAABNQAECn8dAAMhAAYKTAUrSgChAAASAAQKBgVpFAGhAAAhAAUKwwUrSgChAAAAAA==.Mikk:BAAANQADCgIJAgAAAA==.Mildoo:BAABNQAECn8eAAIiAAcKIxCpCwCtAQAiAAcKIxCpCwCtAQAAAA==.Milkymoo:BAAANQAECgQIBwABNQAFFAcIIgALALYWAA==.',
Mo='Monq:BAAANQAECgcIDAAAAA==.Moón:BAABNQAECn8fAAIjAAgKsg/IFQCfAQAjAAgKsg/IFQCfAQAAAA==.',
My='Mythlocked:BAAANQAECgIIAQAAAA==.',
['Mî']='Mîlk:BAAANQADCgIIAgAAAA==.',
Na='Naomii:BAAANQADCgIIAgAAAA==.Narus:BAAANQAECgYICwABNQAECgcIKwAYACobAA==.',
Ne='Nephadin:BAAANQADCggICAABNQAECgkJJwAkADUeAA==.Neviaa:BAABNQAECn8fAAMaAAcKoxhJRAAJAgAaAAcKoxhJRAAJAgAlAAYKtg25IwDoAAAAAA==.',
Ni='Nickypoo:BAAANQADCgYICQAAAA==.Nightmenace:BAAANQAECgQIBgAAAA==.Niq:BAAANQAECgEIAQAAAA==.',
No='Norii:BAAANQADCgMIAwABNQADCgMIAwADAAAAAA==.Nothealster:BAABNQAECn8ZAAIKAAcKAgkiPQBCAQAKAAcKAgkiPQBCAQAAAA==.Novacane:BAAANQAECgEIAgAAAA==.',
Ob='Obitrice:BAABNQAECn8VAAICAAcKcxK6nADNAQACAAcKcxK6nADNAQABNQAECgYIFQAVAKwVAA==.Obsidiian:BAAANQAECgUICQAAAA==.Obsidion:BAABNQAECn8SAAMLAAcKOgjMpgAhAQALAAYKiQjMpgAhAQAKAAUKCgllHACnAAABNQAECgcIKwAYACobAA==.',
Od='Odie:BAAANQAECgIIAgAAAA==.',
Or='Organdonor:BAABNQAECn8cAAILAAgKcxMMYwD3AQALAAgKcxMMYwD3AQAAAA==.',
Os='Ossin:BAAANQAECgIIAwAAAA==.',
Pa='Pantherlilly:BAAANQAECgMIBAAAAA==.',
Pe='Perry:BAAANQAECgUICAAAAA==.',
Ph='Phlampped:BAAANQADCgYIBgABNQAFFAUIBgABABQKAA==.',
Po='Pozufuma:BAABNQAECn8fAAIIAAcKFBhIDAD4AQAIAAcKFBhIDAD4AQAAAA==.',
Ps='Psychomantis:BAABNQAECn8qAAMKAAkKIxP6LQC1AQAKAAgKoBD6LQC1AQALAAcKkQvEkgBeAQAAAA==.',
Ra='Radium:BAAANQADCgcICAAAAA==.Ravenbear:BAAANQAECgUIEAAAAA==.',
Re='Redpool:BAABNQAECn8YAAICAAYK6glQ2gBMAQACAAYK6glQ2gBMAQAAAA==.Rethandra:BAAANQADCgEIAQAAAA==.Retrix:BAAANQAECgQICAAAAA==.Revorra:BAAANQAECgUIEAABNQAECgcIKwAYACobAA==.Rezelflezel:BAAANQAECgUIBQAAAA==.',
Ri='Ristvakbaen:BAABNQAECn8sAAQhAAkKBiGEAAAcAgASAAcKWxyFWgBHAgAhAAgK/h+EAAAcAgAiAAEKxRICKgBFAAAAAA==.',
Ro='Robynlee:BAABNQAECn8eAAILAAcKXhepaADlAQALAAcKXhepaADlAQABNQAECggIEAADAAAAAA==.Rohini:BAAANQADCgQIBgAAAA==.Rovik:BAAANQAECgQIBwAAAA==.',
Sc='Sceryna:BAABNQAECn8hAAMEAAoKvRiHYgBzAgAEAAoKvRiHYgBzAgAkAAIKtReBXgBhAAAAAA==.Schiftly:BAAANQADCgQIBAAAAA==.Scrmndemn:BAABNQAECn8YAAIEAAgKHwR/CQEPAQAEAAgKHwR/CQEPAQAAAA==.',
Se='Sef:BAAANQAECgUICwAAAA==.Serpent:BAAANQAFFAMIBAABNQAFFAUIEQAlAL8OAA==.',
Sh='Shamadeus:BAAANQAECgQIBQABNQAECgkJLAAhAAYhAA==.Shamtastical:BAAANQAECggIEAAAAA==.Shikita:BAABNQAECn8fAAIQAAcKaR62DABvAQAQAAcKaR62DABvAQAAAA==.Shimadin:BAACNQAFFH8RAAIEAAUKfxIIEQA9AQAEAAUKfxIIEQA9AQA1AAQKfy8AAgQACgq1IUUmAI0BAAQACgq1IUUmAI0BAAAA.Shimjun:BAAANQAECgYIBgABNQAFFAUIEQAEAH8SAA==.Shimsong:BAAANQADCggIDQABNQAFFAUIEQAEAH8SAA==.Shirma:BAAANQABCgIIAgAAAA==.Shmerek:BAABNQAECn8qAAIYAAgKxhi3BwA8AQAYAAgKxhi3BwA8AQAAAA==.',
Si='Sierramist:BAABNQAECn8pAAIWAAcK2ByZAwDwAQAWAAcK2ByZAwDwAQAAAA==.Silverpacem:BAAANQAECgQIBAAAAA==.Silverstream:BAABNQAECn8sAAIQAAoKcxeeFACjAgAQAAoKcxeeFACjAgAAAA==.',
So='Solbin:BAABNQAECn8gAAIgAAgKnCLCAwAgAwAgAAgKnCLCAwAgAwABNQAECgoKLQAUAKEfAA==.Solexine:BAAANQADCgQIBAAAAA==.Solitudé:BAAANQAECgQICgABNQAECgoKKgAbAG0gAA==.Soteirian:BAABNQAECn8pAAMEAAgKrAznWgAPAQAEAAgKrAznWgAPAQAkAAEKAADVdwAlAAAAAA==.',
Sp='Spiritlinkin:BAABNQAECn8bAAIGAAkKHhT9KQAVAQAGAAkKHhT9KQAVAQAAAA==.',
St='Stalariais:BAAANQADCgYIBgABNQAECggIDgADAAAAAA==.Steakhammer:BAAANQAECgQIBAABNQAECgkJGwAWAGEcAA==.Steve:BAABNQAECn8WAAIBAAYKCQ3kzABbAQABAAYKCQ3kzABbAQAAAA==.Straw:BAAANQABCgIIAgABNQAECgoKIAAEAF4OAA==.',
Su='Sugardawn:BAAANQAECgQIBAAAAA==.Sugarkitty:BAAANQADCgcIBwAAAA==.Supereclipse:BAABNQAECn8eAAICAAcKjBCoSgAeAQACAAcKjBCoSgAeAQAAAA==.',
Sy='Sydvicious:BAABNQAECn8gAAIJAAkKriDvEQAPAwAJAAkKriDvEQAPAwAAAA==.',
Ta='Taintedwater:BAAANQAECgQIAwAAAA==.Tairnanach:BAAANQADCgYIDgAAAA==.Taladiir:BAAANQAECgQIBQAAAA==.Talana:BAAANQAECgQIBQAAAA==.Tayger:BAAANQADCgcJEAAAAA==.',
Td='Tdog:BAAANQADCgcIDgAAAA==.',
Te='Tecks:BAABNQAECn8qAAILAAgKrAyLLABKAQALAAgKrAyLLABKAQAAAA==.Teslá:BAAANQAECgEIAQAAAA==.',
Th='Thaldur:BAAANQAECgEIAQABNQAECgkJFwAgALUfAA==.Thayo:BAAANQAECgEIAQAAAA==.Theatrix:BAAANQAECgMIBAABNQAECggIFQABAGwVAA==.Themajor:BAAANQAECgQIBQAAAA==.Therossyas:BAAANQAECgQICwAAAA==.Thezuggest:BAAANQADCgMJAwAAAA==.Thicctotems:BAACNQAFFH8QAAMHAAQK3iBKDQB5AQAHAAQK3iBKDQB5AQAGAAEKCQTbNAA/AAA1AAQKfycAAwcACArwIdc2AIMCAAcACArwIdc2AIMCAAYAAgoRFA0DAYkAAAAA.Threat:BAABNQAECn8tAAIEAAkKZSRuCwCkAwAEAAkKZSRuCwCkAwAAAA==.Thunderthigh:BAAANQADCgYIAwAAAA==.Thungerthi:BAAANQADCgUICAAAAA==.',
Ti='Tiamaat:BAABNQAECn8qAAMPAAgKhAXFKADBAAAPAAgKhAXFKADBAAAQAAEK6QFnegApAAAAAA==.Tinysanta:BAAANQAECgIIBAAAAA==.Titus:BAAANQADCgYICQAAAA==.',
To='Toatani:BAAANQADCgMJAwABNQAECgQICQADAAAAAA==.Tokkaebi:BAAANQAECgIIAQAAAA==.Torvar:BAAANQADCggIDwAAAA==.',
Ty='Tyletos:BAABNQAECn8tAAMUAAoKoR/JIQBUAwAUAAoKZx/JIQBUAwAXAAUKXR02EgCDAQAAAA==.',
Ug='Ugolok:BAAANQADCgcIDQAAAA==.',
Ur='Uriél:BAAANQADCgQIBAABNQAECgoKKgAbAG0gAA==.Urubaen:BAAANQAECgYICgABNQAECgkJLAAhAAYhAA==.',
Va='Valanoth:BAAANQADCgIIAgAAAA==.Valeene:BAABNQAECn8kAAIPAAoKIx86GgD3AgAPAAoKIx86GgD3AgAAAA==.',
Ve='Veiler:BAABNQAECn8tAAMCAAoKlgyZOwBBAQACAAcKww2ZOwBBAQAcAAcK+gQ5RAA3AQAAAA==.Veruca:BAAANQAECgYIBgAAAA==.Veviseron:BAABNQAECn8lAAIXAAgKbgZuGgAhAQAXAAgKbgZuGgAhAQAAAA==.',
Vi='Vinstalation:BAAANQAECgQIBwAAAA==.',
Vo='Vonbismarck:BAABNQAECn8fAAMcAAgKjwg7RwAiAQAcAAYKmAk7RwAiAQACAAMKfQaXPwFjAAAAAA==.',
Vr='Vritraz:BAABNQAECn8qAAIbAAoKbSCDCgBGAwAbAAoKbSCDCgBGAwAAAA==.',
Wa='Warsonge:BAAANQAECgUICQAAAA==.',
We='Wendypini:BAABNQAECn81AAICAAoKfRW3GAC3AQACAAoKfRW3GAC3AQAAAA==.',
Wh='Whitlock:BAAANQAECgMIBAAAAA==.',
Xe='Xendria:BAAANQADCggICgAAAA==.',
Ya='Yannhal:BAAANQAECgIIAgAAAA==.',
Za='Zangelf:BAAANQABCggIFAAAAA==.Zangolf:BAAANQABCggIDQAAAA==.',
Zo='Zodiaac:BAABNQAECn8qAAIlAAgKtxeMFgAzAQAlAAgKtxeMFgAzAQAAAA==.',
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
