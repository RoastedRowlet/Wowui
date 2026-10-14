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

local lookup = {'Shaman-Elemental','Druid-Balance','Hunter-BeastMastery','DemonHunter-Havoc','Shaman-Enhancement','Shaman-Restoration','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster','Druid-Restoration','Warrior-Arms','Paladin-Retribution','Unknown-Unknown','DeathKnight-Frost','Paladin-Holy','Mage-Arcane','Rogue-Assassination','Rogue-Outlaw','DeathKnight-Blood','Rogue-Subtlety','Warlock-Demonology','Monk-Windwalker','DemonHunter-Devourer','Priest-Shadow','Priest-Holy','Warlock-Destruction','Warlock-Affliction','Druid-Guardian','Priest-Discipline','Mage-Frost','Warrior-Protection','Paladin-Protection','Druid-Feral','DeathKnight-Unholy','DemonHunter-Vengeance','Warrior-Fury','Monk-Mistweaver','Mage-Fire','Hunter-Survival','Hunter-Marksmanship',}
local provider = {region='US',realm='Nazjatar',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Aberoth:BAAANQADCgMIAwAAAA==.',
Ac='Accoli:BAAANQAECgUIBQAAAA==.Acslater:BAAANQADCgQIBAAAAA==.',
Ag='Agoobagoo:BAABNQAFFH8IAAIBAAMK+CDWFAAkAQABAAMK+CDWFAAkAQABNQAFFAUICwACANkYAA==.',
Al='Aliasx:BAAANQAECgQIBAAAAA==.Allarus:BAAANQADCgcICQAAAA==.Allwrong:BAAANQADCgQIBAAAAA==.Alotofsin:BAAANQAECgEIAQAAAA==.Alphadog:BAEBNQAECn8tAAIDAAgKVSIYJgD9AgADAAgKVSIYJgD9AgAAAA==.Alwaysunny:BAAANQADCgYIDAAAAA==.',
Am='Amahlfarouk:BAAANQAECgUIEAAAAA==.Aminatou:BAABNQAECn8fAAIEAAkKGhO2MAAeAgAEAAkKGhO2MAAeAgAAAA==.',
Ar='Ariaddne:BAABNQAECn8bAAQFAAgKTheMFQAMAgAFAAgKeBaMFQAMAgABAAUKpxXssAAsAQAGAAEKwRiTEQFAAAAAAA==.Artemîs:BAAANQAECgEIAQAAAA==.',
As='Ashaelra:BAAANQAECgUIBQAAAA==.Asolitha:BAAANQADCgUIBQAAAA==.',
Au='Augonly:BAABNQAFFH8JAAIHAAMKABN/EADdAAAHAAMKABN/EADdAAAAAA==.Augy:BAABNQAECn8kAAMIAAgK0x0TBwA+AgAIAAcK0hoTBwA+AgAJAAcKAhtBFQD2AQAAAA==.',
Ba='Bakuretsu:BAAANQAECggIDAABNQAECgkJKwAKAE0eAA==.Barhead:BAAANQADCggIDgAAAA==.Barlow:BAAANQAECgYIDAAAAA==.',
Bb='Bbldrizzy:BAACNQAFFH8LAAIBAAUKgyHTCADdAQABAAUKgyHTCADdAQA1AAQKfyYAAgEACQq9JHURAGIDAAEACQq9JHURAGIDAAAA.',
Be='Beastlieduke:BAAANQADCgYIDAABNQAECggIHQALAGUdAA==.Beastlièduke:BAAANQADCgIIAgABNQAECggIHQALAGUdAA==.Belephon:BAAANQAECgMIAwAAAA==.Belinda:BAAANQADCggIFwAAAA==.',
Bi='Bighunt:BAAANQAECgMIAwAAAA==.Bijju:BAAANQAECggIDAAAAA==.Binggus:BAABNQAECn8XAAIMAAgKyh0jVACLAgAMAAgKyh0jVACLAgAAAA==.',
Bl='Blabbybootze:BAABNQAECn8XAAINAAcK+ALeJQHaAAANAAcK+ALeJQHaAAAAAA==.Bladelight:BAAANQADCgcJDAAAAA==.Blighte:BAAANQAECgQIBAABNQAECgkJJQACAK8eAA==.Blightfangs:BAAANQAECgYIDwAAAA==.Bluzey:BAAANQADCgYIBgAAAA==.',
Bo='Bodakye:BAABNQAECn8YAAIDAAgKhBF+ZQBHAgADAAgKhBF+ZQBHAgAAAA==.Boneplague:BAAANQADCgQIBAAAAA==.Boow:BAAANQAECgUIBQAAAA==.',
Br='Bracalina:BAAANQAECgEIAQAAAA==.Brannix:BAAANQADCgUIBQAAAA==.Broggy:BAAANQADCgEIAQABNQAECgcICAAOAAAAAA==.Brorgy:BAAANQAECgUIEgABNQAECgcIEAAOAAAAAA==.Brovahkin:BAAANQABCggIEAAAAA==.',
Bu='Bubbapal:BAAANQADCgUIBwAAAA==.Bushntush:BAAANQADCggICQAAAA==.Buzzbuzz:BAAANQAECgMIBAAAAA==.',
By='Bywar:BAAANQADCgcICwAAAA==.',
['Bé']='Bébop:BAAANQAECggICAAAAA==.',
Ca='Caeruleus:BAAANQADCgQJBAAAAA==.Captyn:BAAANQABCgQIAwAAAA==.Catbum:BAAANQADCgIIAwAAAA==.Caylea:BAAANQADCggICAAAAA==.',
Ch='Chaosraven:BAABNQAECn8oAAIPAAgKqBFDPQDTAQAPAAgKqBFDPQDTAQAAAA==.Chapelgnome:BAAANQADCgUJBQABNQAECgcIEAAOAAAAAA==.Charlyne:BAAANQABCgMIAwAAAA==.Chewthymight:BAABNQAECn8iAAMNAAcKyxRFpwDMAQANAAcKyxRFpwDMAQAQAAUKegdvyADmAAAAAA==.Chickenslop:BAAANQADCggIGwAAAA==.Chiptime:BAAANQAECgUIDAAAAA==.Chloes:BAAANQAECgIIAgAAAA==.Chri:BAAANQAECgQIBwAAAA==.Chrri:BAAANQAECgIIAwAAAA==.Chungotron:BAABNQAFFH8HAAINAAUKEgvwDQBoAQANAAUKEgvwDQBoAQAAAA==.Chzburger:BAAANQABCgIIBAAAAA==.',
Cl='Cladon:BAAANQAECggICAAAAA==.Clairity:BAAANQADCgcIBwAAAA==.',
Co='Cocoon:BAAANQAECgQIBAABNQAFFAMICAARAKcTAA==.Conda:BAAANQAECggICAAAAA==.Cormogh:BAAANQAECgIIAgAAAA==.Cowhealer:BAABNQAECn8lAAMCAAkKrx4LHwDQAgACAAkKrx4LHwDQAgALAAMKGAoKWwCWAAAAAA==.',
Cr='Craeftig:BAABNQAECn8aAAMSAAgKGRZiIQB1AgASAAgKGRZiIQB1AgATAAEKowFuHwAWAAAAAA==.Craeftigdk:BAABNQAECn8dAAIUAAcKAQ4qWgCHAQAUAAcKAQ4qWgCHAQABNQAECggIGgASABkWAA==.Craeftigtwo:BAAANQADCggJDQABNQAECggIGgASABkWAA==.Craeftigwl:BAAANQAECgIIAgABNQAECggIGgASABkWAA==.Crepitus:BAABNQAECn8WAAMVAAYKEgxNLQBTAQAVAAYKEgxNLQBTAQASAAIKWQWxkgBdAAAAAA==.Crusabull:BAAANQADCgUIBQAAAA==.Cræftig:BAAANQAECgcIEQABNQAECggIGgASABkWAA==.',
Cu='Cuddlseraph:BAAANQAECgUIEgAAAA==.',
Cy='Cynnithice:BAAANQADCgIIAgABNQAECgEIAQAOAAAAAA==.',
Da='Daamdam:BAAANQAECggIEQAAAA==.Dafirenze:BAAANQADCggIDwAAAA==.Daftxshade:BAAANQADCgcICAAAAA==.Dariian:BAAANQAECggIBgAAAA==.Darkbeef:BAABNQAECn8VAAIWAAYKDQO89ADcAAAWAAYKDQO89ADcAAAAAA==.Darkjusticeh:BAAANQAECgUIBwAAAA==.Darlang:BAAANQAECgEIAQAAAA==.Darthbjóurn:BAAANQAECgUIBQAAAA==.Darthsyde:BAAANQAECgcIDwAAAA==.Dayanna:BAAANQADCgUIBQAAAA==.',
De='Deadergriff:BAAANQAECgUIDgAAAA==.Deadicated:BAABNQAECn8YAAIXAAcKvQiQOgA6AQAXAAcKvQiQOgA6AQAAAA==.Deadinsíde:BAAANQAECggICAABNQAECggIEAAOAAAAAA==.Deathlyaura:BAAANQADCggICAABNQAECgMIAwAOAAAAAA==.Deathmark:BAAANQAECgMIAwAAAA==.Deeznutzs:BAAANQAECgYICgAAAA==.Defendaya:BAAANQAECggICAAAAA==.Delan:BAAANQAECgYIBwAAAA==.Demolishonn:BAAANQAECgUIBgAAAA==.Desunaito:BAACNQAFFH8NAAIPAAYKxhfDAwDkAQAPAAYKxhfDAwDkAQA1AAQKfzEAAg8ACQoGI3oLADoDAA8ACQoGI3oLADoDAAAA.Dexter:BAAANQAECgQIBQAAAA==.',
Dh='Dhzilong:BAAANQAECggIDAABNQAFFAcIDQAMADkTAA==.',
Di='Diddlefiddle:BAAANQADCgIIAgAAAA==.Dioji:BAAANQAECggIBgAAAA==.',
Dk='Dkzilong:BAAANQAECgIIAwABNQAFFAcIDQAMADkTAA==.',
Dm='Dmeo:BAAANQADCgMIAwAAAA==.',
Do='Docadoodle:BAAANQADCgcIBwABNQAECgkJJQAYABIYAA==.Docwyle:BAABNQAECn8lAAIYAAkKEhg1GACYAgAYAAkKEhg1GACYAgAAAA==.Doozey:BAAANQABCgcJBwAAAA==.',
Dr='Dracmary:BAAANQADCgUIBQAAAA==.Dracnogard:BAAANQAECgQIBQAAAA==.Dracowulf:BAABNQAECn8ZAAIDAAYKOgXM2wBEAQADAAYKOgXM2wBEAQAAAA==.Dragonbro:BAAANQAECgEIAQAAAA==.Dragonx:BAABNQAECn8bAAIDAAYKEgm2yABrAQADAAYKEgm2yABrAQAAAA==.Drakowolf:BAAANQAECgYIDwAAAA==.Drama:BAAANQAECgEIAQAAAA==.Dreadful:BAABNQAECn81AAIQAAkKTBrKLQCtAgAQAAkKTBrKLQCtAgAAAA==.Dreorge:BAABNQAECn8XAAIHAAkKNBWNEwBzAgAHAAkKNBWNEwBzAgAAAA==.Drewceratops:BAABNQAECn8aAAINAAkKVA9anQDiAQANAAkKVA9anQDiAQAAAA==.Drewidd:BAAANQAECgUIBQABNQAECgcIEAAOAAAAAA==.Drimchi:BAAANQAECgEIAQAAAA==.Drimveil:BAABNQAECn8UAAIEAAgKVxh2LQA0AgAEAAgKVxh2LQA0AgAAAA==.Drogô:BAAANQAECgQIBAAAAA==.Dromgar:BAAANQAECggICAAAAA==.Dromkyr:BAABNQAECn8qAAMHAAkKyQ9mGwAQAgAHAAkKyQ9mGwAQAgAJAAEKNwu6PAAyAAAAAA==.Drossiechan:BAACNQAFFH8IAAIXAAMKog+/DADPAAAXAAMKog+/DADPAAA1AAQKfxsAAhcACQpYGXMZAHQCABcACQpYGXMZAHQCAAAA.',
Du='Duellipa:BAAANQAECgcIEAAAAA==.',
Dy='Dysian:BAAANQADCgQIBQAAAA==.Dywanw:BAAANQABCgYIBgAAAA==.',
Ed='Edward:BAAANQAECggJBwAAAA==.',
Ef='Effloria:BAABNQAECn8pAAILAAkKuyNMAwCSAwALAAkKuyNMAwCSAwAAAA==.',
Ek='Ekim:BAAANQADCgQIAwAAAA==.Eklyps:BAAANQADCgYIBgAAAA==.',
El='Elauvia:BAAANQAECgUICAAAAA==.Elegia:BAAANQAECggIDgAAAA==.',
Em='Emleah:BAAANQAECgEIAwAAAA==.Emmaina:BAAANQAECgIIAgAAAA==.',
En='Enash:BAAANQADCgQIBAAAAA==.Encoredh:BAAANQAECgQJBAABNQAECgcIHAAZAAYXAA==.Encoredk:BAAANQADCgIIAgAAAA==.Encoree:BAAANQADCgcIBwABNQAECgcIHAAZAAYXAA==.Encoremts:BAAANQAECgEIAQABNQAECgcIHAAZAAYXAA==.Encorep:BAABNQAECn8cAAMZAAcKBhd4JQAAAgAZAAcKBhd4JQAAAgAaAAIKiw3g6QBdAAAAAA==.Enris:BAAANQADCgUICAAAAA==.',
Es='Esael:BAAANQAECggICAAAAA==.',
Ev='Eviscerated:BAAANQAECgQIBQAAAA==.',
Fa='Fail:BAAANQADCgYICwAAAA==.Falker:BAAANQADCgYIBgAAAA==.Fallen:BAAANQAECgYICQAAAA==.Fallingvoid:BAAANQAFFAIIAgAAAA==.Fancyfeet:BAAANQADCgIIAwABNQAECgYIBgAOAAAAAA==.Fatchungus:BAAANQAECgQIBQABNQAECgYIBgAOAAAAAA==.Fateesia:BAAANQAECgEIAQAAAA==.',
Fe='Feathersong:BAAANQADCgYIBgAAAA==.Fendru:BAAANQADCgYIAwAAAA==.Fextardo:BAAANQADCgYIBgAAAA==.',
Fi='Finaliter:BAABNQAECn8tAAINAAkKGh0mSgCzAgANAAkKGh0mSgCzAgAAAA==.',
Fl='Flamingdrago:BAAANQAECgQIBQAAAA==.Flirtyflurry:BAAANQAECgQIBgAAAA==.',
Fo='Forsight:BAAANQADCgYIBgABNQAECgMIBgAOAAAAAA==.Fox:BAACNQAFFH8OAAMTAAUKvBqFAQAxAQATAAQK8hKFAQAxAQASAAMKvBp9DgD8AAA1AAQKfzAAAxMACQqgI38CAC8DABMACQqLIX8CAC8DABIABwoaHtkkAF4CAAAA.',
Fr='Fremder:BAAANQAECgUJBgAAAA==.Froggy:BAAANQAECggIEAAAAA==.Frogleap:BAAANQADCgUIBQABNQAECggIEAAOAAAAAA==.Frogred:BAAANQADCgQIBAABNQAECggIEAAOAAAAAA==.Frogtoad:BAAANQAECgQIBQABNQAECggIEAAOAAAAAA==.',
Fu='Funeral:BAACNQAFFH8gAAQbAAcKah+6AAB7AQAbAAQKvRy6AAB7AQAWAAQKfBtCEgBvAQAcAAIKThY7AwDCAAA1AAQKfykABBsACQq7JW4BAHoDABsACQp0JG4BAHoDABYABgq1JHBfADYCABwAAgoEJsEbAKAAAAAA.Furiousmoon:BAAANQADCggICAAAAA==.Futuresailor:BAAANQAECgQIBAAAAA==.',
Fy='Fyjhrt:BAABNQAECn8iAAITAAcKvCLmBACuAgATAAcKvCLmBACuAgAAAA==.',
Ga='Galladin:BAAANQAECgYICAABNQAECgIIAQAOAAAAAA==.Gallory:BAAANQAECggIDgAAAA==.',
Gd='Gdk:BAAANQAECgMIBAABNQAECgkJKgABAMkXAA==.Gdkdrake:BAAANQADCgUIBQABNQAECgkJKgABAMkXAA==.Gdkhunter:BAAANQADCggICAABNQAECgkJKgABAMkXAA==.Gdkmage:BAAANQAECgUICgABNQAECgkJKgABAMkXAA==.Gdkman:BAABNQAECn8qAAQBAAkKyRdjTQA+AgAFAAgKtxVREABiAgABAAgKyBhjTQA+AgAGAAIKlwjQBgFUAAAAAA==.Gdknotlock:BAAANQADCgQIBgABNQAECgkJKgABAMkXAA==.',
Ge='Geoprince:BAAANQADCgcIEAAAAA==.Gerbon:BAAANQADCgMICAAAAA==.',
Gh='Ghaldrin:BAAANQABCggIFAAAAA==.Ghoulfriend:BAAANQADCgUICgAAAA==.',
Gi='Gigitty:BAAANQADCgYIBgAAAA==.Gimmedatneck:BAABNQAECn8dAAMSAAkKQB/XCwAmAwASAAkKQB/XCwAmAwAVAAQKSATxQACrAAABNQAFFAUICwABAIMhAA==.Githrogathan:BAAANQAECgUIDgAAAA==.',
Go='Gokudin:BAAANQADCgIIAgABNQADCgIIAgAOAAAAAA==.Goldenrager:BAAANQADCgQIBAAAAA==.Gooseandmav:BAAANQADCgEIAQAAAA==.',
Gr='Grabetta:BAAANQADCgEIAQAAAA==.Gragasfat:BAAANQAECgIIAgAAAA==.Groundnpound:BAAANQADCgUJBQAAAA==.',
Gy='Gyanall:BAAANQADCgMIAwAAAA==.',
['Gâ']='Gârrosh:BAAANQADCgYIBgABNQAECgkJMgADAJQNAA==.',
['Gö']='Gödhand:BAAANQAECgQIBwAAAA==.',
Ha='Haeha:BAAANQADCgQIBAAAAA==.Haraldsson:BAAANQADCggICAAAAA==.Hargrumn:BAAANQABCgMIAgAAAA==.Harrypooc:BAAANQADCgQJBAAAAA==.Hasaro:BAACNQAFFH8FAAIdAAIKUgZmCABlAAAdAAIKUgZmCABlAAA1AAQKfywAAh0ACQr0DfceAKABAB0ACQr0DfceAKABAAAA.Hatcho:BAAANQADCgUICAAAAA==.Havokvacano:BAAANQAECgUIDwAAAA==.Havøckblaze:BAAANQADCgIIAgAAAA==.',
He='Healmachine:BAAANQAECgMICAAAAA==.Hellbrringer:BAAANQAECgEIAQAAAA==.Helzer:BAAANQADCggIDwABNQAECgkJKQAFANEbAA==.',
Ho='Holybaphomet:BAAANQADCgUICQAAAA==.Holyfarts:BAABNQAECn8zAAQeAAkKnSFHAQBLAwAeAAkKrR9HAQBLAwAaAAgKqh6RMACjAgAZAAgK8hPgKgDNAQAAAA==.Honeypaw:BAAANQADCgUIBQAAAA==.Hornedraven:BAAANQADCgEIAQAAAA==.',
Hu='Humanform:BAAANQADCgUIBQAAAA==.Hunbroll:BAAANQADCgYIBgABNQAFFAYIEwAfAGkQAA==.Hungshaman:BAAANQABCgIIAgAAAA==.Hunterkiller:BAAANQADCggIGgAAAA==.',
Hx='Hx:BAAANQAECgQIBAAAAA==.',
Hy='Hypnoticpal:BAAANQAECggIDAAAAA==.',
['Hõ']='Hõnor:BAABNQAECn8xAAMMAAkKKCGJHQBAAwAMAAkKox+JHQBAAwAgAAUKJCIMFwC2AQABNQAFFAUIBgAPAE0gAA==.',
Ia='Iammoo:BAAANQAECgIIAgAAAA==.',
Ig='Igriss:BAAANQAECgYIDwAAAA==.',
Il='Illidanx:BAAANQADCgQIBAAAAA==.Illuminaughd:BAAANQAECgMIBQAAAA==.Ilumii:BAAANQAECgMIAwAAAA==.Ilydris:BAAANQADCgQICAAAAA==.',
Im='Imonthegcd:BAAANQAECgYIDQABNQAFFAUIBgAPAE0gAA==.',
In='Infinitepain:BAABNQAECn8rAAIaAAkK8iD2FAAmAwAaAAkK8iD2FAAmAwAAAA==.Innodk:BAAANQAECgYIEgAAAA==.',
Ir='Irami:BAAANQAECgEIAQAAAA==.Iridellis:BAAANQADCgcIBwABNQAECgkJNQAQAEwaAA==.',
Is='Ispankutank:BAAANQADCgEIAQAAAA==.',
Ja='Jabzert:BAAANQADCgEIAQABNQAECgkJKgABAMkXAA==.Jahjahblinks:BAAANQADCgYIFAABNQAECgkJMgADAJQNAA==.Jave:BAAANQABCgQIBQAAAA==.Jaycers:BAABNQAECn8fAAIhAAkKSiANCwDnAgAhAAkKSiANCwDnAgAAAA==.Jayclark:BAAANQADCgEIAQAAAA==.',
Ji='Jimmypal:BAAANQAECgMIBwAAAA==.',
Jo='Joedingle:BAABNQAECn8eAAIRAAcKNCAGmQBOAgARAAcKNCAGmQBOAgAAAA==.Joemomma:BAAANQADCgUIBQAAAA==.Johnnyboi:BAAANQADCgEIAQAAAA==.Jokestarfist:BAABNQAECn8YAAINAAcKmxKawACVAQANAAcKmxKawACVAQAAAA==.',
Jr='Jr:BAAANQADCggICAAAAA==.',
Ju='Jumpy:BAAANQABCgMIAwAAAA==.',
Ka='Kaelar:BAAANQADCgMIAwABNQAECgkJMgAiALAkAA==.Kaitokit:BAACNQAFFH8HAAMUAAMKDRBTGgDDAAAUAAMKDRBTGgDDAAAjAAEKeQJDJQA1AAA1AAQKfz4AAxQACQrIH94NAEADABQACQrIH94NAEADACMACAo/EAZdAJcBAAAA.Kalia:BAAANQADCgIIAgAAAA==.Kalyth:BAAANQAECgcIEgAAAA==.Kamera:BAABNQAECn8aAAQNAAkKLx1LdABBAgANAAgKLx1LdABBAgAQAAMK9gXj+gCBAAAhAAEKAADTcAAtAAAAAA==.Kandessa:BAAANQADCgIIAwAAAA==.Kaylah:BAABNQAECn8kAAMTAAgKbSIrAwAGAwATAAgKbCIrAwAGAwASAAYKvh2SPgDOAQAAAA==.Kayllina:BAAANQAECgUIEAAAAA==.Kayotic:BAAANQAECgIIAwAAAA==.',
Ke='Kelmorphic:BAABNQAECn8pAAIkAAkKxCFEAgBkAwAkAAkKxCFEAgBkAwAAAA==.',
Ki='Killcommand:BAAANQADCggICAABNQAFFAMICAARAKcTAA==.',
Ko='Kosmas:BAAANQAECgEJAQAAAA==.',
Kr='Krombear:BAAANQADCgIIAgAAAA==.',
Ku='Kudai:BAAANQAECgQIBgAAAA==.Kungpowchikn:BAAANQADCgIIAgAAAA==.Kurisuw:BAAANQAECgYIBwAAAA==.Kurookami:BAAANQADCgEIAQAAAA==.Kuukwa:BAAANQAECgUICAAAAA==.',
Ky='Kyana:BAAANQAECgMIAgAAAA==.Kyarina:BAAANQABCggIDwAAAA==.',
['Kí']='Kíller:BAAANQAECgUIDQAAAA==.',
La='Lamadda:BAAANQADCgUIBQAAAA==.',
Ld='Ldg:BAAANQADCgQIBAAAAA==.',
Le='Leafdaddy:BAAANQAECgUICQABNQAECgkJKQAKAD4dAA==.Leakoon:BAAANQADCggICAAAAA==.Lelise:BAABNQAECn8UAAIhAAgKzAGrXgBcAAAhAAgKzAGrXgBcAAAAAA==.Letusgiveita:BAAANQADCgQIBAAAAA==.',
Li='Lightbringr:BAAANQADCgYICwAAAA==.Lightingbolt:BAAANQADCgUICwAAAA==.Lightshields:BAAANQADCgIIAgAAAA==.Lilpapi:BAAANQAECgYIBgABNQAFFAMICAAdAGwlAA==.Lilymei:BAAANQADCggIGAAAAA==.Linesondra:BAAANQADCgUICgAAAA==.Linissa:BAAANQAECgQIBgAAAA==.Littledude:BAAANQADCgYIBgAAAA==.Littlemorsel:BAABNQAECn8hAAIDAAgKzwwFfwALAgADAAgKzwwFfwALAgAAAA==.Livalifa:BAAANQAECgcIDAAAAA==.',
Lo='Lockenload:BAAANQAECgUIDAAAAA==.Lockme:BAAANQADCgUIBQAAAA==.Lohhar:BAAANQADCggIDwAAAA==.Loser:BAAANQABCgQIBQAAAA==.',
Ls='Lselec:BAAANQAECgMJBQAAAA==.',
Lu='Lucens:BAABNQAECn8gAAIQAAgKXBAXbQDNAQAQAAgKXBAXbQDNAQAAAA==.Lucerna:BAAANQAECgQIBQAAAA==.Lurchdh:BAAANQADCgQJBAABNQAECgkJYgAfAAQbAA==.Lurchdruid:BAAANQAECgIIAQABNQAECgkJYgAfAAQbAA==.Lurchmage:BAABNQAECn8XAAMfAAgKAg5DFQBVAQAfAAYKCBBDFQBVAQARAAYKFgVdRAEXAQABNQAECgkJYgAfAAQbAA==.Lurchn:BAABNQAECn9iAAMfAAkKBBtNBADpAgAfAAkKBBtNBADpAgARAAkKowY87gCqAQAAAA==.',
Ly='Lyricai:BAAANQAECgUIDwAAAA==.',
Ma='Madjake:BAAANQADCggICAAAAA==.Maemae:BAAANQADCggIEwAAAA==.Magallanes:BAAANQAECgQIBAAAAA==.Mapleleaf:BAAANQAECgYICgAAAA==.Markyy:BAABNQAECn8qAAQNAAkKbiXlBADSAwANAAkKbiXlBADSAwAQAAYKpg98kgBjAQAhAAEKAABeXwBaAAABNQAFFAUIBgAPAE0gAA==.Matas:BAAANQAECgYICgAAAA==.Maylinfenora:BAABNQAECn8eAAISAAcK3Q2ERgCmAQASAAcK3Q2ERgCmAQAAAA==.Mazzikane:BAAANQADCgYIBgAAAA==.',
Me='Meangry:BAAANQADCgEIAQAAAA==.Meowizenith:BAAANQADCgUIBQAAAA==.Merdazin:BAAANQAECgQIDAAAAA==.Metalhedface:BAABNQAECn8iAAMMAAkKRhLRgwAOAgAMAAkKqhDRgwAOAgAlAAEKvRgBLgBHAAAAAA==.',
Mi='Mikecoxwall:BAAANQADCgEIAQAAAA==.Minisan:BAAANQADCgEIAQAAAA==.Misary:BAAANQAECgIIAgAAAA==.Mistake:BAAANQAECgYIDgAAAA==.',
Mo='Mogyar:BAABNQAECn8bAAINAAcKBRbXrwC6AQANAAcKBRbXrwC6AQAAAA==.Moistybush:BAAANQAECgEIAQAAAA==.Moltalgol:BAAANQAECgQICgAAAA==.Monkeli:BAABNQAECn8dAAIlAAcKkxVEDQDhAQAlAAcKkxVEDQDhAQAAAA==.Moocifer:BAAANQADCgcIDQAAAA==.Moocifermoo:BAAANQAECgEIAQAAAA==.Moogrim:BAAANQADCggIEAAAAA==.Moonsiand:BAEBNQAECn8oAAIDAAgK3SAiIgANAwADAAgK3SAiIgANAwABNQAECggILQADAFUiAA==.Moreldwiddle:BAAANQAECgUIDwAAAA==.Morgaia:BAAANQAECgUIBQAAAA==.Morrigån:BAAANQADCgMIAwAAAA==.Motgus:BAABNQAECn8XAAQWAAcKmh57gwDZAQAWAAUKEiB7gwDZAQAbAAIKZRz+RgCqAAAcAAIKVxutHACWAAAAAA==.Mozzsticks:BAAANQADCgYICwAAAA==.',
Ms='Mshottie:BAAANQAECgEIAQAAAA==.',
Mx='Mx:BAAANQADCgYIDwAAAA==.',
My='Mystrialia:BAAANQABCgYIBgAAAA==.Mythlock:BAAANQADCgcIEwAAAA==.Mythranite:BAAANQADCgMIAwAAAA==.Myway:BAAANQADCggICAAAAA==.',
['Mó']='Mócha:BAAANQAECgUIEgAAAA==.',
Na='Nardrian:BAAANQAECgQIBQAAAA==.Naydian:BAAANQAECgQIBAAAAA==.',
Ne='Nekiron:BAAANQADCgQIBAAAAA==.Nellaa:BAAANQAECgcICAAAAA==.Nerrd:BAAANQAECgEIAQAAAA==.Nestaria:BAAANQADCggICAAAAA==.Netalanot:BAAANQADCgYIBgAAAA==.Nettik:BAAANQADCgUIBwAAAA==.Neverborn:BAABNQAECn8dAAICAAcKYg6QVQB+AQACAAcKYg6QVQB+AQAAAA==.',
Ni='Nightrage:BAAANQAECgQICgAAAA==.Nilex:BAAANQAECgYICgAAAA==.',
No='Nomadic:BAAANQADCgIIAgAAAA==.Notmypally:BAAANQAECgUIBQABNQAECgkJJQARAMkfAA==.',
Nu='Numera:BAAANQADCgIIAwABNQAECggIDQAOAAAAAA==.Nutellaqq:BAABNQAECn8YAAIRAAcK4BhIrgAlAgARAAcK4BhIrgAlAgAAAA==.',
Ob='Obeseotter:BAABNQAECn8uAAIRAAgK6RcFogA8AgARAAgK6RcFogA8AgAAAA==.Oborax:BAEBNQAECn8WAAINAAgK3xFUlAD2AQANAAgK3xFUlAD2AQABNQAECggILQADAFUiAA==.',
Od='Od:BAAANQAECgIIAgAAAA==.',
Ol='Oliviabenson:BAABNQAECn8aAAIRAAgKAR8SXgDDAgARAAgKAR8SXgDDAgAAAA==.',
Ox='Oxsidius:BAAANQAECgQICAAAAA==.',
Pa='Palady:BAAANQADCgEIAQAAAA==.Paldi:BAAANQAECgQIBAABNQAECgYIBgAOAAAAAA==.Paliboos:BAAANQADCgYIBgAAAA==.Palulu:BAEANQAECggIDwAAAA==.Pandacub:BAAANQAECggICAAAAA==.Pariss:BAAANQADCgUIBQABNQAECggIEAAOAAAAAA==.Paws:BAAANQAECgUIEwAAAA==.Pawse:BAAANQADCggIDwAAAA==.',
Pe='Peaky:BAABNQAECn8oAAQmAAgKVQq4IgBpAQAmAAgKVQq4IgBpAQAKAAUKgwRLJQChAAAXAAIKNAHMbQArAAAAAA==.Perelia:BAABNQAECn8dAAIeAAcKgg8CDAB6AQAeAAcKgg8CDAB6AQAAAA==.',
Pl='Plondor:BAAANQABCgEIAQAAAA==.',
Po='Polarity:BAAANQAECgUIEAAAAA==.Pooche:BAAANQAECgIIAwAAAA==.Popcola:BAAANQAECgQICQAAAA==.Pouts:BAAANQAECgQIBAABNQAFFAIIBgAOAAAAAA==.Powerpaladin:BAAANQABCgQIBAAAAA==.',
Pr='Prezu:BAEBNQAECn8VAAIHAAcKnA7LKQBeAQAHAAcKnA7LKQBeAQABNQAECggIDwAOAAAAAA==.Procyonx:BAAANQAECgEIAQAAAA==.Prophofdoom:BAABNQAECn8dAAIgAAgKdSHLBgDyAgAgAAgKdSHLBgDyAgAAAA==.Prõc:BAAANQADCggICAAAAA==.',
Pv='Pvc:BAACNQAFFH8IAAIRAAMKpxOvNADtAAARAAMKpxOvNADtAAA1AAQKfx8AAxEACQr9I6tGAPYCABEACQr9I6tGAPYCACcAAQqaACoPACUAAAAA.',
Ra='Raisedead:BAAANQADCgIIAgABNQADCggIDAAOAAAAAA==.Rancord:BAAANQADCggICAAAAA==.Rasmira:BAAANQADCggICAAAAA==.Rastaqwon:BAAANQAECgEIAQAAAA==.Ratsmasher:BAAANQAECgIIAgAAAA==.Razed:BAAANQADCgYICwAAAA==.',
Re='Renoitukax:BAAANQAECgUICQAAAA==.Restfuldark:BAAANQADCggICAAAAA==.Retrobution:BAABNQAECn8gAAINAAkKKiHRJgAoAwANAAkKKiHRJgAoAwAAAA==.Rezz:BAAANQAECgcIDAAAAA==.',
Rh='Rhohir:BAAANQABCgIIAgAAAA==.',
Ri='Riru:BAAANQAECgQIBwAAAA==.',
Ro='Rockstéady:BAAANQAECggICAAAAA==.Roopall:BAABNQAECn8hAAIQAAkKCSHXDgBTAwAQAAkKCSHXDgBTAwAAAA==.',
Ry='Rynzu:BAAANQAECgMIBAAAAA==.Ryzen:BAAANQAECgcIDQAAAA==.',
Sa='Sabelwin:BAAANQADCgEIAQAAAA==.Sanasrindis:BAAANQADCgQIAgAAAA==.Saninar:BAABNQAECn8gAAIhAAcKqwwmMgBMAQAhAAcKqwwmMgBMAQAAAA==.Sanshift:BAAANQAECgQIBAAAAA==.Satansimp:BAAANQAECgIIAgAAAA==.',
Sc='Schezmu:BAAANQAECgUICAAAAA==.',
Se='Sean:BAAANQADCgUICgAAAA==.Senorfiesta:BAAANQAECgUIEgAAAA==.Serazarke:BAAANQADCggICAAAAA==.Setazen:BAAANQADCgYIBgAAAA==.',
Sh='Shadowjoker:BAAANQAECgEIAQAAAA==.Shaee:BAABNQAECn8dAAMEAAYKyxeJQAC1AQAEAAYKyxeJQAC1AQAYAAEKAADvcwAjAAAAAA==.Shamama:BAAANQADCgUIBQAAAA==.Shamans:BAAANQAECgQIBQAAAA==.Shambalaya:BAAANQAECgUICQAAAA==.Shaokhan:BAAANQAECgUIEAAAAA==.Shasta:BAACNQAFFH8IAAIdAAMKbCVSAwAuAQAdAAMKbCVSAwAuAQA1AAQKfyQAAh0ACQqtJaMBAMQDAB0ACQqtJaMBAMQDAAAA.Shihthead:BAAANQADCgUIBQAAAA==.Shisuiuchiha:BAAANQADCgIIAgAAAA==.Shmorg:BAAANQADCgEIAQAAAA==.Shootumup:BAABNQAECn8vAAMoAAkKjCNlAQBdAwAoAAkKjCNlAQBdAwADAAEKZRf0RgFJAAAAAA==.Shyx:BAABNQAECn8tAAQaAAgKeiMZFQAlAwAaAAgKeiMZFQAlAwAZAAcKCw3jNAB4AQAeAAEKjRktJQBBAAAAAA==.',
Si='Simplèjack:BAABNQAECn8eAAIRAAcKswlX/QCPAQARAAcKswlX/QCPAQAAAA==.Sinamon:BAAANQAECgQIBwAAAA==.Sinani:BAAANQADCgUJBQAAAA==.Sinnamon:BAAANQABCgQJBAABNQAECgQIBwAOAAAAAA==.',
Sj='Sjdh:BAAANQADCgYIBgABNQAECgkJKAAMAFsbAA==.',
Sk='Skar:BAAANQADCgUIBgAAAA==.Skram:BAAANQAECgQIBAABNQAECggILwANAP8NAA==.Skronker:BAAANQADCggIDQAAAA==.',
Sl='Slammydooker:BAABNQAECn8ZAAMVAAkKeRKwEgBXAgAVAAkKeRKwEgBXAgASAAUKfw11XQA5AQAAAA==.',
Sm='Smallkat:BAAANQAECgUIBQAAAA==.Smirksfotm:BAAANQAECgUICAABNQAECggIEAAOAAAAAA==.Smoketail:BAAANQAECgUIBwAAAA==.',
Sn='Snail:BAAANQAECgYIBgAAAA==.Sneakmanman:BAAANQADCgYJCQAAAA==.',
So='Somberdh:BAAANQADCggICwAAAA==.Sorni:BAABNQAECn8iAAMNAAcKfweV4wBNAQANAAcKfweV4wBNAQAhAAIK7wJ4agA7AAAAAA==.Soulglo:BAAANQADCgcIDQAAAA==.',
Sp='Spikeprotein:BAAANQABCggICQAAAA==.Sprayandpray:BAAANQAECgQIBgAAAA==.Spritey:BAAANQABCgIIAgAAAA==.',
Sq='Squidnips:BAAANQADCgQIBAAAAA==.',
St='Stareless:BAAANQADCgYIBgAAAA==.Statik:BAAANQAECgMIAwAAAA==.',
Su='Summondemons:BAAANQAECgIIBQAAAA==.Sunpali:BAAANQAECgUICQAAAA==.Susanno:BAAANQADCgUJCwAAAA==.',
Sy='Sylauda:BAAANQADCgYICgAAAA==.Sylvians:BAAANQAECgEIAQAAAA==.',
Ta='Tacutacudark:BAAANQAECgMIBAAAAA==.Taintedbeef:BAAANQADCgEIAQABNQAECgYIDQAOAAAAAA==.Talonflame:BAABNQAECn8nAAMpAAcKNhYSLwDRAQApAAcKNhYSLwDRAQADAAMKERfYEgHXAAAAAA==.Talonted:BAAANQAECgIIAgAAAA==.Tansu:BAAANQADCgcIDQAAAA==.Taterpuff:BAAANQABCgUIBQAAAA==.Taupo:BAAANQAECgEIAgAAAA==.Taxidermy:BAAANQADCgYIDAAAAA==.',
Te='Telarinda:BAAANQAECgcICQAAAA==.',
Th='Thametal:BAAANQADCgQIBAAAAA==.Thicclich:BAAANQAECgcICgAAAA==.Thicktotem:BAAANQAECgEIAQAAAA==.Thickumz:BAAANQADCgQIBAAAAA==.Thinmint:BAAANQADCgcICQAAAA==.Thisismeta:BAAANQAECgYICgAAAA==.Thorynwar:BAACNQAFFH8YAAIMAAYKIB5zCQAXAgAMAAYKIB5zCQAXAgA1AAQKfyYAAgwACQouIAgWAGADAAwACQouIAgWAGADAAE1AAUUBQgNACMAIhQA.Thorýn:BAACNQAFFH8NAAMjAAUKIhRBDgAkAQAjAAQKIhRBDgAkAQAUAAEKAADcJwBXAAA1AAQKfyUAAyMACQpzJmEQADMDACMACQpzJmEQADMDABQABwriGXJGAN0BAAAA.Thórin:BAAANQAECgYIDQAAAA==.',
Ti='Tierax:BAABNQAECn8nAAMVAAkK2B4fCQDiAgAVAAgKdCAfCQDiAgASAAMKhhZdcwDbAAAAAA==.Tipsy:BAABNQAECn8gAAIGAAgKjRILZADeAQAGAAgKjRILZADeAQAAAA==.',
To='Tojì:BAAANQAECggIEAAAAA==.Tomfoolary:BAAANQADCgQIBAAAAA==.Tonathul:BAAANQADCggIEAAAAA==.Torrk:BAAANQAECgQIBAAAAA==.Torultrear:BAAANQAECgIIAgAAAA==.Tot:BAABNQAECn8hAAIGAAgKtw2pfQCPAQAGAAgKtw2pfQCPAQAAAA==.',
Tr='Tralleth:BAABNQAECn8YAAMIAAcKJRnrCwCZAQAIAAYKgBfrCwCZAQAHAAYKJw4gLABFAQAAAA==.Trallock:BAAANQADCggIDwAAAA==.Traumatized:BAAANQADCgUIBwAAAA==.Truska:BAAANQABCgEIAQAAAA==.',
Tu='Tuskyrex:BAAANQAECgEIAQAAAA==.',
Tw='Twinklord:BAAANQAECgYIDAAAAA==.Twostroke:BAABNQAECn8fAAIDAAkKNyOkBgCoAwADAAkKNyOkBgCoAwAAAA==.Twretwtwrewr:BAAANQADCgIIAgAAAA==.Twunkie:BAAANQADCgcIBwAAAA==.',
Ty='Tylopally:BAAANQAFFAIIAgAAAA==.Tyloremixdd:BAAANQAECgQIBAAAAA==.Tylototem:BAAANQAECgQIBAAAAA==.',
['Tö']='Tötem:BAAANQADCgMIAwABNQAFFAUIBgAPAE0gAA==.',
Uj='Ujcpet:BAAANQADCgYIBgAAAA==.',
Un='Uncookedham:BAAANQADCgYIEAAAAA==.Underhorn:BAAANQADCggIDgAAAA==.',
Va='Vaas:BAAANQADCggICAABNQAECgkJHwAhAEogAA==.Vaeelrundor:BAABNQAECn8UAAIDAAUKGgq48gAXAQADAAUKGgq48gAXAQAAAA==.Valyr:BAAANQADCgQIBAAAAA==.Vampslayer:BAAANQADCgYIBgAAAA==.Vanillaface:BAAANQAECgQIBAAAAA==.Vañillaface:BAAANQABCgQIBgAAAA==.',
Ve='Vedebone:BAAANQAECgUIDAAAAA==.Vedexd:BAABNQAECn8nAAIDAAcK5g+VngDFAQADAAcK5g+VngDFAQAAAA==.Velarael:BAABNQAECn8ZAAIcAAYKzRKdDQB8AQAcAAYKzRKdDQB8AQAAAA==.Veletharia:BAAANQADCgQIBAAAAA==.Velexi:BAAANQADCgQIBwAAAA==.',
Vl='Vlidya:BAAANQADCgEIAQAAAA==.',
Vo='Voidberg:BAAANQADCggJDgAAAA==.',
Vs='Vs:BAAANQAECggIDgAAAA==.',
Wa='Wachonaso:BAACNQAFFH8HAAIWAAQKgQtMGQAvAQAWAAQKgQtMGQAvAQA1AAQKfygAAxYACQoEHTw+AJUCABYACQqAHDw+AJUCABsAAwokHaQwAAQBAAAA.Wastedsage:BAAANQAECgUICAAAAA==.Waterlou:BAAANQADCgYIBwAAAA==.',
Wh='Whatuphuz:BAAANQADCggIEAAAAA==.Wheresmyjaw:BAABNQAECn8oAAMWAAkKrB0qPACcAgAWAAgKaB8qPACcAgAbAAMKbRMEPQDMAAAAAA==.',
Wi='Wildthree:BAAANQAECgYIEwAAAA==.Wilkieswar:BAAANQADCggIGAABNQAECgkJKAARAGAeAA==.Willenda:BAAANQAECgEIAgAAAA==.Winterfall:BAAANQADCggIFQAAAA==.',
Wu='Wuinn:BAACNQAFFH8OAAIHAAYKfQlzCQCVAQAHAAYKfQlzCQCVAQA1AAQKfx0AAgcACQqUFGIVAFwCAAcACQqUFGIVAFwCAAAA.',
Xa='Xakutioner:BAABNQAECn8rAAICAAkKZB1dFAAjAwACAAkKZB1dFAAjAwAAAA==.Xaldiir:BAABNQAECn8eAAIEAAgKbh7SHACvAgAEAAgKbh7SHACvAgAAAA==.',
Xe='Xenvoroo:BAAANQADCgIIAgAAAA==.Xerexia:BAABNQAECn88AAIMAAgKJw4xoQDFAQAMAAgKJw4xoQDFAQAAAA==.',
Xw='Xwoo:BAAANQAECgIIAgAAAA==.',
Xz='Xzarlatan:BAAANQADCgIIAgAAAA==.Xzarlatanfi:BAAANQADCgUIBQAAAA==.',
Ya='Yahro:BAAANQAECgcIEQAAAA==.',
Ye='Yellowranger:BAABNQAECn8qAAIQAAkKcRmFLQCuAgAQAAkKcRmFLQCuAgAAAA==.',
Yj='Yjn:BAAANQAECggIDQAAAA==.',
Yo='Yongyong:BAAANQAECgQIDQAAAA==.Yotoymuerto:BAAANQAECgEIAQAAAA==.',
Yu='Yunara:BAAANQAECgYIBgAAAA==.Yustayoke:BAABNQAECn8mAAIRAAgKihR0rQAmAgARAAgKihR0rQAmAgAAAA==.',
Za='Zalvianna:BAAANQAECgUIBwAAAA==.Zarathoz:BAAANQABCgYJBgAAAA==.Zarshx:BAAANQADCgQICAABNQAECgYIBgAOAAAAAA==.',
Ze='Zennith:BAAANQAECggICQAAAA==.Zennithz:BAAANQAECggIEAAAAA==.Zeonz:BAAANQAECgEIAQAAAA==.',
Zi='Zilong:BAAANQAECgEIAQABNQAFFAcIDQAMADkTAA==.Zilongmage:BAAANQAECgYIBgABNQAFFAcIDQAMADkTAA==.Zilongwar:BAACNQAFFH8NAAIMAAcKORNMCwD3AQAMAAcKORNMCwD3AQA1AAQKfxwAAgwACQopIgcsAAoDAAwACQopIgcsAAoDAAAA.',
Zo='Zombor:BAAANQADCgIIAgAAAA==.Zonecw:BAAANQAECgcIDgAAAA==.Zonedk:BAAANQAECgQIBgABNQAECgcIDgAOAAAAAA==.',
['Ør']='Ørsted:BAAANQADCgIIAgABNQAECgEIAgAOAAAAAA==.',
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
