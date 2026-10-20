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

local lookup = {'Shaman-Elemental','Druid-Balance','Hunter-BeastMastery','Warlock-Demonology','DemonHunter-Havoc','Shaman-Enhancement','Shaman-Restoration','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster','Hunter-Marksmanship','Druid-Restoration','Warrior-Arms','Paladin-Retribution','Mage-Arcane','Rogue-Subtlety','Unknown-Unknown','DemonHunter-Devourer','DemonHunter-Vengeance','DeathKnight-Frost','Paladin-Holy','Rogue-Assassination','Rogue-Outlaw','DeathKnight-Blood','Mage-Frost','Warrior-Protection','Monk-Windwalker','Priest-Shadow','Priest-Holy','Warlock-Destruction','Warlock-Affliction','Druid-Guardian','Priest-Discipline','Paladin-Protection','Druid-Feral','DeathKnight-Unholy','Warrior-Fury','Monk-Mistweaver','Mage-Fire','Hunter-Survival',}
local provider = {region='US',realm='Nazjatar',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aanon:BAAANQAECgEIAQAAAA==.',
Ab='Aberoth:BAAANQADCgQIBAAAAA==.',
Ac='Accoli:BAAANQAECgUIBQAAAA==.Acslater:BAAANQADCgQIBAAAAA==.',
Ad='Adridan:BAAANQABCggIEwAAAA==.',
Ag='Agoobagoo:BAACNQAFFH8KAAIBAAMK+CBZFQAkAQABAAMK+CBZFQAkAQA1AAQKfxUAAgEACQpuHvEYADMDAAEACQpuHvEYADMDAAE1AAUUBQgQAAIA2RgA.',
Al='Aliasx:BAAANQAECgQIBAAAAA==.Alissaria:BAAANQAECgEIAQAAAA==.Allarus:BAAANQADCgcICQAAAA==.Allwrong:BAAANQADCgQIBAAAAA==.Alotofsin:BAAANQAECgEIAQAAAA==.Alphadog:BAEBNQAECn81AAIDAAkKdB90BQB4AgADAAkKdB90BQB4AgAAAA==.Alwaysunny:BAAANQADCgYIDAAAAA==.',
Am='Amahlfarouk:BAABNQAECn8cAAIEAAcKlxPsOAAgAQAEAAcKlxPsOAAgAQAAAA==.Aminatou:BAABNQAECn8lAAIFAAoK+hHoDwBsAQAFAAoK+hHoDwBsAQAAAA==.',
Ar='Ariaddne:BAABNQAECn8dAAQGAAgKThfKFQAMAgAGAAgKeBbKFQAMAgABAAYKbhMuswAsAQAHAAEKwRi6FAFAAAAAAA==.Artemîs:BAAANQAECgEIAQAAAA==.',
As='Ashaelra:BAAANQAECgUIBQAAAA==.Asolitha:BAAANQADCgUIBQAAAA==.',
Au='Augonly:BAABNQAFFH8JAAIIAAMKABPJEADdAAAIAAMKABPJEADdAAAAAA==.Augy:BAABNQAECn8mAAMJAAoKUxkgBwA+AgAJAAcK0hogBwA+AgAKAAkKrBZsFQD1AQAAAA==.',
Ba='Bakuretsu:BAABNQAECn8WAAILAAgK2iCIAAC2AgALAAgK2iCIAAC2AgABNQAECgoKLQALAEkbAA==.Barhead:BAAANQADCggIDgAAAA==.Barlow:BAABNQAECn8UAAIMAAgKgQIyGADGAAAMAAgKgQIyGADGAAAAAA==.',
Bb='Bbldrizzy:BAACNQAFFH8MAAIBAAYKixkoCQDcAQABAAYKixkoCQDcAQA1AAQKfykAAgEACgpPJLcRAGEDAAEACgpPJLcRAGEDAAAA.',
Be='Beastlieduke:BAAANQADCgYIDAABNQAECggIHQANAGUdAA==.Beastlièduke:BAAANQADCgIIAgABNQAECggIHQANAGUdAA==.Belephon:BAAANQAECgMIBQAAAA==.Belinda:BAAANQADCggIHQAAAA==.',
Bi='Bighunt:BAAANQAECgMIAwAAAA==.Bijju:BAAANQAECggIDAAAAA==.Binggus:BAABNQAECn8XAAIOAAgKyh1+VQCKAgAOAAgKyh1+VQCKAgAAAA==.',
Bl='Blabbybootze:BAABNQAECn8dAAIPAAcKFwMrKgHaAAAPAAcKFwMrKgHaAAAAAA==.Bladelight:BAAANQADCggIFAAAAA==.Blighte:BAAANQAECgQIBAABNQAECgoKKwACADogAA==.Blightfangs:BAABNQAECn8ZAAIQAAgKDxS8ygDwAQAQAAgKDxS8ygDwAQAAAA==.Bloodieelish:BAAANQAECgIIAQABNQAECggIFwARAJEOAA==.Bluzey:BAAANQADCgYIBgAAAA==.',
Bo='Bodakye:BAABNQAECn8dAAIDAAkKmxAjZwBGAgADAAkKmxAjZwBGAgAAAA==.Boneplague:BAAANQADCgQIBAAAAA==.Boow:BAAANQAECgUIBQAAAA==.',
Br='Bracalina:BAAANQAECgEIAQAAAA==.Brannix:BAAANQADCgUIBQAAAA==.Broggy:BAAANQADCgEIAQABNQAECgcICAASAAAAAA==.Brorgy:BAABNQAECn8ZAAMTAAYKqQiFRQAmAQATAAYKqQiFRQAmAQAUAAEKAADaOQAZAAABNQAECggIFwARAJEOAA==.Brovahkin:BAAANQABCggIEAAAAA==.',
Bu='Bubbapal:BAAANQADCgUIBwAAAA==.Bushntush:BAAANQADCggICQAAAA==.Buzzbuzz:BAAANQAECgMIBAAAAA==.',
By='Bywar:BAAANQADCgcICwAAAA==.',
['Bé']='Bébop:BAAANQAECggICAAAAA==.',
Ca='Caeruleus:BAAANQADCgQJBAAAAA==.Captyn:BAAANQABCgQIAwAAAA==.Catbum:BAAANQADCgIIAwAAAA==.Caylea:BAAANQADCggICAAAAA==.',
Ch='Chaosraven:BAABNQAECn8uAAIVAAoKsA5aPgDSAQAVAAoKsA5aPgDSAQAAAA==.Chapelgnome:BAAANQADCgUJBQABNQAECggIFwARAJEOAA==.Charlyne:BAAANQABCgMIAwAAAA==.Chewthymight:BAABNQAECn8pAAMPAAkKaRO3VAAbAQAPAAcKRxe3VAAbAQAWAAcKlQiMygDmAAAAAA==.Chickenslop:BAAANQADCggIHAAAAA==.Chiptime:BAAANQAECgUIDAAAAA==.Chloes:BAAANQAECgIIAgAAAA==.Chri:BAAANQAECgQIBwAAAA==.Chrri:BAAANQAECgIIAwAAAA==.Chungotron:BAABNQAFFH8HAAIPAAUKEgudDgBjAQAPAAUKEgudDgBjAQAAAA==.Chzburger:BAAANQABCgIIBAAAAA==.',
Cl='Cladon:BAAANQAECggICAAAAA==.Clairity:BAAANQADCgcIBwAAAA==.',
Co='Cocoon:BAAANQAECgQIBAABNQAFFAQIDAAQAKcTAA==.Conda:BAAANQAECggICgAAAA==.Cormogh:BAAANQAECgIIBAAAAA==.Cowhealer:BAABNQAECn8rAAMCAAoKOiA8BQD2AQACAAoKOiA8BQD2AQANAAMKGApLXACWAAAAAA==.',
Cr='Craeftig:BAABNQAECn8gAAMXAAoKGxi9AwABAgAXAAoKGxi9AwABAgAYAAEKowHIHwAWAAAAAA==.Craeftigdk:BAABNQAECn8dAAIZAAcKAQ7nWgCHAQAZAAcKAQ7nWgCHAQABNQAECgoKIAAXABsYAA==.Craeftigtwo:BAAANQADCggJDQABNQAECgoKIAAXABsYAA==.Craeftigwl:BAAANQAECgIIAgABNQAECgoKIAAXABsYAA==.Crepitus:BAABNQAECn8WAAMRAAYKEgzZLQBTAQARAAYKEgzZLQBTAQAXAAIKWQXrlQBdAAAAAA==.Crusabull:BAAANQADCgcIBwAAAA==.Cræftig:BAABNQAECn8bAAMaAAkKxRjGBwBvAgAaAAgKqxzGBwBvAgAQAAMKkwmJmQGTAAABNQAECgoKIAAXABsYAA==.',
Cu='Cuddlseraph:BAAANQAECgUIEgAAAA==.Cutestcc:BAAANQAECggICAAAAA==.',
Cy='Cynnithice:BAAANQADCgIIAgABNQAECgEIAQASAAAAAA==.',
Da='Daamdam:BAABNQAECn8ZAAIbAAgKjgPSLwC3AAAbAAgKjgPSLwC3AAAAAA==.Dafirenze:BAAANQADCggIDwAAAA==.Daftxshade:BAAANQAECgQIBAAAAA==.Dariian:BAAANQAECggIDgAAAA==.Darkbeef:BAABNQAECn8VAAIEAAYKDQOi9wDcAAAEAAYKDQOi9wDcAAAAAA==.Darkjusticeh:BAAANQAECgUIBwAAAA==.Darlang:BAAANQAECgUIBgAAAA==.Darthbjóurn:BAAANQAECgUIBQAAAA==.Darthsyde:BAABNQAECn8ZAAIZAAkK1A9vIgDvAAAZAAkK1A9vIgDvAAAAAA==.Dayanna:BAAANQADCgUIBQAAAA==.',
De='Deadergriff:BAAANQAECgUIDgAAAA==.Deadicated:BAABNQAECn8YAAIcAAcKvQg+OwA6AQAcAAcKvQg+OwA6AQAAAA==.Deadinsíde:BAAANQAECggICAABNQAECggIEAASAAAAAA==.Deathlyaura:BAAANQADCggICAABNQAECgUICAASAAAAAA==.Deathmark:BAAANQAECgUICAAAAA==.Deeznutzs:BAAANQAECgYIDgAAAA==.Defendaya:BAAANQAECggICAAAAA==.Delan:BAAANQAECgYIBwAAAA==.Demolishonn:BAAANQAECgUICAAAAA==.Desunaito:BAACNQAFFH8PAAIVAAcKfRX7AwDkAQAVAAcKfRX7AwDkAQA1AAQKfzUAAhUACgpGI8gLADkDABUACgpGI8gLADkDAAAA.Dexter:BAAANQAECgQIBQAAAA==.',
Dh='Dhzilong:BAAANQAECggIDAABNQAFFAcIDQAOADkTAA==.',
Di='Diddlefiddle:BAAANQADCgIIAgAAAA==.Dimeo:BAAANQADCgQIAQAAAA==.Dioji:BAAANQAECggIBgAAAA==.',
Dk='Dkzilong:BAAANQAECgIIBQABNQAFFAcIDQAOADkTAA==.',
Dm='Dmeo:BAAANQADCgMIAwAAAA==.',
Do='Docadoodle:BAAANQADCgcIBwABNQAECgoKKQATAPEXAA==.Docarcanis:BAAANQAECgYIBgABNQAECgoKKQATAPEXAA==.Docwyle:BAABNQAECn8pAAITAAoK8ReFGACYAgATAAoK8ReFGACYAgAAAA==.Doozey:BAAANQABCgcJBwAAAA==.',
Dr='Dracmary:BAAANQADCgUIBQAAAA==.Dracnogard:BAAANQAECgQICAAAAA==.Dracowulf:BAABNQAECn8aAAIDAAYKOgW93gBDAQADAAYKOgW93gBDAQAAAA==.Dragonbro:BAAANQAECgEIAQAAAA==.Dragonx:BAABNQAECn8hAAIDAAcKtwm7XQDwAAADAAcKtwm7XQDwAAAAAA==.Drakowolf:BAAANQAECgYIDwAAAA==.Drama:BAAANQAECgEIAQAAAA==.Dreadful:BAABNQAECn8/AAIWAAoKAx2UAwDCAgAWAAoKAx2UAwDCAgAAAA==.Dreorge:BAABNQAECn8XAAIIAAkKNBWxEwByAgAIAAkKNBWxEwByAgAAAA==.Drewceratops:BAABNQAECn8aAAIPAAkKVA+WnwDiAQAPAAkKVA+WnwDiAQAAAA==.Drewidd:BAAANQAECgUIBQABNQAECggIFwARAJEOAA==.Drimchi:BAAANQAECgEIAQAAAA==.Drimveil:BAABNQAECn8YAAIFAAkKPRgLLgA0AgAFAAkKPRgLLgA0AgAAAA==.Drogô:BAAANQAECgQICAAAAA==.Dromgar:BAAANQAECggIEAAAAA==.Dromkyr:BAABNQAECn8wAAMIAAoKnQ8eCQAwAQAIAAoKnQ8eCQAwAQAKAAEKNwtJPQAyAAAAAA==.Drossiechan:BAACNQAFFH8NAAIcAAUK7g1nBADUAAAcAAUK7g1nBADUAAA1AAQKfx8AAhwACgq8GbwZAHQCABwACgq8GbwZAHQCAAAA.',
Du='Duellipa:BAABNQAECn8XAAMRAAgKkQ5GEQBMAQARAAcK7g9GEQBMAQAXAAQKwwajewDEAAAAAA==.',
Dy='Dysian:BAAANQADCgQIBQAAAA==.Dywanw:BAAANQABCgYIBgAAAA==.',
Ed='Edward:BAAANQAECggJBwAAAA==.',
Ef='Effloria:BAABNQAECn8vAAINAAoKnCNkAwCSAwANAAoKnCNkAwCSAwAAAA==.',
Ek='Ekim:BAAANQADCgQIAwAAAA==.Eklyps:BAAANQADCgYIBgAAAA==.',
El='Elauvia:BAAANQAECgUICAAAAA==.Elegia:BAAANQAECggIDgAAAA==.',
Em='Emleah:BAAANQAECgQIBwAAAA==.Emmaina:BAAANQAECgIIAgAAAA==.',
En='Enash:BAAANQADCgQIBAAAAA==.Encoredh:BAAANQAECgQIBAABNQAECgcIHAAdAAYXAA==.Encoredk:BAAANQADCgIIAgAAAA==.Encoree:BAAANQADCgcIBwABNQAECgcIHAAdAAYXAA==.Encoremts:BAAANQAECgEIAQABNQAECgcIHAAdAAYXAA==.Encorep:BAABNQAECn8cAAMdAAcKBhfhJQAAAgAdAAcKBhfhJQAAAgAeAAIKiw0n7QBdAAAAAA==.Enris:BAAANQADCgUICAAAAA==.',
Es='Esael:BAAANQAECggIEAAAAA==.',
Ev='Eviscerated:BAAANQAECgQIBQAAAA==.',
Fa='Fail:BAAANQADCgYICwAAAA==.Falker:BAAANQAECgIIAgAAAA==.Fallen:BAAANQAECgcICgAAAA==.Fallingvoid:BAAANQAFFAIIAgAAAA==.Fancyfeet:BAAANQADCgIIAwABNQAECgYIBgASAAAAAA==.Fatchungus:BAAANQAECgQIBQABNQAECgYIBgASAAAAAA==.Fateesia:BAAANQAECgEIAQAAAA==.',
Fe='Feathersong:BAAANQADCggICwAAAA==.Fendru:BAAANQAECgMIAwAAAA==.Fextardo:BAAANQAECgEIAQAAAA==.',
Fi='Finaliter:BAACNQAFFH8FAAIPAAIKvBDdDwCMAAAPAAIKvBDdDwCMAAA1AAQKfzEAAg8ACgqfHI5LALICAA8ACgqfHI5LALICAAAA.',
Fl='Flamingdrago:BAAANQAECgQIBQAAAA==.Flirtyflurry:BAAANQAECgQIBwAAAA==.',
Fo='Forsight:BAAANQADCgYIBgABNQAECgMIBgASAAAAAA==.Fox:BAACNQAFFH8OAAMYAAUKvBqNAQAxAQAYAAQK8hKNAQAxAQAXAAMKvBrhDgD8AAA1AAQKfzEAAxgACgo7IIoCAC8DABgACgpoHooCAC8DABcABwoaHnclAF8CAAAA.',
Fr='Fremder:BAAANQAECgUJBgAAAA==.Fresher:BAAANQAECgIIAgABNQAFFAYIDAABAIsZAA==.Froggy:BAAANQAECggIEAAAAA==.Frogleap:BAAANQADCgUIBQABNQAECggIEAASAAAAAA==.Frogred:BAAANQADCgQIBAABNQAECggIEAASAAAAAA==.Frogtoad:BAAANQAECgQICAABNQAECggIEAASAAAAAA==.',
Fu='Funeral:BAACNQAFFH8gAAQfAAcKah+/AAB6AQAfAAQKvRy/AAB6AQAEAAQKfBtsEgBqAQAgAAIKThZUAwDCAAA1AAQKfysABB8ACgqeJHABAHoDAB8ACQqEJHABAHoDAAQABwpSI/FgADUCACAAAgoEJgIcAKAAAAAA.Furiousmoon:BAAANQADCggICAAAAA==.Futuresailor:BAAANQAECgUIBgAAAA==.',
Fy='Fyjhrt:BAABNQAECn8kAAIYAAgKjCLuBACvAgAYAAgKjCLuBACvAgAAAA==.',
Ga='Galladin:BAAANQAECgYICAABNQAECgIIAQASAAAAAA==.Gallory:BAAANQAECggIDgAAAA==.',
Gd='Gdk:BAAANQAECgMIBAABNQAECgoKMAAGANoYAA==.Gdkdrake:BAAANQADCgUIBQABNQAECgoKMAAGANoYAA==.Gdkhunter:BAAANQADCggICAABNQAECgoKMAAGANoYAA==.Gdkmage:BAAANQAECgcIDwABNQAECgoKMAAGANoYAA==.Gdkman:BAABNQAECn8wAAQGAAoK2hgJCAB1AQABAAgKyBiNTgA9AgAGAAkKCxcJCAB1AQAHAAIKlwjkCQFUAAAAAA==.Gdknotlock:BAAANQADCgQIBgABNQAECgoKMAAGANoYAA==.',
Ge='Geoprince:BAAANQADCgcIEAAAAA==.Gerbon:BAAANQADCgMICAAAAA==.',
Gh='Ghaldrin:BAAANQABCggIEAAAAA==.Ghoulfriend:BAAANQADCgUICgAAAA==.',
Gi='Gigitty:BAAANQADCgYIBgAAAA==.Gimmedatneck:BAABNQAECn8fAAMXAAoKqB4lDAAmAwAXAAoKqB4lDAAmAwARAAQKSATKQQCrAAABNQAFFAYIDAABAIsZAA==.Githrogathan:BAAANQAECgUIDgAAAA==.',
Go='Gokudin:BAAANQADCgUIBAAAAA==.Goldenrager:BAAANQADCgQIBAAAAA==.Gooseandmav:BAAANQADCgEIAQAAAA==.',
Gr='Grabetta:BAAANQADCgEIAQAAAA==.Graegor:BAAANQADCgUIBQAAAA==.Gragasfat:BAAANQAECgIIAgAAAA==.Groundnpound:BAAANQADCgUJBQAAAA==.',
Gy='Gyanall:BAAANQADCgMIAwAAAA==.',
['Gâ']='Gârrosh:BAAANQADCgYIBgABNQAECgoKPAADAOAOAA==.',
['Gö']='Gödhand:BAAANQAECgQICwAAAA==.',
Ha='Haeha:BAAANQADCgQIBAAAAA==.Haraldsson:BAAANQADCggICAAAAA==.Hargrumn:BAAANQABCgMIAgAAAA==.Harrypooc:BAAANQADCgQJBAAAAA==.Hasaro:BAACNQAFFH8HAAIhAAMKzwQABABlAAAhAAMKzwQABABlAAA1AAQKfzAAAiEACgp3DYgfAKEBACEACgp3DYgfAKEBAAAA.Hatcho:BAAANQADCgUICAAAAA==.Havokvacano:BAABNQAECn8VAAIPAAYKuwqX9wAuAQAPAAYKuwqX9wAuAQAAAA==.Havøckblaze:BAAANQADCgIIAgABNQADCgUIBAASAAAAAA==.',
He='Healmachine:BAAANQAECgMICAAAAA==.Hellbrringer:BAAANQAECgEIAQAAAA==.Helzer:BAAANQADCggIDwABNQAECgoKMQAHAIkXAA==.',
Ho='Holybaphomet:BAAANQADCgUICQAAAA==.Holyfarts:BAABNQAECn82AAQiAAoKFCJKAQBLAwAiAAoKViBKAQBLAwAeAAgKqh5EMQCjAgAdAAgK8hNRKwDNAQAAAA==.Honeypaw:BAAANQADCgUIBQAAAA==.Hornedraven:BAAANQADCgEIAQAAAA==.',
Hu='Humanform:BAAANQADCgUIBQAAAA==.Hunbroll:BAAANQADCgYIBgABNQAFFAYIGQAaAOYVAA==.Hungshaman:BAAANQABCgIIAgAAAA==.Hunterkiller:BAAANQADCggIGgAAAA==.',
Hx='Hx:BAAANQAECgQIBAAAAA==.',
Hy='Hypnoticpal:BAAANQAECggIDAAAAA==.Hythere:BAAANQAECgEIAQAAAA==.',
['Hõ']='Hõnor:BAABNQAECn82AAMOAAoKPR/wHQBAAwAOAAoK6B3wHQBAAwAbAAUKJCJdFwC2AQABNQAFFAUIBgAVAE0gAA==.',
Ia='Iammoo:BAAANQAECgIIAgAAAA==.',
Ig='Igriss:BAABNQAECn8VAAIOAAkKeBIErgCqAQAOAAkKeBIErgCqAQAAAA==.',
Il='Illidanx:BAAANQADCgQIBAAAAA==.Illuminaughd:BAAANQAECgQICQAAAA==.Ilumii:BAAANQAECgMIAwAAAA==.Ilydris:BAAANQAECgEIAQAAAA==.',
Im='Imonthegcd:BAAANQAECgYIDQABNQAFFAUIBgAVAE0gAA==.',
In='Infinitepain:BAABNQAECn8vAAIeAAoKySBmFQAmAwAeAAoKySBmFQAmAwABNQAECgIIAgASAAAAAA==.Innodk:BAABNQAECn8bAAIZAAgKTg06HgAGAQAZAAgKTg06HgAGAQAAAA==.',
Ir='Irami:BAAANQAECgEIAQAAAA==.Iridellis:BAAANQADCgcIBwABNQAECgoKPwAWAAMdAA==.',
Is='Ispankutank:BAAANQADCgEIAQAAAA==.',
It='Itslocotoo:BAAANQADCgEIAQAAAA==.',
Ja='Jabzert:BAAANQAECggICAABNQAECgoKMAAGANoYAA==.Jahjahblinks:BAAANQADCgYIFAABNQAECgoKPAADAOAOAA==.Jave:BAAANQABCgQIBQAAAA==.Jaycers:BAABNQAECn8iAAIjAAoKMR8tCwDmAgAjAAoKMR8tCwDmAgAAAA==.Jayclark:BAAANQADCgEIAQAAAA==.',
Ji='Jimmypal:BAAANQAECgQICwAAAA==.',
Jo='Joedingle:BAABNQAECn8kAAIQAAcKNCAoNwBQAQAQAAcKNCAoNwBQAQAAAA==.Joemomma:BAAANQADCgUIBQAAAA==.Johnnyboi:BAAANQADCgEIAQAAAA==.Jokestarfist:BAABNQAECn8aAAIPAAcKmROlwwCVAQAPAAcKmROlwwCVAQAAAA==.',
Jr='Jr:BAAANQADCggICAAAAA==.',
Ju='Jumpy:BAAANQABCgMIAwAAAA==.',
Ka='Kaelar:BAAANQADCgMIAwABNQAECgoKOAAkAGckAA==.Kaitokit:BAACNQAFFH8JAAMZAAUKDRDkGgDDAAAZAAUKDRDkGgDDAAAlAAEKeQKlJQA1AAA1AAQKf0MAAxkACgr2Hw0OAD8DABkACgr2Hw0OAD8DACUACAo/EPNdAJgBAAAA.Kalia:BAAANQADCgIIAgAAAA==.Kalyth:BAABNQAECn8UAAIBAAgK9QYSnwBZAQABAAgK9QYSnwBZAQAAAA==.Kamera:BAABNQAECn8aAAQPAAkKLx0WdgBBAgAPAAgKLx0WdgBBAgAWAAMK9gWh/QCBAAAjAAEKAAAycgAtAAAAAA==.Kandessa:BAAANQADCgIIAwAAAA==.Kaylah:BAABNQAECn8tAAQYAAkKFSKFAAAAAgAYAAgKbCKFAAAAAgAXAAYKvh2yPwDOAQARAAEKBiAcPwBgAAAAAA==.Kayllina:BAABNQAECn8YAAIVAAYKjwKXgACpAAAVAAYKjwKXgACpAAAAAA==.Kayotic:BAAANQAECgIIBgAAAA==.',
Ke='Kelmorphic:BAABNQAECn8vAAIUAAoKkiBMAgBkAwAUAAoKkiBMAgBkAwAAAA==.',
Ki='Killcommand:BAAANQADCggICAABNQAFFAQIDAAQAKcTAA==.',
Kn='Knitemare:BAAANQABCgUIBwAAAA==.',
Ko='Kosmas:BAAANQAECgEJAQAAAA==.',
Kr='Krombear:BAAANQADCgIIAgAAAA==.',
Ku='Kudai:BAAANQAECgQIBgAAAA==.Kungpowchikn:BAAANQADCgIIAgAAAA==.Kurisuw:BAAANQAECgYICgAAAA==.Kurookami:BAAANQADCgEIAQAAAA==.Kuukwa:BAAANQAECgUICAAAAA==.',
Ky='Kyana:BAAANQAECgIIAwAAAA==.Kyarina:BAAANQABCggIEQAAAA==.',
['Kí']='Kíller:BAAANQAECgUIEQAAAA==.',
La='Lamadda:BAAANQADCgUIBQAAAA==.',
Ld='Ldg:BAAANQADCgQIBAAAAA==.',
Le='Leafdaddy:BAAANQAECgUICQABNQAECgoKLQALAFMaAA==.Leakoon:BAAANQADCggICAAAAA==.Lelise:BAABNQAECn8UAAIjAAgKzAGoXwBcAAAjAAgKzAGoXwBcAAAAAA==.Letusgiveita:BAAANQADCgQIBAAAAA==.',
Li='Lightbringr:BAAANQADCgYICwAAAA==.Lightingbolt:BAAANQADCgUICwAAAA==.Lightshields:BAAANQADCgIIAgAAAA==.Lilpapi:BAAANQAECgcIBgABNQAFFAUIDQAhABwjAA==.Lilymei:BAAANQADCggIGAAAAA==.Linesondra:BAAANQADCgUICgAAAA==.Linissa:BAAANQAECgQIBgAAAA==.Littledude:BAAANQADCgYIBgAAAA==.Littlemorsel:BAABNQAECn8kAAIDAAkKtwz3gAAKAgADAAkKtwz3gAAKAgAAAA==.Livalifa:BAABNQAECn8XAAMDAAkKVwpxHgCeAQADAAkKVwpxHgCeAQAMAAMKQgNQcwBqAAAAAA==.',
Lo='Lockenload:BAAANQAECgYIDAAAAA==.Lockme:BAAANQADCgUIBQAAAA==.Lohhar:BAAANQADCggIFAAAAA==.Loser:BAAANQABCgQIBQAAAA==.Louthar:BAAANQAECggICAAAAA==.',
Ls='Lselec:BAAANQAECgMJBQAAAA==.',
Lu='Lucens:BAABNQAECn8gAAIWAAgKXBABbgDOAQAWAAgKXBABbgDOAQAAAA==.Lucerna:BAAANQAECgUICQAAAA==.Lurchdh:BAAANQADCgQJBAABNQAECgoKbAAaAHwZAA==.Lurchdruid:BAAANQAECgIIAQABNQAECgoKbAAaAHwZAA==.Lurchmage:BAABNQAECn8bAAMaAAoK3g/fBwAUAQAQAAYKFgUfRwEXAQAaAAkK3g/fBwAUAQABNQAECgoKbAAaAHwZAA==.Lurchn:BAABNQAECn9sAAMaAAoKfBl8AQAGAgAaAAoKfBl8AQAGAgAQAAkKowaj8ACpAQAAAA==.',
Ly='Lyricai:BAAANQAECgUIDwABNQAECgcIHQAHAAcdAA==.',
Ma='Madjake:BAAANQADCggICAAAAA==.Magallanes:BAAANQAECgQIBAAAAA==.Mapleleaf:BAAANQAECgcIDQAAAA==.Markyy:BAACNQAFFH8GAAIPAAMKPCJzAwAtAQAPAAMKPCJzAwAtAQA1AAQKfy4ABA8ACgpMJfgEANIDAA8ACgpMJfgEANIDABYABgqmDzyUAGMBACMAAQoAAHpgAFoAAAE1AAUUBQgGABUATSAA.Matas:BAAANQAECgYICgAAAA==.Maylinfenora:BAABNQAECn8fAAIXAAgKhQzGRwCmAQAXAAgKhQzGRwCmAQAAAA==.Mazzikane:BAAANQADCgYIBgAAAA==.',
Me='Meangry:BAAANQADCgEIAQAAAA==.Meowizenith:BAAANQADCgUIBQAAAA==.Merdazin:BAAANQAECgQIDAAAAA==.Metalhedface:BAABNQAECn8mAAMOAAoKSxJ7hQAOAgAOAAoK4hB7hQAOAgAmAAEKvRifLgBHAAAAAA==.',
Mi='Mikecoxwall:BAAANQADCgEIAQAAAA==.Minisan:BAAANQADCgEIAQAAAA==.Misary:BAAANQAECgIIAgAAAA==.Mistake:BAAANQAECgcIEQAAAA==.Mixjarnter:BAAANQADCggIDgAAAA==.',
Mo='Mogyar:BAABNQAECn8bAAIPAAcKBRassgC5AQAPAAcKBRassgC5AQAAAA==.Moistybush:BAAANQAECgEIAQAAAA==.Moltalgol:BAAANQAECgQICgAAAA==.Monkeli:BAABNQAECn8dAAImAAcKkxViDQDhAQAmAAcKkxViDQDhAQAAAA==.Moocifer:BAAANQADCgcIDQAAAA==.Moocifermoo:BAAANQAECgEIAQAAAA==.Moogrim:BAAANQADCggIEAAAAA==.Moonsiand:BAEBNQAECn8tAAIDAAgK3SDRIgAMAwADAAgK3SDRIgAMAwABNQAECgkJNQADAHQfAA==.Moreldwiddle:BAABNQAECn8XAAMgAAYKbxhzDwBYAQAgAAQKSB5zDwBYAQAEAAUK4hNfVADaAAAAAA==.Morgaia:BAAANQAECgUIBQAAAA==.Morrigån:BAAANQADCgMIAwAAAA==.Motgus:BAABNQAECn8YAAQEAAgKhR6khQDYAQAEAAYKlR+khQDYAQAfAAIKZRxxRwCqAAAgAAIKVxvwHACWAAAAAA==.Mozzsticks:BAAANQADCgYICwAAAA==.',
Ms='Mshottie:BAAANQAECgEIAQAAAA==.',
Mx='Mx:BAAANQADCgYIDwAAAA==.',
My='Mystrialia:BAAANQABCgYIBgAAAA==.Mythlock:BAAANQADCgcIEwAAAA==.Mythranite:BAAANQADCgMIAwAAAA==.Myway:BAAANQADCggICAAAAA==.',
['Mó']='Mócha:BAABNQAECn8dAAMkAAYK3giDDgC+AAAkAAYK3giDDgC+AAAhAAEKAAByXwA2AAAAAA==.',
Na='Nardrian:BAAANQAECgQIBQAAAA==.Naydian:BAAANQAECgQIBAAAAA==.',
Ne='Nekiron:BAAANQADCgQIBAAAAA==.Nellaa:BAAANQAECgcICAAAAA==.Nerrd:BAAANQAECgEIAQAAAA==.Nestaria:BAAANQADCggICAAAAA==.Netalanot:BAAANQADCgYIBgAAAA==.Nettik:BAAANQADCgUIBwAAAA==.Neverborn:BAABNQAECn8jAAICAAcKnBAkFgAsAQACAAcKnBAkFgAsAQAAAA==.',
Ni='Nightrage:BAAANQAECgQICgAAAA==.Nilex:BAAANQAECgcIDQAAAA==.',
No='Nomadic:BAAANQADCgIIAgAAAA==.Notmypally:BAAANQAECgUIBQABNQAFFAQIBQAQAKQLAA==.',
Nu='Numera:BAAANQADCgIIAwABNQAECggIDgASAAAAAA==.Nutellaqq:BAABNQAECn8YAAIQAAcK1xrQuwAMAgAQAAcK1xrQuwAMAgAAAA==.',
['Nê']='Nêkê:BAABNQAFFH8MAAIBAAYKzBACAwBBAQABAAYKzBACAwBBAQAAAA==.',
Ob='Obeseotter:BAABNQAECn8uAAIQAAgK6ReXowA6AgAQAAgK6ReXowA6AgAAAA==.Oborax:BAEBNQAECn8YAAIPAAgK3xHJlgD2AQAPAAgK3xHJlgD2AQABNQAECgkJNQADAHQfAA==.',
Od='Od:BAAANQAECgIIAgAAAA==.',
Ol='Oliviabenson:BAABNQAECn8fAAIQAAkKfxs5JgB9AQAQAAkKfxs5JgB9AQAAAA==.',
Ox='Oxsidius:BAAANQAECgQICAAAAA==.',
Pa='Palady:BAAANQADCgEIAQAAAA==.Paldi:BAAANQAECgQIBAABNQAECgYIBgASAAAAAA==.Paliboos:BAAANQADCgYIBgAAAA==.Palulu:BAEANQAECggIDwAAAA==.Pandacub:BAAANQAECggICAAAAA==.Pariss:BAAANQADCgUIBQABNQAECgoKGQABAB4KAA==.Paws:BAABNQAECn8VAAICAAYKOAnsaAAoAQACAAYKOAnsaAAoAQAAAA==.Pawse:BAAANQADCggIDwAAAA==.',
Pe='Peaky:BAABNQAECn8tAAQnAAkKVwkPIwBqAQAnAAkKVwkPIwBqAQALAAUKjQRAEABjAAAcAAIKNAGfbwArAAAAAA==.Perelia:BAABNQAECn8gAAIiAAcKrQ8QDAB6AQAiAAcKrQ8QDAB6AQAAAA==.',
Pl='Plondor:BAAANQABCgEIAQAAAA==.',
Po='Polarity:BAABNQAECn8ZAAMdAAYKJAyQGwCtAAAdAAYKJAyQGwCtAAAeAAEKTwDGDgERAAAAAA==.Pooche:BAAANQAECgIIAwAAAA==.Popcola:BAAANQAECgQICQAAAA==.Pouts:BAAANQAECgQIBAABNQAFFAIICAASAAAAAA==.Powerpaladin:BAAANQABCgQIBAAAAA==.',
Pp='Ppc:BAAANQAECgQIBwABNQAFFAQIDAAQAKcTAA==.',
Pr='Prezu:BAEBNQAECn8VAAIIAAcKnA4NKgBfAQAIAAcKnA4NKgBfAQABNQAECggIDwASAAAAAA==.Procyonx:BAAANQAECgEIAQAAAA==.Prophofdoom:BAABNQAECn8kAAIbAAgKxCEUAgD/AQAbAAgKxCEUAgD/AQAAAA==.Prõc:BAAANQADCggICAAAAA==.',
Pv='Pvc:BAACNQAFFH8MAAIQAAQKpxNODgDrAAAQAAQKpxNODgDrAAA1AAQKfyAAAxAACgrQH4xHAPQCABAACgrQH4xHAPQCACgAAQqaAGAPACUAAAAA.',
Ra='Raisedead:BAAANQADCgIIAgABNQADCggIDAASAAAAAA==.Rancord:BAAANQADCggICAAAAA==.Rasmira:BAAANQADCggICAAAAA==.Rastaqwon:BAAANQAECgEIAQAAAA==.Ratsmasher:BAAANQAECgIIAgAAAA==.Razed:BAAANQADCgYICwAAAA==.',
Re='Renoitukax:BAAANQAECgYIEAAAAA==.Restfuldark:BAAANQADCggIDwAAAA==.Retrobution:BAABNQAECn8kAAIPAAoKMB/GJwAnAwAPAAoKMB/GJwAnAwAAAA==.Rezz:BAAANQAECgcIDAAAAA==.',
Rh='Rhohir:BAAANQABCgIIAgAAAA==.',
Ri='Riru:BAAANQAECgQIBwAAAA==.',
Ro='Rockstéady:BAAANQAECggICAAAAA==.Roopall:BAABNQAECn8mAAIWAAoKvh8TDwBSAwAWAAoKvh8TDwBSAwAAAA==.',
Ry='Rynzu:BAAANQAECgMIBAAAAA==.Ryzen:BAAANQAECgcIDQAAAA==.',
Sa='Sabelwin:BAAANQADCgEIAQAAAA==.Sanasrindis:BAAANQADCgQIAgAAAA==.Saninar:BAABNQAECn8mAAIjAAgKDQvHMgBMAQAjAAgKDQvHMgBMAQAAAA==.Sanshift:BAAANQAECgQIBAAAAA==.Satansimp:BAAANQAECgIIAgAAAA==.',
Sc='Schezmu:BAAANQAECgUICAAAAA==.',
Se='Sean:BAAANQADCgUICgAAAA==.Senorfiesta:BAABNQAECn8eAAIlAAcKRhTdEQBOAQAlAAcKRhTdEQBOAQAAAA==.Serazarke:BAAANQADCggICAAAAA==.Setazen:BAAANQAECgEIAQAAAA==.',
Sh='Shadowjoker:BAAANQAECgEIAQAAAA==.Shaee:BAABNQAECn8dAAMFAAYKyxdZQQC1AQAFAAYKyxdZQQC1AQATAAEKAADRdQAjAAAAAA==.Shamama:BAAANQADCgUIBQAAAA==.Shamans:BAAANQAECgUICAAAAA==.Shambalaya:BAAANQAECgUICQAAAA==.Shaokhan:BAABNQAECn8XAAMOAAgK0QYBYQDWAAAOAAcK0QYBYQDWAAAmAAEKAAD7NgArAAAAAA==.Shasta:BAACNQAFFH8NAAIhAAUKHCO9AAAuAQAhAAUKHCO9AAAuAQA1AAQKfygAAiEACgoTJawBAMUDACEACgoTJawBAMUDAAAA.Shihthead:BAAANQADCgUIBQAAAA==.Shisuiuchiha:BAAANQADCgIIAgAAAA==.Shmorg:BAAANQADCgEIAQAAAA==.Shootumup:BAABNQAECn83AAMpAAkKUiQ2AADVAgApAAkKUiQ2AADVAgADAAEKZRcjSwFJAAAAAA==.Shyx:BAABNQAECn8zAAQeAAoKUyMOCgBDAgAeAAoKUyMOCgBDAgAdAAcKCw1nNQB4AQAiAAEKjRmbJQBBAAAAAA==.',
Si='Simplèjack:BAABNQAECn8fAAIQAAcKswnF/wCOAQAQAAcKswnF/wCOAQAAAA==.Sinamon:BAAANQAECgUICwAAAA==.Sinani:BAAANQADCgUJBQAAAA==.Sinnamon:BAAANQABCgQJBAABNQAECgUICwASAAAAAA==.',
Sj='Sjdh:BAAANQADCgYIBgABNQAECgoKMgAOAA8aAA==.',
Sk='Skar:BAAANQADCgUIBgAAAA==.Skram:BAAANQAECgUICAABNQAECgoKMwAPAJwNAA==.Skronker:BAAANQADCggIDQAAAA==.',
Sl='Slammydooker:BAABNQAECn8fAAMRAAoKihWoCgCOAQARAAoKihWoCgCOAQAXAAUKfw0RXwA5AQAAAA==.',
Sm='Smallkat:BAAANQAECgUIBQAAAA==.Smirksfotm:BAAANQAECgUICAABNQAECggIEAASAAAAAA==.Smoketail:BAAANQAECgUIBwAAAA==.',
Sn='Snail:BAAANQAECgYIBgAAAA==.Sneakmanman:BAAANQADCgYJCQAAAA==.',
So='Somberdh:BAAANQADCggICwAAAA==.Sorni:BAABNQAECn8qAAMPAAgKVAjSZwD2AAAPAAgKVAjSZwD2AAAjAAIK7wK5awA7AAAAAA==.Soulglo:BAAANQADCgcIDQAAAA==.',
Sp='Spikeprotein:BAAANQABCggICQAAAA==.Sprayandpray:BAAANQAECgQIBwAAAA==.Spritey:BAAANQABCgIIAgAAAA==.',
Sq='Squidnips:BAAANQADCgQIBAAAAA==.',
St='Stareless:BAAANQADCgYIBgAAAA==.Statik:BAAANQAECgMIAwAAAA==.',
Su='Summondemons:BAAANQAECgIIBQAAAA==.Sumnèr:BAAANQADCgMIAwAAAA==.Sunpali:BAAANQAECgUICQAAAA==.Susanno:BAAANQADCgUJCwAAAA==.',
Sy='Sylauda:BAAANQADCgYICgAAAA==.Sylvians:BAAANQAECgEIAQAAAA==.',
Ta='Tacutacudark:BAAANQAECgMIBAAAAA==.Taintedbeef:BAAANQADCgEIAQABNQAECgYIDQASAAAAAA==.Talonflame:BAABNQAECn8pAAQMAAgKHxWVLwDQAQAMAAcKNhaVLwDQAQADAAMKEReXFgHWAAApAAIKiwpUBwCXAAAAAA==.Talonted:BAAANQAECgIIAgAAAA==.Tandallei:BAAANQAECgQIBAAAAA==.Tansu:BAAANQADCgcIDQAAAA==.Tateraid:BAAANQABCgYICQAAAA==.Taupo:BAAANQAECgIIAgAAAA==.Taxidermy:BAAANQADCgYIDAAAAA==.',
Te='Telarinda:BAABNQAECn8WAAMEAAoK5QevMAA2AQAEAAkKgwevMAA2AQAfAAIKkAqnaQBOAAAAAA==.',
Th='Thametal:BAAANQAECgIIAgAAAA==.Thicclich:BAAANQAECgcIDwAAAA==.Thicktotem:BAAANQAECgEIAQAAAA==.Thickumz:BAAANQADCgQIBAAAAA==.Thisismeta:BAAANQAECgYICgAAAA==.Thorynwar:BAACNQAFFH8YAAIOAAYKIB7GCQAXAgAOAAYKIB7GCQAXAgA1AAQKfy0AAg4ACgoIInUWAGADAA4ACgoIInUWAGADAAE1AAUUBQgNACUAIhQA.Thorýn:BAACNQAFFH8NAAMlAAUKIhR7DgAkAQAlAAQKIhR7DgAkAQAZAAEKAABpKABXAAA1AAQKfyUAAyUACQpzJooQADMDACUACQpzJooQADMDABkABwriGR9HAN0BAAAA.Thyrnoch:BAAANQAECgEIAQAAAA==.Thórin:BAAANQAECgYIDQAAAA==.',
Ti='Tierax:BAABNQAECn8tAAMRAAoKax45CQDiAgARAAkKvB85CQDiAgAXAAMKhhZKdQDcAAAAAA==.Tipsy:BAABNQAECn8mAAIHAAoKzhA1ZQDdAQAHAAoKzhA1ZQDdAQAAAA==.',
To='Tojì:BAAANQAECggIEAAAAA==.Tomfoolary:BAAANQADCgQIBAAAAA==.Tonathul:BAAANQADCggIEAAAAA==.Torrk:BAAANQAECgQIBAAAAA==.Torultrear:BAAANQAECgIIAgAAAA==.Tot:BAABNQAECn8hAAIHAAgKtw0IfwCPAQAHAAgKtw0IfwCPAQAAAA==.',
Tr='Tralleth:BAABNQAECn8ZAAMJAAgKlBoLDACZAQAJAAYKgBcLDACZAQAIAAcK4QxxLABFAQAAAA==.Trallock:BAAANQADCggIDwAAAA==.Traumatized:BAAANQADCgUIBwAAAA==.Truska:BAAANQABCgEIAQAAAA==.',
Tu='Tuskyrex:BAAANQAECgEIAQAAAA==.',
Tw='Twinklord:BAAANQAECgcIDQAAAA==.Twostroke:BAABNQAECn8oAAIDAAoKUiS+AAA7AwADAAoKUiS+AAA7AwAAAA==.Twretwtwrewr:BAAANQADCgIIAgAAAA==.Twunkie:BAAANQADCgcIBwAAAA==.',
Ty='Tylopally:BAAANQAFFAIIAgAAAA==.Tyloremixdd:BAAANQAECgQIBAAAAA==.Tylototem:BAAANQAECgQIBAAAAA==.',
['Tö']='Tötem:BAAANQADCgMIAwABNQAFFAUIBgAVAE0gAA==.',
Uj='Ujcpet:BAAANQADCgYIBgAAAA==.',
Un='Uncookedham:BAAANQADCgYIEAAAAA==.Underhorn:BAAANQADCggIDgAAAA==.',
Va='Vaas:BAAANQADCggICAABNQAECgoKIgAjADEfAA==.Vaeelrundor:BAABNQAECn8YAAIDAAUKGgq/9QAXAQADAAUKGgq/9QAXAQAAAA==.Valyr:BAAANQADCgQIBAAAAA==.Vampslayer:BAAANQADCgYIBgAAAA==.Vanillaface:BAAANQAECgcICAAAAA==.Vañillaface:BAAANQABCgQIBgAAAA==.',
Ve='Vedebone:BAAANQAECgUIDAAAAA==.Vedexd:BAABNQAECn8pAAIDAAcKrRDfoADEAQADAAcKrRDfoADEAQAAAA==.Velarael:BAABNQAECn8ZAAIgAAYKzRK/DQB8AQAgAAYKzRK/DQB8AQAAAA==.Veletharia:BAAANQADCgQIBAAAAA==.Velexi:BAAANQADCgQIBwAAAA==.',
Vh='Vheckxus:BAAANQAECgQIBAAAAA==.',
Vl='Vlidya:BAAANQADCgEIAQAAAA==.',
Vo='Voidberg:BAAANQAECgQIBAAAAA==.',
Vs='Vs:BAAANQAECggIDgAAAA==.',
Wa='Wachonaso:BAACNQAFFH8JAAIEAAQKgQtjGgAjAQAEAAQKgQtjGgAjAQA1AAQKfykAAwQACgooHV0/AJQCAAQACgq0HF0/AJQCAB8AAwokHcwwAAUBAAAA.Wastedsage:BAAANQAECgUICAAAAA==.Waterlou:BAAANQADCgYIBwAAAA==.',
Wh='Whatuphuz:BAAANQADCggIEAAAAA==.Wheresmyjaw:BAABNQAECn8sAAMEAAoKEx0zPQCbAgAEAAkKeh4zPQCbAgAfAAMKbRNfPQDMAAAAAA==.',
Wi='Wildthree:BAABNQAECn8aAAILAAcKDwpsCQDEAAALAAcKDwpsCQDEAAAAAA==.Wilkieswar:BAAANQADCggIGAABNQAECgoKLAAQADgfAA==.Willenda:BAAANQAECgEIAgAAAA==.Winterfall:BAAANQADCggIGwAAAA==.',
Wu='Wuinn:BAACNQAFFH8PAAIIAAcKdgivCQCVAQAIAAcKdgivCQCVAQA1AAQKfyEAAwgACgrXFo4VAFsCAAgACgrXFo4VAFsCAAkAAgpyEMUIAIUAAAAA.',
Xa='Xakutioner:BAABNQAECn8xAAICAAoKkxubFAAiAwACAAoKkxubFAAiAwAAAA==.Xaldiir:BAABNQAECn8nAAIFAAoKpB9/AQDdAgAFAAoKpB9/AQDdAgAAAA==.',
Xe='Xenvoroo:BAAANQADCgIIAgAAAA==.Xerexia:BAABNQAECn8/AAIOAAkK9gwRowDFAQAOAAkK9gwRowDFAQAAAA==.',
Xw='Xwoo:BAAANQAECgIIAgAAAA==.',
Xz='Xzarlatan:BAAANQADCgIIAgAAAA==.Xzarlatanfi:BAAANQADCgUIBQAAAA==.',
Ya='Yahro:BAAANQAECgcIEQAAAA==.',
Ye='Yellowranger:BAABNQAECn8yAAIWAAoKqxnGEgC9AQAWAAoKqxnGEgC9AQAAAA==.',
Yj='Yjn:BAAANQAECggIDQAAAA==.',
Yo='Yongyong:BAAANQAECgQIDQAAAA==.Yotoymuerto:BAAANQAECgEIAQAAAA==.',
Yu='Yunara:BAAANQAECgYIBgAAAA==.Yustayoke:BAABNQAECn8mAAIQAAgKihQarwAkAgAQAAgKihQarwAkAgAAAA==.',
Za='Zalvianna:BAAANQAECgUIBwAAAA==.Zarathoz:BAAANQABCgYJBgAAAA==.Zarshx:BAAANQADCgQICAABNQAECgYIBgASAAAAAA==.',
Ze='Zennithz:BAAANQAECggIEAAAAA==.Zeonz:BAAANQAECgEIAQAAAA==.',
Zi='Zilong:BAAANQAECgIIAwABNQAFFAcIDQAOADkTAA==.Zilongmage:BAAANQAECgYIBgABNQAFFAcIDQAOADkTAA==.Zilongwar:BAACNQAFFH8NAAIOAAcKOROwCwD3AQAOAAcKOROwCwD3AQA1AAQKfx4AAg4ACgpdIa8sAAoDAA4ACgpdIa8sAAoDAAAA.',
Zo='Zombor:BAAANQADCgIIAgAAAA==.Zonecw:BAAANQAECgcIEAAAAA==.Zonedk:BAAANQAECgQIBgABNQAECgcIEAASAAAAAA==.',
['Ør']='Ørsted:BAAANQADCgIIAgABNQAECgIIAgASAAAAAA==.',
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
