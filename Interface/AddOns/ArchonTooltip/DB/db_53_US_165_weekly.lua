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

local lookup = {'Shaman-Elemental','DeathKnight-Blood','Hunter-BeastMastery','Warlock-Demonology','DemonHunter-Havoc','Shaman-Enhancement','Shaman-Restoration','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster','Hunter-Marksmanship','Druid-Restoration','Warrior-Arms','Paladin-Retribution','Druid-Balance','Mage-Arcane','Rogue-Subtlety','Unknown-Unknown','DemonHunter-Devourer','DemonHunter-Vengeance','DeathKnight-Frost','Paladin-Holy','Paladin-Protection','Rogue-Assassination','Rogue-Outlaw','Mage-Frost','Warrior-Protection','Warrior-Fury','Monk-Windwalker','Priest-Shadow','Priest-Holy','Priest-Discipline','Warlock-Destruction','Warlock-Affliction','Druid-Guardian','Druid-Feral','DeathKnight-Unholy','Monk-Mistweaver','Mage-Fire','Hunter-Survival',}
local provider = {region='US',realm='Nazjatar',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aanon:BAAANQAECgEIAQAAAA==.',
Ab='Aberoth:BAAANQADCggIDAAAAA==.',
Ac='Accoli:BAAANQAECgUIBQAAAA==.Acslater:BAAANQADCgQIBAAAAA==.',
Ag='Agoobagoo:BAACNQAFFH8KAAIBAAMK+CBZFQAkAQABAAMK+CBZFQAkAQA1AAQKfxUAAgEACQpuHvEYADMDAAEACQpuHvEYADMDAAE1AAUUBggXAAIAZh8A.',
Al='Aliasx:BAAANQAECgQIBAAAAA==.Alissaria:BAAANQAECgEIAQAAAA==.Allarus:BAAANQADCgcICQAAAA==.Allwrong:BAAANQADCgQIBAAAAA==.Alotofsin:BAAANQAECgEIAQAAAA==.Alphadog:BAEBNQAECn9IAAIDAAoKBSGGGADBAgADAAoKBSGGGADBAgAAAA==.Alwaysunny:BAAANQADCgYIDAAAAA==.',
Am='Amahlfarouk:BAABNQAECn8pAAIEAAgK3BMFcwBIAQAEAAgK3BMFcwBIAQAAAA==.Aminatou:BAABNQAECn81AAIFAAoKnhMlIADPAQAFAAoKnhMlIADPAQAAAA==.',
Ar='Ariaddne:BAABNQAECn8gAAQGAAkKthfKFQAMAgAGAAkK/xbKFQAMAgABAAYKbhQuswAsAQAHAAEKwRi6FAFAAAAAAA==.Arrowblack:BAAANQADCgEIAgAAAA==.Artemîs:BAAANQAECgMIAwAAAA==.',
As='Ashaelra:BAAANQAECgUIBQAAAA==.Asolitha:BAAANQADCgUIBQAAAA==.',
Au='Augonly:BAABNQAFFH8JAAIIAAMKABPJEADdAAAIAAMKABPJEADdAAAAAA==.Augy:BAABNQAECn8mAAMJAAoKUxkgBwA+AgAJAAcK0hogBwA+AgAKAAkKrBZsFQD1AQAAAA==.',
Ay='Aystria:BAAANQADCgMIAgAAAA==.',
Ba='Bakuretsu:BAABNQAECn8fAAILAAkKdiJsAQAdAwALAAkKdiJsAQAdAwABNQAECgoKNAALAAscAA==.Barhead:BAAANQADCggIDgAAAA==.Barlow:BAABNQAECn8gAAIMAAgKiwLQMAC6AAAMAAgKiwLQMAC6AAAAAA==.',
Bb='Bbldrizzy:BAACNQAFFH8NAAIBAAcKsxooCQDcAQABAAcKsxooCQDcAQA1AAQKfzAAAwEACgrtJLcRAGEDAAEACgrtJLcRAGEDAAcAAQqNHgfMAFYAAAAA.',
Be='Beastlieduke:BAAANQADCgYIDAABNQAECggIHQANAGUdAA==.Beastlièduke:BAAANQADCgIIAgABNQAECggIHQANAGUdAA==.Belephon:BAAANQAECgQIBwAAAA==.Belinda:BAAANQAECgYIBwAAAA==.',
Bi='Bighunt:BAAANQAECgMIAwAAAA==.Bijju:BAAANQAECggIEgAAAA==.Binggus:BAABNQAECn8XAAIOAAgKyh1+VQCKAgAOAAgKyh1+VQCKAgAAAA==.',
Bl='Blabbybootze:BAABNQAECn8hAAIPAAcKFwMrKgHaAAAPAAcKFwMrKgHaAAAAAA==.Bladelight:BAAANQAECgIIAQAAAA==.Blighte:BAAANQAECgQIBAABNQAFFAMIBQAQALUVAA==.Blightfangs:BAABNQAECn8xAAIRAAkKwhYhVQDrAQARAAkKwhYhVQDrAQAAAA==.Bloodieelish:BAAANQAECgIIAQABNQAECggIGQASAJEOAA==.Bluzey:BAAANQAECgcIBwAAAA==.',
Bo='Bodakye:BAABNQAECn8qAAIDAAoKKRhIOgAwAgADAAoKKRhIOgAwAgAAAA==.Boneplague:BAAANQADCgQIBAAAAA==.Boow:BAAANQAECgUIBQAAAA==.',
Br='Bracalina:BAAANQAECgYIBwAAAA==.Brannix:BAAANQADCgUIBQAAAA==.Broggy:BAAANQADCgEIAQABNQAECgcICAATAAAAAA==.Brorgy:BAABNQAECn8bAAQUAAYKqQiFRQAmAQAUAAYKqQiFRQAmAQAVAAEKAADaOQAZAAAFAAEKSQHhhAAMAAABNQAECggIGQASAJEOAA==.',
Bu='Bubbapal:BAAANQADCgUIBwAAAA==.Bushntush:BAAANQADCggICQAAAA==.Buzzbuzz:BAAANQAECgMIBAAAAA==.',
By='Bywar:BAAANQADCgcICwAAAA==.',
['Bé']='Bébop:BAAANQAECggIDwAAAA==.',
Ca='Caeruleus:BAAANQADCgQJBAAAAA==.Captyn:BAAANQABCgQIAwABNQAECgoKKgADACkYAA==.Catbum:BAAANQADCgIIAwAAAA==.Caylea:BAAANQADCggICAAAAA==.',
Ch='Chaosraven:BAABNQAECn88AAIWAAoKtA+IMACqAQAWAAoKtA+IMACqAQAAAA==.Chapelgnome:BAAANQAECgQIBAABNQAECggIGQASAJEOAA==.Charlyne:BAAANQABCgMIAwAAAA==.Chewthymight:BAABNQAECn83AAMPAAoK3RRcagC+AQAPAAkKCBZcagC+AQAXAAcKjwqMygDmAAAAAA==.Chickenslop:BAAANQAECgUIBgAAAA==.Chiffón:BAAANQAECgMIAwAAAA==.Chiptime:BAAANQAECgUIDAAAAA==.Chloes:BAAANQAECgIIAgAAAA==.Chri:BAAANQAECgUIBwAAAA==.Chrri:BAAANQAECgIIAwAAAA==.Chungotron:BAACNQAFFH8IAAMPAAYK9g6dDgBjAQAPAAUKEgudDgBjAQAYAAEKhh67CgBaAAA1AAQKfx8AAg8ACgp1I78NACQDAA8ACgp1I78NACQDAAAA.Chzburger:BAAANQABCgIIBAAAAA==.',
Cl='Cladon:BAAANQAECggICAAAAA==.Clairity:BAAANQADCgcIBwAAAA==.',
Co='Cocoon:BAAANQAECgQIBAABNQAFFAQIEAARAAQXAA==.Colay:BAAANQADCgIIAgAAAA==.Conda:BAAANQAECggIEgAAAA==.Cormogh:BAAANQAECgYIDwAAAA==.Cowhealer:BAACNQAFFH8FAAIQAAMKtRUdHQCqAAAQAAMKtRUdHQCqAAA1AAQKfzAAAxAACgpQIWYfANACABAACgpQIWYfANACAA0AAwrEDEtcAJYAAAAA.',
Cr='Craeftig:BAABNQAECn8hAAMZAAoKGxgQDQDWAQAZAAoKGxgQDQDWAQAaAAEKowHIHwAWAAAAAA==.Craeftigdk:BAABNQAECn8dAAICAAcKAQ7nWgCHAQACAAcKAQ7nWgCHAQABNQAECgoKIQAZABsYAA==.Craeftigtwo:BAAANQADCggJDQABNQAECgoKIQAZABsYAA==.Craeftigwl:BAAANQAECgIIAgABNQAECgoKIQAZABsYAA==.Crepitus:BAABNQAECn8WAAMSAAYKEgzZLQBTAQASAAYKEgzZLQBTAQAZAAIKWQXrlQBdAAAAAA==.Crusabull:BAAANQADCgcIBwAAAA==.Cræftig:BAABNQAECn8cAAMbAAkKvxnGBwBvAgAbAAgKzx3GBwBvAgARAAMKkwmJmQGTAAABNQAECgoKIQAZABsYAA==.',
Cu='Cuddlseraph:BAAANQAECgUIEgAAAA==.Cutestcc:BAAANQAECggIDgAAAA==.',
Cy='Cynnithice:BAAANQADCgIIAgABNQAECgYIBwATAAAAAA==.',
Da='Daamdam:BAABNQAECn8ZAAIcAAgKjgPSLwC3AAAcAAgKjgPSLwC3AAAAAA==.Dadune:BAAANQABCgYICAABNQAECgYICQATAAAAAA==.Dafirenze:BAAANQADCggIDwAAAA==.Daftxshade:BAAANQAECgYICQAAAA==.Dariian:BAABNQAECn8WAAIdAAgKJALPJABRAAAdAAgKJALPJABRAAAAAA==.Darkbeef:BAABNQAECn8VAAIEAAYKDQOi9wDcAAAEAAYKDQOi9wDcAAAAAA==.Darkjusticeh:BAAANQAECgUIBwAAAA==.Darlang:BAAANQAECgUICgAAAA==.Darthbjóurn:BAAANQAECgUIBQAAAA==.Darthownage:BAAANQADCgUIBQAAAA==.Darthsyde:BAABNQAECn8mAAICAAkKGRFNPAAmAQACAAkKGRFNPAAmAQABNQAECgoKKgADACkYAA==.Dayanna:BAAANQADCggIDQAAAA==.',
De='Deadergriff:BAAANQAECgUIEwAAAA==.Deadicated:BAABNQAECn8ZAAIeAAgKawg+OwA6AQAeAAgKawg+OwA6AQAAAA==.Deadinsíde:BAAANQAECggICAABNQAECggIEAATAAAAAA==.Deathlyaura:BAAANQADCggICAABNQAECgUICAATAAAAAA==.Deathmark:BAAANQAECgUICAAAAA==.Deeznutzs:BAABNQAECn8aAAIRAAcKoAhMwwD3AAARAAcKoAhMwwD3AAAAAA==.Defendaya:BAAANQAECggICAAAAA==.Delan:BAAANQAECgYIBwAAAA==.Demolishonn:BAAANQAECgUIEQAAAA==.Desunaito:BAACNQAFFH8QAAIWAAcKfRX7AwDkAQAWAAcKfRX7AwDkAQA1AAQKf0QAAhYACgocJOEIAAcDABYACgocJOEIAAcDAAAA.Dexter:BAAANQAECgQIBQAAAA==.',
Dh='Dhzilong:BAABNQAECn8UAAMUAAgKPxw3JwALAgAUAAgKmRs3JwALAgAFAAQK3g/LagBOAAABNQAFFAcIDQAOADkTAA==.',
Di='Diddlefiddle:BAAANQADCgIIAgAAAA==.Dimeo:BAAANQADCgQIAQAAAA==.Dioji:BAAANQAECggIBgAAAA==.',
Dk='Dkzilong:BAAANQAECgIIBQABNQAFFAcIDQAOADkTAA==.',
Dm='Dmeo:BAAANQADCgMIAwAAAA==.',
Do='Docadoodle:BAAANQADCgcIBwABNQAFFAMIBQAUAJAJAA==.Docarcanis:BAAANQAECgYIBgABNQAFFAMIBQAUAJAJAA==.Docwyle:BAACNQAFFH8FAAIUAAMKkAlbFQBFAAAUAAMKkAlbFQBFAAA1AAQKfzIAAhQACgq9GIUYAJgCABQACgq9GIUYAJgCAAAA.Doozey:BAAANQABCgcJBwAAAA==.',
Dr='Dracmary:BAAANQADCgUIBQAAAA==.Dracnogard:BAAANQAECgUIDgAAAA==.Dracowulf:BAABNQAECn8lAAIDAAcKtgahrgAQAQADAAcKtgahrgAQAQAAAA==.Dracuia:BAAANQAECgMIAwAAAA==.Dragonbro:BAAANQAECgMIAwAAAA==.Dragonx:BAABNQAECn8vAAIDAAkKJgw7ZwCtAQADAAkKJgw7ZwCtAQAAAA==.Drakowolf:BAABNQAECn8dAAIKAAoKLAbTEgDZAAAKAAoKLAbTEgDZAAAAAA==.Drama:BAAANQAECgEIAQAAAA==.Dreadful:BAABNQAECn9WAAIXAAoKYR8DCQBxAwAXAAoKYR8DCQBxAwAAAA==.Dreamchi:BAAANQAECgMIAgAAAA==.Dreorge:BAABNQAECn8XAAIIAAkKNBWxEwByAgAIAAkKNBWxEwByAgAAAA==.Drewceratops:BAABNQAECn8aAAIPAAkKVA+WnwDiAQAPAAkKVA+WnwDiAQAAAA==.Drewidd:BAAANQAECgUIBwABNQAECggIGQASAJEOAA==.Drimchi:BAAANQAECgEIAQAAAA==.Drimveil:BAABNQAECn8ZAAIFAAkKPhgLLgA0AgAFAAkKPhgLLgA0AgAAAA==.Drogô:BAAANQAECgQICAAAAA==.Dromgar:BAAANQAECggIEgABNQAECgoKIgAGANcmAA==.Dromkyr:BAABNQAECn80AAMIAAoKnQ+cGwAPAgAIAAoKnQ+cGwAPAgAKAAEKNwtJPQAyAAAAAA==.Drossiechan:BAACNQAFFH8WAAIeAAYKPBLlBAArAQAeAAYKPBLlBAArAQA1AAQKfyYAAh4ACgpmG7wZAHQCAB4ACgpmG7wZAHQCAAAA.',
Du='Duellipa:BAABNQAECn8ZAAMSAAgKkQ4YZgAlAQASAAcK7g8YZgAlAQAZAAQKwwajewDEAAAAAA==.',
Dy='Dysian:BAAANQADCgQIBQAAAA==.Dywanw:BAAANQABCgYIBgAAAA==.',
Ed='Edward:BAAANQAECggJBwAAAA==.',
Ef='Effloria:BAABNQAECn89AAMNAAoKbSRkAwCSAwANAAoKbSRkAwCSAwAQAAEKAAAfkAAAAAAAAA==.',
Ek='Ekim:BAAANQADCgQIAwAAAA==.Eklyps:BAAANQADCgYIBgAAAA==.',
El='Elauvia:BAAANQAECgUICAAAAA==.Elegia:BAAANQAECggIDgAAAA==.',
Em='Emleah:BAABNQAECn8WAAIGAAYK0QLFJQCYAAAGAAYK0QLFJQCYAAAAAA==.Emmaina:BAAANQAECgUICAAAAA==.',
En='Enash:BAAANQADCgQIBAAAAA==.Encoredh:BAAANQAECgQIBAABNQAECggIIQAfAEcZAA==.Encoredk:BAAANQADCgIIAgAAAA==.Encoree:BAAANQADCgcIBwABNQAECggIIQAfAEcZAA==.Encoremts:BAAANQAECgEIAQABNQAECggIIQAfAEcZAA==.Encorep:BAABNQAECn8hAAQfAAgKRxnhJQAAAgAfAAcKBhfhJQAAAgAgAAQKTgkVzQBXAAAhAAIK2APsEgBGAAAAAA==.Enris:BAAANQADCgUICAAAAA==.',
Es='Esael:BAAANQAECggIEAAAAA==.',
Ev='Eviscerated:BAAANQAECgQIBQAAAA==.',
Fa='Fail:BAAANQADCgYICwAAAA==.Falker:BAAANQAECgIIAgAAAA==.Fallen:BAAANQAECggICgAAAA==.Fallingvoid:BAAANQAFFAQIAgAAAA==.Fancyfeet:BAAANQADCgIIAwABNQAECgYIBgATAAAAAA==.Fatchungus:BAAANQAECgQIBQABNQAECgYIBgATAAAAAA==.Fateesia:BAAANQAECgEIAQAAAA==.',
Fe='Feathersong:BAAANQADCggICwAAAA==.Fendru:BAABNQAECn8bAAIDAAkKggbwggBrAQADAAkKggbwggBrAQAAAA==.Fextardo:BAAANQAECgMIAwAAAA==.',
Fi='Finaliter:BAACNQAFFH8HAAIPAAQKhw7nEwDGAAAPAAQKhw7nEwDGAAA1AAQKf0EAAg8ACgpoIOkdAMsCAA8ACgpoIOkdAMsCAAAA.',
Fl='Flamingdrago:BAAANQAECgQIBQAAAA==.Fletchiana:BAAANQAECgEIAQAAAA==.Flexatronic:BAAANQAECgcIDQABNQAECgcIHwARALMJAA==.Flirtyflurry:BAAANQAECgUIBwAAAA==.Flurrybloom:BAAANQADCgYIBgAAAA==.',
Fo='Forsetie:BAAANQADCgMIAwAAAA==.Forsight:BAAANQADCgYIBgABNQAFFAEIAQATAAAAAA==.Fox:BAACNQAFFH8OAAMaAAUKvBqNAQAxAQAaAAQK8hKNAQAxAQAZAAMKvBrhDgD8AAA1AAQKfzEAAxoACgo7IIoCAC8DABoACgpoHooCAC8DABkABwoaHnclAF8CAAAA.',
Fr='Freezerbúrnt:BAAANQAECggIEAAAAA==.Fremder:BAAANQAECgUJBgAAAA==.Fresher:BAAANQAECgIIAgABNQAFFAcIDQABALMaAA==.Froggy:BAAANQAECggIEAAAAA==.Frogleap:BAAANQADCgUIBQABNQAECggIEAATAAAAAA==.Frogred:BAAANQADCgQIBAABNQAECggIEAATAAAAAA==.Frogtoad:BAAANQAECgUIDgABNQAECggIEAATAAAAAA==.',
Fu='Funeral:BAACNQAFFH8iAAQiAAgKUBq/AAB6AQAiAAQKvRy/AAB6AQAEAAQKfBtsEgBqAQAjAAMKjQtUAwDCAAA1AAQKfzYABCIACgp5JXABAHoDACIACQqEJHABAHoDAAQACQozJGYeAHcCACMAAgoEJgIcAKAAAAAA.Furiousmoon:BAAANQADCggICAAAAA==.Futuresailor:BAAANQAECgYICQAAAA==.',
Fy='Fyjhrt:BAABNQAECn81AAIaAAkKCSNoAAAZAwAaAAkKCSNoAAAZAwAAAA==.',
Ga='Galladin:BAAANQAECgYICAABNQAECgIIAQATAAAAAA==.Gallory:BAAANQAECggIDgAAAA==.',
Gd='Gdk:BAAANQAECgMIBAABNQAECgoKQwAGAA4bAA==.Gdkdrake:BAAANQADCgUIBQABNQAECgoKQwAGAA4bAA==.Gdkhunter:BAAANQADCggICAABNQAECgoKQwAGAA4bAA==.Gdkmage:BAABNQAECn8hAAIRAAoK0w/XTgD8AQARAAoK0w/XTgD8AQABNQAECgoKQwAGAA4bAA==.Gdkman:BAABNQAECn9DAAQGAAoKDhvpCQBPAgAGAAoKTBnpCQBPAgABAAgKPhuNTgA9AgAHAAIKlwjkCQFUAAAAAA==.Gdknotlock:BAAANQADCgQIBgABNQAECgoKQwAGAA4bAA==.',
Ge='Geoprince:BAAANQADCgcIEAAAAA==.Gerbon:BAAANQADCgMICAAAAA==.',
Gh='Ghaldrin:BAAANQABCggIEAAAAA==.Ghoulfriend:BAAANQADCgUICgAAAA==.',
Gi='Gigitty:BAAANQADCgYIBgAAAA==.Gimmedatneck:BAABNQAECn8hAAMZAAoKhB8lDAAmAwAZAAoKHh8lDAAmAwASAAUKPgrKQQCrAAABNQAFFAcIDQABALMaAA==.Githrogathan:BAAANQAECgUIEwAAAA==.',
Go='Gokudin:BAAANQADCgUIBAAAAA==.Goldenrager:BAAANQADCgQIBAAAAA==.Gooseandmav:BAAANQADCgEIAQAAAA==.',
Gr='Grabetta:BAAANQADCgEIAQAAAA==.Graegor:BAAANQADCgUIBQAAAA==.Gragasfat:BAAANQAECgIIAgAAAA==.Groundnpound:BAAANQADCgUJBQAAAA==.',
Gy='Gyanall:BAAANQADCgMIAwAAAA==.',
['Gâ']='Gârrosh:BAAANQADCgYIBgABNQAECgoKSwADAI8PAA==.',
['Gö']='Gödhand:BAAANQAECgUICwAAAA==.',
Ha='Haeha:BAAANQADCgQIBAAAAA==.Haraldsson:BAAANQADCggICAAAAA==.Hargrumn:BAAANQABCgMIAgAAAA==.Harrypooc:BAAANQADCgQJBAAAAA==.Hasaro:BAACNQAFFH8JAAIkAAQKmwY1BQCTAAAkAAQKmwY1BQCTAAA1AAQKfz0AAiQACgpNErQTAMIBACQACgpNErQTAMIBAAAA.Hatcho:BAAANQADCgUICAAAAA==.Havokvacano:BAABNQAECn8iAAIPAAcK6AlE1QDxAAAPAAcK6AlE1QDxAAAAAA==.Havøckblaze:BAAANQADCgIIAgABNQADCgUIBAATAAAAAA==.',
He='Healmachine:BAAANQAECgMICwAAAA==.Healzilla:BAAANQADCgYIBgAAAA==.Hellbrringer:BAAANQAECgEIAQAAAA==.Helzer:BAAANQADCggIDwABNQAECgoKRQAGAHkeAA==.',
Ho='Holybaphomet:BAAANQADCgUICQAAAA==.Holyfarts:BAABNQAECn9CAAQhAAoKryJKAQBLAwAhAAoKgiBKAQBLAwAgAAgKNB9EMQCjAgAfAAoKQxgdEQAQAgAAAA==.Honeypaw:BAAANQADCgUIBQAAAA==.Hornedraven:BAAANQADCgEIAQAAAA==.',
Hu='Humanform:BAAANQADCgUIBQAAAA==.Hunbroll:BAAANQADCgYIBgABNQAFFAcIIQAbABYZAA==.Hungshaman:BAAANQABCgIIAgAAAA==.Hunterkiller:BAAANQADCggIGgAAAA==.',
Hx='Hx:BAAANQAECgQIBAAAAA==.',
Hy='Hypnoticpal:BAABNQAECn8UAAIPAAgK+QFqOAFmAAAPAAgK+QFqOAFmAAAAAA==.Hypnoticwar:BAAANQAECgIIAQAAAA==.Hythere:BAAANQAECgEIAQAAAA==.',
['Hõ']='Hõnor:BAABNQAECn9IAAMOAAoKBCR/FgDeAgAOAAoKvSN/FgDeAgAcAAUKJCJdFwC2AQABNQAFFAYIBwAWAF4hAA==.',
Ia='Iammoo:BAAANQAECgIIAgAAAA==.',
Ig='Igriss:BAABNQAECn8VAAIOAAkKeBIErgCqAQAOAAkKeBIErgCqAQAAAA==.',
Il='Illidanx:BAAANQADCgQIBAAAAA==.Illuminaughd:BAABNQAECn8ZAAMYAAoK9xJmGQBzAQAYAAgKuBRmGQBzAQAPAAMKAg1aFgGRAAAAAA==.Ilumii:BAAANQAECgMIAwAAAA==.Ilydris:BAAANQAECgQIBgAAAA==.',
Im='Imonthegcd:BAAANQAECgYIDQABNQAFFAYIBwAWAF4hAA==.',
In='Infinitepain:BAACNQAFFH8IAAIgAAIKkhLTJACGAAAgAAIKkhLTJACGAAA1AAQKf0IAAiAACgp9I5oFAL4DACAACgp9I5oFAL4DAAE1AAQKAggCABMAAAAA.Innodk:BAABNQAECn8qAAICAAoKNxHQIADHAQACAAoKNxHQIADHAQAAAA==.',
Ir='Irami:BAAANQAECgEIAQAAAA==.Iridellis:BAAANQADCgcIBwABNQAECgoKVgAXAGEfAA==.',
Is='Ispankutank:BAAANQADCgEIAQAAAA==.',
It='Itslocotoo:BAAANQADCgEIAQAAAA==.',
Ja='Jabzert:BAAANQAECggIDAABNQAECgoKQwAGAA4bAA==.Jahjahblinks:BAAANQADCgYIFAABNQAECgoKSwADAI8PAA==.Jave:BAAANQABCgQIBQAAAA==.Jaycers:BAABNQAECn8tAAIYAAoKyyEtCwDmAgAYAAoKyyEtCwDmAgAAAA==.Jayclark:BAAANQADCgEIAQAAAA==.Jaçki:BAAANQAECggICAAAAA==.',
Ji='Jimmypal:BAABNQAECn8VAAIXAAYKwxJmYABlAQAXAAYKwxJmYABlAQAAAA==.',
Jo='Joedingle:BAABNQAECn80AAIRAAoKah0/LQBsAgARAAoKah0/LQBsAgAAAA==.Joemomma:BAAANQADCgUIBQAAAA==.Johnnyboi:BAAANQADCgEIAQAAAA==.Jokestarfist:BAABNQAECn8oAAIPAAkKtxXzkABqAQAPAAkKtxXzkABqAQAAAA==.',
Jr='Jr:BAAANQADCggICAAAAA==.',
Ka='Kaelar:BAAANQADCgMIAwABNQAECgoKQgAlAKIkAA==.Kaitokit:BAACNQAFFH8RAAMCAAUKuxoKDQDvAAACAAUKuxoKDQDvAAAmAAEKeQKlJQA1AAA1AAQKf1cAAwIACgp4IcgJANwCAAIACgp4IcgJANwCACYACAo/EPNdAJgBAAAA.Kalia:BAAANQADCgIIAgAAAA==.Kalyth:BAABNQAECn8dAAIBAAkKswfmVQBKAQABAAkKswfmVQBKAQAAAA==.Kamera:BAABNQAECn8aAAQPAAkKLx0WdgBBAgAPAAgKLx0WdgBBAgAXAAMK9gWh/QCBAAAYAAEKAAAycgAtAAAAAA==.Kandessa:BAAANQADCgIIAwAAAA==.Kaylah:BAABNQAECn85AAQaAAoK+SE3AwAGAwAaAAgKsiI3AwAGAwAZAAYKvh2yPwDOAQASAAQKYR2TVwBYAQAAAA==.Kayllina:BAABNQAECn8gAAIWAAkKCwNlbwCpAAAWAAkKCwNlbwCpAAAAAA==.Kayotic:BAAANQAECgUICwAAAA==.',
Ke='Kelmorphic:BAABNQAECn8/AAIVAAoK7SJMAgBkAwAVAAoK7SJMAgBkAwAAAA==.',
Ki='Kiestus:BAAANQAECgEIAQAAAA==.Killcommand:BAAANQADCggICAABNQAFFAQIEAARAAQXAA==.',
Ko='Kosmas:BAAANQAECgEJAQAAAA==.',
Kr='Krombear:BAAANQADCgIIAgAAAA==.',
Ku='Kudai:BAAANQAECgUIBgAAAA==.Kungpowchikn:BAAANQADCgIIAgAAAA==.Kurald:BAAANQAECgUIBQAAAA==.Kurisuw:BAAANQAECgYICwAAAA==.Kurookami:BAAANQADCgEIAQAAAA==.Kuukwa:BAAANQAECgUICAAAAA==.',
Ky='Kyana:BAAANQAECgcICgAAAA==.Kyarina:BAAANQABCggIEQAAAA==.',
['Kí']='Kíller:BAABNQAECn8gAAMDAAkKvQsedgCJAQADAAkKvQsedgCJAQAMAAMKWwXiaQCGAAAAAA==.',
La='Lamadda:BAAANQADCgUIBQAAAA==.Layonahands:BAAANQAECgMIAwAAAA==.',
Ld='Ldg:BAAANQADCgQIBAAAAA==.',
Le='Leafdaddy:BAAANQAECgUICQABNQAECgoKMgALAPMdAA==.Leakoon:BAAANQADCggICAAAAA==.Ledana:BAAANQAECgMIAwAAAA==.Lelise:BAABNQAECn8UAAIYAAgKzAGoXwBcAAAYAAgKzAGoXwBcAAAAAA==.Letusgiveita:BAAANQADCgQIBAAAAA==.',
Li='Lightbringr:BAAANQADCgYICwAAAA==.Lightingbolt:BAAANQADCgUICwAAAA==.Lightshields:BAAANQADCgIIAgAAAA==.Lilmissta:BAAANQAECgQIBAAAAA==.Lilpapi:BAAANQAECgcIBgABNQAFFAYIFgAkACEiAA==.Lilymei:BAAANQADCggIGAAAAA==.Linesondra:BAAANQADCgUICgAAAA==.Linissa:BAAANQAECgQIBgAAAA==.Littledude:BAAANQADCgYIBgAAAA==.Littlemorsel:BAABNQAECn8yAAIDAAoKPA3mVgDaAQADAAoKPA3mVgDaAQAAAA==.Livalifa:BAABNQAECn8iAAMDAAoKWg2AVgDbAQADAAoKWg2AVgDbAQAMAAMKQgNQcwBqAAAAAA==.',
Lo='Lockenload:BAAANQAECgYIDAAAAA==.Lockme:BAAANQADCgUIBQAAAA==.Lohhar:BAAANQADCggIFQAAAA==.Loser:BAAANQABCgQIBQAAAA==.Louthar:BAAANQAECggICAAAAA==.Lovin:BAAANQAECgQIBQAAAA==.',
Ls='Lselec:BAAANQAECgMJBQAAAA==.',
Lu='Lucens:BAABNQAECn8gAAIXAAgKXBABbgDOAQAXAAgKXBABbgDOAQAAAA==.Lucerna:BAABNQAECn8fAAIHAAoKxwnrRgDFAQAHAAoKxwnrRgDFAQAAAA==.Lunarfall:BAAANQADCgYIBgAAAA==.Lurchaug:BAAANQAECggIAwAAAA==.Lurchdh:BAAANQADCgQJBAABNQAFFAQIBgAbAEQGAA==.Lurchdruid:BAAANQAECgIIAQABNQAFFAQIBgAbAEQGAA==.Lurchmage:BAACNQAFFH8GAAIbAAQKRAbiBgCMAAAbAAQKRAbiBgCMAAA1AAQKfygAAxsACgouFEkIAPABABsACQouFEkIAPABABEABgoWBR9HARcBAAAA.Lurchn:BAABNQAECn99AAMbAAoKfRtcBADoAgAbAAoKfRtcBADoAgARAAkKowaj8ACpAQABNQAFFAQIBgAbAEQGAA==.Lurion:BAAANQADCgYIBgAAAA==.',
Ly='Lyricai:BAAANQAECgUIDwABNQAECggIKwAHALQeAA==.',
Ma='Madjake:BAAANQADCggICAAAAA==.Magallanes:BAAANQAECgQIBAAAAA==.Maggieaugers:BAAANQAECgUIBAABNQAECggIGQASAJEOAA==.Mapleleaf:BAABNQAECn8XAAMkAAgKjx7EDgAQAgAkAAgKjx7EDgAQAgAlAAQKmghfJACcAAAAAA==.Markyy:BAACNQAFFH8HAAIPAAQKPCLICgAMAQAPAAQKPCLICgAMAQA1AAQKfzoABA8ACgqrJfgEANIDAA8ACgqrJfgEANIDABcABgqmDzyUAGMBABgAAQoAAHpgAFoAAAE1AAUUBggHABYAXiEA.Matas:BAAANQAECggIDAAAAA==.Maylinfenora:BAABNQAECn8fAAIZAAgKhQzGRwCmAQAZAAgKhQzGRwCmAQAAAA==.Mazzikane:BAAANQADCgYIBgAAAA==.',
Me='Meangry:BAAANQAECgIIAgAAAA==.Meowizenith:BAAANQADCgUIBQAAAA==.Merdazin:BAAANQAECgQIDAAAAA==.Metalhedface:BAABNQAECn85AAMOAAoKRBmhMQBRAgAOAAoKRBmhMQBRAgAdAAEKvRifLgBHAAAAAA==.',
Mi='Mikecoxwall:BAAANQADCgEIAQAAAA==.Millexista:BAAANQABCgQIAgAAAA==.Minisan:BAAANQADCgEIAQAAAA==.Misary:BAAANQAECggIDQAAAA==.Missamy:BAAANQADCgYIBgAAAA==.Mistake:BAABNQAECn8WAAIOAAkKghBrnwDOAQAOAAkKghBrnwDOAQAAAA==.Mixjarnter:BAAANQADCggIFgAAAA==.',
Mo='Mogyar:BAABNQAECn8bAAIPAAcKBRassgC5AQAPAAcKBRassgC5AQAAAA==.Moistybush:BAAANQAECgEIAQAAAA==.Moltalgol:BAAANQAECgQICgAAAA==.Monkeli:BAABNQAECn8dAAIdAAcKkxViDQDhAQAdAAcKkxViDQDhAQAAAA==.Moocifer:BAAANQADCgcIDQAAAA==.Moocifermoo:BAAANQAECgIIAQAAAA==.Moogrim:BAAANQADCggIEAAAAA==.Moonsiand:BAEBNQAECn80AAIDAAgK3SDRIgAMAwADAAgK3SDRIgAMAwABNQAECgoKSAADAAUhAA==.Morbidon:BAAANQAECgUIBQAAAA==.Moreldwiddle:BAABNQAECn8dAAMjAAcKdBVzDwBYAQAjAAYK/xJzDwBYAQAEAAYK0RGbkwD8AAAAAA==.Morgaia:BAAANQAECgYIBQAAAA==.Morrigån:BAAANQADCgMIAwAAAA==.Mosschin:BAAANQAECgcIBwAAAA==.Motgus:BAABNQAECn8YAAQEAAgKhR6khQDYAQAEAAYKlR+khQDYAQAiAAIKZRxxRwCqAAAjAAIKVxvwHACWAAAAAA==.Mozzsticks:BAAANQADCgYICwAAAA==.',
Ms='Mshottie:BAAANQAECgYICwAAAA==.',
Mx='Mx:BAAANQADCgYIDwAAAA==.',
My='Mystrialia:BAAANQABCgYIBgAAAA==.Mythlock:BAAANQADCgcIEwAAAA==.Mythranite:BAAANQADCgMIAwAAAA==.Myway:BAAANQADCggICAAAAA==.',
['Mó']='Mócha:BAABNQAECn8oAAQlAAkK4wfuHQDMAAAlAAcKPgnuHQDMAAAQAAUKegPmXwB6AAAkAAEKAAByXwA2AAAAAA==.',
Na='Nardrian:BAAANQAECgQIBQAAAA==.Naydian:BAAANQAECgQIBAAAAA==.',
Ne='Necrozma:BAAANQAECggIDgAAAA==.Nekiron:BAAANQADCgQIBAAAAA==.Nellaa:BAAANQAECgcICAAAAA==.Nerrd:BAAANQAECgEIAQAAAA==.Nestaria:BAAANQADCggICAAAAA==.Netalanot:BAAANQADCgYIBgAAAA==.Nettik:BAAANQADCgUIBwAAAA==.Neverborn:BAABNQAECn8jAAIQAAcKnBCdPgD9AAAQAAcKnBCdPgD9AAAAAA==.',
Ni='Nightalucard:BAAANQADCgYIBgAAAA==.Nightrage:BAABNQAECn8VAAMFAAcKfwJOWwCCAAAFAAcKfwJOWwCCAAAUAAQKKgFBZABZAAAAAA==.Nilex:BAABNQAECn8XAAIOAAgKXhI2ZwCRAQAOAAgKXhI2ZwCRAQAAAA==.',
No='Nomadic:BAAANQADCgIIAgAAAA==.Notmypally:BAAANQAECgUIBQABNQAFFAQICQARAAcRAA==.',
Nu='Numera:BAAANQADCgIIAwABNQAECggIDwATAAAAAA==.Nutellaqq:BAABNQAECn8YAAIRAAcK1xrQuwAMAgARAAcK1xrQuwAMAgAAAA==.',
['Nê']='Nêkê:BAABNQAFFH8MAAIBAAYKzBA+CAAqAQABAAYKzBA+CAAqAQAAAA==.',
Ob='Obeseotter:BAABNQAECn8uAAIRAAgK6ReXowA6AgARAAgK6ReXowA6AgAAAA==.Oborax:BAEBNQAECn8lAAIPAAkKTRVkcQCtAQAPAAkKTRVkcQCtAQABNQAECgoKSAADAAUhAA==.',
Od='Od:BAAANQAECgMIAgAAAA==.',
Ol='Oliviabenson:BAABNQAECn8rAAIRAAkKMyCvNgBJAgARAAkKMyCvNgBJAgAAAA==.',
Ox='Oxsidius:BAAANQAECgQICAAAAA==.',
Pa='Palady:BAAANQADCgEIAQAAAA==.Palatard:BAAANQAECgEIAQAAAA==.Paldi:BAAANQAECgQIBAABNQAECgYIBgATAAAAAA==.Paliboos:BAAANQADCgYIBgAAAA==.Pallychri:BAAANQAECgYIBQAAAA==.Palulu:BAEANQAECggIDwAAAA==.Pandacub:BAAANQAECggICAAAAA==.Pariss:BAAANQAECggICgAAAA==.Paws:BAABNQAECn8gAAIQAAcKuwkHRADjAAAQAAcKuwkHRADjAAAAAA==.Pawse:BAAANQADCggIDwAAAA==.',
Pe='Peaky:BAABNQAECn84AAQnAAkKOQsPIwBqAQAnAAkKOQsPIwBqAQALAAYK4AOcGQB2AAAeAAIKNAGfbwArAAAAAA==.Perelia:BAABNQAECn8gAAIhAAcKrQ8QDAB6AQAhAAcKrQ8QDAB6AQAAAA==.',
Ph='Phlawless:BAAANQAECgMIAgAAAA==.',
Pl='Plondor:BAAANQABCgEIAQAAAA==.',
Po='Polarity:BAABNQAECn8gAAMfAAcKqAumLwDTAAAfAAcKqAumLwDTAAAgAAEKTwDGDgERAAABNQAECgoKKgADACkYAA==.Pooche:BAAANQAECgIIAwAAAA==.Popcola:BAAANQAECgQICQAAAA==.Pouts:BAAANQAECgQIBAABNQAFFAIICQATAAAAAA==.Powerpaladin:BAAANQABCgQIBAAAAA==.',
Pp='Ppc:BAAANQAECgQICwABNQAFFAQIEAARAAQXAA==.',
Pr='Prezu:BAEBNQAECn8VAAIIAAcKnA4NKgBfAQAIAAcKnA4NKgBfAQABNQAECggIDwATAAAAAA==.Procyonx:BAAANQAECgEIAQAAAA==.Prophofdoom:BAABNQAECn8pAAIcAAkKYCHpBgDyAgAcAAkKYCHpBgDyAgAAAA==.Prõc:BAAANQADCggICAAAAA==.',
Pv='Pvc:BAACNQAFFH8QAAIRAAQKBBd2GwDxAAARAAQKBBd2GwDxAAA1AAQKfyEAAxEACgprIoxHAPQCABEACgprIoxHAPQCACgAAQqaAGAPACUAAAAA.',
Py='Pyrosong:BAAANQADCggICAAAAA==.',
Ra='Raisedead:BAAANQADCgIIAgABNQADCggIDAATAAAAAA==.Rancord:BAAANQADCggICAAAAA==.Rangrr:BAAANQADCgMIAQAAAA==.Rasmira:BAAANQADCggICAAAAA==.Rastaqwon:BAAANQAECgEIAQABNQAECgQIBgATAAAAAA==.Ratsmasher:BAAANQAECgIIAgAAAA==.Ravenight:BAAANQADCgMIAwAAAA==.Razed:BAAANQADCgYICwAAAA==.',
Re='Renoitukax:BAABNQAECn8uAAMgAAoKXiCCDQBNAwAgAAoK/x2CDQBNAwAhAAcKFh9KBgAuAgAAAA==.Restfuldark:BAAANQAECgUICQAAAA==.Retrobution:BAABNQAECn8xAAIPAAoKaSLGJwAnAwAPAAoKaSLGJwAnAwAAAA==.Rezz:BAAANQAECgcIDAAAAA==.',
Rh='Rhohir:BAAANQABCgIIAgAAAA==.',
Ri='Riru:BAAANQAECgQIBwAAAA==.',
Ro='Rockstéady:BAAANQAECggIDAAAAA==.Roopall:BAABNQAECn8tAAIXAAoKByATDwBSAwAXAAoKByATDwBSAwAAAA==.Roxas:BAAANQADCgYIBgAAAA==.',
Ry='Rynzu:BAAANQAECgMIBAAAAA==.Ryzen:BAAANQAECgcIDQAAAA==.',
Sa='Sabelwin:BAAANQADCgEIAQAAAA==.Sanasrindis:BAAANQADCgQIAgAAAA==.Saninar:BAABNQAECn8nAAIYAAgKDQvHMgBMAQAYAAgKDQvHMgBMAQAAAA==.Sanshift:BAAANQAECgQIBAAAAA==.Satansimp:BAAANQAECgMIAgAAAA==.',
Sc='Schezmu:BAAANQAECgUICAAAAA==.',
Se='Sean:BAAANQADCgUICgAAAA==.Senorfiesta:BAABNQAECn8uAAImAAkK1xROHADQAQAmAAkK1xROHADQAQAAAA==.Serazarke:BAAANQAECgEIAgAAAA==.Setazen:BAAANQAECgEIAQAAAA==.',
Sh='Shadowjoker:BAAANQAECgEIAQAAAA==.Shaee:BAABNQAECn8dAAMFAAYKyxdZQQC1AQAFAAYKyxdZQQC1AQAUAAEKAADRdQAjAAAAAA==.Shamama:BAAANQADCgUIBQAAAA==.Shamans:BAAANQAECgUIDAAAAA==.Shambalaya:BAAANQAECgcIEgAAAA==.Shaokhan:BAABNQAECn8jAAMOAAgKUwhijwAsAQAOAAgKUwhijwAsAQAdAAIKxwn8LAAuAAAAAA==.Shasta:BAACNQAFFH8WAAIkAAYKISK0AACHAQAkAAYKISK0AACHAQA1AAQKfy8AAiQACgo4JqwBAMUDACQACgo4JqwBAMUDAAAA.Shihthead:BAAANQADCgUIBQAAAA==.Shisuiuchiha:BAAANQADCgIIAgAAAA==.Shmorg:BAAANQADCgEIAQAAAA==.Shootumup:BAABNQAECn89AAMpAAkKUiRqAQBdAwApAAkKUiRqAQBdAwADAAEKZRcjSwFJAAAAAA==.Shyx:BAABNQAECn84AAQgAAoKUyONFQAlAwAgAAoKUyONFQAlAwAfAAcKCw1nNQB4AQAhAAEKjRmbJQBBAAAAAA==.',
Si='Simplèjack:BAABNQAECn8fAAIRAAcKswnF/wCOAQARAAcKswnF/wCOAQAAAA==.Sinamon:BAABNQAECn8YAAIPAAYKFxtC1ABzAQAPAAYKFxtC1ABzAQAAAA==.Sinani:BAAANQADCgUJBQAAAA==.Sinnamon:BAAANQABCgQJBAABNQAECgYIGAAPABcbAA==.',
Sj='Sjdh:BAAANQADCgYIBgABNQAECgoKNAAOAIccAA==.Sjrogue:BAAANQAECggICAABNQAECgoKNAAOAIccAA==.',
Sk='Skar:BAAANQADCgUIBgAAAA==.Skram:BAAANQAECgUICAABNQAECgoKMwAPAJwNAA==.Skronker:BAAANQADCggIDQAAAA==.',
Sl='Slammydooker:BAABNQAECn8tAAMSAAoKRxjBHgBnAgASAAoKRxjBHgBnAgAZAAUKfw0RXwA5AQAAAA==.',
Sm='Smallkat:BAAANQAECgUIBQAAAA==.Smirksfotm:BAAANQAECgUICAABNQAECggIEAATAAAAAA==.Smoketail:BAAANQAECgUIBwAAAA==.',
Sn='Snail:BAAANQAECgYIBgAAAA==.Sneakmanman:BAAANQADCgYJCQAAAA==.',
So='Somberdh:BAAANQADCggICwAAAA==.Sorni:BAABNQAECn8/AAMPAAoKrQjXlABiAQAPAAoKrQjXlABiAQAYAAIK7wK5awA7AAAAAA==.Soulglo:BAAANQAECgQIBAAAAA==.',
Sp='Spellslanger:BAAANQADCgQIBAAAAA==.Spikeprotein:BAAANQABCggICQAAAA==.Sprayandpray:BAABNQAECn8XAAIRAAoKSRxVNABSAgARAAoKSRxVNABSAgAAAA==.Spritey:BAAANQABCgIIAgAAAA==.',
Sq='Squidnips:BAAANQAECgEIAQAAAA==.',
St='Stareless:BAAANQADCgYIBgAAAA==.Statik:BAAANQAECgMIAwAAAA==.Stinkified:BAAANQAECgEIAQAAAA==.Stoneychri:BAAANQAECgMIAwAAAA==.',
Su='Summondemons:BAAANQAECgIIBQAAAA==.Sumnèr:BAAANQADCgMIAwAAAA==.Sunpali:BAAANQAECgYICgAAAA==.Susanno:BAAANQADCgUJCwAAAA==.',
Sy='Sylauda:BAAANQADCgYICgAAAA==.Sylvians:BAAANQAECgEIAQAAAA==.',
Ta='Tacutacudark:BAAANQAECgUIDwAAAA==.Taintedbeef:BAAANQADCgEIAQABNQAECgYIDQATAAAAAA==.Talonflame:BAABNQAECn8qAAQMAAgKHxWVLwDQAQAMAAcKNhaVLwDQAQADAAMKEReXFgHWAAApAAIKiwrxDACLAAAAAA==.Talonted:BAAANQAECgIIAgAAAA==.Tandallei:BAAANQAECgQIBAAAAA==.Tansu:BAAANQADCgcIDQAAAA==.Tarishi:BAAANQAECgYIBwAAAA==.Tarishii:BAAANQAECgcIDAAAAA==.Tateraid:BAAANQABCgYICQAAAA==.Taterpuff:BAAANQABCgUIBQAAAA==.Taupo:BAAANQAECgEIAgAAAA==.Taxidermy:BAAANQADCgYIDAAAAA==.',
Te='Telarinda:BAABNQAECn8WAAMEAAoK5QcwigASAQAEAAkKgwcwigASAQAiAAIKkAqnaQBOAAAAAA==.',
Th='Thametal:BAAANQAECgIIAgAAAA==.Thicclich:BAABNQAECn8eAAIWAAoKYw1ELwCxAQAWAAoKYw1ELwCxAQAAAA==.Thicktotem:BAAANQAECgEIAQAAAA==.Thickumz:BAAANQADCgQIBAAAAA==.Thinmint:BAAANQADCgcICQAAAA==.Thisismeta:BAAANQAECgYICgAAAA==.Thorynwar:BAACNQAFFH8YAAIOAAYKIB7GCQAXAgAOAAYKIB7GCQAXAgA1AAQKfzgAAg4ACgr5JYoHAEkDAA4ACgr5JYoHAEkDAAE1AAUUBQgNACYAIhQA.Thorýn:BAACNQAFFH8NAAMmAAUKIhR7DgAkAQAmAAQKIhR7DgAkAQACAAEKAABpKABXAAA1AAQKfyUAAyYACQpzJooQADMDACYACQpzJooQADMDAAIABwriGR9HAN0BAAAA.Thyrnoch:BAAANQAECgEIAQAAAA==.Thórin:BAABNQAECn8VAAIYAAcKEhdSKACbAQAYAAcKEhdSKACbAQAAAA==.',
Ti='Tierax:BAABNQAECn82AAMSAAoK2h85CQDiAgASAAkKpiA5CQDiAgAZAAMKNxhKdQDcAAAAAA==.Tipsy:BAABNQAECn8uAAIHAAoKXBE1ZQDdAQAHAAoKXBE1ZQDdAQAAAA==.',
To='Tojì:BAAANQAECggIEAAAAA==.Tonathul:BAAANQADCggIEAAAAA==.Torrk:BAAANQAECgQIBAAAAA==.Torultrear:BAAANQAECgIIAgAAAA==.Tot:BAABNQAECn8qAAIHAAoKEgwIfwCPAQAHAAoKEgwIfwCPAQAAAA==.',
Tr='Tralleth:BAABNQAECn8lAAMJAAgKLxgLDACZAQAJAAcK+xULDACZAQAIAAcKog9xLABFAQAAAA==.Trallock:BAAANQAECgEIAQAAAA==.Traumatized:BAAANQADCgUIBwAAAA==.Truska:BAAANQABCgEIAQAAAA==.',
Ts='Tsoi:BAAANQAECggICAAAAA==.',
Tu='Tuskyrex:BAAANQAECgEIAQAAAA==.',
Tw='Twinklord:BAAANQAECggIDgAAAA==.Twostroke:BAABNQAECn8yAAIDAAoKriXGBgCnAwADAAoKriXGBgCnAwAAAA==.Twretwtwrewr:BAAANQADCgIIAgAAAA==.Twunkie:BAAANQADCgcIBwAAAA==.',
Ty='Tylopally:BAAANQAFFAIIAgAAAA==.Tyloremixdd:BAAANQAECgQIBAAAAA==.Tylototem:BAAANQAECgQIBAAAAA==.',
['Tö']='Tötem:BAAANQADCgMIAwABNQAFFAYIBwAWAF4hAA==.',
Uj='Ujcpet:BAAANQADCgYIBgAAAA==.',
Un='Uncookedham:BAAANQADCgYIEAAAAA==.Underhorn:BAAANQADCggIDgAAAA==.',
Va='Vaas:BAAANQADCggICAABNQAECgoKLQAYAMshAA==.Vaeelrundor:BAABNQAECn8jAAIDAAcKrwgvsQALAQADAAcKrwgvsQALAQAAAA==.Valyr:BAAANQADCgUIBAAAAA==.Vampslayer:BAAANQADCgYIBgAAAA==.Vanillaface:BAAANQAECggIDgAAAA==.Vañillaface:BAAANQABCgQIBgAAAA==.',
Ve='Vedebone:BAAANQAECgUIDAAAAA==.Vedexd:BAABNQAECn8pAAIDAAcKrRDfoADEAQADAAcKrRDfoADEAQAAAA==.Velarael:BAABNQAECn8hAAMjAAgKAQ+/DQB8AQAjAAcK0RC/DQB8AQAEAAIKOgV/5ABfAAAAAA==.Veletharia:BAAANQADCgQICAAAAA==.Velexi:BAAANQADCgQIBwAAAA==.',
Vh='Vheckxus:BAABNQAECn8UAAIBAAUKLwuRgwDPAAABAAUKLwuRgwDPAAAAAA==.',
Vi='Vivi:BAAANQAECgIIAgAAAA==.',
Vl='Vlidya:BAAANQADCgEIAQAAAA==.',
Vo='Voidberg:BAAANQAECgYICAAAAA==.',
Vs='Vs:BAAANQAECggIDgAAAA==.',
Wa='Wachonaso:BAACNQAFFH8JAAIEAAQKgQtjGgAjAQAEAAQKgQtjGgAjAQA1AAQKfykAAwQACgooHV0/AJQCAAQACgq0HF0/AJQCACIAAwokHcwwAAUBAAAA.Wastedsage:BAAANQAECgUICAAAAA==.Waterlou:BAAANQAECgIIAgAAAA==.',
We='Weavefang:BAAANQADCgUIBQAAAA==.',
Wh='Whatuphuz:BAAANQADCggIEAAAAA==.Wheresmyjaw:BAACNQAFFH8IAAIEAAIKHB9UGAC1AAAEAAIKHB9UGAC1AAA1AAQKfz4AAwQACgr/I60RAMcCAAQACQpGJK0RAMcCACIAAwpeGF89AMwAAAAA.',
Wi='Wildthree:BAABNQAECn8hAAILAAgKFwxdDQAlAQALAAgKFwxdDQAlAQAAAA==.Wilkieswar:BAAANQADCggIGAABNQAECgoKLgARADgfAA==.Willenda:BAAANQAECgEIAgAAAA==.Winterfall:BAAANQAECgQIBAAAAA==.',
Wu='Wuinn:BAACNQAFFH8PAAIIAAcKdgivCQCVAQAIAAcKdgivCQCVAQA1AAQKfy0ABAgACgrBF44VAFsCAAgACgrBF44VAFsCAAkABwo+ECYJAFMBAAoAAQpUDSchADgAAAAA.',
Xa='Xakutioner:BAABNQAECn88AAIQAAoKvB6bFAAiAwAQAAoKvB6bFAAiAwAAAA==.Xaldiir:BAABNQAECn85AAIFAAoKYSKzCADxAgAFAAoKYSKzCADxAgAAAA==.',
Xe='Xenvoroo:BAAANQADCgIIAgAAAA==.Xerexia:BAABNQAECn9BAAIOAAkKDQ8RowDFAQAOAAkKDQ8RowDFAQAAAA==.Xeràth:BAAANQAECgYICAAAAA==.',
Xs='Xsjàdo:BAAANQADCgYIBwAAAA==.',
Xw='Xwoo:BAAANQAECgQIBQAAAA==.',
Xz='Xzarlatan:BAAANQADCgIIAgAAAA==.Xzarlatanfi:BAAANQADCgUIBQAAAA==.',
Ya='Yahro:BAAANQAECgcIEQAAAA==.',
Ye='Yellowranger:BAABNQAECn9EAAIXAAoKLSAlCgBgAwAXAAoKLSAlCgBgAwAAAA==.',
Yj='Yjn:BAABNQAECn8hAAILAAoKoQtfDAA3AQALAAoKoQtfDAA3AQABNQAECgoKKgADACkYAA==.',
Yo='Yongyong:BAABNQAECn8dAAMEAAgKAhwYSwC8AQAEAAgKAhwYSwC8AQAiAAEKAAA8bgBCAAAAAA==.Yotoymuerto:BAAANQAECgEIAQAAAA==.',
Yu='Yunara:BAAANQAECgYIBgAAAA==.Yustayoke:BAABNQAECn8mAAIRAAgKihQarwAkAgARAAgKihQarwAkAgAAAA==.',
Za='Zalvianna:BAAANQAECgYICAAAAA==.Zarathoz:BAAANQABCgYJBgAAAA==.Zarshx:BAAANQADCgQICAABNQAECgYIBgATAAAAAA==.',
Ze='Zennithz:BAAANQAECggIEAAAAA==.Zeonz:BAAANQAECgEIAQAAAA==.',
Zh='Zhoya:BAAANQAECggICAAAAA==.',
Zi='Zilong:BAAANQAECgMIBQABNQAFFAcIDQAOADkTAA==.Zilongmage:BAAANQAECggICAABNQAFFAcIDQAOADkTAA==.Zilongwar:BAACNQAFFH8NAAIOAAcKOROwCwD3AQAOAAcKOROwCwD3AQA1AAQKfyIAAg4ACgp0Iq8sAAoDAA4ACgp0Iq8sAAoDAAAA.',
Zo='Zombor:BAAANQADCgIIAgAAAA==.Zonecw:BAABNQAECn8fAAMcAAoKGhjoDgCOAQAcAAkKGhjoDgCOAQAOAAEKAAAiUgE0AAAAAA==.Zonedk:BAAANQAECgQIBgABNQAECgoKHwAcABoYAA==.',
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
