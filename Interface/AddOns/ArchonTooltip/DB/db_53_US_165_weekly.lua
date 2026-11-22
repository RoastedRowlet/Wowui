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

local lookup = {'Shaman-Elemental','Paladin-Protection','Druid-Restoration','Hunter-BeastMastery','Warlock-Demonology','DemonHunter-Havoc','Shaman-Enhancement','Shaman-Restoration','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster','Hunter-Marksmanship','Warrior-Arms','Paladin-Retribution','Druid-Balance','Mage-Arcane','Rogue-Subtlety','Unknown-Unknown','DemonHunter-Devourer','DemonHunter-Vengeance','DeathKnight-Frost','Paladin-Holy','Rogue-Assassination','Rogue-Outlaw','Mage-Frost','DeathKnight-Blood','Warrior-Protection','Warrior-Fury','Monk-Windwalker','Priest-Shadow','Priest-Holy','Priest-Discipline','Warlock-Destruction','Warlock-Affliction','Druid-Guardian','Druid-Feral','DeathKnight-Unholy','Hunter-Survival','Monk-Mistweaver','Mage-Fire',}
local provider = {region='US',realm='Nazjatar',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aanon:BAAANQAECgEIAQAAAA==.',
Ab='Aberoth:BAAANQADCggIDAAAAA==.',
Ac='Accoli:BAAANQAECgUIBQAAAA==.Acslater:BAAANQADCgQIBAAAAA==.',
Ad='Adridan:BAAANQABCggIFQAAAA==.',
Ag='Agoobagoo:BAACNQAFFH8KAAIBAAMK+CBZFQAkAQABAAMK+CBZFQAkAQA1AAQKfxUAAgEACQpuHvEYADMDAAEACQpuHvEYADMDAAE1AAUUBwgJAAIA2hsA.',
Ah='Ahnka:BAAANQAECgEIAQABNQAECgoKQgADAG0kAA==.',
Al='Aliasx:BAAANQAECgQIBAAAAA==.Alissaria:BAAANQAECgEIAQAAAA==.Allarus:BAAANQADCgcICQAAAA==.Allwrong:BAAANQADCgQIBAAAAA==.Alotofsin:BAAANQAECgEIAQAAAA==.Alphadog:BAEBNQAECn9RAAIEAAoKLCGTHgDGAgAEAAoKLCGTHgDGAgAAAA==.Alwaysunny:BAAANQADCgYIDAAAAA==.',
Am='Am:BAAANQADCgUIBAAAAA==.Amahlfarouk:BAABNQAECn8wAAIFAAgKEBWQfwBiAQAFAAgKEBWQfwBiAQAAAA==.Aminatou:BAABNQAECn87AAIGAAoKIhWcIAAGAgAGAAoKIhWcIAAGAgAAAA==.',
An='Anura:BAAANQADCggICAAAAA==.',
Ar='Ariaddne:BAABNQAECn8gAAQHAAkKthfKFQAMAgAHAAkK/xbKFQAMAgABAAYKbhQuswAsAQAIAAEKwRi6FAFAAAAAAA==.Arrowblack:BAAANQADCgEIAgAAAA==.Artemîs:BAAANQAECgUIBgAAAA==.',
As='Ashaelra:BAAANQAECgUIBQAAAA==.Asolitha:BAAANQADCgUIBQAAAA==.',
Au='Augonly:BAABNQAFFH8JAAIJAAMKABPJEADdAAAJAAMKABPJEADdAAAAAA==.Augy:BAABNQAECn8mAAMKAAoKUxkgBwA+AgAKAAcK0hogBwA+AgALAAkKrBZsFQD1AQAAAA==.',
Ay='Aystria:BAAANQADCgMIAgAAAA==.',
Ba='Bakuretsu:BAABNQAECn8fAAIMAAkKdiLVAQAYAwAMAAkKdiLVAQAYAwABNQAECgoKPQAMACUcAA==.Balisong:BAAANQABCgMIBQAAAA==.Barhead:BAAANQADCggIDgAAAA==.Barlow:BAABNQAECn8wAAINAAoK3wLsLgD3AAANAAoK3wLsLgD3AAAAAA==.',
Bb='Bbldrizzy:BAACNQAFFH8NAAIBAAcKsxooCQDcAQABAAcKsxooCQDcAQA1AAQKfzsAAwEACgr7JLcRAGEDAAEACgr7JLcRAGEDAAgAAgpHGJbGAIsAAAAA.',
Be='Beastlieduke:BAAANQADCgYIDAABNQAECggIHQADAGUdAA==.Beastlièduke:BAAANQADCgIIAgABNQAECggIHQADAGUdAA==.Belephon:BAAANQAECgUICgAAAA==.Belinda:BAAANQAECgYIDAAAAA==.',
Bi='Bighunt:BAAANQAECgMIAwAAAA==.Bijju:BAAANQAECggIEgAAAA==.Binggus:BAABNQAECn8XAAIOAAgKyh1+VQCKAgAOAAgKyh1+VQCKAgAAAA==.',
Bl='Blabbybootze:BAABNQAECn8hAAIPAAcKFwMrKgHaAAAPAAcKFwMrKgHaAAAAAA==.Bladelight:BAAANQAECgIIAQAAAA==.Blighte:BAAANQAECgQIBAABNQAFFAMIBQAQALUVAA==.Blightfangs:BAABNQAECn9EAAIRAAoKbxfRRgA5AgARAAoKbxfRRgA5AgAAAA==.Bloodieelish:BAAANQAECgIIAQABNQAECggIGQASAJEOAA==.Bluzey:BAAANQAECgcIBwAAAA==.',
Bo='Bodakye:BAABNQAECn87AAIEAAoK6humJwChAgAEAAoK6humJwChAgAAAA==.Boneplague:BAAANQADCgQIBAAAAA==.Boow:BAAANQAECgUIBQAAAA==.Bordolor:BAAANQADCgEIAQAAAA==.',
Br='Bracalina:BAAANQAECgYIBwAAAA==.Brannix:BAAANQADCgUIBQAAAA==.Broggy:BAAANQADCgEIAQABNQAECgcICAATAAAAAA==.Brorgy:BAABNQAECn8bAAQUAAYKqQiFRQAmAQAUAAYKqQiFRQAmAQAVAAEKAADaOQAZAAAGAAEKSQE0lgAMAAABNQAECggIGQASAJEOAA==.',
Bu='Bubbapal:BAAANQADCgUIBwAAAA==.Bushntush:BAAANQADCggICQAAAA==.Buzzbuzz:BAAANQAECgMIBAAAAA==.',
By='Bywar:BAAANQADCgcICwAAAA==.',
['Bé']='Bébop:BAABNQAECn8YAAIEAAkKxAnXsQBOAQAEAAkKxAnXsQBOAQAAAA==.',
Ca='Caeruleus:BAAANQADCgQJBAAAAA==.Captyn:BAAANQAECggICAABNQAECgoKOwAEAOobAA==.Catbum:BAAANQADCgIIAwAAAA==.Caylea:BAAANQADCggICAAAAA==.',
Ch='Chaosraven:BAABNQAECn9AAAIWAAoKMxCgPACrAQAWAAoKMxCgPACrAQAAAA==.Chapelgnome:BAAANQAECgQIBAABNQAECggIGQASAJEOAA==.Charlyne:BAAANQABCgMIAwAAAA==.Chewthymight:BAABNQAECn9DAAMPAAoKvBfzUAA5AgAPAAoKvBfzUAA5AgAXAAgKfQw/rQDDAAAAAA==.Chickenslop:BAAANQAECgUIBgAAAA==.Chiffón:BAAANQAECggIDwAAAA==.Chiptime:BAAANQAECgUIDAAAAA==.Chloes:BAAANQAECgIIAgAAAA==.Chri:BAAANQAECgUIBwAAAA==.Chrri:BAAANQAECgIIAwAAAA==.Chungotron:BAACNQAFFH8JAAMPAAcK8hGdDgBjAQAPAAUKEgudDgBjAQACAAIKsB+XBwC5AAA1AAQKfyMAAg8ACgqHI+4SABoDAA8ACgqHI+4SABoDAAAA.Chzburger:BAAANQABCgIIBAAAAA==.',
Cl='Cladon:BAAANQAECggICAAAAA==.Clairity:BAAANQAECgUIBQAAAA==.',
Co='Cocoon:BAAANQAECgQIBAABNQAFFAQIEAARAAQXAA==.Colay:BAAANQADCgIIAgAAAA==.Conda:BAAANQAECggIEgAAAA==.Cormogh:BAABNQAECn8XAAMSAAgKpxsDJwBnAgASAAgKpxsDJwBnAgAYAAEK4Qn4YgA3AAAAAA==.Cousinseth:BAAANQAECgQIBAAAAA==.Cowhealer:BAACNQAFFH8FAAIQAAMKtRUdHQCqAAAQAAMKtRUdHQCqAAA1AAQKfzAAAxAACgpQIWYfANACABAACgpQIWYfANACAAMAAwrEDEtcAJYAAAAA.',
Cr='Craeftig:BAABNQAECn8hAAMYAAoKGxjdDwDKAQAYAAoKGxjdDwDKAQAZAAEKowHIHwAWAAABNQAECgoKKAAaACUgAA==.Craeftigdk:BAABNQAECn8dAAIbAAcKAQ7nWgCHAQAbAAcKAQ7nWgCHAQABNQAECgoKKAAaACUgAA==.Craeftigtwo:BAAANQADCggJDQABNQAECgoKKAAaACUgAA==.Craeftigwl:BAAANQAECgIIAgABNQAECgoKKAAaACUgAA==.Crepitus:BAABNQAECn8WAAMSAAYKEgzZLQBTAQASAAYKEgzZLQBTAQAYAAIKWQXrlQBdAAAAAA==.Crusabull:BAAANQADCgcIBwAAAA==.Cræftig:BAABNQAECn8oAAMaAAoKJSC/AgDoAgAaAAoKJSC/AgDoAgARAAMKkwmJmQGTAAAAAA==.',
Cu='Cuddlseraph:BAAANQAECgUIEgAAAA==.Cutestcc:BAAANQAECggIDgAAAA==.',
Cy='Cynnithice:BAAANQADCgIIAgABNQAECgYIBwATAAAAAA==.',
Da='Daamdam:BAABNQAECn8bAAIcAAgKogPSLwC3AAAcAAgKogPSLwC3AAAAAA==.Dadune:BAAANQABCgYICAABNQAECgUICQATAAAAAA==.Dafirenze:BAAANQADCggIDwAAAA==.Daftxshade:BAAANQAECgcICgAAAA==.Dariian:BAABNQAECn8WAAIdAAgKJAJ7LQBSAAAdAAgKJAJ7LQBSAAAAAA==.Darkbeef:BAABNQAECn8VAAIFAAYKDQOi9wDcAAAFAAYKDQOi9wDcAAAAAA==.Darkjusticeh:BAAANQAECgUIBwAAAA==.Darkmetal:BAAANQADCgEIAQAAAA==.Darktank:BAAANQADCgcICwAAAA==.Darlang:BAAANQAECgUIDQAAAA==.Darthbjóurn:BAAANQAECgUIBQAAAA==.Darthmenace:BAAANQAECgQIBAAAAA==.Darthownage:BAAANQADCgYIDgAAAA==.Darthsyde:BAABNQAECn8yAAIbAAoKuhSfJADWAQAbAAoKuhSfJADWAQABNQAECgoKOwAEAOobAA==.Dayanna:BAAANQADCggIDQAAAA==.',
De='Deadergriff:BAABNQAECn8VAAIbAAcKjxPySAAZAQAbAAcKjxPySAAZAQAAAA==.Deadicated:BAABNQAECn8ZAAIeAAgKawg+OwA6AQAeAAgKawg+OwA6AQAAAA==.Deadinsíde:BAAANQAECggICAABNQAECggIEAATAAAAAA==.Deathlyaura:BAAANQADCggICAABNQAECgUICAATAAAAAA==.Deathmark:BAAANQAECgUICAAAAA==.Deezenutsz:BAABNQAECn8lAAIRAAcKpgsbvwAoAQARAAcKpgsbvwAoAQAAAA==.Defendaya:BAAANQAECggICAAAAA==.Delan:BAAANQAECgYIBwAAAA==.Demolishonn:BAAANQAECgUIEQAAAA==.Desunaito:BAACNQAFFH8SAAIWAAgKexL7AwDkAQAWAAgKexL7AwDkAQA1AAQKf0YAAhYACgqxJMoKAAgDABYACgqxJMoKAAgDAAAA.Dexter:BAAANQAECgQIBQAAAA==.',
Dh='Dhzilong:BAABNQAECn8WAAMUAAgKPxw3JwALAgAUAAgKmRs3JwALAgAGAAQK3g+veQBNAAABNQAFFAgIDgAOABYRAA==.',
Di='Diddlefiddle:BAAANQADCgIIAgAAAA==.Dimeo:BAAANQADCgQIAQAAAA==.Dioji:BAAANQAECggIBgAAAA==.',
Dk='Dkzilong:BAAANQAECgIIBQABNQAFFAgIDgAOABYRAA==.',
Dm='Dmeo:BAAANQADCgMIAwAAAA==.',
Do='Docadoodle:BAAANQADCgcIBwABNQAFFAQIBgAUACYHAA==.Docarcanis:BAAANQAECgYIBgABNQAFFAQIBgAUACYHAA==.Docwyle:BAACNQAFFH8GAAIUAAQKJgf5EgA6AAAUAAQKJgf5EgA6AAA1AAQKfzUAAhQACgr4GIUYAJgCABQACgr4GIUYAJgCAAAA.Doozey:BAAANQABCgcJBwAAAA==.',
Dr='Dracmary:BAAANQADCgUIBQAAAA==.Dracnogard:BAAANQAECgUIDgAAAA==.Dracowulf:BAABNQAECn8sAAIEAAoKWwgOegDIAQAEAAoKWwgOegDIAQAAAA==.Dracuia:BAAANQAECgMIAwAAAA==.Dragonbro:BAAANQAECgMIAwAAAA==.Dragonx:BAABNQAECn8/AAIEAAoK0xAGUQArAgAEAAoK0xAGUQArAgAAAA==.Drakowolf:BAABNQAECn8lAAILAAoKRgd0EAA2AQALAAoKRgd0EAA2AQAAAA==.Drama:BAAANQAECgEIAQAAAA==.Dreadful:BAABNQAECn9fAAIXAAoKYR+PDQBYAwAXAAoKYR+PDQBYAwAAAA==.Dreamchi:BAAANQAECgQIBQAAAA==.Dreorge:BAABNQAECn8XAAIJAAkKNBWxEwByAgAJAAkKNBWxEwByAgAAAA==.Drewceratops:BAABNQAECn8aAAIPAAkKVA+WnwDiAQAPAAkKVA+WnwDiAQAAAA==.Drewidd:BAAANQAECgUIBwABNQAECggIGQASAJEOAA==.Drimchi:BAAANQAECgEIAQAAAA==.Drimveil:BAABNQAECn8ZAAIGAAkKPhgLLgA0AgAGAAkKPhgLLgA0AgAAAA==.Drogô:BAAANQAECgQICAAAAA==.Dromgar:BAABNQAECn8VAAMBAAkKpyJKKQA7AgABAAkKpyJKKQA7AgAIAAEKCQ6pEwFCAAABNQAECgoKIgAHANcmAA==.Dromkyr:BAABNQAECn80AAMJAAoKnQ+cGwAPAgAJAAoKnQ+cGwAPAgALAAEKNwtJPQAyAAAAAA==.Drossiechan:BAACNQAFFH8XAAIeAAcKXw+EBQBlAQAeAAcKXw+EBQBlAQA1AAQKfygAAh4ACgonHLwZAHQCAB4ACgonHLwZAHQCAAAA.',
Du='Duellipa:BAABNQAECn8ZAAMSAAgKkQ4ngQAlAQASAAcK7g8ngQAlAQAYAAQKwwajewDEAAAAAA==.',
Dy='Dysian:BAAANQADCgQIBQAAAA==.Dywanw:BAAANQABCgYIBgAAAA==.',
Ed='Ederi:BAAANQAECgEIAQAAAA==.Edward:BAAANQAECggJBwAAAA==.',
Ef='Effloria:BAABNQAECn9CAAMDAAoKbSRkAwCSAwADAAoKbSRkAwCSAwAQAAEKAACloQAAAAAAAA==.',
Ek='Ekim:BAAANQADCgQIAwAAAA==.Eklyps:BAAANQADCgYIBgAAAA==.',
El='Elauvia:BAAANQAECgUICAAAAA==.Elegia:BAAANQAECggIDgAAAA==.',
Em='Emleah:BAABNQAECn8cAAIHAAYK+gJaKwCdAAAHAAYK+gJaKwCdAAAAAA==.Emmaina:BAAANQAECgcIEAAAAA==.',
En='Enash:BAAANQADCgQIBAAAAA==.Encoredh:BAAANQAECgQIBAABNQAECggIIQAfAEcZAA==.Encoredk:BAAANQADCgIIAgAAAA==.Encoree:BAAANQADCgcIBwABNQAECggIIQAfAEcZAA==.Encoremts:BAAANQAECgEIAQABNQAECggIIQAfAEcZAA==.Encorep:BAABNQAECn8hAAQfAAgKRxnhJQAAAgAfAAcKBhfhJQAAAgAgAAQKTgnc4gBXAAAhAAIK2AMpFwBDAAAAAA==.Enris:BAAANQADCgUICAAAAA==.',
Es='Esael:BAABNQAECn8ZAAIaAAkKUQEENABbAAAaAAkKUQEENABbAAAAAA==.',
Ev='Eviscerated:BAAANQAECgQIBQAAAA==.Evoexdk:BAAANQABCgIIAgAAAA==.',
Ey='Eychlo:BAAANQAECgQIBAAAAA==.',
Fa='Fail:BAAANQADCgYICwAAAA==.Falker:BAAANQAECgIIAgAAAA==.Fallen:BAAANQAECggICwAAAA==.Fallingvoid:BAAANQAFFAQIAgAAAA==.Fancyfeet:BAAANQADCgIIAwABNQAECgYIBgATAAAAAA==.Fatchungus:BAAANQAECgQIBQABNQAECgYIBgATAAAAAA==.Fateesia:BAAANQAECgEIAQAAAA==.',
Fe='Feathersong:BAAANQADCggIGgAAAA==.Fendru:BAABNQAECn8rAAIEAAoKsAnQeADLAQAEAAoKsAnQeADLAQAAAA==.Fextardo:BAAANQAECgMIAwAAAA==.',
Fi='Finaliter:BAACNQAFFH8HAAIPAAQKhw52GgDAAAAPAAQKhw52GgDAAAA1AAQKf0oAAg8ACgo+ISoaAPkCAA8ACgo+ISoaAPkCAAAA.',
Fl='Flamingdrago:BAAANQAECgQIBQAAAA==.Fletchiana:BAAANQAECgEIAQAAAA==.Flexatronic:BAAANQAECgcIDQABNQAECgcIHwARALMJAA==.Flirtyflurry:BAAANQAECgUIBwAAAA==.Flurrybloom:BAAANQADCggIEQAAAA==.',
Fo='Forsetie:BAAANQADCgMIAwAAAA==.Forsight:BAAANQADCgYIBgABNQAECgkJFQASAI8KAA==.Fox:BAACNQAFFH8OAAMZAAUKvBqNAQAxAQAZAAQK8hKNAQAxAQAYAAMKvBrhDgD8AAA1AAQKfzEAAxkACgo7IIoCAC8DABkACgpoHooCAC8DABgABwoaHnclAF8CAAAA.',
Fr='Freezerbúrnt:BAABNQAECn8cAAIWAAkKXBKXKQAQAgAWAAkKXBKXKQAQAgAAAA==.Fremder:BAAANQAECgUJBgAAAA==.Fresher:BAAANQAECgIIAgABNQAFFAcIDQABALMaAA==.Froggy:BAAANQAECggIEAAAAA==.Frogleap:BAAANQADCgUIBQABNQAECggIEAATAAAAAA==.Frogred:BAAANQADCgQIBAABNQAECggIEAATAAAAAA==.Frogtoad:BAAANQAECgUIDgABNQAECggIEAATAAAAAA==.',
Fu='Funeral:BAACNQAFFH8kAAQiAAkKoxe/AAB6AQAiAAQKvRy/AAB6AQAFAAUK2hRsEgBqAQAjAAMKjQtUAwDCAAA1AAQKfzcABCIACgp5JXABAHoDACIACQqEJHABAHoDAAUACQozJOcnAHACACMAAgoEJgIcAKAAAAAA.Furiousmoon:BAAANQADCggICAAAAA==.Futuresailor:BAAANQAECgUICQAAAA==.',
Fy='Fyjhrt:BAABNQAECn81AAIZAAkKCSOPAAAQAwAZAAkKCSOPAAAQAwAAAA==.',
Ga='Galladin:BAAANQAECgcICAABNQAECgIIAQATAAAAAA==.Gallory:BAAANQAECggIDgAAAA==.',
Gd='Gdk:BAAANQAECgMIBAABNQAECgoKTgAHAC8cAA==.Gdkdrake:BAAANQADCgUIBQABNQAECgoKTgAHAC8cAA==.Gdkhunter:BAAANQADCggICAABNQAECgoKTgAHAC8cAA==.Gdkmage:BAABNQAECn8lAAIRAAoKhBAiXQD/AQARAAoKhBAiXQD/AQABNQAECgoKTgAHAC8cAA==.Gdkman:BAABNQAECn9OAAQHAAoKLxx9CwBiAgAHAAoK5xp9CwBiAgABAAkKVRuNTgA9AgAIAAIKlwjkCQFUAAAAAA==.Gdknotlock:BAAANQADCgQIBgABNQAECgoKTgAHAC8cAA==.',
Ge='Geoprince:BAAANQADCgcIEAAAAA==.Gerbon:BAAANQADCgMICAAAAA==.',
Gh='Ghaldrin:BAAANQABCggIEAAAAA==.Ghoulfriend:BAAANQADCgUICgAAAA==.',
Gi='Gigitty:BAAANQADCgYIBgAAAA==.Gimmedatneck:BAABNQAECn8iAAMYAAoKhB8lDAAmAwAYAAoKHh8lDAAmAwASAAUKPgrKQQCrAAABNQAFFAcIDQABALMaAA==.Githrogathan:BAABNQAECn8VAAIIAAcKphK2bgBnAQAIAAcKphK2bgBnAQAAAA==.',
Go='Gokudin:BAAANQADCgUIBAAAAA==.Goldenrager:BAAANQADCgQIBAAAAA==.Gooseandmav:BAAANQADCgEIAQAAAA==.',
Gr='Grabetta:BAAANQADCgEIAQAAAA==.Graegor:BAAANQADCgUIBQAAAA==.Gragasfat:BAAANQAECgIIAgAAAA==.Groundnpound:BAAANQADCgUJBQAAAA==.',
Gy='Gyanall:BAAANQADCgMIAwAAAA==.',
['Gâ']='Gârrosh:BAAANQADCgYIBgABNQAECgoKVQAEAI8PAA==.',
['Gö']='Gödhand:BAAANQAECgUICwAAAA==.',
Ha='Haeha:BAAANQADCgQIBAAAAA==.Haraldsson:BAAANQADCggICAAAAA==.Hargrumn:BAAANQABCgMIAgAAAA==.Harrypooc:BAAANQADCgQJBAAAAA==.Hasaro:BAACNQAFFH8JAAIkAAQKmwZbBgCOAAAkAAQKmwZbBgCOAAA1AAQKf0UAAiQACgrpFMgVAOYBACQACgrpFMgVAOYBAAAA.Hatcho:BAAANQADCgUICAAAAA==.Havokvacano:BAABNQAECn8kAAIPAAkKvQnLxgBHAQAPAAkKvQnLxgBHAQAAAA==.Havøckblaze:BAAANQADCgIIAgABNQADCgUIBAATAAAAAA==.',
He='Healmachine:BAAANQAECgMICwAAAA==.Healzilla:BAAANQADCgYIBgAAAA==.Hellbrringer:BAAANQAECgEIAQAAAA==.Helzer:BAAANQADCggIDwABNQAECggICAATAAAAAA==.',
Ho='Holybaphomet:BAAANQADCgUICQAAAA==.Holyfarts:BAABNQAECn9CAAQhAAoKryJKAQBLAwAhAAoKgiBKAQBLAwAgAAgKNB9EMQCjAgAfAAoKQxg7FQAMAgAAAA==.Honeypaw:BAAANQADCgUIBQAAAA==.Hornedraven:BAAANQADCgEIAQAAAA==.',
Hu='Humanform:BAAANQADCgUIBQAAAA==.Hunbroll:BAAANQADCgYIBgABNQAFFAcIIgAaABYZAA==.Hungshaman:BAAANQABCgIIAgAAAA==.Hunterkiller:BAAANQADCggIGgAAAA==.',
Hx='Hx:BAAANQAECgQIBAAAAA==.',
Hy='Hypnoticpal:BAABNQAECn8cAAIPAAgKowK9SwGAAAAPAAgKowK9SwGAAAAAAA==.Hypnoticwar:BAAANQAECgIIAQAAAA==.Hythere:BAAANQAECgEIAQAAAA==.',
['Hõ']='Hõnor:BAABNQAECn9IAAMOAAoKBCTwHQBAAwAOAAoKvSPwHQBAAwAcAAUKJCJdFwC2AQABNQAFFAcIDQAWAOkjAA==.',
Ia='Iammoo:BAAANQAECgIIAgAAAA==.',
Ig='Igriss:BAABNQAECn8VAAIOAAkKeBIErgCqAQAOAAkKeBIErgCqAQAAAA==.',
Il='Illidanx:BAAANQADCgQIBAAAAA==.Illuminaughd:BAABNQAECn8kAAMCAAoKIRj2EQANAgACAAkKIhr2EQANAgAPAAMK2g8WKgGsAAAAAA==.Ilumii:BAAANQAECgMIAwAAAA==.Ilydris:BAAANQAECgUICQAAAA==.',
Im='Imonthegcd:BAAANQAECgYIDQABNQAFFAcIDQAWAOkjAA==.',
In='Infinitepain:BAACNQAFFH8KAAIgAAQK0w5VHAAQAQAgAAQK0w5VHAAQAQA1AAQKf0YAAiAACgqSIxIGANEDACAACgqSIxIGANEDAAE1AAQKAggCABMAAAAA.Innodk:BAABNQAECn8vAAIbAAoKFhNzIgDmAQAbAAoKFhNzIgDmAQAAAA==.',
Io='Iolyte:BAAANQAECggIBQABNQAECgoKOwAEAOobAA==.',
Ir='Irami:BAAANQAECgEIAQAAAA==.Iridellis:BAAANQADCgcIBwABNQAECgoKXwAXAGEfAA==.',
Is='Ispankutank:BAAANQADCgEIAQAAAA==.',
It='Itslocotoo:BAAANQADCgEIAQAAAA==.Itwon:BAAANQAECgIIAwAAAA==.',
Ja='Jabzert:BAABNQAECn8UAAMkAAoKARIxIACBAQAkAAYK+yAxIACBAQAlAAgK2wcFJwDJAAABNQAECgoKTgAHAC8cAA==.Jahjahblinks:BAAANQADCgYIFAABNQAECgoKVQAEAI8PAA==.Jave:BAAANQABCgQIBQAAAA==.Jaycers:BAABNQAECn8tAAICAAoKyyEtCwDmAgACAAoKyyEtCwDmAgAAAA==.Jayclark:BAAANQADCgEIAQAAAA==.Jaçki:BAAANQAECggICAAAAA==.',
Ji='Jimmypal:BAABNQAECn8dAAIXAAgKphWvRAABAgAXAAgKphWvRAABAgAAAA==.',
Jo='Joedingle:BAABNQAECn9AAAIRAAoK2h5DLACOAgARAAoK2h5DLACOAgAAAA==.Joemomma:BAAANQADCgUIBQAAAA==.Johnnyboi:BAAANQADCgEIAQAAAA==.Jokestarfist:BAABNQAECn8yAAIPAAkKIR0WQABqAgAPAAkKIR0WQABqAgAAAA==.',
Jr='Jr:BAAANQADCggICAAAAA==.',
Ju='Jumpy:BAAANQABCgUIBgAAAA==.',
Ka='Kaelar:BAAANQADCgMIAwABNQAECgoKQgAlAKIkAA==.Kaitokit:BAACNQAFFH8RAAMbAAUKuxrpEgDfAAAbAAUKuxrpEgDfAAAmAAEKeQKlJQA1AAA1AAQKf2kAAxsACgrnIVAHABMDABsACgrnIVAHABMDACYACAo/EPNdAJgBAAAA.Kalia:BAAANQADCgIIAgAAAA==.Kalyth:BAABNQAECn8dAAIBAAkKswfYaQBKAQABAAkKswfYaQBKAQAAAA==.Kamera:BAABNQAECn8aAAQPAAkKLx0WdgBBAgAPAAgKLx0WdgBBAgAXAAMK9gWh/QCBAAACAAEKAAAycgAtAAAAAA==.Kandessa:BAAANQADCgIIAwAAAA==.Kaylah:BAABNQAECn9BAAQZAAoKBSMqAQCvAgAZAAkKcSMqAQCvAgAYAAYKvh2yPwDOAQASAAQKYR11cABYAQAAAA==.Kayllina:BAABNQAECn8tAAIWAAoKRgQlYwANAQAWAAoKRgQlYwANAQAAAA==.Kayotic:BAABNQAECn8gAAIGAAcKIQRhXQCuAAAGAAcKIQRhXQCuAAAAAA==.',
Ke='Kelmorphic:BAABNQAECn9FAAIVAAoK7SJMAgBkAwAVAAoK7SJMAgBkAwAAAA==.',
Ki='Kiestus:BAAANQAECgEIAQAAAA==.Killcommand:BAAANQADCggICAABNQAFFAQIEAARAAQXAA==.',
Ko='Kosmas:BAAANQAECgEJAQAAAA==.',
Kr='Krombear:BAAANQADCgIIAgAAAA==.',
Ku='Kudai:BAAANQAECgUICAAAAA==.Kungpowchikn:BAAANQADCgIIAgAAAA==.Kurald:BAAANQAECgUIBQAAAA==.Kurisuw:BAAANQAECgYICwAAAA==.Kurookami:BAAANQADCgEIAQAAAA==.Kuukwa:BAAANQAECgUICAAAAA==.',
Ky='Kyana:BAAANQAECgYIDAAAAA==.Kyarina:BAAANQABCggIEQAAAA==.',
['Kí']='Kíller:BAABNQAECn8nAAQnAAkKAw6nCQBGAQAEAAkKvQu7mACDAQAnAAcKjA2nCQBGAQANAAMKWwXiaQCGAAAAAA==.',
La='Lamadda:BAAANQADCgUIBQAAAA==.Lanadelslayy:BAAANQADCgYIBgAAAA==.Layonahands:BAAANQAECgMIAwAAAA==.',
Ld='Ldg:BAAANQADCgQIBAAAAA==.',
Le='Leafdaddy:BAAANQAECgUICQABNQAECgoKMwAMAFoeAA==.Leakoon:BAAANQADCggICAAAAA==.Ledana:BAAANQAECgMIAwAAAA==.Lelise:BAABNQAECn8UAAICAAgKzAGoXwBcAAACAAgKzAGoXwBcAAAAAA==.Letusgiveita:BAAANQADCgQIBAAAAA==.',
Li='Lightbringr:BAAANQADCgYICwAAAA==.Lightingbolt:BAAANQADCgUICwAAAA==.Lightshields:BAAANQADCgIIAgAAAA==.Lilmissta:BAAANQAECgQICgAAAA==.Lilpapi:BAAANQAECggIDQABNQAFFAcIFwAkAJchAA==.Lilymei:BAAANQADCggIGAAAAA==.Linesondra:BAAANQADCgUICgAAAA==.Linissa:BAAANQAECgQIBgAAAA==.Littledude:BAAANQADCgYIBgAAAA==.Littlemorsel:BAABNQAECn81AAIEAAoKPA0RcADhAQAEAAoKPA0RcADhAQAAAA==.Livalifa:BAABNQAECn81AAMEAAoKJw4AZwD3AQAEAAoKJw4AZwD3AQANAAMKQgNQcwBqAAAAAA==.',
Lo='Lockenload:BAAANQAECgUIDAAAAA==.Lockme:BAAANQADCgUIBQAAAA==.Lohhar:BAAANQADCggIFQAAAA==.Loser:BAAANQABCgQIBQAAAA==.Louthar:BAAANQAECggICAAAAA==.Lovin:BAAANQAECgQIBQAAAA==.',
Ls='Lselec:BAAANQAECgMIBQAAAA==.',
Lu='Lucens:BAABNQAECn8gAAIXAAgKXBABbgDOAQAXAAgKXBABbgDOAQAAAA==.Lucerna:BAABNQAECn8vAAIIAAoKKA8tRgD6AQAIAAoKKA8tRgD6AQAAAA==.Lunarfall:BAAANQADCgYIBgAAAA==.Lurchaug:BAAANQAECggIAwAAAA==.Lurchdh:BAAANQADCgQJBAABNQAFFAQIBgAaAEQGAA==.Lurchdruid:BAAANQAECgIIAQABNQAFFAQIBgAaAEQGAA==.Lurchmage:BAACNQAFFH8GAAIaAAQKRAaHCQCKAAAaAAQKRAaHCQCKAAA1AAQKfy4AAxoACgqjFEYLAOsBABoACgqjFEYLAOsBABEABgoWBR9HARcBAAAA.Lurchn:BAABNQAECn+NAAMaAAoKBx5cBADoAgAaAAoKBx5cBADoAgARAAkKowaj8ACpAQABNQAFFAQIBgAaAEQGAA==.Lurion:BAAANQADCgYIBgAAAA==.',
Ly='Lyricai:BAAANQAECgUIDwABNQAECgoKOgAIABEeAA==.',
['Lò']='Lòrdvader:BAAANQABCgIIAgAAAA==.',
Ma='Madjake:BAAANQADCggICAAAAA==.Madmera:BAAANQAECggICAAAAA==.Magallanes:BAAANQAECgQIBAAAAA==.Maggieaugers:BAAANQAECgcICwABNQAECggIGQASAJEOAA==.Mapleleaf:BAABNQAECn8pAAMkAAkKMiPRAwAvAwAkAAkKMiPRAwAvAwAlAAQKmghxLgCcAAAAAA==.Markyy:BAACNQAFFH8HAAIPAAQKPCKPEAAAAQAPAAQKPCKPEAAAAQA1AAQKf0UABA8ACgqwJfgEANIDAA8ACgqwJfgEANIDABcABgqmDzyUAGMBAAIAAQoAAHpgAFoAAAE1AAUUBwgNABYA6SMA.Matas:BAABNQAECn8XAAIMAAkKWgWgFQDQAAAMAAkKWgWgFQDQAAAAAA==.Maylinfenora:BAABNQAECn8fAAIYAAgKhQzGRwCmAQAYAAgKhQzGRwCmAQAAAA==.Mazzikane:BAAANQADCgYIBgAAAA==.',
Me='Meangry:BAAANQAECgIIAgAAAA==.Meowizenith:BAAANQADCgUIBQAAAA==.Merdazin:BAAANQAECgQIDAAAAA==.Metalhedface:BAACNQAFFH8GAAIOAAQKAwtfHwDCAAAOAAQKAwtfHwDCAAA1AAQKf0EAAw4ACgr8GfU3AGACAA4ACgr8GfU3AGACAB0AAQq9GJ8uAEcAAAAA.',
Mi='Mikecoxwall:BAAANQADCgEIAQAAAA==.Millexista:BAAANQADCgMIAwAAAA==.Minisan:BAAANQADCgEIAQAAAA==.Misary:BAABNQAECn8bAAMgAAkK0gp4eABxAQAgAAgK0Ap4eABxAQAfAAkKdQjCIgBwAQAAAA==.Missamy:BAAANQADCgYIBgAAAA==.Mistake:BAABNQAECn8WAAIOAAkKghBrnwDOAQAOAAkKghBrnwDOAQAAAA==.Mixjarnter:BAAANQADCggIFgAAAA==.',
Mo='Mogyar:BAABNQAECn8bAAIPAAcKBRassgC5AQAPAAcKBRassgC5AQAAAA==.Moistybush:BAAANQAECgEIAQAAAA==.Moltalgol:BAAANQAECgQICgAAAA==.Monkeli:BAABNQAECn8dAAIdAAcKkxViDQDhAQAdAAcKkxViDQDhAQAAAA==.Moocifer:BAAANQADCgcIDQAAAA==.Moocifermoo:BAAANQAECgIIAQAAAA==.Moogrim:BAAANQADCggIEAAAAA==.Moonsiand:BAEBNQAECn80AAIEAAgK3SDRIgAMAwAEAAgK3SDRIgAMAwABNQAECgoKUQAEACwhAA==.Morbidon:BAAANQAECgUIBgAAAA==.Moregan:BAAANQAECgMIAwAAAA==.Moreldwiddle:BAABNQAECn8fAAMjAAkKxBRzDwBYAQAjAAcKlBJzDwBYAQAFAAcKYBKIkQA3AQAAAA==.Morgaia:BAAANQAECgYIBQAAAA==.Morrigån:BAAANQADCgMIAwAAAA==.Mosschin:BAAANQAECgcIBwAAAA==.Motgus:BAABNQAECn8YAAQFAAgKhR6khQDYAQAFAAYKlR+khQDYAQAiAAIKZRxxRwCqAAAjAAIKVxvwHACWAAAAAA==.Mozzsticks:BAAANQADCgYICwAAAA==.',
Ms='Mshottie:BAAANQAECgcIDgAAAA==.',
Mx='Mx:BAAANQADCgYIDwAAAA==.',
My='Mystrialia:BAAANQABCgYIBgAAAA==.Mythlock:BAAANQADCgcIEwAAAA==.Mythranite:BAAANQADCgMIAwAAAA==.Myway:BAAANQADCggICAAAAA==.',
['Mó']='Mócha:BAABNQAECn8oAAQlAAkK4wfoHwAZAQAlAAcKPgnoHwAZAQAQAAUKegNpbAB6AAAkAAEKAAByXwA2AAAAAA==.',
Na='Nardrian:BAAANQAECgQIBQAAAA==.Naydian:BAAANQAECgQIBAAAAA==.',
Ne='Necrozma:BAAANQAECggIDgAAAA==.Nekiron:BAAANQADCgQIBAAAAA==.Nellaa:BAAANQAECgcICAAAAA==.Nerrd:BAAANQAECgEIAQAAAA==.Nestaria:BAAANQADCggICAAAAA==.Netalanot:BAAANQADCgYIBgAAAA==.Nettik:BAAANQADCgUIBwAAAA==.Neverborn:BAABNQAECn8jAAIQAAcKnBBcVgB+AQAQAAcKnBBcVgB+AQAAAA==.',
Ni='Nightalucard:BAAANQADCgYIBgAAAA==.Nightrage:BAABNQAECn8VAAMGAAcKfwKVaQB/AAAGAAcKfwKVaQB/AAAUAAQKKgFBZABZAAAAAA==.Nilex:BAABNQAECn8iAAIOAAkKJROYSQAjAgAOAAkKJROYSQAjAgAAAA==.',
No='Nomadic:BAAANQAECgEIAQAAAA==.Notmypally:BAAANQAECgUIBQABNQAFFAQICQARAAcRAA==.',
Nu='Numera:BAAANQADCgIIAwABNQAECggIDwATAAAAAA==.Nutellaqq:BAABNQAECn8YAAIRAAcK1xrQuwAMAgARAAcK1xrQuwAMAgAAAA==.',
['Nê']='Nêkê:BAABNQAFFH8MAAIBAAYKzBDHCwAgAQABAAYKzBDHCwAgAQAAAA==.',
Ob='Obeseotter:BAABNQAECn8uAAIRAAgK6ReXowA6AgARAAgK6ReXowA6AgAAAA==.Oborax:BAEBNQAECn8tAAIPAAkK2hj+bAD2AQAPAAkK2hj+bAD2AQABNQAECgoKUQAEACwhAA==.',
Od='Od:BAAANQAECgMIAgAAAA==.',
Ol='Oliviabenson:BAABNQAECn8tAAIRAAkKMyDSRgA5AgARAAkKMyDSRgA5AgAAAA==.',
Or='Orchidusk:BAAANQADCggICgAAAA==.',
Ox='Oxsidius:BAAANQAECgQICAAAAA==.',
Pa='Palady:BAAANQADCgEIAQAAAA==.Palatard:BAAANQAECgEIAQAAAA==.Paldi:BAAANQAECgQIBAABNQAECgYIBgATAAAAAA==.Paliboos:BAAANQADCgYIBgAAAA==.Pallychri:BAAANQAECgYIBQAAAA==.Palulu:BAEANQAECggIDwAAAA==.Pandacub:BAAANQAECggICAAAAA==.Pariss:BAAANQAECggICgAAAA==.Paws:BAABNQAECn8gAAIQAAcKuwmZTwDhAAAQAAcKuwmZTwDhAAAAAA==.Pawse:BAAANQADCggIDwAAAA==.',
Pe='Peaky:BAABNQAECn86AAQoAAkKOQsPIwBqAQAoAAkKOQsPIwBqAQAMAAYK4AMrHgBzAAAeAAIKNAGfbwArAAAAAA==.Perelia:BAABNQAECn8hAAIhAAgKUw4QDAB6AQAhAAgKUw4QDAB6AQAAAA==.',
Ph='Pheralta:BAAANQADCgQIBAAAAA==.Phlawless:BAAANQAECgMIAgAAAA==.',
Pl='Plondor:BAAANQABCgEIAQAAAA==.',
Po='Polarity:BAABNQAECn8qAAMfAAoK+wl7IACGAQAfAAoK+wl7IACGAQAgAAEKTwDGDgERAAABNQAECgoKOwAEAOobAA==.Pooche:BAAANQAECgIIAwAAAA==.Popcola:BAAANQAECgQICQAAAA==.Pouts:BAAANQAECgQIBAABNQAFFAIICgATAAAAAA==.Powerpaladin:BAAANQABCgQIBAAAAA==.',
Pp='Ppc:BAAANQAECgQICwABNQAFFAQIEAARAAQXAA==.',
Pr='Prezu:BAEBNQAECn8VAAIJAAcKnA4NKgBfAQAJAAcKnA4NKgBfAQABNQAECggIDwATAAAAAA==.Procyonx:BAAANQAECgEIAQAAAA==.Prophofdoom:BAABNQAECn8pAAIcAAkKYCHpBgDyAgAcAAkKYCHpBgDyAgAAAA==.Prõc:BAAANQADCggICAAAAA==.',
Pv='Pvc:BAACNQAFFH8QAAIRAAQKBBd6JgDeAAARAAQKBBd6JgDeAAA1AAQKfyEAAxEACgprIoxHAPQCABEACgprIoxHAPQCACkAAQqaAGAPACUAAAAA.',
Py='Pyrosong:BAAANQADCggICAAAAA==.',
Ra='Raisedead:BAAANQADCgIIAgABNQADCggIDAATAAAAAA==.Rancord:BAAANQADCggICAAAAA==.Rangrr:BAAANQADCgMIAQAAAA==.Rasmira:BAAANQADCggICAAAAA==.Rastaqwon:BAAANQAECgEIAgABNQAECgQICQATAAAAAA==.Ratsmasher:BAAANQAECgIIAgAAAA==.Ravenight:BAAANQADCgMIAwAAAA==.Razed:BAAANQADCgYICwAAAA==.Razerblade:BAAANQADCgYIBwAAAA==.',
Re='Renoitukax:BAABNQAECn83AAMgAAoKeCG2DAB7AwAgAAoKzR+2DAB7AwAhAAcKFh9KBgAuAgAAAA==.Restfuldark:BAAANQAECgUICQAAAA==.Retrobution:BAABNQAECn8xAAIPAAoKaSLGJwAnAwAPAAoKaSLGJwAnAwAAAA==.Rezz:BAAANQAECgcIDAAAAA==.',
Rh='Rhohir:BAAANQADCgYIBgAAAA==.',
Ri='Riru:BAAANQAECgQIBwAAAA==.',
Ro='Rockstéady:BAAANQAECggIDAAAAA==.Roness:BAAANQABCgUIBQAAAA==.Roopall:BAACNQAFFH8JAAIXAAUKJBgKDACOAQAXAAUKJBgKDACOAQA1AAQKfzsAAhcACgoTIRMPAFIDABcACgoTIRMPAFIDAAAA.Roxas:BAAANQADCggICQAAAA==.',
Ry='Rynzu:BAAANQAECgMIBAAAAA==.Ryzen:BAAANQAECgcIDQAAAA==.',
Sa='Sabelwin:BAAANQADCgEIAQAAAA==.Sanasrindis:BAAANQADCgQIAgAAAA==.Saninar:BAABNQAECn8yAAICAAoK2QzYLgADAQACAAoK2QzYLgADAQAAAA==.Sanshift:BAAANQAECgQIBAAAAA==.Satansimp:BAAANQAECgMIAgAAAA==.',
Sc='Schezmu:BAAANQAECgUICAAAAA==.Scrabler:BAAANQADCggIDgAAAA==.',
Se='Sean:BAAANQADCgUICgAAAA==.Senorfiesta:BAABNQAECn8/AAImAAoK1hfqEwBTAgAmAAoK1hfqEwBTAgAAAA==.Serazarke:BAAANQAECgEIAgAAAA==.Setazen:BAAANQAECgQIBgAAAA==.',
Sh='Shadowjoker:BAAANQAECgEIAQAAAA==.Shaee:BAABNQAECn8dAAMGAAYKyxdZQQC1AQAGAAYKyxdZQQC1AQAUAAEKAADRdQAjAAAAAA==.Shamama:BAAANQADCgUIBQAAAA==.Shamans:BAAANQAECgUIDAAAAA==.Shambalaya:BAAANQAECggIEwAAAA==.Shaokhan:BAABNQAECn8jAAMOAAgKUwhGqQAoAQAOAAgKUwhGqQAoAQAdAAIKxwkGOAAsAAAAAA==.Shasta:BAACNQAFFH8XAAIkAAcKlyGNAADeAQAkAAcKlyGNAADeAQA1AAQKfzEAAiQACgo4JqwBAMUDACQACgo4JqwBAMUDAAAA.Shihthead:BAAANQADCgUIBQAAAA==.Shisuiuchiha:BAAANQADCgIIAgAAAA==.Shmorg:BAAANQADCgEIAQAAAA==.Shootumup:BAABNQAECn9GAAMnAAoKCyQyAQAXAwAnAAoKCyQyAQAXAwAEAAEKZRcjSwFJAAAAAA==.Shyx:BAABNQAECn9FAAQgAAoKDCTVCQCbAwAgAAoKDCTVCQCbAwAfAAcKCw1nNQB4AQAhAAEKjRmbJQBBAAAAAA==.',
Si='Siilas:BAAANQAECgYICAAAAA==.Simplèjack:BAABNQAECn8fAAIRAAcKswnF/wCOAQARAAcKswnF/wCOAQAAAA==.Sinamon:BAABNQAECn8YAAIPAAYKFxtC1ABzAQAPAAYKFxtC1ABzAQAAAA==.Sinani:BAAANQADCgUJBQAAAA==.Sinnamon:BAAANQABCgQJBAABNQAECgYIGAAPABcbAA==.',
Sj='Sjdh:BAAANQADCgYIBgABNQAECggIDQATAAAAAA==.Sjrogue:BAAANQAECggIDQAAAA==.',
Sk='Skar:BAAANQADCgUIBgAAAA==.Skram:BAAANQAECgUICAABNQAECgoKMwAPAJwNAA==.Skronker:BAAANQADCggIDQAAAA==.',
Sl='Slammydooker:BAABNQAECn8xAAMSAAoKRxijJwBkAgASAAoKRxijJwBkAgAYAAUKfw0RXwA5AQAAAA==.',
Sm='Smallkat:BAAANQAECgUIBQAAAA==.Smirksfotm:BAAANQAECgUICAABNQAECggIEAATAAAAAA==.Smoketail:BAAANQAECgUIBwAAAA==.',
Sn='Snail:BAAANQAECgYIBgAAAA==.Sneakmanman:BAAANQADCgYJCQAAAA==.',
So='Somberdh:BAAANQADCggICwAAAA==.Sorni:BAABNQAECn9IAAMPAAoK3whaqAB+AQAPAAoK3whaqAB+AQACAAIK7wK5awA7AAAAAA==.Soulglo:BAAANQAECgQIBAAAAA==.',
Sp='Spellslanger:BAAANQADCgQIBAAAAA==.Spikeprotein:BAAANQABCggICQAAAA==.Sprayandpray:BAABNQAECn8YAAIRAAoKSRxDRABAAgARAAoKSRxDRABAAgAAAA==.Spritey:BAAANQABCgIIAgAAAA==.',
Sq='Squidnips:BAAANQAECgEIAQAAAA==.',
St='Stareless:BAAANQADCgYIBgAAAA==.Statik:BAAANQAECgMIAwAAAA==.Stinkified:BAAANQAECgEIAQAAAA==.Stoneychri:BAAANQAECgMIAwAAAA==.Stormhealerz:BAAANQAECgQIBAAAAA==.Stormshadow:BAAANQAECgQIBgAAAA==.',
Su='Summondemons:BAAANQAECgIIBQAAAA==.Sumnèr:BAAANQADCgMIAwAAAA==.Sunpali:BAAANQAECgcICwAAAA==.Susanno:BAAANQADCgUJCwAAAA==.',
Sy='Sylauda:BAAANQADCgYICgAAAA==.Sylvians:BAAANQAECgEIAQAAAA==.',
Ta='Tacutacudark:BAAANQAECgUIDwAAAA==.Taintedbeef:BAAANQADCgEIAQABNQAECgYIDQATAAAAAA==.Talonflame:BAABNQAECn8qAAQNAAgKHxWVLwDQAQANAAcKNhaVLwDQAQAEAAMKEReXFgHWAAAnAAIKiwqzDwCHAAAAAA==.Talonted:BAAANQAECgIIAgAAAA==.Tandallei:BAAANQAECgQIBAAAAA==.Tansu:BAAANQAECgUIBQAAAA==.Tarishi:BAAANQAECgYIBwAAAA==.Tarishii:BAABNQAECn8XAAMGAAkK1xkzGQBLAgAGAAkKixczGQBLAgAVAAUKnRdCFAAKAQAAAA==.Tateraid:BAAANQABCgYICQAAAA==.Taterpuff:BAAANQABCgUIBQAAAA==.Taupo:BAAANQAECgEIAgAAAA==.Taxidermy:BAAANQADCgYIDAAAAA==.',
Te='Telarinda:BAABNQAECn8WAAMFAAoK5QdPtwBfAQAFAAkKgwdPtwBfAQAiAAIKkAqnaQBOAAAAAA==.',
Th='Thametal:BAAANQAECgIIAgAAAA==.Thicclich:BAABNQAECn8nAAIWAAoK1Q0wOgC2AQAWAAoK1Q0wOgC2AQAAAA==.Thicktotem:BAAANQAECgEIAQAAAA==.Thickumz:BAAANQADCgQIBAAAAA==.Thinmint:BAAANQADCgcICQAAAA==.Thisismeta:BAAANQAECgYICgAAAA==.Thorynwar:BAACNQAFFH8aAAIOAAgKCR7GCQAXAgAOAAgKCR7GCQAXAgA1AAQKfzkAAg4ACgr5JfcKADkDAA4ACgr5JfcKADkDAAE1AAUUBQgNACYAIhQA.Thorýn:BAACNQAFFH8NAAMmAAUKIhR7DgAkAQAmAAQKIhR7DgAkAQAbAAEKAABpKABXAAA1AAQKfyUAAyYACQpzJooQADMDACYACQpzJooQADMDABsABwriGR9HAN0BAAAA.Thyrnoch:BAAANQAECgEIAQAAAA==.Thórin:BAABNQAECn8XAAICAAkK4RNSKACbAQACAAkK4RNSKACbAQAAAA==.',
Ti='Tierax:BAABNQAECn89AAMSAAoK2h85CQDiAgASAAkKpiA5CQDiAgAYAAMKNxgGPACcAAAAAA==.Tipsy:BAABNQAECn8yAAIIAAoKFRI1ZQDdAQAIAAoKFRI1ZQDdAQAAAA==.',
To='Tojì:BAAANQAECggIEAAAAA==.Tonathul:BAAANQADCggIEAAAAA==.Torrk:BAAANQAECgQIBAAAAA==.Torultrear:BAAANQAECgIIAgAAAA==.Tot:BAABNQAECn8qAAIIAAoKEgwIfwCPAQAIAAoKEgwIfwCPAQAAAA==.',
Tr='Tralleth:BAABNQAECn8uAAMKAAkK4xYLDACZAQAKAAgK1hQLDACZAQAJAAgK8A6yIQD6AAAAAA==.Trallock:BAAANQAECgEIAQAAAA==.Traumatized:BAAANQADCgUIBwAAAA==.Trecco:BAAANQAECggICAAAAA==.Truska:BAAANQABCgEIAQAAAA==.',
Ts='Tsoi:BAAANQAECggICAAAAA==.',
Tu='Tuskyrex:BAAANQAECgEIAQAAAA==.',
Tw='Twinklord:BAAANQAECggIEwAAAA==.Twostroke:BAABNQAECn8yAAIEAAoKriXGBgCnAwAEAAoKriXGBgCnAwAAAA==.Twotoe:BAAANQAECgQIBAAAAA==.Twretwtwrewr:BAAANQADCgIIAgAAAA==.Twunkie:BAAANQADCgcIBwAAAA==.',
Ty='Tylopally:BAAANQAFFAIIAgAAAA==.Tyloremixdd:BAAANQAECgQIBAAAAA==.Tylototem:BAAANQAECgQIBAAAAA==.',
['Tö']='Tötem:BAAANQADCgMIAwABNQAFFAcIDQAWAOkjAA==.',
Uj='Ujcpet:BAAANQADCgYIBgAAAA==.',
Un='Uncookedham:BAAANQADCgYIEAAAAA==.Underhorn:BAAANQADCggIDgAAAA==.',
Va='Vaas:BAAANQADCggICAABNQAECgoKLQACAMshAA==.Vaeelrundor:BAABNQAECn8yAAIEAAkKRAkwhQCvAQAEAAkKRAkwhQCvAQAAAA==.Valyr:BAAANQADCgQIBAAAAA==.Vampslayer:BAAANQADCgYIBgAAAA==.Vanillaface:BAAANQAECggIDwAAAA==.Vañillaface:BAAANQABCgQIBgAAAA==.',
Ve='Vedebone:BAAANQAECgYIDAAAAA==.Vedexd:BAABNQAECn8pAAIEAAcKrRDfoADEAQAEAAcKrRDfoADEAQAAAA==.Velarael:BAABNQAECn8hAAMjAAgKAQ+/DQB8AQAjAAcK0RC/DQB8AQAFAAIKOgVg/gBaAAAAAA==.Veletharia:BAAANQADCgQICAAAAA==.Velexi:BAAANQADCgQIBwAAAA==.Velpura:BAAANQADCgYIBgABNQAECggIIQAjAAEPAA==.',
Vh='Vheckxus:BAABNQAECn8VAAIBAAUK7guUmgDSAAABAAUK7guUmgDSAAAAAA==.',
Vi='Vivi:BAAANQAECgMIBAAAAA==.',
Vl='Vlidya:BAAANQADCgEIAQAAAA==.',
Vo='Voidberg:BAAANQAECgYICAAAAA==.',
Vs='Vs:BAAANQAECggIDgAAAA==.',
Wa='Wachonaso:BAACNQAFFH8JAAIFAAQKgQtjGgAjAQAFAAQKgQtjGgAjAQA1AAQKfykAAwUACgooHV0/AJQCAAUACgq0HF0/AJQCACIAAwokHcwwAAUBAAAA.Wastedsage:BAAANQAECgUICAAAAA==.Waterlou:BAAANQAECgIIAgAAAA==.',
We='Weavefang:BAAANQADCgUICAAAAA==.',
Wh='Whatuphuz:BAAANQADCggIEAAAAA==.Wheresmyjaw:BAACNQAFFH8MAAMFAAQKsRm5IACuAAAFAAMKHB+5IACuAAAiAAEK3A5vEQBLAAA1AAQKf0cAAwUACgocJC4XAMMCAAUACQpmJC4XAMMCACIAAwpeGF89AMwAAAAA.',
Wi='Wildthree:BAABNQAECn8hAAIMAAgKFwxoEAAfAQAMAAgKFwxoEAAfAQAAAA==.Wilkieswar:BAAANQADCggIGAABNQAECgoKLgARADgfAA==.Willenda:BAAANQAECgEIAgAAAA==.Winterfall:BAAANQAECgQIBAAAAA==.',
Wu='Wuinn:BAACNQAFFH8QAAIJAAgKrQevCQCVAQAJAAgKrQevCQCVAQA1AAQKfzYABAkACgrqF2QPABUCAAkACgrqF2QPABUCAAoABwo+EAELAFEBAAsAAQpUDVslADgAAAAA.',
Xa='Xakutioner:BAABNQAECn9CAAIQAAoKWiCbFAAiAwAQAAoKWiCbFAAiAwAAAA==.Xaldiir:BAABNQAECn8+AAIGAAoKYSLzCgDtAgAGAAoKYSLzCgDtAgAAAA==.',
Xe='Xenvoroo:BAAANQADCgIIAgAAAA==.Xeralia:BAAANQAECgEIAQAAAA==.Xerexia:BAABNQAECn9CAAIOAAkKQA8RowDFAQAOAAkKQA8RowDFAQAAAA==.Xeràth:BAAANQAECggIDgAAAA==.',
Xs='Xsjàdo:BAAANQADCgYIBwAAAA==.',
Xw='Xwoo:BAAANQAECgQIBQAAAA==.',
Xz='Xzarlatan:BAAANQADCgIIAgAAAA==.Xzarlatanfi:BAAANQADCgUIBQAAAA==.',
Ya='Yahro:BAAANQAECgcIEQAAAA==.',
Ye='Yellowranger:BAABNQAECn9OAAIXAAoK9iFRCQCLAwAXAAoK9iFRCQCLAwAAAA==.',
Yj='Yjn:BAABNQAECn8vAAIMAAoKpRdxBQBJAgAMAAoKpRdxBQBJAgABNQAECgoKOwAEAOobAA==.',
Yo='Yongyong:BAABNQAECn8dAAMFAAgKAhyvYQCxAQAFAAgKAhyvYQCxAQAiAAEKAAA8bgBCAAAAAA==.Yotoymuerto:BAAANQAECgEIAQAAAA==.',
Yu='Yunara:BAAANQAECgYIBgAAAA==.Yustayoke:BAABNQAECn8mAAIRAAgKihQarwAkAgARAAgKihQarwAkAgAAAA==.',
Za='Zalvianna:BAAANQAECgYICAAAAA==.Zarathoz:BAAANQABCgYJBgAAAA==.Zarshx:BAAANQADCgQICAABNQAECgYIBgATAAAAAA==.',
Ze='Zennithz:BAAANQAECggIEAAAAA==.Zeonz:BAAANQAECgEIAQAAAA==.',
Zh='Zhoya:BAAANQAECggIEAAAAA==.',
Zi='Zilong:BAAANQAECgIIBQABNQAFFAgIDgAOABYRAA==.Zilongmage:BAAANQAECggICAABNQAFFAgIDgAOABYRAA==.Zilongwar:BAACNQAFFH8OAAIOAAgKFhGwCwD3AQAOAAgKFhGwCwD3AQA1AAQKfyIAAg4ACgp0Iq8sAAoDAA4ACgp0Iq8sAAoDAAAA.',
Zo='Zombor:BAAANQADCgIIAgAAAA==.Zonecw:BAABNQAECn8wAAMcAAoKrxtFBwCBAgAcAAkKrxtFBwCBAgAOAAkKbQu7gACGAQAAAA==.Zonedk:BAAANQAECgQIBgABNQAECgoKMAAcAK8bAA==.',
['Ør']='Ørsted:BAAANQADCgIIAgABNQAECgEIAgATAAAAAA==.',
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
