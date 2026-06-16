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

local lookup = {'Unknown-Unknown','Paladin-Holy','Warlock-Demonology','Warrior-Fury','Warrior-Protection','Priest-Shadow','Priest-Holy','Warlock-Destruction','DeathKnight-Unholy','Paladin-Retribution','Monk-Brewmaster','Monk-Mistweaver','Monk-Windwalker','Mage-Frost','Hunter-BeastMastery','Evoker-Augmentation','Evoker-Preservation','DeathKnight-Frost','Hunter-Survival','DemonHunter-Devourer','Paladin-Protection','Shaman-Enhancement','Priest-Discipline','Evoker-Devastation','DeathKnight-Blood','Shaman-Elemental','Druid-Restoration','Druid-Balance','Warlock-Affliction','Druid-Feral','Hunter-Marksmanship','DemonHunter-Vengeance','DemonHunter-Havoc','Rogue-Outlaw','Druid-Guardian','Rogue-Subtlety','Rogue-Assassination','Mage-Arcane','Mage-Fire','Warrior-Arms','Shaman-Restoration',}
local provider = {region='US',realm="Blade'sEdge",name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aalduin:BAAALgAECgMJBAABLgAECgYJBgABAAAAAA==.Aarrana:BAAALgADCgYJCQAAAA==.',
Ac='Acupuncher:BAAALgAECgMJAwAAAA==.',
Ad='Ademai:BAAALgAECgYJBgAAAA==.',
Ae='Aephiona:BAAALgAECgQJBAAAAA==.Aetna:BAAALgAECgYJBgABLgAFFAYJEgACAKIZAQ==.',
Af='Affli:BAACLgAFFH8WAAIDAAUJlBkvQgBCAQADAAUJlBkvQgBCAQAuAAQKfysAAgMACQkUIEIbALECAAMACQkUIEIbALECAAAA.',
Ag='Agares:BAAALgAECgYJBgAAAA==.',
Ah='Ahzamir:BAABLgAECn8dAAIEAAgJ1h5DEQDGAgAEAAgJ1h5DEQDGAgAAAA==.',
Ai='Aiunar:BAABLgAECn8nAAIFAAgJwRU/FgCQAQAFAAgJwRU/FgCQAQABLgAECggJJwAGAA0MAA==.Aiupriesty:BAABLgAECn8nAAMGAAgJDQzxLwBdAQAGAAgJDQzxLwBdAQAHAAYJcBMASgC3AAAAAA==.',
Ak='Aka:BAAALgAECgEJAQAAAA==.Akimo:BAAALgADCgEJAQAAAA==.',
Al='Alastiria:BAABLgAECn8XAAIIAAgJ8Qn7EwALAQAIAAgJ8Qn7EwALAQAAAA==.Aledrel:BAAALgADCgEJAQAAAA==.Aleiculous:BAABLgAECn8ZAAIJAAYJ0gxKugADAQAJAAYJ0gxKugADAQAAAA==.Aleinara:BAABLgAECn8bAAIKAAkJzwz0bwCMAQAKAAkJzwz0bwCMAQAAAA==.Aleridin:BAABLgAECn8rAAILAAkJHiUHAgBCAwALAAkJHiUHAgBCAwAAAA==.Alexsneaks:BAAALgAECgMJAwAAAA==.Alleriah:BAAALgADCgcJBwAAAA==.Allhanla:BAAALgAECgQJBgAAAA==.Allwynn:BAACLgAFFH8TAAIMAAUJyiBtFADSAQAMAAUJyiBtFADSAQAuAAQKfx0ABAwACQlwG84NALwCAAwACQlwG84NALwCAA0ABwkoGE0fAK8BAAsAAQlAIS9wAGIAAAAA.Alraa:BAAALgAECggJCAAAAA==.',
Am='Ammora:BAAALgADCgIJAgAAAA==.Amorianys:BAAALgAECgYJBgAAAA==.',
An='Androgynous:BAAALgAECgMJAwAAAA==.Andsey:BAAALgAECgQJCAAAAA==.Annore:BAABLgAECn8dAAIJAAkJdxL+UQDLAQAJAAkJdxL+UQDLAQAAAA==.Antihero:BAABLgAECn8hAAIJAAkJeiN5DgAnAwAJAAkJeiN5DgAnAwAAAA==.',
Ap='Aphelse:BAAALgADCgMJAwABLgAFFAUJEwAMAMogAA==.',
Aq='Aquiell:BAABLgAECn8kAAIOAAkJqxC6VwDTAQAOAAkJqxC6VwDTAQAAAA==.Aqular:BAABLgAECn8YAAIPAAgJVROBSwC7AQAPAAgJVROBSwC7AQAAAA==.',
Ar='Archile:BAAALgADCgYJBgAAAA==.Argyre:BAACLgAFFH8fAAIFAAYJtSS4BQDuAQAFAAYJtSS4BQDuAQAuAAQKf0YAAwUACQkkJdsBADYDAAUACQkkJdsBADYDAAQABQnNEP5fANQAAAAA.Arkenomu:BAABLgAECn8iAAMQAAgJNREEMgBrAQAQAAgJNREEMgBrAQARAAcJagwwGgAzAQAAAA==.Arthûr:BAAALgAECgYJBgAAAA==.',
As='Asakaa:BAABLgAECn8vAAMSAAkJwgmqEQBYAQASAAkJwgmqEQBYAQAJAAYJsAHP7AClAAAAAA==.Asclepius:BAABLgAECn8jAAIRAAkJnQ99DwDQAQARAAkJnQ99DwDQAQAAAA==.Askmeific:BAAALgADCgUJBQAAAA==.Askmelic:BAAALgAECgEJAQAAAA==.Aslo:BAAALgADCgEJAQAAAA==.Asmira:BAAALgADCgYJCQAAAA==.Aspirin:BAAALgAECgYJEQAAAA==.Asynic:BAABLgAECn84AAMTAAgJcyHQEAAnAgATAAcJWSHQEAAnAgAPAAYJVx3ZSwC6AQAAAA==.',
At='Atsunvhi:BAAALgAECgUJEwAAAA==.',
Av='Avadakedevra:BAABLgAECn8jAAMTAAcJKBPPJQBvAQATAAcJKBPPJQBvAQAPAAEJKwpFzQA5AAAAAA==.Aviana:BAAALgADCgUJBQAAAA==.',
Aw='Awooing:BAAALgAECgUJCQAAAA==.',
Az='Azareth:BAAALgADCgkJCQAAAA==.Azreal:BAAALgAECgcJDQAAAA==.Azumok:BAAALgAECgQJBAAAAA==.',
Ba='Babyfive:BAAALgADCgcJBwAAAA==.Bairn:BAAALgADCggJCAAAAA==.Bakedbean:BAAALgAFFAEJAQABLgAFFAEJBQAUABQkAA==.Barackobooma:BAAALgAECgIJAgAAAA==.Bazerker:BAAALgAECgUJCQAAAA==.',
Bb='Bbqboom:BAAALgADCgEJAQAAAA==.',
Bd='Bday:BAABLgAECn8lAAIOAAgJnA+wegB/AQAOAAgJnA+wegB/AQAAAA==.',
Be='Beastcode:BAAALgAECggJCAAAAA==.Belgaria:BAABLgAECn8pAAMVAAgJJxR4EwCPAQAVAAgJJxR4EwCPAQAKAAcJgg1ilQBSAQAAAA==.Berryknight:BAACLgAFFH8FAAIJAAIJ3hMDxACcAAAJAAIJ3hMDxACcAAAuAAQKfy4AAwkACQlxG7wwADkCAAkACQlxG7wwADkCABIAAgnZD8QuAF8AAAAA.Berryqt:BAAALgAECgQJCQAAAA==.Bewlzeye:BAAALgAECgUJBwAAAA==.',
Bi='Bigjonmachne:BAACLgAFFH8LAAIJAAUJthpzUgBJAQAJAAUJthpzUgBJAQAuAAQKfxgAAgkACAlAG8ouAEICAAkACAlAG8ouAEICAAAA.Binky:BAAALgADCgEJAQAAAA==.',
Bl='Blackguyy:BAACLgAFFH8iAAIHAAYJ8COuAgBdAgAHAAYJ8COuAgBdAgAuAAQKfx8AAgcACQnOJIkDACIDAAcACQnOJIkDACIDAAAA.Blessmoo:BAABLgAECn8VAAIKAAgJwBe6QQD/AQAKAAgJwBe6QQD/AQAAAA==.Blinktodome:BAAALgAECgYJCgAAAA==.Bloodsail:BAAALgAECgUJBQAAAA==.Bloodydk:BAAALgAECgEJAQAAAA==.Bluestripee:BAAALgAECgEJAQAAAA==.Bluezugzug:BAAALgAECgMJBQAAAA==.',
Bo='Boababy:BAAALgADCgEJAQAAAA==.Bojakson:BAAALgADCgQJAwAAAA==.Bollux:BAABLgAECn8yAAIWAAkJ2hcvCQAnAgAWAAkJ2hcvCQAnAgAAAA==.Bomßer:BAAALgAECgMJBAAAAA==.Bonetatter:BAAALgAECgMJAwABLgAECgMJAwABAAAAAA==.Bongonnaink:BAABLgAECn8zAAMGAAkJ9yCpCADEAgAGAAkJ9yCpCADEAgAXAAEJaBblVgA0AAAAAA==.Bonnieanne:BAAALgADCgEJAQAAAA==.Bonsaichi:BAAALgAECgkJEQAAAA==.Bownyxia:BAACLgAFFH8JAAIQAAMJQBaVEQD1AAAQAAMJQBaVEQD1AAAuAAQKfzYAAxAACQnIInUFAAcDABAACQnIInUFAAcDABgABAlHDvspAM4AAAEuAAUUCAkqAAkA4BwA.Bowtiekwondo:BAAALgADCgYJBgABLgAFFAgJKgAJAOAcAA==.Bowties:BAACLgAFFH8qAAMJAAgJ4ByqCACVAgAJAAgJ4ByqCACVAgAZAAEJAACNWAAAAAAuAAQKf0MAAwkACQmUJhYCAHwDAAkACQmUJhYCAHwDABkACQk3GHkKAHECAAAA.',
Br='Braxchud:BAABLgAECn8/AAIaAAkJJhx5DwB4AgAaAAkJJhx5DwB4AgAAAA==.Braylith:BAAALgADCgUJBQAAAA==.Breezevape:BAABLgAECn8cAAIOAAkJixv6LwBXAgAOAAkJixv6LwBXAgAAAA==.Brewnwings:BAAALgAECgUJCgAAAA==.Brolance:BAAALgADCgMJBAAAAA==.Brotie:BAACLgAFFH8RAAIUAAQJGROQFAAuAQAUAAQJGROQFAAuAQAuAAQKfx0AAhQACQm9HZoYAH8CABQACQm9HZoYAH8CAAEuAAUUCAkqAAkA4BwA.',
Bu='Buahmdav:BAAALgADCgUJBQAAAA==.Bubbles:BAAALgADCgkJDwABLgAECgkJNQAEAHgkAA==.Buggybuzzy:BAAALgADCgYJDwAAAA==.Bulwark:BAAALgAECgEJAgAAAA==.Burial:BAAALgADCgcJCAAAAA==.Burntbiscuit:BAAALgADCgIJAgAAAA==.Buugada:BAAALgAECgQJEgAAAA==.',
Ca='Caarrl:BAAALgAECgQJCAAAAA==.Caedo:BAAALgAECgEJAQAAAA==.Cainblodhoof:BAAALgADCgEJAQAAAA==.Calas:BAAALgAECgMJBQAAAA==.Caliet:BAAALgADCgUJBQAAAA==.Calii:BAAALgADCgkJCwAAAA==.Calischism:BAAALgAECgYJCAAAAA==.Calistra:BAAALgADCgYJBgAAAA==.Calistriaa:BAAALgADCgQJBAAAAA==.Caplock:BAAALgAECgQJBQAAAA==.Capriestsun:BAAALgAECgQJBQAAAA==.Cardinova:BAAALgAECgYJEwAAAA==.Carlistria:BAAALgADCgEJAQAAAA==.Cartime:BAAALgAECgMJBAAAAA==.Cayllia:BAABLgAECn8jAAMbAAkJDCSOBABFAwAbAAkJDCSOBABFAwAcAAgJDCKMFQAgAgAAAA==.',
Ce='Celaris:BAAALgAECgUJDQAAAA==.',
Ch='Chaolang:BAAALgAFFAEJAQAAAA==.Chataykay:BAAALgAECgcJDgAAAA==.Cheon:BAAALgAECgYJCAAAAA==.Cherrypepsï:BAABLgAECn8cAAMHAAkJOQ/aKwCYAQAHAAkJOQ/aKwCYAQAXAAUJdgbwOADgAAAAAA==.Chinlen:BAAALgAECgEJAQAAAA==.Chipdip:BAAALgAECgUJBQAAAA==.Chivies:BAAALgAECggJDgABLgAECgkJMgAKADMhAA==.Chronosdormi:BAAALgAECgQJBAAAAA==.',
Ci='Circë:BAABLgAECn8kAAIdAAkJKxgcBQA6AgAdAAkJKxgcBQA6AgAAAA==.Citrus:BAABLgAECn85AAITAAkJtBU4FAADAgATAAkJtBU4FAADAgAAAA==.',
Cl='Cliqdragon:BAAALgAECgkJAgAAAA==.Cliqdru:BAAALgAECgMJBwAAAA==.Cliqmonk:BAAALgAECgcJCAAAAA==.',
Cn='Cn:BAABLgAECn8yAAIKAAkJMyGwFADEAgAKAAkJMyGwFADEAgAAAA==.',
Co='Cocoabutter:BAABLgAECn8cAAIOAAYJmBGWtAAXAQAOAAYJmBGWtAAXAQAAAA==.Cocochanel:BAAALgAECgQJBAABLgAECgkJHAAOAIsbAA==.Codeman:BAABLgAECn88AAMZAAkJ7CL/AwD5AgAZAAkJ7CL/AwD5AgAJAAEJEws7bgEyAAAAAA==.Cody:BAAALgADCgcJBwABLgAECgkJPAAZAOwiAA==.Cogne:BAAALgAECgYJCQAAAA==.Cogni:BAAALgAECgYJDAAAAA==.Commiebear:BAACLgAFFH8ZAAMMAAcJpxcFGACrAQAMAAYJuRUFGACrAQANAAUJsBXDFQAMAQAuAAQKf2MAAwwACQl2I6QDAHwDAAwACQl2I6QDAHwDAA0ABgloIekaANUBAAAA.Contemplate:BAAALgAECgMJCAABLgAFFAIJBAABAAAAAA==.Corpsepoker:BAAALgAECgYJCgAAAA==.Corruptz:BAAALgAECgkJGwABLgAFFAEJAQABAAAAAQ==.',
Cr='Crashout:BAAALgAECgUJBQAAAA==.Crúsh:BAAALgAECgEJAQAAAA==.',
Ct='Ctk:BAAALgAECgEJAQAAAA==.',
Cu='Culluh:BAAALgAECgYJBgAAAA==.Cumbo:BAAALgAECgEJAQAAAA==.',
Cy='Cyers:BAABLgAECn8cAAIeAAYJFhzhFwBNAQAeAAYJFhzhFwBNAQAAAA==.',
Cz='Czin:BAABLgAECn81AAMEAAkJeCThAQBcAwAEAAkJeCThAQBcAwAFAAEJkQnBSwAlAAAAAA==.',
['Cï']='Cïel:BAAALgAECgUJBQAAAA==.',
Da='Daimao:BAAALgADCgMJAgAAAA==.Dale:BAAALgADCgMJAwAAAA==.Dalén:BAAALgAECgYJEwAAAA==.Damugly:BAAALgAECgIJAgAAAA==.Darcsides:BAAALgADCgQJCQAAAA==.Darthtater:BAAALgAECgEJAQAAAA==.Dasmuffenman:BAAALgADCgQJBAAAAA==.Dawtz:BAAALgAECgIJAgAAAA==.',
De='Deadasf:BAAALgADCgcJEAAAAA==.Deadstunz:BAAALgAECgYJCQAAAA==.Deathverses:BAACLgAFFH85AAIfAAgJsCZLAAAWAwAfAAgJsCZLAAAWAwAuAAQKfy4AAh8ACQnjJikCAJYDAB8ACQnjJikCAJYDAAAA.Deerslayer:BAAALgAECgcJEAAAAA==.Deezknights:BAAALgAECgUJCAABLgAECgYJDgABAAAAAA==.Delter:BAABLgAECn8UAAIfAAgJuxyFHwAqAgAfAAgJuxyFHwAqAgABLgAECggJFAAfALscAA==.Deltritus:BAACLgAFFH8aAAIOAAcJ8RgaIAD+AQAOAAcJ8RgaIAD+AQAuAAQKfzQAAg4ACQnnI+cIADIDAA4ACQnnI+cIADIDAAEuAAQKCAkUAB8AuxwA.Demaedra:BAAALgAECgMJAwAAAA==.Demoan:BAABLgAECn86AAIgAAkJKSOTAQALAwAgAAkJKSOTAQALAwAAAA==.Demonbiscuit:BAACLgAFFH8GAAIhAAQJ6x3PBwCDAQAhAAQJ6x3PBwCDAQAuAAQKfxoAAiEACAmlJpEEAPwCACEACAmlJpEEAPwCAAAA.Derpydawg:BAAALgAECgEJAQABLgAFFAQJFQAJAHcfAA==.Dethh:BAAALgADCgMJAwAAAA==.Deviancy:BAABLgAECn8XAAMCAAkJdxk9EgB+AgACAAkJdxk9EgB+AgAKAAEJpAWvtwEkAAAAAA==.',
Dh='Dhruven:BAAALgADCggJCAAAAA==.',
Di='Dicoball:BAAALgADCgYJBgAAAA==.Diddyzbuizzy:BAABLgAECn8UAAIQAAYJ0A91VwDQAAAQAAYJ0A91VwDQAAAAAA==.Diese:BAAALgAECgYJCQAAAA==.Dikslapp:BAABLgAECn83AAIhAAkJRiJeBAABAwAhAAkJRiJeBAABAwAAAA==.Dinglebingle:BAAALgAECgEJAgAAAA==.Dipperton:BAAALgAECgEJAQABLgAECgcJFAAYAOkaAA==.Discrespect:BAACLgAFFH8LAAMXAAUJ4xGuJgANAQAXAAQJYBSuJgANAQAHAAEJ8QftMwBBAAAuAAQKfyEABBcACQmaGgUTAEcCABcACQmaGgUTAEcCAAcABAkiCMhcAMAAAAYAAQkfAxyWAB8AAAAA.Distinct:BAAALgAECgkJCQABLgAECgkJOgAgACkjAA==.Distress:BAAALgAFFAIJBAAAAA==.Ditto:BAACLgAFFH8KAAIZAAMJ/xAfKgCiAAAZAAMJ/xAfKgCiAAAuAAQKfzwABBkACAmpHOsMAEECABkACAmpHOsMAEECAAkABwkpC/amAB4BABIAAwlBDt4PAJ4AAAAA.',
Dl='Dlitinaro:BAABLgAECn80AAMJAAkJIyE+IgB8AgAJAAkJBx8+IgB8AgAZAAkJcx67CQB2AgAAAA==.',
Do='Doesgriddy:BAACLgAFFH8JAAMRAAMJoxd9DQAHAQARAAMJoxd9DQAHAQAQAAEJHAnhYwA7AAAuAAQKfxkAAxEACAlwJLYDACADABEACAlwJLYDACADABAAAwlpGjBOAJcAAAAA.Dogecoinsz:BAAALgAECgQJBgABLgAECgcJDwABAAAAAA==.Dollette:BAAALgAECggJBQAAAA==.Donoph:BAABLgAECn88AAMCAAkJ/yOxAgB7AwACAAkJ/yOxAgB7AwAKAAEJQwxpmgEtAAAAAA==.Doomar:BAABLgAECn80AAMDAAkJjSEnGACRAgADAAkJNCEnGACRAgAIAAYJfR8vCADHAQAAAA==.Doomsamdi:BAAALgAECgcJCAABLgAECgkJNAADAI0hAA==.Doomseph:BAAALgAECgEJAQABLgAECgkJNAADAI0hAA==.Dordire:BAAALgAECgYJBgAAAA==.Doreyn:BAAALgADCgQJBAABLgADCgEJAQABAAAAAA==.Dotudown:BAAALgAECgMJAwAAAA==.Dotzilla:BAAALgAECgQJBAAAAA==.',
Dr='Dradin:BAAALgAECgEJAQAAAA==.Dragindznuts:BAABLgAECn8fAAMDAAkJ6AmkcgBUAQADAAkJMAmkcgBUAQAIAAYJ0AfvMQDxAAAAAA==.Dragoisua:BAAALgADCgEJAQAAAA==.Dragonssteel:BAAALgAECgQJCgAAAA==.Dragosh:BAAALgADCgIJAgAAAA==.Drakedonut:BAABLgAECn8hAAMYAAgJSQu+HwAwAQAYAAcJZwq+HwAwAQAQAAYJ9AqdUQDkAAAAAA==.Dreav:BAAALgAECgIJAgAAAA==.Drugar:BAABLgAECn8qAAIOAAgJoA9feQCCAQAOAAgJoA9feQCCAQAAAA==.Druidtyme:BAAALgAECgMJAwAAAA==.Drunkenkhan:BAAALgADCgEJAQAAAA==.Druv:BAACLgAFFH8FAAIEAAIJEx8IFQDCAAAEAAIJEx8IFQDCAAAuAAQKfxYAAgQACAneHbASALkCAAQACAneHbASALkCAAEuAAUUCQk+ABYAzCUA.',
Du='Duloc:BAAALgAECgUJCAAAAA==.Dumbledorc:BAAALgADCgEJAQAAAA==.Durandal:BAAALgAECgUJEwAAAA==.Duskbane:BAAALgAECgUJCgABLgAFFAEJAQABAAAAAA==.',
Dy='Dynabol:BAACLgAFFH8FAAIUAAEJFCRwigBnAAAUAAEJFCRwigBnAAAuAAQKfzUAAxQACQkOJnUCAF8DABQACQl8JXUCAF8DACAACAkhJXMCANQCAAAA.',
['Dë']='Dëåth:BAAALgAECgYJBgAAAA==.',
['Dò']='Dòóm:BAAALgADCgcJDAABLgAFFAQJFQAJAHcfAA==.',
Eb='Eborsisk:BAAALgADCgYJBgAAAA==.',
Ee='Eelane:BAAALgAECgQJDQAAAA==.',
Ef='Effex:BAAALgAECgMJBAAAAA==.',
El='Ell:BAAALgAECgQJBQAAAA==.',
Em='Eminnazen:BAAALgADCgkJDgAAAA==.',
En='Endurall:BAAALgAECggJCQABLgAECgkJQAAiAAEeAA==.',
Es='Eshne:BAAALgADCgEJAQAAAA==.',
Ev='Eveleigh:BAAALgAECgEJAQAAAA==.Everfale:BAAALgAECgIJAwABLgAFFAEJAQABAAAAAQ==.Eviny:BAAALgADCgcJCAAAAA==.',
Ex='Extratylenol:BAAALgADCgcJDgAAAA==.',
Fa='Facerollz:BAAALgAECgQJBwAAAA==.Fahlafflez:BAABLgAECn8yAAIEAAkJIhtdGgAZAgAEAAkJIhtdGgAZAgAAAA==.Fallyandor:BAAALgADCgYJBgAAAA==.Faolsabre:BAABLgAECn8oAAIJAAkJSQwRYgChAQAJAAkJSQwRYgChAQAAAA==.Farkhaz:BAAALgADCgUJBQAAAA==.',
Fe='Felinieron:BAAALgADCgEJAQABLgAECgkJHgATAC0jAA==.Ferrous:BAAALgADCgYJBgAAAA==.',
Fi='Fishinfridge:BAABLgAECn9FAAQeAAkJpxQ0CwAFAgAeAAkJlhQ0CwAFAgAjAAYJVxF9KwD9AAAbAAcJHQZMdADWAAAAAA==.Fizard:BAAALgADCgIJAgAAAA==.',
Fl='Flints:BAAALgADCgEJAQAAAA==.Flloyd:BAABLgAECn8vAAIbAAkJdBltGACAAgAbAAkJdBltGACAAgAAAA==.',
Fo='Folid:BAAALgAECgEJAgAAAA==.Forne:BAAALgAFFAEJAQAAAA==.Foxdk:BAAALgADCgYJBgAAAA==.',
Fr='Friede:BAABLgAECn8kAAICAAkJbB51CgDOAgACAAkJbB51CgDOAgAAAA==.Frostedphyre:BAAALgAECgkJDQAAAA==.',
Fu='Furrywhaco:BAABLgAECn8UAAIjAAkJ+RpjCABlAgAjAAkJ+RpjCABlAgAAAA==.Fuzzyspells:BAAALgAECgYJDAAAAA==.',
Ga='Gaft:BAABLgAECn8ZAAMKAAgJLxv2SwD/AQAKAAYJsB72SwD/AQAVAAYJ7xICIQAJAQAAAA==.Gaftard:BAAALgADCgEJAQAAAA==.Galdrys:BAAALgADCgEJAQAAAA==.Galvaldi:BAAALgAECgEJAQAAAA==.',
Ge='Gero:BAAALgAECgIJAgAAAA==.',
Gh='Ghostbladez:BAABLgAECn8/AAMkAAgJKQonKQBJAQAkAAgJAQgnKQBJAQAlAAYJVAnMFQDNAAAAAA==.',
Gi='Girthmaster:BAAALgADCgcJBwAAAA==.',
Gl='Gleebus:BAAALgADCgEJAQAAAA==.',
Gn='Gnight:BAAALgAECgkJBgAAAA==.',
Go='Gordez:BAAALgADCgYJDwAAAA==.Goththighs:BAABLgAECn8eAAQOAAgJsyQ4HwD4AgAOAAgJniQ4HwD4AgAmAAEJnCZFFQBzAAAnAAEJiSQ/DABrAAABLgAFFAEJBQAUABQkAA==.',
Gr='Gravez:BAAALgAFFAMJAwABLgAFFAEJAQABAAAAAA==.Grawler:BAAALgAECgcJCwAAAA==.Greeny:BAAALgAFFAEJAQAAAA==.Grim:BAAALgAECgEJAQAAAA==.Grissa:BAAALgAECgQJCgABLgAECgcJCQABAAAAAA==.Grumpyhunter:BAAALgAECgcJEAABLgAECgkJOAAOAOsfAA==.',
Gu='Gumgumfury:BAAALgAECgQJDwAAAA==.Gus:BAAALgADCgMJAwAAAA==.',
Ha='Haidies:BAAALgAECgUJDgABLgAFFAQJDQAbALkPAA==.Halzlok:BAABLgAECn8cAAIaAAcJ6Q+5RAAcAQAaAAcJ6Q+5RAAcAQAAAA==.Hammergold:BAAALgAECgEJAQAAAA==.Hammerplz:BAAALgADCgcJBwAAAA==.Hankdalton:BAAALgADCgEJAQAAAA==.Harandy:BAAALgAECgIJAgAAAA==.Harvester:BAAALgADCgUJBgAAAA==.Haylonor:BAAALgADCgIJAgAAAA==.',
He='Healmedaddy:BAAALgADCgUJBQAAAA==.Hebofan:BAAALgAECgQJBQAAAA==.Hellas:BAAALgAECgQJBgABLgAFFAYJHwAFALUkAA==.Herøn:BAAALgAECgUJAQAAAA==.',
Hi='Highglide:BAAALgAECgEJAQABLgAECgcJFAAEACMbAA==.Hitmonchan:BAAALgAECgUJBwABLgAECggJKAAbAAYlAA==.',
Ho='Holybiscuit:BAAALgADCgcJCQABLgAFFAQJBgAhAOsdAA==.Hondacivic:BAAALgAECgEJAQABLgAECgkJJAAkAH0kAA==.',
Hu='Hukowa:BAAALgADCgYJBgAAAA==.Hunterschmax:BAAALgAECggJCQAAAA==.',
Hy='Hycinadra:BAAALgADCgcJFgAAAA==.',
Ia='Iandis:BAAALgADCgYJDwABLgAECgcJHAAFAHwSAA==.',
Ib='Ibuprofen:BAAALgADCgIJAgAAAA==.',
Ic='Iciaalta:BAAALgAECgYJDgAAAA==.',
Ih='Ihot:BAAALgAECgIJBAAAAA==.',
Ik='Ikayhaimahn:BAACLgAFFH8HAAIjAAMJGgyYIgCNAAAjAAMJGgyYIgCNAAAuAAQKfxcAAiMACQlQGIYKADgCACMACQlQGIYKADgCAAAA.',
Im='Imysteriöus:BAABLgAECn8oAAMbAAgJBiW+BgBJAwAbAAgJBiW+BgBJAwAeAAYJHhSJEgCFAQAAAA==.Imæge:BAAALgAECgYJBgAAAA==.',
In='Indicajones:BAAALgAECgYJDwAAAA==.Indipally:BAACLgAFFH8VAAICAAUJQx3oEwCEAQACAAUJQx3oEwCEAQAuAAQKfxcAAgIACAlAHJ0bADcCAAIACAlAHJ0bADcCAAAA.Indishaman:BAAALgAECgYJCwAAAA==.',
Ip='Iphonepromax:BAAALgAECgcJBwABLgAECgkJMgAKADMhAA==.',
Is='Ishamael:BAABLgAECn80AAIGAAkJUxKqIAC+AQAGAAkJUxKqIAC+AQAAAA==.',
Iw='Iwilleatu:BAAALgADCgcJBwAAAA==.Iwillknifeu:BAAALgADCgQJAwAAAA==.',
Ja='Jabronygos:BAACLgAFFH8LAAIYAAQJBhiNAwA5AQAYAAQJBhiNAwA5AQAuAAQKfywAAhgACQkHIm4BAOACABgACQkHIm4BAOACAAAA.Jakett:BAAALgADCgEJAQAAAA==.Jarnroz:BAAALgAECgQJBAABLgAECgUJCgABAAAAAA==.Jaythirian:BAABLgAECn8YAAMoAAcJrQ6JEACUAQAoAAcJrQ6JEACUAQAEAAQJ1gQVgQC5AAAAAA==.',
Je='Jerg:BAACLgAFFH8NAAIbAAQJuQ8AMgDgAAAbAAQJuQ8AMgDgAAAuAAQKfzkAAxsACQlUHtgWAH8CABsACAmfHdgWAH8CABwABwk3FlQtAGsBAAAA.Jessup:BAACLgAFFH8NAAMiAAQJkiFGCAD3AAAiAAQJHh9GCAD3AAAkAAIJuxsTMgCTAAAuAAQKfyoAAyQACQmKIn8EAFADACQACQn8IX8EAFADACIABQl9IQYKAIMBAAAA.',
Jh='Jhara:BAABLgAECn8dAAIOAAcJeBCulgBIAQAOAAcJeBCulgBIAQAAAA==.',
Ju='Juicehead:BAAALgADCgYJBgAAAA==.Junior:BAACLgAFFH8FAAQGAAMJ6g7BJADLAAAGAAMJ6g7BJADLAAAXAAEJiwZoTQA3AAAHAAEJzAiROAAuAAAuAAQKfywABBcACQkQJJ4GAN4CABcACQlNI54GAN4CAAcABQm3IeAdANIBAAYABQnQHGQ1AEABAAEuAAUUBQkTAAwAyiAA.Junnai:BAAALgADCgcJBwAAAA==.Jutai:BAAALgADCgcJDgAAAA==.',
Ka='Kablinkiaa:BAAALgAECggJDgAAAA==.Kaeydun:BAAALgAECgEJAQAAAA==.Kagamie:BAAALgADCgYJCQAAAA==.Kaiola:BAAALgAECgYJCwAAAA==.Kalistria:BAAALgAECgUJBgAAAA==.Kamekazi:BAAALgAECgMJAwAAAA==.Kariva:BAACLgAFFH8GAAIHAAMJTA3SIgCeAAAHAAMJTA3SIgCeAAAuAAQKf0EAAgcACQm4Gi8LALECAAcACQm4Gi8LALECAAAA.Katacemic:BAABLgAECn8mAAIZAAgJiBb/FADDAQAZAAgJiBb/FADDAQABLgAECgkJIgAIAF8KAA==.Katastrophic:BAAALgADCggJEAABLgAECgkJIgAIAF8KAA==.Katazul:BAABLgAECn8iAAMIAAkJXwqrJgArAQADAAkJewckbwBbAQAIAAYJzgqrJgArAQAAAA==.Kaulike:BAAALgADCgIJAgAAAA==.Kayssa:BAAALgAECgUJBQAAAA==.',
Ke='Keelanllan:BAABLgAECn8cAAIhAAkJTAheKQAtAQAhAAkJTAheKQAtAQAAAA==.Keilun:BAEALgAECgcJDAAAAA==.Kertzz:BAAALgADCgcJCAABLgAECgMJAwABAAAAAA==.Kew:BAABLgAECn8aAAIOAAcJLxipWADQAQAOAAcJLxipWADQAQAAAA==.Kewkew:BAAALgADCgcJDAAAAA==.',
Ki='Kiarina:BAAALgADCgYJEQAAAA==.Killerboomy:BAAALgAECgQJBAABLgAECgkJIwARAJ0PAA==.Killinko:BAAALgADCgMJAwAAAA==.Kirsche:BAAALgADCgUJBQABLgAECggJIgAQADURAA==.Kizira:BAAALgADCgMJAwAAAA==.',
Kn='Kneecromance:BAAALgAFFAIJAgAAAA==.Knightxl:BAAALgAECgYJBgAAAA==.',
Ko='Koggmaw:BAAALgAECgcJEAABLgAFFAQJDQAbALkPAA==.Kokuten:BAAALgAECgEJAQABLgAECgkJIAApANgbAA==.Koral:BAAALgAECgYJBgAAAA==.',
Kr='Kralj:BAAALgAECgUJCAAAAA==.',
Ku='Kungfucode:BAAALgAECgEJAQABLgAECgkJPAAZAOwiAA==.Kungfuhealya:BAABLgAECn8hAAMMAAgJcggpWAAJAQAMAAgJcggpWAAJAQANAAEJwQGKvAAYAAAAAA==.Kuraj:BAAALgAECgEJAQAAAA==.Kurisatroll:BAAALgAECgcJAwAAAA==.',
La='Laeral:BAAALgAECgcJEQAAAA==.Landaxx:BAAALgAECgQJBQABLgAECgcJFAAKAPkbAA==.Larrydale:BAABLgAECn8fAAMPAAgJTxwTGQByAgAPAAgJTxwTGQByAgATAAEJqQMDMgAsAAAAAA==.Latex:BAAALgADCgUJBQAAAA==.Laxdan:BAAALgAECgQJBQABLgAECgcJFAAKAPkbAA==.Lazydaze:BAAALgAECgYJCgAAAA==.Lazyriver:BAABLgAECn81AAQJAAkJ/RGnYQCiAQAJAAcJfBCnYQCiAQAZAAkJow30HABvAQASAAEJAABgRQAAAAAAAA==.',
Le='Lea:BAAALgAECgIJAgABLgAECgkJKQAOAFwaAA==.Lemón:BAAALgAECgEJAQAAAA==.Leofrich:BAAALgAECgMJBQAAAA==.Leondis:BAACLgAFFH8HAAIPAAIJcRbQfACWAAAPAAIJcRbQfACWAAAuAAQKfzMAAg8ACQl0IjQIAA0DAA8ACQl0IjQIAA0DAAAA.Leviosa:BAAALgAECgMJAgAAAA==.Lexipriest:BAACLgAFFH8eAAMHAAcJTRjBAwAvAgAHAAcJTRjBAwAvAgAXAAMJiQtgEADHAAAuAAQKf1EAAwcACQlrIT8EAD4DAAcACQlrIT8EAD4DABcACAkzHYcIALUCAAAA.',
Li='Liberation:BAAALgADCgMJAwAAAA==.Lightful:BAAALgAECgQJBAAAAA==.Lildobby:BAAALgADCgQJBAAAAA==.Lilpp:BAAALgAECgIJAgABLgAECgYJDgABAAAAAA==.',
Ll='Llamamamma:BAAALgADCgcJDgABLgAECgEJAQABAAAAAA==.Lloydak:BAAALgAECgkJCgAAAA==.',
Lo='Lobais:BAAALgADCgEJAgABLgAECgcJHAAFAHwSAA==.Lockmonster:BAAALgAECgIJAwAAAA==.Locksteady:BAAALgAECgcJCAAAAA==.Lokii:BAAALgAECgEJAwAAAA==.Lokì:BAAALgADCgMJAwABLgAECgkJNgAUAGUfAA==.Lookalock:BAAALgAECgQJBQAAAA==.Lorp:BAAALgAECgYJBwAAAA==.',
Lu='Luciffer:BAABLgAECn8lAAIUAAgJeB2EKQBcAgAUAAgJeB2EKQBcAgAAAA==.Lumosmaxiima:BAAALgAECgcJCwAAAA==.Lunadesangre:BAAALgAECgEJBAAAAA==.Lunarette:BAAALgAECgMJBQAAAA==.',
Ly='Lydax:BAABLgAECn8UAAIKAAcJ+RtqVwDcAQAKAAcJ+RtqVwDcAQAAAA==.Lylen:BAAALgADCgYJBgAAAA==.',
['Lö']='Lökï:BAAALgAECgEJAQAAAA==.',
Ma='Macet:BAAALgADCgcJBQAAAA==.Madamme:BAABLgAECn8XAAIpAAYJ9xijPwCrAQApAAYJ9xijPwCrAQAAAA==.Madkingzack:BAABLgAECn8fAAMEAAkJQSRIAwA3AwAEAAkJQSRIAwA3AwAoAAEJywaafgAoAAAAAA==.Madpriest:BAAALgAECgQJBQAAAA==.Malgar:BAAALgAECgEJAQAAAA==.Malistavias:BAABLgAECn8bAAMIAAkJZBCbEQApAQADAAkJyws5VgCZAQAIAAYJHxWbEQApAQAAAA==.Mallikii:BAABLgAECn8dAAMbAAkJ0hu9MADoAQAbAAkJ0hu9MADoAQAcAAQJrSMBOABZAQAAAA==.Malnar:BAAALgADCgEJAQAAAA==.Maokui:BAAALgADCgMJAgAAAA==.Maples:BAABLgAECn8gAAIOAAkJ9w3/cQCTAQAOAAkJ9w3/cQCTAQAAAA==.Marigosa:BAABLgAECn8ZAAIOAAkJ9wU2oQA2AQAOAAkJ9wU2oQA2AQAAAA==.Marnolkas:BAAALgAECgEJAQABLgAECgUJDwABAAAAAA==.Mash:BAAALgADCgYJBgAAAA==.Mathan:BAABLgAECn8oAAMKAAkJCx6qGQCoAgAKAAkJCx6qGQCoAgACAAcJ1h7IFQBbAgAAAA==.Mattdemon:BAAALgAECgcJCQAAAA==.Maudib:BAABLgAECn8VAAIjAAgJSRVVJgAcAQAjAAgJSRVVJgAcAQAAAA==.Mawile:BAAALgAECgUJDQAAAA==.',
Me='Meautiful:BAAALgAECgQJBAAAAA==.Medusa:BAAALgAECgUJEwAAAA==.Meesha:BAAALgAECgMJBgAAAA==.Melas:BAAALgADCgYJEgAAAA==.Melinarra:BAABLgAECn8ZAAICAAYJ2RPlNgBwAQACAAYJ2RPlNgBwAQAAAA==.Melmiresa:BAAALgAECgEJAQAAAA==.Mendavo:BAABLgAECn8WAAQIAAgJBA97HABqAQAIAAcJYw57HABqAQADAAUJ/wrlxQDNAAAdAAEJ2hVmLgBBAAAAAA==.Merkxi:BAABLgAECn8tAAITAAkJBiI0AgArAwATAAkJBiI0AgArAwAAAA==.Messe:BAABLgAECn9AAAIiAAkJAR4rAgCqAgAiAAkJAR4rAgCqAgAAAA==.Mestre:BAAALgAECgYJDgAAAA==.Methious:BAABLgAECn8WAAIKAAkJnRg3agCqAQAKAAkJnRg3agCqAQAAAA==.',
Mi='Mikethepally:BAAALgAECgQJBwAAAA==.Minigoober:BAAALgAECgQJBAAAAA==.',
Mo='Mogli:BAAALgAECgQJBAABLgAECgkJNgAUAGUfAA==.Mojokitten:BAAALgADCgcJBgAAAA==.Monkssuck:BAABLgAFFH8ZAAILAAcJuQiuFwBeAQALAAcJuQiuFwBeAQAAAA==.Monktero:BAAALgAECgIJAwAAAA==.Montu:BAAALgAECggJDgAAAA==.Mooawdeeb:BAAALgAECgUJCQAAAA==.Moogyver:BAAALgADCgEJAgAAAA==.Moonrivr:BAAALgAECgUJCAABLgAECgkJNQAJAP0RAA==.Moonsguard:BAAALgADCgcJCgABLgAECgUJFQARAGkTAA==.Moosewillis:BAAALgAECgcJBwAAAA==.Moovit:BAABLgAECn8bAAMZAAYJvQdEOwCiAAAZAAYJvQdEOwCiAAAJAAEJugG/nQEZAAAAAA==.Moox:BAAALgADCgkJAQAAAA==.Mordekaíser:BAAALgAECgIJAQAAAA==.Morgannahkay:BAAALgAECgkJCQAAAA==.Mortja:BAAALgAECgMJAwAAAA==.',
Mu='Mudcrab:BAAALgAECgEJAQAAAA==.Mustards:BAAALgAECgEJAgAAAA==.Musui:BAAALgADCgIJAgAAAA==.',
My='Myströnghand:BAAALgAECgcJBwAAAA==.',
['Må']='Mådd:BAAALgADCgMJAwAAAA==.',
Na='Nagumo:BAABLgAECn8mAAMIAAgJFQTyOQDMAAADAAgJ4wP6qgDsAAAIAAYJYAPyOQDMAAAAAA==.Nahual:BAAALgADCgQJBQAAAA==.Nala:BAABLgAECn8WAAMcAAgJqhGANgA4AQAcAAcJvw6ANgA4AQAbAAQJWBdtbgAJAQABLgAFFAQJDQAbALkPAA==.Nametaken:BAAALgADCgkJEAAAAA==.Narialle:BAACLgAFFH8GAAIQAAMJ9AtHRgCsAAAQAAMJ9AtHRgCsAAAuAAQKfy4AAxAACAklGNE5AEIBABAABwkgF9E5AEIBABEABwllEv8ZADUBAAEuAAUUAwkHACMAGgwA.Nastylock:BAAALgAECgEJAQAAAA==.',
Ne='Nekoya:BAAALgADCgMJAwABLgAECgUJBwABAAAAAA==.Nesaiana:BAAALgAECgMJAwAAAA==.Netharius:BAAALgAECgMJBwABLgAECgQJBAABAAAAAA==.Nevenel:BAAALgADCgEJAQAAAA==.',
Ni='Nibutaguata:BAACLgAFFH8MAAIUAAUJZR0nNABLAQAUAAUJZR0nNABLAQAuAAQKfzQAAxQACQnAJfMAANgDABQACQnAJfMAANgDACAAAQk3FLAyADUAAAAA.Nikhammer:BAAALgAECgMJAwAAAA==.Nitza:BAAALgAECgcJBwAAAA==.Nivan:BAABLgAECn8XAAMKAAgJnAd/uQAPAQAKAAgJBQZ/uQAPAQAVAAEJXxJyTAA4AAAAAA==.Niço:BAACLgAFFH8HAAIPAAMJTxpCVAD2AAAPAAMJTxpCVAD2AAAuAAQKfxUAAg8ACQnPHKkfAEcCAA8ACQnPHKkfAEcCAAAA.',
No='Nodalmu:BAAALgAECgYJCAAAAA==.Noicce:BAABLgAECn8jAAIbAAkJJhs5HgBNAgAbAAkJJhs5HgBNAgAAAA==.Noiceply:BAAALgADCgkJEAAAAA==.Nolifehenry:BAAALgAFFAEJAQAAAQ==.Nordel:BAAALgADCgcJBwAAAA==.Nosaj:BAAALgADCgYJBgAAAA==.Notabu:BAAALgAECgMJAwAAAA==.Notcrims:BAAALgAECgEJAgAAAA==.',
Nu='Nutz:BAAALgAECgkJAgAAAA==.',
['Nï']='Nï:BAAALgAECgEJAQAAAA==.',
Of='Offlyne:BAAALgAECgEJAQAAAA==.',
Oh='Ohntakae:BAAALgAECgUJAgAAAA==.',
Ok='Oksana:BAAALgAECggJEAAAAA==.',
Ol='Ollamh:BAAALgAECgEJAwAAAA==.',
Om='Ombravuota:BAAALgAECgcJEQAAAA==.',
Oo='Oom:BAAALgAECgIJAgAAAA==.',
Or='Oralian:BAABLgAECn8hAAMIAAkJwSMrCwANAgAIAAUJrCMrCwANAgADAAUJhCMLRQD8AQAAAA==.Orcleave:BAABLgAECn8UAAMEAAcJIxuIQwCXAQAEAAYJ3xSIQwCXAQAFAAUJsR6YHgBQAQAAAA==.Orflap:BAAALgAECgEJAgABLgAECgcJFAAEACMbAA==.',
Ov='Ovee:BAAALgADCgcJBgAAAA==.',
Pa='Paboo:BAAALgAECgcJDAAAAA==.Pacmans:BAAALgAECgMJAwAAAA==.Parts:BAAALgAECgYJBgAAAA==.',
Pe='Pea:BAABLgAECn8pAAMOAAkJXBq9NQA/AgAOAAkJXBq9NQA/AgAnAAEJZQkXFQAoAAAAAA==.Perturabo:BAAALgAECgEJAgAAAA==.',
Ph='Phoenyx:BAABLgAECn8YAAMIAAYJOArYHQC2AAAIAAYJOArYHQC2AAADAAUJjQGhDwFWAAAAAA==.',
Pl='Pleb:BAABLgAECn8cAAMPAAcJDx2zJAAqAgAPAAcJDx2zJAAqAgAfAAMJdQuDawCQAAAAAA==.',
Po='Pony:BAAALgAECggJCAABLgAECgkJIAAOAPcNAA==.',
Pr='Prettyfun:BAAALgADCgMJAwAAAA==.',
Pv='Pve:BAAALgAECgYJCAAAAA==.',
['Põ']='Põ:BAAALgAECgMJAwABLgAECgkJKAAKAAseAA==.',
Qu='Quorra:BAAALgAECgMJBAAAAA==.',
Ra='Radnads:BAAALgAECgMJBAAAAA==.Rahzy:BAABLgAECn8rAAIEAAkJcB7DEwCwAgAEAAkJcB7DEwCwAgAAAA==.Rakagar:BAABLgAECn8yAAIKAAkJOh4EIgB8AgAKAAkJOh4EIgB8AgAAAA==.Raktot:BAAALgAECgEJAQAAAA==.Ranko:BAAALgAECgkJBAAAAA==.Rawsushi:BAAALgADCgYJBgAAAA==.',
Re='Reia:BAAALgAFFAMJAwAAAA==.Reignman:BAAALgADCgEJAQAAAA==.Reue:BAACLgAFFH8cAAIMAAcJ9hotDAA1AgAMAAcJ9hotDAA1AgAuAAQKfy8AAgwACQkQIMIQAJYCAAwACQkQIMIQAJYCAAAA.Reyz:BAABLgAECn8ZAAIMAAgJHBWGIQCnAQAMAAgJHBWGIQCnAQAAAA==.Rezyrial:BAAALgAECgEJAQABLgAECgUJBwABAAAAAA==.',
Rh='Rhaegos:BAAALgAECgUJDwAAAA==.Rhux:BAAALgAECgIJAwAAAA==.',
Ri='Rillao:BAAALgADCggJEgAAAA==.',
Ro='Robinavitch:BAAALgADCgEJAQAAAA==.Roblox:BAAALgAECgUJBgAAAA==.Rocketgrab:BAAALgAECgcJDwAAAA==.Rogaldorn:BAAALgADCgEJAQAAAA==.Roid:BAABLgAECn8jAAIEAAYJTCFDKAC5AQAEAAYJTCFDKAC5AQAAAA==.Rotblair:BAAALgADCgIJAgAAAA==.',
Ru='Runswithu:BAAALgADCgUJBQAAAA==.',
Ry='Rythmias:BAAALgAECgUJCgAAAA==.Ryvive:BAAALgADCgkJEQAAAA==.',
['Rè']='Rèd:BAAALgAECgMJBAABLgAFFAUJDQAPAE0eAA==.',
['Rë']='Rëz:BAAALgAECgUJBwAAAA==.',
Sa='Salla:BAAALgAECgQJBQAAAA==.Saltyy:BAAALgAECgIJAgABLgAECgcJFAAEACMbAA==.Sanguindeath:BAAALgADCgEJAQAAAA==.Santaclause:BAAALgADCggJCQAAAA==.',
Sc='Scrapyjack:BAABLgAECn8xAAMhAAkJ1yIoBgDUAgAhAAkJ1yIoBgDUAgAUAAYJUhlkZwBTAQABLgAECgkJNAAJACMhAA==.Scripts:BAAALgAECgYJEQAAAA==.',
Se='Seph:BAAALgAECgIJAgABLgAECgkJIAAOAPcNAA==.',
Sh='Shadowyarrow:BAAALgAECgQJBAAAAA==.Shale:BAACLgAFFH8GAAIRAAMJ6gqfIQCQAAARAAMJ6gqfIQCQAAAuAAQKf1AABBEACQmOGTEIAGoCABEACQmOGTEIAGoCABAACAnHCeY+ACoBABgAAQmNA+YqAB8AAAAA.Shamboo:BAAALgADCgkJEgAAAA==.Shammit:BAAALgADCggJBwAAAA==.Shammydale:BAAALgADCgMJAwABLgAECgcJEwABAAAAAA==.Shammytyme:BAACLgAFFH8FAAIaAAMJ3RaNMADIAAAaAAMJ3RaNMADIAAAuAAQKfxkAAxoABwkKHMgrAJMBABoABwkKHMgrAJMBACkABAnmDFF0AL8AAAAA.Shamyhagar:BAAALgAECggJEAAAAA==.Sharaiya:BAABLgAECn8sAAIbAAkJvgXKagDxAAAbAAkJvgXKagDxAAAAAA==.Sharkmanfive:BAAALgAECgUJBQAAAA==.Shaure:BAAALgAECgUJBQAAAA==.Shearwater:BAAALgAECgYJCQAAAA==.Sheerburst:BAAALgAECgEJAQABLgAECgcJFAAEACMbAA==.Sherp:BAAALgAECgUJBgAAAA==.',
Si='Siantu:BAAALgADCgcJCQAAAA==.Siastraza:BAAALgADCgkJCQAAAA==.Silmeriaa:BAAALgADCggJCAAAAA==.Silversesu:BAABLgAECn8xAAMPAAgJSyIVEgC9AgAPAAgJSyIVEgC9AgAfAAEJJRGYhgA2AAAAAA==.Sioux:BAAALgAECgUJEAAAAA==.',
Sk='Skippybmm:BAAALgAECgQJDQABLgAECgcJHAAFAHwSAA==.Skittlezqt:BAAALgADCgMJAwAAAA==.Skra:BAAALgAECgUJBgABLgAECgkJQAAiAAEeAA==.',
Sl='Sledgehammer:BAAALgADCgUJBQAAAA==.Slid:BAAALgAECgQJBAAAAA==.',
Sm='Smexyshâmmy:BAAALgAECggJDgAAAA==.',
So='Soferus:BAAALgADCggJCAABLgAECgUJDwABAAAAAA==.Solaire:BAACLgAFFH8NAAIVAAUJSRowBgAaAQAVAAUJSRowBgAaAQAuAAQKfy4AAhUACQn+ILkBADMDABUACQn+ILkBADMDAAAA.Sonofalich:BAAALgADCgEJAQAAAA==.Soulflurry:BAABLgAECn8VAAIDAAkJuR4KFQClAgADAAkJuR4KFQClAgABLgAFFAgJJgAUAPoYAA==.Soulful:BAAALgAECgYJBgAAAA==.Souljaz:BAAALgADCgUJBQAAAA==.Soulweaver:BAAALgAECgEJAQABLgAFFAQJDQAbALkPAA==.Sourtofu:BAAALgADCgYJCAAAAA==.',
Sp='Spalduing:BAAALgADCgYJBgAAAA==.Spedboi:BAAALgADCgcJDgAAAA==.Spine:BAABLgAECn8cAAIFAAcJfBL0HgA4AQAFAAcJfBL0HgA4AQAAAA==.Spyy:BAAALgAECgYJCwAAAA==.',
St='Starcast:BAAALgAECgEJAQAAAA==.Starryfire:BAAALgADCgMJAwAAAA==.Starrysky:BAAALgADCgEJAQAAAA==.Starsha:BAAALgAECgEJAQAAAA==.Starßurst:BAAALgAECgEJAQAAAA==.Steezey:BAAALgAECgEJAgAAAA==.Stunny:BAAALgAECgIJAwAAAA==.',
Su='Subzone:BAAALgAECgcJEgAAAA==.Sukas:BAAALgADCgUJBQABLgADCgEJAQABAAAAAA==.Sunmaster:BAAALgAECgQJCgAAAA==.',
Sv='Svecenica:BAAALgADCgYJBgABLgAECgIJAwABAAAAAA==.Svetha:BAABLgAECn9CAAMTAAkJgyL2AQA1AwATAAkJgyL2AQA1AwAfAAcJKBWGFgD+AAAAAA==.',
Sy='Synic:BAAALgADCgYJDgAAAA==.Synora:BAAALgAECgEJAQAAAA==.Syreous:BAAALgADCgMJAwABLgAECgkJPAAgAN0RAA==.',
Ta='Takz:BAAALgAECgEJAgAAAA==.Tandria:BAABLgAECn8hAAMIAAkJ3RdTBQAXAgAIAAkJ3RdTBQAXAgADAAEJlQH8YAEaAAAAAA==.Tankinit:BAAALgAECgQJEgAAAA==.Tanolden:BAAALgAECgUJCQAAAA==.Tanuudrot:BAAALgAECgEJAQABLgAECgUJCgABAAAAAA==.Tatterbone:BAAALgAECgMJAwAAAA==.Tattered:BAAALgADCgEJAQABLgAECgMJAwABAAAAAA==.',
Te='Tenstusî:BAACLgAFFH8GAAIVAAMJswgGBACcAAAVAAMJswgGBACcAAAuAAQKfyUAAhUACAkJHX0GAIACABUACAkJHX0GAIACAAAA.Tenzink:BAABLgAECn8mAAIMAAkJGRyWDwClAgAMAAkJGRyWDwClAgAAAA==.',
Th='Thalon:BAAALgAFFAEJAQABLgAFFAQJDgAJANscAA==.Thathurts:BAAALgADCgcJBwAAAA==.Thatsmyball:BAAALgADCgQJBAAAAA==.Thecoolguy:BAAALgAECgEJAgAAAA==.Thedru:BAABLgAECn9AAAIbAAgJTBByRAB8AQAbAAgJTBByRAB8AQAAAA==.Therodron:BAAALgAECgEJAQAAAA==.Thrastus:BAAALgAECgEJAQAAAA==.Thrus:BAABLgAECn8XAAMNAAgJjBBIKQBtAQANAAgJjBBIKQBtAQAMAAYJqQ46VwAMAQABLgAECgkJQAAiAAEeAA==.Théworld:BAABLgAECn8VAAIRAAUJaROEGwAhAQARAAUJaROEGwAhAQAAAA==.',
Ti='Tindranga:BAAALgAECgQJBAAAAA==.Tip:BAAALgAECgYJBwABLgAECgkJKQAOAFwaAA==.',
Tl='Tlnks:BAAALgADCgQJBwAAAA==.',
To='Toefungus:BAAALgAECgYJCwAAAA==.Tokeon:BAAALgAECgEJAQAAAA==.Touché:BAAALgADCgcJBwAAAA==.Towani:BAACLgAFFH8GAAITAAMJyQ4yHwDYAAATAAMJyQ4yHwDYAAAuAAQKfyUAAhMACQktIEsEAOoCABMACQktIEsEAOoCAAAA.',
Tr='Traler:BAAALgAECgEJAQABLgAECgkJRQAeAKcUAA==.Tralzitashan:BAABLgAECn88AAMmAAkJMhP5AgAGAgAmAAkJMhP5AgAGAgAOAAQJzAMXIgG8AAAAAA==.Trammatize:BAABLgAECn8aAAIOAAcJWhq0ZQAMAgAOAAcJWhq0ZQAMAgAAAA==.Tren:BAAALgADCgMJAwAAAA==.',
Tu='Tubbymuffins:BAAALgAECgEJAQAAAA==.',
Tw='Twohammabray:BAAALgAECgYJCAAAAA==.',
Ty='Tyrdonut:BAAALgAECgEJAQABLgAECggJIQAYAEkLAA==.',
['Tæ']='Tæn:BAAALgADCgMJBAAAAA==.',
Ub='Ubie:BAAALgADCgQJBAAAAA==.',
Uk='Ukonvasara:BAAALgAECgEJAQABLgAECgEJAgABAAAAAA==.',
Um='Umbrà:BAAALgAECgEJAQABLgAECgYJBgABAAAAAA==.',
Un='Undeadnite:BAABLgAECn8WAAMZAAcJLRIlKwD9AAAZAAYJmRElKwD9AAASAAIJDRKVKwBxAAAAAA==.Undertakerz:BAAALgAECgIJAwAAAA==.Unglaus:BAACLgAFFH8JAAIKAAMJpR1aUwADAQAKAAMJpR1aUwADAQAuAAQKfxkAAgoACQnlJIAIACUDAAoACQnlJIAIACUDAAAA.Unglausp:BAACLgAFFH8IAAIGAAMJMxePIgDYAAAGAAMJMxePIgDYAAAuAAQKfycAAgYACAn9HtINAKYCAAYACAn9HtINAKYCAAEuAAUUAwkJAAoApR0A.',
Uz='Uzington:BAACLgAFFH8bAAIFAAUJyxWAFAD3AAAFAAUJyxWAFAD3AAAuAAQKfyYAAgUACQmyHPQIAI8CAAUACQmyHPQIAI8CAAAA.',
Va='Vaanthelos:BAAALgAECgIJAgAAAA==.Valeta:BAAALgAECgEJAgAAAA==.Vali:BAABLgAECn8cAAIDAAcJ9QfopQD1AAADAAcJ9QfopQD1AAAAAA==.Valorien:BAACLgAFFH8QAAIKAAUJ8xx2LQBTAQAKAAUJ8xx2LQBTAQAuAAQKfyEAAgoACAkgG9Y/AAUCAAoACAkgG9Y/AAUCAAAA.Valzlok:BAAALgAECgMJAwAAAA==.',
Ve='Veilthorn:BAAALgAECgQJBAAAAA==.Velinhealion:BAAALgAECgMJAwABLgAECgkJHgATAC0jAA==.Velinieron:BAABLgAECn8eAAITAAkJLSNPBQC8AgATAAkJLSNPBQC8AgAAAA==.Velinvile:BAAALgAECgYJBgABLgAECgkJHgATAC0jAA==.Vellash:BAABLgAECn8cAAIhAAYJxQrlNwDWAAAhAAYJxQrlNwDWAAAAAA==.Vendétta:BAABLgAECn8pAAIPAAkJvRB1RgDKAQAPAAkJvRB1RgDKAQAAAA==.Vengything:BAAALgAECgEJAQAAAA==.',
Vi='Vilandrious:BAABLgAECn8hAAIOAAkJkQkZegCBAQAOAAkJkQkZegCBAQAAAA==.Vince:BAAALgAECgEJAgAAAA==.Virgïl:BAAALgAECgMJAwABLgAECgYJBgABAAAAAA==.',
Vl='Vlper:BAAALgAECgYJEAAAAA==.',
Vo='Voidchild:BAAALgADCggJCQAAAA==.Voidslock:BAAALgAECgEJAQAAAA==.Vonulter:BAABLgAECn8zAAIPAAkJ/RcbIwBUAgAPAAkJ/RcbIwBUAgAAAA==.',
Vy='Vynlandis:BAABLgAECn8+AAMJAAkJ5xicLwA+AgAJAAkJ5xicLwA+AgASAAMJgQSbLQBmAAAAAA==.',
Wa='Wakanda:BAAALgAECgYJDQABLgAFFAQJDQAbALkPAA==.Warbezerker:BAAALgAECgIJAgAAAA==.Wargg:BAAALgAECgYJBgABLgAECgkJHQAhAFsbAA==.Warrything:BAAALgAECgEJAgAAAA==.',
We='Weaknoodle:BAABLgAECn8aAAIGAAcJGhGKMQBUAQAGAAcJGhGKMQBUAQAAAA==.Weenbean:BAABLgAFFH8FAAIQAAMJ8hFWOADiAAAQAAMJ8hFWOADiAAAAAA==.Werebray:BAAALgAFFAMJAwAAAA==.',
Wh='Whaco:BAABLgAECn8fAAIVAAgJmBs3DQDuAQAVAAgJmBs3DQDuAQAAAA==.Whatisaggro:BAABLgAECn8aAAIEAAgJTBq5JQDIAQAEAAgJTBq5JQDIAQAAAA==.Whispertree:BAABLgAECn8vAAIcAAkJ0CEBCADSAgAcAAkJ0CEBCADSAgAAAA==.White:BAAALgAECggJDQABLgAFFAMJBgATACMRAA==.',
Wi='Wilddonut:BAAALgADCgUJBQABLgAECggJIQAYAEkLAA==.Williamld:BAAALgAECgEJAQAAAA==.Wiseguys:BAACLgAFFH8VAAMJAAQJdx/sSQBaAQAJAAQJdx/sSQBaAQASAAIJwRD6HACRAAAuAAQKfysAAwkACQkrIWINAC8DAAkACQkrIWINAC8DABIAAQl9HQwxAFMAAAAA.Wisenhiem:BAAALgADCgMJAwAAAA==.Wixdk:BAABLgAECn8uAAQZAAcJNxnqFADDAQAZAAYJmx3qFADDAQAJAAcJoxJyjQBHAQASAAIJcxhNEgBsAAAAAA==.Wixypoo:BAACLgAFFH8IAAILAAMJOBR0NADRAAALAAMJOBR0NADRAAAuAAQKfzQAAwsACQnoHZALAHkCAAsACQnoHZALAHkCAAwAAQnpATvQABsAAAAA.',
Wo='Wockyslush:BAABLgAECn8kAAIkAAkJfSTpCAADAwAkAAkJfSTpCAADAwAAAA==.Wolfed:BAAALgADCgEJAQAAAA==.Woodnzhood:BAAALgADCgYJFAAAAA==.',
Wr='Wrylah:BAABLgAECn8kAAMQAAkJWhhLGAATAgAQAAkJWhhLGAATAgAYAAYJwAMuKADfAAAAAA==.',
Wu='Wuxian:BAABLgAECn8gAAIpAAkJ2BuBGACCAgApAAkJ2BuBGACCAgAAAA==.',
Wy='Wyyn:BAABLgAECn82AAIOAAkJ1wpAbgCaAQAOAAkJ1wpAbgCaAQAAAA==.',
Xa='Xanboi:BAABLgAECn9DAAMTAAkJ7yQRAgAxAwATAAkJ7yQRAgAxAwAPAAIJ6iK1iwDGAAAAAA==.',
Xe='Xelago:BAAALgAECgMJAwAAAA==.Xexeed:BAAALgADCgcJDgAAAA==.',
Ya='Yaga:BAACLgAFFH8QAAIEAAUJQSDUFgBVAQAEAAUJQSDUFgBVAQAuAAQKfycAAgQACQndIRINAO0CAAQACQndIRINAO0CAAAA.',
Yi='Yikkle:BAAALgADCgIJAQAAAA==.',
Yo='Yona:BAAALgADCgIJAgABLgAECgkJIAAOAPcNAA==.',
Ys='Ysar:BAABLgAECn8dAAIQAAkJag6pKACeAQAQAAkJag6pKACeAQAAAA==.',
Yu='Yujirogojo:BAAALgADCgUJBQAAAA==.Yulan:BAAALgAECggJEAAAAA==.',
Za='Zaddymurph:BAABLgAECn8UAAMYAAcJ6RqJDgDyAQAYAAYJkB+JDgDyAQAQAAYJGxdJIAC/AQAAAA==.Zalter:BAAALgADCgEJAQAAAA==.Zamarched:BAAALgAECgUJCgAAAA==.Zandrama:BAAALgADCggJCAABLgAECggJKQAVACcUAA==.',
Ze='Zeebu:BAABLgAECn8yAAITAAkJlQrpGgDGAQATAAkJlQrpGgDGAQAAAA==.Zenboi:BAABLgAECn8cAAIUAAgJ1RUcQwDnAQAUAAgJ1RUcQwDnAQAAAA==.Zephryyn:BAABLgAECn8ZAAIpAAcJ3gTafQDhAAApAAcJ3gTafQDhAAAAAA==.',
Zh='Zhakareth:BAAALgAECgMJAwABLgAFFAEJAQABAAAAAA==.Zhilan:BAAALgAECgUJEQAAAA==.',
Zi='Ziet:BAAALgADCgMJAwAAAA==.Zinkei:BAAALgAECgYJDQAAAA==.',
Zo='Zoca:BAAALgADCgYJCQAAAA==.Zoda:BAAALgAECgUJBQAAAA==.Zoey:BAAALgAECgYJBgABLgAFFAUJDQAiAJIhAA==.Zoko:BAAALgAFFAEJAQAAAA==.Zophos:BAAALgAECggJDwABLgAECggJFgAIAAQPAA==.',
Zu='Zurgadhunter:BAAALgAECgUJCAAAAA==.Zurgazen:BAAALgAECgIJAwAAAA==.Zuzuk:BAAALgAECggJEwAAAA==.Zuzuki:BAAALgAECgQJBwAAAA==.Zuzukì:BAABLgAECn8UAAIJAAcJ8Q7FjwBDAQAJAAcJ8Q7FjwBDAQAAAA==.',
['Zú']='Zúz:BAABLgAECn8UAAMHAAcJNRkeHgDQAQAHAAYJpxseHgDQAQAGAAYJ7gziRQD1AAAAAA==.',
['Áß']='Áßomination:BAAALgAECgUJCAAAAA==.',
['Ða']='Ðalinar:BAAALgAECgYJCgAAAA==.Ðalinor:BAAALgAECggJCAAAAA==.',
['Ðe']='Ðemaea:BAACLgAFFH8FAAIpAAIJMAIHdABQAAApAAIJMAIHdABQAAAuAAQKfywAAikACQkgDU9NAHcBACkACQkgDU9NAHcBAAAA.',
['Ði']='Ðittø:BAABLgAECn8WAAIOAAkJ3AeAfwB1AQAOAAkJ3AeAfwB1AQABLgAFFAMJCgAZAP8QAA==.',
['Öd']='Ödorodun:BAAALgAECgIJBAAAAA==.',
['Øc']='Øctø:BAAALgAECgQJBAAAAA==.',
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
