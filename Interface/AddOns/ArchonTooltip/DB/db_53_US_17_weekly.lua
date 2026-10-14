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

local lookup = {'Warrior-Arms','Warrior-Protection','Warrior-Fury','Shaman-Elemental','Rogue-Assassination','Hunter-BeastMastery','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Priest-Holy','Warlock-Destruction','Warlock-Demonology','DemonHunter-Vengeance','Mage-Arcane','DemonHunter-Devourer','Evoker-Devastation','Unknown-Unknown','Paladin-Holy','Mage-Frost','DemonHunter-Havoc','Druid-Restoration','Shaman-Restoration','Paladin-Retribution','Monk-Windwalker','Priest-Shadow','Monk-Mistweaver','Warlock-Affliction','Evoker-Augmentation','Rogue-Subtlety','Monk-Brewmaster','Druid-Balance','Druid-Feral','Paladin-Protection',}
local provider = {region='US',realm='Archimonde',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aanaleaa:BAAANQADCggIGwAAAA==.',
Ad='Ad:BAABNQAECn8oAAQBAAkKrh92MwDwAgABAAkKrh92MwDwAgACAAEK2Br5PABMAAADAAIK+ASjLgBDAAAAAA==.Adellon:BAABNQAECn8aAAIEAAkKzht+NACjAgAEAAkKzht+NACjAgAAAA==.Adhar:BAAANQADCgYIEAAAAA==.Adrielle:BAAANQAECgUIBwAAAA==.',
Ak='Akakage:BAABNQAECn8UAAIFAAcKYRyFKgA8AgAFAAcKYRyFKgA8AgAAAA==.Akakaji:BAAANQAECgYIBwABNQAECgcIFAAFAGEcAA==.Akutoku:BAABNQAECn8YAAIGAAgKKxf5XQBZAgAGAAgKKxf5XQBZAgAAAA==.',
An='Anaki:BAAANQADCggIDAAAAA==.Annakkin:BAABNQAECn8cAAQHAAcKkg3nawDmAAAHAAQKJw/nawDmAAAIAAUKngoukADjAAAJAAIKUANUvgBIAAAAAA==.',
Ar='Ar:BAABNQAECn8dAAIKAAgKHBTlTQA4AgAKAAgKHBTlTQA4AgABNQAECgkJKAABAK4fAA==.Archon:BAABNQAECn8vAAMBAAgKgiAVOQDeAgABAAgKgiAVOQDeAgADAAEKJR3PKwBSAAAAAA==.Arienca:BAABNQAECn8lAAMLAAgKrw2nEwDSAQALAAgKrw2nEwDSAQAMAAUKzAMZAQHDAAAAAA==.',
As='Aspir:BAEANQAECgcIDQABNQAFFAQIDAAHAPwWAA==.',
At='At:BAAANQAECgYIBwABNQAECgkJKAABAK4fAA==.',
Ba='Baidoogh:BAAANQAECgEIAQAAAA==.Barbato:BAAANQADCgcICQAAAA==.',
Be='Beavesfault:BAAANQADCgYIBgAAAA==.Beldent:BAAANQADCgYICQAAAA==.Bepis:BAABNQAECn8jAAINAAkK7SD3AgA/AwANAAkK7SD3AgA/AwAAAA==.',
Bi='Bigleif:BAAANQADCgIIAgAAAA==.Bitsakura:BAAANQADCgUICwAAAA==.',
Bl='Blazerunner:BAABNQAECn8nAAIOAAgKkA3U0ADiAQAOAAgKkA3U0ADiAQAAAA==.Blazesmasher:BAAANQAECgEIAQABNQAECggIJwAOAJANAA==.Blitzkreig:BAAANQAECgMIAwAAAA==.Blured:BAABNQAECn8xAAIPAAkKQyPrAgCqAwAPAAkKQyPrAgCqAwAAAA==.',
Bo='Booty:BAABNQAECn8mAAICAAkKPCDbBQANAwACAAkKPCDbBQANAwAAAA==.Bort:BAABNQAECn8cAAIQAAkKZweeGQCsAQAQAAkKZweeGQCsAQAAAA==.',
Br='Brevyn:BAABNQAECn8ZAAIOAAgKGAme4wC+AQAOAAgKGAme4wC+AQAAAA==.',
Bu='Bubblebutt:BAAANQAECgQICAABNQAECggIDAARAAAAAA==.Bulla:BAAANQAECgMIAwAAAA==.Bung:BAABNQAECn8jAAISAAkKXBeJQABgAgASAAkKXBeJQABgAgAAAA==.Buum:BAAANQAECgMIAwAAAA==.',
['Bä']='Bämba:BAAANQADCgcIDQABNQAECgcIGgATAKgMAA==.',
Ca='Cali:BAACNQAFFH8VAAMUAAcKBgoSCQCYAQAUAAYKhAgSCQCYAQAPAAQKFQvFCgAdAQA1AAQKfy8AAw8ACQqbIE4UAMICAA8ACQqaHk4UAMICABQABQoxIHg+AMIBAAAA.Calipari:BAAANQADCgQIBAABNQAFFAcIFQAUAAYKAA==.Catamara:BAAANQAECgIIAgAAAA==.',
Ce='Cephus:BAACNQAFFH8LAAIVAAUKKBMDBwCMAQAVAAUKKBMDBwCMAQA1AAQKfyoAAhUACQoxEoUjAAUCABUACQoxEoUjAAUCAAAA.Cerafina:BAAANQADCgUICgAAAA==.',
Ch='Chayse:BAACNQAFFH8VAAIGAAYK+hOIBQD3AQAGAAYK+hOIBQD3AQA1AAQKfy4AAgYACQo1IvUXADgDAAYACQo1IvUXADgDAAAA.Chumléé:BAAANQADCgEIAQAAAA==.Chérry:BAACNQAFFH8OAAMUAAQK5BqpDABEAQAUAAQK5BqpDABEAQAPAAEKxQotFgBAAAA1AAQKfywAAw8ACQrVIWIWAKsCAA8ACQoNHGIWAKsCABQABAoiI9VGAIsBAAAA.',
Cl='Climpwimp:BAAANQADCgUIBQAAAA==.',
Co='Conneer:BAAANQADCgUIBQAAAA==.Consham:BAABNQAECn8xAAMWAAkKoR33FQAeAwAWAAkKoR33FQAeAwAEAAUK9A2AwQAKAQAAAA==.',
Cy='Cynestra:BAAANQAECgMIAwAAAA==.Cyni:BAAANQAECgEIAQABNQAFFAQIBgASAIoRAA==.Cytheris:BAAANQADCgIIAgABNQAECgkJMQAWAKEdAA==.',
Da='Dadudadu:BAACNQAFFH8MAAIXAAUK1wcmDwBSAQAXAAUK1wcmDwBSAQA1AAQKfzYAAhcACQp6HlRFAMECABcACQp6HlRFAMECAAAA.Daftmonk:BAACNQAFFH8OAAIYAAQKRSBPBwB7AQAYAAQKRSBPBwB7AQA1AAQKfz0AAhgACQpZJUcCALoDABgACQpZJUcCALoDAAAA.Darj:BAABNQAECn8bAAIBAAkKQxXhYQBlAgABAAkKQxXhYQBlAgAAAA==.Darmonevil:BAAANQAECgQICQAAAA==.Dasarus:BAAANQAECgUICwAAAA==.Dauntless:BAAANQAECgQIBAAAAA==.',
De='Deth:BAAANQADCgYIBgABNQAECgQIBQARAAAAAA==.Dethblades:BAAANQAECgEIAQABNQAECgQIBQARAAAAAA==.Dethblow:BAAANQAECgQIBQAAAA==.Dethcurse:BAAANQADCgYIBgABNQAECgQIBQARAAAAAA==.Deuterium:BAAANQADCgYIBgAAAA==.',
Di='Disturbbed:BAAANQAECgIIAgAAAA==.Diwa:BAABNQAECn8tAAMWAAkKCwi/ewCUAQAWAAkKCwi/ewCUAQAEAAcK0AKdwQAKAQAAAA==.',
Dk='Dklot:BAABNQAECn8jAAIIAAkKtRuRMABqAgAIAAkKtRuRMABqAgAAAA==.',
Do='Doomkin:BAAANQAECgUIBgAAAA==.',
Dr='Dragcon:BAAANQADCgQIBAABNQAECgkJMQAWAKEdAA==.Draken:BAAANQAECgQIBAAAAA==.Drama:BAAANQAECgQIBgAAAA==.Draviin:BAABNQAECn8sAAIGAAkKjxwLNgDGAgAGAAkKjxwLNgDGAgAAAA==.Dreadgrave:BAABNQAECn8cAAIIAAgKfhVPUQDKAQAIAAgKfhVPUQDKAQAAAA==.Drequan:BAAANQADCgEIAQAAAA==.Driade:BAAANQADCgIJAgABNQAFFAQIBgASAIoRAA==.',
Du='Dunkyn:BAAANQAECgYIDwAAAA==.',
Eg='Egoh:BAAANQAECgYIBgABNQAFFAUIEgAZAJwiAA==.',
El='Elendryl:BAAANQADCggIEgAAAA==.',
En='Enkeke:BAABNQAECn8vAAIIAAkKDBu2LQB5AgAIAAkKDBu2LQB5AgAAAA==.',
Ep='Epitaph:BAAANQADCggIDAAAAA==.',
Er='Erena:BAAANQADCgUIBQABNQABCgIIAgARAAAAAA==.Eresanna:BAABNQAECn8ZAAIOAAgKiA9R0QDhAQAOAAgKiA9R0QDhAQAAAA==.Erf:BAABNQAECn8kAAIaAAkKXQ/QGgDQAQAaAAkKXQ/QGgDQAQAAAA==.Erinis:BAAANQADCggIGwABNQAECggIIQAUALcbAA==.',
Es='Esdeath:BAAANQAECgUIBgABNQAECggIIQAUALcbAA==.',
Ex='Extremefear:BAAANQAECgYIEwAAAA==.',
Fe='Fearious:BAACNQAFFH8PAAQbAAUKICW5BQB1AAAMAAMKVyXhGgAiAQAbAAEKAAC5BQB1AAALAAEKsiQ9FABmAAA1AAQKfxgABAwACQpjJIZkACkCAAwABgrOJIZkACkCAAsAAgpYI95HAKcAABsAAQoAAO8fAHUAAAAA.Feroond:BAAANQAECgcIEAAAAA==.Feyrah:BAAANQADCgUIBQAAAA==.',
Fr='Frogteeth:BAAANQAECgUIDQAAAA==.Frozath:BAAANQAECgIIAgAAAA==.',
Fu='Furibeav:BAAANQADCgQIBQABNQADCgYIBgARAAAAAA==.Fussypants:BAAANQAECgcIEwAAAA==.',
Ga='Gallindral:BAABNQAECn8qAAIPAAkKPBkBGwB9AgAPAAkKPBkBGwB9AgAAAA==.Gatito:BAAANQAECggIDAAAAA==.',
Ge='Genericnpc:BAAANQAECgUIDQAAAA==.Geobrando:BAABNQAECn8qAAMWAAgKsRp3PABrAgAWAAgKsRp3PABrAgAEAAUK/xQOsQAsAQAAAA==.',
Gg='Ggbrews:BAAANQAECgQIBAAAAA==.',
Gn='Gnosh:BAAANQAECgMIAwAAAA==.',
Go='Goofypally:BAAANQAECgEIAgABNQAECggIEQARAAAAAA==.',
Gr='Grippindeez:BAABNQAECn8dAAMHAAcKOxCdTAB+AQAHAAcK8Q2dTAB+AQAJAAEKhiGstABcAAAAAA==.Grêêd:BAAANQADCgQIBQAAAA==.',
Gu='Guidosarduci:BAABNQAECn8nAAMWAAcKthHHfACSAQAWAAcKthHHfACSAQAEAAIKrwM7GQFWAAAAAA==.Guiseppe:BAABNQAECn8bAAMQAAcK6Q84GwCUAQAQAAcKKA84GwCUAQAcAAMKQA5aHACAAAAAAA==.Gungfu:BAAANQADCgYIBgAAAA==.',
Ha='Harle:BAAANQAECgMIAwAAAA==.Hatari:BAAANQADCgEIAQAAAA==.',
He='Heavyg:BAABNQAECn9SAAIBAAkK3BeoTACgAgABAAkK3BeoTACgAgAAAA==.',
Ho='Holyshortguy:BAACNQAFFH8LAAIKAAUKyQ36EgBvAQAKAAUKyQ36EgBvAQA1AAQKfxsAAwoACQriGTQpAMICAAoACQriGTQpAMICABkAAQoAALp/ACkAAAAA.',
Hu='Hustlermag:BAABNQAECn8rAAQMAAgK5xO3dQD8AQAMAAgK+hC3dQD8AQAbAAQKBxQNFAAHAQALAAQKghjMMAADAQAAAA==.',
Hy='Hyperion:BAAANQAECgEIAQABNQAECgQIBAARAAAAAA==.',
Ic='Icelmo:BAACNQAFFH8GAAIBAAIKrQi4MgB/AAABAAIKrQi4MgB/AAA1AAQKfyQAAgEACQpyGcxQAJQCAAEACQpyGcxQAJQCAAAA.',
Im='Impact:BAAANQADCgIJAgABNQAFFAYIEQAEAAsSAA==.',
In='Infinit:BAAANQADCggIBQAAAA==.',
Is='Isuck:BAAANQADCgcIBwABNQAECgEIAQARAAAAAA==.',
Ja='Jaskow:BAABNQAECn8hAAIVAAkK5BpGFACkAgAVAAkK5BpGFACkAgAAAA==.Jaymick:BAAANQADCggIGQAAAA==.',
Ju='Jusdatip:BAABNQAECn8cAAIdAAcKPQ4TIQDBAQAdAAcKPQ4TIQDBAQABNQAECgcIJwAWALYRAA==.',
Ka='Kalessandra:BAAANQAECgYICQAAAA==.Kameshoga:BAAANQAECgEIAQAAAA==.Karten:BAAANQAECgQICAAAAA==.',
Ke='Keir:BAAANQADCggJDAAAAA==.',
Ki='Killjoyss:BAAANQADCgYIBgAAAA==.Kimlin:BAAANQADCgMIAwAAAA==.',
Kr='Krag:BAAANQAECgQIBAABNQAECgkJJAAeAMMkAA==.Krasis:BAAANQAECggIEgAAAA==.Krazermonk:BAABNQAECn8qAAIYAAkKVRzmFACqAgAYAAkKVRzmFACqAgAAAA==.Kristysavage:BAABNQAECn8xAAIGAAkKdyP4BAC8AwAGAAkKdyP4BAC8AwAAAA==.',
Ku='Kumpell:BAAANQABCgEIAQAAAA==.',
La='Lanc:BAAANQADCggIFwAAAA==.',
Le='Leafsrock:BAAANQADCgEIAQAAAA==.Lealta:BAAANQAECgYIDQABNQAFFAUIEAAVAJwZAA==.',
Li='Lichdawg:BAACNQAFFH8QAAIHAAYKWhRRBADSAQAHAAYKWhRRBADSAQA1AAQKfyMAAgcACQrqI0MWANUCAAcACQrqI0MWANUCAAAA.Lilthorn:BAAANQADCggICQAAAA==.Lithlia:BAAANQADCgMIAQAAAA==.',
Lo='Lofometa:BAAANQADCggICgAAAA==.Lover:BAAANQAECgEIAQAAAA==.',
Lt='Ltroflcopter:BAAANQAECgEIAQABNQAFFAUICwAKAMkNAA==.',
Lu='Lubu:BAABNQAECn8hAAIUAAgKtxsfIwB+AgAUAAgKtxsfIwB+AgAAAA==.Luell:BAAANQAECgIIAgAAAA==.Lumen:BAAANQAECgUIBwAAAA==.Lumiette:BAABNQAECn8YAAICAAgKlREWFwC2AQACAAgKlREWFwC2AQAAAA==.',
Lv='Lvispriestly:BAAANQAECgEJAQABNQABCgIIAgARAAAAAA==.',
Ly='Lynai:BAABNQAECn8XAAITAAcKoA7oEQCEAQATAAcKoA7oEQCEAQAAAA==.',
['Lá']='Lándwhale:BAABNQAECn84AAMdAAkK2SU4AQC/AwAdAAkKByU4AQC/AwAFAAQKxyNqSwCOAQAAAA==.',
['Læ']='Lægolas:BAAANQAECgMIBQAAAA==.',
['Lö']='Löver:BAAANQADCggICAABNQAECgEIAQARAAAAAA==.',
Ma='Macktimus:BAABNQAECn8YAAILAAgKhhhTCAB4AgALAAgKhhhTCAB4AgAAAA==.Madeinchina:BAAANQADCgYICQAAAA==.Magickrag:BAAANQADCgMIAwABNQAECgkJJAAeAMMkAA==.Magictonyp:BAAANQADCggIFgAAAA==.Makili:BAABNQAECn9LAAMOAAkK5SEqOgATAwAOAAkK5SEqOgATAwATAAEKeAxeTwAnAAAAAA==.',
Mc='Mcfire:BAAANQAECgUIBgAAAA==.',
Me='Melotte:BAAANQAECgQIBQABNQAECgUIBQARAAAAAA==.Mepha:BAAANQADCgYIBgAAAA==.Merlîn:BAAANQADCgYIEgAAAA==.',
Mi='Mickallv:BAAANQADCgcIBwAAAA==.',
Mo='Moga:BAAANQAECgEJAQAAAA==.Mornedelth:BAAANQAECgUIBQAAAA==.',
Mu='Murad:BAAANQAECgcIBwAAAA==.',
My='Mylodon:BAAANQABCgIIAwAAAA==.Mysternia:BAAANQAECgMIAwAAAA==.',
Ni='Niade:BAACNQAFFH8GAAISAAQKihF9EQBDAQASAAQKihF9EQBDAQA1AAQKfyEAAxIACQppHS0gAOwCABIACQppHS0gAOwCABcABQpiCEckAd0AAAAA.Nitpo:BAAANQADCgYIBgAAAA==.',
No='Notorckrag:BAABNQAECn8kAAIeAAkKwyRsAQCzAwAeAAkKwyRsAQCzAwAAAA==.',
Ny='Nythor:BAAANQADCgMIAwAAAA==.Nythoz:BAAANQAFFAIIAgABNQAFFAUIEgAZAJwiAA==.',
['Nê']='Nêz:BAAANQADCgYIDAAAAA==.',
Oa='Oathbringer:BAAANQADCgYICQAAAA==.',
Od='Odimeer:BAAANQAECgYICgAAAA==.',
Of='Offbrandcleo:BAAANQABCggIDgAAAA==.',
Ok='Okibi:BAAANQAECgQIDAABNQAECggIIQAUALcbAA==.',
Ol='Oldrecipe:BAABNQAECn8hAAISAAkKtxJ9RwBGAgASAAkKtxJ9RwBGAgAAAA==.Oliange:BAABNQAECn8aAAMTAAcKqAzzEwBnAQATAAcKqAzzEwBnAQAOAAYKEAW6QwEYAQAAAA==.',
Oo='Oopsrofl:BAAANQAECgIIAwAAAA==.',
Op='Optimuze:BAAANQAECgMIBQAAAA==.',
Or='Originalgank:BAABNQAECn8lAAMOAAkKyR8pLwAuAwAOAAkKyR8pLwAuAwATAAEK9REnSgAwAAAAAA==.Orthox:BAAANQADCgUIBQAAAA==.',
Ot='Otoha:BAAANQADCgYIBgAAAA==.',
Pe='Peachcobbler:BAABNQAECn8bAAIZAAgKiAhEMQCVAQAZAAgKiAhEMQCVAQAAAA==.Peachcrumpet:BAAANQADCgEIAQAAAA==.Peppermint:BAAANQAECgUIBwAAAA==.Pewpsmadness:BAAANQAECgQIBAAAAA==.',
Pi='Pinkchadp:BAAANQADCgcJBwAAAA==.Pinkk:BAAANQAECgMIBgAAAA==.',
Pl='Plaguerism:BAABNQAECn8gAAMIAAkKCSHSDABSAwAIAAkKkiDSDABSAwAJAAMKghgAjgDHAAABNQAFFAUIDwAbACAlAA==.',
Po='Poo:BAACNQAFFH8KAAIFAAUK2BNoBgCyAQAFAAUK2BNoBgCyAQA1AAQKfywAAgUACQqsIuIIAEgDAAUACQqsIuIIAEgDAAAA.Pooq:BAAANQAECgEIAQAAAA==.Popcorn:BAAANQADCgEIAQABNQAECgIIAgARAAAAAA==.',
Pr='Promkang:BAAANQADCgUICQAAAA==.',
Pu='Puck:BAAANQADCgYIDAABNQAECggIIQAUALcbAA==.',
['Pâ']='Pâiñ:BAAANQADCggIHAAAAA==.',
Qm='Qmpell:BAAANQADCgYIBgAAAA==.',
Ra='Ragel:BAABNQAECn8dAAMfAAgK+B/uGwDnAgAfAAgK+B/uGwDnAgAVAAQK3g34TgDKAAAAAA==.Rahor:BAAANQAECgYIEQAAAA==.Rainesage:BAAANQAECgYIEwAAAA==.Ralphel:BAAANQAECgUIDQAAAA==.Razzberry:BAAANQADCgQIBAAAAA==.',
Re='Reddyeforty:BAAANQAECgYIBgAAAA==.',
Rh='Rhubarb:BAABNQAECn8eAAIBAAkKriNREwBtAwABAAkKriNREwBtAwAAAA==.',
Ro='Rohiem:BAAANQADCgMIAwAAAA==.',
Ry='Rylosh:BAACNQAFFH8YAAIVAAYKcgmxBgCVAQAVAAYKcgmxBgCVAQA1AAQKfzUAAhUACQq0FK4fACoCABUACQq0FK4fACoCAAAA.',
Sa='Sabornator:BAAANQAECgQIBAAAAA==.Sabot:BAAANQAECgMIAwABNQAECgQIBAARAAAAAA==.Sashafierce:BAAANQAECgEIAQABNQAECgIIAgARAAAAAA==.',
Sc='Scottpaladin:BAAANQAECgQICAAAAA==.',
Se='Seath:BAAANQAECgIIAgABNQAECgkJKAAHABQeAA==.',
Sh='Shamantics:BAAANQAECgEIAQABNQAFFAUIDwAbACAlAA==.Shamerica:BAACNQAFFH8RAAIEAAYKIBzPBQAeAgAEAAYKIBzPBQAeAgA1AAQKfzMAAgQACQoHJf4GAK8DAAQACQoHJf4GAK8DAAAA.Shielderon:BAAANQADCgYIBgAAAA==.Shmooythefox:BAAANQADCgYICgAAAA==.Shòckwave:BAAANQAECgEIAwAAAA==.',
Sk='Skilleaz:BAACNQAFFH8GAAIJAAQKdx7fDwBSAQAJAAQKdx7fDwBSAQA1AAQKfx8AAgkACQrZIpkPAC8DAAkACQrZIpkPAC8DAAAA.',
Sl='Slagothor:BAABNQAECn8aAAIIAAgKJAbJdABBAQAIAAgKJAbJdABBAQAAAA==.',
So='Soultax:BAAANQAECgMIAwAAAA==.',
Sp='Spekaleks:BAAANQAECgIIAwAAAA==.Spinfat:BAACNQAFFH8IAAIYAAUKphzRBgCOAQAYAAUKphzRBgCOAQA1AAQKfyYAAhgACQrTIp8KACcDABgACQrTIp8KACcDAAAA.Spiritbox:BAAANQAECgQIBAAAAA==.',
St='Stapler:BAAANQAECgYIEQAAAA==.Starbux:BAAANQAECgEIAQABNQAECgcIDgARAAAAAA==.',
Su='Sugarr:BAAANQAECgEIAQAAAA==.',
Sy='Syb:BAAANQAECgMIAwAAAA==.',
Ta='Taeyang:BAABNQAECn8jAAQMAAkKiSM8GgAbAwAMAAgKUSM8GgAbAwALAAEKlyPKYABiAAAbAAEKFiFNJgBSAAAAAA==.Tamerlein:BAAANQADCgUIBwAAAA==.Tankadin:BAAANQADCgcIBwABNQAECgcIHQAGAFgYAA==.Tanookii:BAAANQAECgEIAgAAAA==.',
Te='Terraform:BAAANQADCgEIAQAAAA==.',
Th='Theinsider:BAAANQAECgcIDwABNQAECgkJKAAHABQeAA==.Theoutsider:BAABNQAECn8oAAMHAAkKFB4NHACmAgAHAAgKyh0NHACmAgAIAAgKFRySQgAOAgAAAA==.',
Ti='Timhair:BAAANQADCgYIDgAAAA==.Tindril:BAAANQADCgYIBgAAAA==.',
To='Toekneess:BAABNQAECn8gAAIKAAkKJyXcAwCwAwAKAAkKJyXcAwCwAwAAAA==.Toekneez:BAAANQAECgcIDgABNQAECgkJIAAKACclAA==.Toekneezz:BAABNQAECn8gAAIaAAkKdSOsAwB0AwAaAAkKdSOsAwB0AwABNQAECgkJIAAKACclAA==.Totemmalotes:BAAANQADCgMIAwAAAA==.Totemofbear:BAABNQAECn8ZAAIgAAcKwRQJEgDbAQAgAAcKwRQJEgDbAQAAAA==.',
Tr='Trandis:BAABNQAECn8iAAIYAAkKniPTCABBAwAYAAkKniPTCABBAwAAAA==.Tranza:BAABNQAECn8dAAIGAAcKWBhcfgANAgAGAAcKWBhcfgANAgAAAA==.Trash:BAAANQAECgEIAQAAAA==.',
Tx='Tx:BAACNQAFFH8RAAIEAAYKCxJ6CADlAQAEAAYKCxJ6CADlAQA1AAQKfyUAAgQACQpMH28eABIDAAQACQpMH28eABIDAAAA.',
Ty='Tyrannius:BAAANQADCgUIBQAAAA==.',
Ut='Uthros:BAAANQADCgMIAwABNQAECggIHAAIAH4VAA==.Utterchaos:BAABNQAECn8XAAIhAAUKSx2IKgCFAQAhAAUKSx2IKgCFAQABNQAECgcIJwAWALYRAA==.',
Va='Vandrina:BAAANQADCgMIAwAAAA==.Vaporeon:BAAANQADCggIEQAAAA==.',
Ve='Vekris:BAAANQAECgQIBAAAAA==.',
Wa='Wazupp:BAAANQAECggICAAAAA==.',
We='Wematanye:BAAANQADCgYIEQABNQAECgcIGQAeAMgNAA==.Wetheals:BAAANQAECgcIDQAAAA==.',
Wi='Wimpykid:BAAANQADCgIIAgAAAA==.Winter:BAAANQADCgQIBAABNQAECgEIAQARAAAAAA==.',
Wo='Worgnfreeman:BAAANQAECggICAAAAA==.',
Wt='Wtfmonk:BAABNQAECn8iAAIaAAkKgxgDEAB7AgAaAAkKgxgDEAB7AgABNQAFFAUICwAKAMkNAA==.',
Xa='Xazia:BAAANQADCgEIAQAAAA==.',
Xe='Xethani:BAAANQAECgMIAwAAAA==.',
Xo='Xorcopressor:BAAANQAECgYICAABNQAECggIDAARAAAAAA==.',
Xs='Xsaber:BAAANQADCggILQAAAA==.',
Ya='Yangyin:BAAANQAECgYIBgAAAA==.Yazmo:BAACNQAFFH8SAAIZAAUKnCJ6BQDaAQAZAAUKnCJ6BQDaAQA1AAQKfyoAAhkACQpqJV4FAIEDABkACQpqJV4FAIEDAAAA.',
Yu='Yushe:BAAANQAECgIIAgAAAA==.Yuuky:BAABNQAECn8tAAIVAAkKkxseEQDIAgAVAAkKkxseEQDIAgAAAA==.',
Za='Zarivia:BAAANQADCgQIBAAAAA==.',
['Ör']='Ördög:BAAANQADCggICwAAAA==.',
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
