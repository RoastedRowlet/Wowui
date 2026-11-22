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

local lookup = {'DeathKnight-Frost','DeathKnight-Unholy','Druid-Balance','DemonHunter-Devourer','DeathKnight-Blood','Paladin-Retribution','Hunter-BeastMastery','Rogue-Assassination','Paladin-Holy','DemonHunter-Havoc','Warlock-Affliction','Mage-Arcane','Druid-Guardian','Druid-Restoration','Shaman-Elemental','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','Monk-Brewmaster','Warrior-Arms','Warrior-Protection','Unknown-Unknown','DemonHunter-Vengeance','Priest-Holy','Evoker-Augmentation','Evoker-Devastation','Mage-Fire','Monk-Windwalker','Shaman-Restoration','Warrior-Fury','Paladin-Protection','Priest-Discipline','Druid-Feral','Shaman-Enhancement','Mage-Frost','Evoker-Preservation','Monk-Mistweaver','Rogue-Subtlety','Priest-Shadow',}
local provider = {region='US',realm="Quel'dorei",name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abiotic:BAAANQADCgQIBQAAAA==.Abugslife:BAAANQADCgIIAgAAAA==.',
Ac='Acaleus:BAAANQAECgQIBAAAAA==.',
Ad='Adric:BAAANQAECggIEgAAAA==.Aduhgall:BAAANQADCgcIDQAAAA==.',
Ah='Ahnji:BAAANQADCgMIBAAAAA==.Ahrator:BAAANQADCgEIAQAAAA==.',
Ai='Aings:BAABNQAECn84AAMBAAoK1SPgEwDuAgABAAoKnyPgEwDuAgACAAgKDiG4GwDmAgAAAA==.Ainzoulgown:BAAANQAECgUICAAAAA==.Aiydaen:BAAANQADCgQIAwAAAA==.Aiytan:BAAANQADCgMIAwAAAA==.',
Al='Alarus:BAABNQAECn9CAAIDAAoKMBpzHgANAgADAAoKMBpzHgANAgAAAA==.Aldith:BAAANQADCgEIAQAAAA==.Alex:BAABNQAECn8vAAIEAAoKDRUiGQCSAgAEAAoKDRUiGQCSAgAAAA==.Alivathor:BAAANQAECgIIAgABNQAECgoKLQAFAGgWAA==.Allypally:BAABNQAECn8eAAIGAAkKYQz2wQCYAQAGAAkKYQz2wQCYAQAAAA==.Althorian:BAAANQAECggIDwAAAA==.',
Am='Amgrod:BAEANQADCgUIBQAAAA==.Amway:BAAANQAECgQICwAAAA==.',
An='Andaarian:BAAANQADCgUIBQAAAA==.Angelkitty:BAAANQADCgYIBgAAAA==.',
Ap='Apophiz:BAAANQADCgYIBgAAAA==.',
Ar='Arcadius:BAAANQADCgIIAgAAAA==.Aremis:BAAANQAECgYIEwAAAA==.Arkaid:BAABNQAECn8cAAIHAAkKRxWwRQBHAgAHAAkKRxWwRQBHAgAAAA==.Arkhitype:BAABNQAECn8cAAIIAAgKsBctJQBhAgAIAAgKsBctJQBhAgAAAA==.Arteras:BAAANQAECgQIBgAAAA==.Aryadel:BAAANQABCgQIBAAAAA==.Aryahi:BAAANQAECggIAQAAAA==.',
As='Ashyslashy:BAABNQAECn8bAAMGAAoKrBZOfQAvAgAGAAkK0RdOfQAvAgAJAAYKpxDBtwANAQAAAA==.Asur:BAABNQAECn9CAAIGAAoKOBWeVAAwAgAGAAoKOBWeVAAwAgAAAA==.',
Au='Auracorusca:BAABNQAECn8lAAMJAAoKhB/eKQDAAgAJAAoKhB/eKQDAAgAGAAEK2gVWrgEwAAAAAA==.Aurafarmer:BAAANQAECgUIBAAAAA==.Auris:BAAANQADCgQIBAAAAA==.',
Ay='Aydain:BAAANQADCgQIBAAAAA==.Aynilith:BAABNQAECn8aAAIKAAoK9QhZQwAmAQAKAAoK9QhZQwAmAQAAAA==.Aystarael:BAAANQAECggIEAAAAA==.',
Ba='Bajr:BAABNQAECn8rAAIHAAoK6Q2UfgC9AQAHAAoK6Q2UfgC9AQAAAA==.Bakura:BAABNQAECn8oAAILAAoKChnvBACBAgALAAoKChnvBACBAgAAAA==.Banker:BAABNQAECn80AAIEAAoKZg08JQBxAQAEAAoKZg08JQBxAQAAAA==.Baroo:BAAANQAECgQICQAAAA==.Barudd:BAAANQABCgQIBAAAAA==.',
Be='Berko:BAABNQAECn9SAAIMAAoKhx9qKACdAgAMAAoKhx9qKACdAgAAAA==.Beyorne:BAAANQAECgIIAQAAAA==.',
Bh='Bhaang:BAAANQAECgYIDgAAAA==.',
Bi='Bigbear:BAACNQAFFH8GAAMNAAMKeR6WAgALAQANAAMKeR6WAgALAQAOAAEKFwvJGAA7AAA1AAQKfx4AAg0ACQpXJr4AAIYDAA0ACQpXJr4AAIYDAAAA.Bigbill:BAAANQAECgQIBAAAAA==.Bigdeath:BAABNQAECn8fAAIPAAcKXhZAiACQAQAPAAcKXhZAiACQAQAAAA==.Biletooth:BAAANQAECgcIEAABNQAECggILgACALoKAA==.Bizco:BAABNQAECn8tAAMHAAoKBx9ZOwBhAgAHAAoKBx9ZOwBhAgAQAAIKaQkvawAwAAAAAA==.',
Bj='Bjebo:BAABNQAECn8rAAIDAAoKbQxMRADiAQADAAoKbQxMRADiAQAAAA==.',
Bl='Bluffshot:BAABNQAECn8pAAIIAAoKCRvGFADVAgAIAAoKCRvGFADVAgAAAA==.',
Br='Brutes:BAAANQADCggICAABNQAFFAMIBgABAJsgAA==.Brynjalf:BAAANQAECgQIBwAAAA==.Bràe:BAAANQABCgMIAQAAAA==.',
Bx='Bxck:BAAANQAECgEIAQAAAA==.',
['Bï']='Bïcho:BAACNQAFFH8KAAMRAAUKvQ6yJwCTAAARAAQKFBKyJwCTAAALAAEKEAiUGQBHAAA1AAQKfy4AAxEACgqFIS0eAJwCABEACgqFIS0eAJwCABIAAgq1C+tlAFcAAAAA.',
Ca='Calambar:BAAANQADCgYIBgAAAA==.Cas:BAAANQADCgYIBgAAAA==.Casally:BAAANQADCgYICgAAAA==.Cascadio:BAAANQAECgIIAQAAAA==.Castanza:BAAANQADCgQIBwAAAA==.Caswyn:BAABNQAECn8gAAITAAYKVRQ4FADiAAATAAYKVRQ4FADiAAAAAA==.',
Ch='Chapjong:BAAANQADCgQIBQAAAA==.Charjer:BAABNQAECn80AAMUAAoKIBzrNABrAgAUAAoKCBzrNABrAgAVAAQK3RnzJADSAAAAAA==.Chokengag:BAAANQADCgMIAwAAAA==.Choney:BAAANQAECgcIBwAAAA==.',
Co='Codedgar:BAAANQADCgUIBQABNQAECgcIDwAWAAAAAA==.Coffeeshot:BAAANQADCgcIDQAAAA==.Cojostudio:BAAANQADCggICAABNQAECgoKKQAHACcbAA==.Comboost:BAAANQAECgQIDAAAAA==.Costcolshirt:BAAANQAECgEIAQAAAA==.',
Cr='Cranks:BAAANQAECgcIDwAAAA==.Crashcake:BAABNQAECn8lAAIBAAoKqB2LGACGAgABAAoKqB2LGACGAgAAAA==.Creakybones:BAAANQABCgIIAgAAAA==.Croager:BAABNQAECn8ZAAIHAAoKOhy4MQDXAgAHAAoKOhy4MQDXAgABNQAECgkJGQAGANkYAA==.',
Cu='Cup:BAABNQAECn8vAAMJAAoKARKbcgDAAQAJAAoKARKbcgDAAQAGAAEKIBCjiAE/AAAAAA==.',
Cv='Cvv:BAAANQADCgQIBAABNQAECgMIAwAWAAAAAA==.',
Cy='Cyberlinde:BAABNQAECn8UAAIHAAYK1xPx2QBNAQAHAAYK1xPx2QBNAQAAAA==.Cywen:BAAANQADCggICAABNQAFFAgIGgAIAKUcAA==.',
Da='Daelaris:BAABNQAECn8oAAIMAAoKxh9aQAAFAwAMAAoKxh9aQAAFAwAAAA==.Damonoris:BAABNQAECn8kAAIHAAoK6g6WfwC7AQAHAAoK6g6WfwC7AQAAAA==.Damthrax:BAAANQAECgQIBQAAAA==.Danielan:BAAANQAECgcICgAAAA==.Davegrôwl:BAAANQADCgEJAQABNQAECggILgACALoKAA==.',
De='Deadair:BAAANQADCgcICAAAAA==.Deadlyalba:BAAANQADCgYIBgAAAA==.Deadzeo:BAAANQADCgYICQAAAA==.Demonblades:BAABNQAECn85AAIEAAoKqhnBHABvAgAEAAoKqhnBHABvAgAAAA==.Demonbreaker:BAABNQAECn8xAAIXAAkKjRfpCQDIAQAXAAkKjRfpCQDIAQAAAA==.Denarten:BAABNQAECn8hAAIGAAkKvSFYJgAsAwAGAAkKvSFYJgAsAwAAAA==.Deseth:BAAANQAECgcICAAAAA==.',
Di='Diotima:BAAANQADCggIFgAAAA==.Dirtymorris:BAAANQAECgcIEQAAAA==.Disrupt:BAAANQAECgQICAAAAA==.',
Do='Dockevorkian:BAACNQAFFH8UAAIYAAQKAR1TGAA5AQAYAAQKAR1TGAA5AQA1AAQKf0EAAhgACgodIXQXABoDABgACgodIXQXABoDAAAA.Dornaaealdor:BAAANQADCgIIAgAAAA==.Dortwaz:BAACNQAFFH8GAAIRAAQKJAoAKwCFAAARAAQKJAoAKwCFAAA1AAQKfzgAAxEACgqEHRU4ADECABEACQoJHhU4ADECABIAAgoUF41UAIEAAAAA.Doublebonus:BAAANQADCggICAABNQAFFAMIBgABAJsgAA==.Dougdk:BAABNQAECn80AAIFAAoKLCRwAwC6AwAFAAoKLCRwAwC6AwABNQAFFAMIBgANAHkeAA==.',
Dr='Dracoramonk:BAAANQAECgEIAQAAAA==.Dracoz:BAAANQADCgEIAQAAAA==.Dricex:BAAANQADCgYIBgABNQAECgMIBgAWAAAAAA==.Drinnagon:BAAANQADCgcIBwABNQAECgkJIQAGAL0hAA==.Drinntellect:BAAANQAECgMIAwABNQAECgkJIQAGAL0hAA==.Drinnundead:BAAANQADCgEIAQABNQAECgkJIQAGAL0hAA==.Druelf:BAAANQADCgUIBQAAAA==.Dryblood:BAAANQADCgQIBAAAAA==.Dryx:BAAANQAECgIIAgAAAA==.',
Du='Dunaarn:BAAANQADCgMIAwAAAA==.',
Ea='Eargroan:BAAANQADCgYICwABNQAECgoKJgAXAFgjAA==.',
El='Elilla:BAABNQAECn81AAIFAAoKTQvrOABfAQAFAAoKTQvrOABfAQAAAA==.Elkminster:BAAANQAECgMIBAAAAA==.Ellenaya:BAAANQAECggIEgAAAA==.Elorela:BAAANQADCgQIBAABNQAECgoKIwASAIkZAA==.',
En='Enjoy:BAACNQAFFH8GAAIBAAMKmyBuDgD0AAABAAMKmyBuDgD0AAA1AAQKfyYAAwEACQoYJegHAGcDAAEACQqSJOgHAGcDAAIACQqPIm4nAJ0CAAAA.',
Fa='Famiki:BAAANQADCgcICwAAAA==.',
Fe='Feardotcom:BAAANQABCgIIAgAAAA==.Felnollid:BAABNQAECn8mAAMKAAkKWhuWHAC1AgAKAAkKWhuWHAC1AgAEAAUKewdWTQDxAAAAAA==.Fenanigans:BAABNQAECn8iAAIIAAkKeiDUCwApAwAIAAkKeiDUCwApAwAAAA==.Fenquisition:BAAANQADCggICAABNQAECgkJIgAIAHogAA==.',
Fi='Firebender:BAAANQADCgQIBQAAAA==.Firetiger:BAAANQADCgcIBwAAAA==.Fistandcider:BAAANQADCggICQAAAA==.',
Fl='Fluffyhusky:BAABNQAECn8iAAMZAAcK4ATGFgDHAAAaAAcKnQTXJgD+AAAZAAUKhAfGFgDHAAABNQAFFAIIBQAHAMcDAA==.',
Fo='Fontss:BAAANQAECggIEAAAAA==.Fonyfish:BAACNQAFFH8IAAIRAAUK3gxEIgDnAAARAAUK3gxEIgDnAAA1AAQKfyQAAhEACQryGT1UANcBABEACQryGT1UANcBAAAA.Forba:BAAANQAECgYIBgAAAA==.',
Fr='Frostybina:BAAANQADCgMIBAAAAA==.Froztfire:BAAANQAECgQIBAABNQAFFAMIBQAbAAMNAA==.',
Fu='Fubina:BAEBNQAECn9GAAMcAAoK4x+kDgD2AgAcAAoK4x+kDgD2AgATAAIK5R0zJgCcAAAAAA==.',
Fy='Fyjalla:BAAANQADCggIEAAAAA==.',
['Fâ']='Fâllênknîght:BAABNQAECn8tAAIFAAoKaBbXHgAEAgAFAAoKaBbXHgAEAgAAAA==.',
Ga='Gabh:BAAANQADCgYIBgAAAA==.Gandoorr:BAAANQAECgIIAgAAAA==.',
Gi='Gilgaglaive:BAABNQAECn8YAAIEAAkKIxYFHQBsAgAEAAkKIxYFHQBsAgAAAA==.',
Gl='Glomah:BAABNQAECn83AAMFAAoKXyFFEwATAwAFAAkK9yFFEwATAwABAAcKqx0nLwDwAQAAAA==.Glorm:BAABNQAECn9HAAIdAAoKlhk1IQC1AgAdAAoKlhk1IQC1AgAAAA==.',
Go='Gobropro:BAAANQADCgYIBgAAAA==.Gorathan:BAAANQADCgMIAwAAAA==.Gotalock:BAAANQAECgMIBAAAAA==.',
Gr='Grabbyhands:BAABNQAECn8uAAQCAAgKugrmSADjAAACAAcKMQjmSADjAAAFAAcKGQn2XADOAAABAAIK3AC5ygAIAAAAAA==.Grantul:BAABNQAECn87AAIeAAoKrhiqBwA2AgAeAAoKrhiqBwA2AgAAAA==.Grimthore:BAAANQAECgUICwABNQAECgoKIAAfAKQLAA==.Grolgan:BAAANQADCgYIBgAAAA==.Gromz:BAABNQAECn8UAAIRAAoK3xSTSgBzAgARAAoK3xSTSgBzAgAAAA==.',
Gu='Gulbhang:BAABNQAECn8xAAMRAAoKdh5+MwC7AgARAAoKdh5+MwC7AgASAAEKXA+cdgA3AAAAAA==.',
Ha='Hakiranatha:BAAANQADCggICAAAAA==.Harkelanu:BAAANQAECgIIAgAAAA==.',
Hb='Hbkdx:BAABNQAECn8eAAIHAAYKrQaQ7wDRAAAHAAYKrQaQ7wDRAAAAAA==.',
He='Health:BAAANQAECgMIAwAAAA==.',
Ho='Holdi:BAAANQADCgYIBgABNQAECgkJJQAGANcOAA==.Holyhammer:BAAANQAECggIDQAAAA==.Holyoke:BAAANQADCgEIAQAAAA==.Homunculus:BAAANQAECgUIBwAAAA==.',
Hu='Hujo:BAABNQAECn8eAAIUAAkKXxF4iwD/AQAUAAkKXxF4iwD/AQAAAA==.Hushpupi:BAABNQAECn8jAAMSAAoKiRkXCAB+AgASAAoKiRkXCAB+AgARAAQKKApF+wDVAAAAAA==.Huskerpower:BAAANQADCgcIDQAAAA==.',
Ic='Iceharted:BAAANQAECgMIAwAAAA==.Icesloth:BAABNQAECn8lAAIPAAoKGBfyUgAtAgAPAAoKGBfyUgAtAgAAAA==.',
Id='Idamarie:BAABNQAECn8aAAIPAAcKGgKy9QCpAAAPAAcKGgKy9QCpAAAAAA==.Iduun:BAAANQADCgEIAQAAAA==.',
Il='Iladelle:BAABNQAECn8qAAIEAAoKixLOHADAAQAEAAoKixLOHADAAQAAAA==.',
Io='Iorak:BAAANQADCgEIAQAAAA==.',
Ir='Irinon:BAAANQADCgcIDAAAAA==.',
Ix='Ixiya:BAAANQAECgQIBgAAAA==.',
Ja='Jafud:BAAANQAFFAEIAQABNQAFFAYIGAAFAGIZAA==.Jafuds:BAAANQAFFAMIAwABNQAFFAYIGAAFAGIZAA==.Jaggerss:BAAANQAECgEIAQABNQAFFAMIBgABAJsgAA==.Jamaican:BAAANQADCgYIEAAAAA==.Jaste:BAABNQAECn8lAAIYAAgKTBDqeQBsAQAYAAgKTBDqeQBsAQAAAA==.',
Ji='Jimit:BAAANQADCgcIBwAAAA==.Jimmym:BAABNQAECn8iAAIGAAYKHwX6LgGlAAAGAAYKHwX6LgGlAAAAAA==.Jirakaidae:BAAANQADCgYICwABNQAECgYIEwAWAAAAAA==.',
Jo='Jordis:BAABNQAECn8YAAIKAAoKbA0lKwC3AQAKAAoKbA0lKwC3AQAAAA==.',
Ju='Juicyfists:BAAANQADCgMIAwAAAA==.Juju:BAAANQAECgEIAQAAAA==.',
Ka='Kaedeyn:BAABNQAECn8gAAMYAAkK+AnfagCdAQAYAAkK+AnfagCdAQAgAAEK6gFmHwAdAAAAAA==.Kaeltharon:BAAANQADCgQIAwAAAA==.Kairos:BAAANQADCggICAAAAA==.Kamekaze:BAAANQADCgYIBgAAAA==.Kandrys:BAAANQADCgQIBAAAAA==.Kasgotojim:BAAANQAECgQIBAAAAA==.Kaypop:BAAANQAECgQIBAAAAA==.Kayy:BAAANQADCgIIAgAAAA==.',
Ke='Kerrster:BAAANQADCgQIBAAAAA==.',
Kh='Khármá:BAABNQAECn8sAAIfAAoKzhi2DwAtAgAfAAoKzhi2DwAtAgAAAA==.',
Ki='Kicklocks:BAAANQAECgMIAQAAAA==.Kikuri:BAAANQAECggICwAAAA==.Killt:BAABNQAECn8xAAIdAAoK0h10IAC6AgAdAAoK0h10IAC6AgAAAA==.',
Ko='Koojoé:BAAANQAECgQIBQAAAA==.',
Ku='Kurzulan:BAABNQAECn8iAAQOAAoKeg2bOgBLAQAOAAgKdgebOgBLAQADAAUKtgZ6XgCoAAANAAMK5wN/VQBQAAAAAA==.',
La='Laal:BAAANQAECgIIAgAAAA==.Laghles:BAACNQAFFH8GAAIHAAMK8hFQFgDfAAAHAAMK8hFQFgDfAAA1AAQKf1YAAgcACgp2IGkgABYDAAcACgp2IGkgABYDAAAA.Laroes:BAAANQAECgEIAQABNQAECgoKNwAFAF8hAA==.Larua:BAAANQABCgQJBAAAAA==.',
Le='Lemanjá:BAABNQAECn8xAAIQAAoKNwdxHgCCAQAQAAoKNwdxHgCCAQAAAA==.',
Li='Lightlooter:BAAANQADCgYIBgAAAA==.Liliane:BAABNQAECn8YAAIGAAoKEBK+pADXAQAGAAoKEBK+pADXAQAAAA==.Limbless:BAAANQAECgcIDAAAAA==.',
Lo='Loahealth:BAAANQAECgcIDwAAAA==.Lockrocks:BAABNQAECn89AAQRAAoKiBblQAATAgARAAoKThXlQAATAgALAAYK3g9uDQCDAQASAAUKCAfzLwAJAQABNQAECgoKIAAfAKQLAA==.Lockstar:BAAANQADCgYIDAAAAA==.Loko:BAABNQAECn8pAAIdAAoKowtLVgC6AQAdAAoKowtLVgC6AQAAAA==.Lontra:BAAANQADCgUIDAAAAA==.Loozer:BAABNQAECn8gAAMfAAoKpAteOQAiAQAGAAgKUwqD7wA9AQAfAAgK9AdeOQAiAQAAAA==.Loralast:BAAANQADCgQIBAAAAA==.',
Lu='Luzifer:BAAANQADCgYIBgAAAA==.',
Ma='Magelyman:BAABNQAECn8lAAIMAAkK+xmpWQAIAgAMAAkK+xmpWQAIAgAAAA==.Mahlaan:BAABNQAECn8/AAIFAAoKIRuwGQA1AgAFAAoKIRuwGQA1AgAAAA==.Malakai:BAAANQADCgIIAgABNQAECggIHQAFACYTAA==.Malekai:BAAANQAECgUJCAABNQAECggIHQAFACYTAA==.Malyce:BAABNQAECn8dAAMFAAgKJhNOQgA1AQAFAAYK2hROQgA1AQABAAgKsg0aYgAcAQAAAA==.Malzen:BAAANQADCgMIAwABNQAECggIHQAFACYTAA==.Manaleia:BAAANQADCggIDAAAAA==.Manasolid:BAAANQADCgEIAQAAAA==.Mar:BAAANQAECgIIAgAAAA==.Maruug:BAAANQADCgYIBgAAAA==.Marvinah:BAAANQAECgIIBwAAAA==.Maydie:BAAANQAECgYIBwAAAA==.',
Me='Meatcurtin:BAAANQAECgUIBgAAAA==.Meatlover:BAAANQAECgcIDgAAAA==.Mediocre:BAABNQAECn8XAAIhAAgK+R7uBwDcAgAhAAgK+R7uBwDcAgAAAA==.Meeshka:BAABNQAECn8xAAIMAAoKJAsXewC2AQAMAAoKJAsXewC2AQAAAA==.Meraleona:BAABNQAECn8dAAIcAAoKRRd2HwA0AgAcAAoKRRd2HwA0AgAAAA==.Methslinger:BAABNQAECn8XAAIPAAoKigSPfwASAQAPAAoKigSPfwASAQAAAA==.',
Mi='Migue:BAAANQABCgEIAgABNQAECgoKXAAGAM8kAA==.Miltonroe:BAAANQADCggICAABNQAECgoKNAAiAIEMAA==.',
Mo='Moarass:BAAANQAECgQJBgABNQAECgoKPAAOAEsYAA==.Moris:BAABNQAECn8oAAMSAAkKzwP2OQDZAAASAAYKwwL2OQDZAAARAAkKTwMQvQDYAAAAAA==.Mortmuzi:BAAANQADCgYJBwAAAA==.Mosrael:BAABNQAECn8XAAIGAAgKCwWCRAGzAAAGAAgKCwWCRAGzAAAAAA==.',
Ms='Mswizzlë:BAABNQAECn8yAAMjAAkKuAnaFwA7AQAMAAgKLAlqlwB2AQAjAAgKegfaFwA7AQAAAA==.',
Mu='Muldah:BAACNQAFFH8HAAIMAAMKWwdYLgC5AAAMAAMKWwdYLgC5AAA1AAQKf1AAAwwACgohGnVKAC8CAAwACgpSGXVKAC8CACMABwrxCV4cAA0BAAAA.Murdersquab:BAAANQADCggICgAAAA==.',
Na='Nas:BAABNQAECn8+AAMRAAoKQiGjIQCMAgARAAkK3iGjIQCMAgASAAEKAB3/KwBQAAAAAA==.Nausicaa:BAAANQABCggIDQAAAA==.Nausicaä:BAAANQADCgUIBQAAAA==.Navie:BAAANQAECgYIDwAAAA==.Nazgûl:BAAANQABCgYIBAAAAA==.',
Ne='Nekros:BAAANQADCgcIBwABNQAECgoKNAAUACAcAA==.Neø:BAABNQAECn85AAMBAAoK5xwtHwBSAgABAAkKyRwtHwBSAgACAAYK5R1KXwCSAQAAAA==.',
Ni='Nianna:BAAANQADCgYIAgAAAA==.Nicebud:BAAANQAECgEIAQAAAA==.Nightsfury:BAAANQAECgYICgAAAA==.Nightshala:BAAANQAECgQIBAAAAA==.',
No='Nollid:BAAANQADCgYIBgABNQAECgkJJgAKAFobAA==.Nornyr:BAAANQADCgEIAQAAAA==.Notforgiven:BAAANQAECgEIAQAAAA==.Notnonna:BAAANQADCgQIBAAAAA==.',
Nu='Nunsrsus:BAAANQAECgcIDwAAAA==.',
Ny='Nymerias:BAAANQADCgYIDgAAAA==.Nyrrah:BAAANQAECgQIBQAAAA==.',
['Ná']='Nácht:BAAANQAECgYICAAAAA==.',
['Ný']='Nýghtmyst:BAAANQAECgEJAQAAAA==.',
Ok='Oku:BAAANQADCgUIBQAAAA==.',
Ol='Olaf:BAAANQAECgIIAgAAAA==.',
Om='Omaticaya:BAABNQAECn9FAAIDAAoKNwvYLwCIAQADAAoKNwvYLwCIAQAAAA==.Omèn:BAAANQADCgUIBQABNQAECgkJGQAGANkYAA==.',
Oo='Oolong:BAAANQADCggICgAAAA==.',
Op='Optikon:BAAANQAECgUIDAAAAA==.',
Or='Oriax:BAAANQAECggIEAABNQAECgoKQgADADAaAA==.',
Os='Oshot:BAAANQADCgMIBAAAAA==.',
Ow='Owlbearcat:BAAANQAECgYIDQABNQAECgcIDwAWAAAAAA==.',
Pa='Packerssuck:BAAANQADCgEIAQAAAA==.Paean:BAAANQADCgcIJwAAAA==.Paj:BAACNQAFFH8LAAMMAAcKbAfTHACYAQAMAAYK+wfTHACYAQAjAAEKMgW+FABJAAA1AAQKf0YAAwwACgq4IxgPABUDAAwACgq4IxgPABUDACMAAgq9HeolAK4AAAAA.Paladenden:BAEANQAECgQIBAABNQAECgcIMQAMADQcAA==.',
Pe='Peata:BAAANQADCgMIAwAAAA==.Pelledrusil:BAAANQADCgUIBQAAAA==.Peria:BAAANQADCgYIDQABNQAECgMICAAWAAAAAA==.',
Pi='Pinga:BAAANQAECggIDQABNQAECgoKLQAHAAcfAA==.',
Pk='Pkalygos:BAABNQAECn8pAAIkAAoKTxIZEQDyAQAkAAoKTxIZEQDyAQAAAA==.',
Pl='Pleione:BAABNQAECn8XAAIYAAkKmhN/hQCGAQAYAAkKmhN/hQCGAQAAAA==.',
Po='Portadave:BAAANQAECgMIBgAAAA==.Powerstrokee:BAAANQAECgYIEAAAAA==.',
Pr='Preyforme:BAABNQAECn85AAIHAAoKxQl8hgCsAQAHAAoKxQl8hgCsAQAAAA==.Prusik:BAAANQADCgcIBwABNQAECgMIAwAWAAAAAA==.Práystation:BAAANQADCgUIBgAAAA==.',
Ps='Psychelone:BAAANQAECgQIBAAAAA==.',
Pu='Puffshot:BAAANQAECgEIAQABNQAECgoKKQAIAAkbAA==.Puurseus:BAAANQABCgYIBwABNQAECggIFQASAMASAA==.',
Qu='Quillan:BAAANQADCgUIDQABNQAECgcIDwAWAAAAAA==.',
Qy='Qyxh:BAABNQAECn8iAAMKAAoK/A1bQgCuAQAKAAoK/A1bQgCuAQAXAAIKggMeMQA4AAAAAA==.',
Ra='Raine:BAAANQAECgEIAQAAAA==.Rannath:BAAANQAECggIAwABNQAECggIFwAGAAsFAA==.Rastafarian:BAAANQADCgUICQAAAA==.',
Re='Redeye:BAAANQAECgQIBQAAAA==.Rehne:BAAANQAECgEIAQAAAA==.Rexhavoc:BAACNQAFFH8HAAIEAAMKbRURCADhAAAEAAMKbRURCADhAAA1AAQKfzYAAgQACgrTHtMJALcCAAQACgrTHtMJALcCAAAA.Rexion:BAAANQAECgEIAQAAAA==.',
Ri='Rigormortits:BAAANQAECgQIBAAAAA==.Ripre:BAAANQADCgUICwAAAA==.',
Ro='Rosary:BAABNQAECn8kAAINAAcKQQX5MQAPAQANAAcKQQX5MQAPAQAAAA==.Rosewoodren:BAAANQAECgMIAgAAAA==.',
Ru='Ruint:BAAANQADCgUIBQAAAA==.Runeclad:BAABNQAECn8ZAAICAAoKLxgTRQAFAgACAAoKLxgTRQAFAgAAAA==.',
Ry='Ryla:BAAANQADCgIIAgABNQAECgoKMgAIABEaAA==.',
['Rï']='Rïvkah:BAAANQADCgUIBwABNQAECgQIBQAWAAAAAA==.',
Sa='Saauurrora:BAAANQADCgYIBgAAAA==.Saintshift:BAAANQADCgEIAQABNQAECgMIAwAWAAAAAA==.Salitheion:BAAANQAECgMIBAAAAA==.Sapper:BAABNQAECn9MAAIlAAoK3CIoAwCCAwAlAAoK3CIoAwCCAwAAAA==.Sarn:BAAANQAECgEIAQAAAA==.Sathi:BAAANQAECgIIAQAAAA==.Sayuri:BAAANQADCgEIAQAAAA==.',
Se='Sennest:BAAANQADCgUIAwAAAA==.',
Sh='Shadowmoocow:BAAANQAECgEIAQABNQAECgQIDAAWAAAAAA==.Shikí:BAAANQAECgIIBAAAAA==.Shladoran:BAABNQAECn9AAAIUAAoKJA25cQCtAQAUAAoKJA25cQCtAQAAAA==.Shos:BAABNQAECn88AAIVAAoKwh+pBgCVAgAVAAoKwh+pBgCVAgAAAA==.Shuttsyy:BAAANQADCgMIAwAAAA==.',
Si='Siberianwolf:BAABNQAECn8XAAIHAAoKMRlUOwBiAgAHAAoKMRlUOwBiAgAAAA==.Sinnister:BAAANQADCgYIBgAAAA==.Sitruc:BAABNQAECn8VAAMIAAkKhxEMDgDpAQAIAAkKhxEMDgDpAQAmAAEKxwIZ6gAaAAAAAA==.',
Sk='Skully:BAAANQADCgUIBQABNQAFFAMIBgANAHkeAA==.',
Sl='Sledge:BAAANQADCgMIAwAAAA==.',
Sn='Snapdragyn:BAAANQAECgQIAQAAAA==.Snorina:BAABNQAECn89AAInAAoKriCXDQATAwAnAAoKriCXDQATAwAAAA==.',
So='Solàrflàré:BAAANQADCgMIAwAAAA==.Sosgoraan:BAAANQADCgcJBwABNQAECgoKPwAFACEbAA==.Sosozen:BAABNQAECn8tAAIcAAoKbgk/KwA+AQAcAAoKbgk/KwA+AQAAAA==.Soul:BAACNQAFFH8HAAQNAAIK+BFWBwB1AAAhAAIKAQtwAwB2AAANAAIK+BFWBwB1AAADAAIKeQGpIgBLAAA1AAQKfz4ABA0ACgrJHlUIAMACAA0ACgrJHlUIAMACACEACgqdFRYMABICAAMABQqLBFliAJsAAAAA.',
Sp='Spiketurtle:BAAANQAECgMIAwAAAA==.Spirittoast:BAAANQAECgEIAQAAAA==.',
Sq='Squidwrd:BAAANQADCgEIAQAAAA==.',
Sr='Sriman:BAAANQAECgYIBgAAAA==.',
St='Starkiller:BAAANQADCgYIDgAAAA==.Stonesolid:BAABNQAECn9JAAMUAAoKpxvAMgBzAgAUAAoKpxvAMgBzAgAeAAMKKRG2HwCwAAAAAA==.Stratovarius:BAAANQADCgYIBgAAAA==.',
Su='Sugouri:BAAANQAECggICAAAAA==.Summerrosez:BAAANQADCgEIAgAAAA==.Sunnyginger:BAABNQAECn8ZAAIMAAkKswWtrgBHAQAMAAkKswWtrgBHAQAAAA==.Supremacy:BAABNQAECn8oAAMRAAoKUybzCwBtAwARAAoKUybzCwBtAwASAAEKzSE4YwBeAAAAAA==.',
Sw='Sweetspot:BAAANQAECgcIDgABNQAECgoKIAAfAKQLAA==.Swiftshammy:BAAANQADCgQIBAAAAA==.Swytch:BAABNQAECn8yAAIIAAoKERq8CgArAgAIAAoKERq8CgArAgAAAA==.',
Sy='Sylrytherin:BAAANQADCgYICgABNQAECgoKPQAnAK4gAA==.Sylvii:BAABNQAECn8pAAMOAAgKFROfKQDSAQAOAAgKFROfKQDSAQADAAEKAADQpgAAAAAAAA==.',
Ta='Tabor:BAAANQAECgQIBwAAAA==.Taggz:BAAANQABCgQIBAAAAA==.Taladryn:BAAANQADCgcIDQAAAA==.Tammyfaye:BAAANQADCgMIBAABNQAECggILgACALoKAA==.Tarahly:BAABNQAECn80AAIJAAkKrCE5GwDfAgAJAAkKrCE5GwDfAgAAAA==.Tauryel:BAAANQAECgQIBwABNQAECgcIDAAWAAAAAA==.',
Te='Tekhan:BAAANQADCgQIBAAAAA==.Tethlis:BAAANQADCggICAABNQAECgoKGgANACAgAA==.',
Th='Thasarias:BAAANQAECgUIBwAAAA==.Themoosifer:BAACNQAFFH8ZAAIEAAgKRBgSAgBhAgAEAAgKRBgSAgBhAgA1AAQKfzkAAgQACgr5IxUOAAcDAAQACgr5IxUOAAcDAAAA.Thunderdump:BAABNQAECn8pAAIdAAkKNBrXTAAwAgAdAAkKNBrXTAAwAgAAAA==.Thyck:BAABNQAECn8eAAIHAAkKihEgcgAtAgAHAAkKihEgcgAtAgAAAA==.Thydis:BAABNQAECn9BAAIGAAoKGBB7nQCSAQAGAAoKGBB7nQCSAQAAAA==.',
Ti='Tiancit:BAAANQADCgEIAQAAAA==.Tibbs:BAABNQAECn85AAMaAAoKEg58FQD1AQAaAAgK4Q98FQD1AQAZAAkKjQxXCwBIAQAAAA==.Ticklepickle:BAAANQAECgQICAAAAA==.',
To='Torluis:BAAANQADCgMIAwAAAA==.',
Tr='Trumalice:BAAANQADCggIGgAAAA==.',
Tu='Tulpa:BAAANQABCgYIDAAAAA==.',
Ty='Tyrmarlq:BAAANQAECgQIBAAAAA==.',
Un='Uncorrupted:BAABNQAECn8dAAMfAAkKTxM8KQCTAQAfAAgKIBY8KQCTAQAGAAIKigQ2sQEvAAAAAA==.',
Up='Updog:BAAANQAECgEIAQABNQAECgQICAAWAAAAAA==.',
Va='Vaelm:BAAANQADCgcICgAAAA==.Valericia:BAAANQADCgQIBAAAAA==.Valindrux:BAABNQAECn85AAMjAAoKyxfbFABGAQAMAAkKIBNj0QDjAQAjAAUKdhjbFABGAQAAAA==.Valjin:BAAANQADCgQIBAABNQAECgoKOQAjAMsXAA==.Valuryan:BAAANQAECgUICAABNQAECgoKOQAjAMsXAA==.Vasdepherens:BAAANQAECgcIBwAAAA==.',
Ve='Velathila:BAAANQAECgMIBQAAAA==.',
Vi='Victorsith:BAAANQADCgMIAwAAAA==.Violêt:BAAANQADCgYIBgAAAA==.Vizzelok:BAABNQAECn8eAAILAAgKZxBDCgDVAQALAAgKZxBDCgDVAQAAAA==.',
Vo='Voidchris:BAABNQAECn9PAAMEAAoK7x4bEADxAgAEAAoKoxwbEADxAgAKAAoK1hokFQB0AgAAAA==.Voidormu:BAAANQAECgUIEQAAAA==.',
Wa='Warelf:BAABNQAECn8UAAMRAAkKICHJJgDpAgARAAkKICHJJgDpAgASAAEKUxFBdAA6AAAAAA==.Warleck:BAABNQAECn8WAAIRAAgKjQ3HhwBOAQARAAgKjQ3HhwBOAQAAAA==.Waroo:BAAANQADCgIIAwAAAA==.',
Wh='Whodey:BAAANQAECgUIDQABNQAECggIHQAFACYTAA==.',
Wi='Wisp:BAAANQADCgYIEQAAAA==.',
Wo='Wompadonk:BAAANQAECgcIBwABNQAFFAMIBgANAHkeAA==.',
Wy='Wylia:BAABNQAECn8iAAIMAAoKuBD9ZgDmAQAMAAoKuBD9ZgDmAQAAAA==.',
Xc='Xcw:BAAANQAECgIIAgAAAA==.',
Yy='Yyirium:BAAANQADCgIIAgAAAA==.',
Za='Zakkmorris:BAAANQADCgEIAQAAAA==.Zakuren:BAABNQAECn9eAAIHAAoKzxuyKACdAgAHAAoKzxuyKACdAgAAAA==.',
Zi='Ziggi:BAAANQADCgYIBgABNQAECgMIAwAWAAAAAA==.',
Zo='Zondoul:BAAANQADCgYIBgAAAA==.',
Zu='Zugnator:BAABNQAECn8YAAIUAAoKlxRYQwA3AgAUAAoKlxRYQwA3AgAAAA==.',
Zy='Zylera:BAAANQAECgMIAgAAAA==.Zyphor:BAAANQADCggIDQAAAA==.',
['Éd']='Édwina:BAAANQADCgEIAgAAAA==.',
['Él']='Élvira:BAAANQADCgEIAQAAAA==.',
['Ñî']='Ñîx:BAAANQAECgcIEwAAAA==.',
['Òm']='Òmêñ:BAABNQAECn8ZAAIGAAkK2RgaaAABAgAGAAkK2RgaaAABAgAAAA==.',
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
