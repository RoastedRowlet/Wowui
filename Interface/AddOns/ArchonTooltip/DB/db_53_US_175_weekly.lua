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

local lookup = {'DeathKnight-Frost','DeathKnight-Unholy','Druid-Balance','DemonHunter-Devourer','DeathKnight-Blood','Paladin-Retribution','Rogue-Assassination','Paladin-Holy','Hunter-BeastMastery','Warlock-Affliction','Mage-Arcane','Shaman-Elemental','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','Warrior-Protection','Unknown-Unknown','DemonHunter-Vengeance','Priest-Holy','DemonHunter-Havoc','Evoker-Augmentation','Evoker-Devastation','Monk-Windwalker','Monk-Brewmaster','Shaman-Restoration','Warrior-Fury','Paladin-Protection','Druid-Restoration','Druid-Guardian','Druid-Feral','Shaman-Enhancement','Mage-Frost','Evoker-Preservation','Monk-Mistweaver','Priest-Shadow',}
local provider = {region='US',realm="Quel'dorei",name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abiotic:BAAANQADCgQIBQAAAA==.',
Ac='Acaleus:BAAANQAECgQIBAAAAA==.',
Ad='Adric:BAAANQAECgYIDQAAAA==.Aduhgall:BAAANQADCgcIDQAAAA==.',
Ah='Ahnji:BAAANQADCgMIBAAAAA==.',
Ai='Aings:BAABNQAECn81AAMBAAoKfCDgEwDuAgABAAoKRSDgEwDuAgACAAgKDiG4GwDmAgAAAA==.Aiydaen:BAAANQADCgQIAwAAAA==.Aiytan:BAAANQADCgMIAwAAAA==.',
Al='Alarus:BAABNQAECn9AAAIDAAoKgBngEgAdAgADAAoKgBngEgAdAgAAAA==.Aldith:BAAANQABCgEIAQAAAA==.Alex:BAABNQAECn8vAAIEAAoKDRUiGQCSAgAEAAoKDRUiGQCSAgAAAA==.Alivathor:BAAANQAECgIIAgABNQAECggIJgAFAHEYAA==.Allypally:BAABNQAECn8eAAIGAAkKYQz2wQCYAQAGAAkKYQz2wQCYAQAAAA==.Althorian:BAAANQAECgcIDgAAAA==.',
Am='Amgrod:BAEANQADCgUIBQAAAA==.Amway:BAAANQAECgQICwAAAA==.',
An='Andaarian:BAAANQADCgUIBQAAAA==.Angelkitty:BAAANQADCgYIBgAAAA==.',
Ap='Apophiz:BAAANQADCgYIBgAAAA==.',
Ar='Arcadius:BAAANQADCgIIAgAAAA==.Aremis:BAAANQAECgUIDwAAAA==.Arkaid:BAAANQAECgcIDQAAAA==.Arkhitype:BAABNQAECn8cAAIHAAgKsBctJQBhAgAHAAgKsBctJQBhAgAAAA==.Arteras:BAAANQAECgQIBgAAAA==.Aryadel:BAAANQABCgQIBAAAAA==.Aryahi:BAAANQAECggIAQAAAA==.',
As='Ashyslashy:BAABNQAECn8ZAAMGAAoK1BNOfQAvAgAGAAgKmRVOfQAvAgAIAAYKpxDBtwANAQAAAA==.Asur:BAABNQAECn8nAAIGAAgKOw0IygCHAQAGAAgKOw0IygCHAQAAAA==.',
Au='Auracorusca:BAABNQAECn8eAAMIAAoKhB/eKQDAAgAIAAoKhB/eKQDAAgAGAAEK2gVWrgEwAAAAAA==.Aurafarmer:BAAANQAECgUIBAAAAA==.Auris:BAAANQADCgQIBAAAAA==.',
Ay='Aydain:BAAANQADCgQIBAAAAA==.Aynilith:BAAANQAECgcIEgAAAA==.Aystarael:BAAANQAECggICAAAAA==.',
Ba='Bajr:BAABNQAECn8iAAIJAAoK8AmclADfAQAJAAoK8AmclADfAQAAAA==.Bakura:BAABNQAECn8oAAIKAAoKChnvBACBAgAKAAoKChnvBACBAgAAAA==.Banker:BAABNQAECn8rAAIEAAkKqw3MHQA9AQAEAAkKqw3MHQA9AQAAAA==.Baroo:BAAANQAECgQICQAAAA==.Barudd:BAAANQABCgQIBAAAAA==.',
Be='Berko:BAABNQAECn9DAAILAAoK5h3yMQAqAgALAAoK5h3yMQAqAgAAAA==.Beyorne:BAAANQAECgIIAQAAAA==.',
Bh='Bhaang:BAAANQAECgYIDQAAAA==.',
Bi='Bigbear:BAAANQAFFAIIAwAAAA==.Bigbill:BAAANQAECgQIBAAAAA==.Bigdeath:BAABNQAECn8aAAIMAAYKlhZAiACQAQAMAAYKlhZAiACQAQAAAA==.Biletooth:BAAANQADCgcICgABNQAECgcIIAACALMIAA==.Bizco:BAABNQAECn8jAAMJAAoKeRxGVAB0AgAJAAoKeRxGVAB0AgANAAIKaQlpUgA0AAAAAA==.',
Bj='Bjebo:BAABNQAECn8rAAIDAAoKbQxMRADiAQADAAoKbQxMRADiAQAAAA==.',
Bl='Bluffshot:BAABNQAECn8lAAIHAAgKHh7GFADVAgAHAAgKHh7GFADVAgAAAA==.',
Br='Brutes:BAAANQADCggICAABNQAFFAMIBgABAJsgAA==.Brynjalf:BAAANQAECgQIBwAAAA==.Bràe:BAAANQABCgMIAQAAAA==.',
Bx='Bxck:BAAANQAECgEIAQAAAA==.',
['Bï']='Bïcho:BAACNQAFFH8FAAIOAAIKFBImGACaAAAOAAIKFBImGACaAAA1AAQKfyAAAw4ACgpQG/AuAMsCAA4ACgopG/AuAMsCAA8AAgq1C+tlAFcAAAAA.',
Ca='Calambar:BAAANQADCgYIBgAAAA==.Cas:BAAANQADCgYIBgAAAA==.Casally:BAAANQADCgYICgAAAA==.Cascadio:BAAANQAECgIIAQAAAA==.Castanza:BAAANQADCgQIBwAAAA==.Caswyn:BAAANQAECgUIEQAAAA==.',
Ch='Chapjong:BAAANQADCgQIBQAAAA==.Charjer:BAABNQAECn8oAAMQAAgKuB3WTQCgAgAQAAgKuB3WTQCgAgARAAMK2BUdIwB3AAAAAA==.Chokengag:BAAANQADCgMIAwAAAA==.Choney:BAAANQAECgcIBwAAAA==.',
Co='Codedgar:BAAANQADCgUIBQABNQAECgcIDwASAAAAAA==.Coffeeshot:BAAANQADCgcIDQAAAA==.Cojostudio:BAAANQADCggICAAAAA==.Comboost:BAAANQAECgQIBQAAAA==.Costcolshirt:BAAANQAECgEIAQAAAA==.',
Cr='Cranks:BAAANQAECgcIDAAAAA==.Crashcake:BAABNQAECn8cAAIBAAkKyhygHAClAgABAAkKyhygHAClAgAAAA==.Creakybones:BAAANQABCgIIAgAAAA==.Croager:BAABNQAECn8ZAAIJAAoKOhy4MQDXAgAJAAoKOhy4MQDXAgABNQAFFAEIAQASAAAAAA==.',
Cu='Cup:BAABNQAECn8qAAIIAAkKZxIvTwBaAQAIAAkKZxIvTwBaAQAAAA==.',
Cv='Cvv:BAAANQADCgQIBAABNQAECgMIAwASAAAAAA==.',
Cy='Cyberlinde:BAAANQAECgQIEAAAAA==.Cywen:BAAANQADCggICAABNQAFFAcIGQAHAP4dAA==.',
Da='Daelaris:BAABNQAECn8jAAILAAoKWx9aQAAFAwALAAoKWx9aQAAFAwAAAA==.Damonoris:BAABNQAECn8eAAIJAAoK9wywYwB1AQAJAAoK9wywYwB1AQAAAA==.Damthrax:BAAANQAECgQIBQAAAA==.Danielan:BAAANQAECgYICgAAAA==.Davegrôwl:BAAANQADCgEJAQABNQAECgcIIAACALMIAA==.',
De='Deadair:BAAANQADCgMIAwAAAA==.Deadlyalba:BAAANQADCgYIBgAAAA==.Deadzeo:BAAANQADCgYICQAAAA==.Demonblades:BAABNQAECn8wAAIEAAoKvRjBHABvAgAEAAoKvRjBHABvAgAAAA==.Demonbreaker:BAABNQAECn8qAAITAAkKgBeGBQDUAQATAAkKgBeGBQDUAQAAAA==.Denarten:BAABNQAECn8hAAIGAAkKvSFYJgAsAwAGAAkKvSFYJgAsAwAAAA==.',
Di='Diotima:BAAANQADCgUICQAAAA==.Dirtymorris:BAAANQAECgcIEQAAAA==.Disrupt:BAAANQAECgQICAAAAA==.',
Do='Dockevorkian:BAACNQAFFH8KAAIUAAMKrBSLFQDZAAAUAAMKrBSLFQDZAAA1AAQKfzgAAhQACgqSIHQXABoDABQACgqSIHQXABoDAAAA.Dornaaealdor:BAAANQADCgIIAgAAAA==.Dortwaz:BAABNQAECn8wAAMOAAoKTRvIZAArAgAOAAkKpxvIZAArAgAPAAIKlhWNVACBAAAAAA==.Doublebonus:BAAANQADCggICAABNQAFFAMIBgABAJsgAA==.Dougdk:BAABNQAECn80AAIFAAoKLCRwAwC6AwAFAAoKLCRwAwC6AwABNQAFFAIIAwASAAAAAA==.',
Dr='Dracoramonk:BAAANQAECgEIAQAAAA==.Dracoz:BAAANQADCgEIAQAAAA==.Dricex:BAAANQADCgYIBgABNQAECgMIBgASAAAAAA==.Drinnagon:BAAANQADCgcIBwABNQAECgkJIQAGAL0hAA==.Drinntellect:BAAANQAECgMIAwABNQAECgkJIQAGAL0hAA==.Drinnundead:BAAANQADCgEIAQABNQAECgkJIQAGAL0hAA==.Druelf:BAAANQADCgUIBQAAAA==.Dryblood:BAAANQADCgQIBAAAAA==.Dryx:BAAANQAECgIIAgAAAA==.',
Du='Dunaarn:BAAANQADCgMIAwAAAA==.',
Ea='Eargroan:BAAANQADCgYICwABNQAECgoKJgATAFgjAA==.',
El='Elilla:BAABNQAECn8mAAIFAAgKyQtxNQARAQAFAAgKyQtxNQARAQAAAA==.Elkminster:BAAANQAECgMIAwAAAA==.Ellenaya:BAAANQAECggIDwAAAA==.Elorela:BAAANQADCgQIBAABNQAECgoKIQAPAIkZAA==.',
En='Enjoy:BAACNQAFFH8GAAIBAAMKmyBuDgD0AAABAAMKmyBuDgD0AAA1AAQKfyYAAwEACQoYJegHAGcDAAEACQqSJOgHAGcDAAIACQqPIm4nAJ0CAAAA.',
Fa='Famiki:BAAANQADCgcICwAAAA==.',
Fe='Feardotcom:BAAANQABCgIIAgAAAA==.Felnollid:BAABNQAECn8mAAMVAAkKWhuWHAC1AgAVAAkKWhuWHAC1AgAEAAUKewdWTQDxAAAAAA==.Fenanigans:BAABNQAECn8iAAIHAAkKeiDUCwApAwAHAAkKeiDUCwApAwAAAA==.Fenquisition:BAAANQADCggICAABNQAECgkJIgAHAHogAA==.',
Fi='Firebender:BAAANQADCgQIBQAAAA==.Firetiger:BAAANQADCgcIBwAAAA==.Fistandcider:BAAANQADCggICQAAAA==.',
Fl='Fluffyhusky:BAABNQAECn8iAAMWAAcK4ATGFgDHAAAXAAcKnQTXJgD+AAAWAAUKhAfGFgDHAAABNQAECgoKHgAJADkNAA==.',
Fo='Fontss:BAAANQAECgYIBwAAAA==.Fonyfish:BAACNQAFFH8IAAIOAAUK3gxEIgDnAAAOAAUK3gxEIgDnAAA1AAQKfyAAAg4ACQr/GKgwAOsBAA4ACQr/GKgwAOsBAAAA.Forba:BAAANQAECgYIBgAAAA==.',
Fr='Frostybina:BAAANQADCgMIAwAAAA==.',
Fu='Fubina:BAEBNQAECn86AAMYAAoKDh+kDgD2AgAYAAoKDh+kDgD2AgAZAAIK5R0zJgCcAAAAAA==.',
Fy='Fyjalla:BAAANQADCggIEAAAAA==.',
['Fâ']='Fâllênknîght:BAABNQAECn8mAAIFAAgKcRgqHQCnAQAFAAgKcRgqHQCnAQAAAA==.',
Ga='Gabh:BAAANQADCgYIBgAAAA==.Gandoorr:BAAANQAECgIIAgAAAA==.',
Gi='Gilgaglaive:BAABNQAECn8YAAIEAAkKIxYFHQBsAgAEAAkKIxYFHQBsAgAAAA==.',
Gl='Glomah:BAABNQAECn8uAAMFAAoKKSFFEwATAwAFAAkKxSBFEwATAwABAAYK8Bq8JgCcAQAAAA==.Glorm:BAABNQAECn8vAAIaAAoK5BL2YwDhAQAaAAoK5BL2YwDhAQAAAA==.',
Go='Gobropro:BAAANQADCgYIBgAAAA==.Gorathan:BAAANQADCgMIAwAAAA==.Gotalock:BAAANQADCggIDAAAAA==.',
Gr='Grabbyhands:BAABNQAECn8gAAMCAAcKswg/SQCSAAACAAUKcgk/SQCSAAAFAAQKlQcEZgBnAAAAAA==.Grantul:BAABNQAECn82AAIbAAkKbxbzBQDpAQAbAAkKbxbzBQDpAQAAAA==.Grimthore:BAAANQAECgQIBAABNQAECgoKFwAcAFsKAA==.Grolgan:BAAANQADCgYIBgAAAA==.Gromz:BAABNQAECn8UAAIOAAoK3xSTSgBzAgAOAAoK3xSTSgBzAgAAAA==.',
Gu='Gulbhang:BAABNQAECn8tAAMOAAoKxRp+MwC7AgAOAAoKxRp+MwC7AgAPAAEKXA+cdgA3AAAAAA==.',
Ha='Hakiranatha:BAAANQADCggICAAAAA==.Harkelanu:BAAANQAECgIIAgAAAA==.',
Hb='Hbkdx:BAABNQAECn8aAAIJAAYKrQagrgDRAAAJAAYKrQagrgDRAAAAAA==.',
He='Health:BAAANQAECgMIAwAAAA==.',
Ho='Holdi:BAAANQADCgYIBgABNQAECgkJJQAGANcOAA==.Holyhammer:BAAANQAECggIDQAAAA==.Holyoke:BAAANQADCgEIAQAAAA==.Homunculus:BAAANQAECgUIBwAAAA==.',
Hu='Hujo:BAABNQAECn8eAAIQAAkKXxF4iwD/AQAQAAkKXxF4iwD/AQAAAA==.Hushpupi:BAABNQAECn8hAAMPAAoKiRkXCAB+AgAPAAoKiRkXCAB+AgAOAAQKKApF+wDVAAAAAA==.Huskerpower:BAAANQADCgcJDQAAAA==.',
Ic='Iceharted:BAAANQAECgMIAwAAAA==.Icesloth:BAABNQAECn8eAAIMAAoKcBXyUgAtAgAMAAoKcBXyUgAtAgAAAA==.',
Id='Idamarie:BAABNQAECn8UAAIMAAYKXAKy9QCpAAAMAAYKXAKy9QCpAAAAAA==.Iduun:BAAANQADCgEIAQAAAA==.',
Il='Iladelle:BAABNQAECn8nAAIEAAkKfhFtFgCMAQAEAAkKfhFtFgCMAQAAAA==.',
Io='Iorak:BAAANQADCgEIAQAAAA==.',
Ir='Irinon:BAAANQADCgcIDAAAAA==.',
Ix='Ixiya:BAAANQAECgQIBgAAAA==.',
Ja='Jafud:BAAANQAFFAEIAQABNQAFFAYIGAAFAGIZAA==.Jafuds:BAAANQAFFAMIAwABNQAFFAYIGAAFAGIZAA==.Jaggerss:BAAANQAECgEIAQABNQAFFAMIBgABAJsgAA==.Jamaican:BAAANQADCgYIEAAAAA==.Jaste:BAAANQAECgYIEAAAAA==.',
Ji='Jimit:BAAANQADCgcIBwAAAA==.Jimmym:BAABNQAECn8XAAIGAAYKPQPsCAFzAAAGAAYKPQPsCAFzAAAAAA==.Jirakaidae:BAAANQADCgYICwABNQAECgUIDwASAAAAAA==.',
Jo='Jordis:BAAANQAECgMIBAAAAA==.',
Ju='Juicyfists:BAAANQADCgMIAwAAAA==.Juju:BAAANQAECgEIAQAAAA==.',
Ka='Kaedeyn:BAAANQAECgUICQAAAA==.Kaeltharon:BAAANQADCgQIAwAAAA==.Kamekaze:BAAANQADCgYIBgAAAA==.Kandrys:BAAANQADCgQIBAAAAA==.Kasgotojim:BAAANQAECgQIBAAAAA==.Kaypop:BAAANQAECgQIBAAAAA==.Kayy:BAAANQADCgIIAgAAAA==.',
Ke='Kerrster:BAAANQADCgQIBAAAAA==.',
Kh='Khármá:BAABNQAECn8fAAIcAAgKAxlSDgC6AQAcAAgKAxlSDgC6AQAAAA==.',
Ki='Kicklocks:BAAANQAECgMIAQAAAA==.Kikuri:BAAANQAECgYICgAAAA==.Killt:BAABNQAECn8rAAIaAAkKdB45FgCVAgAaAAkKdB45FgCVAgAAAA==.',
Ko='Koojoé:BAAANQAECgQIBQAAAA==.',
Ku='Kurzulan:BAABNQAECn8gAAQdAAkKxQqbOgBLAQAdAAgKdgebOgBLAQADAAQKmgY0UACFAAAeAAMK5wN/VQBQAAAAAA==.',
La='Laal:BAAANQAECgIIAgAAAA==.Laghles:BAABNQAECn9EAAIJAAoKMx9pIAAWAwAJAAoKMx9pIAAWAwAAAA==.Laroes:BAAANQAECgEIAQABNQAECgoKLgAFACkhAA==.Larua:BAAANQABCgQJBAAAAA==.',
Le='Lemanjá:BAABNQAECn8dAAINAAgKzAZFHAAeAQANAAgKzAZFHAAeAQAAAA==.',
Li='Lightlooter:BAAANQADCgYIBgAAAA==.Liliane:BAABNQAECn8XAAIGAAoK2RG+pADXAQAGAAoK2RG+pADXAQAAAA==.Limbless:BAAANQAECgcIDAAAAA==.',
Lo='Loahealth:BAAANQAECgcIDwAAAA==.Lockrocks:BAABNQAECn8zAAQKAAkKpxRuDQCDAQAOAAkKQBOsSQCIAQAKAAYK3g9uDQCDAQAPAAUKCAfzLwAJAQABNQAECgoKFwAcAFsKAA==.Lockstar:BAAANQADCgYIDAAAAA==.Loko:BAABNQAECn8fAAIaAAkKMAtDPgCeAQAaAAkKMAtDPgCeAQAAAA==.Lontra:BAAANQADCgUIDAAAAA==.Loozer:BAABNQAECn8XAAMcAAoKWwpeOQAiAQAGAAgKGgmD7wA9AQAcAAcKKAheOQAiAQAAAA==.Loralast:BAAANQADCgQIBAAAAA==.',
Lu='Luzifer:BAAANQADCgYIBgAAAA==.',
Ma='Magelyman:BAABNQAECn8gAAILAAkKKxdZTADLAQALAAkKKxdZTADLAQAAAA==.Mahlaan:BAABNQAECn80AAIFAAoKcRhhGQDMAQAFAAoKcRhhGQDMAQAAAA==.Malakai:BAAANQADCgIIAgABNQAECggICwASAAAAAA==.Malekai:BAAANQAECgUJCAABNQAECggICwASAAAAAA==.Malyce:BAAANQAECggICwAAAA==.Malzen:BAAANQADCgMIAwABNQAECggICwASAAAAAA==.Manaleia:BAAANQADCggIDAAAAA==.Manasolid:BAAANQADCgEIAQAAAA==.Mar:BAAANQAECgIIAgAAAA==.Maruug:BAAANQADCgYIBgAAAA==.Marvinah:BAAANQAECgIIBwAAAA==.Maydie:BAAANQAECgcIBwAAAA==.',
Me='Meatcurtin:BAAANQADCgQICAAAAA==.Meatlover:BAAANQAECgcIDgAAAA==.Mediocre:BAABNQAECn8XAAIfAAgK+R7uBwDcAgAfAAgK+R7uBwDcAgAAAA==.Meeshka:BAABNQAECn8hAAILAAYKig2VqwDwAAALAAYKig2VqwDwAAAAAA==.Meraleona:BAABNQAECn8aAAIYAAoKIRd2HwA0AgAYAAoKIRd2HwA0AgAAAA==.Methslinger:BAAANQAECggIDgAAAA==.',
Mi='Migue:BAAANQABCgEIAgABNQAECgoKUQAGAJQjAA==.Miltonroe:BAAANQADCggICAABNQAECgkJKwAgAGgMAA==.',
Mo='Moarass:BAAANQAECgQJBgABNQAECgoKMAAdAEsYAA==.Moris:BAABNQAECn8cAAMPAAcKJQP2OQDZAAAPAAYKwwL2OQDZAAAOAAcKcgJvvAB6AAAAAA==.Mortmuzi:BAAANQADCgYJBwAAAA==.Mosrael:BAABNQAECn8UAAIGAAgKCwWb6gCdAAAGAAgKCwWb6gCdAAAAAA==.',
Ms='Mswizzlë:BAABNQAECn8gAAMhAAgKegfaFwA7AQAhAAgKegfaFwA7AQALAAIKAwLsCwFTAAAAAA==.',
Mu='Muldah:BAABNQAECn8+AAMLAAoKLxfMOAAQAgALAAoKYBbMOAAQAgAhAAcK8QleHAANAQAAAA==.',
Na='Nas:BAABNQAECn8zAAMOAAoKUSDCFwBwAgAOAAkKyiDCFwBwAgAPAAEKAB3OZgBVAAAAAA==.Nausicaa:BAAANQABCggIDQAAAA==.Nausicaä:BAAANQADCgUIBQAAAA==.Navie:BAAANQAECgYIDwAAAA==.Nazgûl:BAAANQABCgYIBAAAAA==.',
Ne='Nekros:BAAANQADCgcIBwABNQAECggIKAAQALgdAA==.Neø:BAABNQAECn8pAAMBAAoKwhjVLAB4AQACAAYK5R1KXwCSAQABAAkKpBjVLAB4AQAAAA==.',
Ni='Nicebud:BAAANQAECgEIAQAAAA==.Nightsfury:BAAANQAECgYICgAAAA==.Nightshala:BAAANQAECgQIBAAAAA==.',
No='Nollid:BAAANQADCgYIBgABNQAECgkJJgAVAFobAA==.Nordburg:BAAANQABCggIEwAAAA==.Nornyr:BAAANQADCgEIAQAAAA==.Notforgiven:BAAANQAECgEIAQAAAA==.Notnonna:BAAANQADCgQIBAAAAA==.',
Nu='Nunsrsus:BAAANQAECgcIDwAAAA==.',
Ny='Nymerias:BAAANQADCgYIDgAAAA==.Nyrrah:BAAANQAECgQIBQAAAA==.',
['Ná']='Nácht:BAAANQAECgYICAAAAA==.',
['Ný']='Nýghtmyst:BAAANQAECgEJAQAAAA==.',
Ok='Oku:BAAANQADCgUIBQAAAA==.',
Ol='Olaf:BAAANQAECgIIAgAAAA==.',
Om='Omaticaya:BAABNQAECn82AAIDAAkKhgi1LAApAQADAAkKhgi1LAApAQAAAA==.Omèn:BAAANQADCgUIBQABNQAFFAEIAQASAAAAAA==.',
Oo='Oolong:BAAANQADCggICgAAAA==.',
Op='Optikon:BAAANQAECgUIDAAAAA==.',
Or='Oriax:BAAANQAECgcICwABNQAECgoKQAADAIAZAA==.',
Ow='Owlbearcat:BAAANQAECgYIDQABNQAECgcIDwASAAAAAA==.',
Pa='Packerssuck:BAAANQADCgEIAQAAAA==.Paean:BAAANQADCgcIIAAAAA==.Paj:BAACNQAFFH8LAAMLAAcKbAfTHACYAQALAAYK+wfTHACYAQAhAAEKMgWiCwBRAAA1AAQKfzUAAgsACgoFILAUAIADAAsACgoFILAUAIADAAAA.',
Pe='Peata:BAAANQADCgMIAwAAAA==.Pelledrusil:BAAANQADCgUIBQAAAA==.Peria:BAAANQADCgYIBgABNQAECgMIBwASAAAAAA==.',
Pi='Pinga:BAAANQAECgcICgABNQAECgoKIwAJAHkcAA==.',
Pk='Pkalygos:BAABNQAECn8nAAIiAAkKDBK8DAC5AQAiAAkKDBK8DAC5AQAAAA==.',
Pl='Pleione:BAAANQAECgYIDwAAAA==.',
Po='Portadave:BAAANQAECgMIBgAAAA==.Powerstrokee:BAAANQAECgYIDAAAAA==.',
Pr='Preyforme:BAABNQAECn8xAAIJAAgKSAoHcQBUAQAJAAgKSAoHcQBUAQAAAA==.Prusik:BAAANQADCgcIBwABNQAECgMIAwASAAAAAA==.Práystation:BAAANQADCgMIAwAAAA==.',
Ps='Psychelone:BAAANQAECgQIBAAAAA==.',
Pu='Puffshot:BAAANQAECgEIAQABNQAECggIJQAHAB4eAA==.Puurseus:BAAANQABCgYIBwABNQAECgUIEAASAAAAAA==.',
Qu='Quillan:BAAANQADCgUIDQABNQAECgcIDwASAAAAAA==.',
Qy='Qyxh:BAABNQAECn8dAAMVAAkKUw1bQgCuAQAVAAkKUw1bQgCuAQATAAIKggMeMQA4AAAAAA==.',
Ra='Raine:BAAANQADCggIEAAAAA==.Rannath:BAAANQAECggIAwABNQAECggIFAAGAAsFAA==.Rastafarian:BAAANQADCgUICQAAAA==.',
Re='Redeye:BAAANQAECgEIAQAAAA==.Rehne:BAAANQAECgEIAQAAAA==.Rexhavoc:BAABNQAECn8tAAIEAAoKShtlCgBRAgAEAAoKShtlCgBRAgAAAA==.Rexion:BAAANQAECgEIAQAAAA==.',
Ri='Rigormortits:BAAANQAECgQIBAAAAA==.Ripre:BAAANQADCgUICwAAAA==.',
Ro='Rosary:BAABNQAECn8kAAIeAAcKQQX5MQAPAQAeAAcKQQX5MQAPAQAAAA==.Rosewoodren:BAAANQAECgQIAQAAAA==.',
Ru='Ruint:BAAANQADCgUIBQAAAA==.Runeclad:BAABNQAECn8XAAICAAgKDxkTRQAFAgACAAgKDxkTRQAFAgAAAA==.',
Ry='Ryla:BAAANQADCgIIAgABNQAECgkJLQAHAPQZAA==.',
['Rï']='Rïvkah:BAAANQADCgUIBwABNQAECgQIBQASAAAAAA==.',
Sa='Saauurrora:BAAANQADCgYIBgAAAA==.Saintshift:BAAANQADCgEIAQABNQAECgMIAwASAAAAAA==.Salitheion:BAAANQAECgQIAwAAAA==.Sapper:BAABNQAECn9CAAIjAAoKAiIoAwCCAwAjAAoKAiIoAwCCAwAAAA==.Sarn:BAAANQAECgEIAQAAAA==.Sathi:BAAANQAECgIIAQAAAA==.Sayuri:BAAANQADCgEIAQAAAA==.',
Se='Sennest:BAAANQADCgUIAwAAAA==.',
Sh='Shikí:BAAANQAECgIIBAAAAA==.Shladoran:BAABNQAECn8lAAIQAAoKeQvQawBEAQAQAAoKeQvQawBEAQAAAA==.Shos:BAABNQAECn8zAAIRAAoKqR6mBABhAgARAAoKqR6mBABhAgAAAA==.',
Si='Siberianwolf:BAAANQAECggIDwAAAA==.Sinnister:BAAANQADCgYIBgAAAA==.Sitruc:BAAANQAECgYIBgAAAA==.',
Sk='Skully:BAAANQADCgUIBQABNQAFFAIIAwASAAAAAA==.',
Sl='Sledge:BAAANQADCgMIAwAAAA==.',
Sn='Snapdragyn:BAAANQAECgQIAQAAAA==.Snorina:BAABNQAECn8wAAIkAAoKqB+XDQATAwAkAAoKqB+XDQATAwAAAA==.',
So='Solàrflàré:BAAANQADCgMIAwAAAA==.Sosgoraan:BAAANQADCgcJBwABNQAECgoKNAAFAHEYAA==.Sosozen:BAABNQAECn8hAAIYAAgKEQp4OABQAQAYAAgKEQp4OABQAQAAAA==.Soul:BAABNQAECn8qAAQeAAoKDxxvCgAbAgAeAAgKKR9vCgAbAgAfAAoKSw0DCgCfAQADAAUKiwS0SACiAAAAAA==.',
Sp='Spirittoast:BAAANQAECgEIAQAAAA==.',
Sr='Sriman:BAAANQAECgYIBgAAAA==.',
St='Starkiller:BAAANQADCgYIDgAAAA==.Stonesolid:BAABNQAECn80AAIQAAgKahrmUwCPAgAQAAgKahrmUwCPAgAAAA==.Stratovarius:BAAANQADCgYIBgAAAA==.',
Su='Sugouri:BAAANQAECggICAAAAA==.Sunnyginger:BAAANQAECgYICgAAAA==.Supremacy:BAABNQAECn8lAAMOAAoKMSbzCwBtAwAOAAoKMSbzCwBtAwAPAAEKzSE4YwBeAAAAAA==.',
Sw='Sweetspot:BAAANQAECgcIDgABNQAECgoKFwAcAFsKAA==.Swiftshammy:BAAANQADCgQIBAAAAA==.Swytch:BAABNQAECn8tAAIHAAkK9BknCAAQAgAHAAkK9BknCAAQAgAAAA==.',
Sy='Sylrytherin:BAAANQADCgYICgABNQAECgoKMAAkAKgfAA==.Sylvii:BAABNQAECn8pAAMdAAgKFROfKQDSAQAdAAgKFROfKQDSAQADAAEKAACEggAAAAAAAA==.',
Ta='Tabor:BAAANQAECgUIBgAAAA==.Taggz:BAAANQABCgQIBAAAAA==.Taladryn:BAAANQADCgcIDQAAAA==.Tarahly:BAABNQAECn8pAAIIAAgK0yEWFQCcAgAIAAgK0yEWFQCcAgAAAA==.Tauryel:BAAANQAECgQIBwABNQAECgcIDAASAAAAAA==.',
Te='Tekhan:BAAANQADCgQIBAAAAA==.Tethlis:BAAANQADCggICAABNQAECgoKGAAeACAgAA==.',
Th='Thasarias:BAAANQAECgUIBwAAAA==.Themoosifer:BAACNQAFFH8XAAIEAAcKPRcSAgBhAgAEAAcKPRcSAgBhAgA1AAQKfy0AAgQACgpnIxUOAAcDAAQACgpnIxUOAAcDAAAA.Thunderdump:BAABNQAECn8pAAIaAAkKNBpoLwDmAQAaAAkKNBpoLwDmAQAAAA==.Thyck:BAABNQAECn8eAAIJAAkKihEgcgAtAgAJAAkKihEgcgAtAgAAAA==.Thydis:BAABNQAECn86AAIGAAkKOQ+bfQBWAQAGAAkKOQ+bfQBWAQAAAA==.',
Ti='Tiancit:BAAANQADCgEIAQAAAA==.Tibbs:BAABNQAECn8wAAMXAAoKjg18FQD1AQAXAAgK4Q98FQD1AQAWAAkKBguXEAAuAQAAAA==.Ticklepickle:BAAANQAECgQICAAAAA==.',
To='Tooch:BAAANQADCggICAAAAA==.Torluis:BAAANQADCgMIAwAAAA==.',
Tr='Trumalice:BAAANQADCgcIEQAAAA==.',
Tu='Tulpa:BAAANQABCgYIDAAAAA==.',
Un='Uncorrupted:BAABNQAECn8dAAMcAAkKTxM8KQCTAQAcAAgKIBY8KQCTAQAGAAIKigQ2sQEvAAAAAA==.',
Up='Updog:BAAANQAECgEIAQABNQAECgQICAASAAAAAA==.',
Va='Vaelm:BAAANQADCgcICgAAAA==.Valericia:BAAANQADCgQIBAAAAA==.Valindrux:BAABNQAECn8sAAMhAAkKDBbKDwANAQALAAgKVhFj0QDjAQAhAAQKZxjKDwANAQAAAA==.Valjin:BAAANQADCgQIBAABNQAECgkJLAAhAAwWAA==.Valuryan:BAAANQADCggIEAABNQAECgkJLAAhAAwWAA==.Vasdepherens:BAAANQAECgcIBwAAAA==.',
Ve='Velathila:BAAANQAECgMIBQAAAA==.',
Vi='Victorsith:BAAANQADCgMIAwAAAA==.Violêt:BAAANQADCgYIBgAAAA==.Vizzelok:BAABNQAECn8bAAIKAAcKfBBDCgDVAQAKAAcKfBBDCgDVAQAAAA==.',
Vo='Voidchris:BAABNQAECn80AAMEAAoKCh0bEADxAgAEAAkKUh0bEADxAgAVAAgKnRAVIQCNAQAAAA==.Voidormu:BAAANQAECgIIBAAAAA==.',
Wa='Warelf:BAABNQAECn8UAAMOAAkKICHJJgDpAgAOAAkKICHJJgDpAgAPAAEKUxFBdAA6AAAAAA==.Warleck:BAAANQAECgQICwAAAA==.',
Wh='Whodey:BAAANQAECgUICQABNQAECggICwASAAAAAA==.',
Wi='Wisp:BAAANQADCgYIDwAAAA==.',
Wo='Wompadonk:BAAANQAECgcIBwABNQAFFAIIAwASAAAAAA==.',
Wy='Wylia:BAAANQAECgcIEAAAAA==.',
Xc='Xcw:BAAANQAECgIIAgAAAA==.',
Yy='Yyirium:BAAANQADCgIIAgAAAA==.',
Za='Zakkmorris:BAAANQADCgEIAQAAAA==.Zakuren:BAABNQAECn9BAAIJAAoKvhcQIgBfAgAJAAoKvhcQIgBfAgAAAA==.',
Zi='Ziggi:BAAANQADCgYIBgABNQAECgMIAwASAAAAAA==.',
Zo='Zondoul:BAAANQADCgYIBgAAAA==.',
Zu='Zugnator:BAAANQAECgMIAwABNQAECggIKQAMAEkWAA==.',
Zy='Zylera:BAAANQAECgMIAgAAAA==.Zyphor:BAAANQADCggIDQAAAA==.Zyth:BAAANQABCgMIAgAAAA==.',
['Ñî']='Ñîx:BAAANQAECgYIEwAAAA==.',
['Òm']='Òmêñ:BAAANQAFFAEIAQAAAA==.',
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
