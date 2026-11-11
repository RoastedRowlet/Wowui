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

local lookup = {'Shaman-Elemental','Paladin-Protection','Druid-Restoration','Hunter-BeastMastery','Warlock-Demonology','DemonHunter-Havoc','Shaman-Enhancement','Shaman-Restoration','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster','Hunter-Marksmanship','Warrior-Arms','Paladin-Retribution','Druid-Balance','Mage-Arcane','Rogue-Subtlety','Unknown-Unknown','DemonHunter-Devourer','DemonHunter-Vengeance','DeathKnight-Frost','Paladin-Holy','Rogue-Assassination','Rogue-Outlaw','DeathKnight-Blood','Mage-Frost','Warrior-Protection','Warrior-Fury','Monk-Windwalker','Priest-Shadow','Priest-Holy','Priest-Discipline','Warlock-Destruction','Warlock-Affliction','Druid-Guardian','Druid-Feral','DeathKnight-Unholy','Hunter-Survival','Monk-Mistweaver','Mage-Fire',}
local provider = {region='US',realm='Nazjatar',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aanon:BAAANQAECgEIAQAAAA==.',
Ab='Aberoth:BAAANQADCggIDAAAAA==.',
Ac='Accoli:BAAANQAECgUIBgAAAA==.Acslater:BAAANQADCgQIBAAAAA==.',
Ad='Adridan:BAAANQABCggIFQAAAA==.',
Ag='Agoobagoo:BAACNQAFFH8KAAIBAAMK+CBZFQAkAQABAAMK+CBZFQAkAQA1AAQKfxUAAgEACQpuHvEYADMDAAEACQpuHvEYADMDAAE1AAUUBwgJAAIA2hsA.',
Ah='Ahnka:BAAANQAECgEIAQABNQAECgoKQQADAG0kAA==.',
Al='Aliasx:BAAANQAECgQIBQAAAA==.Alissaria:BAAANQAECgEIAQAAAA==.Allarus:BAAANQADCgcICQAAAA==.Allwrong:BAAANQADCgQIBAAAAA==.Alotofsin:BAAANQAECgEIAgAAAA==.Alphadog:BAEBNQAECn9QAAIEAAoKLCFTGgDOAgAEAAoKLCFTGgDOAgAAAA==.Alwaysunny:BAAANQAECgEIAwAAAA==.',
Am='Amahlfarouk:BAABNQAECn8tAAIFAAgK2RRhdwBhAQAFAAgK2RRhdwBhAQAAAA==.Aminatou:BAABNQAECn87AAIGAAoKIhUFHgAHAgAGAAoKIhUFHgAHAgAAAA==.',
An='Anura:BAAANQADCggICAAAAA==.',
Ar='Ariaddne:BAABNQAECn8gAAQHAAkKthfKFQAMAgAHAAkK/xbKFQAMAgABAAYKbhQuswAsAQAIAAEKwRi6FAFAAAAAAA==.Arrowblack:BAAANQADCgEIAgAAAA==.Artemîs:BAAANQAECgMIAwAAAA==.',
As='Ashaelra:BAAANQAECgUIBgAAAA==.Asolitha:BAAANQADCgUIBQAAAA==.',
Au='Augonly:BAACNQAFFH8JAAIJAAMKABPJEADdAAAJAAMKABPJEADdAAA1AAQKfxQAAgkACAr1HWESAIYCAAkACAr1HWESAIYCAAAA.Augy:BAABNQAECn8mAAMKAAoKUxkgBwA+AgAKAAcK0hogBwA+AgALAAkKrBZsFQD1AQAAAA==.',
Ay='Aystria:BAAANQADCgMIAgAAAA==.',
Ba='Bakuretsu:BAABNQAECn8fAAIMAAkKdiKrAQAZAwAMAAkKdiKrAQAZAwABNQAECgoKPAAMACUcAA==.Balisong:BAAANQABCgIIAgAAAA==.Barhead:BAAANQADCggIDgAAAA==.Barlow:BAABNQAECn8pAAINAAkKvQLmMADXAAANAAkKvQLmMADXAAAAAA==.',
Bb='Bbldrizzy:BAACNQAFFH8NAAIBAAcKsxooCQDcAQABAAcKsxooCQDcAQA1AAQKfzMAAwEACgr7JLcRAGEDAAEACgr7JLcRAGEDAAgAAgpHGNa9AIwAAAAA.',
Be='Beastlieduke:BAAANQADCgYIDAABNQAECggIHQADAGUdAA==.Beastlièduke:BAAANQADCgIIAgABNQAECggIHQADAGUdAA==.Belephon:BAAANQAECgUIDQAAAA==.Belinda:BAAANQAECgYIDgAAAA==.',
Bi='Bighunt:BAAANQAECgMIBQAAAA==.Bijju:BAAANQAECggIEgAAAA==.Binggus:BAABNQAECn8XAAIOAAgKyh1+VQCKAgAOAAgKyh1+VQCKAgAAAA==.',
Bl='Blabbybootze:BAABNQAECn8hAAIPAAcKFwMrKgHaAAAPAAcKFwMrKgHaAAAAAA==.Bladelight:BAAANQAECgIIAQAAAA==.Blighte:BAAANQAECgQIBAABNQAFFAMIBQAQALUVAA==.Blightfangs:BAABNQAECn82AAIRAAoKBxfzQwAzAgARAAoKBxfzQwAzAgAAAA==.Bloodieelish:BAAANQAECgIIAgABNQAECggIGQASAJEOAA==.Bluzey:BAAANQAECgcIBwAAAA==.',
Bo='Bodakye:BAABNQAECn8zAAIEAAoKrBlZNABmAgAEAAoKrBlZNABmAgAAAA==.Boneplague:BAAANQADCgQIBAAAAA==.Boow:BAAANQAECgUIBQAAAA==.',
Br='Bracalina:BAAANQAECgYICAAAAA==.Brannix:BAAANQADCgUIBQAAAA==.Broggy:BAAANQADCgEIAQABNQAECgcICAATAAAAAA==.Brorgy:BAABNQAECn8bAAQUAAYKqQiFRQAmAQAUAAYKqQiFRQAmAQAVAAEKAADaOQAZAAAGAAEKSQH6jgAMAAABNQAECggIGQASAJEOAA==.Brovahkin:BAAANQAECgEIAgAAAA==.',
Bu='Bubbapal:BAAANQADCgUIBwAAAA==.Bushntush:BAAANQADCggICQAAAA==.Buzzbuzz:BAAANQAECgMIBAAAAA==.',
By='Bywar:BAAANQADCgcICwAAAA==.',
['Bé']='Bébop:BAAANQAECggIEgAAAA==.',
Ca='Caeruleus:BAAANQAECgEIAQAAAA==.Captyn:BAAANQAECggICwABNQAECgoKMwAEAKwZAA==.Catbum:BAAANQADCgIIAwAAAA==.Caylea:BAAANQADCggICAAAAA==.',
Ch='Chaosraven:BAABNQAECn9AAAIWAAoKMxDKNgCwAQAWAAoKMxDKNgCwAQAAAA==.Chapelgnome:BAAANQAECgQIBQABNQAECggIGQASAJEOAA==.Charlyne:BAAANQABCgMIAwAAAA==.Chewthymight:BAABNQAECn87AAMPAAoKJBV1egDEAQAPAAkKCBZ1egDEAQAXAAgKfQy3owDGAAAAAA==.Chickenslop:BAAANQAECgQIBwAAAA==.Chiffón:BAAANQAECgYICAAAAA==.Chiptime:BAAANQAECgUIDgAAAA==.Chloes:BAAANQAECgIIAgAAAA==.Chri:BAAANQAECgUICAAAAA==.Chrri:BAAANQAECgIIBAAAAA==.Chungotron:BAACNQAFFH8IAAMPAAYK9g6dDgBjAQAPAAUKEgudDgBjAQACAAEKhh5hDABZAAA1AAQKfyMAAg8ACgqHIy8QACQDAA8ACgqHIy8QACQDAAAA.Chzburger:BAAANQABCgIIBAAAAA==.',
Cl='Cladon:BAAANQAECggICAAAAA==.Clairity:BAAANQAECgUIBQAAAA==.',
Co='Cocoon:BAAANQAECgQIBAABNQAFFAQIEAARAAQXAA==.Colay:BAAANQADCgIIAgAAAA==.Conda:BAAANQAECggIEgAAAA==.Cormogh:BAABNQAECn8VAAMSAAcKnhyzNAAUAgASAAcKnhyzNAAUAgAYAAEK4Qm3YAA3AAAAAA==.Cousinseth:BAAANQAECgQIBAAAAA==.Cowhealer:BAACNQAFFH8FAAIQAAMKtRUdHQCqAAAQAAMKtRUdHQCqAAA1AAQKfzAAAxAACgpQIWYfANACABAACgpQIWYfANACAAMAAwrEDEtcAJYAAAAA.',
Cr='Craeftig:BAABNQAECn8hAAMYAAoKGxivDgDPAQAYAAoKGxivDgDPAQAZAAEKowHIHwAWAAAAAA==.Craeftigdk:BAABNQAECn8dAAIaAAcKAQ7nWgCHAQAaAAcKAQ7nWgCHAQABNQAECgoKIQAYABsYAA==.Craeftigtwo:BAAANQADCggJDQABNQAECgoKIQAYABsYAA==.Craeftigwl:BAAANQAECgIIAgABNQAECgoKIQAYABsYAA==.Crepitus:BAABNQAECn8WAAMSAAYKEgzZLQBTAQASAAYKEgzZLQBTAQAYAAIKWQXrlQBdAAAAAA==.Crusabull:BAAANQADCgcIBwAAAA==.Cræftig:BAABNQAECn8gAAMbAAoKUxvGBwBvAgAbAAkKCB/GBwBvAgARAAMKkwmJmQGTAAABNQAECgoKIQAYABsYAA==.',
Cu='Cuddlseraph:BAABNQAECn8WAAIXAAYKlhqLbQDPAQAXAAYKlhqLbQDPAQAAAA==.Cutestcc:BAAANQAECggIDgAAAA==.',
Cy='Cynnithice:BAAANQADCgIIAgABNQAECgYICAATAAAAAA==.',
Da='Daamdam:BAABNQAECn8ZAAIcAAgKjgPSLwC3AAAcAAgKjgPSLwC3AAAAAA==.Dadune:BAAANQABCgYICAABNQAECgUICgATAAAAAA==.Dafirenze:BAAANQADCggIDwAAAA==.Daftxshade:BAAANQAECgcICgAAAA==.Dariian:BAABNQAECn8WAAIdAAgKJALHKQBSAAAdAAgKJALHKQBSAAAAAA==.Darkbeef:BAABNQAECn8VAAIFAAYKDQOi9wDcAAAFAAYKDQOi9wDcAAAAAA==.Darkjusticeh:BAAANQAECgUIBwAAAA==.Darkmetal:BAAANQADCgEIAQAAAA==.Darktank:BAAANQADCgcIBwAAAA==.Darlang:BAAANQAECgUIDQAAAA==.Darthbjóurn:BAAANQAECgUIBgAAAA==.Darthmenace:BAAANQADCgQIBAAAAA==.Darthownage:BAAANQADCgYICwAAAA==.Darthsyde:BAABNQAECn8sAAIaAAoKYhKDJwC0AQAaAAoKYhKDJwC0AQABNQAECgoKMwAEAKwZAA==.Dayanna:BAAANQAECgEIAQAAAA==.',
De='Deadergriff:BAABNQAECn8VAAIaAAcKjxPbQwAgAQAaAAcKjxPbQwAgAQAAAA==.Deadicated:BAABNQAECn8ZAAIeAAgKawg+OwA6AQAeAAgKawg+OwA6AQAAAA==.Deadinsíde:BAAANQAECggICAABNQAECggIEAATAAAAAA==.Deathlyaura:BAAANQAECgEIAQABNQAECgUICQATAAAAAA==.Deathmark:BAAANQAECgUICQAAAA==.Deeznutzs:BAABNQAECn8fAAIRAAcKcQvvuAAhAQARAAcKcQvvuAAhAQAAAA==.Defendaya:BAAANQAECggICAAAAA==.Delan:BAAANQAECgYICAAAAA==.Demolishonn:BAAANQAECgUIEQAAAA==.Desunaito:BAACNQAFFH8QAAIWAAcKfRX7AwDkAQAWAAcKfRX7AwDkAQA1AAQKf0YAAhYACgqxJHYJAA8DABYACgqxJHYJAA8DAAAA.Dexter:BAAANQAECgQIBgAAAA==.',
Dh='Dhzilong:BAABNQAECn8WAAMUAAgKPxw3JwALAgAUAAgKmRs3JwALAgAGAAQK3g+3cwBNAAABNQAFFAgIDgAOABYRAA==.',
Di='Diddlefiddle:BAAANQADCgIIAgAAAA==.Dimeo:BAAANQADCgQIAQAAAA==.Dioji:BAAANQAECggIBgAAAA==.',
Dk='Dkzilong:BAAANQAECgIIBgABNQAFFAgIDgAOABYRAA==.',
Dm='Dmeo:BAAANQADCgMIAwAAAA==.',
Do='Docadoodle:BAAANQADCgcIBwABNQAFFAQIBgAUACYHAA==.Docarcanis:BAAANQAECgYIBwABNQAFFAQIBgAUACYHAA==.Docwyle:BAACNQAFFH8GAAIUAAQKJgfEEQA9AAAUAAQKJgfEEQA9AAA1AAQKfzMAAhQACgr4GIUYAJgCABQACgr4GIUYAJgCAAAA.Doozey:BAAANQABCgcJBwAAAA==.',
Dr='Dracmary:BAAANQADCgUIBQAAAA==.Dracnogard:BAAANQAECgUIDgAAAA==.Dracowulf:BAABNQAECn8qAAIEAAoKiQeSewCpAQAEAAoKiQeSewCpAQAAAA==.Dracuia:BAAANQAECgMIAwAAAA==.Dragonbro:BAAANQAECgMIAwAAAA==.Dragonx:BAABNQAECn84AAIEAAoK8w2nVgAHAgAEAAoK8w2nVgAHAgAAAA==.Drakowolf:BAABNQAECn8jAAILAAoK2QaBDwAzAQALAAoK2QaBDwAzAQAAAA==.Drama:BAAANQAECgEIAQAAAA==.Dreadful:BAABNQAECn9fAAIXAAoKYR+pCwBiAwAXAAoKYR+pCwBiAwAAAA==.Dreamchi:BAAANQAECgQIBQAAAA==.Dreorge:BAABNQAECn8XAAIJAAkKNBWxEwByAgAJAAkKNBWxEwByAgAAAA==.Drewceratops:BAABNQAECn8aAAIPAAkKVA+WnwDiAQAPAAkKVA+WnwDiAQAAAA==.Drewidd:BAAANQAECgUICQABNQAECggIGQASAJEOAA==.Drimchi:BAAANQAECgEIAgAAAA==.Drimveil:BAABNQAECn8ZAAIGAAkKPhgLLgA0AgAGAAkKPhgLLgA0AgAAAA==.Drogô:BAAANQAECgQICAAAAA==.Dromgar:BAABNQAECn8VAAMBAAkKpyJTJQA/AgABAAkKpyJTJQA/AgAIAAEKCQ6pEwFCAAABNQAECgoKIgAHANcmAA==.Dromkyr:BAABNQAECn80AAMJAAoKnQ+cGwAPAgAJAAoKnQ+cGwAPAgALAAEKNwtJPQAyAAAAAA==.Drossiechan:BAACNQAFFH8WAAIeAAYKPBIeBgAnAQAeAAYKPBIeBgAnAQA1AAQKfycAAh4ACgonHLwZAHQCAB4ACgonHLwZAHQCAAAA.',
Du='Duellipa:BAABNQAECn8ZAAMSAAgKkQ5OdgAlAQASAAcK7g9OdgAlAQAYAAQKwwajewDEAAAAAA==.',
Dy='Dysian:BAAANQADCgQIBQAAAA==.Dywanw:BAAANQABCgYIBgAAAA==.',
Ed='Edward:BAAANQAECggJBwAAAA==.',
Ef='Effloria:BAABNQAECn9BAAMDAAoKbSRkAwCSAwADAAoKbSRkAwCSAwAQAAEKAABgmgAAAAAAAA==.',
Ek='Ekim:BAAANQADCgQIAwAAAA==.Eklyps:BAAANQADCgYIBgAAAA==.',
El='Elauvia:BAAANQAECgUICAAAAA==.Elegia:BAAANQAECggIEAAAAA==.',
Em='Emleah:BAABNQAECn8bAAIHAAYK+gLGKACdAAAHAAYK+gLGKACdAAAAAA==.Emmaina:BAAANQAECgcIDgAAAA==.',
En='Enash:BAAANQADCgQIBAAAAA==.Encoredh:BAAANQAECgQIBAABNQAECggIIQAfAEcZAA==.Encoredk:BAAANQAECgEIAQAAAA==.Encoree:BAAANQADCgcIBwABNQAECggIIQAfAEcZAA==.Encoremts:BAAANQAECgEIAQABNQAECggIIQAfAEcZAA==.Encorep:BAABNQAECn8hAAQfAAgKRxnhJQAAAgAfAAcKBhfhJQAAAgAgAAQKTgnD2QBXAAAhAAIK2AM8FQBGAAAAAA==.Enris:BAAANQADCgUICAAAAA==.',
Es='Esael:BAAANQAECggIEAAAAA==.',
Ev='Evelari:BAAANQAECgEIAQAAAA==.Eviscerated:BAAANQAECgQIBQAAAA==.',
Ey='Eychlo:BAAANQAECgQIBAAAAA==.',
Fa='Fail:BAAANQADCgYICwAAAA==.Falker:BAAANQAECgIIAgAAAA==.Fallen:BAAANQAECggIDQAAAA==.Fallingvoid:BAAANQAFFAQIAgAAAA==.Fancyfeet:BAAANQADCgIIAwABNQAECgYIBgATAAAAAA==.Fatchungus:BAAANQAECgQIBgABNQAECgYIBgATAAAAAA==.Fateesia:BAAANQAECgEIAQAAAA==.',
Fe='Feathersong:BAAANQADCggIEgAAAA==.Fendru:BAABNQAECn8lAAIEAAoKWAmWbgDJAQAEAAoKWAmWbgDJAQAAAA==.Fextardo:BAAANQAECgMIAwAAAA==.',
Fi='Finaliter:BAACNQAFFH8HAAIPAAQKhw5jFwDDAAAPAAQKhw5jFwDDAAA1AAQKf0oAAg8ACgo+IUwWAAMDAA8ACgo+IUwWAAMDAAAA.',
Fl='Flamingdrago:BAAANQAECgQIBQAAAA==.Fletchiana:BAAANQAECgEIAQAAAA==.Flexatronic:BAAANQAECgcIDQABNQAECgcIHwARALMJAA==.Flirtyflurry:BAAANQAECgUIBwAAAA==.Flurrybloom:BAAANQADCgYICQAAAA==.',
Fo='Forsetie:BAAANQADCgMIAwAAAA==.Forsight:BAAANQADCgYIBgABNQAECgkJFQASAI8KAA==.Fox:BAACNQAFFH8OAAMZAAUKvBqNAQAxAQAZAAQK8hKNAQAxAQAYAAMKvBrhDgD8AAA1AAQKfzEAAxkACgo7IIoCAC8DABkACgpoHooCAC8DABgABwoaHnclAF8CAAAA.',
Fr='Freezerbúrnt:BAABNQAECn8bAAIWAAkKixBNKwDxAQAWAAkKixBNKwDxAQAAAA==.Fremder:BAAANQAECgUJCAAAAA==.Fresher:BAAANQAECgIIAgABNQAFFAcIDQABALMaAA==.Froggy:BAAANQAECggIEQAAAA==.Frogleap:BAAANQADCgUIBQABNQAECggIEQATAAAAAA==.Frogred:BAAANQADCgQIBAABNQAECggIEQATAAAAAA==.Frogtoad:BAAANQAECgUIDgABNQAECggIEQATAAAAAA==.',
Fu='Funeral:BAACNQAFFH8iAAQiAAgKUBq/AAB6AQAiAAQKvRy/AAB6AQAFAAQKfBtsEgBqAQAjAAMKjQtUAwDCAAA1AAQKfzcABCIACgp5JXABAHoDACIACQqEJHABAHoDAAUACQozJJUjAHUCACMAAgoEJgIcAKAAAAAA.Furiousmoon:BAAANQAECgEIAwAAAA==.Futuresailor:BAAANQAECgUICgAAAA==.',
Fy='Fyjhrt:BAABNQAECn81AAIZAAkKCSOAAAAUAwAZAAkKCSOAAAAUAwAAAA==.',
Ga='Galladin:BAAANQAECgcICQABNQAECgIIAgATAAAAAA==.Gallory:BAAANQAECggIDgAAAA==.',
Gd='Gdk:BAAANQAECgMIBQABNQAECgoKSAAHAIEbAA==.Gdkdrake:BAAANQADCgUIBQABNQAECgoKSAAHAIEbAA==.Gdkhunter:BAAANQADCggICAABNQAECgoKSAAHAIEbAA==.Gdkmage:BAABNQAECn8jAAIRAAoKhBCMVgAAAgARAAoKhBCMVgAAAgABNQAECgoKSAAHAIEbAA==.Gdkman:BAABNQAECn9IAAQHAAoKgRt7CwBQAgAHAAoKvxl7CwBQAgABAAkKVRuNTgA9AgAIAAIKlwjkCQFUAAAAAA==.Gdknotlock:BAAANQADCgQIBgABNQAECgoKSAAHAIEbAA==.',
Ge='Geoprince:BAAANQADCgcIEAAAAA==.Gerbon:BAAANQADCgMICAAAAA==.',
Gh='Ghaldrin:BAAANQABCggIEAAAAA==.Ghoulfriend:BAAANQADCgUICgAAAA==.',
Gi='Gigitty:BAAANQADCgYIBgAAAA==.Gimmedatneck:BAABNQAECn8iAAMYAAoKhB8lDAAmAwAYAAoKHh8lDAAmAwASAAUKPgrKQQCrAAABNQAFFAcIDQABALMaAA==.Githrogathan:BAABNQAECn8VAAIIAAcKphKZZQBuAQAIAAcKphKZZQBuAQAAAA==.',
Go='Gokudin:BAAANQADCgUIBAAAAA==.Goldenrager:BAAANQADCgQIBAAAAA==.Gooseandmav:BAAANQADCgEIAQAAAA==.',
Gr='Grabetta:BAAANQADCgEIAQAAAA==.Graegor:BAAANQADCgUIBQAAAA==.Gragasfat:BAAANQAECgIIAgAAAA==.Groundnpound:BAAANQADCgUJBQAAAA==.',
Gy='Gyanall:BAAANQADCgMIAwAAAA==.',
['Gâ']='Gârrosh:BAAANQADCgYIBgABNQAECgoKUgAEAI8PAA==.',
['Gö']='Gödhand:BAAANQAECgUICwAAAA==.',
Ha='Haeha:BAAANQAECgEIAQAAAA==.Haraldsson:BAAANQADCggICAAAAA==.Hargrumn:BAAANQABCgMIAgAAAA==.Harrypooc:BAAANQADCgQJBAAAAA==.Hasaro:BAACNQAFFH8JAAIkAAQKmwbRBQCSAAAkAAQKmwbRBQCSAAA1AAQKf0UAAiQACgrpFFcTAO0BACQACgrpFFcTAO0BAAAA.Hatcho:BAAANQADCgUICAAAAA==.Havokvacano:BAABNQAECn8jAAIPAAgKlQlj0gAeAQAPAAgKlQlj0gAeAQAAAA==.Havøckblaze:BAAANQADCgIIAgABNQADCgUIBAATAAAAAA==.',
He='Healmachine:BAAANQAECgMIDwAAAA==.Healzilla:BAAANQADCgYIBgAAAA==.Hellbrringer:BAAANQAECgEIAgAAAA==.Helzer:BAAANQADCggIDwABNQAECgoKTwAHALUeAA==.',
Ho='Holybaphomet:BAAANQADCgUICQAAAA==.Holyfarts:BAABNQAECn9CAAQhAAoKryJKAQBLAwAhAAoKgiBKAQBLAwAgAAgKNB9EMQCjAgAfAAoKQxiVEwAMAgAAAA==.Honeypaw:BAAANQADCgUIBQAAAA==.Hornedraven:BAAANQADCgEIAQAAAA==.',
Hu='Humanform:BAAANQADCgUIBQAAAA==.Hunbroll:BAAANQADCgYIBgABNQAECgkJIgANALQiAA==.Hungshaman:BAAANQABCgIIAgAAAA==.Hunterkiller:BAAANQADCggIGgAAAA==.',
Hx='Hx:BAAANQAECgQIBAAAAA==.',
Hy='Hypnoticpal:BAABNQAECn8cAAIPAAgKowIZOwGCAAAPAAgKowIZOwGCAAAAAA==.Hypnoticwar:BAAANQAECgIIAQAAAA==.Hythere:BAAANQAECgEIAQAAAA==.',
['Hõ']='Hõnor:BAABNQAECn9IAAMOAAoKBCTwHQBAAwAOAAoKvSPwHQBAAwAcAAUKJCJdFwC2AQABNQAFFAcICAAWAHIiAA==.',
Ia='Iammoo:BAAANQAECgIIAgAAAA==.',
Ig='Igriss:BAABNQAECn8VAAIOAAkKeBIErgCqAQAOAAkKeBIErgCqAQAAAA==.',
Il='Illidanx:BAAANQADCgQIBAAAAA==.Illuminaughd:BAABNQAECn8dAAMCAAoK/hW2FgCvAQACAAgKBBm2FgCvAQAPAAMKAg3yIgGiAAAAAA==.Ilumii:BAAANQAECgMIAwAAAA==.Ilydris:BAAANQAECgUICQAAAA==.',
Im='Imonthegcd:BAAANQAECgYIDQABNQAFFAcICAAWAHIiAA==.',
In='Infinitepain:BAACNQAFFH8KAAIgAAQK0w4pGQAWAQAgAAQK0w4pGQAWAQA1AAQKf0IAAiAACgp9I2QHAK8DACAACgp9I2QHAK8DAAE1AAQKAggCABMAAAAA.Innodk:BAABNQAECn8qAAIaAAoKNxFfJQDBAQAaAAoKNxFfJQDBAQAAAA==.',
Ir='Irami:BAAANQAECgEIAQAAAA==.Iridellis:BAAANQADCgcIBwABNQAECgoKXwAXAGEfAA==.',
Is='Ispankutank:BAAANQADCgEIAQAAAA==.',
It='Itslocotoo:BAAANQADCgEIAQAAAA==.Itwon:BAAANQAECgEIAQAAAA==.',
Ja='Jabzert:BAABNQAECn8UAAMkAAoKARJhHQCCAQAkAAYK+yBhHQCCAQAlAAgK2wc5IwDJAAABNQAECgoKSAAHAIEbAA==.Jahjahblinks:BAAANQADCgYIFAABNQAECgoKUgAEAI8PAA==.Jave:BAAANQABCgQIBQAAAA==.Jaycers:BAABNQAECn8tAAICAAoKyyEtCwDmAgACAAoKyyEtCwDmAgAAAA==.Jayclark:BAAANQADCgEIAQAAAA==.Jaçki:BAAANQAECggICAAAAA==.',
Ji='Jimmypal:BAABNQAECn8bAAIXAAYKyRdAWQCfAQAXAAYKyRdAWQCfAQAAAA==.',
Jo='Joedingle:BAABNQAECn84AAIRAAoKah12MABzAgARAAoKah12MABzAgAAAA==.Joemomma:BAAANQADCgUIBQAAAA==.Johnnyboi:BAAANQADCgEIAQAAAA==.Jokestarfist:BAABNQAECn8yAAIPAAkKIR2SOAB1AgAPAAkKIR2SOAB1AgAAAA==.',
Jr='Jr:BAAANQADCggICAAAAA==.',
Ju='Jumpy:BAAANQAECgEIAQAAAA==.',
Ka='Kaelar:BAAANQADCgMIAwABNQAECgoKQgAlAKIkAA==.Kaitokit:BAACNQAFFH8RAAMaAAUKuxoyEADnAAAaAAUKuxoyEADnAAAmAAEKeQKlJQA1AAA1AAQKf2AAAxoACgp4IYsIAPwCABoACgp4IYsIAPwCACYACAo/EPNdAJgBAAAA.Kalia:BAAANQADCgIIAgAAAA==.Kalyth:BAABNQAECn8dAAIBAAkKsweLYQBKAQABAAkKsweLYQBKAQAAAA==.Kamera:BAABNQAECn8aAAQPAAkKLx0WdgBBAgAPAAgKLx0WdgBBAgAXAAMK9gWh/QCBAAACAAEKAAAycgAtAAAAAA==.Kandessa:BAAANQADCgIIAwAAAA==.Kaylah:BAABNQAECn8/AAQZAAoKtCIaAQCrAgAZAAkKFCMaAQCrAgAYAAYKvh2yPwDOAQASAAQKYR0WZgBZAQAAAA==.Kayllina:BAABNQAECn8lAAIWAAkKnAO6cQDDAAAWAAkKnAO6cQDDAAAAAA==.Kayotic:BAABNQAECn8VAAIGAAYKxgNCYQCLAAAGAAYKxgNCYQCLAAAAAA==.',
Ke='Kelmorphic:BAABNQAECn9FAAIVAAoK7SJMAgBkAwAVAAoK7SJMAgBkAwAAAA==.',
Ki='Kiestus:BAAANQAECgEIAQAAAA==.Killcommand:BAAANQADCggICAABNQAFFAQIEAARAAQXAA==.',
Ko='Kosmas:BAAANQAECgEJAQAAAA==.',
Kr='Krombear:BAAANQADCgIIAgAAAA==.',
Ku='Kudai:BAAANQAECgUICAAAAA==.Kungpowchikn:BAAANQADCgIIAgAAAA==.Kurald:BAAANQAECgUIBQAAAA==.Kurisuw:BAAANQAECgYICwAAAA==.Kurookami:BAAANQADCgEIAQAAAA==.Kuukwa:BAAANQAECgUICAAAAA==.',
Ky='Kyana:BAAANQAECgYIDAAAAA==.Kyarina:BAAANQABCggIEQAAAA==.',
['Kí']='Kíller:BAABNQAECn8nAAQEAAkKAw5IiwCEAQAEAAkKvQtIiwCEAQAnAAcKjA3xCABGAQANAAMKWwXiaQCGAAAAAA==.',
La='Lamadda:BAAANQADCgUIBQAAAA==.Layonahands:BAAANQAECgMIAwAAAA==.',
Ld='Ldg:BAAANQADCgQIBAAAAA==.',
Le='Leafdaddy:BAAANQAECgUICQABNQAECgoKMwAMAFoeAA==.Leakoon:BAAANQADCggICAAAAA==.Ledana:BAAANQAECgMIAwAAAA==.Lelise:BAABNQAECn8UAAICAAgKzAGoXwBcAAACAAgKzAGoXwBcAAAAAA==.Letusgiveita:BAAANQADCgQIBAAAAA==.',
Li='Lightbringr:BAAANQADCgYICwAAAA==.Lightingbolt:BAAANQADCgUICwAAAA==.Lightshields:BAAANQADCgIIAgAAAA==.Lilmissta:BAAANQAECgQICQAAAA==.Lilpapi:BAAANQAECggIDgABNQAFFAYIFgAkACEiAA==.Lilymei:BAAANQADCggIGAAAAA==.Linesondra:BAAANQADCgUICgAAAA==.Linissa:BAAANQAECgQIBwAAAA==.Littledude:BAAANQADCgYIBgAAAA==.Littlemorsel:BAABNQAECn81AAIEAAoKPA2kZADjAQAEAAoKPA2kZADjAQAAAA==.Livalifa:BAABNQAECn8pAAMEAAoKdQ0FXwDxAQAEAAoKdQ0FXwDxAQANAAMKQgNQcwBqAAAAAA==.',
Lo='Lockenload:BAAANQAECgUIDgAAAA==.Lockme:BAAANQADCgUIBQAAAA==.Locktard:BAAANQAECgEIAQABNQAECgEIAgATAAAAAA==.Lohhar:BAAANQAECgEIAQAAAA==.Loser:BAAANQABCgQIBQAAAA==.Louthar:BAAANQAECggICAAAAA==.Lovin:BAAANQAECgQIBQAAAA==.',
Ls='Lselec:BAAANQAECgMJBQAAAA==.',
Lu='Lucens:BAABNQAECn8gAAIXAAgKXBABbgDOAQAXAAgKXBABbgDOAQAAAA==.Lucerna:BAABNQAECn8nAAIIAAoKpguTTQDEAQAIAAoKpguTTQDEAQAAAA==.Lunarfall:BAAANQADCgYIBgAAAA==.Lurchaug:BAAANQAECggIAwAAAA==.Lurchdh:BAAANQADCgQJBAABNQAFFAQIBgAbAEQGAA==.Lurchdruid:BAAANQAECgIIAQABNQAFFAQIBgAbAEQGAA==.Lurchmage:BAACNQAFFH8GAAIbAAQKRAZFCACKAAAbAAQKRAZFCACKAAA1AAQKfyoAAxsACgouFBoKAOgBABsACQouFBoKAOgBABEABgoWBR9HARcBAAAA.Lurchn:BAABNQAECn+FAAMbAAoKyh1cBADoAgAbAAoKyh1cBADoAgARAAkKowaj8ACpAQABNQAFFAQIBgAbAEQGAA==.Lurion:BAAANQADCgYIBgAAAA==.',
Ly='Lyricai:BAAANQAECgUIEgABNQAECgoKNAAIAKUdAA==.',
Ma='Madjake:BAAANQADCggICAAAAA==.Madmera:BAAANQAECggICAAAAA==.Maemae:BAAANQAECgEIAQAAAA==.Magallanes:BAAANQAECgQIBQAAAA==.Maggieaugers:BAAANQAECgcICwABNQAECggIGQASAJEOAA==.Mapleleaf:BAABNQAECn8gAAMkAAkKKSAKBgDqAgAkAAkKKSAKBgDqAgAlAAQKmggpKgCcAAAAAA==.Markyy:BAACNQAFFH8HAAIPAAQKPCLtDQAFAQAPAAQKPCLtDQAFAQA1AAQKf0UABA8ACgqwJfgEANIDAA8ACgqwJfgEANIDABcABgqmDzyUAGMBAAIAAQoAAHpgAFoAAAE1AAUUBwgIABYAciIA.Matas:BAABNQAECn8XAAIMAAkKWgUTFADQAAAMAAkKWgUTFADQAAAAAA==.Maylinfenora:BAABNQAECn8fAAIYAAgKhQzGRwCmAQAYAAgKhQzGRwCmAQAAAA==.Mazzikane:BAAANQADCgYIBgAAAA==.',
Me='Meangry:BAAANQAECgIIAgAAAA==.Meathookz:BAAANQAECgEIAgAAAA==.Meowizenith:BAAANQADCgUIBQAAAA==.Merdazin:BAAANQAECgQIDQAAAA==.Metalhedface:BAACNQAFFH8GAAIOAAQKAwtSHADCAAAOAAQKAwtSHADCAAA1AAQKfz0AAw4ACgpNGes4AE4CAA4ACgpNGes4AE4CAB0AAQq9GJ8uAEcAAAAA.',
Mi='Mikecoxwall:BAAANQADCgEIAQAAAA==.Millexista:BAAANQADCgMIAwAAAA==.Minisan:BAAANQADCgEIAQAAAA==.Misary:BAABNQAECn8XAAMgAAkKsgpicAByAQAgAAgKrApicAByAQAfAAkKpwcfIwBUAQAAAA==.Missamy:BAAANQADCgYIBgAAAA==.Mistake:BAABNQAECn8WAAIOAAkKghBrnwDOAQAOAAkKghBrnwDOAQAAAA==.Mixjarnter:BAAANQADCggIFgAAAA==.',
Mo='Mogyar:BAABNQAECn8bAAIPAAcKBRassgC5AQAPAAcKBRassgC5AQAAAA==.Moistybush:BAAANQAECgEIAQAAAA==.Moltalgol:BAAANQAECgQIDgAAAA==.Monkeli:BAABNQAECn8dAAIdAAcKkxViDQDhAQAdAAcKkxViDQDhAQAAAA==.Moocifer:BAAANQADCgcIDQAAAA==.Moocifermoo:BAAANQAECgIIAwAAAA==.Moogrim:BAAANQADCggIEAAAAA==.Moonsiand:BAEBNQAECn80AAIEAAgK3SDRIgAMAwAEAAgK3SDRIgAMAwABNQAECgoKUAAEACwhAA==.Morbidon:BAAANQAECgUIBgAAAA==.Moreldwiddle:BAABNQAECn8eAAMjAAgKshRzDwBYAQAjAAcKlBJzDwBYAQAFAAYK0RFNpQD3AAAAAA==.Morgaia:BAAANQAECgYIBwAAAA==.Morrigån:BAAANQADCgMIAwAAAA==.Mosschin:BAAANQAECgcIBwAAAA==.Motgus:BAABNQAECn8YAAQFAAgKhR6khQDYAQAFAAYKlR+khQDYAQAiAAIKZRxxRwCqAAAjAAIKVxvwHACWAAAAAA==.Mozzsticks:BAAANQADCgYICwAAAA==.',
Ms='Mshottie:BAAANQAECgcIEAAAAA==.',
Mx='Mx:BAAANQADCgYIDwAAAA==.',
My='Mystrialia:BAAANQABCgYIBgAAAA==.Mythlock:BAAANQADCgcIEwAAAA==.Mythranite:BAAANQADCgMIAwAAAA==.Myway:BAAANQADCggICAAAAA==.',
['Mó']='Mócha:BAABNQAECn8oAAQlAAkK4wc7IwDJAAAlAAcKPgk7IwDJAAAQAAUKegM8ZwB6AAAkAAEKAAByXwA2AAAAAA==.',
Na='Nardrian:BAAANQAECgQIBQAAAA==.Naydian:BAAANQAECgQIBQAAAA==.',
Ne='Necrozma:BAAANQAECggIDgAAAA==.Nekiron:BAAANQADCgQIBAAAAA==.Nellaa:BAAANQAECgcICAAAAA==.Nerrd:BAAANQAECgEIAQAAAA==.Nestaria:BAAANQADCggICAAAAA==.Netalanot:BAAANQADCgYIBgAAAA==.Nettik:BAAANQADCgUIBwAAAA==.Neverborn:BAABNQAECn8jAAIQAAcKnBBcVgB+AQAQAAcKnBBcVgB+AQAAAA==.',
Ni='Nightalucard:BAAANQADCgYIBgAAAA==.Nightrage:BAABNQAECn8VAAMGAAcKfwLOYwCBAAAGAAcKfwLOYwCBAAAUAAQKKgFBZABZAAAAAA==.Nilex:BAABNQAECn8gAAIOAAkK7xI2RQAhAgAOAAkK7xI2RQAhAgAAAA==.',
No='Nomadic:BAAANQADCgIIAgAAAA==.Notmypally:BAAANQAECgUIBQABNQAFFAQICQARAAcRAA==.',
Nu='Numera:BAAANQADCgIIAwABNQAECggIDwATAAAAAA==.Nutellaqq:BAABNQAECn8YAAIRAAcK1xrQuwAMAgARAAcK1xrQuwAMAgAAAA==.',
['Nê']='Nêkê:BAABNQAFFH8MAAIBAAYKzBALCgAjAQABAAYKzBALCgAjAQAAAA==.',
Ob='Obeseotter:BAABNQAECn8uAAIRAAgK6ReXowA6AgARAAgK6ReXowA6AgAAAA==.Oborax:BAEBNQAECn8nAAIPAAkKAhh8bgDfAQAPAAkKAhh8bgDfAQABNQAECgoKUAAEACwhAA==.',
Od='Od:BAAANQAECgMIAwAAAA==.',
Ol='Oliviabenson:BAABNQAECn8sAAIRAAkKMyClQAA9AgARAAkKMyClQAA9AgAAAA==.',
Or='Orchidusk:BAAANQADCggICAAAAA==.',
Ox='Oxsidius:BAAANQAECgQICwAAAA==.',
Pa='Palady:BAAANQADCgEIAQAAAA==.Palatard:BAAANQAECgEIAgAAAA==.Paldi:BAAANQAECgQIBAABNQAECgYIBgATAAAAAA==.Paliboos:BAAANQADCgYIBgAAAA==.Pallychri:BAAANQAECgYIBQAAAA==.Palulu:BAEANQAECggIDwAAAA==.Pandacub:BAAANQAECggICAAAAA==.Pariss:BAAANQAECggICgAAAA==.Paws:BAABNQAECn8gAAIQAAcKuwnASgDhAAAQAAcKuwnASgDhAAAAAA==.Pawse:BAAANQADCggIDwAAAA==.',
Pe='Peaky:BAABNQAECn86AAQoAAkKOQsPIwBqAQAoAAkKOQsPIwBqAQAMAAYK4ANdHABzAAAeAAIKNAGfbwArAAAAAA==.Perelia:BAABNQAECn8gAAIhAAcKrQ8QDAB6AQAhAAcKrQ8QDAB6AQAAAA==.',
Ph='Phlawless:BAAANQAECgMIAgAAAA==.',
Pl='Plondor:BAAANQABCgEIAQAAAA==.',
Po='Polarity:BAABNQAECn8pAAMfAAoK+wkQHgCGAQAfAAoK+wkQHgCGAQAgAAEKTwDGDgERAAABNQAECgoKMwAEAKwZAA==.Pooche:BAAANQAECgIIBgAAAA==.Popcola:BAAANQAECgQICQAAAA==.Pouts:BAAANQAECgQIBAABNQAFFAIICQATAAAAAA==.Powerpaladin:BAAANQAECgEIAQAAAA==.',
Pp='Ppc:BAAANQAECgQIDAABNQAFFAQIEAARAAQXAA==.',
Pr='Prezu:BAEBNQAECn8VAAIJAAcKnA4NKgBfAQAJAAcKnA4NKgBfAQABNQAECggIDwATAAAAAA==.Procyonx:BAAANQAECgEIAQAAAA==.Prophofdoom:BAABNQAECn8pAAIcAAkKYCHpBgDyAgAcAAkKYCHpBgDyAgAAAA==.Prõc:BAAANQADCggICAAAAA==.',
Pv='Pvc:BAACNQAFFH8QAAIRAAQKBBcVIQDqAAARAAQKBBcVIQDqAAA1AAQKfyEAAxEACgprIoxHAPQCABEACgprIoxHAPQCACkAAQqaAGAPACUAAAAA.',
Py='Pyrosong:BAAANQADCggICAAAAA==.',
Ra='Raisedead:BAAANQADCgIIAgABNQAECgEIAwATAAAAAA==.Rancord:BAAANQADCggICAAAAA==.Rangrr:BAAANQADCgMIAQAAAA==.Rasmira:BAAANQADCggICAAAAA==.Rastaqwon:BAAANQAECgEIAgABNQAECgQICQATAAAAAA==.Ratsmasher:BAAANQAECgIIAwAAAA==.Ravenight:BAAANQADCgMIAwAAAA==.Razed:BAAANQAECgEIAQAAAA==.Razerblade:BAAANQADCgYIBwAAAA==.',
Re='Renoitukax:BAABNQAECn80AAMgAAoKLiHXCwB1AwAgAAoKgx/XCwB1AwAhAAcKFh9KBgAuAgAAAA==.Restfuldark:BAAANQAECgUICQAAAA==.Retrobution:BAABNQAECn8xAAIPAAoKaSLGJwAnAwAPAAoKaSLGJwAnAwAAAA==.Rezz:BAAANQAECgcIDwAAAA==.',
Rh='Rhohir:BAAANQADCgYIBgAAAA==.',
Ri='Riru:BAAANQAECgQICAAAAA==.',
Ro='Rockstéady:BAAANQAECggIDQAAAA==.Roness:BAAANQABCgUIBQAAAA==.Roopall:BAABNQAECn8vAAIXAAoKVCATDwBSAwAXAAoKVCATDwBSAwAAAA==.Roxas:BAAANQADCggICQAAAA==.',
Ry='Rynzu:BAAANQAECgMIBAAAAA==.Ryzen:BAAANQAECgcIDQAAAA==.',
Sa='Sabelwin:BAAANQADCgEIAQAAAA==.Sanasrindis:BAAANQAECgEIAQAAAA==.Saninar:BAABNQAECn8rAAICAAoKZAvHMgBMAQACAAoKZAvHMgBMAQAAAA==.Sanshift:BAAANQAECgQIBwAAAA==.Satansimp:BAAANQAECgMIBwAAAA==.',
Sc='Schezmu:BAAANQAECgUICAAAAA==.',
Se='Sean:BAAANQADCgUICgAAAA==.Senorfiesta:BAABNQAECn88AAImAAkKzBfZGAAQAgAmAAkKzBfZGAAQAgAAAA==.Serazarke:BAAANQAECgEIAgAAAA==.Setazen:BAAANQAECgQIBgAAAA==.',
Sh='Shadowjoker:BAAANQAECgEIAgAAAA==.Shaee:BAABNQAECn8dAAMGAAYKyxdZQQC1AQAGAAYKyxdZQQC1AQAUAAEKAADRdQAjAAAAAA==.Shamama:BAAANQADCgUIBQAAAA==.Shamans:BAAANQAECgUIDAAAAA==.Shambalaya:BAAANQAECgcIEgAAAA==.Shaokhan:BAABNQAECn8jAAMOAAgKUwgQnwAqAQAOAAgKUwgQnwAqAQAdAAIKxwk2MwAtAAAAAA==.Shasta:BAACNQAFFH8WAAIkAAYKISLlAACDAQAkAAYKISLlAACDAQA1AAQKfzAAAiQACgo4JqwBAMUDACQACgo4JqwBAMUDAAAA.Shihthead:BAAANQADCgUIBQAAAA==.Shisuiuchiha:BAAANQADCgIIAgAAAA==.Shmorg:BAAANQADCgEIAQAAAA==.Shootumup:BAABNQAECn9GAAMnAAoKCyQVAQAcAwAnAAoKCyQVAQAcAwAEAAEKZRcjSwFJAAAAAA==.Shyx:BAABNQAECn88AAQgAAoKUyONFQAlAwAgAAoKUyONFQAlAwAfAAcKCw1nNQB4AQAhAAEKjRmbJQBBAAAAAA==.',
Si='Siilas:BAAANQAECgYIBgAAAA==.Simplèjack:BAABNQAECn8fAAIRAAcKswnF/wCOAQARAAcKswnF/wCOAQAAAA==.Sinamon:BAABNQAECn8YAAIPAAYKFxtC1ABzAQAPAAYKFxtC1ABzAQAAAA==.Sinani:BAAANQADCgUJBQAAAA==.Sinnamon:BAAANQABCgQJBAABNQAECgYIGAAPABcbAA==.',
Sj='Sjdh:BAAANQADCgYIBgABNQAECggICwATAAAAAA==.Sjrogue:BAAANQAECggICwAAAA==.',
Sk='Skar:BAAANQADCgUIBgAAAA==.Skram:BAAANQAECgUICQABNQAECgoKMwAPAJwNAA==.Skronker:BAAANQADCggIDQAAAA==.',
Sl='Slammydooker:BAABNQAECn8xAAMSAAoKRxjdIwBnAgASAAoKRxjdIwBnAgAYAAUKfw0RXwA5AQAAAA==.',
Sm='Smallkat:BAAANQAECgUIBgAAAA==.Smirksfotm:BAAANQAECgUICQABNQAECggIEAATAAAAAA==.Smoketail:BAAANQAECgUIBwAAAA==.',
Sn='Snail:BAAANQAECgYIBwAAAA==.Sneakmanman:BAAANQADCgYJCQAAAA==.',
So='Somberdh:BAAANQADCggICwAAAA==.Sorni:BAABNQAECn9IAAMPAAoK3wiUmgCCAQAPAAoK3wiUmgCCAQACAAIK7wK5awA7AAAAAA==.Soulglo:BAAANQAECgQIBAAAAA==.Soulmuncher:BAAANQAECgEIBAAAAA==.',
Sp='Spellslanger:BAAANQADCgQIBAAAAA==.Spikeprotein:BAAANQAECgEIAQAAAA==.Sprayandpray:BAABNQAECn8YAAIRAAoKSRw+PgBFAgARAAoKSRw+PgBFAgAAAA==.Spritey:BAAANQAECgEIAQAAAA==.',
Sq='Squidnips:BAAANQAECgEIAQAAAA==.',
St='Stareless:BAAANQAECgEIAQAAAA==.Statik:BAAANQAECgMIAwAAAA==.Stinkified:BAAANQAECgEIAQAAAA==.Stoneychri:BAAANQAECgMIAwAAAA==.Stormshadow:BAAANQAECgEIAQAAAA==.',
Su='Summondemons:BAAANQAECgIIBQAAAA==.Sumnèr:BAAANQADCgMIAwAAAA==.Sunpali:BAAANQAECgYIDQAAAA==.Susanno:BAAANQADCgUJCwAAAA==.',
Sy='Sylauda:BAAANQADCgYICgAAAA==.Sylvians:BAAANQAECgEIAwAAAA==.',
Ta='Tacutacudark:BAAANQAECgUIEAAAAA==.Taintedbeef:BAAANQADCgEIAQABNQAECgYIDwATAAAAAA==.Talonflame:BAABNQAECn8qAAQNAAgKHxWVLwDQAQANAAcKNhaVLwDQAQAEAAMKEReXFgHWAAAnAAIKiwqODgCHAAAAAA==.Talonted:BAAANQAECgIIAgAAAA==.Tandallei:BAAANQAECgQIBAAAAA==.Tansu:BAAANQAECgEIAQAAAA==.Tarishi:BAAANQAECgYIBwAAAA==.Tarishii:BAABNQAECn8WAAMGAAkK3xhWGQA2AgAGAAkKkxZWGQA2AgAVAAUKnRd5EgAMAQAAAA==.Tateraid:BAAANQABCgYICQAAAA==.Taterpuff:BAAANQAECgEIAQAAAA==.Taupo:BAAANQAECgEIAwAAAA==.Taxidermy:BAAANQADCgYIDAAAAA==.',
Te='Telarinda:BAABNQAECn8WAAMFAAoK5QfplgAXAQAFAAkKgwfplgAXAQAiAAIKkAqnaQBOAAAAAA==.',
Th='Thametal:BAAANQAECgIIAgAAAA==.Thicclich:BAABNQAECn8nAAIWAAoK1Q2lNAC7AQAWAAoK1Q2lNAC7AQAAAA==.Thicktotem:BAAANQAECgEIAQAAAA==.Thickumz:BAAANQAECgEIAQAAAA==.Thinmint:BAAANQAECgEIAQAAAA==.Thisismeta:BAAANQAECgYIDAAAAA==.Thorynwar:BAACNQAFFH8aAAIOAAgKCR7GCQAXAgAOAAgKCR7GCQAXAgA1AAQKfzkAAg4ACgr5JYQJAD8DAA4ACgr5JYQJAD8DAAE1AAUUBQgNACYAIhQA.Thorýn:BAACNQAFFH8NAAMmAAUKIhR7DgAkAQAmAAQKIhR7DgAkAQAaAAEKAABpKABXAAA1AAQKfyUAAyYACQpzJooQADMDACYACQpzJooQADMDABoABwriGR9HAN0BAAAA.Thyrnoch:BAAANQAECgEIAQAAAA==.Thórin:BAABNQAECn8XAAICAAkK4RNSKACbAQACAAkK4RNSKACbAQAAAA==.',
Ti='Tierax:BAABNQAECn89AAMSAAoK2h85CQDiAgASAAkKpiA5CQDiAgAYAAMKNxhWOgCdAAAAAA==.Tipsy:BAABNQAECn8yAAIIAAoKFRI1ZQDdAQAIAAoKFRI1ZQDdAQAAAA==.',
To='Tojì:BAAANQAECggIEAAAAA==.Tomfoolary:BAAANQAECgEIAQAAAA==.Tonathul:BAAANQADCggIEAAAAA==.Torrk:BAAANQAECgQIBAAAAA==.Torultrear:BAAANQAECgIIAgAAAA==.Tot:BAABNQAECn8qAAIIAAoKEgwIfwCPAQAIAAoKEgwIfwCPAQAAAA==.',
Tr='Tralleth:BAABNQAECn8nAAMKAAkKphkLDACZAQAKAAcK+xULDACZAQAJAAgK8A6mHwD7AAAAAA==.Trallock:BAAANQAECgEIAQAAAA==.Traumatized:BAAANQAECgEIAgAAAA==.Truska:BAAANQAECgEIAQAAAA==.',
Ts='Tsoi:BAAANQAECggICAAAAA==.',
Tu='Tuskyrex:BAAANQAECgEIAQAAAA==.',
Tw='Twinklord:BAABNQAECn8aAAMfAAoK7hqFKgDTAQAfAAcKjhSFKgDTAQAgAAYKIQ7VgwA0AQAAAA==.Twostroke:BAABNQAECn8yAAIEAAoKriXGBgCnAwAEAAoKriXGBgCnAwAAAA==.Twotoe:BAAANQAECgQIBAAAAA==.Twretwtwrewr:BAAANQADCgIIAgAAAA==.Twunkie:BAAANQADCgcIBwAAAA==.',
Ty='Tylanar:BAAANQAECgEIAQAAAA==.Tylopally:BAAANQAFFAIIAgAAAA==.Tyloremixdd:BAAANQAECgQIBAAAAA==.Tylototem:BAAANQAECgQIBAAAAA==.',
['Tö']='Tötem:BAAANQADCgMIAwABNQAFFAcICAAWAHIiAA==.',
Uj='Ujcpet:BAAANQAECgEIAgAAAA==.',
Un='Uncookedham:BAAANQAECgEIAQAAAA==.Underhorn:BAAANQAECgEIAgAAAA==.',
Va='Vaas:BAAANQADCggICAABNQAECgoKLQACAMshAA==.Vaeelrundor:BAABNQAECn8qAAIEAAcKhwo3nABfAQAEAAcKhwo3nABfAQAAAA==.Valyr:BAAANQADCgUIBAAAAA==.Vampslayer:BAAANQADCgYIBgAAAA==.Vanillaface:BAAANQAECggIEAAAAA==.Vañillaface:BAAANQABCgQIBgAAAA==.',
Ve='Vedebone:BAAANQAECgYIDgAAAA==.Vedexd:BAABNQAECn8pAAIEAAcKrRDfoADEAQAEAAcKrRDfoADEAQAAAA==.Velarael:BAABNQAECn8hAAMjAAgKAQ+/DQB8AQAjAAcK0RC/DQB8AQAFAAIKOgW69ABbAAAAAA==.Veletharia:BAAANQADCgQICAAAAA==.Velexi:BAAANQADCgQIBwAAAA==.Velpura:BAAANQADCgYIBgABNQAECggIIQAjAAEPAA==.Verzak:BAAANQAECgEIAQAAAA==.',
Vh='Vheckxus:BAABNQAECn8VAAIBAAUK7gt6kADTAAABAAUK7gt6kADTAAAAAA==.',
Vi='Vivi:BAAANQAECgMIAwAAAA==.',
Vl='Vlidya:BAAANQADCgEIAQAAAA==.',
Vo='Voidberg:BAAANQAECgYICQAAAA==.',
Vs='Vs:BAAANQAECggIDwAAAA==.',
Wa='Wachonaso:BAACNQAFFH8JAAIFAAQKgQtjGgAjAQAFAAQKgQtjGgAjAQA1AAQKfykAAwUACgooHV0/AJQCAAUACgq0HF0/AJQCACIAAwokHcwwAAUBAAAA.Wastedsage:BAAANQAECgUICgAAAA==.Waterlou:BAAANQAECgIIAgAAAA==.',
We='Weavefang:BAAANQADCgUIBwAAAA==.',
Wh='Whatuphuz:BAAANQADCggIEAAAAA==.Wheresmyjaw:BAACNQAFFH8MAAMFAAQKsRnSHACzAAAFAAMKHB/SHACzAAAiAAEK3A79DwBMAAA1AAQKf0IAAwUACgocJBoVAMQCAAUACQpmJBoVAMQCACIAAwpeGF89AMwAAAAA.',
Wi='Wildthree:BAABNQAECn8hAAIMAAgKFwwwDwAfAQAMAAgKFwwwDwAfAQAAAA==.Wilkieswar:BAAANQADCggIGAABNQAECgoKLgARADgfAA==.Willenda:BAAANQAECgEIAwAAAA==.Winterfall:BAAANQAECgUIBgAAAA==.',
Wu='Wuinn:BAACNQAFFH8PAAIJAAcKdgivCQCVAQAJAAcKdgivCQCVAQA1AAQKfy0ABAkACgrBF44VAFsCAAkACgrBF44VAFsCAAoABwo+EEwKAFEBAAsAAQpUDagjADgAAAAA.',
Xa='Xakutioner:BAABNQAECn9AAAIQAAoKVR+bFAAiAwAQAAoKVR+bFAAiAwAAAA==.Xaldiir:BAABNQAECn85AAIGAAoKYSJ8CgDpAgAGAAoKYSJ8CgDpAgAAAA==.',
Xe='Xenvoroo:BAAANQADCgIIAgAAAA==.Xerexia:BAABNQAECn9CAAIOAAkKQA8RowDFAQAOAAkKQA8RowDFAQAAAA==.Xeràth:BAAANQAECggICwAAAA==.',
Xs='Xsjàdo:BAAANQADCgYIBwAAAA==.',
Xw='Xwoo:BAAANQAECgQIBgAAAA==.',
Xz='Xzarlatan:BAAANQADCgIIAgAAAA==.Xzarlatanfi:BAAANQADCgUIBQAAAA==.',
Ya='Yahro:BAAANQAECgcIEgAAAA==.',
Ye='Yellowranger:BAABNQAECn9KAAIXAAoKfyEWCQCCAwAXAAoKfyEWCQCCAwAAAA==.',
Yj='Yjn:BAABNQAECn8pAAIMAAoK+hZRBQA6AgAMAAoK+hZRBQA6AgABNQAECgoKMwAEAKwZAA==.',
Yo='Yongyong:BAABNQAECn8dAAMFAAgKAhyoWAC3AQAFAAgKAhyoWAC3AQAiAAEKAAA8bgBCAAAAAA==.Yotoymuerto:BAAANQAECgEIAQAAAA==.',
Yu='Yunara:BAAANQAECgYIBgAAAA==.Yustayoke:BAABNQAECn8mAAIRAAgKihQarwAkAgARAAgKihQarwAkAgAAAA==.',
Za='Zalvianna:BAAANQAECgYICwAAAA==.Zarathoz:BAAANQABCgYJBgAAAA==.Zarshx:BAAANQADCgQICAABNQAECgYIBgATAAAAAA==.',
Ze='Zennithz:BAAANQAECggIEQAAAA==.Zeonz:BAAANQAECgEIAgAAAA==.',
Zh='Zhoya:BAAANQAECggICAAAAA==.',
Zi='Zilong:BAAANQAECgIIBQABNQAFFAgIDgAOABYRAA==.Zilongmage:BAAANQAECggICAABNQAFFAgIDgAOABYRAA==.Zilongwar:BAACNQAFFH8OAAIOAAgKFhGwCwD3AQAOAAgKFhGwCwD3AQA1AAQKfyIAAg4ACgp0Iq8sAAoDAA4ACgp0Iq8sAAoDAAAA.',
Zo='Zombor:BAAANQADCgIIAgAAAA==.Zonecw:BAABNQAECn8nAAMcAAoKGhidEQCHAQAOAAkKbQsedwCJAQAcAAkKGhidEQCHAQAAAA==.Zonedk:BAAANQAECgQIBwABNQAECgoKJwAcABoYAA==.',
['Ør']='Ørsted:BAAANQADCgIIAgABNQAECgEIAwATAAAAAA==.',
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
