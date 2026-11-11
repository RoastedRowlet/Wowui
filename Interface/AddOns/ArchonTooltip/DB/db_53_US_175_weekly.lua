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

local lookup = {'DeathKnight-Frost','DeathKnight-Unholy','Druid-Balance','DemonHunter-Devourer','DeathKnight-Blood','Paladin-Retribution','Hunter-BeastMastery','Rogue-Assassination','Paladin-Holy','DemonHunter-Havoc','Warlock-Affliction','Mage-Arcane','Druid-Guardian','Druid-Restoration','Shaman-Elemental','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','Monk-Brewmaster','Warrior-Arms','Warrior-Protection','Unknown-Unknown','DemonHunter-Vengeance','Priest-Holy','Evoker-Augmentation','Evoker-Devastation','Mage-Fire','Monk-Windwalker','Shaman-Restoration','Warrior-Fury','Paladin-Protection','Priest-Discipline','Druid-Feral','Shaman-Enhancement','Mage-Frost','Evoker-Preservation','Monk-Mistweaver','Priest-Shadow',}
local provider = {region='US',realm="Quel'dorei",name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abiotic:BAAANQADCgQIBQAAAA==.Abugslife:BAAANQADCgIIAgAAAA==.',
Ac='Acaleus:BAAANQAECgQIBAAAAA==.Acesup:BAAANQAECgEIAwAAAA==.',
Ad='Adric:BAAANQAECggIEgAAAA==.Aduhgall:BAAANQADCgcIDQAAAA==.',
Ah='Ahnji:BAAANQADCgMIBAAAAA==.',
Ai='Aings:BAABNQAECn84AAMBAAoK1SPgEwDuAgABAAoKnyPgEwDuAgACAAgKDiG4GwDmAgAAAA==.Ainzoulgown:BAAANQAECgUICAAAAA==.Aiydaen:BAAANQADCgQIAwAAAA==.Aiytan:BAAANQADCgMIAwAAAA==.',
Al='Alarus:BAABNQAECn9CAAIDAAoKMBpYHAAOAgADAAoKMBpYHAAOAgAAAA==.Aldith:BAAANQAECgEIAgAAAA==.Alex:BAABNQAECn8vAAIEAAoKDRUiGQCSAgAEAAoKDRUiGQCSAgAAAA==.Alivathor:BAAANQAECgIIAgABNQAECgkJKQAFANUWAA==.Allypally:BAABNQAECn8eAAIGAAkKYQz2wQCYAQAGAAkKYQz2wQCYAQAAAA==.Althorian:BAAANQAECggIDwAAAA==.',
Am='Amgrod:BAEANQADCgUIBQAAAA==.Amway:BAAANQAECgQICwAAAA==.',
An='Andaarian:BAAANQADCgUIBQAAAA==.Angelkitty:BAAANQADCgYIBgAAAA==.',
Ap='Apophiz:BAAANQADCgYIBgAAAA==.',
Ar='Arcadius:BAAANQADCgIIAgAAAA==.Aremis:BAAANQAECgYIEgAAAA==.Arkaid:BAABNQAECn8YAAIHAAkKsxRKQABCAgAHAAkKsxRKQABCAgAAAA==.Arkhitype:BAABNQAECn8cAAIIAAgKsBctJQBhAgAIAAgKsBctJQBhAgAAAA==.Arteras:BAAANQAECgQICAAAAA==.Aryadel:BAAANQABCgQIBAAAAA==.Aryahi:BAAANQAECggIAQAAAA==.',
As='Ashyslashy:BAABNQAECn8bAAMGAAoKrBZOfQAvAgAGAAkK0RdOfQAvAgAJAAYKpxDBtwANAQAAAA==.Asur:BAABNQAECn83AAIGAAoKUhGBZAD3AQAGAAoKUhGBZAD3AQAAAA==.',
Au='Auracorusca:BAABNQAECn8lAAMJAAoKhB/eKQDAAgAJAAoKhB/eKQDAAgAGAAEK2gVWrgEwAAAAAA==.Aurafarmer:BAAANQAECgUIBQAAAA==.Auris:BAAANQADCgQIBAAAAA==.',
Ay='Aydain:BAAANQADCgQIBAAAAA==.Aynilith:BAABNQAECn8aAAIKAAoK9QhnPgAoAQAKAAoK9QhnPgAoAQAAAA==.Aystarael:BAAANQAECggIEQAAAA==.',
Ba='Bajr:BAABNQAECn8rAAIHAAoK6Q23cgC+AQAHAAoK6Q23cgC+AQAAAA==.Bakura:BAABNQAECn8oAAILAAoKChnvBACBAgALAAoKChnvBACBAgAAAA==.Banker:BAABNQAECn80AAIEAAoKZg15IgB0AQAEAAoKZg15IgB0AQAAAA==.Baroo:BAAANQAECgQICQAAAA==.Barudd:BAAANQABCgQIBAAAAA==.',
Be='Berko:BAABNQAECn9NAAIMAAoKBB86OwBPAgAMAAoKBB86OwBPAgAAAA==.Beyorne:BAAANQAECgIIAQAAAA==.',
Bh='Bhaang:BAAANQAECgYIDgAAAA==.',
Bi='Bigbear:BAACNQAFFH8GAAMNAAMKeR5bAgANAQANAAMKeR5bAgANAQAOAAEKFwskFwA7AAA1AAQKfx4AAg0ACQpXJqkAAIgDAA0ACQpXJqkAAIgDAAAA.Bigbill:BAAANQAECgQIBAAAAA==.Bigdeath:BAABNQAECn8fAAIPAAcKXhZAiACQAQAPAAcKXhZAiACQAQAAAA==.Biletooth:BAAANQAECgcIDAABNQAECgcILQACAM0KAA==.Bizco:BAABNQAECn8tAAMHAAoKBx9DNABmAgAHAAoKBx9DNABmAgAQAAIKaQl6ZgAwAAAAAA==.',
Bj='Bjebo:BAABNQAECn8rAAIDAAoKbQxMRADiAQADAAoKbQxMRADiAQAAAA==.',
Bl='Bluffshot:BAABNQAECn8pAAIIAAoKCRvGFADVAgAIAAoKCRvGFADVAgAAAA==.',
Br='Brutes:BAAANQADCggICAABNQAFFAMIBgABAJsgAA==.Brynjalf:BAAANQAECgQIBwAAAA==.Bràe:BAAANQABCgMIAQAAAA==.',
Bx='Bxck:BAAANQAECgEIAQAAAA==.',
['Bï']='Bïcho:BAACNQAFFH8KAAMRAAUKvQ6uIwCWAAARAAQKFBKuIwCWAAALAAEKEAhGFQBHAAA1AAQKfy4AAxEACgqFIZYaAKMCABEACgqFIZYaAKMCABIAAgq1C+tlAFcAAAAA.',
Ca='Calambar:BAAANQADCgYIBgAAAA==.Cas:BAAANQADCgYIBgAAAA==.Casally:BAAANQADCgYICgAAAA==.Cascadio:BAAANQAECgIIAgAAAA==.Castanza:BAAANQADCgQIBwAAAA==.Caswyn:BAABNQAECn8gAAITAAYKVRS9EgDiAAATAAYKVRS9EgDiAAAAAA==.',
Ch='Chapjong:BAAANQADCgQIBQAAAA==.Charjer:BAABNQAECn8wAAMUAAgKGR7WTQCgAgAUAAgKGR7WTQCgAgAVAAMK2BUqMQBtAAAAAA==.Chokengag:BAAANQADCgMIAwAAAA==.Choney:BAAANQAECgcICAAAAA==.',
Co='Codedgar:BAAANQADCgUIBQABNQAECgcIDwAWAAAAAA==.Coffeeshot:BAAANQADCgcIDQAAAA==.Cojostudio:BAAANQADCggICAABNQAECgoKKQAHACcbAA==.Comboost:BAAANQAECgQIDAAAAA==.Costcolshirt:BAAANQAECgEIAQAAAA==.',
Cr='Cranks:BAAANQAECgcIEQAAAA==.Crashcake:BAABNQAECn8lAAIBAAoKqB20FQCRAgABAAoKqB20FQCRAgAAAA==.Creakybones:BAAANQAECgEIAwAAAA==.Croager:BAABNQAECn8ZAAIHAAoKOhy4MQDXAgAHAAoKOhy4MQDXAgABNQAECgkJGQAGANkYAA==.',
Cu='Cup:BAABNQAECn8vAAMJAAoKARKbcgDAAQAJAAoKARKbcgDAAQAGAAEKIBArdwFAAAAAAA==.',
Cv='Cvv:BAAANQADCgQIBAABNQAECgMIAwAWAAAAAA==.',
Cy='Cyberlinde:BAAANQAECgQIEwAAAA==.Cywen:BAAANQADCggICAABNQAFFAgIGgAIAKUcAA==.',
Da='Daelaris:BAABNQAECn8nAAIMAAoKxh9aQAAFAwAMAAoKxh9aQAAFAwAAAA==.Damonoris:BAABNQAECn8kAAIHAAoK6g6jcwC8AQAHAAoK6g6jcwC8AQAAAA==.Damthrax:BAAANQAECgQIBQAAAA==.Danielan:BAAANQAECgcICgAAAA==.Davegrôwl:BAAANQADCgEJAQABNQAECgcILQACAM0KAA==.',
De='Deadair:BAAANQADCgcICAAAAA==.Deadlyalba:BAAANQADCgYIBgAAAA==.Deadzeo:BAAANQADCgYICQAAAA==.Demonblades:BAABNQAECn85AAIEAAoKqhnBHABvAgAEAAoKqhnBHABvAgAAAA==.Demonbreaker:BAABNQAECn8xAAIXAAkKjRfrCADJAQAXAAkKjRfrCADJAQAAAA==.Demonnight:BAAANQAECgIIAgAAAA==.Denarten:BAABNQAECn8hAAIGAAkKvSFYJgAsAwAGAAkKvSFYJgAsAwAAAA==.Deseth:BAAANQAECgcICQAAAA==.',
Di='Diotima:BAAANQADCggIEQAAAA==.Dirtymorris:BAAANQAECgcIEQAAAA==.Disrupt:BAAANQAECgQICAAAAA==.',
Do='Dockevorkian:BAACNQAFFH8QAAIYAAQKxBrxFgAtAQAYAAQKxBrxFgAtAQA1AAQKf0AAAhgACgodIXQXABoDABgACgodIXQXABoDAAAA.Dornaaealdor:BAAANQADCgIIAgAAAA==.Dortwaz:BAACNQAFFH8GAAIRAAQKJArvJgCIAAARAAQKJArvJgCIAAA1AAQKfzgAAxEACgqEHSAyADcCABEACQoJHiAyADcCABIAAgoUF41UAIEAAAAA.Doublebonus:BAAANQADCggICAABNQAFFAMIBgABAJsgAA==.Dougdk:BAABNQAECn80AAIFAAoKLCRwAwC6AwAFAAoKLCRwAwC6AwABNQAFFAMIBgANAHkeAA==.',
Dr='Dracoramonk:BAAANQAECgEIAQAAAA==.Dracoz:BAAANQADCgEIAQAAAA==.Dricex:BAAANQADCgYIBgABNQAECgMIBgAWAAAAAA==.Drinnagon:BAAANQADCgcIBwABNQAECgkJIQAGAL0hAA==.Drinntellect:BAAANQAECgMIAwABNQAECgkJIQAGAL0hAA==.Drinnundead:BAAANQADCgEIAQABNQAECgkJIQAGAL0hAA==.Druelf:BAAANQADCgUIBQAAAA==.Dryblood:BAAANQADCgQIBAAAAA==.Dryx:BAAANQAECgIIAgAAAA==.',
Du='Dunaarn:BAAANQADCgMIAwAAAA==.',
Ea='Eargroan:BAAANQADCgYICwABNQAECgoKJgAXAFgjAA==.',
El='Elilla:BAABNQAECn8xAAIFAAoKJAscNQBkAQAFAAoKJAscNQBkAQAAAA==.Elkminster:BAAANQAECgMIBQAAAA==.Ellenaya:BAABNQAECn8VAAIJAAoKAhAeXgD+AQAJAAoKAhAeXgD+AQAAAA==.Elorela:BAAANQADCgQIBAABNQAECgoKIwASAIkZAA==.',
En='Enjoy:BAACNQAFFH8GAAIBAAMKmyBuDgD0AAABAAMKmyBuDgD0AAA1AAQKfyYAAwEACQoYJegHAGcDAAEACQqSJOgHAGcDAAIACQqPIm4nAJ0CAAAA.',
Fa='Famiki:BAAANQADCgcICwAAAA==.',
Fe='Feardotcom:BAAANQABCgIIAgAAAA==.Felnollid:BAABNQAECn8mAAMKAAkKWhuWHAC1AgAKAAkKWhuWHAC1AgAEAAUKewdWTQDxAAAAAA==.Fenanigans:BAABNQAECn8iAAIIAAkKeiDUCwApAwAIAAkKeiDUCwApAwAAAA==.Fenquisition:BAAANQADCggICAABNQAECgkJIgAIAHogAA==.',
Fi='Firebender:BAAANQADCgQIBQAAAA==.Firetiger:BAAANQADCgcIBwAAAA==.Fistandcider:BAAANQADCggICQAAAA==.',
Fl='Fluffyhusky:BAABNQAECn8iAAMZAAcK4ATGFgDHAAAaAAcKnQTXJgD+AAAZAAUKhAfGFgDHAAABNQAFFAIIBQAHAMcDAA==.',
Fo='Fontss:BAAANQAECggICQAAAA==.Fonyfish:BAACNQAFFH8IAAIRAAUK3gxEIgDnAAARAAUK3gxEIgDnAAA1AAQKfyMAAhEACQryGeBMANsBABEACQryGeBMANsBAAAA.Forba:BAAANQAECgYIBgAAAA==.',
Fr='Frostybina:BAAANQADCgMIAwAAAA==.Froztfire:BAAANQAECgQICAABNQAFFAMIBQAbAAMNAA==.',
Fu='Fubina:BAEBNQAECn9CAAMcAAoKZR+kDgD2AgAcAAoKZR+kDgD2AgATAAIK5R0zJgCcAAAAAA==.',
Fy='Fyjalla:BAAANQADCggIEAAAAA==.',
['Fâ']='Fâllênknîght:BAABNQAECn8pAAIFAAkK1Rb7IwDMAQAFAAkK1Rb7IwDMAQAAAA==.',
Ga='Gabh:BAAANQADCgYIBgAAAA==.Gandoorr:BAAANQAECgIIAgAAAA==.',
Gi='Gilgaglaive:BAABNQAECn8YAAIEAAkKIxYFHQBsAgAEAAkKIxYFHQBsAgAAAA==.',
Gl='Glomah:BAABNQAECn83AAMFAAoKXyFFEwATAwAFAAkK9yFFEwATAwABAAcKqx34KQD5AQAAAA==.Glorm:BAABNQAECn9DAAIdAAoKlhl3HQC5AgAdAAoKlhl3HQC5AgAAAA==.',
Go='Gobropro:BAAANQADCgYIBgAAAA==.Gorathan:BAAANQADCgMIAwAAAA==.Gotalock:BAAANQAECgMIBAAAAA==.',
Gr='Grabbyhands:BAABNQAECn8tAAQCAAcKzQpKRQDjAAACAAcKMQhKRQDjAAAFAAYKyQhRZACqAAABAAIK3ACcwAAIAAAAAA==.Grantul:BAABNQAECn87AAIeAAoKrhi9BgA+AgAeAAoKrhi9BgA+AgAAAA==.Grimthore:BAAANQAECgcIDgABNQAECgoKHwAfAJMKAA==.Grolgan:BAAANQADCgYIBgAAAA==.Gromz:BAABNQAECn8UAAIRAAoK3xSTSgBzAgARAAoK3xSTSgBzAgAAAA==.',
Gu='Gulbhang:BAABNQAECn8xAAMRAAoKdh5+MwC7AgARAAoKdh5+MwC7AgASAAEKXA+cdgA3AAAAAA==.',
Ha='Hakiranatha:BAAANQADCggICAAAAA==.Harkelanu:BAAANQAECgIIAgAAAA==.',
Hb='Hbkdx:BAABNQAECn8eAAIHAAYKrQZM4gDRAAAHAAYKrQZM4gDRAAAAAA==.',
He='Health:BAAANQAECgMIAwAAAA==.',
Ho='Holdi:BAAANQADCgYIBgABNQAECgkJJQAGANcOAA==.Holyhammer:BAAANQAECggIDgAAAA==.Holyoke:BAAANQADCgEIAQAAAA==.Homunculus:BAAANQAECgUICQAAAA==.',
Hu='Hujo:BAABNQAECn8eAAIUAAkKXxF4iwD/AQAUAAkKXxF4iwD/AQAAAA==.Hushpupi:BAABNQAECn8jAAMSAAoKiRkXCAB+AgASAAoKiRkXCAB+AgARAAQKKApF+wDVAAAAAA==.Huskerpower:BAAANQADCgcJDQAAAA==.',
Ic='Iceharted:BAAANQAECgMIAwAAAA==.Icesloth:BAABNQAECn8lAAIPAAoKGBfyUgAtAgAPAAoKGBfyUgAtAgAAAA==.',
Id='Idamarie:BAABNQAECn8aAAIPAAcKGgKy9QCpAAAPAAcKGgKy9QCpAAAAAA==.Iduun:BAAANQADCgEIAQAAAA==.',
Il='Iladelle:BAABNQAECn8qAAIEAAoKixJ7GgDFAQAEAAoKixJ7GgDFAQAAAA==.',
Io='Iorak:BAAANQADCgEIAQAAAA==.',
Ir='Irinon:BAAANQADCgcIDAAAAA==.',
Ix='Ixiya:BAAANQAECgQIBgAAAA==.',
Ja='Jafud:BAAANQAFFAEIAQABNQAFFAYIGAAFAGIZAA==.Jafuds:BAAANQAFFAMIAwABNQAFFAYIGAAFAGIZAA==.Jaggerss:BAAANQAECgEIAQABNQAFFAMIBgABAJsgAA==.Jamaican:BAAANQADCgYIEAAAAA==.Jaste:BAABNQAECn8fAAIYAAgKhw7BgAA+AQAYAAgKhw7BgAA+AQAAAA==.',
Ji='Jimit:BAAANQADCgcIBwAAAA==.Jimmym:BAABNQAECn8iAAIGAAYKHwX+HwGmAAAGAAYKHwX+HwGmAAAAAA==.Jirakaidae:BAAANQADCgYICwABNQAECgYIEgAWAAAAAA==.',
Jo='Jordis:BAABNQAECn8XAAIKAAkKfQxSMAB9AQAKAAkKfQxSMAB9AQAAAA==.',
Ju='Juicyfists:BAAANQADCgMIAwAAAA==.Juju:BAAANQAECgEIAQAAAA==.',
Ka='Kaedeyn:BAABNQAECn8ZAAMYAAkKiQjoZACYAQAYAAkKiQjoZACYAQAgAAEK6gFoHQAdAAAAAA==.Kaeltharon:BAAANQADCgQIAwAAAA==.Kairos:BAAANQADCggICAAAAA==.Kamekaze:BAAANQADCgYIBgAAAA==.Kandrys:BAAANQADCgQIBAAAAA==.Kasgotojim:BAAANQAECgQIBAAAAA==.Kaypop:BAAANQAECgQIBQAAAA==.Kayy:BAAANQADCgIIAgAAAA==.',
Ke='Kerrster:BAAANQADCgQIBAAAAA==.',
Kh='Khármá:BAABNQAECn8oAAIfAAgK2xm0FgCwAQAfAAgK2xm0FgCwAQAAAA==.',
Ki='Kicklocks:BAAANQAECgMIAgAAAA==.Kikuri:BAAANQAECggIDQAAAA==.Killt:BAABNQAECn8xAAIdAAoK0h2MHADAAgAdAAoK0h2MHADAAgAAAA==.',
Kl='Klondite:BAAANQAECgEIAgAAAA==.',
Ko='Koojoé:BAAANQAECgQIBQAAAA==.',
Ku='Kurzulan:BAABNQAECn8iAAQOAAoKeg2bOgBLAQAOAAgKdgebOgBLAQADAAUKtganWQCoAAANAAMK5wN/VQBQAAAAAA==.',
La='Laal:BAAANQAECgIIAgAAAA==.Laghles:BAACNQAFFH8GAAIHAAMK8hHtEwDiAAAHAAMK8hHtEwDiAAA1AAQKf1YAAgcACgp2IGkgABYDAAcACgp2IGkgABYDAAAA.Laroes:BAAANQAECgEIAQABNQAECgoKNwAFAF8hAA==.Larua:BAAANQABCgQJBAAAAA==.',
Le='Lemanjá:BAABNQAECn8oAAIQAAkKCAcoIQBPAQAQAAkKCAcoIQBPAQAAAA==.',
Li='Lightlooter:BAAANQADCgYIBgAAAA==.Liliane:BAABNQAECn8YAAIGAAoKEBK+pADXAQAGAAoKEBK+pADXAQAAAA==.Limbless:BAAANQAECgcIDgAAAA==.',
Lo='Loahealth:BAAANQAECgcIDwAAAA==.Lockrocks:BAABNQAECn85AAQLAAoKiBZuDQCDAQARAAoKThVpSADpAQALAAYK3g9uDQCDAQASAAUKCAfzLwAJAQABNQAECgoKHwAfAJMKAA==.Lockstar:BAAANQADCgYIDAAAAA==.Loko:BAABNQAECn8pAAIdAAoKowsFTwC/AQAdAAoKowsFTwC/AQAAAA==.Lontra:BAAANQADCgUIDAAAAA==.Loozer:BAABNQAECn8fAAMfAAoKkwpeOQAiAQAGAAgKGgmD7wA9AQAfAAgK9AdeOQAiAQAAAA==.Loralast:BAAANQADCgQIBAAAAA==.',
Lu='Luzifer:BAAANQADCgYIBgAAAA==.',
Ma='Magelyman:BAABNQAECn8lAAIMAAkK+xnaUgAKAgAMAAkK+xnaUgAKAgAAAA==.Mahlaan:BAABNQAECn87AAIFAAoKlBpeGAAyAgAFAAoKlBpeGAAyAgAAAA==.Malakai:BAAANQADCgIIAgABNQAECggIFgAFALsRAA==.Malekai:BAAANQAECgUJCAABNQAECggIFgAFALsRAA==.Malyce:BAABNQAECn8WAAMFAAgKuxFVSwABAQABAAgKAQkaYgAcAQAFAAUKQRZVSwABAQAAAA==.Malzen:BAAANQADCgMIAwABNQAECggIFgAFALsRAA==.Manaleia:BAAANQADCggIDAAAAA==.Manasolid:BAAANQADCgEIAQAAAA==.Mar:BAAANQAECgIIAgAAAA==.Maruug:BAAANQADCgYIBgAAAA==.Marvinah:BAAANQAECgIIBwAAAA==.Maydie:BAAANQAECgcICAAAAA==.',
Me='Meatcurtin:BAAANQAECgUIBwAAAA==.Meatlover:BAAANQAECgcIEAAAAA==.Mediocre:BAABNQAECn8XAAIhAAgK+R7uBwDcAgAhAAgK+R7uBwDcAgAAAA==.Meeshka:BAABNQAECn8rAAIMAAoK8ArPdACyAQAMAAoK8ArPdACyAQAAAA==.Meraleona:BAABNQAECn8dAAIcAAoKRRd2HwA0AgAcAAoKRRd2HwA0AgAAAA==.Methslinger:BAAANQAECggIEQAAAA==.',
Mi='Migue:BAAANQABCgEIAgABNQAECgoKWAAGALskAA==.Miltonroe:BAAANQADCggICAABNQAECgoKMQAiAB0MAA==.',
Mo='Moarass:BAAANQAECgQJBgABNQAECgoKOAAOAEsYAA==.Moris:BAABNQAECn8oAAMSAAkKzwP2OQDZAAARAAkKTwPysgDZAAASAAYKwwL2OQDZAAAAAA==.Mortmuzi:BAAANQADCgYJBwAAAA==.Mosrael:BAABNQAECn8XAAIGAAgKCwUDLAGWAAAGAAgKCwUDLAGWAAAAAA==.',
Ms='Mswizzlë:BAABNQAECn8rAAMjAAkK0gfaFwA7AQAMAAgKYwbbnQBWAQAjAAgKegfaFwA7AQAAAA==.',
Mu='Muldah:BAACNQAFFH8HAAIMAAMKWwdNKQDCAAAMAAMKWwdNKQDCAAA1AAQKf1AAAwwACgohGqtEADECAAwACgpSGatEADECACMABwrxCV4cAA0BAAAA.Murdersquab:BAAANQADCggICgAAAA==.',
Na='Nas:BAABNQAECn8+AAMRAAoKQiGEHQCTAgARAAkK3iGEHQCTAgASAAEKAB1xKQBRAAAAAA==.Nausicaa:BAAANQAECgEIAQAAAA==.Nausicaä:BAAANQADCgUIBQAAAA==.Navie:BAAANQAECgYIDwAAAA==.Nazgûl:BAAANQABCgYIBAAAAA==.',
Ne='Nekros:BAAANQADCgcIBwABNQAECggIMAAUABkeAA==.Neø:BAABNQAECn8yAAMBAAoK0RzAHABTAgABAAkKshzAHABTAgACAAYK5R1KXwCSAQAAAA==.',
Ni='Nianna:BAAANQADCgYIAQAAAA==.Nicebud:BAAANQAECgEIAQAAAA==.Nightsfury:BAAANQAECgYICwAAAA==.Nightshala:BAAANQAECgQIBAAAAA==.',
No='Nollid:BAAANQADCgYIBgABNQAECgkJJgAKAFobAA==.Nordburg:BAAANQAECgEIAQAAAA==.Nornyr:BAAANQADCgEIAQAAAA==.Notforgiven:BAAANQAECgEIBAAAAA==.Notnonna:BAAANQAECgEIAQAAAA==.',
Nu='Nunsrsus:BAAANQAECgcIDwAAAA==.',
Ny='Nymerias:BAAANQADCgYIDgAAAA==.Nyrrah:BAAANQAECgQIBQAAAA==.',
['Ná']='Nácht:BAAANQAECgYICAAAAA==.',
['Ný']='Nýghtmyst:BAAANQAECgEJAQAAAA==.',
Ok='Oku:BAAANQADCgUIBQAAAA==.',
Ol='Olaf:BAAANQAECgIIAgAAAA==.',
Om='Omaticaya:BAABNQAECn88AAIDAAkKzAlnOAA8AQADAAkKzAlnOAA8AQAAAA==.Omèn:BAAANQADCgUIBQABNQAECgkJGQAGANkYAA==.',
Oo='Oolong:BAAANQADCggICgAAAA==.',
Op='Optikon:BAAANQAECgUIDAAAAA==.',
Or='Oriax:BAAANQAECggIEgABNQAECgoKQgADADAaAA==.',
Ow='Owlbearcat:BAAANQAECgYIDQABNQAECgcIDwAWAAAAAA==.',
Pa='Packerssuck:BAAANQADCgEIAQAAAA==.Paean:BAAANQADCgcIJgAAAA==.Paj:BAACNQAFFH8LAAMMAAcKbAfTHACYAQAMAAYK+wfTHACYAQAjAAEKMgXPEgBJAAA1AAQKf0UAAwwACgq4I2gNABkDAAwACgq4I2gNABkDACMAAgq9HdIiALEAAAAA.Paladenden:BAEANQAECgQIBAABNQAECgcIMQAMADQcAA==.',
Pe='Peata:BAAANQADCgMIAwAAAA==.Pelledrusil:BAAANQADCgUIBQAAAA==.Peria:BAAANQADCgYIDAABNQAECgMICAAWAAAAAA==.',
Pi='Pinga:BAAANQAECggIDgABNQAECgoKLQAHAAcfAA==.',
Pk='Pkalygos:BAABNQAECn8pAAIkAAoKTxLpDwDzAQAkAAoKTxLpDwDzAQAAAA==.',
Pl='Pleione:BAABNQAECn8WAAIYAAkK1BB/hQCGAQAYAAkK1BB/hQCGAQAAAA==.',
Po='Portadave:BAAANQAECgMIBgAAAA==.Powerstrokee:BAAANQAECgYIEAAAAA==.',
Pr='Preyforme:BAABNQAECn80AAIHAAkK1gnrmADWAQAHAAkK1gnrmADWAQAAAA==.Prusik:BAAANQADCgcIBwABNQAECgMIAwAWAAAAAA==.Práystation:BAAANQAECgEIAQAAAA==.',
Ps='Psychelone:BAAANQAECgQICQAAAA==.',
Pu='Puffshot:BAAANQAECgEIAQABNQAECgoKKQAIAAkbAA==.Puurseus:BAAANQAECgEIAgABNQAECggIFQASAMASAA==.',
Qu='Quillan:BAAANQADCgUIDQABNQAECgcIDwAWAAAAAA==.',
Qy='Qyxh:BAABNQAECn8iAAMKAAoK/A1bQgCuAQAKAAoK/A1bQgCuAQAXAAIKggMeMQA4AAAAAA==.',
Ra='Raine:BAAANQAECgEIAQAAAA==.Rannath:BAAANQAECggIAwABNQAECggIFwAGAAsFAA==.Rastafarian:BAAANQADCgUICQAAAA==.',
Re='Redeye:BAAANQAECgQIBQAAAA==.Rehne:BAAANQAECgEIAQAAAA==.Rexhavoc:BAACNQAFFH8HAAIEAAMKbRU2BwDpAAAEAAMKbRU2BwDpAAA1AAQKfzYAAgQACgrTHsIIAMACAAQACgrTHsIIAMACAAAA.Rexion:BAAANQAECgEIAQAAAA==.',
Ri='Rigormortits:BAAANQAECgQIBAAAAA==.Ripre:BAAANQADCgUICwAAAA==.',
Ro='Rosary:BAABNQAECn8kAAINAAcKQQX5MQAPAQANAAcKQQX5MQAPAQAAAA==.Rosewoodren:BAAANQAECgMIAwAAAA==.',
Ru='Ruint:BAAANQADCgUIBQAAAA==.Runeclad:BAABNQAECn8ZAAICAAoKLxgTRQAFAgACAAoKLxgTRQAFAgAAAA==.',
Ry='Ryla:BAAANQADCgIIAgABNQAECgoKMgAIABEaAA==.',
['Rï']='Rïvkah:BAAANQADCgUIBwABNQAECgQIBQAWAAAAAA==.',
Sa='Saauurrora:BAAANQADCgYIBgAAAA==.Saintshift:BAAANQADCgEIAQABNQAECgMIAwAWAAAAAA==.Salitheion:BAAANQAECgMIBQAAAA==.Sapper:BAABNQAECn9MAAIlAAoK3CIoAwCCAwAlAAoK3CIoAwCCAwAAAA==.Sarn:BAAANQAECgEIAQAAAA==.Sathi:BAAANQAECgIIAQAAAA==.Sayuri:BAAANQADCgEIAQAAAA==.',
Se='Sennest:BAAANQADCgUIAwAAAA==.',
Sh='Shadowmoocow:BAAANQAECgEIAQABNQAECgQIDAAWAAAAAA==.Shikí:BAAANQAECgIIBQAAAA==.Shladoran:BAABNQAECn87AAIUAAoKrwzDbQCiAQAUAAoKrwzDbQCiAQAAAA==.Shos:BAABNQAECn88AAIVAAoKwh/vBQCaAgAVAAoKwh/vBQCaAgAAAA==.Shuttsyy:BAAANQADCgMIAwAAAA==.',
Si='Siberianwolf:BAABNQAECn8XAAIHAAoKMRkaMwBqAgAHAAoKMRkaMwBqAgAAAA==.Sinnister:BAAANQADCgYIBgAAAA==.Sitruc:BAAANQAECggIDgAAAA==.',
Sk='Skully:BAAANQADCgUIBQABNQAFFAMIBgANAHkeAA==.',
Sl='Sledge:BAAANQADCgMIAwAAAA==.',
Sn='Snapdragyn:BAAANQAECgQIAgAAAA==.Snorina:BAABNQAECn85AAImAAoKMyCXDQATAwAmAAoKMyCXDQATAwAAAA==.',
So='Solàrflàré:BAAANQADCgMIAwAAAA==.Sosgoraan:BAAANQADCgcJBwABNQAECgoKOwAFAJQaAA==.Sosozen:BAABNQAECn8nAAIcAAkKjQmZLQAWAQAcAAkKjQmZLQAWAQAAAA==.Soul:BAACNQAFFH8HAAQNAAIK+BG3BgB5AAANAAIK+BG3BgB5AAAhAAIKAQscAwB3AAADAAIKeQE8IABLAAA1AAQKfz4ABA0ACgrJHo4HAMMCAA0ACgrJHo4HAMMCACEACgqdFX8KABcCAAMABQqLBGVdAJsAAAAA.',
Sp='Spiketurtle:BAAANQAECgMIAwAAAA==.Spirittoast:BAAANQAECgEIAQAAAA==.',
Sr='Sriman:BAAANQAECgYIBgAAAA==.',
St='Starkiller:BAAANQADCgYIDgAAAA==.Stonesolid:BAABNQAECn9AAAMUAAoKDhtpMwBjAgAUAAoKDhtpMwBjAgAeAAMKKRGqHACzAAAAAA==.Stratovarius:BAAANQADCgYIBgAAAA==.',
Su='Sugouri:BAAANQAECggICAAAAA==.Sunnyginger:BAAANQAECggIEwAAAA==.Supremacy:BAABNQAECn8oAAMRAAoKUybzCwBtAwARAAoKUybzCwBtAwASAAEKzSE4YwBeAAAAAA==.',
Sw='Sweetspot:BAAANQAECgcIDgABNQAECgoKHwAfAJMKAA==.Swiftshammy:BAAANQADCgQIBAAAAA==.Swytch:BAABNQAECn8yAAIIAAoKERrFCQAyAgAIAAoKERrFCQAyAgAAAA==.',
Sy='Sylrytherin:BAAANQAECgEIAQABNQAECgoKOQAmADMgAA==.Sylvii:BAABNQAECn8pAAMOAAgKFROfKQDSAQAOAAgKFROfKQDSAQADAAEKAABPnwAAAAAAAA==.',
Ta='Tabor:BAAANQAECgQICAAAAA==.Taggz:BAAANQAECgEIAQAAAA==.Taladryn:BAAANQADCgcIDQAAAA==.Tammyfaye:BAAANQADCgMIAwABNQAECgcILQACAM0KAA==.Tarahly:BAABNQAECn8sAAIJAAkKrCEVGADnAgAJAAkKrCEVGADnAgAAAA==.Tauryel:BAAANQAECgQICgABNQAECgcIDgAWAAAAAA==.',
Te='Tekhan:BAAANQADCgQIBAAAAA==.Tethlis:BAAANQADCggICAABNQAECgoKGgANACAgAA==.',
Th='Thasarias:BAAANQAECgUIBwAAAA==.Themoosifer:BAACNQAFFH8ZAAIEAAgKRBgSAgBhAgAEAAgKRBgSAgBhAgA1AAQKfzMAAgQACgqgIxUOAAcDAAQACgqgIxUOAAcDAAAA.Thunderdump:BAABNQAECn8pAAIdAAkKNBrXTAAwAgAdAAkKNBrXTAAwAgAAAA==.Thyck:BAABNQAECn8eAAIHAAkKihEgcgAtAgAHAAkKihEgcgAtAgAAAA==.Thydis:BAABNQAECn9BAAIGAAoKGBAWkACXAQAGAAoKGBAWkACXAQAAAA==.',
Ti='Tiancit:BAAANQADCgEIAQAAAA==.Tibbs:BAABNQAECn85AAMaAAoKEg58FQD1AQAaAAgK4Q98FQD1AQAZAAkKjQyGCgBKAQAAAA==.Ticklepickle:BAAANQAECgQICAAAAA==.',
To='Tooch:BAAANQADCggICAAAAA==.Torluis:BAAANQADCgMIAwAAAA==.',
Tr='Trumalice:BAAANQADCggIGQAAAA==.',
Tu='Tulpa:BAAANQABCgYIDAAAAA==.',
Ty='Tyrmarlq:BAAANQAECgQIBAAAAA==.',
Un='Uncorrupted:BAABNQAECn8dAAMfAAkKTxM8KQCTAQAfAAgKIBY8KQCTAQAGAAIKigQ2sQEvAAAAAA==.',
Up='Updog:BAAANQAECgEIAQABNQAECgQICAAWAAAAAA==.',
Va='Vaelm:BAAANQADCgcICgAAAA==.Valericia:BAAANQADCgQIBAAAAA==.Valindrux:BAABNQAECn85AAMjAAoKyxdyEgBKAQAMAAkKIBNj0QDjAQAjAAUKdhhyEgBKAQAAAA==.Valjin:BAAANQADCgQIBAABNQAECgoKOQAjAMsXAA==.Valuryan:BAAANQAECgUICAABNQAECgoKOQAjAMsXAA==.Vasdepherens:BAAANQAECgcIBwAAAA==.',
Ve='Velathila:BAAANQAECgMIBQAAAA==.',
Vi='Victorsith:BAAANQADCgMIAwAAAA==.Violêt:BAAANQADCgYIBgAAAA==.Vizzelok:BAABNQAECn8eAAILAAgKZxBDCgDVAQALAAgKZxBDCgDVAQAAAA==.',
Vo='Voidchris:BAABNQAECn9GAAMKAAoK7x5cEwB3AgAEAAoKoxwbEADxAgAKAAoK1hpcEwB3AgAAAA==.Voidormu:BAAANQAECgQIDAAAAA==.',
Wa='Warelf:BAABNQAECn8UAAMRAAkKICHJJgDpAgARAAkKICHJJgDpAgASAAEKUxFBdAA6AAAAAA==.Warleck:BAABNQAECn8WAAIRAAgKjQ3ZfQBRAQARAAgKjQ3ZfQBRAQAAAA==.Waroo:BAAANQADCgIIAgAAAA==.',
Wh='Whillen:BAAANQAECgEIAQAAAA==.Whodey:BAAANQAECgUIDwABNQAECggIFgAFALsRAA==.',
Wi='Wisp:BAAANQADCgYIEQAAAA==.',
Wo='Wompadonk:BAAANQAECgcIBwABNQAFFAMIBgANAHkeAA==.',
Wy='Wylia:BAABNQAECn8iAAIMAAoKuBA9YADnAQAMAAoKuBA9YADnAQAAAA==.',
Xc='Xcw:BAAANQAECgIIAgAAAA==.',
Yy='Yyirium:BAAANQADCgIIAgAAAA==.',
Za='Zakkmorris:BAAANQADCgEIAQAAAA==.Zakuren:BAABNQAECn9UAAIHAAoKkhqYLACAAgAHAAoKkhqYLACAAgAAAA==.',
Zi='Ziggi:BAAANQADCgYIBgABNQAECgMIAwAWAAAAAA==.',
Zo='Zondoul:BAAANQADCgYIBgAAAA==.',
Zu='Zugnator:BAAANQAECggIEAAAAA==.',
Zy='Zylera:BAAANQAECgMIAgAAAA==.Zyphor:BAAANQADCggIDQAAAA==.Zyth:BAAANQAECgEIAQAAAA==.',
['Ñî']='Ñîx:BAAANQAECgYIEwAAAA==.',
['Òm']='Òmêñ:BAABNQAECn8ZAAIGAAkK2RgBXQAJAgAGAAkK2RgBXQAJAgAAAA==.',
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
