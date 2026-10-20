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

local lookup = {'DeathKnight-Frost','DeathKnight-Unholy','Druid-Balance','DemonHunter-Devourer','DeathKnight-Blood','Paladin-Retribution','Rogue-Assassination','Paladin-Holy','Hunter-BeastMastery','Warlock-Affliction','Mage-Arcane','Shaman-Elemental','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','Warrior-Protection','Unknown-Unknown','DemonHunter-Vengeance','Priest-Holy','DemonHunter-Havoc','Evoker-Augmentation','Evoker-Devastation','Monk-Windwalker','Monk-Brewmaster','Shaman-Restoration','Warrior-Fury','Paladin-Protection','Druid-Restoration','Druid-Guardian','Hunter-Marksmanship','Druid-Feral','Shaman-Enhancement','Mage-Frost','Evoker-Preservation','Monk-Mistweaver','Priest-Shadow',}
local provider = {region='US',realm="Quel'dorei",name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abiotic:BAAANQADCgQIBQAAAA==.',
Ac='Acaleus:BAAANQAECgQIBAAAAA==.',
Ad='Adric:BAAANQAECgYIDwAAAA==.Aduhgall:BAAANQADCgcIDQAAAA==.',
Ah='Ahnji:BAAANQADCgMIBAAAAA==.',
Ai='Aings:BAABNQAECn8xAAMBAAoK3B/gEwDuAgABAAoKjx/gEwDuAgACAAgKDiG4GwDmAgAAAA==.Airbubble:BAAANQAECgEIAQAAAA==.Aiydaen:BAAANQADCgQIAwAAAA==.Aiytan:BAAANQADCgMIAwAAAA==.',
Al='Alarus:BAABNQAECn82AAIDAAkK3xgGKwCBAgADAAkK3xgGKwCBAgAAAA==.Alex:BAABNQAECn8vAAIEAAoKDRUiGQCSAgAEAAoKDRUiGQCSAgAAAA==.Alivathor:BAAANQAECgIIAgABNQAECggIIAAFAMEWAA==.Allypally:BAABNQAECn8bAAIGAAgKywv2wQCYAQAGAAgKywv2wQCYAQAAAA==.Althorian:BAAANQAECgYIDAAAAA==.',
Am='Amgrod:BAEANQADCgUIBQAAAA==.Amway:BAAANQAECgQIDwAAAA==.',
An='Andaarian:BAAANQADCgUIBQAAAA==.Angelkitty:BAAANQADCgYIBgAAAA==.',
Ap='Apophiz:BAAANQADCgYIBgAAAA==.',
Ar='Arcadius:BAAANQADCgIIAgAAAA==.Ardur:BAAANQAECgEIAQAAAA==.Aremis:BAAANQAECgUIDgAAAA==.Arkaid:BAAANQAECgYIBgAAAA==.Arkhitype:BAABNQAECn8cAAIHAAgKsBctJQBhAgAHAAgKsBctJQBhAgAAAA==.Arteras:BAAANQAECgIIAwAAAA==.Aryadel:BAAANQABCgQIBAAAAA==.Aryahi:BAAANQAECggIAQAAAA==.',
As='Ashyslashy:BAABNQAECn8XAAMGAAoKuxJOfQAvAgAGAAgKmRVOfQAvAgAIAAYKgRDBtwANAQAAAA==.Asur:BAABNQAECn8jAAIGAAgKxgwIygCHAQAGAAgKxgwIygCHAQAAAA==.',
Au='Auracorusca:BAABNQAECn8dAAMIAAoKhB+KDQDzAQAIAAoKhB+KDQDzAQAGAAEK2gVWrgEwAAAAAA==.Aurafarmer:BAAANQAECgUIBAAAAA==.Auris:BAAANQADCgQIBAAAAA==.',
Ay='Aydain:BAAANQADCgQIBAAAAA==.Aynilith:BAAANQAECgYIDwAAAA==.Aystarael:BAAANQAECggICAAAAA==.',
Ba='Bajr:BAABNQAECn8dAAIJAAkKLAoHUwAKAQAJAAkKLAoHUwAKAQAAAA==.Bakura:BAABNQAECn8nAAIKAAoKChnvBACBAgAKAAoKChnvBACBAgAAAA==.Banker:BAABNQAECn8jAAIEAAgKOw+5LQDUAQAEAAgKOw+5LQDUAQAAAA==.Baroo:BAAANQAECgQIBQAAAA==.Barudd:BAAANQAECgEIAQAAAA==.',
Be='Berko:BAABNQAECn87AAILAAgK2SCGeACNAgALAAgK2SCGeACNAgAAAA==.Beyorne:BAAANQAECgIIAgAAAA==.',
Bh='Bhaang:BAAANQAECgYIEQAAAA==.',
Bi='Bigbear:BAAANQAFFAEIAQAAAA==.Bigbill:BAAANQAECgQIBAAAAA==.Bigdeath:BAABNQAECn8aAAIMAAYKlhZAiACQAQAMAAYKlhZAiACQAQAAAA==.Biletooth:BAAANQADCgcICgABNQAECgYIFgACABcHAA==.Bizco:BAABNQAECn8eAAIJAAkKshtGVAB0AgAJAAkKshtGVAB0AgAAAA==.',
Bj='Bjebo:BAABNQAECn8rAAIDAAoKbQxMRADiAQADAAoKbQxMRADiAQAAAA==.',
Bl='Bluffshot:BAABNQAECn8lAAIHAAgKHh7GFADVAgAHAAgKHh7GFADVAgAAAA==.',
Br='Brutes:BAAANQADCggICAABNQAFFAMIBgABAJsgAA==.Brynjalf:BAAANQAECgQIBwAAAA==.Bràe:BAAANQAECgEIAgAAAA==.',
Bu='Bulltan:BAAANQAECgEIAQAAAA==.',
Bx='Bxck:BAAANQAECgEIBAAAAA==.',
['Bï']='Bïcho:BAABNQAECn8cAAMNAAoKHRvwLgDLAgANAAoK9xrwLgDLAgAOAAIKtQvrZQBXAAAAAA==.',
Ca='Calambar:BAAANQAECgEIAgAAAA==.Cas:BAAANQADCgYIBgAAAA==.Casally:BAAANQADCgQIBAAAAA==.Cascadio:BAAANQAECgIIAgAAAA==.Castanza:BAAANQADCgQIBwAAAA==.Caswyn:BAAANQAECgQIDwAAAA==.',
Ch='Chapjong:BAAANQADCgQIBQAAAA==.Charjer:BAABNQAECn8hAAMPAAgKGhzWTQCgAgAPAAgKGBzWTQCgAgAQAAMK2BW9FQCDAAAAAA==.Chokengag:BAAANQADCgMIAwAAAA==.Choney:BAAANQAECgcICAAAAA==.',
Co='Codedgar:BAAANQADCgUIBQABNQAECgcIEQARAAAAAA==.Coffeeshot:BAAANQADCgcIDQAAAA==.Cojostudio:BAAANQADCggICAAAAA==.Comboost:BAAANQAECgQIBgAAAA==.Costcolshirt:BAAANQAECgEIAgAAAA==.',
Cr='Cranks:BAAANQAECgcICwAAAA==.Crashcake:BAABNQAECn8bAAIBAAkKyhygHAClAgABAAkKyhygHAClAgAAAA==.Creakybones:BAAANQAECgEIAgAAAA==.Croager:BAABNQAECn8ZAAIJAAoKOhy4MQDXAgAJAAoKOhy4MQDXAgAAAA==.',
Cu='Cup:BAABNQAECn8iAAIIAAgKQxObcgDAAQAIAAgKQxObcgDAAQAAAA==.',
Cv='Cvv:BAAANQADCgQIBAABNQAECgMIAwARAAAAAA==.',
Cy='Cyberlinde:BAAANQAECgQIDQAAAA==.Cywen:BAAANQADCggICAABNQAFFAYIGAAHAE0eAA==.',
Da='Daelaris:BAABNQAECn8hAAILAAoKWx9aQAAFAwALAAoKWx9aQAAFAwAAAA==.Damonoris:BAABNQAECn8ZAAIJAAkKcw1ejwDrAQAJAAkKcw1ejwDrAQAAAA==.Damthrax:BAAANQAECgQIBQAAAA==.Danielan:BAAANQAECgYICwAAAA==.Davegrôwl:BAAANQADCgEJAQABNQAECgYIFgACABcHAA==.',
De='Deadair:BAAANQAECgEIAgAAAA==.Deadlyalba:BAAANQAECgEIAQAAAA==.Deadzeo:BAAANQADCgYICQAAAA==.Dejavoid:BAAANQADCggICgAAAA==.Demonblades:BAABNQAECn8qAAIEAAgKKhnBHABvAgAEAAgKKhnBHABvAgAAAA==.Demonbreaker:BAABNQAECn8iAAISAAkK4BQKDQDyAQASAAkK4BQKDQDyAQAAAA==.Denarten:BAABNQAECn8hAAIGAAkKvSFYJgAsAwAGAAkKvSFYJgAsAwAAAA==.',
Di='Diotima:BAAANQADCgUICQAAAA==.Dirtymorris:BAAANQAECgcIEgAAAA==.Disrupt:BAAANQAECgQIBwAAAA==.',
Do='Dockevorkian:BAACNQAFFH8HAAITAAMKihS7DQDbAAATAAMKihS7DQDbAAA1AAQKfzQAAhMACgp+IHQXABoDABMACgp+IHQXABoDAAAA.Dornaaealdor:BAAANQADCgIIAgAAAA==.Dortwaz:BAABNQAECn8tAAMNAAoKTRtpIABtAQANAAkKpxtpIABtAQAOAAIKlhWNVACBAAAAAA==.Doublebonus:BAAANQADCggICAABNQAFFAMIBgABAJsgAA==.Dougdk:BAABNQAECn8zAAIFAAoK3iNwAwC6AwAFAAoK3iNwAwC6AwABNQAFFAEIAQARAAAAAA==.',
Dr='Dracoramonk:BAAANQAECgEIAQAAAA==.Dracoz:BAAANQADCgEIAQAAAA==.Dricex:BAAANQADCgYIBgABNQAECgMIAwARAAAAAA==.Drinnagon:BAAANQADCgcIBwABNQAECgkJIQAGAL0hAA==.Drinntellect:BAAANQAECgMIBgABNQAECgkJIQAGAL0hAA==.Drinnundead:BAAANQAECgEIAQABNQAECgkJIQAGAL0hAA==.Druelf:BAAANQAECgEIAwAAAA==.Dryblood:BAAANQADCgQIBAAAAA==.Dryx:BAAANQAECgIIAwAAAA==.',
Du='Dunaarn:BAAANQADCgMIAwAAAA==.',
Ea='Eargroan:BAAANQADCgYICwABNQAECgkJHgASAOYjAA==.',
El='Elilla:BAABNQAECn8fAAIFAAgKiwppYgBoAQAFAAgKiwppYgBoAQAAAA==.Elkminster:BAAANQAECgQIBQAAAA==.Ellenaya:BAAANQAECggIEAAAAA==.Elorela:BAAANQADCgQIBAABNQAECgoKHQAOALkXAA==.',
En='Enjoy:BAACNQAFFH8GAAIBAAMKmyBuDgD0AAABAAMKmyBuDgD0AAA1AAQKfyYAAwEACQoYJegHAGcDAAEACQqSJOgHAGcDAAIACQqPIm4nAJ0CAAAA.',
Fa='Famiki:BAAANQADCgcICwAAAA==.',
Fe='Feardotcom:BAAANQAECgEIAQAAAA==.Felnollid:BAABNQAECn8mAAMUAAkKWhuWHAC1AgAUAAkKWhuWHAC1AgAEAAUKewdWTQDxAAAAAA==.Fenanigans:BAABNQAECn8iAAIHAAkKeiDUCwApAwAHAAkKeiDUCwApAwAAAA==.Fenquisition:BAAANQAECgEIAQABNQAECgkJIgAHAHogAA==.',
Fi='Firebender:BAAANQADCgQIBQAAAA==.Firetiger:BAAANQADCgcIBwAAAA==.Fistandcider:BAAANQADCgMIAwAAAA==.',
Fl='Fluffyhusky:BAABNQAECn8iAAMVAAcK4ATGFgDHAAAWAAcKnQTXJgD+AAAVAAUKhAfGFgDHAAABNQAECgoKGgAJAOYMAA==.',
Fo='Fontss:BAAANQAECgYIBwAAAA==.Fonyfish:BAACNQAFFH8GAAINAAUKJgtEIgDnAAANAAUKJgtEIgDnAAA1AAQKfxcAAg0ACQpbFohuABMCAA0ACQpbFohuABMCAAAA.Forba:BAAANQAECgYIBgAAAA==.',
Fr='Frostybina:BAAANQADCgMIAwAAAA==.',
Fu='Fubina:BAEBNQAECn8yAAMXAAoKjxukDgD2AgAXAAoKjxukDgD2AgAYAAIK5R0zJgCcAAAAAA==.',
Fy='Fyjalla:BAAANQADCggIEAAAAA==.',
['Fâ']='Fâllênknîght:BAABNQAECn8gAAIFAAgKwRbbDgBsAQAFAAgKwRbbDgBsAQAAAA==.',
Ga='Gabh:BAAANQADCgYIBgAAAA==.Garazeb:BAAANQAECgEIAQABNQAECgUICAARAAAAAA==.',
Gi='Gilead:BAAANQAECgEIAQAAAA==.Gilgaglaive:BAABNQAECn8YAAIEAAkKIxYFHQBsAgAEAAkKIxYFHQBsAgAAAA==.',
Gl='Glomah:BAABNQAECn8oAAMFAAkKxSBFEwATAwAFAAkKxSBFEwATAwABAAIK6QXoVwBbAAAAAA==.Glorm:BAABNQAECn8pAAIZAAoK/xD2YwDhAQAZAAoK/xD2YwDhAQAAAA==.',
Go='Gobropro:BAAANQADCgYIBgAAAA==.Gorathan:BAAANQAECgEIAgAAAA==.Gotalock:BAAANQADCgYIBgAAAA==.',
Gr='Grabbyhands:BAABNQAECn8WAAMCAAYKFwdGNACLAAACAAUKgAhGNACLAAAFAAMK2wJnawAnAAAAAA==.Grantul:BAABNQAECn8uAAIaAAkKUBSGAgC2AQAaAAkKUBSGAgC2AQAAAA==.Grimthore:BAAANQAECgEIAQABNQAECggIFAAbAPIKAA==.Grolgan:BAAANQADCgYIBgAAAA==.Gromz:BAAANQAECggIEgAAAA==.',
Gu='Gulbhang:BAABNQAECn8sAAMNAAoKyRl+MwC7AgANAAoKyRl+MwC7AgAOAAEKXA+cdgA3AAAAAA==.',
Ha='Hakiranatha:BAAANQADCggICAAAAA==.',
Hb='Hbkdx:BAABNQAECn8VAAIJAAYKrQarZADhAAAJAAYKrQarZADhAAAAAA==.',
He='Health:BAAANQAECgMIAwAAAA==.',
Ho='Holdi:BAAANQADCgYIBgABNQAECggIIgAGANsPAA==.Holyhammer:BAAANQAECgcIDQAAAA==.Holyoke:BAAANQADCgEIAQAAAA==.Homunculus:BAAANQAECgcIBwAAAA==.',
Hu='Hujo:BAABNQAECn8bAAIPAAgKGRJ4iwD/AQAPAAgKGRJ4iwD/AQAAAA==.Hushpupi:BAABNQAECn8dAAMOAAoKuRcXCAB+AgAOAAoKuRcXCAB+AgANAAQKKApF+wDVAAAAAA==.Huskerpower:BAAANQADCgcJDQAAAA==.',
Ic='Iceharted:BAAANQAECgEIAwAAAA==.Icesloth:BAABNQAECn8dAAIMAAoK4hTKFgBpAQAMAAoK4hTKFgBpAQAAAA==.',
Id='Idamarie:BAABNQAECn8UAAIMAAYKXAKy9QCpAAAMAAYKXAKy9QCpAAAAAA==.Iduun:BAAANQADCgEIAQAAAA==.',
Il='Iladelle:BAABNQAECn8fAAIEAAgKxxKeCQB3AQAEAAgKxxKeCQB3AQAAAA==.',
In='Indecisa:BAAANQAECgEIAQAAAA==.',
Io='Iorak:BAAANQADCgEIAQAAAA==.',
Ir='Irinon:BAAANQAECgEIAQAAAA==.',
Ix='Ixiya:BAAANQAECgIIAgAAAA==.',
Ja='Jafud:BAAANQAFFAEIAQABNQAFFAYIGAAFAGIZAA==.Jafuds:BAAANQAFFAIIAgABNQAFFAYIGAAFAGIZAA==.Jaggerss:BAAANQAECgEIAQABNQAFFAMIBgABAJsgAA==.Jamaican:BAAANQADCgYIEAAAAA==.Jaste:BAAANQAECgYIEwAAAA==.',
Ji='Jimit:BAAANQADCgcIBwAAAA==.Jimmym:BAAANQAECgUIEAAAAA==.Jirakaidae:BAAANQADCgYICwABNQAECgUIDgARAAAAAA==.',
Jo='Jordis:BAAANQAECgIIAwAAAA==.',
Ju='Juicyfists:BAAANQADCgMIAwAAAA==.Juju:BAAANQAECgEIAQAAAA==.',
Ka='Kaedeyn:BAAANQAECgUIBwAAAA==.Kaeltharon:BAAANQADCgQIAwAAAA==.Kamekaze:BAAANQADCgYIBgAAAA==.Kandrys:BAAANQADCgQIBAAAAA==.Kasgotojim:BAAANQAECgQIBAAAAA==.Kaypop:BAAANQAECgQIBAAAAA==.Kayy:BAAANQADCgIIAgAAAA==.',
Ke='Kerrster:BAAANQADCgQIBAAAAA==.',
Kh='Khármá:BAABNQAECn8ZAAIbAAgKChd9BwCGAQAbAAgKChd9BwCGAQAAAA==.',
Ki='Kicklocks:BAAANQAECgMIAgAAAA==.Kikuri:BAAANQAECgYIDQAAAA==.Killahertz:BAAANQAECgEIAQAAAA==.Killt:BAABNQAECn8jAAIZAAgKphyXDwDdAQAZAAgKphyXDwDdAQAAAA==.',
Ko='Koojoé:BAAANQAECgQIBgAAAA==.',
Ku='Kurzulan:BAABNQAECn8dAAQcAAkKvwqbOgBLAQAcAAgKdgebOgBLAQAdAAMK5wN/VQBQAAADAAIKYgNptQAtAAAAAA==.',
La='Laghles:BAABNQAECn87AAIJAAoKmRtpIAAWAwAJAAoKmRtpIAAWAwAAAA==.Laroes:BAAANQAECgEIAQABNQAECgkJKAAFAMUgAA==.Larua:BAAANQABCgQJBAAAAA==.',
Le='Lemanjá:BAABNQAECn8XAAIeAAgKewYQEAAIAQAeAAgKewYQEAAIAQAAAA==.',
Li='Lightlooter:BAAANQADCgYIBgAAAA==.Liliane:BAABNQAECn8WAAIGAAoK2RG+pADXAQAGAAoK2RG+pADXAQAAAA==.Limbless:BAAANQAECggIDwAAAA==.',
Lo='Loahealth:BAAANQAECgcIEQAAAA==.Lockrocks:BAABNQAECn8sAAQNAAkKpxSqGACQAQANAAkKnBKqGACQAQAKAAYK3g9uDQCDAQAOAAUKCAfzLwAJAQABNQAECggIFAAbAPIKAA==.Lockstar:BAAANQADCgYIDAAAAA==.Loko:BAABNQAECn8YAAIZAAgKpAu4GgCGAQAZAAgKpAu4GgCGAQAAAA==.Lontra:BAAANQAECgEIAwAAAA==.Loozer:BAABNQAECn8UAAMbAAgK8gpeOQAiAQAGAAYKTwmD7wA9AQAbAAcKKAheOQAiAQAAAA==.Loralast:BAAANQADCgQIBAAAAA==.',
Lu='Luzifer:BAAANQADCgYIBgAAAA==.',
Ma='Magelyman:BAABNQAECn8ZAAILAAkKqBToQQA4AQALAAkKqBToQQA4AQAAAA==.Mahlaan:BAABNQAECn8qAAIFAAoKMxgVNgAzAgAFAAoKMxgVNgAzAgAAAA==.Malakai:BAAANQADCgIIAgABNQAECgUICgARAAAAAA==.Malekai:BAAANQAECgUJCQABNQAECgUICgARAAAAAA==.Malyce:BAAANQAECgUICgAAAA==.Malzen:BAAANQADCgMIAwABNQAECgUICgARAAAAAA==.Manaleia:BAAANQADCggIDAAAAA==.Manasolid:BAAANQADCgEIAQAAAA==.Mar:BAAANQAECgIIAgAAAA==.Marshusians:BAAANQAECgEIAgAAAA==.Maruug:BAAANQADCgYIBgAAAA==.Marvinah:BAAANQAECgIICAAAAA==.Maydie:BAAANQAECgcICAAAAA==.',
Me='Meatcurtin:BAAANQADCgQICAAAAA==.Meatlover:BAAANQAECgcICwAAAA==.Mediocre:BAABNQAECn8XAAIfAAgK+R7uBwDcAgAfAAgK+R7uBwDcAgAAAA==.Meeshka:BAABNQAECn8bAAILAAYKLw08YgD5AAALAAYKLw08YgD5AAAAAA==.Meraleona:BAAANQAECggIEwAAAA==.Methslinger:BAAANQAECggIEAAAAA==.',
Mi='Migue:BAAANQABCgEIAgABNQAECgoKSQAGACgiAA==.Miltonroe:BAAANQADCggICAABNQAECgkJKAAgABULAA==.',
Mo='Moarass:BAAANQAECgQJBgABNQAECgoKJwAcAIIVAA==.Moris:BAABNQAECn8WAAMOAAcKDAP2OQDZAAAOAAYKwwL2OQDZAAANAAcKWQL6BgG+AAAAAA==.Mortmuzi:BAAANQADCgYJBwAAAA==.Mosrael:BAABNQAECn8UAAIGAAgKCwUNmgCnAAAGAAgKCwUNmgCnAAAAAA==.',
Ms='Mswizzlë:BAABNQAECn8aAAIhAAgKRwbaFwA7AQAhAAgKRwbaFwA7AQAAAA==.',
Mu='Muldah:BAABNQAECn81AAMLAAoKDBbVJgB8AQALAAoKPRXVJgB8AQAhAAcK8QleHAANAQAAAA==.',
Na='Nas:BAABNQAECn8pAAMNAAoKsh3eDADkAQANAAkKyx3eDADkAQAOAAEKAB1OEgBKAAAAAA==.Nausicaa:BAAANQAECgEIAwAAAA==.Nausicaä:BAAANQAECgEIAQAAAA==.Navie:BAAANQAECgYIEwAAAA==.Nazgûl:BAAANQABCgYIBAAAAA==.',
Ne='Nekros:BAAANQADCgcIBwABNQAECggIIQAPABocAA==.Neø:BAABNQAECn8kAAMBAAkKlBmkOgDmAQABAAgK6hikOgDmAQACAAYK5R1KXwCSAQAAAA==.',
Ni='Nicebud:BAAANQAECgEIAQAAAA==.Nightsfury:BAAANQAECgYICgAAAA==.Nightshala:BAAANQAECgQIBAAAAA==.',
No='Nollid:BAAANQADCgYIBgABNQAECgkJJgAUAFobAA==.Nordburg:BAAANQAECgEIAQAAAA==.Nornyr:BAAANQADCgEIAQAAAA==.Notforgiven:BAAANQAECgEIAQAAAA==.Notnonna:BAAANQADCgQIBAAAAA==.',
Nu='Nunsrsus:BAAANQAECgcIEQAAAA==.',
Ny='Nymerias:BAAANQADCgYIDgAAAA==.Nyrrah:BAAANQAECgQIBgAAAA==.',
['Ná']='Nácht:BAAANQAECgYICgAAAA==.',
['Ný']='Nýghtmyst:BAAANQAECgEJAQAAAA==.',
Ok='Oku:BAAANQADCgUIBQAAAA==.',
Ol='Olaf:BAAANQAECgIIAgAAAA==.',
Om='Omaticaya:BAABNQAECn8vAAIDAAgKqQm2HAACAQADAAgKqQm2HAACAQAAAA==.Omèn:BAAANQADCgUIBQAAAA==.',
Op='Optikon:BAAANQAECgUIDQAAAA==.',
Or='Oriax:BAAANQAECgUICQABNQAECgkJNgADAN8YAA==.',
Ow='Owlbearcat:BAAANQAECgYIDwABNQAECgcIEQARAAAAAA==.',
Pa='Packerssuck:BAAANQADCgEIAQAAAA==.Paean:BAAANQADCgcIIAAAAA==.Paj:BAACNQAFFH8KAAILAAYK+wfTHACYAQALAAYK+wfTHACYAQA1AAQKfywAAgsACgqCHrAUAIADAAsACgqCHrAUAIADAAAA.',
Pe='Peata:BAAANQADCgMIAwAAAA==.Pelledrusil:BAAANQADCgUIBQAAAA==.Peria:BAAANQADCgYIBgABNQAECgMICQARAAAAAA==.',
Pi='Pinga:BAAANQAECgMIAwABNQAECgkJHgAJALIbAA==.',
Pk='Pkalygos:BAABNQAECn8fAAIiAAgKzQ+CBgBoAQAiAAgKzQ+CBgBoAQAAAA==.',
Pl='Pleione:BAAANQAECgYIEAAAAA==.',
Po='Portadave:BAAANQAECgMIAwAAAA==.Powerstrokee:BAAANQAECgQIBgAAAA==.',
Pr='Preyforme:BAABNQAECn8rAAIJAAgKpgleMABgAQAJAAgKpgleMABgAQAAAA==.Prusik:BAAANQADCgcIBwABNQAECgMIAwARAAAAAA==.Práystation:BAAANQADCgMIAwAAAA==.',
Ps='Psychelone:BAAANQAECgYICAAAAA==.',
Pu='Puffshot:BAAANQAECgEIAwABNQAECggIJQAHAB4eAA==.',
Qu='Quillan:BAAANQADCgUIDQABNQAECgcIEQARAAAAAA==.',
Qy='Qyxh:BAABNQAECn8ZAAMUAAgKZgxbQgCuAQAUAAgKZgxbQgCuAQASAAIKggMeMQA4AAAAAA==.',
Ra='Raine:BAAANQADCggIEAAAAA==.Rannath:BAAANQAECggIAwABNQAECggIFAAGAAsFAA==.Rastafarian:BAAANQADCgUICQAAAA==.',
Re='Redeye:BAAANQAECgEIAgAAAA==.Rehne:BAAANQAECgEIAQAAAA==.Rexhavoc:BAABNQAECn8kAAIEAAoKIRcwBQDBAQAEAAoKIRcwBQDBAQAAAA==.Rexion:BAAANQAECgEIAQAAAA==.',
Ri='Rigormortits:BAAANQAECgQIBAAAAA==.Ripre:BAAANQADCgUICwAAAA==.',
Ro='Rosary:BAABNQAECn8kAAIdAAcKQQX5MQAPAQAdAAcKQQX5MQAPAQAAAA==.Rosewoodren:BAAANQAECgQIAgAAAA==.',
Ru='Ruint:BAAANQADCgUIBQAAAA==.Runeclad:BAABNQAECn8WAAICAAgKQRgTRQAFAgACAAgKQRgTRQAFAgAAAA==.',
Ry='Ryla:BAAANQADCgIIAgABNQAECgkJJQAHABkZAA==.',
['Rï']='Rïvkah:BAAANQADCgUIBwABNQAECgQIBgARAAAAAA==.',
Sa='Saauurrora:BAAANQADCgYIBgAAAA==.Saintshift:BAAANQADCgEIAQABNQAECgMIAwARAAAAAA==.Salitheion:BAAANQAECgQIBgAAAA==.Sammaa:BAAANQAECgEIAQAAAA==.Sapper:BAABNQAECn83AAIjAAoKmyEoAwCCAwAjAAoKmyEoAwCCAwAAAA==.Sathi:BAAANQAECgIIAQAAAA==.Sayuri:BAAANQADCgEIAQAAAA==.',
Se='Sennest:BAAANQADCgUIAwAAAA==.',
Sh='Shikí:BAAANQAECgEIAgAAAA==.Shladoran:BAABNQAECn8dAAIPAAgKrwy2sQCgAQAPAAgKrwy2sQCgAQAAAA==.Shos:BAABNQAECn8qAAIQAAoKtx3jCADBAgAQAAoKtx3jCADBAgAAAA==.',
Si='Siberianwolf:BAAANQAECggICgAAAA==.Sinnister:BAAANQADCgYIBgAAAA==.Sitruc:BAAANQADCgQIBAAAAA==.',
Sk='Skully:BAAANQADCgUIBQABNQAFFAEIAQARAAAAAA==.',
Sl='Sledge:BAAANQADCgMIAwAAAA==.',
Sn='Snapdragyn:BAAANQAECgQIAgAAAA==.Snorina:BAABNQAECn8qAAIkAAoKcR6XDQATAwAkAAoKcR6XDQATAwAAAA==.',
So='Solàrflàré:BAAANQADCgMIAwAAAA==.Sosgoraan:BAAANQADCgcJBwABNQAECgoKKgAFADMYAA==.Sosozen:BAABNQAECn8cAAIXAAcKNwp4OABQAQAXAAcKNwp4OABQAQAAAA==.Soul:BAABNQAECn8UAAMdAAkKPBQbGwDLAQAdAAcK7RgbGwDLAQADAAUKiwRLLQCsAAAAAA==.',
Sp='Spirittoast:BAAANQAECgEIAQAAAA==.',
Sr='Sriman:BAAANQAECgYIBgAAAA==.',
St='Starkiller:BAAANQADCgYIDgAAAA==.Stonesolid:BAABNQAECn8uAAIPAAgKahriGQCeAQAPAAgKahriGQCeAQAAAA==.Stratovarius:BAAANQADCgYIBgAAAA==.',
Su='Sugouri:BAAANQAECggICAAAAA==.Sunnyginger:BAAANQAECgYIBgAAAA==.Supremacy:BAABNQAECn8hAAMNAAoKVSPzCwBtAwANAAoKVSPzCwBtAwAOAAEKzSE4YwBeAAAAAA==.',
Sw='Sweetspot:BAAANQAECgcIDgABNQAECggIFAAbAPIKAA==.Swiftshammy:BAAANQADCgQIBAAAAA==.Swytch:BAABNQAECn8lAAIHAAkKGRmiIwBrAgAHAAkKGRmiIwBrAgAAAA==.',
Sy='Sylrytherin:BAAANQADCgYICgABNQAECgoKKgAkAHEeAA==.Sylvii:BAABNQAECn8mAAIcAAgKqBKfKQDSAQAcAAgKqBKfKQDSAQAAAA==.',
Ta='Tabor:BAAANQAECgUICQAAAA==.Taggz:BAAANQAECgEIAwAAAA==.Taladryn:BAAANQADCgcIDQAAAA==.Tarahly:BAABNQAECn8gAAIIAAgKbiD9EADNAQAIAAgKbiD9EADNAQAAAA==.Tauryel:BAAANQAECgUIBwABNQAECggIDwARAAAAAA==.',
Te='Tekhan:BAAANQADCgQIBAAAAA==.Tethlis:BAAANQADCggICAABNQAECggIEgARAAAAAA==.',
Th='Thasarias:BAAANQAECgUICAAAAA==.Themoosifer:BAACNQAFFH8XAAIEAAcKPRcSAgBhAgAEAAcKPRcSAgBhAgA1AAQKfysAAgQACgriIBUOAAcDAAQACgriIBUOAAcDAAAA.Thunderdump:BAABNQAECn8mAAIZAAkKWxkIEQDPAQAZAAkKWxkIEQDPAQAAAA==.Thyck:BAABNQAECn8eAAIJAAkKihEgcgAtAgAJAAkKihEgcgAtAgAAAA==.Thydis:BAABNQAECn8zAAIGAAkK/QoMrwDBAQAGAAkK/QoMrwDBAQAAAA==.',
Ti='Tiancit:BAAANQAECgEIAwAAAA==.Tibbs:BAABNQAECn8qAAMWAAgKsxB8FQD1AQAWAAgK4Q98FQD1AQAVAAYKThCXEAAuAQAAAA==.Ticklepickle:BAAANQAECgQICgAAAA==.',
To='Tooch:BAAANQAECgEIAQAAAA==.Torluis:BAAANQADCgMIAwAAAA==.',
Tr='Trumalice:BAAANQADCgcIEQAAAA==.',
Tu='Tulpa:BAAANQAECgEIBQAAAA==.',
Un='Uncorrupted:BAABNQAECn8dAAMbAAkKTxM8KQCTAQAbAAgKIBY8KQCTAQAGAAIKigQ2sQEvAAAAAA==.',
Up='Updog:BAAANQAECgEIAQABNQAECgQICgARAAAAAA==.',
Va='Vaelm:BAAANQADCgcICgAAAA==.Valericia:BAAANQADCgQIBAAAAA==.Valindrux:BAABNQAECn8kAAMhAAkKgRXvCQDnAAALAAgKVhGfZgDwAAAhAAMKPhvvCQDnAAAAAA==.Valjin:BAAANQADCgQIBAABNQAECgkJJAAhAIEVAA==.Valsan:BAAANQAECgEIAQAAAA==.Valuryan:BAAANQADCggIEAABNQAECgkJJAAhAIEVAA==.Variana:BAAANQAECgEIAQAAAA==.',
Ve='Velathila:BAAANQAECgIIBQAAAA==.',
Vi='Victorsith:BAAANQADCgMIAwAAAA==.Violêt:BAAANQADCgYIBgAAAA==.Vizzelok:BAABNQAECn8ZAAIKAAcKbBBDCgDVAQAKAAcKbBBDCgDVAQAAAA==.',
Vo='Voidchris:BAABNQAECn8yAAMEAAoKmRobEADxAgAEAAkKUh0bEADxAgAUAAcK5A1GEwBQAQAAAA==.Voidormu:BAAANQAECgIIAwAAAA==.',
Wa='Warelf:BAABNQAECn8UAAMNAAkKICHJJgDpAgANAAkKICHJJgDpAgAOAAEKUxFBdAA6AAAAAA==.Warleck:BAAANQAECgUICAAAAA==.',
Wh='Whodey:BAAANQAECgUICQABNQAECgUICgARAAAAAA==.',
Wi='Wisp:BAAANQADCgYIDwAAAA==.',
Wy='Wylia:BAAANQAECgcIEQAAAA==.',
Xc='Xcw:BAAANQAECgIIAgAAAA==.',
Yu='Yuffshot:BAAANQAECgEIAwABNQAECggIJQAHAB4eAA==.',
Yy='Yyirium:BAAANQADCgIIAgAAAA==.',
Za='Zakkmorris:BAAANQADCgEIAQAAAA==.Zakuren:BAABNQAECn83AAIJAAoKJRZhJQCDAQAJAAoKJRZhJQCDAQAAAA==.',
Zi='Ziggi:BAAANQADCgYIBgABNQAECgMIAwARAAAAAA==.',
Zo='Zondoul:BAAANQADCgYIBgAAAA==.',
Zy='Zylera:BAAANQAECgMIBQAAAA==.Zyphor:BAAANQAECgEIAQAAAA==.Zyth:BAAANQABCgMIAgAAAA==.',
['Ñî']='Ñîx:BAABNQAECn8UAAMiAAcK4Q6CLwAhAQAiAAYKAAuCLwAhAQAWAAIKJw3EMwBvAAAAAA==.',
['Òm']='Òmêñ:BAAANQAECgYIBgAAAA==.',
['Ød']='Ødinson:BAAANQAECgEJAQAAAA==.',
['ßæ']='ßær:BAAANQAECgIJAwAAAA==.',
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
