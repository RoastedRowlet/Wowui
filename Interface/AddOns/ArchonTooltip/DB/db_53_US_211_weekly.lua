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

local lookup = {'Paladin-Protection','Warrior-Arms','Priest-Holy','DemonHunter-Devourer','Druid-Restoration','Unknown-Unknown','Shaman-Restoration','Hunter-Survival','Druid-Balance','Paladin-Retribution','Shaman-Elemental','Mage-Arcane','Warrior-Protection','Warrior-Fury','Monk-Windwalker','Rogue-Assassination','Paladin-Holy','DemonHunter-Vengeance','Druid-Feral','Monk-Brewmaster','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Mage-Frost','DemonHunter-Havoc','Evoker-Augmentation','Monk-Mistweaver','DeathKnight-Unholy','Hunter-Marksmanship','Shaman-Enhancement','Rogue-Subtlety','DeathKnight-Frost','DeathKnight-Blood','Rogue-Outlaw','Priest-Shadow','Druid-Guardian','Evoker-Devastation','Mage-Fire','Evoker-Preservation','Priest-Discipline',}
local provider = {region='US',realm='Terenas',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abysslicker:BAAANQADCggIFAAAAA==.',
Ac='Achooe:BAABNQAECn8kAAIBAAcK5wMtMgCLAAABAAcK5wMtMgCLAAAAAA==.',
Ad='Ado:BAAANQAECgcIDwAAAA==.Adversity:BAACNQAFFH8JAAICAAUKNhzjFgCqAAACAAUKNhzjFgCqAAA1AAQKfx0AAgIACgoZIiwSANQCAAIACgoZIiwSANQCAAAA.',
Ae='Aegeus:BAAANQADCggICQAAAA==.Aenil:BAAANQADCgMIAwAAAA==.Aevintz:BAAANQAECgcICgAAAA==.',
Ai='Aiolii:BAAANQAECgUIDwAAAA==.Aisling:BAAANQADCgQIBAAAAA==.',
Ak='Akiras:BAAANQABCgYIDAAAAA==.',
Al='Alanala:BAAANQABCgQIBAAAAA==.Alcestis:BAAANQADCgIIAgAAAA==.Aldea:BAAANQAECgUIEAABNQAECgkJIAADAOoUAA==.Alyndrya:BAABNQAECn8/AAIEAAoK9BEQEgDJAQAEAAoK9BEQEgDJAQAAAA==.',
Am='Amithralia:BAABNQAECn8tAAIFAAkKBCIyBgAJAwAFAAkKBCIyBgAJAwAAAA==.',
An='Anejo:BAAANQAECgQIBAAAAA==.Ankari:BAAANQADCgEIAQAAAA==.Ansdusk:BAAANQAECgQIBgABNQAECgUICwAGAAAAAA==.Anzarna:BAAANQAECgIIAgABNQAECgUIBgAGAAAAAA==.',
Ao='Aohikari:BAAANQAECgQICAABNQAFFAcIGgAHAIkYAA==.',
Ap='Apples:BAAANQADCgMIAwAAAA==.Aprigity:BAAANQAECgYIEQAAAA==.',
Aq='Aquaten:BAABNQAECn8YAAIIAAYKQRTwCwAmAQAIAAYKQRTwCwAmAQAAAA==.',
Ar='Arashinigon:BAABNQAECn8hAAMJAAcKhAx6KABDAQAJAAcKhAx6KABDAQAFAAUKqBE6QQAdAQAAAA==.Arcafrost:BAAANQAECggIAQAAAA==.Arceus:BAAANQAECgQICAAAAA==.Arick:BAABNQAECn8UAAIKAAcKkxS7zgB+AQAKAAcKkxS7zgB+AQAAAA==.Ark:BAABNQAECn9TAAMHAAoK+iYSAAAFBAAHAAoK+iYSAAAFBAALAAEKAADSGAFdAAAAAA==.',
At='Atanker:BAAANQADCgMIAwAAAA==.',
Au='Aunn:BAAANQAECgYICgAAAA==.Aureia:BAABNQAECn8UAAMLAAkKOB24SQBQAgALAAkKOB24SQBQAgAHAAEKHA3pHAEzAAAAAA==.Auriea:BAAANQAECgQIAgABNQAECgkJFAALADgdAA==.',
Ax='Axon:BAABNQAECn8rAAIMAAgKqAo9fgBGAQAMAAgKqAo9fgBGAQAAAA==.',
Ba='Baaku:BAAANQAECgQIBgAAAA==.Baelhay:BAABNQAECn8ZAAMNAAYKAQPoNACOAAANAAYKAQPoNACOAAAOAAEKAABjOwAcAAAAAA==.Ballard:BAAANQADCgMIAwAAAA==.Barrelroll:BAAANQADCgUIBgAAAA==.Bashon:BAABNQAECn85AAMHAAoKehp6FQCbAgAHAAoKehp6FQCbAgALAAEKAAABWQEgAAAAAA==.Battlebot:BAAANQAECgUIDAAAAA==.',
Be='Beet:BAABNQAECn8wAAIPAAgKFCEyDgD7AgAPAAgKFCEyDgD7AgAAAA==.Belgaron:BAAANQAECgQIBAABNQAECgkJMwAPALoXAA==.Belitha:BAABNQAECn8rAAIEAAoKtSD3DAAUAwAEAAoKtSD3DAAUAwAAAA==.Belmaris:BAABNQAECn8nAAIQAAcKexoaFABbAQAQAAcKexoaFABbAQAAAA==.Beriana:BAAANQAECgQIBAABNQAECgkJGgARAAgRAA==.Betëlgeuse:BAAANQADCgUICQAAAA==.',
Bi='Bigcupcakes:BAAANQAECgUICgAAAA==.Bigdruid:BAAANQAECgIIAwABNQAECgUIBQAGAAAAAA==.Bimbosuzi:BAAANQAECgUIDAAAAA==.Bingbing:BAAANQADCgUIBAAAAA==.Binghealing:BAAANQADCgEIAQAAAA==.',
Bl='Blasteyes:BAABNQAECn8nAAISAAkK7hmYBgChAQASAAkK7hmYBgChAQAAAA==.Bloomharvest:BAAANQADCgEIAQAAAA==.Bluegrass:BAABNQAECn86AAITAAoK2R5UAwClAgATAAoK2R5UAwClAgAAAA==.',
Bo='Borc:BAAANQADCgcIGwAAAA==.Borik:BAABNQAECn8oAAIUAAcKziAeBAAQAgAUAAcKziAeBAAQAgAAAA==.Borknagar:BAAANQADCgcIFAAAAA==.',
Br='Brat:BAAANQADCgcIBwABNQAFFAcIIAADAOAeAA==.Brighteye:BAAANQAECgQIBAAAAA==.Brindis:BAAANQAECgUICAAAAA==.Brisket:BAAANQADCggIGwAAAA==.Brutalicious:BAAANQADCgIIAgAAAA==.',
Bu='Bubblebut:BAABNQAECn8kAAIRAAoKmh3kFwCFAgARAAoKmh3kFwCFAgAAAA==.Bubbs:BAAANQADCgQIBAABNQAECgoKNAAPAAglAA==.Buckme:BAABNQAECn8pAAIVAAoK4RiyMwDRAgAVAAoK4RiyMwDRAgAAAA==.Bulova:BAAANQAECgQIBAAAAA==.Bunnygirl:BAAANQAECgIIAgABNQAFFAcIFAAWAKIiAA==.',
By='Byungsoon:BAAANQADCgQIBAAAAA==.',
['Bà']='Bàal:BAABNQAECn8hAAMXAAoKqxJjUwBcAgAXAAoKqxJjUwBcAgAWAAEKNxFMcwA7AAAAAA==.',
Ca='Caiphage:BAAANQADCgcIBwAAAA==.Caladelm:BAAANQAECgUIDwAAAA==.Caralhan:BAAANQAECgYIDwAAAA==.Castelo:BAAANQAECgQIBAAAAA==.',
Ce='Cedra:BAABNQAECn9IAAMMAAoK9yKQGAByAwAMAAoK4CKQGAByAwAYAAIK1B3XGACrAAAAAA==.Cegeo:BAABNQAECn8sAAIWAAoKZRDLAgC1AQAWAAoKZRDLAgC1AQAAAA==.Celari:BAAANQAECgEIAQAAAA==.Celinari:BAAANQADCgEIAQAAAA==.Centric:BAAANQADCgcIBwAAAA==.',
Ch='Cheepdeeps:BAABNQAECn84AAICAAoKbxmxJQBQAgACAAoKbxmxJQBQAgAAAA==.Chelea:BAAANQADCgcICgAAAA==.Chidora:BAAANQADCgcIBwAAAA==.Chocoworm:BAAANQADCgMIAgAAAA==.Chìpotle:BAAANQADCgYICgAAAA==.',
Ci='Ciennajewel:BAAANQAECgcIEAAAAA==.Cirdle:BAABNQAECn8nAAIVAAcK9BIPXwCBAQAVAAcK9BIPXwCBAQAAAA==.',
Co='Cobalt:BAACNQAFFH8LAAIXAAQKLA5mEADOAAAXAAQKLA5mEADOAAA1AAQKfysAAhcACgqxHrwgAAEDABcACgqxHrwgAAEDAAE1AAUUBggKABcAexEA.Coolkid:BAAANQAECgMJBAAAAA==.Corntard:BAAANQADCggIGAAAAA==.',
Cr='Crazynlazy:BAABNQAECn8bAAILAAcKcgOy0QDwAAALAAcKcgOy0QDwAAAAAA==.Crucifixea:BAABNQAECn8hAAMRAAkKEBRNSABGAgARAAgKoBVNSABGAgABAAkKdhOOLwBiAQABNQAFFAMICgADAF4YAA==.Cruxsader:BAAANQADCggIEAAAAA==.Crystyl:BAABNQAECn8WAAIYAAcKmg1REAAFAQAYAAcKmg1REAAFAQAAAA==.',
Ct='Ctesias:BAAANQADCgYIBgAAAA==.',
Cu='Cuddly:BAAANQAECgcIBwABNQAFFAcIAgAGAAAAAA==.Cute:BAAANQAECgYIBgABNQAFFAcIIAADAOAeAA==.',
Cy='Cymoril:BAABNQAECn85AAICAAoK9RpBJgBNAgACAAoK9RpBJgBNAgAAAA==.',
Da='Daamass:BAAANQAECgIIAgAAAA==.Dagyrr:BAAANQADCgEIAQAAAA==.Dalman:BAAANQAECgQIBgAAAA==.Dalmin:BAAANQADCggICAAAAA==.Dalov:BAABNQAECn8aAAIVAAkKzRSmbQBcAQAVAAkKzRSmbQBcAQAAAA==.Darkcarnival:BAABNQAECn8gAAIXAAcKqBYBYgA/AQAXAAcKqBYBYgA/AQAAAA==.Darkkill:BAAANQADCgMIAwABNQAECgoKKQAHAFQjAA==.Darthraider:BAAANQAECgUIEgAAAA==.Dasnotgood:BAAANQADCggIHwAAAA==.',
De='Deemon:BAABNQAECn8jAAMEAAkK8xb4MgCqAQAEAAcKtxj4MgCqAQAZAAQKiBLzUQB9AAAAAA==.Delathatha:BAAANQADCgcICwAAAA==.Demiish:BAAANQADCgEIAQAAAA==.Demorjan:BAAANQADCggIEAAAAA==.Denard:BAAANQADCgYIEwABNQADCggIGwAGAAAAAA==.Denarias:BAAANQADCgUJBQABNQAECgUIBgAGAAAAAA==.Denevien:BAAANQAECgYIDAAAAA==.Desdemona:BAABNQAECn8WAAIBAAcKiA4uJADdAAABAAcKiA4uJADdAAAAAA==.Dethiaris:BAAANQAECgQICwAAAA==.',
Di='Diablojr:BAAANQAECgUIDAAAAA==.Dianimal:BAAANQAECgMIAwAAAA==.Distroya:BAAANQAECgQIBAAAAA==.',
Dk='Dkaiseremp:BAABNQAECn8dAAIaAAoKoAftCwCcAQAaAAoKoAftCwCcAQAAAA==.',
Do='Dobutsu:BAAANQAECggIEAAAAA==.Dog:BAACNQAFFH8WAAIbAAUKyCYHAQAwAgAbAAUKyCYHAQAwAgA1AAQKf9MAAhsACgoNJwEAAKUEABsACgoNJwEAAKUEAAAA.Doomace:BAABNQAECn86AAIKAAoKIhM1VAC5AQAKAAoKIhM1VAC5AQAAAA==.',
Dr='Draaka:BAAANQADCgYIDgAAAA==.Dragee:BAAANQAECgUIBQABNQAECgkJIwAEAPMWAA==.Dragon:BAAANQAECgcICQAAAA==.Driftyshaman:BAAANQAECgIIAgAAAA==.Droopy:BAAANQAECgUIBQAAAA==.Dræghoule:BAABNQAECn8UAAIcAAcKxAZLPADJAAAcAAcKxAZLPADJAAAAAA==.',
Du='Durnik:BAABNQAECn8hAAMVAAoKDh1AHAB+AgAVAAoKDh1AHAB+AgAdAAEKAADLkQAuAAABNQAECgkJMwAPALoXAA==.',
Dw='Dworflundgrn:BAABNQAECn8gAAIeAAkKZgdTEgBgAQAeAAkKZgdTEgBgAQAAAA==.',
Dy='Dyamí:BAABNQAECn8nAAIMAAcKxBYjggA+AQAMAAcKxBYjggA+AQAAAA==.',
['Dá']='Dánte:BAAANQAECgYICQAAAA==.',
Eg='Eglosira:BAAANQADCgMIBQAAAA==.',
El='Elbuhero:BAABNQAECn8qAAMFAAgKJwezNgBmAQAFAAgKJwezNgBmAQAJAAUK+xX/XQBZAQAAAA==.Eldiablo:BAAANQAECgMIBwAAAA==.Electric:BAAANQAECgUIEAAAAA==.Elementstone:BAAANQAECgIIAgAAAA==.Elendish:BAAANQADCgIIAgAAAA==.Eleven:BAABNQAECn8tAAIMAAkKxwcshAA6AQAMAAkKxwcshAA6AQAAAA==.Eliasevo:BAAANQADCgcICQABNQAECgoKKQAHAFQjAA==.Elrythe:BAABNQAECn9HAAIVAAoKECGdDADrAgAVAAoKECGdDADrAgAAAA==.',
Er='Eraleth:BAAANQAECgUICwABNQAECgoKKwAEALUgAA==.',
Fa='Faben:BAAANQADCgUIBQAAAA==.Faced:BAAANQAECgUICwAAAA==.Fatalii:BAABNQAECn8WAAMfAAgKmxQONgCSAQAfAAcKxRAONgCSAQAQAAYKahRRKgDHAAAAAA==.',
Fe='Felebash:BAAANQAECgUIDQAAAA==.Felfireflux:BAAANQADCgYIDAAAAA==.Fellirane:BAAANQADCgUIBQAAAA==.',
Fi='Fistdaddy:BAAANQADCgYJDwAAAA==.',
Fl='Floofies:BAABNQAECn81AAIeAAoKjyRXAQCtAwAeAAoKjyRXAQCtAwAAAA==.Floofthulu:BAAANQAECgEIAQABNQAECgoKNQAeAI8kAA==.Fluffalo:BAABNQAECn8uAAILAAoKbSCBEQBiAwALAAoKbSCBEQBiAwABNQAECgoKNQAeAI8kAA==.',
Fo='Foxypocket:BAAANQAECgUIEwAAAA==.',
Fr='Fredrickk:BAAANQAECgUIDwAAAA==.',
Fu='Furcas:BAAANQAECgIIAgAAAA==.Furrglur:BAAANQAECgIIAgABNQAECgoKNQAeAI8kAA==.Furrylight:BAAANQAECgIIAQABNQAECgoKKAAHAE0gAA==.Furryphase:BAABNQAECn8oAAMHAAoKTSB6HgDxAgAHAAoKTSB6HgDxAgALAAMKlQXpqQBTAAAAAA==.Fuzzington:BAAANQAECgcICwABNQAECgoKNQAeAI8kAA==.Fuzzydunlop:BAAANQADCgUICQAAAA==.',
Fz='Fzoul:BAAANQADCgYIBgAAAA==.',
Ga='Gaith:BAAANQAECgYIBgAAAA==.Galnier:BAAANQAECgcIDAAAAA==.Gandoomi:BAAANQABCgIIAgAAAA==.',
Gh='Ghosted:BAAANQAECgMIBQAAAA==.',
Gl='Glaur:BAABNQAECn8pAAIHAAkKExM0PACoAQAHAAkKExM0PACoAQAAAA==.',
Go='Goatjira:BAAANQAECgMIBAAAAA==.',
Gr='Grimgor:BAAANQAECgQIBAABNQAECgcIGwAgADAdAA==.Gripisrdy:BAABNQAECn8gAAQcAAcKoh4yOgA6AgAcAAYKjyAyOgA6AgAgAAcK2hjWSgCPAQAhAAIK2w+lqACAAAAAAA==.Grippindeez:BAABNQAECn8kAAMgAAkKvQ4OTgB+AQAgAAkK+wsOTgB+AQAhAAIKNBxKtgBbAAAAAA==.',
Gu='Gunslingr:BAABNQAECn8vAAMiAAoKjyAuAwAIAwAiAAoKECAuAwAIAwAfAAYK6BW+OgB6AQAAAA==.',
Gw='Gweetow:BAAANQAECgEIAQAAAA==.',
Gy='Gymsharklyfe:BAAANQAECggIBgAAAA==.',
Ha='Hairyjolene:BAAANQADCggIEgAAAA==.Handsome:BAABNQAECn8rAAMdAAoK/RziEgDLAgAdAAkKRxziEgDLAgAVAAcKFBfMxwByAQABNQAFFAMICgADAF4YAA==.',
He='Headpats:BAACNQAFFH8HAAIRAAUKjBJzBwCDAQARAAUKjBJzBwCDAQA1AAQKfxwAAhEACgpsH6oLAA0DABEACgpsH6oLAA0DAAE1AAUUBwgCAAYAAAAA.Hearthisrdy:BAAANQAECgYIBgAAAA==.Helmshammer:BAAANQAECgYIBgAAAA==.Hexwhisper:BAAANQAECgQIBAAAAA==.Heycarlos:BAABNQAECn9AAAMgAAkKkCKTBgB5AwAgAAkKkCKTBgB5AwAcAAIKrwfJzQBRAAAAAA==.',
Hi='Hikaripala:BAAANQADCgYIBgABNQAFFAcIGgAHAIkYAA==.Hikarishaman:BAACNQAFFH8aAAMHAAcKiRiZCgClAQAHAAUKDhaZCgClAQALAAQKmhuMEgBGAQA1AAQKfzMAAwsACgrjGwUWAFMCAAsACgrjGwUWAFMCAAcACQopHShPACgCAAAA.Hime:BAABNQAECn8jAAIKAAcKVAil9wAuAQAKAAcKVAil9wAuAQAAAA==.',
Ho='Holyblimblam:BAAANQAECgMIBwAAAA==.Honeypieheal:BAAANQAECgMIAwAAAA==.Horabad:BAAANQAECgUIBwAAAA==.Hosemachine:BAABNQAECn8ZAAIcAAgKWhkLOgA7AgAcAAgKWhkLOgA7AgAAAA==.',
Hu='Hulque:BAAANQADCgYIBgAAAA==.Humper:BAAANQADCgEIAQAAAA==.',
['Hè']='Hèri:BAAANQAECgMIAwAAAA==.Hèrifire:BAAANQAECgUIDQAAAA==.',
Ic='Icyshadow:BAABNQAECn8XAAMjAAYKgg2ISAD7AAAjAAYKgg2ISAD7AAADAAEKqxDoxwA1AAAAAA==.',
Id='Idouna:BAAANQADCgEIAQAAAA==.',
Ih='Ihalo:BAAANQAECgYIEAAAAA==.',
Il='Illinesh:BAAANQADCgYICgAAAA==.',
Ir='Ironpaw:BAAANQAECgUJDAAAAA==.',
It='Ithildur:BAAANQADCgQIBAAAAA==.',
Ja='Jadde:BAAANQADCgYIBgAAAA==.Jadienne:BAAANQAECgQIDAAAAA==.Jameson:BAAANQAECgUIDAAAAA==.Jangewinde:BAAANQAECgQICwAAAA==.Jasmind:BAAANQAECgcIEQAAAA==.Jaywu:BAAANQADCggICAAAAA==.',
Ji='Jiwà:BAABNQAECn81AAMHAAkKARQuVgAPAgAHAAkKARQuVgAPAgALAAcKnwKexgAFAQAAAA==.',
Jo='Joshjb:BAAANQAECgIIAgAAAA==.Joss:BAAANQADCgIIAgAAAA==.',
Ka='Kaguro:BAABNQAECn8pAAMQAAoKkQ9/GQAwAQAiAAkK8w6QAwBGAQAQAAcKGg9/GQAwAQAAAA==.Kahless:BAAANQADCggIFwAAAA==.Kaibab:BAAANQADCgEIAQAAAA==.Kakwaa:BAAANQAECgIJAwAAAA==.Kalix:BAAANQABCgUICAAAAA==.Kaliyah:BAAANQAECgYIDwAAAA==.Kattrin:BAAANQADCgYIFgAAAA==.Kayleebear:BAAANQADCgQIBAAAAA==.',
Ke='Kerplaa:BAAANQADCgMIAwAAAA==.Keyadistor:BAABNQAECn8bAAQgAAcKMB2FLQB0AQAgAAcK2hyFLQB0AQAhAAEKkCP+sABpAAAcAAEKAACz5gAuAAAAAA==.',
Kh='Khazabrew:BAABNQAECn8vAAIUAAkKoB4aBAAQAgAUAAkKoB4aBAAQAgAAAA==.',
Ki='Kiamara:BAABNQAECn8WAAIXAAcKkwQNkwDJAAAXAAcKkwQNkwDJAAAAAA==.Kinderlin:BAABNQAECn81AAIKAAoKoxTFSQDaAQAKAAoKoxTFSQDaAQAAAA==.Kirbun:BAABNQAECn8xAAIMAAkK/xyJZwCvAgAMAAkK/xyJZwCvAgAAAA==.Kizchaos:BAAANQAECgMIBAAAAA==.',
Ko='Komurash:BAABNQAECn8jAAMCAAoKRRMRXgBoAQACAAoKRRMRXgBoAQANAAIKRgM8PABVAAAAAA==.Korstruck:BAAANQAECgUIBQAAAA==.Kotys:BAAANQADCgUIBQAAAA==.',
Kr='Kravvelocity:BAAANQAECgQIBAAAAA==.',
Ku='Kungbrew:BAAANQAECgEIAQABNQAECgYIFwAjAIINAA==.',
La='Lancaban:BAAANQADCggIHQAAAQ==.',
Le='Lethalarrow:BAABNQAECn8eAAIVAAgKJA05ZwBtAQAVAAgKJA05ZwBtAQAAAA==.Lethalpally:BAAANQADCggIDAAAAA==.Lewismr:BAAANQADCgUIDQABNQAECgkKKQAKACQTAA==.Lewisr:BAABNQAECn8pAAIKAAkKJBNJYQCXAQAKAAkKJBNJYQCXAQAAAA==.',
Li='Ligahoo:BAAANQADCggJDwAAAA==.Lilysweets:BAAANQADCgcICgAAAA==.',
Lo='Loralynn:BAAANQAECgQIBAABNQAECgoKSAARAKAYAA==.Lorianne:BAAANQAECggIDQABNQAECgoKSAARAKAYAA==.Lorryanne:BAABNQAECn9IAAMRAAoKoBgpJQAjAgARAAoKoBgpJQAjAgAKAAoKNw6ETgDKAQAAAA==.',
Lu='Lucianas:BAAANQAECgYIDAAAAA==.Lunacat:BAAANQAECgQICQABNQADCgYJDwAGAAAAAA==.Luxdaddy:BAAANQAECgcIDgABNQADCgYJDwAGAAAAAA==.',
Ly='Lysi:BAAANQAECgUIDwAAAA==.',
Ma='Madaea:BAABNQAECn8oAAIbAAoKoRqGEgBUAgAbAAoKoRqGEgBUAgAAAA==.Madameuyen:BAAANQAECgQIBQAAAA==.Madlyn:BAAANQAECgQICwAAAA==.Magepuppy:BAABNQAECn8cAAMMAAgK+hQ/ygDxAQAMAAcKTxU/ygDxAQAYAAEKTxM9QABEAAABNQAECgoKQgABALsdAA==.Makavali:BAABNQAECn8fAAMFAAoKQBVoDQBZAgAFAAkKyxZoDQBZAgAJAAgKCg0nYwBBAQAAAA==.Makavalii:BAABNQAECn9TAAMKAAkK9xUzeAA8AgAKAAkK9xUzeAA8AgARAAkKCxM/UAArAgABNQAECgoKHwAFAEAVAA==.Malanimus:BAAANQAECgUICQAAAA==.Malevola:BAAANQAECgEIAQAAAA==.Malholis:BAAANQAECgUICwAAAA==.Mandorallen:BAAANQAECgQIBAABNQAECgkJMwAPALoXAA==.Matagi:BAABNQAECn8wAAIVAAkKPxTvVwBrAgAVAAkKPxTvVwBrAgAAAA==.Mate:BAAANQADCgUIBQABNQADCggIGwAGAAAAAA==.',
Me='Meatloaf:BAAANQADCgQIBAAAAA==.Meeseks:BAABNQAECn80AAIcAAoKShvmEQAFAgAcAAoKShvmEQAFAgAAAA==.Megabyte:BAAANQAECgQJBAAAAA==.Melbeast:BAAANQAECgcICgAAAA==.Melorea:BAAANQAECgEIAgAAAA==.Merdin:BAABNQAECn8fAAIMAAcKAw61awBwAQAMAAcKAw61awBwAQAAAA==.Methmartion:BAABNQAECn8aAAIWAAYKtwnYNADwAAAWAAYKtwnYNADwAAAAAA==.',
Mi='Mignon:BAAANQADCggICAABNQADCggIGwAGAAAAAA==.Milougheh:BAAANQAECggIAgAAAA==.Minós:BAAANQADCgUIBQAAAA==.Mish:BAAANQAECgQIBAAAAA==.Missiah:BAABNQAECn8oAAIBAAkKXAd2HAAYAQABAAkKXAd2HAAYAQAAAA==.',
Mo='Molfise:BAAANQADCgYIBQAAAA==.Monna:BAAANQABCgIIAgAAAA==.Moonfell:BAABNQAECn8lAAIDAAkK2xGjWgBKAQADAAkK2xGjWgBKAQAAAA==.Moonlilly:BAABNQAECn8WAAINAAcKgAMRHACwAAANAAcKgAMRHACwAAAAAA==.Mopp:BAAANQAECgQIDgAAAA==.Morganthe:BAAANQADCggIEAAAAA==.Mornîngstar:BAAANQAECgcIEQAAAA==.',
Mx='Mxtemlen:BAAANQAECgQIBAABNQAECggIHAARAHcSAA==.',
My='Mylilhunter:BAABNQAECn8bAAIVAAcK5wZymgD7AAAVAAcK5wZymgD7AAAAAA==.Myrtheli:BAAANQADCggICAABNQAECgkJIAADAOoUAA==.Mysticx:BAAANQAECggICAAAAA==.',
Na='Nachtelf:BAABNQAECn89AAIVAAoKER0nHAB+AgAVAAoKER0nHAB+AgAAAA==.Nagan:BAAANQAECgYIDAAAAA==.Natadawn:BAAANQADCgYIBgAAAA==.Natalone:BAABNQAECn85AAIYAAoKLST1AQBhAwAYAAoKLST1AQBhAwAAAA==.Nathel:BAABNQAECn8XAAMYAAYKnAP7IwBbAAAMAAYKawI+AgFiAAAYAAYKRAP7IwBbAAAAAA==.',
Ne='Nerisa:BAAANQADCgUIBQAAAA==.',
Ni='Nirra:BAAANQAECgMIBQAAAA==.',
No='Noctis:BAAANQAECgYICwAAAA==.Notoriginal:BAABNQAECn8mAAIcAAoKzw4GFQDdAQAcAAoKzw4GFQDdAQAAAA==.Novatron:BAABNQAECn8aAAQeAAcKZAVmJQAGAQAeAAcK5QJmJQAGAQALAAQKbwYAjwB/AAAHAAMK7wCRFwE8AAAAAA==.',
Nu='Nuked:BAABNQAECn8UAAIMAAYKuxddAAGNAQAMAAYKuxddAAGNAQAAAA==.',
['Né']='Néith:BAAANQADCgQIBAAAAA==.',
Od='Odor:BAAANQAECgMIAwAAAA==.',
Og='Ograskygazer:BAAANQAECgUIEgAAAA==.',
Oi='Oieg:BAAANQABCgUIBAAAAA==.',
Om='Omee:BAABNQAECn8YAAMEAAcKfg2gIgATAQAEAAcKfg2gIgATAQAZAAEKAABPlwAuAAABNQAECgoKKwAVAPQcAA==.Omegaone:BAAANQADCgcIBwAAAA==.',
On='Oneil:BAAANQADCgMJAwAAAA==.Onlyshrimps:BAAANQAECgYIBgAAAA==.',
Or='Oralena:BAAANQAECgUIEwAAAA==.Orioncheats:BAABNQAECn85AAMcAAkKahbaGQCnAQAcAAkKahbaGQCnAQAhAAcKzgpKPQDtAAAAAA==.',
Ow='Owo:BAAANQAECgEIAQAAAA==.',
Ox='Oxygën:BAABNQAECn8kAAIMAAgK/hOBZQB/AQAMAAgK/hOBZQB/AQAAAA==.',
Pa='Palomita:BAAANQADCgIIAgAAAA==.',
Pe='Ped:BAAANQAECgEIAQABNQAECgkJIAADAOoUAA==.Pedaramun:BAAANQAECgYIBQABNQAECgkJIAADAOoUAA==.Pedarias:BAABNQAECn8gAAMDAAkK6hRTaQDiAQADAAkK6hRTaQDiAQAjAAEKAABTlgANAAAAAA==.Peon:BAAANQAECgYIDwAAAA==.Perstephanie:BAAANQADCgQIBAAAAA==.',
Ph='Pharune:BAABNQAECn8mAAIkAAcK2Q0MKABWAQAkAAcK2Q0MKABWAQAAAA==.Phredrick:BAAANQAECgUIBwAAAA==.',
Pi='Piemanninty:BAAANQAECgIJBQAAAA==.',
Pl='Plandemic:BAAANQAECgEIAQAAAA==.',
Po='Pockithealz:BAAANQADCgQIBAABNQAECggIFgAfAJsUAA==.Pointnshoot:BAAANQADCgQIBAABNQAECgcIHwAGAAAAAA==.Pokerface:BAAANQAECgQIBgAAAA==.Ponky:BAAANQAECgIIAgABNQAECgoKLwARACcZAA==.Poongwoon:BAAANQADCgMIAwAAAA==.Pounces:BAABNQAFFH8GAAIFAAQKBxKhCgApAQAFAAQKBxKhCgApAQABNQAFFAcIAgAGAAAAAA==.',
Pr='Precious:BAAANQAECgIIBQABNQAFFAcIIAADAOAeAA==.',
Pu='Puppet:BAAANQAECgcIEAABNQAFFAcIIAADAOAeAA==.',
Py='Pymura:BAAANQADCgQIBAAAAA==.',
['Pí']='Píongá:BAAANQADCgEIAQAAAA==.',
Qe='Qee:BAAANQAECgEIAQABNQAECgkJIwAEAPMWAA==.',
Qu='Quattro:BAABNQAECn8lAAIlAAkKkg4SCACOAQAlAAkKkg4SCACOAQAAAA==.',
Ra='Racecar:BAAANQAECgUIDQAAAA==.Raezil:BAAANQAECgQICQABNQAECgoKIQAXAKsSAA==.Raivyn:BAABNQAECn8zAAIPAAkKuhctDgAKAgAPAAkKuhctDgAKAgAAAA==.Rathmora:BAAANQADCggIHgAAAA==.Raylaira:BAAANQAECgUIBgABNQAECgUIBgAGAAAAAA==.Raziel:BAAANQADCgYIBgAAAA==.',
Re='Redbeard:BAAANQADCgYIBgAAAA==.Remnants:BAAANQADCggIEwAAAA==.Renard:BAABNQAECn8+AAIFAAoKJCNjAwCSAwAFAAoKJCNjAwCSAwAAAA==.Reposado:BAAANQAECgUIDgAAAA==.Revelare:BAABNQAECn8gAAIHAAcKYBd8ZwDWAQAHAAcKYBd8ZwDWAQAAAA==.Rexbie:BAAANQAECgcICwAAAA==.',
Rh='Rhylee:BAAANQAECgUICgAAAA==.',
Ri='Rianne:BAAANQADCgUIBQAAAA==.Riptidepod:BAABNQAECn8mAAMHAAoKYBvbJgDJAgAHAAoKYBvbJgDJAgALAAEKAACrRgErAAAAAA==.',
Rm='Rmplstiltskn:BAAANQADCgUICQAAAA==.',
Ro='Robberttrest:BAABNQAECn8aAAIVAAUKWwl87QAmAQAVAAUKWwl87QAmAQAAAA==.Rockyhunter:BAAANQAECggIDAABNQAECgoKMQAhALAbAA==.Rockyhunterr:BAABNQAECn8xAAIhAAoKsBvzEQAdAwAhAAoKsBvzEQAdAwAAAA==.Rockymage:BAAANQADCgYIBgAAAA==.Rockyrogue:BAAANQADCggICAABNQAECgoKMQAhALAbAA==.Rockywarlock:BAAANQAECgEIAQABNQAECgoKMQAhALAbAA==.Rockywarrior:BAAANQADCgYICgABNQAECgoKMQAhALAbAA==.Ronaeminnda:BAAANQABCgQIBAAAAA==.Rooth:BAAANQAECgUIDgAAAA==.Roryn:BAABNQAECn9GAAIKAAoK2iVNBQBVAwAKAAoK2iVNBQBVAwAAAA==.',
Ru='Rubï:BAABNQAECn8aAAIOAAoKkSJ2AQDxAgAOAAoKkSJ2AQDxAgAAAA==.Rugiaas:BAACNQAFFH8oAAIRAAcKXSH4AAC2AgARAAcKXSH4AAC2AgA1AAQKfz4AAxEACgoFJc4EAKoDABEACgoFJc4EAKoDAAoABArUGM35ACsBAAAA.Rugian:BAAANQAECgQIBQABNQAFFAcIKAARAF0hAA==.',
Ry='Ryuka:BAAANQAECgcIEQAAAA==.',
['Râ']='Râezil:BAAANQADCgIIAgABNQAECgoKIQAXAKsSAA==.',
Sa='Sabriiel:BAAANQADCgIIAwABNQAECgQIBgAGAAAAAA==.Samyria:BAAANQAECgQICQAAAA==.Sapphiriana:BAAANQADCgIIAgABNQAECgUIDgAGAAAAAA==.Saprates:BAAANQADCgMIAwAAAA==.Satyaru:BAABNQAECn8nAAQUAAgKag/sEQDHAQAUAAgKag/sEQDHAQAbAAQKkgg/OwCYAAAPAAEKAAAIcwAmAAAAAA==.Saucy:BAABNQAECn8XAAILAAYKqBaPtwAjAQALAAYKqBaPtwAjAQAAAA==.',
Se='Sedona:BAAANQAECgYICwAAAA==.Selarra:BAABNQAECn8gAAIDAAkK7gxcfACkAQADAAkK7gxcfACkAQAAAA==.Seric:BAABNQAECn8hAAMNAAkKtg4pGwCHAQANAAkKtg4pGwCHAQACAAMK+wE5TQE5AAAAAA==.Sethuriel:BAAANQAECggIDgAAAA==.',
Sh='Shadowdancèr:BAAANQADCgEJAQAAAA==.Shadowlocke:BAAANQADCgMIAwAAAA==.Shalzith:BAAANQAECgEIAQAAAA==.Shenandoah:BAAANQADCgYIBgAAAA==.Shockadelica:BAAANQADCgYIBgAAAA==.',
Si='Sitheretta:BAAANQAECgQIBAAAAA==.',
Sk='Skoto:BAAANQAECgUIBQAAAA==.',
Sm='Smartfood:BAAANQAECggIEQAAAA==.Smoochybooty:BAAANQAECgMIBAAAAA==.',
Sn='Snuggy:BAAANQAECgIIAgAAAA==.',
So='Solnar:BAABNQAECn8cAAMRAAgKdxJZYAD3AQARAAgKdxJZYAD3AQAKAAQK8QyVRwGuAAAAAA==.',
Sp='Specter:BAAANQAECggICAAAAA==.Splashdaddy:BAACNQAFFH8NAAIHAAcKjQ/ICQCzAQAHAAcKjQ/ICQCzAQA1AAQKfz8AAgcACgqGIKYaAAUDAAcACgqGIKYaAAUDAAE1AAMKBgkPAAYAAAAA.Spoiled:BAAANQADCggICAABNQAFFAcIIAADAOAeAA==.',
Sr='Srìracha:BAAANQAECggICwAAAA==.',
St='Staks:BAAANQADCgcIFAAAAA==.Starii:BAAANQAECgcIEAAAAA==.Stormieskye:BAABNQAECn80AAILAAkKIRT7LwCaAQALAAkKIRT7LwCaAQAAAA==.Striga:BAAANQADCgcIBwAAAA==.',
Su='Summonme:BAAANQAECgIIAgAAAA==.Suzume:BAAANQAECgQIBAABNQAFFAcIGgAHAIkYAA==.',
Sw='Sweetshot:BAAANQADCgEIAQAAAA==.',
Sy='Sylvancura:BAAANQADCgQIBAAAAA==.Synestra:BAAANQAECgUIEAAAAA==.',
Ta='Taea:BAAANQAECgUIDwAAAA==.Taeus:BAABNQAECn8vAAQYAAoKGyDiBgCLAgAYAAoKGyDiBgCLAgAMAAcKMRff0wDfAQAmAAEKPw9zDAA/AAAAAA==.Taintedkoma:BAAANQAECgMIAwABNQAECgYIGgAWALcJAA==.Talagark:BAAANQADCgYIBgAAAA==.Talanat:BAAANQADCgIIAgAAAA==.Taurenator:BAABNQAECn8eAAINAAoKQyCkBgD5AgANAAoKQyCkBgD5AgAAAA==.',
Te='Teheez:BAAANQADCgIIAgAAAA==.Tenthrol:BAAANQABCgMIBQAAAA==.Teranidas:BAAANQAECgUIBgAAAA==.Teratrendera:BAABNQAECn8XAAInAAYKBh9rDQCmAQAnAAYKBh9rDQCmAQAAAA==.Teron:BAAANQAECgMJBAAAAA==.Tesx:BAAANQAECgEIAQAAAA==.',
Th='Thavis:BAABNQAECn8pAAMXAAgKlBN+QgCgAQAXAAgKthF+QgCgAQAWAAQKwgxVOwDUAAAAAA==.Thdoris:BAAANQADCgQIBAAAAA==.Thetimelord:BAAANQAECgMIBQAAAA==.Thewarrior:BAAANQAECgYIDgAAAA==.Thrask:BAAANQADCgQIBAAAAA==.',
Ti='Ticktac:BAAANQAECgYIBgAAAA==.Tik:BAAANQADCggIDgAAAA==.Tilted:BAABNQAECn8fAAIKAAoKbRc4kwD9AQAKAAoKbRc4kwD9AQAAAA==.Tiltêd:BAAANQAECgQIBAAAAA==.Tinkr:BAABNQAECn8tAAIhAAkK0RjnFwDcAQAhAAkK0RjnFwDcAQAAAA==.',
To='Tobi:BAAANQADCgYIBgAAAA==.Toewzix:BAAANQAECgQIBAAAAA==.Tom:BAAANQAECgUICAABNQAECgoKIQAXAKsSAA==.Torrey:BAABNQAECn8hAAMSAAkKSAtEDAAVAQAEAAkKngmuNACdAQASAAkKxwhEDAAVAQAAAA==.Totemsareus:BAABNQAECn8pAAMHAAoKVCMgCACAAwAHAAoKVCMgCACAAwALAAIKigdZFQFjAAAAAA==.Toxx:BAAANQAECgcIBgABNQAECgoKKwAVAPQcAA==.',
Tr='Tradd:BAACNQAFFH8KAAIDAAMKXhhHFwDHAAADAAMKXhhHFwDHAAA1AAQKfzoABAMACgpNICMOAFMDAAMACgpNICMOAFMDACgABwrDDr4MAGwBACMABwpMCmguAJ8AAAAA.Trallor:BAABNQAECn8iAAICAAgKWg0VvgCBAQACAAgKWg0VvgCBAQAAAA==.Trhall:BAAANQAECgQIBQAAAA==.Tristyana:BAABNQAECn84AAIVAAoK4xCMOwDyAQAVAAoK4xCMOwDyAQAAAA==.',
Ts='Tsiddahn:BAABNQAECn8sAAIDAAkK9RqmKADHAgADAAkK9RqmKADHAgAAAA==.Tsunâde:BAABNQAECn80AAMPAAoKCCUYAgA/AwAPAAoKCCUYAgA/AwAbAAYKMhL/HADGAAAAAA==.',
Tw='Twanu:BAAANQADCgMIAwAAAA==.',
Ty='Tylurien:BAABNQAECn8mAAIRAAcKSSbNGQAQAwARAAcKSSbNGQAQAwAAAA==.Tyrael:BAABNQAECn8iAAMBAAkK7RI2HAAbAQABAAgKsg82HAAbAQARAAEKYwLQ2wAVAAABNQADCgMIBgAGAAAAAA==.',
Uk='Ukon:BAAANQADCgYIBgAAAA==.',
Ul='Ulangi:BAAANQAECgEIAQAAAA==.',
Un='Un:BAAANQADCgcIAQAAAA==.',
Ur='Urbanprey:BAABNQAECn8kAAIWAAkKFQvuBQAqAQAWAAkKFQvuBQAqAQAAAA==.',
Va='Valenhi:BAAANQAECgEIAQAAAA==.Valkoinen:BAAANQADCgMIBgAAAA==.Valora:BAABNQAECn83AAIDAAoKUR6vFADAAgADAAoKUR6vFADAAgAAAA==.Valoria:BAAANQAECgIIAwAAAA==.Vanille:BAABNQAECn8XAAIFAAYKkQTRPwCUAAAFAAYKkQTRPwCUAAAAAA==.Vargen:BAAANQAECgQICAAAAA==.Varonika:BAAANQAECgUIBwAAAA==.Vayla:BAABNQAECn8zAAINAAkKfB1TBAByAgANAAkKfB1TBAByAgAAAA==.',
Vb='Vbv:BAAANQAECgMIAwAAAA==.',
Ve='Vedik:BAAANQAECgQICAAAAA==.Vegasduc:BAAANQADCgQIBAAAAA==.Vegasducks:BAABNQAECn8oAAIMAAkKpgcxXQCWAQAMAAkKpgcxXQCWAQAAAA==.Velara:BAAANQADCgYIDAAAAA==.Veld:BAAANQAECgcIEQAAAA==.Velithara:BAAANQADCgYJBgAAAA==.Veralyn:BAAANQADCgUICQAAAA==.',
Vi='Violet:BAABNQAECn8bAAIKAAYKpwVUDAEKAQAKAAYKpwVUDAEKAQAAAA==.',
Vy='Vyla:BAAANQABCgcIDAAAAA==.',
['Vè']='Vèngeance:BAAANQAECgUIBQAAAA==.',
Wa='Wardancer:BAAANQAECgUIBQAAAA==.Warfise:BAAANQAECgUIDQAAAA==.Warspriest:BAABNQAECn8gAAIjAAcKcRzCHgBIAgAjAAcKcRzCHgBIAgAAAA==.Warwizard:BAABNQAECn9NAAIRAAoKfiQyAwC4AwARAAoKfiQyAwC4AwAAAA==.',
Wd='Wdemperor:BAABNQAECn8YAAMNAAcKUwOTMACxAAANAAcKPAOTMACxAAACAAMKzgOJ7wA9AAABNQAECgoKHQAaAKAHAA==.',
We='Webin:BAAANQAECgEIAQAAAA==.',
Wh='Whispaknight:BAAANQAECgEIAQABNQAECgEIAQAGAAAAAA==.Whisperwiind:BAAANQADCgcIBwABNQAECgEIAQAGAAAAAA==.Whisperz:BAAANQADCgYIBgABNQAECgEIAQAGAAAAAA==.',
Wi='Wickedywaque:BAAANQADCgUIBQAAAA==.Wickerchickn:BAAANQAECgQJBwAAAA==.Wiisper:BAAANQAECgEIAQAAAA==.Wilshammy:BAAANQADCgYIGAAAAA==.Winterhunter:BAAANQADCgEIAQAAAA==.',
Wo='Wonkyponky:BAABNQAECn8vAAIRAAoKJxndJwDJAgARAAoKJxndJwDJAgAAAA==.',
Wr='Wrathbarrage:BAAANQAECgYICwABNQAECgkJMgAkAOMSAA==.Wrathchoi:BAAANQAECgYIBgAAAA==.Wrathstorm:BAABNQAECn8yAAMkAAkK4xIbGQBEAQAkAAkKuRIbGQBEAQATAAEKKQrBMQAwAAAAAA==.',
Ya='Yazahk:BAAANQADCggIFgABNQAECgYIBgAGAAAAAA==.Yazjani:BAAANQADCgIIAgAAAA==.Yazoth:BAAANQADCgEIAQAAAA==.Yazoura:BAAANQADCggIDwAAAA==.Yazwynn:BAAANQADCgcIDgAAAA==.',
Ye='Yezgraine:BAACNQAFFH8aAAIhAAcK+iDKAQCdAgAhAAcK+iDKAQCdAgA1AAQKfywAAyEACgpmJVABAGsDACEACgpmJVABAGsDACAAAQrdHM6dAFYAAAAA.',
Yo='Yookock:BAAANQADCggIDgAAAA==.',
Yz='Yzaak:BAAANQAECgYIBgAAAA==.',
Za='Zagyg:BAAANQADCgQIBAAAAA==.',
Ze='Zeddiccus:BAABNQAECn8aAAMYAAkK1ByXEQDzAAAMAAYKWRyhigAtAQAYAAQKohqXEQDzAAAAAA==.Zeva:BAAANQAECgUIDQAAAA==.',
Zo='Zonzmik:BAAANQADCgIIAgAAAA==.Zorrokiller:BAAANQADCgQIBAAAAA==.Zorvoth:BAAANQADCgQIBAABNQAECgUIBgAGAAAAAA==.',
Zu='Zurazaee:BAABNQAECn8ZAAIDAAYKlCF8NwDaAQADAAYKlCF8NwDaAQAAAA==.',
['Él']='Élle:BAAANQADCgcICAAAAA==.',
['Ér']='Éric:BAABNQAECn84AAIkAAoKkwqiGQA/AQAkAAoKkwqiGQA/AQAAAA==.',
['Ïr']='Ïridescent:BAAANQAECgIIAgAAAA==.',
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
