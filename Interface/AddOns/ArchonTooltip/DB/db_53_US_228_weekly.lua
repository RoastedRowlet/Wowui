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

local lookup = {'Hunter-Survival','DeathKnight-Frost','Priest-Holy','Priest-Shadow','DeathKnight-Blood','Warlock-Affliction','Hunter-BeastMastery','Unknown-Unknown','Warrior-Fury','Warrior-Arms','Monk-Mistweaver','Shaman-Restoration','Druid-Restoration','Druid-Balance','DeathKnight-Unholy','Druid-Feral','DemonHunter-Devourer','Warlock-Demonology','Warlock-Destruction','Paladin-Retribution','Paladin-Protection','Druid-Guardian','Shaman-Elemental','Rogue-Subtlety','DemonHunter-Havoc','Monk-Brewmaster','Hunter-Marksmanship','Mage-Frost','Evoker-Devastation','Mage-Arcane','Monk-Windwalker','DemonHunter-Vengeance','Evoker-Preservation',}
local provider = {region='US',realm='Uldaman',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abasi:BAAANQABCgQIBAAAAA==.',
Ad='Ademar:BAABNQAECn8zAAIBAAoKxR6xAgADAwABAAoKxR6xAgADAwABNQAFFAIIBgACAPoVAA==.',
Al='Alkie:BAAANQAECgMIAgAAAA==.Allectra:BAABNQAECn8fAAMDAAgKRhNwdwBcAQADAAYKeBVwdwBcAQAEAAcKQRDPJwAuAQAAAA==.Allupinya:BAAANQAECgQIBAABNQAECgoKKgAFACYdAA==.',
Am='Amarie:BAAANQABCgMIAwAAAA==.Amnon:BAABNQAECn81AAIGAAoKcxYiBQB4AgAGAAoKcxYiBQB4AgAAAA==.',
An='Anáthema:BAAANQADCgQIAwAAAA==.',
Aq='Aquianna:BAAANQABCgQIBgAAAA==.',
Ar='Arath:BAAANQADCggICQAAAA==.Arielsz:BAAANQAECgEIAQAAAA==.',
As='Asanath:BAAANQADCgYJBQAAAA==.Ashlara:BAAANQAECgYICgAAAA==.',
Au='Ausha:BAAANQADCggICAAAAA==.',
Az='Azdaja:BAAANQADCgQIBAAAAA==.Azulå:BAACNQAFFH8JAAIHAAQKVgnAFgDLAAAHAAQKVgnAFgDLAAA1AAQKf1MAAgcACgqMJX8MAHoDAAcACgqMJX8MAHoDAAAA.',
Ba='Baadkitty:BAAANQADCgQIBAAAAA==.Baalzaas:BAAANQADCgMIAwAAAA==.Baltik:BAAANQADCgMIAQAAAA==.Bandwidth:BAAANQADCgUIBQABNQAECgUIDAAIAAAAAA==.',
Be='Becomedeath:BAAANQABCgcICwAAAA==.Bellachai:BAAANQAECgUIDAAAAA==.Benm:BAAANQADCgcIBwABNQAECgoKQwADAMEhAA==.Berastu:BAABNQAECn9FAAMJAAoKQhndBQC7AgAJAAoKQhndBQC7AgAKAAoKTxLdTQADAgAAAA==.Bergalicious:BAAANQAECgUICAAAAA==.',
Bl='Bludmace:BAAANQABCgcICQAAAA==.',
Bo='Booz:BAAANQAECgUIBQAAAA==.Bowdacious:BAABNQAECn8XAAMHAAkK9g+CcgC+AQAHAAgKDBGCcgC+AQABAAUK6gmFCwDmAAABNQAECgoKKgAFACYdAA==.',
Bu='Bugabooed:BAAANQADCggICgAAAA==.',
Ca='Callee:BAAANQAECgEIAQAAAA==.Calyse:BAAANQADCgYIBgAAAA==.Casima:BAAANQAECgEIAwAAAA==.',
Ch='Cheydinhal:BAABNQAECn81AAIDAAoKWQmxdQC7AQADAAoKWQmxdQC7AQAAAA==.Cheydinhalas:BAAANQADCgQIBgAAAA==.Chichi:BAABNQAECn8cAAILAAcK9xpxFwAGAgALAAcK9xpxFwAGAgAAAA==.Chicknwaffle:BAAANQAECgYIDgAAAA==.Chumlee:BAAANQAECgEIAQAAAA==.Chunks:BAAANQAECgUIDQAAAA==.',
Co='Colleague:BAAANQAECgUIDAAAAA==.Cornmoon:BAAANQADCggIKAAAAA==.Corychasè:BAAANQAECgEIAQABNQAECgEIAgAIAAAAAA==.',
Cr='Creamed:BAAANQAECgUIBgABNQAECgoKMAAHANIYAA==.Crewgy:BAAANQADCgIIAgABNQADCggICAAIAAAAAA==.',
Da='Dafukisdis:BAAANQADCgcICgAAAA==.Dahlianna:BAAANQAECgEIAQAAAA==.Darksushi:BAAANQAECgUIDAAAAA==.Dashamana:BAABNQAECn8wAAIMAAoKiRZCJwB7AgAMAAoKiRZCJwB7AgAAAA==.',
De='Deathbear:BAABNQAECn8jAAMNAAcKJRsuLQBpAQANAAYKZhsuLQBpAQAOAAMKhwubbgBmAAAAAA==.Demacia:BAAANQADCggIDgABNQAFFAUICgAPALYLAA==.',
Dh='Dhabyss:BAAANQADCgIIAgABNQAECggIOQAIAAAAAA==.',
Di='Dimensionul:BAAANQAECgEIAQAAAA==.Dimensiònal:BAAANQADCgMIAwAAAA==.Dinbek:BAAANQAECgUICAAAAA==.Dindroc:BAAANQADCggICAAAAA==.Displacement:BAAANQADCgQIBAABNQAECgUIDAAIAAAAAA==.Disruptive:BAAANQAECggIAgAAAA==.Distortion:BAAANQABCgMIAQABNQAECgUIDAAIAAAAAA==.',
Do='Dordis:BAABNQAECn8mAAIQAAkK0h7bBwBgAgAQAAkK0h7bBwBgAgAAAA==.',
Dr='Dragonflamz:BAAANQAECgEIAQAAAA==.Drashammy:BAAANQADCggIEAAAAA==.',
Du='Duckmyass:BAAANQADCgMIAwAAAA==.Dusksurge:BAAANQADCggIBwAAAA==.',
['Dÿ']='Dÿmmensional:BAAANQAECgMIAwAAAA==.',
Ec='Eclipze:BAABNQAECn9CAAMEAAoKvBiIFgDkAQAEAAoKvBiIFgDkAQADAAYKMBMnbgB6AQAAAA==.Eclipzee:BAABNQAECn8XAAIRAAgKkA9iKAA/AQARAAgKkA9iKAA/AQABNQAECgoKQgAEALwYAA==.Eclipzé:BAABNQAECn8YAAQGAAkKvRdmBABBAgAGAAkKvRdmBABBAgASAAMKXQwg7wBlAAATAAEKSge3fgAuAAABNQAECgoKQgAEALwYAA==.Eclípze:BAAANQADCgcIBwABNQAECgoKQgAEALwYAA==.',
Ei='Eifel:BAABNQAECn8cAAMUAAcKZSGfZwBlAgAUAAcKZSGfZwBlAgAVAAEKsR78YQBVAAAAAA==.',
El='Elaure:BAAANQADCgYIBgABNQAFFAQICAAFAIocAA==.Elenna:BAAANQAECgEIAgABNQAECgoKOgANAMAiAA==.Elessardan:BAABNQAECn86AAQNAAoKwCKsCAA6AwANAAoKwCKsCAA6AwAWAAgKUhQ/FwD5AQAOAAIKVgeJpABRAAAAAA==.',
En='Endilli:BAABNQAECn8WAAIXAAcKfATKmADBAAAXAAcKfATKmADBAAABNQAECgoKOQAUABIhAA==.',
Eq='Equinoxis:BAEANQAECgYICwABNQAFFAcIGwAEAIIPAA==.',
Eu='Euria:BAAANQAECggIEAABNQAFFAYIFQAFAHkRAA==.',
Ev='Everwolf:BAAANQAECgEIAwAAAA==.',
Ey='Eyeeball:BAAANQADCgcJBwAAAA==.',
Fa='Fallynangel:BAABNQAECn8uAAIYAAcK7gwjKwBqAQAYAAcK7gwjKwBqAQAAAA==.',
Fi='Filho:BAAANQAECgQIBQAAAA==.',
Fo='Foxptm:BAAANQAECgcIDgAAAA==.',
Fr='Frastbert:BAAANQABCgEIAQAAAA==.Friedtips:BAAANQADCgQIAwABNQAFFAMICAAZALQLAA==.Frostymilk:BAABNQAECn83AAIOAAoK2RsYGAA9AgAOAAoK2RsYGAA9AgAAAA==.',
Fu='Furmidable:BAAANQAECgEIAQABNQAECggILQAaAJYfAA==.',
Ga='Galvek:BAACNQAFFH8IAAMbAAQKTAmFFwB1AAAbAAIKLgiFFwB1AAAHAAIKiAtYMwBDAAA1AAQKfy0AAxsACgolGQ4tAOMBABsACQo4Ew4tAOMBAAcABQqtHYimAEoBAAAA.Garjzlaa:BAAANQAECgQIBgAAAA==.Garugamesh:BAAANQAECgMIBwAAAA==.Gas:BAAANQAECgEIAQAAAA==.',
Gh='Ghanjamon:BAAANQABCgYICQAAAA==.',
Gi='Gigglecups:BAAANQAECgIIBQAAAA==.',
Gl='Glutton:BAAANQAECgEIAgAAAA==.',
Gr='Greenfoam:BAAANQADCgMIAwAAAA==.Greyswandir:BAABNQAECn8cAAIHAAgK6gWJxwAIAQAHAAgK6gWJxwAIAQAAAA==.',
Gw='Gwarr:BAABNQAECn8cAAIKAAkKKhmaTAAHAgAKAAkKKhmaTAAHAgAAAA==.Gwendolynn:BAABNQAECn8mAAIDAAoKCRkkSgBHAgADAAoKCRkkSgBHAgAAAA==.',
Ha='Hailyea:BAABNQAECn84AAIcAAkKfxZNCQBBAgAcAAkKfxZNCQBBAgAAAA==.Harvie:BAAANQAECgEIAQABNQAECggIHAAHAOoFAA==.Haskar:BAAANQAECgEIAwAAAA==.Havøc:BAAANQADCgQIBwABNQAECgcICQAIAAAAAA==.Haylee:BAAANQAECgEIAQAAAA==.',
He='Healydan:BAAANQADCgUIBQAAAA==.',
Hi='Hitchlock:BAAANQAECgEIAQABNQAECgkJHAAKACoZAA==.',
Ho='Holii:BAAANQADCgUIBwAAAA==.',
Hu='Husky:BAAANQAECgIIAgABNQAECgUIDQAIAAAAAA==.',
Hy='Hyage:BAAANQAECgcIBwABNQAFFAEIAQAIAAAAAA==.',
['Hó']='Hótpockets:BAAANQAECgEIAQABNQAECggIEAAIAAAAAA==.',
Id='Idfc:BAAANQADCgQIBAAAAA==.',
Il='Ilovesanta:BAAANQAECgUIDQAAAA==.',
In='Indigobleue:BAABNQAECn9HAAIDAAoK8SO/CACbAwADAAoK8SO/CACbAwAAAA==.Inurfacepaly:BAAANQAECggIBAAAAA==.',
Iv='Ivyamituofo:BAAANQAECgcIDAAAAA==.',
Je='Jemera:BAAANQADCgUIBQAAAA==.',
Ji='Jinkalou:BAAANQAECgEIAQABNQAECggILQAaAJYfAA==.Jinsun:BAAANQADCggIEAAAAA==.Jinzun:BAAANQADCgYICQAAAA==.Jiñ:BAAANQADCgUICAAAAA==.',
Ka='Kabbitha:BAAANQADCgEIAQAAAA==.Kahuma:BAAANQAECgEIAgAAAA==.Kalzdemar:BAACNQAFFH8GAAICAAIK+hVIFwCGAAACAAIK+hVIFwCGAAA1AAQKfz8AAwIACgp8JVMDAK4DAAIACgp8JVMDAK4DAA8ABQoFFDGKAPoAAAAA.Karnoviaa:BAAANQADCgUICAAAAA==.',
Ke='Keldanor:BAAANQAECgEIAQAAAA==.',
Kh='Kheann:BAAANQADCgYIBgAAAA==.Khärdeen:BAAANQAECgEIAQAAAA==.',
Ki='Kimjongheals:BAABNQAECn8kAAIDAAkKFB3QKwC5AgADAAkKFB3QKwC5AgAAAA==.Kissey:BAAANQADCgEIAQAAAA==.',
Ko='Konjar:BAAANQADCgUIBAAAAA==.',
Ku='Kungpowpoee:BAAANQADCgEIAQAAAA==.',
Ky='Kyrak:BAABNQAECn8jAAINAAgK3xf/GAAuAgANAAgK3xf/GAAuAgAAAA==.',
La='Lainey:BAABNQAECn9JAAIHAAoKnh5lHwC1AgAHAAoKnh5lHwC1AgAAAA==.Landocamando:BAAANQAECgUIDAAAAA==.',
Le='Lerya:BAABNQAECn8ZAAIdAAoK1gyHFwDRAQAdAAoK1gyHFwDRAQAAAA==.Lessa:BAAANQADCgQIBAAAAA==.Lexnn:BAABNQAECn9AAAMRAAoKvRSTIQA/AgARAAoKvRSTIQA/AgAZAAIKhQkWbQBiAAAAAA==.',
Li='Lifedrynker:BAAANQADCgUIBQAAAA==.Ligetnoone:BAAANQAECgEIAQABNQAECgIIAwAIAAAAAA==.Lighte:BAABNQAECn8yAAMcAAoKHCEWAwAgAwAcAAoKHCEWAwAgAwAeAAEKAADSxgE1AAAAAA==.Lillïth:BAAANQAECgEIAQAAAA==.',
Lo='Logicx:BAAANQAECgQIEgABNQAECgcIJwAVAKYXAA==.Lorin:BAAANQAECgEIAQAAAA==.',
Lu='Lunalia:BAAANQADCgYIBgAAAA==.Lunarrastorm:BAAANQAECgYIEgAAAA==.Lunarìa:BAAANQAECggICQAAAA==.',
['Lê']='Lêssa:BAAANQAECgEIAgAAAA==.',
Ma='Magici:BAABNQAECn8WAAIcAAcKyApCGAAGAQAcAAcKyApCGAAGAQAAAA==.Maraposaa:BAAANQAECggICAAAAA==.Marraud:BAAANQAECgEIBAAAAA==.Mavren:BAAANQAECgUIEAAAAA==.',
Me='Mellesaun:BAAANQADCgMIAwAAAA==.Mephístø:BAABNQAECn8qAAMXAAcKHSPWLADKAgAXAAcKHSPWLADKAgAMAAcKpRaSgQCHAQABNQAECgkJLAADAMMjAA==.Merie:BAAANQABCgQIBAAAAA==.Mewtwo:BAAANQAECgMIAwABNQAFFAgIGAAHAFocAA==.',
Mi='Micali:BAABNQAECn8vAAIUAAoKShrPdQBCAgAUAAoKShrPdQBCAgAAAA==.Mirrën:BAAANQAECgEIAwAAAA==.Mithrios:BAAANQAECgIIAgABNQAECggICgAIAAAAAA==.Mizztress:BAAANQAECgEIAQAAAA==.',
Mo='Monoris:BAAANQADCgcICwAAAA==.Moonk:BAAANQADCggIFAAAAA==.Moonsaw:BAACNQAFFH8HAAIfAAUKdRdUDwCWAAAfAAUKdRdUDwCWAAA1AAQKf0cAAh8ACgrJIj8EAJADAB8ACgrJIj8EAJADAAAA.Morgarlan:BAABNQAECn9DAAIDAAoKwSFnDgBcAwADAAoKwSFnDgBcAwAAAA==.',
Mu='Mulligan:BAAANQADCgMIAwAAAA==.',
My='Mysaa:BAAANQAECgIIBAABNQADCgYIBgAIAAAAAA==.',
['Má']='Máxîmús:BAAANQABCgEIAQAAAA==.',
['Mï']='Mïck:BAAANQAECgQIEwAAAA==.',
Na='Narusia:BAAANQAECgEIAQAAAA==.',
Ne='Newt:BAABNQAECn88AAMRAAoKQCICBwDkAgARAAoKQCICBwDkAgAgAAIKMQRYMwAvAAABNQAFFAEIAQAIAAAAAA==.',
Ni='Ninkasi:BAABNQAECn8aAAIfAAgK5xLoKQDPAQAfAAgK5xLoKQDPAQAAAA==.Nishikki:BAECNQAFFH8bAAIEAAcKgg/mBQDQAQAEAAcKgg/mBQDQAQA1AAQKf1AAAgQACgq2Jb4BAGsDAAQACgq2Jb4BAGsDAAAA.',
No='Nohaytotems:BAAANQAECgUIBQAAAA==.Noomrats:BAAANQABCgQIAgAAAA==.',
Ny='Nydie:BAABNQAECn8nAAIVAAoKKw+mJwChAQAVAAoKKw+mJwChAQAAAA==.',
Om='Omegon:BAAANQAECgEIAQAAAA==.',
Pa='Pallyrocker:BAAANQAECgIIBQAAAA==.Papally:BAAANQAECgMIBAAAAA==.',
Pe='Penumbral:BAAANQAECgQICQAAAA==.Peterios:BAAANQADCgYIBgABNQAFFAcIHAAMAIohAA==.',
Ph='Phalst:BAAANQABCgMIBQAAAA==.Phibalan:BAAANQAECgEIAwAAAA==.Phyeo:BAAANQADCgcICwABNQAECgoKRwAUAAETAA==.',
Pi='Pixishot:BAAANQADCggIGgAAAA==.',
Pl='Plagueia:BAAANQADCggIDwAAAA==.',
Pr='Prestolight:BAAANQABCgIIAgABNQAECgoKKgAFACYdAA==.',
Pu='Pubba:BAAANQAECgYIEQABNQAECgYIEQAIAAAAAA==.Pubbatis:BAAANQAECgYIEQAAAA==.',
['Pá']='Páin:BAAANQABCgEIAQAAAA==.',
Ra='Radiator:BAAANQADCgYIEAABNQAECgUIDAAIAAAAAA==.Raelyndria:BAAANQAECgQICQAAAA==.Rampart:BAAANQAECgEIAQAAAA==.Ratraxx:BAAANQAECgcIEgABNQAECggILQAaAJYfAA==.Ravagen:BAAANQAECgEIAQAAAA==.',
Re='Redrogue:BAABNQAECn8kAAITAAcKNgd7EgC5AAATAAcKNgd7EgC5AAAAAA==.Reiko:BAAANQADCgEIAQAAAA==.Renjanà:BAAANQAECgUIBQAAAA==.',
Ri='Riftan:BAABNQAECn88AAIPAAoKyBfiMQBlAgAPAAoKyBfiMQBlAgAAAA==.Riviee:BAAANQADCggIGgAAAA==.',
Ro='Roderígo:BAAANQADCgEIAQAAAA==.Rogun:BAABNQAECn84AAIbAAoK9woNGQCsAQAbAAoK9woNGQCsAQAAAA==.Roredge:BAABNQAECn8tAAMaAAgKlh+ECACiAgAaAAgKlh+ECACiAgAfAAgKtBl3IQAgAgAAAA==.',
Ru='Ruff:BAAANQAECgQIBAAAAA==.',
['Rö']='Rögnvaldr:BAAANQAECgEIAwAAAA==.',
Sa='Sarann:BAABNQAECn8kAAMNAAkKDAtgMwCAAQANAAkKDAtgMwCAAQAOAAEKLQKztwAqAAAAAA==.',
Sc='Scarypoppins:BAABNQAECn8qAAIFAAoKJh2bHAAKAgAFAAoKJh2bHAAKAgAAAA==.',
Se='Seanç:BAAANQABCgYICgAAAA==.',
Sh='Shagster:BAAANQADCgYIBgAAAA==.Shamoomoo:BAAANQADCggICAAAAA==.Sharrell:BAAANQADCgIIAgAAAA==.Shazzamo:BAAANQAECgEIAQABNQAECgcIDwAIAAAAAA==.Sheraania:BAAANQADCgUIBQAAAA==.Shoripan:BAAANQAECgEIAQAAAA==.',
Si='Silvertrees:BAABNQAECn8oAAINAAcK8wfFPgD4AAANAAcK8wfFPgD4AAAAAA==.',
Sk='Skorpius:BAABNQAECn8cAAISAAgKEwZttwDQAAASAAgKEwZttwDQAAAAAA==.',
Sl='Slaytanic:BAABNQAECn8iAAMUAAcKzA826QBJAQAUAAcKzA826QBJAQAVAAEKAAAefwAeAAAAAA==.Slingshot:BAAANQAECggICAAAAA==.Slymick:BAAANQADCgYICwABNQAECgQIEwAIAAAAAA==.',
Sn='Snoka:BAABNQAECn9HAAIUAAoKARP6agDoAQAUAAoKARP6agDoAQAAAA==.',
So='Solora:BAABNQAECn8kAAIXAAcKlwaUjwDVAAAXAAcKlwaUjwDVAAAAAA==.',
Sp='Sparklesky:BAAANQADCgYICQAAAA==.',
St='Stankyy:BAAANQAFFAEIAQAAAA==.Starí:BAAANQADCgYIBwAAAA==.Strawry:BAAANQADCgcIDAAAAA==.',
Su='Sunjiwung:BAAANQAECgMIAgAAAA==.Supadin:BAAANQADCgIIAgAAAA==.',
Sy='Sylanan:BAAANQAECgUIBwAAAA==.Syrüs:BAACNQAFFH8IAAIZAAMKtAssDwC/AAAZAAMKtAssDwC/AAA1AAQKfzMAAhkACgrZHHUhAJACABkACgrZHHUhAJACAAAA.',
['Sã']='Sãrik:BAAANQADCgMIAwAAAA==.',
Ta='Tasty:BAAANQAECgQIBAABNQAFFAcIEQAbAJITAA==.',
Te='Temuraire:BAAANQADCgUIBgAAAA==.Tethyssra:BAAANQADCgYICwABNQAECgUIDAAIAAAAAA==.',
Th='Thalyra:BAABNQAECn8iAAIRAAgKxhrVJAAgAgARAAgKxhrVJAAgAgAAAA==.Thestar:BAAANQADCgQICgAAAA==.Thirstrap:BAABNQAECn87AAIZAAoKhREWJQDNAQAZAAoKhREWJQDNAQAAAA==.Thorge:BAABNQAECn8ZAAMBAAgKZw+2CAC9AQABAAcKEA+2CAC9AQAHAAcKnwwtuQCRAQAAAA==.Thíngtwo:BAAANQADCgUIBQAAAA==.',
Ti='Tiltawhirl:BAAANQAECgMIBQAAAA==.',
Tw='Twigz:BAAANQABCgYICQAAAA==.',
Um='Umahpriest:BAAANQADCgQIBAAAAA==.',
Un='Unclerukus:BAAANQADCgMIAwAAAA==.Unnserra:BAAANQAECgQIBQABNQAECgkJHwAhAFkPAA==.Unrestraind:BAAANQAECgUIEQAAAA==.Unrêstrained:BAAANQADCgcICQAAAA==.',
Va='Valeska:BAAANQADCgMIAwAAAA==.',
Ve='Vennt:BAACNQAFFH8VAAIbAAcKpR4oBQARAgAbAAcKpR4oBQARAgA1AAQKf1YAAhsACgqFJFcCAEIDABsACgqFJFcCAEIDAAAA.Ventt:BAAANQADCggIDgABNQAFFAcIFQAbAKUeAA==.Veredelyse:BAAANQADCgQIBAABNQAECgkJHwAhAFkPAA==.',
Vu='Vuhdostev:BAAANQAECggIEAAAAA==.',
Wa='Warpéd:BAAANQABCgQIAwAAAA==.Wartraxx:BAAANQAECgIIAgABNQAECggILQAaAJYfAA==.Wayme:BAAANQADCggIGgAAAA==.',
We='Wensa:BAAANQAECgEIAQAAAA==.',
Wi='Wizzlord:BAAANQAECgUICQAAAA==.',
Wo='Woghog:BAAANQAECgYIDgAAAA==.Wotlk:BAAANQADCgQIBQAAAA==.',
Xa='Xahle:BAABNQAECn9BAAQPAAoKoRj2EQBcAgAPAAoKoRj2EQBcAgAFAAcKPAdKTgD2AAACAAEK8AJsvwAdAAAAAA==.',
Ya='Yaboì:BAAANQADCgQIBAAAAA==.',
Za='Zareck:BAAANQADCgYIBgAAAA==.',
Ze='Zendayah:BAAANQADCggIDAAAAA==.Zent:BAAANQAECgUIBwAAAA==.Zephie:BAAANQADCgYIBgABNQAECggIGgAfAOcSAA==.',
Zi='Zitillidan:BAACNQAFFH8FAAIZAAIKfA4PFQByAAAZAAIKfA4PFQByAAA1AAQKfywAAhkACgphHTAfAKACABkACgphHTAfAKACAAE1AAUUAggGAAIA+hUA.',
Zo='Zogo:BAAANQADCgIIAgAAAA==.',
['Ör']='Öreö:BAAANQADCggICQAAAA==.',
['ße']='ßeech:BAAANQAECgEIAgAAAA==.',
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
