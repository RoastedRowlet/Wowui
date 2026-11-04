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

local lookup = {'DeathKnight-Frost','DeathKnight-Unholy','Druid-Balance','DemonHunter-Devourer','DeathKnight-Blood','Paladin-Retribution','Hunter-BeastMastery','Rogue-Assassination','Paladin-Holy','DemonHunter-Havoc','Warlock-Affliction','Mage-Arcane','Druid-Guardian','Druid-Restoration','Shaman-Elemental','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','Monk-Brewmaster','Warrior-Arms','Warrior-Protection','Unknown-Unknown','DemonHunter-Vengeance','Priest-Holy','Evoker-Augmentation','Evoker-Devastation','Monk-Windwalker','Shaman-Restoration','Warrior-Fury','Paladin-Protection','Druid-Feral','Shaman-Enhancement','Mage-Frost','Evoker-Preservation','Monk-Mistweaver','Priest-Shadow',}
local provider = {region='US',realm="Quel'dorei",name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abiotic:BAAANQADCgQIBQAAAA==.Abugslife:BAAANQADCgIIAgAAAA==.',
Ac='Acaleus:BAAANQAECgQIBAAAAA==.',
Ad='Adric:BAAANQAECgYIDQAAAA==.Aduhgall:BAAANQADCgcIDQAAAA==.',
Ah='Ahnji:BAAANQADCgMIBAAAAA==.',
Ai='Aings:BAABNQAECn83AAMBAAoKYyPgEwDuAgABAAoKLSPgEwDuAgACAAgKDiG4GwDmAgAAAA==.Ainzoulgown:BAAANQAECgUIBQAAAA==.Aiydaen:BAAANQADCgQIAwAAAA==.Aiytan:BAAANQADCgMIAwAAAA==.',
Al='Alarus:BAABNQAECn9CAAIDAAoKMBryGAASAgADAAoKMBryGAASAgAAAA==.Aldith:BAAANQABCgEIAQAAAA==.Alex:BAABNQAECn8vAAIEAAoKDRUiGQCSAgAEAAoKDRUiGQCSAgAAAA==.Alivathor:BAAANQAECgIIAgABNQAECggIJgAFAHEYAA==.Allypally:BAABNQAECn8eAAIGAAkKYQz2wQCYAQAGAAkKYQz2wQCYAQAAAA==.Althorian:BAAANQAECggIDwAAAA==.',
Am='Amgrod:BAEANQADCgUIBQAAAA==.Amway:BAAANQAECgQICwAAAA==.',
An='Andaarian:BAAANQADCgUIBQAAAA==.Angelkitty:BAAANQADCgYIBgAAAA==.',
Ap='Apophiz:BAAANQADCgYIBgAAAA==.',
Ar='Arcadius:BAAANQADCgIIAgAAAA==.Aremis:BAAANQAECgYIEQAAAA==.Arkaid:BAABNQAECn8UAAIHAAcKwxQxaACrAQAHAAcKwxQxaACrAQAAAA==.Arkhitype:BAABNQAECn8cAAIIAAgKsBctJQBhAgAIAAgKsBctJQBhAgAAAA==.Arteras:BAAANQAECgQIBgAAAA==.Aryadel:BAAANQABCgQIBAAAAA==.Aryahi:BAAANQAECggIAQAAAA==.',
As='Ashyslashy:BAABNQAECn8bAAMGAAoKrBZOfQAvAgAGAAkK0RdOfQAvAgAJAAYKpxDBtwANAQAAAA==.Asur:BAABNQAECn8uAAIGAAgKyg8EjwBuAQAGAAgKyg8EjwBuAQAAAA==.',
Au='Auracorusca:BAABNQAECn8kAAMJAAoKhB/eKQDAAgAJAAoKhB/eKQDAAgAGAAEK2gVWrgEwAAAAAA==.Aurafarmer:BAAANQAECgUIBAAAAA==.Auris:BAAANQADCgQIBAAAAA==.',
Ay='Aydain:BAAANQADCgQIBAAAAA==.Aynilith:BAABNQAECn8aAAIKAAoK9QiOOAAjAQAKAAoK9QiOOAAjAQAAAA==.Aystarael:BAAANQAECggIEAAAAA==.',
Ba='Bajr:BAABNQAECn8nAAIHAAoKQA0ybAChAQAHAAoKQA0ybAChAQAAAA==.Bakura:BAABNQAECn8oAAILAAoKChnvBACBAgALAAoKChnvBACBAgAAAA==.Banker:BAABNQAECn8uAAIEAAkKtQ25LQDUAQAEAAkKtQ25LQDUAQAAAA==.Baroo:BAAANQAECgQICQAAAA==.Barudd:BAAANQABCgQIBAAAAA==.',
Be='Berko:BAABNQAECn9HAAIMAAoKNh4IMgBaAgAMAAoKNh4IMgBaAgAAAA==.Beyorne:BAAANQAECgIIAQAAAA==.',
Bh='Bhaang:BAAANQAECgYIDgAAAA==.',
Bi='Bigbear:BAABNQAFFH8GAAMNAAMKeR4HAgAPAQANAAMKeR4HAgAPAQAOAAEKFwvTEwBDAAAAAA==.Bigbill:BAAANQAECgQIBAAAAA==.Bigdeath:BAABNQAECn8aAAIPAAYKlhZAiACQAQAPAAYKlhZAiACQAQAAAA==.Biletooth:BAAANQAECgYIBgABNQAECgcIJgAFALIKAA==.Bizco:BAABNQAECn8tAAMHAAoKBx9SLABjAgAHAAoKBx9SLABjAgAQAAIKaQlYYQAwAAAAAA==.',
Bj='Bjebo:BAABNQAECn8rAAIDAAoKbQxMRADiAQADAAoKbQxMRADiAQAAAA==.',
Bl='Bluffshot:BAABNQAECn8lAAIIAAgKHh7GFADVAgAIAAgKHh7GFADVAgAAAA==.',
Br='Brutes:BAAANQADCggICAABNQAFFAMIBgABAJsgAA==.Brynjalf:BAAANQAECgQIBwAAAA==.Bràe:BAAANQABCgMIAQAAAA==.',
Bx='Bxck:BAAANQAECgEIAQAAAA==.',
['Bï']='Bïcho:BAACNQAFFH8HAAIRAAIKFBIXHwCYAAARAAIKFBIXHwCYAAA1AAQKfyQAAxEACgo1HPAuAMsCABEACgoPHPAuAMsCABIAAgq1C+tlAFcAAAAA.',
Ca='Calambar:BAAANQADCgYIBgAAAA==.Cas:BAAANQADCgYIBgAAAA==.Casally:BAAANQADCgYICgAAAA==.Cascadio:BAAANQAECgIIAQAAAA==.Castanza:BAAANQADCgQIBwAAAA==.Caswyn:BAABNQAECn8bAAITAAYKeBM7EQDdAAATAAYKeBM7EQDdAAAAAA==.',
Ch='Chapjong:BAAANQADCgQIBQAAAA==.Charjer:BAABNQAECn8uAAMUAAgKuB3WTQCgAgAUAAgKuB3WTQCgAgAVAAMK2BWZKwBxAAAAAA==.Chokengag:BAAANQADCgMIAwAAAA==.Choney:BAAANQAECgcIBwAAAA==.',
Co='Codedgar:BAAANQADCgUIBQABNQAECgcIDwAWAAAAAA==.Coffeeshot:BAAANQADCgcIDQAAAA==.Cojostudio:BAAANQADCggICAABNQAECgoKKQAHACcbAA==.Comboost:BAAANQAECgQICAAAAA==.Costcolshirt:BAAANQAECgEIAQAAAA==.',
Cr='Cranks:BAAANQAECgcIDwAAAA==.Crashcake:BAABNQAECn8lAAIBAAoKqB2TEQCdAgABAAoKqB2TEQCdAgAAAA==.Creakybones:BAAANQABCgIIAgAAAA==.Croager:BAABNQAECn8ZAAIHAAoKOhy4MQDXAgAHAAoKOhy4MQDXAgABNQAECgkJFgAGANkYAA==.',
Cu='Cup:BAABNQAECn8tAAIJAAkK0BKbcgDAAQAJAAkK0BKbcgDAAQAAAA==.',
Cv='Cvv:BAAANQADCgQIBAABNQAECgMIAwAWAAAAAA==.',
Cy='Cyberlinde:BAAANQAECgQIEAAAAA==.Cywen:BAAANQADCggICAABNQAFFAcIGQAIAP4dAA==.',
Da='Daelaris:BAABNQAECn8lAAIMAAoKaB9aQAAFAwAMAAoKaB9aQAAFAwAAAA==.Damonoris:BAABNQAECn8hAAIHAAoK0g3XbACfAQAHAAoK0g3XbACfAQAAAA==.Damthrax:BAAANQAECgQIBQAAAA==.Danielan:BAAANQAECgYICgAAAA==.Davegrôwl:BAAANQADCgEJAQABNQAECgcIJgAFALIKAA==.',
De='Deadair:BAAANQADCgcICAAAAA==.Deadlyalba:BAAANQADCgYIBgAAAA==.Deadzeo:BAAANQADCgYICQAAAA==.Demonblades:BAABNQAECn81AAIEAAoKCRkPFQDkAQAEAAoKCRkPFQDkAQAAAA==.Demonbreaker:BAABNQAECn8xAAIXAAkKjRewBwDNAQAXAAkKjRewBwDNAQAAAA==.Denarten:BAABNQAECn8hAAIGAAkKvSFYJgAsAwAGAAkKvSFYJgAsAwAAAA==.Deseth:BAAANQAECgEIAQAAAA==.',
Di='Diotima:BAAANQADCggIEQAAAA==.Dirtymorris:BAAANQAECgcIEQAAAA==.Disrupt:BAAANQAECgQICAAAAA==.',
Do='Dockevorkian:BAACNQAFFH8OAAIYAAQKxBq8EwAzAQAYAAQKxBq8EwAzAQA1AAQKfzwAAhgACgqSIHQXABoDABgACgqSIHQXABoDAAAA.Dornaaealdor:BAAANQADCgIIAgAAAA==.Dortwaz:BAACNQAFFH8GAAIRAAQKJAq0IQCMAAARAAQKJAq0IQCMAAA1AAQKfzgAAxEACgqEHYkpAD4CABEACQoJHokpAD4CABIAAgoUF41UAIEAAAAA.Doublebonus:BAAANQADCggICAABNQAFFAMIBgABAJsgAA==.Dougdk:BAABNQAECn80AAIFAAoKLCRwAwC6AwAFAAoKLCRwAwC6AwABNQAFFAMIBgANAHkeAA==.',
Dr='Dracoramonk:BAAANQAECgEIAQAAAA==.Dracoz:BAAANQADCgEIAQAAAA==.Dricex:BAAANQADCgYIBgABNQAECgMIBgAWAAAAAA==.Drinnagon:BAAANQADCgcIBwABNQAECgkJIQAGAL0hAA==.Drinntellect:BAAANQAECgMIAwABNQAECgkJIQAGAL0hAA==.Drinnundead:BAAANQADCgEIAQABNQAECgkJIQAGAL0hAA==.Druelf:BAAANQADCgUIBQAAAA==.Dryblood:BAAANQADCgQIBAAAAA==.Dryx:BAAANQAECgIIAgAAAA==.',
Du='Dunaarn:BAAANQADCgMIAwAAAA==.',
Ea='Eargroan:BAAANQADCgYICwABNQAECgoKJgAXAFgjAA==.',
El='Elilla:BAABNQAECn8tAAIFAAgK4AsrQQARAQAFAAgK4AsrQQARAQAAAA==.Elkminster:BAAANQAECgMIAwAAAA==.Ellenaya:BAAANQAECggIEAAAAA==.Elorela:BAAANQADCgQIBAABNQAECgoKIwASAIkZAA==.',
En='Enjoy:BAACNQAFFH8GAAIBAAMKmyBuDgD0AAABAAMKmyBuDgD0AAA1AAQKfyYAAwEACQoYJegHAGcDAAEACQqSJOgHAGcDAAIACQqPIm4nAJ0CAAAA.',
Fa='Famiki:BAAANQADCgcICwAAAA==.',
Fe='Feardotcom:BAAANQABCgIIAgAAAA==.Felnollid:BAABNQAECn8mAAMKAAkKWhuWHAC1AgAKAAkKWhuWHAC1AgAEAAUKewdWTQDxAAAAAA==.Fenanigans:BAABNQAECn8iAAIIAAkKeiDUCwApAwAIAAkKeiDUCwApAwAAAA==.Fenquisition:BAAANQADCggICAABNQAECgkJIgAIAHogAA==.',
Fi='Firebender:BAAANQADCgQIBQAAAA==.Firetiger:BAAANQADCgcIBwAAAA==.Fistandcider:BAAANQADCggICQAAAA==.',
Fl='Fluffyhusky:BAABNQAECn8iAAMZAAcK4ATGFgDHAAAaAAcKnQTXJgD+AAAZAAUKhAfGFgDHAAABNQAFFAIIBQAHAMcDAA==.',
Fo='Fontss:BAAANQAECgYIBwAAAA==.Fonyfish:BAACNQAFFH8IAAIRAAUK3gxEIgDnAAARAAUK3gxEIgDnAAA1AAQKfyMAAhEACQryGWtDANYBABEACQryGWtDANYBAAAA.Forba:BAAANQAECgYIBgAAAA==.',
Fr='Frostybina:BAAANQADCgMIAwAAAA==.Froztfire:BAAANQAECgQIBAABNQAECgoKGwAMAPMcAA==.',
Fu='Fubina:BAEBNQAECn8+AAMbAAoKDh+kDgD2AgAbAAoKDh+kDgD2AgATAAIK5R0zJgCcAAAAAA==.',
Fy='Fyjalla:BAAANQADCggIEAAAAA==.',
['Fâ']='Fâllênknîght:BAABNQAECn8mAAIFAAgKcRhTJwCZAQAFAAgKcRhTJwCZAQAAAA==.',
Ga='Gabh:BAAANQADCgYIBgAAAA==.Gandoorr:BAAANQAECgIIAgAAAA==.',
Gi='Gilgaglaive:BAABNQAECn8YAAIEAAkKIxYFHQBsAgAEAAkKIxYFHQBsAgAAAA==.',
Gl='Glomah:BAABNQAECn8zAAMFAAoKXyFFEwATAwAFAAkK9yFFEwATAwABAAYK8BoDNwCIAQAAAA==.Glorm:BAABNQAECn84AAIcAAoKehYSMgAlAgAcAAoKehYSMgAlAgAAAA==.',
Go='Gobropro:BAAANQADCgYIBgAAAA==.Gorathan:BAAANQADCgMIAwAAAA==.Gotalock:BAAANQAECgMIAwAAAA==.',
Gr='Grabbyhands:BAABNQAECn8mAAQFAAcKsgo6XACsAAAFAAYKyQg6XACsAAACAAUKcgkjVQCNAAABAAIK3ABBsgAIAAAAAA==.Grantul:BAABNQAECn85AAIdAAkKGBc+CADiAQAdAAkKGBc+CADiAQAAAA==.Grimthore:BAAANQAECgYICAABNQAECgoKHwAeAJMKAA==.Grolgan:BAAANQADCgYIBgAAAA==.Gromz:BAABNQAECn8UAAIRAAoK3xSTSgBzAgARAAoK3xSTSgBzAgAAAA==.',
Gu='Gulbhang:BAABNQAECn8xAAMRAAoKdh5+MwC7AgARAAoKdh5+MwC7AgASAAEKXA+cdgA3AAAAAA==.',
Ha='Hakiranatha:BAAANQADCggICAAAAA==.Harkelanu:BAAANQAECgIIAgAAAA==.',
Hb='Hbkdx:BAABNQAECn8eAAIHAAYKrQZLzQDSAAAHAAYKrQZLzQDSAAAAAA==.',
He='Health:BAAANQAECgMIAwAAAA==.',
Ho='Holdi:BAAANQADCgYIBgABNQAECgkJJQAGANcOAA==.Holyhammer:BAAANQAECggIDQAAAA==.Holyoke:BAAANQADCgEIAQAAAA==.Homunculus:BAAANQAECgUIBwAAAA==.',
Hu='Hujo:BAABNQAECn8eAAIUAAkKXxF4iwD/AQAUAAkKXxF4iwD/AQAAAA==.Hushpupi:BAABNQAECn8jAAMSAAoKiRkXCAB+AgASAAoKiRkXCAB+AgARAAQKKApF+wDVAAAAAA==.Huskerpower:BAAANQADCgcJDQAAAA==.',
Ic='Iceharted:BAAANQAECgMIAwAAAA==.Icesloth:BAABNQAECn8kAAIPAAoKGBfyUgAtAgAPAAoKGBfyUgAtAgAAAA==.',
Id='Idamarie:BAABNQAECn8YAAIPAAYKXAKy9QCpAAAPAAYKXAKy9QCpAAAAAA==.Iduun:BAAANQADCgEIAQAAAA==.',
Il='Iladelle:BAABNQAECn8oAAIEAAkKJBLBHACKAQAEAAkKJBLBHACKAQAAAA==.',
Io='Iorak:BAAANQADCgEIAQAAAA==.',
Ir='Irinon:BAAANQADCgcIDAAAAA==.',
Ix='Ixiya:BAAANQAECgQIBgAAAA==.',
Ja='Jafud:BAAANQAFFAEIAgABNQAFFAYIGAAFAGIZAA==.Jafuds:BAAANQAFFAMIAwABNQAFFAYIGAAFAGIZAA==.Jaggerss:BAAANQAECgEIAQABNQAFFAMIBgABAJsgAA==.Jamaican:BAAANQADCgYIEAAAAA==.Jaste:BAABNQAECn8dAAIYAAgKYAxCgwAVAQAYAAgKYAxCgwAVAQAAAA==.',
Ji='Jimit:BAAANQADCgcIBwAAAA==.Jimmym:BAABNQAECn8dAAIGAAYK2QMnGQGNAAAGAAYK2QMnGQGNAAAAAA==.Jirakaidae:BAAANQADCgYICwABNQAECgYIEQAWAAAAAA==.',
Jo='Jordis:BAAANQAECgcIDQAAAA==.',
Ju='Juicyfists:BAAANQADCgMIAwAAAA==.Juju:BAAANQAECgEIAQAAAA==.',
Ka='Kaedeyn:BAAANQAECggIEQAAAA==.Kaeltharon:BAAANQADCgQIAwAAAA==.Kamekaze:BAAANQADCgYIBgAAAA==.Kandrys:BAAANQADCgQIBAAAAA==.Kasgotojim:BAAANQAECgQIBAAAAA==.Kaypop:BAAANQAECgQIBAAAAA==.Kayy:BAAANQADCgIIAgAAAA==.',
Ke='Kerrster:BAAANQADCgQIBAAAAA==.',
Kh='Khármá:BAABNQAECn8mAAIeAAgKeBkrFACuAQAeAAgKeBkrFACuAQAAAA==.',
Ki='Kicklocks:BAAANQAECgMIAQAAAA==.Kikuri:BAAANQAECgYICwAAAA==.Killt:BAABNQAECn8uAAIcAAkKdB4kIQCGAgAcAAkKdB4kIQCGAgAAAA==.',
Ko='Koojoé:BAAANQAECgQIBQAAAA==.',
Ku='Kurzulan:BAABNQAECn8iAAQOAAoKeg2bOgBLAQAOAAgKdgebOgBLAQADAAUKtgaqUgCoAAANAAMK5wN/VQBQAAAAAA==.',
La='Laal:BAAANQAECgIIAgAAAA==.Laghles:BAACNQAFFH8GAAIHAAMK8hE3EQDmAAAHAAMK8hE3EQDmAAA1AAQKf00AAgcACgqGH2kgABYDAAcACgqGH2kgABYDAAAA.Laroes:BAAANQAECgEIAQABNQAECgoKMwAFAF8hAA==.Larua:BAAANQABCgQJBAAAAA==.',
Le='Lemanjá:BAABNQAECn8gAAIQAAkKYAb9HwAzAQAQAAkKYAb9HwAzAQAAAA==.',
Li='Lightlooter:BAAANQADCgYIBgAAAA==.Liliane:BAABNQAECn8YAAIGAAoKEBK+pADXAQAGAAoKEBK+pADXAQAAAA==.Limbless:BAAANQAECgcIDAAAAA==.',
Lo='Loahealth:BAAANQAECgcIDwAAAA==.Lockrocks:BAABNQAECn83AAQLAAoK+RNuDQCDAQARAAoKvxKnRQDOAQALAAYK3g9uDQCDAQASAAUKCAfzLwAJAQABNQAECgoKHwAeAJMKAA==.Lockstar:BAAANQADCgYIDAAAAA==.Loko:BAABNQAECn8pAAIcAAoKowt8QgDZAQAcAAoKowt8QgDZAQAAAA==.Lontra:BAAANQADCgUIDAAAAA==.Loozer:BAABNQAECn8fAAMeAAoKkwpeOQAiAQAGAAgKGgmD7wA9AQAeAAgK9AdeOQAiAQAAAA==.Loralast:BAAANQADCgQIBAAAAA==.',
Lu='Luzifer:BAAANQADCgYIBgAAAA==.',
Ma='Magelyman:BAABNQAECn8kAAIMAAkK+xk9SAAPAgAMAAkK+xk9SAAPAgAAAA==.Mahlaan:BAABNQAECn81AAIFAAoKcRi2IQDAAQAFAAoKcRi2IQDAAQAAAA==.Malakai:BAAANQADCgIIAgABNQAECggIFAAFADkQAA==.Malekai:BAAANQAECgUJCAABNQAECggIFAAFADkQAA==.Malyce:BAABNQAECn8UAAMFAAgKORDsSgDnAAABAAgKAQkaYgAcAQAFAAUK/hPsSgDnAAAAAA==.Malzen:BAAANQADCgMIAwABNQAECggIFAAFADkQAA==.Manaleia:BAAANQADCggIDAAAAA==.Manasolid:BAAANQADCgEIAQAAAA==.Mar:BAAANQAECgIIAgAAAA==.Maruug:BAAANQADCgYIBgAAAA==.Marvinah:BAAANQAECgIIBwAAAA==.Maydie:BAAANQAECgcIBwAAAA==.',
Me='Meatcurtin:BAAANQAECgUIBQAAAA==.Meatlover:BAAANQAECgcIDgAAAA==.Mediocre:BAABNQAECn8XAAIfAAgK+R7uBwDcAgAfAAgK+R7uBwDcAgAAAA==.Meeshka:BAABNQAECn8oAAIMAAgK6gyAiwBhAQAMAAgK6gyAiwBhAQAAAA==.Meraleona:BAABNQAECn8aAAIbAAoKIRd2HwA0AgAbAAoKIRd2HwA0AgAAAA==.Methslinger:BAAANQAECggIDgAAAA==.',
Mi='Migue:BAAANQABCgEIAgABNQAECgoKVQAGALskAA==.Miltonroe:BAAANQADCggICAABNQAECgkJLwAgAGgMAA==.',
Mo='Moarass:BAAANQAECgQJBgABNQAECgoKNAAOAEsYAA==.Moris:BAABNQAECn8iAAMSAAkKXwP2OQDZAAASAAYKwwL2OQDZAAARAAkK3wIFrwDBAAAAAA==.Mortmuzi:BAAANQADCgYJBwAAAA==.Mosrael:BAABNQAECn8XAAIGAAgKCwVXEgGXAAAGAAgKCwVXEgGXAAAAAA==.',
Ms='Mswizzlë:BAABNQAECn8lAAMhAAgKegfaFwA7AQAhAAgKegfaFwA7AQAMAAUKygPw7QCsAAAAAA==.',
Mu='Muldah:BAACNQAFFH8HAAIMAAMKWwfjIwDHAAAMAAMKWwfjIwDHAAA1AAQKf0cAAwwACgq1GLdBACMCAAwACgrnF7dBACMCACEABwrxCV4cAA0BAAAA.Murdersquab:BAAANQADCggICAAAAA==.',
Na='Nas:BAABNQAECn89AAMRAAoKQiH/FwCcAgARAAkK3iH/FwCcAgASAAEKAB2HJQBSAAAAAA==.Nausicaa:BAAANQABCggIDQAAAA==.Nausicaä:BAAANQADCgUIBQAAAA==.Navie:BAAANQAECgYIDwAAAA==.Nazgûl:BAAANQABCgYIBAAAAA==.',
Ne='Nekros:BAAANQADCgcIBwABNQAECggILgAUALgdAA==.Neø:BAABNQAECn8wAAMBAAoKmBlxIQALAgABAAkKeRlxIQALAgACAAYK5R1KXwCSAQAAAA==.',
Ni='Nianna:BAAANQADCgYIAQAAAA==.Nicebud:BAAANQAECgEIAQAAAA==.Nightsfury:BAAANQAECgYICgAAAA==.Nightshala:BAAANQAECgQIBAAAAA==.',
No='Nollid:BAAANQADCgYIBgABNQAECgkJJgAKAFobAA==.Nordburg:BAAANQABCggIEwAAAA==.Nornyr:BAAANQADCgEIAQAAAA==.Notforgiven:BAAANQAECgEIAQAAAA==.Notnonna:BAAANQADCgQIBAAAAA==.',
Nu='Nunsrsus:BAAANQAECgcIDwAAAA==.',
Ny='Nymerias:BAAANQADCgYIDgAAAA==.Nyrrah:BAAANQAECgQIBQAAAA==.',
['Ná']='Nácht:BAAANQAECgYICAAAAA==.',
['Ný']='Nýghtmyst:BAAANQAECgEJAQAAAA==.',
Ok='Oku:BAAANQADCgUIBQAAAA==.',
Ol='Olaf:BAAANQAECgIIAgAAAA==.',
Om='Omaticaya:BAABNQAECn85AAIDAAkKwwmVMgA9AQADAAkKwwmVMgA9AQAAAA==.Omèn:BAAANQADCgUIBQABNQAECgkJFgAGANkYAA==.',
Oo='Oolong:BAAANQADCggICgAAAA==.',
Op='Optikon:BAAANQAECgUIDAAAAA==.',
Or='Oriax:BAAANQAECggIEAABNQAECgoKQgADADAaAA==.',
Ow='Owlbearcat:BAAANQAECgYIDQABNQAECgcIDwAWAAAAAA==.',
Pa='Packerssuck:BAAANQADCgEIAQAAAA==.Paean:BAAANQADCgcIJgAAAA==.Paj:BAACNQAFFH8LAAMMAAcKbAfTHACYAQAMAAYK+wfTHACYAQAhAAEKMgVLDwBRAAA1AAQKfz8AAwwACgozI3QNAA0DAAwACgozI3QNAA0DACEAAQpZH2IrAF4AAAAA.',
Pe='Peata:BAAANQADCgMIAwAAAA==.Pelledrusil:BAAANQADCgUIBQAAAA==.Peria:BAAANQADCgYIDAABNQAECgMIBwAWAAAAAA==.',
Pi='Pinga:BAAANQAECggIDQABNQAECgoKLQAHAAcfAA==.',
Pk='Pkalygos:BAABNQAECn8nAAIiAAkKDBLrEACyAQAiAAkKDBLrEACyAQAAAA==.',
Pl='Pleione:BAABNQAECn8UAAIYAAkKzQ9/hQCGAQAYAAkKzQ9/hQCGAQAAAA==.',
Po='Portadave:BAAANQAECgMIBgAAAA==.Powerstrokee:BAAANQAECgYIEAAAAA==.',
Pr='Preyforme:BAABNQAECn8xAAIHAAgKSArrmADWAQAHAAgKSArrmADWAQAAAA==.Prusik:BAAANQADCgcIBwABNQAECgMIAwAWAAAAAA==.Práystation:BAAANQADCgUIBgAAAA==.',
Ps='Psychelone:BAAANQAECgQIBAAAAA==.',
Pu='Puffshot:BAAANQAECgEIAQABNQAECggIJQAIAB4eAA==.Puurseus:BAAANQABCgYIBwABNQAECggIFQASAMASAA==.',
Qu='Quillan:BAAANQADCgUIDQABNQAECgcIDwAWAAAAAA==.',
Qy='Qyxh:BAABNQAECn8iAAMKAAoK/A1bQgCuAQAKAAoK/A1bQgCuAQAXAAIKggMeMQA4AAAAAA==.',
Ra='Raine:BAAANQAECgEIAQAAAA==.Rannath:BAAANQAECggIAwABNQAECggIFwAGAAsFAA==.Rastafarian:BAAANQADCgUICQAAAA==.',
Re='Redeye:BAAANQAECgEIAQAAAA==.Rehne:BAAANQAECgEIAQAAAA==.Rexhavoc:BAACNQAFFH8HAAIEAAMKbRUQBgDvAAAEAAMKbRUQBgDvAAA1AAQKfy0AAgQACgpKG8IPADECAAQACgpKG8IPADECAAAA.Rexion:BAAANQAECgEIAQAAAA==.',
Ri='Rigormortits:BAAANQAECgQIBAAAAA==.Ripre:BAAANQADCgUICwAAAA==.',
Ro='Rosary:BAABNQAECn8kAAINAAcKQQX5MQAPAQANAAcKQQX5MQAPAQAAAA==.Rosewoodren:BAAANQAECgQIAQAAAA==.',
Ru='Ruint:BAAANQADCgUIBQAAAA==.Runeclad:BAABNQAECn8XAAICAAgKDxkTRQAFAgACAAgKDxkTRQAFAgAAAA==.',
Ry='Ryla:BAAANQADCgIIAgABNQAECgkJMAAIAPEaAA==.',
['Rï']='Rïvkah:BAAANQADCgUIBwABNQAECgQIBQAWAAAAAA==.',
Sa='Saauurrora:BAAANQADCgYIBgAAAA==.Saintshift:BAAANQADCgEIAQABNQAECgMIAwAWAAAAAA==.Salitheion:BAAANQAECgQIAwAAAA==.Sapper:BAABNQAECn9MAAIjAAoK3CIoAwCCAwAjAAoK3CIoAwCCAwAAAA==.Sarn:BAAANQAECgEIAQAAAA==.Sathi:BAAANQAECgIIAQAAAA==.Sayuri:BAAANQADCgEIAQAAAA==.',
Se='Sennest:BAAANQADCgUIAwAAAA==.',
Sh='Shadowmoocow:BAAANQAECgEIAQABNQAECgQICAAWAAAAAA==.Shikí:BAAANQAECgIIBAAAAA==.Shladoran:BAABNQAECn8vAAIUAAoK1gvgaQCKAQAUAAoK1gvgaQCKAQAAAA==.Shos:BAABNQAECn88AAIVAAoKwh/BBACnAgAVAAoKwh/BBACnAgAAAA==.Shuttsyy:BAAANQADCgMIAwAAAA==.',
Si='Siberianwolf:BAABNQAECn8XAAIHAAoKMRkXKgBrAgAHAAoKMRkXKgBrAgAAAA==.Sinnister:BAAANQADCgYIBgAAAA==.Sitruc:BAAANQAECgcICwAAAA==.',
Sk='Skully:BAAANQADCgUIBQABNQAFFAMIBgANAHkeAA==.',
Sl='Sledge:BAAANQADCgMIAwAAAA==.',
Sn='Snapdragyn:BAAANQAECgQIAQAAAA==.Snorina:BAABNQAECn80AAIkAAoKqR+XDQATAwAkAAoKqR+XDQATAwAAAA==.',
So='Solàrflàré:BAAANQADCgMIAwAAAA==.Sosgoraan:BAAANQADCgcJBwABNQAECgoKNQAFAHEYAA==.Sosozen:BAABNQAECn8lAAIbAAgKEQp4OABQAQAbAAgKEQp4OABQAQAAAA==.Soul:BAACNQAFFH8FAAQNAAIK+BELBgB5AAANAAIK+BELBgB5AAADAAIKeQGpHABMAAAfAAEKBwOdBAAuAAA1AAQKfzMABA0ACgrJHk0GAMoCAA0ACgrJHk0GAMoCAB8ACgpLDT0PAIQBAAMABQqLBG5WAJsAAAAA.',
Sp='Spirittoast:BAAANQAECgEIAQAAAA==.',
Sr='Sriman:BAAANQAECgYIBgAAAA==.',
St='Starkiller:BAAANQADCgYIDgAAAA==.Stonesolid:BAABNQAECn83AAMUAAkK3xjmUwCPAgAUAAgKGBzmUwCPAgAdAAEKhwWXLwAhAAAAAA==.Stratovarius:BAAANQADCgYIBgAAAA==.',
Su='Sugouri:BAAANQAECggICAAAAA==.Sunnyginger:BAAANQAECgYICgAAAA==.Supremacy:BAABNQAECn8oAAMRAAoKUybzCwBtAwARAAoKUybzCwBtAwASAAEKzSE4YwBeAAAAAA==.',
Sw='Sweetspot:BAAANQAECgcIDgABNQAECgoKHwAeAJMKAA==.Swiftshammy:BAAANQADCgQIBAAAAA==.Swytch:BAABNQAECn8wAAIIAAkK8Rr8CgD8AQAIAAkK8Rr8CgD8AQAAAA==.',
Sy='Sylrytherin:BAAANQADCgYICgABNQAECgoKNAAkAKkfAA==.Sylvii:BAABNQAECn8pAAMOAAgKFROfKQDSAQAOAAgKFROfKQDSAQADAAEKAACulAAAAAAAAA==.',
Ta='Tabor:BAAANQAECgUIBgAAAA==.Taggz:BAAANQABCgQIBAAAAA==.Taladryn:BAAANQADCgcIDQAAAA==.Tarahly:BAABNQAECn8qAAIJAAkKViEnFQDjAgAJAAkKViEnFQDjAgAAAA==.Tauryel:BAAANQAECgQIBwABNQAECgcIDAAWAAAAAA==.',
Te='Tekhan:BAAANQADCgQIBAAAAA==.Tethlis:BAAANQADCggICAABNQAECgoKGgANACAgAA==.',
Th='Thasarias:BAAANQAECgUIBwAAAA==.Themoosifer:BAACNQAFFH8ZAAIEAAgKRBgSAgBhAgAEAAgKRBgSAgBhAgA1AAQKfzIAAgQACgqgIxUOAAcDAAQACgqgIxUOAAcDAAAA.Thunderdump:BAABNQAECn8pAAIcAAkKNBrXTAAwAgAcAAkKNBrXTAAwAgAAAA==.Thyck:BAABNQAECn8eAAIHAAkKihEgcgAtAgAHAAkKihEgcgAtAgAAAA==.Thydis:BAABNQAECn9BAAIGAAoKGBCggACLAQAGAAoKGBCggACLAQAAAA==.',
Ti='Tiancit:BAAANQADCgEIAQAAAA==.Tibbs:BAABNQAECn81AAMaAAoKEg58FQD1AQAaAAgK4Q98FQD1AQAZAAkKLAxuCwAQAQAAAA==.Ticklepickle:BAAANQAECgQICAAAAA==.',
To='Tooch:BAAANQADCggICAAAAA==.Torluis:BAAANQADCgMIAwAAAA==.',
Tr='Trumalice:BAAANQADCggIGQAAAA==.',
Tu='Tulpa:BAAANQABCgYIDAAAAA==.',
Ty='Tyrmarlq:BAAANQAECgQIBAAAAA==.',
Un='Uncorrupted:BAABNQAECn8dAAMeAAkKTxM8KQCTAQAeAAgKIBY8KQCTAQAGAAIKigQ2sQEvAAAAAA==.',
Up='Updog:BAAANQAECgEIAQABNQAECgQICAAWAAAAAA==.',
Va='Vaelm:BAAANQADCgcICgAAAA==.Valericia:BAAANQADCgQIBAAAAA==.Valindrux:BAABNQAECn8zAAMhAAkKDBbDFAAKAQAMAAgKVhFj0QDjAQAhAAQKZxjDFAAKAQAAAA==.Valjin:BAAANQADCgQIBAABNQAECgkJMwAhAAwWAA==.Valuryan:BAAANQAECgUICAABNQAECgkJMwAhAAwWAA==.Vasdepherens:BAAANQAECgcIBwAAAA==.',
Ve='Velathila:BAAANQAECgMIBQAAAA==.',
Vi='Victorsith:BAAANQADCgMIAwAAAA==.Violêt:BAAANQADCgYIBgAAAA==.Vizzelok:BAABNQAECn8eAAILAAgKZxBDCgDVAQALAAgKZxBDCgDVAQAAAA==.',
Vo='Voidchris:BAABNQAECn8/AAMEAAoK7x4bEADxAgAEAAoKoxwbEADxAgAKAAoKVxp1EgBlAgAAAA==.Voidormu:BAAANQAECgQICAAAAA==.',
Wa='Warelf:BAABNQAECn8UAAMRAAkKICHJJgDpAgARAAkKICHJJgDpAgASAAEKUxFBdAA6AAAAAA==.Warleck:BAAANQAECgYIDgAAAA==.Waroo:BAAANQADCgIIAgAAAA==.',
Wh='Whodey:BAAANQAECgUIDQABNQAECggIFAAFADkQAA==.',
Wi='Wisp:BAAANQADCgYIEQAAAA==.',
Wo='Wompadonk:BAAANQAECgcIBwABNQAFFAMIBgANAHkeAA==.',
Wy='Wylia:BAABNQAECn8bAAIMAAoK/w+DXQDTAQAMAAoK/w+DXQDTAQAAAA==.',
Xc='Xcw:BAAANQAECgIIAgAAAA==.',
Yy='Yyirium:BAAANQADCgIIAgAAAA==.',
Za='Zakkmorris:BAAANQADCgEIAQAAAA==.Zakuren:BAABNQAECn9LAAIHAAoKJBkrLwBYAgAHAAoKJBkrLwBYAgAAAA==.',
Zi='Ziggi:BAAANQADCgYIBgABNQAECgMIAwAWAAAAAA==.',
Zo='Zondoul:BAAANQADCgYIBgAAAA==.',
Zu='Zugnator:BAAANQAECgQIBgABNQAECggILwAPAEkWAA==.',
Zy='Zylera:BAAANQAECgMIAgAAAA==.Zyphor:BAAANQADCggIDQAAAA==.Zyth:BAAANQABCgMIAgAAAA==.',
['Ñî']='Ñîx:BAAANQAECgYIEwAAAA==.',
['Òm']='Òmêñ:BAABNQAECn8WAAIGAAkK2Rh2SwATAgAGAAkK2Rh2SwATAgAAAA==.',
['Ød']='Ødinson:BAAANQAECgEJAQAAAA==.',
['ßæ']='ßær:BAAANQAECgIJAgAAAA==.',
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
