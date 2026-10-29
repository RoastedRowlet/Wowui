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
local provider = {region='US',realm='Nazjatar',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aanon:BAAANQAECgEIAQAAAA==.',
Ab='Aberoth:BAAANQADCggIDAAAAA==.',
Ac='Accoli:BAAANQAECgUIBQAAAA==.Acslater:BAAANQADCgQIBAAAAA==.',
Ag='Agoobagoo:BAACNQAFFH8KAAIBAAMK+CBZFQAkAQABAAMK+CBZFQAkAQA1AAQKfxUAAgEACQpuHvEYADMDAAEACQpuHvEYADMDAAE1AAUUBggWAAIAZh8A.',
Al='Aliasx:BAAANQAECgQIBAAAAA==.Alissaria:BAAANQAECgEIAQAAAA==.Allarus:BAAANQADCgcICQAAAA==.Allwrong:BAAANQADCgQIBAAAAA==.Alotofsin:BAAANQAECgEIAQAAAA==.Alphadog:BAEBNQAECn8+AAIDAAoKYh7kGQCLAgADAAoKYh7kGQCLAgAAAA==.Alwaysunny:BAAANQADCgYIDAAAAA==.',
Am='Amahlfarouk:BAABNQAECn8iAAIEAAcKDRT2cwASAQAEAAcKDRT2cwASAQAAAA==.Aminatou:BAABNQAECn8vAAIFAAoK2RIFGQDaAQAFAAoK2RIFGQDaAQAAAA==.',
Ar='Ariaddne:BAABNQAECn8gAAQGAAkKthfKFQAMAgAGAAkK/xbKFQAMAgABAAYKbhQuswAsAQAHAAEKwRi6FAFAAAAAAA==.Artemîs:BAAANQAECgEIAQAAAA==.',
As='Ashaelra:BAAANQAECgUIBQAAAA==.Asolitha:BAAANQADCgUIBQAAAA==.',
Au='Augonly:BAABNQAFFH8JAAIIAAMKABPJEADdAAAIAAMKABPJEADdAAAAAA==.Augy:BAABNQAECn8mAAMJAAoKUxkgBwA+AgAJAAcK0hogBwA+AgAKAAkKrBZsFQD1AQAAAA==.',
Ay='Aystria:BAAANQADCgMIAgAAAA==.',
Ba='Bakuretsu:BAABNQAECn8dAAILAAgKMCLsAQDBAgALAAgKMCLsAQDBAgABNQAECgoKMwALAAscAA==.Barhead:BAAANQADCggIDgAAAA==.Barlow:BAABNQAECn8bAAIMAAgKgQJ8KQC7AAAMAAgKgQJ8KQC7AAAAAA==.',
Bb='Bbldrizzy:BAACNQAFFH8NAAIBAAcKsxooCQDcAQABAAcKsxooCQDcAQA1AAQKfyoAAgEACgpPJLcRAGEDAAEACgpPJLcRAGEDAAAA.',
Be='Beastlieduke:BAAANQADCgYIDAABNQAECggIHQANAGUdAA==.Beastlièduke:BAAANQADCgIIAgABNQAECggIHQANAGUdAA==.Belephon:BAAANQAECgQIBwAAAA==.Belinda:BAAANQAECgQIBAAAAA==.',
Bi='Bighunt:BAAANQAECgMIAwAAAA==.Bijju:BAAANQAECggIEgAAAA==.Binggus:BAABNQAECn8XAAIOAAgKyh1+VQCKAgAOAAgKyh1+VQCKAgAAAA==.',
Bl='Blabbybootze:BAABNQAECn8dAAIPAAcKFwMrKgHaAAAPAAcKFwMrKgHaAAAAAA==.Bladelight:BAAANQAECgIIAQAAAA==.Blighte:BAAANQAECgQIBAABNQAFFAMIBQAQALUVAA==.Blightfangs:BAABNQAECn8jAAIRAAgKERiLXgCSAQARAAgKERiLXgCSAQAAAA==.Bloodieelish:BAAANQAECgIIAQABNQAECggIGQASAJEOAA==.Bluzey:BAAANQAECgcIBwAAAA==.',
Bo='Bodakye:BAABNQAECn8nAAIDAAoKMxTdLQApAgADAAoKMxTdLQApAgAAAA==.Boneplague:BAAANQADCgQIBAAAAA==.Boow:BAAANQAECgUIBQAAAA==.',
Br='Bracalina:BAAANQAECgMIAgAAAA==.Brannix:BAAANQADCgUIBQAAAA==.Broggy:BAAANQADCgEIAQABNQAECgcICAATAAAAAA==.Brorgy:BAABNQAECn8bAAQUAAYKqQiFRQAmAQAUAAYKqQiFRQAmAQAVAAEKAADaOQAZAAAFAAEKSQGwdAANAAABNQAECggIGQASAJEOAA==.',
Bu='Bubbapal:BAAANQADCgUIBwAAAA==.Bushntush:BAAANQADCggICQAAAA==.Buzzbuzz:BAAANQAECgMIBAAAAA==.',
By='Bywar:BAAANQADCgcICwAAAA==.',
['Bé']='Bébop:BAAANQAECggIDgAAAA==.',
Ca='Caeruleus:BAAANQADCgQJBAAAAA==.Captyn:BAAANQABCgQIAwAAAA==.Catbum:BAAANQADCgIIAwAAAA==.Caylea:BAAANQADCggICAAAAA==.',
Ch='Chaosraven:BAABNQAECn84AAIWAAoKbw/AIwCwAQAWAAoKbw/AIwCwAQAAAA==.Chapelgnome:BAAANQADCgUJBQABNQAECggIGQASAJEOAA==.Charlyne:BAAANQABCgMIAwAAAA==.Chewthymight:BAABNQAECn8wAAMPAAoKfhN/VQC1AQAPAAkKeBR/VQC1AQAXAAcKlQiMygDmAAAAAA==.Chickenslop:BAAANQAECgUIBAAAAA==.Chiptime:BAAANQAECgUIDAAAAA==.Chloes:BAAANQAECgIIAgAAAA==.Chri:BAAANQAECgUIBwAAAA==.Chrri:BAAANQAECgIIAwAAAA==.Chungotron:BAACNQAFFH8IAAMPAAYK9g6dDgBjAQAPAAUKEgudDgBjAQAYAAEKhh7cCABaAAA1AAQKfxUAAg8ACgoiICYQAPYCAA8ACgoiICYQAPYCAAAA.Chzburger:BAAANQABCgIIBAAAAA==.',
Cl='Cladon:BAAANQAECggICAAAAA==.Clairity:BAAANQADCgcIBwAAAA==.',
Co='Cocoon:BAAANQAECgQIBAABNQAFFAQIEAARAAQXAA==.Conda:BAAANQAECggIEgAAAA==.Cormogh:BAAANQAECgYICgAAAA==.Cowhealer:BAACNQAFFH8FAAIQAAMKtRUdHQCqAAAQAAMKtRUdHQCqAAA1AAQKfzAAAxAACgpQIX0SACMCABAACgpQIX0SACMCAA0AAwrEDEtcAJYAAAAA.',
Cr='Craeftig:BAABNQAECn8hAAMZAAoKGxjQCQDrAQAZAAoKGxjQCQDrAQAaAAEKowHIHwAWAAAAAA==.Craeftigdk:BAABNQAECn8dAAICAAcKAQ7nWgCHAQACAAcKAQ7nWgCHAQABNQAECgoKIQAZABsYAA==.Craeftigtwo:BAAANQADCggJDQABNQAECgoKIQAZABsYAA==.Craeftigwl:BAAANQAECgIIAgABNQAECgoKIQAZABsYAA==.Crepitus:BAABNQAECn8WAAMSAAYKEgzZLQBTAQASAAYKEgzZLQBTAQAZAAIKWQXrlQBdAAAAAA==.Crusabull:BAAANQADCgcIBwAAAA==.Cræftig:BAABNQAECn8bAAMbAAkKxRjGBwBvAgAbAAgKqxzGBwBvAgARAAMKkwmJmQGTAAABNQAECgoKIQAZABsYAA==.',
Cu='Cuddlseraph:BAAANQAECgUIEgAAAA==.Cutestcc:BAAANQAECggICgAAAA==.',
Cy='Cynnithice:BAAANQADCgIIAgABNQAECgMIAgATAAAAAA==.',
Da='Daamdam:BAABNQAECn8ZAAIcAAgKjgPSLwC3AAAcAAgKjgPSLwC3AAAAAA==.Dafirenze:BAAANQADCggIDwAAAA==.Daftxshade:BAAANQAECgQIBAAAAA==.Dariian:BAABNQAECn8WAAIdAAgKJAJWHQBTAAAdAAgKJAJWHQBTAAAAAA==.Darkbeef:BAABNQAECn8VAAIEAAYKDQOi9wDcAAAEAAYKDQOi9wDcAAAAAA==.Darkjusticeh:BAAANQAECgUIBwAAAA==.Darlang:BAAANQAECgUICgAAAA==.Darthbjóurn:BAAANQAECgUIBQAAAA==.Darthsyde:BAABNQAECn8fAAICAAkKhhBgMgAhAQACAAkKhhBgMgAhAQAAAA==.Dayanna:BAAANQADCgUIBQAAAA==.',
De='Deadergriff:BAAANQAECgUIEgAAAA==.Deadicated:BAABNQAECn8ZAAIeAAgKawg+OwA6AQAeAAgKawg+OwA6AQAAAA==.Deadinsíde:BAAANQAECggICAABNQAECggIEAATAAAAAA==.Deathlyaura:BAAANQADCggICAABNQAECgUICAATAAAAAA==.Deathmark:BAAANQAECgUICAAAAA==.Deeznutzs:BAAANQAECgYIEgAAAA==.Defendaya:BAAANQAECggICAAAAA==.Delan:BAAANQAECgYIBwAAAA==.Demolishonn:BAAANQAECgUIDAAAAA==.Desunaito:BAACNQAFFH8QAAIWAAcKfRX7AwDkAQAWAAcKfRX7AwDkAQA1AAQKfz4AAhYACgoWJDMFABkDABYACgoWJDMFABkDAAAA.Dexter:BAAANQAECgQIBQAAAA==.',
Dh='Dhzilong:BAAANQAECggIDAABNQAFFAcIDQAOADkTAA==.',
Di='Diddlefiddle:BAAANQADCgIIAgAAAA==.Dimeo:BAAANQADCgQIAQAAAA==.Dioji:BAAANQAECggIBgAAAA==.',
Dk='Dkzilong:BAAANQAECgIIBQABNQAFFAcIDQAOADkTAA==.',
Dm='Dmeo:BAAANQADCgMIAwAAAA==.',
Do='Docadoodle:BAAANQADCgcIBwABNQAECgoKLgAUAL0YAA==.Docarcanis:BAAANQAECgYIBgABNQAECgoKLgAUAL0YAA==.Docwyle:BAABNQAECn8uAAIUAAoKvRiFGACYAgAUAAoKvRiFGACYAgAAAA==.Doozey:BAAANQABCgcJBwAAAA==.',
Dr='Dracmary:BAAANQADCgUIBQAAAA==.Dracnogard:BAAANQAECgUICwAAAA==.Dracowulf:BAABNQAECn8fAAIDAAYK5wW93gBDAQADAAYK5wW93gBDAQAAAA==.Dragonbro:BAAANQAECgEIAQAAAA==.Dragonx:BAABNQAECn8nAAIDAAcKHgpbywBqAQADAAcKHgpbywBqAQAAAA==.Drakowolf:BAABNQAECn8WAAIKAAkKZgUvJAAgAQAKAAkKZgUvJAAgAQAAAA==.Drama:BAAANQAECgEIAQAAAA==.Dreadful:BAABNQAECn9MAAIXAAoKih2JCwAPAwAXAAoKih2JCwAPAwAAAA==.Dreorge:BAABNQAECn8XAAIIAAkKNBWxEwByAgAIAAkKNBWxEwByAgAAAA==.Drewceratops:BAABNQAECn8aAAIPAAkKVA+WnwDiAQAPAAkKVA+WnwDiAQAAAA==.Drewidd:BAAANQAECgUIBQABNQAECggIGQASAJEOAA==.Drimchi:BAAANQAECgEIAQAAAA==.Drimveil:BAABNQAECn8ZAAIFAAkKPhgLLgA0AgAFAAkKPhgLLgA0AgAAAA==.Drogô:BAAANQAECgQICAAAAA==.Dromgar:BAAANQAECggIEQABNQAECgoKHQAGACEkAA==.Dromkyr:BAABNQAECn8wAAMIAAoKnQ+cGwAPAgAIAAoKnQ+cGwAPAgAKAAEKNwtJPQAyAAAAAA==.Drossiechan:BAACNQAFFH8QAAIeAAUK5A/QBgDQAAAeAAUK5A/QBgDQAAA1AAQKfyMAAh4ACgq6GrwZAHQCAB4ACgq6GrwZAHQCAAAA.',
Du='Duellipa:BAABNQAECn8ZAAMSAAgKkQ4ITgAlAQASAAcK7g8ITgAlAQAZAAQKwwajewDEAAAAAA==.',
Dy='Dysian:BAAANQADCgQIBQAAAA==.Dywanw:BAAANQABCgYIBgAAAA==.',
Ed='Edward:BAAANQAECggJBwAAAA==.',
Ef='Effloria:BAABNQAECn85AAMNAAoKvSNkAwCSAwANAAoKvSNkAwCSAwAQAAEKAACHfgAAAAAAAA==.',
Ek='Ekim:BAAANQADCgQIAwAAAA==.Eklyps:BAAANQADCgYIBgAAAA==.',
El='Elauvia:BAAANQAECgUICAAAAA==.Elegia:BAAANQAECggIDgAAAA==.',
Em='Emleah:BAAANQAECgcICgAAAA==.Emmaina:BAAANQAECgIIAgAAAA==.',
En='Enash:BAAANQADCgQIBAAAAA==.Encoredh:BAAANQAECgQIBAABNQAECggIIQAfAEcZAA==.Encoredk:BAAANQADCgIIAgAAAA==.Encoree:BAAANQADCgcIBwABNQAECggIIQAfAEcZAA==.Encoremts:BAAANQAECgEIAQABNQAECggIIQAfAEcZAA==.Encorep:BAABNQAECn8hAAQfAAgKRxnhJQAAAgAfAAcKBhfhJQAAAgAgAAQKTgkitQBXAAAhAAIK2AMmDwBGAAAAAA==.Enris:BAAANQADCgUICAAAAA==.',
Es='Esael:BAAANQAECggIEAAAAA==.',
Ev='Eviscerated:BAAANQAECgQIBQAAAA==.',
Fa='Fail:BAAANQADCgYICwAAAA==.Falker:BAAANQAECgIIAgAAAA==.Fallen:BAAANQAECgcICgAAAA==.Fallingvoid:BAAANQAFFAQIAgAAAA==.Fancyfeet:BAAANQADCgIIAwABNQAECgYIBgATAAAAAA==.Fatchungus:BAAANQAECgQIBQABNQAECgYIBgATAAAAAA==.Fateesia:BAAANQAECgEIAQAAAA==.',
Fe='Feathersong:BAAANQADCggICwAAAA==.Fendru:BAAANQAECgUICgAAAA==.Fextardo:BAAANQAECgMIAgAAAA==.',
Fi='Finaliter:BAACNQAFFH8GAAIPAAMKhw4iDwDNAAAPAAMKhw4iDwDNAAA1AAQKfzcAAg8ACgpWHY5LALICAA8ACgpWHY5LALICAAAA.',
Fl='Flamingdrago:BAAANQAECgQIBQAAAA==.Fletchiana:BAAANQAECgEIAQAAAA==.Flexatronic:BAAANQAECgYIBgABNQAECgcIHwARALMJAA==.Flirtyflurry:BAAANQAECgQIBwAAAA==.Flurrybloom:BAAANQADCgYIBgAAAA==.',
Fo='Forsetie:BAAANQADCgMIAwAAAA==.Forsight:BAAANQADCgYIBgABNQAECggICQATAAAAAA==.Fox:BAACNQAFFH8OAAMaAAUKvBqNAQAxAQAaAAQK8hKNAQAxAQAZAAMKvBrhDgD8AAA1AAQKfzEAAxoACgo7IIoCAC8DABoACgpoHooCAC8DABkABwoaHnclAF8CAAAA.',
Fr='Freezerbúrnt:BAAANQAECgcIBwAAAA==.Fremder:BAAANQAECgUJBgAAAA==.Fresher:BAAANQAECgIIAgABNQAFFAcIDQABALMaAA==.Froggy:BAAANQAECggIEAAAAA==.Frogleap:BAAANQADCgUIBQABNQAECggIEAATAAAAAA==.Frogred:BAAANQADCgQIBAABNQAECggIEAATAAAAAA==.Frogtoad:BAAANQAECgUICwABNQAECggIEAATAAAAAA==.',
Fu='Funeral:BAACNQAFFH8iAAQiAAgKUBq/AAB6AQAiAAQKvRy/AAB6AQAEAAQKfBtsEgBqAQAjAAMKjQtUAwDCAAA1AAQKfzQABCIACgp5JXABAHoDACIACQqEJHABAHoDAAQACQoNJEQVAIECACMAAgoEJgIcAKAAAAAA.Furiousmoon:BAAANQADCggICAAAAA==.Futuresailor:BAAANQAECgUIBgAAAA==.',
Fy='Fyjhrt:BAABNQAECn8tAAIaAAkKpSJIAAAbAwAaAAkKpSJIAAAbAwAAAA==.',
Ga='Galladin:BAAANQAECgYICAABNQAECgIIAQATAAAAAA==.Gallory:BAAANQAECggIDgAAAA==.',
Gd='Gdk:BAAANQAECgMIBAABNQAECgoKOwAGAEUaAA==.Gdkdrake:BAAANQADCgUIBQABNQAECgoKOwAGAEUaAA==.Gdkhunter:BAAANQADCggICAABNQAECgoKOwAGAEUaAA==.Gdkmage:BAABNQAECn8dAAIRAAoKGg+zOwAEAgARAAoKGg+zOwAEAgABNQAECgoKOwAGAEUaAA==.Gdkman:BAABNQAECn87AAQGAAoKRRp+BgBrAgAGAAoKTBl+BgBrAgABAAgKyBiNTgA9AgAHAAIKlwjkCQFUAAAAAA==.Gdknotlock:BAAANQADCgQIBgABNQAECgoKOwAGAEUaAA==.',
Ge='Geoprince:BAAANQADCgcIEAAAAA==.Gerbon:BAAANQADCgMICAAAAA==.',
Gh='Ghaldrin:BAAANQABCggIEAAAAA==.Ghoulfriend:BAAANQADCgUICgAAAA==.',
Gi='Gigitty:BAAANQADCgYIBgAAAA==.Gimmedatneck:BAABNQAECn8fAAMZAAoKqB4lDAAmAwAZAAoKqB4lDAAmAwASAAQKSATKQQCrAAABNQAFFAcIDQABALMaAA==.Githrogathan:BAAANQAECgUIEgAAAA==.',
Go='Gokudin:BAAANQADCgUIBAAAAA==.Goldenrager:BAAANQADCgQIBAAAAA==.Gooseandmav:BAAANQADCgEIAQAAAA==.',
Gr='Grabetta:BAAANQADCgEIAQAAAA==.Graegor:BAAANQADCgUIBQAAAA==.Gragasfat:BAAANQAECgIIAgAAAA==.Groundnpound:BAAANQADCgUJBQAAAA==.',
Gy='Gyanall:BAAANQADCgMIAwAAAA==.',
['Gâ']='Gârrosh:BAAANQADCgYIBgABNQAECgoKRQADAI8PAA==.',
['Gö']='Gödhand:BAAANQAECgQICwAAAA==.',
Ha='Haeha:BAAANQADCgQIBAAAAA==.Haraldsson:BAAANQADCggICAAAAA==.Hargrumn:BAAANQABCgMIAgAAAA==.Harrypooc:BAAANQADCgQJBAAAAA==.Hasaro:BAACNQAFFH8IAAIkAAQKzwTqBQBhAAAkAAQKzwTqBQBhAAA1AAQKfzQAAiQACgoYEIgfAKEBACQACgoYEIgfAKEBAAAA.Hatcho:BAAANQADCgUICAAAAA==.Havokvacano:BAABNQAECn8cAAIPAAcKOQnVuwDjAAAPAAcKOQnVuwDjAAAAAA==.Havøckblaze:BAAANQADCgIIAgABNQADCgUIBAATAAAAAA==.',
He='Healmachine:BAAANQAECgMICwAAAA==.Hellbrringer:BAAANQAECgEIAQAAAA==.Helzer:BAAANQADCggIDwABNQAECgoKOwAGAKAcAA==.',
Ho='Holybaphomet:BAAANQADCgUICQAAAA==.Holyfarts:BAABNQAECn8/AAQhAAoKryJKAQBLAwAhAAoKgiBKAQBLAwAgAAgKNB9EMQCjAgAfAAoKQxjHDwDTAQAAAA==.Honeypaw:BAAANQADCgUIBQAAAA==.Hornedraven:BAAANQADCgEIAQAAAA==.',
Hu='Humanform:BAAANQADCgUIBQAAAA==.Hunbroll:BAAANQADCgYIBgABNQAFFAYIHwAbALkXAA==.Hungshaman:BAAANQABCgIIAgAAAA==.Hunterkiller:BAAANQADCggIGgAAAA==.',
Hx='Hx:BAAANQAECgQIBAAAAA==.',
Hy='Hypnoticpal:BAAANQAECggIDAAAAA==.Hythere:BAAANQAECgEIAQAAAA==.',
['Hõ']='Hõnor:BAABNQAECn9CAAMOAAoK8SM1EQDbAgAOAAoKqiM1EQDbAgAcAAUKJCJdFwC2AQABNQAFFAYIBwAWAF4hAA==.',
Ia='Iammoo:BAAANQAECgIIAgAAAA==.',
Ig='Igriss:BAABNQAECn8VAAIOAAkKeBIErgCqAQAOAAkKeBIErgCqAQAAAA==.',
Il='Illidanx:BAAANQADCgQIBAAAAA==.Illuminaughd:BAABNQAECn8WAAMYAAoKfREnGQA2AQAYAAcKtxQnGQA2AQAPAAMKGwyI5QCkAAAAAA==.Ilumii:BAAANQAECgMIAwAAAA==.Ilydris:BAAANQAECgUIBQAAAA==.',
Im='Imonthegcd:BAAANQAECgYIDQABNQAFFAYIBwAWAF4hAA==.',
In='Infinitepain:BAACNQAFFH8GAAIgAAIKXxLmHQCKAAAgAAIKXxLmHQCKAAA1AAQKfzkAAiAACgqLIhQGAIUDACAACgqLIhQGAIUDAAE1AAQKAggCABMAAAAA.Innodk:BAABNQAECn8nAAICAAoKCw6VHQCkAQACAAoKCw6VHQCkAQAAAA==.',
Ir='Irami:BAAANQAECgEIAQAAAA==.Iridellis:BAAANQADCgcIBwABNQAECgoKTAAXAIodAA==.',
Is='Ispankutank:BAAANQADCgEIAQAAAA==.',
It='Itslocotoo:BAAANQADCgEIAQAAAA==.',
Ja='Jabzert:BAAANQAECggICgABNQAECgoKOwAGAEUaAA==.Jahjahblinks:BAAANQADCgYIFAABNQAECgoKRQADAI8PAA==.Jave:BAAANQABCgQIBQAAAA==.Jaycers:BAABNQAECn8qAAIYAAoKEiEtCwDmAgAYAAoKEiEtCwDmAgAAAA==.Jayclark:BAAANQADCgEIAQAAAA==.',
Ji='Jimmypal:BAAANQAECgQIDwAAAA==.',
Jo='Joedingle:BAABNQAECn8vAAIRAAoKIB0iIgBwAgARAAoKIB0iIgBwAgAAAA==.Joemomma:BAAANQADCgUIBQAAAA==.Johnnyboi:BAAANQADCgEIAQAAAA==.Jokestarfist:BAABNQAECn8iAAIPAAgKzRelwwCVAQAPAAgKzRelwwCVAQAAAA==.',
Jr='Jr:BAAANQADCggICAAAAA==.',
Ka='Kaelar:BAAANQADCgMIAwABNQAECgoKQQAlAKIkAA==.Kaitokit:BAACNQAFFH8NAAMCAAUKThErDwCtAAACAAUKThErDwCtAAAmAAEKeQKlJQA1AAA1AAQKf00AAwIACgpmIO0HANMCAAIACgpmIO0HANMCACYACAo/EPNdAJgBAAAA.Kalia:BAAANQADCgIIAgAAAA==.Kalyth:BAABNQAECn8dAAIBAAkKswdiQABTAQABAAkKswdiQABTAQAAAA==.Kamera:BAABNQAECn8aAAQPAAkKLx0WdgBBAgAPAAgKLx0WdgBBAgAXAAMK9gWh/QCBAAAYAAEKAAAycgAtAAAAAA==.Kandessa:BAAANQADCgIIAwAAAA==.Kaylah:BAABNQAECn8xAAQaAAoKcyE3AwAGAwAaAAgKbCI3AwAGAwAZAAYKvh2yPwDOAQASAAQKvBwjRQBKAQAAAA==.Kayllina:BAABNQAECn8bAAIWAAYKjwKXgACpAAAWAAYKjwKXgACpAAAAAA==.Kayotic:BAAANQAECgIIBgAAAA==.',
Ke='Kelmorphic:BAABNQAECn85AAIVAAoKoiJMAgBkAwAVAAoKoiJMAgBkAwAAAA==.',
Ki='Killcommand:BAAANQADCggICAABNQAFFAQIEAARAAQXAA==.',
Kn='Knitemare:BAAANQABCgUIBwAAAA==.',
Ko='Kosmas:BAAANQAECgEJAQAAAA==.',
Kr='Krombear:BAAANQADCgIIAgAAAA==.',
Ku='Kudai:BAAANQAECgUIBgAAAA==.Kungpowchikn:BAAANQADCgIIAgAAAA==.Kurisuw:BAAANQAECgYICwAAAA==.Kurookami:BAAANQADCgEIAQAAAA==.Kuukwa:BAAANQAECgUICAAAAA==.',
Ky='Kyana:BAAANQAECgQIBQAAAA==.Kyarina:BAAANQABCggIEQAAAA==.',
['Kí']='Kíller:BAABNQAECn8ZAAMDAAcKlwkBygBtAQADAAcKlwkBygBtAQAMAAMKWwXiaQCGAAAAAA==.',
La='Lamadda:BAAANQADCgUIBQAAAA==.',
Ld='Ldg:BAAANQADCgQIBAAAAA==.',
Le='Leafdaddy:BAAANQAECgUICQABNQAECgoKMQALAPMdAA==.Leakoon:BAAANQADCggICAAAAA==.Lelise:BAABNQAECn8UAAIYAAgKzAGoXwBcAAAYAAgKzAGoXwBcAAAAAA==.Letusgiveita:BAAANQADCgQIBAAAAA==.',
Li='Lightbringr:BAAANQADCgYICwAAAA==.Lightingbolt:BAAANQADCgUICwAAAA==.Lightshields:BAAANQADCgIIAgAAAA==.Lilmissta:BAAANQADCgUIBQAAAA==.Lilpapi:BAAANQAECgcIBgABNQAFFAUIEAAkABwjAA==.Lilymei:BAAANQADCggIGAAAAA==.Linesondra:BAAANQADCgUICgAAAA==.Linissa:BAAANQAECgQIBgAAAA==.Littledude:BAAANQADCgYIBgAAAA==.Littlemorsel:BAABNQAECn8uAAIDAAoK3wxePgDpAQADAAoK3wxePgDpAQAAAA==.Livalifa:BAABNQAECn8eAAMDAAkKpQvfUgCkAQADAAkKpQvfUgCkAQAMAAMKQgNQcwBqAAAAAA==.',
Lo='Lockenload:BAAANQAECgYIDAAAAA==.Lockme:BAAANQADCgUIBQAAAA==.Lohhar:BAAANQADCggIFQAAAA==.Loser:BAAANQABCgQIBQAAAA==.Louthar:BAAANQAECggICAAAAA==.Lovin:BAAANQAECgQIBQAAAA==.',
Ls='Lselec:BAAANQAECgMJBQAAAA==.',
Lu='Lucens:BAABNQAECn8gAAIXAAgKXBABbgDOAQAXAAgKXBABbgDOAQAAAA==.Lucerna:BAAANQAFFAIIAgAAAA==.Lunarfall:BAAANQADCgYIBgAAAA==.Lurchaug:BAAANQAECggIAQAAAA==.Lurchdh:BAAANQADCgQJBAABNQAFFAMIBQAbAEQGAA==.Lurchdruid:BAAANQAECgIIAQABNQAFFAMIBQAbAEQGAA==.Lurchmage:BAACNQAFFH8FAAIbAAMKRAbvBACUAAAbAAMKRAbvBACUAAA1AAQKfx8AAxsACgp3EHoVAFUBABsACQp3EHoVAFUBABEABgoWBR9HARcBAAAA.Lurchn:BAABNQAECn90AAMbAAoKfBlcBADoAgAbAAoKfBlcBADoAgARAAkKowaj8ACpAQABNQAFFAMIBQAbAEQGAA==.',
Ly='Lyricai:BAAANQAECgUIDwAAAA==.',
['Lò']='Lòrdvader:BAAANQABCgEIAQAAAA==.',
Ma='Madjake:BAAANQADCggICAAAAA==.Magallanes:BAAANQAECgQIBAAAAA==.Mapleleaf:BAAANQAECgcIEgAAAA==.Markyy:BAACNQAFFH8HAAIPAAQKPCIhBwAaAQAPAAQKPCIhBwAaAQA1AAQKfzYABA8ACgqrJfgEANIDAA8ACgqrJfgEANIDABcABgqmDzyUAGMBABgAAQoAAHpgAFoAAAE1AAUUBggHABYAXiEA.Matas:BAAANQAECgcICwAAAA==.Maylinfenora:BAABNQAECn8fAAIZAAgKhQzGRwCmAQAZAAgKhQzGRwCmAQAAAA==.Mazzikane:BAAANQADCgYIBgAAAA==.',
Me='Meangry:BAAANQAECgIIAgAAAA==.Meowizenith:BAAANQADCgUIBQAAAA==.Merdazin:BAAANQAECgQIDAAAAA==.Metalhedface:BAABNQAECn8wAAMOAAoKohZ9MAAWAgAOAAoKfBV9MAAWAgAdAAEKvRifLgBHAAAAAA==.',
Mi='Mikecoxwall:BAAANQADCgEIAQAAAA==.Minisan:BAAANQADCgEIAQAAAA==.Misary:BAAANQAECgcICQAAAA==.Mistake:BAABNQAECn8WAAIOAAkKghBrnwDOAQAOAAkKghBrnwDOAQAAAA==.Mixjarnter:BAAANQADCggIDgAAAA==.',
Mo='Mogyar:BAABNQAECn8bAAIPAAcKBRassgC5AQAPAAcKBRassgC5AQAAAA==.Moistybush:BAAANQAECgEIAQAAAA==.Moltalgol:BAAANQAECgQICgAAAA==.Monkeli:BAABNQAECn8dAAIdAAcKkxViDQDhAQAdAAcKkxViDQDhAQAAAA==.Moocifer:BAAANQADCgcIDQAAAA==.Moocifermoo:BAAANQAECgEIAQAAAA==.Moogrim:BAAANQADCggIEAAAAA==.Moonsiand:BAEBNQAECn80AAIDAAgK3SDRIgAMAwADAAgK3SDRIgAMAwABNQAECgoKPgADAGIeAA==.Moreldwiddle:BAABNQAECn8YAAMjAAcKdBVzDwBYAQAjAAQKSB5zDwBYAQAEAAYK0RF6fAD+AAAAAA==.Morgaia:BAAANQAECgYIBQAAAA==.Morrigån:BAAANQADCgMIAwAAAA==.Motgus:BAABNQAECn8YAAQEAAgKhR6khQDYAQAEAAYKlR+khQDYAQAiAAIKZRxxRwCqAAAjAAIKVxvwHACWAAAAAA==.Mozzsticks:BAAANQADCgYICwAAAA==.',
Ms='Mshottie:BAAANQAECgcIBwAAAA==.',
Mx='Mx:BAAANQADCgYIDwAAAA==.',
My='Mystrialia:BAAANQABCgYIBgAAAA==.Mythlock:BAAANQADCgcIEwAAAA==.Mythranite:BAAANQADCgMIAwAAAA==.Myway:BAAANQADCggICAAAAA==.',
['Mó']='Mócha:BAABNQAECn8jAAMlAAcKPgkWFgDYAAAlAAcKPgkWFgDYAAAkAAEKAAByXwA2AAAAAA==.',
Na='Nardrian:BAAANQAECgQIBQAAAA==.Naydian:BAAANQAECgQIBAAAAA==.',
Ne='Necrozma:BAAANQAECggIBwAAAA==.Nekiron:BAAANQADCgQIBAAAAA==.Nellaa:BAAANQAECgcICAAAAA==.Nerrd:BAAANQAECgEIAQAAAA==.Nestaria:BAAANQADCggICAAAAA==.Netalanot:BAAANQADCgYIBgAAAA==.Nettik:BAAANQADCgUIBwAAAA==.Neverborn:BAABNQAECn8jAAIQAAcKnBAMMgAJAQAQAAcKnBAMMgAJAQAAAA==.',
Ni='Nightalucard:BAAANQADCgYIBgAAAA==.Nightrage:BAAANQAECgUIDgAAAA==.Nilex:BAAANQAECgcIEgAAAA==.',
No='Nomadic:BAAANQADCgIIAgAAAA==.Notmypally:BAAANQAECgUIBQABNQAFFAQICAARAAcRAA==.',
Nu='Numera:BAAANQADCgIIAwABNQAECggIDwATAAAAAA==.Nutellaqq:BAABNQAECn8YAAIRAAcK1xrQuwAMAgARAAcK1xrQuwAMAgAAAA==.',
['Nê']='Nêkê:BAABNQAFFH8MAAIBAAYKzBDSBQAsAQABAAYKzBDSBQAsAQAAAA==.',
Ob='Obeseotter:BAABNQAECn8uAAIRAAgK6ReXowA6AgARAAgK6ReXowA6AgAAAA==.Oborax:BAEBNQAECn8fAAIPAAgKchLJlgD2AQAPAAgKchLJlgD2AQABNQAECgoKPgADAGIeAA==.',
Od='Od:BAAANQAECgIIAgAAAA==.',
Ol='Oliviabenson:BAABNQAECn8nAAIRAAkKbx/vKQBLAgARAAkKbx/vKQBLAgAAAA==.',
Ox='Oxsidius:BAAANQAECgQICAAAAA==.',
Pa='Palady:BAAANQADCgEIAQAAAA==.Paldi:BAAANQAECgQIBAABNQAECgYIBgATAAAAAA==.Paliboos:BAAANQADCgYIBgAAAA==.Pallychri:BAAANQAECgYIBQAAAA==.Palulu:BAEANQAECggIDwAAAA==.Pandacub:BAAANQAECggICAAAAA==.Pariss:BAAANQAECgIIAgABNQAECgoKHwAHAMYQAA==.Paws:BAABNQAECn8aAAIQAAYKNwrmQgC5AAAQAAYKNwrmQgC5AAAAAA==.Pawse:BAAANQADCggIDwAAAA==.',
Pe='Peaky:BAABNQAECn8vAAQnAAkKbgkPIwBqAQAnAAkKbgkPIwBqAQALAAUKjQS5JQChAAAeAAIKNAGfbwArAAAAAA==.Perelia:BAABNQAECn8gAAIhAAcKrQ8QDAB6AQAhAAcKrQ8QDAB6AQAAAA==.',
Pl='Plondor:BAAANQABCgEIAQAAAA==.',
Po='Polarity:BAABNQAECn8aAAMfAAcKCwryQQAiAQAfAAcKCwryQQAiAQAgAAEKTwDGDgERAAAAAA==.Pooche:BAAANQAECgIIAwAAAA==.Popcola:BAAANQAECgQICQAAAA==.Pouts:BAAANQAECgQIBAABNQAFFAIICQATAAAAAA==.Powerpaladin:BAAANQABCgQIBAAAAA==.',
Pp='Ppc:BAAANQAFFAEIAgABNQAFFAQIEAARAAQXAA==.',
Pr='Prezu:BAEBNQAECn8VAAIIAAcKnA4NKgBfAQAIAAcKnA4NKgBfAQABNQAECggIDwATAAAAAA==.Procyonx:BAAANQAECgEIAQAAAA==.Prophofdoom:BAABNQAECn8mAAIcAAgKFCLpBgDyAgAcAAgKFCLpBgDyAgAAAA==.Prõc:BAAANQADCggICAAAAA==.',
Pu='Punchy:BAAANQABCgEIAQAAAA==.',
Pv='Pvc:BAACNQAFFH8QAAIRAAQKBBfCEwD8AAARAAQKBBfCEwD8AAA1AAQKfyEAAxEACgprIoxHAPQCABEACgprIoxHAPQCACgAAQqaAGAPACUAAAAA.',
Py='Pyrosong:BAAANQADCggICAAAAA==.',
Ra='Raisedead:BAAANQADCgIIAgABNQADCggIDAATAAAAAA==.Rancord:BAAANQADCggICAAAAA==.Rasmira:BAAANQADCggICAAAAA==.Rastaqwon:BAAANQAECgEIAQABNQAECgQIBQATAAAAAA==.Ratsmasher:BAAANQAECgIIAgAAAA==.Ravenight:BAAANQADCgMIAwAAAA==.Razed:BAAANQADCgYICwAAAA==.',
Re='Renoitukax:BAABNQAECn8nAAMgAAoKnR3yCwAkAwAgAAoKNhvyCwAkAwAhAAcKFh9KBgAuAgAAAA==.Restfuldark:BAAANQAECgYIBQAAAA==.Retrobution:BAABNQAECn8tAAIPAAoKLyDGJwAnAwAPAAoKLyDGJwAnAwAAAA==.Rezz:BAAANQAECgcIDAAAAA==.',
Rh='Rhohir:BAAANQABCgIIAgAAAA==.',
Ri='Riru:BAAANQAECgQIBwAAAA==.',
Ro='Rockstéady:BAAANQAECggIDAAAAA==.Roopall:BAABNQAECn8rAAIXAAoKByATDwBSAwAXAAoKByATDwBSAwAAAA==.Roxas:BAAANQADCgYIBgAAAA==.',
Ry='Rynzu:BAAANQAECgMIBAAAAA==.Ryzen:BAAANQAECgcIDQAAAA==.',
Sa='Sabelwin:BAAANQADCgEIAQAAAA==.Sanasrindis:BAAANQADCgQIAgAAAA==.Saninar:BAABNQAECn8mAAIYAAgKDQvHMgBMAQAYAAgKDQvHMgBMAQAAAA==.Sanshift:BAAANQAECgQIBAAAAA==.Satansimp:BAAANQAECgIIAgAAAA==.',
Sc='Schezmu:BAAANQAECgUICAAAAA==.',
Se='Sean:BAAANQADCgUICgAAAA==.Senorfiesta:BAABNQAECn8mAAImAAkK9hDuHACNAQAmAAkK9hDuHACNAQAAAA==.Serazarke:BAAANQAECgEIAQAAAA==.Setazen:BAAANQAECgEIAQAAAA==.',
Sh='Shadowjoker:BAAANQAECgEIAQAAAA==.Shaee:BAABNQAECn8dAAMFAAYKyxdZQQC1AQAFAAYKyxdZQQC1AQAUAAEKAADRdQAjAAAAAA==.Shamama:BAAANQADCgUIBQAAAA==.Shamans:BAAANQAECgUIDAAAAA==.Shambalaya:BAAANQAECgcIEAAAAA==.Shaokhan:BAABNQAECn8aAAMOAAgKIAcHlQDjAAAOAAcK0QYHlQDjAAAdAAIKxwnDIwAwAAAAAA==.Shasta:BAACNQAFFH8QAAIkAAUKHCNRAQAhAQAkAAUKHCNRAQAhAQA1AAQKfywAAiQACgrEJawBAMUDACQACgrEJawBAMUDAAAA.Shihthead:BAAANQADCgUIBQAAAA==.Shisuiuchiha:BAAANQADCgIIAgAAAA==.Shmorg:BAAANQADCgEIAQAAAA==.Shootumup:BAABNQAECn84AAMpAAkKUiRqAQBdAwApAAkKUiRqAQBdAwADAAEKZRcjSwFJAAAAAA==.Shromack:BAAANQADCgEIAQAAAA==.Shyx:BAABNQAECn83AAQgAAoKUyONFQAlAwAgAAoKUyONFQAlAwAfAAcKCw1nNQB4AQAhAAEKjRmbJQBBAAAAAA==.',
Si='Simplèjack:BAABNQAECn8fAAIRAAcKswnF/wCOAQARAAcKswnF/wCOAQAAAA==.Sinamon:BAAANQAECgQIDwAAAA==.Sinani:BAAANQADCgUJBQAAAA==.Sinnamon:BAAANQABCgQJBAABNQAECgQIDwATAAAAAA==.',
Sj='Sjdh:BAAANQADCgYIBgABNQAECgoKNAAOAIccAA==.',
Sk='Skar:BAAANQADCgUIBgAAAA==.Skram:BAAANQAECgUICAABNQAECgoKMwAPAJwNAA==.Skronker:BAAANQADCggIDQAAAA==.',
Sl='Slammydooker:BAABNQAECn8pAAMSAAoKnRfnGABWAgASAAoKnRfnGABWAgAZAAUKfw0RXwA5AQAAAA==.',
Sm='Smallkat:BAAANQAECgUIBQAAAA==.Smirksfotm:BAAANQAECgUICAABNQAECggIEAATAAAAAA==.Smoketail:BAAANQAECgUIBwAAAA==.',
Sn='Snail:BAAANQAECgYIBgAAAA==.Sneakmanman:BAAANQADCgYJCQAAAA==.',
So='Somberdh:BAAANQADCggICwAAAA==.Sorni:BAABNQAECn80AAMPAAgKogg6oQASAQAPAAgKogg6oQASAQAYAAIK7wK5awA7AAAAAA==.Soulglo:BAAANQAECgQIBAAAAA==.',
Sp='Spellslanger:BAAANQADCgQIBAAAAA==.Spikeprotein:BAAANQABCggICQAAAA==.Sprayandpray:BAABNQAECn8WAAIRAAoK8RurJABkAgARAAoK8RurJABkAgAAAA==.Spritey:BAAANQABCgIIAgAAAA==.',
Sq='Squidnips:BAAANQAECgEIAQAAAA==.',
St='Stareless:BAAANQADCgYIBgAAAA==.Statik:BAAANQAECgMIAwAAAA==.',
Su='Summondemons:BAAANQAECgIIBQAAAA==.Sumnèr:BAAANQADCgMIAwAAAA==.Sunpali:BAAANQAECgYICgAAAA==.Susanno:BAAANQADCgUJCwAAAA==.',
Sy='Sylauda:BAAANQADCgYICgAAAA==.Sylvians:BAAANQAECgEIAQAAAA==.',
Ta='Tacutacudark:BAAANQAECgUIDwAAAA==.Taintedbeef:BAAANQADCgEIAQABNQAECgYIDQATAAAAAA==.Talonflame:BAABNQAECn8qAAQMAAgKHxWVLwDQAQAMAAcKNhaVLwDQAQADAAMKEReXFgHWAAApAAIKiwqgCgCMAAAAAA==.Talonted:BAAANQAECgIIAgAAAA==.Tandallei:BAAANQAECgQIBAAAAA==.Tansu:BAAANQADCgcIDQAAAA==.Tarishi:BAAANQAECgUIBQAAAA==.Tarishii:BAAANQAECgUIBQAAAA==.Tateraid:BAAANQABCgYICQAAAA==.Taterpuff:BAAANQABCgUIBgAAAA==.Taupo:BAAANQAECgEIAgAAAA==.Taxidermy:BAAANQADCgYIDAAAAA==.',
Te='Telarinda:BAABNQAECn8WAAMEAAoK5QfHbQAiAQAEAAkKgwfHbQAiAQAiAAIKkAqnaQBOAAAAAA==.',
Th='Thametal:BAAANQAECgIIAgAAAA==.Thicclich:BAABNQAECn8aAAIWAAkKYQxPLwBqAQAWAAkKYQxPLwBqAQAAAA==.Thicktotem:BAAANQAECgEIAQAAAA==.Thickumz:BAAANQADCgQIBAAAAA==.Thinmint:BAAANQADCgcICQAAAA==.Thisismeta:BAAANQAECgYICgAAAA==.Thorynwar:BAACNQAFFH8YAAIOAAYKIB7GCQAXAgAOAAYKIB7GCQAXAgA1AAQKfzcAAg4ACgr5JcoDAF0DAA4ACgr5JcoDAF0DAAE1AAUUBQgNACYAIhQA.Thorýn:BAACNQAFFH8NAAMmAAUKIhR7DgAkAQAmAAQKIhR7DgAkAQACAAEKAABpKABXAAA1AAQKfyUAAyYACQpzJooQADMDACYACQpzJooQADMDAAIABwriGR9HAN0BAAAA.Thyrnoch:BAAANQAECgEIAQAAAA==.Thórin:BAAANQAECgYIDQAAAA==.',
Ti='Tierax:BAABNQAECn82AAMSAAoK2h85CQDiAgASAAkKpiA5CQDiAgAZAAMKNxhKdQDcAAAAAA==.Tipsy:BAABNQAECn8qAAIHAAoKWhE1ZQDdAQAHAAoKWhE1ZQDdAQAAAA==.',
To='Tojì:BAAANQAECggIEAAAAA==.Tonathul:BAAANQADCggIEAAAAA==.Torrk:BAAANQAECgQIBAAAAA==.Torultrear:BAAANQAECgIIAgAAAA==.Tot:BAABNQAECn8oAAIHAAoKEgwIfwCPAQAHAAoKEgwIfwCPAQAAAA==.',
Tr='Tralleth:BAABNQAECn8gAAMJAAgK0hoLDACZAQAJAAYKgBcLDACZAQAIAAcKog9xLABFAQAAAA==.Trallock:BAAANQADCggIFwAAAA==.Traumatized:BAAANQADCgUIBwAAAA==.Trecco:BAAANQABCgEIAQAAAA==.Truska:BAAANQABCgEIAQAAAA==.',
Ts='Tsoi:BAAANQAECggICAAAAA==.',
Tu='Tuskyrex:BAAANQAECgEIAQAAAA==.',
Tw='Twinklord:BAAANQAECggIDQAAAA==.Twostroke:BAABNQAECn8rAAIDAAoKUiTGBgCnAwADAAoKUiTGBgCnAwAAAA==.Twretwtwrewr:BAAANQADCgIIAgAAAA==.Twunkie:BAAANQADCgcIBwAAAA==.',
Ty='Tylopally:BAAANQAFFAIIAgAAAA==.Tyloremixdd:BAAANQAECgQIBAAAAA==.Tylototem:BAAANQAECgQIBAAAAA==.',
['Tö']='Tötem:BAAANQADCgMIAwABNQAFFAYIBwAWAF4hAA==.',
Uj='Ujcpet:BAAANQADCgYIBgAAAA==.',
Un='Uncookedham:BAAANQADCgYIEAAAAA==.Underhorn:BAAANQADCggIDgAAAA==.',
Va='Vaas:BAAANQADCggICAABNQAECgoKKgAYABIhAA==.Vaeelrundor:BAABNQAECn8fAAIDAAcKrwh2kAAQAQADAAcKrwh2kAAQAQAAAA==.Valyr:BAAANQADCgQIBAAAAA==.Vampslayer:BAAANQADCgYIBgAAAA==.Vanillaface:BAAANQAECggICQAAAA==.Vañillaface:BAAANQABCgQIBgAAAA==.',
Ve='Vedebone:BAAANQAECgUIDAAAAA==.Vedexd:BAABNQAECn8pAAIDAAcKrRDfoADEAQADAAcKrRDfoADEAQAAAA==.Velarael:BAABNQAECn8fAAIjAAcK0RBQCAAkAQAjAAcK0RBQCAAkAQAAAA==.Veletharia:BAAANQADCgQICAAAAA==.Velexi:BAAANQADCgQIBwAAAA==.',
Vh='Vheckxus:BAAANQAECgQICwAAAA==.',
Vi='Vivi:BAAANQAECgIIAgAAAA==.',
Vl='Vlidya:BAAANQADCgEIAQAAAA==.',
Vo='Voidberg:BAAANQAECgYICAAAAA==.',
Vs='Vs:BAAANQAECggIDgAAAA==.',
Wa='Wachonaso:BAACNQAFFH8JAAIEAAQKgQtjGgAjAQAEAAQKgQtjGgAjAQA1AAQKfykAAwQACgooHV0/AJQCAAQACgq0HF0/AJQCACIAAwokHcwwAAUBAAAA.Wastedsage:BAAANQAECgUICAAAAA==.Waterlou:BAAANQAECgIIAgAAAA==.',
We='Weavefang:BAAANQADCgUIBQAAAA==.',
Wh='Whatuphuz:BAAANQADCggIEAAAAA==.Wheresmyjaw:BAACNQAFFH8GAAIEAAIKWxqQEwCxAAAEAAIKWxqQEwCxAAA1AAQKfzYAAwQACgrYIdgPAKsCAAQACQrbIdgPAKsCACIAAwpDGF89AMwAAAAA.',
Wi='Wildthree:BAABNQAECn8hAAILAAgKFwzjCQA4AQALAAgKFwzjCQA4AQAAAA==.Wilkieswar:BAAANQADCggIGAABNQAECgoKLAARADgfAA==.Willenda:BAAANQAECgEIAgAAAA==.Winterfall:BAAANQADCggIJQAAAA==.',
Wu='Wuinn:BAACNQAFFH8PAAIIAAcKdgivCQCVAQAIAAcKdgivCQCVAQA1AAQKfykAAwgACgrBF44VAFsCAAgACgrBF44VAFsCAAkABwogEMwGAF0BAAAA.',
Xa='Xakutioner:BAABNQAECn85AAIQAAoKvB6bFAAiAwAQAAoKvB6bFAAiAwAAAA==.Xaldiir:BAABNQAECn8wAAIFAAoKMSJgBQAHAwAFAAoKMSJgBQAHAwAAAA==.',
Xe='Xenvoroo:BAAANQADCgIIAgAAAA==.Xerexia:BAABNQAECn9AAAIOAAkKDQ8RowDFAQAOAAkKDQ8RowDFAQAAAA==.',
Xs='Xsjàdo:BAAANQADCgYIBwAAAA==.',
Xw='Xwoo:BAAANQAECgIIAgAAAA==.',
Xz='Xzarlatan:BAAANQADCgIIAgAAAA==.Xzarlatanfi:BAAANQADCgUIBQAAAA==.',
Ya='Yahro:BAAANQAECgcIEQAAAA==.',
Ye='Yellowranger:BAABNQAECn88AAIXAAoKkx25DgDlAgAXAAoKkx25DgDlAgAAAA==.',
Yj='Yjn:BAABNQAECn8aAAILAAkKNQa0GgA5AQALAAkKNQa0GgA5AQAAAA==.',
Yo='Yongyong:BAABNQAECn8WAAMEAAYK9htmnACfAQAEAAYK9htmnACfAQAiAAEKAAA8bgBCAAAAAA==.Yotoymuerto:BAAANQAECgEIAQAAAA==.',
Yu='Yunara:BAAANQAECgYIBgAAAA==.Yustayoke:BAABNQAECn8mAAIRAAgKihQarwAkAgARAAgKihQarwAkAgAAAA==.',
Za='Zalvianna:BAAANQAECgUIBwAAAA==.Zarathoz:BAAANQABCgYJBgAAAA==.Zarshx:BAAANQADCgQICAABNQAECgYIBgATAAAAAA==.',
Ze='Zennithz:BAAANQAECggIEAAAAA==.Zeonz:BAAANQAECgEIAQAAAA==.',
Zh='Zhoya:BAAANQAECggICAAAAA==.',
Zi='Zilong:BAAANQAECgIIBAABNQAFFAcIDQAOADkTAA==.Zilongmage:BAAANQAECgcICAABNQAFFAcIDQAOADkTAA==.Zilongwar:BAACNQAFFH8NAAIOAAcKOROwCwD3AQAOAAcKOROwCwD3AQA1AAQKfyIAAg4ACgqAIq8sAAoDAA4ACgqAIq8sAAoDAAAA.',
Zo='Zombor:BAAANQADCgIIAgAAAA==.Zonecw:BAABNQAECn8ZAAMcAAkKSRY0FgDGAQAcAAgKSRY0FgDGAQAOAAEKAAAiUgE0AAAAAA==.Zonedk:BAAANQAECgQIBgABNQAECgkJGQAcAEkWAA==.',
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
